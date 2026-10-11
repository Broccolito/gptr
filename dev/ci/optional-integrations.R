# Dedicated offline optional integrations. Every selected file runs in an owned child.
# Source this file for its pure gate functions; execute it with Rscript --vanilla to run.
optional_titles = list(
  "test-doc-knitr.R" =
    "quarto render records a #| label agent chunk and the next render replays it",
  "test-doc-jupyter.R" =
    "pending notebook code publishes one MIME bundle while source and sidecar stay intact",
  "test-doc-history-display.R" = c(
    "history renderers register lazily for each inherited document format",
    "notebook MIME displays share the compact printer without changing full history",
    "rich history displays keep markup inert and redact only a display copy",
    "knitr dispatch prints a history once before a data-frame renderer can intercept it"),
  "test-bridge-lang.R" = c(
    "peter$py() keeps objects in __main__, shows the last value and one-line errors",
    "peter$py() receives R objects by name and knitr python chunks share __main__"),
  "test-tool-search.R" = "grep agrees with ripgrep on (file, line) pairs",
  "test-artifact-app.R" = c(
    "the session check passes a working app and returns a 1000x700 screenshot",
    "the session check catches render errors and crashed servers but not validate()"),
  "test-artifact-browser-cleanup.R" = c(
    "artifact browser cleanup closes its owned local process before the websocket",
    "artifact browser cleanup still closes its websocket after a process-close error",
    "artifact browser cleanup leaves a remote browser process alone",
    "the private Linux test temp root fits Chromium's Unix socket limit"),
  "test-config-content-cache.R" = c(
    "file SHA256 preserves byte identity for binary and empty inputs",
    "content-sensitive settings reuse a parsed value and invalidate unchanged metadata",
    "a settings rewrite during decoding cannot publish a mismatched cache entry",
    "an unavailable content digest never serves or retains stale settings",
    "content-sensitive trust verifies each hit and reuses its current file hashes"),
  "test-gptr-config.R" = c(
    "a trust decision taken in this process lapses when a gated file changes (IC-52)",
    "gptr's own write keeps an in-process decision without recording it (IC-52)"),
  "test-windows-security.R" = c(
    "Windows true symbolic links are readable and detached without deleting targets",
    "Windows safe instruction links remain while escaped and guarded inputs stay private",
    "Windows cache and checkpoint cleanup never follow foreign directory links",
    "Windows scrub excludes escaping links and never writes through a foreign lock root",
    "Windows checkpoint walks label links and forbid restoring through them",
    "Windows writes resolve links and edits refuse duplicate physical file operations",
    "Windows settings refresh after a same-size rewrite with unchanged file timestamps",
    "Windows same-size gated rewrites revoke trust even with unchanged file timestamps"),
  "test-windows-link-policy.R" = c(
    "Windows text reads canonical file bytes despite empty alias metadata",
    "Windows writes use the canonical target when readlink reports no link",
    "Windows direct link policy distinguishes a link from its ordinary descendants",
    "Windows checkpoint walks list directory links without descending into them",
    "Windows checkpoint capture refuses a direct file link"),
  "test-proc-windows-backpressure.R" = c(
    "real child duplex backpressure preserves every 4 MB stdout and stderr line",
    "a real no-reader child returns the typed stdin timeout under external bounds",
    "a real queued 4 MB write leaves reactor cancellation responsive with no late exit"),
  "test-proc-writer-prototype.R" = c(
    "owned writer prototype preserves every 4 MB duplex stdout and stderr line",
    "owned writer prototype returns a typed no-reader stdin timeout",
    "owned writer prototype cancels a queued 4 MB write without a late exit",
    "owned writer prototype preserves queued binary NUL and UTF-8 bytes"),
  "test-proc-backpressure-sampling.R" = c(
    "backpressure enumeration tolerates only a dead original parent exit race",
    "backpressure enumeration preserves the returned original child handles",
    "backpressure enumeration fails closed for live and unknown parent identities",
    "backpressure sample diagnostics are bounded and omit arbitrary messages"),
  "test-proc-writer-runtime.R" = c(
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
    "Windows production mailbox has a protected owner DACL and inherited file rights"),
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
    "a control file gptr cannot read is marked by its size and time instead"),
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
    "discovered project instructions cannot read escaped or guarded link targets"),
  "test-lint-rules.R" = c(
    "R/ follows the package lint rules (contract section 12.3, IC-72)",
    "each lint rule catches its violation (negative controls)"),
  "test-proc-writer-idle-slots.R" =
    "two acknowledged idle Windows writers do not starve a third reading target",
  "test-proc-marker-family.R" =
    "canonical markers enumerate an owned family and preserve unrelated processes"
)

optional_select = function(pattern, root) {
  files = names(optional_titles)[grepl(pattern, names(optional_titles))]
  if (!length(files)) stop("No approved optional integration files selected")
  paths = file.path(root, "tests", "testthat", files)
  if (!all(file.exists(paths))) stop("Missing selected integration files")
  paths
}

optional_original_os_guards = list(
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

optional_platform_guard = function(file, name, windows) {
  if (windows) return(FALSE)
  if (identical(file, "test-windows-security.R"))
    return(name %in% optional_titles[[file]])
  if (identical(file, "test-proc-writer-idle-slots.R")) return(identical(name,
    "two acknowledged idle Windows writers do not starve a third reading target"))
  identical(file, "test-proc-writer-runtime.R") && name %in% c(
    "Windows production writer preserves ordered writes and idle EOF",
    "Windows production writer death is a typed IO failure",
    "Windows reactor shutdown settles an idle production writer",
    "Windows orphan sweep settles the exact production writer and mailbox",
    "Windows production writer preserves split binary NUL and UTF-8 bytes",
    "Windows no-reader timeout proves writer readiness and delivery-stage backpressure",
    "Windows production mailbox has a protected owner DACL and inherited file rights")
}

optional_allowed_skip = function(file, name, windows) {
  if (optional_platform_guard(file, name, windows)) return(TRUE)
  if (windows && name %in% optional_original_os_guards[[file]]) return(TRUE)
  if (!windows) return(identical(file, "test-mcp-client.R") && identical(name,
    "a .cmd MCP command runs through cmd.exe /d /c call on Windows"))
  windows && ((identical(file, "test-artifact-app.R") && identical(name,
    "the access token is 128 random bits from openssl or /dev/urandom")) ||
    (identical(file, "test-bridge-lang.R") && name %in% c(
      "shell engines run through peter$sh() without registered keys and with a timeout",
      "the cmd engine is refused outside Windows")) ||
    (identical(file, "test-gptr-config.R") && name %in% c(
      "a settings file is parsed once per change, a same-size rewrite included",
      "a gated file rewritten at the same size with its old mtime still voids trust")) ||
    (identical(file, "test-proc-spawn.R") && identical(name,
      "a parent killed with SIGTERM leaves children that the next load's sweep removes")) ||
    (identical(file, "test-http-reactor.R") && name %in% c(
      "wire log resolves symlinks before enforcing its path boundary",
      "wire default and fallback paths reject escaping symlinks")) ||
    (identical(file, "test-subagent-worker.R") && identical(name,
      "a worker exits within 10 s when its parent is killed (IC-60)")) ||
    (identical(file, "test-cli-common.R") && identical(name,
      "an install location without the execute bit is skipped, as on PATH")))
}

optional_gate = function(rows, file, windows) {
  if (!length(rows)) stop("No test cases selected")
  if (any(vapply(rows, function(x) x$failed > 0L, logical(1)))) stop("Failed assertions")
  if (any(vapply(rows, function(x) x$warnings > 0L, logical(1)))) stop("Warnings captured")
  for (row in rows) if (row$skipped && !optional_allowed_skip(file, row$test, windows))
    stop("Skipped integration case: ", row$test)
  expected = optional_titles[[file]]
  if (!length(expected)) stop("Unapproved integration file")
  names = vapply(rows, function(x) x$test, "")
  if (!all(expected %in% names)) stop("Missing mandatory integration cases")
  mandatory = expected[!vapply(expected, function(name) {
    optional_platform_guard(file, name, windows)
  }, logical(1))]
  platform_only = !length(mandatory)
  for (name in expected) {
    selected = rows[names == name]
    if (length(selected) != 1L) stop("Duplicate mandatory integration case")
    if (name %in% mandatory && (selected[[1L]]$skipped || selected[[1L]]$passed < 1L))
      stop("Mandatory integration has no passing assertions: ", name)
  }
  if (!platform_only && sum(vapply(rows, function(x) x$passed, 0L)) < 1L)
    stop("No passing assertions")
  guards = names[vapply(rows, function(row) row$skipped > 0L, logical(1))]
  list(passed = TRUE, expected_cases = expected, mandatory_cases = mandatory,
    platform_guard_cases = guards, platform_guard_only = platform_only, rows = rows)
}

optional_condition_diagnostic = function(condition) {
  message = conditionMessage(condition)
  list(classes = class(condition), message = substr(message, 1L, 2000L),
       message_truncated = nchar(message) > 2000L)
}

optional_result_rows = function(result) {
  lapply(result, function(test) {
    entries = test$results
    count = function(classes) sum(vapply(entries, inherits, logical(1), what = classes))
    diagnostics = Filter(function(entry) {
      inherits(entry, c("expectation_failure", "expectation_error", "expectation_skip",
        "expectation_warning", "warning"))
    }, entries)
    list(test = test$test, passed = count("expectation_success"),
      failed = count(c("expectation_failure", "expectation_error")),
      warnings = count(c("expectation_warning", "warning")), skipped = count("expectation_skip"),
      diagnostics = lapply(head(diagnostics, 25L), optional_condition_diagnostic),
      diagnostic_conditions_total = length(diagnostics),
      diagnostic_conditions_truncated = length(diagnostics) > 25L)
  })
}

# ps parses the second underscore-delimited field as a process creation-time lower bound.
# Generate only a name: the parent never carries this marker, and R's RNG is untouched.
optional_marker = function(time = Sys.time()) {
  after = floor(as.numeric(time))
  if (length(after) != 1L || !is.finite(after) || after < 0)
    stop("Invalid controller marker time")
  paste0(basename(tempfile("GPTROPT")), "_", sprintf("%.0f", after))
}

optional_wait_family = function(root_stopped, remaining, seconds = 5,
                                now = function() proc.time()[["elapsed"]], pause = Sys.sleep) {
  started = now()
  polls = 0L
  repeat {
    polls = polls + 1L
    stopped = root_stopped()
    count = length(remaining())
    elapsed = now() - started
    if ((stopped && count == 0L) || elapsed >= seconds) {
      return(list(settled = stopped && count == 0L, root_stopped = stopped,
        remaining_marked_processes = count, settlement_elapsed_s = elapsed,
        settlement_polls = polls))
    }
    pause(min(0.05, seconds - elapsed))
  }
}

optional_check_logs = function(paths) {
  for (path in paths) {
    lines = readLines(path, warn = FALSE)
    if (any(grepl("Unhandled promise error", lines, fixed = TRUE)))
      stop("Unhandled browser promise error; see the owned log: ", basename(path))
  }
  invisible(NULL)
}

optional_controller_phases = c("controller", "child-launch", "child-wait", "child-result",
  "raw-result-json", "child-warning-gate", "promise-log-gate", "test-result-gate",
  "kill-tree", "marker-kill", "family-root-query", "family-marked-query", "cleanup-json",
  "integration-summary-json", "integration-progress-json", "controller-witness-json")

optional_controller_state = function() {
  state = new.env(parent = emptyenv())
  state$phase = "controller"
  state$label = "controller"
  state$total = 0L
  state$diagnostics = list()
  state$summary = NULL
  state
}

optional_controller_phase = function(state, phase, label) {
  if (!phase %in% optional_controller_phases) stop("Unapproved controller phase")
  if (!label %in% c("controller", "dependency-preflight", names(optional_titles)))
    stop("Unapproved controller label")
  state$phase = phase
  state$label = label
  invisible(NULL)
}

optional_controller_diagnostic = function(condition, phase, label) {
  if (!phase %in% optional_controller_phases) phase = "controller"
  if (!label %in% c("controller", "dependency-preflight", names(optional_titles)))
    label = "controller"
  allowed_classes = c("simpleWarning", "warning", "condition", "rlang_warning", "rlang_condition")
  classes = class(condition)
  call = conditionCall(condition)
  head = if (is.call(call)) call[[1L]] else NULL
  name = if (is.name(head)) as.character(head) else "other"
  if (is.call(head) && length(head) == 3L && is.name(head[[1L]]) &&
      as.character(head[[1L]]) %in% c("$", "::", ":::")) {
    name = if (is.name(head[[3L]])) as.character(head[[3L]]) else "other"
  }
  allowed_heads = c("wait", "get_result", "is_alive", "kill_tree", "ps_kill_tree",
    "ps_find_tree", "ps_handle", "write_json", "optional_controller_write", "readLines")
  if (!name %in% allowed_heads) name = "other"
  list(phase = phase, label = label, classes = unname(intersect(classes, allowed_classes)),
    other_class_count = as.integer(sum(!classes %in% allowed_classes)), call_head = name)
}

optional_controller_observe = function(state, condition) {
  state$total = state$total + 1L
  if (length(state$diagnostics) < 25L) {
    state$diagnostics[[length(state$diagnostics) + 1L]] =
      optional_controller_diagnostic(condition, state$phase, state$label)
  }
  invisible(NULL)
}

optional_controller_snapshot = function(state) {
  list(warnings_total = state$total, diagnostics = state$diagnostics,
    diagnostics_truncated = state$total > length(state$diagnostics))
}

optional_controller_write = function(value, path) {
  jsonlite::write_json(value, path, pretty = TRUE, auto_unbox = TRUE, null = "null")
}

optional_controller_run = function(main = optional_integrations_main,
                                    output = file.path(getwd(), "optional-evidence"),
                                    write = optional_controller_write) {
  state = optional_controller_state()
  withCallingHandlers({
    dir.create(output, showWarnings = FALSE, recursive = TRUE)
    outcome = tryCatch(list(value = main(state), error = NULL),
      error = function(e) list(value = NULL, error = e))
    final_error = tryCatch({
      for (attempt in seq_len(2L)) {
        before_attempt = state$total
        if (!is.null(state$summary)) {
          optional_controller_phase(state, "integration-summary-json", "controller")
          state$summary$controller_warnings = optional_controller_snapshot(state)
          state$summary$passed = isTRUE(state$summary$passed) && state$total == 0L &&
            is.null(outcome$error)
          write(state$summary, file.path(output, "integration-summary.json"))
        }
        optional_controller_phase(state, "controller-witness-json", "controller")
        witness = c(list(passed = is.null(outcome$error) && state$total == 0L,
          original_error = !is.null(outcome$error), artifact_finalization_attempt = attempt,
          observation_boundary = "before this artifact write; later warnings remain fatal"),
          optional_controller_snapshot(state))
        write(witness, file.path(output, "controller-warnings.json"))
        if (state$total == before_attempt) break
      }
      NULL
    }, error = identity)
    if (!is.null(outcome$error)) stop(outcome$error)
    if (!is.null(final_error)) stop(final_error)
    if (state$total > 0L) stop("Controller warnings captured: ", state$total)
    invisible(outcome$value)
  }, warning = function(w) optional_controller_observe(state, w))
}

optional_preflight = function() {
  required = c("gptr", "reticulate", "repr", "chromote", "knitr", "rmarkdown",
                "shiny", "httpuv", "later", "bslib", "DBI", "RSQLite", "duckdb")
  stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
  stopifnot(identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"),
    identical(Sys.getenv("NOT_CRAN"), "true"),
    nzchar(Sys.getenv("RETICULATE_PYTHON")), nzchar(Sys.getenv("CHROMOTE_CHROME")))
  stopifnot(!length(gptr:::secret_registered_names()))
  counters = new.env(parent = emptyenv())
  counters$request = 0L
  counters$usage = 0L
  native = nrow(gptr:::usage_log())
  off = list(gptr::gptr_register(gptr::gptr_hook("before_request", function(event, ctx) {
    counters$request = counters$request + 1L
    NULL
  })), gptr::gptr_register(gptr::gptr_hook("usage", function(event, ctx) {
    counters$usage = counters$usage + 1L
    NULL
  })))
  on.exit(for (remove in rev(off)) remove(), add = TRUE)
  quarto = processx::run(Sys.which("quarto"), "--version", timeout = 10)
  rg = processx::run(Sys.which("rg"), "--version", timeout = 5)
  if (!nzchar(Sys.which("perl"))) stop("Perl is unavailable; provision it before integration tests")
  perl = processx::run(Sys.which("perl"), c("-e", "print 42"), timeout = 5)
  stopifnot(identical(perl$stdout, "42"))
  config = reticulate::py_config()
  stopifnot(identical(normalizePath(config$python),
                      normalizePath(Sys.getenv("RETICULATE_PYTHON"))))
  reticulate::py_run_string("import pandas as pd\nimport numpy as np")
  stopifnot(identical(as.integer(reticulate::py_eval("int(pd.Series([1, 2, 3]).sum())")), 6L))
  browser = NULL
  session = NULL
  chrome = NULL
  on.exit({
    if (!is.null(session)) try(session$close(), silent = TRUE)
    if (!is.null(browser)) try(browser$close(), silent = TRUE)
    if (!is.null(chrome) && chrome$is_alive()) chrome$close()
  }, add = TRUE)
  # Keep chromote's original startup bound; use the same arguments as gptr's browser.
  stopifnot(identical(as.numeric(getOption("chromote.timeout", 10)), 10))
  chrome = chromote::Chrome$new(path = Sys.getenv("CHROMOTE_CHROME"),
    args = c(chromote::get_chrome_args(), "--use-mock-keychain"))
  browser = chromote::Chromote$new(browser = chrome)
  session = browser$new_session()
  value = session$Runtime$evaluate("1 + 1", returnByValue = TRUE)$result$value
  stopifnot(identical(as.numeric(value), 2))
  session$close()
  session = NULL
  browser$close()
  browser = NULL
  stopifnot(!chrome$is_alive(), counters$request == 0L, counters$usage == 0L,
             identical(nrow(gptr:::usage_log()), native))
  list(passed = TRUE, actual_browser = TRUE, browser_closed = TRUE,
    browser_expression_value = value, browser_startup_bound_s = 10L,
    configured_python = config$python, python_version = as.character(config$version),
    quarto_version = trimws(quarto$stdout), ripgrep_version = strsplit(rg$stdout, "\n")[[1L]][1L],
    perl_path = unname(Sys.which("perl")), perl_expression_value = perl$stdout,
    r_version = R.version.string,
    package_versions = as.list(stats::setNames(vapply(required, function(name) {
      as.character(utils::packageVersion(name))
    }, ""), required)),
    before_request_events = counters$request, usage_events = counters$usage,
    fresh_native_usage_rows = nrow(gptr:::usage_log()) - native,
    request_observer_scope = "dependency preflight only; source suites use fake/replay assertions")
}

optional_integrations_main = function(controller) {
  root = normalizePath(getwd())
  output = file.path(root, "optional-evidence")
  dir.create(output, showWarnings = FALSE)
  pattern = Sys.getenv("GPTR_OPTIONAL_FILTER")
  if (!nzchar(pattern)) stop("Set the explicit optional integration filter")
  files = optional_select(pattern, root)
  summary = list(passed = FALSE, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    filter = pattern, selected_files = basename(files), per_file_timeout_s = 300L,
    external_live_tests_enabled = FALSE, results = list())
  on.exit({
    optional_controller_phase(controller, "integration-summary-json", "controller")
    summary$controller_warnings = optional_controller_snapshot(controller)
    if (controller$total > 0L) summary$passed = FALSE
    controller$summary = summary
    optional_controller_write(summary, file.path(output, "integration-summary.json"))
  }, add = TRUE)
  child = function(action, file = NULL) {
    source("dev/ci/optional-integrations.R", local = TRUE)
    conditions = new.env(parent = emptyenv())
    conditions$warnings = character()
    conditions$warning_details = list()
    conditions$advisory = 0L
    observe = function(w) {
      if (grepl("^package .+ was built under R version", conditionMessage(w))) {
        conditions$advisory = conditions$advisory + 1L
      } else {
        conditions$warnings = c(conditions$warnings, paste(class(w), collapse = "/"))
        if (length(conditions$warning_details) < 25L)
          conditions$warning_details[[length(conditions$warning_details) + 1L]] =
            optional_condition_diagnostic(w)
      }
    }
    result = withCallingHandlers({
      if (action == "preflight") {
        optional_preflight()
      } else {
        pkgload::load_all(".", helpers = FALSE, quiet = TRUE)
        optional_result_rows(testthat::test_file(file,
          reporter = testthat::LocationReporter$new(file = stderr()),
          package = "gptr", load_package = "none"))
      }
    }, warning = observe)
    list(result = result, outside_test_warning_classes = conditions$warnings,
         outside_test_warnings = conditions$warning_details,
         outside_test_warning_total = length(conditions$warnings),
         outside_test_warnings_truncated = length(conditions$warnings) > 25L,
         known_build_advisories = conditions$advisory)
  }
  invoke = function(action, label, file = NULL, timeout = 300) {
    log = file.path(output, paste0(label, ".log"))
    stdout_log = file.path(output, paste0(label, "-stdout.log"))
    marker = optional_marker()
    stopifnot(!nzchar(Sys.getenv(marker)))
    process = NULL
    on.exit({
      cleanup_error = tryCatch({
        optional_controller_phase(controller, "kill-tree", label)
        if (!is.null(process)) process$kill_tree()
        optional_controller_phase(controller, "marker-kill", label)
        ps::ps_kill_tree(marker)
        NULL
      }, error = function(e) substr(conditionMessage(e), 1L, 2000L))
      family = optional_wait_family(function() {
        optional_controller_phase(controller, "family-root-query", label)
        is.null(process) || !process$is_alive()
      }, function() {
        optional_controller_phase(controller, "family-marked-query", label)
        ps::ps_find_tree(marker)
      })
      settled = family$settled && is.null(cleanup_error)
      optional_controller_phase(controller, "cleanup-json", label)
      jsonlite::write_json(c(list(passed = settled, settlement_bound_s = 5L,
        cleanup_error = cleanup_error, scope = "owned child and marker-inheriting descendants"),
        family),
        file.path(output, paste0(label, "-cleanup.json")), pretty = TRUE,
        auto_unbox = TRUE, null = "null")
      if (!settled) stop("Owned child family did not settle: ", label)
    }, add = TRUE)
    optional_controller_phase(controller, "child-launch", label)
    process = callr::r_bg(child, list(action, file), stdout = stdout_log, stderr = log,
      cmdargs = c("--vanilla", "--slave"), user_profile = FALSE, system_profile = FALSE,
      cleanup_tree = TRUE, supervise = FALSE,
      env = c(callr::rcmd_safe_env(), stats::setNames("YES", marker)))
    optional_controller_phase(controller, "child-wait", label)
    process$wait(timeout * 1000)
    if (process$is_alive()) stop("Owned child deadline exceeded: ", label)
    optional_controller_phase(controller, "child-result", label)
    result = process$get_result()
    optional_controller_phase(controller, "raw-result-json", label)
    jsonlite::write_json(result, file.path(output, paste0(label, "-results.json")),
      pretty = TRUE, auto_unbox = TRUE, null = "null")
    optional_controller_phase(controller, "child-warning-gate", label)
    stopifnot(!length(result$outside_test_warning_classes))
    optional_controller_phase(controller, "promise-log-gate", label)
    optional_check_logs(c(stdout_log, log))
    result
  }
  summary$preflight = tryCatch({
    observed = invoke("preflight", "dependency-preflight", timeout = 90)
    list(passed = isTRUE(observed$result$passed), witness = observed$result,
      known_build_advisories = observed$known_build_advisories)
  },
    error = function(e) {
      list(passed = FALSE, error_class = class(e)[1L],
        reason = substr(conditionMessage(e), 1L, 2000L))
    })
  if (!isTRUE(summary$preflight$passed)) {
    reason = summary$preflight$reason
    if (is.null(reason)) reason = "Dependency preflight has no positive passing witness"
    stop(reason)
  }
  failures = character()
  for (file in files) {
    name = basename(file)
    started = proc.time()[["elapsed"]]
    cat("Starting ", name, " (300 s bound)\n", sep = "", file = stderr())
    value = tryCatch({
      res = invoke("test", name, file)
      optional_controller_phase(controller, "test-result-gate", name)
      gate = optional_gate(res$result, name, .Platform$OS.type == "windows")
      list(passed = TRUE, gate = gate, known_build_advisories = res$known_build_advisories)
    }, error = function(e) {
      reason = substr(conditionMessage(e), 1L, 2000L)
      cat(name, ": ", reason, "\n", sep = "", file = stderr())
      list(passed = FALSE, error_class = class(e)[1L], reason = reason)
    })
    value$elapsed_s = proc.time()[["elapsed"]] - started
    summary$results[[name]] = value
    if (!isTRUE(value$passed)) failures = c(failures, name)
    optional_controller_phase(controller, "integration-progress-json", name)
    jsonlite::write_json(summary, file.path(output, "integration-progress.json"),
      pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat("Finished ", name, ": ", if (value$passed) "PASS" else "FAIL", "\n",
        sep = "", file = stderr())
  }
  summary$passed = !length(failures) && controller$total == 0L
  if (length(failures))
    stop("Optional integration files failed: ", paste(failures, collapse = ", "))
}

if (sys.nframe() == 0L) optional_controller_run()
