import Foundation
import Darwin

@main struct BotermCLI {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst()), env = ProcessInfo.processInfo.environment
            if args.isEmpty || args[0] == "--help" {
                print("""
                boterm agent codex|claude|gemini|opencode [ARGS...]
                boterm mcp
                boterm list | read [SESSION] | inbox | new NAME
                boterm message SESSION|'*' TEXT
                boterm send SESSION TEXT [--submit]
                Read $BOTERM_AGENT_GUIDE for team collaboration. IDs come from list.
                send inserts a draft; only --submit presses Enter. Messages never type into a shell.
                """); return
            }
            var path = env["BOTERM_SOCKET"], from = env["BOTERM_SESSION"], workspace = env["BOTERM_WORKSPACE"]
            if path == nil || from == nil || workspace == nil {
                // Agent CLIs may filter environment variables; the app resolves the kernel peer's ancestry.
                let directories = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp")) ?? []
                for directory in directories where directory.hasPrefix("boterm-") {
                    let candidate = "/tmp/" + directory + "/control.sock"
                    if let response = try? call(candidate, ["command": "resolve"]), let identity = response["result"] as? [String: String] {
                        path = candidate; from = identity["session"]; workspace = identity["workspace"]; break
                    }
                }
            }
            guard let path, let from, let workspace else { throw ControlError.invalid("Run this command inside Boterm") }
            if args[0] == "mcp" { BotermMCP.serve(path: path, from: from, workspace: workspace); return }
            if args[0] == "agent" {
                guard args.count >= 2, ["codex", "claude", "gemini", "opencode"].contains(args[1]) else { throw ControlError.invalid("Usage: boterm agent codex|claude|gemini|opencode [ARGS...]") }
                let kind = args[1], executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
                var flags: [String] = []
                if kind == "codex" {
                    let quoted = String(decoding: try JSONSerialization.data(withJSONObject: executable, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
                    flags = ["-c", "mcp_servers.boterm.command=" + quoted, "-c", "mcp_servers.boterm.args=[\"mcp\"]"]
                    for (key, value) in ["BOTERM_SOCKET": path, "BOTERM_SESSION": from, "BOTERM_WORKSPACE": workspace] {
                        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
                        flags += ["-c", "mcp_servers.boterm.env." + key + "=" + encoded]
                    }
                } else if kind == "claude" {
                    let config = ["mcpServers": ["boterm": ["command": executable, "args": ["mcp"], "env": ["BOTERM_SOCKET": path, "BOTERM_SESSION": from, "BOTERM_WORKSPACE": workspace]]]] as [String: Any]
                    // Bind the variadic option to its JSON so it cannot consume the initial prompt.
                    flags = ["--mcp-config=" + String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)]
                }
                _ = try call(path, ["command": "agentState", "from": from, "workspace": workspace, "agent": kind, "state": "running"])
                // Replace the launcher so the agent keeps the terminal's foreground process group.
                let values = ([kind] + flags + Array(args.dropFirst(2))).map { strdup($0) }
                defer { values.forEach { free($0) } }
                var argv = values + [nil]
                _ = argv.withUnsafeMutableBufferPointer { execvp(kind, $0.baseAddress!) }
                let failure = errno
                _ = try? call(path, ["command": "agentState", "from": from, "workspace": workspace, "agent": kind, "state": "idle"])
                throw ControlError.invalid("Could not start \(kind): \(String(cString: strerror(failure)))")
            }
            var request: [String: Any] = ["command": args[0], "from": from, "workspace": workspace]
            switch args[0] {
            case "list", "inbox": guard args.count == 1 else { throw ControlError.invalid("Unexpected arguments") }
            case "read": guard args.count <= 2 else { throw ControlError.invalid("Usage: boterm read [SESSION]") }; request["target"] = args.count == 2 ? args[1] : from
            case "new": guard args.count == 2 else { throw ControlError.invalid("Usage: boterm new NAME") }; request["text"] = args[1]
            case "message", "send":
                guard args.count == 3 || (args[0] == "send" && args.count == 4 && args[3] == "--submit") else { throw ControlError.invalid("Usage: boterm \(args[0]) SESSION TEXT [--submit for send only]") }
                request["target"] = args[1]; request["text"] = args[2]; request["submit"] = args.count == 4
            default: throw ControlError.invalid("Unknown command; use boterm --help")
            }
            let json = try call(path, request)
            if let error = json["error"] as? String { throw ControlError.invalid(error) }
            if let value = json["result"] as? String { print(value) }
            else { print(String(decoding: try JSONSerialization.data(withJSONObject: json["result"] ?? NSNull(), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]), as: UTF8.self)) }
        } catch { FileHandle.standardError.write(Data("boterm: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    static func call(_ path: String, _ request: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { throw ControlError.invalid("Could not open socket") }
        defer { Darwin.close(fd) }; socketTimeout(fd)
        var address = try socketAddress(path)
        let result = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { throw ControlError.invalid("Boterm is not running or this session has ended") }
        try writeControl(fd, JSONSerialization.data(withJSONObject: request))
        guard let json = try JSONSerialization.jsonObject(with: readControl(fd)) as? [String: Any] else { throw ControlError.invalid("Invalid response") }
        return json
    }

}
