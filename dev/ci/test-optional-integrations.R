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
  "writer cleanup refuses a dangling mailbox link",
  "writer allows only confirmed fresh names inside its canonical mailbox",
  "writer canonical parent checks accept Windows separators and reject outside paths",
  "writer compressed bootstrap preserves exact trusted source and binary literals",
  "writer full compressed bootstrap fits a long Windows mailbox path",
  "writer early-case diagnostics retain only bounded structural evidence",
  "writer startup diagnostics accept only fixed monotonic stages and split lines",
  "writer startup diagnostics fail closed without retaining arbitrary stderr",
  "writer trusted bootstrap sends startup diagnostics only to its own stderr",
  "Windows no-reader timeout proves writer readiness and delivery-stage backpressure",
  "Windows production mailbox has a protected owner DACL and inherited file rights",
  "nested ACL diagnostics preserve exact LF and split CRLF progress",
  "nested ACL diagnostics reject arbitrary and unordered native output",
  "nested ACL diagnostics read only after zero-time polling",
  "writer nested ACL phases preserve exit failure without granting readiness",
  "writer early failures retain only fixed numeric nested ACL phases")

testthat::test_that("production writer platform guards are explicit and never count as coverage", {
  file = "test-proc-writer-runtime.R"
  testthat::expect_identical(optional_titles[[file]], writer_runtime_titles)
  rows = lapply(writer_runtime_titles, record)
  native = c(seq_len(5L), 29L, 30L)
  for (i in native) {
    rows[[i]]$passed = 0L
    rows[[i]]$skipped = 1L
    testthat::expect_true(optional_allowed_skip(file, writer_runtime_titles[[i]], FALSE))
    testthat::expect_false(optional_allowed_skip(file, writer_runtime_titles[[i]], TRUE))
  }
  result = optional_gate(rows, file, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_false(result$platform_guard_only)
  testthat::expect_identical(result$platform_guard_cases, writer_runtime_titles[native])
  testthat::expect_identical(result$mandatory_cases, writer_runtime_titles[-native])
  testthat::expect_error(optional_gate(rows[native], file, FALSE), "Missing mandatory")
  testthat::expect_error(optional_gate(c(rows, list(record("Windows unrelated writer guard",
    passed = 0L, skipped = 1L))), file, FALSE), "Skipped")
  testthat::expect_error(optional_gate(rows, file, TRUE), "Skipped")
})

testthat::test_that("production writer mandatory rows reject omissions, duplicates and errors", {
  file = "test-proc-writer-runtime.R"
  rows = lapply(writer_runtime_titles, record)
  native = c(seq_len(5L), 29L, 30L)
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
      if (windows || !i %in% native) {
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
    "a fake codex returns a function's numeric result through the HTTP MCP bridge",
    "control files gptr cannot hash are kept by a marker, so an auto exec still runs",
    "retargeting a dangling control link warns after the Codex exec completes",
    "a control file gptr cannot read is marked by its size and time instead",
  "Windows control entry listing refuses unreadable or uncertain parents",
  "Windows control entry membership retains fixed names without following targets",
  "Windows reparse digests use only the trusted query and stripped helper environment",
  "Windows reparse probes reject unavailable executables and uncertain results",
  "control digests query only unobservable Windows entries and retain POSIX markers",
  "fixed dangling SYSTEM and MCP control links keep markers and detect retargeting"))

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

original_regression_titles = list(
  "test-utils-encoding.R" = c(
    "as_utf8() keeps valid UTF-8 bytes under LC_ALL=C where enc2utf8() does not (IC-62)",
    "read_utf8() and write_utf8() round-trip CRLF, BOM and missing final newlines"),
  "test-utils-paths.R" = c(
    "write_atomic() falls back to an in-place write when rename keeps failing (IC-51)",
    "path_norm() expands '~' before it turns backslashes into slashes (CI-5)",
    "path_class protects local credential directories and env files"),
  "test-tool-write.R" = c(
    "write creates parent directories and writes a new file verbatim",
    "an existing CRLF file keeps CRLF, its BOM and its encoding"),
  "test-tool-walk.R" = c(
    "the walker prunes .git, node_modules, renv/library; dotfiles only with hidden = TRUE",
    "walk_files() returns path, size, mtime, type and honours max"),
  "test-ckpt-files.R" = c(
    "the blob store deduplicates, compresses small text and restores atomically",
    "a mutating step records created, modified and deleted files; undo and redo swap them",
    "undo keeps a file edited after the turn (3-way) unless forced",
    "already-compressed files are stored raw and come back byte for byte",
    "the blob store reports effective create denial and restores its owned bucket",
    "undo and redo of a case-only rename preserve bytes on the observed filesystem"),
  "test-tool-edit.R" = c(
    "NFKC compatibility forms match through stringi",
    "CRLF, BOM, mixed endings, CP1252, UTF-16 and stray bytes round-trip byte for byte",
    "a patch that names one file in two operations is refused and writes nothing",
    "two operations on one file through a directory link are refused",
    "patch additions respect the observed case-folding of the filesystem"),
  "test-storage-boundaries.R" = c(
    "cache info and cleanup stay inside owned cache directories",
    "checkpoint GC never removes foreign content through storage links",
    "discovered project instructions cannot read escaped or guarded link targets"))

original_os_guards = list(
  "test-utils-paths.R" = c(
    "write_atomic() writes privately, keeps replaced permission bits, else `mode`",
    "lexical control and secret paths stay protected when they are symlinks"),
  "test-tool-write.R" = c(
    "write refuses directories and writes through symbolic links keeping the mode",
    "a new file gets the umask's default mode, an existing one keeps its own",
    "a relative link that climbs with .. resolves from the link's physical directory",
    "a chain of links is followed; a loop or a dangling link is refused",
    "non-ASCII directories, files and relative links work in a C locale",
    "a file that may be written but not read is written verbatim, keeping its mode",
    "a link text that climbs after a symlinked component resolves as the kernel does",
    "an existing file the process may not write is refused with EACCES and left unchanged"),
  "test-tool-walk.R" = c(
    "a file name holding a newline is matched like git",
    "a symlinked directory is listed but not followed"),
  "test-ckpt-files.R" = c(
    "the walk prunes .git and .gptr and lists links unfollowed; restores avoid them",
    "files over the capture cap and symbolic links are not restorable",
    "undo restores mode bits; old rows, later edits and missing copies are not written",
    "a file that cannot be written or read is an item and the undo goes on",
    "files that cannot be read are listed, never captured and stop nothing else"),
  "test-tool-edit.R" = c(
    "Delete File refuses a directory, an empty Add File is empty, a move removes its name",
    "Delete File and a move remove only the file they name, whatever its characters",
    "a move onto its own file under another spelling keeps the file and takes the name"))

testthat::test_that("original regressions require their representative cases on both hosts", {
  for (file in names(original_regression_titles)) {
    titles = original_regression_titles[[file]]
    testthat::expect_identical(optional_titles[[file]], titles)
    rows = lapply(titles, record)
    for (windows in c(FALSE, TRUE)) {
      result = optional_gate(rows, file, windows)
      testthat::expect_true(result$passed)
      testthat::expect_identical(result$mandatory_cases, titles)
      testthat::expect_false(result$platform_guard_only)
      for (i in seq_along(rows)) {
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
  }
})

testthat::test_that("original OS guards are file-scoped and never excuse a Linux skip", {
  testthat::expect_identical(optional_original_os_guards, original_os_guards)
  for (file in names(original_os_guards)) for (name in original_os_guards[[file]]) {
    testthat::expect_true(optional_allowed_skip(file, name, TRUE))
    testthat::expect_false(optional_allowed_skip(file, name, FALSE))
    testthat::expect_false(optional_allowed_skip("test-windows-link-policy.R", name, TRUE))
    rows = lapply(original_regression_titles[[file]], record)
    guarded = c(rows, list(record(name, passed = 0L, skipped = 1L)))
    result = optional_gate(guarded, file, TRUE)
    testthat::expect_identical(result$platform_guard_cases, name)
    testthat::expect_identical(result$mandatory_cases, original_regression_titles[[file]])
    testthat::expect_error(optional_gate(guarded, file, FALSE), "Skipped")
    testthat::expect_error(optional_gate(c(rows, list(record("unrelated OS guard",
      passed = 0L, skipped = 1L))), file, TRUE), "Skipped")
  }
})

testthat::test_that("regression capabilities remain fatal even after earlier assertions", {
  capabilities = list(
    "test-utils-encoding.R" =
      "as_utf8() keeps bytes that are not UTF-8 in a UTF-8 locale, on every R version",
    "test-tool-walk.R" = "the file set equals git ls-files on a repository with tricky rules",
    "test-ckpt-files.R" = c(
      "already-compressed files are stored raw and come back byte for byte",
      "undo and redo of a case-only rename keep the file"),
    "test-tool-edit.R" = "NFKC compatibility forms match through stringi",
    "test-storage-boundaries.R" =
      "a cache-kind link to owned workspace storage still works")
  for (file in names(capabilities)) for (name in capabilities[[file]]) {
    for (windows in c(FALSE, TRUE)) {
      testthat::expect_false(optional_allowed_skip(file, name, windows))
      rows = lapply(original_regression_titles[[file]], record)
      if (name %in% original_regression_titles[[file]]) {
        i = match(name, original_regression_titles[[file]])
        rows[[i]]$skipped = 1L
      } else rows = c(rows, list(record(name, passed = 3L, skipped = 1L)))
      testthat::expect_error(optional_gate(rows, file, windows), "Skipped")
    }
  }
  file = "test-tool-edit.R"
  name = "two operations on one file through a directory link or a folded name are refused"
  rows = c(lapply(original_regression_titles[[file]], record),
    list(record(name, passed = 3L, skipped = 1L)))
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_false(optional_allowed_skip(file, name, windows))
    testthat::expect_error(optional_gate(rows, file, windows), "Skipped")
  }
})

testthat::test_that("split filesystem cases require real assertions without late trait skips", {
  variants = list(
    "test-ckpt-files.R" = c(
      "already-compressed files are stored raw and come back byte for byte",
      "the blob store reports effective create denial and restores its owned bucket",
      "undo and redo of a case-only rename preserve bytes on the observed filesystem"),
    "test-tool-edit.R" = c(
      "two operations on one file through a directory link are refused",
      "patch additions respect the observed case-folding of the filesystem"))
  testthat::expect_length(unlist(optional_original_os_guards), 20L)
  for (file in names(variants)) for (name in variants[[file]]) {
    testthat::expect_true(name %in% optional_titles[[file]])
    for (windows in c(FALSE, TRUE)) {
      testthat::expect_false(optional_allowed_skip(file, name, windows))
      rows = lapply(original_regression_titles[[file]], record)
      i = match(name, original_regression_titles[[file]])
      rows[[i]]$passed = 3L
      rows[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(rows, file, windows), "Skipped")
    }
  }
})

testthat::test_that("package-wide lint rules and their negative controls cannot silently skip", {
  file = "test-lint-rules.R"
  titles = c(
    "R/ follows the package lint rules (contract section 12.3, IC-72)",
    "each lint rule catches its violation (negative controls)")
  testthat::expect_identical(optional_titles[[file]], titles)
  rows = lapply(titles, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
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
      late_skip = rows
      late_skip[[i]]$passed = 3L
      late_skip[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(late_skip, file, windows), "Skipped")
    }
    testthat::expect_error(optional_gate(c(rows, list(record("unrelated lint capability",
      passed = 3L, skipped = 1L))), file, windows), "Skipped")
  }
})

testthat::test_that("idle Windows writer coverage has only its exact non-Windows guard", {
  file = "test-proc-writer-idle-slots.R"
  name = "two acknowledged idle Windows writers do not starve a third reading target"
  testthat::expect_identical(optional_titles[[file]], name)
  testthat::expect_true(optional_platform_guard(file, name, FALSE))
  testthat::expect_false(optional_platform_guard(file, name, TRUE))
  testthat::expect_false(optional_platform_guard("test-proc-writer-runtime.R", name, FALSE))
  testthat::expect_false(optional_allowed_skip(file, "unrelated idle writer skip", FALSE))
  testthat::expect_false(optional_allowed_skip(file, "unrelated idle writer skip", TRUE))
  guarded = list(record(name, passed = 0L, skipped = 1L))
  result = optional_gate(guarded, file, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_true(result$platform_guard_only)
  testthat::expect_identical(result$mandatory_cases, character())
  testthat::expect_identical(result$platform_guard_cases, name)
  testthat::expect_error(optional_gate(guarded, file, TRUE), "Skipped")
  result = optional_gate(list(record(name, passed = 19L)), file, TRUE)
  testthat::expect_true(result$passed)
  testthat::expect_false(result$platform_guard_only)
  testthat::expect_identical(result$mandatory_cases, name)
  testthat::expect_identical(result$platform_guard_cases, character())
})

testthat::test_that("idle writer omissions, raw errors and late skips cannot pass on Windows", {
  file = "test-proc-writer-idle-slots.R"
  name = "two acknowledged idle Windows writers do not starve a third reading target"
  rows = list(record(name, passed = 19L))
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_error(optional_gate(list(), file, windows), "No test cases")
    testthat::expect_error(optional_gate(list(record("unrelated")), file, windows),
      "Missing mandatory")
    testthat::expect_error(optional_gate(c(rows, rows), file, windows), "Duplicate")
    testthat::expect_error(optional_gate(list(record(name, failed = 1L)), file, windows),
      "Failed")
    testthat::expect_error(optional_gate(list(record(name, warnings = 1L)), file, windows),
      "Warnings")
    raw = optional_result_rows(list(list(test = name, results = list(
      structure(list(message = "controlled idle error"),
        class = c("expectation_error", "condition"))))))
    testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    testthat::expect_error(optional_gate(c(rows, list(record("unrelated idle capability",
      passed = 3L, skipped = 1L))), file, windows), "Skipped")
  }
  testthat::expect_error(optional_gate(list(record(name, passed = 0L)), file, TRUE),
    "assertions")
  testthat::expect_error(optional_gate(list(record(name, passed = 3L, skipped = 1L)),
    file, TRUE), "Skipped")
})

testthat::test_that("controller warning diagnostics omit messages, arguments and custom classes", {
  canary = "CONTROLLED_PRIVATE_WARNING_CANARY"
  warning = structure(list(message = canary, call = call("ps_kill_tree", canary)),
    class = c(canary, "simpleWarning", "warning", "condition"))
  diagnostic = optional_controller_diagnostic(warning, "marker-kill", "dependency-preflight")
  testthat::expect_identical(diagnostic$phase, "marker-kill")
  testthat::expect_identical(diagnostic$label, "dependency-preflight")
  testthat::expect_identical(diagnostic$classes, c("simpleWarning", "warning", "condition"))
  testthat::expect_identical(diagnostic$other_class_count, 1L)
  testthat::expect_identical(diagnostic$call_head, "ps_kill_tree")
  testthat::expect_false(grepl(canary, jsonlite::toJSON(diagnostic), fixed = TRUE))
  warning$call = call(canary, canary)
  diagnostic = optional_controller_diagnostic(warning, "child-result", "dependency-preflight")
  testthat::expect_identical(diagnostic$call_head, "other")
  testthat::expect_false(grepl(canary, jsonlite::toJSON(diagnostic), fixed = TRUE))
  state = optional_controller_state()
  testthat::expect_error(optional_controller_phase(state, canary, "controller"),
    "Unapproved controller phase")
  testthat::expect_error(optional_controller_phase(state, "child-wait", canary),
    "Unapproved controller label")
})

testthat::test_that("controller warnings include main cleanup and cannot leave a passing summary", {
  output = withr::local_tempdir()
  main = function(controller) {
    controller$summary = list(passed = TRUE)
    optional_controller_phase(controller, "child-result", "dependency-preflight")
    warning("controlled body warning", call. = FALSE)
    on.exit({
      optional_controller_phase(controller, "marker-kill", "dependency-preflight")
      warning("controlled cleanup warning", call. = FALSE)
    })
    invisible(NULL)
  }
  seen = new.env(parent = emptyenv())
  seen$messages = character()
  expected = c("controlled body warning", "controlled cleanup warning")
  # Capture at the test boundary after the controller's inner observer sees every warning.
  withCallingHandlers(
    testthat::expect_error(optional_controller_run(main, output), "Controller warnings captured"),
    warning = function(w) {
      message = conditionMessage(w)
      if (!identical(class(w), c("simpleWarning", "warning", "condition")) ||
          !(message %in% expected)) return(invisible(NULL))
      seen$messages = c(seen$messages, message)
      invokeRestart("muffleWarning")
    })
  testthat::expect_identical(seen$messages, expected)
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  summary = jsonlite::read_json(file.path(output, "integration-summary.json"))
  testthat::expect_false(witness$passed)
  testthat::expect_identical(witness$warnings_total, 2L)
  testthat::expect_false(witness$diagnostics_truncated)
  testthat::expect_identical(vapply(witness$diagnostics, function(x) x$phase, ""),
    c("child-result", "marker-kill"))
  testthat::expect_false(summary$passed)
  testthat::expect_identical(summary$controller_warnings$warnings_total, 2L)
})

testthat::test_that(
  "controller warnings preserve an original error and bounded structural evidence", {
  output = withr::local_tempdir()
  original = structure(list(message = "controlled original error", call = NULL),
    class = c("optional_fixture_error", "error", "condition"))
  main = function(controller) {
    on.exit(warning("controlled cleanup warning", call. = FALSE))
    stop(original)
  }
  testthat::expect_warning(testthat::expect_error(optional_controller_run(main, output),
    class = "optional_fixture_error"), "controlled")
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  testthat::expect_false(witness$passed)
  testthat::expect_true(witness$original_error)
  testthat::expect_identical(witness$warnings_total, 1L)
  testthat::expect_false(grepl("controlled original error",
    jsonlite::toJSON(witness), fixed = TRUE))
})

testthat::test_that("controller warnings keep a complete count with at most 25 diagnostics", {
  output = withr::local_tempdir()
  main = function(controller) {
    for (i in seq_len(27L)) warning("controlled repeated warning", call. = FALSE)
  }
  seen = new.env(parent = emptyenv())
  seen$messages = character()
  expected = rep("controlled repeated warning", 27L)
  withCallingHandlers(
    testthat::expect_error(optional_controller_run(main, output), "Controller warnings captured"),
    warning = function(w) {
      message = conditionMessage(w)
      if (!identical(class(w), c("simpleWarning", "warning", "condition")) ||
          !(message %in% expected)) return(invisible(NULL))
      seen$messages = c(seen$messages, message)
      invokeRestart("muffleWarning")
    })
  testthat::expect_identical(seen$messages, expected)
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  testthat::expect_identical(witness$warnings_total, 27L)
  testthat::expect_length(witness$diagnostics, 25L)
  testthat::expect_true(witness$diagnostics_truncated)
  testthat::expect_false(witness$passed)
})

testthat::test_that("a warning-free controller writes an affirmative witness", {
  output = withr::local_tempdir()
  main = function(controller) {
    controller$summary = list(passed = TRUE)
    42L
  }
  testthat::expect_identical(optional_controller_run(main, output), 42L)
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  summary = jsonlite::read_json(file.path(output, "integration-summary.json"))
  testthat::expect_true(witness$passed)
  testthat::expect_false(witness$original_error)
  testthat::expect_identical(witness$warnings_total, 0L)
  testthat::expect_length(witness$diagnostics, 0L)
  testthat::expect_false(witness$diagnostics_truncated)
  testthat::expect_true(summary$passed)
})

testthat::test_that("a late artifact-write warning fails after main has returned", {
  output = withr::local_tempdir()
  state = new.env(parent = emptyenv())
  state$warned = FALSE
  main = function(controller) {
    controller$summary = list(passed = TRUE)
    invisible(NULL)
  }
  write = function(value, path) {
    if (!state$warned && basename(path) == "controller-warnings.json") {
      state$warned = TRUE
      warning("controlled late write warning", call. = FALSE)
    }
    optional_controller_write(value, path)
  }
  testthat::expect_warning(testthat::expect_error(optional_controller_run(main, output,
    write = write), "Controller warnings captured"), "controlled")
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  summary = jsonlite::read_json(file.path(output, "integration-summary.json"))
  testthat::expect_false(witness$passed)
  testthat::expect_identical(witness$warnings_total, 1L)
  testthat::expect_identical(witness$diagnostics[[1L]]$phase, "controller-witness-json")
  testthat::expect_false(summary$passed)
  testthat::expect_identical(summary$controller_warnings$warnings_total, 1L)
})

testthat::test_that("a late summary-write warning revokes the summary's passing status", {
  output = withr::local_tempdir()
  state = new.env(parent = emptyenv())
  state$warned = FALSE
  main = function(controller) {
    controller$summary = list(passed = TRUE)
    invisible(NULL)
  }
  write = function(value, path) {
    if (!state$warned && basename(path) == "integration-summary.json") {
      state$warned = TRUE
      warning("controlled late summary warning", call. = FALSE)
    }
    optional_controller_write(value, path)
  }
  testthat::expect_warning(testthat::expect_error(optional_controller_run(main, output,
    write = write), "Controller warnings captured"), "controlled")
  witness = jsonlite::read_json(file.path(output, "controller-warnings.json"))
  summary = jsonlite::read_json(file.path(output, "integration-summary.json"))
  testthat::expect_false(witness$passed)
  testthat::expect_identical(witness$warnings_total, 1L)
  testthat::expect_identical(witness$diagnostics[[1L]]$phase, "integration-summary-json")
  testthat::expect_false(summary$passed)
  testthat::expect_identical(summary$controller_warnings$warnings_total, 1L)
})

testthat::test_that(
  "startup diagnostic cases keep exact native guards and mandatory pure coverage", {
  file = "test-proc-writer-runtime.R"
  added = c(
    "writer startup diagnostics accept only fixed monotonic stages and split lines",
    "writer startup diagnostics fail closed without retaining arbitrary stderr",
    "writer trusted bootstrap sends startup diagnostics only to its own stderr",
    "Windows no-reader timeout proves writer readiness and delivery-stage backpressure")
  expected = c(writer_runtime_titles[1:25], added)
  testthat::expect_identical(optional_titles[[file]][seq_along(expected)], expected)
  native = c(seq_len(5L), 29L, 30L)
  rows = lapply(writer_runtime_titles, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_identical(result$mandatory_cases,
      if (windows) writer_runtime_titles else writer_runtime_titles[-native])
    for (i in 26:29) {
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      failed = rows
      failed[[i]]$failed = 1L
      testthat::expect_error(optional_gate(failed, file, windows), "Failed")
      warned = rows
      warned[[i]]$warnings = 1L
      testthat::expect_error(optional_gate(warned, file, windows), "Warnings")
      if (windows || i < 29L) {
        testthat::expect_false(optional_allowed_skip(file, expected[[i]], windows))
        empty = rows
        empty[[i]]$passed = 0L
        testthat::expect_error(optional_gate(empty, file, windows), "assertions")
        skipped = rows
        skipped[[i]]$passed = 3L
        skipped[[i]]$skipped = 1L
        testthat::expect_error(optional_gate(skipped, file, windows), "Skipped")
      }
    }
  }
  for (i in native) {
    rows[[i]]$passed = 0L
    rows[[i]]$skipped = 1L
  }
  result = optional_gate(rows, file, FALSE)
  testthat::expect_identical(result$platform_guard_cases, writer_runtime_titles[native])
  testthat::expect_identical(result$mandatory_cases, writer_runtime_titles[-native])
  testthat::expect_false(result$platform_guard_only)
  testthat::expect_error(optional_gate(rows, file, TRUE), "Skipped")
  testthat::expect_true(optional_allowed_skip(file, added[[4L]], FALSE))
  testthat::expect_false(optional_allowed_skip("test-proc-writer-idle-slots.R", added[[4L]], FALSE))
})

testthat::test_that("native Codex control variants never excuse capability skips or raw errors", {
  file = "test-cli-codex.R"
  titles = c(
    "control files gptr cannot hash are kept by a marker, so an auto exec still runs",
    "retargeting a dangling control link warns after the Codex exec completes",
    "a control file gptr cannot read is marked by its size and time instead")
  rows = lapply(optional_titles[[file]], record)
  testthat::expect_identical(tail(optional_titles[[file]], 3L), titles)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
    for (title in titles) {
      i = match(title, vapply(rows, function(row) row$test, ""))
      testthat::expect_false(optional_allowed_skip(file, title, windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      for (field in c("failed", "warnings", "skipped", "passed")) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows))
      }
      changed = rows
      changed[[i]] = optional_result_rows(list(list(test = title, results = list(
        structure(list(), class = "expectation_success"),
        structure(list(message = "controlled native fixture error"),
          class = c("expectation_error", "condition"))))))[[1L]]
      testthat::expect_error(optional_gate(changed, file, windows), "Failed")
      changed[[i]]$failed = 0L
      changed[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(changed, file, windows), "Skipped")
    }
  }
})


testthat::test_that(
  "controller markers have a numeric second field without parent or RNG changes", {
  environment = Sys.getenv()
  seed_present = exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  markers = c(optional_marker(1791700000.9), optional_marker(1791700000.9))
  testthat::expect_false(identical(markers[[1L]], markers[[2L]]))
  testthat::expect_true(all(grepl("^GPTROPT[^_]+_1791700000$", markers)))
  for (marker in markers) {
    fields = strsplit(marker, "_", fixed = TRUE)[[1L]]
    testthat::expect_length(fields, 2L)
    testthat::expect_identical(as.numeric(fields[[2L]]), 1791700000)
    testthat::expect_identical(Sys.getenv(marker, unset = NA_character_), NA_character_)
  }
  testthat::expect_true(identical(Sys.getenv(), environment),
    info = "parent environment unchanged")
  testthat::expect_identical(exists(".Random.seed", envir = globalenv(), inherits = FALSE),
    seed_present)
  testthat::expect_identical(get0(".Random.seed", envir = globalenv(), inherits = FALSE), seed)
})

testthat::test_that("controller markers reject unavailable or invalid creation-time bounds", {
  for (time in list(NA_real_, Inf, -Inf, -1, numeric(), c(1, 2))) {
    testthat::expect_error(optional_marker(time), "Invalid controller marker time")
  }
})

testthat::test_that("controller markers pass the actual ps parser without coercion warnings", {
  # Keep the real ps parser, but prohibit process enumeration or signalling in this unit control.
  no_signal = function(processes, ...) {
    if (length(processes)) stop("Unexpected process in marker parser control")
    character()
  }
  testthat::local_mocked_bindings(ps_pids = function() integer(), ps_send_signal = no_signal,
    ps_kill = no_signal, .package = "ps")
  testthat::expect_warning(ps::ps_find_tree("GPTR_OPTIONAL_OWNER_control"),
    class = "simpleWarning")
  marker = optional_marker()
  testthat::expect_no_warning(testthat::expect_identical(ps::ps_find_tree(marker), list()))
  testthat::expect_no_warning(testthat::expect_length(ps::ps_kill_tree(marker), 0L))
})


testthat::test_that("owned marker-family integration cannot omit or skip its native witness", {
  file = "test-proc-marker-family.R"
  title = "canonical markers enumerate an owned family and preserve unrelated processes"
  testthat::expect_identical(optional_titles[[file]][[1L]], title)
  for (windows in c(FALSE, TRUE)) {
    rows = lapply(optional_titles[[file]], record)
    row = rows[[1L]]
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
    testthat::expect_false(optional_allowed_skip(file, title, windows))
    testthat::expect_error(optional_gate(list(), file, windows), "No test cases")
    testthat::expect_error(optional_gate(list(record("unrelated case")), file, windows),
                          "Missing mandatory")
    testthat::expect_error(optional_gate(c(rows, rows[1L]), file, windows), "Duplicate")
    for (field in c("failed", "warnings", "skipped", "passed")) {
      changed = row
      changed[[field]] = if (field == "passed") 0L else 1L
      testthat::expect_error(optional_gate(c(list(changed), rows[-1L]), file, windows))
    }
    raw = optional_result_rows(list(list(test = title, results = list(
      structure(list(), class = "expectation_success"),
      structure(list(message = "controlled marker family error"),
        class = c("expectation_error", "condition"))))))[[1L]]
    testthat::expect_error(optional_gate(c(list(raw), rows[-1L]), file, windows), "Failed")
    raw$failed = 0L
    raw$skipped = 1L
    testthat::expect_error(optional_gate(c(list(raw), rows[-1L]), file, windows), "Skipped")
    testthat::expect_false(optional_allowed_skip("test-proc-marker-family-other.R",
                                               title, windows))
    testthat::expect_false(optional_allowed_skip(file, "unrelated capability case", windows))
  }
})


testthat::test_that("native mailbox ACL proof is mandatory on Windows with one exact Unix guard", {
  file = "test-proc-writer-runtime.R"
  title = "Windows production mailbox has a protected owner DACL and inherited file rights"
  testthat::expect_identical(optional_titles[[file]][[30L]], title)
  rows = lapply(optional_titles[[file]], record)
  i = match(title, vapply(rows, function(row) row$test, ""))
  testthat::expect_false(is.na(i))
  if (is.na(i)) return(invisible(NULL))
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_true(optional_gate(rows, file, windows)$passed)
    testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
    testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
    for (field in c("failed", "warnings")) {
      changed = rows
      changed[[i]][[field]] = 1L
      testthat::expect_error(optional_gate(changed, file, windows))
    }
    raw = rows
    raw[[i]] = optional_result_rows(list(list(test = title, results = list(
      structure(list(), class = "expectation_success"),
      structure(list(message = "controlled native ACL verifier error"),
        class = c("expectation_error", "condition"))))))[[1L]]
    testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    testthat::expect_false(optional_allowed_skip("test-proc-marker-family.R", title, windows))
    testthat::expect_false(optional_allowed_skip(file, "unrelated native ACL capability", windows))
  }
  testthat::expect_false(optional_allowed_skip(file, title, TRUE))
  testthat::expect_true(optional_allowed_skip(file, title, FALSE))
  empty = rows
  empty[[i]]$passed = 0L
  testthat::expect_error(optional_gate(empty, file, TRUE), "assertions")
  late_skip = rows
  late_skip[[i]]$skipped = 1L
  testthat::expect_error(optional_gate(late_skip, file, TRUE), "Skipped")
  guard = rows
  guard[[i]]$passed = 0L
  guard[[i]]$skipped = 1L
  result = optional_gate(guard, file, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_identical(result$platform_guard_cases, title)
  testthat::expect_false(title %in% result$mandatory_cases)
  testthat::expect_false(result$platform_guard_only)
})


testthat::test_that("marker restoration diagnostics remain mandatory without skip allowances", {
  file = "test-proc-marker-family.R"
  expected = c("canonical markers enumerate an owned family and preserve unrelated processes",
    "marker environment diagnostics distinguish casing from private value changes")
  testthat::expect_identical(optional_titles[[file]], expected)
  rows = lapply(expected, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
    testthat::expect_identical(result$mandatory_cases, expected)
    testthat::expect_length(result$platform_guard_cases, 0L)
    for (i in seq_along(expected)) {
      testthat::expect_false(optional_allowed_skip(file, expected[[i]], windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      for (field in c("passed", "failed", "warnings", "skipped")) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows))
      }
      raw = rows
      raw[[i]] = optional_result_rows(list(list(test = expected[[i]], results = list(
        structure(list(), class = "expectation_success"),
        structure(list(message = "controlled environment witness error"),
          class = c("expectation_error", "condition"))))))[[1L]]
      testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    }
    testthat::expect_false(optional_allowed_skip("test-proc-marker-family-other.R",
      expected[[2L]], windows))
  }
})


testthat::test_that("nested ACL diagnostics remain mandatory on both hosts", {
  file = "test-proc-writer-runtime.R"
  added = c(
    "nested ACL diagnostics preserve exact LF and split CRLF progress",
    "nested ACL diagnostics reject arbitrary and unordered native output",
    "nested ACL diagnostics read only after zero-time polling",
    "writer nested ACL phases preserve exit failure without granting readiness",
    "writer early failures retain only fixed numeric nested ACL phases")
  expected = c(writer_runtime_titles[seq_len(30L)], added)
  testthat::expect_identical(optional_titles[[file]], expected)
  rows = lapply(expected, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
    testthat::expect_true(all(added %in% result$mandatory_cases))
    testthat::expect_false(result$platform_guard_only)
    for (title in added) {
      i = match(title, expected)
      testthat::expect_false(optional_allowed_skip(file, title, windows))
      testthat::expect_false(optional_allowed_skip("test-proc-marker-family.R", title, windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      for (field in c("failed", "warnings", "skipped", "passed")) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows))
      }
      raw = rows
      raw[[i]] = optional_result_rows(list(list(test = title, results = list(
        structure(list(), class = "expectation_success"),
        structure(list(message = "controlled nested ACL diagnostic error"),
          class = c("expectation_error", "condition"))))))[[1L]]
      testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    }
  }
})


testthat::test_that("fixed Codex control cases remain mandatory without capability guards", {
  file = "test-cli-codex.R"
  added = c(
    "Windows control entry listing refuses unreadable or uncertain parents",
    "Windows control entry membership retains fixed names without following targets",
    "Windows reparse digests use only the trusted query and stripped helper environment",
    "Windows reparse probes reject unavailable executables and uncertain results",
    "control digests query only unobservable Windows entries and retain POSIX markers",
    "fixed dangling SYSTEM and MCP control links keep markers and detect retargeting")
  original = c(
    "a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env",
    "the next turn resumes the Codex thread with -c sandbox_mode=",
    "a fake codex returns a function's numeric result through the HTTP MCP bridge",
    "control files gptr cannot hash are kept by a marker, so an auto exec still runs",
    "retargeting a dangling control link warns after the Codex exec completes",
    "a control file gptr cannot read is marked by its size and time instead")
  expected = c(original, added)
  testthat::expect_identical(optional_titles[[file]], expected)
  rows = lapply(expected, record)
  for (windows in c(FALSE, TRUE)) {
    result = optional_gate(rows, file, windows)
    testthat::expect_true(result$passed)
    testthat::expect_identical(result$mandatory_cases, expected)
    testthat::expect_identical(result$platform_guard_cases, character())
    testthat::expect_false(result$platform_guard_only)
    for (title in added) {
      i = match(title, expected)
      testthat::expect_false(optional_allowed_skip(file, title, windows))
      testthat::expect_false(optional_allowed_skip("test-cli-claude.R", title, windows))
      testthat::expect_error(optional_gate(rows[-i], file, windows), "Missing mandatory")
      testthat::expect_error(optional_gate(c(rows, rows[i]), file, windows), "Duplicate")
      for (field in c("failed", "warnings", "skipped", "passed")) {
        changed = rows
        changed[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(optional_gate(changed, file, windows))
      }
      late = rows
      late[[i]]$passed = 3L
      late[[i]]$skipped = 1L
      testthat::expect_error(optional_gate(late, file, windows), "Skipped")
      raw = rows
      raw[[i]] = optional_result_rows(list(list(test = title, results = list(
        structure(list(), class = "expectation_success"),
        structure(list(message = "controlled fixed Codex entry error"),
          class = c("expectation_error", "condition"))))))[[1L]]
      testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    }
  }
})


testthat::test_that("warm idle writer boundary is mandatory on Windows with one exact Unix guard", {
  file = "test-proc-writer-idle-boundary.R"
  title = "two warm acknowledged Windows writers do not starve a third two-second write"
  testthat::expect_identical(optional_titles[[file]], title)
  rows = list(record(title))
  result = optional_gate(rows, file, TRUE)
  testthat::expect_true(result$passed)
  testthat::expect_identical(result$mandatory_cases, title)
  testthat::expect_false(result$platform_guard_only)
  for (windows in c(FALSE, TRUE)) {
    testthat::expect_error(optional_gate(list(), file, windows), "No test cases")
    testthat::expect_error(optional_gate(list(record("unrelated native case")), file, windows),
                          "Missing mandatory")
    testthat::expect_error(optional_gate(c(rows, rows), file, windows), "Duplicate")
    for (field in c("failed", "warnings")) {
      changed = rows
      changed[[1L]][[field]] = 1L
      testthat::expect_error(optional_gate(changed, file, windows))
    }
    raw = optional_result_rows(list(list(test = title, results = list(
      structure(list(), class = "expectation_success"),
      structure(list(message = "controlled warm writer boundary error"),
        class = c("expectation_error", "condition"))))))
    testthat::expect_error(optional_gate(raw, file, windows), "Failed")
    testthat::expect_false(optional_allowed_skip("test-proc-writer-retirement.R", title, windows))
    testthat::expect_false(optional_allowed_skip(file, "unrelated capability guard", windows))
  }
  testthat::expect_false(optional_allowed_skip(file, title, TRUE))
  testthat::expect_true(optional_allowed_skip(file, title, FALSE))
  empty = rows
  empty[[1L]]$passed = 0L
  testthat::expect_error(optional_gate(empty, file, TRUE), "assertions")
  late = rows
  late[[1L]]$passed = 3L
  late[[1L]]$skipped = 1L
  testthat::expect_error(optional_gate(late, file, TRUE), "Skipped")
  guarded = list(record(title, passed = 0L, skipped = 1L))
  result = optional_gate(guarded, file, FALSE)
  testthat::expect_true(result$passed)
  testthat::expect_identical(result$mandatory_cases, character())
  testthat::expect_identical(result$platform_guard_cases, title)
  testthat::expect_true(result$platform_guard_only)
  testthat::expect_identical(sum(vapply(result$rows, function(row) row$passed, 0L)), 0L)
})
