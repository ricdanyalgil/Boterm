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
        precondition(Telemetry.category("mcp__github__search_code") == "mcp:github" && Telemetry.category("Bash") == "Bash" && Telemetry.category("mcp__") == "mcp:?")
        let stat = Telemetry.numstat("3\t1\tsrc/a.ts\n-\t-\timg.png\n10\t0\tREADME.md\nlixo")
        precondition(stat.added == 13 && stat.removed == 1 && stat.files.count == 3 && stat.files[0]["file"] as? String == "README.md")
        let repo = project.appendingPathComponent("repo").path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        precondition(Telemetry.codeChanges(directory: repo, since: "2000-01-01")["repo"] as? Bool == false)
        for args in [["init", "-q"], ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "start"]] { precondition(Telemetry.git(repo, args) != nil, "git \(args[0]) failed") }
        try "um\ndois\n".write(toFile: repo + "/novo.txt", atomically: true, encoding: .utf8)
        try "x\n".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)
        _ = Telemetry.git(repo, ["add", "b.txt"])
        try FileManager.default.createDirectory(atPath: repo + "/.boterm", withIntermediateDirectories: true)
        try "h\n".write(toFile: repo + "/.boterm/HISTORY.md", atomically: true, encoding: .utf8)
        let code = Telemetry.codeChanges(directory: repo, since: "2000-01-01")
        precondition(code["repo"] as? Bool == true && code["changed"] as? Int == 2 && code["untracked"] as? Int == 1 && code["added"] as? Int == 1 && (code["commits"] as? [String])?.count == 1, "\(code)")
        print("PASS: tool categories, numstat parsing and git changes on a real repository")
        print("PASS: project history limit, archive rotation, heading injection and compaction commands")
        print("PASS: permission store (normalize, replace, private file, revoke) and reply parsing")
        // Phone paired, no Telegram (the owner's setup): notify reaches the phone app and reports it.
        let bridge = TelegramBridge(); var notes: [String] = []
        bridge.mobilePaired = { true }; bridge.mobileNote = { notes.append($0) }
        if bridge.owner == nil {
            _ = Task { @MainActor in
                try await bridge.notify("site · Testes: 12/12")
                precondition(notes == ["site · Testes: 12/12"] && bridge.channels == ["celular"], "paired phone must get the update")
                bridge.mobilePaired = { false }
                do { try await bridge.notify("x"); preconditionFailure("no channel must fail") } catch {}
                precondition(bridge.channels.isEmpty && notes.count == 1)
                print("PASS: notify goes to the paired phone and reports via; fails with no channel")
                exit(0)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(5)); preconditionFailure("notify timed out")
        }
    }
}
