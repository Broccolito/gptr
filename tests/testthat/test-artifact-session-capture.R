# Exercise the package browser/check code with a fixed, offline CDP peer.
artifact_capture_probe = function(capture, errors = list(), js = NULL,
                                   disconnected = FALSE, navigation_error = NULL) {
  seen = new.env(parent = emptyenv())
  seen$closed = 0L
  seen$captured = 0L
  seen$evaluated = character()
  browser = list(
    close = function() {
      seen$closed = seen$closed + 1L
    },
    wait_for = function(value) value,
    Runtime = list(
      enable = function() invisible(NULL),
      exceptionThrown = function(callback_) {
        if (!is.null(js)) callback_(list(exceptionDetails = list(text = js)))
      },
      consoleAPICalled = function(callback_) invisible(NULL),
      evaluate = function(expression, ...) {
        expect_identical(list(...), list(returnByValue = TRUE))
        seen$evaluated = c(seen$evaluated, expression)
        value = if (identical(expression, artifact_js_state)) {
          json_encode(list(connected = TRUE, disconnected = disconnected,
            busy = FALSE, recalculating = 0L))
        } else {
          expect_identical(expression, artifact_js_errors)
          json_encode(errors)
        }
        list(result = list(value = value))
      }
    ),
    Page = list(
      loadEventFired = function(wait_, timeout_) {
        expect_false(wait_)
        expect_identical(timeout_, 20)
        TRUE
      },
      navigate = function(url, wait_) {
        expect_identical(url, "http://127.0.0.1/synthetic")
        expect_false(wait_)
        if (!is.null(navigation_error)) stop(navigation_error)
        invisible(NULL)
      },
      captureScreenshot = function(format) {
        expect_identical(format, "png")
        seen$captured = seen$captured + 1L
        capture()
      }
    )
  )
  scope = list2env(list(
    artifact_browser = function() {
      list(new_session = function(width, height) {
        expect_identical(c(width, height), c(1000L, 700L))
        browser
      })
    },
    reactor_now = function() 0,
    reactor_pump = function(...) invisible(FALSE)
  ), parent = environment(artifact_session_browse))
  browse = artifact_session_browse
  environment(browse) = scope
  list(browse = browse, seen = seen)
}

artifact_capture_run = function(probe, server_error = character()) {
  run = artifact_session_run
  environment(run) = list2env(list(
    artifact_chromote_missing = function() NULL,
    artifact_session_browse = probe$browse,
    artifact_log_sync = function(rec) invisible(NULL),
    artifact_log_errors = function(log) list(errors = server_error, warnings = character()),
    artifact_log_messages = function(log) {
      if (length(server_error)) paste0("server log: ", server_error) else character()
    }
  ), parent = environment(artifact_session_run))
  run(list(url = "http://127.0.0.1/synthetic", log = "synthetic"),
    tempfile(fileext = ".png"), 1000L, 700L, 20)
}

test_that("screenshot errors retain collected page state and close the exact session", {
  skip_on_cran()
  original = simpleError("synthetic screenshot timeout")
  probe = artifact_capture_probe(function() stop(original),
    errors = list(list(id = "plot", message = "synthetic output failure")),
    js = "synthetic JavaScript failure", disconnected = TRUE)
  value = probe$browse("http://127.0.0.1/synthetic", 1000L, 700L, 20)
  expect_true(value$connected)
  expect_true(value$disconnected)
  expect_identical(value$output_errors, "plot: synthetic output failure")
  expect_identical(value$js_errors, "synthetic JavaScript failure")
  expect_null(value$png)
  expect_identical(value$screenshot_error, conditionMessage(original))
  expect_identical(probe$seen$captured, 1L)
  expect_identical(probe$seen$closed, 1L)
  expect_identical(utils::tail(probe$seen$evaluated, 1L), artifact_js_errors)
  success = artifact_capture_probe(function() list(data = "synthetic-base64"))
  value = success$browse("http://127.0.0.1/synthetic", 1000L, 700L, 20)
  expect_identical(value$png, "synthetic-base64")
  expect_null(value$screenshot_error)
  expect_identical(success$seen$closed, 1L)
})

test_that("clean page validation reports a missing screenshot without claiming HTTP-only", {
  probe = artifact_capture_probe(function() stop("synthetic screenshot timeout"))
  value = artifact_capture_run(probe)
  expect_identical(value$ok, TRUE)
  expect_null(value$screenshot)
  expect_identical(value$messages,
    "The screenshot could not be captured: synthetic screenshot timeout")
  expect_false(any(grepl("HTTP-only|page was not rendered", value$messages)))
  expect_identical(probe$seen$closed, 1L)
})

test_that("screenshot failures retain output JavaScript server and disconnect errors", {
  probe = artifact_capture_probe(function() stop("synthetic screenshot timeout"),
    errors = list(list(id = "plot", message = "synthetic output failure")),
    js = "synthetic JavaScript failure", disconnected = TRUE)
  value = artifact_capture_run(probe, server_error = "synthetic server failure")
  expect_identical(value$ok, FALSE)
  expect_null(value$screenshot)
  expect_identical(value$messages, c(
    "output error in plot: synthetic output failure",
    "JavaScript error: synthetic JavaScript failure",
    "The screenshot could not be captured: synthetic screenshot timeout",
    "server log: synthetic server failure",
    "the Shiny session disconnected: the server function failed"))
  expect_false(any(grepl("HTTP-only|page was not rendered", value$messages)))
  expect_identical(probe$seen$closed, 1L)
})

test_that("screenshot interrupts and navigation errors preserve their original boundary", {
  original = structure(list(message = "synthetic screenshot interrupt", call = NULL),
    class = c("synthetic_interrupt", "interrupt", "condition"))
  probe = artifact_capture_probe(function() stop(original))
  caught = tryCatch(probe$browse("http://127.0.0.1/synthetic", 1000L, 700L, 20),
    interrupt = identity)
  expect_identical(caught, original)
  expect_identical(probe$seen$closed, 1L)
  expect_identical(probe$seen$captured, 1L)
  navigation = artifact_capture_probe(function() stop("Screenshot must not run"),
    navigation_error = simpleError("synthetic navigation failure"))
  value = artifact_capture_run(navigation)
  expect_true(is.na(value$ok))
  expect_null(value$screenshot)
  expect_identical(value$messages,
    paste0("HTTP-only check: the headless browser failed: synthetic navigation failure; ",
      "the page was not rendered"))
  expect_identical(navigation$seen$captured, 0L)
  expect_identical(navigation$seen$closed, 1L)
})
