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
