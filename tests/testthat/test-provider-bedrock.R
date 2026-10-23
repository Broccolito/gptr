# Tests for R/provider-bedrock.R (plan P26 Task 11, IC-80): SigV4 signing, the AWS event-stream
# decoder, the ConverseStream normaliser, the Converse request body, signing per attempt in
# http_handle(), the agent loop through a scripted wire and the redaction of the key pair.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "bedrock-converse"

# AWS's published SigV4 test-suite credentials (aws-sig-v4-test-suite, 2015-08-30)
aws_key_id = "AKIDEXAMPLE"
aws_secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
aws_token = "FQoGZXIvYXdzEXAMPLEsessionTOKEN0123456789abcdefABCDEF"

# ---- the constructed ConverseStream fixture (AWS event-stream framing) -------------------------

# A big-endian uint32
be_u32 = function(x) as.raw(c(x %/% 16777216, x %/% 65536 %% 256, x %/% 256 %% 256, x %% 256))

# One frame: prelude (total and header lengths, prelude CRC), string headers, payload, CRC
es_frame = function(headers, payload) {
  hb = raw()
  for (k in names(headers)) {
    v = charToRaw(headers[[k]])
    hb = c(hb, as.raw(nchar(k)), charToRaw(k), as.raw(7L),
           as.raw(c(length(v) %/% 256, length(v) %% 256)), v)
  }
  p = charToRaw(payload)
  prelude = c(be_u32(16 + length(hb) + length(p)), be_u32(length(hb)))
  msg = c(prelude, be_u32(bedrock_crc32(prelude)), hb, p)
  c(msg, be_u32(bedrock_crc32(msg)))
}

es_event = function(type, payload) {
  es_frame(list(`:event-type` = type, `:content-type` = "application/json",
                `:message-type` = "event"), payload)
}

es_exception = function(type, message) {
  es_frame(list(`:exception-type` = type, `:content-type` = "application/json",
                `:message-type` = "exception"), json_encode(list(message = message)))
}

# A ConverseStream reply: text, then one toolUse whose input arrives in pieces (stop tool_use)
converse_tool = function(text = "Counting.", id = "tooluse_01", name = "r",
                         input = c("{\"code\":", "\"1 + 1\"}")) {
  deltas = lapply(input, function(x) {
    es_event("contentBlockDelta", paste0('{"contentBlockIndex":1,"delta":{"toolUse":{"input":',
                                         json_encode(x), '}},"p":"abc"}'))
  })
  c(es_event("messageStart", '{"role":"assistant","p":"abcdefgh"}'),
    es_event("contentBlockDelta", paste0('{"contentBlockIndex":0,"delta":{"text":',
                                         json_encode(text), '},"p":"ab"}')),
    es_event("contentBlockStop", '{"contentBlockIndex":0,"p":"abcd"}'),
    es_event("contentBlockStart", paste0('{"contentBlockIndex":1,"start":{"toolUse":',
                                         '{"toolUseId":"', id, '","name":"', name, '"}}}')),
    do.call(c, deltas),
    es_event("contentBlockStop", '{"contentBlockIndex":1}'),
    es_event("messageStop", '{"stopReason":"tool_use","p":"abcdef"}'),
    es_event("metadata", paste0('{"usage":{"inputTokens":20,"outputTokens":5,"totalTokens":25},',
                                '"metrics":{"latencyMs":120},"p":"ab"}')))
}

# A ConverseStream text reply (stop end_turn); `metadata = FALSE` leaves the usage out
converse_text = function(text, metadata = TRUE) {
  c(es_event("messageStart", '{"role":"assistant"}'),
    es_event("contentBlockDelta", paste0('{"contentBlockIndex":0,"delta":{"text":',
                                         json_encode(text), "}}")),
    es_event("contentBlockStop", '{"contentBlockIndex":0}'),
    es_event("messageStop", '{"stopReason":"end_turn"}'),
    if (metadata) {
      es_event("metadata", '{"usage":{"inputTokens":30,"outputTokens":6,"totalTokens":36}}')
    })
}

# Replay bytes through the normaliser in chunks of the given sizes (the whole body by default)
bedrock_replay = function(bytes, sizes = length(bytes), retry = NULL) {
  out = new.env(parent = emptyenv())
  out$events = list()
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  emit = function(ev) out$events[[length(out$events) + 1L]] = ev
  n = bedrock_normaliser(adp_fixture_model(api), list(emit = emit, signal = signal, retry = retry))
  for (chunk in adp_split_raw(bytes, sizes)) n$push(list(data = chunk))
  list(message = n$finish(), events = out$events,
       types = vapply(out$events, function(e) e$type, ""))
}

# A SigV4 provider record for the calling test (a gateway path under the origin)
local_bedrock_provider = function(id = "versa-test",
                                  base_url = "https://bedrock.example.test/awsai",
                                  .env = parent.frame()) {
  spec = gptr_provider(id, api = api, base_url = base_url, auth = "AWS_SECRET_ACCESS_KEY",
                       compat = list(region = "us-west-2"),
                       models = list(list(id = "us.anthropic.claude-opus-4-8", tool_call = TRUE,
                                          input = c("text", "image"), max_output = 4096)))
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

# ---- HMAC-SHA256 and SigV4 ---------------------------------------------------------------------

test_that("hmac_sha256() matches RFC 4231 (test cases 2 and 6, a key longer than the block)", {
  hex = function(x) paste(as.character(x), collapse = "")
  expect_identical(hex(hmac_sha256(charToRaw("Jefe"), "what do ya want for nothing?")),
                   "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
  expect_identical(hex(hmac_sha256(as.raw(rep(0xaa, 131L)),
                                   "Test Using Larger Than Block-Size Key - Hash Key First")),
                   "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
})

test_that("sigv4() reproduces AWS's get-vanilla and post-vanilla test-suite vectors", {
  at = as.POSIXct("2015-08-30 12:36:00", tz = "UTC")
  empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  vectors = list(
    GET = list(sts_hash = "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63",
               signature = "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"),
    POST = list(sts_hash = "553f88c9e4d10fc9e109e2aeb65f030801b70c2f6468faca261d401ae622fc87",
                signature = "5da7c1a2acd57cee7505fc6676e4e544621c30862966e37dddb68e92efbe5d6b")
  )
  for (method in names(vectors)) {
    v = vectors[[method]]
    s = sigv4(method, "https://example.amazonaws.com/", list(), empty, aws_key_id, aws_secret,
              "us-east-1", "service", time = at)
    expect_identical(s$canonical, paste(method, "/", "", "host:example.amazonaws.com",
                                        "x-amz-date:20150830T123600Z", "", "host;x-amz-date",
                                        empty, sep = "\n"))
    expect_identical(hash_sha256(s$canonical), v$sts_hash)
    expect_identical(s$string_to_sign,
                     paste("AWS4-HMAC-SHA256", "20150830T123600Z",
                           "20150830/us-east-1/service/aws4_request", v$sts_hash, sep = "\n"))
    expect_identical(s$signature, v$signature)
    expect_identical(s$headers$authorization, paste0(
      "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, ",
      "SignedHeaders=host;x-amz-date, Signature=", v$signature))
    expect_identical(s$headers$`x-amz-date`, "20150830T123600Z")
  }
})

test_that("the canonical URI encodes the sent path once more and keeps a gateway prefix", {
  url = "https://gw.example.test:8443/general/awsai/model/anthropic.claude-v1%3A0/converse-stream"
  s = sigv4("POST", url, list(`x-amz-content-sha256` = "abc"), "abc", aws_key_id, aws_secret,
            "us-west-2", "bedrock")
  lines = strsplit(s$canonical, "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[[2L]], "/general/awsai/model/anthropic.claude-v1%253A0/converse-stream")
  expect_identical(lines[[4L]], "host:gw.example.test:8443")
  expect_identical(lines[[7L]], "")
  expect_identical(lines[[8L]], "host;x-amz-content-sha256;x-amz-date")
  expect_named(s$headers, c("x-amz-content-sha256", "x-amz-date", "authorization"))
})

# ---- the AWS event-stream decoder ------------------------------------------------------------

test_that("bedrock_crc32() is the IEEE CRC-32 and frames match AWS's empty-message vector", {
  expect_identical(bedrock_crc32(charToRaw("123456789")), 3421780262)
  expect_identical(bedrock_crc32(raw()), 0)
  # aws-c-event-stream encoded/positive/empty_message
  empty = as.raw(c(0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x05, 0xc2, 0x48, 0xeb, 0x7d,
                   0x98, 0xc8, 0xff))
  expect_identical(es_frame(list(), ""), empty)
  expect_identical(bedrock_decoder()(empty), list(list(headers = list(), payload = raw())))
  # aws-c-event-stream encoded/positive/payload_one_str_header
  hex = paste0("0000003d0000002007fd83960c636f6e74656e742d747970650700106170706c69636174696f6e",
               "2f6a736f6e7b27666f6f273a27626172277d8d9c08b1")
  expect_identical(bedrock_decoder()(hex_raw(hex)),
                   list(list(headers = list(`content-type` = "application/json"),
                             payload = charToRaw("{'foo':'bar'}"))))
})

test_that("the recorded ConverseStream fixtures pass check_adapter() and gptr_check()", {
  skip_on_cran()
  a = adapter_get(api)
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], res$message[!res$ok], collapse = "; "))
  expect_true(all(c("adapter.tool_use.chunk_invariance", "adapter.tool_use.roundtrip",
                    "adapter.throttled.golden_message") %in% res$check))
  expect_true(all(gptr_check(a)$ok))
  # the binary fixtures, not a build() call, make the replay raw: one that refuses still replays
  a$build = function(model, ctx, opts) stop("no key")
  res = check_adapter(a, fixtures = sse_dir(api))
  replay = grepl("\\.(no_condition|event_order|golden_events|golden_message|chunk_invariance)$",
                 res$check)
  expect_identical(sum(replay), 10L)
  expect_true(all(res$ok[replay]))
})

test_that("the decoder gives the same frames for every split of the bytes (exception included)", {
  skip_on_cran()
  bytes = c(converse_tool(), es_exception("throttlingException", "Too many requests"))
  whole = bedrock_decoder()(bytes)
  expect_length(whole, 10L)
  expect_identical(whole[[1L]]$headers[[":event-type"]], "messageStart")
  expect_identical(whole[[10L]]$headers[[":message-type"]], "exception")
  expect_identical(whole[[10L]]$headers[[":exception-type"]], "throttlingException")
  same = vapply(seq_len(length(bytes) - 1L), function(k) {
    d = bedrock_decoder()
    identical(c(d(bytes[seq_len(k)]), d(bytes[(k + 1L):length(bytes)])), whole)
  }, NA)
  expect_identical(which(!same), integer())
})

test_that("a CRC mismatch in the prelude or the message is refused", {
  bytes = converse_text("Hello")
  bad = bytes
  bad[[length(bytes) - 10L]] = xor(bad[[length(bytes) - 10L]], as.raw(1L))
  expect_error(bedrock_decoder()(bad), "message CRC mismatch")
  r = bedrock_replay(bad)
  expect_identical(r$types[[length(r$types)]], "error")
  expect_identical(r$events[[length(r$events)]]$error$class, "network")
  expect_match(r$message$error_message, "message CRC mismatch", fixed = TRUE)
  bad = bytes
  bad[[3L]] = xor(bad[[3L]], as.raw(1L))
  expect_error(bedrock_decoder()(bad), "prelude CRC mismatch")
})

# ---- the ConverseStream normaliser -------------------------------------------------------------

test_that("text and a tool call stream as events; stop reason and usage come from the stream", {
  r = bedrock_replay(converse_tool())
  expect_identical(r$types, c("start", "text_start", "text_delta", "text_end", "toolcall_start",
                              "toolcall_delta", "toolcall_delta", "toolcall_end", "done"))
  m = r$message
  expect_identical(m$stop_reason, "tool_use")
  expect_identical(m$raw_stop_reason, "tool_use")
  expect_identical(m$content[[1L]], block_text("Counting."))
  call = m$content[[2L]]
  expect_identical(c(call$id, call$name), c("tooluse_01", "r"))
  expect_identical(call$arguments, list(code = "1 + 1"))
  expect_identical(c(m$usage$input, m$usage$output, m$usage$cache_read), c(20, 5, 0))
  expect_identical(m$api, api)
  # byte by byte and pseudo-random chunkings give the same events
  whole = lapply(r$events, adp_golden_event)
  for (sz in list(1L, adp_chunk_sizes("a"), adp_chunk_sizes("b"))) {
    expect_identical(lapply(bedrock_replay(converse_tool(), sz)$events, adp_golden_event), whole)
  }
})

test_that("unreported usage stays unknown and a missing messageStop is a truncated stream", {
  m = bedrock_replay(converse_text("Hi", metadata = FALSE))$message
  expect_identical(m$stop_reason, "stop")
  expect_identical(c(m$usage$input, m$usage$output), c(NA_real_, NA_real_))
  bytes = converse_text("Hi")
  r = bedrock_replay(bytes[seq_len(length(bytes) - 40L)])
  expect_identical(r$types[[length(r$types)]], "done")
  r = bedrock_replay(converse_tool()[1:300])
  expect_identical(r$events[[length(r$events)]]$error$class, "network")
  expect_match(r$message$error_message, "ended before messageStop", fixed = TRUE)
  expect_identical(msg_text(r$message), "Counting.")
})

test_that("an exception frame is a provider error, retried only before any delta", {
  bytes = c(es_event("messageStart", '{"role":"assistant"}'),
            es_event("contentBlockDelta", '{"contentBlockIndex":0,"delta":{"text":"Hel"}}'),
            es_exception("throttlingException", "Too many requests"))
  r = bedrock_replay(bytes)
  err = r$events[[length(r$events)]]
  expect_identical(err$type, "error")
  expect_identical(c(err$error$class, as.character(err$error$status)), c("rate_limit", "429"))
  expect_identical(r$message$error_message, "throttlingException: Too many requests")
  expect_identical(msg_text(r$message), "Hel")
  asked = new.env(parent = emptyenv())
  asked$info = NULL
  r = bedrock_replay(c(es_event("messageStart", "{}"),
                       es_exception("serviceUnavailableException", "busy")),
                     retry = function(info) asked$info = info)
  expect_identical(asked$info$class, "overloaded")
  expect_identical(asked$info$status, 503L)
  expect_match(r$message$error_message, "serviceUnavailableException: busy", fixed = TRUE)
  r = bedrock_replay(c(es_event("messageStart", "{}"),
                       es_exception("validationException", "bad input")),
                     retry = function(info) stop("never retried"))
  expect_identical(r$events[[length(r$events)]]$error$status, 400L)
})

test_that("reasoning deltas are a signed thinking block; a guardrail stop is a refusal", {
  bytes = c(es_event("messageStart", "{}"),
            es_event("contentBlockDelta", paste0('{"contentBlockIndex":0,"delta":',
                                                 '{"reasoningContent":{"text":"Think."}}}')),
            es_event("contentBlockDelta", paste0('{"contentBlockIndex":0,"delta":',
                                                 '{"reasoningContent":{"signature":"sig1"}}}')),
            es_event("contentBlockStop", '{"contentBlockIndex":0}'),
            es_event("messageStop", '{"stopReason":"guardrail_intervened"}'))
  r = bedrock_replay(bytes)
  expect_identical(r$types[1:4], c("start", "thinking_start", "thinking_delta", "thinking_end"))
  b = r$message$content[[1L]]
  expect_identical(c(b$type, b$thinking, b$signature), c("thinking", "Think.", "sig1"))
  expect_identical(r$message$stop_reason, "refusal")
  expect_identical(r$message$raw_stop_reason, "guardrail_intervened")
})

# ---- the Converse request body -----------------------------------------------------------------

test_that("the body maps system, messages, tools, tool results, images and inference config", {
  model = test_model(api, reasoning = FALSE)
  turn = msg_assistant(list(block_text("Reading."),
                            block_tool_call("toolu_1|fc_2", "read", list(path = "a.R"))),
                       api = api, provider = "fixture", model = "fixture-1")
  ctx = ctx_fixture(list(first_message(), msg_user(list(block_image(png_b64()))), turn,
                         msg_tool_result("toolu_1|fc_2", "read", "x = 1"),
                         msg_tool_result("toolu_1|fc_2", "read", "no such file", is_error = TRUE)),
                    params = list(max_tokens = 512L, temperature = 0.2))
  spec = bedrock_build(model, ctx, list(base_url = "https://bedrock.example.test/v1/"))
  expect_identical(spec$url, "https://bedrock.example.test/v1/model/fixture-1/converse-stream")
  expect_identical(c(spec$method, spec$stream), c("POST", "raw"))
  expect_null(spec$sign)
  body = json_decode(spec$body)
  expect_identical(names(body), c("inferenceConfig", "system", "toolConfig", "messages"))
  expect_identical(body$inferenceConfig, list(maxTokens = 512L, temperature = 0.2))
  expect_identical(body$system, list(list(text = "T0 static sections."),
                                     list(text = "T1 catalogs.")))
  spec1 = body$toolConfig$tools[[1L]]$toolSpec
  expect_identical(c(spec1$name, spec1$description), c("read", "Read a file."))
  expect_identical(spec1$inputSchema$json$required, list("path"))
  msgs = body$messages
  expect_identical(vapply(msgs, function(m) m$role, ""), c("user", "assistant", "user"))
  user = msgs[[1L]]$content
  expect_identical(vapply(user[1:3], function(b) b$text, ""),
                   vapply(first_message()$content, function(b) b$text, ""))
  expect_identical(user[[4L]], list(image = list(format = "png", source = list(bytes = png_b64()))))
  expect_identical(msgs[[2L]]$content[[2L]],
                   list(toolUse = list(toolUseId = "toolu_1_fc_2", name = "read",
                                       input = list(path = "a.R"))))
  results = msgs[[3L]]$content
  expect_identical(results[[1L]], list(toolResult = list(toolUseId = "toolu_1_fc_2",
                                                         content = list(list(text = "x = 1")))))
  expect_identical(results[[2L]]$toolResult$status, "error")
  # a text-only model gets a note for an image; a reasoning model gets no temperature
  model = test_model(api, input = "text", reasoning = TRUE)
  body = json_decode(bedrock_build(model, ctx, list(base_url = "https://h.test"))$body)
  expect_identical(body$messages[[1L]]$content[[4L]]$text, adp_image_note())
  expect_identical(body$inferenceConfig, list(maxTokens = 512L))
  # model ids are one path segment
  model = test_model(api, id = "anthropic.claude-v1:0")
  expect_match(bedrock_build(model, ctx, list(base_url = "https://h.test"))$url,
               "/model/anthropic.claude-v1%3A0/converse-stream", fixed = TRUE)
})

test_that("signed reasoning is replayed only to the model that produced it", {
  turn = msg_assistant(list(block_thinking("Think.", signature = "sig1"), block_text("Done.")),
                       api = api, provider = "fixture", model = "fixture-1")
  ctx = ctx_fixture(list(msg_user("q", timestamp = 1), turn, msg_user("again", timestamp = 2)))
  body = json_decode(bedrock_build(test_model(api), ctx, list(base_url = "https://h.test"))$body)
  expect_identical(body$messages[[2L]]$content[[1L]],
                   list(reasoningContent = list(reasoningText = list(text = "Think.",
                                                                     signature = "sig1"))))
  other = test_model(api, id = "other-1")
  body = json_decode(bedrock_build(other, ctx, list(base_url = "https://h.test"))$body)
  expect_identical(body$messages[[2L]]$content, list(list(text = "Done.")))
})

test_that("a Claude model declared adaptive gets the thinking level; others get none (D-250)", {
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  body_of = function(model, thinking, max_tokens = 32000L) {
    params = list(max_tokens = max_tokens, thinking = thinking, temperature = 0.2)
    ctx = ctx_fixture(list(msg_user("q", timestamp = 1)), params = params)
    json_decode(bedrock_build(model, ctx, list(base_url = "https://h.test"))$body)
  }
  today = c("inferenceConfig", "system", "toolConfig", "messages")
  opus = test_model(api, id = "us.anthropic.claude-opus-4-8")
  body = body_of(opus, "high")
  expect_identical(body$additionalModelRequestFields,
                   list(thinking = list(type = "adaptive", display = "omitted"),
                        output_config = list(effort = "high")))
  expect_identical(body$inferenceConfig, list(maxTokens = 32000L))
  expect_identical(names(body_of(opus, "off")), today)
  expect_identical(names(body_of(test_model(api, id = opus$id, reasoning = FALSE), "high")), today)
  # a registered Claude record that does not declare how it thinks (Opus 4.8 refuses a budget
  # with HTTP 400; Claude 4.5 and earlier think only on one): no thinking, said once per model
  spec = gptr_provider("gw", api = api, base_url = "https://h.test", auth = "AWS_SECRET_ACCESS_KEY",
                       compat = list(region = "us-west-2"),
                       models = list(list(id = opus$id, tool_call = TRUE, reasoning = TRUE,
                                         max_output = 32000)))
  plain = model_resolve(spec)
  withr::local_options(gptr.quiet = FALSE)
  expect_message(expect_identical(names(body_of(plain, "high")), today),
                 "capabilities = list(adaptive_thinking = TRUE, effort = TRUE)", fixed = TRUE,
                 class = "gptr_message_notice")
  expect_no_message(expect_identical(names(body_of(plain, "max")), today))
  expect_no_message(expect_identical(names(body_of(plain, NULL)), today))
  # another Converse model gets no thinking field either
  nova = test_model(api, id = "amazon.nova-pro-v1:0")
  expect_message(expect_identical(names(body_of(nova, "high")), today), "not sent",
                 class = "gptr_message_notice")
  expect_no_message(body_of(nova, "high"))
  expect_no_message(body_of(nova, "off"))
})

test_that("`returns =` adds the schema instruction to the last user message", {
  turn = msg_assistant(list(block_tool_call("toolu_1", "read", list(path = "a.R"))),
                       api = api, provider = "fixture", model = "fixture-1")
  ctx = ctx_fixture(list(msg_user("q", timestamp = 1), turn,
                         msg_tool_result("toolu_1", "read", "x = 1")),
                    params = list(returns = count_schema()))
  body = json_decode(bedrock_build(test_model(api), ctx, list(base_url = "https://h.test"))$body)
  msgs = body$messages
  expect_identical(vapply(msgs, function(m) m$role, ""), c("user", "assistant", "user"))
  last = msgs[[3L]]$content
  expect_identical(names(last[[1L]]), "toolResult")
  expect_identical(last[[2L]]$text, adp_returns_instruction(count_schema()))
})

test_that("without tools to send, past tool calls and results are text (no toolConfig)", {
  turn = msg_assistant(list(block_text("Reading."),
                            block_tool_call("toolu_1", "read", list(path = "a.R"))),
                       api = api, provider = "fixture", model = "fixture-1")
  ctx = ctx_fixture(list(msg_user("q", timestamp = 1), turn,
                         msg_tool_result("toolu_1", "read", "x = 1")))
  for (model in list(test_model(api, tool_call = FALSE), test_model(api))) {
    if (isTRUE(model$tool_call)) ctx$tools_json = json_verbatim("[]")
    body = suppressMessages(bedrock_build(model, ctx, list(base_url = "https://h.test"))$body)
    expect_false(grepl("toolUse|toolResult|toolConfig", body))
    msgs = json_decode(body)$messages
    expect_identical(vapply(msgs, function(m) m$role, ""), c("user", "assistant", "user"))
    expect_identical(msgs[[2L]]$content[[2L]]$text, "[tool call read {\"path\":\"a.R\"}]")
    expect_identical(vapply(msgs[[3L]]$content, function(b) b$text, ""),
                     c("[tool result of read]", "x = 1"))
  }
})

# ---- signing: build() and http_handle() --------------------------------------------------------

test_that("with a key pair the request is signed for service bedrock and the record's region", {
  local_vault()
  withr::local_envvar(AWS_ACCESS_KEY_ID = aws_key_id, AWS_SECRET_ACCESS_KEY = aws_secret,
                      AWS_SESSION_TOKEN = aws_token)
  local_bedrock_provider()
  p = provider_get("versa-test")
  model = model_resolve("versa-test/us.anthropic.claude-opus-4-8")
  opts = list(credential = provider_credential(p), base_url = provider_base_url(p), provider = p)
  spec = bedrock_build(model, ctx_fixture(list(msg_user("hi", timestamp = 1))), opts)
  expect_identical(spec$url, paste0("https://bedrock.example.test/awsai/model/",
                                    "us.anthropic.claude-opus-4-8/converse-stream"))
  origin = url_origin(spec$url)
  h = spec$sign("POST", spec$url, charToRaw(spec$body), function(x) secret_value(x, origin))
  expect_named(h, c("x-amz-content-sha256", "x-amz-date", "x-amz-security-token",
                    "authorization"))
  expect_identical(h[["x-amz-content-sha256"]], hash_sha256(charToRaw(spec$body)))
  expect_identical(h[["x-amz-security-token"]], aws_token)
  expect_match(h$authorization, paste0(
    "^AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/", substr(h[["x-amz-date"]], 1L, 8L),
    "/us-west-2/bedrock/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date;",
    "x-amz-security-token, Signature=[0-9a-f]{64}$"))
  # without a session token nothing names one
  withr::local_envvar(AWS_SESSION_TOKEN = "")
  local_vault()
  opts$credential = provider_credential(p)
  spec = bedrock_build(model, ctx_fixture(list(msg_user("hi", timestamp = 1))), opts)
  h = spec$sign("POST", spec$url, charToRaw(spec$body), function(x) secret_value(x, origin))
  expect_named(h, c("x-amz-content-sha256", "x-amz-date", "authorization"))
  # a missing region or key id is refused before anything is sent
  opts$provider$compat = list()
  expect_error(bedrock_build(model, ctx_fixture(list(msg_user("hi"))), opts),
               class = "gptr_error_invalid_spec")
  opts$provider = p
  withr::local_envvar(AWS_ACCESS_KEY_ID = "")
  local_vault()
  opts$credential = provider_credential(p)
  err = expect_error(bedrock_build(model, ctx_fixture(list(msg_user("hi"))), opts),
                     class = "gptr_error_no_key")
  expect_identical(err$variables, "AWS_ACCESS_KEY_ID")
  expect_false(grepl(aws_secret, conditionMessage(err), fixed = TRUE))
})

test_that("a key pair loaded into the vault only, through aliases, signs the request", {
  local_vault()
  f = withr::local_tempfile(fileext = ".env")
  writeLines(c(paste0("AWS_ACCESS_KEY=", aws_key_id), paste0("AWS_SECRET_KEY=", aws_secret)), f)
  rep = gptr_env(f, aliases = list(AWS_ACCESS_KEY_ID = "AWS_ACCESS_KEY",
                                   AWS_SECRET_ACCESS_KEY = "AWS_SECRET_KEY"),
                 set_env = FALSE, quiet = TRUE)
  expect_identical(rep$secret, c(TRUE, TRUE))
  expect_identical(rep$action, c("registered", "registered"))
  expect_identical(unname(Sys.getenv(c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"))), c("", ""))
  local_bedrock_provider()
  p = provider_get("versa-test")
  opts = list(credential = provider_credential(p), base_url = provider_base_url(p), provider = p)
  spec = bedrock_build(model_resolve("versa-test/us.anthropic.claude-opus-4-8"),
                       ctx_fixture(list(msg_user("hi", timestamp = 1))), opts)
  origin = url_origin(spec$url)
  h = spec$sign("POST", spec$url, charToRaw(spec$body), function(x) secret_value(x, origin))
  expect_match(h$authorization, "Credential=AKIDEXAMPLE/", fixed = TRUE)
})

test_that("a worker sub-agent gets the key id and session token with the secret key", {
  local_vault()
  withr::local_envvar(AWS_ACCESS_KEY_ID = aws_key_id, AWS_SECRET_ACCESS_KEY = aws_secret,
                      AWS_SESSION_TOKEN = aws_token)
  local_bedrock_provider()
  env = child_env("worker", provider = "versa-test")
  keys = c("AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_SESSION_TOKEN")
  expect_identical(unname(env[keys]), c(aws_secret, aws_key_id, aws_token))
  withr::local_envvar(AWS_SESSION_TOKEN = "")
  local_vault()
  expect_false("AWS_SESSION_TOKEN" %in% names(child_env("worker", provider = "versa-test")))
})

test_that("http_handle() calls spec$sign per attempt with values for the URL's own origin only", {
  local_vault()
  h = secret_register("synthetic-sign-secret-0123456789", "GPTR_SIGN_TEST_KEY",
                      origin = "https://sign.example.test")
  seen = new.env(parent = emptyenv())
  seen$calls = list()
  spec = list(url = "https://sign.example.test/a", method = "POST",
              headers = list(`content-type` = "application/json"), body = "{}",
              sign = function(method, url, body, value) {
                seen$calls[[length(seen$calls) + 1L]] = list(method, url, body, value(h))
                list(`x-signed` = "yes")
              })
  expect_s3_class(http_handle(spec), "curl_handle")
  expect_s3_class(http_handle(spec), "curl_handle")
  expect_length(seen$calls, 2L)
  expect_identical(seen$calls[[1L]], list("POST", "https://sign.example.test/a", charToRaw("{}"),
                                          "synthetic-sign-secret-0123456789"))
  spec$url = "https://other.example.test/a"
  expect_error(http_handle(spec), class = "gptr_error_untrusted")
  spec$url = "https://sign.example.test/a"
  spec$sign = function(method, url, body, value) list(`x-bad` = "a\r\nb")
  expect_error(http_handle(spec), class = "gptr_error_invalid_argument")
})

# ---- the agent loop and redaction --------------------------------------------------------------

test_that("a recorded ConverseStream runs a tool through the agent loop (scripted wire)", {
  local_vault()
  local_gptr_options(unsafe_no_permissions = TRUE)
  withr::local_envvar(AWS_ACCESS_KEY_ID = aws_key_id, AWS_SECRET_ACCESS_KEY = aws_secret,
                      AWS_SESSION_TOKEN = "")
  local_bedrock_provider()
  local_count_tool()
  wire = local_scripted_wire(list(converse_tool(id = "tooluse_7", name = "count", input = "{}"),
                                  converse_text("There are 32 rows.")))
  s = session_new("versa-test/us.anthropic.claude-opus-4-8", "auto", home = new.env())
  session_run(s, msg_user("How many rows?"))
  expect_identical(vapply(s$messages, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "assistant"))
  expect_identical(msg_text(s$messages[[4L]]), "There are 32 rows.")
  expect_identical(s$messages[[3L]]$tool_call_id, "tooluse_7")
  expect_length(wire$requests, 2L)
  expect_true(all(vapply(wire$requests, function(r) is.function(r$sign), NA)))
  second = json_decode(wire$requests[[2L]]$body)
  expect_identical(vapply(second$messages, function(m) m$role, ""),
                   c("user", "assistant", "user"))
  expect_identical(second$messages[[2L]]$content[[2L]]$toolUse$toolUseId, "tooluse_7")
  result = second$messages[[3L]]$content[[1L]]$toolResult
  expect_identical(result$toolUseId, "tooluse_7")
  expect_match(result$content[[1L]]$text, "32", fixed = TRUE)
  expect_true("count" %in% vapply(second$toolConfig$tools, function(t) t$toolSpec$name, ""))
})

test_that("request specs hold handles only, never the secret key or the session token", {
  local_vault()
  withr::local_envvar(AWS_ACCESS_KEY_ID = aws_key_id, AWS_SECRET_ACCESS_KEY = aws_secret,
                      AWS_SESSION_TOKEN = aws_token)
  local_bedrock_provider()
  p = provider_get("versa-test")
  opts = list(credential = provider_credential(p), base_url = provider_base_url(p), provider = p)
  spec = bedrock_build(model_resolve("versa-test/us.anthropic.claude-opus-4-8"),
                       ctx_fixture(list(msg_user("hi", timestamp = 1))), opts)
  shown = paste(c(spec$url, spec$body, utils::capture.output(str(spec$headers)),
                  utils::capture.output(print(as.list(environment(spec$sign))))), collapse = "\n")
  for (v in c(aws_secret, aws_token)) expect_false(grepl(v, shown, fixed = TRUE))
  held = mget(c("key_id", "secret", "token"), envir = environment(spec$sign))
  expect_true(all(vapply(held, inherits, NA, what = "gptr_secret")))
  # the values are registered, so any text that echoes them is redacted
  echoed = gptr_redact(paste("denied", aws_secret, aws_token))
  for (v in c(aws_secret, aws_token)) expect_false(grepl(v, echoed, fixed = TRUE))
})

test_that("a refused key pair over HTTP names no secret in the error or the events (mock)", {
  local_vault()
  echo = json_encode(list(message = paste("Invalid Client Id", aws_secret, aws_token)))
  srv = local_mock_server("json", status = 403L, body = echo)
  withr::local_envvar(AWS_ACCESS_KEY_ID = aws_key_id, AWS_SECRET_ACCESS_KEY = aws_secret,
                      AWS_SESSION_TOKEN = aws_token)
  local_bedrock_provider("versa-mock", base_url = srv$url)
  log = event_log()
  out = new.env(parent = emptyenv())
  out$message = NULL
  provider_stream(model_resolve("versa-mock/us.anthropic.claude-opus-4-8"),
                  ctx_fixture(list(msg_user("hi", timestamp = 1))), list(), emit = log$emit,
                  done = function(msg) out$message = msg)
  reactor_pump(until = function() !is.null(out$message), timeout = 30)
  m = out$message
  expect_identical(m$stop_reason, "error")
  expect_match(m$error_message, "HTTP 403: Invalid Client Id", fixed = TRUE)
  err = log$events[[length(log$events)]]
  expect_identical(err$error$class, "auth")
  seen = paste(m$error_message, json_encode(lapply(log$events, adp_golden_event)))
  for (v in c(aws_secret, aws_token)) expect_false(grepl(v, seen, fixed = TRUE))
  req = srv$log()
  expect_match(req$path[[1L]], "/model/us.anthropic.claude-opus-4-8/converse-stream$")
  expect_match(req$headers[[1L]], "authorization: [redacted]", fixed = TRUE)
  expect_match(req$headers[[1L]],
               paste0("x-amz-content-sha256: ", hash_sha256(req$body[[1L]])), fixed = TRUE)
  expect_false(grepl(aws_secret, paste(req$headers[[1L]], req$body[[1L]]), fixed = TRUE))
})

test_that("the adapter is registered and the bearer-token bedrock record is unchanged", {
  withr::local_envvar(AWS_REGION = "", AWS_DEFAULT_REGION = "")
  a = adapter_get(api)
  expect_identical(a$transport, "http_sse")
  expect_identical(a$capabilities$max_tool_name, 64L)
  expect_false(a$capabilities$forced_tool_choice)
  b = provider_get("bedrock")
  expect_identical(c(b$api, b$auth), c("openai-completions", "AWS_BEARER_TOKEN_BEDROCK"))
  expect_identical(provider_base_url(b),
                   "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1")
})
