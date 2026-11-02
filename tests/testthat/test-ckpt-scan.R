scan_worker_library = function(.env = parent.frame()) {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (file.exists(file.path(path, "R", "aaa-state.R"))) local_worker_lib(.env)
}

test_that("checkpoint workers keep the caller store and inspect known absences", {
  scan_worker_library()
  root = local_project(files = list("source.R" = "answer = 42", "empty.txt" = character()))
  local_gptr_options(checkpoint_scan_timeout = 15)
  old = data.frame(path = "gone.R", size = 3, mtime = 1, link = FALSE)
  result = ckpt_scan_run(root, ckpt_prune(root), old, baseline = TRUE)
  expect_true(result$complete)
  expect_setequal(result$walk$path, c("source.R", "empty.txt"))
  expect_identical(result$absent, "gone.R")
  expect_setequal(names(result$hash), result$walk$path)
  expect_true(all(vapply(result$hash, function(h) !is.null(ckpt_blob_find(h)), logical(1))))
  expect_gte(result$seconds, result$walk_seconds)
  expect_false(result$capture_capped)
})

test_that("capture limits preserve complete inventory and source files get priority", {
  scan_worker_library()
  root = local_project()
  paths = sprintf("a%03d.bin", seq_len(270L))
  expect_true(all(file.create(file.path(root, paths))))
  writeLines("priority = TRUE", file.path(root, "z.R"))
  local_gptr_options(checkpoint_scan_timeout = 20)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
  expect_true(result$capture_capped)
  expect_length(result$hash, 256L)
  expect_equal(nrow(result$walk), 271L)
  expect_true("z.R" %in% names(result$hash))
  expect_true(all(result$uncaptured == "capture limit"))
})

test_that("the entry cap leaves undiscovered files unknown", {
  scan_worker_library()
  root = local_project()
  expect_true(all(file.create(file.path(root, sprintf("f%04d", seq_len(2005L))))))
  local_gptr_options(checkpoint_scan_timeout = 30)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_false(result$complete)
  expect_identical(result$reason, "entry limit")
  expect_lte(nrow(result$walk), 2000L)
  expect_length(result$absent, 0L)
})

test_that("workers never capture protected paths, links or FIFOs", {
  scan_worker_library()
  root = local_project(files = list("source.R" = "x = 1", ".secrets/key.txt" = "synthetic",
                                   ".env" = "SYNTHETIC_KEY=example"))
  local_gptr_options(checkpoint_scan_timeout = 15)
  if (!is_windows()) {
    expect_true(file.symlink(file.path(root, "source.R"), file.path(root, "link.R")))
    pipe = file.path(root, "pipe")
    fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
    withr::defer(close(fifo))
  }
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
  expect_identical(names(result$hash), "source.R")
  expect_identical(unname(result$uncaptured[[".env"]]), "protected or control path")
  if (!is_windows()) {
    expect_identical(unname(result$uncaptured[["pipe"]]), "not a regular file")
    expect_identical(unname(result$uncaptured[["link.R"]]), "symbolic link")
  }
})

test_that("known files use the changed-file cap and directory replacements are present", {
  scan_worker_library()
  root = local_project(files = list("known.R" = "longer content", "new.R" = "longer content"))
  dir.create(file.path(root, "was-file"))
  local_gptr_options(checkpoint_scan_timeout = 15, checkpoint_track_file_max = 1,
                     checkpoint_capture_max = 100, checkpoint_track_total = 1000)
  old = data.frame(path = c("known.R", "was-file"), size = 1, mtime = 1, link = FALSE)
  result = ckpt_scan_run(root, ckpt_prune(root), old)
  expect_true(result$complete)
  expect_setequal(names(result$hash), c("known.R", "new.R"))
  expect_identical(result$not_files, "was-file")
  expect_length(result$absent, 0L)
  expect_length(result$uncaptured, 0L)
})

test_that("follow-up new files obey the changed-file capture cap", {
  scan_worker_library()
  root = local_project(files = list("new.R" = "longer than ten bytes"))
  local_gptr_options(checkpoint_scan_timeout = 15, checkpoint_track_file_max = 1e6,
                     checkpoint_capture_max = 10)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = FALSE)
  expect_true(result$complete)
  expect_length(result$hash, 0L)
  expect_identical(unname(result$uncaptured[["new.R"]]), "file size limit")
})

test_that("case-only renames retire the old spelling even on insensitive filesystems", {
  scan_worker_library()
  root = local_project(files = list("Readme.md" = "original"))
  local_gptr_options(checkpoint_scan_timeout = 15)
  before = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(file.rename(file.path(root, "Readme.md"), file.path(root, "readme.md")))
  if (fs_case_insensitive(root)) expect_true(file.exists(file.path(root, "Readme.md")))
  after = ckpt_scan_run(root, ckpt_prune(root), before$walk, before$hash)
  expect_true(after$complete)
  expect_identical(after$absent, "Readme.md")
  expect_identical(after$walk$path, "readme.md")
  expect_identical(names(after$hash), "readme.md")
})

test_that("timeout kills the worker and retains only committed capture records", {
  root = local_project(files = list("source.R" = "answer = 42"))
  local_gptr_options(checkpoint_scan_timeout = 2)
  state = new.env(parent = emptyenv())
  original = proc_rscript
  probe = function(dir, source, blob, record) {
    dir.create(dirname(blob), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(source, blob))
    pending = file.path(dir, "pending.rds")
    saveRDS(record, pending)
    stopifnot(file.rename(pending, file.path(dir, "00001.rds")))
    Sys.sleep(30)
  }
  hash = hash_file(file.path(root, "source.R"))
  record = list(row = data.frame(path = "source.R", size = 12, mtime = 1, link = FALSE),
                hash = hash, mode = 384L)
  local_mocked_bindings(proc_rscript = function(entry, args, dir, env, stdout, stderr, .on_spawn) {
    original("artifact", list(dir, file.path(root, "source.R"),
      ckpt_blob_path(hash, ""), record), dir = dir, env = env, stdout = stdout,
      stderr = stderr, .fun = probe, .on_spawn = function(p) {
        state$p = p
        .on_spawn(p)
      })
  })
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_false(result$complete)
  expect_true(result$reason %in% c("time limit", "worker stopped"))
  expect_lt(result$seconds, 4.5)
  expect_identical(unname(result$hash[["source.R"]]), hash)
  expect_true(file.exists(ckpt_blob_find(hash)))
  state$p$wait(1000L)
  ckpt_scan_reap()
  expect_false(state$p$is_alive())
})

test_that("an unreaped scan prevents another worker from starting", {
  state = new.env(parent = emptyenv())
  state$is_alive = function() TRUE
  state$kill = function(...) invisible(TRUE)
  before = get0("ckpt_scan_pending", envir = the, inherits = FALSE)
  withr::defer({
    the$ckpt_scan_pending = before
  })
  the$ckpt_scan_pending = list(p = state, dir = tempdir())
  local_mocked_bindings(proc_rscript = function(...) stop("must not spawn"))
  result = ckpt_scan_run(tempdir(), character())
  expect_false(result$complete)
  expect_identical(result$reason, "cleanup pending")
})
