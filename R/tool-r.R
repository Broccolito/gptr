# The `r` tool (P10; architecture 6.12, 7.2; contract 4.4, 7.9, 9.2): IC-68 schema variants,
# evaluation through the `evaluator` kind (IC-69) in the run's evaluation environment (IC-15), and
# format_eval_result() text with peter$plot() and peter$read() images in one budget (IC-67). The
# execute frame binds the r-call marker `gptr_r_call` through which member calls are gated.

r_tool_description = paste(
  "Run R code in the user's live R session. Objects persist between calls and belong to the user.",
  "Returns printed output, messages, warnings, errors with a traceback, and plots as images.",
  "Execution stops at the first error. Output beyond about 4000 tokens keeps the first 40% and",
  "last 60% and names a peter$out(id) handle for the rest."
)
r_tool_snippet =
  "Run R code in the user's live session (objects persist; plots come back as images)"
r_tool_guidelines = c(
  paste("Use r to inspect and compute on objects in the live session; never reload or recompute",
        "data that is already in memory"),
  paste("In r, assign results to names and print compact summaries (dim(), head(),",
        "peter$describe(x)) rather than whole objects"),
  "Use = for assignment and |> for pipes in all R code you write"
)

#' The `r` input schema variant (IC-68): `record` and `note` only with a document bound at freeze,
#' `timeout` only when no human can answer
#' @noRd
r_schema = function(document = FALSE, human = TRUE) {
  props = list(code = list(
    type = "string", description = "R code to evaluate. May contain several expressions."
  ))
  if (isTRUE(document)) {
    props$record = list(type = "boolean", description = paste(
      "Record this code in the user's document (default true).",
      "Use false for throwaway inspection."
    ))
    props$note = list(type = "string", description = paste(
      "One-line decision or rationale, recorded as a '## Decision:' comment."
    ))
  }
  if (!isTRUE(human)) {
    props$timeout = list(type = "number", description = "Seconds; best effort. Default 3600.")
  }
  list(type = "object", required = I("code"), properties = props)
}

#' The r tool's `parameters`, evaluated once at freeze with `ctx$input` (contract 10.2 row 14)
#' `document` is non-NULL when a history document is bound, `human` whether someone can answer.
#' @noRd
r_tool_parameters = function(ctx) {
  input = if (is.null(ctx)) NULL else ctx$input
  document = !is.null(input$document)
  if (is.null(input) && !is.null(ctx) && !is.null(ctx$session) && ext_service_has("doc.site")) {
    site = tryCatch(ext_service_get("doc.site")(ctx$session), error = function(e) NULL)
    document = !is.null(site)
  }
  human = if (is.null(input$human)) gptr_can_prompt() else isTRUE(input$human)
  r_schema(document = document, human = human)
}

#' The evaluator of a session: the `evaluator` record named by setting `evaluator` (default "r"),
#' else P09's eval_r() (IC-69)
#' @noRd
r_evaluator = function(session = NULL) {
  sid = if (is.null(session)) NULL else session$id
  name = setting_get("evaluator", session = session, default = "r") %||% "r"
  ev = registry_get("evaluator", name, session = sid)
  if (is.null(ev) || !is.function(ev$eval)) eval_r else ev$eval
}

#' Session hooks collecting bridge digests (`bridge_call`, P22) and artifact paths
#' (`artifact_start`, P23) into the r-call marker while the evaluation runs; returns the hook ids
#' @noRd
r_collect_hooks = function(rc, sid) {
  if (is.null(sid)) return(character())
  on_bridge = function(event, ctx) {
    if (is.character(event$digest)) rc$bridge = c(rc$bridge, event$digest)
    NULL
  }
  on_artifact = function(event, ctx) {
    if (is.character(event$id) && length(event$id) == 1L) {
      app = file.path(workspace_root(create = FALSE), "artifacts", event$id, "app.R")
      rc$artifacts = c(rc$artifacts, path_rel(app))
    }
    NULL
  }
  c(hook_add("bridge_call", on_bridge, rank = 6L, source = "builtin:r", session = sid),
    hook_add("artifact_start", on_artifact, rank = 6L, source = "builtin:r", session = sid))
}

#' Remove the collecting hooks
#' @noRd
r_collect_unhook = function(ids) {
  for (id in ids) hook_remove(id)
  invisible(NULL)
}

#' Printed-output lines of the completed expressions for `#>` comments: at most
#' gptr.doc_output_lines per expression, 76 characters each (contract section 4.4)
#' @noRd
r_doc_outputs = function(res) {
  outs = res$outputs %||% list()
  n = min(length(outs), as.integer(res$n_done %||% 0L))
  if (!n) return(character())
  cap = as.integer(gptr_opt("doc_output_lines"))
  lines = unlist(lapply(outs[seq_len(n)], function(o) {
    o = as.character(o)
    o = utils::head(o[nzchar(o)], cap)
    ifelse(nchar(o) > 76L, paste0(substr(o, 1L, 73L), "..."), o)
  }), use.names = FALSE)
  as_utf8(as.character(lines))
}

#' Name designated through gptr_return() during this call (the newest value record), or NULL
#' @noRd
r_new_value_name = function(session, n_before) {
  if (is.null(session)) return(NULL)
  vals = session_data(session)$values %||% list()
  if (length(vals) <= n_before) return(NULL)
  vals[[length(vals)]]$name
}

#' Messages of the events of one type
#' @noRd
r_event_text = function(events, type) {
  ev = Filter(function(e) identical(e$type, type), events)
  as.character(unlist(lapply(ev, function(e) e$message %||% e$text), use.names = FALSE))
}

#' The r tool result: format_eval_result() text and images, and the contract 4.4 `details`
#' (plus `plot_files`, the PNGs behind peter$plot(which))
#' @noRd
r_tool_result = function(code, record, note, res, fmt, rc, session, n_values) {
  events = res$events %||% list()
  plots = Filter(function(e) identical(e$type, "plot"), events)
  err = r_event_text(events, "error")
  images = fmt$images %||% list()
  rendered = Filter(function(e) is.character(e$path) && length(e$path) == 1L, plots)
  plot_files = vapply(rendered, function(e) e$path, "")
  plot_index = vapply(rendered, function(e) as.integer(e$index %||% NA_integer_), 0L)
  obj = res$changes$objects %||% list()
  objects = list(added = as.character(obj$added), modified = as.character(obj$modified),
                 removed = as.character(obj$removed))
  changes = res$changes
  changes$objects = NULL
  details = list(
    code = code, record = record, note = note, status = res$status,
    n_done = as.integer(res$n_done %||% 0L), n_total = as.integer(res$n_total %||% 0L),
    objects = objects, plots = length(images),
    warnings = redact_hook(r_event_text(events, "warning"), "persist"),
    error = if (length(err)) redact_hook(err[[1L]], "persist") else NULL,
    changes = changes, elapsed = res$elapsed, out_id = fmt$out_id, spill = fmt$spill,
    outputs = if (record) r_doc_outputs(res) else character(), nested = list(), bridge = rc$bridge,
    artifacts = rc$artifacts, checkpoint = NULL, value = r_new_value_name(session, n_values),
    plot_files = plot_files, plot_index = plot_index
  )
  text = fmt$text
  dropped = as.integer(rc$dropped %||% 0L)
  if (dropped > 0L) {
    text = paste0(text, "\n[", dropped, " image(s) from peter$plot() or peter$read() not ",
                  "attached: at most ", as.integer(gptr_opt("r_max_images")), " per r call]")
  }
  out = gptr_tool_result(text, images = if (length(images)) images else NULL, details = details,
                         is_error = !identical(res$status, "ok"))
  out$out_id = fmt$out_id
  out$spill = fmt$spill
  out$truncated = isTRUE(fmt$truncated)
  out
}

#' The r tool's execute: evaluate `code` in the run's evaluation environment
#' Copy safety R2, R3, R8: the environment is bound only while the call runs, no closure or
#' tryCatch(), the value is never kept; `gptr_r_call` holds the ctx and collectors only.
#' @noRd
r_tool_execute = function(input, ctx) {
  code = as_utf8(input$code)
  check_string(code, "code", empty = TRUE)
  record = if (is.null(input$record)) TRUE else isTRUE(input$record)
  note = input$note
  check_string(note, "note", null = TRUE, empty = TRUE)
  run = run_current()
  opts = if (is.null(run)) list() else run$opts %||% list()
  mode = if (is.null(run)) NULL else run$mode
  if (is.null(mode) && !is.null(ctx) && is.function(ctx$mode)) mode = ctx$mode()
  if (identical(mode, "plan")) record = FALSE
  timeout = input$timeout %||% opts$timeout
  envir = if (is.null(run)) ctx$envir else run_eval_env(run)
  on.exit({
    envir = NULL
  }, add = TRUE)
  if (!is.environment(envir)) {
    gptr_abort("The r tool has no evaluation environment.", "internal",
               detail = "no run and no ctx$envir")
  }
  session = if (is.null(ctx)) NULL else ctx$session
  gptr_r_call = r_call_new(ctx)
  hooks = r_collect_hooks(gptr_r_call, if (is.null(session)) NULL else session$id)
  on.exit(r_collect_unhook(hooks), add = TRUE)
  n_values = if (is.null(session)) 0L else length(session_data(session)$values %||% list())
  budget = as.integer(gptr_opt("r_output_tokens"))
  evaluate = r_evaluator(session)
  res = evaluate(code, envir, timeout = timeout, budget_tokens = budget, rng = opts$rng_state,
                 record = record)
  envir = NULL
  # images attached by peter$plot() and peter$read() count against the budget too (IC-67)
  res$images = c(res$images, gptr_r_call$images)
  fmt = format_eval_result(res, budget)
  r_tool_result(code, record, note, res, fmt, gptr_r_call, session, n_values)
}

#' builtin:r: the `r` tool (contract sections 7.10 and 9.2); no `risk` function, because P06's
#' call_risk() already rates r calls through the `risk.classify` service (level 2 without it)
#' @noRd
builtin_r = function(gptr) {
  gptr$register(gptr_tool("r", r_tool_description, parameters = r_tool_parameters,
                          execute = r_tool_execute, exposure = "direct", execution = "sequential",
                          snippet = r_tool_snippet, guidelines = r_tool_guidelines, record = TRUE))
  invisible(NULL)
}

on_load(ext_declare_builtin("r", builtin_r))
