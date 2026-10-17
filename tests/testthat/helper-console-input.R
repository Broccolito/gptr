# gptr_readline() answering `answers` in order (NA after the last), each as if readline() had
# waited `secs` seconds (the real wrapper records them in the$readline_secs, IC-75); `prompts`
# collects the prompts shown
local_readline = function(answers, secs = 1, .env = parent.frame()) {
  box = new.env(parent = emptyenv())
  box$i = 0L
  box$prompts = character()
  secs = rep_len(secs, length(answers))
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "", ...) {
    box$i = box$i + 1L
    box$prompts = c(box$prompts, prompt)
    if (box$i > length(answers)) return(NA_character_)
    the$readline_secs = secs[[box$i]]
    answers[[box$i]]
  }, .env = .env)
  withr::defer(assign("readline_secs", NULL, envir = the), envir = .env)
  box
}

# No lines wait on fd 0: a test that drives the console never reads the developer's own
# keystrokes when the tests run in a terminal (P26)
local_no_fd0 = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(console_typed_lines = function(rd) character(), .env = .env)
}
