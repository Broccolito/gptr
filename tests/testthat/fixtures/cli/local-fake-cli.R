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
