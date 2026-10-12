# Pure route controls: no PowerShell, token, child, optional namespace or compiler launch.
held_controller_file = file.path("dev", "ci", "windows-token", "held-controller.R")
if (!file.exists(held_controller_file)) held_controller_file = "held-controller.R"
source(held_controller_file, local = TRUE)
held_faults_file = file.path(dirname(held_controller_file), "held-faults.R")
source(held_faults_file, local = TRUE)

testthat::test_that("held route keeps the original token packet and selects exact new cases", {
  testthat::expect_identical(held_old_assets[["manifest.json"]]$sha256,
    "c874e9eb49204a990bd3d3a8183c059bf01fc558d58ca6fd30ab9af783ae34aa")
  testthat::expect_identical(length(held_old_assets), 14L)
  testthat::expect_identical(names(held_core$token_titles), c("held-protocol", "held-native"))
  testthat::expect_length(held_core$token_titles[["held-protocol"]], 2L)
  testthat::expect_length(held_core$token_titles[["held-native"]], 1L)
  testthat::expect_identical(held_assets[["baseline/ordinary-helper-proc-writer-runtime.R"]]$bytes,
    51608L)
  testthat::expect_identical(held_assets[["baseline/ordinary-helper-proc-writer-runtime.R"]]$sha256,
    held_old_assets[["baseline/helper-proc-writer-runtime.R"]]$sha256)
})

testthat::test_that("held raw gate requires actual completed twelve-control fault witness", {
  action = "held-protocol"
  faults = list(cases = 12L, status = 0L, elapsed_s = 1, utility_timeout_s = 5L,
    settled = TRUE, stderr_bytes = 0L)
  rows = lapply(held_core$token_titles[[action]], function(title) {
    list(test = title, passed = 1L, failed = 0L, warnings = 0L, skipped = 0L)
  })
  proof = list(review_manifest_sha256 = held_assets[["manifest.json"]]$sha256,
    files_verified = length(held_assets), original_helper_prefix_bytes = 51608L, faults = faults)
  installed = list(source_sha = strrep("a", 40L), comparisons = as.list(stats::setNames(
    rep(TRUE, 4L), c("proc_spawn", "proc_writer_acl", "proc_cleanup_record", "kill_all"))))
  observed = list(result = list(rows = rows, installed = installed, packet = proof),
    outside_test_warning_total = 0L, outside_test_warning_classes = character(),
    known_build_advisories = 0L)
  testthat::expect_true(held_core$token_raw_gate(observed, action, installed$source_sha)$passed)
  for (field in names(faults)) {
    bad = observed
    bad$result$packet$faults[[field]] = NULL
    testthat::expect_error(held_core$token_raw_gate(bad, action, installed$source_sha))
  }
  for (change in list(list(cases = 11L), list(status = 1L), list(elapsed_s = 5.001),
      list(elapsed_s = NA_real_), list(elapsed_s = -1), list(settled = FALSE),
      list(stderr_bytes = 1L), list(utility_timeout_s = 6L))) {
    bad = observed
    for (field in names(change)) bad$result$packet$faults[[field]] = change[[field]]
    testthat::expect_error(held_core$token_raw_gate(bad, action, installed$source_sha),
      "Held fault controls")
  }
  bad = observed
  bad$result$rows[[1L]]$skipped = 1L
  testthat::expect_error(held_core$token_raw_gate(bad, action, installed$source_sha), "skipped")
  bad = observed
  bad$outside_test_warning_total = 1L
  testthat::expect_error(held_core$token_raw_gate(bad, action, installed$source_sha), "warnings")
})

testthat::test_that("held runner transfers private child selection to the current sampler", {
  walk = function(expression) {
    if (missing(expression)) return(list())
    found = list()
    if (is.call(expression) && length(expression) == 3L &&
        identical(expression[[1L]], as.name("=")) &&
        identical(expression[[2L]], quote(held$bp_run))) found = list(expression)
    if (is.call(expression) || is.expression(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  expressions = walk(body(held_original_file))
  testthat::expect_length(expressions, 1L)
  scope = new.env(parent = baseenv())
  scope$held = new.env(parent = baseenv())
  original_scope = new.env(parent = baseenv())
  original_scope$bp_child_case = "original"
  scope$original_run = function(case, ...) list(case = case, selected = bp_child_case)
  environment(scope$original_run) = original_scope
  eval(expressions[[1L]], envir = scope)
  wrapper = scope$held$bp_run
  selected_scope = new.env(parent = environment(wrapper))
  selected_scope$bp_child_case = "held-only"
  environment(wrapper) = selected_scope
  result = wrapper("native-held-token")
  testthat::expect_identical(result, list(case = "native-absence", selected = "held-only"))
  testthat::expect_identical(scope$original_run("original"),
    list(case = "original", selected = "original"))
  testthat::expect_identical(original_scope$bp_child_case, "original")
  testthat::expect_error(wrapper("other"))
})

testthat::test_that(
  "held fault launch capture preserves original failure across cleanup uncertainty", {
  owned = tempfile("held-route-controls-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  stopifnot(dir.create(owned, mode = "0700"))
  withr::defer(unlink(owned, recursive = TRUE))
  errors = list(simpleError("PUBLIC-PRIMARY"),
    structure(list(message = "PUBLIC-INTERRUPT", call = NULL), class = c("interrupt", "condition")))
  for (original in errors) {
    for (cleanup in list(TRUE, FALSE, NA, simpleError("PUBLIC-CLEANUP"), errors[[2L]])) {
      state = new.env(parent = emptyenv())
      state$captured = FALSE
      state$kills = 0L
      process = list(is_alive = function() FALSE)
      ns = new.env(parent = emptyenv())
      ns$proc_spawn = function(..., .on_spawn) {
        .on_spawn(process)
        state$captured = TRUE
        stop(original)
      }
      ns$kill_all = function(p, grace) {
        stopifnot(identical(p, process), identical(grace, 0))
        state$kills = state$kills + 1L
        if (inherits(cleanup, "condition")) stop(cleanup)
        cleanup
      }
      ns$reactor_now = function() 0
      scope = new.env(parent = environment(token_held_faults))
      scope$.Platform = list(OS.type = "windows")
      scope$asNamespace = function(name) {
        stopifnot(identical(name, "gptr"))
        ns
      }
      actual = token_held_faults
      environment(actual) = scope
      before = Sys.getenv()
      seen = tryCatch(actual(owned, owned), error = identity, interrupt = identity)
      testthat::expect_identical(seen, original)
      testthat::expect_true(state$captured)
      testthat::expect_identical(state$kills, 1L)
      testthat::expect_identical(Sys.getenv(), before)
    }
  }
})
