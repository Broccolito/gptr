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
  old = the$background
  the$background = "dark"
  withr::defer(assign("background", old, envir = the))
  long = paste(rep("use base R", 12L), collapse = " ")
  fake = slow_first()
  local_typed(typed_once(long, function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
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

test_that("a line queued while an answer streams goes between its whole rows (D-245)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.width = 40L, cli.num_colors = 1L)
  words = paste(sprintf("word%02d", 1:40), collapse = " ")
  fake = gptr_fake_provider(list(list(text = words, chunk = 8L, gap = 0.02), "second"))
  looks = 0L
  local_typed(typed_once("use base R", function() {
    looks <<- looks + 1L
    looks >= 4L
  }))
  res = typing_console(fake, c("go", "/exit"))
  whole = utils::capture.output(console_print_text(words))
  # the screen's rows: what follows the last carriage return of each line
  rows = sub(".*\r", "", res$out)
  first = grep("word01", rows, fixed = TRUE)
  last = grep("word40", rows, fixed = TRUE)
  q = which(rows == queue_line("steer", "use base R"))
  expect_true(length(q) == 1L && first < q && q < last)
  # the paragraph is not cut at the queue line, and no waiting row comes back inside it
  expect_identical(rows[setdiff(first:last, q)], whole)
  expect_false(any(grepl("thinking", res$out[(first + 1L):last], fixed = TRUE)))
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
  status = which(startsWith(res$out, paste0("  done", sym$sep)))
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
  expect_true(all(c(queue_line("follow-up", "!zz = 5"), queue_line("follow-up", "then plot it"))
                  %in% res$out))
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
  # routed before the question is drawn
  expect_lt(match(queue_line("steer", "use base R instead"), out),
            grep("? Allow r?", out, fixed = TRUE))
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

test_that("a terminal call runs without echo; its modes return after it, an error or interrupt", {
  skip_on_cran()
  local_console_test()
  tty = local_stty()
  during = list()
  fake = gptr_fake_provider(function(req) {
    during[[length(during) + 1L]] <<- list(log = tty$log, saved = the$tty_modes)
    if (identical(req$last_user, "fail")) list(error = "bad key", status = 401L) else "ok"
  })
  local_typed(function() character())
  err = utils::capture.output(invisible(typing_console(fake, c("go", "fail", "/exit"))),
                             type = "message")
  expect_identical(during[[1L]], list(log = c("-g", "-echo"), saved = "SAVED"))
  expect_identical(during[[2L]]$log, c("-g", "-echo", "SAVED", "-g", "-echo"))
  expect_true(any(startsWith(err, "Error: ")))
  expect_identical(tty$log, rep(c("-g", "-echo", "SAVED"), 2L))
  expect_null(the$tty_modes)
  tty$log = character()
  slow = gptr_fake_provider(list(list(text = "first", delay = 5)))
  local_typed(function() {
    if (length(fake_requests(slow))) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    character()
  })
  res = typing_console(slow, c("go", "/exit"))
  expect_true(any(grepl("[gptr] aborted", res$out, fixed = TRUE)))
  expect_identical(tty$log, c("-g", "-echo", "SAVED"))
  expect_null(the$tty_modes)
  # an interrupt while stty turns the echo off
  tty$log = character()
  local_mocked_bindings(tty_modes = function(modes = "-g") {
    tty$log = c(tty$log, modes)
    if (identical(modes, "-echo")) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    if (identical(modes, "-g")) "SAVED"
  })
  res = typing_console(fake, c("go", "/exit"))
  expect_true(any(grepl("[gptr] interrupted", res$out, fixed = TRUE)))
  expect_identical(tty$log, c("-g", "-echo", "SAVED"))
  expect_null(the$tty_modes)
})

test_that("a question during a terminal call reads with the saved modes (readline echoes then)", {
  tty = local_stty()
  withr::defer(assign("tty_modes", NULL, envir = the))
  read = function(prompt) {
    tty$log = c(tty$log, paste0("read ", prompt))
    "y"
  }
  the$tty_modes = "SAVED"
  expect_identical(gptr_readline("allow? ", read), "y")
  expect_identical(tty$log, c("SAVED", "read allow? ", "-echo"))
  the$tty_modes = NULL
  tty$log = character()
  expect_identical(gptr_readline("peter> ", read), "y")
  expect_identical(tty$log, "read peter> ")
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

test_that("a terminal: typed text shows when queued and delivered, never in the answer (D-242)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:60), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) switch(as.character(req$n),",
    "  '2' = list(tool = 'r', input = list(code = 'zz = 1')), '3' = 'STEERED',",
    "  list(text = long, chunk = 8L, gap = 0.04)))",
    "invisible(peter(model = fake, envir = new.env()))"
  ), term = "xterm")
  expect_true(pty$wait("peter> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("steer me\r")
  expect_true(pty$wait("Allow r?"))
  pty$pending()
  pty$send("y\r")
  expect_true(pty$wait("STEERED"))
  expect_true(pty$wait("peter> "))
  pty$send("TWO\r")
  expect_true(pty$wait("END"))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  # once in its queue line, once as the person's line at the boundary
  utf8 = l10n_info()[["UTF-8"]]
  queued = queue_line("steer", "steer me", utf8)
  shown = paste0(if (utf8) "\u203a" else ">", " steer me")
  expect_identical(c(pty$seen("steer me"), pty$seen(queued), pty$seen(shown)), c(2L, 1L, 1L))
  # the answer to approve and the next prompt are shown: readline echoes with the modes restored
  expect_identical(c(pty$seen(paste0("? more\r", pty_asked(), "y")), pty$seen("peter> TWO")),
                   c(1L, 1L))
  # the screen's rows (escapes dropped, a row redrawn after "\r" kept as redrawn) without the
  # queue line: the streamed answer reads as the undisturbed one of the second prompt
  rows = strsplit(gsub("\033\\[[0-9;?]*[A-Za-z]", "", pty$all), "\n", fixed = TRUE)[[1L]]
  text = paste(sub("^.*\r", "", sub("\r$", "", rows)), collapse = " ")
  text = gsub(queued, "", gsub("\\s+", " ", text), fixed = TRUE)
  # the person's line follows the first answer, before the agent's next request
  expect_true(grepl(paste0("END ", shown, " "), text, fixed = TRUE))
  answers = gsub(" ", "", regmatches(text, gregexpr("BEGIN.*?END", text, perl = TRUE))[[1L]])
  expect_length(answers, 2L)
  expect_identical(answers[[1L]], answers[[2L]])
})

test_that("console_typed_split() marks a last line without a line end as partial", {
  expect_identical(console_typed_split(""), character())
  expect_identical(console_typed_split("a\r\n\nb\r"), c("a", "", "b"))
  expect_identical(console_typed_split("steer me\nuse base R"),
                   structure(c("steer me", "use base R"), partial = TRUE))
})

test_that("a question drains fd 0 first: lines steer, a partial line is kept in the history", {
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
    expect_lt(grep(notice[[k]], out, fixed = TRUE), grep("? Allow r?", out, fixed = TRUE))
    # the drain's modes are restored before the question reads
    expect_identical(tty$log, c("-g", "-echo", "-g", drain, "SAVED", "SAVED"))
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
    "calls = list(B = list(tool = 'r', input = list(code = 'zz = 1')),",
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
  expect_true(pty$wait("peter> ", timeout = 120))
  # B: typed without Enter while the answer streams; the approval row ends with its prompt
  pty$send("B\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait("kept in history"))
  expect_true(pty$wait("use base R"))
  expect_true(pty$wait("Allow r?"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  expect_true(pty$wait("REQ tool_result: "))
  expect_true(pty$wait("peter> "))
  # the kept line is the newest history entry at the next prompt
  pty$send("\033[A\r")
  expect_true(pty$wait("REQ user: use base R END"))
  expect_true(pty$wait("peter> "))
  # C: a partial line starting with "no" denies nothing
  pty$send("C\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("no wait, plot it first")
  expect_true(pty$wait("Allow r?"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("y\r")
  expect_true(pty$wait("REQ tool_result: "))
  expect_true(pty$wait("peter> "))
  # H: a partial line at the agent's question is not its answer
  pty$send("H\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait("Choose a number, or type your own answer"))
  expect_true(endsWith(pty$pending(), pty_asked()))
  pty$send("1\r")
  expect_true(pty$wait("REQ tool_result: The user answered: - q1: ggplot2 END"))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(c(pty$seen("kept in history"), pty$seen("Not an answer"),
                     pty$seen("Permission denied"), pty$seen("(typed)")), c(3L, 0L, 0L, 0L))
})

test_that("a terminal: a line arriving just as a question is drawn steers the run (P28 D)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE)",
    # the line arrives after the question drained fd 0, before its readline() starts
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
  # the question is asked again, empty; a person answers it later than 0.1 s
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
