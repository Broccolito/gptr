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

# The rows a terminal shows for `bytes`: CR returns to the first column, LF ends a row
screen_rows = function(bytes) {
  rows = character()
  row = character()
  col = 1L
  for (ch in strsplit(bytes, "", fixed = TRUE)[[1L]]) {
    if (identical(ch, "\n")) {
      rows = c(rows, sub(" +$", "", paste(row, collapse = "")))
      row = character()
    }
    if (ch %in% c("\r", "\n")) {
      col = 1L
      next
    }
    row[[col]] = ch
    col = col + 1L
  }
  rows
}

# What each step of a stream writes, finish() last: a step is a delta for write() or a function
# of the renderer
render_writes = function(steps, width = 40L) {
  steps = c(as.list(steps), function(r) r$finish())
  out = character(length(steps))
  i = 0L
  local_mocked_bindings(console_cat = function(text) out[[i]] <<- paste0(out[[i]], text))
  r = render_markdown_stream(width)
  for (i in seq_along(steps)) if (is.function(steps[[i]])) steps[[i]](r) else r$write(steps[[i]])
  out
}

# Every construct of the renderer, nested lists, a fence indented under an item (D-187), a
# table, a rule and two languages (D-186)
render_rich = paste0(
  "# Title\n\n\nSome **bold** and `code` text that is long enough to wrap at forty columns.\r\n",
  "\r\n- outer *italic* item\n  - nested [a link](https://e.org/x)\n    - deeper\n1. numbered\n\n",
  "    ```r\n    x = 1\n      y\n    ```\n\n",
  "> a quote\n\n| term | estimate |\n|------|---------:|\n| (Intercept) | 37.29 |\n",
  "| wt | -5.34 |\n\n---\n\n```r\np = ggplot(mtcars, aes(wt, mpg)) +\n  geom_point()  # pts\n",
  "```\n```python\nx = 'a'  # comment 1\n```\nWide \u4e2d\u6587 chars.\n\n")

test_that("the output does not depend on chunking in the four console modes (acceptance 3)", {
  skip_on_cran()
  withr::local_seed(42)
  # highlighting decides per complete line; cli's parser is slow for 800 renders
  local_mocked_bindings(code_highlight = function(code, ...) code, .package = "cli")
  for (dynamic in c(FALSE, TRUE)) {
    for (colours in c(1L, 256L)) {
      withr::local_options(cli.num_colors = colours, cli.dynamic = dynamic, gptr.verbose = 2L)
      ref = render_chunks(render_rich)
      same = vapply(seq_len(200L), function(i) {
        identical(render_chunks(random_chunks(render_rich, sample.int(9L, 1L))), ref)
      }, NA)
      expect_true(all(same))
    }
  }
})

test_that("the transcript is written in whole rows, each at its line end or its wrap (D-245)", {
  skip_on_cran()
  withr::local_seed(45)
  local_mocked_bindings(code_highlight = function(code, ...) code, .package = "cli")
  for (dynamic in c(FALSE, TRUE)) {
    for (colours in c(1L, 256L)) {
      withr::local_options(cli.num_colors = colours, cli.dynamic = dynamic, gptr.verbose = 2L)
      ref = paste(render_writes(render_rich), collapse = "")
      for (i in seq_len(20L)) {
        out = render_writes(random_chunks(render_rich, 9L))
        expect_true(all(!nzchar(out) | endsWith(out, "\n")))
        expect_identical(paste(out, collapse = ""), ref)
      }
    }
  }
  # the wrap is at the width less the margin's four columns
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE)
  expect_identical(render_writes(c("Hello wor", "ld and ", "more\n", "alpha beta gamma delta ",
                                   "epsilon"), 24L),
                   c("", "", "  Hello world and more\n", "  alpha beta gamma\n", "",
                     "  delta epsilon\n"))
})

test_that("prose wraps at 100 columns at most, however wide the console (visual review)", {
  words = sprintf("word%02d", 1:40)
  for (dynamic in c(TRUE, FALSE)) {
    withr::local_options(cli.num_colors = 1L, cli.dynamic = dynamic, gptr.verbose = 2L)
    pad = if (dynamic) "  " else ""
    out = render_chunks(paste(words, collapse = " "), width = 140L)
    expect_identical(out[[1L]], paste0(pad, paste(words[1:14], collapse = " ")), info = pad)
    expect_true(all(nchar(out) <= 100L + nchar(pad)))
  }
})

test_that("plain contexts print exactly what they printed before the console layout (D-186)", {
  skip_on_cran()
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "display widths need a UTF-8 locale (report 18)")
  withr::local_options(cli.num_colors = 1L, gptr.verbose = 2L)
  before = c(
    "# Model summary", "", "The **linear model** explains most of",
    "the variance in `mpg`; the coefficient", "on `wt` is strongly negative, which",
    "means heavier cars travel fewer miles", "per gallon on average.", "",
    "- first bullet that is long enough to", "  need wrapping onto a second line at",
    "  forty columns", "- second bullet with **bold text**", "  inside", "1. numbered item", "",
    "> a quoted remark from the user", "", "```r", "fit = lm(mpg ~ wt, data = mtcars)",
    "summary(fit)$r.squared", "```", "Done: R\u00b2 = 0.75 \u2014 averaging wide chars",
    "\u4e2d\u6587\u5b57\u7b26 too.")
  # pipes and Jupyter; knitr, jsonl and tests (verbosity 0) and Rscript (verbosity 1)
  withr::with_options(list(cli.dynamic = FALSE),
                      expect_identical(render_chunks(render_sample), before))
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 0L)
  expect_identical(render_chunks(render_sample), before)
  withr::local_options(gptr.verbose = 1L)
  expect_identical(render_chunks(render_sample), before)
  expect_identical(render_chunks("\n\n# T\n\n- a\n  - b\n| a | bb |\n|---|---:|\n\n\nend\n\n"),
                   c("", "", "# T", "", "- a", "- b", "| a | bb |", "|---|---:|", "", "", "end",
                     ""))
})

test_that("an interactive console keeps a two-column margin at 40 columns (D-186)", {
  skip_on_cran()
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "display widths need a UTF-8 locale (report 18)")
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours, cli.dynamic = TRUE, gptr.verbose = 2L)
    out = screen_rows(paste0(cli::ansi_strip(render_chunks(render_rich, width = 40L)), "\n",
                             collapse = ""))
    expect_true(all(startsWith(out[nzchar(out)], "  ")))
    expect_true(all(nchar(out, type = "width") <= 38L))
    expect_false(any(grepl("^ +$", out)))
  }
  # NO_COLOR removes colours and styles only
  withr::local_envvar(NO_COLOR = "1")
  withr::local_options(cli.num_colors = NULL)
  out = render_chunks(render_rich, width = 40L)
  expect_identical(cli::ansi_strip(out), out)
  expect_true(all(startsWith(out[nzchar(out)], "  ")))
})

test_that("blank lines collapse and nested lists keep their indentation (D-186)", {
  skip_on_cran()
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE, gptr.verbose = 2L,
                       cli.unicode = FALSE)
  text = "\n\n# T\n\n\n- a\n  - b\n    - c\n1. x\n   - y\n\nend\n\n"
  expect_identical(render_chunks(text), c("  T", "", "  - a", "    - b", "      - c",
                                          "  1. x", "     - y", "", "  end"))
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "symbols need a UTF-8 locale")
  local_utf8_glyphs()
  # the same rows at every colour depth: without colour too the Markdown is read (visual review)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    expect_identical(cli::ansi_strip(render_chunks(text)),
                     c("  T", "", "  \u2022 a", "    \u25e6 b", "      \u25e6 c", "  1. x",
                       "     \u25e6 y", "", "  end"), info = paste(colours))
  }
})

test_that("a console shows the same text at any colour depth; only SGR differs (visual review)", {
  skip_on_cran()
  local_mocked_bindings(code_highlight = function(code, ...) code, .package = "cli")
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L)
  for (unicode in c(TRUE, FALSE)) {
    withr::local_options(cli.unicode = unicode, cli.num_colors = 256L)
    styled = cli::ansi_strip(render_chunks(render_rich))
    withr::local_options(cli.num_colors = 1L)
    expect_identical(render_chunks(render_rich), styled, info = paste(unicode))
  }
  withr::local_options(cli.num_colors = 1L)
  expect_identical(render_chunks("Use `mtcars` and **bold** *it* here."),
                   "  Use mtcars and bold it here.")
})

test_that("other output goes between whole rows; the held row continues, nesting kept (D-245)", {
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE, gptr.verbose = 2L)
  note = function(r) console_cat("(note)\n")
  expect_identical(render_writes(list("keeps streaming ", note, "slowly on.\n- a\n  ", note,
                                      "- b")),
                   c("", "(note)\n", "  keeps streaming slowly on.\n  - a\n", "(note)\n", "",
                     "    - b\n"))
})

test_that("pipe tables are aligned on an interactive console and stay valid Markdown (D-186)", {
  skip_on_cran()
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_chunks("| a | bb |\n|---|---:|\n| 1 | 2 |\n| 333 | 4 |\nafter")
    expect_identical(cli::ansi_strip(out), c("  | a   |  bb |", "  |-----|----:|",
                                             "  | 1   |   2 |", "  | 333 |   4 |", "  after"))
    for (bad in c("| a | b |\n| 1 | 2 |", "| a | b |\n|---|---|\n| 1 |",
                  "| aaaaaaaaaa | bbbbbbbbbb |\n|---|---|")) {
      expect_identical(cli::ansi_strip(render_chunks(bad, width = 24L)),
                       paste0("  ", strsplit(bad, "\n", fixed = TRUE)[[1L]]))
    }
  }
})

test_that("a pipe table too wide to align prints verbatim as its rows arrive (#43)", {
  skip_on_cran()
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE, gptr.verbose = 2L)
  genes = c("IL7R", "CCR7", "S100A4", "CD14", "LYZ", "MS4A1", "CD8A", "FCGR3A", "MS4A7", "GNLY",
            "NKG7", "FCER1A", "CST3", "PPBP")
  wide = c(paste("| Cluster |", paste(genes, collapse = " | "), "|"),
           paste0(strrep("|---", 15L), "|"), paste0("| ", 0:8, " | ", vapply(0:8, function(i) {
             paste(i + seq_along(genes) / 100, collapse = " | ")
           }, ""), " |"))
  stream = function(rows) {
    r = render_markdown_stream(80L)
    c(lapply(rows, function(x) utils::capture.output(r$write(paste0(x, "\n")))),
      list(utils::capture.output(r$finish())))
  }
  # the header waits for the delimiter row; from there each row prints when it ends
  seen = stream(wide)
  expect_identical(lengths(seen), c(0L, 2L, rep(1L, 9L), 0L))
  expect_identical(unlist(seen), paste0("  ", wide))
  # a table that fits is held to the end of its block and aligned
  expect_identical(stream(c("| a | bb |", "|---|---:|", "| 333 | 4 |")),
                   list(character(), character(), character(),
                        c("  | a   |  bb |", "  |-----|----:|", "  | 333 |   4 |")))
  withr::local_seed(43)
  text = paste0(paste0(wide, "\n", collapse = ""), "\nafter\n")
  ref = render_chunks(text, 80L)
  for (i in seq_len(50L)) expect_identical(render_chunks(random_chunks(text, 9L), 80L), ref)
})

test_that("italics, link URLs, quotes, rules and headings are styled only with colours", {
  skip_on_cran()
  withr::local_options(cli.num_colors = 256L, cli.dynamic = FALSE)
  text = "An *it* and [d](http://x.y) a * b 2*3"
  out = render_chunks(text, 80L)
  expect_identical(cli::ansi_strip(out), "An it and [d](http://x.y) a * b 2*3")
  expect_match(out, "An \033[0;3mit\033[0m and", fixed = TRUE)
  expect_match(out, "[d]\033[0;38;5;244m(http://x.y)\033[0m a * b 2*3", fixed = TRUE)
  expect_identical(render_chunks("> q"), "\033[38;5;244m> \033[39mq")
  expect_identical(render_chunks("a\n\n---\n\nb")[[3L]],
                   paste0("\033[38;5;244m", strrep("-", 40L), "\033[39m"))
  expect_identical(cli::ansi_strip(render_chunks("a\n\n---\n\nb")),
                   c("a", "", strrep("-", 40L), "", "b"))
  expect_identical(render_chunks("# One\n## Two"),
                   c("\033[0;1;4mOne\033[0m", "\033[0;1mTwo\033[0m"))
  # an asterisk that its own token does not close prints, as in plain mode
  for (x in c("a *glob* like *.csv and the *apply family.", "*two words* a*b *x")) {
    expect_identical(cli::ansi_strip(render_chunks(x, 80L)), sub("*glob*", "glob", x, fixed = TRUE))
  }
  withr::local_options(cli.num_colors = 1L)
  for (plain in c(text, "> q", "a\n\n---\n\nb", "# One\n## Two")) {
    expect_identical(render_chunks(plain, 80L), strsplit(plain, "\n", fixed = TRUE)[[1L]])
  }
})

test_that("R code is highlighted in the logo palette and other code is plain (D-245)", {
  skip_on_cran()
  withr::local_options(cli.dynamic = FALSE)
  code = c("f = function(x) if (x) \"s\" else NULL  # c", "y = mean(1L, na.rm = TRUE)")
  # reserved words red; strings, numbers and constants blue; calls bold; comments dim; the rest ink
  lit = function(red, blue, grey) {
    r = function(x) paste0("\033[", red, "m", x, "\033[39m")
    b = function(x) paste0("\033[", blue, "m", x, "\033[39m")
    c(paste0("f = ", r("function"), "(x) ", r("if"), " (x) ", b("\"s\""), " ", r("else"), " ",
             b("NULL"), "  ", grey),
      paste0("y = \033[1mmean\033[22m(", b("1L"), ", na.rm = ", b("TRUE"), ")"))
  }
  want = list(`16777216` = lit("38;2;184;84;80", "38;2;85;126;168",
                               "\033[38;2;135;135;135m# c\033[39m"),
              `256` = lit("38;5;167", "38;5;67", "\033[38;5;244m# c\033[39m"),
              `16` = lit("31", "34", "\033[2m# c\033[22m"), `1` = code)
  for (n in names(want)) {
    withr::local_options(cli.num_colors = as.integer(n))
    for (lang in c("r", "R", "{r, echo=FALSE}", "r title")) {
      out = render_chunks(paste0("```", lang, "\n", paste(code, collapse = "\n"), "\n```"), 80L)
      expect_identical(out[2:3], want[[n]], info = paste(n, lang))
    }
    expect_identical(console_call_line(list(name = "r", input = list(code = code)), 80L)[2:3],
                     paste0("    ", want[[n]]), info = n)
  }
  withr::local_options(cli.num_colors = 256L)
  # R that does not parse and other languages: ink between dim fences
  expect_identical(render_chunks("```r\np = g('b',\n```", 80L)[[2L]], "p = g('b',")
  for (lang in c("python", "json", "text", "")) {
    expect_identical(render_chunks(paste0("```", lang, "\nx = 'a'  # c 1\n```"), 80L),
                     c(paste0("\033[38;5;244m```", lang, "\033[39m"), "x = 'a'  # c 1",
                       "\033[38;5;244m```\033[39m"), info = lang)
  }
  # a user's cli.code_theme wins
  withr::local_options(cli.code_theme = list(reserved = "#00ff00"))
  expect_identical(render_chunks("```r\nfunction(x) 's'\n```", 80L)[[2L]],
                   "\033[38;5;46mfunction\033[39m(x) 's'")
})

test_that("highlighted R has no help links, as RStudio would add (visual review)", {
  withr::local_options(cli.num_colors = 256L, cli.hyperlink = TRUE, cli.hyperlink_help = TRUE)
  out = console_code("fit = lm(mpg ~ wt, data = fuel)", "r")
  expect_identical(out, "fit = \033[1mlm\033[22m(mpg ~ wt, data = fuel)")
})

test_that("a fenced line is written once, whole and highlighted, at its line end (D-245)", {
  skip_on_cran()
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L)
  long = "zz = c('a line longer than the row, never wrapped')"
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_writes(c("```r\nx = mean(", paste0("y)\n", long, "\n```\n")))
    expect_identical(cli::ansi_strip(out),
                     c("  ```r\n", paste0("  x = mean(y)\n  ", long, "\n  ```\n"), ""))
    expect_false(any(grepl("\r", out, fixed = TRUE)))
    if (colours > 1L) expect_match(out[[2L]], "  x = \033[1mmean\033[22m(y)\n", fixed = TRUE)
  }
})

test_that("a fenced line broken by other output is written once, after it (D-245)", {
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L, cli.num_colors = 256L)
  out = utils::capture.output({
    r = render_markdown_stream(60L)
    r$write("```python\nif x:\n    y = foo(")
    cat("  (a notice)\n")
    r$write("bar)\n```\n")
    r$finish()
  })
  expect_identical(cli::ansi_strip(out),
                   c("  ```python", "  if x:", "  (a notice)", "      y = foo(bar)", "  ```"))
})

test_that("prose lines respect the width and bullets hang (UTF-8 locale)", {
  skip_on_cran()
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
  skip_on_cran()
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

test_that("ordinary notices use stdout and actual errors use stderr", {
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output(console_notice("[gptr] ", "hello"), type = "message")
  })
  expect_identical(out, "[gptr] hello")
  expect_identical(err, character())
  out = utils::capture.output({
    err = utils::capture.output(console_notice("Error: failure", .error = TRUE),
                                type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "Error: failure")
})

test_that("console_print_text() prints a whole reply and skips empty text", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(utils::capture.output(console_print_text("Hello **there**")),
                   "Hello **there**")
  expect_identical(utils::capture.output(console_print_text(NA_character_)), character())
  expect_identical(utils::capture.output(console_print_text("")), character())
})

test_that("the interrupt key follows the front end", {
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(console_interrupt_key(), "Esc")
  # Ctrl-C reaches R in Positron's console (visual review)
  local_mocked_bindings(front_end = function() "positron")
  expect_identical(console_interrupt_key(), "Ctrl-C")
  local_mocked_bindings(front_end = function() "terminal")
  expect_identical(console_interrupt_key(), "Ctrl-C")
})

# ---------------------------------------------------------------- P28 Task 8: the style table

# The terminal background console_style() reads, set for the calling test only
local_background = function(value, .env = parent.frame()) {
  old = the$background
  the$background = value
  withr::defer(assign("background", old, envir = the), envir = .env)
}

test_that("console_style() holds the logo's cursor glyphs, ASCII where they may not show (D-245)", {
  utf8 = list(person = "\u203a", tool = "\u258e", agent = "\u258c", queued = "\u21b3",
              up = "\u2191", bullet = "\u2022", nested = "\u25e6", sep = " \u00b7 ",
              ellipsis = "\u2026")
  # ASCII's chevron is doubled, so an answer never reads as R's own prompt `> ` (visual review)
  ascii = list(person = ">>", tool = "|", agent = "#", queued = "->", up = "Up", bullet = "-",
               nested = "-", sep = " - ", ellipsis = "...")
  glyphs = function() console_style()[names(utf8)]
  local_mocked_bindings(is_windows = function() FALSE)
  withr::local_options(cli.unicode = TRUE)
  expect_identical(glyphs(), utf8)
  withr::local_options(cli.unicode = FALSE)
  expect_identical(glyphs(), ascii)
  # U+258E and U+21B3 are not in WGL4: Windows consoles outside Windows Terminal and RStudio
  withr::local_options(cli.unicode = TRUE)
  local_mocked_bindings(is_windows = function() TRUE, front_end = function() "rgui")
  withr::local_envvar(WT_SESSION = NA)
  expect_identical(glyphs(), ascii)
  withr::local_envvar(WT_SESSION = "8e2c")
  expect_identical(glyphs(), utf8)
  withr::local_envvar(WT_SESSION = NA)
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(glyphs(), utf8)
})

test_that("console_style() gives the logo accents by depth and the band by background (D-245)", {
  local_background(NULL)
  want = list(
    `16777216` = c("\033[38;2;184;84;80mx\033[39m", "\033[38;2;85;126;168mx\033[39m"),
    `256` = c("\033[38;5;167mx\033[39m", "\033[38;5;67mx\033[39m"),
    `16` = c("\033[31mx\033[39m", "\033[34mx\033[39m"),
    `1` = c("x", "x"))
  # the one grey: halfway between the logo's ink and cream where 256 colours show, else SGR 2
  grey = c(`16777216` = "\033[38;2;135;135;135mx\033[39m", `256` = "\033[38;5;244mx\033[39m",
           `16` = "\033[2mx\033[22m", `1` = "x")
  band = c(dark = "\033[48;5;237m", light = "\033[48;5;254m")
  for (n in names(want)) {
    withr::local_options(cli.num_colors = as.integer(n))
    dim = grey[[n]]
    for (bg in c("dark", "light", NA)) {
      the$background = bg
      st = console_style()
      expect_identical(c(st$red("x"), st$blue("x"), st$dim("x")), c(want[[n]], dim), info = n)
      expect_identical(st$band, if (n %in% c("16777216", "256") && !is.na(bg)) band[[bg]] else "",
                       info = paste(n, bg))
    }
  }
})

test_that("the background comes from COLORFGBG's last field, read once (D-245)", {
  local_background(NULL)
  fgbg = c("15;0", "0;15", "15;default;8", "0;7", "0;16", "default;default", "")
  want = c("dark", "light", "dark", "light", NA, NA, NA)
  for (i in seq_along(fgbg)) {
    the$background = NULL
    withr::local_envvar(COLORFGBG = fgbg[[i]])
    expect_identical(console_background(), want[[i]], info = fgbg[[i]])
  }
  withr::local_envvar(COLORFGBG = "0;15")
  expect_identical(console_background(), NA_character_)
})

test_that("NO_COLOR keeps the glyphs and drops every SGR (D-245)", {
  local_background("dark")
  withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL, cli.default_num_colors = 256L,
                       cli.unicode = TRUE)
  withr::local_envvar(NO_COLOR = NA, R_CLI_NUM_COLORS = NA)
  local_mocked_bindings(is_windows = function() FALSE)
  st = console_style()
  expect_identical(c(st$red("x"), st$band), c("\033[38;5;167mx\033[39m", "\033[48;5;237m"))
  withr::local_envvar(NO_COLOR = "1")
  st = console_style()
  expect_identical(c(st$tool, st$agent, st$red("x"), st$blue("x"), st$dim("x"), st$band),
                   c("\u258e", "\u258c", "x", "x", "x", ""))
})

test_that("no U+25CF dot and no Braille spinner anywhere in R/ (D-245)", {
  dir = arch_source_dir()
  skip_if(is.null(dir), "the package sources under R/ were not found")
  for (path in list.files(dir, pattern = "[.][Rr]$", full.names = TRUE)) {
    text = readLines(path, encoding = "UTF-8", warn = FALSE)
    expect_false(any(grepl("\\\\u(25[cC][fF]|28[0-9a-fA-F]{2})|[\u25cf\u2800-\u28ff]", text,
                           perl = TRUE)), info = basename(path))
  }
})

test_that("inline code in an answer takes the blue accent, not cli's cyan (D-245)", {
  text = "Use `mtcars` here."
  withr::local_options(cli.num_colors = 256L)
  expect_identical(render_chunks(text, width = 80L), "Use \033[0;38;5;67mmtcars\033[0m here.")
  withr::local_options(cli.num_colors = 16L)
  expect_identical(render_chunks(text, width = 80L), "Use \033[0;34mmtcars\033[0m here.")
  withr::local_options(cli.num_colors = 1L)
  expect_identical(render_chunks(text, width = 80L), text)
})

test_that("the console's one grey is the style table's dim (D-245)", {
  dir = arch_source_dir()
  skip_if(is.null(dir), "the package sources under R/ were not found")
  for (path in list.files(dir, pattern = "^console-.*[.][Rr]$", full.names = TRUE)) {
    text = readLines(path, encoding = "UTF-8", warn = FALSE)
    expect_false(any(grepl("col_grey|col_silver|make_ansi_style[(]\"grey", text)),
                 info = basename(path))
  }
})

# ---------------------------------------------------------------- P28 Task 11: tool kinds

test_that("tool calls are cursor strips tinted by kind (D-245)", {
  skip_on_cran()
  local_project()
  local_mocked_bindings(is_windows = function() FALSE)
  spec = function(name) tryCatch(registry_get("tool", name), error = function(e) NULL)
  kinds = c(read = "read", grep = "read", ls = "read", ask = "read", r = "act", edit = "act",
            write = "act", codex_shell = "act", mcp__github__search_issues = "act",
            codex_agent = "agent")
  expect_identical(vapply(names(kinds), function(n) console_tool_kind(n, spec(n)), ""), kinds)
  # a trusted MCP server's readOnlyHint arrives as read_only
  hint = gptr_spec("tool", "mcp__docs__search", description = "Search the docs.",
                   parameters = list(type = "object", properties = list()),
                   execute = function(input, ctx) "ok", annotations = list(readOnlyHint = TRUE))
  expect_identical(console_tool_kind(hint$name, hint), "read")
  calls = list(list(id = "c1", name = "read", input = list(path = "R/plot.R")),
               list(id = "c2", name = "r", input = list(code = "zz = 1")),
               list(id = "c3", name = "mcp__github__search_issues", input = list(q = "bug")),
               list(id = "c4", name = "codex_agent", input = json_obj()))
  fit = c(msg_tool_result("c2", "r", "", details = list(objects = list(added = "fit"))),
          list(elapsed = 1.2))
  diff = msg_tool_result("c5", "edit", "ok", details = list(
    diff = c("--- a/x.R", "+++ b/x.R", "@@ -1 +1 @@", "-a", "+b")))
  shown = function() {
    list(calls = vapply(calls, console_tool_line, "", width = 80L),
         results = c(console_tool_line(calls[[2L]], fit),
                     console_tool_line(list(name = "codex_shell"),
                                       list(is_error = FALSE, elapsed = 3)),
                     console_tool_line(list(name = "edit"), diff)),
         # a read shows no result line unless it fails
         read = console_tool_line(calls[[1L]], c(msg_tool_result("c1", "read", "text"),
                                                 list(elapsed = 3))),
         failed = console_tool_line(calls[[1L]], msg_tool_result("c1", "read", "no such file",
                                                                 is_error = TRUE)))
  }
  want = function(tool, agent, sep, red = identity, blue = identity, dim = identity,
                  bold = identity) {
    list(calls = c(paste0("  ", dim(paste0(tool, " read  R/plot.R"))),
                   paste0("  ", red(tool), " ", bold("r"), "  zz = ", blue("1")),
                   paste0("  ", red(tool), " ", bold("github/search_issues"), "  ",
                          dim("{\"q\":\"bug\"}")),
                   paste0("  ", blue(agent), " codex_agent")),
         results = c(dim(paste0("    + fit", sep, "1.2 s")), dim(paste0("    done", sep, "3.0 s")),
                     dim("    @@ -1 +1 @@"), red("    -a"), blue("    +b")),
         read = character(), failed = red("    error: no such file"))
  }
  sgr = function(on, off) function(x) paste0("\033[", on, "m", x, "\033[", off, "m")
  at256 = list(red = sgr("38;5;167", 39), blue = sgr("38;5;67", 39), dim = sgr("38;5;244", 39),
               bold = sgr(1, 22))
  withr::local_options(cli.unicode = TRUE, cli.num_colors = 256L)
  expect_identical(shown(), do.call(want, c(list("\u258e", "\u258c", " \u00b7 "), at256)))
  withr::local_options(cli.unicode = FALSE)
  expect_identical(shown(), do.call(want, c(list("|", "#", " - "), at256)))
  withr::local_options(cli.num_colors = NULL, crayon.enabled = NULL, cli.default_num_colors = 256L,
                       cli.unicode = TRUE)
  withr::local_envvar(NO_COLOR = "1", R_CLI_NUM_COLORS = NA)
  expect_identical(shown(), want("\u258e", "\u258c", " \u00b7 "))
  # a sub-agent's lines start with the agent's blue block, its model after its label, also from
  # the agent's r code, whose evaluation says 1 colour: the console's depth holds there
  withr::local_options(cli.num_colors = 256L)
  withr::local_envvar(NO_COLOR = NA)
  local_gptr_options(mode = "auto", verbose = 1L, quiet = FALSE)
  e = new.env()
  e$kid = local_fake_provider(function(request) "ok", name = "kid")
  code = "res = peter('each', list(a = 1), model = kid, parallel = 1)"
  lead = local_fake_provider(list(fake_tool("r", code = code), "done"), name = "lead")
  out = utils::capture.output(peter("fan out", model = lead, envir = e))
  block = paste0("  ", at256$blue("\u258c"), " sub-agent a ")
  kids = grep("sub-agent a ", out, value = TRUE, fixed = TRUE)
  expect_identical(kids[[1L]], paste0(block, "(kid/kid-1) started"))
  done = paste0(block, "done (1/1) \u00b7 1 turn \u00b7 ")
  expect_identical(substr(kids[[2L]], 1L, nchar(done)), done)
})

test_that("the ask tool's call line counts its questions in words (visual review)", {
  q = list(id = "fit", question = "Which fit?", options = list("lm", "loess"))
  expect_identical(console_preview(list(questions = list(q))), "1 question")
  expect_identical(console_preview(list(questions = list(q, q))), "2 questions")
})

test_that("a diff row wider than the console is cut, its spaces and sign kept (visual review)", {
  withr::local_options(cli.num_colors = 1L, cli.unicode = FALSE)
  row = "+     xlab = \"weight (1000 lb)\", ylab = \"miles per gallon\")"
  diff = msg_tool_result("c5", "edit", "ok", details = list(diff = c("@@ -1 +1,2 @@", " a", row)))
  out = console_tool_line(list(name = "edit"), diff, width = 40L)
  expect_identical(out, c("    @@ -1 +1,2 @@", "     a",
                          "    +     xlab = \"weight (1000 lb)\", ..."))
  # a row that fits keeps its last character beside one that is cut (cli 3.6.6's vectorised
  # ansi_strtrim() cut both)
  fits = paste0("+", strrep("a", 35L))
  diff = msg_tool_result("c6", "edit", "ok",
                         details = list(diff = c(fits, paste0("+", strrep("b", 50L)))))
  out = console_tool_line(list(name = "edit"), diff, width = 40L)
  expect_identical(out, c(paste0("    ", fits), paste0("    +", strrep("b", 32L), "...")))
})

# ---------------------------------------------------------------- Task 2: renderer hooks

# A real, idle session that never ran (its prompt waits in the queue): the hooks only read it
render_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

# Run events through the handlers that console_hooks() registers, capturing stdout
render_events = function(s, events) {
  hooks = console_hooks()
  types = vapply(hooks, function(h) h$event, "")
  ctx = session_live(s)$ctx
  utils::capture.output({
    for (ev in events) {
      for (h in hooks[types == ev$type]) h$handler(ev, ctx)
    }
  })
}

# Give the live session a run whose model is a CLI model (`type = "cli"`, D-192)
local_cli_run = function(s, .env = parent.frame()) {
  live = session_live(s)
  live$run = list(model = list(type = "cli"))
  withr::defer(assign("run", NULL, envir = live), envir = .env)
}

hook_event = function(type, s, ..., run = "u0000test") {
  ev_new(type, session = session_data(s)$id, run = run, ...)
}

assistant_msg = function(text) {
  msg_assistant(text, api = "fake", provider = "fake", model = "fake-1")
}

test_that("console_hooks() subscribes the events of contract 7.14", {
  events = vapply(console_hooks(), function(h) h$event, "")
  expect_true(all(c("message_update", "message_end", "tool_execution_start",
                    "tool_execution_end", "agent_end", "artifact_start") %in% events))
  expect_true(all(vapply(console_hooks(), function(h) inherits(h, "gptr_hook"), NA)))
})

test_that("a foreground run streams its answer and ends with a status line (verbosity 2)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Hello **wo"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "rld** {x}\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Hello")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L)))
  expect_identical(out, c("Hello **world** {x}", "  done - 0 requests - 0 tokens - $0.0000"))
  expect_null(console_record(list(run = "u0000test")))
})

test_that("nothing is printed at verbosity 0 or for a background session", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  s = render_session()
  events = list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "quiet"),
    hook_event("agent_end", s, status = "idle", usage = NULL, turns = 1L))
  local_gptr_options(verbose = 0L)
  expect_identical(render_events(s, events), character())
  local_gptr_options(verbose = 2L)
  live = session_live(s)
  live$background = list(id = "s-in-the-background")
  withr::defer({
    live$background = NULL
  })
  expect_identical(render_events(s, events), character())
})

test_that("a compaction during a foreground run prints one dim notice with its counts (D-202)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  session_append(s, list(type = "compaction", summary = "s", first_kept_entry_id = NULL,
                         tokens_before = 98200,
                         details = list(reason = "threshold", tokens_after = 4100),
                         usage = NULL, gptr = list(blocks = list(block_text("c")),
                                                   state = compact_state_empty(), n = 1L)))
  done = function(run = "u0000test") {
    hook_event("session_compact", s, strategy = "checkpoint", tokens_before = 98200,
               summary_tokens = 300, run = run)
  }
  expect_identical(render_events(s, list(hook_event("agent_start", s), done())),
                   "  conversation compacted: 98.2k -> 4.1k tokens")
  # /compact outside a run reports itself
  expect_identical(render_events(s, list(done(NULL))), character())
  testthat::local_reproducible_output(width = 80, crayon = TRUE, unicode = FALSE)
  expect_identical(render_events(s, list(done())),
                   "\033[2m  conversation compacted: 98.2k -> 4.1k tokens\033[22m")
})

test_that("an answer without deltas is printed whole at message_end", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("All at once."))))
  expect_identical(out, "All at once.")
})

test_that("whole replies join only text blocks with canonical line breaks", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  local_vault()
  s = render_session()
  withr::defer(console_drop("u0000test"))
  secret = paste0("synthetic-", strrep("FAKE", 8L), "-offline")
  secret_register(secret, "CONSOLE_BLOCK_SYNTHETIC", source = "test")
  left = substr(secret, 1L, 25L)
  right = substr(secret, 26L, nchar(secret))
  msg = assistant_msg(list(block_text(left), block_thinking("hidden"), block_text(right)))
  expect_identical(console_msg_text(msg), msg_text(msg))
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_events(s, list(
      hook_event("agent_start", s),
      hook_event("message_end", s, role = "assistant", message = msg)))
    expect_identical(cli::ansi_strip(out), c(left, right))
    expect_false(grepl(secret, paste(cli::ansi_strip(out), collapse = "\n"), fixed = TRUE))
  }
})

test_that("same-block chunks stay contiguous and tools follow the complete text tail", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "First "),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "ta"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "il"),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "1 + 1")),
    hook_event("message_update", s, index = 2L, kind = "text", delta = "Second ending"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("ignored"))))
  expect_identical(out, c("First tail", "  | r  1 + 1", "Second ending"))
})

test_that("tool lines escape the preview and summarise the result (acceptance 7)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  result = msg_tool_result("c1", "r", "ok", details = list(
    objects = list(added = c("x", "y"), modified = character(), removed = character()),
    plots = 0L))
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "x = 1 # \033[31mred\ny = 2")),
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 2.5, details = list()),
    hook_event("message_end", s, role = "tool_result", message = result)))
  expect_identical(out, c("  | r", "    x = 1 # <U+001B>[31mred", "    y = 2",
                          "    + x, y - 2.5 s"))
  expect_false(any(grepl("\033", out, fixed = TRUE)))
})

test_that("an error result shows the lines of its message", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  bad = msg_tool_result("c2", "r", "Error: object 'z' not found\nIn: z + 1", is_error = TRUE)
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c2", tool_name = "r",
               input = list(code = "z + 1")),
    hook_event("message_end", s, role = "tool_result", message = bad)))
  expect_identical(out[-1L], c("    error: Error: object 'z' not found", "    In: z + 1"))
})

test_that("result lines keep a failed call's objects, project paths and whole errors (#35)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 60, crayon = FALSE, unicode = FALSE)
  root = local_project()
  r = list(id = "c1", name = "r", input = list(code = "res = 1; stop('boom')"))
  bad = msg_tool_result("c1", "r", "Error: boom", is_error = TRUE, details = list(
    error = "boom", objects = list(added = "res", modified = character(), removed = character())))
  expect_identical(console_tool_line(r, bad), c("    error: boom", "    + res"))
  w = list(id = "c2", name = "write", input = list(path = "analysis.R"))
  wrote = msg_tool_result("c2", "write", "ok",
                          details = list(path = file.path(root, "analysis.R"), bytes = 5123L))
  expect_identical(console_tool_line(w, wrote), "    wrote analysis.R (5,123 bytes)")
  long = paste0(paste(rep("abcdefghi", 20L), collapse = " "), ".")
  out = console_tool_line(r, msg_tool_result("c3", "r", long, is_error = TRUE,
                                             details = list(error = long)))
  expect_gt(length(out), 1L)
  expect_true(all(startsWith(out, "    ") & cli::ansi_nchar(out, type = "width") <= 60L))
  expect_identical(paste(trimws(out), collapse = " "), paste("error:", long))
  eight = paste0("line ", 1:8, collapse = "\n")
  expect_identical(console_tool_line(r, msg_tool_result("c4", "r", eight, is_error = TRUE)),
                   c("    error: line 1", paste0("    line ", 2:6), "    ..."))
  huge = paste0("not found: ", paste0("GENE", 1:300, collapse = ", "))
  out = console_tool_line(r, msg_tool_result("c5", "r", huge, is_error = TRUE))
  expect_identical(c(length(out), out[[7L]]), c("7", "    ..."))
  inv = list(id = "c6", name = "inventory", input = list())
  odd = msg_tool_result("c6", "inventory", "3 objects",
                        details = list(objects = c("a", "b", "c"), plots = "two"))
  expect_identical(console_tool_line(inv, odd), character())
})

test_that("the end of a call served to a CLI route prints its result line (D-192)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "mcp_3", tool_name = "r",
               input = list(code = "mean(big_vector)")),
    hook_event("tool_execution_end", s, tool_call_id = "mcp_3", tool_name = "r", is_error = TRUE,
               elapsed = 0.1, details = list(),
               content = list(list(type = "text", text = "Error: object 'big_vector' not found"))),
    hook_event("tool_execution_start", s, tool_call_id = "mcp_4", tool_name = "r",
               input = list(code = "answer = 42")),
    hook_event("tool_execution_end", s, tool_call_id = "mcp_4", tool_name = "r", is_error = FALSE,
               elapsed = 0.1, details = list(objects = list(added = "answer"), plots = 0L),
               content = list(list(type = "text", text = ""))),
    hook_event("tool_execution_start", s, tool_call_id = "mcp_5", tool_name = "r",
               input = list(code = "res = 1; stop('boom')")),
    hook_event("tool_execution_end", s, tool_call_id = "mcp_5", tool_name = "r", is_error = TRUE,
               elapsed = 0.1, details = list(objects = list(added = "res"), plots = 0L),
               content = list(list(type = "text", text = "Error: boom")))))
  expect_identical(out, c("  | r  mean(big_vector)",
                          "    error: Error: object 'big_vector' not found",
                          "  | r  answer = 42", "    + answer",
                          "  | r  res = 1; stop('boom')", "    error: Error: boom", "    + res"))
})

test_that("on a CLI route verbosity 2 shows each thinking block's first line, dim (D-192)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  events = list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "thinking", delta = "\n**Plan"),
    hook_event("message_update", s, index = 1L, kind = "thinking",
               delta = "ning**\n\nThe body"),
    hook_event("message_update", s, index = 1L, kind = "thinking", delta = " stays hidden."),
    hook_event("message_update", s, index = 2L, kind = "thinking",
               delta = "step 2 is a line far longer than forty columns"),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "1 + 1")),
    hook_event("message_update", s, index = 3L, kind = "text", delta = "Done."),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Done.")))
  expect_identical(render_events(s, events), c("  | r  1 + 1", "Done."))
  local_cli_run(s)
  plain = c("  Planning", "  step 2 is a line far longer than fo...", "  | r  1 + 1", "Done.")
  expect_identical(render_events(s, events), plain)
  withr::local_options(cli.num_colors = 256L)
  out = render_events(s, events)
  expect_identical(cli::ansi_strip(out), plain)
  expect_true(all(startsWith(out[1:2], "\033[38;5;244m  ")))
  local_gptr_options(verbose = 1L)
  expect_identical(render_events(s, events[1:5]), character())
})

test_that("a thinking line cut at the width ends with an ellipsis", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 60, crayon = FALSE, unicode = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  local_cli_run(s)
  long = substr(strrep("a thinking line ", 13L), 1L, 200L)
  full = strrep("y", 58L)
  think = function(index, delta) {
    hook_event("message_update", s, index = index, kind = "thinking", delta = delta)
  }
  out = render_events(s, list(hook_event("agent_start", s), think(1L, long), think(2L, full),
                              think(2L, " goes on"), think(3L, paste0(full, "\n"))))
  expect_identical(out, c(paste0("  ", substr(long, 1L, 57L), "\u2026"),
                          paste0("  ", strrep("y", 57L), "\u2026"), paste0("  ", full)))
})

test_that("on a CLI route the live row keeps its clock around each thinking line (D-192)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  local_cli_run(s)
  ctx = session_live(s)$ctx
  withr::defer(console_drop("u0000test"))
  local_live_console()
  think = function(index, delta) {
    utils::capture.output(invisible(console_on_message_update(
      hook_event("message_update", s, index = index, kind = "thinking", delta = delta), ctx)))
  }
  utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_before_request(hook_event("before_request", s, provider = "fake",
                                         model = "fake/fake-1", request_id = "q1",
                                         tokens_est = 10), ctx)
  })
  rec = console_record(list(run = "u0000test"))
  # the row's clock reads 0s on any runner, however slow
  rec$t0 = Inf
  task = the$live_row$task
  t0 = rec$t0
  expect_identical(think(1L, "**Plan"), character())
  # padded, the row ends at the line's block, and comes back under it as the request still waits
  # (the session's queued prompt counts)
  expect_identical(sub(" +$", "", think(1L, "ning**\n\nThe body")),
                   c(paste0("\r", strrep(" ", 39L), "\r"), "  Planning",
                     "\r# thinking 0s - 1 queued - ctrl-c stop"))
  think(1L, " goes on.")
  think(2L, "a first line far longer than forty columns")
  expect_identical(the$live_row$task, task)
  expect_identical(rec$t0, t0)
  # nothing of a held thinking line is on screen when a prompt ends partial lines
  think(3L, "held")
  expect_no_error(utils::capture.output(console_before_message(kind = "prompt", tools = TRUE)))
  start = hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
                     input = list(code = "1"))
  utils::capture.output(console_on_tool_start(start, ctx))
  # a thinking line after a tool block opens its own block (D-186)
  expect_identical(think(4L, "after a tool line\n")[1:2], c("", "  after a tool line"))
  expect_false(is.null(the$live_row))
})

test_that("a tool's render() function replaces the default lines (IC-69)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  shout = gptr_spec("tool", "shout", description = "Shout a text.",
                    parameters = list(type = "object",
                                      properties = list(text = list(type = "string"))),
                    execute = function(input, ctx) "ok",
                    render = function(call, result, width) {
                      if (is.null(result)) paste("SHOUT", call$input$text) else "SHOUTED"
                    })
  off = gptr_register(shout)
  withr::defer(off())
  call = list(id = "c1", name = "shout", input = list(text = "hi\033"))
  expect_identical(console_tool_line(call), "SHOUT hi<U+001B>")
  expect_identical(console_tool_line(call, list(is_error = FALSE)), "SHOUTED")
})

test_that("artifact_start prints the NS-8 line (acceptance 7)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  ev = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
              version = 1L)
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(invisible(console_on_artifact_start(ev, NULL))),
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
  local_gptr_options(verbose = 1L, quiet = FALSE)
  expect_message(console_on_artifact_start(ev, NULL), class = "gptr_message_progress")
})

test_that("an artifact_start fired while a tool executes prints after tool_execution_end", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  st = console_state()
  st$artifacts = NULL
  withr::defer({
    st$artifacts = NULL
    console_drop("u0000test")
  })
  s = render_session()
  ctx = session_live(s)$ctx
  in_tool = structure(new.env(parent = emptyenv()), class = "gptr_run")
  art = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
               version = 1L)
  line = "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)"
  invisible(utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "a = peter$app()")),
                          ctx)
  }))
  # inside the model's r code (run_current() non-NULL; P09 captures this output): queued; a
  # nested tool call (peter$<tool>() in that code) ends while the r tool still runs
  inside = local({
    local_mocked_bindings(run_current = function() in_tool)
    utils::capture.output({
      console_on_artifact_start(art, ctx)
      invisible(console_on_tool_end(hook_event("tool_execution_end", s, tool_call_id = "n1",
                                               tool_name = "read", is_error = FALSE,
                                               elapsed = 0.1, details = list()), ctx))
    })
  })
  expect_identical(inside, character())
  expect_identical(console_state()$artifacts, line)
  after = utils::capture.output(invisible(console_on_tool_end(
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 0.2, details = list()), ctx)))
  expect_identical(after, line)
  expect_null(console_state()$artifacts)
})

test_that("a run's events while a tool executes print nothing (P09 captures that output)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  withr::defer(console_drop("u0000test"))
  # a nested peter$read() inside the model's r code
  local_mocked_bindings(run_current = function() structure(new.env(), class = "gptr_run"))
  start = hook_event("tool_execution_start", s, tool_call_id = "c1/1", tool_name = "read",
                     input = list(path = "a.txt"))
  end = hook_event("tool_execution_end", s, tool_call_id = "c1/1", tool_name = "read",
                   is_error = TRUE, elapsed = 0.1, details = list())
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(invisible(console_on_tool_start(start, ctx))),
                   character())
  local_gptr_options(verbose = 1L, quiet = FALSE)
  expect_no_message(console_on_tool_start(start, ctx))
  expect_no_message(console_on_tool_end(end, ctx))
})

test_that("verbosity 1 reports tool calls and the end as progress messages", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  expect_message(
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "dim(x)")), ctx),
    "gptr: r  dim(x)", fixed = TRUE)
  expect_message(
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 2L),
                         ctx),
    "gptr: done - 0 requests", fixed = TRUE)
})

test_that("a cut answer keeps what it received, the cut marked (visual review)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  cut = function(text, cut = TRUE) {
    utils::capture.output({
      r = render_markdown_stream(80L)
      r$write(text)
      r$finish(cut = cut)
    })
  }
  expect_identical(cut("Heavy cars are also the heaviest, so par"),
                   "Heavy cars are also the heaviest, so par...")
  expect_identical(cut("Heavy cars, so par", cut = FALSE), "Heavy cars, so par")
  expect_identical(cut("Heavy cars.\n"), "Heavy cars.")
  # an aborted run's answer ends so, an idle one whole
  local_gptr_options(verbose = 2L)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  ended = function(status) {
    render_events(s, list(hook_event("agent_start", s),
                          hook_event("message_update", s, index = 1L, kind = "text",
                                     delta = "Heavy cars, so par"),
                          hook_event("agent_end", s, status = status, usage = NULL)))[[1L]]
  }
  expect_identical(c(ended("aborted"), ended("idle")),
                   c("Heavy cars, so par...", "Heavy cars, so par"))
  # run_abort() ends the partial answer with stop_reason "aborted" before agent_end (visual review:
  # RStudio's abort showed `already` unmarked); a truncated or failed answer is cut too
  stopped = function(reason) {
    msg = assistant_msg("Heavy cars, so par")
    msg$stop_reason = reason
    render_events(s, list(hook_event("agent_start", s),
                          hook_event("message_update", s, index = 1L, kind = "text",
                                     delta = "Heavy cars, so par"),
                          hook_event("message_end", s, role = "assistant", message = msg)))[[1L]]
  }
  expect_identical(vapply(c("aborted", "error", "length", "stop"), stopped, ""),
                   c(aborted = "Heavy cars, so par...", error = "Heavy cars, so par...",
                     length = "Heavy cars, so par...", stop = "Heavy cars, so par"))
})

test_that("the status line names an unusual end and sums the usage rows", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  usage = data.frame(input = c(1000, 200), output = c(50, 10), cache_read = c(0, 900),
                     cost = c(0.001, 0.0005))
  expect_identical(console_status_line("idle", NULL, usage),
                   "  done - 2 requests - 2.2k tokens - $0.0015")
  expect_identical(console_status_line("aborted", "aborted (user)", NULL),
                   "  aborted: aborted (user) - 0 requests - 0 tokens - $0.0000")
  expect_identical(console_status_line("idle", NULL, data.frame(input = 999950)),
                   "  done - 1 request - 1.0M tokens - $0.0000")
  usage$cost[[2L]] = NA
  usage$output[[1L]] = NA
  expect_identical(console_status_line("idle", NULL, usage, c(0.5, NA)), paste(
    "  done - 2 requests - unknown tokens - $0.0010 + 1 request of unknown cost - sub-agents",
    "$0.5000 + 1 request of unknown cost"))
  usage$cost[[1L]] = NA
  expect_identical(console_status_line("idle", NULL, usage, NA_real_),
                   "  done - 2 requests - unknown tokens - unknown cost - sub-agents unknown cost")
})

test_that("the status line counts the run's requests and adds its sub-agents' cost (#38)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  s = render_session()
  d = session_data(s)
  d$turns = 5L
  ctx = session_live(s)$ctx
  row = function(id, sid, cost) {
    usage_conform(data.frame(request_id = id, session = sid, agent = "main", input = 100,
                             output = 10, cache_read = 0, cache_write_5m = 0,
                             cache_write_1h = 0, cost = cost, stringsAsFactors = FALSE))
  }
  end = function(own) {
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = own, turns = 5L),
                         ctx)
  }
  # an earlier run's sub-agent is not this run's
  usage_add(s, row("q-earlier", "s0000000001", 9))
  console_on_agent_start(hook_event("agent_start", s), ctx)
  fan = session_new(d$model, "auto", kind = "fanout", parent = s)
  kid = session_new(d$model, "auto", kind = "child", parent = fan)
  usage_add(kid, row("q-kid", session_data(kid)$id, 0.5))
  own = rbind(row("q1", d$id, 0.001), row("q2", d$id, 0.002))
  for (i in 1:2) usage_add(s, own[i, ])
  expect_message(end(own), "gptr: done - 2 requests - 220 tokens - $0.0030 - sub-agents $0.5000",
                 fixed = TRUE)
  console_on_agent_start(hook_event("agent_start", s), ctx)
  expect_message(end(own[1L, ]), "^gptr: done - 1 request - 110 tokens - \\$0\\.0010\\s*$")
})

test_that("custom entries of a run are shown through renderer records (IC-69)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  off = gptr_register(gptr_spec("renderer", "demo.note",
                                render = function(entry, width, ctx) {
                                  paste("NOTE:", entry$data$text)
                                }))
  withr::defer(off())
  s = render_session()
  ctx = session_live(s)$ctx
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    session_append(s, list(type = "custom", custom_type = "demo.note",
                           data = list(text = "kept \033 safe")))
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 0L),
                         ctx)
  })
  expect_identical(out[[1L]], "NOTE: kept <U+001B> safe")
})

test_that("the live row runs as a reactor task from a request to the run's end (D-243)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  local_live_console()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  utils::capture.output(console_on_before_request(
    hook_event("before_request", s, provider = "fake", model = "fake/fake-1", request_id = "q1",
               tokens_est = 10), ctx))
  row = the$live_row
  expect_true(exists(row$task, envir = reactor_get()$tasks, inherits = FALSE))
  for (delta in c("x", " y", "\n")) {
    utils::capture.output(console_on_message_update(
      hook_event("message_update", s, index = 1L, kind = "text", delta = delta), ctx))
    expect_identical(the$live_row, row)
    expect_true(row$shown)
  }
  utils::capture.output(console_on_agent_end(
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L), ctx))
  expect_null(the$live_row)
  expect_false(exists(row$task, envir = reactor_get()$tasks, inherits = FALSE))
})

test_that("the console UI prompts between whole rows; the held row waits (D-186, D-245)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  withr::defer(console_drop("u0000test"))
  req = list(tool = "r", input = list(code = "x = 1"), risk = list(level = 1L), tier = "ask")
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_message_update(hook_event("message_update", s, index = 1L, kind = "text",
                                         delta = "partial "), ctx)
    ans = ui_console_permission(req, read = function(...) "y")
  })
  expect_identical(out, c("  | r  x = 1", "  ? Allow r?", "    y yes - n no - ? more"))
  expect_identical(ans$decision, "allow")
  expect_false("permission_request" %in% vapply(console_hooks(), function(h) h$event, ""))
})

test_that("a prompt or pause in a tool's evaluation ends partial lines on the console (D-188)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  withr::defer(console_drop("u0000test"))
  home = new.env()
  # a sub-agent asks while the parent's r code runs (claude-cli: no tool line ended the text)
  home$tool = function(f) {
    .gptr_tool_run = structure(new.env(), class = "gptr_run")
    f()
  }
  home$ask = function() {
    ui_console_permission(list(tool = "r", input = list(code = "x = 1"), risk = list(level = 1L),
                               tier = "ask", agent = "a"), read = function(...) "y")
  }
  home$pause = console_render_pause
  text = function(res) paste(vapply(res$events, function(e) e$text %||% "", ""), collapse = "")
  res = NULL
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_message_update(hook_event("message_update", s, index = 1L, kind = "text",
                                         delta = "Fanning out HELDWORD"), ctx)
    res = eval_r("ans = tool(ask)", home, plots = "none", tee = FALSE)
  })
  # the held row continues after the prompt (D-186, D-245), never in the tool result
  expect_identical(out, c("  | r  x = 1", "  ? sub-agent a: allow r?", "    y yes - n no - ? more"))
  expect_identical(home$ans$decision, "allow")
  expect_false(grepl("HELDWORD|x = 1", text(res)))
  withr::local_options(cli.dynamic = TRUE)
  local_live_console()
  rec = console_record(list(run = "u0000test"))
  bytes = paste(utils::capture.output({
    console_live_start(rec)
    rec$last = "text"
    res = eval_r("tool(pause)", home, plots = "none", tee = FALSE)
  }), collapse = "\n")
  expect_match(bytes, "thinking", fixed = TRUE)
  # the abort's pause takes the live row down and ends the held row, the cut marked
  expect_match(bytes, "\r +\rFanning out HELDWORD\\.\\.\\.$")
  expect_null(the$live_row)
  expect_false(grepl("\r|HELDWORD", text(res)))
})

test_that("inside an evaluation the console margin follows the person's console (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  home = new.env()
  home$pad = console_pad
  prompts = character()
  home$pick = function() {
    ui_console_select("Which format?", c("Plot", "Table"), read = function(prompt, ...) {
      prompts <<- c(prompts, prompt)
      "1"
    })
  }
  out = utils::capture.output(eval_r("p = pad(); k = pick()", home, plots = "none", tee = FALSE))
  expect_identical(home$p, "  ")
  expect_identical(home$k, 1L)
  expect_identical(prompts, ">> ")
  expect_true("  ? Which format?" %in% out)
})

test_that("sub-agent lines need a child of a foreground root, verbosity 1+, no quiet (D-188)", {
  skip_on_cran()
  local_gptr_options(verbose = 1L, quiet = FALSE)
  s = render_session()
  root = structure(new.env(), class = "gptr_run")
  root$shell = s
  root$depth = 0L
  kid = structure(new.env(), class = "gptr_run")
  kid$depth = 1L
  kid$outer = root
  expect_true(console_child_shown(kid))
  expect_false(console_child_shown(root))
  expect_false(console_child_shown(NULL))
  live = session_live(s)
  live$background = list(id = "s-in-the-background")
  withr::defer({
    live$background = NULL
  })
  expect_false(console_child_shown(kid))
  live$background = NULL
  local_gptr_options(verbose = 0L)
  expect_false(console_child_shown(kid))
  local_gptr_options(verbose = 1L, quiet = TRUE)
  expect_false(console_child_shown(kid))
  # two columns, as the prompts, with or without the console margin, after the agent's block
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(console_child_line(list(child = list(label = "a")), "x")),
                   "  # sub-agent a x")
})

test_that("a failed sub-agent line counts it and gives its reason's first line, cut (#36)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_project()
  local_gptr_options(mode = "auto", verbose = 1L, quiet = FALSE)
  fake = local_fake_provider(list("never sent"))
  local_mocked_bindings(provider_credential = function(provider, register = TRUE) {
    gptr_abort(c(paste0("No credential found for provider ", provider$id, ". Set FAKE_API_KEY ",
                        "(for example with gptr_env()) or store one with gptr_login()."),
                 i = "a second line"), "no_key", provider = provider$id)
  })
  out = utils::capture.output(tryCatch(peter("each", list(a = 1, b = 2), model = fake,
                                             parallel = 1), error = function(e) NULL))
  failed = grep("failed", out, value = TRUE)
  expect_identical(failed[[1L]], paste0("  # sub-agent a failed (1/2): No credential found for ",
                                        "provider fake. Set FAKE..."))
  expect_match(failed[[2L]], "^  # sub-agent b failed \\(2/2\\): No credential found for")
  # without a reason, the status
  local_gptr_options(verbose = 0L)
  s = render_session()
  rec = console_track("u0000test", s)
  withr::defer(console_drop("u0000test"))
  rec$child = list(label = "c", run = list(started = Sys.time()))
  expect_identical(utils::capture.output(invisible(console_on_agent_end(
    hook_event("agent_end", s, status = "aborted", usage = NULL, turns = 1L),
    session_live(s)$ctx))), "  # sub-agent c failed: aborted")
})

test_that("a line routed at a question sits under it; a later person's line opens a block", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "terminal")
  s = render_session()
  withr::defer(console_drop("u0000test"))
  render_events(s, list(hook_event("agent_start", s)))
  rec = console_record(list(run = "u0000test"))
  # a line the question's read routes sits right under its rows
  rec$last = "prompt"
  expect_identical(utils::capture.output(console_queue_line(s, "use base R", "steer")),
                   queue_line("steer", "use base R"))
  # the steer delivered after the call the question approved, which printed only output (no
  # result line closed the block), opens its own block (visual review)
  rec$last = "prompt"
  took = render_events(s, list(hook_event("queue_update", s, op = "take", which = "steer",
                                          text = "use base R", source = "repl")))
  expect_identical(took, c("", ">> use base R"))
})

test_that("a foreground run separates text, tool and status blocks once (D-186, D-245)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  fe = "terminal"
  local_mocked_bindings(front_end = function() fe)
  s = render_session()
  withr::defer(console_drop("u0000test"))
  local_live_console()
  hooks = console_hooks()
  types = vapply(hooks, function(h) h$event, "")
  request = function(id) {
    hook_event("before_request", s, provider = "fake", model = "fake/fake-1", request_id = id,
               tokens_est = 10)
  }
  result = msg_tool_result("c1", "r", "ok", details = list(
    objects = list(added = "value", modified = character(), removed = character()), plots = 0L))
  events = list(
    hook_event("agent_start", s), request("q1"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "\n\nFirst "),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "tail\n\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("First tail")),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "1 + 1")),
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 0.1, details = list()),
    hook_event("message_end", s, role = "tool_result", message = result), request("q2"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Second ending\n\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Second ending")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L))
  # a launch boundary clears the shown live row, which its reactor task draws again; a notice
  # replaces it, and a padded row then waits for the next request
  tick = function() get(the$live_row$task, envir = reactor_get()$tasks)$fn()
  waits = list(
    hook_event("agent_start", s), request("q1"), function() console_before_message(kind = NULL),
    tick, function() {
      console_before_message()
      console_notice("[gptr] a notice")
    }, tick,
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Answer\n\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Answer")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L))
  # tool blocks of consecutive requests group as those of one response: the live row between them
  # is no block, and the text after the last one is spaced (D-245)
  call = function(id, code) {
    list(hook_event("message_end", s, role = "assistant", message = assistant_msg("")),
         hook_event("tool_execution_start", s, tool_call_id = id, tool_name = "r",
                    input = list(code = code)),
         hook_event("tool_execution_end", s, tool_call_id = id, tool_name = "r", is_error = FALSE,
                    elapsed = 0.1, details = list()),
         hook_event("message_end", s, role = "tool_result",
                    message = modifyList(result, list(tool_call_id = id))))
  }
  tools = c(list(hook_event("agent_start", s), request("q1")), call("c1", "1 + 1"),
            list(request("q2")), call("c2", "2 + 2"),
            list(request("q3"),
                 hook_event("message_update", s, index = 1L, kind = "text", delta = "Done\n\n"),
                 hook_event("message_end", s, role = "assistant", message = assistant_msg("Done")),
                 hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL,
                            doc = NULL, turns = 1L)))
  rows = list(c("", "  First tail", "", "  | r  1 + 1", "    + value", "", "  Second ending", "",
                "  done - 0 requests - 0 tokens - $0.0000", ""),
              c("", "  [gptr] a notice", "", "  Answer", "",
                "  done - 0 requests - 0 tokens - $0.0000", ""),
              c("", "  | r  1 + 1", "    + value", "  | r  2 + 2", "    + value", "", "  Done", "",
                "  done - 0 requests - 0 tokens - $0.0000", ""))
  # an R GUI spaces the blocks exactly as a terminal does
  for (fe in c("terminal", "rgui")) {
    for (i in 1:3) {
      con = rawConnection(raw(), "w")
      sink(con)
      tryCatch({
        for (ev in list(events, waits, tools)[[i]]) {
          if (is.function(ev)) {
            ev()
          } else {
            for (h in hooks[types == ev$type]) h$handler(ev, session_live(s)$ctx)
          }
        }
      }, finally = sink())
      bytes = rawToChar(rawConnectionValue(con))
      close(con)
      expect_match(bytes, "thinking", fixed = TRUE)
      # the live row takes no blank line before it, so a block that owes one writes it on the
      # cleared row, and a tool block after a tool block none
      expect_identical(lengths(regmatches(bytes, gregexpr("\r +\r\n", bytes))), c(2L, 1L, 2L)[[i]])
      expect_identical(screen_rows(bytes), rows[[i]], info = fe)
    }
  }
})

# ---------------------------------------------------------------- Task 7: end-to-end rendering

test_that("a streamed reply is printed verbatim and never evaluated (acceptance 3, rule C1)", {
  skip_on_cran()
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_envvar(GPTR_PWNED = NA)
  fake = gptr_fake_provider(list("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care."))
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter("hi", model = fake, envir = new.env()))
  })
  expect_true("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care." %in% out)
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_false(res$visible)
  expect_match(out[[length(out)]], "^  done - 1 request - ")
})

test_that("nothing is rendered at verbosity 0 (knitr, testthat)", {
  skip_on_cran()
  local_project()
  local_gptr_options(verbose = 0L, record = "off")
  out = utils::capture.output(invisible(peter("hi", model = gptr_fake_provider(list("quiet")),
                                             envir = new.env())))
  expect_false(any(grepl("quiet", out, fixed = TRUE)))
})

test_that("tool calls of a run show escaped previews and results (acceptance 7)", {
  skip_on_cran()
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1 # \033[31mred")),
                                 "done"))
  e = new.env(parent = globalenv())
  out = utils::capture.output(peter("go", model = fake, envir = e, mode = auto))
  expect_true("  | r  z = 1 # <U+001B>[31mred" %in% out)
  # the elapsed time follows when the call took a second or more (a first call on a slow runner)
  expect_match(out, "^    \\+ z( \\([0-9.]+ s\\))?$", all = FALSE)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_identical(e$z, 1)
})

test_that("artifact_start events print the NS-8 line through builtin:console (acceptance 7)", {
  local_gptr_options(verbose = 2L)
  out = utils::capture.output(invisible(ev_dispatch("artifact_start", ev_new(
    "artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827", version = 1L))))
  expect_identical(out,
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
})

# ---------------------------------------------------------------- Task 8: INFRA-27

# Rendering is decoupled from transport (INFRA-27, 03 section 2.2 rule 2): the JSONL transcript
# of one run does not depend on what the renderer prints.

# Fields that depend on time or on generated ids (contract 12.3 golden-event rule: ts, session,
# run, request_id; plus the other clocks, the prefix guard's view of the request and the r
# tool's checkpoint entry id)
infra27_volatile = c("ts", "timestamp", "session", "run", "request_id", "requestId", "elapsed",
                     "started", "seconds", "view", "response_id", "responseId", "checkpoint")

infra27_norm_value = function(x) {
  if (is.list(x)) {
    nms = names(x)
    if (!is.null(nms)) x = x[!(nms %in% infra27_volatile)]
    return(lapply(x, infra27_norm_value))
  }
  if (is.character(x)) {
    x = gsub("\\bs[0-9a-f]{10}\\b", "<session>", x, perl = TRUE)
    x = gsub("\\bu[0-9a-f]{8}\\b", "<run>", x, perl = TRUE)
    x = gsub("\\bq[0-9a-f]{12}\\b", "<request>", x, perl = TRUE)
  }
  x
}

infra27_normalise = function(lines) {
  vapply(lines, function(l) json_encode(infra27_norm_value(json_decode(l))), "",
         USE.NAMES = FALSE)
}

# One fake-provider run (an `r` call, then an answer) streamed to a JSONL file at `verbose`,
# with whatever the renderer prints captured and discarded; the free RAM in <environment> is fixed
infra27_run = function(verbose) {
  local_gptr_options(verbose = verbose, quiet = TRUE, record = "off")
  local_mocked_bindings(context_r_line = function() "R")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1")),
                                 "The answer is 42."))
  s = peter("compute", model = fake, .run = FALSE, envir = new.env(parent = globalenv()),
           mode = "auto")
  file = tempfile(fileext = ".jsonl")
  on.exit(unlink(file), add = TRUE)
  con = file(file, open = "wb")
  off = jsonl_sink(s, con)
  utils::capture.output(gptr_step(s, turns = Inf))
  off()
  close(con)
  readLines(file, encoding = "UTF-8", warn = FALSE)
}

test_that("the transcript is the same at verbosity 0, 1 and 2 (INFRA-27, acceptance 4)", {
  skip_on_cran()
  local_project()
  v0 = infra27_normalise(infra27_run(0L))
  v1 = infra27_normalise(infra27_run(1L))
  v2 = infra27_normalise(infra27_run(2L))
  expect_gt(length(v0), 10L)
  expect_identical(v1, v0)
  expect_identical(v2, v0)
})
