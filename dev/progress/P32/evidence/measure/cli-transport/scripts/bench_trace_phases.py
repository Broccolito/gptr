"""Per-request phases of the published T03 traces (A1 gptr+codex exec, C1 codex app-server).
Times in seconds from the trace's own clock. Prints a CSV."""
import json
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = []
for arm in ("A1", "C1"):
    for k in (1, 2, 3):
        ev = [json.loads(l) for l in open(root / f"{arm}-{k}" / "trace.jsonl")]
        for r in (1, 2, 3):
            E = [e for e in ev if e["turn"] == r]
            t = lambda e: e["time_ms"] / 1000
            start = next(t(e) for e in E if e["type"] == "request_start")
            end = next(t(e) for e in E if e["type"] == "request_end")
            if arm == "A1":
                user = next(t(e) for e in E if e["type"] == "message_end" and e["data"].get("message", {}).get("role") == "user")
                ts = [t(e) for e in E if e["type"] == "tool_execution_start"]
                te = [t(e) for e in E if e["type"] == "tool_execution_end"]
                asst = [t(e) for e in E if e["type"] == "message_end" and e["data"].get("message", {}).get("role") == "assistant"][-1]
                rows.append(dict(arm=arm, trial=k, req=r, wall=end - start,
                                 pre_turn=user - start, to_first_tool=ts[0] - start,
                                 tool_outer_sum=sum(b - a for a, b in zip(ts, te)),
                                 last_tool_end_to_reply=asst - te[-1], post_turn=end - asst))
            else:
                msgs = [(t(e), e["data"]["message"]) for e in E if e["type"] == "app_server_event"]
                ts_turn = next(x for x, m in msgs if m.get("method") == "turn/started")
                done = next(x for x, m in msgs if m.get("method") == "turn/completed")
                cmds_s = [x for x, m in msgs if m.get("method") == "item/started" and m["params"]["item"]["type"] == "commandExecution"]
                cmds_e = [x for x, m in msgs if m.get("method") == "item/completed" and m["params"]["item"]["type"] == "commandExecution"]
                rows.append(dict(arm=arm, trial=k, req=r, wall=end - start, pre_turn=ts_turn - start,
                                 to_first_tool=cmds_s[0] - start,
                                 tool_outer_sum=sum(b - a for a, b in zip(cmds_s, cmds_e)),
                                 last_tool_end_to_reply=done - cmds_e[-1], post_turn=end - done))
keys = ["wall", "pre_turn", "to_first_tool", "tool_outer_sum", "last_tool_end_to_reply", "post_turn"]
print("arm,trial,req," + ",".join(keys))
for r in rows:
    print(f"{r['arm']},{r['trial']},{r['req']}," + ",".join(f"{r[k]:.3f}" for k in keys))
print("# medians over trials")
for arm in ("A1", "C1"):
    for q in (1, 2, 3):
        sel = [r for r in rows if r["arm"] == arm and r["req"] == q]
        print(f"{arm},median,{q}," + ",".join(f"{statistics.median(r[k] for r in sel):.3f}" for k in keys))
