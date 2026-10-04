# The streaming partial-JSON scanner (Task 11; cases from report 03 section 5.2).

scan_value = function(text) {
  scanner = partial_json()
  scanner$push(text)
  scanner$value()
}

show_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}

test_that("partial values follow partial-json Allow.ALL semantics (report 03 cases)", {
  cases = list(
    c("{", "{}"),
    c("{\"", "{}"),
    c("{\"pa", "{}"),
    c("{\"path\"", "{}"),
    c("{\"path\":", "{}"),
    c("{\"path\": \"", "{\"path\":\"\"}"),
    c("{\"path\": \"src/ma", "{\"path\":\"src/ma\"}"),
    c("{\"path\": \"src/main.R\",", "{\"path\":\"src/main.R\"}"),
    c("{\"path\": \"src/main.R\", \"con", "{\"path\":\"src/main.R\"}"),
    c("{\"path\": \"a\", \"content\": \"x = 1\\", "{\"path\":\"a\",\"content\":\"x = 1\"}"),
    c("{\"path\": \"a\", \"content\": \"x = 1\\n", "{\"path\":\"a\",\"content\":\"x = 1\\n\"}"),
    c("{\"s\": \"tab\\there \\\"q\\\" \\u00e", "{\"s\":\"tab\\there \\\"q\\\" \"}"),
    c("{\"s\": \"emoji \\ud83d", "{\"s\":\"emoji \"}"),
    c("{\"s\": \"back\\\\", "{\"s\":\"back\\\\\"}"),
    c("{\"n\": 12", "{\"n\":12}"),
    c("{\"n\": 12.", "{\"n\":12}"),
    c("{\"n\": 1.5e", "{\"n\":1.5}"),
    c("{\"n\": -", "{}"),
    c("{\"a\": 1, \"n\": -", "{\"a\":1}"),
    c("{\"b\": tr", "{\"b\":true}"),
    c("{\"b\": fals", "{\"b\":false}"),
    c("{\"b\": nu", "{\"b\":null}"),
    c("{\"xs\": [1, 2", "{\"xs\":[1,2]}"),
    c("{\"xs\": [1, 2,", "{\"xs\":[1,2]}"),
    c("{\"xs\": [{\"a\": 1}, {\"b\": \"z", "{\"xs\":[{\"a\":1},{\"b\":\"z\"}]}"),
    c("{\"a\": {\"b\": {\"c\": [", "{\"a\":{\"b\":{\"c\":[]}}}"),
    c("{\"a\": \"x, y: {z} [w]\", \"b", "{\"a\":\"x, y: {z} [w]\"}"),
    c("{\"a\": 1}", "{\"a\":1}"),
    c("[\"a\", \"b", "[\"a\",\"b\"]")
  )
  for (case in cases) {
    expect_identical(show_json(scan_value(case[[1]])), case[[2]], label = case[[1]])
  }
  expect_null(partial_json()$value())
})

test_that("the scanner yields the final object for every prefix split (05 P01 acceptance 4)", {
  full = paste0(
    "{\"path\": \"R/plot.R\", \"edits\": [{\"old\": \"ggplot(df, aes(x, y))\", ",
    "\"new\": \"ggplot(df, aes(x = wt, y = mpg)) +\\n  geom_point(colour = \\\"#1b9e77\\\")\"}, ",
    "{\"old\": \"caf\u00e9 \\u00e9 \\ud83d\\ude00\", \"new\": null}], \"dry_run\": false, ",
    "\"limit\": 12.5e3}"
  )
  expected = json_decode(full)
  bytes = charToRaw(full)
  for (k in seq_len(length(bytes) - 1L)) {
    scanner = partial_json()
    scanner$push(bytes[seq_len(k)])
    scanner$push(bytes[(k + 1L):length(bytes)])
    expect_identical(scanner$value(), expected, label = paste("split at byte", k))
    expect_true(scanner$complete())
  }
})

test_that("incremental pushes agree with one-shot parsing of every prefix", {
  full = "{\"code\": \"x = c(1, 2)\\nprint(x)\", \"record\": true, \"note\": \"sum\"}"
  bytes = charToRaw(full)
  for (k in seq_along(bytes)) {
    prefix = bytes[seq_len(k)]
    scanner = partial_json()
    cuts = unique(c(0L, k %/% 3L, (2L * k) %/% 3L, k))
    for (j in seq_len(length(cuts) - 1L)) {
      if (cuts[j + 1L] > cuts[j]) scanner$push(prefix[(cuts[j] + 1L):cuts[j + 1L]])
    }
    expect_identical(scanner$value(), scan_value(prefix), label = paste("prefix", k))
  }
})

test_that("complete(), text() and preview() report the scanner state", {
  scanner = partial_json()
  scanner$push("{\"a\": ")
  expect_false(scanner$complete())
  expect_identical(scanner$text(), "{\"a\": ")
  expect_identical(scanner$preview(min_interval = 0), json_obj())
  scanner$push("1}")
  expect_true(scanner$complete())
  expect_identical(scanner$preview(min_interval = 0), list(a = 1L))
  expect_null(scanner$preview(min_interval = 3600))
})

test_that("a raw delta that ends inside a multi-byte character never makes value() fail", {
  full = charToRaw("{\"note\": \"caf\u00e9 \u4e2d\"}")
  for (k in seq_len(length(full) - 1L)) {
    scanner = partial_json()
    scanner$push(full[seq_len(k)])
    expect_true(is.list(scanner$value()), label = paste("value() after byte", k))
    expect_true(validUTF8(scanner$text()), label = paste("text() after byte", k))
    scanner$push(full[(k + 1L):length(full)])
    expect_identical(scanner$value(), list(note = "caf\u00e9 \u4e2d"), label = paste("byte", k))
  }
  scanner = partial_json()
  scanner$push(full[1:14])
  expect_identical(scanner$value(), list(note = "caf"))
})

test_that("raw control characters inside strings are repaired", {
  broken = "{\"cmd\": \"line1\nline2\ttabbed \\d+\"}"
  expect_identical(scan_value(broken), list(cmd = "line1\nline2\ttabbed \\d+"))
})

test_that("20,000 small deltas are scanned in linear time", {
  big = paste0("{\"content\": \"", strrep("x = c(1, 2, 3)\\n", 5000), "\"}")
  bytes = charToRaw(big)
  cuts = unique(as.integer(seq(0, length(bytes), length.out = 20001)))
  scanner = partial_json()
  elapsed = system.time(
    for (j in seq_len(length(cuts) - 1L)) scanner$push(bytes[(cuts[j] + 1L):cuts[j + 1L]])
  )[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_identical(nchar(scanner$value()$content), 5000L * 15L)
})
