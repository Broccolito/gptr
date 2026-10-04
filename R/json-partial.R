# Incremental, tolerant parser for streamed tool-call arguments (INFRA-09).
# Adapted from the verified prototype in report 03 section 5.2 (R/partial_json.R), which follows
# the npm package partial-json with Allow.ALL as used by Pi: an unterminated string value is
# truncated (a dangling escape removed); an unterminated key, a key without a value or a trailing
# comma is dropped; partial literals (t, tr, nul, fals) are completed; a partial number becomes
# its longest valid prefix; open containers are closed. Each byte is inspected once and only
# structural bytes reach the R loop; parsing is delegated to jsonlite.

#' Structural bytes: " \ { } [ ] , :
#' @noRd
pj_specials = as.raw(c(0x22, 0x5c, 0x7b, 0x7d, 0x5b, 0x5d, 0x2c, 0x3a))

#' JSON whitespace bytes
#' @noRd
pj_ws = as.raw(c(0x20, 0x09, 0x0a, 0x0d))

#' Complete a partial scalar token, or NULL
#' @noRd
pj_complete_scalar = function(token) {
  for (literal in c("true", "false", "null")) {
    if (startsWith(literal, token)) return(literal)
  }
  number = "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
  while (nzchar(token)) {
    if (grepl(number, token)) return(token)
    token = substr(token, 1L, nchar(token) - 1L)
  }
  NULL
}

#' Drop an incomplete UTF-8 sequence from the end of string bytes (a raw delta may end inside a
#' multi-byte character; the rest arrives with the next delta)
#' @noRd
pj_trim_partial_utf8 = function(bytes) {
  n = length(bytes)
  if (n == 0L) return(bytes)
  tail_ints = as.integer(bytes[max(1L, n - 3L):n])
  k = length(tail_ints)
  for (i in rev(seq_len(k))) {
    b = tail_ints[[i]]
    if (b < 128L) return(bytes)
    if (b >= 192L) {
      need = if (b >= 240L) 4L else if (b >= 224L) 3L else 2L
      have = k - i + 1L
      if (have < need) return(bytes[seq_len(n - have)])
      return(bytes)
    }
  }
  bytes
}

#' Remove an incomplete escape (or an unpaired high surrogate) from the end of string bytes
#' @noRd
pj_trim_dangling_escape = function(bytes) {
  repeat {
    n = length(bytes)
    if (n == 0L) return(bytes)
    from = max(1L, n - 11L)
    backslashes = which(bytes[from:n] == as.raw(0x5c))
    if (!length(backslashes)) return(bytes)
    last = from + backslashes[[length(backslashes)]] - 1L
    run = 0L
    i = last
    while (i >= 1L && bytes[[i]] == as.raw(0x5c)) {
      run = run + 1L
      i = i - 1L
    }
    if (run %% 2L == 0L) return(bytes)
    rest = if (last < n) rawToChar(bytes[(last + 1L):n]) else ""
    if (!nzchar(rest)) return(bytes[seq_len(last - 1L)])
    dangling = grepl("^u[0-9a-fA-F]{0,3}$", rest, useBytes = TRUE) ||
      grepl("^u[dD][89abAB][0-9a-fA-F]{2}$", rest, useBytes = TRUE)
    if (!dangling) return(bytes)
    bytes = bytes[seq_len(last - 1L)]
  }
}

#' Escape raw control characters inside strings and double backslashes that start an invalid
#' escape (port of Pi's repairJson())
#' @noRd
pj_repair = function(text) {
  b = charToRaw(as_utf8(text))
  n = length(b)
  if (n == 0L) return(text)
  idx = which(b == as.raw(0x22) | b == as.raw(0x5c) | b < as.raw(0x20))
  if (!length(idx)) return(text)
  out = vector("list", length(idx) * 2L + 1L)
  k = 0L
  last = 0L
  in_string = FALSE
  skip = 0L
  valid_escapes = as.raw(c(0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75))
  for (i in idx) {
    if (i <= skip) next
    byte = b[[i]]
    if (!in_string) {
      if (byte == as.raw(0x22)) in_string = TRUE
      next
    }
    if (byte == as.raw(0x22)) {
      in_string = FALSE
      next
    }
    if (byte == as.raw(0x5c)) {
      following = if (i < n) b[[i + 1L]] else NULL
      ok = !is.null(following) && following %in% valid_escapes
      if (ok && following == as.raw(0x75)) {
        hex = if (i + 5L <= n) rawToChar(b[(i + 2L):(i + 5L)]) else ""
        ok = grepl("^[0-9a-fA-F]{4}$", hex)
      }
      if (ok) {
        skip = i + 1L
        next
      }
      k = k + 1L
      out[[k]] = b[(last + 1L):i]
      k = k + 1L
      out[[k]] = as.raw(0x5c)
      last = i
      next
    }
    if (i - 1L > last) {
      k = k + 1L
      out[[k]] = b[(last + 1L):(i - 1L)]
    }
    escape = switch(as.character(as.integer(byte)),
      "8" = "\\b", "12" = "\\f", "10" = "\\n", "13" = "\\r", "9" = "\\t",
      sprintf("\\u%04x", as.integer(byte))
    )
    k = k + 1L
    out[[k]] = charToRaw(escape)
    last = i
  }
  if (last < n) {
    k = k + 1L
    out[[k]] = b[(last + 1L):n]
  }
  res = rawToChar(unlist(out[seq_len(k)]))
  Encoding(res) = "UTF-8"
  res
}

#' Strict parse, retried once after pj_repair(); errors when the text is not valid JSON
#' @noRd
pj_parse = function(text) {
  tryCatch(json_decode(text), error = function(e) {
    fixed = pj_repair(text)
    if (identical(fixed, text)) stop(e)
    json_decode(fixed)
  })
}

#' A streaming partial-JSON scanner
#'
#' Returns an environment with `push(delta)` (character or raw), `value()` (the best-effort parsed
#' value so far: a named list for objects, `NULL` before any input; it never signals an error),
#' `text()` (the text so far, without a trailing incomplete UTF-8 character), `complete()` (TRUE
#' once the top-level value is closed) and `preview(min_interval = 0.1)` (`value()` at most every
#' `min_interval` seconds, else NULL; for throttled tool-call previews). A raw delta may end
#' inside a multi-byte character: the incomplete bytes are left out until the next delta.
#' @noRd
partial_json = function() {
  capacity = 1024L
  buf = raw(capacity)
  n = 0L
  stack = character()
  expect = "value"
  in_string = FALSE
  string_is_key = FALSE
  string_start = 0L
  escaped = FALSE
  last_safe = 0L
  tail_start = 1L
  cache_n = -1L
  cache_value = NULL
  last_preview = -Inf

  scalar_pending = function(upto) {
    if (!(expect %in% c("value", "value_or_end"))) return(FALSE)
    if (upto < tail_start) return(FALSE)
    any(!(buf[tail_start:upto] %in% pj_ws))
  }
  value_done = function(pos) {
    last_safe <<- pos
    expect <<- if (length(stack)) "after_value" else "done"
  }

  push = function(delta) {
    if (is.character(delta)) delta = charToRaw(as_utf8(paste(delta, collapse = "")))
    m = length(delta)
    if (m == 0L) return(invisible(NULL))
    if (n + m > capacity) {
      while (n + m > capacity) capacity <<- capacity * 2L
      grown = raw(capacity)
      if (n > 0L) grown[seq_len(n)] = buf[seq_len(n)]
      buf <<- grown
    }
    buf[(n + 1L):(n + m)] <<- delta
    base = n
    n <<- n + m
    specials = which(delta %in% pj_specials)
    skip = 0L
    if (escaped) {
      skip = 1L
      escaped <<- FALSE
    }
    for (r in specials) {
      if (r == skip) next
      b = delta[[r]]
      pos = base + r
      if (in_string) {
        if (b == as.raw(0x5c)) {
          if (r == m) escaped <<- TRUE else skip = r + 1L
        } else if (b == as.raw(0x22)) {
          in_string <<- FALSE
          if (string_is_key) expect <<- "colon" else value_done(pos)
          tail_start <<- pos + 1L
        }
        next
      }
      if (expect == "done") next
      if (b == as.raw(0x22)) {
        in_string <<- TRUE
        string_start <<- pos
        string_is_key <<- length(stack) > 0L && stack[[length(stack)]] == "{" &&
          expect %in% c("key_or_end", "key")
      } else if (b == as.raw(0x7b) || b == as.raw(0x5b)) {
        open = if (b == as.raw(0x7b)) "{" else "["
        stack[[length(stack) + 1L]] <<- open
        expect <<- if (open == "{") "key_or_end" else "value_or_end"
        last_safe <<- pos
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x7d) || b == as.raw(0x5d)) {
        if (length(stack)) stack <<- stack[-length(stack)]
        value_done(pos)
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x2c)) {
        if (scalar_pending(pos - 1L)) last_safe <<- pos - 1L
        expect <<- if (length(stack) && stack[[length(stack)]] == "{") "key" else "value"
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x3a)) {
        expect <<- "value"
        tail_start <<- pos + 1L
      }
    }
    invisible(NULL)
  }

  closers = function() {
    if (!length(stack)) return(raw(0))
    charToRaw(paste(rev(ifelse(stack == "{", "}", "]")), collapse = ""))
  }

  completed_text = function() {
    if (n == 0L) return("")
    if (in_string) {
      if (string_is_key) {
        body = if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      } else {
        content = if (n > string_start) buf[(string_start + 1L):n] else raw(0)
        content = pj_trim_dangling_escape(pj_trim_partial_utf8(content))
        body = c(buf[seq_len(string_start)], content, as.raw(0x22))
      }
    } else if (expect %in% c("after_value", "done")) {
      body = buf[seq_len(if (expect == "done") last_safe else n)]
    } else {
      token = if (n >= tail_start) buf[tail_start:n] else raw(0)
      token = token[!(token %in% pj_ws)]
      done = if (length(token) && expect %in% c("value", "value_or_end")) {
        pj_complete_scalar(rawToChar(token))
      }
      if (!is.null(done)) {
        body = c(if (tail_start > 1L) buf[seq_len(tail_start - 1L)] else raw(0), charToRaw(done))
      } else {
        body = if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      }
    }
    if (!length(body)) return("")
    out = rawToChar(c(body, closers()))
    Encoding(out) = "UTF-8"
    out
  }

  value = function() {
    if (n == 0L) return(NULL)
    if (cache_n == n) return(cache_value)
    # Never an R condition: a stream normaliser calls value() between deltas (INFRA-02)
    parsed = tryCatch({
      text = completed_text()
      blank = !length(grep("[^ \t\r\n]", text, useBytes = TRUE))
      if (blank) json_obj() else pj_parse(text)
    }, error = function(e) json_obj())
    cache_n <<- n
    cache_value <<- parsed %||% json_obj()
    cache_value
  }

  text = function() {
    if (n == 0L) return("")
    out = rawToChar(pj_trim_partial_utf8(buf[seq_len(n)]))
    Encoding(out) = "UTF-8"
    out
  }

  complete = function() {
    identical(expect, "done")
  }

  preview = function(min_interval = 0.1) {
    now = proc.time()[["elapsed"]]
    if (now - last_preview < min_interval) return(NULL)
    last_preview <<- now
    value()
  }

  api = new.env(parent = emptyenv())
  api$push = push
  api$value = value
  api$text = text
  api$complete = complete
  api$preview = preview
  class(api) = "gptr_partial_json"
  api
}
