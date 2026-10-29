# tests/testthat/test-cli-codex.R -- the cli-codex adapter, the codex routes end to end and the
# CLI leg of INFRA-16 (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The relay overrides of IC-65 as amended by IC-79, verbatim: Codex starts gptr's stdio relay
codex_relay_args = function(dir, seconds = "3600") {
  relay = system.file("gptr", "mcp_relay.R", package = "gptr")
  c("-c", paste0("mcp_servers.gptr.command=\"", rscript_path(), "\""),
    "-c", paste0("mcp_servers.gptr.args=[\"--vanilla\",\"", relay, "\",\"", dir, "\",\"",
                 seconds, "\"]"),
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.startup_timeout_sec=60",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

# ---- the cli-codex adapter (Task 7) -------------------------------------------------------------

test_that("the codex argv starts gptr's stdio relay; the resume form uses -c sandbox_mode=", {
  expect_identical(pcli_codex_args("gpt-6-sol", "/w", "read-only", "/r"),
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", "/w", codex_relay_args("/r"), "--sandbox", "read-only",
                     "-"))
  resumed = pcli_codex_args("gpt-6-sol", "/w", "workspace-write", "/r",
                           resume = "0199a213-thread")
  expect_identical(resumed,
                   c("exec", "resume", "0199a213-thread", "--json", "--ignore-user-config",
                     "--skip-git-repo-check", "-m", "gpt-6-sol", codex_relay_args("/r"), "-c",
                     "sandbox_mode=workspace-write", "-"))
  expect_false(any(c("-C", "-s", "--sandbox") %in% resumed))
  expect_false(any(grepl("url=|bearer_token", resumed)))
  # paths are TOML basic strings; the relay waits no longer than the turn's wall clock
  local_gptr_options(cli_turn_timeout = 90)
  args = pcli_codex_args("gpt-6-sol", "/w", "read-only", "C:\\Temp\\a\"b")
  expect_true(paste0("mcp_servers.gptr.args=[\"--vanilla\",\"",
                     system.file("gptr", "mcp_relay.R", package = "gptr"),
                     "\",\"C:\\\\Temp\\\\a\\\"b\",\"90\"]") %in% args)
})

test_that("plan, manual and edits run read-only; auto and yolo write; Windows falls back", {
  local_mocked_bindings(pcli_is_windows = function() FALSE)
  for (mode in c("plan", "manual", "edits")) {
    expect_identical(pcli_codex_sandbox(mode, "codex"), "read-only")
  }
  expect_identical(pcli_codex_sandbox("auto", "codex"), "workspace-write")
  expect_identical(pcli_codex_sandbox("yolo", "codex"), "workspace-write")
  local_mocked_bindings(pcli_is_windows = function() TRUE,
                        pcli_codex_windows_ready = function(path) FALSE)
  w = expect_warning(pcli_codex_sandbox("auto", "codex"), class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), "runs read-only", fixed = TRUE)
})

test_that("the prompt carries instructions and history on a fresh thread only", {
  msgs = list(msg_user("first"),
              msg_assistant(list(block_text("one")), api = "fake", provider = "fake",
                            model = "fake-1"),
              msg_user("second"))
  ctx = list(system = list(t0 = "You are gptr.", t1 = ""), messages = msgs)
  fresh = pcli_codex_prompt(ctx, fresh = TRUE)
  expect_match(fresh, "^<gptr_instructions>\nYou are gptr.\n</gptr_instructions>\n\n")
  expect_match(fresh, "Assistant: one", fixed = TRUE)
  expect_match(fresh, "\n\nsecond$")
  expect_identical(pcli_codex_prompt(ctx, fresh = FALSE, provider = "fake"), "second")
  foreign = pcli_codex_prompt(ctx, fresh = FALSE, provider = "fakecodex")
  expect_match(foreign, "^<conversation_history>\n")
  expect_match(foreign, "Assistant: one", fixed = TRUE)
  expect_false(grepl("<gptr_instructions>", foreign, fixed = TRUE))
})

test_that("build() starts one exec per turn with a fresh private relay mailbox", {
  skip_on_cran()
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(
    pcli_probe = function(path) list(resume = TRUE),
    pcli_notice = function(cli) invisible(NULL)
  )
  opts = stub_opts(run = "r0000000002")
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000004",
             messages = list(msg_user("Summarise x")),
             params = list(cli_mode = "edits", cli_budget = list(turns = 4)))
  spec = pcli_codex_build(stub_model("codex"), ctx, opts)
  dir = opts$state$codex_relay
  withr::defer(unlink(dir, recursive = TRUE))
  expect_true(dir.exists(dir))
  expect_identical(dir, path_norm(dir))
  if (!is_windows()) expect_identical(file.info(dir)$mode, as.octmode("700"))
  args = spec$start$args
  tail = c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", "gpt-6-sol",
           "-C", path_norm(getwd()), codex_relay_args(dir), "--sandbox", "read-only", "-")
  expect_identical(args[(length(args) - length(tail) + 1L):length(args)], tail)
  expect_identical(spec$start$env, character())
  expect_identical(spec$start$env_profile, "cli-codex")
  expect_true(spec$close_stdin)
  expect_s3_class(spec$send[[1]], "json")
  expect_match(spec$send[[1]], "Summarise x$")
  expect_identical(opts$state$codex_cap, 4L)
  opts$state$codex_thread = "0199a213-thread"
  spec2 = pcli_codex_build(stub_model("codex"), ctx, opts)
  withr::defer(unlink(opts$state$codex_relay, recursive = TRUE))
  expect_false(identical(opts$state$codex_relay, dir))
  i = match("exec", spec2$start$args)
  expect_identical(spec2$start$args[i + 0:2], c("exec", "resume", "0199a213-thread"))
  expect_identical(as.character(spec2$send[[1]]), "Summarise x")
  pcli_untrack("s0123456789")
})

# Write one request into a relay mailbox as the relay does, pump until the session answers;
# returns the answer's text, or NULL when none came within `timeout` seconds
relay_ask = function(dir, msg, allow_runs = NULL, timeout = 5) {
  resp = file.path(dir, "resp")
  write_utf8(file.path(dir, "req"), json_encode(msg))
  reactor_pump(until = function() file.exists(resp), allow_runs = allow_runs, timeout = timeout)
  if (!file.exists(resp)) return(NULL)
  out = read_utf8(resp)$text
  unlink(resp)
  out
}

test_that("the relay mailbox is answered in order; tools/call through the run's FIFO", {
  skip_on_cran()
  dir = withr::local_tempdir()
  opts = stub_opts(run = "r0000000009")
  opts$state$codex_relay = dir
  tasks = ls(reactor_get()$tasks)
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  init = relay_ask(dir, list(jsonrpc = "2.0", id = 1L, method = "initialize"))
  expect_identical(json_decode(init)$id, 1L)
  expect_identical(relay_ask(dir, list(jsonrpc = "2.0", method = "notifications/initialized")),
                   "\n")
  call = list(jsonrpc = "2.0", id = 3L, method = "tools/call",
              params = list(name = "r", arguments = list(code = "24")))
  # a pump that runs no FIFO tool of the run leaves the call queued, unanswered
  expect_null(relay_ask(dir, call, allow_runs = character(), timeout = 0.5))
  expect_false(file.exists(file.path(dir, "req")))
  expect_true(reactor_pump(until = function() file.exists(file.path(dir, "resp")), timeout = 5))
  res = json_decode(read_utf8(file.path(dir, "resp"))$text)
  expect_identical(res$id, 3L)
  expect_identical(res$result$content[[1L]]$text, "[1] 24")
  expect_identical(vapply(opts$log$dispatched, function(m) m$method, ""),
                   c("initialize", "notifications/initialized", "tools/call"))
  # the end of the turn removes the mailbox (the relay exits) and the task at once: the run's
  # last pump may return before the task polls again
  expect_true(push_obj(n, list(type = "turn.completed")))
  expect_false(dir.exists(dir))
  expect_length(setdiff(ls(reactor_get()$tasks), tasks), 0L)
})

test_that("a relayed tools/call whose turn ended is never evaluated (D-104)", {
  skip_on_cran()
  dir = withr::local_tempdir()
  opts = stub_opts(run = "r0000000010")
  opts$state$codex_relay = dir
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  call = list(jsonrpc = "2.0", id = 2L, method = "tools/call",
              params = list(name = "r", arguments = list(code = "x = 1")))
  expect_null(relay_ask(dir, call, allow_runs = character(), timeout = 0.5))
  expect_true(push_obj(n, list(type = "turn.completed")))
  expect_true(reactor_pump(until = function() {
    !dir.exists(dir) && !any(vapply(reactor_get()$fifo, function(i) i$run, "") == "r0000000010")
  }, timeout = 5))
  expect_length(opts$log$dispatched, 0L)
})

test_that("the relay script passes lines through its mailbox and exits when it should", {
  skip_on_cran()
  relay = system.file("gptr", "mcp_relay.R", package = "gptr", mustWork = TRUE)
  start = function(dir, seconds = 60, env = parent.frame()) {
    p = processx::process$new(rscript_path(), c("--vanilla", relay, dir, seconds),
                              stdin = "|", stdout = "|", stderr = "|", encoding = "UTF-8")
    withr::defer(p$kill(), envir = env)
    p
  }
  wait = function(cond, seconds = 20) {
    deadline = Sys.time() + seconds
    while (!isTRUE(cond()) && Sys.time() < deadline) Sys.sleep(0.02)
    isTRUE(cond())
  }
  dir = withr::local_tempdir()
  req = file.path(dir, "req")
  p = start(dir)
  note = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
  p$write_input(paste0(note, "\n"))
  expect_true(wait(function() file.exists(req)))
  expect_identical(read_utf8(req)$text, paste0(note, "\n"))
  unlink(req)
  write_utf8(file.path(dir, "resp"), "")
  ask = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"t\":\"caf\u00e9\"}}"
  p$write_input(paste0(ask, "\n"))
  expect_true(wait(function() file.exists(req)))
  expect_identical(read_utf8(req)$text, paste0(ask, "\n"))
  unlink(req)
  answer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"t\":\"caf\u00e9\"}}"
  write_utf8(file.path(dir, "resp"), answer)
  got = new.env()
  got$out = character()
  expect_true(wait(function() {
    got$out = c(got$out, p$read_output_lines())
    length(got$out) > 0L
  }))
  expect_identical(got$out, answer)
  # the end of stdin ends the relay
  close(p$get_input_connection())
  expect_true(wait(function() !p$is_alive()))
  expect_identical(p$get_exit_status(), 0L)
  # so does the removal of its mailbox while it waits for an answer
  dir2 = withr::local_tempdir()
  p2 = start(dir2)
  p2$write_input(paste0(ask, "\n"))
  expect_true(wait(function() file.exists(file.path(dir2, "req"))))
  unlink(dir2, recursive = TRUE)
  expect_true(wait(function() !p2$is_alive()))
  # and an answer that takes longer than its limit (an R session that died)
  dir3 = withr::local_tempdir()
  p3 = start(dir3, seconds = 1)
  p3$write_input(paste0(ask, "\n"))
  expect_true(wait(function() !p3$is_alive()))
  expect_true(file.exists(file.path(dir3, "req")))
})

test_that("the call-1 capture: informational tool events, the answer and the usage", {
  skip_on_cran()
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-call1.jsonl"))
  expect_identical(event_types(opts),
                   c("start", "tool_execution_start", "tool_execution_end", "text_start",
                     "text_delta", "text_end", "done"))
  expect_identical(opts$log$events[[2]]$tool_name, "codex_shell")
  expect_false(opts$log$events[[3]]$is_error)
  msg = n$message()
  expect_identical(msg_text(msg), "pong")
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$raw_stop_reason, "completed")
  expect_equal(c(msg$usage$input, msg$usage$cache_read, msg$usage$output), c(8336, 30208, 35))
  expect_identical(opts$state$codex_thread, "<UUID>")
})

test_that("a Codex shell step shows its command without the shell's -lc wrapper", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = TRUE)
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  shell = function(id, command) {
    push_obj(n, list(type = "item.started",
                     item = list(id = id, type = "command_execution", command = command,
                                 status = "in_progress")))
    ev = opts$log$events[[length(opts$log$events)]]
    console_tool_line(list(id = ev$tool_call_id, name = ev$tool_name, input = ev$input))
  }
  expect_identical(shell("i1", "/bin/zsh -lc 'wc -l mtcars_by_cyl.csv'"),
                   "  \u258e codex_shell  wc -l mtcars_by_cyl.csv")
  expect_identical(shell("i2", "/bin/sh -lc ls"), "  \u258e codex_shell  ls")
  expect_identical(shell("i6", "/bin/zsh -lc 'rg -n \"foo\" R/'"),
                   "  \u258e codex_shell  rg -n \"foo\" R/")
  # a double-quoted script keeps its wrapper
  expect_identical(shell("i3", "/bin/bash -lc \"echo 'hi'\""),
                   "  \u258e codex_shell  /bin/bash -lc \"echo 'hi'\"")
  expect_identical(shell("i7", "/bin/zsh -lc \"rg -n foo\\\\( R/\""),
                   "  \u258e codex_shell  /bin/zsh -lc \"rg -n foo\\\\( R/\"")
  expect_identical(shell("i8", "/bin/zsh -lc \"ls -la\""),
                   "  \u258e codex_shell  /bin/zsh -lc \"ls -la\"")
  # a command of several lines stays one JSON line, so no line is hidden
  expect_identical(shell("i4", "/bin/zsh -lc \"python - <<'PY'\nprint(1)\nPY\""),
                   paste0("  \u258e codex_shell  ",
                          "{\"command\":\"/bin/zsh -lc \\\"python - <<'PY'\\nprint(1)\\nPY\\\"\"}"))
  expect_identical(shell("i5", "/bin/zsh -lc 'set -e\nmake check'"),
                   "  \u258e codex_shell  {\"command\":\"set -e\\nmake check\"}")
})

test_that("Codex reports other servers' MCP calls, not gptr's own; reasoning is thinking", {
  skip_on_cran()
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-mcp.jsonl"))
  expect_false(any(startsWith(event_types(opts), "tool_execution")))
  opts1 = stub_opts()
  n1 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts1)
  push_obj(n1, list(type = "item.started",
                    item = list(id = "item_4", type = "mcp_tool_call", server = "docs",
                                tool = "search", arguments = list(q = "lm"),
                                status = "in_progress")))
  starts = Filter(function(e) identical(e$type, "tool_execution_start"), opts1$log$events)
  expect_identical(starts[[1]]$tool_name, "mcp__docs__search")
  expect_identical(starts[[1]]$input$q, "lm")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  feed_fixture(n2, "codex-text.jsonl")
  expect_identical(vapply(n2$message()$content, function(b) b$type, ""), c("thinking", "text"))
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  push_obj(n3, list(type = "item.completed", item = list(id = "r1", type = "reasoning",
                                                         text = "step 1 ")))
  push_obj(n3, list(type = "item.completed", item = list(id = "r2", type = "reasoning",
                                                         text = "")))
  deltas = Filter(function(e) identical(e$type, "thinking_delta"), opts3$log$events)
  expect_identical(vapply(deltas, function(e) e$delta, ""), "step 1\n")
})

test_that("Codex is stopped at the run's turn cap", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    invisible(TRUE)
  })
  opts = stub_opts()
  opts$state$codex_cap = 2L
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-many.jsonl"))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "max_turns")
  expect_match(ev$message$error_message, "turn cap of this run (2 tool steps)", fixed = TRUE)
  expect_identical(stopped$n, 1L)
})

test_that("turn.failed, a missing turn.completed and the wall clock end the exec", {
  skip_on_cran()
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  push_obj(n, list(type = "turn.started"))
  push_obj(n, list(type = "turn.failed", error = list(message = "usage limit reached")))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$error$class, "provider")
  expect_match(ev$message$error_message, "usage limit reached", fixed = TRUE)
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  feed_fixture(n2, "codex-hang.jsonl")
  expect_match(n2$finish()$error_message, "exited before completing the turn", fixed = TRUE)
  local_gptr_options(cli_turn_timeout = 0.3)
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    invisible(TRUE)
  })
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  expect_true(reactor_pump(until = function() length(opts3$log$events) > 0L, timeout = 5))
  ev3 = opts3$log$events[[length(opts3$log$events)]]
  expect_identical(ev3$error$class, "timeout")
  expect_match(ev3$message$error_message, "out of budget", fixed = TRUE)
})

test_that("a Codex error event is noted, not terminal; turn.failed and the exit report it", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  push_obj(n, list(type = "turn.started"))
  expect_false(push_obj(n, list(type = "error", message = "Reconnecting... 1/5")))
  push_obj(n, list(type = "item.completed",
                   item = list(id = "item_1", type = "agent_message", text = "ok")))
  expect_true(push_obj(n, list(type = "turn.completed", usage = list(input_tokens = 5L))))
  expect_identical(event_types(opts)[length(opts$log$events)], "done")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  push_obj(n2, list(type = "error", message = "stream disconnected"))
  expect_match(n2$finish()$error_message, "Its last error: stream disconnected", fixed = TRUE)
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  push_obj(n3, list(type = "error", message = "usage limit reached"))
  expect_true(push_obj(n3, list(type = "turn.failed", error = json_obj())))
  expect_match(n3$message()$error_message, "Codex reported an error: usage limit reached",
               fixed = TRUE)
})

test_that("a workspace-write exec that changes control files is reported after it ends", {
  skip_on_cran()
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  opts = stub_opts()
  opts$state$codex_sandbox = "workspace-write"
  opts$state$codex_control = pcli_control_hash(root)
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  writeLines('{"permissions": {"allow": ["r(*)"]}}', file.path(root, ".gptr", "settings.json"))
  seen = new.env()
  seen$events = NA_integer_
  withCallingHandlers(feed_fixture(n, "codex-text.jsonl"),
                      gptr_warning_cli_sandbox = function(w) {
                        seen$events = length(opts$log$events)
                        seen$text = conditionMessage(w)
                        invokeRestart("muffleWarning")
                      })
  expect_match(seen$text, ".gptr/settings.json", fixed = TRUE)
  expect_identical(event_types(opts)[[seen$events]], "done")
  expect_length(opts$log$events, seen$events)
  expect_null(opts$state$codex_control)
})

# ---- reconciliations with the contract, IC-74 and the shared helpers (Task 7, D-106) -----------

test_that("turn.completed usage Codex left out stays unknown, and its cost is unknown (IC-74)", {
  skip_on_cran()
  full = pcli_codex_usage(list(input_tokens = 38544L, cached_input_tokens = 30208L,
                               cache_write_input_tokens = 0L, output_tokens = 35L,
                               reasoning_output_tokens = 0L))
  expect_equal(c(full$input, full$cache_read, full$cache_write_5m, full$cache_write_1h,
                 full$output, full$reasoning, full$total), c(8336, 30208, 0, 0, 35, 0, 38579))
  expect_true(all(is.na(unlist(full$cost))))
  expect_false(full$estimated)
  part = pcli_codex_usage(list(input_tokens = 5L, output_tokens = 2L))
  expect_equal(part$output, 2)
  expect_true(all(is.na(c(part$input, part$cache_read, part$cache_write_5m,
                          part$cache_write_1h, part$reasoning, part$total))))
  odd = pcli_codex_usage(list(input_tokens = "many", cached_input_tokens = -1,
                              output_tokens = c(1, 2)))
  expect_true(all(is.na(c(odd$input, odd$cache_read, odd$output))))
  # more cached than input tokens: the uncached part is unknown, never a clamped zero
  inverted = pcli_codex_usage(list(input_tokens = 5L, cached_input_tokens = 9L,
                                   cache_write_input_tokens = 0L))
  expect_true(is.na(inverted$input))
  expect_true(is.na(pcli_codex_usage("lots")$input))
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-call1.jsonl"))
  done = opts$log$events[[length(opts$log$events)]]
  expect_identical(done$usage, n$message()$usage)
  expect_true(is.na(done$usage$cost$total))
  for (usage in list(NULL, "lots")) {
    o = stub_opts()
    nn = local_normaliser(pcli_codex_parse, stub_model("codex"), o)
    expect_true(push_obj(nn, list(type = "turn.completed", usage = usage)))
    u = nn$message()$usage
    expect_identical(event_types(o), c("start", "done"))
    expect_true(all(is.na(c(u$input, u$output, u$total, u$cost$total))))
  }
})

test_that("a resumed thread's turn.completed counts its increase; a new thread counts whole", {
  opts = stub_opts()
  exec = function(thread, input, cached, output) {
    n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
    push_obj(n, list(type = "thread.started", thread_id = thread))
    push_obj(n, list(type = "turn.completed",
                     usage = list(input_tokens = input, cached_input_tokens = cached,
                                  cache_write_input_tokens = 0L, output_tokens = output,
                                  reasoning_output_tokens = 0L)))
    u = n$message()$usage
    c(u$input, u$cache_read, u$cache_write_5m, u$output, u$reasoning)
  }
  expect_equal(exec("thread-a", 17106L, 12160L, 5L), c(4946, 12160, 0, 5, 0))
  expect_equal(exec("thread-a", 34231L, 29056L, 10L), c(229, 16896, 0, 5, 0))
  expect_equal(exec("thread-b", 17106L, 12160L, 5L), c(4946, 12160, 0, 5, 0))
  # a running total that went down gives an unknown increase, never a negative count (IC-74)
  expect_equal(exec("thread-b", 17106L, 12000L, 9L), c(NA, NA, 0, 4, 0))
})

test_that("a turn budget that is not finite or very large still gives a whole-number cap", {
  skip_on_cran()
  expect_identical(pcli_codex_cap(list(turns = Inf)), 50L)
  expect_identical(pcli_codex_cap(list(turns = 3e9)), .Machine$integer.max)
  expect_identical(pcli_codex_cap(list(turns = 2.7)), 2L)
  expect_identical(pcli_codex_cap(list(turns = 0.4)), 1L)
  expect_identical(pcli_codex_cap(list()), 50L)
  local_gptr_options(max_turns = 12)
  expect_identical(pcli_codex_cap(list()), 12L)
  local_gptr_options(max_turns = Inf)
  expect_identical(pcli_codex_cap(list()), .Machine$integer.max)
  local_gptr_options(max_turns = "many")
  expect_identical(pcli_codex_cap(list()), 50L)
})

test_that("the wall clock of an aborted run ends the exec as aborted and stops it", {
  skip_on_cran()
  local_gptr_options(cli_turn_timeout = 0.3)
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    stopped$wait = wait_ack
    invisible(TRUE)
  })
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  opts$signal$aborted = TRUE
  expect_true(reactor_pump(until = function() length(opts$log$events) > 0L, timeout = 2))
  expect_identical(event_types(opts), c("start", "error"))
  expect_identical(opts$log$events[[2]]$reason, "aborted")
  expect_identical(opts$log$events[[2]]$error$class, "aborted")
  expect_identical(n$finish()$stop_reason, "aborted")
  expect_null(opts$state$turn_timer)
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
  # a line that reaches the normaliser of an aborted run ends the exec the same way
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  opts2$signal$aborted = TRUE
  expect_true(push_obj(n2, list(type = "turn.started")))
  expect_identical(opts2$log$events[[2]]$error$class, "aborted")
  expect_identical(stopped$n, 2L)
})

test_that("a late wall clock of an earlier exec leaves the session's next exec alone", {
  skip_on_cran()
  timers = new.env()
  timers$fns = list()
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(
    reactor_timer = function(at, fn, run = NULL) {
      timers$fns[[length(timers$fns) + 1L]] = fn
      paste0("x", length(timers$fns))
    },
    pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
      stopped$n = stopped$n + 1L
      invisible(TRUE)
    }
  )
  opts1 = stub_opts()
  pcli_codex_parse(stub_model("codex"), opts1)
  # P05 lets go of exec 1 without its normaliser; exec 2 of the session shares its state
  opts2 = stub_opts()
  opts2$state = opts1$state
  pcli_codex_parse(stub_model("codex"), opts2)
  timers$fns[[1]]()
  expect_length(opts1$log$events, 0L)
  expect_identical(stopped$n, 0L)
  expect_true(opts2$state$turn_open)
  expect_identical(opts2$state$turn_timer, "x2")
  # exec 2's own wall clock still ends exec 2 and stops it
  timers$fns[[2]]()
  expect_identical(event_types(opts2), c("start", "error"))
  expect_identical(opts2$log$events[[2]]$error$class, "timeout")
  expect_identical(stopped$n, 1L)
})

test_that("an R error inside the codex normaliser ends the exec with one error event (8.1)", {
  skip_on_cran()
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_codex_event = function(obj, s) stop("boom"),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          stopped$n = stopped$n + 1L
                          stopped$wait = wait_ack
                          invisible(TRUE)
                        })
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(push_obj(n, list(type = "turn.started")))
  expect_identical(event_types(opts), c("start", "error"))
  ev = opts$log$events[[2]]
  expect_identical(ev$error$class, "internal")
  expect_match(ev$message$error_message, "boom", fixed = TRUE)
  expect_identical(n$finish(), ev$message)
  # Codex may still be working on the turn: the exec is stopped
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
  local_mocked_bindings(pcli_aborted = function(s) stop("disk gone"))
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  expect_match(n2$finish()$error_message, "disk gone", fixed = TRUE)
  expect_identical(opts2$log$events[[2]]$error$class, "internal")
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  expect_match(n3$fail(simpleError("pipe closed"))$error_message, "disk gone", fixed = TRUE)
  expect_identical(event_types(opts3), c("start", "error"))
})

test_that("malformed Codex events are ignored or read as unknown, never an R error", {
  skip_on_cran()
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_false(push_obj(n, list(type = "thread.started", thread_id = list("t"))))
  expect_null(opts$state$codex_thread)
  expect_false(push_obj(n, list(type = "item.completed", item = "oops")))
  expect_false(push_obj(n, list(type = "item.started", item = list(id = 1L, type = 5L))))
  change = list(id = "item_1", type = "file_change", status = "completed",
                changes = list(list(path = 7L), "x", list(path = "R/a.R")))
  expect_false(push_obj(n, list(type = "item.completed", item = change)))
  expect_false(push_obj(n, list(type = "error", error = "flaky")))
  expect_true(push_obj(n, list(type = "turn.failed", error = "boom")))
  expect_identical(event_types(opts),
                   c("start", "tool_execution_start", "tool_execution_end", "error"))
  expect_identical(as.character(opts$log$events[[2]]$input$paths), "R/a.R")
  expect_identical(as.character(opts$log$events[[3]]$details$files), "R/a.R")
  last = opts$log$events[[4]]
  expect_identical(last$error$class, "provider")
  expect_match(last$message$error_message, "Codex reported an error: boom", fixed = TRUE)
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  expect_false(push_obj(n2, list(type = "error", error = list(message = "flaky"))))
  expect_true(push_obj(n2, list(type = "turn.failed", error = list(message = 5L))))
  expect_match(n2$message()$error_message, "Codex reported an error: flaky", fixed = TRUE)
})

test_that("the Windows sandbox probe caches answers and timeouts, never a run that did not start", {
  skip_on_cran()
  runs = new.env()
  runs$args = list()
  runs$queue = list("error", list(status = NA_integer_, timed_out = FALSE),
                    list(status = 0L, timed_out = FALSE))
  local_mocked_bindings(pcli_run = function(cmd, args, timeout = 30) {
    runs$args[[length(runs$args) + 1L]] = args
    runs$timeout = timeout
    res = runs$queue[[1L]]
    runs$queue = runs$queue[-1L]
    if (identical(res, "error")) stop("could not start")
    res
  })
  cmd = file.path(tempdir(), "no-such-codex")
  withr::defer(pcli_version_forget(cmd))
  # a run that could not start or ended without an exit status is asked again at the next exec
  expect_false(pcli_codex_windows_ready(cmd))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_true(pcli_codex_windows_ready(cmd))
  expect_true(pcli_codex_windows_ready(cmd))
  expect_length(runs$args, 3L)
  expect_identical(runs$args[[1]], c("sandbox", "windows", "cmd.exe", "/d", "/c", "exit", "0"))
  expect_identical(runs$timeout, 60)
  # gptr_providers(check = TRUE) forgets the answer with the probe, so it is asked again
  pcli_version_forget(cmd)
  runs$queue = list(list(status = 1L, timed_out = FALSE))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_length(runs$args, 4L)
  # a probe that timed out is not run again before the next check: every auto-mode exec
  # would otherwise wait the 60 s timeout in build()
  pcli_version_forget(cmd)
  runs$queue = list(list(status = NA_integer_, timed_out = TRUE))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_false(pcli_codex_windows_ready(cmd))
  expect_length(runs$args, 5L)
})

# ---- review round 1: control files, the wall clock and the order of a stop (Task 7, D-106) ------

test_that("control files gptr cannot hash are kept by a marker, so an auto exec still runs", {
  skip_on_cran()
  codex_capability_local()
  root = local_project(files = list(".gptr/settings.json" = "{}", ".git/hooks/pre-push" = "x",
    "capability-canary.txt" = "untouched sentinel"))
  codex_capability_preserve(file.path(root, "capability-canary.txt"))
  hook = file.path(root, ".git", "hooks", "pre-commit")
  link = codex_capability_link(hook, root)
  link$make(file.path(root, "gone-1.sh"))
  # Keep the real platform's observed readlink result; the fake CLI does not alter the filesystem.
  readable = nzchar(pcli_control_link(hook))
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL))
  withr::defer(pcli_untrack("s0123456789"))
  opts = stub_opts()
  ctx = list(messages = list(msg_user("hi")), params = list(cli_mode = "auto"))
  spec = pcli_codex_build(stub_model("codex"), ctx, opts)
  args = spec$start$args
  expect_identical(args[[match("--sandbox", args) + 1L]], "workspace-write")
  before = opts$state$codex_control
  marker = before[[path_norm(hook)]]
  if (readable) {
    expect_identical(marker, paste0("link:", file.path(root, "gone-1.sh")))
  } else {
    expect_match(marker, "^unreadable")
  }
  expect_true(path_norm(file.path(root, ".git", "hooks", "pre-push")) %in% names(before))
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_no_warning(expect_true(feed_fixture(n, "codex-text.jsonl")))
  expect_identical(event_types(opts)[[length(opts$log$events)]], "done")
})

test_that("retargeting a dangling control link warns after the Codex exec completes", {
  skip_on_cran()
  codex_capability_local()
  root = local_project(files = list(".gptr/settings.json" = "{}", ".git/hooks/pre-push" = "x",
    "capability-canary.txt" = "untouched sentinel"))
  codex_capability_preserve(file.path(root, "capability-canary.txt"))
  hook = file.path(root, ".git", "hooks", "pre-commit")
  link = codex_capability_link(hook, root)
  first = link$make(file.path(root, "gone-1.sh"))
  opts2 = stub_opts()
  opts2$state$codex_sandbox = "workspace-write"
  opts2$state$codex_control = pcli_control_hash(root)
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  link$detach()
  second = link$make(file.path(root, "gone-2.sh"))
  expect_false(identical(first, second), info = "actual native link payload changed")
  expect_identical(pcli_control_changed(opts2$state$codex_control, pcli_control_hash(root)),
    path_norm(hook))
  seen = new.env(parent = emptyenv())
  seen$last = NULL
  w = expect_warning(withCallingHandlers(feed_fixture(n2, "codex-text.jsonl"),
    gptr_warning_cli_sandbox = function(w) {
      seen$last = tail(event_types(opts2), 1L)
    }), class = "gptr_warning_cli_sandbox")
  warning_text = if (inherits(w, "condition")) conditionMessage(w) else ""
  expect_match(warning_text, ".git/hooks/pre-commit", fixed = TRUE)
  expect_identical(seen$last, "done")
  expect_identical(event_types(opts2)[[length(opts2$log$events)]], "done")
})

test_that("a control file gptr cannot read is marked by its size and time instead", {
  skip_on_cran()
  codex_capability_local()
  root = local_project(files = list(".gptr/agents/locked.md" = "secret agent",
    "capability-canary.txt" = "untouched sentinel"))
  codex_capability_preserve(file.path(root, "capability-canary.txt"))
  locked = file.path(root, ".gptr", "agents", "locked.md")
  access = codex_capability_deny_read(locked, root)
  h = pcli_control_hash(root)
  expect_match(h[[path_norm(locked)]], "^unreadable:[0-9]+ [0-9.]+$")
  before_size = file.info(locked, extra_cols = FALSE)$size
  access$set_expected(c(access$bytes, charToRaw("a longer secret agent\n")))
  connection = file(locked, open = "ab")
  tryCatch(writeBin(charToRaw("a longer secret agent\n"), connection),
    finally = close(connection))
  expect_gt(file.info(locked, extra_cols = FALSE)$size, before_size)
  expect_identical(pcli_control_changed(h, pcli_control_hash(root)), path_norm(locked))
  access$restore()
})

test_that("a control-file check that fails still completes the exec, then warns", {
  skip_on_cran()
  local_project(files = list(".gptr/settings.json" = "{}"))
  opts = stub_opts()
  opts$state$codex_sandbox = "workspace-write"
  opts$state$codex_control = c("/p/.gptr/settings.json" = "h")
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  local_mocked_bindings(pcli_control_hash = function(root = project_root()) stop("disk gone"))
  seen = new.env()
  seen$events = NA_integer_
  withCallingHandlers(expect_true(feed_fixture(n, "codex-text.jsonl")),
                      gptr_warning_cli_sandbox = function(w) {
                        seen$events = length(opts$log$events)
                        seen$text = conditionMessage(w)
                        invokeRestart("muffleWarning")
                      })
  expect_identical(event_types(opts)[[seen$events]], "done")
  expect_length(opts$log$events, seen$events)
  expect_match(seen$text, "could not check its control files", fixed = TRUE)
  expect_match(seen$text, "disk gone", fixed = TRUE)
  expect_null(opts$state$codex_control)
})

test_that("the wall clock ends the exec and stops Codex even when its own work fails", {
  skip_on_cran()
  timers = new.env()
  timers$fns = list()
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(
    reactor_timer = function(at, fn, run = NULL) {
      timers$fns[[length(timers$fns) + 1L]] = fn
      paste0("x", length(timers$fns))
    },
    pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
      stopped$n = stopped$n + 1L
      stopped$wait = wait_ack
      invisible(TRUE)
    },
    pcli_control_hash = function(root = project_root()) stop("disk gone")
  )
  local_project()
  opts = stub_opts()
  opts$state$codex_sandbox = "workspace-write"
  opts$state$codex_control = c("/p/.gptr/settings.json" = "h")
  pcli_codex_parse(stub_model("codex"), opts)
  w = expect_warning(timers$fns[[1]](), class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), "disk gone", fixed = TRUE)
  expect_identical(event_types(opts), c("start", "error"))
  expect_identical(opts$log$events[[2]]$error$class, "timeout")
  expect_identical(stopped$n, 1L)
  # any other R error in the wall clock gives the one terminal event and stops Codex (8.1)
  local_mocked_bindings(pcli_codex_timeout = function(s) stop("boom"))
  opts2 = stub_opts()
  n2 = pcli_codex_parse(stub_model("codex"), opts2)
  expect_no_error(timers$fns[[2]]())
  expect_identical(event_types(opts2), c("start", "error"))
  ev = opts2$log$events[[2]]
  expect_identical(ev$error$class, "internal")
  expect_match(ev$message$error_message, "boom", fixed = TRUE)
  expect_identical(n2$finish(), ev$message)
  expect_identical(stopped$n, 2L)
  expect_false(stopped$wait)
  expect_null(opts2$state$turn_timer)
})

test_that("an exec gptr stops is stopped before its control files are checked", {
  skip_on_cran()
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  seen = new.env()
  opts = stub_opts()
  # Codex edits a control file while gptr stops it at the turn cap
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    seen$events = length(opts$log$events)
    writeLines('{"permissions": {"allow": ["r(*)"]}}', file.path(root, ".gptr", "settings.json"))
    invisible(TRUE)
  })
  opts$state$codex_sandbox = "workspace-write"
  opts$state$codex_control = pcli_control_hash(root)
  opts$state$codex_cap = 2L
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  w = expect_warning(expect_true(feed_fixture(n, "codex-many.jsonl")),
                     class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), ".gptr/settings.json", fixed = TRUE)
  last = opts$log$events[[length(opts$log$events)]]
  expect_identical(last$error$class, "max_turns")
  # stopped before the terminal event, so P06's done callback finds no running Codex
  expect_lt(seen$events, length(opts$log$events))
})

# ---- review round 2: execs that end without the normaliser's own end (Task 7, D-106) -----------

test_that("a workspace-write exec P05 ends without its normaliser is checked at the next build", {
  skip_on_cran()
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  settings = file.path(root, ".gptr", "settings.json")
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL))
  withr::defer(pcli_untrack("s0123456789"))
  auto = list(messages = list(msg_user("hi")), params = list(cli_mode = "auto"))
  edits = list(messages = list(msg_user("next")), params = list(cli_mode = "edits"))
  opts = stub_opts()
  expect_no_warning(pcli_codex_build(stub_model("codex"), auto, opts))
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_false(push_obj(n, list(type = "turn.started")))
  # Codex edits a control file, then P05 ends the exec without the normaliser (stream_abort()
  # after Ctrl-C, stream_detach() of a settled run) and the session's next prompt builds
  writeLines('{"permissions": {"allow": ["r(*)"]}}', settings)
  opts2 = stub_opts()
  opts2$state = opts$state
  w = expect_warning(pcli_codex_build(stub_model("codex"), edits, opts2),
                     class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), ".gptr/settings.json", fixed = TRUE)
  expect_match(conditionMessage(w), "earlier workspace-write turn", fixed = TRUE)
  expect_identical(opts2$state$codex_sandbox, "read-only")
  expect_null(opts2$state$codex_control)
  # each exec is checked once
  expect_no_warning(pcli_codex_build(stub_model("codex"), edits, opts2))
  # an auto exec after the check takes its own baseline: the earlier edit is not reported again
  opts3 = stub_opts()
  opts3$state = opts$state
  expect_no_warning(pcli_codex_build(stub_model("codex"), auto, opts3))
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  expect_no_warning(expect_true(feed_fixture(n3, "codex-text.jsonl")))
  expect_identical(event_types(opts3)[[length(opts3$log$events)]], "done")
  expect_null(opts3$state$codex_control)
})

test_that("the deferred control-file check hashes the project the exec ran in", {
  skip_on_cran()
  a = local_project(files = list(".gptr/settings.json" = "{}"))
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL))
  withr::defer(pcli_untrack("s0123456789"))
  auto = list(messages = list(msg_user("hi")), params = list(cli_mode = "auto"))
  edits = list(messages = list(msg_user("next")), params = list(cli_mode = "edits"))
  opts = stub_opts()
  pcli_codex_build(stub_model("codex"), auto, opts)
  writeLines('{"permissions": {"allow": ["r(*)"]}}', file.path(a, ".gptr", "settings.json"))
  # the session's next prompt runs in another project, whose own control files are no change
  b = local_project(files = list(".gptr/mcp.json" = "{}"))
  w = expect_warning(pcli_codex_build(stub_model("codex"), edits, opts),
                     class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), ".gptr/settings.json", fixed = TRUE)
  expect_false(grepl("mcp.json", conditionMessage(w), fixed = TRUE))
  expect_no_warning(pcli_codex_build(stub_model("codex"), auto, opts))
  withr::local_dir(a)
  withr::local_options(gptr.project_root = a)
  expect_no_warning(pcli_codex_build(stub_model("codex"), edits, opts))
  expect_null(opts$state$codex_control)
})

test_that("an exec that ends in an internal error has its control files checked, then warns", {
  skip_on_cran()
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  settings = file.path(root, ".gptr", "settings.json")
  timers = new.env()
  timers$fns = list()
  seen = new.env()
  seen$stops = 0L
  local_mocked_bindings(
    reactor_timer = function(at, fn, run = NULL) {
      timers$fns[[length(timers$fns) + 1L]] = fn
      paste0("x", length(timers$fns))
    },
    # Codex writes a control file while gptr stops it
    pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
      seen$stops = seen$stops + 1L
      writeLines(paste0('{"stop": ', seen$stops, "}"), settings)
      invisible(TRUE)
    },
    pcli_codex_item = function(s, item) stop("boom"),
    pcli_codex_timeout = function(s) stop("boom")
  )
  auto_opts = function() {
    o = stub_opts()
    o$state$codex_sandbox = "workspace-write"
    o$state$codex_control = pcli_control_hash(root)
    o
  }
  catch = function(code, opts) {
    seen$at = NA_integer_
    seen$text = NULL
    withCallingHandlers(code, gptr_warning_cli_sandbox = function(w) {
      seen$at = length(opts$log$events)
      seen$text = conditionMessage(w)
      invokeRestart("muffleWarning")
    })
  }
  item = list(id = "item_0", type = "agent_message", text = "x")
  # an R error in push(): Codex is stopped, checked, the internal event emitted, then the warning
  opts = auto_opts()
  n = pcli_codex_parse(stub_model("codex"), opts)
  catch(expect_true(push_obj(n, list(type = "item.completed", item = item))), opts)
  expect_identical(event_types(opts), c("start", "error"))
  expect_identical(opts$log$events[[2]]$error$class, "internal")
  expect_identical(seen$at, 2L)
  expect_match(seen$text, ".gptr/settings.json", fixed = TRUE)
  expect_null(opts$state$codex_control)
  expect_identical(seen$stops, 1L)
  # an R error in the wall clock: the same
  opts2 = auto_opts()
  pcli_codex_parse(stub_model("codex"), opts2)
  catch(timers$fns[[2]](), opts2)
  expect_identical(event_types(opts2), c("start", "error"))
  expect_identical(opts2$log$events[[2]]$error$class, "internal")
  expect_identical(seen$at, 2L)
  expect_match(seen$text, ".gptr/settings.json", fixed = TRUE)
  expect_null(opts2$state$codex_control)
  expect_identical(seen$stops, 2L)
  # an R error at the end of input (Codex has exited): checked and reported as well
  opts3 = auto_opts()
  n3 = pcli_codex_parse(stub_model("codex"), opts3)
  writeLines('{"exit": true}', settings)
  local_mocked_bindings(pcli_aborted = function(s) stop("boom"))
  catch(n3$finish(), opts3)
  expect_identical(event_types(opts3), c("start", "error"))
  expect_identical(opts3$log$events[[2]]$error$class, "internal")
  expect_identical(seen$at, 2L)
  expect_match(seen$text, ".gptr/settings.json", fixed = TRUE)
  expect_null(opts3$state$codex_control)
})

# ---- the codex route end to end, the CLI leg of INFRA-16 (Task 10) ------------------------------

# The relay mailbox named in a codex argv
codex_argv_relay = function(argv) {
  args = sub("^mcp_servers[.]gptr[.]args=", "", grep("^mcp_servers[.]gptr[.]args=", argv,
                                                     value = TRUE))
  json_decode(args)[[3L]]
}

test_that("a codex turn: exact argv, a 200 KB prompt on stdin intact, no token in env", {
  skip_on_cran()
  local_vault()
  local_gptr_options(quiet = FALSE)
  f = local_fake_cli("codex", "text")
  withr::local_envvar(OPENAI_API_KEY = "sk-p20fake-openai-0000000000000000",
                      CODEX_API_KEY = "codex-p20fake-0000000000000",
                      OPENAI_BASE_URL = "https://example.invalid/v1", CODEX_SANDBOX = "seatbelt")
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  big = paste0("Summarise this text: ", strrep("abcdefghij", 20000L), " caf\u00e9.")
  seen = new.env()
  seen$vars = character()
  s = withCallingHandlers(
    peter(prompt = big, model = f$model, envir = new.env(), mode = "edits"),
    gptr_message_billing_env = function(w) {
      seen$vars = c(seen$vars, w$variables)
      invokeRestart("muffleMessage")
    })
  argv = fake_argv(f)[[1]]
  expect_identical(argv,
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", path_norm(getwd()),
                     codex_relay_args(codex_argv_relay(argv)), "--sandbox", "read-only", "-"))
  bytes = fake_prompts(f)[[1]]
  prompt = rawToChar(bytes)
  Encoding(prompt) = "UTF-8"
  expect_gt(length(bytes), 200000L)
  expect_true(grepl(big, prompt, fixed = TRUE, useBytes = TRUE))
  expect_match(prompt, "^<gptr_instructions>\n")
  env = fake_env_names(f)[[1]]
  expect_false("GPTR_MCP_TOKEN" %in% env)
  expect_false(any(c("OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "CODEX_SANDBOX") %in%
                     env))
  expect_true(all(c("OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL") %in% seen$vars))
  expect_false("CODEX_SANDBOX" %in% seen$vars)
  expect_identical(s$text, paste0("Hello from the fake codex CLI (", length(bytes),
                                  " prompt bytes)."))
  m = s$messages[[length(s$messages)]]
  expect_identical(m$route, "plan-cli")
  expect_equal(m$usage$cache_read, 24448)
})

test_that("the codex turn's fake keys do not stay registered in the process vault", {
  expect_false(any(c("OPENAI_API_KEY", "CODEX_API_KEY") %in% secret_registered_names()))
})

test_that("the next turn resumes the Codex thread with -c sandbox_mode=", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  s = peter("First", model = f$model, envir = new.env(), mode = "auto")
  s |> peter("Second")
  argv = fake_argv(f)
  expect_length(argv, 2L)
  expect_identical(argv[[1]][match("--sandbox", argv[[1]]) + 1L], "workspace-write")
  expect_identical(argv[[2]][1:3], c("exec", "resume", "00000000-0000-4000-8000-000000000001"))
  expect_true("sandbox_mode=workspace-write" %in% argv[[2]])
  expect_false(any(c("-C", "--sandbox") %in% argv[[2]]))
  second = rawToChar(fake_prompts(f)[[2]])
  expect_false(grepl("<gptr_instructions>", second, fixed = TRUE))
  expect_match(second, "Second\n$")
})

test_that("after a rewind the next turn starts a fresh Codex thread with the remaining path", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  s = peter("First", model = f$model, envir = new.env(), mode = "auto")
  s |> peter("Quick one: add a logical column flag = TRUE to top5")
  gptr_rewind(s)
  s |> peter("Again")
  argv = fake_argv(f)
  expect_length(argv, 3L)
  expect_identical(argv[[2]][1:2], c("exec", "resume"))
  expect_false("resume" %in% argv[[3]])
  third = rawToChar(fake_prompts(f)[[3]])
  expect_match(third, "^<gptr_instructions>\n")
  expect_match(third, "First", fixed = TRUE)
  expect_false(grepl("flag = TRUE", third, fixed = TRUE))
  expect_match(third, "Again\n$")
  expect_equal(s$messages[[length(s$messages)]]$usage$cache_read, 24448)
})

test_that("without httpuv, later and openssl a fake codex evaluates R in the live session", {
  skip_on_cran()
  local_gptr_options(quiet = FALSE)
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  local_mocked_bindings(mcp_serve_start = function(port = NULL) {
    stop("The MCP server needs the 'httpuv' package.")
  })
  f = local_fake_cli("codex", "mcp")
  e = new.env()
  seen = new.env()
  seen$text = character()
  s = withCallingHandlers(
    peter("Compute the sum of 1 to 10 in R", model = f$model, envir = e, mode = "auto"),
    gptr_message = function(m) {
      seen$text = c(seen$text, conditionMessage(m))
      invokeRestart("muffleMessage")
    })
  expect_identical(e$live_answer, 55L)
  expect_match(s$text, "55", fixed = TRUE)
  expect_false(any(grepl("files only", seen$text, fixed = TRUE)))
  expect_false("GPTR_MCP_TOKEN" %in% fake_env_names(f)[[1L]])
  # Codex is served the session's frozen tools, the array an API provider gets (IC-79); the
  # relay ends with Codex's stdin and the session removes the mailbox after the turn
  mcp = fake_log(f, "mcp")[[1L]]
  expect_identical(as.character(unlist(mcp$tools)), session_data(s)$frozen$tool_names)
  expect_identical(mcp$status, 0L)
  dir = codex_argv_relay(fake_argv(f)[[1L]])
  expect_true(reactor_pump(until = function() !dir.exists(dir), timeout = 5))
  # the relayed call is checkpointed, so a rewind removes what it made (#24)
  expect_identical(gptr_checkpoints(s)$objects, "1/1")
  gptr_rewind(s, 0)
  expect_false(exists("live_answer", envir = e, inherits = FALSE))
})

test_that("a fake codex returns a function's numeric result through the stdio relay", {
  skip_on_cran()
  f = local_fake_cli("codex", "mcp-return")
  fit_in_session = function(data) {
    work = new.env(parent = baseenv())
    work$dat = data
    s = peter("Fit mpg on wt and hp, then return its coefficients with gptr_return().",
              model = f$model, envir = work, mode = "auto", .opts = list(record = FALSE))
    list(session = s, fit = work$fit, beta = work$beta)
  }
  answer = fit_in_session(datasets::mtcars)
  expected = stats::coef(stats::lm(mpg ~ wt + hp, data = datasets::mtcars))
  expect_s3_class(answer$fit, "lm")
  expect_equal(answer$beta, expected)
  expect_equal(answer$session$value, expected)
  expect_identical(fake_log(f, "mcp")[[1L]]$status, 0L)
  expect_null(run_current())
})

test_that("a codex turn shows its reasoning and tool steps at the console as they run (D-192)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 200, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  f = local_fake_cli("codex", "progress")
  e = new.env()
  out = utils::capture.output(peter("How many files are there?", model = f$model, envir = e,
                                    mode = "auto"))
  at = match(c("  Listing the files", "  | codex_shell  ls",
               "  | r  n_files = 1L", "There is one file."), out)
  expect_false(anyNA(at))
  expect_false(is.unsorted(at))
  expect_false(any(grepl("directory listing", out, fixed = TRUE)))
  expect_identical(sum(grepl("n_files = 1L", out, fixed = TRUE)), 1L)
  expect_identical(e$n_files, 1L)
})

test_that("a Codex message shows whole once it completes, a blank line from the next (#41)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  f = local_fake_cli("codex", "messages")
  seen = new.env()
  seen$log = character()
  event = pcli_codex_event
  write = console_cat
  local_mocked_bindings(
    console_pad = function() "  ",
    pcli_codex_event = function(obj, s) {
      seen$log = c(seen$log, paste0("<", obj[["type"]], ">"))
      event(obj, s)
    },
    console_cat = function(text) {
      seen$log = c(seen$log, text)
      write(text)
    })
  out = utils::capture.output({
    s = peter("How many files are there?", model = f$model, envir = new.env())
  })
  # the last word is on screen before Codex's next event, not held until it
  expect_lt(which(grepl("files.", seen$log, fixed = TRUE))[[1L]],
            match("<item.started>", seen$log))
  at = match("  | codex_shell  ls", out)
  expect_identical(out[at + 1:4], c("", "  There is one file.", "", "  It is a.txt."))
  expect_identical(s$text, "I will list the files.\nThere is one file.\nIt is a.txt.")
})

test_that("a Codex step leaves the control exports to the user; a served call does not (IC-53)", {
  skip_on_cran()
  f = local_fake_cli("codex", "progress")
  seen = new.env()
  off = gptr_register(gptr_hook("tool_execution_start", function(event, ctx) {
    seen[[event$tool_name]] = tryCatch({
      ext_control_guard("gptr_register")
      "passed"
    }, gptr_error_permission = function(e) "refused")
    NULL
  }))
  withr::defer(off())
  peter("How many files are there?", model = f$model, envir = new.env(), mode = "auto")
  expect_identical(seen$codex_shell, "passed")
  expect_identical(seen$r, "refused")
})

test_that("the first CLI turn probes the CLI before its waiting row starts (D-192)", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_gptr_options(verbose = 2L)
  f = local_fake_cli("codex", "text")
  seen = new.env()
  seen$log = character()
  probe = pcli_probe
  local_mocked_bindings(
    pcli_probe = function(path) {
      res = probe(path)
      seen$log = c(seen$log, "probe")
      res
    },
    console_wait_start = function(rec) {
      seen$log = c(seen$log, "wait")
      invisible(NULL)
    })
  utils::capture.output(peter("Hello", model = f$model, envir = new.env()))
  expect_identical(seen$log[[1L]], "probe")
  expect_true("wait" %in% seen$log)
})

test_that("the auto rule runs CLI-only models on the cli backend", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  expect_identical(subagent_backend(gptr_agent("code", model = "fakecodex/gpt-6-sol"),
                                    model_resolve(f$model)), "cli")
})

test_that("a fake CLI joins two inline agents and two workers on one reactor (INFRA-16)", {
  skip_on_cran()
  skip_without_installed_gptr()
  f = local_fake_cli("codex", "slow")
  slow = function(name) {
    gptr_fake_provider(list(list(text = paste(name, "done"), delay = 3)), name = name)
  }
  inline1 = slow("fakea")
  inline2 = slow("fakeb")
  work1 = slow("fakec")
  work2 = slow("faked")
  t0 = Sys.time()
  team = peter("Review the analysis", envir = new.env(), agents = list(
    a1 = agent(model = inline1), a2 = agent(model = inline2),
    w1 = agent(model = work1, backend = "worker"), w2 = agent(model = work2, backend = "worker"),
    code = agent(model = "fakecodex/gpt-6-sol")))
  elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_identical(team$kind, "team")
  expect_identical(team$code$text, "Slow codex done.")
  expect_identical(team$a1$text, "fakea done")
  expect_identical(team$w2$text, "faked done")
  expect_identical(team$code$messages[[length(team$code$messages)]]$route, "plan-cli")
  expect_lt(elapsed, 13)
})

# These copies isolate leaf observations without changing base or package namespace bindings.
codex_control_scope = function(fun, ...) {
  scope = list2env(list(...), parent = environment(fun))
  environment(fun) = scope
  fun
}

test_that("Windows control entry listing refuses unreadable or uncertain parents", {
  skip_on_cran()
  seen = new.env(parent = emptyenv())
  seen$calls = list()
  probe = codex_control_scope(pcli_control_entries, dir.exists = function(path) TRUE,
    list.files = function(path, ...) {
      args = list(...)
      required = c("all.files", "no..")
      stopifnot(all(required %in% names(args)), !anyDuplicated(names(args)),
        all(names(args) %in% c(required, "recursive", "full.names")))
      seen$calls[[length(seen$calls) + 1L]] = list(all.files = args[["all.files"]],
        no.. = args[["no.."]],
        recursive = if ("recursive" %in% names(args)) args[["recursive"]] else FALSE,
        full.names = if ("full.names" %in% names(args)) args[["full.names"]] else FALSE)
      c(".", "..", "SYSTEM.md")
    })
  expect_identical(probe("C:/public/.gptr"), "SYSTEM.md")
  expect_identical(seen$calls[[1L]],
    list(all.files = TRUE, no.. = FALSE, recursive = FALSE, full.names = FALSE))
  for (entries in list(character(), ".", c(".", "..", NA_character_))) {
    bad = codex_control_scope(pcli_control_entries, dir.exists = function(path) TRUE,
      list.files = function(...) entries)
    expect_error(bad("C:/public/.gptr"), class = "gptr_error_io")
  }
  bad = codex_control_scope(pcli_control_entries, dir.exists = function(path) TRUE,
    list.files = function(...) {
      warning("synthetic private listing detail")
      c(".", "..")
    })
  expect_no_warning(expect_error(bad("C:/public/.gptr"), class = "gptr_error_io"))
  bad = codex_control_scope(pcli_control_entries, dir.exists = function(path) TRUE,
    list.files = function(...) stop("synthetic private listing detail"))
  e = tryCatch(bad("C:/public/.gptr"), error = identity)
  expect_s3_class(e, "gptr_error_io")
  expect_false(grepl("synthetic private", conditionMessage(e), fixed = TRUE))
  missing = codex_control_scope(pcli_control_entries,
    dir.exists = function(path) identical(path, "C:/public"),
    list.files = function(...) c(".", "..", "canary.txt"))
  expect_identical(missing("C:/public/.gptr"), character())
  blocked = codex_control_scope(pcli_control_entries,
    dir.exists = function(path) identical(path, "C:/public"),
    list.files = function(...) c(".", "..", ".GPTR"))
  expect_error(blocked("C:/public/.gptr"), class = "gptr_error_io")
  no_relative = codex_control_scope(pcli_control_entries,
    dir.exists = function(path) path %in% c("C:", "/", "."),
    list.files = function(...) c(".", ".."))
  expect_error(no_relative("C:/"), class = "gptr_error_io")
  expect_error(no_relative("//public-server/share/.gptr"), class = "gptr_error_io")
})

test_that("Windows control entry membership retains fixed names without following targets", {
  root = path_norm(file.path(tempdir(), "codex-public-root"))
  g = file.path(root, ".gptr")
  probe = codex_control_scope(pcli_control_paths, is_windows = function() TRUE,
    pcli_control_entries = function(dir) {
      if (identical(dir, g)) c("system.MD", "mcp.json", "settings.local.json") else character()
    }, dir.exists = function(path) rep(FALSE, length(path)),
    file.exists = function(path) rep(FALSE, length(path)),
    pcli_control_link = function(path) rep("", length(path)))
  expect_identical(probe(root), sort(path_norm(file.path(g,
    c("SYSTEM.md", "mcp.json", "settings.local.json"))), method = "radix"))
  broken = codex_control_scope(pcli_control_paths, is_windows = function() TRUE,
    pcli_control_entries = function(dir) gptr_abort("Unreadable owned parent.", "io"))
  expect_error(broken(root), class = "gptr_error_io")
})

test_that("Windows reparse digests use only the trusted query and stripped helper environment", {
  skip_on_cran()
  withr::local_envvar(c(GPTR_TEST_API_KEY = "synthetic-control-secret"))
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  native = "Reparse Tag Value : 0xa000000c\nReparse Data Length : 16\n0000: 00 01 02 03\n"
  probe = codex_control_scope(pcli_control_reparse,
    Sys.getenv = function(name, unset = "") {
      expect_identical(name, "SystemRoot")
      "Z:\\Windows"
    }, dir.exists = function(path) identical(path, "Z:/Windows"),
    file.exists = function(path) identical(path, "Z:/Windows/System32/fsutil.exe"),
    proc_run = function(command, args, input = NULL, timeout, env, wd = NULL, echo = FALSE) {
      seen$calls = seen$calls + 1L
      expect_identical(command, "Z:/Windows/System32/fsutil.exe")
      expect_identical(args, c("reparsepoint", "query", "Z:/public/.gptr/SYSTEM.md"))
      expect_null(input)
      expect_identical(timeout, 5)
      expect_null(wd)
      expect_false(echo)
      expect_false("GPTR_TEST_API_KEY" %in% names(env))
      expect_identical(env[["NO_COLOR"]], "1")
      list(status = 0L, timed_out = FALSE, stdout = native, stderr = "")
    })
  marker = probe("Z:/public/.gptr/SYSTEM.md")
  expect_identical(marker, paste0("unreadable:reparse:", hash_sha256(native)))
  expect_identical(probe("Z:/public/.gptr/SYSTEM.md"), marker)
  expect_identical(seen$calls, 2L)
  expect_false(grepl("0xa000000c", marker, fixed = TRUE))
  expect_identical(Sys.getenv("GPTR_TEST_API_KEY"), "synthetic-control-secret")
})

test_that("Windows reparse probes reject unavailable executables and uncertain results", {
  skip_on_cran()
  good = list(status = 0L, timed_out = FALSE,
    stdout = "Reparse Tag Value : 0xa000000c\n0000: 00 01\n", stderr = "")
  state = new.env(parent = emptyenv())
  state$result = good
  state$root = "Z:/Windows"
  state$exists = TRUE
  state$calls = 0L
  probe = codex_control_scope(pcli_control_reparse,
    Sys.getenv = function(name, unset = "") state$root,
    dir.exists = function(path) identical(path, "Z:/Windows"),
    file.exists = function(path) state$exists,
    child_env = function(profile) character(),
    proc_run = function(...) {
      state$calls = state$calls + 1L
      state$result
    })
  for (root in c("", "Windows", "../Windows", "Z:/Windows\n", "Z:/../Windows")) {
    state$root = root
    expect_error(probe("Z:/public/link"), class = "gptr_error_io")
  }
  expect_identical(state$calls, 0L)
  state$root = "Z:/Windows"
  state$exists = FALSE
  expect_error(probe("Z:/public/link"), class = "gptr_error_io")
  expect_identical(state$calls, 0L)
  state$exists = TRUE
  bad = list(NULL, list(status = 1L, timed_out = FALSE, stdout = good$stdout),
    list(status = 0L, timed_out = TRUE, stdout = good$stdout),
    list(status = NA_integer_, timed_out = FALSE, stdout = good$stdout),
    list(status = 0L, stdout = good$stdout),
    list(status = 0L, timed_out = FALSE, stdout = ""),
    list(status = 0L, timed_out = FALSE, stdout = NA_character_),
    list(status = 0L, timed_out = FALSE, stdout = c(good$stdout, good$stdout)),
    list(status = 0L, timed_out = FALSE, stdout = "unexpected non-reparse output"),
    list(status = 0L, timed_out = FALSE, stdout = strrep("x", 128L * 1024L + 1L)))
  for (result in bad) {
    state$result = result
    expect_error(probe("Z:/public/link"), class = "gptr_error_io")
  }
  failure = codex_control_scope(probe,
    proc_run = function(...) stop("synthetic private process detail"))
  e = tryCatch(failure("Z:/public/link"), error = identity)
  expect_s3_class(e, "gptr_error_io")
  expect_false(grepl("synthetic private", conditionMessage(e), fixed = TRUE))
})

test_that("control digests query only unobservable Windows entries and retain POSIX markers", {
  skip_on_cran()
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  probe = codex_control_scope(pcli_control_digest, is_windows = function() TRUE,
    hash_file = function(path) stop("synthetic denied content"),
    pcli_control_link = function(path) "",
    path_info = function(...) {
      data.frame(size = NA_real_, mtime = as.POSIXct(NA_real_, origin = "1970-01-01"))
    },
    pcli_control_reparse = function(path) {
      seen$calls = seen$calls + 1L
      "unreadable:reparse:public-digest"
    })
  expect_identical(probe("public-link"), "unreadable:reparse:public-digest")
  expect_identical(seen$calls, 1L)
  finite = codex_control_scope(probe,
    path_info = function(...) data.frame(size = 12, mtime = as.POSIXct(1, origin = "1970-01-01")))
  expect_identical(finite("public-file"), "unreadable:12 1")
  expect_identical(seen$calls, 1L)
  posix = codex_control_scope(probe, is_windows = function() FALSE,
    pcli_control_link = function(path) "public-gone-target")
  expect_identical(posix("public-link"), "link:public-gone-target")
  expect_identical(seen$calls, 1L)
  unknown = codex_control_scope(probe, is_windows = function() FALSE,
    path_info = function(...) NULL)
  expect_identical(unknown("public-file"), "unreadable")
  expect_identical(seen$calls, 1L)
  readable = codex_control_scope(probe, hash_file = function(path) "public-content-digest")
  expect_identical(readable("public-file"), "public-content-digest")
  expect_identical(seen$calls, 1L)
  broken = codex_control_scope(probe,
    pcli_control_reparse = function(path) gptr_abort("Uncertain owned query.", "io"))
  expect_error(broken("public-link"), class = "gptr_error_io")
})

test_that("fixed dangling SYSTEM and MCP control links keep markers and detect retargeting", {
  skip_on_cran()
  codex_capability_local()
  root = local_project(files = list(".gptr/settings.json" = "{}",
    "capability-canary.txt" = "untouched sentinel"))
  codex_capability_preserve(file.path(root, "capability-canary.txt"))
  system = file.path(root, ".gptr", "SYSTEM.md")
  mcp = file.path(root, ".gptr", "mcp.json")
  system_link = codex_capability_link(system, root)
  mcp_link = codex_capability_link(mcp, root)
  system_first = system_link$make(file.path(root, "gone-system-1.md"))
  mcp_first = mcp_link$make(file.path(root, "gone-mcp-1.json"))
  before = pcli_control_hash(root)
  expect_true(all(path_norm(c(system, mcp)) %in% names(before)))
  expect_true(all(grepl("^(unreadable:reparse:|link:)", before[path_norm(c(system, mcp))])))
  expect_identical(pcli_control_hash(root), before)
  system_link$detach()
  system_second = system_link$make(file.path(root, "gone-system-2.md"))
  expect_false(identical(system_first, system_second), info = "native SYSTEM payload changed")
  system_after = pcli_control_hash(root)
  expect_identical(pcli_control_changed(before, system_after), path_norm(system))
  mcp_link$detach()
  mcp_second = mcp_link$make(file.path(root, "gone-mcp-2.json"))
  expect_false(identical(mcp_first, mcp_second), info = "native MCP payload changed")
  expect_identical(pcli_control_changed(system_after, pcli_control_hash(root)), path_norm(mcp))
})

# ---- confined Codex sessions for gptr_coach() (P29 T5; 08 section 3.7) -------------------------

# The switches every confined exec carries (08 3.7)
codex_off = c("shell_tool", "unified_exec_tty", "view_image", "multi_agent", "apps", "plugins",
              "tool_suggest", "image_generation", "memories", "goals", "sleep_tool",
              "skill_search", "browser_use", "computer_use")
codex_settings = c("web_search=\"disabled\"", "tools.experimental_request_user_input.enabled=false",
                   "agents.enabled=false", "skills.bundled.enabled=false",
                   "skills.include_instructions=false", "cloud.skills.enabled=false",
                   "include_permissions_instructions=false", "include_environment_context=false",
                   "include_apps_instructions=false", "history.persistence=\"none\"")

# The warning item the bypass flag always adds, and a hook log's start and denial lines
codex_bypass = list(type = "item.completed",
                    item = list(id = "item_0", type = "error",
                                message = paste("`--dangerously-bypass-hook-trust` is enabled.",
                                                "Enabled hooks may run without review for this",
                                                "invocation.")))
hook_start = "{\"event\":\"start\",\"time\":\"2026-10-28T10:00:00+0000\"}"
hook_deny = function(tool) {
  paste0("{\"event\":\"deny\",\"tool_name\":\"", tool, "\",\"time\":\"2026-10-28T10:00:01+0000\"}")
}
agent_message = function(text, id = "item_9") {
  list(type = "item.completed", item = list(id = id, type = "agent_message", text = text))
}

# A confined exec's normaliser: the role in the adapter state and a private folder whose hook
# log holds `log`
local_confined = function(role, log = hook_start, .env = parent.frame()) {
  opts = stub_opts() # nolint: object_usage_linter.
  dir = withr::local_tempdir(.local_envir = .env)
  if (length(log)) writeLines(log, file.path(dir, "hook.log"))
  opts$state$codex_role = role
  opts$state$codex_relay = dir
  model = stub_model("codex") # nolint: object_usage_linter.
  n = local_normaliser(pcli_codex_parse, model, opts, .env = .env) # nolint: object_usage_linter.
  list(n = n, opts = opts, dir = dir)
}

# Push events in order until one ends the exec; the last event emitted
push_all = function(n, opts, events) {
  for (ev in events) if (isTRUE(n$push(list(data = json_encode(ev), obj = ev)))) break
  opts$log$events[[length(opts$log$events)]]
}

# The value of a `-c hooks.<event>=` override: the hook's shell command, TOML-unescaped
codex_hook_command = function(args, event) {
  value = sub(paste0("^hooks[.]", event, "="), "",
              grep(paste0("^hooks[.]", event, "="), args, value = TRUE))
  quoted = regmatches(value, regexec("command=\"((?:[^\"\\\\]|\\\\.)*)\"", value, perl = TRUE))
  gsub("\\\\(.)", "\\1", quoted[[1L]][[2L]], perl = TRUE)
}

test_that("a confined exec is ephemeral, read-only, without Codex's own tools, and hooked", {
  withr::local_envvar(CODEX_HOME = withr::local_tempdir())
  head = c("exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules",
           "--skip-git-repo-check", "-m", "gpt-5.5", "-C", "/w")
  coach = pcli_codex_args("gpt-5.5", "/w", "workspace-write", "/r", role = "coach",
                          schema = "/r/schema.json")
  expect_identical(coach[seq_along(head)], head)
  expect_false(any(grepl("mcp_servers", coach, fixed = TRUE)))
  expect_identical(coach[match("--sandbox", coach) + 1L], "read-only")
  expect_identical(coach[which(coach == "--disable") + 1L], codex_off)
  expect_identical(coach[which(coach == "-c") + 1L][seq_along(codex_settings)], codex_settings)
  expect_true("--dangerously-bypass-hook-trust" %in% coach)
  expect_identical(utils::tail(coach, 3L), c("--output-schema", "/r/schema.json", "-"))
  hook = codex_hook_command(coach, "PreToolUse")
  expect_identical(codex_hook_command(coach, "SessionStart"), hook)
  expect_match(hook, "codex_hook.R", fixed = TRUE)
  expect_match(hook, "'coach' '/r/hook.log'", fixed = TRUE)
  expect_true(any(grepl("timeout=30}]}]$", coach)))
  run = pcli_codex_args("gpt-5.5", "/w", "workspace-write", "/r", role = "run")
  relay = codex_relay_args("/r")
  i = match(relay[[2L]], run)
  expect_identical(run[(i - 1L):(i + length(relay) - 2L)], relay)
  expect_identical(run[match("--sandbox", run) + 1L], "read-only")
  expect_match(codex_hook_command(run, "PreToolUse"), "'run' '/r/hook.log'", fixed = TRUE)
  expect_false("--output-schema" %in% run)
  expect_false(any(c("resume", "--resume") %in% c(coach, run)))
})

test_that("a keyring login's credentials store is passed through, and only that key", {
  home = withr::local_tempdir()
  withr::local_envvar(CODEX_HOME = home)
  expect_null(pcli_codex_auth_store())
  config = file.path(home, "config.toml")
  writeLines(c("model = \"gpt-5.5\"", "cli_auth_credentials_store = \"keyring\"  # OS keyring",
               "[profiles.work]", "cli_auth_credentials_store = \"file\""), config)
  expect_identical(pcli_codex_auth_store(), c("-c", "cli_auth_credentials_store=\"keyring\""))
  args = pcli_codex_args("gpt-5.5", "/w", "read-only", "/r", role = "coach")
  i = match("cli_auth_credentials_store=\"keyring\"", args)
  expect_identical(args[i - 1L], "-c")
  writeLines(c("[profiles.work]", "cli_auth_credentials_store = \"keyring\""), config)
  expect_null(pcli_codex_auth_store())
  writeLines("cli_auth_credentials_store = \"keyring\\\"; x = 1\"", config)
  expect_null(pcli_codex_auth_store())
})

test_that("under a coaching role build() never resumes and sends the whole history", {
  skip_on_cran()
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(
    pcli_probe = function(path) list(resume = TRUE),
    pcli_notice = function(cli) invisible(NULL)
  )
  rlang::local_bindings(coach_role = "coach", .env = the)
  opts = stub_opts(run = "r0000000002")
  opts$state$codex_thread = "0199a213-thread"
  returns = list(type = "object", properties = list(notes = list(type = "string"),
                                                    note = list(type = "string")),
                 required = list("notes"))
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000004",
             messages = list(msg_user("first"),
                             msg_assistant(list(block_text("one")), api = "cli-codex",
                                           provider = "fakecodex", model = "gpt-6-sol"),
                             msg_user("Again")),
             params = list(cli_mode = "auto", returns = returns))
  spec = pcli_codex_build(stub_model("codex"), ctx, opts)
  dir = opts$state$codex_relay
  withr::defer(unlink(dir, recursive = TRUE))
  args = spec$start$args
  expect_false("resume" %in% args)
  expect_identical(args[match("--sandbox", args) + 1L], "read-only")
  expect_null(opts$state$codex_control)
  expect_identical(opts$state$codex_role, "coach")
  expect_false(any(grepl("mcp_servers", args, fixed = TRUE)))
  prompt = as.character(spec$send[[1]])
  expect_match(prompt, "^<gptr_instructions>\nT0\n</gptr_instructions>")
  expect_match(prompt, "Assistant: one", fixed = TRUE)
  expect_match(prompt, "Again$")
  file = args[match("--output-schema", args) + 1L]
  expect_identical(file, file.path(dir, "schema.json"))
  expect_identical(json_decode(read_utf8(file)$text),
                   json_decode(paste0("{\"type\":\"object\",\"properties\":{\"notes\":",
                                      "{\"type\":\"string\"},\"note\":{\"type\":[\"string\",",
                                      "\"null\"]}},\"required\":[\"notes\",\"note\"],",
                                      "\"additionalProperties\":false}")))
  rlang::local_bindings(coach_role = "run", .env = the)
  spec2 = pcli_codex_build(stub_model("codex"), ctx, opts)
  withr::defer(unlink(opts$state$codex_relay, recursive = TRUE))
  args2 = spec2$start$args
  expect_false("resume" %in% args2)
  expect_true(any(startsWith(args2, "mcp_servers.gptr.command=")))
  expect_false("--output-schema" %in% args2)
  pcli_untrack("s0123456789")
})

test_that("strict form: every key required, optional keys nullable, no other keys anywhere", {
  schema = list(
    type = "object",
    properties = list(
      notes = list(type = "string"),
      level = list(enum = c("low", "high")),
      kind = list(type = "string", enum = list("a", "b")),
      skills = list(type = "array",
                    items = list(type = "object",
                                 properties = list(name = list(type = "string"),
                                                   text = list(type = list("string"))),
                                 required = "name")),
      extra = list(properties = list(x = list(type = "integer")))),
    required = c("notes", "skills"))
  want = paste0(
    "{\"type\":\"object\",\"properties\":{",
    "\"notes\":{\"type\":\"string\"},",
    "\"level\":{\"anyOf\":[{\"enum\":[\"low\",\"high\"]},{\"type\":\"null\"}]},",
    "\"kind\":{\"type\":[\"string\",\"null\"],\"enum\":[\"a\",\"b\",null]},",
    "\"skills\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{",
    "\"name\":{\"type\":\"string\"},\"text\":{\"type\":[\"string\",\"null\"]}},",
    "\"required\":[\"name\",\"text\"],\"additionalProperties\":false}},",
    "\"extra\":{\"anyOf\":[{\"properties\":{\"x\":{\"type\":[\"integer\",\"null\"]}},",
    "\"required\":[\"x\"],\"additionalProperties\":false},{\"type\":\"null\"}]}},",
    "\"required\":[\"notes\",\"level\",\"kind\",\"skills\",\"extra\"],",
    "\"additionalProperties\":false}")
  expect_identical(json_decode(json_encode(pcli_codex_strict(schema))), json_decode(want))
  empty = json_encode(pcli_codex_strict(list(type = "object")))
  expect_identical(empty, paste0("{\"type\":\"object\",\"properties\":{},\"required\":[],",
                                 "\"additionalProperties\":false}"))
})

# Run gptr's Codex hook on `input` (text on stdin) as Codex does; its exit status, output and log
run_codex_hook = function(input, mode = "run", log = tempfile("hook-", fileext = ".log"),
                          lib = dirname(system.file(package = "jsonlite"))) {
  inp = tempfile("hook-in-")
  writeBin(charToRaw(input), inp)
  hook = system.file("gptr", "codex_hook.R", package = "gptr", mustWork = TRUE)
  res = processx::run(rscript_path(), c("--vanilla", hook, mode, log, lib), stdin = inp,
                      error_on_status = FALSE)
  rows = if (file.exists(log)) lapply(readLines(log, warn = FALSE), json_decode) else list()
  list(status = res$status, stdout = res$stdout, stderr = res$stderr, rows = rows)
}
pre_tool = function(tool, input = json_obj()) {
  json_encode(list(hook_event_name = "PreToolUse", tool_name = tool, tool_input = input,
                   session_id = "s", turn_id = "t", tool_use_id = "u", cwd = "/w"))
}

test_that("the Codex hook writes its start line and lets a run use only gptr's tools", {
  skip_on_cran()
  start = run_codex_hook(json_encode(list(hook_event_name = "SessionStart", source = "startup")),
                         mode = "coach")
  expect_identical(start$status, 0L)
  expect_identical(start$stdout, "")
  expect_identical(start$rows[[1L]]$event, "start")
  expect_length(start$rows, 1L)
  ok = run_codex_hook(pre_tool("mcp__gptr__r", list(code = "1 + 1")))
  expect_identical(ok$status, 0L)
  expect_length(ok$rows, 0L)
  marker = file.path(withr::local_tempdir(), "evaluated")
  denied = list(
    run_codex_hook(pre_tool("mcp__gptr__r"), mode = "coach"),
    run_codex_hook(pre_tool("Bash", list(command = paste0("touch ", marker, " mcp__gptr__r")))),
    run_codex_hook(pre_tool(paste0("system('touch ", marker, "')"))),
    run_codex_hook(pre_tool("xmcp__gptr__r")),
    run_codex_hook(pre_tool("mcp__gptr__r"), mode = "auto"))
  for (d in denied) {
    expect_identical(d$status, 2L)
    expect_true(nzchar(trimws(d$stderr)))
    expect_identical(d$rows[[1L]]$event, "deny")
    expect_true(nzchar(d$rows[[1L]]$time))
  }
  expect_identical(vapply(denied, function(d) d$rows[[1L]]$tool_name, ""),
                   c("mcp__gptr__r", "Bash", paste0("system('touch ", marker, "')"),
                     "xmcp__gptr__r", "mcp__gptr__r"))
  expect_false(file.exists(marker))
  # input it cannot read is denied, with no tool name; so is everything without jsonlite
  for (d in list(run_codex_hook("not json {"), run_codex_hook("[1, 2]"),
                 run_codex_hook(pre_tool("mcp__gptr__r"), lib = withr::local_tempdir()))) {
    expect_identical(d$status, 2L)
    expect_null(d$rows[[1L]]$tool_name)
  }
  nolib = run_codex_hook(json_encode(list(hook_event_name = "SessionStart")),
                         lib = withr::local_tempdir())
  expect_identical(nolib$rows[[1L]]$event, "deny")
  # a log it cannot write still denies
  lost = run_codex_hook(pre_tool("Bash"), log = file.path(tempfile(), "no", "hook.log"))
  expect_identical(lost$status, 2L)
})

test_that("the hook command in the argv runs through the shell and logs its start", {
  skip_on_cran()
  skip_on_os("windows")
  dir = withr::local_tempdir(pattern = "a dir with 'quotes' ")
  withr::local_envvar(CODEX_HOME = withr::local_tempdir())
  cmd = codex_hook_command(pcli_codex_args("gpt-5.5", "/w", "read-only", dir, role = "coach"),
                           "SessionStart")
  inp = tempfile("hook-in-")
  writeLines(json_encode(list(hook_event_name = "SessionStart", source = "startup")), inp)
  res = processx::run("/bin/sh", c("-c", cmd), stdin = inp, error_on_status = FALSE)
  expect_identical(res$status, 0L)
  expect_identical(json_decode(readLines(file.path(dir, "hook.log")))$event, "start")
})

test_that("on Windows the hook command holds no quote: short paths, or a refusal", {
  short = c("C:\\PROGRA~1\\R\\bin\\Rscript.exe", "C:\\R\\gptr\\CODEX_~1.R", "C:\\T\\GPTR-C~1",
            "C:\\R\\lib")
  local_mocked_bindings(pcli_is_windows = function() TRUE,
                        pcli_cmd_paths = function(paths) if (length(paths) == 4L) short)
  hook = codex_hook_command(pcli_codex_hooks("coach", "C:/Users/Jane Doe/T/gptr-codex-1"),
                            "PreToolUse")
  expect_identical(hook, paste(short[[1L]], "--vanilla", short[[2L]], "coach",
                               file.path(short[[3L]], "hook.log"), short[[4L]]))
  local_mocked_bindings(pcli_cmd_paths = function(paths) NULL)
  expect_error(pcli_codex_hooks("run", "C:/Users/Jane Doe/T/gptr-codex-1"),
               "no short (8.3) name", fixed = TRUE, class = "gptr_error_model_refused")
})

test_that("on Windows the hook command runs through cmd.exe and logs its start", {
  skip_on_cran()
  skip_if_not(pcli_is_windows())
  dir = withr::local_tempdir(pattern = "a dir ")
  withr::local_envvar(CODEX_HOME = withr::local_tempdir())
  if (is.null(pcli_cmd_paths(dir))) skip("this volume gives no short (8.3) names")
  cmd = codex_hook_command(pcli_codex_args("gpt-5.5", "/w", "read-only", dir, role = "coach"),
                           "SessionStart")
  expect_false(grepl("\"", cmd, fixed = TRUE))
  inp = tempfile("hook-in-")
  writeLines(json_encode(list(hook_event_name = "SessionStart", source = "startup")), inp)
  res = processx::run(Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/c", cmd), stdin = inp,
                      error_on_status = FALSE)
  expect_identical(res$status, 0L)
  expect_identical(json_decode(readLines(file.path(dir, "hook.log")))$event, "start")
})

test_that("a confined coach keeps its reply: bypass warning, hook start, one message", {
  skip_on_cran()
  c1 = local_confined("coach")
  ev = push_all(c1$n, c1$opts, list(
    list(type = "thread.started", thread_id = "t1"), list(type = "turn.started"), codex_bypass,
    list(type = "item.completed", item = list(id = "item_1", type = "error",
                                              message = "Model rerouted to gpt-5.5")),
    list(type = "error", message = "Reconnecting... 1/5"),
    list(type = "item.completed", item = list(id = "item_2", type = "reasoning", text = "ok")),
    agent_message("{\"notes\":\"n\"}"),
    list(type = "turn.completed", usage = list(input_tokens = 9L, output_tokens = 2L))))
  expect_identical(ev$type, "done")
  expect_identical(msg_text(c1$n$message()), "{\"notes\":\"n\"}")
  expect_false(dir.exists(c1$dir))
})

test_that("a confined coach is discarded when a check fails", {
  skip_on_cran()
  done = list(type = "turn.completed", usage = list(input_tokens = 9L, output_tokens = 2L))
  cases = list(
    list(log = hook_start, events = list(agent_message("{}"), done), why = "bypass"),
    list(log = character(), events = list(codex_bypass, agent_message("{}"), done),
         why = "start"),
    list(log = c(hook_start, hook_deny("view_image")),
         events = list(codex_bypass, agent_message("{}"), done), why = "view_image"),
    list(log = c(hook_start, "garbled"), events = list(codex_bypass, agent_message("{}"), done),
         why = "denied"),
    list(log = hook_start, events = list(codex_bypass, done), why = "0 messages"),
    list(log = hook_start,
         events = list(codex_bypass, agent_message("a", "item_1"), agent_message("b"), done),
         why = "2 messages"))
  for (case in cases) {
    c1 = local_confined("coach", log = case$log)
    ev = push_all(c1$n, c1$opts, case$events)
    expect_identical(ev$type, "error")
    expect_identical(ev$error$class, "cli_check")
    expect_match(ev$message$error_message, case$why, fixed = TRUE)
    expect_equal(ev$message$usage$output, 2)
  }
})

test_that("a step outside gptr's tools stops a confined exec at once", {
  skip_on_cran()
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    invisible(TRUE)
  })
  item = function(type, ...) list(id = "item_5", type = type, ...)
  outside = list(
    coach = list(list(type = "item.started", item = item("command_execution", command = "ls")),
                 list(type = "item.started", item = item("mcp_tool_call", server = "gptr",
                                                         tool = "r")),
                 list(type = "item.completed", item = item("file_change")),
                 list(type = "item.started", item = item("web_search", query = "q")),
                 list(type = "item.updated", item = item("todo_list")),
                 list(type = "item.started", item = list(id = "item_6"))),
    run = list(list(type = "item.started", item = item("mcp_tool_call", server = "docs",
                                                       tool = "search")),
               list(type = "item.completed", item = item("collab_tool_call"))))
  for (role in names(outside)) {
    for (ev in outside[[role]]) {
      c1 = local_confined(role)
      expect_true(push_obj(c1$n, ev))
      last = c1$opts$log$events[[length(c1$opts$log$events)]]
      expect_identical(last$error$class, "cli_check")
      expect_match(last$message$error_message, "outside gptr's tools", fixed = TRUE)
    }
  }
  expect_identical(stopped$n, 8L)
  c2 = local_confined("run")
  ev = push_all(c2$n, c2$opts, list(
    codex_bypass,
    list(type = "item.started", item = item("mcp_tool_call", server = "gptr", tool = "r",
                                            status = "in_progress")),
    list(type = "item.completed", item = item("mcp_tool_call", server = "gptr", tool = "r",
                                              status = "completed")),
    agent_message("Done."), list(type = "turn.completed")))
  expect_identical(ev$type, "done")
})

test_that("a confined run reports each hook denial as a refused step and still completes", {
  skip_on_cran()
  c1 = local_confined("run", log = c(hook_start, hook_deny("Bash"), hook_deny("view_image")))
  ev = push_all(c1$n, c1$opts, list(codex_bypass, agent_message("Done."),
                                    list(type = "turn.completed")))
  expect_identical(ev$type, "done")
  ends = Filter(function(e) identical(e$type, "tool_execution_end"), c1$opts$log$events)
  expect_identical(vapply(ends, function(e) e$tool_name, ""), c("Bash", "view_image"))
  for (e in ends) {
    expect_true(e$informational)
    expect_true(e$is_error)
    expect_match(e$refused, "hook", fixed = TRUE)
  }
  starts = Filter(function(e) identical(e$type, "tool_execution_start"), c1$opts$log$events)
  expect_identical(vapply(starts, function(e) e$tool_call_id, ""),
                   vapply(ends, function(e) e$tool_call_id, ""))
  c2 = local_confined("run", log = character())
  ev2 = push_all(c2$n, c2$opts, list(codex_bypass, agent_message("Done."),
                                     list(type = "turn.completed")))
  expect_identical(ev2$error$class, "cli_check")
})

test_that("a Codex plan limit ends the exec as a plan limit with its quoted reset time", {
  expect_identical(pcli_codex_limit(paste("You’ve hit your usage limit. Upgrade to Pro,",
                                          "or try again at 3:45 PM.")), "3:45 PM")
  expect_identical(pcli_codex_limit(c("Reconnecting...", paste(
    "You've hit your usage limit. Try again at Oct 29th, 2026 9:05 AM."))),
    "Oct 29th, 2026 9:05 AM")
  expect_identical(pcli_codex_limit("You’ve hit your usage limit. Try again later."),
                   NA_character_)
  expect_identical(pcli_codex_limit("Your workspace is out of credits. Add credits to continue."),
                   NA_character_)
  expect_identical(pcli_codex_limit(paste("You hit your spend cap set in your workspace.",
                                          "Increase your spend cap to continue.")),
                   NA_character_)
  expect_null(pcli_codex_limit(c("usage limit reached", "stream disconnected")))
  expect_null(pcli_codex_limit(NULL))
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  push_obj(n, list(type = "error",
                   message = "You’ve hit your usage limit. Try again at 3:45 PM."))
  expect_true(push_obj(n, list(type = "turn.failed", error = json_obj())))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$error$class, "plan_limit")
  expect_identical(ev$error$resets_at, "3:45 PM")
  expect_match(ev$message$error_message, "hit your usage limit", fixed = TRUE)
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  push_obj(n2, list(type = "error", message = "Your workspace is out of credits."))
  ev2 = n2$finish()
  last = opts2$log$events[[length(opts2$log$events)]]
  expect_identical(last$error$class, "plan_limit")
  expect_identical(last$error$resets_at, NA_character_)
})

# A fake codex for the preflight in its own folder: it prints features.txt and exits with
# status.txt; calls.txt logs each argv
local_preflight_codex = function(features = NULL, status = 0L, .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  script = file.path(dir, "fake-codex.R")
  writeLines(c(
    "args = commandArgs(trailingOnly = TRUE)",
    "cat(paste(args[-1L], collapse = ' '), '\\n', file = file.path(args[[1L]], 'calls.txt'),",
    "    append = TRUE)",
    "writeLines(readLines(file.path(args[[1L]], 'features.txt')))",
    "quit(save = 'no', status = as.integer(readLines(file.path(args[[1L]], 'status.txt'))))"),
    script)
  states = c(stats::setNames(rep("false", length(codex_off)), codex_off), hooks = "true",
             unified_exec = "true")
  states[names(features)] = features
  states = states[!is.na(states)]
  rows = c(sprintf("%-40s %-18s %s", names(states), "stable", states),
           sprintf("%-40s %-18s %s", "agent_message_board", "under development", "false"))
  writeLines(rows, file.path(dir, "features.txt"))
  writeLines(as.character(status), file.path(dir, "status.txt"))
  list(path = c(rscript_path(), "--vanilla", script, dir),
       calls = function() readLines(file.path(dir, "calls.txt"), warn = FALSE))
}

test_that("the Codex preflight checks hooks.json and the switched-off features", {
  skip_on_cran()
  home = withr::local_tempdir()
  withr::local_envvar(CODEX_HOME = home)
  ok = local_preflight_codex()
  expect_true(pcli_codex_preflight(ok$path))
  features = grep("^features list", ok$calls(), value = TRUE)
  expect_length(features, 1L)
  expect_identical(strsplit(trimws(features), " ", fixed = TRUE)[[1L]],
                   c("features", "list", as.vector(rbind("--disable", codex_off)),
                     as.vector(rbind("-c", codex_settings))))
  refused = function(fake, pattern) {
    e = expect_error(pcli_codex_preflight(fake$path), class = "gptr_error_model_refused")
    expect_identical(e$reason, "cli_preflight")
    expect_match(conditionMessage(e), pattern, fixed = TRUE)
  }
  refused(local_preflight_codex(features = c(shell_tool = "true")), "shows shell_tool in")
  refused(local_preflight_codex(features = c(hooks = "false")), "shows hooks in")
  refused(local_preflight_codex(features = c(computer_use = NA)), "shows computer_use in")
  refused(local_preflight_codex(status = 1L), "features list` exited")
  file.create(file.path(home, "hooks.json"))
  refused(ok, "hooks.json exists")
  unlink(file.path(home, "hooks.json"))
  expect_true(pcli_codex_preflight(ok$path))
})
