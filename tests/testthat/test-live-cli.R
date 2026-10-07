# tests/testthat/test-live-cli.R -- the plan routes against the real claude and codex CLIs (P20)
#
# Gated: runs only with GPTR_LIVE_TESTS=true. tests/testthat/setup.R moves HOME to a temporary
# directory, where the CLIs find no sign-in, so these tests also need GPTR_LIVE_HOME set to the
# real home directory; they point HOME/USERPROFILE back at it for the duration of each test. Each
# test makes one small model call through the user's own plan and never reads a credential file.
# setup.R's options(gptr.replay = "replay") would refuse these non-offline providers (P08's
# replay_guard(); the option outranks GPTR_REPLAY), so the helper sets it to "live"; the calls pass
# .opts = list(context = "none"), P08's egress exemption for a non-interactive run; the billing
# variables are unset so the CLIs bill the plan and P03 has nothing to warn about.
#   GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME" \
#     Rscript --vanilla -e 'devtools::test(filter = "live-cli")'

live_billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                      "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                      "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                      "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY",
                      "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")

skip_live_cli = function(cli, .env = parent.frame()) {
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "GPTR_LIVE_TESTS is not true")
  home = Sys.getenv("GPTR_LIVE_HOME")
  skip_if_not(nzchar(home) && dir.exists(home), "GPTR_LIVE_HOME names no directory")
  withr::local_envvar(HOME = home, USERPROFILE = home, .local_envir = .env)
  withr::local_envvar(stats::setNames(rep(NA_character_, length(live_billing_vars)),
                                      live_billing_vars), .local_envir = .env)
  local_gptr_options(replay = "live", .env = .env)
  found = tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
  skip_if(is.null(found), paste("the", cli, "CLI is not installed"))
  invisible(found)
}

test_that("the claude plan route evaluates R in the live session", {
  skip_live_cli("claude")
  e = new.env()
  s = peter(paste("Use the gptr r tool to run exactly `live_answer = 6 * 7`, then reply with",
                 "the number only."),
           model = "claude-cli/claude-haiku-4-5", envir = e, mode = "auto",
           .opts = list(context = "none"))
  withr::defer(pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = s$id))))
  expect_identical(e$live_answer, 42)
  expect_match(s$text, "42", fixed = TRUE)
  m = s$messages[[length(s$messages)]]
  expect_identical(m$route, "plan-cli")
  expect_gt(m$usage$output, 0)
})

test_that("Codex in a non-git temporary directory calls the gptr r tool", {
  skip_live_cli("codex")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
  withr::defer(gptr_mcp_serve(stop = TRUE))
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  expect_false(dir.exists(file.path(dir, ".git")))
  e = new.env()
  s = peter(paste("Call the gptr MCP tool `r` with the code `live_answer = sum(1:10);",
                 "live_answer`, then reply with the result only."),
           model = "codex/default", envir = e, mode = "auto", .opts = list(context = "none"))
  expect_identical(e$live_answer, 55L)
  expect_match(s$text, "55", fixed = TRUE)
})
