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

#' The dispatcher; never throws. `target` is list(session, tools, envir). A notification gets an
#' empty result, which the claude CLI's control protocol expects.
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
#' fork's overlay, plan mode's scratch overlay), else its kept home, else `target$envir` (the
#' environment gptr_mcp_serve() holds when it is a function frame P06 keeps no home for, R2);
#' without a run, plan mode evaluates in a fresh scratch overlay, as a plan-mode run does (IC-15)
#' @noRd
mcp_serve_envir = function(target, run, mode) {
  if (!is.null(run)) return(run_eval_env(run))
  env = session_home(target$session) %||% target$envir
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

# ---- bearer tokens (IC-58) ---------------------------------------------------------------------

#' Revoke every token bound to a session id
#' @noRd
mcp_token_revoke = function(id) {
  env = the$mcp_tokens
  for (k in ls(env)) if (identical(env[[k]]$id, id)) rm(list = k, envir = env)
  invisible(NULL)
}

#' The token record behind an Authorization header, plus its `key` (the sha256 of the token), or
#' NULL (a token whose session was collected is no longer valid)
#' @noRd
mcp_token_lookup = function(authorization) {
  if (!rlang::is_string(authorization) || !startsWith(authorization, "Bearer ")) return(NULL)
  key = hash_sha256(substring(authorization, 8L))
  rec = get0(key, envir = the$mcp_tokens, inherits = FALSE)
  if (is.null(rec) || is.null(rlang::wref_key(rec$ref))) return(NULL)
  rec$key = key
  rec
}

#' The bearer token bound to `session` on the running server (contract 7.18): `the$mcp_tokens`
#' maps its sha256 to list(id, ref (a weak reference to the session), handle, tools), never its
#' value. The value (openssl::rand_bytes(24), hex) is a secret bound to the server's origin and
#' the session's live record holds its handle (`mcp_token`). A session keeps one token, its value
#' read back from the vault, because P20 calls mcp.serve_ensure before every codex request;
#' builtin:mcp revokes it at the session's shutdown.
#' @noRd
mcp_serve_token = function(session, tools = mcp_default_tools()) {
  url = the$mcp_server$url
  sid = session_data(session)$id
  env = the$mcp_tokens
  for (k in ls(env)) {
    if (identical(env[[k]]$id, sid)) {
      return(list(handle = env[[k]]$handle, key = k, value = secret_value(env[[k]]$handle, url)))
    }
  }
  value = rand_hex(24L)
  handle = secret_register(value, "GPTR_MCP_TOKEN", source = "mcp_serve", origin = url)
  key = hash_sha256(value)
  assign(key, list(id = sid, ref = rlang::new_weakref(session), handle = handle, tools = tools),
         envir = env)
  live = session_live(session)
  if (!is.null(live)) live$mcp_token = handle
  list(handle = handle, key = key, value = value)
}

# ---- the loopback HTTP server ------------------------------------------------------------------

#' The listening socket (one per process, IC-58): 127.0.0.1 on `port` or the first free port of
#' port_candidates() (never httpuv::randomPort(), IC-61), started with the seed preserved and
#' recorded in the job table; a running socket on another port refuses `port`
#' @noRd
mcp_serve_start = function(port = NULL) {
  st = the$mcp_server
  if (!is.null(st)) {
    if (!is.null(port) && port != st$port) {
      arg_abort(port, "port", paste0("NULL or ", st$port, ", the port the MCP server listens on"))
    }
    return(st)
  }
  for (p in c("httpuv", "later", "openssl")) oauth_need(p, "The MCP server")
  st = new.env(parent = emptyenv())
  st$legacy = new.env(parent = emptyenv())
  app = list(call = function(req) mcp_http_handle(st, req))
  for (p in port %||% port_candidates(20L)) {
    st$srv = tryCatch(with_seed_preserved(httpuv::startServer("127.0.0.1", p, app)),
                      error = function(e) NULL)
    if (!is.null(st$srv)) break
  }
  if (is.null(st$srv)) {
    gptr_abort("Could not open a local port for the MCP server.", "spawn",
               command = "httpuv::startServer")
  }
  st$port = as.integer(p)
  st$url = paste0("http://127.0.0.1:", st$port, "/mcp")
  st$job = paste0("mcp-serve-", st$port)
  job_add("mcp_serve", st$job, paste("MCP server", st$url), pid = Sys.getpid(),
          stop = mcp_serve_stop)
  the$mcp_server = st
  ev_dispatch("mcp_serve_start", list(url = st$url))
  st
}

#' Stop the server: revoke every token and release the served environment and the dedicated
#' session (R2)
#' @noRd
mcp_serve_stop = function() {
  st = the$mcp_server
  if (is.null(st)) return(invisible(FALSE))
  the$mcp_server = NULL
  httpuv::stopServer(st$srv)
  rm(list = ls(the$mcp_tokens), envir = the$mcp_tokens)
  st$envir = NULL
  st$user = NULL
  st$handle = NULL
  job_remove(st$job)
  ev_dispatch("mcp_serve_stop", list(url = st$url))
  invisible(TRUE)
}

#' An HTTP response for httpuv
#' @noRd
mcp_http_resp = function(status, body = "", headers = list()) {
  list(status = as.integer(status),
       headers = c(list(`Content-Type` = "application/json"), headers), body = body)
}

#' The busy rule of IC-57: inside a nested pump only requests of the runs it serves are
#' answered; others, and requests on the user's token (its dedicated session never runs), get
#' the retryable JSON-RPC error -32002
#' @noRd
mcp_serve_busy = function(rec) {
  allow = reactor_allow_runs()
  if (is.null(allow)) return(FALSE)
  s = rlang::wref_key(rec$ref)
  run = if (!is.null(s)) session_live(s)$run
  is.null(run) || !(run$id %in% allow)
}

#' The httpuv handler; never throws into httpuv
#' @noRd
mcp_http_handle = function(st, req) {
  tryCatch(mcp_http_route(st, req), error = function(e) {
    mcp_http_resp(500L, "{\"error\":\"internal error\"}")
  })
}

#' Route one HTTP request: path (404), Origin (403), bearer token (401), method (405), the era
#' headers, legacy sessions (no state beyond their ids), the busy rule, then the dispatcher
#' @noRd
mcp_http_route = function(st, req) {
  h = function(name) req[[paste0("HTTP_", toupper(gsub("-", "_", name)))]]
  if (!identical(req$PATH_INFO, "/mcp")) return(mcp_http_resp(404L))
  origin = h("Origin")
  allowed = paste0(c("http://127.0.0.1:", "http://localhost:"), st$port)
  if (!is.null(origin) && !(origin %in% allowed)) {
    return(mcp_http_resp(403L, "{\"error\":\"forbidden origin\"}"))
  }
  rec = mcp_token_lookup(h("Authorization"))
  if (is.null(rec)) {
    return(mcp_http_resp(401L, "{\"error\":\"invalid_token\"}",
                         list(`WWW-Authenticate` = "Bearer error=\"invalid_token\"")))
  }
  sid = h("Mcp-Session-Id")
  if (!identical(req$REQUEST_METHOD, "POST")) {
    if (identical(req$REQUEST_METHOD, "DELETE") && !is.null(sid) &&
          exists(sid, envir = st$legacy, inherits = FALSE)) {
      rm(list = sid, envir = st$legacy)
      return(mcp_http_resp(200L))
    }
    return(mcp_http_resp(405L, "", list(Allow = "POST")))
  }
  msg = tryCatch(json_decode(raw_to_utf8(req$rook.input$read())), error = function(e) NULL)
  if (!is.list(msg) || is.null(names(msg))) {
    return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(NULL, -32700L, "Parse error"))))
  }
  extra = list()
  meta_ver = msg$params[["_meta"]][[mcp_k_ver]]
  if (!is.null(meta_ver)) {
    same = identical(h("MCP-Protocol-Version"), meta_ver) && identical(h("Mcp-Method"), msg$method)
    if (!same) {
      return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(msg$id, -32020L, "Header mismatch"))))
    }
  } else if (identical(msg$method, "initialize")) {
    sid = rand_hex(16L)
    assign(sid, TRUE, envir = st$legacy)
    extra = list(`Mcp-Session-Id` = sid)
  } else if (is.null(sid)) {
    return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(msg$id, -32600L, paste(
      "Missing Mcp-Session-Id: send initialize first, or use the 2026-07-28 _meta fields")))))
  } else if (!exists(sid, envir = st$legacy, inherits = FALSE)) {
    return(mcp_http_resp(404L))
  }
  if (is.null(msg$id)) return(mcp_http_resp(202L))
  if (identical(msg$method, "tools/call") && mcp_serve_busy(rec)) {
    return(mcp_http_resp(200L, mcp_json(mcp_rpc_err(msg$id, -32002L, "gptr is busy; retry"))))
  }
  # the user's token falls back to the environment gptr_mcp_serve() holds (R2)
  target = list(session = rlang::wref_key(rec$ref), tools = rec$tools,
                envir = if (identical(rec$key, st$user$key)) st$envir)
  mcp_http_resp(200L, mcp_json(mcp_dispatch(msg, target)), extra)
}

# ---- handles, snippets and the exported server -------------------------------------------------

#' Client snippets for Codex, Claude Code, Claude Desktop and Cursor, each with a tool timeout of
#' 3,600 s (HTTP MCP clients time a request out after 60 s by default). They carry the token, so
#' they print redacted. The Codex snippet is a list: `args` (the `-c` overrides, which read the
#' token from GPTR_MCP_TOKEN) and `env` (the child's environment, which P20's pcli_codex_env()
#' reads); the others are JSON text (contract 6.3)
#' @noRd
mcp_client_snippets = function(url, token) {
  bearer = paste("Bearer", token)
  obj = function(x) {
    structure(json_encode(list(mcpServers = list(gptr = x)), pretty = TRUE),
              class = c("gptr_mcp_snippet", "character"))
  }
  list(
    codex = structure(list(args = c("-c", paste0("mcp_servers.gptr.url=", url), "-c",
                                    "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
                                    "-c", "mcp_servers.gptr.tool_timeout_sec=3600"),
                           env = c(GPTR_MCP_TOKEN = token)),
                      class = c("gptr_mcp_snippet", "list")),
    claude_code = obj(list(type = "http", url = url, headers = list(Authorization = bearer),
                           timeout = 3600000L)),
    claude_desktop = obj(list(command = "npx", args = I(c("-y", "mcp-remote", url, "--header",
                                                          paste0("Authorization: ", bearer))),
                              timeout = 3600000L)),
    cursor = obj(list(url = url, headers = list(Authorization = bearer), timeout = 3600000L)))
}

#' A `gptr_mcp_handle` (contract 5.11): url, port, token_env, config and stop(), plus `token`,
#' the `gptr_secret` handle of the bearer token (never its value; plan ambiguity 3)
#' @noRd
mcp_handle_new = function(st, tok, stop) {
  h = new.env(parent = emptyenv())
  h$url = st$url
  h$port = st$port
  h$token_env = "GPTR_MCP_TOKEN"
  h$token = tok$handle
  h$config = mcp_client_snippets(st$url, tok$value)
  h$stop = stop
  class(h) = "gptr_mcp_handle"
  h
}

#' Serve the live R session to other agents over MCP
#'
#' Starts an MCP server inside this R session that offers `r`, `read`, `edit` and `write` to
#' agents such as Codex, Claude Code, Claude Desktop or Cursor. It listens only on 127.0.0.1,
#' requires a 192-bit bearer token, rejects foreign browser origins, and runs every call through
#' your permission settings; R code evaluates in `envir`, where its objects persist. The calls
#' belong to a dedicated gptr session whose permission mode is the one in effect when the server
#' starts (stop and start the server to change it); like any new session, it becomes
#' [gptr_last()]. Requests are answered while R waits at the console or inside a gptr call; one
#' that needs your approval is refused with a note on how to allow it, because gptr never asks
#' from a background callback. The token appears only in the snippets of `$config` (printed
#' redacted; `as.character()` gives the text to paste; `$config$codex` holds the `codex` options
#' in `$args` and the environment to start Codex with in `$env`) and in the environment of
#' children gptr starts. One server runs per R process. Needs 'httpuv', 'later' and 'openssl'.
#'
#' @param tools The tools to serve: a subset of `c("r", "read", "edit", "write")`.
#' @param envir Where served R code evaluates and its objects persist.
#' @param port A port, or `NULL` for a free one.
#' @param stop `TRUE` to stop the server.
#' @return A `gptr_mcp_handle` with `$url`, `$port`, `$token_env`, `$config` and `$stop()`;
#'   calling again returns the running handle; with `stop = TRUE`, `invisible(NULL)`.
#' @examplesIf interactive() && rlang::is_installed(c("httpuv", "later", "openssl"))
#' h = gptr_mcp_serve(envir = new.env())
#' h$config$codex
#' gptr_mcp_serve(stop = TRUE)
#' @export
gptr_mcp_serve = function(tools = c("r", "read", "edit", "write"), envir = parent.frame(),
                          port = NULL, stop = FALSE) {
  if (!is.character(tools) || !length(tools) || !all(tools %in% mcp_default_tools())) {
    arg_abort(tools, "tools", "a subset of \"r\", \"read\", \"edit\" and \"write\"")
  }
  check_env(envir, "envir")
  port = check_number(port, "port", min = 1, max = 65535, int = TRUE, null = TRUE)
  check_flag(stop, "stop")
  ext_control_guard("gptr_mcp_serve")
  if (stop) {
    mcp_serve_stop()
    return(invisible(NULL))
  }
  if (!is.null(the$mcp_server$handle)) return(the$mcp_server$handle)
  st = mcp_serve_start(port)
  st$envir = envir
  # the dedicated session (contract 6.3, IC-58; P01's arch_contract_edges() admits this edge):
  # the mode setting now, and a placeholder model, since it never sends a request
  s = session_new(setting_get("model", default = "mcp/serve"),
                  setting_get("mode", default = "manual"), home = envir, kind = "chat")
  tok = mcp_serve_token(s, unique(tools))
  st$user = list(key = tok$key, session = s)
  st$handle = mcp_handle_new(st, tok, mcp_serve_stop)
  st$handle
}

#' The `mcp.serve_ensure` service (contract 7.0, IC-58): the shared socket plus the token bound
#' to `session` (a CLI child's session, P19/P20); the handle's stop() revokes that token only
#' @noRd
mcp_serve_ensure = function(session) {
  session = mcp_session_resolve(session)
  mcp_session_remember(session)
  st = mcp_serve_start()
  sid = session_data(session)$id
  mcp_handle_new(st, mcp_serve_token(session), function() mcp_token_revoke(sid))
}

#' Print a server handle (never the token)
#'
#' @param x A `gptr_mcp_handle`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_mcp_handle = function(x, ...) {
  msg_verbatim(c(paste0("<gptr MCP server> ", x$url),
                 paste0("token: in the environment variable ", x$token_env,
                        " of children gptr starts"),
                 paste0("config: ", paste(names(x$config), collapse = ", ")),
                 "stop: $stop() or gptr_mcp_serve(stop = TRUE)"))
  invisible(x)
}

#' Print a client snippet with its token redacted
#'
#' @param x A `gptr_mcp_snippet`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_mcp_snippet = function(x, ...) {
  if (is.list(x)) {
    text = c(paste(x$args, collapse = " "), paste0(names(x$env), "=", unname(x$env)))
    note = "(the token is hidden; $args are the codex options, $env the child's environment)"
  } else {
    text = as.character(x)
    note = "(the token is hidden; as.character() gives the text to paste)"
  }
  msg_verbatim(c(redact(text, "persist"), note))
  invisible(x)
}

on_load({
  the$mcp_tokens = new.env(parent = emptyenv())
})
on_load(ext_service_set("mcp.serve_ensure", mcp_serve_ensure, provided_by = "P18",
                        builtin = "mcp"))
on_load(on_unload(mcp_serve_stop))
