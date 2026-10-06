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
