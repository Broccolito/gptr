# The live row (it replaced the spinner, D-243) stays on one row at the console's current width.
live_draw = function(state = list(what = "thinking", secs = 0, key = "Ctrl-C")) {
  row = console_live("L")
  c(written(function() row$draw(state)), written(row$clear))
}

test_that("a padded live row fills and erases the current row at narrow widths", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L)
  local_mocked_bindings(front_end = function() "rgui")
  for (width in c(20L, 32L, 80L)) {
    withr::local_options(cli.width = width)
    out = live_draw()
    expect_true(startsWith(out[[1L]], "\r# "))
    expect_identical(nchar(sub("^\r", "", out[[1L]]), type = "width"), width - 1L)
    expect_false(grepl("[\n\033]", out[[1L]]))
    expect_identical(out[[2L]], paste0("\r", strrep(" ", width - 1L), "\r"))
  }
})

test_that("live row redraws follow a shrinking and expanding console", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L)
  local_mocked_bindings(front_end = function() "rgui")
  for (width in c(80L, 20L, 80L)) {
    withr::local_options(cli.width = width)
    expect_identical(nchar(sub("^\r", "", live_draw()[[1L]]), type = "width"), width - 1L)
  }
})

test_that("the live row's words are those of the old waiting row's place, in lower case (D-243)", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
                       cli.width = 80L)
  local_mocked_bindings(front_end = function() "rgui")
  out = sub(" +$", "", live_draw(list(what = "thinking", secs = 12, key = "Esc"))[[1L]])
  expect_identical(out, "\r# thinking 12s - esc stops")
  expect_false(grepl("Ctrl-C to|\\(", out))
})

test_that("an ANSI terminal erases to the line end and keeps the cursor after the row (D-186)", {
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.unicode = FALSE,
                       cli.num_colors = 1L, cli.width = 80L)
  local_mocked_bindings(front_end = function() "terminal")
  out = live_draw(list(what = "thinking", secs = 3, key = "Ctrl-C", pause = TRUE))
  expect_identical(out, c("\r# thinking 3s - ctrl-c pauses\033[K", "\r\033[K"))
})

test_that("a console too narrow for the block and the time gets an empty row", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
                       cli.width = 1L)
  local_mocked_bindings(front_end = function() "rgui")
  expect_identical(live_draw(), c("\r", "\r\r"))
})

test_that("the live row's fit counts display columns of styled and wide characters", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = TRUE, cli.num_colors = 8L,
                       cli.width = 20L)
  local_mocked_bindings(front_end = function() "rgui")
  out = live_draw(list(secs = 0, draft = "读取 数据"))
  expect_false(grepl("\n", out[[1L]], fixed = TRUE))
  expect_identical(cli::ansi_nchar(sub("^\r", "", out[[1L]]), type = "width"), 19L)
  expect_true(grepl("数据", cli::ansi_strip(out[[1L]]), fixed = TRUE))
  expect_identical(out[[2L]], paste0("\r", strrep(" ", 19L), "\r"))
})
