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
  local_mocked_bindings(code_highlight = function(code) code, .package = "cli")
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
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE, gptr.verbose = 2L)
  text = "\n\n# T\n\n\n- a\n  - b\n    - c\n1. x\n   - y\n\nend\n\n"
  expect_identical(render_chunks(text), c("  # T", "", "  - a", "    - b", "      - c",
                                          "  1. x", "     - y", "", "  end"))
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "symbols need a UTF-8 locale")
  withr::local_options(cli.num_colors = 256L, cli.unicode = TRUE)
  expect_identical(cli::ansi_strip(render_chunks(text)),
                   c("  T", "", "  \u2022 a", "    \u25e6 b", "      \u25e6 c", "  1. x",
                     "     \u25e6 y", "", "  end"))
})

test_that("a line ended by other output continues at the margin, nesting kept (D-186)", {
  withr::local_options(cli.num_colors = 1L, cli.dynamic = TRUE, gptr.verbose = 2L)
  out = utils::capture.output({
    r = render_markdown_stream(40L)
    r$write("keeps streaming ")
    r$reset_line()
    r$write("slowly on.\n- a\n  ")
    r$reset_line()
    r$write("- b")
    r$finish()
  })
  expect_identical(out, c("  keeps streaming", "  slowly on.", "  - a", "    - b"))
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
  expect_match(out, "[d]\033[0;2m(http://x.y)\033[0m a * b 2*3", fixed = TRUE)
  expect_identical(render_chunks("> q"), "\033[2m> \033[22mq")
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

test_that("complete R lines use cli's highlighter and other code a light one (D-186)", {
  skip_on_cran()
  withr::local_options(cli.num_colors = 256L, cli.dynamic = FALSE)
  whole = "x = f(1, 'a')"
  expect_false(identical(as.character(cli::code_highlight(whole)), whole))
  for (lang in c("r", "R", "{r, echo=FALSE}", "r title")) {
    out = render_chunks(paste0("```", lang, "\n", whole, "\np = g('b',\n```"), 80L)
    expect_match(out[[2L]], cli::code_highlight(whole), fixed = TRUE)
    expect_match(out[[3L]], code_light("p = g('b',", "r"), fixed = TRUE)
    expect_match(out[[3L]], "\033\\[[0-9;]+m'b'")
  }
  py = render_chunks("```python\nx = 'a'  # c 1\n```", 80L)[[2L]]
  expect_match(py, "\033\\[[0-9;]+m'a'")
  expect_match(py, "\033\\[[0-9;]+m# c 1")
  expect_identical(cli::ansi_strip(py), "x = 'a'  # c 1")
  expect_match(render_chunks("```json\n{\"a\": 1}\n```", 80L)[[2L]],
               "\033\\[[0-9;]+m\"a\".*\033\\[[0-9;]+m1")
  expect_identical(render_chunks("```text\n'a' 1\n```", 80L)[[2L]], "'a' 1")
})

test_that("fenced lines stream as they arrive and a line that fits is redrawn (D-187)", {
  skip_on_cran()
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L)
  long = "zz = c('a line too long to be redrawn')"
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    con = rawConnection(raw(), "w")
    sink(con)
    tryCatch({
      r = render_markdown_stream(40L)
      r$write("```r\nx = mean(")
      partial = rawToChar(rawConnectionValue(con))
      r$write(paste0("y)\n", long, "\n\tif (a) b\n```\n"))
      r$finish()
    }, finally = sink())
    bytes = rawToChar(rawConnectionValue(con))
    close(con)
    expect_identical(cli::ansi_strip(partial), "  ```r\n  x = mean(")
    expect_identical(screen_rows(cli::ansi_strip(bytes)),
                     c("  ```r", "  x = mean(y)", paste0("  ", long), "  \tif (a) b", "  ```"))
    expect_false(grepl(paste0("\r  ", long), bytes, fixed = TRUE))
    # a TAB has no display width in nchar(), so a line holding one is never redrawn
    expect_false(grepl("\tif (a) b\r", bytes, fixed = TRUE))
    if (colours == 1L) {
      expect_false(grepl("\r", bytes, fixed = TRUE))
    } else {
      expect_match(bytes, paste0("x = mean(y)\r  ", cli::code_highlight("x = mean(y)"), "\n"),
                   fixed = TRUE)
    }
  }
})

test_that("a fenced line broken by other output is shown whole after it (D-187)", {
  withr::local_options(cli.dynamic = TRUE, gptr.verbose = 2L, cli.num_colors = 256L)
  out = utils::capture.output({
    r = render_markdown_stream(60L)
    r$write("```python\nif x:\n    y = foo(")
    r$reset_line()
    cat("  (a notice)\n")
    r$write("bar)\n```\n")
    r$finish()
  })
  expect_identical(screen_rows(paste0(cli::ansi_strip(out), "\n", collapse = "")),
                   c("  ```python", "  if x:", "      y = foo(", "  (a notice)",
                     "      y = foo(bar)", "  ```"))
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
  expect_identical(out, c("Hello **world** {x}", "  done | 0 requests | 0 tokens | $0.0000"))
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
                   as.character(cli::col_grey("  conversation compacted: 98.2k -> 4.1k tokens")))
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
  expect_identical(out, c("First tail", "  * r  1 + 1", "Second ending"))
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
  expect_identical(out, c("  * r", "```r", "x = 1 # <U+001B>[31mred", "y = 2", "```",
                          "    + x, y (2.5 s)"))
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
  expect_identical(out, c("  * r  mean(big_vector)",
                          "    error: Error: object 'big_vector' not found",
                          "  * r  answer = 42", "    + answer",
                          "  * r  res = 1; stop('boom')", "    error: Error: boom", "    + res"))
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
  expect_identical(render_events(s, events), c("  * r  1 + 1", "Done."))
  local_cli_run(s)
  plain = c("  Planning", "  step 2 is a line far longer than fo...", "  * r  1 + 1", "Done.")
  expect_identical(render_events(s, events), plain)
  withr::local_options(cli.num_colors = 256L)
  out = render_events(s, events)
  expect_identical(cli::ansi_strip(out), plain)
  expect_true(all(grepl("\033[90m", out[1:2], fixed = TRUE)))
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

test_that("on a CLI route the waiting row keeps its clock around each thinking line (D-192)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  local_cli_run(s)
  ctx = session_live(s)$ctx
  withr::defer(console_drop("u0000test"))
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
  task = rec$task
  t0 = rec$spinner$t0
  expect_identical(think(1L, "**Plan"), character())
  expect_identical(think(1L, "ning**\n\nThe body"), paste0("\r", strrep(" ", 39L), "\r  Planning"))
  think(1L, " goes on.")
  think(2L, "a first line far longer than forty columns")
  expect_identical(rec$task, task)
  expect_identical(rec$spinner$t0, t0)
  # nothing of a held thinking line is on screen when a prompt ends partial lines
  think(3L, "held")
  expect_no_error(utils::capture.output(console_before_message(kind = "prompt", tools = TRUE)))
  start = hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
                     input = list(code = "1"))
  utils::capture.output(console_on_tool_start(start, ctx))
  # a thinking line after a tool block opens its own block (D-186)
  expect_identical(think(4L, "after a tool line\n")[1:2], c("", "  after a tool line"))
  expect_false(is.null(rec$task))
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
    "gptr: done | 0 requests", fixed = TRUE)
})

test_that("the status line names an unusual end and sums the usage rows", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  usage = data.frame(input = c(1000, 200), output = c(50, 10), cache_read = c(0, 900),
                     cost = c(0.001, 0.0005))
  expect_identical(console_status_line("idle", NULL, usage),
                   "  done | 2 requests | 2.2k tokens | $0.0015")
  expect_identical(console_status_line("aborted", "aborted (user)", NULL),
                   "  aborted: aborted (user) | 0 requests | 0 tokens | $0.0000")
  expect_identical(console_status_line("idle", NULL, data.frame(input = 999950)),
                   "  done | 1 request | 1.0M tokens | $0.0000")
  usage$cost[[2L]] = NA
  usage$output[[1L]] = NA
  expect_identical(console_status_line("idle", NULL, usage, c(0.5, NA)), paste(
    "  done | 2 requests | unknown tokens | $0.0010 + 1 request of unknown cost | sub-agents",
    "$0.5000 + 1 request of unknown cost"))
  usage$cost[[1L]] = NA
  expect_identical(console_status_line("idle", NULL, usage, NA_real_),
                   "  done | 2 requests | unknown tokens | unknown cost | sub-agents unknown cost")
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
  expect_message(end(own), "gptr: done | 2 requests | 220 tokens | $0.0030 | sub-agents $0.5000",
                 fixed = TRUE)
  console_on_agent_start(hook_event("agent_start", s), ctx)
  expect_message(end(own[1L, ]), "^gptr: done \\| 1 request \\| 110 tokens \\| \\$0\\.0010\\s*$")
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

test_that("the spinner runs as a reactor task until the first rendered text", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  rec = console_record(list(run = "u0000test"))
  console_on_before_request(hook_event("before_request", s, provider = "fake",
                                       model = "fake/fake-1", request_id = "q1",
                                       tokens_est = 10), ctx)
  expect_false(is.null(rec$task))
  utils::capture.output(console_on_message_update(
    hook_event("message_update", s, index = 1L, kind = "text", delta = "x"), ctx))
  expect_false(is.null(rec$task))
  expect_false(is.null(rec$spinner))
  utils::capture.output(console_on_message_update(
    hook_event("message_update", s, index = 1L, kind = "text", delta = " "), ctx))
  expect_null(rec$task)
  expect_null(rec$spinner)
  console_drop("u0000test")
})

test_that("the console UI ends a partial answer line before it prompts (D-186)", {
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
  expect_identical(out, c("partial", "  r  x = 1"))
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
  # the held word continues after the prompt (D-186), never in the tool result
  expect_identical(out, c("Fanning out", "  sub-agent a > r  x = 1"))
  expect_identical(home$ans$decision, "allow")
  expect_false(grepl("HELDWORD|x = 1", text(res)))
  withr::local_options(cli.dynamic = TRUE)
  rec = console_record(list(run = "u0000test"))
  bytes = paste(utils::capture.output({
    rec$spinner = console_spinner()
    rec$last = "wait"
    rec$spinner$tick()
    res = eval_r("tool(pause)", home, plots = "none", tee = FALSE)
  }), collapse = "\n")
  expect_match(bytes, "thinking", fixed = TRUE)
  expect_match(bytes, "\r +\rHELDWORD$")
  expect_null(rec$spinner)
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
  expect_identical(prompts, "  Choose (a number): ")
  expect_true("  Which format?" %in% out)
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
  # two columns, as the prompts, with or without the console margin
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(console_child_line(list(child = list(label = "a")), "x")),
                   "  sub-agent a x")
})

test_that("a failed sub-agent line counts it and gives its reason's first line, cut (#36)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  # made before the key is mocked away: the gateway checks it before a call changes anything
  s = render_session()
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
  expect_identical(failed[[1L]], paste0("  sub-agent a failed (1/2): No credential found for ",
                                        "provider fake. Set FAKE_A..."))
  expect_match(failed[[2L]], "^  sub-agent b failed \\(2/2\\): No credential found for")
  # without a reason, the status
  local_gptr_options(verbose = 0L)
  rec = console_track("u0000test", s)
  withr::defer(console_drop("u0000test"))
  rec$child = list(label = "c", run = list(started = Sys.time()))
  expect_identical(utils::capture.output(invisible(console_on_agent_end(
    hook_event("agent_end", s, status = "aborted", usage = NULL, turns = 1L),
    session_live(s)$ctx))), "  sub-agent c failed: aborted")
})

test_that("a foreground run separates text, tool and status blocks once (D-186)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  fe = "terminal"
  local_mocked_bindings(front_end = function() fe)
  s = render_session()
  withr::defer(console_drop("u0000test"))
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
  # a launch boundary and a notice replacing a shown waiting row, which then resumes as the
  # reactor task draws it
  rec = function() console_record(list(run = "u0000test"))
  tick = function() {
    sp = rec()$spinner
    sp$last = 0
    sp$tick()
  }
  waits = list(
    hook_event("agent_start", s), request("q1"), function() console_before_message(kind = NULL),
    tick, function() {
      console_before_message()
      console_notice("[gptr] a notice")
    }, function() {
      console_gap(rec(), "wait")
      tick()
    },
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Answer\n\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Answer")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L))
  rows = list(c("", "  First tail", "", "  * r  1 + 1", "    + value", "", "  Second ending", "",
                "  done | 0 requests | 0 tokens | $0.0000", ""),
              c("", "  [gptr] a notice", "", "  Answer", "",
                "  done | 0 requests | 0 tokens | $0.0000", ""))
  # an R GUI spaces the blocks exactly as a terminal does
  for (fe in c("terminal", "rgui")) {
    for (i in 1:2) {
      con = rawConnection(raw(), "w")
      sink(con)
      tryCatch({
        for (ev in list(events, waits)[[i]]) {
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
      expect_false(grepl("\r +\r\n", bytes))
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
  expect_match(out[[length(out)]], "^  done \\| 1 request \\| ")
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
  expect_true("  * r  z = 1 # <U+001B>[31mred" %in% out)
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
