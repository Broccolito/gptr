# The shared pure fixture follows the supported public owner/remote-adapter boundaries.
artifact_browser_fixture = function(local = TRUE) {
  x = artifact_owner_fixture(remote = isFALSE(local))
  x$state$local = local
  x
}

test_that("artifact browser cleanup uses graceful close before confirming its local process", {
  x = artifact_browser_fixture()
  expect_invisible(x$close())
  expect_identical(x$state$events[[1L]], "websocket")
  expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
  expect_true(all(x$state$events[2:(length(x$state$events) - 2L)] == "pump"))
  expect_true(length(x$state$pump_timeouts) > 0L)
  expect_true(all(x$state$pump_timeouts > 0 & x$state$pump_timeouts <= 0.02))
  expect_true(all(vapply(x$state$during, identical, logical(1), y = x$container)))
  expect_identical(x$state$socket_wait, FALSE)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
  previous = x$state$events
  expect_invisible(x$close())
  expect_identical(x$state$events, previous)
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
    expect_identical(x$state$events[[1L]], "websocket")
    expect_identical(utils::tail(x$state$events, 1L), "process")
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    x$state$process_error = NULL
    expect_invisible(x$close())
    expect_identical(sum(x$state$events == "process"), 2L)
    expect_identical(sum(x$state$events == "wait"), 1L)
    expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
    expect_null(x$scope$artifact_state$browser)
    expect_null(x$scope$artifact_state$browser_owner)
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

test_that(
  "artifact browser cleanup refuses unknown owners and retains a live owner after waiting", {
  for (alive in list(TRUE, NA, 0, NULL)) {
    x = artifact_browser_fixture()
    x$state$alive = alive
    x$state$wait_dead = FALSE
    expect_error(x$close(), class = "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    if (isTRUE(alive)) {
      expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
    } else {
      expect_identical(x$state$events, character())
    }
  }
  x = artifact_browser_fixture(local = NA)
  expect_error(x$close(), class = "gptr_error_io")
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_identical(x$state$events, character())
})

test_that("artifact browser cleanup retries a dead owner's failed socket without signalling", {
  x = artifact_browser_fixture()
  x$state$alive = FALSE
  original = simpleError("controlled socket close")
  x$state$socket_error = original
  result = tryCatch(x$close(), error = identity)
  expect_identical(result, original)
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_identical(x$scope$artifact_state$browser_owner, x$owner)
  expect_false(x$state$alive)
  x$state$socket_error = NULL
  expect_invisible(x$close())
  expect_identical(sum(x$state$events == "websocket"), 2L)
  expect_true(all(x$state$events %in% c("pump", "websocket")))
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
})

test_that("artifact browser cleanup cannot discard a replacement cache object", {
  x = artifact_browser_fixture()
  x$state$replace_on_close = TRUE
  expect_error(x$close(), class = "gptr_error_io")
  expect_identical(x$scope$artifact_state$browser, x$replacement)
  expect_identical(x$scope$artifact_state$browser_owner, x$owner)
  expect_true(x$state$alive)
  expect_false("process" %in% x$state$events)
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
    expect_identical(x$state$owner_calls, 0L)
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
  expect_identical(x$state$owner_calls, 0L)
  x$state$socket_error = NULL
  opened = x$open()
  expect_identical(x$state$owner_calls, 1L)
  expect_identical(x$state$container_calls, 1L)
  expect_identical(sum(x$state$events == "websocket"), 2L)
  expect_true(all(x$state$events %in% c("pump", "websocket")))
  expect_identical(x$scope$artifact_state$browser, opened)
  expect_identical(x$scope$artifact_state$browser_owner, x$owner)
  expect_false(identical(opened, x$container))
  expect_false(opened$get_browser()$is_local())
  expect_true(x$state$alive)
})

test_that("artifact browser cache reuses its live exact container without a new owner", {
  x = artifact_browser_fixture()
  expect_identical(x$open(), x$container)
  expect_identical(x$state$owner_calls, 0L)
  expect_identical(x$state$events, character())
})

test_that("a dead browser settles only its retained child loop before closing the socket", {
  x = artifact_browser_fixture()
  x$state$alive = FALSE
  x$state$needs_pump = TRUE
  expect_invisible(x$close())
  expect_identical(utils::tail(x$state$events, 1L), "websocket")
  expect_true(all(utils::head(x$state$events, -1L) == "pump"))
  expect_true(all(vapply(x$state$during, identical, logical(1), y = x$container)))
  expect_false(x$state$needs_pump)
  expect_null(x$scope$artifact_state$browser)
  expect_identical(x$state$owner_calls, 0L)
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
      expect_identical(utils::tail(x$state$events, 1L), "websocket")
      expect_false("process" %in% x$state$events)
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
        x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
        x$state$draw_construct = TRUE
        original = structure(list(message = "controlled constructor condition", call = NULL),
          class = c(paste0("controlled_", outcome), outcome, "condition"))
        if (outcome != "return") x$state$factory_error = original
        seen = tryCatch(x$open(), error = identity, interrupt = identity)
        if (outcome == "return") {
          expect_identical(seen, x$scope$artifact_state$browser)
          expect_identical(x$scope$artifact_state$browser_owner, x$owner)
          expect_false(seen$get_browser()$is_local())
        } else {
          expect_identical(seen, original)
          expect_null(x$scope$artifact_state$browser)
        }
        expect_identical(x$state$owner_calls, 1L)
        expect_length(x$state$draws, 2L)
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
            expect_identical(x$state$events[[1L]], "websocket")
            expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
            expect_true(all(x$state$events[2:(length(x$state$events) - 2L)] == "pump"))
            expect_true(length(x$state$draws) >= 4L)
            expect_null(x$scope$artifact_state$browser_owner)
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
