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
