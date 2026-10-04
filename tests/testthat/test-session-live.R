source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

test_that("the live registry is weak and keyed on the shell: a detached copy has no live record", {
  s = test_session()
  id = session_data(s)$id
  copy = unserialize(serialize(s, NULL))
  expect_false(is.null(session_live(s)))
  expect_null(session_live(copy))
  expect_identical(session_by_id(id), s)
  expect_true(id %in% names(live_all()))
})

test_that("a function frame is never kept as the home (R2)", {
  f = function() test_session(home = environment())
  s = f()
  expect_null(session_home(s))
  expect_match(session_data(s)$home_label, "^frame of f")
  g = test_session(home = globalenv())
  expect_identical(session_home(g), globalenv())
  expect_identical(session_data(g)$home_label, "globalenv")
})

test_that("gptr_last() holds the most recent session strongly and survives gc()", {
  s = test_session()
  id = session_data(s)$id
  rm(s)
  invisible(gc())
  expect_identical(session_data(gptr_last())$id, id)
  expect_false(is.null(session_by_id(id)))
})

test_that("an unreferenced session is finalised and its lock removed, except gptr_last()'s", {
  local_store()
  a = test_session()
  session_append(a, entry_custom("test.note", list(i = 1L)))
  lock_a = lock_path(session_data(a)$file)
  id_a = session_data(a)$id
  b = test_session()
  session_append(b, entry_custom("test.note", list(i = 2L)))
  lock_b = lock_path(session_data(b)$file)
  expect_true(dir.exists(lock_a))
  rm(a)
  invisible(gc())
  expect_false(dir.exists(lock_a))
  expect_null(session_by_id(id_a))
  rm(b)
  invisible(gc())
  expect_true(dir.exists(lock_b))
})

test_that("a same-process duplicate cannot attach: gptr_error_split_brain", {
  s = test_session()
  copy = unserialize(serialize(s, NULL))
  expect_error(session_attach(copy), class = "gptr_error_split_brain")
})

test_that("a detached copy continues from its own leaf once the original is gone", {
  local_store()
  s = test_session(home = globalenv())
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("one")))
  session_append(s, entry_message(msg_assistant("first", api = "fake", provider = "fake",
                                                model = "fake-1")))
  snap = serialize(s, NULL)
  d$turns = 2L
  session_append(s, entry_message(msg_user("two")))
  file = d$file
  other = test_session()
  rm(s, d)
  invisible(gc())
  copy = unserialize(snap)
  session_attach(copy)
  session_append(copy, entry_message(msg_user("two, rephrased")))
  lines = readLines(file, encoding = "UTF-8")[-1L]
  entries = lapply(lines, json_decode)
  users = Filter(function(e) identical(e$message$role, "user"), entries)
  expect_length(users, 3L)
  expect_identical(users[[2L]]$parentId, users[[3L]]$parentId)
})

test_that("locks hold the pid and the process creation time; a dead holder is stale", {
  local_store()
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  h = lock_holder(lock_path(file))
  expect_identical(h$pid, Sys.getpid())
  expect_true(lock_is_mine(h))
  # the live record names the lock it holds (04 section 5.1: `lock`, chr path)
  expect_identical(session_live(s)$lock, lock_path(file))
  write_atomic(file.path(lock_path(file), "pid"), c("999999", "1"))
  expect_false(lock_held_elsewhere(file))
  expect_identical(lock_acquire(file), lock_path(file))
})

test_that("a lock held by another live process is split brain", {
  skip_on_cran()
  local_store()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"),
                           supervise = supervise_default())
  withr::defer(p$kill())
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  created = as.numeric(ps::ps_create_time(ps::ps_handle(p$get_pid())))
  write_atomic(file.path(lock_path(file), "pid"),
               c(as.character(p$get_pid()), format(created, digits = 17)))
  expect_true(lock_held_elsewhere(file))
  expect_error(lock_acquire(file), class = "gptr_error_split_brain")
})

test_that("300 sessions kept in a list leave no connection open (IC-59)", {
  local_store()
  n0 = nrow(showConnections())
  keep = lapply(1:300, function(i) {
    s = test_session()
    session_append(s, entry_custom("test.note", list(i = i)))
    s
  })
  expect_length(keep, 300L)
  expect_identical(nrow(showConnections()), n0)
})

test_that("secret_register() warns secret_late for a value a live session already holds (IC-70)", {
  local_store()
  s = test_session()
  late = paste0("FAKE_late_", "kernel_secret_77")
  session_append(s, entry_message(msg_user(paste("my key is", late))))
  withr::defer(vault_reset())
  w = expect_warning(secret_register(late, "LATE_KERNEL", source = "session"),
                     class = "gptr_warning_secret_late")
  expect_identical(names(w$counts), session_data(s)$id)
})

test_that("continuing a same-process duplicate with a run is split brain", {
  local_permissive()
  local_fake_provider(list("a"))
  s = test_session()
  run_text(s, "one")
  copy = unserialize(serialize(s, NULL))
  expect_error(run_start(copy, msg_user("again")), class = "gptr_error_split_brain")
  expect_error(gptr_resume(copy), class = "gptr_error_split_brain")
})

test_that("a copy snapshotted while running is attached as aborted (reason detached)", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE), "resumed"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  snap = serialize(s, NULL)
  run_abort(run)
  other = test_session()
  rm(s, run)
  invisible(gc())
  copy = unserialize(snap)
  gptr_resume(copy)
  expect_identical(copy$status, "aborted")
  expect_identical(copy$reason, "detached")
})

test_that("a file locked by another live process is not resumed and leaves no live session", {
  skip_on_cran()
  local_store()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"),
                           supervise = supervise_default())
  withr::defer(p$kill())
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  id = session_data(s)$id
  last = test_session()
  rm(s)
  invisible(gc())
  created = as.numeric(ps::ps_create_time(ps::ps_handle(p$get_pid())))
  dir.create(lock_path(file), showWarnings = FALSE)
  write_atomic(file.path(lock_path(file), "pid"),
               c(as.character(p$get_pid()), format(created, digits = 17)))
  expect_error(gptr_resume(file, envir = new.env()), class = "gptr_error_split_brain")
  expect_null(session_by_id(id))
  expect_identical(gptr_last(), last)
  expect_error(gptr_resume(id, envir = new.env()), class = "gptr_error_split_brain")
})
