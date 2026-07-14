import Foundation

public enum IntegrationNotifier {
    /// Deliver a message to the selected channel(s).
    public static func send(
        _ message: String,
        channel: NotifyChannel = .all,
        config: AppConfig = ConfigStore.load()
    ) -> [NotifyDeliveryResult] {
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return [NotifyDeliveryResult(channel: channel.rawValue, ok: false, detail: "Empty message")]
        }

        var results: [NotifyDeliveryResult] = []
        let targets: [NotifyChannel]
        switch channel {
        case .all: targets = [.slack, .telegram, .mail]
        default: targets = [channel]
        }

        for target in targets {
            switch target {
            case .slack:
                results.append(sendSlack(body, config.integrations.slack))
            case .telegram:
                results.append(sendTelegram(body, config.integrations.telegram))
            case .mail:
                results.append(sendMail(body, config.integrations.mail))
            case .all:
                break
            }
        }
        return results
    }

    /// Push alert lines to all configured integrations.
    public static func deliverAlerts(
        _ messages: [String],
        config: AppConfig = ConfigStore.load()
    ) -> [NotifyDeliveryResult] {
        guard !messages.isEmpty else { return [] }
        let info = SystemInfoService.current()
        let header = "MasterFabric alert · \(info.model)"
        let body = ([header] + messages.map { "• \($0)" }).joined(separator: "\n")
        return send(body, channel: .all, config: config)
    }

    // MARK: - Slack

    private static func sendSlack(_ text: String, _ cfg: SlackIntegrationConfig) -> NotifyDeliveryResult {
        guard cfg.isConfigured else {
            return NotifyDeliveryResult(channel: "slack", ok: false, detail: "Not configured / disabled")
        }
        guard let url = URL(string: cfg.webhookURL) else {
            return NotifyDeliveryResult(channel: "slack", ok: false, detail: "Invalid webhook URL")
        }
        let payload: [String: Any] = [
            "text": text,
            "username": "MasterFabric",
            "icon_emoji": ":thermometer:",
        ]
        do {
            let (status, body) = try httpJSON(url: url, method: "POST", headers: [:], json: payload)
            if (200...299).contains(status) {
                return NotifyDeliveryResult(channel: "slack", ok: true, detail: "ok")
            }
            return NotifyDeliveryResult(channel: "slack", ok: false, detail: "HTTP \(status): \(body)")
        } catch {
            return NotifyDeliveryResult(channel: "slack", ok: false, detail: error.localizedDescription)
        }
    }

    // MARK: - Telegram

    private static func sendTelegram(_ text: String, _ cfg: TelegramIntegrationConfig) -> NotifyDeliveryResult {
        guard cfg.isConfigured else {
            return NotifyDeliveryResult(channel: "telegram", ok: false, detail: "Not configured / disabled")
        }
        let token = cfg.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            return NotifyDeliveryResult(channel: "telegram", ok: false, detail: "Invalid bot token / URL")
        }
        let payload: [String: Any] = [
            "chat_id": cfg.chatID,
            "text": text,
            "disable_web_page_preview": true,
        ]
        do {
            let (status, body) = try httpJSON(url: url, method: "POST", headers: [:], json: payload)
            if (200...299).contains(status) {
                return NotifyDeliveryResult(channel: "telegram", ok: true, detail: "ok")
            }
            return NotifyDeliveryResult(channel: "telegram", ok: false, detail: "HTTP \(status): \(body)")
        } catch {
            return NotifyDeliveryResult(channel: "telegram", ok: false, detail: error.localizedDescription)
        }
    }

    // MARK: - Mail

    private static func sendMail(_ text: String, _ cfg: MailIntegrationConfig) -> NotifyDeliveryResult {
        guard cfg.isConfigured else {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: "Not configured / disabled")
        }
        let subject = "\(cfg.subjectPrefix) alert".trimmingCharacters(in: .whitespaces)
        switch cfg.provider.lowercased() {
        case "resend":
            return sendResend(text, subject: subject, cfg: cfg)
        case "mailgun":
            return sendMailgun(text, subject: subject, cfg: cfg)
        default:
            return sendSMTP(text, subject: subject, cfg: cfg)
        }
    }

    private static func sendResend(_ text: String, subject: String, cfg: MailIntegrationConfig) -> NotifyDeliveryResult {
        guard let url = URL(string: "https://api.resend.com/emails") else {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: "Invalid Resend URL")
        }
        let payload: [String: Any] = [
            "from": cfg.from,
            "to": [cfg.to],
            "subject": subject,
            "text": text,
        ]
        do {
            let (status, body) = try httpJSON(
                url: url,
                method: "POST",
                headers: ["Authorization": "Bearer \(cfg.apiKey)"],
                json: payload
            )
            if (200...299).contains(status) {
                return NotifyDeliveryResult(channel: "mail", ok: true, detail: "resend ok")
            }
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: "HTTP \(status): \(body)")
        } catch {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: error.localizedDescription)
        }
    }

    private static func sendMailgun(_ text: String, subject: String, cfg: MailIntegrationConfig) -> NotifyDeliveryResult {
        let domain = cfg.mailgunDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://api.mailgun.net/v3/\(domain)/messages") else {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: "Invalid Mailgun URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let auth = Data("api:\(cfg.apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "from=\(urlEncode(cfg.from))",
            "to=\(urlEncode(cfg.to))",
            "subject=\(urlEncode(subject))",
            "text=\(urlEncode(text))",
        ].joined(separator: "&")
        request.httpBody = Data(form.utf8)
        do {
            let (data, response) = try URLSession.shared.syncData(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            if (200...299).contains(status) {
                return NotifyDeliveryResult(channel: "mail", ok: true, detail: "mailgun ok")
            }
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: "HTTP \(status): \(body)")
        } catch {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: error.localizedDescription)
        }
    }

    /// SMTP via python3 smtplib (available on macOS developer machines).
    private static func sendSMTP(_ text: String, subject: String, cfg: MailIntegrationConfig) -> NotifyDeliveryResult {
        let script = """
        import smtplib, ssl, sys
        from email.message import EmailMessage
        host = sys.argv[1]
        port = int(sys.argv[2])
        user = sys.argv[3]
        password = sys.argv[4]
        mail_from = sys.argv[5]
        mail_to = sys.argv[6]
        subject = sys.argv[7]
        body = sys.argv[8]
        use_tls = sys.argv[9] == "1"
        msg = EmailMessage()
        msg["From"] = mail_from
        msg["To"] = mail_to
        msg["Subject"] = subject
        msg.set_content(body)
        if use_tls:
            context = ssl.create_default_context()
            with smtplib.SMTP(host, port, timeout=30) as server:
                server.ehlo()
                server.starttls(context=context)
                server.ehlo()
                if user:
                    server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=30) as server:
                if user:
                    server.login(user, password)
                server.send_message(msg)
        print("ok")
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [
            "-c", script,
            cfg.smtpHost,
            String(cfg.smtpPort),
            cfg.smtpUsername,
            cfg.smtpPassword,
            cfg.from,
            cfg.to,
            subject,
            text,
            cfg.smtpUseTLS ? "1" : "0",
        ]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if p.terminationStatus == 0 {
                return NotifyDeliveryResult(channel: "mail", ok: true, detail: "smtp ok")
            }
            let detail = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: detail.isEmpty ? "smtp failed" : detail)
        } catch {
            return NotifyDeliveryResult(channel: "mail", ok: false, detail: error.localizedDescription)
        }
    }

    // MARK: - HTTP helper

    private static func httpJSON(
        url: URL,
        method: String,
        headers: [String: String],
        json: [String: Any]
    ) throws -> (Int, String) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try URLSession.shared.syncData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        return (status, body)
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private extension URLSession {
    func syncData(for request: URLRequest) throws -> (Data, URLResponse) {
        let box = SyncBox()
        let sem = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 30)
        if let error = box.error { throw error }
        guard let data = box.data, let response = box.response else {
            throw URLError(.timedOut)
        }
        return (data, response)
    }
}

private final class SyncBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}
