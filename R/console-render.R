# console-render.R -- the console's printing layer (P14, layer L5, area console; architecture
# 6.17, contract 7.14). The markdown stream renderer is report 18 Appendix A.6's md_stream(); every
# delta is UTF-8 marked (display widths, verification item 24), its line ends normalised and then
# escaped (IC-53 item 8); the live row is console-input.R's (D-243). Untrusted text is written
# with cat() after console_escape(), never as a cli or glue format string (rule C1).

#' The key that interrupts R in this front end (Esc in Rgui, R.app and RStudio's console; report
#' 18 section 6; Ctrl-C in Positron's console, as the visual review found)
#' @noRd
console_interrupt_key = function() {
  if (front_end() %in% c("rgui", "rstudio")) "Esc" else "Ctrl-C"
}

#' Lines of untrusted text for one-line displays: split on CRLF, CR and LF, then escaped
#' @noRd
console_lines = function(x) {
  x = console_utf8(x)
  x = x[!is.na(x)]
  if (!length(x)) return(character())
  ui_escape(strsplit(paste(x, collapse = "\n"), "\r\n|\r|\n", perl = TRUE)[[1L]])
}

#' Print untrusted text on stdout, one escaped line each, inside the console margin (D-186)
#' @noRd
console_out = function(x) {
  lines = console_lines(x)
  if (length(lines)) console_notice(paste(lines, collapse = "\n"))
  invisible(NULL)
}

#' Print lines that are already safe (built from escaped parts) on stdout
#' @noRd
console_write = function(lines) {
  if (length(lines)) console_cat(paste0(lines, "\n", collapse = ""))
  invisible(NULL)
}

#' The person's rows at column 0 (D-242): `glyph`, a space and the escaped `text`, wrapped inside
#' the console width with the later rows under the text; for a finite `n`, cut to `n` rows of
#' that width, the cut marked with an ellipsis
#' @noRd
console_person_rows = function(glyph, text, n = Inf) {
  lead = paste0(glyph, " ")
  width = max(20L, cli::console_width() - 1L - nchar(lead))
  rows = console_wrap(console_lines(text), width)
  if (is.finite(n)) {
    ell = console_style()$ellipsis
    more = length(rows) > n
    rows = console_cut(utils::head(rows, n), width, ell)
    if (more) {
      rows[[n]] = paste0(cli::ansi_strtrim(rows[[n]], width - nchar(ell), ellipsis = ""), ell)
    }
  }
  paste0(ifelse(seq_along(rows) == 1L, lead, strrep(" ", nchar(lead))), rows)
}

#' The person's rows on the input band, where it shows (console_style()$band, IC-82): each row
#' after the band, shaded to its end and reset (`\033[K\033[0m`); else as they are
#' @noRd
console_band = function(rows) {
  band = console_style()$band
  if (nzchar(band)) paste0(band, rows, "\033[K\033[0m") else rows
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
#' Returns an environment with `write(delta)` and `finish(cut = FALSE)`, writing to stdout; a cut
#' (an abort, an unusual end) writes all it received and ends a non-empty held row with a dim
#' ellipsis.
#' Styling (bold, italic within one token, inline code in the blue accent, link URLs, quotes,
#' rules and fence lines in the grey, headings, bullets, highlighted fenced code) is used when
#' `cli::num_ansi_colors() > 1` at creation. The Markdown is read in the console margin at every
#' depth, so a console without colour shows the same text (no SGR); only the plain mode without
#' colour keeps the markdown characters. Fenced code stays Markdown: fence lines as written (dim),
#' the body unwrapped and de-indented by the opener's indentation (D-187).
#' Where console_pad() gives a margin (D-186) lines get two columns on both sides, nested list
#' indentation is kept, pipe tables are aligned, blank lines collapse to one between blocks (none
#' before or after a reply); elsewhere the plain mode only wraps at `width` display columns. Prose
#' wraps at 100 columns at most, a readable measure however wide the console. Rows
#' are written whole, each at its line end or its wrap, so no half row sits where the live row
#' is drawn and other output goes between whole rows, the held row continuing after it (D-245).
#' A word is held until the next blank or line end, so the output does not
#' depend on how the text was chunked at a fixed width. When width is omitted, each write and
#' final flush sample the current console width; an explicit width stays fixed.
#' @noRd
render_markdown_stream = function(width = cli::console_width(), before_output = NULL) {
  auto_width = missing(width)
  style = cli::num_ansi_colors() > 1L
  pad = console_pad()
  lay = nzchar(pad)
  md = lay || style
  sym = console_style()
  st = new.env(parent = emptyenv())
  set_width = function(w) st$width = max(20L, min(as.integer(w) - 2L * nchar(pad), 100L))
  set_width(width)
  st$buf = ""
  st$cr = ""
  st$row = ""
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
  st$table = character()
  st$cells = list()
  st$table_raw = FALSE
  st$space = FALSE
  # inline code and link URLs: the style table's blue and grey (D-245), their SGR parameters
  param = function(f) sub("^\033\\[([0-9;]*)m.*$", "\\1", f("x"))
  codes = c(h1 = "1;4", h = "1", bold = "1", italic = "3", code = param(sym$blue),
            url = param(sym$dim))
  st$on = logical(length(codes))
  names(st$on) = names(codes)
  sgr = function(code) if (style) paste0("\033[", code, "m") else ""
  restyle = function() sgr(paste(c("0", codes[st$on]), collapse = ";"))
  toggle = function(name) {
    st$on[[name]] = !st$on[[name]]
    restyle()
  }
  # The margin opens every non-empty row; a pending blank line is written only before more text.
  # A row is held until its line end
  emit = function(x) {
    if (!nzchar(x)) return(invisible())
    if (st$bol && !startsWith(x, "\n")) {
      x = paste0(if (st$blank) "\n", pad, x)
      st$blank = FALSE
    }
    st$bol = endsWith(x, "\n")
    st$out = TRUE
    st$row = paste0(st$row, x)
    if (!st$bol) return(invisible())
    x = st$row
    st$row = ""
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
      # a held inter-word blank of the ended line would read as indentation of the next one
      st$buf = sub("^[ \t]+$", "", st$buf)
    }
    st$blank = FALSE
    st$out = FALSE
  }
  inline = function(tok) {
    if (!md) return(list(text = tok, width = vis_width(tok)))
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
        i == 1L && grepl("^\\*[^*[:space:]][^*]*\\*[[:punct:]]*$", tok)
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
      return(list(text = if (md) restyle() else paste0(tok, " "),
                  width = if (md) 0L else nchar(tok) + 1L))
    }
    if (md && grepl("^(-{3,}|\\*{3,}|_{3,})$", tok) && !grepl("^[ \t]", after)) {
      return(list(text = sym$dim(strrep("-", st$width)), width = st$width))
    }
    if (tok %in% c("-", "*", "+")) {
      st$indent = n + 2L
      mark = if (!md) "- " else paste0(if (n > 0L) sym$nested else sym$bullet, " ")
      return(list(text = paste0(lead, mark), width = st$indent))
    }
    if (grepl("^[0-9]+[.)]$", tok)) {
      st$indent = n + nchar(tok) + 1L
      return(list(text = paste0(lead, tok, " "), width = st$indent))
    }
    if (identical(tok, ">")) {
      st$indent = n + 2L
      return(list(text = paste0(lead, sym$dim("> ")), width = st$indent))
    }
    if (n > 0L) {
      st$indent = n
      return(list(text = lead, width = n, keep = TRUE))
    }
    NULL
  }
  fence_marker = function(line) {
    st$fence = !st$fence
    if (st$fence) {
      st$fence_n = attr(regexpr("^`{3,}", line), "match.length")
      st$fence_lang = trimws(substring(line, st$fence_n + 1L))
      st$fence_indent = st$ws
    }
    emit(paste0(sym$dim(line), "\n"))
  }
  # A block of pipe-table rows is held while it can be aligned: a delimiter second row, one cell
  # count and a fitting width. From the row that rules this out the block prints verbatim as
  # each row ends, so a table too wide to align streams (#43); either way it stays a valid pipe
  # table.
  table_widths = function() {
    cells = st$cells
    k = length(cells[[1L]])
    if (length(cells) < 2L || k == 0L || any(lengths(cells) != k) ||
        !all(grepl("^:?-+:?$", cells[[2L]]))) return(NULL)
    widths = do.call(pmax, c(lapply(cells[-2L], nchar, type = "width"), 3L))
    if (sum(widths) + 3L * k + 1L <= st$width) widths
  }
  table_add = function(line) {
    st$table = c(st$table, line)
    if (!st$table_raw) {
      cl = strsplit(sub("^\\|", "", sub("\\|[ \t]*$", "", line)), "|", fixed = TRUE)[[1L]]
      st$cells = c(st$cells, list(trimws(cl)))
      if (length(st$cells) < 2L || !is.null(table_widths())) return(invisible())
      st$table_raw = TRUE
      line = st$table
    }
    for (r in line) emit(paste0(r, "\n"))
  }
  table_flush = function() {
    widths = if (!st$table_raw) table_widths()
    rows = if (!st$table_raw) st$table
    cells = st$cells
    st$table = character()
    st$cells = list()
    st$table_raw = FALSE
    if (is.null(widths)) {
      for (r in rows) emit(paste0(r, "\n"))
      return(invisible())
    }
    body = cells[-2L]
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
        if (st$fence) line = sub(paste0("^ {0,", st$fence_indent, "}"), "", line)
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
          table_add(line)
        } else if (opening || closing) {
          fence_marker(line)
        } else {
          emit(paste0(console_code(line, st$fence_lang), "\n"))
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
  r$finish = function(cut = FALSE) {
    refresh_width()
    ingest("", final = TRUE)
    if (cut && !st$line_start && !st$fence) emit(sym$dim(sym$ellipsis))
    end_block()
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r
}

#' Code lines as shown: R highlighted where colours show, in the user's `cli.code_theme` or else
#' the style table's (IC-82), without the help links RStudio would add to calls; R that does not
#' parse and other languages as written
#' @noRd
console_code = function(lines, lang) {
  if (cli::num_ansi_colors() < 2L || !grepl("^\\{?[rR]([ ,}]|$)", lang)) return(lines)
  rlang::local_options(cli.hyperlink_help = FALSE)
  theme = getOption("cli.code_theme") %||% console_style()$code
  tryCatch(as.character(cli::code_highlight(lines, theme)), error = function(e) lines)
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

#' Verbosity 2's view of a thinking block of a record on a CLI route: its first line without a
#' bold title's markers, dim and cut with an ellipsis to the width within the margin (D-186,
#' D-207), printed as a block once its line end comes or it passes the width, or by finish(),
#' above the live row, which keeps its clock; Codex's reasoning items so show as progress lines
#' (D-192). Nothing is on screen before that.
#' @noRd
console_think_line = function(rec, width = cli::console_width()) {
  width = width - nchar(console_pad())
  st = new.env(parent = emptyenv())
  st$text = ""
  st$open = TRUE
  st$finish = function() {
    if (st$open && nzchar(st$text)) {
      line = sub("^\\*\\*(.+)\\*\\*$", "\\1", console_lines(st$text)[[1L]])
      console_gap(rec, "think")
      console_write(console_style()$dim(cli::ansi_strtrim(paste0("  ", line), width)))
    }
    st$open = FALSE
    invisible(NULL)
  }
  st$write = function(delta) {
    if (!st$open) return(invisible(NULL))
    st$text = sub("^[[:space:]]+", "", paste0(st$text, paste(delta, collapse = "")))
    if (!nzchar(st$text)) return(invisible(NULL))
    first = console_lines(st$text)[[1L]]
    if (grepl("[\r\n]", st$text) || cli::ansi_nchar(first) + 2L > width) st$finish()
    invisible(NULL)
  }
  st
}

# ---- renderer hooks ---------------------------------------------------------------------------
# Rendering subscribes to events (INFRA-27): process-wide notify hooks render runs of foreground
# sessions at verbosity() >= 2 and report ordinary progress on stdout at verbosity 1.
# `the$console$active`
# maps a run id to its session from agent_start to agent_end, at any verbosity, because the
# interrupt policy needs the session of a run (04 gives no accessor from a run to its session).

#' The console's process state (`the$console`, owned by P14): `active` (run id -> record);
#' `artifacts` (NS-8 lines) and `pending` (pause-menu items) held while a tool executes;
#' `last_call`, the session and call ids of the last call line printed (D-243)
#' @noRd
console_state = function() {
  if (is.null(the$console)) {
    the$console = new.env(parent = emptyenv())
    the$console$active = new.env(parent = emptyenv())
  }
  the$console
}

#' Start tracking a run of a session: a record with its session, tool calls, entry count, usage
#' row count, count of queue items dropped by aborts, start time and state word (the live row's)
#' @noRd
console_track = function(run_id, session) {
  rec = new.env(parent = emptyenv())
  rec$session = session
  rec$t0 = as.numeric(Sys.time())
  rec$what = "thinking"
  rec$tools = new.env(parent = emptyenv())
  rec$n0 = length(session_data(session)$entries)
  rec$u0 = nrow(session_data(session)$usage)
  rec$d0 = length(session_data(session)$dropped)
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

#' Forget a run after taking down its live row
#' @noRd
console_drop = function(run_id) {
  active = console_state()$active
  rec = get0(run_id, envir = active, inherits = FALSE)
  if (!is.null(rec)) {
    console_live_stop(rec)
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

#' One line about a sub-agent, on a finished line, two columns in as its prompts (D-188), after
#' the agent's blue block in the console's colours, also from the agent's r code (D-245), cut to
#' the console width (D-224) before its last words `keep`, which stay (Task 36: ` started`)
#' @noRd
console_child_line = function(rec, text, keep = "") {
  console_before_message(tools = TRUE)
  old = options(cli.num_colors = console_colors())
  on.exit(options(old), add = TRUE)
  sym = console_style()
  head = paste0("  ", sym$blue(sym$agent), " sub-agent ", rec$child$label, " ", text)
  console_write(paste0(cli::ansi_strtrim(head, cli::console_width() - nchar(keep)), keep))
}

#' Render this record on stdout now?
#' @noRd
console_render_on = function(rec) {
  verbosity() >= 2L && console_foreground(rec)
}

#' Other output is about to appear for the foreground records of `runs` (every tracked run when
#' NULL): it opens a block of `kind` (none when NULL). The writes themselves clear the live row and
#' redraw it after them (gptr_message_write()); a question (`kind = "prompt"`) or a launched
#' process (`kind = NULL`), which writes to the terminal past gptr, first clears it, and the row's
#' task draws it again once the run waits (a T console's question draws it when it has its answer,
#' console_asked()). A question in a T console first waits for typing to pause
#' (console_ask_wait()); a question of a terminal call then reads in the saved modes from before its
#' rows (tty_question()), until console_asked(). A streamed answer has nothing on screen to end:
#' its held row continues after the output (D-245). TRUE when a foreground record was found
#'
#' Called by the outer blocking policy without handling or changing the condition, by a launch
#' boundary (`kind = NULL`), and with `tools` by the console UI before it prompts and by the
#' sub-agent lines, which also find a run whose tool executes (a sub-agent asking during the
#' parent's `r` code; its writes never enter captured output, D-188).
#' @noRd
console_before_message = function(runs = NULL, kind = "notice", tools = FALSE) {
  recs = if (is.null(runs)) {
    as.list(console_state()$active)
  } else {
    lapply(runs, function(run) console_record(list(run = run$id)))
  }
  recs = Filter(function(rec) !is.null(rec) && console_foreground(rec, tools), recs)
  if (length(recs) && identical(kind, "prompt")) console_ask_wait()
  if (identical(kind, "prompt")) tty_question(TRUE)
  if (length(recs) && !identical(kind, "notice") && !is.null(the$live_row)) the$live_row$clear()
  if (!is.null(kind)) for (rec in recs) console_gap(rec, kind)
  invisible(length(recs) > 0L)
}

#' One blank line between a run's blocks (text, tool, notice, prompt, the person's lines, status)
#' where lines keep the margin, written on a finished line; blocks of one kind group, so the tool
#' rows of consecutive requests group as those of one response (D-245), except prompts, and a
#' question and the tool block it is asked in are one (it asks under the call it gates, D-243).
#' The live row below them is no block. Queue lines held while the answer's text block was open
#' (`rec$queued`, console_queue_line()) are written first, as the person's block, when any other
#' block starts
#' @noRd
console_gap = function(rec, kind) {
  if (length(rec$queued) && !identical(kind, "text")) {
    rows = unlist(lapply(rec$queued, `[[`, "rows"))
    rec$queued = NULL
    console_gap(rec, "person")
    console_write(rows)
  }
  same = identical(rec$last, kind) && !identical(kind, "prompt")
  join = paste(rec$last, kind) %in% c("tool prompt", "prompt tool")
  if (!same && !join && nzchar(console_pad())) console_cat("\n")
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

#' Waiting feedback: the live row on streamed dynamic consoles, else concise progress
#' @noRd
console_wait_start = function(rec) {
  if (verbosity() < 1L || !console_foreground(rec)) return(invisible(NULL))
  if (verbosity() >= 2L && cli::is_dynamic_tty()) {
    console_live_start(rec)
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

#' A record-only callback: a rendered row opens a text block
#' @noRd
console_stream_output = function(rec) {
  force(rec)
  function(text) {
    console_gap(rec, "text")
    invisible(NULL)
  }
}

#' End the partial lines of a record (before a tool line; `cut` when the answer is cut off)
#' @noRd
console_pause_one = function(rec, cut = FALSE) {
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish(cut)
  invisible(NULL)
}

#' End the partial lines of every tracked run, cut (an abort, the pause menu's [b]), and take the
#' live row down; the next block after it is separated like the first block after an input line
#' @noRd
console_render_pause = function() {
  console_live_stop()
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) {
    rec = get(id, envir = active)
    console_pause_one(rec, cut = TRUE)
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

#' The preview lines of a tool input: its code, its one-line command, its path, its questions,
#' else compact JSON
#' @noRd
console_preview = function(input) {
  text = if (is.character(input$code) && length(input$code)) {
    paste(input$code, collapse = "\n")
  } else if (rlang::is_string(input$command) && !grepl("\n", input$command, fixed = TRUE)) {
    input$command
  } else if (is.character(input$path) && length(input$path)) {
    input$path[[1L]]
  } else if (is.list(input$questions)) {
    n = length(input$questions)
    paste0(n, if (n == 1L) " question" else " questions")
  } else if (length(input)) {
    tryCatch(json_encode(input), error = function(e) "")
  } else {
    ""
  }
  strsplit(text, "\n", fixed = TRUE)[[1L]]
}

#' The term after a call's first line that counts its other lines (D-187): `  (+N more lines)`
#' @noRd
console_more_lines = function(lines) {
  if (length(lines) > 1L) paste0("  (+", length(lines) - 1L, " more lines)") else ""
}

#' A tool's name as the console shows it (D-245): an MCP tool `mcp__<server>__<tool>` as
#' `server/tool`; escaped
#' @noRd
console_tool_name = function(name) {
  console_escape(sub("^mcp__(.+?)__", "\\1/", name %||% "?", perl = TRUE), FALSE)
}

#' The kind of a tool call (IC-82, D-245): "read" for a tool annotated read-only (an MCP
#' server's `readOnlyHint` arrives as `read_only`), "agent" for a sub-agent call (Codex's
#' collab call; gptr's own sub-agents are `peter()` calls), else "act"
#' @noRd
console_tool_kind = function(name, spec) {
  if (isTRUE(spec$annotations$read_only)) return("read")
  if (identical(name, "codex_agent")) "agent" else "act"
}

#' The language of a tool's code: "r" for the r tool and its MCP form, else "" (plain)
#' @noRd
console_lang = function(name) if (grepl("(^|__)r$", name %||% "")) "r" else ""

#' Code rows under a tool call's name, at column 4 with its results (D-245): at most `n` lines,
#' R highlighted (console_code()), a cut block ending in a `# ... +N more lines` row (D-207); with
#' a `width`, a row wider than it is cut with an ellipsis, as a diff row is
#' @noRd
console_code_rows = function(lines, lang, n, width = NULL) {
  sym = console_style()
  shown = utils::head(lines, n)
  more = length(lines) - length(shown)
  cut = if (more > 0L) sym$dim(paste0("# ", sym$ellipsis, " +", more, " more lines"))
  rows = paste0("    ", c(console_code(shown, lang), cut))
  if (is.null(width)) return(rows)
  console_cut(rows, width, sym$ellipsis)
}

#' The default start of a tool call, a cursor strip by its kind (D-245): `  | r  x = 1` with the
#' strip (`console_style()$tool`) red, the name bold and R code highlighted, an MCP call as
#' `server/tool` with its arguments dim; the whole line dim for a read; the agent's blue block for
#' a sub-agent call. Code that does not fit `width` follows under the name, at most 20 rows, each
#' cut to `width` (console_code_rows())
#' @noRd
console_call_line = function(call, width, kind = "act") {
  lines = console_escape(console_preview(call$input), FALSE)
  sym = console_style()
  mcp = startsWith(call$name %||% "", "mcp__")
  code = is.character(call$input$code)
  lang = console_lang(call$name)
  name = console_tool_name(call$name)
  head = switch(kind, read = paste0(sym$tool, " ", name),
                agent = paste0(sym$blue(sym$agent), " ", name),
                paste0(sym$red(sym$tool), " ", cli::style_bold(name)))
  arg = c(lines, "")[[1L]]
  if (nzchar(arg) && kind == "act") {
    arg = if (mcp && !code) sym$dim(arg) else console_code(arg, lang)
  }
  if (nzchar(arg)) arg = paste0("  ", arg)
  tone = if (identical(kind, "read")) sym$dim else identity
  one = paste0("  ", tone(paste0(head, arg)))
  if (!code || (length(lines) < 2L && cli::ansi_nchar(one, type = "width") <= width)) {
    return(as.character(cli::ansi_strtrim(one, width)))
  }
  c(paste0("  ", tone(head)), console_code_rows(lines, lang, 20L, width))
}

#' Rows wrapped to `width` display columns with their spaces kept (code, a diff): a row breaks at
#' its last space that fits after its text begins past column `hang` (at most half the width), else
#' at the width, and goes on `hang` columns in, its styles carried over
#' @noRd
console_hang = function(rows, width, hang) {
  hang = min(hang, width %/% 2L)
  pad = strrep(" ", hang)
  unlist(lapply(rows, function(row) {
    out = character()
    repeat {
      plain = strsplit(cli::ansi_strip(row), "", fixed = TRUE)[[1L]]
      fit = sum(cumsum(nchar(plain, type = "width")) <= width)
      if (fit >= length(plain)) return(c(out, row))
      text = hang + match(TRUE, plain[-seq_len(hang)] != " ", nomatch = 0L)
      sp = which(plain[seq_len(fit + 1L)] == " ")
      sp = sp[sp > text]
      cut = if (length(sp)) max(sp) else fit + 1L
      out = c(out, cli::ansi_substr(row, 1L, cut - 1L))
      row = paste0(pad, cli::ansi_substr(row, cut + (length(sp) > 0L), length(plain)))
    }
  }))
}

#' Diff rows at column 4 (D-245): at most `n` of the escaped `rows`, `+` rows blue, `-` rows red,
#' others dim, with a `width` a row wider than it cut, never wrapped, so its code keeps its spaces;
#' then a dim `(+N more lines<more>)`
#' @noRd
console_diff_rows = function(rows, n, width = NULL, more = "") {
  if (!length(rows)) return(character())
  sym = console_style()
  shown = utils::head(rows, n)
  lines = paste0("    ", shown)
  if (!is.null(width)) lines = console_cut(lines, width, sym$ellipsis)
  sign = substr(shown, 1L, 1L)
  lines = ifelse(sign == "+", sym$blue(lines), ifelse(sign == "-", sym$red(lines), sym$dim(lines)))
  left = length(rows) - length(shown)
  c(lines, if (left > 0L) sym$dim(paste0("    (+", left, " more lines", more, ")")))
}

#' The default result lines of a tool call, indented 4 and dim (D-245): a call that did not run
#' (`call$refused`, its end's reason) one row, `not run<sep><why>` with `the user` as `you`, cut to
#' `width`; an error's message in red,
#' wrapped to at most 6 rows, then the object changes of `r` (also after an error); nothing else
#' for a read; the diff of `edit` without its file headers, which the call line names, at most 12
#' rows (console_diff_rows()), or where its approval showed the change (`call$asked`) one row,
#' `edited <path><sep>+a -r`; the project-relative path of `write`, else `done`; each with
#' `<sep><elapsed>` when it took a second or more
#' @noRd
console_result_lines = function(call, result, width, kind = "act") {
  sym = console_style()
  pad = "    "
  el = result$elapsed
  secs = if (isTRUE(el >= 1)) paste0(sym$sep, sprintf("%.1f s", el)) else ""
  d = result$details %||% list()
  obj = d$objects
  parts = if (identical(call$name, "r")) c(
    if (length(obj$added)) paste0("+ ", paste(obj$added, collapse = ", ")),
    if (length(obj$modified)) paste0("~ ", paste(obj$modified, collapse = ", ")),
    if (length(obj$removed)) paste0("- ", paste(obj$removed, collapse = ", ")),
    if (isTRUE(d$plots >= 1L)) paste0("[", d$plots, if (d$plots == 1L) " plot]" else " plots]")
  )
  changes = if (length(parts)) paste0(pad, console_escape(paste(parts, collapse = "  "), FALSE))
  why = call$refused
  if (rlang::is_string(why)) {
    why = console_escape(sub("^the user ", "you ", why), FALSE)
    return(sym$dim(console_cut(paste0(pad, "not run", sym$sep, why), width)))
  }
  if (isTRUE(result$is_error)) {
    err = console_escape(text_lines(d$error %||% console_msg_text(result)), FALSE)
    if (!length(err)) err = "failed"
    err[[1L]] = paste0("error: ", err[[1L]], if (!isTRUE(d$interrupted)) secs)
    rows = console_wrap(paste0(pad, err), width)
    more = if (length(rows) > 6L) paste0(pad, sym$ellipsis)
    return(c(sym$red(c(utils::head(rows, 6L), more)), if (length(changes)) sym$dim(changes)))
  }
  if (identical(kind, "read")) return(character())
  if (!is.null(changes)) return(sym$dim(paste0(changes, secs)))
  if (identical(call$name, "edit") && is.character(d$diff) && length(d$diff)) {
    diff = d$diff[!grepl("^(--- a/|[+]{3} b/)", d$diff)]
    if (!isTRUE(call$asked)) return(console_diff_rows(console_escape(diff, FALSE), 12L, width))
    n = c(sum(startsWith(diff, "+")), sum(startsWith(diff, "-")))
    counts = paste(c(if (n[[1L]]) paste0("+", n[[1L]]), if (n[[2L]]) paste0("-", n[[2L]])),
                   collapse = " ")
    path = if (rlang::is_string(d$path)) path_rel(d$path) else call$input$path %||% ""
    return(sym$dim(paste0(pad, "edited ", console_escape(path, FALSE),
                          if (nzchar(counts)) paste0(sym$sep, counts), secs)))
  }
  if (identical(call$name, "write") && rlang::is_string(d$path)) {
    bytes = if (is.numeric(d$bytes)) paste0(" (", format(d$bytes, big.mark = ","), " bytes)")
    return(sym$dim(paste0(pad, "wrote ", console_escape(path_rel(d$path), FALSE), bytes, secs)))
  }
  if (nzchar(secs)) sym$dim(paste0(pad, "done", secs)) else character()
}

#' The console lines of a tool call (`result = NULL`) or of its result, fitted to `width`: the
#' default call line is cut (its code fence never), other lines wrap and keep their indentation
#' (a word wider than `width` is cut)
#'
#' A tool spec's `render(call, result, width)` wins (IC-69), escaped like any untrusted text;
#' `call` is `list(id, name, input)`, `result` the tool-result message plus `elapsed`.
#' @noRd
console_tool_line = function(call, result = NULL, session = NULL, width = cli::console_width()) {
  spec = tryCatch(registry_get("tool", call$name, session = session), error = function(e) NULL)
  out = tryCatch(if (is.function(spec$render)) spec$render(call, result, width),
                 error = function(e) NULL)
  width = max(20L, as.integer(width) - nchar(console_pad()))
  kind = console_tool_kind(call$name, spec)
  if (!is.character(out) && is.null(result)) return(console_call_line(call, width, kind))
  out = if (is.character(out)) console_escape(out, FALSE) else
    console_result_lines(call, result, width, kind)
  console_cut(console_wrap(out, width), width)
}

#' The terms of a run's end status line (IC-77, D-245), joined by the separator, in ASCII
#' `done - fake-1 - 2 requests - 1.2k tokens - $0.0042 - 82% context left`, from the run's own
#' requests (its usage rows): the last request's model (a built-in CLI's `default` as the full id
#' the CLI gets, console_cli_default()), then `sub-agents $0.8500` when `kids` holds
#' the costs of its sub-agents' requests, then the context the last request left
#' (console_context_left()); the status and reason when it did not end idle, the reason's line
#' breaks one space (curl's errors take two lines). A term whose value is unknown (IC-74) is left
#' out, as is a cost that is not above 0 (a free or local model)
#' @noRd
console_status_line = function(status, reason = NULL, usage = NULL, kids = NULL) {
  word = if (identical(status, "idle")) "done" else console_escape(status %||% "?", FALSE)
  if (!identical(status, "idle") && rlang::is_string(reason) && nzchar(reason)) {
    reason = gsub("\\s*(\r\n|\r|\n)\\s*", " ", reason, perl = TRUE)
    word = paste0(word, ": ", console_escape(reason, FALSE))
  }
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  n = NROW(usage)
  model = if (n) usage$model[[n]]
  if (identical(model, "default")) {
    model = tryCatch(console_cli_default(paste0(usage$provider[[n]], "/default")),
                     error = function(e) NULL) %||% model
  }
  tokens = format_count(unlist(usage[intersect(cols, names(usage))]))
  cost = function(x) if (sum(x, na.rm = TRUE) > 0) format_cost(x)
  left = console_context_left(usage)
  c(word, if (rlang::is_string(model)) console_escape(model, FALSE),
    paste0(n, if (n == 1L) " request" else " requests"),
    if (tokens != "unknown") paste(tokens, "tokens"), cost(usage$cost),
    if (!is.null(cost(kids))) paste("sub-agents", cost(kids)),
    if (!is.na(left)) paste0(left, "% context left"))
}

#' The context the last of usage rows `u` left (IC-77, D-245), a whole percent: 1 minus its prompt
#' tokens (input, cache reads and writes) over compact_threshold() of its model, where compaction
#' starts; NA where that is not finite (an unknown window with compact_at off), a count is unknown,
#' and on a CLI route, whose CLI keeps its own transcript (D-202). The status line and /context;
#' `used` stands for those prompt tokens (/context after a compaction request: the next request's)
#' @noRd
console_context_left = function(u, used = NULL) {
  n = NROW(u)
  if (!n || identical(u$route[[n]], "plan-cli")) return(NA_real_)
  u = u[n, , drop = FALSE]
  m = prompt_model(paste0(u$provider, "/", u$model))
  limit = compact_threshold(as.numeric(m$context %||% NA_real_),
                            as.numeric(m$max_output %||% NA_real_), gptr_opt("r_output_tokens"))
  used = used %||% sum(unlist(u[intersect(c("input", "cache_read", "cache_write_5m",
                                            "cache_write_1h"), names(u))]))
  if (!is.finite(limit) || is.na(used)) return(NA_real_)
  round(100 * max(0, limit - used) / limit)
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
    console_child_line(rec, paste0("(", console_escape(model, FALSE), ")"), " started")
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
    console_write(console_style()$dim(sprintf(
      "  request %s -> %s (~%.0f tokens)", console_escape(event$request_id %||% "", FALSE),
      console_escape(event$model %||% "", FALSE), as.numeric(event$tokens_est %||% 0))))
  }
  console_wait_start(rec)
  NULL
}

#' message_update: stream text deltas through the markdown renderer (after an abort, the text held
#' when it came under a dim `received before the abort:`); thinking at verbosity 3; on a
#' CLI route, whose one request runs a whole agent turn, the first line of each thinking block at
#' verbosity 2, with the live row below it
#' @noRd
console_on_message_update = function(event, ctx) {
  rec = console_record(event)
  delta = event$delta
  if (is.null(rec) || !is.character(delta) || !console_render_on(rec)) return(NULL)
  kind = event$kind %||% "text"
  think = identical(kind, "thinking") &&
    (verbosity() >= 3L || identical(session_live(rec$session)$run$model[["type"]], "cli"))
  visible = identical(kind, "text") || think
  if (visible && isTRUE(rec$paused) && any(nzchar(delta))) {
    rec$paused = FALSE
    live = session_live(rec$session)
    if (isTRUE(live$run$signal$aborted)) {
      # what arrived before the abort continues under a dim label, one block with it
      console_gap(rec, "text")
      console_notice(console_style()$dim("received before the abort:"))
    }
  }
  if (identical(kind, "text")) {
    if (!is.null(rec$think)) rec$think$finish()
    rec$think = NULL
    if (!is.null(rec$md) && !identical(rec$md_index, event$index)) {
      rec$md$finish()
      rec$md = NULL
      # a new text block right after one opens its own block, a blank line between (#41)
      if (identical(rec$last, "text")) rec$last = NULL
    }
    if (is.null(rec$md)) {
      rec$md = render_markdown_stream(before_output = console_stream_output(rec))
    }
    rec$md_index = event$index
    rec$md$write(delta)
  } else if (identical(kind, "thinking") && verbosity() >= 3L) {
    if (is.null(rec$think)) {
      if (!is.null(rec$md)) rec$md$finish()
      console_gap(rec, "text")
      console_write(console_style()$dim("  (thinking)"))
      rec$think = render_markdown_stream(before_output = console_stream_output(rec))
    }
    rec$think$write(delta)
  } else if (think) {
    if (is.null(rec$think) || !identical(rec$think_index, event$index)) {
      if (!is.null(rec$think)) rec$think$finish()
      if (!is.null(rec$md)) rec$md$finish()
      rec$think = console_think_line(rec)
      rec$think_index = event$index
    }
    rec$think$write(delta)
    if (!rec$think$open && isTRUE(rec$request_pending)) console_live_start(rec)
  }
  NULL
}

#' The result lines of a call, in its tool block (a tool-result message, a served call's end)
#' @noRd
console_result_block = function(rec, call, result) {
  lines = console_tool_line(call, result, rec$session)
  if (length(lines)) {
    console_gap(rec, "tool")
    console_write(lines)
  }
  invisible(NULL)
}

#' message_end: close the streamed answer, cut (finish(cut = TRUE)) when it was aborted, failed or
#' truncated, or print it whole when nothing was streamed; for a tool result, its result lines
#' @noRd
console_on_message_end = function(event, ctx) {
  rec = console_record(event)
  msg = event$message
  if (is.null(rec) || !is.list(msg)) return(NULL)
  if (identical(msg$role, "assistant")) rec$request_pending = FALSE
  if (!console_render_on(rec)) return(NULL)
  if (identical(msg$role, "assistant")) {
    if (!is.null(rec$think)) rec$think$finish()
    if (is.null(rec$md)) {
      console_print_text(console_msg_text(msg), console_stream_output(rec))
    } else {
      rec$md$finish(cut = isTRUE(msg$stop_reason %in% c("aborted", "error", "length")))
    }
    rec$think = NULL
    rec$md = NULL
    rec$md_index = NULL
  } else if (identical(msg$role, "tool_result")) {
    call = get0(paste0("t", msg$tool_call_id), envir = rec$tools, inherits = FALSE) %||%
      list(id = msg$tool_call_id, name = msg$tool_name, input = list())
    console_result_block(rec, call, c(msg[c("content", "is_error", "details")],
                                      list(elapsed = call$elapsed)))
  }
  NULL
}

#' tool_execution_start: the call's lines (verbosity 2), whose ids its approval reads (D-243), with
#' the tool's name as the live row's state word, or a progress message of its first line and
#' `(+N more lines)` (verbosity 1); an r call, which evaluates in this process, freezes its
#' record with its id, and a shown sub-agent's draws the row once
#' @noRd
console_on_tool_start = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  # the r tool evaluates in this process: the live row cannot tick or read keys until it returns
  if (identical(event$tool_name, "r") && is.null(rec$frozen)) rec$frozen = event$tool_call_id
  if (!console_foreground(rec)) {
    if (!is.null(rec$frozen) && !is.null(rec$child) && isTRUE(the$live_row$on)) the$live_row$draw()
    return(NULL)
  }
  call = list(id = event$tool_call_id, name = event$tool_name, input = event$input %||% list())
  v = verbosity()
  if (v == 1L) {
    lines = console_preview(call$input)
    lines = lines[nzchar(trimws(lines))]
    console_progress(paste0("gptr: ", console_escape(call$name %||% "?", FALSE), "  ",
                            console_escape(c(lines, "")[[1L]], FALSE), console_more_lines(lines)))
  } else if (v >= 2L) {
    assign(paste0("t", call$id), call, envir = rec$tools)
    rec$what = console_tool_name(call$name)
    console_pause_one(rec)
    console_gap(rec, "tool")
    lines = console_tool_line(call, NULL, rec$session)
    console_write(lines)
    if (length(lines)) {
      assign("last_call", c(session_data(rec$session)$id, call$id), console_state())
    }
  }
  NULL
}

#' tool_execution_end: queue the pause-menu items and print the artifact lines held while tools
#' ran, unfreeze the record at the end of the r call that froze it (not a nested call's), keep the
#' elapsed time and why a refused call did not run for the result line, report a failure at
#' verbosity 1, a refused call as not run; the end of a call served in a live run carries its
#' `content` and prints its result line (D-192); a CLI route's informational tool event leaves its
#' request pending, so the live row says thinking
#' @noRd
console_on_tool_end = function(event, ctx) {
  policy_flush()
  console_artifact_flush()
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  if (identical(rec$frozen, event$tool_call_id)) rec$frozen = NULL
  key = paste0("t", event$tool_call_id)
  call = get0(key, envir = rec$tools, inherits = FALSE)
  if (!is.null(call)) {
    call$elapsed = event$elapsed
    call$refused = event$refused
    assign(key, call, envir = rec$tools)
  }
  if (!is.null(event$content) && console_render_on(rec)) {
    console_result_block(rec, call %||% list(name = event$tool_name, input = list(),
                                             refused = event$refused),
                         event[c("content", "is_error", "details", "elapsed")])
  }
  if (verbosity() == 1L && isTRUE(event$is_error) && console_foreground(rec)) {
    why = event$refused
    end = if (rlang::is_string(why)) {
      paste0(" not run", if (nzchar(why)) paste0(": ", console_escape(why, FALSE)))
    } else {
      " failed"
    }
    gptr_inform(paste0("gptr: ", console_escape(event$tool_name %||% "?", FALSE), end),
                "progress", .stream = "stderr")
  }
  if (isTRUE(rec$request_pending) && console_render_on(rec)) console_live_start(rec)
  NULL
}

#' retry_start: say that a request is retried, and the class of its error where it has one
#' @noRd
console_on_retry = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  console_pause_one(rec)
  console_gap(rec, "notice")
  # err_class() gives NA for an error of no known class, a retry its text chose
  cls = event$class
  why = if (rlang::is_string(cls) && !is.na(cls)) paste0(" (", console_escape(cls, FALSE), ")")
  console_write(console_style()$dim(sprintf("  retrying in %.1f s%s",
                                            as.numeric(event$delay %||% 0), why %||% "")))
  NULL
}

#' session_compact: a compaction during a foreground run (an automatic one; `/compact` reports
#' itself) prints one dim line with the token counts of its entry (D-202)
#' @noRd
console_on_compact = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  e = Find(function(e) identical(e$type, "compaction"), session_data(rec$session)$entries,
           right = TRUE)
  console_pause_one(rec)
  console_gap(rec, "notice")
  console_write(console_style()$dim(paste0(
    "  conversation compacted: ", format_count(e$tokens_before %||% NA_real_), " -> ",
    format_count(e$details$tokens_after %||% NA_real_), " tokens")))
  NULL
}

#' agent_end: take the live row down, close the streams, show custom entries and the status line,
#' forget the run; queued artifact lines (an interrupted tool) print last, then what the person
#' queued and the run did not take (console_queue_left()), then the blank row before the prompt; a
#' shown sub-agent, forgotten first so the live row no longer names it, says how it ended, `(k/N)`
#' counting the settled children of its scheduled group (D-188), a failure with the first line of
#' its reason, else its status (D-224)
#' @noRd
console_on_agent_end = function(event, ctx) {
  on.exit(console_artifact_flush(), add = TRUE)
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  on.exit(console_drop(event$run), add = TRUE)
  on.exit(console_queue_left(rec, event$status), add = TRUE)
  console_live_stop(rec)
  run = rec$child$run
  if (!is.null(run)) {
    rm(list = event$run, envir = console_state()$active)
    g = run$group
    k = if (is.environment(g)) {
      sprintf(" (%d/%d)", sum(vapply(g$runs, function(r) isTRUE(r$settled), NA)), g$n)
    }
    n = event$turns %||% 0L
    sep = console_style()$sep
    console_child_line(rec, if (identical(event$status, "idle")) {
      paste0("done", k, sep, n, if (n == 1L) " turn" else " turns", sep,
             sprintf("%.0f s", as.numeric(Sys.time()) - as.numeric(run$started)))
    } else {
      why = c(text_lines(event$reason), event$status, "?")[[1L]]
      paste0("failed", k, ": ", console_escape(why, FALSE))
    })
  }
  if (!console_foreground(rec)) return(NULL)
  # the rows charged to the session during the run by other sessions: its sub-agents' (IC-66)
  d = session_data(rec$session)
  u = d$usage
  kids = u$cost[seq_len(nrow(u)) > rec$u0 & !(u$session %in% d$id) & !duplicated(u$request_id)]
  terms = console_status_line(event$status, event$reason, event$usage, kids)
  sym = console_style()
  v = verbosity()
  if (v == 1L) {
    text = paste0("gptr: ", paste(terms, collapse = sym$sep))
    if (identical(event$status, "idle")) {
      console_progress(text)
    } else {
      gptr_inform(text, "progress", .stream = if (event$status == "error") "stderr" else "stdout")
    }
  }
  if (v < 2L) return(NULL)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish(cut = !identical(event$status, "idle"))
  console_gap(rec, "status")
  console_render_custom(rec$session, rec$n0)
  # in rows ending at whole terms (console_terms()), at the content width; the status and its
  # reason wrap between words, so the reason shows whole, once (repl_turn())
  width = max(20L, cli::console_width() - 2L * nchar(console_pad()))
  why = console_wrap(terms[[1L]], width)
  rows = c(utils::head(why, -1L), console_terms(c(utils::tail(why, 1L), terms[-1L]), width))
  console_notice(paste(sym$dim(rows), collapse = "\n"))
  st = console_state()
  st$ended = session_data(rec$session)$id
  on.exit(console_gap(rec, "prompt"), add = TRUE)
  NULL
}

#' What the person queued for a foreground run that ended and the run did not take, in an
#' interactive R (D-242); elsewhere (Rscript, knitr: no history, no next prompt) it stays queued.
#' After a run that ended idle or at max_turns, its steers still queued and those held while a
#' tool ran are the next prompts of the REPL whose prompt runs, after its held lines; elsewhere
#' they stay queued for the session's next run. After any other end nothing is sent: the person's
#' items its abort dropped, the steers still queued, the items held and the REPL's held lines go
#' to the console history, listed once (console_keep()). The composer's draft (a T console, D-243)
#' stays after a run that ended idle or at max_turns, for the REPL's next prompt (console_idle());
#' after any other end it joins them
#' @noRd
console_queue_left = function(rec, status) {
  if (!gptr_is_interactive()) return(invisible(NULL))
  s = rec$session
  rs = console_repl_prompt()
  rd = rs$reader
  ended = status %in% c("idle", "max_turns")
  if (!console_foreground(rec, tools = TRUE) || (ended && is.null(rs))) return(invisible(NULL))
  st = console_state()
  mine = vapply(st$pending, function(it) identical(it$s, s), NA)
  left = c(console_unqueue(s), vapply(st$pending[mine], function(it) it$text, ""))
  st$pending = st$pending[!mine]
  if (ended) {
    rd$typed = c(rd$typed, left)
    return(invisible(NULL))
  }
  d = session_data(s)
  dropped = Filter(function(it) it$source %in% queue_user_sources,
                   d$dropped[seq_along(d$dropped) > rec$d0])
  draft = rd$compose$draft
  texts = c(vapply(dropped, function(it) it$text, ""), left, rd$typed, draft[nzchar(draft)])
  if (!is.null(rd)) {
    rd$typed = character()
    rd$compose = NULL
  }
  console_keep(texts)
}

#' Take the person's steers off the queue of `s` (session_unqueue()): their texts, oldest first
#' @noRd
console_unqueue = function(s) {
  texts = character()
  repeat {
    it = session_unqueue(s, "steer")
    if (is.null(it)) return(texts)
    texts = c(it$text, texts)
  }
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

#' queue_update: a user's message the loop takes (a steer at its step boundary) is the person's line
#' at column 0, the person's glyph and the text (ASCII `>> <text>`), on the band, before the next
#' request's output (D-242). The steers' queue lines still held (console_queue_line()) are dropped:
#' the loop takes every queued steer at once, and the deliveries say what they said
#' @noRd
console_on_queue_update = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !identical(event$op, "take") || !(event$source %in% queue_user_sources) ||
      !console_render_on(rec)) return(NULL)
  rows = console_person_rows(console_style()$person, event$text)
  console_pause_one(rec)
  if (identical(event$which, "steer")) rec$queued = Filter(function(x) !x$drop, rec$queued)
  console_gap(rec, "person")
  console_write(console_band(rows))
  NULL
}

#' turn_end, emitted just before the loop polls steers: a terminal REPL reads what was typed (also
#' during an in-process tool), so a line sent before this step boundary reaches it (D-242)
#' @noRd
console_on_turn_end = function(event, ctx) {
  console_typed()
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
    gptr_hook("turn_end", console_on_turn_end),
    gptr_hook("queue_update", console_on_queue_update),
    gptr_hook("retry_start", console_on_retry),
    gptr_hook("session_compact", console_on_compact),
    gptr_hook("agent_end", console_on_agent_end),
    gptr_hook("artifact_start", console_on_artifact_start),
    gptr_hook("session_shutdown", console_on_shutdown)
  )
}
