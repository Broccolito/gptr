# tests/testthat/test-console-render.R -- the console's printing layer (P14)

render_sample = paste0(
  "# Model summary\n\nThe **linear model** explains most of the variance in `mpg`; the ",
  "coefficient on `wt` is strongly negative, which means heavier cars travel fewer miles ",
  "per gallon on average.\r\n\r\n",
  "- first bullet that is long enough to need wrapping onto a second line at forty columns\n",
  "- second bullet with **bold text** inside\n",
  "1. numbered item\n\n",
  "> a quoted remark from the user\n\n",
  "```r\nfit = lm(mpg ~ wt, data = mtcars)\nsummary(fit)$r.squared\n```\n",
  "Done: R\u00b2 = 0.75 \u2014 averaging wide chars \u4e2d\u6587\u5b57\u7b26 too.")

render_chunks = function(chunks, width = 40L) {
  utils::capture.output({
    r = render_markdown_stream(width)
    for (ch in chunks) r$write(ch)
    r$finish()
  })
}

random_chunks = function(x, maxlen) {
  chars = strsplit(x, "")[[1L]]
  out = character()
  i = 1L
  while (i <= length(chars)) {
    k = sample.int(maxlen, 1L)
    out = c(out, paste(chars[i:min(length(chars), i + k - 1L)], collapse = ""))
    i = i + k
  }
  out
}

test_that("the output does not depend on chunking, plain and styled (acceptance 3)", {
  withr::local_seed(42)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    ref = render_chunks(render_sample)
    same = vapply(seq_len(200L), function(i) {
      identical(render_chunks(random_chunks(render_sample, sample.int(9L, 1L))), ref)
    }, NA)
    expect_true(all(same))
  }
})

test_that("prose lines respect the width and bullets hang (UTF-8 locale)", {
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "display widths need a UTF-8 locale (report 18)")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks(render_sample, width = 40L)
  prose = out[!grepl("^(```|fit|summary)", out)]
  expect_true(all(nchar(prose, type = "width") <= 40L))
  expect_true("- first bullet that is long enough to" %in% out)
  expect_true("  need wrapping onto a second line at" %in% out)
  expect_true("fit = lm(mpg ~ wt, data = mtcars)" %in% out)
})

test_that("a CRLF split across two chunks gives one line break", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(render_chunks(c("one\r", "\ntwo")), render_chunks("one\r\ntwo"))
  expect_identical(render_chunks("one\r\ntwo"), c("one", "two"))
  expect_identical(render_chunks(c("one\r", "two")), c("one", "two"))
})

test_that("untrusted braces are printed verbatim and never evaluated (rule C1)", {
  withr::local_envvar(GPTR_PWNED = NA)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_chunks(c("Try {Sys.setenv(GPTR", "_PWNED = \"1\")} now"), width = 80L)
    expect_true(any(grepl("{Sys.setenv(GPTR_PWNED = \"1\")}", out, fixed = TRUE)))
  }
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("control, bidi, zero-width characters and invalid bytes are escaped (IC-53 item 8)", {
  expect_identical(console_escape("a\033[31mb"), "a<U+001B>[31mb")
  expect_identical(console_escape(paste0("x", intToUtf8(0x202e), "y")), "x<U+202E>y")
  expect_identical(console_escape(paste0("x", intToUtf8(0x200b), "y")), "x<U+200B>y")
  expect_identical(console_escape("tab\there\nnext"), "tab\there\nnext")
  expect_identical(console_escape("a\nb", newlines = FALSE), "a<U+000A>b")
  expect_identical(console_escape(c("ok", NA, "")), c("ok", NA, ""))
  expect_identical(console_escape("caf\u00e9"), "caf\u00e9")
  expect_identical(console_escape("end\n"), "end\n")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks("red \033[31mtext\033[0m", width = 80L)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_true(any(grepl("<U+001B>[31m", out, fixed = TRUE)))
  bad = rawToChar(as.raw(c(0x61, 0xff, 0x0a, 0x62)))
  expect_identical(console_escape(bad), "a<ff>\nb")
  expect_identical(console_escape(paste0("\033", bad), newlines = FALSE), "<U+001B>a<ff><U+000A>b")
  surrogate = rawToChar(as.raw(c(0xed, 0xa0, 0x80, 0x1b)))
  expect_identical(console_lines(surrogate), "<ed><a0><80><U+001B>")
  expect_identical(console_lines(bad), c("a<ff>", "b"))
  expect_identical(render_chunks(bad), c("a<ff>", "b"))
})

test_that("console_lines() splits on any line end and console_out() prints escaped lines", {
  expect_identical(console_lines(c("a\r\nb\rc", "d\033")), c("a", "b", "c", "d<U+001B>"))
  expect_identical(console_lines(NA_character_), character())
  expect_identical(utils::capture.output(console_out("x {y}\ny\033")), c("x {y}", "y<U+001B>"))
})

test_that("notices go to stderr, never to stdout", {
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output(console_notice("[gptr] ", "hello"), type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "[gptr] hello")
})

test_that("reset_line() ends a partial line and finish() closes it", {
  withr::local_options(cli.num_colors = 1L)
  out = utils::capture.output({
    r = render_markdown_stream(80L)
    r$write("partial answer ")
    r$write("continues")
    r$reset_line()
    r$write(" next line")
    r$finish()
  })
  expect_identical(out, c("partial answer", "continues next line"))
})

test_that("console_print_text() prints a whole reply and skips empty text", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(utils::capture.output(console_print_text("Hello **there**")),
                   "Hello **there**")
  expect_identical(utils::capture.output(console_print_text(NA_character_)), character())
  expect_identical(utils::capture.output(console_print_text("")), character())
})

test_that("the spinner is silent when stdout is not a dynamic terminal", {
  withr::local_options(cli.dynamic = FALSE)
  sp = console_spinner()
  expect_identical(utils::capture.output({
    sp$tick()
    sp$clear()
  }), character())
})

test_that("the interrupt key follows the front end", {
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(console_interrupt_key(), "Esc")
  local_mocked_bindings(front_end = function() "terminal")
  expect_identical(console_interrupt_key(), "Ctrl-C")
})

# ---------------------------------------------------------------- Task 2: renderer hooks

# A real, idle session that never ran (its prompt waits in the queue): the hooks only read it
render_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

# Run events through the handlers that console_hooks() registers, capturing stdout
render_events = function(s, events) {
  hooks = console_hooks()
  types = vapply(hooks, function(h) h$event, "")
  ctx = session_live(s)$ctx
  utils::capture.output({
    for (ev in events) {
      for (h in hooks[types == ev$type]) h$handler(ev, ctx)
    }
  })
}

hook_event = function(type, s, ..., run = "u0000test") {
  ev_new(type, session = session_data(s)$id, run = run, ...)
}

assistant_msg = function(text) {
  msg_assistant(text, api = "fake", provider = "fake", model = "fake-1")
}

test_that("console_hooks() subscribes the events of contract 7.14", {
  events = vapply(console_hooks(), function(h) h$event, "")
  expect_true(all(c("message_update", "message_end", "tool_execution_start",
                    "tool_execution_end", "agent_end", "artifact_start") %in% events))
  expect_true(all(vapply(console_hooks(), function(h) inherits(h, "gptr_hook"), NA)))
})

test_that("a foreground run streams its answer and ends with a status line (verbosity 2)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Hello **wo"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "rld** {x}\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Hello")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L)))
  expect_identical(out, c("Hello **world** {x}", "  done | 1 turn | 0 tokens | $0.0000"))
  expect_null(console_record(list(run = "u0000test")))
})

test_that("nothing is printed at verbosity 0 or for a background session", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  s = render_session()
  events = list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "quiet"),
    hook_event("agent_end", s, status = "idle", usage = NULL, turns = 1L))
  local_gptr_options(verbose = 0L)
  expect_identical(render_events(s, events), character())
  local_gptr_options(verbose = 2L)
  live = session_live(s)
  live$background = list(id = "s-in-the-background")
  withr::defer({
    live$background = NULL
  })
  expect_identical(render_events(s, events), character())
})

test_that("an answer without deltas is printed whole at message_end", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("All at once."))))
  expect_identical(out, "All at once.")
})

test_that("tool lines escape the preview and summarise the result (acceptance 7)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  result = msg_tool_result("c1", "r", "ok", details = list(
    objects = list(added = c("x", "y"), modified = character(), removed = character()),
    plots = 0L))
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "x = 1 # \033[31mred\ny = 2")),
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 2.5, details = list()),
    hook_event("message_end", s, role = "tool_result", message = result)))
  expect_identical(out, c("  * r  x = 1 # <U+001B>[31mred  (+1 more lines)",
                          "    -> + x, y (2.5 s)"))
  expect_false(any(grepl("\033", out, fixed = TRUE)))
})

test_that("an error result shows its first line", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  bad = msg_tool_result("c2", "r", "Error: object 'z' not found\nIn: z + 1", is_error = TRUE)
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c2", tool_name = "r",
               input = list(code = "z + 1")),
    hook_event("message_end", s, role = "tool_result", message = bad)))
  expect_identical(out[[2L]], "    -> error: Error: object 'z' not found")
})

test_that("a tool's render() function replaces the default lines (IC-69)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  shout = gptr_spec("tool", "shout", description = "Shout a text.",
                    parameters = list(type = "object",
                                      properties = list(text = list(type = "string"))),
                    execute = function(input, ctx) "ok",
                    render = function(call, result, width) {
                      if (is.null(result)) paste("SHOUT", call$input$text) else "SHOUTED"
                    })
  off = gptr_register(shout)
  withr::defer(off())
  call = list(id = "c1", name = "shout", input = list(text = "hi\033"))
  expect_identical(console_tool_line(call), "SHOUT hi<U+001B>")
  expect_identical(console_tool_line(call, list(is_error = FALSE)), "SHOUTED")
})

test_that("artifact_start prints the NS-8 line (acceptance 7)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  ev = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
              version = 1L)
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(invisible(console_on_artifact_start(ev, NULL))),
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
  local_gptr_options(verbose = 1L, quiet = FALSE)
  expect_message(console_on_artifact_start(ev, NULL), class = "gptr_message_progress")
})

test_that("an artifact_start fired while a tool executes prints after tool_execution_end", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  st = console_state()
  st$artifacts = NULL
  withr::defer({
    st$artifacts = NULL
    console_drop("u0000test")
  })
  s = render_session()
  ctx = session_live(s)$ctx
  in_tool = structure(new.env(parent = emptyenv()), class = "gptr_run")
  art = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
               version = 1L)
  line = "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)"
  invisible(utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "a = peter$app()")),
                          ctx)
  }))
  # inside the model's r code (run_current() non-NULL; P09 captures this output): queued; a
  # nested tool call (peter$<tool>() in that code) ends while the r tool still runs
  inside = local({
    local_mocked_bindings(run_current = function() in_tool)
    utils::capture.output({
      console_on_artifact_start(art, ctx)
      invisible(console_on_tool_end(hook_event("tool_execution_end", s, tool_call_id = "n1",
                                               tool_name = "read", is_error = FALSE,
                                               elapsed = 0.1, details = list()), ctx))
    })
  })
  expect_identical(inside, character())
  expect_identical(console_state()$artifacts, line)
  after = utils::capture.output(invisible(console_on_tool_end(
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 0.2, details = list()), ctx)))
  expect_identical(after, line)
  expect_null(console_state()$artifacts)
})

test_that("a run's events while a tool executes print nothing (P09 captures that output)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  withr::defer(console_drop("u0000test"))
  # a nested peter$read() inside the model's r code
  local_mocked_bindings(run_current = function() structure(new.env(), class = "gptr_run"))
  start = hook_event("tool_execution_start", s, tool_call_id = "c1/1", tool_name = "read",
                     input = list(path = "a.txt"))
  end = hook_event("tool_execution_end", s, tool_call_id = "c1/1", tool_name = "read",
                   is_error = TRUE, elapsed = 0.1, details = list())
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(invisible(console_on_tool_start(start, ctx))),
                   character())
  local_gptr_options(verbose = 1L, quiet = FALSE)
  expect_no_message(console_on_tool_start(start, ctx))
  expect_no_message(console_on_tool_end(end, ctx))
})

test_that("verbosity 1 reports tool calls and the end as progress messages", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  expect_message(
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "dim(x)")), ctx),
    "gptr: r  dim(x)", fixed = TRUE)
  expect_message(
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 2L),
                         ctx),
    "gptr: done | 2 turns", fixed = TRUE)
})

test_that("the status line names an unusual end and sums the usage rows", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  usage = data.frame(input = c(1000, 200), output = c(50, 10), cache_read = c(0, 900),
                     cost = c(0.001, 0.0005))
  expect_identical(console_status_line("idle", NULL, usage, 3L),
                   "  done | 3 turns | 2.2k tokens | $0.0015")
  expect_identical(console_status_line("aborted", "aborted (user)", NULL, 1L),
                   "  aborted: aborted (user) | 1 turn | 0 tokens | $0.0000")
  expect_identical(console_status_line("idle", NULL, data.frame(input = 999950), 1L),
                   "  done | 1 turn | 1.0M tokens | $0.0000")
  usage$cost[[2L]] = NA
  usage$output[[1L]] = NA
  expect_identical(console_status_line("idle", NULL, usage, 3L),
                   "  done | 3 turns | unknown tokens | unknown cost")
})

test_that("custom entries of a run are shown through renderer records (IC-69)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  off = gptr_register(gptr_spec("renderer", "demo.note",
                                render = function(entry, width, ctx) {
                                  paste("NOTE:", entry$data$text)
                                }))
  withr::defer(off())
  s = render_session()
  ctx = session_live(s)$ctx
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    session_append(s, list(type = "custom", custom_type = "demo.note",
                           data = list(text = "kept \033 safe")))
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 0L),
                         ctx)
  })
  expect_identical(out[[1L]], "NOTE: kept <U+001B> safe")
})

test_that("the spinner runs as a reactor task from before_request to the first delta", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  rec = console_record(list(run = "u0000test"))
  console_on_before_request(hook_event("before_request", s, provider = "fake",
                                       model = "fake/fake-1", request_id = "q1",
                                       tokens_est = 10), ctx)
  expect_false(is.null(rec$task))
  utils::capture.output(console_on_message_update(
    hook_event("message_update", s, index = 1L, kind = "text", delta = "x"), ctx))
  expect_null(rec$task)
  expect_null(rec$spinner)
  console_drop("u0000test")
})

test_that("permission_request ends partial lines and never decides", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_message_update(hook_event("message_update", s, index = 1L, kind = "text",
                                         delta = "partial "), ctx)
    expect_null(console_on_permission(hook_event("permission_request", s), ctx))
    cat("allow? ")
  })
  expect_identical(out, c("partial", "allow? "))
  console_drop("u0000test")
})

# ---------------------------------------------------------------- Task 7: end-to-end rendering

test_that("a streamed reply is printed verbatim and never evaluated (acceptance 3, rule C1)", {
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_envvar(GPTR_PWNED = NA)
  fake = gptr_fake_provider(list("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care."))
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter("hi", model = fake, envir = new.env()))
  })
  expect_true("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care." %in% out)
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_false(res$visible)
  expect_match(out[[length(out)]], "^  done \\| 1 turn \\| ")
})

test_that("nothing is rendered at verbosity 0 (knitr, testthat)", {
  local_project()
  local_gptr_options(verbose = 0L, record = "off")
  out = utils::capture.output(invisible(peter("hi", model = gptr_fake_provider(list("quiet")),
                                             envir = new.env())))
  expect_false(any(grepl("quiet", out, fixed = TRUE)))
})

test_that("tool calls of a run show escaped previews and results (acceptance 7)", {
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1 # \033[31mred")),
                                 "done"))
  e = new.env(parent = globalenv())
  out = utils::capture.output(peter("go", model = fake, envir = e, mode = auto))
  expect_true("  * r  z = 1 # <U+001B>[31mred" %in% out)
  # the elapsed time follows when the call took a second or more (a first call on a slow runner)
  expect_match(out, "^    -> \\+ z( \\([0-9.]+ s\\))?$", all = FALSE)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_identical(e$z, 1)
})

test_that("artifact_start events print the NS-8 line through builtin:console (acceptance 7)", {
  local_gptr_options(verbose = 2L)
  out = utils::capture.output(invisible(ev_dispatch("artifact_start", ev_new(
    "artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827", version = 1L))))
  expect_identical(out,
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
})

# ---------------------------------------------------------------- Task 8: INFRA-27

# Rendering is decoupled from transport (INFRA-27, 03 section 2.2 rule 2): the JSONL transcript
# of one run does not depend on what the renderer prints.

# Fields that depend on time or on generated ids (contract 12.3 golden-event rule: ts, session,
# run, request_id; plus the other clocks, the prefix guard's view of the request and the r
# tool's checkpoint entry id)
infra27_volatile = c("ts", "timestamp", "session", "run", "request_id", "requestId", "elapsed",
                     "started", "seconds", "view", "response_id", "responseId", "checkpoint")

infra27_norm_value = function(x) {
  if (is.list(x)) {
    nms = names(x)
    if (!is.null(nms)) x = x[!(nms %in% infra27_volatile)]
    return(lapply(x, infra27_norm_value))
  }
  if (is.character(x)) {
    x = gsub("\\bs[0-9a-f]{10}\\b", "<session>", x, perl = TRUE)
    x = gsub("\\bu[0-9a-f]{8}\\b", "<run>", x, perl = TRUE)
    x = gsub("\\bq[0-9a-f]{12}\\b", "<request>", x, perl = TRUE)
  }
  x
}

infra27_normalise = function(lines) {
  vapply(lines, function(l) json_encode(infra27_norm_value(json_decode(l))), "",
         USE.NAMES = FALSE)
}

# One fake-provider run (an `r` call, then an answer) streamed to a JSONL file at `verbose`,
# with whatever the renderer prints captured and discarded; the free RAM in <environment> is fixed
infra27_run = function(verbose) {
  local_gptr_options(verbose = verbose, quiet = TRUE, record = "off")
  local_mocked_bindings(context_r_line = function() "R")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1")),
                                 "The answer is 42."))
  s = peter("compute", model = fake, .run = FALSE, envir = new.env(parent = globalenv()),
           mode = "auto")
  file = tempfile(fileext = ".jsonl")
  on.exit(unlink(file), add = TRUE)
  con = file(file, open = "wb")
  off = jsonl_sink(s, con)
  utils::capture.output(gptr_step(s, turns = Inf))
  off()
  close(con)
  readLines(file, encoding = "UTF-8", warn = FALSE)
}

test_that("the transcript is the same at verbosity 0, 1 and 2 (INFRA-27, acceptance 4)", {
  local_project()
  v0 = infra27_normalise(infra27_run(0L))
  v1 = infra27_normalise(infra27_run(1L))
  v2 = infra27_normalise(infra27_run(2L))
  expect_gt(length(v0), 10L)
  expect_identical(v1, v0)
  expect_identical(v2, v0)
})
