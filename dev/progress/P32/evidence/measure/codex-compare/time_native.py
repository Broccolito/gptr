import subprocess, time, statistics, sys, json, os
W = os.path.dirname(os.path.abspath(__file__)); WS = os.path.join(W, "ws")
B = "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
N = int(sys.argv[1])
cmds = {
 "native_version": [B, "--version"],
 "native_sandbox_readonly_true": [B, "sandbox", "-P", ":read-only", "-C", WS, "--", "/usr/bin/true"],
 "native_sandbox_workspace_true": [B, "sandbox", "-P", ":workspace", "-C", WS, "--", "/usr/bin/true"],
 "native_sandbox_workspace_log_denials_true": [B, "sandbox", "-P", ":workspace", "--log-denials", "-C", WS, "--", "/usr/bin/true"],
}
out = {}
for name, c in cmds.items():
    ts = []
    for i in range(N):
        t0 = time.perf_counter(); p = subprocess.run(c, cwd=WS, capture_output=True); ts.append(time.perf_counter() - t0)
    out[name] = {"n": N, "median_ms": round(statistics.median(ts)*1000, 2), "min_ms": round(min(ts)*1000, 2), "rc": p.returncode, "err": p.stderr.decode()[-200:]}
    print(name, json.dumps(out[name]), flush=True)
