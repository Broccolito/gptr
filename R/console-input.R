# console-input.R -- the composer of a terminal console (P28, layer L5, area console; IC-76,
# D-243): the key machine that edits the draft typed while the agent works, the keys it reads
# and the live row at the bottom.

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

#' Apply one read batch `chars` of a T console (IC-76, D-243) to the composer of the REPL reader
#' `rd` (`rd$compose`, console_compose()) for session `s`: a message is queued as its kind says
#' (policy_enqueue(): a steer for the next step boundary, a follow-up in `rd$typed` for the next
#' prompt) and Up takes back the newest one (console_newest()); the live row is drawn again where
#' it shows. Tab completes nothing yet. Ctrl-C, a key in character mode (tty_call()), interrupts
#' as SIGINT would, after the keys before it; the keys after it in the batch are dropped
#' @noRd
console_keys = function(rd, s, chars) {
  ctrl_c = regexpr("\003", chars, fixed = TRUE)
  if (ctrl_c > 0L) chars = substr(chars, 1L, ctrl_c - 1L)
  if (nzchar(chars)) {
    res = console_compose(rd$compose, chars, reactor_now(), setting_get("type_ahead", s),
                          function(line, end) character())
    rd$compose = res$state
    act = res$action
    if (identical(act$type, "send")) {
      policy_enqueue(s, act$text, act$kind, source = "repl")
    } else if (identical(act$type, "take_back")) {
      rd$compose$draft = console_newest(s, rd, take = TRUE)$text %||% ""
    }
    if (isTRUE(the$live_row$shown)) the$live_row$draw()
  }
  if (ctrl_c > 0L) rlang::interrupt()
  invisible(NULL)
}

#' The REPL reader `rd`'s read at `prompt` of a T console's draft a run left (D-243): the prompt
#' and the draft's tail are one row (on the input band, as the live row), edited with the
#' composer's keys in character mode (tty_call()) and drawn again after every key; the row is
#' cleared when the read ends. Enter returns the line, which the reader echoes after the prompt
#' as readline() leaves it; Up and Ctrl-D do nothing, nor does Tab but on a trigger word. Once the
#' draft is empty, at Ctrl-C or when nothing is read, a draft left goes to the console history
#' (console_keep()) and NULL is returned, so readline() reads at the same prompt
#' @noRd
console_idle = function(rd, prompt) {
  sym = console_style()
  line = NULL
  on.exit(tty_restore(), add = TRUE)
  tryCatch({
    tty_call(TRUE)
    repeat {
      draft = rd$compose$draft %||% ""
      if (!nzchar(draft)) break
      room = cli::console_width() - 1L - live_fit(prompt)
      console_cat(paste0("\r", sym$band, prompt,
                         live_fit(live_text(draft), room, sym$ellipsis, tail = TRUE),
                         "\033[K", if (nzchar(sym$band)) "\033[0m"))
      keys = console_typed_chars(rd, -1L)
      if (!nzchar(keys)) break
      # Ctrl-C is a key in character mode: the keys before it count
      ctrl_c = regexpr("\003", keys, fixed = TRUE)
      if (ctrl_c > 0L) keys = substr(keys, 1L, ctrl_c - 1L)
      if (nzchar(keys) && (!identical(keys, "\t") || !is.null(console_trigger(draft)))) {
        res = console_compose(rd$compose, keys, reactor_now(), "steer",
                              function(line, end) character())
        rd$compose = res$state
        if (identical(res$action$type, "send")) {
          line = res$action$text
          break
        }
      }
      if (ctrl_c > 0L) break
    }
  }, interrupt = function(e) NULL)
  console_cat("\r\033[K")
  if (!is.null(line)) return(line)
  draft = rd$compose$draft
  rd$compose = NULL
  if (nzchar(draft %||% "")) console_keep(draft)
  NULL
}

#' May a question be asked at time `now` (seconds)? Only once the last key the composer read
#' (`last_key`, NULL when none) is a second old, so typing never runs into an answer (D-243)
#' @noRd
ask_ready = function(last_key, now) is.null(last_key) || now - last_key >= 1

#' Before a console question in a T console (D-243): what waits on fd 0 goes to the composer
#' (console_typed()), and while its last key is under a second old (ask_ready()) the keys are read
#' every 0.05 s, the live row saying `question waiting` (`rec$question` of its record), so Enter
#' and Tab still queue
#' @noRd
console_ask_wait = function() {
  rd = console_repl_find()$reader
  if (!isTRUE(the$tty$keys) || is.null(rd)) return(invisible(NULL))
  row = the$live_row
  on.exit(if (!is.null(row)) row$rec$question = NULL, add = TRUE)
  repeat {
    console_typed()
    if (ask_ready(rd$compose$t, reactor_now())) break
    if (!is.null(row) && !isTRUE(row$rec$question)) {
      row$rec$question = TRUE
      if (row$shown) row$draw()
    }
    Sys.sleep(0.05)
  }
  invisible(NULL)
}

#' After a console question in a terminal call (D-243): the call's modes again (tty_question()),
#' and in a T console the live row the question cleared is drawn again, the composer's draft
#' unchanged, while the call it gated runs
#' @noRd
console_asked = function() {
  tty_question(FALSE)
  row = the$live_row
  if (isTRUE(the$tty$keys) && isTRUE(row$on) && !row$shown) row$draw()
  invisible(NULL)
}

#' The newest message the person queued for session `s` that no run has taken (D-242), as
#' list(kind, text), or NULL; `take` takes it back. Follow-ups wait in the REPL reader `rd`'s
#' `typed` lines, steers among the console's held items (policy_flush()), then in the session's
#' queue (session_unqueue()); when both kinds wait, the newest is of the kind queued last
#' (`rd$sent`, policy_enqueue())
#' @noRd
console_newest = function(s, rd, take = FALSE) {
  st = console_state()
  held = which(vapply(st$pending, function(it) identical(it$s, s), NA))
  q = session_data(s)$queue$steer
  user = which(vapply(q, function(it) it$source %in% queue_user_sources, NA))
  steer = if (length(held)) {
    st$pending[[held[[length(held)]]]]$text
  } else if (length(user)) {
    q[[user[[length(user)]]]]$text
  }
  n = length(rd$typed)
  if (n && (is.null(steer) || identical(rd$sent, "follow_up"))) {
    text = rd$typed[[n]]
    if (take) rd$typed = rd$typed[-n]
    return(list(kind = "follow_up", text = text))
  }
  if (is.null(steer)) return(NULL)
  if (take && length(held)) st$pending = st$pending[-held[[length(held)]]]
  if (take && !length(held)) session_unqueue(s, "steer")
  list(kind = "steer", text = steer)
}

#' The live row's text (IC-82, D-243): what the run does and how long it has run, its queue and a
#' waiting question, then the person's draft or the keys, fitted to `width - 1` columns
#'
#' `state`: `what` (thinking, the running tool's name or `sub-agent a`), `secs` (the run's
#' seconds, shown as 0s, 59s, 1m 05s), `queued` (the person's messages waiting), `question` (a
#' question waits), `newest` (list(kind, text): the newest of them), `candidates` (completions,
#' shown in place of the status words), `draft` (the composer's text; NULL where no composer reads
#' keys), `enter` (the kind Enter queues, the `type_ahead` setting), `key` (the console's interrupt
#' key), `pause` (TRUE where the key pauses, else it stops) and `steer` (TRUE where only the pause
#' menu steers: Positron's console holds what is typed), `frozen` (TRUE while R code runs in this
#' process: no clock, and with an empty draft `<sep>keys show when r returns`), `band` (TRUE on the
#' input band, its words
#' in the band's grey) and `status_w` (the widest status a row with a draft had this run: the
#' status is padded to it, so the draft never moves left; attr "status_w" of the result is this
#' row's). In the style table's glyphs:
#' without a composer the status ends with the key and its verb, as the composer's keys read,
#' `<sep>esc stop`; with an empty draft the newest message follows, `<queued> steer<sep><text><sep>
#' <up> edit`, or the keys, `enter steer<sep>tab follow-up<sep>ctrl-c pause`; else `<person>
#' <draft>`. The block is the agent's blue and the words dim; the draft is ink. One collapse rule:
#' whole terms go from the right, the hint's, then the queue and a waiting question, then the
#' queued message is cut keeping its head, down to the block and the elapsed time; the draft keeps
#' its tail, so an ellipsis always marks cut text. Widths are counted as the console draws them
#' (live_fit()), so the row never wraps; where not even the block and the time fit, it is empty.
#' @noRd
console_live_row = function(state, width) {
  sym = console_style()
  kind = function(k) if (identical(k, "follow_up")) "follow-up" else "steer"
  secs = as.integer(max(0, state$secs %||% 0))
  clock = if (secs < 60L) paste0(secs, "s") else sprintf("%dm %02ds", secs %/% 60L, secs %% 60L)
  what = state$what %||% "thinking"
  # R code runs in this process: no clock ticks and no key is read until it returns
  frozen = isTRUE(state$frozen)
  if (frozen) clock = what
  words = c(if (frozen) what else paste(what, clock),
            if (isTRUE(state$queued > 0)) paste0(state$queued, " queued"),
            if (isTRUE(state$question)) "question waiting")
  key = tolower(state$key %||% "Ctrl-C")
  enter = state$enter %||% "steer"
  draft = state$draft
  # the hint's terms; a queued message (`said`) is the one text cut, the others are dropped whole
  said = NULL
  terms = if (is.null(draft)) {
    paste(key, if (isTRUE(state$steer)) "steer" else if (isTRUE(state$pause)) "pause" else "stop")
  } else if (!nzchar(draft) && frozen) {
    paste("keys show when", what, "returns")
  } else if (!nzchar(draft) && is.null(state$newest)) {
    c(paste("enter", kind(enter)), paste("tab", kind(setdiff(c("steer", "follow_up"), enter))),
      paste(key, "pause"))
  } else if (!nzchar(draft)) {
    said = paste0(sym$queued, " ", kind(state$newest$kind), sym$sep, live_text(state$newest$text))
    c(said, paste(sym$up, "edit"))
  }
  hint = function(terms) {
    if (!length(terms)) "" else if (is.null(draft) || frozen) paste0(sym$sep, terms) else
      paste0("   ", paste(terms, collapse = sym$sep))
  }
  lead = paste0(sym$agent, " ")
  gap = paste0("   ", sym$person, " ")
  input = if (nzchar(draft %||% "")) live_text(draft)
  room = width - 1L - live_fit(lead)
  if (room < live_fit(clock)) return("")
  fit = if (is.null(input)) room else max(live_fit(clock), room - live_fit(gap) - live_fit(input))
  if (length(state$candidates)) {
    shown = paste(vapply(state$candidates, live_text, ""), collapse = "  ")
    status = live_fit(shown, fit, sym$ellipsis)
  } else {
    # dropped whole, from the right: the hint's terms, then the queue and a waiting question;
    # then the queued message is cut, keeping its head; at least the block and the time
    repeat {
      status = paste0(paste(words, collapse = sym$sep), hint(terms))
      if (live_fit(status) <= fit) break
      if (length(terms) > !is.null(said)) {
        terms = terms[-length(terms)]
      } else if (length(words) > 1L) {
        words = words[-length(words)]
      } else if (!is.null(said)) {
        cut = live_fit(said, fit - live_fit(words) - 3L, sym$ellipsis)
        if (startsWith(cut, paste0(sym$queued, " ", kind(state$newest$kind), sym$sep))) {
          status = paste0(words, hint(cut))
          break
        }
        said = NULL
        terms = character()
      } else {
        status = clock
        break
      }
    }
  }
  grey = if (isTRUE(state$band)) sym$band_dim else sym$dim
  if (is.null(input)) return(paste0(sym$blue(sym$agent), " ", grey(status)))
  # the draft stays where it was this run: the status keeps the widest width it had (`status_w`)
  shown = live_fit(status)
  status = paste0(status, strrep(" ", max(0L, min(fit, state$status_w %||% 0L) - shown)))
  row = paste0(sym$blue(sym$agent), " ", grey(status))
  left = room - live_fit(status) - live_fit(gap)
  if (left > live_fit(sym$ellipsis)) {
    row = paste0(row, gap, live_fit(input, left, sym$ellipsis, tail = TRUE))
  }
  structure(row, status_w = shown)
}

#' The person's text on one row of the live row or the idle editor: its lines escaped
#' (console_lines(), rule C1) and joined by a blank, a tab a blank
#' @noRd
live_text = function(x) gsub("\t", " ", paste(console_lines(x), collapse = " "), fixed = TRUE)

#' Plain text fitted to `n` columns as the live row counts them (in a CJK locale, whose terminals
#' draw East Asian ambiguous widths wide, a character outside ASCII that R counts as one column
#' counts two): with `n` NULL its columns; else the text when it fits, or it cut with `ell` at its
#' end, or its tail after `ell` (`tail`), no blank or separator at the cut
#' @noRd
live_fit = function(x, n = NULL, ell = "", tail = FALSE) {
  ch = strsplit(x, "", fixed = TRUE)[[1L]]
  w = nchar(ch, type = "width")
  if (grepl("^(ja|ko|zh)", Sys.getlocale("LC_CTYPE"))) {
    w = w + (w == 1L & nchar(ch, type = "bytes") > 1L)
  }
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
  row$status_w = 0L
  row$draw = function(state = console_live_state(row$rec), write = console_cat) {
    # in the console's colours, also when drawn inside an evaluation, whose options say 1 colour
    rlang::local_options(cli.num_colors = console_colors())
    width = cli::console_width()
    state$band = nzchar(row$band)
    state$status_w = row$status_w
    text = console_live_row(state, width)
    row$status_w = max(row$status_w, attr(text, "status_w") %||% 0L)
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
#' person's messages waiting for its session, whether a question waits (`rec$question`,
#' console_ask_wait()), and the console's interrupt key and what it does; where a T console's
#' composer reads keys (tty_call()), its draft, the newest message waiting (console_newest()) and
#' the kind Enter sends
#' @noRd
console_live_state = function(rec) {
  kids = Filter(function(r) !is.null(r$child), as.list(console_state()$active))
  labels = sort(vapply(kids, function(r) r$child$label, ""))
  s = rec$session
  rd = if (isTRUE(the$tty$keys)) console_repl_prompt()$reader
  list(what = if (length(labels)) paste("sub-agent", labels[[1L]]) else rec$what,
       secs = as.numeric(Sys.time()) - rec$t0, queued = console_queued(s),
       question = isTRUE(rec$question), frozen = isTRUE(rec$frozen),
       key = console_interrupt_key(), pause = console_menu_available(),
       steer = console_menu_available() && front_end() == "positron",
       draft = if (!is.null(rd)) rd$compose$draft %||% "",
       newest = if (!is.null(rd)) console_newest(s, rd), enter = setting_get("type_ahead", s))
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
#' (console_render_on()), on a dynamic console of an interactive R (not class P), but not in
#' R.app, whose console gives everything after a carriage return the input's colour
#' @noRd
console_live_start = function(rec) {
  rec$what = "thinking"
  rec$frozen = NULL
  row = the$live_row
  if (!identical(row$rec, rec)) {
    cls = console_class()
    if (!cli::is_dynamic_tty() || cls == "P" || platform_gui() == "AQUA") {
      return(invisible(NULL))
    }
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
