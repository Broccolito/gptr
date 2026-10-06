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
