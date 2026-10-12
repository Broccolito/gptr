# Replace only the native stop call in the actual function; start no optional namespace/server.
mcp_stop_pure = function(stopper) {
  state = new.env(parent = emptyenv())
  state$order = character()
  state$server = new.env(parent = emptyenv())
  state$server$srv = new.env(parent = emptyenv())
  state$server$srv$isRunning = function() FALSE
  state$server$url = "http://synthetic-loopback/mcp"
  state$server$job = "synthetic-mcp-job"
  state$shared = new.env(parent = emptyenv())
  state$shared$data = c(2L, 4L, 6L)
  for (field in c("envir", "user", "handle")) state$server[[field]] = state$shared
  state$the = new.env(parent = emptyenv())
  state$the$mcp_server = state$server
  state$the$mcp_tokens = new.env(parent = emptyenv())
  state$the$mcp_tokens$first = list(id = "synthetic-first", handle = "synthetic-handle")
  state$the$mcp_tokens$second = list(id = "synthetic-second", handle = "synthetic-handle")
  replace = function(expr) {
    if (identical(expr, quote(httpuv::stopServer))) return(as.name("stop_server"))
    if (is.call(expr)) {
      for (i in seq_along(expr)) expr[i] = list(replace(expr[[i]]))
    }
    expr
  }
  stop = mcp_serve_stop
  body(stop) = replace(body(stop))
  environment(stop) = list2env(list(the = state$the,
    stop_server = function(server) {
      state$order = c(state$order, "stop")
      expect_identical(server, state$server$srv)
      stopper()
    },
    job_remove = function(job) {
      state$order = c(state$order, "job")
      state$removed_job = job
    },
    ev_dispatch = function(name, data) {
      state$order = c(state$order, "event")
      state$event = list(name = name, data = data)
    }), parent = environment(mcp_serve_stop))
  list(stop = stop, state = state)
}

test_that("owned MCP stop preserves seeded and absent RNG while revoking its tokens", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(73L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      seed = get0(".Random.seed", globalenv(), inherits = FALSE)
      x = mcp_stop_pure(function() {
        stats::runif(2L)
        invisible(NULL)
      })
      expect_invisible(x$stop())
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
      expect_null(x$state$the$mcp_server)
      expect_identical(ls(x$state$the$mcp_tokens), character())
      expect_null(x$state$server$envir)
      expect_null(x$state$server$user)
      expect_null(x$state$server$handle)
      expect_identical(x$state$shared$data, c(2L, 4L, 6L))
      expect_identical(x$state$order, c("stop", "job", "event"))
      expect_identical(x$state$removed_job, "synthetic-mcp-job")
      expect_identical(x$state$event,
        list(name = "mcp_serve_stop", data = list(url = "http://synthetic-loopback/mcp")))
    })
  }
})

test_that("owned MCP stop retains the original error or interrupt and caller RNG", {
  for (outcome in c("error", "interrupt")) {
    for (seeded in c(FALSE, TRUE)) {
      local({
        withr::local_preserve_seed()
        if (seeded) {
          set.seed(73L)
        } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        original = structure(list(message = "synthetic native stop condition", call = NULL),
          class = c(paste0("synthetic_", outcome), outcome, "condition"))
        seed = get0(".Random.seed", globalenv(), inherits = FALSE)
        x = mcp_stop_pure(function() {
          stats::runif(2L)
          stop(original)
        })
        seen = tryCatch(x$stop(), error = identity, interrupt = identity)
        expect_identical(seen, original)
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
        expect_identical(x$state$shared$data, c(2L, 4L, 6L))
      })
    }
  }
})

test_that("an inactive MCP stop is invisible and performs no native or cleanup call", {
  withr::local_preserve_seed()
  x = mcp_stop_pure(function() stop("No native stop is allowed"))
  x$state$the$mcp_server = NULL
  seed = get0(".Random.seed", globalenv(), inherits = FALSE)
  expect_false(withVisible(x$stop())$visible)
  expect_identical(x$stop(), FALSE)
  expect_identical(x$state$order, character())
  expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
})

test_that("failed MCP stop revokes access and keeps the owned server available for retry", {
  for (outcome in c("error", "interrupt")) {
    for (running in list(TRUE, NA)) {
      local({
        withr::local_preserve_seed()
        if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        original = structure(list(message = "synthetic stop condition", call = NULL),
          class = c(paste0("synthetic_", outcome), outcome, "condition"))
        native = new.env(parent = emptyenv())
        native$running = running
        native$fail = TRUE
        x = mcp_stop_pure(function() {
          stats::runif(1L)
          if (native$fail) stop(original)
          native$running = FALSE
        })
        x$state$server$srv$isRunning = function() native$running
        seen = tryCatch(x$stop(), error = identity, interrupt = identity)
        expect_identical(seen, original)
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), NULL)
        expect_identical(ls(x$state$the$mcp_tokens), character())
        for (field in c("envir", "user", "handle")) {
          expect_null(x$state$server[[field]])
        }
        expect_identical(x$state$the$mcp_server, x$state$server)
        expect_true(x$state$server$stopping)
        expect_null(x$state$removed_job)
        expect_identical(x$state$shared$data, c(2L, 4L, 6L))
        native$fail = FALSE
        expect_identical(withVisible(x$stop()), list(value = TRUE, visible = FALSE))
        expect_null(x$state$the$mcp_server)
        expect_identical(x$state$removed_job, "synthetic-mcp-job")
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), NULL)
      })
    }
  }
})

test_that("unknown MCP stop confirmation never reports success or drops recovery ownership", {
  for (outcome in c("running", "unknown", "string", "vector", "error", "interrupt")) {
    local({
      withr::local_seed(73L)
      seed = get(".Random.seed", envir = globalenv())
      x = mcp_stop_pure(function() stats::runif(1L))
      x$state$server$srv$isRunning = function() {
        if (outcome == "running") return(TRUE)
        if (outcome == "unknown") return(NA)
        if (outcome == "string") return("FALSE")
        if (outcome == "vector") return(c(FALSE, FALSE))
        stop(structure(list(message = "synthetic confirmation condition", call = NULL),
          class = c(outcome, "condition")))
      }
      seen = tryCatch(x$stop(), error = identity, interrupt = identity)
      expect_s3_class(seen, "gptr_error_state_restore")
      expect_identical(get(".Random.seed", envir = globalenv()), seed)
      expect_identical(x$state$the$mcp_server, x$state$server)
      expect_true(x$state$server$stopping)
      expect_identical(ls(x$state$the$mcp_tokens), character())
      for (field in c("envir", "user", "handle")) expect_null(x$state$server[[field]])
      expect_null(x$state$removed_job)
      expect_null(x$state$event)
    })
  }
  for (failure in c("tokens", "error", "interrupt")) {
    local({
      withr::local_seed(73L)
      seed = get(".Random.seed", envir = globalenv())
      x = mcp_stop_pure(function() stats::runif(1L))
      if (failure == "tokens") {
        lockEnvironment(x$state$the$mcp_tokens)
      } else {
        shared = x$state$shared
        rm(list = "envir", envir = x$state$server)
        makeActiveBinding("envir", function(value) {
          if (missing(value)) return(shared)
          stop(structure(list(message = "synthetic release condition", call = NULL),
            class = c(failure, "condition")))
        }, x$state$server)
      }
      expect_error(x$stop(), class = "gptr_error_state_restore")
      expect_identical(get(".Random.seed", envir = globalenv()), seed)
      expect_identical(x$state$the$mcp_server, x$state$server)
      expect_true(x$state$server$stopping)
      expect_null(x$state$server$user)
      expect_null(x$state$server$handle)
      expect_null(x$state$removed_job)
      if (failure == "tokens") {
        expect_identical(ls(x$state$the$mcp_tokens), c("first", "second"))
        expect_null(x$state$server$envir)
      } else {
        expect_identical(ls(x$state$the$mcp_tokens), character())
        expect_identical(x$state$server$envir, x$state$shared)
      }
    })
  }
})

test_that("a stopping MCP listener refuses new serving tokens and HTTP dispatch", {
  x = mcp_stop_pure(function() NULL)
  x$state$server$stopping = TRUE
  calls = new.env(parent = emptyenv())
  calls$loads = 0L
  calls$sessions = 0L
  calls$routes = 0L
  start = mcp_serve_start
  environment(start) = list2env(list(the = x$state$the,
    oauth_need = function(...) {
      calls$loads = calls$loads + 1L
      stop("No initialization may run while stop is pending")
    }), parent = environment(mcp_serve_start))
  token = mcp_serve_token
  environment(token) = list2env(list(the = x$state$the,
    session_data = function(session) {
      calls$sessions = calls$sessions + 1L
      list(id = "synthetic-first")
    }, secret_value = function(...) "synthetic-value"), parent = environment(mcp_serve_token))
  handle = mcp_http_handle
  environment(handle) = list2env(list(mcp_http_route = function(...) {
    calls$routes = calls$routes + 1L
    list(status = 200L)
  }), parent = environment(mcp_http_handle))
  expect_error(start(), class = "gptr_error_not_available")
  expect_error(token(new.env(parent = emptyenv())), class = "gptr_error_not_available")
  expect_identical(handle(x$state$server, list())$status, 503L)
  public = gptr_mcp_serve
  environment(public) = list2env(list(the = x$state$the,
    ext_control_guard = function(...) invisible(NULL),
    mcp_serve_start = function(...) {
      calls$loads = calls$loads + 1L
      x$state$server
    }), parent = environment(gptr_mcp_serve))
  x$state$server$handle = x$state$shared
  expect_error(public(envir = new.env(parent = emptyenv())),
               class = "gptr_error_not_available")
  expect_identical(calls$loads, 0L)
  expect_identical(calls$sessions, 0L)
  expect_identical(calls$routes, 0L)
  expect_identical(x$state$the$mcp_server, x$state$server)
})

test_that("confirmed MCP stop still cleans ownership before rethrowing its original condition", {
  for (outcome in c("error", "interrupt")) {
    local({
      withr::local_seed(73L)
      seed = get(".Random.seed", envir = globalenv())
      original = structure(list(message = "synthetic post-stop condition", call = NULL),
        class = c(paste0("synthetic_", outcome), outcome, "condition"))
      x = mcp_stop_pure(function() {
        stats::runif(1L)
        stop(original)
      })
      x$state$server$srv$isRunning = function() FALSE
      seen = tryCatch(x$stop(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(get(".Random.seed", envir = globalenv()), seed)
      expect_null(x$state$the$mcp_server)
      expect_identical(ls(x$state$the$mcp_tokens), character())
      for (field in c("envir", "user", "handle")) expect_null(x$state$server[[field]])
      expect_identical(x$state$removed_job, "synthetic-mcp-job")
      expect_identical(x$state$shared$data, c(2L, 4L, 6L))
    })
  }
  for (outcome in c("error", "interrupt")) {
    local({
      original = structure(list(message = "synthetic notification condition", call = NULL),
        class = c(outcome, "condition"))
      x = mcp_stop_pure(function() NULL)
      mock = environment(x$stop)
      mock$ev_dispatch = function(...) stop(original)
      expect_identical(tryCatch(x$stop(), error = identity, interrupt = identity), original)
      expect_null(x$state$the$mcp_server)
      expect_identical(x$state$removed_job, "synthetic-mcp-job")
      expect_identical(ls(x$state$the$mcp_tokens), character())
      x = mcp_stop_pure(function() stop(original))
      mock = environment(x$stop)
      mock$ev_dispatch = function(...) stop("secondary notification failure")
      expect_identical(tryCatch(x$stop(), error = identity, interrupt = identity), original)
      expect_null(x$state$the$mcp_server)
    })
  }
  x = mcp_stop_pure(function() NULL)
  mock = environment(x$stop)
  mock$ev_dispatch = function(...) {
    expect_identical(x$stop(), FALSE)
  }
  expect_identical(withVisible(x$stop()), list(value = TRUE, visible = FALSE))
  expect_identical(x$state$order, c("stop", "job"))
})
