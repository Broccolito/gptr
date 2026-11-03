# Partial inventories must never turn a missing observation into proof of absence.
partial_scan = function(paths = character(), hashes = character(), absent = character(),
                         complete = FALSE, not_files = character()) {
  info = path_info(fs_path(file.path(project_root(), paths)))
  list(walk = data.frame(path = paths, size = info$size, mtime = as.numeric(info$mtime),
                         link = rep(FALSE, length(paths))),
       hash = hashes, mode = stats::setNames(rep(420L, length(hashes)), names(hashes)),
       absent = absent, not_files = not_files, complete = complete,
       reason = if (complete) "" else "entry limit", capture_capped = FALSE,
       uncaptured = character(), seconds = 0)
}

test_that("partial discovery never calls an unvisited existing file created", {
  proj = local_project(files = list("seen.R" = "old", "unseen.R" = "keep me"))
  next_scan = partial_scan("seen.R", c(seen.R = ckpt_store_put("seen.R")))
  local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
  ck = ckpt_ck_new("s0000000201")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  next_scan = partial_scan(c("seen.R", "unseen.R"),
                          c(seen.R = tr$hash[["seen.R"]],
                            unseen.R = ckpt_store_put("unseen.R")))
  expect_length(ckpt_files_step(tr), 0L)
  expect_identical(readLines(file.path(proj, "unseen.R")), "keep me")
})

test_that("a partial scan retains unvisited preimages and proves deletions separately", {
  local_project(files = list("a.R" = "original", "b.R" = "keep"))
  next_scan = partial_scan(c("a.R", "b.R"),
                          c(a.R = ckpt_store_put("a.R"), b.R = ckpt_store_put("b.R")))
  local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
  ck = ckpt_ck_new("s0000000202")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  original = tr$hash[["a.R"]]
  next_scan = partial_scan("b.R", c(b.R = tr$hash[["b.R"]]))
  expect_length(ckpt_files_step(tr), 0L)
  expect_identical(tr$hash[["a.R"]], original)
  expect_true("a.R" %in% tr$stat$path)
  unlink("a.R")
  next_scan = partial_scan("b.R", c(b.R = tr$hash[["b.R"]]), absent = "a.R")
  rows = ckpt_files_step(tr)
  expect_length(rows, 1L)
  expect_identical(rows[[1L]]$status, "deleted")
  expect_identical(rows[[1L]]$pre, original)
})

test_that("predicted writes outside an incomplete inventory still have exact preimages", {
  local_project(files = list("unseen.R" = "original"))
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan())
  ck = ckpt_ck_new("s0000000203")
  call = list(id = "c", name = "write", input = list(path = "unseen.R", content = "new"))
  tok = ckpt_files_before(ck, call)
  writeLines("new", "unseen.R")
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(frag$files[[1L]]$status, "modified")
  expect_true(frag$files[[1L]]$restorable)
  expect_true(ckpt_files_undo(ck, frag)$ok)
  expect_identical(readLines("unseen.R"), "original")
})

test_that("CLI late targets are not mistaken for start-of-turn preimages", {
  local_project(files = list("unseen.R" = "original"))
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan())
  ck = ckpt_ck_new("s0000000204")
  ckpt_files_sync(ckpt_files_tr(ck))
  writeLines("native CLI edit", "unseen.R")
  call = list(id = "c", name = "write", input = list(path = "unseen.R", content = "new"))
  tok = ckpt_files_before(ck, call, sync = FALSE)
  expect_false(tok$exact)
  writeLines("new", "unseen.R")
  frag = ckpt_files_after(ck, call, tok)
  expect_length(frag$files, 0L)
  expect_identical(frag$coverage, "partial")
})

test_that("complete and partial inventories preserve proven creations and absence", {
  local_project(files = list("a.R" = "old"))
  next_scan = partial_scan("a.R", c(a.R = ckpt_store_put("a.R")), complete = TRUE)
  local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
  ck = ckpt_ck_new("s0000000205")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  writeLines("new", "b.R")
  next_scan = partial_scan("b.R", c(b.R = ckpt_store_put("b.R")))
  rows = ckpt_files_step(tr)
  expect_identical(rows[[1L]]$status, "created")
  expect_identical(rows[[1L]]$path, "b.R")
  expect_false(tr$complete)
  unlink("a.R")
  next_scan = partial_scan(absent = "a.R")
  expect_identical(ckpt_files_step(tr)[[1L]]$status, "deleted")
  writeLines("recreated", "a.R")
  next_scan = partial_scan("a.R", c(a.R = ckpt_store_put("a.R")), complete = TRUE)
  expect_identical(ckpt_files_step(tr)[[1L]]$status, "created")
  expect_true(tr$complete)
})

test_that("a complete later inventory does not repair earlier partial undo coverage", {
  local_project(files = list("a.R" = "old", "unseen.R" = "keep"))
  next_scan = partial_scan("a.R", c(a.R = ckpt_store_put("a.R")))
  local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
  ck = ckpt_ck_new("s0000000206")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  writeLines("changed", "a.R")
  next_scan = partial_scan(c("a.R", "unseen.R"),
                          c(a.R = ckpt_store_put("a.R"),
                            unseen.R = ckpt_store_put("unseen.R")), complete = TRUE)
  frag = ckpt_files_turn_scan(ck, 1L)
  expect_identical(frag$coverage, "partial")
  expect_identical(frag$files[[1L]]$path, "a.R")
  expect_true(tr$complete)
  expect_true(tr$coverage)
})

test_that("missing follow-up captures cannot certify unchanged contents from metadata alone", {
  for (reason in c("capture limit", "unreadable file")) {
    local_project(files = list("known.R" = "AAAA"))
    stamp = as.POSIXct(1e9, origin = "1970-01-01", tz = "UTC")
    Sys.setFileTime("known.R", stamp)
    next_scan = partial_scan("known.R", c(known.R = ckpt_store_put("known.R")), complete = TRUE)
    local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
    ck = ckpt_ck_new("s0000000210")
    ckpt_files_sync(ckpt_files_tr(ck))
    writeBin(charToRaw("BBBB\n"), "known.R")
    Sys.setFileTime("known.R", stamp)
    next_scan = partial_scan("known.R", complete = TRUE)
    next_scan$capture_capped = TRUE
    next_scan$uncaptured = c(known.R = reason)
    next_scan$reason = reason
    fragment = ckpt_files_turn_scan(ck, 1L, force = TRUE)
    expect_length(fragment$files, 0L)
    expect_identical(fragment$coverage, "partial")
    report = ckpt_files_undo(ck, fragment)
    expect_identical(report$item, "file coverage")
    expect_false(report$ok)
    expect_identical(readLines("known.R"), "BBBB")
  }
})

test_that("coverage-only fragments tell undo that unobserved changes remain", {
  local_project(files = list("unseen.R" = "old"))
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan())
  ck = ckpt_ck_new("s0000000207")
  ckpt_files_sync(ckpt_files_tr(ck))
  writeLines("unobserved edit", "unseen.R")
  frag = ckpt_files_turn_scan(ck, 1L)
  expect_length(frag$files, 0L)
  expect_identical(frag$coverage, "partial")
  items = ckpt_files_undo(ck, frag)
  expect_identical(items$item, "file coverage")
  expect_false(items$ok)
  expect_match(items$action, "unobserved file changes may remain", fixed = TRUE)
  expect_identical(ckpt_files_describe(frag), "file coverage: automatic scan incomplete")
  expect_identical(readLines("unseen.R"), "unobserved edit")
})

test_that("a CLI deletion of an unknown target is not proof of original absence", {
  local_project(files = list("unseen.R" = "original"))
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan())
  ck = ckpt_ck_new("s0000000208")
  ckpt_files_sync(ckpt_files_tr(ck))
  unlink("unseen.R")
  call = list(id = "c", name = "write", input = list(path = "unseen.R", content = "new"))
  tok = ckpt_files_before(ck, call, sync = FALSE)
  expect_false(tok$exact)
  writeLines("new", "unseen.R")
  frag = ckpt_files_after(ck, call, tok)
  expect_length(frag$files, 0L)
  expect_identical(frag$coverage, "partial")
})

test_that("CLI targets outside the inventory cannot acquire late originals", {
  local_project()
  target = withr::local_tempfile(fileext = ".R")
  writeLines("original", target)
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan())
  ck = ckpt_ck_new("s0000000209")
  ckpt_files_sync(ckpt_files_tr(ck))
  writeLines("native CLI edit", target)
  call = list(id = "c", name = "write", input = list(path = target, content = "new"))
  tok = ckpt_files_before(ck, call, sync = FALSE)
  expect_false(tok$exact)
  writeLines("new", target)
  frag = ckpt_files_after(ck, call, tok)
  expect_length(frag$files, 0L)
  expect_identical(frag$coverage, "partial")
})

test_that("CLI metadata matches cannot prove uncaptured original contents", {
  local_project(files = list("known.R" = "old"))
  old_time = as.POSIXct(1e9, origin = "1970-01-01", tz = "UTC")
  Sys.setFileTime("known.R", old_time)
  local_mocked_bindings(ckpt_scan_run = function(...) partial_scan("known.R"))
  ck = ckpt_ck_new("s0000000210")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  writeBin(charToRaw("new\n"), "known.R")
  Sys.setFileTime("known.R", old_time)
  expect_identical(as.numeric(file.mtime("known.R")), tr$stat$mtime)
  expect_identical(file.size("known.R"), tr$stat$size)
  call = list(id = "c", name = "write", input = list(path = "known.R", content = "own"))
  tok = ckpt_files_before(ck, call, sync = FALSE)
  expect_false(tok$exact)
  writeLines("own", "known.R")
  frag = ckpt_files_after(ck, call, tok)
  expect_length(frag$files, 0L)
  expect_identical(frag$coverage, "partial")
})

test_that("a partial sync gives no pre-image to an edit or deletion made outside gptr", {
  for (change in c("edit", "delete")) {
    local_project(files = list("a.R" = "original", "b.R" = "keep"))
    next_scan = partial_scan(c("a.R", "b.R"),
                            c(a.R = ckpt_store_put("a.R"), b.R = ckpt_store_put("b.R")),
                            complete = TRUE)
    local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
    ck = ckpt_ck_new("s0000000211")
    tr = ckpt_files_tr(ck)
    ckpt_files_sync(tr)
    # between turns, the person edits or deletes a.R; the next sync does not reach it
    if (change == "edit") writeLines("USER EDIT", "a.R") else unlink("a.R")
    next_scan = partial_scan("b.R", c(b.R = tr$hash[["b.R"]]))
    ckpt_files_sync(tr)
    next_scan = if (change == "edit") {
      partial_scan(c("a.R", "b.R"), c(a.R = ckpt_store_put("a.R"), b.R = tr$hash[["b.R"]]))
    } else {
      partial_scan("b.R", c(b.R = tr$hash[["b.R"]]), absent = "a.R")
    }
    frag = ckpt_files_turn_scan(ck, 2L, force = TRUE)
    expect_false(any(vapply(frag$files, function(r) isTRUE(r$restorable), NA)))
    ckpt_files_undo(ck, frag)
    if (change == "edit") {
      expect_identical(readLines("a.R"), "USER EDIT")
    } else {
      expect_false(file.exists("a.R"))
    }
  }
})

test_that("a file recreated outside gptr after a proven absence is not undone as created", {
  local_project(files = list("a.R" = "first", "b.R" = "keep"))
  next_scan = partial_scan(c("a.R", "b.R"),
                          c(a.R = ckpt_store_put("a.R"), b.R = ckpt_store_put("b.R")))
  local_mocked_bindings(ckpt_scan_run = function(...) next_scan)
  ck = ckpt_ck_new("s0000000212")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  unlink("a.R")
  next_scan = partial_scan("b.R", c(b.R = tr$hash[["b.R"]]), absent = "a.R")
  expect_identical(ckpt_files_turn_scan(ck, 1L, force = TRUE)$files[[1L]]$status, "deleted")
  # between turns, the person recreates a.R; the next sync does not reach it
  writeLines("USER FILE", "a.R")
  next_scan = partial_scan("b.R", c(b.R = tr$hash[["b.R"]]))
  ckpt_files_sync(tr)
  next_scan = partial_scan(c("a.R", "b.R"), c(a.R = ckpt_store_put("a.R"), b.R = tr$hash[["b.R"]]))
  frag = ckpt_files_turn_scan(ck, 2L, force = TRUE)
  ckpt_files_undo(ck, frag)
  expect_identical(readLines("a.R"), "USER FILE")
})
