# Synthetic dependency startup; no optional namespace, child or network is opened.
artifact_openssl_probe = function(loader, installed = TRUE, windows = FALSE, warm = FALSE,
                                   extra = list()) {
  scope = list2env(c(list(requireNamespace = loader,
    system.file = function(...) if (installed) "/synthetic/openssl" else "",
    is_windows = function() windows, isNamespaceLoaded = function(pkg) warm), extra),
    parent = environment(artifact_has_openssl))
  available = get0("oauth_available", envir = environment(artifact_has_openssl),
    inherits = FALSE)
  if (!is.null(available)) {
    environment(available) = scope
    scope$oauth_available = available
  }
  has = artifact_has_openssl
  environment(has) = scope
  has
}

artifact_openssl_env = function(value, .env = parent.frame()) {
  keys = c("PATH", "GIT_ASKPASS", "SSH_ASKPASS")
  old = Sys.getenv(keys, unset = NA_character_)
  if (.Platform$OS.type == "windows" && any(!is.na(old) & old == "")) {
    stop("Synthetic fixture cannot restore an existing empty Windows initialization value")
  }
  withr::local_envvar(stats::setNames(rep(value, length(keys)), keys), .local_envir = .env)
  withr::local_preserve_seed(.local_envir = .env)
}

test_that("artifact dependency startup preserves known keys and existing or absent RNG", {
  for (seeded in c(FALSE, TRUE)) {
    for (value in c(NA_character_, "synthetic-custom")) {
      local({
        artifact_openssl_env(value)
        if (seeded) {
          set.seed(42L)
        } else if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
          rm(list = ".Random.seed", envir = globalenv())
        }
        before = Sys.getenv()
        seed = get0(".Random.seed", globalenv(), inherits = FALSE)
        state = new.env(parent = emptyenv())
        state$calls = 0L
        has = artifact_openssl_probe(function(pkg, quietly) {
          expect_identical(pkg, "openssl")
          expect_true(quietly)
          state$calls = state$calls + 1L
          Sys.setenv(GIT_ASKPASS = "synthetic-loaded", SSH_ASKPASS = "synthetic-loaded")
          stats::runif(2L)
          TRUE
        })
        expect_identical(has(), TRUE)
        expect_identical(state$calls, 1L)
        expect(identical(Sys.getenv(), before), "artifact startup must preserve caller environment")
        expect(identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed),
          "artifact startup must preserve caller RNG state")
      })
    }
  }
})

test_that("unavailable artifact openssl stays Boolean false and keeps urandom fallback", {
  artifact_openssl_env(NA_character_)
  before = Sys.getenv()
  seed = get0(".Random.seed", globalenv(), inherits = FALSE)
  calls = new.env(parent = emptyenv())
  calls$n = 0L
  has = artifact_openssl_probe(function(pkg, quietly) {
    calls$n = calls$n + 1L
    Sys.setenv(GIT_ASKPASS = "synthetic-loaded")
    stats::runif(1L)
    FALSE
  })
  expect_identical(has(), FALSE)
  expect_identical(calls$n, 1L)
  expect(identical(Sys.getenv(), before), "artifact startup must preserve caller environment")
  expect(identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed),
    "artifact startup must preserve caller RNG state")
  if (.Platform$OS.type == "unix" && file.exists("/dev/urandom")) {
    token = artifact_token
    environment(token) = list2env(list(artifact_has_openssl = has),
      parent = environment(artifact_token))
    expect_match(token(), "^[0-9a-f]{32}$")
    expect(identical(Sys.getenv(), before), "artifact startup must preserve caller environment")
    expect(identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed),
      "artifact startup must preserve caller RNG state")
  }
  absent = artifact_openssl_probe(function(...) stop("Missing package must not load"),
    installed = FALSE, windows = TRUE, extra = list(Sys.getenv = function(...) c(PATH = "")))
  expect_identical(absent(), FALSE)
  warm = artifact_openssl_probe(function(...) TRUE, installed = FALSE, warm = TRUE)
  expect_identical(warm(), TRUE)
})

test_that("artifact dependency loader errors and interrupts retain original identity and state", {
  for (outcome in c("error", "interrupt")) {
    local({
      artifact_openssl_env(NA_character_)
      before = Sys.getenv()
      seed = get0(".Random.seed", globalenv(), inherits = FALSE)
      original = structure(list(message = "synthetic artifact dependency", call = NULL),
        class = c(paste0("synthetic_", outcome), outcome, "condition"))
      has = artifact_openssl_probe(function(...) {
        Sys.setenv(GIT_ASKPASS = "synthetic-loaded", SSH_ASKPASS = "synthetic-loaded")
        stats::runif(1L)
        stop(original)
      })
      expect_identical(tryCatch(has(), error = identity, interrupt = identity), original)
      expect(identical(Sys.getenv(), before), "artifact startup must preserve caller environment")
      expect(identical(get0(".Random.seed", globalenv(), inherits = FALSE), seed),
        "artifact startup must preserve caller RNG state")
    })
  }
})

test_that("artifact dependency restoration uncertainty remains fatal with primary priority", {
  original = structure(list(message = "synthetic artifact dependency", call = NULL),
    class = c("synthetic_error", "error", "condition"))
  has = artifact_openssl_probe(function(...) TRUE,
    extra = list(env_restore_python = function(...) FALSE))
  expect_error(has(), class = "gptr_error_state_restore")
  has = artifact_openssl_probe(function(...) stop(original),
    extra = list(env_restore_python = function(...) FALSE))
  seen = NULL
  expect_warning({
    seen = tryCatch(has(), error = identity)
  }, class = "gptr_warning_state_restore")
  expect_identical(seen, original)
})

test_that("artifact cold Windows empties refuse loading but warm untouched empties remain exact", {
  empty = c(PATH = "", GIT_ASKPASS = "", SSH_ASKPASS = "")
  state = new.env(parent = emptyenv())
  state$calls = 0L
  state$restores = 0L
  has = artifact_openssl_probe(function(...) {
    state$calls = state$calls + 1L
    TRUE
  }, windows = TRUE, extra = list(Sys.getenv = function(...) empty,
    env_restore_python = function(...) {
      state$restores = state$restores + 1L
      TRUE
    }))
  expect_error(has(), class = "gptr_error_not_available")
  expect(identical(state$calls, 0L), "cold Windows empty startup must not call the loader")
  expect_identical(state$restores, 0L)
  restore = env_restore_python
  environment(restore) = list2env(list(Sys.getenv = function(...) empty,
    Sys.setenv = function(...) stop("Untouched empty value must not be set"),
    Sys.unsetenv = function(...) stop("Untouched empty value must not be removed")),
    parent = environment(env_restore_python))
  warm = artifact_openssl_probe(function(...) TRUE, windows = TRUE, warm = TRUE,
    extra = list(Sys.getenv = function(...) empty, env_restore_python = restore))
  expect_identical(warm(), TRUE)
  expect_identical(empty, c(PATH = "", GIT_ASKPASS = "", SSH_ASKPASS = ""))
})

test_that("artifact dependency setup refuses ambiguous Windows key spellings before loading", {
  ambiguous = c(PATH = "synthetic-one", Path = "synthetic-two")
  has = artifact_openssl_probe(function(...) stop("Ambiguous names must not load"),
    windows = TRUE, extra = list(Sys.getenv = function(...) ambiguous))
  expect_error(has(), class = "gptr_error_not_available")
  expect_identical(ambiguous, c(PATH = "synthetic-one", Path = "synthetic-two"))
})
