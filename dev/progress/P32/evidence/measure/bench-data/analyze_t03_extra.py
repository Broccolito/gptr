"""C1 turn boundaries and A1 counterfactuals from the T03 CSVs written by analyze_t03.py.
Usage: python3 -I analyze_t03_extra.py <bench-root> <out-dir>"""
import csv, json, statistics, sys
from pathlib import Path
ROOT, OUT = Path(sys.argv[1]), Path(sys.argv[2])
REPLAY = ROOT / "biomedical/v0.5/reports/T03/replay"
med = statistics.median
# C1: request_start -> turn/started, turn/completed -> request_end, thread start before request 1
pre, post, thread = [], [], []
for t in (1, 2, 3):
    ev = [json.loads(l) for l in open(REPLAY / f"C1-{t}/trace.jsonl")]
    rs, ts, tc = {}, {}, {}
    cur = 0
    first_event = None
    for e in ev:
        if e["type"] == "request_start":
            cur = e["turn"]; rs[cur] = e["data"]["unix"]
        elif e["type"] == "request_end":
            post.append(e["data"]["unix"] - tc[e["turn"]])
        elif e["type"] == "app_server_event":
            m = e["data"]["message"]
            if first_event is None and m.get("emittedAtMs"):
                first_event = m["emittedAtMs"] / 1000
            if m.get("method") == "turn/started":
                ts[cur] = m["emittedAtMs"] / 1000; pre.append(ts[cur] - rs[cur])
            if m.get("method") == "turn/completed":
                tc[cur] = m["emittedAtMs"] / 1000
print("C1 request_start->turn/started median/max:", round(med(pre), 3), round(max(pre), 3))
print("C1 turn/completed->request_end median/max:", round(med(post), 3), round(max(post), 3))
runs = {r["run"]: r for r in csv.DictReader(open(OUT / "t03_runs.csv"))}
reqs = [r for r in csv.DictReader(open(OUT / "t03_requests.csv")) if r["arm"] == "A1"]
calls = list(csv.DictReader(open(OUT / "t03_a1_calls.csv")))
cmds = [float(c["overhead_around_rscript_s"]) for c in csv.DictReader(open(OUT / "t03_c1_commands.csv"))
        if c["overhead_around_rscript_s"] not in ("", "None")]
lvl = med(cmds)
c1_pre, c1_post = med(pre), med(post)
c1_out = med([float(runs[f"C1-{t}"]["outside_requests_s"]) for t in (1, 2, 3)])
rows = []
for t in (1, 2, 3):
    run = f"A1-{t}"
    wall = float(runs[run]["wall_s"])
    rr = [r for r in reqs if r["run"] == run]
    gap_x = sum(max(0, float(c["gap_s"]) - lvl) for c in calls if c["run"] == run)
    after_x = sum(float(r["gptr_after_provider_s"]) - c1_post for r in rr)
    before_x = sum(float(r["gptr_before_provider_s"]) - c1_pre for r in rr)
    out_x = float(runs[run]["outside_requests_s"]) - c1_out
    rows.append(dict(run=run, wall_s=wall, gap_excess_s=gap_x, after_provider_excess_s=after_x,
                     before_provider_excess_s=before_x, outside_requests_excess_s=out_x,
                     cf1_gap_only_s=wall - gap_x, cf2_plus_turn_edges_s=wall - gap_x - after_x - before_x,
                     cf3_plus_startup_s=wall - gap_x - after_x - before_x - out_x))
keys = list(rows[0].keys())
print(" | ".join(keys))
for r in rows:
    print(" | ".join(f"{v:.2f}" if isinstance(v, float) else str(v) for v in r.values()))
for k in keys[1:]:
    print("median", k, round(med([r[k] for r in rows]), 2), "mean", round(statistics.mean([r[k] for r in rows]), 2))
c1w = [float(runs[f"C1-{t}"]["wall_s"]) for t in (1, 2, 3)]
print("C1 wall median/mean:", round(med(c1w), 2), round(statistics.mean(c1w), 2))
print("C1 per-command overhead level used:", round(lvl, 3), "C1 outside-requests median:", round(c1_out, 3))
with open(OUT / "t03_counterfactual.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=keys); w.writeheader()
    for r in rows:
        w.writerow({k: round(v, 3) if isinstance(v, float) else v for k, v in r.items()})
# per-binding scan unit (inference): A1-1 kept `tables` and `raw`; A1-2/A1-3 only `raw`
for run, nb in (("A1-1", 2), ("A1-2", 1), ("A1-3", 1)):
    g = [float(c["gap_s"]) for c in calls if c["run"] == run and c["tool"] == "r" and c["request"] != "1"]
    r1 = [r for r in rr if True]
    a = [r for r in reqs if r["run"] == run and r["request"] == "1"][0]
    c1r = [c for c in calls if c["run"] == run and c["request"] == "1"][0]
    print(run, "large bindings in dead branch:", nb, "req2/3 gaps:", [round(x, 2) for x in g],
          "gap per binding per pass:", [round(x / (2 * nb), 2) for x in g],
          "req1 post-provider:", round(float(a["gptr_after_provider_s"]), 2),
          "per binding:", round(float(a["gptr_after_provider_s"]) / nb, 2),
          "req1 internal-minus-read:", round(float(c1r["internal_minus_read_s"]), 2))
