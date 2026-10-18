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
    list(bullet = "\u2022 ", nested = "\u25e6 ", tool = "\u25cf ", sep = " \u00b7 ",
         frames = c("\u280b", "\u2819", "\u2839", "\u2838", "\u283c", "\u2834", "\u2826",
                    "\u2827", "\u2807", "\u280f"))
  } else {
    list(bullet = "- ", nested = "- ", tool = "* ", sep = " | ", frames = c("-", "\\", "|", "/"))
  }
}

#' The key that interrupts R in this front end (Esc in Rgui, R.app and the IDE consoles; report
#' 18 section 6)
#' @noRd
console_interrupt_key = function() {
  if (front_end() %in% c("rgui", "rstudio", "positron")) "Esc" else "Ctrl-C"
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
  if (length(lines)) console_cat(paste0(lines, "\n", collapse = ""))
  invisible(NULL)
}

#' Every console write: through gptr_message_write(), so it is plain stdout outside an evaluation
#' and reaches the console, never the captured output, inside one (D-188)
#' @noRd
console_cat = function(text) gptr_message_write(text, gptr_message_stream("stdout"))

#' Ordinary console notices on stdout; actual errors on stderr. The scoped evaluator writer
#' keeps pause-menu controls out of tool output. Callers escape parts with console_escape().
#' @noRd
console_notice = function(..., .error = FALSE) {
  stream = gptr_message_stream(if (.error) "stderr" else "stdout")
  gptr_message_write(paste0(paste0(...), "\n"), stream, margin = TRUE)
}

#' Chunk-invariant markdown stream renderer (contract 7.14)
#'
#' Returns an environment with `write(delta)`, `finish()` and `reset_line()`, writing to stdout.
#' Styling (bold, italic at token edges, inline code, dim link URLs, headings, bullets, dim
#' quotes and rules, highlighted fenced code) is used when `cli::num_ansi_colors() > 1` at
#' creation; without it the markdown characters are kept. Fenced code stays Markdown: fence lines
#' as written (dim), the body unwrapped and de-indented by the opener's indentation (D-187).
#' Where console_pad() gives a margin (D-186) lines get two columns on both sides, nested list
#' indentation is kept, pipe tables are aligned, blank lines collapse to one between blocks (none
#' before or after a reply) and code characters appear as they arrive, a line that fits one row
#' redrawn highlighted; elsewhere the plain mode only wraps at `width` display columns. A word is
#' held until the next blank or line end, so the output does not depend on how the text was
#' chunked at a fixed width. When width is omitted, each write and final flush sample the current
#' console width; an explicit width stays fixed.
#' @noRd
render_markdown_stream = function(width = cli::console_width(), before_output = NULL) {
  auto_width = missing(width)
  style = cli::num_ansi_colors() > 1L
  pad = console_pad()
  lay = nzchar(pad)
  sym = console_symbols()
  st = new.env(parent = emptyenv())
  set_width = function(w) st$width = max(20L, as.integer(w) - 2L * nchar(pad))
  set_width(width)
  st$buf = ""
  st$cr = ""
  st$col = 0L
  st$bol = TRUE
  st$out = FALSE
  st$blank = FALSE
  st$line_start = TRUE
  st$ws = 0L
  st$indent = 0L
  st$fence = FALSE
  st$fence_n = 0L
  st$fence_lang = ""
  st$fence_indent = 0L
  st$shown = 0L
  st$table = character()
  st$space = FALSE
  codes = c(h1 = "1;4", h = "1", bold = "1", italic = "3", code = "36", url = "2")
  st$on = logical(length(codes))
  names(st$on) = names(codes)
  sgr = function(code) if (style) paste0("\033[", code, "m") else ""
  restyle = function() sgr(paste(c("0", codes[st$on]), collapse = ";"))
  toggle = function(name) {
    st$on[[name]] = !st$on[[name]]
    restyle()
  }
  # The margin opens every non-empty row; a pending blank line is written only before more text
  emit = function(x) {
    if (!nzchar(x)) return(invisible())
    if (st$bol && !startsWith(x, "\n")) {
      x = paste0(if (st$blank) "\n", pad, x)
      st$blank = FALSE
    }
    st$bol = endsWith(x, "\n")
    st$out = TRUE
    if (is.function(before_output)) before_output(x)
    console_cat(x)
    invisible()
  }
  vis_width = function(x) sum(nchar(x, type = "width"))
  newline = function() {
    if (lay && st$line_start) {
      st$blank = st$out
    } else {
      emit(paste0(if (any(st$on)) sgr("0"), "\n"))
    }
    st$col = 0L
    st$line_start = TRUE
    st$ws = 0L
    st$indent = 0L
    st$on[] = FALSE
    st$space = FALSE
  }
  # A block ends: its trailing blank lines are dropped and the next block starts afresh
  end_block = function() {
    if (length(st$table)) table_flush()
    if (!st$bol) {
      newline()
      # a held inter-word blank of the ended line would read as indentation of the next one;
      # a broken fenced line is shown whole again
      if (st$fence) st$shown = 0L else st$buf = sub("^[ \t]+$", "", st$buf)
    }
    st$blank = FALSE
    st$out = FALSE
  }
  inline = function(tok) {
    if (!style) return(list(text = tok, width = vis_width(tok)))
    out = character()
    w = 0L
    i = 1L
    n = nchar(tok)
    while (i <= n) {
      ch = substr(tok, i, i)
      two = substr(tok, i, i + 1L)
      if (identical(ch, "`")) {
        out = c(out, toggle("code"))
      } else if (st$on[["code"]]) {
        out = c(out, ch)
        w = w + vis_width(ch)
      } else if (identical(two, "**")) {
        out = c(out, toggle("bold"))
        i = i + 1L
      } else if (identical(ch, "*") && (if (st$on[["italic"]]) {
        grepl("^[[:punct:]]*$", substring(tok, i + 1L))
      } else {
        i == 1L && n > 1L
      })) {
        out = c(out, toggle("italic"))
      } else if (identical(two, "](") || (identical(ch, ")") && st$on[["url"]])) {
        out = c(out, ch, toggle("url"))
        w = w + 1L
      } else {
        out = c(out, ch)
        w = w + vis_width(ch)
      }
      i = i + 1L
    }
    list(text = paste(out, collapse = ""), width = w)
  }
  line_prefix = function(tok, after) {
    n = if (lay) min(st$ws, st$width %/% 2L) else 0L
    lead = strrep(" ", n)
    if (grepl("^#{1,6}$", tok)) {
      st$on[[if (nchar(tok) == 1L) "h1" else "h"]] = TRUE
      return(list(text = if (style) restyle() else paste0(tok, " "),
                  width = if (style) 0L else nchar(tok) + 1L))
    }
    if (style && grepl("^(-{3,}|\\*{3,}|_{3,})$", tok) && !grepl("^[ \t]", after)) {
      return(list(text = paste0(sgr("2"), strrep("-", st$width), sgr("22")), width = st$width))
    }
    if (tok %in% c("-", "*", "+")) {
      st$indent = n + 2L
      mark = if (!style) "- " else if (n > 0L) sym$nested else sym$bullet
      return(list(text = paste0(lead, mark), width = st$indent))
    }
    if (grepl("^[0-9]+[.)]$", tok)) {
      st$indent = n + nchar(tok) + 1L
      return(list(text = paste0(lead, tok, " "), width = st$indent))
    }
    if (identical(tok, ">")) {
      st$indent = n + 2L
      return(list(text = paste0(lead, if (style) paste0(sgr("2"), "> ", sgr("22")) else "> "),
                  width = st$indent))
    }
    if (n > 0L) {
      st$indent = n
      return(list(text = lead, width = n, keep = TRUE))
    }
    NULL
  }
  # In the margin a fenced line's characters appear as they arrive
  fence_stream = function(line) {
    add = substring(line, st$shown + 1L)
    if (!lay || !nzchar(add)) return(invisible())
    emit(add)
    st$shown = nchar(line)
    st$col = st$col + vis_width(add)
    st$line_start = FALSE
  }
  # An ended fenced line in its style `out`: a streamed one is redrawn when it filled one row
  # (a TAB has no width in nchar(), so a line with one is never redrawn)
  fence_end = function(line, out) {
    streamed = st$shown > 0L
    st$shown = 0L
    if (!streamed) {
      emit(paste0(out, "\n"))
    } else {
      fit = style && st$col <= st$width && !grepl("\t", line, fixed = TRUE)
      emit(if (fit) paste0("\r", pad, out, "\n") else "\n")
    }
  }
  fence_marker = function(line) {
    st$fence = !st$fence
    if (st$fence) {
      st$fence_n = attr(regexpr("^`{3,}", line), "match.length")
      st$fence_lang = trimws(substring(line, st$fence_n + 1L))
      st$fence_indent = st$ws
    }
    fence_end(line, paste0(sgr("2"), line, sgr("22")))
  }
  # A block of pipe-table rows, aligned when it has a delimiter row, one cell count and fits;
  # either way it stays a valid pipe table
  table_flush = function() {
    rows = st$table
    st$table = character()
    cells = lapply(rows, function(r) {
      trimws(strsplit(sub("^\\|", "", sub("\\|[ \t]*$", "", r)), "|", fixed = TRUE)[[1L]])
    })
    k = length(cells[[1L]])
    ok = length(rows) >= 2L && k > 0L && all(lengths(cells) == k) &&
      all(grepl("^:?-+:?$", cells[[2L]]))
    body = cells[-2L]
    widths = if (ok) do.call(pmax, c(lapply(body, nchar, type = "width"), 3L))
    if (!ok || sum(widths) + 3L * k + 1L > st$width) {
      for (r in rows) emit(paste0(r, "\n"))
      return(invisible())
    }
    d = cells[[2L]]
    align = ifelse(endsWith(d, ":"), ifelse(startsWith(d, ":"), "c", "r"), "l")
    row = function(cl) {
      gap = widths - nchar(cl, type = "width")
      left = ifelse(align == "r", gap, ifelse(align == "c", gap %/% 2L, 0L))
      paste0("| ", paste0(strrep(" ", left), cl, strrep(" ", gap - left), collapse = " | "), " |")
    }
    rule = paste0("|", paste0(ifelse(align == "c", ":", "-"), strrep("-", widths),
                              ifelse(align == "l", "-", ":"), collapse = "|"), "|")
    emit(paste0(sgr("1"), row(body[[1L]]), sgr("22"), "\n"))
    for (r in c(rule, vapply(body[-1L], row, ""))) emit(paste0(r, "\n"))
  }
  process = function(text, final = FALSE) {
    text = paste0(st$buf, text)
    st$buf = ""
    repeat {
      if (!nzchar(text)) break
      if (length(st$table) && st$line_start && !grepl("^[ \t|]", text)) table_flush()
      table_row = lay && st$line_start && !st$fence && startsWith(text, "|")
      if (st$fence || table_row || (st$line_start && startsWith(text, "```"))) {
        nl = regexpr("\n", text, fixed = TRUE)
        line = if (nl < 0L) text else substr(text, 1L, nl - 1L)
        if (st$fence) {
          line = sub(paste0("^ {0,", st$fence_indent, "}"), "", line)
          fence_stream(line)
        }
        if (nl < 0L) {
          if (final) {
            text = paste0(text, "\n")
            next
          }
          st$buf = text
          return(invisible())
        }
        text = substr(text, nl + 1L, nchar(text))
        opening = !st$fence && startsWith(line, "```")
        closing = st$fence && grepl("^ {0,3}`{3,}[ \t]*$", line) &&
          nchar(trimws(line)) >= st$fence_n
        if (table_row) {
          st$table = c(st$table, line)
        } else if (opening || closing) {
          fence_marker(line)
        } else {
          code = style && nzchar(trimws(line))
          fence_end(line, if (code) console_code(line, st$fence_lang) else line)
        }
        st$col = 0L
        st$ws = 0L
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
        if (st$line_start) st$ws = st$ws + nchar(gsub("\t", "    ", tok))
        if (!st$line_start && st$col != st$indent) st$space = TRUE
        next
      }
      if (st$line_start) {
        st$line_start = FALSE
        pre = line_prefix(tok, text)
        if (!is.null(pre)) {
          emit(pre$text)
          st$col = st$col + pre$width
          if (!isTRUE(pre$keep)) {
            if (nzchar(text) && grepl("^[ \t]", text)) text = sub("^[ \t]+", "", text)
            next
          }
        }
      }
      w = inline(tok)
      sp = isTRUE(st$space)
      st$space = FALSE
      if (st$col > st$indent && st$col + sp + w$width > st$width) {
        emit(paste0(if (any(st$on)) sgr("0"), "\n"))
        emit(paste0(strrep(" ", st$indent), if (any(st$on)) restyle()))
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
  refresh_width = function() {
    if (auto_width) set_width(cli::console_width())
    invisible()
  }
  r = new.env(parent = emptyenv())
  r$write = function(delta) {
    refresh_width()
    ingest(delta)
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$finish = function() {
    refresh_width()
    ingest("", final = TRUE)
    end_block()
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$reset_line = function() {
    end_block()
    invisible()
  }
  r
}

#' Highlight complete code lines: R through `cli::code_highlight()` (the user's code theme),
#' R that does not parse alone and other languages through code_light()
#' @noRd
console_code = function(lines, lang) {
  if (!grepl("^\\{?[rR]([ ,}]|$)", lang)) return(code_light(lines, lang))
  tryCatch(as.character(cli::code_highlight(lines)),
           cli_parse_failure = function(e) code_light(lines, "r"), error = function(e) lines)
}

#' Strings, numbers and end-of-line comments of a known language in the colours of cli's
#' default code theme (Solarized, readable on dark and light backgrounds); others verbatim
#' @noRd
code_light = function(lines, lang) {
  com = switch(tolower(lang), r = , python = , py = , bash = , sh = , shell = , zsh = , yaml = ,
               yml = , toml = , ruby = , perl = , make = , dockerfile = "#", js = ,
               javascript = , ts = , typescript = , c = , cpp = , java = , go = , rust = ,
               swift = , kotlin = , scala = "//", sql = , lua = , haskell = "--", json = "", NULL)
  if (is.null(com)) return(lines)
  pat = paste0("\"(\\\\.|[^\"\\\\])*\"|'(\\\\.|[^'\\\\])*'|\\b[0-9]+(\\.[0-9]+)?\\b",
               if (nzchar(com)) paste0("|", com, ".*$"))
  m = gregexpr(pat, lines, perl = TRUE)
  regmatches(lines, m) = lapply(regmatches(lines, m), function(tok) {
    col = ifelse(nzchar(com) & startsWith(tok, com), "#657B83",
                 ifelse(grepl("^[\"']", tok), "#2AA198", "#D33682"))
    vapply(seq_along(tok), function(i) cli::make_ansi_style(col[[i]])(tok[[i]]), "")
  })
  lines
}

#' Print a complete text through the markdown renderer (one shot)
#' @noRd
console_print_text = function(text, before_output = NULL) {
  text = text[!is.na(text)]
  if (!any(nzchar(text))) return(invisible())
  r = render_markdown_stream(before_output = before_output)
  r$write(paste(text, collapse = "\n"))
  r$finish()
}

#' The waiting indicator (report 18 A.6 wait_indicator()), ticked by its caller
#'
#' Uses "\r" redraws inside the console margin; an ANSI terminal erases to the line end, so the
#' cursor stays after the text, other consoles pad the row with spaces. `tick()` is a no-op when
#' stdout is not a dynamic terminal, so tests, pipes and knitr never see it.
#' @noRd
console_spinner = function(label = "thinking") {
  frames = console_symbols()$frames
  utf8 = isTRUE(l10n_info()[["UTF-8"]])
  if (!utf8) frames = c("-", "\\", "|", "/")
  key = console_interrupt_key()
  action = if (console_menu_available()) "steer or stop" else "stop"
  sp = new.env(parent = emptyenv())
  sp$dynamic = cli::is_dynamic_tty()
  sp$ansi = cli::is_ansi_tty()
  sp$pad = console_pad()
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
    width = max(0L, as.integer(cli::console_width()) - 1L)
    text = sprintf("%s%s %s (%.0fs, %s to %s)", sp$pad, frames[[sp$i]], label, now - sp$t0, key,
                   action)
    if (!utf8) text = enc2native(text)
    text = if (width) cli::ansi_strtrim(text, width,
      ellipsis = if (utf8) cli::symbol$ellipsis else "...") else ""
    # Reserve the last column to avoid wrapping; padding erases the tail of a shorter frame.
    padding = strrep(" ", max(0L, width - cli::ansi_nchar(text, type = "width")))
    console_cat(paste0("\r", text, if (sp$ansi) "\033[K" else padding))
    sp$shown = TRUE
    invisible()
  }
  sp$clear = function() {
    if (sp$shown) {
      blank = strrep(" ", max(0L, cli::console_width() - 1L))
      console_cat(if (sp$ansi) "\r\033[K" else paste0("\r", blank, "\r"))
      sp$shown = FALSE
    }
    invisible()
  }
  sp
}

# ---- renderer hooks ---------------------------------------------------------------------------
# Rendering subscribes to events (INFRA-27): process-wide notify hooks render runs of foreground
# sessions at verbosity() >= 2 and report ordinary progress on stdout at verbosity 1.
# `the$console$active`
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
  rec$paused = FALSE
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

#' A foreground session: depth 0, live, not handed to P21's background pump; unless `tools`,
#' never while a tool executes on the stack, whose events (nested calls: `details$nested`) are
#' the model's, not the person's
#' @noRd
console_foreground = function(rec, tools = FALSE) {
  live = session_live(rec$session)
  !is.null(live) && is.null(live$background) &&
    identical(session_data(rec$session)$depth, 0L) && (tools || is.null(run_current()))
}

#' Show a sub-agent's start and end (D-188): a child run (depth 1+) whose outermost run is in the
#' foreground (a top-level team or fan-out has none above its children), at verbosity 1+, not
#' quiet
#' @noRd
console_child_shown = function(run) {
  top = run
  while (!is.null(top$outer)) top = top$outer
  live = if (inherits(top$shell, "gptr_session")) session_live(top$shell)
  isTRUE(run$depth >= 1L) && !is.null(live) && is.null(live$background) &&
    !isTRUE(top$opts$background) && verbosity() >= 1L && !isTRUE(getOption("gptr.quiet"))
}

#' One line about a sub-agent, on a finished line, two columns in as its prompts (D-188)
#' @noRd
console_child_line = function(rec, text) {
  console_before_message(tools = TRUE)
  console_write(paste0("  sub-agent ", rec$child$label, " ", text))
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
  draw = function() {
    if (!rec$spinner$shown) console_gap(rec, "wait")
    rec$spinner$tick()
  }
  draw()
  rec$task = reactor_task(function() {
    if (is.null(rec$spinner)) return(FALSE)
    if (console_render_on(rec)) draw()
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

#' Other output is about to appear: end the partial lines of the foreground records of `runs`
#' (every tracked run when NULL) and clear their waiting rows, keeping the pending request's
#' clock and task so waiting resumes by itself; the output opens a block of `kind` (none when
#' NULL). TRUE when a foreground record was found
#'
#' Called by the outer blocking policy without handling or changing the condition, by a launch
#' boundary (`kind = NULL`), and with `tools` by the console UI before it prompts and by the
#' sub-agent lines, which also end the lines of a run whose tool executes (a sub-agent asking
#' during the parent's `r` code; its writes never enter captured output, D-188).
#' @noRd
console_before_message = function(runs = NULL, kind = "notice", tools = FALSE) {
  recs = if (is.null(runs)) {
    as.list(console_state()$active)
  } else {
    lapply(runs, function(run) console_record(list(run = run$id)))
  }
  found = FALSE
  for (rec in recs) {
    if (is.null(rec) || !console_foreground(rec, tools)) next
    found = TRUE
    if (!is.null(rec$think)) rec$think$reset_line()
    if (!is.null(rec$md)) rec$md$reset_line()
    if (!is.null(rec$spinner)) {
      shown = isTRUE(rec$spinner$shown)
      rec$spinner$clear()
      # R GUIs keep a cleared row's overwrite range, so they continue on a fresh line
      if (shown && identical(front_end(), "rgui")) console_cat("\n")
    }
    if (!is.null(kind)) console_gap(rec, kind)
  }
  invisible(found)
}

#' One blank line between a run's blocks (text, tool, notice, prompt, waiting row, status) where
#' lines keep the margin, written on a finished line; blocks of one kind group, except prompts,
#' and a block replacing a cleared waiting row needs none
#' @noRd
console_gap = function(rec, kind) {
  same = identical(rec$last, kind) && !identical(kind, "prompt")
  if (!same && !identical(rec$last, "wait") && nzchar(console_pad())) console_cat("\n")
  rec$last = kind
  invisible(NULL)
}

#' Normal progress: ordinary stdout display. Callers keep
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
    if (!is.null(rec)) rec$paused = FALSE
    if (!is.null(rec) && isTRUE(rec$request_pending) &&
        run$status %in% c("requesting", "streaming")) console_wait_start(rec)
  }
  invisible(NULL)
}

#' A record-only callback: any rendered output (a style alone too) ends the waiting row and
#' opens a text block
#' @noRd
console_stream_output = function(rec) {
  force(rec)
  function(text) {
    console_spinner_stop(rec)
    console_gap(rec, "text")
    invisible(NULL)
  }
}

#' End the partial lines of a record and stop its waiting row (before a tool line or the menu)
#' @noRd
console_pause_one = function(rec) {
  console_spinner_stop(rec)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish()
  invisible(NULL)
}

#' End the partial lines of every tracked run (the pause menu, an abort); the next block after
#' the menu's answer line is separated like the first block after an input line
#' @noRd
console_render_pause = function() {
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) {
    rec = get(id, envir = active)
    console_pause_one(rec)
    rec$paused = TRUE
    rec$last = NULL
  }
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

#' The default start of a tool call: "  * r  x = 1" when it fits `width`; code that does not
#' follows as a Markdown fence of at most 20 lines that are never cut, `r` for the r tool (D-187)
#' @noRd
console_call_line = function(call, width) {
  lines = console_escape(console_preview(call$input), FALSE)
  head = paste0("  ", console_symbols()$tool, console_escape(call$name %||% "?", FALSE))
  one = paste0(head, "  ", c(lines, "")[[1L]])
  if (!is.character(call$input$code) ||
      (length(lines) < 2L && cli::ansi_nchar(one, type = "width") <= width)) {
    return(as.character(cli::ansi_strtrim(one, width)))
  }
  code = utils::head(lines, 20L)
  fence = doc_rmd_fence("```", code)
  more = length(lines) - length(code)
  lang = if (grepl("(^|__)r$", call$name %||% "")) "r" else ""
  body = c(cli::style_dim(paste0(fence, lang)), console_code(code, lang), cli::style_dim(fence),
           if (more > 0L) cli::style_dim(paste0("(+", more, " more lines)")))
  c(head, paste0(console_pad(), body))
}

#' The default result lines of a tool call: errors, object changes of `r`, the diff of `edit`,
#' the path of `write`, else the elapsed time when it took a second or more
#' @noRd
console_result_lines = function(call, result) {
  pad = "    "
  el = result$elapsed
  secs = if (isTRUE(el >= 1)) sprintf(" (%.1f s)", el) else ""
  d = result$details %||% list()
  if (isTRUE(result$is_error)) {
    first = c(text_lines(d$error %||% console_msg_text(result)), "failed")[[1L]]
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
    lines = ifelse(startsWith(shown, "+"), cli::col_green(lines), lines)
    more = length(d$diff) - 12L
    return(c(lines, if (more > 0L) paste0("    (+", more, " more lines)")))
  }
  if (identical(call$name, "write") && rlang::is_string(d$path)) {
    bytes = if (is.numeric(d$bytes)) paste0(" (", format(d$bytes, big.mark = ","), " bytes)")
    return(paste0(pad, "wrote ", console_escape(d$path, FALSE), bytes, secs))
  }
  if (nzchar(secs)) paste0(pad, "done", secs) else character()
}

#' The console lines of a tool call (`result = NULL`) or of its result, fitted to `width` (a
#' call's code fence excepted)
#'
#' A tool spec's `render(call, result, width)` wins (IC-69), escaped like any untrusted text;
#' `call` is `list(id, name, input)`, `result` the tool-result message plus `elapsed`.
#' @noRd
console_tool_line = function(call, result = NULL, session = NULL, width = cli::console_width()) {
  out = tryCatch({
    spec = registry_get("tool", call$name, session = session)
    if (is.function(spec$render)) spec$render(call, result, width)
  }, error = function(e) NULL)
  width = max(20L, as.integer(width) - nchar(console_pad()))
  if (!is.character(out) && is.null(result)) return(console_call_line(call, width))
  out = if (is.character(out)) console_escape(out, FALSE) else console_result_lines(call, result)
  as.character(cli::ansi_strtrim(out, width))
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

#' agent_start: track the run; a sub-agent of a foreground call says that it started with the
#' model it calls (a worker proxy's session model is `worker/worker`, D-188)
#' @noRd
console_on_agent_start = function(event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || !rlang::is_string(event$run)) return(NULL)
  rec = console_track(event$run, s)
  live = session_live(s)
  run = live$run
  if (console_child_shown(run)) {
    rec$child = list(label = console_escape(agent_label(run), FALSE), run = run)
    model = live$adapter$worker_spec$model %||% session_data(s)$model
    console_child_line(rec, paste0("started (", console_escape(model, FALSE), ")"))
  }
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
    console_gap(rec, "notice")
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
  visible = identical(kind, "text") || (identical(kind, "thinking") && verbosity() >= 3L)
  if (visible && isTRUE(rec$paused) && any(nzchar(delta))) {
    rec$paused = FALSE
    live = session_live(rec$session)
    if (isTRUE(live$run$signal$aborted)) console_write("[gptr] final received text:")
  }
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
      console_gap(rec, "text")
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
    if (is.null(rec$md)) {
      console_print_text(console_msg_text(msg), console_stream_output(rec))
    } else {
      rec$md$finish()
    }
    rec$think = NULL
    rec$md = NULL
    rec$md_index = NULL
  } else if (identical(msg$role, "tool_result")) {
    call = get0(paste0("t", msg$tool_call_id), envir = rec$tools, inherits = FALSE) %||%
      list(id = msg$tool_call_id, name = msg$tool_name, input = list())
    result = c(msg[c("content", "is_error", "details")], list(elapsed = call$elapsed))
    lines = console_tool_line(call, result, rec$session)
    if (length(lines)) {
      console_gap(rec, "tool")
      console_write(lines)
    }
  }
  NULL
}

#' tool_execution_start: the call's lines (verbosity 2) or a progress message (verbosity 1)
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
    console_gap(rec, "tool")
    console_write(console_tool_line(call, NULL, rec$session))
  }
  NULL
}

#' tool_execution_end: queue the pause-menu items and print the artifact lines held while tools
#' ran, keep the elapsed time for the result line, report a failure at verbosity 1; a CLI route's
#' informational tool event leaves its request pending, so the waiting row comes back
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
                "progress", .stream = "stderr")
  }
  if (isTRUE(rec$request_pending) && console_render_on(rec)) console_spinner_start(rec)
  NULL
}

#' retry_start: say that a request is retried
#' @noRd
console_on_retry = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  console_pause_one(rec)
  console_gap(rec, "notice")
  console_write(cli::col_grey(sprintf("  retrying in %.1f s (%s)",
                                      as.numeric(event$delay %||% 0),
                                      console_escape(event$class %||% "error", FALSE))))
  NULL
}

#' agent_end: close the streams, show custom entries and the status line, forget the run; queued
#' artifact lines (an interrupted tool) print last; a shown sub-agent says how it ended, `(k/N)`
#' counting the settled children of its scheduled group (D-188)
#' @noRd
console_on_agent_end = function(event, ctx) {
  on.exit(console_artifact_flush(), add = TRUE)
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  on.exit(console_drop(event$run), add = TRUE)
  console_spinner_stop(rec)
  run = rec$child$run
  if (!is.null(run)) {
    g = run$group
    k = if (is.environment(g)) {
      sprintf(" (%d/%d)", sum(vapply(g$runs, function(r) isTRUE(r$settled), NA)), g$n)
    }
    n = event$turns %||% 0L
    sep = console_symbols()$sep
    console_child_line(rec, if (identical(event$status, "idle")) {
      paste0("done", k, sep, n, if (n == 1L) " turn" else " turns", sep,
             sprintf("%.0f s", as.numeric(Sys.time()) - as.numeric(run$started)))
    } else {
      paste0("failed: ", console_escape(event$status %||% "?", FALSE))
    })
  }
  if (!console_foreground(rec)) return(NULL)
  line = console_status_line(event$status, event$reason, event$usage, event$turns)
  v = verbosity()
  if (v == 1L) {
    text = paste0("gptr:", sub("^ +", " ", line))
    if (identical(event$status, "idle")) {
      console_progress(text)
    } else {
      gptr_inform(text, "progress", .stream = if (event$status == "error") "stderr" else "stdout")
    }
  }
  if (v < 2L) return(NULL)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish()
  console_gap(rec, "status")
  console_render_custom(rec$session, rec$n0)
  console_write(cli::col_grey(line))
  console_gap(rec, "prompt")
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

#' Print NS-8 lines: on stdout at verbosity 2 or 3, as ordinary progress at verbosity 1
#' @noRd
console_artifact_emit = function(lines) {
  v = verbosity()
  if (v == 1L) gptr_inform(lines, "progress")
  if (v >= 2L) console_write(paste0(console_pad(), lines))
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
    gptr_hook("retry_start", console_on_retry),
    gptr_hook("agent_end", console_on_agent_end),
    gptr_hook("artifact_start", console_on_artifact_start),
    gptr_hook("session_shutdown", console_on_shutdown)
  )
}
