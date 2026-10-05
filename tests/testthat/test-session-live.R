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

test_that("an eval() target is kept as the home, a function frame under eval() is not (R2)", {
  e = new.env()
  s = eval(quote(test_session(home = e)), e)
  expect_identical(session_home(s), e)
  expect_identical(session_data(s)$home_label, "<environment>")
  f = function() eval(quote(test_session(home = environment())), environment())
  s = f()
  expect_null(session_home(s))
  expect_match(session_data(s)$home_label, "^frame of f")
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

# ---- FIX-1: a GC-time session shutdown is deferred out of registry iteration --------------------
# A dead session's finalizer runs at whatever allocation triggers the collection. It releases the
# lock and leaves the live index at once, but its session_shutdown (hooks, record drop) waits for
# the next registry entry (D-085).
# A test whose collection must happen at a controlled point keeps the session only in `hold` and
# releases it right before that point: a collection earlier (a natural one, any allocation can
# trigger it) would finalise the session while no registry work runs, and the next entry would
# then drain its shutdown before the scenario starts. The explicit gc() in each such window
# checks that the session survives it.

# A command handler defined here, so that registry records never hold a test's frame
fix1_cmd = function(args, ctx) "x"

# A scratch registry for the calling test; the sessions of earlier tests are collected and their
# shutdowns dispatched first, in the registry they were registered in
fix1_registry = function(env = parent.frame()) {
  invisible(gc())
  registry_names("command")
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("a session collected inside registry_session_drop()'s loop does not break it (FIX-1)", {
  reg = fix1_registry()
  registry_add(gptr_command("b1", fix1_cmd), "session", 0L, session = "sB")
  registry_add(gptr_command("b2", fix1_cmd), "session", 0L, session = "sB")
  hold = new.env()
  hold$a = test_session()
  id_a = session_data(hold$a)$id
  registry_add(gptr_command("a1", fix1_cmd), "session", 0L, session = id_a)
  registry_add(gptr_command("a2", fix1_cmd), "session", 0L, session = id_a)
  test_session() # gptr_last() now holds this one, so only `hold` keeps `a`
  invisible(gc()) # the window: `a` survives it
  expect_false(is.null(session_by_id(id_a)))
  # the loop visits sB's records first, then a's
  expect_identical(ls(reg$recs), c("r1", "r2", "r3", "r4"))
  drop_one = registry_remove
  expect_no_error(with_mocked_bindings(
    registry_session_drop("sB"),
    registry_remove = function(id) {
      hold$a = NULL # `a` is released and finalised in the middle of the loop
      invisible(gc())
      drop_one(id)
    }
  ))
  expect_null(session_by_id(id_a))
  expect_identical(ls(reg$recs), c("r3", "r4"))
  expect_null(registry_get("command", "a1", session = id_a))
  expect_length(ls(reg$recs), 0L)
})

test_that("a session collected inside ext_unload()'s loop does not break it (FIX-1)", {
  reg = fix1_registry()
  ext_load(function(gptr) gptr$register(gptr_command("p1", fix1_cmd)), "plugin:fixone", 5L)
  hold = new.env()
  hold$a = test_session()
  id_a = session_data(hold$a)$id
  ext_load(function(gptr) gptr$register(gptr_command("a1", fix1_cmd)), "session", 0L,
           session = id_a)
  test_session()
  invisible(gc()) # the window: `a` survives it
  expect_false(is.null(session_by_id(id_a)))
  expect_identical(ls(reg$exts), c("e1", "e2"))
  forget = ext_forget
  expect_no_error(with_mocked_bindings(
    ext_unload("plugin:fixone"),
    ext_forget = function(info, reg = registry_env()) {
      hold$a = NULL # `a` is released and finalised in the middle of the loop
      invisible(gc())
      forget(info, reg)
    }
  ))
  expect_identical(ls(reg$exts), "e2")
  registry_names("command")
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$recs), 0L)
})

test_that("a collected session's shutdown runs at the next safe point, not inside gc() (FIX-1)", {
  local_store()
  reg = fix1_registry()
  log = new.env()
  log$order = character()
  hold = new.env()
  hold$a = test_session()
  id_a = session_data(hold$a)$id
  session_append(hold$a, entry_custom("test.note", list(i = 1L)))
  lock_a = lock_path(session_data(hold$a)$file)
  registry_add(gptr_command("mine", fix1_cmd), "session", 0L, session = id_a)
  hook_add("session_shutdown", function(event, ctx) {
    log$order = c(log$order, paste0("own:", event$reason))
    # the session's own listener runs before its records are dropped
    log$mine = registry_get("command", "mine", session = event$session)
    NULL
  }, rank = 0L, source = "session", session = id_a)
  hook_add("turn_end", function(event, ctx) {
    hold$a = NULL # `a` is released and finalised inside this handler
    invisible(gc())
    log$order = c(log$order, "turn_end")
    NULL
  })
  test_session()
  invisible(gc()) # the window: `a` survives it
  expect_true(dir.exists(lock_a))
  ev_dispatch("turn_end", list())
  expect_identical(log$order, "turn_end")
  # the finalizer still releases the lock and leaves the live index at once
  expect_false(dir.exists(lock_a))
  expect_null(session_by_id(id_a))
  expect_false(is.null(get0("command\rmine", envir = reg$by_key, inherits = FALSE)))
  # the next registry entry dispatches session_shutdown (reason gc), then drops the records
  expect_null(registry_get("command", "mine", session = id_a))
  expect_identical(log$order, c("turn_end", "own:gc"))
  expect_false(is.null(log$mine))
  expect_null(get0("command\rmine", envir = reg$by_key, inherits = FALSE))
  expect_null(get0("session_shutdown", envir = reg$hooks, inherits = FALSE))
})

test_that("shutdown hooks may create and drop sessions while the queue drains (FIX-1)", {
  reg = fix1_registry()
  keep = test_session()
  log = new.env()
  log$mine = character()
  log$seen = character()
  log$depth = 0L
  log$deepest = 0L
  hook_add("session_shutdown", function(event, ctx) {
    if (!(event$session %in% log$mine)) return(NULL)
    log$depth = log$depth + 1L
    log$deepest = max(log$deepest, log$depth)
    log$seen = c(log$seen, event$session)
    if (length(log$seen) < 3L) {
      s = test_session() # session_new() inside a drain does not drain again
      sid = session_data(s)$id
      log$mine = c(log$mine, sid)
      registry_add(gptr_command("tmp", fix1_cmd), "session", 0L, session = sid)
      last_set(keep)
      rm(s)
      invisible(gc()) # collected while the queue drains: queued, not dispatched here
    }
    log$depth = log$depth - 1L
    NULL
  })
  a = test_session()
  log$mine = session_data(a)$id
  registry_add(gptr_command("tmp", fix1_cmd), "session", 0L, session = log$mine)
  last_set(keep)
  rm(a)
  invisible(gc())
  expect_length(log$seen, 0L)
  registry_names("command")
  expect_identical(log$seen, log$mine)
  expect_length(log$seen, 3L)
  expect_identical(log$deepest, 1L)
  tmp = vapply(mget(ls(reg$recs), envir = reg$recs), function(r) r$name, "")
  expect_false("tmp" %in% tmp)
})

test_that("a new shell under a collected shell's id gets that shell's shutdown first (FIX-1)", {
  reg = fix1_registry()
  log = new.env()
  log$order = character()
  hold = new.env()
  hold$a = test_session()
  id_a = session_data(hold$a)$id
  registry_add(gptr_command("old", fix1_cmd), "session", 0L, session = id_a)
  hook_add("session_shutdown", function(event, ctx) {
    if (identical(event$session, id_a)) log$order = c(log$order, paste0("shutdown:", event$reason))
    NULL
  })
  hook_add("turn_end", function(event, ctx) {
    hold$a = NULL # `a` is collected inside registry work, so its shutdown stays queued
    invisible(gc())
    log$order = c(log$order, "collected")
    # session_new() does not drain here; only the shutdown queued for this id is dispatched
    log$s = test_session(opts = list(id = id_a))
    registry_add(gptr_command("new", fix1_cmd), "session", 0L, session = id_a)
    log$order = c(log$order, "new shell")
    NULL
  })
  test_session()
  invisible(gc()) # the window: `a` survives it
  expect_false(is.null(session_by_id(id_a)))
  ev_dispatch("turn_end", list())
  expect_identical(log$order, c("collected", "shutdown:gc", "new shell"))
  expect_identical(session_by_id(id_a), log$s)
  expect_false(is.null(registry_get("command", "new", session = id_a)))
  expect_null(registry_get("command", "old", session = id_a))
  expect_identical(log$order, c("collected", "shutdown:gc", "new shell"))
})

test_that("unloading drains the deferred shutdowns, then shuts the live sessions down (FIX-1)", {
  local_store()
  reg = fix1_registry()
  log = new.env()
  log$events = list()
  hook_add("session_shutdown", function(event, ctx) {
    log$events[[length(log$events) + 1L]] = c(event$session, event$reason)
    NULL
  })
  a = test_session()
  id_a = session_data(a)$id
  b = test_session()
  id_b = session_data(b)$id
  session_append(b, entry_custom("test.note", list(i = 1L)))
  lock_b = lock_path(session_data(b)$file)
  rm(a)
  invisible(gc())
  mine = function() Filter(function(e) e[[1L]] %in% c(id_a, id_b), log$events)
  expect_length(mine(), 0L)
  # only `b` is live here, whatever earlier tests left behind
  local_mocked_bindings(live_all = function() stats::setNames(list(b), id_b))
  live_unload()
  expect_identical(mine(), list(c(id_a, "gc"), c(id_b, "unload")))
  expect_false(dir.exists(lock_b))
  expect_length(ls(reg$deferred), 0L)
})

test_that("at process exit the deferred shutdowns are dispatched (FIX-1)", {
  skip_on_cran()
  out = withr::local_tempfile(fileext = ".txt")
  script = withr::local_tempfile(fileext = ".R")
  writeLines(c(
    tracemem_loader(),
    sprintf("out = %s", deparse(out)),
    "note = function(event, ctx) {",
    "  cat(paste0(event$session, ' ', event$reason, '\\n'), file = out, append = TRUE)",
    "}",
    "invisible(gptr:::hook_add('session_shutdown', note))",
    "a = gptr:::session_new('fake/fake-1', 'auto', home = new.env())",
    "b = gptr:::session_new('fake/fake-1', 'auto', home = new.env())",
    "cat('GPTR-IDS', gptr:::session_data(a)$id, gptr:::session_data(b)$id, '\\n')",
    "rm(a)",
    "invisible(gc())",
    "cat('GPTR-AFTER-GC', file.exists(out), '\\n')"
  ), script)
  libs = paste(.libPaths(), collapse = .Platform$path.sep)
  res = processx::run(rscript_path(), c("--vanilla", script), env = c("current", R_LIBS = libs),
                      error_on_status = FALSE, timeout = 300)
  expect_identical(res$status, 0L)
  lines = strsplit(res$stdout, "\r?\n", perl = TRUE)[[1L]]
  ids = grep("^GPTR-IDS ", lines, value = TRUE)
  ids = unlist(strsplit(trimws(sub("^GPTR-IDS ", "", ids)), " "))
  expect_length(ids, 2L)
  # nothing was dispatched inside gc(); both shutdowns ran at exit, the collected session first
  expect_identical(trimws(grep("^GPTR-AFTER-GC", lines, value = TRUE)), "GPTR-AFTER-GC FALSE")
  got = if (file.exists(out)) readLines(out) else character()
  expect_identical(got, paste(ids, "gc"))
})
