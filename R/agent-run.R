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
