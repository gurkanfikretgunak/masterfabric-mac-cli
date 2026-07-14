import AppKit
import SwiftUI
import MasterFabricCore

@main
struct MasterFabricMenuBarApp: App {
    @StateObject private var model = MenuBarModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            Text(model.title)
                .font(.system(size: 12).monospacedDigit())
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var title: String = "mf…"
    @Published var status: SystemStatus = StatusService.current()
    @Published var info: SystemInfo = SystemInfoService.current()
    @Published var battery: BatteryInfo = BatteryService.current()
    @Published var memory: MemoryInfo = MemoryService.current()
    @Published var load: CPULoadInfo = CPULoadService.current()
    @Published var power: PowerInfo = PowerService.current()
    @Published var history: HistorySnapshot = HistoryStore.snapshot()
    @Published var alerts: [String] = []

    private var timer: Timer?

    init() {
        refresh()
        let interval = ConfigStore.load().pollIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: max(1.0, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        HistoryStore.record()
        status = StatusService.current()
        info = SystemInfoService.current()
        battery = BatteryService.current()
        memory = MemoryService.current()
        _ = CPULoadService.current()
        load = CPULoadService.current()
        power = PowerService.current()
        history = HistoryStore.snapshot()
        // Menu bar UI is English-first regardless of CLI language setting.
        var config = ConfigStore.load()
        config.language = "en"
        alerts = AlertService.evaluate(status: status, memory: memory, config: config)
        title = TextFormat.compactStatusBar(status, load: load)
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MasterFabric")
                .font(.headline)
            Text("MacBook system monitor · CLI · Menu Bar · MCP")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                row("Model", model.info.model)
                row("Chip", model.info.chip)
            }

            Divider()

            row("CPU", model.status.temperature.cpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            row("GPU", model.status.temperature.gpuCelsius.map { String(format: "%.1f °C", $0) } ?? "N/A")
            row("Load", String(format: "%.1f%%", model.load.overallPercent))
            row("Thermal", model.power.thermalState)

            if model.status.fans.isEmpty {
                row("Fan", "N/A")
            } else {
                ForEach(Array(model.status.fans.enumerated()), id: \.offset) { _, fan in
                    row(fan.name, fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "N/A")
                }
            }

            Divider()

            if model.battery.isPresent {
                row("Battery", model.battery.percent.map { String(format: "%.0f%%", $0) } ?? "N/A")
            }
            row("Memory", String(format: "%.0f%% · %@", model.memory.usedPercent, model.memory.pressure))
            row("CPU hist", model.history.cpuSparkline)

            if !model.alerts.isEmpty {
                Divider()
                ForEach(model.alerts, id: \.self) { alert in
                    Text(alert)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            Button("Refresh") { model.refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}
