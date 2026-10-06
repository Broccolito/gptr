# Tests of R/artifact-registry.R (P23). Tests that start processes skip on CRAN.

# An artifact.json with `n` versions (current = n); returns the id invisibly
seed_artifact = function(id, n = 1L, kind = "shiny") {
  meta = artifact_meta_new(id, paste("Title of", id), kind)
  meta$versions = lapply(seq_len(n), function(i) {
    dir.create(artifact_version_dir(id, i), recursive = TRUE, showWarnings = FALSE)
    list(n = i, created = artifact_time(), app_sha = NULL, data = list(), session = NULL,
         checks = artifact_checks_json(artifact_checks(parse = TRUE)))
  })
  meta$current = as.integer(n)
  artifact_meta_write(id, meta)
  invisible(id)
}

# A sleeping R child with a handle shaped like the launcher's (closures over the process only).
# R_TESTS is blanked: R CMD check sets it to a relative startup file that R's base profile
# sources in every R child, which would end the child at once (as callr::rcmd_safe_env() does)
sleeper_handle = function(.env = parent.frame()) {
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
                            env = c("current", R_TESTS = ""), cleanup = TRUE,
                            cleanup_tree = TRUE)
  withr::defer(kill_all(p, grace = 0), envir = .env)
  list(url = "http://127.0.0.1:50000/?gptr_token=ab", pid = p$get_pid(), port = 50000L,
       alive = function() p$is_alive(), stop = function() kill_all(p, grace = 1))
}

sleeper_type = list(stop = function(handle) handle$stop())

# Collect the payloads of an event for the calling test
local_events = function(event, .env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$events = list()
  id = hook_add(event, function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(id), envir = .env)
  seen
}

test_that("a record's status is running, then stopped after a requested stop (IC-60)", {
  skip_on_cran()
  local_project()
  seed_artifact("rec")
  stops = local_events("artifact_stop")
  expect_identical(artifact_status("rec"), "stopped")
  rec = artifact_record_new("rec", 1L, sleeper_type, sleeper_handle())
  assign("rec", rec, envir = artifact_state$procs)
  withr::defer(if (!is.null(artifact_proc_get("rec"))) artifact_stop("rec", emit = FALSE))
  expect_identical(artifact_status("rec"), "running")
  expect_false(is.na(rec$create_time))
  artifact_job_add("rec", "Title of rec", rec$pid)
  expect_identical(job_list("artifact")$id, "artifact:rec")
  expect_identical(job_list("artifact")$status, "running")
  expect_true(artifact_stop("rec"))
  expect_false(isTRUE(pid_alive(rec$pid, rec$create_time)))
  expect_identical(artifact_status("rec"), "stopped")
  expect_identical(nrow(job_list("artifact")), 0L)
  expect_length(stops$events, 1L)
  expect_identical(stops$events[[1]]$id, "rec")
  expect_identical(stops$events[[1]]$reason, "user")
  expect_identical(stops$events[[1]]$version, 1L)
  expect_false(artifact_stop("rec"))
})

test_that("a process that ends without a stop request reads failed", {
  skip_on_cran()
  local_project()
  seed_artifact("crash")
  h = sleeper_handle()
  rec = artifact_record_new("crash", 1L, sleeper_type, h)
  assign("crash", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("crash", emit = FALSE))
  ps::ps_kill(ps::ps_handle(h$pid))
  deadline = Sys.time() + 10
  while (h$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_identical(artifact_status("crash"), "failed")
})

test_that("child output reaches the log in complete lines, redacted, and the raw file goes", {
  local_project()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("sk-ant-", "api03-", strrep("FAKEartifact", 4L), "00AA")
  secret_register(fake, "GPTR_ARTIFACT_TEST_KEY", source = "test")
  raw = withr::local_tempfile(fileext = ".log")
  log = file.path(artifact_dir("logs"), "run", "app-v001.log")
  rec = artifact_log_new(raw, log)
  write_bytes = function(text) {
    con = file(raw, "ab")
    on.exit(close(con))
    writeBin(charToRaw(text), con)
  }
  write_bytes(paste0("Listening on http://127.0.0.1:5000\nkey=", fake, "\npartial"))
  artifact_log_sync(rec)
  got = readLines(log, encoding = "UTF-8")
  expect_identical(got[1], "Listening on http://127.0.0.1:5000")
  expect_false(any(grepl(fake, got, fixed = TRUE)))
  expect_false(any(grepl("partial", got, fixed = TRUE)))
  write_bytes(" line\nWarning: Error in f: boom\n")
  artifact_log_sync(rec, final = TRUE)
  got = readLines(log, encoding = "UTF-8")
  expect_true("partial line" %in% got)
  expect_identical(artifact_log_tail(log, 1L), "Warning: Error in f: boom")
  expect_false(file.exists(raw))
  expect_null(rec$raw)
  expect_identical(artifact_tail_text(character(), log), "")
  expect_match(artifact_tail_text("x", log), "Last lines of .gptr/artifacts/logs/run/app-v001.log",
               fixed = TRUE)
})

test_that("run.json carries the contract fields and the owner; the handle reads both tables", {
  skip_on_cran()
  local_project()
  seed_artifact("hand", n = 2L)
  expect_identical(artifact_handle("hand")$status, "stopped")
  expect_true(is.na(artifact_handle("hand")$url))
  rec = artifact_record_new("hand", 2L, sleeper_type, sleeper_handle())
  rec$checks = artifact_checks(TRUE, TRUE, TRUE, NA, "HTTP-only check")
  assign("hand", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("hand", emit = FALSE))
  artifact_run_write(rec)
  info = json_decode(read_utf8(file.path(artifact_dir("hand"), "run", "run.json"))$text)
  expect_true(all(c("pid", "port", "url", "version", "started") %in% names(info)))
  expect_identical(as.integer(info$parent_pid), Sys.getpid())
  h = artifact_handle("hand")
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "running")
  expect_identical(h$version, 2L)
  expect_identical(h$url, rec$url)
  expect_identical(h$title, "Title of hand")
  expect_identical(h$checks$messages, "HTTP-only check")
  expect_identical(basename(h$path), "app.R")
  artifact_stop("hand", emit = FALSE)
  expect_false(file.exists(file.path(artifact_dir("hand"), "run", "run.json")))
  expect_error(artifact_handle("absent"), class = "gptr_error_invalid_argument")
})

test_that("the orphan sweep kills children of dead owners and spares the rest", {
  skip_on_cran()
  local_project()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  plant = function(id, pid, create_time, owner) {
    seed_artifact(id)
    dir.create(file.path(artifact_dir(id), "run"), showWarnings = FALSE)
    write_utf8(file.path(artifact_dir(id), "run", "run.json"),
               json_encode(list(pid = pid, port = 50001L, url = "http://127.0.0.1:50001/",
                                version = 1L, started = artifact_time(),
                                create_time = create_time, parent_pid = owner)))
  }
  orphan = sleeper_handle()
  plant("orphan", orphan$pid, proc_create_time(orphan$pid), dead$get_pid())
  reused = sleeper_handle()
  plant("reused", reused$pid, proc_create_time(reused$pid) - 100, dead$get_pid())
  owned = sleeper_handle()
  owner = sleeper_handle()
  plant("owned", owned$pid, proc_create_time(owned$pid), owner$pid)
  expect_identical(artifact_sweep(), "orphan")
  deadline = Sys.time() + 10
  while (orphan$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_false(orphan$alive())
  expect_true(reused$alive())
  expect_true(owned$alive())
  expect_false(file.exists(file.path(artifact_dir("orphan"), "run", "run.json")))
  expect_true(file.exists(file.path(artifact_dir("owned"), "run", "run.json")))
  expect_true(artifact_state$swept)
})
