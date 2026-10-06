# tests/testthat/test-console-repl.R -- the console REPL (plan P14).
# Task 4: REPL state and the input layer; Task 5: `!expr`, notes, mentions and console_send();
# Task 7: scripted console sessions.

# The REPL's persistent stdin connection replaced by a text connection over `lines`
local_console_stdin = function(lines, .env = parent.frame()) {
  testthat::local_mocked_bindings(console_stdin_open = function() textConnection(lines),
                                  .env = .env)
}

# A reader over `lines` (piped input, no echo unless asked)
stdin_reader = function(lines, echo = FALSE, .env = parent.frame()) {
  local_console_stdin(lines, .env = .env)
  rd = console_reader(stdin = TRUE, echo = echo)
  withr::defer(rd$close(), envir = .env)
  rd
}

test_that("the stdin reader reads one line per call and NA at the end", {
  rd = stdin_reader(c("first", "second"))
  expect_identical(rd$read("peter> "), "first")
  expect_identical(rd$read("peter> "), "second")
  expect_identical(rd$read("peter> "), NA_character_)
})

test_that("the stdin reader echoes the prompt and the escaped line when asked", {
  rd = stdin_reader("hello \033", echo = TRUE)
  got = NULL
  out = utils::capture.output({
    got = rd$read("peter> ")
  })
  expect_identical(out, "peter> hello <U+001B>")
  expect_identical(got, "hello \033")
})

test_that("close() closes the stdin connection once (IC-59)", {
  n0 = nrow(showConnections())
  local_console_stdin("x")
  rd = console_reader(stdin = TRUE)
  expect_identical(nrow(showConnections()), n0 + 1L)
  rd$close()
  rd$close()
  expect_identical(nrow(showConnections()), n0)
  expect_identical(rd$read(""), NA_character_)
})

test_that("a triple-quote block is one prompt", {
  rd = stdin_reader(c('"""', "line one", "line two", '"""', "next"))
  expect_identical(repl_read_logical(rd, "peter> "), "line one\nline two")
  expect_identical(repl_read_logical(rd, "peter> "), "next")
  rd = stdin_reader(c('"""one line"""'))
  expect_identical(repl_read_logical(rd, "peter> "), "one line")
})

test_that("a fenced block is R code and ! code continues while incomplete", {
  rd = stdin_reader(c("```r", "x = 1", "y = 2", "```", "!for (i in 1:2) {", "  print(i)", "}",
                      "!!z = 3"))
  expect_identical(repl_read_logical(rd, "peter> "), "!x = 1\ny = 2")
  expect_identical(repl_read_logical(rd, "peter> "), "!for (i in 1:2) {\n  print(i)\n}")
  expect_identical(repl_read_logical(rd, "peter> "), "!!z = 3")
})

test_that("a trailing backslash continues a line; end of input ends every block", {
  rd = stdin_reader(c("first part \\", "second part"))
  expect_identical(repl_read_logical(rd, "peter> "), "first part \nsecond part")
  rd = stdin_reader(c('"""', "unterminated"))
  expect_identical(repl_read_logical(rd, "peter> "), "unterminated")
  expect_identical(repl_read_logical(rd, "peter> "), NA_character_)
  rd = stdin_reader("!f = function() {")
  expect_identical(repl_read_logical(rd, "peter> "), "!f = function() {")
})

test_that("r_incomplete() recognises incomplete code in any locale", {
  expect_true(r_incomplete("for (i in 1:2) {"))
  expect_true(r_incomplete("x = 'abc"))
  expect_false(r_incomplete("x = 1"))
  expect_false(r_incomplete("x = )"))
})

test_that("a line at the readline limit is warned about and dropped", {
  long = strrep("a", readline_limit())
  local_mocked_bindings(gptr_readline = function(prompt = "") long)
  rd = console_reader(stdin = FALSE)
  out = NULL
  expect_warning({
    out = repl_read_logical(rd, "peter> ")
  }, "next line you entered", class = "gptr_warning_readline_limit")
  expect_identical(out, "")
  expect_identical(readline_limit(), if (getRversion() >= "4.5.0") 8190L else 4095L)
})

test_that("repl_state() takes the console call's identifiers, options and objects", {
  e = new.env()
  call = list(ids = list(model = "fake/fake-1", mode = "auto", skills = "stats", tools = NULL,
                         plugins = NULL, extensions = NULL),
              args = list(budget = list(cost = 1),
                          opts = list(frontend = "console", max_turns = 5L),
                          envir_given = TRUE),
              context = list(list(label = "mtcars", kind = "symbol", name = "mtcars"),
                             list(label = "..2", kind = "value", name = NULL)))
  rs = repl_state(NULL, e, stdin = FALSE, call = call)
  expect_identical(rs$model, "fake/fake-1")
  expect_identical(rs$mode, "auto")
  expect_identical(rs$opts, list(max_turns = 5L))
  expect_identical(rs$attach, "mtcars")
  expect_identical(rs$budget, list(cost = 1))
  expect_identical(repl_eval_env(rs), e)
  expect_identical(repl_prompt(rs), "peter[auto]> ")
  expect_identical(repl_model(rs), "fake/fake-1")
  rs$mode = NULL
  local_gptr_options(mode = "manual")
  expect_identical(repl_prompt(rs), "peter> ")
  expect_error(repl_state(NULL, "not an env"), class = "gptr_error_invalid_argument")
})

test_that("console_history_add() never fails", {
  expect_null(console_history_add("a prompt"))
})

# ---------------------------------------------------------------- Task 5: !expr, notes, mentions

# The console's context blocks for this test unless builtin:console registered them already
local_console_blocks = function(.env = parent.frame()) {
  have = registry_names("context_block")
  for (spec in console_blocks()) {
    if (spec$name %in% have) next
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  invisible(NULL)
}

# Context blocks and text of the last user message a fake provider received, named by kind
last_user_blocks = function(req) {
  users = Filter(function(m) identical(m$role, "user"), req$messages)
  content = users[[length(users)]]$content
  kinds = vapply(content, function(b) if (identical(b$type, "context")) b$kind else b$type, "")
  stats::setNames(vapply(content, function(b) as.character(b$text %||% ""), ""), kinds)
}

test_that("notes keep the newest within the token budget and cut one long note", {
  notes = c("> a\n#> [1] 1", "> b\n#> [1] 2")
  text = console_notes_text(notes, 300L)
  expect_match(text, "^The user ran this R code in the session")
  expect_match(text, "> a\n#> [1] 1\n> b\n#> [1] 2", fixed = TRUE)
  many = vapply(1:200, function(i) paste0("> x", i, "\n#> [1] ", i), "")
  text = console_notes_text(many, 300L)
  expect_lte(est_tokens(text, "r_output"), 300)
  expect_match(text, "> x200", fixed = TRUE)
  expect_false(grepl("> x1\n", text, fixed = TRUE))
  expect_match(text, "earlier omitted", fixed = TRUE)
  long = paste(c("> big", paste0("#> ", strrep("y", 60), seq_len(200))), collapse = "\n")
  text = console_notes_text(long, 300L)
  expect_lte(est_tokens(text, "r_output"), 300)
  expect_match(text, "#> [... output cut]", fixed = TRUE)
  expect_null(console_notes_text(character()))
})

test_that("@mentions: files become <file> blocks, bound names become objects", {
  root = local_project(files = list("data/notes.txt" = c("line one", "line two")))
  e = new.env()
  e$tbl = data.frame(a = 1:3)
  men = repl_mentions("compare @tbl with @data/notes.txt and mail me@example.org", e)
  expect_identical(men$objects, "tbl")
  expect_length(men$files, 1L)
  expect_match(men$files, "<file path=\"data/notes.txt\">\nline one\nline two\n</file>",
               fixed = TRUE)
  expect_identical(repl_mentions("use @c and @nothing", e)$objects, character())
})

test_that("a binary @file is announced, not inlined", {
  root = local_project()
  writeBin(as.raw(c(0x50, 0x00, 0x01)), file.path(root, "blob.bin"))
  men = repl_mentions("look at @blob.bin", new.env())
  expect_match(men$files, "binary=\"true\" bytes=\"3\"", fixed = TRUE)
})

test_that("a long @file is marked truncated even when the first cut line is blank", {
  root = local_project(files = list("long.R" = c(paste0("l", 1:40), "", paste0("m", 1:10))))
  block = repl_mentions("see @long.R", new.env())$files
  expect_match(block, "<file path=\"long.R\" truncated=\"true\">\nl1\n", fixed = TRUE)
  expect_match(block, "\nl40\n</file>", fixed = TRUE)
})

test_that("!code runs in the REPL environment and leaves a note; !!code does not", {
  local_project()
  e = new.env()
  e$x = matrix(1:6, 2)
  rs = repl_state(NULL, e)
  out = utils::capture.output(repl_passthrough(rs, "!dim(x)"))
  expect_true("[1] 2 3" %in% out)
  expect_length(rs$notes, 1L)
  expect_match(rs$notes, "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  utils::capture.output(repl_passthrough(rs, "!!y = sum(x)"))
  expect_identical(e$y, 21L)
  expect_length(rs$notes, 1L)
})

test_that("!code errors are shown on stderr and noted", {
  local_project()
  rs = repl_state(NULL, new.env())
  err = utils::capture.output(invisible(utils::capture.output(
    repl_passthrough(rs, "!stop('boom')"))), type = "message")
  expect_true(any(grepl("Error: boom", err, fixed = TRUE)))
  expect_match(rs$notes, "boom", fixed = TRUE)
})

test_that("the input event (source passthrough) can handle or transform !code", {
  local_project()
  e = new.env()
  rs = repl_state(NULL, e)
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (!identical(event$source, "passthrough")) return(NULL)
    if (identical(event$text, "secret()")) return(list(action = "handled", text = ""))
    list(action = "transform", text = sub("^old", "new_value", event$text))
  }))
  withr::defer(off())
  utils::capture.output(repl_passthrough(rs, "!secret()"))
  expect_length(rs$notes, 0L)
  utils::capture.output(repl_passthrough(rs, "!old = 5"))
  expect_identical(e$new_value, 5)
})

test_that("!code is announced on the console:direct channel", {
  local_project()
  got = new.env(parent = emptyenv())
  off = gptr_register(gptr_hook("console:direct", function(event, ctx) {
    got$data = event$data
    NULL
  }))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  utils::capture.output(repl_passthrough(rs, "!1 + 1"))
  expect_identical(got$data$code, "1 + 1")
  expect_identical(got$data$status, "ok")
  expect_true(got$data$noted)
  expect_true(any(grepl("[1] 2", got$data$output, fixed = TRUE)))
})

test_that("console_send() makes an ordinary gateway call and continues the session", {
  local_project()
  local_console_blocks()
  fake = gptr_fake_provider(list("first answer", "second answer"))
  e = new.env()
  e$x = matrix(1:6, 2)
  rs = repl_state(NULL, e)
  rs$model = fake
  utils::capture.output(repl_passthrough(rs, "!dim(x)"))
  res = console_send(rs, "how big is it?")
  expect_identical(res$status, "ok")
  s = rs$session
  expect_s3_class(s, "gptr_session")
  expect_identical(s$text, "first answer")
  blocks = last_user_blocks(fake_requests(fake)[[1L]])
  expect_identical(unname(blocks[["text"]]), "how big is it?")
  expect_match(blocks[["user_ran"]], "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  expect_length(rs$notes, 0L)
  console_send(rs, "and now?")
  expect_identical(rs$session, s)
  expect_identical(s$turns, 2L)
  expect_false("user_ran" %in% names(last_user_blocks(fake_requests(fake)[[2L]])))
  expect_identical(ls(e), "x")
  expect_null(rs$sending)
})

test_that("console_send() attaches @objects by name and @files as a block", {
  local_project(files = list("a.R" = "fit = lm(mpg ~ wt, data = mtcars)"))
  local_console_blocks()
  fake = gptr_fake_provider(list("ok"))
  e = new.env(parent = globalenv())
  e$my_cars = mtcars
  rs = repl_state(NULL, e)
  rs$model = fake
  console_send(rs, "explain @a.R using @my_cars")
  blocks = last_user_blocks(fake_requests(fake)[[1L]])
  expect_match(blocks[["user_files"]], "<file path=\"a.R\">", fixed = TRUE)
  expect_true("attached" %in% names(blocks))
  expect_match(blocks[["attached"]], "my_cars", fixed = TRUE)
  expect_identical(unname(blocks[["text"]]), "explain @a.R using @my_cars")
})

test_that("console_send() keeps the session of a failed call and reports the error", {
  local_project()
  fake = gptr_fake_provider(list(list(error = "bad key", status = 401L, after = 0L)))
  rs = repl_state(NULL, new.env())
  rs$model = fake
  res = console_send(rs, "hello")
  expect_identical(res$status, "error")
  expect_s3_class(res$error, "gptr_error")
  expect_s3_class(rs$session, "gptr_session")
  expect_identical(rs$session$status, "error")
})

test_that("!code runs through the eval.r service (the evaluator kind, IC-69)", {
  local_project()
  old = the$services
  withr::defer({
    the$services = old
  })
  seen = new.env(parent = emptyenv())
  ext_service_set("eval.r", function(code, envir, ...) {
    seen$code = code
    seen$args = names(list(...))
    eval_r(code, envir, ...)
  }, provided_by = "test")
  rs = repl_state(NULL, new.env())
  utils::capture.output(repl_passthrough(rs, "!1 + 1"))
  expect_identical(seen$code, "1 + 1")
  expect_setequal(seen$args, c("plots", "tee", "guard"))
})

test_that("the console call's arguments reach the first prompt, also on a piped session", {
  local_project()
  s = peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  call = list(ids = list(mode = "auto"), args = list(), context = list())
  rs = repl_state(s, new.env(), call = call)
  cl = console_call(rs, "go")
  console_call_release(rs)
  expect_identical(cl$mode, "auto")
  expect_identical(cl[[2L]], quote(.gptr_session))
  cl2 = console_call(rs, "again")
  console_call_release(rs)
  expect_null(cl2$mode)
})

test_that("console_send() passes max_turns from gptr.max_turns_console", {
  local_project()
  fake = gptr_fake_provider(list("ok"))
  rs = repl_state(NULL, new.env())
  rs$model = fake
  local_gptr_options(max_turns_console = 7L)
  got = new.env(parent = emptyenv())
  off = gptr_register(gptr_context_block("probe_opts", function(ctx, budget) {
    got$max_turns = ctx$input$opts$max_turns
    NULL
  }, placement = "both"))
  withr::defer(off())
  console_send(rs, "hello")
  expect_identical(got$max_turns, 7L)
})

# ---------------------------------------------------------------- Task 7: console sessions

# A console test: a temporary project, no history, no document recording questions
local_console_test = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(history = FALSE, record = "off", .env = .env)
}

test_that("builtin:console registers its frontend, route, commands, blocks and service", {
  routes = registry_all("route")
  console = Filter(function(r) identical(r$name, "console"), routes)
  expect_length(console, 1L)
  expect_identical(console[[1L]]$order, 30)
  expect_false(is.null(registry_get("frontend", "console")))
  expect_false(is.null(registry_get("command", "mode")))
  expect_true(all(c("user_ran", "user_files") %in% registry_names("context_block")))
  expect_true(ext_service_has("console.interrupt_policy"))
})

test_that("the console route never matches inside a run (model code cannot open a REPL)", {
  call = list(prompt = NULL, args = list(stdin = TRUE))
  expect_true(console_route_match(call))
  local_mocked_bindings(run_current = function() structure(new.env(), class = "gptr_run"))
  expect_false(console_route_match(call))
})

test_that("the stdin UI answers selections and approvals from the reader", {
  rd = stdin_reader(c("2", "maybe", "y", "n use base R"))
  ui = ui_console_spec(rd$read, "console_stdin")
  pick = NULL
  a1 = NULL
  a2 = NULL
  err = utils::capture.output({
    pick = ui$select("Which?", c("Table", "Plot"))
    a1 = ui$permission(list(tool = "r", input = list(code = "y = 2"), risk = list(level = 1L)))
    a2 = ui$permission(list(tool = "r", input = list(code = "unlink('x')"),
                            risk = list(level = 3L)))
  }, type = "message")
  expect_identical(pick, 2L)
  expect_identical(a1$decision, "allow")
  expect_identical(a2, list(decision = "deny", remember = NULL, feedback = "use base R"))
  expect_true(any(grepl("Answer [y]es", err, fixed = TRUE)))
  expect_s3_class(ui, "gptr_ui")
})

test_that("the stdin UI never echoes a secret answer", {
  rd = stdin_reader(c("FAKE-TOKEN-123", "plain"), echo = TRUE)
  ui = ui_console_spec(rd$read, "console_stdin")
  got = NULL
  out = utils::capture.output({
    got = c(ui$input("Token", secret = TRUE), ui$input("Name"))
  })
  expect_identical(got, c("FAKE-TOKEN-123", "plain"))
  expect_identical(out, c("Token: ", "Name: plain"))
})

test_that("a scripted .stdin console session (acceptance 2)", {
  local_console_test()
  local_scripted_ui()
  fake = gptr_fake_provider(list("first answer", "second answer"))
  e = new.env(parent = globalenv())
  e$x = matrix(1:6, 2)
  local_console_stdin(c("hello there", "!dim(x)", "!!x", "/mode auto", '"""', "line one",
                        "line two", '"""', "/exit"))
  n0 = nrow(showConnections())
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter(.stdin = TRUE, model = fake, envir = e))
  })
  expect_false(res$visible)
  s = res$value
  expect_s3_class(s, "gptr_session")
  expect_identical(s$turns, 2L)
  expect_identical(s$mode, "auto")
  expect_identical(nrow(showConnections()), n0)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(reqs[[1L]]$last_user, "hello there")
  expect_identical(reqs[[2L]]$last_user, "line one\nline two")
  blocks = last_user_blocks(reqs[[2L]])
  expect_match(blocks[["user_ran"]], "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  expect_false(grepl("> x\n", blocks[["user_ran"]], fixed = TRUE))
  expect_true("mode" %in% names(blocks))
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% "", "")
  expect_true("gptr.mode_change" %in% types)
  expect_true("peter> hello there" %in% out)
  expect_true("first answer" %in% out)
  expect_true("second answer" %in% out)
  expect_true("[1] 2 3" %in% out)
})

test_that("the end of piped input leaves the REPL like /exit", {
  local_console_test()
  local_scripted_ui()
  local_console_stdin("only line")
  res = NULL
  utils::capture.output({
    res = peter(.stdin = TRUE, model = gptr_fake_provider(list("ok")), envir = new.env())
  })
  expect_s3_class(res, "gptr_session")
  expect_identical(res$text, "ok")
})

test_that("in IRkernel peter() without a prompt starts the console on gptr_readline() (acc. 7)", {
  local_console_test()
  withr::local_options(gptr.interactive = NULL, jupyter.in_kernel = TRUE)
  box = new.env(parent = emptyenv())
  box$answers = c("/status", "/exit")
  local_mocked_bindings(
    gptr_is_interactive = function() FALSE, is_testthat = function() FALSE,
    check_running = function() FALSE, is_knitting = function() FALSE,
    gptr_readline = function(prompt = "") {
      a = box$answers[[1L]]
      box$answers = box$answers[-1L]
      a
    })
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter(envir = new.env()))
  })
  expect_false(res$visible)
  expect_null(res$value)
  expect_match(out[[1L]], "^gptr .* \\| model .* \\| mode .* \\| ")
  expect_true(any(grepl("session   (none yet", out, fixed = TRUE)))
  expect_length(box$answers, 0L)
})

test_that("Ctrl-C at the prompt prints a hint; twice in a row leaves", {
  local_console_test()
  ctrl_c = function(prompt = "") {
    signalCondition(structure(class = c("interrupt", "condition"),
                              list(message = "", call = NULL)))
    ""
  }
  local_mocked_bindings(gptr_readline = ctrl_c)
  res = "not set"
  err = utils::capture.output(invisible(utils::capture.output({
    res = console_run(NULL, new.env())
  })), type = "message")
  expect_null(res)
  expect_length(grep("again to leave gptr", err, fixed = TRUE), 1L)
})

test_that("a line at the readline limit is reported at once and not sent", {
  local_console_test()
  box = new.env(parent = emptyenv())
  box$answers = c(strrep("a", readline_limit()), "/exit")
  local_mocked_bindings(gptr_readline = function(prompt = "") {
    a = box$answers[[1L]]
    box$answers = box$answers[-1L]
    a
  })
  res = "not set"
  err = utils::capture.output(invisible(utils::capture.output({
    res = console_run(NULL, new.env())
  })), type = "message")
  expect_null(res)
  expect_true(any(grepl("^Warning: That line was [0-9]+ bytes long", err)))
})

test_that("background sessions that wait for approval are announced once (IC-57)", {
  rows = data.frame(id = c("s1", "s2"), kind = "session", name = c("a", "b"),
                    pid = NA_integer_, status = c("waiting", "running"),
                    stringsAsFactors = FALSE)
  local_mocked_bindings(job_list = function(kind = NULL) rows)
  rs = repl_state(NULL, new.env())
  err = utils::capture.output({
    repl_waiting_notice(rs)
    repl_waiting_notice(rs)
  }, type = "message")
  expect_identical(err, paste("[gptr] 1 background session waits for approval;",
                              "the next prompt or gptr_wait() asks."))
  expect_identical(rs$waiting, 1L)
})

test_that("an error is printed on stderr and the REPL goes on", {
  local_console_test()
  local_scripted_ui()
  fake = gptr_fake_provider(list(list(error = "bad key", status = 401L, after = 0L),
                                 "recovered"))
  local_console_stdin(c("first", "second", "/exit"))
  res = NULL
  err = utils::capture.output(invisible(utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, envir = new.env())
  })), type = "message")
  expect_true(any(startsWith(err, "Error: ")))
  expect_identical(res$text, "recovered")
})

test_that("approvals of a .stdin session are answered from the same stdin", {
  local_console_test()
  withr::local_options(gptr.interactive = NULL, gptr.ui = NULL)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "y = 2")), "made y"))
  e = new.env(parent = globalenv())
  local_console_stdin(c("make y", "y", "/exit"))
  res = NULL
  out = NULL
  err = utils::capture.output({
    out = utils::capture.output({
      res = peter(.stdin = TRUE, model = fake, envir = e, mode = manual)
    })
  }, type = "message")
  expect_identical(e$y, 2)
  expect_identical(res$text, "made y")
  expect_true(any(grepl("allow? [y]es", out, fixed = TRUE)))
  expect_true("  r  y = 2" %in% err)
  expect_null(getOption("gptr.ui"))
  expect_null(getOption("gptr.interactive"))
})

test_that("the frontend comes from .opts$frontend or the setting frontend (IC-69)", {
  local_console_test()
  off = gptr_register(gptr_spec("frontend", "probe", run = function(session, ...) "probe ran"))
  withr::defer(off())
  res = withVisible(peter(.stdin = TRUE, .opts = list(frontend = "probe")))
  expect_identical(res$value, "probe ran")
  expect_false(res$visible)
  local_gptr_options(frontend = "probe")
  expect_identical(peter(.stdin = TRUE), "probe ran")
})

test_that("the console echoes an interpolated prompt at verbosity 2", {
  local_console_test()
  local_scripted_ui()
  local_gptr_options(verbose = 2L)
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  e = new.env(parent = globalenv())
  e$cl = 4L
  local_console_stdin(c("describe cluster {cl}", "/exit"))
  out = utils::capture.output(peter(.stdin = TRUE, model = gptr_fake_provider(list("ok")),
                                   envir = e))
  expect_true("> describe cluster 4" %in% out)
})
