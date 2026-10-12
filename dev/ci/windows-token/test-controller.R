# Pure controller controls. No compiler, native utility or process is launched.
token_controller_file = file.path("dev", "ci", "windows-token", "controller.R")
if (!file.exists(token_controller_file)) token_controller_file = "controller.R"
source(token_controller_file, local = TRUE)

token_row = function(test, passed = 1L, failed = 0L, warnings = 0L, skipped = 0L) {
  list(test = test, passed = passed, failed = failed, warnings = warnings, skipped = skipped)
}

token_titles = get("token_titles", inherits = FALSE)
token_assets = get("token_assets", inherits = FALSE)

token_observation = function(action, source = strrep("a", 40L)) {
  list(result = list(rows = lapply(token_titles[[action]], token_row),
    installed = list(source_sha = source,
      comparisons = as.list(stats::setNames(rep(TRUE, 4L),
        c("proc_spawn", "proc_writer_acl", "proc_cleanup_record", "kill_all")))),
    packet = list(review_manifest_sha256 = token_assets[["manifest.json"]]$sha256,
      files_verified = length(token_assets), original_helper_prefix_bytes = 51608L)),
    outside_test_warning_total = 0L, outside_test_warning_classes = character(),
    known_build_advisories = 0L)
}

testthat::test_that("token dispatch requires Windows optional nofollow and exact source", {
  args = list(optional = "true", platform = "windows", nofollow = "true",
    source = strrep("a", 40L), windows = TRUE)
  testthat::expect_true(do.call(token_nomination, args))
  alternatives = list(optional = c("false", ""), platform = c("all", "linux"),
    nofollow = c("false", ""), source = c("", strrep("A", 40L), strrep("a", 39L)),
    windows = FALSE)
  for (field in names(alternatives)) {
    for (value in alternatives[[field]]) {
      bad = args
      bad[[field]] = value
      testthat::expect_error(do.call(token_nomination, bad), "Invalid token experiment")
    }
  }
})

testthat::test_that("token packet admission bounds every asset and preserves the helper prefix", {
  state = new.env(parent = emptyenv())
  state$requests = list()
  read = function(path, n) {
    name = sub("^packet/", "", path)
    state$name = name
    state$requests[[name]] = n
    raw(token_assets[[name]]$bytes)
  }
  hash = function(bytes) token_assets[[state$name]]$sha256
  proof = token_verify_packet("packet", read = read, hash = hash)
  testthat::expect_identical(proof$original_helper_prefix_bytes, 51608L)
  testthat::expect_identical(names(state$requests), names(token_assets))
  testthat::expect_identical(state$requests,
    lapply(token_assets, function(spec) spec$bytes + 1L))
  testthat::expect_error(token_verify_packet("packet", read = function(path, n) raw(n),
    hash = hash), "identity mismatch")
  testthat::expect_error(token_verify_packet("packet", read = read,
    hash = function(bytes) strrep("0", 64L)), "identity mismatch")
  bad_read = function(path, n) {
    bytes = read(path, n)
    if (identical(state$name, "amended/helper-proc-writer-runtime.R")) bytes[[1L]] = as.raw(1L)
    bytes
  }
  testthat::expect_error(token_verify_packet("packet", read = bad_read, hash = hash),
    "prefix changed")
})

testthat::test_that("token raw gates require all unique positive pure and native cases", {
  for (action in names(token_titles)) {
    original = token_observation(action)
    testthat::expect_true(token_raw_gate(original, action, strrep("a", 40L))$passed)
    for (i in seq_along(original$result$rows)) {
      bad = original
      bad$result$rows = bad$result$rows[-i]
      testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "Missing")
      bad = original
      bad$result$rows = c(bad$result$rows, bad$result$rows[i])
      testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "Missing")
      for (field in c("passed", "failed", "warnings", "skipped")) {
        bad = original
        bad$result$rows[[i]][[field]] = if (field == "passed") 0L else 1L
        testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)),
          "Failed warned skipped or empty")
        bad$result$rows[[i]][[field]] = NA_integer_
        testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "Invalid")
      }
      bad = original
      bad$result$rows[[i]]$test = "Unknown token case"
      testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "Unknown")
    }
    if (length(original$result$rows) > 1L) {
      bad = original
      bad$result$rows[[2L]]$test = bad$result$rows[[1L]]$test
      testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "duplicated")
      bad = original
      bad$result$rows = rev(bad$result$rows)
      testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "reordered")
    }
    testthat::expect_error(token_raw_gate(NULL, action, strrep("a", 40L)), "shape")
    bad = original
    bad$result$rows = NULL
    testthat::expect_error(token_raw_gate(bad, action, strrep("a", 40L)), "shape")
  }
})

testthat::test_that("token raw gates refuse outside warnings and incomplete installed witnesses", {
  original = token_observation("token-protocol")
  for (field in c("outside_test_warning_total", "known_build_advisories")) {
    bad = original
    bad[[field]] = 1L
    testthat::expect_error(token_raw_gate(bad, "token-protocol", strrep("a", 40L)), "warnings")
  }
  bad = original
  bad$outside_test_warning_classes = "simpleWarning/warning/condition"
  testthat::expect_error(token_raw_gate(bad, "token-protocol", strrep("a", 40L)), "warnings")
  for (field in c("source_sha", "comparisons")) {
    bad = original
    bad$result$installed[[field]] = NULL
    testthat::expect_error(token_raw_gate(bad, "token-protocol", strrep("a", 40L)), "witness")
  }
  for (field in c("review_manifest_sha256", "files_verified", "original_helper_prefix_bytes")) {
    bad = original
    bad$result$packet[[field]] = NULL
    testthat::expect_error(token_raw_gate(bad, "token-protocol", strrep("a", 40L)), "witness")
  }
  bad = token_observation("token-native")
  bad$result$rows[[1L]]$failed = 1L
  testthat::expect_error(token_raw_gate(bad, "token-native", strrep("a", 40L)), "Failed")
})

testthat::test_that("token installed function identity preserves formals and executable bodies", {
  actual = function(x = 1L) x + 2L
  parsed = function(text) parse(text = text, keep.source = FALSE)[[1L]]
  testthat::expect_true(token_same_function(actual, parsed("function(x = 1L) x + 2L")))
  testthat::expect_false(token_same_function(actual, parsed("function(x = 2L) x + 2L")))
  testthat::expect_false(token_same_function(actual, parsed("function(x = 1L) x + 3L")))
  testthat::expect_false(token_same_function(actual, parsed("1L")))
  testthat::expect_false(token_same_function(NULL, parsed("function(x = 1L) x + 2L")))
})

testthat::test_that("token settlement rejects live unknown failed and marked families", {
  family = list(settled = TRUE, root_stopped = TRUE, remaining_marked_processes = 0L)
  testthat::expect_true(token_settlement_gate(family, NULL, FALSE))
  testthat::expect_false(token_settlement_gate(family, "simpleError", FALSE))
  testthat::expect_false(token_settlement_gate(family, NULL, TRUE))
  for (field in c("settled", "root_stopped", "remaining_marked_processes")) {
    bad = family
    bad[[field]] = NULL
    testthat::expect_false(token_settlement_gate(bad, NULL, FALSE))
    bad[[field]] = NA
    testthat::expect_false(token_settlement_gate(bad, NULL, FALSE))
  }
  bad = family
  bad$remaining_marked_processes = 1L
  testthat::expect_false(token_settlement_gate(bad, NULL, FALSE))
})

testthat::test_that("token child transport uses the existing complete environment without launch", {
  controller = normalizePath(token_controller_file, winslash = "/", mustWork = TRUE)
  root = dirname(dirname(dirname(dirname(controller))))
  before_wd = getwd()
  dir = tempfile("token-controller-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  stopifnot(dir.create(dir, mode = "0700"))
  withr::defer(unlink(dir, recursive = TRUE))
  before = Sys.getenv()
  env = c(GPTR_PUBLIC_CANARY = "PUBLIC-CHILD-ONLY", GPTR_EXPERIMENT_PLATFORM = "windows")
  capture = function(...) list(arguments = list(...))
  for (action in names(token_titles)) {
    owned = file.path(dir, action)
    stopifnot(dir.create(owned, mode = "0700"))
    process = token_support$optional_child_start(action, NULL, root, owned,
      file.path(dir, "stdout"), file.path(dir, "stderr"), env, spawn = capture)
    testthat::expect_identical(process$arguments$env, env)
    testthat::expect_identical(process$arguments$args[[1L]], "--vanilla")
    testthat::expect_false(process$arguments$supervise)
    testthat::expect_identical(process$arguments$wd, root)
    request = readRDS(file.path(owned, "request.rds"))
    testthat::expect_identical(request$action, action)
    testthat::expect_identical(request$libpaths, .libPaths())
    testthat::expect_identical(request$source,
      normalizePath(file.path(root, "dev", "ci", "optional-integrations.R"),
        winslash = "/", mustWork = TRUE))
    testthat::expect_identical(Sys.getenv(), before)
    testthat::expect_identical(getwd(), before_wd)
  }
})


testthat::test_that("token sources resolve both root and nested test-file layouts privately", {
  controller = normalizePath(token_controller_file, winslash = "/", mustWork = TRUE)
  root = dirname(dirname(dirname(dirname(controller))))
  test_file = file.path(dirname(controller), "test-controller.R")
  test_code = as.list(parse(test_file, keep.source = FALSE))
  support_code = as.list(parse(controller, keep.source = FALSE))
  assigned = function(expression, name) {
    is.call(expression) && length(expression) == 3L &&
      identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name(name))
  }
  row_start = which(vapply(test_code, assigned, logical(1), "token_row"))
  title_start = which(vapply(support_code, assigned, logical(1), "token_titles"))
  testthat::expect_length(row_start, 1L)
  testthat::expect_length(title_start, 1L)
  bootstrap = test_code[seq_len(row_start - 1L)]
  support = support_code[seq.int(2L, title_start - 1L)]
  replay = function(code, cwd) {
    state = new.env(parent = emptyenv())
    scope = new.env(parent = baseenv())
    scope$file.exists = function(path) file.exists(file.path(cwd, path))
    record = function(file) {
      path = file.path(cwd, file)
      if (!file.exists(path)) stop("Path replay is not readable")
      state$path = normalizePath(path, winslash = "/", mustWork = TRUE)
    }
    scope$source = function(file, local) {
      stopifnot(identical(local, TRUE))
      record(file)
    }
    scope$sys.source = function(file, envir) {
      stopifnot(is.environment(envir), identical(parent.env(envir), baseenv()))
      record(file)
    }
    for (expression in code) eval(expression, envir = scope)
    state$path
  }
  before = getwd()
  for (cwd in c(root, dirname(controller))) {
    testthat::expect_identical(replay(bootstrap, cwd), controller)
    testthat::expect_identical(replay(support, cwd),
      normalizePath(file.path(root, "dev", "ci", "optional-integrations.R"),
        winslash = "/", mustWork = TRUE))
  }
  missing = tempfile("token-missing-layout-")
  testthat::expect_error(replay(bootstrap, missing), "not readable")
  testthat::expect_error(replay(support, missing), "not readable")
  testthat::expect_identical(getwd(), before)
})


testthat::test_that("token decoder preserves exact A-B-A in a base-only child environment", {
  root = dirname(dirname(dirname(dirname(normalizePath(token_controller_file,
    winslash = "/", mustWork = TRUE)))))
  path = file.path(root, "dev", "ci", "windows-token", "packet", "token-protocol.R")
  scope = new.env(parent = baseenv())
  sys.source(path, envir = scope)
  testthat::expect_false(exists("tail", envir = scope, inherits = TRUE))
  keys = c("BACKUP", "RESTORE", "CHANGE_NOTIFY", "FILE_LOOKUP", "PARENT_LOOKUP",
    "PROBE", "TOKEN_EXACT", "ACL_EXACT")
  lines = unlist(lapply(c("A1", "B", "A2"), function(phase) {
    values = c(rep(if (phase == "B") 1L else 2L, 6L), 1L, 1L)
    paste("GPTR_TOKEN", phase, keys, values)
  }), use.names = FALSE)
  lines = c(lines, "GPTR_TOKEN END TOKEN_RESTORED 1", "GPTR_TOKEN END HANDLE_CLOSED 1")
  original = serialize(lines, NULL)
  diagnostic = scope$token_trial_decode(lines)
  testthat::expect_identical(dim(diagnostic$records), c(3L, 8L))
  testthat::expect_identical(dimnames(diagnostic$records), list(c("A1", "B", "A2"), keys))
  testthat::expect_true(diagnostic$group_contribution)
  testthat::expect_false(diagnostic$individual_privilege_identified)
  testthat::expect_false(diagnostic$feature_accepted)
  testthat::expect_identical(serialize(lines, NULL), original)
  for (i in c(25L, 26L)) {
    bad = lines
    bad[[i]] = sub(" 1$", " 2", bad[[i]])
    testthat::expect_error(scope$token_trial_decode(bad), "Invalid owned-token diagnostic")
  }
  testthat::expect_error(scope$token_trial_decode(lines[-26L]), "Invalid owned-token diagnostic")
  testthat::expect_error(scope$token_trial_decode(c(lines, lines[[26L]])),
    "Invalid owned-token diagnostic")
})
