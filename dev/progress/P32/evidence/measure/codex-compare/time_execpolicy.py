import subprocess, time, statistics, json, os, sys
W = os.path.dirname(os.path.abspath(__file__))
B = "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
N = int(sys.argv[1])
cases = {}
for rf in ["small", "large"]:
    for cmd in [["git","push","origin","main"], ["rm","-rf","build"], ["ls","-la"], ["python3","script.py"]]:
        cases["%s|%s" % (rf, " ".join(cmd))] = [B, "execpolicy", "check", "--rules", os.path.join(W, "rules", rf + ".rules"), "--"] + cmd
for name, c in cases.items():
    ts = []
    for i in range(N):
        t0 = time.perf_counter(); p = subprocess.run(c, capture_output=True); ts.append(time.perf_counter() - t0)
    d = json.loads(p.stdout.decode()).get("decision")
    print(name, json.dumps({"n": N, "median_ms": round(statistics.median(ts)*1000, 2), "decision": d}), flush=True)
