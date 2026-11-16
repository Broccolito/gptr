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

# Two scans of a tree holding every kind of entry a scan decides on: a first one, then one from its
# walk plus stale known paths after `swap.R` became a link out of the root. Their results without
# the seconds, and without the sizes of directory links (a directory's size depends on the OS).
scan_fixture_rows = function() {
  root = local_project()
  outside = withr::local_tempdir()
  put = function(rel, text, dir = root) {
    path = file.path(dir, rel)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(text), path)
  }
  files = c("source.R" = "x = 1\n", "notes.md" = "# notes\n", "readme.md" = "read me\n",
            ".env" = "SYNTHETIC=1\n", "big.bin" = strrep("b", 200L), "swap.R" = "swap\n",
            "sub/a.R" = "a = 1\n", "sub/deep/b.txt" = "b\n", "locked.txt" = "locked\n",
            "closed/c.txt" = "c\n", ".git/HEAD" = "ref\n", "node_modules/m.js" = "m\n")
  for (rel in names(files)) put(rel, files[[rel]])
  put("known.R", "outside\n", outside)
  put("swap.R", "outside swap\n", outside)
  targets = c(file.path(root, c("source.R", "missing", "sub")), outside)
  expect_true(all(file.symlink(targets, file.path(root, c("link.R", "dangling", "ldir", "out")))))
  fifo = processx::conn_create_fifo(file.path(root, "pipe"), read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  expect_true(all(Sys.chmod(file.path(root, names(files)), "0644", use_umask = FALSE)))
  stamped = c(file.path(root, c(names(files), "pipe", "sub", "sub/deep")), outside,
              file.path(outside, c("known.R", "swap.R")))
  expect_true(all(Sys.setFileTime(stamped, as.POSIXct(1e9, origin = "1970-01-01", tz = "UTC"))))
  locked = file.path(root, c("locked.txt", "closed"))
  withr::defer(Sys.chmod(locked, "0700", use_umask = FALSE))
  expect_true(all(Sys.chmod(locked, "0000", use_umask = FALSE)))
  skip_if(file.access(locked[[1L]], 4L) == 0L, "permissions do not prevent this user from reading")
  local_gptr_options(checkpoint_scan_timeout = 30, checkpoint_track_file_max = 100)
  first = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  unlink(file.path(root, "swap.R"))
  expect_true(file.symlink(file.path(outside, "swap.R"), file.path(root, "swap.R")))
  stale = c("README.md", "out/known.R", "gone.R", "sub", "closed/c.txt", ".git/HEAD", "../escape.R")
  old = rbind(first$walk, data.frame(path = stale, size = 1, mtime = 1, link = FALSE))
  second = ckpt_scan_run(root, ckpt_prune(root), old)
  rows = function(s) {
    s$seconds = NULL
    s$walk$size[s$walk$path %in% c("ldir", "out")] = NA
    s
  }
  list(first = rows(first), second = rows(second))
}

test_that("a scan's rows, captures and reasons equal main's on a tree of every entry kind", {
  skip_on_os("windows")
  expect_identical(scan_fixture_rows(), dget(test_path("fixtures", "ckpt-scan-rows.txt")))
})

test_that("a scan checks each folder's entries with one call per check", {
  calls = function(k, ...) {
    root = local_project()
    for (d in c("a", "b", "c")) {
      dir.create(file.path(root, d))
      for (i in seq_len(k)) writeBin(charToRaw("x"), file.path(root, d, sprintf("f%02d.txt", i)))
    }
    local_gptr_options(checkpoint_scan_timeout = 30, ...)
    n = local_calls(c("ckpt_is_link", "ckpt_regular"))
    s = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
    expect_true(s$complete)
    c(n(), captured = length(s$hash))
  }
  few = calls(2L, checkpoint_track_total = 0)
  many = calls(40L, checkpoint_track_total = 0)
  expect_identical(few, many)
  # the known paths, the root and its three folders; a capture checks its file again first
  expect_identical(many[["ckpt_regular"]], 5L)
  held = calls(40L)
  expect_identical(held[["ckpt_regular"]], 5L + held[["captured"]])
})

test_that("an entry or folder swapped for a link after its folder's checks is never read", {
  skip_on_os("windows")
  root = local_project(files = list("b.R" = "b = 1", "sub/a.R" = "a = 1"))
  outside = withr::local_tempdir()
  writeLines("synthetic outside content", file.path(outside, "a.R"))
  local_gptr_options(checkpoint_scan_timeout = 30)
  # each swap runs as path_class() classes its entry, after the entry's link and type checks
  swaps = list("b.R" = c(file.path(outside, "a.R"), "b.R"), "sub/a.R" = c(outside, "sub"))
  classify = path_class
  local_mocked_bindings(path_class = function(path, ...) {
    for (rel in names(swaps)[file.path(root, names(swaps)) %in% path]) {
      unlink(file.path(root, swaps[[rel]][[2L]]), recursive = TRUE)
      expect_true(file.symlink(swaps[[rel]][[1L]], file.path(root, swaps[[rel]][[2L]])))
    }
    classify(path, ...)
  })
  s = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_identical(s$uncaptured[c("b.R", "sub/a.R")],
                   c(b.R = "symbolic link", `sub/a.R` = "not a regular file"))
  expect_length(s$hash, 0L)
  expect_null(ckpt_blob_find(hash_file(file.path(outside, "a.R")), ckpt_store_root(root)))
})

test_that("a file deleted between its folder's stat and type checks is unread, the rest kept", {
  skip_on_os("windows")
  root = local_project(files = list("a.R" = "a = 1", "b.R" = "b = 1", "c.R" = "c = 1",
                                    "sub/d.R" = "d = 1"))
  local_gptr_options(checkpoint_scan_timeout = 30)
  regular = ckpt_regular
  # the root's type check finds b.R gone; it fails as one call, so each entry is checked alone
  local_mocked_bindings(ckpt_regular = function(full) {
    if (length(full) > 1L) unlink(file.path(root, "b.R"))
    regular(full)
  })
  s = ckpt_scan_run(root, ckpt_prune(root), baseline = TRUE)
  expect_identical(s$reason, "a path could not be read")
  expect_setequal(s$walk$path, c("a.R", "c.R", "sub/d.R"))
  expect_setequal(names(s$hash), s$walk$path)
})
