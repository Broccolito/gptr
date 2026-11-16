import subprocess, time, statistics, sys, json, os
W = os.path.dirname(os.path.abspath(__file__))
WS = os.path.join(W, "ws")
N = int(sys.argv[1]) if len(sys.argv) > 1 else 7
cmds = {
  "direct_true": ["/usr/bin/true"],
  "sandbox_exec_allow_default_true": ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)", "/usr/bin/true"],
  "sandbox_exec_deny_default_true": ["/usr/bin/sandbox-exec", "-p", "(version 1)(deny default)(allow process-exec)(allow process-fork)(allow file-read*)(allow sysctl-read)(allow mach-lookup)", "/usr/bin/true"],
  "codex_version": ["/opt/homebrew/bin/codex", "--version"],
  "codex_sandbox_readonly_true": ["/opt/homebrew/bin/codex", "sandbox", "-P", ":read-only", "-C", WS, "--", "/usr/bin/true"],
  "codex_sandbox_workspace_true": ["/opt/homebrew/bin/codex", "sandbox", "-P", ":workspace", "-C", WS, "--", "/usr/bin/true"],
  "codex_sandbox_workspace_sh_echo": ["/opt/homebrew/bin/codex", "sandbox", "-P", ":workspace", "-C", WS, "--", "/bin/sh", "-c", "echo hi"],
  "codex_sandbox_readonly_denied_write": ["/opt/homebrew/bin/codex", "sandbox", "-P", ":read-only", "-C", WS, "--", "/bin/sh", "-c", "echo x > ./denied.txt"],
}
res = {}
for name, c in cmds.items():
    ts = []
    rc = None
    for i in range(N):
        t0 = time.perf_counter()
        p = subprocess.run(c, cwd=WS, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        ts.append(time.perf_counter() - t0)
        rc = p.returncode
    res[name] = {"n": N, "median_ms": round(statistics.median(ts)*1000, 2), "min_ms": round(min(ts)*1000, 2), "max_ms": round(max(ts)*1000, 2), "rc": rc, "stderr_tail": p.stderr.decode()[-300:]}
    print(name, json.dumps(res[name]), flush=True)
json.dump(res, open(os.path.join(W, "sandbox-timing.json"), "w"), indent=1)
