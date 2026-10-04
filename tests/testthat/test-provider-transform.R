# Tests for R/provider-transform.R (plan P05): the hand-off transform (INFRA-08) and the
# projection of the transcript tree (INFRA-04).

tx_model = function(provider, id, api, input = c("text", "image")) {
  list(ref = paste0(provider, "/", id), provider = provider, id = id, api = api,
       input = input, reasoning = TRUE, capabilities = list())
}

anthropic_msg = function(content, stop = "tool_use", ts = 1000, model = "claude-sonnet-5-5",
                         error = NULL) {
  msg_assistant(content, api = "anthropic-messages", provider = "anthropic", model = model,
                stop_reason = stop, error_message = error, timestamp = ts)
}

block_types = function(msg) vapply(msg$content, function(b) b$type, "")

test_that("hand-off keeps a same-model turn byte for byte", {
  a = anthropic_msg(list(block_thinking("plan the fit", signature = "sig-abc"),
                         block_thinking("", redacted = TRUE, data = "opaque-redacted"),
                         block_text("Fitting now.", signature = "txt-sig"),
                         block_opaque("anthropic", "anthropic-messages", "claude-sonnet-5-5",
                                      "{\"server\":1}"),
                         block_tool_call("toolu_01", "r", list(code = "fit = lm(y ~ x)"))))
  same = handoff_transform(list(a), tx_model("anthropic", "claude-sonnet-5-5",
                                             "anthropic-messages"))
  expect_identical(same[[1]]$content, a$content)
})

test_that("hand-off to other providers drops every foreign signature and opaque item (INFRA-08)", {
  a = anthropic_msg(list(block_thinking("plan the fit", signature = "sig-abc"),
                         block_thinking("", redacted = TRUE, data = "opaque-redacted"),
                         block_text("Fitting now.", signature = "txt-sig"),
                         block_opaque("anthropic", "anthropic-messages", "claude-sonnet-5-5",
                                      "{\"server\":1}"),
                         block_tool_call("toolu_01", "r", list(code = "fit = lm(y ~ x)"),
                                         thought_signature = "ts-1")))
  msgs = list(msg_user("Fit a model", timestamp = 900), a,
              msg_tool_result("toolu_01", "r", "done", timestamp = 1100))
  targets = list(tx_model("openai", "gpt-6.1-sol", "openai-responses"),
                 tx_model("google", "gemini-3.8-flash", "google-generative-ai"))
  for (target in targets) {
    out = handoff_transform(msgs, target)
    blocks = out[[2]]$content
    expect_equal(block_types(out[[2]]), c("text", "text", "tool_call"))
    expect_equal(blocks[[1]]$text, "plan the fit")
    expect_true(all(vapply(blocks, function(b) is.null(b$signature), NA)))
    expect_null(blocks[[3]]$thought_signature)
    expect_false(any(grepl("sig-abc|txt-sig|opaque-redacted|ts-1|server",
                           json_encode(lapply(out, msg_to_json)))))
    expect_identical(out[[3]]$tool_call_id, blocks[[3]]$id)
  }
  expect_length(msgs, 3L)
  expect_equal(msgs[[2]]$content[[1]]$signature, "sig-abc")
})

test_that("tool ids are normalised per target api and results follow them", {
  src = msg_assistant(list(block_tool_call("call_1|fc_ab+/=", "r", list(code = "1"))),
                      api = "openai-responses", provider = "openai", model = "gpt-6.1-sol",
                      stop_reason = "tool_use", timestamp = 1)
  res = msg_tool_result("call_1|fc_ab+/=", "r", "1", timestamp = 2)
  to_anthropic = handoff_transform(list(src, res),
                                   tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages"))
  expect_equal(to_anthropic[[1]]$content[[1]]$id, "call_1_fc_ab___")
  expect_equal(to_anthropic[[2]]$tool_call_id, "call_1_fc_ab___")
  to_mistral = handoff_transform(list(src, res),
                                 tx_model("mistral", "mistral-large", "openai-completions"))
  expect_match(to_mistral[[1]]$content[[1]]$id, "^[0-9a-zA-Z]{9}$")
  expect_identical(to_mistral[[2]]$tool_call_id, to_mistral[[1]]$content[[1]]$id)
  long = paste0("call_", strrep("x", 30), "|fc_", strrep("y", 30))
  expect_match(id_completions(long, "groq"), "^call_x+_[0-9a-f]{8}$")
  expect_lte(nchar(id_completions(long, "groq")), 40L)
  expect_equal(id_completions("call_a|fc_b", "groq"), "call_a_fc_b")
  expect_equal(id_completions(strrep("z", 50), "openai"), strrep("z", 40))
  responses = tx_model("openai", "gpt-6.1-sol", "openai-responses")
  foreign = list(provider = "anthropic", api = "anthropic-messages")
  expect_equal(id_responses("call_9|rs_77", responses, foreign),
               paste0("call_9|fc_", substr(hash_sha256("rs_77"), 1, 12)))
  expect_equal(id_responses("call_9|fc_77", responses, list(provider = "openai",
                                                            api = "openai-responses")),
               "call_9|fc_77")
  norm = id_alnum9_normaliser()
  expect_identical(norm("toolu_01ABC", NULL), norm("toolu_01ABC", NULL))
  expect_equal(norm("abcdefghi", NULL), "abcdefghi")
})

test_that("images become one placeholder for a target that reads no images", {
  u = msg_user(list(block_text("look"), block_image("AAAA"), block_image("BBBB")), timestamp = 1)
  r = msg_tool_result("c1", "r", list(block_image("CCCC")), timestamp = 2)
  target = tx_model("deepseek", "deepseek-v4-pro", "openai-completions", input = "text")
  out = handoff_transform(list(u, r), target)
  expect_equal(vapply(out[[1]]$content, function(b) b$text, ""),
               c("look", "(image omitted: model does not support images)"))
  expect_equal(out[[2]]$content[[1]]$text,
               "(tool image omitted: model does not support images)")
})

test_that("foreign thinking becomes text unless the target refuses reasoning replay", {
  a = anthropic_msg(list(block_thinking("why"), block_thinking("  "), block_text("answer")),
                    stop = "stop", model = "claude-opus-5-5")
  target = tx_model("openai", "gpt-6.1-sol", "openai-responses")
  expect_equal(vapply(handoff_transform(list(a), target)[[1]]$content, function(b) b$text, ""),
               c("why", "answer"))
  target$capabilities = list(reasoning_replay = FALSE)
  expect_equal(vapply(handoff_transform(list(a), target)[[1]]$content, function(b) b$text, ""),
               "answer")
  # the capability usually comes from the target api's adapter (04 section 8.1)
  off = gptr_register(gptr_adapter("test-noreplay", transport = "inprocess",
                                   stream = function(model, context, opts) function() NULL,
                                   capabilities = list(reasoning_replay = FALSE)))
  withr::defer(off())
  lab = tx_model("lab", "lab-1", "test-noreplay")
  expect_equal(vapply(handoff_transform(list(a), lab)[[1]]$content, function(b) b$text, ""),
               "answer")
})

test_that("foreign-origin reasoning honors target replay even inside a same-model turn", {
  target = tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages")
  target$capabilities$reasoning_replay = FALSE
  foreign = block_thinking("foreign reasoning", signature = "foreign-secret",
                          origin = list(provider = "other", api = "other", model = "other"))
  own = block_thinking("own reasoning", signature = "own-signature")
  message = anthropic_msg(list(foreign, own, block_thinking("  "), block_text("answer")))
  before = message
  out = handoff_transform(list(message), target)
  expect_identical(message, before)
  expect_identical(out[[1]]$content, list(own, block_text("answer")))
  expect_false(grepl("foreign", json_encode(lapply(out, msg_to_json)), fixed = TRUE))
})

test_that("tool result remapping belongs to the current assistant turn", {
  target = tx_model("openai", "gpt-6.1-sol", "openai-responses")
  raw_id = "call_1|fc_2"
  foreign = anthropic_msg(list(block_tool_call(raw_id, "r", list())))
  same = msg_assistant(list(block_tool_call(raw_id, "r", list())),
                       provider = target$provider, api = target$api, model = target$id,
                       stop_reason = "tool_use", timestamp = 3)
  messages = list(foreign, msg_tool_result(raw_id, "r", "first", timestamp = 2),
                  same, msg_tool_result(raw_id, "r", "second", timestamp = 4))
  out = handoff_transform(messages, target)
  expect_false(identical(out[[1]]$content[[1]]$id, raw_id))
  expect_identical(out[[2]]$tool_call_id, out[[1]]$content[[1]]$id)
  expect_identical(out[[3]], same)
  expect_identical(out[[4]]$tool_call_id, raw_id)
})

test_that("foreign tool id normalization keeps colliding calls distinct and stable", {
  target = tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages")
  ids = c("call/a", "call?a", "call_a")
  calls = lapply(ids, function(id) block_tool_call(id, "r", list()))
  message = msg_assistant(calls, provider = "other", api = "other", model = "other",
                         stop_reason = "tool_use", timestamp = 1)
  messages = c(list(message), lapply(ids, function(id) {
    msg_tool_result(id, "r", id, timestamp = 2)
  }))
  before = messages
  out = handoff_transform(messages, target)
  normalized = vapply(out[[1]]$content, function(b) b$id, "")
  expect_length(unique(normalized), length(ids))
  expect_true(all(grepl("^[A-Za-z0-9_-]{1,64}$", normalized)))
  expect_identical(vapply(out[-1], function(m) m$tool_call_id, ""), normalized)
  expect_identical(handoff_transform(messages, target), out)
  expect_identical(messages, before)
})

test_that("foreign ids reserve native same-model ids without changing native messages", {
  target = tx_model("mistral", "mistral-large", "openai-completions")
  own = msg_assistant(list(block_tool_call("abcdefghi", "r", list())),
                     provider = target$provider, api = target$api, model = target$id,
                     stop_reason = "tool_use", timestamp = 1)
  foreign = anthropic_msg(list(block_tool_call("abc-defghi", "r", list())), ts = 3)
  native_pair = list(own, msg_tool_result("abcdefghi", "r", "own", timestamp = 2))
  foreign_pair = list(foreign, msg_tool_result("abc-defghi", "r", "foreign", timestamp = 4))
  for (native_first in c(TRUE, FALSE)) {
    messages = if (native_first) c(native_pair, foreign_pair) else c(foreign_pair, native_pair)
    native_at = if (native_first) 1L else 3L
    foreign_at = if (native_first) 3L else 1L
    out = handoff_transform(messages, target)
    expect_identical(out[native_at:(native_at + 1L)], native_pair)
    id = out[[foreign_at]]$content[[1]]$id
    expect_match(id, "^[A-Za-z0-9]{9}$")
    expect_false(identical(id, "abcdefghi"))
    expect_identical(out[[foreign_at + 1L]]$tool_call_id, id)
    expect_identical(handoff_transform(messages, target), out)
  }
})

test_that("explicit model replay capability overrides the adapter in either direction", {
  off = gptr_register(gptr_adapter("test-replay-precedence", transport = "inprocess",
                                  stream = function(model, context, opts) function() NULL,
                                  capabilities = list(reasoning_replay = FALSE)))
  withr::defer(off())
  target = tx_model("lab", "lab-1", "test-replay-precedence")
  messages = list(anthropic_msg(list(block_thinking("reason"), block_text("answer"))))
  target$capabilities$reasoning_replay = TRUE
  expect_equal(vapply(handoff_transform(messages, target)[[1]]$content, function(b) b$text, ""),
               c("reason", "answer"))
  target$capabilities$reasoning_replay = FALSE
  expect_equal(vapply(handoff_transform(messages, target)[[1]]$content, function(b) b$text, ""),
               "answer")
})


test_that("a target can refuse replay allowed by its adapter", {
  off = gptr_register(gptr_adapter("test-replay-allow", transport = "inprocess",
                                  stream = function(model, context, opts) function() NULL,
                                  capabilities = list(reasoning_replay = TRUE)))
  withr::defer(off())
  target = tx_model("lab", "lab-1", "test-replay-allow")
  target$capabilities$reasoning_replay = FALSE
  messages = list(anthropic_msg(list(block_thinking("reason"), block_text("answer"))))
  expect_equal(vapply(handoff_transform(messages, target)[[1]]$content, function(b) b$text, ""),
               "answer")
})
