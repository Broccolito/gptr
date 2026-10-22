# console-input.R -- the composer of a terminal console (P28, layer L5, area console; IC-76,
# D-243): the pure key machine that edits the draft typed while the agent works.

#' The composer's key machine (IC-76, D-243): the read batch `chars` (decoded text) applied at
#' time `now` (seconds) to `state`, list(draft, esc, t) (list() to start)
#'
#' Text is added at the draft's end; DEL and BS delete its last character, Ctrl-U clears it and
#' Ctrl-W deletes its last word. Other control bytes and escape sequences (up to their final byte)
#' are dropped, so nothing moves a cursor. A sequence the batch ends in is held in `esc` until
#' `now` passes its start `t` by 50 ms, then dropped (a lone Esc). `\r` and `\r\n` read as `\n`; a
#' batch holding newlines sends the draft and its text up to the last newline as one message,
#' newlines kept (IC-76's paste rule), and keeps the rest as the draft; a newline ends what the
#' edit keys reach. A message goes as `enter_kind` (`"steer"` or `"follow_up"`), always as a
#' follow-up when it starts with / or !, and not at all when blank. Two keys act only as a batch
#' of their own (elsewhere Tab is text and Up is dropped): Up (`ESC [ A`, `ESC O A`) on an empty
#' draft takes back the newest queued message; Tab on a trigger word (console_trigger())
#' completes it and never sends: `complete(line, end)` returns full words, whose longest common
#' prefix replaces the word when longer, else two or more are listed. On any other draft Tab
#' sends the other kind.
#' @return list(state, action), the action NULL, list(type = "send", kind, text),
#'   list(type = "take_back") or list(type = "complete", candidates)
#' @noRd
console_compose = function(state, chars, now, enter_kind, complete) {
  draft = state$draft %||% ""
  held = if (now - (state$t %||% now) <= 0.05) state$esc %||% "" else ""
  x = paste0(held, gsub("\r\n?", "\n", chars))
  out = function(action = NULL, esc = "", t = now) {
    list(state = list(draft = draft, esc = esc, t = t), action = action)
  }
  send = function(text, kind) {
    if (grepl("^\\s*[/!]", text)) kind = "follow_up"
    if (nzchar(trimws(text))) list(type = "send", kind = kind, text = text)
  }
  if (x %in% c("\033[A", "\033OA")) return(out(if (!nzchar(draft)) list(type = "take_back")))
  if (identical(x, "\t")) {
    word = console_trigger(draft)
    if (is.null(word)) {
      action = send(draft, setdiff(c("steer", "follow_up"), enter_kind))
      draft = ""
      return(out(action))
    }
    cands = complete(draft, nchar(draft))
    if (!length(cands)) return(out())
    pre = cands[[1L]]
    for (cand in cands[-1L]) while (!startsWith(cand, pre)) pre = substr(pre, 1L, nchar(pre) - 1L)
    if (nchar(pre) <= nchar(word)) {
      return(out(if (length(cands) > 1L) list(type = "complete", candidates = cands)))
    }
    draft = paste0(substr(draft, 1L, nchar(draft) - nchar(word)), pre)
    return(out())
  }
  keys = regmatches(x, gregexpr(paste0("\\x1b(\\[[\\x20-\\x3f]*[\\x40-\\x7e]?|O[\\x40-\\x7e]?|",
                                       "[\\x20-\\x7e])?|[\\x01-\\x1f\\x7f]|[^\\x01-\\x1f\\x7f]+"),
                                x, perl = TRUE))[[1L]]
  lines = ""
  esc = ""
  for (i in seq_along(keys)) {
    k = keys[[i]]
    if (k == "\n") {
      lines = paste0(lines, draft, "\n")
      draft = ""
    } else if (k %in% c("\177", "\b")) {
      draft = substr(draft, 1L, nchar(draft) - 1L)
    } else if (k == "\025") {
      draft = ""
    } else if (k == "\027") {
      draft = sub("\\S*\\s*$", "", draft, perl = TRUE)
    } else if (startsWith(k, "\033")) {
      if (i == length(keys) && grepl("^\\x1b(\\[[\\x20-\\x3f]*|O)?$", k, perl = TRUE)) esc = k
    } else if (k == "\t" || !grepl("^[\\x01-\\x1f]", k, perl = TRUE)) {
      draft = paste0(draft, k)
    }
  }
  t = if (nzchar(esc) && length(keys) == 1L && nzchar(held)) state$t else now
  out(if (nzchar(lines)) send(sub("\n$", "", lines), enter_kind), esc, t)
}

#' The word at the end of `line` that Tab completes (D-244), or NULL where it is no trigger word:
#' the last word of a line starting with ! or !!, a word starting with @ or peter$, or a first
#' word starting with /. A word ends at whitespace and readline's break characters, ! among them
#' @noRd
console_trigger = function(line) {
  word = regmatches(line, regexpr("[^ \\t\\n\"\\\\'`><=%;,|&{()}!]*$", line, perl = TRUE))
  if (grepl("^\\s*!", line, perl = TRUE) || grepl("^(@|peter\\$)", word) ||
        grepl("^\\s*/\\S*$", line, perl = TRUE)) {
    word
  }
}
