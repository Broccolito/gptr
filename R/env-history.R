# The user's top-level expressions between agent turns (P09; report 12 section 2.C5).
# A task callback registered while a session with a kept home is live; it never touches `value`.
# R drops a callback that throws, so nothing it runs may throw on parser output (D-045). peter()
# calls, the registering one included, are not logged.

#' Process-level log of the user's top-level expressions (not run state: the user's own
#' typing history, the last 20 entries)
#' @noRd
user_log_state = new.env(parent = emptyenv())
user_log_state$text = character()
user_log_state$time = numeric()
user_log_state$sessions = character()

#' Is `x` the name `name` (a symbol, or the string R accepts after `::`)?
#' @noRd
user_log_is_name = function(x, name) {
  (is.name(x) || (is.character(x) && length(x) == 1L && !is.na(x))) &&
    identical(as.character(x), name)
}

#' Is a call head the function peter() (`peter`, `gptr::peter` or `gptr:::peter`)?
#' @noRd
user_log_gptr_head = function(head) {
  if (user_log_is_name(head, "peter")) return(TRUE)
  is.call(head) && length(head) == 3L &&
    (identical(head[[1L]], as.name("::")) || identical(head[[1L]], as.name(":::"))) &&
    user_log_is_name(head[[2L]], "gptr") && user_log_is_name(head[[3L]], "peter")
}

#' Classify an expression: "gptr" (calls peter() anywhere), "deep" (nests past 5,000 calls), "show"
#' Breadth-first and linear; children are joined without names (a child named `recursive` would
#' bind to c()'s formal) and `function` formals join the same level (D-045).
#' @noRd
user_log_scan = function(expr) {
  level = if (is.call(expr)) list(expr) else list()
  depth = 0L
  while (length(level)) {
    depth = depth + 1L
    if (depth > 5000L) return("deep")
    heads = lapply(level, `[[`, 1L)
    if (any(vapply(heads, user_log_gptr_head, logical(1L)))) return("gptr")
    kids = unlist(lapply(level, as.list), recursive = FALSE, use.names = FALSE)
    formals = vapply(kids, typeof, "") == "pairlist"
    if (any(formals)) {
      kids = c(kids, unlist(lapply(kids[formals], as.list), recursive = FALSE, use.names = FALSE))
    }
    level = kids[vapply(kids, is.call, logical(1L))]
  }
  "show"
}

#' One log entry: the deparsed expression on one line, valid UTF-8 (IC-62), at most 120 characters
#' deparse() errors on some parsed input (non-UTF-8 backtick names, long call chains) become a
#' note; this frame holds only `expr`, never the callback's `value`.
#' @noRd
user_log_text = function(expr) {
  tryCatch(user_log_line(expr), error = function(e) "<expression that cannot be deparsed>")
}

#' The text of user_log_text(), which may signal an error
#' Deparsed lines join with "; " between statements and a space inside one: after `{`, before `}`
#' or `else`, and after the trailing space deparse() leaves at a break inside a statement.
#' @noRd
user_log_line = function(expr) {
  raw = deparse(expr, width.cutoff = 500L, nlines = 120L)
  lines = trimws(raw)
  n = length(lines)
  if (n > 1L) {
    inside = endsWith(raw[-n], "{") | endsWith(raw[-n], " ") |
      startsWith(lines[-1L], "}") | grepl("^else( |$)", lines[-1L], useBytes = TRUE)
    lines = paste0(lines, c(ifelse(inside, " ", "; "), ""))
  }
  txt = env_text(paste(lines, collapse = ""))
  if (nchar(txt) > 120L) txt = paste0(substr(txt, 1L, 117L), "...")
  txt
}

#' Append one expression to the log (keeps the last 20)
#' @noRd
user_log_push = function(expr) {
  kind = user_log_scan(expr)
  if (identical(kind, "gptr")) return(invisible())
  txt = if (identical(kind, "deep")) {
    "<expression nested more than 5000 calls deep>"
  } else {
    user_log_text(expr)
  }
  n = length(user_log_state$text)
  keep = if (n >= 20L) seq.int(n - 18L, n) else seq_len(n)
  user_log_state$text = c(user_log_state$text[keep], txt)
  user_log_state$time = c(user_log_state$time[keep], as.numeric(Sys.time()))
  invisible()
}

#' The task callback: logs successful top-level expressions; never touches `value`
#' @noRd
user_log_callback = function(expr, value, ok, visible) {
  if (isTRUE(ok)) user_log_push(expr)
  TRUE
}

#' Is the history callback registered with R? (R drops a callback that fails, and the user can
#' remove it by position, so a flag of ours could be stale)
#' @noRd
user_log_registered = function() {
  "gptr_history" %in% getTaskCallbackNames()
}

#' Start logging for a session with a kept home (idempotent per session id)
#' @noRd
user_log_start = function(session_id) {
  check_string(session_id, "session_id")
  user_log_state$sessions = union(user_log_state$sessions, session_id)
  if (!user_log_registered()) addTaskCallback(user_log_callback, name = "gptr_history")
  invisible()
}

#' Stop logging for a session; the callback is removed with the last session
#' @noRd
user_log_release = function(session_id) {
  check_string(session_id, "session_id")
  user_log_state$sessions = setdiff(user_log_state$sessions, session_id)
  if (!length(user_log_state$sessions)) user_log_stop()
  invisible()
}

#' Remove the callback and clear the log (also run by .onUnload)
#' @noRd
user_log_stop = function() {
  for (i in seq_len(sum(getTaskCallbackNames() == "gptr_history"))) {
    removeTaskCallback("gptr_history")
  }
  user_log_state$sessions = character()
  user_log_state$text = character()
  user_log_state$time = numeric()
  invisible()
}

on_load(on_unload(user_log_stop))

#' Top-level expressions the user evaluated since `since` (epoch seconds; NULL: the whole log)
#' The last `n`, oldest first, each at most 120 characters.
#' @noRd
user_expr_log = function(since = NULL, n = 20L) {
  check_number(since, "since", null = TRUE)
  check_number(n, "n", min = 0, int = TRUE)
  keep = if (is.null(since)) rep(TRUE, length(user_log_state$text)) else user_log_state$time > since
  out = user_log_state$text[keep]
  utils::tail(out, n)
}
