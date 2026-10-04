# Run the offline test suite one file at a time and say where it is (CI Task CI-2).
# R CMD check prints the test output only after the tests end, so the hosted Windows run that
# hung in "checking tests" named no file. This prints, before each file, its name and the time
# into the run, then each test's start and end and every expectation (testthat's
# LocationReporter), all to stderr, which R does not buffer, and after each file its counts and
# its failure messages. A test that never returns is the last "Start test:" without an
# "End test:". Exits 1 when a test failed or errored.
# The user's home and R_user_dir() folders are redirected before the package loads (its load
# sweeps the process-marker folder); tests/testthat/setup.R isolates each file's tests as usual.
# NOT_CRAN is "true", as under devtools::test() and the R CMD check jobs, so the tests that start
# processes run.
# Usage, from the repository root: Rscript --vanilla dev/ci/test-by-file.R [<file name regex>]
status = (function() {
  args = commandArgs(trailingOnly = TRUE)
  pattern = if (length(args)) args[[1L]] else "."
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
  pkgload::load_all(".", helpers = FALSE, quiet = TRUE)
  start = now()
  bad = character()
  for (f in files) {
    t0 = now()
    say(sprintf("==> %s (%.0f s into the run)", basename(f), t0 - start))
    res = tryCatch(
      testthat::test_file(f, reporter = testthat::LocationReporter$new(file = stderr()),
                          package = "gptr", load_package = "none"),
      error = function(e) e
    )
    if (inherits(res, "error")) {
      say(sprintf("<== %s stopped after %.1f s: %s", basename(f), now() - t0,
                  conditionMessage(res)))
      bad = c(bad, basename(f))
      next
    }
    df = as.data.frame(res)
    failed = sum(df$failed) + sum(df$error)
    say(sprintf("<== %s in %.1f s: %d failed, %d skipped, %d passed", basename(f), now() - t0,
                failed, sum(df$skipped), sum(df$passed)))
    for (test in res) {
      for (e in test$results) {
        if (inherits(e, c("expectation_failure", "expectation_error"))) {
          say("    ", test$test, ": ", conditionMessage(e))
        }
      }
    }
    if (failed > 0) bad = c(bad, basename(f))
  }
  say(sprintf("Done in %.0f s; files with failures: %s", now() - start,
              if (length(bad)) paste(bad, collapse = ", ") else "none"))
  if (length(bad)) 1L else 0L
})()
quit(save = "no", status = status)
