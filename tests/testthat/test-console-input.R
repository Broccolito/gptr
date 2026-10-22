# tests/testthat/test-console-input.R -- the composer of a terminal console (P28; IC-76, D-243):
# its pure key machine. CRAN runs this file (D-240).

# console_compose() on `chars` from the draft `draft` at time `now`; the completer knows a few
# full words and offers those starting with the trigger word
compose = function(chars, draft = "", now = 0, enter_kind = "steer", state = list(draft = draft)) {
  words = c("@mtcars", "@mtcars_copy", "/mode", "/model", "mtcars_copy", "peter$send")
  complete = function(line, end) {
    word = console_trigger(substr(line, 1L, end))
    words[startsWith(words, word)]
  }
  console_compose(state, chars, now, enter_kind, complete)
}

# Each case: the keys, the draft before, the draft after and the action; a difference names its
# case as 'draft + keys'
expect_keys = function(cases, enter_kind = "steer") {
  got = lapply(cases, function(x) {
    r = compose(x[[1L]], x[[2L]], enter_kind = enter_kind)
    list(r$state$draft, r$action)
  })
  names(got) = vapply(cases, function(x) encodeString(paste0(x[[2L]], " + ", x[[1L]])), "")
  expect_identical(got, stats::setNames(lapply(cases, `[`, 3:4), names(got)))
}

sent = function(kind, text) list(type = "send", kind = kind, text = text)

test_that("printable text is added at the draft's end; DEL, BS, Ctrl-U and Ctrl-W edit it", {
  expect_keys(list(
    list("use base R", "", "use base R", NULL),
    list("x", "use base R", "use base Rx", NULL),
    list("\177", "use base Rx", "use base R", NULL),
    list("\b", "use base Rx", "use base R", NULL),
    list("\177", "", "", NULL),
    list("\025", "use base R", "", NULL),
    list("\027", "use base R  ", "use base ", NULL),
    list("\027", "and plot it", "and plot ", NULL),
    list("typo\177\177\177\177ok", "", "ok", NULL)
  ))
})

test_that("a key is one character: UTF-8 and wide characters", {
  expect_keys(list(
    list("café", "", "café", NULL),
    list("\177", "café", "caf", NULL),
    list("数据", "plot ", "plot 数据", NULL),
    list("\177", "plot 数据", "plot 数", NULL),
    list("\027", "plot 数据", "plot ", NULL),
    list("\r", "plot 数据", "", sent("steer", "plot 数据"))
  ))
})

test_that("cursor keys and other sequences are dropped up to their final byte", {
  expect_keys(list(
    list("\033[D", "abc", "abc", NULL),
    list("\033[C", "abc", "abc", NULL),
    list("\033OH", "abc", "abc", NULL),
    list("\033[1;5C", "abc", "abc", NULL),
    list("\033[15~", "abc", "abc", NULL),
    list("\033b", "abc", "abc", NULL),
    list("\001\005\004", "abc", "abc", NULL),
    list("ab\033[Dc", "", "abc", NULL),
    list(paste0("\033", "é"), "", "é", NULL)
  ))
})

test_that("an escape sequence cut short is held for 50 ms, then dropped", {
  esc = compose("\033", "abc", now = 0)
  expect_identical(esc$state$draft, "abc")
  expect_identical(esc$state$esc, "\033")
  expect_null(esc$action)
  # completed in time: a cursor key, dropped
  r = compose("[D", state = esc$state, now = 0.01)
  expect_identical(r$state[c("draft", "esc")], list(draft = "abc", esc = ""))
  # still incomplete at 40 ms: held from the time its first byte came
  csi = compose("[1;", state = esc$state, now = 0.04)
  expect_identical(csi$state$esc, "\033[1;")
  expect_identical(csi$state$t, 0)
  r = compose("5C", state = csi$state, now = 0.045)
  expect_identical(r$state[c("draft", "esc")], list(draft = "abc", esc = ""))
  # at 60 ms a lone Esc is dropped: the next key is text, not part of a sequence
  r = compose("", state = esc$state, now = 0.06)
  expect_identical(r$state[c("draft", "esc")], list(draft = "abc", esc = ""))
  r = compose("d", state = esc$state, now = 0.06)
  expect_identical(r$state[c("draft", "esc")], list(draft = "abcd", esc = ""))
  r = compose("[A", state = compose("\033", now = 0)$state, now = 0.06)
  expect_identical(r$state$draft, "[A")
  expect_null(r$action)
  # a batch ending in a new sequence holds it from now
  r = compose("x\033[", "abc", now = 1)
  expect_identical(r$state, list(draft = "abcx", esc = "\033[", t = 1))
})

test_that("Up on an empty draft takes back; only as a batch of its own", {
  back = list(type = "take_back")
  expect_keys(list(
    list("\033[A", "", "", back),
    list("\033OA", "", "", back),
    list("\033[A", "abc", "abc", NULL),
    list("\033[Ax", "", "x", NULL),
    list("\033[A\033[A", "", "", NULL)
  ))
  r = compose("[A", state = compose("\033", now = 0)$state, now = 0.01)
  expect_identical(r$action, back)
})

test_that("Enter sends the draft; a batch holding newlines is one message (the paste rule)", {
  expect_keys(list(
    list("\r", "use base R", "", sent("steer", "use base R")),
    list("\n", "use base R", "", sent("steer", "use base R")),
    list("\r", "", "", NULL),
    list("\r", "   ", "", NULL),
    list("b\nc", "a", "c", sent("steer", "ab")),
    list("line 1\nline 2\n", "", "", sent("steer", "line 1\nline 2")),
    list("x = 1\r\ny = 2\rz", "", "z", sent("steer", "x = 1\ny = 2")),
    list("a\tb\n", "", "", sent("steer", "a\tb")),
    list("abc\n\177", "", "", sent("steer", "abc")),
    list("typo\025fixed\n", "", "", sent("steer", "fixed"))
  ))
  expect_keys(list(
    list("\r", "use base R", "", sent("follow_up", "use base R")),
    list("a\nb", "", "b", sent("follow_up", "a"))
  ), enter_kind = "follow_up")
})

test_that("/ and ! drafts are follow-ups, whatever the key", {
  expect_keys(list(
    list("\r", "/status", "", sent("follow_up", "/status")),
    list("\r", "  !x = 1", "", sent("follow_up", "  !x = 1")),
    list("!x = 1\nuse x\n", "", "", sent("follow_up", "!x = 1\nuse x")),
    list("\t", "/model gpt", "", sent("follow_up", "/model gpt"))
  ))
  expect_keys(list(
    list("\t", "/model gpt", "", sent("follow_up", "/model gpt")),
    list("\r", "!!plot(x)", "", sent("follow_up", "!!plot(x)"))
  ), enter_kind = "follow_up")
})

test_that("Tab completes a trigger word and never queues it; other drafts go as the other kind", {
  listed = function(...) list(type = "complete", candidates = c(...))
  expect_keys(list(
    list("\t", "use @mtc", "use @mtcars", NULL),
    list("\t", "use @mtcars", "use @mtcars", listed("@mtcars", "@mtcars_copy")),
    list("\t", "(@mtcars_", "(@mtcars_copy", NULL),
    list("\t", "/mo", "/mode", NULL),
    list("\t", "/mode", "/mode", listed("/mode", "/model")),
    list("\t", "!!summary(mtcars_c", "!!summary(mtcars_copy", NULL),
    list("\t", "ask peter$se", "ask peter$send", NULL),
    # a trigger word without a match: nothing happens
    list("\t", "use @zz", "use @zz", NULL),
    list("\t", "/status", "/status", NULL),
    list("\t", "!zz", "!zz", NULL),
    # natural language and other $ and @ uses are no trigger words
    list("\t", "summarise the da", "", sent("follow_up", "summarise the da")),
    list("\t", "mail a@b.com", "", sent("follow_up", "mail a@b.com")),
    list("\t", "cost is $5", "", sent("follow_up", "cost is $5")),
    list("\t", "use $name", "", sent("follow_up", "use $name")),
    list("\t", "x$y", "", sent("follow_up", "x$y")),
    list("\t", "wow! x", "", sent("follow_up", "wow! x")),
    list("\t", "", "", NULL)
  ))
  expect_keys(list(
    list("\t", "summarise the da", "", sent("steer", "summarise the da")),
    list("\t", "use @mtc", "use @mtcars", NULL)
  ), enter_kind = "follow_up")
})
