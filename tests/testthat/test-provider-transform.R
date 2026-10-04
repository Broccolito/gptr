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

tx_entry = function(id, parent, message) {
  list(type = "message", id = id, parent_id = parent, timestamp = "2026-09-30T10:00:00.000Z",
       message = message)
}

target_sonnet = function() tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages")

test_that("a recorded 401 and an abort are projected out; every call has one result (INFRA-04)", {
  entries = list(
    tx_entry("e1", NULL, msg_user("hello", timestamp = 1000)),
    tx_entry("e2", "e1", anthropic_msg(list(), "error", 1100, error = "401 invalid x-api-key")),
    tx_entry("e3", "e2", msg_user("again", timestamp = 1200)),
    tx_entry("e4", "e3", anthropic_msg(list(block_tool_call("toolu_a", "r", list(code = "1")),
                                            block_tool_call("toolu_b", "r", list(code = "2"))),
                                       "tool_use", 2000)),
    tx_entry("e5", "e4", msg_tool_result("toolu_a", "r", "1", timestamp = 2100)),
    tx_entry("e6", "e5", anthropic_msg(list(block_text("partial")), "aborted", 4300)),
    tx_entry("e7", "e6", msg_user("continue", timestamp = 5000))
  )
  before = entries
  out = project_messages(entries, "e7", target_sonnet())
  expect_identical(entries, before)
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "user", "assistant", "tool_result", "tool_result", "user"))
  assistant = Filter(function(x) identical(x$role, "assistant"), out)
  expect_false(any(vapply(assistant, function(x) x$stop_reason %in% c("error", "aborted"), NA)))
  expect_false(any(grepl("401|partial", vapply(out, msg_text, ""))))
  results = vapply(Filter(function(x) identical(x$role, "tool_result"), out),
                   function(x) x$tool_call_id, "")
  expect_equal(sort(results), c("toolu_a", "toolu_b"))
  synthetic = out[[5]]
  expect_true(synthetic$is_error)
  expect_equal(synthetic$content[[1]]$text,
               "interrupted after 2.3 s; side effects may have occurred")
})

test_that("a call left open by a new user turn gets 'No result provided'", {
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list())), ts = 2)),
    tx_entry("e3", "e2", msg_user("never mind", timestamp = 3)),
    tx_entry("e4", "e3", msg_tool_result("c1", "r", "late result", timestamp = 4))
  )
  out = project_messages(entries, "e4", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""), c("user", "assistant", "tool_result", "user"))
  expect_equal(out[[3]]$content[[1]]$text, "No result provided")
  expect_true(out[[3]]$is_error)
})

test_that("operator relays wait until the tool results are complete", {
  relay = list(type = "custom_message", id = "e4", parent_id = "e3",
               timestamp = "2026-09-30T10:00:00.004Z", custom_type = "gptr.operator",
               content = list(block_text(
                 "The user sent this message while you were working: use TPM"
               )),
               display = FALSE, details = list(kind = "steer_relay", origin_text = "use TPM"))
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list()),
                                            block_tool_call("c2", "r", list())), ts = 2)),
    tx_entry("e3", "e2", msg_tool_result("c1", "r", "one", timestamp = 3)),
    relay,
    tx_entry("e5", "e4", msg_tool_result("c2", "r", "two", timestamp = 5))
  )
  out = project_messages(entries, "e5", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "assistant", "tool_result", "tool_result", "operator"))
  expect_equal(out[[5]]$kind, "steer_relay")
  expect_match(msg_text(out[[5]]), "use TPM", fixed = TRUE)
})

test_that("operator entries in the session kernel's shape (a `message` field) are projected", {
  op = msg_operator("steer_relay", "The user sent this message while you were working: use TPM",
                    origin_text = "use TPM", timestamp = 4)
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list())), ts = 2)),
    list(type = "custom_message", id = "e3", parent_id = "e2",
         timestamp = "2026-09-30T10:00:00.003Z", message = op),
    tx_entry("e4", "e3", msg_tool_result("c1", "r", "one", timestamp = 5)),
    list(type = "custom_message", id = "e5", parent_id = "e4",
         timestamp = "2026-09-30T10:00:00.006Z",
         message = msg_operator("mode", "Mode is now auto.", timestamp = 6)),
    list(type = "custom_message", id = "e6", parent_id = "e5",
         timestamp = "2026-09-30T10:00:00.007Z",
         raw = list(customType = "pi.note", content = list(), display = TRUE))
  )
  out = project_messages(entries, "e6", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "assistant", "tool_result", "operator", "operator"))
  expect_identical(out[[4]], op)
  expect_equal(out[[5]]$kind, "mode")
})

test_that("the newest compaction replaces everything before its first kept entry", {
  checkpoint = block_context("checkpoint", "Summary: fitted lm.", attrs = list(n = "1"))
  entries = list(
    tx_entry("e1", NULL, msg_user("old question", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_text("old answer")), "stop", 2)),
    tx_entry("e3", "e2", msg_user("kept question", timestamp = 3)),
    tx_entry("e4", "e3", anthropic_msg(list(block_text("kept answer")), "stop", 4)),
    list(type = "compaction", id = "e5", parent_id = "e4", timestamp = "2026-09-30T10:00:05.000Z",
         summary = "fitted lm", first_kept_entry_id = "e3", tokens_before = 1234,
         gptr = list(blocks = list(checkpoint), n = 1L)),
    tx_entry("e6", "e5", msg_user("new question", timestamp = 6))
  )
  out = project_messages(entries, "e6", target_sonnet())
  expect_equal(length(out), 4L)
  expect_equal(out[[1]]$content[[1]]$type, "context")
  expect_match(out[[1]]$content[[1]]$text, "Summary: fitted lm.", fixed = TRUE)
  expect_equal(vapply(out[-1], msg_text, ""), c("kept question", "kept answer", "new question"))
  bare = entries
  bare[[5]]$gptr = NULL
  out2 = project_messages(bare, "e6", target_sonnet())
  expect_match(out2[[1]]$content[[1]]$text, "fitted lm", fixed = TRUE)
})

test_that("the path follows parent ids, tolerates a missing parent and rejects an unknown leaf", {
  entries = list(
    tx_entry("e1", NULL, msg_user("root", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_text("branch a")), "stop", 2)),
    tx_entry("e3", "e1", anthropic_msg(list(block_text("branch b")), "stop", 3)),
    tx_entry("e4", "gone", msg_user("after a torn line", timestamp = 4))
  )
  expect_equal(vapply(project_messages(entries, "e2", target_sonnet()), msg_text, ""),
               c("root", "branch a"))
  expect_equal(vapply(project_messages(entries, "e3", target_sonnet()), msg_text, ""),
               c("root", "branch b"))
  expect_equal(vapply(project_messages(entries, "e4", target_sonnet()), msg_text, ""),
               c("root", "branch b", "after a torn line"))
  expect_equal(project_messages(entries, NULL, target_sonnet()), list())
  expect_error(project_messages(entries, "nope", target_sonnet()), class = "gptr_error_internal")
})

test_that("partial results and held relays survive abort and error closure deterministically", {
  calls = anthropic_msg(list(block_tool_call("a", "r", list()),
                            block_tool_call("b", "r", list())), ts = 1000)
  first = msg_tool_result("a", "r", "real", timestamp = 1100)
  relay1 = msg_operator("steer_relay", "first relay", timestamp = 1200)
  relay2 = msg_operator("steer_relay", "second relay", timestamp = 1300)
  for (stop in c("aborted", "error")) {
    terminal = anthropic_msg(list(block_text("discard")), stop, 3300)
    messages = list(calls, first, relay1, relay2, terminal,
                    msg_tool_result("b", "r", "late", timestamp = 4000))
    before = messages
    out = project_structure(messages)
    expect_equal(vapply(out, function(m) m$role, ""),
                 c("assistant", "tool_result", "tool_result", "operator", "operator"))
    expect_identical(out[[2]], first)
    expect_identical(out[[3]]$tool_call_id, "b")
    expect_identical(out[[3]]$timestamp, calls$timestamp)
    expect_true(out[[3]]$is_error)
    text = if (stop == "aborted") {
      "interrupted after 2.3 s; side effects may have occurred"
    } else {
      "No result provided"
    }
    expect_identical(msg_text(out[[3]]), text)
    expect_identical(out[4:5], list(relay1, relay2))
    expect_identical(project_structure(messages), out)
    expect_identical(messages, before)
  }
})

test_that("duplicate and unknown results are dropped while reused later ids are independent", {
  call = function(ts) anthropic_msg(list(block_tool_call("same", "r", list())), ts = ts)
  result = function(text, ts, id = "same") msg_tool_result(id, "r", text, timestamp = ts)
  messages = list(call(1), result("first", 2), result("duplicate", 3),
                  result("unknown", 4, "other"), msg_user("next", timestamp = 5),
                  call(6), result("second", 7), result("another duplicate", 8))
  out = project_structure(messages)
  results = Filter(function(m) m$role == "tool_result", out)
  expect_equal(vapply(results, msg_text, ""), c("first", "second"))
  expect_identical(vapply(results, function(m) m$timestamp, 0), c(2, 7))
  expect_identical(project_structure(messages), out)
})

test_that("held relays are FIFO at EOF and after a completed result group", {
  call = anthropic_msg(list(block_tool_call("a", "r", list())), ts = 1)
  relay1 = msg_operator("steer_relay", "one", timestamp = 2)
  relay2 = msg_operator("steer_relay", "two", timestamp = 4)
  done = msg_tool_result("a", "r", "done", timestamp = 3)
  pending = project_structure(list(call, relay1, relay2))
  expect_equal(vapply(pending, function(m) m$role, ""),
               c("assistant", "tool_result", "operator", "operator"))
  expect_identical(pending[3:4], list(relay1, relay2))
  finished = project_structure(list(call, relay1, done, relay2))
  expect_identical(finished, list(call, done, relay1, relay2))
  note = msg_user("extension note", source = "extension", timestamp = 5)
  expect_identical(project_structure(list(note)), list(note))
})

test_that("only ancestry compactions apply and earlier summaries are not resurrected", {
  first = list(type = "compaction", id = "c1", parent_id = "e2", timestamp = 3,
               summary = "OLD SUMMARY", first_kept_entry_id = "e1")
  checkpoint = block_context("checkpoint", "CURRENT SUMMARY",
                              attrs = list(custom = "<&>"), anchor = TRUE)
  newest = list(type = "compaction", id = "c2", parent_id = "e3", timestamp = 5,
                summary = "fallback", first_kept_entry_id = "e2",
                gptr = list(blocks = list(checkpoint)))
  entries = list(
    tx_entry("e1", NULL, msg_user("old", timestamp = 1)),
    tx_entry("e2", "e1", msg_user("kept", timestamp = 2)), first,
    tx_entry("e3", "c1", msg_user("after first", timestamp = 4)), newest,
    tx_entry("branch", "e3", msg_user("other branch", timestamp = 6)),
    tx_entry("e4", "c2", msg_user("after second", timestamp = 7))
  )
  before = entries
  out = project_messages(entries, "e4", target_sonnet())
  expect_identical(out[[1]]$content, list(checkpoint))
  expect_equal(vapply(out[-1], msg_text, ""), c("kept", "after first", "after second"))
  expect_false(grepl("OLD SUMMARY|other branch", json_encode(lapply(out, msg_to_json))))
  branch = project_messages(entries, "branch", target_sonnet())
  expect_match(branch[[1]]$content[[1]]$text, "OLD SUMMARY", fixed = TRUE)
  expect_false(grepl("CURRENT SUMMARY|after second", json_encode(lapply(branch, msg_to_json))))
  expect_identical(project_messages(entries, "e4", target_sonnet()), out)
  expect_identical(entries, before)
})

test_that("a compaction with no kept range removes earlier calls and orphaned results", {
  compaction = list(type = "compaction", id = "c", parent_id = "e1", timestamp = 2,
                    summary = "summary", first_kept_entry_id = NULL)
  entries = list(
    tx_entry("e1", NULL, anthropic_msg(list(block_tool_call("a", "r", list())), ts = 1)),
    compaction, tx_entry("e2", "c", msg_tool_result("a", "r", "old result", timestamp = 3))
  )
  out = project_messages(entries, "e2", target_sonnet())
  expect_length(out, 1L)
  expect_identical(out[[1]]$role, "user")
  expect_match(out[[1]]$content[[1]]$text, "summary", fixed = TRUE)
  expect_identical(project_messages(entries, "e2", target_sonnet()), out)
})

test_that("a non-null unknown leaf is an error even for an empty transcript", {
  expect_error(project_messages(list(), "missing", target_sonnet()),
               class = "gptr_error_internal")
  expect_identical(project_messages(list(), NULL, target_sonnet()), list())
})

test_that("unparsable entry timestamps consistently fall back to zero", {
  for (value in list(NA_real_, NA_integer_, NaN, Inf, -Inf, 1 + 1i, "bad timestamp")) {
    expect_identical(entry_ms(value), 0)
  }
  expect_identical(entry_ms(1250), 1250)
  expect_identical(entry_ms("1970-01-01T00:00:01.250Z"), 1250)
  entry = list(type = "compaction", id = "c", parent_id = NULL, timestamp = Inf,
               summary = "summary", first_kept_entry_id = NULL)
  out = project_messages(list(entry), "c", target_sonnet())
  expect_identical(out[[1]]$timestamp, 0)
})
