# Waiting feedback must precede live inference, remain outside captured R-tool output, and
# survive a resumed pause; on a dynamic console it is the live row (D-243). These tests drive
# renderer hooks directly; no request is sent.
wait_record = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_fake_provider(list("ok"), .env = .env)
  s = session_new("fake/fake-1", "auto", home = new.env())
  run = new.env(parent = emptyenv())
  run$id = "u0000wait"
  run$status = "streaming"
  run$opts = list(background = FALSE)
  class(run) = "gptr_run"
  live = session_live(s)
  live$run = run
  ctx = live$ctx
  console_on_agent_start(ev_new("agent_start", run = run$id), ctx)
  withr::defer({
    console_drop(run$id)
    live$run = NULL
  }, envir = .env)
  local_live_console(.env = .env)
  list(s = s, live = live, ctx = ctx, run = run, rec = console_record(list(run = run$id)))
}

wait_request = function(w) {
  console_on_before_request(ev_new("before_request", run = w$run$id, request_id = "q-wait",
                                  model = "fake/fake-1", tokens_est = 10), w$ctx)
}

wait_delta = function(w, text) {
  console_on_message_update(ev_new("message_update", run = w$run$id, index = 1L,
                                  kind = "text", delta = text), w$ctx)
}

wait_interrupt = function() {
  cnd = structure(list(message = "", call = NULL), class = c("interrupt", "condition"))
  withRestarts(signalCondition(cnd), resume = function() invisible(NULL))
}

test_that("verbosity 1 announces inference on stderr without animation", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  out = utils::capture.output({
    expect_message(wait_request(w), "gptr: thinking", fixed = TRUE)
  })
  expect_identical(out, character())
  expect_null(the$live_row)
})

test_that("a non-dynamic streamed console receives a concise waiting message", {
  local_gptr_options(verbose = 2L, quiet = FALSE)
  w = wait_record()
  withr::local_options(cli.dynamic = FALSE)
  expect_message(wait_request(w), "gptr: thinking", fixed = TRUE)
  expect_null(the$live_row)
})

test_that("Rscript and other non-interactive R draw no live row (class P)", {
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  local_live_console("P")
  expect_no_message(expect_identical(utils::capture.output(invisible(wait_request(w))),
                                     character()))
  expect_null(the$live_row)
})

test_that("R.app draws no live row: a carriage return there restyles what follows (review)", {
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  local_live_console("L")
  local_mocked_bindings(platform_gui = function() "AQUA")
  expect_identical(utils::capture.output(invisible(wait_request(w))), character())
  expect_null(the$live_row)
})

test_that("verbosity zero and background requests produce no waiting feedback", {
  local_gptr_options(verbose = 0L, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  expect_no_message(expect_output(wait_request(w), NA))
  expect_null(the$live_row)
  local_gptr_options(verbose = 2L)
  w$live$background = list(id = "b-wait")
  expect_no_message(expect_output(wait_request(w), NA))
  expect_null(the$live_row)
})

test_that("the live row replaces the old waiting text, at column 0 (D-243)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = TRUE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "terminal")
  w = wait_record()
  out = utils::capture.output(invisible(wait_request(w)))
  expect_identical(sub(" +$", "", out), "\r\u258c thinking 0s \u00b7 ctrl-c stops")
  expect_false(any(grepl("Ctrl-C to|steer or stop|\\(0s", out)))
  # it names the running tool, then thinks again at the next request
  withr::local_options(cli.ansi = TRUE)
  utils::capture.output(console_live_stop())
  utils::capture.output(invisible(wait_request(w)))
  tool = ev_new("tool_execution_start", run = w$run$id, tool_call_id = "c1", tool_name = "r",
                input = list(code = "zz = 1"))
  out = utils::capture.output(invisible(console_on_tool_start(tool, w$ctx)))
  expect_identical(out[[length(out)]], paste0("\r\u258c r 0s \u00b7 ctrl-c stops", "\033[K"))
  out = utils::capture.output(invisible(wait_request(w)))
  expect_identical(out, paste0("\r\u258c thinking 0s \u00b7 ctrl-c stops", "\033[K"))
})

test_that("the live row is drawn at once and stays under the rows of an answer (D-243)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE, cli.ansi = TRUE)
  w = wait_record()
  first = utils::capture.output(invisible(wait_request(w)))
  expect_true(any(grepl("thinking", first, fixed = TRUE)))
  row = the$live_row
  for (delta in c("", "\n", " \t", "```r")) {
    expect_identical(utils::capture.output(invisible(wait_delta(w, delta))), character())
    expect_true(row$shown)
  }
  bytes = written(function() wait_delta(w, "\nx = 1\n"))
  # cleared, the rows written, then the row again below them
  expect_true(startsWith(bytes, "\r\033[K"))
  expect_identical(term_rows(bytes), c("", "  ```r", "  x = 1", "# thinking 0s - ctrl-c stops"))
  expect_identical(the$live_row, row)
  expect_true(row$shown)
})

test_that("where the live row is padded, the first whole row ends it until the next wait (D-245)", {
  testthat::local_reproducible_output(width = 80, crayon = TRUE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  expect_identical(utils::capture.output(invisible(wait_delta(w, "# Hea"))), character())
  expect_true(the$live_row$shown)
  out = utils::capture.output(invisible(wait_delta(w, "ding\n")))
  expect_identical(out[[1L]], paste0("\r", strrep(" ", 79L), "\r"))
  expect_false(the$live_row$shown)
  expect_false(the$live_row$on)
  # its task draws nothing until the run waits again
  tick = get(the$live_row$task, envir = reactor_get()$tasks)$fn
  expect_identical(utils::capture.output(invisible(tick())), character())
  utils::capture.output(invisible(wait_request(w)))
  expect_true(the$live_row$shown)
})

test_that("live row redraws cannot enter a nested R tool's captured output", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  task = get(the$live_row$task, envir = reactor_get()$tasks)
  nested = function() {
    .gptr_tool_run = w$run
    force(.gptr_tool_run)
    utils::capture.output(invisible(task$fn()))
  }
  expect_identical(nested(), character())
  expect_false(is.null(the$live_row))
  w$live$background = list(id = "b-wait")
  expect_identical(utils::capture.output(invisible(task$fn())), character())
})

test_that("an abort-only IDE console advertises its stop key without promising a pause", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, interactive = TRUE)
  withr::local_options(cli.dynamic = TRUE)
  testthat::local_mocked_bindings(front_end = function() "rstudio")
  w = wait_record()
  local_live_console("L")
  # RStudio honours \033[K, so no padding stays in its transcript (visual review)
  expect_identical(utils::capture.output(invisible(wait_request(w))),
                   "\r# thinking 0s - esc stops\033[K")
  # Positron's console erases by writing spaces, so its row is padded as R.app's
  testthat::local_mocked_bindings(front_end = function() "positron")
  utils::capture.output(console_live_stop())
  expect_identical(sub(" +$", "", utils::capture.output(invisible(wait_request(w)))),
                   "\r# thinking 0s - ctrl-c pauses")
})

test_that("continue and queued pause messages restore a pending request's live row", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, interactive = TRUE, quiet = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  answers = new.env(parent = emptyenv())
  answers$left = c("c", "s", "use only x", "f", "then summarize")
  testthat::local_mocked_bindings(front_end = function() "terminal",
    gptr_readline = function(prompt = "") {
      ans = answers$left[[1L]]
      answers$left = answers$left[-1L]
      ans
    })
  utils::capture.output(invisible(wait_request(w)))
  for (i in seq_len(3L)) {
    utils::capture.output({
      utils::capture.output({
        with_interrupt_policy(wait_interrupt, list(w$run), mode = "call")
      }, type = "message")
    })
    expect_true(the$live_row$shown)
  }
  expect_identical(length(session_data(w$s)$queue$steer), 1L)
  expect_identical(length(session_data(w$s)$queue$follow_up), 1L)
})

test_that("a prompt clears the live row, keeps its task and a later tick redraws (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  local_mocked_bindings(front_end = function() "terminal")
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  task = the$live_row$task
  code = "gptr_mcp_serve()"
  req = list(tool = "r", input = list(code = code), risk = gptr_risk(code), tier = "ask_human")
  prompts = list(function() ui_console_permission(req, read = function(...) "n"),
                 function() ui_console_select("Pick one", c("a", "b"), read = function(...) "1"))
  seen = character()
  for (prompt in prompts) {
    utils::capture.output(invisible(the$live_row$draw()))
    con = rawConnection(raw(), "w")
    sink(con)
    tryCatch(invisible(prompt()), finally = sink())
    seen = c(seen, rawToChar(rawConnectionValue(con)))
    close(con)
    expect_false(the$live_row$shown)
    expect_identical(the$live_row$task, task)
    redraw = utils::capture.output(invisible(get(task, envir = reactor_get()$tasks)$fn()))
    # the row is no block: it comes back right under the question's last row
    expect_identical(sub(" +$", "", redraw), "\r# thinking 0s - ctrl-c stops")
  }
  clear = paste0("\r", strrep(" ", 79L), "\r")
  expect_true(startsWith(seen[[1L]], paste0(clear, "\n  | r  gptr_mcp_serve()")))
  expect_true(startsWith(seen[[2L]], paste0(clear, "\n  ? Pick one")))
})

test_that("consecutive prompts in a run stay separated by a blank line (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  w$rec$last = "text"
  read = function(prompt = "", ...) {
    cat(prompt, "1\n", sep = "")
    "1"
  }
  qs = list(list(id = "a", question = "First?", options = c("x", "y")),
            list(id = "b", question = "Second?", options = c("p", "q")),
            list(id = "c", question = "Name?", type = "text"))
  out = utils::capture.output(invisible(ui_questions_via(
    function(...) ui_console_select(..., read = read),
    function(...) ui_console_input(..., read = read), qs)))
  for (title in c("  ? First?", "  ? Second?", "  ? Name?")) {
    expect_identical(out[[which(out == title) - 1L]], "")
  }
  expect_identical(sum(!nzchar(out)), 3L)
})

test_that("a CLI tool line names the tool on the live row, then thinking while pending (D-243)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  tool = function(type) {
    ev_new(type, run = w$run$id, tool_call_id = "codex_1", tool_name = "codex_shell",
           input = list(command = "ls"), is_error = FALSE, elapsed = NA_real_)
  }
  utils::capture.output(invisible(console_on_tool_start(tool("tool_execution_start"), w$ctx)))
  expect_identical(w$rec$what, "codex_shell")
  out = utils::capture.output(invisible(console_on_tool_end(tool("tool_execution_end"), w$ctx)))
  expect_identical(w$rec$what, "thinking")
  expect_match(out, "thinking 0s", fixed = TRUE)
  expect_true(the$live_row$shown)
  w$rec$request_pending = FALSE
  utils::capture.output(console_live_stop())
  utils::capture.output(invisible(console_on_tool_end(tool("tool_execution_end"), w$ctx)))
  expect_null(the$live_row)
})

test_that("CLI tool items add no progress lines on a non-dynamic console (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = FALSE)
  w = wait_record()
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output({
      wait_request(w)
      for (type in rep(c("tool_execution_start", "tool_execution_end"), 3L)) {
        fun = if (endsWith(type, "start")) console_on_tool_start else console_on_tool_end
        fun(ev_new(type, run = w$run$id, tool_call_id = "codex_1", tool_name = "codex_shell",
                   input = list(command = "ls"), is_error = FALSE, elapsed = NA_real_), w$ctx)
      }
    }, type = "message")
  })
  expect_identical(sum(grepl("gptr: thinking", c(out, err), fixed = TRUE)), 1L)
})

test_that("the live row stays to the run's end, which takes it and its task down (D-243)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  w = wait_record()
  utils::capture.output(invisible(wait_request(w)))
  task = the$live_row$task
  utils::capture.output(invisible(console_on_message_end(
    ev_new("message_end", run = w$run$id,
           message = msg_assistant("", api = "fake", provider = "fake", model = "fake-1")),
    w$ctx)))
  expect_identical(the$live_row$task, task)
  out = utils::capture.output(invisible(console_on_agent_end(
    ev_new("agent_end", run = w$run$id, status = "error", reason = "synthetic error"), w$ctx)))
  expect_identical(out[[1L]], paste0("\r", strrep(" ", 79L), "\r"))
  expect_null(console_record(list(run = w$run$id)))
  expect_null(the$live_row)
  expect_false(exists(task, envir = reactor_get()$tasks, inherits = FALSE))
})

test_that("background notices remove all synthetic bidi and invisible controls", {
  controls = c(0x061CL, 0x2060L:0x2065L, 0x2066L:0x2069L, 0xFEFFL)
  for (cp in controls) {
    expect_identical(bg_clean(paste0("left", intToUtf8(cp), "right")), "left right")
  }
  expect_identical(bg_clean("literal <U+2060>"), "literal <U+2060>")
  expect_identical(bg_clean(c(NA_character_, "safe")), c("", "safe"))
})
