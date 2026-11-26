import Foundation
import Security

/// Permissions the owner granted once, kept across sessions and projects (global by the owner's choice).
enum PermissionStore {
    struct Grant: Codable { var id: String; var scope: String; var note: String; var via: String; var time: String }
    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Boterm/permissions.json") }

    static func scope(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value.count <= 200, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || mobileHidden($0) }) else {
            throw ControlError.invalid("Invalid scope (1–200 characters, one line)")
        }
        return value
    }
    static func all(at file: URL = file) -> [Grant] {
        (try? JSONDecoder().decode([Grant].self, from: Data(contentsOf: file))) ?? []
    }
    static func granted(_ scope: String, at file: URL = file) -> Grant? {
        guard let scope = try? Self.scope(scope) else { return nil }
        return all(at: file).first { $0.scope == scope }
    }
    @discardableResult static func add(scope raw: String, note: String, via: String, at file: URL = file) throws -> Grant {
        let scope = try Self.scope(raw)
        let grant = Grant(id: String(UUID().uuidString.prefix(8)).lowercased(), scope: scope, note: String(note.prefix(500)), via: via, time: ISO8601DateFormatter().string(from: Date()))
        try save(all(at: file).filter { $0.scope != scope } + [grant], at: file)
        return grant
    }
    static func revoke(_ id: String, at file: URL = file) throws { try save(all(at: file).filter { $0.id != id }, at: file) }
    private static func save(_ grants: [Grant], at file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(grants).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func dictionary(_ grant: Grant) -> [String: Any] { ["id": grant.id, "scope": grant.scope, "note": grant.note, "via": grant.via, "time": grant.time] }
}

/// The bot token lives only in the login Keychain; it is never shown, logged or handed to agents.
enum TelegramKeychain {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.danyalgil.boterm.telegram", kSecAttrAccount as String: "bot"] }
    static func read() -> String? {
        var result: AnyObject?
        var request = query; request[kSecReturnData as String] = true
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ token: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var item = query; item[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Telegram as the verified channel to the owner: only the paired private chat can answer or grant.
@MainActor final class TelegramBridge {
    struct Ask { let id: String; let session: String; let text: String; let scope: String?; var messageID = 0; var status = "pending"; var choice = ""; var reply = ""; var answeredAt = ""; var created = ISO8601DateFormatter().string(from: Date()) }
    private(set) var asks: [String: Ask] = [:]
    private var askOrder: [String] = []
    private var token: String? = TelegramKeychain.read()
    private(set) var pairingCode: String?
    private var offset = 0
    private var polling = false
    var answered: ((Ask) -> Void)?
    var ownerMessage: ((String) -> Void)?
    var changed: (() -> Void)?

    var owner: Int64? {
        get { let value = UserDefaults.standard.object(forKey: "telegramOwnerChat") as? NSNumber; return value?.int64Value }
        set { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: "telegramOwnerChat") }
    }
    var state: String { token == nil ? "off" : owner != nil ? "paired" : pairingCode != nil ? "pairing" : "token" }

    /// Called with a token read straight from the clipboard; returns false when Telegram rejects it.
    func configure(token newToken: String) async -> Bool {
        guard newToken.range(of: #"^\d{5,}:[A-Za-z0-9_-]{30,}$"#, options: .regularExpression) != nil else { return false }
        let previous = token; token = newToken
        guard (try? await call("getMe", [:])) != nil, TelegramKeychain.write(newToken) else { token = previous; return false }
        owner = nil; offset = 0
        pairingCode = String(format: "%06d", Int.random(in: 0..<1_000_000))
        changed?(); start()
        return true
    }

    func start() {
        guard !polling, token != nil else { return }
        polling = true
        Task { [weak self] in
            while let self, self.token != nil {
                do {
                    let updates = try await self.call("getUpdates", ["offset": self.offset, "timeout": 50, "allowed_updates": ["message", "callback_query"]], timeout: 70) as? [[String: Any]] ?? []
                    for update in updates {
                        if let id = update["update_id"] as? Int { self.offset = max(self.offset, id + 1) }
                        await self.handle(update)
                    }
                } catch { try? await Task.sleep(for: .seconds(5)) }
            }
            self?.polling = false
        }
    }

    /// Mirrors to the phone app; Telegram is used only when paired. Fails only when neither channel reaches the owner.
    var mobileNote: ((String) -> Void)?
    var mobilePaired: () -> Bool = { false }

    static let channelValues = ["celular", "telegram", "whatsapp", "email"]
    /// The channel the owner picked when creating the team; nil keeps the old behaviour (phone and Telegram, whichever is paired).
    var channel: String? {
        get { UserDefaults.standard.string(forKey: "messengerChannel").flatMap { Self.channelValues.contains($0) ? $0 : nil } }
        set { UserDefaults.standard.set(newValue, forKey: "messengerChannel") }
    }

    /// Where notify and ask go. The chosen channel alone when it is verified; otherwise whichever verified one exists.
    /// WhatsApp and email are sent by the Mensageiro itself, so the Boterm tools refuse and say so.
    func targets() throws -> (phone: Bool, telegram: Bool) { try Self.targets(channel: channel, phone: mobilePaired(), paired: owner != nil) }
    static func targets(channel: String?, phone: Bool, paired: Bool) throws -> (phone: Bool, telegram: Bool) {
        switch channel {
        case "celular" where phone: return (true, false)
        case "telegram" where paired: return (false, true)
        case "whatsapp", "email":
            throw ControlError.invalid("O Ricardo escolheu \(channel == "email" ? "email" : "WhatsApp") como canal do Mensageiro: envie por lá, como nas regras, e grave as permissões concedidas com grant.")
        default: return (phone, paired || !phone)
        }
    }

    /// Returns the channels that got the message.
    func notify(_ text: String) async throws -> [String] {
        guard !text.isEmpty, text.utf8.count <= 4000 else { throw ControlError.invalid("Mensagem vazia ou acima de 4000 bytes") }
        let to = try targets()
        if to.phone { mobileNote?(text) }
        if to.telegram { _ = try await send(text) }
        return (to.phone ? ["celular"] : []) + (to.telegram ? ["telegram"] : [])
    }

    func ask(_ text: String, scope: String?, session: String) async throws -> Ask {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        var buttons: [[String: String]] = [["text": "Sim, uma vez", "callback_data": "a:\(id):once"]]
        if scope != nil { buttons.append(["text": "Sim, sempre", "callback_data": "a:\(id):always"]) }
        buttons.append(["text": "Não", "callback_data": "a:\(id):no"])
        let body = scope.map { "\(text)\n\nPermissão: \($0)" } ?? text
        guard !text.isEmpty, text.utf8.count <= 4000 else { throw ControlError.invalid("Mensagem vazia ou acima de 4000 bytes") }
        var ask = Ask(id: id, session: session, text: text, scope: scope)
        if try targets().telegram { ask.messageID = try await send(body, keyboard: [buttons]) }
        asks[id] = ask; askOrder.append(id)
        if askOrder.count > 100 { asks.removeValue(forKey: askOrder.removeFirst()) }
        changed?()
        return ask
    }

    static func dictionary(_ ask: Ask) -> [String: Any] {
        ["id": ask.id, "status": ask.status, "choice": ask.choice, "reply": ask.reply, "scope": ask.scope ?? "", "question": ask.text, "answeredAt": ask.answeredAt]
    }

    /// Free-text answers: "sim, sempre" grants permanently, "sim"/"ok"/"pode" once, "não" refuses.
    static func choice(for text: String, scoped: Bool) -> String {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if scoped, value.range(of: #"^(sim|yes)\W*(sempre|always)"#, options: .regularExpression) != nil { return "always" }
        if value.range(of: #"^(sim|yes|ok|pode|autorizo)\b"#, options: .regularExpression) != nil { return "once" }
        if value.range(of: #"^(n[ãa]o|no)\b"#, options: .regularExpression) != nil { return "no" }
        return "text"
    }

    /// An answer given in the Boterm phone app; the Telegram copy, if any, loses its buttons.
    func answerFromApp(_ id: String, choice: String, device: String) -> Bool {
        guard asks[id]?.status == "pending", choice != "always" || asks[id]?.scope != nil, let label = ["once": "Sim, uma vez", "always": "Sim, sempre", "no": "Não"][choice] else { return false }
        answer(id, choice: choice, reply: label, via: "app")
        if let owner, let message = asks[id]?.messageID, message > 0 {
            Task {
                _ = try? await call("editMessageReplyMarkup", ["chat_id": owner, "message_id": message, "reply_markup": ["inline_keyboard": [[[String: String]]]()]])
                _ = try? await send("→ \(label) (no celular \(device))", replyTo: message)
            }
        }
        return true
    }

    private func answer(_ id: String, choice: String, reply: String, via: String = "telegram") {
        guard var ask = asks[id], ask.status == "pending" else { return }
        ask.status = "answered"; ask.choice = choice; ask.reply = String(reply.prefix(4000))
        ask.answeredAt = ISO8601DateFormatter().string(from: Date())
        if choice == "always", let scope = ask.scope { _ = try? PermissionStore.add(scope: scope, note: ask.text, via: via) }
        asks[id] = ask; answered?(ask); changed?()
    }

    private func handle(_ update: [String: Any]) async {
        if let query = update["callback_query"] as? [String: Any] {
            let from = (query["from"] as? [String: Any])?["id"] as? Int64
            _ = try? await call("answerCallbackQuery", ["callback_query_id": query["id"] as? String ?? ""])
            guard let owner, from == owner, let data = query["data"] as? String else { return }
            let parts = data.split(separator: ":").map(String.init)
            guard parts.count == 3, parts[0] == "a", ["once", "always", "no"].contains(parts[2]), asks[parts[1]]?.status == "pending" else { return }
            let label = ["once": "Sim, uma vez", "always": "Sim, sempre", "no": "Não"][parts[2]]!
            answer(parts[1], choice: parts[2], reply: label)
            if let message = asks[parts[1]]?.messageID {
                _ = try? await call("editMessageReplyMarkup", ["chat_id": owner, "message_id": message, "reply_markup": ["inline_keyboard": [[[String: String]]]()]])
                _ = try? await send("→ \(label)", replyTo: message)
            }
            return
        }
        guard let message = update["message"] as? [String: Any], let chat = message["chat"] as? [String: Any],
              let chatID = chat["id"] as? Int64, let text = message["text"] as? String else { return }
        if owner == nil {
            guard let code = pairingCode, chat["type"] as? String == "private", text.contains(code) else { return }
            owner = chatID; pairingCode = nil; changed?()
            _ = try? await send("🤖 Boterm conectado. Pedidos e avisos da equipe chegam aqui.")
            return
        }
        guard chatID == owner else { return }
        let pending = askOrder.filter { asks[$0]?.status == "pending" }
        let repliedTo = (message["reply_to_message"] as? [String: Any])?["message_id"] as? Int
        if let repliedTo, let id = pending.first(where: { asks[$0]?.messageID == repliedTo }) {
            answer(id, choice: Self.choice(for: text, scoped: asks[id]?.scope != nil), reply: text)
        } else if repliedTo == nil, pending.count == 1 {
            answer(pending[0], choice: Self.choice(for: text, scoped: asks[pending[0]]?.scope != nil), reply: text)
        } else {
            ownerMessage?(String(text.prefix(4000)))
        }
    }

    @discardableResult private func send(_ text: String, keyboard: [[[String: String]]]? = nil, replyTo: Int? = nil) async throws -> Int {
        guard let owner else { throw ControlError.invalid("Telegram não está emparelhado. Peça ao Ricardo: Boterm → Configurações → Configurar Telegram. Use WhatsApp ou email enquanto isso.") }
        guard !text.isEmpty, text.utf8.count <= 4000 else { throw ControlError.invalid("Mensagem vazia ou acima de 4000 bytes") }
        var body: [String: Any] = ["chat_id": owner, "text": text]
        if let keyboard { body["reply_markup"] = ["inline_keyboard": keyboard] }
        if let replyTo { body["reply_parameters"] = ["message_id": replyTo] }
        return (try await call("sendMessage", body) as? [String: Any])?["message_id"] as? Int ?? 0
    }

    /// Errors never carry the request URL, which contains the token.
    private func call(_ method: String, _ body: [String: Any], timeout: TimeInterval = 8) async throws -> Any {
        guard let token, let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else { throw ControlError.invalid("Telegram não configurado") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ControlError.invalid("Telegram indisponível (rede)") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["ok"] as? Bool == true, let result = json["result"] else {
            throw ControlError.invalid("Telegram recusou o pedido (HTTP \(status))")
        }
        return result
    }
}

/// Named layouts saved in preferences; the page decides how to apply them to the current terminals.
enum LayoutProfiles {
    static func all(defaults: UserDefaults = .standard) -> [String: String] { defaults.dictionary(forKey: "layoutProfiles") as? [String: String] ?? [:] }
    static func save(_ name: String, layout: String, defaults: UserDefaults = .standard) {
        var profiles = all(defaults: defaults); profiles[name] = layout; defaults.set(profiles, forKey: "layoutProfiles")
    }
    static func delete(_ name: String, defaults: UserDefaults = .standard) {
        var profiles = all(defaults: defaults); profiles.removeValue(forKey: name); defaults.set(profiles, forKey: "layoutProfiles")
    }
}

/// Project memory across sessions: `.boterm/HISTORY.md` stays small enough to read at every start;
/// older entries roll into `HISTORY-archive.md`, which is only read on demand.
enum SessionLog {
    static let limit = 8192
    static let header = "# Histórico Boterm\n\nResumo das sessões anteriores, mantido pelo Orquestrador com `boterm history`. Entradas antigas ficam em HISTORY-archive.md e só são lidas quando necessário.\n"
    static func file(_ directory: String) -> URL { URL(fileURLWithPath: directory).appendingPathComponent(".boterm/HISTORY.md") }
    static func archive(_ directory: String) -> URL { URL(fileURLWithPath: directory).appendingPathComponent(".boterm/HISTORY-archive.md") }
    static func read(_ directory: String) -> String { (try? String(contentsOf: file(directory), encoding: .utf8)) ?? "" }
    static func entries(_ text: String) -> [String] {
        text.components(separatedBy: "\n## ").dropFirst().map { "## " + $0.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" }
    }
    @discardableResult static func add(title rawTitle: String, text rawText: String, directory: String, now: Date = Date()) throws -> [String: Int] {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines), text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...120).contains(title.count), !title.contains("\n"), (1...2000).contains(text.count) else {
            throw ControlError.invalid("history needs a one-line title (≤120) and a summary (≤2000 characters); keep details in the archive or the repository")
        }
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ControlError.invalid("This session has no project folder")
        }
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate, .withDashSeparatorInDate, .withSpaceBetweenDateAndTime, .withTime, .withColonSeparatorInTime])
        var list = entries(read(directory)) + ["## \(stamp.prefix(16)) · \(title)\n\(text.replacingOccurrences(of: "\n## ", with: "\n### "))\n"]
        var moved: [String] = []
        while list.count > 1, (header + "\n" + list.joined(separator: "\n")).utf8.count > limit { moved.append(list.removeFirst()) }
        try FileManager.default.createDirectory(at: file(directory).deletingLastPathComponent(), withIntermediateDirectories: true)
        if !moved.isEmpty {
            let old = (try? String(contentsOf: archive(directory), encoding: .utf8)) ?? "# Arquivo do histórico Boterm\n"
            try (old + "\n" + moved.joined(separator: "\n")).write(to: archive(directory), atomically: true, encoding: .utf8)
        }
        try (header + "\n" + list.joined(separator: "\n")).write(to: file(directory), atomically: true, encoding: .utf8)
        return ["entries": list.count, "archived": moved.count, "bytes": (header + "\n" + list.joined(separator: "\n")).utf8.count]
    }
    /// The CLI's own context-compaction command; agents without a known one are refused rather than guessed.
    static func compactCommand(agent: String, focus: String) -> String? {
        switch agent {
        case "claude": return focus.isEmpty ? "/compact" : "/compact " + focus
        case "codex": return "/compact"
        case "gemini": return "/compress"
        default: return nil
        }
    }
}
