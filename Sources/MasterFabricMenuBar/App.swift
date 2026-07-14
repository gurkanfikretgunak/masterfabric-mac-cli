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

enum IntegrationKind: String, CaseIterable, Identifiable {
    case slack = "Slack"
    case telegram = "Telegram"
    case mail = "Mail"

    var id: String { rawValue }

    /// Asset name for official logos (Slack / Telegram). Mail stays vector-drawn.
    var brandImageName: String? {
        switch self {
        case .slack: return "brand-slack"
        case .telegram: return "brand-telegram"
        case .mail: return nil
        }
    }

    var brandCircleColor: Color {
        switch self {
        case .slack: return Color(red: 74 / 255, green: 21 / 255, blue: 75 / 255) // #4A154B
        case .telegram: return Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255) // #229ED9
        case .mail: return Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
        }
    }
}

/// Circle badge using official Slack / Telegram logo assets (Mail stays drawn).
struct IntegrationBrandBadge: View {
    let kind: IntegrationKind
    var size: CGFloat = 22
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let name = kind.brandImageName, let nsImage = BrandAssets.nsImage(named: name) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(kind.brandCircleColor)
                    MailEnvelopeMark()
                        .frame(width: size * 0.58, height: size * 0.58)
                }
                .frame(width: size, height: size)
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityLabel(kind.rawValue)
    }
}

enum BrandAssets {
    /// Resolves SPM `Bundle.module`, installed `.app` Resources, or sibling resource bundle.
    static func nsImage(named name: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        // Installed app: Contents/Resources next to MacOS/
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            exe.deletingLastPathComponent().appendingPathComponent("../Resources/\(name).png"),
            exe.deletingLastPathComponent().appendingPathComponent("\(name).png"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/MasterFabricMenuBar.app/Contents/Resources/\(name).png"),
        ]
        for url in candidates {
            let resolved = url.standardizedFileURL
            if let image = NSImage(contentsOf: resolved) { return image }
        }
        return nil
    }
}

private struct MailEnvelopeMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: max(1.2, w * 0.1))
                    .frame(width: w * 0.92, height: h * 0.68)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.28))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.58))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.28))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.2, w * 0.1), lineCap: .round, lineJoin: .round))
            }
            .frame(width: w, height: h)
        }
    }
}


enum AlertKind: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case fan
    case memory
    case disk
    case battery
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU temp"
        case .gpu: return "GPU temp"
        case .fan: return "Fan speed"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .battery: return "Battery"
        case .power: return "Low power"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "thermometer.medium"
        case .gpu: return "cpu"
        case .fan: return "fanblades"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "bolt.fill"
        }
    }

    var help: String {
        switch self {
        case .cpu: return "High CPU temperature"
        case .gpu: return "High GPU temperature"
        case .fan: return "Fan near max RPM"
        case .memory: return "High memory pressure"
        case .disk: return "Disk nearly full"
        case .battery: return "Low battery"
        case .power: return "Low Power Mode"
        }
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var title: String = "mf…"
    @Published var status: SystemStatus = StatusService.current()
    @Published var info: SystemInfo = SystemInfoService.current()
    @Published var battery: BatteryInfo = BatteryService.current()
    @Published var memory: MemoryInfo = MemoryService.current()
    @Published var disk: DiskInfo = DiskService.current()
    @Published var load: CPULoadInfo = CPULoadService.current()
    @Published var power: PowerInfo = PowerService.current()
    @Published var history: HistorySnapshot = HistoryStore.snapshot()
    @Published var alerts: [String] = []
    @Published var alertConfig: AlertConfig = ConfigStore.load().alerts
    @Published var integrations: IntegrationsConfig = ConfigStore.load().integrations
    @Published var lastNotifyMessage: String = ""

    /// Inline editor (not a sheet — MenuBarExtra sheets need two clicks to dismiss).
    @Published var showAddIntegration = false
    @Published var editingKind: IntegrationKind = .slack
    @Published var editorSession: Int = 0

    @Published var showEditAlert = false
    @Published var editingAlertKind: AlertKind = .cpu
    @Published var alertEditorSession: Int = 0

    /// Inline update prompt (avoid MenuBarExtra `.sheet` dismiss bugs).
    @Published var showUpdateDialog = false
    @Published var pendingUpdate: VersionCheckResult?
    @Published var declinedRemoteVersion: String?
    @Published var isCheckingUpdate = false
    @Published var isUpdating = false

    private var timer: Timer?

    init() {
        refreshMetrics()
        let interval = ConfigStore.load().pollIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: max(1.0, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
            }
        }
    }

    /// Public refresh used by the Refresh button.
    func refresh() {
        refreshMetrics()
    }

    private var isEditingInline: Bool {
        showAddIntegration || showEditAlert || showUpdateDialog
    }

    private func refreshMetrics() {
        // Don't stomp the inline editor while the user is configuring.
        guard !isEditingInline else { return }

        HistoryStore.record()
        status = StatusService.current()
        info = SystemInfoService.current()
        battery = BatteryService.current()
        memory = MemoryService.current()
        disk = DiskService.current()
        _ = CPULoadService.current()
        load = CPULoadService.current()
        power = PowerService.current()
        history = HistoryStore.snapshot()
        var config = ConfigStore.load()
        config.language = "en"
        alertConfig = config.alerts
        alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )
        integrations = config.integrations
        title = TextFormat.compactStatusBar(status, load: load)

        if config.alerts.notifyIntegrations, !alerts.isEmpty {
            let results = AlertService.notifyIfNeeded(
                status: status,
                memory: memory,
                disk: disk,
                battery: battery,
                power: power,
                config: config
            )
            if !results.isEmpty {
                lastNotifyMessage = TextFormat.notifyResults(results)
            }
        }
    }

    func openAdd(kind: IntegrationKind? = nil) {
        showEditAlert = false
        if let kind {
            editingKind = kind
        } else if let firstMissing = IntegrationKind.allCases.first(where: { !isConfigured($0) }) {
            editingKind = firstMissing
        } else {
            editingKind = .slack
        }
        editorSession &+= 1
        showAddIntegration = true
    }

    func openEditAlert(kind: AlertKind) {
        showAddIntegration = false
        editingAlertKind = kind
        alertEditorSession &+= 1
        showEditAlert = true
    }

    func closeEditor() {
        showAddIntegration = false
        showEditAlert = false
        var config = ConfigStore.load()
        config.language = "en"
        alertConfig = config.alerts
        integrations = config.integrations
        alerts = AlertService.evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )
    }

    func isAlertRuleEnabled(_ kind: AlertKind) -> Bool {
        let a = alertConfig
        switch kind {
        case .cpu: return a.cpuTempEnabled
        case .gpu: return a.gpuTempEnabled
        case .fan: return a.fanEnabled
        case .memory: return a.memoryPressureNotify
        case .disk: return a.diskEnabled
        case .battery: return a.batteryEnabled
        case .power: return a.lowPowerModeNotify
        }
    }

    func isAlertActive(_ kind: AlertKind) -> Bool {
        let joined = alerts.joined(separator: " ").lowercased()
        switch kind {
        case .cpu: return joined.contains("cpu")
        case .gpu: return joined.contains("gpu")
        case .fan: return joined.contains("fan") || joined.contains("maximum")
        case .memory: return joined.contains("memory")
        case .disk: return joined.contains("disk")
        case .battery: return joined.contains("battery")
        case .power: return joined.contains("low power")
        }
    }

    func saveAlerts(_ alerts: AlertConfig) {
        var config = ConfigStore.load()
        config.alerts = alerts
        try? ConfigStore.save(config)
        alertConfig = alerts
    }

    func isConfigured(_ kind: IntegrationKind) -> Bool {
        switch kind {
        case .slack: return integrations.slack.isConfigured
        case .telegram: return integrations.telegram.isConfigured
        case .mail: return integrations.mail.isConfigured
        }
    }

    var listedIntegrations: [IntegrationKind] {
        IntegrationKind.allCases.filter { isConfigured($0) }
    }

    var availableToAdd: [IntegrationKind] {
        IntegrationKind.allCases.filter { !isConfigured($0) }
    }

    func isEnabled(_ kind: IntegrationKind) -> Bool {
        switch kind {
        case .slack: return integrations.slack.enabled
        case .telegram: return integrations.telegram.enabled
        case .mail: return integrations.mail.enabled
        }
    }

    func saveIntegrations(_ updated: IntegrationsConfig) {
        var config = ConfigStore.load()
        config.integrations = updated
        do {
            try ConfigStore.save(config)
            integrations = updated
            lastNotifyMessage = "Saved"
        } catch {
            lastNotifyMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func toggle(_ kind: IntegrationKind, enabled: Bool) {
        var updated = integrations
        switch kind {
        case .slack: updated.slack.enabled = enabled
        case .telegram: updated.telegram.enabled = enabled
        case .mail: updated.mail.enabled = enabled
        }
        saveIntegrations(updated)
    }

    func remove(_ kind: IntegrationKind) {
        var updated = integrations
        switch kind {
        case .slack: updated.slack = .default
        case .telegram: updated.telegram = .default
        case .mail: updated.mail = .default
        }
        saveIntegrations(updated)
        lastNotifyMessage = "\(kind.rawValue) removed"
    }

    func test(_ kind: IntegrationKind) {
        let channel: NotifyChannel
        switch kind {
        case .slack: channel = .slack
        case .telegram: channel = .telegram
        case .mail: channel = .mail
        }
        let msg = "MasterFabric menu bar test · \(info.model)"
        let results = IntegrationNotifier.send(msg, channel: channel)
        lastNotifyMessage = TextFormat.notifyResults(results)
    }

    func checkForUpdates(promptIfAvailable: Bool, forcePrompt: Bool = false) {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = VersionService.check()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingUpdate = false
                self.pendingUpdate = result
                if result.updateAvailable {
                    let remote = result.remote ?? ""
                    let alreadyDeclined = self.declinedRemoteVersion == remote
                    if forcePrompt || (promptIfAvailable && !alreadyDeclined) {
                        self.showAddIntegration = false
                        self.showEditAlert = false
                        self.showUpdateDialog = true
                    }
                } else if forcePrompt {
                    self.lastNotifyMessage = VersionService.format(result)
                }
            }
        }
    }

    func declineUpdate() {
        if let remote = pendingUpdate?.remote {
            declinedRemoteVersion = remote
        }
        showUpdateDialog = false
        lastNotifyMessage = "Update declined"
    }

    func acceptUpdate() {
        guard !isUpdating else { return }
        isUpdating = true
        lastNotifyMessage = "Updating from GitHub…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = UpdateService.update(force: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdating = false
                self.showUpdateDialog = false
                self.lastNotifyMessage = UpdateService.format(result)
                if result.performed {
                    self.declinedRemoteVersion = nil
                }
            }
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        Group {
            if model.showUpdateDialog {
                UpdatePromptView(model: model)
            } else if model.showEditAlert {
                EditAlertForm(model: model)
                    .id(model.alertEditorSession)
            } else if model.showAddIntegration {
                AddIntegrationForm(model: model)
                    .id(model.editorSession)
            } else {
                StatusHomeView(model: model)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

struct UpdatePromptView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.orange)
                Text("Update available")
                    .font(.headline)
                Spacer()
                Button {
                    model.declineUpdate()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(model.isUpdating)
            }

            let local = model.pendingUpdate?.local ?? AboutInfo.version
            let remote = model.pendingUpdate?.remote ?? "?"
            Text("A newer open-source release is on GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Installed: v\(local)")
                .font(.callout.monospacedDigit())
            Text("Latest:    v\(remote)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.orange)

            if model.isUpdating {
                Text("Updating from GitHub…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Decline") {
                    model.declineUpdate()
                }
                .disabled(model.isUpdating)
                Spacer()
                Button(model.isUpdating ? "Updating…" : "Update") {
                    model.acceptUpdate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isUpdating)
            }
        }
    }
}

struct StatusHomeView: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MasterFabric")
                        .font(.headline)
                    Text("MacBook system monitor · CLI · Menu Bar · MCP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Refresh metrics")
            }

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

            Divider()

            AlertsSection(model: model)

            if !model.alerts.isEmpty {
                ForEach(model.alerts, id: \.self) { alert in
                    Text(alert)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            IntegrationsSection(model: model)

            if !model.lastNotifyMessage.isEmpty {
                Text(model.lastNotifyMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            AboutSection(model: model)

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}

struct AboutSection: View {
    @ObservedObject var model: MenuBarModel
    @State private var remoteLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("About")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.checkForUpdates(promptIfAvailable: true, forcePrompt: true)
                } label: {
                    Group {
                        if model.isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .help("Check for updates")
                .disabled(model.isCheckingUpdate || model.isUpdating)
            }

            Text("\(AboutInfo.product) v\(AboutInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !remoteLabel.isEmpty {
                Text(remoteLabel)
                    .font(.caption2)
                    .foregroundStyle(remoteLabel.contains("Update") ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                Text("Author")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(AboutInfo.author, destination: URL(string: AboutInfo.authorURL)!)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Text("Company")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("MasterFabric · masterfabric.co", destination: URL(string: AboutInfo.companyURL)!)
                    .font(.caption)
            }

            Text("Open-source company · MIT")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Link("GitHub repo", destination: URL(string: AboutInfo.repoURL)!)
                .font(.caption2)
        }
        .onAppear {
            model.checkForUpdates(promptIfAvailable: true, forcePrompt: false)
            syncLabelFromPending()
        }
        .onChange(of: model.pendingUpdate) { _ in
            syncLabelFromPending()
        }
    }

    private func syncLabelFromPending() {
        guard let result = model.pendingUpdate else { return }
        if let remote = result.remote {
            if result.updateAvailable {
                remoteLabel = "GitHub latest: v\(remote) — Update available"
            } else if VersionService.isRemoteNewer(remote: AboutInfo.version, local: remote) {
                remoteLabel = "GitHub latest: v\(remote) (local ahead)"
            } else {
                remoteLabel = "GitHub latest: v\(remote) — up to date"
            }
        } else {
            remoteLabel = result.detail
        }
    }
}

struct AlertsSection: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Alerts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.alertConfig.enabled },
                    set: { on in
                        var a = model.alertConfig
                        a.enabled = on
                        model.saveAlerts(a)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Master alerts on/off")
            }

            Text("Tap an icon to set thresholds · fires to Integrations")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(AlertKind.allCases) { kind in
                    Button {
                        model.openEditAlert(kind: kind)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(circleFill(for: kind))
                                .frame(width: 32, height: 32)
                            Image(systemName: kind.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(circleForeground(for: kind))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(kind.help)
                }
            }

            Toggle("Send to Integrations", isOn: Binding(
                get: { model.alertConfig.notifyIntegrations },
                set: { on in
                    var a = model.alertConfig
                    a.notifyIntegrations = on
                    model.saveAlerts(a)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .help("When an alert triggers, notify enabled Slack / Telegram / Mail")
        }
    }

    private func circleFill(for kind: AlertKind) -> Color {
        if model.isAlertActive(kind) { return Color.orange.opacity(0.35) }
        if model.isAlertRuleEnabled(kind), model.alertConfig.enabled {
            return Color.accentColor.opacity(0.22)
        }
        return Color.secondary.opacity(0.15)
    }

    private func circleForeground(for kind: AlertKind) -> Color {
        if model.isAlertActive(kind) { return .orange }
        if model.isAlertRuleEnabled(kind), model.alertConfig.enabled { return .primary }
        return .secondary
    }
}

/// Inline alert threshold editor (replaces home view).
struct EditAlertForm: View {
    @ObservedObject var model: MenuBarModel

    @State private var enabled = true
    @State private var threshold = ""
    @State private var feedback = ""

    private var kind: AlertKind { model.editingAlertKind }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.closeEditor()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: kind.symbol)
                    Text(kind.title)
                        .font(.headline)
                }

                Spacer()

                Button {
                    model.closeEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            Text(kind.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enabled", isOn: $enabled)

            if showsThreshold {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thresholdLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(thresholdPlaceholder, text: $threshold)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text(boolOnlyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("When this fires, enabled Integrations (Slack / Telegram / Mail) receive the alert.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !feedback.isEmpty {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { model.closeEditor() }
                Spacer()
                Button("Save") {
                    save()
                    model.closeEditor()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { load() }
    }

    private var showsThreshold: Bool {
        switch kind {
        case .memory, .power: return false
        default: return true
        }
    }

    private var thresholdLabel: String {
        switch kind {
        case .cpu, .gpu: return "Alert when ≥ °C"
        case .fan: return "Alert when fan ≥ % of max RPM"
        case .disk: return "Alert when disk used ≥ %"
        case .battery: return "Alert when battery ≤ %"
        default: return "Threshold"
        }
    }

    private var thresholdPlaceholder: String {
        switch kind {
        case .cpu, .gpu: return "90"
        case .fan: return "95"
        case .disk: return "90"
        case .battery: return "15"
        default: return ""
        }
    }

    private var boolOnlyHint: String {
        switch kind {
        case .memory: return "Triggers when memory pressure is high (system-reported)."
        case .power: return "Triggers when Low Power Mode is on."
        default: return ""
        }
    }

    private func load() {
        let a = model.alertConfig
        switch kind {
        case .cpu:
            enabled = a.cpuTempEnabled
            threshold = String(format: "%.0f", a.cpuTempCelsius)
        case .gpu:
            enabled = a.gpuTempEnabled
            threshold = String(format: "%.0f", a.gpuTempCelsius)
        case .fan:
            enabled = a.fanEnabled
            threshold = String(format: "%.0f", a.fanNearMaxPercent)
        case .memory:
            enabled = a.memoryPressureNotify
            threshold = ""
        case .disk:
            enabled = a.diskEnabled
            threshold = String(format: "%.0f", a.diskUsedPercentMax)
        case .battery:
            enabled = a.batteryEnabled
            threshold = String(format: "%.0f", a.batteryPercentMin)
        case .power:
            enabled = a.lowPowerModeNotify
            threshold = ""
        }
        feedback = ""
    }

    private func save() {
        var a = model.alertConfig
        let value = Double(threshold.trimmingCharacters(in: .whitespacesAndNewlines))
        switch kind {
        case .cpu:
            a.cpuTempEnabled = enabled
            if let value { a.cpuTempCelsius = value }
        case .gpu:
            a.gpuTempEnabled = enabled
            if let value { a.gpuTempCelsius = value }
        case .fan:
            a.fanEnabled = enabled
            if let value { a.fanNearMaxPercent = value }
        case .memory:
            a.memoryPressureNotify = enabled
        case .disk:
            a.diskEnabled = enabled
            if let value { a.diskUsedPercentMax = value }
        case .battery:
            a.batteryEnabled = enabled
            if let value { a.batteryPercentMin = value }
        case .power:
            a.lowPowerModeNotify = enabled
        }
        model.saveAlerts(a)
        feedback = "Saved — Integrations will get this alert when it fires"
    }
}

struct IntegrationsSection: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Integrations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !model.availableToAdd.isEmpty {
                    Button {
                        model.openAdd()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Slack, Telegram, or Mail")
                }
            }

            if model.listedIntegrations.isEmpty {
                Text("No integrations yet — tap + to add")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.listedIntegrations) { kind in
                    HStack(spacing: 8) {
                        IntegrationBrandBadge(
                            kind: kind,
                            size: 24,
                            dimmed: !model.isEnabled(kind)
                        )

                        Toggle(kind.rawValue, isOn: Binding(
                            get: { model.isEnabled(kind) },
                            set: { model.toggle(kind, enabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Spacer(minLength: 0)

                        Button("Edit") { model.openAdd(kind: kind) }
                            .buttonStyle(.borderless)
                            .font(.caption)

                        Button {
                            model.remove(kind)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(kind.rawValue)")
                    }
                }
            }
        }
    }
}

/// Inline form (replaces home view). Avoids MenuBarExtra `.sheet` double-click close bug.
struct AddIntegrationForm: View {
    @ObservedObject var model: MenuBarModel

    @State private var kind: IntegrationKind = .slack
    @State private var enabled = true

    @State private var webhookURL = ""
    @State private var botToken = ""
    @State private var chatID = ""

    @State private var provider = "resend"
    @State private var from = ""
    @State private var to = ""
    @State private var subjectPrefix = "[MasterFabric]"
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var smtpUsername = ""
    @State private var smtpPassword = ""
    @State private var smtpUseTLS = true
    @State private var apiKey = ""
    @State private var mailgunDomain = ""

    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.closeEditor()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()

                HStack(spacing: 6) {
                    IntegrationBrandBadge(kind: kind, size: 20)
                    Text(model.isConfigured(model.editingKind) ? "Edit integration" : "Add integration")
                        .font(.headline)
                }

                Spacer()

                Button {
                    model.closeEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            Picker("Channel", selection: $kind) {
                ForEach(pickerKinds) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pickerKinds.count <= 1)
            .onChange(of: kind) { newValue in
                load(from: newValue)
            }

            Toggle("Enabled", isOn: $enabled)

            Group {
                switch kind {
                case .slack:
                    field("Webhook URL", text: $webhookURL, secure: false)
                case .telegram:
                    field("Bot token", text: $botToken, secure: true)
                    field("Chat ID (numeric example: 123456789 — not @username)", text: $chatID, secure: false)
                case .mail:
                    Picker("Provider", selection: $provider) {
                        Text("Resend").tag("resend")
                        Text("Mailgun").tag("mailgun")
                        Text("SMTP").tag("smtp")
                    }
                    field("From", text: $from, secure: false)
                    field("To", text: $to, secure: false)
                    field("Subject prefix", text: $subjectPrefix, secure: false)
                    if provider == "smtp" {
                        field("SMTP host", text: $smtpHost, secure: false)
                        field("SMTP port", text: $smtpPort, secure: false)
                        field("Username", text: $smtpUsername, secure: false)
                        field("Password", text: $smtpPassword, secure: true)
                        Toggle("Use TLS", isOn: $smtpUseTLS)
                    } else {
                        field("API key", text: $apiKey, secure: true)
                        if provider == "mailgun" {
                            field("Mailgun domain", text: $mailgunDomain, secure: false)
                        }
                    }
                }
            }

            if !feedback.isEmpty {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Test") { test() }
                Spacer()
                Button("Cancel") { model.closeEditor() }
                Button("Save") {
                    save()
                    model.closeEditor()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            kind = model.editingKind
            if !pickerKinds.contains(kind), let first = pickerKinds.first {
                kind = first
            }
            load(from: kind)
        }
    }

    private var pickerKinds: [IntegrationKind] {
        var kinds = model.availableToAdd
        if model.isConfigured(model.editingKind), !kinds.contains(model.editingKind) {
            kinds.insert(model.editingKind, at: 0)
        }
        return IntegrationKind.allCases.filter { kinds.contains($0) }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if secure {
                SecureField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func load(from kind: IntegrationKind) {
        let i = model.integrations
        switch kind {
        case .slack:
            enabled = i.slack.enabled || i.slack.webhookURL.isEmpty
            webhookURL = i.slack.webhookURL
        case .telegram:
            enabled = i.telegram.enabled || i.telegram.botToken.isEmpty
            botToken = i.telegram.botToken
            chatID = i.telegram.chatID
        case .mail:
            enabled = i.mail.enabled || i.mail.from.isEmpty
            provider = i.mail.provider
            from = i.mail.from
            to = i.mail.to
            subjectPrefix = i.mail.subjectPrefix
            smtpHost = i.mail.smtpHost
            smtpPort = String(i.mail.smtpPort)
            smtpUsername = i.mail.smtpUsername
            smtpPassword = i.mail.smtpPassword
            smtpUseTLS = i.mail.smtpUseTLS
            apiKey = i.mail.apiKey
            mailgunDomain = i.mail.mailgunDomain
        }
        feedback = ""
    }

    private func save() {
        var updated = model.integrations
        switch kind {
        case .slack:
            updated.slack = SlackIntegrationConfig(
                enabled: enabled,
                webhookURL: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .telegram:
            updated.telegram = TelegramIntegrationConfig(
                enabled: enabled,
                botToken: botToken.trimmingCharacters(in: .whitespacesAndNewlines),
                chatID: chatID.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .mail:
            updated.mail = MailIntegrationConfig(
                enabled: enabled,
                provider: provider,
                from: from.trimmingCharacters(in: .whitespacesAndNewlines),
                to: to.trimmingCharacters(in: .whitespacesAndNewlines),
                subjectPrefix: subjectPrefix,
                smtpHost: smtpHost.trimmingCharacters(in: .whitespacesAndNewlines),
                smtpPort: Int(smtpPort) ?? 587,
                smtpUsername: smtpUsername,
                smtpPassword: smtpPassword,
                smtpUseTLS: smtpUseTLS,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                mailgunDomain: mailgunDomain.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        model.saveIntegrations(updated)
        feedback = "Saved to config.toml"
    }

    private func test() {
        save()
        model.test(kind)
        feedback = model.lastNotifyMessage
    }
}
