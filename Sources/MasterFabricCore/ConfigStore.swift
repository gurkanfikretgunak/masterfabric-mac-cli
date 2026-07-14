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
            let value = stripQuotes(parts[1])

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
            } else if section == "integrations.slack" {
                switch key {
                case "enabled": config.integrations.slack.enabled = value == "true"
                case "webhook_url": config.integrations.slack.webhookURL = value
                default: break
                }
            } else if section == "integrations.telegram" {
                switch key {
                case "enabled": config.integrations.telegram.enabled = value == "true"
                case "bot_token": config.integrations.telegram.botToken = value
                case "chat_id": config.integrations.telegram.chatID = value
                default: break
                }
            } else if section == "integrations.mail" {
                switch key {
                case "enabled": config.integrations.mail.enabled = value == "true"
                case "provider": config.integrations.mail.provider = value
                case "from": config.integrations.mail.from = value
                case "to": config.integrations.mail.to = value
                case "subject_prefix": config.integrations.mail.subjectPrefix = value
                case "smtp_host": config.integrations.mail.smtpHost = value
                case "smtp_port": config.integrations.mail.smtpPort = Int(value) ?? config.integrations.mail.smtpPort
                case "smtp_username": config.integrations.mail.smtpUsername = value
                case "smtp_password": config.integrations.mail.smtpPassword = value
                case "smtp_use_tls": config.integrations.mail.smtpUseTLS = value == "true"
                case "api_key": config.integrations.mail.apiKey = value
                case "mailgun_domain": config.integrations.mail.mailgunDomain = value
                default: break
                }
            }
        }
        return config
    }

    private static func stripQuotes(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
            v.removeFirst()
            v.removeLast()
            v = v.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return v
    }

    private static func escapeTOML(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func renderTOML(_ config: AppConfig) -> String {
        let s = config.integrations.slack
        let t = config.integrations.telegram
        let m = config.integrations.mail
        return """
        # MasterFabric configuration
        # https://github.com/gurkanfikretgunak/masterfabric-mac-cli

        [general]
        language = "\(escapeTOML(config.language))"
        launch_at_login = \(config.launchAtLogin)
        poll_interval_seconds = \(config.pollIntervalSeconds)

        [alerts]
        enabled = \(config.alerts.enabled)
        cpu_temp_celsius = \(config.alerts.cpuTempCelsius)
        fan_near_max_percent = \(config.alerts.fanNearMaxPercent)
        memory_pressure_notify = \(config.alerts.memoryPressureNotify)

        [integrations.slack]
        enabled = \(s.enabled)
        webhook_url = "\(escapeTOML(s.webhookURL))"

        [integrations.telegram]
        enabled = \(t.enabled)
        bot_token = "\(escapeTOML(t.botToken))"
        chat_id = "\(escapeTOML(t.chatID))"

        [integrations.mail]
        enabled = \(m.enabled)
        provider = "\(escapeTOML(m.provider))"
        from = "\(escapeTOML(m.from))"
        to = "\(escapeTOML(m.to))"
        subject_prefix = "\(escapeTOML(m.subjectPrefix))"
        smtp_host = "\(escapeTOML(m.smtpHost))"
        smtp_port = \(m.smtpPort)
        smtp_username = "\(escapeTOML(m.smtpUsername))"
        smtp_password = "\(escapeTOML(m.smtpPassword))"
        smtp_use_tls = \(m.smtpUseTLS)
        api_key = "\(escapeTOML(m.apiKey))"
        mailgun_domain = "\(escapeTOML(m.mailgunDomain))"
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
