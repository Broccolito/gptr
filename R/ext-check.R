# ext-check.R -- the extension API version and features (contract 6.7 gptr_api()), the
# deprecation helper for API members (contract 10.9; architecture 3.2, 11.4) and the gptr_check()
# conformance suites for specs, factories and installed plugin packages (contract 6.7, 7.2;
# IC-42, IC-69). No network: adapter fixture replay is the `check.adapter` service of P12.

#' Extension API version and features
#'
#' The version of gptr's public extension API (independent of the package version) and the
#' features this build offers: `kind.<name>` for every registered kind, `event.<name>` for every
#' catalogued event, and the named features `lazy_activation`, `declarations`, `ctx.decide`,
#' `ctx.secret`, `route` and `services`. Plugins test features instead of comparing versions.
#'
#' @return A `gptr_api` list with `version` (a `package_version`) and `features` (character).
#' @examples
#' gptr_api()$version
#' "kind.router" %in% gptr_api()$features
#' @export
gptr_api = function() {
  structure(list(version = package_version(ext_api_version),
                 features = c(paste0("kind.", kind_names()), paste0("event.", ev_table$event),
                              "lazy_activation", "declarations", "ctx.decide", "ctx.secret",
                              "route", "services")),
            class = "gptr_api")
}

#' Print the API version and the number of features
#' @export
#' @noRd
print.gptr_api = function(x, ...) {
  cat("<gptr_api ", format(x$version), "> ", length(x$features), " features\n", sep = "")
  invisible(x)
}

#' Deprecated members of the API object ("api") and of ctx ("ctx"): member -> list(since,
#' instead). Extension API 1.0 deprecates nothing; a MINOR release adds entries here and keeps the
#' member for at least one MINOR release and six months (contract 10.9)
#' @noRd
ext_deprecations = function() list(api = list(), ctx = list())

#' Warn once per session about a deprecated member (an error with
#' options(gptr.deprecations = "error")); FALSE when the member is not deprecated
#' @noRd
ext_warn_deprecated = function(object, name) {
  dep = ext_deprecations()[[object]][[name]]
  if (is.null(dep)) return(invisible(FALSE))
  prefix = if (identical(object, "api")) "gptr$" else "ctx$"
  gptr_deprecated(paste0(prefix, name), dep$since, dep$instead)
  invisible(TRUE)
}

# ---- conformance (contract 6.7 gptr_check(), 7.2; architecture 11.4) ----------------------------
# Adapted from the verified G1 prototype (report G1 5.1 check.R: check_row(),
# with_scratch_registry(), the tool, policy, factory and package suites) and its checks 5.2/5.5.

#' One conformance row (contract 5.11: target, check, ok, message)
#' @noRd
check_row = function(target, check, ok, message = "") {
  data.frame(target = as.character(target), check = as.character(check), ok = isTRUE(ok),
             message = paste(as.character(message), collapse = "; "), stringsAsFactors = FALSE)
}

#' Bind rows into a `gptr_check` data frame
#' @noRd
check_rows = function(rows) {
  df = if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(target = character(), check = character(), ok = logical(), message = character(),
               stringsAsFactors = FALSE)
  }
  rownames(df) = NULL
  structure(df, class = c("gptr_check", "data.frame"))
}

#' Rows of a gptr_check data frame as a list of one-row frames
#' @noRd
check_as_rows = function(df, target) {
  lapply(seq_len(nrow(df)), function(i) {
    check_row(target, df$check[[i]], df$ok[[i]], df$message[[i]] %||% "")
  })
}

#' Run `fun()` in a scratch registry that mirrors the current one: its plugin kinds and its
#' enabled, active process-level records (never session records or lazy placeholders). Without
#' the records, P01's ext_service_get() would treat every bootstrap service owned by a loaded
#' built-in as filtered out (the scratch lists records but none of that built-in), so a policy
#' calling ctx$risk() would fail its matrix, and a plugin namespace clashing with a live member
#' would pass. Checks register only into the scratch, so nothing leaks into the live registry
#' @noRd
check_in_scratch = function(fun) {
  live = registry_env()
  scratch = registry_scratch()
  scratch$check_origin = live
  for (nm in ls(live$kinds)) {
    d = get0(nm, envir = live$kinds, inherits = FALSE)
    fresh = is.null(get0(nm, envir = scratch$kinds, inherits = FALSE))
    if (!is.null(d) && !identical(d$source, "builtin") && fresh) {
      assign(nm, d, envir = scratch$kinds)
    }
  }
  scratch$seq = live$seq
  for (id in ls(live$recs)) {
    rec = get0(id, envir = live$recs, inherits = FALSE)
    keep = !is.null(rec) && is.null(rec$session) && identical(rec$state, "active") &&
      !is.null(get0(rec$kind, envir = scratch$kinds, inherits = FALSE)) &&
      !registry_rec_filtered(rec, live)
    if (!keep) next
    rec$ext = NULL
    assign(id, rec, envir = scratch$recs)
    registry_index_push(scratch$by_kind, rec$kind, id)
    registry_index_push(scratch$by_key, paste(rec$kind, rec$name, sep = "\r"), id)
    if (identical(rec$kind, "hook")) {
      registry_index_push(scratch$hooks, rec$spec[["event"]] %||% rec$name, id)
    }
  }
  old = registry_swap(scratch)
  on.exit(registry_swap(old), add = TRUE)
  fun()
}

#' Child process ids of this R process (for "no action at load" and backend cancel checks)
#' @noRd
check_children = function() {
  tryCatch({
    kids = ps::ps_children(ps::ps_handle())
    sort(vapply(kids, function(p) as.integer(ps::ps_pid(p)), 0L))
  }, error = function(e) e)
}

#' Tools: schema validity, direct description at most 400 tokens, empty-input handling
#' @noRd
check_tool = function(spec, target) {
  rows = list()
  params = spec[["parameters"]]
  if (is.list(params)) {
    probs = schema_problems(params)
    rows = c(rows, list(check_row(target, "tool.schema", !length(probs), probs)))
  } else {
    rows = c(rows, list(check_row(target, "tool.schema", TRUE,
                                  "a function of ctx, evaluated when a session freezes")))
  }
  if (identical(spec[["exposure"]], "direct")) {
    n = est_tokens(spec[["description"]], "prose")
    rows = c(rows, list(check_row(target, "tool.description_tokens", n <= 400,
                                  paste0(n, " tokens (a direct tool allows at most 400)"))))
  }
  c(rows, list(check_tool_empty(spec, target)))
}

#' Empty input: rejected by the schema, or answered with a result or a classed gptr condition
#' @noRd
check_tool_empty = function(spec, target) {
  params = spec[["parameters"]]
  required = if (is.list(params)) as.character(unlist(params[["required"]])) else character()
  if (length(required)) {
    rejected = !isTRUE(schema_validate(params, json_obj())$ok)
    return(check_row(target, "tool.empty_input", rejected,
                     if (rejected) "empty input fails schema validation before execute()" else
                       "the schema requires properties but accepts empty input"))
  }
  direct = is.function(spec[["execute"]])
  run = if (direct) {
    function() spec[["execute"]](json_obj(), ctx_new(NULL))
  } else {
    function() spec[["fun"]]()
  }
  res = tryCatch(list(value = run()), error = function(e) e)
  if (inherits(res, "gptr_error")) return(check_row(target, "tool.empty_input", TRUE))
  if (inherits(res, "error")) {
    return(check_row(target, "tool.empty_input", FALSE,
                     paste0("empty input raised an unclassed error: ", conditionMessage(res))))
  }
  valid = if (direct) tryCatch({
    as_tool_result(res$value)
    NULL
  }, error = function(e) e) else NULL
  check_row(target, "tool.empty_input", is.null(valid),
            if (is.null(valid)) "" else paste0("malformed tool result: ", conditionMessage(valid)))
}

#' Prompt sections: a fixed text fits its token budget
#' @noRd
check_section = function(spec, target) {
  text = spec[["text"]]
  if (!is.character(text)) {
    return(list(check_row(target, "section.budget", TRUE, "rendered when a session freezes")))
  }
  n = est_tokens(text, "prose")
  list(check_row(target, "section.budget", n <= spec[["budget"]],
                 paste0(n, " tokens (budget ", spec[["budget"]], ")")))
}

#' Synthetic tool calls of report 18 section 4.7 (contract 4.4 call records): tool, input, level
#' @noRd
check_policy_calls = function() {
  rows = list(
    list("read", list(path = "R/analysis.R"), 0L, "read"),
    list("read", list(path = "/etc/hosts"), 1L, "read"),
    list("read", list(path = "~/.ssh/id_rsa"), 2L, "secret"),
    list("write", list(path = "R/analysis.R", content = "x = 1"), 2L, "file_write"),
    list("edit", list(path = ".Rprofile", edits = list()), 3L, "control"),
    list("r", list(code = "summary(x)"), 0L, "read"),
    list("r", list(code = "y = x + 1"), 1L, "object_write"),
    list("r", list(code = "write.csv(x, 'x.csv')"), 2L, "file_write"),
    list("r", list(code = "unlink('data', recursive = TRUE)"), 3L, "file_delete"),
    list("r", list(code = "rm(list = ls())"), 4L, "critical")
  )
  lapply(seq_along(rows), function(i) {
    r = rows[[i]]
    list(id = paste0("check_", i), name = r[[1]], input = r[[2]], raw = NULL, tool = NULL,
         nested = FALSE, parent_id = NULL, outer_level = NULL,
         risk = list(level = r[[3]], categories = r[[4]], paths = character()))
  })
}

#' Policies: every verdict over the modes x report 18 matrix is NULL or a valid decision, no
#' call throws, and the median call takes at most 10 ms (contract 10.2 row 12)
#' @noRd
check_policy = function(spec, target) {
  cell = new.env(parent = emptyenv())
  cell$mode = "manual"
  kernel = function() list(mode = function(ctx) cell$mode, model = function(ctx) "check/check-1")
  # Temporarily hide mirrored kernels, including rank 0 records, so every mode is exercised.
  reg = registry_env()
  key = "service\rctx.kernel"
  ids = get0(key, envir = reg$by_key, inherits = FALSE) %||% character()
  saved = registry_recs(reg, ids)
  for (old_id in ids) registry_remove(old_id)
  id = registry_add(gptr_spec("service", "ctx.kernel", fun = kernel), "user", 0L)
  on.exit({
    registry_remove(id)
    for (record in saved) {
      assign(record$id, record, envir = reg$recs)
      registry_index_push(reg$by_kind, "service", record$id)
      registry_index_push(reg$by_key, key, record$id)
    }
    registry_touch(reg)
  }, add = TRUE)
  ctx = ctx_new(NULL)
  bad = character()
  times = numeric()
  for (mode in c("plan", "manual", "edits", "auto")) {
    cell$mode = mode
    for (call in check_policy_calls()) {
      t0 = proc.time()[["elapsed"]]
      v = tryCatch(spec[["check"]](call, ctx), error = function(e) e)
      times = c(times, proc.time()[["elapsed"]] - t0)
      why = if (inherits(v, "error")) {
        paste0("error: ", conditionMessage(v))
      } else if (!is.null(v) && !ext_policy_ok(v)) {
        "malformed decision"
      }
      if (!is.null(why)) bad = c(bad, paste0(mode, "/", call$name, " level ", call$risk$level,
                                             ": ", why))
    }
  }
  med = stats::median(times)
  list(
    check_row(target, "policy.matrix", !length(bad),
              if (length(bad)) utils::head(bad, 3L) else paste(length(times), "calls")),
    check_row(target, "policy.speed", med <= 0.01, paste0("median ", round(med * 1000, 2), " ms"))
  )
}

#' Backends: start() and cancel() of a probe succeed and cancel leaves no child process
#' @noRd
check_backend = function(spec, target) {
  before = check_children()
  if (inherits(before, "error")) {
    return(list(check_row(target, "backend.processes", FALSE,
                           paste0("cannot observe child processes: ", conditionMessage(before)))))
  }
  probe = list(name = "gptr-check", prompt = "conformance probe", model = NULL,
               tools = character())
  h = tryCatch(spec[["start"]](probe, ctx_new(NULL)), error = function(e) e)
  rows = list(check_row(target, "backend.start", !inherits(h, "error"),
                        if (inherits(h, "error")) conditionMessage(h) else ""))
  if (inherits(h, "error")) return(rows)
  cancelled = tryCatch({
    spec[["cancel"]](h)
    NULL
  }, error = function(e) e)
  rows = c(rows, list(check_row(target, "backend.cancel", is.null(cancelled),
                                if (is.null(cancelled)) "" else conditionMessage(cancelled))))
  t0 = proc.time()[["elapsed"]]
  repeat {
    after = check_children()
    if (inherits(after, "error")) {
      return(c(rows, list(check_row(target, "backend.processes", FALSE,
                                    paste0("cannot observe child processes: ",
                                           conditionMessage(after))))))
    }
    extra = setdiff(after, before)
    if (!length(extra) || proc.time()[["elapsed"]] - t0 > 2) break
    Sys.sleep(0.05)
  }
  c(rows, list(check_row(target, "backend.processes", !length(extra),
                         if (length(extra)) paste("still running after cancel: pid", extra) else
                           "")))
}

#' Adapters: fixture replay through the `check.adapter` service (P12) when it is available. The
#' name check_adapter() belongs to P12's service implementation (04 section 7.12)
#' @noRd
check_adapter_rows = function(spec, target, adapter_check) {
  if (is.null(adapter_check)) return(list())
  res = tryCatch(adapter_check(spec), error = function(e) e)
  if (inherits(res, "error")) {
    return(list(check_row(target, "adapter.replay", FALSE, conditionMessage(res))))
  }
  check_as_rows(res, target)
}

#' Token costs (IC-69): the declaration, and the printed result of each of a member's `examples`
#' (a list of argument lists)
#' @noRd
check_tokens = function(spec, target) {
  rows = list(check_row(target, "tokens.declaration", TRUE,
                        paste0(spec_tokens(spec), " tokens")))
  examples = spec[["examples"]]
  if (!identical(spec$kind, "tool") || !is.list(examples) || !is.function(spec[["fun"]])) {
    return(rows)
  }
  budget = spec[["output_tokens"]] %||% gptr_opt("helper_output_tokens")
  for (i in seq_along(examples)) {
    out = tryCatch(utils::capture.output(print(do.call(spec[["fun"]], as.list(examples[[i]])))),
                   error = function(e) e)
    row = if (inherits(out, "error")) {
      check_row(target, paste0("tokens.example.", i), FALSE, conditionMessage(out))
    } else {
      n = est_tokens(out, "r_output")
      check_row(target, paste0("tokens.example.", i), n <= budget,
                paste0(n, " tokens printed (budget ", budget, ")"))
    }
    rows = c(rows, list(row))
  }
  rows
}

#' The conformance rows of a spec (contract 6.7)
#' @noRd
check_spec = function(spec, tokens = FALSE, adapter_check = NULL) {
  kind = if (is.list(spec)) spec[["kind"]] else NULL
  name = if (is.list(spec)) spec[["name"]] else NULL
  ok_kind = is.character(kind) && length(kind) == 1L && !is.na(kind)
  ok_name = is.character(name) && length(name) == 1L && !is.na(name)
  target = paste0(if (ok_kind) kind else "?", ":", if (ok_name) name else "?")
  ok_class = inherits(spec, "gptr_spec") && ok_kind && ok_name
  rows = list(check_row(target, "spec.class", ok_class,
                        if (ok_class) "" else "not a gptr_spec with a kind and a name"))
  if (!ok_class) return(rows)
  valid = tryCatch(spec_finish(unclass(spec), kind_get(kind)), error = function(e) e)
  if (inherits(valid, "error")) {
    msg = if (inherits(valid, "gptr_error_invalid_spec") && is.character(valid$field)) {
      paste0("field '", valid$field, "' ", valid$problem)
    } else {
      conditionMessage(valid)
    }
    return(c(rows, list(check_row(target, "spec.fields", FALSE, msg))))
  }
  rows = c(rows, list(check_row(target, "spec.fields", TRUE)))
  rows = c(rows, switch(kind,
    tool = check_tool(valid, target),
    prompt_section = check_section(valid, target),
    policy = check_policy(valid, target),
    backend = check_backend(valid, target),
    adapter = check_adapter_rows(valid, target, adapter_check),
    list()
  ))
  if (tokens) rows = c(rows, check_tokens(valid, target))
  rows
}

#' What a factory may not change while it loads: working directory, search path, environment
#' variables, options, the random-number state and child processes ("no action at load",
#' contract 6.7; IC-61)
#' @noRd
check_snapshot = function() {
  list(wd = getwd(), search = search(), env = Sys.getenv(), options = options(),
       seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
       children = check_children())
}

#' The conformance rows of a factory, loaded eagerly in the (scratch) registry (contract 6.7)
#' @noRd
check_factory = function(factory, manifest = NULL, tokens = FALSE, adapter_check = NULL) {
  source = "plugin:gptr-check"
  target = "factory"
  reg = registry_env()
  previous_ids = ls(reg$recs)
  previous_diag = length(reg$diag$rows)
  invocation = new.env(parent = emptyenv())
  invocation$id = NULL
  checked = function(gptr) {
    # Identify the outer transaction from the API it receives. Nested loads may share
    # its source string, but their registrations must not satisfy this factory's claims.
    for (eid in ls(reg$exts)) {
      info = get0(eid, envir = reg$exts, inherits = FALSE)
      if (!is.null(info) && identical(info$api, gptr)) invocation$id = eid
    }
    factory(gptr)
  }
  attr(checked, "gptr_api") = attr(factory, "gptr_api", exact = TRUE)
  before = check_snapshot()
  ok = withCallingHandlers(
    ext_load(checked, source = source, rank = 5L, manifest = manifest),
    gptr_warning_plugin = function(w) invokeRestart("muffleWarning")
  )
  after = check_snapshot()
  reg = registry_env()
  recs = Filter(function(r) {
    !is.null(invocation$id) && identical(r$ext, invocation$id) &&
      identical(r$source, source) && !identical(r$state, "lazy")
  }, registry_recs(reg, setdiff(ls(reg$recs), previous_ids)))
  recs = recs[order(vapply(recs, function(r) r$order, 0L))]
  d = utils::tail(reg$diag$rows, length(reg$diag$rows) - previous_diag)
  mine = Filter(function(r) identical(r$source, source), d)
  why = if (length(mine)) mine[[length(mine)]]$message else ""
  same = vapply(names(before), function(n) identical(before[[n]], after[[n]]), NA)
  same[["children"]] = same[["children"]] && !inherits(before$children, "error") &&
    !inherits(after$children, "error")
  changed = names(before)[!same]
  rows = list(
    check_row(target, "factory.load", ok, if (isTRUE(ok)) "" else why),
    check_row(target, "factory.registers", length(recs) > 0L, paste(length(recs), "record(s)")),
    check_row(target, "factory.no_action", !length(changed),
              if (length(changed)) paste("changed at load:", paste(changed, collapse = ", ")) else
                "")
  )
  provides = ext_provides(manifest)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      got = vapply(recs, function(r) {
        identical(r$kind, kind) && (identical(r$name, nm) || identical(r$spec[["event"]], nm))
      }, NA)
      rows = c(rows, list(check_row(target, paste0("provides.", kind, ":", nm), any(got),
                                    if (any(got)) "" else "declared but not registered")))
    }
  }
  for (r in recs) rows = c(rows, check_spec(r$spec, tokens, adapter_check))
  rows
}

#' A file of an installed package ("" when absent); mockable in tests
#' @noRd
ext_pkg_path = function(pkg, ...) system.file(..., package = pkg)

#' An exported function of a package (loads its namespace); mockable in tests
#' @noRd
ext_pkg_factory = function(pkg, fun) getExportedValue(pkg, fun)

#' A DESCRIPTION field of an installed package (NA when absent); mockable in tests
#' @noRd
ext_pkg_description = function(pkg, field) {
  v = suppressWarnings(utils::packageDescription(pkg, fields = field))
  if (is.character(v) && length(v) == 1L) v else NA_character_
}

#' The objects of a package namespace as a named list; mockable in tests
#' @noRd
ext_pkg_objects = function(pkg) {
  ns = asNamespace(pkg)
  nms = ls(ns, all.names = TRUE)
  out = lapply(nms, function(n) get0(n, envir = ns, inherits = FALSE))
  names(out) = nms
  out
}

#' Is element `i` of a call's parts the empty (missing) argument?
#' @noRd
ext_is_empty = function(parts, i) identical(parts[[i]], quote(expr = ))

#' Call `visit(call)` for every call inside an expression
#' @noRd
ext_walk_calls = function(expr, visit) {
  if (!is.call(expr)) return(invisible(NULL))
  visit(expr)
  parts = as.list(expr)
  for (i in seq_along(parts)) {
    if (!ext_is_empty(parts, i)) ext_walk_calls(parts[[i]], visit)
  }
  invisible(NULL)
}

#' Name of a called function, with the gptr:: prefix removed ("" for other heads)
#' @noRd
ext_call_name = function(call) {
  h = call[[1L]]
  if (is.name(h)) return(as.character(h))
  if (is.call(h) && identical(h[[1L]], as.name("::")) && identical(h[[2L]], as.name("gptr"))) {
    return(as.character(h[[3L]]))
  }
  ""
}

#' The assignment operators and `for` (the arrows are written as \u escapes, so that no arrow
#' appears in gptr's own source)
#' @noRd
ext_binding_heads = c("=", "\u003c-", "\u003c\u003c-", "for")

#' Names a function binds locally: its formals, assignment targets and for-loop variables
#' @noRd
ext_local_names = function(f) {
  acc = new.env(parent = emptyenv())
  acc$names = names(formals(f))
  ext_walk_calls(body(f), function(call) {
    head = ext_call_name(call)
    if (head %in% ext_binding_heads && length(call) >= 2L && is.name(call[[2L]])) {
      acc$names = c(acc$names, as.character(call[[2L]]))
    }
  })
  unique(acc$names)
}

#' Bare identifiers passed to gptr's identifier arguments in package code (IC-42): a symbol that
#' is neither local nor a binding of the package or base makes R CMD check report "no visible
#' binding" and should be a string. gptr_agent() stores `model` and `skills` unevaluated (IC-34)
#' and the gateway resolves them in the frame of a later peter() call, where the package
#' function's locals and objects are not visible, so every bare symbol there is reported (use a
#' string, or I(x) for a variable's value)
#' @noRd
ext_bare_identifiers = function(objects) {
  args = c("model", "mode", "preset", "skills", "agents", "tools", "plugins", "extensions",
           "backend")
  heads = c("peter", "gptr_agent", "gptr_parallel")
  known = names(objects)
  acc = new.env(parent = emptyenv())
  acc$found = character()
  for (fn in names(objects)) {
    f = objects[[fn]]
    if (!is.function(f) || is.primitive(f)) next
    local = ext_local_names(f)
    ext_walk_calls(body(f), function(call) {
      head = ext_call_name(call)
      if (!(head %in% heads)) return(NULL)
      nms = names(call)
      for (i in seq_along(nms)) {
        if (!(nms[[i]] %in% args) || ext_is_empty(as.list(call), i)) next
        v = call[[i]]
        if (!is.name(v)) next
        sym = as.character(v)
        raw = identical(head, "gptr_agent") && nms[[i]] %in% c("model", "skills")
        if (!raw && (sym %in% c(local, known) || exists(sym, envir = baseenv()))) next
        acc$found = c(acc$found, paste0(fn, ": ", nms[[i]], " = ", sym))
      }
      NULL
    })
  }
  unique(acc$found)
}

#' Validate the manifest fields the conformance checker consumes before nested extraction
#' @noRd
check_manifest = function(man) {
  check_list(man, "manifest", named = TRUE)
  check_string(man[["name"]], "manifest name")
  check_list(man[["gptr"]], "manifest gptr", named = TRUE, null = TRUE)
  check_string(man[["gptr"]][["api"]], "manifest API", null = TRUE)
  extension = man[["extension"]]
  check_list(extension, "manifest extension", named = TRUE, null = TRUE)
  if (!is.null(extension)) {
    check_entry(extension[["entry"]])
    check_string(extension[["activation"]], "extension activation", null = TRUE)
    declarations = extension[["declarations"]]
    check_list(declarations, "extension declarations", named = TRUE, null = TRUE)
    for (declaration in declarations) {
      check_list(declaration, "declaration", named = TRUE)
      check_string(declaration[["signature"]], "declaration signature", null = TRUE, empty = TRUE)
      check_string(declaration[["description"]], "declaration description", null = TRUE,
                    empty = TRUE)
    }
  }
  ext_provides(man)
  invisible(man)
}

#' Parse an installed package's exported factory entry without discarding its package
#' @noRd
check_entry = function(entry) {
  check_string(entry, "extension entry")
  parts = regmatches(entry, regexec("\\A([^:[:space:]]+)::([^:[:space:]]+)\\z",
                                    entry, perl = TRUE))[[1L]]
  if (length(parts) != 3L) {
    arg_abort(entry, "extension entry", "pkg::fun naming an exported function")
  }
  parts[2:3]
}

#' The conformance rows of an installed plugin package (contract 6.7, 11.12; IC-42)
#' @noRd
check_package = function(pkg, tokens = FALSE, adapter_check = NULL) {
  target = paste0("package:", pkg)
  installed = nzchar(ext_pkg_path(pkg))
  rows = list(check_row(target, "package.installed", installed))
  if (!installed) return(rows)
  path = ext_pkg_path(pkg, "gptr", "plugin.json")
  present = nzchar(path) && file.exists(path)
  rows = c(rows, list(check_row(target, "manifest.present", present, "inst/gptr/plugin.json")))
  man = NULL
  if (present) {
    man = tryCatch({
      parsed = json_decode(paste(readLines(path, encoding = "UTF-8", warn = FALSE),
                                 collapse = "\n"))
      check_manifest(parsed)
      parsed
    }, error = function(e) e)
    valid = !inherits(man, "error")
    rows = c(rows, list(check_row(target, "manifest.valid", valid,
                                  if (inherits(man, "error")) conditionMessage(man) else "")))
    if (!valid) man = NULL
  }
  req = man[["gptr"]][["api"]]
  if (is.null(req)) {
    desc = ext_pkg_description(pkg, "Config/gptr/api")
    if (!is.na(desc)) req = desc
  }
  rows = c(rows, list(check_row(target, "api.declared", !is.null(req), req %||% "")))
  if (!is.null(req)) {
    ok = isTRUE(tryCatch(api_satisfies(req), error = function(e) FALSE))
    rows = c(rows, list(check_row(target, "api.satisfied", ok,
                                  paste0("requires ", req, "; this gptr provides ",
                                         ext_api_version))))
  }
  entry = man[["extension"]][["entry"]]
  if (is.character(entry) && length(entry) == 1L) {
    parts = check_entry(entry)
    factory = tryCatch(ext_pkg_factory(parts[[1L]], parts[[2L]]), error = function(e) e)
    exported = is.function(factory)
    rows = c(rows, list(check_row(target, "factory.exported", exported, entry)))
    if (exported) rows = c(rows, check_factory(factory, man, tokens, adapter_check))
  }
  if (tokens && !is.null(man)) {
    decl = man[["extension"]][["declarations"]] %||% list()
    n = sum(vapply(decl, function(d) {
      est_tokens(paste(d[["signature"]] %||% "", d[["description"]] %||% ""), "code")
    }, 0))
    rows = c(rows, list(check_row(target, "tokens.declarations", TRUE,
                                  paste0(n, " tokens in ", length(decl), " declaration(s)"))))
  }
  bare = ext_bare_identifiers(ext_pkg_objects(pkg))
  hint = if (length(bare)) paste("use strings for", paste(bare, collapse = ", ")) else ""
  c(rows, list(check_row(target, "code.identifiers", !length(bare), hint)))
}

#' Check an extension for conformance
#'
#' Runs gptr's conformance suite, offline, in a scratch registry. For a spec: its fields and kind
#' validator, schema validity, direct tool descriptions of at most 400 tokens, prompt-section
#' budgets, empty-input handling of tools, the permission matrix for policies, start and cancel
#' for backends, and wire-fixture replay for adapters when the adapter checker is available. For
#' a factory `function(gptr)`: it loads, registers something, takes no action at load, and each
#' registered spec passes. For an installed package name: its `inst/gptr/plugin.json` manifest,
#' API requirement, factory, every provided capability, and bare gptr identifiers in its code.
#'
#' @param x A spec, a factory `function(gptr)`, or the name of an installed plugin package.
#' @param error `TRUE` to signal `gptr_error_conformance` when a check fails.
#' @param tokens `TRUE` to also report declaration costs and the printed cost of each member's
#'   `examples`.
#' @return A `gptr_check` data frame with columns `target`, `check`, `ok` and `message`.
#' @examples
#' gptr_check(gptr_tool("add", "Add two numbers",
#'                      parameters = list(type = "object", required = I(c("a", "b")),
#'                                        properties = list(a = list(type = "number"),
#'                                                          b = list(type = "number"))),
#'                      fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
#' @export
gptr_check = function(x, error = FALSE, tokens = FALSE) {
  check_flag(error, "error")
  check_flag(tokens, "tokens")
  adapter_check = if (ext_service_has("check.adapter")) ext_service_get("check.adapter") else NULL
  rows = check_in_scratch(function() {
    if (is.list(x) && !is.data.frame(x)) {
      check_spec(x, tokens, adapter_check)
    } else if (is.function(x)) {
      check_factory(x, NULL, tokens, adapter_check)
    } else if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)) {
      check_package(x, tokens, adapter_check)
    } else {
      gptr_abort("`x` must be a spec, a factory function(gptr) or an installed package name.",
                 "invalid_argument", arg = "x",
                 expected = "a gptr_spec, a function(gptr) or a package name")
    }
  })
  out = check_rows(rows)
  if (error && !all(out$ok)) {
    gptr_abort(paste0("gptr_check() found ", sum(!out$ok), " failing check(s): ",
                      paste(unique(out$check[!out$ok]), collapse = ", "), "."),
               "conformance", results = out)
  }
  out
}

#' Print conformance results: one line per check
#' @export
#' @noRd
print.gptr_check = function(x, ...) {
  cat("<gptr_check> ", nrow(x), " check(s), ", sum(!x$ok), " failed\n", sep = "")
  for (i in seq_len(nrow(x))) {
    msg = x$message[[i]]
    cat(if (x$ok[[i]]) "  ok    " else "  FAIL  ", x$target[[i]], "  ", x$check[[i]],
        if (nzchar(msg)) paste0(": ", msg) else "", "\n", sep = "")
  }
  invisible(x)
}
