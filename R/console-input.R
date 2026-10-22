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

#' The live row's text (IC-82, D-243): what the run does and how long it has run, its queue and a
#' waiting question, then the person's draft or the keys, fitted to `width - 1` columns
#'
#' `state`: `what` (thinking, the running tool's name or `sub-agent a`), `secs` (the run's
#' seconds, shown as 0s, 59s, 1m 05s), `queued` (the person's messages waiting), `question` (a
#' question waits), `newest` (list(kind, text): the newest of them), `candidates` (completions,
#' shown in place of the status words), `draft` (the composer's text; NULL where no composer reads
#' keys), `enter` (the kind Enter queues, the `type_ahead` setting), `key` (the console's interrupt
#' key) and `pause` (TRUE where the key pauses, else it stops). In the style table's glyphs:
#' without a composer the status ends with the key, `<sep>esc stops`; with an empty draft the
#' newest message follows, `<queued> steer<sep><text><sep><up> edit`, or the keys,
#' `enter steer<sep>tab follow-up<sep>ctrl-c pause`; else `<person> <draft>`. The block is the
#' agent's blue and the words dim; the draft is ink. One collapse
#' rule: the status part is cut from the right with an ellipsis, down to the block and the elapsed
#' time, and the draft keeps its tail. A character outside ASCII that R counts as one column counts
#' two (live_fit()), as a terminal drawing East Asian ambiguous widths wide shows it, so the row
#' never wraps; where not even the block and the time fit, the row is empty.
#' @noRd
console_live_row = function(state, width) {
  sym = console_style()
  line = function(x) gsub("\t", " ", paste(console_lines(x), collapse = " "), fixed = TRUE)
  kind = function(k) if (identical(k, "follow_up")) "follow-up" else "steer"
  secs = as.integer(max(0, state$secs %||% 0))
  clock = if (secs < 60L) paste0(secs, "s") else sprintf("%dm %02ds", secs %/% 60L, secs %% 60L)
  base = paste(state$what %||% "thinking", clock)
  words = paste0(base, if (isTRUE(state$queued > 0)) paste0(sym$sep, state$queued, " queued"),
                 if (isTRUE(state$question)) paste0(sym$sep, "question waiting"))
  if (length(state$candidates)) {
    base = ""
    words = paste(vapply(state$candidates, line, ""), collapse = "  ")
  }
  key = tolower(state$key %||% "Ctrl-C")
  enter = state$enter %||% "steer"
  draft = state$draft
  hint = if (is.null(draft)) {
    paste0(sym$sep, key, if (isTRUE(state$pause)) " pauses" else " stops")
  } else if (!nzchar(draft)) {
    paste0("   ", if (is.null(state$newest)) {
      paste0("enter ", kind(enter), sym$sep, "tab ", kind(setdiff(c("steer", "follow_up"), enter)),
             sym$sep, key, " pause")
    } else {
      paste0(sym$queued, " ", kind(state$newest$kind), sym$sep, line(state$newest$text), sym$sep,
             sym$up, " edit")
    })
  }
  lead = paste0(sym$agent, " ")
  gap = paste0("   ", sym$person, " ")
  input = if (nzchar(draft %||% "")) line(draft)
  room = width - 1L - live_fit(lead)
  if (room < live_fit(clock)) return("")
  status = paste0(words, hint)
  fit = if (is.null(input)) room else max(live_fit(clock), room - live_fit(gap) - live_fit(input))
  if (live_fit(status) > fit) {
    status = live_fit(status, fit, sym$ellipsis)
    if (!startsWith(status, base)) status = clock
  }
  row = paste0(sym$blue(sym$agent), " ", sym$dim(status))
  if (is.null(input)) return(row)
  left = room - live_fit(status) - live_fit(gap)
  if (left > live_fit(sym$ellipsis)) {
    row = paste0(row, gap, live_fit(input, left, sym$ellipsis, tail = TRUE))
  }
  row
}

#' Plain text fitted to `n` columns as the live row counts them (a character outside ASCII that R
#' counts as one column counts two): with `n` NULL its columns; else the text when it fits, or it
#' cut with `ell` at its end, or its tail after `ell` (`tail`), no blank or separator at the cut
#' @noRd
live_fit = function(x, n = NULL, ell = "", tail = FALSE) {
  ch = strsplit(x, "", fixed = TRUE)[[1L]]
  w = nchar(ch, type = "width")
  w = w + (w == 1L & nchar(ch, type = "bytes") > 1L)
  if (is.null(n)) return(sum(w))
  if (sum(w) <= n) return(x)
  n = n - live_fit(ell)
  if (tail) {
    ch = rev(ch)
    w = rev(w)
  }
  keep = ch[cumsum(w) <= n]
  while (length(keep) && keep[[length(keep)]] %in% c(" ", "\u00b7", "-")) {
    keep = keep[-length(keep)]
  }
  keep = paste(if (tail) rev(keep) else keep, collapse = "")
  if (tail) paste0(ell, keep) else paste0(keep, ell)
}

#' The live row (IC-82, D-243): one row at the bottom, below the transcript's whole rows, while a
#' foreground run works, at column 0 like the person's input. `draw(state)` writes
#' console_live_row() (by default the state of the run's record `rec`, console_live_state()) and
#' `clear()` erases it; the cursor stays at the row's end. Where `\033[K` ends the line (an ANSI
#' terminal; RStudio) a row is `\r`, the row and `\033[K`, on the input band in a T console (then
#' `\033[0m`); elsewhere (R.app, Rgui, TERM=dumb, and Positron, whose console erases by writing
#' spaces) it is padded with spaces to width - 1, and a clear writes spaces. Both `write` as every
#' console control is (console_cat()), so from inside an evaluation too the row reaches the console,
#' never the tool's output. `the$live_row` holds the row while it is up, so gptr_message_write()
#' clears it before other output at its sink (`sinks`) and redraws it after (`erase`), writing it
#' itself; `on` says the run wants it drawn.
#' @noRd
console_live = function(cls) {
  row = new.env(parent = emptyenv())
  row$erase = cli::is_ansi_tty() || front_end() == "rstudio"
  row$band = if (identical(cls, "T")) console_style()$band else ""
  row$sinks = sink.number()
  row$shown = FALSE
  row$on = TRUE
  row$draw = function(state = console_live_state(row$rec), write = console_cat) {
    width = cli::console_width()
    text = console_live_row(state, width)
    row$shown = FALSE
    write(if (row$erase) {
      paste0("\r", row$band, text, "\033[K", if (nzchar(row$band)) "\033[0m")
    } else {
      paste0("\r", text, strrep(" ", max(0L, width - 1L - cli::ansi_nchar(text, type = "width"))))
    })
    row$shown = TRUE
    invisible(NULL)
  }
  row$clear = function(write = console_cat) {
    if (row$shown) {
      row$shown = FALSE
      blank = strrep(" ", max(0L, cli::console_width() - 1L))
      write(if (row$erase) "\r\033[K" else paste0("\r", blank, "\r"))
    }
    invisible(NULL)
  }
  row
}

#' The live row's state for the record `rec` of a foreground run (console_live_row()): the state
#' word (`rec$what`; `sub-agent <label>` while a sub-agent it shows runs), the run's seconds, the
#' person's messages waiting for its session, and the console's interrupt key
#' @noRd
console_live_state = function(rec) {
  kids = Filter(function(r) !is.null(r$child), as.list(console_state()$active))
  labels = sort(vapply(kids, function(r) r$child$label, ""))
  list(what = if (length(labels)) paste("sub-agent", labels[[1L]]) else rec$what,
       secs = as.numeric(Sys.time()) - rec$t0, queued = console_queued(rec$session),
       key = console_interrupt_key(), pause = console_menu_available())
}

#' The person's messages waiting for session `s`: its queued items from user sources, the items
#' the console holds for it (policy_flush()) and the lines the REPL holds for its next prompt
#' @noRd
console_queued = function(s) {
  q = session_data(s)$queue
  user = vapply(c(q$steer, q$follow_up), function(it) it$source %in% queue_user_sources, NA)
  held = vapply(console_state()$pending, function(it) identical(it$s, s), NA)
  sum(user) + sum(held) + length(console_repl_prompt()$reader$typed)
}

#' Show the live row for the record `rec` of a foreground run while it waits for its model
#' (`what` thinking): drawn now and once a second by a reactor task while the record renders
#' (console_render_on()), on a dynamic console of an interactive R (not class P)
#' @noRd
console_live_start = function(rec) {
  rec$what = "thinking"
  row = the$live_row
  if (!identical(row$rec, rec)) {
    cls = console_class()
    if (!cli::is_dynamic_tty() || cls == "P") return(invisible(NULL))
    console_live_stop()
    row = console_live(cls)
    row$rec = rec
    the$live_row = row
    row$task = reactor_task(function() {
      if (!identical(the$live_row, row)) return(FALSE)
      if (row$on && console_render_on(rec)) row$draw()
      1
    })
  }
  row$on = TRUE
  row$draw()
  invisible(NULL)
}

#' Take the live row down: clear it and end its task; only the row of `rec` when given
#' @noRd
console_live_stop = function(rec = NULL) {
  row = the$live_row
  if (is.null(row) || (!is.null(rec) && !identical(row$rec, rec))) return(invisible(NULL))
  row$clear()
  reactor_cancel(row$task)
  the$live_row = NULL
  invisible(NULL)
}
