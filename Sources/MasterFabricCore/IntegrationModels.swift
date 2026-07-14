import Foundation

public struct SlackIntegrationConfig: Sendable, Codable, Equatable {
    public var enabled: Bool
    public var webhookURL: String

    public static let `default` = SlackIntegrationConfig(enabled: false, webhookURL: "")

    public init(enabled: Bool, webhookURL: String) {
        self.enabled = enabled
        self.webhookURL = webhookURL
    }

    public var isConfigured: Bool {
        !webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct TelegramIntegrationConfig: Sendable, Codable, Equatable {
    public var enabled: Bool
    public var botToken: String
    public var chatID: String

    public static let `default` = TelegramIntegrationConfig(enabled: false, botToken: "", chatID: "")

    public init(enabled: Bool, botToken: String, chatID: String) {
        self.enabled = enabled
        self.botToken = botToken
        self.chatID = chatID
    }

    public var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Mail via SMTP or HTTP providers (resend / mailgun).
public struct MailIntegrationConfig: Sendable, Codable, Equatable {
    public var enabled: Bool
    /// `smtp`, `resend`, or `mailgun`
    public var provider: String
    public var from: String
    public var to: String
    public var subjectPrefix: String
    // SMTP
    public var smtpHost: String
    public var smtpPort: Int
    public var smtpUsername: String
    public var smtpPassword: String
    public var smtpUseTLS: Bool
    // HTTP providers
    public var apiKey: String
    public var mailgunDomain: String

    public static let `default` = MailIntegrationConfig(
        enabled: false,
        provider: "smtp",
        from: "",
        to: "",
        subjectPrefix: "[MasterFabric]",
        smtpHost: "",
        smtpPort: 587,
        smtpUsername: "",
        smtpPassword: "",
        smtpUseTLS: true,
        apiKey: "",
        mailgunDomain: ""
    )

    public init(
        enabled: Bool,
        provider: String,
        from: String,
        to: String,
        subjectPrefix: String,
        smtpHost: String,
        smtpPort: Int,
        smtpUsername: String,
        smtpPassword: String,
        smtpUseTLS: Bool,
        apiKey: String,
        mailgunDomain: String
    ) {
        self.enabled = enabled
        self.provider = provider
        self.from = from
        self.to = to
        self.subjectPrefix = subjectPrefix
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpUsername = smtpUsername
        self.smtpPassword = smtpPassword
        self.smtpUseTLS = smtpUseTLS
        self.apiKey = apiKey
        self.mailgunDomain = mailgunDomain
    }

    public var isConfigured: Bool {
        let hasIdentity = !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasIdentity else { return false }
        switch provider.lowercased() {
        case "resend":
            return !apiKey.isEmpty
        case "mailgun":
            return !apiKey.isEmpty && !mailgunDomain.isEmpty
        default:
            return !smtpHost.isEmpty
        }
    }
}

public struct IntegrationsConfig: Sendable, Codable, Equatable {
    public var slack: SlackIntegrationConfig
    public var telegram: TelegramIntegrationConfig
    public var mail: MailIntegrationConfig

    public static let `default` = IntegrationsConfig(
        slack: .default,
        telegram: .default,
        mail: .default
    )

    public init(
        slack: SlackIntegrationConfig,
        telegram: TelegramIntegrationConfig,
        mail: MailIntegrationConfig
    ) {
        self.slack = slack
        self.telegram = telegram
        self.mail = mail
    }

    /// Configured channels in stable order (Slack → Telegram → Mail). Unconfigured are omitted.
    public var listedKinds: [String] {
        var list: [String] = []
        if slack.isConfigured { list.append("slack") }
        if telegram.isConfigured { list.append("telegram") }
        if mail.isConfigured { list.append("mail") }
        return list
    }
}

public enum NotifyChannel: String, CaseIterable, Sendable {
    case slack
    case telegram
    case mail
    case all
}

public struct NotifyDeliveryResult: Sendable, Codable, Equatable {
    public var channel: String
    public var ok: Bool
    public var detail: String

    public init(channel: String, ok: Bool, detail: String) {
        self.channel = channel
        self.ok = ok
        self.detail = detail
    }
}
