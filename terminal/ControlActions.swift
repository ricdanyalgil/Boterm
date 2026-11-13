import AppKit
import WebKit

@MainActor extension TerminalWindow {
    @objc func pasteText() {
        if let text = NSPasteboard.general.string(forType: .string), text.utf8.count <= 1_048_576 {
            js("window.voz.paste(\(Self.json(text)))")
        }
    }

    func closeSession(_ id: String) {
        guard let record = records[id] else { return }
        let alert = NSAlert()
        alert.messageText = tr("Close \(record.name)?", "Fechar \(record.name)?")
        alert.informativeText = tr("Programs in this session will end. Unsent text will be lost.", "Os programas desta sessão vão terminar. O texto não enviado será perdido.")
        alert.addButton(withTitle: tr("Keep Open", "Manter aberto")); alert.addButton(withTitle: tr("Close", "Fechar"))
        guard record.shell.pid == 0 || alert.runModal() == .alertSecondButtonReturn else { return }
        if voiceSessionID == id, dictation.state != .idle { cancelVoice() }
        record.shell.close(); records.removeValue(forKey: id)
        js("window.voz.remove(\(Self.json(id)))")
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
                guard let agent = request["agent"] as? String, ["codex", "claude", "gemini", "opencode"].contains(agent),
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
