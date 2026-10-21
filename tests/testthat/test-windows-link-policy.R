# Windows link policy regressions, with canonical-path results injected on every host.
# Actual native file/directory links and containment guards live in test-windows-security.R.

local_win_alias = function(alias, target, .env = parent.frame()) {
  canonical = path_norm
  alias = canonical(alias)
  target = canonical(target)
  testthat::local_mocked_bindings(is_windows = function() TRUE,
    path_norm = function(path) {
      out = canonical(path)
      exact = out == alias
      below = startsWith(out, paste0(alias, "/"))
      out[exact] = target
      out[below] = paste0(target, substring(out[below], nchar(alias) + 1L))
      out
    }, .env = .env)
}

test_that("Windows text reads canonical file bytes despite empty alias metadata", {
  root = path_norm(withr::local_tempdir())
  target = file.path(root, "real.md")
  alias = file.path(root, "alias.md")
  bytes = c(as.raw(c(239, 187, 191)), charToRaw("safe linked instruction\r\n"))
  writeBin(bytes, target)
  file.create(alias)
  expect_identical(file.size(alias), 0)
  local_win_alias(alias, target)
  value = read_utf8(alias)
  expect_identical(value$text, "safe linked instruction\n")
  expect_identical(value$eol, "\r\n")
  expect_true(value$bom)
  expect_true(value$final_newline)
})

test_that("Windows writes use the canonical target when readlink reports no link", {
  skip_on_cran()
  root = path_norm(withr::local_tempdir())
  target = file.path(root, "real.R")
  alias = file.path(root, "alias.R")
  writeBin(charToRaw("x = 1\r\n"), target)
  file.create(alias)
  expect_identical(Sys.readlink(alias), "")
  local_win_alias(alias, target)
  value = write_file(alias, "x = 2\n")
  expect_identical(readBin(target, "raw", 100L), charToRaw("x = 2\r\n"))
  expect_identical(value$details$path, target)
  expect_identical(file.size(alias), 0)
})

test_that("Windows direct link policy distinguishes a link from its ordinary descendants", {
  skip_on_cran()
  root = path_norm(withr::local_tempdir())
  target = file.path(root, "real")
  alias = file.path(root, "alias")
  dir.create(target)
  dir.create(alias)
  writeLines("owned", file.path(target, "data.txt"))
  writeLines("owned", file.path(alias, "data.txt"))
  local_win_alias(alias, target)
  expect_true(ckpt_is_link(alias))
  expect_false(ckpt_is_link(target))
  expect_false(ckpt_is_link(file.path(alias, "data.txt")))
  guard = ckpt_restore_guard(file.path(alias, "data.txt"))
  expect_false(guard$ok)
  expect_identical(guard$reason, "through a symbolic link")
})

test_that("Windows checkpoint walks list directory links without descending into them", {
  skip_on_cran()
  root = local_project()
  target = file.path(root, "data")
  alias = file.path(root, "data-link")
  dir.create(target)
  dir.create(alias)
  writeLines("id\n1", file.path(target, "x.csv"))
  writeLines("unexpected alias child", file.path(alias, "unexpected.txt"))
  local_win_alias(alias, target)
  value = ckpt_walk(root)
  expect_true("data-link" %in% value$path)
  expect_true(value$link[value$path == "data-link"])
  expect_false("data-link/unexpected.txt" %in% value$path)
  expect_true("data/x.csv" %in% value$path)
})

test_that("Windows checkpoint capture refuses a direct file link", {
  skip_on_cran()
  root = local_project()
  target = file.path(root, "real.txt")
  alias = file.path(root, "alias.txt")
  writeLines("owned", target)
  file.create(alias)
  local_win_alias(alias, target)
  expect_true(ckpt_is_link(alias))
  expect_false(ckpt_capturable(alias))
  expect_true(ckpt_capturable(target))
})
