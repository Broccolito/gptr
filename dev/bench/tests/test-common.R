test_that("bench_root() finds the repository from a sub-directory", {
  expect_identical(bench_root(), normalizePath(file.path("..", "..", ".."), winslash = "/"))
  expect_error(bench_root(tempdir()), "cannot find the gptr repository root")
})

test_that("bench_args() parses --check, --update and --only", {
  a = bench_args(c("--check", "--only=T1_git,T2_script"))
  expect_true(a$check)
  expect_false(a$update)
  expect_identical(a$only, c("T1_git", "T2_script"))
  expect_null(bench_args(character())$only)
})

test_that("bench_utf8() marks valid UTF-8 without re-encoding it", {
  x = rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  y = bench_utf8(x)
  expect_identical(Encoding(y), "UTF-8")
  expect_identical(charToRaw(y), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
})

test_that("bench_require() signals bench_missing_tool naming the package", {
  cnd = tryCatch(bench_require("notapkg.p24", "a test"), error = function(e) e)
  expect_s3_class(cnd, "bench_missing_tool")
  expect_identical(cnd$package, "notapkg.p24")
  expect_match(conditionMessage(cnd), "stops for the maintainer", fixed = TRUE)
})

test_that("bench_regression() builds the contract's condition class", {
  cnd = bench_regression(c("a", "b"), "polyglot-B", "total", 10, 12)
  expect_identical(class(cnd), c("gptr_error_token_regression", "gptr_error", "error",
                                 "condition"))
  expect_identical(conditionMessage(cnd), "a\nb")
  expect_identical(cnd$metric, "total")
})

test_that("bench_run() maps success, regressions, errors and missing tools to 0, 1, 1, 2", {
  expect_identical(bench_run(function() NULL), 0L)
  regress = function() stop(bench_regression("r", "f", "m", 1, 2))
  expect_identical(suppressMessages(bench_run(regress)), 1L)
  expect_identical(suppressMessages(bench_run(function() stop("boom"))), 1L)
  expect_identical(suppressMessages(bench_run(function() bench_require("notapkg.p24", "x"))), 2L)
})

test_that("bench_write_csv() writes LF line ends and round-trips", {
  path = withr::local_tempfile(fileext = ".csv")
  df = data.frame(task = c("a", "b"), variant = "B", total = c(1.5, 2))
  bench_write_csv(df, path)
  raw = readBin(path, "raw", file.size(path))
  expect_false(any(raw == as.raw(0x0d)))
  expect_equal(bench_read_csv(path), df)
  expect_null(bench_read_csv(file.path(tempdir(), "absent-p24.csv")))
})

test_that("tok_count() counts o200k tokens", {
  skip_if_not_installed("rtiktoken")
  expect_identical(tok_count(c("hello world", "")), c(2L, 0L))
  expect_identical(tok_count(character()), integer())
})
