# R.app can inherit stderr color after deleting a CR row; start a fresh stdout line first.
spinner_gui_capture = function(callback) {
  bytes = rawConnection(raw(), "w")
  on.exit(close(bytes), add = TRUE)
  sink(bytes)
  tryCatch(callback(bytes), finally = sink())
}

test_that("native R GUI spinner establishes a flushed stdout line once per shown cycle", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
    cli.width = 40L)
  local_mocked_bindings(front_end = function() "rgui")
  spinner_gui_capture(function(bytes) {
    observed = new.env(parent = emptyenv())
    observed$flushes = list()
    local_mocked_bindings(flush.console = function() {
      observed$flushes[[length(observed$flushes) + 1L]] = rawToChar(rawConnectionValue(bytes))
    }, .package = "utils")
    sp = console_spinner()
    sp$tick()
    first = rawToChar(rawConnectionValue(bytes))
    expect_true(startsWith(first, "\n\r"))
    expect_identical(sum(rawConnectionValue(bytes) == charToRaw("\n")), 1L)
    expect_length(observed$flushes, 2L)
    expect_identical(observed$flushes[[1L]], "\n")
    expect_identical(tail(observed$flushes, 1L)[[1L]], first)
    expect_true(sp$shown)
    expect_false(grepl("\033", first, fixed = TRUE))
    sp$last = 0
    sp$tick()
    expect_identical(sum(rawConnectionValue(bytes) == charToRaw("\n")), 1L)
    expect_length(observed$flushes, 3L)
    sp$clear()
    expect_false(sp$shown)
    cleared = rawConnectionValue(bytes)
    sp$last = Inf
    sp$tick()
    expect_identical(rawConnectionValue(bytes), cleared)
    expect_false(sp$shown)
    sp$last = 0
    sp$tick()
    expect_identical(sum(rawConnectionValue(bytes) == charToRaw("\n")), 2L)
    expect_true(sp$shown)
    second = substring(rawToChar(rawConnectionValue(bytes)), nchar(rawToChar(cleared)) + 1L)
    expect_true(startsWith(second, "\n\r"))
  })
})

test_that("other dynamic frontends retain carriage-return-only spinner frames", {
  withr::local_options(cli.dynamic = TRUE, cli.unicode = FALSE, cli.num_colors = 1L,
    cli.width = 40L)
  for (frontend in c("terminal", "vscode", "rstudio", "positron", "jupyter", "rscript",
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
