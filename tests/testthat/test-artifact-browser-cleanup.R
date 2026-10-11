# Pure browser lifecycle checks; actual Chrome rendering remains in test-artifact-app.R.

test_that("artifact browser cleanup closes its owned local process before the websocket", {
  original = artifact_state$browser
  withr::defer({
    artifact_state$browser = original
  })
  state = new.env(parent = emptyenv())
  state$alive = TRUE
  state$events = character()
  browser = list(is_local = function() TRUE, close = function(wait) {
    expect_true(wait)
    expect_null(artifact_state$browser)
    state$events = c(state$events, "process")
    state$alive = FALSE
  })
  artifact_state$browser = list(get_browser = function() browser, close = function() {
    expect_false(state$alive)
    expect_null(artifact_state$browser)
    state$events = c(state$events, "websocket")
  })
  expect_invisible(artifact_browser_close())
  expect_identical(state$events, c("process", "websocket"))
  expect_null(artifact_state$browser)
  expect_invisible(artifact_browser_close())
  expect_identical(state$events, c("process", "websocket"))
})

test_that("artifact browser cleanup still closes its websocket after a process-close error", {
  original = artifact_state$browser
  withr::defer({
    artifact_state$browser = original
  })
  state = new.env(parent = emptyenv())
  state$events = character()
  browser = list(is_local = function() TRUE, close = function(wait) {
    state$events = c(state$events, "process")
    stop("controlled process-close fixture error")
  })
  artifact_state$browser = list(get_browser = function() browser, close = function() {
    state$events = c(state$events, "websocket")
  })
  expect_no_error(artifact_browser_close())
  expect_identical(state$events, c("process", "websocket"))
  expect_null(artifact_state$browser)
})

test_that("artifact browser cleanup leaves a remote browser process alone", {
  original = artifact_state$browser
  withr::defer({
    artifact_state$browser = original
  })
  state = new.env(parent = emptyenv())
  state$process_calls = 0L
  state$websocket_calls = 0L
  browser = list(is_local = function() FALSE, close = function(wait) {
    state$process_calls = state$process_calls + 1L
  })
  artifact_state$browser = list(get_browser = function() browser, close = function() {
    state$websocket_calls = state$websocket_calls + 1L
  })
  expect_no_error(artifact_browser_close())
  expect_identical(state$process_calls, 0L)
  expect_identical(state$websocket_calls, 1L)
  expect_null(artifact_state$browser)
})

test_that("the private Linux test temp root fits Chromium's Unix socket limit", {
  path = Sys.getenv("TMPDIR")
  expect_true(dir.exists(path))
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    expect_true(startsWith(path, "/tmp/"))
    socket = file.path(path, "org.chromium.Chromium.XXXXXX", "SingletonSocket")
    expect_lte(nchar(socket, type = "bytes"), 107L)
    mode = bitwAnd(as.integer(file.info(dirname(path))$mode), 511L)
    expect_identical(mode, 448L)
  }
})
