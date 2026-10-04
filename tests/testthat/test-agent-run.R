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
