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

test_that("lines_fit() keeps the most leading lines, with a notice of the omitted count", {
  lines = sprintf("row %02d of some printed words", 1:40)
  k = lines_fit(lines, 50, "r_output")
  expect_lte(est_tokens(lines[seq_len(k)], "r_output"), 50)
  expect_gt(est_tokens(lines[seq_len(k + 1L)], "r_output"), 50)
  more = function(m) if (m > 0L) sprintf("(+ %d more)", m)
  j = lines_fit(lines, 50, "r_output", more)
  expect_lte(est_tokens(c(lines[seq_len(j)], more(40L - j)), "r_output"), 50)
  expect_gt(est_tokens(c(lines[seq_len(j + 1L)], more(39L - j)), "r_output"), 50)
  expect_identical(lines_fit(c("~ a", "~ b"), 4, "r_output", function(m) if (m) "(+ 9 more)"), 2L)
  expect_identical(lines_fit(character(), 10, "r_output"), 0L)
  expect_identical(lines_fit(lines, Inf, "r_output"), 40L)
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

test_that("image dimensions reject non-finite and complex values with typed errors", {
  for (value in list(Inf, -Inf, NaN, NA_real_, 1 + 1i)) {
    for (api in c("anthropic", "openai-responses", "google-generative-ai")) {
      expect_error(est_image_tokens(value, 512, api), class = "gptr_error_invalid_argument")
      expect_error(est_image_tokens(768, value, api), class = "gptr_error_invalid_argument")
    }
  }
})

test_that("non-finite or complex usage cannot corrupt estimator calibration", {
  state = list(m = 1.35, n = 2L)
  for (value in list(Inf, -Inf, NaN, NA_real_, 1 + 1i)) {
    expect_identical(est_multiplier(state, value, 1000), state)
    expect_identical(est_multiplier(state, 1000, value), state)
  }
  expect_identical(est_multiplier(NULL, Inf, Inf, prior = 1), list(m = 1, n = 0L))
})

test_that("new estimator calibration requires a positive finite real prior", {
  for (prior in list(Inf, -Inf, NaN, NA_real_, 1 + 1i, 0, -1, c(1, 2))) {
    expect_error(est_multiplier(NULL, 1000, 1000, prior),
                 class = "gptr_error_invalid_argument")
  }
})
