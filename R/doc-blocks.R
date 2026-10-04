# doc-blocks.R -- history-document blocks (plan P15; contract 7.15, 11.5; IC-45..IC-49): the block
# grammar, prompt and args hashes, the gptr() call scanner, block ownership, stale and user-edited
# detection, the recorded block content and the writer doc_upsert(). Layer L4: it calls L0
# helpers, the record constructors, the kernel SDK (session_data(), session_append()) and its
# own area only. Adapted from report 14 section 5.0 (proto/gptrdoc.R: doc_find_blocks,
# doc_scan_calls, doc_blocks_after, doc_owned_block, doc_render_block, prompt_hash, parse_kv,
# format_kv) with the verification-log fixes (radix ordering; sys.source frames) and G3 (11).

doc_re_open = "^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$"
doc_re_close = "^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$"
doc_re_kv = "([A-Za-z_][A-Za-z0-9_.]*)=(\"([^\"\\\\]|\\\\.)*\"|[^ \t]+)"
doc_re_steer = "^[ \t]*## (Steer|Follow-up): "
doc_block_token = "@@GPTR_BLOCK@@"
doc_header_keys = c("model", "date", "prompt", "sha", "call", "tokens", "cost", "session", "turn",
                    "value", "fork", "plan", "status", "args", "kind", "children")
doc_quoted_keys = "children"

#' Collapse text to one comment-safe line
#' @noRd
doc_one_line = function(x) {
  x = as_utf8(paste(as.character(x), collapse = " "))
  trimws(gsub("[\r\n\t]+", " ", x))
}

#' An R string literal that keeps non-ASCII characters (encodeString() escapes them in a C locale)
#' @noRd
doc_str_literal = function(x) {
  x = as_utf8(as.character(x))
  x = gsub("\\", "\\\\", x, fixed = TRUE)
  x = gsub("\"", "\\\"", x, fixed = TRUE)
  x = gsub("\n", "\\n", x, fixed = TRUE)
  x = gsub("\r", "\\r", x, fixed = TRUE)
  x = gsub("\t", "\\t", x, fixed = TRUE)
  paste0("\"", x, "\"")
}

#' Undo doc_str_literal(): drop the outer quotes and decode the escapes it writes (backslash,
#' quote, n, r, t); any other escaped character stands for itself. Text that is not one whole
#' literal is returned as written. The R parser is not used: in a C locale it rewrites each
#' non-ASCII character of a literal as "<U+00E1>".
#' @noRd
doc_str_unquote = function(v) {
  if (!grepl("^\"(?:[^\"\\\\]|\\\\.)*\"\\z", v, perl = TRUE)) return(v)
  body = substr(v, 2L, nchar(v) - 1L)
  parts = regmatches(body, gregexpr("\\\\.", body, perl = TRUE), invert = NA)[[1L]]
  esc = seq_along(parts) %% 2L == 0L
  ch = substr(parts[esc], 2L, 2L)
  map = c(n = "\n", r = "\r", t = "\t")
  hit = ch %in% names(map)
  ch[hit] = map[ch[hit]]
  parts[esc] = ch
  paste(parts, collapse = "")
}

#' Parse the key=value pairs of a block header into a named list of strings
#' @noRd
doc_parse_kv = function(s) {
  if (is.null(s) || !length(s) || is.na(s) || !nzchar(trimws(s))) return(list())
  kv = regmatches(s, gregexpr(doc_re_kv, s, perl = TRUE))[[1L]]
  if (!length(kv)) return(list())
  keys = sub("=.*$", "", kv)
  vals = sub("^[^=]*=", "", kv)
  quoted = startsWith(vals, "\"")
  vals[quoted] = vapply(vals[quoted], doc_str_unquote, "", USE.NAMES = FALSE)
  stats::setNames(as.list(as_utf8(vals)), keys)
}

#' Format header fields in the key order of contract 11.5 (unknown keys last); values that hold
#' a blank, a line break, a quote, `=` or a backslash are quoted so the header stays one line
#' @noRd
doc_format_kv = function(x) {
  x = x[!vapply(x, function(v) is.null(v) || !length(v), NA)]
  if (!length(x)) return("")
  known = intersect(doc_header_keys, names(x))
  x = x[c(known, setdiff(names(x), known))]
  vals = vapply(names(x), function(k) {
    v = as.character(x[[k]])[1L]
    if (is.na(v)) v = "NA"
    quote = k %in% doc_quoted_keys || !nzchar(v) || grepl("[ \t\r\n\"=\\\\]", v)
    if (quote) doc_str_literal(v) else v
  }, "")
  paste0(names(x), "=", vals, collapse = " ")
}

#' The agent blocks of a text: df(id, start, end, indent, header (list column)); attribute
#' `malformed` flags unterminated, nested or orphan markers. Only lines holding "gptr:" are
#' matched against the marker patterns.
#' @noRd
doc_find_blocks = function(lines) {
  lines = as_utf8(as.character(lines))
  hit = which(grepl("gptr:", lines, fixed = TRUE))
  om = regmatches(lines[hit], regexec(doc_re_open, lines[hit], perl = TRUE))
  cm = regmatches(lines[hit], regexec(doc_re_close, lines[hit], perl = TRUE))
  is_open = lengths(om) > 0L
  is_close = lengths(cm) > 0L
  opens = hit[is_open]
  open_m = om[is_open]
  closes = hit[is_close]
  close_ids = vapply(cm[is_close], function(m) m[3L], "")
  ids = character()
  starts = integer()
  ends = integer()
  indents = character()
  headers = list()
  bad = FALSE
  for (k in seq_along(opens)) {
    i = opens[k]
    m = open_m[[k]]
    id = m[3L]
    j = closes[closes > i & close_ids == id]
    nxt = opens[opens > i]
    if (!length(j) || (length(nxt) && nxt[1L] < j[1L])) {
      bad = TRUE
      next
    }
    ids = c(ids, id)
    starts = c(starts, i)
    ends = c(ends, j[1L])
    indents = c(indents, m[2L])
    headers[[length(headers) + 1L]] = doc_parse_kv(m[4L])
  }
  if (anyDuplicated(ids) || length(setdiff(closes, ends))) bad = TRUE
  res = data.frame(id = ids, start = starts, end = ends, indent = indents,
                   stringsAsFactors = FALSE)
  res$header = headers
  attr(res, "malformed") = bad
  res
}

#' Body lines of one row of doc_find_blocks(), without the block's indentation
#' @noRd
doc_block_body = function(lines, block) {
  if (block$end - block$start < 2L) return(character())
  body = lines[(block$start + 1L):(block$end - 1L)]
  ind = block$indent
  if (nzchar(ind)) body = ifelse(startsWith(body, ind), substring(body, nchar(ind) + 1L), body)
  body
}

#' First 8 hex of sha256 of the body as written, without steering lines (IC-49)
#' @noRd
doc_body_sha = function(body) {
  body = as_utf8(as.character(body))
  body = body[!grepl(doc_re_steer, body)]
  substr(hash_sha256(paste(body, collapse = "\n")), 1L, 8L)
}

#' 12 hex of sha256 of the normalised prompt template (contract 7.15): trimws, CRLF -> LF,
#' whitespace around newlines removed
#' @noRd
prompt_hash = function(template) {
  p = as_utf8(paste(as.character(template), collapse = "\n"))
  p = gsub("[ \t]*\r?\n[ \t]*", "\n", trimws(p))
  substr(hash_sha256(p), 1L, 12L)
}

#' 8 hex of sha256 of the sorted interpolated `name=value` pairs, NULL without interpolation
#' (IC-45). `interp` is P08's character vector of pairs or a named list of values.
#' @noRd
args_hash = function(interp) {
  if (is.null(interp) || !length(interp)) return(NULL)
  if (is.list(interp) || (!is.null(names(interp)) && all(nzchar(names(interp))))) {
    vals = vapply(interp, function(v) paste(as.character(v), collapse = ", "), "")
    interp = paste0(names(interp), "=", vals)
  }
  x = sort(as_utf8(as.character(interp)), method = "radix")
  substr(hash_sha256(paste(x, collapse = "\n")), 1L, 8L)
}

#' Status of a block: undone > user-edited (sha) > stale (prompt or args) > fresh. With
#' `ph = NULL` only undone and user-edited are detected. Header keys are matched exactly.
#' @noRd
doc_block_status = function(header, body, ph = NULL, ah = NULL) {
  if (identical(header[["status"]], "undone")) return("undone")
  sha = header[["sha"]]
  if (!is.null(sha) && !identical(sha, doc_body_sha(body))) return("user-edited")
  if (!is.null(ph)) {
    if (!identical(header[["prompt"]], ph)) return("stale")
    if (!identical(header[["args"]] %||% "", ah %||% "")) return("stale")
  }
  "fresh"
}

#' Render a marker block (contract 11.5): header, indented non-empty body lines, footer
#' @noRd
doc_render_block = function(id, header = list(), body = character(), indent = "") {
  kv = doc_format_kv(header)
  head = paste0(indent, "# >>> gptr:", id, if (nzchar(kv)) paste0(" ", kv) else "")
  c(head, doc_indent_lines(as.character(body), indent), paste0(indent, "# <<< gptr:", id))
}

#' Prefix the non-empty lines with an indentation string
#' @noRd
doc_indent_lines = function(x, indent = "") {
  if (!nzchar(indent %||% "")) return(x)
  x[nzchar(x)] = paste0(indent, x[nzchar(x)])
  x
}

#' Replace lines from..to of a text by `new`
#' @noRd
doc_splice = function(lines, from, to, new) {
  c(lines[seq_len(from - 1L)], new, if (to < length(lines)) lines[(to + 1L):length(lines)])
}
