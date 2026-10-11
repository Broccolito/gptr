# Pure result-gate tests. Run before the dedicated integration runner is implemented.
source("dev/ci/optional-integrations.R", local = TRUE)

record = function(test, passed = 1L, skipped = 0L, failed = 0L, warnings = 0L) {
  list(test = test, passed = passed, skipped = skipped, failed = failed, warnings = warnings)
}

testthat::test_that("no files and missing selected files cannot pass", {
  testthat::expect_error(optional_select("does-not-exist", tempdir()), "No approved")
  testthat::expect_error(optional_select("doc-knitr", tempdir()), "Missing selected")
})

testthat::test_that("a mandatory Quarto integration may not silently skip", {
  name = "quarto render records a #| label agent chunk and the next render replays it"
  testthat::expect_error(optional_gate(list(record(name, skipped = 1L)),
                                      "test-doc-knitr.R", FALSE), "Skipped")
  testthat::expect_true(optional_gate(list(record(name)), "test-doc-knitr.R", FALSE)$passed)
})

testthat::test_that("warnings, missing assertions and failed mandatory cases fail", {
  name = "grep agrees with ripgrep on (file, line) pairs"
  testthat::expect_error(optional_gate(list(record(name, warnings = 1L)),
                                      "test-tool-search.R", FALSE), "Warnings")
  testthat::expect_error(optional_gate(list(record(name, passed = 0L)),
                                      "test-tool-search.R", FALSE), "assertions")
  testthat::expect_error(optional_gate(list(record(name, failed = 1L)),
                                      "test-tool-search.R", FALSE), "Failed")
  testthat::expect_error(optional_gate(list(record("unrelated")),
                                      "test-tool-search.R", FALSE), "Missing mandatory")
})

testthat::test_that("raw testthat errors and warnings cannot disappear from result counts", {
  result = list(list(test = "raw condition fixture", results = list(
    structure(list(), class = "expectation_success"),
    structure(list(), class = "expectation_error"),
    structure(list(), class = "expectation_failure"),
    structure(list(), class = "expectation_warning"),
    structure(list(), class = c("simpleWarning", "warning", "condition")))))
  row = optional_result_rows(result)[[1L]]
  testthat::expect_identical(row$passed, 1L)
  testthat::expect_identical(row$failed, 2L)
  testthat::expect_identical(row$warnings, 2L)
  testthat::expect_identical(row$skipped, 0L)
})

testthat::test_that("only named platform guards are allowed to skip", {
  name = "the access token is 128 random bits from openssl or /dev/urandom"
  testthat::expect_true(optional_allowed_skip("test-artifact-app.R", name, TRUE))
  testthat::expect_false(optional_allowed_skip("test-artifact-app.R", name, FALSE))
  testthat::expect_false(optional_allowed_skip("test-artifact-app.R",
    "the session check passes a working app and returns a 1000x700 screenshot", TRUE))
  testthat::expect_false(optional_allowed_skip("test-tool-search.R", "unknown", TRUE))
  testthat::expect_true(optional_allowed_skip("test-bridge-lang.R",
    "the cmd engine is refused outside Windows", TRUE))
  testthat::expect_false(optional_allowed_skip("test-bridge-lang.R",
    "the cmd engine is refused outside Windows", FALSE))
})

testthat::test_that("Windows security platform guards never excuse Windows coverage", {
  name = "Windows safe instruction links remain while escaped and guarded inputs stay private"
  testthat::expect_true(optional_allowed_skip("test-windows-security.R", name, FALSE))
  testthat::expect_false(optional_allowed_skip("test-windows-security.R", name, TRUE))
  testthat::expect_error(optional_gate(list(record(name, skipped = 1L)),
                                      "test-windows-security.R", TRUE), "Skipped")
})
