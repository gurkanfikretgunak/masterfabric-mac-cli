import AppKit
import Foundation
import MasterFabricCore
import SwiftUI

/// Renders README screenshots (menu bar panel + CLI) without Accessibility permission.
@main
@MainActor
struct GenerateScreenshot {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let status = StatusService.current()
        let info = SystemInfoService.current()
        let battery = BatteryService.current()
        let memory = MemoryService.current()
        let disk = DiskService.current()
        _ = CPULoadService.current()
        Thread.sleep(forTimeInterval: 0.35)
        let load = CPULoadService.current()
        let power = PowerService.current()
        HistoryStore.record()
        let history = HistoryStore.snapshot()
        var config = ConfigStore.load()
        config.language = "en"
        // Demo UI only — never bake real tokens into PNGs.
        config.integrations.telegram.enabled = true
        config.integrations.telegram.botToken = "demo"
        config.integrations.telegram.chatID = "123456789"
        let alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )

        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        writePNG(
            content: MenuBarShot(
                title: TextFormat.compactStatusBar(status, load: load),
                info: info,
                status: status,
                load: load,
                power: power,
                battery: battery,
                memory: memory,
                history: history,
                alerts: alerts,
                alertConfig: config.alerts,
                integrations: config.integrations
            )
            .padding(20)
            .frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor)),
            to: outDir.appendingPathComponent("menubar.png")
        )

        let cliBody = buildCLITranscript(status: status, info: info, load: load, memory: memory)
        writePNG(
            content: TerminalShot(transcript: cliBody)
                .padding(24)
                .frame(width: 720)
                .background(Color(red: 0.12, green: 0.13, blue: 0.15)),
            to: outDir.appendingPathComponent("cli.png")
        )
    }

    private static func buildCLITranscript(
        status: SystemStatus,
        info: SystemInfo,
        load: CPULoadInfo,
        memory: MemoryInfo
    ) -> String {
        let cpu = status.temperature.cpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let gpu = status.temperature.gpuCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let fan: String = {
            guard let f = status.fans.first, let rpm = f.rpm else { return "N/A" }
            return String(format: "%.0f RPM", rpm)
        }()
        return """
        $ mf status
        CPU \(cpu)  ·  GPU \(gpu)  ·  Fan \(fan)

        $ mf cpu
        Load \(String(format: "%.1f%%", load.overallPercent))

        $ mf memory
        Used \(String(format: "%.0f%%", memory.usedPercent))  ·  pressure \(memory.pressure)

        $ mf notify status
        ✓ telegram: configured · enabled
          (tokens stay in ~/.config — never committed)

        $ mf bot --help
        OVERVIEW: Run interactive bots that answer with live Mac metrics.
        SUBCOMMANDS:
          telegram (default)  Long-poll Telegram with /status /temp /fan …

        $ mf about
        \(AboutInfo.product) v\(AboutInfo.version)
        \(info.model) · \(info.chip)
        Privacy-first · no telemetry · MIT
        """
    }

    @MainActor
    private static func writePNG<V: View>(content: V, to url: URL) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("Failed to render \(url.lastPathComponent)\n", stderr)
            exit(1)
        }
        do {
            try png.write(to: url)
            print("Wrote \(url.path)")
        } catch {
            fputs("Write failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

// MARK: - Menu bar shot (mirrors current panel)

private struct MenuBarShot: View {
    let title: String
    let info: SystemInfo
    let status: SystemStatus
    let load: CPULoadInfo
    let power: PowerInfo
    let battery: BatteryInfo
    let memory: MemoryInfo
    let history: HistorySnapshot
    let alerts: [String]
    let alertConfig: AlertConfig
    let integrations: IntegrationsConfig

    private let alertKinds: [(String, String)] = [
        ("thermometer.medium", "CPU"),
        ("cpu", "GPU"),
        ("fanblades", "Fan"),
        ("memorychip", "Mem"),
        ("internaldrive", "Disk"),
        ("battery.100", "Batt"),
        ("bolt.fill", "Power"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MF")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(title)
                    .font(.system(size: 12, design: .default).monospacedDigit())
                Spacer()
            }
            .padding(.bottom, 2)

            Text("MasterFabric")
                .font(.headline)
            Text("MacBook system monitor · CLI · Menu Bar · MCP")
                .font(.caption2)
                .foregroundStyle(.secondary)

            row("Model", info.model)
            row("Chip", info.chip)

            Divider()

            row("CPU", status.temperature.cpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            row("GPU", status.temperature.gpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            row("Load", String(format: "%.1f%%", load.overallPercent))
            row("Thermal", power.thermalState)

            if status.fans.isEmpty {
                row("Fan", "N/A")
            } else {
                ForEach(Array(status.fans.enumerated()), id: \.offset) { _, fan in
                    row(fan.name, fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "N/A")
                }
            }

            Divider()

            if battery.isPresent {
                row("Battery", battery.percent.map { String(format: "%.0f%%", $0) } ?? "N/A")
            }
            row("Memory", String(format: "%.0f%% · %@", memory.usedPercent, memory.pressure))
            row("CPU hist", history.cpuSparkline)

            Divider()

            HStack {
                Text("Alerts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(alertConfig.enabled ? "On" : "Off")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Tap an icon to set thresholds · fires to Integrations")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Array(alertKinds.enumerated()), id: \.offset) { _, item in
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: 28, height: 28)
                        Image(systemName: item.0)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .help(item.1)
                }
            }

            Text("Send to Integrations  ●")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !alerts.isEmpty {
                ForEach(alerts.prefix(3), id: \.self) { alert in
                    Text(alert)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Text("Integrations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ShotBrandBadge.telegram
                Text("Telegram")
                    .font(.callout)
                Spacer()
                Text("On")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("✓ telegram: ok")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("About")
                .font(.subheadline.weight(.semibold))
            Text("\(AboutInfo.product) v\(AboutInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Author  \(AboutInfo.author)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Text("Refresh                                                          Quit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}

private enum ShotBrandBadge {
    static var telegram: some View {
        logo("brand-telegram")
    }

    static var slack: some View {
        logo("brand-slack")
    }

    private static func logo(_ name: String) -> some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let ns = NSImage(contentsOf: url)
            {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255))
                    .frame(width: 22, height: 22)
            }
        }
    }
}

// MARK: - CLI terminal shot

private struct TerminalShot: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.38, blue: 0.35)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.25)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.19, green: 0.8, blue: 0.35)).frame(width: 10, height: 10)
                Spacer()
                Text("mf — MasterFabric CLI")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35))

            Text(transcript)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.88))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.09, green: 0.1, blue: 0.12))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
