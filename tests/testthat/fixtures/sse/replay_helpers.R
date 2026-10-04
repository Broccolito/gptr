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
