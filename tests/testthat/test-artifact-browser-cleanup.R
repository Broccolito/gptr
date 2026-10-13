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
  state$pump_error = NULL
  state$loop_error = NULL
  state$needs_pump = FALSE
  state$draw_construct = FALSE
  state$draw_close = FALSE
  state$draw_pump = FALSE
  state$draws = numeric()
  state$factory_error = NULL
  expected_loop = new.env(parent = emptyenv())
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
    }, is_active = function() state$active, get_child_loop = function() {
      if (!is.null(state$loop_error)) stop(state$loop_error)
      expected_loop
    }, close = function(wait = TRUE) {
      if (state$draw_close) state$draws = c(state$draws, runif(1))
      if (isTRUE(wait)) {
        stopifnot(isTRUE(state$local), isTRUE(state$alive))
        state$events = c(state$events, "graceful")
        state$during = c(state$during, list(scope$artifact_state$browser))
        if (!is.null(state$process_error)) stop(state$process_error)
        if (state$wait_dead) state$alive = FALSE
        state$active = FALSE
        return(invisible(NULL))
      }
      state$events = c(state$events, "websocket")
      state$during = c(state$during, list(scope$artifact_state$browser))
      state$socket_wait = wait
      if (!is.null(state$socket_error)) stop(state$socket_error)
      if (state$needs_pump) stop("The native socket is closed but its callback is pending")
      state$active = FALSE
      if (state$replace_on_close) scope$artifact_state$browser = replacement
    })
  scope$artifact_state$browser = container
  rewrite = function(expr) {
    constructor = quote(chromote::Chromote$new(browser = chromote::Chrome$new(args = args)))
    if (identical(expr, constructor)) return(quote(new_browser()))
    if (is.call(expr)) {
      if (identical(expr[[1L]], quote(later::run_now))) expr[[1L]] = as.name("pump")
      for (i in seq_along(expr)) expr[i] = list(rewrite(expr[[i]]))
    }
    expr
  }
  close = artifact_browser_close
  body(close) = rewrite(body(close))
  environment(close) = scope
  scope$artifact_browser_close = close
  open = artifact_browser
  environment(open) = scope
  # Replace only construction and the private-loop leaf in the actual cloned functions.
  code = as.list(body(open))
  args = which(vapply(code, function(expr) {
    identical(expr, quote({
      args = c(chromote::get_chrome_args(), "--use-mock-keychain")
    })[[2L]])
  }, logical(1)))
  stopifnot(length(args) == 1L)
  code[[args]] = quote({
    args = character()
  })[[2L]]
  body(open) = rewrite(as.call(code))
  scope$new_browser = function() {
    state$new_calls = state$new_calls + 1L
    stopifnot(is.null(scope$artifact_state$browser))
    if (state$draw_construct) state$draws = c(state$draws, runif(1))
    if (!is.null(state$factory_error)) stop(state$factory_error)
    replacement
  }
  scope$pump = function(loop, ...) {
    arguments = list(...)
    stopifnot(identical(names(arguments), "timeoutSecs"),
      identical(arguments[["timeoutSecs"]], 0.2), identical(loop, expected_loop),
      identical(scope$artifact_state$browser, container), isFALSE(state$alive))
    state$events = c(state$events, "pump")
    state$during = c(state$during, list(scope$artifact_state$browser))
    if (state$draw_pump) state$draws = c(state$draws, runif(1))
    if (!is.null(state$pump_error)) stop(state$pump_error)
    state$needs_pump = FALSE
    invisible(TRUE)
  }
  list(state = state, scope = scope, container = container, replacement = replacement,
    close = close, open = open)
}

test_that("artifact browser cleanup uses graceful close before confirming its local process", {
  x = artifact_browser_fixture()
  expect_invisible(x$close())
  expect_identical(x$state$events, c("graceful", "pump", "websocket"))
  expect_true(all(vapply(x$state$during, identical, logical(1), y = x$container)))
  expect_identical(x$state$socket_wait, FALSE)
  expect_null(x$scope$artifact_state$browser)
  expect_invisible(x$close())
  expect_identical(x$state$events, c("graceful", "pump", "websocket"))
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
    expect_identical(x$state$events, "graceful")
    x$state$process_error = NULL
    expect_invisible(x$close())
    expect_identical(x$state$events, c("graceful", "graceful", "pump", "websocket"))
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
  expect_identical(x$state$events, c("graceful", "pump", "websocket", "pump", "websocket"))
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
  expect_identical(x$state$events, c("pump", "websocket", "pump", "websocket"))
  expect_identical(x$scope$artifact_state$browser, x$replacement)
})

test_that("artifact browser cache reuses its live exact container without a new owner", {
  x = artifact_browser_fixture()
  expect_identical(x$open(), x$container)
  expect_identical(x$state$new_calls, 0L)
  expect_identical(x$state$events, character())
})

test_that("a dead browser settles only its retained child loop before closing the socket", {
  x = artifact_browser_fixture()
  x$state$alive = FALSE
  x$state$needs_pump = TRUE
  expect_invisible(x$close())
  expect_identical(x$state$events, c("pump", "websocket"))
  expect_true(all(vapply(x$state$during, identical, logical(1), y = x$container)))
  expect_false(x$state$needs_pump)
  expect_null(x$scope$artifact_state$browser)
  expect_identical(x$state$new_calls, 0L)
})

test_that("browser loop queries and callbacks retain their original conditions and owner", {
  for (stage in c("loop_error", "pump_error")) {
    for (kind in c("error", "interrupt")) {
      x = artifact_browser_fixture()
      x$state$alive = FALSE
      original = structure(list(message = "controlled child loop condition", call = NULL),
        class = c(paste0("controlled_", kind), kind, "condition"))
      x$state[[stage]] = original
      seen = tryCatch(x$close(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(x$scope$artifact_state$browser, x$container)
      expect_false("process" %in% x$state$events)
      expect_false("websocket" %in% x$state$events)
      x$state[[stage]] = NULL
      expect_invisible(x$close())
      expect_identical(utils::tail(x$state$events, 2L), c("pump", "websocket"))
      expect_null(x$scope$artifact_state$browser)
    }
  }
})

test_that("browser construction preserves seeded and absent RNG on return and unwind", {
  for (seeded in c(FALSE, TRUE)) {
    for (outcome in c("return", "error", "interrupt")) {
      local({
        withr::local_preserve_seed()
        if (seeded) {
          set.seed(173L)
        } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        seed = get0(".Random.seed", globalenv(), inherits = FALSE)
        objects = ls(envir = globalenv(), all.names = TRUE)
        x = artifact_browser_fixture()
        x$scope$artifact_state$browser = NULL
        x$state$draw_construct = TRUE
        original = structure(list(message = "controlled constructor condition", call = NULL),
          class = c(paste0("controlled_", outcome), outcome, "condition"))
        if (outcome != "return") x$state$factory_error = original
        seen = tryCatch(x$open(), error = identity, interrupt = identity)
        if (outcome == "return") {
          expect_identical(seen, x$replacement)
          expect_identical(x$scope$artifact_state$browser, x$replacement)
        } else {
          expect_identical(seen, original)
          expect_null(x$scope$artifact_state$browser)
        }
        expect_identical(x$state$new_calls, 1L)
        expect_length(x$state$draws, 1L)
        expect_true(all(is.finite(x$state$draws)))
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
        expect_identical(ls(envir = globalenv(), all.names = TRUE), objects)
      })
    }
  }
})

test_that("browser close preserves caller RNG and callback effects on success and unwind", {
  for (seeded in c(FALSE, TRUE)) {
    for (stage in c("return", "process_error", "pump_error", "socket_error")) {
      for (kind in c("error", "interrupt")) {
        local({
          withr::local_preserve_seed()
          if (seeded) {
            set.seed(173L)
          } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
            rm(list = ".Random.seed", envir = globalenv())
          }
          seed = get0(".Random.seed", globalenv(), inherits = FALSE)
          objects = ls(envir = globalenv(), all.names = TRUE)
          x = artifact_browser_fixture()
          x$state$draw_close = TRUE
          x$state$draw_pump = TRUE
          original = structure(list(message = "controlled close condition", call = NULL),
            class = c(paste0("controlled_", kind), kind, "condition"))
          if (stage != "return") x$state[[stage]] = original
          seen = tryCatch(x$close(), error = identity, interrupt = identity)
          if (stage == "return") {
            expect_null(seen)
            expect_null(x$scope$artifact_state$browser)
            expect_identical(x$state$events, c("graceful", "pump", "websocket"))
            expect_length(x$state$draws, 3L)
          } else {
            expect_identical(seen, original)
            expect_identical(x$scope$artifact_state$browser, x$container)
            expect_true(length(x$state$draws) >= 1L)
          }
          expect_true(all(is.finite(x$state$draws)))
          expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
          expect_identical(ls(envir = globalenv(), all.names = TRUE), objects)
        })
      }
    }
  }
})

test_that("remote browser socket cleanup preserves caller RNG without a local process query", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(173L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      seed = get0(".Random.seed", globalenv(), inherits = FALSE)
      x = artifact_browser_fixture(local = FALSE)
      x$state$draw_close = TRUE
      expect_invisible(x$close())
      expect_identical(x$state$events, "websocket")
      expect_true(x$state$alive)
      expect_length(x$state$draws, 1L)
      expect_null(x$scope$artifact_state$browser)
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
    })
  }
})
