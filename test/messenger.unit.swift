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
        print("PASS: permission store (normalize, replace, private file, revoke) and reply parsing")
    }
}
