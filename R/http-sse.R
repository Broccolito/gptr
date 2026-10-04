# Byte-level stream splitters (INFRA-23, contract 8.3, IC-64).
#
# Adapted from report 21 section 2.6 (the vectorised `sse_new_r2()` of its verification log)
# with the fixes the verification and IC-64 require: LF, CRLF and lone CR line ends (a CR at
# the end of a chunk is held until the next chunk), a leading BOM stripped, comment lines
# dropped, `data:` lines joined with "\n", the LAST `event:` field wins, `id` and `retry`
# parsed. Boundaries are found with grepRaw() on raw bytes and the incomplete tail is carried,
# so splits inside multi-byte characters and inside CRLF pairs are harmless.

#' Normalise SSE line ends on raw bytes
#'
#' CRLF becomes LF and a lone CR becomes LF. When `final` is FALSE a CR in the last byte is
#' returned separately in `hold` because it may be the first half of a CRLF pair.
#' @noRd
sse_normalise_eol = function(b, final = FALSE) {
  cr = as.raw(13L)
  if (!length(b) || !length(grepRaw(cr, b, fixed = TRUE))) return(list(b = b, hold = raw(0)))
  hold = raw(0)
  n = length(b)
  if (!final && b[n] == cr) {
    hold = cr
    b = b[-n]
    n = n - 1L
  }
  if (!n) return(list(b = b, hold = hold))
  pos = which(b == cr)
  if (!length(pos)) return(list(b = b, hold = hold))
  nxt = pos + 1L
  crlf = nxt <= n & b[pmin(nxt, n)] == as.raw(10L)
  if (any(!crlf)) b[pos[!crlf]] = as.raw(10L)
  if (any(crlf)) b = b[-pos[crlf]]
  list(b = b, hold = hold)
}

#' Last value of one field per event (SSE: the last field of a name wins)
#' @noRd
sse_last_by_group = function(sel, value, g, ids) {
  out = rep(NA_character_, length(ids))
  if (!any(sel)) return(out)
  gs = g[sel]
  vs = value[sel]
  if (anyDuplicated(gs)) {
    last = !duplicated(gs, fromLast = TRUE)
    gs = gs[last]
    vs = vs[last]
  }
  m = match(gs, ids)
  ok = !is.na(m)
  out[m[ok]] = vs[ok]
  out
}

#' Build the event list from parallel vectors (NA means absent)
#' @noRd
sse_events = function(data, ev, id, rt) {
  out = vector("list", length(data))
  for (i in seq_along(data)) {
    out[[i]] = list(event = if (is.na(ev[i])) NULL else ev[i], data = data[i],
                    id = if (is.na(id[i])) NULL else id[i],
                    retry = if (is.na(rt[i])) NULL else as.numeric(rt[i]))
  }
  out
}

#' Strip the field name and the one optional space after the colon
#' @noRd
sse_field_value = function(x, skip) {
  v = substr(x, skip, 1e8L)
  sp = startsWith(v, " ")
  if (any(sp)) v[sp] = substr(v[sp], 2L, 1e8L)
  v
}

#' One event from its (bytes-encoded) data and optional event line
#' @noRd
sse_one = function(data_line, event_line = NULL) {
  d = sse_field_value(data_line, 6L)
  Encoding(d) = "UTF-8"
  e = NULL
  if (!is.null(event_line)) {
    e = sse_field_value(event_line, 7L)
    Encoding(e) = "UTF-8"
  }
  list(list(event = e, data = d, id = NULL, retry = NULL))
}

#' Parse a block of complete SSE events (normalised bytes ending in a blank line)
#'
#' Two fast paths cover what providers send: a block holding exactly one event (`data:`, or
#' `event:` then `data:`), and blocks whose lines are only `event:` and `data:` with at most one
#' of each per event. Anything else (comments, `id`, `retry`, several `data:` or `event:` lines,
#' fields without a colon) takes the general path of the SSE specification.
#' @noRd
sse_parse_block = function(b) {
  if (length(grepRaw(as.raw(0L), b, fixed = TRUE))) {
    gptr_abort("Stream contains a NUL byte that R strings cannot represent.", "provider")
  }
  l = strsplit(rawToChar(b), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  n = length(l)
  if (!n) return(list())
  Encoding(l) = "bytes"
  if (n == 2L && !nzchar(l[2L]) && startsWith(l[1L], "data:")) return(sse_one(l[1L]))
  if (n == 3L && !nzchar(l[3L]) && startsWith(l[1L], "event:") && startsWith(l[2L], "data:")) {
    return(sse_one(l[2L], l[1L]))
  }
  blank = !nzchar(l)
  isd = startsWith(l, "data:")
  ise = startsWith(l, "event:")
  g = cumsum(blank)
  if (all(blank | isd | ise)) {
    gd = g[isd]
    ge = g[ise]
    if (!anyDuplicated(gd) && !anyDuplicated(ge)) {
      if (!length(gd)) return(list())
      data = sse_field_value(l[isd], 6L)
      ev = rep(NA_character_, length(gd))
      if (length(ge)) {
        m = match(ge, gd)
        ok = !is.na(m)
        ev[m[ok]] = sse_field_value(l[ise], 7L)[ok]
      }
      Encoding(data) = "UTF-8"
      Encoding(ev) = "UTF-8"
      na = rep(NA_character_, length(gd))
      return(sse_events(data, ev, na, na))
    }
  }
  keep = !blank & !startsWith(l, ":")
  if (!any(keep)) return(list())
  l = l[keep]
  g = g[keep]
  colon = regexpr(":", l, fixed = TRUE, useBytes = TRUE)
  field = substr(l, 1L, colon - 1L)
  value = substr(l, colon + 1L, 1e8L)
  nc = colon < 0L
  if (any(nc)) {
    field[nc] = l[nc]
    value[nc] = ""
  }
  sp = startsWith(value, " ")
  if (any(sp)) value[sp] = substr(value[sp], 2L, 1e8L)
  isd = field == "data"
  if (!any(isd)) return(list())
  gd = g[isd]
  ids = unique(gd)
  data = if (length(ids) < length(gd)) {
    unname(vapply(split(value[isd], factor(gd, levels = ids)), paste, "", collapse = "\n"))
  } else {
    value[isd]
  }
  ev = sse_last_by_group(field == "event", value, g, ids)
  id = sse_last_by_group(field == "id", value, g, ids)
  valid_retry = field == "retry" & grepl("^[0-9]+$", value, useBytes = TRUE)
  rt = sse_last_by_group(valid_retry, value, g, ids)
  Encoding(data) = "UTF-8"
  Encoding(ev) = "UTF-8"
  Encoding(id) = "UTF-8"
  sse_events(data, ev, id, rt)
}

#' Incremental Server-Sent Events splitter
#'
#' @return An environment with `push(raw)` (the list of events completed by this chunk) and
#'   `flush()` (the final unterminated event, or NULL when there is none; the tail after the
#'   last blank line can hold at most one event). Each event is
#'   `list(event = chr(1) | NULL, data = chr(1), id = chr(1) | NULL, retry = num(1) | NULL)`.
#' @noRd
sse_splitter = function() {
  st = new.env(parent = emptyenv())
  st$buf = raw(0)
  st$bom_checked = FALSE
  bom = as.raw(c(0xef, 0xbb, 0xbf))
  nn = as.raw(c(10L, 10L))
  cr = as.raw(13L)

  strip_bom = function(b, final) {
    if (st$bom_checked) return(b)
    if (!final && length(b) < 3L && identical(b, bom[seq_along(b)])) return(NULL)
    st$bom_checked = TRUE
    if (length(b) >= 3L && identical(b[1:3], bom)) b = b[-(1:3)]
    b
  }

  push = function(chunk) {
    if (!length(chunk)) return(list())
    b = if (length(st$buf)) c(st$buf, chunk) else chunk
    if (!st$bom_checked) {
      b = strip_bom(b, final = FALSE)
      if (is.null(b)) {
        st$buf = c(st$buf, chunk)
        return(list())
      }
    }
    hold = raw(0)
    if (length(grepRaw(cr, b, fixed = TRUE))) {
      nb = sse_normalise_eol(b, final = FALSE)
      b = nb$b
      hold = nb$hold
    }
    p = grepRaw(nn, b, fixed = TRUE, all = TRUE)
    if (!length(p)) {
      st$buf = if (length(hold)) c(b, hold) else b
      return(list())
    }
    last = p[length(p)] + 1L
    n = length(b)
    st$buf = c(if (last < n) b[(last + 1L):n] else raw(0), hold)
    sse_parse_block(b[seq_len(last)])
  }

  flush = function() {
    b = st$buf
    st$buf = raw(0)
    b = strip_bom(b, final = TRUE)
    if (!length(b)) return(NULL)
    b = sse_normalise_eol(b, final = TRUE)$b
    if (!length(b)) return(NULL)
    ev = sse_parse_block(c(b, nn))
    if (length(ev)) ev[[1L]] else NULL
  }

  st$push = push
  st$flush = flush
  st
}

#' Strip one trailing CR from each line (byte-wise, safe for invalid UTF-8)
#' @noRd
ndjson_strip_cr = function(l) {
  e = endsWith(l, "\r")
  if (any(e)) {
    x = l[e]
    Encoding(x) = "bytes"
    l[e] = substr(x, 1L, nchar(x, type = "bytes") - 1L)
  }
  l
}

#' Incremental newline-delimited JSON splitter
#'
#' @return An environment with `push(raw)` (chr of complete, non-empty lines, UTF-8 marked,
#'   trailing CR removed) and `flush()` (the final unterminated line, if any).
#' @noRd
ndjson_splitter = function() {
  st = new.env(parent = emptyenv())
  st$buf = raw(0)
  st$bom_checked = FALSE
  bom = as.raw(c(0xef, 0xbb, 0xbf))
  lf = as.raw(10L)

  to_lines = function(b) {
    if (length(grepRaw(as.raw(0L), b, fixed = TRUE))) {
      gptr_abort("Stream contains a NUL byte that R strings cannot represent.", "provider")
    }
    if (!length(b)) return(character())
    l = strsplit(rawToChar(b), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
    l = ndjson_strip_cr(l)
    l = l[nzchar(l)]
    Encoding(l) = "UTF-8"
    l
  }

  strip_bom = function(b, final) {
    if (st$bom_checked) return(b)
    if (!final && length(b) < 3L && identical(b, bom[seq_along(b)])) return(NULL)
    st$bom_checked = TRUE
    if (length(b) >= 3L && identical(b[1:3], bom)) b = b[-(1:3)]
    b
  }

  push = function(chunk) {
    if (!length(chunk)) return(character())
    b = if (length(st$buf)) c(st$buf, chunk) else chunk
    b = strip_bom(b, final = FALSE)
    if (is.null(b)) {
      st$buf = c(st$buf, chunk)
      return(character())
    }
    p = grepRaw(lf, b, fixed = TRUE, all = TRUE)
    if (!length(p)) {
      st$buf = b
      return(character())
    }
    last = p[length(p)]
    n = length(b)
    st$buf = if (last < n) b[(last + 1L):n] else raw(0)
    to_lines(b[seq_len(last)])
  }

  flush = function() {
    b = strip_bom(st$buf, final = TRUE)
    st$buf = raw(0)
    if (!length(b)) return(character())
    to_lines(b)
  }

  st$push = push
  st$flush = flush
  st
}
