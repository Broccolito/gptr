# Replay the actual memory-error handler; no ps import, process, native query or real sleep.
(function() {
  args = commandArgs(trailingOnly = TRUE)
  stopifnot(length(args) == 1L, file.exists(args[[1L]]))
  tree = parse(args[[1L]], keep.source = FALSE)
  # The enclosing sampler also contains the memory call; choose the innermost catch.
  collect = function(expr) {
    candidates = list()
    if (is.call(expr) && identical(expr[[1L]], as.name("tryCatch")) &&
        grepl("ps::ps_memory_info", paste(deparse(expr[[2L]]), collapse = " "), fixed = TRUE)) {
      candidates = list(expr)
    }
    if (!(is.call(expr) || is.expression(expr) || is.pairlist(expr))) return(candidates)
    for (i in seq_along(expr)) {
      if (is.name(expr[[i]]) && !nzchar(as.character(expr[[i]]))) next
      candidates = c(candidates, collect(expr[[i]]))
    }
    candidates
  }
  candidates = collect(tree)
  stopifnot(length(candidates) == 2L)
  memory = candidates[[2L]]
  stopifnot(identical(names(as.list(memory))[-(1:2)], "error"))
  handler = memory[["error"]]
  stopifnot(!grepl("::", paste(deparse(handler), collapse = " "), fixed = TRUE))
  run = function(sequence, original = simpleError("Synthetic memory query failed"),
                  sleep_failure = NULL, query_cost = 0) {
    scope = new.env(parent = baseenv())
    handle = new.env(parent = emptyenv())
    handle$pid = 12345L
    handle$create_time = 123.125
    scope$handle = handle
    scope$tracked = list(handles = list(handle), identities = list(
      list(pid = handle$pid, create_time = handle$create_time)))
    cached = serialize(scope$tracked, NULL)
    ambient = Sys.getenv()
    scope$clock = 0
    scope$calls = 0L
    scope$waits = numeric()
    scope$seen = list()
    scope$proc_handle_alive = function(held) {
      stopifnot(identical(held, handle))
      scope$seen[[length(scope$seen) + 1L]] = held
      scope$calls = scope$calls + 1L
      scope$clock = scope$clock + query_cost
      value = sequence[[min(scope$calls, length(sequence))]]
      if (inherits(value, "condition")) stop(value)
      value
    }
    scope$proc.time = function() c(elapsed = scope$clock)
    scope$Sys.sleep = function(delay) {
      stopifnot(is.numeric(delay), length(delay) == 1L, is.finite(delay),
        delay > 0, delay <= 0.05)
      scope$waits = c(scope$waits, delay)
      if (!is.null(sleep_failure)) stop(sleep_failure)
      scope$clock = scope$clock + delay
      invisible(NULL)
    }
    scope$ps_memory_info = function(...) stop("Memory query must not be retried")
    scope$ps_handle = function(...) stop("Native handle must not be recreated")
    callback = eval(handler, scope)
    result = tryCatch(callback(original), error = function(error) error,
      interrupt = function(error) error)
    stopifnot(identical(Sys.getenv(), ambient), identical(serialize(scope$tracked, NULL), cached),
      all(vapply(scope$seen, function(held) identical(held, handle), logical(1))),
      scope$calls <= 6L)
    list(result = result, original = original, calls = scope$calls,
      elapsed = scope$clock, waits = scope$waits)
  }
  exact_failure = function(x) identical(x$result, x$original)
  immediate = run(list(FALSE))
  late = run(list(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  first_wait = run(list(TRUE, FALSE))
  mixed = run(list(NA, TRUE, NA, FALSE))
  live = run(list(TRUE))
  unknown = run(list(NA))
  original = structure(list(message = "Synthetic private memory query", call = NULL,
    errno = 0L), class = c("access_denied", "ps_error", "error", "condition"))
  typed = run(list(TRUE), original = original)
  query_error = run(list(TRUE, simpleError("Synthetic liveness failure")), original = original)
  query_interrupt = run(list(TRUE, structure(list(message = "Synthetic interrupt", call = NULL),
    class = c("interrupt", "condition"))), original = original)
  sleep_error = run(list(TRUE), original = original,
    sleep_failure = simpleError("Synthetic sleep"))
  sleep_interrupt = run(list(TRUE), original = original,
    sleep_failure = structure(list(message = "Synthetic sleep interrupt", call = NULL),
      class = c("interrupt", "condition")))
  overdue = run(list(TRUE), original = original, query_cost = 0.06)
  invalid = run(list(TRUE, NULL), original = original)
  interruption = structure(list(message = "Synthetic original interrupt", call = NULL),
    class = c("interrupt", "condition"))
  original_interrupt = run(list(TRUE), original = interruption)
  checks = c(immediate_dead_zero = identical(immediate$result, 0),
    immediate_dead_no_wait = length(immediate$waits) == 0L && immediate$calls == 1L,
    dead_at_first_wait_zero = identical(first_wait$result, 0) && first_wait$calls == 2L,
    dead_at_last_wait_zero = identical(late$result, 0) && late$calls == 6L,
    scheduled_wait_bounded = late$elapsed <= 0.05 && sum(late$waits) <= 0.05,
    earlier_unknown_is_not_death = identical(mixed$result, 0) && mixed$calls == 4L,
    live_original_condition = exact_failure(live),
    unknown_original_condition = exact_failure(unknown),
    live_checks_all_targets = live$calls == 6L,
    unknown_checks_all_targets = unknown$calls == 6L,
    typed_condition_identity = exact_failure(typed),
    liveness_error_keeps_original = exact_failure(query_error),
    liveness_interrupt_keeps_original = exact_failure(query_interrupt),
    sleep_error_keeps_original = exact_failure(sleep_error),
    sleep_interrupt_keeps_original = exact_failure(sleep_interrupt),
    already_overdue_no_wait = exact_failure(overdue) && length(overdue$waits) == 0L &&
      overdue$calls == 1L,
    invalid_liveness_never_zero = exact_failure(invalid),
    original_interrupt_identity = exact_failure(original_interrupt),
    all_same_handle_cache_env_invariants = TRUE)
  for (i in seq_along(checks)) {
    cat("CHECK ", names(checks)[[i]], " ", checks[[i]], "\n", sep = "")
  }
  stopifnot(all(checks))
  invisible(NULL)
})()
