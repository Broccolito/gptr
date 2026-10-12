# Resolve the same real helper bindings as the existing scoped integration lint gate.
pkgload::load_all(quiet = TRUE)
source("dev/ci/optional-integrations.R", local = TRUE)
sys.source("dev/upstream/callr-native-environment/gptr-fixtures/helper-callr-parent-environment.R",
           envir = environment())
paths = c("dev/ci/callr-native.R",
  "dev/upstream/callr-native-environment/gptr-fixtures/helper-callr-parent-environment.R",
  "dev/upstream/callr-native-environment/gptr-fixtures/test-callr-parent-environment.R",
  "dev/upstream/callr-native-environment/gptr-fixtures/test-callr-startup-admission.R",
  "dev/upstream/callr-native-environment/gptr-fixtures/setup.R",
  "tests/testthat/helper-proc-backpressure.R", "dev/ci/lint-callr-native.R")
results = lapply(paths, lintr::lint)
names(results) = paths
print(results)
stopifnot(all(lengths(results) == 0L))
