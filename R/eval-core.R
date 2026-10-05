# The evaluator eval_r() and the agent RNG swap rng_swap() (P09; 04 section 7.9; IC-61, IC-67).
# Copy safety (architecture 6.4, test-copy-eval.R): eval_r() binds `envir` (st$envir, reset on
# exit); the frames around user code hold only `st` and force their arguments; withVisible()
# results are cleared in place (R2, R3, R8). R limit: a passed object copies once after an error.

#' L'Ecuyer-CMRG seed vector from a key, drawing no random number (IC-61)
#' Three words of sha256(key) modulo m1 and three modulo m2 after the kind code 10407L; the word
#' 2^31 is stored as NA_integer_ (its bit pattern), which R reads back as 2^31 (D-052).
#' @noRd
rng_seeds = function(key) {
  h = hash_sha256(as.character(key)[[1L]])
  hex = substring(h, seq(1L, 41L, by = 8L), seq(8L, 48L, by = 8L))
  v = as.numeric(paste0("0x", hex))
  v = v %% c(rep(4294967087, 3L), rep(4294944443, 3L))
  if (all(v[1:3] == 0)) v[1L] = 1
  if (all(v[4:6] == 0)) v[4L] = 1
  v = ifelse(v > 2147483647, v - 4294967296, v)
  v[v == -2147483648] = NA
  c(10407L, as.integer(v))
}

#' Evaluate `expr` with the agent's L'Ecuyer stream in .Random.seed, then restore the user's (IC-61)
#' `state` holds `seed` (NULL: rng_seeds(id)) and `id`. R keeps the generator kind internally, so
#' the user's kind is restored too: rbinom(1, 0, 0.5) makes R read it without a draw (D-052).
#' @noRd
rng_swap = function(state, expr) {
  check_env(state, "state")
  seed = state$seed %||% rng_seeds(state$id %||% "gptr")
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  kind = NULL
  if (is.null(saved)) {
    invisible(stats::rbinom(1L, 0L, 0.5))
    now = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(now)) rm(list = ".Random.seed", envir = env)
    kind = if (is.integer(now) && length(now)) now[1L] else 10403L
  }
  env[[".Random.seed"]] = seed
  on.exit({
    state$seed = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(saved)) {
      env[[".Random.seed"]] = saved
      try(suppressWarnings(stats::rbinom(1L, 0L, 0.5)), silent = TRUE)
      env[[".Random.seed"]] = saved
    } else {
      env[[".Random.seed"]] = kind
      invisible(stats::rbinom(1L, 0L, 0.5))
      if (exists(".Random.seed", envir = env, inherits = FALSE)) {
        rm(list = ".Random.seed", envir = env)
      }
    }
  }, add = TRUE)
  expr
}

#' Top-level calls whose value is always invisible (evaluated without withVisible())
#' Not listed: calls whose query form prints (options("digits"), library(), suppress*(x)).
#' @noRd
eval_invisible_heads = c(
  "=", paste0("<", "-"), "<<-", "invisible", "for", "while", "repeat", "require", "print",
  "cat", "message", "set.seed", "rm", "setwd", "stopifnot"
)

#' Graphics hooks used for plot capture
#' @noRd
eval_hook_names = c("before.plot.new", "before.grid.newpage", "persp")

#' Monotonic seconds (04 section 1.2)
#' @noRd
eval_now = function() {
  as.numeric(proc.time()[["elapsed"]])
}

#' Evaluate model-written R code in the live session (the `evaluator` record `r`, IC-69)
#' Top-level expressions run one by one in `envir` with capture, plots and a time limit, stopping
#' at the first error; returns a `gptr_eval_result` (04 section 5.8), never a value (R1-R3, R8).
#' @noRd
eval_r = function(code, envir, timeout = NULL, plots = c("auto", "capture", "none"),
                  tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"),
                  guard = TRUE, rng = NULL, record = TRUE,
                  max_images = gptr_opt("r_max_images")) {
  check_string(code, "code", empty = TRUE)
  check_env(envir, "envir")
  plot_mode = check_choice(plots, c("auto", "capture", "none"), "plots")
  check_number(timeout, "timeout", min = 0, null = TRUE)
  check_flag(tee, "tee")
  check_number(budget_tokens, "budget_tokens", min = 1)
  check_flag(guard, "guard")
  check_env(rng, "rng", null = TRUE)
  check_flag(record, "record")
  check_number(max_images, "max_images", min = 0, int = TRUE)
  st = eval_state_new(as_utf8(code), timeout, plot_mode, tee, budget_tokens, guard, record,
                      max_images)
  st$envir = envir
  on.exit(eval_close(st), add = TRUE)
  state0 = eval_session_state()
  if (is.null(rng)) eval_run(st) else rng_swap(rng, eval_run(st))
  eval_result(st, state0)
}

#' The mutable state of one evaluation (holds `envir` only in the binding st$envir)
#' @noRd
eval_state_new = function(code, timeout, plots, tee, budget, guard, record, max_images) {
  st = new.env(parent = emptyenv())
  human = gptr_has_human()
  st$code = code
  st$human = human
  st$timeout = if (is.null(timeout)) (if (human) Inf else gptr_opt("r_timeout")) else timeout
  st$t0 = eval_now()
  st$deadline = if (is.finite(st$timeout)) st$t0 + st$timeout else Inf
  st$plots = plots
  st$tee = tee
  st$budget = budget
  st$guard = guard
  st$record = record
  st$max_images = as.integer(max_images)
  st$events = list()
  st$status = "ok"
  st$n_done = 0L
  st$n_total = 0L
  st$outputs = list()
  st$assigned = character()
  st$images = list()
  st$objects = NULL
  st$state1 = NULL
  st$interrupted_after = NULL
  st$line = NA_integer_
  st$catch_interrupt = is.null(run_current())
  st$restored = FALSE
  st
}

#' Append an event
#' @noRd
eval_push = function(st, type, ...) {
  st$events[[length(st$events) + 1L]] = list(type = type, ...)
  invisible()
}

#' Parse with source references under the file name "<gptr>", line ends as LF; an error object
#' on failure, also for code that is not valid UTF-8 (gsub() and the parser would throw; D-055)
#' @noRd
eval_parse = function(code) {
  if (!validUTF8(code)) {
    return(simpleError("<gptr>: the code is not valid UTF-8 text; nothing was evaluated."))
  }
  code = gsub("\r\n?", "\n", code)
  lines = strsplit(code, "\n", fixed = TRUE)[[1L]]
  tryCatch(parse(text = code, keep.source = TRUE, srcfile = srcfilecopy("<gptr>", lines)),
           error = function(e) e)
}

#' Parse, guard, shim, evaluate, restore; results land in `st`
#' @noRd
eval_run = function(st) {
  force(st)
  parsed = eval_parse(st$code)
  if (inherits(parsed, "error")) {
    eval_push(st, "error", message = conditionMessage(parsed), call = NULL,
              class = "parse_error", line = NA_integer_, timeout = FALSE,
              traceback = character())
    st$status = "parse_error"
    return(invisible(st))
  }
  st$n_total = length(parsed)
  st$outputs = rep(list(character()), st$n_total)
  if (!st$n_total) return(invisible(st))
  if (st$guard) {
    g = eval_guard(parsed)
    if (!is.null(g$reason)) {
      eval_push(st, "error", message = g$reason, call = NULL, class = "gptr_blocked",
                line = NA_integer_, timeout = FALSE, traceback = character())
      st$status = "blocked"
      return(invisible(st))
    }
  }
  exprs = gptr_shim(parsed, st$envir)
  st$assigned = eval_assign_targets(exprs)
  snap0 = env_snapshot_rows(st$envir, NULL, sizes = FALSE)
  eval_open(st)
  if (st$catch_interrupt) eval_loop_catch(st, exprs) else eval_loop(st, exprs)
  eval_finish(st)
  snap1 = env_snapshot_rows(st$envir, NULL, sizes = FALSE)
  st$objects = eval_objects(snap0, snap1, st$assigned)
  invisible(st)
}

#' Harness options, the anonymous-file sink and plot capture (undone by eval_restore()); the
#' message sink in use is noted, so one the code leaves open is undone
#' @noRd
eval_open = function(st) {
  force(st)
  st$old_opts = options(max.print = 1000L, width = 100L, rlang_interactive = FALSE,
                        cli.dynamic = FALSE, cli.num_colors = 1L, askYesNo = eval_no_ask)
  st$msg_sink = sink.number(type = "message")
  st$con = file("", "w+b")
  sink(st$con, split = st$tee)
  st$sink_n = sink.number()
  st$old_try = options(try.outFile = st$con)
  st$ps = plot_begin(st$plots, st$human)
  st$hook = eval_plot_hook(st)
  for (h in eval_hook_names) setHook(h, st$hook, "append")
  invisible(st)
}

#' The askYesNo option during an evaluation: the agent cannot ask through askYesNo() (a trap
#' for package code such as install.packages())
#' @noRd
eval_no_ask = function(...) {
  stop("askYesNo() is not available to the agent; use the ask tool.", call. = FALSE)
}

#' The plot hook; a closure that holds only `st`
#' @noRd
eval_plot_hook = function(st) {
  force(st)
  function(...) eval_on_plot_new(st)
}

#' Hook body: enable the display list on new devices, capture the finished page
#' @noRd
eval_on_plot_new = function(st) {
  plot_enable_new(st$ps)
  eval_capture_plot(st, FALSE)
}

#' Capture a plot and record its event after the output printed before it
#' @noRd
eval_capture_plot = function(st, incomplete) {
  if (is.null(st$ps) || !plot_capture(st$ps, incomplete)) return(invisible(FALSE))
  eval_flush(st)
  eval_push(st, "plot", index = st$ps$n, path = NULL, attached = FALSE, out_id = NULL)
  invisible(TRUE)
}

#' Read what the sink captured since the last read (recovers a popped sink or a closed file)
#' @noRd
eval_read_sink = function(st) {
  if (is.null(st$con)) return(NULL)
  if (!tryCatch(isOpen(st$con), error = function(e) FALSE)) {
    st$con = file("", "w+b")
    options(try.outFile = st$con)
  }
  if (sink.number() < st$sink_n) {
    sink(st$con, split = st$tee)
    st$sink_n = sink.number()
  }
  bytes = raw()
  repeat {
    b = readBin(st$con, "raw", n = 65536L)
    if (!length(b)) break
    bytes = c(bytes, b)
  }
  if (!length(bytes)) return(NULL)
  raw_to_utf8(bytes[bytes != as.raw(0L)])
}

#' Move captured output into an `output` event (merged with a preceding output event)
#' @noRd
eval_flush = function(st) {
  txt = eval_read_sink(st)
  if (is.null(txt) || !nzchar(txt)) return(invisible())
  n = length(st$events)
  if (n && identical(st$events[[n]]$type, "output")) {
    st$events[[n]]$text = paste0(st$events[[n]]$text, txt)
  } else {
    eval_push(st, "output", text = txt)
  }
  invisible()
}

#' Evaluate the expressions in order; stop at the first failure
#' @noRd
eval_loop = function(st, exprs) {
  force(st)
  force(exprs)
  srcrefs = attr(exprs, "srcref")
  for (i in seq_along(exprs)) {
    res = eval_one(st, exprs[[i]], i, srcrefs[[i]])
    if (!isTRUE(res)) {
      st$status = res
      break
    }
    st$n_done = i
  }
  invisible(st)
}

#' Outside a run nobody else handles interrupts: catch them here (status "interrupt")
#' @noRd
eval_loop_catch = function(st, exprs) {
  force(st)
  force(exprs)
  tryCatch(eval_loop(st, exprs), interrupt = function(cnd) eval_interrupted(st))
}

#' Record an interrupt that ended the evaluation
#' @noRd
eval_interrupted = function(st) {
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (is.null(st$interrupted_after)) st$interrupted_after = eval_now() - st$t0
  st$status = "interrupt"
  invisible(st)
}

#' Evaluate one top-level expression with calling handlers created here (this frame holds `st`,
#' never `envir`); TRUE, or "error"/"timeout" through the gptr_stop restart
#' @noRd
eval_one = function(st, expr, i, sref) {
  force(st)
  force(expr)
  force(i)
  force(sref)
  st$line = if (is.null(sref)) NA_integer_ else as.integer(sref[1L])
  eval_push(st, "source", text = paste(as.character(sref), collapse = "\n"), line = st$line)
  start = length(st$events)
  if (is.finite(st$deadline)) {
    remaining = st$deadline - eval_now()
    if (remaining <= 0) {
      eval_push(st, "error",
                message = sprintf("Timed out after %gs before expression %d of %d.",
                                  st$timeout, i, st$n_total),
                call = NULL, class = "gptr_timeout", line = st$line, timeout = TRUE,
                traceback = character())
      return("timeout")
    }
    setTimeLimit(elapsed = remaining, transient = TRUE)
  }
  res = withRestarts(
    withCallingHandlers(
      eval_one_body(st, expr),
      message = function(cnd) eval_on_message(st, cnd),
      warning = function(cnd) eval_on_warning(st, cnd),
      error = function(cnd) eval_on_error(st, cnd),
      interrupt = function(cnd) eval_on_interrupt(st)
    ),
    gptr_stop = function(why) why
  )
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (inherits(res, "condition")) res = eval_overflow(st, res)
  if (st$record) st$outputs[[i]] = eval_outputs_since(st, start)
  res
}

#' Evaluate, then capture a finished plot and the printed output; TRUE
#' @noRd
eval_one_body = function(st, expr) {
  eval_top(expr, st)
  eval_capture_plot(st, FALSE)
  eval_flush(st)
  TRUE
}

#' The traceback marker: user frames start after this frame
#' @noRd
eval_frame = function(expr, st) {
  eval(expr, st$envir)
}

#' Evaluate one expression and print it like the console; returns the visibility only
#' A symbol prints as `print(<sym>)` in the environment; invisible heads skip withVisible(), whose
#' result is cleared in place before this frame returns (R8, IC-67).
#' @noRd
eval_top = function(expr, st) {
  if (is.symbol(expr)) {
    eval_frame(call("print", expr), st)
    return(TRUE)
  }
  invisible_head = is.call(expr) && is.symbol(expr[[1L]]) &&
    as.character(expr[[1L]]) %in% eval_invisible_heads
  if (invisible_head) {
    eval_frame(expr, st)
    return(FALSE)
  }
  res = withVisible(eval_frame(expr, st))
  vis = res$visible
  if (vis) eval_print(res$value, st$envir)
  res[1L] = list(NULL)
  vis
}

#' Print a visible value as the console does (S4 through show())
#' Plain values print directly (the empty symbol cannot be bound); objects and functions as
#' `print(x)` in a child of `envir`, detached on exit so no frame home stays referenced (D-055).
#' @noRd
eval_print = function(value, envir) {
  if (isS4(value)) {
    methods::show(value)
    return(invisible(NULL))
  }
  if (!is.object(value) && !is.function(value)) {
    print(value)
    return(invisible(NULL))
  }
  pe = new.env(parent = envir)
  on.exit(eval_print_drop(pe), add = TRUE)
  assign("x", value, envir = pe)
  eval(quote(print(x)), pe)
  invisible(NULL)
}

#' Drop the print environment's references: its binding `x` and its parent
#' @noRd
eval_print_drop = function(pe) {
  if (exists("x", envir = pe, inherits = FALSE)) rm(list = "x", envir = pe)
  parent.env(pe) = emptyenv()
  invisible()
}

#' Message handler: record; muffle unless the output is teed to the user
#' @noRd
eval_on_message = function(st, cnd) {
  eval_flush(st)
  eval_push(st, "message", text = conditionMessage(cnd))
  if (!st$tee) tryInvokeRestart("muffleMessage")
  invisible()
}

#' Warning handler: record; under options(warn = 2) R turns the warning into an error next
#' @noRd
eval_on_warning = function(st, cnd) {
  w = getOption("warn", 0)
  if (w >= 2 || w < 0) return(invisible())
  eval_flush(st)
  eval_push(st, "warning", text = conditionMessage(cnd),
            call = eval_call_text(conditionCall(cnd)))
  if (!st$tee) tryInvokeRestart("muffleWarning")
  invisible()
}

#' Error handler: traceback first (as text), record, stop through gptr_stop
#' A stack overflow leaves the handler no stack, so it unwinds first; eval_overflow() records it.
#' @noRd
eval_on_error = function(st, cnd) {
  if (inherits(cnd, "stackOverflowError")) invokeRestart("gptr_stop", cnd)
  tb = eval_traceback()
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  eval_capture_plot(st, TRUE)
  eval_flush(st)
  to = eval_is_timeout(st, cnd)
  msg = if (to) {
    sprintf("Timed out after %gs (limit set by the harness).", st$timeout)
  } else {
    conditionMessage(cnd)
  }
  eval_push(st, "error", message = msg, call = eval_call_text(conditionCall(cnd)),
            class = class(cnd), line = st$line, timeout = to,
            traceback = if (to) character() else tb)
  invokeRestart("gptr_stop", if (to) "timeout" else "error")
}

#' Record a stack overflow after the restart unwound the recursion (R >= 4.2 classes); "error"
#' @noRd
eval_overflow = function(st, cnd) {
  eval_flush(st)
  eval_push(st, "error", message = conditionMessage(cnd), call = NULL, class = class(cnd),
            line = st$line, timeout = FALSE, traceback = character())
  "error"
}

#' Interrupt handler: record and decline, so the run's interrupt policy decides
#' @noRd
eval_on_interrupt = function(st) {
  if (is.null(st$interrupted_after)) st$interrupted_after = eval_now() - st$t0
  eval_flush(st)
  eval_push(st, "interrupt", message = "Interrupted by the user.",
            seconds = st$interrupted_after)
  invisible()
}

#' Is `cl` the evaluator's own `eval(expr, st$envir)` call? (source references ignored)
#' @noRd
eval_is_own_call = function(cl) {
  is.call(cl) && identical(as.call(as.list(cl)), quote(eval(expr, st$envir)))
}

#' Deparsed condition call, or NULL for the evaluator's own eval() call
#' @noRd
eval_call_text = function(cl) {
  if (is.null(cl) || eval_is_own_call(cl)) return(NULL)
  paste(deparse(cl, nlines = 1L, width.cutoff = 500L), collapse = "")
}

#' Did the harness time limit end the expression?
#' @noRd
eval_is_timeout = function(st, cnd) {
  if (!is.finite(st$deadline) || !inherits(cnd, "simpleError")) return(FALSE)
  msgs = unique(c("reached elapsed time limit", "reached CPU time limit",
                  gettext("reached elapsed time limit", domain = "R"),
                  gettext("reached CPU time limit", domain = "R")))
  any(vapply(msgs, grepl, NA, x = conditionMessage(cnd), fixed = TRUE))
}

#' Traceback lines of the current error: the user frames after eval_frame(), before the handler
#' Text only, so no call object (values inlined by do.call()) stays in the unwound handler frame.
#' @noRd
eval_traceback = function() {
  calls = sys.calls()
  n = length(calls)
  mark = 0L
  hand = n
  for (k in seq_len(n)) {
    fn = sys.function(k)
    if (identical(fn, eval_frame)) mark = k
    if (mark > 0L && identical(fn, eval_on_error)) {
      hand = k
      break
    }
  }
  if (!mark || hand - 2L <= mark) return(character())
  calls = calls[seq.int(mark + 1L, hand - 2L)]
  while (length(calls) && eval_is_own_call(calls[[1L]])) calls = calls[-1L]
  while (length(calls) && eval_is_internal(calls[[length(calls)]])) {
    calls = calls[-length(calls)]
  }
  eval_format_calls(calls)
}

#' Is `cl` a condition-system frame (trimmed from the end of a traceback)?
#' @noRd
eval_is_internal = function(cl) {
  internal = c(".handleSimpleError", ".signalSimpleWarning", "signalCondition", "withRestarts",
               "withOneRestart", "doWithOneRestart", "signal_abort", "withCallingHandlers")
  f = if (is.call(cl)) cl[[1L]] else NULL
  nm = ""
  if (is.symbol(f)) {
    nm = as.character(f)
  } else if (is.call(f) && length(f) == 3L) {
    nm = as.character(f[[3L]])
  }
  nm %in% internal
}

#' Traceback lines: at most 20 frames (the first 5, the last 15), 120 characters each, with
#' "at <gptr>#<line>" locations from source references
#' @noRd
eval_format_calls = function(calls, max_calls = 20L, width = 120L) {
  n = length(calls)
  if (!n) return(character())
  keep = if (n > max_calls) c(seq_len(5L), seq.int(n - max_calls + 6L, n)) else seq_len(n)
  out = character()
  for (i in keep) {
    cl = calls[[i]]
    txt = paste(deparse(cl, width.cutoff = 500L, nlines = 2L), collapse = " ")
    if (nchar(txt) > width) txt = paste0(substr(txt, 1L, width - 3L), "...")
    sr = attr(cl, "srcref")
    loc = ""
    if (!is.null(sr)) {
      sf = attr(sr, "srcfile")
      fname = if (!is.null(sf$filename) && nzchar(sf$filename)) basename(sf$filename) else "<code>"
      loc = sprintf(" at %s#%d", fname, sr[1L])
    }
    out[length(out) + 1L] = sprintf("%2d: %s%s", i, txt, loc)
    if (n > max_calls && i == 5L) {
      out[length(out) + 1L] = sprintf("    ... %d frames omitted ...", n - max_calls)
    }
  }
  out
}

#' Printed output lines of the events after position `start` (cleaned, empty lines dropped)
#' @noRd
eval_outputs_since = function(st, start) {
  ev = st$events
  if (length(ev) <= start) return(character())
  txt = character()
  for (k in seq.int(start + 1L, length(ev))) {
    if (identical(ev[[k]]$type, "output")) txt = c(txt, ev[[k]]$text)
  }
  if (!length(txt)) return(character())
  out = clean_terminal(paste(txt, collapse = ""))
  out[nzchar(out)]
}

#' Final capture, restore the session, render the plots (normal and restart paths)
#' The session state is taken before rendering, whose package loads are gptr's own (D-055).
#' @noRd
eval_finish = function(st) {
  eval_capture_plot(st, TRUE)
  eval_flush(st)
  eval_restore(st)
  st$state1 = eval_session_state()
  eval_plots_done(st)
  invisible(st)
}

#' Undo everything eval_open() did; idempotent, safe on every exit path
#' The message sink is reset first: code's `sink(stdout(), type = "message")` points at the capture
#' connection, which R would refuse to close (D-055).
#' @noRd
eval_restore = function(st) {
  if (isTRUE(st$restored)) return(invisible())
  st$restored = TRUE
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (!is.null(st$hook)) {
    for (h in eval_hook_names) {
      hs = getHook(h)
      keep = !vapply(hs, identical, NA, st$hook)
      setHook(h, hs[keep], "replace")
    }
    st$hook = NULL
  }
  if (!is.null(st$msg_sink)) {
    if (sink.number(type = "message") != st$msg_sink) eval_msg_sink_reset(st$msg_sink, st$con)
    st$msg_sink = NULL
  }
  if (!is.null(st$con)) {
    while (sink.number() >= st$sink_n && sink.number() > 0L) sink()
    if (!is.null(st$old_try)) options(st$old_try)
    tryCatch(if (isOpen(st$con)) close(st$con), error = function(e) NULL)
    st$con = NULL
  }
  if (!is.null(st$old_opts)) options(st$old_opts)
  plot_close(st$ps)
  invisible()
}

#' Point messages back to the sink in use before the evaluation: stderr, or the user's connection
#' while it is open; never a reopened capture connection that took its number (D-055)
#' @noRd
eval_msg_sink_reset = function(n, con) {
  sink(type = "message")
  if (n != 2L && (is.null(con) || n != as.integer(con))) {
    tryCatch(sink(getConnection(n), type = "message"), error = function(e) NULL)
  }
  invisible()
}

#' on.exit() of eval_r(): restore with interrupts suspended and drop the home reference (R2)
#' @noRd
eval_close = function(st) {
  suspendInterrupts({
    eval_restore(st)
    st$envir = NULL
  })
  invisible()
}

#' The session whose run is evaluating (the run's `shell` binding), or NULL
#' 04 section 7.6 types `gptr_run$session` as an id; without a session the process out store is
#' used and no context pressure is assumed.
#' @noRd
eval_session = function() {
  run = run_current()
  if (!is.environment(run)) return(NULL)
  s = get0("shell", envir = run, inherits = FALSE)
  if (inherits(s, "gptr_session")) s else NULL
}

#' The out store of the running session (its live record), or NULL for the process store
#' @noRd
eval_out_target = function() {
  s = eval_session()
  if (is.null(s)) return(NULL)
  live = session_live(s)
  if (is.environment(live) && exists("out", envir = live, inherits = FALSE)) live else NULL
}

#' Render the captured plots; attach the first ones and store the rest in one out entry
#' At most `max_images`, fewer when image tokens would pass 60% of the budget (IC-67); the others'
#' paths go to the session's out store for `gptr$plot(k)`.
#' @noRd
eval_plots_done = function(st) {
  if (is.null(st$ps) || !st$ps$n) return(invisible())
  w = gptr_opt("plot_width")
  h = gptr_opt("plot_height")
  files = plot_render_all(st$ps, 50L, w, h, gptr_opt("plot_res"))
  per = est_image_tokens(w, h)
  k_max = min(st$max_images, max(1L, floor(0.6 * st$budget / per)))
  stored = integer()
  for (j in seq_along(st$events)) {
    ev = st$events[[j]]
    if (!identical(ev$type, "plot")) next
    f = if (ev$index <= length(files)) files[ev$index] else NA_character_
    if (is.na(f)) next
    ev$path = f
    if (length(st$images) < k_max) {
      st$images[[length(st$images) + 1L]] = plot_block(f, w, h)
      ev$attached = TRUE
    } else {
      stored = c(stored, j)
    }
    st$events[[j]] = ev
  }
  if (length(stored)) {
    idx = vapply(st$events[stored], function(e) e$index, 1L)
    paths = vapply(st$events[stored], function(e) e$path, "")
    id = out_put(sprintf("plot %d: %s", idx, paths), meta = list(
      kind = "plots", index = idx, path = paths, width = w, height = h
    ), session = eval_out_target())
    for (j in stored) st$events[[j]]$out_id = id
  }
  invisible()
}

#' Object changes of an evaluation with their model-facing lines
#' An added promise or active binding shows its kind, never its class; lines are valid UTF-8.
#' @noRd
eval_objects = function(old, new, assigned) {
  d = env_diff(old, new, assigned)
  i = match(d$added, new$name)
  add = character()
  if (length(i)) {
    what = ifelse(new$kind[i] == "value", trimws(paste(new$class[i], new$shape[i])),
                  new$kind[i])
    add = sprintf("+ %s <%s>", env_text(d$added), env_text(what))
  }
  j = match(d$modified, new$name)
  mod = character()
  if (length(j)) {
    cls = ifelse(is.na(new$class[j]), new$kind[j], new$class[j])
    mod = sprintf("~ %s <%s> modified", env_text(d$modified), env_text(cls))
  }
  rem = if (length(d$removed)) sprintf("- %s removed", env_text(d$removed)) else character()
  c(d, list(lines = c(add, mod, rem)))
}

#' Session-wide state compared before and after an evaluation (kept in memory only)
#' @noRd
eval_session_state = function() {
  list(wd = getwd(), options = options(), envvars = Sys.getenv(), search = search(),
       ns = loadedNamespaces(), devices = grDevices::dev.list())
}

#' Differences of eval_session_state(): option and variable names (never values), the working
#' directory, packages and devices; a new `TZDIR` is R's own (set when a time is first formatted)
#' @noRd
eval_state_diff = function(a, b) {
  on = union(names(a$options), names(b$options))
  opt = on[!vapply(on, function(n) identical(a$options[[n]], b$options[[n]]), NA)]
  en = union(names(a$envvars), names(b$envvars))
  env = en[!vapply(en, function(n) identical(a$envvars[n], b$envvars[n]), NA)]
  if (!("TZDIR" %in% names(a$envvars))) env = setdiff(env, "TZDIR")
  wd = if (identical(a$wd, b$wd)) NULL else c(from = a$wd, to = b$wd)
  devices = NULL
  if (!identical(a$devices, b$devices)) {
    devices = list(from = names(a$devices), to = names(b$devices))
  }
  list(wd = wd, options = opt, envvars = env, attached = setdiff(b$search, a$search),
       loaded = setdiff(b$ns, a$ns), devices = devices)
}

#' Assemble the gptr_eval_result (04 section 5.8); `changes$objects` carries the object diff
#' @noRd
eval_result = function(st, state0) {
  ch = eval_state_diff(state0, st$state1 %||% eval_session_state())
  ch$objects = st$objects %||%
    list(added = character(), modified = character(), removed = character(),
         lines = character())
  structure(
    list(status = st$status, events = st$events, n_done = st$n_done, n_total = st$n_total,
         changes = ch, elapsed = eval_now() - st$t0, images = st$images,
         assigned = st$assigned, outputs = st$outputs, spill = NULL, out_id = NULL,
         interrupted_after = st$interrupted_after),
    class = "gptr_eval_result"
  )
}
