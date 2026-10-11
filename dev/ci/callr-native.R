# Dedicated disposable-process validation; dependency installations stay private to CI.
callr_native_owned = function(command, args, output, paths, compat = FALSE) {
  source("dev/ci/optional-integrations.R", local = TRUE)
  marker = optional_marker()
  stopifnot(!nzchar(Sys.getenv(marker)))
  environment = c(Sys.getenv(), stats::setNames("YES", marker))
  if (compat) environment = environment[!startsWith(toupper(names(environment)), "OTEL_")]
  process = NULL
  peak_rss = 0
  samples = 0L
  outcome = tryCatch({
    process = processx::process$new(command, args, env = environment,
      stdout = paths[[1L]], stderr = paths[[2L]], cleanup_tree = TRUE, supervise = FALSE)
    started = proc.time()[["elapsed"]]
    repeat {
      process$wait(100)
      sizes = file.info(paths)$size
      if (any(sizes > 1024 * 1024, na.rm = TRUE)) stop("Validation output exceeded bound")
      family = ps::ps_find_tree(marker)
      rss = vapply(family, function(handle) {
        tryCatch(ps::ps_memory_info(handle)[["rss"]], error = function(e) {
          if (ps::ps_is_running(handle)) stop(e)
          0
        })
      }, 0)
      peak_rss = max(peak_rss, sum(rss))
      samples = samples + 1L
      if (peak_rss > 2 * 1024^3) stop("Owned validation family exceeded RSS bound")
      if (!process$is_alive()) break
      if (proc.time()[["elapsed"]] - started > 300) stop("Validation deadline exceeded")
    }
    list(status = process$get_exit_status(), error = NULL)
  }, error = function(e) list(status = NULL, error = e))
  cleanup_error = tryCatch({
    if (!is.null(process)) process$kill_tree()
    ps::ps_kill_tree(marker)
    NULL
  }, error = identity)
  settlement = tryCatch(optional_wait_family(function() {
    is.null(process) || !process$is_alive()
  }, function() ps::ps_find_tree(marker)), error = identity)
  settled = !inherits(settlement, "error") && isTRUE(settlement$settled) &&
    is.null(cleanup_error)
  cleanup = c(list(passed = settled, peak_family_rss = peak_rss, samples = samples,
    original_error_class = if (is.null(outcome$error)) NULL else class(outcome$error)[1L],
    cleanup_error_class = if (is.null(cleanup_error)) NULL else class(cleanup_error)[1L]),
    if (inherits(settlement, "error")) list(settlement_error_class = class(settlement)[1L])
    else settlement)
  publication_error = tryCatch({
    jsonlite::write_json(cleanup, file.path(output, "cleanup.json"),
      auto_unbox = TRUE, pretty = TRUE, null = "null")
    NULL
  }, error = identity)
  if (!is.null(outcome$error)) {
    if (!is.null(publication_error)) warning("Cleanup evidence publication also failed")
    stop(outcome$error)
  }
  if (!is.null(publication_error)) stop(publication_error)
  if (!settled) stop("Owned validation family did not settle; retained cleanup record")
  outcome$status
}

callr_native_install = function(args) {
  stopifnot(length(args) == 3L)
  source = normalizePath(args[[1L]], mustWork = TRUE)
  library = normalizePath(args[[2L]], mustWork = TRUE)
  output = normalizePath(args[[3L]], mustWork = TRUE)
  command = Sys.which("R")
  stopifnot(nzchar(command))
  status = callr_native_owned(command,
    c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", library), source),
    output, c(file.path(output, "install.log"), file.path(output, "install-stderr.log")))
  stopifnot(identical(status, 0L))
}

callr_native_compat_preflight = function() {
  stopifnot(!any(startsWith(toupper(names(Sys.getenv())), "OTEL_")),
    !"otelsdk" %in% loadedNamespaces())
  packages = c("callr", "processx", "testthat", "withr", "otelsdk")
  dependencies = stats::setNames(lapply(packages, function(package) {
    as.character(utils::packageVersion(package))
  }), packages)
  stopifnot(identical(dependencies$callr, "3.8.0"),
    identical(dependencies$processx, "3.9.0"),
    utils::packageVersion("testthat") >= "3.2.0",
    utils::packageVersion("withr") >= "2.3.0",
    utils::packageVersion("otelsdk") >= "0.2.0",
    requireNamespace("otelsdk", quietly = TRUE),
    "with_otel_record" %in% getNamespaceExports("otelsdk"))
  initially_off = !otel::is_tracing_enabled("org.r-lib.callr")
  recorded = otelsdk::with_otel_record({
    tracer = otel::get_tracer("gptr.compat.preflight")
    span = tracer$start_local_active_span("compat-preflight")
    span$end()
    7
  }, what = "traces")
  stopifnot(initially_off, identical(recorded$value, 7),
    length(recorded$traces) == 1L,
    identical(recorded$traces[[1L]]$name, "compat-preflight"),
    !otel::is_tracing_enabled("org.r-lib.callr"),
    !any(startsWith(toupper(names(Sys.getenv())), "OTEL_")))
  list(dependencies = dependencies, exporter_free = TRUE)
}

callr_native_child = function(file, result_path, library) {
  warnings = new.env(parent = emptyenv())
  warnings$total = 0L
  warnings$classes = character()
  withCallingHandlers({
    .libPaths(c(library, .libPaths()))
    stopifnot(identical(as.character(utils::packageVersion("callr")), "3.8.0"),
      identical(normalizePath(dirname(find.package("callr"))), normalizePath(library)))
    source("dev/ci/optional-integrations.R", local = TRUE)
    compat = basename(file) %in% c("test-r-bg.R", "test-hook.R", "test-timeout.R", "test-otel.R")
    upstream = identical(basename(file), "test-native-child-env.R") || compat
    compatibility = if (compat) callr_native_compat_preflight() else list()
    if (!upstream) pkgload::load_all(".", helpers = FALSE, quiet = TRUE)
    raw = testthat::test_file(file,
      reporter = testthat::LocationReporter$new(file = stderr()),
      package = if (upstream) "callr" else "gptr",
      load_package = if (upstream) "installed" else "none")
    result = list(rows = optional_result_rows(raw), errors = sum(vapply(raw, function(test) {
      sum(vapply(test$results, inherits, logical(1), what = "expectation_error"))
    }, 0L)))
  if (compat) stopifnot(!otel::is_tracing_enabled("org.r-lib.callr"),
    !any(startsWith(toupper(names(Sys.getenv())), "OTEL_")))
  saveRDS(c(list(result = result$rows, fixture_errors_total = result$errors,
    outside_test_warning_total = warnings$total,
    outside_test_warning_classes = warnings$classes,
    callr_version = as.character(utils::packageVersion("callr")),
    processx_version = as.character(utils::packageVersion("processx")),
    private_library_exact = identical(normalizePath(dirname(find.package("callr"))),
      normalizePath(library))), compatibility), result_path)
  }, warning = function(w) {
    warnings$total = warnings$total + 1L
    warnings$classes = unique(c(warnings$classes,
      intersect(class(w), c("simpleWarning", "warning", "condition", "rlang_warning"))))
  })
  if (warnings$total > 0L) stop("Test child warnings are fatal")
}

callr_native_main = function(args) {
  stopifnot(length(args) == 4L)
  mode = match.arg(args[[1L]], c("stock", "patched"))
  compat_files = c("compat-r-bg" = "test-r-bg.R", "compat-hook" = "test-hook.R",
    "compat-timeout" = "test-timeout.R", "compat-otel" = "test-otel.R")
  packet = match.arg(args[[2L]], c("strict", "admission", "upstream", names(compat_files)))
  compat = packet %in% names(compat_files)
  library = normalizePath(args[[3L]], mustWork = TRUE)
  output = args[[4L]]
  .libPaths(c(library, .libPaths()))
  stopifnot(identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"),
    identical(Sys.getenv("NOT_CRAN"), "true"),
    identical(as.character(utils::packageVersion("callr")), "3.8.0"),
    identical(normalizePath(dirname(find.package("callr"))), library))
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  source("dev/ci/optional-integrations.R", local = TRUE)
  registry = jsonlite::read_json("dev/upstream/callr-native-environment/test-registry.json",
    simplifyVector = TRUE)
  file = registry[[packet]]$file
  expected = registry[[packet]]$titles
  stopifnot(length(file) == 1L, length(expected) > 0L,
    file %in% c("test-callr-parent-environment.R", "test-callr-startup-admission.R",
      "test-native-child-env.R", unname(compat_files)))
  if (compat) stopifnot(identical(file, unname(compat_files[[packet]])))
  test_file = if (packet == "upstream" || compat) {
    file.path(dirname(library), "source", "tests", "testthat", file)
  } else {
    file.path("tests", "testthat", file)
  }
  stdout = file.path(output, "stdout.log")
  stderr = file.path(output, "stderr.log")
  result_path = file.path(output, "raw.rds")
  command = file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") command = paste0(command, ".exe")
  expression = paste0("a=commandArgs(TRUE);source('dev/ci/callr-native.R');",
    "callr_native_child(a[[1]],a[[2]],a[[3]])")
  started = proc.time()[["elapsed"]]
  status = callr_native_owned(command,
    c("--vanilla", "-e", expression, test_file,
      result_path, library), output, c(stdout, stderr, result_path), compat = compat)
  stopifnot(identical(status, 0L), file.exists(result_path))
  observed = readRDS(result_path)
  rows = observed$result
  titles = vapply(rows, function(x) x$test, "")
  counts = function(name) sum(vapply(rows, function(x) as.integer(x[[name]]), 0L))
  structure_ok = identical(sort(titles), sort(expected)) && !anyDuplicated(titles) &&
    all(vapply(rows, function(x) x$passed > 0L, logical(1))) &&
    counts("skipped") == 0L && counts("warnings") == 0L &&
    identical(observed$fixture_errors_total, 0L) &&
    identical(observed$outside_test_warning_total, 0L) &&
    !length(observed$outside_test_warning_classes) && isTRUE(observed$private_library_exact)
  if (compat) structure_ok = structure_ok && isTRUE(observed$exporter_free) &&
    is.list(observed$dependencies) &&
    identical(names(observed$dependencies),
      c("callr", "processx", "testthat", "withr", "otelsdk")) &&
    all(vapply(observed$dependencies, function(version) {
      is.character(version) && length(version) == 1L && !is.na(version) && nzchar(version)
    }, logical(1)))
  summary = list(mode = mode, packet = packet, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    os = .Platform$OS.type, structural_gates_passed = isTRUE(structure_ok),
    passed = isTRUE(structure_ok) && counts("failed") == 0L,
    totals = list(passed = counts("passed"), failed = counts("failed"),
      warnings = counts("warnings"), skipped = counts("skipped")),
    elapsed_s = proc.time()[["elapsed"]] - started, observation = observed)
  jsonlite::write_json(summary, file.path(output, "results.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (!isTRUE(structure_ok)) stop("Strict validation structure/warning/skip gate failed")
  if (!isTRUE(summary$passed)) stop("Observed assertions failed; retained raw evidence")
  invisible(summary)
}

if (sys.nframe() == 0L) {
  args = commandArgs(trailingOnly = TRUE)
  warnings = new.env(parent = emptyenv())
  warnings$total = 0L
  warnings$classes = character()
  warnings$other = 0L
  withCallingHandlers({
    outcome = tryCatch({
      if (identical(args[[1L]], "install")) {
        callr_native_install(args[-1L])
      } else {
        callr_native_main(args)
      }
      NULL
    }, error = identity)
    finalization_error = NULL
    for (attempt in seq_len(2L)) {
      before = warnings$total
      finalization_error = tryCatch({
        jsonlite::write_json(list(passed = warnings$total == 0L, warnings_total = warnings$total,
          warning_classes = warnings$classes, other_class_count = warnings$other,
          observation_boundary = "before this write; later warnings remain fatal"),
          file.path(args[[4L]], "controller-warnings.json"), auto_unbox = TRUE, pretty = TRUE)
      NULL
      }, error = identity)
      if (!is.null(finalization_error) || warnings$total == before) break
    }
    if (inherits(outcome, "error")) stop(outcome)
    if (!is.null(finalization_error)) stop(finalization_error)
    if (warnings$total > 0L) stop("Validation controller warnings are fatal")
  }, warning = function(w) {
    warnings$total = warnings$total + 1L
    allowed = c("simpleWarning", "warning", "condition", "rlang_warning", "rlang_condition")
    warnings$classes = unique(c(warnings$classes, intersect(class(w), allowed)))
    warnings$other = warnings$other + sum(!class(w) %in% allowed)
  })
}
