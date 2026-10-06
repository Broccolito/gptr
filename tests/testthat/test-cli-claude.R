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

# ---- the cli-claude normaliser (Task 6) ---------------------------------------------------------

test_that("the call-2 capture streams thinking and text and reports the result's usage", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  opts = stub_opts()
  opts$state$pcli_request_id = "q000000000003"
  n = local_normaliser(pcli_claude_parse, stub_model("claude", "claude-haiku-4-5"), opts)
  expect_true(feed_fixture(n, "claude-call2.ndjson"))
  expect_identical(event_types(opts),
                   c("start", "thinking_start", "thinking_end", "thinking_start", "thinking_end",
                     "text_start", "text_delta", "text_end", "done"))
  msg = n$message()
  expect_identical(msg_text(msg), "24")
  expect_identical(vapply(msg$content, function(b) b$type, ""), c("thinking", "thinking", "text"))
  expect_true(nzchar(msg$content[[1]]$signature))
  expect_identical(msg$stop_reason, "stop")
  expect_identical(msg$raw_stop_reason, "end_turn")
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$request_id, "q000000000003")
  expect_identical(msg$response_model, "claude-haiku-4-5-20251001")
  u = msg$usage
  expect_equal(c(u$input, u$output, u$cache_read, u$cache_write_5m, u$cache_write_1h,
                 u$reasoning), c(20, 172, 7448, 0, 7641, 91))
  expect_equal(u$cost$total, 0.0178928)
  expect_identical(opts$state$claude_session, "<session_id>")
  expect_identical(pcli_cache$plan$fakeclaude$type, "five_hour")
  expect_false(opts$state$turn_open)
  expect_null(opts$state$turn_timer)
  expect_identical(n$finish(), msg)
})

test_that("a reused child's turn costs the increase of the CLI's total_cost_usd", {
  state = new.env()
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.02), state), 0.02)
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.035), state), 0.015)
  expect_equal(state$claude_cost_seen, 0.035)
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.01), state), 0.01)
  expect_null(pcli_claude_cost(list(), state))
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.5)), 0.5)
})

test_that("mcp_message requests go to opts$mcp_dispatch; tools/call through the tool FIFO", {
  queued = new.env()
  queued$fns = list()
  local_mocked_bindings(reactor_enqueue_tool = function(run, fn) {
    queued$run = run
    queued$fns[[length(queued$fns) + 1L]] = fn
    invisible("f1")
  })
  opts = stub_opts(run = "r0000000001")
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  mcp = function(id, message, server = "gptr") {
    list(type = "control_request", request_id = id,
         request = list(subtype = "mcp_message", server_name = server, message = message))
  }
  push_obj(n, mcp("c1", list(jsonrpc = "2.0", id = 0L, method = "initialize")))
  push_obj(n, mcp("c2", list(jsonrpc = "2.0", method = "notifications/initialized")))
  push_obj(n, mcp("c3", list(jsonrpc = "2.0", id = 1L, method = "tools/call",
                             params = list(name = "r", arguments = list(code = "1 + 1")))))
  push_obj(n, mcp("c4", list(jsonrpc = "2.0", id = 2L, method = "tools/list"), server = "other"))
  expect_length(opts$log$sent, 3L)
  expect_identical(opts$log$sent[[1]]$response$request_id, "c1")
  expect_identical(opts$log$sent[[1]]$response$response$mcp_response$id, 0L)
  expect_identical(opts$log$sent[[2]]$response$response$mcp_response,
                   list(jsonrpc = "2.0", result = json_obj()))
  expect_identical(opts$log$sent[[3]]$response$response$mcp_response$error$code, -32601L)
  expect_length(queued$fns, 1L)
  expect_identical(queued$run, "r0000000001")
  queued$fns[[1]]()
  expect_length(opts$log$sent, 4L)
  expect_identical(opts$log$sent[[4]]$response$request_id, "c3")
  res = opts$log$sent[[4]]$response$response$mcp_response
  expect_identical(res$result$content[[1]]$text, "[1] 24")
  expect_identical(vapply(opts$log$dispatched, function(m) m$method, ""),
                   c("initialize", "notifications/initialized", "tools/call"))
  expect_length(opts$log$gated, 0L)
})

test_that("can_use_tool allows gptr's own tools without a second gate; others ask the gate", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  ask = function(id, tool) {
    list(type = "control_request", request_id = id,
         request = list(subtype = "can_use_tool", tool_name = tool,
                        input = list(code = "x = 1"), tool_use_id = "toolu_1"))
  }
  push_obj(n, ask("p1", "mcp__gptr__r"))
  expect_identical(opts$log$sent[[1]]$response$response,
                   list(behavior = "allow", updatedInput = list(code = "x = 1")))
  expect_length(opts$log$gated, 0L)
  push_obj(n, ask("p2", "Bash"))
  expect_identical(opts$log$sent[[2]]$response$response,
                   list(behavior = "deny", message = "denied in tests"))
  expect_length(opts$log$gated, 1L)
  expect_identical(opts$log$gated[[1]]$name, "Bash")
  opts2 = stub_opts(gate = function(call) list(decision = "allow", reason = "ok", input = NULL))
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts2)
  push_obj(n2, ask("p3", "Bash"))
  expect_identical(opts2$log$sent[[1]]$response$response$behavior, "allow")
  push_obj(n2, list(type = "control_request", request_id = "p4",
                    request = list(subtype = "rewind_files")))
  expect_identical(opts2$log$sent[[2]]$response,
                   list(subtype = "error", request_id = "p4",
                        error = "Unsupported control request subtype: rewind_files"))
})

test_that("an apiKeySource other than none ends the turn with gptr_error_billing", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    stopped$wait = wait_ack
    invisible(TRUE)
  })
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  expect_true(feed_fixture(n, "claude-apikey.ndjson"))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "billing")
  expect_match(ev$message$error_message, "apiKeySource ANTHROPIC_API_KEY", fixed = TRUE)
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
})

test_that("failed results map to gptr condition classes", {
  run = function(result) {
    opts = stub_opts()
    n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
    push_obj(n, c(list(type = "result", usage = list(input_tokens = 3L)), result))
    ev = opts$log$events[[length(opts$log$events)]]
    list(ev = ev, state = opts$state)
  }
  r = run(list(subtype = "error_max_turns", is_error = TRUE))
  expect_identical(r$ev$error$class, "max_turns")
  expect_match(r$ev$message$error_message, "--max-turns", fixed = TRUE)
  expect_identical(run(list(subtype = "error_max_budget_usd", is_error = TRUE))$ev$error$class,
                   "budget_cost")
  r = run(list(subtype = "success", is_error = TRUE, api_error_status = 429L))
  expect_identical(r$ev$error$class, "rate_limit")
  expect_identical(r$ev$error$status, 429L)
  r = run(list(subtype = "error_during_execution", is_error = TRUE,
               terminal_reason = "aborted_streaming"))
  expect_identical(r$ev$reason, "aborted")
  expect_identical(r$ev$message$stop_reason, "aborted")
  opts = stub_opts()
  opts$state$claude_session = "gone"
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  push_obj(n, list(type = "result", subtype = "error_during_execution", is_error = TRUE,
                   errors = list("No conversation found with session ID: gone")))
  expect_null(opts$state$claude_session)
})

test_that("a turn without a result line ends with an error; an aborted one with aborted", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  feed_fixture(n, "claude-hang.ndjson")
  msg = n$finish()
  expect_identical(msg$stop_reason, "error")
  expect_match(msg$error_message, "exited before the end of the turn", fixed = TRUE)
  expect_identical(msg_text(msg), "Working")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts2)
  opts2$signal$aborted = TRUE
  push_obj(n2, list(type = "control_request", request_id = "c9",
                    request = list(subtype = "mcp_message", server_name = "gptr",
                                   message = list(jsonrpc = "2.0", id = 5L,
                                                  method = "tools/call"))))
  expect_identical(opts2$log$sent[[1]]$response$response$mcp_response$error$message,
                   "The gptr run was aborted.")
  expect_length(opts2$log$dispatched, 0L)
  push_obj(n2, list(type = "control_request", request_id = "c10",
                    request = list(subtype = "can_use_tool", tool_name = "Bash",
                                   input = list(command = "ls"))))
  expect_identical(opts2$log$sent[[2]]$response$response,
                   list(behavior = "deny", message = "The gptr turn is over."))
  expect_length(opts2$log$gated, 0L)
  expect_identical(n2$finish()$stop_reason, "aborted")
})

test_that("the per-turn wall clock interrupts the CLI and ends the turn as out of budget", {
  local_gptr_options(cli_turn_timeout = 0.3)
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  expect_true(reactor_pump(until = function() length(opts$log$events) > 0L, timeout = 5))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "timeout")
  expect_match(ev$message$error_message, "out of budget", fixed = TRUE)
  expect_identical(opts$log$sent[[1]]$request$subtype, "interrupt")
})

test_that("a result line's unreported usage and cost stay unknown, never zeros (IC-74)", {
  u = pcli_claude_usage(list(usage = list(input_tokens = 5L, output_tokens = 2L)))
  expect_equal(c(u$input, u$output), c(5, 2))
  expect_true(all(is.na(c(u$cache_read, u$cache_write_5m, u$cache_write_1h, u$reasoning))))
  expect_true(all(is.na(unlist(u$cost))))
  priced = pcli_claude_usage(list(usage = list(input_tokens = 5L), total_cost_usd = 0.25))
  expect_equal(priced$cost$total, 0.25)
  expect_true(all(is.na(unlist(priced$cost[c("input", "output", "cache_read", "cache_write")]))))
  expect_identical(pcli_claude_usage(list(usage = list(), total_cost_usd = 0))$cost$total, 0)
  bare = pcli_claude_usage(list(usage = list(cache_creation_input_tokens = 40L)))
  expect_equal(c(bare$cache_write_5m, bare$cache_write_1h), c(40, 0))
  state = new.env()
  state$claude_cost_seen = 0.1
  expect_null(pcli_claude_cost(list(total_cost_usd = -1), state))
  expect_null(pcli_claude_cost(list(total_cost_usd = "0.5"), state))
  expect_equal(state$claude_cost_seen, 0.1)
  odd = pcli_claude_usage(list(usage = list(input_tokens = "many", output_tokens = -1L)))
  expect_true(is.na(odd$input) && is.na(odd$output))
  expect_true(is.na(pcli_claude_usage(list())$input))
})

test_that("an R error inside the normaliser ends the turn with one error event (contract 8.1)", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_claude_system = function(obj, s) stop("boom"),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          stopped$n = stopped$n + 1L
                          stopped$wait = wait_ack
                          invisible(TRUE)
                        })
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  expect_true(push_obj(n, list(type = "system", subtype = "init")))
  expect_identical(event_types(opts), c("start", "error"))
  ev = opts$log$events[[2]]
  expect_identical(ev$error$class, "internal")
  expect_match(ev$message$error_message, "boom", fixed = TRUE)
  expect_identical(n$finish(), ev$message)
  # the CLI may still be working on the turn: its child goes, so no later turn reuses it
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
  odd = stub_opts()
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), odd)
  expect_false(push_obj(n2, list(type = list("a", "b"))))
  expect_false(push_obj(n2, list(type = list())))
  expect_length(odd$log$events, 0L)
  expect_true(push_obj(n2, list(type = "result", subtype = "success", is_error = FALSE,
                                stop_reason = 2L, terminal_reason = 5L,
                                usage = list(input_tokens = "many"))))
  last = odd$log$events[[length(odd$log$events)]]
  expect_identical(last$type, "done")
  expect_identical(last$message$stop_reason, "stop")
  expect_true(is.na(last$message$usage$input))
  expect_identical(stopped$n, 1L)
})

test_that("an answer to a control request that cannot be built ends the turn, never hangs", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    invisible(TRUE)
  })
  ask = function(n, tool) {
    push_obj(n, list(type = "control_request", request_id = "p5",
                     request = list(subtype = "can_use_tool", tool_name = tool, input = list())))
  }
  internal_end = function(opts) {
    expect_identical(event_types(opts), c("start", "error"))
    expect_identical(opts$log$events[[2]]$error$class, "internal")
    expect_length(opts$log$sent, 0L)
  }
  opts = stub_opts()
  expect_true(ask(local_normaliser(pcli_claude_parse, stub_model("claude"), opts), 5L))
  internal_end(opts)
  expect_identical(stopped$n, 1L)
  odd_gate = stub_opts(gate = function(call) "allow")
  expect_true(ask(local_normaliser(pcli_claude_parse, stub_model("claude"), odd_gate), "Bash"))
  internal_end(odd_gate)
  expect_identical(stopped$n, 2L)
  other = stub_opts()
  n3 = local_normaliser(pcli_claude_parse, stub_model("claude"), other)
  expect_true(push_obj(n3, list(type = "control_request", request_id = "c8",
                                request = list(subtype = "mcp_message", server_name = "other",
                                               message = "oops"))))
  internal_end(other)
  expect_identical(stopped$n, 3L)
})

test_that("a tools/call still queued when the wall clock ended the turn is refused, not run", {
  local_gptr_options(cli_turn_timeout = 0.3)
  queued = new.env()
  queued$fns = list()
  local_mocked_bindings(reactor_enqueue_tool = function(run, fn) {
    queued$fns[[length(queued$fns) + 1L]] = fn
    invisible("f1")
  })
  opts = stub_opts(run = "r0000000002")
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  call = list(jsonrpc = "2.0", id = 3L, method = "tools/call",
              params = list(name = "r", arguments = list(code = "x = 1")))
  push_obj(n, list(type = "control_request", request_id = "c7",
                   request = list(subtype = "mcp_message", server_name = "gptr", message = call)))
  expect_length(queued$fns, 1L)
  expect_true(reactor_pump(until = function() length(opts$log$events) > 0L, timeout = 5))
  queued$fns[[1]]()
  expect_length(opts$log$dispatched, 0L)
  last = opts$log$sent[[length(opts$log$sent)]]
  expect_identical(last$response$request_id, "c7")
  expect_identical(last$response$response$mcp_response$error$message, "The gptr turn is over.")
})

test_that("the wall clock of an aborted run ends the turn as aborted, without an interrupt", {
  local_gptr_options(cli_turn_timeout = 0.3)
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    stopped$wait = wait_ack
    stopped$open = state$turn_open
    invisible(TRUE)
  })
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  opts$signal$aborted = TRUE
  expect_true(reactor_pump(until = function() length(opts$log$events) > 0L, timeout = 2))
  expect_identical(event_types(opts), c("start", "error"))
  expect_identical(opts$log$events[[2]]$reason, "aborted")
  expect_length(opts$log$sent, 0L)
  expect_identical(n$finish()$stop_reason, "aborted")
  expect_null(opts$state$turn_timer)
  # the child goes once the turn has ended (no interrupt: the turn is no longer open)
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
  expect_false(stopped$open)
})

test_that("a turn P05 ended without its normaliser cannot stop the session's next turn", {
  local_gptr_options(cli_turn_timeout = 0.3)
  killed = new.env()
  killed$n = 0L
  local_mocked_bindings(stream_process_kill = function(p, watch, job) {
    killed$n = killed$n + 1L
    invisible(NULL)
  })
  opts1 = stub_opts()
  n1 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts1)
  t1 = opts1$state$turn_timer
  # P05's stream_abort() ends turn 1 itself and drops its child; the normaliser is not told
  opts1$signal$aborted = TRUE
  local_gptr_options(cli_turn_timeout = 60)
  opts2 = stub_opts()
  opts2$state = opts1$state
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts2)
  t2 = opts2$state$turn_timer
  withr::defer(reactor_cancel(t2))
  child = stub_process(2222L)
  opts2$state$process = child
  # the next turn disarmed turn 1's wall clock
  expect_false(exists(t1, envir = reactor_get()$timers, inherits = FALSE))
  reactor_pump(until = function() killed$n > 0L || length(opts1$log$events) > 0L, timeout = 1)
  expect_identical(killed$n, 0L)
  expect_identical(opts2$state$process, child)
  expect_true(opts2$state$turn_open)
  expect_identical(opts2$state$turn_timer, t2)
  expect_length(opts1$log$events, 0L)
})

test_that("a late timer or queued tools/call of an earlier turn leaves the next turn alone", {
  timers = new.env()
  timers$fns = list()
  queued = new.env()
  queued$fns = list()
  killed = new.env()
  killed$n = 0L
  local_mocked_bindings(
    reactor_timer = function(at, fn, run = NULL) {
      timers$fns[[length(timers$fns) + 1L]] = fn
      paste0("x", length(timers$fns))
    },
    reactor_enqueue_tool = function(run, fn) {
      queued$fns[[length(queued$fns) + 1L]] = fn
      invisible("f1")
    },
    stream_process_kill = function(p, watch, job) {
      killed$n = killed$n + 1L
      invisible(NULL)
    }
  )
  call = list(jsonrpc = "2.0", id = 1L, method = "tools/call",
              params = list(name = "r", arguments = list(code = "x = 1")))
  opts1 = stub_opts(run = "r0000000001")
  n1 = pcli_claude_parse(stub_model("claude"), opts1)
  push_obj(n1, list(type = "control_request", request_id = "c1",
                    request = list(subtype = "mcp_message", server_name = "gptr", message = call)))
  # P05 lets go of turn 1 without its normaliser (its run settled: stream_detach()); turn 2
  # of the session starts its own child on the same adapter state
  opts2 = stub_opts(run = "r0000000002")
  opts2$state = opts1$state
  n2 = pcli_claude_parse(stub_model("claude"), opts2)
  child = stub_process(2222L)
  opts2$state$process = child
  queued$fns[[1]]()
  timers$fns[[1]]()
  expect_length(opts1$log$dispatched, 0L)
  expect_length(opts1$log$sent, 1L)
  expect_identical(opts1$log$sent[[1]]$response$response$mcp_response$error$message,
                   "The gptr turn is over.")
  expect_length(opts1$log$events, 0L)
  expect_identical(killed$n, 0L)
  expect_identical(opts2$state$process, child)
  expect_true(opts2$state$turn_open)
  expect_identical(opts2$state$turn_timer, "x2")
  expect_length(opts2$log$sent, 0L)
  # turn 2's own wall clock still ends turn 2 and stops its child
  timers$fns[[2]]()
  expect_identical(event_types(opts2), c("start", "error"))
  expect_identical(opts2$log$sent[[1]]$request$subtype, "interrupt")
  expect_identical(killed$n, 1L)
  expect_null(opts2$state$process)
})
