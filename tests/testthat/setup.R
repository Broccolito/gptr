# Test environment (contract section 3.2 and 12.2, IC-63): nothing a test does may touch the
# user's home directory, the user's R_user_dir() folders, a real `.gptr/` workspace, real keys or
# the network. Everything below is restored when the test run ends.
local({
  root = withr::local_tempdir("gptr-tests-", .local_envir = testthat::teardown_env())
  dirs = c(
    config = "user-config", data = "user-data", cache = "user-cache", home = "home",
    appdata = "appdata", localappdata = "localappdata", xdg = "xdg-config", project = "project"
  )
  paths = stats::setNames(file.path(root, dirs), names(dirs))
  for (path in paths) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  withr::local_envvar(
    R_USER_CONFIG_DIR = paths[["config"]],
    R_USER_DATA_DIR = paths[["data"]],
    R_USER_CACHE_DIR = paths[["cache"]],
    HOME = paths[["home"]],
    USERPROFILE = paths[["home"]],
    APPDATA = paths[["appdata"]],
    LOCALAPPDATA = paths[["localappdata"]],
    XDG_CONFIG_HOME = paths[["xdg"]],
    GPTR_PROJECT_ROOT = paths[["project"]],
    GPTR_REPLAY = "replay",
    OMP_THREAD_LIMIT = "2",
    .local_envir = testthat::teardown_env()
  )
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
    keys = c(
      "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
      "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY", "MISTRAL_API_KEY",
      "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY", "FIREWORKS_API_KEY", "VLLM_API_KEY",
      "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT", "AWS_BEARER_TOKEN_BEDROCK",
      "TYPESAFE_API_KEY", "JEV_KEY", "JEV_API_KEY", "TYPESAFE_KEY"
    )
    withr::local_envvar(
      stats::setNames(rep("", length(keys)), keys),
      .local_envir = testthat::teardown_env()
    )
  }
  withr::local_options(
    gptr.interactive = FALSE,
    gptr.quiet = TRUE,
    .local_envir = testthat::teardown_env()
  )
})
