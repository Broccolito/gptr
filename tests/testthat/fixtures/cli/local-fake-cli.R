# tests/testthat/fixtures/cli/local-fake-cli.R -- shared support of test-cli-*.R (P20).
# Each test-cli-*.R file sources it as its first statement, with local = TRUE, from the path
# testthat::test_path("fixtures", "cli", "local-fake-cli.R") (P20 owns fixtures/cli/, not a
# helper-*.R file). Tests run inside the gptr namespace, so internal functions are visible.

# The fixtures directory of the fake CLI, absolute (fixed when this file is sourced, so tests
# that change the working directory, such as local_project(), still find it)
cli_fixture_dir = normalizePath(testthat::test_path("fixtures", "cli"), winslash = "/")
fake_cli_fixtures = function() cli_fixture_dir

# The variables that switch a CLI to API billing (G6 3.7; P03 removes them with a billing_env
# warning). The helpers unset them, so a developer's own environment never adds a warning.
cli_billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                     "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                     "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                     "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY",
                     "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")

# Point options(gptr.cli_path) at the fake CLI in one case for the calling test
local_fake_cli_path = function(cli, case = "text", .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  log = file.path(normalizePath(dir, winslash = "/"), "fake-log.jsonl")
  path = pcli_fake_command(cli, case, fixtures = fake_cli_fixtures(), log = log)
  paths = getOption("gptr.cli_path") %||% list()
  paths[[cli]] = path
  withr::local_options(gptr.cli_path = paths, .local_envir = .env)
  # the fake Rscript child finds jsonlite and curl in this session's libraries (setup.R moves
  # HOME, so a user library would not be found by default)
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
                      .local_envir = .env)
  withr::local_envvar(stats::setNames(rep(NA_character_, length(cli_billing_vars)),
                                      cli_billing_vars), .local_envir = .env)
  list(path = path, log = log, cli = cli)
}

# Rows of a fake CLI's log (JSON lines), optionally of one kind
fake_log = function(fake, kind = NULL) {
  if (!file.exists(fake$log)) return(list())
  lines = readLines(fake$log, encoding = "UTF-8", warn = FALSE)
  rows = lapply(lines[nzchar(lines)], json_decode)
  if (is.null(kind)) return(rows)
  Filter(function(r) identical(r[["kind"]], kind), rows)
}

# The argv of the fake's session runs (not its --version/--help/sandbox probes)
fake_argv = function(fake) {
  lapply(fake_log(fake, "argv"), function(r) as.character(unlist(r[["argv"]])))
}

# Environment variable names each session run of the fake saw
fake_env_names = function(fake) {
  lapply(fake_log(fake, "env"), function(r) as.character(unlist(r[["names"]])))
}

# The stdin prompts a fake codex received, in order, as raw bytes
fake_prompts = function(fake) {
  lapply(fake_log(fake, "prompt"), function(r) readBin(r[["file"]], "raw", file.size(r[["file"]])))
}

# Process ids of the fake's session runs
fake_pids = function(fake) {
  vapply(fake_log(fake, "start"), function(r) as.integer(r[["pid"]]), 1L)
}

# Every process is gone within 10 seconds
expect_all_dead = function(pids) {
  deadline = Sys.time() + 10
  alive = function() any(vapply(pids, function(p) isTRUE(pid_alive(p)), NA))
  while (alive() && Sys.time() < deadline) Sys.sleep(0.1)
  expect_false(alive())
}

# Point options(gptr.cli_path) at the fake CLI and register its offline provider record
# ("fakeclaude" or "fakecodex", IC-45) for the calling test; `model` is the first model ref
local_fake_cli = function(cli, case = "text", models = NULL, register = TRUE,
                          .env = parent.frame()) {
  fake = local_fake_cli_path(cli, case, .env = .env)
  spec = pcli_fake_provider(cli, models = models)
  if (register) {
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  c(fake, list(provider = spec, id = spec$id,
               model = paste0(spec$id, "/", spec$models[[1L]]$id)))
}
