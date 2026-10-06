# Shared helpers for permission and UI tests (P11; contract section 12.2)

# Restores the process permission rules (`the$rules_session`) when the calling test ends
local_permission_rules = function(.env = parent.frame()) {
  old = the$rules_session
  withr::defer(assign("rules_session", old, envir = the), envir = .env)
  invisible(perm_store())
}

# A scripted UI backend for the calling test (contract section 12.2): answers are consumed in
# order (permission(): "y", "a" (always, session), "p" (always, project), "n",
# list(decision = "deny", feedback = <text>), "abort"; select(): an integer; input(): a string;
# questions(): a named list); an empty queue answers nothing, which fails closed. Registers the
# `scripted` UI at user rank and sets options(gptr.ui = "scripted", gptr.interactive = TRUE).
# Returns the state: `log` (df method, prompt, answer) and `remaining()`.
local_scripted_ui = function(answers = list(), .env = parent.frame()) {
  st = ui_scripted_state(answers)
  off = gptr_register(ui_scripted_spec(st, "scripted"))
  withr::defer(off(), envir = .env)
  withr::local_options(gptr.ui = "scripted", gptr.interactive = TRUE, .local_envir = .env)
  st
}
