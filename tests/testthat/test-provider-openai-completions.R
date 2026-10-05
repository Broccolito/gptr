# Tests for R/provider-openai-completions.R (plan P12): compat flags, the <think> splitter,
# tool ids, the openai-completions normaliser and request body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "openai-completions"

# One chat.completion.chunk as JSON text (`delta` and `finish` are JSON text)
chat_chunk = function(delta, finish = "null", id = "c1", model = "m") {
  paste0('{"id":"', id, '","object":"chat.completion.chunk","model":"', model, '",',
         '"choices":[{"index":0,"delta":', delta, ',"finish_reason":', finish, "}]}")
}

# Push chunk data through the normaliser of a fixture model of `provider`; finish() at the end
chat_run = function(chunks, provider = "fixture", id = "fixture-1", opts = list()) {
  model = adp_fixture_model("openai-completions")
  model$provider = provider
  model$id = id
  out = new.env(parent = emptyenv())
  out$events = list()
  opts$emit = function(ev) out$events[[length(out$events) + 1L]] = ev
  n = completions_normaliser(model, opts)
  for (ch in chunks) n$push(list(data = ch))
  list(message = n$finish(), events = out$events)
}

# ---- compat flags, the <think> splitter and tool ids (Task 4) ---------------------------------

test_that("compat_flags() combines detection with the provider records of P05 (09 section 3.3)", {
  ds = compat_flags("deepseek", list(id = "deepseek-v4-pro"))
  expect_identical(ds$thinking_format, "deepseek")
  expect_true(ds$requires_reasoning_content)
  expect_identical(ds$max_tokens_field, "max_tokens")
  expect_false(ds$supports_store)
  ms = compat_flags("mistral", list(id = "devstral-medium-latest"))
  expect_identical(ms$tool_id, "alnum9")
  expect_true(ms$thinking_in_content)
  az = compat_flags("azure", list(id = "gpt-6-sol"))
  expect_identical(az$auth_header, "api-key")
  expect_true(az$deployment_model)
  ol = compat_flags("ollama", list(id = "qwen3:8b"))
  expect_false(ol$supports_store)
  expect_false(ol$supports_tool_choice)
  expect_identical(ol$max_tokens_field, "max_tokens")
  expect_true(compat_flags("together", list(id = "deepseek-r1"))$think_tags)
  groq = compat_flags("groq", list(id = "openai/gpt-oss-120b"))
  expect_identical(groq$max_tokens_field, "max_completion_tokens")
  expect_false(groq$requires_tool_result_name)
  expect_true(compat_flags("openai", NULL)$explicit_cache_mode)
  expect_identical(compat_flags(NULL, list(id = "m")), compat_defaults())
  expect_setequal(names(ds), names(compat_defaults()))
})

test_that("OpenRouter sends cache_control only for Anthropic and Google models (G4 3.7)", {
  expect_identical(compat_flags("openrouter", list(id = "anthropic/claude-sonnet-5-5"))$
                     cache_control_format, "anthropic")
  expect_identical(compat_flags("openrouter", list(id = "google/gemini-3.8-flash"))$
                     cache_control_format, "anthropic")
  expect_identical(compat_flags("openrouter", list(id = "meta/llama-5"))$cache_control_format,
                   "none")
  expect_identical(compat_flags("openrouter", list(id = "x/y"))$session_affinity, "openrouter")
})

test_that("compat_flags() applies a record's compat in snake_case or Pi's camelCase", {
  rec = list(id = "corp", base_url = "https://llm.corp.example/v1",
             compat = list(maxTokensField = "max_tokens", requires_tool_result_name = TRUE,
                           requiresReasoningContentOnAssistantMessages = TRUE,
                           base_url_env = "IGNORED"))
  cf = compat_flags(rec, list(id = "corp-large"))
  expect_identical(cf$max_tokens_field, "max_tokens")
  expect_true(cf$requires_tool_result_name)
  expect_true(cf$requires_reasoning_content)
  expect_null(cf$base_url_env)
  expect_false(compat_flags(list(id = "x", base_url = "https://api.together.xyz/v1"),
                            list(id = "m"))$supports_store)
})

test_that("Azure deployments come from AZURE_OPENAI_DEPLOYMENT_NAME_MAP (09 section 2.5)", {
  withr::local_envvar(AZURE_OPENAI_DEPLOYMENT_NAME_MAP = "gpt-6-sol=prod-sol, other=x")
  cf = compat_flags("azure", list(id = "gpt-6-sol"))
  expect_identical(completions_model_name(list(id = "gpt-6-sol"), cf), "prod-sol")
  expect_identical(completions_model_name(list(id = "gpt-6-luna"), cf), "gpt-6-luna")
  expect_identical(completions_model_name(list(id = "gpt-6-sol"),
                                          compat_flags("groq", list(id = "m"))), "gpt-6-sol")
})

test_that("the <think> splitter routes tagged text to thinking across any chunking", {
  text = "<think>Plan: count rows.</think>The answer is 32."
  for (size in c(1L, 2L, 3L, 5L, 7L, 100L)) {
    sp = think_splitter()
    segs = list()
    for (s in seq(1L, nchar(text), by = size)) {
      segs = c(segs, sp$push(substr(text, s, s + size - 1L)))
    }
    segs = c(segs, sp$flush())
    kinds = vapply(segs, function(x) x$kind, "")
    texts = vapply(segs, function(x) x$text, "")
    expect_identical(paste(texts[kinds == "thinking"], collapse = ""), "Plan: count rows.")
    expect_identical(paste(texts[kinds == "text"], collapse = ""), "The answer is 32.")
  }
  sp = think_splitter()
  expect_identical(sp$push("a <thi"), list(list(kind = "text", text = "a ")))
  expect_identical(sp$flush(), list(list(kind = "text", text = "<thi")))
})

test_that("completions_tool_id() keeps ids within each provider's rules", {
  cf = compat_flags("groq", list(id = "m"))
  expect_identical(completions_tool_id("call_9Zx8Yw7Vu6|fc_0a1b2c", cf),
                   "call_9Zx8Yw7Vu6_fc_0a1b2c")
  long = completions_tool_id(paste0("call_", strrep("a", 40), "|fc_", strrep("b", 40)), cf)
  expect_lte(nchar(long), 40L)
  expect_match(long, "^[A-Za-z0-9_-]+$")
  nine = completions_tool_id("toolu_01A", compat_flags("mistral", list(id = "m")))
  expect_match(nine, "^[A-Za-z0-9]{9}$")
  expect_identical(completions_tool_id("toolu_01A", compat_flags("mistral", list(id = "m"))),
                   nine)
  expect_identical(nchar(completions_tool_id(strrep("c", 50), cf, "openai")), 40L)
})

# ---- the normaliser (Task 4) -------------------------------------------------------------------

test_that("a mid-stream error chunk and a truncated stream each give one error event", {
  for (case in c("error_chunk", "truncated")) {
    ev = replay_case(api, completions_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
    expect_identical(ev[[length(ev)]]$message$content[[1L]]$type, "text")
  }
})

test_that("a missing finish_reason is inferred only when the compat record says so", {
  off = gptr_register(gptr_provider("corpx", api = "openai-completions",
                                    base_url = "http://127.0.0.1:9/v1",
                                    compat = list(supports_finish_reason = FALSE),
                                    local = TRUE, offline = TRUE))
  withr::defer(off())
  log = event_log()
  n = completions_normaliser(test_model(api, provider = "corpx"), list(emit = log$emit))
  n$push(list(data = '{"id":"c1","choices":[{"index":0,"delta":{"content":"ok"}}]}'))
  msg = n$finish()
  expect_identical(msg$stop_reason, "stop")
  expect_identical(log$events[[length(log$events)]]$type, "done")
})

test_that("Mistral thinking arrives as content items and becomes a thinking block", {
  log = event_log()
  n = completions_normaliser(test_model(api, provider = "mistral"), list(emit = log$emit))
  n$push(list(data = paste0('{"id":"m1","choices":[{"index":0,"delta":{"content":[',
                            '{"type":"thinking","thinking":[{"type":"text","text":"Hmm."}]},',
                            '{"type":"text","text":"Done."}]}}]}')))
  n$push(list(data = '{"id":"m1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'))
  msg = n$finish()
  expect_identical(vapply(msg$content, function(b) b$type, ""), c("thinking", "text"))
  expect_identical(msg$content[[1L]]$thinking, "Hmm.")
})

# ---- additions beyond the plan (IC-74 and contract typing) -------------------------------------

test_that("an Ollama chat stream keeps reasoning, tool calls, usage and the output limit (IC-74)", {
  # 07-local-ollama.md section 6, P12 row: Ollama chat goes through openai-completions; streaming,
  # tool support and reasoning/output limits of capable models (report 04b: the reasoning field
  # can use up the budget and end with finish_reason "length" and no content)
  q = "qwen3:8b"
  r = chat_run(c(
    chat_chunk('{"role":"assistant","content":"","reasoning":"Sum them."}', id = "chatcmpl-7",
               model = q),
    chat_chunk(paste0('{"role":"assistant","content":"","tool_calls":[{"id":"call_k3x9",',
                      '"index":0,"type":"function","function":{"name":"sum_numbers",',
                      '"arguments":"{\\"a\\":7,\\"b\\":5}"}}]}'), id = "chatcmpl-7", model = q),
    chat_chunk('{"role":"assistant","content":""}', '"tool_calls"', id = "chatcmpl-7", model = q),
    paste0('{"id":"chatcmpl-7","object":"chat.completion.chunk","model":"', q, '",',
           '"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":30,',
           '"total_tokens":150}}'),
    "[DONE]"
  ), provider = "ollama", id = q)
  expect_one_terminal(r$events)
  m = r$message
  expect_identical(vapply(m$content, function(b) b$type, ""), c("thinking", "tool_call"))
  expect_identical(m$content[[1L]]$thinking, "Sum them.")
  expect_identical(m$content[[1L]]$signature, "reasoning")
  expect_identical(c(m$content[[2L]]$id, m$content[[2L]]$name), c("call_k3x9", "sum_numbers"))
  expect_equal(m$content[[2L]]$arguments, list(a = 7, b = 5))
  expect_identical(c(m$stop_reason, m$raw_stop_reason), c("tool_use", "tool_calls"))
  expect_null(m$response_model)
  expect_identical(c(m$usage$input, m$usage$output, m$usage$cache_read, m$usage$total),
                   c(120, 30, 0, 150))
  # the reasoning used up the output budget: a length stop with the thinking kept, no text
  r = chat_run(c(
    chat_chunk('{"role":"assistant","content":"","reasoning":"Let me think about"}', model = q),
    chat_chunk('{"role":"assistant","content":""}', '"length"', model = q),
    "[DONE]"
  ), provider = "ollama", id = q)
  expect_identical(types_of(r$events), c("start", "thinking_start", "thinking_delta",
                                         "thinking_end", "done"))
  expect_identical(r$events[[5L]]$reason, "length")
  expect_identical(vapply(r$message$content, function(b) b$type, ""), "thinking")
  expect_identical(r$message$content[[1L]]$thinking, "Let me think about")
})

test_that("unreported or null usage stays unknown; fields left out keep P05's zero (IC-74)", {
  usage_of = function(usage) {
    r = chat_run(c(chat_chunk('{"content":"x"}', '"stop"'),
                   paste0('{"id":"c1","choices":[],"usage":', usage, "}"), "[DONE]"))
    u = r$message$usage
    c(input = u$input, output = u$output, cache_read = u$cache_read, total = u$total)
  }
  # no usage at all ("usage": null in every chunk is no report): every count and the cost unknown
  r = chat_run(c(chat_chunk('{"content":"x"}'),
                 paste0('{"id":"c1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],',
                        '"usage":null}'), "[DONE]"))
  expect_identical(r$message$stop_reason, "stop")
  u = r$message$usage
  expect_identical(c(u$input, u$output, u$cache_read, u$total), rep(NA_real_, 4L))
  expect_identical(u$cost$total, NA_real_)
  # a reported null is unknown, not zero
  expect_identical(usage_of('{"prompt_tokens":null,"completion_tokens":5}'),
                   c(input = NA, output = 5, cache_read = 0, total = NA))
  # DeepSeek reports cache hits at the top level; a null cached_tokens falls back to it
  expect_identical(usage_of(paste0('{"prompt_tokens":100,"completion_tokens":10,',
                                   '"prompt_cache_hit_tokens":60,"prompt_cache_miss_tokens":40}')),
                   c(input = 40, output = 10, cache_read = 60, total = 110))
  expect_identical(usage_of(paste0('{"prompt_tokens":100,"completion_tokens":10,',
                                   '"prompt_tokens_details":{"cached_tokens":null},',
                                   '"prompt_cache_hit_tokens":60}')),
                   c(input = 40, output = 10, cache_read = 60, total = 110))
  # a null cache count with nothing else reported leaves the cache read and the input unknown
  expect_identical(usage_of(paste0('{"prompt_tokens":100,"completion_tokens":10,',
                                   '"prompt_tokens_details":{"cached_tokens":null}}')),
                   c(input = NA, output = 10, cache_read = NA, total = NA))
  # fields the provider left out of a reported usage keep the legacy zero
  expect_identical(usage_of('{"prompt_tokens":100,"completion_tokens":10}'),
                   c(input = 100, output = 10, cache_read = 0, total = 110))
})

test_that("non-string finish reasons are never matched by position (04 4.2)", {
  # R's switch() picks an alternative by position for a number: 2 would have been "stop"
  r = chat_run(c(chat_chunk('{"content":"x"}', "2"), "[DONE]"))
  expect_identical(r$message$stop_reason, "error")
  expect_identical(r$message$raw_stop_reason, "2")
  last = r$events[[length(r$events)]]
  expect_identical(c(last$type, last$error$class), c("error", "provider"))
  r = chat_run(c(chat_chunk('{"content":"x"}', '"content_filter"'), "[DONE]"))
  expect_identical(c(r$message$stop_reason, r$message$raw_stop_reason),
                   c("error", "content_filter"))
  expect_identical(r$message$error_message, "Provider finish_reason: content_filter")
})

test_that("the compat record comes from the provider record provider_stream() resolved (04 10.1)", {
  # a provider passed as `model = <spec>` is a session-scoped record the global lookup never sees
  rec = function(id, finish) {
    gptr_provider(id, api = "openai-completions", base_url = "http://127.0.0.1:9/v1",
                  compat = list(supports_finish_reason = finish), local = TRUE, offline = TRUE)
  }
  no_finish = c(chat_chunk('{"content":"ok"}'), "[DONE]")
  stop_of = function(opts) {
    chat_run(no_finish, provider = "p12-corpy", opts = opts)$message$stop_reason
  }
  expect_identical(stop_of(list(provider = rec("p12-corpy", FALSE))), "stop")
  # a record of another provider is not used; nothing else is registered, so the defaults apply
  expect_identical(stop_of(list(provider = rec("p12-other", FALSE))), "error")
  expect_identical(stop_of(list()), "error")
  # the session's own record when the normaliser gets only the session id
  sid = "s_p12compat01"
  withr::defer(registry_session_drop(sid))
  registry_add(rec("p12-corpy", FALSE), source = "session", rank = 0L, session = sid)
  expect_identical(stop_of(list(session = sid)), "stop")
  # a session record over a global one with the same id: the session's wins
  off = gptr_register(rec("p12-corpy", TRUE))
  withr::defer(off())
  expect_identical(stop_of(list(session = sid)), "stop")
  expect_identical(stop_of(list()), "error")
})

test_that("a string error, object arguments and a bare Mistral thinking string are kept", {
  # an error given as a bare string is the provider's message, not an internal adapter error
  r = chat_run(c(chat_chunk('{"content":"x"}'), '{"id":"c1","error":"Model unloaded"}'))
  last = r$events[[length(r$events)]]
  expect_identical(c(last$type, last$error$class), c("error", "provider"))
  expect_identical(r$message$error_message, "Model unloaded")
  # tool arguments sent as a parsed object are serialised back to JSON text
  r = chat_run(c(chat_chunk(paste0('{"tool_calls":[{"index":0,"id":"call_1","type":"function",',
                                   '"function":{"name":"sum","arguments":{"a":7}}}]}'),
                            '"tool_calls"'), "[DONE]"))
  expect_identical(r$message$stop_reason, "tool_use")
  expect_equal(r$message$content[[1L]]$arguments, list(a = 7))
  # a Mistral thinking item whose `thinking` is a bare string
  r = chat_run(c(chat_chunk('{"content":[{"type":"thinking","thinking":"Hmm."}]}', '"stop"'),
                 "[DONE]"), provider = "mistral")
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(r$message$content[[1L]]$thinking, "Hmm.")
})

test_that("an error chunk before any delta is handed to the transport's retry (09 2.4, 08 3.5)", {
  # OpenRouter's mid-stream error chunk before content: the transport may restart the request
  log = event_log()
  retried = event_log()
  n = completions_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  expect_false(n$push(list(data = '{"id":"c1","error":{"code":429,"message":"slow"}}')))
  expect_length(retried$events, 1L)
  expect_identical(retried$events[[1L]], list(class = "rate_limit", status = 429L,
                                              retry_after = NULL))
  expect_length(log$events, 0L)
  expect_false(n$push(list(data = chat_chunk('{"content":"late"}'))))
  msg = n$finish()
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(c(msg$stop_reason, msg$error_message), c("error", "slow"))
  expect_identical(log$events[[2L]]$error[c("class", "status")],
                   list(class = "rate_limit", status = 429L))
  # after the first delta the same failure is final and the transport is not asked
  r = chat_run(c(chat_chunk('{"content":"x"}'), '{"error":{"code":502,"message":"upstream"}}'),
               opts = list(retry = retried$emit))
  expect_length(retried$events, 1L)
  last = r$events[[length(r$events)]]
  expect_identical(list(last$type, last$error$class, last$error$status),
                   list("error", "overloaded", 502L))
  expect_identical(r$message$content[[1L]]$text, "x")
  # a spend cap is never retried, even before any delta
  r = chat_run('{"error":{"code":429,"type":"insufficient_quota","message":"quota"}}',
               opts = list(retry = retried$emit))
  expect_length(retried$events, 1L)
  expect_identical(r$events[[length(r$events)]]$error$class, "spend_cap")
  # the classification rows of completions_error_info()
  info = function(x) completions_error_info(x)[c("class", "status", "retry")]
  expect_identical(info(list(type = "insufficient_quota")),
                   list(class = "spend_cap", status = 429L, retry = FALSE))
  expect_identical(info(list(code = "credit_balance_too_low")),
                   list(class = "spend_cap", status = 429L, retry = FALSE))
  expect_identical(info(list(code = "rate_limit_exceeded")),
                   list(class = "rate_limit", status = 429L, retry = TRUE))
  expect_identical(info(list(type = "server_error")),
                   list(class = "overloaded", status = 503L, retry = TRUE))
  expect_identical(info(list(code = 504)), list(class = "overloaded", status = 504L, retry = TRUE))
  expect_identical(info(list(code = 400, message = "bad")),
                   list(class = "provider", status = 400L, retry = FALSE))
  expect_identical(info("Model unloaded"),
                   list(class = "provider", status = NA_integer_, retry = FALSE))
})

test_that("an error code that is not an HTTP status is never coerced (04 8.1, D-027)", {
  # only one whole number from 100 to 599 is a status (google_error_info()'s rule, D-034): an
  # integer overflow would warn, and normalisers signal no R condition after start
  info = function(x) completions_error_info(x)[c("class", "status", "retry")]
  provider = list(class = "provider", status = NA_integer_, retry = FALSE)
  for (code in list(1e10, -1e10, Inf, NaN, 429.5, 99, 600, c(429, 500))) {
    expect_identical(expect_no_warning(info(list(code = code))), provider,
                     label = paste("code", paste(code, collapse = ",")))
  }
  expect_identical(info(list(code = 1e10, type = "server_error")),
                   list(class = "overloaded", status = 503L, retry = TRUE))
  expect_identical(info(list(code = 429L)), list(class = "rate_limit", status = 429L, retry = TRUE))
  r = expect_no_warning(chat_run('{"error":{"code":1e10,"message":"Huge."}}'))
  expect_identical(types_of(r$events), c("start", "error"))
  expect_identical(r$events[[2L]]$error$class, "provider")
  expect_null(r$events[[2L]]$error$status)
  expect_identical(r$message$error_message, "Huge.")
})

test_that("OpenRouter reasoning_details become one opaque block, merged as Pi does (09 2.3)", {
  # consecutive reasoning.text / reasoning.summary fragments of one index are joined, the closing
  # signature kept; reasoning.encrypted stays discrete; a single object counts as one item
  det = function(...) paste0('{"reasoning_details":', paste0(...), "}")
  txt = function(text, sig = "null", index = 0L) {
    paste0('[{"type":"reasoning.text","text":"', text, '","signature":', sig,
           ',"format":"anthropic-claude-v1","index":', index, "}]")
  }
  r = chat_run(c(
    chat_chunk('{"reasoning":"Let ","reasoning_details":[]}'),
    chat_chunk(det(txt("Let "))),
    chat_chunk(paste0('{"reasoning":"me.","reasoning_details":', txt("me."), "}")),
    chat_chunk(det(txt("", '"sig-abc"'))),
    chat_chunk(det('{"type":"reasoning.encrypted","data":"enc+/1=","id":"rs_1",',
                   '"format":"openai-responses-v1","index":1}')),
    chat_chunk(det('[{"type":"reasoning.summary","summary":"Plan","index":2},',
                   '{"type":"reasoning.summary","summary":"ned.","index":2}]')),
    chat_chunk(det(txt("Again", index = 0L))),
    chat_chunk(det(txt("Other", index = 3L))),
    chat_chunk('{"content":"Hi"}', '"stop"'),
    "[DONE]"
  ), provider = "openrouter", id = "anthropic/claude-sonnet-5-5")
  expect_one_terminal(r$events)
  m = r$message
  expect_identical(vapply(m$content, function(b) b$type, ""), c("thinking", "text", "opaque"))
  expect_identical(c(m$content[[1L]]$thinking, m$content[[1L]]$signature),
                   c("Let me.", "reasoning"))
  op = m$content[[3L]]
  expect_identical(c(op$provider, op$api, op$model),
                   c("openrouter", "openai-completions", "anthropic/claude-sonnet-5-5"))
  expect_identical(op$json, paste0(
    '[{"type":"reasoning.text","text":"Let me.","signature":"sig-abc",',
    '"format":"anthropic-claude-v1","index":0},',
    '{"type":"reasoning.encrypted","data":"enc+/1=","id":"rs_1",',
    '"format":"openai-responses-v1","index":1},',
    '{"type":"reasoning.summary","summary":"Planned.","index":2},',
    '{"type":"reasoning.text","text":"Again","signature":null,',
    '"format":"anthropic-claude-v1","index":0},',
    '{"type":"reasoning.text","text":"Other","signature":null,',
    '"format":"anthropic-claude-v1","index":3}]'))
  # opaque data is never streamed
  expect_false(any(grepl("opaque", types_of(r$events))))
  # fragments with different ids are not merged, a fragment without an id joins the open item
  # and a null item is dropped; a stream without details has no opaque block
  r = chat_run(c(
    chat_chunk(det('[{"type":"reasoning.text","text":"a","id":"r1","index":0}]')),
    chat_chunk(det('[{"type":"reasoning.text","text":"b","id":"r2","index":0}]')),
    chat_chunk(det('[null,{"type":"reasoning.text","text":"c","index":0}]')),
    chat_chunk('{"content":"ok"}', '"stop"'), "[DONE]"
  ), provider = "openrouter", id = "x/y")
  expect_identical(r$message$content[[2L]]$json, paste0(
    '[{"type":"reasoning.text","text":"a","id":"r1","index":0},',
    '{"type":"reasoning.text","text":"bc","id":"r2","index":0}]'))
  r = chat_run(c(chat_chunk('{"content":"ok"}', '"stop"'), "[DONE]"), provider = "openrouter")
  expect_identical(vapply(r$message$content, function(b) b$type, ""), "text")
})

# ---- the request body and the built-in (Task 5) ------------------------------------------------

completions_turn2 = function(model) {
  asst = msg_assistant(list(block_thinking("Need the row count.", signature = "reasoning_content"),
                            block_text("Checking."),
                            block_tool_call("call_A1", "r", list(code = "nrow(d)"))),
                       api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use", timestamp = 2)
  # first_message() comes from replay_helpers.R, sourced at run time where lintr cannot see it
  first = first_message() # nolint: object_usage_linter.
  list(first, asst, msg_tool_result("call_A1", "r", "[1] 32", timestamp = 3))
}

test_that("completions bodies: one system message, converted tools, the messages last", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  req = completions_build(model, ctx_fixture(list(first_message())),
                          list(base_url = "https://api.groq.com/openai/v1"))
  body = json_decode(req$body)
  expect_identical(names(body), c("model", "stream", "stream_options", "store",
                                  "max_completion_tokens", "tools", "messages"))
  expect_equal(body$stream_options, list(include_usage = TRUE))
  expect_identical(body$messages[[1L]]$role, "developer")
  expect_identical(body$messages[[1L]]$content, "T0 static sections.\n\nT1 catalogs.")
  expect_identical(body$tools[[2L]]$`function`$name, "r")
  expect_identical(body$tools[[2L]]$`function`$parameters$required, list("code"))
  expect_identical(req$url, "https://api.groq.com/openai/v1/chat/completions")
})

test_that("OpenRouter Anthropic models get cache_control on the system and project blocks", {
  model = test_model(api, provider = "openrouter", id = "anthropic/claude-sonnet-5-5")
  req = completions_build(model, ctx_fixture(list(first_message())), list())
  body = json_decode(req$body)
  sys = body$messages[[1L]]$content
  expect_equal(sys[[length(sys)]]$cache_control, list(type = "ephemeral"))
  user = body$messages[[2L]]$content
  expect_equal(user[[1L]]$cache_control, list(type = "ephemeral"))
  expect_null(user[[2L]]$cache_control)
  expect_identical(req$headers$`x-session-id`, "s0123456789")
  expect_identical(req$headers$`X-OpenRouter-Title`, "gptr")
  none = list(anchors = character(), tail_ttl = "5m", key = "gptr:0123456789ab")
  expect_false(grepl("cache_control",
                     completions_build(model, ctx_fixture(list(first_message()), cache_plan = none),
                                       list())$body, fixed = TRUE))
  model$id = "meta/llama-5"
  expect_false(grepl("cache_control", completions_build(model, ctx_fixture(list(first_message())),
                                                        list())$body, fixed = TRUE))
})

test_that("the default cache policy anchors the OpenRouter system and project blocks", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "project"))
  model = test_model(api, provider = "openrouter", id = "google/gemini-3.8-flash")
  body = json_decode(completions_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                                       list())$body)
  sys = body$messages[[1L]]$content
  expect_equal(sys[[length(sys)]]$cache_control, list(type = "ephemeral"))
  expect_equal(body$messages[[2L]]$content[[1L]]$cache_control, list(type = "ephemeral"))
  groq = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  expect_false(grepl("cache_control",
                     completions_build(groq, ctx_fixture(list(first_message()), cache_plan = plan),
                                       list())$body, fixed = TRUE))
})

test_that("reasoning is replayed in its own field to the same model; DeepSeek forces the field", {
  model = test_model(api, provider = "together", id = "deepseek-r1")
  body = json_decode(completions_build(model, ctx_fixture(completions_turn2(model)), list())$body)
  asst = body$messages[[3L]]
  expect_identical(asst$reasoning_content, "Need the row count.")
  expect_identical(asst$content, "Checking.")
  expect_identical(asst$tool_calls[[1L]]$`function`$arguments, "{\"code\":\"nrow(d)\"}")
  expect_identical(body$messages[[4L]], list(role = "tool", tool_call_id = "call_A1",
                                             content = "[1] 32"))
  ds = test_model(api, provider = "deepseek", id = "deepseek-v4-pro")
  msgs = completions_turn2(test_model(api, provider = "other", id = "x"))
  asst = json_decode(completions_build(ds, ctx_fixture(msgs), list())$body)$messages[[3L]]
  expect_identical(asst$reasoning_content, "")
})

test_that("tool-result images follow as one user message; Mistral ids are 9 characters", {
  model = test_model(api, provider = "mistral", id = "pixtral-large")
  msgs = completions_turn2(model)
  msgs[[3L]] = msg_tool_result("call_A1", "r", list(block_text("plot drawn"),
                                                    block_image(png_b64())))
  body = json_decode(completions_build(model, ctx_fixture(msgs), list())$body)
  tool = body$messages[[4L]]
  expect_identical(tool$role, "tool")
  expect_match(tool$tool_call_id, "^[A-Za-z0-9]{9}$")
  expect_identical(body$messages[[3L]]$tool_calls[[1L]]$id, tool$tool_call_id)
  img = body$messages[[5L]]
  expect_identical(img$role, "user")
  expect_identical(img$content[[2L]]$image_url$url, paste0("data:image/png;base64,", png_b64()))
})

test_that("no tools but tool calls in history sends tools: []; max_tokens per compat", {
  model = test_model(api, provider = "deepseek", id = "deepseek-v4-pro")
  ctx = ctx_fixture(completions_turn2(model), params = list(max_tokens = 2000L))
  ctx$tools_json = NULL
  body = json_decode(completions_build(model, ctx, list())$body)
  expect_identical(body$tools, list())
  expect_identical(body$max_tokens, 2000L)
  expect_null(body$max_completion_tokens)
})

test_that("thinking formats, tool_choice and auth headers follow the compat record", {
  model = test_model(api, provider = "openrouter", id = "openai/gpt-6-sol")
  forced = list(type = "tool", name = "read")
  req = completions_build(model, ctx_fixture(list(msg_user("x")),
                                             params = list(thinking = "low",
                                                           tool_choice = forced)),
                          list(credential = fake_handle("OPENROUTER_API_KEY")))
  body = json_decode(req$body)
  expect_equal(body$reasoning, list(effort = "low"))
  expect_equal(body$tool_choice, list(type = "function", `function` = list(name = "read")))
  expect_identical(req$headers$authorization, list("Bearer ", fake_handle("OPENROUTER_API_KEY")))
  no = test_model(api, provider = "groq", capabilities = list(forced_tool_choice = FALSE))
  body = json_decode(completions_build(no, ctx_fixture(list(msg_user("x")),
                                                       params = list(tool_choice = forced)),
                                       list())$body)
  expect_null(body$tool_choice)
  ol = test_model(api, provider = "ollama", id = "qwen3:8b")
  body = json_decode(completions_build(ol, ctx_fixture(list(msg_user("x")),
                                                       params = list(tool_choice = "none")),
                                       list())$body)
  expect_null(body$tool_choice)
  az = test_model(api, provider = "azure", id = "gpt-6-sol")
  req = completions_build(az, ctx_fixture(list(msg_user("x"))),
                          list(credential = fake_handle("AZURE_OPENAI_API_KEY")))
  expect_identical(req$headers$`api-key`, fake_handle("AZURE_OPENAI_API_KEY"))
  expect_null(req$headers$authorization)
})

test_that("returns = becomes an instruction with auto tool choice (IC-71)", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  body = json_decode(completions_build(model, ctx_fixture(list(msg_user("x")),
                                                          params = list(returns = count_schema())),
                                       list())$body)
  last = body$messages[[length(body$messages)]]
  expect_identical(last$role, "user")
  expect_match(last$content, "JSON Schema", fixed = TRUE)
  expect_null(body$tool_choice)
  expect_null(body$response_format)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  memo = new.env(parent = emptyenv())
  b1 = completions_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = completions_build(model, ctx_fixture(completions_turn2(model)), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, completions_build(model, ctx_fixture(completions_turn2(model)),
                                         list())$body)
})

test_that("end to end on the mock server: a Chat Completions stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("chat_completions", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$usage$input, 100)
})

test_that("build() takes compat and headers from the record provider_stream() resolved (04 10.1)", {
  # D-023, D-027 item 3: a session-scoped provider (`model = <spec>`) is invisible to the global
  # lookup, so its compat and headers come from opts$provider or the session's own record
  model = test_model(api, provider = "p12-corp", id = "corp-large")
  rec = gptr_provider("p12-corp", api = api, base_url = "https://llm.corp.example/v1",
                      compat = list(maxTokensField = "max_tokens", auth_header = "api-key",
                                    supports_developer_role = FALSE),
                      headers = list(`X-Org` = "lab", `Content-Type` = "text/plain",
                                     Authorization = "Bearer record"))
  ctx = ctx_fixture(list(msg_user("x")))
  req = completions_build(model, ctx, list(provider = rec, credential = fake_handle("CORP_KEY")))
  body = json_decode(req$body)
  expect_identical(body$max_tokens, 1024L)
  expect_null(body$max_completion_tokens)
  expect_identical(body$messages[[1L]]$role, "system")
  h = req$headers
  expect_identical(anyDuplicated(tolower(names(h))), 0L)
  expect_identical(h$`api-key`, fake_handle("CORP_KEY"))
  expect_false("authorization" %in% tolower(names(h)))
  expect_identical(h$`content-type`, "application/json")
  expect_identical(h$`X-Org`, "lab")
  # without a credential the record's own credential header goes out as it is (D-023 item 3)
  expect_identical(completions_build(model, ctx, list(provider = rec))$headers$Authorization,
                   "Bearer record")
  # a record of another provider is ignored; nothing else is registered, so the defaults apply
  other = gptr_provider("p12-other", api = api, compat = list(max_tokens_field = "max_tokens"),
                        headers = list(`X-Org` = "other"))
  req = completions_build(model, ctx, list(provider = other))
  expect_identical(json_decode(req$body)$max_completion_tokens, 1024L)
  expect_null(req$headers$`X-Org`)
  # the session's own record when build() gets only the session id
  sid = "s_p12build01"
  withr::defer(registry_session_drop(sid))
  registry_add(rec, source = "session", rank = 0L, session = sid)
  req = completions_build(model, ctx, list(session = sid))
  expect_identical(json_decode(req$body)$max_tokens, 1024L)
  expect_identical(req$headers$`X-Org`, "lab")
})

test_that("a model without tool calling gets no tools and no tool_choice (IC-74, 07 section 1)", {
  # P05 prepares an Ollama model with tool_call = FALSE when the server lacks the tools capability
  forced = list(type = "tool", name = "read")
  blind = test_model(api, provider = "groq", id = "small-1", tool_call = FALSE)
  for (tc in list("none", forced)) {
    body = json_decode(completions_build(blind, ctx_fixture(completions_turn2(blind),
                                                            params = list(tool_choice = tc)),
                                         list())$body)
    expect_false(any(c("tools", "tool_choice") %in% names(body)))
    expect_identical(body$messages[[3L]]$tool_calls[[1L]]$id, "call_A1")
  }
  # a request without any tools sends no tool_choice either; a model that calls tools keeps both
  able = test_model(api, provider = "groq", id = "large-1")
  ctx = ctx_fixture(list(msg_user("x")), params = list(tool_choice = "none"))
  ctx$tools_json = NULL
  expect_false(grepl("tool", completions_build(able, ctx, list())$body, fixed = TRUE))
  body = json_decode(completions_build(able, ctx_fixture(list(msg_user("x")),
                                                         params = list(tool_choice = "none")),
                                       list())$body)
  expect_identical(body$tool_choice, "none")
  expect_length(body$tools, 2L)
})

test_that("Ollama chat bodies follow the prepared model's capabilities (IC-74, 07 section 6)", {
  # the P05 ollama record: system role, no store, `max_tokens`, reasoning_effort, no tool_choice;
  # reasoning replays in the field Ollama streamed it in (`reasoning`, Task 4)
  ol = test_model(api, provider = "ollama", id = "qwen3:8b", input = "text")
  asst = msg_assistant(list(block_thinking("Count first.", signature = "reasoning"),
                            block_tool_call("call_1", "r", list(code = "nrow(d)"))),
                       api = api, provider = "ollama", model = "qwen3:8b",
                       stop_reason = "tool_use", timestamp = 2)
  msgs = list(msg_user("How many rows?", timestamp = 1), asst,
              msg_tool_result("call_1", "r", list(block_text("[1] 32"), block_image(png_b64())),
                              timestamp = 3))
  ctx = ctx_fixture(msgs, params = list(thinking = "medium", max_tokens = 4096L,
                                        tool_choice = "none"))
  req = completions_build(ol, ctx, list(base_url = "http://127.0.0.1:11434/v1"))
  body = json_decode(req$body)
  expect_identical(names(body), c("model", "stream", "stream_options", "max_tokens",
                                  "reasoning_effort", "tools", "messages"))
  expect_identical(c(body$model, body$reasoning_effort), c("qwen3:8b", "medium"))
  expect_identical(body$max_tokens, 4096L)
  expect_identical(vapply(body$tools, function(t) t$`function`$name, ""), c("read", "r"))
  expect_identical(vapply(body$messages, function(m) m$role, ""),
                   c("system", "user", "assistant", "tool"))
  expect_identical(body$messages[[3L]]$reasoning, "Count first.")
  expect_true("content" %in% names(body$messages[[3L]]))
  expect_null(body$messages[[3L]]$content)
  # a text-only model gets the omission note in place of the image, and no image message
  expect_identical(body$messages[[4L]]$content, paste0("[1] 32\n", adp_image_note()))
  expect_identical(req$url, "http://127.0.0.1:11434/v1/chat/completions")
  expect_false(any(c("authorization", "api-key") %in% tolower(names(req$headers))))
  # a vision model gets the image after the tool message
  vl = test_model(api, provider = "ollama", id = "qwen3-vl:8b")
  img = json_decode(completions_build(vl, ctx, list())$body)$messages[[5L]]
  expect_identical(img$content[[2L]]$image_url$url, paste0("data:image/png;base64,", png_b64()))
  # thinking off where the model can switch it off; no reasoning field without thinking
  off = completions_build(ol, ctx_fixture(list(msg_user("x")), params = list(thinking = "off")),
                          list())
  expect_identical(json_decode(off$body)$reasoning_effort, "none")
  plain = test_model(api, provider = "ollama", id = "gemma3:4b", reasoning = FALSE,
                     thinking_levels = "off")
  expect_null(json_decode(completions_build(plain, ctx, list())$body)$reasoning_effort)
})

test_that("an image-only tool result for a text-only model carries only the omission note", {
  # D-023 item 4: no "(see attached image)" lead when no image is attached
  blind = test_model(api, provider = "groq", id = "openai/gpt-oss-120b", input = "text")
  msgs = completions_turn2(blind)
  msgs[[3L]] = msg_tool_result("call_A1", "r", list(block_image(png_b64())), timestamp = 3)
  body = json_decode(completions_build(blind, ctx_fixture(msgs), list())$body)
  expect_length(body$messages, 4L)
  expect_identical(body$messages[[4L]]$content, adp_image_note())
  vision = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  body = json_decode(completions_build(vision, ctx_fixture(msgs), list())$body)
  expect_identical(body$messages[[4L]]$content, "(see attached image)")
  expect_identical(body$messages[[5L]]$role, "user")
})

test_that("the bridging assistant message precedes every user message after tool results", {
  # requires_assistant_after_tool_result: a user message never directly follows tool results,
  # neither the returns instruction nor the message carrying the results' images, which the
  # bridge precedes (report 09 section 3.2; Pi 1426-1461, 1443-1448)
  model = test_model(api, provider = "p12-bridge", id = "m1")
  rec = list(id = "p12-bridge", compat = list(requiresAssistantAfterToolResult = TRUE))
  build = function(params, msgs = completions_turn2(model), m = model) {
    json_decode(completions_build(m, ctx_fixture(msgs, params = params),
                                  list(provider = rec))$body)$messages
  }
  roles = function(...) vapply(build(...), function(x) x$role, "")
  expect_identical(roles(list(returns = count_schema())),
                   c("developer", "user", "assistant", "tool", "assistant", "user"))
  expect_identical(roles(list()), c("developer", "user", "assistant", "tool"))
  plot = completions_turn2(model)
  plot[[3L]] = msg_tool_result("call_A1", "r", list(block_text("plot drawn"),
                                                    block_image(png_b64())), timestamp = 3)
  nxt = c(plot, list(msg_user("next", timestamp = 4)))
  bridged = c("developer", "user", "assistant", "tool", "assistant", "user")
  msgs = build(list(), plot)
  expect_identical(vapply(msgs, function(x) x$role, ""), bridged)
  expect_identical(msgs[[5L]]$content, "I have processed the tool results.")
  expect_identical(msgs[[6L]]$content[[2L]]$type, "image_url")
  # the image message is the user message the bridge was for: no second bridge after it
  expect_identical(roles(list(), nxt), c(bridged, "user"))
  expect_identical(roles(list(returns = count_schema()), plot), c(bridged, "user"))
  # a text-only model attaches no image, so the bridge goes before the next user message only
  blind = test_model(api, provider = "p12-bridge", id = "m1", input = "text")
  expect_identical(roles(list(), plot, blind), c("developer", "user", "assistant", "tool"))
  expect_identical(roles(list(), nxt, blind), bridged)
})

test_that("memoised pieces follow the model's image input and the compat record", {
  memo = new.env(parent = emptyenv())
  msgs = list(msg_user(list(block_text("Look."), block_image(png_b64())), timestamp = 1))
  vision = test_model(api, provider = "p12-memo", id = "m1")
  blind = test_model(api, provider = "p12-memo", id = "m1", input = "text")
  expect_match(completions_build(vision, ctx_fixture(msgs), list(memo = memo))$body, "image_url",
               fixed = TRUE)
  expect_identical(completions_build(blind, ctx_fixture(msgs), list(memo = memo))$body,
                   completions_build(blind, ctx_fixture(msgs), list())$body)
  turn = completions_turn2(vision)
  plain = list(id = "p12-memo")
  named = list(id = "p12-memo", compat = list(requires_tool_result_name = TRUE))
  completions_build(vision, ctx_fixture(turn), list(memo = memo, provider = plain))
  body = completions_build(vision, ctx_fixture(turn), list(memo = memo, provider = named))$body
  expect_identical(json_decode(body)$messages[[4L]]$name, "r")
  # an assistant piece follows the compat record and the model's reasoning flag
  past = completions_turn2(test_model(api, provider = "other", id = "x"))
  forced = list(id = "p12-memo", compat = list(requires_reasoning_content = TRUE))
  asst = function(m, rec) {
    json_decode(completions_build(m, ctx_fixture(past),
                                  list(memo = memo, provider = rec))$body)$messages[[3L]]
  }
  expect_null(asst(vision, plain)$reasoning_content)
  expect_identical(asst(vision, forced)$reasoning_content, "")
  flat = test_model(api, provider = "p12-memo", id = "m1", reasoning = FALSE)
  expect_false("reasoning_content" %in% names(asst(flat, forced)))
})

test_that("a resolved model whose record omits tool_call gets no tools (P05, IC-74)", {
  # P05's model_resolve() turns an omitted tool_call into FALSE (user and plugin models, generic
  # local ids): such a model gets no tools until its record says tool_call = TRUE (D-029.1)
  off = gptr_register(gptr_provider("p12-resolve", api = api,
                                    base_url = "https://llm.corp.example/v1",
                                    models = list(list(id = "corp-large"),
                                                  list(id = "corp-tools", tool_call = TRUE))))
  withr::defer(off())
  for (ref in c("p12-resolve/corp-large", "lmstudio/qwen3-coder")) {
    m = model_resolve(ref)
    expect_false(m$tool_call)
    body = json_decode(completions_build(m, ctx_fixture(completions_turn2(m)), list())$body)
    expect_false(any(c("tools", "tool_choice") %in% names(body)))
  }
  m = model_resolve("p12-resolve/corp-tools")
  expect_true(m$tool_call)
  body = json_decode(completions_build(m, ctx_fixture(completions_turn2(m)), list())$body)
  expect_null(body$tool_choice)
  expect_identical(vapply(body$tools, function(t) t$`function`$name, ""), c("read", "r"))
})

test_that("OpenRouter reasoning_details replay verbatim to the same model only (INFRA-07)", {
  model = test_model(api, provider = "openrouter", id = "openai/gpt-6-sol")
  details = '[{"type":"reasoning.encrypted","data":"enc+/1=","id":"rs_1","index":0}]'
  asst = msg_assistant(list(block_thinking("Plan.", signature = "reasoning"), block_text("Done."),
                            block_opaque("openrouter", api, model$id, details)),
                       api = api, provider = "openrouter", model = model$id, timestamp = 2)
  msgs = list(msg_user("x", timestamp = 1), asst, msg_user("again", timestamp = 3))
  body = completions_build(model, ctx_fixture(msgs), list())$body
  expect_true(grepl(paste0('"reasoning_details":', details), body, fixed = TRUE))
  expect_identical(json_decode(body)$messages[[3L]]$reasoning, "Plan.")
  other = test_model(api, provider = "openrouter", id = "anthropic/claude-sonnet-5-5")
  body = completions_build(other, ctx_fixture(msgs), list())$body
  expect_false(grepl("enc+/1=", body, fixed = TRUE))
  expect_false(grepl("Plan.", body, fixed = TRUE))
})
