# tests/testthat/test-console-typing.R -- lines typed while a console answer runs (P26 Task 3,
# IC-76): they steer the running agent (the `type_ahead` setting); /commands and !code wait.
source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# A terminal REPL whose fd 0 holds what `look()` returns at each look of the typing task; the
# paste joining of a macOS terminal stays off
local_typed = function(look, .env = parent.frame()) {
  testthat::local_mocked_bindings(repl_terminal = function(rs) TRUE,
                                  console_readline_tty = function() FALSE,
                                  console_typed_lines = function(rd, ...) look(), .env = .env)
}

# A look() returning `lines` once `when()` holds, nothing before or after
typed_once = function(lines, when) {
  force(when)
  function() {
    if (!length(lines) || !isTRUE(when())) return(character())
    x = lines
    lines <<- character()
    x
  }
}

# The REPL on a new session in mode auto with `answers` at its prompt: its output lines, its
# session and what went to the history
typing_console = function(fake, answers, tools = NULL, envir = new.env()) {
  box = local_readline(answers, .env = parent.frame())
  rs = repl_state(NULL, envir)
  rs$model = fake
  rs$mode = "auto"
  rs$tools = tools
  s = NULL
  out = utils::capture.output({
    s = repl_main(rs)
  })
  list(out = out, s = s, kept = box$kept)
}

# stty on fd 0 recorded in `log`; the saved modes are "SAVED"
local_stty = function(.env = parent.frame()) {
  box = new.env(parent = emptyenv())
  box$log = character()
  testthat::local_mocked_bindings(tty_modes = function(modes = "-g") {
    box$log = c(box$log, modes)
    if (identical(modes, "-g")) "SAVED" else character()
  }, .env = .env)
  box
}

# A T console (P28 Task 18): stty succeeds and the composer reads, at each look of the typing
# task, what `look()` returns from fd 0
local_keys = function(look, .env = parent.frame()) {
  local_live_console("T", .env = .env)
  testthat::local_mocked_bindings(console_typed_chars = function(rd, ...) look(), .env = .env)
  local_stty(.env = .env)
}

# A look() returning `batches` one per look once `when()` holds, "" before and after
keys_once = function(batches, when) {
  force(when)
  function() {
    if (!length(batches) || !isTRUE(when())) return("")
    x = batches[[1L]]
    batches <<- batches[-1L]
    x
  }
}

char_mode = c("-icanon", "-echo", "-iexten", "-isig", "min", "1", "time", "0")

last_message = function(req) req$messages[[length(req$messages)]]

relay = function(text) paste0("The user sent this message while you were working: ", text)

slow_first = function() gptr_fake_provider(list(list(text = "first", delay = 0.3), "second"))

test_that("a line typed while an answer runs steers the same run (IC-76, IC-55 source repl)", {
  skip_on_cran()
  local_console_test()
  fake = slow_first()
  local_typed(typed_once("use base R", function() length(fake_requests(fake)) == 1L))
  enqueue = session_enqueue
  sources = character()
  local_mocked_bindings(session_enqueue = function(s, text, ..., source = "api_user") {
    sources <<- c(sources, source)
    enqueue(s, text, ..., source = source)
  })
  res = typing_console(fake, c("go", "/exit"))
  expect_identical(sources, "repl")
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  msg = last_message(reqs[[2L]])
  expect_identical(msg$role, "operator")
  expect_identical(msg_text(msg), relay("use base R"))
  expect_identical(res$s$turns, 1L)
  expect_length(session_data(res$s)$queue$steer, 0L)
  expect_true(queue_line("steer", "use base R") %in% res$out)
  expect_false(any(grepl("[gptr] steering", res$out, fixed = TRUE)))
})

test_that("a delivered steer is the person's line at its boundary, before the next text (D-242)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  fake = slow_first()
  local_typed(typed_once(c("use base R", "and log2"),
                         function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  sym = console_style()
  queued = which(res$out == queue_line("steer", "use base R"))
  shown = which(res$out == paste0(sym$person, " use base R"))
  expect_length(queued, 1L)
  expect_length(shown, 1L)
  # a message of two lines: the later rows under the text, at column 0 as the person's
  expect_identical(res$out[c(queued, shown) + 1L],
                   paste0(strrep(" ", nchar(c(sym$queued, sym$person)) + 1L), "and log2"))
  expect_true(all(c(queued, which(res$out == "first")) < shown) &&
                shown < which(res$out == "second"))
})

test_that("the person's line is on the band; a queue line is dim and cut to three rows (D-245)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.num_colors = 256L, cli.width = 40L)
  # a T console's band; its probe at the REPL's start gets no answer (no stty), so it stays dark
  local_mocked_bindings(console_class = function() "T")
  old = the$background
  the$background = "dark"
  withr::defer(assign("background", old, envir = the))
  long = paste(rep("use base R", 12L), collapse = " ")
  fake = slow_first()
  local_typed(typed_once(long, function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  # the reset after the prompt's read (on the band, IC-82) starts the row after it
  res$out = sub("^\033\\[0m\033\\[K", "", res$out)
  sym = console_style()
  plain = cli::ansi_strip(res$out)
  q = which(startsWith(plain, queue_line("steer", "use")))
  expect_length(q, 1L)
  queued = res$out[q + 0:2]
  expect_true(all(startsWith(queued, "\033[38;5;244m")))
  expect_false(startsWith(res$out[[q + 3L]], "\033[38;5;244m"))
  expect_true(endsWith(cli::ansi_strip(queued[[3L]]), sym$ellipsis))
  # the delivered message whole, every row on the band, the later rows under the text
  shown = res$out[startsWith(res$out, "\033[48;5;237m")]
  expect_gt(length(shown), 3L)
  expect_true(all(endsWith(shown, "\033[K\033[0m")))
  k = nchar(sym$person) + 1L
  lead = substr(cli::ansi_strip(shown), 1L, k)
  expect_identical(lead, c(paste0(sym$person, " "), rep(strrep(" ", k), length(shown) - 1L)))
  expect_identical(paste(substring(cli::ansi_strip(shown), k + 1L), collapse = " "), long)
  expect_true(all(cli::ansi_nchar(c(queued, shown), type = "width") <= 39L))
})

test_that("a line queued while an answer streams waits for its block to end (visual review)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.width = 40L, cli.num_colors = 1L)
  words = paste(sprintf("word%02d", 1:40), collapse = " ")
  fake = gptr_fake_provider(list(list(text = words, chunk = 8L, gap = 0.03), "second"))
  # typed in three looks once the answer's first row is written, while the rest of it streams
  steers = c("use base R", "and log2", "and plot it")
  local_typed(keys_once(steers, function() {
    any(vapply(as.list(console_state()$active), function(r) identical(r$last, "text"), NA))
  }))
  res = typing_console(fake, c("go", "/exit"))
  whole = utils::capture.output(console_print_text(words))
  # the screen's rows: what follows the last carriage return of each line
  rows = sub(".*\r", "", res$out)
  first = grep("word01", rows, fixed = TRUE)
  last = grep("word40", rows, fixed = TRUE)
  # the paragraph is whole, never split at a queue line, and no waiting row comes back inside it;
  # the held queue lines give way to the deliveries, which say the same (steering review)
  expect_identical(rows[first:last], whole)
  expect_false(any(grepl("thinking", res$out[(first + 1L):last], fixed = TRUE)))
  expect_identical(rows[last + 1:4], c("", paste0(console_style()$person, " ", steers)))
  expect_false(any(startsWith(rows, queue_line("steer", ""))))
})

test_that("a held follow-up line stays; a held steer's shows before a tool (steering review)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.width = 40L, cli.num_colors = 1L)
  words = paste(sprintf("word%02d", 1:40), collapse = " ")
  streaming = function() {
    any(vapply(as.list(console_state()$active), function(r) identical(r$last, "text"), NA))
  }
  person = paste0(console_style()$person, " use base R")
  # a /command waits for the next prompt: its follow-up line shows, the steer's gives way
  fake = gptr_fake_provider(list(list(text = words, chunk = 8L, gap = 0.03), "second"))
  local_typed(typed_once(c("/status", "use base R"), streaming))
  rows = sub(".*\r", "", typing_console(fake, c("go", "/exit"))$out)
  last = grep("word40", rows, fixed = TRUE)
  expect_identical(rows[last + 1:3], c("", queue_line("follow-up", "/status"), person))
  # a tool block before the step boundary: the held line first, the delivery after the result
  fake = gptr_fake_provider(list(list(text = words, chunk = 8L, gap = 0.03, tool = "r",
                                      input = list(code = "zz = 1")), "second"))
  local_typed(typed_once("use base R", streaming))
  rows = sub(".*\r", "", typing_console(fake, c("go", "/exit"))$out)
  q = which(rows == queue_line("steer", "use base R"))
  tool = grep("zz = 1", rows, fixed = TRUE)
  expect_length(q, 1L)
  expect_true(grep("word40", rows, fixed = TRUE) < q && q < tool[[1L]] &&
                tool[[1L]] < which(rows == person))
})

test_that("a queue line is a block of its own: a blank row before the text after it", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.num_colors = 1L)
  fake = slow_first()
  local_typed(typed_once("use base R", function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  rows = sub(".*\r", "", res$out)
  q = which(rows == queue_line("steer", "use base R"))
  expect_length(q, 1L)
  expect_identical(rows[q + 1:2], c("", "  first"))
})

test_that("on a CLI route the queue line says the steer is sent after the CLI's answer", {
  skip_on_cran()
  local_console_test()
  f = local_fake_cli("claude", "toolstream")
  local_typed(typed_once("use base R", function() length(fake_log(f, "turn")) == 1L))
  res = typing_console(f$model, c("go", "/exit"))
  local_cli_cleanup(res$s)
  expect_true(paste0(queue_line("steer", "use base R"), console_style()$sep,
                     "after the CLI's answer") %in% res$out)
  roles = vapply(res$s$messages, function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "operator", "assistant"))
})

test_that("a T console's steer on a CLI route still says it waits for the CLI's answer (review)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.num_colors = 1L, cli.width = 80L)
  local_mocked_bindings(front_end = function() "terminal")
  f = local_fake_cli("claude", "toolstream")
  local_keys(keys_once("use base R\r", function() length(fake_log(f, "turn")) == 1L))
  res = typing_console(f$model, c("go", "/exit"))
  local_cli_cleanup(res$s)
  # the live row cannot say it, so the queue line is printed above the row
  rows = term_rows(paste(res$out, collapse = "\n"))
  expect_true(paste0(queue_line("steer", "use base R"), console_style()$sep,
                     "after the CLI's answer") %in% rows)
})

test_that("type_ahead = 'follow_up' sends the line as the next prompt, its own run (D-242)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(type_ahead = "follow_up", verbose = 2L)
  fake = slow_first()
  local_typed(typed_once("then plot it", function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  roles = vapply(reqs[[2L]]$messages, function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "user"))
  # the source of a second prompt typed at `peter> `, which pipes the session on
  msg = last_message(reqs[[2L]])
  expect_identical(msg$source, "pipe")
  expect_identical(msg_text(msg), "then plot it")
  expect_length(session_data(res$s)$queue$follow_up, 0L)
  # queued during run 1, echoed at the prompt after its status line, then run 2's status line
  sym = console_style()
  status = which(startsWith(res$out, paste0("done", sym$sep)))
  expect_length(status, 2L)
  at = match(c(queue_line("follow-up", "then plot it"), "peter[auto]> then plot it"), res$out)
  expect_identical(sort(c(at, status)), c(at[[1L]], status[[1L]], at[[2L]], status[[2L]]))
  expect_false(paste0(sym$person, " then plot it") %in% res$out)
})

test_that("follow-ups wait with the /commands and !code typed around them, in order (D-242)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(type_ahead = "follow_up")
  e = new.env()
  fake = slow_first()
  local_typed(typed_once(c("!x = 1", "use x", "!y = 2"),
                         function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"), envir = e)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), "use x")
  # `!x = 1` ran before the follow-up, so its note goes with it; `!y = 2` ran after it
  sent = json_encode(last_message(reqs[[2L]]))
  expect_match(sent, "> x = 1", fixed = TRUE)
  expect_no_match(sent, "y = 2", fixed = TRUE)
  expect_identical(c(e$x, e$y), c(1, 2))
  q = match(queue_line("follow-up", c("!x = 1", "use x", "!y = 2")), res$out)
  expect_false(anyNA(q) || is.unsorted(q))
  at = match(paste0("peter[auto]> ", c("!x = 1", "use x", "!y = 2")), res$out)
  expect_false(anyNA(at) || is.unsorted(at))
})

test_that("the pause menu's [f] in the REPL is the next prompt; a /, ! draft never steers", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(front_end = function() "terminal")
  e = new.env()
  fake = gptr_fake_provider(list(list(text = "first", delay = 0.6), "second"))
  # Ctrl-C twice while the first answer streams: [s] `!zz = 5`, then [f] `then plot it`
  pauses = 2L
  local_typed(function() {
    if (pauses > 0L && length(fake_requests(fake)) == 1L) {
      pauses <<- pauses - 1L
      withRestarts(signalCondition(structure(class = c("interrupt", "condition"),
                                             list(message = "", call = NULL))),
                   resume = function() NULL)
    }
    character()
  })
  res = typing_console(fake, c("go", "s", "!zz = 5", "f", "then plot it", "/exit"), envir = e)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  roles = vapply(reqs[[2L]]$messages, function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "user"))
  expect_identical(msg_text(last_message(reqs[[2L]])), "then plot it")
  expect_match(json_encode(last_message(reqs[[2L]])), "> zz = 5", fixed = TRUE)
  expect_identical(e$zz, 5)
  # each text under its question's title, its queue line without it
  expect_identical(sum(res$out == "-> follow-up"), 2L)
  at = match(paste0("peter[auto]> ", c("!zz = 5", "then plot it")), res$out)
  expect_false(anyNA(at) || is.unsorted(at))
})

test_that("a steer a run at max_turns did not take is the next prompt, run 2's user message", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(max_turns_console = 1L)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  fake = gptr_fake_provider(list(c(fake_tool("r", code = "zz = 1"), list(delay = 0.3)), "second"))
  local_typed(typed_once("use base R", function() length(fake_requests(fake)) == 1L))
  res = NULL
  err = utils::capture.output({
    res = typing_console(fake, c("go", "/exit"))
  }, type = "message")
  expect_true(any(grepl("(max_turns)", err, fixed = TRUE)))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  roles = vapply(reqs[[2L]]$messages, function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "tool_result", "user"))
  expect_identical(msg_text(last_message(reqs[[2L]])), "use base R")
  expect_true("peter[auto]> use base R" %in% res$out)
  expect_length(session_data(res$s)$queue$steer, 0L)
})

test_that("a line typed during a tool reaches the request right after its result (D-242)", {
  skip_on_cran()
  local_console_test()
  box = new.env(parent = emptyenv())
  slow = test_tool("slow", function(ctx) {
    Sys.sleep(0.25)
    box$ran = TRUE
    "slept"
  })
  fake = gptr_fake_provider(list(fake_tool("slow"), "after"))
  local_typed(typed_once("and also use mtcars", function() isTRUE(box$ran)))
  # the periodic typing task never ticks: the step boundary itself reads fd 0
  task = reactor_task
  local_mocked_bindings(reactor_task = function(fn, run = NULL) {
    if (identical(fn, console_typed)) "never" else task(fn, run)
  })
  typing_console(fake, c("go", "/exit"), tools = list(slow))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  roles = vapply(reqs[[2L]]$messages, function(m) m$role, "")
  expect_identical(utils::tail(roles, 2L), c("tool_result", "operator"))
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("and also use mtcars"))
})

# fd 0 of a terminal as one buffer: the typing task and readline() both take its `lines`, and
# readline() returns a waiting line at once (IC-75 sees 0.01 s), else the next of `answers`
local_fd0 = function(answers, .env = parent.frame()) {
  fd0 = new.env(parent = emptyenv())
  fd0$lines = character()
  fd0$answers = answers
  testthat::local_mocked_bindings(
    repl_terminal = function(rs) TRUE, console_readline_tty = function() FALSE,
    gptr_is_interactive = function() TRUE,
    console_typed_lines = function(rd, ...) {
      x = fd0$lines
      fd0$lines = character()
      x
    },
    gptr_readline = function(prompt = "", ...) {
      stale = length(fd0$lines) > 0L
      if (!stale && !length(fd0$answers)) return(NA_character_)
      x = if (stale) fd0$lines[[1L]] else fd0$answers[[1L]]
      if (stale) fd0$lines = fd0$lines[-1L] else fd0$answers = fd0$answers[-1L]
      the$readline_secs = if (stale) 0.01 else 1
      x
    }, .env = .env)
  withr::defer(assign("readline_secs", NULL, envir = the), envir = .env)
  fd0
}

test_that("a line typed during a tool steers when the next call's question follows it", {
  local_console_test()
  local_gptr_options(interactive = TRUE)
  fd0 = local_fd0(c("go", "y", "/exit"))
  peek = gptr_tool("peek", "Test tool peek", parameters = list(type = "object",
                                                                properties = json_obj()),
                   execute = function(input, ctx) {
                     fd0$lines = "use base R instead"
                     "seen"
                   }, annotations = list(read_only = TRUE))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tools(list("peek"), list("r", list(code = "zz = 2"))),
                                 "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$tools = list(peek)
  out = utils::capture.output(repl_main(rs))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(e$zz, 2)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("use base R instead"))
  # routed before the question reads, its line under the question and keys (visual review)
  expect_identical(match(queue_line("steer", "use base R instead"), out),
                   grep("? Allow r?", out, fixed = TRUE) + 2L)
})

test_that("/commands and !code typed during a run run after the answer; text still steers", {
  skip_on_cran()
  local_console_test()
  e = new.env()
  fake = slow_first()
  local_typed(typed_once(c("/status", "!x = 1", "and steer"),
                         function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"), envir = e)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("and steer"))
  expect_identical(e$x, 1)
  # each held line shows as a follow-up, in the order typed, before the steer typed after them
  q = match(c(queue_line("follow-up", "/status"), queue_line("follow-up", "!x = 1"),
              queue_line("steer", "and steer")), res$out)
  expect_false(anyNA(q) || is.unsorted(q))
  expect_false(any(grepl("after this answer", res$out, fixed = TRUE)))
  expect_true(all(c("peter[auto]> /status", "peter[auto]> !x = 1") %in% res$out))
  expect_true(any(startsWith(res$out, "session   ")))
})

test_that("lines typed in one batch (a paste) are one message", {
  skip_on_cran()
  local_console_test()
  fake = slow_first()
  local_typed(typed_once(c("a", "", "b"), function() length(fake_requests(fake)) == 1L))
  typing_console(fake, c("go", "/exit"))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("a\n\nb"))
})

test_that("an abort sends nothing queued: it goes to the history, listed once (D-242)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(history = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  e = new.env()
  fake = gptr_fake_provider(list(list(text = "first", delay = 5)))
  held = FALSE
  local_typed(function() {
    if (!length(fake_requests(fake))) return(character())
    if (!held) {
      held <<- TRUE
      return(c("/status", "!x = 1", "use base R"))
    }
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    character()
  })
  res = typing_console(fake, c("go", "/exit"), envir = e)
  expect_true(any(grepl("[gptr] aborted", res$out, fixed = TRUE)))
  # the prompt, the steer the abort dropped from the queue, the held lines, then the next input
  expect_identical(res$kept, c("go", "use base R", "/status", "!x = 1", "/exit"))
  notice = kept_line(c("use base R", "/status", "!x = 1"))
  expect_identical(sum(res$out == notice), 1L)
  expect_false(any(grepl("dropped", res$out, fixed = TRUE)))
  expect_length(fake_requests(fake), 1L)
  expect_null(e$x)
  expect_false("peter[auto]> /status" %in% res$out)
})

test_that("an abort's status line says aborted once; the kept list follows it, then a blank row", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(history = TRUE, verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  fake = gptr_fake_provider(list(list(text = "first", delay = 5)))
  held = FALSE
  local_typed(function() {
    if (!length(fake_requests(fake))) return(character())
    if (!held) {
      held <<- TRUE
      return("use base R")
    }
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    character()
  })
  res = typing_console(fake, c("go", "/exit"))
  rows = sub(".*\r", "", res$out)
  sym = console_style()
  status = grep(paste0("^  aborted", sym$sep), rows)
  expect_length(status, 1L)
  # the person's text at column 0, dim, as the queue lines (visual review)
  expect_identical(rows[status + 1:2], c(kept_line("use base R"), ""))
  expect_false(any(grepl("[gptr] aborted", rows, fixed = TRUE)))
})

test_that("after an error the queued steer is kept in the history, not sent with the next prompt", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(history = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  fake = gptr_fake_provider(list(list(error = "bad request", status = 400L, delay = 0.3), "second"))
  local_typed(typed_once("use base R", function() length(fake_requests(fake)) == 1L))
  res = NULL
  err = utils::capture.output({
    res = typing_console(fake, c("go", "next", "/exit"))
  }, type = "message")
  expect_true(any(grepl("bad request", err, fixed = TRUE)))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), "next")
  expect_no_match(json_encode(reqs[[2L]]$messages), "use base R", fixed = TRUE)
  expect_identical(res$kept, c("go", "use base R", "next", "/exit"))
  expect_true(kept_line("use base R") %in% res$out)
})

test_that("Ctrl-C at an approval prompt aborts the run and keeps the held lines in the history", {
  local_console_test()
  local_gptr_options(interactive = TRUE, history = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2", .text = "hmm")))
  local_typed(typed_once("!x = 1", function() length(fake_requests(fake)) == 1L))
  asks = 0L
  kept = character()
  local_mocked_bindings(readline_answer = function(prompt, ...) {
    asks <<- asks + 1L
    if (identical(prompt, ">> ")) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    if (asks == 1L) "go" else "/exit"
  }, gptr_readline = function(prompt = "", ...) readline_answer(prompt))
  local_mocked_bindings(timestamp = function(stamp, ...) kept <<- c(kept, stamp),
                        .package = "utils")
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_true(queue_line("follow-up", "!x = 1") %in% out)
  expect_identical(kept, c("go", "!x = 1", "/exit"))
  expect_true(kept_line("!x = 1") %in% out)
  expect_null(e$x)
  expect_null(e$zz)
})

test_that("a held !code line keeps the lines that complete it, also from a later batch", {
  skip_on_cran()
  local_console_test()
  e = new.env()
  fake = slow_first()
  batches = list(c("!f = function(x) {", "  x + 1"), c("}", "and steer"))
  local_typed(function() {
    if (length(fake_requests(fake)) != 1L || !length(batches)) return(character())
    x = batches[[1L]]
    batches <<- batches[-1L]
    x
  })
  res = typing_console(fake, c("go", "!g = 2", "/exit"), envir = e)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("and steer"))
  expect_identical(e$f(1), 2)
  expect_identical(e$g, 2)
  # a held !code line and the lines that continue it are one entry, its later rows under the text
  q = match(queue_line("follow-up", "!f = function(x) {"), res$out)
  expect_identical(res$out[q + 1L],
                   paste0(strrep(" ", nchar(console_style()$queued) + 1L), "  x + 1"))
})

test_that("no fd-0 reads outside a terminal REPL (.stdin, jsonl, peter() with a prompt)", {
  skip_on_cran()
  local_console_test()
  local_scripted_ui()
  tty = local_stty()
  box = new.env(parent = emptyenv())
  box$calls = 0L
  local_mocked_bindings(console_typed_lines = function(rd, ...) {
    box$calls = box$calls + 1L
    "never"
  }, gptr_is_interactive = function() TRUE, stdin_tty = function() TRUE)
  fake = gptr_fake_provider(function(req) list(text = "ok", delay = 0.2))
  local_console_stdin(c("hello", "/exit"))
  utils::capture.output(peter(.stdin = TRUE, model = fake, envir = new.env()))
  local_console_stdin('{"text": "hello"}')
  utils::capture.output(peter(.stdin = TRUE, model = fake, envir = new.env(),
                              .opts = list(frontend = "jsonl")))
  utils::capture.output(peter("hello", model = fake, envir = new.env()))
  local_mocked_bindings(stdin_tty = function() FALSE)
  typing_console(fake, c("hello", "/exit"))
  expect_length(fake_requests(fake), 4L)
  expect_identical(box$calls, 0L)
  expect_identical(tty$log, character())
})

test_that("a T console's call reads keys in character mode; its modes return after it (D-243)", {
  skip_on_cran()
  local_console_test()
  during = list()
  fake = gptr_fake_provider(function(req) {
    during[[length(during) + 1L]] <<- list(log = tty$log, saved = the$tty$saved)
    if (identical(req$last_user, "fail")) list(error = "bad key", status = 401L) else "ok"
  })
  tty = local_keys(function() "")
  err = utils::capture.output(invisible(typing_console(fake, c("go", "fail", "/exit"))),
                             type = "message")
  # Ctrl-C is a key the composer reads; opost stays on; `min 1` keeps a tool that reads stdin
  # blocking
  expect_identical(during[[1L]], list(log = c("-g", char_mode), saved = "SAVED"))
  expect_identical(during[[2L]]$log, c("-g", char_mode, "SAVED", "-g", char_mode))
  expect_true(any(startsWith(err, "Error: ")))
  expect_identical(tty$log, rep(c("-g", char_mode, "SAVED"), 2L))
  expect_null(the$tty)
  # a D console (TERM=dumb, Emacs) reads whole lines with the echo off (D-221)
  local_live_console("D")
  tty$log = character()
  typing_console(fake, c("go", "/exit"))
  expect_identical(tty$log, c("-g", "-echo", "SAVED"))
  expect_null(the$tty)
})

test_that("a terminal call's modes return after an interrupt, also one while stty sets them", {
  skip_on_cran()
  local_console_test()
  slow = gptr_fake_provider(list(list(text = "first", delay = 5)))
  tty = local_keys(function() {
    if (length(fake_requests(slow))) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    ""
  })
  res = typing_console(slow, c("go", "/exit"))
  expect_true(any(grepl("[gptr] aborted", res$out, fixed = TRUE)))
  expect_identical(tty$log, c("-g", char_mode, "SAVED"))
  expect_null(the$tty)
  tty$log = character()
  local_mocked_bindings(tty_modes = function(modes = "-g") {
    tty$log = c(tty$log, modes)
    if (identical(modes, char_mode)) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    if (identical(modes, "-g")) "SAVED"
  })
  fake = gptr_fake_provider(list("ok"))
  res = typing_console(fake, c("go", "/exit"))
  expect_true(any(grepl("[gptr] interrupted", res$out, fixed = TRUE)))
  expect_identical(tty$log, c("-g", char_mode, "SAVED"))
  expect_null(the$tty)
})

test_that("no character mode under radian, which owns its tty (D-243)", {
  local_console_test()
  tty = local_stty()
  withr::local_envvar(RADIAN_VERSION = "0.6.13")
  local_mocked_bindings(gptr_is_interactive = function() TRUE, stdin_tty = function() TRUE,
                        is_windows = function() FALSE, front_end = function() "terminal")
  withr::local_options(cli.ansi = TRUE, cli.dynamic = TRUE)
  typing_console(gptr_fake_provider(list("ok")), c("go", "/exit"))
  expect_identical(tty$log, character())
})

test_that("a question during a terminal call reads with the saved modes, then the call's", {
  tty = local_stty()
  withr::defer(assign("tty", NULL, envir = the))
  read = function(prompt) {
    tty$log = c(tty$log, paste0("read ", prompt))
    "y"
  }
  the$tty = list2env(list(saved = "SAVED", set = char_mode))
  expect_identical(gptr_readline("allow? ", read), "y")
  expect_identical(tty$log, c("SAVED", "read allow? ", char_mode))
  the$tty = NULL
  tty$log = character()
  expect_identical(gptr_readline("peter> ", read), "y")
  expect_identical(tty$log, "read peter> ")
})

test_that("a terminal call's question reads in the saved modes from before its rows (review)", {
  local_console_test()
  withr::defer(assign("tty", NULL, envir = the))
  # stty and the rows in the order the terminal gets them
  local_mocked_bindings(tty_modes = function(modes = "-g") cat("<stty", modes, ">\n"))
  rl = local_readline("y")
  the$tty = list2env(list(saved = "SAVED", set = char_mode, keys = TRUE))
  ans = NULL
  req = list(tool = "r", input = list(code = "zz = 1"), risk = list(level = 2L))
  out = utils::capture.output({
    ans = ui_console_permission(req)
  })
  expect_identical(ans$decision, "allow")
  stty = grep("^<stty", out)
  expect_identical(out[stty], c("<stty SAVED >", paste("<stty", paste(char_mode, collapse = " "),
                                                      ">")))
  # the saved modes come before the question's first row, the call's after its answer
  expect_lt(stty[[1L]], min(grep("Allow r?", out, fixed = TRUE)))
  expect_identical(stty[[2L]], length(out))
})

test_that("a T console's keys edit the draft on the live row; Enter steers (D-242, D-243)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.num_colors = 1L,
                       cli.unicode = TRUE, cli.width = 80L)
  local_mocked_bindings(front_end = function() "terminal")
  fake = gptr_fake_provider(list(list(text = "first", delay = 0.6), "second"))
  local_keys(keys_once(c("use base", " R\r"), function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("use base R"))
  # the draft after the person's chevron, then the queue on the row: the row is the queue view,
  # so no queue line is printed while it shows
  sym = console_style()
  bytes = paste(res$out, collapse = "\n")
  expect_match(bytes, paste0("   ", sym$person, " use base\033[K"), fixed = TRUE)
  expect_match(bytes, paste0(" 1 queued   ", sym$queued, " steer", sym$sep, "use base R",
                             sym$sep, sym$up, " edit\033[K"), fixed = TRUE)
  rows = term_rows(bytes)
  expect_false(queue_line("steer", "use base R") %in% rows)
  expect_identical(sum(rows == paste0(sym$person, " use base R")), 1L)
})

test_that("Tab completes a trigger word; several show on the live row until a key (IC-81)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.num_colors = 1L,
                       cli.unicode = TRUE, cli.width = 80L)
  local_mocked_bindings(front_end = function() "terminal")
  # a reader that completes, as on a readline tty (IC-81)
  reader = console_reader
  local_mocked_bindings(console_reader = function(...) {
    rd = reader(...)
    rd$complete = TRUE
    rd
  })
  fake = gptr_fake_provider(list(list(text = "first", delay = 1), "second"))
  local_keys(keys_once(c("use @mtc", "\t", "\025/mo", "\t", "\t", "l", "\025"),
                       function() length(fake_requests(fake)) == 1L))
  env = new.env()
  env$mtcars_copy = mtcars
  res = typing_console(fake, c("go", "/exit"), envir = env)
  expect_length(fake_requests(fake), 1L)
  sym = console_style()
  bytes = paste(res$out, collapse = "\n")
  expect_match(bytes, paste0(sym$person, " use @mtcars_copy\033[K"), fixed = TRUE)
  expect_match(bytes, paste0(sym$person, " /mode\033[K"), fixed = TRUE)
  # the candidates replace the status words, the draft where it was, until the next key
  expect_match(bytes, paste0("\r", sym$agent, " /mode  /model   ", sym$person, " /mode\033[K"),
               fixed = TRUE)
  # and the draft returns to its column after them, after the hint of a / draft (D-244)
  expect_match(bytes, paste0("\r", sym$agent, " thinking 0s   runs after this answer   ",
                             sym$person, " /model\033[K"), fixed = TRUE)
  # completion never queues: one request, nothing kept
  expect_identical(res$kept, character())
})

test_that("Tab sends a follow-up, the next prompt; Up takes it back and Ctrl-U discards it", {
  skip_on_cran()
  local_console_test()
  fake = gptr_fake_provider(function(req) {
    list(text = paste("got", req$last_user), delay = if (req$n == 1L) 0.6 else 0)
  })
  local_keys(keys_once(c("then plot", "\t", "oops", "\t", "\033[A", "\025"),
                       function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  last_user = vapply(fake_requests(fake), function(r) r$last_user, "")
  expect_identical(last_user, c("go", "then plot"))
  expect_true("peter[auto]> then plot" %in% res$out)
  expect_false("peter[auto]> oops" %in% res$out)
})

test_that("Ctrl-C is a key the composer reads: it pauses after the keys before it (review)", {
  local_console_test()
  s = session_new("fake/fake-1", "auto", home = new.env())
  rs = repl_state(s, new.env())
  rs$reader = console_reader()
  rs$sending = quote(peter())
  .gptr_repl = rs
  # a calling handler resumes, as the pause menu's [c] does, after it read the keys after Ctrl-C
  # (`read`) or none of them (steering review)
  paused = function(chars, read = FALSE) {
    seen = NULL
    resume = function(e) {
      seen <<- list(draft = rs$reader$compose$draft, after = rs$reader$after_interrupt)
      if (read) rs$reader$after_interrupt = ""
      invokeRestart("resume")
    }
    utils::capture.output(withCallingHandlers(console_keys(rs$reader, s, chars),
                                              interrupt = resume))
    seen
  }
  # the keys after Ctrl-C are the pause menu's (console_ahead())
  expect_identical(paused("use base\003s\r", read = TRUE), list(draft = "use base", after = "s\r"))
  expect_identical(rs$reader$compose$draft, "use base")
  # a message sent before Ctrl-C in the same batch is queued first; a second Ctrl-C is dropped,
  # and the keys the menu did not read are typed after it
  expect_identical(paused(" R\r\003and\003 plot"), list(draft = "", after = "and plot"))
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "use base R")
  expect_identical(rs$reader$compose$draft, "and plot")
  expect_identical(rs$reader$after_interrupt, "")
})

test_that("keys read with Ctrl-C that no question took wait at the prompt (steering review)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(history = TRUE, interactive = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE, front_end = function() "terminal")
  fake = gptr_fake_provider(list(list(text = "first", delay = 5)))
  # [a] read with Ctrl-C aborts; the text after it is the prompt's draft, never a later answer
  local_keys(keys_once("\003a\rnext please", function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  expect_length(fake_requests(fake), 1L)
  expect_true(paste0(console_style()$person, " a") %in% res$out)
  # the prompt's editor showed it, then handed it to readline, kept in the history
  expect_true(any(endsWith(res$out, paste0("peter[auto]> next please\033[K\r\033[K",
                                           kept_line("next please")))))
  expect_identical(res$kept, c("go", "next please", "/exit"))
})

test_that("in-process R code runs with isig on, so Ctrl-C interrupts it (review)", {
  skip_on_cran()
  local_console_test()
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "zz = 1")), "done"))
  tty = local_keys(function() "")
  typing_console(fake, c("go", "/exit"))
  expect_identical(tty$log, c("-g", char_mode, "isig", "-isig", "SAVED"))
})

test_that("Up takes back the newest message the person queued, of either kind (D-242)", {
  local_console_test()
  s = session_new("fake/fake-1", "auto", home = new.env())
  rs = repl_state(s, new.env())
  rs$reader = console_reader()
  rs$sending = quote(peter())
  keys = function(...) {
    .gptr_repl = rs
    for (k in c(...)) console_keys(rs$reader, s, k)
  }
  newest = function() console_newest(s, rs$reader)
  draft = function() rs$reader$compose$draft
  utils::capture.output({
    keys("use base R\r", "then plot", "\t")
    expect_identical(newest(), list(kind = "follow_up", text = "then plot"))
    keys("\033[A")
    expect_identical(draft(), "then plot")
    expect_length(rs$reader$typed, 0L)
    expect_identical(newest(), list(kind = "steer", text = "use base R"))
    keys("\025", "\033[A")
    expect_identical(draft(), "use base R")
    expect_null(newest())
    expect_length(session_data(s)$queue$steer, 0L)
    # a steer sent after a follow-up is the newest; Up on a draft takes back nothing
    keys("\025", "then plot", "\t", "use log\r", "x", "\033[A")
    expect_identical(newest(), list(kind = "steer", text = "use log"))
    expect_identical(draft(), "x")
  })
})

test_that("keys read on the polling beat are a paste; after a stall they are typed (review)", {
  local_console_test()
  s = session_new("fake/fake-1", "auto", home = new.env())
  rs = repl_state(s, new.env())
  rs$reader = console_reader()
  rs$sending = quote(peter())
  clock = 0
  local_mocked_bindings(reactor_now = function() clock)
  read = function(t, chars) {
    clock <<- t
    .gptr_repl = rs
    console_keys(rs$reader, s, chars)
  }
  steers = function() vapply(session_data(s)$queue$steer, function(it) it$text, "")
  utils::capture.output({
    # a run's first read is typed: `a` goes, `b` is the draft
    read(0, "a\rb")
    expect_identical(steers(), "a")
    expect_identical(rs$reader$compose$draft, "b")
    # 0.05 s after the last read, an empty one too, a newline and more text are a paste
    read(0.05, "")
    read(0.1, "\rc\rd")
    expect_identical(steers(), "a")
    expect_identical(rs$reader$compose$draft, "b\nc\nd")
    read(0.15, "\r")
    expect_identical(steers(), c("a", "b\nc\nd"))
    # the same batch after a 2 s stall (keys piled up during an in-process tool) is typed
    read(2.15, "a\rb")
    expect_identical(steers(), c("a", "b\nc\nd", "a"))
    expect_identical(rs$reader$compose$draft, "b")
  })
})

test_that("a draft a run left waits for the follow-ups, then continues at the prompt (D-243)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(history = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  # it waits through the follow-up's run, then Enter at the prompt sends it, echoed there
  fake = gptr_fake_provider(list(list(text = "first", delay = 0.6), "second", "third"))
  run = keys_once(c("then plot", "\t", "and label it"),
                  function() length(fake_requests(fake)) == 1L)
  idle = keys_once("\r", function() length(fake_requests(fake)) == 2L)
  local_keys(function() paste0(run(), if (is.null(console_repl_prompt())) idle()))
  res = typing_console(fake, c("go", "/exit"))
  last_user = vapply(fake_requests(fake), function(r) r$last_user, "")
  expect_identical(last_user, c("go", "then plot", "and label it"))
  expect_identical(res$kept, c("go", "then plot", "and label it", "/exit"))
  rows = term_rows(paste(res$out, collapse = "\n"))
  expect_identical(sum(rows == "peter[auto]> and label it"), 1L)
  expect_false(kept_line("and label it") %in% rows)
  # after an abort it joins the list of what was queued and not sent
  slow = gptr_fake_provider(list(list(text = "first", delay = 5)))
  looks = 0L
  local_keys(function() {
    if (!length(fake_requests(slow))) return("")
    looks <<- looks + 1L
    if (looks <= 2L) return(c("use base R\r", "and plot")[[looks]])
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    ""
  })
  res = typing_console(slow, c("go", "/exit"))
  expect_identical(res$kept, c("go", "use base R", "and plot", "/exit"))
  expect_identical(sum(res$out == kept_line(c("use base R", "and plot"))), 1L)
})

test_that("repl_terminal() needs an interactive tty REPL and ignores the front end", {
  rs = repl_state(NULL, new.env())
  local_mocked_bindings(gptr_is_interactive = function() TRUE, stdin_tty = function() TRUE,
                        front_end = function() "rstudio")
  expect_identical(repl_terminal(rs), !is_windows())
  rs$stdin = TRUE
  expect_false(repl_terminal(rs))
  rs$stdin = FALSE
  local_mocked_bindings(stdin_tty = function() FALSE)
  expect_false(repl_terminal(rs))
})

test_that("the fd-0 reader returns complete lines, survives Ctrl-D and a /dev/null stdin", {
  skip_on_cran()
  skip_on_os("windows")
  dir = withr::local_tempdir("gptr-typing-")
  child = file.path(dir, "child.R")
  writeLines(c(
    "as_utf8 = enc2utf8",
    paste("console_typed_chars =", paste(deparse(console_typed_chars), collapse = "\n")),
    paste("console_typed_lines =", paste(deparse(console_typed_lines), collapse = "\n")),
    paste("console_typed_split =", paste(deparse(console_typed_split), collapse = "\n")),
    "rd = new.env()",
    "if (!isatty(stdin())) {",
    "  for (k in 1:2) {",
    "    t0 = proc.time()[['elapsed']]",
    "    n = length(console_typed_lines(rd, 0L))",
    "    cat(sprintf('DEVNULL %d in %.2f s\\n', n, proc.time()[['elapsed']] - t0))",
    "  }",
    "  quit(save = 'no')",
    "}",
    "cat('READY\\n')",
    "repeat {",
    "  x = console_typed_lines(rd, 0L)",
    "  if (length(x)) cat(sprintf('GOT[%s]\\n', paste(x, collapse = '|')))",
    "  if ('four' %in% x) break",
    "  Sys.sleep(0.05)",
    "}",
    "cat('CHILD DONE\\n')"
  ), child)
  rscript = file.path(R.home("bin"), "Rscript")
  env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  p = processx::process$new(rscript, c("--vanilla", child), pty = TRUE, env = env, cleanup = TRUE)
  st = new.env(parent = emptyenv())
  st$out = ""
  # a pty child exits only once its output is read: p$kill() would wait for it forever
  withr::defer({
    if (p$is_alive()) p$signal(tools::SIGKILL)
    deadline = Sys.time() + 10
    while (p$is_alive() && Sys.time() < deadline) {
      p$poll_io(100L)
      p$read_output()
    }
  })
  wait_for = function(x, timeout = 30) {
    deadline = Sys.time() + timeout
    while (!grepl(x, st$out, fixed = TRUE) && p$is_alive() && Sys.time() < deadline) {
      p$poll_io(200L)
      st$out = paste0(st$out, p$read_output())
    }
    grepl(x, st$out, fixed = TRUE)
  }
  expect_true(wait_for("READY"))
  # processx writes text in the native encoding, which holds the check mark only in UTF-8
  two = if (isTRUE(l10n_info()[["UTF-8"]])) "two \u2713" else "two"
  p$write_input(paste0("one\n", two, "\nthr"))
  expect_true(wait_for(paste0("GOT[one|", two, "]")))
  # the partial "thr" stays in the terminal's line until Ctrl-D (or Enter) ends it
  expect_false(wait_for("GOT[thr", timeout = 1))
  p$write_input("\004")
  expect_true(wait_for("GOT[thr]"))
  # Ctrl-D on an empty line is an end of input: nothing is read and fd 0 is opened again
  p$write_input("\004")
  Sys.sleep(0.3)
  p$write_input("four\n")
  expect_true(wait_for("CHILD DONE"))
  expect_true(grepl("GOT[four]", st$out, fixed = TRUE))
  expect_false(grepl("GOT[]", st$out, fixed = TRUE))
  # stdin from /dev/null polls ready at once and reads nothing, without a wait
  q = processx::run(rscript, c("--vanilla", child), env = env, error_on_status = FALSE,
                    timeout = 60)
  got = regmatches(q$stdout, gregexpr("DEVNULL 0 in [0-9.]+ s", q$stdout))[[1L]]
  expect_length(got, 2L)
  expect_true(all(as.numeric(sub(".* in ([0-9.]+) s", "\\1", got)) < 0.5))
})

test_that("a terminal: the draft shows on the live row as text streams; Enter steers (D-243)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:60), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$n == 1L) return(list(text = long, chunk = 8L, gap = 0.05, tool = 'r',",
    "                               input = list(code = 'zz = 1')))",
    "  if (req$n == 3L) return(list(text = long, chunk = 8L, gap = 0.05))",
    "  roles = vapply(req$messages, function(m) m$role, '')",
    "  paste0('REQ ', paste(roles, collapse = ','), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "\u203a" else ">>"
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("steer me")
  expect_true(pty$wait(paste0(person, " steer me")))
  # the row is drawn again under each streamed row, the draft after the chevron
  expect_true(pty$wait("w30abc"))
  expect_true(pty$wait(paste0(person, " steer me")))
  pty$send("\r")
  expect_true(pty$wait("1 queued"))
  # delivered at the boundary after the tool's result, as the agent's next request reads it
  expect_true(pty$wait(paste0(person, " steer me\r\n")))
  expect_true(pty$wait("REQ user,assistant,tool_result,operator END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("TWO\r")
  expect_true(pty$wait("END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  # the row is the queue view: no queue line
  expect_identical(pty$seen(paste0(queue_line("steer", "steer me", utf8), "\r\n")), 0L)
  # the screen's rows (escapes dropped, a row redrawn after "\r" kept as redrawn): the streamed
  # answer reads as the undisturbed one of the second prompt, the draft never in it
  rows = strsplit(gsub("\033\\[[0-9;?]*[A-Za-z]", "", pty$all), "\n", fixed = TRUE)[[1L]]
  text = gsub("\\s+", " ", paste(sub("^.*\r", "", sub("\r$", "", rows)), collapse = " "))
  answers = gsub(" ", "", regmatches(text, gregexpr("BEGIN.*?END", text, perl = TRUE))[[1L]])
  expect_length(answers, 2L)
  expect_identical(answers[[1L]], answers[[2L]])
})

test_that("a terminal: a paste during a run is one draft; Enter sends it as one steer (review)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$n == 1L) return(list(text = 'first', delay = 4))",
    "  ops = Filter(function(m) identical(m$role, 'operator'), req$messages)",
    "  text = sub('^.*working: ', '', gptr:::msg_text(ops[[1L]]))",
    "  paste0('REQ ', length(ops), ' [', gsub('\\n', '/', text), ']')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  person = if (l10n_info()[["UTF-8"]]) "\u203a" else ">>"
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("thinking"))
  # on the polling beat, as the run goes
  Sys.sleep(0.5)
  pty$send("a\rb\rc")
  expect_true(pty$wait(paste0(person, " a b c")))
  expect_identical(pty$seen("queued"), 0L)
  pty$send("\r")
  expect_true(pty$wait("1 queued"))
  expect_true(pty$wait("REQ 1 [a/b/c]"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("REQ "), 1L)
})

test_that("a terminal: during a sub-agent the row ticks and steers; its r call waits (review)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L)",
    "busy = 'local({ t0 = proc.time()[[3]]; while (proc.time()[[3]] - t0 < 3) NULL }); 32L'",
    "kid = gptr_fake_provider(list(list(text = 'counting', tool = 'r', input = list(code = busy)),",
    "                              list(text = 'There are 32 cars.', delay = 4)), name = 'kid')",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$n == 1L) return(list(text = 'Starting.', tool = 'r',",
    "                               input = list(code = 'k = peter(\"count\", model = kid); 1L')))",
    "  roles = vapply(req$messages, function(m) m$role, '')",
    "  paste0('REQ ', paste(roles, collapse = ','), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  sep = if (utf8) " \u00b7 " else " - "
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("(kid/kid-1) started"))
  # the sub-agent's r call evaluates in this process: keys wait
  expect_true(pty$wait(paste0("sub-agent 'count' #1", sep, "keys show when r returns")))
  # it waits for its model: the row ticks and reads keys, which steer the parent
  expect_true(pty$wait("enter steer"))
  pty$send("s11")
  expect_true(pty$wait(paste0(if (utf8) "\u203a" else ">>", " s11")))
  pty$send("\r")
  expect_true(pty$wait(queue_line("steer", "s11", utf8)))
  expect_true(pty$wait("#1 done"))
  expect_true(pty$wait("REQ user,assistant,tool_result,operator END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  shown = gsub("\033\\[[0-9;?]*[A-Za-z]", "", pty$all)
  kid = regmatches(shown, regexpr("\\(kid/kid-1\\) started.*#1 done", shown))
  expect_false(grepl("keys show when sub-agent", kid, fixed = TRUE))
  clocks = regmatches(kid, gregexpr("sub-agent 'count' #1 [0-9]+s", kid))[[1L]]
  expect_gt(length(unique(clocks)), 1L)
})

test_that("a terminal: Tab queues a follow-up, a second run; Up takes back, Ctrl-U discards", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:80), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (identical(req$last_user, 'ONE')) return(list(text = long, chunk = 8L, gap = 0.05))",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "\u203a" else ">>"
  follow = queue_line("follow-up", "", utf8)
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  # each key as a batch of its own, once the row shows the one before
  pty$send("next please")
  expect_true(pty$wait(paste0(person, " next please")))
  pty$send("\t")
  expect_true(pty$wait(paste0(follow, "next please")))
  pty$send("oops")
  expect_true(pty$wait(paste0(person, " oops")))
  pty$send("\t")
  expect_true(pty$wait(paste0("2 queued   ", follow, "oops")))
  pty$send("\033[A")
  expect_true(pty$wait(paste0("1 queued   ", person, " oops")))
  pty$send("\025")
  expect_true(pty$wait(paste0(follow, "next please")))
  expect_true(pty$wait("END"))
  expect_true(pty$wait("peter[auto]> next please"))
  expect_true(pty$wait("REQ user: next please END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("REQ user: "), 1L)
  expect_identical(pty$seen("oops END"), 0L)
})

test_that("a terminal: a draft survives Ctrl-C and the pause menu (P28 G, D-243)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:80), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (identical(m$role, 'user')) return(list(text = long, chunk = 8L, gap = 0.05))",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  person = if (l10n_info()[["UTF-8"]]) "›" else ">>"
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait(paste0(person, " use base R")))
  # Ctrl-C: the menu is a console question read at the person's chevron, its answer empty
  pty$send("\003")
  expect_true(pty$wait("? Paused"))
  expect_true(pty$wait("c continue"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  # [c]: the stream goes on and the draft is back on the live row; Enter steers with it
  pty$send("c\r")
  expect_true(pty$wait(paste0(person, " use base R")))
  pty$send("\r")
  expect_true(pty$wait("END"))
  # the relay, wrapped at 60 columns
  expect_true(pty$wait(paste("REQ operator:", substr(relay(""), 1L, 40L))))
  expect_true(pty$wait("use base R END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("continuing"), 0L)
})

test_that("a terminal: keys read with Ctrl-C answer the pause menu (steering review)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:80), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (identical(m$role, 'user')) return(list(text = long, chunk = 8L, gap = 0.05))",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "›" else ">>"
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  # Ctrl-C, s and Enter in one read, as under load: the s answers the menu, echoed at its chevron
  pty$send("\003s\r")
  expect_true(pty$wait("? Paused"))
  expect_true(pty$wait(paste0(person, " s\r\n")))
  expect_true(pty$wait("? Steer"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("use the median\r")
  expect_true(pty$wait(paste0(if (utf8) "↳" else "->", " steer\r\n")))
  expect_true(pty$wait("END"))
  expect_true(pty$wait("use the median END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("Paused. Type"), 0L)
})

test_that("console_typed_split() marks a last line without a line end as partial", {
  expect_identical(console_typed_split(""), character())
  expect_identical(console_typed_split("a\r\n\nb\r"), c("a", "", "b"))
  expect_identical(console_typed_split("steer me\nuse base R"),
                   structure(c("steer me", "use base R"), partial = TRUE))
})

test_that("a question drains fd 0 before it reads: lines steer, a partial line is kept", {
  local_console_test()
  local_gptr_options(interactive = TRUE)
  tty = local_stty()
  drain = c("-icanon", "min", "0", "time", "0")
  local_mocked_bindings(
    repl_terminal = function(rs) TRUE, console_readline_tty = function() FALSE,
    # the partial line is read only in the drain's mode
    console_typed_lines = function(rd, ...) {
      if (!identical(utils::tail(tty$log, 5L), drain)) return(character())
      structure(c("steer me", "use base R"), partial = TRUE)
    })
  # the notice quotes the line (typed with the echo off) and names the key (D-245 glyphs); with
  # gptr.history off it says the line was not kept
  notice = c(kept_line("use base R"), kept_line("use base R", kept = FALSE))
  for (k in 1:2) {
    local_gptr_options(history = k == 1L)
    tty$log = character()
    rl = local_readline(c("go", "y", "/exit"))
    e = new.env()
    fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2"), "after"))
    rs = repl_state(NULL, e)
    rs$model = fake
    rs$mode = "manual"
    out = utils::capture.output(repl_main(rs))
    expect_identical(e$zz, 2)
    expect_identical(rl$kept, if (k == 1L) "use base R" else character())
    reqs = fake_requests(fake)
    expect_length(reqs, 2L)
    expect_identical(msg_text(last_message(reqs[[2L]])), relay("steer me"))
    # under the question and its keys, right above the chevron, never inside the call's block
    # (visual review)
    at = grep("? Allow r?", out, fixed = TRUE)
    expect_identical(out[at + 2:3], c(queue_line("steer", "steer me"), notice[[k]]))
    # the question reads in the saved modes from before its rows, the drain's restored before it
    # reads; the call's after it
    expect_identical(tty$log, c("-g", "-echo", "SAVED", "-g", drain, "SAVED", "-echo", "SAVED"))
  }
})

test_that("a terminal: a question never takes the line typed ahead of it (P28 B, C, H)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = TRUE)",
    "long = paste(c('BEGIN', sprintf('w%02d', 1:30), 'END'), collapse = ' ')",
    "q = list(list(id = 'q1', question = 'Which package?', options = list('ggplot2', 'base')))",
    "calls = list(B = list(tool = 'r', input = list(code = 'Sys.sleep(1); zz = 1')),",
    "             C = list(tool = 'r', input = list(code = 'zz = 2')),",
    "             H = list(tool = 'ask', input = list(questions = q)))",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  call = if (identical(m$role, 'user')) calls[[req$last_user]]",
    "  if (!is.null(call)) return(c(list(text = long, chunk = 8L, gap = 0.05), call))",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'manual', envir = new.env()))"
  ))
  person = if (l10n_info()[["UTF-8"]]) "\u203a" else ">>"
  sep = if (l10n_info()[["UTF-8"]]) " \u00b7 " else " - "
  kept = paste0("draft kept, back after your answer", sep, "use base R")
  expect_true(pty$wait("peter> ", timeout = 120))
  # B: typed without Enter while the answer streams, it is the composer's draft: the approval
  # says it is kept, its row ends with its prompt and the draft is on the live row again while the
  # call it gated runs
  pty$send("B\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait("Allow r?"))
  expect_true(pty$wait(kept))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  expect_match(pty$pending(), paste0(person, " use base R"), fixed = TRUE)
  expect_true(pty$wait("REQ tool_result: "))
  # each draft continues at the prompt after its run (P28 I); Ctrl-U clears it there
  expect_true(pty$wait("peter> use base R"))
  # C: a partial line starting with "no" denies nothing
  pty$send("\025C\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("no wait, plot it first")
  expect_true(pty$wait("Allow r?"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  expect_true(pty$wait("REQ tool_result: "))
  expect_true(pty$wait("peter> no wait, plot it first"))
  # H: a partial line at the agent's question is not its answer
  pty$send("\025H\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait("Choose a number, or type your own answer"))
  expect_true(pty$wait(kept))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("1\r")
  expect_true(pty$wait("REQ tool_result: The user answered: - q1: ggplot2 END"))
  expect_true(pty$wait("peter> use base R"))
  pty$send("\025/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(c(pty$seen("kept in history"), pty$seen("Not an answer"),
                     pty$seen("Permission denied"), pty$seen("(typed)")), c(0L, 0L, 0L, 0L))
})

test_that("a terminal: a draft a run left continues at the prompt until sent (P28 I, D-243)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = TRUE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:40), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$last_user %in% c('ONE', 'TWO')) return(list(text = long, chunk = 8L, gap = 0.05))",
    "  paste0('REQ ', req$last_user, ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "›" else ">>"
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base")
  expect_true(pty$wait(paste0(person, " use base")))
  # the run ends and the draft is at the prompt, edited with the composer's keys; Enter sends it
  expect_true(pty$wait("peter[auto]> use base"))
  pty$send("x")
  expect_true(pty$wait("peter[auto]> use basex"))
  pty$send("\177 R")
  expect_true(pty$wait("peter[auto]> use base R"))
  pty$send("\r")
  expect_true(pty$wait("REQ use base R END"))
  # Ctrl-C there adds the draft to the history and readline takes over: Up recalls it
  expect_true(pty$wait("peter[auto]> "))
  pty$send("TWO\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("and plot")
  expect_true(pty$wait("peter[auto]> and plot"))
  pty$send("\003")
  expect_true(pty$wait(kept_line("and plot", utf8 = utf8)))
  # a blank row between the kept line and the prompt, as after every run; readline's prompt
  # erases its row first (steering review)
  expect_true(pty$wait("\r\n\r\n\r\033[Kpeter[auto]> "))
  pty$send("\033[A\r")
  expect_true(pty$wait("REQ and plot END"))
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(c(pty$seen("REQ "), pty$seen("again to leave")), c(2L, 0L))
})

test_that("a terminal: keys typed as the idle editor hands over show after the prompt only", {
  skip_on_cran()
  skip_on_os("windows")
  # the moment between the restore of the terminal's modes and readline's start, marked and widened
  restored = withr::local_tempfile()
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = TRUE, cli.num_colors = 1L, cli.width = 60L)",
    sprintf("trace('tty_restore', exit = quote({file.create(%s); Sys.sleep(0.5)}),",
            deparse(restored)),
    "      where = asNamespace('gptr'), print = FALSE)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:40), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(list(list(text = long, chunk = 8L, gap = 0.05)))",
    "invisible(peter(model = fake, mode = 'auto', envir = new.env()))",
    "cat('ECHO', any(grepl('(^| )echo( |$)', system('stty -a', intern = TRUE))), '\\n')"
  ), term = "xterm")
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("and colour")
  expect_true(pty$wait("peter[auto]> and colour"))
  # Ctrl-U empties the draft; `/ex` comes once the modes are restored, before readline starts
  unlink(restored)
  pty$send("\025")
  deadline = Sys.time() + 30
  while (!file.exists(restored) && Sys.time() < deadline) Sys.sleep(0.01)
  pty$send("/ex")
  expect_true(pty$wait("peter[auto]> "))
  pty$send("it\r")
  expect_true(pty$wait("ECHO TRUE"))
  rows = term_rows(gsub("\033\\[\\?[0-9;]*[A-Za-z]", "", pty$all))
  expect_identical(grep("> /exit", rows, fixed = TRUE, value = TRUE), "peter[auto]> /exit")
})

test_that("a terminal: a question waits a second after the last key; `yes` is no answer (D-243)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE)",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (!identical(m$role, 'user')) {",
    "    return(paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END'))",
    "  }",
    # the answer streams for about a second, then comes its call, and the ask
    "  long = paste(c('BEGIN', sprintf('w%02d', 1:30), 'END'), collapse = ' ')",
    "  list(text = long, chunk = 8L, gap = 0.05, tool = 'r', input = list(code = 'zz = 1'))",
    "})",
    "invisible(peter(model = fake, mode = 'manual', envir = new.env()))"
  ))
  expect_true(pty$wait("peter> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  # typed key by key while the answer streams and the ask comes due, however slow the child:
  # the live row says a question waits, Enter still queues, and the ask is drawn a second after
  # the Enter, its answer empty
  typed = ""
  for (k in rep(c("y", "e", "s"), 10L)) {
    pty$send(k)
    typed = paste0(typed, k)
    if (pty$wait("question waiting", timeout = 0.3)) break
  }
  expect_lt(nchar(typed), 30L)
  # while the draft has text it waits three seconds: a pause in a sentence is not its end
  expect_false(pty$wait("Allow r?", timeout = 1.5))
  pty$send("\r")
  sent = Sys.time()
  expect_true(pty$wait("Allow r?"))
  expect_gte(as.numeric(difftime(Sys.time(), sent, units = "secs")), 1)
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  # the relay, its typed word on the next row where the row is full
  expect_true(pty$wait(paste0("REQ operator: ", trimws(relay("")))))
  expect_true(pty$wait(paste0(typed, " END")))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  # a sent draft leaves nothing to keep
  expect_identical(c(pty$seen("Not an answer"), pty$seen("Permission denied"),
                     pty$seen("draft kept")), c(0L, 0L, 0L))
})

test_that("a terminal: a line arriving just as a question is drawn steers the run (P28 D)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE)",
    # the line arrives once the question's rows are drawn, before it reads
    "trace('ui_permission_lines', exit = quote({cat('DRAWN\\n'); Sys.sleep(1)}), print = FALSE,",
    "      where = asNamespace('gptr'))",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (identical(m$role, 'user')) return(list(tool = 'r', input = list(code = 'zz = 1')))",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'manual', envir = new.env()))"
  ))
  expect_true(pty$wait("peter> ", timeout = 120))
  pty$send("D\r")
  expect_true(pty$wait("DRAWN"))
  pty$send("steer me\r")
  expect_true(pty$wait(queue_line("steer", "steer me", l10n_info()[["UTF-8"]])))
  # the question's drain gives it to the composer, so the question starts empty; a person
  # answers it later than 0.1 s
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  expect_true(pty$wait(paste0("REQ operator: ", relay("steer me"))))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("Not an answer"), 0L)
})

test_that("a macOS terminal: a block pasted at a question comes back as one prompt", {
  skip_on_cran()
  skip_if_not(is_macos(), "paste joining reads a macOS terminal")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = TRUE)",
    "fake = gptr_fake_provider(function(req) {",
    "  m = req$messages[[length(req$messages)]]",
    "  if (identical(req$last_user, 'P') && identical(m$role, 'user')) {",
    "    return(list(tool = 'r', input = list(code = 'zz = 1')))",
    "  }",
    "  paste0('REQ ', m$role, ': ', gsub('\\n', ' ', gptr:::msg_text(m)), ' END')",
    "})",
    "invisible(peter(model = fake, mode = 'manual', envir = new.env()))"
  ))
  expect_true(pty$wait("peter> ", timeout = 120))
  pty$send("P\r")
  expect_true(pty$wait("Allow r?"))
  pty$pending()
  pty$send("y\rpasted two\rpasted three\r")
  expect_true(pty$wait("A pasted block is not an answer (kept in history)."))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("n\r")
  expect_true(pty$wait("REQ tool_result: "))
  expect_true(pty$wait("peter> "))
  # Up then Enter sends the block as one message: one request, one answer
  pty$send("\033[A")
  pty$pending()
  pty$send("\r")
  expect_true(pty$wait("REQ user: y pasted two pasted three END", timeout = 10))
  expect_true(pty$wait("peter> "))
  # so does a block pasted at the prompt
  pty$send("a\rb\rc\r")
  expect_true(pty$wait("Enter sends it as one message"))
  pty$send("\r")
  expect_true(pty$wait("REQ user: a b c END"))
  expect_true(pty$wait("peter> "))
  pty$send("\033[A")
  pty$pending()
  pty$send("\r")
  expect_true(pty$wait("REQ user: a b c END", timeout = 10))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(c(pty$seen("REQ user: y END"), pty$seen("REQ user: ")), c(0L, 3L))
})
