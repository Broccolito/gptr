# Shared helpers for permission and UI tests (P11; contract section 12.2)

# Restores the process permission rules (`the$rules_session`) when the calling test ends
local_permission_rules = function(.env = parent.frame()) {
  old = the$rules_session
  withr::defer(assign("rules_session", old, envir = the), envir = .env)
  invisible(perm_store())
}
