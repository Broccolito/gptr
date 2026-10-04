# The calibrated estimator (Task 9; architecture section 12.5; report G2 part f).

token_fixture = function() {
  path = testthat::test_path("fixtures", "tokens", "counts.json")
  json_decode(readLines(path, encoding = "UTF-8"))
}

test_that("est_tokens() is within 15% median absolute error on the fixture (05 P01 acceptance 4)", {
  samples = token_fixture()
  expect_length(samples, 12L)
  errors = vapply(samples, function(s) {
    (est_tokens(s$text, s$class) - s$o200k) / s$o200k
  }, numeric(1))
  expect_lte(stats::median(abs(errors)), 0.15)
})

test_that("est_tokens() uses the class constants and the non-ASCII weights", {
  expect_identical(est_tokens(strrep("a", 436), "prose"), 100)
  expect_identical(est_tokens(strrep("a", 213), "r_output"), 100)
  expect_identical(est_tokens(strrep("\u4e2d", 100), "prose"), ceiling(84.8))
  expect_identical(est_tokens(strrep("\u00e9", 100), "prose"), 35)
  expect_identical(est_tokens(c("ab", "cd"), "code"), est_tokens("ab\ncd", "code"))
  expect_identical(est_tokens(character()), 0)
  expect_identical(est_tokens(NULL), 0)
  expect_error(est_tokens("x", "html"), class = "gptr_error_invalid_argument")
})

test_that("est_tokens() counts characters, not bytes, in a C locale", {
  old = Sys.getlocale("LC_CTYPE")
  withr::defer(Sys.setlocale("LC_CTYPE", old))
  skip_if(!nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))), "cannot use the C locale")
  expect_identical(
    est_tokens("abc \xe4\xbd\xa0\xe5\xa5\xbd", "prose"), est_tokens("abc \u4f60\u597d", "prose")
  )
})

test_that("est_image_tokens() follows the provider formulas", {
  expect_identical(est_image_tokens(768, 512), 532)
  expect_identical(est_image_tokens(1400, 1000), 1551)
  expect_identical(est_image_tokens(10000, 10000), 1521)
  expect_identical(est_image_tokens(768, 512, api = "openai-responses"), ceiling(24 * 16 * 1.2))
  expect_identical(est_image_tokens(768, 512, api = "google-generative-ai"), 1120)
})

test_that("est_multiplier() updates by EWMA only for large enough estimates", {
  state = est_multiplier(NULL, estimated = 100, reported = 500, prior = 1.35)
  expect_identical(state, list(m = 1.35, n = 0L))
  state = est_multiplier(state, estimated = 1000, reported = 1350)
  expect_equal(state$m, exp(0.5 * log(1.35) + 0.5 * log(1.35)))
  expect_identical(state$n, 1L)
  state = est_multiplier(state, estimated = 1000, reported = 10000)
  expect_equal(state$m, exp(0.5 * log(1.35) + 0.5 * log(3)))
})
