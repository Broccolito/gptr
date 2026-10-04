# Tests for R/provider-openai-responses.R (plan P12): the openai-responses normaliser and
# request body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "openai-responses"

# Push Responses stream events through the normaliser of a fixture model; finish() at the end.
# Each element of `datas` is the JSON text of one SSE `data:` line; its `type` is the event name
resp_run = function(datas, opts = list(), events = NULL) {
  out = new.env(parent = emptyenv())
  out$events = list()
  opts$emit = function(ev) out$events[[length(out$events) + 1L]] = ev
  n = responses_normaliser(adp_fixture_model(api), opts)
  for (k in seq_along(datas)) {
    name = events[[k]] %||% (json_decode(datas[[k]])[["type"]] %||% "")
    n$push(list(event = name, data = datas[[k]]))
  }
  list(message = n$finish(), events = out$events)
}

# The JSON text of a response.created event and of a terminal event with `response` fields
resp_created = function(id = "resp_x") {
  paste0('{"type":"response.created","response":{"id":"', id, '","status":"in_progress",',
         '"model":"fixture-1","output":[]}}')
}
resp_terminal = function(response, type = "response.completed") {
  paste0('{"type":"', type, '","response":', response, "}")
}

# A message item added at output index 0 and one text delta for it
resp_text = function(text = "x") {
  c(paste0('{"type":"response.output_item.added","output_index":0,',
           '"item":{"id":"msg_x","type":"message","role":"assistant","content":[]}}'),
    paste0('{"type":"response.output_text.delta","output_index":0,"content_index":0,',
           '"delta":"', text, '"}'))
}

# ---- the normaliser (Task 6) -------------------------------------------------------------------

test_that("responses fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, responses_normaliser)
})

test_that("responses events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("reasoning_tools", "backfill", "truncated")) {
    expect_chunk_invariant(api, responses_normaliser, case)
  }
})

test_that("reasoning items, phase and fc_/call_ ids are kept verbatim (INFRA-07)", {
  msg = replay_case(api, responses_normaliser, "reasoning_tools")$message
  types = vapply(msg$content, function(b) b$type, "")
  expect_identical(types, c("thinking", "opaque", "text", "tool_call"))
  item = json_decode(msg$content[[2L]]$json)
  expect_identical(item$encrypted_content, "gAAAAB-fixture-opaque-blob==")
  expect_identical(msg$content[[2L]]$api, api)
  expect_identical(json_decode(msg$content[[3L]]$signature)$phase, "commentary")
  expect_identical(msg$content[[4L]]$id, "call_fixture1|fc_fixture1")
})

test_that("encrypted_content missing from output_item.done is backfilled from completed", {
  msg = replay_case(api, responses_normaliser, "backfill")$message
  item = json_decode(msg$content[[2L]]$json)
  expect_identical(item$encrypted_content, "gAAAAB-backfilled==")
})

test_that("failed and truncated streams each end with one error event and the partial", {
  for (case in c("failed", "truncated")) {
    ev = replay_case(api, responses_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
  }
  inc = replay_case(api, responses_normaliser, "incomplete")$message
  expect_identical(inc$stop_reason, "length")
})

test_that("an error event before any delta asks the transport to retry", {
  log = event_log()
  retried = event_log()
  n = responses_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  expect_false(n$push(list(event = "error", data = paste0(
    '{"type":"error","code":"server_is_overloaded","message":"busy"}'
  ))))
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_length(log$events, 0L)
  n$finish()
  expect_identical(types_of(log$events), c("start", "error"))
})

# ---- additions beyond the plan (IC-74, contract typing, robustness) ----------------------------

test_that("unreported or null usage stays unknown; fields left out keep P05's zero (IC-74)", {
  usage_of = function(usage) {
    r = resp_run(c(resp_created(), resp_text(), resp_terminal(paste0(
      '{"id":"resp_x","status":"completed","output":[],"usage":', usage, "}"
    ))))
    expect_identical(r$message$stop_reason, "stop")
    u = r$message$usage
    c(input = u$input, output = u$output, cache_read = u$cache_read, w5 = u$cache_write_5m,
      reasoning = u$reasoning, total = u$total)
  }
  # no usage at all, or "usage": null: every count and the cost unknown
  for (usage in c("null", "")) {
    response = if (nzchar(usage)) {
      '{"id":"resp_x","status":"completed","output":[],"usage":null}'
    } else {
      '{"id":"resp_x","status":"completed","output":[]}'
    }
    r = resp_run(c(resp_created(), resp_text(), resp_terminal(response)))
    expect_identical(r$message$stop_reason, "stop")
    u = r$message$usage
    expect_identical(c(u$input, u$output, u$cache_read, u$reasoning, u$total), rep(NA_real_, 5L))
    expect_identical(u$cost$total, NA_real_)
  }
  # a reported null is unknown, not zero
  expect_identical(usage_of('{"input_tokens":null,"output_tokens":5}'),
                   c(input = NA, output = 5, cache_read = 0, w5 = 0, reasoning = 0, total = NA))
  expect_identical(usage_of(paste0('{"input_tokens":100,"output_tokens":10,',
                                   '"input_tokens_details":{"cached_tokens":null},',
                                   '"output_tokens_details":{"reasoning_tokens":null}}')),
                   c(input = NA, output = 10, cache_read = NA, w5 = 0, reasoning = NA,
                     total = NA))
  # cached and cache-write tokens are part of input_tokens (08 section 3.3)
  expect_identical(usage_of(paste0('{"input_tokens":100,"output_tokens":10,',
                                   '"input_tokens_details":{"cached_tokens":40,',
                                   '"cache_write_tokens":10},',
                                   '"output_tokens_details":{"reasoning_tokens":3}}')),
                   c(input = 50, output = 10, cache_read = 40, w5 = 10, reasoning = 3,
                     total = 110))
  # fields the provider left out of a reported usage keep the legacy zero
  expect_identical(usage_of('{"input_tokens":100,"output_tokens":10}'),
                   c(input = 100, output = 10, cache_read = 0, w5 = 0, reasoning = 0,
                     total = 110))
  # usage reported with response.failed is kept on the error's partial message
  r = resp_run(c(resp_created(), resp_text(), resp_terminal(paste0(
    '{"id":"resp_x","status":"failed","error":{"code":"server_error","message":"boom"},',
    '"usage":{"input_tokens":20,"output_tokens":2}}'
  ), "response.failed")))
  expect_identical(r$message$stop_reason, "error")
  expect_identical(c(r$message$usage$input, r$message$usage$output, r$message$usage$total),
                   c(20, 2, 22))
})


test_that("error codes are classified by text; spend caps are never retried (08 3.5, 04 2.2)", {
  info = function(x) responses_error_info(x)[c("class", "status", "retry")]
  expect_identical(info("insufficient_quota"),
                   list(class = "spend_cap", status = 429L, retry = FALSE))
  expect_identical(info("organization_usage_limit_exceeded"),
                   list(class = "spend_cap", status = 429L, retry = FALSE))
  expect_identical(info("rate_limit_exceeded"),
                   list(class = "rate_limit", status = 429L, retry = TRUE))
  expect_identical(info("slow_down"), list(class = "rate_limit", status = 429L, retry = TRUE))
  expect_identical(info("server_error"),
                   list(class = "overloaded", status = 503L, retry = TRUE))
  provider = list(class = "provider", status = NA_integer_, retry = FALSE)
  expect_identical(info("invalid_prompt"), provider)
  # a code that is not one string is a provider error, never matched as text
  expect_identical(info(NULL), provider)
  expect_identical(info(5L), provider)
  expect_identical(info(NA_character_), provider)
  expect_identical(info(list("server_error")), provider)
  expect_identical(info(c("slow_down", "x")), provider)
})

test_that("stream errors: retry before any delta, spend caps final, every shape read (08 3.5)", {
  retried = event_log()
  # a spend cap before any delta is final; the transport is not asked to retry
  r = resp_run(resp_terminal(paste0('{"id":"resp_q","status":"failed","error":',
                                    '{"code":"insufficient_quota","message":"quota"}}'),
                             "response.failed"), opts = list(retry = retried$emit))
  expect_length(retried$events, 0L)
  last = r$events[[length(r$events)]]
  expect_identical(list(last$type, last$error$class, last$error$status),
                   list("error", "spend_cap", 429L))
  expect_identical(r$message$error_message, "insufficient_quota: quota")
  # a rate limit before any delta is handed to the transport with the contract's info
  r = resp_run('{"type":"error","code":"rate_limit_exceeded","message":"slow"}',
               opts = list(retry = retried$emit))
  expect_identical(retried$events, list(list(class = "rate_limit", status = 429L,
                                             retry_after = NULL)))
  expect_identical(types_of(r$events), c("start", "error"))
  expect_identical(r$message$error_message, "rate_limit_exceeded: slow")
  # a nested error object after a delta is final and keeps the partial text
  r = resp_run(c(resp_created(), resp_text("Part"),
                 '{"type":"error","error":{"code":"server_error","message":"lost"}}'),
               opts = list(retry = retried$emit))
  expect_length(retried$events, 1L)
  last = r$events[[length(r$events)]]
  expect_identical(list(last$type, last$error$class), list("error", "overloaded"))
  expect_identical(c(r$message$error_message, r$message$content[[1L]]$text),
                   c("server_error: lost", "Part"))
  # an SSE `event: error` whose data has no type is an error event
  r = resp_run(c(resp_created(), resp_text(), '{"code":"server_error","message":"gone"}'),
               events = list(NULL, NULL, NULL, "error"))
  expect_identical(r$message$error_message, "server_error: gone")
  expect_identical(r$message$content[[1L]]$text, "x")
  # an error given as a bare string is the provider's message, not an internal adapter error
  r = resp_run(c(resp_created(), resp_text(), resp_terminal(
    '{"id":"resp_x","status":"failed","error":"Model crashed"}', "response.failed"
  )))
  last = r$events[[length(r$events)]]
  expect_identical(list(last$type, last$error$class), list("error", "provider"))
  expect_identical(r$message$error_message, "unknown: Model crashed")
})

test_that("only max_output_tokens is a length stop; other statuses are errors (04 4.2)", {
  r = resp_run(c(resp_created(), resp_text(), resp_terminal(
    '{"id":"resp_x","status":"incomplete","incomplete_details":{"reason":"content_filter"}}',
    "response.incomplete"
  )))
  expect_identical(c(r$message$stop_reason, r$message$raw_stop_reason),
                   c("error", "incomplete.content_filter"))
  expect_identical(r$message$error_message, "Response incomplete: content_filter")
  last = r$events[[length(r$events)]]
  expect_identical(list(last$type, last$error$class), list("error", "provider"))
  expect_identical(r$message$content[[1L]]$text, "x")
  # a terminal response without a status takes it from the event
  r = resp_run(c(resp_created(), resp_text(), resp_terminal('{"id":"resp_x"}')))
  expect_identical(c(r$message$stop_reason, r$message$raw_stop_reason), c("stop", "completed"))
  r = resp_run(c(resp_created(), resp_text(), resp_terminal(
    '{"id":"resp_x","incomplete_details":{"reason":"max_output_tokens"}}', "response.incomplete"
  )))
  expect_identical(c(r$message$stop_reason, r$message$raw_stop_reason),
                   c("length", "incomplete.max_output_tokens"))
  # a status or reason that is not one string is never taken as text
  r = resp_run(c(resp_created(), resp_text(), resp_terminal(
    '{"id":"resp_x","status":7,"incomplete_details":{"reason":["max_output_tokens"]}}',
    "response.incomplete"
  )))
  expect_identical(c(r$message$stop_reason, r$message$raw_stop_reason), c("error", "incomplete"))
})

test_that("deltas that carry only item_id reach their item; a done item keeps the added phase", {
  r = resp_run(c(
    resp_created(),
    paste0('{"type":"response.output_item.added","item":{"id":"msg_a","type":"message",',
           '"phase":"commentary","content":[]}}'),
    '{"type":"response.output_text.delta","item_id":"msg_a","delta":"Hello"}',
    paste0('{"type":"response.output_item.done","item":{"id":"msg_a","type":"message",',
           '"content":[{"type":"output_text","text":"Hello"}]}}'),
    resp_terminal('{"id":"resp_x","status":"completed"}')
  ))
  expect_identical(types_of(r$events), c("start", "text_start", "text_delta", "text_end", "done"))
  expect_identical(r$message$content, list(block_text(
    "Hello", signature = '{"v":1,"id":"msg_a","phase":"commentary"}'
  )))
})

test_that("an item that is not an object or a delta for no known item ends nothing", {
  r = resp_run(c(
    resp_created(),
    '{"type":"response.output_item.added","output_index":0,"item":"msg_b"}',
    '{"type":"response.output_text.delta","output_index":5,"delta":"lost"}',
    paste0('{"type":"response.output_item.added","output_index":1,',
           '"item":{"type":"message","content":[]}}'),
    '{"type":"response.output_text.delta","output_index":1,"delta":"Kept"}',
    '{"type":"response.function_call_arguments.done","output_index":1,"arguments":["x"]}',
    '{"type":"response.output_item.done","output_index":0,"item":"msg_b"}',
    paste0('{"type":"response.output_item.done","output_index":1,"item":{"type":"message",',
           '"content":[{"type":"output_text","text":"Kept"}]}}'),
    resp_terminal('{"id":"resp_x","status":"completed"}')
  ))
  expect_identical(types_of(r$events), c("start", "text_start", "text_delta", "text_end", "done"))
  # a message item without an id gets no signature
  expect_identical(r$message$content, list(block_text("Kept")))
  expect_identical(r$message$stop_reason, "stop")
})

test_that("a function call seen only in response.completed is finished from it (08 3.3)", {
  r = resp_run(c(
    resp_created(),
    resp_terminal(paste0('{"id":"resp_x","status":"completed","output":[',
                         '{"type":"function_call","call_id":"call_z","name":"r",',
                         '"arguments":"{\\"code\\":\\"1\\"}"}]}'))
  ))
  expect_identical(types_of(r$events), c("start", "toolcall_start", "toolcall_delta",
                                         "toolcall_end", "done"))
  expect_identical(r$message$stop_reason, "tool_use")
  # without an fc_ id the call id stays alone (04 section 4.1)
  tc = r$message$content[[1L]]
  expect_identical(list(tc$id, tc$name, tc$arguments), list("call_z", "r", list(code = "1")))
})

test_that("summary parts are streamed and finished with the same blank line between them", {
  part = function(type, k, rest = "") {
    paste0('{"type":"response.reasoning_summary_', type, '","item_id":"rs_p","output_index":0,',
           '"summary_index":', k, rest, "}")
  }
  r = resp_run(c(
    resp_created(),
    paste0('{"type":"response.output_item.added","output_index":0,',
           '"item":{"id":"rs_p","type":"reasoning","summary":[]}}'),
    part("part.added", 0L), part("text.delta", 0L, ',"delta":"A"'),
    part("part.added", 1L), part("text.delta", 1L, ',"delta":"B"'),
    paste0('{"type":"response.output_item.done","output_index":0,"item":{"id":"rs_p",',
           '"type":"reasoning","summary":[{"type":"summary_text","text":"A"},',
           '{"type":"summary_text","text":"B"}],"encrypted_content":"gA=="}}'),
    resp_terminal('{"id":"resp_x","status":"completed"}')
  ))
  deltas = Filter(function(ev) ev$type == "thinking_delta", r$events)
  streamed = vapply(deltas, function(ev) ev$delta, "")
  expect_identical(streamed, c("A", "\n\n", "B"))
  ends = Filter(function(ev) ev$type == "thinking_end", r$events)
  expect_length(ends, 1L)
  expect_identical(ends[[1L]]$block$thinking, paste(streamed, collapse = ""))
  expect_identical(r$message$content[[1L]]$thinking, "A\n\nB")
})

test_that("a done item with an empty summary or content list keeps the streamed text", {
  r = resp_run(c(
    resp_created(),
    paste0('{"type":"response.output_item.added","output_index":0,',
           '"item":{"id":"rs_e","type":"reasoning","summary":[]}}'),
    paste0('{"type":"response.reasoning_summary_text.delta","output_index":0,',
           '"summary_index":0,"delta":"Plan."}'),
    paste0('{"type":"response.output_item.done","output_index":0,',
           '"item":{"id":"rs_e","type":"reasoning","summary":[],"encrypted_content":"gA=="}}'),
    paste0('{"type":"response.output_item.added","output_index":1,',
           '"item":{"id":"msg_e","type":"message","content":[]}}'),
    '{"type":"response.output_text.delta","output_index":1,"delta":"Answer."}',
    paste0('{"type":"response.output_item.done","output_index":1,',
           '"item":{"id":"msg_e","type":"message","content":[]}}'),
    resp_terminal('{"id":"resp_x","status":"completed"}')
  ))
  expect_identical(vapply(r$message$content, function(b) b$type, ""),
                   c("thinking", "opaque", "text"))
  expect_identical(c(r$message$content[[1L]]$thinking, r$message$content[[3L]]$text),
                   c("Plan.", "Answer."))
  expect_identical(r$message$content[[2L]]$json,
                   '{"type":"reasoning","id":"rs_e","summary":[],"encrypted_content":"gA=="}')
})
