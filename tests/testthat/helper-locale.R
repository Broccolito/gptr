# Locale helper for tests of non-ASCII names (contract IC-62; hosted CI-5, D-111).

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
