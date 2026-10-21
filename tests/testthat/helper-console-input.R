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

# No lines wait on fd 0 and stty finds no terminal there: a test that drives the console never
# reads the developer's own keystrokes or changes their terminal when the tests run in one (P26)
local_no_fd0 = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(console_typed_lines = function(rd, ...) character(),
                                  tty_modes = function(modes = "-g") NULL, .env = .env)
}

# A console test: a temporary project, no history, no document recording questions, no fd 0
local_console_test = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(history = FALSE, record = "off", .env = .env)
  local_no_fd0(.env = .env)
}

# The REPL's persistent stdin connection replaced by a text connection over `lines`
local_console_stdin = function(lines, .env = parent.frame()) {
  testthat::local_mocked_bindings(console_stdin_open = function() textConnection(lines),
                                  .env = .env)
}

# Terminal R in a pty (80x24, TERM `term`, echo on as in a terminal unless `echo` is FALSE) that
# loads gptr and sources `child`, the child's code (its options too). `send(x)` types; `wait(x)`
# reads until `x` is shown and consumes the output through it, so the next wait() looks after it;
# `pending()` reads for 0.5 s and returns what followed, its escapes dropped; `all` keeps
# everything shown and `seen(x)` counts `x` in it. The child dies with the test.
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
  pty$seen = function(x) sum(gregexpr(x, pty$all, fixed = TRUE, useBytes = TRUE)[[1L]] > 0L)
  pty$wait("> ")
  pty$send(sprintf("source(%s)\r", deparse(script)))
  pty
}
