import Foundation

public enum ConfigStore {
    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/masterfabric", isDirectory: true)
    }

    public static var configURL: URL {
        configDirectory.appendingPathComponent("config.toml")
    }

    public static var historyURL: URL {
        configDirectory.appendingPathComponent("history.json")
    }

    public static func load() -> AppConfig {
        ensureDirectory()
        guard let data = try? Data(contentsOf: configURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return .default
        }
        return parseTOML(text)
    }

    public static func save(_ config: AppConfig) throws {
        ensureDirectory()
        let text = renderTOML(config)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    // Minimal TOML for our keys only
    private static func parseTOML(_ text: String) -> AppConfig {
        var config = AppConfig.default
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            if section.isEmpty || section == "general" {
                switch key {
                case "language": config.language = value
                case "launch_at_login": config.launchAtLogin = value == "true"
                case "poll_interval_seconds": config.pollIntervalSeconds = Double(value) ?? config.pollIntervalSeconds
                default: break
                }
            } else if section == "alerts" {
                switch key {
                case "enabled": config.alerts.enabled = value == "true"
                case "cpu_temp_celsius": config.alerts.cpuTempCelsius = Double(value) ?? config.alerts.cpuTempCelsius
                case "fan_near_max_percent": config.alerts.fanNearMaxPercent = Double(value) ?? config.alerts.fanNearMaxPercent
                case "memory_pressure_notify": config.alerts.memoryPressureNotify = value == "true"
                default: break
                }
            }
        }
        return config
    }

    private static func renderTOML(_ config: AppConfig) -> String {
        """
        # MasterFabric configuration
        # https://github.com/gurkanfikretgunak/masterfabric-mac-cli

        [general]
        language = "\(config.language)"
        launch_at_login = \(config.launchAtLogin)
        poll_interval_seconds = \(config.pollIntervalSeconds)

        [alerts]
        enabled = \(config.alerts.enabled)
        cpu_temp_celsius = \(config.alerts.cpuTempCelsius)
        fan_near_max_percent = \(config.alerts.fanNearMaxPercent)
        memory_pressure_notify = \(config.alerts.memoryPressureNotify)
        """
    }
}

public enum LaunchAtLogin {
    private static let label = "com.masterfabric.menubar"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func setEnabled(_ enabled: Bool, executablePath: String) throws {
        if enabled {
            // Prefer launching the .app bundle when available
            let programArguments: String
            let appPath = NSHomeDirectory() + "/.local/MasterFabricMenuBar.app"
            if FileManager.default.fileExists(atPath: appPath) {
                programArguments = """
                      <string>/usr/bin/open</string>
                      <string>-a</string>
                      <string>\(appPath)</string>
                """
            } else {
                programArguments = """
                      <string>\(executablePath)</string>
                """
            }
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>\(label)</string>
              <key>ProgramArguments</key>
              <array>
            \(programArguments)
              </array>
              <key>RunAtLoad</key>
              <true/>
              <key>KeepAlive</key>
              <false/>
            </dict>
            </plist>
            """
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            _ = try? shell(["launchctl", "unload", plistURL.path])
            _ = try? shell(["launchctl", "load", plistURL.path])
        } else {
            _ = try? shell(["launchctl", "unload", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func shell(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
