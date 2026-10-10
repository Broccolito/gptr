# console-render.R -- the console's printing layer (P14, layer L5, area console; architecture
# 6.17, contract 7.14). The markdown stream renderer and the spinner are report 18 Appendix A.6's
# md_stream() and wait_indicator(); every delta is UTF-8 marked (display widths, verification
# item 24), its line ends normalised and then escaped (IC-53 item 8). Untrusted text is written
# with cat() after console_escape(), never as a cli or glue format string (rule C1).

#' Symbols of the console with ASCII fallbacks (report 18 section 6: symbols vanish when the
#' output is not UTF-8)
#' @noRd
console_symbols = function() {
  if (cli::is_utf8_output()) {
    list(bullet = "\u2022 ", tool = "\u25cf ", bar = "\u2502 ", top = "\u250c\u2500 ",
         bottom = "\u2514\u2500", result = "\u23bf ", sep = " \u00b7 ",
         frames = c("\u280b", "\u2819", "\u2839", "\u2838", "\u283c", "\u2834", "\u2826",
                    "\u2827", "\u2807", "\u280f"))
  } else {
    list(bullet = "- ", tool = "* ", bar = "| ", top = "+- ", bottom = "+-", result = "-> ",
         sep = " | ", frames = c("-", "\\", "|", "/"))
  }
}

#' The key that interrupts R in this front end (Esc in Rgui, R.app and the IDE consoles; report
#' 18 section 6)
#' @noRd
console_interrupt_key = function() {
  if (front_end() %in% c("rgui", "rstudio", "positron")) "Esc" else "Ctrl-C"
}

#' Untrusted text as valid UTF-8; an invalid string shows its non-ASCII bytes as <xx>
#' @noRd
console_utf8 = function(x) {
  x = as_utf8(as.character(x))
  bad = !validUTF8(x)
  x[bad] = iconv(x[bad], "UTF-8", "ASCII", sub = "byte")
  x
}

#' Escape untrusted text for display with P11's ui_escape() (IC-53 item 8), keeping line feeds
#' unless `newlines = FALSE`; per character, so escaping commutes with chunking. NA stays NA.
#' @noRd
console_escape = function(x, newlines = TRUE) {
  if (!newlines) return(ui_escape(x))
  x = console_utf8(x)
  ok = !is.na(x)
  # The appended line feed keeps trailing empty lines through strsplit()
  x[ok] = vapply(strsplit(paste0(x[ok], "\n"), "\n", fixed = TRUE),
                 function(lines) paste(ui_escape(lines), collapse = "\n"), "")
  x
}

#' Lines of untrusted text for one-line displays: split on CRLF, CR and LF, then escaped
#' @noRd
console_lines = function(x) {
  x = console_utf8(x)
  x = x[!is.na(x)]
  if (!length(x)) return(character())
  ui_escape(strsplit(paste(x, collapse = "\n"), "\r\n|\r|\n", perl = TRUE)[[1L]])
}

#' Print untrusted text on stdout, one escaped line each
#' @noRd
console_out = function(x) {
  console_write(console_lines(x))
}

#' Print lines that are already safe (built from escaped parts) on stdout
#' @noRd
console_write = function(lines) {
  if (length(lines)) cat(paste0(lines, "\n"), sep = "")
  utils::flush.console()
  invisible(NULL)
}

#' A console notice on stderr (the pause menu can run inside a tool's stdout capture); callers
#' escape untrusted parts with console_escape()
#' @noRd
console_notice = function(...) {
  msg_verbatim(paste0(...), "stderr")
}

#' Chunk-invariant markdown stream renderer (contract 7.14)
#'
#' Returns an environment with `write(delta)`, `finish()` and `reset_line()`, writing to stdout.
#' Styling (bold, inline code, headings, bullets, quotes, fenced code) is used when
#' `cli::num_ansi_colors() > 1` at creation; the plain mode keeps the markdown characters and only
#' wraps at `width` display columns. A word is held until the next blank or line end, so the
#' output does not depend on how the text was chunked.
#' @noRd
render_markdown_stream = function(width = cli::console_width(), before_output = NULL) {
  style = cli::num_ansi_colors() > 1L
  sym = console_symbols()
  width = max(20L, as.integer(width))
  st = new.env(parent = emptyenv())
  st$buf = ""
  st$cr = ""
  st$col = 0L
  st$line_start = TRUE
  st$indent = 0L
  st$fence = FALSE
  st$fence_lang = ""
  st$bold = FALSE
  st$code = FALSE
  st$heading = FALSE
  st$space = FALSE
  sgr = function(code) if (style) paste0("\033[", code, "m") else ""
  emit = function(x) {
    if (nzchar(x)) {
      if (is.function(before_output)) before_output(x)
      cat(x, sep = "")
    }
    invisible()
  }
  vis_width = function(x) sum(nchar(x, type = "width"))
  reset_styles = function() if (st$heading || st$bold || st$code) sgr("0") else ""
  newline = function() {
    emit(paste0(reset_styles(), "\n"))
    st$col = 0L
    st$line_start = TRUE
    st$indent = 0L
    st$heading = FALSE
    st$bold = FALSE
    st$code = FALSE
    st$space = FALSE
  }
  inline = function(tok) {
    if (!style) return(list(text = tok, width = vis_width(tok)))
    out = character()
    w = 0L
    i = 1L
    n = nchar(tok)
    while (i <= n) {
      if (!st$code && identical(substr(tok, i, i + 1L), "**")) {
        st$bold = !st$bold
        out = c(out, if (st$bold) sgr("1") else sgr("22"))
        i = i + 2L
        next
      }
      ch = substr(tok, i, i)
      if (identical(ch, "`")) {
        st$code = !st$code
        out = c(out, if (st$code) sgr("36") else sgr("39"))
        i = i + 1L
        next
      }
      out = c(out, ch)
      w = w + vis_width(ch)
      i = i + 1L
    }
    list(text = paste(out, collapse = ""), width = w)
  }
  line_prefix = function(tok) {
    if (grepl("^#{1,6}$", tok)) {
      st$heading = TRUE
      return(list(text = if (style) sgr("1;4") else paste0(tok, " "),
                  width = if (style) 0L else nchar(tok) + 1L))
    }
    if (tok %in% c("-", "*", "+")) {
      st$indent = 2L
      return(list(text = if (style) sym$bullet else "- ", width = 2L))
    }
    if (grepl("^[0-9]+[.)]$", tok)) {
      st$indent = nchar(tok) + 1L
      return(list(text = paste0(tok, " "), width = nchar(tok) + 1L))
    }
    if (identical(tok, ">")) {
      st$indent = 2L
      return(list(text = if (style) paste0(sgr("2"), sym$bar, sgr("22")) else "> ", width = 2L))
    }
    NULL
  }
  fence_line = function(line) {
    code = line
    if (st$fence_lang %in% c("r", "R", "{r}") && nzchar(trimws(line))) {
      code = tryCatch(cli::code_highlight(line), error = function(e) line)
    }
    emit(paste0(sgr("2"), sym$bar, sgr("22"), code, "\n"))
  }
  fence_marker = function(line) {
    if (!st$fence) {
      st$fence = TRUE
      st$fence_lang = trimws(substring(line, 4L))
      emit(paste0(if (style) paste0(sgr("2"), sym$top, st$fence_lang, sgr("22")) else line, "\n"))
    } else {
      st$fence = FALSE
      emit(paste0(if (style) paste0(sgr("2"), sym$bottom, sgr("22")) else line, "\n"))
    }
  }
  process = function(text, final = FALSE) {
    text = paste0(st$buf, text)
    st$buf = ""
    repeat {
      if (!nzchar(text)) break
      if (st$fence || (st$line_start && startsWith(text, "```"))) {
        nl = regexpr("\n", text, fixed = TRUE)
        if (nl < 0L) {
          if (final) {
            text = paste0(text, "\n")
            next
          }
          st$buf = text
          return(invisible())
        }
        line = substr(text, 1L, nl - 1L)
        text = substr(text, nl + 1L, nchar(text))
        if (startsWith(line, "```")) {
          fence_marker(line)
        } else if (style) {
          fence_line(line)
        } else {
          emit(paste0(line, "\n"))
        }
        st$col = 0L
        st$line_start = TRUE
        next
      }
      m = regexpr("^(\n|[ \t]+|[^ \t\n]+)", text)
      tok = regmatches(text, m)
      rest = substr(text, attr(m, "match.length") + 1L, nchar(text))
      if (!nzchar(rest) && !final && !identical(tok, "\n")) {
        st$buf = tok
        return(invisible())
      }
      text = rest
      if (identical(tok, "\n")) {
        newline()
        next
      }
      if (grepl("^[ \t]+$", tok)) {
        if (st$line_start || st$col == st$indent) next
        st$space = TRUE
        next
      }
      if (st$line_start) {
        st$line_start = FALSE
        pre = line_prefix(tok)
        if (!is.null(pre)) {
          emit(pre$text)
          st$col = st$col + pre$width
          if (nzchar(text) && grepl("^[ \t]", text)) text = sub("^[ \t]+", "", text)
          next
        }
      }
      w = inline(tok)
      sp = isTRUE(st$space)
      st$space = FALSE
      if (st$col > st$indent && st$col + sp + w$width > width) {
        emit(paste0(reset_styles(), "\n", strrep(" ", st$indent),
                    if (st$heading) sgr("1;4") else "", if (st$bold) sgr("1") else "",
                    if (st$code) sgr("36") else ""))
        st$col = st$indent
      } else if (sp) {
        emit(" ")
        st$col = st$col + 1L
      }
      emit(w$text)
      st$col = st$col + w$width
    }
    invisible()
  }
  # Line ends first (CRLF and lone CR become LF; a trailing CR waits for the next chunk), then
  # escaping, then rendering: each step is chunk-invariant
  ingest = function(delta, final = FALSE) {
    text = paste0(st$cr, paste(console_utf8(delta), collapse = ""))
    st$cr = ""
    if (!final && endsWith(text, "\r")) {
      st$cr = "\r"
      text = substr(text, 1L, nchar(text) - 1L)
    }
    process(console_escape(gsub("\r\n?", "\n", text)), final)
  }
  r = new.env(parent = emptyenv())
  r$write = function(delta) {
    ingest(delta)
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$finish = function() {
    ingest("", final = TRUE)
    if (st$col > 0L) newline()
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$reset_line = function() {
    if (st$col > 0L) newline()
    invisible()
  }
  r
}

#' Print a complete text through the markdown renderer (one shot)
#' @noRd
console_print_text = function(text) {
  text = text[!is.na(text)]
  if (!any(nzchar(text))) return(invisible())
  r = render_markdown_stream()
  r$write(paste(text, collapse = "\n"))
  r$finish()
}

#' The waiting indicator (report 18 A.6 wait_indicator()), ticked by its caller
#'
#' Uses only "\r" redraws (safe in RStudio and Windows consoles); `tick()` is a no-op when stdout
#' is not a dynamic terminal, so tests, pipes and knitr never see it.
#' @noRd
console_spinner = function(label = "thinking") {
  frames = console_symbols()$frames
  key = console_interrupt_key()
  action = if (console_menu_available()) "steer or stop" else "stop"
  sp = new.env(parent = emptyenv())
  sp$dynamic = cli::is_dynamic_tty()
  sp$i = 0L
  sp$t0 = as.numeric(Sys.time())
  sp$shown = FALSE
  sp$last = 0
  sp$tick = function() {
    if (!sp$dynamic) return(invisible())
    now = as.numeric(Sys.time())
    if (now - sp$last < 0.08) return(invisible())
    sp$last = now
    sp$i = sp$i %% length(frames) + 1L
    cat(sprintf("\r%s %s (%.0fs, %s to %s)", frames[[sp$i]], label, now - sp$t0, key, action),
        sep = "")
    utils::flush.console()
    sp$shown = TRUE
    invisible()
  }
  sp$clear = function() {
    if (sp$shown) {
      cat("\r", strrep(" ", max(0L, cli::console_width() - 1L)), "\r", sep = "")
      utils::flush.console()
      sp$shown = FALSE
    }
    invisible()
  }
  sp
}

# ---- renderer hooks ---------------------------------------------------------------------------
# Rendering subscribes to events (INFRA-27): process-wide notify hooks render runs of foreground
# sessions at verbosity() >= 2 and report progress on stderr at verbosity 1. `the$console$active`
# maps a run id to its session from agent_start to agent_end, at any verbosity, because the
# interrupt policy needs the session of a run (04 gives no accessor from a run to its session).

#' The console's process state (`the$console`, owned by P14): `active` (run id -> record);
#' `artifacts` (NS-8 lines) and `pending` (pause-menu items) held while a tool executes
#' @noRd
console_state = function() {
  if (is.null(the$console)) {
    the$console = new.env(parent = emptyenv())
    the$console$active = new.env(parent = emptyenv())
  }
  the$console
}

#' Start tracking a run of a session: a record with its session, tool calls and entry count
#' @noRd
console_track = function(run_id, session) {
  rec = new.env(parent = emptyenv())
  rec$session = session
  rec$tools = new.env(parent = emptyenv())
  rec$n0 = length(session_data(session)$entries)
  rec$request_pending = FALSE
  assign(run_id, rec, envir = console_state()$active)
  invisible(rec)
}

#' The record of the run an event belongs to, or NULL
#' @noRd
console_record = function(event) {
  if (!rlang::is_string(event$run)) return(NULL)
  get0(event$run, envir = console_state()$active, inherits = FALSE)
}

#' Forget a run after stopping its spinner
#' @noRd
console_drop = function(run_id) {
  active = console_state()$active
  rec = get0(run_id, envir = active, inherits = FALSE)
  if (!is.null(rec)) {
    console_spinner_stop(rec)
    rm(list = run_id, envir = active)
  }
  invisible(NULL)
}

#' A foreground session: depth 0, live, not handed to P21's background pump; never while a tool
#' executes on the stack, whose output P09 captures for the model (nested calls: `details$nested`)
#' @noRd
console_foreground = function(rec) {
  live = session_live(rec$session)
  !is.null(live) && is.null(live$background) &&
    identical(session_data(rec$session)$depth, 0L) && is.null(run_current())
}

#' Render this record on stdout now?
#' @noRd
console_render_on = function(rec) {
  verbosity() >= 2L && console_foreground(rec)
}

#' Start the spinner of a record, ticked by a reactor task every 0.1 s (03 section 6.17)
#' @noRd
console_spinner_start = function(rec) {
  if (!is.null(rec$task) || !cli::is_dynamic_tty()) return(invisible(NULL))
  rec$spinner = console_spinner("thinking")
  rec$spinner$tick()
  rec$task = reactor_task(function() {
    if (is.null(rec$spinner)) return(FALSE)
    if (console_render_on(rec)) rec$spinner$tick()
    0.1
  })
  invisible(NULL)
}

#' Stop the spinner of a record and clear its line
#' @noRd
console_spinner_stop = function(rec) {
  if (!is.null(rec$spinner)) rec$spinner$clear()
  if (!is.null(rec$task)) reactor_cancel(rec$task)
  rec$spinner = NULL
  rec$task = NULL
  invisible(NULL)
}

#' Normal progress: stdout in an IRkernel cell, else the usual stderr message. Callers keep
#' their verbosity/foreground gates and escape untrusted parts; failures do not use this path.
#' @noRd
console_progress = function(text) {
  if (isTRUE(getOption("gptr.quiet"))) return(invisible(NULL))
  if (isTRUE(getOption("jupyter.in_kernel")) && !is_knitting()) {
    console_write(text)
  } else {
    gptr_inform(text, "progress")
  }
  invisible(NULL)
}

#' Waiting feedback: a dynamic spinner for streamed consoles, else concise progress
#' @noRd
console_wait_start = function(rec) {
  if (verbosity() < 1L || !console_foreground(rec)) return(invisible(NULL))
  if (verbosity() >= 2L && cli::is_dynamic_tty()) {
    console_spinner_start(rec)
  } else {
    console_progress("gptr: thinking")
  }
  invisible(NULL)
}

#' Restore waiting feedback after a pause, only while the same foreground request is pending
#' @noRd
console_render_resume = function(runs) {
  for (run in runs) {
    rec = console_record(list(run = run$id))
    if (!is.null(rec) && isTRUE(rec$request_pending) &&
        run$status %in% c("requesting", "streaming")) console_wait_start(rec)
  }
  invisible(NULL)
}

#' A record-only callback: clear before visible text; blank output clears only the current redraw
#' @noRd
console_stream_output = function(rec) {
  force(rec)
  function(text) {
    if (is.null(rec$spinner)) return(invisible(NULL))
    if (grepl("[^[:space:]]", cli::ansi_strip(text))) {
      console_spinner_stop(rec)
    } else {
      rec$spinner$clear()
    }
    invisible(NULL)
  }
}

#' End the partial lines of a record (before a tool line, a prompt or the pause menu)
#' @noRd
console_pause_one = function(rec) {
  console_spinner_stop(rec)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish()
  invisible(NULL)
}

#' End the partial lines of every tracked run (the pause menu, approval prompts)
#' @noRd
console_render_pause = function() {
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) console_pause_one(get(id, envir = active))
  invisible(NULL)
}

#' Only text blocks, joined with the same line breaks as msg_text()
#' @noRd
console_msg_text = function(msg) {
  text = vapply(msg$content %||% list(), function(b) {
    if (identical(b$type, "text") && rlang::is_string(b$text)) b$text else NA_character_
  }, "")
  paste(text[!is.na(text)], collapse = "\n")
}

#' The preview lines of a tool input: its code, its path, its questions, else compact JSON
#' @noRd
console_preview = function(input) {
  text = if (is.character(input$code) && length(input$code)) {
    paste(input$code, collapse = "\n")
  } else if (is.character(input$path) && length(input$path)) {
    input$path[[1L]]
  } else if (is.list(input$questions)) {
    paste0(length(input$questions), " question(s)")
  } else if (length(input)) {
    tryCatch(json_encode(input), error = function(e) "")
  } else {
    ""
  }
  strsplit(text, "\n", fixed = TRUE)[[1L]]
}

#' The default start line of a tool call: "  * r  first line  (+N more lines)" (NS-1)
#' @noRd
console_call_line = function(call) {
  lines = console_preview(call$input)
  more = if (length(lines) > 1L) paste0("  (+", length(lines) - 1L, " more lines)") else ""
  paste0("  ", console_symbols()$tool, console_escape(call$name %||% "?", FALSE), "  ",
         console_escape(c(lines, "")[[1L]], FALSE), more)
}

#' The default result lines of a tool call: errors, object changes of `r`, the diff of `edit`,
#' the path of `write`, else the elapsed time when it took a second or more
#' @noRd
console_result_lines = function(call, result) {
  pad = paste0("    ", console_symbols()$result)
  el = result$elapsed
  secs = if (isTRUE(el >= 1)) sprintf(" (%.1f s)", el) else ""
  d = result$details %||% list()
  if (isTRUE(result$is_error)) {
    first = c(strsplit(console_msg_text(result), "\n", fixed = TRUE)[[1L]], "failed")[[1L]]
    return(cli::col_red(paste0(pad, "error: ", console_escape(first, FALSE), secs)))
  }
  if (identical(call$name, "r")) {
    obj = d$objects
    parts = c(
      if (length(obj$added)) paste0("+ ", paste(obj$added, collapse = ", ")),
      if (length(obj$modified)) paste0("~ ", paste(obj$modified, collapse = ", ")),
      if (length(obj$removed)) paste0("- ", paste(obj$removed, collapse = ", ")),
      if (isTRUE(d$plots >= 1L)) paste0("[", d$plots, if (d$plots == 1L) " plot]" else " plots]")
    )
    if (length(parts)) {
      return(paste0(pad, console_escape(paste(parts, collapse = "  "), FALSE), secs))
    }
  }
  if (identical(call$name, "edit") && is.character(d$diff) && length(d$diff)) {
    shown = utils::head(d$diff, 12L)
    lines = paste0("    ", console_escape(shown, FALSE))
    lines = ifelse(startsWith(shown, "+"), cli::col_green(lines),
                   ifelse(startsWith(shown, "-"), cli::col_red(lines), lines))
    more = length(d$diff) - 12L
    return(c(lines, if (more > 0L) paste0("    (+", more, " more lines)")))
  }
  if (identical(call$name, "write") && rlang::is_string(d$path)) {
    bytes = if (is.numeric(d$bytes)) paste0(" (", format(d$bytes, big.mark = ","), " bytes)")
    return(paste0(pad, "wrote ", console_escape(d$path, FALSE), bytes, secs))
  }
  if (nzchar(secs)) paste0(pad, "done", secs) else character()
}

#' The console lines of a tool call (`result = NULL`) or of its result, fitted to `width`
#'
#' A tool spec's `render(call, result, width)` wins (IC-69), escaped like any untrusted text;
#' `call` is `list(id, name, input)`, `result` the tool-result message plus `elapsed`.
#' @noRd
console_tool_line = function(call, result = NULL, session = NULL, width = cli::console_width()) {
  out = tryCatch({
    spec = registry_get("tool", call$name, session = session)
    if (is.function(spec$render)) spec$render(call, result, width)
  }, error = function(e) NULL)
  out = if (is.character(out)) {
    console_escape(out, FALSE)
  } else if (is.null(result)) {
    console_call_line(call)
  } else {
    console_result_lines(call, result)
  }
  as.character(cli::ansi_strtrim(out, max(20L, as.integer(width))))
}

#' The status line of a run's end: `  done | 2 turns | 1.2k tokens | $0.0042`; the status and
#' reason when it did not end idle; an unknown (NA) usage value is unknown (IC-74)
#' @noRd
console_status_line = function(status, reason = NULL, usage = NULL, turns = NULL) {
  word = if (identical(status, "idle")) "done" else console_escape(status %||% "?", FALSE)
  if (!identical(status, "idle") && rlang::is_string(reason) && nzchar(reason)) {
    word = paste0(word, ": ", console_escape(reason, FALSE))
  }
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  parts = c(word,
            if (length(turns) == 1L && !is.na(turns)) {
              paste0(turns, if (turns == 1L) " turn" else " turns")
            },
            paste(format_count(unlist(usage[intersect(cols, names(usage))])), "tokens"),
            format_cost(usage$cost))
  paste0("  ", paste(parts, collapse = console_symbols()$sep))
}

#' Show the custom entries appended during a run through `renderer` records (IC-69)
#' @noRd
console_render_custom = function(s, n0) {
  d = session_data(s)
  ctx = session_live(s)$ctx
  for (e in d$entries[seq_along(d$entries) > n0]) {
    if (!identical(e$type, "custom")) next
    out = tryCatch({
      spec = registry_get("renderer", e$custom_type, session = d$id)
      if (is.function(spec$render)) spec$render(e, cli::console_width(), ctx)
    }, error = function(err) NULL)
    if (is.character(out)) console_write(console_escape(out, FALSE))
  }
  invisible(NULL)
}

#' agent_start: track the run
#' @noRd
console_on_agent_start = function(event, ctx) {
  s = ctx$session
  if (inherits(s, "gptr_session") && rlang::is_string(event$run)) console_track(event$run, s)
  NULL
}

#' before_request: announce waiting; at verbosity 3 also a request line
#' @noRd
console_on_before_request = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  rec$request_pending = TRUE
  if (verbosity() < 1L || !console_foreground(rec)) return(NULL)
  if (verbosity() >= 3L) {
    console_pause_one(rec)
    console_write(cli::col_grey(sprintf(
      "  request %s -> %s (~%.0f tokens)", console_escape(event$request_id %||% "", FALSE),
      console_escape(event$model %||% "", FALSE), as.numeric(event$tokens_est %||% 0))))
  }
  console_wait_start(rec)
  NULL
}

#' message_update: stream text deltas through the markdown renderer; thinking at verbosity 3
#' @noRd
console_on_message_update = function(event, ctx) {
  rec = console_record(event)
  delta = event$delta
  if (is.null(rec) || !is.character(delta) || !console_render_on(rec)) return(NULL)
  kind = event$kind %||% "text"
  if (identical(kind, "text")) {
    if (!is.null(rec$think)) rec$think$finish()
    rec$think = NULL
    if (!is.null(rec$md) && !identical(rec$md_index, event$index)) {
      rec$md$finish()
      rec$md = NULL
    }
    if (is.null(rec$md)) {
      rec$md = render_markdown_stream(before_output = console_stream_output(rec))
    }
    rec$md_index = event$index
    rec$md$write(delta)
  } else if (identical(kind, "thinking") && verbosity() >= 3L) {
    console_spinner_stop(rec)
    if (is.null(rec$think)) {
      if (!is.null(rec$md)) rec$md$finish()
      console_write(cli::col_grey("  (thinking)"))
      rec$think = render_markdown_stream(before_output = console_stream_output(rec))
    }
    rec$think$write(delta)
  }
  NULL
}

#' message_end: close the streamed answer, or print it whole when nothing was streamed; for a
#' tool result, its result lines
#' @noRd
console_on_message_end = function(event, ctx) {
  rec = console_record(event)
  msg = event$message
  if (is.null(rec) || !is.list(msg)) return(NULL)
  if (identical(msg$role, "assistant")) rec$request_pending = FALSE
  if (!console_render_on(rec)) return(NULL)
  if (identical(msg$role, "assistant")) {
    console_spinner_stop(rec)
    if (!is.null(rec$think)) rec$think$finish()
    if (is.null(rec$md)) console_print_text(console_msg_text(msg)) else rec$md$finish()
    rec$think = NULL
    rec$md = NULL
    rec$md_index = NULL
  } else if (identical(msg$role, "tool_result")) {
    call = get0(paste0("t", msg$tool_call_id), envir = rec$tools, inherits = FALSE) %||%
      list(id = msg$tool_call_id, name = msg$tool_name, input = list())
    result = c(msg[c("content", "is_error", "details")], list(elapsed = call$elapsed))
    console_write(console_tool_line(call, result, rec$session))
  }
  NULL
}

#' tool_execution_start: one line per call (verbosity 2) or a progress message (verbosity 1)
#' @noRd
console_on_tool_start = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_foreground(rec)) return(NULL)
  call = list(id = event$tool_call_id, name = event$tool_name, input = event$input %||% list())
  v = verbosity()
  if (v == 1L) {
    console_progress(paste0("gptr: ", console_escape(call$name %||% "?", FALSE), "  ",
                            console_escape(c(console_preview(call$input), "")[[1L]], FALSE)))
  } else if (v >= 2L) {
    assign(paste0("t", call$id), call, envir = rec$tools)
    console_pause_one(rec)
    console_write(console_tool_line(call, NULL, rec$session))
  }
  NULL
}

#' tool_execution_end: queue the pause-menu items and print the artifact lines held while tools
#' ran, keep the elapsed time for the result line, report a failure at verbosity 1
#' @noRd
console_on_tool_end = function(event, ctx) {
  policy_flush()
  console_artifact_flush()
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  key = paste0("t", event$tool_call_id)
  call = get0(key, envir = rec$tools, inherits = FALSE)
  if (!is.null(call)) {
    call$elapsed = event$elapsed
    assign(key, call, envir = rec$tools)
  }
  if (verbosity() == 1L && isTRUE(event$is_error) && console_foreground(rec)) {
    gptr_inform(paste0("gptr: ", console_escape(event$tool_name %||% "?", FALSE), " failed"),
                "progress")
  }
  NULL
}

#' permission_request: end partial lines before the UI asks; never decides and never fails, since
#' a failing permission_request handler denies (04 section 10.7)
#' @noRd
console_on_permission = function(event, ctx) {
  tryCatch(console_render_pause(), error = function(e) NULL)
  NULL
}

#' retry_start: say that a request is retried
#' @noRd
console_on_retry = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  console_pause_one(rec)
  console_write(cli::col_grey(sprintf("  retrying in %.1f s (%s)",
                                      as.numeric(event$delay %||% 0),
                                      console_escape(event$class %||% "error", FALSE))))
  NULL
}

#' agent_end: close the streams, show custom entries and the status line, forget the run; queued
#' artifact lines (an interrupted tool) print last
#' @noRd
console_on_agent_end = function(event, ctx) {
  on.exit(console_artifact_flush(), add = TRUE)
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  on.exit(console_drop(event$run), add = TRUE)
  console_spinner_stop(rec)
  if (!console_foreground(rec)) return(NULL)
  line = console_status_line(event$status, event$reason, event$usage, event$turns)
  v = verbosity()
  if (v == 1L) {
    text = paste0("gptr:", sub("^ +", " ", line))
    if (identical(event$status, "idle")) console_progress(text) else gptr_inform(text, "progress")
  }
  if (v < 2L) return(NULL)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish()
  console_render_custom(rec$session, rec$n0)
  console_write(cli::col_grey(line))
  NULL
}

#' artifact_start: the NS-8 line `artifact  <id>  ->  <url>   (running in background)` (IC-71)
#'
#' The event usually fires inside the model's `r` code (`peter$app()`), whose output P09's
#' evaluator captures into the tool result; so while a tool executes the line is queued and the
#' tool_execution_end hook (or agent_end) prints it once no tool executes on the stack.
#' @noRd
console_on_artifact_start = function(event, ctx) {
  if (verbosity() < 1L) return(NULL)
  line = paste0("artifact  ", console_escape(event$id %||% "?", FALSE), "  ->  ",
                console_escape(event$url %||% "?", FALSE), "   (running in background)")
  if (is.null(run_current())) return(console_artifact_emit(line))
  st = console_state()
  st$artifacts = c(st$artifacts, line)
  NULL
}

#' Print NS-8 lines: on stdout at verbosity 2 or 3, as progress on stderr at verbosity 1
#' @noRd
console_artifact_emit = function(lines) {
  v = verbosity()
  if (v == 1L) gptr_inform(lines, "progress")
  if (v >= 2L) console_write(lines)
  NULL
}

#' Print the queued NS-8 lines once no tool executes on the stack
#' @noRd
console_artifact_flush = function() {
  st = console_state()
  if (!length(st$artifacts) || !is.null(run_current())) return(invisible(NULL))
  lines = st$artifacts
  st$artifacts = NULL
  console_artifact_emit(lines)
  invisible(NULL)
}

#' session_shutdown: forget every run of the session
#' @noRd
console_on_shutdown = function(event, ctx) {
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) {
    if (identical(session_data(get(id, envir = active)$session)$id, event$session)) {
      console_drop(id)
    }
  }
  NULL
}

#' The renderer hooks builtin_console() registers (04 section 7.14)
#' @noRd
console_hooks = function() {
  list(
    gptr_hook("agent_start", console_on_agent_start),
    gptr_hook("before_request", console_on_before_request),
    gptr_hook("message_update", console_on_message_update),
    gptr_hook("message_end", console_on_message_end),
    gptr_hook("tool_execution_start", console_on_tool_start),
    gptr_hook("tool_execution_end", console_on_tool_end),
    gptr_hook("permission_request", console_on_permission),
    gptr_hook("retry_start", console_on_retry),
    gptr_hook("agent_end", console_on_agent_end),
    gptr_hook("artifact_start", console_on_artifact_start),
    gptr_hook("session_shutdown", console_on_shutdown)
  )
}
