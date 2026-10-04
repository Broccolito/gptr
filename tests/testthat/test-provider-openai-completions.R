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

test_that("completions fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, completions_normaliser)
})

test_that("completions events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("tools", "think_tags", "error_chunk")) {
    expect_chunk_invariant(api, completions_normaliser, case)
  }
})

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
