"""Run inside Boterm against a workspace-mode harness left open with VOZ_TEST_KEEP_OPEN=1."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

metadata = json.loads(Path(sys.argv[1]).read_text())
assert metadata["passed"]
metadata.update(socket=os.environ["BOTERM_SOCKET"], session=os.environ["BOTERM_SESSION"],
                workspace=os.environ["BOTERM_WORKSPACE"])
cli = str(Path(sys.argv[2]).resolve())
env = dict(os.environ, BOTERM_SOCKET=metadata["socket"],
           BOTERM_SESSION=metadata["session"], BOTERM_WORKSPACE=metadata["workspace"])
# The workspace harness intentionally leaves draft input in its existing peer.
metadata["peer"] = subprocess.check_output([cli, "new", "Control integration"], env=env, text=True).strip()
for _ in range(50):
    sessions = json.loads(subprocess.check_output([cli, "list"], env=env, text=True))
    if any(s["id"] == metadata["peer"] and s["pid"] > 0 for s in sessions):
        break
    time.sleep(.1)
else:
    raise AssertionError("Fresh control test terminal did not start")
forged = dict(env, BOTERM_SESSION=metadata["peer"])
denied = subprocess.run([cli, "list"], env=forged, capture_output=True, text=True)
assert denied.returncode != 0 and "Caller does not belong" in denied.stderr, denied
print("PASS: forged session identity rejected against real socket peer ancestry")
server = subprocess.Popen([cli, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=env, text=True)

def rpc(identifier, method, params=None):
    server.stdin.write(json.dumps(dict(jsonrpc="2.0", id=identifier, method=method, params=params or {})) + "\n")
    server.stdin.flush()
    response = json.loads(server.stdout.readline())
    assert response["id"] == identifier and "result" in response, response
    return response["result"]

try:
    assert rpc(1, "initialize", {"protocolVersion": "2025-11-25"})["serverInfo"]["name"] == "boterm"
    names = {tool["name"] for tool in rpc(2, "tools/list")["tools"]}
    assert {"list", "read", "message", "inbox", "send", "new"} == names
    result = rpc(3, "tools/call", {"name": "message", "arguments": {"target": metadata["peer"], "text": "BOTERM_MCP_OK"}})
    assert not result["isError"], result
    denied = rpc(4, "tools/call", {"name": "read", "arguments": {"target": "outside-this-workspace"}})
    assert denied["isError"], denied
    inbox = rpc(5, "tools/call", {"name": "inbox", "arguments": {}})
    assert "BOTERM_MCP_OK" in inbox["content"][0]["text"]
finally:
    server.stdin.close()
    server.wait(timeout=5)
    assert server.returncode == 0, server.stderr.read()

# A process inside the real peer PTY must still resolve its session after an agent filters env.
import shlex
command = "env -u BOTERM_SOCKET -u BOTERM_SESSION -u BOTERM_WORKSPACE " + shlex.join(
    [cli, "message", metadata["session"], "BOTERM_ANCESTRY_OK"])
subprocess.run([cli, "send", metadata["peer"], command, "--submit"], env=env, check=True, stdout=subprocess.DEVNULL)
for _ in range(50):
    messages = json.loads(subprocess.check_output([cli, "inbox"], env=env, text=True))
    if any(m["text"] == "BOTERM_ANCESTRY_OK" and m["from"] == metadata["peer"] for m in messages):
        break
    time.sleep(.1)
else:
    raise AssertionError("Session ancestry resolution failed")
print("PASS: real MCP stdio/socket roundtrip, tool errors, inbox and env-filtered session discovery")

# The generated TOML overrides must be accepted by the actual installed Codex CLI.
import shutil
if shutil.which("codex"):
    configured = subprocess.run([cli, "agent", "codex", "mcp", "list", "--json"], env=env, capture_output=True, text=True, check=True)
    server = next(s for s in json.loads(configured.stdout) if s["name"] == "boterm")
    assert server["transport"]["command"] == cli
    assert server["transport"]["args"] == ["mcp"]
    assert server["transport"]["env"]["BOTERM_SESSION"] == metadata["session"]
    print("PASS: actual Codex parses generated per-session MCP configuration")
