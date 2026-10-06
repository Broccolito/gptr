# Shared fake-provider helpers for every plan's tests (contract section 12.2, P01).
# Replies follow the script grammar of contract section 12.1.

# A text reply; `...` adds modifiers such as `chunk`, `gap`, `delay` or `usage`
fake_text = function(text, ...) {
  c(list(text = text), list(...))
}

# A reply calling tool `name` with input `list(...)`, optionally after some text
fake_tool = function(name, ..., .text = NULL, .id = NULL) {
  input = list(...)
  if (!length(input)) input = json_obj()
  reply = list(tool = name, input = input)
  if (!is.null(.id)) reply$id = .id
  if (!is.null(.text)) reply$text = .text
  reply
}

# A reply with parallel tool calls; each argument is list(name, input)
fake_tools = function(...) {
  calls = lapply(list(...), function(call) {
    list(name = call[[1L]], input = if (length(call) > 1L) call[[2L]] else json_obj())
  })
  list(tools = calls)
}

# A reply that fails with an `error` event after `after` text deltas
fake_error = function(message = "overloaded", status = 529L, after = 0L) {
  list(error = message, status = as.integer(status), after = as.integer(after))
}

# A fake provider for the calling test, registered with gptr_register() and unregistered when the
# test ends; returns the spec
local_fake_provider = function(script, name = "fake", type = "chat", .env = parent.frame()) {
  spec = gptr_fake_provider(script, name = name, type = type)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  spec
}

# The requests a fake provider received, in order
fake_requests = function(spec) {
  spec$log$requests
}

# A temporary project made the working directory and the project root for the calling test
#
# `gptr = TRUE` creates a `.gptr/` skeleton directly (sessions/, cache/tmp/, .gitignore; no
# dependency on gptr_init()); `files` is a named list of relative path -> content (a character
# vector of lines); `trust = TRUE` records trust in the redirected user config through
# gptr_trust(). Returns the normalised project path.
local_project = function(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame()) {
  root = path_norm(withr::local_tempdir("gptr-project-", .local_envir = .env))
  if (gptr) {
    dir.create(file.path(root, ".gptr", "sessions"), recursive = TRUE)
    dir.create(file.path(root, ".gptr", "cache", "tmp"), recursive = TRUE)
    write_atomic(file.path(root, ".gptr", ".gitignore"), c(
      "sessions/", "cache/s2/", "cache/tmp/", "checkpoints/", "artifacts/*/v*/data/",
      "artifacts/*/run/", "locks/", "*.lock/", "settings.local.json", "transcripts/"
    ))
  }
  for (rel in names(files)) {
    path = file.path(root, rel)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    write_atomic(path, as.character(files[[rel]]))
  }
  withr::local_dir(root, .local_envir = .env)
  withr::local_options(gptr.project_root = root, .local_envir = .env)
  if (trust) gptr_trust(root, trust = TRUE)
  root
}

# withr::local_options() with `gptr.` prefixed names
local_gptr_options = function(..., .env = parent.frame()) {
  opts = list(...)
  nms = names(opts)
  if (length(opts) && (is.null(nms) || !all(nzchar(nms)))) stop("all options must be named")
  nms = ifelse(startsWith(nms, "gptr."), nms, paste0("gptr.", nms))
  withr::local_options(stats::setNames(opts, nms), .local_envir = .env)
}
