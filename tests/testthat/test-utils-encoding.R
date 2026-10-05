# Encoding at ingress (Task 2: as_utf8; Task 5: byte-level I/O; IC-62).

local_c_ctype = function(.env = parent.frame()) {
  old = Sys.getlocale("LC_CTYPE")
  ok = suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))
  if (!nzchar(ok)) testthat::skip("cannot switch LC_CTYPE to C")
  withr::defer(Sys.setlocale("LC_CTYPE", old), envir = .env)
}

cafe_bytes = as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))

test_that("as_utf8() keeps valid UTF-8 bytes under LC_ALL=C where enc2utf8() does not (IC-62)", {
  x = "caf\xc3\xa9"
  expect_identical(Encoding(x), "unknown")
  local_c_ctype()
  y = as_utf8(x)
  expect_identical(charToRaw(y), cafe_bytes)
  expect_identical(Encoding(y), "UTF-8")
  expect_false(identical(charToRaw(enc2utf8(x)), charToRaw(y)))
})

test_that("as_utf8() converts latin1, leaves ASCII and NA, keeps names", {
  latin = "caf\xe9"
  Encoding(latin) = "latin1"
  expect_identical(as_utf8(latin), "caf\u00e9")
  expect_identical(charToRaw(as_utf8(latin)), cafe_bytes)
  x = c(a = "plain", b = NA)
  expect_identical(as_utf8(x), x)
  expect_identical(as_utf8(1:3), 1:3)
})

test_that("as_utf8() keeps bytes that are not UTF-8 in a UTF-8 locale, on every R version", {
  # A UTF-8 native encoding has nothing to convert them from; R 4.2.3's enc2utf8() turned them
  # into "<ff>" text, so code holding a stray byte ran as other code (D-063).
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "the session's native encoding is not UTF-8")
  bad = rawToChar(as.raw(c(0x61, 0xff)))
  latin = "caf\xe9"
  Encoding(latin) = "latin1"
  x = c(k = bad, l = latin, m = "caf\xc3\xa9", n = "plain", o = NA)
  y = as_utf8(x)
  expect_identical(charToRaw(y[["k"]]), as.raw(c(0x61, 0xff)))
  expect_identical(unname(Encoding(y)), c("UTF-8", "UTF-8", "UTF-8", "unknown", "unknown"))
  expect_identical(unname(y[2:5]), c("caf\u00e9", "caf\u00e9", "plain", NA))
  expect_named(y, names(x))
})

test_that("utf8_mark() marks valid UTF-8 only", {
  x = c("caf\xc3\xa9", "\xff\xfe")
  y = utf8_mark(x)
  expect_identical(Encoding(y), c("UTF-8", "unknown"))
})

test_that("os_bytes() hands UTF-8 bytes to the OS without an encoding mark", {
  y = os_bytes("caf\u00e9")
  expect_identical(Encoding(y), "unknown")
  expect_identical(charToRaw(y), cafe_bytes)
})

test_that("raw_to_utf8() strips a BOM and falls back to CP1252", {
  expect_identical(raw_to_utf8(as.raw(c(0xef, 0xbb, 0xbf, 0x61))), "a")
  expect_identical(raw_to_utf8(as.raw(c(0x63, 0x61, 0x66, 0xe9))), "caf\u00e9")
  expect_identical(raw_to_utf8(raw(0)), "")
})

test_that("read_utf8() and write_utf8() round-trip CRLF, BOM and missing final newlines", {
  dir = withr::local_tempdir()
  cases = list(
    lf = charToRaw("a\nb\n"),
    crlf_bom = c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ny = 2\r\n")),
    no_final = charToRaw("last line"),
    utf8 = c(cafe_bytes, as.raw(0x0a))
  )
  for (name in names(cases)) {
    src = file.path(dir, paste0(name, ".txt"))
    out = file.path(dir, paste0(name, "-copy.txt"))
    writeBin(cases[[name]], src)
    info = read_utf8(src)
    expect_false(grepl("\r", info$text, fixed = TRUE), label = name)
    write_utf8(out, info$text, eol = info$eol, bom = info$bom, final_newline = info$final_newline)
    expect_identical(readBin(out, "raw", 1000), cases[[name]], label = name)
  }
  info = read_utf8(file.path(dir, "crlf_bom.txt"))
  expect_identical(info$eol, "\r\n")
  expect_true(info$bom)
  expect_identical(info$text, "x = 1\ny = 2\n")
  expect_false(read_utf8(file.path(dir, "no_final.txt"))$final_newline)
  expect_error(read_utf8(file.path(dir, "missing.txt")), class = "gptr_error_invalid_argument")
})
