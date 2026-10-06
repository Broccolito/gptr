# gptr as an MCP server for the live session (contract 6.3, 7.18; architecture 6.14; IC-57,
# IC-58, IC-65): one JSON-RPC dispatcher (both eras) over the session's r, read, edit and write,
# gated like any tool call. The claude CLI's in-process "sdk" transport reaches it through P20's
# opts$mcp_dispatch (the mcp.dispatch_local service, the single gate of the claude route).
# Adapted from dev/research/07-anthropic-api-claude-plan.md 5.5-5.6 (the transport-agnostic
# dispatcher, verified live) and dev/research/16-mcp-skills-plugins.md 5.9 (dual-era answers).

#' The tools gptr serves
#' @noRd
mcp_default_tools = function() c("r", "read", "edit", "write")

#' The server's instructions
#' @noRd
mcp_server_instructions = paste("Tools run inside the user's live R session; objects persist.",
                                "Every call passes the user's permission settings.")

#' The schema of the served `r` tool: no person watches an MCP caller, so it offers the
#' best-effort timeout (IC-68)
#' @noRd
mcp_r_schema = list(type = "object", required = I("code"), properties = list(
  code = list(type = "string",
              description = "R code to evaluate. May contain several expressions."),
  timeout = list(type = "number", description = "Seconds; best effort. Default 3600.")))

#' tools/list entries of the served tools (descriptions and schemas of the registered specs)
#' @noRd
mcp_served_tools = function(tools) {
  out = list()
  for (nm in tools) {
    spec = registry_get("tool", nm)
    if (is.null(spec)) next
    schema = if (identical(nm, "r")) mcp_r_schema else spec$parameters
    if (!is.list(schema)) next
    ro = isTRUE(spec$annotations$read_only)
    out[[length(out) + 1L]] = list(name = nm, description = spec$description, inputSchema = schema,
                                   annotations = list(readOnlyHint = ro, destructiveHint = !ro,
                                                      openWorldHint = FALSE))
  }
  out
}

#' A gptr_tool_result as an MCP tools/call result (the text leaves the process: context-profile
#' redaction)
#' @noRd
mcp_tool_content = function(res) {
  blocks = lapply(res$content, function(b) {
    if (identical(b$type, "image")) {
      list(type = "image", data = b$data, mimeType = b$mime %||% "image/png")
    } else {
      list(type = "text", text = redact(b$text %||% "", "context"))
    }
  })
  if (!length(blocks)) blocks = list(list(type = "text", text = "(no output)"))
  list(content = blocks, isError = isTRUE(res$is_error))
}

#' Answer one JSON-RPC message (both eras) for `session` (a gptr_session or the id of one
#' builtin:mcp saw start) with the four served tools: the `mcp.dispatch_local` service
#' @noRd
mcp_dispatch_local = function(message, session) {
  mcp_dispatch(message, list(session = session, tools = mcp_default_tools()))
}

#' The dispatcher; never throws. `target` is list(session, tools). A notification gets an empty
#' result, which the claude CLI's control protocol expects.
#' @noRd
mcp_dispatch = function(message, target) {
  if (is.null(message$id)) return(list(jsonrpc = "2.0", result = json_obj()))
  tryCatch({
    target$session = mcp_session_resolve(target$session)
    mcp_dispatch_impl(message, target)
  }, error = function(e) {
    mcp_rpc_err(message$id, -32603L,
                paste("Internal error:", redact(conditionMessage(e), "context")))
  })
}

#' The method switch of the dispatcher: legacy results as they are, modern ones with the
#' 2026-07-28 fields (cacheable lists private with ttlMs 0)
#' @noRd
mcp_dispatch_impl = function(msg, target) {
  id = msg$id
  method = as.character(msg$method %||% "")
  params = msg$params %||% list()
  meta_ver = params[["_meta"]][[mcp_k_ver]]
  v = mcp_versions()
  if (!is.null(meta_ver) && !identical(meta_ver, v$modern)) {
    return(mcp_rpc_err(id, -32022L, "Unsupported protocol version",
                       list(supported = I(v$modern), requested = meta_ver)))
  }
  caps = list(tools = list(listChanged = FALSE))
  result = switch(
    method,
    initialize = {
      pv = params$protocolVersion
      list(protocolVersion = if (isTRUE(pv %in% v$legacy)) pv else v$legacy[1L],
           capabilities = caps, serverInfo = mcp_client_info(),
           instructions = mcp_server_instructions)
    },
    ping = json_obj(),
    "server/discover" = list(supportedVersions = I(v$modern), capabilities = caps,
                             instructions = mcp_server_instructions),
    "tools/list" = list(tools = mcp_served_tools(target$tools)),
    "tools/call" = {
      name = params$name
      if (!rlang::is_string(name) || !name %in% target$tools) {
        return(mcp_rpc_err(id, -32602L, paste("Unknown tool:", toString(name))))
      }
      mcp_tool_content(mcp_serve_call(target, name, params$arguments, id))
    },
    return(mcp_rpc_err(id, -32601L, paste("Method not found:", method)))
  )
  if (!is.null(meta_ver)) {
    result$resultType = "complete"
    result[["_meta"]] = stats::setNames(list(mcp_client_info()), mcp_k_sinfo)
    if (method %in% c("server/discover", "tools/list")) {
      result$ttlMs = 0L
      result$cacheScope = "private"
    }
  }
  mcp_rpc_ok(id, result)
}

#' Where a served call evaluates (IC-58): the running evaluation environment of the session (a
#' fork's overlay, plan mode's scratch overlay), else its kept home; without a run, plan mode
#' evaluates in a fresh scratch overlay of the home, as a plan-mode run does (IC-15)
#' @noRd
mcp_serve_envir = function(target, run, mode) {
  if (!is.null(run)) return(run_eval_env(run))
  env = session_home(target$session)
  if (is.environment(env) && identical(mode, "plan")) env = new.env(parent = env)
  env
}

#' Gate a served call when no pump runs (an idle console): the policies alone decide; whatever
#' needs approval is denied with how to allow it and a console notice, never prompted from a
#' callback (IC-57)
#' @noRd
mcp_gate_idle = function(call, ctx, sid = NULL) {
  if (isTRUE(gptr_opt("unsafe_no_permissions"))) {
    return(list(decision = "allow", reason = "gptr.unsafe_no_permissions is set"))
  }
  pols = registry_all("policy", session = sid)
  ask = if (!"mode" %in% names(pols)) list(reason = "no permission mode policy is active")
  for (p in pols) {
    d = ext_policy_decide(p, call, ctx)
    if (identical(d$decision, "deny")) return(d)
    if (!is.null(d) && !identical(d$decision, "allow")) ask = ask %||% d
  }
  if (is.null(ask)) return(list(decision = "allow", reason = ""))
  gptr_inform(paste0("An MCP client asked for ", call$name, ", which needs your approval; it ",
                     "was refused. Allow it with gptr_permissions(allow = ...) or run it ",
                     "yourself."), "notice")
  list(decision = "deny",
       reason = paste0(if (nzchar(ask$reason)) ask$reason else "this needs approval",
                       "; nobody can approve it while gptr serves requests in the background"))
}

#' The gate of a served call (IC-57): perm_check() with the session's run only while a pump runs
#' (the request is served inside a blocking gptr call, where a person may be asked); otherwise
#' (no run, or a run left in progress by gptr_step()) mcp_gate_idle()
#' @noRd
mcp_serve_gate = function(call, run, ctx, sid = NULL) {
  if (!is.null(run) && reactor_depth() > 0L) return(perm_check(call, run))
  mcp_gate_idle(call, ctx, sid)
}

#' Run one served tool call through mcp_serve_gate(); returns a gptr_tool_result
#' @noRd
mcp_serve_call = function(target, name, args, id) {
  s = target$session
  live = session_live(s)
  if (is.null(live)) return(gptr_tool_result("This session is not live.", is_error = TRUE))
  run = live$run
  ctx = live$ctx
  sid = session_data(s)$id
  spec = registry_get("tool", name, session = sid)
  if (is.null(spec) || !is.function(spec$execute)) {
    return(gptr_tool_result(paste("Tool", name, "not found"), is_error = TRUE))
  }
  v = schema_validate(if (identical(name, "r")) mcp_r_schema else spec$parameters,
                      if (length(args)) args else json_obj())
  if (!isTRUE(v$ok)) {
    return(gptr_tool_result(paste0("Invalid arguments for ", name, ": ",
                                   paste(v$errors, collapse = "; ")), is_error = TRUE))
  }
  input = v$input
  env = mcp_serve_envir(target, run, ctx$mode())
  if (identical(name, "r") && !is.environment(env)) {
    return(gptr_tool_result("This session has no environment to evaluate R code in.",
                            is_error = TRUE))
  }
  risk = if (identical(name, "r")) {
    ext_service_get("risk.classify")(input$code, envir = env, root = project_root(), kind = "r")
  } else if (is.function(spec$risk)) {
    spec$risk(input, ctx)
  }
  call = list(id = paste0("mcp_", id), name = name, input = input, tool = spec, nested = FALSE,
              risk = risk)
  d = mcp_serve_gate(call, run, ctx, sid)
  if (!identical(d$decision, "allow")) {
    return(gptr_tool_result(paste0("Permission denied: ", d$reason %||% "not allowed",
                                   ". To allow it, run it yourself at the R prompt or add a ",
                                   "rule with gptr_permissions(allow = ...)."), is_error = TRUE))
  }
  if (is.list(d$input)) input = d$input
  if (identical(name, "r")) return(mcp_serve_r(input, env, run))
  tryCatch(as_tool_result(spec$execute(input, ctx)), error = function(e) {
    gptr_tool_result(paste("Error:", conditionMessage(e)), is_error = TRUE)
  })
}

#' Evaluate served R code in `env` through the eval.r service (the evaluator kind, IC-69)
#' @noRd
mcp_serve_r = function(input, env, run) {
  budget = as.integer(gptr_opt("r_output_tokens"))
  timeout = input$timeout %||% (if (gptr_has_human()) NULL else gptr_opt("r_timeout"))
  res = ext_service_get("eval.r")(input$code, env, timeout = timeout, plots = "capture",
                                  tee = FALSE, budget_tokens = budget, rng = run$opts$rng_state,
                                  record = FALSE)
  out = format_eval_result(res, budget)
  gptr_tool_result(out$text, images = out$images, is_error = !identical(res$status, "ok"))
}

on_load(ext_service_set("mcp.dispatch_local", mcp_dispatch_local, provided_by = "P18",
                        builtin = "mcp"))
