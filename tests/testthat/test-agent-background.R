# test-agent-background.R -- P21 background sessions (experimental; never run on CRAN).

test_that("bg_state() creates the background state once", {
  skip_on_cran()
  old = the$bg
  withr::defer({
    the$bg = old
  })
  the$bg = NULL
  st = bg_state()
  expect_true(is.environment(st))
  expect_identical(bg_state(), st)
  expect_identical(bg_ids(), character())
  expect_false(bg_ticking())
  expect_false(bg_has("s0123456789"))
  expect_false(bg_has(""))
  expect_null(bg_get(NA_character_))
})

test_that("bg_once() stops reactor_pump() after exactly one iteration", {
  skip_on_cran()
  until = bg_once()
  expect_false(until())
  expect_true(until())
  expect_true(until())
})

test_that("bg_clean() and bg_cut() make one safe line in any locale", {
  skip_on_cran()
  x = paste0("a\tb", intToUtf8(0x202e), "c", intToUtf8(0x200b), "d\u0007e")
  expect_identical(bg_clean(x), "a b c d e")
  expect_identical(bg_clean(NA_character_), "")
  expect_identical(bg_clean(character()), character())
  expect_identical(bg_clean("a\033\xff"), "a <ff>")
  cafe = intToUtf8(c(99L, 97L, 102L, 233L))
  expect_identical(charToRaw(bg_clean(cafe)), charToRaw(cafe))
  expect_identical(bg_cut("  load   the\ncounts ", 40L), "load the counts")
  expect_identical(bg_cut(strrep("x", 50), 10L), "xxxxxxx...")
})

test_that("bg_names_text() and bg_request_summary() build notice text", {
  skip_on_cran()
  expect_identical(bg_names_text(c("a", "b", "a")), "a, b")
  expect_identical(bg_names_text(letters[1:8]), "a, b, c, d, e, f and 2 more")
  expect_identical(bg_names_text(character()), "")
  expect_identical(bg_request_summary(list(tool = "r", summary = c("", "x = 1"))), "r: x = 1")
  expect_identical(bg_request_summary(list(tool = "write", reason = "level 2")), "write: level 2")
  expect_identical(bg_request_summary(list()), "tool: an action")
  expect_identical(bg_request_summary(list(tool = "r", summary = "x\xff")), "r: x<ff>")
})

test_that("bg_tools_mode() reads gptr.background_tools", {
  skip_on_cran()
  local_gptr_options(background_tools = NULL)
  expect_identical(bg_tools_mode(), "idle")
  local_gptr_options(background_tools = "wait")
  expect_identical(bg_tools_mode(), "wait")
  local_gptr_options(background_tools = "sometimes")
  expect_identical(bg_tools_mode(), "idle")
})

bg_fixture = function(.env = parent.frame()) {
  s = peter("background fixture", model = gptr_fake_provider(list("ok")), .run = FALSE,
            envir = new.env())
  id = s$id
  assign(id, s, envir = bg_state()$sessions)
  live = session_live(s)
  live$background = list(id = id, run = NULL, ui = character(), dropped_n = 0L, ask = NULL,
                         waiting = FALSE, opts = list(background = TRUE))
  withr::defer({
    the$bg = NULL
  }, envir = .env)
  s
}

bg_recording_ui = function(calls, .env = parent.frame()) {
  permission = function(request) {
    calls$n = calls$n + 1L
    list(decision = "allow", remember = NULL, feedback = NULL)
  }
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    1L
  }
  spec = gptr_spec("ui", "bgtest", has_ui = function() TRUE, select = select,
                   input = function(prompt, default = "", secret = FALSE) "typed",
                   questions = function(qs) list(answers = list(q1 = "yes"), cancelled = FALSE),
                   notify = function(text, level = "info") invisible(NULL),
                   permission = permission)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(off)
}

test_that("a session UI wrapper delegates outside idle ticks and never prompts during them", {
  skip_on_cran()
  calls = new.env()
  calls$n = 0L
  bg_recording_ui(calls)
  s = bg_fixture()
  ui = bg_ui_spec("bgtest", s$id)
  req = list(tool = "r", summary = "x = 1", reason = "level 1", session = s$id, turn = 1L)
  expect_s3_class(ui, "gptr_ui")
  expect_true(ui$has_ui())
  expect_identical(ui$permission(req)$decision, "allow")
  expect_identical(ui$input("name?"), "typed")
  expect_identical(calls$n, 1L)
  st = bg_state()
  st$ticking = TRUE
  ans = ui$permission(req)
  expect_true(ui$questions(list())$cancelled)
  expect_identical(ui$select("pick", c("a", "b")), NA_integer_)
  expect_identical(ui$input("name?"), NA_character_)
  st$ticking = FALSE
  expect_identical(ans$decision, "deny")
  expect_match(ans$feedback, "runs in the background", fixed = TRUE)
  expect_match(ans$feedback, "call the tool again with the same input", fixed = TRUE)
  expect_identical(calls$n, 1L)
  ask = session_live(s)$background$ask
  expect_identical(ask$what, "permission")
  expect_identical(ask$summary, "r: x = 1")
})

test_that("bg_install_ui() shadows every ui record for that session only", {
  skip_on_cran()
  calls = new.env()
  calls$n = 0L
  bg_recording_ui(calls)
  s = bg_fixture()
  ids = bg_install_ui(s$id)
  expect_true(length(ids) >= 1L)
  expect_identical(length(ids), length(registry_names("ui")))
  global = registry_get("ui", "bgtest")
  wrapped = registry_get("ui", "bgtest", session = s$id)
  expect_false(identical(wrapped, global))
  expect_identical(wrapped$permission(list(tool = "r", summary = "y = 2"))$decision, "allow")
  expect_identical(calls$n, 1L)
  for (rid in ids) registry_remove(rid)
  expect_identical(registry_get("ui", "bgtest", session = s$id), global)
})

test_that("bg_park() records the first ask only and never stops the run itself", {
  skip_on_cran()
  s = bg_fixture()
  run = run_start(s, NULL, opts = list())
  withr::defer(run_abort(run))
  expect_true(bg_park(s$id, "input", "Which file?"))
  expect_true(bg_park(s$id, "permission", "second"))
  ask = session_live(s)$background$ask
  expect_identical(ask$what, "input")
  expect_identical(ask$summary, "Which file?")
  expect_identical(s$status, "running")
  expect_false(bg_park("s_not_a_background_session", "input", "x"))
})

test_that("bg.register is a service provided by P21 and owned by builtin:background", {
  skip_on_cran()
  expect_true("builtin:background" %in% gptr_registry()$source)
  expect_null(registry_get("service", "bg.register"))
  expect_true(ext_service_has("bg.register"))
  expect_true(is.function(ext_service_get("bg.register")))
})

test_that("an ask tool call at an idle tick is blocked and recorded, never shown", {
  skip_on_cran()
  s = bg_fixture()
  ev = list(type = "tool_call", session = s$id, tool_name = "ask", tool_call_id = "c1",
            input = list())
  expect_null(bg_on_tool_call(ev, NULL))
  st = bg_state()
  st$ticking = TRUE
  out = bg_on_tool_call(ev, NULL)
  other = bg_on_tool_call(list(type = "tool_call", session = "s_other", tool_name = "ask"), NULL)
  st$ticking = FALSE
  expect_identical(out$decision, "block")
  expect_match(out$reason, "call the tool again with the same input", fixed = TRUE)
  expect_null(other)
  expect_identical(session_live(s)$background$ask$what, "questions")
})

test_that("without later, background runs fail with gptr_error_missing_package", {
  skip_on_cran()
  local_mocked_bindings(bg_has_later = function() FALSE)
  fake = gptr_fake_provider(list("ok"))
  s = peter("idle job", model = fake, .run = FALSE, envir = new.env())
  cnd = expect_error(bg_register(s), class = "gptr_error_missing_package")
  expect_identical(cnd$package, "later")
  expect_identical(cnd$feature, "background sessions")
  expect_identical(s$status, "idle")
  expect_error(peter("x", model = fake, envir = new.env(), background = TRUE),
               class = "gptr_error_missing_package")
  expect_false(bg_has(s$id))
})

test_that("bg_run_opts() keeps the options a resumed run needs, never a frame or a snapshot", {
  skip_on_cran()
  run = list(opts = list(max_turns = 5L, budget = list(tokens = 100), call = new.env(),
                         safety = list(can_prompt = TRUE), doc = list(path = "a.R"),
                         background = FALSE, timeout = 30))
  expect_identical(bg_run_opts(run), list(max_turns = 5L, budget = list(tokens = 100),
                                          timeout = 30, background = TRUE))
  expect_identical(bg_run_opts(list(opts = NULL)), list(background = TRUE))
})

test_that("bg_register() starts a queued session in the background (contract 7.21 example)", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  calls = new.env()
  calls$n = 0L
  bg_recording_ui(calls)
  s = peter("long job", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
           envir = new.env())
  res = withVisible(ext_service_get("bg.register")(s))
  expect_false(res$visible)
  expect_identical(res$value, s)
  expect_identical(s$status, "running")
  expect_true(isTRUE(session_live(s)$run$opts$background))
  expect_true(bg_has(s$id))
  expect_true(length(session_live(s)$background$ui) >= 1L)
  expect_true(isTRUE(session_live(s)$background$opts$background))
  jobs = gptr_jobs()
  row = jobs[jobs$id == s$id, , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(row$kind, "session")
  expect_match(row$name, "long job", fixed = TRUE)
  expect_identical(row$status, "running")
})

test_that("bg_register() marks a running foreground run (the pause menu's [b]ackground)", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = peter("foreground", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
           envir = new.env())
  run = run_start(s, NULL, opts = list())
  expect_false(isTRUE(run$opts$background))
  bg_register(s)
  expect_true(isTRUE(run$opts$background))
  expect_identical(session_live(s)$background$run, run$id)
})

test_that("an idle session without queued input cannot run in the background", {
  skip_on_cran()
  skip_if_not_installed("later")
  s = peter("done already", model = gptr_fake_provider(list("ok")), envir = new.env())
  expect_identical(s$status, "idle")
  cnd = expect_error(bg_register(s), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "s")
  expect_error(bg_register("not a session"), class = "gptr_error_invalid_argument")
  a = peter("stopped", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
           envir = new.env())
  run_abort(run_start(a, NULL))
  expect_error(bg_register(a), class = "gptr_error_invalid_argument")
  expect_identical(a$status, "aborted")
  expect_false(bg_has(a$id))
})

test_that("gptr_jobs(kill = TRUE) and bg_shutdown() stop background sessions", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  hang = gptr_fake_provider(list(list(hang = TRUE)))
  a = peter("first", model = hang, .run = FALSE, envir = new.env())
  b = peter("second", model = hang, .run = FALSE, envir = new.env())
  bg_register(a)
  bg_register(b)
  gptr_jobs(kill = TRUE)
  expect_identical(a$status, "aborted")
  expect_false(bg_has(a$id))
  expect_false(a$id %in% gptr_jobs()$id)
  expect_identical(b$status, "aborted")
  c1 = peter("third", model = hang, .run = FALSE, envir = new.env())
  bg_register(c1)
  bg_shutdown()
  expect_identical(c1$status, "aborted")
  expect_null(the$bg)
})

bg_pump_until = function(cond, timeout = 20) {
  t0 = Sys.time()
  while (!isTRUE(cond()) && as.numeric(difftime(Sys.time(), t0, units = "secs")) < timeout) {
    later::run_now(0.05)
  }
  isTRUE(cond())
}

bg_has_assistant = function(s) {
  "assistant" %in% vapply(s$messages, function(m) m$role, "")
}

test_that("a background run progresses while the test pumps later::run_now()", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_gptr_options(background_tools = "idle")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "x = 1"), delay = 0.1),
                                 list(text = "done", delay = 0.1)))
  e = new.env()
  s = peter("long job", model = fake, mode = "auto", envir = e, background = TRUE)
  expect_s3_class(s, "gptr_session")
  expect_identical(s$status, "running")
  expect_true(s$id %in% gptr_jobs()$id)
  expect_true(bg_pump_until(function() !identical(s$status, "running")))
  expect_identical(s$status, "idle")
  expect_identical(s$text, "done")
  expect_identical(e$x, 1)
  expect_identical(length(fake$log$requests), 2L)
  expect_true(bg_state()$ticks > 0L)
  expect_true(bg_pump_until(function() !bg_has(s$id)))
  expect_false(s$id %in% gptr_jobs()$id)
})

test_that("the background tick is a no-op while a reactor pump is on the stack", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = peter("hang", model = gptr_fake_provider(list(list(hang = TRUE))), envir = new.env(),
           background = TRUE)
  st = bg_state()
  before = st$ticks
  reactor_pump(until = function() {
    bg_callback()
    TRUE
  }, slice_ms = 0L, timeout = 5)
  expect_identical(st$ticks, before)
  bg_callback()
  expect_identical(st$ticks, before + 1L)
  expect_identical(s$status, "running")
})

test_that("a pipe into a running background session steers it after the tool result", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_gptr_options(background_tools = "wait")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "y = 2")), "used TPM"))
  e = new.env()
  s = peter("normalise the counts", model = fake, mode = "auto", envir = e, background = TRUE)
  expect_true(bg_pump_until(function() bg_has_assistant(s)))
  expect_identical(s$status, "running")
  expect_null(e$y)
  res = withVisible(s |> peter("Use TPM, not CPM"))
  expect_false(res$visible)
  expect_identical(res$value, s)
  expect_identical(s$status, "running")
  expect_identical(length(session_data(s)$queue$steer), 1L)
  gptr_wait(s, timeout = 20)
  expect_identical(s$status, "idle")
  expect_identical(e$y, 2)
  expect_identical(s$text, "used TPM")
  msgs = fake$log$requests[[2]]$messages
  roles = vapply(msgs, function(m) m$role, "")
  texts = vapply(msgs, msg_text, "")
  i_result = max(which(roles == "tool_result"))
  i_steer = which(grepl("Use TPM, not CPM", texts, fixed = TRUE))
  expect_identical(i_steer, i_result + 1L)
  expect_match(texts[[i_steer]],
               "The user sent this message while you were working: Use TPM, not CPM",
               fixed = TRUE)
})

test_that("gptr_cancel() aborts a background session and releases its job", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  fake = gptr_fake_provider(list(list(hang = TRUE)))
  s = peter("long task", model = fake, envir = new.env(), background = TRUE)
  expect_true(bg_pump_until(function() length(fake$log$requests) >= 1L))
  gptr_cancel(s)
  expect_identical(s$status, "aborted")
  local_gptr_options(quiet = FALSE)
  expect_message(expect_true(bg_pump_until(function() !bg_has(s$id))),
                 "finished with status aborted", class = "gptr_message_notice")
  expect_false(s$id %in% gptr_jobs()$id)
})

test_that("an unreferenced settled background session is collected", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = peter("short job", model = gptr_fake_provider(list("done")), envir = new.env(),
           background = TRUE)
  w = rlang::new_weakref(s)
  id = s$id
  expect_true(bg_pump_until(function() !bg_has(id)))
  expect_identical(rlang::wref_key(w)$status, "idle")
  peter("replace the last session", model = gptr_fake_provider(list("ok")), envir = new.env())
  rm(s)
  invisible(gc())
  invisible(gc())
  expect_null(rlang::wref_key(w))
})
