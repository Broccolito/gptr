# agent-background.R -- experimental background sessions (P21; contract 04 section 7.21, IC-57).
#
# peter(..., background = TRUE) returns a running session at once. A `later` timer pumps the
# process reactor while the console is idle: one non-blocking reactor iteration per tick, and
# nothing while a reactor pump is on the call stack (IC-57: reactor_depth() > 0).

#' The background pump state `the$bg` (owned by P21, 04 section 7.0), created on first use
#' @noRd
bg_state = function() {
  st = the$bg
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$sessions = new.env(parent = emptyenv())
    st$ticking = FALSE
    the$bg = st
  }
  st
}

#' The background session with id `id`, or NULL
#' @noRd
bg_get = function(id) {
  if (!rlang::is_string(id) || !nzchar(id)) return(NULL)
  get0(id, envir = bg_state()$sessions, inherits = FALSE)
}

#' Is `id` a registered background session?
#' @noRd
bg_has = function(id) {
  !is.null(bg_get(id))
}

#' Ids of the registered background sessions, sorted
#' @noRd
bg_ids = function() {
  ls(bg_state()$sessions, sorted = TRUE)
}

#' Is an idle tick pumping the reactor right now?
#' @noRd
bg_ticking = function() {
  isTRUE(bg_state()$ticking)
}

#' An `until` function for reactor_pump() that allows exactly one non-blocking iteration
#' (the pump checks `until()` before each iteration)
#' @noRd
bg_once = function() {
  first = TRUE
  function() {
    if (!first) return(TRUE)
    first <<- FALSE
    FALSE
  }
}

#' The `gptr.background_tools` mode: "wait" or "idle" (anything else reads as "idle")
#' @noRd
bg_tools_mode = function() {
  if (identical(gptr_opt("background_tools"), "wait")) "wait" else "idle"
}

#' Replace C0/C1 controls, bidi and zero-width characters by spaces and invalid bytes by <xx>
#' (code points, so the result does not depend on the locale)
#' @noRd
bg_clean = function(x) {
  x = iconv(as_utf8(as.character(x)), "UTF-8", "UTF-8", sub = "byte")
  vapply(x, function(s) {
    if (is.na(s)) return("")
    cp = utf8ToInt(s)
    bad = cp < 32L | (cp >= 127L & cp <= 159L) | (cp >= 0x200bL & cp <= 0x200fL) |
      (cp >= 0x202aL & cp <= 0x202eL) | (cp >= 0x2066L & cp <= 0x2069L) | cp == 0xfeffL
    cp[bad] = 32L
    intToUtf8(cp)
  }, "", USE.NAMES = FALSE)
}

#' One line of at most `n` characters, whitespace collapsed, cut with an ASCII ellipsis
#' @noRd
bg_cut = function(x, n) {
  x = gsub("[[:space:]]+", " ", trimws(paste(bg_clean(x), collapse = " ")))
  if (nchar(x) > n) x = paste0(substr(x, 1L, n - 3L), "...")
  x
}

#' Object names for a notice: at most `max` names, then "and N more"
#' @noRd
bg_names_text = function(nm, max = 6L) {
  nm = unique(bg_clean(nm))
  nm = nm[nzchar(trimws(nm))]
  shown = paste(utils::head(nm, max), collapse = ", ")
  if (length(nm) > max) shown = paste0(shown, " and ", length(nm) - max, " more")
  shown
}

#' One line describing a permission request for the waiting notice
#' @noRd
bg_request_summary = function(request) {
  lines = bg_clean(c(request$summary, request$reason, "an action"))
  first = lines[nzchar(trimws(lines))][[1L]]
  bg_cut(paste0(request$tool %||% "tool", ": ", first), 100L)
}
