# Prepared tests first. These mocks do not initialize or execute Python.
py_init_test_keys = c("PATH", "VIRTUAL_ENV", "R_SESSION_INITIALIZED", "LD_LIBRARY_PATH",
                      "PYTHONPATH", "PYTHONIOENCODING")

py_init_test_values = function(prefix) {
  stats::setNames(paste0(prefix, seq_along(py_init_test_keys)), py_init_test_keys)
}

py_init_test_env = function(values, extra = character(), .env = parent.frame()) {
  controlled = c(names(values), "RETICULATE_PYTHON", extra)
  old = Sys.getenv(controlled, unset = NA_character_)
  if (.Platform$OS.type == "windows" && any(!is.na(old) & old == "")) {
    stop("Synthetic fixture cannot restore an existing native-empty Windows setup key")
  }
  values = c(values, RETICULATE_PYTHON = "synthetic-configured-python")
  withr::local_envvar(values, .local_envir = .env)
}

py_init_test_mocks = function(main, initialized, initialize, .env = parent.frame()) {
  force(initialized)
  testthat::local_mocked_bindings(
    py_available = function(initialize = FALSE) initialized,
    import_main = initialize,
    py_has_attr = function(x, name) TRUE,
    py_to_r = function(x) x,
    py_get_item = function(x, key) x[[key + 1L]],
    .package = "reticulate", .env = .env
  )
  invisible(main)
}

test_that("Python setup restores known R environment keys after new and existing initialization", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  for (initialized in c(FALSE, TRUE)) {
    local({
      py_init_test_env(py_init_test_values("before-"))
      before = Sys.getenv(py_init_test_keys, unset = NA_character_)
      before_raw = Sys.getenv()
      main = new.env(parent = emptyenv())
      initialize = function(convert = FALSE) {
        do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
        main
      }
      py_init_test_mocks(main, initialized, initialize)
      result = bridge_py_main()
      expect_identical(result, main)
      expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
      expect_identical(Sys.getenv(), before_raw)
    })
  }
})

test_that("Python setup restores keys before propagating the original error or interrupt", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  for (type in c("error", "interrupt")) {
    for (stage in c("import", "helper")) {
      local({
        py_init_test_env(py_init_test_values("before-"))
        before = Sys.getenv(py_init_test_keys, unset = NA_character_)
        before_raw = Sys.getenv()
        original = structure(list(message = "synthetic setup condition", call = NULL),
                             class = c(paste0("synthetic_", type), type, "condition"))
        initialize = function(convert = FALSE) {
          do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
          if (stage == "import") stop(original)
          new.env(parent = emptyenv())
        }
        py_init_test_mocks(NULL, FALSE, initialize)
        testthat::local_mocked_bindings(
          py_has_attr = function(x, name) stage != "helper",
          py_run_string = function(code, convert = FALSE) stop(original),
          .package = "reticulate"
        )
        seen = tryCatch(bridge_py_main(), error = identity, interrupt = identity)
        expect_identical(seen, original)
        expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
        expect_identical(Sys.getenv(), before_raw)
      })
    }
  }
})

test_that("Python setup restores absent keys without adding empty environment entries", {
  skip_if_not_installed("reticulate")
  values = stats::setNames(rep(NA_character_, length(py_init_test_keys)), py_init_test_keys)
  py_init_test_env(values)
  before = Sys.getenv(py_init_test_keys, unset = NA_character_)
  main = new.env(parent = emptyenv())
  initialize = function(convert = FALSE) {
    do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
    main
  }
  py_init_test_mocks(main, FALSE, initialize)
  expect_identical(bridge_py_main(), main)
  expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
  expect_false(any(py_init_test_keys %in% names(Sys.getenv())))
})

test_that("Python setup restores changed POSIX empty keys exactly", {
  skip_if_not_installed("reticulate")
  skip_if(.Platform$OS.type == "windows", "requires POSIX empty environment restoration")
  py_init_test_env(stats::setNames(rep("", length(py_init_test_keys)), py_init_test_keys))
  before = Sys.getenv(py_init_test_keys, unset = NA_character_)
  main = new.env(parent = emptyenv())
  initialize = function(convert = FALSE) {
    do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
    main
  }
  py_init_test_mocks(main, FALSE, initialize)
  expect_identical(bridge_py_main(), main)
  expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
  expect_true(all(py_init_test_keys %in% names(Sys.getenv())))
})

test_that("Python setup refuses un-restorable Windows empty keys before first initialization", {
  skip_if_not_installed("reticulate")
  skip_if(.Platform$OS.type == "windows",
          "this injected-state fixture requires POSIX empty values")
  py_init_test_env(py_init_test_values("before-"))
  Sys.setenv(PYTHONPATH = "")
  before = Sys.getenv(py_init_test_keys, unset = NA_character_)
  state = new.env(parent = emptyenv())
  state$calls = 0L
  initialize = function(convert = FALSE) {
    state$calls = state$calls + 1L
    do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
    new.env(parent = emptyenv())
  }
  py_init_test_mocks(NULL, FALSE, initialize)
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  expect_error(bridge_py_main(), class = "gptr_error_not_available")
  expect_identical(state$calls, 0L)
  expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
})

test_that("Python setup keeps untouched empty keys when Python is already initialized", {
  skip_if_not_installed("reticulate")
  skip_if(.Platform$OS.type == "windows",
          "this injected-state fixture requires POSIX empty values")
  py_init_test_env(py_init_test_values("before-"))
  Sys.setenv(PYTHONPATH = "")
  before = Sys.getenv(py_init_test_keys, unset = NA_character_)
  main = new.env(parent = emptyenv())
  py_init_test_mocks(main, TRUE, function(convert = FALSE) main)
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  expect_identical(bridge_py_main(), main)
  expect_identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
})

test_that("Python user evaluation keeps deliberate environment changes after setup restoration", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  py_init_test_env(py_init_test_values("before-"), extra = "GPTR_PY_INIT_USER_CANARY")
  withr::local_envvar(GPTR_PY_INIT_USER_CANARY = NA_character_)
  before = Sys.getenv(py_init_test_keys, unset = NA_character_)
  state = new.env(parent = emptyenv())
  state$setup_restored = FALSE
  main = new.env(parent = emptyenv())
  main$`_gptr_run` = function(src, rows) {
    state$setup_restored = identical(Sys.getenv(py_init_test_keys, unset = NA_character_), before)
    Sys.setenv(PATH = "deliberate-user-path", GPTR_PY_INIT_USER_CANARY = "deliberate-user-value")
    list(list(out = "", err = "", repr = "42", error = NULL, kind = "int"), 42L)
  }
  initialize = function(convert = FALSE) {
    do.call(Sys.setenv, as.list(py_init_test_values("initialization-")))
    main
  }
  py_init_test_mocks(main, FALSE, initialize)
  result = bridge_py("synthetic user source")
  expect_true(state$setup_restored)
  expect_identical(result$value, 42L)
  expect_identical(Sys.getenv("PATH"), "deliberate-user-path")
  expect_identical(Sys.getenv("GPTR_PY_INIT_USER_CANARY"), "deliberate-user-value")
})

test_that("Python setup never completes when environment restoration is uncertain", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  for (type in c("false", "error", "interrupt")) {
    local({
      py_init_test_env(py_init_test_values("before-"))
      main = new.env(parent = emptyenv())
      py_init_test_mocks(main, FALSE, function(convert = FALSE) main)
      restore = function(...) {
        if (type == "false") return(FALSE)
        stop(structure(list(message = "synthetic restoration condition", call = NULL),
                       class = c(type, "condition")))
      }
      testthat::local_mocked_bindings(env_restore_python = restore)
      error = expect_error(bridge_py_main(), class = "gptr_error_not_available")
      expect_identical(error$env_restored, FALSE)
    })
  }
})

test_that("Python setup keeps its original failure when restoration also fails", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  for (type in c("error", "interrupt")) {
    local({
      py_init_test_env(py_init_test_values("before-"))
      original = structure(list(message = "synthetic setup condition", call = NULL),
                           class = c(paste0("synthetic_", type), type, "condition"))
      initialize = function(convert = FALSE) stop(original)
      py_init_test_mocks(NULL, FALSE, initialize)
      testthat::local_mocked_bindings(env_restore_python = function(...) FALSE)
      state = new.env(parent = emptyenv())
      expect_warning({
        state$seen = tryCatch(bridge_py_main(), error = identity, interrupt = identity)
      }, class = "gptr_warning_state_restore")
      expect_identical(state$seen, original)
      diagnostic = structure(list(message = "synthetic diagnostic failure", call = NULL),
                             class = c(type, "condition"))
      testthat::local_mocked_bindings(gptr_warn = function(...) stop(diagnostic))
      seen = tryCatch(bridge_py_main(), error = identity, interrupt = identity)
      expect_identical(seen, original)
    })
  }
})

test_that("Python setup rejects a changed initialized Windows empty key without normalizing it", {
  skip_if_not_installed("reticulate")
  skip_if(.Platform$OS.type == "windows",
          "this injected-state fixture requires POSIX empty values")
  py_init_test_env(py_init_test_values("before-"))
  Sys.setenv(PYTHONPATH = "")
  main = new.env(parent = emptyenv())
  py_init_test_mocks(main, TRUE, function(convert = FALSE) {
    Sys.setenv(PYTHONPATH = "unexpected-initialized-change")
    main
  })
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  error = expect_error(bridge_py_main(), class = "gptr_error_not_available")
  expect_identical(error$env_restored, FALSE)
  expect_identical(Sys.getenv("PYTHONPATH", unset = NA_character_), "unexpected-initialized-change")
})


test_that("Python setup preserves the caller's absent or configured uv option", {
  skip_if_not_installed("reticulate")
  for (prior in list(NULL, structure("caller-uv", marker = "caller"))) {
    local({
      withr::local_options(list(reticulate.uv_binary = prior))
      py_init_test_env(py_init_test_values("before-"))
      main = new.env(parent = emptyenv())
      py_init_test_mocks(main, FALSE, function(convert = FALSE) {
        options(reticulate.uv_binary = "initialization-uv")
        main
      })
      before = options()
      expect_identical(bridge_py_main(), main)
      expect(identical(options(), before), "setup must preserve the exact caller options")
      expect(identical(getOption("reticulate.uv_binary"), prior),
        "setup must preserve the exact caller uv option")
    })
  }
})

test_that("Python setup preserves its uv option before the original error or interrupt", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  for (type in c("error", "interrupt")) {
    for (stage in c("import", "helper")) {
      for (prior in list(NULL, structure("caller-uv", marker = "caller"))) {
        local({
          withr::local_options(list(reticulate.uv_binary = prior))
          py_init_test_env(py_init_test_values("before-"))
          original = structure(list(message = "synthetic uv setup condition", call = NULL),
            class = c(paste0("synthetic_", type), type, "condition"))
          py_init_test_mocks(NULL, FALSE, function(convert = FALSE) {
            options(reticulate.uv_binary = "initialization-uv")
            if (stage == "import") stop(original)
            new.env(parent = emptyenv())
          })
          testthat::local_mocked_bindings(
            py_has_attr = function(x, name) stage != "helper",
            py_run_string = function(code, convert = FALSE) stop(original),
            .package = "reticulate"
          )
          before = options()
          env_before = Sys.getenv()
          seen = tryCatch(bridge_py_main(), error = identity, interrupt = identity)
          expect_identical(seen, original)
          expect(identical(options(), before), "failed setup must preserve caller options")
          expect_identical(Sys.getenv(), env_before)
          expect(identical(getOption("reticulate.uv_binary"), prior),
            "failed setup must preserve the exact caller uv option")
        })
      }
    }
  }
})

test_that("Python user evaluation keeps deliberate option changes after setup", {
  skip_if_not_installed("reticulate")
  withr::local_options(reticulate.uv_binary = NULL)
  py_init_test_env(py_init_test_values("before-"))
  state = new.env(parent = emptyenv())
  state$setup_restored = FALSE
  main = new.env(parent = emptyenv())
  main$`_gptr_run` = function(src, rows) {
    state$setup_restored = is.null(getOption("reticulate.uv_binary"))
    options(reticulate.uv_binary = "deliberate-user-uv")
    list(list(out = "", err = "", repr = "42", error = NULL, kind = "int"), 42L)
  }
  py_init_test_mocks(main, FALSE, function(convert = FALSE) {
    options(reticulate.uv_binary = "initialization-uv")
    main
  })
  result = bridge_py("synthetic user source")
  expect(isTRUE(state$setup_restored), "setup must restore its option before user evaluation")
  expect_identical(result$value, 42L)
  expect_identical(getOption("reticulate.uv_binary"), "deliberate-user-uv")
})


# Clone only the namespace-loader lookup; the actual setup body and formals stay intact.
py_init_test_main_loader = function(loader) {
  main = bridge_py_main
  scope = new.env(parent = environment(main))
  scope$requireNamespace = loader
  environment(main) = scope
  main
}

test_that("Python setup preserves the caller's absent or configured Matrix callback", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  callback = function(condition) invisible(NULL)
  for (prior in list(NULL, callback)) {
    local({
      withr::local_options(list(ambiguousMethodSelection = prior))
      py_init_test_env(py_init_test_values("before-"))
      main = new.env(parent = emptyenv())
      py_init_test_mocks(main, FALSE, function(convert = FALSE) main)
      state = new.env(parent = emptyenv())
      state$calls = 0L
      setup = py_init_test_main_loader(function(package, quietly = FALSE) {
        state$calls = state$calls + 1L
        options(ambiguousMethodSelection = function(condition) "initialization")
        TRUE
      })
      before = options()
      result = setup()
      after = options()
      expect_identical(result, main)
      expect_identical(state$calls, 1L)
      expect(identical(after, before), "setup must preserve the exact caller Matrix options")
      expect(identical(getOption("ambiguousMethodSelection"), prior),
        "setup must preserve the exact caller Matrix callback")
    })
  }
})

test_that("Python setup preserves its Matrix callback before the original error or interrupt", {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  callback = function(condition) invisible(NULL)
  for (type in c("error", "interrupt")) {
    for (stage in c("namespace", "import", "helper")) {
      for (prior in list(NULL, callback)) {
        local({
          withr::local_options(list(ambiguousMethodSelection = prior))
          py_init_test_env(py_init_test_values("before-"))
          original = structure(list(message = "synthetic Matrix setup condition", call = NULL),
            class = c(paste0("synthetic_", type), type, "condition"))
          py_init_test_mocks(NULL, FALSE, function(convert = FALSE) {
            if (stage == "import") stop(original)
            new.env(parent = emptyenv())
          })
          testthat::local_mocked_bindings(
            py_has_attr = function(x, name) stage != "helper",
            py_run_string = function(code, convert = FALSE) stop(original),
            .package = "reticulate"
          )
          setup = py_init_test_main_loader(function(package, quietly = FALSE) {
            options(ambiguousMethodSelection = function(condition) "initialization")
            if (stage == "namespace") stop(original)
            TRUE
          })
          before = options()
          env_before = Sys.getenv()
          seen = tryCatch(setup(), error = identity, interrupt = identity)
          after = options()
          env_after = Sys.getenv()
          expect_identical(seen, original)
          expect(identical(after, before), "failed setup must preserve caller Matrix options")
          expect_identical(env_after, env_before)
          expect(identical(getOption("ambiguousMethodSelection"), prior),
            "failed setup must preserve the exact caller Matrix callback")
        })
      }
    }
  }
})

test_that("Python user evaluation keeps deliberate Matrix callback changes after setup", {
  skip_if_not_installed("reticulate")
  withr::local_options(ambiguousMethodSelection = NULL)
  py_init_test_env(py_init_test_values("before-"))
  state = new.env(parent = emptyenv())
  state$setup_restored = FALSE
  user_callback = function(condition) "deliberate user choice"
  main = new.env(parent = emptyenv())
  main$`_gptr_run` = function(src, rows) {
    state$setup_restored = is.null(getOption("ambiguousMethodSelection"))
    options(ambiguousMethodSelection = user_callback)
    list(list(out = "", err = "", repr = "42", error = NULL, kind = "int"), 42L)
  }
  py_init_test_mocks(main, FALSE, function(convert = FALSE) main)
  setup = py_init_test_main_loader(function(package, quietly = FALSE) {
    options(ambiguousMethodSelection = function(condition) "initialization")
    TRUE
  })
  evaluate = bridge_py
  scope = new.env(parent = environment(evaluate))
  scope$bridge_py_main = setup
  environment(evaluate) = scope
  result = evaluate("synthetic user source")
  expect(isTRUE(state$setup_restored),
    "setup must restore its Matrix callback before user evaluation")
  expect_identical(result$value, 42L)
  expect_identical(getOption("ambiguousMethodSelection"), user_callback)
})
