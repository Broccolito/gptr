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

# ---- Task 17: the live row ---------------------------------------------------------------------

# The live row's text for each state at `width`, as a named list a difference names
live_rows = function(states, width) {
  stats::setNames(lapply(states, console_live_row, width = width), names(states))
}

live_states = list(
  rstudio = list(what = "thinking", secs = 6, queued = 1, key = "Esc", pause = FALSE),
  menu = list(what = "r", secs = 65, key = "Ctrl-C", pause = TRUE),
  hint = list(what = "thinking", secs = 6, draft = ""),
  follow = list(what = "thinking", secs = 6, draft = "", enter = "follow_up"),
  queue = list(what = "thinking", secs = 6, queued = 2, draft = "",
               newest = list(kind = "steer", text = "use log(mpg)\ninstead")),
  draft = list(what = "thinking", secs = 6, queued = 1,
               draft = "and plot the residuals against the fitted values please"),
  question = list(what = "edit", secs = 11, question = TRUE, draft = "and plot the residu"),
  complete = list(what = "thinking", secs = 3, candidates = c("@mtcars", "@mtcars_copy"),
                  draft = "use @mtc")
)

test_that("the live row says what the run does, its queue and the person's draft (D-243)", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = TRUE)
  expect_identical(live_rows(live_states, 80L), list(
    rstudio = "▌ thinking 6s · 1 queued · esc stops",
    menu = "▌ r 1m 05s · ctrl-c pauses",
    hint = "▌ thinking 6s   enter steer · tab follow-up · ctrl-c pause",
    follow = "▌ thinking 6s   enter follow-up · tab steer · ctrl-c pause",
    queue = paste("▌ thinking 6s · 2 queued   ↳ steer · use log(mpg) instead",
                  "· ↑ edit"),
    draft = "▌ thinking 6s…   › and plot the residuals against the fitted values please",
    question = "▌ edit 11s · question waiting   › and plot the residu",
    complete = "▌ @mtcars  @mtcars_copy   › use @mtc"
  ))
  # one collapse rule: the status is cut from the right, down to the time; the draft keeps its tail
  expect_identical(live_rows(live_states, 40L), list(
    rstudio = "▌ thinking 6s · 1 queued · esc stops",
    menu = "▌ r 1m 05s · ctrl-c pauses",
    hint = "▌ thinking 6s   enter steer · tab f…",
    follow = "▌ thinking 6s   enter follow-up · t…",
    queue = "▌ thinking 6s · 2 queued   ↳ steer…",
    draft = "▌ 6s   › …t the fitted values please",
    question = "▌ edit 11s…   › and plot the residu",
    complete = "▌ @mtcars  @mtcars_copy   › use @mtc"
  ))
  expect_identical(live_rows(live_states, 30L), list(
    rstudio = "▌ thinking 6s · 1 queued…",
    menu = "▌ r 1m 05s · ctrl-c pauses",
    hint = "▌ thinking 6s   enter stee…",
    follow = "▌ thinking 6s   enter foll…",
    queue = "▌ thinking 6s · 2 queued…",
    draft = "▌ 6s   › …ed values please",
    question = "▌ 11s   › …plot the residu",
    complete = "▌ @mtcars  @…   › use @mtc"
  ))
  # a character outside ASCII counts two columns, so the row never wraps where they are wide
  wide = live_rows(list(a = list(secs = 0, draft = "数据 été αβ")), 20L)
  expect_identical(wide$a, "▌ 0s   › …αβ")
  expect_lte(live_fit(wide$a), 19L)
  expect_identical(console_live_row(list(secs = 0), 5L), "")
  withr::local_options(cli.unicode = FALSE)
  expect_identical(live_rows(live_states[c("queue", "draft")], 80L), list(
    queue = "# thinking 6s - 2 queued   -> steer - use log(mpg) instead - Up edit",
    draft = "# thinking 6s...   >> and plot the residuals against the fitted values please"
  ))
})

test_that("the live row's block is the agent's blue, its words dim and the draft ink (D-243)", {
  withr::local_options(cli.num_colors = 256L, cli.unicode = TRUE)
  expect_identical(console_live_row(live_states$question, 80L), paste0(
    "\033[38;5;67m▌\033[39m \033[38;5;244medit 11s · question waiting\033[39m",
    "   › and plot the residu"))
  withr::local_options(cli.num_colors = 16L)
  expect_identical(console_live_row(live_states$menu, 80L),
                   "\033[34m▌\033[39m \033[2mr 1m 05s · ctrl-c pauses\033[22m")
})

test_that("the live row is drawn with \\r and erased to the line end, or padded (D-243)", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = TRUE, cli.width = 40L)
  state = live_states$menu
  row = "▌ r 1m 05s · ctrl-c pauses"
  draws = function(cls) {
    lv = console_live(cls)
    c(written(function() lv$draw(state)), written(lv$clear), written(lv$clear))
  }
  # a T console: on the input band where the background is known, then the reset
  withr::local_options(cli.ansi = TRUE)
  local_mocked_bindings(front_end = function() "terminal")
  expect_identical(draws("T"), c(paste0("\r", row, "\033[K"), "\r\033[K", ""))
  withr::local_options(cli.num_colors = 256L)
  local_mocked_bindings(console_background = function() "dark")
  expect_identical(draws("T")[[1L]], paste0("\r\033[48;5;237m",
                                           console_live_row(state, 40L), "\033[K\033[0m"))
  withr::local_options(cli.num_colors = 1L, cli.ansi = FALSE)
  # RStudio honours \033[K: no padding stays in its transcript (visual review)
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(draws("L"), c(paste0("\r", row, "\033[K"), "\r\033[K", ""))
  # R.app, Rgui, TERM=dumb and Positron, whose console erases with spaces, pad to width - 1
  for (fe in c("rgui", "terminal", "positron")) {
    local_mocked_bindings(front_end = function() fe)
    blank = strrep(" ", 39L)
    expect_identical(draws("L"), c(paste0("\r", row, strrep(" ", 39L - nchar(row))),
                                   paste0("\r", blank, "\r"), ""), info = fe)
  }
})

test_that("a console write clears the live row and redraws it after its whole lines (D-243)", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = TRUE, cli.width = 40L, cli.ansi = TRUE)
  local_mocked_bindings(front_end = function() "terminal",
                        console_live_state = function(rec) live_states$menu)
  row = "\r▌ r 1m 05s · ctrl-c pauses\033[K"
  writes = function(...) written(function() for (x in list(...)) gptr_message_write(x, "stdout"))
  draw = function() written(function() the$live_row$draw())
  withr::defer(assign("live_row", NULL, envir = the))
  # the row is drawn and written at the sink written() opens
  the$live_row = console_live("T")
  the$live_row$sinks = sink.number() + 1L
  expect_identical(writes("x\n"), "x\n")
  expect_identical(draw(), row)
  expect_identical(writes("  a notice\n"), paste0("\r\033[K", "  a notice\n", row))
  expect_true(the$live_row$shown)
  # a partial line leaves the row cleared until the run next waits
  expect_identical(writes("partial"), "\r\033[Kpartial")
  expect_false(the$live_row$shown)
  expect_false(the$live_row$on)
  expect_identical(writes("\n"), "\n")
  # where the row is padded, the first write ends it: no spaces stay on the rows after it
  local_mocked_bindings(front_end = function() "rgui")
  withr::local_options(cli.ansi = FALSE)
  the$live_row = console_live("L")
  the$live_row$sinks = sink.number() + 1L
  draw()
  expect_identical(writes("  one\n", "  two\n"),
                   paste0("\r", strrep(" ", 39L), "\r  one\n  two\n"))
  expect_false(the$live_row$on)
  # text written into another sink (a capture in the agent's code) leaves the row alone
  the$live_row$on = TRUE
  draw()
  inner = NULL
  expect_identical(utils::capture.output({
    inner = writes("  captured\n")
  }), character())
  expect_identical(inner, "  captured\n")
  expect_true(the$live_row$shown)
})

test_that("console_class() decides the console's class by capability (D-243)", {
  local_mocked_bindings(gptr_is_interactive = function() TRUE, stdin_tty = function() TRUE,
                        is_windows = function() FALSE, front_end = function() "terminal")
  withr::local_envvar(RADIAN_VERSION = NA)
  withr::local_options(cli.ansi = TRUE, cli.dynamic = TRUE)
  expect_identical(console_class(), "T")
  withr::local_options(cli.ansi = FALSE)
  expect_identical(console_class(), "D")
  withr::with_envvar(c(RADIAN_VERSION = "0.6"), expect_identical(console_class(), "L"))
  local_mocked_bindings(front_end = function() "positron")
  expect_identical(console_class(), "L")
  local_mocked_bindings(front_end = function() "terminal", stdin_tty = function() FALSE)
  expect_identical(console_class(), "L")
  local_mocked_bindings(gptr_is_interactive = function() FALSE)
  expect_identical(console_class(), "P")
})

# ---- Task 19: a question waits for typing to pause ---------------------------------------------

test_that("a question is asked once no key came for a second (D-243)", {
  expect_true(ask_ready(NULL, 10))
  expect_false(ask_ready(10, 10))
  expect_false(ask_ready(9.5, 10))
  expect_false(ask_ready(9.01, 10))
  expect_true(ask_ready(9, 10))
  expect_true(ask_ready(2, 10))
})

# ---- Task 21: a draft left at a run's end stays in the composer --------------------------------

# The REPL reader's read at `peter> ` of the draft a run left (D-243): fd 0 gives `keys`, one batch
# per read and nothing after the last (a function in place of a batch signals Ctrl-C), and
# readline() answers `answers`: what the read returned and wrote, the prompts readline() showed,
# what went to the history, what stty was told and the draft after
idle_read = function(draft, keys, answers = character()) {
  stty = character()
  local_mocked_bindings(
    tty_modes = function(modes = "-g") {
      stty <<- c(stty, paste(modes, collapse = " "))
      if (identical(modes, "-g")) "SAVED" else character()
    },
    console_typed_chars = function(rd, wait) {
      if (!length(keys)) return("")
      k = keys[[1L]]
      keys <<- keys[-1L]
      if (is.function(k)) k() else k
    })
  rl = local_readline(answers)
  local_gptr_options(history = TRUE)
  rd = console_reader()
  rd$compose = list(draft = draft)
  x = NULL
  out = written(function() x <<- rd$read("peter> "))
  list(x = x, out = out, rows = term_rows(out), prompts = rl$prompts, kept = rl$kept, stty = stty,
       draft = rd$compose$draft)
}

keys_mode = "-icanon -echo -iexten min 1 time 0"

ctrl_c = function() {
  signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
}

test_that("a draft a run left is edited at the prompt; Enter returns it as readline would", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = TRUE, cli.width = 80L)
  # Up, Ctrl-D and Tab on plain text do nothing; the row is drawn again after every key
  r = idle_read("and label", list(" it", "\033[A", "\004", "\t", "x\177 the axes", "\r"))
  expect_identical(r$x, "and label it the axes")
  expect_identical(r$rows, c("peter> and label it the axes", ""))
  expect_identical(lengths(regmatches(r$out, gregexpr("\rpeter> and label it\033[K", r$out,
                                                      fixed = TRUE))), 4L)
  expect_identical(r$prompts, character())
  expect_identical(r$kept, character())
  expect_identical(r$stty, c("-g", keys_mode, "SAVED"))
  expect_identical(r$draft, "")
  # a draft wider than the row shows its tail; Enter writes the whole line
  withr::local_options(cli.width = 30L)
  r = idle_read("and label both of the axes", "\r")
  expect_match(r$out, "\rpeter> …bel both of the axes\033[K", fixed = TRUE)
  expect_identical(r$rows, c("peter> and label both of the axes", ""))
  # the row is on the input band where the background is known
  withr::local_options(cli.num_colors = 256L)
  local_mocked_bindings(console_background = function() "dark")
  r = idle_read("x", "\r")
  expect_match(r$out, "\r\033[48;5;237mpeter> x\033[K\033[0m", fixed = TRUE)
})

test_that("an emptied draft hands over to readline at the same prompt; Ctrl-C keeps it first", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = TRUE, cli.width = 80L)
  r = idle_read("ab", list("\177", "\025"), "/exit")
  expect_identical(r$x, "/exit")
  expect_identical(r$rows, "")
  expect_identical(r$prompts, "peter> ")
  expect_identical(r$kept, character())
  expect_identical(r$stty, c("-g", keys_mode, "SAVED"))
  # Ctrl-C adds the draft to the history and lists it, as Codex clears its composer
  r = idle_read("and plot", list(ctrl_c), "next")
  expect_identical(r$x, "next")
  expect_identical(r$rows, c(kept_line("and plot"), ""))
  expect_identical(r$prompts, "peter> ")
  expect_identical(r$kept, "and plot")
  expect_null(r$draft)
  expect_identical(r$stty, c("-g", keys_mode, "SAVED"))
})
