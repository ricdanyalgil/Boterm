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
