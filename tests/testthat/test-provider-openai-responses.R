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

# ---- the request body and the built-in (Task 7) ------------------------------------------------

test_that("Responses bodies: store = false, the cache key, explicit breakpoints (G4 3.7)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  req = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                        list(base_url = "https://api.openai.com/v1"))
  body = json_decode(req$body)
  expect_identical(names(body)[1:5], c("model", "store", "stream", "prompt_cache_key",
                                       "prompt_cache_options"))
  expect_identical(names(body)[length(body)], "input")
  expect_false(body$store)
  expect_identical(body$prompt_cache_key, "gptr:0123456789ab")
  expect_equal(body$prompt_cache_options, list(mode = "implicit"))
  dev = body$input[[1L]]
  expect_identical(dev$role, "developer")
  expect_equal(dev$content[[1L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  expect_equal(dev$content[[2L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  user = body$input[[2L]]$content
  expect_equal(user[[1L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  expect_null(user[[2L]]$prompt_cache_breakpoint)
  read_params = list(type = "object", required = list("path"),
                     properties = list(path = list(type = "string")))
  expect_identical(body$tools[[1L]], list(type = "function", name = "read",
                                          description = "Read a file.",
                                          parameters = read_params, strict = FALSE))
  expect_identical(req$url, "https://api.openai.com/v1/responses")
  expect_identical(req$headers$`x-client-request-id`, "q0123456789ab")
  other = json_decode(responses_build(test_model(api), ctx_fixture(list(first_message())),
                                      list())$body)
  expect_null(other$prompt_cache_options)
  expect_false(grepl("prompt_cache_breakpoint", json_encode(other$input), fixed = TRUE))
})

test_that("the default cache policy gives T0, T1 and project breakpoints (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "t1", "project"))
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  req = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan), list())
  expect_identical(lengths(regmatches(req$body, gregexpr("prompt_cache_breakpoint", req$body))),
                   3L)
  expect_identical(json_decode(req$body)$prompt_cache_key, plan$key)
})

test_that("reasoning items, phase and fc_ ids replay byte for byte to the same model only", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, responses_normaliser, "reasoning_tools")$message
  ctx = ctx_fixture(list(first_message(), msg,
                         msg_tool_result("call_fixture1|fc_fixture1", "r", "[1] 10")))
  req = responses_build(model, ctx, list())
  expect_true(grepl(msg$content[[2L]]$json, req$body, fixed = TRUE))
  items = json_decode(req$body)$input
  kinds = vapply(items, function(x) x$type %||% x$role, "")
  expect_identical(kinds, c("developer", "user", "reasoning", "message", "function_call",
                            "function_call_output"))
  expect_identical(items[[4L]]$phase, "commentary")
  expect_identical(items[[4L]]$id, "msg_fixture1")
  expect_identical(items[[5L]]$id, "fc_fixture1")
  expect_identical(items[[5L]]$call_id, "call_fixture1")
  expect_identical(items[[6L]]$call_id, "call_fixture1")
  other = json_decode(responses_build(test_model(api, id = "other-1"), ctx, list())$body)$input
  kinds = vapply(other, function(x) x$type %||% x$role, "")
  expect_false("reasoning" %in% kinds)
  fc = other[[which(kinds == "function_call")]]
  expect_null(fc$id)
  expect_identical(fc$call_id, "call_fixture1")
})

test_that("a handed-off Anthropic conversation: no foreign opaque data, valid body (INFRA-08)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  h = handoff_entries()
  expect_length(h$opaque, 2L)
  # P05's projection (project_messages() ends with handoff_transform()), as request_build() runs it
  msgs = project_messages(h$entries, h$leaf, model)
  wire = responses_build(model, ctx_fixture(msgs, cache_plan = plan), list())$body
  for (s in h$opaque) expect_false(grepl(s, wire, fixed = TRUE), label = s)
  body = json_decode(wire)
  expect_identical(schema_validate(responses_body_schema(), body)$errors, character())
  expect_identical(names(body)[1:5], c("model", "store", "stream", "prompt_cache_key",
                                       "prompt_cache_options"))
  expect_identical(names(body)[length(body)], "input")
  expect_identical(lengths(regmatches(wire, gregexpr("prompt_cache_breakpoint", wire,
                                                     fixed = TRUE))), 3L)
  kinds = vapply(body$input, function(x) x$type %||% x$role, "")
  expect_identical(kinds, c("developer", "user", "assistant", "assistant", "function_call",
                            "function_call", "function_call_output", "function_call_output"))
  expect_identical(body$input[[3L]]$content,
                   "The user wants mpg by cyl. Aggregate in the session.")
  expect_identical(vapply(body$input[5:8], function(x) x$call_id, ""),
                   c("toolu_01A", "toolu_01B", "toolu_01A", "toolu_01B"))
  expect_null(body$input[[5L]]$id)
  # the schema is closed: an Anthropic signature on an item does not validate
  bad = body
  bad$input[[5L]]$signature = h$opaque[[1L]]
  expect_false(schema_validate(responses_body_schema(), bad)$ok)
})

test_that("a PNG tool result is sent as an input_image (acceptance 3)", {
  model = test_model(api)
  call = block_tool_call("call_9|fc_9", "r", list(code = "plot(1)"))
  asst = msg_assistant(list(call), api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use")
  res = msg_tool_result("call_9|fc_9", "r", list(block_text("drawn"), block_image(png_b64())))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("plot"), asst, res)),
                                     list())$body)
  out = body$input[[length(body$input)]]
  expect_identical(out$type, "function_call_output")
  expect_identical(out$output[[1L]], list(type = "input_text", text = "drawn"))
  expect_identical(out$output[[2L]]$type, "input_image")
  expect_identical(out$output[[2L]]$image_url, paste0("data:image/png;base64,", png_b64()))
})

test_that("reasoning effort, tool_choice, operators and returns follow 08 section 3.1", {
  model = test_model(api, thinking_levels = c("off", "low", "high"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(thinking = "high")),
                                     list())$body)
  expect_equal(body$reasoning, list(effort = "high", summary = "auto"))
  expect_identical(body$include, list("reasoning.encrypted_content"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(thinking = "off")),
                                     list())$body)
  expect_equal(body$reasoning, list(effort = "none"))
  forced = list(tool_choice = list(type = "tool", name = "read"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "function", name = "read"))
  add = msg_operator("tool_change", "New tool: lint.",
                     tool_add = list(list(name = "lint", description = "Lint a file.",
                                          input_schema = list(type = "object"))))
  items = json_decode(responses_build(model, ctx_fixture(list(msg_user("x"), add)),
                                      list())$body)$input
  expect_identical(items[[3L]], list(role = "developer", content = "New tool: lint."))
  expect_identical(items[[4L]]$type, "additional_tools")
  expect_identical(items[[4L]]$tools[[1L]]$name, "lint")
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(returns = count_schema())),
                                     list())$body)
  last = body$input[[length(body$input)]]
  expect_identical(last$role, "developer")
  expect_match(last$content, "JSON Schema", fixed = TRUE)
  expect_null(body$text)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  call = block_tool_call("call_A1|fc_A1", "r", list(code = "nrow(d)"))
  asst = msg_assistant(list(block_text("Checking."), call), api = api, provider = "openai",
                       model = "gpt-6-sol", stop_reason = "tool_use", timestamp = 2)
  turn2 = list(first_message(), asst, msg_tool_result("call_A1|fc_A1", "r", "[1] 32"))
  memo = new.env(parent = emptyenv())
  b1 = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                       list(memo = memo))$body
  b2 = responses_build(model, ctx_fixture(turn2, cache_plan = plan), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, responses_build(model, ctx_fixture(turn2, cache_plan = plan), list())$body)
})

test_that("builtin:openai registers the adapter; check_adapter() and gptr_check() pass", {
  a = adapter_get(api)
  expect_identical(a$capabilities$operator_role, "developer")
  expect_true(a$capabilities$tool_addition)
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true("adapter.reasoning_tools.roundtrip" %in% res$check)
  expect_true(all(gptr_check(a)$ok))
})

test_that("returns = through the run loop on Responses: instruction and validation (INFRA-25)", {
  skip_without_run_engine()
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_scripted_provider(api)
  local_count_tool()
  wire = local_scripted_wire(list(responses_sse_tool("call_w1", "count", "{}"),
                                  responses_sse_text("{\"n\":32}")))
  s = session_new("scripted/scripted-1", "auto", home = new.env())
  session_run(s, msg_user("How many rows?"), list(returns = count_schema()))
  expect_identical(s$value$n, 32L)
  expect_identical(vapply(s$messages, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "assistant"))
  expect_match(wire$requests[[2L]]$url, "/responses$")
  # the run's returns schema reaches the wire as the closing developer instruction (IC-71)
  first = json_decode(wire$requests[[1L]]$body)
  closing = first$input[[length(first$input)]]
  expect_identical(closing$role, "developer")
  expect_match(closing$content, "JSON Schema", fixed = TRUE)
  expect_null(first$tool_choice)
  second = json_decode(wire$requests[[2L]]$body)$input
  kinds = vapply(second, function(x) x$type %||% x$role, "")
  expect_true(all(c("function_call", "function_call_output") %in% kinds))
})

test_that("end to end on the mock server: a Responses stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("openai_responses", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$response_id, "resp_mock")
})

# The number of explicit cache breakpoints in a request body
resp_breakpoints = function(body) {
  lengths(regmatches(body, gregexpr("prompt_cache_breakpoint", body, fixed = TRUE)))
}

test_that("build() takes compat and headers from the record provider_stream() resolved (04 10.1)", {
  # D-023, D-027 item 3: a session-scoped provider (`model = <spec>`) is invisible to the global
  # lookup, so its compat (the explicit cache mode) and headers come from opts$provider or the
  # session's own record; record headers never repeat or replace the adapter's
  model = test_model(api, provider = "p12-resp", id = "resp-large")
  rec = gptr_provider("p12-resp", api = api, base_url = "https://llm.corp.example/v1",
                      compat = list(supportsExplicitPromptCacheMode = TRUE),
                      headers = list(`X-Org` = "lab", `Content-Type` = "text/plain",
                                     Authorization = "Bearer record",
                                     `X-Client-Request-Id` = "fixed"))
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  ctx = ctx_fixture(list(first_message()), cache_plan = plan)
  req = responses_build(model, ctx, list(provider = rec, credential = fake_handle("CORP_KEY")))
  expect_equal(json_decode(req$body)$prompt_cache_options, list(mode = "implicit"))
  expect_identical(resp_breakpoints(req$body), 3L)
  h = req$headers
  expect_identical(anyDuplicated(tolower(names(h))), 0L)
  expect_identical(h$authorization, list("Bearer ", fake_handle("CORP_KEY")))
  expect_identical(h$`content-type`, "application/json")
  expect_identical(h$`x-client-request-id`, "q0123456789ab")
  expect_identical(h$`X-Org`, "lab")
  # without a credential the record's own credential header goes out as it is (D-023 item 3)
  expect_identical(responses_build(model, ctx, list(provider = rec))$headers$Authorization,
                   "Bearer record")
  # the resolved openai record can switch the explicit cache mode off (plan ambiguity 13)
  off = gptr_provider("openai", api = api, compat = list(explicit_cache_mode = FALSE))
  oa = test_model(api, provider = "openai", id = "gpt-6-sol")
  body = responses_build(oa, ctx, list(provider = off))$body
  expect_null(json_decode(body)$prompt_cache_options)
  expect_identical(resp_breakpoints(body), 0L)
  # a record of another provider is ignored; nothing else is registered, so the defaults apply
  other = gptr_provider("p12-other", api = api, compat = list(explicit_cache_mode = TRUE),
                        headers = list(`X-Org` = "other"))
  req = responses_build(model, ctx, list(provider = other))
  expect_null(json_decode(req$body)$prompt_cache_options)
  expect_null(req$headers$`X-Org`)
  # the session's own record when build() gets only the session id
  sid = "s_p12resp01"
  withr::defer(registry_session_drop(sid))
  registry_add(rec, source = "session", rank = 0L, session = sid)
  req = responses_build(model, ctx, list(session = sid))
  expect_equal(json_decode(req$body)$prompt_cache_options, list(mode = "implicit"))
  expect_identical(req$headers$`X-Org`, "lab")
})

test_that("a model without tool calling gets no tools, tool_choice or added tools (IC-74)", {
  # 07-local-ollama.md section 1: tool calling is enabled only when the model supports it
  # (D-029 items 1 and 2 for this adapter); the history's calls and results are still sent
  forced = list(type = "tool", name = "read")
  blind = test_model(api, provider = "openai", id = "small-1", tool_call = FALSE)
  call = block_tool_call("call_A1|fc_A1", "r", list(code = "nrow(d)"))
  asst = msg_assistant(list(call), api = api, provider = "openai", model = "small-1",
                       stop_reason = "tool_use", timestamp = 2)
  add = msg_operator("tool_change", "New tool: lint.",
                     tool_add = list(list(name = "lint", description = "Lint a file.",
                                          input_schema = list(type = "object"))))
  msgs = list(msg_user("x", timestamp = 1), asst,
              msg_tool_result("call_A1|fc_A1", "r", "[1] 32", timestamp = 3), add)
  for (tc in list("none", forced)) {
    body = json_decode(responses_build(blind, ctx_fixture(msgs, params = list(tool_choice = tc)),
                                       list())$body)
    expect_false(any(c("tools", "tool_choice") %in% names(body)))
    kinds = vapply(body$input, function(x) x$type %||% x$role, "")
    expect_identical(kinds, c("developer", "user", "function_call", "function_call_output",
                              "developer"))
  }
  # a request without any tools sends no tool_choice either; a model that calls tools keeps all
  able = test_model(api, provider = "openai", id = "large-1")
  ctx = ctx_fixture(list(msg_user("x")), params = list(tool_choice = "none"))
  ctx$tools_json = NULL
  expect_false(grepl("tool", responses_build(able, ctx, list())$body, fixed = TRUE))
  body = json_decode(responses_build(able, ctx_fixture(msgs, params = list(tool_choice = "none")),
                                     list())$body)
  expect_identical(body$tool_choice, "none")
  expect_length(body$tools, 2L)
  expect_identical(body$input[[length(body$input)]]$type, "additional_tools")
})

test_that("a text signature replays only its own id and phase strings (no partial matching)", {
  model = test_model(api)
  input = function(sig) {
    msg = msg_assistant(list(block_text("Done.", signature = sig)), api = api,
                        provider = model$provider, model = model$id, timestamp = 2)
    ctx = ctx_fixture(list(msg_user("x", timestamp = 1), msg))
    json_decode(responses_build(model, ctx, list())$body)$input
  }
  it = input('{"v":1,"id":"msg_1","phase":"final_answer"}')[[3L]]
  expect_identical(it[c("type", "id", "phase")],
                   list(type = "message", id = "msg_1", phase = "final_answer"))
  # a key that only starts with "id", a JSON scalar or an id that is not one string: plain text
  for (sig in c('{"v":1,"identifier":"msg_x"}', "7", '{"id":7}', '{"id":["a","b"]}')) {
    expect_identical(input(sig)[[3L]], list(role = "assistant", content = "Done."), label = sig)
  }
  # a phase that is not one string is left out
  it = input('{"v":1,"id":"msg_2","phase":{"x":1}}')[[3L]]
  expect_identical(it$id, "msg_2")
  expect_null(it$phase)
})

test_that("a forced choice: any is required, and returns = never forces a call (IC-71)", {
  # 08 section 3.1: tool_choice is "none", "required" or a named function, and a forced choice
  # is sent only when the model allows it and `returns` is not set (IC-71: auto, the closing
  # instruction and validation)
  model = test_model(api)
  build = function(params, m = model) {
    json_decode(responses_build(m, ctx_fixture(list(msg_user("x")), params = params),
                                list())$body)
  }
  forced = list(type = "tool", name = "read")
  expect_identical(build(list(tool_choice = list(type = "any")))$tool_choice, "required")
  expect_null(build(list(tool_choice = list(type = "auto")))$tool_choice)
  for (tc in list(forced, list(type = "any"))) {
    body = build(list(tool_choice = tc, returns = count_schema()))
    expect_false("tool_choice" %in% names(body))
    expect_length(body$tools, 2L)
    last = body$input[[length(body$input)]]
    expect_identical(last$role, "developer")
    expect_match(last$content, "JSON Schema", fixed = TRUE)
  }
  # a model whose capability forbids a forced choice keeps the default auto
  free = test_model(api, forced_tool_choice = FALSE)
  expect_false("tool_choice" %in% names(build(list(tool_choice = forced), free)))
})
