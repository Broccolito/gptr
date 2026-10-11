test_that("informational conditions display as ordinary stdout without losing handlers", {
  local_gptr_options(quiet = FALSE)
  observed = new.env(parent = emptyenv())
  out = utils::capture.output({
    err = utils::capture.output(withCallingHandlers({
      observed$value = withVisible(gptr_inform(c("ordinary notice", "literal {x}"), "notice",
        route = "offline"))
    }, gptr_message_notice = function(cnd) observed$cnd = cnd), type = "message")
  })
  expect_identical(out, c("ordinary notice", "literal {x}"))
  expect_identical(err, character())
  expect_s3_class(observed$cnd, "gptr_message_notice")
  expect_identical(observed$cnd$route, "offline")
  expect_identical(conditionMessage(observed$cnd), "ordinary notice\nliteral {x}\n")
  expect_null(observed$value$value)
  expect_false(observed$value$visible)
  expect_identical(utils::capture.output(suppressMessages(gptr_inform("hidden", "notice"))),
                   character())
})

test_that("verbatim stdout display stays out of the native error stream", {
  out = utils::capture.output({
    err = utils::capture.output(msg_verbatim(c("normal response", "literal {x}")),
                                type = "message")
  })
  expect_identical(out, c("normal response", "literal {x}"))
  expect_identical(err, character())
})

test_that("actual failure notices have an explicit stderr route", {
  local_gptr_options(quiet = FALSE)
  out = utils::capture.output({
    err = utils::capture.output(gptr_inform("synthetic failure", "progress", .stream = "stderr"),
                                type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "synthetic failure")
})

test_that("successful edit removals stay plain while actual tool errors are marked", {
  withr::local_options(cli.num_colors = 256L)
  result = list(is_error = FALSE, details = list(diff = c("-old", "+new")))
  lines = console_result_lines(list(name = "edit"), result)
  expect_identical(lines[[1L]], "    -old")
  expect_identical(cli::ansi_strip(lines[[2L]]), "    +new")
  result$is_error = TRUE
  result$content = list(block_text("failed"))
  expect_match(cli::ansi_strip(console_result_lines(list(name = "edit"), result)),
               "error: failed", fixed = TRUE)
})

test_that("UI notifications distinguish actual errors from ordinary guidance", {
  local_gptr_options(quiet = FALSE)
  for (ui in list(ui_none_spec(), ui_console_spec(), ui_rstudio_spec())) {
    out = utils::capture.output({
      err = utils::capture.output({
        ui$notify("ordinary guidance", "warning")
        ui$notify("actual failure", "error")
      }, type = "message")
    })
    expect_length(out, 1L)
    expect_match(out, "ordinary guidance", fixed = TRUE)
    expect_length(err, 1L)
    expect_match(err, "actual failure", fixed = TRUE)
  }
})

test_that("teed R messages display once and retain one message event", {
  local_gptr_options(quiet = FALSE)
  home = new.env()
  home$inform = gptr_inform
  observed = new.env(parent = emptyenv())
  out = utils::capture.output({
    err = utils::capture.output(withCallingHandlers({
      result = eval_r('cat("before\\n"); inform("notice", "notice"); cat("after\\n")',
                       home, plots = "none", tee = TRUE)
    }, gptr_message_notice = function(cnd) {
      observed$cnd = cnd
      cat("handler output\n")
    }), type = "message")
  })
  expect_identical(out, c("before", "handler output", "notice", "after"))
  expect_identical(err, character())
  expect_s3_class(observed$cnd, "gptr_message_notice")
  events = Filter(function(e) e$type %in% c("output", "message"), result$events)
  expect_identical(vapply(events, function(e) e$type, ""),
                   c("output", "message", "output", "output"))
  expect_identical(vapply(events, function(e) e$text, ""),
                   c("before\n", "notice\n", "handler output\n", "after\n"))
  hidden = utils::capture.output({
    result = eval_r('inform("hidden", "notice")', home, plots = "none", tee = FALSE)
  })
  expect_identical(hidden, character())
  expect_identical(vapply(Filter(function(e) e$type == "message", result$events),
                          function(e) e$text, ""), "hidden\n")
})

test_that("console controls stay out of R-tool results while normal prints remain", {
  home = new.env()
  home$notice = console_notice
  home$verbatim = msg_verbatim
  out = utils::capture.output({
    err = utils::capture.output({
      result = eval_r('cat("before\\n"); notice("control"); verbatim("printed"); 7', home,
                       plots = "none", tee = TRUE)
    }, type = "message")
  })
  expect_identical(out, c("before", "control", "printed", "[1] 7"))
  expect_identical(err, character())
  events = Filter(function(e) e$type %in% c("output", "message"), result$events)
  captured = paste(vapply(events, function(e) e$text %||% "", ""), collapse = "")
  expect_false(grepl("control", captured, fixed = TRUE))
  expect_true(grepl("printed", captured, fixed = TRUE))
})

test_that("informational display preserves user-created output sinks", {
  local_gptr_options(quiet = FALSE)
  for (split in c(FALSE, TRUE)) {
    path = withr::local_tempfile()
    home = new.env()
    home$inform = gptr_inform
    home$path = path
    home$split = split
    out = utils::capture.output({
      result = eval_r(paste0('con = file(path, "w"); sink(con, split = split); ',
        'depth = sink.number(); inform("notice", "notice"); ',
        'same_depth = identical(depth, sink.number()); cat("user output\\n"); ',
        'sink(); close(con); cat("restored\\n")'), home, plots = "none", tee = TRUE)
    })
    expect_true(home$same_depth)
    expect_identical(readLines(path), c("notice", "user output"))
    expect_identical(out, if (split) c("notice", "user output", "restored") else "restored")
    events = Filter(function(e) e$type %in% c("output", "message"), result$events)
    messages = Filter(function(e) e$type == "message", events)
    expect_identical(vapply(messages, function(e) e$text, ""), "notice\n")
    output = paste(vapply(Filter(function(e) e$type == "output", events),
                          function(e) e$text, ""), collapse = "")
    expect_false(grepl("notice", output, fixed = TRUE))
    expect_true(grepl("restored", output, fixed = TRUE))
  }
})

test_that("JSONL reserves stdout for events even when a real CLI notice is signalled", {
  local_project()
  local_gptr_options(quiet = FALSE, record = "off")
  old = the$once
  the$once = new.env(parent = emptyenv())
  withr::defer({
    the$once = old
  })
  s = peter("offline", model = gptr_fake_provider(list("unused")), .run = FALSE,
            envir = new.env())
  seen = new.env(parent = emptyenv())
  local_mocked_bindings(gptr_wait = function(session) {
    pcli_notice("codex")
    jsonl_write(stdout(), ev_new("agent_end", session = session$id, status = "idle", turns = 0L))
    invisible(session)
  })
  out = utils::capture.output({
    err = utils::capture.output(withCallingHandlers(jsonl_frontend_run(s),
      gptr_message_notice = function(cnd) seen$cnd = cnd), type = "message")
  })
  expect_length(out, 1L)
  expect_identical(json_decode(out)$type, "agent_end")
  expect_length(err, 1L)
  expect_true(startsWith(err, "The codex route uses your own Codex CLI"))
  expect_s3_class(seen$cnd, "gptr_message_notice")
  expect_identical(utils::capture.output(gptr_inform("ordinary again", "notice")),
                   "ordinary again")
})
