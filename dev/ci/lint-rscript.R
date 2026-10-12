# Helper-loaded source lint is separate from the installed execution gate.
pkgload::load_all(quiet = TRUE)
lint_paths = c("R/proc-rscript.R", "R/proc-spawn.R", "R/subagent-worker.R",
  "R/artifact-app.R", "R/artifact-registry.R", "tests/testthat/test-proc-rscript.R",
  "tests/testthat/helper-proc-rscript.R", "tests/testthat/test-proc-rscript-native.R",
  "tests/testthat/test-subagent-worker.R", "tests/testthat/test-subagent-worker-rscript.R",
  "tests/testthat/test-artifact-app.R", "tests/testthat/test-artifact-registry.R",
  "dev/ci/rscript-native.R", "dev/ci/lint-rscript.R")
lints = lapply(lint_paths, lintr::lint)
print(lints)
stopifnot(all(lengths(lints) == 0L))
