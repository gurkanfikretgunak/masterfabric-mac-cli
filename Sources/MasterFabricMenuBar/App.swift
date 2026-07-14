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
    @Published var integrations: IntegrationsConfig = ConfigStore.load().integrations
    @Published var lastNotifyMessage: String = ""

    @Published var showAddIntegration = false
    @Published var editingKind: IntegrationKind = .slack

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
        var config = ConfigStore.load()
        config.language = "en"
        alerts = AlertService.evaluate(status: status, memory: memory, config: config)
        integrations = config.integrations
        title = TextFormat.compactStatusBar(status, load: load)
    }

    func openAdd(kind: IntegrationKind? = nil) {
        if let kind {
            editingKind = kind
        } else if let firstMissing = IntegrationKind.allCases.first(where: { !isConfigured($0) }) {
            editingKind = firstMissing
        } else {
            editingKind = .slack
        }
        showAddIntegration = true
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

    func statusLabel(for kind: IntegrationKind) -> String {
        isEnabled(kind) ? "On" : "Off"
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

            IntegrationsSection(model: model)

            if !model.lastNotifyMessage.isEmpty {
                Text(model.lastNotifyMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Refresh") { model.refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
        .sheet(isPresented: $model.showAddIntegration) {
            AddIntegrationSheet(model: model)
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
                    .buttonStyle(.plain)
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

struct AddIntegrationSheet: View {
    @ObservedObject var model: MenuBarModel

    @State private var kind: IntegrationKind = .slack
    @State private var enabled = true

    // Slack
    @State private var webhookURL = ""

    // Telegram
    @State private var botToken = ""
    @State private var chatID = ""

    // Mail
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
                Text("Add integration")
                    .font(.headline)
                Spacer()
                Button(action: close) {
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
                    field("Chat ID", text: $chatID, secure: false)
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
                Button("Cancel", action: close)
                Button("Save") {
                    save()
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            kind = model.editingKind
            if !pickerKinds.contains(kind), let first = pickerKinds.first {
                kind = first
            }
            load(from: kind)
        }
    }

    /// MenuBarExtra sheets often ignore Environment.dismiss on the first click —
    /// drive dismissal via the isPresented binding instead.
    private func close() {
        model.showAddIntegration = false
    }

    /// When adding: only unconfigured channels. When editing an existing one: keep that channel visible.
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
            updated.slack = SlackIntegrationConfig(enabled: enabled, webhookURL: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines))
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
