import ArgumentParser
import Foundation
import MasterFabricCore

@main
struct MF: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mf",
        abstract: "MasterFabric — MacBook system monitor (CLI, menu bar, MCP).",
        version: AboutInfo.version,
        subcommands: [
            Info.self,
            Status.self,
            Temp.self,
            Fan.self,
            Battery.self,
            Memory.self,
            Disk.self,
            Network.self,
            CPU.self,
            Power.self,
            Top.self,
            History.self,
            Watch.self,
            Config.self,
            Login.self,
            Check.self,
            Notify.self,
            About.self,
            MenuBar.self,
            MCP.self,
        ],
        defaultSubcommand: Status.self
    )
}

struct JSONFlagOptions: ParsableArguments {
    @Flag(name: .long, help: "Output JSON.")
    var json: Bool = false
}

extension MF {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show Mac model, chip, macOS, RAM, and uptime.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let info = SystemInfoService.current()
            print(format.json ? try JSONOutput.string(info) : TextFormat.info(info))
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show CPU/GPU temperature and fan RPM.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            HistoryStore.record()
            let status = StatusService.current()
            print(format.json ? try JSONOutput.string(status) : TextFormat.status(status))
        }
    }

    struct Temp: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show CPU and GPU temperatures.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let temp = ThermalService.read()
            print(format.json ? try JSONOutput.string(temp) : TextFormat.temp(temp))
        }
    }

    struct Fan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show fan speeds (RPM).")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let fans = FanService.read()
            print(format.json ? try JSONOutput.string(fans) : TextFormat.fans(fans))
        }
    }

    struct Battery: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show battery percent, health, cycles, watts.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let b = BatteryService.current()
            print(format.json ? try JSONOutput.string(b) : TextFormat.battery(b))
        }
    }

    struct Memory: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show memory usage and pressure.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let m = MemoryService.current()
            print(format.json ? try JSONOutput.string(m) : TextFormat.memory(m))
        }
    }

    struct Disk: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show disk capacity for a volume.")
        @OptionGroup var format: JSONFlagOptions
        @Option(name: .shortAndLong, help: "Volume path.")
        var path: String = "/"
        func run() throws {
            let d = DiskService.current(path: path)
            print(format.json ? try JSONOutput.string(d) : TextFormat.disk(d))
        }
    }

    struct Network: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show network interface throughput.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            _ = NetworkService.current()
            Thread.sleep(forTimeInterval: 0.4)
            let n = NetworkService.current()
            print(format.json ? try JSONOutput.string(n) : TextFormat.network(n))
        }
    }

    struct CPU: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cpu",
            abstract: "Show overall and per-core CPU load."
        )
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            _ = CPULoadService.current()
            Thread.sleep(forTimeInterval: 0.35)
            let c = CPULoadService.current()
            print(format.json ? try JSONOutput.string(c) : TextFormat.cpuLoad(c))
        }
    }

    struct Power: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show thermal pressure and low-power mode.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let p = PowerService.current()
            print(format.json ? try JSONOutput.string(p) : TextFormat.power(p))
        }
    }

    struct Top: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show top processes by CPU.")
        @OptionGroup var format: JSONFlagOptions
        @Option(name: .shortAndLong, help: "Number of processes.")
        var limit: Int = 10
        func run() throws {
            let list = ProcessService.top(limit: limit)
            print(format.json ? try JSONOutput.string(list) : TextFormat.top(list))
        }
    }

    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show ~1h CPU/load sparklines.")
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            HistoryStore.record()
            let h = HistoryStore.snapshot()
            print(format.json ? try JSONOutput.string(h) : TextFormat.history(h))
        }
    }

    struct Watch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Live-refresh metrics in the terminal.")
        @Option(name: .shortAndLong, help: "Refresh interval in seconds.")
        var interval: Double = 1.5
        func run() throws {
            let seconds = max(0.5, interval)
            while true {
                print("\u{001B}[2J\u{001B}[H", terminator: "")
                print("MasterFabric watch (Ctrl+C)  \(String(format: "%.1fs", seconds))\n")
                HistoryStore.record()
                let status = StatusService.current()
                _ = CPULoadService.current()
                Thread.sleep(forTimeInterval: 0.2)
                let load = CPULoadService.current()
                let batt = BatteryService.current()
                print(TextFormat.status(status))
                print("")
                print(TextFormat.cpuLoad(load))
                if batt.isPresent, let p = batt.percent {
                    print(String(format: "\nBattery: %.0f%%", p))
                }
                let alerts = AlertService.evaluate(status: status, memory: MemoryService.current())
                if !alerts.isEmpty {
                    print("\nAlerts:")
                    alerts.forEach { print("  • \($0)") }
                }
                print("\nUpdated: \(ISO8601DateFormatter().string(from: Date()))")
                fflush(stdout)
                Thread.sleep(forTimeInterval: max(0.1, seconds - 0.2))
            }
        }
    }

    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or update ~/.config/masterfabric/config.toml",
            subcommands: [Show.self, Init.self, Set.self],
            defaultSubcommand: Show.self
        )

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Print current config.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let c = ConfigStore.load()
                print(format.json ? try JSONOutput.string(c) : TextFormat.config(c))
            }
        }

        struct Init: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Write default config.toml.")
            func run() throws {
                try ConfigStore.save(.default)
                print("Wrote \(ConfigStore.configURL.path)")
            }
        }

        struct Set: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Set a config key.")
            @Argument(help: "Key (language|…|integrations.slack.enabled|integrations.slack.webhook_url|integrations.telegram.*|integrations.mail.*)")
            var key: String
            @Argument(help: "Value")
            var value: String
            func run() throws {
                var c = ConfigStore.load()
                switch key {
                case "language": c.language = value
                case "launch_at_login":
                    c.launchAtLogin = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "poll_interval_seconds":
                    c.pollIntervalSeconds = Double(value) ?? c.pollIntervalSeconds
                case "alerts.enabled":
                    c.alerts.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "alerts.cpu_temp_celsius":
                    c.alerts.cpuTempCelsius = Double(value) ?? c.alerts.cpuTempCelsius
                case "alerts.fan_near_max_percent":
                    c.alerts.fanNearMaxPercent = Double(value) ?? c.alerts.fanNearMaxPercent
                case "alerts.memory_pressure_notify":
                    c.alerts.memoryPressureNotify = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.slack.enabled":
                    c.integrations.slack.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.slack.webhook_url":
                    c.integrations.slack.webhookURL = value
                case "integrations.telegram.enabled":
                    c.integrations.telegram.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.telegram.bot_token":
                    c.integrations.telegram.botToken = value
                case "integrations.telegram.chat_id":
                    c.integrations.telegram.chatID = value
                case "integrations.mail.enabled":
                    c.integrations.mail.enabled = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.mail.provider":
                    c.integrations.mail.provider = value
                case "integrations.mail.from":
                    c.integrations.mail.from = value
                case "integrations.mail.to":
                    c.integrations.mail.to = value
                case "integrations.mail.subject_prefix":
                    c.integrations.mail.subjectPrefix = value
                case "integrations.mail.smtp_host":
                    c.integrations.mail.smtpHost = value
                case "integrations.mail.smtp_port":
                    c.integrations.mail.smtpPort = Int(value) ?? c.integrations.mail.smtpPort
                case "integrations.mail.smtp_username":
                    c.integrations.mail.smtpUsername = value
                case "integrations.mail.smtp_password":
                    c.integrations.mail.smtpPassword = value
                case "integrations.mail.smtp_use_tls":
                    c.integrations.mail.smtpUseTLS = ["1", "true", "yes", "on"].contains(value.lowercased())
                case "integrations.mail.api_key":
                    c.integrations.mail.apiKey = value
                case "integrations.mail.mailgun_domain":
                    c.integrations.mail.mailgunDomain = value
                default:
                    throw ValidationError("Unknown key: \(key)")
                }
                try ConfigStore.save(c)
                if key == "launch_at_login" {
                    let path = menuBarPath()
                    try LaunchAtLogin.setEnabled(c.launchAtLogin, executablePath: path)
                }
                print(TextFormat.config(c))
            }
        }
    }

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enable/disable menu bar launch at login.",
            subcommands: [Enable.self, Disable.self, Status.self],
            defaultSubcommand: Status.self
        )
        struct Enable: ParsableCommand {
            func run() throws {
                var c = ConfigStore.load()
                c.launchAtLogin = true
                try ConfigStore.save(c)
                try LaunchAtLogin.setEnabled(true, executablePath: menuBarPath())
                print("Launch at login enabled → \(menuBarPath())")
            }
        }
        struct Disable: ParsableCommand {
            func run() throws {
                var c = ConfigStore.load()
                c.launchAtLogin = false
                try ConfigStore.save(c)
                try LaunchAtLogin.setEnabled(false, executablePath: menuBarPath())
                print("Launch at login disabled")
            }
        }
        struct Status: ParsableCommand {
            func run() throws {
                print(LaunchAtLogin.isEnabled ? "enabled" : "disabled")
            }
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Evaluate alert thresholds and print warnings.")
        @Flag(name: .long, help: "Deliver via Slack/Telegram/mail (and macOS banner when running as .app).")
        var notify: Bool = false
        @OptionGroup var format: JSONFlagOptions
        func run() throws {
            let status = StatusService.current()
            let memory = MemoryService.current()
            let alerts = AlertService.evaluate(status: status, memory: memory)
            var delivered: [NotifyDeliveryResult] = []
            if notify, !alerts.isEmpty {
                delivered = IntegrationNotifier.deliverAlerts(alerts)
            }
            if format.json {
                struct Payload: Encodable {
                    let alerts: [String]
                    let delivered: [NotifyDeliveryResult]
                }
                print(try JSONOutput.string(Payload(alerts: alerts, delivered: delivered)))
                return
            }
            if alerts.isEmpty {
                print("OK — no alerts")
            } else {
                alerts.forEach { print("• \($0)") }
            }
            if notify {
                print("")
                if alerts.isEmpty {
                    print("Nothing to deliver")
                } else {
                    print(TextFormat.notifyResults(delivered))
                }
            }
        }
    }

    struct Notify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Send a message or test alerts via Slack, Telegram, or mail.",
            subcommands: [Send.self, Test.self, Status.self],
            defaultSubcommand: Status.self
        )

        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show integration configuration status.")
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                let c = ConfigStore.load().integrations
                if format.json {
                    print(try JSONOutput.string(c))
                } else {
                    print("""
                    Slack:    enabled=\(c.slack.enabled) configured=\(c.slack.isConfigured)
                    Telegram: enabled=\(c.telegram.enabled) configured=\(c.telegram.isConfigured)
                    Mail:     enabled=\(c.mail.enabled) provider=\(c.mail.provider) configured=\(c.mail.isConfigured)
                    Config:   \(ConfigStore.configURL.path)
                    """)
                }
            }
        }

        struct Send: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Send a custom message to a channel.")
            @Option(name: .shortAndLong, help: "Channel: slack | telegram | mail | all")
            var channel: String = "all"
            @Argument(help: "Message text")
            var message: String
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                guard let ch = NotifyChannel(rawValue: channel.lowercased()) else {
                    throw ValidationError("channel must be slack, telegram, mail, or all")
                }
                let results = IntegrationNotifier.send(message, channel: ch)
                if format.json {
                    print(try JSONOutput.string(results))
                } else {
                    print(TextFormat.notifyResults(results))
                }
                if results.contains(where: { !$0.ok }) {
                    throw ExitCode.failure
                }
            }
        }

        struct Test: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Send a test message to configured channels.")
            @Option(name: .shortAndLong, help: "Channel: slack | telegram | mail | all")
            var channel: String = "all"
            @OptionGroup var format: JSONFlagOptions
            func run() throws {
                guard let ch = NotifyChannel(rawValue: channel.lowercased()) else {
                    throw ValidationError("channel must be slack, telegram, mail, or all")
                }
                let host = SystemInfoService.current().model
                let msg = "MasterFabric test notification from \(host) at \(ISO8601DateFormatter().string(from: Date()))"
                let results = IntegrationNotifier.send(msg, channel: ch)
                if format.json {
                    print(try JSONOutput.string(results))
                } else {
                    print(TextFormat.notifyResults(results))
                }
                if results.contains(where: { !$0.ok }) {
                    throw ExitCode.failure
                }
            }
        }
    }

    struct About: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Product info, version, privacy.")
        @Option(name: .long, help: "Language override (en|tr).")
        var lang: String?
        func run() throws {
            print(AboutInfo.text(language: lang))
        }
    }

    struct MenuBar: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "menubar",
            abstract: "Launch the MasterFabric menu bar app."
        )
        func run() throws {
            if let app = resolveMenuBarApp() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", app]
                try process.run()
                print("Launched \(app)")
                return
            }
            let path = try resolveMenuBarExecutable()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            try process.run()
            print("Launched MasterFabricMenuBar from \(path)")
        }
    }
}

func menuBarPath() -> String {
    (try? resolveMenuBarExecutable())
        ?? "\(NSHomeDirectory())/.local/MasterFabricMenuBar.app/Contents/MacOS/MasterFabricMenuBar"
}

func resolveMenuBarExecutable() throws -> String {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let candidates = [
        "\(home)/.local/MasterFabricMenuBar.app/Contents/MacOS/MasterFabricMenuBar",
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MasterFabricMenuBar").path,
        ".build/release/MasterFabricMenuBar",
        ".build/debug/MasterFabricMenuBar",
        "/usr/local/bin/MasterFabricMenuBar",
        "\(home)/.local/bin/MasterFabricMenuBar",
    ].compactMap { $0 }

    for path in candidates where fm.isExecutableFile(atPath: path) {
        return path
    }
    throw ValidationError("MasterFabricMenuBar not found. Run `make install`.")
}

func resolveMenuBarApp() -> String? {
    let app = "\(NSHomeDirectory())/.local/MasterFabricMenuBar.app"
    if FileManager.default.fileExists(atPath: app) { return app }
    return nil
}
