"""T08 per-call gaps (gptr 1.0.0, numeric peak matrices), T01 median-run spans, and T03 A1
request 2/3 tool time across gptr versions. Usage: python3 -I analyze_other.py <bench-root> <out-dir>"""
import csv
import json
import statistics
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
V5 = ROOT / "biomedical/v0.5"
T08 = V5 / "docs/t08-results-rmd"


def union(iv):
    iv = sorted((a, b) for a, b in iv if b > a)
    tot, ca, cb = 0.0, None, None
    for a, b in iv:
        if cb is None or a > cb:
            if cb is not None:
                tot += cb - ca
            ca, cb = a, b
        else:
            cb = max(cb, b)
    return tot + (cb - ca if cb is not None else 0.0)


def clip(iv, lo, hi):
    return [(max(a, lo), min(b, hi)) for a, b in iv if min(b, hi) > max(a, lo)]


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def write_csv(name, rows):
    keys = []
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(OUT / name, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})


def show(title, rows, keys=None):
    keys = keys or list(rows[0].keys())
    print(f"\n## {title}")
    print(" | ".join(keys))
    for r in rows:
        print(" | ".join(f"{r.get(k):.2f}" if isinstance(r.get(k), float) else str(r.get(k, "")) for k in keys))


# ------------------------------------------------------------------ T08
events = [json.loads(l) for l in open(T08 / "trace/key-events.jsonl")]
intervals = list(csv.DictReader(open(T08 / "trace/all-run-intervals.csv")))
attempts = {(r["arm"], int(r["trial"])): r for r in csv.DictReader(open(T08 / "data/all-attempts.csv"))}
reqwin = {}
for r in intervals:
    if r["kind"] == "request":
        reqwin[(r["arm"], int(r["trial"]), int(r["request"]))] = (float(r["started_unix"]), float(r["finished_unix"]))
reads = {}
for r in intervals:
    if r["kind"] == "read":
        reads.setdefault((r["arm"], int(r["trial"])), []).append((float(r["started_unix"]), float(r["finished_unix"])))

t08_a1_calls, t08_req = [], []
starts = {}
for e in events:
    if e["arm"] != "A1":
        continue
    if e["type"] == "tool_execution_start":
        starts[(e["trial"], e["request"], e["tool_call_id"])] = e["ts"]
    elif e["type"] == "tool_execution_end":
        s = starts[(e["trial"], e["request"], e["tool_call_id"])]
        outer = e["ts"] - s
        el = e["elapsed"]
        rd = union(clip(reads.get(("A1", e["trial"]), []), s, e["ts"]))
        t08_a1_calls.append(dict(run=f"A1-{e['trial']}", request=e["request"], tool=e["tool_name"],
                                 start=s, end=e["ts"], outer_s=outer, internal_s=el,
                                 gap_s=(outer - el) if el is not None else None, read_s=rd))
# C1 commands and rscripts
cmd_s, cmd_e, rscripts = {}, {}, {}
for e in events:
    if e["arm"] != "C1":
        continue
    if e["type"] == "app_server_event" and e.get("item_type") == "commandExecution":
        if e["method"] == "item/started":
            cmd_s[(e["trial"], e["item_id"])] = (e.get("startedAtMs") or e["emittedAtMs"]) / 1000
        else:
            cmd_e[(e["trial"], e["item_id"])] = (e.get("completedAtMs") or e["emittedAtMs"]) / 1000
    if e["type"] == "io" and e["operation"] == "rscript":
        rscripts.setdefault(e["trial"], []).append((e["started_unix"], e["finished_unix"]))
t08_c1_cmds = []
for (trial, iid), s in cmd_s.items():
    e_ = cmd_e.get((trial, iid))
    inside = [(a, b) for a, b in rscripts.get(trial, []) if e_ and a >= s - 0.5 and b <= e_ + 0.5]
    t08_c1_cmds.append(dict(run=f"C1-{trial}", cmd_span_s=(e_ - s) if e_ else None,
                            rscript_s=sum(b - a for a, b in inside) if inside else None,
                            overhead_s=((e_ - s) - sum(b - a for a, b in inside)) if inside and e_ else None))
c1_calls = {}
for r in csv.DictReader(open(T08 / "trace/tool-calls.csv")):
    if r["arm"] != "C1":
        continue
    ts = datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")).timestamp()
    c1_calls.setdefault(int(r["trial"]), []).append((ts, r["name"], int(r["inner_index"] or 1)))
for (arm, trial, q), (a, b) in sorted(reqwin.items()):
    if arm == "A1":
        cc = sorted([c for c in t08_a1_calls if c["run"] == f"A1-{trial}" and c["request"] == q], key=lambda c: c["start"])
        t08_req.append(dict(arm=arm, run=f"{arm}-{trial}", request=q, wall_s=b - a, calls=len(cc),
                            first_call_after_s=cc[0]["start"] - a,
                            between_calls_s=sum(cc[i + 1]["start"] - cc[i]["end"] for i in range(len(cc) - 1)),
                            after_last_call_s=b - cc[-1]["end"],
                            sum_outer_s=sum(c["outer_s"] for c in cc),
                            sum_gap_s=sum(c["gap_s"] or 0 for c in cc if c["tool"] != "codex_shell"),
                            read_s=union(clip(reads.get(("A1", trial), []), a, b))))
    else:
        cc = sorted([c for c in c1_calls.get(trial, []) if a <= c[0] <= b])
        rs = [(x, y) for x, y in rscripts.get(trial, []) if x >= a and y <= b]
        t08_req.append(dict(arm=arm, run=f"{arm}-{trial}", request=q, wall_s=b - a, calls=len(cc),
                            first_call_after_s=cc[0][0] - a,
                            call_start_to_call_start_median_s=med([cc[i + 1][0] - cc[i][0] for i in range(len(cc) - 1)
                                                                   if cc[i + 1][0] > cc[i][0]]),
                            after_last_call_start_s=b - cc[-1][0],
                            rscript_s=union(rs), read_s=union(clip(reads.get(("C1", trial), []), a, b))))
write_csv("t08_a1_calls.csv", t08_a1_calls)
write_csv("t08_c1_commands.csv", t08_c1_cmds)
write_csv("t08_requests.csv", t08_req)
show("T08 A1 calls (gptr 1.0.0)", t08_a1_calls, ["run", "request", "tool", "outer_s", "internal_s", "gap_s", "read_s"])
show("T08 C1 commands", t08_c1_cmds)
show("T08 requests", t08_req)
r_gaps_2_3 = [c["gap_s"] for c in t08_a1_calls if c["tool"] == "r" and c["request"] > 1]
r_gaps_1 = [c["gap_s"] for c in t08_a1_calls if c["tool"] == "r" and c["request"] == 1]
print("T08 A1 r gaps req1:", [round(x, 2) for x in r_gaps_1], "req2/3:", [round(x, 2) for x in r_gaps_2_3],
      "median req2/3:", med(r_gaps_2_3))
c1o = [c["overhead_s"] for c in t08_c1_cmds if c["overhead_s"] is not None]
print("T08 C1 per-Rscript overhead median/min/max:", med(c1o), min(c1o), max(c1o), len(c1o))
excess = {}
for c in t08_a1_calls:
    if c["gap_s"] is not None:
        excess[c["run"]] = excess.get(c["run"], 0) + max(0.0, c["gap_s"] - med(c1o))
for run, x in sorted(excess.items()):
    w = float(attempts[("A1", int(run[-1]))]["wall_s"])
    print("T08", run, "wall", round(w, 2), "gap excess", round(x, 2), "counterfactual", round(w - x, 2))

# ------------------------------------------------------------------ T01 (median runs only)
tl = list(csv.DictReader(open(V5 / "docs/t01-results-current/timeline.csv")))
t01 = []
for arm in ("A1", "C1"):
    reqs = [(float(r["start"]), float(r["finish"]), r["label"]) for r in tl if r["arm"] == arm and r["kind"] == "request"]
    ex = [(float(r["start"]), float(r["finish"])) for r in tl if r["arm"] == arm and r["kind"] == "execution"]
    rd = [(float(r["start"]), float(r["finish"])) for r in tl if r["arm"] == arm and r["kind"] == "read"]
    for a, b, lab in reqs:
        e_in = [(x, y) for x, y in ex if x >= a and y <= b]
        t01.append(dict(arm=arm, request=lab, wall_s=b - a, executions=len(e_in),
                        execution_spans_s=" ".join(f"{y - x:.2f}" for x, y in e_in),
                        execution_union_s=union(e_in), read_s=union(clip(rd, a, b)),
                        first_exec_after_s=(e_in[0][0] - a) if e_in else None,
                        after_last_exec_s=(b - e_in[-1][1]) if e_in else None))
    pre = [(x, y) for x, y in rd if x < reqs[0][0]]
    if pre:
        print(f"T01 {arm} read before first request (dataset preload):", [round(y - x, 2) for x, y in pre])
write_csv("t01_median_run_requests.csv", t01)
show("T01 median-run (trial 3) request spans", t01)

# --------------------------------------- T03 A1 tool_nonread by request across gptr versions
ver = []
for label, d in (("1.0.0 dev29", "gptr-1.0.0-dev29"), ("1.0.0 dev30", "gptr-1.0.0-dev30"), ("1.0.1", "gptr-1.0.1")):
    rows = list(csv.DictReader(open(V5 / "reports/T03" / d / "figures/request-stages.csv")))
    att = list(csv.DictReader(open(V5 / "reports/T03" / d / "figures/all-attempts.csv")))
    for arm in ("A1", "C1"):
        for q in ("1", "2", "3"):
            sel = [r for r in rows if r["arm"] == arm and r["request"] == q]
            ver.append(dict(batch=label, arm=arm, request=int(q),
                            tool_nonread_s=" ".join(f"{float(r['tool_nonread_s']):.2f}" for r in sel),
                            tool_nonread_median_s=med([float(r["tool_nonread_s"]) for r in sel]),
                            harness_model_median_s=med([float(r["harness_model_s"]) for r in sel]),
                            wall_median_s=med([float(r["wall_s"]) for r in sel])))
        ver.append(dict(batch=label, arm=arm, request="run",
                        wall_median_s=med([float(r["wall_s"]) for r in att if r["arm"] == arm]),
                        tool_nonread_median_s=med([float(r["tool_nonread_s"]) for r in att if r["arm"] == arm]),
                        harness_model_median_s=med([float(r["harness_model_s"]) for r in att if r["arm"] == arm])))
write_csv("t03_versions.csv", ver)
show("T03 tool_nonread / harness by gptr version (benchmark's request-stages)", ver)
