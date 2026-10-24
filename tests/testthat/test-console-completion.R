# tests/testthat/test-console-completion.R -- native Unix readline prefix scope and restoration;
# completion only after @, !, !!, / and peter$ (P28 Task 22, IC-81, D-244), in RStudio and Windows
# consoles too (Task 23).

local_completion_console = function(human = TRUE, cledit = TRUE, tty = TRUE, unix = TRUE,
                                    gui = "X11", .env = parent.frame()) {
  force(human)
  force(cledit)
  force(tty)
  platform = .Platform
  platform$OS.type = if (unix) "unix" else "windows"
  platform$GUI = gui
  testthat::local_mocked_bindings(
    .Platform = platform, capabilities = function(...) c(cledit = cledit), .package = "base",
    .env = .env
  )
  testthat::local_mocked_bindings(gptr_is_interactive = function() human,
                                  stdin_tty = function() tty, .env = .env)
  withr::local_envvar(R_COMPLETION = NA, RSTUDIO = NA, POSITRON = NA, RADIAN_VERSION = NA,
                      .local_envir = .env)
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
  # IDE consoles get the scoped completer and keep their word breaks (IC-81): RStudio's, a
  # Windows console (Rgui, Rterm), with or without a caller-owned completer
  ide = list(list(tty = FALSE, gui = "RStudio"), list(unix = FALSE, tty = FALSE, gui = "Rgui"),
             list(unix = FALSE, gui = "RTerm"), list(unix = FALSE, gui = "RTerm", owned = TRUE))
  # out of reach (no completer): Positron (its ark has a tty stdin; Task 26's visual check), radian,
  # R.app; and the unsupported input modes: not interactive, R without readline in a terminal,
  # another unix front end with no tty, piped, R_COMPLETION=FALSE (also in RStudio)
  none = list(list(tty = FALSE, env = c(POSITRON = "1")), list(gui = "Positron"),
              list(unix = FALSE, gui = "RTerm", env = c(RADIAN_VERSION = "0.6.13")),
              list(tty = FALSE, gui = "AQUA"), list(human = FALSE), list(cledit = FALSE),
              list(tty = FALSE), list(stdin = TRUE), list(disabled = TRUE),
              list(tty = FALSE, gui = "RStudio", disabled = TRUE))
  for (case in c(ide, none)) (function(case) {
    original = getOption("rl_word_breaks")
    completes = any(vapply(ide, identical, NA, case))
    input = isTRUE(case$stdin)
    disabled = isTRUE(case$disabled)
    owned = isTRUE(case$owned)
    env = case$env
    case$stdin = case$disabled = case$owned = case$env = NULL
    do.call(local_completion_console, c(case, list(.env = environment())))
    if (disabled) withr::local_envvar(R_COMPLETION = "FALSE")
    if (length(env)) withr::local_envvar(env)
    if (owned) {
      handler = function(env) env$comps = "caller completion"
      old = utils::rc.options(custom.completer = handler)
      withr::defer(utils::rc.options(old))
    }
    local_completion_repl(function(rs) {
      expect_identical(getOption("rl_word_breaks"), original)
      if (completes) expect_true(rs$reader$complete) else expect_null(rs$reader$complete)
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

test_that("/skill: completes the project's skills before the first prompt (Task 30)", {
  local_project(trust = TRUE, files = list(".gptr/skills/tidy-up/SKILL.md" = c(
    "---", "name: tidy-up", "description: Tidy the data.", "---", "Tidy it.")))
  rs = repl_state(NULL, new.env())
  rs$reader = console_reader()
  rs$reader$complete = TRUE
  .gptr_repl = rs
  expect_identical(console_complete("/skill:ti"), "/skill:tidy-up")
})

test_that("/ completes the project's template commands before the first prompt (D-252)", {
  withr::defer(res_prune("prompts:", character()))
  local_project(list(".gptr/prompts/check.md" = "Check $1."), trust = TRUE)
  res_prune("prompts:", character())
  rs = repl_state(NULL, new.env())
  rs$reader = console_reader()
  rs$reader$complete = TRUE
  .gptr_repl = rs
  expect_identical(console_complete("/ch"), c("/check", "/checkpoints"))
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

test_that("Windows' console completion completes only the triggers (IC-81)", {
  .gptr_repl = local_completing_repl()
  old = utils::rc.options(custom.completer = console_completer(NULL))
  withr::defer(utils::rc.options(old))
  # what Rgui and Rterm call on Tab: the text the cursor ends inserted, several listed
  win = function(line) {
    utils::getFromNamespace(".win32consoleCompletion", "utils")(line, nchar(line),
                                                               check.repeat = FALSE)
  }
  expect_identical(win("summarise the da")[c("addition", "comps")],
                   list(addition = "", comps = ""))
  expect_identical(win("please /mo")$comps, "")
  expect_identical(win("cost is $5")$comps, "")
  expect_identical(win("use @mtc")$addition, "ars_copy")
  expect_identical(win("/mo")[c("addition", "comps")], list(addition = "de", comps = "mode model"))
  expect_identical(win("@data/a")$addition, ".csv")
  expect_identical(win("ask peter$rea")$addition, "d")
  expect_match(win("!summ")$comps, "(^| )summary( |$)")
  expect_identical(win("plot @mtcars_copy$m")$addition, "pg")
})

# RStudio's completion request as its get_completions handler makes it with a custom completer:
# `isConsole` bound in the handler's frame (FALSE when the editor asks), then
# .rs.getCustomRCompletions(): utils' token guess, .completeToken(), .retrieveCompletions()
rstudio_complete = function(line, isConsole) { # nolint: object_name_linter.
  force(isConsole)
  u = function(f) utils::getFromNamespace(f, "utils")
  u(".assignLinebuffer")(line)
  u(".assignEnd")(nchar(line))
  u(".guessTokenFromLine")()
  u(".completeToken")()
  u(".retrieveCompletions")()
}

test_that("RStudio's console completes only the triggers; its editor gets R's (IC-81)", {
  .gptr_repl = local_completing_repl()
  old = utils::rc.options(custom.completer = console_completer(NULL))
  withr::defer(utils::rc.options(old))
  # the console: only syntactic names, as RStudio inserts any other in backticks; none is the
  # token itself, as RStudio shows its own completions for an empty result
  # (.rs.getCustomRCompletions() fails on it) and none for the token alone
  expect_identical(rstudio_complete("summarise the da", TRUE), "da")
  expect_identical(rstudio_complete("hello /mo", TRUE), "mo")
  expect_identical(rstudio_complete("/mo", TRUE), c("mode", "model"))
  expect_identical(rstudio_complete("@data/a", TRUE), "a.csv")
  summ = rstudio_complete("!summ", TRUE)
  expect_true("summary" %in% summ)
  expect_true(all(make.names(summ) == summ))
  # `@mtcars_copy`, `peter$read`, `skill:tidy-data` and `mtcars$mpg` would be inserted in backticks
  expect_identical(rstudio_complete("use @mtc", TRUE), "@mtc")
  expect_identical(rstudio_complete("ask peter$rea", TRUE), "peter$rea")
  expect_identical(rstudio_complete("/skill:t", TRUE), "skill:t")
  expect_identical(rstudio_complete("!mtcars$m", TRUE), "mtcars$m")
  # the editor, which RStudio asks through the same request while peter> waits: R's completion
  expect_true("summary" %in% rstudio_complete("x = summ", FALSE))
  expect_true("data.frame" %in% rstudio_complete("summarise the da", FALSE))
  # with the caller's completer, the caller's
  caller = function(env) env$comps = paste0(env$token, "_caller")
  utils::rc.options(custom.completer = console_completer(caller))
  expect_identical(rstudio_complete("x = summ", FALSE), "summ_caller")
  expect_identical(rstudio_complete("summarise the da", TRUE), "da")
  # a terminal or Windows request (no isConsole on the stack) still gets nothing for none
  expect_identical(host_complete("summarise the da", completer = console_completer(caller)),
                   character())
})

test_that("RStudio's console has the triggers for the REPL's whole life, a run's too (IC-81)", {
  # RStudio asks while R is busy too, in the evaluation's frames: a line typed during a run is the
  # next prompt, and its popup or Tab would rewrite natural language there
  local_completion_console(tty = FALSE, gui = "RStudio")
  caller = function(env) env$comps = paste0(env$token, "_caller")
  old = utils::rc.options(custom.completer = caller)
  withr::defer(utils::rc.options(old))
  local_mocked_bindings(registry_names = function(kind, session = NULL) {
    if (kind == "command") c("mode", "model") else character()
  })
  seen = new.env(parent = emptyenv())
  local_completion_repl(function(rs) TRUE)
  local_mocked_bindings(repl_dispatch = function(rs, line) {
    seen$run = list(rstudio_complete("check the summ", TRUE), rstudio_complete("/mo", TRUE),
                    rstudio_complete("x = summ", FALSE))
    rs$exit = TRUE
  })
  expect_null(repl_main(completion_repl_state()))
  # outside a prompt read: the token alone for none, the triggers, the editor the caller's
  expect_identical(seen$run, list("summ", c("mode", "model"), "summ_caller"))
  expect_identical(utils::rc.getOption("custom.completer"), caller)
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
  # RStudio: the REPL's own completer is installed for its whole life, the caller's kept
  lifetime = console_completer(caller)
  utils::rc.options(custom.completer = lifetime)
  rd$caller = list(caller)
  for (p in c("peter> ", "+ ")) rd$read(p)
  expect_identical(seen[["+ "]], caller)
  expect_identical(host_complete("!summ", "summ", seen[["peter> "]]), "caller")
  expect_identical(utils::rc.getOption("custom.completer"), lifetime)
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
