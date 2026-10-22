# Compaction requests are billable attempts, not assistant replies or executable R turns.
# All fixtures use public data and the offline fake provider in disposable projects.

compaction_fixture = function(script, .env = parent.frame()) {
  local_project(.env = .env)
  fake = local_fake_provider(script, .env = .env)
  home = new.env()
  home$d = mtcars
  s = session_new("fake/fake-1", "auto", home = home)
  session_append(s, list(type = "message", message = msg_user("Use the public mtcars data.")))
  list(s = s, fake = fake, home = home)
}

compaction_entries = function(s) {
  Filter(function(e) identical(e$type, "compaction"), session_data(s)$entries)
}

compaction_events = function(types, .env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$events = list()
  offs = list()
  withr::defer({
    for (off in offs) off()
  }, envir = .env)
  for (type in types) {
    offs[[length(offs) + 1L]] = gptr_register(gptr_hook(type, function(event, ctx) {
      seen$events[[length(seen$events) + 1L]] = event
      NULL
    }))
  }
  seen
}

test_that("each checkpoint attempt is charged once and survives stored reconstruction", {
  x = compaction_fixture(list(fake_text("", usage = usage_new(input = 100, output = 5)),
                              fake_text("A useful summary.",
                                        usage = usage_new(input = 120, output = 7))))
  before = session_data(x$s)$entries
  id = x$s$id
  input = serialize(x$home$d, NULL)
  compact_run(x$s, "manual")
  rows = x$s$usage
  expect_identical(nrow(rows), 2L)
  expect_equal(rows$input, c(100, 120))
  expect_equal(rows$output, c(5, 7))
  expect_equal(rows$cost, c(0, 0))
  expect_false(any(rows$estimated))
  expect_identical(anyDuplicated(rows$request_id), 0L)
  expect_true(all(nzchar(rows$request_id)))
  expect_length(fake_requests(x$fake), 2L)
  expect_length(compaction_entries(x$s), 1L)
  expect_equal(compaction_entries(x$s)[[1L]]$usage$input, 220)
  restored = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_identical(restored$request_id, rows$request_id)
  expect_equal(restored$input, rows$input)
  expect_equal(as.numeric(restored$started), as.numeric(rows$started))
  expect_identical(x$s$id, id)
  expect_identical(session_data(x$s)$entries[seq_along(before)], before)
  expect_identical(serialize(x$home$d, NULL), input)
})

test_that("unknown CLI-style checkpoint usage is durable and never changed into zero", {
  x = compaction_fixture(list("A summary without metering."))
  original = provider_stream
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    original(model, context, opts, emit, function(msg) {
      msg$usage = NULL
      msg$route = "plan-cli"
      done(msg)
    }, run)
  })
  compact_run(x$s, "manual")
  expect_identical(nrow(x$s$usage), 1L)
  expect_true(all(is.na(unlist(x$s$usage[usage_token_columns], use.names = FALSE))))
  expect_false(x$s$usage$estimated)
  expect_identical(x$s$usage$route, "plan-cli")
  rebuilt = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_identical(rebuilt$request_id, x$s$usage$request_id)
  expect_true(all(is.na(unlist(rebuilt[usage_token_columns], use.names = FALSE))))
})

test_that("a checkpoint attempt consumes the active request budget before retrying", {
  x = compaction_fixture(list(fake_text("", usage = usage_new(input = 100, output = 5)),
                              "This second request must not start."))
  seen = compaction_events(c("before_request", "usage", "session_compact", "agent_end"))
  local_service("compact.should", function(s, tokens, idle) TRUE)
  run = run_start(x$s, msg_user("Continue."), list(budget = list(turns = 1L)))
  run_wait(list(run), timeout = 5)
  expect_identical(x$s$status, "budget")
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  types = vapply(seen$events, function(e) e$type, "")
  expect_identical(types, c("before_request", "usage", "session_compact", "agent_end"))
  expect_identical(seen$events[[1L]]$run, run$id)
  expect_identical(seen$events[[1L]]$request_id, x$s$usage$request_id)
  expect_identical(seen$events[[2L]]$row$request_id, x$s$usage$request_id)
  expect_identical(nrow(seen$events[[4L]]$usage), 1L)
  expect_identical(seen$events[[4L]]$usage$request_id, x$s$usage$request_id)
  expect_identical(seen$events[[4L]]$usage$input, 100)
  expect_identical(run$request_ids, x$s$usage$request_id)
  expect_null(run$compact_finish)
  expect_false(any(grepl("must not start", vapply(seen$events, json_encode, ""), fixed = TRUE)))
  expect_null(session_live(x$s)$run)
})

test_that("an exhausted token budget prevents the checkpoint request itself", {
  x = compaction_fixture(list("This request must not start."))
  local_service("compact.should", function(s, tokens, idle) TRUE)
  run = run_start(x$s, msg_user("Continue."), list(budget = list(tokens = 1L)))
  run_wait(list(run), timeout = 5)
  expect_identical(x$s$status, "budget")
  expect_length(fake_requests(x$fake), 0L)
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(run$request_ids, 0L)
  expect_null(session_live(x$s)$run)
})

test_that("a delayed aborted checkpoint is charged without a late reply or history rewrite", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_live_console()
  x = compaction_fixture(function(request) {
    reactor_timer(at = reactor_now() + 0.05, fn = function() {
      seen$task = the$live_row$task
      run_abort(run, "user")
    })
    fake_text("late summary", delay = 1)
  })
  local_service("compact.should", function(s, tokens, idle) TRUE)
  seen = compaction_events(c("before_request", "usage", "session_compact", "agent_end"))
  before = session_data(x$s)$entries
  run = run_start(x$s, msg_user("Continue."))
  output = utils::capture.output(run_wait(list(run), timeout = 5))
  expect_true(any(grepl("thinking", output, fixed = TRUE)))
  expect_true(rlang::is_string(seen$task))
  expect_false(exists(seen$task, envir = reactor_get()$tasks, inherits = FALSE))
  expect_null(console_record(list(run = run$id)))
  expect_identical(x$s$status, "aborted")
  expect_null(session_live(x$s)$run)
  expect_length(compaction_entries(x$s), 0L)
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(x$s$usage$stop_reason, "aborted")
  expect_true(all(is.na(unlist(x$s$usage[setdiff(usage_token_columns, "cost")],
                              use.names = FALSE))))
  expect_identical(x$s$usage$cost, 0)
  expect_identical(session_data(x$s)$entries[seq_along(before)], before)
  restored = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_identical(restored$request_id, x$s$usage$request_id)
  expect_identical(restored$stop_reason, "aborted")
  expect_false(any(vapply(seen$events, function(e) identical(e$type, "session_compact"), NA)))
  charged = Filter(function(e) identical(e$type, "usage"), seen$events)
  expect_length(charged, 1L)
  expect_identical(charged[[1L]]$run, run$id)
  expect_identical(charged[[1L]]$row$request_id, x$s$usage$request_id)
  expect_identical(tail(vapply(seen$events, function(e) e$type, ""), 1L), "agent_end")
  end = Filter(function(e) identical(e$type, "agent_end"), seen$events)
  expect_length(end, 1L)
  expect_identical(nrow(end[[1L]]$usage), 1L)
  expect_identical(end[[1L]]$usage$request_id, x$s$usage$request_id)
  expect_true(all(is.na(end[[1L]]$usage$input)))
  expect_identical(run$request_ids, x$s$usage$request_id)
  expect_null(run$compact_finish)
  run_abort(run, "repeated")
  expect_identical(nrow(x$s$usage), 1L)
  expect_length(Filter(function(e) identical(e$type, "usage"), seen$events), 1L)
  expect_length(Filter(function(e) identical(e$type, "agent_end"), seen$events), 1L)
  expect_false(isTRUE(session_live(x$s)$compacting))
  after = mcp_dispatch_local(
    mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "restored = TRUE"))),
    x$s)$result
  expect_false(after$isError)
  expect_true(x$home$restored)
})

test_that("a checkpoint settlement failure is diagnosed without replacing the run condition", {
  x = compaction_fixture(list("No request must start."))
  seen = new.env(parent = emptyenv())
  seen$calls = 0L
  seen$cleared = FALSE
  original = gptr_condition("Original synthetic failure.", "internal", "error")
  run = run_start(x$s, msg_user("Continue."))
  run$compact_finish = function() {
    seen$calls = seen$calls + 1L
    seen$cleared = is.null(run$compact_finish)
    run_settle(run, "idle")
    gptr_abort("Synthetic checkpoint charge failure.", "internal")
  }
  run_fail(run, original)
  expect_identical(seen$calls, 1L)
  expect_true(seen$cleared)
  expect_true(run$settled)
  expect_identical(x$s$status, "error")
  expect_identical(run$condition, original)
  expect_identical(session_data(x$s)$condition, original)
  expect_null(session_live(x$s)$run)
  expect_null(run$compact_finish)
  expect_null(run$home)
  expect_length(fake_requests(x$fake), 0L)
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 1L)
  expect_identical(diag$event, "compaction_usage")
  expect_match(diag$message, "checkpoint charge could not be completed", fixed = TRUE)
  expect_match(diag$message, "Synthetic checkpoint charge failure", fixed = TRUE)
})

test_that("synchronous checkpoint cancellation still cancels its returned task exactly once", {
  x = compaction_fixture(list("A response that must not be pumped."))
  seen = new.env(parent = emptyenv())
  seen$id = NULL
  original = provider_stream
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    seen$id = original(model, context, opts, emit, done, run)
    emit(list(type = "start"))
    run_abort(session_live(x$s)$run, "user")
    seen$id
  })
  local_service("compact.should", function(s, tokens, idle) TRUE)
  run = run_start(x$s, msg_user("Continue."))
  run_wait(list(run), timeout = 5)
  expect_identical(x$s$status, "aborted")
  expect_true(rlang::is_string(seen$id))
  expect_false(exists(seen$id, envir = reactor_get()$tasks, inherits = FALSE))
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(run$request_ids, x$s$usage$request_id)
  expect_null(run$compact_finish)
  expect_false(isTRUE(session_live(x$s)$compacting))
  ledger = gptr_usage(x$s, detail = TRUE)
  expect_true(nrow(ledger) > 0L)
  expect_true(all(is.na(ledger$cached)))
  expect_identical(nrow(session_data(x$s)$ledger), nrow(ledger))
})

test_that("manual compaction announces waiting before inference and respects quiet output", {
  local_gptr_options(verbose = 1L, quiet = FALSE)
  seen = new.env(parent = emptyenv())
  seen$notices = character()
  seen$before = FALSE
  x = compaction_fixture(function(request) {
    seen$before = any(grepl("Compacting", seen$notices, fixed = TRUE))
    fake_text("A summary.", delay = 0.02)
  })
  returned = withVisible(withCallingHandlers(compact_run(x$s, "manual"),
                                             gptr_message = function(cnd) {
    seen$notices = c(seen$notices, conditionMessage(cnd))
    invokeRestart("muffleMessage")
  }))
  expect_true(seen$before)
  expect_identical(seen$notices, "Compacting conversation...\n")
  expect_identical(returned$value, x$s)
  expect_false(returned$visible)
  seen$notices = character()
  acknowledgement = withCallingHandlers(cmd_compact("", session_live(x$s)$ctx),
                                          gptr_message = function(cnd) {
    seen$notices = c(seen$notices, conditionMessage(cnd))
    invokeRestart("muffleMessage")
  })
  expect_identical(seen$notices, "Compacting conversation...\n")
  expect_identical(acknowledgement, "Conversation compacted.")
  local_gptr_options(verbose = 0L)
  expect_no_message(compact_run(x$s, "manual"))
  local_gptr_options(verbose = 1L, quiet = TRUE)
  expect_no_message(compact_run(x$s, "manual"))
})

test_that("a failed manual checkpoint preserves its exception and reports unfinished progress", {
  local_gptr_options(verbose = 1L, quiet = FALSE)
  x = compaction_fixture(list("A summary."))
  seen = new.env(parent = emptyenv())
  seen$notices = character()
  original = session_append
  local_mocked_bindings(session_append = function(s, entry, ...) {
    if (identical(entry$type, "compaction")) {
      gptr_abort("Synthetic checkpoint persistence failure.", "internal")
    }
    original(s, entry, ...)
  })
  expect_error(withCallingHandlers(compact_run(x$s, "manual"),
                                   gptr_message = function(cnd) {
    seen$notices = c(seen$notices, conditionMessage(cnd))
    invokeRestart("muffleMessage")
  }), "Synthetic checkpoint persistence failure", fixed = TRUE)
  expect_identical(seen$notices, c("Compacting conversation...\n", "Compaction did not finish.\n"))
  expect_length(compaction_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_false(isTRUE(session_live(x$s)$compacting))
})

test_that("a cancelled compact command never claims that the conversation was compacted", {
  x = compaction_fixture(list("No request expected."))
  off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    list(cancel = TRUE)
  }))
  withr::defer(off())
  text = cmd_compact("", session_live(x$s)$ctx)
  expect_identical(text, "Compaction was cancelled.")
  expect_length(fake_requests(x$fake), 0L)
  expect_length(compaction_entries(x$s), 0L)
  expect_identical(nrow(x$s$usage), 0L)
})

test_that("the checkpoint cannot execute served R and the ordinary tool scope is restored", {
  x = compaction_fixture(list("A tool-free summary."))
  other_home = new.env()
  other = session_new("fake/fake-1", "auto", home = other_home)
  original = provider_stream
  seen = new.env(parent = emptyenv())
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    seen$response = mcp_dispatch_local(
      mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "changed = 99"))),
      x$s)$result
    seen$other = mcp_dispatch_local(
      mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "unrelated = 1"))),
      other)$result
    original(model, context, opts, emit, done, run)
  })
  compact_run(x$s, "manual")
  expect_true(seen$response$isError)
  expect_match(seen$response$content[[1L]]$text, "compaction", fixed = TRUE)
  expect_false(exists("changed", envir = x$home, inherits = FALSE))
  expect_false(seen$other$isError)
  expect_identical(other_home$unrelated, 1)
  expect_false(isTRUE(session_live(x$s)$compacting))
  after = mcp_dispatch_local(
    mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "after = 7"))),
    x$s)$result
  expect_false(after$isError)
  expect_identical(x$home$after, 7)
})

test_that("estimated checkpoint observations retain their provenance", {
  x = compaction_fixture(list(fake_text("An estimated summary.",
    usage = usage_new(input = 80, output = 4, estimated = TRUE))))
  compact_run(x$s, "manual")
  expect_identical(nrow(x$s$usage), 1L)
  expect_true(x$s$usage$estimated)
  expect_equal(x$s$usage$input, 80)
  rebuilt = rebuild_usage(store_read(x$s$file)$entries, session_data(x$s))
  expect_true(rebuilt$estimated)
  expect_identical(rebuilt$request_id, x$s$usage$request_id)
})

test_that("stored checkpoint charges validate counts and bind to their owning session", {
  x = compaction_fixture(list(fake_text("A summary.", usage = usage_new(input = 80, output = 4))))
  compact_run(x$s, "manual")
  entries = store_read(x$s$file)$entries
  at = which(vapply(entries, function(e) identical(e$custom_type, "gptr.compaction_usage"), NA))
  expect_length(at, 1L)
  rebuilt = rebuild_usage(entries, session_data(x$s))
  expect_identical(rebuilt$session, x$s$id)
  expect_true(is.na(rebuilt$parent_id))
  valid_entries = entries
  entries[[at]]$data$row$session = "s0000000000"
  entries[[at]]$data$row$parent_id = "s1111111111"
  expect_error(rebuild_usage(entries, session_data(x$s)), class = "gptr_error_invalid_argument")
  entries = valid_entries
  entries[[at]]$data$row$input = -1
  expect_error(rebuild_usage(entries, session_data(x$s)), class = "gptr_error_invalid_argument")
})

test_that("malformed checkpoint charges fail closed and unrelated custom entries survive", {
  x = compaction_fixture(list("A summary."))
  compact_run(x$s, "manual")
  entries = store_read(x$s$file)$entries
  at = which(vapply(entries, function(e) identical(e$custom_type, "gptr.compaction_usage"), NA))
  expect_length(at, 1L)
  multiple = entries[[at]]$data$row
  multiple$input = c(1, 2)
  for (row in list(NULL, "broken", list(), list(request_id = NULL),
                   list(request_id = NA_character_), list(request_id = c("qone", "qtwo")),
                   multiple)) {
    broken = entries
    broken[[at]]$data$row = row
    expect_error(rebuild_usage(broken, session_data(x$s)), class = "gptr_error_invalid_argument")
  }
  broken = entries
  broken[[at]]$data = "broken"
  expect_error(rebuild_usage(broken, session_data(x$s)), class = "gptr_error_invalid_argument")
  unrelated = entries
  unrelated[[at]]$custom_type = "example.unrelated"
  unrelated[[at]]$data = NULL
  expect_identical(nrow(rebuild_usage(unrelated, session_data(x$s))), 0L)
})

test_that("compaction preserves loaded R objects and continuation uses them directly", {
  x = compaction_fixture(list("Remember the fitted public-data coefficients.",
                              fake_tool("r", code = "gptr_return(beta)"), "done"))
  x$home$beta = unname(stats::coef(stats::lm(mpg ~ wt, data = x$home$d)))
  before = serialize(list(d = x$home$d, beta = x$home$beta), NULL)
  call = block_tool_call("fit-public", "r", list(code = "beta = coef(lm(mpg ~ wt, data = d))"))
  session_append(x$s, list(type = "message", message = msg_assistant(list(call),
    api = "fake", provider = "fake", model = "fake-1", stop_reason = "tool_use")))
  session_append(x$s, list(type = "message", message = msg_tool_result("fit-public", "r", "ok",
    details = list(code = call$arguments$code, status = "ok"))))
  original = session_data(x$s)$entries
  compact_run(x$s, "manual")
  expect_identical(session_data(x$s)$entries[seq_along(original)], original)
  checkpoint = compaction_entries(x$s)[[1L]]
  expect_null(checkpoint$first_kept_entry_id)
  expect_match(checkpoint$gptr$state$objects$beta, "beta = coef", fixed = TRUE)
  session_run(x$s, msg_user("Return the existing beta vector."), list(max_turns = 3L))
  expect_identical(x$s$status, "idle")
  expect_equal(x$s$value, x$home$beta)
  expect_identical(serialize(list(d = x$home$d, beta = x$home$beta), NULL), before)
  expect_length(fake_requests(x$fake), 3L)
  expect_identical(nrow(x$s$usage), 3L)
})

test_that("a child's checkpoint attempt consumes its root's shared budget", {
  x = compaction_fixture(list(fake_text("A child summary.",
                                        usage = usage_new(input = 100, output = 5))))
  child = session_new("fake/fake-1", "auto", home = x$home, kind = "child", parent = x$s)
  local_service("compact.should", function(s, tokens, idle) TRUE)
  run = run_start(child, msg_user("Continue child work."),
                  list(root = x$s$id, budget = list(turns = 1L)))
  run_wait(list(run), timeout = 5)
  expect_identical(child$status, "budget")
  expect_length(fake_requests(x$fake), 1L)
  expect_identical(nrow(child$usage), 1L)
  expect_identical(nrow(x$s$usage), 1L)
  expect_identical(x$s$usage$request_id, child$usage$request_id)
  expect_identical(x$s$usage$session, child$id)
  expect_null(session_live(child)$run)
})

test_that("a refused checkpoint restores its tool scope without inventing a request charge", {
  x = compaction_fixture(list("unused"))
  local_gptr_options(verbose = 1L, quiet = FALSE)
  local_mocked_bindings(provider_stream = function(...) stop("synthetic provider unavailable"))
  notices = new.env(parent = emptyenv())
  notices$text = character()
  withCallingHandlers(compact_run(x$s, "manual"), gptr_message = function(cnd) {
    notices$text = c(notices$text, conditionMessage(cnd))
    invokeRestart("muffleMessage")
  })
  expect_false(isTRUE(session_live(x$s)$compacting))
  expect_identical(nrow(x$s$usage), 0L)
  expect_length(fake_requests(x$fake), 0L)
  expect_length(compaction_entries(x$s), 1L)
  expect_identical(notices$text, "Compacting conversation...\n")
  expect_match(compaction_entries(x$s)[[1L]]$summary, "No model summary", fixed = TRUE)
})

test_that("the JSONL sink records checkpoint request and usage without exposing its summary", {
  x = compaction_fixture(list(fake_text("INTERNAL_SYNTHETIC_SUMMARY",
                                        usage = usage_new(input = 50, output = 3))))
  local_service("compact.should", function(s, tokens, idle) TRUE)
  path = withr::local_tempfile(fileext = ".jsonl")
  con = file(path, "wb")
  withr::defer(close(con))
  off = jsonl_sink(x$s, con)
  withr::defer(off())
  run = run_start(x$s, msg_user("Continue."), list(budget = list(turns = 1L)))
  run_wait(list(run), timeout = 5)
  lines = readLines(path, warn = FALSE, encoding = "UTF-8")
  events = lapply(lines, json_decode)
  requests = Filter(function(e) identical(e$type, "before_request"), events)
  usage = Filter(function(e) identical(e$type, "usage"), events)
  expect_length(requests, 1L)
  expect_length(usage, 1L)
  expect_identical(requests[[1L]]$request_id, x$s$usage$request_id)
  expect_identical(usage[[1L]]$row[[1L]]$request_id, x$s$usage$request_id)
  expect_identical(usage[[1L]]$row[[1L]]$input, 50L)
  expect_identical(usage[[1L]]$run, run$id)
  expect_true(is.character(usage[[1L]]$row[[1L]]$started))
  expect_false(any(grepl("INTERNAL_SYNTHETIC_SUMMARY", lines, fixed = TRUE)))
})

test_that("compaction event fixtures remove every hook on return and error", {
  reg = local_registry()
  user_env = new.env(parent = baseenv())
  user_env$marker = "unrelated user hook"
  user = eval(parse(text = "function(event, ctx) marker", keep.source = TRUE), user_env)
  user_attributes = attributes(user)
  user_body = body(user)
  spec = gptr_hook("turn_end", user)
  off = gptr_register(spec)
  withr::defer(off())
  types = c("before_request", "usage", "session_compact", "agent_end")
  for (abort in c(FALSE, TRUE)) {
    before = as.list(reg$recs, all.names = TRUE)
    invoke = function() {
      seen = compaction_events(types)
      ids = setdiff(ls(reg$recs, all.names = TRUE), names(before))
      expect_length(ids, length(types))
      hooks = lapply(ids, get, envir = reg$recs, inherits = FALSE)
      expect_setequal(vapply(hooks, function(rec) rec$spec$event, ""), types)
      for (type in types) {
        hook = Filter(function(rec) identical(rec$spec$event, type), hooks)
        expect_length(hook, 1L)
        hook[[1L]]$spec$handler(list(type = type), NULL)
      }
      expect_identical(vapply(seen$events, function(event) event$type, ""), types)
      if (abort) stop("fixture exit", call. = FALSE)
      invisible(NULL)
    }
    if (abort) {
      expect_error(invoke(), "fixture exit", fixed = TRUE)
    } else {
      invoke()
    }
    expect_identical(as.list(reg$recs, all.names = TRUE), before)
  }
  expect_identical(registry_all("hook")[[spec$name]]$handler, user)
  expect_identical(attributes(user), user_attributes)
  expect_identical(body(user), user_body)
  expect_identical(environment(user), user_env)
  expect_s3_class(attr(user, "srcref"), "srcref")
  expect_identical(user(NULL, NULL), "unrelated user hook")
})
