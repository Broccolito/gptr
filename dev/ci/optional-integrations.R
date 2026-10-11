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
  "test-windows-security.R" = c(
    "Windows true symbolic links are readable and detached without deleting targets",
    "Windows safe instruction links remain while escaped and guarded inputs stay private",
    "Windows cache and checkpoint cleanup never follow foreign directory links",
    "Windows scrub excludes escaping links and never writes through a foreign lock root",
    "Windows checkpoint walks label links and forbid restoring through them",
    "Windows writes resolve links and edits refuse duplicate physical file operations",
    "Windows settings refresh after a same-size rewrite with unchanged file timestamps",
    "Windows same-size gated rewrites revoke trust even with unchanged file timestamps"),
  "test-proc-windows-backpressure.R" = c(
    "real child duplex backpressure preserves every 4 MB stdout and stderr line",
    "a real no-reader child returns the typed stdin timeout under external bounds",
    "a real queued 4 MB write leaves reactor cancellation responsive with no late exit")
)

optional_select = function(pattern, root) {
  files = names(optional_titles)[grepl(pattern, names(optional_titles))]
  if (!length(files)) stop("No approved optional integration files selected")
  paths = file.path(root, "tests", "testthat", files)
  if (!all(file.exists(paths))) stop("Missing selected integration files")
  paths
}

optional_allowed_skip = function(file, name, windows) {
  if (!windows && identical(file, "test-windows-security.R"))
    return(name %in% optional_titles[[file]])
  windows && ((identical(file, "test-artifact-app.R") && identical(name,
    "the access token is 128 random bits from openssl or /dev/urandom")) ||
    (identical(file, "test-bridge-lang.R") && name %in% c(
      "shell engines run through peter$sh() without registered keys and with a timeout",
      "the cmd engine is refused outside Windows")))
}

optional_gate = function(rows, file, windows) {
  if (!length(rows)) stop("No test cases selected")
  if (any(vapply(rows, function(x) x$failed > 0L, logical(1)))) stop("Failed assertions")
  if (any(vapply(rows, function(x) x$warnings > 0L, logical(1)))) stop("Warnings captured")
  for (row in rows) if (row$skipped && !optional_allowed_skip(file, row$test, windows))
    stop("Skipped integration case: ", row$test)
  expected = optional_titles[[file]]
  names = vapply(rows, function(x) x$test, "")
  if (!all(expected %in% names)) stop("Missing mandatory integration cases")
  platform_only = !windows && identical(file, "test-windows-security.R")
  for (name in expected) {
    selected = rows[names == name]
    if (length(selected) != 1L) stop("Duplicate mandatory integration case")
    if (!platform_only && (selected[[1L]]$skipped || selected[[1L]]$passed < 1L))
      stop("Mandatory integration has no passing assertions: ", name)
  }
  if (!platform_only && sum(vapply(rows, function(x) x$passed, 0L)) < 1L)
    stop("No passing assertions")
  list(passed = TRUE, mandatory_cases = expected, platform_guard_only = platform_only,
       rows = rows)
}

optional_result_rows = function(result) {
  lapply(result, function(test) {
    entries = test$results
    count = function(classes) sum(vapply(entries, inherits, logical(1), what = classes))
    list(test = test$test, passed = count("expectation_success"),
      failed = count(c("expectation_failure", "expectation_error")),
      warnings = count(c("expectation_warning", "warning")), skipped = count("expectation_skip"))
  })
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
    package_versions = as.list(stats::setNames(vapply(required, function(name)
      as.character(utils::packageVersion(name)), ""), required)),
    before_request_events = counters$request, usage_events = counters$usage,
    fresh_native_usage_rows = nrow(gptr:::usage_log()) - native,
    request_observer_scope = "dependency preflight only; source suites use fake/replay assertions")
}

optional_integrations_main = function() {
  root = normalizePath(getwd())
  output = file.path(root, "optional-evidence")
  dir.create(output, showWarnings = FALSE)
  pattern = Sys.getenv("GPTR_OPTIONAL_FILTER")
  if (!nzchar(pattern)) stop("Set the explicit optional integration filter")
  files = optional_select(pattern, root)
  summary = list(passed = FALSE, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    filter = pattern, selected_files = basename(files), per_file_timeout_s = 300L,
    external_live_tests_enabled = FALSE, results = list())
  on.exit(jsonlite::write_json(summary, file.path(output, "integration-summary.json"),
    pretty = TRUE, auto_unbox = TRUE, null = "null"), add = TRUE)
  child = function(action, file = NULL) {
    source("dev/ci/optional-integrations.R", local = TRUE)
    conditions = new.env(parent = emptyenv())
    conditions$warnings = character()
    conditions$advisory = 0L
    observe = function(w) {
      if (grepl("^package .+ was built under R version", conditionMessage(w))) {
        conditions$advisory = conditions$advisory + 1L
      } else conditions$warnings = c(conditions$warnings, paste(class(w), collapse = "/"))
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
         known_build_advisories = conditions$advisory)
  }
  invoke = function(action, label, file = NULL, timeout = 300) {
    log = file.path(output, paste0(label, ".log"))
    marker = basename(tempfile("GPTR_OPTIONAL_OWNER_"))
    stopifnot(!nzchar(Sys.getenv(marker)))
    process = NULL
    on.exit({
      cleanup_error = tryCatch({
        if (!is.null(process)) process$kill_tree()
        ps::ps_kill_tree(marker)
        if (!is.null(process)) process$wait(5000)
        NULL
      }, error = function(e) substr(conditionMessage(e), 1L, 2000L))
      remaining = ps::ps_find_tree(marker)
      root_stopped = is.null(process) || !process$is_alive()
      settled = root_stopped && !length(remaining) && is.null(cleanup_error)
      jsonlite::write_json(list(passed = settled, root_stopped = root_stopped,
        remaining_marked_processes = length(remaining), settlement_bound_s = 5L,
        cleanup_error = cleanup_error, scope = "owned child and marker-inheriting descendants"),
        file.path(output, paste0(label, "-cleanup.json")), pretty = TRUE,
        auto_unbox = TRUE, null = "null")
      if (!settled) stop("Owned child family did not settle: ", label)
    }, add = TRUE)
    process = callr::r_bg(child, list(action, file), stdout = log, stderr = log,
      cmdargs = "--vanilla", user_profile = FALSE, system_profile = FALSE,
      cleanup_tree = TRUE, supervise = TRUE,
      env = c(callr::rcmd_safe_env(), stats::setNames("YES", marker)))
    process$wait(timeout * 1000)
    if (process$is_alive()) stop("Owned child deadline exceeded: ", label)
    result = process$get_result()
    stopifnot(!length(result$outside_test_warning_classes))
    lines = readLines(log, warn = FALSE)
    if (any(grepl("Unhandled promise error", lines, fixed = TRUE)))
      stop("Unhandled browser promise error; see the owned log")
    result
  }
  summary$preflight = tryCatch({
    observed = invoke("preflight", "dependency-preflight", timeout = 90)
    list(passed = isTRUE(observed$result$passed), witness = observed$result,
      known_build_advisories = observed$known_build_advisories)
  },
    error = function(e) list(passed = FALSE, error_class = class(e)[1L],
      reason = substr(conditionMessage(e), 1L, 2000L)))
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
    jsonlite::write_json(summary, file.path(output, "integration-progress.json"),
      pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat("Finished ", name, ": ", if (value$passed) "PASS" else "FAIL", "\n",
        sep = "", file = stderr())
  }
  summary$passed = !length(failures)
  if (length(failures))
    stop("Optional integration files failed: ", paste(failures, collapse = ", "))
}

if (sys.nframe() == 0L) optional_integrations_main()
