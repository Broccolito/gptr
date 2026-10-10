# tests/testthat/test-console-resize.R -- resize within a streamed text block, without reflow.

resize_stream = function(widths, deltas, fixed = NULL, finish_width = tail(widths, 1L)) {
  stopifnot(length(widths) == length(deltas))
  withr::local_options(cli.width = widths[[1L]], cli.num_colors = 1L)
  utils::capture.output({
    r = if (is.null(fixed)) render_markdown_stream() else render_markdown_stream(fixed)
    for (i in seq_along(deltas)) {
      options(cli.width = widths[[i]])
      r$write(deltas[[i]])
    }
    options(cli.width = finish_width)
    r$finish()
  })
}

test_that("default prose width follows shrink and expansion within the same text block", {
  out = resize_stream(c(80L, 20L, 80L), c(
    "alpha beta gamma delta epsilon zeta eta theta ",
    "iota kappa lambda mu ",
    "nu xi omicron pi rho sigma "
  ))
  expect_identical(out, c(
    "alpha beta gamma delta epsilon zeta eta theta",
    "iota kappa lambda mu nu xi omicron pi rho sigma"
  ))
})

test_that("an explicitly supplied width stays fixed when the console width changes", {
  out = resize_stream(c(80L, 20L, 80L), c(
    "alpha beta gamma delta epsilon zeta eta theta ",
    "iota kappa lambda mu ",
    "nu xi omicron pi rho sigma "
  ), fixed = 40L)
  expect_identical(out, c(
    "alpha beta gamma delta epsilon zeta eta",
    "theta iota kappa lambda mu nu xi omicron",
    "pi rho sigma"
  ))
})

test_that("finish uses the latest default width when releasing a held final word", {
  expect_identical(resize_stream(80L, "alpha beta gamma delta", finish_width = 20L),
                   c("alpha beta gamma", "delta"))
  expect_identical(resize_stream(80L, "alpha beta gamma delta", fixed = 80L,
                                 finish_width = 20L), "alpha beta gamma delta")
})

test_that("a hanging bullet keeps its indentation after a width change", {
  out = resize_stream(c(32L, 20L), c(
    "- alpha beta gamma delta epsilon ", "zeta eta theta iota "
  ))
  expect_identical(out, c("- alpha beta gamma delta epsilon", "  zeta eta theta", "  iota"))
})

test_that("resizing preserves fenced code, split CRLF and an unbreakable token verbatim", {
  out = resize_stream(c(80L, 20L, 40L), c(
    "before\n```r\nx = \"", "abcdefghijklmnopqrstuvwxyz\"\r", "\n```\nafter"
  ))
  expect_identical(out, c("before", "```r", 'x = "abcdefghijklmnopqrstuvwxyz"', "```", "after"))
  token = paste0("https://example.org/", strrep("x", 80L))
  expect_identical(resize_stream(80L, token, finish_width = 20L), token)
})
