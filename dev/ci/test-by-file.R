# Run the offline test suite one file at a time and say where it is (CI Task CI-2; on demand
# since CI-19, .github/workflows/windows-by-file.yaml).
# R CMD check prints the test output only after the tests end, so a hosted run that hangs in
# "checking tests" names no file. This runs each file in its own R child, limited to `minutes`
# (default 15), and prints, before each file, its name and the time into the run, then each
# test's start and end and every expectation (testthat's LocationReporter) to stderr, which R
# does not buffer, and after each file its counts and failure messages, or TIMEOUT: a test that
# never returns is the last "Start test:" without an "End test:"; the next file still runs.
# Exits 1 when a test failed, errored or timed out.
# The user's home and R_user_dir() folders are redirected before the package loads (its load
# sweeps the process-marker folder); tests/testthat/setup.R isolates each file's tests as usual.
# NOT_CRAN is "true", as under devtools::test() and the R CMD check jobs, so the tests that start
# processes run.
# Usage, from the repository root:
#   Rscript --vanilla dev/ci/test-by-file.R [<file name regex> [<minutes per file>]]
status = (function() {
  args = commandArgs(trailingOnly = TRUE)
  pattern = if (length(args)) args[[1L]] else "."
  minutes = if (length(args) > 1L) as.numeric(args[[2L]]) else 15
  files = sort(list.files("tests/testthat", pattern = "^test-.*[.][Rr]$", full.names = TRUE))
  files = files[grepl(pattern, basename(files))]
  if (!length(files)) stop("No test file matches ", pattern)
  root = tempfile("gptr-by-file-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  dirs = stats::setNames(file.path(root, c("home", "config", "cache", "data", "project")),
                         c("home", "config", "cache", "data", "project"))
  for (d in dirs) dir.create(d)
  withr::local_envvar(
    HOME = dirs[["home"]], USERPROFILE = dirs[["home"]], R_USER_CONFIG_DIR = dirs[["config"]],
    R_USER_CACHE_DIR = dirs[["cache"]], R_USER_DATA_DIR = dirs[["data"]],
    APPDATA = dirs[["config"]], LOCALAPPDATA = dirs[["cache"]],
    XDG_CONFIG_HOME = dirs[["config"]], XDG_CACHE_HOME = dirs[["cache"]],
    XDG_DATA_HOME = dirs[["data"]], GPTR_PROJECT_ROOT = dirs[["project"]],
    GPTR_LIVE_TESTS = "false", NOT_CRAN = "true"
  )
  say = function(...) cat(..., "\n", sep = "", file = stderr())
  now = function() proc.time()[["elapsed"]]
  run_file = function(f) {
    pkgload::load_all(".", helpers = FALSE, quiet = TRUE)
    res = testthat::test_file(f, reporter = testthat::LocationReporter$new(file = stderr()),
                              package = "gptr", load_package = "none")
    df = as.data.frame(res)
    msgs = character()
    for (test in res) {
      for (e in test$results) {
        if (inherits(e, c("expectation_failure", "expectation_error"))) {
          msgs = c(msgs, paste0(test$test, ": ", conditionMessage(e)))
        }
      }
    }
    list(failed = sum(df$failed) + sum(df$error), skipped = sum(df$skipped),
         passed = sum(df$passed), msgs = msgs)
  }
  start = now()
  bad = character()
  for (f in files) {
    t0 = now()
    say(sprintf("==> %s (%.0f s into the run)", basename(f), t0 - start))
    res = tryCatch(callr::r(run_file, list(f), stdout = "", stderr = "", timeout = 60 * minutes),
                   error = function(e) e)
    if (inherits(res, "error")) {
      what = if (inherits(res, "callr_timeout_error")) "TIMEOUT" else conditionMessage(res)
      say(sprintf("<== %s stopped after %.1f s: %s", basename(f), now() - t0, what))
      bad = c(bad, basename(f))
      next
    }
    say(sprintf("<== %s in %.1f s: %d failed, %d skipped, %d passed", basename(f), now() - t0,
                res$failed, res$skipped, res$passed))
    for (m in res$msgs) say("    ", m)
    if (res$failed > 0) bad = c(bad, basename(f))
  }
  say(sprintf("Done in %.0f s; files with failures: %s", now() - start,
              if (length(bad)) paste(bad, collapse = ", ") else "none"))
  if (length(bad)) 1L else 0L
})()
quit(save = "no", status = status)
