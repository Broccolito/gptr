# Provider notices are ordinary conditions; clear a foreground redraw before their delivery.
notice_record = function(.env = parent.frame()) {
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

notice_request = function(w) {
  invisible(console_on_before_request(ev_new("before_request", run = w$run$id,
    request_id = "q-notice", model = "fake/fake-1", tokens_est = 10), w$live$ctx))
}

local_notice_once = function(.env = parent.frame()) {
  old = the$once
  the$once = new.env(parent = emptyenv())
  withr::defer({
    the$once = old
  }, envir = .env)
}

test_that("a CLI notice clears before delivery and the pending spinner resumes", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_notice_once()
  w = notice_record()
  utils::capture.output(notice_request(w))
  sp = w$rec$spinner
  task = w$rec$task
  start = sp$t0
  observed = new.env(parent = emptyenv())
  out = utils::capture.output({
    err = utils::capture.output({
      observed$value = withCallingHandlers(with_interrupt_policy(function() {
        pcli_notice("claude")
        17L
      }, list(w$run)), gptr_message_notice = function(cnd) {
        observed$shown = sp$shown
        observed$condition = cnd
      })
    }, type = "message")
  })
  expect_false(observed$shown)
  expect_true(startsWith(out[[1L]],
    paste0("\r", strrep(" ", 79L), "\r  The claude-cli route is experimental:")))
  out[[1L]] = sub("^\r +\r", "", out[[1L]])
  expect_true(all(startsWith(out, "  ")))
  expect_true(all(nchar(out, type = "width") <= 78L))
  expect_identical(err, character())
  expect_s3_class(observed$condition, "gptr_message_notice")
  expect_identical(observed$value, 17L)
  expect_identical(w$rec$spinner, sp)
  expect_identical(w$rec$task, task)
  expect_identical(sp$t0, start)
  expect_true(w$rec$request_pending)
  sp$last = 0
  redraw = utils::capture.output(invisible(get(task, envir = reactor_get()$tasks)$fn()))
  expect_true(any(grepl("thinking", redraw, fixed = TRUE)))
  expect_true(sp$shown)
})

test_that("once and quiet notices do not clear an otherwise pending redraw", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_notice_once()
  w = notice_record()
  utils::capture.output(notice_request(w))
  utils::capture.output(expect_message(with_interrupt_policy(function() pcli_notice("claude"),
    list(w$run)), class = "gptr_message_notice"))
  w$rec$spinner$last = 0
  utils::capture.output(invisible(w$rec$spinner$tick()))
  out = utils::capture.output(expect_no_message(with_interrupt_policy(function() {
    pcli_notice("claude")
  }, list(w$run))))
  expect_identical(out, character())
  expect_true(w$rec$spinner$shown)
  local_gptr_options(quiet = TRUE)
  out = utils::capture.output(expect_no_message(with_interrupt_policy(function() {
    gptr_inform("quiet notice", "notice")
  }, list(w$run))))
  expect_identical(out, character())
  expect_true(w$rec$spinner$shown)
})

test_that("native R GUI notices replace the cleared waiting row, as on a terminal (D-186)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "rgui")
  w = notice_record()
  utils::capture.output(notice_request(w))
  sp = w$rec$spinner
  observed = new.env(parent = emptyenv())
  out = utils::capture.output({
    err = utils::capture.output(withCallingHandlers(with_interrupt_policy(function() {
      gptr_inform(strrep("long notice ", 12L), "notice")
    }, list(w$run)), gptr_message_notice = function(cnd) {
      observed$condition = cnd
      observed$shown = sp$shown
    }), type = "message")
  })
  clear = paste0("\r", strrep(" ", 39L), "\r")
  expect_true(startsWith(out[[1L]], clear))
  lines = c(substring(out[[1L]], nchar(clear) + 1L), out[-1L])
  expect_true(all(startsWith(lines, "  ")))
  expect_true(all(nchar(lines) <= 38L))
  expect_identical(paste(trimws(lines), collapse = " "), trimws(strrep("long notice ", 12L)))
  expect_identical(err, character())
  expect_s3_class(observed$condition, "gptr_message_notice")
  expect_false(observed$shown)
  expect_true(w$rec$request_pending)
  # no line feed follows the cleared row: the block gap before it gave R.app its stdout line
  bytes = rawConnection(raw(), "w")
  on.exit(close(bytes), add = TRUE)
  sp$last = 0
  utils::capture.output(invisible(sp$tick()))
  sink(bytes)
  tryCatch(console_before_message(list(w$run)), finally = sink())
  expect_identical(rawToChar(rawConnectionValue(bytes)), clear)
  expect_identical(utils::capture.output(console_before_message(list(w$run))), character())
})

test_that("notices on an interactive console wrap inside the two-column margin (D-186)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(quiet = FALSE, verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  text = trimws(strrep("word ", 30L))
  observed = new.env(parent = emptyenv())
  out = utils::capture.output(withCallingHandlers(gptr_inform(text, "notice"),
    gptr_message_notice = function(cnd) observed$message = conditionMessage(cnd)))
  expect_identical(observed$message, paste0(text, "\n"))
  expect_gt(length(out), 1L)
  expect_true(all(startsWith(out, "  ")))
  expect_true(all(nchar(out) <= 38L))
  expect_identical(paste(trimws(out), collapse = " "), text)
  nested = utils::capture.output(gptr_inform(paste0("    - ", text), "notice"))
  expect_gt(length(nested), 1L)
  expect_true(all(startsWith(nested, "      ")))
  expect_true(all(nchar(nested) <= 38L))
  coloured = withr::with_options(list(cli.num_colors = 256L), utils::capture.output(
    gptr_inform(cli::col_grey(paste0("    - ", text)), "notice")))
  expect_identical(cli::ansi_strip(coloured), nested)
  expect_identical(utils::capture.output(console_notice("[gptr] a  b")), "  [gptr] a  b")
  # NO_COLOR keeps the layout; Rscript (verbosity 1, a terminal stderr) and a non-dynamic
  # console print as before
  withr::with_envvar(c(NO_COLOR = "1"),
                     expect_identical(utils::capture.output(gptr_inform(text, "notice")), out))
  withr::with_options(list(gptr.verbose = 1L),
                      expect_identical(utils::capture.output(gptr_inform(text, "notice")), text))
  withr::local_options(cli.dynamic = FALSE)
  expect_identical(utils::capture.output(gptr_inform(text, "notice")), text)
})

test_that("messages keep redaction, metadata and caller handlers", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = notice_record()
  utils::capture.output(notice_request(w))
  old = redactor_set(function(x, profile = "persist") gsub("FAKE_TOKEN", "[secret:TEST]", x))
  withr::defer(redactor_set(old))
  observed = new.env(parent = emptyenv())
  utils::capture.output(withCallingHandlers(with_interrupt_policy(function() {
    gptr_inform("literal {x}: FAKE_TOKEN", "notice", route = "fake")
  }, list(w$run)), gptr_message_notice = function(cnd) {
    observed$condition = cnd
    invokeRestart("muffleMessage")
  }))
  expect_identical(conditionMessage(observed$condition), "literal {x}: [secret:TEST]\n")
  expect_identical(observed$condition$route, "fake")
  expect_null(conditionCall(observed$condition))
  expect_false(w$rec$spinner$shown)
})

test_that("background and nested conditions do not write foreground clear bytes", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = notice_record()
  utils::capture.output(notice_request(w))
  nested = function() {
    .gptr_tool_run = w$run
    force(.gptr_tool_run)
    gptr_inform("nested notice", "notice")
  }
  out = utils::capture.output(expect_message(with_interrupt_policy(nested, list(w$run)),
    "nested notice", fixed = TRUE))
  expect_identical(out, character())
  expect_true(w$rec$spinner$shown)
  w$live$background = list(id = "b-notice")
  out = utils::capture.output(expect_message(with_interrupt_policy(function() {
    gptr_inform("background notice", "notice")
  }, list(w$run)), "background notice", fixed = TRUE))
  expect_identical(out, character())
  expect_true(w$rec$spinner$shown)
})

test_that("real R-tool capture contains no spinner clear bytes or altered warnings", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE, warn = 1L)
  local_mocked_bindings(gptr_has_human = function() TRUE)
  w = notice_record()
  w$run$home$inform = gptr_inform
  w$run$home$warn = gptr_warn
  utils::capture.output(notice_request(w))
  call = list(id = "c-notice", name = "r", tool = tool_lookup("r"),
    input = list(code = paste0('cat("tool output\\n"); inform("tool notice", "notice"); ',
      'warn("tool warning", "notice")')))
  out = utils::capture.output({
    err = utils::capture.output({
      expect_warning({
        result = with_interrupt_policy(function() {
          tool_execute_frame(w$run, call, w$live$ctx)
        }, list(w$run))
      }, class = "gptr_warning_notice")
    }, type = "message")
  })
  # the notice keeps the margin of the console the evaluation started from (D-186)
  expect_identical(out, c("tool output", "  tool notice"))
  expect_identical(err, character())
  expect_false(result$is_error)
  expect_identical(result$details$warnings, "tool warning")
  expect_false(grepl("[\r\033]", tool_result_text(result)))
  expect_true(w$rec$spinner$shown)
})

test_that("non-dynamic and quiet consoles emit no redraw bytes around notices", {
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = FALSE)
  w = notice_record()
  expect_message(notice_request(w), "gptr: thinking", fixed = TRUE)
  out = utils::capture.output(expect_message(with_interrupt_policy(function() {
    gptr_inform("static notice", "notice")
  }, list(w$run)), "static notice", fixed = TRUE))
  expect_identical(out, character())
  expect_null(w$rec$spinner)
  local_gptr_options(quiet = TRUE)
  expect_no_message(expect_output(with_interrupt_policy(function() {
    gptr_inform("quiet notice", "notice")
  }, list(w$run)), NA))
})
