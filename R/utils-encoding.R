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
#' from the native encoding with enc2utf8(). When the native encoding is UTF-8, an unknown string
#' that is not valid UTF-8 has nothing to be converted from: its bytes are kept and marked UTF-8,
#' as enc2utf8() does on R 4.5 and later (R 4.2.3 turned each such byte into "<xx>" text, which
#' made such code run as other code instead of being refused; DEVIATIONS D-063). Attributes
#' (names, class) are kept.
#' @noRd
as_utf8 = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  enc = Encoding(x)
  mark = enc == "unknown" & !is.na(x)
  convert = enc == "latin1"
  if (any(mark)) {
    invalid = mark & !validUTF8(x)
    if (any(invalid) && !isTRUE(l10n_info()[["UTF-8"]])) {
      mark = mark & !invalid
      convert = convert | invalid
    }
    y = x[mark]
    Encoding(y) = "UTF-8"
    x[mark] = y
  }
  if (any(convert)) x[convert] = enc2utf8(x[convert])
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

#' Path handed to base file-system functions: UTF-8 bytes without a mark in non-UTF-8 Unix locales
#' (a marked non-ASCII path fails there with "unable to translate"; report 01 E4)
#' @noRd
fs_path = function(p) {
  if (.Platform$OS.type != "windows" && !isTRUE(l10n_info()[["UTF-8"]])) Encoding(p) = "unknown"
  p
}

#' Parse R text so that parse-data columns and getParseText() (which cuts source lines with
#' substr()) count the same unit (IC-62). In a UTF-8 locale marked UTF-8 is parsed: nothing is
#' translated and both count characters. Elsewhere the parser would translate marked text to the
#' native encoding (in a C locale each non-ASCII character becomes "<U+00E9>" text), so the
#' unmarked UTF-8 bytes are parsed and both count bytes. Strings read back from the result go
#' through as_utf8(). Parse data is kept even where the caller turned it off: sys.source() sets
#' `keep.parse.data = FALSE` while the sourced code runs.
#' @noRd
doc_parse_text = function(lines, keep_source = TRUE) {
  old = options(keep.parse.data = TRUE)
  on.exit(options(old), add = TRUE)
  text = if (isTRUE(l10n_info()[["UTF-8"]])) as_utf8(lines) else os_bytes(lines)
  parse(text = text, keep.source = keep_source)
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
  # the five bytes CP1252 lacks become `?` first, as Windows' iconv() reads them as C1 controls
  if (identical(fallback, "CP1252")) {
    x[x %in% as.raw(c(0x81, 0x8d, 0x8f, 0x90, 0x9d))] = as.raw(0x3f)
    text = rawToChar(x)
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
  # Windows can report a file link's empty metadata rather than the target's byte length.
  # Obtain both size and content from the same canonical target.
  target = if (is_windows()) path_norm(path) else path
  info = path_info(target)
  if (is.na(info$size) || isTRUE(info$isdir)) {
    gptr_abort(
      paste0("Cannot read '", path, "': it is not an existing file."),
      "invalid_argument",
      arg = "path",
      expected = "an existing file"
    )
  }
  bytes = readBin(target, "raw", n = info$size)
  bom = length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  valid = validUTF8(rawToChar(bytes[bytes != as.raw(0L)]))
  text = raw_to_utf8(bytes)
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
