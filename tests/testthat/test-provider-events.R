# Events and the accumulator (Task 14; INFRA-02, INFRA-23).

test_that("ev_new() fills the common fields and keeps NULL-valued fields", {
  ev = ev_new("text_delta", index = 1L, delta = "hi", response_id = NULL)
  expect_identical(
    names(ev),
    c("type", "session", "run", "agent", "turn", "ts", "index", "delta", "response_id")
  )
  expect_identical(ev$agent, "main")
  expect_true(is.numeric(ev$ts))
  expect_true("response_id" %in% names(ev))
  expect_identical(ev_new("start", session = "s1", agent = "child")$session, "s1")
  expect_error(ev_new("x", 1), class = "gptr_error_invalid_argument")
})

stream_events = function() {
  list(
    ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1",
           response_id = "r1"),
    ev_new("thinking_start", index = 1L),
    ev_new("thinking_delta", index = 1L, delta = "let me "),
    ev_new("thinking_delta", index = 1L, delta = "think"),
    ev_new("thinking_end", index = 1L, block = block_thinking("let me think", signature = "sig")),
    ev_new("text_start", index = 2L),
    ev_new("text_delta", index = 2L, delta = "caf"),
    ev_new("text_delta", index = 2L, delta = "\u00e9 ok"),
    ev_new("toolcall_start", index = 3L, id = "c1", name = "r"),
    ev_new("toolcall_delta", index = 3L, delta = "{\"code\": \"1 +", preview = NULL),
    ev_new("toolcall_delta", index = 3L, delta = " 1\"}", preview = NULL)
  )
}

test_that("the accumulator builds the partial message from deltas", {
  acc = acc_new()
  for (ev in stream_events()) acc$push(ev)
  msg = acc$message(stop_reason = "aborted")
  expect_identical(msg$stop_reason, "aborted")
  expect_identical(msg$request_id, "q1")
  expect_identical(msg$content[[1]]$signature, "sig")
  expect_identical(msg$content[[2]], block_text("caf\u00e9 ok"))
  expect_identical(msg$content[[3]]$arguments, list(code = "1 + 1"))
  expect_identical(msg$content[[3]]$raw_arguments, "{\"code\": \"1 + 1\"}")
})

test_that("the accumulator returns the terminal message once `done` arrives", {
  acc = acc_new()
  final = msg_assistant("done", "fake", "fake", "fake-1")
  acc$push(ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1"))
  acc$push(ev_new("done", reason = "stop", message = final, usage = NULL))
  expect_identical(acc$message(), final)
})

test_that("100,000 deltas accumulate in linear time (INFRA-23)", {
  # Linear accumulation takes well under 1 s here; a buffer list copied on every delta (quadratic)
  # takes about 1.7 s for 20,000 deltas and about 40 s for 100,000, far above the 5 s bound
  acc = acc_new()
  acc$push(ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1"))
  acc$push(ev_new("text_start", index = 1L))
  delta = ev_new("text_delta", index = 1L, delta = "token ")
  elapsed = system.time(for (i in 1:100000) acc$push(delta))[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_identical(nchar(msg_text(acc$message())), 100000L * 6L)
})

test_that("partial blocks can arrive without their start event", {
  acc = acc_new()
  acc$push(ev_new("text_delta", index = 2L, delta = "partial"))
  acc$push(ev_new("thinking_end", index = 3L, block = block_thinking("done", "sig")))
  expect_identical(
    acc$message()$content, list(block_text("partial"), block_thinking("done", "sig"))
  )
})

test_that("an error terminal event preserves its partial message", {
  acc = acc_new()
  final = msg_assistant("partial", "fake", "fake", "fake-1", stop_reason = "error",
                        error_message = "interrupted")
  acc$push(ev_new("error", reason = "error", message = final))
  expect_identical(acc$message(), final)
})
