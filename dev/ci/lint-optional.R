# Keep the complete scoped lint program in a file: Windows Rscript -e quoting differs.
pkgload::load_all(quiet = TRUE)
paths = c(
  "R/artifact-app.R", "R/gptr-config.R", "tests/testthat/setup.R",
  "tests/testthat/test-tool-search.R", "tests/testthat/test-artifact-browser-cleanup.R",
  "tests/testthat/test-config-content-cache.R", "tests/testthat/test-gptr-config.R",
  "tests/testthat/helper-windows-security.R", "tests/testthat/test-windows-security.R",
  "R/proc-spawn.R", "R/proc-supervise.R", "R/http-reactor.R", "R/cli-codex.R",
  "R/utils-paths.R", "R/utils-encoding.R", "R/tool-write.R", "R/tool-walk.R",
  "R/ckpt-files.R", "tests/testthat/test-windows-link-policy.R",
  "tests/testthat/test-utils-encoding.R", "tests/testthat/test-utils-paths.R",
  "tests/testthat/test-tool-write.R", "tests/testthat/test-tool-walk.R",
  "tests/testthat/test-ckpt-files.R", "tests/testthat/test-tool-edit.R",
  "tests/testthat/test-storage-boundaries.R",
  "tests/testthat/helper-proc-backpressure.R", "tests/testthat/test-proc-windows-backpressure.R",
  "tests/testthat/helper-proc-writer-prototype.R", "tests/testthat/test-proc-writer-prototype.R",
  "tests/testthat/test-proc-backpressure-sampling.R",
  "tests/testthat/helper-proc-writer-runtime.R", "tests/testthat/test-proc-writer-runtime.R",
  "tests/testthat/test-proc-spawn.R", "tests/testthat/test-proc-supervise.R",
  "tests/testthat/test-http-reactor.R", "tests/testthat/test-arch-layers.R",
  "tests/testthat/test-lint-rules.R",
  "tests/testthat/test-proc-writer-idle-slots.R",
  "tests/testthat/helper-proc-marker-family.R", "tests/testthat/test-proc-marker-family.R",
  "tests/testthat/test-mcp-client.R", "tests/testthat/test-subagent-worker.R",
  "tests/testthat/test-cli-common.R", "tests/testthat/test-cli-claude.R",
  "tests/testthat/test-cli-codex.R", "tests/testthat/helper-cli-codex-capabilities.R",
  "dev/ci/optional-integrations.R", "dev/ci/test-optional-integrations.R",
  "dev/ci/lint-optional.R")
stopifnot(all(file.exists(paths)))
results = lapply(paths, lintr::lint)
names(results) = paths
print(results)
stopifnot(all(lengths(results) == 0L))
