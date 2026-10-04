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
    session_set_model(s, pm$ref, pm$reason %||% "plugin")
    if (is.character(pm$thinking) && length(pm$thinking) == 1L && !is.na(pm$thinking)) {
      d$thinking = pm$thinking
    }
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
