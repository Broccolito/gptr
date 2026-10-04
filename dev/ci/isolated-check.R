# Local offline validation with user state isolated before package load.
# Run from the repository root, with R_LIBS_USER pointing to the development library.
# Usage: Rscript --vanilla dev/ci/isolated-check.R test <filter>
#        Rscript --vanilla dev/ci/isolated-check.R lint [files ...]
#        Rscript --vanilla dev/ci/isolated-check.R document
#        Rscript --vanilla dev/ci/isolated-check.R check <output-directory>
#        Rscript --vanilla dev/ci/isolated-check.R connections
(function() {
  root = tempfile("gptr-root-check-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  paths = stats::setNames(file.path(root, c("home", "config", "cache", "data", "project")),
                          c("home", "config", "cache", "data", "project"))
  for (path in paths) dir.create(path)
  withr::local_envvar(
    HOME = paths[["home"]], USERPROFILE = paths[["home"]],
    R_USER_CONFIG_DIR = paths[["config"]], R_USER_CACHE_DIR = paths[["cache"]],
    R_USER_DATA_DIR = paths[["data"]], APPDATA = paths[["config"]],
    LOCALAPPDATA = paths[["cache"]], XDG_CONFIG_HOME = paths[["config"]],
    XDG_CACHE_HOME = paths[["cache"]], XDG_DATA_HOME = paths[["data"]],
    GPTR_PROJECT_ROOT = paths[["project"]], GPTR_REPLAY = "replay",
    GPTR_LIVE_TESTS = "false", OMP_THREAD_LIMIT = "2"
  )
  # Package load precedes testthat setup; keep offline validation free of credentials.
  keys = c("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
           "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY", "MISTRAL_API_KEY",
           "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY", "FIREWORKS_API_KEY",
           "VLLM_API_KEY", "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT",
           "AWS_BEARER_TOKEN_BEDROCK", "TYPESAFE_API_KEY", "JEV_KEY", "JEV_API_KEY",
           "TYPESAFE_KEY", "jev-key", "GITHUB_PAT", "GH_TOKEN")
  withr::local_envvar(stats::setNames(rep("", length(keys)), keys))
  withr::local_options(gptr.project_root = paths[["project"]], gptr.replay = "replay",
                      gptr.interactive = FALSE)
  args = commandArgs(trailingOnly = TRUE)
  if (!length(args)) stop("Supply a validation action")
  if (args[[1L]] == "test") {
    if (length(args) != 2L) stop("Supply one test filter")
    testthat::set_max_fails(Inf)
    devtools::test(filter = args[[2L]], stop_on_failure = TRUE)
  } else if (args[[1L]] == "lint") {
    pkgload::load_all(quiet = TRUE)
    if (length(args) == 1L) {
      out = lintr::lint_package()
      print(out)
      stopifnot(length(out) == 0L)
    } else {
      out = lapply(args[-1L], lintr::lint)
      print(out)
      stopifnot(all(lengths(out) == 0L))
    }
  } else if (args[[1L]] == "document") {
    devtools::document()
  } else if (args[[1L]] == "connections") {
    source("dev/ci/check-connections.R", local = TRUE)
    testthat::set_max_fails(Inf)
    run_gate()
  } else if (args[[1L]] == "check") {
    if (length(args) != 2L) stop("Supply an output directory for the package check")
    devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning",
                    document = FALSE, check_dir = args[[2L]])
  } else {
    stop("Unknown isolated check action")
  }
})()
