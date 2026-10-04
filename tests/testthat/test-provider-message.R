# Content blocks, messages and the JSON mapping (Task 13; contract sections 4.1-4.3, 4.8).

all_blocks = function() {
  list(
    block_text("plain", signature = "sig-1"),
    block_thinking("hmm", signature = "tsig", redacted = TRUE, data = "RVhB",
                   origin = list(api = "anthropic-messages", provider = "anthropic", model = "m")),
    block_image(as.raw(1:10), source = "plot", width = 768, height = 512),
    block_tool_call("call_1|fc_2", "r", list(code = "1 + 1", note = "n"), raw_arguments = "{}",
                    thought_signature = "ts"),
    block_opaque("openai", "openai-responses", "gpt-x", "{\"type\":\"reasoning\"}"),
    block_context("workspace", "d: data.frame 32 x 11",
                  attrs = list(env = "globalenv", objects = "1"), anchor = TRUE)
  )
}

usage_record = function(estimated = FALSE) {
  list(
    input = 10, output = 5, cache_read = 2, cache_write_5m = 3, cache_write_1h = 4,
    reasoning = 1, images = 0, total = 24,
    cost = list(input = 0.1, output = 0.2, cache_read = 0, cache_write = 0.3, total = 0.6),
    estimated = estimated
  )
}

test_that("block constructors produce the documented fields", {
  expect_identical(names(block_text("a")), c("type", "text", "signature"))
  img = block_image(as.raw(1:100))
  expect_false(grepl("\n", img$data, fixed = TRUE))
  expect_identical(img$mime, "image/png")
  expect_identical(block_tool_call("c1", "r", list())$arguments, json_obj())
  expect_error(block_image("x", source = "camera"), class = "gptr_error_invalid_argument")
})

test_that("block_context() renders tags with escaped attributes in the given order", {
  b = block_context("attached", "32 rows", attrs = list(name = "say \"hi\"", n = 2))
  expect_identical(
    b$text, "<attached name=\"say &quot;hi&quot;\" n=\"2\">\n32 rows\n</attached>"
  )
  expect_identical(block_context("mode", "manual")$text, "<mode>\nmanual\n</mode>")
})

test_that("message constructors fill defaults and wrap text content", {
  u = msg_user("hello", source = "pipe", timestamp = 1)
  expect_identical(
    u, list(role = "user", content = list(block_text("hello")), source = "pipe", timestamp = 1)
  )
  a = msg_assistant("done", api = "fake", provider = "fake", model = "fake-1")
  expect_identical(a$stop_reason, "stop")
  expect_identical(a$route, "api")
  expect_true(is.numeric(a$timestamp))
  r = msg_tool_result("c1", "r", "ok", details = list(status = "ok"))
  expect_false(r$is_error)
  o = msg_operator("steer_relay", "The user sent this message while you were working: stop",
                   origin_text = "stop")
  expect_identical(o$content[[1]]$type, "text")
  expect_error(msg_user("x", source = "email"), class = "gptr_error_invalid_argument")
  expect_error(msg_assistant("x", "a", "p", "m", stop_reason = "max_tokens"),
               class = "gptr_error_invalid_argument")
})

test_that("msg_text() joins text blocks and skips context and other blocks", {
  m = msg_user(list(block_context("mode", "manual"), block_text("first"), block_text("second")))
  expect_identical(msg_text(m), "first\nsecond")
  expect_identical(msg_text(msg_user(list(block_image(as.raw(1))))), "")
})

test_that("msg_validate() accepts constructor output and names the broken field", {
  expect_invisible(msg_validate(msg_user("x")))
  blocks = all_blocks()[c(1, 2, 4, 5)]
  expect_invisible(msg_validate(msg_assistant(blocks, "fake", "fake", "fake-1")))
  bad = msg_user("x")
  bad$content[[1]]$text = NULL
  cnd = tryCatch(msg_validate(bad), error = identity)
  expect_s3_class(cnd, "gptr_error_internal")
  expect_match(cnd$detail, "content[[1]]$text", fixed = TRUE)
  wrong = msg_tool_result("c1", "r", list(block_opaque("p", "a", "m", "{}")))
  expect_error(msg_validate(wrong), class = "gptr_error_internal")
})

test_that("JSON shapes use Pi names, gptr objects and omit NULL fields (section 4.8)", {
  a = msg_assistant(list(block_tool_call("c1", "r", list(code = "x"))), "anthropic-messages",
                    "anthropic", "claude-x", usage = usage_record(), stop_reason = "tool_use",
                    request_id = "q123", timestamp = 5)
  j = msg_to_json(a)
  expect_identical(j$stopReason, "toolUse")
  expect_identical(j$gptr, list(route = "api", requestId = "q123"))
  expect_identical(j$usage$cacheWrite, 7)
  expect_identical(j$usage$cacheWrite1h, 4)
  expect_false("errorMessage" %in% names(j))
  expect_identical(j$content[[1]]$type, "toolCall")
  expect_identical(
    json_encode(msg_to_json(msg_user("hi", timestamp = 7))),
    paste0(
      "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],",
      "\"timestamp\":7,\"gptr\":{\"source\":\"prompt\"}}"
    )
  )
  tr = msg_to_json(msg_tool_result("c1", "r", "ok", is_error = TRUE, timestamp = 1))
  expect_identical(tr$role, "toolResult")
  expect_true(tr$isError)
  expect_identical(msg_to_json(msg_operator("mode", "Mode is now auto."))$customType,
                   "gptr.operator")
  ctx = msg_to_json(msg_user(list(block_context("mode", "manual"))))$content[[1]]
  expect_identical(ctx$type, "text")
  expect_identical(ctx$gptr$context, "mode")
  expect_identical(json_encode(ctx$gptr$attrs), "{}")
})

test_that("every block type and role survives a JSON round trip", {
  blocks = all_blocks()
  messages = list(
    msg_user(blocks[c(1, 3, 6)], source = "steer", timestamp = 1759200000123),
    msg_assistant(blocks[c(1, 2, 4, 5)], "anthropic-messages", "anthropic", "claude-x",
                  usage = usage_record(estimated = TRUE), stop_reason = "tool_use",
                  response_id = "msg_1", thinking_level = "high", request_id = "q1",
                  timestamp = 2),
    msg_tool_result("call_1|fc_2", "r", blocks[c(1, 3)], is_error = TRUE,
                    details = list(status = "error", n_done = 1L), timestamp = 3),
    msg_operator("tool_change", "Tools changed.",
                 tool_add = list(list(name = "edit", description = "Edit a file",
                                      input_schema = list(type = "object"))),
                 timestamp = 4)
  )
  for (msg in messages) {
    back = msg_from_json(json_decode(json_encode(msg_to_json(msg))))
    expect_equal(back, msg, label = msg$role)
  }
})

test_that("unknown JSON fields are kept under `extra` and written back", {
  x = json_decode("{\"role\":\"user\",\"content\":\"hi\",\"timestamp\":1,\"piOnly\":{\"k\":1}}")
  msg = msg_from_json(x)
  expect_identical(msg$extra, list(piOnly = list(k = 1L)))
  expect_identical(msg$content[[1]]$text, "hi")
  expect_identical(msg_to_json(msg)$piOnly, list(k = 1L))
})

test_that("json_rename() applies the section 4.8 table in both directions", {
  entry = list(type = "compaction", id = "a1b2c3d4", parent_id = "0f0f0f0f",
               first_kept_entry_id = "9e9e9e9e", tokens_before = 1200, summary = "s")
  j = json_rename(entry)
  expect_identical(
    names(j), c("type", "id", "parentId", "firstKeptEntryId", "tokensBefore", "summary")
  )
  expect_identical(json_rename(j, to = "r"), entry)
  expect_identical(json_rename(list(1, 2)), list(1, 2))
})

test_that("unknown usage survives JSON round trips rather than becoming zero (IC-74)", {
  usage = usage_record()
  usage$input = NA_real_
  usage$output = NA_real_
  usage$total = NA_real_
  usage$cost$input = NA_real_
  usage$cost$output = NA_real_
  usage$cost$total = NA_real_
  encoded = json_encode(usage_to_json(usage))
  decoded = json_decode(encoded)
  expect_null(decoded$input)
  expect_null(decoded$output)
  expect_null(decoded$totalTokens)
  expect_null(decoded$cost$total)
  expect_no_warning({
    back = usage_from_json(decoded)
  })
  expect_equal(back, usage)
  legacy = usage_from_json(list(input = 12, output = 1, cacheWrite = 3))
  expect_identical(legacy$cache_write_5m, 3)
  expect_identical(legacy$cache_write_1h, 0)
})
