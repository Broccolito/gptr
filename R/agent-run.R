# agent-run.R -- the run lifecycle on the reactor (P06, layer L3).
#
# A run drives the pure loop of agent-loop.R from reactor callbacks: `run_start()` registers the run
# and one reactor task that asks the loop for its next action; requests go out through P05's
# `provider_stream()` with the run's emit/done callbacks; tool batches run in the reactor's tool
# FIFO (sequential tools) or directly (concurrent batches); steering is delivered after complete
# tool results. Recovery follows report 02 sections 2.8-2.9 and 5.3 (`run_with_recovery()`) with
# gptr's constants (C-33: at most 2 agent-level retries, 2 s then 4 s; one compact-and-retry on
# overflow). The interrupt policy is the `console.interrupt_policy` service (P14) when registered,
# else abort-only (report 02 section 4.8; G3 finding 5). No run state lives in the package
# namespace (INFRA-15): the reactor holds active runs until they settle.

#' A new run record (04 section 7.6 fields plus private fields)
#'
#' The safety options are snapshotted here for a root run and inherited by nested runs (IC-53);
#' a nested run's mode is the stricter of the outer run's and the session's. The evaluation
#' environment is the gateway's choice (`opts$call$envir`, IC-40) or the kept home; it is held only
#' in the `home` binding, which is reset to NULL at settlement (rule R2).
#' @return An environment of class `gptr_run`.
#' @noRd
run_new = function(s, opts, outer) {
  d = session_data(s)
  live = session_live(s)
  run = new.env(parent = emptyenv())
  class(run) = "gptr_run"
  run$id = id_new("u", 8L)
  run$session = d$id
  run$shell = s
  run$status = "queued"
  run$turn = 0L
  run$opts = opts
  run$opts$safety = opts$safety %||% (if (is.null(outer)) safety_snapshot() else outer$opts$safety)
  # the run option `interactive = FALSE` (04 section 7.6: "a human can answer") means nobody can
  # answer this run's gate (background runs, children without a human): asks stop or deny
  if (isFALSE(opts$interactive)) run$opts$safety$can_prompt = FALSE
  run$mode = if (is.null(outer)) d$mode else run_mode_tighter(outer$mode, d$mode)
  run$model = NULL
  run$depth = as.integer(opts$depth %||% d$depth)
  run$parent_run = opts$parent_run %||% (if (is.null(outer)) NULL else outer$id)
  run$signal = new.env(parent = emptyenv())
  run$signal$aborted = FALSE
  run$signal$reason = NULL
  # IC-53 item 3: the one-shot approval tokens (names of control exports approved through an
  # ask_human for the executing call), the slot P08's control_check() consumes; and the stored,
  # unsignalled condition of the terminal status that P08's gateway_signal() reads
  run$signal$control = character()
  run$signal$condition = NULL
  run$started = Sys.time()
  run$children = character()
  run$outer = outer
  run$max_turns = as.integer(opts$max_turns %||% d$max_turns %||% gptr_opt("max_turns"))
  run$budget = run_budget_limits(s, opts, outer)
  # the shared pool of a root without a run (opts$root names a team or fan-out container, IC-66)
  run$budget_root = if (is.null(outer)) run_budget_pool(s, opts) else NULL
  run$usage_start = nrow(d$usage)
  run$near = character()
  run$home = opts$call$envir %||% live$home
  plan = identical(run$mode, "plan") && !is.null(run$home)
  run$scratch = if (plan) new.env(parent = run$home) else NULL
  run$busy = FALSE
  run$settled = FALSE
  run$requested = FALSE
  run$counted_turn = FALSE
  run$attempt = 0L
  run$overflow_used = FALSE
  run$transfers = character()
  run$timers = character()
  run$fifo = character()
  run$request_ids = character()
  run$nested = list()
  run$nested_count = list()
  run$pending_operator = list()
  run$pending_model = NULL
  run$pending_compact = NULL
  run$blocked = NULL
  run$condition = NULL
  run$message = NULL
  run$tool_call = NULL
  run$abort_after_call = FALSE
  if (!is.null(outer)) outer$children = unique(c(outer$children, d$id))
  run
}

#' The safety options of a run, snapshotted at its start (IC-53 item 2)
#' @noRd
safety_snapshot = function() {
  list(ui = getOption("gptr.ui"), interactive = getOption("gptr.interactive"),
       critical_guard = gptr_opt("critical_guard"), secret_guard = gptr_opt("secret_guard"),
       noninteractive_ask = gptr_opt("noninteractive_ask"), protect_size = gptr_opt("protect_size"),
       mode = getOption("gptr.mode"),
       unsafe_no_permissions = isTRUE(gptr_opt("unsafe_no_permissions")),
       can_prompt = gptr_can_prompt(), has_human = gptr_has_human())
}

#' The stricter of two modes (plan < manual < edits < auto)
#' @noRd
run_mode_tighter = function(a, b) session_modes[min(match(c(a, b), session_modes))]

#' The innermost run whose tool is executing on this call stack, or NULL
#'
#' A tool executes inside `tool_execute_frame()` (agent-dispatch.R), whose frame binds the marker
#' `.gptr_tool_run`; the call stack is walked with `sys.frame(k)` (never `sys.frames()`, R3), so
#' no package-global stack exists (INFRA-15).
#' @noRd
run_current = function() {
  k = sys.nframe()
  while (k > 0L) {
    run = get0(".gptr_tool_run", envir = sys.frame(k), inherits = FALSE)
    if (inherits(run, "gptr_run")) return(run)
    k = k - 1L
  }
  NULL
}

#' Where `r` evaluates for this run: the plan-mode scratch overlay (IC-15), else the run's home
#' @noRd
run_eval_env = function(run) {
  if (is.null(run)) return(NULL)
  run$scratch %||% run$home
}

#' Build and dispatch an agent event for a run (ev_dispatch() redacts the payload)
#' @return The dispatch result (decision, collect and patch events).
#' @noRd
run_emit = function(run, type, ...) {
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  ev = ev_new(type, session = d$id, run = run$id, agent = run$opts$agent %||% "main",
              turn = d$turns, ...)
  ev_dispatch(type, ev, session = s, ctx = if (is.null(live)) NULL else live$ctx)
}

#' Build and dispatch a session event (outside a run, or for the session's current run)
#' @noRd
session_emit = function(s, type, ...) {
  d = session_data(s)
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  ev = ev_new(type, session = d$id, run = if (is.null(run)) NULL else run$id, agent = "main",
              turn = d$turns, ...)
  ev_dispatch(type, ev, session = s, ctx = if (is.null(live)) NULL else live$ctx)
}

#' The UI backend of a run (the `ui.get` service of P11), or NULL
#' @noRd
run_ui = function(run) {
  if (!ext_service_has("ui.get")) return(NULL)
  tryCatch(ext_service_get("ui.get")(run$shell), error = function(e) NULL)
}

# The dispatcher (agent-dispatch.R) is layer L2: it may call L0, L1 records and its own `agent`
# area, never the L3 session files (03 section 2.2; P01's test-arch-layers.R). It reaches the
# session only through its run and the agent-area helpers below.

#' The data environment of a run's session
#' @noRd
run_data = function(run) session_data(run$shell)

#' The live record of a run's session, or NULL
#' @noRd
run_live = function(run) session_live(run$shell)

#' The ctx of a run's session, or NULL
#' @noRd
run_ctx = function(run) {
  live = session_live(run$shell)
  if (is.null(live)) NULL else live$ctx
}

#' The id of a ctx's session, or NULL for a process-level ctx
#' @noRd
run_ctx_sid = function(ctx) {
  s = ctx$session
  if (is.null(s)) NULL else session_data(s)$id
}

#' Append a message (a tool result) to a run's session; returns the entry id invisibly
#' @noRd
run_append_message = function(run, msg) session_append(run$shell, entry_message(msg))

#' Append a custom entry to a run's session; returns the entry id invisibly
#' @noRd
run_append_custom = function(run, type, data) {
  session_append(run$shell, entry_custom(type, data))
}

# ---------------------------------------------------------------------------- recovery

# Error-text patterns: provider error-message facts collected by Pi (MIT licence;
# packages/ai/src/utils/overflow.ts and retry.ts at commit 1b347794), transcribed in report 02
# section 5.3 (`recovery.R`, with the verifier's fixes) and gptr's libcurl additions. Matched with
# perl = TRUE and ignore.case = TRUE.
overflow_patterns = c(
  "prompt (?:is )?too long", "request_too_large", "input is too long for requested model",
  "exceeds the context window",
  "exceeds (?:the )?(?:model'?s )?maximum context length(?: of [\\d,]+ tokens?|\\s*\\([\\d,]+\\))",
  "input token count.*exceeds the maximum", "maximum prompt length is \\d+",
  "reduce the length of the messages", "maximum context length is \\d+ tokens",
  "exceeds (?:the )?maximum allowed input length of [\\d,]+ tokens?",
  "input \\(\\d+ tokens\\) is longer than the model'?s context length \\(\\d+ tokens\\)",
  "exceeds the limit of \\d+", "exceeds the available context size",
  "greater than the context length", "context window exceeds limit", "exceeded model token limit",
  "too large for model with \\d+ maximum context length",
  "prompt has [\\d,]+ tokens?, but the configured context size is [\\d,]+ tokens?",
  "model_context_window_exceeded", "prompt too long; exceeded (?:max )?context length",
  "range of input length should be", "context[_ ]length[_ ]exceeded", "too many tokens",
  "token limit exceeded")
non_overflow_patterns = c("^(Throttling error|Service unavailable):", "rate limit",
                          "too many requests")
bodyless_overflow_pattern = "^4(?:00|13)\\s*(?:status code)?\\s*\\(no body\\)"
non_retryable_pattern = paste(c(
  "GoUsageLimitError", "FreeUsageLimitError", "Monthly usage limit reached", "available balance",
  "insufficient_quota", "out of budget", "quota exceeded", "billing",
  "subscription_sharing_usage_limit_exceeded"), collapse = "|")
retryable_pattern = paste(c(
  "overloaded", "currently experiencing high demand", "rate.?limit", "too many requests", "429",
  "500", "502", "503", "504", "520", "524", "service.?unavailable", "server.?error",
  "internal.?error", "provider.?returned.?error",
  "exceeded request buffer limit while retrying upstream", "network.?error",
  "connection.?error", "connection.?refused", "connection.?lost", "other side closed",
  "fetch failed", "getaddrinfo", "ENOTFOUND", "EAI_AGAIN", "upstream.?connect",
  "reset before headers", "socket hang up", "socket connection was closed", "timed? out",
  "timeout", "terminated", "websocket.?closed", "websocket.?error", "ended without",
  "stream ended before message_stop", "stream ended before a terminal response event",
  "http2 request did not get a response", "retry delay", "you can retry your request",
  "try your request again", "please retry your request", "ResourceExhausted",
  "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable",
  "could not resolve host", "failed to connect", "recv failure", "send failure",
  "ssl connect error", "transfer closed with", "empty reply from server"), collapse = "|")

#' Does any of the patterns match the text? (PCRE, case-insensitive)
#' @noRd
any_match = function(patterns, x) {
  any(vapply(patterns, function(p) grepl(p, x, perl = TRUE, ignore.case = TRUE), NA))
}

#' The error text of a message: its `error_message` when that is one string, else ""
#' @noRd
run_error_text = function(msg) {
  x = if (is.list(msg)) msg[["error_message"]] else NULL
  if (is.character(x) && length(x) == 1L && !is.na(x)) x else ""
}

#' A context window in tokens (one positive finite number), else NA
#' @noRd
overflow_window = function(x) {
  if (!(is.numeric(x) || is.character(x)) || length(x) != 1L) return(NA_real_)
  x = suppressWarnings(as.numeric(x))
  if (is.finite(x) && x > 0) x else NA_real_
}

#' One token count of a usage record: 0 when the record leaves it out (P05's legacy zero of a
#' reported usage), NA when it is unknown (an explicit null, as in P05's `usage_from_json()`) or
#' not one nonnegative number (IC-74)
#' @noRd
overflow_count = function(usage, field) {
  if (!field %in% names(usage)) return(0)
  x = usage[[field]]
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0) return(NA_real_)
  as.numeric(x)
}

#' Is a response a context overflow? (report 02 section 5.3 `is_context_overflow()`)
#'
#' Three signals: the error record's class, the provider's error text (the 21 texts of report 02,
#' the 413/no-body forms), and a silent overflow shown by the reported usage. Under IC-74 an
#' unknown count is not zero: the known prompt counts are a lower bound, which proves an overflow
#' only when it alone exceeds the window, and an estimated usage (`estimated = TRUE`, gptr's own
#' guess) proves nothing. Malformed records give FALSE, never an error.
#' @param message An assistant message (R shape).
#' @param context_window The model's window in tokens, or NULL/NA.
#' @param error The error record of the terminal `error` event, if any.
#' @noRd
is_context_overflow = function(message, context_window = NULL, error = NULL) {
  if (identical(err_class(error), "context_overflow")) return(TRUE)
  if (!is.list(message)) return(FALSE)
  err = run_error_text(message)
  if (identical(message[["stop_reason"]], "error") && nzchar(err) &&
      !any_match(non_overflow_patterns, err)) {
    if (any_match(overflow_patterns, err)) return(TRUE)
    if (identical(message[["provider"]], "cerebras") && any_match(bodyless_overflow_pattern, err)) {
      return(TRUE)
    }
  }
  window = overflow_window(context_window)
  usage = message[["usage"]]
  if (is.na(window) || !is.list(usage) || isTRUE(usage[["estimated"]])) return(FALSE)
  input = sum(overflow_count(usage, "input"), overflow_count(usage, "cache_read"), na.rm = TRUE)
  if (identical(message[["stop_reason"]], "stop") && input > window) return(TRUE)
  identical(message[["stop_reason"]], "length") &&
    identical(overflow_count(usage, "output"), 0) && input >= window * 0.99
}

#' Does an error text describe a transient failure? (non-retryable patterns win)
#' @noRd
retryable_error_text = function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) return(FALSE)
  if (grepl(non_retryable_pattern, text, perl = TRUE, ignore.case = TRUE)) return(FALSE)
  grepl(retryable_pattern, text, perl = TRUE, ignore.case = TRUE)
}

#' The HTTP status of an error record as one integer, else NA
#' @noRd
err_status = function(err) {
  st = if (is.list(err)) err[["status"]] else NULL
  if (!(is.numeric(st) || is.character(st)) || length(st) != 1L) return(NA_integer_)
  suppressWarnings(as.integer(st))
}

#' The gptr class name of an error record (`list(class, status, ...)` of an `error` event)
#' @noRd
err_class = function(err) {
  cls = if (is.list(err)) err[["class"]] else NULL
  cls = if (is.character(cls)) cls[!is.na(cls) & nzchar(cls)] else character()
  cls = setdiff(sub("^gptr_error_", "", cls),
                c("gptr_error", "error", "condition", "provider", "timeout"))
  if (length(cls)) return(cls[[1L]])
  st = err_status(err)
  if (is.na(st)) return(NA_character_)
  if (st %in% c(401L, 403L)) return("auth")
  if (st == 429L) return("rate_limit")
  if (st >= 500L) return("overloaded")
  NA_character_
}

#' The condition classes of a failed request (most specific first)
#' @noRd
provider_classes = function(err) {
  k = err_class(err)
  if (is.na(k)) return("provider")
  if (startsWith(k, "timeout")) return(c(k, "timeout"))
  if (k %in% c("auth", "rate_limit", "spend_cap", "retry_after", "overloaded", "context_overflow",
               "network", "redirect", "billing")) return(c(k, "provider"))
  "provider"
}

#' Is a failed request transient, to be retried at agent level?
#'
#' Never an overflow (compaction recovers it, Pi's `_isRetryableError()`), never a provider's
#' definitive answer (auth, spend cap, a long retry-after, a redirect, billing, quota texts), and
#' never one of gptr's own local failures (no credential, an unavailable or untrusted model, an
#' invalid argument or spec, a missing package), whose message is gptr's text, not a provider's.
#' @noRd
run_retryable = function(msg, err) {
  if (is_context_overflow(msg, NULL, err)) return(FALSE)
  text = run_error_text(msg)
  k = err_class(err)
  if (!is.na(k) && k %in% c("spend_cap", "auth", "retry_after", "redirect", "billing",
                            "context_overflow", "no_key", "not_available", "untrusted",
                            "invalid_argument", "invalid_spec", "missing_package")) {
    return(FALSE)
  }
  quota = grepl(non_retryable_pattern, text, perl = TRUE, ignore.case = TRUE)
  if (!is.na(k) && k %in% c("overloaded", "rate_limit", "network", "timeout_idle",
                            "timeout_first_byte", "timeout_connect")) {
    return(!quota)
  }
  st = err_status(err)
  if (!is.na(st) && (st %in% c(408L, 409L, 429L, 529L) || st >= 500L)) return(!quota)
  retryable_error_text(text)
}

#' Agent-level retry delays in seconds: 2 s, then 4 s (C-33)
#' @param attempt The number of the retry (1 for the first).
#' @noRd
agent_retry_delay = function(attempt) {
  attempt = check_number(attempt, "attempt", min = 1, int = TRUE)
  c(2, 4)[min(attempt, 2L)]
}

# ---------------------------------------------------------------------------- freeze and input

#' Freeze the prompt at the first run
#'
#' Emits `session_start` (collect), then calls the `prompt.freeze` service (P07) or the documented
#' fallback (empty T0/T1 and the core tools' JSON, 04 section 7.0); blocks returned by
#' `session_start` handlers join the first user message.
#' @return The input messages, with the collected blocks inserted.
#' @noRd
run_freeze = function(run, input) {
  s = run$shell
  d = session_data(s)
  if (length(d$frozen)) return(input)
  collected = run_emit(run, "session_start", reason = session_start_reason(d))
  if (ext_service_has("prompt.freeze")) {
    # the run options P07's prompt_compose() reads (`preset`, `tools`, `doc`, `system`, `call`),
    # plus `start` (the merged session_start result), `interactive` and `refreeze` (IC-52)
    fopts = run$opts
    fopts$start = collected
    fopts$interactive = fopts$interactive %||% isTRUE(fopts$safety$can_prompt)
    fopts$refreeze = isTRUE(d$refreeze)
    fr = ext_service_get("prompt.freeze")(s, fopts)
    if (!length(d$frozen)) d$frozen = fr
  } else {
    freeze_fallback(s)
  }
  d$refreeze = FALSE
  blocks = if (is.list(collected)) collected$blocks else NULL
  if (length(blocks) && !is.null(input)) input = input_insert_blocks(input, blocks)
  input
}

#' The `session_start` reason of a session's first freeze
#' @noRd
session_start_reason = function(d) {
  if (!is.null(d$fork_of)) return("fork")
  if (identical(d$kind, "child")) return("child")
  if (identical(d$kind, "replayed")) return("replay")
  if (length(d$entries)) return("resume")
  "new"
}

#' The fallback freeze used before P07 is loaded: empty T0/T1 and the four core tools' JSON
#'
#' As at any freeze (04 section 9.1), a tool's `available(ctx)` decides whether it is offered and
#' a `parameters` function is evaluated once, with the session's ctx (freeze_tool_decl()).
#' @noRd
freeze_fallback = function(s) {
  d = session_data(s)
  live = session_live(s)
  ctx = if (is.null(live)) NULL else live$ctx
  core = c("read", "r", "edit", "write")
  decls = lapply(core, function(n) freeze_tool_decl(tool_lookup(n, d$id), ctx))
  keep = !vapply(decls, is.null, NA)
  fr = list(t0 = "", t1 = "", tools_json = json_encode(decls[keep]), tool_names = core[keep],
            sections = frozen_sections_df(list()))
  d$frozen = fr
  session_append(s, entry_custom("gptr.frozen",
                                 list(preset = d$preset, t0 = "", t1 = "",
                                      toolsJson = fr$tools_json,
                                      toolNames = I(fr$tool_names), sections = list(),
                                      model = d$model)))
  invisible(fr)
}

#' The frozen declaration `{name, description, input_schema}` of a tool (Anthropic shape, 04
#' section 9.1), or NULL when the tool is absent, its `available(ctx)` is not TRUE, or it has no
#' object schema; a failing `available()` or `parameters()` leaves the tool out with a diagnostic
#' @noRd
freeze_tool_decl = function(tool, ctx) {
  if (is.null(tool)) return(NULL)
  left_out = function(why) {
    registry_diagnostic("session", "freeze", "tool_left_out",
                        paste0("tool ", tool[["name"]], " is not frozen: ", why))
    NULL
  }
  avail = tool[["available"]]
  if (is.function(avail)) {
    ok = tryCatch(isTRUE(avail(ctx)), error = function(e) {
      left_out(paste0("available() failed: ", conditionMessage(e)))
      FALSE
    })
    if (!ok) return(NULL)
  }
  params = tool[["parameters"]]
  schema = if (is.function(params)) {
    tryCatch(params(ctx), error = function(e) e)
  } else {
    tool_schema(tool) %||% list(type = "object", properties = json_obj())
  }
  if (inherits(schema, "error")) {
    return(left_out(paste0("parameters() failed: ", conditionMessage(schema))))
  }
  if (!is.list(schema) || !identical(schema[["type"]], "object")) {
    return(left_out("its parameters are not a JSON Schema with type \"object\""))
  }
  list(name = tool[["name"]], description = tool[["description"]], input_schema = schema)
}

#' Insert context blocks contributed by session_start handlers into the first user message,
#' after its leading context blocks and before its text
#' @noRd
input_insert_blocks = function(input, blocks) {
  for (i in seq_along(input)) {
    m = input[[i]]
    if (!is.list(m) || !identical(m[["role"]], "user")) next
    content = m$content
    pos = which(!vapply(content, function(b) identical(b$type, "context"), NA))
    at = if (length(pos)) pos[[1L]] - 1L else length(content)
    m$content = append(content, blocks, after = at)
    input[[i]] = m
    break
  }
  input
}

# ---------------------------------------------------------------------------- the next request

#' The model record of the next request: a pending `ctx$set_model()` switch first, then the router
#' (`router.call`, IC-69) for `router:` models, else the session's model
#'
#' The pending switch is applied as the idle `ctx$set_model()` applies it (kernel_model_switch()),
#' so its `model_change` entry records the thinking level too.
#' A decision-only (classifier) model is refused here, before any request is built, with the
#' condition of provider_stream()'s refusal (IC-74, D-017). The session's thinking level is
#' clamped to the model's levels, as P05's model_resolve() clamps a `:<level>` suffix.
#' @noRd
run_target = function(run) {
  s = run$shell
  d = session_data(s)
  pm = run$pending_model
  if (!is.null(pm)) {
    run$pending_model = NULL
    kernel_model_switch(s, pm$ref, pm$thinking, pm$reason %||% "plugin")
  }
  if (startsWith(d$model, "router:")) return(run_route(run, "turn"))
  if (is.null(run$model) || !identical(run$model_key, d$model)) {
    rec = run_model_resolve(d$model, d$id)
    stream_chat_model(rec)
    run$model = rec
    run$model_key = d$model
  }
  if (!is.null(d$thinking)) {
    run$model$thinking = model_clamp_thinking(run$model$thinking_levels, d$thinking)
  }
  run$model
}

#' Resolve a model reference for a session: P05's catalog first, else a provider registered at
#' rank 0 for this session only (`model = <spec:provider>`, 04 section 6.1), which the catalog
#' does not list; P05's model_resolve() accepts that spec (its first model), so the spec is
#' narrowed to the declared model the reference names. A model id may hold a colon (an Ollama tag
#' such as `qwen3:8b`, IC-74), so the whole id is tried first, and a `:<suffix>` counts as a
#' thinking level only when it is one (P05's rule). Anything else is the strict, classed
#' `gptr_error_unknown_model` of model_resolve().
#' @noRd
run_model_resolve = function(ref, sid) {
  rec = model_resolve(ref, strict = FALSE)
  if (!is.null(rec)) return(rec)
  if (grepl("/", ref, fixed = TRUE)) {
    pr = tryCatch(registry_get("provider", sub("/.*$", "", ref), session = sid),
                  error = function(e) NULL)
    if (inherits(pr, "gptr_provider")) {
      mid = sub("^[^/]*/", "", ref)
      rec = session_model_resolve(pr, mid)
      if (!is.null(rec)) return(rec)
      pos = regexpr(":[^:]*$", mid)
      level = if (pos > 0L) substring(mid, pos + 1L) else ""
      if (level %in% catalog_thinking_levels) {
        rec = session_model_resolve(pr, substr(mid, 1L, pos - 1L))
        if (!is.null(rec)) {
          rec$thinking = model_clamp_thinking(rec$thinking_levels, level)
          return(rec)
        }
      }
    }
  }
  model_resolve(ref)
}

#' The model record of a session-registered provider spec's model `id` (by `id`, or the `ref` P08's
#' specs may carry), or NULL when the spec declares no such model
#' @noRd
session_model_resolve = function(pr, id) {
  model_id = function(m) as.character(m[["id"]] %||% sub("^[^/]*/", "", m[["ref"]] %||% ""))
  keep = Filter(function(m) is.list(m) && identical(model_id(m), id), pr$models %||% list())
  if (!length(keep)) return(NULL)
  pr$models = keep[1L]
  model_resolve(pr)
}

#' Ask the session's router for the model (IC-69)
#'
#' A failing router or an unusable answer (no model, a model that does not resolve, or a
#' decision-only model, which cannot hold a conversation, IC-74) falls back to the default chat
#' model with a diagnostic, keeping the router's last state. A switch is a model other than the
#' one of the branch's last `model_change` entry, so a new run on the same branch records none.
#' Each switch appends `model_change` (reason `router`) and `gptr.router`, and emits `route`; a
#' fallback is a switch only when it changes the model (IC-69, as P08's `router_fallback()`).
#' @param reason `"turn"` or `"compaction"`.
#' @noRd
run_route = function(run, reason = "turn") {
  s = run$shell
  d = session_data(s)
  router = sub("^router:", "", d$model)
  res = tryCatch(ext_service_get("router.call")(s, reason), error = function(e) e)
  ans = if (inherits(res, "error")) {
    list(why = paste0("failed: ", conditionMessage(res)))
  } else {
    route_answer(res, d$id)
  }
  path = entries_path(d)
  state = NULL
  rec = ans$rec
  if (is.null(rec)) {
    registry_diagnostic("session", "router", "router_fallback",
                        paste0("router ", router, " ", ans$why, "; using the default model"))
    rec = route_default(router, d)
    state = path_router_state(path)
  } else if (is.list(res)) {
    state = res[["state"]]
  }
  run$model = rec
  run$model_key = NULL
  if (identical(path_model_ref(path), rec$ref)) return(rec)
  if (!is.null(state) && inherits(tryCatch(json_encode(state), error = function(e) e), "error")) {
    registry_diagnostic("session", "router", "router_state",
                        paste0("router ", router, " returned a state that is not JSON; not kept"))
    state = NULL
  }
  session_append(s, entry_model_change(rec$ref, rec$thinking, "router"))
  session_append(s, entry_custom("gptr.router",
                                 drop_null(list(router = router, state = state, model = rec$ref,
                                                reason = reason))))
  run_emit(run, "route", route = "router", router = router, model = rec$ref, reason = reason)
  rec
}

#' The model record of a router's answer (`list(model, thinking, state)` or a model reference),
#' as `list(rec)`, or `list(why)` when the answer is unusable
#' @noRd
route_answer = function(res, sid) {
  ref = if (is.list(res)) res[["model"]] else res
  if (!is.character(ref) || length(ref) != 1L || is.na(ref) || !nzchar(ref)) {
    return(list(why = "gave no model"))
  }
  rec = tryCatch(run_model_resolve(ref, sid), error = function(e) e)
  if (inherits(rec, "error")) {
    return(list(why = paste0("chose a model that does not resolve (", ref, "): ",
                             conditionMessage(rec))))
  }
  if (identical(rec$type, "classifier")) {
    return(list(why = paste0("chose the decision-only model ", rec$ref, ", which cannot hold a ",
                             "conversation")))
  }
  th = if (is.list(res)) res[["thinking"]] else NULL
  if (is.character(th) && length(th) == 1L && !is.na(th)) {
    rec$thinking = model_clamp_thinking(rec$thinking_levels, th)
  }
  list(rec = rec)
}

#' The default chat model a router falls back to (a decision-only default is refused)
#' @noRd
route_default = function(router, d) {
  ref = model_default("chat")
  if (is.null(ref)) {
    gptr_abort(paste0("router ", router, " gave no model and no default model is configured"),
               "unknown_model", ref = d$model, suggestions = character())
  }
  rec = run_model_resolve(ref, d$id)
  stream_chat_model(rec)
  rec
}

#' The model of the last `model_change` entry of a path, or NULL
#' @noRd
path_model_ref = function(path) {
  for (e in rev(path)) {
    if (identical(e$type, "model_change")) {
      return(e$gptr$ref %||% paste0(e$provider, "/", e$model_id))
    }
  }
  NULL
}

#' The router state of the last `gptr.router` entry of a path, or NULL
#' @noRd
path_router_state = function(path) {
  for (e in rev(path)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.router")) {
      return(e$data$state)
    }
  }
  NULL
}

#' The request for a target: the `request.build` service (P07) then image elision, or the fallback
#' (which elides before it estimates)
#' @return `list(context, view, tokens_est, components)`.
#' @noRd
run_build = function(run, target) {
  s = run$shell
  if (ext_service_has("request.build")) {
    req = ext_service_get("request.build")(s, target, NULL)
    req$context$messages = images_elide(s, req$context$messages, target)
  } else {
    req = request_fallback(run, target)
  }
  req$context$request_id = req$context$request_id %||% id_new("q", 12L)
  req$context$session_id = req$context$session_id %||% session_data(s)$id
  req$tokens_est = req$tokens_est %||% 0
  req
}

#' The fallback request before P07 is loaded: the projected messages after image elision (so the
#' estimate counts what is sent) and the frozen tools
#' @noRd
request_fallback = function(run, target) {
  s = run$shell
  d = session_data(s)
  fr = d$frozen
  msgs = images_elide(s, project_messages(d$entries, d$leaf, target), target)
  tools = lapply(fr$tool_names %||% character(), function(n) tool_lookup(n, d$id))
  tools = Filter(Negate(is.null), tools)
  transcript = sum(vapply(msgs, msg_tokens_est, 1))
  static = frozen_tokens(fr)
  max_out = suppressWarnings(as.numeric(target$max_output %||% NA))
  context = list(system = list(t0 = fr$t0 %||% "", t1 = fr$t1 %||% ""),
                 tools_json = json_verbatim(fr$tools_json %||% "[]"), tools = tools,
                 messages = msgs,
                 cache_plan = list(anchors = character(), tail_ttl = "5m", key = ""),
                 params = list(max_tokens = if (is.finite(max_out)) as.integer(max_out) else 8192L,
                               thinking = target$thinking, effort = NULL, tool_choice = "auto",
                               returns = run$opts$returns, temperature = NULL),
                 session_id = d$id, request_id = id_new("q", 12L))
  list(context = context, view = NULL, tokens_est = static + transcript,
       components = list(tools = static, transcript = transcript))
}

#' Estimated tokens of a frozen prompt: T0 and T1 as prose, the tool array as JSON
#' @noRd
frozen_tokens = function(fr) {
  if (!length(fr)) return(0)
  est_tokens(fr$t0 %||% "", "prose") + est_tokens(fr$t1 %||% "", "prose") +
    est_tokens(fr$tools_json %||% "", "json")
}

#' Estimated tokens of a message's content (03 section 12.5): text, context and thinking blocks
#' as prose, tool-call arguments as JSON and images by their size (the 1000 x 700 default of
#' `gptr$plot()` when the block does not say); an image whose id is in `elided` counts as the text
#' that replaces it (images_elide())
#' @noRd
msg_tokens_est = function(m, elided = character()) {
  total = 0
  for (b in m[["content"]] %||% list()) {
    type = if (is.list(b)) b[["type"]] else NULL
    if (!is.character(type) || length(type) != 1L || is.na(type)) next
    total = total + switch(type,
      text = ,
      context = est_tokens(b[["text"]], "prose"),
      thinking = est_tokens(b[["thinking"]], "prose"),
      tool_call = tryCatch(est_tokens(json_encode(b[["arguments"]] %||% json_obj()), "json"),
                           error = function(e) 0),
      image = image_tokens_est(b, elided),
      0)
  }
  total
}

#' Estimated tokens of an image block (Anthropic's formula, est_image_tokens()), or of its
#' omission text when its id is in `elided`
#' @noRd
image_tokens_est = function(b, elided = character()) {
  if (length(elided)) {
    id = image_id(b)
    if (!is.na(id) && id %in% elided) return(est_tokens(image_omitted_text(id), "prose"))
  }
  size = function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 1
  w = b[["width"]]
  h = b[["height"]]
  if (!size(w) || !size(h)) {
    w = 1000
    h = 700
  }
  est_image_tokens(w, h)
}

#' The `request_params` patch chain over the adapter's declared non-prefix fields (IC-69)
#' @noRd
run_request_params = function(run, target, params) {
  adapter = tryCatch(adapter_get(target$api), error = function(e) NULL)
  fields = adapter$capabilities$request_params %||% character()
  if (!length(fields)) return(params)
  res = run_emit(run, "request_params", provider = target$provider, model = target$ref,
                 params = params[intersect(names(params), fields)])
  patched = if (is.list(res)) res$params else NULL
  if (!is.list(patched)) return(params)
  bad = setdiff(names(patched), fields)
  if (length(bad)) {
    registry_diagnostic("session", "request_params", "ignored_patch",
                        paste0("request_params handlers may not patch: ",
                               paste(bad, collapse = ", ")))
  }
  for (f in intersect(names(patched), fields)) params[f] = list(patched[[f]])
  params
}

#' Older images projected as omitted when a request exceeds the model's image count or 32 MB (IC-67)
#'
#' Newly elided images are recorded by one appended `gptr.image_elision` entry (one stated cache
#' break); images elided earlier on the path stay elided. An image is elided by its id, so every
#' copy of it goes at once and the next request projects the same messages.
#' @noRd
images_elide = function(s, messages, target) {
  info = images_scan(messages)
  if (!nrow(info)) return(messages)
  d = session_data(s)
  max_n = suppressWarnings(as.numeric(target[["max_images"]] %||% NA))
  keep = !(info$id %in% elided_image_ids(d))
  over = function() (is.finite(max_n) && sum(keep) > max_n) || sum(info$bytes[keep]) > 32 * 1024^2
  new = character()
  while (any(keep) && over()) {
    id = info$id[which(keep)[[1L]]]
    keep[info$id == id] = FALSE
    new = c(new, id)
  }
  if (length(new)) session_append(s, entry_custom("gptr.image_elision", list(images = I(new))))
  for (r in which(!keep)) {
    messages[[info$msg[r]]]$content[[info$block[r]]] = block_text(image_omitted_text(info$id[r]))
  }
  messages
}

#' The id of an image block: 8 hex of its data's sha256 (NA when the block has no data string)
#' @noRd
image_id = function(b) {
  data = b[["data"]]
  if (!is.character(data) || length(data) != 1L || is.na(data)) return(NA_character_)
  substr(hash_sha256(data), 1L, 8L)
}

#' The text an elided image is projected as (IC-67)
#' @noRd
image_omitted_text = function(id) {
  paste0("[image omitted: gptr$plot(\"", id, "\")]")
}

#' The image blocks of a message list: position, id (8 hex of the data's sha256) and bytes
#' @noRd
images_scan = function(messages) {
  rows = list()
  for (i in seq_along(messages)) {
    content = messages[[i]]$content %||% list()
    for (j in seq_along(content)) {
      b = content[[j]]
      if (!identical(b$type, "image")) next
      rows[[length(rows) + 1L]] = data.frame(msg = i, block = j,
                                             id = image_id(b),
                                             bytes = nchar(b$data, type = "bytes") * 3 / 4,
                                             stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(msg = integer(), block = integer(), id = character(), bytes = numeric(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Image ids already elided on the session's path
#' @noRd
elided_image_ids = function(d) {
  ids = character()
  for (e in entries_path(d)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.image_elision")) {
      ids = c(ids, as.character(unlist(e$data$images)))
    }
  }
  ids
}

# ---------------------------------------------------------------------------- answers and state

#' Structured final answers (`opts$returns`, INFRA-25): the final text parsed, validated and
#' designated as the run's value; a mismatch, or a schema that cannot be applied, is a notice
#' @noRd
run_returns = function(run) {
  schema = run$opts$returns
  if (is.null(schema)) return(invisible(NULL))
  s = run$shell
  txt = session_data(s)$last_text
  ok_txt = is.character(txt) && length(txt) == 1L && !is.na(txt)
  val = if (ok_txt) tryCatch(json_decode(txt), error = function(e) NULL) else NULL
  chk = if (is.null(val)) NULL else tryCatch(schema_validate(schema, val), error = function(e) e)
  if (is.null(chk) || inherits(chk, "error") || !isTRUE(chk$ok)) {
    why = if (is.null(chk)) {
      " (not JSON)"
    } else if (inherits(chk, "error")) {
      paste0(" (the schema cannot be applied: ", conditionMessage(chk), ")")
    } else {
      paste0(": ", paste(chk$errors, collapse = "; "))
    }
    gptr_inform(paste0("the final answer does not match `returns`", why), "notice")
    return(invisible(NULL))
  }
  session_value_set(s, "returns", chk$input)
  invisible(NULL)
}

#' Persist JSON-able per-plugin state (`ctx$state()`) as gptr.ext entries when it changed
#'
#' A state emptied after it was persisted is persisted as `{}`, so that a resume does not bring
#' the old state back.
#' @noRd
plugin_state_persist = function(s) {
  live = session_live(s)
  if (is.null(live)) return(invisible(NULL))
  d = session_data(s)
  for (plugin in ls(live$ext)) {
    st = get(plugin, envir = live$ext)
    if (!is.environment(st)) next
    vals = as.list(st, sorted = TRUE)
    if (!length(vals)) {
      if (!length(d$ext[[plugin]])) next
      vals = json_obj()
    }
    if (identical(d$ext[[plugin]], vals)) next
    ok = tryCatch({
      json_encode(vals)
      TRUE
    }, error = function(e) FALSE)
    if (!ok) next
    ext = d$ext
    ext[[plugin]] = vals
    d$ext = ext
    session_append(s, entry_custom("gptr.ext", list(plugin = plugin, state = vals)))
  }
  invisible(NULL)
}

#' Update the session's estimator multiplier from provider-reported usage (03 section 12.5)
#'
#' Only a reported prompt total updates it: gptr's own estimate (`estimated = TRUE`) and a usage
#' with an unknown prompt count (IC-74) leave it unchanged; a count the usage leaves out is P05's
#' legacy zero (overflow_count()).
#' @noRd
run_estimator_update = function(run, msg) {
  d = session_data(run$shell)
  u = msg[["usage"]]
  if (!is.list(u) || isTRUE(u[["estimated"]])) return(invisible(NULL))
  counts = vapply(c("input", "cache_read", "cache_write_5m", "cache_write_1h"),
                  function(f) overflow_count(u, f), 1)
  est = run$tokens_est %||% 0
  if (anyNA(counts) || !(sum(counts) > 0) || !isTRUE(est > 0)) return(invisible(NULL))
  prior = switch(run$model$provider %||% "", anthropic = 1.35, google = 1.10, 1.00)
  state = d$estimator %||% list(m = prior, n = 0L)
  d$estimator = est_multiplier(state, estimated = est, reported = sum(counts), prior = prior)
  invisible(NULL)
}

#' Context size projection (03 section 12.5): the last provider-reported total plus the
#' multiplier times the estimate of what follows it
#'
#' The anchor is the newest of the latest compaction and the latest assistant message whose total
#' the provider reported. After a compaction, the frozen prompt, its blocks, its kept tail and what
#' follows are estimated (the projection of P05's `entry_compaction_cut()`). An unknown total
#' (IC-74) or gptr's own estimate (`estimated = TRUE`) is no anchor; without one, the frozen
#' prompt and the whole path are estimated. Errored and aborted replies are not counted, as the
#' projection drops them, and images elided on the path count as their omission text (IC-67).
#' @noRd
context_tokens = function(s) {
  d = session_data(s)
  path = entries_path(d)
  m = d$estimator$m %||% 1
  elided = elided_image_ids(d)
  est = function(idx) sum(vapply(path[idx], entry_tokens_est, 1, elided = elided))
  after = function(i) seq_along(path)[-seq_len(i)]
  for (i in rev(seq_along(path))) {
    e = path[[i]]
    if (identical(e$type, "compaction")) {
      blocks = sum(vapply(e$gptr$blocks %||% list(), function(b) {
        est_tokens(b$text %||% "", "prose")
      }, 1))
      tail = c(compaction_kept(path, i), after(i))
      return(m * (frozen_tokens(d$frozen) + blocks + est(tail)))
    }
    total = reported_total(e)
    if (!is.na(total)) return(total + m * est(after(i)))
  }
  m * (frozen_tokens(d$frozen) + est(seq_along(path)))
}

#' Path positions of a compaction's kept tail (from its first kept entry up to the compaction)
#' @noRd
compaction_kept = function(path, i) {
  first = path[[i]]$first_kept_entry_id
  if (!is.character(first) || length(first) != 1L || i < 2L) return(integer())
  ids = vapply(path[seq_len(i - 1L)], function(e) as.character(e$id %||% NA_character_), "")
  from = match(first, ids)
  if (is.na(from)) integer() else from:(i - 1L)
}

#' The provider-reported total of an entry (an assistant reply that did not fail), else NA
#' @noRd
reported_total = function(e) {
  m = e$message
  if (!identical(e$type, "message") || !is.list(m) || !identical(m$role, "assistant") ||
      isTRUE((m$stop_reason %||% "stop") %in% c("error", "aborted"))) {
    return(NA_real_)
  }
  u = m$usage
  if (!is.list(u) || isTRUE(u[["estimated"]])) return(NA_real_)
  total = u[["total"]]
  if (!is.numeric(total) || length(total) != 1L || !is.finite(total) || total < 0) {
    return(NA_real_)
  }
  as.numeric(total)
}

#' Estimated tokens of an entry's message as the projection sends it (0 for other entries and for
#' errored or aborted replies; images in `elided` as their omission text)
#' @noRd
entry_tokens_est = function(e, elided = character()) {
  m = e$message
  if (!isTRUE(e$type %in% c("message", "custom_message")) || !is.list(m)) return(0)
  if (identical(m$role, "assistant") &&
      isTRUE((m$stop_reason %||% "stop") %in% c("error", "aborted"))) {
    return(0)
  }
  msg_tokens_est(m, elided)
}

#' Seconds since the last assistant message on the path (the cold rule of compact.should)
#' @noRd
context_idle = function(s) {
  d = session_data(s)
  for (e in rev(entries_path(d))) {
    if (identical(e$type, "message") && identical(e$message$role, "assistant")) {
      return(max(0, as.numeric(Sys.time()) - (e$message$timestamp %||% 0) / 1000))
    }
  }
  0
}

# ---------------------------------------------------------------------------- starting and waiting

#' Run a session to settlement
#'
#' Appends the input and runs `s` on the reactor under the interrupt policy (the
#' `console.interrupt_policy` service of P14 when registered, else abort-only). Raises nothing
#' itself: the gateway maps terminal statuses to conditions (04 section 6.1.2); an interrupt aborts
#' the run, keeps the partial turn and is re-signalled. A run marked `opts$background` by P21 stops
#' the foreground wait.
#' @param input A message (`msg_user()`), a list of messages, or `NULL` (the queued items, else a
#'   continuation from the leaf).
#' @param opts Run options (04 section 7.6).
#' @return `s`, invisibly.
#' @noRd
session_run = function(s, input, opts = list()) {
  run = run_start(s, input, opts)
  wait = function() run_wait_foreground(run)
  if (ext_service_has("console.interrupt_policy")) {
    ext_service_get("console.interrupt_policy")(wait, list(run), mode = "call")
  } else {
    run_abort_only(wait, run)
  }
  invisible(s)
}

#' Pump until the run settles or is sent to the background
#'
#' A pump nested in another reactor callback (a tool, a hook) runs only this run's FIFO tools, so
#' it never runs another run's tool (IC-57); the outermost pump runs every run's tools.
#' @noRd
run_wait_foreground = function(run) {
  allow = if (reactor_depth() == 0L) NULL else run$id
  reactor_pump(until = function() isTRUE(run$settled) || isTRUE(run$opts$background),
               slice_ms = 100L, allow_runs = allow)
}

#' The abort-only interrupt policy: abort the run, then re-signal the interrupt
#' @noRd
run_abort_only = function(expr_fun, run) {
  tryCatch(expr_fun(), interrupt = function(cnd) {
    run_abort(run, "interrupt")
    run_resignal_interrupt()
  })
}

#' Re-signal an interrupt after cleanup (report 02 section 5.8): enclosing handlers see it, and
#' without one the evaluation returns to the top level
#' @noRd
run_resignal_interrupt = function() {
  cnd = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  signalCondition(cnd)
  invokeRestart("abort")
}

#' Start a run without blocking
#'
#' Attaches a detached copy first (split-brain rules), refuses a running session
#' (`gptr_error_busy`), counts nested `gptr()` calls against `gptr.max_nested_calls` (IC-66),
#' freezes the prompt at the first run, appends the input and registers the run with the reactor.
#' @return A `gptr_run` held by the reactor until it settles.
#' @noRd
run_start = function(s, input, opts = list()) {
  check_class(s, "gptr_session", "s")
  check_list(opts, "opts")
  input = run_input(input)
  outer = run_current()
  live = session_attach(s)
  d = session_data(s)
  if (!is.null(live$run) || identical(d$status, "running")) {
    gptr_abort(paste0("session ", d$id, " is running; steer it with gptr_steer() or wait for it"),
               "busy", session = d$id)
  }
  if (!is.null(outer)) run_count_nested(outer, opts)
  run = run_new(s, opts, outer)
  replay_notice(s)
  input = run_initial_input(run, input)
  live$run = run
  d$status = "running"
  d$reason = NULL
  d$condition = NULL
  d$budget = run$budget
  if (is.null(d$parent_id)) last_set(s)
  reactor_run_add(run)
  # a failure before the run is wired (a freeze that refuses the model, a store error) settles
  # the run with status error and re-signals, so the session never stays `running`
  started = tryCatch({
    input = run_freeze(run, input)
    run_emit(run, "agent_start")
    run_emit(run, "turn_start")
    if (!is.null(input)) run_append_messages(run, input)
    run_wire(run)
    TRUE
  }, error = function(e) e)
  if (!isTRUE(started)) {
    run_fail(run, started)
    stop(started)
  }
  run
}

#' Normalise the input of a run: NULL, one message, or a list of messages
#' @noRd
run_input = function(input) {
  if (is.null(input)) return(NULL)
  if (is.list(input) && !is.null(input[["role"]])) return(list(input))
  if (is.list(input) && length(input) &&
      all(vapply(input, function(m) is.list(m) && !is.null(m[["role"]]), NA))) {
    return(input)
  }
  gptr_abort("`input` must be a message or a list of messages", "invalid_argument", arg = "input",
             expected = "a message from msg_user() or a list of messages")
}

#' Without input: the first queued item (steers first) opens the turn; with an empty queue the run
#' continues from the leaf when the path awaits a response, else there is nothing to run
#' @noRd
run_initial_input = function(run, input) {
  if (!is.null(input)) return(input)
  d = session_data(run$shell)
  for (which in c("steer", "follow_up")) {
    if (length(d$queue[[which]])) return(run_take(run, which))
  }
  msgs = Filter(function(m) {
    !(identical(m$role, "assistant") && (m$stop_reason %||% "stop") %in% c("error", "aborted"))
  }, path_messages(entries_path(d)))
  if (length(msgs)) {
    last = msgs[[length(msgs)]]
    open_calls = any(vapply(last$content %||% list(),
                            function(b) identical(b$type, "tool_call"), NA))
    if (!identical(last$role, "assistant") || open_calls) return(NULL)
  }
  gptr_abort("nothing to run: no input, an empty queue and a finished answer", "invalid_argument",
             arg = "input", expected = "a message or queued items")
}

#' Wire a run: the loop, its reactor task, the heartbeat and the callbacks that provider_stream()
#' injects into adapters (IC-33); the closures capture a frame that holds only `run` (rule R2)
#' @noRd
run_wire = function(run) {
  run$gate = function(call) perm_check(call, run)
  run$tool_result = function(result, call) tool_result_message(result, call)
  run$mcp_dispatch = function(message) ext_service_get("mcp.dispatch_local")(message, run$shell)
  run$loop = loop_new(max_turns = run$max_turns,
                      steering = function() run_take(run, "steer"),
                      follow_up = function() run_take(run, "follow_up"),
                      finish_turn = function(turn) run_finish_turn(run, turn),
                      emit = function(type, ...) run_emit(run, type, ...))
  run$task = reactor_task(function() run_drive(run), run = run)
  # touch the lock now, then every 10 minutes (IC-59): a session whose runs are all shorter than
  # 10 minutes still refreshes its lock at each run, so another process never takes an actively
  # used session's lock for stale after 24 h
  run_heartbeat(run)
  invisible(run)
}

#' Count gptr() calls made from one `r` evaluation (gptr.max_nested_calls, IC-66); the children of
#' one team or fan-out share `opts$nested_group` and count once
#' @noRd
run_count_nested = function(outer, opts) {
  tc = outer$tool_call
  if (is.null(tc)) return(invisible(NULL))
  counts = outer$nested_count
  keys = unique(c(counts[[tc$id]], opts$nested_group %||% id_new("g", 8L)))
  counts[[tc$id]] = keys
  outer$nested_count = counts
  cap = gptr_opt("max_nested_calls")
  if (length(keys) > cap) {
    gptr_abort(paste0("too many gptr() calls in one evaluation (limit ", cap,
                      ", option gptr.max_nested_calls)"),
               "budget", kind = "nested_calls", budget = cap, used = length(keys),
               session = outer$session)
  }
  invisible(length(keys))
}

#' Pump the reactor until every run settled or `timeout` seconds passed
#'
#' As run_wait_foreground(), a nested pump runs only the FIFO tools of the awaited runs (IC-57).
#' @return `invisible(TRUE)` when all settled.
#' @noRd
run_wait = function(runs, timeout = Inf) {
  if (inherits(runs, "gptr_run")) runs = list(runs)
  settled = function() all(vapply(runs, function(r) isTRUE(r$settled), NA))
  if (settled()) return(invisible(TRUE))
  allow = if (reactor_depth() == 0L) NULL else vapply(runs, function(r) r$id, "")
  ok = reactor_pump(until = settled, slice_ms = 100L, allow_runs = allow, timeout = timeout)
  invisible(isTRUE(ok) || settled())
}

#' Append messages and emit their events; the first user message of a run opens a prompt turn
#' @noRd
run_append_messages = function(run, msgs) {
  s = run$shell
  d = session_data(s)
  for (m in msgs) {
    if (identical(m$role, "user") && !isTRUE(run$counted_turn) && !isTRUE(run$requested)) {
      d$turns = d$turns + 1L
      run$counted_turn = TRUE
    }
    session_append(s, entry_message(m))
    run_emit(run, "message_start", role = m$role)
    run_emit(run, "message_end", role = m$role, message = m)
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------- driving the loop

#' The reactor task of a run: one loop action per call while not waiting
#' @return `TRUE` while the run is active.
#' @noRd
run_drive = function(run) {
  if (isTRUE(run$settled)) return(FALSE)
  if (isTRUE(run$busy)) return(TRUE)
  tryCatch(run_step(run), error = function(e) run_fail(run, e))
  !isTRUE(run$settled)
}

#' One step: abort when signalled, else the loop's next action
#' @noRd
run_step = function(run) {
  if (isTRUE(run$signal$aborted)) return(run_abort(run, run$signal$reason %||% "user"))
  act = loop_next(run$loop)
  switch(act$action,
    request = run_begin_request(run, act$messages),
    tools = run_tools(run, act),
    end = run_settle(run, act$reason),
    invisible(NULL))
}

#' Is the run aborted (signalled) or already settled, for example by a hook that called
#' `ctx$abort()` during the current step?
#' @noRd
run_halted = function(run) isTRUE(run$settled) || isTRUE(run$signal$aborted)

#' Take one queued item and turn it into a message (IC-55); steers become relays once the run has
#' made a request
#' @noRd
run_take = function(run, which) {
  d = session_data(run$shell)
  q = d$queue
  if (!length(q[[which]])) return(list())
  item = q[[which]][[1L]]
  q[[which]] = q[[which]][-1L]
  d$queue = q
  run_emit(run, "queue_update", steer = length(q$steer), follow_up = length(q$follow_up))
  list(queue_item_message(item, which, relay = isTRUE(run$requested)))
}

#' The loop's finish_turn hook: a blocked gate or an abort ends the run
#' @noRd
run_finish_turn = function(run, turn) {
  if (!is.null(run$blocked)) return(list(action = "end", reason = "blocked"))
  if (isTRUE(run$signal$aborted)) return(list(action = "end", reason = "aborted"))
  NULL
}

#' Start a turn's request: pending operator messages and queued messages first
#' @noRd
run_begin_request = function(run, messages) {
  ops = run$pending_operator
  run$pending_operator = list()
  run_append_messages(run, c(ops, messages))
  run$requested = TRUE
  run$boundary_compacted = FALSE
  run_request(run)
}

#' Make one model request (also used for retries)
#'
#' provider_stream() (P05) refuses a decision-only model, a disabled provider, a request
#' preflight that fails (IC-74: a local-only Ollama selection that cannot establish local
#' execution, missing or stale discovery evidence) and a missing key before anything starts; that
#' condition ends the run with status `error` (run_drive() and the retry timer hand it to
#' run_fail()). The preflight reads the run's frozen safety snapshot (`run$opts$safety`), because
#' the run is passed as `run`. A hook of the request's preparation (`model_select`,
#' `before_request`, `request_params`) can abort the run (`ctx$abort()`); the request then stops
#' at once, before it marks the run busy or starts a transfer that settlement no longer cancels.
#' @noRd
run_request = function(run) {
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  if (run_halted(run)) return(run_abort(run, run$signal$reason %||% "user"))
  if (identical(run$attempt, 0L) && !isTRUE(run$boundary_compacted)) run_compact_check(run)
  target = run_target(run)
  if (run_halted(run)) return(run_abort(run, run$signal$reason %||% "user"))
  req = run_build(run, target)
  hit = budget_check(s, req$tokens_est)
  if (!is.null(hit) && !run_budget_extend(run, hit)) return(run_stop_budget(run, hit))
  if (ext_service_has("prefix.guard")) {
    # gptr.check_prefix = "error" (04 section 3.1) stops the run: P07's guard signals
    # gptr_error_internal and the run settles with status error; other failures are diagnostics
    tryCatch(ext_service_get("prefix.guard")(s, target, req$view), error = function(e) {
      if (inherits(e, "gptr_error_internal") && identical(gptr_opt("check_prefix"), "error")) {
        stop(e)
      }
      registry_diagnostic("session", "prefix.guard", "service_error", conditionMessage(e))
    })
  }
  run$request_id = req$context$request_id
  run$request_ids = c(run$request_ids, run$request_id)
  run$tokens_est = req$tokens_est
  ledger_add(s, run$request_id, req$components)
  run_emit(run, "before_request", provider = target$provider, model = target$ref,
           request_id = run$request_id, view = req$view, tokens_est = req$tokens_est)
  if (run_halted(run)) return(run_abort(run, run$signal$reason %||% "user"))
  req$context$params = run_request_params(run, target, req$context$params)
  if (run_halted(run)) return(run_abort(run, run$signal$reason %||% "user"))
  run$acc = acc_new()
  run$rs = new.env(parent = emptyenv())
  run$last_error = NULL
  run$request_started = Sys.time()
  run$request_closed = FALSE
  run$busy = TRUE
  run$status = "requesting"
  run$turn = run$loop$turn
  # IC-33: the run's gate, tool-result builder and MCP dispatcher are injected through `opts`
  # (P05's provider_stream() reads opts$gate, opts$tool_result and opts$mcp_dispatch and falls
  # back to a closed gate without them)
  opts = list(signal = run$signal, state = live$adapter, memo = live$memo, run = run$id,
              session = d$id, gate = run$gate, tool_result = run$tool_result)
  if (ext_service_has("mcp.dispatch_local")) opts$mcp_dispatch = run$mcp_dispatch
  cb = run_stream_callbacks(run)
  tid = provider_stream(target, req$context, opts, emit = cb$emit, done = cb$done, run = run)
  tid = as.character(tid)
  if (length(tid) == 1L && !is.na(tid)) run$transfers = c(run$transfers, tid)
  invisible(NULL)
}

#' The emit/done callbacks of a request; their frame holds only the run (rule R2)
#' @noRd
run_stream_callbacks = function(run) {
  list(emit = function(ev) run_on_event(run, ev), done = function(msg) run_on_done(run, msg))
}

# ---------------------------------------------------------------------------- stream callbacks

#' INFRA-02 events: delta-only agent events, redacted per content block with a streaming hold-back
#' @noRd
run_on_event = function(run, ev) {
  if (isTRUE(run$settled) || isTRUE(run$request_closed)) return(invisible(NULL))
  run$acc$push(ev)
  type = ev$type
  if (identical(type, "start")) {
    run$status = "streaming"
    run_emit(run, "message_start", role = "assistant")
  } else if (type %in% c("text_delta", "thinking_delta", "toolcall_delta")) {
    kind = sub("_delta$", "", type)
    key = as.character(ev$index)
    x = get0(key, envir = run$rs, inherits = FALSE)
    if (is.null(x)) {
      x = list(rs = redact_stream("stream"), kind = kind)
      assign(key, x, envir = run$rs)
    }
    safe = x$rs$push(ev$delta)
    if (nzchar(safe)) run_emit(run, "message_update", index = ev$index, kind = kind, delta = safe)
  } else if (identical(type, "error")) {
    run$last_error = ev$error
  } else if (type %in% c("retry_start", "retry_end")) {
    args = ev[setdiff(names(ev), c("type", "ts", "session", "run", "agent", "turn"))]
    do.call(run_emit, c(list(run, type), args))
  }
  invisible(NULL)
}

#' Emit what the streaming redactors still hold
#'
#' A redactor that failed closed at its holding limit (D-010) keeps failing: its held text is
#' dropped with a diagnostic, never emitted, and the response is still recorded.
#' @noRd
run_flush_deltas = function(run) {
  for (key in ls(run$rs)) {
    x = get(key, envir = run$rs)
    rest = tryCatch(x$rs$flush(), error = function(e) {
      registry_diagnostic("session", "message_update", class(e)[[1L]], conditionMessage(e))
      ""
    })
    if (nzchar(rest)) {
      run_emit(run, "message_update", index = as.integer(key), kind = x$kind, delta = rest)
    }
  }
  invisible(NULL)
}

#' The final assistant message of a request (called once by provider_stream())
#' @noRd
run_on_done = function(run, msg) {
  if (isTRUE(run$settled) || isTRUE(run$request_closed)) return(invisible(NULL))
  run$request_closed = TRUE
  tryCatch(run_response(run, msg), error = function(e) run_fail(run, e))
  invisible(NULL)
}

#' Account, append and hand the response to the loop (or to recovery when it failed)
#'
#' Usage (IC-74, 07-local-ollama.md section 5 "Missing usage remains unknown"): a usage the
#' provider reported is recorded as reported, its unknown counts staying unknown (`NA`); only when
#' the provider reported no token count at all is the row filled by the estimator and marked
#' `estimated = TRUE` (04 section 4.3).
#' @noRd
run_response = function(run, msg) {
  s = run$shell
  d = session_data(s)
  run_flush_deltas(run)
  if (!run_usage_reported(msg[["usage"]])) {
    msg$usage = usage_new(input = run$tokens_est %||% 0,
                          output = est_tokens(msg_text(msg), "prose"), estimated = TRUE)
  }
  row = usage_row(msg, session = d$id, agent = run$opts$agent %||% "main",
                  parent_id = d$parent_id %||% NA_character_, started = run$request_started,
                  seconds = as.numeric(difftime(Sys.time(), run$request_started, units = "secs")),
                  multiplier = d$estimator$m %||% 1)
  row = usage_conform(row)
  row$request_id = run$request_id
  usage_add(s, row)
  ledger_mark_cached(s, run$request_id, usage_as(msg[["usage"]])[["cache_read"]])
  run_emit(run, "usage", row = row)
  run_estimator_update(run, msg)
  session_append(s, entry_message(msg))
  run_emit(run, "message_end", role = "assistant", message = msg)
  run$message = msg
  if (identical(msg$stop_reason, "error")) return(run_response_error(run, msg))
  if (run$attempt > 0L) {
    run_emit(run, "retry_end", attempt = run$attempt, ok = TRUE)
    run$attempt = 0L
  }
  if (identical(msg$stop_reason, "stop") && is_context_overflow(msg, run$model$context)) {
    run$pending_compact = "overflow"
  }
  budget_near(run)
  run$busy = FALSE
  loop_response(run$loop, msg)
  invisible(NULL)
}

#' Did the provider report usage? TRUE when P05 accepts the record (usage_as()) and it holds at
#' least one known positive token count (IC-74)
#'
#' A missing record, an all-unknown one (P05's `usage_as(NULL)`, which P12's normalisers give for
#' a stream that reported nothing), only legacy zeros, or a record P05 refuses report nothing;
#' a partial report is a report, and its unknown counts stay unknown.
#' @noRd
run_usage_reported = function(usage) {
  if (!is.list(usage)) return(FALSE)
  u = tryCatch(usage_as(usage), error = function(e) NULL)
  if (is.null(u)) return(FALSE)
  counts = vapply(c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h"),
                  function(f) as.numeric(u[[f]]), 1)
  any(!is.na(counts) & counts > 0)
}

#' Recovery of a failed request: one compact-and-retry on overflow, at most two agent-level
#' retries of transient errors, else the error ends the run (report 02 sections 2.8-2.9, C-33)
#' @noRd
run_response_error = function(run, msg) {
  err = run$last_error %||% list()
  if (is_context_overflow(msg, run$model$context, err)) {
    if (!isTRUE(run$overflow_used) && ext_service_has("compact.run")) {
      run$overflow_used = TRUE
      ok = tryCatch({
        ext_service_get("compact.run")(run$shell, "overflow")
        TRUE
      }, error = function(e) {
        registry_diagnostic("session", "compaction", "compaction_failed", conditionMessage(e))
        FALSE
      })
      if (ok) {
        run$boundary_compacted = TRUE
        return(run_schedule_request(run, 0))
      }
    }
    run$condition = run_condition(
      run, msg, c("context_overflow", "provider"),
      message = paste0("the context is still too large",
                       if (isTRUE(run$overflow_used)) " after one compaction and retry" else "",
                       ": ", msg$error_message %||% "context overflow"),
      tokens = run_overflow_tokens(msg))
    return(run_response_final(run, msg))
  }
  if (run_retryable(msg, err) && run$attempt < 2L) {
    run$attempt = run$attempt + 1L
    delay = agent_retry_delay(run$attempt)
    run_emit(run, "retry_start", attempt = run$attempt, delay = delay, class = err_class(err))
    return(run_schedule_request(run, delay))
  }
  if (run$attempt > 0L) run_emit(run, "retry_end", attempt = run$attempt, ok = FALSE)
  run$condition = run_condition(run, msg, provider_classes(err))
  run_response_final(run, msg)
}

#' The prompt tokens the provider reported for an overflowing request, else NA: gptr's own
#' estimate (`estimated = TRUE`) is not the provider's count (IC-74)
#' @noRd
run_overflow_tokens = function(msg) {
  u = msg[["usage"]]
  if (!is.list(u) || isTRUE(u[["estimated"]])) return(NA_real_)
  overflow_count(u, "input")
}

#' Hand a failed response to the loop, which ends the run
#' @noRd
run_response_final = function(run, msg) {
  run$busy = FALSE
  loop_response(run$loop, msg)
  invisible(NULL)
}

#' Re-send the current request after `delay` seconds (an interruptible reactor timer)
#' @noRd
run_schedule_request = function(run, delay) {
  run$busy = TRUE
  id = reactor_timer(at = reactor_now() + delay, fn = function() {
    tryCatch(run_request(run), error = function(e) run_fail(run, e))
  }, run = run)
  run$timers = c(run$timers, id)
  invisible(NULL)
}

#' The unsignalled condition object stored for a terminal status (04 section 2.2)
#' @noRd
run_condition = function(run, msg, cls, message = NULL, ...) {
  err = run$last_error %||% list()
  d = session_data(run$shell)
  rid = err[["request_id"]]
  if (!is.character(rid) || length(rid) != 1L || is.na(rid)) rid = run$request_id %||% NA_character_
  gptr_condition(message %||% msg$error_message %||% "the model request failed", cls, "error",
                 list(provider = run$model$provider %||% NA_character_,
                      model = run$model$ref %||% d$model, status = err_status(err),
                      request_id = rid, error_type = err_class(err), session = d$id, ...))
}

# ---------------------------------------------------------------------------- compaction, budgets

#' Threshold compaction at a request boundary (compact.should), or the pending compaction after a
#' silent overflow; none before P07 registers the services. A router session is asked for the
#' compaction model first (IC-69)
#' @noRd
run_compact_check = function(run) {
  s = run$shell
  reason = run$pending_compact
  run$pending_compact = NULL
  if (is.null(reason) && ext_service_has("compact.should")) {
    should_fun = ext_service_get("compact.should")
    should = tryCatch(isTRUE(should_fun(s, context_tokens(s), context_idle(s))),
                      error = function(e) FALSE)
    if (should) reason = "threshold"
  }
  if (is.null(reason) || !ext_service_has("compact.run")) return(invisible(FALSE))
  if (startsWith(session_data(s)$model, "router:")) run_route(run, "compaction")
  ok = tryCatch({
    ext_service_get("compact.run")(s, reason)
    TRUE
  }, error = function(e) {
    registry_diagnostic("session", "compaction", "compaction_failed", conditionMessage(e))
    FALSE
  })
  if (ok) run$boundary_compacted = TRUE
  invisible(ok)
}

#' Ask to extend a reached budget by the same amount (ask_human: the run's UI only)
#' @noRd
run_budget_extend = function(run, hit) {
  if (!isTRUE(run$opts$safety$can_prompt)) return(FALSE)
  ui = run_ui(run)
  if (is.null(ui) || !isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) return(FALSE)
  title = paste0("The ", hit$kind, " budget of this call (", format(hit$budget), ") is reached.")
  ans = tryCatch(ui$select(title, c("Extend it by the same amount", "Stop the run"), default = 2L),
                 error = function(e) NA_integer_)
  if (!identical(suppressWarnings(as.integer(ans)), 1L)) return(FALSE)
  for (r in run_chain(run)) {
    if (identical(r$budget[[hit$kind]], hit$budget)) {
      b = r$budget
      b[[hit$kind]] = 2 * hit$budget
      r$budget = b
      return(TRUE)
    }
  }
  FALSE
}

#' Stop a run at a request boundary because a budget is reached (status budget)
#' @noRd
run_stop_budget = function(run, hit) {
  s = run$shell
  d = session_data(s)
  session_append(s, entry_custom("gptr.budget", list(kind = hit$kind, budget = hit$budget,
                                                     used = hit$used)))
  run_emit(run, "budget_exceeded", kind = hit$kind, budget = hit$budget, used = hit$used)
  run$condition = gptr_condition(
    paste0("the ", hit$kind, " budget of this call (", format(hit$budget), ") is reached (used ",
           format(hit$used), ")"),
    c(paste0("budget_", hit$kind), "budget"), "error",
    list(kind = hit$kind, budget = hit$budget, used = hit$used, session = d$id))
  run_settle(run, "budget")
}

# ---------------------------------------------------------------------------- tools

#' Hand a turn's tool calls to the dispatcher: through the reactor's tool FIFO when any call is
#' sequential (R-evaluating or file-writing tools), directly when every call is concurrent or the
#' batch is truncated (nothing executes). The loop (and so `turn_end`) receives the tool-result
#' messages, never the results' R values (rule R1). The FIFO item id is kept in `run$fifo` so that
#' settlement cancels a job that has not started (it would otherwise hold the run, and the
#' session, until the next pump).
#' @noRd
run_tools = function(run, act) {
  calls = lapply(act$calls, function(b) call_record(run, b))
  run$status = "tools"
  run$busy = TRUE
  job = function() {
    tryCatch({
      out = dispatch_tools(run, calls)
      if (!isTRUE(run$settled)) {
        run$busy = FALSE
        run$status = "boundary"
        loop_results(run$loop, out$messages, out$terminate)
      }
    }, error = function(e) run_fail(run, e))
    invisible(NULL)
  }
  sequential = any(vapply(calls, function(cl) {
    is.null(cl$tool) || !identical(cl$tool$execution, "concurrent")
  }, NA))
  if (sequential && !isTRUE(act$truncated)) {
    run$fifo = c(run$fifo, reactor_enqueue_tool(run, job))
  } else {
    job()
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------- settle and abort

#' Settle a run with a loop end reason: status, stored condition, released frame bindings (rule R2),
#' `agent_end`
#' @noRd
run_settle = function(run, reason) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  run$settled = TRUE
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  status = switch(reason, aborted = "aborted", error = "error", max_turns = "max_turns",
                  blocked = "blocked", budget = "budget", "idle")
  if (identical(status, "max_turns") && is.null(run$condition)) {
    run$condition = gptr_condition(
      paste0("the run stopped after ", run$max_turns, " turns (max_turns)"), "max_turns", "error",
      list(max_turns = run$max_turns, session = d$id))
  }
  if (identical(status, "error") && is.null(run$condition)) {
    run$condition = run_condition(run, run$message %||% list(), "provider")
  }
  run_settle_model(run)
  status = run_settle_persist(run, status)
  d$status = status
  d$reason = if (is.null(run$condition)) NULL else conditionMessage(run$condition)
  d$condition = run$condition
  # 04 section 2.2: the condition object travels in the run; P08's gateway_signal() reads it here
  run$signal$condition = run$condition
  run$status = status
  run$home = NULL
  run$scratch = NULL
  run$outer = NULL
  run$opts["call"] = list(NULL)
  ids = as.character(c(run$task, run$timers, run$transfers, run$fifo))
  ids = ids[!is.na(ids) & nzchar(ids)]
  if (length(ids)) tryCatch(reactor_cancel(ids), error = function(e) NULL)
  if (!is.null(live) && identical(live$run, run)) live$run = NULL
  reactor_run_remove(run)
  u = d$usage
  run_emit(run, "agent_end", status = status, reason = d$reason,
           usage = u[u$request_id %in% run$request_ids, , drop = FALSE], doc = run$opts$doc,
           turns = d$turns)
  if (is.null(d$parent_id)) last_set(s)
  invisible(NULL)
}

#' Apply a `ctx$set_model()` switch that no later request of the run took
#'
#' A switch requested inside a run waits for the next request boundary (IC-69, 04 section 10.6);
#' when the run ends first (a call during its last reply, a `turn_end` hook, `max_turns`), the
#' run's end is that boundary, so the switch is not lost. Whatever stopped the run, the switch is
#' the plugin's choice for the session and applies. A failure (the provider went away since the
#' call) is a registry diagnostic and never interrupts the settlement.
#' @noRd
run_settle_model = function(run) {
  pm = run$pending_model
  if (is.null(pm)) return(invisible(NULL))
  run$pending_model = NULL
  tryCatch(kernel_model_switch(run$shell, pm$ref, pm$thinking, pm$reason %||% "plugin"),
           error = function(e) {
             registry_diagnostic("session", "set_model", class(e)[[1L]],
                                 paste0("the model switch to ", pm$ref, " was not applied: ",
                                        conditionMessage(e)))
           })
  invisible(NULL)
}

#' Persist a settling run's outcome: the last text, the `returns` value and the plugin state
#'
#' These steps write to the store, which can fail (a full disk, a read-only file). The failure
#' never interrupts the settlement, which would leave the session `running` and the run held by
#' the reactor. A run without a terminal condition of its own (an `idle` run) settles with status
#' `error` and the store's condition; a run that already ends `aborted` or with a condition keeps
#' it, and the store failure is a registry diagnostic.
#' @return The status to settle with.
#' @noRd
run_settle_persist = function(run, status) {
  s = run$shell
  d = session_data(s)
  err = tryCatch({
    txt = final_text(entries_path(d))
    if (!is.null(txt) && !status %in% c("error", "aborted")) d$last_text = txt
    if (identical(status, "idle")) run_returns(run)
    plugin_state_persist(s)
    NULL
  }, error = function(e) e)
  if (is.null(err)) return(status)
  if (identical(status, "aborted") || !is.null(run$condition)) {
    registry_diagnostic("session", "settle", class(err)[[1L]], conditionMessage(err))
    return(status)
  }
  run$condition = run_error_condition(err)
  "error"
}

#' The stored condition of an unexpected R error: a gptr_error as it is, else
#' `gptr_error_internal`
#' @noRd
run_error_condition = function(e) {
  if (inherits(e, "gptr_error")) return(e)
  gptr_condition(paste0("internal error in the run: ", conditionMessage(e)), "internal", "error",
                 list(detail = conditionMessage(e)))
}

#' Settle a run after an unexpected R error (kept as the stored condition)
#' @noRd
run_fail = function(run, e) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  run$condition = run_error_condition(e)
  run_settle(run, "error")
}

#' Abort a run: cancel its transfers and child runs, record the partial answer with
#' `stop_reason = "aborted"`, move the queue to `dropped`, settle with status `aborted`
#' @noRd
run_abort = function(run, reason = "user") {
  if (isTRUE(run$settled)) return(invisible(run))
  s = run$shell
  d = session_data(s)
  run$signal$aborted = TRUE
  run$signal$reason = reason
  if (length(run$transfers)) tryCatch(reactor_cancel(run$transfers), error = function(e) NULL)
  for (cid in run$children) {
    cs = session_by_id(cid)
    cl = if (is.null(cs)) NULL else session_live(cs)
    if (!is.null(cl$run)) run_abort(cl$run, reason)
  }
  streaming = run$status %in% c("requesting", "streaming")
  if (isTRUE(run$busy) && streaming && !isTRUE(run$request_closed)) {
    run$request_closed = TRUE
    msg = run_partial_message(run)
    msg$stop_reason = "aborted"
    msg$error_message = paste0("aborted (", reason, ")")
    # a store failure here must not stop the abort (the session would stay `running`, and under
    # the abort-only policy the store error would replace the re-signalled interrupt)
    tryCatch(session_append(s, entry_message(msg)), error = function(e) {
      registry_diagnostic("session", "abort", class(e)[[1L]], conditionMessage(e))
    })
    run_emit(run, "message_end", role = "assistant", message = msg)
  }
  d$dropped = c(d$dropped, d$queue$steer, d$queue$follow_up)
  d$queue = list(steer = list(), follow_up = list())
  run_settle(run, "aborted")
  invisible(run)
}

#' The partial answer of an aborted request
#'
#' The accumulator's message once the stream's `start` event named the model; before it, P01's
#' accumulator answers "unknown" for the api, provider and model, so an empty message of the run's
#' model is built instead (as P05's stream_partial() does).
#' @noRd
run_partial_message = function(run) {
  msg = if (identical(run$status, "streaming")) {
    tryCatch(run$acc$message(), error = function(e) NULL)
  } else {
    NULL
  }
  if (is.list(msg)) return(msg)
  m = run$model
  msg_assistant(list(), api = m[["api"]] %||% "unknown", provider = m[["provider"]] %||% "unknown",
                model = m[["id"]] %||% "unknown", stop_reason = "aborted", route = stream_route(m),
                request_id = run$request_id)
}

#' Touch the session's lock every 10 minutes while the run is live (IC-59)
#' @noRd
run_heartbeat = function(run) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  live = session_live(run$shell)
  if (!is.null(live$store)) tryCatch(store_heartbeat(live$store), error = function(e) NULL)
  run$timers = c(run$timers, reactor_timer(at = reactor_now() + 600,
                                           fn = function() run_heartbeat(run), run = run))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- ctx.kernel (IC-34)

on_load(ext_service_set("ctx.kernel", ctx_kernel, provided_by = "P06"))

#' The `ctx.kernel` service: the implementations of the `ctx` members marked P06 in contract
#' section 10.6
#'
#' P02's `ctx_new()` is a thin shell whose members fetch this list at call time and call the
#' member with the `ctx` first, then the member's own arguments, positionally (P02's
#' `ctx_call()`); inside a handler P02 appends the handler's source (`"plugin:units"`) as the last
#' argument of `send`, `append_entry` and `state`, which P06 receives as `extension` (`NULL`
#' outside handlers; `ctx_ext_label()` accepts the bare name or a full source and gives
#' `"units"`). The run a member acts on is `ctx_run()`: the run of the ctx's session whose tool is
#' executing on the call stack, else the session's current run (`session_live(s)$run`).
#'
#' `send`, `set_model` and `append_entry` need the ctx of a session; a process-level ctx (P02's
#' `ctx_new(NULL)`) gets `gptr_error_invalid_argument` (`arg = "ctx"`), and its other members read
#' the process: no environment or state, the run id the ctx was created for (if any), the `mode`
#' setting, the default chat model and the process usage. `set_model` refuses an unknown or
#' decision-only model at once, also inside a run, and records the thinking level in the
#' `model_change` entry; inside a run the switch applies at the run's next request, or when the
#' run settles first (run_settle_model()). `append_entry` refuses data the store cannot encode and
#' the reserved `gptr.` entry types (04 section 4.6), before anything is appended. `abort` inside
#' the dispatcher (a tool, or a hook of a call) only raises the run's abort signal, so the call
#' ends (a call whose `tool_call` or `permission_request` hook aborted is not executed), the
#' remaining calls are skipped and the next step settles the run with the reason; elsewhere it
#' aborts at once, and a request being prepared stops before its transfer starts.
#' @return A named list of functions: `envir`, `run`, `mode`, `model`, `execute_tool`, `send`,
#'   `set_model`, `append_entry`, `abort`, `aborted`, `update`, `usage`, `state`.
#' @noRd
ctx_kernel = function() {
  list(
    envir = function(ctx) {
      run = ctx_run(ctx)
      env = if (is.null(run)) NULL else run_eval_env(run)
      if (!is.null(env)) return(env)
      s = ctx_session(ctx)
      if (is.null(s)) NULL else session_home(s)
    },
    run = function(ctx) {
      run = ctx_run(ctx)
      if (is.null(run)) ctx_own_run_id(ctx) else run$id
    },
    mode = function(ctx) {
      run = ctx_run(ctx)
      if (!is.null(run)) return(run$mode)
      s = ctx_session(ctx)
      if (is.null(s)) setting_get("mode", default = "manual") else session_data(s)$mode
    },
    model = function(ctx) {
      s = ctx_session(ctx)
      if (is.null(s)) model_default("chat") %||% NA_character_ else session_data(s)$model
    },
    execute_tool = function(ctx, name, input) dispatch_nested(name, input, ctx),
    send = function(ctx, text, as = c("steer", "follow_up"), extension = NULL) {
      s = ctx_session(ctx, "send")
      check_strings(text, "text")
      as = check_choice(as, c("steer", "follow_up"), "as")
      d = session_data(s)
      # the item's position, taken before a queue_update hook can enqueue after it
      at = length(d$queue[[as]]) + 1L
      session_enqueue(s, paste(text, collapse = "\n"), as = as, source = "extension")
      q = d$queue
      if (length(q[[as]]) >= at) {
        q[[as]][[at]]$name = ctx_ext_label(extension)
        d$queue = q
      }
      invisible(NULL)
    },
    set_model = function(ctx, ref, thinking = NULL, reason = "plugin") {
      s = ctx_session(ctx, "set_model")
      check_string(ref, "ref")
      if (!is.null(thinking)) thinking = check_choice(thinking, catalog_thinking_levels, "thinking")
      check_string(reason, "reason")
      run = ctx_run(ctx)
      if (is.null(run) || isTRUE(run$settled)) {
        kernel_model_switch(s, ref, thinking, reason)
      } else {
        kernel_model_ref(ref, thinking)
        run$pending_model = list(ref = ref, thinking = thinking, reason = reason)
      }
      invisible(NULL)
    },
    append_entry = function(ctx, type, data, extension = NULL) {
      s = ctx_session(ctx, "append_entry")
      check_string(type, "type")
      custom_type = paste0(ctx_ext_label(extension), ".", type)
      if (startsWith(custom_type, "gptr.")) {
        gptr_abort(paste0("custom entries named gptr.* are written only by gptr itself; ",
                          custom_type, " cannot be appended by an extension"),
                   "invalid_argument", arg = "type",
                   expected = "an entry type outside the reserved gptr.* entries")
      }
      encodable = tryCatch({
        json_encode(data)
        TRUE
      }, error = function(e) FALSE)
      if (!encodable) arg_abort(data, "data", "JSON-able data (lists, atomic vectors and NULL)")
      session_append(s, entry_custom(custom_type, data))
    },
    abort = function(ctx, reason = "plugin") {
      check_string(reason, "reason")
      run = ctx_run(ctx)
      if (is.null(run) || isTRUE(run$settled)) return(invisible(NULL))
      if (!is.null(run$tool_call) || identical(run$status, "tools")) {
        if (!isTRUE(run$signal$aborted)) {
          run$signal$aborted = TRUE
          run$signal$reason = reason
        }
      } else {
        run_abort(run, reason)
      }
      invisible(NULL)
    },
    aborted = function(ctx) {
      run = ctx_run(ctx)
      !is.null(run) && isTRUE(run$signal$aborted)
    },
    update = function(ctx, text) {
      check_string(text, "text")
      run = ctx_run(ctx)
      if (!is.null(run) && !is.null(run$tool_call)) {
        run_emit(run, "tool_execution_update", tool_call_id = run$tool_call$id,
                 tool_name = run$tool_call$name, text = text)
      }
      invisible(NULL)
    },
    usage = function(ctx) gptr_usage(ctx_session(ctx)),
    state = function(ctx, extension = NULL) {
      s = ctx_session(ctx)
      live = if (is.null(s)) NULL else session_live(s)
      if (is.null(live)) return(NULL)
      plugin = ctx_ext_label(extension)
      e = get0(plugin, envir = live$ext, inherits = FALSE)
      if (is.null(e)) {
        e = new.env(parent = emptyenv())
        prior = session_data(s)$ext[[plugin]]
        if (ctx_state_restorable(prior)) list2env(prior, envir = e)
        assign(plugin, e, envir = live$ext)
      }
      e
    })
}

#' The session of a ctx, or NULL for a process-level ctx
#'
#' With `member` (the name of a session verb), a process-level ctx is refused with
#' `gptr_error_invalid_argument` (`arg = "ctx"`).
#' @noRd
ctx_session = function(ctx, member = NULL) {
  s = ctx$session
  if (inherits(s, "gptr_session")) return(s)
  if (is.null(member)) return(NULL)
  gptr_abort(paste0("ctx$", member, "() needs the ctx of a session; this ctx belongs to a ",
                    "dispatch without a session"),
             "invalid_argument", arg = "ctx", expected = "the ctx of a session")
}

#' The run a ctx member acts on, or NULL
#'
#' The run of the ctx's session whose tool is executing on this call stack (`run_current()`), even
#' when it settled while the tool runs (an abort from elsewhere), so that a long tool polling
#' `ctx$aborted()` sees the abort; otherwise the session's current run.
#' @noRd
ctx_run = function(ctx) {
  s = ctx_session(ctx)
  if (is.null(s)) return(NULL)
  cur = run_current()
  if (!is.null(cur) && identical(cur$shell, s)) return(cur)
  live = session_live(s)
  if (is.null(live)) NULL else live$run
}

#' The run id a ctx was created for (P02's `ctx_new(session, run)`: "the run (or run id) whose
#' tool is executing"), or NULL; `ctx$run` falls back to it when the kernel finds no run
#' @noRd
ctx_own_run_id = function(ctx) {
  id = if (is.environment(ctx)) get0(".run", envir = ctx, inherits = FALSE) else NULL
  if (is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)) id else NULL
}

#' The plugin label of a handler's extension source: `"plugin:units"` -> `"units"`,
#' `"builtin:tools"` -> `"tools"`; `"plugin"` when no source (or an empty name) is known (P02
#' passes nothing outside handlers)
#' @noRd
ctx_ext_label = function(extension) {
  if (!is.character(extension) || !length(extension) || is.na(extension[[1L]])) return("plugin")
  label = sub("^[A-Za-z_]+:", "", extension[[1L]])
  if (nzchar(label)) label else "plugin"
}

#' Can a stored plugin state (`gptr.ext`) seed a state environment? A list whose elements all
#' have names (an empty list included)
#' @noRd
ctx_state_restorable = function(prior) {
  if (!is.list(prior)) return(FALSE)
  if (!length(prior)) return(TRUE)
  nms = names(prior)
  !is.null(nms) && !anyNA(nms) && all(nzchar(nms))
}

#' The reference that switches a session to `ref` at thinking level `thinking`
#'
#' Resolution is pure (no discovery, no I/O; IC-74) and refuses at once what session_set_model()
#' refuses: an unknown reference (`gptr_error_unknown_model`) and a decision-only model
#' (`gptr_error_not_available`, D-017). A thinking level travels as the reference's `:<level>`
#' suffix, which P05's resolver clamps to the model's levels, so the `model_change` entry records
#' it; a router chooses each request's level itself, so its reference is kept as given.
#' @noRd
kernel_model_ref = function(ref, thinking = NULL) {
  m = model_canonical(ref, strict = TRUE)
  stream_chat_model(m)
  if (is.null(thinking) || startsWith(m$ref, "router:")) return(ref)
  paste0(m$ref, ":", thinking)
}

#' Switch a session's model (and thinking level) now: one `model_change` entry and `model_select`
#' @noRd
kernel_model_switch = function(s, ref, thinking = NULL, reason = "plugin") {
  target = kernel_model_ref(ref, thinking)
  session_set_model(s, target, reason)
  if (!is.null(thinking) && startsWith(target, "router:")) {
    d = session_data(s)
    d$thinking = thinking
  }
  invisible(s)
}
