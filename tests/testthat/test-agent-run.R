source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- run records (04 section 7.6)

test_that("run_new() builds a queued gptr_run with the contract fields", {
  home = new.env()
  s = test_session(mode = "edits", home = home)
  run = run_new(s, list(agent = "main"), NULL)
  expect_s3_class(run, "gptr_run")
  expect_match(run$id, "^u[0-9a-f]{8}$")
  expect_identical(run$session, session_data(s)$id)
  expect_identical(run$status, "queued")
  expect_identical(run$turn, 0L)
  expect_identical(run$mode, "edits")
  expect_identical(run$depth, 0L)
  expect_null(run$parent_run)
  expect_identical(run$children, character())
  expect_false(run$signal$aborted)
  expect_s3_class(run$started, "POSIXct")
  expect_identical(run$max_turns, 50L)
  expect_identical(run_eval_env(run), home)
})

test_that("the safety options are snapshotted at the start of a root run (IC-53)", {
  local_gptr_options(noninteractive_ask = "deny", unsafe_no_permissions = FALSE)
  s = test_session()
  run = run_new(s, list(), NULL)
  options(gptr.noninteractive_ask = "stop", gptr.unsafe_no_permissions = TRUE)
  expect_identical(run$opts$safety$noninteractive_ask, "deny")
  expect_false(run$opts$safety$unsafe_no_permissions)
  expect_named(run$opts$safety, c("ui", "interactive", "critical_guard", "secret_guard",
                                  "noninteractive_ask", "protect_size", "mode",
                                  "unsafe_no_permissions", "can_prompt", "has_human"))
})

test_that("a nested run tightens the mode, inherits the snapshot and links to the outer run", {
  outer_s = test_session(mode = "manual")
  outer = run_new(outer_s, list(), NULL)
  child = test_session(mode = "auto", kind = "child", parent = outer_s)
  inner = run_new(child, list(), outer)
  expect_identical(inner$mode, "manual")
  expect_identical(inner$opts$safety, outer$opts$safety)
  expect_identical(inner$parent_run, outer$id)
  expect_identical(inner$depth, 1L)
  expect_true(session_data(child)$id %in% outer$children)
  expect_identical(run_mode_tighter("auto", "plan"), "plan")
})

test_that("plan mode evaluates in a scratch overlay of the home (IC-15)", {
  home = new.env()
  s = test_session(mode = "plan", home = home)
  run = run_new(s, list(), NULL)
  env = run_eval_env(run)
  expect_false(identical(env, home))
  expect_identical(parent.env(env), home)
  expect_null(run_eval_env(NULL))
})

test_that("the gateway's evaluation environment wins over the kept home (IC-40)", {
  home = new.env()
  frame = new.env()
  s = test_session(home = home)
  call = new.env()
  call$envir = frame
  expect_identical(run_eval_env(run_new(s, list(call = call), NULL)), frame)
})

test_that("run_current() finds the innermost frame that marks a running tool", {
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_current())
  inner = function() run_current()
  tool_frame = function() {
    .gptr_tool_run = run
    inner()
  }
  expect_identical(tool_frame(), run)
  expect_null(run_current())
})

test_that("run_emit() and session_emit() dispatch events with the section 4.5 fields", {
  s = test_session()
  sid = session_data(s)$id
  got = new.env()
  local_hook("turn_start", function(event, ctx) {
    got$ev = event
    got$ctx = ctx
    NULL
  }, session = sid)
  run = test_run(s, list(agent = "stats"))
  run_emit(run, "turn_start")
  expect_identical(got$ev$type, "turn_start")
  expect_identical(got$ev$session, sid)
  expect_identical(got$ev$run, run$id)
  expect_identical(got$ev$agent, "stats")
  expect_identical(got$ev$turn, 0L)
  expect_true(is.numeric(got$ev$ts))
  expect_identical(got$ctx, session_live(s)$ctx)
  session_emit(s, "turn_start")
  expect_identical(got$ev$run, run$id)
})

test_that("run_ui() is NULL without the ui.get service and the service's UI otherwise", {
  local_without_services("ui.get")
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_ui(run))
  local_service("ui.get", function(session = NULL) {
    list(name = "scripted", has_ui = function() TRUE)
  })
  expect_identical(run_ui(run)$name, "scripted")
})

test_that("interactive = FALSE in the run options means nobody can answer the run's gate", {
  local_gptr_options(interactive = TRUE)
  s = test_session()
  expect_true(run_new(s, list(), NULL)$opts$safety$can_prompt)
  expect_false(run_new(s, list(interactive = FALSE), NULL)$opts$safety$can_prompt)
})

# ---------------------------------------------------------------- additions to the plan's tests

test_that("session_emit() outside a run names no run and the main agent", {
  s = test_session()
  got = new.env()
  local_hook("turn_start", function(event, ctx) {
    got$ev = event
    NULL
  }, session = session_data(s)$id)
  session_emit(s, "turn_start")
  expect_null(got$ev$run)
  expect_identical(got$ev$agent, "main")
  expect_identical(got$ev$session, session_data(s)$id)
})

test_that("the agent-area accessors reach the run's session for the L2 dispatcher", {
  s = test_session()
  sid = session_data(s)$id
  run = run_new(s, list(), NULL)
  expect_identical(run_data(run), session_data(s))
  expect_identical(run_live(run), session_live(s))
  expect_identical(run_ctx(run), session_live(s)$ctx)
  expect_identical(run_ctx_sid(run_ctx(run)), sid)
  expect_null(run_ctx_sid(ctx_new(NULL)))
  id = run_append_message(run, msg_user("hello"))
  expect_match(id, "^[0-9a-f]{8}$")
  d = session_data(s)
  expect_identical(d$leaf, id)
  expect_identical(d$entries[[length(d$entries)]]$message$role, "user")
  cid = run_append_custom(run, "gptr.budget", list(kind = "cost", budget = 5, used = 6))
  e = d$entries[[length(d$entries)]]
  expect_identical(d$leaf, cid)
  expect_identical(e$custom_type, "gptr.budget")
  expect_identical(e$data$kind, "cost")
})

# ---------------------------------------------------------------- report 02 section 5.3 (26 checks)

recovery_recs = oracle("recovery")
err_msg = function(text, provider = "x", stop = "error", usage = list()) {
  list(role = "assistant", stop_reason = stop, error_message = text, provider = provider,
       usage = usage)
}

test_that(oracle_title(recovery_recs, "R01"), {
  ex = unlist(recovery_recs$R01$data)
  expect_length(ex, 21L)
  expect_true(all(vapply(ex, function(e) is_context_overflow(err_msg(e)), NA)))
})

test_that(oracle_title(recovery_recs, "R02"), {
  expect_false(is_context_overflow(err_msg(
    "ThrottlingException: Too many tokens, please wait before trying again. rate limit")))
})

test_that(oracle_title(recovery_recs, "R03"), {
  expect_true(is_context_overflow(err_msg("400 status code (no body)", "cerebras")))
  expect_false(is_context_overflow(err_msg("400 status code (no body)", "openai")))
})

test_that(oracle_title(recovery_recs, "R04"), {
  m = list(role = "assistant", stop_reason = "stop",
           usage = list(input = 190000, cache_read = 20000, output = 5))
  expect_true(is_context_overflow(m, 200000))
  expect_false(is_context_overflow(m, 300000))
})

test_that(oracle_title(recovery_recs, "R05"), {
  m = list(role = "assistant", stop_reason = "length",
           usage = list(input = 199000, cache_read = 0, output = 0))
  expect_true(is_context_overflow(m, 200000))
})

test_that(oracle_title(recovery_recs, "R06"), {
  m = json_decode(paste0('{"role":"assistant","stop_reason":"length",',
                         '"usage":{"input":199000,"cache_read":0,"output":0}}'))
  expect_true(is.integer(m$usage$output))
  expect_true(is_context_overflow(m, 200000))
})

test_that(oracle_title(recovery_recs, "R07"), {
  expect_true(run_retryable(err_msg("529 overloaded"), list(status = 529L)))
  expect_true(run_retryable(err_msg("Error: fetch failed"), list()))
  expect_true(run_retryable(err_msg("Connection timed out after 10001 milliseconds"), list()))
  expect_true(run_retryable(err_msg("idle"), list(class = "gptr_error_timeout_idle")))
})

test_that(oracle_title(recovery_recs, "R08"), {
  expect_false(run_retryable(err_msg("insufficient_quota: You exceeded your current quota"),
                             list()))
  expect_false(run_retryable(err_msg("insufficient_quota"), list(status = 429L)))
  expect_false(run_retryable(err_msg("spend limit reached"), list(class = "gptr_error_spend_cap")))
  expect_false(retryable_error_text("429 billing hard limit reached"))
})

test_that(oracle_title(recovery_recs, "R09"), {
  expect_false(run_retryable(err_msg("invalid x-api-key"), list(status = 401L)))
  expect_identical(provider_classes(list(status = 401L)), c("auth", "provider"))
})

test_that(oracle_title(recovery_recs, "R10"), {
  expect_identical(vapply(1:2, agent_retry_delay, 1), c(2, 4))
})

test_that(oracle_title(recovery_recs, "R11"), {
  a = retry_classify(429L, list(`retry-after-ms` = "1500"))
  b = retry_classify(429L, list(`retry-after` = "7"))
  expect_true(a$retry && b$retry)
  expect_equal(a$delay, 1.5)
  expect_equal(b$delay, 7)
})

test_that(oracle_title(recovery_recs, "R12"), {
  x = retry_classify(429L, list(`retry-after` = "120"))
  expect_false(x$retry)
  expect_true("retry_after" %in% x$class)
})

test_that(oracle_title(recovery_recs, "R13"), {
  x = retry_classify(503L, list())
  expect_true(x$retry)
  expect_true(is.null(x$delay) || x$delay <= 8)
})

test_that(oracle_title(recovery_recs, "R14"), {
  lt = as.POSIXlt(Sys.time() + 5, tz = "GMT")
  days = c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
  hd = sprintf("%s, %02d %s %d %02d:%02d:%02d GMT", days[lt$wday + 1L], lt$mday,
               month.abb[lt$mon + 1L], lt$year + 1900L, lt$hour, lt$min, as.integer(lt$sec))
  x = retry_classify(429L, list(`retry-after` = hd))
  expect_true(x$retry)
  expect_true(x$delay > 3 && x$delay <= 5)
  expect_true(retry_classify(429L, list(`retry-after` = "soon"))$retry)
})

test_that(oracle_title(recovery_recs, "R15"), {
  for (st in c(408L, 409L, 429L, 500L, 503L, 529L)) expect_true(retry_classify(st, list())$retry)
  for (st in c(400L, 401L, 403L)) expect_false(retry_classify(st, list())$retry)
})

test_that(oracle_title(recovery_recs, "R16"), {
  s = projection_session()
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(vapply(pr, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "tool_result", "user"))
})

test_that(oracle_title(recovery_recs, "R17"), {
  s = projection_session()
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(pr[[4L]]$tool_call_id, "c2")
  expect_true(pr[[4L]]$is_error)
})

test_that(oracle_title(recovery_recs, "R18"), {
  local_fake_provider(list("x"))
  s = test_session()
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant(list(block_tool_call("c1", "read",
                                                                     list(path = "a"))),
                                                api = "fake", provider = "fake", model = "fake-1",
                                                stop_reason = "tool_use")))
  relay = "The user sent this message while you were working: x"
  session_append(s, entry_message(msg_operator("steer_relay", relay)))
  session_append(s, entry_message(msg_tool_result("c1", "read", "ok")))
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(vapply(pr, function(m) m$role, ""), c("user", "assistant", "tool_result",
                                                         "operator"))
})

# ------------------------------------------------------- additions to the plan's tests (Task 8)

test_that("unknown usage never proves a silent overflow; known counts are a lower bound (IC-74)", {
  reply = function(stop, ...) list(role = "assistant", stop_reason = stop, usage = list(...))
  expect_false(is_context_overflow(reply("stop", input = NA_real_, cache_read = NA_real_,
                                         output = 5), 200000))
  expect_true(is_context_overflow(reply("stop", input = 210000, cache_read = NA_real_,
                                        output = 5), 200000))
  expect_false(is_context_overflow(reply("stop", input = 150000, cache_read = NA_real_,
                                         output = 5), 200000))
  expect_false(is_context_overflow(reply("length", input = 199000, cache_read = 0,
                                         output = NA_real_), 200000))
  expect_false(is_context_overflow(reply("length", input = NA_real_, cache_read = 0,
                                         output = 0), 200000))
  expect_true(is_context_overflow(reply("length", input = 199000, cache_read = NA_real_,
                                        output = 0), 200000))
  # An explicit null is unknown, a left-out field keeps P05's legacy zero (usage_from_json())
  decoded = json_decode(paste0('{"role":"assistant","stop_reason":"length",',
                               '"usage":{"input":199000,"cache_read":0,"output":null}}'))
  expect_true("output" %in% names(decoded$usage))
  expect_false(is_context_overflow(decoded, 200000))
  expect_false(is_context_overflow(reply("length", input = 199000, cache_read = 0,
                                         output = NULL), 200000))
  decoded$usage[["output"]] = NULL
  expect_true(is_context_overflow(decoded, 200000))
  # P05's record of an unreported usage: every counter and the cost unknown
  unreported = msg_assistant("x", api = "fake", provider = "fake", model = "fake-1",
                             usage = usage_as(NULL))
  expect_false(is_context_overflow(unreported, 200000))
  unreported$stop_reason = "length"
  expect_false(is_context_overflow(unreported, 200000))
})

test_that("an estimated usage proves no silent overflow", {
  m = list(role = "assistant", stop_reason = "stop",
           usage = usage_new(input = 300000, output = 5, estimated = TRUE))
  expect_false(is_context_overflow(m, 200000))
  m$usage$estimated = FALSE
  expect_true(is_context_overflow(m, 200000))
  m = list(role = "assistant", stop_reason = "length",
           usage = usage_new(input = 199500, output = 0, estimated = TRUE))
  expect_false(is_context_overflow(m, 200000))
})

test_that("the recovery classifier never throws on malformed records", {
  msgs = list(NULL, "text", list(stop_reason = "error", error_message = c("a", "b")),
              list(stop_reason = "error", error_message = NA_character_),
              list(stop_reason = "error", error_message = 1),
              list(stop_reason = "stop", usage = 5),
              list(stop_reason = "stop", usage = list(input = "300000")),
              list(stop_reason = "stop", usage = list(input = c(300000, 1))))
  for (m in msgs) {
    expect_false(is_context_overflow(m, 200000))
    expect_false(run_retryable(m, list()))
  }
  m = list(stop_reason = "stop", usage = list(input = 300000))
  for (w in list(NULL, NA, c(1, 2), "abc", -1, Inf, list(200000))) {
    expect_false(is_context_overflow(m, w))
  }
  expect_true(is_context_overflow(m, 200000L))
  errs = list(NULL, "overloaded", 5, list(class = NA_character_), list(class = ""),
              list(status = c(500L, 501L)), list(status = "abc"), list(status = sum))
  for (e in errs) {
    expect_identical(err_class(e), NA_character_)
    expect_identical(provider_classes(e), "provider")
    expect_false(is_context_overflow(err_msg("overloaded"), NULL, e))
  }
  expect_false(retryable_error_text(NA_character_))
  expect_false(retryable_error_text(c("overloaded", "overloaded")))
  expect_false(retryable_error_text(1))
})

test_that("an overflow is never retried, whatever its status says", {
  expect_false(run_retryable(err_msg("429 too many tokens in the prompt"), list(status = 429L)))
  expect_false(run_retryable(err_msg("prompt is too long: 213462 tokens > 200000 maximum"),
                             list(status = 500L)))
  expect_false(run_retryable(err_msg("overloaded"), list(class = "context_overflow")))
  expect_true(run_retryable(err_msg("Too many tokens, rate limit reached"), list(status = 429L)))
})

test_that("gptr's own definitive failures are never retried, whatever their text says", {
  for (cls in c("no_key", "not_available", "untrusted", "invalid_argument", "invalid_spec",
                "missing_package")) {
    err = list(class = cls, status = NA_integer_, request_id = "q000000000001")
    expect_false(run_retryable(err_msg("`timeout` must be a number, not a character"), err))
  }
  # P05's stream-level failures keep the text rule of report 02
  expect_true(run_retryable(err_msg("The stream ended without a terminal event."),
                            list(class = "internal")))
  expect_false(run_retryable(err_msg("The inprocess generator returned a malformed step."),
                             list(class = "internal")))
})

test_that("the fake provider's terminal error records classify as the contract says", {
  spec = gptr_fake_provider(list(list(overflow = TRUE), fake_error("overloaded", 529L),
                                 fake_error("invalid x-api-key", 401L),
                                 fake_error("insufficient_quota", 429L)))
  terminal = function() {
    gen = fake_stream(spec$models[[1L]], list(messages = list(msg_user("hi")),
                                              request_id = "q000000000001"),
                      list(signal = new.env()))
    last = NULL
    for (i in seq_len(100L)) {
      step = gen()
      if (is.null(step)) break
      if (length(step$events)) last = step$events[[length(step$events)]]
    }
    last
  }
  ev = terminal()
  expect_identical(ev$type, "error")
  expect_true(is_context_overflow(ev$message, 200000, ev$error))
  expect_false(run_retryable(ev$message, ev$error))
  expect_identical(provider_classes(ev$error), c("context_overflow", "provider"))
  ev = terminal()
  expect_false(is_context_overflow(ev$message, 200000, ev$error))
  expect_true(run_retryable(ev$message, ev$error))
  expect_identical(provider_classes(ev$error), c("overloaded", "provider"))
  ev = terminal()
  expect_false(run_retryable(ev$message, ev$error))
  expect_identical(provider_classes(ev$error), c("auth", "provider"))
  ev = terminal()
  expect_false(run_retryable(ev$message, ev$error))
  expect_identical(provider_classes(ev$error), c("rate_limit", "provider"))
})

test_that("agent_retry_delay() keeps the second delay and refuses a bad attempt", {
  expect_identical(agent_retry_delay(3L), 4)
  for (a in list(0L, 1.5, NA_integer_, "1", c(1L, 2L), NULL)) {
    expect_error(agent_retry_delay(a), class = "gptr_error_invalid_argument")
  }
})

# ---------------------------------------------------------------- request shaping

test_that("the fallback freeze appends gptr.frozen and emits session_start (reason new)", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_tool("read", function(input, ctx) "x",
             parameters = list(type = "object", properties = list(path = list(type = "string"))))
  ev = local_events("session_start")
  s = test_session()
  run = test_run(s)
  input = run_freeze(run, list(msg_user("hi")))
  d = session_data(s)
  expect_identical(d$entries[[1L]]$custom_type, "gptr.frozen")
  expect_named(d$frozen, c("t0", "t1", "tools_json", "tool_names", "sections"))
  expect_identical(d$frozen$tool_names, "read")
  expect_match(d$frozen$tools_json, "\"input_schema\"", fixed = TRUE)
  expect_identical(ev(s)[[1L]]$reason, "new")
  expect_identical(input[[1L]]$content[[1L]]$text, "hi")
  n = length(d$entries)
  run_freeze(run, list(msg_user("again")))
  expect_length(d$entries, n)
})

test_that("session_start blocks join the first user message; the prompt.freeze service is used", {
  local_hook("session_start", function(event, ctx) {
    list(blocks = list(block_context("lab_notebook", "Experiment 12")))
  })
  got = new.env()
  local_service("prompt.freeze", function(s, opts) {
    got$opts = opts
    d = session_data(s)
    d$frozen = list(t0 = "T0", t1 = "T1", tools_json = "[]", tool_names = character(),
                    sections = frozen_sections_df(list()))
    invisible(d$frozen)
  })
  s = test_session()
  run = test_run(s)
  lead = block_context("environment", "Date: today")
  input = run_freeze(run, list(msg_user(list(lead, block_text("hi")))))
  kinds = vapply(input[[1L]]$content, function(b) b$kind %||% b$type, "")
  expect_identical(kinds, c("environment", "lab_notebook", "text"))
  expect_identical(session_data(s)$frozen$t0, "T0")
  expect_identical(got$opts$start$blocks[[1L]]$kind, "lab_notebook")
})

test_that("session_start reasons follow the session's origin", {
  expect_identical(session_start_reason(list(kind = "chat", entries = list())), "new")
  expect_identical(session_start_reason(list(kind = "child", entries = list())), "child")
  expect_identical(session_start_reason(list(kind = "replayed", entries = list())), "replay")
  expect_identical(session_start_reason(list(kind = "chat", entries = list(1), fork_of = NULL)),
                   "resume")
  expect_identical(session_start_reason(list(kind = "chat", fork_of = list(id = "s1"))), "fork")
})

test_that("run_target() resolves the model once and applies a pending ctx$set_model() switch", {
  local_fake_provider(list("x"))
  local_fake_provider(list("y"), name = "other")
  s = test_session()
  run = test_run(s)
  expect_identical(run_target(run)$ref, "fake/fake-1")
  run$pending_model = list(ref = "other/other-1", thinking = "high", reason = "plugin")
  rec = run_target(run)
  expect_identical(rec$ref, "other/other-1")
  expect_identical(rec$thinking, "high")
  expect_identical(s$model, "other/other-1")
  d = session_data(s)
  expect_identical(d$entries[[length(d$entries)]]$gptr$reason, "plugin")
})

test_that("run_target() resolves a provider registered for the session only (model = <spec>)", {
  s = test_session()
  d = session_data(s)
  spec = gptr_provider("loc", api = "fake", models = list(list(id = "m0"), list(id = "m1")),
                       offline = TRUE)
  id = registry_add(spec, source = "session", rank = 0L, session = d$id)
  withr::defer(registry_remove(id))
  expect_null(model_resolve("loc/m1", strict = FALSE))
  d$model = "loc/m1"
  run = test_run(s)
  rec = run_target(run)
  expect_identical(c(rec$provider, rec$id, rec$ref), c("loc", "m1", "loc/m1"))
  d$model = "loc/absent"
  expect_error(run_target(run), class = "gptr_error_unknown_model")
})

test_that("a router session asks router.call before each request and records each switch (IC-69)", {
  local_fake_provider(list("x"))
  calls = new.env()
  calls$reasons = character()
  local_service("router.call", function(s, reason) {
    calls$reasons = c(calls$reasons, reason)
    list(model = "fake/fake-1", thinking = NULL, state = list(k = 1))
  })
  ev = local_events("route")
  s = session_new("router:cheapest", "auto", home = new.env())
  run = test_run(s)
  expect_identical(run_target(run)$ref, "fake/fake-1")
  expect_identical(run_target(run)$ref, "fake/fake-1")
  expect_identical(calls$reasons, c("turn", "turn"))
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
  expect_identical(types, c("model_change", "gptr.router"))
  router = session_data(s)$entries[[2L]]$data
  expect_identical(router$router, "cheapest")
  expect_identical(router$state, list(k = 1))
  expect_length(ev(s), 1L)
})

test_that("a failing router falls back to the default model with a diagnostic", {
  local_fake_provider(list("x"))
  local_service("router.call", function(s, reason) stop("router crashed"))
  testthat::local_mocked_bindings(model_default = function(role = "chat") "fake/fake-1")
  s = session_new("router:cheapest", "auto", home = new.env())
  expect_identical(run_route(test_run(s), "turn")$ref, "fake/fake-1")
})

test_that("the fallback request projects the transcript and carries the frozen tools", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_fake_provider(list("x"))
  local_tool("read", function(input, ctx) "x")
  s = test_session()
  run = test_run(s, list(returns = list(type = "object")))
  freeze_fallback(s)
  session_append(s, entry_message(msg_user("What is in a.R?")))
  req = run_build(run, run_target(run))
  ctx = req$context
  expect_named(ctx$system, c("t0", "t1"))
  expect_s3_class(ctx$tools_json, "json")
  expect_identical(vapply(ctx$tools, function(t) t$name, ""), "read")
  expect_identical(vapply(ctx$messages, function(m) m$role, ""), "user")
  expect_match(ctx$request_id, "^q[0-9a-f]{12}$")
  expect_identical(ctx$params$returns, list(type = "object"))
  expect_gt(req$tokens_est, 0)
  expect_true(all(c("tools", "transcript") %in% names(req$components)))
})

test_that("request_params handlers patch only the adapter's declared fields (IC-69)", {
  testthat::local_mocked_bindings(adapter_get = function(api) {
    list(api = api, capabilities = list(request_params = "service_tier"))
  })
  local_hook("request_params", function(event, ctx) {
    list(params = list(service_tier = "priority", max_tokens = 5L))
  })
  run = test_run(test_session())
  out = run_request_params(run, list(api = "fake", provider = "fake", ref = "fake/fake-1"),
                           list(max_tokens = 100L, service_tier = "auto"))
  expect_identical(out$service_tier, "priority")
  expect_identical(out$max_tokens, 100L)
})

test_that("older images are elided above the model's image limit, once (IC-67)", {
  s = test_session()
  img = function(k) block_image(strrep(as.character(k), 40))
  msgs = list(msg_user(list(img(1), img(2), img(3), block_text("look"))))
  out = images_elide(s, msgs, list(max_images = 2))
  expect_match(out[[1L]]$content[[1L]]$text, "^\\[image omitted: gptr\\$plot\\(")
  expect_identical(out[[1L]]$content[[2L]]$type, "image")
  d = session_data(s)
  expect_identical(d$entries[[length(d$entries)]]$custom_type, "gptr.image_elision")
  n = length(d$entries)
  again = images_elide(s, msgs, list(max_images = 2))
  expect_length(d$entries, n)
  expect_match(again[[1L]]$content[[1L]]$text, "image omitted", fixed = TRUE)
})

test_that("returns = <schema> designates the parsed final answer; a mismatch is a notice", {
  s = test_session()
  run = test_run(s, list(returns = list(type = "object", required = I("n"),
                                        properties = list(n = list(type = "integer")))))
  d = session_data(s)
  d$last_text = "{\"n\": 32}"
  run_returns(run)
  expect_identical(s$value$n, 32L)
  d$last_text = "no JSON here"
  withr::local_options(gptr.quiet = FALSE)
  expect_message(run_returns(run), class = "gptr_message_notice")
})

test_that("JSON-able plugin state is persisted as a gptr.ext entry when it changed", {
  s = test_session()
  st = new.env()
  st$count = 1L
  assign("panel", st, envir = session_live(s)$ext)
  plugin_state_persist(s)
  plugin_state_persist(s)
  ext = Filter(function(e) identical(e$custom_type, "gptr.ext"), session_data(s)$entries)
  expect_length(ext, 1L)
  expect_identical(ext[[1L]]$data, list(plugin = "panel", state = list(count = 1L)))
  expect_identical(s$ext$panel$count, 1L)
})

test_that("the estimator multiplier follows reported usage (03 section 12.5)", {
  s = test_session()
  run = test_run(s)
  run$model = list(provider = "anthropic")
  run$tokens_est = 1000
  run_estimator_update(run, list(usage = usage_new(input = 1500, output = 10)))
  st = session_data(s)$estimator
  expect_gt(st$m, 1)
  expect_identical(st$n, 1L)
})

test_that("context_tokens() is the last reported total plus the multiplier times new content", {
  s = test_session()
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 500, output = 20))))
  expect_equal(context_tokens(s), 520)
  session_append(s, entry_message(msg_user(strrep("x", 400))))
  expect_equal(context_tokens(s), 520 + est_tokens(strrep("x", 400), "prose"))
  expect_gte(context_idle(s), 0)
})

# ---------------------------------------------------- request shaping: IC-67, IC-69, IC-74

test_that("a colon tag is part of a session model id; a suffix is thinking only when known", {
  s = test_session()
  d = session_data(s)
  spec = gptr_provider("loc", api = "fake",
                       models = list(list(id = "qwen3:8b"), list(id = "m1", reasoning = TRUE)),
                       offline = TRUE)
  id = registry_add(spec, source = "session", rank = 0L, session = d$id)
  withr::defer(registry_remove(id))
  run = test_run(s)
  d$model = "loc/qwen3:8b"
  rec = run_target(run)
  expect_identical(c(rec$id, rec$ref), c("qwen3:8b", "loc/qwen3:8b"))
  d$model = "loc/m1:high"
  rec = run_target(run)
  expect_identical(c(rec$id, rec$thinking), c("m1", "high"))
  d$model = "loc/m1:8b"
  expect_error(run_target(run), class = "gptr_error_unknown_model")
})

test_that("run_target() refuses a decision-only model before any request (IC-74)", {
  local_fake_provider(list("x"), name = "judge", type = "classifier")
  s = test_session(model = "judge/judge-s1")
  run = test_run(s)
  expect_error(run_target(run), class = "gptr_error_not_available")
  expect_null(run$model)
})

test_that("an unusable router answer falls back to the default chat model (IC-69, IC-74)", {
  local_fake_provider(list("x"))
  local_fake_provider(list("y"), name = "other")
  local_fake_provider(list("z"), name = "judge", type = "classifier")
  answers = list(list(model = "other/other-1", state = list(k = 1)), "judge/judge-s1",
                 "nowhere/absent", list(model = 42),
                 list(model = "other/other-1", state = new.env()))
  k = new.env()
  k$i = 0L
  local_service("router.call", function(s, reason) {
    k$i = k$i + 1L
    answers[[k$i]]
  })
  testthat::local_mocked_bindings(model_default = function(role = "chat") "fake/fake-1")
  ev = local_events("route")
  s = session_new("router:cheapest", "auto", home = new.env())
  run = test_run(s)
  refs = vapply(1:5, function(i) run_target(run)$ref, "")
  expect_identical(refs, c("other/other-1", rep("fake/fake-1", 3L), "other/other-1"))
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 4L)
  expect_identical(diag$class, c(rep("router_fallback", 3L), "router_state"))
  expect_match(diag$message[[1L]], "decision-only", fixed = TRUE)
  expect_match(diag$message[[2L]], "nowhere/absent", fixed = TRUE)
  ents = session_data(s)$entries
  types = vapply(ents, function(e) e$custom_type %||% e$type, "")
  expect_identical(types, rep(c("model_change", "gptr.router"), 3L))
  # the fallback switch keeps the router's last state; a state that is not JSON is dropped
  expect_identical(ents[[4L]]$data$state, list(k = 1))
  expect_null(ents[[6L]]$data$state)
  expect_identical(vapply(ev(s), function(e) e$model, ""),
                   c("other/other-1", "fake/fake-1", "other/other-1"))
})

test_that("a router fallback refuses a decision-only default model (IC-74)", {
  local_fake_provider(list("z"), name = "judge", type = "classifier")
  local_service("router.call", function(s, reason) stop("router crashed"))
  testthat::local_mocked_bindings(model_default = function(role = "chat") "judge/judge-s1")
  s = session_new("router:cheapest", "auto", home = new.env())
  run = test_run(s)
  expect_error(run_target(run), class = "gptr_error_not_available")
  expect_length(session_data(s)$entries, 0L)
  expect_null(run$model)
})

test_that("a router switch is recorded against the branch's last model, also across runs", {
  local_fake_provider(list("x"))
  local_fake_provider(list("y"), name = "other")
  pick = new.env()
  pick$model = "fake/fake-1"
  local_service("router.call", function(s, reason) {
    list(model = pick$model, state = list(m = pick$model))
  })
  s = session_new("router:cheapest", "auto", home = new.env())
  types = function() vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
  run_target(test_run(s))
  run_target(test_run(s))
  expect_identical(types(), c("model_change", "gptr.router"))
  pick$model = "other/other-1"
  expect_identical(run_target(test_run(s))$ref, "other/other-1")
  expect_identical(types(), rep(c("model_change", "gptr.router"), 2L))
  expect_identical(session_data(s)$entries[[4L]]$data$state, list(m = "other/other-1"))
  expect_identical(s$model, "router:cheapest")
})

test_that("router and ctx$set_model() thinking levels are clamped to the model's levels", {
  local_fake_provider(list("x"))
  local_service("router.call", function(s, reason) list(model = "fake/fake-1", thinking = "max"))
  s = session_new("router:cheapest", "auto", home = new.env())
  expect_identical(run_target(test_run(s))$thinking, "high")
  s2 = test_session()
  run = test_run(s2)
  run$pending_model = list(ref = "fake/fake-1", thinking = "xhigh", reason = "plugin")
  expect_identical(run_target(run)$thinking, "high")
})

test_that("the fallback freeze evaluates function parameters and available() (04 section 9.1)", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  seen = new.env()
  local_tool("read", function(input, ctx) "x", parameters = function(ctx) {
    seen$ctx = ctx
    list(type = "object", properties = list(path = list(type = "string")))
  })
  off = gptr_register(gptr_tool("edit", "Test tool edit", execute = function(input, ctx) "x",
                                available = function(ctx) FALSE))
  withr::defer(off())
  off2 = gptr_register(gptr_tool("write", "Test tool write", execute = function(input, ctx) "x",
                                 parameters = function(ctx) stop("no schema")))
  withr::defer(off2())
  s = test_session()
  fr = freeze_fallback(s)
  expect_identical(fr$tool_names, "read")
  arr = json_decode(fr$tools_json)
  expect_identical(arr[[1L]]$input_schema$properties$path$type, "string")
  expect_s3_class(seen$ctx, "gptr_ctx")
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 1L)
  expect_match(diag$message, "write", fixed = TRUE)
})

test_that("an elided image is elided in every copy at once (IC-67)", {
  s = test_session()
  img = function(k) block_image(strrep(as.character(k), 40))
  msgs = list(msg_user(list(img(1), block_text("a"))),
              msg_user(list(img(2), img(1), block_text("b"))))
  out = images_elide(s, msgs, list(max_images = 2))
  types = vapply(c(out[[1L]]$content, out[[2L]]$content), function(b) b$type, "")
  expect_identical(types, c("text", "text", "image", "text", "text"))
  d = session_data(s)
  el = d$entries[[length(d$entries)]]
  expect_identical(as.character(unlist(el$data$images)),
                   substr(hash_sha256(strrep("1", 40)), 1L, 8L))
  expect_identical(images_elide(s, msgs, list(max_images = 2)), out)
})

test_that("the fallback request and the context projection count elided images as omitted", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_fake_provider(list("x"))
  s = test_session()
  run = test_run(s)
  freeze_fallback(s)
  img = function(k) block_image(strrep(as.character(k), 40))
  session_append(s, entry_message(msg_user(list(img(1), img(2), img(3), img(4),
                                                block_text("look")))))
  target = run_target(run)
  target$max_images = 1
  req = run_build(run, target)
  sent = req$context$messages
  expect_identical(vapply(sent[[1L]]$content, function(b) b$type, ""),
                   c("text", "text", "text", "image", "text"))
  transcript = sum(vapply(sent, msg_tokens_est, 1))
  expect_equal(req$components$transcript, transcript)
  expect_equal(req$tokens_est, frozen_tokens(session_data(s)$frozen) + transcript)
  # no reported total yet: the projection estimates the same elided messages
  expect_equal(context_tokens(s), req$tokens_est)
})

test_that("context_tokens() anchors on provider-reported totals only and counts every block", {
  s = test_session()
  d = session_data(s)
  t0 = strrep("system ", 50)
  d$frozen = list(t0 = t0, t1 = "", tools_json = "[]", tool_names = character(),
                  sections = frozen_sections_df(list()))
  static = est_tokens(t0, "prose") + est_tokens("[]", "json")
  env = block_context("environment", strrep("env ", 100))
  session_append(s, entry_message(msg_user(list(env, block_text("q")))))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1", usage = usage_as(NULL))))
  est = static + est_tokens(env$text, "prose") + est_tokens("q", "prose") +
    est_tokens("a", "prose")
  expect_equal(context_tokens(s), est)
  session_append(s, entry_message(msg_assistant("b", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 9999, output = 1,
                                                                  estimated = TRUE))))
  expect_equal(context_tokens(s), est + est_tokens("b", "prose"))
  session_append(s, entry_message(msg_assistant("c", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 500, output = 20))))
  kept = session_append(s, entry_message(msg_user(list(block_image(strrep("A", 40)),
                                                       block_text("plot")))))
  call = block_tool_call("c1", "r", list(code = "x = 1"))
  session_append(s, entry_message(msg_assistant(list(call), api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "tool_use")))
  tail = est_image_tokens(1000, 700) + est_tokens("plot", "prose") +
    est_tokens(json_encode(list(code = "x = 1")), "json")
  expect_equal(context_tokens(s), 520 + tail)
  summary = block_context("checkpoint", "short")
  session_append(s, list(type = "compaction", summary = "short", first_kept_entry_id = kept,
                         tokens_before = 600,
                         gptr = list(blocks = list(summary), state = list(), n = 1L)))
  expect_equal(context_tokens(s), static + est_tokens(summary$text, "prose") + tail)
})

test_that("an unknown prompt count leaves the estimator unchanged (IC-74)", {
  s = test_session()
  run = test_run(s)
  run$model = list(provider = "anthropic")
  run$tokens_est = 1000
  run_estimator_update(run, list(usage = usage_new(input = NA_real_, output = 10)))
  run_estimator_update(run, list(usage = usage_as(NULL)))
  run_estimator_update(run, list(usage = usage_new(input = 1500, cache_read = NA_real_,
                                                   output = 10)))
  expect_null(session_data(s)$estimator)
})

test_that("plugin state emptied after it was persisted is persisted as an empty object", {
  s = test_session()
  st = new.env()
  st$count = 1L
  assign("panel", st, envir = session_live(s)$ext)
  plugin_state_persist(s)
  rm("count", envir = st)
  plugin_state_persist(s)
  plugin_state_persist(s)
  ext = Filter(function(e) identical(e$custom_type, "gptr.ext"), session_data(s)$entries)
  expect_length(ext, 2L)
  expect_match(entry_json_line(ext[[2L]]), "\"state\":{}", fixed = TRUE)
  expect_identical(s$ext$panel, json_obj())
})

test_that("a returns schema that cannot be applied is a notice, not an error", {
  s = test_session()
  run = test_run(s, list(returns = "not a schema"))
  d = session_data(s)
  d$last_text = "{\"n\": 1}"
  withr::local_options(gptr.quiet = FALSE)
  expect_message(run_returns(run), class = "gptr_message_notice")
  expect_null(s$value)
})

# ---------------------------------------------------------------- the run engine

test_that("session_run() returns the identical session; each run is one prompt turn", {
  local_permissive()
  local_fake_provider(list("one", "two"))
  s = test_session()
  expect_identical(session_run(s, msg_user("a")), s)
  expect_identical(s |> session_run(msg_user("b")), s)
  expect_identical(s$turns, 2L)
  expect_identical(s$text, "two")
  expect_identical(s$status, "idle")
})

test_that("run_start() is non-blocking; run_wait() settles; the run carries its contract fields", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  expect_identical(s$status, "running")
  expect_identical(session_live(s)$run, run)
  expect_true(run_wait(list(run), timeout = 30))
  expect_identical(run$status, "idle")
  expect_identical(run$turn, 1L)
  expect_identical(s$status, "idle")
  expect_null(session_live(s)$run)
  expect_identical(gptr_last(), s)
})

test_that("agent events are paired and ordered", {
  local_permissive()
  local_fake_provider(list("done"))
  ev = local_events(c("agent_start", "turn_start", "message_start", "message_end", "turn_end",
                      "agent_end"))
  s = test_session()
  run_text(s, "go")
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, c("agent_start", "turn_start", "message_start", "message_end",
                            "message_start", "message_end", "turn_end", "agent_end"))
  end = ev(s)[[length(ev(s))]]
  expect_identical(end$status, "idle")
  expect_identical(end$turns, 1L)
  expect_identical(nrow(end$usage), 1L)
})

test_that("turn_end carries the tool-result messages, never the tools' R values (R1)", {
  local_permissive()
  local_tool("val", function(input, ctx) gptr_tool_result("made", value = as.numeric(1:10)))
  ev = local_events("turn_end")
  local_fake_provider(list(fake_tool("val"), "done"))
  s = test_session()
  run_text(s, "go")
  res = ev(s)[[1L]]$results[[1L]]
  expect_identical(res$role, "tool_result")
  expect_identical(msg_text(res), "made")
  expect_null(res[["value"]])
})

test_that("the first run freezes the prompt: gptr.frozen is the first entry (fallback before P07)",
          {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "go")
  first = session_data(s)$entries[[1L]]
  expect_identical(first$custom_type, "gptr.frozen")
})

test_that("a busy session refuses a second run", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  run = run_start(s, msg_user("go"))
  expect_error(run_start(s, msg_user("again")), class = "gptr_error_busy")
  run_abort(run)
  expect_identical(s$status, "aborted")
})

test_that("an empty input, an empty queue and a finished answer is refused", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "go")
  expect_error(run_start(s, NULL), class = "gptr_error_invalid_argument")
})

test_that("queued items start an idle session's run (input = NULL)", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  session_enqueue(s, "please start", as = "follow_up", source = "api_user")
  session_run(s, NULL)
  expect_identical(roles(s), c("user", "assistant"))
  expect_identical(s$messages[[1L]]$source, "follow_up")
  expect_identical(s$turns, 1L)
})

test_that("run_start(s, NULL) continues from the leaf after an abort", {
  local_permissive()
  fake = local_fake_provider(list(list(hang = TRUE), "resumed answer"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  run_wait(list(run), timeout = 0.2)
  run_abort(run, "waiting")
  session_run(s, NULL)
  expect_identical(s$text, "resumed answer")
  expect_identical(s$turns, 1L)
  expect_identical(req_roles(fake_requests(fake)[[2L]]), "user")
})

test_that("run_current() and run_eval_env() inside a tool; the home is reset at settlement", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$run = run_current()
    box$env = run_eval_env(box$run)
    "seen"
  })
  local_fake_provider(list(fake_tool("peek"), "done"))
  home = new.env()
  s = test_session(home = home)
  run_text(s, "go")
  expect_s3_class(box$run, "gptr_run")
  expect_identical(box$env, home)
  expect_null(box$run$home)
  expect_null(run_current())
})

test_that("plan mode evaluates in a scratch overlay that is discarded (IC-15)", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$env = run_eval_env(run_current())
    assign("scratch_obj", 1, envir = box$env)
    "ok"
  })
  local_fake_provider(list(fake_tool("peek"), "plan ready"))
  home = new.env()
  s = test_session(mode = "plan", home = home)
  run_text(s, "plan it")
  expect_identical(parent.env(box$env), home)
  expect_false(exists("scratch_obj", envir = home, inherits = FALSE))
})

test_that("a function-frame home is used for the run but never kept (R2)", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$env = run_eval_env(run_current())
    "ok"
  })
  local_fake_provider(list(fake_tool("peek"), "done"))
  f = function() {
    s = session_new("fake/fake-1", "auto", home = environment())
    call = new.env()
    call$envir = environment()
    session_run(s, msg_user("go"), list(call = call))
    list(s = s, frame = environment())
  }
  x = f()
  expect_identical(box$env, x$frame)
  expect_null(x$s$envir)
  expect_match(session_data(x$s)$home_label, "^frame of f")
})

test_that("run_abort() records the partial answer, moves the queue to dropped and settles aborted",
          {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  ev = local_events("agent_end")
  s = test_session()
  run = run_start(s, msg_user("go"))
  run_wait(list(run), timeout = 0.3)
  session_enqueue(s, "later", as = "steer", source = "pipe")
  run_abort(run, "user")
  expect_identical(s$status, "aborted")
  last = s$messages[[length(s$messages)]]
  expect_identical(last$role, "assistant")
  expect_identical(last$stop_reason, "aborted")
  expect_length(session_data(s)$dropped, 1L)
  expect_length(session_data(s)$queue$steer, 0L)
  expect_identical(ev(s)[[1L]]$status, "aborted")
})

test_that("an abort while a tool waits in the FIFO cancels the job; the session can be collected", {
  local_permissive()
  local_tool("queued", function(input, ctx) "never runs")
  local_fake_provider(list(fake_tool("queued"), "never"))
  s = test_session()
  id = session_data(s)$id
  run = run_start(s, msg_user("go"))
  # pump without running any FIFO tool (allow_runs = character()) until the batch is queued
  reactor_pump(until = function() identical(run$status, "tools"), allow_runs = character(),
               timeout = 30)
  run_abort(run)
  other = test_session()
  rm(s, run)
  invisible(gc())
  expect_null(session_by_id(id))
})

test_that("an interrupt aborts the run and is re-signalled; no connection is left open", {
  local_permissive()
  local_store()
  n0 = nrow(showConnections())
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "no"
  })
  local_fake_provider(list(fake_tool("spin"), "never"))
  s = test_session()
  res = tryCatch({
    run_text(s, "go")
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  expect_identical(s$status, "aborted")
  expect_identical(nrow(showConnections()), n0)
})

test_that("no connection is left open after a run returns or errors (IC-59)", {
  local_permissive()
  local_store()
  n0 = nrow(showConnections())
  local_fake_provider(list("ok", fake_error("400 bad request", status = 400L)))
  s = test_session()
  run_text(s, "a")
  run_text(s, "b")
  expect_identical(s$status, "error")
  expect_identical(nrow(showConnections()), n0)
})

test_that("a nested run tightens the mode, inherits the snapshot and links to the outer run", {
  local_permissive()
  box = new.env()
  local_tool("sub", function(input, ctx) {
    child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                        parent = ctx$session)
    box$outer = run_current()
    box$child_run = run_start(child, msg_user("child task"))
    box$child = child
    run_wait(list(box$child_run))
    "child done"
  })
  local_fake_provider(list(fake_tool("sub"), "child answer", "outer done"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(box$child_run$mode, "manual")
  expect_identical(box$child_run$opts$safety, box$outer$opts$safety)
  expect_identical(box$child_run$parent_run, box$outer$id)
  expect_true(session_data(box$child)$id %in% box$outer$children)
  expect_identical(session_data(box$child)$depth, 1L)
  expect_identical(box$child$text, "child answer")
  expect_identical(nrow(s$usage), 3L)
})

test_that("gptr.max_nested_calls caps gptr() calls of one evaluation; a group counts once", {
  local_permissive()
  local_gptr_options(max_nested_calls = 2L)
  box = new.env()
  local_tool("many", function(input, ctx) {
    # three children of one team share `nested_group` and count once (1 of 2) ...
    box$team = tryCatch({
      for (i in 1:3) {
        child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                            parent = ctx$session)
        run_wait(list(run_start(child, msg_user("x"), list(nested_group = "team1"))))
      }
      "ok"
    }, error = function(e) e)
    # ... so one more call fits (2 of 2) and the next is refused (3 > 2)
    box$err = tryCatch({
      for (i in 1:2) {
        child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                            parent = ctx$session)
        run_wait(list(run_start(child, msg_user("x"))))
      }
      NULL
    }, error = function(e) e)
    "ok"
  })
  local_fake_provider(list(fake_tool("many"), "c"))
  s = test_session()
  run_text(s, "go")
  expect_identical(box$team, "ok")
  expect_s3_class(box$err, "gptr_error_budget")
  expect_identical(box$err$kind, "nested_calls")
})

test_that("tools plus returns = <schema> give a typed $value and keep the tool calls (INFRA-25)", {
  local_permissive()
  local_tool("count", function(input, ctx) "32")
  local_fake_provider(list(fake_tool("count"), list(json = list(n = 32L))))
  s = test_session()
  run_text(s, "count", list(returns = list(type = "object", required = I("n"),
                                           properties = list(n = list(type = "integer")))))
  expect_identical(s$value$n, 32L)
  expect_identical(roles(s), c("user", "assistant", "tool_result", "assistant"))
})

test_that("a router session calls router.call before each request (IC-69)", {
  # P07's compactor would ask the router for its compaction model first (reason "compaction")
  local_without_services(c("compact.should", "compact.run"))
  local_permissive()
  local_fake_provider(list("routed"))
  calls = new.env()
  calls$reasons = character()
  local_service("router.call", function(s, reason) {
    calls$reasons = c(calls$reasons, reason)
    list(model = "fake/fake-1", thinking = NULL, state = list(k = 1))
  })
  s = session_new("router:cheapest", "auto", home = new.env())
  run_text(s, "go")
  expect_identical(calls$reasons, "turn")
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
  expect_true(all(c("model_change", "gptr.router") %in% types))
  expect_identical(s$text, "routed")
  expect_identical(s$model, "router:cheapest")
})

test_that("a prefix break stops the run only under gptr.check_prefix = \"error\"", {
  local_permissive()
  local_service("prefix.guard", function(s, target, view) {
    gptr_abort("Prompt-cache prefix broken at t1", "internal", detail = "test break")
  })
  fake = local_fake_provider(list("ok"))
  local_gptr_options(check_prefix = "error")
  s = test_session()
  run_text(s, "hello")
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_internal")
  expect_length(fake_requests(fake), 0L)
  local_gptr_options(check_prefix = "event")
  s2 = test_session()
  run_text(s2, "hello")
  expect_identical(s2$status, "idle")
  expect_identical(s2$text, "ok")
})

test_that("two concurrent sessions keep separate usage and tool context (INFRA-15)", {
  local_permissive()
  seen = new.env()
  local_tool("who", function(input, ctx) {
    seen[[session_data(ctx$session)$id]] = run_current()$session
    "me"
  })
  local_fake_provider(list(fake_tool("who"), "a2"), name = "fa")
  local_fake_provider(list(fake_tool("who"), "b2"), name = "fb")
  s1 = test_session(model = "fa/fa-1")
  s2 = test_session(model = "fb/fb-1")
  r1 = run_start(s1, msg_user("x"))
  r2 = run_start(s2, msg_user("y"))
  run_wait(list(r1, r2))
  id1 = session_data(s1)$id
  id2 = session_data(s2)$id
  expect_identical(nrow(s1$usage), 2L)
  expect_identical(unique(s1$usage$session), id1)
  expect_identical(unique(s2$usage$session), id2)
  expect_identical(seen[[id1]], id1)
  expect_identical(seen[[id2]], id2)
})

test_that("a tool piping into its own running session enqueues a steer delivered after its result",
          {
  local_permissive()
  local_tool("self", function(input, ctx) {
    session_enqueue(ctx$session, "use TPM", as = "steer", source = "pipe")
    "sent"
  })
  fake = local_fake_provider(list(fake_tool("self"), "ack", "done"))
  s = test_session()
  run_text(s, "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", "tool_result", "operator"))
  expect_identical(msg_text(req$messages[[4L]]),
                   "The user sent this message while you were working: use TPM")
})

test_that("a mode change during a run reaches the model as an operator message after the results", {
  local_permissive()
  box = new.env()
  local_tool("switch", function(input, ctx) {
    session_set_mode(ctx$session, "plan", source = "pause_menu")
    "switched"
  })
  fake = local_fake_provider(list(fake_tool("switch"), "ok"))
  s = test_session(mode = "auto")
  run_text(s, "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", "tool_result", "operator"))
  expect_match(msg_text(req$messages[[4L]]), "<mode name=\"plan\">", fixed = TRUE)
})

test_that("a run sent to the background ends the foreground wait (P21)", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  local_hook("message_start", function(event, ctx) {
    run = session_live(ctx$session)$run
    if (!is.null(run)) run$opts$background = TRUE
    NULL
  })
  session_run(s, msg_user("go"))
  expect_identical(s$status, "running")
  run_abort(session_live(s)$run)
})

test_that("a UI answering abort to a permission request aborts the run", {
  local_gptr_options(interactive = TRUE)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) list(decision = "abort"))
  })
  local_tool("w", function(input, ctx) "written")
  fake = local_fake_provider(list(fake_tools(list(name = "w", input = json_obj()),
                                             list(name = "w", input = json_obj())), "never"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_length(tool_results(s), 1L)
  expect_length(fake_requests(fake), 1L)
})

# ---------------------------------------------------------------- report 02 section 5.3: the driver

local_fast_retry = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(agent_retry_delay = function(attempt) c(0.04, 0.08)[attempt],
                                  .env = .env)
}
flaky = function() {
  list(fake_error("529 overloaded", 529L), fake_error("503 service unavailable", 503L), "finally")
}

test_that(oracle_title(recovery_recs, "R19"), {
  local_permissive()
  local_fast_retry()
  fake = local_fake_provider(flaky())
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 3L)
  expect_identical(s$text, "finally")
  expect_identical(s$status, "idle")
})

test_that(oracle_title(recovery_recs, "R20"), {
  local_permissive()
  local_fast_retry()
  fake = local_fake_provider(flaky())
  run_text(test_session(), "hello")
  expect_identical(req_roles(fake_requests(fake)[[3L]]), "user")
})

test_that(oracle_title(recovery_recs, "R21"), {
  local_permissive()
  local_fast_retry()
  local_fake_provider(flaky())
  s = test_session()
  run_text(s, "hello")
  expect_identical(sum(vapply(s$messages, function(m) identical(m$stop_reason, "error"), NA)), 2L)
})

test_that(oracle_title(recovery_recs, "R22"), {
  local_permissive()
  local_fast_retry()
  ev = local_events(c("retry_start", "retry_end"))
  local_fake_provider(flaky())
  s = test_session()
  t0 = Sys.time()
  run_text(s, "hello")
  el = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  starts = Filter(function(e) identical(e$type, "retry_start"), ev(s))
  expect_identical(vapply(starts, function(e) e$delay, 1), c(0.04, 0.08))
  expect_gte(el, 0.1)
  expect_true(ev(s)[[length(ev(s))]]$ok)
})

test_that(oracle_title(recovery_recs, "R23"), {
  local_permissive()
  ev = local_events("retry_start")
  fake = local_fake_provider(list(fake_error("insufficient_quota", status = 400L)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 1L)
  expect_length(ev(s), 0L)
  expect_identical(s$status, "error")
})

test_that(oracle_title(recovery_recs, "R24"), {
  local_permissive()
  local_fast_retry()
  ev = local_events("retry_end")
  fake = local_fake_provider(list(fake_error("overloaded", 529L)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 3L)
  expect_false(ev(s)[[1L]]$ok)
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_provider")
})

test_that(oracle_title(recovery_recs, "R25"), {
  local_permissive()
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    n$reason = reason
    invisible(s)
  })
  fake = local_fake_provider(list(list(overflow = TRUE), "fits now"))
  s = test_session()
  run_text(s, "hello")
  expect_identical(n$calls, 1L)
  expect_identical(n$reason, "overflow")
  expect_length(fake_requests(fake), 2L)
  expect_identical(s$status, "idle")
})

test_that(oracle_title(recovery_recs, "R26"), {
  local_permissive()
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    invisible(s)
  })
  fake = local_fake_provider(list(list(overflow = TRUE)))
  s = test_session()
  run_text(s, "hello")
  expect_identical(n$calls, 1L)
  expect_length(fake_requests(fake), 2L)
  expect_identical(s$status, "error")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_context_overflow")
  expect_s3_class(cnd, "gptr_error_provider")
  expect_match(conditionMessage(cnd), "still too large after one compaction", fixed = TRUE)
})

test_that("without a compactor the first overflow is terminal", {
  local_without_services(c("compact.should", "compact.run"))
  local_permissive()
  fake = local_fake_provider(list(list(overflow = TRUE)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 1L)
  expect_s3_class(session_data(s)$condition, "gptr_error_context_overflow")
})

test_that("every report 02 recovery check has a test", {
  expect_oracles_covered(recovery_recs, "test-agent-run.R")
})

# ---------------------------------------------------------------- the engine under IC-74 and IC-57

test_that("a reported usage keeps its unknown counts; only an unreported one is estimated", {
  expect_false(run_usage_reported(NULL))
  expect_false(run_usage_reported(usage_as(NULL)))
  expect_false(run_usage_reported(usage_new()))
  expect_false(run_usage_reported(list(input = -1, output = 2)))
  expect_false(run_usage_reported("12 tokens"))
  expect_true(run_usage_reported(usage_new(input = 3, output = NA)))
  expect_true(run_usage_reported(list(cache_read = 40)))
  local_permissive()
  partly = usage_new(input = 120, output = NA)
  local_fake_provider(list(list(text = "partly reported", usage = partly),
                           list(text = "nothing reported", usage = usage_as(NULL)),
                           fake_error("400 invalid request", status = 400L)))
  s = test_session()
  run_text(s, "one")
  run_text(s, "two")
  run_text(s, "three")
  u = session_data(s)$usage
  expect_identical(nrow(u), 3L)
  expect_identical(u$input[[1L]], 120)
  expect_true(is.na(u$output[[1L]]))
  expect_false(u$estimated[[1L]])
  msgs = s$messages
  expect_identical(msgs[[2L]]$usage$input, 120)
  expect_true(is.na(msgs[[2L]]$usage$output))
  expect_identical(u$estimated[2:3], c(TRUE, TRUE))
  expect_true(all(u$input[2:3] > 0))
  expect_true(isTRUE(msgs[[4L]]$usage$estimated))
  expect_true(isTRUE(msgs[[6L]]$usage$estimated))
  expect_identical(s$status, "error")
})

test_that("an overflow condition carries the provider's prompt count, never gptr's estimate", {
  expect_identical(run_overflow_tokens(list(usage = usage_new(input = 5000, output = 0))), 5000)
  expect_identical(run_overflow_tokens(list(usage = usage_new(input = 5000, estimated = TRUE))),
                   NA_real_)
  expect_identical(run_overflow_tokens(list(usage = usage_as(NULL))), NA_real_)
  expect_identical(run_overflow_tokens(list()), NA_real_)
  local_without_services(c("compact.should", "compact.run"))
  local_permissive()
  local_fake_provider(list(list(overflow = TRUE)))
  s = test_session()
  run_text(s, "hello")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_context_overflow")
  expect_identical(cnd$tokens, NA_real_)
  expect_true(isTRUE(s$messages[[2L]]$usage$estimated))
})

test_that("a decision-only model or a refused request preflight ends the run before any request", {
  local_permissive()
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  s = test_session(model = "judge/judge-s1")
  run_text(s, "go")
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_not_available")
  expect_null(session_live(s)$run)
  expect_length(fake_requests(judge), 0L)
  fake = local_fake_provider(list("never sent"))
  seen = new.env()
  testthat::local_mocked_bindings(provider_preflight = function(model, provider, safety = NULL) {
    seen$safety = safety
    gptr_abort("test refusal: local execution cannot be established", "untrusted",
               what = "model", path = model$ref, origin = "http://192.0.2.1:11434")
  })
  s2 = test_session()
  run_text(s2, "go")
  expect_identical(s2$status, "error")
  cnd = session_data(s2)$condition
  expect_s3_class(cnd, "gptr_error_untrusted")
  expect_identical(s2$reason, conditionMessage(cnd))
  expect_length(fake_requests(fake), 0L)
  # the preflight reads the run's frozen safety snapshot: without a human relaxation, local-only
  expect_true(isTRUE(seen$safety$ollama_local_only))
  expect_null(session_live(s2)$run)
  expect_identical(nrow(s2$usage), 0L)
})

test_that("a pump nested in a hook runs only its own run's tools, never another run's (IC-57)", {
  local_permissive()
  box = new.env()
  local_tool("probe", function(input, ctx) {
    box$depth = reactor_depth()
    "probed"
  })
  local_fake_provider(list(fake_tool("probe"), "a done"), name = "fa")
  local_fake_provider(list("b done"), name = "fb")
  local_fake_provider(list("c done"), name = "fc")
  a = test_session(model = "fa/fa-1")
  b = test_session(model = "fb/fb-1")
  c_s = test_session(model = "fc/fc-1")
  bid = session_data(b)$id
  local_hook("turn_end", function(event, ctx) {
    if (identical(event$session, bid) && is.null(box$nested)) {
      box$nested = TRUE
      session_run(c_s, msg_user("nested"))
    }
    NULL
  })
  ra = run_start(a, msg_user("x"))
  rb = run_start(b, msg_user("y"))
  run_wait(list(ra, rb))
  expect_true(isTRUE(box$nested))
  expect_identical(c_s$text, "c done")
  expect_identical(box$depth, 1L)
  expect_identical(a$text, "a done")
  expect_identical(b$text, "b done")
})

test_that("a streaming redactor that failed closed drops its held text; the reply is recorded", {
  local_permissive()
  limit = function(...) {
    gptr_abort("Streaming redaction exceeded its holding limit.", "redaction_limit", limit = 1L)
  }
  testthat::local_mocked_bindings(redact_stream = function(profile = "stream") {
    list(push = limit, flush = limit)
  })
  updates = local_events("message_update")
  local_fake_provider(list("a reply the redactor cannot hold"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "idle")
  expect_identical(s$text, "a reply the redactor cannot hold")
  expect_length(updates(s), 0L)
})

# ---------------------------------------------------------------- settlement when the store fails

test_that("a store failure while a run settles ends it with status error; the session is free", {
  local_permissive()
  box = new.env()
  box$fail = TRUE
  persist = plugin_state_persist
  testthat::local_mocked_bindings(plugin_state_persist = function(s) {
    if (isTRUE(box$fail)) {
      box$fail = FALSE
      gptr_abort("the session store failed: disk full", "internal", detail = "disk full")
    }
    persist(s)
  })
  ev = local_events("agent_end")
  local_fake_provider(list("first", "second"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  expect_true(run_wait(list(run), timeout = 30))
  expect_identical(s$status, "error")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_internal")
  expect_identical(s$reason, conditionMessage(cnd))
  expect_match(s$reason, "the session store failed", fixed = TRUE)
  expect_identical(run$signal$condition, cnd)
  expect_null(session_live(s)$run)
  expect_null(run$home)
  expect_false(exists(reactor_run_id(run), envir = reactor_get()$runs, inherits = FALSE))
  expect_identical(vapply(ev(s), function(e) e$status, ""), "error")
  run_text(s, "again")
  expect_identical(s$status, "idle")
  expect_identical(s$text, "second")
})

test_that("a store failure while storing the `returns` value settles the run with status error", {
  local_permissive()
  testthat::local_mocked_bindings(session_value_set = function(...) {
    gptr_abort("the session store failed: read-only file", "internal", detail = "read-only file")
  })
  local_fake_provider(list('{"n": 1}'))
  s = test_session()
  run_text(s, "go", list(returns = num_schema(n = "integer")))
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_internal")
  expect_null(session_live(s)$run)
})

test_that("a store failure while a run settles keeps its own terminal condition, with a diagnostic",
          {
  local_permissive()
  testthat::local_mocked_bindings(plugin_state_persist = function(s) {
    gptr_abort("the session store failed: disk full", "internal", detail = "disk full")
  })
  local_tool("again", function(input, ctx) "ok")
  local_fake_provider(list(fake_tool("again"), "never"))
  s = test_session()
  run_text(s, "go", list(max_turns = 1L))
  expect_identical(s$status, "max_turns")
  expect_s3_class(session_data(s)$condition, "gptr_error_max_turns")
  expect_null(session_live(s)$run)
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 1L)
  expect_identical(diag$event, "settle")
  expect_match(diag$message, "the session store failed", fixed = TRUE)
})

test_that("an abort whose partial answer cannot be stored still settles and re-signals", {
  local_permissive()
  append = session_append
  testthat::local_mocked_bindings(session_append = function(s, entry) {
    if (identical(entry$message$stop_reason, "aborted")) {
      gptr_abort("the session store failed: disk full", "internal", detail = "disk full")
    }
    append(s, entry)
  })
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  run = run_start(s, msg_user("go"))
  reactor_pump(until = function() identical(run$status, "streaming"), timeout = 30)
  interrupt = function() {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
  }
  res = tryCatch(run_abort_only(interrupt, run), interrupt = function(cnd) "interrupted",
                 error = function(e) conditionMessage(e))
  expect_identical(res, "interrupted")
  expect_identical(s$status, "aborted")
  expect_true(isTRUE(run$settled))
  expect_null(session_live(s)$run)
  expect_false(exists(reactor_run_id(run), envir = reactor_get()$runs, inherits = FALSE))
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 1L)
  expect_identical(diag$event, "abort")
  expect_match(diag$message, "the session store failed", fixed = TRUE)
})

test_that("an abort before the stream's start event records the run's model, not 'unknown'", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE, delay = 5)))
  s = test_session()
  run = run_start(s, msg_user("go"))
  reactor_pump(until = function() identical(run$status, "requesting"), timeout = 30)
  run_abort(run, "user")
  expect_identical(s$status, "aborted")
  last = s$messages[[length(s$messages)]]
  expect_identical(last$role, "assistant")
  expect_identical(last$stop_reason, "aborted")
  expect_identical(c(last$api, last$provider, last$model), c(run$model$api, "fake", "fake-1"))
  expect_false(identical(last$api, "unknown"))
  expect_identical(last$request_id, run$request_id)
})

# ---------------------------------------------------------------- the ctx.kernel service (IC-34)

kernel_members = c("envir", "run", "mode", "model", "execute_tool", "send", "set_model",
                   "append_entry", "abort", "aborted", "update", "usage", "state")

test_that("ctx.kernel is a registered service listing the P06 members of section 10.6", {
  expect_true(ext_service_has("ctx.kernel"))
  k = ext_service_get("ctx.kernel")()
  expect_identical(names(k), kernel_members)
  expect_true(all(vapply(k, is.function, NA)))
})

test_that("outside a run the members read the session", {
  home = new.env()
  s = test_session(mode = "manual", home = home)
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  expect_identical(k$envir(ctx), home)
  expect_null(k$run(ctx))
  expect_identical(k$mode(ctx), "manual")
  expect_identical(k$model(ctx), "fake/fake-1")
  expect_false(k$aborted(ctx))
  expect_s3_class(k$usage(ctx), "gptr_usage")
  expect_null(k$update(ctx, "ignored outside a tool"))
  expect_null(k$abort(ctx))
})

test_that("inside a tool the members see the run; update emits tool_execution_update", {
  local_permissive()
  box = new.env()
  local_tool("probe", function(input, ctx) {
    k = ctx_kernel()
    box$run = k$run(ctx)
    box$envir = k$envir(ctx)
    box$mode = k$mode(ctx)
    k$update(ctx, "half way")
    "probed"
  })
  local_fake_provider(list(fake_tool("probe"), "done"))
  ev = local_events("tool_execution_update")
  home = new.env()
  s = test_session(home = home)
  run_text(s, "go")
  expect_match(box$run, "^u[0-9a-f]{8}$")
  expect_identical(box$envir, home)
  expect_identical(box$mode, "auto")
  up = ev(s)
  expect_length(up, 1L)
  expect_identical(up[[1L]]$text, "half way")
  expect_identical(up[[1L]]$tool_name, "probe")
})

test_that("send() enqueues extension notes, never operator relays (IC-55)", {
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  k$send(ctx, "check the units", extension = "plugin:units")
  k$send(ctx, "then plot", as = "follow_up")
  q = session_data(s)$queue
  expect_identical(q$steer[[1L]]$source, "extension")
  expect_identical(q$steer[[1L]]$name, "units")
  expect_identical(q$follow_up[[1L]]$text, "then plot")
  m = queue_item_message(q$steer[[1L]], "steer", relay = TRUE)
  expect_identical(m$role, "user")
  expect_identical(msg_text(m),
                   "Extension units sent this note (not from the user): check the units")
})

test_that("send() from model code of the same session tree is refused (IC-55)", {
  local_permissive()
  box = new.env()
  local_tool("r", function(input, ctx) {
    box$err = tryCatch(ctx_kernel()$send(ctx, "sneaky"), error = function(e) e)
    "ran"
  }, parameters = list(type = "object", required = I("code"),
                       properties = list(code = list(type = "string"))))
  local_fake_provider(list(fake_tool("r", code = "gptr_steer(s, 'x')"), "done"))
  s = test_session()
  run_text(s, "go")
  expect_s3_class(box$err, "gptr_error_permission")
  expect_length(session_data(s)$queue$steer, 0L)
})

test_that("set_model() switches at once when idle and at the next request inside a run", {
  local_permissive()
  local_fake_provider(list("a"))
  local_fake_provider(list("from other"), name = "other")
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  k$set_model(ctx, "other/other-1", thinking = "high", reason = "plugin")
  expect_identical(s$model, "other/other-1")
  change = Filter(function(e) identical(e$type, "model_change"), session_data(s)$entries)
  expect_identical(change[[1L]]$gptr$reason, "plugin")
  run = test_run(s)
  k$set_model(ctx, "fake/fake-1", thinking = "low")
  expect_identical(s$model, "other/other-1")
  expect_identical(run$pending_model, list(ref = "fake/fake-1", thinking = "low",
                                           reason = "plugin"))
})

test_that("append_entry() writes a custom entry named <plugin>.<type>", {
  s = test_session()
  ctx = session_live(s)$ctx
  id = ctx_kernel()$append_entry(ctx, "note", list(n = 1L), extension = "plugin:units")
  e = session_data(s)$entries[[length(session_data(s)$entries)]]
  expect_identical(e$id, id)
  expect_identical(e$custom_type, "units.note")
  expect_identical(e$data, list(n = 1L))
})

test_that("abort() inside a tool stops the run after the call with the given reason", {
  local_permissive()
  local_tool("stopper", function(input, ctx) {
    ctx_kernel()$abort(ctx, "plugin stop")
    "stopping"
  })
  local_fake_provider(list(fake_tools(list(name = "stopper", input = json_obj()),
                                      list(name = "stopper", input = json_obj())),
                           "never reached"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_length(tool_results(s), 1L)
  expect_false(identical(s$text, "never reached"))
})

test_that("state() is one environment per session and plugin, persisted when JSON-able", {
  local_permissive()
  local_fake_provider(list("ok"))
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  st = k$state(ctx, extension = "plugin:panel")
  st$count = 2L
  expect_identical(k$state(ctx, extension = "plugin:panel"), st)
  expect_false(identical(k$state(ctx, extension = "plugin:other"), st))
  run_text(s, "go")
  expect_identical(s$ext$panel$count, 2L)
})

# Added beyond the plan (P06 Task 15 adaptations, dev/progress/P06.md): labels, the process-level
# ctx, recorded thinking levels, refused entries, aborts inside the dispatcher, the stack's run.

test_that("ctx_ext_label() takes a bare plugin name or a full source", {
  expect_identical(ctx_ext_label("plugin:units"), "units")
  expect_identical(ctx_ext_label("builtin:documents"), "documents")
  expect_identical(ctx_ext_label("panel"), "panel")
  expect_identical(ctx_ext_label(NULL), "plugin")
  expect_identical(ctx_ext_label(NA_character_), "plugin")
  expect_identical(ctx_ext_label(""), "plugin")
  expect_identical(ctx_ext_label("plugin:"), "plugin")
})

test_that("a process-level ctx reads the process defaults and refuses the session verbs", {
  local_gptr_options(mode = "plan", model = "fake/fake-1")
  ctx = ctx_new(NULL)
  k = ctx_kernel()
  expect_null(k$envir(ctx))
  expect_null(k$run(ctx))
  expect_identical(k$run(ctx_new(NULL, run = list(id = "u1"))), "u1")
  expect_identical(k$mode(ctx), "plan")
  expect_identical(k$model(ctx), "fake/fake-1")
  expect_false(k$aborted(ctx))
  expect_null(k$abort(ctx, "stop"))
  expect_null(k$update(ctx, "progress"))
  expect_null(k$state(ctx))
  expect_s3_class(k$usage(ctx), "gptr_usage")
  verbs = list(function() k$send(ctx, "note"), function() k$set_model(ctx, "fake/fake-1"),
               function() k$append_entry(ctx, "note", list()))
  for (verb in verbs) {
    err = expect_error(verb(), class = "gptr_error_invalid_argument")
    expect_identical(err$arg, "ctx")
  }
})

test_that("set_model() records the thinking level with the model and refuses bad input at once", {
  local_fake_provider(list("a"))
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  k$set_model(ctx, "fake/fake-1", thinking = "high")
  d = session_data(s)
  e = d$entries[[length(d$entries)]]
  expect_identical(e$type, "model_change")
  expect_identical(e$gptr[c("thinking", "reason")], list(thinking = "high", reason = "plugin"))
  expect_identical(d$thinking, "high")
  expect_identical(s$model, "fake/fake-1")
  n = length(d$entries)
  err = expect_error(k$set_model(ctx, "fake/fake-1", thinking = "extreme"),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "thinking")
  expect_error(k$set_model(ctx, "nowhere/none-1"), class = "gptr_error_unknown_model")
  run = test_run(s)
  expect_error(k$set_model(ctx, "nowhere/none-1"), class = "gptr_error_unknown_model")
  expect_null(run$pending_model)
  expect_length(d$entries, n)
  k$set_model(ctx, "fake/fake-1", thinking = "low")
  expect_length(d$entries, n)
  expect_identical(run_target(run)$thinking, "low")
  e = d$entries[[length(d$entries)]]
  expect_identical(e$type, "model_change")
  expect_identical(e$gptr[c("thinking", "reason")], list(thinking = "low", reason = "plugin"))
  expect_identical(d$thinking, "low")
})

test_that("append_entry() refuses data the store cannot hold and gptr's own entry types", {
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  n = length(session_data(s)$entries)
  err = expect_error(k$append_entry(ctx, "note", list(where = new.env())),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "data")
  err = expect_error(k$append_entry(ctx, "mode_change", list(from = "manual", to = "auto"),
                                    extension = "plugin:gptr"),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "type")
  expect_error(k$append_entry(ctx, "", list()), class = "gptr_error_invalid_argument")
  expect_length(session_data(s)$entries, n)
  k$append_entry(ctx, "mode_change", list(to = "auto"), extension = "plugin:gptrx")
  expect_identical(session_data(s)$entries[[n + 1L]]$custom_type, "gptrx.mode_change")
})

test_that("send() labels its own queue item when a queue_update hook enqueues another", {
  s = test_session()
  ctx = session_live(s)$ctx
  once = new.env()
  once$done = FALSE
  local_hook("queue_update", function(event, ctx) {
    if (!once$done) {
      once$done = TRUE
      session_enqueue(ctx$session, "from the pipe", "steer", source = "pipe")
    }
    NULL
  })
  ctx_kernel()$send(ctx, "check the units", extension = "plugin:units")
  q = session_data(s)$queue$steer
  expect_identical(vapply(q, function(i) i$source, ""), c("extension", "pipe"))
  expect_identical(q[[1L]]$name, "units")
  expect_null(q[[2L]]$name)
})

test_that("abort() from a tool_call hook ends the call unrun, then settles the run", {
  local_permissive()
  box = new.env()
  box$status = character()
  local_tool("work", function(input, ctx) {
    box$status = c(box$status, session_data(ctx$session)$status)
    "worked"
  })
  local_hook("tool_call", function(event, ctx) {
    ctx_kernel()$abort(ctx, "hook stop")
    NULL
  })
  ev = local_events(c("tool_execution_end", "agent_end"))
  local_fake_provider(list(fake_tools(list(name = "work", input = json_obj()),
                                      list(name = "work", input = json_obj())),
                           "never reached"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_length(box$status, 0L)
  res = tool_results(s)
  expect_length(res, 1L)
  expect_true(res[[1L]]$is_error)
  expect_identical(msg_text(res[[1L]]), "Tool call not executed: the run was aborted (hook stop).")
  expect_identical(vapply(ev(s), function(e) e$type, ""), c("tool_execution_end", "agent_end"))
})

test_that("aborted() and run() still see a run that was aborted while its tool executes", {
  local_permissive()
  box = new.env()
  local_tool("long", function(input, ctx) {
    k = ctx_kernel()
    box$before = k$aborted(ctx)
    run_abort(session_live(ctx$session)$run, "user")
    box$after = k$aborted(ctx)
    box$run = k$run(ctx)
    "stopped early"
  })
  local_fake_provider(list(fake_tool("long"), "never reached"))
  s = test_session()
  run_text(s, "go")
  expect_false(box$before)
  expect_true(box$after)
  expect_match(box$run, "^u[0-9a-f]{8}$")
  expect_identical(s$status, "aborted")
})

test_that("state() starts empty when the stored state of a plugin is not a named list", {
  s = test_session()
  d = session_data(s)
  d$ext = list(panel = list(count = 3L), broken = list(1, 2))
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  expect_identical(k$state(ctx, extension = "plugin:panel")$count, 3L)
  expect_length(ls(k$state(ctx, extension = "plugin:broken")), 0L)
})

# Added in the Task 15 review (round 1): a switch requested during the run's last reply, an abort
# before the request starts, the refusals inside a run.

test_that("set_model() during the run's last reply switches the model when the run settles", {
  local_permissive()
  local_fake_provider(list("done"))
  local_fake_provider(list(), name = "other")
  local_hook("message_end", function(event, ctx) {
    if (identical(event$role, "assistant")) ctx_kernel()$set_model(ctx, "other/other-1")
    NULL
  })
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "idle")
  expect_identical(s$model, "other/other-1")
  change = Filter(function(e) identical(e$type, "model_change"), session_data(s)$entries)
  expect_length(change, 1L)
  expect_identical(change[[1L]]$gptr$reason, "plugin")
})

test_that("a pending switch that fails when the run settles is a diagnostic, not a failed run", {
  local_permissive()
  local_fake_provider(list("done"))
  local_fake_provider(list(), name = "other")
  testthat::local_mocked_bindings(session_set_model = function(s, ref, reason = "user") {
    gptr_abort("the session store failed: disk full", "internal", detail = "disk full")
  })
  local_hook("message_end", function(event, ctx) {
    if (identical(event$role, "assistant")) ctx_kernel()$set_model(ctx, "other/other-1")
    NULL
  })
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "idle")
  expect_identical(s$model, "fake/fake-1")
  expect_null(session_live(s)$run)
  diag = utils::tail(gptr_registry(diagnostics = TRUE), 1L)
  expect_identical(diag$event, "set_model")
  expect_match(diag$message, "other/other-1 was not applied: the session store failed",
               fixed = TRUE)
})

test_that("abort() from a before_request hook settles the run before any transfer starts", {
  local_permissive()
  box = new.env()
  local_hook("before_request", function(event, ctx) {
    box$run = session_live(ctx$session)$run
    ctx_kernel()$abort(ctx, "too expensive")
    NULL
  })
  ev = local_events("agent_end")
  fake = local_fake_provider(list("never sent"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_identical(box$run$status, "aborted")
  expect_true(box$run$settled)
  expect_false(isTRUE(box$run$busy))
  expect_length(box$run$transfers, 0L)
  expect_length(fake_requests(fake), 0L)
  expect_length(ev(s), 1L)
})

test_that("inside a run set_model() refuses a decision-only model; a second abort keeps the reason",
          {
  local_permissive()
  local_fake_provider(list("a"))
  local_fake_provider(list(0.9), name = "cls", type = "classifier")
  s = test_session()
  ctx = session_live(s)$ctx
  run = test_run(s)
  expect_error(ctx_kernel()$set_model(ctx, "cls/cls-s1"), class = "gptr_error_not_available")
  expect_null(run$pending_model)
  box = new.env()
  local_tool("twice", function(input, ctx) {
    k = ctx_kernel()
    k$abort(ctx, "first")
    k$abort(ctx, "second")
    box$run = ctx_run(ctx)
    "stopping"
  })
  local_fake_provider(list(fake_tool("twice"), "never reached"), name = "fake2")
  s2 = test_session(model = "fake2/fake2-1")
  run_text(s2, "go")
  expect_identical(s2$status, "aborted")
  expect_identical(box$run$signal$reason, "first")
  expect_length(tool_results(s2), 1L)
})
