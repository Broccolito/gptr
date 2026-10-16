# Clone the actual owned pump and replace only its native run_now call head.
later_pump_pure = function(callback, loaded = TRUE) {
  state = new.env(parent = emptyenv())
  state$calls = 0L
  state$diagnostics = list()
  replace = function(expr) {
    if (identical(expr, quote(later::run_now))) return(as.name("run_now"))
    if (is.call(expr)) {
      for (i in seq_along(expr)) expr[i] = list(replace(expr[[i]]))
    }
    expr
  }
  pump = later_run_now
  body(pump) = replace(body(pump))
  environment(pump) = list2env(list(
    isNamespaceLoaded = function(package) {
      expect_identical(package, "later")
      loaded
    },
    run_now = function(timeout_secs) {
      expect_identical(timeout_secs, 0)
      state$calls = state$calls + 1L
      callback()
    },
    registry_diagnostic = function(source, event, category, message) {
      state$diagnostics[[length(state$diagnostics) + 1L]] =
        list(source = source, event = event, category = category, message = message)
    }), parent = environment(later_run_now))
  list(pump = pump, state = state)
}

test_that("an owned later pump restores ambient RNG while callback results and writes survive", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(73L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      before = get0(".Random.seed", globalenv(), inherits = FALSE)
      effects = new.env(parent = emptyenv())
      effects$count = 0L
      x = later_pump_pure(function() {
        effects$result = stats::runif(2L)
        effects$inside = get0(".Random.seed", globalenv(), inherits = FALSE)
        effects$count = effects$count + 1L
        effects$result
      })
      expect_identical(withVisible(x$pump()), list(value = TRUE, visible = FALSE))
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      expect_false(identical(effects$inside, before))
      expect_type(effects$result, "double")
      expect_length(effects$result, 2L)
      expect_true(all(is.finite(effects$result) & effects$result >= 0 & effects$result < 1))
      expect_identical(effects$count, 1L)
      expect_identical(x$state$calls, 1L)
      expect_identical(x$state$diagnostics, list())
    })
  }
})

test_that("an owned later pump keeps independent agent RNG advancement", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(73L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      before = get0(".Random.seed", globalenv(), inherits = FALSE)
      agent = new.env(parent = emptyenv())
      agent$id = "synthetic-owned-pump-agent"
      agent$seed = rng_seeds(agent$id)
      first = agent$seed
      reference = new.env(parent = emptyenv())
      reference$id = agent$id
      reference$seed = first
      expected = rng_swap(reference, stats::runif(4L))
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      effects = new.env(parent = emptyenv())
      effects$values = numeric()
      x = later_pump_pure(function() {
        rng_swap(agent, {
          effects$values = c(effects$values, stats::runif(2L))
        })
      })
      expect_true(x$pump())
      second = agent$seed
      expect_false(identical(second, first))
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      expect_true(x$pump())
      expect_false(identical(agent$seed, second))
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      expect_length(effects$values, 4L)
      expect_identical(effects$values, expected)
      expect_identical(agent$seed, reference$seed)
      expect_false(identical(effects$values[1:2], effects$values[3:4]))
      expect_identical(x$state$calls, 2L)
    })
  }
})

test_that("an owned later pump restores ambient RNG after diagnosing a callback error", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(73L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      before = get0(".Random.seed", globalenv(), inherits = FALSE)
      x = later_pump_pure(function() {
        stats::runif(2L)
        stop("synthetic callback failure")
      })
      expect_identical(withVisible(x$pump()), list(value = TRUE, visible = FALSE))
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      expect_identical(x$state$diagnostics,
        list(list(source = "reactor", event = "later", category = "error",
                  message = "synthetic callback failure")))
      expect_identical(x$state$calls, 1L)
    })
  }
})

test_that("an owned later pump preserves its original interrupt and ambient RNG", {
  for (seeded in c(FALSE, TRUE)) {
    local({
      withr::local_preserve_seed()
      if (seeded) {
        set.seed(73L)
      } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
        rm(list = ".Random.seed", envir = globalenv())
      }
      before = get0(".Random.seed", globalenv(), inherits = FALSE)
      original = structure(list(message = "synthetic callback interrupt", call = NULL),
        class = c("synthetic_interrupt", "interrupt", "condition"))
      x = later_pump_pure(function() {
        stats::runif(2L)
        stop(original)
      })
      seen = tryCatch(x$pump(), error = identity, interrupt = identity)
      expect_identical(seen, original)
      expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
      expect_identical(x$state$diagnostics, list())
      expect_identical(x$state$calls, 1L)
    })
  }
})

test_that("an unloaded later pump returns invisibly without callbacks or state changes", {
  withr::local_preserve_seed()
  before = get0(".Random.seed", globalenv(), inherits = FALSE)
  x = later_pump_pure(function() stop("No callback is allowed"), loaded = FALSE)
  expect_identical(withVisible(x$pump()), list(value = FALSE, visible = FALSE))
  expect_identical(x$state$calls, 0L)
  expect_identical(x$state$diagnostics, list())
  expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), before)
})
