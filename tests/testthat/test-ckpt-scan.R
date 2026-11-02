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
  skip_on_cran()
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
  skip_on_cran()
  scan_worker_library()
  root = local_project()
  expect_true(all(file.create(file.path(root, sprintf("f%04d", seq_len(2005L))))))
  local_gptr_options(checkpoint_scan_timeout = 30)
  # Count real ignored entries without making the entry-cap assertion race slow Windows I/O.
  result = ckpt_scan_run(root, c(ckpt_prune(root), "f*"), baseline = TRUE)
  expect_false(result$complete)
  expect_identical(result$reason, "entry limit")
  expect_equal(nrow(result$walk), 0L)
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
  after = ckpt_scan_run(root, ckpt_prune(root), before$walk)
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

test_that("a result read failure preserves the previous checkpoint observations", {
  scan_worker_library()
  root = local_project(files = list("a.R" = "old-a", "b.R" = "old-b"))
  local_gptr_options(checkpoint_scan_timeout = 15, quiet = TRUE)
  ck = ckpt_ck_new("s0000000801")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  before = list(stat = tr$stat, hash = tr$hash, mode = tr$mode, absent = tr$absent)
  writeLines("changed-a", file.path(root, "a.R"))
  writeLines("changed-b", file.path(root, "b.R"))
  seen = new.env(parent = emptyenv())
  seen$records = 0L
  read = readRDS
  run = ckpt_scan_run
  environment(run) = list2env(list(readRDS = function(file, ...) {
    if (grepl("^[0-9]{5}[.]rds$", basename(file))) {
      seen$records = seen$records + 1L
      if (seen$records == 2L) stop("synthetic result read failure")
    }
    read(file, ...)
  }), parent = environment(run))
  local_mocked_bindings(ckpt_scan_run = run)
  result = ckpt_files_scan(tr)
  expect_identical(seen$records, 2L)
  expect_false(result$complete)
  expect_identical(result$reason, "worker unavailable")
  expect_equal(nrow(result$walk), 0L)
  for (field in c("hash", "mode", "absent", "not_files", "uncaptured")) {
    expect_length(result[[field]], 0L)
  }
  ckpt_files_observe(tr, result)
  expect_identical(tr$stat, before$stat)
  expect_identical(tr$hash, before$hash)
  expect_identical(tr$mode, before$mode)
  expect_identical(tr$absent, before$absent)
  expect_false(tr$coverage)
})

test_that("a worker exiting during manifest collection cannot certify a frozen partial result", {
  scan_worker_library()
  root = local_project(files = list("first.R" = "first", "last.R" = "last"))
  local_gptr_options(checkpoint_scan_timeout = 0.01)
  paths = c("first.R", "last.R")
  full = file.path(root, paths)
  info = file.info(full)
  hashes = ckpt_store_put(full)
  records = lapply(seq_along(paths), function(i) {
    list(row = data.frame(path = paths[i], size = info$size[i],
                          mtime = as.numeric(info$mtime[i]), link = FALSE),
         hash = hashes[i], mode = ckpt_modes(full[i]))
  })
  publish = function(dir, records) {
    for (i in seq_along(records)) {
      pending = file.path(dir, "pending.rds")
      saveRDS(records[[i]], pending)
      stopifnot(file.rename(pending, file.path(dir, sprintf("%05d.rds", i))))
      if (i == 1L) {
        while (!file.exists(file.path(dir, "release"))) Sys.sleep(0.01)
      }
    }
    saveRDS(list(complete = TRUE, capture_capped = FALSE, reason = "", walk_seconds = 0),
            file.path(dir, "finished.rds"))
  }
  seen = new.env(parent = emptyenv())
  seen$p = NULL
  seen$published = 0L
  withr::defer(if (!is.null(seen$p) && seen$p$is_alive()) seen$p$kill(grace = 0))
  original = proc_rscript
  local_mocked_bindings(proc_rscript = function(entry, args, dir, env, stdout, stderr, .on_spawn) {
    p = original("artifact", list(dir, records), dir = dir, env = env, stdout = stdout,
                  stderr = stderr, .fun = publish, .on_spawn = function(p) {
                    seen$p = p
                    .on_spawn(p)
                  })
    deadline = Sys.time() + 15
    while (!file.exists(file.path(dir, "00001.rds")) && p$is_alive() && Sys.time() < deadline) {
      Sys.sleep(0.01)
    }
    stopifnot(file.exists(file.path(dir, "00001.rds")))
    Sys.sleep(0.02)
    p
  })
  run = ckpt_scan_run
  environment(run) = list2env(list(list.files = function(path, pattern, ...) {
    frozen = base::list.files(path, pattern = pattern, ...)
    stopifnot(file.create(file.path(path, "release")))
    seen$p$wait(10000L)
    stopifnot(!seen$p$is_alive(), file.exists(file.path(path, "finished.rds")))
    seen$published = length(base::list.files(path, pattern = pattern))
    frozen
  }), parent = environment(run))
  result = run(root, ckpt_prune(root), baseline = TRUE)
  expect_identical(seen$published, 2L)
  expect_equal(nrow(result$walk), 1L)
  expect_identical(names(result$hash), "first.R")
  expect_false(result$complete)
  expect_identical(result$reason, "time limit")
  expect_false(seen$p$is_alive())
})
