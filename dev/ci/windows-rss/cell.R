(function(args) {
  warning_count = 0L
  observe = function(warning) warning_count <<- warning_count + 1L
  withCallingHandlers({
    stopifnot(length(args) == 1L, .Platform$OS.type == "windows")
    config = jsonlite::read_json(args[[1L]], simplifyVector = FALSE)
    root = normalizePath(config$root, winslash = "/", mustWork = TRUE)
    output = normalizePath(config$output, winslash = "/", mustWork = TRUE)
    stopifnot(config$scope %in% c("full", "fresh"), is.logical(config$collect),
      identical(Sys.getenv("GPTR_SUPERVISOR_RSS_DIAGNOSTIC"), "true"),
      identical(Sys.getenv("GPTR_EXPECTED_SOURCE"), config$source_sha),
      identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
    for (package in c("testthat", "diffobj", "jsonlite", "digest", "ps", "processx", "gptr")) {
      stopifnot(requireNamespace(package, quietly = TRUE))
    }
    # Reporting dependencies are admitted before the unwrapped caller-state boundary.
    support = new.env(parent = baseenv())
    sys.source(file.path(root, "dev/ci/windows-rss/gc-observation.R"), support)
    sys.source(file.path(root, "dev/ci/windows-rss/probe.R"), support)
    library("testthat", character.only = TRUE)
    library("gptr", character.only = TRUE)
    # test_check sets this one framework option; admit its supported check context first.
    old_check = options(cli.hyperlink = FALSE)
    on.exit(options(old_check), add = TRUE)
    reporter = testthat::SummaryReporter$new(show_praise = FALSE, max_reports = Inf)
    setwd(file.path(root, "tests"))
    capture = support$rss_capture(output, config$collect,
      gc_observation = support$bp_gc_observation)
    old = options(gptr.test.rss_capture = capture$callback)
    on.exit(options(old), add = TRUE)
    installed = system.file(package = "gptr")
    installed_files = file.path(installed, c("DESCRIPTION", "NAMESPACE", "R/gptr.rdb",
      "R/gptr.rdx", "Meta/package.rds"))
    installed_before = vapply(installed_files, support$rss_digest, character(1))
    admit = function() {
      for (name in names(config$source_map)) {
        stopifnot(identical(support$rss_digest(file.path(root, name)), config$source_map[[name]]))
      }
      stopifnot(identical(vapply(installed_files, support$rss_digest, character(1)),
        installed_before))
    }
    admit()
    before = support$rss_snapshot()
    result = tryCatch({
      if (identical(config$scope, "full")) {
        testthat::test_check("gptr", reporter = reporter, stop_on_failure = FALSE,
          stop_on_warning = FALSE)
      } else {
        testthat::test_check("gptr", filter = "^proc-writer-runtime$",
          reporter = reporter, stop_on_failure = FALSE,
          stop_on_warning = FALSE)
      }
    }, error = base::identity, interrupt = base::identity)
    after = support$rss_snapshot()
    same = support$rss_flags(before, after)
    rows = if (inherits(result, "condition")) list() else support$rss_result(result)
    failed = inherits(result, "condition") || !length(rows) || warning_count != 0L ||
      !all(same) || capture$state$target_seen != 1L ||
      capture$state$collections != as.integer(config$collect) || capture$state$fatal_seen ||
      any(vapply(rows, function(row) row$failed + row$errors + row$warnings > 0L, logical(1)))
    summary = list(source_sha = config$source_sha, scope = config$scope, collect = config$collect,
      operation_complete = !inherits(result, "condition"), status = if (failed) 1L else 0L,
      product_acceptance = FALSE, rows = rows, whole_warning_count = warning_count,
      all8 = as.list(same), target_seen = capture$state$target_seen,
      collections = capture$state$collections, fatal_seen = capture$state$fatal_seen,
      condition_classes = if (inherits(result, "condition")) class(result) else character(),
      installed_namespace = installed, installed_files_unchanged = FALSE)
    final = tryCatch({
      admit()
      summary$installed_files_unchanged = TRUE
      support$rss_write(summary, file.path(output, "result.json"))
      saveRDS(if (inherits(result, "condition")) NULL else result, file.path(output, "results.rds"))
      last = support$rss_flags(before, support$rss_snapshot())
      stopifnot(all(last), identical(warning_count, 0L))
      NULL
    }, error = base::identity, interrupt = base::identity)
    if (inherits(result, "condition") || inherits(final, "condition")) {
      summary$status = 1L
      summary$whole_warning_count = warning_count
      try(support$rss_write(summary, file.path(output, "result.json")), silent = TRUE)
    }
    if (inherits(result, "condition")) stop(result)
    if (inherits(final, "condition")) stop(final)
    if (failed) stop("Windows RSS comparison cell retained an original failure")
    cat("GPTR-RSS-COMPARISON-CELL-COMPLETE\n")
  }, warning = observe)
})(commandArgs(trailingOnly = TRUE))
