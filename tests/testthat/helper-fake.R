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

# A fake provider for the calling test, registered with gptr_register() when the extension API
# (P02) exists and unregistered when the test ends; returns the spec
local_fake_provider = function(script, name = "fake", type = "chat", .env = parent.frame()) {
  spec = gptr_fake_provider(script, name = name, type = type)
  register = get0("gptr_register", mode = "function")
  if (!is.null(register)) {
    off = register(spec)
    withr::defer(off(), envir = .env)
  }
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
# vector of lines); `trust = TRUE` records trust in the redirected user config (through
# gptr_trust() once P08 exists). Returns the normalised project path.
local_project = function(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame()) {
  nms = names(files)
  if (!is.list(files) || (length(files) &&
      (is.null(nms) || anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms)))) {
    stop("files must be a named list with unique, nonempty paths")
  }
  root = path_norm(withr::local_tempdir("gptr-project-", .local_envir = .env))
  if (length(files) && any(!path_inside(file.path(root, nms), root) |
      path_key(file.path(root, nms)) == path_key(root) |
      grepl("^(/|~|[A-Za-z]:|\\\\)", nms))) {
    stop("file paths must be relative and inside the temporary project")
  }
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
  if (trust) local_project_trust(root)
  root
}

# Record trust for a project in the (redirected) user config
local_project_trust = function(root) {
  trust_fun = get0("gptr_trust", mode = "function")
  if (!is.null(trust_fun)) {
    trust_fun(root, trust = TRUE)
    return(invisible(root))
  }
  file = file.path(gptr_user_dir("config", create = TRUE), "trust.json")
  data = if (file.exists(file)) json_decode(readLines(file, encoding = "UTF-8")) else list()
  data$version = 1L
  data$projects = data$projects %||% json_obj()
  data$projects[[path_key(root)]] = list(trusted = TRUE, date = format(Sys.Date()))
  write_atomic(file, json_encode(data, pretty = TRUE))
  invisible(root)
}

# withr::local_options() with `gptr.` prefixed names
local_gptr_options = function(..., .env = parent.frame()) {
  opts = list(...)
  nms = names(opts)
  if (length(opts) && (is.null(nms) || !all(nzchar(nms)))) stop("all options must be named")
  nms = ifelse(startsWith(nms, "gptr."), nms, paste0("gptr.", nms))
  withr::local_options(stats::setNames(opts, nms), .local_envir = .env)
}
