# Content-sensitive cache policy; native Windows filesystem witnesses live in
# test-windows-security.R. These tests keep the metadata stamp fixed deliberately.

local_content_stamp = function(path, .env = parent.frame()) {
  info = file.info(path, extra_cols = FALSE)
  info$mtime = info$ctime = Sys.time() - 10
  stamp = settings_file_stamp
  testthat::local_mocked_bindings(
    settings_content_hash = function(paths) {
      vapply(paths, trust_file_hash, "", USE.NAMES = FALSE)
    },
    settings_file_stamp = function(path) stamp(path, info = info), .env = .env
  )
  invisible(info)
}

test_that("file SHA256 preserves byte identity for binary and empty inputs", {
  path = withr::local_tempfile()
  bytes = c(as.raw(0:255), charToRaw("caf\u00e9\r\n"))
  writeBin(bytes, path)
  expect_identical(trust_file_hash(path), hash_sha256(bytes))
  writeBin(raw(), path)
  expect_identical(trust_file_hash(path), hash_sha256(raw()))
  expect_identical(trust_file_hash(paste0(path, ".missing")), "unreadable")
})

test_that("content-sensitive settings reuse a parsed value and invalidate unchanged metadata", {
  local_gw()
  path = settings_path("user", create = TRUE)
  writeLines('{"mode":"plan"}', path)
  info = local_content_stamp(path)
  calls = new.env(parent = emptyenv())
  calls$n = 0L
  decode = settings_decode
  local_mocked_bindings(settings_decode = function(...) {
    calls$n = calls$n + 1L
    decode(...)
  })
  expect_identical(settings_read("user")$mode, "plan")
  expect_identical(settings_read("user")$mode, "plan")
  expect_identical(calls$n, 1L)
  expect_false(is.null(get0(path, envir = gateway_state()$files, inherits = FALSE)))
  writeLines('{"mode":"auto"}', path)
  expect_identical(file.size(path), info$size)
  expect_identical(settings_read("user")$mode, "auto")
  expect_identical(settings_read("user")$mode, "auto")
  expect_identical(calls$n, 2L)
})

test_that("a settings rewrite during decoding cannot publish a mismatched cache entry", {
  local_gw()
  path = settings_path("user", create = TRUE)
  writeLines('{"mode":"plan"}', path)
  local_content_stamp(path)
  decode = settings_decode
  calls = new.env(parent = emptyenv())
  calls$n = 0L
  local_mocked_bindings(settings_decode = function(...) {
    calls$n = calls$n + 1L
    value = decode(...)
    if (calls$n == 1L) writeLines('{"mode":"auto"}', path)
    value
  })
  expect_identical(settings_read("user")$mode, "plan")
  expect_null(get0(path, envir = gateway_state()$files, inherits = FALSE))
  expect_identical(settings_read("user")$mode, "auto")
  expect_false(is.null(get0(path, envir = gateway_state()$files, inherits = FALSE)))
  expect_identical(settings_read("user")$mode, "auto")
  expect_identical(calls$n, 2L)
})

test_that("an unavailable content digest never serves or retains stale settings", {
  local_gw()
  path = settings_path("user", create = TRUE)
  writeLines('{"mode":"plan"}', path)
  local_content_stamp(path)
  expect_identical(settings_read("user")$mode, "plan")
  expect_false(is.null(get0(path, envir = gateway_state()$files, inherits = FALSE)))
  writeLines('{"mode":"auto"}', path)
  local_mocked_bindings(settings_content_hash = function(paths) rep("unreadable", length(paths)))
  expect_identical(settings_read("user")$mode, "auto")
  expect_null(get0(path, envir = gateway_state()$files, inherits = FALSE))
})

test_that("content-sensitive trust verifies each hit and reuses its current file hashes", {
  project = local_gw()
  path = file.path(project, ".gptr", "settings.json")
  writeLines('{"mode":"plan"}', path)
  calls = new.env(parent = emptyenv())
  calls$n = 0L
  hash = trust_file_hash
  local_mocked_bindings(
    settings_content_hash = function(paths) {
      vapply(paths, trust_file_hash, "", USE.NAMES = FALSE)
    },
    trust_file_hash = function(path) {
      calls$n = calls$n + 1L
      hash(path)
    }
  )
  first = trust_fingerprint(project)
  expect_identical(calls$n, 1L)
  expect_identical(first$files, stats::setNames(hash(path), ".gptr/settings.json"))
  expect_identical(trust_fingerprint(project), first)
  expect_identical(calls$n, 2L)
  writeLines('{"mode":"auto"}', path)
  second = trust_fingerprint(project)
  expect_identical(calls$n, 3L)
  expect_false(identical(second$fp, first$fp))
  expect_identical(second$files, stats::setNames(hash(path), ".gptr/settings.json"))
})
