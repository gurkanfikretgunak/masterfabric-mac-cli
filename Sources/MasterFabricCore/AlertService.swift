import Foundation
import UserNotifications

public enum AlertService {
    private static let notifyLock = NSLock()
    private static var lastNotifyFingerprint: String = ""
    private static var lastNotifyAt: Date = .distantPast

    public static func evaluate(
        status: SystemStatus,
        memory: MemoryInfo,
        disk: DiskInfo = DiskService.current(),
        battery: BatteryInfo = BatteryService.current(),
        power: PowerInfo = PowerService.current(),
        config: AppConfig = ConfigStore.load()
    ) -> [String] {
        guard config.alerts.enabled else { return [] }
        let a = config.alerts
        var messages: [String] = []

        if a.cpuTempEnabled, let cpu = status.temperature.cpuCelsius, cpu >= a.cpuTempCelsius {
            messages.append(
                L10n.t("alert.cpu_hot", config.language, args: [String(format: "%.0f", cpu)])
            )
        }

        if a.gpuTempEnabled, let gpu = status.temperature.gpuCelsius, gpu >= a.gpuTempCelsius {
            messages.append(
                L10n.t("alert.gpu_hot", config.language, args: [String(format: "%.0f", gpu)])
            )
        }

        if a.fanEnabled {
            for fan in status.fans {
                guard let rpm = fan.rpm, let max = fan.maxRPM, max > 0 else { continue }
                let pct = rpm / max * 100
                if pct >= a.fanNearMaxPercent {
                    messages.append(
                        L10n.t("alert.fan_max", config.language, args: [fan.name, String(format: "%.0f", pct)])
                    )
                }
            }
        }

        if a.memoryPressureNotify, memory.pressure == "high" {
            messages.append(L10n.t("alert.memory_high", config.language))
        }

        if a.diskEnabled, disk.usedPercent >= a.diskUsedPercentMax {
            messages.append(
                L10n.t("alert.disk_full", config.language, args: [String(format: "%.0f", disk.usedPercent)])
            )
        }

        if a.batteryEnabled, battery.isPresent, let pct = battery.percent, pct <= a.batteryPercentMin {
            messages.append(
                L10n.t("alert.battery_low", config.language, args: [String(format: "%.0f", pct)])
            )
        }

        if a.lowPowerModeNotify, power.lowPowerMode {
            messages.append(L10n.t("alert.low_power", config.language))
        }

        return messages
    }

    /// Deliver alerts to integrations (and optional macOS banner) with cooldown dedupe.
    @discardableResult
    public static func notifyIfNeeded(
        status: SystemStatus,
        memory: MemoryInfo,
        disk: DiskInfo = DiskService.current(),
        battery: BatteryInfo = BatteryService.current(),
        power: PowerInfo = PowerService.current(),
        config: AppConfig = ConfigStore.load(),
        force: Bool = false
    ) -> [NotifyDeliveryResult] {
        let messages = evaluate(
            status: status,
            memory: memory,
            disk: disk,
            battery: battery,
            power: power,
            config: config
        )
        guard !messages.isEmpty else { return [] }
        guard config.alerts.notifyIntegrations || force else { return [] }

        let fingerprint = messages.joined(separator: "|")
        let cooldown = max(30, config.alerts.notifyCooldownSeconds)

        notifyLock.lock()
        let shouldSend: Bool
        if force {
            shouldSend = true
        } else if fingerprint != lastNotifyFingerprint {
            shouldSend = true
        } else {
            shouldSend = Date().timeIntervalSince(lastNotifyAt) >= cooldown
        }
        if shouldSend {
            lastNotifyFingerprint = fingerprint
            lastNotifyAt = Date()
        }
        notifyLock.unlock()

        guard shouldSend else { return [] }

        let delivered = IntegrationNotifier.deliverAlerts(messages, config: config)

        // Local notification only inside a real .app bundle
        if Bundle.main.bundleIdentifier != nil,
           Bundle.main.bundleURL.pathExtension == "app"
        {
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

        return delivered
    }
}
