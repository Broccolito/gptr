# Tests of R/skill-templates.R (plan P17). Task 5: Pi's template grammar.

pi_oracle = function() {
  path = test_path("fixtures", "oracles", "pi-templates", "templates.json")
  json_decode(read_utf8(path)$text)
}

test_that("Pi's 67 template tests pass (report 05 section 5.1)", {
  o = pi_oracle()
  n = 0L
  for (case in o$substitute) {
    got = template_substitute(case$template, as.character(unlist(case$args)))
    expect_identical(charToRaw(got), charToRaw(case$expected),
                     label = paste("substitute:", case$template))
    n = n + 1L
  }
  for (case in o$parse) {
    got = template_args_parse(case$input)
    want = as.character(unlist(case$expected))
    expect_identical(lapply(got, charToRaw), lapply(want, charToRaw),
                     label = paste("parse:", case$input))
    n = n + 1L
  }
  for (case in o$expand) {
    got = template_expand_input(case$input, o$templates)
    expect_identical(charToRaw(got), charToRaw(case$expected), label = paste("expand:", case$input))
    n = n + 1L
  }
  expect_identical(n, 67L)
})

test_that("template_expand takes the raw argument string or a vector (contract example)", {
  expect_identical(template_expand("Review $1 for $ARGUMENTS", "analysis.R statistics"),
                   "Review analysis.R for analysis.R statistics")
  expect_identical(template_expand("$2", c("a b", "c")), "c")
  expect_identical(template_expand("Hi $1", NULL), "Hi ")
  expect_error(template_expand(NA_character_, "x"), class = "gptr_error_invalid_argument")
})

test_that("$ARGUMENTS[N] is Claude's 0-based index", {
  expect_identical(template_expand("$ARGUMENTS[0] and $ARGUMENTS[1]", "x y"), "x and y")
  expect_identical(template_expand("$ARGUMENTS[5]", "x"), "")
  expect_identical(template_expand("$ARGUMENTS", "x y"), "x y")
})

test_that("substitution keeps UTF-8 bytes in any locale", {
  cafe = paste0("caf", intToUtf8(0xE9L))
  kanji = intToUtf8(c(0x65E5L, 0x672CL))
  got = template_expand(paste(cafe, "$1"), kanji)
  expect_identical(charToRaw(got), charToRaw(paste(cafe, kanji)))
  expect_identical(Encoding(got), "UTF-8")
})

# Task 5 adaptations (D-084)

test_that("arguments split on the command pattern's ASCII whitespace in every locale (D-084)", {
  expect_identical(template_args_parse("a\vb\fc\rd"), c("a", "b", "c", "d"))
  for (cp in c(0x00A0L, 0x1680L, 0x2003L, 0x2028L, 0x3000L)) {
    word = paste0("x", intToUtf8(cp), "y")
    got = template_args_parse(paste(word, "z"))
    expect_identical(lapply(got, charToRaw), lapply(c(word, "z"), charToRaw),
                     label = sprintf("U+%04X", cp))
    got = template_expand_input(paste("/review", word), list(review = "<$1>"))
    expect_identical(charToRaw(got), charToRaw(paste0("<", word, ">")),
                     label = sprintf("/review with U+%04X", cp))
  }
})

test_that("a long pasted argument is split in linear time (D-084)", {
  long = strrep("x", 100000L)
  elapsed = system.time({
    got = template_args_parse(paste0("\"", long, "\" ", long))
  })
  expect_identical(nchar(got), c(100000L, 100000L))
  expect_lt(elapsed[["elapsed"]], 5)
})

# Task 5 review round 1

test_that("a latin1 argument string is converted before it is joined, in any locale", {
  withr::local_locale(c(LC_CTYPE = "C"))
  l1 = "caf\xe9 x"
  Encoding(l1) = "latin1"
  cafe = paste0("caf", intToUtf8(0xE9L))
  got = template_args_parse(l1)
  expect_identical(lapply(got, charToRaw), lapply(c(cafe, "x"), charToRaw))
  expect_identical(charToRaw(template_expand("$1", l1)), charToRaw(cafe))
  expect_identical(charToRaw(template_expand("$1", c(l1, "y"))), charToRaw(paste(cafe, "x")))
})
