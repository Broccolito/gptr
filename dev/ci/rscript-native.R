# Serial native launch parity: installed and source packages, offline fixtures only.
rscript_native_run = function() {
  args = commandArgs(TRUE)
  stopifnot(length(args) == 2L, args[[1L]] %in% c("source", "installed"))
  mode = args[[1L]]
  output = args[[2L]]
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  home = tempfile("gptr-rscript-native-")
  dir.create(home, mode = "0700")
  on.exit(unlink(home, recursive = TRUE), add = TRUE)
  dirs = stats::setNames(file.path(home, c("home", "config", "cache", "data", "project")),
                         c("home", "config", "cache", "data", "project"))
  for (dir in dirs) dir.create(dir, mode = "0700")
  withr::local_envvar(HOME = dirs[["home"]], USERPROFILE = dirs[["home"]],
    R_USER_CONFIG_DIR = dirs[["config"]], R_USER_CACHE_DIR = dirs[["cache"]],
    R_USER_DATA_DIR = dirs[["data"]], APPDATA = dirs[["config"]], LOCALAPPDATA = dirs[["cache"]],
    XDG_CONFIG_HOME = dirs[["config"]], XDG_CACHE_HOME = dirs[["cache"]],
    XDG_DATA_HOME = dirs[["data"]], GPTR_PROJECT_ROOT = dirs[["project"]],
    GPTR_LIVE_TESTS = "false", GPTR_REPLAY = "replay", NOT_CRAN = "true")
  packages = c("processx", "ps", "shiny", "httpuv", "later", "chromote", "openssl", "lintr",
                "reticulate", "knitr")
  stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly = TRUE)))
  if (mode == "source") pkgload::load_all(quiet = TRUE, helpers = FALSE)
  else loadNamespace("gptr")
  ns = asNamespace("gptr")
  internal = function(name) get(name, ns, inherits = FALSE)
  stopifnot(is.null(internal("artifact_chromote_missing")()))
  started = proc.time()[["elapsed"]]
  testthat::set_max_fails(Inf)
  pattern = paste0("^(proc-rscript|proc-rscript-native|subagent-worker|",
    "subagent-worker-rscript|artifact-app|artifact-registry|artifact-browser-cleanup|",
    "proc-spawn|proc-supervise|",
    "secrets-e2e|arch-layers|bridge-python-native)$")
  result = testthat::test_dir("tests/testthat", filter = pattern, package = "gptr",
    load_package = if (mode == "source") "none" else "installed", reporter = "summary",
    stop_on_failure = FALSE, stop_on_warning = FALSE)
  rows = as.data.frame(result)
  selected = rows[, setdiff(names(rows), "result"), drop = FALSE]
  jsonlite::write_json(selected, file.path(output, "rows.json"), auto_unbox = TRUE, pretty = TRUE)
  guards = if (.Platform$OS.type == "windows") c(
    "the access token is 128 random bits from openssl or /dev/urandom",
    "a worker exits within 10 s when its parent is killed (IC-60)",
    "a parent killed with SIGTERM leaves children that the next load's sweep removes") else
    "a Windows worker exits within 10 s after its acknowledged parent dies (IC-60)"
  python_guards = if (.Platform$OS.type == "windows") character() else c(
    "native Windows Python startup refuses an empty known setup entry before initialization",
    "native Windows Python startup refuses an empty case alias before initialization",
    "native Windows initialized Python preserves an untouched empty setup entry")
  python_skip = basename(rows$file) == "test-bridge-python-native.R" &
    rows$test %in% python_guards
  bad_skips = rows$skipped & !(rows$test %in% guards | python_skip)
  expected_files = paste0(c("proc-rscript", "proc-rscript-native", "subagent-worker",
    "subagent-worker-rscript", "artifact-app", "artifact-registry", "proc-spawn", "proc-supervise"),
    ".R")
  expected_files = c(expected_files, "artifact-browser-cleanup.R", "secrets-e2e.R", "arch-layers.R")
  expected_files = c(expected_files, "bridge-python-native.R")
  file_names = sub("^test-", "", basename(rows$file))
  positive = !rows$skipped & rows$passed > 0L
  source_titles = function(expr) {
    if (is.call(expr) && identical(expr[[1L]], as.name("test_that")) &&
        is.character(expr[[2L]])) return(expr[[2L]])
    if (!(is.call(expr) || is.expression(expr) || is.pairlist(expr))) return(character())
    out = character()
    for (i in seq_along(expr)) {
      if (is.name(expr[[i]]) && !nzchar(as.character(expr[[i]]))) next
      out = c(out, source_titles(expr[[i]]))
    }
    out
  }
  expected = unlist(lapply(expected_files, function(file) {
    path = file.path("tests", "testthat", paste0("test-", file))
    titles = source_titles(parse(path, keep.source = FALSE))
    if (file == "proc-rscript-native.R") {
      titles = unlist(lapply(c("worker", "artifact"), function(profile) {
        paste("native Rscript", profile, c("success", "error", "cancel"),
              "preserves exact caller state")
      }))
    }
    paste(file, titles, sep = "::")
  }), use.names = FALSE)
  observed = paste(file_names, rows$test, sep = "::")
  complete = setequal(expected, observed) && !anyDuplicated(expected) &&
    !anyDuplicated(observed) && all(positive | rows$skipped)
  summary = list(context = mode, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
    os = unname(Sys.info()[["sysname"]]), r = R.version.string,
    elapsed = proc.time()[["elapsed"]] - started, cases = nrow(rows),
    passed = sum(rows$passed), failed = sum(rows$failed) + sum(rows$error),
    warnings = sum(rows$warning), platform_guards = sum(rows$skipped),
    unexpected_skips = sum(bad_skips), complete = complete,
    dependencies = vapply(packages, function(pkg) as.character(utils::packageVersion(pkg)), ""))
  jsonlite::write_json(summary, file.path(output, "summary.json"), auto_unbox = TRUE, pretty = TRUE)
  stopifnot(complete, summary$failed == 0L, summary$warnings == 0L,
            summary$unexpected_skips == 0L)
  list(summary = summary, path = file.path(output, "summary.json"))
}

# This handler surrounds the whole invocation, including its on.exit cleanup and restoration.
(function() {
  observed = new.env(parent = emptyenv())
  observed$warnings = 0L
  withCallingHandlers({
    result = rscript_native_run()
    result$summary$outer_warnings = observed$warnings
    jsonlite::write_json(result$summary, result$path, auto_unbox = TRUE, pretty = TRUE)
    stopifnot(observed$warnings == 0L)
    invisible(NULL)
  }, warning = function(w) {
    observed$warnings = observed$warnings + 1L
  })
})()
