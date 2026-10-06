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
