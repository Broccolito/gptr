# Controls launch or signal no process; one case queries the current native process read-only.
path = file.path("dev", "ci", "windows-startup", "controller.R")
if (!file.exists(path)) path = "controller.R"
source(path, local = TRUE)

owner = "GPTROPTowned_1770000000"
intent = charToRaw(paste(owner, "1", "empty", sep = "|"))
identity_bytes = charToRaw(paste(owner, "1", "empty", "123", "1770000000.125", sep = "|"))

testthat::test_that("only a bounded exact owner and attempted profile admit identities", {
  testthat::expect_identical(startup_decode(intent, owner, 1L, FALSE)$index, 1L)
  expected = startup_decode(identity_bytes, owner, 1L, TRUE)
  testthat::expect_identical(expected$pid, 123L)
  testthat::expect_identical(expected$create_time, 1770000000.125)
  testthat::expect_error(startup_decode(identity_bytes, "GPTROPTother_1770000000", 1L, TRUE))
  testthat::expect_error(startup_decode(identity_bytes, owner, 2L, TRUE))
  testthat::expect_error(startup_decode(c(identity_bytes, charToRaw("|private")), owner, 1L, TRUE))
  testthat::expect_error(startup_decode(c(identity_bytes, charToRaw("|")), owner, 1L, TRUE))
  testthat::expect_error(startup_decode(as.raw(rep(65L, 513L)), owner, 1L, TRUE))
  testthat::expect_error(startup_decode(charToRaw(paste(owner, "1", "empty", "123", "NaN",
    sep = "|")), owner, 1L, TRUE))
})

testthat::test_that("begun launches without published identities cannot become known", {
  files = list("launch-1.txt" = intent)
  scan = function() {
    startup_scan("unused", owner,
      entries = function(path) names(files), read = function(path) files[[basename(path)]])
  }
  testthat::expect_true(scan()$unknown)
  testthat::expect_length(scan()$identities, 0L)
  files[["identity-1.txt"]] = identity_bytes
  testthat::expect_false(scan()$unknown)
  testthat::expect_length(scan()$identities, 1L)
  files[["identity-1.txt"]] = NULL
  testthat::expect_true(scan()$unknown)
  files = list("identity-1.txt" = identity_bytes)
  testthat::expect_true(scan()$unknown)
  testthat::expect_length(scan()$identities, 0L)
  files = list("launch-1.txt" = intent, "identity-1.txt.part" = identity_bytes)
  testthat::expect_true(scan()$unknown)
})

testthat::test_that("stale or dead exact handles are never signalled and unknowns fail", {
  expected = startup_decode(identity_bytes, owner, 1L, TRUE)
  handle = list(pid = expected$pid, create_time = expected$create_time)
  state = new.env(parent = emptyenv())
  state$signals = list()
  fresh = c(handle, list(native = TRUE))
  make = function(pid, time = NULL) {
    testthat::expect_identical(pid, handle$pid)
    if (is.null(time)) return(fresh)
    testthat::expect_s3_class(time, "POSIXct")
    testthat::expect_identical(as.numeric(time), handle$create_time)
    handle
  }
  kill = function(value) state$signals[[length(state$signals) + 1L]] = value
  # ps_is_running(exact_handle) is FALSE for both death and a recycled PID.
  dead = startup_identity(expected, make, running = function(value) FALSE, kill = kill)
  testthat::expect_identical(dead, "dead-exact")
  testthat::expect_length(state$signals, 0L)
  unknown = startup_identity(expected, make, running = function(value) NA, kill = kill)
  testthat::expect_identical(unknown, "unknown")
  testthat::expect_length(state$signals, 0L)
  testthat::expect_identical(startup_identity(expected, make,
    running = function(value) stop("controlled lookup failure"), kill = kill), "unknown")
  testthat::expect_identical(startup_identity(expected,
    make = function(pid, time) stop("controlled identity failure"), kill = kill), "unknown")
  live = startup_identity(expected, make, running = function(value) TRUE, kill = kill,
    pid = function(value) value$pid, created = function(value) {
      as.POSIXct(value$create_time, origin = "1970-01-01", tz = "UTC")
    })
  testthat::expect_identical(live, "alive")
  testthat::expect_identical(state$signals, list(fresh))
})

testthat::test_that("the external clock includes constructor time and never waits past 60", {
  clock = new.env(parent = emptyenv())
  clock$t = 0
  clock$waits = numeric()
  process = list(is_alive = function() TRUE, wait = function(milliseconds) {
    clock$waits = c(clock$waits, milliseconds)
    clock$t = clock$t + milliseconds / 1000
  })
  testthat::expect_false(startup_wait(process, 0, now = function() clock$t))
  testthat::expect_equal(clock$t, 60, tolerance = 1e-8)
  testthat::expect_true(all(clock$waits <= 50))
  clock$t = 61
  clock$waits = numeric()
  testthat::expect_false(startup_wait(process, 0, now = function() clock$t))
  testthat::expect_length(clock$waits, 0L)
  clock$t = 59
  process$is_alive = function() {
    clock$t = 61
    FALSE
  }
  testthat::expect_false(startup_wait(process, 0, now = function() clock$t))
})

testthat::test_that("publication, cleanup and process proof are independent fatal gates", {
  clean = list(settled = TRUE, unknown = FALSE, identities = rep("dead-exact", 4L),
    journal_attempts = seq_len(4L))
  testthat::expect_true(startup_closed(clean, TRUE, TRUE, TRUE))
  testthat::expect_false(startup_closed(clean, FALSE, TRUE, TRUE))
  testthat::expect_false(startup_closed(clean, TRUE, FALSE, TRUE))
  testthat::expect_false(startup_closed(clean, TRUE, TRUE, FALSE))
  clean$unknown = TRUE
  testthat::expect_false(startup_closed(clean, TRUE, TRUE, TRUE))
  clean$unknown = FALSE
  clean$identities = "unknown"
  testthat::expect_false(startup_closed(clean, TRUE, TRUE, TRUE))
  clean$identities = character()
  clean$journal_attempts = integer()
  testthat::expect_false(startup_closed(clean, TRUE, TRUE, TRUE))
})

testthat::test_that("partial publication preserves fixed observations without private fields", {
  value = list(schema = "gptr-powershell-startup-v2", owner = owner,
    fixture_lookup_matches_native = TRUE, processx = "3.9.0", ps = "1.9.1", R = "4.7.0",
    profile_order = startup_profiles, rows = list(),
    parent_state = stats::setNames(as.list(rep(TRUE, 5L)),
      c("options", "startup_env_presence", "cwd", "seed", "global_names")), complete = FALSE)
  testthat::expect_true(startup_observation(value, owner))
  value$parent_state = list()
  testthat::expect_false(startup_observation(value, owner))
  value$parent_state = stats::setNames(as.list(rep(TRUE, 5L)),
    c("options", "startup_env_presence", "cwd", "seed", "global_names"))
  value$private = "unapproved field"
  testthat::expect_false(startup_observation(value, owner))
  value$private = NULL
  value$owner = "GPTROPTother_1770000000"
  testthat::expect_false(startup_observation(value, owner))
  value$owner = owner
  value$rows = list(list(index = 1L, profile = "empty", limit_seconds = 5, status = 0L,
    failure = "none", timeout = FALSE, stage = "done", entered_elapsed = 0.1,
    construction_elapsed = 0.05, launch_elapsed = 0.2, settled = TRUE, cleanup_failed = FALSE,
    child_observations = 0L, pid = 123L, create_time = 1770000000.125,
    stdout_bytes = 100L, stderr_bytes = 0L,
    tokens = c("GPTR-PS-STARTUP-ENTERED", "GPTR-PS-ENV=1,1,1,1,1", "GPTR-PS-NATIVE=1",
      "GPTR-PS-STARTUP-DONE"), ok = TRUE))
  testthat::expect_true(startup_observation(value, owner))
  value$rows[[1L]]$create_time = as.POSIXct(1770000000.125, origin = "1970-01-01", tz = "GMT")
  testthat::expect_false(startup_observation(value, owner))
})

testthat::test_that("late artifact publication latches a failed clock witness", {
  state = new.env(parent = emptyenv())
  state$startup_started = 0
  state$summary = list(passed = TRUE, external_clock_ok = TRUE)
  emitted = new.env(parent = emptyenv())
  emitted$values = list()
  write = function(value, path) emitted$values[[basename(path)]] = value
  testthat::expect_error(startup_write(state$summary, "integration-summary.json", state,
    write = write, now = function() 61), "publication")
  testthat::expect_false(state$summary$passed)
  testthat::expect_false(emitted$values[["integration-summary.json"]]$external_clock_ok)
  testthat::expect_equal(emitted$values[["integration-summary.json"]]$external_elapsed_s, 61)
})

testthat::test_that("an original error keeps priority over the late publication failure", {
  run = function() {
    state = new.env(parent = emptyenv())
    output = tempfile("gptr-startup-pure-")
    on.exit(unlink(output, recursive = TRUE), add = TRUE)
    main = function(controller) {
      state$controller = controller
      controller$startup_started = 0
      controller$summary = list(passed = FALSE, external_clock_ok = FALSE)
      stop("controlled original error")
    }
    write = function(value, path) {
      startup_write(value, path, state$controller,
        write = function(value, path) NULL, now = function() 61)
    }
    testthat::expect_error(support$optional_controller_run(main, output, write),
      "controlled original error")
  }
  run()
})

testthat::test_that("primary conditions survive cleanup publication errors and interrupts", {
  primaries = list(simpleError("controlled primary error"),
    structure(list(message = "controlled primary interrupt", call = NULL),
      class = c("interrupt", "condition")))
  faults = list(simpleError("controlled cleanup error"),
    structure(list(message = "controlled cleanup interrupt", call = NULL),
      class = c("interrupt", "condition")))
  for (primary in primaries) for (fault in faults) {
    recorded = new.env(parent = emptyenv())
    recorded$reports = 0L
    report = function(publication_ok) {
      recorded$publication_ok = publication_ok
      recorded$reports = recorded$reports + 1L
      FALSE
    }
    observed = tryCatch(startup_finish(primary, function() stop(fault), report),
      error = identity, interrupt = identity)
    testthat::expect_identical(observed, primary)
    testthat::expect_identical(recorded$publication_ok, FALSE)
    testthat::expect_identical(recorded$reports, 1L)
  }
})

testthat::test_that("the reused controller finalizes interrupted mains without replacing them", {
  run = function(primary, fault) {
    output = tempfile("gptr-startup-precedence-")
    on.exit(unlink(output, recursive = TRUE), add = TRUE)
    emitted = new.env(parent = emptyenv())
    emitted$files = character()
    main = function(controller) {
      controller$summary = list(passed = FALSE)
      stop(primary)
    }
    write = function(value, path) {
      emitted$files = c(emitted$files, basename(path))
      stop(fault)
    }
    observed = tryCatch(support$optional_controller_run(main, output, write),
      error = identity, interrupt = identity)
    testthat::expect_identical(observed, primary)
    testthat::expect_gt(length(emitted$files), 0L)
    testthat::expect_identical(emitted$files[[1L]], "integration-summary.json")
  }
  conditions = list(simpleError("controlled precedence error"),
    structure(list(message = "controlled precedence interrupt", call = NULL),
      class = c("interrupt", "condition")))
  for (primary in conditions) for (fault in conditions) run(primary, fault)
})

testthat::test_that("journal identities reconstruct the current process with POSIXct time", {
  original = ps::ps_handle()
  expected_pid = ps::ps_pid(original)
  expected_time = as.numeric(ps::ps_create_time(original))
  journal = charToRaw(paste(owner, "1", "empty", expected_pid,
    sprintf("%.17g", expected_time), sep = "|"))
  decoded = startup_decode(journal, owner, 1L, TRUE)
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  seen$fresh_calls = 0L
  make = function(pid, time = NULL) {
    seen$calls = seen$calls + 1L
    if (is.null(time)) {
      seen$fresh_calls = seen$fresh_calls + 1L
      handle = ps::ps_handle(pid)
      seen$native_pid = ps::ps_pid(handle)
      seen$native_time = as.numeric(ps::ps_create_time(handle))
      return(handle)
    }
    seen$pid = pid
    seen$time = time
    if (!inherits(time, "POSIXct")) stop("Constructor requires a POSIXct timestamp")
    ps::ps_handle(pid, time)
  }
  testthat::expect_identical(startup_identity(decoded, make = make), "alive")
  testthat::expect_identical(seen$calls, 2L)
  testthat::expect_identical(seen$fresh_calls, 1L)
  testthat::expect_identical(seen$pid, expected_pid)
  testthat::expect_s3_class(seen$time, "POSIXct")
  testthat::expect_identical(as.numeric(seen$time), expected_time)
  testthat::expect_identical(attr(seen$time, "tzone"), "UTC")
  testthat::expect_identical(seen$native_pid, expected_pid)
  testthat::expect_identical(seen$native_time, expected_time)
})

testthat::test_that("live journals require exact fresh PID and time before signalling", {
  expected = startup_decode(identity_bytes, owner, 1L, TRUE)
  supplied = list(kind = "supplied")
  exact = list(kind = "fresh", pid = expected$pid, create_time = expected$create_time)
  near = expected$create_time + 2^-22
  testthat::expect_identical(near - expected$create_time, 2^-22)
  candidates = list(exact, list(kind = "fresh", pid = expected$pid, create_time = near),
    list(kind = "fresh", pid = expected$pid, create_time = expected$create_time + 0.005),
    list(kind = "fresh", pid = expected$pid + 1L, create_time = expected$create_time))
  testthat::expect_lt(abs(candidates[[3L]]$create_time - expected$create_time), 0.01)
  for (index in seq_along(candidates)) {
    state = new.env(parent = emptyenv())
    state$calls = list()
    state$running = list()
    state$signals = list()
    fresh = candidates[[index]]
    make = function(pid, time = NULL) {
      state$calls = c(state$calls, list(list(pid = pid, time = time)))
      if (is.null(time)) fresh else supplied
    }
    running = function(value) {
      state$running = c(state$running, list(value))
      TRUE
    }
    kill = function(value) state$signals = c(state$signals, list(value))
    observed = startup_identity(expected, make, running, kill,
      pid = function(value) value$pid, created = function(value) {
        as.POSIXct(value$create_time, origin = "1970-01-01", tz = "UTC")
      })
    testthat::expect_identical(observed, if (index == 1L) "alive" else "unknown")
    testthat::expect_length(state$calls, 2L)
    testthat::expect_identical(state$calls[[2L]], list(pid = expected$pid, time = NULL))
    testthat::expect_identical(state$signals, if (index == 1L) list(fresh) else list())
    testthat::expect_identical(state$running,
      if (index == 1L) list(supplied, fresh) else list(supplied))
  }
})

testthat::test_that("fresh identity construction queries and liveness fail closed", {
  expected = startup_decode(identity_bytes, owner, 1L, TRUE)
  supplied = list(kind = "supplied")
  fresh = list(kind = "fresh")
  faults = list(simpleError("controlled fresh error"),
    structure(list(message = "controlled fresh interrupt", call = NULL),
      class = c("interrupt", "condition")))
  for (stage in c("make", "pid", "created", "running")) for (fault in faults) {
    state = new.env(parent = emptyenv())
    state$signals = list()
    make = function(pid, time = NULL) {
      if (!is.null(time)) return(supplied)
      if (stage == "make") stop(fault)
      fresh
    }
    pid = function(value) {
      if (stage == "pid") stop(fault)
      expected$pid
    }
    created = function(value) {
      if (stage == "created") stop(fault)
      as.POSIXct(expected$create_time, origin = "1970-01-01", tz = "UTC")
    }
    running = function(value) {
      if (identical(value, fresh) && stage == "running") stop(fault)
      TRUE
    }
    kill = function(value) state$signals = c(state$signals, list(value))
    testthat::expect_identical(startup_identity(expected, make, running, kill, pid, created),
      "unknown")
    testthat::expect_length(state$signals, 0L)
  }
  for (stage in c("pid", "created", "running")) {
    state = new.env(parent = emptyenv())
    state$signals = list()
    make = function(pid, time = NULL) if (is.null(time)) fresh else supplied
    pid = function(value) if (stage == "pid") NA_integer_ else expected$pid
    created = function(value) {
      time = if (stage == "created") NA_real_ else expected$create_time
      as.POSIXct(time, origin = "1970-01-01", tz = "UTC")
    }
    running = function(value) if (identical(value, fresh) && stage == "running") NA else TRUE
    kill = function(value) state$signals = c(state$signals, list(value))
    testthat::expect_identical(startup_identity(expected, make, running, kill, pid, created),
      "unknown")
    testthat::expect_length(state$signals, 0L)
  }
})

testthat::test_that("fresh exact handles that die or are recycled never admit a signal", {
  expected = startup_decode(identity_bytes, owner, 1L, TRUE)
  supplied = list(kind = "supplied")
  fresh = list(kind = "fresh", raw_time = 17L)
  for (reason in c("dead", "recycled")) {
    state = new.env(parent = emptyenv())
    state$signals = list()
    state$queries = character()
    make = function(pid, time = NULL) if (is.null(time)) fresh else supplied
    pid = function(value) {
      state$queries = c(state$queries, "pid")
      expected$pid
    }
    created = function(value) {
      state$queries = c(state$queries, "time")
      as.POSIXct(expected$create_time, origin = "1970-01-01", tz = "UTC")
    }
    running = function(value) {
      if (identical(value, supplied)) return(TRUE)
      state$queries = c(state$queries, "native-running")
      if (reason == "dead") FALSE else identical(value$raw_time, 18L)
    }
    kill = function(value) state$signals = c(state$signals, list(value))
    testthat::expect_identical(startup_identity(expected, make, running, kill, pid, created),
      "dead-exact")
    testthat::expect_identical(state$queries, c("pid", "time", "native-running"))
    testthat::expect_length(state$signals, 0L)
  }
})
