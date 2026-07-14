import AppKit
import Foundation
import MasterFabricCore
import SwiftUI

/// Renders an English menu-bar panel preview PNG for the README (no Accessibility permission needed).
@main
struct GenerateScreenshot {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let status = StatusService.current()
        let info = SystemInfoService.current()
        let battery = BatteryService.current()
        let memory = MemoryService.current()
        _ = CPULoadService.current()
        Thread.sleep(forTimeInterval: 0.35)
        let load = CPULoadService.current()
        let power = PowerService.current()
        HistoryStore.record()
        let history = HistoryStore.snapshot()

        let view = ScreenshotPanel(
            title: TextFormat.compactStatusBar(status, load: load),
            info: info,
            status: status,
            load: load,
            power: power,
            battery: battery,
            memory: memory,
            history: history
        )
        .padding(20)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("Failed to render PNG\n", stderr)
            exit(1)
        }

        let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots/menubar.png")
        try? FileManager.default.createDirectory(
            at: out.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try png.write(to: out)
            print("Wrote \(out.path)")
        } catch {
            fputs("Write failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

private struct ScreenshotPanel: View {
    let title: String
    let info: SystemInfo
    let status: SystemStatus
    let load: CPULoadInfo
    let power: PowerInfo
    let battery: BatteryInfo
    let memory: MemoryInfo
    let history: HistorySnapshot

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
            .padding(.bottom, 4)

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
