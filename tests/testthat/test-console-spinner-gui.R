# The live row (it replaced the spinner, D-243) is drawn with carriage returns only, in R GUIs
# too, so no line feed is left behind it; an R GUI pads it where it cannot erase to the line end.
test_that("dynamic front ends, R GUIs too, draw and clear the live row without a line feed", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
                       cli.width = 40L)
  state = list(what = "thinking", secs = 3, key = "Esc", pause = FALSE)
  for (frontend in c("rgui", "terminal", "vscode", "rstudio", "positron", "unknown")) {
    local_mocked_bindings(front_end = function() frontend)
    row = console_live("L")
    drawn = written(function() row$draw(state))
    expect_true(startsWith(drawn, "\r# thinking 3s - esc stop"), info = frontend)
    cleared = written(row$clear)
    expect_true(startsWith(cleared, "\r"), info = frontend)
    expect_false(grepl("\n", paste0(drawn, cleared), fixed = TRUE), info = frontend)
    # where \033[K does not end the line (cli.ansi is off) the row and its clear are padded
    padded = frontend != "rstudio"
    expect_identical(endsWith(drawn, "\033[K"), !padded, info = frontend)
    expect_identical(nchar(cleared), if (padded) 41L else 4L, info = frontend)
  }
})

test_that("a terminal's live row is on the input band where the background is known (D-243)", {
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE, cli.unicode = FALSE,
                       cli.num_colors = 256L, cli.width = 40L)
  local_mocked_bindings(front_end = function() "terminal")
  state = list(what = "r", secs = 1, key = "Ctrl-C", pause = TRUE)
  local_mocked_bindings(console_background = function() "light")
  expect_identical(written(function() console_live("T")$draw(state)),
                   paste0("\r\033[48;5;254m", console_live_row(c(state, band = TRUE), 40L),
                          "\033[K\033[0m"))
  # an IDE console has no band; nor has a terminal whose background is unknown
  expect_identical(written(function() console_live("L")$draw(state)),
                   paste0("\r", console_live_row(state, 40L), "\033[K"))
  local_mocked_bindings(console_background = function() NA_character_)
  expect_identical(written(function() console_live("T")$draw(state)),
                   paste0("\r", console_live_row(state, 40L), "\033[K"))
})
