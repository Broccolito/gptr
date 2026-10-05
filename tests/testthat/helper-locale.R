# Locale and R-version helpers for tests of non-ASCII names (contract IC-62; hosted CI-5, D-111).

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

# R >= 4.6's tools::file_ext() and tools::file_path_sans_ext() test the extension on basename(),
# which stops on a marked UTF-8 non-ASCII path in a non-UTF-8 locale ("unable to translate ... to
# native encoding"; hosted R 4.6.1 and devel, CI-5). These follow the R 4.6.1 sources, so a test on
# an older R sees what R 4.6 does once they replace the bindings in tools' namespace.
r46_file_ext = function(x) {
  x = as.character(x)
  if (!length(x)) return(character())
  ifelse(grepl("^(.*[^.]+.*)[.]([[:alnum:]]+)$", basename(x)),
         sub(".*[.]([[:alnum:]]+)$", "\\1", x), "")
}

r46_file_path_sans_ext = function(x, compression = FALSE) {
  x = as.character(x)
  if (!length(x)) return(character())
  if (compression) x = sub("[.](gz|bz2|xz)$", "", x)
  ifelse(grepl("^(.*[^.]+.*)[.]([[:alnum:]]+)$", basename(x)),
         sub("[.]([[:alnum:]]+)$", "", x), x)
}

local_r46_file_ext = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(file_ext = r46_file_ext,
                                  file_path_sans_ext = r46_file_path_sans_ext,
                                  .package = "tools", .env = .env)
}
