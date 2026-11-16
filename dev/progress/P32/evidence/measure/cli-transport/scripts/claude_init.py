"""Claude Code stream-json startup: spawn `claude -p --input-format stream-json ...` (gptr's
catalog argv, no MCP server, no tools), send only the `initialize` control request (no user
message, so no model request), time spawn -> control_response. Empty CLAUDE_CONFIG_DIR (no
login) and a sandbox-exec profile that denies all network. Prints JSON lines."""
import json
import os
import select
import statistics
import subprocess
import sys
import time

work = sys.argv[1]
reps = int(sys.argv[2]) if len(sys.argv) > 2 else 5
cfg = os.path.join(work, "home", "claude-empty")
os.makedirs(cfg, exist_ok=True)
env = {k: v for k, v in os.environ.items() if not k.startswith(("ANTHROPIC_", "CLAUDE_CODE_"))}
env["CLAUDE_CONFIG_DIR"] = cfg
env.update(CLAUDE_CODE_DISABLE_AUTO_MEMORY="1", CLAUDE_CODE_DISABLE_CLAUDE_MDS="1",
           CLAUDE_CODE_SKIP_PROMPT_HISTORY="1")
argv = ["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", "claude", "-p",
        "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--system-prompt", "", "--tools", "", "--strict-mcp-config", "--mcp-config",
        '{"mcpServers":{}}', "--setting-sources", "", "--disable-slash-commands",
        "--no-session-persistence"]
req = dict(type="control_request", request_id="probe",
           request=dict(subtype="initialize", hooks=None, skills=[]))
vals = []
for _ in range(reps):
    t0 = time.perf_counter()
    p = subprocess.Popen(argv, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, bufsize=1, cwd=os.path.join(work, "tmp"))
    p.stdin.write(json.dumps(req) + "\n")
    p.stdin.flush()
    got, first = None, None
    deadline = t0 + 30
    while time.perf_counter() < deadline:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if not r:
            if p.poll() is not None:
                break
            continue
        line = p.stdout.readline()
        if not line:
            break
        if first is None:
            first = time.perf_counter() - t0
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "control_response" and obj.get("response", {}).get("request_id") == "probe":
            got = time.perf_counter() - t0
            sub = obj["response"].get("subtype")
            break
    p.stdin.close()
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
    err = p.stderr.read()[:200]
    vals.append(got)
    print(json.dumps(dict(spawn_to_initialize_response_s=got, first_line_s=first,
                          subtype=sub if got else None, rc=p.returncode, stderr_head=err)), flush=True)
ok = [v for v in vals if v is not None]
print(json.dumps(dict(summary=True, n_ok=len(ok), median_s=statistics.median(ok) if ok else None)))
