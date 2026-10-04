# Shared helpers of the P12 adapter tests. P12 owns tests/testthat/fixtures/sse/ and no
# helper-*.R file, so every test-provider-*.R and test-live-*.R file sources this file first
# (local = TRUE, through testthat::test_path()).

# The fixture directory of an api
sse_dir = function(api) testthat::test_path("fixtures", "sse", api)

# An event collector: log$emit(ev) appends to log$events
event_log = function() {
  log = new.env(parent = emptyenv())
  log$events = list()
  log$emit = function(ev) log$events[[length(log$events) + 1L]] = ev
  log
}

# The types of a list of events
types_of = function(events) vapply(events, function(e) e$type %||% "", "")

# Replay one fixture through a normaliser in the given chunk sizes (whole stream by default)
replay_case = function(api, parse, case, sizes = NULL) {
  dir = sse_dir(api)
  path = file.path(dir, paste0(case, ".sse"))
  bytes = readBin(path, "raw", file.size(path))
  adapter = list(api = api, transport = "http_sse", parse = parse)
  adp_replay(adapter, adp_fixture_model(api, dir), bytes, sizes %||% length(bytes))
}

# Compare x with a golden JSON file of the fixture directory (04 section 12.4)
expect_golden = function(x, api, file) {
  want = json_decode(read_utf8(file.path(sse_dir(api), file))$text)
  testthat::expect_equal(json_decode(json_encode(x)), want)
}

# The golden check of every case of an api: events and the final message
expect_all_golden = function(api, parse) {
  cases = sub("\\.sse$", "", list.files(sse_dir(api), pattern = "\\.sse$"))
  testthat::expect_gt(length(cases), 0L)
  for (case in cases) {
    r = replay_case(api, parse, case)
    testthat::expect_null(r$condition)
    expect_golden(lapply(r$events, adp_golden_event), api, paste0(case, ".events.json"))
    expect_golden(adp_golden_message(r$message), api, paste0(case, ".message.json"))
  }
}

# Byte-by-byte and three pseudo-random chunkings give the events of the whole stream (INFRA-23)
expect_chunk_invariant = function(api, parse, case) {
  whole = lapply(replay_case(api, parse, case)$events, adp_golden_event)
  for (sz in list(1L, adp_chunk_sizes("a"), adp_chunk_sizes("b"), adp_chunk_sizes("c"))) {
    got = lapply(replay_case(api, parse, case, sz)$events, adp_golden_event)
    testthat::expect_identical(got, whole)
  }
}

# Exactly one start event first and exactly one terminal event last
expect_one_terminal = function(events) {
  types = types_of(events)
  testthat::expect_identical(types[[1L]], "start")
  testthat::expect_identical(sum(types == "start"), 1L)
  testthat::expect_identical(sum(types %in% c("done", "error")), 1L)
  testthat::expect_true(types[[length(types)]] %in% c("done", "error"))
}

# A model record (04 section 4.9) for normaliser and request-builder tests
test_model = function(api, id = "fixture-1", provider = "fixture", ...) {
  m = adp_fixture_model(api)
  m$id = id
  m$provider = provider
  m$ref = paste0(provider, "/", id)
  over = list(...)
  for (k in names(over)) m[[k]] = over[[k]]
  m
}

# ---- request contexts (04 section 8.1) ---------------------------------------------------------

# The frozen tool array in the Anthropic shape (04 section 9.2): read and r
tools_json_fixture = function() {
  json_verbatim(paste0(
    '[{"name":"read","description":"Read a file.","input_schema":{"type":"object",',
    '"required":["path"],"properties":{"path":{"type":"string"}}}},',
    '{"name":"r","description":"Run R code.","input_schema":{"type":"object",',
    '"required":["code"],"properties":{"code":{"type":"string"}}}}]'
  ))
}

# The first user message: the anchored project block, the environment block, the prompt
first_message = function(prompt = "How many rows does d have?") {
  msg_user(list(block_context("project_instructions", "Use data.table.",
                              attrs = list(path = "AGENTS.md"), anchor = TRUE),
                block_context("environment", "R 4.4.3 on macOS"),
                block_text(prompt)), timestamp = 1)
}

# A request context of 04 section 8.1
ctx_fixture = function(messages, params = list(), cache_plan = NULL, t1 = "T1 catalogs.") {
  p = list(max_tokens = 1024L, thinking = NULL, effort = NULL, tool_choice = "auto",
           returns = NULL, temperature = NULL)
  for (k in names(params)) p[k] = list(params[[k]])
  list(system = list(t0 = "T0 static sections.", t1 = t1), tools_json = tools_json_fixture(),
       tools = list(), messages = messages,
       cache_plan = cache_plan %||% list(anchors = c("t0", "project"), tail_ttl = "5m",
                                         key = "gptr:0123456789ab"),
       params = p, session_id = "s0123456789", request_id = "q0123456789ab")
}

# The cache plan the registered default cache_policy (P07, prompt-cache.R) gives an adapter
default_plan = function(api, project = TRUE) {
  policy = registry_get("cache_policy", "default")
  testthat::skip_if(is.null(policy), "the default cache_policy of builtin:prompt is not loaded")
  parts = list(t0 = "T0 static sections.", t1 = "T1 catalogs.", tools_json = "[]",
               project = project, n = 1L)
  policy$plan(parts, adapter_get(api)$capabilities, NULL)
}

# A secret handle of the 04 section 5.9 shape, holding no value
fake_handle = function(name) {
  structure(list(id = paste0(name, "#abc123"), name = name, fp = "abc123", origin = NULL),
            class = "gptr_secret")
}

# A 1 x 1 PNG as base64
png_b64 = function() {
  paste0("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJ",
         "RU5ErkJggg==")
}

# ---- scripted wire: SSE bodies through the real adapter, run loop and reactor -----------------

# Replace reactor_http() (P04) so that request k receives bodies[[k]] (the last repeats) through
# reactor_task(); every request spec is kept in wire$requests. No socket is opened.
local_scripted_wire = function(bodies, .env = parent.frame()) {
  wire = new.env(parent = emptyenv())
  wire$bodies = bodies
  wire$requests = list()
  scripted_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL,
                           provider = NULL, retry = NULL) {
    k = length(wire$requests) + 1L
    wire$requests[[k]] = spec
    body = wire$bodies[[min(k, length(wire$bodies))]]
    reactor_task(function() {
      if (is.function(on_headers)) on_headers(200L, list(`content-type` = "text/event-stream"))
      on_bytes(charToRaw(body))
      on_done(200L, list())
      FALSE
    })
  }
  testthat::local_mocked_bindings(reactor_http = scripted_http, .env = .env)
  wire
}

# One SSE event as text
sse_event = function(event, data) paste0("event: ", event, "\n", "data: ", data, "\n\n")

# An Anthropic stream with one tool call (stop_reason tool_use)
anthropic_sse_tool = function(id, name, json) {
  paste0(
    sse_event("message_start", paste0('{"type":"message_start","message":{"id":"msg_w1",',
                                      '"model":"scripted-1","usage":{"input_tokens":20,',
                                      '"output_tokens":1}}}')),
    sse_event("content_block_start", paste0('{"type":"content_block_start","index":0,',
                                            '"content_block":{"type":"tool_use","id":"', id,
                                            '","name":"', name, '","input":{}}}')),
    sse_event("content_block_delta", paste0('{"type":"content_block_delta","index":0,',
                                            '"delta":{"type":"input_json_delta",',
                                            '"partial_json":', json_encode(json), "}}")),
    sse_event("content_block_stop", '{"type":"content_block_stop","index":0}'),
    sse_event("message_delta", paste0('{"type":"message_delta","delta":{"stop_reason":',
                                      '"tool_use"},"usage":{"output_tokens":5}}')),
    sse_event("message_stop", '{"type":"message_stop"}')
  )
}

# An Anthropic stream with one text block (stop_reason end_turn)
anthropic_sse_text = function(text) {
  paste0(
    sse_event("message_start", paste0('{"type":"message_start","message":{"id":"msg_w2",',
                                      '"model":"scripted-1","usage":{"input_tokens":30,',
                                      '"output_tokens":1}}}')),
    sse_event("content_block_start", paste0('{"type":"content_block_start","index":0,',
                                            '"content_block":{"type":"text","text":""}}')),
    sse_event("content_block_delta", paste0('{"type":"content_block_delta","index":0,',
                                            '"delta":{"type":"text_delta","text":',
                                            json_encode(text), "}}")),
    sse_event("content_block_stop", '{"type":"content_block_stop","index":0}'),
    sse_event("message_delta", paste0('{"type":"message_delta","delta":{"stop_reason":',
                                      '"end_turn"},"usage":{"output_tokens":6}}')),
    sse_event("message_stop", '{"type":"message_stop"}')
  )
}

# A scripted provider record (offline, local, no key, IC-45) for an api, registered for the
# calling test
local_scripted_provider = function(api, structured_output = TRUE, .env = parent.frame()) {
  spec = gptr_provider("scripted", api = api, base_url = "http://127.0.0.1:9", auth = NULL,
                       models = list(list(id = "scripted-1", name = "Scripted",
                                          context = 200000, max_output = 4096,
                                          reasoning = FALSE,
                                          structured_output = structured_output,
                                          input = c("text", "image"), tool_call = TRUE)),
                       local = TRUE, offline = TRUE)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

# A `count` tool registered for the calling test; it answers "32"
local_count_tool = function(.env = parent.frame()) {
  off = gptr_register(gptr_tool("count", "Count the rows of the data.",
                                parameters = list(type = "object", properties = json_obj()),
                                execute = function(input, ctx) "32"))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

# The `returns =` schema of the INFRA-25 runs
count_schema = function() {
  list(type = "object", required = I("n"), properties = list(n = list(type = "integer")))
}

# The INFRA-25 run tests drive P06's run engine (session_new(), session_run()) with P07's request
# context (the request.build service fills params$returns; plan header "Depends on: P05, P07").
# This lane runs before P06/P07 are complete, so such a test skips until both are loaded and runs
# unchanged from then on.
skip_without_run_engine = function() {
  ns = asNamespace("gptr")
  ready = exists("session_run", envir = ns, mode = "function", inherits = FALSE) &&
    ext_service_has("request.build")
  testthat::skip_if_not(ready, "P06's session_run() and P07's request.build are not loaded")
}

# ---- the base-R mock server (P01's local_mock_server(), skips on CRAN) -------------------------

# Stream one request to the mock server through provider_stream() and the reactor; with
# `abort_after`, the run's signal is set after that many text deltas
mock_stream = function(srv, context = NULL, abort_after = NULL) {
  off = gptr_register(srv$provider)
  on.exit(off(), add = TRUE)
  model = srv$provider$models[[1L]]
  log = event_log()
  out = new.env(parent = emptyenv())
  out$message = NULL
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  signal$reason = NULL
  emit = function(ev) {
    log$emit(ev)
    if (!is.null(abort_after) && sum(types_of(log$events) == "text_delta") >= abort_after) {
      signal$aborted = TRUE
      signal$reason = "user"
    }
  }
  provider_stream(model, context %||% ctx_fixture(list(msg_user("hello", timestamp = 1))),
                  list(signal = signal), emit = emit, done = function(msg) out$message = msg)
  reactor_pump(until = function() !is.null(out$message), timeout = 30)
  list(events = log$events, types = types_of(log$events), message = out$message)
}

# A Responses stream with one function call
responses_sse_tool = function(call_id, name, json) {
  item = paste0('{"id":"fc_w1","type":"function_call","status":"completed","call_id":"', call_id,
                '","name":"', name, '","arguments":', json_encode(json), "}")
  paste0(
    sse_event("response.created", paste0('{"type":"response.created","response":',
                                         '{"id":"resp_w1","status":"in_progress",',
                                         '"output":[]}}')),
    sse_event("response.output_item.added", paste0('{"type":"response.output_item.added",',
                                                   '"output_index":0,"item":', item, "}")),
    sse_event("response.output_item.done", paste0('{"type":"response.output_item.done",',
                                                  '"output_index":0,"item":', item, "}")),
    sse_event("response.completed", paste0('{"type":"response.completed","response":',
                                           '{"id":"resp_w1","status":"completed","output":[',
                                           item, '],"usage":{"input_tokens":20,',
                                           '"output_tokens":5}}}'))
  )
}

# A Responses stream with one assistant message
responses_sse_text = function(text) {
  item = paste0('{"id":"msg_w2","type":"message","role":"assistant","status":"completed",',
                '"phase":"final_answer","content":[{"type":"output_text","text":',
                json_encode(text), ',"annotations":[]}]}')
  paste0(
    sse_event("response.created", paste0('{"type":"response.created","response":',
                                         '{"id":"resp_w2","status":"in_progress",',
                                         '"output":[]}}')),
    sse_event("response.output_item.added", paste0('{"type":"response.output_item.added",',
                                                   '"output_index":0,"item":', item, "}")),
    sse_event("response.output_item.done", paste0('{"type":"response.output_item.done",',
                                                  '"output_index":0,"item":', item, "}")),
    sse_event("response.completed", paste0('{"type":"response.completed","response":',
                                           '{"id":"resp_w2","status":"completed","output":[',
                                           item, '],"usage":{"input_tokens":30,',
                                           '"output_tokens":6}}}'))
  )
}

# ---- INFRA-08 body leg (03 section 6.18 row 08): an Anthropic-origin transcript ----------------

# Transcript entries (04 section 4.6 shape, as P06 stores them) of a conversation built on
# Anthropic: the thinking_tools fixture turn (signed and redacted thinking, two parallel tool
# calls) with its two results, then the messages of `more`. `opaque` holds every opaque string of
# the assistant messages (signatures, redacted data, reasoning items and their encrypted content,
# thought signatures), none of which a foreign target may receive
handoff_entries = function(more = list()) {
  turn = replay_case("anthropic-messages", anthropic_normaliser, "thinking_tools")$message
  msgs = c(list(first_message(), turn,
                msg_tool_result("toolu_01A", "r", "[1] 26.7 19.7 15.1", timestamp = 3),
                msg_tool_result("toolu_01B", "read", "x = 1", timestamp = 4)), more)
  entries = list()
  opaque = character()
  for (k in seq_along(msgs)) {
    entries[[k]] = list(type = "message", id = paste0("e", k),
                        parent_id = if (k > 1L) paste0("e", k - 1L),
                        timestamp = "2026-10-01T10:00:00.000Z", message = msgs[[k]])
    if (!identical(msgs[[k]][["role"]], "assistant")) next
    for (b in msgs[[k]][["content"]]) {
      opaque = c(opaque, b[["signature"]], b[["data"]], b[["thought_signature"]])
      if (identical(b[["type"]], "opaque")) {
        opaque = c(opaque, b[["json"]], json_decode(b[["json"]])[["encrypted_content"]])
      }
    }
  }
  list(entries = entries, leaf = paste0("e", length(msgs)),
       opaque = unique(opaque[nzchar(opaque)]))
}

# A closed object schema for P01's schema_validate(): unknown keys are errors
wire_object = function(properties, required = NULL) {
  s = list(type = "object", properties = properties, additionalProperties = FALSE)
  if (length(required)) s$required = required
  s
}

# The schema fixture of a Responses request body (report 08 section 3.1; G4 section 3.7): the
# fields and input items gptr sends, closed, so a foreign key such as a signature fails
responses_body_schema = function() {
  str = list(type = "string")
  arr = list(type = "array")
  enum = function(...) list(type = "string", enum = c(...))
  breakpoint = wire_object(list(mode = enum("explicit")))
  part = wire_object(list(type = enum("input_text", "input_image", "output_text"), text = str,
                          detail = str, image_url = str, annotations = arr,
                          prompt_cache_breakpoint = breakpoint), "type")
  content = list(type = c("string", "array"), items = part)
  item = wire_object(list(type = enum("message", "reasoning", "function_call",
                                      "function_call_output", "additional_tools"),
                          role = enum("developer", "user", "assistant"), id = str, status = str,
                          phase = str, content = content, summary = arr,
                          encrypted_content = str, call_id = str, name = str, arguments = str,
                          output = content, tools = arr))
  tool = wire_object(list(type = str, name = str, description = str,
                          parameters = list(type = "object"), strict = list(type = "boolean")),
                     c("type", "name", "parameters"))
  top = list(model = str, store = list(type = "boolean", enum = FALSE),
             stream = list(type = "boolean"), prompt_cache_key = str,
             prompt_cache_options = wire_object(list(mode = str)),
             reasoning = wire_object(list(effort = str, summary = str)),
             include = list(type = "array", items = str),
             max_output_tokens = list(type = "integer"),
             tool_choice = list(type = c("string", "object")),
             tools = list(type = "array", items = tool), service_tier = str,
             metadata = list(type = "object"), safety_identifier = str,
             input = list(type = "array", items = item))
  wire_object(top, c("model", "store", "stream", "input"))
}

# The schema fixture of a Gemini request body (report 09 section 2.1; G4 section 3.7): the fields,
# contents and parts gptr sends, closed, so a foreign key such as a signature fails
gemini_body_schema = function() {
  str = list(type = "string")
  obj = list(type = "object")
  int = list(type = "integer")
  inline = wire_object(list(mimeType = str, data = str), c("mimeType", "data"))
  call = wire_object(list(name = str, args = obj, id = str), c("name", "args"))
  response = wire_object(list(name = str, response = obj, id = str, parts = list(type = "array")),
                         c("name", "response"))
  part = wire_object(list(text = str, thought = list(type = "boolean"), thoughtSignature = str,
                          inlineData = inline, functionCall = call, functionResponse = response))
  parts = list(type = "array", items = part)
  decl = wire_object(list(name = str, description = str, parametersJsonSchema = obj), "name")
  tool = wire_object(list(functionDeclarations = list(type = "array", items = decl)))
  calling = wire_object(list(mode = list(type = "string", enum = c("AUTO", "ANY", "NONE")),
                             allowedFunctionNames = list(type = "array", items = str)), "mode")
  thinking = wire_object(list(includeThoughts = list(type = "boolean"), thinkingLevel = str,
                              thinkingBudget = int))
  generation = wire_object(list(maxOutputTokens = int, temperature = list(type = "number"),
                                thinkingConfig = thinking))
  content = wire_object(list(role = list(type = "string", enum = c("user", "model")),
                             parts = parts), c("role", "parts"))
  top = list(systemInstruction = wire_object(list(parts = parts), "parts"),
             tools = list(type = "array", items = tool),
             toolConfig = wire_object(list(functionCallingConfig = calling)),
             generationConfig = generation, labels = obj, serviceTier = str,
             contents = list(type = "array", items = content))
  wire_object(top, "contents")
}

# ---- live tests (opt-in: GPTR_LIVE_TESTS=true and the provider's key) ----------------------------

# Skip unless live tests are switched on and one of the key variables is set
skip_unless_live = function(keys) {
  testthat::skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"),
                        "live tests need GPTR_LIVE_TESTS=true")
  testthat::skip_if(!any(nzchar(Sys.getenv(keys))), paste(keys, collapse = " or "))
}

# One real request through provider_stream() and the reactor; returns the final message. A
# transfer still streaming at the timeout is cancelled, so it stops billing and reaches no later
# test (P04 has only first-byte and idle timers)
live_stream = function(model, context) {
  out = new.env(parent = emptyenv())
  out$message = NULL
  id = provider_stream(model, context, list(memo = new.env(parent = emptyenv())),
                       emit = function(ev) NULL, done = function(msg) out$message = msg)
  ok = reactor_pump(until = function() !is.null(out$message), timeout = 180)
  if (!isTRUE(ok) && is.character(id) && length(id) == 1L && !is.na(id)) reactor_cancel(id)
  out$message
}

# A live context: a terse system prompt, the `count` tool and the given messages. Each request
# gets its own RNG-free request id (architecture 8.1: X-Client-Request-Id unique per request)
live_context = function(messages, params = list()) {
  tools = json_verbatim(paste0(
    '[{"name":"count","description":"Count the rows of the data set d.",',
    '"input_schema":{"type":"object","properties":{}}}]'
  ))
  ctx = ctx_fixture(messages, params = params, t1 = "")
  ctx$system$t0 = "You are a terse assistant inside an R session."
  ctx$tools_json = tools
  ctx$params$max_tokens = 4096L
  ctx$request_id = id_new("q", 12L)
  ctx
}

# A text turn, then a tool round trip whose second request replays the first reply (with any
# thinking, signatures, reasoning items or thought signatures) to the same model
expect_live_round_trip = function(ref, thinking = "low") {
  model = model_resolve(ref)
  params = list(thinking = thinking)
  first = live_stream(model, live_context(list(msg_user("Reply with the single word: ready.")),
                                          params))
  testthat::expect_identical(first$stop_reason, "stop", info = first$error_message %||% "")
  testthat::expect_match(tolower(msg_text(first)), "ready")
  ask = msg_user("Use the count tool to count the rows of d, then tell me the number.")
  turn1 = live_stream(model, live_context(list(ask), params))
  testthat::expect_identical(turn1$stop_reason, "tool_use", info = turn1$error_message %||% "")
  calls = Filter(function(b) identical(b$type, "tool_call"), turn1$content)
  results = lapply(calls, function(b) msg_tool_result(b$id, b$name, "32"))
  turn2 = live_stream(model, live_context(c(list(ask, turn1), results), params))
  testthat::expect_identical(turn2$stop_reason, "stop", info = turn2$error_message %||% "")
  testthat::expect_match(msg_text(turn2), "32", fixed = TRUE)
}
