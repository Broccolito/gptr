# Default-off test diagnosis. These functions never repair a failed case or change its caps.
rss_snapshot = function() {
  names = ls(globalenv(), all.names = TRUE)
  list(env = Sys.getenv(), options = options(), cwd = getwd(), libs = .libPaths(),
    kind = RNGkind(), search = search(),
    seed = if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
      get(".Random.seed", globalenv(), inherits = FALSE)
    } else {
      NULL
    },
    objects = serialize(mget(names, globalenv(), inherits = FALSE), NULL))
}

rss_flags = function(before, after) {
  stopifnot(identical(names(before), names(after)), length(before) == 8L)
  stats::setNames(vapply(names(before), function(name) {
    identical(before[[name]], after[[name]])
  }, logical(1)), names(before))
}

rss_write = function(value, path) {
  jsonlite::write_json(value, path, pretty = TRUE, auto_unbox = TRUE,
    null = "null", na = "null", digits = NA)
}

rss_digest = function(path) {
  stopifnot(file.exists(path), !dir.exists(path), !nzchar(Sys.readlink(path)))
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

rss_result = function(results) {
  lapply(results, function(test) {
    entries = test$results
    count = function(classes) sum(vapply(entries, inherits, logical(1), what = classes))
    bad = Filter(function(entry) {
      inherits(entry, c("expectation_failure", "expectation_error", "expectation_warning",
        "expectation_skip", "warning"))
    }, entries)
    list(test = test$test, file = test$file, passed = count("expectation_success"),
      failed = count("expectation_failure"), errors = count("expectation_error"),
      warnings = count(c("expectation_warning", "warning")), skipped = count("expectation_skip"),
      conditions = lapply(bad, function(entry) list(classes = class(entry))))
  })
}

rss_capture = function(output, collect, gc_observation,
                        snapshot = rss_snapshot, flags = rss_flags, write = rss_write) {
  stopifnot(is.logical(collect), length(collect) == 1L, !is.na(collect))
  state = new.env(parent = emptyenv())
  state$target_seen = 0L
  state$collections = 0L
  state$events = 0L
  state$fatal_seen = FALSE
  state$gc = NULL
  callback = function(stage, data, supervisor_rss = NULL) {
    stopifnot(stage %in% c("before_observer", "initialization", "sample", "sample_failure",
      "settled"), is.list(data), length(data$case) == 1L, is.character(data$case))
    state$events = state$events + 1L
    stopifnot(state$events <= 100000L)
    target = identical(stage, "before_observer") && isTRUE(data$writer) &&
      identical(data$case, "ordered")
    if (target) {
      state$target_seen = state$target_seen + 1L
      stopifnot(state$target_seen == 1L)
      if (collect) {
        stopifnot(is.function(supervisor_rss), state$collections == 0L)
        before = snapshot()
        value = tryCatch(gc_observation(supervisor_rss), error = identity, interrupt = identity)
        after = tryCatch(snapshot(), error = identity, interrupt = identity)
        if (inherits(value, "condition")) stop(value)
        if (inherits(after, "condition")) stop(after)
        same = flags(before, after)
        stopifnot(all(same))
        state$collections = 1L
        state$gc = c(value, list(all8 = as.list(same)))
        write(state$gc, file.path(output, "gc-summary.json"))
      }
    }
    if (isTRUE(data$resource_failure) || identical(stage, "sample_failure") ||
        (!is.null(data$guard) && nzchar(data$guard))) state$fatal_seen = TRUE
    row = list(event = state$events, stage = stage, data = data,
      target_seen = state$target_seen, collections = state$collections,
      prior_fatal_retained = state$fatal_seen, product_acceptance = FALSE)
    text = jsonlite::toJSON(row, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    stopifnot(nchar(text, type = "bytes") <= 65536L)
    cat(text, "\n", file = file.path(output, "rss-events.jsonl"), append = TRUE, sep = "")
    invisible(NULL)
  }
  list(callback = callback, state = state)
}

# Discover marker-free descendants only through the exact owned cell root.
# Remembered handles retain their admitted PID/time; a reused PID is never substituted.
rss_census = function(root, root_pid, root_time, marker, remembered = list(),
                      children = ps::ps_children, marked = ps::ps_find_tree,
                      pid = ps::ps_pid, create_time = ps::ps_create_time,
                      alive = ps::ps_is_running, supervisor_pid = Sys.getpid()) {
  valid_pid = function(value) {
    is.numeric(value) && length(value) == 1L && is.finite(value) && value > 0 &&
      value <= .Machine$integer.max && value == floor(value)
  }
  stopifnot(valid_pid(root_pid), valid_pid(supervisor_pid), root_pid != supervisor_pid,
    is.numeric(root_time), length(root_time) == 1L, is.finite(root_time), root_time > 0,
    is.character(marker), length(marker) == 1L, !is.na(marker), nzchar(marker),
    is.list(remembered))
  state = new.env(parent = emptyenv())
  state$rows = list()
  remember = function(handle, expected_pid = NULL, expected_time = NULL) {
    observed_pid = pid(handle)
    observed_time = as.numeric(create_time(handle))
    stopifnot(valid_pid(observed_pid), observed_pid != supervisor_pid,
      length(observed_time) == 1L, is.finite(observed_time), observed_time > 0)
    observed_pid = as.integer(observed_pid)
    if (!is.null(expected_pid)) {
      stopifnot(valid_pid(expected_pid), identical(observed_pid, as.integer(expected_pid)))
    }
    if (!is.null(expected_time)) stopifnot(identical(observed_time, expected_time))
    existing = which(vapply(state$rows, function(row) identical(row$pid, observed_pid), logical(1)))
    if (length(existing)) {
      stopifnot(length(existing) == 1L, identical(state$rows[[existing]]$time, observed_time))
    } else {
      state$rows[[length(state$rows) + 1L]] = list(handle = handle, pid = observed_pid,
        time = observed_time)
    }
    invisible(NULL)
  }
  remember(root, root_pid, root_time)
  for (row in remembered) {
    stopifnot(is.list(row), identical(names(row), c("handle", "pid", "time")),
      valid_pid(row$pid), is.numeric(row$time), length(row$time) == 1L,
      is.finite(row$time), row$time > 0)
    remember(row$handle, row$pid, row$time)
  }
  running = alive(root)
  stopifnot(is.logical(running), length(running) == 1L, !is.na(running))
  if (running) {
    descendants = children(root, recursive = TRUE)
    stopifnot(is.list(descendants))
    remember(root, root_pid, root_time)
    for (handle in descendants) remember(handle)
  }
  carrying_marker = marked(marker)
  stopifnot(is.list(carrying_marker))
  for (handle in carrying_marker) remember(handle)
  remember(root, root_pid, root_time)
  state$rows
}

# Same-handle death confirmation reuses the existing case sampler's 50 ms bound.
rss_memory = function(handle, time, create_time = ps::ps_create_time,
                      alive = ps::ps_is_running, memory_info = ps::ps_memory_info,
                      now = function() proc.time()[["elapsed"]], pause = Sys.sleep) {
  living = function() {
    stopifnot(identical(as.numeric(create_time(handle)), time))
    value = alive(handle)
    stopifnot(is.logical(value), length(value) == 1L, !is.na(value))
    value
  }
  if (isFALSE(living())) return(0)
  value = tryCatch(unname(memory_info(handle)[["rss"]]), error = function(original) {
    dead = tryCatch({
      began = now()
      confirmed = isFALSE(living())
      if (!confirmed) {
        for (target in c(1, 5, 10, 25, 50)) {
          elapsed = now() - began
          if (elapsed >= 0.05) break
          remaining = target / 1000 - elapsed
          if (remaining > 0) pause(remaining)
          if (isFALSE(living())) {
            confirmed = TRUE
            break
          }
        }
      }
      confirmed
    }, error = function(observation_error) FALSE,
      interrupt = function(observation_error) FALSE)
    if (isTRUE(dead)) 0 else stop(original)
  })
  stopifnot(length(value) == 1L, is.finite(value), value >= 0)
  value
}

# Attempt every owned cleanup stage even when an earlier operation fails.
rss_cleanup = function(kill_root, kill_marked, settle, known_stopped, launch_unknown) {
  first = NULL
  attempt = function(expr) {
    value = tryCatch(force(expr), error = base::identity, interrupt = base::identity)
    if (inherits(value, "condition") && is.null(first)) first <<- value
    value
  }
  attempt(kill_root())
  attempt(kill_marked())
  family = attempt(settle())
  attempt(stopifnot(is.list(family), isTRUE(family$settled)))
  attempt(stopifnot(isTRUE(known_stopped()), !launch_unknown))
  list(complete = is.null(first), error = first,
    family = if (inherits(family, "condition")) NULL else family)
}
