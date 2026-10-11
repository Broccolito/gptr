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
  testthat::expect_error(optional_gate(list(record("unapproved")),
    "test-unapproved.R", FALSE), "Unapproved")
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

testthat::test_that("injected Windows link policy cases are mandatory on both actual hosts", {
  file = "test-windows-link-policy.R"
  titles = c(
    "Windows text reads canonical file bytes despite empty alias metadata",
    "Windows writes use the canonical target when readlink reports no link",
    "Windows direct link policy distinguishes a link from its ordinary descendants",
    "Windows checkpoint walks list directory links without descending into them",
    "Windows checkpoint capture refuses a direct file link")
  testthat::expect_identical(optional_titles[[file]], titles)
  rows = lapply(titles, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
    testthat::expect_false(result$platform_guard_only)
    testthat::expect_identical(result$mandatory_cases, titles)
    testthat::expect_identical(result$platform_guard_cases, character())
    for (i in seq_along(rows)) {
      testthat::expect_false(optional_allowed_skip(file, titles[[i]], windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      messages = c(failed = "Failed", warnings = "Warnings", skipped = "Skipped",
        passed = "assertions")
      for (field in names(messages)) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows), messages[[field]])
      }
    }
  }
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

writer_runtime_titles = c(
  "Windows production writer preserves ordered writes and idle EOF",
  "Windows production writer death is a typed IO failure",
  "Windows reactor shutdown settles an idle production writer",
  "Windows orphan sweep settles the exact production writer and mailbox",
  "Windows production writer preserves split binary NUL and UTF-8 bytes",
  "writer ACK accounting advances accepted bytes once",
  "writer ACK validation rejects corrupt and regressing acceptance",
  "writer startup death fails IO before publishing any payload",
  "writer refuses malformed readiness before publishing any payload",
  "writer ACK precedes immediate target exit classification",
  "writer mailbox cleanup refuses foreign ownership and child directories",
  "writer refuses a preexisting mailbox before actor construction",
  "writer requires the exact live recorded target before construction",
  "writer cleanup retains its original state until settlement is confirmed",
  "writer refuses a changed mailbox root or owner before payload access",
  "writer validates child aliases and preserves a single-line bootstrap",
  "writer enforces the actual Rscript expression byte boundary",
  "full production writer bootstrap fits the unchanged Rscript limits",
  "Unix marker release does not consult the Windows mailbox",
  "writer cleanup refuses a dangling mailbox link")

testthat::test_that("production writer platform guards are explicit and never count as coverage", {
  file = "test-proc-writer-runtime.R"
  testthat::expect_identical(optional_titles[[file]], writer_runtime_titles)
  rows = lapply(writer_runtime_titles, record)
  for (i in seq_len(5L)) {
    rows[[i]]$passed = 0L
    rows[[i]]$skipped = 1L
    testthat::expect_true(optional_allowed_skip(file, writer_runtime_titles[[i]], FALSE))
    testthat::expect_false(optional_allowed_skip(file, writer_runtime_titles[[i]], TRUE))
  }
  result = optional_gate(rows, file, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_false(result$platform_guard_only)
  testthat::expect_identical(result$platform_guard_cases, writer_runtime_titles[1:5])
  testthat::expect_identical(result$mandatory_cases, writer_runtime_titles[6:20])
  testthat::expect_error(optional_gate(rows[1:5], file, FALSE), "Missing mandatory")
  testthat::expect_error(optional_gate(c(rows, list(record("Windows unrelated writer guard",
    passed = 0L, skipped = 1L))), file, FALSE), "Skipped")
  testthat::expect_error(optional_gate(rows, file, TRUE), "Skipped")
})

testthat::test_that("production writer mandatory rows reject omissions, duplicates and errors", {
  file = "test-proc-writer-runtime.R"
  rows = lapply(writer_runtime_titles, record)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
    for (i in seq_along(rows)) {
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      failed = rows
      failed[[i]]$failed = 1L
      testthat::expect_error(optional_gate(failed, file, windows), "Failed")
      warned = rows
      warned[[i]]$warnings = 1L
      testthat::expect_error(optional_gate(warned, file, windows), "Warnings")
      if (windows || i > 5L) {
        empty = rows
        empty[[i]]$passed = 0L
        testthat::expect_error(optional_gate(empty, file, windows), "assertions")
        skipped = rows
        skipped[[i]]$skipped = 1L
        testthat::expect_error(optional_gate(skipped, file, windows), "Skipped")
      }
    }
  }
})

testthat::test_that("affected process files retain only their named native platform guards", {
  guards = list(
    "test-proc-spawn.R" =
      "a parent killed with SIGTERM leaves children that the next load's sweep removes",
    "test-http-reactor.R" = c(
      "wire log resolves symlinks before enforcing its path boundary",
      "wire default and fallback paths reject escaping symlinks"),
    "test-subagent-worker.R" =
      "a worker exits within 10 s when its parent is killed (IC-60)")
  for (file in names(guards)) for (name in guards[[file]]) {
    testthat::expect_true(optional_allowed_skip(file, name, TRUE))
    testthat::expect_false(optional_allowed_skip(file, name, FALSE))
    testthat::expect_false(optional_allowed_skip(file, "unrelated native skip", TRUE))
    rows = lapply(optional_titles[[file]], record)
    result = optional_gate(c(rows, list(record(name, passed = 0L, skipped = 1L))),
      file, TRUE)
    testthat::expect_identical(result$platform_guard_cases, name)
    testthat::expect_identical(result$mandatory_cases, optional_titles[[file]])
  }
  cmd = "a .cmd MCP command runs through cmd.exe /d /c call on Windows"
  testthat::expect_true(optional_allowed_skip("test-mcp-client.R", cmd, FALSE))
  testthat::expect_false(optional_allowed_skip("test-mcp-client.R", cmd, TRUE))
  mode = "an install location without the execute bit is skipped, as on PATH"
  testthat::expect_true(optional_allowed_skip("test-cli-common.R", mode, TRUE))
  testthat::expect_false(optional_allowed_skip("test-cli-common.R", mode, FALSE))
  testthat::expect_false(optional_allowed_skip("test-cli-common.R",
    "a missing command signals gptr_error_cli_missing with the install hint", TRUE))
  for (name in c("a 4 MB payload to a child that echoes each line completes without deadlock",
    "write_all() times out on a child that reads nothing and refuses one without a pipe")) {
    testthat::expect_false(optional_allowed_skip("test-proc-spawn.R", name, TRUE))
    testthat::expect_false(optional_allowed_skip("test-proc-spawn.R", name, FALSE))
  }
})

writer_affected_titles = list(
  "test-proc-spawn.R" = c(
    "write_all() delivers 2 MB through a pipe and write_close() sends EOF",
    "a 4 MB payload to a child that echoes each line completes without deadlock",
    "write_all() times out on a child that reads nothing and refuses one without a pipe"),
  "test-proc-supervise.R" = c(
    "kill_all() leaves no descendant",
    "boundary: orphan cleanup waits for a kill that completes asynchronously",
    "boundary: unload retains records when owned child cleanup is unconfirmed"),
  "test-http-reactor.R" = c(
    "reactor_proc() delivers stdout and stderr lines, then the exit status once",
    "reactor_cancel() on a watcher kills the child without calling on_exit",
    "a pump nested in on_line never re-enters the watcher and on_exit comes once, last",
    "one pump drives an HTTP stream and a child process together"),
  "test-arch-layers.R" = c(
    "every file under R/ has a layer and every function one home",
    "internal calls respect the layer table and the kernel SDK (IC-33)",
    "arch_check() flags calls that cross a boundary (negative controls)"),
  "test-mcp-client.R" = c(
    "a modern stdio server is found by the probe, listed with pagination and called",
    "a legacy stdio server falls back to initialize, and the era is cached",
    "progress re-arms the idle timer; without progress a call times out and is cancelled"),
  "test-subagent-worker.R" = c(
    "a worker child answers through its proxy session and returns its exports",
    "gptr_cancel() of a worker child leaves no process (P19 acceptance 5)"),
  "test-cli-common.R" = c(
    "pcli_version() and pcli_probe() read the fake CLIs and cache per command",
    "a watched child is stopped through P05's glue: no watcher and no job row stay"),
  "test-cli-claude.R" = c(
    "a claude turn through peter() streams the answer; the next call resumes the session",
    "an mcp_message round trip evaluates R in the live session and is gated once",
    "gptr_cancel() sends the interrupt control request, then kill_all()"),
  "test-cli-codex.R" = c(
    "a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env",
    "the next turn resumes the Codex thread with -c sandbox_mode=",
    "a fake codex returns a function's numeric result through the HTTP MCP bridge"))

testthat::test_that("affected transport integrations require their actual representative cases", {
  for (file in names(writer_affected_titles)) {
    titles = writer_affected_titles[[file]]
    testthat::expect_identical(optional_titles[[file]], titles)
    rows = lapply(titles, record)
    for (windows in c(FALSE, TRUE)) {
      testthat::expect_true(optional_gate(rows, file, windows)$passed)
      testthat::expect_error(optional_gate(rows[-1L], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[1L]), file, windows), "Duplicate")
      for (i in seq_along(rows)) {
        messages = c(failed = "Failed", warnings = "Warnings", skipped = "Skipped",
          passed = "assertions")
        for (field in c("failed", "warnings", "skipped", "passed")) {
          changed = rows
          changed[[i]][[field]] = if (field == "passed") 0L else 1L
          testthat::expect_error(optional_gate(changed, file, windows), messages[[field]])
        }
      }
      testthat::expect_error(optional_gate(c(rows, list(record("unrelated skipped case",
        passed = 0L, skipped = 1L))), file, windows), "Skipped")
    }
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
