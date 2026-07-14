import Foundation

public enum JSONOutput {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static func string<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func data<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}

public enum TextFormat {
    public static func bytes(_ n: UInt64) -> String {
        let kb = 1024.0
        let v = Double(n)
        if v >= kb * kb * kb { return String(format: "%.1f GB", v / (kb * kb * kb)) }
        if v >= kb * kb { return String(format: "%.1f MB", v / (kb * kb)) }
        if v >= kb { return String(format: "%.0f KB", v / kb) }
        return "\(n) B"
    }

    public static func rate(_ bps: Double?) -> String {
        guard let bps else { return "—" }
        return bytes(UInt64(max(0, bps))) + "/s"
    }

    public static func info(_ info: SystemInfo) -> String {
        """
        MasterFabric — System Info
        Model:      \(info.model)
        Identifier: \(info.modelIdentifier)
        Chip:       \(info.chip)
        macOS:      \(info.macOSVersion)
        CPU cores:  \(info.cpuCount)
        Memory:     \(String(format: "%.1f", info.ramGB)) GB
        Uptime:     \(info.uptimeFormatted)
        """
    }

    public static func status(_ status: SystemStatus) -> String {
        let cpu = status.temperature.cpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let gpu = status.temperature.gpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        var lines = [
            "CPU: \(cpu)",
            "GPU: \(gpu)",
        ]
        if status.fans.isEmpty {
            lines.append(L10n.t("fan.na"))
        } else {
            for fan in status.fans {
                let rpm = fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "N/A"
                lines.append("\(fan.name): \(rpm)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func temp(_ t: TemperatureReading) -> String {
        let cpu = t.cpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let gpu = t.gpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        return "CPU: \(cpu)\nGPU: \(gpu)"
    }

    public static func fans(_ fans: [FanReading]) -> String {
        if fans.isEmpty { return L10n.t("fan.na") }
        return fans.map { fan in
            let rpm = fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "N/A"
            return "\(fan.name): \(rpm)"
        }.joined(separator: "\n")
    }

    public static func compactStatusBar(_ status: SystemStatus, load: CPULoadInfo? = nil) -> String {
        let cpu = status.temperature.cpuCelsius.map { String(format: "%.0f°", $0) } ?? "—"
        var parts = ["CPU \(cpu)"]
        if let load {
            parts.append(String(format: "%.0f%%", load.overallPercent))
        }
        if let fan = status.fans.first, let rpm = fan.rpm {
            parts.append("Fan \(Int(rpm))")
        }
        return parts.joined(separator: " · ")
    }

    public static func battery(_ b: BatteryInfo) -> String {
        guard b.isPresent else { return L10n.t("battery.absent") }
        var lines: [String] = []
        if let p = b.percent { lines.append(String(format: "Charge:   %.0f%%", p)) }
        if let c = b.isCharging { lines.append("Charging: \(c ? "yes" : "no")") }
        if let ac = b.isACPowered { lines.append("AC Power: \(ac ? "yes" : "no")") }
        if let cycles = b.cycleCount { lines.append("Cycles:   \(cycles)") }
        if let h = b.healthPercent { lines.append(String(format: "Health:   %.1f%%", h)) }
        if let w = b.watts { lines.append(String(format: "Power:    %.1f W", w)) }
        if let m = b.timeRemainingMinutes {
            lines.append("ETA:      \(m / 60)h \(m % 60)m")
        }
        return lines.joined(separator: "\n")
    }

    public static func memory(_ m: MemoryInfo) -> String {
        """
        Used:       \(bytes(m.usedBytes)) / \(bytes(m.totalBytes)) (\(String(format: "%.1f", m.usedPercent))%)
        Wired:      \(bytes(m.wiredBytes))
        Compressed: \(bytes(m.compressedBytes))
        Swap:       \(bytes(m.swapUsedBytes))
        Pressure:   \(m.pressure)
        """
    }

    public static func disk(_ d: DiskInfo) -> String {
        """
        Volume: \(d.path)
        Used:   \(bytes(d.usedBytes)) / \(bytes(d.totalBytes)) (\(String(format: "%.1f", d.usedPercent))%)
        Free:   \(bytes(d.freeBytes))
        """
    }

    public static func network(_ n: NetworkInfo) -> String {
        if n.interfaces.isEmpty { return "No interfaces" }
        return n.interfaces.map { iface in
            "\(iface.name): ↓ \(rate(iface.bytesInPerSec))  ↑ \(rate(iface.bytesOutPerSec))"
        }.joined(separator: "\n")
    }

    public static func cpuLoad(_ c: CPULoadInfo) -> String {
        var lines = [
            String(format: "Overall: %.1f%%  (user %.1f%% / sys %.1f%% / idle %.1f%%)",
                   c.overallPercent, c.userPercent, c.systemPercent, c.idlePercent),
        ]
        if !c.perCorePercent.isEmpty {
            let cores = c.perCorePercent.enumerated().map { i, v in
                String(format: "  core%02d: %.1f%%", i, v)
            }.joined(separator: "\n")
            lines.append(cores)
        }
        return lines.joined(separator: "\n")
    }

    public static func power(_ p: PowerInfo) -> String {
        """
        Thermal:       \(p.thermalState)
        Low Power Mode:\(p.lowPowerMode ? " on" : " off")
        """
    }

    public static func top(_ list: [ProcessCPUInfo]) -> String {
        var lines = ["PID     CPU%      MEM  NAME"]
        for p in list {
            let mem = bytes(p.memoryBytes)
            let line = String(
                format: "%-6d %6.1f %8@  %@",
                p.pid,
                p.cpuPercent,
                mem as NSString,
                p.name as NSString
            )
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    public static func history(_ h: HistorySnapshot) -> String {
        """
        Samples (1h): \(h.samples.count)
        CPU °C:  \(h.cpuSparkline)
        Load %:  \(h.loadSparkline)
        """
    }

    public static func config(_ c: AppConfig) -> String {
        let s = c.integrations.slack
        let t = c.integrations.telegram
        let m = c.integrations.mail
        return """
        language:              \(c.language)
        launch_at_login:       \(c.launchAtLogin)
        poll_interval_seconds: \(c.pollIntervalSeconds)
        alerts.enabled:        \(c.alerts.enabled)
        alerts.cpu_temp_c:     \(c.alerts.cpuTempCelsius)
        alerts.fan_near_max_%: \(c.alerts.fanNearMaxPercent)
        alerts.memory_notify:  \(c.alerts.memoryPressureNotify)
        slack.enabled:         \(s.enabled)  configured=\(s.isConfigured)
        telegram.enabled:      \(t.enabled)  configured=\(t.isConfigured)
        mail.enabled:          \(m.enabled)  provider=\(m.provider) configured=\(m.isConfigured)
        path: \(ConfigStore.configURL.path)
        """
    }

    public static func notifyResults(_ results: [NotifyDeliveryResult]) -> String {
        if results.isEmpty { return "No deliveries" }
        return results.map { r in
            "\(r.ok ? "✓" : "✗") \(r.channel): \(r.detail)"
        }.joined(separator: "\n")
    }
}
