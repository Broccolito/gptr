# Diagnostic-only, default-off hosted token experiment. Source for its pure gates.
# Native authority is confined to the independently owned PowerShell utility.
token_assets = list(
  "README.md" = list(
    bytes = 7914L, sha256 = "967cde94b13c847939d593a5815a512f72fc1139eab9937e54e10794fb992b15"),
  "amended/helper-proc-writer-runtime.R" = list(
    bytes = 91738L, sha256 = "2acd08d324155ee2fac743d2e5ef1a84d06bde0d677849a546bff6e47863f1a5"),
  "baseline/fixtures/bp-disk-observer.py" = list(
    bytes = 13195L, sha256 = "18347a8f18677e1ec17efe0d345e797393202b6a50ec3dd1321b888da3314451"),
  "baseline/helper-bp-disk-observer.R" = list(
    bytes = 5680L, sha256 = "2124533f1a8c31e1778b50ca5b3224c21317021648b09e05fed676d1a8a2e682"),
  "baseline/helper-proc-backpressure.R" = list(
    bytes = 18600L, sha256 = "766798d6bd8e69044f81d6dec332d8f79804cdeb3c737f5284ad0b1890baf5c7"),
  "baseline/helper-proc-writer-runtime.R" = list(
    bytes = 51608L, sha256 = "56a0abb8eb595fbd103c8f423c4b5dba9438a5644c3dce19126ff1d70915f482"),
  "baseline/test-proc-writer-runtime.R" = list(
    bytes = 46164L, sha256 = "9a03efc17f572532104814048bcbb0a703de8c4ef644207690494a92f7c4eb63"),
  "controls/test-token-native.R" = list(
    bytes = 3737L, sha256 = "e4e23f3ebd7d624c1158e70a55422996951c21c33eb1b40292e02df6255ad9a1"),
  "controls/test-token-protocol.R" = list(
    bytes = 4101L, sha256 = "833bc3981343c217bd0d0afcb80e032d191a90692ca10afa4bbc4aa2ee2f1de8"),
  "current-token.cs" = list(
    bytes = 13340L, sha256 = "c8ca069362b0a07a8a16187c9a8d32b60d685a29b0ecf36712d6baf26ebffb88"),
  "experimental-helper.patch" = list(
    bytes = 41084L, sha256 = "5b1f1004bd7d0c2a06fe4746bb077a1424a64751ef7463928edf04c082418fe4"),
  "token-protocol.R" = list(
    bytes = 3379L, sha256 = "85620345d0756a8a50f6fe08a5efb1c1355ff67202a4e4b9b7da58d35036c921"),
  "token-trial.ps1" = list(
    bytes = 4454L, sha256 = "aae0e9b54331f8dc3a94bc2e8fe49d734bbc74345dbfb69ac803e4d28142e2c6"),
  "manifest.json" = list(
    bytes = 4423L, sha256 = "c874e9eb49204a990bd3d3a8183c059bf01fc558d58ca6fd30ab9af783ae34aa"))

token_support_file = file.path("dev", "ci", "optional-integrations.R")
if (!file.exists(token_support_file)) {
  token_support_file = file.path("..", "optional-integrations.R")
}
token_support = new.env(parent = baseenv())
sys.source(token_support_file, envir = token_support)

token_titles = list(
  "token-protocol" = c(
    "owned token evidence requires a closed nonvacuous A-B-A sequence",
    "owned token evidence refuses missing duplicate and reordered records",
    "owned token evidence rejects arbitrary fields values and private text",
    "owned token evidence refuses ineffective adjustment or uncertain restoration",
    "unchanged denial outcomes do not identify a token contribution",
    "owned token streaming admission keeps every exact record in order",
    "owned token streaming rejects unknown failure and ineffective state"),
  "token-native" = "owned-token A-B-A retains the strict native absence oracle")

token_nomination = function(optional, platform, nofollow, source, windows) {
  if (!identical(optional, "true") || !identical(platform, "windows") ||
      !identical(nofollow, "true") || !isTRUE(windows) || !is.character(source) ||
      length(source) != 1L || is.na(source) || !grepl("^[0-9a-f]{40}$", source)) {
    stop("Invalid token experiment nomination")
  }
  invisible(TRUE)
}

token_verify_packet = function(packet, read = function(path, n) readBin(path, "raw", n = n),
                               hash = function(bytes) {
                                 digest::digest(bytes, algo = "sha256", serialize = FALSE)
                               }) {
  loaded = list()
  for (name in names(token_assets)) {
    expected = token_assets[[name]]
    bytes = read(file.path(packet, name), expected$bytes + 1L)
    if (!is.raw(bytes) || length(bytes) != expected$bytes ||
        !identical(hash(bytes), expected$sha256)) stop("Token packet identity mismatch")
    if (name %in% c("baseline/helper-proc-writer-runtime.R",
                   "amended/helper-proc-writer-runtime.R")) loaded[[name]] = bytes
  }
  original = loaded[["baseline/helper-proc-writer-runtime.R"]]
  helper = loaded[["amended/helper-proc-writer-runtime.R"]]
  if (!identical(length(original), 51608L) ||
      !identical(helper[seq_along(original)], original)) stop("Token helper prefix changed")
  list(review_manifest_sha256 = token_assets[["manifest.json"]]$sha256,
    files_verified = length(token_assets), original_helper_prefix_bytes = length(original))
}

token_same_function = function(actual, expression) {
  if (!is.function(actual) || !is.call(expression) ||
      !identical(expression[[1L]], as.name("function"))) return(FALSE)
  identical(formals(actual), expression[[2L]]) &&
    identical(deparse(body(actual), width.cutoff = 500L),
              deparse(expression[[3L]], width.cutoff = 500L))
}

token_installed_witness = function(root = getwd()) {
  source = Sys.getenv("GPTR_EXPECTED_SOURCE")
  if (!grepl("^[0-9a-f]{40}$", source)) stop("Missing exact installed-source nomination")
  library = normalizePath(.libPaths()[[1L]], winslash = "/", mustWork = TRUE)
  package = normalizePath(find.package("gptr"), winslash = "/", mustWork = TRUE)
  expected = normalizePath(file.path(library, "gptr"), winslash = "/", mustWork = TRUE)
  if (!identical(package, expected) ||
      !file.exists(file.path(package, "Meta", "package.rds"))) {
    stop("Token tests require the nominated installed package")
  }
  namespace = asNamespace("gptr")
  version = as.character(utils::packageVersion("gptr"))
  if (!identical(version, unname(read.dcf(file.path(root, "DESCRIPTION"))[1L, "Version"]))) {
    stop("Installed package version differs from source")
  }
  files = c(proc_spawn = "R/proc-spawn.R", proc_writer_acl = "R/proc-spawn.R",
    proc_cleanup_record = "R/proc-supervise.R", kill_all = "R/proc-supervise.R")
  comparisons = vapply(names(files), function(name) {
    expressions = parse(file.path(root, files[[name]]), keep.source = FALSE)
    matches = Filter(function(expression) {
      is.call(expression) && length(expression) == 3L &&
        identical(expression[[1L]], as.name("=")) &&
        identical(expression[[2L]], as.name(name))
    }, as.list(expressions))
    length(matches) == 1L &&
      token_same_function(get(name, namespace, inherits = FALSE), matches[[1L]][[3L]])
  }, logical(1))
  if (!all(comparisons)) stop("Installed token runtime differs from nominated source")
  list(source_sha = source, package_version = version, installed_library = library,
    installed_package = package, comparisons = as.list(comparisons),
    scope = "installed namespace and four exact token/lifecycle functions")
}

token_raw_gate = function(observation, action, source) {
  expected = token_titles[[action]]
  if (!length(expected) || !is.list(observation) || !is.list(observation$result) ||
      !identical(names(observation$result), c("rows", "installed", "packet")) ||
      !identical(observation$outside_test_warning_total, 0L) ||
      length(observation$outside_test_warning_classes) ||
      !identical(observation$known_build_advisories, 0L)) stop("Token child warnings or shape")
  result = observation$result
  installed = result$installed
  functions = c("proc_spawn", "proc_writer_acl", "proc_cleanup_record", "kill_all")
  if (!is.list(installed) || !identical(installed$source_sha, source) ||
      !identical(names(installed$comparisons), functions) ||
      !all(vapply(installed$comparisons, identical, logical(1), TRUE)) ||
      !identical(result$packet$review_manifest_sha256,
        token_assets[["manifest.json"]]$sha256) ||
      !identical(result$packet$files_verified, length(token_assets)) ||
      !identical(result$packet$original_helper_prefix_bytes, 51608L)) {
    stop("Token installed or immutable packet witness is incomplete")
  }
  rows = result$rows
  if (!is.list(rows) || length(rows) != length(expected)) stop("Missing token raw cases")
  names = vapply(rows, function(row) {
    if (!is.list(row) || !is.character(row$test) || length(row$test) != 1L ||
        is.na(row$test)) stop("Invalid token raw row")
    for (field in c("passed", "failed", "warnings", "skipped")) {
      value = row[[field]]
      if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
          value < 0 || value != floor(value)) stop("Invalid token raw count")
    }
    if (row$failed || row$warnings || row$skipped || row$passed < 1L)
      stop("Failed warned skipped or empty token case")
    row$test
  }, "")
  if (!identical(names, expected)) stop("Unknown duplicated or reordered token raw cases")
  list(passed = TRUE, action = action, cases = length(rows), titles = expected,
    assertions = sum(vapply(rows, function(row) row$passed, 0)), raw_rows = rows)
}

token_child = function(action) {
  packet = normalizePath(Sys.getenv("GPTR_TOKEN_EXPERIMENT_PACKET"),
    winslash = "/", mustWork = TRUE)
  proof = token_verify_packet(packet)
  installed = token_installed_witness()
  file = switch(action, "token-protocol" = "test-token-protocol.R",
    "token-native" = "test-token-native.R", stop("Invalid token child action"))
  scope = new.env(parent = asNamespace("testthat"))
  sys.source(file.path(packet, "token-protocol.R"), envir = scope)
  rows = token_support$optional_result_rows(testthat::test_file(file.path(packet, "controls", file),
    env = scope, reporter = testthat::LocationReporter$new(file = stderr()),
    package = "gptr", load_package = "none"))
  list(rows = rows, installed = installed, packet = proof)
}

token_settlement_gate = function(family, cleanup_error, launch_unknown) {
  is.list(family) && isTRUE(family$settled) && isTRUE(family$root_stopped) &&
    identical(family$remaining_marked_processes, 0L) && is.null(cleanup_error) && !launch_unknown
}

token_invoke = function(action, root, output, controller) {
  if (!action %in% names(token_titles)) stop("Invalid token child action")
  log = file.path(output, paste0(action, ".log"))
  stdout_log = file.path(output, paste0(action, "-stdout.log"))
  marker = token_support$optional_marker()
  stopifnot(!nzchar(Sys.getenv(marker)))
  dir = tempfile(paste0(action, "-transport-"), tmpdir = output)
  stopifnot(dir.create(dir, mode = "0700"))
  process = NULL
  attempted = FALSE
  outcome = NULL
  on.exit({
    cleanup = tryCatch({
      cleanup_error = tryCatch({
        token_support$optional_controller_phase(controller, "kill-tree", "controller")
        if (!is.null(process)) process$kill_tree()
        token_support$optional_controller_phase(controller, "marker-kill", "controller")
        ps::ps_kill_tree(marker)
        NULL
      }, error = function(e) class(e)[[1L]])
      family = token_support$optional_wait_family(function() {
        token_support$optional_controller_phase(controller, "family-root-query", "controller")
        is.null(process) || !process$is_alive()
      }, function() {
        token_support$optional_controller_phase(controller, "family-marked-query", "controller")
        ps::ps_find_tree(marker)
      })
      launch_unknown = attempted && is.null(process)
      settled = token_settlement_gate(family, cleanup_error, launch_unknown)
      token_support$optional_controller_phase(controller, "cleanup-json", "controller")
      token_support$optional_controller_write(c(list(passed = settled, settlement_bound_s = 5L,
        cleanup_error_class = cleanup_error, launch_unknown = launch_unknown,
        scope = "owned child and marker-inheriting descendants"), family),
        file.path(output, paste0(action, "-cleanup.json")))
      if (settled) unlink(dir, recursive = TRUE)
      if (!settled) stop("Token owned child family did not settle")
      NULL
    }, error = identity, interrupt = identity)
    if (!is.null(cleanup) && (is.null(outcome) || is.null(outcome$error))) stop(cleanup)
  }, add = TRUE)
  outcome = tryCatch({
    token_support$optional_controller_phase(controller, "child-launch", "controller")
    env = c(Sys.getenv(), stats::setNames("YES", marker),
      GPTR_TOKEN_EXPERIMENT_PACKET = file.path(root, "dev", "ci", "windows-token", "packet"))
    if (action %in% c("held-protocol", "held-native")) {
      env = c(env, GPTR_HELD_TOKEN_PACKET =
        file.path(root, "dev", "ci", "windows-token", "held-packet"))
    }
    attempted = TRUE
    process = token_support$optional_child_start(action, NULL, root, dir, stdout_log, log, env)
    token_support$optional_controller_phase(controller, "child-wait", "controller")
    process$wait(300000L)
    if (process$is_alive()) stop("Token owned child deadline exceeded")
    token_support$optional_controller_phase(controller, "child-result", "controller")
    result = token_support$optional_child_result(process, file.path(dir, "result.rds"))
    token_support$optional_controller_phase(controller, "raw-result-json", "controller")
    token_support$optional_controller_write(result,
      file.path(output, paste0(action, "-results.json")))
    token_support$optional_controller_phase(controller, "promise-log-gate", "controller")
    token_support$optional_check_logs(c(stdout_log, log))
    token_support$optional_controller_phase(controller, "test-result-gate", "controller")
    gate = token_raw_gate(result, action, Sys.getenv("GPTR_EXPECTED_SOURCE"))
    list(value = list(gate = gate, witness = result), error = NULL)
  }, error = function(e) list(value = NULL, error = e),
     interrupt = function(e) list(value = NULL, error = e))
  if (!is.null(outcome$error)) stop(outcome$error)
  outcome$value
}

token_main = function(controller) {
  token_nomination(Sys.getenv("GPTR_EXPERIMENT_OPTIONAL"),
    Sys.getenv("GPTR_EXPERIMENT_PLATFORM"), Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"),
    Sys.getenv("GPTR_EXPECTED_SOURCE"), .Platform$OS.type == "windows")
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "false")) stop("Token experiment is offline")
  root = normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  output = file.path(root, "optional-evidence", "windows-token")
  stopifnot(dir.exists(output))
  summary = list(passed = FALSE, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    diagnostic_only = TRUE, feature_oracle_waived = FALSE, per_file_timeout_s = 300L,
    compiler_pure_checks = 10L, protocol_cases = 7L, native_cases = 1L, results = list())
  on.exit({
    controller$summary = summary
  }, add = TRUE)
  for (action in names(token_titles)) {
    # The pure gate completes before any compiler or token adjustment can launch.
    summary$results[[action]] = token_invoke(action, root, output, controller)
    if (controller$total > 0L) stop("Token controller warnings captured")
  }
  summary$passed = controller$total == 0L
  invisible(summary)
}

if (sys.nframe() == 0L) {
  local({
    args = commandArgs(TRUE)
    output = file.path(getwd(), "optional-evidence", "windows-token")
    if (identical(args, "verify-install")) {
      withCallingHandlers({
        token_nomination(Sys.getenv("GPTR_EXPERIMENT_OPTIONAL"),
          Sys.getenv("GPTR_EXPERIMENT_PLATFORM"), Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"),
          Sys.getenv("GPTR_EXPECTED_SOURCE"), .Platform$OS.type == "windows")
        stopifnot(dir.create(output, mode = "0700"),
          identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
        packet = token_verify_packet(file.path("dev", "ci", "windows-token", "packet"))
        token_support$optional_controller_write(
          list(installed = token_installed_witness(), packet = packet),
          file.path(output, "installed-identity.json"))
      }, warning = function(w) stop(w))
    } else if (identical(args, "run")) {
      token_support$optional_controller_run(main = token_main, output = output)
    } else {
      stop("Choose the exact token controller action")
    }
  })
}
