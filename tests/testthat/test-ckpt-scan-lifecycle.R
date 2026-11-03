scan_lifecycle_library = function(.env = parent.frame()) {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (file.exists(file.path(path, "R", "aaa-state.R"))) local_worker_lib(.env)
}

test_that("real scanner captures respect the aggregate byte cap, including empty files", {
  scan_lifecycle_library()
  root = local_project()
  writeBin(charToRaw("alpha001"), "a.R")
  writeBin(charToRaw("bravo002"), "b.R")
  writeBin(charToRaw("charl003"), "c.R")
  expect_true(file.create("empty.R"))
  local_gptr_options(checkpoint_scan_timeout = 15, checkpoint_track_file_max = 100,
                     checkpoint_track_total = 16)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
  expect_true(result$capture_capped)
  expect_setequal(result$walk$path, c("a.R", "b.R", "c.R", "empty.R"))
  expect_setequal(names(result$hash), c("a.R", "b.R", "empty.R"))
  expect_identical(unname(result$uncaptured[["c.R"]]), "capture limit")
  expect_equal(sum(file.size(names(result$hash))), 16)
  for (path in names(result$hash)) {
    restored = withr::local_tempfile()
    expect_true(ckpt_store_get(result$hash[[path]], restored, ckpt_store_root(root)))
    expect_identical(readBin(restored, "raw", n = file.size(restored)),
                     readBin(path, "raw", n = file.size(path)))
  }
})

test_that("real scanner excludes custom startup paths despite its reset child environment", {
  scan_lifecycle_library()
  root = local_project(files = list("source.R" = "answer = 42",
    "ordinary-profile.txt" = "SYNTHETIC_PROFILE_SENTINEL",
    "ordinary-environ.txt" = "SYNTHETIC_ENVIRON_SENTINEL"))
  startup = c(R_PROFILE_USER = file.path(root, "ordinary-profile.txt"),
              R_ENVIRON_USER = file.path(root, "ordinary-environ.txt"))
  withr::local_envvar(startup)
  reset = child_env("worker")[names(startup)]
  expect_true(all(!is.na(reset) & reset != startup))
  local_gptr_options(checkpoint_scan_timeout = 15)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
  expect_identical(names(result$hash), "source.R")
  for (path in basename(startup)) {
    expect_identical(unname(result$uncaptured[[path]]), "protected or control path")
  }
  expect_identical(Sys.getenv(names(startup)), startup)
  blobs = list.files(file.path(ckpt_store_root(root), "blobs"), recursive = TRUE,
                      full.names = TRUE)
  expect_length(blobs, 1L)
  text = vapply(blobs, function(path) {
    bytes = readBin(path, "raw", n = file.size(path))
    rawToChar(if (endsWith(path, ".gz")) memDecompress(bytes, "gzip") else bytes)
  }, "")
  expect_false(any(grepl("SYNTHETIC_", text, fixed = TRUE)))
})

test_that("interrupting after a real scanner spawn settles its process and launch files", {
  scan_lifecycle_library()
  root = local_project(files = list("source.R" = "answer = 42"))
  local_gptr_options(checkpoint_scan_timeout = 15)
  expect_null(get0("ckpt_scan_pending", envir = the, inherits = FALSE))
  state = new.env(parent = emptyenv())
  state$p = NULL
  state$dir = NULL
  withr::defer({
    if (!is.null(state$p)) {
      if (state$p$is_alive()) state$p$kill(grace = 0)
      state$p$wait(1000L)
      ckpt_scan_reap()
    }
    if (!is.null(state$dir) && dir.exists(state$dir) &&
          (is.null(state$p) || !state$p$is_alive())) unlink(state$dir, recursive = TRUE)
  })
  original = proc_rscript
  interrupt = structure(list(message = "owned scanner interruption", call = NULL),
                         class = c("scanner_test_interrupt", "interrupt", "condition"))
  local_mocked_bindings(proc_rscript = function(entry, args, dir, env, stdout, stderr, .on_spawn) {
    p = original(entry, args, dir = dir, env = env, stdout = stdout, stderr = stderr,
      .on_spawn = function(child) {
        state$p = child
        state$dir = dir
        .on_spawn(child)
      })
    state$alive = p$is_alive()
    state$registered = !is.null(proc_record(p$get_pid(), process = p))
    state$launch_present = file.exists(file.path(dir, "bootstrap.rds"))
    signalCondition(interrupt)
    p
  })
  caught = tryCatch(ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE),
                    interrupt = identity)
  expect_identical(caught, interrupt)
  expect_true(state$alive)
  expect_true(state$registered)
  expect_true(state$launch_present)
  expect_true(inherits(state$p, "process"))
  state$p$wait(1000L)
  ckpt_scan_reap()
  expect_false(state$p$is_alive())
  expect_false(dir.exists(state$dir))
  expect_null(proc_record(state$p$get_pid(), process = state$p))
  expect_null(get0("ckpt_scan_pending", envir = the, inherits = FALSE))
})
