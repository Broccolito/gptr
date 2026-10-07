# The fake provider (Task 15), the shared fake helpers (Task 16) and the mock SSE server
# (Task 18).

play_fake = function(spec, messages = list(msg_user("hi")), signal = new.env(),
                     max_steps = 1000L) {
  gen = fake_stream(spec$models[[1]], list(messages = messages, request_id = "q-test"),
                    list(signal = signal))
  events = list()
  for (i in seq_len(max_steps)) {
    step = gen()
    if (is.null(step)) break
    events = c(events, step$events)
  }
  events
}

event_digest = function(ev) {
  enc = function(x) json_encode(x)
  switch(ev$type,
    start = paste("start", ev$api, ev$provider, ev$model),
    text_start = , thinking_start = paste(ev$type, ev$index),
    toolcall_start = paste(ev$type, ev$index, ev$id, ev$name),
    text_delta = , thinking_delta = paste(ev$type, ev$index, enc(ev$delta)),
    toolcall_delta = paste(ev$type, ev$index, enc(ev$delta), enc(ev$preview %||% json_obj())),
    text_end = paste(ev$type, ev$index, enc(ev$block$text)),
    thinking_end = paste(ev$type, ev$index, enc(ev$block$thinking), ev$block$signature),
    toolcall_end = paste(
      ev$type, ev$index, ev$block$id, enc(ev$block$arguments), enc(ev$block$raw_arguments)
    ),
    done = paste("done", ev$reason, ev$message$stop_reason, length(ev$message$content)),
    error = paste(
      "error", ev$reason, ev$error$class, ev$error$status, enc(msg_text(ev$message)),
      enc(ev$message$error_message)
    )
  )
}

digests = function(reply) {
  vapply(play_fake(gptr_fake_provider(list(reply))), event_digest, "")
}

test_that("gptr_fake_provider() returns an offline provider spec (contract section 12.1)", {
  spec = gptr_fake_provider(list("hi"))
  expect_s3_class(spec, c("gptr_provider", "gptr_spec"))
  expect_identical(spec$id, "fake")
  expect_identical(spec$api, "fake")
  expect_true(spec$offline)
  expect_true(spec$local)
  expect_identical(spec$api_version, "1.0")
  model = spec$models[[1]]
  expect_identical(model$ref, "fake/fake-1")
  expect_identical(model$context, 200000)
  expect_identical(model$max_output, 8192)
  expect_true(model$reasoning && model$tool_call)
  expect_identical(model$input, c("text", "image"))
  expect_true(all(unlist(model$prices[c("input", "output")]) == 0))
  classifier = gptr_fake_provider(list(0.9), name = "judge", type = "classifier")
  expect_identical(classifier$api, "fake-classifier")
  expect_identical(classifier$models[[1]]$ref, "judge/judge-s1")
  invalid = "gptr_error_invalid_argument"
  expect_error(gptr_fake_provider(list(), name = "Bad Name"), class = invalid)
  expect_error(gptr_fake_provider(42), class = invalid)
})

test_that("golden events: text", {
  expect_identical(digests(list(text = "Hello there", chunk = 6L)), c(
    r"(start fake fake fake-1)",
    r"(text_start 1)",
    r"(text_delta 1 "Hello ")",
    r"(text_delta 1 "there")",
    r"(text_end 1 "Hello there")",
    r"(done stop stop 1)"
  ))
})

test_that("golden events: thinking before text", {
  reply = list(thinking = "Plan first.", signature = "sig-1", text = "Answer.")
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(thinking_start 1)",
    r"(thinking_delta 1 "Plan first.")",
    r"(thinking_end 1 "Plan first." sig-1)",
    r"(text_start 2)",
    r"(text_delta 2 "Answer.")",
    r"(text_end 2 "Answer.")",
    r"(done stop stop 2)"
  ))
})

test_that("golden events: two parallel tool calls", {
  reply = list(tools = list(
    list(name = "read", input = list(path = "a.R")),
    list(name = "r", input = list(code = "1 + 1"))
  ))
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(toolcall_start 1 fake_1_1 read)",
    r"(toolcall_delta 1 "{\"path\"" {})",
    r"(toolcall_delta 1 ":\"a.R\"}" {"path":"a.R"})",
    r"(toolcall_end 1 fake_1_1 {"path":"a.R"} "{\"path\":\"a.R\"}")",
    r"(toolcall_start 2 fake_1_2 r)",
    r"(toolcall_delta 2 "{\"code\":" {})",
    r"(toolcall_delta 2 "\"1 + 1\"}" {"code":"1 + 1"})",
    r"(toolcall_end 2 fake_1_2 {"code":"1 + 1"} "{\"code\":\"1 + 1\"}")",
    r"(done tool_use tool_use 2)"
  ))
})

test_that("golden events: an error after two deltas carries the partial message", {
  reply = list(
    error = "overloaded", status = 529L, after = 2L, text = "partial answer here", chunk = 8L
  )
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(text_start 1)",
    r"(text_delta 1 "partial ")",
    r"(text_delta 1 "answer h")",
    r"(error error overloaded 529 "partial answer h" "overloaded")"
  ))
})

test_that("golden events: a truncated tool call stops with length", {
  reply = list(tool = "write", input = list(path = "out.R", content = "x = 1"), stop = "length")
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(toolcall_start 1 fake_1_1 write)",
    r"(toolcall_delta 1 "{\"path\":\"out.R\",\"" {"path":"out.R"})",
    r"(toolcall_end 1 fake_1_1 {"path":"out.R"} "{\"path\":\"out.R\",\"")",
    r"(done length length 1)"
  ))
})

test_that("the done message matches the accumulated events", {
  spec = gptr_fake_provider(list(
    list(text = "Checking.", tool = "r", input = list(code = "nrow(d)"))
  ))
  events = play_fake(spec)
  acc = acc_new()
  for (ev in events[-length(events)]) acc$push(ev)
  done = events[[length(events)]]
  partial = acc$message(stop_reason = "tool_use")
  expect_identical(lapply(partial$content, `[[`, "type"), list("text", "tool_call"))
  expect_identical(done$message$content[[2]]$arguments, list(code = "nrow(d)"))
  expect_identical(done$message$stop_reason, "tool_use")
  expect_true(all(vapply(done$message$content, block_ok, NA, msg_block_types[["assistant"]])))
  expect_true(done$usage$input > 0 && done$usage$output > 0)
})

test_that("scripts see the request, requests are logged and the last reply repeats", {
  seen = new.env()
  spec = gptr_fake_provider(function(request) {
    seen$request = request
    paste("You said:", request$last_user)
  })
  messages = list(
    msg_user("count rows"),
    msg_assistant(list(block_tool_call("c1", "r", list(code = "1"))), "fake", "fake", "fake-1",
                  stop_reason = "tool_use"),
    msg_tool_result("c1", "r", "1")
  )
  events = play_fake(spec, messages)
  expect_identical(msg_text(events[[length(events)]]$message), "You said: count rows")
  expect_identical(seen$request$n, 1L)
  expect_identical(seen$request$model, "fake/fake-1")
  expect_length(seen$request$last_results, 1L)
  expect_identical(spec$log$requests[[1]]$last_user, "count rows")
  looping = gptr_fake_provider(list("first", "last"))
  texts = vapply(1:3, function(i) msg_text(tail(play_fake(looping), 1)[[1]]$message), "")
  expect_identical(texts, c("first", "last", "last"))
})

test_that("json, overflow, missing scripts and failing script functions end cleanly", {
  events = play_fake(gptr_fake_provider(list(list(json = list(n = 3L)))))
  expect_identical(msg_text(events[[length(events)]]$message), "{\"n\":3}")
  events = play_fake(gptr_fake_provider(list(list(overflow = TRUE))))
  last = events[[length(events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "context_overflow")
  expect_identical(
    last$message$error_message, "prompt is too long: 201000 tokens > 200000 maximum"
  )
  events = play_fake(gptr_fake_provider(function(request) stop("script bug")))
  expect_match(events[[length(events)]]$message$error_message, "script bug", fixed = TRUE)
  model = list(api = "fake", provider = "no-such-fake", id = "x-1")
  gen = fake_stream(model, list(), list(signal = new.env()))
  step = gen()
  expect_identical(vapply(step$events, `[[`, "", "type"), c("start", "error"))
  expect_null(gen())
})

test_that("a model record without `fake` finds its live provider by name only", {
  spec = gptr_fake_provider(list("found by name"), name = "byname")
  model = spec$models[[1]]
  model$fake = NULL
  events = play_fake(list(models = list(model)))
  expect_identical(msg_text(events[[length(events)]]$message), "found by name")
  rm(spec)
  invisible(gc())
  events = play_fake(list(models = list(model)))
  expect_identical(events[[length(events)]]$type, "error")
})

test_that("delay and gap become waits between generator steps", {
  spec = gptr_fake_provider(list(list(text = "abcdef", chunk = 2L, delay = 0.5, gap = 0.25)))
  gen = fake_stream(spec$models[[1]], list(), list(signal = new.env()))
  first = gen()
  expect_length(first$events, 0L)
  expect_identical(first$wait, 0.5)
  second = gen()
  expect_identical(
    vapply(second$events, `[[`, "", "type"), c("start", "text_start", "text_delta")
  )
  expect_identical(second$wait, 0.25)
})

test_that("a hanging reply runs until the signal aborts it", {
  signal = new.env()
  signal$aborted = FALSE
  spec = gptr_fake_provider(list(list(hang = TRUE)))
  gen = fake_stream(spec$models[[1]], list(), list(signal = signal))
  expect_identical(gen()$events[[1]]$type, "start")
  for (i in 1:3) expect_length(gen()$events, 0L)
  signal$aborted = TRUE
  signal$reason = "user interrupt"
  last = gen()$events[[1]]
  expect_identical(last$type, "error")
  expect_identical(last$reason, "aborted")
  expect_identical(last$message$stop_reason, "aborted")
  expect_identical(last$message$error_message, "user interrupt")
  expect_null(gen())
})

test_that("the classifier fake returns canonical decisions (IC-74)", {
  spec = gptr_fake_provider(list(0.93, c(dog = 0.8, cat = 0.2), c(0.1, 0.2, 0.7)),
                            name = "judge", type = "classifier")
  questions = list(
    is_dog = list(type = "noul", instructions = "Is it a dog?",
                  criteria = list(`true` = "y", `false` = "n")),
    animal = list(type = "choice", instructions = "Which?",
                  criteria = list(dog = "A dog", cat = "A cat")),
    mood = list(type = "score", instructions = "How happy?",
                criteria = list("sad", "neutral", "happy"))
  )
  res = fake_classify(spec$models[[1]], list(text = "a puppy"), questions, list())
  expect_identical(res$model_version, "judge-s1-1.0")
  expect_identical(res$engine, "fake")
  expect_true(is.na(res$calibrated))
  expect_identical(res$answers$is_dog, list(type = "noul", prob = 0.93))
  expect_identical(res$answers$animal$choice, "dog")
  expect_identical(res$answers$animal$probabilities, c(dog = 0.8, cat = 0.2))
  expect_equal(res$answers$mood$score, 1.6)
  expect_identical(res$answers$mood$legend, c(`0` = "sad", `1` = "neutral", `2` = "happy"))
  expect_length(spec$log$requests, 3L)
  failing = gptr_fake_provider(list(list(error = "slow down", status = 429L)),
                               type = "classifier")
  cnd = fake_classify(failing$models[[1]], list(text = "x"), questions["is_dog"], list())
  expect_s3_class(cnd, c("gptr_error_s1_rate_limit", "gptr_error_s1"))
  expect_identical(cnd$status, 429L)
})

test_that("a chat request to the classifier adapter ends with one error event", {
  spec = gptr_fake_provider(list(0.5), name = "judge", type = "classifier")
  gen = fake_classifier_stream(spec$models[[1]], list(), list(signal = new.env()))
  events = gen()$events
  expect_identical(vapply(events, `[[`, "", "type"), c("start", "error"))
  expect_null(gen())
})

test_that("builtin_fake() registers the two adapters through the API object only", {
  api = new.env()
  api$specs = list()
  api$register_adapter = function(name, ...) {
    api$specs[[name]] = list(name = name, ...)
    invisible(NULL)
  }
  builtin_fake(api)
  expect_identical(names(api$specs), c("fake", "fake-classifier"))
  expect_identical(api$specs$fake$transport, "inprocess")
  expect_identical(api$specs$fake$stream, fake_stream)
  expect_identical(api$specs[["fake-classifier"]]$stream, fake_classifier_stream)
  expect_identical(api$specs[["fake-classifier"]]$classify$run, fake_classify)
})

test_that("undescribed choices keep the request order, including ties (D-077)", {
  spec = gptr_fake_provider(list(c(cat = 0.5, dog = 0.5)), type = "classifier")
  q = list(animal = list(type = "choice", criteria = list(dog = NULL, cat = NULL)))
  answer = fake_classify(spec$models[[1]], list(text = "pet"), q, list())$answers$animal
  expect_identical(answer$probabilities, c(dog = 0.5, cat = 0.5))
  expect_identical(answer$choice, "dog")
  expect_true(is.numeric(answer$confidence) && is.finite(answer$confidence))
})

test_that("invalid classifier probabilities are returned as typed errors", {
  noul = list(ok = list(type = "noul"))
  choice = list(pick = list(type = "choice", criteria = list(a = "a", b = "b")))
  score = list(level = list(type = "score", criteria = list("low", "high")))
  invalid = list(
    list(q = noul, x = numeric()), list(q = noul, x = c(0.2, 0.8)),
    list(q = noul, x = NA_real_), list(q = noul, x = Inf),
    list(q = noul, x = 1.2), list(q = noul, x = "0.9"),
    list(q = choice, x = c(a = 0.8, b = 0.3)),
    list(q = choice, x = c(a = -0.1, b = 1.1)),
    list(q = choice, x = c(a = 0.5, wrong = 0.5)),
    list(q = choice, x = c(a = 0.5, a = 0.5)),
    list(q = score, x = c(0.5, NaN)), list(q = score, x = c(1, 0, 0))
  )
  for (case in invalid) {
    spec = gptr_fake_provider(list(case$x), type = "classifier")
    result = fake_classify(spec$models[[1]], list(), case$q, list())
    expect_s3_class(result, c("gptr_error_s1_response", "gptr_error_s1"))
  }
})

test_that("pre-aborted chat streams never invoke the script", {
  signal = new.env()
  signal$aborted = TRUE
  signal$reason = "cancelled before start"
  spec = gptr_fake_provider(function(request) stop("must not run"))
  events = play_fake(spec, signal = signal)
  expect_identical(vapply(events, `[[`, "", "type"), c("start", "error"))
  expect_identical(events[[2]]$reason, "aborted")
  expect_length(spec$log$requests, 0L)
})

test_that("aborting during the initial delay still emits exactly one start", {
  signal = new.env()
  spec = gptr_fake_provider(list(list(text = "later", delay = 1)))
  gen = fake_stream(spec$models[[1]], list(), list(signal = signal))
  expect_length(gen()$events, 0L)
  signal$aborted = TRUE
  step = gen()
  expect_identical(vapply(step$events, `[[`, "", "type"), c("start", "error"))
  expect_identical(step$events[[2]]$message$provider, "fake")
  expect_null(gen())
})
test_that("the reply helpers build replies the fake provider plays (contract section 12.2)", {
  expect_identical(fake_text("hi", chunk = 1L), list(text = "hi", chunk = 1L))
  expect_identical(
    fake_tool("r", code = "1 + 1", .text = "Let me check."),
    list(tool = "r", input = list(code = "1 + 1"), text = "Let me check.")
  )
  expect_identical(fake_tool("ls")$input, json_obj())
  expect_identical(fake_tool("r", code = "x", .id = "call_9")$id, "call_9")
  expect_identical(
    fake_tools(list("read", list(path = "a.R")), list("ls")),
    list(tools = list(list(name = "read", input = list(path = "a.R")),
                      list(name = "ls", input = json_obj())))
  )
  expect_identical(fake_error(), list(error = "overloaded", status = 529L, after = 0L))
  spec = local_fake_provider(list(
    fake_tools(list("read", list(path = "a.R")), list("r", list(code = "1"))),
    fake_error("rate limited", status = 429L, after = 1L)
  ))
  types = vapply(play_fake(spec), `[[`, "", "type")
  expect_identical(types[length(types)], "done")
  expect_identical(sum(types == "toolcall_start"), 2L)
  last = play_fake(spec)
  expect_identical(last[[length(last)]]$error$class, "rate_limit")
  expect_length(fake_requests(spec), 2L)
})

test_that("local_project() makes a temporary project the working directory and root", {
  outer = getwd()
  local({
    root = local_project(files = list("R/analysis.R" = c("x = 1", "y = 2")))
    expect_identical(path_norm(getwd()), root)
    expect_identical(project_root(), root)
    expect_true(dir.exists(file.path(root, ".gptr", "sessions")))
    expect_true(dir.exists(file.path(root, ".gptr", "cache", "tmp")))
    expect_identical(workspace_dir(), file.path(root, ".gptr"))
    expect_identical(
      readLines(file.path(root, "R", "analysis.R"), encoding = "UTF-8"), c("x = 1", "y = 2")
    )
    bare = local_project(gptr = FALSE)
    expect_null(workspace_dir())
    expect_identical(project_root(), bare)
  })
  expect_identical(getwd(), outer)
})

test_that("local_project(trust = TRUE) records trust in the redirected user config", {
  root = local_project(trust = TRUE)
  file = file.path(tools::R_user_dir("gptr", "config"), "trust.json")
  expect_match(file, "gptr-tests-", fixed = TRUE)
  record = json_decode(readLines(file, encoding = "UTF-8"))
  expect_true(record$projects[[path_key(root)]]$trusted)
})

test_that("local_gptr_options() prefixes names and restores them", {
  local({
    local_gptr_options(out_keep = 3L, gptr.quiet = FALSE)
    expect_identical(getOption("gptr.out_keep"), 3L)
    expect_false(getOption("gptr.quiet"))
  })
  expect_null(getOption("gptr.out_keep"))
  expect_true(getOption("gptr.quiet"))
})

mock_handle = function(body, headers, timeout) {
  h = curl::new_handle()
  curl::handle_setopt(h, post = TRUE, postfields = body, followlocation = 0L, timeout = timeout,
                      pipewait = 0L, proxy = "")
  curl::handle_setheaders(h, .list = as.list(c(`content-type` = "application/json", headers)))
  h
}

mock_fetch = function(url, body = "{\"model\":\"mock-1\",\"messages\":[]}",
                      headers = c(`x-api-key` = "sk-test-NOT-A-REAL-KEY"), timeout = 30) {
  res = curl::curl_fetch_memory(url, handle = mock_handle(body, headers, timeout))
  res$text = rawToChar(res$content)
  res$header_list = curl::parse_headers_list(res$headers)
  res
}

count_events = function(text, event) {
  lengths(regmatches(text, gregexpr(paste0("event: ", event, "\n"), text, fixed = TRUE)))
}

test_that("the mock streams Anthropic SSE on token paths only and logs redacted requests", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  expect_true(srv$provider$offline)
  expect_identical(srv$provider$api, "anthropic-messages")
  expect_identical(srv$provider$base_url, srv$url)
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(res$status_code, 200L)
  expect_identical(res$header_list[["content-type"]], "text/event-stream")
  expect_identical(count_events(res$text, "content_block_delta"), 3L)
  expect_identical(count_events(res$text, "message_stop"), 1L)
  foreign = mock_fetch(sprintf("http://127.0.0.1:%d/v1/messages", srv$port))
  expect_identical(foreign$status_code, 404L)
  # The server logs the end of a request just after writing its last byte, so the client can
  # finish first: wait until both requests are logged as ended
  deadline = Sys.time() + 10
  while (anyNA(srv$log()$disconnected) && Sys.time() < deadline) Sys.sleep(0.05)
  log = srv$log()
  expect_identical(log$method, c("POST", "POST"))
  expect_identical(log$path, c("/v1/messages", "/v1/messages"))
  expect_match(log$headers[[1]], "x-api-key: [redacted]", fixed = TRUE)
  expect_false(any(grepl("NOT-A-REAL-KEY", unlist(log), fixed = TRUE)))
  expect_identical(log$body, c("{\"model\":\"mock-1\",\"messages\":[]}", ""))
  expect_identical(log$disconnected, c(FALSE, FALSE))
})

test_that("status, spend_cap and overload scenarios fail, then succeed when asked to", {
  srv = local_mock_server("status", status = 429L, retry_after = 2, succeed_after = 1)
  first = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(first$status_code, 429L)
  expect_identical(first$header_list[["retry-after"]], "2")
  expect_match(first$text, "rate_limit_error", fixed = TRUE)
  expect_identical(mock_fetch(paste0(srv$url, "/v1/messages"))$status_code, 200L)
  srv$stop()
  cap = local_mock_server("spend_cap")
  res = mock_fetch(paste0(cap$url, "/v1/messages"))
  expect_identical(res$status_code, 429L)
  expect_match(res$text, "enforced_spend_limit_reached", fixed = TRUE)
  expect_null(res$header_list[["retry-after"]])
  cap$stop()
  over = local_mock_server("overload", attempts = 1L)
  res = mock_fetch(paste0(over$url, "/v1/messages"))
  expect_identical(count_events(res$text, "error"), 1L)
  expect_identical(count_events(res$text, "content_block_delta"), 0L)
  res = mock_fetch(paste0(over$url, "/v1/messages"))
  expect_identical(count_events(res$text, "message_stop"), 1L)
})

test_that("a redirect points at a second origin that logs any key bytes it receives (IC-64)", {
  srv = local_mock_server("redirect")
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(res$status_code, 307L)
  location = res$header_list[["location"]]
  expect_match(location, "/redirected-to-second-origin$")
  expect_false(grepl(sprintf(":%d/", srv$port), location, fixed = TRUE))
  expect_identical(srv$log()$path, "/v1/messages")
  followed = mock_fetch(location, headers = character())
  expect_identical(followed$status_code, 200L)
  expect_identical(srv$log()$path, c("/v1/messages", "/redirected-to-second-origin"))
  # A client that carried the key across origins is caught: the second origin logs it raw
  leaked = mock_fetch(location)
  expect_identical(leaked$status_code, 200L)
  expect_match(srv$log()$headers[[3L]], "x-api-key: sk-test-NOT-A-REAL-KEY", fixed = TRUE)
  expect_match(srv$log()$headers[[1L]], "x-api-key: [redacted]", fixed = TRUE)
})

test_that("truncated, stalled and held streams end as the client sees them", {
  cut = local_mock_server("truncated", n = 2L)
  expect_error(mock_fetch(paste0(cut$url, "/v1/messages")))
  cut$stop()
  stall = local_mock_server("stall", n = 2L)
  expect_error(mock_fetch(paste0(stall$url, "/v1/messages"), timeout = 2))
  stall$stop()
  held = local_mock_server("hold_headers")
  expect_error(mock_fetch(paste0(held$url, "/v1/messages"), timeout = 1))
  deadline = Sys.time() + 10
  while (!isTRUE(held$log()$disconnected[1]) && Sys.time() < deadline) Sys.sleep(0.1)
  expect_true(held$log()$disconnected[1])
})

test_that("time-shaped scenarios delay the first byte or trickle bytes", {
  ttft = local_mock_server("ttft", delay = 1)
  started = Sys.time()
  res = mock_fetch(paste0(ttft$url, "/v1/messages"))
  expect_gte(as.numeric(Sys.time() - started, units = "secs"), 1)
  expect_identical(count_events(res$text, "message_stop"), 1L)
  ttft$stop()
  slow = local_mock_server("bytes_per_10s", duration = 2, every = 0.5)
  res = mock_fetch(paste0(slow$url, "/v1/messages"))
  expect_match(res$text, "^:\n:\n")
  expect_identical(count_events(res$text, "message_stop"), 1L)
})

test_that("parallel_tools answers tool calls first and text after tool results", {
  srv = local_mock_server("parallel_tools")
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_match(res$text, "\"name\":\"read\"", fixed = TRUE)
  expect_match(res$text, "\"name\":\"r\"", fixed = TRUE)
  expect_match(res$text, "\"stop_reason\":\"tool_use\"", fixed = TRUE)
  body = json_encode(list(model = "mock-1", messages = list(list(
    role = "user", content = list(list(type = "tool_result", tool_use_id = "toolu_A",
                                       content = "ok"))
  ))))
  res = mock_fetch(paste0(srv$url, "/v1/messages"), body = body)
  expect_match(res$text, "both done", fixed = TRUE)
})

test_that("OpenAI, Gemini, System 1 and JSON scenarios speak their wire shapes", {
  responses = local_mock_server("openai_responses", n = 2L)
  expect_identical(responses$provider$api, "openai-responses")
  text = mock_fetch(paste0(responses$url, "/responses"))$text
  expect_identical(count_events(text, "response.output_text.delta"), 2L)
  expect_identical(count_events(text, "response.completed"), 1L)
  responses$stop()
  chat = local_mock_server("chat_completions", n = 2L)
  text = mock_fetch(paste0(chat$url, "/chat/completions"))$text
  expect_match(text, "chat.completion.chunk", fixed = TRUE)
  expect_match(text, "data: [DONE]\n\n", fixed = TRUE)
  chat$stop()
  gemini = local_mock_server("gemini", n = 2L)
  text = mock_fetch(paste0(gemini$url, "/v1beta/models/m:streamGenerateContent?alt=sse"))$text
  expect_match(text, "\"finishReason\":\"STOP\"", fixed = TRUE)
  expect_match(gemini$log()$path, "streamGenerateContent", fixed = TRUE)
  gemini$stop()
  s1 = local_mock_server("systemone")
  expect_identical(s1$provider$type, "classifier")
  body = json_encode(list(model = "jev-latest", state = list(text = "a puppy"), questions = list(
    is_dog = list(type = "noul", instructions = "Dog?", criteria = list(true = "y", false = "n"))
  )))
  answer = json_decode(mock_fetch(paste0(s1$url, "/systemone"), body = body)$text)
  expect_identical(answer$answers$is_dog, list(type = "noul", noul = 0.9))
  s1$stop()
  custom = local_mock_server("systemone", answers = function(body) {
    list(is_dog = list(type = "noul", noul = 0.25))
  })
  answer = json_decode(mock_fetch(paste0(custom$url, "/systemone"), body = body)$text)
  expect_identical(answer$answers$is_dog$noul, 0.25)
  custom$stop()
  fixed = local_mock_server("json", body = "{\"ok\":true}", status = 201L)
  res = mock_fetch(paste0(fixed$url, "/anything"))
  expect_identical(res$status_code, 201L)
  expect_identical(res$text, "{\"ok\":true}")
})

test_that("concurrent streams are served in parallel, not one after another", {
  srv = local_mock_server("stream", n = 4L, interval = 1)
  pool = curl::new_pool()
  done = 0L
  for (i in 1:3) {
    curl::curl_fetch_multi(
      paste0(srv$url, "/v1/messages"), pool = pool,
      handle = mock_handle("{\"model\":\"mock-1\",\"messages\":[]}", character(), 30),
      done = function(res) done <<- done + 1L
    )
  }
  started = Sys.time()
  curl::multi_run(pool = pool)
  elapsed = as.numeric(Sys.time() - started, units = "secs")
  expect_identical(done, 3L)
  expect_lt(elapsed, 9)
})

test_that("mock requests bypass configured proxies for loopback only", {
  withr::local_envvar(
    http_proxy = "http://127.0.0.1:1", ALL_PROXY = "http://127.0.0.1:1",
    no_proxy = "", NO_PROXY = ""
  )
  srv = local_mock_server("json", body = "{}")
  expect_identical(mock_fetch(srv$url)$status_code, 200L)
  expect_identical(curl::curl_fetch_memory(srv$url)$status_code, 200L)
})

test_that("the mock skips a port another process holds on loopback", {
  skip_if_not_installed("httpuv")
  ports = port_candidates(20L)
  held = httpuv::startServer("127.0.0.1", ports[[1L]], list())
  withr::defer(httpuv::stopServer(held))
  local_mocked_bindings(port_candidates = function(n) ports)
  srv = local_mock_server("json", body = "{}")
  expect_false(srv$port == ports[[1L]])
  expect_identical(mock_fetch(srv$url)$status_code, 200L)
})

test_that("the mock child exits if its parent vanished before startup", {
  skip_on_cran()
  dir = withr::local_tempdir()
  config = list(
    ports = port_candidates(20L), token = id_new("", 24L), scenario = "json", args = list(),
    log = file.path(dir, "log.jsonl"), ready = file.path(dir, "ready.json"),
    parent_pid = .Machine$integer.max
  )
  config_file = file.path(dir, "config.rds")
  saveRDS(config, config_file)
  proc = processx::process$new(
    rscript_path(), c("--vanilla", test_path("fixtures", "mock_server.R"), config_file),
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)),
    stdout = file.path(dir, "stdout.txt"), stderr = file.path(dir, "stderr.txt"), cleanup = TRUE
  )
  withr::defer(if (proc$is_alive()) proc$kill())
  proc$wait(5000)
  expect_false(proc$is_alive())
})
