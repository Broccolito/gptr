# Fixed installed worker entrypoint and owned cleanup; no real child is launched here.

worker_launch_state = function() {
  st = new.env(parent = emptyenv())
  st$spec = list(depth = 1L, name = "launch-test", object_names = "d",
                 settings = list(project_root = tempdir()), key_provider = NULL)
  st$home = new.env(parent = emptyenv())
  st$home$d = c(1, 2, 3)
  st$home$unshipped = "p19-unshipped-launch-canary"
  st$provider = "fake"
  st$model_id = "fake-1"
  st$request_id = "worker-launch-test"
  st$stderr = character()
  st$opts = list(signal = new.env(parent = emptyenv()))
  st
}

test_that("worker launch passes a complete child environment and keeps one owned handle", {
  st = worker_launch_state()
  seen = new.env(parent = emptyenv())
  p = list(get_pid = function() 123L)
  env = c(EMPTY = "", GPTR_WORKER = "1")
  local_mocked_bindings(
    child_env = function(profile, set, provider) {
      seen$profile = profile
      seen$set = set
      seen$provider = provider
      env
    },
    proc_mark = function(...) stop("the worker marked its process twice"),
    proc_rscript = function(entry, args, dir, env, stdin, .marker, .on_spawn) {
      seen$launch = list(entry = entry, args = args, dir = dir, env = env, stdin = stdin,
                          marker = .marker)
      .on_spawn(p)
      p
    },
    reactor_proc = function(proc, ...) {
      seen$watched = proc
      "worker-watch"
    },
    reactor_task = function(...) "worker-task",
    job_add = function(kind, id, name, pid, stop) {
      seen$job = list(kind = kind, pid = pid)
    })
  withr::defer(unlink(st$dir, recursive = TRUE))
  expect_identical(worker_spawn(st), st)
  expect_identical(st$p, p)
  expect_identical(seen$watched, p)
  expect_identical(seen$profile, "worker")
  expect_null(seen$provider)
  expect_identical(seen$launch$entry, "worker")
  expect_true(all(vapply(seen$launch$args, is.character, logical(1))))
  expect_length(grepRaw("srcfile", serialize(seen$launch$args, NULL), fixed = TRUE), 0L)
  expect_identical(seen$launch$env, env)
  expect_false(anyNA(seen$launch$env))
  expect_identical(seen$launch$stdin, "|")
  expect_identical(seen$launch$dir, st$dir)
  expect_false(seen$launch$marker %in% names(seen$set))
  expect_identical(seen$job, list(kind = "worker", pid = 123L))
  spec = readRDS(seen$launch$args[[1L]], refhook = worker_refhook)
  expect_identical(spec$objects, list(d = c(1, 2, 3)))
  expect_length(grepRaw("p19-unshipped-launch-canary",
                        readBin(seen$launch$args[[1L]], "raw", file.size(seen$launch$args[[1L]])),
                        fixed = TRUE), 0L)
})

test_that("worker launch failure retains the native handle and its original condition", {
  st = worker_launch_state()
  seen = new.env(parent = emptyenv())
  p = list(get_pid = function() 124L)
  original = structure(list(message = "registration failed", call = NULL),
                       class = c("worker_launch_failure", "error", "condition"))
  local_mocked_bindings(
    child_env = function(...) character(),
    proc_rscript = function(..., .on_spawn) {
      .on_spawn(p)
      stop(original)
    },
    kill_all = function(proc, grace) {
      seen$killed = proc
      FALSE
    })
  withr::defer(unlink(st$dir, recursive = TRUE))
  error = tryCatch(worker_spawn(st), error = identity)
  expect_identical(error, original)
  expect_identical(st$p, p)
  expect_identical(seen$killed, p)
  expect_true(dir.exists(st$dir))
  expect_true(file.exists(st$result_path |> dirname() |> file.path("spec.rds")))
  expect_true(st$stopped)
  expect_identical(st$final[[1L]]$reason, "aborted")
})

test_that("watcher or job registration failure settles before deleting the worker payload", {
  for (stage in c("watch", "job")) {
    st = worker_launch_state()
    seen = new.env(parent = emptyenv())
    p = list(get_pid = function() 125L)
    original = structure(list(message = stage, call = NULL),
                         class = c("worker_registration_failure", "error", "condition"))
    local_mocked_bindings(
      child_env = function(...) character(),
      proc_rscript = function(..., .on_spawn) {
        .on_spawn(p)
        p
      },
      reactor_proc = function(...) {
        if (stage == "watch") stop(original)
        "owned-watch"
      },
      job_add = function(...) stop(original),
      reactor_cancel = function(id) {
        seen$cancelled = id
        1L
      },
      kill_all = function(proc, grace) {
        seen$payload_at_kill = file.exists(file.path(st$dir, "spec.rds"))
        seen$dir = st$dir
        TRUE
      },
      job_remove = function(...) TRUE)
    expect_identical(tryCatch(worker_spawn(st), error = identity), original)
    expect_true(seen$payload_at_kill)
    expect_false(dir.exists(seen$dir))
    expect_null(st$dir)
    if (stage == "job") expect_identical(seen$cancelled, "owned-watch")
  }
})

test_that("unsettled worker cleanup retains ownership and permits a confirmed retry", {
  skip_on_cran()
  values = list(FALSE, NA, structure(list(message = "kill failed", call = NULL),
                                     class = c("error", "condition")),
                 structure(list(message = "kill interrupted", call = NULL),
                           class = c("interrupt", "condition")))
  for (value in values) {
    st = worker_launch_state()
    st$p = list(get_pid = function() 126L)
    st$dir = withr::local_tempdir()
    dir = st$dir
    st$job = "owned-job"
    st$watch = "owned-watch"
    seen = new.env(parent = emptyenv())
    seen$order = character()
    seen$removed = 0L
    local_mocked_bindings(
      reactor_cancel = function(id) {
        seen$order = c(seen$order, "cancel")
        1L
      },
      kill_all = function(p, grace) {
        seen$order = c(seen$order, "kill")
        if (inherits(value, "condition")) stop(value)
        value
      },
      job_remove = function(id) {
        seen$removed = seen$removed + 1L
        TRUE
      })
    expect_false(worker_kill(st))
    expect_identical(seen$order, c("cancel", "kill"))
    expect_true(st$stopped)
    expect_true(dir.exists(dir))
    expect_identical(st$job, "owned-job")
    expect_identical(seen$removed, 0L)
    local_mocked_bindings(kill_all = function(p, grace) TRUE)
    expect_true(worker_kill(st))
    expect_false(dir.exists(dir))
    expect_null(st$job)
    expect_null(st$dir)
    expect_identical(seen$removed, 1L)
    expect_true(worker_kill(st))
    expect_identical(seen$removed, 1L)
  }
})

test_that("cancelled workers ignore late result, permission and exit callbacks", {
  st = worker_launch_state()
  st$p = list(get_pid = function() 127L)
  st$dir = withr::local_tempdir()
  st$result_path = file.path(st$dir, "result.rds")
  save_rds(list(status = "idle", exports = list(injected = TRUE)), st$result_path)
  local_mocked_bindings(kill_all = function(...) FALSE,
                        worker_reply = function(...) stop("late permission was answered"))
  expect_false(worker_kill(st))
  final = st$final
  worker_on_line(st, json_encode(list(type = "result", status = "idle", text = "late")))
  worker_on_line(st, json_encode(list(type = "permission_request", id = "late",
                                      request = list(tool = "r", input = list(code = "1")))))
  worker_on_exit(st, 0L)
  expect_null(st$result)
  expect_identical(st$final, final)
  expect_false(exists("injected", envir = st$home, inherits = FALSE))
  expect_true(dir.exists(st$dir))
})

test_that("natural worker exit keeps recovery files until the process tree settles", {
  st = worker_launch_state()
  st$p = list(get_pid = function() 128L)
  st$dir = withr::local_tempdir()
  st$result_path = file.path(st$dir, "result.rds")
  save_rds(list(status = "idle", exports = list(m = 2)), st$result_path)
  st$result = list(status = "idle", text = "done", usage = list(input = 2, output = 1))
  st$job = "natural-job"
  seen = new.env(parent = emptyenv())
  seen$removed = 0L
  local_mocked_bindings(kill_all = function(...) FALSE,
                        job_remove = function(...) seen$removed = seen$removed + 1L)
  worker_on_exit(st, 0L)
  expect_identical(st$home$m, 2)
  expect_identical(st$final[[4L]]$type, "done")
  expect_true(dir.exists(st$dir))
  expect_identical(st$job, "natural-job")
  expect_identical(seen$removed, 0L)
  final = st$final
  local_mocked_bindings(kill_all = function(...) TRUE)
  expect_true(worker_kill(st))
  expect_null(st$dir)
  expect_null(st$job)
  expect_identical(st$final, final)
})

test_that("failed watcher cancellation cannot complete worker cleanup before a retry", {
  skip_on_cran()
  values = list(structure(list(message = "cancel failed", call = NULL),
                           class = c("error", "condition")),
                 structure(list(message = "cancel interrupted", call = NULL),
                           class = c("interrupt", "condition")))
  for (value in values) {
    st = worker_launch_state()
    st$p = list(get_pid = function() 129L)
    st$dir = withr::local_tempdir()
    dir = st$dir
    st$job = "cancel-job"
    st$watch = "cancel-watch"
    seen = new.env(parent = emptyenv())
    seen$kills = 0L
    seen$removed = 0L
    local_mocked_bindings(
      reactor_cancel = function(...) stop(value),
      kill_all = function(...) {
        seen$kills = seen$kills + 1L
        TRUE
      },
      job_remove = function(...) seen$removed = seen$removed + 1L)
    expect_false(worker_kill(st))
    expect_identical(seen$kills, 1L)
    expect_identical(seen$removed, 0L)
    expect_identical(st$watch, "cancel-watch")
    expect_identical(st$job, "cancel-job")
    expect_true(dir.exists(dir))
    expect_false(isTRUE(st$cleaned))
    local_mocked_bindings(reactor_cancel = function(...) 1L)
    expect_true(worker_kill(st))
    expect_null(st$watch)
    expect_null(st$job)
    expect_false(dir.exists(dir))
    expect_identical(seen$removed, 1L)
  }
})
