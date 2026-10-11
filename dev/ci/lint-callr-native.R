# Resolve the same real helper bindings as the existing scoped integration lint gate.
pkgload::load_all(quiet = TRUE)
source("dev/ci/optional-integrations.R", local = TRUE)
paths = c("dev/ci/callr-native.R", "tests/testthat/helper-callr-parent-environment.R",
  "tests/testthat/test-callr-parent-environment.R", "tests/testthat/test-callr-startup-admission.R",
  "tests/testthat/helper-proc-backpressure.R", "dev/ci/lint-callr-native.R")
results = lapply(paths, lintr::lint)
names(results) = paths
print(results)
stopifnot(all(lengths(results) == 0L))
