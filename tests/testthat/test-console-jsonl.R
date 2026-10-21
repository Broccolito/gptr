# tests/testthat/test-console-jsonl.R -- the JSONL sink and the `jsonl` frontend (plan P14,
# Task 8). The INFRA-27 test (acceptance 4) is in test-console-render.R (03 section 6.18).

# One fake-provider run (an `r` call, then an answer) streamed to a JSONL file at `verbose`
jsonl_run = function(verbose, script = NULL) {
  local_gptr_options(verbose = verbose, quiet = TRUE, record = "off")
  script = script %||% list(list(tool = "r", input = list(code = "z = 1")), "The answer is 42.")
  fake = gptr_fake_provider(script)
  s = peter("compute", model = fake, .run = FALSE, envir = new.env(parent = globalenv()),
           mode = "auto")
  file = tempfile(fileext = ".jsonl")
  on.exit(unlink(file), add = TRUE)
  con = file(file, open = "wb")
  off = jsonl_sink(s, con)
  utils::capture.output(gptr_step(s, turns = Inf))
  off()
  close(con)
  readLines(file, encoding = "UTF-8", warn = FALSE)
}

test_that("jsonl_event() gives the contract 4.5 JSON form", {
  msg = msg_assistant("hi", api = "fake", provider = "fake", model = "fake-1",
                      stop_reason = "tool_use")
  ev = ev_new("message_end", session = "s0123456789", run = "u01234567", role = "assistant",
              message = msg)
  ev$ts = 1790000000.5
  x = jsonl_event(ev)
  expect_identical(x$ts, "2026-09-21T14:13:20.500Z")
  expect_identical(x$type, "message_end")
  expect_identical(x$message$stopReason, "toolUse")
  expect_identical(x$message$content[[1L]]$text, "hi")
  expect_false("turn" %in% names(x))
  line = jsonl_line(ev)
  expect_false(grepl("\n", line, fixed = TRUE))
  expect_identical(json_decode(line)$message$role, "assistant")
})

test_that("jsonl_value() keeps data and drops live objects", {
  x = jsonl_value(list(a = 1, f = function() 1, e = new.env(), q = quote(x + 1),
                       d = as.Date("2026-09-30"), k = factor("lvl")))
  expect_identical(x, list(a = 1, d = "2026-09-30", k = "lvl"))
  df = jsonl_value(data.frame(t = as.POSIXct(0, origin = "1970-01-01", tz = "UTC"), n = 2))
  expect_identical(df$t, "1970-01-01T00:00:00.000Z")
  expect_identical(jsonl_value(list(f = function() 1)), json_obj())
  expect_identical(json_encode(jsonl_value(df)), "[{\"t\":\"1970-01-01T00:00:00.000Z\",\"n\":2}]")
  # agent_end's usage before any response: a 0-row table with a POSIXct column
  expect_identical(nrow(jsonl_value(usage_empty())), 0L)
})

test_that("jsonl_sink() needs an open connection and subscribes to every catalogued event", {
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  expect_error(jsonl_sink(s, "stdout"), class = "gptr_error_invalid_argument")
  con = file(withr::local_tempfile(fileext = ".jsonl"), open = "wb")
  withr::defer(close(con))
  n = length(registry_all_recs("hook", s))
  off = jsonl_sink(s, con)
  expect_identical(length(registry_all_recs("hook", s)) - n, nrow(ev_catalogue()))
  off()
  expect_identical(length(registry_all_recs("hook", s)), n)
})

test_that("a run gives a JSON line per event, in order (contract 4.5)", {
  local_project()
  lines = jsonl_run(0L)
  types = vapply(lines, function(l) json_decode(l)$type, "", USE.NAMES = FALSE)
  # P06's run_start() takes the queued prompt (queue_update) and freezes the prompt of a new
  # session (session_start) before agent_start
  expect_true(all(c("queue_update", "session_start", "agent_start") %in% types))
  expect_lt(match("session_start", types), match("agent_start", types))
  expect_lt(match("agent_start", types), match("message_update", types))
  expect_identical(types[[length(types)]], "agent_end")
  expect_true(all(c("message_update", "message_end", "tool_execution_start",
                    "tool_execution_end", "turn_end") %in% types))
  ends = Filter(function(x) identical(x$type, "message_end"), lapply(lines, json_decode))
  roles = vapply(ends, function(x) x$message$role, "")
  expect_true("toolResult" %in% roles)
})

test_that("no registered secret reaches the sink (acceptance 6)", {
  local_project()
  vault_reset()
  withr::defer(vault_reset())
  key = paste0("sk-ant-api03-", strrep("Q7x", 12), "AA")
  secret_register(key, "ANTHROPIC_API_KEY", source = "test")
  lines = jsonl_run(0L, script = list(paste("The key is", key, "and it must not leak.")))
  expect_gt(length(lines), 3L)
  expect_false(any(grepl(key, lines, fixed = TRUE)))
  expect_false(any(grepl(substr(key, 1L, 24L), lines, fixed = TRUE)))
})

test_that("the jsonl frontend streams a piped session until it settles", {
  local_project()
  local_gptr_options(record = "off")
  s = peter("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
  file = withr::local_tempfile(fileext = ".jsonl")
  con = file(file, open = "wb")
  res = jsonl_frontend_run(s, con = con)
  close(con)
  expect_identical(res, s)
  expect_identical(s$status, "idle")
  types = vapply(readLines(file, encoding = "UTF-8"), function(l) json_decode(l)$type, "",
                 USE.NAMES = FALSE)
  expect_identical(types[[length(types)]], "agent_end")
  expect_error(jsonl_frontend_run(NULL, con = stdout()), class = "gptr_error_invalid_argument")
})

test_that("peter(.stdin = TRUE, .opts = list(frontend = 'jsonl')) reads prompts, writes events", {
  local_project()
  local_gptr_options(record = "off")
  lines = c("hello", " {\"type\":\"prompt\",\"text\":\"again\"}", "/exit")
  local_mocked_bindings(console_stdin_open = function() textConnection(lines))
  fake = gptr_fake_provider(list("one", "two"))
  res = NULL
  out = utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, .opts = list(frontend = "jsonl"),
               envir = new.env())
  })
  expect_identical(res$turns, 2L)
  expect_identical(fake_requests(fake)[[2L]]$last_user, "again")
  decoded = lapply(out, json_decode)
  expect_true(all(vapply(decoded, function(x) is.character(x$type), NA)))
  expect_identical(sum(vapply(decoded, function(x) identical(x$type, "agent_end"), NA)), 2L)
  expect_false(any(grepl("^gptr ", out)))
})

test_that("a failed prompt of the jsonl frontend gives an error line and the loop goes on", {
  local_project()
  local_gptr_options(record = "off")
  lines = c("fail", "next")
  local_mocked_bindings(console_stdin_open = function() textConnection(lines))
  fake = gptr_fake_provider(list(list(error = "bad request", status = 400L), "fine"))
  out = utils::capture.output(peter(.stdin = TRUE, model = fake,
                                    .opts = list(frontend = "jsonl"), envir = new.env()))
  decoded = lapply(out, json_decode)
  types = vapply(decoded, function(x) x$type, "")
  expect_identical(sum(types == "error"), 1L)
  expect_identical(sum(types == "agent_end"), 2L)
  expect_identical(fake_requests(fake)[[2L]]$last_user, "next")
})

test_that("builtin:jsonl registers the jsonl frontend", {
  expect_false(is.null(registry_get("frontend", "jsonl")))
})
