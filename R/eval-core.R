# eval-core.R -- the hand-rolled evaluator eval_r() and the RNG swap rng_swap() (P09).
#
# Adapted from report 12 section 5.1 (gptr_eval2.R: anonymous-file sink, calling handlers,
# per-expression time limits, trimmed tracebacks, plot hooks, harness options) with the fixes of
# its verification log (items 3, 4, 9, 10, 25), the contract's amendments (04 section 7.9;
# IC-61, IC-67) and the G3 fact-check fix for function-frame homes. Frame layout, verified with
# fresh-process tracemem runs (test-copy-eval.R):
#   eval_r()        binds `envir`; creates no closure, no tryCatch() and no loop; stores `envir`
#                   in the state environment `st` and resets st$envir to NULL on exit (R2).
#   eval_run(), eval_loop(), eval_loop_catch(), eval_one()
#                   hold only `st`; eval_one() creates the calling handlers and the restart.
#                   Every helper forces its arguments on entry (R3).
#   eval_top(), eval_frame()
#                   closure-free leaves that reach `envir` through st$envir; every withVisible()
#                   result is cleared in place with res[1L] = list(NULL) (R8, IC-67).
# The value of an evaluation is never kept. Known limit (R itself, not gptr): an error unwinds
# the frames between the failing call and the restart without releasing what they reference, so
# an object the failing code passed through a function (or a home frame the failing code forced)
# copies once on its next in-place edit, exactly as after try() in user code.

#' L'Ecuyer-CMRG seed vector from a key (IC-61)
#'
#' 24 bytes of sha256(key): three 32-bit words reduced modulo m1 = 4294967087 and three modulo
#' m2 = 4294944443, stored as R integers (two's complement) after the kind code 10407L. Uses no
#' random number generator. The word 2^31 has no R integer other than NA_integer_ (its
#' two's-complement bit pattern), so it is stored as NA without a coercion warning; R reads
#' that NA back as the word 2^31.
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

#' Evaluate `expr` with an agent's L'Ecuyer stream in .Random.seed (a leaf)
#'
#' Saves the user's `.Random.seed` of the global environment (or its absence), assigns
#' `state$seed` (derived with rng_seeds(state$id) when unset: `id` is the agent id, or
#' `"<.opts$seed>:<agent label>"` for reproducible streams, IC-61), evaluates, keeps the
#' advanced vector in `state$seed` and restores or removes the user's value. With
#' with_seed_preserved() the only code that assigns .Random.seed. R also keeps its generator
#' kind internally, and set.seed() keeps the kind in force: removing the variable alone would
#' leave L'Ecuyer-CMRG in force, so the user's next `set.seed(42)` would draw other numbers.
#' When the user had no seed, the kind code is therefore read before the swap and put back
#' after it: `stats::rbinom(1L, 0L, 0.5)` makes R load (or initialise) and store its state
#' without drawing a number (size 0 returns 0), and the variable it stores is removed again.
#' When the user had a seed, restoring the vector alone leaves the agent's kind in force
#' internally until R next reads the variable, so a user who then removed `.Random.seed` would
#' get L'Ecuyer-CMRG from `set.seed()`. The same call makes R read the kind from the restored
#' vector. It is silent and never fails, also for a vector R rejects (R checks that vector again
#' at the user's next draw), and the vector is assigned again so it stays identical.
#' @param state An environment: `seed` (the vector, or NULL) and `id`.
#' @param expr The expression to evaluate (lazily, inside the swap).
#' @return The value of `expr`.
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

#' Top-level calls whose value is always invisible: evaluated without withVisible(). Calls whose
#' query form prints at the console (options("digits"), library(), suppress*(x)) are not listed.
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

#' Evaluate model-written R code in the live session
#'
#' The built-in `evaluator` record `r` (IC-69). Parses `code` with `srcfilecopy("<gptr>", ...)`,
#' applies the static guard and the `gptr::` shim, evaluates the top-level expressions one by
#' one in `envir` with output, message, warning and error capture, plot capture and a time
#' limit, stops at the first error and returns a `gptr_eval_result` (04 section 5.8). Never
#' keeps the value of an evaluation (R8). Copy-safety: rules R1, R2, R3 and R8.
#' @param code R code: one string, possibly several expressions.
#' @param envir The evaluation environment (the run's `run_eval_env()`).
#' @param timeout Seconds, or NULL: none with a human present, else `gptr.r_timeout`.
#' @param plots "auto", "capture" or "none" (see plot_begin()).
#' @param tee Also show the output to the user (split sink).
#' @param budget_tokens Output budget; image tokens count against it (IC-67).
#' @param guard Apply eval_guard().
#' @param rng NULL, or an environment with the agent's L'Ecuyer state (see rng_swap()).
#' @param record Collect the printed output of each top-level expression (`outputs`).
#' @param max_images Plots attached as images; the rest go to the out store (IC-67).
#' @return A `gptr_eval_result`.
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

#' Parse with source references under the file name "<gptr>" (CR LF and CR line ends become LF);
#' an error object on failure, also for code that is not valid UTF-8 after as_utf8() (gsub()
#' and the parser would throw or warn on it)
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
#'
#' A symbol is printed by name (`print(<sym>)` evaluated in the environment), any other visible
#' value by eval_print() with the print methods visible from the environment, assignments and
#' other invisible heads never pass through withVisible(), and a withVisible() result is
#' cleared in place before this frame returns (R8, IC-67).
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

#' Print a visible value: S4 objects through show(), others as R's console does
#' (PrintValueEnv()). The console dispatches print() for objects and functions only; for those,
#' `print(x)` is evaluated in a short-lived child of `envir`, so a print method defined in a
#' home other than globalenv() (a function frame, an overlay) is used, as it is for a symbol.
#' Other values print as in the plan: binding the empty symbol (an argument without a default,
#' from formals() or alist()) to `x` would make `print(x)` fail, where the console prints a
#' blank line. Before this frame returns, the binding `x` is removed and the child is
#' detached from `envir`: a child left pointing at a function-frame home counts as a reference
#' to the frame, and R then keeps the frame's arguments referenced after the function returns,
#' so the user's next edit copies them (R2, R8).
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
#'
#' An infinite recursion leaves a handler almost no stack (a tryCatch() inside it fails again
#' with "evaluation nested too deeply"), so a stack overflow unwinds first and is recorded by
#' eval_overflow() at the normal depth.
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
#'
#' Returns text only, so no call object (which may carry values inlined by do.call()) is left in
#' the handler frame that the restart unwinds.
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
#'
#' The session state is taken before the plots are rendered: rendering is gptr's own work (it
#' loads ragg, systemfonts and textshaping on the first plot of a process), not a change the
#' evaluated code made.
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
#'
#' The message sink is reset before the capture connection is closed: while output is
#' captured, stdout() is that connection, so `sink(stdout(), type = "message")` in the code
#' points messages at it, and R refuses to close a message sink. The close cannot throw, so
#' the options and the plot device are always restored.
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

#' Point messages back to the sink in use before the evaluation: stderr (2), or the user's own
#' connection while it is still open (else stderr). The code's connection is its own object and
#' stays open. A capture connection reopened by eval_read_sink() after the code closed both it
#' and the user's connection can hold the user's number; it is never pointed at.
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

#' The session whose run is evaluating, or NULL
#'
#' 04 section 7.6 types `gptr_run$session` as an id and the kernel SDK has no id-to-session
#' accessor; the run's `shell` binding (the session object, when P06 provides it) is read
#' defensively. Without it the process out store is used and no context pressure is assumed.
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
#'
#' At most `max_images` plots are attached, and fewer when their image tokens would take more
#' than 60% of the output budget (IC-67); the paths of the others are kept in the session's out
#' store for `gptr$plot(k)` (P10), one entry for the whole evaluation.
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
#'
#' An added promise or active binding shows its kind (`+ p <promise>`), never its unforced
#' class; names, classes and shapes go through env_text(), so the lines are valid UTF-8.
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
#' directory, attached and loaded packages, devices. `TZDIR` appearing is not reported: R sets
#' it itself the first time a time is formatted (macOS), whoever formats it (gptr's own ids
#' too).
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
