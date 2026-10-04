# Writes the P12 wire fixtures: tests/testthat/fixtures/sse/<api>/<case>.sse (raw stream bytes)
# with the hand-specified golden files <case>.events.json and <case>.message.json (contract
# sec 12.4). The golden values are written here by hand, never computed by gptr.
# Run from the repository root: Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
# ASCII only: non-ASCII text is written with \u escapes, which are marked UTF-8 in every locale.

root = file.path("tests", "testthat", "fixtures", "sse")
if (!dir.exists(root)) stop("run from the repository root")

to_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE))
}
write_text = function(path, text) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(text), con)
}
obj = function() structure(list(), names = character())
drop_null = function(x) x[!vapply(x, is.null, logical(1))]
js = function(...) paste0(...)

# ---- stream builders -----------------------------------------------------------------------
ev = function(event, data) paste0("event: ", event, "\n", "data: ", data, "\n\n")
dat = function(data) paste0("data: ", data, "\n\n")

# ---- golden builders (key order = the order of adp_golden_*() in provider-anthropic.R) ------
g_text = function(text, signature = NULL) {
  drop_null(list(type = "text", text = text, signature = signature))
}
g_think = function(thinking, signature = NULL, redacted = NULL, data = NULL) {
  drop_null(list(type = "thinking", thinking = thinking, signature = signature,
                 redacted = redacted, data = data))
}
g_tool = function(id, name, arguments, raw = NULL, sig = NULL) {
  drop_null(list(type = "tool_call", id = id, name = name, arguments = arguments,
                 raw_arguments = raw, thought_signature = sig))
}
g_opaque = function(json) list(type = "opaque", json = json)
e_start = function(rid) list(type = "start", response_id = rid)
e_open = function(kind, i) list(type = paste0(kind, "_start"), index = i)
e_delta = function(kind, i, d) list(type = paste0(kind, "_delta"), index = i, delta = d)
e_end = function(kind, i, block) list(type = paste0(kind, "_end"), index = i, block = block)
e_tstart = function(i, id, name) list(type = "toolcall_start", index = i, id = id, name = name)
e_done = function(reason) list(type = "done", reason = reason)
e_error = function(class, status = NULL) {
  list(type = "error", reason = "error", error = list(class = class, status = status))
}
g_usage = function(input = 0, output = 0, cache_read = 0, w5 = 0, w1 = 0, reasoning = 0) {
  list(input = input, output = output, cache_read = cache_read, cache_write_5m = w5,
       cache_write_1h = w1, reasoning = reasoning,
       total = input + output + cache_read + w5 + w1)
}
# The usage of a stream that reported none: every count unknown, JSON null (IC-74: "Missing usage
# remains unknown"; 07-local-ollama.md section 5)
g_usage_unknown = function() {
  list(input = NULL, output = NULL, cache_read = NULL, cache_write_5m = NULL,
       cache_write_1h = NULL, reasoning = NULL, total = NULL)
}
g_msg = function(stop, raw = NULL, err = NULL, rid = NULL, rmodel = NULL, content = list(),
                 usage = g_usage()) {
  drop_null(list(stop_reason = stop, raw_stop_reason = raw, error_message = err,
                 response_id = rid, response_model = rmodel, content = content,
                 usage = usage))
}
write_case = function(api, case, stream, events, message, eol = "\n") {
  dir = file.path(root, api)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  stream = paste(stream, collapse = "")
  if (!identical(eol, "\n")) stream = gsub("\n", eol, stream, fixed = TRUE)
  write_text(file.path(dir, paste0(case, ".sse")), stream)
  write_text(file.path(dir, paste0(case, ".events.json")), paste0(to_json(events), "\n"))
  write_text(file.path(dir, paste0(case, ".message.json")), paste0(to_json(message), "\n"))
}
# ============================================================================================
# anthropic-messages
# ============================================================================================
a = "anthropic-messages"
greet = "caf\u00e9 \u2014 \U0001F600."

a_text = c(
  ": keep-alive\n\n",
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01TEXT",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"stop_sequence":null,',
    '"usage":{"input_tokens":12,"cache_read_input_tokens":0,',
    '"cache_creation_input_tokens":0,"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("ping", '{"type":"ping"}'),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"Hello, "}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"',
    greet,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn",',
    '"stop_sequence":null},"usage":{"output_tokens":9}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "text", a_text,
  list(e_start("msg_01TEXT"), e_open("text", 1L), e_delta("text", 1L, "Hello, "),
       e_delta("text", 1L, greet), e_end("text", 1L, g_text(paste0("Hello, ", greet))),
       e_done("stop")),
  g_msg("stop", "end_turn", rid = "msg_01TEXT", rmodel = "claude-sonnet-5-5",
        content = list(g_text(paste0("Hello, ", greet))), usage = g_usage(12, 9)),
  eol = "\r\n"
)

sig = "EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds=="
red = "EmwKAhgBEgy3va3pzix/LafPsn4aDFIT2Xlxh0L5L8rLVyIwxtE3rAFBa8cr3qpP"
think = "The user wants mpg by cyl. Aggregate in the session."

a_tools = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01TOOLS",',
    '"type":"message","role":"assistant","model":"claude-opus-5-5",',
    '"content":[],"stop_reason":null,"stop_sequence":null,',
    '"usage":{"input_tokens":2140,"cache_read_input_tokens":18000,',
    '"cache_creation_input_tokens":1200,',
    '"cache_creation":{"ephemeral_5m_input_tokens":200,',
    '"ephemeral_1h_input_tokens":1000},"output_tokens":3}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"thinking","thinking":"","signature":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"thinking_delta",',
    '"thinking":"The user wants mpg by cyl. "}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"thinking_delta",',
    '"thinking":"Aggregate in the session."}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"signature_delta","signature":"',
    sig,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":1,',
    '"content_block":{"type":"redacted_thinking","data":"',
    red,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":1}'),
  ev("future_event", '{"type":"future_event","detail":1}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":2,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":2,',
    '"delta":{"type":"text_delta","text":"I will compute that."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":2}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":3,',
    '"content_block":{"type":"tool_use","id":"toolu_01A","name":"r",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta","partial_json":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"code\\": \\"aggregate(mpg ~ cyl"}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta","partial_json":", mtcars,',
    ' mean)\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":3}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":4,',
    '"content_block":{"type":"tool_use","id":"toolu_01B","name":"read",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":4,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"path\\":\\"R/a.R\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":4}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"tool_use",',
    '"stop_sequence":null},"usage":{"output_tokens":187,',
    '"output_tokens_details":{"thinking_tokens":61}}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
code_args = list(code = "aggregate(mpg ~ cyl, mtcars, mean)")
write_case(
  a, "thinking_tools", a_tools,
  list(e_start("msg_01TOOLS"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "The user wants mpg by cyl. "),
       e_delta("thinking", 1L, "Aggregate in the session."),
       e_end("thinking", 1L, g_think(think, signature = sig)),
       e_open("thinking", 2L), e_end("thinking", 2L, g_think("", redacted = TRUE, data = red)),
       e_open("text", 3L), e_delta("text", 3L, "I will compute that."),
       e_end("text", 3L, g_text("I will compute that.")),
       e_tstart(4L, "toolu_01A", "r"),
       e_delta("toolcall", 4L, "{\"code\": \"aggregate(mpg ~ cyl"),
       e_delta("toolcall", 4L, ", mtcars, mean)\"}"),
       e_end("toolcall", 4L, g_tool("toolu_01A", "r", code_args)),
       e_tstart(5L, "toolu_01B", "read"),
       e_delta("toolcall", 5L, "{\"path\":\"R/a.R\"}"),
       e_end("toolcall", 5L, g_tool("toolu_01B", "read", list(path = "R/a.R"))),
       e_done("tool_use")),
  g_msg("tool_use", "tool_use", rid = "msg_01TOOLS", rmodel = "claude-opus-5-5",
        content = list(g_think(think, signature = sig),
                       g_think("", redacted = TRUE, data = red),
                       g_text("I will compute that."),
                       g_tool("toolu_01A", "r", code_args),
                       g_tool("toolu_01B", "read", list(path = "R/a.R"))),
        usage = g_usage(2140, 187, 18000, 200, 1000, 61))
)

a_error = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01ERR",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":25,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"Partial ans"}}'
  )),
  ev("error", js(
    '{"type":"error","error":{"type":"overloaded_error",',
    '"message":"Overloaded"}}'
  ))
)
write_case(
  a, "error_midstream", a_error,
  list(e_start("msg_01ERR"), e_open("text", 1L), e_delta("text", 1L, "Partial ans"),
       e_error("overloaded", 529L)),
  g_msg("error", err = "overloaded_error: Overloaded", rid = "msg_01ERR",
        rmodel = "claude-sonnet-5-5", content = list(g_text("Partial ans")),
        usage = g_usage(25, 1))
)

a_cut = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01CUT",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":25,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"tool_use","id":"toolu_01C","name":"write",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"path\\": \\"a.R\\", \\"content\\": \\"x = "}}'
  ))
)
cut_raw = "{\"path\": \"a.R\", \"content\": \"x = "
write_case(
  a, "truncated", a_cut,
  list(e_start("msg_01CUT"), e_tstart(1L, "toolu_01C", "write"),
       e_delta("toolcall", 1L, cut_raw), e_error("network")),
  g_msg("error", err = "The Anthropic stream ended before message_stop.", rid = "msg_01CUT",
        rmodel = "claude-sonnet-5-5",
        content = list(g_tool("toolu_01C", "write", obj(), raw = cut_raw)),
        usage = g_usage(25, 1))
)

a_refusal = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01REF",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":30,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"I cannot help with that."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"refusal",',
    '"stop_sequence":null,"stop_details":{"type":"refusal",',
    '"category":"cyber","explanation":"The request was declined."}},',
    '"usage":{"output_tokens":7}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "refusal", a_refusal,
  list(e_start("msg_01REF"), e_open("text", 1L), e_delta("text", 1L, "I cannot help with that."),
       e_end("text", 1L, g_text("I cannot help with that.")), e_done("refusal")),
  g_msg("refusal", "refusal", err = "The request was declined.", rid = "msg_01REF",
        rmodel = "claude-sonnet-5-5", content = list(g_text("I cannot help with that.")),
        usage = g_usage(30, 7))
)

stu = js(
  '{"type":"server_tool_use","id":"srvtoolu_01","name":"web_search",',
  '"input":{"query":"R 4.4 news"}}'
)

wsr = js(
  '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_01",',
  '"content":[{"type":"web_search_result",',
  '"url":"https://example.org/r","title":"R news",',
  '"encrypted_content":"EqgfCioIARgB"}]}'
)

a_server = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01SRV",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":40,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"server_tool_use","id":"srvtoolu_01",',
    '"name":"web_search","input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"query\\":\\"R 4.4 news\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":1,"content_block":',
    wsr,
    "}"
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":1}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":2,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":2,',
    '"delta":{"type":"text_delta","text":"R 4.4 is out."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":2}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn",',
    '"stop_sequence":null},"usage":{"output_tokens":20}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "server_tool", a_server,
  list(e_start("msg_01SRV"), e_open("text", 3L), e_delta("text", 3L, "R 4.4 is out."),
       e_end("text", 3L, g_text("R 4.4 is out.")), e_done("stop")),
  g_msg("stop", "end_turn", rid = "msg_01SRV", rmodel = "claude-sonnet-5-5",
        content = list(g_opaque(stu), g_opaque(wsr), g_text("R 4.4 is out.")),
        usage = g_usage(40, 20))
)

# ============================================================================================
# openai-completions (model.json: provider together, so the <think> splitter is on)
# ============================================================================================
k = "openai-completions"
dir.create(file.path(root, k), showWarnings = FALSE, recursive = TRUE)
write_text(file.path(root, k, "model.json"),
           '{"provider": "together", "id": "deepseek-r1", "input": ["text"]}\n')
chat_chunk = function(delta, finish = "null") {
  js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[{"index":0,"delta":', delta, ',"finish_reason":', finish, "}]}"
  )
}

k_tools = c(
  ": OPENROUTER PROCESSING\n\n",
  dat(chat_chunk(js(
    '{"role":"assistant","content":"",',
    '"reasoning_content":"Need two lookups. "}'
  ))),
  dat(chat_chunk('{"content":"Checking both files"}')),
  dat(chat_chunk('{"content":"."}')),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":0,"id":"call_A1","type":"function",',
    '"function":{"name":"read","arguments":""}}]}'
  ))),
  dat(chat_chunk('{"tool_calls":[{"index":0,"function":{"arguments":"{\\"pa"}}]}')),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":0,"function":',
    '{"arguments":"th\\":\\"R/a.R\\"}"}}]}'
  ))),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":1,"id":"call_B2","type":"function",',
    '"function":{"name":"grep","arguments":"{\\"pattern\\":\\"nrow\\"}"}}]}'
  ))),
  dat(chat_chunk("{}", '"tool_calls"')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[],"usage":{"prompt_tokens":1500,"completion_tokens":96,',
    '"total_tokens":1596,"prompt_tokens_details":{"cached_tokens":1024},',
    '"completion_tokens_details":{"reasoning_tokens":32}}}'
  )),
  dat("[DONE]")
)
write_case(
  k, "tools", k_tools,
  list(e_start("chatcmpl-1"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "Need two lookups. "), e_open("text", 2L),
       e_delta("text", 2L, "Checking both files"), e_delta("text", 2L, "."),
       e_tstart(3L, "call_A1", "read"), e_delta("toolcall", 3L, "{\"pa"),
       e_delta("toolcall", 3L, "th\":\"R/a.R\"}"),
       e_tstart(4L, "call_B2", "grep"), e_delta("toolcall", 4L, "{\"pattern\":\"nrow\"}"),
       e_end("thinking", 1L, g_think("Need two lookups. ", signature = "reasoning_content")),
       e_end("text", 2L, g_text("Checking both files.")),
       e_end("toolcall", 3L, g_tool("call_A1", "read", list(path = "R/a.R"))),
       e_end("toolcall", 4L, g_tool("call_B2", "grep", list(pattern = "nrow"))),
       e_done("tool_use")),
  g_msg("tool_use", "tool_calls", rid = "chatcmpl-1",
        content = list(g_think("Need two lookups. ", signature = "reasoning_content"),
                       g_text("Checking both files."),
                       g_tool("call_A1", "read", list(path = "R/a.R")),
                       g_tool("call_B2", "grep", list(pattern = "nrow"))),
        usage = g_usage(476, 96, 1024, reasoning = 32))
)

k_tags = c(
  dat(chat_chunk('{"role":"assistant","content":"<thi"}')),
  dat(chat_chunk('{"content":"nk>Plan: count rows.</th"}')),
  dat(chat_chunk('{"content":"ink>\\n\\nThere are 32 rows."}')),
  dat(chat_chunk("{}", '"stop"')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[],"usage":{"prompt_tokens":40,"completion_tokens":12,"total_tokens":52}}'
  )),
  dat("[DONE]")
)
write_case(
  k, "think_tags", k_tags,
  list(e_start("chatcmpl-1"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "Plan: count rows."), e_open("text", 2L),
       e_delta("text", 2L, "\n\nThere are 32 rows."),
       e_end("thinking", 1L, g_think("Plan: count rows.")),
       e_end("text", 2L, g_text("\n\nThere are 32 rows.")), e_done("stop")),
  g_msg("stop", "stop", rid = "chatcmpl-1",
        content = list(g_think("Plan: count rows."), g_text("\n\nThere are 32 rows.")),
        usage = g_usage(40, 12))
)

# error_chunk and truncated report no usage: it stays unknown (IC-74), never a zero
k_error = c(
  dat(chat_chunk('{"role":"assistant","content":"Partial"}')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk",',
    '"choices":[{"index":0,"delta":{},"finish_reason":"error"}],',
    '"error":{"code":502,"message":"Upstream provider failed"}}'
  ))
)
write_case(
  k, "error_chunk", k_error,
  list(e_start("chatcmpl-1"), e_open("text", 1L), e_delta("text", 1L, "Partial"),
       e_error("overloaded", 502L)),
  g_msg("error", err = "Upstream provider failed", rid = "chatcmpl-1",
        content = list(g_text("Partial")), usage = g_usage_unknown())
)

write_case(
  k, "truncated", dat(chat_chunk('{"role":"assistant","content":"Half"}')),
  list(e_start("chatcmpl-1"), e_open("text", 1L), e_delta("text", 1L, "Half"),
       e_error("network")),
  g_msg("error", err = "The stream ended without a finish_reason.", rid = "chatcmpl-1",
        content = list(g_text("Half")), usage = g_usage_unknown())
)
