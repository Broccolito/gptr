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

testthat::test_that("held original helper loading uses a scoped testthat path context", {
  setup = Filter(function(expression) {
    is.call(expression) && (identical(expression[[1L]], quote(testthat::local_test_directory)) ||
      identical(expression[[1L]], quote(testthat::source_test_helpers)))
  }, as.list(body(held_original_file))[-1L])
  testthat::expect_length(setup, 2L)
  load = function(file, scope) NULL
  body(load) = as.call(c(list(quote(`{`)), setup, list(quote(invisible(scope)))))

  owned = tempfile("held-helper-context-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  stopifnot(dir.create(owned, mode = "0700"))
  withr::defer(unlink(owned, recursive = TRUE))
  helpers = file.path(owned, "helpers")
  fixtures = file.path(helpers, "fixtures", "mcp")
  stopifnot(dir.create(fixtures, recursive = TRUE, mode = "0700"))
  writeLines(c(
    "resolved = normalizePath(testthat::test_path('fixtures', 'mcp'), winslash = '/',",
    "  mustWork = TRUE)",
    "testing = testthat::is_testing()",
    "package = testthat::testing_package()",
    "if (identical(mode, 'error')) stop(original)",
    "if (identical(mode, 'interrupt')) stop(original)",
    "if (identical(mode, 'warning')) warning('PUBLIC-HELPER-WARNING')"),
    file.path(helpers, "helper-context.R"))
  file = file.path(helpers, "test-proc-writer-runtime.R")
  keys = c("TESTTHAT", "TESTTHAT_PKG", "R_TESTS", "TESTTHAT_WD")
  withr::local_envvar(stats::setNames(c("false", "PUBLIC-PARENT", "PUBLIC-TESTS", "PUBLIC-WD"),
    keys))
  withr::local_options(testthat_interactive = FALSE)
  withr::local_dir(owned)
  state = function() {
    list(cwd = getwd(), env = Sys.getenv(keys, unset = NA_character_),
      edition = getOption("testthat.edition"))
  }
  before = state()
  scope = new.env(parent = baseenv())
  scope$mode = "success"
  testthat::expect_no_error(load(file, scope))
  testthat::expect_identical(scope$resolved,
    normalizePath(fixtures, winslash = "/", mustWork = TRUE))
  testthat::expect_true(scope$testing)
  testthat::expect_identical(scope$package, "gptr")
  testthat::expect_identical(state(), before)

  original = simpleError("PUBLIC-HELPER-ERROR")
  scope$mode = "error"
  scope$original = original
  seen = tryCatch(load(file, scope), error = function(error) error)
  testthat::expect_s3_class(seen, "rlang_error")
  testthat::expect_identical(seen$parent, original)
  testthat::expect_identical(state(), before)
  original = structure(list(message = "PUBLIC-HELPER-INTERRUPT", call = NULL),
    class = c("interrupt", "condition"))
  scope$mode = "interrupt"
  scope$original = original
  seen = tryCatch(load(file, scope), interrupt = function(error) error)
  testthat::expect_identical(seen, original)
  testthat::expect_identical(state(), before)
  scope$mode = "warning"
  testthat::expect_warning(load(file, scope), "PUBLIC-HELPER-WARNING")
  testthat::expect_identical(state(), before)
})

testthat::test_that("held postcondition diagnostics preserve original values and failures", {
  helper = new.env(parent = environment())
  sys.source(file.path(dirname(held_controller_file), "held-packet", "amended",
    "helper-proc-writer-runtime.R"), envir = helper)
  rw_absence_postcondition = get("rw_absence_postcondition", envir = helper, inherits = FALSE)
  observed = new.env(parent = emptyenv())
  observed$labels = character()
  phase = function(text) observed$labels = c(observed$labels, text)
  keys = c("owner-marker", "existing-file", "denied-file", "missing-target", "dangling-entry",
    "existing-directory", "fresh-entries", "remove-owner", "remove-existing-file",
    "remove-denied-file", "remove-utilities", "remove-fresh-directory",
    "remove-existing-directory")
  for (key in keys) {
    testthat::expect_true(rw_absence_postcondition(key, TRUE, phase))
    testthat::expect_identical(utils::tail(observed$labels, 1L),
      paste0("absence-post-", key, "-1"))
  }
  for (value in list(FALSE, NA, c(TRUE, FALSE))) {
    testthat::expect_identical(rw_absence_postcondition("owner-marker", value, phase), value)
    testthat::expect_identical(utils::tail(observed$labels, 1L), "absence-post-owner-marker-0")
  }
  calls = 0L
  value = rw_absence_postcondition("remove-owner", {
    calls = calls + 1L
    TRUE
  }, phase)
  testthat::expect_true(value)
  testthat::expect_identical(calls, 1L)
  testthat::expect_identical(utils::tail(observed$labels, 1L), "absence-post-remove-owner-1")
  original = simpleError("PRIVATE-POSTCONDITION-CANARY")
  observed$labels = character()
  result = tryCatch(rw_absence_postcondition("owner-marker", stop(original), phase),
    error = function(error) error)
  testthat::expect_identical(result, original)
  testthat::expect_identical(observed$labels, "absence-post-owner-marker-error")
  interrupt = structure(list(message = "PRIVATE-INTERRUPT-CANARY", call = NULL),
    class = c("interrupt", "condition"))
  result = tryCatch(rw_absence_postcondition("existing-file", stop(interrupt), phase),
    interrupt = function(error) error)
  testthat::expect_identical(result, interrupt)
  testthat::expect_identical(utils::tail(observed$labels, 1L),
    "absence-post-existing-file-interrupt")
  for (publication in list(simpleError("PRIVATE-PUBLICATION-CANARY"), interrupt)) {
    failed = function(text) stop(publication)
    result = tryCatch(rw_absence_postcondition("owner-marker", stop(original), failed),
      error = function(error) error)
    testthat::expect_identical(result, original)
    result = tryCatch(rw_absence_postcondition("owner-marker", stop(interrupt), failed),
      interrupt = function(error) error)
    testthat::expect_identical(result, interrupt)
    testthat::expect_true(rw_absence_postcondition("owner-marker", TRUE, failed))
  }
  value = NULL
  testthat::expect_warning({
    value = rw_absence_postcondition("owner-marker", {
      warning("FIXED-SYNTHETIC-POSTCONDITION-WARNING")
      TRUE
    }, phase)
  }, "FIXED-SYNTHETIC-POSTCONDITION-WARNING", fixed = TRUE)
  testthat::expect_true(value)
  calls = 0L
  observed$labels = character()
  for (key in list(NULL, NA_character_, c("owner-marker", "existing-file"),
    "PRIVATE-KEY-CANARY", "owner-marker-1")) {
    testthat::expect_error(rw_absence_postcondition(key, {
      calls = calls + 1L
      TRUE
    }, phase), "Invalid absence postcondition diagnostic", fixed = TRUE)
  }
  testthat::expect_identical(calls, 0L)
  testthat::expect_identical(observed$labels, character())
  testthat::expect_error(stopifnot(rw_absence_postcondition("owner-marker", FALSE, phase),
    rw_absence_postcondition("existing-file", {
      calls = calls + 1L
      TRUE
    }, phase)))
  testthat::expect_identical(calls, 0L)
  testthat::expect_identical(observed$labels, "absence-post-owner-marker-0")
  observed$labels = character()
  observed$effects = character()
  remove = function(key) {
    observed$effects = c(observed$effects, key)
    TRUE
  }
  stopifnot(rw_absence_postcondition("remove-owner", remove("owner"), phase),
    rw_absence_postcondition("remove-denied-file", remove("denied"), phase))
  testthat::expect_identical(observed$effects, c("owner", "denied"))
  testthat::expect_identical(observed$labels,
    c("absence-post-remove-owner-1", "absence-post-remove-denied-file-1"))
})


testthat::test_that("held native postcondition tail and child decoder retain every fixed key", {
  helper = new.env(parent = environment())
  sys.source(file.path(dirname(held_controller_file), "held-packet", "amended",
    "helper-proc-writer-runtime.R"), envir = helper)
  sys.source(file.path(dirname(held_controller_file), "held-packet", "token-held-protocol.R"),
    envir = helper)
  keys = c("owner-marker", "existing-file", "denied-file", "missing-target", "dangling-entry",
    "existing-directory", "fresh-entries", "remove-owner", "remove-existing-file",
    "remove-denied-file", "remove-utilities", "remove-fresh-directory",
    "remove-existing-directory")
  parts = as.list(body(helper$rw_held_token_case))[-1L]
  selected = which(vapply(parts, function(expression) {
    is.call(expression) && identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name("post"))
  }, logical(1)))
  testthat::expect_length(selected, 1L)
  tail = parts[seq.int(selected[[1L]], selected[[1L]] + 2L)]
  testthat::expect_identical(lapply(tail[-1L], function(expression) expression[[1L]]),
    list(quote(stopifnot), quote(stopifnot)))
  walk = function(expression) {
    if (missing(expression)) return(character())
    found = character()
    if (is.call(expression) && identical(expression[[1L]], as.name("post"))) {
      found = expression[[2L]]
    }
    if (is.call(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  testthat::expect_identical(unlist(lapply(tail, walk), use.names = FALSE), keys)
  observed = new.env(parent = emptyenv())
  observed$labels = character()
  observed$effects = character()
  scope = new.env(parent = baseenv())
  scope$rw_absence_postcondition = helper$rw_absence_postcondition
  scope$paths = stats::setNames(c("PUBLIC-FRESH", "PUBLIC-DIRECTORY", "PUBLIC-FILE",
    "PUBLIC-DENIED", "PUBLIC-LINK", "PUBLIC-MISSING", "PUBLIC-SCRIPT", "PUBLIC-RECOVERY",
    "PUBLIC-PARENT-BACKUP", "PUBLIC-FILE-BACKUP", "PUBLIC-ARMED", "PUBLIC-TOKEN-SOURCE",
    "PUBLIC-TOKEN-LIBRARY", "PUBLIC-TOKEN-COMPILE"),
    c("fresh", "directory", "file", "denied", "link", "missing", "script", "recovery",
      "parent_backup", "file_backup", "armed", "token_source", "token_library", "token_compile"))
  scope$root = "."
  observed$removed = character()
  scope$dir.exists = function(path) path %in% scope$paths[c("fresh", "directory")]
  remove_definition = Filter(function(expression) {
    is.call(expression) && identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name("remove_empty"))
  }, parts)
  testthat::expect_length(remove_definition, 1L)
  eval(remove_definition[[1L]], envir = scope)
  scope$owner = file.path(scope$paths[["fresh"]], "owner")
  scope$marker = "GPTR_PROC_0123456789abcdef"
  scope$sentinel = charToRaw("PUBLIC-ABSENCE-SENTINEL")
  scope$phase = function(text) observed$labels = c(observed$labels, text)
  effect = function(key, value) {
    observed$effects = c(observed$effects, key)
    value
  }
  scope$readBin = function(path, what, n) {
    stopifnot(identical(path, scope$owner), identical(what, "raw"), identical(n, 27L))
    effect("owner-marker", charToRaw(scope$marker))
  }
  scope$bytes = function(path) {
    key = if (identical(path, scope$paths[["file"]])) "existing-file" else "denied-file"
    stopifnot(path %in% scope$paths[c("file", "denied")])
    effect(key, scope$sentinel)
  }
  scope$file.exists = function(path) {
    stopifnot(identical(path, scope$paths[["missing"]]))
    effect("missing-target", FALSE)
  }
  scope$list.files = function(path, ...) {
    arguments = list(...)
    stopifnot(identical(sort(names(arguments)), c("all.files", "no..")),
      isTRUE(arguments[["all.files"]]), is.logical(arguments[["no.."]]),
      length(arguments[["no.."]]) == 1L, !is.na(arguments[["no.."]]))
    if (identical(arguments[["no.."]], FALSE)) {
      if (identical(path, scope$root)) {
        return(c(".", "..", basename(setdiff(scope$paths[c("fresh", "directory")],
          observed$removed))))
      }
      stopifnot(path %in% scope$paths[c("fresh", "directory")])
      return(c(".", ".."))
    }
    if (identical(path, scope$root)) return(effect("dangling-entry", character()))
    if (identical(path, scope$paths[["directory"]])) {
      return(effect("existing-directory", character()))
    }
    stopifnot(identical(path, scope$paths[["fresh"]]))
    effect("fresh-entries", c("owner", "denied-file"))
  }
  utilities = scope$paths[c("script", "recovery", "parent_backup", "file_backup", "armed",
    "token_source", "token_library", "token_compile")]
  scope$file.remove = function(path) {
    if (identical(path, scope$owner)) return(effect("remove-owner", TRUE))
    if (identical(path, scope$paths[["file"]])) return(effect("remove-existing-file", TRUE))
    if (identical(path, scope$paths[["denied"]])) return(effect("remove-denied-file", TRUE))
    stopifnot(identical(path, utilities))
    effect("remove-utilities", rep(TRUE, length(utilities)))
  }
  scope$unlink = function(path, recursive, force, expand) {
    stopifnot(identical(recursive, TRUE), identical(force, FALSE), identical(expand, FALSE),
      path %in% scope$paths[c("fresh", "directory")])
    observed$removed = c(observed$removed, path)
    key = if (identical(path, scope$paths[["fresh"]])) {
      "remove-fresh-directory"
    } else {
      "remove-existing-directory"
    }
    effect(key, 0L)
  }
  actual = function() NULL
  body(actual) = as.call(c(list(quote(`{`)), tail, list(quote(invisible(NULL)))))
  environment(actual) = scope
  testthat::expect_no_error(actual())
  testthat::expect_identical(observed$effects, keys)
  testthat::expect_identical(observed$labels, paste0("absence-post-", keys, "-1"))

  parts = as.list(body(helper$rw_held_token_run))[-1L]
  find_assignment = function(name) {
    Filter(function(expression) {
      is.call(expression) && identical(expression[[1L]], as.name("=")) &&
        identical(expression[[2L]], as.name(name))
    }, parts)
  }
  decoders = find_assignment("decoders")
  testthat::expect_length(decoders, 1L)
  serialized = new.env(parent = helper)
  eval(decoders[[1L]], envir = serialized)
  testthat::expect_identical(serialized$decoders, c("rw_absence_control", "rw_absence_stage",
    "rw_absence_status", "rw_absence_observation", "rw_absence_privilege", "token_held_line",
    "token_held_decode", "rw_absence_postcondition"))
  definitions = find_assignment("definitions")
  testthat::expect_length(definitions, 2L)
  eval(definitions[[1L]], envir = serialized)
  testthat::expect_length(serialized$definitions, 8L)
  decoded = new.env(parent = baseenv())
  eval(parse(text = serialized$definitions[["rw_absence_postcondition"]]), envir = decoded)
  testthat::expect_identical(formals(decoded$rw_absence_postcondition),
    formals(helper$rw_absence_postcondition))
  testthat::expect_identical(deparse(body(decoded$rw_absence_postcondition)),
    deparse(body(helper$rw_absence_postcondition)))
})


testthat::test_that("held helper scope supplies the real unqualified test_path before loading", {
  setup = Filter(function(expression) {
    is.call(expression) &&
      ((identical(expression[[1L]], as.name("=")) &&
        identical(expression[[2L]], quote(scope$test_path))) ||
       identical(expression[[1L]], quote(testthat::local_test_directory)) ||
       identical(expression[[1L]], quote(testthat::source_test_helpers)))
  }, as.list(body(held_original_file))[-1L])
  testthat::expect_length(setup, 3L)
  load = function(file, scope) NULL
  body(load) = as.call(c(list(quote(`{`)), setup, list(quote(invisible(scope)))))
  owned = tempfile("held-unqualified-helper-",
    tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  stopifnot(dir.create(owned, mode = "0700"))
  withr::defer(unlink(owned, recursive = TRUE))
  helpers = file.path(owned, "helpers")
  fixtures = file.path(helpers, "fixtures", "bench")
  stopifnot(dir.create(fixtures, recursive = TRUE, mode = "0700"))
  writeLines(c(
    "captured = test_path",
    "resolved = normalizePath(test_path('fixtures', 'bench'), winslash = '/',",
    "  mustWork = TRUE)",
    "if (identical(mode, 'error')) stop(original)",
    "if (identical(mode, 'interrupt')) stop(original)",
    "if (identical(mode, 'warning')) warning('PUBLIC-UNQUALIFIED-HELPER-WARNING')"),
    file.path(helpers, "helper-unqualified.R"))
  file = file.path(helpers, "test-proc-writer-runtime.R")
  snapshot = function() {
    list(env = Sys.getenv(), options = options(), cwd = getwd(), libraries = .libPaths(),
      search = search(), kind = RNGkind(),
      seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
      names = ls(envir = globalenv(), all.names = TRUE))
  }
  before = snapshot()
  scope = new.env(parent = baseenv())
  scope$mode = "success"
  testthat::expect_no_error(load(file, scope))
  testthat::expect_identical(scope$test_path, testthat::test_path)
  testthat::expect_identical(scope$captured, testthat::test_path)
  testthat::expect_identical(scope$resolved,
    normalizePath(fixtures, winslash = "/", mustWork = TRUE))
  testthat::expect_identical(parent.env(scope), baseenv())
  testthat::expect_identical(snapshot(), before)
  scope$mode = "error"
  scope$original = simpleError("PUBLIC-UNQUALIFIED-HELPER-ERROR")
  failed = tryCatch(load(file, scope), error = identity)
  testthat::expect_s3_class(failed, "error")
  testthat::expect_identical(failed$parent, scope$original)
  testthat::expect_identical(snapshot(), before)
  scope$mode = "interrupt"
  scope$original = structure(list(message = "PUBLIC-UNQUALIFIED-HELPER-INTERRUPT"),
    class = c("interrupt", "condition"))
  failed = tryCatch(load(file, scope), interrupt = identity)
  testthat::expect_identical(failed, scope$original)
  testthat::expect_identical(snapshot(), before)
  scope$mode = "warning"
  testthat::expect_warning(load(file, scope), "PUBLIC-UNQUALIFIED-HELPER-WARNING")
  testthat::expect_identical(snapshot(), before)
})


testthat::test_that("held cleanup removes only direct owned proven-empty directories", {
  helper = new.env(parent = baseenv())
  sys.source(file.path(dirname(held_controller_file), "held-packet", "amended",
    "helper-proc-writer-runtime.R"), envir = helper)
  definitions = Filter(function(expression) {
    is.call(expression) && identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name("remove_empty"))
  }, as.list(body(helper$rw_held_token_case))[-1L])
  testthat::expect_length(definitions, 1L)
  root = tempfile("held-empty-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  testthat::expect_true(dir.create(root))
  withr::defer(unlink(root, recursive = TRUE, force = FALSE, expand = FALSE))
  scope = new.env(parent = baseenv())
  scope$root = root
  scope$paths = c(fresh = file.path(root, "fresh"), directory = file.path(root, "directory"))
  eval(definitions[[1L]], envir = scope)
  testthat::expect_true(dir.create(scope$paths[["fresh"]]))
  testthat::expect_true(dir.create(scope$paths[["directory"]]))
  testthat::expect_true(scope$remove_empty(scope$paths[["fresh"]]))
  testthat::expect_false(dir.exists(scope$paths[["fresh"]]))
  testthat::expect_false("fresh" %in% list.files(root, all.files = TRUE, no.. = TRUE))
  testthat::expect_true(scope$remove_empty(scope$paths[["directory"]]))
  testthat::expect_false(dir.exists(scope$paths[["directory"]]))
  testthat::expect_identical(sort(list.files(root, all.files = TRUE, no.. = FALSE)), c(".", ".."))
})


testthat::test_that("held empty cleanup refuses populated missing foreign and uncertain entries", {
  helper = new.env(parent = baseenv())
  sys.source(file.path(dirname(held_controller_file), "held-packet", "amended",
    "helper-proc-writer-runtime.R"), envir = helper)
  definitions = Filter(function(expression) {
    is.call(expression) && identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name("remove_empty"))
  }, as.list(body(helper$rw_held_token_case))[-1L])
  testthat::expect_length(definitions, 1L)
  root = tempfile("held-retain-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  outside = tempfile("held-foreign-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  testthat::expect_true(dir.create(root))
  testthat::expect_true(dir.create(outside))
  withr::defer(unlink(c(root, outside), recursive = TRUE, force = FALSE, expand = FALSE))
  scope = new.env(parent = baseenv())
  scope$root = root
  scope$paths = c(fresh = file.path(root, "fresh"), directory = file.path(root, "directory"))
  eval(definitions[[1L]], envir = scope)
  testthat::expect_true(dir.create(scope$paths[["fresh"]]))
  canary = file.path(scope$paths[["fresh"]], "canary")
  sentinel = charToRaw("PUBLIC-RETAIN-EXACT")
  writeBin(sentinel, canary)
  testthat::expect_false(scope$remove_empty(scope$paths[["fresh"]]))
  testthat::expect_identical(readBin(canary, "raw", n = length(sentinel) + 1L), sentinel)
  testthat::expect_false(scope$remove_empty(scope$paths[["directory"]]))
  testthat::expect_false(scope$remove_empty(outside))
  testthat::expect_true(dir.exists(outside))
  testthat::expect_false(scope$remove_empty(NA_character_))
  testthat::expect_false(scope$remove_empty(character()))
  uncertain = new.env(parent = scope)
  uncertain$list.files = function(path, ...) character()
  actual = scope$remove_empty
  environment(actual) = uncertain
  testthat::expect_false(actual(scope$paths[["fresh"]]))
  testthat::expect_identical(readBin(canary, "raw", n = length(sentinel) + 1L), sentinel)
  testthat::expect_true(dir.create(scope$paths[["directory"]]))
  failed = new.env(parent = scope)
  failed$unlink = function(path, recursive, force, expand) 1L
  actual = scope$remove_empty
  environment(actual) = failed
  testthat::expect_false(actual(scope$paths[["directory"]]))
  testthat::expect_true(dir.exists(scope$paths[["directory"]]))
  failed$unlink = function(path, recursive, force, expand) 0L
  testthat::expect_false(actual(scope$paths[["directory"]]))
  testthat::expect_true(dir.exists(scope$paths[["directory"]]))
})
