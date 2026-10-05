# tests/testthat/test-cli-claude.R -- the cli-claude adapter (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The argv of architecture 8.3 / contract 8.5, verbatim
claude_argv_8_3 = function(mcp, system, model) {
  c("-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--include-partial-messages", "--tools", "", "--strict-mcp-config", "--setting-sources", "",
    "--disable-slash-commands", "--mcp-config", mcp, "--permission-prompt-tool", "stdio",
    "--permission-mode", "default", "--allowedTools", "mcp__gptr__*", "--system-prompt-file",
    system, "--model", model)
}

# ---- build (Task 5) ----------------------------------------------------------------------------

test_that("the claude argv equals architecture 8.3 exactly, plus budget, opt-out, resume", {
  expect_identical(pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md"),
                   claude_argv_8_3("/t/m.json", "/t/s.md", "claude-sonnet-5-5"))
  full = pcli_claude_args("claude-opus-5-5", "/t/m.json", "/t/s.md",
                         budget = list(turns = 7.6, cost = 2.5), optout = "--no-bare",
                         resume = "11111111-1111-4111-8111-111111111111")
  expect_identical(full[seq_len(25L)], claude_argv_8_3("/t/m.json", "/t/s.md", "claude-opus-5-5"))
  expect_identical(full[-seq_len(25L)],
                   c("--max-turns", "7", "--max-budget-usd", "2.5", "--no-bare", "--resume",
                     "11111111-1111-4111-8111-111111111111"))
  expect_false("--bare" %in% full)
  expect_identical(pcli_claude_mcp_json(), '{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}')
})

test_that("a budget that is not finite adds no flag; large and tiny budgets stay numbers", {
  base = claude_argv_8_3("/t/m.json", "/t/s.md", "claude-sonnet-5-5")
  expect_identical(pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md",
                                    budget = list(turns = Inf, cost = Inf)), base)
  big = pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md",
                         budget = list(turns = 3e9, cost = 0.001))
  expect_identical(big[-seq_len(25L)], c("--max-turns", "3000000000", "--max-budget-usd", "0.01"))
  expect_identical(pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md",
                                    budget = list(turns = 0.4, cost = 0))[-seq_len(25L)],
                   c("--max-turns", "1"))
})

test_that("the budget words are plain numbers whatever OutDec and digits say", {
  withr::local_options(OutDec = ",", digits = 2)
  words = function(cost) {
    pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md",
                     budget = list(turns = 1234567, cost = cost))[-seq_len(25L)]
  }
  expect_identical(words(2.5), c("--max-turns", "1234567", "--max-budget-usd", "2.5"))
  expect_identical(words(1234.56789)[[4L]], "1234.5679")
  expect_identical(words(0.3)[[4L]], "0.3")
})

test_that("a budget that is not finite counts as none: that child lives across runs", {
  local_fake_cli_path("claude", "text")
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          stopped$n = stopped$n + 1L
                          state$process = NULL
                          invisible(TRUE)
                        })
  expect_false(pcli_claude_budgeted(list(turns = Inf, cost = Inf)))
  expect_true(pcli_claude_budgeted(list(turns = NULL, cost = 0.5)))
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
             params = list(cli_budget = list(turns = Inf, cost = Inf)))
  opts = stub_opts(run = "r0000000001")
  first = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_identical(utils::tail(first$start$args, 2L), c("--model", "claude-sonnet-5-5"))
  expect_identical(opts$state$claude_flags, list(turns = NULL, cost = NULL))
  opts$state$process = stub_process()
  opts$run = "r0000000002"
  ctx$messages = list(msg_user("Hello"),
                      msg_assistant(list(block_text("Hi")), api = "cli-claude",
                                    provider = "fakeclaude", model = "claude-sonnet-5-5"),
                      msg_user("Again"))
  expect_null(pcli_claude_build(stub_model("claude"), ctx, opts)$start)
  expect_identical(stopped$n, 0L)
  pcli_untrack("s0123456789")
})

test_that("white-space-only text never becomes a content block", {
  input = list(msg_user(list(block_text("  \n "), block_text("Go"))))
  expect_identical(pcli_claude_content(input), list(list(type = "text", text = "Go")))
  expect_identical(pcli_claude_content(list(msg_user(list(block_text(" \t"))))),
                   list(list(type = "text", text = "(no new input)")))
})

test_that("the new input becomes Anthropic content blocks", {
  input = list(msg_user(list(block_context("workspace", "x = 1"), block_text("Plot it"),
                             block_image("iVBORw0KGgo=", mime = "image/png"))))
  out = pcli_claude_content(input)
  expect_identical(out[[1]], list(type = "text", text = "<workspace>\nx = 1\n</workspace>"))
  expect_identical(out[[2]], list(type = "text", text = "Plot it"))
  expect_identical(out[[3]]$source,
                   list(type = "base64", media_type = "image/png", data = "iVBORw0KGgo="))
  expect_identical(pcli_claude_content(list()), list(list(type = "text", text = "(no new input)")))
  line = json_encode(pcli_claude_user_line(out[1]))
  expect_match(line, '^\\{"type":"user","message":\\{"role":"user","content":\\[\\{"type":"text"')
  expect_match(line, '"parent_tool_use_id":null,"session_id":""}', fixed = TRUE)
})

test_that("build() starts a child once, then reuses it for the next turn", {
  local_fake_cli_path("claude", "text")
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL))
  opts = stub_opts()
  ctx = list(system = list(t0 = "You are gptr.", t1 = "Notes."), request_id = "q000000000001",
             messages = list(msg_user("Hello")),
             params = list(cli_mode = "manual", cli_budget = list(cost = 5)))
  spec = pcli_claude_build(stub_model("claude"), ctx, opts)
  args = spec$start$args
  n = length(args)
  expect_identical(spec$start$command, normalizePath(rscript_path(), winslash = "/"))
  expect_identical(args[(n - 26L):n],
                   c(claude_argv_8_3(opts$state$claude_mcp_file, opts$state$claude_system_file,
                                     "claude-sonnet-5-5"), "--max-budget-usd", "5"))
  expect_identical(spec$start$env_profile, "cli-claude")
  expect_false(spec$close_stdin)
  expect_identical(readLines(opts$state$claude_system_file), c("You are gptr.", "", "Notes."))
  expect_identical(readLines(opts$state$claude_mcp_file), pcli_claude_mcp_json())
  expect_identical(spec$send[[1]]$request$subtype, "initialize")
  expect_identical(spec$send[[2]]$message$content, list(list(type = "text", text = "Hello")))
  expect_identical(pcli_tracked("s0123456789"), opts$state)
  opts$state$process = stub_process()
  ctx$messages = c(ctx$messages, list(msg_assistant(list(block_text("Hi")), api = "cli-claude",
                                                    provider = "fakeclaude",
                                                    model = "claude-sonnet-5-5")),
                   list(msg_user("Again")))
  spec2 = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_null(spec2$start)
  expect_length(spec2$send, 1L)
  expect_identical(spec2$send[[1]]$message$content, list(list(type = "text", text = "Again")))
  pcli_untrack("s0123456789")
})

test_that("a budgeted child serves one run; an unbudgeted child lives across runs", {
  local_fake_cli_path("claude", "text")
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          stopped$n = stopped$n + 1L
                          state$process = NULL
                          invisible(TRUE)
                        })
  hi = msg_assistant(list(block_text("Hi")), api = "cli-claude", provider = "fakeclaude",
                     model = "claude-sonnet-5-5")
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
             params = list(cli_budget = list(cost = 5)))
  opts = stub_opts(run = "r0000000001")
  pcli_claude_build(stub_model("claude"), ctx, opts)
  opts$state$process = stub_process()
  opts$state$claude_session = "11111111-1111-4111-8111-111111111111"
  opts$run = "r0000000002"
  ctx$messages = list(msg_user("Hello"), hi, msg_user("Again"))
  next_run = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_identical(stopped$n, 1L)
  expect_identical(utils::tail(next_run$start$args, 4L),
                   c("--max-budget-usd", "5", "--resume", "11111111-1111-4111-8111-111111111111"))
  expect_identical(next_run$send[[2]]$message$content, list(list(type = "text", text = "Again")))
  expect_identical(opts$state$claude_run, "r0000000002")
  free = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
              params = list(cli_mode = "auto"))
  opts2 = stub_opts(run = "r0000000003")
  pcli_claude_build(stub_model("claude"), free, opts2)
  opts2$state$process = stub_process()
  opts2$run = "r0000000004"
  free$messages = list(msg_user("Hello"), hi, msg_user("Again"))
  expect_null(pcli_claude_build(stub_model("claude"), free, opts2)$start)
  expect_identical(stopped$n, 1L)
  pcli_untrack("s0123456789")
})

test_that("a restarted child resumes the CLI session; a fresh one gets the history", {
  local_fake_cli_path("claude", "text")
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = "--no-bare"),
                        pcli_notice = function(cli) invisible(NULL))
  msgs = list(msg_user("first"),
              msg_assistant(list(block_text("answer one")), api = "anthropic-messages",
                            provider = "anthropic", model = "claude-sonnet-5-5"),
              msg_user("second"))
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000002", messages = msgs)
  opts = stub_opts()
  fresh = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_false("--resume" %in% fresh$start$args)
  expect_identical(utils::tail(fresh$start$args, 1L), "--no-bare")
  first = fresh$send[[2]]$message$content
  expect_match(first[[1]]$text, "Assistant: answer one", fixed = TRUE)
  expect_identical(first[[2]]$text, "second")
  own = msg_assistant(list(block_text("answer one")), api = "cli-claude", provider = "fakeclaude",
                      model = "claude-sonnet-5-5")
  ctx$messages = list(msg_user("first"), own, msg_user("second"))
  opts2 = stub_opts()
  opts2$state$claude_session = "11111111-1111-4111-8111-111111111111"
  resumed = pcli_claude_build(stub_model("claude"), ctx, opts2)
  expect_identical(utils::tail(resumed$start$args, 2L),
                   c("--resume", "11111111-1111-4111-8111-111111111111"))
  expect_identical(resumed$send[[2]]$message$content, list(list(type = "text", text = "second")))
  ctx$messages = list(msg_user("first"), own, msg_user("aside"),
                      msg_assistant(list(block_text("answer two")), api = "anthropic-messages",
                                    provider = "anthropic", model = "claude-sonnet-5-5"),
                      msg_user("third"))
  opts3 = stub_opts()
  opts3$state$claude_session = "11111111-1111-4111-8111-111111111111"
  later = pcli_claude_build(stub_model("claude"), ctx, opts3)$send[[2]]$message$content
  expect_match(later[[1]]$text, "User: aside\n\nAssistant: answer two", fixed = TRUE)
  expect_false(grepl("answer one", later[[1]]$text, fixed = TRUE))
  expect_identical(later[[2]]$text, "third")
  pcli_untrack("s0123456789")
})
