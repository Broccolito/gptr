"""Decompose A1 (gptr) vs C1 (Codex) time in the T03 gptr 1.0.1 batch from the published traces.

Usage: python3 -I analyze_t03.py <bench-repo-root> <out-dir>
Reads only; writes CSVs into <out-dir>.
"""
import csv
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
T03 = ROOT / "biomedical/v0.5/reports/T03"
REPLAY = T03 / "replay"


def union(intervals):
    """Total length of the union of [a, b] intervals."""
    iv = sorted((a, b) for a, b in intervals if b > a)
    total, cur_a, cur_b = 0.0, None, None
    for a, b in iv:
        if cur_b is None or a > cur_b:
            if cur_b is not None:
                total += cur_b - cur_a
            cur_a, cur_b = a, b
        else:
            cur_b = max(cur_b, b)
    if cur_b is not None:
        total += cur_b - cur_a
    return total


def clip(intervals, lo, hi):
    return [(max(a, lo), min(b, hi)) for a, b in intervals if min(b, hi) > max(a, lo)]


def minus(a_intervals, b_intervals):
    """Length of union(a) minus its overlap with union(b)."""
    ua = union(a_intervals)
    inter = []
    for a0, a1 in a_intervals:
        for b0, b1 in b_intervals:
            lo, hi = max(a0, b0), min(a1, b1)
            if hi > lo:
                inter.append((lo, hi))
    return ua - union(inter)


def jsonl(path):
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def write_csv(name, rows):
    if not rows:
        return
    keys = list(rows[0].keys())
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(OUT / name, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


# ---------------------------------------------------------------- A1
a1_calls, a1_reqs = [], []
for trial in (1, 2, 3):
    run = f"A1-{trial}"
    ev = jsonl(REPLAY / run / "trace.jsonl")
    io = jsonl(REPLAY / run / "io.jsonl")
    tsv_reads = [(e["started_unix"], e["finished_unix"]) for e in io
                 if e["operation"] == "fread" and e["file"].endswith(".tsv")]
    reqs = {}
    starts = {}
    for e in ev:
        d, t = e["data"], e["type"]
        r = reqs.setdefault(e["turn"], {"calls": []})
        if t == "request_start":
            r["start"] = d["unix"]
        elif t == "request_end":
            r["end"] = d["unix"]
        elif t == "message_end" and d["role"] == "user":
            r["user_msg"] = d["ts"]
        elif t == "message_end" and d["role"] == "assistant":
            r["asst_msg"] = d["ts"]
        elif t == "usage":
            r["usage_ts"] = d["ts"]
            r["provider_s"] = d["row"][0]["seconds"]
        elif t == "tool_execution_start":
            starts[(e["turn"], d["tool_call_id"])] = (d["ts"], d["tool_name"])
        elif t == "tool_execution_end":
            s_ts, name = starts[(e["turn"], d["tool_call_id"])]
            r["calls"].append(dict(start=s_ts, end=d["ts"], tool=name, elapsed=d["elapsed"],
                                   call_id=d["tool_call_id"]))
    for turn, r in sorted(reqs.items()):
        calls = sorted(r["calls"], key=lambda c: c["start"])
        for c in calls:
            outer = c["end"] - c["start"]
            internal = c["elapsed"]
            int_start = c["end"] - internal
            read = union(clip(tsv_reads, int_start, c["end"]))
            read_outer = union(clip(tsv_reads, c["start"], c["end"]))
            a1_calls.append(dict(run=run, request=turn, tool=c["tool"], call_id=c["call_id"],
                                 outer_s=outer, internal_s=internal, gap_s=outer - internal,
                                 gap_share=(outer - internal) / outer if outer else None,
                                 input_read_s=read, input_read_outside_internal_s=read_outer - read,
                                 internal_minus_read_s=internal - read,
                                 since_request_start_s=c["start"] - r["start"]))
        wall = r["end"] - r["start"]
        provider_start = r["usage_ts"] - r["provider_s"]
        sum_outer = sum(c["end"] - c["start"] for c in calls)
        sum_internal = sum(c["elapsed"] for c in calls)
        between = [calls[i + 1]["start"] - calls[i]["end"] for i in range(len(calls) - 1)]
        read = union(clip(tsv_reads, r["start"], r["end"]))
        a1_reqs.append(dict(
            arm="A1", run=run, request=turn, wall_s=wall, tool_calls=len(calls),
            first_call_after_s=calls[0]["start"] - r["start"],
            between_calls_s=sum(between), n_between=len(between),
            after_last_call_s=r["end"] - calls[-1]["end"],
            sum_tool_outer_s=sum_outer, sum_tool_internal_s=sum_internal,
            gptr_gap_s=sum_outer - sum_internal, input_read_s=read,
            r_internal_minus_read_s=sum_internal - read,
            # A1-only boundaries
            gptr_before_provider_s=provider_start - r["start"],
            provider_s=r["provider_s"],
            model_cli_relay_in_provider_s=r["provider_s"] - sum_outer,
            provider_start_to_first_call_s=calls[0]["start"] - provider_start,
            last_call_to_provider_end_s=r["usage_ts"] - calls[-1]["end"],
            gptr_after_provider_s=r["end"] - r["usage_ts"],
            user_msg_after_start_s=r["user_msg"] - r["start"],
            first_r_internal_start_after_s=min(c["end"] - c["elapsed"] for c in calls if c["tool"] == "r") - r["start"],
            after_last_r_end_s=r["end"] - max(c["end"] for c in calls if c["tool"] == "r"),
        ))

# ---------------------------------------------------------------- C1
c1_calls, c1_cmds, c1_reqs = [], [], []
TOOL_RE = re.compile(r"tools\.(\w+)\(")
for trial in (1, 2, 3):
    run = f"C1-{trial}"
    ev = jsonl(REPLAY / run / "trace.jsonl")
    io = jsonl(REPLAY / run / "io.jsonl")
    tsv_reads = [(e["started_unix"], e["finished_unix"]) for e in io
                 if e["operation"] == "fread" and e["file"].endswith(".tsv")]
    rscripts = [(e["started_unix"], e["finished_unix"], e["file"]) for e in io
                if e["operation"] == "rscript"]
    reqs, calls, outs, cmd_start, cmd_end = {}, {}, {}, {}, {}
    model_responses = {}
    cur = 0
    for e in ev:
        t = e["type"]
        if t == "request_start":
            cur = e["turn"]
            reqs[cur] = {"start": e["data"]["unix"]}
            continue
        if t == "request_end":
            reqs[e["turn"]]["end"] = e["data"]["unix"]
            continue
        if t != "app_server_event":
            continue
        m = e["data"]["message"]
        meth = m.get("method")
        p = m.get("params") or {}
        em = (m.get("emittedAtMs") or 0) / 1000
        it = p.get("item") if isinstance(p, dict) else None
        if meth == "rawResponse/completed":
            model_responses[cur] = model_responses.get(cur, 0) + 1
        if meth == "rawResponseItem/completed" and isinstance(it, dict):
            if it.get("type") == "custom_tool_call":
                calls[it["call_id"]] = dict(req=cur, call=em, inner=TOOL_RE.findall(it["input"]))
            elif it.get("type") == "custom_tool_call_output":
                outs[it["call_id"]] = em
        if meth in ("item/started", "item/completed") and isinstance(it, dict) and \
                it.get("type") == "commandExecution":
            if meth == "item/started":
                cmd_start[it["id"]] = (p.get("startedAtMs", m.get("emittedAtMs")) / 1000, it["command"], cur)
            else:
                cmd_end[it["id"]] = (p.get("completedAtMs", m.get("emittedAtMs")) / 1000, it.get("durationMs"))
    for cid, c in calls.items():
        c["out"] = outs[cid]
    for turn, r in sorted(reqs.items()):
        rc = sorted([c for c in calls.values() if c["req"] == turn], key=lambda c: c["call"])
        inner = [x for c in rc for x in c["inner"]]
        rs = [(a, b) for a, b, _ in rscripts if a >= r["start"] and b <= r["end"]]
        for c in rc:
            c1_calls.append(dict(run=run, request=turn, inner="+".join(c["inner"]),
                                 outer_s=c["out"] - c["call"],
                                 rscript_overlap_s=union(clip(rs, c["call"], c["out"])),
                                 since_request_start_s=c["call"] - r["start"]))
        between = [rc[i + 1]["call"] - rc[i]["out"] for i in range(len(rc) - 1)]
        tool_iv = [(c["call"], c["out"]) for c in rc]
        read = union(clip(tsv_reads, r["start"], r["end"]))
        rs_union = union(rs)
        cmds = [(cid, *cmd_start[cid], *cmd_end.get(cid, (None, None))) for cid in cmd_start
                if cmd_start[cid][2] == turn]
        for cid, s, cmd, _, e_, dur in cmds:
            inside = [(a, b) for a, b in rs if a >= s - 0.5 and b <= (e_ or 0) + 0.5]
            rspan = sum(b - a for a, b in inside)
            c1_cmds.append(dict(run=run, request=turn, command=cmd[:90], cmd_span_s=(e_ - s) if e_ else None,
                                duration_ms=dur, rscript_process_s=rspan if inside else None,
                                overhead_around_rscript_s=((e_ - s) - rspan) if inside and e_ else None,
                                launch_to_r_start_s=(inside[0][0] - s) if inside else None,
                                r_end_to_cmd_end_s=(e_ - inside[-1][1]) if inside and e_ else None))
        # detection latency: R process finished -> first tool output after it
        detect = []
        for a, b in rs:
            later = [c["out"] for c in rc if c["out"] >= b]
            if later:
                detect.append(min(later) - b)
        c1_reqs.append(dict(
            arm="C1", run=run, request=turn, wall_s=r["end"] - r["start"],
            tool_calls=len(inner), outer_wrapper_calls=len(rc),
            inner_counts=json.dumps({k: inner.count(k) for k in sorted(set(inner))}),
            first_call_after_s=rc[0]["call"] - r["start"],
            between_calls_s=sum(between), n_between=len(between),
            after_last_call_s=r["end"] - rc[-1]["out"],
            sum_tool_outer_s=sum(c["out"] - c["call"] for c in rc),
            tool_union_s=union(tool_iv),
            rscript_process_s=rs_union, input_read_s=read,
            r_nonread_s=rs_union - read,
            tool_outside_rscript_s=minus(tool_iv, rs),
            rscript_outside_tool_calls_s=minus(rs, tool_iv),
            model_responses=model_responses.get(turn, 0),
            r_end_to_observed_s=sum(detect),
            first_r_internal_start_after_s=min(a for a, b in rs) - r["start"],
            after_last_r_end_s=r["end"] - max(b for a, b in rs),
        ))

# ------------------------------------------------- exclusive per-request decomposition
decomp = []
for r in a1_reqs:
    decomp.append(dict(arm="A1", run=r["run"], request=r["request"], wall_s=r["wall_s"],
                       input_read_s=r["input_read_s"],
                       r_compute_s=r["r_internal_minus_read_s"],  # includes checkpoint_after
                       tool_overhead_s=r["gptr_gap_s"],
                       model_harness_s=r["wall_s"] - r["sum_tool_outer_s"]))
for r in c1_reqs:
    tool_over = r["tool_outside_rscript_s"]
    decomp.append(dict(arm="C1", run=r["run"], request=r["request"], wall_s=r["wall_s"],
                       input_read_s=r["input_read_s"], r_compute_s=r["r_nonread_s"],
                       tool_overhead_s=tool_over,
                       model_harness_s=r["wall_s"] - r["rscript_process_s"] - tool_over))

# --------------------------------------------- run totals and counterfactual
attempts = {(row["arm"], int(row["trial"])): row for row in
            csv.DictReader(open(T03 / "gptr-1.0.1/figures/all-attempts.csv"))}
c1_r_over = [c["overhead_around_rscript_s"] for c in c1_cmds if c["overhead_around_rscript_s"] is not None]
c1_nonr_outer = [c["outer_s"] for c in c1_calls if c["rscript_overlap_s"] == 0 and "write_stdin" not in c["inner"]]
c1_level = med(c1_r_over)
runs = []
for arm, reqs in (("A1", a1_reqs), ("C1", c1_reqs)):
    for trial in (1, 2, 3):
        run = f"{arm}-{trial}"
        rr = [r for r in reqs if r["run"] == run]
        dd = [d for d in decomp if d["run"] == run]
        wall = float(attempts[(arm, trial)]["wall_s"])
        row = dict(arm=arm, run=run, wall_s=wall,
                   outside_requests_s=wall - sum(r["wall_s"] for r in rr),
                   tool_calls=sum(r["tool_calls"] for r in rr),
                   input_read_s=sum(d["input_read_s"] for d in dd),
                   r_compute_s=sum(d["r_compute_s"] for d in dd),
                   tool_overhead_s=sum(d["tool_overhead_s"] for d in dd),
                   model_harness_in_requests_s=sum(d["model_harness_s"] for d in dd),
                   first_call_after_s=sum(r["first_call_after_s"] for r in rr),
                   between_calls_s=sum(r["between_calls_s"] for r in rr),
                   after_last_call_s=sum(r["after_last_call_s"] for r in rr))
        if arm == "A1":
            calls = [c for c in a1_calls if c["run"] == run]
            excess = sum(max(0.0, c["gap_s"] - c1_level) for c in calls)
            row.update(gptr_before_provider_s=sum(r["gptr_before_provider_s"] for r in rr),
                       gptr_after_provider_s=sum(r["gptr_after_provider_s"] for r in rr),
                       model_cli_relay_s=sum(r["model_cli_relay_in_provider_s"] for r in rr),
                       gap_excess_over_c1_level_s=excess,
                       counterfactual_wall_s=wall - excess)
        runs.append(row)

write_csv("t03_a1_calls.csv", a1_calls)
write_csv("t03_c1_calls.csv", c1_calls)
write_csv("t03_c1_commands.csv", c1_cmds)
write_csv("t03_requests.csv", a1_reqs + c1_reqs)
write_csv("t03_decomposition_requests.csv", decomp)
write_csv("t03_runs.csv", runs)


def show(title, rows, keys):
    print(f"\n## {title}")
    print(" | ".join(keys))
    for r in rows:
        print(" | ".join(f"{r.get(k):.2f}" if isinstance(r.get(k), float) else str(r.get(k, "")) for k in keys))


show("A1 calls", a1_calls, ["run", "request", "tool", "outer_s", "internal_s", "gap_s", "gap_share",
                            "input_read_s", "internal_minus_read_s", "since_request_start_s"])
show("A1 requests", a1_reqs, ["run", "request", "wall_s", "tool_calls", "first_call_after_s",
                              "between_calls_s", "after_last_call_s", "sum_tool_outer_s",
                              "gptr_gap_s", "gptr_before_provider_s", "provider_s",
                              "model_cli_relay_in_provider_s", "provider_start_to_first_call_s",
                              "last_call_to_provider_end_s", "gptr_after_provider_s"])
show("C1 requests", c1_reqs, ["run", "request", "wall_s", "tool_calls", "outer_wrapper_calls",
                              "inner_counts", "first_call_after_s", "between_calls_s", "n_between",
                              "after_last_call_s", "sum_tool_outer_s", "rscript_process_s",
                              "input_read_s", "tool_outside_rscript_s", "model_responses",
                              "r_end_to_observed_s"])
show("C1 commands", c1_cmds, ["run", "request", "command", "cmd_span_s", "rscript_process_s",
                              "overhead_around_rscript_s", "launch_to_r_start_s", "r_end_to_cmd_end_s"])
show("Time to first R start and after last R end", a1_reqs + c1_reqs,
     ["arm", "run", "request", "wall_s", "first_r_internal_start_after_s", "after_last_r_end_s"])
show("Decomposition per request", decomp, ["arm", "run", "request", "wall_s", "input_read_s",
                                           "r_compute_s", "tool_overhead_s", "model_harness_s"])
show("Runs", runs, list(runs[0].keys()))
show("A1 runs extra", [r for r in runs if r["arm"] == "A1"],
     ["run", "gptr_before_provider_s", "gptr_after_provider_s", "model_cli_relay_s",
      "gap_excess_over_c1_level_s", "counterfactual_wall_s"])
print("\nC1 per-command overhead around Rscript (median, min, max):",
      c1_level, min(c1_r_over), max(c1_r_over), "n=", len(c1_r_over))
print("C1 non-R, non-poll wrapper call outer (median, min, max):",
      med(c1_nonr_outer), min(c1_nonr_outer), max(c1_nonr_outer), "n=", len(c1_nonr_outer))
polls = [c["outer_s"] for c in c1_calls if c["inner"] == "write_stdin"]
print("C1 poll call outer (median, min, max):", med(polls), min(polls), max(polls), "n=", len(polls))
poll_gaps = []
for run in ("C1-1", "C1-2", "C1-3"):
    rows = [c for c in c1_calls if c["run"] == run]
    for i in range(len(rows) - 1):
        if rows[i + 1]["inner"] == "write_stdin" and rows[i + 1]["request"] == rows[i]["request"]:
            poll_gaps.append(rows[i + 1]["since_request_start_s"] - rows[i]["since_request_start_s"] - rows[i]["outer_s"])
print("C1 model turnaround before a poll (median, min, max):", med(poll_gaps), min(poll_gaps), max(poll_gaps), "n=", len(poll_gaps))
gaps = [c["gap_s"] for c in a1_calls if c["tool"] == "r"]
print("A1 r-call gaps:", [round(g, 2) for g in gaps])


def arm_median(key, arm):
    return med([r[key] for r in runs if r["arm"] == arm and key in r])


print("\n## Median per arm")
for key in ["wall_s", "outside_requests_s", "tool_calls", "input_read_s", "r_compute_s", "tool_overhead_s",
            "model_harness_in_requests_s", "first_call_after_s", "between_calls_s", "after_last_call_s",
            "gptr_before_provider_s", "gptr_after_provider_s", "model_cli_relay_s",
            "gap_excess_over_c1_level_s", "counterfactual_wall_s"]:
    print(key, arm_median(key, "A1"), arm_median(key, "C1"))
print("\n## Mean per arm (additive)")
for key in ["wall_s", "outside_requests_s", "input_read_s", "r_compute_s", "tool_overhead_s",
            "model_harness_in_requests_s", "counterfactual_wall_s"]:
    a = [r[key] for r in runs if r["arm"] == "A1" and key in r]
    c = [r[key] for r in runs if r["arm"] == "C1" and key in r]
    print(key, statistics.mean(a) if a else None, statistics.mean(c) if c else None)
print("\n## Median per arm and request")
for arm, reqs in (("A1", a1_reqs), ("C1", c1_reqs)):
    for q in (1, 2, 3):
        rr = [r for r in reqs if r["request"] == q]
        dd = [d for d in decomp if d["arm"] == arm and d["request"] == q]
        print(arm, q, "wall", round(med([r["wall_s"] for r in rr]), 2),
              "first", round(med([r["first_call_after_s"] for r in rr]), 2),
              "between", round(med([r["between_calls_s"] for r in rr]), 2),
              "after", round(med([r["after_last_call_s"] for r in rr]), 2),
              "read", round(med([d["input_read_s"] for d in dd]), 2),
              "rcomp", round(med([d["r_compute_s"] for d in dd]), 2),
              "toolover", round(med([d["tool_overhead_s"] for d in dd]), 2),
              "modelharn", round(med([d["model_harness_s"] for d in dd]), 2))
