# Encoding at every ingress (contract IC-62; architecture section 6.6).
# This is the only file that may call enc2utf8(): enc2utf8() rewrites unmarked UTF-8 to
# "<c3><a9>" in a C locale, so text of unknown encoding goes through as_utf8() instead.

#' Mark valid UTF-8 strings of unknown encoding as UTF-8 (ASCII is left alone)
#' @noRd
utf8_mark = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  idx = which(Encoding(x) == "unknown" & !is.na(x))
  if (length(idx)) {
    idx = idx[validUTF8(x[idx])]
    if (length(idx)) {
      y = x[idx]
      Encoding(y) = "UTF-8"
      x[idx] = y
    }
  }
  x
}

#' Normalise text entering gptr to marked UTF-8
#'
#' Valid UTF-8 of unknown encoding is marked UTF-8; other unknown or latin1 strings are converted
#' from the native encoding with enc2utf8(). Attributes (names, class) are kept.
#' @noRd
as_utf8 = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  x = utf8_mark(x)
  enc = Encoding(x)
  convert = which(!is.na(x) & (enc == "latin1" | (enc == "unknown" & !validUTF8(x))))
  if (length(convert)) x[convert] = enc2utf8(x[convert])
  x
}

#' Bytes for the operating system (argv, environment, working directory): UTF-8 without a mark
#'
#' processx translates UTF-8-marked strings to the native encoding, which in a C locale turns
#' non-ASCII characters into "<U+00E9>" escapes (report G5); unmarked UTF-8 bytes pass unchanged.
#' @noRd
os_bytes = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  x = as_utf8(x)
  Encoding(x) = "unknown"
  x
}

#' Decode bytes as UTF-8 (a leading BOM and NUL bytes dropped), with a code-page fallback
#' @noRd
raw_to_utf8 = function(x, fallback = "CP1252") {
  if (length(x) >= 3L && identical(x[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) x = x[-(1:3)]
  x = x[x != as.raw(0L)]
  text = if (length(x)) rawToChar(x) else ""
  if (validUTF8(text)) {
    Encoding(text) = "UTF-8"
    return(text)
  }
  out = iconv(text, from = fallback, to = "UTF-8", sub = "?")
  if (is.na(out)) out = iconv(text, from = "latin1", to = "UTF-8", sub = "?")
  Encoding(out) = "UTF-8"
  out
}

#' Read a text file as UTF-8
#'
#' Returns `list(text, eol, bom, encoding, final_newline)`: `text` has LF line endings and no
#' BOM; `eol` is "\r\n" when the file uses CRLF, else "\n"; `encoding` is "UTF-8" or "CP1252".
#' @noRd
read_utf8 = function(path) {
  check_string(path, "path")
  size = file.size(path)
  if (is.na(size) || dir.exists(path)) {
    gptr_abort(
      paste0("Cannot read '", path, "': it is not an existing file."),
      "invalid_argument",
      arg = "path",
      expected = "an existing file"
    )
  }
  bytes = readBin(path, "raw", n = size)
  bom = length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  body = if (bom) bytes[-(1:3)] else bytes
  valid = validUTF8(rawToChar(body[body != as.raw(0L)]))
  text = raw_to_utf8(body)
  eol = if (grepl("\r\n", text, fixed = TRUE)) "\r\n" else "\n"
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  list(
    text = text,
    eol = eol,
    bom = bom,
    encoding = if (valid) "UTF-8" else "CP1252",
    final_newline = endsWith(text, "\n")
  )
}

#' Write UTF-8 text atomically, with the given line ending, BOM and final newline
#'
#' `read_utf8()` followed by `write_utf8()` with the returned `eol`, `bom` and `final_newline`
#' reproduces a UTF-8 file byte for byte.
#' @noRd
write_utf8 = function(path, text, eol = "\n", bom = FALSE, final_newline = TRUE) {
  check_string(path, "path")
  eol = check_choice(eol, c("\n", "\r\n"), "eol")
  check_flag(bom, "bom")
  check_flag(final_newline, "final_newline")
  text = paste(as_utf8(as.character(text)), collapse = "\n")
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  if (final_newline && !endsWith(text, "\n")) text = paste0(text, "\n")
  if (!final_newline && endsWith(text, "\n")) text = substr(text, 1L, nchar(text) - 1L)
  if (identical(eol, "\r\n")) text = gsub("\n", "\r\n", text, fixed = TRUE)
  bytes = charToRaw(text)
  if (bom) bytes = c(as.raw(c(0xef, 0xbb, 0xbf)), bytes)
  write_atomic(path, bytes)
}

#' Is the session locale UTF-8? Warns once (class `locale`) when it is not
#' @noRd
locale_utf8 = function() {
  ok = isTRUE(l10n_info()[["UTF-8"]])
  if (!ok) {
    gptr_warn(
      paste(
        "This R session does not use a UTF-8 locale. gptr marks its text as UTF-8 itself,",
        "but non-ASCII characters may print incorrectly."
      ),
      "locale",
      .once = "locale"
    )
  }
  ok
}
