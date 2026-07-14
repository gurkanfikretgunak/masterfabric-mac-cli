import Foundation
import Darwin

/// Root LaunchDaemon + Unix-socket fan control so the menu bar only asks for
/// the administrator password once (to install the helper), not on every Auto/Full.
public enum FanDaemon {
    public static let socketPath = "/var/run/com.masterfabric.fan.sock"
    public static let label = "com.masterfabric.fancontrol"
    public static let helperBinary = "/usr/local/libexec/masterfabric-mf"
    public static let plistPath = "/Library/LaunchDaemons/com.masterfabric.fancontrol.plist"

    public struct InstallResult: Sendable {
        public var ok: Bool
        public var detail: String
        public init(ok: Bool, detail: String) {
            self.ok = ok
            self.detail = detail
        }
    }
}

// MARK: - Client

public enum FanDaemonClient {
    public static func isReachable(timeoutSeconds: TimeInterval = 0.4) -> Bool {
        guard let fd = connectSocket(timeoutSeconds: timeoutSeconds) else { return false }
        defer { close(fd) }
        return sendLine(fd, #"{"cmd":"ping"}"#) && (readLine(fd)?.contains("\"ok\":true") == true)
    }

    public static func setMode(_ mode: FanControlMode) -> FanControlResult {
        guard let fd = connectSocket(timeoutSeconds: 1.0) else {
            return FanControlResult(
                ok: false,
                mode: mode,
                detail: "Fan helper not reachable. Open menu bar Auto/Full once to install it.",
                fans: FanService.read(),
                needsPrivilege: true
            )
        }
        defer { close(fd) }

        let payload = #"{"cmd":"set","mode":"\#(mode.rawValue)"}"#
        guard sendLine(fd, payload), let line = readLine(fd), !line.isEmpty else {
            return FanControlResult(
                ok: false,
                mode: mode,
                detail: "No response from fan helper.",
                fans: FanService.read(),
                needsPrivilege: false
            )
        }
        if let decoded = try? JSONDecoder().decode(FanControlResult.self, from: Data(line.utf8)) {
            return decoded
        }
        return FanControlResult(
            ok: false,
            mode: mode,
            detail: "Invalid helper response: \(line)",
            fans: FanService.read()
        )
    }

    private static func fillUnixAddress(_ path: String, _ addr: inout sockaddr_un) {
        addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            path.withCString { cPath in
                let len = min(strlen(cPath), maxLen - 1)
                _ = memcpy(raw.baseAddress, cPath, len)
            }
        }
    }

    private static func connectSocket(timeoutSeconds: TimeInterval) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        fillUnixAddress(FanDaemon.socketPath, &addr)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let ok = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            if ok { return fd }
            Thread.sleep(forTimeInterval: 0.05)
        }
        close(fd)
        return nil
    }

    private static func sendLine(_ fd: Int32, _ line: String) -> Bool {
        let data = Array((line + "\n").utf8)
        var sent = 0
        while sent < data.count {
            let chunk = data.count - sent
            let n: Int = data.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return -1 }
                return write(fd, base.advanced(by: sent), chunk)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    private static func readLine(_ fd: Int32) -> String? {
        var bytes: [UInt8] = []
        var buf: UInt8 = 0
        while bytes.count < 1_000_000 {
            let n = read(fd, &buf, 1)
            if n <= 0 { break }
            if buf == UInt8(ascii: "\n") { break }
            bytes.append(buf)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

// MARK: - Server (root)

public enum FanDaemonServer {
    /// Blocks forever serving fan set/ping requests. Must run as root.
    public static func run() -> Never {
        guard geteuid() == 0 else {
            fputs("mf fan-daemon must run as root (LaunchDaemon).\n", stderr)
            exit(1)
        }

        unlink(FanDaemon.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("fan-daemon: socket() failed\n", stderr)
            exit(1)
        }

        var addr = sockaddr_un()
        FanDaemonClient.fillUnixAddressPublic(FanDaemon.socketPath, &addr)

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard bindOK else {
            fputs("fan-daemon: bind(\(FanDaemon.socketPath)) failed errno=\(errno)\n", stderr)
            exit(1)
        }
        _ = chmod(FanDaemon.socketPath, 0o666)
        guard listen(fd, 8) == 0 else {
            fputs("fan-daemon: listen failed\n", stderr)
            exit(1)
        }

            fputs("masterfabric fan-daemon listening on \(FanDaemon.socketPath)\n", stderr)

        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            handleClient(client)
            close(client)
        }
    }

    private static func handleClient(_ client: Int32) {
        guard let line = FanDaemonClient.readLinePublic(client),
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = obj["cmd"] as? String
        else {
            _ = FanDaemonClient.sendLinePublic(client, #"{"ok":false,"detail":"bad request"}"#)
            return
        }

        switch cmd {
        case "ping":
            _ = FanDaemonClient.sendLinePublic(client, #"{"ok":true}"#)
        case "set":
            let raw = (obj["mode"] as? String) ?? ""
            guard let mode = FanControlMode(rawValue: raw) else {
                _ = FanDaemonClient.sendLinePublic(client, #"{"ok":false,"detail":"mode must be auto|full"}"#)
                return
            }
            let result = FanService.setMode(mode)
            if let encoded = try? JSONEncoder().encode(result),
               let text = String(data: encoded, encoding: .utf8)
            {
                _ = FanDaemonClient.sendLinePublic(client, text)
            } else {
                _ = FanDaemonClient.sendLinePublic(client, #"{"ok":false,"detail":"encode failed"}"#)
            }
        default:
            _ = FanDaemonClient.sendLinePublic(client, #"{"ok":false,"detail":"unknown cmd"}"#)
        }
    }
}

extension FanDaemonClient {
    fileprivate static func readLinePublic(_ fd: Int32) -> String? { readLine(fd) }
    fileprivate static func sendLinePublic(_ fd: Int32, _ line: String) -> Bool { sendLine(fd, line) }
    fileprivate static func fillUnixAddressPublic(_ path: String, _ addr: inout sockaddr_un) {
        fillUnixAddress(path, &addr)
    }
}

// MARK: - One-time installer

public enum FanDaemonInstaller {
    /// Returns true when helper is already running (no password needed).
    public static func isInstalledAndRunning() -> Bool {
        FanDaemonClient.isReachable()
    }

    /// Install / refresh LaunchDaemon with a single admin password prompt.
    public static func installWithAdminPrompt() -> FanDaemon.InstallResult {
        let mf = FanService.resolveMFExecutable()
        guard FileManager.default.isExecutableFile(atPath: mf) else {
            return .init(ok: false, detail: "mf not found at \(mf). Run `make install` first.")
        }

        let plist = launchdPlistXML()
        // Write plist to a temp file the elevated shell can copy (avoids escaping XML in AppleScript).
        let tmpPlist = NSTemporaryDirectory() + "com.masterfabric.fancontrol.plist"
        let tmpScript = NSTemporaryDirectory() + "masterfabric-install-fan-helper.sh"
        do {
            try plist.write(toFile: tmpPlist, atomically: true, encoding: .utf8)
            let scriptBody = """
            #!/bin/bash
            set -euo pipefail
            mkdir -p /usr/local/libexec
            cp -f '\(shellEscape(mf))' '\(FanDaemon.helperBinary)'
            chmod 755 '\(FanDaemon.helperBinary)'
            cp -f '\(shellEscape(tmpPlist))' '\(FanDaemon.plistPath)'
            chmod 644 '\(FanDaemon.plistPath)'
            /bin/launchctl bootout system/\(FanDaemon.label) >/dev/null 2>&1 || true
            /bin/launchctl bootstrap system '\(FanDaemon.plistPath)'
            /bin/launchctl enable system/\(FanDaemon.label) >/dev/null 2>&1 || true
            /bin/launchctl kickstart -k system/\(FanDaemon.label)
            """
            try scriptBody.write(toFile: tmpScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpScript)
        } catch {
            return .init(ok: false, detail: "Could not prepare installer: \(error.localizedDescription)")
        }

        let escapedScript = shellEscape(tmpScript)
        let apple = #"do shell script "'\#(escapedScript)'" with administrator privileges"#
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: apple) else {
            return .init(ok: false, detail: "Could not create admin install script.")
        }
        _ = appleScript.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String)
                ?? "Admin elevation cancelled or failed."
            return .init(ok: false, detail: msg)
        }
        return .init(ok: true, detail: "Fan helper installed (one-time).")
    }

    private static func shellEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func launchdPlistXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(FanDaemon.label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(FanDaemon.helperBinary)</string>
            <string>fan-daemon</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardErrorPath</key>
          <string>/var/log/com.masterfabric.fancontrol.err.log</string>
          <key>StandardOutPath</key>
          <string>/var/log/com.masterfabric.fancontrol.out.log</string>
        </dict>
        </plist>
        """
    }
}

extension FanService {
    /// Menu bar / `--elevate`: talk to root helper; install it once with admin password if needed.
    public static func setModePrivileged(_ mode: FanControlMode) -> FanControlResult {
        if geteuid() == 0 {
            return setMode(mode)
        }
        if FanDaemonClient.isReachable() {
            return FanDaemonClient.setMode(mode)
        }

        let install = FanDaemonInstaller.installWithAdminPrompt()
        guard install.ok else {
            return FanControlResult(
                ok: false,
                mode: mode,
                detail: install.detail,
                fans: read(),
                needsPrivilege: true
            )
        }

        for _ in 0..<60 {
            if FanDaemonClient.isReachable() { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard FanDaemonClient.isReachable() else {
            return FanControlResult(
                ok: false,
                mode: mode,
                detail: "Helper installed but not responding yet. Wait a second and try Auto/Full again (no password).",
                fans: read(),
                needsPrivilege: false
            )
        }

        var result = FanDaemonClient.setMode(mode)
        if result.ok {
            result.detail = "\(result.detail) — helper will not ask for password again."
        }
        return result
    }

    /// Re-run via privileged helper (install once). Kept for call-site compatibility.
    public static func setModeElevated(_ mode: FanControlMode) -> FanControlResult {
        setModePrivileged(mode)
    }

    public static func setMode(_ mode: FanControlMode, elevateIfNeeded: Bool) -> FanControlResult {
        if elevateIfNeeded {
            return setModePrivileged(mode)
        }
        return setMode(mode)
    }
}
