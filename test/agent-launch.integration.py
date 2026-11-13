"""Run with python3 test/agent-launch.integration.py /absolute/path/to/boterm."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading

cli = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="boterm-launch-", dir="/tmp") as directory:
    root = Path(directory)
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(root / "control.sock"))
    listener.listen()
    requests = []

    def serve():
        while True:
            connection, _ = listener.accept()
            with connection, connection.makefile("rb") as stream:
                request = json.loads(stream.readline())
                requests.append(request)
                connection.sendall(b'{"result":"ok"}\n')

    threading.Thread(target=serve, daemon=True).start()
    for kind in ("codex", "claude", "gemini", "opencode"):
        executable = root / kind
        executable.write_text("#!" + sys.executable + "\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
        executable.chmod(0o700)
    env = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
               BOTERM_SOCKET=str(root / "control.sock"), BOTERM_SESSION="session",
               BOTERM_WORKSPACE="workspace")
    prompt = 'Você integra a equipe como Integrações. "aspas" $(touch INJECTION) `touch INJECTION`\n' * 50
    for kind in ("codex", "claude", "gemini", "opencode"):
        for forwarded in ([], ["--help"], ["--prompt-interactive", prompt] if kind == "gemini" else [prompt]):
            result = subprocess.run([cli, "agent", kind, *forwarded], env=env, cwd=root,
                                    capture_output=True, text=True, check=True, timeout=15)
            arguments = json.loads(result.stdout)
            if kind == "claude":
                assert arguments[0].startswith("--mcp-config="), arguments
                config = json.loads(arguments[0].split("=", 1)[1])["mcpServers"]["boterm"]
                assert config["command"] == cli and config["args"] == ["mcp"]
                assert config["env"]["BOTERM_SESSION"] == "session"
                assert config["env"]["BOTERM_WORKSPACE"] == "workspace"
                assert arguments[1:] == forwarded
            elif kind == "codex":
                assert arguments[:2] == ["-c", "mcp_servers.boterm.command=" + json.dumps(cli)]
                assert arguments[10:] == forwarded
            else:
                assert arguments == forwarded
            assert requests[-1] == dict(command="agentState", agent=kind, state="running",
                                        **{"from": "session", "workspace": "workspace"})
    assert not (root / "INJECTION").exists()
    print("PASS: all four launchers preserve options, long literal prompts and per-session MCP configuration")
