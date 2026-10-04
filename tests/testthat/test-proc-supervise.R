local_proc_state = function(.env = parent.frame()) {
  old = the$jobs
  the$jobs = NULL
  withr::defer({
    the$jobs = old
  }, envir = .env)
  cache = withr::local_tempdir(.local_envir = .env)
  withr::local_envvar(R_USER_CACHE_DIR = cache, .local_envir = .env)
}

wait_until = function(cond, seconds = 5) {
  t0 = proc.time()[["elapsed"]]
  while (!isTRUE(cond()) && proc.time()[["elapsed"]] - t0 < seconds) Sys.sleep(0.05)
  isTRUE(cond())
}

test_that("pid_alive() checks liveness and the creation time against pid reuse", {
  local_proc_state()
  me = Sys.getpid()
  ct = proc_create_time(me)
  expect_true(pid_alive(me))
  expect_true(pid_alive(me, ct))
  expect_false(pid_alive(me, ct + 1000))
  # an unreadable creation time (a marker file stores NA as the JSON string "NA") is no mismatch
  expect_true(pid_alive(me, "NA"))
  expect_false(pid_alive(NA_integer_))
  expect_false(pid_alive(integer()))
  skip_on_cran()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  p$wait(10000L)
  expect_true(wait_until(function() !pid_alive(p$get_pid()), 5))
})

test_that("child-process pools are capped at 2 under R CMD check", {
  local_proc_state()
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  expect_identical(proc_pool_cap(8L), 2L)
  expect_identical(proc_pool_cap(1L), 1L)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = NA)
  expect_identical(proc_pool_cap(8L), 8L)
})

test_that("proc_mark() records a marker file that kill_all() releases", {
  local_proc_state()
  skip_on_cran()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"))
  withr::defer(try(p$kill(), silent = TRUE))
  marker = proc_marker_new()
  expect_match(marker, "^GPTR_PROC_[0-9a-f]{16}$")
  proc_mark(p, marker, rscript_path())
  rec = proc_record(p$get_pid())
  expect_identical(rec$marker, marker)
  expect_identical(rec$parent_pid, Sys.getpid())
  path = file.path(proc_dir(), paste0(marker, ".json"))
  expect_true(file.exists(path))
  expect_identical(json_decode(read_utf8(path)$text)$pid, p$get_pid())
  expect_true(kill_all(p, grace = 0))
  expect_false(file.exists(path))
  expect_null(proc_record(p$get_pid()))
})

test_that("kill_all() leaves no descendant", {
  local_proc_state()
  skip_on_cran()
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  # the grandchild has cleanup = FALSE, so only kill_all()'s tree logic can stop it (with the
  # default cleanup = TRUE the child's own exit would kill it and the test would prove nothing)
  code = paste0("rs = file.path(R.home('bin'), if (.Platform$OS.type == 'windows') ",
                "'Rscript.exe' else 'Rscript'); ",
                "g = processx::process$new(rs, c('--vanilla', '-e', 'Sys.sleep(60)'), ",
                "cleanup = FALSE); cat(g$get_pid(), '\\n'); flush(stdout()); Sys.sleep(60)")
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", code), stdout = "|",
                            cleanup_tree = TRUE)
  withr::defer(try(p$kill_tree(), silent = TRUE))
  kids = function() ps::ps_children(ps::ps_handle(p$get_pid()), recursive = TRUE)
  expect_true(wait_until(function() length(kids()) >= 1L, 30))
  tree = c(p$get_pid(), vapply(kids(), ps::ps_pid, 1L))
  expect_true(kill_all(p, grace = 1))
  expect_true(wait_until(function() !any(vapply(tree, pid_alive, NA)), 5))
})

test_that("proc_sweep() kills the trees of markers whose parent process is gone", {
  local_proc_state()
  skip_on_cran()
  me = proc_self()
  write_marker = function(marker, pid, parent_create) {
    rec = list(marker = marker, pid = pid, create_time = proc_create_time(pid),
               parent_pid = me$pid, parent_create = parent_create, command = "Rscript",
               started = "2026-09-30T00:00:00.000Z")
    path = file.path(proc_dir(create = TRUE), paste0(marker, ".json"))
    write_atomic(path, json_encode(rec))
    path
  }
  orphan_marker = proc_marker_new()
  orphan = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
                                 env = c("current", stats::setNames("YES", orphan_marker)))
  withr::defer(try(orphan$kill(), silent = TRUE))
  kept_marker = proc_marker_new()
  kept = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
                               env = c("current", stats::setNames("YES", kept_marker)))
  withr::defer(try(kept$kill(), silent = TRUE))
  expect_true(wait_until(function() length(proc_tree(orphan_marker)) == 1L, 10))
  # a parent creation time that does not match this process reads as "parent gone"
  orphan_file = write_marker(orphan_marker, orphan$get_pid(), me$create_time + 1000)
  kept_file = write_marker(kept_marker, kept$get_pid(), me$create_time)
  withr::defer(unlink(kept_file))
  expect_gte(proc_sweep(), 1L)
  expect_true(wait_until(function() !pid_alive(orphan$get_pid()), 5))
  expect_false(file.exists(orphan_file))
  expect_true(pid_alive(kept$get_pid()))
  expect_true(file.exists(kept_file))
})

test_that("proc_sweep() never kills by pid when the recorded creation time is unknown", {
  local_proc_state()
  skip_on_cran()
  me = proc_self()
  # a process that carries no marker: only the recorded pid points at it, as after pid reuse
  bystander = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(try(bystander$kill(), silent = TRUE))
  marker = proc_marker_new()
  rec = list(marker = marker, pid = bystander$get_pid(), create_time = NA_real_,
             parent_pid = me$pid, parent_create = me$create_time + 1000, command = "Rscript",
             started = "2026-09-30T00:00:00.000Z")
  path = file.path(proc_dir(create = TRUE), paste0(marker, ".json"))
  write_atomic(path, json_encode(rec))
  expect_identical(proc_sweep(), 0L)
  expect_false(file.exists(path))
  expect_true(pid_alive(bystander$get_pid(), proc_create_time(bystander$get_pid())))
})

write_proc_fixture = function(rec, marker = rec$marker) {
  path = file.path(proc_dir(create = TRUE), paste0(marker, ".json"))
  write_atomic(path, json_encode(rec))
  path
}

test_that("boundary: malformed marker records never reach process operations", {
  local_proc_state()
  calls = character()
  local_mocked_bindings(
    proc_tree = function(marker) {
      calls <<- c(calls, marker)
      list()
    },
    pid_alive = function(...) FALSE, .package = "gptr"
  )
  marker = paste0("GPTR_PROC_", strrep("a", 16L))
  good = list(marker = marker, pid = 42L, create_time = 10,
              parent_pid = 43L, parent_create = 11)
  bad = list(
    list(marker = "PATH"), list(marker = paste0("GPTR_PROC_", strrep("b", 16L))),
    list(pid = -1L), list(pid = 42.5), list(pid = c(42L, 43L)),
    list(parent_pid = NULL), list(parent_pid = 0L), list(create_time = "invalid"),
    list(create_time = c(10, 11)), list(parent_create = Inf)
  )
  for (change in bad) {
    rec = good
    for (name in names(change)) rec[name] = change[name]
    path = write_proc_fixture(rec, marker)
    expect_identical(proc_sweep(), 0L)
    expect_false(file.exists(path))
  }
  expect_length(calls, 0L)
})

test_that("boundary: process records distinguish stale handles with reused PIDs", {
  local_proc_state()
  local_mocked_bindings(proc_create_time = function(pid) 10, .package = "gptr")
  old = list(get_pid = function() 42L, tag = "old")
  current = list(get_pid = function() 42L, tag = "current")
  old_marker = proc_marker_new()
  marker = proc_marker_new()
  proc_mark(old, old_marker, "synthetic")
  proc_unmark(old_marker)
  proc_mark(current, marker, "synthetic")
  withr::defer(proc_unmark(marker))
  expect_null(proc_record(42L, process = old))
  expect_identical(proc_record(42L, process = current)$marker, marker)
})

test_that("boundary: orphan cleanup signals through the recorded process identity", {
  local_proc_state()
  killed = FALSE
  signalled_handle = NULL
  verified_handle = NULL
  local_mocked_bindings(
    ps_handle = function(pid, time = NULL) list(pid = pid, time = time),
    ps_is_running = function(p) p$pid == 42L && !killed,
    ps_status = function(p) "running",
    ps_create_time = function(p) {
      verified_handle <<- p
      10
    },
    ps_kill = function(p) {
      signalled_handle <<- p
      killed <<- TRUE
    },
    .package = "ps"
  )
  local_mocked_bindings(
    pid_alive = function(pid, create_time = NULL) pid == 42L && !killed,
    proc_tree = function(marker) list(), .package = "gptr"
  )
  marker = proc_marker_new()
  path = write_proc_fixture(list(marker = marker, pid = 42L, create_time = 10,
                                 parent_pid = 43L, parent_create = 11))
  expect_identical(proc_sweep(), 1L)
  expect_identical(signalled_handle, verified_handle)
  expect_false(file.exists(path))
})

test_that("boundary: failed orphan cleanup retains the recovery marker", {
  local_proc_state()
  local_mocked_bindings(
    ps_handle = function(pid, time = NULL) list(pid = pid, time = time),
    ps_is_running = function(p) p$pid == 42L,
    ps_status = function(p) "running",
    ps_create_time = function(p) 10,
    ps_kill = function(p) stop("synthetic access failure"),
    ps_kill_tree = function(marker) stop("synthetic access failure"),
    .package = "ps"
  )
  local_mocked_bindings(
    pid_alive = function(pid, create_time = NULL) pid == 42L,
    proc_tree = function(marker) list(list(pid = 42L, time = 10)), .package = "gptr"
  )
  marker = proc_marker_new()
  path = write_proc_fixture(list(marker = marker, pid = 42L, create_time = 10,
                                 parent_pid = 43L, parent_create = 11))
  withr::defer(unlink(path))
  expect_identical(proc_sweep(), 0L)
  expect_true(file.exists(path))
})

test_that("boundary: stale process cleanup cannot release or kill a reused PID record", {
  local_proc_state()
  signalled = character()
  local_mocked_bindings(proc_create_time = function(pid) 10, .package = "gptr")
  local_mocked_bindings(
    ps_kill_tree = function(marker) {
      signalled <<- c(signalled, marker)
    }, .package = "ps"
  )
  stale = list(get_pid = function() 42L, is_alive = function() FALSE,
               kill_tree = function() NULL, kill = function() NULL)
  current = list(get_pid = function() 42L, tag = "current")
  marker = proc_marker_new()
  proc_mark(current, marker, "synthetic")
  expect_true(kill_all(stale, grace = 0))
  expect_false(proc_release(stale))
  expect_identical(proc_record(42L)$marker, marker)
  expect_length(signalled, 0L)
})

test_that("boundary: unavailable tree inspection preserves recovery records", {
  local_proc_state()
  local_mocked_bindings(
    proc_tree = function(marker) structure(list(), unavailable = TRUE),
    proc_parent_alive = function(...) FALSE, proc_handle_alive = function(...) FALSE,
    proc_identity = function(...) list(handle = NULL, alive = FALSE),
    .package = "gptr"
  )
  local_mocked_bindings(ps_handle = function(pid, time = NULL) list(), .package = "ps")
  marker = proc_marker_new()
  path = write_proc_fixture(list(marker = marker, pid = 42L, create_time = 10,
                                 parent_pid = 43L, parent_create = 11))
  expect_identical(proc_sweep(), 0L)
  expect_true(file.exists(path))
})

test_that("boundary: unreadable parent identity never authorizes orphan cleanup", {
  local_proc_state()
  calls = 0L
  local_mocked_bindings(
    ps_handle = function(...) stop("synthetic access denied"), .package = "ps"
  )
  local_mocked_bindings(proc_tree = function(marker) {
    calls <<- calls + 1L
    list()
  }, .package = "gptr")
  marker = proc_marker_new()
  path = write_proc_fixture(list(marker = marker, pid = 42L, create_time = 10,
                                 parent_pid = 43L, parent_create = 11))
  expect_identical(proc_sweep(), 0L)
  expect_true(file.exists(path))
  expect_identical(calls, 0L)
})

test_that("boundary: JSON timestamp rounding does not turn a live parent into an orphan", {
  local_proc_state()
  saved = json_decode(json_encode(list(time = proc_create_time(Sys.getpid()))))$time
  expect_true(proc_parent_alive(list(parent_pid = Sys.getpid(), parent_create = saved)))
})

test_that("the job table maps a requested stop to stopped or aborted, never error", {
  local_proc_state()
  st = new.env()
  st$w = "running"
  st$a = "running"
  job_add("worker", "job-test-w", "demo worker", pid = 101L,
          stop = function() st$w = "error", status = function() st$w)
  job_add("artifact", "job-test-a", "demo app", stop = function() st$a = "error",
          status = function() st$a)
  withr::defer({
    job_remove("job-test-w")
    job_remove("job-test-a")
  })
  jl = job_list()
  expect_identical(names(jl), c("id", "kind", "name", "pid", "status", "started"))
  expect_identical(jl$status[jl$id == "job-test-w"], "running")
  expect_identical(jl$pid[jl$id == "job-test-w"], 101L)
  expect_s3_class(jl$started, "POSIXct")
  st$w = "error"
  expect_identical(job_list()$status[job_list()$id == "job-test-w"], "error")
  st$w = "running"
  stopped = gptr_jobs(kill = TRUE)
  expect_s3_class(stopped, "gptr_jobs")
  expect_s3_class(stopped, "gptr_listing")
  expect_identical(stopped$status[stopped$id == "job-test-w"], "aborted")
  expect_identical(stopped$status[stopped$id == "job-test-a"], "stopped")
  expect_identical(job_list(kind = "artifact")$id, "job-test-a")
  expect_true(job_remove("job-test-a"))
  expect_false(job_remove("job-test-a"))
})

test_that("gptr_jobs() returns a gptr_jobs listing and validates its arguments", {
  local_proc_state()
  out = gptr_jobs()
  expect_s3_class(out, "gptr_jobs")
  expect_identical(names(out), c("id", "kind", "name", "pid", "status", "started"))
  expect_error(gptr_jobs(kill = "yes"), class = "gptr_error_invalid_argument")
  expect_error(job_add("nope", "x", "y", stop = function() NULL),
               class = "gptr_error_invalid_argument")
  expect_error(job_add("bg", "x", "y", stop = "no"), class = "gptr_error_invalid_argument")
})

test_that("a job added twice keeps one row and a running job keeps its status", {
  local_proc_state()
  job_add("bg", "job-test-b", "first", stop = function() NULL)
  job_add("bg", "job-test-b", "second", stop = function() NULL)
  withr::defer(job_remove("job-test-b"))
  jl = job_list(kind = "bg")
  expect_identical(jl$name[jl$id == "job-test-b"], "second")
  expect_identical(sum(jl$id == "job-test-b"), 1L)
  gptr_jobs(kill = TRUE)
  jl = job_list(kind = "bg")
  expect_identical(jl$status[jl$id == "job-test-b"], "running")
})

test_that("gptr_jobs(kill = TRUE) reports a job whose stop removes its own row", {
  local_proc_state()
  st = new.env()
  st$s = "running"
  job_add("session", "job-test-s", "a background session",
          stop = function() {
            st$s = "error"
            job_remove("job-test-s")
          }, status = function() st$s)
  stopped = gptr_jobs(kill = TRUE)
  expect_identical(stopped$status[stopped$id == "job-test-s"], "aborted")
  expect_false("job-test-s" %in% job_list()$id)
})

test_that("proc_unload() stops every job", {
  local_proc_state()
  st = new.env()
  st$stopped = FALSE
  job_add("cli", "job-test-u", "fake cli", stop = function() st$stopped = TRUE)
  withr::defer(job_remove("job-test-u"))
  proc_unload()
  expect_true(st$stopped)
})

test_that("boundary: job PID metadata is scalar and status uncertainty remains visible", {
  local_proc_state()
  for (pid in list(c(1L, 2L), NULL, "invalid", TRUE, Inf, NaN, -1L, 1.5)) {
    expect_error(job_add("bg", "bad", "bad", pid = pid, stop = function() NULL),
                 class = "gptr_error_invalid_argument")
  }
  job_add("bg", "unknown", "unreadable", stop = function() NULL,
          status = function() stop("synthetic status failure"))
  stopped = gptr_jobs(kill = TRUE)
  expect_identical(stopped$status[stopped$id == "unknown"], "unknown")
})

test_that("boundary: unload cleans marked children even when their environment is unreadable", {
  local_proc_state()
  killed = FALSE
  local_mocked_bindings(
    proc_create_time = function(pid) 10,
    proc_tree = function(marker) list(),
    proc_identity = function(...) list(handle = list(pid = 42L), alive = !killed),
    proc_handle_alive = function(handle) !killed, .package = "gptr"
  )
  local_mocked_bindings(
    ps_kill_tree = function(marker) NULL,
    ps_kill = function(handle) {
      killed <<- TRUE
    }, .package = "ps"
  )
  p = list(get_pid = function() 42L, is_alive = function() !killed,
           interrupt = function() NULL, wait = function(...) NULL,
           kill_tree = function() NULL, kill = function() NULL)
  marker = proc_marker_new()
  proc_mark(p, marker, "synthetic")
  proc_unload()
  expect_true(killed)
  expect_null(proc_record(42L))
})

test_that("boundary: unload retains records when owned child cleanup is unconfirmed", {
  local_proc_state()
  local_mocked_bindings(
    proc_create_time = function(pid) 10,
    proc_cleanup_record = function(rec) list(killed = 0L, complete = FALSE), .package = "gptr"
  )
  local_mocked_bindings(ps_kill_tree = function(marker) NULL, .package = "ps")
  p = list(get_pid = function() 42L)
  marker = proc_marker_new()
  proc_mark(p, marker, "synthetic")
  path = file.path(proc_dir(), paste0(marker, ".json"))
  proc_unload()
  expect_true(file.exists(path))
  expect_identical(proc_record(42L)$marker, marker)
})

test_that("boundary: marker persistence failures propagate while retaining the exact child", {
  local_proc_state()
  local_mocked_bindings(
    proc_self = function() list(pid = 42L, create_time = 10),
    proc_create_time = function(pid) 11,
    write_atomic = function(...) gptr_abort("Synthetic marker write failure.", "io")
  )
  p = list(get_pid = function() 43L)
  marker = proc_marker_new()
  expect_error(proc_mark(p, marker, "synthetic"), class = "gptr_error_io")
  expect_identical(proc_record(43L, process = p)$marker, marker)
  expect_identical(jobs_env()$handles[[marker]], p)
})
