# Tests for R/provider-google.R (plan P12): the google-generative-ai normaliser and request
# body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "google-generative-ai"

# Push Gemini stream chunks through the normaliser of a fixture model; finish() at the end.
# Each element of `datas` is the JSON text of one SSE `data:` line
gem_run = function(datas, opts = list()) {
  out = new.env(parent = emptyenv())
  out$events = list()
  opts$emit = function(ev) out$events[[length(out$events) + 1L]] = ev
  n = google_normaliser(adp_fixture_model(api), opts)
  for (d in datas) n$push(list(data = d))
  list(message = n$finish(), events = out$events)
}

# The JSON text of one Gemini chunk: a parts array, a finish reason and a usage object (both as
# JSON text, left out when NULL) and the response id
gem_chunk = function(parts, finish = NULL, usage = NULL, rid = "rx") {
  paste0('{"candidates":[{"content":{"parts":', parts, ',"role":"model"}',
         if (!is.null(finish)) paste0(',"finishReason":', finish), ',"index":0}]',
         if (!is.null(usage)) paste0(',"usageMetadata":', usage), ',"responseId":"', rid, '"}')
}

# ---- the normaliser (Task 8) -------------------------------------------------------------------

test_that("google fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, google_normaliser)
})

test_that("google events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("thought_tools", "text_signature", "truncated")) {
    expect_chunk_invariant(api, google_normaliser, case)
  }
})

test_that("thought signatures stay on the part they arrived on (09 section 2.1)", {
  msg = replay_case(api, google_normaliser, "thought_tools")$message
  expect_identical(msg$content[[1L]]$signature, "CiQBjz1rX3NpZ1RoaW5r")
  expect_identical(msg$content[[3L]]$thought_signature, "CiQBjz1rX3NpZ0NhbGw=")
  expect_null(msg$content[[4L]]$thought_signature)
  expect_identical(msg$usage$output, 74)
  expect_identical(msg$usage$cache_read, 512)
  sig = replay_case(api, google_normaliser, "text_signature")$message
  expect_identical(sig$content[[1L]]$signature, "Q2lnVGV4dFNpZw==")
})

test_that("blocked prompts, unknown finish reasons and truncation end in one error event", {
  for (case in c("blocked", "unknown_finish", "truncated")) {
    ev = replay_case(api, google_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
  }
  unk = replay_case(api, google_normaliser, "unknown_finish")$message
  expect_identical(unk$raw_stop_reason, "MISSING_THOUGHT_SIGNATURE")
})

test_that("an error chunk before any delta asks the transport to retry", {
  log = event_log()
  retried = event_log()
  n = google_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  expect_false(n$push(list(data = paste0(
    '{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}'
  ))))
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_identical(retried$events[[1L]]$status, 503L)
  n$finish()
  expect_identical(types_of(log$events), c("start", "error"))
})

test_that("missing or duplicate function-call ids are generated", {
  log = event_log()
  n = google_normaliser(test_model(api), list(emit = log$emit))
  n$push(list(data = paste0('{"candidates":[{"content":{"parts":[',
                            '{"functionCall":{"name":"read","args":{"path":"a"}}},',
                            '{"functionCall":{"name":"read","args":{"path":"b"}}}],',
                            '"role":"model"},"finishReason":"STOP","index":0}],',
                            '"responseId":"abc"}')))
  msg = n$finish()
  ids = vapply(msg$content, function(b) b$id, "")
  expect_identical(ids, c("read_abc_1", "read_abc_2"))
  expect_identical(msg$stop_reason, "tool_use")
})

test_that("unreported or null usage stays unknown; fields left out keep P05's zero (IC-74)", {
  usage_of = function(...) {
    r = gem_run(c(...))
    expect_identical(r$message$stop_reason, "stop")
    u = r$message$usage
    c(input = u$input, output = u$output, cache_read = u$cache_read, reasoning = u$reasoning,
      total = u$total)
  }
  # no usage at all, or "usageMetadata": null: every count and the cost unknown
  for (usage in list(NULL, "null")) {
    r = gem_run(gem_chunk('[{"text":"x"}]', '"STOP"', usage))
    u = r$message$usage
    expect_identical(c(u$input, u$output, u$cache_read, u$reasoning, u$total), rep(NA_real_, 5L))
    expect_identical(u$cost$total, NA_real_)
  }
  # a reported null is unknown, not zero
  expect_identical(usage_of(gem_chunk('[{"text":"x"}]', '"STOP"',
                                      '{"promptTokenCount":null,"candidatesTokenCount":5}')),
                   c(input = NA, output = 5, cache_read = 0, reasoning = 0, total = NA))
  expect_identical(usage_of(gem_chunk('[{"text":"x"}]', '"STOP"', paste0(
    '{"promptTokenCount":100,"cachedContentTokenCount":null,"candidatesTokenCount":5,',
    '"thoughtsTokenCount":null}'
  ))), c(input = NA, output = NA, cache_read = NA, reasoning = NA, total = NA_real_))
  # fields the provider left out of a reported usage keep the legacy zero
  expect_identical(usage_of(gem_chunk('[{"text":"x"}]', '"STOP"',
                                      '{"promptTokenCount":100,"candidatesTokenCount":5}')),
                   c(input = 100, output = 5, cache_read = 0, reasoning = 0, total = 105))
  # each report replaces the last; cached tokens are part of the prompt, thoughts of the output
  expect_identical(usage_of(gem_chunk('[{"text":"x"}]', usage = '{"promptTokenCount":100}'),
                            gem_chunk("[]", '"STOP"', paste0(
                              '{"promptTokenCount":100,"cachedContentTokenCount":60,',
                              '"candidatesTokenCount":7,"thoughtsTokenCount":3}'
                            ))),
                   c(input = 40, output = 10, cache_read = 60, reasoning = 3, total = 110))
})

test_that("non-string finish reasons and signatures are never used as text (04 4.2)", {
  r = gem_run(gem_chunk('[{"text":"x"}]', "2"))
  expect_identical(r$message$stop_reason, "error")
  expect_identical(r$message$raw_stop_reason, "2")
  expect_identical(r$message$error_message, "Provider stopped with: 2")
  expect_identical(types_of(r$events)[[length(r$events)]], "error")
  r = gem_run(gem_chunk('[{"text":"x"}]', '["STOP"]'))
  expect_identical(r$message$stop_reason, "error")
  expect_null(r$message$raw_stop_reason)
  expect_identical(r$message$error_message, "Provider stopped with: unknown")
  # the finish message is passed through (09 section 2.1)
  r = gem_run(sub('"index":0', '"finishMessage":"Blocked by policy.","index":0',
                  gem_chunk('[{"text":"x"}]', '"SAFETY"'), fixed = TRUE))
  expect_identical(r$message$error_message, "Provider stopped with: SAFETY: Blocked by policy.")
  expect_identical(r$message$raw_stop_reason, "SAFETY")
  # a signature that is not one string is dropped; the block and the stream are unaffected
  r = gem_run(gem_chunk(paste0('[{"text":"x","thoughtSignature":5},',
                               '{"functionCall":{"id":"c1","name":"f","args":{}},',
                               '"thoughtSignature":["QUJDRA==","RUZHSA=="]}]'), '"STOP"'))
  expect_identical(r$message$stop_reason, "tool_use")
  expect_identical(r$message$content[[1L]], block_text("x"))
  expect_null(r$message$content[[2L]]$thought_signature)
  expect_identical(r$message$content[[2L]]$id, "c1")
})

test_that("error chunks: retry before any delta, final after one, every shape read (09 2.1)", {
  info = function(x) google_error_info(x)[c("class", "status", "retry")]
  rate = list(class = "rate_limit", status = 429L, retry = TRUE)
  expect_identical(info(list(code = 429L, status = "RESOURCE_EXHAUSTED")), rate)
  expect_identical(info(list(status = "RESOURCE_EXHAUSTED")), rate)
  expect_identical(info(list(code = 429L)), rate)
  expect_identical(info(list(code = 500L, status = "INTERNAL")),
                   list(class = "overloaded", status = 500L, retry = TRUE))
  expect_identical(info(list(status = "UNAVAILABLE")),
                   list(class = "overloaded", status = 503L, retry = TRUE))
  expect_identical(info(list(code = 401L, status = "UNAUTHENTICATED")),
                   list(class = "auth", status = 401L, retry = FALSE))
  expect_identical(info(list(code = 403L, status = "PERMISSION_DENIED")),
                   list(class = "auth", status = 403L, retry = FALSE))
  expect_identical(info(list(code = 400L, status = "INVALID_ARGUMENT")),
                   list(class = "provider", status = 400L, retry = FALSE))
  # values that are not one number or one string are never matched
  provider = list(class = "provider", status = NA_integer_, retry = FALSE)
  expect_identical(info("UNAVAILABLE"), provider)
  expect_identical(info(list(code = c(500L, 503L))), provider)
  expect_identical(info(list(code = "503", status = list("UNAVAILABLE"))), provider)
  # a code that is not a whole number from 100 to 599 is not an HTTP status: never coerced (an
  # integer overflow would warn, and normalisers signal no R condition, 04 section 8.1)
  for (code in list(1e10, -1e10, Inf, 429.5, 99, 600)) {
    expect_identical(expect_no_warning(info(list(code = code))), provider,
                     label = paste("code", code))
  }
  expect_identical(info(list(code = 1e10, status = "UNAVAILABLE")),
                   list(class = "overloaded", status = 503L, retry = TRUE))
  r = expect_no_warning(gem_run('{"error":{"code":1e10,"message":"Huge.","status":"X"}}'))
  expect_identical(types_of(r$events), c("start", "error"))
  expect_identical(r$events[[2L]]$error$class, "provider")
  expect_null(r$events[[2L]]$error$status)
  expect_identical(r$message$error_message, "X: Huge.")

  # before any delta: one retry request, then the provider's error if the transport gives up
  retried = event_log()
  r = gem_run(c('{"error":{"code":429,"message":"Quota exceeded.","status":"RESOURCE_EXHAUSTED"}}',
                gem_chunk('[{"text":"ignored"}]', '"STOP"')), list(retry = retried$emit))
  expect_identical(retried$events,
                   list(list(class = "rate_limit", status = 429L, retry_after = NULL)))
  expect_identical(types_of(r$events), c("start", "error"))
  expect_identical(r$message$error_message, "RESOURCE_EXHAUSTED: Quota exceeded.")
  # after a delta: final, never retried, with the partial text
  retried = event_log()
  r = gem_run(c(gem_chunk('[{"text":"Part"}]'),
                '{"error":{"code":500,"message":"Internal error.","status":"INTERNAL"}}',
                gem_chunk('[{"text":"ignored"}]', '"STOP"')), list(retry = retried$emit))
  expect_length(retried$events, 0L)
  expect_identical(types_of(r$events), c("start", "text_start", "text_delta", "error"))
  expect_identical(r$events[[4L]]$error[c("class", "status")],
                   list(class = "overloaded", status = 500L))
  expect_identical(r$message$content, list(block_text("Part")))
  # an auth error is never retried; an error given as a bare string is the provider's message
  r = gem_run('{"error":{"code":403,"message":"Denied.","status":"PERMISSION_DENIED"}}',
              list(retry = retried$emit))
  expect_length(retried$events, 0L)
  expect_identical(r$events[[2L]]$error[c("class", "status")], list(class = "auth", status = 403L))
  r = gem_run('{"error":"Backend unreachable."}', list(retry = retried$emit))
  expect_identical(types_of(r$events), c("start", "error"))
  expect_identical(r$events[[2L]]$error$class, "provider")
  expect_identical(r$message$error_message, "error: Backend unreachable.")
})

test_that("parts that are not objects, nameless calls and non-object args stay harmless", {
  r = gem_run(gem_chunk(paste0('[5,"x",null,{"text":7},{"functionCall":{"args":[1,2]}},',
                               '{"functionCall":"f"},{"text":"ok"}]'), '"STOP"', rid = "r-9"))
  expect_identical(types_of(r$events)[[length(r$events)]], "done")
  expect_identical(r$message$stop_reason, "tool_use")
  expect_identical(vapply(r$message$content, function(b) b$type, ""), c("tool_call", "text"))
  call = r$message$content[[1L]]
  expect_identical(call$id, "call_r9_1")
  expect_identical(call$name, "unknown_tool")
  expect_identical(call$arguments, json_obj())
  expect_identical(r$message$content[[2L]]$text, "ok")
  # candidates or content that are not objects end nothing
  r = gem_run(c('{"candidates":"x","responseId":"r1"}',
                '{"candidates":[{"content":"x","index":0}]}',
                gem_chunk('[{"text":"y"}]', '"STOP"')))
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(r$message$response_id, "r1")
  expect_identical(r$message$content, list(block_text("y")))
})

test_that("a repeated call id is regenerated, and a generated id never repeats one in use", {
  ids = function(...) {
    r = gem_run(c(...))
    expect_identical(r$message$stop_reason, "tool_use")
    vapply(r$message$content, function(b) b$id, "")
  }
  fc = function(id = NULL) {
    paste0('{"functionCall":{', if (!is.null(id)) paste0('"id":"', id, '",'),
           '"name":"read","args":{}}}')
  }
  # a provider id repeated in one chunk or in a later chunk of the same message
  expect_identical(ids(gem_chunk(paste0("[", fc("c1"), ",", fc("c1"), "]"), '"STOP"',
                                 rid = "abc")),
                   c("c1", "read_abc_2"))
  expect_identical(ids(gem_chunk(paste0("[", fc("c1"), "]"), rid = "abc"),
                       gem_chunk(paste0("[", fc("c1"), "]"), '"STOP"', rid = "abc")),
                   c("c1", "read_abc_2"))
  # a generated id that a provider id already holds moves on to the next free number
  expect_identical(ids(gem_chunk(paste0("[", fc("read_abc_2"), ",", fc(), ",", fc(), "]"),
                                 '"STOP"', rid = "abc")),
                   c("read_abc_2", "read_abc_3", "read_abc_4"))
  expect_identical(ids(gem_chunk(paste0("[", fc(), ",", fc("read_abc_1"), "]"), '"STOP"',
                                 rid = "abc")),
                   c("read_abc_1", "read_abc_2"))
})

test_that("a signature on an empty text part after thinking opens an empty signed text block", {
  r = gem_run(c(gem_chunk('[{"text":"Plan.","thought":true,"thoughtSignature":"QUJDRA=="}]'),
                gem_chunk('[{"text":" More.","thought":true,"thoughtSignature":"SUpLTA=="}]'),
                gem_chunk('[{"text":"","thought":true,"thoughtSignature":""}]'),
                gem_chunk('[{"text":"","thoughtSignature":"RUZHSA=="}]', '"STOP"')))
  expect_identical(types_of(r$events),
                   c("start", "thinking_start", "thinking_delta", "thinking_delta",
                     "thinking_end", "text_start", "text_end", "done"))
  # the last non-empty signature of a streamed block is kept (09 section 2.1, Pi)
  expect_identical(r$message$content[[1L]]$thinking, "Plan. More.")
  expect_identical(r$message$content[[1L]]$signature, "SUpLTA==")
  expect_identical(r$message$content[[2L]], block_text("", signature = "RUZHSA=="))
})

test_that("model helpers: Gemini versions, thinking levels, call ids, signatures, budgets", {
  expect_identical(google_major("gemini-3.8-flash"), 3L)
  expect_identical(google_major("Gemini-2.5-Pro"), 2L)
  expect_identical(google_major("gemini-live-3.1-flash"), 3L)
  expect_identical(google_major("gemini-flash-latest"), NA_integer_)
  expect_true(google_uses_level("gemini-3.8-flash"))
  expect_true(google_uses_level("gemini-3.1-pro-preview"))
  expect_true(google_uses_level("gemini-flash-latest"))
  expect_true(google_uses_level("gemma-4-27b-it"))
  expect_false(google_uses_level("gemini-2.5-flash"))
  expect_true(google_needs_id("gemini-3.8-flash"))
  expect_true(google_needs_id("claude-sonnet-5-5"))
  expect_true(google_needs_id("gpt-oss-120b"))
  expect_false(google_needs_id("gemini-2.5-pro"))
  expect_true(google_valid_sig("CiQBjz1rX3NpZ0NhbGw="))
  for (bad in list("abc", "", "ab-_", "ab==cd==", NA_character_, NULL, 5, c("QUJD", "QUJD"))) {
    expect_false(google_valid_sig(bad), label = deparse(bad))
  }
  expect_identical(google_budget("gemini-2.5-pro", "medium"), 8192L)
  expect_identical(google_budget("gemini-2.5-flash-lite", "minimal"), 512L)
  expect_identical(google_budget("gemini-2.5-flash", "xhigh"), 24576L)
  expect_identical(google_budget("gemini-2.5-flash", "max"), 24576L)
  expect_identical(google_budget("gemini-3.8-flash", "high"), -1L)
  expect_identical(google_budget("gemini-2.5-pro", "unknown"), -1L)
})

# ---- the request body and the built-in (Task 9) ------------------------------------------------

test_that("Gemini bodies: systemInstruction, tools, toolConfig, generationConfig, contents", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  req = google_build(model, ctx_fixture(list(first_message())),
                     list(base_url = "https://generativelanguage.googleapis.com/v1beta",
                          credential = fake_handle("GEMINI_API_KEY")))
  body = json_decode(req$body)
  expect_identical(names(body), c("systemInstruction", "tools", "toolConfig", "generationConfig",
                                  "contents"))
  expect_identical(body$systemInstruction$parts[[1L]]$text, "T0 static sections.")
  decl = body$tools[[1L]]$functionDeclarations[[2L]]
  expect_identical(decl$name, "r")
  expect_identical(decl$parametersJsonSchema$required, list("code"))
  expect_equal(body$toolConfig, list(functionCallingConfig = list(mode = "AUTO")))
  expect_equal(body$generationConfig, list(maxOutputTokens = 1024L,
                                           thinkingConfig = list(includeThoughts = TRUE)))
  expect_identical(req$url, paste0("https://generativelanguage.googleapis.com/v1beta/models/",
                                   "gemini-3.8-flash:streamGenerateContent?alt=sse"))
  expect_identical(req$headers$`x-goog-api-key`, fake_handle("GEMINI_API_KEY"))
  expect_false(grepl("key=", req$url, fixed = TRUE))
})

test_that("the default cache policy gives Gemini no markers: implicit caching (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, character())
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  body = google_build(model, ctx_fixture(list(first_message()), cache_plan = plan), list())$body
  expect_false(grepl("cache", body, ignore.case = TRUE))
  expect_identical(names(json_decode(body))[[1L]], "systemInstruction")
})

test_that("thought signatures replay byte for byte to the same model only (acceptance 2)", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, google_normaliser, "thought_tools")$message
  ctx = ctx_fixture(list(first_message(), msg, msg_tool_result("fc_7h2k", "find", "a.R"),
                         msg_tool_result("fc_8j3m", "read", "x = 1")))
  body = json_decode(google_build(model, ctx, list())$body)
  parts = body$contents[[2L]]$parts
  expect_identical(parts[[1L]], list(thought = TRUE, text = msg$content[[1L]]$thinking,
                                     thoughtSignature = "CiQBjz1rX3NpZ1RoaW5r"))
  expect_identical(parts[[3L]]$thoughtSignature, "CiQBjz1rX3NpZ0NhbGw=")
  expect_identical(parts[[3L]]$functionCall$id, "fc_7h2k")
  expect_null(parts[[4L]]$thoughtSignature)
  results = body$contents[[3L]]
  expect_identical(results$role, "user")
  expect_identical(results$parts[[1L]]$functionResponse,
                   list(name = "find", response = list(output = "a.R"), id = "fc_7h2k"))
  other = json_decode(google_build(test_model(api, provider = "google", id = "gemini-3.5-flash"),
                                   ctx, list())$body)
  expect_false(grepl("thoughtSignature", json_encode(other$contents), fixed = TRUE))
  expect_null(other$contents[[2L]]$parts[[1L]]$thought)
})

test_that("Anthropic -> Responses -> Gemini: no foreign opaque data, valid body (INFRA-08)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  resp = replay_case("openai-responses", responses_normaliser, "reasoning_tools")$message
  h = handoff_entries(list(msg_user("And the row count?", timestamp = 5), resp,
                           msg_tool_result("call_fixture1|fc_fixture1", "r", "[1] 32",
                                           timestamp = 7)))
  expect_length(h$opaque, 5L)
  # P05's projection (project_messages() ends with handoff_transform()), as request_build() runs it
  msgs = project_messages(h$entries, h$leaf, model)
  wire = google_build(model, ctx_fixture(msgs), list())$body
  for (s in h$opaque) expect_false(grepl(s, wire, fixed = TRUE), label = s)
  expect_false(grepl("thoughtSignature|rs_fixture1|msg_fixture1", wire))
  body = json_decode(wire)
  expect_identical(schema_validate(gemini_body_schema(), body)$errors, character())
  expect_identical(names(body), c("systemInstruction", "tools", "toolConfig", "generationConfig",
                                  "contents"))
  roles = vapply(body$contents, function(x) x$role, "")
  expect_identical(roles, c("user", "model", "user", "user", "model", "user"))
  part_ids = function(contents, field) {
    unlist(lapply(contents, function(x) lapply(x$parts, function(p) p[[field]]$id)))
  }
  calls = part_ids(body$contents[roles == "model"], "functionCall")
  expect_identical(calls, c("toolu_01A", "toolu_01B", "call_fixture1_fc_fixture1"))
  expect_identical(part_ids(body$contents[roles == "user"], "functionResponse"), calls)
  expect_identical(body$contents[[5L]]$parts[[1L]],
                   list(text = "**Planning** Need nrow of the data."))
  # the schema is closed: an Anthropic signature on a part does not validate
  bad = body
  bad$contents[[2L]]$parts[[1L]]$signature = h$opaque[[1L]]
  expect_false(schema_validate(gemini_body_schema(), bad)$ok)
})

test_that("tool-result images ride in functionResponse.parts on Gemini 3 (09 section 2.1)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "plot(1)"))), api = api,
                       provider = "google", model = "gemini-3.8-flash", stop_reason = "tool_use")
  res = msg_tool_result("fc_1", "r", list(block_text("drawn"), block_image(png_b64())))
  body = json_decode(google_build(model, ctx_fixture(list(msg_user("plot"), asst, res)),
                                  list())$body)
  fr = body$contents[[3L]]$parts[[1L]]$functionResponse
  expect_identical(fr$parts[[1L]]$inlineData$data, png_b64())
  old = test_model(api, provider = "google", id = "gemini-2.5-flash")
  body = json_decode(google_build(old, ctx_fixture(list(msg_user("plot"), asst, res)),
                                  list())$body)
  expect_identical(body$contents[[4L]]$parts[[1L]]$text, "Tool result image:")
  expect_null(body$contents[[3L]]$parts[[1L]]$functionResponse$id)
})

test_that("thinking levels for Gemini 3, budgets for 2.5, forced calls as mode ANY", {
  g3 = test_model(api, provider = "google", id = "gemini-3.8-flash",
                  thinking_levels = c("low", "medium", "high"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")),
                                                  params = list(thinking = "xhigh")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig,
               list(includeThoughts = TRUE, thinkingLevel = "HIGH"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")),
                                                  params = list(thinking = "off")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig, list(thinkingLevel = "LOW"))
  g25 = test_model(api, provider = "google", id = "gemini-2.5-pro")
  body = json_decode(google_build(g25, ctx_fixture(list(msg_user("x")),
                                                   params = list(thinking = "medium")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig,
               list(includeThoughts = TRUE, thinkingBudget = 8192L))
  forced = list(tool_choice = list(type = "tool", name = "read"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")), params = forced),
                                  list())$body)
  expect_equal(body$toolConfig$functionCallingConfig,
               list(mode = "ANY", allowedFunctionNames = list("read")))
})

test_that("returns = becomes a user instruction; operators are user contents (IC-71)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  relay = msg_operator("steer_relay", "The user sent this message while you were working: stop")
  body = json_decode(google_build(model, ctx_fixture(list(msg_user("x"), relay),
                                                     params = list(returns = count_schema())),
                                  list())$body)
  n = length(body$contents)
  expect_identical(body$contents[[n - 1L]]$parts[[1L]]$text,
                   "The user sent this message while you were working: stop")
  expect_match(body$contents[[n]]$parts[[1L]]$text, "JSON Schema", fixed = TRUE)
  expect_null(body$generationConfig$responseJsonSchema)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "nrow(d)"),
                                            thought_signature = "Q2lnRmNTaWc=")),
                       api = api, provider = "google", model = "gemini-3.8-flash",
                       stop_reason = "tool_use", timestamp = 2)
  turn2 = list(first_message(), asst, msg_tool_result("fc_1", "r", "[1] 32"))
  memo = new.env(parent = emptyenv())
  b1 = google_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = google_build(model, ctx_fixture(turn2), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, google_build(model, ctx_fixture(turn2), list())$body)
  expect_true(grepl("\"thoughtSignature\":\"Q2lnRmNTaWc=\"", b2, fixed = TRUE))
})

test_that("builtin:google registers the adapter; check_adapter() and gptr_check() pass", {
  a = adapter_get(api)
  expect_identical(a$capabilities$tool_shape, "gemini")
  expect_identical(a$capabilities$cache, "gemini")
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true("adapter.thought_tools.roundtrip" %in% res$check)
  expect_true(all(gptr_check(a)$ok))
})

test_that("end to end on the mock server: a Gemini stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("gemini", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$stop_reason, "stop")
})

test_that("build() takes headers from the record provider_stream() resolved (04 10.1, D-023)", {
  # D-023 items 1 and 3: a session-scoped provider (`model = <spec>`) is invisible to the global
  # lookup, so its headers come from opts$provider or the session's own record, merged by name:
  # the adapter's headers and credential win, and a record never adds a second key
  model = test_model(api, provider = "p12-gem", id = "gemini-3.8-flash")
  rec = gptr_provider("p12-gem", api = api, base_url = "https://gemini.corp.example/v1beta",
                      headers = list(`X-Org` = "lab", `Content-Type` = "text/plain",
                                     `X-Goog-Api-Key` = "record-key"))
  ctx = ctx_fixture(list(first_message()))
  h = google_build(model, ctx, list(provider = rec, credential = fake_handle("CORP_KEY")))$headers
  expect_identical(anyDuplicated(tolower(names(h))), 0L)
  expect_identical(h$`x-goog-api-key`, fake_handle("CORP_KEY"))
  expect_null(h$`X-Goog-Api-Key`)
  expect_identical(h$`content-type`, "application/json")
  expect_null(h$`Content-Type`)
  expect_identical(h$`X-Org`, "lab")
  # without a credential the record's own key header goes out as it is (D-023 item 3)
  expect_identical(google_build(model, ctx, list(provider = rec))$headers$`X-Goog-Api-Key`,
                   "record-key")
  # a record of another provider is ignored; nothing else is registered
  other = gptr_provider("p12-other", api = api, headers = list(`X-Org` = "other"))
  expect_null(google_build(model, ctx, list(provider = other))$headers$`X-Org`)
  # the session's own record when build() gets only the session id
  sid = "s_p12gem01"
  withr::defer(registry_session_drop(sid))
  registry_add(rec, source = "session", rank = 0L, session = sid)
  expect_identical(google_build(model, ctx, list(session = sid))$headers$`X-Org`, "lab")
})

test_that("a model without tool calling gets no tools or toolConfig (IC-74, 07 section 1)", {
  # 07-local-ollama.md section 1: tool calling is enabled only when the model supports it
  # (D-029.1, D-032.2 for this adapter); the history's calls and results are still sent
  forced = list(type = "tool", name = "read")
  blind = test_model(api, provider = "google", id = "gemini-3.8-flash", tool_call = FALSE)
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "nrow(d)"))), api = api,
                       provider = "google", model = "gemini-3.8-flash", stop_reason = "tool_use",
                       timestamp = 2)
  msgs = list(msg_user("x", timestamp = 1), asst, msg_tool_result("fc_1", "r", "[1] 32",
                                                                  timestamp = 3))
  for (tc in list("none", forced)) {
    body = json_decode(google_build(blind, ctx_fixture(msgs, params = list(tool_choice = tc)),
                                    list())$body)
    expect_false(any(c("tools", "toolConfig") %in% names(body)))
    expect_identical(body$contents[[2L]]$parts[[1L]]$functionCall$id, "fc_1")
    expect_identical(body$contents[[3L]]$parts[[1L]]$functionResponse$response,
                     list(output = "[1] 32"))
  }
  # a request without a tools array sends no toolConfig; a model that calls tools keeps both
  able = test_model(api, provider = "google", id = "gemini-3.8-flash")
  ctx = ctx_fixture(list(msg_user("x")), params = list(tool_choice = forced))
  ctx$tools_json = NULL
  expect_false(grepl("tool", google_build(able, ctx, list())$body, ignore.case = TRUE))
  body = json_decode(google_build(able, ctx_fixture(msgs, params = list(tool_choice = "none")),
                                  list())$body)
  expect_equal(body$toolConfig, list(functionCallingConfig = list(mode = "NONE")))
  expect_length(body$tools[[1L]]$functionDeclarations, 2L)
})

test_that("a text-only model gets the omission note in the tool output, no image content", {
  # D-023 item 4 and D-029.3 for this adapter: the note stands in the result's own output and no
  # "Tool result image:" content follows with nothing attached
  note = "(image omitted: this model does not accept images)"
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "plot(1)"))), api = api,
                       provider = "google", model = "gemini-3.8-flash", stop_reason = "tool_use")
  drawn = msg_tool_result("fc_1", "r", list(block_text("drawn"), block_image(png_b64())))
  only = msg_tool_result("fc_1", "r", list(block_image(png_b64())))
  for (id in c("gemini-3.8-flash", "gemini-2.5-flash")) {
    model = test_model(api, provider = "google", id = id, input = "text")
    for (case in list(list(res = drawn, out = paste0("drawn\n", note)),
                      list(res = only, out = note))) {
      wire = google_build(model, ctx_fixture(list(msg_user("plot"), asst, case$res)),
                          list())$body
      expect_false(grepl(png_b64(), wire, fixed = TRUE))
      body = json_decode(wire)
      expect_length(body$contents, 3L)
      fr = body$contents[[3L]]$parts[[1L]]$functionResponse
      expect_identical(fr$response, list(output = case$out), label = id)
      expect_null(fr$parts)
    }
  }
})

test_that("a forced any is mode ANY; returns = never forces a call; params and errors (IC-69)", {
  # IC-71: a forced choice only when the model allows it and `returns` is not set (auto, the
  # closing instruction and validation); IC-69: only the declared request params reach the body
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  build = function(params, msgs = list(msg_user("x")), m = model) {
    json_decode(google_build(m, ctx_fixture(msgs, params = params), list())$body)
  }
  calling = function(body) body$toolConfig$functionCallingConfig
  expect_equal(calling(build(list(tool_choice = list(type = "any")))), list(mode = "ANY"))
  expect_equal(calling(build(list(tool_choice = list(type = "auto")))), list(mode = "AUTO"))
  for (tc in list(list(type = "tool", name = "read"), list(type = "any"))) {
    body = build(list(tool_choice = tc, returns = count_schema()))
    expect_equal(calling(body), list(mode = "AUTO"))
    last = body$contents[[length(body$contents)]]
    expect_identical(last$role, "user")
    expect_match(last$parts[[1L]]$text, "JSON Schema", fixed = TRUE)
  }
  free = test_model(api, provider = "google", id = "gemini-3.8-flash", forced_tool_choice = FALSE)
  expect_equal(calling(build(list(tool_choice = list(type = "tool", name = "read")), m = free)),
               list(mode = "AUTO"))
  # a failed tool reports response.error
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "nrow(d)"))), api = api,
                       provider = "google", model = "gemini-3.8-flash", stop_reason = "tool_use")
  err = msg_tool_result("fc_1", "r", "object 'd' not found", is_error = TRUE)
  body = build(list(), list(msg_user("x"), asst, err))
  expect_identical(body$contents[[3L]]$parts[[1L]]$functionResponse,
                   list(name = "r", response = list(error = "object 'd' not found"), id = "fc_1"))
  # labels and serviceTier are the declared params, placed before contents; metadata is not
  body = build(list(labels = list(team = "lab"), service_tier = "flex", metadata = list(a = 1)))
  expect_identical(names(body), c("systemInstruction", "tools", "toolConfig", "generationConfig",
                                  "labels", "serviceTier", "contents"))
  expect_identical(body$labels, list(team = "lab"))
  expect_identical(body$serviceTier, "flex")
})
