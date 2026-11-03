test_that("scans keep the caller store and inspect known absences", {
  root = local_project(files = list("source.R" = "answer = 42", "empty.txt" = character()))
  local_gptr_options(checkpoint_scan_timeout = 15)
  old = data.frame(path = "gone.R", size = 3, mtime = 1, link = FALSE)
  result = ckpt_scan_run(root, ckpt_prune(root), old, baseline = TRUE)
  expect_true(result$complete)
  expect_setequal(result$walk$path, c("source.R", "empty.txt"))
  expect_identical(result$absent, "gone.R")
  expect_setequal(names(result$hash), result$walk$path)
  expect_true(all(vapply(result$hash, function(h) !is.null(ckpt_blob_find(h)), logical(1))))
})

test_that("capture limits preserve complete inventory and source files get priority", {
  skip_on_cran()
  root = local_project()
  paths = sprintf("a%03d.bin", seq_len(270L))
  expect_true(all(file.create(file.path(root, paths))))
  writeLines("priority = TRUE", file.path(root, "z.R"))
  local_gptr_options(checkpoint_scan_timeout = 20)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
  expect_length(result$hash, 256L)
  expect_equal(nrow(result$walk), 271L)
  expect_true("z.R" %in% names(result$hash))
  expect_true(all(result$uncaptured == "capture limit"))
})

test_that("captures respect the aggregate byte cap, including empty files", {
  root = local_project()
  writeBin(charToRaw("alpha001"), "a.R")
  writeBin(charToRaw("bravo002"), "b.R")
  writeBin(charToRaw("charl003"), "c.R")
  expect_true(file.create("empty.R"))
  local_gptr_options(checkpoint_scan_timeout = 15, checkpoint_track_file_max = 100,
                     checkpoint_track_total = 16)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_true(result$complete)
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

test_that("the entry cap leaves undiscovered files unknown", {
  skip_on_cran()
  root = local_project()
  expect_true(all(file.create(file.path(root, sprintf("f%04d", seq_len(2005L))))))
  local_gptr_options(checkpoint_scan_timeout = 30)
  # Count real ignored entries without making the entry-cap assertion race slow Windows I/O.
  result = ckpt_scan_run(root, c(ckpt_prune(root), "f*"), baseline = TRUE)
  expect_false(result$complete)
  expect_identical(result$reason, "the folder has more than 2,000 entries")
  expect_equal(nrow(result$walk), 0L)
  expect_length(result$absent, 0L)
})

test_that("scans never capture protected paths, startup files, links or FIFOs", {
  root = local_project(files = list("source.R" = "x = 1", ".secrets/key.txt" = "synthetic",
                                   ".env" = "SYNTHETIC_KEY=example",
                                   "ordinary-profile.txt" = "SYNTHETIC_PROFILE_SENTINEL"))
  withr::local_envvar(R_PROFILE_USER = file.path(root, "ordinary-profile.txt"))
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
  for (path in c(".env", "ordinary-profile.txt")) {
    expect_identical(unname(result$uncaptured[[path]]), "protected or control path")
  }
  if (!is_windows()) {
    expect_identical(unname(result$uncaptured[["pipe"]]), "not a regular file")
    expect_identical(unname(result$uncaptured[["link.R"]]), "symbolic link")
  }
})

test_that("known files use the changed-file cap and directory replacements are present", {
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
  root = local_project(files = list("new.R" = "longer than ten bytes"))
  local_gptr_options(checkpoint_scan_timeout = 15, checkpoint_track_file_max = 1e6,
                     checkpoint_capture_max = 10)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = FALSE)
  expect_true(result$complete)
  expect_length(result$hash, 0L)
  expect_identical(unname(result$uncaptured[["new.R"]]), "file size limit")
})

test_that("case-only renames retire the old spelling even on insensitive filesystems", {
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

test_that("the time budget stops a scan between entries and keeps what it completed", {
  root = local_project(files = list("a.R" = "a", "b.R" = "b", "c.R" = "c"))
  local_gptr_options(checkpoint_scan_timeout = 1)
  put = ckpt_store_put
  local_mocked_bindings(ckpt_store_put = function(path, store) {
    Sys.sleep(1.2)
    put(path, store)
  })
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_false(result$complete)
  expect_identical(result$reason, "it ran out of time (gptr.checkpoint_scan_timeout)")
  expect_identical(result$walk$path, "a.R")
  expect_identical(names(result$hash), "a.R")
  expect_false(is.null(ckpt_blob_find(result$hash[["a.R"]])))
})

test_that("a zero budget scans nothing and invalid budgets are refused", {
  root = local_project(files = list("a.R" = "a"))
  local_gptr_options(checkpoint_scan_timeout = 0)
  result = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_false(result$complete)
  expect_identical(result$reason, "it ran out of time (gptr.checkpoint_scan_timeout)")
  expect_equal(nrow(result$walk), 0L)
  for (bad in list(-1, "2", NA_real_, c(1, 2))) {
    local_gptr_options(checkpoint_scan_timeout = bad)
    expect_error(ckpt_scan_run(root, ckpt_prune(root)), class = "gptr_error_invalid_argument")
  }
})

test_that("an interrupt the person continues from stops the scan and keeps its records", {
  root = local_project(files = list("a.R" = "a", "b.R" = "b"))
  local_gptr_options(checkpoint_scan_timeout = 15)
  interrupt = structure(list(message = "synthetic interrupt", call = NULL),
                        class = c("interrupt", "condition"))
  put = ckpt_store_put
  local_mocked_bindings(ckpt_store_put = function(path, store) {
    hash = put(path, store)
    withRestarts(signalCondition(interrupt), resume = function() NULL)
    hash
  })
  # the pause menu's continue resumes the interrupted code
  result = withCallingHandlers(ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE),
                               interrupt = function(cnd) invokeRestart("resume"))
  expect_false(result$complete)
  expect_identical(result$reason, "it was interrupted")
  expect_identical(names(result$hash), "a.R")
  # an interrupt that aborts keeps unwinding
  expect_identical(tryCatch(ckpt_scan_run(root, ckpt_prune(root)), interrupt = identity), interrupt)
})
