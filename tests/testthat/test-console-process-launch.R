# A native pre-exec diagnostic can reach the console before processx redirects child stderr.
launch_record = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_fake_provider(list("ok"), .env = .env)
  s = session_new("fake/fake-1", "auto", home = new.env())
  run = run_new(s, list(), NULL)
  run$status = "requesting"
  live = session_live(s)
  live$run = run
  console_on_agent_start(ev_new("agent_start", run = run$id), live$ctx)
  withr::defer({
    console_drop(run$id)
    live$run = NULL
  }, envir = .env)
  list(s = s, live = live, run = run, rec = console_record(list(run = run$id)))
}

launch_request = function(w) {
  invisible(console_on_before_request(ev_new("before_request", run = w$run$id,
    request_id = "q-launch", model = "fake/fake-1", tokens_est = 10), w$live$ctx))
}

launch_condition = function() {
  structure(list(message = "", call = NULL), class = c("gptr_process_spawn", "condition"))
}

launch_capture = function(callback) {
  bytes = rawConnection(raw(), "w")
  on.exit(close(bytes), add = TRUE)
  sink(bytes)
  tryCatch(callback(bytes), finally = sink())
}

test_that("process launch signals a private boundary before the native constructor", {
  local_project()
  observed = new.env(parent = emptyenv())
  observed$order = character()
  p = new.env(parent = emptyenv())
  parent_env = Sys.getenv()
  local_mocked_bindings(process = list(new = function(...) {
    observed$order = c(observed$order, "constructor")
    p
  }), .package = "processx")
  local_mocked_bindings(proc_mark = function(...) NULL)
  result = withCallingHandlers(proc_spawn(rscript_path(),
    env = c(GPTR_SYNTHETIC_CHILD = "child-only"), .on_spawn = function(child) {
      observed$order = c(observed$order, "owned")
      observed$child = child
    }), gptr_process_spawn = function(cnd) {
      observed$order = c(observed$order, "boundary")
      observed$condition = cnd
    })
  expect_identical(observed$order, c("boundary", "constructor", "owned"))
  expect_identical(result, p)
  expect_identical(observed$child, p)
  expect_identical(class(observed$condition), c("gptr_process_spawn", "condition"))
  expect_identical(names(observed$condition), c("message", "call"))
  expect_identical(conditionMessage(observed$condition), "")
  expect_null(conditionCall(observed$condition))
  expect_identical(Sys.getenv(), parent_env)
})

test_that("failed launch retains the existing spawn error and parent environment", {
  local_project()
  observed = new.env(parent = emptyenv())
  observed$count = 0L
  parent_env = Sys.getenv()
  local_mocked_bindings(process = list(new = function(...) stop("synthetic native failure")),
    .package = "processx")
  error = tryCatch(withCallingHandlers(proc_spawn(rscript_path(),
    env = c(GPTR_SYNTHETIC_CHILD = "child-only")), gptr_process_spawn = function(cnd) {
      observed$count = observed$count + 1L
    }), error = identity)
  expect_s3_class(error, "gptr_error_spawn")
  expect_match(conditionMessage(error), "synthetic native failure", fixed = TRUE)
  expect_identical(observed$count, 1L)
  expect_identical(Sys.getenv(), parent_env)
})

test_that("a foreground launch closes the thinking row before stderr and resumes animation", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "rstudio")
  w = launch_record()
  utils::capture.output(launch_request(w))
  sp = w$rec$spinner
  task = w$rec$task
  start = sp$t0
  observed = new.env(parent = emptyenv())
  launch_capture(function(bytes) {
    err = utils::capture.output({
      observed$value = with_interrupt_policy(function() {
        signalCondition(launch_condition())
        observed$before_stderr = rawToChar(rawConnectionValue(bytes))
        observed$shown = sp$shown
        cat("SYNTHETIC-NATIVE-DIAGNOSTIC\n", file = stderr())
        17L
      }, list(w$run))
    }, type = "message")
    expect_identical(observed$before_stderr, paste0("\r", strrep(" ", 39L), "\r"))
    expect_false(observed$shown)
    expect_identical(err, "SYNTHETIC-NATIVE-DIAGNOSTIC")
    expect_identical(observed$value, 17L)
    expect_identical(w$rec$spinner, sp)
    expect_identical(w$rec$task, task)
    expect_identical(sp$t0, start)
    expect_true(w$rec$request_pending)
    sp$last = 0
    invisible(get(task, envir = reactor_get()$tasks)$fn())
    expect_true(sp$shown)
    expect_match(rawToChar(rawConnectionValue(bytes)), "thinking", fixed = TRUE)
  })
})

test_that("launch observation preserves genuine stderr and the original condition", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = launch_record()
  utils::capture.output(launch_request(w))
  original = simpleError("synthetic genuine error")
  observed = new.env(parent = emptyenv())
  launch_capture(function(bytes) {
    err = utils::capture.output({
      observed$error = tryCatch(with_interrupt_policy(function() {
        signalCondition(launch_condition())
        cat("SYNTHETIC-GENUINE-STDERR\n", file = stderr())
        stop(original)
      }, list(w$run)), error = identity)
    }, type = "message")
    expect_identical(err, "SYNTHETIC-GENUINE-STDERR")
    expect_identical(observed$error, original)
    expect_false(w$rec$spinner$shown)
    expect_identical(rawToChar(rawConnectionValue(bytes)), paste0("\r", strrep(" ", 39L), "\r"))
  })
})

test_that("a launch boundary ends the waiting row without a line feed, in R GUIs too (D-186)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  for (frontend in c("terminal", "rgui")) {
    local_mocked_bindings(front_end = function() frontend)
    w = launch_record()
    utils::capture.output(launch_request(w))
    launch_capture(function(bytes) {
      with_interrupt_policy(function() signalCondition(launch_condition()), list(w$run))
      expect_identical(rawToChar(rawConnectionValue(bytes)),
                       paste0("\r", strrep(" ", 39L), "\r"),
                       info = frontend)
    })
    console_drop(w$run$id)
  }
})

test_that("nested and background launches do not inject foreground display bytes", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = launch_record()
  utils::capture.output(launch_request(w))
  nested = function() {
    .gptr_tool_run = w$run
    force(.gptr_tool_run)
    signalCondition(launch_condition())
  }
  expect_identical(utils::capture.output(invisible(with_interrupt_policy(nested, list(w$run)))),
    character())
  expect_true(w$rec$spinner$shown)
  w$live$background = list(id = "b-launch")
  expect_identical(utils::capture.output(invisible(with_interrupt_policy(function() {
    signalCondition(launch_condition())
  }, list(w$run)))), character())
  expect_true(w$rec$spinner$shown)
})

test_that("real R-tool launch observation leaves captured text and warnings intact", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE, warn = 1L)
  local_mocked_bindings(gptr_has_human = function() TRUE)
  w = launch_record()
  w$run$home$launch = function() invisible(signalCondition(launch_condition()))
  w$run$home$warn = gptr_warn
  utils::capture.output(launch_request(w))
  call = list(id = "c-launch", name = "r", tool = tool_lookup("r"),
    input = list(code = paste0('cat("tool output\\n"); launch(); ',
      'warn("tool warning", "notice")')))
  out = utils::capture.output({
    expect_warning({
      result = with_interrupt_policy(function() {
        tool_execute_frame(w$run, call, w$live$ctx)
      }, list(w$run))
    }, class = "gptr_warning_notice")
  })
  expect_identical(out, "tool output")
  expect_false(result$is_error)
  expect_identical(result$details$warnings, "tool warning")
  expect_false(grepl("[\r\033]", tool_result_text(result)))
  expect_true(w$rec$spinner$shown)
})

test_that("nested policies clear once and inactive policies emit no boundary output", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = launch_record()
  utils::capture.output(launch_request(w))
  launch_capture(function(bytes) {
    with_interrupt_policy(function() {
      with_interrupt_policy(function() signalCondition(launch_condition()), list(w$run))
      signalCondition(launch_condition())
    }, list(w$run))
    expect_identical(rawToChar(rawConnectionValue(bytes)),
      paste0("\r", strrep(" ", 39L), "\r"))
  })
  expect_identical(utils::capture.output(invisible(signalCondition(launch_condition()))),
    character())
  withr::local_options(cli.dynamic = FALSE)
  expect_identical(utils::capture.output(invisible(with_interrupt_policy(function() {
    signalCondition(launch_condition())
  }, list(w$run)))), character())
  local_gptr_options(quiet = TRUE)
  expect_identical(utils::capture.output(invisible(with_interrupt_policy(function() {
    signalCondition(launch_condition())
  }, list(w$run)))), character())
})

test_that("bare command lookup closes the thinking row before its native diagnostic", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "rstudio")
  w = launch_record()
  utils::capture.output(launch_request(w))
  sp = w$rec$spinner
  task = w$rec$task
  start = sp$t0
  parent_env = Sys.getenv()
  path = rscript_path()
  p = new.env(parent = emptyenv())
  observed = new.env(parent = emptyenv())
  observed$order = character()
  local_mocked_bindings(process = list(new = function(...) {
    observed$order = c(observed$order, "constructor")
    p
  }), .package = "processx")
  local_mocked_bindings(proc_mark = function(...) NULL)
  launch_capture(function(bytes) {
    local_mocked_bindings(Sys.which = function(command) {
      observed$order = c(observed$order, "lookup")
      observed$command = command
      observed$before_stderr = rawToChar(rawConnectionValue(bytes))
      observed$shown = sp$shown
      cat("SYNTHETIC-LOOKUP-DIAGNOSTIC\n", file = stderr())
      stats::setNames(path, command)
    }, .package = "base")
    err = utils::capture.output({
      observed$value = with_interrupt_policy(function() {
        withCallingHandlers(proc_spawn("gptr-synthetic-bare", .on_spawn = function(child) {
          observed$order = c(observed$order, "owned")
          observed$child = child
        }), gptr_process_spawn = function(cnd) {
          observed$order = c(observed$order, "boundary")
        })
      }, list(w$run))
    }, type = "message")
    expect_identical(observed$order, c("boundary", "lookup", "constructor", "owned"))
    expect_identical(observed$command, "gptr-synthetic-bare")
    expect_identical(observed$before_stderr, paste0("\r", strrep(" ", 39L), "\r"))
    expect_false(observed$shown)
    expect_identical(err, "SYNTHETIC-LOOKUP-DIAGNOSTIC")
    expect_identical(observed$value, p)
    expect_identical(observed$child, p)
    expect_identical(w$rec$spinner, sp)
    expect_identical(w$rec$task, task)
    expect_identical(sp$t0, start)
    expect_true(w$rec$request_pending)
    expect_identical(Sys.getenv(), parent_env)
  })
})

test_that("lookup failure preserves its original error without starting a native process", {
  local_project()
  parent_env = Sys.getenv()
  original = simpleError("synthetic lookup failure")
  observed = new.env(parent = emptyenv())
  observed$order = character()
  local_mocked_bindings(Sys.which = function(command) {
    observed$order = c(observed$order, "lookup")
    stop(original)
  }, .package = "base")
  local_mocked_bindings(process = list(new = function(...) {
    observed$order = c(observed$order, "constructor")
    stop("unexpected constructor")
  }), .package = "processx")
  error = tryCatch(withCallingHandlers(proc_spawn("gptr-synthetic-bare"),
    gptr_process_spawn = function(cnd) {
      observed$order = c(observed$order, "boundary")
    }), error = identity)
  expect_identical(observed$order, c("boundary", "lookup"))
  expect_identical(error, original)
  expect_identical(Sys.getenv(), parent_env)
})
