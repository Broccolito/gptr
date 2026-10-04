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

test_that("utf8_mark() marks valid UTF-8 only", {
  x = c("caf\xc3\xa9", "\xff\xfe")
  y = utf8_mark(x)
  expect_identical(Encoding(y), c("UTF-8", "unknown"))
})
