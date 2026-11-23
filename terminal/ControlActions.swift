import AppKit
import WebKit

enum TerminalHistory {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Boterm/History", isDirectory: true) }
    static func save(_ text: String, in directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = directory.appendingPathComponent("Boterm-\(timestamp)-\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }
}

enum ProjectHistory {
    static func directory(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url.path
    }
    static func paths(defaults: UserDefaults = .standard) -> [String] {
        var result: [String] = []
        for path in defaults.stringArray(forKey: "recentProjectDirectories") ?? [] {
            if let path = directory(path), !result.contains(path) { result.append(path) }
            if result.count == 10 { break }
        }
        return result
    }
    static func remember(_ path: String, defaults: UserDefaults = .standard) {
        guard let path = directory(path) else { return }
        defaults.set(Array(([path] + paths(defaults: defaults).filter { $0 != path }).prefix(10)), forKey: "recentProjectDirectories")
    }
}

/// Agent role profiles: one global file and an optional per-project copy in .boterm/roles.json. The page owns the schema and its caps.
enum RoleProfiles {
    static let limit = 512 * 1024
    static var global: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Boterm/roles.json") }
    static func project(_ directory: String) -> URL? {
        ProjectHistory.directory(directory).map { URL(fileURLWithPath: $0).appendingPathComponent(".boterm/roles.json") }
    }
    static func read(_ url: URL?) -> String {
        guard let url, let data = try? Data(contentsOf: url), data.count <= limit else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func payload(_ directory: String) -> [String: String] {
        ["global": read(global), "project": read(project(directory)), "directory": ProjectHistory.directory(directory) ?? ""]
    }
    static func save(_ text: String, scope: String, directory: String) throws {
        let data = Data(text.utf8)
        guard data.count <= limit, (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
              let url = scope == "global" ? global : scope == "project" ? project(directory) : nil else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    /// Role id -> CLI ("" = closed), plus "id:cli" for the CLI remembered while a role is unchecked.
    static func validChoice(_ value: Any?) -> [String: String]? {
        guard let choice = value as? [String: String], choice.count <= 200 else { return nil }
        let ok = choice.allSatisfy { key, cli in
            key.range(of: "^[a-z0-9-]{1,40}(:cli)?$", options: .regularExpression) != nil && ["", "codex", "claude", "agy", "gemini"].contains(cli)
        }
        return ok ? choice : nil
    }
}

@MainActor extension TerminalWindow {
    func saveHistory(sessionID: String? = nil) async throws -> URL {
        guard let text = try await web.callAsyncJavaScript("return await window.voz.historySnapshot(sessionID);", arguments: ["sessionID": sessionID as Any? ?? NSNull()], in: nil, contentWorld: .page) as? String,
              text.utf8.count <= 64 * 1024 * 1024 else { throw ControlError.invalid("Could not capture terminal history") }
        let file = try TerminalHistory.save("Boterm · \(ISO8601DateFormatter().string(from: Date()))\n\n" + text, in: TerminalHistory.directory)
        status.stringValue = tr("History saved: ", "Histórico salvo: ") + file.path
        return file
    }

    func confirmHistoryClose(sessionID: String? = nil) async -> Bool {
        guard !confirmingClose, window.attachedSheet == nil else { return false }
        confirmingClose = true
        defer { confirmingClose = false }
        let alert = NSAlert()
        alert.messageText = tr("Save history before closing?", "Salvar o histórico antes de fechar?")
        alert.informativeText = tr("Saves the available terminal output and team messages locally. Running programs will end; unsent input may be lost. Saved History in the Shell menu opens your files.", "Salva a saída disponível dos terminais e as mensagens da equipe neste Mac. Os programas vão terminar; texto não enviado pode ser perdido. Acesse os arquivos em Shell → Histórico salvo.")
        alert.addButton(withTitle: tr("Save and Close", "Salvar e fechar"))
        alert.addButton(withTitle: tr("Close Without Saving", "Fechar sem salvar"))
        alert.addButton(withTitle: tr("Cancel", "Cancelar")).keyEquivalent = "\u{1b}"
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        if response == .alertSecondButtonReturn { return true }
        guard response == .alertFirstButtonReturn else { return false }
        do { _ = try await saveHistory(sessionID: sessionID); return true }
        catch {
            let failure = NSAlert(error: error)
            failure.messageText = tr("History was not saved. The terminal remains open.", "O histórico não foi salvo. O terminal continua aberto.")
            failure.beginSheetModal(for: window, completionHandler: nil)
            return false
        }
    }

    @objc func pasteText() {
        if let text = NSPasteboard.general.string(forType: .string), text.utf8.count <= 1_048_576 {
            js("window.voz.paste(\(Self.json(text)))")
        }
    }

    func closeSession(_ id: String) {
        guard records[id] != nil else { return }
        Task {
            guard await confirmHistoryClose(sessionID: id), let record = records[id] else { return }
            if voiceSessionID == id, dictation.state != .idle { cancelVoice() }
            record.shell.close(); records.removeValue(forKey: id)
            js("window.voz.remove(\(Self.json(id)))")
        }
    }

    func renameSession(_ id: String) {
        guard let record = records[id] else { return }
        let alert = NSAlert(); alert.messageText = tr("Rename terminal", "Renomear terminal")
        let field = NSTextField(string: record.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: tr("Save", "Salvar")); alert.addButton(withTitle: tr("Cancel", "Cancelar"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { return }
        records[id]?.name = name; js("window.voz.rename(\(Self.json(id)), \(Self.json(name)))")
    }

    func postMessage(from: String, to: String, text: String) throws -> [String: Any] {
        guard let sender = records[from], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 16000 else { throw ControlError.invalid("Invalid sender or message (maximum 16 KB)") }
        guard to == "*" || records[to]?.workspace == sender.workspace else { throw ControlError.invalid("Recipient is outside this workspace") }
        let message: [String: Any] = ["id": UUID().uuidString, "from": from, "to": to, "fromName": sender.name,
            "toName": to == "*" ? "Equipe" : records[to]!.name, "workspace": sender.workspace,
            "time": ISO8601DateFormatter().string(from: Date()), "text": text]
        messages.append(message); if messages.count > 200 { messages.removeFirst() }
        js("window.voz.message(\(Self.json(message)))")
        return message
    }
}

@MainActor extension AppDelegate {
    @objc func saveHistory() {
        guard let terminal = focused else { return }
        Task {
            do { _ = try await terminal.saveHistory() }
            catch { NSAlert(error: error).beginSheetModal(for: terminal.window, completionHandler: nil) }
        }
    }
    @objc func showHistory() {
        do {
            try FileManager.default.createDirectory(at: TerminalHistory.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.open(TerminalHistory.directory)
        } catch { NSAlert(error: error).runModal() }
    }
    var focused: TerminalWindow? { terminals.first { $0.window === NSApplication.shared.keyWindow } }
    @objc func copy(_ sender: Any?) { focused?.js("window.voz.copy()") }
    @objc func paste(_ sender: Any?) { focused?.pasteText() }
    @objc func selectAll(_ sender: Any?) { focused?.js("window.voz.selectAll()") }
    @objc func newTab() { focused?.js("window.voz.create()") }

    func refreshAgentStates() {
        for terminal in terminals {
            for (id, record) in terminal.records where record.state == "running" && record.agentPID > 0 {
                if !processAncestors(record.agentPID).contains(record.shell.pid) {
                    terminal.records[id]?.state = "idle"
                    terminal.js("window.voz.agent(\(TerminalWindow.json(id)), \(TerminalWindow.json(record.agent)), 'idle')")
                }
            }
        }
    }

    func controlRequest(_ data: Data) async -> Data {
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ControlError.invalid("Invalid request") }
            if request["command"] as? String == "resolve", let peer = request["peerPID"] as? Int32 {
                let ancestors = processAncestors(peer)
                for terminal in terminals {
                    if let (id, record) = terminal.records.first(where: { $0.value.shell.pid > 0 && ancestors.contains($0.value.shell.pid) }) {
                        return try JSONSerialization.data(withJSONObject: ["result": ["session": id, "workspace": record.workspace]])
                    }
                }
                throw ControlError.invalid("Caller is not a child of a Boterm session")
            }
            guard
                  let from = request["from"] as? String, let workspace = request["workspace"] as? String,
                  let terminal = terminals.first(where: { $0.records[from]?.workspace == workspace }),
                  let command = request["command"] as? String else { throw ControlError.invalid("Run boterm inside a Boterm terminal; workspace/session required") }
            guard let peer = request["peerPID"] as? Int32, let caller = terminal.records[from],
                  caller.shell.pid > 0, processAncestors(peer).contains(caller.shell.pid) else {
                throw ControlError.invalid("Caller does not belong to this session")
            }
            let target = request["target"] as? String ?? from
            func checkedTarget() throws {
                guard terminal.records[target]?.workspace == workspace else { throw ControlError.invalid("Session is outside this workspace") }
            }
            var value: Any
            switch command {
            case "list":
                value = terminal.records.filter { $0.value.workspace == workspace }.map { id, record in
                    ["id": id, "name": record.name, "pid": record.shell.pid, "workspace": workspace, "agent": record.agent, "state": record.state] as [String: Any]
                }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            case "agentState":
                guard let agent = request["agent"] as? String, ["codex", "claude", "agy", "gemini", "opencode"].contains(agent),
                      let state = request["state"] as? String, ["running", "idle"].contains(state) else { throw ControlError.invalid("Invalid agent state") }
                terminal.records[from]?.agent = agent; terminal.records[from]?.state = state
                terminal.records[from]?.agentPID = request["peerPID"] as? Int32 ?? 0
                terminal.js("window.voz.agent(\(TerminalWindow.json(from)), \(TerminalWindow.json(agent)), \(TerminalWindow.json(state)))")
                value = true
            case "read":
                try checkedTarget()
                value = try await terminal.web.evaluateJavaScript("window.voz.snapshot(\(TerminalWindow.json(target)))") ?? ""
            case "message":
                value = try terminal.postMessage(from: from, to: target, text: request["text"] as? String ?? "")
            case "inbox":
                value = terminal.messages.filter { $0["workspace"] as? String == workspace && ($0["to"] as? String == from || $0["to"] as? String == "*" || $0["from"] as? String == from) }
            case "send":
                try checkedTarget()
                guard let text = request["text"] as? String, text.utf8.count <= 15000,
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) else { throw ControlError.invalid("Invalid text (maximum 15 KB, no terminal control characters)") }
                let submitting = request["submit"] as? Bool == true
                // Paste stays a draft; Enter is a separate, explicit operation.
                _ = try await terminal.web.evaluateJavaScript("window.voz.insert(\(TerminalWindow.json(text)), \(TerminalWindow.json(target)), \(submitting))")
                value = try terminal.postMessage(from: from, to: target, text: submitting ? "[Terminal: submitted input] \(text)" : "[Terminal: inserted draft] \(text)")
            case "tool":
                // Claude hook timing: PreToolUse starts a clock, PostToolUse closes it.
                let name = String((request["name"] as? String ?? "").prefix(200)), id = String((request["id"] as? String ?? "").prefix(100))
                let key = id.isEmpty ? name : id
                guard !name.isEmpty else { throw ControlError.invalid("Tool name required") }
                if request["event"] as? String == "pre" {
                    terminal.records[from]?.toolStarts[key] = Date()
                    if let starts = terminal.records[from]?.toolStarts, starts.count > 100 {
                        terminal.records[from]?.toolStarts = starts.filter { Date().timeIntervalSince($0.value) < 3600 }
                    }
                } else {
                    let started = terminal.records[from]?.toolStarts.removeValue(forKey: key)
                    // Claude reports duration_ms on PostToolUse; the local clock is the fallback.
                    let reported = (request["duration"] as? Double ?? 0) / 1000
                    let seconds = min(reported > 0 ? reported : started.map { Date().timeIntervalSince($0) } ?? 0, 3600)
                    let category = Telemetry.category(name)
                    terminal.records[from]?.tools[category, default: ToolUsage()].calls += 1
                    terminal.records[from]?.tools[category, default: ToolUsage()].seconds += seconds
                    terminal.usage[workspace, default: [:]][category, default: ToolUsage()].calls += 1
                    terminal.usage[workspace, default: [:]][category, default: ToolUsage()].seconds += seconds
                }
                value = true
            case "event":
                let text = (request["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let kind = request["kind"] as? String, Telemetry.eventKinds.contains(kind), (1...500).contains(text.count), !text.contains("\n") else {
                    throw ControlError.invalid("event needs a kind (\(Telemetry.eventKinds.joined(separator: ", "))) and one line of text (≤500)")
                }
                let event: [String: Any] = ["id": UUID().uuidString, "workspace": workspace, "session": from, "name": caller.name, "kind": kind, "text": text, "time": ISO8601DateFormatter().string(from: Date())]
                terminal.events.append(event); if terminal.events.count > 500 { terminal.events.removeFirst() }
                terminal.js("window.voz.event(\(TerminalWindow.json(event)))")
                value = event
            case "events":
                value = Array(terminal.events.filter { $0["workspace"] as? String == workspace }.suffix(100))
            case "history":
                let text = request["text"] as? String ?? ""
                if text.isEmpty { value = SessionLog.read(caller.directory) }
                else {
                    guard caller.role == "Orquestrador" else { throw ControlError.invalid("Only the Orquestrador records project history; send your summary to the Orquestrador") }
                    value = try SessionLog.add(title: request["title"] as? String ?? "", text: text, directory: caller.directory)
                }
            case "compact":
                try checkedTarget()
                guard let peer = terminal.records[target], let command = SessionLog.compactCommand(agent: peer.agent, focus: String((request["text"] as? String ?? "").prefix(500))) else {
                    throw ControlError.invalid("No known compaction command for this terminal's agent")
                }
                guard !peer.compacting else { throw ControlError.invalid("Compaction already scheduled for this terminal") }
                terminal.scheduleCompact(target, command: command)
                value = ["scheduled": true, "command": command]
            case "permissions":
                value = PermissionStore.all().map(PermissionStore.dictionary)
            case "notify", "ask", "answer", "grant":
                guard caller.role == "Mensageiro" else { throw ControlError.invalid("Only the Mensageiro session contacts the owner or records permissions; send your request to the Mensageiro") }
                let text = request["text"] as? String ?? ""
                switch command {
                case "notify":
                    try await telegram.notify(text); value = ["sent": true]
                case "ask":
                    let scope = try (request["scope"] as? String).flatMap { $0.isEmpty ? nil : try PermissionStore.scope($0) }
                    if let scope, let grant = PermissionStore.granted(scope) { value = ["status": "granted", "grant": PermissionStore.dictionary(grant)] }
                    else { value = TelegramBridge.dictionary(try await telegram.ask(text, scope: scope, session: from)) }
                case "answer":
                    guard let ask = telegram.asks[request["id"] as? String ?? ""], ask.session == from else { throw ControlError.invalid("Unknown request ID") }
                    value = TelegramBridge.dictionary(ask)
                default:
                    guard let via = request["via"] as? String, ["whatsapp", "email"].contains(via), !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                        throw ControlError.invalid("grant needs via whatsapp|email and the owner's exact reply as text; Telegram answers are recorded automatically")
                    }
                    value = PermissionStore.dictionary(try PermissionStore.add(scope: request["scope"] as? String ?? "", note: text, via: via))
                }
            case "new":
                let name = String((request["text"] as? String ?? "Agent").prefix(80))
                guard terminal.records.count < 32 else { throw ControlError.invalid("Maximum 32 sessions per window") }
                value = try await terminal.web.evaluateJavaScript("window.voz.create(\(TerminalWindow.json(name)), \(TerminalWindow.json(workspace)))") ?? ""
            default: throw ControlError.invalid("Unknown command")
            }
            return try JSONSerialization.data(withJSONObject: ["result": value], options: [.sortedKeys])
        } catch { return (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data("{}".utf8) }
    }
}

@MainActor extension TerminalWindow {
    func saveLayout(_ layout: String, suggested: String) {
        guard layout.utf8.count <= 65536, (try? JSONSerialization.jsonObject(with: Data(layout.utf8))) is [String: Any] else { return }
        let alert = NSAlert(); alert.messageText = "Salvar perfil de layout"
        alert.informativeText = "Guarda o modo (único, dividir ou mosaico), a ordem e o tamanho de cada terminal pelo nome. Ao aplicar, os terminais existentes são reorganizados; nenhum é criado."
        let field = NSTextField(string: suggested); field.placeholderString = "Ex.: Equipe completa"; field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Salvar"); alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return }
        LayoutProfiles.save(name, layout: layout)
        for terminal in (NSApp.delegate as? AppDelegate)?.terminals ?? [self] {
            terminal.js("window.voz.layoutProfiles(\(Self.json(LayoutProfiles.all())), \(Self.json(terminal === self ? name : "")))")
        }
    }
    func deleteLayout(_ name: String) {
        let alert = NSAlert(); alert.messageText = "Apagar o perfil “\(name)”?"
        alert.addButton(withTitle: "Apagar"); alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LayoutProfiles.delete(name)
        for terminal in (NSApp.delegate as? AppDelegate)?.terminals ?? [self] { terminal.js("window.voz.layoutProfiles(\(Self.json(LayoutProfiles.all())))") }
    }
    /// Waits until the agent is quiet (no output for 5 s, no typing for 30 s) so the command lands in an idle prompt.
    func scheduleCompact(_ id: String, command: String) {
        records[id]?.compacting = true
        Task { [weak self] in
            for _ in 0..<1800 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let record = self.records[id] else { return }
                guard Date().timeIntervalSince(record.lastOutput) > 5, Date().timeIntervalSince(record.lastInput) > 30 else { continue }
                self.records[id]?.compacting = false
                self.js("window.voz.insert(\(Self.json(command)), \(Self.json(id)), true)")
                self.postOwnerMessage(to: id, text: "[Boterm] Compactação enviada: \(command)", sender: "Boterm")
                return
            }
            self?.records[id]?.compacting = false
        }
    }
    /// Shown in the recipient's pane and inbox; it never becomes terminal input.
    func postOwnerMessage(to id: String, text: String, sender: String = "Ricardo · Telegram") {
        guard let record = records[id] else { return }
        let message: [String: Any] = ["id": UUID().uuidString, "from": "owner", "to": id, "fromName": sender, "toName": record.name,
            "workspace": record.workspace, "time": ISO8601DateFormatter().string(from: Date()), "text": String(text.prefix(16000))]
        messages.append(message); if messages.count > 200 { messages.removeFirst() }
        js("window.voz.message(\(Self.json(message)))")
    }
}

@MainActor extension AppDelegate {
    func connectTelegram() {
        telegram.answered = { [weak self] ask in
            guard let terminal = self?.terminals.first(where: { $0.records[ask.session] != nil }) else { return }
            terminal.postOwnerMessage(to: ask.session, text: "Resposta ao pedido \(ask.id): \(ask.reply)" + (ask.choice == "always" ? " · permissão gravada: \(ask.scope ?? "")" : ""))
        }
        telegram.ownerMessage = { [weak self] text in
            for terminal in self?.terminals ?? [] {
                for (id, record) in terminal.records where record.role == "Mensageiro" { terminal.postOwnerMessage(to: id, text: text) }
            }
        }
        telegram.changed = { [weak self] in self?.terminals.forEach { self?.sendMessengerState(to: $0) } }
        telegram.start()
    }
    func sendMessengerState(to terminal: TerminalWindow) {
        let state: [String: Any] = ["telegram": telegram.state, "code": telegram.pairingCode ?? "", "grants": PermissionStore.all().map(PermissionStore.dictionary)]
        terminal.js("window.voz.messengerState(\(TerminalWindow.json(state)))")
    }
    /// Follows the approved secret pattern: the token goes from the clipboard to the Keychain unseen, then the clipboard is cleared.
    func setupTelegram(for terminal: TerminalWindow) {
        let intro = NSAlert()
        intro.messageText = "Configurar o Telegram do Mensageiro"
        intro.informativeText = "1. No Telegram, abra @BotFather, envie /newbot e siga os passos.\n2. Toque em copiar no token que ele devolve.\n3. Volte aqui e clique em Ler token.\n\nO token vai direto para o Keychain deste Mac, não aparece na tela e a área de transferência é limpa. Depois você envia ao seu bot um código de 6 dígitos; só essa conversa poderá responder e conceder permissões."
        intro.addButton(withTitle: "Ler token"); intro.addButton(withTitle: "Cancelar")
        guard intro.runModal() == .alertFirstButtonReturn else { return }
        let token = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await telegram.configure(token: token)
            if ok { NSPasteboard.general.clearContents() }
            let result = NSAlert()
            result.messageText = ok ? "Agora envie ao seu bot: \(telegram.pairingCode ?? "")" : "Token não aceito"
            result.informativeText = ok ? "Abra a conversa com o bot que você criou e envie esse código. O Boterm confirma por lá quando ficar conectado." : "A área de transferência não tinha um token válido, ou o Telegram o recusou. Nada foi gravado e a área de transferência ficou como estava."
            result.beginSheetModal(for: terminal.window, completionHandler: nil)
            sendMessengerState(to: terminal)
        }
    }
}
