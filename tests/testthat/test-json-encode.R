# JSON layer (Task 7; conventions section 6).

test_that("json_encode() uses auto_unbox, null and full digits", {
  expect_identical(
    json_encode(list(a = 1, b = "x", c = NULL, d = TRUE)),
    "{\"a\":1,\"b\":\"x\",\"c\":null,\"d\":true}"
  )
  expect_identical(json_encode(list(x = I("only"))), "{\"x\":[\"only\"]}")
  expect_identical(json_encode(list()), "[]")
  expect_identical(json_encode(json_obj()), "{}")
  expect_identical(json_encode(1759200000123), "1759200000123")
  expect_identical(json_encode(1 / 3), "0.333333333333333")
  expect_identical(Encoding(json_encode("caf\u00e9")), "UTF-8")
  expect_match(json_encode(list(a = 1), pretty = TRUE), "\n", fixed = TRUE)
})

test_that("json_verbatim() pieces are embedded unchanged", {
  piece = json_verbatim("{\"frozen\":[1,2]}")
  expect_s3_class(piece, "json")
  expect_identical(
    json_encode(list(tools = piece, n = 2L)), "{\"tools\":{\"frozen\":[1,2]},\"n\":2}"
  )
})

test_that("json_decode() never simplifies and never reads files", {
  x = json_decode("{\"a\":[1,2],\"b\":{},\"c\":[],\"d\":null}")
  expect_identical(x$a, list(1L, 2L))
  expect_identical(x$b, json_obj())
  expect_identical(x$c, list())
  expect_true("d" %in% names(x))
  file = withr::local_tempfile(fileext = ".json")
  writeLines("{\"secret\": 1}", file)
  expect_error(json_decode(file))
})

test_that("json_encode() writes correct UTF-8 bytes for unmarked input in a C locale", {
  old = Sys.getlocale("LC_CTYPE")
  withr::defer(Sys.setlocale("LC_CTYPE", old))
  skip_if(!nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))), "cannot use the C locale")
  out = json_encode(list(text = "caf\xc3\xa9"))
  expect_identical(charToRaw(out), c(charToRaw("{\"text\":\"caf"), as.raw(c(0xc3, 0xa9)),
                                     charToRaw("\"}")))
})

test_that("json_encode() and json_decode() round-trip nested records", {
  x = list(role = "user", content = list(list(type = "text", text = "\u4e2d\u6587")), n = 3L)
  expect_identical(json_decode(json_encode(x)), x)
})
