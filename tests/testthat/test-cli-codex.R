# tests/testthat/test-cli-codex.R -- the cli-codex adapter, the codex routes end to end and the
# CLI leg of INFRA-16 (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The MCP overrides of contract 8.5 / IC-65, verbatim
codex_mcp_8_5 = function(port) {
  c("-c", paste0("mcp_servers.gptr.url=http://127.0.0.1:", port, "/mcp"),
    "-c", "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

# ---- the cli-codex adapter (Task 7) -------------------------------------------------------------

test_that("the codex argv follows IC-65, and the resume form uses -c sandbox_mode=", {
  expect_identical(pcli_codex_args("gpt-6-sol", "/w", "read-only", port = 54321L),
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", "/w", codex_mcp_8_5(54321L), "--sandbox", "read-only",
                     "-"))
  resumed = pcli_codex_args("gpt-6-sol", "/w", "workspace-write", port = 54321L,
                           resume = "0199a213-thread")
  expect_identical(resumed,
                   c("exec", "resume", "0199a213-thread", "--json", "--ignore-user-config",
                     "--skip-git-repo-check", "-m", "gpt-6-sol", codex_mcp_8_5(54321L), "-c",
                     "sandbox_mode=workspace-write", "-"))
  expect_false(any(c("-C", "-s", "--sandbox") %in% resumed))
  expect_identical(pcli_codex_args("gpt-6-sol", "/w", "read-only"),
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", "/w", "--sandbox", "read-only", "-"))
})

test_that("plan, manual and edits run read-only; auto workspace-write; Windows falls back", {
  local_mocked_bindings(pcli_is_windows = function() FALSE)
  for (mode in c("plan", "manual", "edits")) {
    expect_identical(pcli_codex_sandbox(mode, "codex"), "read-only")
  }
  expect_identical(pcli_codex_sandbox("auto", "codex"), "workspace-write")
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

test_that("the MCP record of a session reaches only its own codex exec", {
  local_mcp_stub(stub_mcp_handle(port = 54999L, token = "tok-session-0123"))
  rec = pcli_codex_ensure(list(id = "s0123456789"))
  withr::defer(pcli_codex_forget("s0123456789"))
  expect_identical(rec$port, 54999L)
  h = pcli_codex_mcp(stub_opts())
  expect_identical(h$port, 54999L)
  expect_identical(h$env, c(GPTR_MCP_TOKEN = "tok-session-0123"))
  expect_null(pcli_codex_mcp(stub_opts(session = "s9999999999")))
  expect_null(pcli_codex_ensure(list(id = NULL)))
  pcli_codex_forget("s0123456789")
  expect_null(pcli_codex_mcp(stub_opts()))
})

test_that("a tokenless MCP server leaves the exec on files only", {
  h = stub_mcp_handle()
  h$config = list()
  local_mcp_stub(h)
  rec = pcli_codex_ensure(list(id = "s0123456789"))
  withr::defer(pcli_codex_forget("s0123456789"))
  expect_match(rec$error, "no token", fixed = TRUE)
  expect_null(pcli_codex_mcp(stub_opts()))
})

test_that("build() starts one exec per turn with the MCP overrides and the token in env", {
  local_fake_cli_path("codex", "text")
  seen = new.env()
  local_mocked_bindings(
    pcli_probe = function(path) list(resume = TRUE),
    pcli_notice = function(cli) invisible(NULL),
    pcli_codex_mcp = function(opts) list(port = 54321L, env = c(GPTR_MCP_TOKEN = "tok-test-0123")),
    reactor_served = function(run, served = TRUE) {
      seen$calls = c(seen$calls, paste(run, served))
      invisible(run)
    }
  )
  opts = stub_opts(run = "r0000000002")
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000004",
             messages = list(msg_user("Summarise x")),
             params = list(cli_mode = "edits", cli_budget = list(turns = 4)))
  spec = pcli_codex_build(stub_model("codex"), ctx, opts)
  args = spec$start$args
  tail = c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", "gpt-6-sol",
           "-C", path_norm(getwd()), codex_mcp_8_5(54321L), "--sandbox", "read-only", "-")
  expect_identical(args[(length(args) - length(tail) + 1L):length(args)], tail)
  expect_identical(spec$start$env, c(GPTR_MCP_TOKEN = "tok-test-0123"))
  expect_identical(spec$start$env_profile, "cli-codex")
  expect_true(spec$close_stdin)
  expect_s3_class(spec$send[[1]], "json")
  expect_match(spec$send[[1]], "Summarise x$")
  expect_identical(opts$state$codex_cap, 4L)
  expect_identical(seen$calls, "r0000000002 TRUE")
  opts$state$codex_thread = "0199a213-thread"
  spec2 = pcli_codex_build(stub_model("codex"), ctx, opts)
  i = match("exec", spec2$start$args)
  expect_identical(spec2$start$args[i + 0:2], c("exec", "resume", "0199a213-thread"))
  expect_identical(as.character(spec2$send[[1]]), "Summarise x")
  pcli_untrack("s0123456789")
})

test_that("without a token for this session the exec runs on files only", {
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_codex_mcp = function(opts) NULL)
  spec = pcli_codex_build(stub_model("codex"), list(messages = list(msg_user("hi"))), stub_opts())
  expect_false(any(grepl("mcp_servers", spec$start$args, fixed = TRUE)))
  expect_identical(spec$start$env, character())
  pcli_untrack("s0123456789")
})

test_that("the call-1 capture: informational tool events, the answer and the usage", {
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

test_that("gptr's own MCP calls are reported, reasoning becomes thinking", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-mcp.jsonl"))
  starts = Filter(function(e) identical(e$type, "tool_execution_start"), opts$log$events)
  expect_identical(starts[[1]]$tool_name, "mcp__gptr__r")
  expect_identical(starts[[1]]$input$code, "live_answer = sum(1:10); live_answer")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  feed_fixture(n2, "codex-text.jsonl")
  expect_identical(vapply(n2$message()$content, function(b) b$type, ""), c("thinking", "text"))
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

test_that("a turn budget that is not finite or very large still gives a whole-number cap", {
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
  root = local_project(files = list(".gptr/settings.json" = "{}", ".git/hooks/pre-push" = "x"))
  hook = file.path(root, ".git", "hooks", "pre-commit")
  made = suppressWarnings(file.symlink(file.path(root, "gone-1.sh"), hook))
  skip_if_not(isTRUE(made), "symbolic links are not available")
  # R reads no link target on Windows (Sys.readlink() gives ""): there the link is unreadable
  readable = nzchar(pcli_control_link(hook))
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_codex_mcp = function(opts) NULL)
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
  # the dangling link pointed somewhere else is a change (R on Windows can neither read nor
  # unlink a file link)
  skip_if_not(readable, "R reads no symbolic link target on this platform")
  opts2 = stub_opts()
  opts2$state$codex_sandbox = "workspace-write"
  opts2$state$codex_control = pcli_control_hash(root)
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  unlink(hook)
  file.symlink(file.path(root, "gone-2.sh"), hook)
  w = expect_warning(feed_fixture(n2, "codex-text.jsonl"), class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), ".git/hooks/pre-commit", fixed = TRUE)
  expect_identical(event_types(opts2)[[length(opts2$log$events)]], "done")
})

test_that("a control file gptr cannot read is marked by its size and time instead", {
  root = local_project(files = list(".gptr/agents/locked.md" = "secret agent"))
  locked = file.path(root, ".gptr", "agents", "locked.md")
  Sys.chmod(locked, "200")
  withr::defer(Sys.chmod(locked, "644"))
  skip_if(file.access(locked, 4L) == 0L, "the file stays readable (permissions not enforced)")
  h = pcli_control_hash(root)
  expect_match(h[[path_norm(locked)]], "^unreadable:[0-9]+ [0-9.]+$")
  cat("a longer secret agent\n", file = locked, append = TRUE)
  expect_identical(pcli_control_changed(h, pcli_control_hash(root)), path_norm(locked))
})

test_that("a control-file check that fails still completes the exec, then warns", {
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
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  settings = file.path(root, ".gptr", "settings.json")
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_codex_mcp = function(opts) NULL)
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
  a = local_project(files = list(".gptr/settings.json" = "{}"))
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_is_windows = function() FALSE,
                        pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_codex_mcp = function(opts) NULL)
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

test_that("a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  local_mcp_stub()
  withr::local_envvar(OPENAI_API_KEY = "sk-p20fake-openai-0000000000000000",
                      CODEX_API_KEY = "codex-p20fake-0000000000000",
                      OPENAI_BASE_URL = "https://example.invalid/v1", CODEX_SANDBOX = "seatbelt")
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  big = paste0("Summarise this text: ", strrep("abcdefghij", 5000L), " caf\u00e9.")
  seen = new.env()
  seen$vars = character()
  s = withCallingHandlers(
    peter(big, model = f$model, envir = new.env(), mode = "edits"),
    gptr_warning_billing_env = function(w) {
      seen$vars = c(seen$vars, w$variables)
      invokeRestart("muffleWarning")
    })
  expect_identical(fake_argv(f)[[1]],
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", path_norm(getwd()), codex_mcp_8_5(54321L), "--sandbox",
                     "read-only", "-"))
  bytes = fake_prompts(f)[[1]]
  prompt = rawToChar(bytes)
  Encoding(prompt) = "UTF-8"
  expect_gt(length(bytes), 50000L)
  expect_true(grepl(big, prompt, fixed = TRUE, useBytes = TRUE))
  expect_match(prompt, "^<gptr_instructions>\n")
  env = fake_env_names(f)[[1]]
  expect_true("GPTR_MCP_TOKEN" %in% env)
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

test_that("the next turn resumes the Codex thread with -c sandbox_mode=", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  local_mcp_stub()
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

test_that("a fake codex evaluates R in the live session through gptr's MCP server", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
  withr::defer(gptr_mcp_serve(stop = TRUE))
  f = local_fake_cli("codex", "mcp")
  e = new.env()
  s = peter("Compute the sum of 1 to 10 in R", model = f$model, envir = e, mode = "auto")
  expect_identical(e$live_answer, 55L)
  expect_identical(fake_log(f, "mcp")[[1]]$status, 200L)
  expect_match(s$text, "55", fixed = TRUE)
})

test_that("a fake codex returns a function's numeric result through the HTTP MCP bridge", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
  withr::defer(gptr_mcp_serve(stop = TRUE))
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
  expect_identical(fake_log(f, "mcp")[[1L]]$status, 200L)
  expect_null(run_current())
})

test_that("the auto rule runs CLI-only models on the cli backend", {
  f = local_fake_cli("codex", "text")
  expect_identical(subagent_backend(gptr_agent("code", model = "fakecodex/gpt-6-sol"),
                                    model_resolve(f$model)), "cli")
})

test_that("a fake CLI joins two inline agents and two workers on one reactor (INFRA-16)", {
  skip_on_cran()
  skip_without_installed_gptr()
  f = local_fake_cli("codex", "slow")
  local_mcp_stub()
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
