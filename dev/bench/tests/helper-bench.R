# Helpers of the development tests of dev/bench (plan P24). From the repository root:
#   Rscript --vanilla -e 'testthat::test_dir("dev/bench/tests")'
# testthat sources this file with the working directory at dev/bench/tests.
source(file.path("..", "common.R"), local = TRUE)

# Loads the gptr source tree once per test run (export_all, so the internals are visible).
bench_test_load_gptr = function() {
  testthat::skip_if_not_installed("pkgload")
  if (!isNamespaceLoaded("gptr")) {
    pkgload::load_all(file.path("..", "..", ".."), quiet = TRUE, export_all = TRUE,
                      helpers = FALSE, attach_testthat = FALSE)
  }
}
