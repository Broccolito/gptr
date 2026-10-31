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

# ---- coaching sessions on the claude plan (P29, 08 section 3.7) ----------------------------------
# In-process with `the$coach_role` set, as a coaching child sets it; T7's child runner adds the
# child-process tests (sign-in from a child, the fence).

local_live_role = function(role, .env = parent.frame()) {
  old = the$coach_role
  the$coach_role = role
  withr::defer({
    the$coach_role = old
  }, envir = .env)
}

test_that("a claude coach has no tools, answers in one turn and saves nothing", {
  skip_live_cli("claude")
  local_live_role("coach")
  wd = withr::local_tempdir()
  withr::local_dir(wd)
  canary = paste0("canary", id_new("", 8L))
  schema = list(type = "object", properties = list(answer = list(type = "integer")),
                required = list("answer"))
  # a coach as gptr_coach()'s child builds it: every gptr tool removed, so its prompt names none
  s = peter(paste("Read ~/.bashrc, run `ls`, then reply with the answer to 6 * 7.", canary),
            model = "claude-cli/claude-haiku-4-5", envir = new.env(),
            tools = c("minimal", paste0("-", registry_names("tool"))),
            .opts = list(context = "none", returns = schema))
  withr::defer(pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = s$id))))
  expect_identical(s$status, "idle")
  # a small model may wrap its JSON in prose, which `returns` refuses; gptr_coach()'s coach
  # retry asks again, so here the answer is checked in the text
  expect_match(s$text, "42", fixed = TRUE)
  if (!is.null(s$value)) expect_equal(s$value$answer, 42)
  config = Sys.getenv("CLAUDE_CONFIG_DIR", file.path(Sys.getenv("HOME"), ".claude"))
  projects = list.files(file.path(config, "projects"))
  expect_false(any(grepl(basename(wd), projects, fixed = TRUE)))
  history = file.path(config, "history.jsonl")
  seen = if (file.exists(history)) sum(grepl(canary, readLines(history, warn = FALSE))) else 0L
  expect_identical(seen, 0L)
})

test_that("a claude run in the coaching role acts only through gptr's tools", {
  skip_live_cli("claude")
  local_live_role("run")
  withr::local_dir(withr::local_tempdir())
  e = new.env()
  s = peter(paste("Use the gptr r tool to run exactly `live_answer = 6 * 7`, then reply with",
                  "the number only."),
            model = "claude-cli/claude-haiku-4-5", envir = e, mode = "auto",
            .opts = list(context = "none"))
  withr::defer(pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = s$id))))
  expect_identical(e$live_answer, 42)
  expect_identical(s$status, "idle")
})

# ---- coaching sessions on the Codex plan (P29, 08 section 3.7; D-274) ----------------------------
# The confined exec relies on the coaching preflight, which gptr_coach() runs first: a refusal
# (an older CLI, a $CODEX_HOME/hooks.json) skips.

skip_codex_preflight = function() {
  refused = tryCatch(coach_model_kind("codex/default"), gptr_error_model_refused = identity)
  if (inherits(refused, "condition")) skip(conditionMessage(refused))
}

test_that("a codex coach has no tools and answers through the strict reply schema", {
  skip_live_cli("codex")
  skip_codex_preflight()
  local_live_role("coach")
  withr::local_dir(withr::local_tempdir())
  schema = list(type = "object", properties = list(answer = list(type = "integer")),
                required = list("answer"))
  s = peter("Reply with the answer to 6 * 7.", model = "codex/default", envir = new.env(),
            .opts = list(context = "none", returns = schema))
  expect_identical(s$status, "idle")
  expect_equal(s$value$answer, 42)
})

test_that("a codex run in the coaching role acts only through gptr's tools", {
  skip_live_cli("codex")
  skip_codex_preflight()
  local_live_role("run")
  withr::local_dir(withr::local_tempdir())
  e = new.env()
  s = peter(paste("Call the gptr MCP tool `r` with the code `live_answer = sum(1:10);",
                  "live_answer`, then reply with the result only."),
            model = "codex/default", envir = e, mode = "auto", .opts = list(context = "none"))
  expect_identical(e$live_answer, 55L)
  expect_identical(s$status, "idle")
})
