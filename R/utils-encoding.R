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
