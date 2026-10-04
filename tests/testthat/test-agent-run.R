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
