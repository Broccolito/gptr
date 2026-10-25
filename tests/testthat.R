# Windows native files get fresh supervisors under R CMD check, and CRAN runs a fixed list of
# files (D-240). Other checks keep one suite.
library(testthat)
library(gptr)

if (.Platform$OS.type == "windows" && identical(Sys.getenv("NOT_CRAN"), "true")) {
  local({
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
    files = sort(list.files("testthat", pattern = "^test.*[.][rR]$"))
    stopifnot(length(files) > length(native), !anyDuplicated(files), all(native %in% files))
    stopifnot(all(grepl("^test-[A-Za-z0-9_-]+[.][rR]$", files)))
    ordinary = setdiff(files, native)
    source("testthat/ci-shard.R", local = TRUE)
    selected = ci_shard_files(ordinary)
    names = sub("[.][rR]$", "", sub("^test[-_]", "", selected))
    stopifnot(all(grepl("^[A-Za-z0-9_-]+$", names)), !anyDuplicated(names))
    result = test_check("gptr", filter = paste0("^(", paste(names, collapse = "|"), ")$"))
    # A CI shard fails unless each of its files recorded a test result
    if (nzchar(Sys.getenv("GPTR_CI_TEST_SHARD"))) {
      missing = setdiff(selected, as.data.frame(result)$file)
      if (length(missing)) {
        stop("CI shard files that recorded no test result (a file-level skip() records none): ",
             toString(missing))
      }
    }
  })
} else if (!identical(Sys.getenv("NOT_CRAN"), "true")) {
  cran = c(
    "aaa-state", "agent-loop", "agent-run", "auth-dotenv", "auth-redact", "auth-secrets",
    "bridge-sh", "ckpt-objects", "ckpt-rewind", "cli-claude", "cli-codex", "cli-common",
    "console-input", "console-render", "console-repl", "console-ui", "env-describe",
    "env-history", "env-probe", "env-snapshot", "eval-core", "eval-format", "eval-guard",
    "ext-api", "ext-builtins", "ext-check", "ext-events", "ext-load", "ext-plugins",
    "ext-registry", "ext-specs", "gptr-capture", "gptr-config", "http-reactor", "http-retry",
    "http-sse", "json-schema", "mcp-client", "perm-classify", "perm-gate", "perm-plan",
    "perm-rules", "proc-spawn", "proc-supervise", "proc-writer-runtime", "prompt-compact",
    "prompt-sections", "prompt-text", "provider-anthropic", "provider-fake", "provider-google",
    "provider-openai-completions", "provider-openai-responses", "provider-transform",
    "s1-client", "s1-route", "subagent-backends", "subagent-worker", "tool-edit",
    "tool-namespace", "tool-read", "utils-conditions", "utils-hash", "utils-options",
    "utils-paths", "zzz"
  )
  test_check("gptr", filter = paste0("^(", paste(cran, collapse = "|"), ")$"))
} else {
  test_check("gptr")
}
