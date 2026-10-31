# Locale and encoding helpers for tests of non-ASCII text (contract IC-62; hosted CI-5, D-111).

# Run the calling test where R cannot translate a marked UTF-8 non-ASCII name to the native
# encoding: the C locale on macOS and Linux. Windows R translates every path it hands the file
# system to the native encoding, which in a C locale cannot hold a non-ASCII name, so R itself
# cannot list or open such a file there (hosted Windows, CI-5). R >= 4.2 on current Windows runs
# in UTF-8, so the test keeps that locale on Windows and skips where it is not UTF-8.
local_name_locale = function(.env = parent.frame()) {
  if (.Platform$OS.type == "windows") {
    testthat::skip_if_not(isTRUE(l10n_info()[["UTF-8"]]),
                          "Windows R without a UTF-8 native encoding")
    return(invisible(NULL))
  }
  withr::local_locale(c(LC_CTYPE = "C"), .local_envir = .env)
}

# A byte-wise stand-in for Windows' iconv(), which reads each byte CP1252 lacks (0x81, 0x8d, 0x8f,
# 0x90 and 0x9d) as the C1 control of its code, where macOS's and glibc's refuse it (FIX-34)
win_iconv = function(x, from, to, sub = NA) {
  one = function(b) {
    s = iconv(rawToChar(b), from, to)
    if (is.na(s)) iconv(rawToChar(b), "latin1", to) else s
  }
  vapply(x, function(s) paste(vapply(charToRaw(s), one, ""), collapse = ""), "",
         USE.NAMES = FALSE)
}
