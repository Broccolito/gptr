# tests/testthat/test-ckpt-files.R -- the blob store, garbage collection, the tracker and the
# guarded 3-way restores (P16).

blob_count = function() {
  length(list.files(file.path(workspace_root(create = FALSE), "checkpoints", "blobs"),
                    recursive = TRUE))
}

test_that("the blob store deduplicates, compresses small text and restores atomically", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines(c("x = 1", "y = 2"), f)
  h = ckpt_store_put(f)
  expect_match(h, "^[0-9a-f]{32}$")
  blob = ckpt_blob_find(h)
  expect_true(endsWith(blob, ".gz"))
  expect_match(blob, "/.gptr/checkpoints/blobs/", fixed = TRUE)
  n0 = blob_count()
  f2 = file.path(proj, "copy.R")
  file.copy(f, f2)
  expect_identical(ckpt_store_put(f2), h)
  expect_identical(blob_count(), n0)
  writeLines("changed", f)
  expect_true(ckpt_store_get(h, f))
  expect_identical(readLines(f), c("x = 1", "y = 2"))
  expect_false(ckpt_store_get(strrep("0", 32L), f))
  expect_false(ckpt_store_get("../../copy.R", file.path(proj, "out.R")))
  expect_identical(ckpt_store_put(character()), character())
})

test_that("already-compressed files are stored raw and come back byte for byte", {
  proj = local_project()
  f = file.path(proj, "d.rds")
  saveRDS(1:10, f)
  h = ckpt_store_put(f)
  expect_false(endsWith(ckpt_blob_find(h), ".gz"))
  out = file.path(proj, "restored", "d.rds")
  expect_true(ckpt_store_get(h, out))
  expect_identical(readBin(out, "raw", 1e4), readBin(f, "raw", 1e4))
  g = file.path(proj, "e.rds")
  saveRDS(11:20, g)
  blobs = dirname(ckpt_blob_path(hash_file(g), ""))
  dir.create(blobs, showWarnings = FALSE)
  Sys.chmod(blobs, "0555", use_umask = FALSE)
  withr::defer(Sys.chmod(blobs, "0755", use_umask = FALSE))
  skip_if(file.access(blobs, 2L) == 0L, "the directory stays writable")
  expect_error(suppressWarnings(ckpt_store_put(g)), class = "gptr_error_workspace")
})

test_that("without a workspace the store lives under tempdir(), never in the project", {
  proj = local_project(gptr = FALSE)
  f = file.path(proj, "a.txt")
  writeLines("a", f)
  h = ckpt_store_put(f)
  expect_true(startsWith(path_norm(ckpt_blob_find(h)), path_norm(tempdir())))
  expect_false(dir.exists(file.path(proj, ".gptr")))
})

test_that("blob GC keeps referenced and young blobs and deletes old unreferenced ones", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  make = function(txt) {
    f = tempfile(fileext = ".txt", tmpdir = proj)
    writeLines(txt, f)
    ckpt_store_put(f)
  }
  h_ref = make("referenced")
  h_old = make("old and unreferenced")
  h_new = make("young and unreferenced")
  old = Sys.time() - 40 * 86400
  Sys.setFileTime(ckpt_blob_find(h_ref), old)
  Sys.setFileTime(ckpt_blob_find(h_old), old)
  Sys.setFileTime(ckpt_blob_find(h_new), old)
  expect_identical(make("young and unreferenced"), h_new)
  sdir = file.path(root, "sessions")
  writeLines(c('{"type":"session","version":3,"id":"s0000000001"}',
               paste0('{"type":"custom","id":"a1b2c3d4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"a.R","pre":"', h_ref, '"}]}}}}')),
             file.path(sdir, "20260930T000000_s0000000001.jsonl"))
  stale = file.path(root, "checkpoints", "blobs", "ab", paste0(strrep("ab", 16L), ".tmp-1"))
  dir.create(dirname(stale), showWarnings = FALSE)
  writeLines("interrupted", stale)
  Sys.setFileTime(stale, old)
  spills = file.path(root, "checkpoints", "objects", c("s0000000001", "s0000000099"))
  for (d in spills) dir.create(d, recursive = TRUE)
  Sys.setFileTime(spills, old)
  res = ckpt_gc(root, days = 30)
  expect_false(file.exists(stale))
  expect_false(res$skipped)
  expect_identical(res$deleted, 1L)
  expect_false(is.null(ckpt_blob_find(h_ref)))
  expect_null(ckpt_blob_find(h_old))
  expect_false(is.null(ckpt_blob_find(h_new)))
  expect_identical(dir.exists(spills), c(TRUE, FALSE))
  idx = jsonlite::fromJSON(file.path(root, "checkpoints", "index.json"), simplifyVector = FALSE)
  expect_setequal(names(idx$blobs), c(h_ref, h_new))
  local_gptr_options(quiet = FALSE, checkpoint_disk_bytes = 1)
  expect_message(ckpt_gc(root, days = 30), "above gptr.checkpoint_disk_bytes",
                 class = "gptr_message_notice")
})

test_that("blob GC skips while another live process holds a session lock (IC-71)", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("old and unreferenced", f)
  h_old = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h_old), Sys.time() - 40 * 86400)
  sf = file.path(root, "sessions", "20260930T000000_s0000000002.jsonl")
  writeLines('{"type":"session","version":3,"id":"s0000000002"}', sf)
  dir.create(paste0(sf, ".lock"))
  writeLines(c("999999", "1790000000.5"), file.path(paste0(sf, ".lock"), "pid"))
  local_mocked_bindings(pid_alive = function(pid, create_time = NULL) TRUE)
  res = ckpt_gc(root, days = 30)
  expect_true(res$skipped)
  expect_false(is.null(ckpt_blob_find(h_old)))
  local_mocked_bindings(pid_alive = function(pid, create_time = NULL) FALSE)
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_null(ckpt_blob_find(h_old))
})

test_that("pruning in one process keeps the blobs another live process's session references", {
  skip_on_cran()
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("held by the other session", f)
  h = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h), Sys.time() - 40 * 86400)
  other = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(other$kill())
  sf = file.path(root, "sessions", "20260930T000000_s0000000003.jsonl")
  writeLines(c('{"type":"session","version":3,"id":"s0000000003"}',
               paste0('{"type":"custom","id":"b1c2d3e4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"x.R","pre":"', h, '"}]}}}}')), sf)
  dir.create(paste0(sf, ".lock"))
  writeLines(c(as.character(other$get_pid()), ""), file.path(paste0(sf, ".lock"), "pid"))
  expect_true(ckpt_gc(root, days = 30)$skipped)
  other$kill()
  other$wait(5000)
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_false(is.null(ckpt_blob_find(h)))
})
