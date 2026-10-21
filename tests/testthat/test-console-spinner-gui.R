# Spinner frames are CR-only everywhere; in R.app the block gap before a waiting row gives the
# fresh stdout line that keeps a deleted row from inheriting stderr color (D-186).
spinner_gui_capture = function(callback) {
  bytes = rawConnection(raw(), "w")
  on.exit(close(bytes), add = TRUE)
  sink(bytes)
  tryCatch(callback(bytes), finally = sink())
}

test_that("dynamic frontends, R GUIs too, use carriage-return-only spinner frames", {
  skip_on_cran()
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
    cli.width = 40L)
  for (frontend in c("rgui", "terminal", "vscode", "rstudio", "positron", "jupyter", "rscript",
                     "knitr", "quarto", "unknown")) {
    local_mocked_bindings(front_end = function() frontend)
    spinner_gui_capture(function(bytes) {
      sp = console_spinner()
      sp$tick()
      first = rawToChar(rawConnectionValue(bytes))
      expect_true(startsWith(first, "\r"), info = frontend)
      expect_false(grepl("\n", first, fixed = TRUE), info = frontend)
      sp$clear()
      expect_false(grepl("\n", rawToChar(rawConnectionValue(bytes)), fixed = TRUE), info = frontend)
    })
  }
})

test_that("non-dynamic native GUI, pipe and knitr spinners remain silent", {
  withr::local_options(cli.dynamic = FALSE)
  for (frontend in c("rgui", "rscript", "knitr")) {
    local_mocked_bindings(front_end = function() frontend)
    spinner_gui_capture(function(bytes) {
      sp = console_spinner()
      sp$tick()
      sp$clear()
      expect_identical(rawConnectionValue(bytes), raw(), info = frontend)
      expect_false(sp$shown, info = frontend)
    })
  }
})
