# tests/testthat/test-console-completion.R -- native Unix readline prefix scope and restoration.

local_completion_console = function(human = TRUE, cledit = TRUE, tty = TRUE, unix = TRUE,
                                    .env = parent.frame()) {
  force(human)
  force(cledit)
  force(tty)
  platform = .Platform
  platform$OS.type = if (unix) "unix" else "windows"
  testthat::local_mocked_bindings(
    .Platform = platform, capabilities = function(...) c(cledit = cledit), .package = "base",
    .env = .env
  )
  testthat::local_mocked_bindings(gptr_is_interactive = function() human,
                                  stdin_tty = function() tty, .env = .env)
  withr::local_envvar(R_COMPLETION = NA, .local_envir = .env)
}

completion_repl_state = function(stdin = FALSE) {
  rs = new.env(parent = emptyenv())
  rs$stdin = stdin
  rs$session = NULL
  rs$exit = FALSE
  rs$interrupts = 0L
  rs
}

local_completion_repl = function(setup, .env = parent.frame()) {
  testthat::local_mocked_bindings(
    console_reader = function(...) list(read = function(...) "/exit", waiting = character),
    repl_setup = setup, repl_close = function(...) invisible(NULL),
    repl_banner = function(...) invisible(NULL),
    repl_waiting_notice = function(...) invisible(NULL),
    repl_dispatch = function(rs, line) rs$exit = TRUE, .env = .env
  )
}

test_that("native readline gets one bang separator and caller separators return on exit", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " ,;")
  seen = new.env(parent = emptyenv())
  local_completion_repl(function(rs) {
    seen$breaks = getOption("rl_word_breaks")
    TRUE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(seen$breaks, " ,;!")
  expect_identical(getOption("rl_word_breaks"), " ,;")
})

test_that("R's readline in an IDE terminal tab gets the bang separator", {
  skip_on_os("windows")
  local_completion_console()
  # a terminal tab inherits the IDE's variables
  withr::local_envvar(RSTUDIO = "1", POSITRON = "1")
  withr::local_options(rl_word_breaks = " ,;")
  seen = new.env(parent = emptyenv())
  local_completion_repl(function(rs) {
    seen$breaks = getOption("rl_word_breaks")
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(seen$breaks, " ,;!")
  expect_identical(getOption("rl_word_breaks"), " ,;")
})

test_that("the REPL reads with a copy of base::readline() that RStudio's console completes in", {
  seen = new.env(parent = emptyenv())
  local_mocked_bindings(gptr_readline = function(prompt = "", read = readline) {
    seen$read = read
    "/exit"
  })
  expect_identical(console_reader()$read("peter> "), "/exit")
  # RStudio's .rs.readlineCompletions() completes nothing in a frame identical() to readline
  expect_false(identical(seen$read, base::readline))
  expect_identical(formals(seen$read), formals(base::readline))
  expect_identical(body(seen$read), body(base::readline))
  expect_identical(environment(seen$read), environment(base::readline))
})

test_that("an existing bang is preserved without duplication", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " !,;")
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " !,;")
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(getOption("rl_word_breaks"), " !,;")
})

test_that("setup cancellation restores the original default separators", {
  skip_on_os("windows")
  local_completion_console()
  defaults = " \t\n\"\\'`><=%;,|&{()}"
  withr::local_options(rl_word_breaks = defaults)
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), paste0(defaults, "!"))
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(getOption("rl_word_breaks"), defaults)
})

test_that("errors and interrupts restore the caller's completion option", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " ,")
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " ,!")
    stop("synthetic setup error")
  })
  expect_error(repl_main(completion_repl_state()), "synthetic setup error", fixed = TRUE)
  expect_identical(getOption("rl_word_breaks"), " ,")
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " ,!")
    stop(structure(list(message = "synthetic interrupt", call = NULL),
                   class = c("interrupt", "condition")))
  })
  got = tryCatch(repl_main(completion_repl_state()), interrupt = function(e) "caught")
  expect_identical(got, "caught")
  expect_identical(getOption("rl_word_breaks"), " ,")
})

test_that("nested console entry restores the outer scope before the original option", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " ,")
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " ,!")
    if (!isTRUE(rs$inner)) {
      inner = completion_repl_state()
      inner$inner = TRUE
      expect_null(repl_main(inner))
      expect_identical(getOption("rl_word_breaks"), " ,!")
    }
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(getOption("rl_word_breaks"), " ,")
})

test_that("a caller-owned full completer keeps its token policy and settings", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " ,")
  handler = function(env) env$comps = "caller completion"
  old = utils::rc.options(custom.completer = handler)
  withr::defer(utils::rc.options(old))
  settings = utils::rc.settings()
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " ,")
    expect_identical(utils::rc.getOption("custom.completer"), handler)
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(utils::rc.getOption("custom.completer"), handler)
  expect_identical(utils::rc.settings(), settings)
})

test_that("native prefix integration preserves argument and quote completers", {
  skip_on_os("windows")
  local_completion_console()
  withr::local_options(rl_word_breaks = " ,")
  argument = function(fun, text) character()
  quote = function(token) character()
  old = utils::rc.options(custom.completer = NULL, custom.argument.completer = argument,
                          custom.quote.completer = quote)
  withr::defer(utils::rc.options(old))
  local_completion_repl(function(rs) {
    expect_identical(getOption("rl_word_breaks"), " ,!")
    expect_identical(utils::rc.getOption("custom.argument.completer"), argument)
    expect_identical(utils::rc.getOption("custom.quote.completer"), quote)
    FALSE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(utils::rc.getOption("custom.argument.completer"), argument)
  expect_identical(utils::rc.getOption("custom.quote.completer"), quote)
})

test_that("unsupported input modes and IDE consoles keep completion options unchanged", {
  skip_on_cran()
  # an IDE console (RStudio, Positron, R.app, Jupyter) reads no tty
  cases = list(list(human = FALSE), list(cledit = FALSE), list(tty = FALSE),
               list(unix = FALSE), list(stdin = TRUE), list(disabled = TRUE))
  for (case in cases) (function(case) {
    original = getOption("rl_word_breaks")
    input = isTRUE(case$stdin)
    disabled = isTRUE(case$disabled)
    case$stdin = NULL
    case$disabled = NULL
    do.call(local_completion_console, c(case, list(.env = environment())))
    if (disabled) withr::local_envvar(R_COMPLETION = "FALSE")
    local_completion_repl(function(rs) {
      expect_identical(getOption("rl_word_breaks"), original)
      FALSE
    })
    expect_null(repl_main(completion_repl_state(input)))
    expect_identical(getOption("rl_word_breaks"), original)
  })(case)
})
