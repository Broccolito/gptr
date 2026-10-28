# console-input.R -- the composer of a terminal console (P28, layer L5, area console; IC-76,
# D-243): the key machine that edits the draft typed while the agent works, the keys it reads
# and the live row at the bottom.

#' The composer's key machine (IC-76, D-243): the read batch `chars` (decoded text) applied at
#' time `now` (seconds) to `state`, list(draft, esc, t, bracket) (list() to start)
#'
#' Text is added at the draft's end; DEL and BS delete its last character, Ctrl-U clears it and
#' Ctrl-W deletes its last word. Other control bytes and escape sequences (up to their final byte)
#' are dropped, so nothing moves a cursor, and so is a terminal's late answer to the background
#' probe (tty_unreply()). A sequence the batch ends in is held in `esc` until `now` passes its start
#' `t` by 50 ms, then dropped (a lone Esc). `\r` and `\r\n` read as `\n`; a batch holding newlines
#' sends the draft and its text up to the last newline as one message, newlines kept (IC-76's paste
#' rule), and keeps the rest as the draft; a newline ends what the edit keys reach. Text between
#' `ESC [ 200 ~` and `ESC [ 201 ~` (bracketed paste, D-263; both dropped) is a paste whatever
#' `paste` says: its newlines stay in the draft, leading blank lines dropped; a paste open at a
#' batch's end (`bracket`) lasts into the next batches; a sequence cut inside it waits for its rest
#' however late, as does a marker's start (`ESC [`, `ESC [ 2`, `ESC [ 2 0`, `ESC [ 2 0 0`,
#' `ESC [ 2 0 1`) while the batches after it may still complete it, and once they cannot its Esc is
#' the Esc key, dropped, and the rest is typed; in a batch holding a marker the text before the
#' markers is typed, unless the first is an end marker (the rest of a paste whose text ended it
#' early in an earlier batch, or whose start another reader took), and a newline after a paste's
#' end stays in the draft too, so pasted text that holds an end marker sends nothing: only Enter in
#' a later batch sends. With `paste` (a batch without markers read on the polling beat, too quick
#' for a person to type a newline and more) a batch with text after its last newline is a paste the
#' same way. A message goes as `enter_kind`
#' (`"steer"` or `"follow_up"`), always as a follow-up when it starts with / or !, and not at all
#' when blank. Two keys act only outside an open bracketed paste, as a batch of their own or as the
#' end of a batch without a newline outside a paste (console_unpasted(); elsewhere Tab is text and
#' Up is dropped): Up (`ESC [ A`, `ESC O A`) on an empty draft takes back the newest queued
#' message; Tab on a trigger word (console_trigger()) completes it and never sends:
#' `complete(line, end)` returns full words, whose longest common prefix replaces the word when
#' longer, else two or more are listed. On any other draft Tab sends the other kind.
#' @return list(state, action), the action NULL, list(type = "send", kind, text),
#'   list(type = "take_back") or list(type = "complete", candidates)
#' @noRd
console_compose = function(state, chars, now, enter_kind, complete, paste = FALSE) {
  draft = state$draft %||% ""
  bracket = isTRUE(state$bracket)
  held = state$esc %||% ""
  # a bracketed-paste marker's start (D-263), held however late while the reads may complete it
  start = "^\033\\[(2(0[01]?)?)?$"
  if (!bracket && now - (state$t %||% now) > 0.05 &&
      !grepl(paste0(start, "|^\033\\[20[01]~"), paste0(held, chars))) {
    held = if (grepl(start, held)) substring(held, 2L) else ""
  }
  x = tty_unreply(paste0(held, gsub("\r\n?", "\n", chars)))
  out = function(action = NULL, esc = "", t = now) {
    list(state = list(draft = draft, esc = esc, t = t, bracket = bracket), action = action)
  }
  send = function(text, kind) {
    if (grepl("^\\s*[/!]", text)) kind = "follow_up"
    if (nzchar(trimws(text))) list(type = "send", kind = kind, text = text)
  }
  # a bracketed paste (D-263) is open at the batch's end when its last marker opens one
  marks = regmatches(x, gregexpr("\033\\[20[01]~", x))[[1L]]
  # an end marker before any start ends a paste whose text ended it early in an earlier batch, or
  # whose start another reader took: the text before it is pasted
  if (length(marks) && marks[[1L]] == "\033[201~") bracket = TRUE
  open = if (length(marks)) marks[[length(marks)]] == "\033[200~" else bracket
  # a Tab or Up that ends a batch without a newline outside a paste is the key after the batch's
  # text, as keys typed during an in-process tool arrive as one batch
  key = regmatches(x, regexpr("(\t|\033\\[A|\033OA)$", x))
  if (!open && length(key) && nchar(key) < nchar(x) &&
        !grepl("\n", console_unpasted(x, bracket), fixed = TRUE)) {
    text = console_compose(list(draft = draft, bracket = bracket),
                           substr(x, 1L, nchar(x) - nchar(key)), now, enter_kind, complete)
    return(console_compose(list(draft = text$state$draft), key, now, enter_kind, complete))
  }
  if (!open && x %in% c("\033[A", "\033OA")) {
    return(out(if (!nzchar(draft)) list(type = "take_back")))
  }
  if (!open && identical(x, "\t")) {
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
  # a paste on the beat has text after its last newline, not only edit keys; in a batch with
  # markers the text before them is typed, and a newline after a paste's end (`ended`) is text
  last = max(0L, which(keys == "\n"))
  joined = paste && !length(marks) && !bracket && last > 0L &&
    any(!grepl("^[\\x01-\\x1f\\x7f]", keys[-seq_len(last)], perl = TRUE))
  lines = ""
  esc = ""
  ended = FALSE
  for (i in seq_along(keys)) {
    k = keys[[i]]
    if (k %in% c("\033[200~", "\033[201~")) {
      bracket = k == "\033[200~"
      ended = ended || !bracket
    } else if (k == "\n" && (joined || bracket || ended)) {
      draft = if (nzchar(trimws(draft))) paste0(draft, "\n") else ""
    } else if (k == "\n") {
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

#' Is a bracketed paste (D-263) open in the composer's state `state` at time `now`, its last read at
#' most 2 s before? Later its Ctrl-C byte is the key again, as a paste whose end marker another
#' reader took (a question asked mid-paste) never ends (console_keys())
#' @noRd
console_paste_open = function(state, now) {
  isTRUE(state$bracket) && now - (state$t %||% now) <= 2
}

#' The keys `x` outside bracketed pastes (D-263), with `bracket` after one open before them
#' @noRd
console_unpasted = function(x, bracket = FALSE) {
  gsub("(?s)\033\\[200~.*?(\033\\[201~|\\z)", "", paste0(if (bracket) "\033[200~", x), perl = TRUE)
}

#' The text of keys `keys` once their edit keys act (console_compose()): the message they end, else
#' the draft they leave
#' @noRd
console_line_text = function(keys) {
  res = console_compose(list(), keys, 0, "steer", console_complete)
  res$action$text %||% res$state$draft
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
#' prompt) and Up takes back the newest one (console_newest()), saying so where its queue line was
#' printed (console_queue_line()); Tab on a trigger word completes it
#' (console_complete()), and several candidates are kept as `rd$compose$candidates`, which the live
#' row shows until the next key; the live row is drawn again where it shows. A batch read at most
#' 0.2 s after the reader's last read (`rd$polled`, an empty read too) is on the polling beat, timed
#' by its last key's read (`rd$read_at`, console_typed_chars()), not the reader's wait after it, and
#' one there holding more keys than a person types since that read (one in 30 ms, plus one) is a
#' paste to console_compose(); fewer were typed, as when a late read under load holds Enter and the
#' next key. Bracketed-paste markers decide first: this rule decides only a batch without them read
#' while no paste they opened is open (console_compose(), D-263). A Tab or Up that ends a batch
#' right after a newline is a key of its own, after the message the newline sent (console_compose()
#' acts once a batch), as when Enter and Up share a late read. Ctrl-C, a key in character mode
#' (tty_call()), interrupts as SIGINT would, after the keys before it (in a batch holding a
#' bracketed-paste marker, read while a paste is open up to 2 s after its last read, or read on the
#' beat right after such a batch with no empty read between, `rd$compose$pasted`, it is pasted
#' text, as the text after an early end marker is); the keys after it in the batch (a further
#' Ctrl-C dropped) are the pause
#' menu's answers (`rd$after_interrupt`, console_ahead()), and those it leaves are read here once
#' it resumes, as if typed after it
#' @noRd
console_keys = function(rd, s, chars) {
  # the first read of a run, or one after an in-process tool held the reactor, is off the beat
  now = reactor_now()
  gap = (rd$read_at %||% now) - (rd$polled %||% -Inf)
  paste = gap <= 0.2 && nchar(chars) > 1 + gap / 0.03
  rd$polled = now
  rd$read_at = NULL
  # a batch holding a bracketed-paste marker, read while a paste is open (up to 2 s after its last
  # read, console_paste_open()), or read on the beat right after such a batch with no empty read
  # between (the rest of a paste whose text ended it early, split again) holds no Ctrl-C key: its
  # Ctrl-C bytes are pasted text, which the composer drops (D-263)
  pasted = nzchar(chars) && (console_paste_open(rd$compose, now) ||
                               (isTRUE(rd$compose$pasted) && gap <= 0.2) ||
                               grepl("\033\\[20[01]~", paste0(rd$compose$esc, chars)))
  if (pasted) chars = gsub("\003", "", chars, fixed = TRUE)
  ctrl_c = regexpr("\003", chars, fixed = TRUE)
  if (ctrl_c > 0L) {
    after = gsub("\003", "", substring(chars, ctrl_c + 1L), fixed = TRUE)
    rd$after_interrupt = paste0(rd$after_interrupt, after)
    chars = substr(chars, 1L, ctrl_c - 1L)
  }
  compose = function(chars) {
    if (!nzchar(chars)) return()
    key = regmatches(chars, regexpr("[\r\n](\t|\033\\[A|\033OA)$", chars))
    if (length(key)) {
      compose(substr(chars, 1L, nchar(chars) - nchar(key) + 1L))
      return(compose(substring(key, 2L)))
    }
    res = console_compose(rd$compose, chars, now, setting_get("type_ahead", s), console_complete,
                          paste)
    rd$compose = res$state
    act = res$action
    if (identical(act$type, "send")) {
      policy_enqueue(s, act$text, act$kind, source = "repl")
    } else if (identical(act$type, "take_back")) {
      it = console_newest(s, rd, take = TRUE)
      rd$compose$draft = it$text %||% ""
      if (!is.null(it)) console_queue_line(s, it$text, it$kind, taken = TRUE)
    } else if (identical(act$type, "complete")) {
      rd$compose$candidates = act$candidates
    }
    if (isTRUE(the$live_row$shown)) the$live_row$draw()
  }
  compose(chars)
  if (pasted || isTRUE(rd$compose$pasted)) rd$compose$pasted = pasted
  if (ctrl_c > 0L) {
    rlang::interrupt()
    left = rd$after_interrupt
    rd$after_interrupt = ""
    compose(left)
  }
  invisible(NULL)
}

#' The REPL reader `rd`'s read at `prompt` of a T console's draft a run left (D-243): the prompt
#' and the draft's tail are one row (on the input band, as the live row; a leading ! bold red, the
#' shell glyph, D-244), edited with the composer's keys in character mode (tty_call()) and drawn
#' again after every key; the row is cleared when the read ends. Enter returns the line, which the
#' reader echoes after the prompt
#' as readline() leaves it; Up and Ctrl-D do nothing, nor does Tab but on a trigger word, which it
#' completes (console_complete()), several candidates listed on a dim row at column 2 above the
#' prompt's row, as readline lists them. Once the
#' draft is empty, at Ctrl-C, at a cursor key (Left, Right, Home, End, Ctrl-A, Ctrl-E: readline's
#' editing, where Up recalls the draft) or when nothing is read, a draft left goes to the console
#' history (console_keep()) and NULL is returned, so readline() reads at the same prompt; where R's
#' readline reads the tty the call's modes stay (`rd$handed`) until the reader calls it, so a key
#' typed in between is not echoed before its prompt
#' @noRd
console_idle = function(rd, prompt) {
  sym = console_style()
  line = NULL
  on.exit(if (is.null(rd$handed)) tty_restore(), add = TRUE)
  tryCatch({
    tty_call(TRUE)
    repeat {
      draft = rd$compose$draft %||% ""
      if (!nzchar(draft)) break
      room = cli::console_width() - 1L - live_fit(prompt)
      shown = live_fit(live_text(draft), room, sym$ellipsis, tail = TRUE)
      # a leading ! is the shell glyph, as on the live row
      if (startsWith(shown, "!")) {
        shown = paste0(cli::style_bold(sym$red("!")), substring(shown, 2L))
      }
      console_cat(paste0("\r", sym$band, prompt, shown, "\033[K",
                         if (nzchar(sym$band)) "\033[0m"))
      keys = console_typed_chars(rd, -1L)
      if (!nzchar(keys)) break
      # Ctrl-C (a key in character mode), and a cursor key only readline edits with, hand the draft
      # over after the keys before them
      hand = regexpr("\003|[\001\005]|\033(\\[([1478]~|[0-9;]*[CDHF])|O[CDHF])", keys, perl = TRUE)
      if (hand > 0L) keys = substr(keys, 1L, hand - 1L)
      # Tab off a trigger word does nothing here (the composer would send the other kind)
      tab = endsWith(keys, "\t") &&
        !grepl("[\r\n]", console_unpasted(keys, isTRUE(rd$compose$bracket)))
      if (tab && is.null(console_trigger(paste0(draft, sub("\t$", "", keys))))) {
        keys = sub("\t$", "", keys)
      }
      if (nzchar(keys)) {
        # a read here starts at its first key, so a newline with text after it came as a paste
        res = console_compose(rd$compose, keys, reactor_now(), "steer", console_complete, TRUE)
        rd$compose = res$state
        if (identical(res$action$type, "send")) {
          line = res$action$text
          break
        }
        if (identical(res$action$type, "complete")) {
          console_cat("\r\033[K")
          console_write(paste0("  ", sym$dim(live_candidates(res$action$candidates,
                                                             cli::console_width() - 3L))))
        }
      }
      if (hand > 0L) break
    }
  }, interrupt = function(e) NULL)
  console_cat("\r\033[K")
  if (!is.null(line)) return(line)
  draft = rd$compose$draft
  rd$compose = NULL
  if (nzchar(draft %||% "")) {
    console_keep(draft)
    # the prompt keeps the blank row above it, as after every run
    console_write("")
  }
  if (console_readline_tty()) rd$handed = the$tty
  NULL
}

#' May a question be asked at time `now` (seconds)? Only once the last key the composer read
#' (`last_key`, NULL when none) is a second old, three while it holds a `draft`, so typing never
#' runs into an answer, nor does the rest of a sentence after a pause (D-243)
#' @noRd
ask_ready = function(last_key, now, draft = "") {
  is.null(last_key) || now - last_key >= if (nzchar(draft)) 3 else 1
}

#' Before a console question in a T console (D-243): what waits on fd 0 goes to the composer
#' (console_typed()), and until the question may be asked (ask_ready()) the keys are read every
#' 0.05 s, the live row saying `question waiting` (`rec$question` of its record), so Enter and Tab
#' still queue. A D console's call (line modes, `the$tty$keys` FALSE) waits the same way, reading
#' fd 0 as typed (tty_drain_mode()), the terminal's edits applied (tty_line_edit()): a line ended
#' meanwhile is routed (console_typed_route()), and the partial line waits in the reader (`rd$part`)
#' for the question's drain, which keeps it
#' @noRd
console_ask_wait = function() {
  rd = console_repl_find()$reader
  if (is.null(rd) || is.null(the$tty$saved)) return(invisible(NULL))
  if (!isTRUE(the$tty$keys)) return(console_ask_wait_lines(rd))
  row = the$live_row
  on.exit(if (!is.null(row)) row$rec$question = NULL, add = TRUE)
  repeat {
    console_typed()
    if (ask_ready(rd$compose$t, reactor_now(), rd$compose$draft %||% "")) break
    if (!is.null(row) && !isTRUE(row$rec$question)) {
      row$rec$question = TRUE
      if (row$shown) row$draw()
    }
    Sys.sleep(0.05)
  }
  invisible(NULL)
}

#' console_ask_wait() of a D console's call, for a run of the policy on the stack
#' @noRd
console_ask_wait_lines = function(rd) {
  target = Find(function(t) !is.null(t$session), policy_targets(policy_find()$runs))
  if (is.null(target)) return(invisible(NULL))
  modes = tty_drain_mode()
  if (length(modes) == 1L) on.exit(tty_modes(modes), add = TRUE)
  last = NULL
  repeat {
    lines = console_typed_lines(rd, 50L)
    if (length(lines)) last = reactor_now()
    lines = tty_line_edit(typed_join(rd, lines))
    if (isTRUE(attr(lines, "partial"))) {
      rd$part = lines[[length(lines)]]
      lines = lines[-length(lines)]
    }
    if (length(lines)) console_typed_route(rd, target$session, lines)
    if (ask_ready(last, reactor_now(), rd$part %||% "")) break
  }
  invisible(NULL)
}

#' `lines` read from fd 0 after the partial line a D console's wait held (`rd$part`,
#' console_ask_wait_lines()), which the first of them continues; `rd$part` is emptied
#' @noRd
typed_join = function(rd, lines) {
  part = rd$part %||% ""
  if (!nzchar(part)) return(lines)
  rd$part = ""
  partial = isTRUE(attr(lines, "partial")) || !length(lines)
  lines = c(paste0(part, c(lines, "")[[1L]]), lines[-1L])
  if (partial) attr(lines, "partial") = TRUE
  lines
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
#' `state`: `what` (thinking, the running tool's name or `sub-agent a`), `secs` (the run's seconds,
#' shown as 0s, 59s, 1m 05s), `queued` (the person's messages waiting), `question` (a question
#' waits), `newest` (list(kind, text): the newest of them), `candidates` (completions, shown in
#' place of the status words), `draft` (the composer's text; NULL where no composer reads keys),
#' `enter` (the kind Enter queues, the `type_ahead` setting), `key` (the console's interrupt key),
#' `pause` (TRUE where the key pauses, else it stops), `steer` (TRUE where only the pause menu
#' steers: Positron's console holds what is typed as R code) and `typed` (TRUE where a line typed
#' during the run is the next prompt: RStudio's console), `frozen` (TRUE while R code runs in this
#' process: no clock, and the keys wait, `<sep>keys show when r returns` with an empty draft, else
#' `keys wait` among the status words before the queue; not while a question waits, which reads
#' keys), `band` (TRUE on the input band, its words in the band's grey) and `status_w` (the widest
#' status a row with a draft had this run: the status is padded to it, so the draft never moves
#' left; attr "status_w" of the result is this row's lasting width, without `keys wait` and
#' `question waiting`, 0 for a row of completions, which shows until the next key). In the style
#' table's glyphs: without a composer the status ends with the key and its verb, as the composer's
#' keys read, `<sep>esc stop`, with `steer` `<sep>ctrl-c, then s, to steer`, and with `typed`
#' `<sep>typed lines run next`; with an empty draft the newest message follows, `<queued>
#' steer<sep><text><sep><up> edit`, or the keys, `enter steer<sep>tab follow-up<sep>ctrl-c pause`;
#' else `<person> <draft>`, after the hint `runs after this answer` where the draft starts with / or
#' ! (a follow-up, whatever the key) and the hint fits beside the status at its widest, and a
#' leading ! takes the person's glyph's place, bold red (Codex's shell mode, D-244). The block is
#' the agent's blue and the words dim; the draft is ink. One collapse rule: whole terms go from the
#' right, the hint's, then the queue and a waiting question, then the queued message is cut keeping
#' its head, down to the block and the elapsed time; the draft keeps its tail, so an ellipsis always
#' marks cut text. Widths are counted as the console draws them (live_fit()), so the row never
#' wraps; where not even the block and the time fit, it is empty.
#' @noRd
console_live_row = function(state, width) {
  sym = console_style()
  kind = function(k) if (identical(k, "follow_up")) "follow-up" else "steer"
  secs = as.integer(max(0, state$secs %||% 0))
  clock = if (secs < 60L) paste0(secs, "s") else sprintf("%dm %02ds", secs %/% 60L, secs %% 60L)
  what = state$what %||% "thinking"
  # R code runs in this process: no clock ticks and no key is read until it returns, unless a
  # question waits, which reads them
  frozen = isTRUE(state$frozen) && !isTRUE(state$question)
  if (frozen) clock = what
  # a sub-agent's short form, `sub-agent #1`, takes its label's place first where the row is narrow
  short = if (frozen) state$short %||% what else paste(state$short %||% what, clock)
  words = c(if (frozen) what else paste(what, clock),
            if (frozen && nzchar(state$draft %||% "")) "keys wait",
            if (isTRUE(state$queued > 0)) paste0(state$queued, " queued"),
            if (isTRUE(state$question)) "question waiting")
  key = tolower(state$key %||% "Ctrl-C")
  enter = state$enter %||% "steer"
  draft = state$draft
  # the hint's terms; a queued message (`said`) is the one text cut, the others are dropped whole
  said = NULL
  terms = if (is.null(draft)) {
    verb = if (isTRUE(state$steer)) ", then s, to steer" else
      if (isTRUE(state$pause)) " pause" else " stop"
    c(paste0(key, verb), if (isTRUE(state$typed)) "typed lines run next")
  } else if (!nzchar(draft) && frozen) {
    "keys show when r returns"
  } else if (!nzchar(draft) && is.null(state$newest)) {
    c(paste("enter", kind(enter)), paste("tab", kind(setdiff(c("steer", "follow_up"), enter))),
      paste(key, "pause"))
  } else if (!nzchar(draft)) {
    said = paste0(sym$queued, " ", kind(state$newest$kind), sym$sep, live_text(state$newest$text))
    c(said, paste(sym$up, "edit"))
  }
  hint = function(terms) {
    if (!length(terms)) return("")
    if (is.null(draft) || frozen) return(paste0(sym$sep, terms, collapse = ""))
    paste0("   ", paste(terms, collapse = sym$sep))
  }
  lead = paste0(sym$agent, " ")
  # a leading ! takes the chevron's place, as Codex's shell mode
  bang = startsWith(draft %||% "", "!")
  gap = paste0("   ", if (bang) "!" else sym$person, " ")
  input = if (nzchar(draft %||% "")) live_text(if (bang) substring(draft, 2L) else draft)
  room = width - 1L - live_fit(lead)
  if (room < live_fit(clock)) return("")
  # a / or ! draft (a follow-up whatever the key) says so before its glyph where that fits beside
  # the status at its widest this run, so the hint does not come and go with the status words
  after = "   runs after this answer"
  later = grepl("^\\s*[/!]", draft %||% "") && !length(state$candidates) &&
    max(live_fit(paste(words, collapse = sym$sep)), state$status_w %||% 0L) + live_fit(after) +
      live_fit(gap) + live_fit(input) <= room
  if (later) gap = paste0(after, gap)
  fit = if (is.null(input)) room else max(live_fit(clock), room - live_fit(gap) - live_fit(input))
  if (length(state$candidates)) {
    status = live_candidates(state$candidates, fit)
  } else {
    # a sub-agent's short form first; then dropped whole, from the right: the hint's terms, then
    # the queue and a waiting question; then the queued message is cut, keeping its head; at least
    # the block and the time
    repeat {
      status = paste0(paste(words, collapse = sym$sep), hint(terms))
      if (live_fit(status) <= fit) break
      if (!identical(words[[1L]], short)) {
        words[[1L]] = short
      } else if (length(terms) > !is.null(said)) {
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
  # the draft stays where it was this run: the status keeps the widest width it had (`status_w`),
  # but a bare clock, all that fits, is not padded
  shown = live_fit(status)
  pad = if (identical(status, clock)) 0L else min(fit, state$status_w %||% 0L) - shown
  status = paste0(status, strrep(" ", max(0L, pad)))
  row = paste0(sym$blue(sym$agent), " ", grey(paste0(status, if (later) after)))
  left = room - live_fit(status) - live_fit(gap)
  if (left > live_fit(sym$ellipsis)) {
    glyph = if (bang) cli::style_bold(sym$red("!")) else sym$person
    row = paste0(row, "   ", glyph, " ", live_fit(input, left, sym$ellipsis, tail = TRUE))
  }
  # completions show until the next key, and `keys wait` and `question waiting` until r returns or
  # the question is asked: they move the draft only while they show
  lasting = live_fit(paste(setdiff(words, c("keys wait", "question waiting")), collapse = sym$sep))
  structure(row, status_w = if (length(state$candidates)) 0L else min(shown, lasting))
}

#' Completion candidates on one row of `n` columns (IC-81): each escaped (live_text()), two blanks
#' apart, cut with an ellipsis
#' @noRd
live_candidates = function(cands, n) {
  live_fit(paste(vapply(cands, live_text, ""), collapse = "  "), n, console_style()$ellipsis)
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
#' terminal; RStudio) a row is `\r`, the row and `\033[K`, on the input band where it shows
#' (console_style(): a T console's; then `\033[0m`); elsewhere (R.app, Rgui, TERM=dumb, and
#' Positron, whose console erases by writing spaces) it is padded with spaces to width - 1, and a
#' clear writes spaces. Both `write` as every console control is (console_cat()), so from inside an
#' evaluation too the row reaches the console, never the tool's output. `the$live_row` holds the
#' row while it is up, so gptr_message_write() clears it before other output at its sink (`sinks`)
#' and redraws it after (`erase`), writing it itself; `on` says the run wants it drawn.
#' @noRd
console_live = function() {
  row = new.env(parent = emptyenv())
  row$erase = cli::is_ansi_tty() || front_end() == "rstudio"
  row$band = console_style()$band
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
#' console_ask_wait()), whether an r call evaluates in this process (`rec$frozen`, its call id;
#' during a sub-agent, which runs in the parent's r call and reads keys, one of the sub-agents'),
#' and the console's interrupt key and what it does (in RStudio, also that a typed line is the next
#' prompt); where a T console's composer reads keys (tty_call()), its draft, the newest message
#' waiting (console_newest()), the completion candidates its last key listed and the kind Enter
#' sends
#' @noRd
console_live_state = function(rec) {
  kids = console_kids()
  frozen = if (length(kids)) {
    any(vapply(kids, function(r) !is.null(r$frozen), NA))
  } else {
    !is.null(rec$frozen)
  }
  s = rec$session
  rd = if (isTRUE(the$tty$keys)) console_repl_prompt()$reader
  label = if (length(kids)) kids[[1L]]$child$label
  list(what = if (length(kids)) paste("sub-agent", label) else rec$what,
       short = if (length(kids)) paste("sub-agent", sub("^.* (#[0-9]+)$", "\\1", label)),
       secs = as.numeric(Sys.time()) - rec$t0, queued = console_queued(s),
       question = isTRUE(rec$question), frozen = isTRUE(frozen),
       key = console_interrupt_key(), pause = console_menu_available(),
       steer = console_menu_available() && front_end() == "positron",
       typed = front_end() == "rstudio",
       draft = if (!is.null(rd)) rd$compose$draft %||% "", candidates = rd$compose$candidates,
       newest = if (!is.null(rd)) console_newest(s, rd), enter = setting_get("type_ahead", s))
}

#' The records of the sub-agents the console shows (console_child_shown()), by label
#' @noRd
console_kids = function() {
  kids = Filter(function(r) !is.null(r$child), as.list(console_state()$active))
  kids[order(vapply(kids, function(r) r$child$label, ""))]
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
#' (console_render_on()) or a sub-agent it shows runs, whose run pumps the reactor inside the
#' parent's r call, on a dynamic console of an interactive R (not class P), but not in
#' R.app, whose console gives everything after a carriage return the input's colour
#' @noRd
console_live_start = function(rec) {
  rec$what = "thinking"
  rec$frozen = NULL
  row = the$live_row
  if (!identical(row$rec, rec)) {
    if (!cli::is_dynamic_tty() || console_class() == "P" || platform_gui() == "AQUA") {
      return(invisible(NULL))
    }
    console_live_stop()
    row = console_live()
    row$rec = rec
    the$live_row = row
    row$task = reactor_task(function() {
      if (!identical(the$live_row, row)) return(FALSE)
      if (row$on && (console_render_on(rec) || length(console_kids()))) row$draw()
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
