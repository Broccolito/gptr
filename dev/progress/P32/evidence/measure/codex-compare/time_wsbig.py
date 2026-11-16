import subprocess, time, statistics, json, os, sys
W = os.path.dirname(os.path.abspath(__file__))
B = "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
N = int(sys.argv[1])
for ws in ["ws", "ws_big"]:
    for prof in [":read-only", ":workspace"]:
        c = [B, "sandbox", "-P", prof, "-C", os.path.join(W, ws), "--", "/usr/bin/true"]
        ts = []
        for i in range(N):
            t0 = time.perf_counter(); p = subprocess.run(c, capture_output=True); ts.append(time.perf_counter() - t0)
        print(ws, prof, json.dumps({"n": N, "median_ms": round(statistics.median(ts)*1000, 2), "rc": p.returncode}), flush=True)
