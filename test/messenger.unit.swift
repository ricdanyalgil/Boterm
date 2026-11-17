import Foundation

@main
struct MessengerTests {
    @MainActor static func main() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("boterm-permissions-\(UUID().uuidString)/permissions.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        precondition(PermissionStore.all(at: file).isEmpty)
        let grant = try PermissionStore.add(scope: "  Deploy:Firebase:Bibs ", note: "Sim, sempre", via: "whatsapp", at: file)
        precondition(grant.scope == "deploy:firebase:bibs" && PermissionStore.granted("DEPLOY:firebase:bibs", at: file) != nil)
        try PermissionStore.add(scope: "deploy:firebase:bibs", note: "again", via: "telegram", at: file)
        precondition(PermissionStore.all(at: file).count == 1 && PermissionStore.all(at: file)[0].via == "telegram", "same scope must replace, not duplicate")
        let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
        precondition(mode == 0o600, "permissions file must be private")
        for bad in ["", "a\nb", String(repeating: "x", count: 201)] {
            precondition((try? PermissionStore.scope(bad)) == nil, "invalid scope accepted: \(bad.prefix(10))")
        }
        try PermissionStore.revoke(PermissionStore.all(at: file)[0].id, at: file)
        precondition(PermissionStore.all(at: file).isEmpty)
        let cases: [(String, Bool, String)] = [("Sim, sempre", true, "always"), ("sim sempre", true, "always"), ("Sim, sempre", false, "once"),
            ("ok", true, "once"), ("Pode", true, "once"), ("Não", true, "no"), ("nao agora", true, "no"), ("simples demais", true, "text"), ("Depois vejo", true, "text")]
        for (text, scoped, expected) in cases { precondition(TelegramBridge.choice(for: text, scoped: scoped) == expected, "\(text) → \(expected)") }
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("boterm-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        precondition((try? SessionLog.add(title: "x", text: "y", directory: project.path + "/missing")) == nil, "missing folder accepted")
        precondition((try? SessionLog.add(title: "a\nb", text: "y", directory: project.path)) == nil, "multiline title accepted")
        precondition((try? SessionLog.add(title: "x", text: String(repeating: "z", count: 2001), directory: project.path)) == nil, "oversized summary accepted")
        var archived = 0
        for i in 1...12 {
            let result = try SessionLog.add(title: "Atividade \(i)", text: String(repeating: "resumo \(i) ", count: 120) + "\n## injetado", directory: project.path)
            archived += result["archived"] ?? 0
            precondition(SessionLog.read(project.path).utf8.count <= SessionLog.limit, "history exceeded its limit")
        }
        let current = SessionLog.read(project.path), old = try String(contentsOf: SessionLog.archive(project.path), encoding: .utf8)
        let kept = SessionLog.entries(current)
        precondition(archived > 0 && kept.count + archived == 12 && kept.last!.contains("Atividade 12") && old.contains("· Atividade 1\n") && !current.contains("· Atividade 1\n"), "rotation lost or duplicated entries")
        precondition(!current.contains("\n## injetado") && current.contains("### injetado"), "summary could forge an entry heading")
        precondition(SessionLog.compactCommand(agent: "claude", focus: "manter o plano") == "/compact manter o plano" && SessionLog.compactCommand(agent: "codex", focus: "x") == "/compact"
            && SessionLog.compactCommand(agent: "gemini", focus: "") == "/compress" && SessionLog.compactCommand(agent: "agy", focus: "") == nil && SessionLog.compactCommand(agent: "", focus: "") == nil)
        print("PASS: project history limit, archive rotation, heading injection and compaction commands")
        print("PASS: permission store (normalize, replace, private file, revoke) and reply parsing")
    }
}
