# These controls load no optional namespace and start no server or child process.
oauth_cold_keys = c("PATH", "GIT_ASKPASS", "SSH_ASKPASS")

oauth_cold_values = function(value) {
  stats::setNames(rep(value, length(oauth_cold_keys)), oauth_cold_keys)
}

oauth_cold_env = function(values, .env = parent.frame()) {
  old = Sys.getenv(oauth_cold_keys, unset = NA_character_)
  if (.Platform$OS.type == "windows" && any(!is.na(old) & old == "")) {
    stop("Synthetic fixture cannot restore an existing empty Windows initialization value")
  }
  withr::local_envvar(values, .local_envir = .env)
  withr::local_preserve_seed(.local_envir = .env)
}

oauth_cold_need = function(loader, windows = FALSE, warm = FALSE, extra = list()) {
  need = oauth_need
  scope = list2env(c(list(requireNamespace = loader,
    is_windows = function() windows, isNamespaceLoaded = function(pkg) warm), extra),
    parent = environment(oauth_need))
  available = get0("oauth_available", envir = environment(oauth_need), inherits = FALSE)
  if (!is.null(available)) {
    environment(available) = scope
    scope$oauth_available = available
  }
  environment(need) = scope
  need
}

test_that("dependency setup restores PATH and askpass values and the caller RNG", {
  skip_on_cran()
  for (value in c(NA_character_, "synthetic-custom-askpass")) {
    for (seeded in c(FALSE, TRUE)) {
      local({
        oauth_cold_env(oauth_cold_values(value))
        if (seeded) {
          set.seed(42L)
        } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        before = Sys.getenv()
        seed = get0(".Random.seed", globalenv(), inherits = FALSE)
        state = new.env(parent = emptyenv())
        state$calls = 0L
        need = oauth_cold_need(function(pkg, quietly) {
          state$calls = state$calls + 1L
          do.call(Sys.setenv, as.list(oauth_cold_values("synthetic-loaded-askpass")))
          stats::runif(2L)
          TRUE
        })
        expect_invisible(need("openssl", "Synthetic dependency"))
        expect_identical(state$calls, 1L)
        expect_identical(Sys.getenv(), before)
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
      })
    }
  }
})

test_that("dependency setup restores state before missing errors and original conditions", {
  skip_on_cran()
  for (outcome in c("missing", "error", "interrupt")) {
    for (seeded in c(FALSE, TRUE)) {
      local({
        oauth_cold_env(oauth_cold_values(NA_character_))
        if (seeded) {
          set.seed(42L)
        } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        before = Sys.getenv()
        seed = get0(".Random.seed", globalenv(), inherits = FALSE)
        original = structure(list(message = "synthetic dependency condition", call = NULL),
          class = c(paste0("synthetic_", outcome), outcome, "condition"))
        need = oauth_cold_need(function(pkg, quietly) {
          do.call(Sys.setenv, as.list(oauth_cold_values("synthetic-loaded-askpass")))
          stats::runif(2L)
          if (outcome == "missing") FALSE else stop(original)
        })
        seen = tryCatch(need("openssl", "Synthetic dependency"), error = identity,
          interrupt = identity)
        if (outcome == "missing") {
          expect_s3_class(seen, "gptr_error_missing_package")
        } else {
          expect_identical(seen, original)
        }
        expect_identical(Sys.getenv(), before)
        expect_identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed)
      })
    }
  }
})

test_that("repeated warm dependency setup still restores changed askpass values", {
  skip_on_cran()
  oauth_cold_env(oauth_cold_values("synthetic-original-askpass"))
  before = Sys.getenv()
  state = new.env(parent = emptyenv())
  state$calls = 0L
  need = oauth_cold_need(function(pkg, quietly) {
    state$calls = state$calls + 1L
    do.call(Sys.setenv, as.list(oauth_cold_values("synthetic-loaded-askpass")))
    TRUE
  }, warm = TRUE)
  expect_invisible(need("openssl", "Synthetic dependency"))
  expect_invisible(need("openssl", "Synthetic dependency"))
  expect_identical(state$calls, 2L)
  expect_identical(Sys.getenv(), before)
})

test_that("POSIX empty initialization and untouched warm Windows empties stay exact", {
  if (.Platform$OS.type != "windows") {
    oauth_cold_env(oauth_cold_values(""))
    before = Sys.getenv()
    need = oauth_cold_need(function(pkg, quietly) {
      do.call(Sys.setenv, as.list(oauth_cold_values("synthetic-loaded-askpass")))
      TRUE
    })
    expect_invisible(need("openssl", "Synthetic dependency"))
    expect_identical(Sys.getenv(), before)
  }
  empty = oauth_cold_values("")
  restore = env_restore_python
  environment(restore) = list2env(list(Sys.getenv = function(...) empty,
    Sys.setenv = function(...) stop("An unchanged empty value must not be set"),
    Sys.unsetenv = function(...) stop("An unchanged empty value must not be removed")),
    parent = environment(env_restore_python))
  need = oauth_cold_need(function(pkg, quietly) TRUE, windows = TRUE, warm = TRUE,
    extra = list(Sys.getenv = function(...) empty, env_restore_python = restore))
  expect_invisible(need("openssl", "Synthetic dependency"))
  expect_identical(empty, oauth_cold_values(""))
})

test_that("cold openssl refuses native-empty Windows initialization before loading", {
  skip_on_cran()
  for (name in oauth_cold_keys) {
    local({
      state = new.env(parent = emptyenv())
      state$calls = 0L
      state$restores = 0L
      empty = oauth_cold_values("synthetic-unchanged")
      empty[[name]] = ""
      loader = function(pkg, quietly) {
        state$calls = state$calls + 1L
        TRUE
      }
      need = oauth_cold_need(loader, windows = TRUE, extra = list(
        Sys.getenv = function(...) empty,
        env_restore_python = function(...) {
          state$restores = state$restores + 1L
          TRUE
        }))
      expect_error(need("openssl", "Synthetic dependency"), class = "gptr_error_not_available")
      expect_identical(state$calls, 0L)
      expect_identical(state$restores, 0L)
      expect_identical(empty[[name]], "")
      expect_invisible(need("later", "Synthetic dependency"))
      expect_identical(state$calls, 1L)
      expect_identical(state$restores, 1L)
    })
  }
})

test_that("uncertain dependency restoration is fatal without replacing an original condition", {
  skip_on_cran()
  for (outcome in c("success", "error", "interrupt")) {
    local({
      original = structure(list(message = "synthetic original dependency condition", call = NULL),
        class = c(paste0("synthetic_", outcome), outcome, "condition"))
      need = oauth_cold_need(function(pkg, quietly) {
        if (outcome == "success") TRUE else stop(original)
      }, extra = list(env_restore_python = function(...) FALSE))
      if (outcome == "success") {
        seen = tryCatch(need("openssl", "Synthetic dependency"), error = identity)
        expect_s3_class(seen, "gptr_error_state_restore")
        expect_true(is.list(seen) && identical(seen$env_restored, FALSE))
      } else {
        seen = NULL
        expect_warning((seen = tryCatch(need("openssl", "Synthetic dependency"),
          error = identity, interrupt = identity)), class = "gptr_warning_state_restore")
        expect_identical(seen, original)
        failed_diagnostic = oauth_cold_need(function(pkg, quietly) stop(original),
          extra = list(env_restore_python = function(...) FALSE,
            gptr_warn = function(...) {
              stop(structure(list(message = "synthetic diagnostic", call = NULL),
                class = c("interrupt", "condition")))
            }))
        expect_identical(tryCatch(failed_diagnostic("openssl", "Synthetic dependency"),
          error = identity, interrupt = identity), original)
      }
    })
  }
})
