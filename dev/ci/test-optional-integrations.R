# Pure result-gate tests. Run before the dedicated integration runner is implemented.
runner_path = if (file.exists("optional-integrations.R")) "optional-integrations.R" else
  file.path("dev", "ci", "optional-integrations.R")
source(runner_path, local = TRUE)

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
    structure(list(message = "controlled error"), class = c("expectation_error", "condition")),
    structure(list(message = "controlled failure"), class = c("expectation_failure", "condition")),
    structure(list(message = "controlled warning"), class = c("expectation_warning", "condition")),
    simpleWarning("controlled outside warning"))))
  row = optional_result_rows(result)[[1L]]
  testthat::expect_identical(row$passed, 1L)
  testthat::expect_identical(row$failed, 2L)
  testthat::expect_identical(row$warnings, 2L)
  testthat::expect_identical(row$skipped, 0L)
})

testthat::test_that("raw diagnostic messages survive a failed gate within explicit bounds", {
  names = c("expectation_skip", "expectation_failure", "expectation_error", "expectation_warning")
  conditions = lapply(names, function(name) {
    structure(list(message = paste("controlled", name)), class = c(name, "condition"))
  })
  conditions[[5L]] = simpleWarning(paste(rep("x", 2001L), collapse = ""))
  row = optional_result_rows(list(list(test = "controlled diagnostics",
    results = conditions)))[[1L]]
  testthat::expect_identical(row$diagnostic_conditions_total, 5L)
  testthat::expect_false(row$diagnostic_conditions_truncated)
  testthat::expect_identical(vapply(row$diagnostics[1:4], function(x) x$message, ""),
                            paste("controlled", names))
  testthat::expect_identical(row$diagnostics[[1L]]$classes, c("expectation_skip", "condition"))
  testthat::expect_identical(nchar(row$diagnostics[[5L]]$message), 2000L)
  testthat::expect_true(row$diagnostics[[5L]]$message_truncated)
  testthat::expect_error(optional_gate(list(row), "test-artifact-app.R", FALSE), "Failed")
  testthat::expect_identical(length(row$diagnostics), 5L)
  many = optional_result_rows(list(list(test = "controlled many", results =
    rep(list(simpleWarning("controlled repeated warning")), 26L))))[[1L]]
  testthat::expect_identical(many$warnings, 26L)
  testthat::expect_identical(many$diagnostic_conditions_total, 26L)
  testthat::expect_identical(length(many$diagnostics), 25L)
  testthat::expect_true(many$diagnostic_conditions_truncated)
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

testthat::test_that("every approved writer prototype case must execute assertions on both hosts", {
  file = "test-proc-writer-prototype.R"
  titles = c(
    "owned writer prototype preserves every 4 MB duplex stdout and stderr line",
    "owned writer prototype returns a typed no-reader stdin timeout",
    "owned writer prototype cancels a queued 4 MB write without a late exit",
    "owned writer prototype preserves queued binary NUL and UTF-8 bytes")
  rows = lapply(titles, record)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_error(optional_gate(rows[-1L], file, windows), "Missing mandatory")
    for (i in seq_along(rows)) {
      no_assertions = rows
      no_assertions[[i]]$passed = 0L
      testthat::expect_error(optional_gate(no_assertions, file, windows), "assertions")
      skipped = rows
      skipped[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(skipped, file, windows), "Skipped")
    }
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
  }
})

testthat::test_that("the pure sampler regressions remain mandatory on both hosts", {
  file = "test-proc-backpressure-sampling.R"
  titles = c(
    "backpressure enumeration tolerates only a dead original parent exit race",
    "backpressure enumeration preserves the returned original child handles",
    "backpressure enumeration fails closed for live and unknown parent identities",
    "backpressure sample diagnostics are bounded and omit arbitrary messages")
  testthat::expect_identical(optional_titles[[file]], titles)
  rows = lapply(titles, record)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_error(optional_gate(rows[-1L], file, windows), "Missing mandatory")
    skipped = rows
    skipped[[1L]]$skipped = 1L
    testthat::expect_error(optional_gate(skipped, file, windows), "Skipped")
    no_assertions = rows
    no_assertions[[1L]]$passed = 0L
    testthat::expect_error(optional_gate(no_assertions, file, windows), "assertions")
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
  }
})

testthat::test_that("existing Windows ctime guards never excuse skipped content-cache coverage", {
  guards = c("a settings file is parsed once per change, a same-size rewrite included",
    "a gated file rewritten at the same size with its old mtime still voids trust")
  titles = c("file SHA256 preserves byte identity for binary and empty inputs",
    "content-sensitive settings reuse a parsed value and invalidate unchanged metadata",
    "a settings rewrite during decoding cannot publish a mismatched cache entry",
    "an unavailable content digest never serves or retains stale settings",
    "content-sensitive trust verifies each hit and reuses its current file hashes")
  file = "test-config-content-cache.R"
  testthat::expect_identical(optional_titles[[file]], titles)
  for (guard in guards) {
    testthat::expect_true(optional_allowed_skip("test-gptr-config.R", guard, TRUE))
    testthat::expect_false(optional_allowed_skip("test-gptr-config.R", guard, FALSE))
    testthat::expect_false(optional_allowed_skip(file, guard, TRUE))
  }
  rows = lapply(titles, record)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
    for (i in seq_along(rows)) {
      skipped = rows
      skipped[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(skipped, file, windows), "Skipped")
    }
  }
  original = lapply(c(
    "a trust decision taken in this process lapses when a gated file changes (IC-52)",
    "gptr's own write keeps an in-process decision without recording it (IC-52)"), record)
  guarded = c(original, lapply(guards, record, passed = 0L, skipped = 1L))
  testthat::expect_true(optional_gate(guarded, "test-gptr-config.R", TRUE)$passed)
  testthat::expect_error(optional_gate(c(original, list(record("unrelated config skip",
    passed = 0L, skipped = 1L))), "test-gptr-config.R", TRUE), "Skipped")
})

testthat::test_that("family settlement waits for descendants after the root has stopped", {
  clock = new.env(parent = emptyenv())
  clock$seconds = 0
  clock$polls = 0L
  remaining = function() {
    clock$polls = clock$polls + 1L
    if (clock$polls < 3L) list("owned fixture") else list()
  }
  value = optional_wait_family(function() TRUE, remaining,
    now = function() clock$seconds,
    pause = function(seconds) {
      clock$seconds = clock$seconds + seconds
    })
  testthat::expect_true(value$settled)
  testthat::expect_identical(value$remaining_marked_processes, 0L)
  testthat::expect_identical(value$settlement_polls, 3L)
  testthat::expect_gt(value$settlement_elapsed_s, 0)
  testthat::expect_lte(value$settlement_elapsed_s, 5)
})

testthat::test_that("family settlement bounds live roots and propagates query errors", {
  for (root_stopped in c(FALSE, TRUE)) {
    clock = new.env(parent = emptyenv())
    clock$seconds = 0
    value = optional_wait_family(function() root_stopped,
      function() if (root_stopped) list("owned fixture") else list(),
      now = function() clock$seconds,
      pause = function(seconds) {
        clock$seconds = clock$seconds + seconds
      })
    testthat::expect_false(value$settled)
    testthat::expect_identical(value$root_stopped, root_stopped)
    testthat::expect_equal(value$settlement_elapsed_s, 5)
  }
  testthat::expect_error(optional_wait_family(function() TRUE,
    function() stop("controlled marker query failed")), "controlled marker query failed")
})

testthat::test_that("an unhandled promise in either owned log remains a hard failure", {
  folder = withr::local_tempdir()
  paths = file.path(folder, c("fixture-stdout.log", "fixture.log"))
  for (path in paths) writeLines("controlled ordinary fixture output", path)
  testthat::expect_no_error(optional_check_logs(paths))
  for (path in paths) {
    writeLines("Unhandled promise error: controlled fixture", path)
    testthat::expect_error(optional_check_logs(paths), "Unhandled browser promise error")
    writeLines("controlled ordinary fixture output", path)
  }
})
