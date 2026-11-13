import Foundation

@main
struct Tests {
    @MainActor static func main() async throws {
        let themeHome = FileManager.default.temporaryDirectory.appendingPathComponent("boterm-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: themeHome) }
        let user = themeHome.appendingPathComponent("Library/Application Support/Code/User")
        let themeFolder = themeHome.appendingPathComponent(".vscode/extensions/example")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        try "{\"workbench.colorTheme\":\"Test Theme\", /* JSONC */ \"workbench.colorCustomizations\":{\"terminal.ansiGreen\":\"#123456\"},}".write(to: user.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "{\"contributes\":{\"themes\":[{\"label\":\"Test Theme\",\"path\":\"theme.json\"}]}}".write(to: themeFolder.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{\"include\":\"base.json\",\"colors\":{\"terminal.ansiRed\":\"bad-color\"}}".write(to: themeFolder.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)
        try "{\"colors\":{\"editor.background\":\"#102030\",\"terminal.ansiBlue\":\"#445566\"}}".write(to: themeFolder.appendingPathComponent("base.json"), atomically: true, encoding: .utf8)
        let theme = TerminalTheme.load(home: themeHome)
        precondition(theme["background"] == "#102030" && theme["green"] == "#123456" && theme["blue"] == "#445566" && theme["red"] == nil)
        precondition(TerminalTheme.validColor("#717CB450") && !TerminalTheme.validColor("url(secret)"))
        precondition(promptText("  Olá!\r\nReveja a API.\t🚀\u{1b}\u{0}  ") == "Olá! Reveja a API. 🚀")
        precondition(promptText("$(teste) `código`") == "$(teste) `código`")
        precondition(!promptText("a\u{8}b\u{9b}c\n").unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }))
        let shell = ShellSession()
        var output = Data()
        shell.output = { output.append($0) }
        try shell.start(executable: "/bin/zsh", arguments: ["-f", "-c", "printf 'READY\\n'; IFS= read -r value; printf 'SUBMITTED:%s\\n' \"$value\""], directory: "/tmp")
        defer { shell.close() }
        for _ in 0..<100 {
            if String(decoding: output, as: UTF8.self).contains("READY") { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(String(decoding: output, as: UTF8.self).contains("READY"))
        shell.resize(columns: 80, rows: 24)
        shell.write("Texto sem Enter")
        try await Task.sleep(for: .milliseconds(200))
        precondition(!String(decoding: output, as: UTF8.self).contains("SUBMITTED:"))
        shell.write("\n")
        for _ in 0..<100 {
            if String(decoding: output, as: UTF8.self).contains("SUBMITTED:Texto sem Enter") { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(String(decoding: output, as: UTF8.self).contains("SUBMITTED:Texto sem Enter"))
        print("PASS: native text sanitization, real PTY, resize and no submission without Enter")
    }
}
