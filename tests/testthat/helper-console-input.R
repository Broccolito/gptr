# gptr_readline() answering `answers` in order (NA after the last), each as if readline() had
# waited `secs` seconds (the real wrapper records them in the$readline_secs, IC-75); `prompts`
# collects the prompts shown and `kept` what console_history_add() added (gptr.history decides),
# never to the developer's history
local_readline = function(answers, secs = 1, .env = parent.frame()) {
  box = new.env(parent = emptyenv())
  box$i = 0L
  box$prompts = character()
  box$kept = character()
  secs = rep_len(secs, length(answers))
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "", ...) {
    box$i = box$i + 1L
    box$prompts = c(box$prompts, prompt)
    if (box$i > length(answers)) return(NA_character_)
    the$readline_secs = secs[[box$i]]
    answers[[box$i]]
  }, .env = .env)
  testthat::local_mocked_bindings(timestamp = function(stamp, ...) box$kept = c(box$kept, stamp),
                                  .package = "utils", .env = .env)
  withr::defer(assign("readline_secs", NULL, envir = the), envir = .env)
  box
}

# No lines wait on fd 0, stty finds no terminal there and no terminal answers the background probe:
# a test that drives the console never reads the developer's own keystrokes or changes their
# terminal when the tests run in one (P26)
local_no_fd0 = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(console_typed_chars = function(rd, ...) "",
                                  tty_modes = function(modes = "-g") NULL,
                                  tty_query = function(query, ...) "", .env = .env)
}

# The style table's UTF-8 glyphs (D-245): cli's unicode output, and no Windows console, where
# console_style() gives ASCII outside Windows Terminal and RStudio
local_utf8_glyphs = function(.env = parent.frame()) {
  withr::local_options(cli.unicode = TRUE, .local_envir = .env)
  testthat::local_mocked_bindings(is_windows = function() FALSE, .env = .env)
}

# A console test: a temporary project, no history, no document recording questions, no fd 0
local_console_test = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(history = FALSE, record = "off", .env = .env)
  local_no_fd0(.env = .env)
}

# A console where the live row draws on a dynamic output (P28 Task 17): console_class() gives
# `cls` (an interactive R); when the test ends the row is forgotten, nothing written
local_live_console = function(cls = "T", .env = parent.frame()) {
  testthat::local_mocked_bindings(console_class = function() cls, .env = .env)
  withr::defer({
    if (!is.null(the$live_row)) reactor_cancel(the$live_row$task)
    the$live_row = NULL
  }, envir = .env)
}

# What `f()` writes to stdout, as one string
written = function(f) {
  con = rawConnection(raw(), "w")
  on.exit(close(con))
  sink(con)
  tryCatch(f(), finally = sink())
  rawToChar(rawConnectionValue(con))
}

# The rows a terminal shows for `bytes`: \r, \n and \033[K act, other escapes are dropped
term_rows = function(bytes) {
  keys = regmatches(bytes, gregexpr("\033\\[[0-9;]*[A-Za-z]|[\r\n]|[^\r\n\033]", bytes,
                                    perl = TRUE))[[1L]]
  rows = character()
  row = character()
  col = 1L
  for (k in keys) {
    if (k == "\n") {
      rows = c(rows, paste(row, collapse = ""))
      row = character()
    }
    if (k %in% c("\r", "\n")) {
      col = 1L
    } else if (k == "\033[K") {
      row = row[seq_len(col - 1L)]
    } else if (!startsWith(k, "\033")) {
      row[[col]] = k
      col = col + 1L
    }
  }
  c(rows, paste(row, collapse = ""))
}

# The REPL's persistent stdin connection replaced by a text connection over `lines`
local_console_stdin = function(lines, .env = parent.frame()) {
  testthat::local_mocked_bindings(console_stdin_open = function() textConnection(lines),
                                  .env = .env)
}

# The end of a question in a pty child (D-243): its last row, then the person's chevron as the
# prompt, `>>` where the child's output, in this process's locale, is not UTF-8
pty_asked = function() paste0("\n", if (l10n_info()[["UTF-8"]]) "\u203a" else ">>", " ")

# The start of an approval's row for an invalid answer in a pty child (ui_reask()), which a queue
# line's `not an answer` (a line typed before the question) never is
pty_reask = function() paste0("not an answer", if (l10n_info()[["UTF-8"]]) " \u00b7 " else " - ")

# The first row of the line that shows a queued message (D-242), in console_style()'s glyphs;
# `utf8 = l10n_info()[["UTF-8"]]` gives a pty child's
queue_line = function(kind, text, utf8 = cli::is_utf8_output()) {
  sym = withr::with_options(list(cli.unicode = utf8), console_style())
  paste0(sym$queued, " ", kind, sym$sep, text)
}

# The line that lists the person's text gptr will not send (console_keep()): a queue line whose
# kind says it was kept in the history (the Up key recalls it) or not kept
kept_line = function(texts, kept = TRUE, utf8 = cli::is_utf8_output()) {
  sym = withr::with_options(list(cli.unicode = utf8), console_style())
  kind = if (kept) paste("kept in history", sym$up) else "not kept (gptr.history is off)"
  queue_line(kind, paste(texts, collapse = sym$sep), utf8)
}

# Terminal R in a pty (80x24, TERM `term`, echo on as in a terminal unless `echo` is FALSE) that
# loads gptr and sources `child`, the child's code (its options too). `send(x)` types; `wait(x)`
# reads until `x` is shown and consumes the output through it, so the next wait() looks after it;
# `pending()` reads for 0.5 s and returns what followed, its escapes and a CR at a row's start (a
# question's prompt clears its row, tty_question()) dropped; `all` keeps
# everything shown and `seen(x)` counts `x` in it; `interrupt()` sends SIGINT, as a terminal's
# Ctrl-C does where isig is on (the pty is not the child's controlling terminal, so `\003` is not).
# The child dies with the test.
local_pty_r = function(child, term = "xterm-256color", echo = TRUE, .env = parent.frame()) {
  dir = withr::local_tempdir("gptr-pty-", .local_envir = .env)
  script = file.path(dir, "child.R")
  writeLines(c(tracemem_loader(), child, "cat('CHILD DONE\\n')"), script)
  # an absolute path, so R CMD check's dummy `R` on PATH is never used (IC-60)
  p = processx::process$new(
    file.path(R.home("bin"), "R"), c("--vanilla", "--quiet"), pty = TRUE,
    pty_options = list(echo = echo, rows = 24L, cols = 80L), wd = dir,
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), TERM = term),
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
  pty$interrupt = function() p$interrupt()
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
    gsub("\n\r", "\n", gsub("\033\\[[0-9;?]*[A-Za-z]", "", pty$out), fixed = TRUE)
  }
  pty$seen = function(x) sum(gregexpr(x, pty$all, fixed = TRUE, useBytes = TRUE)[[1L]] > 0L)
  pty$wait("> ")
  pty$send(sprintf("source(%s)\r", deparse(script)))
  pty
}
