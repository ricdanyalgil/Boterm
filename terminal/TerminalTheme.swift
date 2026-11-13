import Foundation

enum TerminalTheme {
    /// Read the user's installed theme; third-party theme files are never bundled or redistributed.
    static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        func object(_ url: URL) -> [String: Any]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any]
        }
        let settings = object(home.appendingPathComponent("Library/Application Support/Code/User/settings.json")) ?? [:]
        guard let selected = settings["workbench.colorTheme"] as? String else { return [:] }
        let directories = [home.appendingPathComponent(".vscode/extensions"), URL(fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions")]
        var colors: [String: String] = [:]
        func readColors(_ url: URL, depth: Int = 0) -> [String: String] {
            guard depth < 8, let theme = object(url) else { return [:] }
            var values: [String: String] = [:]
            if let include = theme["include"] as? String { values = readColors(url.deletingLastPathComponent().appendingPathComponent(include), depth: depth + 1) }
            values.merge(theme["colors"] as? [String: String] ?? [:]) { _, new in new }
            return values
        }
        search: for directory in directories {
            let extensions = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for folder in extensions.sorted(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) {
                guard let package = object(folder.appendingPathComponent("package.json")), let contributes = package["contributes"] as? [String: Any], let themes = contributes["themes"] as? [[String: Any]] else { continue }
                if let theme = themes.first(where: { $0["label"] as? String == selected || $0["id"] as? String == selected }), let path = theme["path"] as? String {
                    colors = readColors(folder.appendingPathComponent(path)); break search
                }
            }
        }
        if let overrides = settings["workbench.colorCustomizations"] as? [String: Any] {
            colors.merge(overrides.compactMapValues { $0 as? String }) { _, new in new }
            if let scoped = overrides["[\(selected)]"] as? [String: String] { colors.merge(scoped) { _, new in new } }
        }
        var result: [String: String] = ["name": selected]
        let base = ["background": colors["terminal.background"] ?? colors["editor.background"],
                    "foreground": colors["terminal.foreground"] ?? colors["editor.foreground"],
                    "cursor": colors["terminalCursor.foreground"] ?? colors["editorCursor.foreground"],
                    "selectionBackground": colors["terminal.selectionBackground"] ?? colors["editor.selectionBackground"]]
        for (key, value) in base { if let value, validColor(value) { result[key] = value } }
        for key in ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite"] {
            let ansi = key.prefix(1).uppercased() + key.dropFirst()
            if let value = colors["terminal.ansi" + ansi], validColor(value) { result[key] = value }
        }
        return result
    }
    static func validColor(_ value: String) -> Bool { value.range(of: "^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", options: .regularExpression) != nil }
}
