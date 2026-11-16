"""Offline CLI startup timings: no prompt, no auth, no model request.

codex/claude run with --version / --help only, except the app-server and mcp-server
handshakes, which run with an empty CODEX_HOME (no auth) inside a sandbox-exec profile that
denies all network access. Output: one JSON object per measurement on stdout.
"""
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

work = Path(sys.argv[1])
reps = int(sys.argv[2]) if len(sys.argv) > 2 else 7
relay = "/Users/wgu/Desktop/gptr/inst/gptr/mcp_relay.R"
nonet = ["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"]


def timed(argv, env=None, stdin=subprocess.DEVNULL):
    t0 = time.perf_counter()
    res = subprocess.run(argv, env=env, stdin=stdin, capture_output=True, text=True)
    return time.perf_counter() - t0, res.returncode


def series(name, argv, env=None):
    vals = []
    for _ in range(reps):
        dt, rc = timed(argv, env)
        vals.append(dt)
    print(json.dumps(dict(what=name, n=reps, median_s=statistics.median(vals),
                          min_s=min(vals), max_s=max(vals), rc=rc)), flush=True)


def handshake(name, argv, env, messages):
    """Spawn a JSON-RPC stdio server, send `messages`; time spawn->each response."""
    vals = {m["method"]: [] for m in messages if "id" in m}
    total = []
    for _ in range(reps):
        t0 = time.perf_counter()
        p = subprocess.Popen(argv, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, bufsize=1,
                             cwd=str(work / "tmp"))
        ok = True
        for m in messages:
            t1 = time.perf_counter()
            p.stdin.write(json.dumps(m) + "\n")
            p.stdin.flush()
            if "id" not in m:
                continue
            while True:
                line = p.stdout.readline()
                if not line:
                    ok = False
                    break
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("id") == m["id"]:
                    break
            if not ok:
                break
            vals[m["method"]].append(time.perf_counter() - (t0 if m is messages[0] else t1))
        total.append(time.perf_counter() - t0)
        p.stdin.close()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
    out = dict(what=name, n=reps, ok=ok,
               spawn_to_all_responses_median_s=statistics.median(total))
    for k, v in vals.items():
        if v:
            out[k + "_median_s"] = statistics.median(v)
            out[k + "_min_s"] = min(v)
    print(json.dumps(out), flush=True)


series("rscript_vanilla_empty", ["Rscript", "--vanilla", "-e", "invisible(0)"])
series("codex_version", ["codex", "--version"])
series("codex_exec_help", ["codex", "exec", "--help"])
series("claude_version", ["claude", "--version"])

home = work / "home" / "codex-empty"
home.mkdir(parents=True, exist_ok=True)
env = {k: v for k, v in os.environ.items() if k not in
       {"OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL"}}
env["CODEX_HOME"] = str(home)
init = dict(jsonrpc="2.0", id=1, method="initialize",
            params=dict(clientInfo=dict(name="bench_probe", version="0"),
                        capabilities=dict(experimentalApi=True)))
handshake("codex_app_server_initialize_nonet_emptyhome",
          nonet + ["codex", "app-server", "--listen", "stdio://"], env, [init])
mcp_init = dict(jsonrpc="2.0", id=1, method="initialize",
                params=dict(protocolVersion="2025-06-18", capabilities={},
                            clientInfo=dict(name="bench_probe", version="0")))
handshake("codex_mcp_server_initialize_toolslist_nonet_emptyhome",
          nonet + ["codex", "mcp-server"], env,
          [mcp_init, dict(jsonrpc="2.0", method="notifications/initialized"),
           dict(jsonrpc="2.0", id=2, method="tools/list")])
