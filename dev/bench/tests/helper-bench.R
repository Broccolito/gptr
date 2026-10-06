# Helpers of the development tests of dev/bench (plan P24). From the repository root:
#   Rscript --vanilla -e 'testthat::test_dir("dev/bench/tests")'
# testthat sources this file with the working directory at dev/bench/tests.
source(file.path("..", "common.R"), local = TRUE)

# Sources a runner into the calling test file without running it (a runner runs only as the
# Rscript entry point), from the repository root as its Rscript runs.
bench_source_only = function(...) {
  env = parent.frame()
  withr::with_dir(file.path("..", "..", ".."),
                  sys.source(file.path("dev", "bench", ...), envir = env))
}

# Loads the gptr source tree once per test run (export_all, so the internals are visible).
bench_test_load_gptr = function() {
  testthat::skip_if_not_installed("pkgload")
  if (!isNamespaceLoaded("gptr")) {
    pkgload::load_all(file.path("..", "..", ".."), quiet = TRUE, export_all = TRUE,
                      helpers = FALSE, attach_testthat = FALSE)
  }
}
