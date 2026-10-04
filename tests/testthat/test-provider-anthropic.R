# Tests for R/provider-anthropic.R (plan P12): the shared normaliser core, the
# anthropic-messages normaliser and request body, and check_adapter().
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "anthropic-messages"

# ---- the normaliser (Task 1) -----------------------------------------------------------------

test_that("anthropic fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, anthropic_normaliser)
})

test_that("every anthropic fixture has one start first and one terminal event last", {
  for (case in c("text", "thinking_tools", "error_midstream", "truncated", "refusal",
                 "server_tool")) {
    expect_one_terminal(replay_case(api, anthropic_normaliser, case)$events)
  }
})

test_that("anthropic events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("text", "thinking_tools", "truncated")) {
    expect_chunk_invariant(api, anthropic_normaliser, case)
  }
})

test_that("text is UTF-8 and usage splits 5-minute and 1-hour cache writes", {
  r = replay_case(api, anthropic_normaliser, "text")
  expect_identical(Encoding(r$message$content[[1L]]$text), "UTF-8")
  expect_match(r$message$content[[1L]]$text, "caf\u00e9 \u2014 \U0001F600", fixed = TRUE)
  u = replay_case(api, anthropic_normaliser, "thinking_tools")$message$usage
  expect_identical(c(u$cache_write_5m, u$cache_write_1h, u$reasoning), c(200, 1000, 61))
})

test_that("unreported usage stays unknown and cost needs price evidence (IC-74)", {
  # no usage was ever reported: unknown counters and cost, never a known zero
  n = anthropic_normaliser(test_model(api), list(emit = function(ev) NULL))
  n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}'
  )))
  u = n$message()$usage
  expect_identical(c(u$input, u$output, u$cache_read, u$total), rep(NA_real_, 4L))
  expect_identical(u$cost$total, NA_real_)
  # reported tokens without prices: the tokens are known, the charge is not
  u = replay_case(api, anthropic_normaliser, "text")$message$usage
  expect_identical(c(u$input, u$output, u$total), c(12, 9, 21))
  expect_identical(u$cost$total, NA_real_)
  # a declared zero rate (a local model) gives a known zero charge; real rates are applied
  run = function(prices) {
    n = anthropic_normaliser(test_model(api, prices = prices), list(emit = function(ev) NULL))
    n$push(list(event = "message_start", data = paste0(
      '{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1000000,',
      '"output_tokens":1}}}'
    )))
    n$push(list(event = "message_delta", data = paste0(
      '{"type":"message_delta","delta":{"stop_reason":"end_turn"},',
      '"usage":{"output_tokens":2000000}}'
    )))
    n$push(list(event = "message_stop", data = '{"type":"message_stop"}'))
    n$message()$usage$cost
  }
  free = run(list(list(from = "2000-01-01", input = 0, output = 0)))
  expect_identical(free$total, 0)
  paid = run(list(list(from = "2000-01-01", input = 3, output = 15)))
  expect_equal(c(paid$input, paid$output, paid$total), c(3, 30, 33))
})

test_that("a server error event and a truncated stream each end with one error and the partial", {
  err = replay_case(api, anthropic_normaliser, "error_midstream")
  last = err$events[[length(err$events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "overloaded")
  expect_identical(last$message$stop_reason, "error")
  expect_identical(last$message$content[[1L]]$text, "Partial ans")
  cut = replay_case(api, anthropic_normaliser, "truncated")
  last = cut$events[[length(cut$events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "network")
  expect_identical(last$message$content[[1L]]$raw_arguments,
                   "{\"path\": \"a.R\", \"content\": \"x = ")
})

test_that("an overload before any delta asks the transport to retry instead of failing", {
  log = event_log()
  retried = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  n$push(list(event = "message_start", data = paste0(
    '{"type":"message_start","message":{"id":"msg_r","model":"fixture-1",',
    '"usage":{"input_tokens":5,"output_tokens":1}}}'
  )))
  expect_false(n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
  ))))
  expect_length(retried$events, 1L)
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_identical(retried$events[[1L]]$status, 529L)
  expect_length(log$events, 0L)
  msg = n$finish()
  expect_identical(msg$stop_reason, "error")
  expect_identical(types_of(log$events), c("start", "error"))
  # the transport gives up on the retry (attempts used up): the provider's text is reported
  log2 = event_log()
  n2 = anthropic_normaliser(test_model(api), list(emit = log2$emit, retry = retried$emit))
  n2$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
  )))
  gave_up = structure(class = c("gptr_error_overloaded", "gptr_error_provider", "gptr_error",
                                "error", "condition"),
                      list(message = "The provider reported a retryable failure (overloaded).",
                           call = NULL, status = 529L))
  msg = n2$fail(gave_up)
  expect_identical(msg$error_message, "overloaded_error: Overloaded")
  expect_identical(log2$events[[2L]]$error$class, "overloaded")
  expect_identical(log2$events[[2L]]$error$status, 529L)
})

test_that("a spend-cap error is never retried (report 07 section 2.11)", {
  log = event_log()
  retried = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  done = n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"rate_limit_error","message":"cap",',
    '"details":{"error_code":"enforced_spend_limit_reached"}}}'
  )))
  expect_true(done)
  expect_length(retried$events, 0L)
  expect_identical(log$events[[2L]]$error$class, "spend_cap")
})

test_that("push() reports the stream complete when the transport refuses a retry at once", {
  log = event_log()
  n = NULL
  gave_up = structure(class = c("gptr_error_overloaded", "gptr_error_provider", "gptr_error",
                                "error", "condition"),
                      list(message = "The provider reported a retryable failure (overloaded).",
                           call = NULL, status = 529L))
  n = anthropic_normaliser(test_model(api),
                           list(emit = log$emit, retry = function(info) n$fail(gave_up)))
  expect_true(n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
  ))))
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(n$message()$error_message, "overloaded_error: Overloaded")
})

test_that("non-string error types and stop reasons are never matched by position (04 4.2)", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  expect_true(n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":5,"message":"odd"}}'
  ))))
  expect_identical(log$events[[2L]]$error$class, "provider")
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  n$push(list(event = "message_delta", data = paste0(
    '{"type":"message_delta","delta":{"stop_reason":2},"usage":{"output_tokens":3}}'
  )))
  n$push(list(event = "message_stop", data = '{"type":"message_stop"}'))
  msg = n$message()
  expect_identical(msg$stop_reason, "error")
  expect_identical(msg$raw_stop_reason, "2")
  expect_identical(types_of(log$events), c("start", "error"))
})

test_that("a reported null usage field is unknown; an omitted one keeps P05's zero (IC-74)", {
  n = anthropic_normaliser(test_model(api), list(emit = function(ev) NULL))
  n$push(list(event = "message_start", data = paste0(
    '{"type":"message_start","message":{"id":"m","usage":{"input_tokens":7,',
    '"cache_read_input_tokens":null,"output_tokens":1}}}'
  )))
  n$push(list(event = "message_delta", data = paste0(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":4}}'
  )))
  n$push(list(event = "message_stop", data = '{"type":"message_stop"}'))
  u = n$message()$usage
  expect_identical(c(u$input, u$output, u$cache_write_5m, u$reasoning), c(7, 4, 0, 0))
  expect_identical(c(u$cache_read, u$total), c(NA_real_, NA_real_))
})

# The usage of a message after the given stream-event JSON objects, through push() or, for the
# cli-claude reuse, push_parsed() (the fixture model is test_model(api) with its defaults)
usage_after = function(objs, parsed = FALSE) {
  n = anthropic_normaliser(adp_fixture_model(api), list(emit = function(ev) NULL))
  for (o in objs) if (parsed) n$push_parsed(json_decode(o)) else n$push(list(data = o))
  n$message()$usage
}

usage_vec = function(u) {
  c(u$input, u$output, u$cache_read, u$cache_write_5m, u$cache_write_1h, u$reasoning, u$total)
}

test_that("a bare cache total in message_delta keeps the 5-minute/1-hour split (07 3.14)", {
  # the verified wire shape: message_delta repeats the cumulative cache_creation_input_tokens
  # without a cache_creation object
  wire = c(
    paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":10,',
           '"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,',
           '"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},',
           '"output_tokens":3}}}'),
    paste0('{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{',
           '"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,',
           '"output_tokens":137,"output_tokens_details":{"thinking_tokens":63},',
           '"iterations":[{"input_tokens":10,"output_tokens":137,"cache_read_input_tokens":0,',
           '"cache_creation_input_tokens":7448,"cache_creation":{"ephemeral_5m_input_tokens":0,',
           '"ephemeral_1h_input_tokens":7448},"type":"message"}]}}'),
    '{"type":"message_stop"}'
  )
  want = c(10, 137, 0, 0, 7448, 63, 7595)
  expect_identical(usage_vec(usage_after(wire)), want)
  expect_identical(usage_vec(usage_after(wire, parsed = TRUE)), want)
  # a grown total keeps the known 1-hour writes; the rest are 5-minute writes
  grown = c(
    paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1,',
           '"cache_creation_input_tokens":1200,"cache_creation":{"ephemeral_5m_input_tokens":200,',
           '"ephemeral_1h_input_tokens":1000},"output_tokens":1}}}'),
    paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},',
           '"usage":{"cache_creation_input_tokens":1500,"output_tokens":2}}')
  )
  u = usage_after(grown)
  expect_identical(c(u$cache_write_5m, u$cache_write_1h), c(500, 1000))
  # no split ever reported: every cache write is a 5-minute write (report 07 section 3.5)
  plain = c(
    paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1,',
           '"cache_creation_input_tokens":0,"output_tokens":1}}}'),
    paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},',
           '"usage":{"cache_creation_input_tokens":300,"output_tokens":2}}')
  )
  u = usage_after(plain)
  expect_identical(c(u$cache_write_5m, u$cache_write_1h), c(300, 0))
})

test_that("a null in message_delta keeps the value reported before it (cumulative, IC-74)", {
  start = paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":10,',
                 '"cache_creation_input_tokens":0,"cache_read_input_tokens":300,',
                 '"output_tokens":3}}}')
  delta = paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{',
                 '"input_tokens":null,"cache_creation_input_tokens":null,',
                 '"cache_read_input_tokens":null,"output_tokens":15}}')
  u = usage_after(c(start, delta, '{"type":"message_stop"}'))
  expect_identical(usage_vec(u), c(10, 15, 300, 0, 0, 0, 325))
  # null split fields and a null thinking count keep the earlier values
  start = paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":5,',
                 '"cache_creation_input_tokens":1200,"cache_creation":{',
                 '"ephemeral_5m_input_tokens":200,"ephemeral_1h_input_tokens":1000},',
                 '"output_tokens":1,"output_tokens_details":{"thinking_tokens":1}}}}')
  delta = paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{',
                 '"cache_creation_input_tokens":null,"cache_creation":{',
                 '"ephemeral_5m_input_tokens":null,"ephemeral_1h_input_tokens":null},',
                 '"output_tokens":2,"output_tokens_details":{"thinking_tokens":null}}}')
  u = usage_after(c(start, delta))
  expect_identical(usage_vec(u), c(5, 2, 0, 200, 1000, 1, 1207))
  # a null split field never reported before is unknown, not a known zero; a later bare total
  # then gives the 5-minute writes from the known 1-hour ones
  start = paste0('{"type":"message_start","message":{"id":"m","usage":{"input_tokens":5,',
                 '"cache_creation":{"ephemeral_5m_input_tokens":null,',
                 '"ephemeral_1h_input_tokens":1000},"output_tokens":1}}}')
  u = usage_after(start)
  expect_identical(c(u$cache_write_5m, u$cache_write_1h, u$total), c(NA_real_, 1000, NA_real_))
  delta = paste0('{"type":"message_delta","delta":{"stop_reason":"end_turn"},',
                 '"usage":{"cache_creation_input_tokens":1200,"output_tokens":2}}')
  u = usage_after(c(start, delta))
  expect_identical(c(u$cache_write_5m, u$cache_write_1h, u$total), c(200, 1000, 1207))
})

test_that("fail() gives one error event, aborted when the run's signal says so", {
  log = event_log()
  signal = new.env()
  signal$aborted = TRUE
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, signal = signal))
  cnd = structure(class = c("gptr_error_network", "gptr_error_provider", "gptr_error", "error",
                            "condition"),
                  list(message = "connection reset", call = NULL))
  msg = n$fail(cnd)
  expect_identical(msg$stop_reason, "aborted")
  expect_identical(log$events[[length(log$events)]]$reason, "aborted")
  expect_identical(log$events[[length(log$events)]]$error$class, "network")
  n$fail(cnd)
  n$finish()
  expect_identical(sum(types_of(log$events) %in% c("done", "error")), 1L)
})

test_that("fail() and message() never signal, even for a malformed condition (04 section 8.1)", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  msg = n$fail("not a condition object")
  expect_identical(msg$stop_reason, "error")
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(log$events[[2L]]$error$class, "internal")
  expect_identical(n$message()$stop_reason, "error")
})

test_that("unparsable data ends the stream with an error event, never an R condition", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  expect_true(n$push(list(event = "content_block_delta", data = "{not json")))
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(n$message()$stop_reason, "error")
})

test_that("40,000 text deltas are consumed in linear time (INFRA-23; skip on CRAN)", {
  skip_on_cran()
  n = anthropic_normaliser(test_model(api), list(emit = function(ev) NULL))
  n$push(list(event = "message_start", data = paste0(
    '{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1}}}'
  )))
  n$push(list(event = "content_block_start", data = paste0(
    '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}'
  )))
  delta = list(event = "content_block_delta", data = paste0(
    '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"tok "}}'
  ))
  secs = system.time(for (i in seq_len(40000L)) n$push(delta))[["elapsed"]]
  n$push(list(event = "message_delta", data = paste0(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}'
  )))
  n$push(list(event = "message_stop", data = '{"type":"message_stop"}'))
  expect_lt(secs, 5)
  expect_identical(nchar(n$message()$content[[1L]]$text), 160000L)
})

test_that("an event of an unexpected shape ends the stream with an error event, not a condition", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  n$push(list(event = "content_block_start", data = paste0(
    '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}'
  )))
  expect_true(n$push(list(event = "content_block_delta", data = paste0(
    '{"type":"content_block_delta","index":0,"delta":"not an object"}'
  ))))
  expect_identical(types_of(log$events), c("start", "text_start", "error"))
  expect_identical(log$events[[3L]]$error$class, "internal")
  expect_identical(n$finish()$stop_reason, "error")
  expect_identical(sum(types_of(log$events) %in% c("done", "error")), 1L)
})

test_that("push_parsed() accepts stream-event objects (the cli-claude reuse, 04 section 7.12)", {
  dir = sse_dir(api)
  path = file.path(dir, "thinking_tools.sse")
  evs = sse_splitter()$push(readBin(path, "raw", file.size(path)))
  log = event_log()
  cli = adp_fixture_model(api, dir)
  cli$type = "cli"
  n = anthropic_normaliser(cli, list(emit = log$emit))
  for (ev in evs) n$push_parsed(json_decode(ev$data))
  msg = n$finish()
  expect_golden(lapply(log$events, adp_golden_event), api, "thinking_tools.events.json")
  expect_identical(msg$route, "plan-cli")
  expect_identical(replay_case(api, anthropic_normaliser, "text")$message$route, "api")
})
