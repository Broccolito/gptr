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

# The REPL on a new session in mode auto with `answers` at its prompt: its output lines and its
# session
typing_console = function(fake, answers, tools = NULL, envir = new.env()) {
  local_readline(answers, .env = parent.frame())
  rs = repl_state(NULL, envir)
  rs$model = fake
  rs$mode = "auto"
  rs$tools = tools
  s = NULL
  out = utils::capture.output({
    s = repl_main(rs)
  })
  list(out = out, s = s)
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
  expect_true(any(grepl("[gptr] steering: 'use base R'; it reaches the agent at its next step",
                        res$out, fixed = TRUE)))
})

test_that("on a CLI route the steering notice says it is sent after the CLI's response", {
  skip_on_cran()
  local_console_test()
  f = local_fake_cli("claude", "toolstream")
  local_typed(typed_once("use base R", function() length(fake_log(f, "turn")) == 1L))
  res = typing_console(f$model, c("go", "/exit"))
  local_cli_cleanup(res$s)
  expect_true(any(grepl(
    "[gptr] steering: 'use base R'; it is sent after the CLI's current response", res$out,
    fixed = TRUE
  )))
  roles = vapply(res$s$messages, function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "operator", "assistant"))
})

test_that("type_ahead = 'follow_up' queues the line for when the agent would stop", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(type_ahead = "follow_up")
  fake = slow_first()
  local_typed(typed_once("then plot it", function() length(fake_requests(fake)) == 1L))
  res = typing_console(fake, c("go", "/exit"))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  msgs = reqs[[2L]]$messages
  expect_identical(msgs[[length(msgs) - 1L]]$role, "assistant")
  msg = last_message(reqs[[2L]])
  expect_identical(msg$role, "user")
  expect_identical(msg$source, "follow_up")
  expect_identical(msg_text(msg), "then plot it")
  expect_true(any(grepl("[gptr] follow-up queued: 'then plot it'; it is sent when the agent",
                        res$out, fixed = TRUE)))
})

test_that("a line typed during a tool reaches the request right after its result", {
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
  expect_lt(grep("[gptr] steering: 'use base R instead'", out, fixed = TRUE),
            match("  r  zz = 2", out))
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
  expect_true(any(grepl("[gptr] after this answer: '/status', '!x = 1'", res$out, fixed = TRUE)))
  expect_true(all(c("peter[auto]> /status", "peter[auto]> !x = 1") %in% res$out))
  expect_true(any(startsWith(res$out, "session   ")))
})

test_that("the held-lines notice ends the streamed line first (render pause)", {
  skip_on_cran()
  local_console_test()
  log = character()
  pause = console_render_pause
  resume = console_render_resume
  notice = console_notice
  local_mocked_bindings(
    console_render_pause = function() {
      log <<- c(log, "pause")
      pause()
    },
    console_render_resume = function(runs) {
      log <<- c(log, "resume")
      resume(runs)
    },
    console_notice = function(..., .error = FALSE) {
      log <<- c(log, paste0(...))
      notice(..., .error = .error)
    })
  fake = slow_first()
  local_typed(typed_once("/status", function() length(fake_requests(fake)) == 1L))
  typing_console(fake, c("go", "/exit"))
  i = grep("after this answer", log, fixed = TRUE)
  expect_length(i, 1L)
  expect_identical(log[c(i - 1L, i + 1L)], c("pause", "resume"))
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

test_that("an interrupted run drops the held lines and lists them", {
  skip_on_cran()
  local_console_test()
  e = new.env()
  fake = gptr_fake_provider(list(list(text = "first", delay = 5)))
  held = FALSE
  local_typed(function() {
    if (!length(fake_requests(fake))) return(character())
    if (!held) {
      held <<- TRUE
      return(c("/status", "!x = 1"))
    }
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    character()
  })
  res = typing_console(fake, c("go", "/exit"), envir = e)
  expect_true(any(grepl("[gptr] aborted", res$out, fixed = TRUE)))
  expect_true(any(grepl("[gptr] dropped typed lines: '/status', '!x = 1'", res$out, fixed = TRUE)))
  expect_null(e$x)
  expect_false("peter[auto]> /status" %in% res$out)
})

test_that("Ctrl-C at an approval prompt aborts the run and drops the held lines", {
  local_console_test()
  local_gptr_options(interactive = TRUE)
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2", .text = "hmm")))
  local_typed(typed_once("!x = 1", function() length(fake_requests(fake)) == 1L))
  asks = 0L
  local_mocked_bindings(readline_answer = function(prompt, ...) {
    asks <<- asks + 1L
    if (startsWith(prompt, "  allow?")) {
      signalCondition(structure(class = c("interrupt", "condition"),
                                list(message = "", call = NULL)))
    }
    if (asks == 1L) "go" else "/exit"
  }, gptr_readline = function(prompt = "", ...) readline_answer(prompt))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_true(any(grepl("[gptr] after this answer: '!x = 1'", out, fixed = TRUE)))
  expect_true(any(grepl("[gptr] dropped typed lines: '!x = 1'", out, fixed = TRUE)))
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

test_that("a terminal: typed text shows once, in its notice; questions and the next prompt echo", {
  skip_on_cran()
  skip_on_os("windows")
  dir = withr::local_tempdir("gptr-echo-")
  child = file.path(dir, "child.R")
  writeLines(c(
    tracemem_loader(),
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 60L)",
    "long = paste(c('BEGIN', sprintf('w%02dabc', 1:60), 'END'), collapse = ' ')",
    "fake = gptr_fake_provider(function(req) switch(as.character(req$n),",
    "  '2' = list(tool = 'r', input = list(code = 'zz = 1')), '3' = 'STEERED',",
    "  list(text = long, chunk = 8L, gap = 0.04)))",
    "invisible(peter(model = fake, envir = new.env()))",
    "cat('CHILD DONE\\n')"
  ), child)
  # the terminal echoes, as a terminal does (a processx pty does not by default)
  p = processx::process$new(
    file.path(R.home("bin"), "R"), c("--vanilla", "--quiet"), pty = TRUE,
    pty_options = list(echo = TRUE), wd = dir,
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
            TERM = "xterm"),
    cleanup = TRUE
  )
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
  seen = function(x) sum(gregexpr(x, st$out, fixed = TRUE, useBytes = TRUE)[[1L]] > 0L)
  wait_for = function(x, n = 1L, timeout = 30) {
    deadline = Sys.time() + timeout
    while (seen(x) < n && p$is_alive() && Sys.time() < deadline) {
      p$poll_io(100L)
      st$out = paste0(st$out, p$read_output())
    }
    seen(x) >= n
  }
  expect_true(wait_for("> "))
  p$write_input(sprintf("source(%s)\r", deparse(child)))
  expect_true(wait_for("peter> ", timeout = 120))
  p$write_input("ONE\r")
  expect_true(wait_for("BEGIN"))
  p$write_input("steer me\r")
  expect_true(wait_for("allow?"))
  Sys.sleep(0.5)
  p$write_input("y\r")
  expect_true(wait_for("STEERED"))
  expect_true(wait_for("peter> ", n = 2L))
  p$write_input("TWO\r")
  expect_true(wait_for("END", n = 2L))
  expect_true(wait_for("peter> ", n = 3L))
  p$write_input("/exit\r")
  expect_true(wait_for("CHILD DONE"))
  expect_identical(seen("steer me"), 1L)
  expect_identical(seen("[gptr] steering: 'steer me'"), 1L)
  # the answer to approve and the next prompt are shown: readline echoes with the modes restored
  expect_identical(c(seen("[?]: y"), seen("peter> TWO")), c(1L, 1L))
  # the screen's rows (escapes dropped, a row redrawn after "\r" kept as redrawn) without the
  # notice: the streamed answer reads as the undisturbed one of the second prompt
  rows = strsplit(gsub("\033\\[[0-9;?]*[A-Za-z]", "", st$out), "\n", fixed = TRUE)[[1L]]
  text = paste(sub("^.*\r", "", sub("\r$", "", rows)), collapse = " ")
  text = gsub("\\[gptr\\] steering:.*?next step", "", gsub("\\s+", " ", text), perl = TRUE)
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
  rl = local_readline(c("go", "y", "/exit"))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2"), "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_identical(e$zz, 2)
  expect_identical(rl$kept, "use base R")
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(msg_text(last_message(reqs[[2L]])), relay("steer me"))
  expect_lt(grep("[gptr] kept your unfinished line; ", out, fixed = TRUE),
            match("  r  zz = 2", out))
  # the drain's modes are restored before the question reads
  expect_identical(tty$log, c("-g", "-echo", "-g", drain, "SAVED", "SAVED"))
})

# Terminal R in a pty (80x24, TERM=xterm-256color, echo on as in a terminal) that loads gptr and
# sources `child`. `send(x)` types; `wait(x)` reads until `x` is shown and consumes the output
# through it, so the next wait() looks after it; `pending()` reads for 0.5 s and returns what
# followed, its escapes dropped; `all` keeps everything shown. The child dies with the test.
local_pty_r = function(child, .env = parent.frame()) {
  dir = withr::local_tempdir("gptr-pty-", .local_envir = .env)
  script = file.path(dir, "child.R")
  writeLines(c(tracemem_loader(), child, "cat('CHILD DONE\\n')"), script)
  p = processx::process$new(
    file.path(R.home("bin"), "R"), c("--vanilla", "--quiet"), pty = TRUE,
    pty_options = list(echo = TRUE, rows = 24L, cols = 80L), wd = dir,
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
            TERM = "xterm-256color"),
    cleanup = TRUE
  )
  # a pty child exits only once its output is read: p$kill() would wait for it forever
  withr::defer({
    if (p$is_alive()) p$signal(tools::SIGKILL)
    deadline = Sys.time() + 10
    while (p$is_alive() && Sys.time() < deadline) {
      p$poll_io(100L)
      p$read_output()
    }
  }, envir = .env)
  pty = new.env(parent = emptyenv())
  pty$all = ""
  pty$out = ""
  read = function(ms) {
    p$poll_io(ms)
    x = p$read_output()
    pty$all = paste0(pty$all, x)
    pty$out = paste0(pty$out, x)
  }
  pty$send = function(x) p$write_input(x)
  pty$wait = function(x, timeout = 30) {
    deadline = Sys.time() + timeout
    repeat {
      i = regexpr(x, pty$out, fixed = TRUE)
      if (i > 0L) {
        pty$out = substring(pty$out, i + attr(i, "match.length"))
        return(TRUE)
      }
      if (!p$is_alive() || Sys.time() > deadline) return(FALSE)
      read(100L)
    }
  }
  pty$pending = function() {
    deadline = Sys.time() + 0.5
    while (Sys.time() < deadline) read(50L)
    gsub("\033\\[[0-9;?]*[A-Za-z]", "", pty$out)
  }
  pty$seen = function(x) sum(gregexpr(x, pty$all, fixed = TRUE)[[1L]] > 0L)
  pty$wait("> ")
  pty$send(sprintf("source(%s)\r", deparse(script)))
  pty
}

test_that("a terminal: a question never takes the line typed ahead of it (P28 B, C, H)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE)",
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
  expect_true(pty$wait("[gptr] kept your unfinished line; "))
  expect_true(pty$wait("allow? "))
  expect_true(endsWith(pty$pending(), "[?]: "))
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
  expect_true(pty$wait("allow? "))
  expect_true(endsWith(pty$pending(), "[?]: "))
  pty$send("y\r")
  expect_true(pty$wait("REQ tool_result: "))
  expect_true(pty$wait("peter> "))
  # H: a partial line at the agent's question is not its answer
  pty$send("H\r")
  expect_true(pty$wait("BEGIN"))
  pty$send("use base R")
  expect_true(pty$wait("Choose ("))
  expect_true(endsWith(pty$pending(), "your own answer): "))
  pty$send("1\r")
  expect_true(pty$wait("REQ tool_result: The user answered: - q1: ggplot2 END"))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(c(pty$seen("kept your unfinished line"), pty$seen("Not an answer"),
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
  expect_true(pty$wait("[gptr] steering: 'steer me'"))
  # the question is asked again, empty; a person answers it later than 0.1 s
  expect_true(pty$wait("allow? "))
  expect_true(endsWith(pty$pending(), "[?]: "))
  pty$send("y\r")
  expect_true(pty$wait(paste0("REQ operator: ", relay("steer me"))))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("Not an answer"), 0L)
})
