source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- the pure state machine

reply_text = function(text = "ok", stop = "stop") {
  list(role = "assistant", content = list(list(type = "text", text = text)), stop_reason = stop)
}
reply_tool = function(name = "t", stop = "tool_use") {
  list(role = "assistant", stop_reason = stop,
       content = list(list(type = "tool_call", id = "c1", name = name, arguments = list())))
}
drive = function(lp, replies, terminate = FALSE) {
  actions = character()
  n = 0L
  repeat {
    act = loop_next(lp)
    actions = c(actions, act$action)
    if (identical(act$action, "end")) return(list(reason = act$reason, actions = actions,
                                                  requests = n))
    if (identical(act$action, "request")) {
      n = n + 1L
      loop_response(lp, replies[[min(n, length(replies))]])
    }
    if (identical(act$action, "tools")) loop_results(lp, list("r"), terminate)
  }
}
event_log = function() {
  log = new.env()
  log$types = character()
  log$emit = function(type, ...) log$types = c(log$types, type)
  log
}

test_that("a text reply ends the loop after one request and one turn_end", {
  ev = event_log()
  lp = loop_new(emit = ev$emit)
  expect_s3_class(lp, "gptr_loop")
  out = drive(lp, list(reply_text()))
  expect_identical(out$reason, "stop")
  expect_identical(out$requests, 1L)
  expect_identical(ev$types, "turn_end")
})

test_that("a tool reply asks for tools, then a second turn starts with turn_start", {
  ev = event_log()
  out = drive(loop_new(emit = ev$emit), list(reply_tool(), reply_text()))
  expect_identical(out$actions, c("request", "tools", "request", "end"))
  expect_identical(ev$types, c("turn_end", "turn_start", "turn_end"))
})

test_that("while a response is outstanding the loop waits", {
  lp = loop_new()
  expect_identical(loop_next(lp)$action, "request")
  expect_identical(loop_next(lp)$action, "wait")
})

test_that("steering is polled at the start and after each turn; follow-ups only when stopping", {
  queues = new.env()
  queues$steer = list(list(role = "operator", kind = "steer_relay"))
  queues$follow = list(list(role = "user", source = "follow_up"))
  queues$polled = character()
  take = function(which) {
    function() {
      queues$polled = c(queues$polled, which)
      x = queues[[which]]
      queues[[which]] = list()
      x
    }
  }
  lp = loop_new(steering = take("steer"), follow_up = take("follow"))
  sent = list()
  repeat {
    act = loop_next(lp)
    if (identical(act$action, "end")) break
    if (identical(act$action, "request")) {
      sent[[length(sent) + 1L]] = act$messages
      loop_response(lp, reply_text())
    }
  }
  expect_identical(queues$polled[1:3], c("steer", "steer", "follow"))
  expect_length(sent, 2L)
  expect_identical(sent[[1L]][[1L]]$role, "operator")
  expect_identical(sent[[2L]][[1L]]$source, "follow_up")
})

test_that("max_turns caps the requests of a run", {
  out = drive(loop_new(max_turns = 3L), list(reply_tool()))
  expect_identical(out$reason, "max_turns")
  expect_identical(out$requests, 3L)
})

test_that("a batch whose results all terminate ends the run without another request", {
  out = drive(loop_new(), list(reply_tool(), reply_text()), terminate = TRUE)
  expect_identical(out$reason, "stop")
  expect_identical(out$requests, 1L)
})

test_that("error and aborted responses end the loop after turn_end", {
  ev = event_log()
  out = drive(loop_new(emit = ev$emit), list(reply_text(stop = "error")))
  expect_identical(out$reason, "error")
  expect_identical(ev$types, "turn_end")
  expect_identical(drive(loop_new(), list(reply_text(stop = "aborted")))$reason, "aborted")
})

test_that("length and refusal stops mark the tool batch truncated", {
  lp = loop_new()
  loop_next(lp)
  loop_response(lp, reply_tool(stop = "length"))
  act = loop_next(lp)
  expect_identical(act$action, "tools")
  expect_true(act$truncated)
})

test_that("finish_turn can end the loop with a reason", {
  out = drive(loop_new(finish_turn = function(turn) list(action = "end", reason = "blocked")),
              list(reply_tool()))
  expect_identical(out$reason, "blocked")
  expect_identical(out$requests, 1L)
})

test_that("queue items become relays, user messages, extension notes and agent reports (IC-55)", {
  it = function(source, name = NULL) {
    list(text = "use TPM", blocks = list(), source = source, name = name, t = 0)
  }
  relay = queue_item_message(it("pipe"), "steer", relay = TRUE)
  expect_identical(relay$role, "operator")
  expect_identical(relay$kind, "steer_relay")
  expect_identical(msg_text(relay), "The user sent this message while you were working: use TPM")
  expect_identical(queue_item_message(it("pipe"), "steer", relay = FALSE)$role, "user")
  expect_identical(queue_item_message(it("repl"), "follow_up", relay = TRUE)$source, "follow_up")
  ext = queue_item_message(it("extension", "panel"), "steer", relay = TRUE)
  expect_identical(ext$role, "user")
  expect_identical(msg_text(ext), "Extension panel sent this note (not from the user): use TPM")
  rep = queue_item_message(it("agent", "stats"), "steer", relay = TRUE)
  expect_identical(rep$source, "agent")
  expect_identical(rep$content[[1L]]$type, "context")
  expect_match(rep$content[[1L]]$text, "<agent_report from=\"stats\">", fixed = TRUE)
})

test_that("request caps preserve queued input that cannot be delivered", {
  polls = character()
  take = function() {
    polls <<- c(polls, "steer")
    list(msg_user("queued"))
  }
  lp = loop_new(max_turns = 0L, steering = take)
  expect_identical(loop_next(lp)$reason, "max_turns")
  expect_length(polls, 0L)
  lp = loop_new(max_turns = 1L, steering = take, follow_up = take)
  loop_next(lp)
  loop_response(lp, reply_tool())
  loop_next(lp)
  loop_results(lp, list(msg_tool_result("c1", "t", "done")))
  expect_identical(loop_next(lp)$reason, "max_turns")
  expect_identical(polls, "steer")
})

test_that("tools finish in source order before steering or follow-ups are polled", {
  log = character()
  append_log = function(x) log <<- c(log, x)
  lp = loop_new(steering = function() {
      append_log("steer")
      list()
    },
    follow_up = function() {
      append_log("follow_up")
      list()
    },
    finish_turn = function(turn) {
      append_log("finish")
      NULL
    },
    emit = function(type, ...) append_log(type))
  loop_next(lp)
  calls = list(block_tool_call("b", "second", list()), block_tool_call("a", "first", list()))
  reply = reply_tool()
  reply$content = c(list(block_text("before")), calls, list(block_text("after")))
  loop_response(lp, reply)
  expect_identical(loop_next(lp)$calls, calls)
  expect_identical(loop_next(lp)$action, "wait")
  expect_identical(log, "steer")
  results = list(msg_tool_result("b", "second", "B"), msg_tool_result("a", "first", "A"))
  loop_results(lp, results, terminate = TRUE)
  expect_identical(loop_next(lp)$action, "end")
  expect_identical(lp$results, results)
  expect_identical(log, c("steer", "finish", "turn_end", "steer", "follow_up"))
})

test_that("failure preserves the partial message and never dispatches its tool calls", {
  for (reason in c("error", "aborted")) {
    partial = reply_tool(stop = reason)
    seen = NULL
    lp = loop_new(finish_turn = function(turn) {
      seen <<- turn
      NULL
    })
    loop_next(lp)
    loop_response(lp, partial)
    expect_identical(loop_next(lp), list(action = "end", reason = reason))
    expect_identical(seen$message, partial)
    expect_identical(seen$results, list())
    expect_identical(lp$turn, 1L)
  }
})

test_that("late callbacks cannot reopen a settled loop", {
  lp = loop_new()
  loop_next(lp)
  loop_end(lp, "aborted")
  loop_response(lp, reply_tool())
  loop_results(lp, list(), terminate = FALSE)
  expect_identical(loop_next(lp), list(action = "end", reason = "aborted"))
  expect_identical(lp$turn, 1L)
})

test_that("callbacks reject out-of-order delivery", {
  lp = loop_new()
  expect_error(loop_response(lp, reply_text()), class = "gptr_error_internal")
  loop_next(lp)
  expect_error(loop_results(lp, list()), class = "gptr_error_internal")
  loop_response(lp, reply_text())
  expect_error(loop_response(lp, reply_tool()), class = "gptr_error_internal")
})

test_that("reentrant event callbacks cannot issue duplicate requests", {
  nested = list()
  lp = loop_new(emit = function(type, ...) {
    nested[[length(nested) + 1L]] <<- loop_next(lp)
  })
  out = drive(lp, list(reply_tool(), reply_text()))
  expect_identical(out$requests, 2L)
  expect_true(all(vapply(nested, function(x) identical(x$action, "wait"), TRUE)))
  expect_identical(loop_next(lp)$reason, "stop")
})

test_that("a boundary callback may settle the loop without losing its reason", {
  lp = loop_new(finish_turn = function(turn) {
    loop_end(lp, "budget")
    NULL
  })
  out = drive(lp, list(reply_tool()))
  expect_identical(out$reason, "budget")
  expect_identical(out$requests, 1L)
})

test_that("follow-ups are consumed one at a time and text stop at cap leaves queues alone", {
  pending = list(msg_user("one"), msg_user("two"))
  take = function() {
    if (!length(pending)) return(list())
    next_item = pending[1L]
    pending <<- pending[-1L]
    next_item
  }
  out = drive(loop_new(follow_up = take), list(reply_text()))
  expect_identical(out$requests, 3L)
  expect_length(pending, 0L)
  pending = list(msg_user("saved"))
  out = drive(loop_new(max_turns = 1L, follow_up = take), list(reply_text()))
  expect_identical(out$requests, 1L)
  expect_identical(out$reason, "stop")
  expect_length(pending, 1L)
})

test_that("both truncation reasons mark tool batches; user-source steers become relays", {
  for (reason in c("length", "refusal")) {
    lp = loop_new()
    loop_next(lp)
    loop_response(lp, reply_tool(stop = reason))
    expect_true(loop_next(lp)$truncated)
  }
  for (source in c("pipe", "pause_menu", "repl", "api_user")) {
    item = list(text = "hello", source = source)
    expect_identical(queue_item_message(item, "steer", TRUE)$role, "operator")
    expect_identical(queue_item_message(item, "follow_up", TRUE)$role, "user")
  }
})

test_that("steering relays retain text blocks; follow-ups keep attachments", {
  item = list(text = "hello", source = "pipe", blocks = list(block_text("extra")))
  relay = queue_item_message(item, "steer", TRUE)
  expect_identical(relay$content[[1L]], item$blocks[[1L]])
  expect_identical(relay$origin_text, "hello")
  item$blocks = list(block_image("YQ==", "image/png"))
  expect_identical(queue_item_message(item, "follow_up", TRUE)$content[[1L]], item$blocks[[1L]])
})

# ---------------------------------------------------------------- report 02 section 5.1 (24 checks)

loop_recs = oracle("loop")

test_that(oracle_title(loop_recs, "L01"), {
  local_permissive()
  local_fake_provider(list("Hello from gptr!"))
  s = test_session()
  run_text(s, "Hi")
  expect_identical(roles(s), c("user", "assistant"))
})

test_that(oracle_title(loop_recs, "L02"), {
  local_permissive()
  local_fake_provider(list(fake_text("Hello from gptr! A longer answer.", chunk = 8L)))
  updates = local_events("message_update")
  s = test_session()
  run_text(s, "Hi")
  expect_identical(s$text, "Hello from gptr! A longer answer.")
  expect_gt(length(updates(s)), 1L)
  expect_identical(paste(vapply(updates(s), function(e) e$delta, ""), collapse = ""), s$text)
})

test_that(oracle_title(loop_recs, "L03"), {
  local_permissive()
  local_fake_provider(list("Hello"))
  s = test_session()
  run_text(s, "Hi")
  expect_identical(s$status, "idle")
})

test_that(oracle_title(loop_recs, "L04"), {
  local_permissive()
  add_tool()
  local_tool("boom", function(input, ctx) stop("kaboom: file not found"))
  local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 2, b = 3)),
                                      list(name = "boom", input = json_obj()),
                                      list(name = "nope", input = json_obj()),
                                      list(name = "add", input = list(a = 1))),
                           "Done: 5"))
  s = test_session()
  run_text(s, "compute")
  expect_length(tool_results(s), 4L)
})

test_that(oracle_title(loop_recs, "L05"), {
  local_permissive()
  add_tool()
  local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 2, b = 3)),
                                      list(name = "add", input = list(a = 2, b = "3"))),
                           "ok"))
  s = test_session()
  run_text(s, "compute")
  tr = tool_results(s)
  expect_identical(msg_text(tr[[1L]]), "5")
  expect_false(tr[[1L]]$is_error)
  expect_true(tr[[2L]]$is_error)
  expect_match(msg_text(tr[[2L]]), "^Invalid arguments for add")
})

test_that(oracle_title(loop_recs, "L06"), {
  local_permissive()
  local_tool("boom", function(input, ctx) stop("kaboom: file not found"))
  local_fake_provider(list(fake_tool("boom"), "ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "kaboom: file not found", fixed = TRUE)
})

test_that(oracle_title(loop_recs, "L07"), {
  local_permissive()
  local_fake_provider(list(fake_tool("nope"), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]), "Tool nope not found")
})

test_that(oracle_title(loop_recs, "L08"), {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("add", function(input, ctx) {
    ran$yes = TRUE
    "x"
  }, parameters = num_schema(a = "number", b = "number"))
  local_fake_provider(list(fake_tool("add", a = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "^Invalid arguments for add: .*b")
  expect_false(ran$yes)
})

test_that(oracle_title(loop_recs, "L09"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 1, b = 2)),
                                             list(name = "add", input = list(a = 3, b = 4))),
                                  "done"))
  run_text(test_session(), "go")
  expect_length(fake_requests(fake), 2L)
})

test_that(oracle_title(loop_recs, "L10"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 1, b = 1)),
                                             list(name = "add", input = list(a = 1, b = 2)),
                                             list(name = "add", input = list(a = 1, b = 3)),
                                             list(name = "add", input = list(a = 1, b = 4))),
                                  "done"))
  run_text(test_session(), "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", rep("tool_result", 4L)))
  expect_identical(vapply(req$messages[3:6], msg_text, ""), c("2", "3", "4", "5"))
})

test_that(oracle_title(loop_recs, "L11"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_identical(roles(box$s), c("user", "assistant", "tool_result", "operator", "assistant",
                                   "operator", "assistant", "user", "assistant"))
})

test_that(oracle_title(loop_recs, "L12"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  txt = vapply(box$s$messages, msg_text, "")
  expect_match(txt[[4L]], "STEER-1", fixed = TRUE)
  expect_match(txt[[6L]], "STEER-2", fixed = TRUE)
  expect_match(txt[[8L]], "FOLLOWUP", fixed = TRUE)
})

test_that(oracle_title(loop_recs, "L13"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  fake = local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  reqs = fake_requests(fake)
  expect_length(reqs, 4L)
  last_role = vapply(reqs[2:3], function(r) r$messages[[length(r$messages)]]$role, "")
  expect_identical(last_role, c("operator", "operator"))
})

test_that(oracle_title(loop_recs, "L14"), {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("w", function(input, ctx) {
    ran$yes = TRUE
    "x"
  })
  local_fake_provider(list(c(fake_tool("w"), list(stop = "length")), "retry ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_false(ran$yes)
  expect_true(tr$is_error)
  expect_identical(msg_text(tr), paste0("Tool call not executed: the response stopped (length) ",
                                        "before the call was complete."))
})

test_that(oracle_title(loop_recs, "L15"), {
  local_permissive()
  add_tool()
  local_hook("tool_call", function(event, ctx) {
    list(decision = "block", reason = "denied by permission mode")
  })
  local_fake_provider(list(fake_tool("add", a = 1, b = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]),
                   "Tool execution was blocked: denied by permission mode")
})

test_that(oracle_title(loop_recs, "L16"), {
  local_permissive()
  local_tool("stopper", function(input, ctx) {
    res = gptr_tool_result("final")
    res$terminate = TRUE
    res
  })
  fake = local_fake_provider(list(fake_tool("stopper"), "unused"))
  s = test_session()
  run_text(s, "go")
  expect_length(fake_requests(fake), 1L)
  expect_identical(s$status, "idle")
})

test_that(oracle_title(loop_recs, "L17"), {
  local_permissive()
  add_tool()
  local_hook("tool_result", function(event, ctx) {
    list(content = list(block_text(paste0("[audited] ", event$content[[1L]]$text))))
  })
  local_fake_provider(list(fake_tool("add", a = 1, b = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]), "[audited] 2")
})

test_that(oracle_title(loop_recs, "L18"), {
  local_permissive()
  x = interrupting_run()
  expect_identical(x$res, "interrupted")
  expect_identical(x$s$status, "aborted")
  expect_length(fake_requests(x$fake), 1L)
})

test_that(oracle_title(loop_recs, "L19"), {
  local_permissive()
  x = interrupting_run()
  tr = tool_results(x$s)
  expect_length(tr, 1L)
  expect_match(msg_text(tr[[1L]]),
               "^Interrupted after [0-9.]+ s; side effects may have occurred[.]$")
})

test_that(oracle_title(loop_recs, "L20"), {
  local_permissive()
  x = interrupting_run()
  expect_null(session_live(x$s)$run)
  run_text(x$s, "continue")
  expect_identical(x$s$status, "idle")
  expect_identical(x$s$text, "after the interrupt")
  req = fake_requests(x$fake)[[2L]]
  ids = vapply(Filter(function(m) identical(m$role, "tool_result"), req$messages),
               function(m) m$tool_call_id, "")
  expect_length(ids, 2L)
})

test_that(oracle_title(loop_recs, "L21"), {
  local_permissive()
  local_fake_provider(list(fake_error("400 invalid request: bad parameter", status = 400L)))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "error")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_provider")
  expect_match(conditionMessage(cnd), "bad parameter", fixed = TRUE)
  expect_identical(cnd$session, session_data(s)$id)
})

test_that(oracle_title(loop_recs, "L22"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tool("add", a = 1, b = 1)))
  s = test_session()
  run_text(s, "loop forever", list(max_turns = 3L))
  expect_identical(s$status, "max_turns")
  expect_length(fake_requests(fake), 3L)
  expect_s3_class(session_data(s)$condition, "gptr_error_max_turns")
  expect_identical(session_data(s)$condition$max_turns, 3L)
})

test_that(oracle_title(loop_recs, "L23"), {
  local_permissive()
  local_hook("message_end", function(event, ctx) stop("listener bug"))
  local_fake_provider(list("fine"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "idle")
  expect_identical(s$text, "fine")
})

test_that(oracle_title(loop_recs, "L24"), {
  local_permissive()
  box = new.env()
  local_tool("re", function(input, ctx) {
    box$err = tryCatch({
      run_start(box$s, msg_user("nested"))
      "no error"
    }, error = function(e) e)
    "ok"
  })
  local_fake_provider(list(fake_tool("re"), "x"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_s3_class(box$err, "gptr_error_busy")
})

test_that("every report 02 loop check has a test", {
  expect_oracles_covered(loop_recs, "test-agent-loop.R")
})
