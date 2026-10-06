# tests/testthat/test-console-render.R -- the console's printing layer (P14)

render_sample = paste0(
  "# Model summary\n\nThe **linear model** explains most of the variance in `mpg`; the ",
  "coefficient on `wt` is strongly negative, which means heavier cars travel fewer miles ",
  "per gallon on average.\r\n\r\n",
  "- first bullet that is long enough to need wrapping onto a second line at forty columns\n",
  "- second bullet with **bold text** inside\n",
  "1. numbered item\n\n",
  "> a quoted remark from the user\n\n",
  "```r\nfit = lm(mpg ~ wt, data = mtcars)\nsummary(fit)$r.squared\n```\n",
  "Done: R\u00b2 = 0.75 \u2014 averaging wide chars \u4e2d\u6587\u5b57\u7b26 too.")

render_chunks = function(chunks, width = 40L) {
  utils::capture.output({
    r = render_markdown_stream(width)
    for (ch in chunks) r$write(ch)
    r$finish()
  })
}

random_chunks = function(x, maxlen) {
  chars = strsplit(x, "")[[1L]]
  out = character()
  i = 1L
  while (i <= length(chars)) {
    k = sample.int(maxlen, 1L)
    out = c(out, paste(chars[i:min(length(chars), i + k - 1L)], collapse = ""))
    i = i + k
  }
  out
}

test_that("the output does not depend on chunking, plain and styled (acceptance 3)", {
  withr::local_seed(42)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    ref = render_chunks(render_sample)
    same = vapply(seq_len(200L), function(i) {
      identical(render_chunks(random_chunks(render_sample, sample.int(9L, 1L))), ref)
    }, NA)
    expect_true(all(same))
  }
})

test_that("prose lines respect the width and bullets hang (UTF-8 locale)", {
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "display widths need a UTF-8 locale (report 18)")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks(render_sample, width = 40L)
  prose = out[!grepl("^(```|fit|summary)", out)]
  expect_true(all(nchar(prose, type = "width") <= 40L))
  expect_true("- first bullet that is long enough to" %in% out)
  expect_true("  need wrapping onto a second line at" %in% out)
  expect_true("fit = lm(mpg ~ wt, data = mtcars)" %in% out)
})

test_that("a CRLF split across two chunks gives one line break", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(render_chunks(c("one\r", "\ntwo")), render_chunks("one\r\ntwo"))
  expect_identical(render_chunks("one\r\ntwo"), c("one", "two"))
  expect_identical(render_chunks(c("one\r", "two")), c("one", "two"))
})

test_that("untrusted braces are printed verbatim and never evaluated (rule C1)", {
  withr::local_envvar(GPTR_PWNED = NA)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_chunks(c("Try {Sys.setenv(GPTR", "_PWNED = \"1\")} now"), width = 80L)
    expect_true(any(grepl("{Sys.setenv(GPTR_PWNED = \"1\")}", out, fixed = TRUE)))
  }
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("control, bidi, zero-width characters and invalid bytes are escaped (IC-53 item 8)", {
  expect_identical(console_escape("a\033[31mb"), "a<U+001B>[31mb")
  expect_identical(console_escape(paste0("x", intToUtf8(0x202e), "y")), "x<U+202E>y")
  expect_identical(console_escape(paste0("x", intToUtf8(0x200b), "y")), "x<U+200B>y")
  expect_identical(console_escape("tab\there\nnext"), "tab\there\nnext")
  expect_identical(console_escape("a\nb", newlines = FALSE), "a<U+000A>b")
  expect_identical(console_escape(c("ok", NA, "")), c("ok", NA, ""))
  expect_identical(console_escape("caf\u00e9"), "caf\u00e9")
  expect_identical(console_escape("end\n"), "end\n")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks("red \033[31mtext\033[0m", width = 80L)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_true(any(grepl("<U+001B>[31m", out, fixed = TRUE)))
  bad = rawToChar(as.raw(c(0x61, 0xff, 0x0a, 0x62)))
  expect_identical(console_escape(bad), "a<ff>\nb")
  expect_identical(console_escape(paste0("\033", bad), newlines = FALSE), "<U+001B>a<ff><U+000A>b")
  surrogate = rawToChar(as.raw(c(0xed, 0xa0, 0x80, 0x1b)))
  expect_identical(console_lines(surrogate), "<ed><a0><80><U+001B>")
  expect_identical(console_lines(bad), c("a<ff>", "b"))
  expect_identical(render_chunks(bad), c("a<ff>", "b"))
})

test_that("console_lines() splits on any line end and console_out() prints escaped lines", {
  expect_identical(console_lines(c("a\r\nb\rc", "d\033")), c("a", "b", "c", "d<U+001B>"))
  expect_identical(console_lines(NA_character_), character())
  expect_identical(utils::capture.output(console_out("x {y}\ny\033")), c("x {y}", "y<U+001B>"))
})

test_that("notices go to stderr, never to stdout", {
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output(console_notice("[gptr] ", "hello"), type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "[gptr] hello")
})

test_that("reset_line() ends a partial line and finish() closes it", {
  withr::local_options(cli.num_colors = 1L)
  out = utils::capture.output({
    r = render_markdown_stream(80L)
    r$write("partial answer ")
    r$write("continues")
    r$reset_line()
    r$write(" next line")
    r$finish()
  })
  expect_identical(out, c("partial answer", "continues next line"))
})

test_that("console_print_text() prints a whole reply and skips empty text", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(utils::capture.output(console_print_text("Hello **there**")),
                   "Hello **there**")
  expect_identical(utils::capture.output(console_print_text(NA_character_)), character())
  expect_identical(utils::capture.output(console_print_text("")), character())
})

test_that("the spinner is silent when stdout is not a dynamic terminal", {
  withr::local_options(cli.dynamic = FALSE)
  sp = console_spinner()
  expect_identical(utils::capture.output({
    sp$tick()
    sp$clear()
  }), character())
})

test_that("the interrupt key follows the front end", {
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(console_interrupt_key(), "Esc")
  local_mocked_bindings(front_end = function() "terminal")
  expect_identical(console_interrupt_key(), "Ctrl-C")
})
