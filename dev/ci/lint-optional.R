# Keep the complete scoped lint program in a file: Windows Rscript -e quoting differs.
pkgload::load_all(quiet = TRUE)
paths = c(
  "R/artifact-app.R", "R/gptr-config.R", "tests/testthat/setup.R",
  "tests/testthat/test-tool-search.R", "tests/testthat/test-artifact-browser-cleanup.R",
  "tests/testthat/test-config-content-cache.R", "tests/testthat/test-gptr-config.R",
  "tests/testthat/helper-windows-security.R", "tests/testthat/test-windows-security.R",
  "dev/ci/optional-integrations.R", "dev/ci/test-optional-integrations.R",
  "dev/ci/lint-optional.R")
stopifnot(all(file.exists(paths)))
results = lapply(paths, lintr::lint)
names(results) = paths
print(results)
stopifnot(all(lengths(results) == 0L))
