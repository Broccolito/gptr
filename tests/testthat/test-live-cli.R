# tests/testthat/test-live-cli.R -- the plan routes against the real claude and codex CLIs (P20)
#
# Gated: runs only with GPTR_LIVE_TESTS=true. tests/testthat/setup.R moves HOME to a temporary
# directory, where the CLIs find no sign-in, so these tests also need GPTR_LIVE_HOME set to the
# real home directory; they point HOME/USERPROFILE back at it for the duration of each test. Most
# tests make one small model call; the final two test nested ephemeral CLI sessions. None reads a
# credential file.
# setup.R's options(gptr.replay = "replay") would refuse these non-offline providers (P08's
# replay_guard(); the option outranks GPTR_REPLAY), so the helper sets it to "live"; the calls pass
# .opts = list(context = "none") to limit context. Existing single-route smokes require recorded
# provider consent; the final two seed consent only in their private test configuration. Billing
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
  pid = if (identical(cli, "claude")) "claude-cli" else "codex"
  skip_if_not(identical(settings_get("egress")[[pid]], "ack"),
              paste("provider", pid, "has no previously recorded consent"))
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

# ---- ephemeral transport delegation (P19/P20) -------------------------------------------------
# These exercise real delegation with persistence disabled, not ordinary CLI history behavior.
# Both CLIs must pass discovery, login and confined-run preflight before either sends a prompt.

local_live_cli_delegation = function(.env = parent.frame()) {
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "GPTR_LIVE_TESTS is not true")
  home = Sys.getenv("GPTR_LIVE_HOME")
  skip_if_not(nzchar(home) && dir.exists(home), "GPTR_LIVE_HOME names no directory")
  for (asset in c("mcp_relay.R", "codex_hook.R")) {
    skip_if_not(nzchar(system.file("gptr", asset, package = "gptr")),
                paste("gptr's", asset, "is unavailable"))
  }
  before = if (is.null(pcli_cache$children)) character() else ls(pcli_cache$children)
  local_gw(workspace = FALSE, .env = .env)
  # Only the test-owned configuration is acknowledged; the real user settings stay isolated.
  gptr_config(egress = list(`claude-cli` = "ack", codex = "ack"), .scope = "user")
  gptr_config(budget = list(tokens = 60000, cost = 1, turns = 4L), record = "off",
              transcript = "off", .scope = "session")
  local_gptr_options(cli_turn_timeout = 120, max_attempts = 1L, subagents.max_cli = 2L,
                     max_turns = 2L, .env = .env)
  for (cli in c("claude", "codex")) {
    skip_live_cli(cli, .env = .env)
    skip_if_not(identical(pcli_login_status(cli), "signed in"),
                paste("the", cli, "CLI has no confirmed sign-in"))
  }
  for (model in c("claude-cli/claude-opus-5-5", "codex/gpt-6-sol")) {
    refused = tryCatch(coach_model_kind(model), gptr_error_model_refused = identity)
    if (inherits(refused, "condition")) skip(conditionMessage(refused))
  }
  local_live_role("run", .env = .env)
  withr::defer({
    ids = if (is.null(pcli_cache$children)) character() else ls(pcli_cache$children)
    for (id in setdiff(ids, before)) {
      pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = id)))
    }
  }, envir = .env)
}

test_that("ephemeral Claude Opus delegates a real team to Claude Sonnet and Codex", {
  local_live_cli_delegation()
  e = new.env()
  code = paste0(
    "live_team = peter(\"Use the gptr r tool to run exactly `live_answer = 6 * 7; ",
    "gptr_return(live_answer)`, then reply with 42 only.\", ",
    "agents = list(sonnet = agent(model = \"claude-cli/sonnet\", tools = \"r\"), ",
    "codex = agent(model = \"codex/gpt-6-sol\", tools = \"r\")), ",
    ".opts = list(context = \"none\", max_turns = 2L))\n",
    "gptr_return(live_team$text)"
  )
  s = peter(paste("Use only the gptr r tool to execute this exact R code, then reply with",
                  "the returned reports. Do not edit files or use other tools.\n", code),
            model = "claude-cli/claude-opus-5-5", envir = e, mode = "auto",
            tools = c("minimal", "-read", "-edit", "-write"),
            .opts = list(context = "none", max_turns = 2L))
  expect_identical(s$status, "idle")
  expect_identical(s$model, "claude-cli/claude-opus-5-5")
  team = e$live_team
  expect_s3_class(team, "gptr_session")
  expect_identical(team$kind, "team")
  expect_true(team$id %in% vapply(s$children, function(child) child$id, ""))
  expect_identical(names(team$children), c("sonnet", "codex"))
  expect_identical(team$sonnet$model, "claude-cli/claude-sonnet-5-5")
  expect_identical(team$codex$model, "codex/gpt-6-sol")
  for (child in team$children) {
    expect_identical(child$status, "idle")
    expect_identical(child$envir$live_answer, 42)
    expect_identical(child$value, 42)
    expect_match(child$text, "42", fixed = TRUE)
  }
  entries = Filter(function(entry) identical(entry$custom_type, "gptr.subagent"),
                    session_data(team)$entries)
  expect_identical(vapply(entries, function(entry) entry$data$backend, ""), rep("cli", 2L))
  expect_match(team$text, "### sonnet (claude-cli/claude-sonnet-5-5)", fixed = TRUE)
  expect_match(team$text, "### codex (codex/gpt-6-sol)", fixed = TRUE)
  expect_identical(s$value, team$text)
  usage = gptr_usage(s, by = "model")
  expect_setequal(usage$group, c(s$model, team$sonnet$model, team$codex$model))
  expect_true(all(usage$requests > 0L & usage$output > 0))
  expect_true(all(session_data(s)$usage$route == "plan-cli"))
})

test_that("ephemeral Codex delegates a real child to Claude Sonnet", {
  local_live_cli_delegation()
  e = new.env()
  code = paste0(
    "live_child = peter(\"Use the gptr r tool to run exactly `live_answer = 6 * 7; ",
    "gptr_return(live_answer)`, then reply with 42 only.\", ",
    "model = \"claude-cli/sonnet\", ",
    ".opts = list(context = \"none\", max_turns = 2L))\n",
    "gptr_return(live_child$text)"
  )
  s = peter(paste("Use only the gptr MCP r tool to execute this exact R code, then reply with",
                  "the returned report. Do not edit files or use other tools.\n", code),
            model = "codex/gpt-6-sol", envir = e, mode = "auto",
            tools = c("minimal", "-read", "-edit", "-write"),
            .opts = list(context = "none", max_turns = 2L))
  expect_identical(s$status, "idle")
  expect_identical(s$model, "codex/gpt-6-sol")
  child = e$live_child
  expect_s3_class(child, "gptr_session")
  expect_true(child$id %in% vapply(s$children, function(candidate) candidate$id, ""))
  expect_identical(child$model, "claude-cli/claude-sonnet-5-5")
  expect_identical(child$status, "idle")
  expect_identical(child$envir$live_answer, 42)
  expect_identical(child$value, 42)
  expect_match(child$text, "42", fixed = TRUE)
  expect_identical(s$value, child$text)
  usage = gptr_usage(s, by = "model")
  expect_setequal(usage$group, c(s$model, child$model))
  expect_true(all(usage$requests > 0L & usage$output > 0))
  expect_true(all(session_data(s)$usage$route == "plan-cli"))
})
