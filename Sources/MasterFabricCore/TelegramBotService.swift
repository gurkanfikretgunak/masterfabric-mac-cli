import Foundation

/// Long-polling Telegram bot that answers with live Mac metrics from MasterFabricCore.
public enum TelegramBotService {
    public struct Options: Sendable {
        public var token: String
        /// If non-empty, only these chat IDs may query the machine.
        public var allowedChatIDs: Set<Int>
        public var pollTimeoutSeconds: Int

        public init(token: String, allowedChatIDs: Set<Int>, pollTimeoutSeconds: Int = 25) {
            self.token = token
            self.allowedChatIDs = allowedChatIDs
            self.pollTimeoutSeconds = pollTimeoutSeconds
        }
    }

    /// Blocking run loop (Ctrl+C to stop).
    public static func run(options: Options, log: (String) -> Void = { line in
        print(line)
        fflush(stdout)
    }) throws {
        let token = options.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw BotError.missingToken
        }

        var offset = 0
        log("MasterFabric Telegram bot listening…")
        if options.allowedChatIDs.isEmpty {
            log("Warning: no allowed chat_id — set integrations.telegram.chat_id first.")
        } else {
            log("Allowed chat_id(s): \(options.allowedChatIDs.sorted().map(String.init).joined(separator: ", "))")
        }
        log("Commands: /status /temp /fan /battery /info /cpu /memory /disk /power /top /check /help")
        log("Leave this process running — the bot only answers while mf bot is up.")

        while true {
            do {
                let updates = try getUpdates(token: token, offset: offset, timeout: options.pollTimeoutSeconds)
                for update in updates {
                    if update.updateID >= offset {
                        offset = update.updateID + 1
                    }
                    guard let message = update.message,
                          let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty
                    else { continue }

                    let chatID = message.chatID
                    log("← [\(chatID)] \(text)")

                    guard options.allowedChatIDs.contains(chatID) else {
                        _ = try? sendMessage(
                            token: token,
                            chatID: chatID,
                            text: "Unauthorized. Your chat_id is \(chatID).\nAdd it with:\nmf config set integrations.telegram.chat_id \"\(chatID)\""
                        )
                        log("→ denied chat_id \(chatID)")
                        continue
                    }

                    let reply = answer(to: text)
                    do {
                        try sendMessage(token: token, chatID: chatID, text: reply)
                        log("→ replied (\(reply.count) chars)")
                    } catch {
                        log("→ send failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                log("poll error: \(error.localizedDescription) — retry in 3s")
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }

    public static func optionsFromConfig(_ config: AppConfig = ConfigStore.load()) throws -> Options {
        let tg = config.integrations.telegram
        let token = tg.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BotError.missingToken }
        var allowed = Set<Int>()
        if let id = Int(tg.chatID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            allowed.insert(id)
        }
        return Options(token: token, allowedChatIDs: allowed)
    }

    public static func answer(to raw: String) -> String {
        let text = raw.lowercased()
        let cmd = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? text

        switch true {
        case cmd == "/start", cmd == "start":
            return welcome()
        case cmd == "/help", cmd == "help", cmd == "yardım", cmd == "yardim":
            return helpText()
        case cmd.hasPrefix("/status"), text.contains("status"), text.contains("durum"):
            return formatStatus()
        case cmd.hasPrefix("/temp"), text.contains("temp"), text.contains("sıcak"), text.contains("sicak"), text.contains("derece"):
            return TextFormat.temp(ThermalService.read())
        case cmd.hasPrefix("/fan"), text.contains("fan"):
            return TextFormat.fans(FanService.read())
        case cmd.hasPrefix("/battery"), cmd.hasPrefix("/bat"), text.contains("battery"), text.contains("pil"), text.contains("şarj"), text.contains("sarj"):
            return TextFormat.battery(BatteryService.current())
        case cmd.hasPrefix("/info"), text.contains("info"), text.contains("bilgi"), text.contains("model"):
            return TextFormat.info(SystemInfoService.current())
        case cmd.hasPrefix("/cpu"), text.contains("cpu"), text.contains("yük"), text.contains("yuk"), text.contains("load"):
            _ = CPULoadService.current()
            Thread.sleep(forTimeInterval: 0.35)
            return TextFormat.cpuLoad(CPULoadService.current())
        case cmd.hasPrefix("/memory"), cmd.hasPrefix("/mem"), text.contains("memory"), text.contains("bellek"), text.contains("ram"):
            return TextFormat.memory(MemoryService.current())
        case cmd.hasPrefix("/disk"), text.contains("disk"):
            return TextFormat.disk(DiskService.current())
        case cmd.hasPrefix("/power"), text.contains("power"), text.contains("thermal"):
            return TextFormat.power(PowerService.current())
        case cmd.hasPrefix("/top"), text.contains("top"), text.contains("process"):
            return TextFormat.top(ProcessService.top(limit: 8))
        case cmd.hasPrefix("/check"), text.contains("alert"), text.contains("uyarı"), text.contains("uyari"):
            let alerts = AlertService.evaluate(
                status: StatusService.current(),
                memory: MemoryService.current()
            )
            return alerts.isEmpty ? "OK — no alerts" : alerts.map { "• \($0)" }.joined(separator: "\n")
        case cmd.hasPrefix("/about"):
            return AboutInfo.text(language: "en")
        default:
            if text.count > 2 {
                return formatStatus() + "\n\n(Tip: /help for commands)"
            }
            return helpText()
        }
    }

    private static func welcome() -> String {
        """
        MasterFabric bot online ✅
        \(SystemInfoService.current().model)

        Ask about this Mac, or use:
        /status /temp /fan /battery /info /cpu /help
        """
    }

    private static func helpText() -> String {
        """
        MasterFabric Telegram commands

        /status   CPU/GPU/fan snapshot
        /temp     Temperatures
        /fan      Fan RPM
        /battery  Battery
        /info     Model / chip / RAM
        /cpu      CPU load
        /memory   Memory pressure
        /disk     Disk free
        /power    Thermal / low power
        /top      Top processes
        /check    Alert thresholds
        /about    Version & links
        /help     This list

        Or ask in plain text (EN/TR), e.g. "fan?" / "pil nasıl?"
        """
    }

    private static func formatStatus() -> String {
        HistoryStore.record()
        let status = StatusService.current()
        _ = CPULoadService.current()
        Thread.sleep(forTimeInterval: 0.25)
        let load = CPULoadService.current()
        let batt = BatteryService.current()
        var parts = [
            TextFormat.status(status),
            "",
            TextFormat.cpuLoad(load),
        ]
        if batt.isPresent, let p = batt.percent {
            parts.append(String(format: "\nBattery: %.0f%%", p))
        }
        return parts.joined(separator: "\n")
    }

    private struct Update {
        var updateID: Int
        var message: IncomingMessage?
    }

    private struct IncomingMessage {
        var chatID: Int
        var text: String?
    }

    private static func getUpdates(token: String, offset: Int, timeout: Int) throws -> [Update] {
        var comps = URLComponents(string: "https://api.telegram.org/bot\(token)/getUpdates")!
        comps.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]"),
        ]
        guard let url = comps.url else { throw BotError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(timeout + 10)
        let (data, response) = try URLSession.shared.botSyncData(for: request, waitSeconds: timeout + 15)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BotError.http(status, body)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["ok"] as? Bool == true,
              let result = obj["result"] as? [[String: Any]]
        else {
            throw BotError.invalidResponse
        }

        return result.compactMap { item in
            guard let updateID = item["update_id"] as? Int else { return nil }
            var message: IncomingMessage?
            if let msg = item["message"] as? [String: Any],
               let chat = msg["chat"] as? [String: Any],
               let chatID = chat["id"] as? Int
            {
                message = IncomingMessage(chatID: chatID, text: msg["text"] as? String)
            }
            return Update(updateID: updateID, message: message)
        }
    }

    @discardableResult
    public static func sendMessage(token: String, chatID: Int, text: String) throws -> Bool {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw BotError.badURL
        }
        let payload: [String: Any] = [
            "chat_id": chatID,
            "text": String(text.prefix(4000)),
            "disable_web_page_preview": true,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30
        let (data, response) = try URLSession.shared.botSyncData(for: request, waitSeconds: 30)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BotError.http(status, body)
        }
        return true
    }

    public enum BotError: Error, LocalizedError {
        case missingToken
        case badURL
        case invalidResponse
        case http(Int, String)

        public var errorDescription: String? {
            switch self {
            case .missingToken: return "Telegram bot_token missing — set integrations.telegram.bot_token"
            case .badURL: return "Invalid Telegram API URL"
            case .invalidResponse: return "Invalid Telegram API response"
            case .http(let code, let body): return "Telegram HTTP \(code): \(body)"
            }
        }
    }
}

extension URLSession {
    fileprivate func botSyncData(for request: URLRequest, waitSeconds: Int) throws -> (Data, URLResponse) {
        let box = BotSyncBox()
        let sem = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }
        task.resume()
        let result = sem.wait(timeout: .now() + .seconds(waitSeconds))
        if result == .timedOut {
            task.cancel()
            throw URLError(.timedOut)
        }
        if let error = box.error { throw error }
        guard let data = box.data, let response = box.response else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

private final class BotSyncBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}
