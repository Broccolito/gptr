# A carriage-return spinner must stay on one row at the current native width.
spinner_tick_output = function(sp) {
  sp$last = 0
  utils::capture.output(invisible(sp$tick()))
}

test_that("dynamic spinner frames fit and erase the current row at narrow widths", {
  skip_on_cran()
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L)
  local_mocked_bindings(front_end = function() "terminal")
  sp = console_spinner()
  for (width in c(20L, 32L, 80L)) {
    withr::local_options(cli.width = width)
    out = spinner_tick_output(sp)
    expect_length(out, 1L)
    expect_true(startsWith(out, "\r"))
    expect_identical(nchar(sub("^\r", "", out), type = "width"), width - 1L)
    expect_false(grepl("[\n\033]", out))
    expect_identical(utils::capture.output(invisible(sp$clear())),
      paste0("\r", strrep(" ", width - 1L), "\r"))
  }
})

test_that("spinner redraws follow shrinking and expanding native width", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L)
  local_mocked_bindings(front_end = function() "terminal")
  sp = console_spinner()
  for (width in c(80L, 20L, 80L)) {
    withr::local_options(cli.width = width)
    out = spinner_tick_output(sp)
    expect_identical(nchar(sub("^\r", "", out), type = "width"), width - 1L)
  }
})

test_that("wide spinner text and its stop hint retain the original appearance", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
    cli.width = 80L)
  local_mocked_bindings(front_end = function() "terminal")
  sp = console_spinner()
  expected = sprintf("\r%s thinking (0s, Ctrl-C to %s)", console_symbols()$frames[[1L]],
    if (console_menu_available()) "steer or stop" else "stop")
  out = sub(" +$", "", spinner_tick_output(sp))
  out = sub("\\([0-9]+s,", "(0s,", out)
  expect_identical(out, expected)
})

test_that("an ANSI terminal erases to the line end and keeps the cursor after the text (D-186)", {
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.unicode = FALSE,
    cli.num_colors = 1L, cli.width = 80L, gptr.verbose = 2L)
  local_mocked_bindings(front_end = function() "terminal")
  sp = console_spinner()
  out = spinner_tick_output(sp)
  expect_match(out, "^\r  [-\\\\|/] thinking \\([0-9]+s, Ctrl-C to [a-z ]+\\)\033\\[K$")
  expect_identical(utils::capture.output(invisible(sp$clear())), "\r\033[K")
})

test_that("spinner fits a one-column row without wrapping or introducing escape codes", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
    cli.width = 1L)
  sp = console_spinner()
  expect_identical(spinner_tick_output(sp), "\r")
  expect_identical(utils::capture.output(invisible(sp$clear())), "\r\r")
})

test_that("spinner fitting counts display columns for styled and wide characters", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = TRUE, cli.num_colors = 8L,
    cli.width = 20L)
  sp = console_spinner(label = cli::col_blue("\u8bfb\u53d6 \u6570\u636e"))
  out = spinner_tick_output(sp)
  expect_length(out, 1L)
  expect_identical(cli::ansi_nchar(sub("^\r", "", out), type = "width"), 19L)
  retained = if (isTRUE(l10n_info()[["UTF-8"]])) "\u8bfb\u53d6" else enc2native("\u8bfb")
  expect_true(grepl(retained, cli::ansi_strip(out), fixed = TRUE))
  expect_identical(utils::capture.output(invisible(sp$clear())),
    paste0("\r", strrep(" ", 19L), "\r"))
})
