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
render_markdown_stream = function(width = cli::console_width()) {
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
    if (nzchar(x)) cat(x, sep = "")
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
    cat(sprintf("\r%s %s (%.0fs, %s to steer or stop)", frames[[sp$i]], label, now - sp$t0, key),
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
