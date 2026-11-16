"""Phase analysis of drive.R runs: per-request phases and per-call transport hops.
Usage: python3 -I analyze.py <cli> <run dir> [<run dir> ...]  -> JSON summary on stdout."""
import glob
import json
import statistics
import sys

cli = sys.argv[1]
dirs = sys.argv[2:]


def med(x):
    x = [v for v in x if v is not None]
    return round(statistics.median(x), 4) if x else None


def p90(x):
    x = sorted(v for v in x if v is not None)
    return round(x[min(len(x) - 1, int(0.9 * len(x)))], 4) if x else None


req_phases = {}
calls = {k: [] for k in ("rtt", "hop_in", "fifo_wait", "pre_start", "outer", "post_end",
                         "hop_out", "in_session")}
hs = {k: [] for k in ("relay_or_init_first", "initialized_rtt", "toolslist_rtt")}
for d in dirs:
    marks = json.load(open(d + "/marks.json"))
    events = json.load(open(d + "/events.json"))
    fake = []
    for f in glob.glob(d + "/fake.jsonl.*"):
        fake += [json.loads(l) for l in open(f)]
    reqs = sorted({m["req"] for m in marks if m["req"] > 0})
    for r in reqs:
        M = [m for m in marks if m["req"] == r]

        def first(fn, stage="enter", info=None, after=-1e18):
            for m in M:
                if m["fn"] == fn and m["stage"] == stage and m["t"] >= after and (
                        info is None or m.get("info") == info):
                    return m["t"]
            return None

        def last(fn, stage="exit"):
            v = [m["t"] for m in M if m["fn"] == fn and m["stage"] == stage]
            return v[-1] if v else None

        t_in, t_out = first("request"), first("request", "exit")
        F = [x for x in fake if t_in <= x["t"] <= t_out]
        ph = {}
        spawn_in = first("stream_process_start")
        spawn_out = first("stream_process_start", "exit")
        ph["request_to_spawn_s"] = (spawn_in - t_in) if spawn_in else None
        ph["run_start_s"] = (first("run_start", "exit") - first("run_start")) if first("run_start") else None
        ph["spawn_call_s"] = (spawn_out - spawn_in) if spawn_in else None
        proc = [x for x in F if x["kind"] == "proc_start"]
        if spawn_out and proc:
            ph["spawn_to_fake_main_s"] = proc[0]["t_proc"] - spawn_out
        rpcs = [x for x in F if x["kind"] == "rpc"]
        if cli == "codex":
            rs = [x for x in F if x["kind"] == "relay_spawn"]
            init = [x for x in rpcs if x["label"] == "initialize"]
            if rs and init:
                ph["relay_spawn_to_initialize_answer_s"] = init[0]["t_recv"] - rs[0]["t"]
                hs["relay_or_init_first"].append(ph["relay_spawn_to_initialize_answer_s"])
            hd = [x for x in F if x["kind"] == "handshake_done"]
            if init and hd:
                ph["rest_of_handshake_s"] = hd[0]["t"] - init[0]["t_recv"]
            tl = [x for x in rpcs if x["label"] == "tools/list"]
            if tl:
                hs["toolslist_rtt"].append(tl[0]["t_recv"] - tl[0]["t_send"])
        else:
            init = [x for x in rpcs if x["label"] == "initialize"]
            hd = [x for x in F if x["kind"] == "handshake_done"]
            ir = [x for x in F if x["kind"] == "initialize_received"]
            if ir and hd:
                ph["handshake_s"] = hd[0]["t"] - ir[0]["t"]
            if proc and ir:
                ph["fake_start_to_initialize_received_s"] = ir[0]["t"] - proc[0]["t_proc"]
        tc = [x for x in rpcs if x["label"] == "tools/call"]
        ph["n_calls"] = len(tc)
        if tc:
            ph["calls_total_s"] = tc[-1]["t_recv"] - tc[0]["t_send"]
        # per call: match session marks inside [t_send, t_recv]
        for c in tc:
            a, b = c["t_send"], c["t_recv"]
            W = [m for m in M if a <= m["t"] <= b]
            E = [e for e in events if a <= e["t"] <= b]

            def w(fn, stage="enter", info=None):
                for m in W:
                    if m["fn"] == fn and m["stage"] == stage and (info is None or m.get("info") == info):
                        return m["t"]
                return None
            pick = w("pcli_mcp", "enter", "tools/call")
            pexit = w("pcli_mcp", "exit")
            disp = w("mcp_served_tools")
            ts = [e["t"] for e in E if e["type"] == "tool_execution_start"]
            te = [e["t"] for e in E if e["type"] == "tool_execution_end"]
            resp = [m["t"] for m in W if m["fn"] in ("write_utf8", "pcli_send") and m["stage"] == "exit"]
            resp = resp[-1] if resp else None
            calls["rtt"].append(b - a)
            if pick:
                calls["hop_in"].append(pick - a)
            if pexit and disp:
                calls["fifo_wait"].append(disp - pexit)
            if disp and ts:
                calls["pre_start"].append(ts[0] - disp)
            if ts and te:
                calls["outer"].append(te[0] - ts[0])
            if te and resp:
                calls["post_end"].append(resp - te[0])
            if resp:
                calls["hop_out"].append(b - resp)
            if pick and resp:
                calls["in_session"].append(resp - pick)
        done = [x for x in F if x["kind"] in ("turn_completed", "turn_done")]
        if tc and done:
            ph["last_call_to_turn_completed_s"] = done[0]["t"] - tc[-1]["t_recv"]
        end_in = first("pcli_codex_end") if cli == "codex" else first("pcli_done")
        if done and end_in:
            ph["turn_completed_to_session_sees_it_s"] = end_in - done[0]["t"]
        if end_in:
            ph["turn_end_processing_to_request_exit_s"] = t_out - end_in
        settle = first("run_settle")
        if settle:
            ph["run_settle_s"] = first("run_settle", "exit") - settle
        ph["request_wall_s"] = t_out - t_in
        key = "req1" if r == 1 else "req2plus"
        for k, v in ph.items():
            req_phases.setdefault(key, {}).setdefault(k, []).append(v)

summary = dict(cli=cli, runs=dirs,
               per_request={k: {p: med(v) for p, v in d.items()} for k, d in req_phases.items()},
               per_request_n={k: len(d["request_wall_s"]) for k, d in req_phases.items()},
               per_call_median={k: med(v) for k, v in calls.items()},
               per_call_p90={k: p90(v) for k, v in calls.items()},
               per_call_n=len(calls["rtt"]),
               handshake_median={k: med(v) for k, v in hs.items()})
print(json.dumps(summary, indent=1))
