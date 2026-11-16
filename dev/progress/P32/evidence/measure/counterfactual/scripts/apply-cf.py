import sys, pathlib
R = pathlib.Path(sys.argv[1])

def sub(fname, old, new):
    p = R / fname
    t = p.read_text()
    n = t.count(old)
    if n != 1:
        raise SystemExit(f"{fname}: pattern found {n} times: {old[:60]!r}")
    p.write_text(t.replace(old, new))
    print("patched", fname)

# (2) classify once: dispatch_steps keeps the first risk with its input; perm_decide reuses it
sub("agent-dispatch.R",
    "  call = tool_call_hook(run, call, call_risk(call, ctx, run))\n",
    "  r0 = call_risk(call, ctx, run)\n"
    "  if (cf_on(\"reuse\") && inherits(r0, \"gptr_risk\")) {\n"
    "    call$risk = r0\n"
    "    call$risk_input = call$input\n"
    "  }\n"
    "  call = tool_call_hook(run, call, r0)\n")
sub("agent-dispatch.R",
    "  snap = run$opts$safety %||% list()\n  risk = call_risk(call, ctx, run)\n",
    "  snap = run$opts$safety %||% list()\n"
    "  risk = if (cf_on(\"reuse\") && inherits(call$risk, \"gptr_risk\") &&\n"
    "             identical(call$risk_input, call$input)) call$risk else call_risk(call, ctx, run)\n")
sub("mcp-server.R",
    "              risk = risk, envir = env)\n",
    "              risk = risk, envir = env)\n"
    "  if (cf_on(\"reuse\")) call$risk_input = input\n")

# (3) size of overwritten bindings
sub("perm-classify.R",
    "  list(class = class(obj)[1L], bytes = env_snap_size(obj, home),\n",
    "  list(class = class(obj)[1L], bytes = cf_binding_bytes(obj, home),\n")

# (4) one size per object version shared by every snapshot holder
sub("env-snapshot.R",
    "    bytes[i] = if (reuse) {\n"
    "      previous$bytes[j]\n"
    "    } else {\n"
    "      env_snap_size(get(nms[i], envir = box$envir, inherits = FALSE), box$envir)\n"
    "    }\n",
    "    bytes[i] = if (reuse) {\n"
    "      previous$bytes[j]\n"
    "    } else if (cf_on(\"share\") && !is.null(cf_stash()[[cf_key(f)]])) {\n"
    "      cf_stash()[[cf_key(f)]]\n"
    "    } else {\n"
    "      env_snap_size(get(nms[i], envir = box$envir, inherits = FALSE), box$envir)\n"
    "    }\n"
    "    if (cf_stash_writes() && !is.na(bytes[i])) assign(cf_key(f), bytes[i], envir = cf_stash())\n")

# (5) reactor: a run task that just advanced the loop is due now, not in 5 ms
sub("agent-run.R",
    "  act = loop_next(run$loop)\n",
    "  act = loop_next(run$loop)\n"
    "  if (cf_on(\"reactor\") && !identical(act$action, \"wait\")) the$cf_hot = TRUE\n")
sub("http-reactor.R",
    "    res = reactor_run_task(t)\n",
    "    the$cf_hot = FALSE\n"
    "    res = reactor_run_task(t)\n"
    "    t$hot = cf_on(\"reactor\") && isTRUE(the$cf_hot)\n"
    "    the$cf_hot = FALSE\n")
sub("http-reactor.R",
    "    if (!isTRUE(t$busy)) at = min(at, max(t$next_at, tick))\n",
    "    if (!isTRUE(t$busy)) at = min(at, if (isTRUE(t$hot)) t$next_at else max(t$next_at, tick))\n")
