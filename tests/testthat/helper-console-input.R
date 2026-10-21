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
