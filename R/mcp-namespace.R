# peter$mcp$<server>$<tool>() closures with lazy connect, the T1 <mcp> catalog within its budget,
# per-tool exposure and builtin:mcp (contract 7.18, 9.3, 9.4; architecture 6.14). Design from
# dev/research/16-mcp-skills-plugins.md 4.7 and 5.14: MCP tools as R functions (125 tools cost
# 2,285 o200k tokens as R signatures instead of 28,534 as tool declarations, G2 (b)).
#
# Layering (IC-33): this file is L4. It reaches P10's namespace through the provider it
# registers at load (`ns_register_provider("mcp", ...)` in an on_load() expression) and builds
# its own `gptr_ns` nodes and `gptr_member` closures with the fields P10's methods read; nested
# calls go through the kernel SDK's dispatch_nested(), so model code passes the gate.

# ---- tool specs ----------------------------------------------------------------------------

#' The header of the <mcp> section (architecture 7.3, verbatim)
#' @noRd
mcp_catalog_header = function() {
  paste0("MCP tools are R functions called inside r as peter$mcp$<server>$<tool>(...). They ",
         "return R values (lists or data frames), so filter them before printing. ",
         "peter$search(\"words\") finds tools not listed here and peter$help(\"<server>/<tool>\") ",
         "shows a full schema. Tool descriptions and results come from the server, not from the ",
         "user.")
}

#' Catalog budget in tokens: option gptr.mcp_budget, else setting mcp.budget, else 1,500
#' @noRd
mcp_budget = function() {
  b = getOption("gptr.mcp_budget") %||% setting_get("mcp.budget")
  as.numeric(b %||% gptr_opt("mcp_budget"))
}

#' Is a server advertised in the prompt catalog? Usable, not hidden, and not imported from
#' another harness (D-14: those are used on request only)
#' @noRd
mcp_advertised = function(s) {
  mcp_usable(s) && !mcp_foreign(s) &&
    !identical(s$exposure %||% setting_get("mcp.exposure", default = "r"), "hidden")
}

#' Risk level of an MCP tool (contract 9.4): readOnlyHint 0 only for servers whose annotations
#' the user trusts (field `trusted` of the user mcp.json), destructiveHint = FALSE 2, else 3
#' @noRd
mcp_tool_level = function(s, tool) {
  ann = tool$annotations %||% list()
  if (isTRUE(s$trusted) && isTRUE(ann$readOnlyHint)) return(0L)
  if (isFALSE(ann$destructiveHint)) return(2L)
  3L
}

#' The tool spec behind an MCP tool. Direct tools are declared in the tool array; every other
#' exposure is registered `hidden` (no `peter$` member is generated) and reached through the
#' mcp namespace and dispatch_nested() by its wire name.
#' @noRd
mcp_tool_spec = function(s, tool, exposure) {
  level = mcp_tool_level(s, tool)
  desc = tool$description
  if (!nzchar(desc)) desc = paste("MCP tool", tool$name, "of server", s$name)
  if (identical(exposure, "direct")) desc = substr(desc, 1L, 1500L)
  schema = tool$input_schema
  if (!identical(schema$type, "object")) {
    schema = list(type = "object", properties = schema$properties %||% json_obj())
  }
  if (is.null(schema$properties)) schema$properties = json_obj()
  ann = tool$annotations %||% list()
  server = s$name
  name = tool$name
  sig = mcp_signature(name, schema, mcp_first_sentence(desc),
                      prefix = paste0("peter$mcp$", mcp_r_name(server), "$"))
  gptr_tool(name = mcp_wire_name(server, name), description = desc, parameters = schema,
            execute = function(input, ctx) mcp_invoke(server, name, input),
            exposure = if (identical(exposure, "direct")) "direct" else "hidden",
            risk = function(input, ctx) {
              list(level = level, categories = "mcp", paths = character())
            },
            signature = sig, output_tokens = 4000L,
            annotations = if (isTRUE(s$trusted)) {
              list(readOnlyHint = isTRUE(ann$readOnlyHint),
                   destructiveHint = !isFALSE(ann$destructiveHint))
            } else {
              list()
            })
}

#' Register (or reuse) the spec of an MCP tool: rank 6 (source builtin:mcp) for servers every
#' session sees, rank 0 scoped to `session` for a session's own servers (plugins = , P17). The
#' server record it was built from is kept, so mcp_sync() drops it when that record changes.
#' @noRd
mcp_spec_ensure = function(s, tool, exposure, session = NULL) {
  st = mcp_state()
  wire = mcp_wire_name(s$name, tool$name)
  global = !is.null(registry_get("mcp_server", s$name))
  sid = if (global || is.null(session)) NULL else session_data(session)$id
  key = if (is.null(sid)) wire else paste0(sid, "/", wire)
  old = get0(key, envir = st$specs, inherits = FALSE)
  if (!is.null(old)) {
    current = registry_get("tool", wire, session = sid)
    want = if (identical(exposure, "direct")) "direct" else "hidden"
    same = !is.null(current) && identical(current$exposure, want)
    if (same) return(current)
    registry_remove(old$id)
  }
  spec = mcp_tool_spec(s, tool, exposure)
  id = if (is.null(sid)) {
    registry_add(spec, source = "builtin:mcp", rank = 6L)
  } else {
    registry_add(spec, source = "session", rank = 0L, session = sid)
  }
  assign(key, list(id = id, sid = sid, server = s), envir = st$specs)
  registry_get("tool", wire, session = sid) %||% spec
}

#' Call an MCP tool for execute(): an isError result is signalled as gptr_error_mcp_tool (the
#' dispatcher turns it into an error result and caps the text at the spec's 4,000 output
#' tokens); the R value is the simplified structuredContent, else the text (contract 9.4)
#' @noRd
mcp_invoke = function(server, tool, input) {
  conn = mcp_conn_get(server)
  res = mcp_call(conn, tool, input)
  assign(paste0(server, "/", tool), reactor_now(), envir = mcp_state()$lru)
  if (isTRUE(res$is_error)) {
    gptr_abort(paste0("MCP tool ", server, "/", tool, " failed: ", res$text), c("mcp_tool", "mcp"),
               server = server, tool = tool)
  }
  gptr_tool_result(text = res$text, images = if (length(res$images)) res$images,
                   details = list(server = server, tool = tool, elapsed = res$elapsed),
                   value = mcp_value(res))
}

# ---- namespace nodes and member closures ------------------------------------------------------

#' A `gptr_ns` node with the bindings P10's methods read: `path`, `kind` ("mcp" or
#' "mcp_server"), `members()` and `signatures()`
#' @noRd
mcp_node = function(path, kind, members, signatures) {
  node = new.env(parent = emptyenv())
  assign("path", as.character(path), envir = node)
  assign("kind", kind, envir = node)
  assign("members", members, envir = node)
  assign("signatures", signatures, envir = node)
  class(node) = "gptr_ns"
  node
}

#' Formals of a member from a JSON Schema: required properties first (no default), optional
#' ones default NULL; non-syntactic property names become syntactic R names
#' @noRd
mcp_schema_formals = function(schema) {
  props = names(schema$properties %||% list())
  req = intersect(as.character(unlist(schema$required %||% list())), props)
  nms = c(req, setdiff(props, req))
  f = rep(list(quote(expr = )), length(nms))
  names(f) = mcp_r_name(nms)
  for (i in which(!nms %in% req)) f[i] = list(NULL)
  list(formals = as.pairlist(f), map = stats::setNames(nms, mcp_r_name(nms)),
       required = mcp_r_name(req))
}

#' The input list of a member call: supplied, non-NULL arguments under their schema names
#' @noRd
mcp_member_input = function(frame, fm, label) {
  input = list()
  for (rn in names(fm$map)) {
    missing_arg = eval(call("missing", as.name(rn)), frame)
    if (missing_arg) {
      if (rn %in% fm$required) {
        gptr_abort(paste0(label, "(): argument `", rn, "` is missing."), "invalid_argument",
                   arg = rn, expected = "a value")
      }
      next
    }
    v = get(rn, envir = frame, inherits = FALSE)
    if (!is.null(v)) input[[fm$map[[rn]]]] = v
  }
  if (length(input)) input else json_obj()
}

#' Run a member call: inside an `r` evaluation (a run's tool executes) through
#' dispatch_nested(), so the gate decides; at the console directly (the user's own call). An
#' isError result reaches R code as gptr_error_mcp_tool (contract 2.2).
#' @noRd
mcp_member_call = function(server, tool, wire, input) {
  run = run_current()
  if (is.null(run)) return(mcp_invoke(server, tool, input)$value)
  ctx = session_live(run$shell)$ctx
  prefix = paste0("MCP tool ", server, "/", tool, " failed: ")
  tryCatch(dispatch_nested(wire, input, ctx), gptr_error_tool = function(e) {
    msg = conditionMessage(e)
    if (startsWith(msg, prefix)) {
      gptr_abort(msg, c("mcp_tool", "mcp"), server = server, tool = tool)
    }
    stop(e)
  })
}

#' A `gptr_member` closure (class, `tool`, `spec` and `signature` attributes as P10's) for one
#' MCP tool. Its body calls `run` inlined, as P10's member closures do, so a tool argument named
#' like a variable here (`tool`, `server`) never shadows it.
#' @noRd
mcp_member_closure = function(spec, server, tool) {
  fm = mcp_schema_formals(spec$parameters)
  wire = spec$name
  label = paste0("peter$mcp$", mcp_r_name(server), "$", mcp_r_name(tool))
  run = function(frame) mcp_member_call(server, tool, wire, mcp_member_input(frame, fm, label))
  f = function() NULL
  formals(f) = fm$formals
  body(f) = as.call(list(run, as.call(list(base::environment))))
  structure(f, class = c("gptr_member", "function"), tool = wire, spec = spec,
            signature = spec$signature)
}

#' The member of one tool; a server whose tool list is not cached is connected here, at the
#' tool's first use (the lazy connect)
#' @noRd
mcp_member = function(server, name, session = NULL) {
  s = mcp_server_get(server, session)
  find = function(tl) {
    hit = Filter(function(t) identical(t$name, name) || identical(mcp_r_name(t$name), name),
                 tl %||% list())
    if (length(hit)) hit[[1L]] else NULL
  }
  tool = find(mcp_tools_known(s))
  if (is.null(tool)) tool = find(mcp_tools(mcp_conn_get(s$name, session)))
  exposure = if (!is.null(tool)) mcp_tool_exposure(s, tool$name)
  if (is.null(tool) || identical(exposure, "hidden")) {
    known = Filter(function(t) !identical(mcp_tool_exposure(s, t$name), "hidden"),
                   mcp_tools_known(s) %||% list())
    gptr_abort(paste0("MCP server ", s$name, " has no tool ", name, "."), "unknown_member",
               name = name, available = mcp_r_name(vapply(known, function(t) t$name, "")))
  }
  mcp_member_closure(mcp_spec_ensure(s, tool, exposure, session), s$name, tool$name)
}

#' Tools of a server for names(), completion and print() of peter$mcp$<server>: the known list,
#' else a connection lists them (asking to see a server's tools is its first use). Errors (an
#' untrusted project, a needed sign-in) propagate as classed conditions.
#' @noRd
mcp_tools_load = function(s, session = NULL) {
  tl = mcp_tools_known(s)
  if (!is.null(tl)) return(tl)
  mcp_tools(mcp_conn_get(s$name, session))
}

#' Remember a session by id (a weak reference in the$mcp_conns). Adapters hold only session ids
#' (contract 8.1), so the services also accept one (P20's request_params hook and P19 pass the
#' session object); the IC-33 kernel SDK has no lookup by id, so builtin:mcp records every
#' session whose session_start it sees.
#' @noRd
mcp_session_remember = function(session) {
  if (!inherits(session, "gptr_session")) return(invisible(NULL))
  assign(session_data(session)$id, rlang::new_weakref(session), envir = mcp_state()$sessions)
  invisible(NULL)
}

#' A session from a `gptr_session` or the id of a live session builtin:mcp saw start
#' @noRd
mcp_session_resolve = function(session) {
  if (inherits(session, "gptr_session")) return(session)
  if (is.character(session) && length(session) == 1L && !is.na(session)) {
    w = get0(session, envir = mcp_state()$sessions, inherits = FALSE)
    s = if (is.null(w)) NULL else rlang::wref_key(w)
    if (inherits(s, "gptr_session")) return(s)
  }
  gptr_abort("`session` must be a gptr session or the id of a live one.", "invalid_argument",
             arg = "session", expected = "a gptr_session or the id of a live session")
}

#' The `mcp` namespace provider (ns_register_provider("mcp", ...)): peter$mcp,
#' peter$mcp$<server> (no I/O) and peter$mcp$<server>$<tool>
#' @noRd
mcp_ns_provider = function(path) {
  if (!ext_service_has("mcp.catalog")) {
    gptr_abort("MCP support is not available: builtin:mcp is filtered out.", "not_available",
               member = "peter$mcp", provided_by = "P18")
  }
  path = as.character(path)
  # the session of the innermost running tool, or NULL at the console
  session = run_current()$shell
  if (length(path) == 1L) {
    return(mcp_node("mcp", "mcp",
                    members = function() {
                      mcp_r_name(names(Filter(mcp_usable, mcp_sync(session = session))))
                    },
                    signatures = function() {
                      unlist(lapply(Filter(mcp_usable, mcp_sync(session = session)),
                                    function(s) mcp_server_lines(s)[1L]), use.names = FALSE)
                    }))
  }
  server = mcp_server_resolve(path[2L], session)
  if (length(path) == 2L) {
    s = registry_get("mcp_server", server, session = session)
    s$name = server
    return(mcp_node(c("mcp", server), "mcp_server",
                    members = function() {
                      tl = tryCatch(mcp_tools_load(s, session), gptr_error = function(e) NULL)
                      tl = Filter(function(t) !identical(mcp_tool_exposure(s, t$name), "hidden"),
                                  tl %||% list())
                      mcp_r_name(vapply(tl, function(t) t$name, ""))
                    },
                    signatures = function() {
                      tl = tryCatch(mcp_tools_load(s, session), gptr_error = function(e) e)
                      if (inherits(tl, "condition")) {
                        return(paste0(mcp_r_name(server), ": tools unavailable: ",
                                      conditionMessage(tl)))
                      }
                      mcp_server_lines(s, tools = tl, exposures = c("r", "deferred", "direct"))
                    }))
  }
  if (length(path) == 3L) return(mcp_member(server, path[3L], session))
  gptr_abort(paste0("peter$", paste(path, collapse = "$"), " is not an MCP tool."),
             "unknown_member", name = path[length(path)], available = character())
}

# ---- the catalog -----------------------------------------------------------------------------

#' The catalog over `specs` within `budget` (architecture 6.14): the least recently used tools
#' lose their descriptions first, then their lines; descriptions then go back to the most
#' recently used tools while they fit. Server lines and counts always stay. The cost is
#' re-estimated on the joined text after every step, as the prompt section is measured.
#' @noRd
mcp_catalog_lines = function(specs, budget, exposures = "r") {
  lru = mcp_state()$lru
  servers = list()
  server = character()
  tool = character()
  used = numeric()
  full = character()
  short = character()
  for (s in specs) {
    tl = mcp_tools_known(s)
    if (is.null(tl)) {
      servers[[length(servers) + 1L]] = list(name = s$name, n = NA_integer_)
      next
    }
    tl = Filter(function(t) mcp_tool_exposure(s, t$name) %in% exposures, tl)
    servers[[length(servers) + 1L]] = list(name = s$name, n = length(tl))
    for (t in tl) {
      server = c(server, s$name)
      tool = c(tool, t$name)
      used = c(used, get0(paste0(s$name, "/", t$name), envir = lru, inherits = FALSE) %||% -Inf)
      full = c(full, paste0("  ", mcp_signature(t$name, t$input_schema,
                                                mcp_first_sentence(t$description))))
      short = c(short, paste0("  ", mcp_signature(t$name, t$input_schema, "")))
    }
  }
  bare = rep(FALSE, length(tool))
  drop = rep(FALSE, length(tool))
  render = function() {
    out = character()
    for (sv in servers) {
      if (is.na(sv$n)) {
        out = c(out, mcp_unlisted_line(sv$name))
        next
      }
      keep = which(server == sv$name & !drop)
      out = c(out, paste0(mcp_r_name(sv$name), ": ", sv$n, " tools, ", length(keep), " shown"),
              ifelse(bare[keep], short[keep], full[keep]))
    }
    out
  }
  head = est_tokens(mcp_catalog_header(), "prose")
  cost = function() head + est_tokens(paste(render(), collapse = "\n"), "code")
  if (!length(tool) || cost() <= budget) return(render())
  ord = order(used, server, tool, method = "radix")
  for (i in ord) {
    if (cost() <= budget) break
    bare[i] = TRUE
  }
  for (i in ord) {
    if (cost() <= budget) break
    drop[i] = TRUE
  }
  for (i in rev(ord)) {
    if (drop[i] || !bare[i]) next
    bare[i] = FALSE
    if (cost() > budget) bare[i] = TRUE
  }
  render()
}

#' Body of the <mcp> section: the header and the catalog of the advertised servers visible to
#' `session`; NULL when there is none
#' @noRd
mcp_catalog_text = function(session = NULL, budget = mcp_budget()) {
  specs = Filter(mcp_advertised, mcp_sync(session = session))
  if (!length(specs)) return(NULL)
  paste(c(mcp_catalog_header(), mcp_catalog_lines(specs, budget)), collapse = "\n")
}

#' Text of the `mcp` prompt section (T1, order 840); NULL when `r` is not an active tool or no
#' server is advertised
#' @noRd
mcp_section_text = function(ctx) {
  tools = ctx$input$tool_names
  if (!is.null(tools) && !"r" %in% tools) return(NULL)
  mcp_catalog_text(ctx$session, mcp_budget())
}

#' The `mcp.catalog` service (contract 7.0) behind peter$search(): every usable server visible to
#' `session`, imported ones included, with every tool that is not hidden; NULL when none
#' @noRd
mcp_catalog = function(session = NULL, budget = NULL) {
  specs = Filter(mcp_usable, mcp_sync(session = session))
  if (!length(specs)) return(NULL)
  paste(mcp_catalog_lines(specs, budget %||% mcp_budget(), c("r", "deferred", "direct")),
        collapse = "\n")
}

# ---- session start, login target, builtin:mcp -------------------------------------------------

#' session_start hook: remember the session by id (mcp_session_resolve()), then register the
#' direct-exposure tools of the advertised servers before the prompt freezes (from the cache,
#' or from a connection when a server, its toolExposure or setting mcp.exposure declares
#' direct tools)
#' @noRd
mcp_on_session_start = function(event, ctx) {
  session = ctx$session
  mcp_session_remember(session)
  for (s in Filter(mcp_advertised, mcp_sync(session = session))) {
    wants = c(s$exposure %||% setting_get("mcp.exposure", default = "r"), unlist(s$toolExposure))
    if (!"direct" %in% wants) next
    tl = mcp_tools_known(s)
    if (is.null(tl)) {
      tl = tryCatch(mcp_tools(mcp_conn_get(s$name, session)), gptr_error = function(e) {
        registry_diagnostic("builtin:mcp", "session_start", class(e)[1L], conditionMessage(e))
        NULL
      })
    }
    for (t in tl %||% list()) {
      if (identical(mcp_tool_exposure(s, t$name), "direct")) {
        mcp_spec_ensure(s, t, "direct", session)
      }
    }
  }
  NULL
}

#' The login target of gptr_login("mcp:<name>"): the expanded URL and oauth fields of an HTTP
#' server (registered with oauth_hooks_set(); auth-oauth.R is L0)
#' @noRd
mcp_login_target = function(name) {
  s = mcp_server_get(name)
  if (!identical(mcp_transport(s), "http")) {
    gptr_abort(paste0("MCP server ", name, " runs as a local process; it takes credentials from ",
                      "its env entries."), "invalid_argument", arg = "provider",
               expected = "an HTTP MCP server")
  }
  ex = mcp_expand_spec(s)
  list(url = ex$url, oauth = mcp_expand(s$oauth))
}

#' builtin:mcp (contract 10.3): the `mcp` prompt section, the session_start hook and the
#' session_shutdown hook revoking the session's server token (IC-58). The namespace provider, the
#' services and the login target are registered by the on_load() expressions below.
#' @noRd
builtin_mcp = function(gptr) {
  gptr$register(gptr_prompt_section("mcp", text = mcp_section_text, tier = "T1", order = 840L,
                                    budget = 1500L))
  gptr$on("session_start", mcp_on_session_start)
  gptr$on("session_shutdown", function(event, ctx) mcp_token_revoke(event$session))
  invisible(NULL)
}

on_load(ext_declare_builtin("mcp", builtin_mcp))
on_load(ext_service_set("mcp.catalog", mcp_catalog, provided_by = "P18", builtin = "mcp"))
on_load(ns_register_provider("mcp", mcp_ns_provider))
on_load(oauth_hooks_set(target = mcp_login_target))
on_load(on_unload(mcp_close_all))
