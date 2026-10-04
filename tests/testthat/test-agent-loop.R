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

test_that("invalid request caps fail explicitly without truncation or warnings", {
  for (cap in list(-1L, 1.5, NA_real_, Inf, c(1L, 2L), "3", TRUE, 2147483648)) {
    expect_error(loop_new(max_turns = cap), class = "gptr_error_invalid_argument")
  }
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

test_that("both truncation reasons mark tool batches and invalid sources fail closed", {
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
  expect_error(queue_item_message(list(text = "hi", source = "unknown"), "steer"),
               class = "gptr_error_invalid_argument")
})

test_that("steering relays retain text blocks and refuse unsupported attachments", {
  item = list(text = "hello", source = "pipe", blocks = list(block_text("extra")))
  relay = queue_item_message(item, "steer", TRUE)
  expect_identical(relay$content[[1L]], item$blocks[[1L]])
  expect_identical(relay$origin_text, "hello")
  item$blocks = list(block_image("YQ==", "image/png"))
  expect_error(queue_item_message(item, "steer", TRUE), class = "gptr_error_invalid_argument")
  expect_identical(queue_item_message(item, "follow_up", TRUE)$content[[1L]], item$blocks[[1L]])
})
