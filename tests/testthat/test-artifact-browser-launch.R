# Clone the actual launcher and readiness check; replace only executable/process/clock leaves.
artifact_launch_fixture = function() {
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
  scope$port_candidates = function(n) {
    stopifnot(identical(n, 1L))
    54321L
  }
  scope$child_env = function(profile) {
    stopifnot(identical(profile, "artifact"))
    c(PATH = "/synthetic/bin", SAFE_SETTING = "fixture")
  }
  scope$supervise_default = function() TRUE
  scope$proc_marker_new = function() "GPTR_PROC_0123456789abcdef"
  state$jobs = new.env(parent = emptyenv())
  state$jobs$table = new.env(parent = emptyenv())
  state$jobs$order = character()
  scope$jobs_env = function() state$jobs
  for (name in c("job_add", "job_remove", "job_status", "job_frame", "job_list", "gptr_jobs")) {
    fun = get(name, envir = namespace, inherits = FALSE)
    environment(fun) = scope
    assign(name, fun, envir = scope)
  }
  scope$proc_spawn = function(command, args, env, stdout, stderr, supervise, ...) {
    state$calls = list(command = command, args = args, env = env, stdout = stdout,
      stderr = stderr, supervise = supervise)
    profile = sub("^--user-data-dir=", "", args[startsWith(args, "--user-data-dir=")])
    state$roots = c(state$roots, dirname(profile))
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
  expect_identical(call$args, c("--headless", "--remote-debugging-port=54321",
    "--remote-allow-origins=http://127.0.0.1:54321",
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
  expect_identical(owner$get_port(), 54321L)
  withr::local_options(chromote.headless = "new")
  expect_identical(x$launch(character())$get_port(), 54321L)
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
  for (kind in c("ready", "partial", "wrong_port", "wrong_host", "duplicate", "oversize",
                "dead", "unknown", "timeout", "late")) {
    x = artifact_launch_fixture()
    owner = x$launch(character())
    line = "DevTools listening on ws://127.0.0.1:54321/devtools/browser/fixed-id"
    if (kind == "wrong_port") line = sub("54321", "54322", line, fixed = TRUE)
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
    if (kind %in% c("ready", "partial")) {
      expect_true(x$ready(owner))
    } else {
      expect_error(x$ready(owner), class = "gptr_error_io")
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
