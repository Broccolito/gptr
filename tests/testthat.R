# A CI shard (GPTR_CI_TEST_SHARD, testthat/ci-shard.R) runs its share of the test files, Windows
# native files get fresh supervisors under R CMD check, and CRAN runs a fixed list of files
# (D-240). Other checks keep one suite.
library(testthat)
library(gptr)

if (identical(Sys.getenv("NOT_CRAN"), "true") &&
    (nzchar(Sys.getenv("GPTR_CI_TEST_SHARD")) || .Platform$OS.type == "windows")) {
  local({
    files = sort(list.files("testthat", pattern = "^test.*[.][rR]$"))
    stopifnot(!anyDuplicated(files), all(grepl("^test-[A-Za-z0-9_-]+[.][rR]$", files)))
    if (.Platform$OS.type == "windows") {
      native = c(
        "test-bridge-python-native.R",
        "test-proc-marker-family.R",
        "test-proc-rscript-native.R",
        "test-proc-windows-backpressure.R",
        "test-proc-writer-idle-boundary.R",
        "test-proc-writer-idle-slots.R",
        "test-proc-writer-prototype.R",
        "test-proc-writer-retirement.R",
        "test-proc-writer-runtime.R",
        "test-subagent-worker.R"
      )
      stopifnot(length(files) > length(native), all(native %in% files))
      files = setdiff(files, native)
    }
    source("testthat/ci-shard.R", local = TRUE)
    selected = ci_shard_files(files)
    if (!nzchar(Sys.getenv("GPTR_CI_TEST_SHARD"))) {
      test_check("gptr", filter = ci_shard_filter(selected))
    } else {
      # A CI shard's log names each file with its time, and the shard fails unless each of its
      # files recorded a test result
      result = test_check("gptr", filter = ci_shard_filter(selected), reporter = "progress")
      missing = setdiff(selected, as.data.frame(result)$file)
      if (length(missing)) {
        stop("CI shard files that recorded no test result (a file-level skip() records none): ",
             toString(missing))
      }
    }
  })
} else if (!identical(Sys.getenv("NOT_CRAN"), "true")) {
  cran = c(
    "aaa-state", "agent-run", "auth-redact", "auth-secrets", "bridge-sh", "ckpt-rewind",
    "cli-claude", "cli-codex", "console-render", "console-repl", "env-describe", "eval-core",
    "ext-builtins", "ext-check", "gptr-capture", "http-reactor", "json-schema", "mcp-client",
    "perm-classify", "perm-gate", "perm-plan", "perm-rules", "proc-spawn", "prompt-compact",
    "provider-google", "provider-openai-completions", "provider-openai-responses", "s1-client",
    "s1-route", "subagent-worker", "tool-edit", "tool-namespace", "tool-read", "utils-options",
    "zzz"
  )
  test_check("gptr", filter = paste0("^(", paste(cran, collapse = "|"), ")$"))
} else {
  test_check("gptr")
}
