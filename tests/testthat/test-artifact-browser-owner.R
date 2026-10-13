test_that("a cold artifact browser separately owns Chrome and reuses its remote connection", {
  x = artifact_owner_fixture()
  x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
  b = x$open()
  expect_identical(x$scope$artifact_state$browser, b)
  expect_identical(x$scope$artifact_state$browser_owner, x$owner)
  expect_false(b$get_browser()$is_local())
  expect_null(b$get_browser()$get_process())
  expect_identical(b$get_browser()$get_host(), "127.0.0.1")
  expect_identical(b$get_browser()$get_port(), x$owner$get_port())
  expect_identical(x$open(), b)
  expect_identical(x$state$owner_calls, 1L)
  expect_identical(x$state$container_calls, 1L)
  expect_identical(x$state$events, character())
})

test_that("owned artifact disconnect settles its loop before signalling and waiting once", {
  x = artifact_owner_fixture()
  expect_invisible(x$close())
  expect_identical(x$state$events[[1L]], "websocket")
  expect_identical(utils::tail(x$state$events, 2L), c("process", "wait"))
  expect_true(x$state$alive_at_pump)
  expect_true(all(x$state$events[2:(length(x$state$events) - 2L)] == "pump"))
  expect_true(length(x$state$pump_timeouts) > 0L)
  expect_true(all(x$state$pump_timeouts > 0 & x$state$pump_timeouts <= 0.02))
  expect_false("legacy-rpc" %in% x$state$events)
  expect_false(x$state$alive)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
  previous = x$state$events
  expect_invisible(x$close())
  expect_identical(x$state$events, previous)
})

test_that("artifact owner uncertainty and endpoint changes cannot signal a process", {
  for (which in c("local", "alive", "endpoint")) {
    x = artifact_owner_fixture()
    if (which == "local") x$state$local = NA
    if (which == "alive") x$state$alive = NA
    if (which == "endpoint") x$state$port = 9876L
    expect_error(x$close(), class = "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_identical(x$state$events, character())
    expect_error(x$open(), class = "gptr_error_io")
    expect_identical(x$state$owner_calls, 0L)
  }
  for (active in list(FALSE, NA, 0, NULL)) {
    x = artifact_owner_fixture()
    x$state$active = active
    expect_error(x$open(), class = "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_identical(x$state$owner_calls, 0L)
    expect_identical(x$state$events, character())
  }
  for (kind in c("error", "interrupt")) {
    x = artifact_owner_fixture()
    original = structure(list(message = "controlled active query", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$active_error = original
    seen = tryCatch(x$open(), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_identical(x$state$events, character())
  }
})

test_that(
  "artifact constructor unwind settles only its retained owner and preserves primary conditions", {
  for (kind in c("error", "interrupt")) {
    for (cleanup_fails in c(FALSE, TRUE)) {
      x = artifact_owner_fixture()
      x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
      original = structure(list(message = "controlled attachment failure", call = NULL),
        class = c(paste0("controlled_", kind), kind, "condition"))
      x$state$factory_error = original
      if (cleanup_fails) x$state$wait_error = simpleError("controlled secondary wait")
      seen = tryCatch(x$open(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(x$state$events, c("process", "wait"))
      expect_null(x$scope$artifact_state$browser)
      if (cleanup_fails) {
        expect_identical(x$scope$artifact_state$browser_owner, x$owner)
        expect_true(x$state$alive)
      } else {
        expect_null(x$scope$artifact_state$browser_owner)
        expect_false(x$state$alive)
      }
    }
  }
  for (field in c("browser", "owner", "both", "pending", "all")) {
    for (outcome in c("return", "error", "interrupt")) {
      for (cleanup in c("return", "error", "interrupt")) {
        x = artifact_owner_fixture()
        x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
        x$state$replace_construct = field
        original = structure(list(message = "controlled replaced attachment", call = NULL),
          class = c(paste0("controlled_", outcome), outcome, "condition"))
        if (outcome != "return") x$state$factory_error = original
        if (cleanup != "return") {
          x$state$wait_error = structure(list(message = "controlled pending wait", call = NULL),
            class = c(paste0("controlled_", cleanup), cleanup, "condition"))
        }
        seen = tryCatch(x$open(), error = identity, interrupt = identity)
        if (outcome == "return") {
          expect_s3_class(seen, "gptr_error_io")
        } else {
          expect_identical(seen, original)
        }
        foreign_browser = if (field %in% c("browser", "both", "all")) x$replacement else NULL
        foreign_owner = if (field %in% c("owner", "both", "all")) x$replacement else NULL
        expect_identical(x$scope$artifact_state$browser, foreign_browser)
        expect_identical(x$state$owner_calls, 1L)
        expect_identical(x$state$container_calls, 1L)
        if (cleanup == "return") {
          expect_null(x$scope$artifact_state$browser_pending)
          expect_identical(x$scope$artifact_state$browser_owner, foreign_owner)
          expect_false(x$state$alive)
        } else {
          lease = x$scope$artifact_state$browser_pending
          expect_identical(lease$owner, x$owner)
          expect_identical(lease$browser, x$state$constructed)
          expect_identical(x$scope$artifact_state$browser_owner,
            if (is.null(foreign_owner)) x$owner else foreign_owner)
          expect_true(x$state$alive)
          expect_error(x$open(), class = "gptr_error_io")
          expect_identical(x$scope$artifact_state$browser_pending, lease)
          expect_identical(x$scope$artifact_state$browser, foreign_browser)
          expect_identical(x$state$owner_calls, 1L)
          x$state$wait_error = NULL
          expect_invisible(x$close())
          expect_null(x$scope$artifact_state$browser_pending)
          expect_identical(x$scope$artifact_state$browser, foreign_browser)
          expect_identical(x$scope$artifact_state$browser_owner, foreign_owner)
          expect_false(x$state$alive)
        }
      }
    }
  }
  for (field in c("browser", "owner", "both", "pending", "all")) {
    for (cleanup in c("return", "error", "interrupt")) {
      x = artifact_owner_fixture()
      x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
      x$state$replace_launch = field
      if (cleanup != "return") {
        x$state$wait_error = structure(list(message = "controlled launch cleanup", call = NULL),
          class = c(paste0("controlled_", cleanup), cleanup, "condition"))
      }
      seen = tryCatch(x$open(), error = identity, interrupt = identity)
      expect_s3_class(seen, "gptr_error_io")
      foreign_browser = if (field %in% c("browser", "both", "all")) x$replacement else NULL
      foreign_owner = if (field %in% c("owner", "both", "all")) x$replacement else NULL
      expect_identical(x$scope$artifact_state$browser, foreign_browser)
      expect_identical(x$scope$artifact_state$browser_owner, foreign_owner)
      expect_identical(x$state$owner_calls, 1L)
      expect_identical(x$state$container_calls, 0L)
      expect_identical(x$state$events, c("process", "wait"))
      if (cleanup == "return") {
        expect_null(x$scope$artifact_state$browser_pending)
        expect_false(x$state$alive)
      } else {
        lease = x$scope$artifact_state$browser_pending
        expect_identical(lease, list(browser = NULL, owner = x$owner))
        expect_true(x$state$alive)
        expect_error(x$open(), class = "gptr_error_io")
        expect_identical(x$state$owner_calls, 1L)
        x$state$wait_error = NULL
        expect_invisible(x$close())
        expect_null(x$scope$artifact_state$browser_pending)
        expect_identical(x$scope$artifact_state$browser, foreign_browser)
        expect_identical(x$scope$artifact_state$browser_owner, foreign_owner)
        expect_false(x$state$alive)
      }
    }
  }
  for (kind in c("error", "interrupt")) {
    x = artifact_owner_fixture()
    x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
    x$state$replace_construct = "both"
    x$state$wait_error = simpleError("controlled first pending cleanup")
    expect_error(x$open(), class = "gptr_error_io")
    lease = x$scope$artifact_state$browser_pending
    original = structure(list(message = "controlled replaced pending cleanup", call = NULL),
      class = c(paste0("controlled_", kind), kind, "condition"))
    x$state$replace_pending_wait = TRUE
    x$state$wait_error = original
    seen = tryCatch(x$close(), error = identity, interrupt = identity)
    expect_identical(seen, original)
    expect_identical(x$scope$artifact_state$browser_pending, lease)
    expect_identical(x$scope$artifact_state$browser, x$replacement)
    expect_identical(x$scope$artifact_state$browser_owner, x$replacement)
    expect_true(x$state$alive)
    x$state$replace_pending_wait = FALSE
    x$state$wait_error = NULL
    expect_invisible(x$close())
    expect_null(x$scope$artifact_state$browser_pending)
    expect_false(x$state$alive)
    expect_identical(x$scope$artifact_state$browser, x$replacement)
    expect_identical(x$scope$artifact_state$browser_owner, x$replacement)
  }
})

test_that("foreign remote artifacts and already dead local owners receive no process signal", {
  x = artifact_owner_fixture(remote = TRUE)
  expect_invisible(x$close())
  expect_identical(x$state$events, "websocket")
  expect_true(x$state$alive)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
  x = artifact_owner_fixture()
  x$state$alive = FALSE
  expect_invisible(x$close())
  expect_identical(utils::tail(x$state$events, 1L), "websocket")
  expect_true(all(utils::head(x$state$events, -1L) == "pump"))
  expect_false(x$state$alive_at_pump)
  expect_null(x$scope$artifact_state$browser)
  expect_null(x$scope$artifact_state$browser_owner)
})

test_that("artifact replacement caches cannot be discarded or used for a local signal", {
  for (which in c("browser", "owner")) {
    x = artifact_owner_fixture()
    x$state[[paste0("replace_", which)]] = TRUE
    expect_error(x$close(), class = "gptr_error_io")
    field = if (which == "browser") "browser" else "browser_owner"
    expect_identical(x$scope$artifact_state[[field]], x$replacement)
    expect_true(x$state$alive)
    expect_false("process" %in% x$state$events)
  }
})

test_that(
  "artifact waits retain live owners and reject responses after the shared close deadline", {
  for (late in c(FALSE, TRUE)) {
    x = artifact_owner_fixture()
    if (late) x$state$wait_jump = 11 else x$state$wait_dead = FALSE
    expect_error(x$close(), class = "gptr_error_io")
    expect_identical(x$scope$artifact_state$browser, x$container)
    expect_identical(x$scope$artifact_state$browser_owner, x$owner)
    expect_true(x$state$wait_timeout < 10000)
  }
})

test_that("artifact close errors and interrupts preserve exact conditions and retry ownership", {
  for (which in c("query_error", "socket_error", "loop_error", "pump_error",
                 "process_error", "wait_error")) {
    for (kind in c("error", "interrupt")) {
      x = artifact_owner_fixture()
      original = structure(list(message = "controlled owned close", call = NULL),
        class = c(paste0("controlled_", kind), kind, "condition"))
      x$state[[which]] = original
      seen = tryCatch(x$close(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(x$scope$artifact_state$browser, x$container)
      expect_identical(x$scope$artifact_state$browser_owner, x$owner)
      if (which %in% c("process_error", "wait_error")) {
        expect_false(x$state$active)
        expect_true(x$state$alive)
        expect_error(x$open(), class = "gptr_error_io")
        expect_identical(x$scope$artifact_state$browser, x$container)
        expect_identical(x$scope$artifact_state$browser_owner, x$owner)
        expect_identical(x$state$owner_calls, 0L)
      }
      x$state[[which]] = NULL
      expect_invisible(x$close())
      expect_null(x$scope$artifact_state$browser)
      expect_null(x$scope$artifact_state$browser_owner)
      expect_false(x$state$alive)
    }
  }
})

test_that("artifact owner construction and loop callbacks preserve seeded and absent caller RNG", {
  for (seeded in c(FALSE, TRUE)) {
    for (which in c("open", "close", "replaced", "launch")) {
      for (failed in c(FALSE, TRUE)) {
        local({
          withr::local_preserve_seed()
          if (seeded) {
            set.seed(173L)
          } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
            rm(list = ".Random.seed", envir = globalenv())
          }
          seed = get0(".Random.seed", globalenv(), inherits = FALSE)
          objects = ls(envir = globalenv(), all.names = TRUE)
          x = artifact_owner_fixture()
          x$state$draw = TRUE
          original = simpleError("controlled RNG unwind")
          if (which %in% c("open", "replaced", "launch")) {
            x$scope$artifact_state$browser = x$scope$artifact_state$browser_owner = NULL
            if (which == "replaced") {
              x$state$replace_construct = "both"
              x$state$wait_error = simpleError("controlled pending RNG cleanup")
            }
            if (which == "launch") {
              x$state$replace_launch = "all"
              if (failed) x$state$wait_error = original
            } else if (failed) {
              x$state$factory_error = original
            }
          } else if (failed) {
            x$state$pump_error = original
          }
          action = if (which %in% c("replaced", "launch")) "open" else which
          seen = tryCatch(x[[action]](), error = identity)
          if (failed && which != "launch") expect_identical(seen, original)
          if (which == "launch") {
            expect_s3_class(seen, "gptr_error_io")
            expect_identical(x$scope$artifact_state$browser, x$replacement)
            expect_identical(x$scope$artifact_state$browser_owner, x$replacement)
            expect_identical(x$state$container_calls, 0L)
            if (failed) {
              expect_identical(x$scope$artifact_state$browser_pending$owner, x$owner)
            } else {
              expect_null(x$scope$artifact_state$browser_pending)
            }
          }
          if (which == "replaced") {
            if (!failed) expect_s3_class(seen, "gptr_error_io")
            expect_identical(x$scope$artifact_state$browser, x$replacement)
            expect_identical(x$scope$artifact_state$browser_owner, x$replacement)
            expect_identical(x$scope$artifact_state$browser_pending$owner, x$owner)
          }
          expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
          expect_identical(ls(envir = globalenv(), all.names = TRUE), objects)
        })
      }
    }
  }
})
