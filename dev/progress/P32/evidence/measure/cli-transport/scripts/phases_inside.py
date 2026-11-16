"""In-session phase durations per request (median over runs) from drive.R marks: the pre-turn
(request -> spawn), the served call's segments, and the post-turn (CLI turn end -> request exit)
with the agent_end snapshot. Usage: python3 -I phases_inside.py <run dir> ..."""
import json
import statistics
import sys

out = {}
for d in sys.argv[1:]:
    m = json.load(open(d + "/marks.json"))
    ev = json.load(open(d + "/events.json"))
    for r in sorted({x["req"] for x in m if x["req"] > 0}):
        M = [x for x in m if x["req"] == r]
        E = [e for e in ev if e["req"] == r]

        def t(fn, stage="enter", k=0):
            v = [x["t"] for x in M if x["fn"] == fn and x["stage"] == stage]
            return v[k] if len(v) > abs(k) else None
        ph = {}
        ph["pre_turn_request_to_user_message_end"] = next(e["t"] for e in E if e["type"] == "message_end") - t("request")
        ph["request_to_spawn"] = t("stream_process_start") - t("request")
        ts = next(e["t"] for e in E if e["type"] == "tool_execution_start")
        te = next(e["t"] for e in E if e["type"] == "tool_execution_end")
        ph["call_outer"] = te - ts
        ph["call_start_to_tool_call_hook"] = t("tool_call_hook") - ts
        ph["call_gate"] = t("mcp_serve_gate", "exit") - t("mcp_serve_gate")
        ph["call_checkpoint_before"] = t("checkpoint_before", "exit") - t("checkpoint_before")
        ph["call_eval_mcp_serve_r"] = t("mcp_serve_r", "exit") - t("mcp_serve_r")
        ph["call_checkpoint_after"] = t("checkpoint_after", "exit") - t("checkpoint_after")
        end = t("pcli_codex_end")
        ph["post_turn_cli_end_to_request_exit"] = t("request", "exit") - end
        ph["agent_end_env_view_snapshot"] = t("env_view_snapshot", "exit", -1) - t("env_view_snapshot", "enter", -1)
        ph["ckpt_on_agent_end"] = t("ckpt_on_agent_end", "exit") - t("ckpt_on_agent_end")
        ph["request_wall"] = t("request", "exit") - t("request")
        for k, v in ph.items():
            out.setdefault(r, {}).setdefault(k, []).append(v)
print(json.dumps({f"req{r}": {k: round(statistics.median(v), 3) for k, v in d.items()}
                  for r, d in out.items()}, indent=1))
