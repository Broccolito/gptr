# Pure lifecycle checks clone only private gptr closures; no Chromote binding is changed.
artifact_browser_fixture = function(local = TRUE) {
  scope = new.env(parent = environment(artifact_browser))
  scope$artifact_state = new.env(parent = emptyenv())
  state = new.env(parent = emptyenv())
  state$alive = TRUE
  state$active = TRUE
  state$events = character()
  state$during = list()
  state$local = local
  state$process_error = NULL
  state$socket_error = NULL
  state$query_error = NULL
  state$wait_dead = TRUE
  state$new_calls = 0L
  state$replace_on_close = FALSE
  replacement = list(replacement = TRUE)
  process = list(is_alive = function() state$alive)
  browser = list(is_local = function() state$local,
    get_process = function() {
      if (!isTRUE(state$local)) stop("A remote process was queried")
      process
    }, close = function(wait) {
      stopifnot(identical(wait, TRUE), isTRUE(state$local))
      state$events = c(state$events, "process")
      state$during = c(state$during, list(scope$artifact_state$browser))
      if (!is.null(state$process_error)) stop(state$process_error)
      if (state$wait_dead) state$alive = FALSE
    })
  container = list(get_browser = function() browser,
    is_alive = function() {
      if (!is.null(state$query_error)) stop(state$query_error)
      state$alive
    }, is_active = function() state$active, close = function(wait = TRUE) {
      state$events = c(state$events, "websocket")
      state$during = c(state$during, list(scope$artifact_state$browser))
      state$socket_wait = wait
      if (!is.null(state$socket_error)) stop(state$socket_error)
      state$active = FALSE
      if (state$replace_on_close) scope$artifact_state$browser = replacement
    })
  scope$artifact_state$browser = container
  close = artifact_browser_close
  environment(close) = scope
  scope$artifact_browser_close = close
  open = artifact_browser
  environment(open) = scope
  # Replace construction only, so baseline cache failures cannot launch a real browser.
  code = as.list(body(open))
  args = which(vapply(code, function(expr) {
    identical(expr, quote({
      args = c(chromote::get_chrome_args(), "--use-mock-keychain")
    })[[2L]])
  }, logical(1)))
  create = which(vapply(code, function(expr) {
    identical(expr, quote({
      b = chromote::Chromote$new(browser = chromote::Chrome$new(args = args))
    })[[2L]])
  }, logical(1)))
  stopifnot(length(args) == 1L, length(create) == 1L)
  code[[args]] = quote({
    args = character()
  })[[2L]]
  code[[create]] = quote({
    b = new_browser()
  })[[2L]]
  body(open) = as.call(code)
  scope$new_browser = function() {
    state$new_calls = state$new_calls + 1L
    stopifnot(is.null(scope$artifact_state$browser))
    replacement
  }
  list(state = state, scope = scope, container = container, replacement = replacement,
    close = close, open = open)
}

test_that("artifact browser cleanup closes its owned local process before the websocket", {
  x = artifact_browser_fixture()
  expect_invisible(x$close())
  expect_identical(x$state$events, c("process", "websocket"))
  expect_true(all(vapply(x$state$during, identical, logical(1), y = x$container)))
  expect_identical(x$state$socket_wait, FALSE)
  expect_null(x$scope$artifact_state$browser)
  expect_invisible(x$close())
  expect_identical(x$state$events, c("process", "websocket"))
})

test_that("artifact browser cleanup retains its owner after a process-close error", {
  for (kind in c("error", "interrupt")) {
    x = artifact_browser_fixture()
    original = if (kind == "error") simpleError("controlled process close") else
      structure(list(message = "controlled interrupt", call = NULL),
                class = c("interrupt", "condition"))
    x$state$process_error = original
    result = tryCatch(x$close(), error = function(e) e, interrupt = function(e) e)
    expect_identical(result, original)
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$state$events, "process")
    x$state$process_error = NULL
    expect_invisible(x$close())
    expect_identical(x$state$events, c("process", "process", "websocket"))
    expect_null(x$scope$artifact_state$browser)
  }
})

test_that("artifact browser cleanup leaves a remote browser process alone", {
  x = artifact_browser_fixture(local = FALSE)
  expect_invisible(x$close())
  expect_identical(x$state$events, "websocket")
  expect_identical(x$state$socket_wait, FALSE)
  expect_true(x$state$alive)
  expect_null(x$scope$artifact_state$browser)
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

test_that("artifact browser cleanup refuses live or unknown owners before websocket close", {
  for (alive in list(TRUE, NA, 0, NULL)) {
    x = artifact_browser_fixture()
    x$state$alive = alive
    x$state$wait_dead = FALSE
    expect_error(x$close(), class = "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_false("websocket" %in% x$state$events)
  }
  x = artifact_browser_fixture(local = NA)
  expect_error(x$close(), class = "gptr_error_io")
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_identical(x$state$events, character())
})

test_that("artifact browser cleanup retries a dead owner's failed socket without signalling", {
  x = artifact_browser_fixture()
  original = simpleError("controlled socket close")
  x$state$socket_error = original
  result = tryCatch(x$close(), error = function(e) e)
  expect_identical(result, original)
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_false(x$state$alive)
  x$state$socket_error = NULL
  expect_invisible(x$close())
  expect_identical(x$state$events, c("process", "websocket", "websocket"))
  expect_null(x$scope$artifact_state$browser)
})

test_that("artifact browser cleanup cannot discard a replacement cache object", {
  x = artifact_browser_fixture()
  x$state$replace_on_close = TRUE
  expect_invisible(x$close())
  expect_identical(x$scope$artifact_state$browser, x$replacement)
})

test_that("artifact browser cache refuses unknown ownership without constructing a replacement", {
  for (kind in c("unknown", "error", "interrupt")) {
    x = artifact_browser_fixture()
    original = if (kind == "error") simpleError("controlled cache query") else
      structure(list(message = "controlled cache interrupt", call = NULL),
                class = c("interrupt", "condition"))
    if (kind == "unknown") x$state$alive = NA else x$state$query_error = original
    result = tryCatch(x$open(), error = function(e) e, interrupt = function(e) e)
    if (kind == "unknown") {
      expect_s3_class(result, "gptr_error_io")
    } else {
      expect_identical(result, original)
    }
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$state$new_calls, 0L)
    expect_identical(x$state$events, character())
  }
})

test_that("artifact browser cache replaces a dead owner only after successful socket cleanup", {
  x = artifact_browser_fixture()
  x$state$alive = FALSE
  original = simpleError("controlled dead socket close")
  x$state$socket_error = original
  result = tryCatch(x$open(), error = function(e) e)
  expect_identical(result, original)
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_identical(x$state$new_calls, 0L)
  x$state$socket_error = NULL
  expect_identical(x$open(), x$replacement)
  expect_identical(x$state$new_calls, 1L)
  expect_identical(x$state$events, c("websocket", "websocket"))
  expect_identical(x$scope$artifact_state$browser, x$replacement)
})

test_that("artifact browser cache reuses its live exact container without a new owner", {
  x = artifact_browser_fixture()
  expect_identical(x$open(), x$container)
  expect_identical(x$state$new_calls, 0L)
  expect_identical(x$state$events, character())
})
