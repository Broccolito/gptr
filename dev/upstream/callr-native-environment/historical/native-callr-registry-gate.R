testthat::test_that("native callr profiles require complete positive rows on both hosts", {
  file = "test-callr-parent-environment.R"
  expected = c(
  "a native callr worker launch preserves actual-empty parent entries and its r_process contract",
  "a native callr artifact launch preserves actual-empty parent entries and its r_process contract")
  testthat::expect_identical(optional_titles[[file]], expected)
  testthat::expect_identical(length(expected), 2L)
  testthat::expect_identical(anyDuplicated(expected), 0L)
  testthat::expect_error(optional_select("^test-callr-parent-environment\\.R$", tempdir()),
                         "Missing selected")
  rows = lapply(expected, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
    testthat::expect_false(result$platform_guard_only)
    testthat::expect_identical(result$mandatory_cases, expected)
    testthat::expect_length(result$platform_guard_cases, 0L)
    for (i in seq_along(expected)) {
      title = expected[[i]]
      testthat::expect_false(optional_allowed_skip(file, title, windows))
      testthat::expect_false(optional_allowed_skip("test-proc-writer-runtime.R", title, windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      messages = c(passed = "assertions", failed = "Failed", warnings = "Warnings")
      for (field in names(messages)) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows), messages[[field]])
      }
      late = rows
      late[[i]]$passed = 3L
      late[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(late, file, windows), "Skipped")
      for (kind in c("expectation_error", "expectation_warning")) {
        raw = rows
        raw[[i]] = optional_result_rows(list(list(test = title, results = list(
          structure(list(), class = "expectation_success"),
          structure(list(message = "controlled callr parent condition"),
            class = c(kind, "condition"))))))[[1L]]
        testthat::expect_error(optional_gate(raw, file, windows))
      }
    }
    unknown = record("unrelated callr parent capability guard", passed = 3L, skipped = 1L)
    testthat::expect_error(optional_gate(c(rows, list(unknown)), file, windows), "Skipped")
  }
})

