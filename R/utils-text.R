# Output budgets: head/tail truncation, the gptr$out() store, spill files, terminal cleanup and
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
#' store (its id starts with `id_prefix`) and in a spill file, and the kept lines surround the
#' notice `[... n lines omitted; all: gptr$out("<id>")]`.
#' @noRd
truncate_output = function(text, budget_tokens, class = "r_output", head = 0.4,
                           id_prefix = "o") {
  budget = check_number(budget_tokens, "budget_tokens", min = 1)
  class = check_choice(class, names(token_cpt), "class")
  head = check_number(head, "head", min = 0, max = 1)
  check_string(id_prefix, "id_prefix")
  lines = text_lines(text)
  total = length(lines)
  costs = est_tokens_each(paste0(lines, "\n"), class)
  if (sum(costs) <= budget) {
    return(list(
      text = paste(lines, collapse = "\n"), truncated = FALSE, omitted = 0L,
      total_lines = total, out_id = NULL, spill = NULL
    ))
  }
  out_id = out_put_prefixed(lines, "stdout", list(class = class), NULL, id_prefix)
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
  paste0("[... ", omitted, " lines omitted; all: gptr$out(\"", id, "\")]")
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

#' Store text for gptr$out(id); returns the id ("o" + 6 hex)
#'
#' `meta$stderr` (a character vector), when given with `stream = "stdout"`, is stored as the
#' entry's stderr stream.
#' @noRd
out_put = function(text, stream = "stdout", meta = list(), session = NULL) {
  out_put_prefixed(text, stream, meta, session, "o")
}

#' @noRd
out_put_prefixed = function(text, stream, meta, session, prefix) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  check_list(meta, "meta")
  store = out_store(session)
  repeat {
    id = id_new(prefix, 6L)
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

#' Write redacted text to a spill file under the workspace's cache/tmp; returns the path
#'
#' A `prefix` ending in "-" or "_" gets a fresh 6-hex id appended; any other prefix is used as
#' the file name stem as is (truncate_output() passes "gptr-output-<out id>").
#' @noRd
spill_write = function(text, prefix = "gptr-output-") {
  check_string(prefix, "prefix")
  stem = if (grepl("[-_]$", prefix)) paste0(prefix, id_new("", 6L)) else prefix
  path = ws_path("cache", "tmp", paste0(stem, ".txt"))
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
    print(shown, row.names = FALSE)
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
