import Foundation
import UserNotifications

public enum AlertService {
    public static func evaluate(
        status: SystemStatus,
        memory: MemoryInfo,
        config: AppConfig = ConfigStore.load()
    ) -> [String] {
        guard config.alerts.enabled else { return [] }
        var messages: [String] = []

        if let cpu = status.temperature.cpuCelsius, cpu >= config.alerts.cpuTempCelsius {
            messages.append(
                L10n.t("alert.cpu_hot", config.language, args: [String(format: "%.0f", cpu)])
            )
        }

        for fan in status.fans {
            guard let rpm = fan.rpm, let max = fan.maxRPM, max > 0 else { continue }
            let pct = rpm / max * 100
            if pct >= config.alerts.fanNearMaxPercent {
                messages.append(
                    L10n.t("alert.fan_max", config.language, args: [fan.name, String(format: "%.0f", pct)])
                )
            }
        }

        if config.alerts.memoryPressureNotify, memory.pressure == "high" {
            messages.append(L10n.t("alert.memory_high", config.language))
        }

        return messages
    }

    public static func notifyIfNeeded(
        status: SystemStatus,
        memory: MemoryInfo,
        config: AppConfig = ConfigStore.load()
    ) {
        let messages = evaluate(status: status, memory: memory, config: config)
        guard !messages.isEmpty else { return }

        // Remote integrations (Slack / Telegram / mail)
        _ = IntegrationNotifier.deliverAlerts(messages, config: config)

        // Local notification only inside a real .app bundle
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app"
        else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for (i, message) in messages.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "MasterFabric"
                content.body = message
                let req = UNNotificationRequest(
                    identifier: "mf-alert-\(i)-\(Int(Date().timeIntervalSince1970))",
                    content: content,
                    trigger: nil
                )
                center.add(req, withCompletionHandler: nil)
            }
        }
    }
}
