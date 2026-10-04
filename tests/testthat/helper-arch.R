# Architecture layering support (architecture section 2.2 rule 4; contract IC-33, section 12.2;
# proposal P-B section 2.4). The layer table is architecture section 3.2; the function map is
# built by parsing the files under R/, never from srcrefs (installed packages carry none).

# The layer of every file of architecture section 3.2 (119 files after IC-74).
# "L4 svc" files are declared services other built-ins may call (eval-*, env-*, tool-walk).
arch_layer_table = function() {
  rows = c(
    "aaa-state.R", "L0", "P01",
    "utils-conditions.R", "L0", "P01",
    "utils-hash.R", "L0", "P01",
    "utils-encoding.R", "L0", "P01",
    "utils-options.R", "L0", "P01",
    "utils-paths.R", "L0", "P01",
    "utils-text.R", "L0", "P01",
    "utils-tokens.R", "L0", "P01",
    "json-encode.R", "L0", "P01",
    "json-partial.R", "L0", "P01",
    "json-schema.R", "L0", "P01",
    "provider-message.R", "L1", "P01",
    "provider-events.R", "L1", "P01",
    "provider-fake.R", "L1", "P01",
    "zzz.R", "-", "P01",
    "ext-registry.R", "L0", "P02",
    "ext-specs.R", "L0", "P02",
    "ext-api.R", "L0", "P02",
    "ext-events.R", "L0", "P02",
    "ext-load.R", "L0", "P02",
    "ext-check.R", "L0", "P02",
    "ext-builtins.R", "L0", "P02",
    "auth-secrets.R", "L0", "P03",
    "auth-redact.R", "L0", "P03",
    "auth-dotenv.R", "L0", "P03",
    "auth-store.R", "L0", "P03",
    "auth-childenv.R", "L0", "P03",
    "proc-spawn.R", "L0", "P04",
    "proc-supervise.R", "L0", "P04",
    "http-reactor.R", "L0", "P04",
    "http-request.R", "L0", "P04",
    "http-sse.R", "L0", "P04",
    "http-retry.R", "L0", "P04",
    "provider-transform.R", "L1", "P05",
    "provider-registry.R", "L1", "P05",
    "provider-usage.R", "L1", "P05",
    "catalog-models.R", "L1", "P05",
    "session-object.R", "L3", "P06",
    "session-live.R", "L3", "P06",
    "session-store.R", "L3", "P06",
    "session-budget.R", "L3", "P06",
    "agent-loop.R", "L2", "P06",
    "agent-run.R", "L3", "P06",
    "agent-dispatch.R", "L2", "P06",
    "prompt-sections.R", "L3", "P07",
    "prompt-text.R", "L3", "P07",
    "prompt-context.R", "L3", "P07",
    "prompt-cache.R", "L3", "P07",
    "prompt-compact.R", "L3", "P07",
    "gptr-gateway.R", "L6", "P08",
    "gptr-capture.R", "L6", "P08",
    "gptr-sdk.R", "L6", "P08",
    "gptr-config.R", "L6", "P08",
    "eval-core.R", "L4 svc", "P09",
    "eval-plots.R", "L4 svc", "P09",
    "eval-guard.R", "L4 svc", "P09",
    "eval-format.R", "L4 svc", "P09",
    "env-snapshot.R", "L4 svc", "P09",
    "env-describe.R", "L4 svc", "P09",
    "env-history.R", "L4 svc", "P09",
    "env-probe.R", "L4 svc", "P09",
    "tool-namespace.R", "L4", "P10",
    "tool-r.R", "L4", "P10",
    "tool-read.R", "L4", "P10",
    "tool-write.R", "L4", "P10",
    "tool-edit.R", "L4", "P10",
    "tool-diff.R", "L4", "P10",
    "tool-walk.R", "L4 svc", "P10",
    "tool-search.R", "L4", "P10",
    "perm-classify.R", "L4", "P11",
    "perm-rules.R", "L4", "P11",
    "perm-gate.R", "L4", "P11",
    "perm-plan.R", "L4", "P11",
    "console-ui.R", "L5", "P11",
    "tool-ask.R", "L4", "P11",
    "provider-anthropic.R", "L1", "P12",
    "provider-openai-responses.R", "L1", "P12",
    "provider-openai-completions.R", "L1", "P12",
    "provider-google.R", "L1", "P12",
    "s1-types.R", "L1", "P13",
    "s1-client.R", "L4", "P13",
    "s1-route.R", "L4", "P13",
    "s1-cache.R", "L4", "P13",
    "s1-emulate.R", "L4", "P13",
    "s1-ollama.R", "L4", "P13",
    "console-repl.R", "L5", "P14",
    "console-render.R", "L5", "P14",
    "console-interrupt.R", "L5", "P14",
    "console-commands.R", "L5", "P14",
    "console-jsonl.R", "L5", "P14",
    "doc-locate.R", "L4", "P15",
    "doc-blocks.R", "L4", "P15",
    "doc-io.R", "L4", "P15",
    "doc-formats.R", "L4", "P15",
    "doc-replay.R", "L4", "P15",
    "doc-knitr.R", "L5", "P15",
    "ckpt-objects.R", "L4", "P16",
    "ckpt-files.R", "L4", "P16",
    "ckpt-rewind.R", "L4", "P16",
    "skill-discover.R", "L4", "P17",
    "skill-templates.R", "L4", "P17",
    "subagent-defs.R", "L4", "P17",
    "ext-plugins.R", "L0", "P17",
    "mcp-client.R", "L4", "P18",
    "mcp-config.R", "L4", "P18",
    "mcp-namespace.R", "L4", "P18",
    "mcp-server.R", "L4", "P18",
    "auth-oauth.R", "L0", "P18",
    "subagent-backends.R", "L4", "P19",
    "subagent-team.R", "L4", "P19",
    "subagent-worker.R", "L4", "P19",
    "cli-common.R", "L1", "P20",
    "cli-claude.R", "L1", "P20",
    "cli-codex.R", "L1", "P20",
    "agent-background.R", "L3", "P21",
    "bridge-sh.R", "L4", "P22",
    "bridge-lang.R", "L4", "P22",
    "artifact-app.R", "L4", "P23",
    "artifact-registry.R", "L4", "P23"
  )
  m = matrix(rows, ncol = 3L, byrow = TRUE)
  data.frame(
    file = m[, 1L], layer = sub(" svc$", "", m[, 2L]), service = m[, 2L] == "L4 svc",
    plan = m[, 3L]
  )
}

# The kernel SDK of IC-33: functions any L3-L6 file and any built-in may call directly
arch_kernel_sdk = function() {
  c(
    "session_data", "session_live", "session_home", "session_append", "session_set_model",
    "session_set_mode", "session_enqueue", "session_value_set", "session_value_get",
    "session_replay_apply", "session_replay_new", "session_replay_bind", "replay_lookup",
    "session_run", "run_start", "run_wait", "run_abort", "run_current", "run_eval_env",
    "run_emit", "dispatch_nested", "perm_check", "tool_result_message", "store_read",
    "store_rebuild", "call_value", "route_pass", "gateway_run", "gateway_defer", "replay_mode",
    "replay_guard", "egress_check", "home_address", "setting_get", "settings_effective",
    "settings_write", "resolve_identifier", "interpolate_prompt", "describe_binding", "eval_r",
    "format_eval_result", "rule_parse", "last_set", "ckpt_store_put"
  )
}

# Cross-area calls that the contract names by consumer although IC-33's kernel SDK omits them;
# arch_kernel_sdk() stays exactly the IC-33 list (contract section 12.2). P16's ckpt_predict()
# wraps P11's code_targets() (IC-31, sections 7.11 and 7.16); P19's sub-agents (section 7.6
# consumers) and the dedicated session of P18's gptr_mcp_serve() (section 6.3) create sessions
# with P06's session_new()
arch_contract_edges = function() {
  data.frame(
    caller_area = c("ckpt", "subagent", "mcp"),
    callee = c("code_targets", "session_new", "session_new")
  )
}

# Is each call from `caller_file` to `callee` one of arch_contract_edges()? (vectorised)
arch_contract_ok = function(caller_file, callee) {
  extra = arch_contract_edges()
  paste(arch_area(caller_file), callee) %in% paste(extra$caller_area, extra$callee)
}

# The layers each layer may call (architecture section 2.2). arch_edge_ok() adds the rest of
# the table: same-area calls, the record constructors of contract section 4 (callable from
# every layer), the L4 service files, the kernel SDK, the contract edges and the SDK verbs for L5.
arch_allowed = function() {
  list(
    L0 = "L0",
    L1 = c("L0", "L1"),
    L2 = c("L0", "L2"),
    L3 = c("L0", "L1", "L2", "L3"),
    L4 = "L0",
    L5 = c("L0", "L5"),
    L6 = c("L0", "L1", "L2", "L3", "L6"),
    `-` = "L0"
  )
}

# The service table of contract section 7.0: service name -> providing plan (from aaa-state.R)
arch_services = function() {
  service_plans
}

# The files that build records (contract section 4): every layer builds records through them
arch_record_files = c("provider-message.R", "provider-events.R")

# The directory of the R sources, or NULL when they cannot be found (IC-33)
arch_source_dir = function() {
  candidates = c(
    testthat::test_path("..", "..", "R"),
    testthat::test_path("..", "..", "00_pkg_src", "gptr", "R"),
    file.path(Sys.getenv("R_PACKAGE_DIR"), "..", "00_pkg_src", "gptr", "R")
  )
  for (dir in candidates) {
    if (file.exists(file.path(dir, "aaa-state.R"))) return(normalizePath(dir, winslash = "/"))
  }
  NULL
}

# The left-arrow assignment operator as a symbol (spelled without the literal so that the plan
# and the sources stay free of it)
arch_arrow = as.name(paste0("<", "-"))

# Top-level assignments of every file under R/: df(fun, file)
arch_fun_map = function(dir = arch_source_dir()) {
  rows = list()
  for (path in sort(list.files(dir, pattern = "[.][Rr]$", full.names = TRUE))) {
    for (e in parse(path, keep.source = FALSE, encoding = "UTF-8")) {
      is_assign = is.call(e) && (identical(e[[1L]], as.name("=")) ||
                                   identical(e[[1L]], arch_arrow))
      if (is_assign && (is.name(e[[2L]]) || is.character(e[[2L]]))) {
        rows[[length(rows) + 1L]] = data.frame(fun = as.character(e[[2L]]),
                                               file = basename(path))
      }
    }
  }
  if (!length(rows)) return(data.frame(fun = character(), file = character()))
  do.call(rbind, rows)
}

# Every function call of a file, from the parse data: df(file, line, fun, pkg, text)
pd_calls = function(path) {
  exprs = parse(path, keep.source = TRUE, encoding = "UTF-8")
  pd = utils::getParseData(exprs, includeText = TRUE)
  empty = data.frame(file = character(), line = integer(), fun = character(),
                     pkg = character(), text = character())
  if (is.null(pd)) return(empty)
  calls = pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
  if (!nrow(calls)) return(empty)
  pkg = vapply(calls$parent, function(id) {
    hit = pd$text[pd$parent == id & pd$token == "SYMBOL_PACKAGE"]
    if (length(hit)) hit[[1L]] else ""
  }, "")
  call_ids = pd$parent[match(calls$parent, pd$id)]
  data.frame(
    file = basename(path), line = calls$line1, fun = calls$text, pkg = pkg,
    text = vapply(call_ids, function(id) utils::getParseText(pd, id), "")
  )
}

# Literal service names used in calls to ext_service_get/has/set: df(file, line, fun, service)
arch_service_calls = function(dir = arch_source_dir()) {
  rows = list()
  for (path in list.files(dir, pattern = "[.][Rr]$", full.names = TRUE)) {
    calls = pd_calls(path)
    calls = calls[calls$fun %in% c("ext_service_get", "ext_service_has", "ext_service_set"), ]
    for (i in seq_len(nrow(calls))) {
      call = str2lang(calls$text[[i]])
      if (length(call) >= 2L && is.character(call[[2L]])) {
        rows[[length(rows) + 1L]] = data.frame(
          file = calls$file[[i]], line = calls$line[[i]], fun = calls$fun[[i]],
          service = call[[2L]]
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(file = character(), line = integer(), fun = character(),
                      service = character()))
  }
  do.call(rbind, rows)
}

# The area of a file: the part of its name before the first "-" (aaa-state.R -> "aaa")
arch_area = function(file) {
  sub("-.*$", "", sub("[.][Rr]$", "", file))
}

# May a function in `caller_file` call `callee`, defined in `callee_file`?
arch_edge_ok = function(caller_file, callee_file, callee, table = arch_layer_table()) {
  if (identical(caller_file, callee_file)) return(TRUE)
  if (identical(arch_area(caller_file), arch_area(callee_file))) return(TRUE)
  if (callee_file %in% arch_record_files) return(TRUE)
  from = table$layer[match(caller_file, table$file)]
  to = table$layer[match(callee_file, table$file)]
  if (is.na(from) || is.na(to)) return(FALSE)
  if (from %in% c("L3", "L4", "L5", "L6") && callee %in% arch_kernel_sdk()) return(TRUE)
  if (arch_contract_ok(caller_file, callee)) return(TRUE)
  if (from == "L4" && isTRUE(table$service[match(callee_file, table$file)])) return(TRUE)
  if (from == "L5" && callee_file == "gptr-sdk.R") return(TRUE)
  to %in% arch_allowed()[[from]]
}

# Violations among call edges: edges is df(caller, caller_file, callee, callee_file)
arch_check = function(edges, table = arch_layer_table()) {
  if (!nrow(edges)) return(edges)
  ok = vapply(seq_len(nrow(edges)), function(i) {
    arch_edge_ok(edges$caller_file[[i]], edges$callee_file[[i]], edges$callee[[i]], table)
  }, logical(1))
  edges[!ok, , drop = FALSE]
}

# The internal call edges of the package namespace (codetools::findGlobals)
arch_edges = function(map = arch_fun_map(), ns = asNamespace("gptr")) {
  rows = list()
  for (i in seq_len(nrow(map))) {
    fn = get0(map$fun[[i]], envir = ns, inherits = FALSE)
    if (!is.function(fn)) next
    called = codetools::findGlobals(fn, merge = FALSE)$functions
    called = intersect(called, map$fun)
    if (length(called)) {
      rows[[length(rows) + 1L]] = data.frame(
        caller = map$fun[[i]], caller_file = map$file[[i]], callee = called,
        callee_file = map$file[match(called, map$fun)]
      )
    }
  }
  if (!length(rows)) {
    return(data.frame(caller = character(), caller_file = character(), callee = character(),
                      callee_file = character()))
  }
  do.call(rbind, rows)
}
