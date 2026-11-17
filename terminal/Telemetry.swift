import Foundation

/// Facts for the project dashboard. Everything is local; nothing leaves the Mac.
struct ToolUsage { var calls = 0; var seconds = 0.0 }

enum Telemetry {
    /// Events agents report for the dashboard, one line each.
    static let eventKinds = ["test-fail", "test-pass", "fix", "improvement", "decision", "blocker"]

    /// `mcp__server__tool` → `mcp:server`; built-in tools keep their name.
    static func category(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return String(tool.prefix(60)) }
        let server = tool.dropFirst(5).components(separatedBy: "__").first ?? ""
        return "mcp:" + (server.isEmpty ? "?" : String(server.prefix(60)))
    }

    static func dictionary(_ usage: [String: ToolUsage]) -> [String: [String: Any]] {
        usage.mapValues { ["calls": $0.calls, "seconds": ($0.seconds * 10).rounded() / 10] }
    }

    /// `git diff --numstat` lines: "added<TAB>removed<TAB>path"; binary files report "-".
    static func numstat(_ text: String) -> (files: [[String: Any]], added: Int, removed: Int) {
        var files: [[String: Any]] = [], added = 0, removed = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            let a = Int(parts[0]) ?? 0, r = Int(parts[1]) ?? 0
            added += a; removed += r
            files.append(["file": parts[2], "added": a, "removed": r])
        }
        files.sort { ($0["added"] as! Int) + ($0["removed"] as! Int) > ($1["added"] as! Int) + ($1["removed"] as! Int) }
        return (files, added, removed)
    }

    /// Runs read-only git with optional locks off, so it never contends with agents committing.
    static func git(_ directory: String, _ arguments: [String]) -> String? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 4_194_304 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func codeChanges(directory: String, since: String) -> [String: Any] {
        guard git(directory, ["rev-parse", "--is-inside-work-tree"]) == "true" else { return ["repo": false] }
        // Boterm's own .boterm/ files are project memory, not code changes.
        let status = (git(directory, ["status", "--porcelain=v1", "--untracked-files=normal", "--", ".", ":(exclude).boterm"]) ?? "").split(separator: "\n")
        let diff = numstat(git(directory, ["diff", "--numstat", "HEAD", "--", ".", ":(exclude).boterm"]) ?? git(directory, ["diff", "--numstat", "--", ".", ":(exclude).boterm"]) ?? "")
        let commits = (git(directory, ["log", "--since=\(since)", "--format=%h %s", "-n", "30"]) ?? "").split(separator: "\n").map(String.init)
        return ["repo": true, "branch": git(directory, ["branch", "--show-current"]) ?? "", "changed": status.count,
                "untracked": status.filter { $0.hasPrefix("??") }.count, "added": diff.added, "removed": diff.removed,
                "files": Array(diff.files.prefix(8)), "commits": commits]
    }

    static func history(directory: String) -> [String: Any] {
        let entries = SessionLog.entries(SessionLog.read(directory))
        let titles = entries.reversed().prefix(5).map { $0.split(separator: "\n").first.map { String($0.dropFirst(3)) } ?? "" }
        let roles = (try? String(contentsOfFile: directory + "/.boterm/ROLES.md", encoding: .utf8)) ?? ""
        let learned = roles.split(separator: "\n").filter { $0.hasPrefix("## ") }.count
        return ["entries": entries.count, "recent": titles, "archive": FileManager.default.fileExists(atPath: SessionLog.archive(directory).path), "roles": learned]
    }
}
