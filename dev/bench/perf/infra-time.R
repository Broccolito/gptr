# INFRA-24 (architecture 6.18): the offline INFRA suite runs under --as-cran in under 60 s. From
# the repository root (the CI bench job runs it):
#   Rscript --vanilla dev/bench/perf/infra-time.R
# NOT_CRAN=false skips every skip_on_cran() test, as on CRAN; exit 1 when a test fails or the
# INFRA tests take 60 s or more.

source(file.path("dev", "bench", "common.R"), local = TRUE)

# The acceptance-test files of architecture 6.18 (INFRA-02 names every test-provider-*.R file).
infra_files = c("http-reactor", "http-request", "http-retry", "http-sse", "provider-events",
                "provider-fake", "provider-message", "provider-transform", "provider-registry",
                "provider-usage", "provider-anthropic", "provider-openai-responses",
                "provider-openai-completions", "provider-google", "agent-dispatch", "agent-loop",
                "agent-run", "perm-gate", "session-store", "session-object", "s1-route",
                "prompt-compact", "console-render", "console-interrupt", "subagent-backends",
                "cli-claude", "cli-codex", "agent-background", "secrets-e2e")
infra_limit = 60

# The suite is the INFRA-nn acceptance tests (6.18 row 24, D-178): the run's elapsed time less the
# blocks naming no INFRA-nn in files whose other blocks do; a file naming none counts whole.
infra_seconds = function(res, secs) {
  tag = grepl("INFRA-[0-9]", res$test)
  secs - sum(res$real[!tag & res$file %in% res$file[tag]])
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  bench_require("pkgload", "loading the gptr source tree")
  files = file.path("tests", "testthat", paste0("test-", infra_files, ".R"))
  if (!all(file.exists(files))) {
    stop("INFRA test files missing: ", paste(files[!file.exists(files)], collapse = ", "))
  }
  Sys.setenv(NOT_CRAN = "false")
  t0 = proc.time()[["elapsed"]]
  res = as.data.frame(testthat::test_local(".", reporter = "summary", stop_on_failure = FALSE,
                                           filter = paste0("^(", paste(infra_files,
                                                                       collapse = "|"), ")$")))
  secs = proc.time()[["elapsed"]] - t0
  infra = infra_seconds(res, secs)
  bad = sum(res$failed) + sum(res$error)
  message(sprintf(paste("[bench] INFRA suite: %d files, %d tests, %d failed, %.1f s in all,",
                        "INFRA tests %.1f s (limit %d s)"),
                  length(files), nrow(res), bad, secs, infra, infra_limit))
  if (bad > 0) stop("the INFRA suite has ", bad, " failing test(s)")
  if (infra >= infra_limit) stop(sprintf("the INFRA tests took %.1f s (limit %d s)", infra,
                                         infra_limit))
}))
