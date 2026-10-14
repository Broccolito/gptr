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


test_that("browser cleanup accepts delayed callbacks within its existing shutdown deadline", {
  started = 1
  target = started + 0.2
  expect_lt(target - started, 0.2)
  x = artifact_browser_fixture()
  x$state$clock = started
  x$scope$clock = function() c(elapsed = x$state$clock)
  pump = x$scope$pump
  x$scope$pump = function(loop, ...) {
    pump(loop, ...)
    x$state$clock = target
  }
  expect_invisible(x$close())
  expect_identical(x$state$clock, target)
  expect_length(x$state$pump_timeouts, 1L)
  expect_identical(x$state$events, c("websocket", "pump", "process", "wait"))
  expect_false(x$state$alive)
  expect_false(x$state$active)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
  for (delay in c(0.31, 1, 9)) {
    x = artifact_browser_fixture()
    process = x$owner$get_process()
    pump = x$scope$pump
    x$scope$pump = function(loop, ...) {
      x$state$clock = x$state$clock + delay
      pump(loop, ...)
    }
    expect_invisible(x$close())
    expect_true(x$state$clock > delay && x$state$clock < 10)
    expect_length(x$state$pump_timeouts, 1L)
    expect_true(all(x$state$pump_timeouts > 0 & x$state$pump_timeouts <= 0.02))
    expect_identical(x$owner$get_process(), process)
    expect_identical(x$state$events[[1L]], "websocket")
    expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
    expect_false(x$state$alive)
    expect_false(x$state$active)
    expect_null(x$scope$artifact_state$browser)
    expect_null(x$scope$artifact_state$browser_owner)
  }
})

test_that("browser cleanup advances a fractional grace remainder on a coarse clock", {
  x = artifact_browser_fixture()
  x$state$milliseconds = 100L
  x$state$naps = numeric()
  x$scope$clock = function() {
    c(elapsed = floor(x$state$milliseconds / 10) / 100)
  }
  # R 4.2 Windows reports elapsed time in 10 ms ticks and rounds sleeps to milliseconds.
  expect_gt(0.1 + 0.2, 30 / 100)
  pump = x$scope$pump
  x$scope$pump = function(loop, ...) {
    pump(loop, ...)
    x$state$milliseconds = max(300L, x$state$milliseconds)
  }
  x$scope$nap = function(seconds) {
    x$state$naps = c(x$state$naps, seconds)
    x$state$milliseconds = x$state$milliseconds + as.integer(1000 * seconds + 0.5)
  }
  seen = tryCatch(x$close(), error = identity)
  expect_identical(list(
    closed = is.null(seen),
    condition = if (inherits(seen, "condition")) class(seen) else character(),
    condition_message = if (inherits(seen, "condition")) conditionMessage(seen) else character(),
    positive_waits = length(x$state$naps) > 0L && all(x$state$naps >= 0.001),
    bounded_waits = all(x$state$naps <= 0.01),
    grace_finished = x$scope$clock()[["elapsed"]] >= 0.1 + 0.2,
    within_deadline = x$scope$clock()[["elapsed"]] < 10.1,
    bounded_steps = length(x$state$pump_timeouts) < 64L,
    dead = !x$state$alive,
    inactive = !x$state$active,
    browser_cleared = is.null(x$scope$artifact_state$browser),
    owner_cleared = is.null(x$scope$artifact_state$browser_owner)
  ), list(closed = TRUE, condition = character(), condition_message = character(),
    positive_waits = TRUE,
    bounded_waits = TRUE, grace_finished = TRUE, within_deadline = TRUE,
    bounded_steps = TRUE, dead = TRUE, inactive = TRUE,
    browser_cleared = TRUE, owner_cleared = TRUE))
})

test_that("browser cleanup retains ownership after deadline or clock failure", {
  for (mode in c("deadline", "stalled", "nonfinite", "backward")) {
    x = artifact_browser_fixture()
    if (mode %in% c("deadline", "nonfinite")) {
      pump = x$scope$pump
      x$scope$pump = function(loop, ...) {
        pump(loop, ...)
        if (mode == "deadline") {
          x$state$clock = x$state$clock + 11
        } else {
          x$scope$clock = function() c(elapsed = NA_real_)
        }
      }
    } else if (mode == "stalled") {
      x$scope$clock = function() c(elapsed = 0)
    } else {
      x$scope$clock = function() {
        x$state$clock = x$state$clock - 0.01
        c(elapsed = x$state$clock)
      }
    }
    seen = tryCatch(x$close(), error = identity)
    expect_s3_class(seen, "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_true(x$state$alive)
    expect_false(any(x$state$events %in% c("process", "wait")))
    expect_identical(x$state$events[[1L]], "websocket")
    if (mode %in% c("stalled", "backward")) {
      expect_length(x$state$pump_timeouts, 64L)
    } else {
      expect_length(x$state$pump_timeouts, 1L)
    }
  }
})

test_that("delayed browser callbacks preserve exact conditions and replacement caches", {
  for (kind in c("error", "interrupt")) {
    x = artifact_browser_fixture()
    original = structure(list(message = "controlled delayed callback", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$pump_error = original
    pump = x$scope$pump
    x$scope$pump = function(loop, ...) {
      force(list(...))
      x$state$clock = x$state$clock + 11
      pump(loop, ...)
    }
    seen = tryCatch(x$close(), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_true(x$state$alive)
    expect_false(any(x$state$events %in% c("process", "wait")))
  }
  for (field in c("browser", "owner")) {
    x = artifact_browser_fixture()
    x$state[[paste0("replace_", field)]] = TRUE
    pump = x$scope$pump
    x$scope$pump = function(loop, ...) {
      x$state$clock = x$state$clock + 0.31
      pump(loop, ...)
    }
    seen = tryCatch(x$close(), error = identity)
    expect_s3_class(seen, "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser,
      if (field == "browser") x$replacement else x$container)
    expect_identical(x$scope$artifact_state$browser_owner,
      if (field == "owner") x$replacement else x$owner)
    expect_true(x$state$alive)
    expect_false(any(x$state$events %in% c("process", "wait")))
  }
})

test_that("an owned connected browser requests ordinary close before its adapter disconnects", {
  x = artifact_browser_fixture()
  x$state$cdp_dead = TRUE
  expect_invisible(x$close())
  expect_identical(x$state$cdp_calls, 1L)
  expect_true(x$state$cdp_timeout > 0 && x$state$cdp_timeout < 10)
  expect_identical(utils::head(x$state$close_order, 2L), c("browser", "websocket"))
  expect_false(any(x$state$close_order %in% c("process", "wait")))
  expect_false(x$state$alive)
  expect_false(x$state$active)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
  before = x$state$close_order
  expect_invisible(x$close())
  expect_identical(x$state$close_order, before)
})

test_that("ordinary owned-browser close preserves errors and interrupts before disconnect", {
  for (kind in c("error", "interrupt")) {
    x = artifact_browser_fixture()
    original = structure(list(message = "controlled owned browser command", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$cdp_error = original
    x$state$draw_close = TRUE
    seed_present = exists(".Random.seed", globalenv(), inherits = FALSE)
    seed = get0(".Random.seed", globalenv(), inherits = FALSE)
    objects = ls(envir = globalenv(), all.names = TRUE)
    seen = tryCatch(x$close(), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$state$cdp_calls, 1L)
    expect_identical(x$state$close_order, "browser")
    expect_true(x$state$alive)
    expect_true(x$state$active)
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_identical(exists(".Random.seed", globalenv(), inherits = FALSE), seed_present)
    expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
    expect_identical(ls(envir = globalenv(), all.names = TRUE), objects)
    x$state$cdp_error = NULL
    expect_invisible(x$close())
    expect_identical(x$state$cdp_calls, 2L)
    expect_null(x$scope$artifact_state$browser)
    expect_null(x$scope$artifact_state$browser_owner)
  }
})

test_that("ordinary browser commands never reach borrowed dead or mismatched owners", {
  control = artifact_browser_fixture()
  expect_invisible(control$close())
  expect_identical(control$state$cdp_calls, 1L)
  for (mode in c("borrowed", "dead", "mismatched", "unconnected", "inactive")) {
    x = artifact_browser_fixture(local = if (mode == "borrowed") FALSE else TRUE)
    x$state$cdp_error = simpleError("the unowned browser command must not run")
    if (mode == "dead") x$state$alive = FALSE
    if (mode == "mismatched") x$state$port = 9999L
    if (mode == "unconnected") x$scope$artifact_state$browser = NULL
    if (mode == "inactive") x$state$active = FALSE
    seen = tryCatch(x$close(), error = identity)
    if (mode == "mismatched") {
      expect_s3_class(seen, "gptr_error_io")
      expect_identical(x$state$events, character())
      expect_identical(x$scope$artifact_state$browser, x$container)
    } else {
      expect_null(seen)
      expect_null(x$scope$artifact_state$browser)
    }
    expect_identical(x$state$cdp_calls, 0L)
    expect_false("browser" %in% x$state$close_order)
    if (mode %in% c("borrowed", "dead", "mismatched")) {
      expect_false(any(x$state$close_order %in% c("process", "wait")))
    } else {
      expect_identical(utils::tail(x$state$close_order, 2L), c("process", "wait"))
    }
  }
})

test_that("ordinary browser close retains the existing bounded exact-owner fallback", {
  x = artifact_browser_fixture()
  expect_invisible(x$close())
  expect_identical(x$state$cdp_calls, 1L)
  expect_true(x$state$cdp_timeout > 0 && x$state$cdp_timeout < 10)
  expect_identical(utils::head(x$state$close_order, 2L), c("browser", "websocket"))
  expect_identical(utils::tail(x$state$close_order, 2L), c("process", "wait"))
  expect_true(x$state$wait_timeout > 0 && x$state$wait_timeout < 10000)
  expect_false(x$state$alive)
  x = artifact_browser_fixture()
  x$state$cdp_delay = 11
  seen = tryCatch(x$close(), error = identity)
  expect_s3_class(seen, "gptr_error_io")
  expect_identical(x$state$cdp_calls, 1L)
  expect_identical(x$state$close_order, "browser")
  expect_true(x$state$alive)
  expect_true(x$state$active)
  expect_identical(x$scope$artifact_state$browser, x$container)
  expect_identical(x$scope$artifact_state$browser_owner, x$owner)
})


test_that("owned browser disconnect waits for the close acknowledgment", {
  x = artifact_browser_fixture()
  x$state$cdp_delay = 0.25
  x$state$cdp_dead = TRUE
  expect_invisible(x$close())
  expect_identical(x$state$disconnect_acknowledged, TRUE)
  expect_true(x$state$clock >= 0.25)
  expect_true(x$state$cdp_timeout > 0 && x$state$cdp_timeout < 10)
  expect_identical(utils::head(x$state$close_order, 2L), c("browser", "websocket"))
  expect_false(any(x$state$close_order %in% c("process", "wait")))
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
})

test_that("owned browser acknowledgment failures retain the connection for retry", {
  for (kind in c("error", "interrupt")) {
    x = artifact_browser_fixture()
    original = structure(list(message = "controlled close acknowledgment", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$cdp_ack_error = original
    x$state$draw_close = TRUE
    seed_present = exists(".Random.seed", globalenv(), inherits = FALSE)
    seed = get0(".Random.seed", globalenv(), inherits = FALSE)
    objects = ls(envir = globalenv(), all.names = TRUE)
    seen = tryCatch(x$close(), error = identity, interrupt = identity)
    held = list(condition = seen, order = x$state$close_order,
      alive = x$state$alive, active = x$state$active,
      browser = identical(x$scope$artifact_state$browser, x$container),
      owner = identical(x$scope$artifact_state$browser_owner, x$owner),
      acknowledged = x$state$cdp_acknowledged,
      seed_unchanged =
        identical(exists(".Random.seed", globalenv(), inherits = FALSE), seed_present) &&
        identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed),
      objects_unchanged = identical(ls(envir = globalenv(), all.names = TRUE), objects))
    x$state$cdp_ack_error = NULL
    expect_invisible(x$close())
    expect_identical(list(held = held, commands = x$state$cdp_calls),
      list(held = list(condition = original, order = "browser", alive = TRUE, active = TRUE,
        browser = TRUE, owner = TRUE, acknowledged = FALSE, seed_unchanged = TRUE,
        objects_unchanged = TRUE), commands = 2L))
    expect_null(x$scope$artifact_state$browser)
    expect_null(x$scope$artifact_state$browser_owner)
  }
})
