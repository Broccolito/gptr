# Default-off CI fixture correction. Native token authority stays in the owned utility.
held_core_file = file.path("dev", "ci", "windows-token", "controller.R")
if (!file.exists(held_core_file)) held_core_file = "controller.R"
held_core = new.env(parent = baseenv())
sys.source(held_core_file, envir = held_core)
held_old_assets = held_core$token_assets
held_old_verify = held_core$token_verify_packet
old_scope = new.env(parent = held_core)
old_scope$token_assets = held_old_assets
environment(held_old_verify) = old_scope
held_assets = list(
  "README.md" = list(
    bytes = 6742L, sha256 = "125ab8e1ba1bfead64db85155f1ded56f1e22b5c4575418090c949d21595d88e"),
  "amended/helper-proc-writer-runtime.R" = list(
    bytes = 91830L, sha256 = "432724450b7cfa31a0c389de2cac9c29bff727947427b18776c38ca53d6b7095"),
  "baseline/fixtures/bp-disk-observer.py" = list(
    bytes = 13195L, sha256 = "18347a8f18677e1ec17efe0d345e797393202b6a50ec3dd1321b888da3314451"),
  "baseline/helper-bp-disk-observer.R" = list(
    bytes = 5680L, sha256 = "2124533f1a8c31e1778b50ca5b3224c21317021648b09e05fed676d1a8a2e682"),
  "baseline/helper-proc-backpressure.R" = list(
    bytes = 18600L, sha256 = "766798d6bd8e69044f81d6dec332d8f79804cdeb3c737f5284ad0b1890baf5c7"),
  "baseline/helper-proc-writer-runtime.R" = list(
    bytes = 91738L, sha256 = "2acd08d324155ee2fac743d2e5ef1a84d06bde0d677849a546bff6e47863f1a5"),
  "baseline/ordinary-helper-proc-writer-runtime.R" = list(
    bytes = 51608L, sha256 = "56a0abb8eb595fbd103c8f423c4b5dba9438a5644c3dce19126ff1d70915f482"),
  "baseline/owner-manifest.json" = list(
    bytes = 4423L, sha256 = "c874e9eb49204a990bd3d3a8183c059bf01fc558d58ca6fd30ab9af783ae34aa"),
  "baseline/test-token-native.R" = list(
    bytes = 3737L, sha256 = "e4e23f3ebd7d624c1158e70a55422996951c21c33eb1b40292e02df6255ad9a1"),
  "baseline/token-protocol.R" = list(
    bytes = 3379L, sha256 = "85620345d0756a8a50f6fe08a5efb1c1355ff67202a4e4b9b7da58d35036c921"),
  "baseline/token-trial.ps1" = list(
    bytes = 4454L, sha256 = "aae0e9b54331f8dc3a94bc2e8fe49d734bbc74345dbfb69ac803e4d28142e2c6"),
  "controls/test-held-faults.ps1" = list(
    bytes = 5878L, sha256 = "2f463ba827f9fa22fda0a89c00f77475156026c110322812b0e7c5f2eefddce8"),
  "controls/test-held-native.R" = list(
    bytes = 3683L, sha256 = "8f88c8333f986c2db8a4c349a0147a5263a8f8a6a9232a94cc072c29f902515d"),
  "controls/test-held-protocol.R" = list(
    bytes = 1867L, sha256 = "9c50271cf67d7a21044cb343a3cb576d3f532f04b10eb7965382bd1ac4443fe0"),
  "current-token.cs" = list(
    bytes = 13340L, sha256 = "c8ca069362b0a07a8a16187c9a8d32b60d685a29b0ecf36712d6baf26ebffb88"),
  "forward-inverse.json" = list(
    bytes = 590L, sha256 = "60e6bcb545848de70803bd22067fd80eb77094ad4afd0d6eb95c0a110b23c55a"),
  "held-successor.patch" = list(
    bytes = 9682L, sha256 = "89845f2e3b8626138cdf9676e8aa72fce70d9a4e1b1ba47d07c0278b0819beee"),
  "prepare-source.py" = list(
    bytes = 8930L, sha256 = "93f2c5777e9ddd6703600de71bc7ecc87dfdc8f01f01a8f21968dca00100aba6"),
  "prior-frozen-85814a4b/manifest.json" = list(
    bytes = 3861L, sha256 = "85814a4bdf405285f2adf30e94ad1460fcf9457aa4e3fb3cee736305e3f3787f"),
  "prior-frozen-85814a4b/prepare-source.py" = list(
    bytes = 8289L, sha256 = "ee7ed138a177c818f7ef127cf1952441d5d24ed3e82f3297f07f51462f6205e2"),
  "prior-frozen-85814a4b/source-proof.json" = list(
    bytes = 785L, sha256 = "fea41e99ec6cc3e87c58f8fe7909106fa6cc16dfbe4da220fc46713216c357f0"),
  "prior-frozen-8eedb863/README.md" = list(
    bytes = 6201L, sha256 = "e0d87e8b4a50c702843d78f67dc6d758f31738ef6b002657af859e135aba9f98"),
  "prior-frozen-8eedb863/manifest.json" = list(
    bytes = 4336L, sha256 = "8eedb863c3836075d1f90261c8b05585c9f11c722b2b0b7f689e15edff5fcfab"),
  "prior-frozen-8eedb863/prepare-source.py" = list(
    bytes = 8401L, sha256 = "7292c00384e0416f09c8be6e3c4dbbef221b805161cb9fa2e64391cb2c67bb1e"),
  "prior-frozen-8eedb863/source-proof.json" = list(
    bytes = 827L, sha256 = "582214b7877cebf39118480adbb69bfea3f71255a8aa6ac7feb140c9873f93bf"),
  "source-proof.json" = list(
    bytes = 1225L, sha256 = "5f6cf5d0fb552cba3768881acfb1d12bc0e5550136d5ccab912ea8a91691b1dc"),
  "token-held-protocol.R" = list(
    bytes = 1466L, sha256 = "dc508cbd90c6c8083d6a4421799e87235bb5fc27c1ff42d12fd3955216e89c03"),
  "token-held.ps1" = list(
    bytes = 2070L, sha256 = "f66e7892e1157ab2f422075281a72f65638770d08ea0764afbe5b8b4cb8b7851"),
  "verify-source.py" = list(
    bytes = 5288L, sha256 = "253dc87735cd9c9584348e38e51d1b44cddd8812151a3c55a1ac38dcbefe09d2"),
  "manifest.json" = list(
    bytes = 5132L, sha256 = "a6c677519a18d71505aaa6f8100b15f8554590f3b28cadc256c8f4392e0a6441")
)
held_core$token_assets = held_assets
held_core$token_titles = list(
  "held-protocol" = c(
    "held-token protocol admits only the exact completed utility window",
    "held-token protocol rejects ineffective missing and conflicting proofs"),
  "held-native" = "owned held-disabled token proves the strict native absence oracle")

held_nomination = function() {
  held_core$token_nomination(Sys.getenv("GPTR_EXPERIMENT_OPTIONAL"),
    Sys.getenv("GPTR_EXPERIMENT_PLATFORM"), Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"),
    Sys.getenv("GPTR_EXPECTED_SOURCE"), .Platform$OS.type == "windows")
  stopifnot(identical(Sys.getenv("GPTR_HELD_B"), "true"),
    identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
  root = normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  files = held_core$token_support$optional_select(Sys.getenv("GPTR_OPTIONAL_FILTER"), root)
  expected = c("test-bp-disk-observer.R", "test-windows-security.R",
    "test-proc-windows-backpressure.R", "test-proc-backpressure-sampling.R",
    "test-proc-writer-runtime.R")
  if (length(files) != length(expected) || !setequal(basename(files), expected)) {
    stop("Held fixture nomination requires the exact original joint files")
  }
  root
}

held_verify_packet = function(root) {
  packet = file.path(root, "dev", "ci", "windows-token", "held-packet")
  for (name in names(held_assets)) {
    expected = held_assets[[name]]
    bytes = readBin(file.path(packet, name), "raw", n = expected$bytes + 1L)
    if (length(bytes) != expected$bytes ||
        !identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), expected$sha256)) {
      stop("Held packet identity mismatch")
    }
  }
  old_packet = file.path(root, "dev", "ci", "windows-token", "packet")
  held_old_verify(old_packet)
  ordinary = readBin(file.path(packet, "baseline", "ordinary-helper-proc-writer-runtime.R"),
    "raw", n = 51609L)
  helper = readBin(file.path(packet, "amended", "helper-proc-writer-runtime.R"),
    "raw", n = 51608L)
  stopifnot(length(ordinary) == 51608L, identical(helper, ordinary))
  list(review_manifest_sha256 = held_assets[["manifest.json"]]$sha256,
    files_verified = length(held_assets), original_helper_prefix_bytes = 51608L)
}

held_pure_admission = function(root) {
  output = file.path(root, "optional-evidence", "windows-token-held-b", "pure")
  read = function(name) {
    bytes = readBin(file.path(output, name), "raw", n = 65537L)
    if (!length(bytes) || length(bytes) > 65536L) stop("Held pure witness size is invalid")
    jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE)
  }
  summary = read("integration-summary.json")
  warnings = read("controller-warnings.json")
  cleanup = read("held-protocol-cleanup.json")
  proof = held_verify_packet(root)
  count = function(value, expected) {
    is.numeric(value) && length(value) == 1L && is.finite(value) && value == expected
  }
  if (!isTRUE(summary$passed) || !isTRUE(warnings$passed) ||
      !identical(summary$source_sha, Sys.getenv("GPTR_EXPECTED_SOURCE")) ||
      !identical(summary$review_manifest_sha256, proof$review_manifest_sha256) ||
      !identical(summary$action, "held-protocol") || !count(summary$fault_controls, 12) ||
      !count(summary$protocol_cases, 2) || !count(warnings$warnings_total, 0) ||
      !isTRUE(cleanup$passed) || !isTRUE(cleanup$settled) ||
      !isTRUE(cleanup$root_stopped) || !count(cleanup$remaining_marked_processes, 0) ||
      !identical(cleanup$launch_unknown, FALSE) || !is.null(cleanup$cleanup_error_class)) {
    stop("Held pure admission is incomplete")
  }
  invisible(TRUE)
}

held_child = function(action) {
  root = held_nomination()
  proof = held_verify_packet(root)
  installed = held_core$token_installed_witness(root)
  packet = file.path(root, "dev", "ci", "windows-token", "held-packet")
  scope = new.env(parent = asNamespace("testthat"))
  sys.source(file.path(packet, "token-held-protocol.R"), envir = scope)
  if (identical(action, "held-protocol")) {
    sys.source(file.path(root, "dev", "ci", "windows-token", "held-faults.R"), envir = scope)
    proof$faults = scope$token_held_faults(packet,
      file.path(root, "optional-evidence", "windows-token-held-b", "pure"))
    file = "test-held-protocol.R"
  } else if (identical(action, "held-native")) {
    held_pure_admission(root)
    file = "test-held-native.R"
  } else {
    stop("Invalid held child action")
  }
  rows = held_core$token_support$optional_result_rows(testthat::test_file(
    file.path(packet, "controls", file), env = scope,
    reporter = testthat::LocationReporter$new(file = stderr()),
    package = "gptr", load_package = "none"))
  list(rows = rows, installed = installed, packet = proof)
}

held_gate = held_core$token_raw_gate
held_core$token_raw_gate = function(observation, action, source) {
  result = held_gate(observation, action, source)
  if (identical(action, "held-protocol")) {
    faults = observation$result$packet$faults
    if (!is.list(faults) || !identical(faults$cases, 12L) ||
        !identical(faults$status, 0L) || !identical(faults$settled, TRUE) ||
        !identical(faults$stderr_bytes, 0L) || !identical(faults$utility_timeout_s, 5L) ||
        !is.numeric(faults$elapsed_s) || length(faults$elapsed_s) != 1L ||
        !is.finite(faults$elapsed_s) || faults$elapsed_s < 0 || faults$elapsed_s > 5) {
      stop("Held fault controls are incomplete")
    }
  }
  result
}

held_original_file = function(file) {
  root = held_nomination()
  if (!identical(basename(file), "test-proc-writer-runtime.R")) {
    stop("Held override is restricted to the original writer file")
  }
  held_pure_admission(root)
  held_core$token_installed_witness(root)
  packet = file.path(root, "dev", "ci", "windows-token", "held-packet")
  scope = new.env(parent = asNamespace("gptr"))
  testthat::local_test_directory(dirname(file), package = "gptr")
  testthat::source_test_helpers(dirname(file), env = scope)
  original_run = get("bp_run", envir = scope, inherits = FALSE)
  held = new.env(parent = scope)
  sys.source(file.path(packet, "amended", "helper-proc-writer-runtime.R"), envir = held)
  sys.source(file.path(packet, "token-held-protocol.R"), envir = held)
  held$bp_run = function(case, ...) {
    stopifnot(identical(case, "native-held-token"))
    actual = original_run
    environment(actual) = parent.env(environment())
    actual("native-absence", ...)
  }
  state = new.env(parent = emptyenv())
  state$calls = 0L
  scope$rw_absence_run = function() {
    state$calls = state$calls + 1L
    if (state$calls != 1L) stop("Held fixture was invoked more than once")
    x = held$rw_held_token_run(packet)
    held$token_held_decode(x$phases[startsWith(x$phases, "GPTR_HELD ")])
    x
  }
  rows = held_core$token_support$optional_result_rows(testthat::test_file(file, env = scope,
    load_helpers = FALSE, reporter = testthat::LocationReporter$new(file = stderr()),
    package = "gptr", load_package = "none"))
  if (state$calls != 1L) stop("Original native absence case was not invoked")
  held_core$token_support$optional_controller_write(list(
    source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    fixture_variant = "held-disabled-owned-utility", original_tests_unchanged = TRUE,
    calls = state$calls, ordinary_sampler_retained = TRUE,
    restored_token_denial_proved = FALSE),
    file.path(root, "optional-evidence", "held-original-writer-fixture.json"))
  rows
}

held_main = function(controller, action) {
  root = held_nomination()
  if (!action %in% names(held_core$token_titles)) stop("Invalid held action")
  if (identical(action, "held-native")) held_pure_admission(root)
  output = file.path(root, "optional-evidence", "windows-token-held-b",
    if (identical(action, "held-protocol")) "pure" else "native")
  summary = list(passed = FALSE, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    review_manifest_sha256 = held_assets[["manifest.json"]]$sha256, action = action,
    fixture_variant = "held-disabled-owned-utility", restored_token_denial_proved = FALSE,
    fault_controls = 12L, protocol_cases = 2L, native_cases = 1L,
    per_file_timeout_s = 300L, results = list())
  on.exit({
    controller$summary = summary
  }, add = TRUE)
  summary$results[[action]] = held_core$token_invoke(action, root, output, controller)
  if (controller$total > 0L) stop("Held controller warnings captured")
  summary$passed = TRUE
  invisible(summary)
}

if (sys.nframe() == 0L) {
  local({
    args = commandArgs(TRUE)
    root = held_nomination()
    output = file.path(root, "optional-evidence", "windows-token-held-b")
    if (identical(args, "verify-install")) {
      withCallingHandlers({
        stopifnot(dir.create(output, mode = "0700"))
        held_core$token_support$optional_controller_write(list(
          installed = held_core$token_installed_witness(root), packet = held_verify_packet(root)),
          file.path(output, "installed-identity.json"))
      }, warning = function(w) stop(w))
    } else if (length(args) == 1L && args %in% c("pure", "native")) {
      action = if (identical(args, "pure")) "held-protocol" else "held-native"
      output = file.path(output, args)
      stopifnot(dir.create(output, mode = "0700"))
      held_core$token_support$optional_controller_run(
        main = function(controller) held_main(controller, action), output = output)
    } else {
      stop("Choose the exact held controller action")
    }
  })
}
