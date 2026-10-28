# Clone the actual launcher and readiness check; replace only executable/process/clock leaves.
artifact_launch_fixture = function() {
  # On Linux the launch needs a short tempdir() for Chromium's socket; CRAN's may be longer.
  skip_on_cran()
  namespace = environment(artifact_browser)
  scope = new.env(parent = namespace)
  scope$artifact_state = new.env(parent = emptyenv())
  scope$artifact_state$browser_pending = NULL
  state = new.env(parent = emptyenv())
  state$alive = TRUE
  state$registered = TRUE
  state$release_ok = TRUE
  state$spawn_error = NULL
  state$signal_error = NULL
  state$clock = 0
  state$pump_result = TRUE
  state$pump_error = NULL
  state$pump_write = NULL
  state$pump_finished = 0
  state$calls = list()
  state$signals = integer()
  state$releases = 0L
  state$kills = 0L
  state$kill_ok = TRUE
  state$tree = list()
  state$record_changed = FALSE
  state$spawn_after_capture = FALSE
  state$spawn_hook = NULL
  state$roots = character()
  state$files = character()
  process = list(is_alive = function() state$alive, get_pid = function() 2468L,
    signal = function(signal) {
      if (!is.null(state$signal_error)) stop(state$signal_error)
      state$signals = c(state$signals, signal)
      invisible(TRUE)
    }, wait = function(timeout) {
      state$wait_timeout = timeout
      state$alive = FALSE
      invisible(TRUE)
    }, get_error_file = function() state$calls$stderr,
    get_output_file = function() state$calls$stdout)
  scope$find_chrome = function() "/synthetic/private/chrome"
  scope$child_env = function(profile, set = character()) {
    stopifnot(identical(profile, "artifact"))
    c(PATH = "/synthetic/bin", SAFE_SETTING = "fixture", set)
  }
  scope$supervise_default = function() TRUE
  scope$proc_marker_new = function() "GPTR_PROC_0123456789abcdef"
  state$jobs = new.env(parent = emptyenv())
  state$jobs$table = new.env(parent = emptyenv())
  state$jobs$order = character()
  scope$jobs_env = function() state$jobs
  for (name in c("job_add", "job_remove", "job_status", "job_frame", "job_list", "gptr_jobs",
                 "proc_wait_exit")) {
    fun = get(name, envir = namespace, inherits = FALSE)
    environment(fun) = scope
    assign(name, fun, envir = scope)
  }
  scope$proc_spawn = function(command, args, env, stdout, stderr, supervise, ...) {
    state$calls = list(command = command, args = args, env = env, stdout = stdout,
      stderr = stderr, supervise = supervise)
    profile = sub("^--user-data-dir=", "", args[startsWith(args, "--user-data-dir=")])
    stopifnot(length(profile) == 1L, endsWith(profile, "/profile"))
    state$roots = c(state$roots, substr(profile, 1L, nchar(profile) - nchar("/profile")))
    state$files = c(state$files, stdout, stderr)
    extra = list(...)
    stopifnot(identical(names(extra), c(".marker", ".on_spawn")),
      identical(extra[[".marker"]], "GPTR_PROC_0123456789abcdef"))
    if (is.function(state$spawn_hook)) state$spawn_hook()
    if (!is.null(state$spawn_error) && !state$spawn_after_capture) stop(state$spawn_error)
    extra[[".on_spawn"]](process)
    if (!is.null(state$spawn_error)) stop(state$spawn_error)
    process
  }
  scope$kill_all = function(p, grace) {
    stopifnot(identical(p, process), identical(grace, 0))
    state$kills = state$kills + 1L
    if (state$kill_ok) {
      state$alive = FALSE
      state$registered = FALSE
    }
    invisible(state$kill_ok)
  }
  scope$proc_release = function(p) {
    stopifnot(identical(p, process))
    state$releases = state$releases + 1L
    if (state$release_ok) state$registered = FALSE
    invisible(state$release_ok)
  }
  retained = process
  scope$proc_record = function(pid, process) {
    stopifnot(identical(pid, 2468L), identical(process, retained))
    if (state$registered) {
      list(pid = pid, create_time = if (state$record_changed) 1234.6 else 1234.5,
        marker = "GPTR_PROC_0123456789abcdef")
    } else {
      NULL
    }
  }
  scope$proc_tree = function(marker) {
    stopifnot(identical(marker, "GPTR_PROC_0123456789abcdef"))
    state$tree
  }
  scope$proc_children = function(p) {
    stopifnot(identical(p, process))
    list()
  }
  scope$proc.time = function() c(elapsed = state$clock)
  scope$reactor_pump = function(until, slice_ms, allow_runs, timeout) {
    stopifnot(identical(slice_ms, 50L), identical(allow_runs, character()),
      identical(timeout, 10))
    if (!is.null(state$pump_error)) stop(state$pump_error)
    if (!state$pump_result) {
      state$clock = state$clock + timeout
      return(invisible(FALSE))
    }
    admitted = until()
    if (!isTRUE(admitted) && !is.null(state$pump_write)) {
      writeLines(state$pump_write, state$calls$stderr, useBytes = TRUE)
      admitted = until()
    }
    state$clock = state$clock + state$pump_finished
    invisible(admitted)
  }
  launch = get("artifact_browser_launch", envir = namespace)
  ready = get("artifact_browser_ready", envir = namespace)
  replace_find = function(expr) {
    if (is.call(expr)) {
      if (identical(expr[[1L]], quote(chromote::find_chrome))) {
        expr[[1L]] = as.name("find_chrome")
      }
      for (i in seq_along(expr)) expr[i] = list(replace_find(expr[[i]]))
    }
    expr
  }
  body(launch) = replace_find(body(launch))
  environment(launch) = environment(ready) = scope
  withr::defer(unlink(c(state$roots, state$files), recursive = TRUE),
    envir = parent.frame())
  list(launch = launch, ready = ready, scope = scope, state = state, process = process)
}

test_that("artifact browser launch keeps fixed loopback and owned profile arguments", {
  x = artifact_launch_fixture()
  withr::local_options(chromote.headless = NULL)
  withr::local_envvar(CHROMOTE_HEADLESS = NA_character_)
  owner = x$launch(c("--mute-audio", "--use-mock-keychain"))
  call = x$state$calls
  root = x$state$roots[[1L]]
  expect_identical(call$command, "/synthetic/private/chrome")
  expect_identical(call$args, c("--headless", "--remote-debugging-port=0",
    paste0("--user-data-dir=", file.path(root, "profile")),
    paste0("--crash-dumps-dir=", file.path(root, "crashes")),
    "--mute-audio", "--use-mock-keychain"))
  expect_false(identical(dirname(call$stdout), root))
  expect_false(identical(dirname(call$stderr), root))
  expect_false(identical(call$stdout, call$stderr))
  expect_true(all(file.exists(c(call$stdout, call$stderr))))
  expect_true(dir.exists(file.path(root, "profile")))
  expect_true(dir.exists(file.path(root, "crashes")))
  expect_true(owner$is_local())
  expect_identical(owner$get_process(), x$process)
  expect_identical(owner$get_host(), "127.0.0.1")
  expect_identical(owner$get_port(), NA_integer_)
  withr::local_options(chromote.headless = "new")
  expect_identical(x$launch(character())$get_port(), NA_integer_)
  expect_identical(x$state$calls$args[[1L]], "--headless=new")
})

test_that("artifact browser launch uses artifact filtering and check-aware supervision", {
  local_vault()
  x = artifact_launch_fixture()
  synthetic = c(PATH = "/synthetic/bin", SAFE_SETTING = "fixture",
    OPENAI_API_KEY = "FAKE_BROWSER_KEY_123456", R_ENVIRON = "/synthetic/site.Renviron",
    ORDINARY_VALUE = "prefix FAKE_BROWSER_REGISTERED_123456 suffix")
  secret_register("FAKE_BROWSER_REGISTERED_123456", "TEST_BROWSER_KEY", "test")
  filtered = child_env
  environment(filtered) = list2env(list(Sys.getenv = function(...) synthetic),
    parent = environment(filtered))
  x$scope$child_env = filtered
  x$scope$supervise_default = supervise_default
  withr::local_options(gptr.supervise = NULL)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  x$launch(character())
  env = x$state$calls$env
  expect_false(x$state$calls$supervise)
  expect_identical(env[["SAFE_SETTING"]], "fixture")
  expect_false(any(c("OPENAI_API_KEY", "R_ENVIRON", "ORDINARY_VALUE") %in% names(env)))
  expect_identical(file.size(env[["R_ENVIRON_USER"]]), 0)
  expect_identical(file.size(env[["R_PROFILE_USER"]]), 0)
  withr::local_options(gptr.supervise = TRUE)
  x$launch(character())
  expect_true(x$state$calls$supervise)
  withr::local_options(gptr.supervise = NULL)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = NA_character_, NOT_CRAN = "true")
  x$launch(character())
  expect_true(x$state$calls$supervise)
})

test_that("artifact browser rejects ownership-changing Chrome arguments before spawning", {
  x = artifact_launch_fixture()
  for (arg in c("--headless=new", "--remote-debugging-port=9",
                "--remote-debugging-address=0.0.0.0", "--remote-debugging-pipe",
                "--remote-allow-origins=*", "--user-data-dir=/synthetic/foreign",
                "--crash-dumps-dir=/synthetic/foreign")) {
    expect_error(x$launch(arg), class = "gptr_error_invalid_argument")
    expect_identical(x$state$calls, list())
  }
})

test_that("artifact browser readiness requires its exact live endpoint within the startup budget", {
  for (kind in c("ready", "partial", "port_max", "port_zero", "port_range", "wrong_host",
                "duplicate", "oversize", "dead", "unknown", "timeout", "late")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    line = "DevTools listening on ws://127.0.0.1:54321/devtools/browser/fixed-id"
    if (kind == "port_max") line = sub("54321", "65535", line, fixed = TRUE)
    if (kind == "port_zero") line = sub("54321", "0", line, fixed = TRUE)
    if (kind == "port_range") line = sub("54321", "65536", line, fixed = TRUE)
    if (kind == "wrong_host") line = sub("127.0.0.1", "0.0.0.0", line, fixed = TRUE)
    if (kind == "duplicate") line = c(line, line)
    if (kind == "oversize") line = strrep("x", 1048577L)
    writeLines(line, x$state$calls$stderr, useBytes = TRUE)
    if (kind == "partial") {
      writeChar("DevTools listening on ws://127.0.0.1:", x$state$calls$stderr,
        eos = NULL, useBytes = TRUE)
      x$state$pump_write = line
    }
    if (kind == "dead") x$state$alive = FALSE
    if (kind == "unknown") x$state$alive = NA
    if (kind == "timeout") x$state$pump_result = FALSE
    if (kind == "late") x$state$pump_finished = 10.01
    if (kind %in% c("ready", "partial", "port_max")) {
      expect_true(x$ready(owner))
      expect_identical(owner$get_port(), if (kind == "port_max") 65535L else 54321L)
    } else {
      expect_error(x$ready(owner), class = "gptr_error_io")
      expect_identical(owner$get_port(), NA_integer_)
    }
    expect_identical(x$state$signals, integer())
    expect_identical(x$state$releases, 0L)
  }
})

test_that("artifact browser startup unwind preserves its original condition and exact owner", {
  for (kind in c("error", "interrupt")) {
    for (cleanup_fails in c(FALSE, TRUE)) {
      x = artifact_owner_fixture()
      x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
      original = structure(list(message = "controlled startup readiness", call = NULL),
        class = c(paste0("controlled_", kind), kind, "condition"))
      x$scope$artifact_browser_ready = function(owner) {
        stopifnot(identical(owner, x$owner))
        stop(original)
      }
      if (cleanup_fails) x$state$wait_error = simpleError("controlled cleanup wait")
      seen = tryCatch(x$open(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(x$state$container_calls, 0L)
      expect_identical(x$state$events, c("process", "wait"))
      expect_null(x$scope$artifact_state$browser)
      if (cleanup_fails) {
        expect_identical(x$scope$artifact_state$browser_pending,
          list(browser = NULL, owner = x$owner))
      } else {
        expect_null(x$scope$artifact_state$browser_pending)
        expect_null(x$scope$artifact_state$browser_owner)
      }
    }
  }
})

test_that("artifact browser marked owner releases only its exact dead settled family", {
  x = artifact_launch_fixture()
  owner = x$launch(character())
  expect_error(owner$release(), class = "gptr_error_io")
  expect_identical(x$state$releases, 0L)
  x$state$alive = NA
  expect_error(owner$close(), class = "gptr_error_io")
  expect_identical(x$state$signals, integer())
  x$state$alive = TRUE
  expect_invisible(owner$close(wait = FALSE))
  expect_identical(x$state$signals, tools::SIGTERM)
  expect_identical(owner$get_process(), x$process)
  x$state$alive = FALSE
  x$state$release_ok = FALSE
  expect_error(owner$release(), class = "gptr_error_io")
  expect_true(x$state$registered)
  x$state$release_ok = TRUE
  x$state$record_changed = TRUE
  expect_error(owner$release(), class = "gptr_error_io")
  expect_true(x$state$registered)
  x$state$record_changed = FALSE
  x$state$registered = FALSE
  for (tree in list(list(survivor = TRUE), structure(list(), unavailable = TRUE))) {
    x$state$tree = tree
    expect_error(owner$release(), class = "gptr_error_io")
    expect_true(dir.exists(x$state$roots[[1L]]))
  }
  x$state$tree = list()
  expect_invisible(owner$release())
  expect_false(x$state$registered)
  expect_false(dir.exists(x$state$roots[[1L]]))
  expect_true(file.exists(x$state$calls$stderr))
  expect_true(file.exists(x$state$calls$stdout))
})

test_that("artifact browser spawn refusal preserves its condition without a foreign signal", {
  namespace = environment(artifact_browser)
  empty_scope = new.env(parent = namespace)
  calendar = new.env(parent = emptyenv())
  calendar$calls = 0L
  empty_scope$as.POSIXct = function(...) {
    calendar$calls = calendar$calls + 1L
    stop("The empty job table must not invoke calendar conversion.")
  }
  empty_frame = get("job_frame", envir = namespace, inherits = FALSE)
  environment(empty_frame) = empty_scope
  env_before = Sys.getenv()
  kind_before = RNGkind()
  seed_before = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  empty = tryCatch(empty_frame(list()), error = identity, interrupt = identity)
  expected = data.frame(id = character(), kind = character(), name = character(),
    pid = integer(), status = character(),
    started = structure(numeric(), class = c("POSIXct", "POSIXt"), tzone = "UTC"),
    stringsAsFactors = FALSE)
  expect(identical(empty, expected), "The empty job table preserves every column and attribute.")
  expect(identical(calendar$calls, 0L), "The empty job table does not convert a calendar value.")
  expect(identical(Sys.getenv(), env_before), "The empty job table preserves the environment.")
  expect(identical(RNGkind(), kind_before) && identical(
    get0(".Random.seed", envir = globalenv(), inherits = FALSE), seed_before),
    "The empty job table preserves the RNG kind and seed.")
  for (kind in c("error", "interrupt")) {
    x = artifact_launch_fixture()
    original = structure(list(message = "controlled browser spawn", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$spawn_error = original
    seen = tryCatch(x$launch(character()), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$state$signals, integer())
    expect_identical(x$state$releases, 0L)
    expect_identical(x$state$kills, 0L)
    expect_true(all(file.exists(c(x$state$calls$stdout, x$state$calls$stderr))))
    for (settles in c(FALSE, TRUE)) {
      x = artifact_launch_fixture()
      x$state$spawn_error = original
      x$state$spawn_after_capture = TRUE
      x$state$kill_ok = settles
      seen = tryCatch(x$launch(character()), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(x$state$kills, 1L)
      expect_identical(x$state$alive, !settles)
      expect_identical(x$state$signals, integer())
      if (settles) {
        expect_null(x$scope$artifact_state$browser_pending)
        expect_false(dir.exists(x$state$roots[[1L]]))
      } else {
        lease = x$scope$artifact_state$browser_pending
        expect_null(lease$browser)
        expect_identical(lease$owner$get_process(), x$process)
        expect_true(dir.exists(x$state$roots[[1L]]))
      }
      expect_true(all(file.exists(c(x$state$calls$stdout, x$state$calls$stderr))))
    }
    x = artifact_launch_fixture()
    x$state$registered = FALSE
    x$state$kill_ok = FALSE
    expect_error(x$launch(character()), class = "gptr_error_io")
    lease = x$scope$artifact_state$browser_pending
    expect_identical(lease$owner$get_process(), x$process)
    expect_true(x$state$alive)
    x$state$alive = FALSE
    x$state$tree = structure(list(), unavailable = TRUE)
    expect_error(lease$owner$release(), class = "gptr_error_io")
    expect_true(dir.exists(x$state$roots[[1L]]))
    x$state$tree = list()
    expect_invisible(lease$owner$release())
    expect_false(dir.exists(x$state$roots[[1L]]))
    x = artifact_launch_fixture()
    foreign = list(browser = list(foreign = TRUE), owner = list(foreign = TRUE))
    x$state$spawn_error = original
    x$state$spawn_after_capture = TRUE
    x$state$registered = FALSE
    x$state$kill_ok = FALSE
    x$state$spawn_hook = function() {
      signalCondition(structure(list(message = "", call = NULL),
        class = c("gptr_process_spawn", "condition")))
    }
    seen = tryCatch(withCallingHandlers(x$launch(character()),
      gptr_process_spawn = function(condition) {
        reserved = x$scope$artifact_state$browser_pending
        expect_null(reserved$browser)
        expect_true(reserved$owner$is_local())
        expect_null(reserved$owner$get_process())
        x$scope$artifact_state$browser_pending = foreign
      }), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$scope$artifact_state$browser_pending, foreign)
    expect_true(x$state$alive)
    expect_identical(x$state$kills, 1L)
    jobs = x$scope$gptr_jobs()
    marker = "GPTR_PROC_0123456789abcdef"
    expect_identical(jobs$id, marker)
    expect_identical(jobs$name, "headless-browser-cleanup")
    expect_identical(jobs$kind, "artifact")
    expect_identical(jobs$pid, 2468L)
    expect_identical(jobs$status, "running")
    expect_error(x$state$jobs$table[[marker]]$stop(), class = "gptr_error_io")
    expect_identical(x$state$jobs$order, marker)
    expect_identical(x$scope$artifact_state$browser_pending, foreign)
    x$state$alive = NA
    expect_identical(x$scope$gptr_jobs()$status, "unknown")
    x$state$alive = FALSE
    x$state$kill_ok = TRUE
    x$state$tree = structure(list(), unavailable = TRUE)
    expect_error(x$state$jobs$table[[marker]]$stop(), class = "gptr_error_io")
    expect_identical(x$state$jobs$order, marker)
    expect_true(dir.exists(x$state$roots[[1L]]))
    x$state$tree = list()
    stopped = x$scope$gptr_jobs(kill = TRUE)
    expect_identical(stopped$id, marker)
    expect_identical(stopped$status, "stopped")
    expect_identical(x$state$jobs$order, character())
    expect_false(dir.exists(x$state$roots[[1L]]))
    expect_identical(x$scope$artifact_state$browser_pending, foreign)
    expect_identical(x$state$signals, integer())
    expect_true(all(file.exists(c(x$state$calls$stdout, x$state$calls$stderr))))
    expect_identical(nrow(x$scope$gptr_jobs(kill = TRUE)), 0L)
    expect_identical(x$scope$artifact_state$browser_pending, foreign)
  }
})

test_that("artifact browser release settles only its exact retained stopped family", {
  for (mode in c("settled", "unconfirmed", "changed", "refused")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    record = x$scope$proc_record(2468L, x$process)
    x$state$alive = FALSE
    x$state$family_calls = 0L
    x$scope$proc_release = function(process) {
      expect_identical(process, x$process)
      if (mode == "changed") x$state$record_changed = TRUE
      invisible(mode != "refused")
    }
    x$scope$proc_cleanup_record = function(retained) {
      expect_identical(retained, record)
      expect_false(x$state$alive)
      x$state$family_calls = x$state$family_calls + 1L
      if (mode == "settled") x$state$registered = FALSE
      list(killed = 0L, complete = mode == "settled")
    }
    outcome = tryCatch(owner$release(), error = identity)
    if (mode == "settled") {
      expect_null(outcome)
      expect_null(x$scope$proc_record(2468L, x$process))
      expect_false(dir.exists(x$state$roots[[1L]]))
    } else {
      expect_s3_class(outcome, "gptr_error_io")
      expect_true(x$state$registered)
      expect_true(dir.exists(x$state$roots[[1L]]))
    }
    expect_identical(x$state$family_calls,
      if (mode %in% c("settled", "unconfirmed")) 1L else 0L)
    expect_identical(x$state$signals, integer())
    expect_true(all(file.exists(x$state$files)))
  }
})

test_that("artifact browser directory failure reports its stage and retains retry ownership", {
  for (mode in c("link-shape", "link-target", "unlink", "remaining")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    root = x$state$roots[[1L]]
    x$state$alive = FALSE
    x$state$unlink_calls = 0L
    if (mode == "link-shape") x$scope$Sys.readlink = function(path) character()
    if (mode == "link-target") x$scope$Sys.readlink = function(path) "controlled-foreign-target"
    x$scope$unlink = function(path, recursive) {
      expect_identical(path, root)
      expect_true(recursive)
      x$state$unlink_calls = x$state$unlink_calls + 1L
      if (mode == "unlink") 1L else 0L
    }
    seen = tryCatch(owner$release(), error = identity)
    expect_s3_class(seen, "gptr_error_io")
    expect_identical(seen$operation, "close")
    expect_identical(seen$path, root)
    expect_identical(seen$cleanup_stage,
      if (startsWith(mode, "link")) "link" else mode)
    expect_identical(x$state$unlink_calls, if (startsWith(mode, "link")) 0L else 1L)
    if (mode == "unlink") expect_identical(seen$unlink_status, 1L)
    expect_true(dir.exists(root))
    expect_identical(owner$get_process(), x$process)
    expect_identical(x$state$signals, integer())
    expect_true(all(file.exists(x$state$files)))
    x$scope$Sys.readlink = base::Sys.readlink
    x$scope$unlink = base::unlink
    expect_invisible(owner$release())
    expect_false(dir.exists(root))
    expect_true(all(file.exists(x$state$files)))
  }
})

test_that("artifact browser close waits for its unmarked helpers before removing the profile", {
  # A helper exits by itself, or only when killed after the 2 s grace (FIX-35), or never.
  for (mode in c("exits", "killed", "survives")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    root = x$state$roots[[1L]]
    x$state$exits = if (mode == "exits") 0.5 else Inf
    x$state$dead_at = numeric()
    x$state$unlinked_at = numeric()
    x$state$killed_at = numeric()
    x$scope$proc_kill_signalled = function(handles) {
      expect_identical(handles, list("network-service"))
      x$state$killed_at = c(x$state$killed_at, x$state$clock)
      if (mode == "killed") x$state$exits = x$state$clock
      handles
    }
    # The marker misses Chrome's helpers, so only their parent link records them.
    x$scope$proc_children = function(p) {
      expect_identical(p, x$process)
      expect_identical(x$state$signals, integer())
      list("network-service")
    }
    x$scope$proc_handle_alive = function(handle) {
      stopifnot(identical(handle, "network-service"))
      alive = x$state$clock < x$state$exits
      if (!alive && !length(x$state$dead_at)) x$state$dead_at = x$state$clock
      alive
    }
    x$scope$Sys.sleep = function(seconds) {
      stopifnot(seconds > 0, seconds <= 0.02)
      x$state$clock = x$state$clock + seconds
    }
    x$scope$unlink = function(path, recursive) {
      x$state$unlinked_at = c(x$state$unlinked_at, x$state$clock)
      # A helper writing in the profile during the walk makes R's unlink return 1.
      if (x$state$clock < x$state$exits) 1L else base::unlink(path, recursive = recursive)
    }
    close = get("artifact_browser_close", envir = environment(artifact_browser))
    environment(close) = x$scope
    seen = tryCatch(close(b = NULL, owner = owner, cached = FALSE), error = identity)
    expect_identical(x$state$signals, tools::SIGTERM)
    expect_false(x$state$alive)
    if (mode == "exits") {
      expect_true(x$state$dead_at >= 0.5)
      expect_identical(x$state$killed_at, numeric())
    } else {
      # The grace ends 2 s into the wait, at most one 20 ms poll late.
      expect_length(x$state$killed_at, 1L)
      expect_true(x$state$killed_at >= 2 && x$state$killed_at <= 2.02)
    }
    if (mode != "survives") {
      expect_null(seen)
      expect_identical(x$state$unlinked_at, x$state$dead_at)
      expect_false(dir.exists(root))
      if (mode == "killed") expect_identical(x$state$dead_at, x$state$killed_at)
    } else {
      expect_s3_class(seen, "gptr_error_io")
      expect_match(conditionMessage(seen), "family did not finish cleanup", fixed = TRUE)
      # The wait ends at the close deadline, at most one 20 ms poll late.
      expect_true(x$state$clock >= 10 && x$state$clock <= 10.02)
      expect_identical(x$state$unlinked_at, numeric())
      expect_true(dir.exists(root))
      expect_identical(owner$get_process(), x$process)
      x$state$exits = x$state$clock
      expect_invisible(owner$release())
      expect_identical(x$state$unlinked_at, x$state$exits)
      expect_false(dir.exists(root))
    }
    expect_true(all(file.exists(x$state$files)))
  }
})

test_that("a recorded helper that cannot run is killed after the grace, in the deadline (FIX-35)", {
  # Under load the scheduler starved an orphaned Chrome renderer past the close deadline. A
  # stopped child stands in for it: SIGTERM stays pending, so only the kill ends it.
  x = artifact_launch_fixture()
  x$scope$proc.time = base::proc.time
  helper = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
    env = c("current", R_TESTS = ""), cleanup = TRUE)
  withr::defer(helper$kill())
  handle = ps::ps_handle(helper$get_pid())
  ps::ps_suspend(handle)
  owner = x$launch(character())
  root = x$state$roots[[1L]]
  x$scope$proc_children = function(p) list(handle)
  close = get("artifact_browser_close", envir = environment(artifact_browser))
  environment(close) = x$scope
  started = proc.time()[["elapsed"]]
  seen = tryCatch(close(b = NULL, owner = owner, cached = FALSE), error = identity)
  elapsed = proc.time()[["elapsed"]] - started
  expect_null(seen)
  expect_false(helper$is_alive())
  expect_true(elapsed >= 2 && elapsed < 10)
  expect_false(dir.exists(root))
})

artifact_launch_temp = function(x) {
  path = unname(x$state$calls$env["TMPDIR"])
  expect_true(length(path) == 1L && !is.na(path) && nzchar(path))
  if (length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("The owned Chrome temporary directory was not forwarded.")
  }
  path
}

test_that("artifact launch gives only its child a separate private temporary directory", {
  x = artifact_launch_fixture()
  before = Sys.getenv()
  owners = list(x$launch(character()), x$launch(character()))
  expect_true(all(vapply(owners, function(owner) owner$is_local(), logical(1))))
  temp = artifact_launch_temp(x)
  keys = c("TMPDIR", "TMP", "TEMP", "MAC_CHROMIUM_TMPDIR")
  expect_identical(unname(x$state$calls$env[keys]), rep(temp, 4L))
  expect_identical(temp, file.path(x$state$roots[[2L]], "tmp"))
  expect_true(dir.exists(temp))
  expect_false(identical(x$state$roots[[1L]], x$state$roots[[2L]]))
  parent = normalizePath(dirname(x$state$roots), winslash = "/", mustWork = TRUE)
  expect_identical(parent,
    rep(normalizePath(tempdir(), winslash = "/", mustWork = TRUE), 2L))
  if (!is_windows()) {
    expect_identical(bitwAnd(as.integer(file.info(temp)$mode), 511L), 448L)
    socket = file.path(temp, "org.chromium.Chromium.XXXXXX", "SingletonSocket")
    expect_lte(nchar(socket, type = "bytes"), if (is_macos()) 253L else 107L)
  }
  expect_identical(Sys.getenv(), before)
  expect_true(all(file.exists(x$state$files)))
  expect_false(dirname(x$state$calls$stderr) %in% x$state$roots)
})

test_that("artifact launch enforces Linux and macOS socket path limits before spawning", {
  for (mac in c(FALSE, TRUE)) {
    limit = if (mac) 253L else 107L
    for (path_case in c("check", "boundary", "overlong")) {
      x = artifact_launch_fixture()
      x$scope$is_windows = function() FALSE
      x$scope$is_macos = function() mac
      suffix = nchar(file.path("tmp", "org.chromium.Chromium.XXXXXX", "SingletonSocket"),
        type = "bytes") + 1L
      # R CMD check used this 38-byte startup parent and a 12-byte nonce on Linux.
      parent = "/tmp/RtmpoAySAX/working_dir/RtmpxBVU2J"
      root = if (path_case == "check") {
        expect_identical(nchar(parent, type = "bytes"), 38L)
        file.path(parent, paste0("gptr-", strrep("x", 12L)))
      } else {
        paste0("/virtual-browser-",
          strrep("x", limit + as.integer(path_case == "overlong") - suffix - 17L))
      }
      expect_identical(nchar(file.path(root, "tmp", "org.chromium.Chromium.XXXXXX",
        "SingletonSocket"), type = "bytes"),
        if (path_case == "check") 105L else limit + as.integer(path_case == "overlong"))
      x$scope$tempfile = function(pattern, ...) {
        if (identical(pattern, "gptr-")) root else base::tempfile(pattern, ...)
      }
      x$scope$dir.create = function(path, mode) {
        expect_true(path %in% c(root, file.path(root, c("profile", "crashes", "tmp"))))
        expect_identical(mode, "0700")
        TRUE
      }
      spawn = x$scope$proc_spawn
      x$state$virtual_spawns = 0L
      x$scope$proc_spawn = function(...) {
        process = spawn(...)
        x$state$virtual_spawns = x$state$virtual_spawns + 1L
        x$state$roots = character() # Virtual paths are never created or passed to real unlink.
        process
      }
      if (path_case != "overlong") {
        expect_true(x$launch(character())$is_local())
        expect_identical(x$state$virtual_spawns, 1L)
      } else {
        expect_error(x$launch(character()), "Restart R with a shorter TMPDIR",
          class = "gptr_error_io")
        expect_identical(x$state$calls, list())
        expect_identical(x$state$virtual_spawns, 0L)
      }
      expect_false(file.exists(root))
    }
  }
})

test_that("a dead settled browser removes a real owned POSIX SingletonSocket only", {
  skip_on_os("windows")
  python = Sys.getenv("RETICULATE_PYTHON", unset = unname(Sys.which("python3")))
  skip_if(!nzchar(python) || !file.exists(python), "a provisioned Python is unavailable")
  x = artifact_launch_fixture()
  owner = x$launch(character())
  temp = artifact_launch_temp(x)
  child = file.path(temp, "controlled-child")
  expect_true(dir.create(child, mode = "0700"))
  socket = file.path(child, "SingletonSocket")
  withr::defer(if (file.exists(socket)) file.remove(socket))
  before = getwd()
  code = paste("import os,socket,stat,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);",
    "os.chdir(os.path.dirname(sys.argv[1])); s.bind('SingletonSocket'); s.close();",
    "assert stat.S_ISSOCK(os.lstat(sys.argv[1]).st_mode);",
    "print('GPTR_OWNED_POSIX_SOCKET_CREATED')")
  answer = system2(python, c("-I", "-c", shQuote(code), shQuote(socket)),
    stdout = TRUE, stderr = TRUE, timeout = 5)
  expect_identical(answer, "GPTR_OWNED_POSIX_SOCKET_CREATED")
  expect_identical(getwd(), before)
  expect_true(file.exists(socket))
  outside = withr::local_tempfile()
  expect_true(file.create(outside))
  x$state$alive = FALSE
  expect_invisible(owner$release())
  expect_false(file.exists(x$state$roots[[1L]]))
  expect_true(file.exists(outside))
  expect_true(all(file.exists(x$state$files)))
  expect_identical(x$state$signals, integer())
})

test_that("owned socket cleanup refuses linked or unobserved ancestors without outside removal", {
  skip_on_os("windows")
  for (stage in c("temp", "child", "socket", "unknown")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    temp = artifact_launch_temp(x)
    child = file.path(temp, "controlled-child")
    expect_true(dir.create(child))
    socket = file.path(child, "SingletonSocket")
    outside = withr::local_tempdir()
    keep = file.path(outside, "SingletonSocket")
    expect_true(file.create(keep))
    path = switch(stage, temp = temp, child = child, socket = socket, unknown = child)
    if (stage == "unknown") {
      x$scope$Sys.readlink = function(value) {
        result = base::Sys.readlink(value)
        result[value == path] = NA_character_
        result
      }
    } else {
      unlink(path, recursive = TRUE)
      expect_true(file.symlink(if (stage == "socket") keep else outside, path))
    }
    x$state$remove_calls = 0L
    x$scope$file.remove = function(value) {
      x$state$remove_calls = x$state$remove_calls + 1L
      stop("A linked or unknown ancestor must not reach file.remove.")
    }
    x$state$alive = FALSE
    expect_error(owner$release(), class = "gptr_error_io")
    expect_identical(x$state$remove_calls, 0L)
    expect_true(file.exists(keep))
    expect_true(dir.exists(x$state$roots[[1L]]))
    expect_identical(owner$get_process(), x$process)
    expect_true(all(file.exists(x$state$files)))
    x$scope$Sys.readlink = base::Sys.readlink
    x$scope$file.remove = base::file.remove
    if (stage != "unknown") expect_true(file.remove(path))
    expect_invisible(owner$release())
    expect_true(file.exists(keep))
  }
})

test_that("socket removal preserves failure conditions and requires exact dead settled ownership", {
  skip_on_os("windows")
  x = artifact_launch_fixture()
  owner = x$launch(character())
  child = file.path(artifact_launch_temp(x), "controlled-child")
  expect_true(dir.create(child))
  socket = file.path(child, "SingletonSocket")
  expect_true(file.create(socket))
  for (kind in c("refused", "error", "interrupt")) {
    original = structure(list(message = "controlled socket removal", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$scope$file.remove = function(path) {
      expect_identical(path, socket)
      if (kind == "refused") FALSE else stop(original)
    }
    x$state$alive = FALSE
    seen = tryCatch(owner$release(), error = identity, interrupt = identity)
    if (kind == "refused") expect_s3_class(seen, "gptr_error_io") else
      expect_identical(seen, original)
    expect_true(file.exists(socket))
    expect_true(dir.exists(x$state$roots[[1L]]))
    expect_true(all(file.exists(x$state$files)))
  }
  x$scope$file.remove = function(path) stop("Unsettled ownership must not remove a socket.")
  for (alive in list(TRUE, NA, NULL, 0)) {
    x$state$alive = alive
    expect_error(owner$release(), class = "gptr_error_io")
    expect_true(file.exists(socket))
  }
  x$state$alive = FALSE
  for (tree in list(list(survivor = TRUE), structure(list(), unavailable = TRUE))) {
    x$state$tree = tree
    expect_error(owner$release(), class = "gptr_error_io")
    expect_true(file.exists(socket))
  }
  borrowed = artifact_owner_fixture(remote = TRUE)
  borrowed$scope$file.remove = x$scope$file.remove
  borrowed$scope$unlink = function(...) stop("A borrowed browser must not remove a tree.")
  expect_invisible(borrowed$close())
  expect_true(borrowed$state$alive)
  expect_identical(borrowed$state$events, "websocket")
  expect_true(file.exists(socket))
  x$state$tree = list()
  x$scope$file.remove = base::file.remove
  expect_invisible(owner$release())
  expect_false(file.exists(socket))
  expect_true(all(file.exists(x$state$files)))
})
