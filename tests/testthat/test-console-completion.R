# tests/testthat/test-console-completion.R -- native Unix readline prefix scope and restoration;
# completion only after @, !, !!, / and peter$ (P28 Task 22, IC-81, D-244).

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
    seen$complete = rs$reader$complete
    TRUE
  })
  expect_null(repl_main(completion_repl_state()))
  expect_identical(seen$breaks, " ,;!")
  expect_identical(getOption("rl_word_breaks"), " ,;")
  # and its reader completes (IC-81)
  expect_true(seen$complete)
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
    # the reader completes, its completer calling the caller's for ! lines (IC-81)
    expect_true(rs$reader$complete)
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
      # no trigger-only completion either (IC-81; IDE consoles: Task 23)
      expect_null(rs$reader$complete)
      FALSE
    })
    expect_null(repl_main(completion_repl_state(input)))
    expect_identical(getOption("rl_word_breaks"), original)
  })(case)
})

# ---- P28 Task 22: completion only after @, !, !!, / and peter$ (IC-81, D-244) ----------------

# A REPL that completes (its reader's `complete`) on an environment holding mtcars_copy,
# my_long_object_name and .hidden, in a working directory holding analysis_notes.R and
# data/a.csv; the commands mode, model, help and plug:run and the skill tidy-data are registered
local_completing_repl = function(.env = parent.frame()) {
  dir = withr::local_tempdir("gptr-complete-", .local_envir = .env)
  writeLines("x", file.path(dir, "analysis_notes.R"))
  dir.create(file.path(dir, "data"))
  writeLines("x", file.path(dir, "data", "a.csv"))
  withr::local_dir(dir, .local_envir = .env)
  env = list2env(list(mtcars_copy = mtcars, my_long_object_name = 1, .hidden = 2),
                 parent = emptyenv())
  testthat::local_mocked_bindings(registry_names = function(kind, session = NULL) {
    switch(kind, command = c("mode", "model", "help", "plug:run"), skill = "tidy-data",
           character())
  }, .env = .env)
  rs = repl_state(NULL, env)
  rs$reader = console_reader()
  rs$reader$complete = TRUE
  rs
}

# What R's completion gives for `line` (the cursor at its end) with `completer` as the custom
# completer, as R calls it: Unix readline with readline's word as the token (`word`; it breaks
# at its break characters, ! among them), RStudio and Windows with utils' own token guess (`word`
# NULL). "<file>" ends the result where readline would go on to complete a file name.
host_complete = function(line, word = NULL, completer = console_completer(NULL)) {
  u = function(f) utils::getFromNamespace(f, "utils")
  old = utils::rc.options(custom.completer = completer)
  on.exit(utils::rc.options(old))
  u(".assignLinebuffer")(line)
  u(".assignEnd")(nchar(line))
  if (is.null(word)) u(".guessTokenFromLine")() else u(".assignToken")(word)
  u(".completeToken")()
  c(u(".retrieveCompletions")(), if (isTRUE(u(".getFileComp")())) "<file>")
}

test_that("completion comes only after @, !, !!, / and peter$, in full words (IC-81)", {
  .gptr_repl = local_completing_repl()
  cases = list(
    "summarise the da" = character(),
    "use @mtc" = "@mtcars_copy",
    "(@my_" = "@my_long_object_name",
    "see @an" = "@analysis_notes.R",
    "@da" = "@data/",
    "@data/" = "@data/a.csv",
    "@.hid" = "@.hidden",
    "plot @mtcars_copy$m" = "@mtcars_copy$mpg",
    "ask peter$rea" = "peter$read",
    "/mo" = c("/mode", "/model"),
    "  /skill:t" = "/skill:tidy-data",
    "/plug:" = "/plug:run",
    "please /mo" = character(),
    "mail a@b.com" = character(),
    "cost is $5" = character(),
    "use $name" = character(),
    "x$y" = character(),
    "wow! x" = character(),
    "use @zz" = character(),
    "@nothing$x" = character()
  )
  got = lapply(names(cases), console_complete)
  names(got) = names(cases)
  expect_identical(got, cases)
  # objects first, then files and directories; dot names only when typed
  expect_identical(console_complete("@"),
                   c("@mtcars_copy", "@my_long_object_name", "@analysis_notes.R", "@data/"))
  # the word before the cursor
  expect_identical(console_complete("use @mtc and more", 8L), "@mtcars_copy")
  # R's own completion of the code after ! and !!
  summ = console_complete("!summ")
  expect_true("summary" %in% summ)
  expect_true(all(startsWith(summ, "summ")))
  expect_true("mtcars" %in% console_complete("!!summary(mtc"))
  # only in a REPL whose reader completes
  .gptr_repl$reader$complete = NULL
  expect_identical(console_complete("use @mtc"), character())
})

test_that("R's completion through the adapter gives the table's words as its token's (IC-81)", {
  .gptr_repl = local_completing_repl()
  # RStudio and Windows: utils guesses the token (`mo` after /, `a` after /)
  expect_identical(host_complete("summarise the da"), character())
  expect_identical(host_complete("use @mtc"), "@mtcars_copy")
  expect_identical(host_complete("/mo"), c("mode", "model"))
  expect_identical(host_complete("@data/a"), "a.csv")
  expect_identical(host_complete("ask peter$rea"), "peter$read")
  expect_true("summary" %in% host_complete("!summ"))
  # Unix readline: the token is readline's word
  expect_identical(host_complete("/mo", "/mo"), c("/mode", "/model"))
  expect_identical(host_complete("@data/a", "@data/a"), "@data/a.csv")
  expect_identical(host_complete("summarise the da", "da"), character())
  expect_true("summary" %in% host_complete("!summ", "summ"))
})

test_that("the adapter sets fileName first, so a failure completes nothing (IC-81)", {
  .gptr_repl = local_completing_repl()
  ce = utils::getFromNamespace(".CompletionEnv", "utils")
  # without fileName R's readline aborts the readline() call
  if (exists("fileName", envir = ce, inherits = FALSE)) rm("fileName", envir = ce)
  local_mocked_bindings(repl_eval_env = function(rs) stop("synthetic failure"))
  expect_identical(host_complete("use @mtc", "@mtc"), character())
  expect_false(ce$fileName)
})

test_that("a caller-owned completer completes ! lines; the triggers stay gptr's (IC-81)", {
  .gptr_repl = local_completing_repl()
  caller = function(env) env$comps = paste0(env$token, "_caller")
  f = console_completer(caller)
  expect_identical(host_complete("!summ", "summ", f), "summ_caller")
  # readline keeps ! in its word for a caller-owned completer (no bang separator): the word is
  # completed as a whole
  expect_identical(host_complete("!summ", "!summ", f), "!summ_caller")
  expect_identical(host_complete("use @mtc", "@mtc", f), "@mtcars_copy")
  expect_identical(host_complete("summarise the da", "da", f), character())
  # the caller's completer is the custom one again after each call
  expect_identical(utils::rc.getOption("custom.completer"), NULL)
  # outside a prompt read (the composer during a run) R's completion calls the caller's
  old = utils::rc.options(custom.completer = caller)
  withr::defer(utils::rc.options(old))
  expect_identical(console_complete("!summ"), "summ_caller")
})

test_that("the reader completes around its prompt reads, not at + and not unflagged (IC-81)", {
  seen = list()
  local_mocked_bindings(gptr_readline = function(prompt = "", read = readline) {
    seen[[prompt]] <<- utils::rc.getOption("custom.completer")
    "x"
  })
  caller = function(env) env$comps = "caller"
  old = utils::rc.options(custom.completer = caller)
  withr::defer(utils::rc.options(old))
  rd = console_reader()
  rd$read("peter> ")
  expect_identical(seen[["peter> "]], caller)
  rd$complete = TRUE
  for (p in c("peter> ", "... ", "+ ")) rd$read(p)
  expect_true(is.function(seen[["peter> "]]))
  expect_false(identical(seen[["peter> "]], caller))
  expect_false(identical(seen[["... "]], caller))
  # `+ ` continues !code, where R's own completion (here the caller's) applies
  expect_identical(seen[["+ "]], caller)
  expect_identical(utils::rc.getOption("custom.completer"), caller)
  # the installed completer is gptr's, calling the caller's for ! lines
  .gptr_repl = local_completing_repl()
  expect_identical(host_complete("!summ", "summ", seen[["peter> "]]), "caller")
  expect_identical(host_complete("use @mtc", "@mtc", seen[["peter> "]]), "@mtcars_copy")
})

test_that("a terminal: Tab completes after @, / and ! and never natural language (IC-81)", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L)",
    "fake = gptr_fake_provider(function(req) paste0('GOT[', req$last_user, ']'))",
    "env = new.env()",
    "env$mtcars_copy = mtcars",
    "invisible(peter(model = fake, envir = env))"
  ), term = "xterm")
  expect_true(pty$wait("peter> ", timeout = 120))
  # natural language: R's completion would make `da` `dat` (data, date, ...)
  pty$send("summarise the da\t")
  Sys.sleep(0.5)
  pty$send("\r")
  expect_true(pty$wait("GOT[summarise the da]"))
  expect_true(pty$wait("peter> "))
  pty$send("use @mtc\t")
  Sys.sleep(0.5)
  pty$send("\r")
  expect_true(pty$wait("GOT[use @mtcars_copy]"))
  expect_true(pty$wait("peter> "))
  # a second Tab lists the commands, never R's rep or readline
  pty$send("/re\t")
  Sys.sleep(0.5)
  pty$send("\t")
  Sys.sleep(0.5)
  listed = pty$pending()
  expect_match(listed, "/redo +/resume +/retry .*/rewind")
  expect_no_match(listed, "/rep", fixed = TRUE)
  # /mo completes /mode, a command
  pty$send("\025/mo\t")
  Sys.sleep(0.5)
  pty$send("l\r")
  expect_true(pty$wait("Model: fake"))
  expect_true(pty$wait("peter> "))
  # ! lines get R's own completion
  pty$send("!summ\t")
  Sys.sleep(0.5)
  pty$send("(c(2, 4))\r")
  expect_true(pty$wait("1st Qu."))
  expect_true(pty$wait("peter> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD DONE"))
})
