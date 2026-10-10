# Output budgets: head/tail truncation, the peter$out() store, spill files, terminal cleanup and
# listing data frames (contract sections 5.12, 7.1; IC-71; report G5 and its fact-check 13-15).

#' Split text (a character vector of lines or one string) into UTF-8 lines
#' @noRd
text_lines = function(text) {
  x = as_utf8(as.character(text))
  x[is.na(x)] = "NA"
  if (!length(x)) return(character())
  strsplit(paste(x, collapse = "\n"), "\n", fixed = TRUE)[[1L]]
}

#' Keep the first `head` and last `1 - head` share of lines within a token budget
#'
#' When the text fits, it is returned unchanged. Otherwise the full text is stored in the out
#' store and in a spill file, and the kept lines surround the notice
#' `[... n lines omitted; all: peter$out("<id>")]`.
#' @noRd
truncate_output = function(text, budget_tokens, class = "r_output", head = 0.4) {
  budget = check_number(budget_tokens, "budget_tokens", min = 1)
  class = check_choice(class, names(token_cpt), "class")
  head = check_number(head, "head", min = 0, max = 1)
  lines = text_lines(text)
  total = length(lines)
  costs = est_tokens_each(paste0(lines, "\n"), class)
  if (sum(costs) <= budget) {
    return(list(
      text = paste(lines, collapse = "\n"), truncated = FALSE, omitted = 0L,
      total_lines = total, out_id = NULL, spill = NULL
    ))
  }
  out_id = out_put(lines, "stdout", list(class = class))
  spill = spill_write(lines, prefix = paste0("gptr-output-", out_id))
  notice_cost = est_tokens_each(paste0(truncation_notice(total, out_id), "\n"), class)
  available = budget - notice_cost
  head_cum = c(0, cumsum(costs))
  tail_cum = c(0, cumsum(rev(costs)))
  cost_of = function(k) {
    h = round(k * head)
    head_cum[h + 1L] + tail_cum[k - h + 1L]
  }
  lo = 0L
  hi = total - 1L
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (cost_of(mid) <= available) lo = mid else hi = mid - 1L
  }
  keep = lo
  n_head = as.integer(round(keep * head))
  n_tail = keep - n_head
  omitted = total - keep
  kept_tail = if (n_tail > 0L) lines[(total - n_tail + 1L):total] else character()
  list(
    text = paste(
      c(lines[seq_len(n_head)], truncation_notice(omitted, out_id), kept_tail),
      collapse = "\n"
    ),
    truncated = TRUE, omitted = as.integer(omitted), total_lines = total,
    out_id = out_id, spill = spill
  )
}

#' The truncation notice (about 26 tokens; G5 fact-check 13)
#' @noRd
truncation_notice = function(omitted, id) {
  paste0("[... ", omitted, " lines omitted; all: peter$out(\"", id, "\")]")
}

#' A new, empty out store keeping the last `keep` entries
#' @noRd
out_store_new = function(keep = gptr_opt("out_keep")) {
  store = new.env(parent = emptyenv())
  store$keep = check_number(keep, "keep", min = 1, int = TRUE)
  store$ids = character()
  store$items = new.env(parent = emptyenv())
  class(store) = "gptr_out_store"
  store
}

#' Resolve an out store (IC-71)
#'
#' `session` is `NULL` (the process store), a `gptr_out_store`, or a session's live record: an
#' environment with an `out` binding (the store, or `NULL` until the first use, when it is
#' created). Callers that hold a `gptr_session` pass its live record (`session_live()`, P06).
#' @noRd
out_store = function(session = NULL) {
  if (is.null(session)) {
    if (is.null(the$out)) the$out = out_store_new()
    return(the$out)
  }
  if (inherits(session, "gptr_out_store")) return(session)
  if (is.environment(session) && exists("out", envir = session, inherits = FALSE)) {
    store = get("out", envir = session, inherits = FALSE)
    if (is.null(store)) {
      store = out_store_new()
      assign("out", store, envir = session)
    }
    if (inherits(store, "gptr_out_store")) return(store)
  }
  arg_abort(session, "session", "NULL, an out store or a session's live record")
}

#' Store text for peter$out(id); returns the id ("o" + 6 hex)
#'
#' `meta$stderr` (a character vector), when given with `stream = "stdout"`, is stored as the
#' entry's stderr stream.
#' @noRd
out_put = function(text, stream = "stdout", meta = list(), session = NULL) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  check_list(meta, "meta")
  store = out_store(session)
  repeat {
    id = id_new("o", 6L)
    if (!exists(id, envir = store$items, inherits = FALSE)) break
  }
  streams = list()
  streams[[stream]] = text_lines(text)
  if (identical(stream, "stdout") && is.character(meta$stderr)) {
    streams$stderr = text_lines(meta$stderr)
    meta$stderr = NULL
  }
  entry = list(id = id, streams = streams, meta = meta, time = as.numeric(Sys.time()))
  assign(id, entry, envir = store$items)
  store$ids = c(store$ids, id)
  extra = length(store$ids) - store$keep
  if (extra > 0L) {
    rm(list = store$ids[seq_len(extra)], envir = store$items)
    store$ids = store$ids[-seq_len(extra)]
  }
  id
}

#' Lines of a stored output: the session store, then the process store, then the spill file
#' @noRd
out_get = function(id, stream = c("stdout", "stderr"), lines = NULL, session = NULL) {
  check_string(id, "id")
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  if (!grepl("^[A-Za-z0-9_-]+$", id)) arg_abort(id, "id", "an output id such as \"o1a2b3c\"")
  stores = list(out_store(NULL))
  if (!is.null(session)) stores = c(list(out_store(session)), stores)
  entry = NULL
  for (store in stores) {
    entry = get0(id, envir = store$items, inherits = FALSE)
    if (!is.null(entry)) break
  }
  if (!is.null(entry)) {
    x = entry$streams[[stream]] %||% character()
  } else {
    path = file.path(
      workspace_root(create = FALSE), "cache", "tmp", paste0("gptr-output-", id, ".txt")
    )
    if (!file.exists(path)) {
      gptr_abort(
        paste0("There is no stored output with id '", id, "'."),
        "invalid_argument",
        arg = "id",
        expected = "an id shown in a truncation notice"
      )
    }
    stdout = identical(stream, "stdout")
    x = if (stdout) text_lines(sub("\n$", "", read_utf8(path)$text)) else character()
  }
  if (!is.null(lines)) x = x[lines[lines >= 1 & lines <= length(x)]]
  x
}

#' Write redacted text to `<prefix>.txt` under the workspace's cache/tmp; returns the path
#' @noRd
spill_write = function(text, prefix) {
  check_string(prefix, "prefix")
  path = ws_path("cache", "tmp", paste0(prefix, ".txt"))
  write_atomic(path, redact_hook(paste(text_lines(text), collapse = "\n"), profile = "persist"))
  path
}

#' Clean terminal output: drop ANSI/OSC sequences, keep the last frame of \r progress lines,
#' cap lines at 400 characters. Returns lines.
#' @noRd
clean_terminal = function(x) {
  x = as_utf8(as.character(x))
  if (!length(x)) return(character())
  text = paste(x, collapse = "\n")
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  text = gsub("\033\\[[0-?]*[ -/]*[@-~]", "", text, perl = TRUE)
  text = gsub("\033\\][^\a\033]*(\a|\033\\\\)", "", text, perl = TRUE)
  text = gsub("\r+(\n|$)", "\\1", text, perl = TRUE)
  text = gsub("[^\n\r]*\r", "", text, perl = TRUE)
  cap_lines(strsplit(text, "\n", fixed = TRUE)[[1L]], 400L)
}

#' Cut lines longer than `max_chars`, noting how many characters were dropped
#' @noRd
cap_lines = function(lines, max_chars = 400L) {
  width = nchar(lines, type = "chars", allowNA = TRUE)
  long = !is.na(width) & width > max_chars
  if (any(long)) {
    extra = width[long] - max_chars
    lines[long] = paste0(substr(lines[long], 1L, max_chars), " ...[+", extra, " chars]")
  }
  lines
}

#' Build a listing data frame: class c("gptr_<name>", "gptr_listing", "data.frame")
#' @noRd
new_listing = function(df, class, footer = NULL) {
  if (!is.data.frame(df)) arg_abort(df, "df", "a data frame")
  check_string(class, "class")
  check_strings(footer, "footer", null = TRUE)
  if (!startsWith(class, "gptr_")) class = paste0("gptr_", class)
  attr(df, "footer") = footer
  class(df) = c(class, "gptr_listing", "data.frame")
  df
}

#' Print a listing: at most 20 rows, a count line, then the footer
#'
#' @param x A listing data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_listing = function(x, ...) {
  n = nrow(x)
  if (n > 0L) {
    shown = x[seq_len(min(n, 20L)), , drop = FALSE]
    attr(shown, "footer") = NULL
    class(shown) = "data.frame"
    cat(listing_print_lines(shown), sep = "\n")
    cat("\n")
  }
  count = if (n > 20L) {
    paste0("# 20 of ", n, " rows shown")
  } else {
    paste0("# ", n, if (n == 1L) " row" else " rows")
  }
  cat(count, "\n", sep = "")
  footer = attr(x, "footer", exact = TRUE)
  if (length(footer)) cat(footer, sep = "\n")
  invisible(x)
}

#' A width-bounded display copy: provenance/state first, at most two column groups, no row loss
#' @noRd
listing_print_lines = function(x, width = cli::console_width()) {
  if (!ncol(x)) return(character())
  width = max(10L, as.integer(width))
  row_width = nchar(as.character(nrow(x))) + 1L
  budget = width - row_width
  priority = c("name", "ref", "id", "rule", "source", "visible", "trusted", "status")
  first = which(names(x) %in% priority)
  first = first[order(match(names(x)[first], priority))]
  idx = c(first, setdiff(seq_along(x), first))
  x = x[idx]
  headers = listing_cell(names(x), min(24L, budget))
  values = lapply(x, function(col) {
    text = if (is.character(col) || is.factor(col)) as.character(col) else format(col, trim = TRUE)
    listing_cell(text, Inf)
  })
  caps = ifelse(names(x) == "description", 40L, ifelse(names(x) == "path", 28L, 24L))
  identifiers = names(x) %in% c("id", "ref", "name", "rule")
  caps[identifiers] = budget
  wanted = vapply(seq_along(x), function(j) {
    min(budget, caps[[j]], max(nchar(c(headers[[j]], values[[j]]), type = "width")))
  }, 0)
  minimum = pmax(nchar(headers, type = "width"), pmin(wanted, 8L))
  state = identifiers | names(x) %in% c("source", "visible", "trusted", "status")
  minimum[state] = wanted[state]
  groups = list()
  group = integer()
  used = 0
  for (j in seq_along(x)) {
    gap = if (length(group)) 2L else 0L
    if (length(group) && used + gap + minimum[[j]] > budget) {
      groups[[length(groups) + 1L]] = group
      group = integer()
      used = gap = 0L
    }
    group = c(group, j)
    used = used + gap + minimum[[j]]
  }
  groups[[length(groups) + 1L]] = group
  omitted = unlist(groups[-seq_len(min(2L, length(groups)))], use.names = FALSE)
  groups = utils::head(groups, 2L)
  pad = function(text, size) paste0(text, strrep(" ", size - nchar(text, type = "width")))
  out = character()
  for (k in seq_along(groups)) {
    g = groups[[k]]
    sizes = wanted[g]
    while (sum(sizes) + 2L * (length(g) - 1L) > budget) {
      choices = which(sizes > minimum[g])
      j = choices[[which.max(sizes[choices])]]
      sizes[[j]] = sizes[[j]] - 1L
    }
    cells = lapply(seq_along(g), function(j) {
      pad(listing_cell(values[[g[[j]]]], sizes[[j]]), sizes[[j]])
    })
    if (length(groups) > 1L) out = c(out, paste0("# Columns ", k, "/", length(groups)))
    title = vapply(seq_along(g), function(j) {
      pad(listing_cell(headers[[g[[j]]]], sizes[[j]]), sizes[[j]])
    }, "")
    out = c(out, paste0(strrep(" ", row_width), paste(title, collapse = "  ")),
            vapply(seq_len(nrow(x)), function(i) {
              prefix = paste0(strrep(" ", row_width - nchar(as.character(i)) - 1L), i, " ")
              paste0(prefix, paste(vapply(cells, `[[`, "", i), collapse = "  "))
            }, ""))
  }
  if (length(omitted)) {
    out = c(out, strwrap(paste("# Other columns:", paste(headers[omitted], collapse = ", ")),
                         width = width))
  }
  sub(" +$", "", out)
}

#' Collapse cell whitespace and mark display-width truncation without splitting UTF-8 bytes
#' @noRd
listing_cell = function(text, width) {
  text = as_utf8(as.character(text))
  text[is.na(text)] = "NA"
  text = trimws(gsub("[[:space:][:cntrl:]]+", " ", text))
  long = nchar(text, type = "width") > width
  if (any(long)) text[long] = paste0(strtrim(text[long], max(0L, width - 3L)), "...")
  text
}

#' Safe notebook Markdown: keep fenced code and matched backtick spans literal, while prose
#' HTML and link/image markup remain text. This is a display copy, never the canonical message.
#' @noRd
doc_jupyter_markdown = function(text) {
  text = redact(as_utf8(text), "persist")
  text = gsub("\r\n|\r", "\n", text, perl = TRUE)
  lines = strsplit(paste0(text, "\n"), "\n", fixed = TRUE)[[1L]]
  fence = ""
  width = 0L
  for (i in seq_along(lines)) {
    line = lines[[i]]
    if (nzchar(fence)) {
      if (grepl(paste0("^ {0,3}", fence, "{", width, ",}[ \t]*$"), line)) fence = ""
      next
    }
    marker = regmatches(line, regexpr("^ {0,3}(`{3,}|~{3,})", line))
    if (length(marker)) {
      run = trimws(marker)
      info = substring(line, nchar(marker) + 1L)
      if (!startsWith(run, "`") || !grepl("`", info, fixed = TRUE)) {
        fence = substr(run, 1L, 1L)
        width = nchar(run)
        next
      }
    }
    lines[[i]] = doc_jupyter_prose(line)
  }
  paste(lines, collapse = "\n")
}

#' Escape prose between inline code spans; an escaped or unmatched opener protects nothing
#' @noRd
doc_jupyter_prose = function(text) {
  escape = function(x) {
    x = gsub("&", "&amp;", x, fixed = TRUE)
    x = gsub("<", "&lt;", x, fixed = TRUE)
    x = gsub(">", "&gt;", x, fixed = TRUE)
    gsub("[", "&#91;", x, fixed = TRUE)
  }
  ticks = gregexpr("`+", text)[[1L]]
  if (ticks[[1L]] < 0L) return(escape(text))
  widths = attr(ticks, "match.length")
  next_tick = integer(length(ticks))
  last = integer(max(widths))
  for (j in rev(seq_along(ticks))) {
    next_tick[[j]] = last[[widths[[j]]]]
    last[[widths[[j]]]] = j
  }
  escaped = rep(FALSE, length(ticks))
  slashes = gregexpr("\\\\+`", text)[[1L]]
  if (slashes[[1L]] > 0L) {
    slash_widths = attr(slashes, "match.length")
    at = match(slashes + slash_widths - 1L, ticks)
    escaped[at] = (slash_widths - 1L) %% 2L == 1L
  }
  out = character(length(ticks) + 1L)
  count = 0L
  start = 1L
  i = 1L
  while (i <= length(ticks)) {
    j = next_tick[[i]]
    if (!escaped[[i]] && j > 0L) {
      end = ticks[[j]] + widths[[j]] - 1L
      out[[count + 1L]] = escape(substr(text, start, ticks[[i]] - 1L))
      out[[count + 2L]] = substr(text, ticks[[i]], end)
      count = count + 2L
      start = end + 1L
      i = j + 1L
    } else {
      i = i + 1L
    }
  }
  out[[count + 1L]] = escape(substring(text, start))
  paste0(out[seq_len(count + 1L)], collapse = "")
}
