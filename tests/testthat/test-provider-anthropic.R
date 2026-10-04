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

# ---- the request body and the built-in (Task 2) ------------------------------------------------

anthropic_turn2 = function(model) {
  asst = msg_assistant(list(block_text("Checking."),
                            block_tool_call("toolu_01A", "r", list(code = "nrow(d)"))),
                       api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use", timestamp = 2)
  # first_message() comes from replay_helpers.R, sourced at run time where lintr cannot see it
  first = first_message() # nolint: object_usage_linter.
  list(first, asst, msg_tool_result("toolu_01A", "r", "[1] 32", timestamp = 3))
}

test_that("anthropic breakpoints follow G4 section 3.7: T0 and the project block 1 h, auto tail", {
  model = test_model(api)
  req = anthropic_build(model, ctx_fixture(list(first_message())), list())
  body = json_decode(req$body)
  expect_identical(names(body), c("model", "max_tokens", "stream", "cache_control", "thinking",
                                  "tools", "system", "messages"))
  expect_equal(body$cache_control, list(type = "ephemeral"))
  expect_equal(body$system[[1L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_null(body$system[[2L]]$cache_control)
  project = body$messages[[1L]]$content[[1L]]
  expect_match(project$text, "<project_instructions", fixed = TRUE)
  expect_equal(project$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_null(body$messages[[1L]]$content[[2L]]$cache_control)
  expect_identical(lengths(regmatches(req$body, gregexpr("cache_control", req$body))), 3L)
  plan = list(anchors = c("t0", "project"), tail_ttl = "1h", key = "gptr:0123456789ab")
  body_1h = json_decode(anthropic_build(model, ctx_fixture(list(first_message()),
                                                           cache_plan = plan), list())$body)
  expect_equal(body_1h$cache_control, list(type = "ephemeral", ttl = "1h"))
})

test_that("the default cache policy of prompt-cache.R drives the breakpoints (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "project"))
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(first_message()),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[1L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_equal(body$messages[[1L]]$content[[1L]]$cache_control,
               list(type = "ephemeral", ttl = "1h"))
  plan = default_plan(api, project = FALSE)
  expect_identical(plan$anchors, c("t0", "t1"))
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(msg_user("hi")),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[2L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
})

test_that("without a project block the second breakpoint moves to the T1 system block", {
  plan = list(anchors = c("t0", "t1"), tail_ttl = "5m", key = "gptr:0123456789ab")
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(msg_user("hi")),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[2L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  # a cache plan that names neither T1 nor the project block marks only T0 and the tail
  plan = list(anchors = "t0", tail_ttl = "5m", key = "gptr:0123456789ab")
  req = anthropic_build(test_model(api), ctx_fixture(list(first_message()), cache_plan = plan),
                        list())
  expect_identical(lengths(regmatches(req$body, gregexpr("cache_control", req$body))), 2L)
  expect_null(json_decode(req$body)$messages[[1L]]$content[[1L]]$cache_control)
})

test_that("the frozen prefix stays byte-identical across turns and pieces are memoised", {
  model = test_model(api)
  memo = new.env(parent = emptyenv())
  b1 = anthropic_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  fresh = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list())$body
  expect_identical(b2, fresh)
  n = length(ls(memo))
  expect_gt(n, 0L)
  again = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list(memo = memo))$body
  expect_identical(again, b2)
  expect_identical(length(ls(memo)), n)
})

test_that("a PNG tool result is sent as a native image block (acceptance 3)", {
  model = test_model(api)
  msgs = anthropic_turn2(model)
  msgs[[3L]] = msg_tool_result("toolu_01A", "r", list(block_text("plot drawn"),
                                                      block_image(png_b64())))
  body = json_decode(anthropic_build(model, ctx_fixture(msgs), list())$body)
  result = body$messages[[3L]]$content[[1L]]
  expect_identical(result$type, "tool_result")
  expect_identical(result$tool_use_id, "toolu_01A")
  expect_identical(result$content[[2L]]$type, "image")
  expect_equal(result$content[[2L]]$source,
               list(type = "base64", media_type = "image/png", data = png_b64()))
  text_only = test_model(api, input = "text")
  body = json_decode(anthropic_build(text_only, ctx_fixture(msgs), list())$body)
  expect_identical(body$messages[[3L]]$content[[1L]]$content[[2L]]$type, "text")
})

test_that("an image-only tool result for a text-only model carries only the omission note", {
  msgs = anthropic_turn2(test_model(api))
  msgs[[3L]] = msg_tool_result("toolu_01A", "r", list(block_image(png_b64())))
  result = function(model) {
    body = json_decode(anthropic_build(model, ctx_fixture(msgs), list())$body)
    body$messages[[3L]]$content[[1L]]$content
  }
  # no "(see attached image)" lead: no image is attached
  blind = result(test_model(api, input = "text"))
  expect_identical(vapply(blind, function(p) p$type, ""), "text")
  expect_identical(blind[[1L]]$text, adp_image_note())
  seen = result(test_model(api))
  expect_identical(vapply(seen, function(p) p$type, ""), c("text", "image"))
  expect_identical(seen[[1L]]$text, "(see attached image)")
})

test_that("signed and redacted thinking replay byte for byte only to the same model", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, anthropic_normaliser, "thinking_tools")$message
  ctx = ctx_fixture(list(first_message(), msg, msg_tool_result("toolu_01A", "r", "ok"),
                         msg_tool_result("toolu_01B", "read", "ok")))
  req = anthropic_build(model, ctx, list())
  parts = json_decode(req$body)$messages[[2L]]$content
  expect_identical(parts[[1L]]$type, "thinking")
  expect_identical(parts[[1L]]$signature, msg$content[[1L]]$signature)
  expect_identical(parts[[2L]], list(type = "redacted_thinking", data = msg$content[[2L]]$data))
  expect_true(grepl(msg$content[[2L]]$data, req$body, fixed = TRUE))
  expect_length(json_decode(req$body)$messages[[3L]]$content, 2L)
  other = json_decode(anthropic_build(test_model(api, id = "other-model"), ctx, list())$body)
  kinds = vapply(other$messages[[2L]]$content, function(p) p$type, "")
  expect_false(any(kinds %in% c("thinking", "redacted_thinking")))
  expect_identical(kinds[[1L]], "text")
})

test_that("adaptive models get adaptive thinking and effort; budget models an enabled budget", {
  body = json_decode(anthropic_build(test_model(api),
                                     ctx_fixture(list(msg_user("hi")),
                                                 params = list(thinking = "high")),
                                     list())$body)
  expect_equal(body$thinking, list(type = "adaptive", display = "omitted"))
  expect_identical(body$output_config$effort, "high")
  haiku = test_model(api, id = "claude-haiku-4-5", max_output = 64000,
                     capabilities = list(adaptive_thinking = FALSE, effort = FALSE))
  req = anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                           params = list(thinking = "medium", max_tokens = 4096L)),
                        list())
  body = json_decode(req$body)
  expect_equal(body$thinking, list(type = "enabled", budget_tokens = 8192L))
  expect_gt(body$max_tokens, 8192L)
  expect_null(body$output_config)
  expect_match(req$headers$`anthropic-beta`, "interleaved-thinking-2025-05-14", fixed = TRUE)
  haiku$max_output = 8192
  body = json_decode(anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                                        params = list(thinking = "high")),
                                     list())$body)
  expect_identical(body$max_tokens, 8192L)
  expect_lt(body$thinking$budget_tokens, body$max_tokens)
  # report 07 section 2.3: a temperature is never sent to a 5.x (adaptive) model
  cold = json_decode(anthropic_build(test_model(api),
                                     ctx_fixture(list(msg_user("hi")),
                                                 params = list(thinking = "off",
                                                               temperature = 0.2)),
                                     list())$body)
  expect_null(cold$thinking)
  expect_null(cold$temperature)
  warm = json_decode(anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                                        params = list(temperature = 0.2)),
                                     list())$body)
  expect_null(warm$thinking)
  expect_identical(warm$temperature, 0.2)
})

test_that("returns = uses output_config.format and keeps the tools (IC-71, INFRA-25)", {
  schema = list(type = "object", required = I("rows"),
                properties = list(rows = list(type = "integer")))
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("rows?")),
                                                     params = list(returns = schema)), list())
  body = json_decode(req$body)
  expect_identical(body$output_config$format$type, "json_schema")
  expect_identical(body$output_config$format$schema$required, list("rows"))
  expect_identical(vapply(body$tools, function(t) t$name, ""), c("read", "r"))
  expect_null(body$tool_choice)
  plain = test_model(api, structured_output = FALSE)
  body = json_decode(anthropic_build(plain, ctx_fixture(list(msg_user("rows?")),
                                                        params = list(returns = schema)),
                                     list())$body)
  expect_null(body$output_config$format)
  last = body$messages[[length(body$messages)]]
  expect_identical(last$role, "system")
  expect_match(last$content[[1L]]$text, "JSON Schema", fixed = TRUE)
})

test_that("a forced tool_choice is never sent while forced_tool_choice is FALSE (IC-71)", {
  forced = list(tool_choice = list(type = "tool", name = "read"))
  no = test_model(api, reasoning = FALSE, capabilities = list(forced_tool_choice = FALSE))
  body = json_decode(anthropic_build(no, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_null(body$tool_choice)
  silent = test_model(api, reasoning = FALSE, capabilities = list())
  body = json_decode(anthropic_build(silent, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_null(body$tool_choice)
  yes = test_model(api, reasoning = FALSE, capabilities = list(forced_tool_choice = TRUE))
  body = json_decode(anthropic_build(yes, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "tool", name = "read"))
  body = json_decode(anthropic_build(yes, ctx_fixture(list(msg_user("x")),
                                                      params = list(tool_choice = "none")),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "none"))
})

test_that("operator messages are system messages only where the placement rule allows", {
  model = test_model(api)
  relay = msg_operator("steer_relay",
                       "The user sent this message while you were working: use TPM")
  body = json_decode(anthropic_build(model, ctx_fixture(c(anthropic_turn2(model), list(relay))),
                                     list())$body)
  expect_identical(body$messages[[length(body$messages)]]$role, "system")
  old = test_model(api, capabilities = list(mid_system = FALSE))
  body = json_decode(anthropic_build(old, ctx_fixture(c(anthropic_turn2(model), list(relay))),
                                     list())$body)
  expect_identical(body$messages[[length(body$messages)]]$role, "user")
  before_user = c(anthropic_turn2(model), list(relay, msg_user("and then?")))
  body = json_decode(anthropic_build(model, ctx_fixture(before_user), list())$body)
  roles = vapply(body$messages, function(m) m$role, "")
  expect_false("system" %in% roles)
  add = msg_operator("tool_change", "New tool: lint.",
                     tool_add = list(list(name = "lint", description = "Lint a file.",
                                          input_schema = list(type = "object"))))
  req = anthropic_build(model, ctx_fixture(c(anthropic_turn2(model), list(add))), list())
  parts = json_decode(req$body)$messages[[4L]]$content
  expect_identical(parts[[2L]]$type, "tool_addition")
  expect_identical(parts[[2L]]$tool$definition$name, "lint")
  expect_match(req$headers$`anthropic-beta`, "inline-tools-2026-09-15", fixed = TRUE)
})

test_that("a run of operator messages is one system message, never two in a row (07 2.3)", {
  model = test_model(api)
  mode = msg_operator("mode", "Mode changed to auto.")
  relay = msg_operator("steer_relay",
                       "The user sent this message while you were working: use TPM")
  body = json_decode(anthropic_build(model, ctx_fixture(c(anthropic_turn2(model),
                                                          list(mode, relay))),
                                     list())$body)
  expect_identical(vapply(body$messages, function(m) m$role, ""),
                   c("user", "assistant", "user", "system"))
  expect_identical(vapply(body$messages[[4L]]$content, function(p) p$text, ""),
                   c("Mode changed to auto.",
                     "The user sent this message while you were working: use TPM"))
  # a returns instruction closes the request: the trailing run is user text, the instruction
  # the one system message after it
  plain = test_model(api, structured_output = FALSE)
  ctx = ctx_fixture(c(anthropic_turn2(model), list(relay)),
                    params = list(returns = count_schema()))
  roles = vapply(json_decode(anthropic_build(plain, ctx, list())$body)$messages,
                 function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "user", "user", "system"))
})

test_that("credentials stay handles: x-api-key, or Bearer with the oauth beta", {
  key = fake_handle("ANTHROPIC_API_KEY")
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("x"))),
                        list(credential = key, base_url = "https://api.anthropic.com"))
  expect_identical(req$url, "https://api.anthropic.com/v1/messages")
  expect_identical(req$method, "POST")
  expect_identical(req$headers$`x-api-key`, key)
  expect_identical(req$headers$`anthropic-version`, "2023-06-01")
  expect_identical(req$stream, "sse")
  tok = fake_handle("ANTHROPIC_AUTH_TOKEN")
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("x"))), list(credential = tok))
  expect_identical(req$headers$authorization, list("Bearer ", tok))
  expect_null(req$headers$`x-api-key`)
  expect_match(req$headers$`anthropic-beta`, "oauth-2025-04-20", fixed = TRUE)
  expect_false(grepl("abc123", req$body, fixed = TRUE))
})

test_that("provider headers come from the record provider_stream() resolved (04 10.1, 10.2)", {
  # a provider passed as `model = <spec>` is a session-scoped (rank 0) record that the global
  # lookup never sees; its non-secret headers must still reach the wire
  probe = function(org, id = "p12-probe") {
    gptr_provider(id, api = api, base_url = "http://127.0.0.1:9", auth = NULL,
                  headers = list(`x-org` = org),
                  models = list(list(id = "probe-1", name = "Probe", context = 200000,
                                     max_output = 4096, reasoning = FALSE,
                                     input = "text", tool_call = TRUE)),
                  local = TRUE, offline = TRUE)
  }
  model = test_model(api, provider = "p12-probe")
  ctx = ctx_fixture(list(msg_user("x")))
  # the record handed over as opts$provider is used; one of another provider is not
  req = anthropic_build(model, ctx, list(provider = probe("direct")))
  expect_identical(req$headers$`x-org`, "direct")
  other = probe("other", id = "p12-other")
  expect_null(anthropic_build(model, ctx, list(provider = other))$headers$`x-org`)
  # through provider_stream(): a session record alone, then a session record over a global one
  sid = "s_p12probe01"
  withr::defer(registry_session_drop(sid))
  registry_add(probe("session"), source = "session", rank = 0L, session = sid)
  sent = function(opts) {
    wire = local_scripted_wire(list(anthropic_sse_text("ok")))
    out = new.env(parent = emptyenv())
    out$msg = NULL
    provider_stream(model_resolve(probe("unused")), ctx, opts, emit = function(ev) NULL,
                    done = function(msg) out$msg = msg)
    reactor_pump(until = function() !is.null(out$msg), timeout = 10)
    wire$requests[[1L]]$headers
  }
  expect_identical(sent(list(session = sid))$`x-org`, "session")
  # the session's own record is also found when build() gets only the session id
  expect_identical(anthropic_build(model, ctx, list(session = sid))$headers$`x-org`, "session")
  off = gptr_register(probe("global"))
  withr::defer(off())
  expect_identical(sent(list(session = sid))$`x-org`, "session")
  expect_identical(sent(list())$`x-org`, "global")
})

test_that("provider headers never repeat an adapter header: betas join, the adapter's win", {
  # 04 10.2 row 1 allows any non-secret header in a provider record, and P04's http_headers()
  # refuses a spec that repeats a name in any case, so the request would never leave the process
  rec = function(...) {
    gptr_provider("p12-beta", api = api, base_url = "http://127.0.0.1:9", auth = NULL,
                  headers = list(...),
                  models = list(list(id = "h-1", name = "H", context = 200000,
                                     max_output = 64000, reasoning = TRUE,
                                     input = "text", tool_call = TRUE)),
                  local = TRUE, offline = TRUE)
  }
  haiku = test_model(api, id = "claude-haiku-4-5", provider = "p12-beta", max_output = 64000,
                     capabilities = list(adaptive_thinking = FALSE, effort = FALSE))
  ctx = ctx_fixture(list(msg_user("hi")), params = list(thinking = "medium"))
  tok = fake_handle("ANTHROPIC_AUTH_TOKEN")
  p = rec(`anthropic-beta` = "context-1m-2025-08-07, interleaved-thinking-2025-05-14",
          Accept = "application/json", `Anthropic-Version` = "2099-01-01",
          `X-Api-Key` = "static", `x-org` = "p12")
  h = anthropic_build(haiku, ctx, list(credential = tok, provider = p))$headers
  expect_identical(anyDuplicated(tolower(names(h))), 0L)
  local_mocked_bindings(secret_value = function(handle, origin) "tok-value")
  expect_no_error(http_headers(h, "https://api.anthropic.com"))
  # the beta tokens of both sides, gptr's first, each once
  expect_identical(h$`anthropic-beta`, paste("interleaved-thinking-2025-05-14",
                                             "oauth-2025-04-20", "context-1m-2025-08-07",
                                             sep = ","))
  # the adapter's wire format and credential stay; a second credential is never added
  expect_identical(h$accept, "text/event-stream")
  expect_identical(h$`anthropic-version`, "2023-06-01")
  expect_identical(h$authorization, list("Bearer ", tok))
  expect_false("x-api-key" %in% tolower(names(h)))
  expect_identical(h$`x-org`, "p12")
  # without gptr betas or a credential the provider's headers go out as they are
  plain = anthropic_build(test_model(api, provider = "p12-beta"),
                          ctx_fixture(list(msg_user("hi"))),
                          list(provider = rec(`anthropic-beta` = "context-1m-2025-08-07",
                                              `X-Api-Key` = "static")))$headers
  expect_identical(plain$`anthropic-beta`, "context-1m-2025-08-07")
  expect_identical(plain$`X-Api-Key`, "static")
  expect_identical(anyDuplicated(tolower(names(plain))), 0L)
})

test_that("a budget model without room for the minimum budget sends no thinking (07 2.6)", {
  # the API needs 1024 <= budget_tokens < max_tokens
  haiku = test_model(api, id = "claude-haiku-4-5", max_output = 1024,
                     capabilities = list(adaptive_thinking = FALSE, effort = FALSE))
  req = anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                           params = list(thinking = "high", max_tokens = 800L)),
                        list())
  body = json_decode(req$body)
  expect_null(body$thinking)
  expect_identical(body$max_tokens, 800L)
  expect_null(req$headers$`anthropic-beta`)
  # one token more leaves room for the minimum budget below max_tokens
  haiku$max_output = 1025
  req = anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                           params = list(thinking = "high")),
                        list())
  body = json_decode(req$body)
  expect_identical(body$max_tokens, 1025L)
  expect_equal(body$thinking, list(type = "enabled", budget_tokens = 1024L))
  expect_match(req$headers$`anthropic-beta`, "interleaved-thinking-2025-05-14", fixed = TRUE)
})

test_that("declared request params reach the body; others do not (IC-69)", {
  ctx = ctx_fixture(list(msg_user("x")), params = list(service_tier = "auto", user = "u1"))
  body = json_decode(anthropic_build(test_model(api), ctx, list())$body)
  expect_identical(body$service_tier, "auto")
  expect_null(body$user)
})

test_that("builtin:anthropic registers the adapter with its capabilities", {
  a = adapter_get(api)
  expect_s3_class(a, "gptr_adapter")
  expect_identical(a$transport, "http_sse")
  expect_false(a$capabilities$forced_tool_choice)
  expect_identical(a$capabilities$request_params, c("service_tier", "metadata"))
  expect_identical(a$capabilities$max_tool_name, 128L)
})

test_that("provider_stream() puts the returns schema on the wire (INFRA-25)", {
  local_scripted_provider(api)
  wire = local_scripted_wire(list(anthropic_sse_text("{\"n\":32}")))
  out = new.env(parent = emptyenv())
  out$msg = NULL
  ctx = ctx_fixture(list(msg_user("How many rows?")), params = list(returns = count_schema()))
  provider_stream(model_resolve("scripted/scripted-1"), ctx, list(), emit = function(ev) NULL,
                  done = function(msg) out$msg = msg)
  reactor_pump(until = function() !is.null(out$msg), timeout = 10)
  body = json_decode(wire$requests[[1L]]$body)
  expect_identical(body$output_config$format$type, "json_schema")
  expect_identical(body$output_config$format$schema$required, list("n"))
  expect_identical(msg_text(out$msg), "{\"n\":32}")
})

test_that("returns = through the run loop: a typed value and the tool calls kept (INFRA-25)", {
  skip_without_run_engine()
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_scripted_provider(api)
  local_count_tool()
  wire = local_scripted_wire(list(anthropic_sse_tool("toolu_01", "count", "{}"),
                                  anthropic_sse_text("{\"n\":32}")))
  s = session_new("scripted/scripted-1", "auto", home = new.env())
  session_run(s, msg_user("How many rows?"), list(returns = count_schema()))
  expect_identical(s$value$n, 32L)
  expect_identical(vapply(s$messages, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "assistant"))
  expect_length(wire$requests, 2L)
  expect_match(wire$requests[[1L]]$url, "/v1/messages$")
  # the run's returns schema reaches the wire through P07's request context (IC-71)
  first = json_decode(wire$requests[[1L]]$body)
  expect_identical(first$output_config$format$type, "json_schema")
  expect_identical(first$output_config$format$schema$required, list("n"))
  expect_true("count" %in% vapply(first$tools, function(t) t$name, ""))
  second = json_decode(wire$requests[[2L]]$body)
  kinds = unlist(lapply(second$messages, function(m) vapply(m$content, function(b) b$type, "")))
  expect_true(all(c("tool_use", "tool_result") %in% kinds))
})

test_that("end to end on the mock server: streaming, retry and abort (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("stream", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$usage$input, 100)
  over = local_mock_server("overload", attempts = 1L)
  r = mock_stream(over)
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(nrow(over$log()), 2L)
  expect_identical(sum(r$types == "start"), 1L)
  slow = local_mock_server("stream", n = 12L, interval = 0.2)
  r = mock_stream(slow, abort_after = 2L)
  expect_identical(r$message$stop_reason, "aborted")
  expect_identical(msg_text(r$message), "tok01 tok02 ")
  expect_identical(r$types[[length(r$types)]], "error")
  tools = local_mock_server("parallel_tools")
  r = mock_stream(tools)
  expect_identical(r$message$stop_reason, "tool_use")
  expect_identical(vapply(r$message$content, function(b) b$name, ""), c("read", "r"))
  expect_identical(r$message$content[[2L]]$arguments, list(code = "1 + 1"))
})
