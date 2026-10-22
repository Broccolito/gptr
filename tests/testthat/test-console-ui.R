# tests/testthat/test-console-ui.R -- UI backends, the approval prompt and ui.get (P11)

ui_request = function(code, tier = "ask", rule = NULL) {
  risk = gptr_risk(code)
  list(tool = "r", input = list(code = code), summary = strsplit(code, "\n")[[1]], risk = risk,
       reason = paste0("mode manual, risk level ", risk$level), suggested_rule = rule,
       undo_note = NULL, session = "s0000000001", turn = 1L, nested = FALSE, tier = tier)
}

# Run `fun()` with gptr_readline() answering from `answers`; returns the result, the printed
# lines and what went to the console history (gptr.history decides; never the developer's)
console_try = function(fun, answers) {
  i = 0L
  kept = character()
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    i <<- i + 1L
    if (i > length(answers)) NA_character_ else answers[[i]]
  })
  testthat::local_mocked_bindings(timestamp = function(stamp, ...) kept <<- c(kept, stamp),
                                  .package = "utils")
  res = NULL
  shown = utils::capture.output({
    res = fun()
  })
  list(result = res, shown = shown, asked = i, kept = kept)
}

test_that("displays escape C0/C1 controls, bidi and zero-width characters (IC-53 item 8)", {
  expect_identical(ui_escape("a\u202eb\u200bc\td\u2066"), "a<U+202E>b<U+200B>c\td<U+2066>")
  expect_identical(ui_escape(c("\u001b[2J", "ok", NA)), c("<U+001B>[2J", "ok", NA))
  # literals mixing U+0080-U+00FF with higher code points are mis-encoded by R's parser in a
  # C locale, so each literal stays on one side
  expect_identical(ui_escape(c("\u0085x", "y\u061c")), c("<U+0085>x", "y<U+061C>"))
})

test_that("console select preserves title line feeds but escapes other controls and labels", {
  out = console_try(function() {
    ui_console_select("First line\nSecond line\033[2J", c("One\nInjected", "Two"))
  }, "2")
  expect_identical(out$result, 2L)
  text = paste(out$shown, collapse = "\n")
  expect_match(text, "? First line\n  Second line<U+001B>[2J", fixed = TRUE)
  expect_match(text, "1  One<U+000A>Injected", fixed = TRUE)
  expect_false(grepl("\033", text, fixed = TRUE))
})

test_that("a console select outside a run opens its own block in the margin (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  out = console_try(function() ui_console_select("Rewind to", c("a", "b")), "1")
  expect_identical(out$shown, c("", "  ? Rewind to", "    1  a", "    2  b", "    Choose a number"))
})

test_that("questions share one frame: ? and the title, numbered choices, a dim hint, the chevron", {
  # every row under the title is at column 4, under its text (visual review: the hint was at 2)
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = TRUE)
  local_utf8_glyphs()
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  prompts = character()
  read = function(prompt, ...) {
    prompts <<- c(prompts, prompt)
    ""
  }
  k = NULL
  out = utils::capture.output({
    k = ui_console_select("Which package?", c("dplyr", "base"), default = 2L, allow_other = TRUE,
                          read = read)
  })
  expect_identical(k, 2L)
  expect_identical(out, c("", "  ? Which package?", "    1  dplyr", "    2  base",
                          "    Choose a number, or type your own answer; Enter = base"))
  # ten choices or more align their numbers; several answers are numbers separated by commas
  out = utils::capture.output({
    k = ui_console_select("Pick", letters[1:10], multiple = TRUE, read = function(...) "1, 10")
  })
  expect_identical(k, c(1L, 10L))
  expect_identical(out[c(3L, 12L, 13L)], c("     1  a", "    10  j",
                                           "    Choose numbers separated by commas"))
  out = utils::capture.output({
    k = ui_console_input("Name?", default = "fit", read = read)
  })
  expect_identical(k, "fit")
  expect_identical(out, c("  ? Name?", "    Enter = fit"))
  # the answer is read after the person's chevron at column 0 (D-245 glyphs)
  expect_identical(prompts, rep("\u203a ", 2L))
  # ? blue, the title bold, the numbers bold, the hint dim
  withr::local_options(cli.num_colors = 256L)
  out = utils::capture.output(ui_console_select("Pick", c("a", "b"), read = function(...) "1"))
  expect_identical(out[2:5], c("  \033[38;5;67m?\033[39m \033[1mPick\033[22m",
                               "    \033[1m1\033[22m  a", "    \033[1m2\033[22m  b",
                               "    \033[38;5;244mChoose a number\033[39m"))
})

test_that("a long title, choice, detail or hint wraps under its own text (D-243)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  out = console_try(function() {
    ui_console_select("Should I convert cyl, gear and carb to factors before modelling?",
                      c("Yes, convert all three before fitting", "No"),
                      details = "The data has 32 rows and 11 columns.", allow_other = TRUE)
  }, "2")
  expect_identical(out$shown, c("", "  ? Should I convert cyl, gear and",
                                "    carb to factors before modelling?",
                                "    The data has 32 rows and 11", "    columns.",
                                "    1  Yes, convert all three before", "       fitting",
                                "    2  No", "    Choose a number, or type your own", "    answer"))
  out = console_try(function() {
    ui_console_input("What should the output file be called, with its extension?",
                     default = "results.csv")
  }, "")
  expect_identical(out$shown, c("  ? What should the output file be",
                                "    called, with its extension?", "    Enter = results.csv"))
  req = modifyList(ui_request("x = 1"), list(agent = "'Summarise the data by group' #12"))
  expect_identical(utils::tail(ui_permission_lines(req), 3L)[1:2],
                   c("  ? sub-agent 'Summarise the data by", "    group' #12: allow r?"))
})

test_that("the one-line prompt shows the first line, +N more lines and the flagged calls", {
  skip_on_cran()
  root = local_project()
  # R's parser refuses bidi controls inside string literals in UTF-8 locales, so the payload
  # sits in comments, where it parses everywhere
  req = ui_request(paste0("note = 1 # \u001b[2J\u202e\nwrite.csv(df, 'out.csv')\n",
                          "# \u001b[2J clear\nunlink('data', recursive = TRUE)"))
  lines = ui_permission_lines(req)
  expect_identical(lines[1L], "  | r  note = 1 # <U+001B>[2J<U+202E>  (+3 more lines)")
  expect_identical(lines[2:3], c("    flagged: [3 file_delete] unlink(\"data\", recursive = TRUE)",
                                 "             [2 file_write] write.csv(df, \"out.csv\")"))
  expect_false(any(grepl("[\u0001-\u0008\u000b-\u001f\u007f\u202e]", lines, perl = TRUE)))
  detail = ui_permission_detail(req)
  expect_true(any(grepl("<U+001B>[2J clear", detail, fixed = TRUE)))
  expect_false(any(grepl("\u001b", detail, fixed = TRUE)))
  expect_true(any(grepl("[3] file_delete", detail, fixed = TRUE)))
  w = list(tool = "write", input = list(path = "notes.md"), risk = list(level = 2L))
  expect_identical(ui_permission_lines(w), c("  | write  notes.md", "  ? Allow write?",
                                             "    y yes - n no - ? more"))
})

test_that("the prompt's first line fits the console, keeping +N more lines (D-187)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  req = ui_request(paste0("x = c(", strrep("1, ", 30L), "1)\ny = 2"))
  first = ui_permission_lines(req)[1L]
  expect_identical(first, "  | r  x = c(1, 1, 1...  (+1 more lines)")
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  expect_identical(nchar(ui_permission_lines(req)[1L]), 38L)
})

test_that("flagged calls fit one per line, highest level first, at most 5 (#33)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  root = local_project()
  code = c(sprintf("writeLines('%s', 'f%d.txt')", strrep("x", 30L), 1:7), "unlink('data')")
  lines = ui_permission_lines(ui_request(paste(code, collapse = "\n")))
  expect_length(lines, 9L)
  expect_true(all(nchar(lines) <= 40L))
  expect_identical(lines[2L], "    flagged: [3 file_delete] unlink(\"...")
  expect_identical(lines[3L], "             [2 file_write] writeLine...")
  expect_identical(lines[7L], "             (+3 more; ? shows all)")
  # dim, like the result rows
  withr::local_options(cli.num_colors = 256L)
  expect_true(all(startsWith(ui_permission_lines(ui_request(paste(code, collapse = "\n")))[2:7],
                             "\033[38;5;244m    ")))
})

test_that("a path tool's prompt shows the path relative to the project; no empty label (#33)", {
  skip_on_cran()
  root = local_project()
  # a tool's own risk record, as the dispatcher passes it: no label
  w = list(tool = "write", input = list(path = file.path(root, "R", "io.R")),
           risk = list(level = 2L, categories = "write", paths = "R/io.R"))
  expect_identical(ui_permission_lines(w)[1L], "  | write  R/io.R")
  detail = ui_permission_detail(w)
  expect_identical(detail[1:2], c("  gptr wants to use write (level 2)", "    R/io.R"))
  expect_match(ui_permission_detail(ui_request("x = 1"))[1L], "(level 1: local)", fixed = TRUE)
})

test_that("a and p are offered only with a suggested rule; a and p say why not (#33)", {
  skip_on_cran()
  root = local_project()
  e = new.env()
  e$x = 1
  req = ui_request("x = 2")
  req$risk = gptr_risk("x = 2", envir = e)
  expect_null(rule_suggest(list(name = "r", risk = req$risk)))
  out = console_try(function() ui_console_permission(req), c("?", "a", "p", "y"))
  expect_identical(out$result, list(decision = "allow", remember = NULL, feedback = NULL))
  expect_false(any(grepl("[a] always", out$shown, fixed = TRUE)))
  expect_identical(sum(out$shown == paste0("  a and p are not offered: no rule covers these ",
                                           "calls; answer y, n or ?.")), 2L)
  expect_null(ui_answer_norm(list(decision = "allow", remember = "session"), req)$remember)
})

test_that("the detail view shows at most 40 code rows at column 4, as the call block (D-187)", {
  skip_on_cran()
  root = local_project()
  code = sprintf("x%d = %d", 1:45, 1:45)
  detail = ui_permission_detail(ui_request(paste(code, collapse = "\n")))
  at = match("    x1 = 1", detail)
  expect_identical(detail[at + 0:40], paste0("    ", c(code[1:40], "# ... +5 more lines")))
  expect_false(any(grepl("\033|```", detail)))
  py = list(tool = "py", input = list(code = "a = 1"), risk = list(level = 2L))
  expect_identical(ui_permission_detail(py)[2L], "    a = 1")
})

test_that("the detail view's keys read as the question's; it skips a fence shown above (D-243)", {
  skip_on_cran()
  root = local_project()
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  keys = c("    y  yes", "    a  always in this session: r(fn:write.csv)",
           "    p  always in this project: r(fn:write.csv)",
           "    n  no (type n <what to do instead> to tell gptr)", "    Ctrl-C  abort the run")
  expect_identical(utils::tail(ui_permission_detail(req), 5L), keys)
  # the console printed this call's line with its code: ? leaves the fence out
  req$tool_call_id = "t1"
  old = console_state()$last_call
  withr::defer(assign("last_call", old, envir = console_state()))
  assign("last_call", c(req$session, "t1"), envir = console_state())
  out = console_try(function() ui_console_permission(req), c("?", "y"))
  expect_false("    write.csv(df, 'out.csv')" %in% out$shown)
  expect_true(all(keys %in% out$shown))
  # a code row the call block cut at the console's width is shown whole by ? (visual review)
  long = paste0("write.csv(df, '", strrep("d", 90L), ".csv')")
  wide = modifyList(req, list(input = list(code = long), summary = long))
  out = console_try(function() ui_console_permission(wide), c("?", "y"))
  expect_true(paste0("    ", long) %in% out$shown)
  # the key bold and its words dim; the RStudio dialog gets the code and no SGR
  withr::local_options(cli.num_colors = 256L)
  expect_identical(utils::tail(ui_permission_detail(req), 1L),
                   "    \033[1mCtrl-C\033[22m  \033[38;5;244mabort the run\033[39m")
  skip_if_not_installed("rstudioapi")
  shown = NULL
  local_mocked_bindings(ui_rstudio = function() TRUE)
  local_mocked_bindings(showQuestion = function(title, message, ...) {
    shown <<- message
    TRUE
  }, .package = "rstudioapi")
  expect_identical(ui_rstudio_spec()$permission(req)$decision, "allow")
  expect_match(shown, "\n    write.csv(df, 'out.csv')\n", fixed = TRUE)
  expect_false(grepl("\033", shown, fixed = TRUE))
})

test_that("the console prompt maps y, a, p, n, n <feedback>, ? and Ctrl-C (6.8.3)", {
  skip_on_cran()
  root = local_project()
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  out = console_try(function() ui_console_permission(req), "y")
  expect_identical(out$result, list(decision = "allow", remember = NULL, feedback = NULL))
  expect_match(out$shown[1L], "write.csv", fixed = TRUE)
  expect_identical(console_try(function() ui_console_permission(req), "a")$result$remember,
                   "session")
  expect_identical(console_try(function() ui_console_permission(req), "p")$result$remember,
                   "project")
  expect_identical(console_try(function() ui_console_permission(req), "n")$result$decision,
                   "deny")
  fb = console_try(function() ui_console_permission(req), "n use write_csv instead")$result
  expect_identical(fb$feedback, "use write_csv instead")
  out = console_try(function() ui_console_permission(req), c("?", "y"))
  expect_identical(out$result$decision, "allow")
  expect_true("    a  always in this session: r(fn:write.csv)" %in% out$shown)
  expect_identical(console_try(function() ui_console_permission(req), character())$result$decision,
                   "abort")
  crit = ui_request("q('no')", tier = "ask_human")
  out = console_try(function() ui_console_permission(crit), c("a", "y"))
  expect_identical(out$result$remember, NULL)
  expect_identical(out$asked, 2L)
})

test_that("the keys are a row under the question, a and p only with a rule (D-243)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = TRUE)
  local_utf8_glyphs()
  root = local_project()
  req = ui_request("x = 1", rule = "r(level<=1)")
  q = function(r) utils::tail(ui_permission_lines(r), 2L)
  keys = paste0("    y yes \u00b7 a always (session) \u00b7 p always (project) \u00b7 n no ",
                "\u00b7 ? more")
  expect_identical(q(req), c("  ? Allow r?", keys))
  expect_identical(q(ui_request("x = 1"))[[2L]], "    y yes \u00b7 n no \u00b7 ? more")
  # the keys row is 68 columns whatever the tool and whoever asks: it fits 80 columns
  long = modifyList(req, list(tool = "edit", agent = "'Summarise the data' #12"))
  expect_identical(q(long), c("  ? sub-agent 'Summarise the data' #12: allow edit?", keys))
  # narrower, it wraps under its first key, a key never apart from its words
  testthat::local_reproducible_output(width = 50, crayon = FALSE, unicode = TRUE)
  local_mocked_bindings(console_pad = function() "  ")
  expect_identical(utils::tail(ui_permission_lines(req), 3L),
                   c("  ? Allow r?", "    y yes \u00b7 a always (session) \u00b7",
                     "    p always (project) \u00b7 n no \u00b7 ? more"))
  # an MCP tool reads as the console's call line names it: server/tool, its arguments dim
  mcp = list(tool = "mcp__github__create_issue", input = list(title = "bug"),
             summary = "{\"title\":\"bug\"}", risk = list(level = 2L))
  lines = ui_permission_lines(mcp)
  expect_identical(lines[1:2], c("  \u258e github/create_issue  {\"title\":\"bug\"}",
                                 "  ? Allow github/create_issue?"))
  expect_match(ui_permission_detail(mcp)[1L], "wants to use github/create_issue", fixed = TRUE)
  # ? blue, the question bold, the keys bold, what they do dim; the call's strip red
  withr::local_options(cli.num_colors = 256L)
  expect_identical(ui_permission_lines(mcp)[1L],
                   console_call_line(list(name = mcp$tool, input = mcp$input), 78L))
  expect_identical(ui_permission_lines(ui_request("x = 1")),
                   c(paste0("  \u001b[38;5;167m\u258e\u001b[39m \u001b[1mr\u001b[22m  x = ",
                            "\u001b[38;5;67m1\u001b[39m"),
                     "  \033[38;5;67m?\033[39m \033[1mAllow r?\033[22m",
                     paste0("    \u001b[1my\u001b[22m\u001b[38;5;244m yes \u00b7\u001b[39m ",
                            "\u001b[1mn\u001b[22m\u001b[38;5;244m no \u00b7\u001b[39m ",
                            "\u001b[1m?\u001b[22m\u001b[38;5;244m more\u001b[39m")))
})

test_that("an approval asks under the call it gates; a call not shown is printed (D-243)", {
  skip_on_cran()
  local_project()
  sub = local_fake_provider(function(request) {
    if (length(request$last_results)) "child done" else fake_tool("r", code = "x = 1")
  }, name = "sub")
  fake = local_fake_provider(function(request) {
    if (length(request$last_results)) return("parent done")
    fake_tool("r", code = "res = peter('count', model = sub)")
  }, name = "main")
  prompts = character()
  local_gptr_options(mode = "manual", interactive = TRUE, verbose = 2L, quiet = FALSE,
                     ui = ui_console_spec(function(prompt, ...) {
                       prompts <<- c(prompts, prompt)
                       "y"
                     }))
  e = new.env()
  e$sub = sub
  out = utils::capture.output(peter("go", model = fake, envir = e))
  keys = "    y yes - a always (session) - p always (project) - n no - ? more"
  # the parent's call line, printed at its start, is not repeated: its ask follows it
  at = grep("res = peter(", out, fixed = TRUE)
  expect_identical(out[at], "  | r  res = peter('count', model = sub)")
  expect_identical(out[at + 2:3], c("  ? Allow r?", keys))
  # the sub-agent's call runs in the parent's r code, where no call line is shown: its ask
  # prints it, and the question names who asks
  at = match("  | r  x = 1", out)
  expect_identical(out[at + 1:2], c("  ? sub-agent 'count' #1: allow r?", keys))
  expect_identical(prompts, c(">> ", ">> "))
})

test_that("a remembered answer adds one dim line naming the rule and its scope (D-243)", {
  skip_on_cran()
  root = local_project()
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  out = console_try(function() ui_console_permission(req), "a")
  expect_identical(utils::tail(out$shown, 1L), "    allowed r(fn:write.csv) for this session")
  out = console_try(function() ui_console_permission(req), "project")
  expect_identical(utils::tail(out$shown, 1L), "    allowed r(fn:write.csv) for this project")
  expect_false(any(grepl("allowed", console_try(function() ui_console_permission(req), "y")$shown,
                         fixed = TRUE)))
  withr::local_options(cli.num_colors = 256L)
  out = console_try(function() ui_console_permission(req), "a")
  expect_identical(utils::tail(out$shown, 1L),
                   "\033[38;5;244m    allowed r(fn:write.csv) for this session\033[39m")
})

test_that("lines typed or pasted before the approval prompt never answer it (IC-75)", {
  root = local_project()
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  expect_identical(vapply(list(0.099, 0.1, NULL), answer_stale, NA), c(TRUE, FALSE, FALSE))
  rl = local_readline(c("h$config$codex", "", "y", "n"), secs = c(0.001, 0.001, 0.001, 1.5))
  res = NULL
  utils::capture.output({
    res = ui_console_permission(ui_request("zz = 1"))
  })
  expect_identical(res$decision, "deny")
  expect_identical(rl$i, 4L)
  # outside a run they go to the console history
  expect_identical(rl$kept, c("h$config$codex", "y"))
  # a secret is never kept
  rl = local_readline(c("sk-typed-ahead", "sk-answer"), secs = c(0.001, 1.5))
  expect_identical(ui_console_read("Key: ", secret = TRUE), "sk-answer")
  expect_identical(rl$kept, character())
})

test_that("a console command typed as a free-text answer waits for the next prompt (review)", {
  local_console_test()
  local_gptr_options(history = TRUE)
  rl = local_readline(character())
  answers = function(...) {
    x = c(...)
    function(...) {
      a = x[[1L]]
      x <<- x[-1L]
      a
    }
  }
  k = NULL
  utils::capture.output({
    k = ui_console_select("Which?", c("a", "b"), allow_other = TRUE,
                          read = answers("/exit", "/tmp/fit.rds"))
  })
  # outside a run it goes to the console history; a path names no command and is the answer
  expect_identical(attr(k, "other"), "/tmp/fit.rds")
  expect_identical(rl$kept, "/exit")
  utils::capture.output({
    k = ui_console_input("Name?", read = answers("/help mode", "fit"))
  })
  expect_identical(k, "fit")
  expect_identical(rl$kept, c("/exit", "/help mode"))
})

test_that("a terminal's question read that Ctrl-C or an end of input ends ends its line (review)", {
  local_console_test()
  local_readline(character())
  # a terminal leaves the person's row open: the next row starts on a line of its own
  local_live_console("T")
  out = written(function() expect_identical(ui_console_read("> "), NA_character_))
  expect_identical(out, "\n")
  local_live_console("D")
  expect_identical(written(function() ui_console_read("> ")), "\n")
  # an IDE console ends the input line itself
  local_live_console("L")
  expect_identical(written(function() ui_console_read("> ")), "")
})

test_that("during a run a line typed before the approval prompt is queued, then it asks again", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  enqueue = session_enqueue
  queued = list()
  local_mocked_bindings(session_enqueue = function(s, text, as = "steer", source = "api_user",
                                                   ...) {
    queued[[length(queued) + 1L]] <<- list(text = text, as = as, source = source)
    enqueue(s, text, as = as, source = source, ...)
  })
  rl = local_readline(c("go", "use base R", "y", "/exit"), secs = c(1, 0.01, 1, 1))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2"), "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_identical(e$zz, 2)
  expect_identical(queued, list(list(text = "use base R", as = "steer", source = "repl")))
  expect_identical(sum(rl$prompts == ">> "), 2L)
  expect_identical(rl$kept, character())
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  last = reqs[[2L]]$messages[[length(reqs[[2L]]$messages)]]
  expect_identical(msg_text(last),
                   "The user sent this message while you were working: use base R")
  expect_false(any(grepl("Not an answer", out, fixed = TRUE)))
  # the console echoed the line at the question, so its queue line does not repeat it: it says the
  # line was queued, not taken as the answer (visual review)
  expect_true(queue_line("steer", "not an answer") %in% out)
  expect_false(queue_line("steer", "use base R") %in% out)
})

test_that("during a run a !code or /command line typed before a question waits for the prompt", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  rl = local_readline(c("go", "!zz2 = 5", "y", "/exit"), secs = c(1, 0.01, 1, 1))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2"), "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  # as console_typed() routes it (IC-76, D-242): never a steer, run at the next prompt
  expect_identical(c(e$zz, e$zz2), c(2, 5))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_false(any(grepl("zz2", vapply(reqs[[2L]]$messages, msg_text, ""), fixed = TRUE)))
  expect_true(queue_line("follow-up", "not an answer") %in% out)
  expect_false(any(startsWith(out, queue_line("steer", ""))))
  expect_false(any(grepl("after this answer", out, fixed = TRUE)))
})

test_that("a block pasted at the approval prompt never answers it nor steers (IC-75)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(interactive = TRUE, history = TRUE)
  # fd 0 as one buffer: the rest of a paste whose first line answers the question waits there
  fd0 = new.env(parent = emptyenv())
  fd0$lines = character()
  fd0$answers = c("go", "y", "n", "/exit")
  fd0$prompts = character()
  reader = console_reader
  kept = character()
  local_mocked_bindings(timestamp = function(stamp, ...) kept <<- c(kept, stamp),
                        .package = "utils")
  local_mocked_bindings(
    repl_terminal = function(rs) TRUE,
    console_typed_lines = function(rd, ...) {
      x = fd0$lines
      fd0$lines = character()
      x
    },
    console_reader = function(...) {
      rd = reader(...)
      rd$waiting = function() console_typed_lines(rd)
      rd
    },
    gptr_readline = function(prompt = "", ...) {
      x = fd0$answers[[1L]]
      fd0$answers = fd0$answers[-1L]
      fd0$prompts = c(fd0$prompts, prompt)
      if (identical(x, "y")) fd0$lines = c("pasted line two", "pasted line three")
      the$readline_secs = 1
      x
    })
  withr::defer(assign("readline_secs", NULL, envir = the))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2", .text = "hmm"), "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_null(e$zz)
  expect_identical(sum(fd0$prompts == ">> "), 2L)
  expect_identical(sum(out == "  A pasted block is not an answer (kept in history)."), 1L)
  expect_identical(kept, '"""\ny\npasted line two\npasted line three\n"""')
  expect_false(any(grepl("Not an answer", out, fixed = TRUE)))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  texts = vapply(reqs[[2L]]$messages, msg_text, "")
  expect_false(any(grepl("pasted line", texts, fixed = TRUE)))
  expect_length(rs$reader$typed, 0L)
})

test_that("a sub-agent's prompt and detail view name it; ask_human says why (D-188)", {
  skip_on_cran()
  root = local_project()
  req = ui_request("x = 1")
  q = function(r) utils::tail(ui_permission_lines(r), 2L)[[1L]]
  keys = "    y yes - n no - ? more"
  expect_identical(ui_permission_lines(req), c("  | r  x = 1", "  ? Allow r?", keys))
  expect_identical(q(c(req, agent = "main")), "  ? Allow r?")
  expect_identical(ui_permission_lines(c(req, agent = "alpha")),
                   c("  | r  x = 1", "  ? sub-agent alpha: allow r?", keys))
  expect_identical(q(c(req, agent = "'Sum\033...'")), "  ? sub-agent 'Sum<U+001B>...': allow r?")
  expect_match(ui_permission_detail(c(req, agent = "alpha"))[1L],
               "^  sub-agent alpha wants to use r \\(level")
  expect_match(ui_permission_detail(req)[1L], "^  gptr wants to use r")
  crit = ui_request("q('no')", tier = "ask_human")
  expect_identical(utils::tail(ui_permission_lines(crit), 3L)[1L],
                   paste0("    asks in every mode: ", crit$reason))
  expect_false(any(grepl("every mode", ui_permission_lines(req), fixed = TRUE)))
})

test_that("nested calls with the same prompt are told apart by their number (#36)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_project()
  sub = local_fake_provider(function(request) {
    if (length(request$last_results)) "child done" else fake_tool("r", code = "x = 1")
  }, name = "sub")
  code = "for (id in 1:2) peter('You are annotating one cluster of the object', model = sub)"
  fake = local_fake_provider(function(request) {
    if (length(request$last_results)) "parent done" else fake_tool("r", code = code)
  }, name = "main")
  local_gptr_options(mode = "manual", interactive = TRUE, verbose = 1L, quiet = FALSE,
                     ui = ui_console_spec(function(prompt, ...) "y"))
  e = new.env()
  e$sub = sub
  s = NULL
  out = utils::capture.output({
    s = peter("annotate", model = fake, envir = e)
  })
  expect_identical(s$text, "parent done")
  who = "sub-agent 'You are annotating one cluster...' #"
  for (k in c("1", "2")) {
    expect_true(any(startsWith(out, paste0("  ? ", who, k, ": allow r?"))), info = k)
    expect_true(paste0("  # ", who, k, " (sub/sub-1) started") %in% out, info = k)
    expect_true(any(startsWith(out, paste0("  # ", who, k, " done"))), info = k)
  }
})

test_that("invalid answers are explained and kept; five end in a refusal the model is told", {
  skip_on_cran()
  root = local_project()
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  crit = ui_request("q('no')", tier = "ask_human")
  out = console_try(function() ui_console_permission(crit), c("a", "p", "y"))
  expect_identical(out$result$decision, "allow")
  expect_identical(sum(grepl("a and p are not offered: level-4 and control actions",
                             out$shown, fixed = TRUE)), 2L)
  expect_identical(out$kept, character())
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  out = console_try(function() ui_console_permission(req), rep("zz", 5L))
  expect_identical(out$result, list(decision = "deny", remember = NULL,
                                    feedback = "no valid answer was given at the approval prompt"))
  # the hint names the question, as it may have scrolled away (visual review), the prompt's own
  # letters and how to deny with feedback
  hint = "  Allow r? Type y, a, p or n (n <text> says what to do instead), or ?."
  expect_identical(c(sum(out$shown == "  Not an answer: 'zz' (kept in history)."),
                     sum(out$shown == hint)), c(5L, 5L))
  expect_identical(out$kept, rep("zz", 5L))
  expect_identical(utils::tail(out$shown, 1L), "  No valid answer after 5 tries; refused.")
  # asking for details is not an invalid answer
  out = console_try(function() ui_console_permission(req), c("?", "?", "zz", "?", "zz", "?", "y"))
  expect_identical(out$result$decision, "allow")
  out = console_try(function() ui_console_permission(crit), c("maybe \033", "", "n"))
  expect_true("  Not an answer: 'maybe <U+001B>' (kept in history)." %in% out$shown)
  # an empty answer only gets the hint, and is not kept
  expect_false(any(grepl("Not an answer: ''", out$shown, fixed = TRUE)))
  hint = "  Allow r? Type y or n (n <text> says what to do instead), or ?."
  expect_identical(sum(out$shown == hint), 2L)
  expect_identical(out$kept, "maybe \033")
  sub = console_try(function() ui_console_permission(modifyList(req, list(agent = "a"))),
                    c("zz", "y"))
  expect_match(paste(sub$shown, collapse = " "), "  sub-agent a: allow r? Type y, a, p or n (n",
               fixed = TRUE)
  # nothing is kept where there is no console history (a piped .stdin session)
  local_mocked_bindings(gptr_is_interactive = function() FALSE)
  out = console_try(function() ui_console_permission(req), c("zz", "y"))
  expect_true("  Not an answer: 'zz'." %in% out$shown)
  expect_identical(out$kept, character())
})

test_that("with gptr.history off nothing is kept and no notice says it was (D-243)", {
  root = local_project()
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  local_gptr_options(history = FALSE)
  out = console_try(function() ui_console_permission(ui_request("zz = 1")), c("zz", "y"))
  expect_true("  Not an answer: 'zz'." %in% out$shown)
  rd = list(waiting = function() "b")
  local_mocked_bindings(console_repl_find = function() list(reader = rd))
  out2 = console_try(function() ui_console_read("Q: "), "a")
  expect_identical(out2$shown, "  A pasted block is not an answer.")
  expect_identical(c(out$kept, out2$kept), character())
})

test_that("a long invalid answer's notice wraps inside the approval's width (P28 B, E, F)", {
  testthat::local_reproducible_output(width = 60)
  root = local_project()
  # in the console margin (D-186) the approval's rows end two columns before the edge
  local_mocked_bindings(gptr_is_interactive = function() TRUE, console_pad = function() "  ")
  a = "please use base R graphics for this plot"
  req = ui_request("zz = 1", rule = "r(level<=1)")
  out = console_try(function() ui_console_permission(req), c(a, "y"))
  rows = out$shown[seq(grep("Not an answer", out$shown, fixed = TRUE), length.out = 4L)]
  expect_identical(rows, c("  Not an answer: 'please use base R graphics for this",
                           "  plot' (kept in history).",
                           "  Allow r? Type y, a, p or n (n <text> says what to do",
                           "  instead), or ?."))
  expect_lte(max(nchar(out$shown)), 58L)
  expect_identical(out$kept, a)
})

test_that("the detail view shows the checkpoint.note service's undo note", {
  root = local_project()
  local_mocked_bindings(
    ext_service_has = function(name) identical(name, "checkpoint.note"),
    ext_service_get = function(name) function(call, run) "cannot be undone: pbmc 5.1 GB"
  )
  expect_true(any(grepl("cannot be undone: pbmc 5.1 GB",
                        ui_permission_detail(ui_request("pbmc = 1")), fixed = TRUE)))
})

test_that("ui.get resolves the snapshot of gptr.ui, else console or none (IC-43, IC-53)", {
  skip_on_cran()
  root = local_project()
  get_ui = ext_service_get("ui.get")
  expect_identical(get_ui()$name, "none")
  local_gptr_options(interactive = TRUE)
  expect_identical(get_ui()$name, "console")
  local_gptr_options(ui = "rstudio")
  expect_identical(get_ui()$name, "rstudio")
  local_gptr_options(ui = "no-such-ui", interactive = FALSE)
  expect_identical(get_ui()$name, "none")
  run = new.env(parent = emptyenv())
  run$id = "u00000001"
  run$session = "s0000000001"
  run$opts = list(safety = list(ui = "console", interactive = TRUE))
  local_mocked_bindings(run_current = function() run)
  expect_identical(get_ui()$name, "console")
  run$opts = list(safety = list(ui = ui_scripted_spec(ui_scripted_state(list()), "probe")))
  expect_identical(get_ui()$name, "probe")
  # P06's snapshot carries can_prompt; it wins over the live options (IC-53 item 2)
  local_gptr_options(interactive = TRUE)
  run$opts = list(safety = list(ui = NULL, interactive = NULL, can_prompt = FALSE))
  expect_identical(get_ui()$name, "none")
  run$opts = list(safety = list(ui = NULL, interactive = NULL, can_prompt = TRUE))
  local_gptr_options(interactive = FALSE)
  expect_identical(get_ui()$name, "console")
})

test_that("a failing or empty dialog is never an approval (10.2 row 22)", {
  skip_on_cran()
  broken = gptr_spec("ui", "broken", has_ui = function() TRUE,
                     select = function(title, choices, ...) stop("dialog crashed"),
                     permission = function(request) stop("dialog crashed"))
  ans = ui_wrap(broken)$permission(ui_request("unlink('x')"))
  expect_identical(ans$decision, "deny")
  odd = gptr_spec("ui", "odd", has_ui = function() TRUE, select = function(...) 1L,
                  permission = function(request) list(decision = "maybe"))
  expect_identical(ui_wrap(odd)$permission(ui_request("unlink('x')"))$decision, "deny")
  none = ui_wrap(ui_none_spec())
  expect_false(none$has_ui())
  expect_identical(none$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_true(none$questions(list(list(id = "a", question = "?")))$cancelled)
  expect_true(is.na(none$input("Name?")))
})

test_that("the rstudio UI has no UI outside RStudio and then denies", {
  rs = ui_rstudio_spec()
  skip_if(requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable(),
          "running inside RStudio")
  expect_false(rs$has_ui())
  expect_identical(rs$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_true(is.na(rs$select("t", c("a", "b"))))
})

test_that("the scripted UI answers in order, logs and fails closed when empty (12.2)", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("y", list(decision = "deny", feedback = "use a temp file"), 2L,
                              "fit", list(fmt = "Table")))
  ui = ext_service_get("ui.get")()
  expect_identical(ui$name, "scripted")
  expect_identical(ui$permission(ui_request("unlink('x')"))$decision, "allow")
  ans = ui$permission(ui_request("unlink('x')"))
  expect_identical(ans$feedback, "use a temp file")
  expect_identical(ui$select("Pick", c("a", "b")), 2L)
  expect_identical(ui$input("Name?"), "fit")
  expect_identical(ui$questions(list(list(id = "fmt", question = "Format?")))$answers,
                   list(fmt = "Table"))
  expect_identical(st$remaining(), 0L)
  expect_identical(ui$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_identical(st$log$method, c("permission", "permission", "select", "input", "questions",
                                    "permission"))
})

test_that("answering [a]lways adds a session rule covering exactly the flagged calls", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("a", "p", "a"))
  ui = ext_service_get("ui.get")()
  code = "write.csv(df, 'results/a.csv')\nsaveRDS(df, 'results/df.rds')"
  expect_identical(ui$permission(ui_request(code, rule = "r(fn:write.csv,saveRDS)"))$remember,
                   "session")
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
  w = list(tool = "write", input = list(path = "results/t.csv"), risk = list(level = 2L),
           suggested_rule = "write(results/**)", tier = "ask")
  expect_identical(ui$permission(w)$remember, "project")
  expect_true("write(results/**)" %in% perm_rules_effective()$allow)
  gptr_permissions(remove = "write(results/**)", scope = "project")
  ans = ui$permission(ui_request("rm(list = ls())", tier = "ask_human"))
  expect_identical(ans$decision, "allow")
  expect_null(ans$remember)
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
})

test_that("[a]lways in a run covers the same calls in the next run (05 P11 acceptance 5)", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("a"))
  code = "write.csv(mtcars, 'a.csv'); saveRDS(mtcars, 'b.rds')"
  fake = local_fake_provider(list(fake_tool("r", code = code), "Saved.",
                                  fake_tool("r", code = code), "Saved again."))
  peter("Save mtcars.", model = fake, envir = new.env(), mode = "manual")
  expect_true(file.exists(file.path(root, "a.csv")))
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
  unlink(file.path(root, c("a.csv", "b.rds")))
  peter("Save mtcars again.", model = fake, envir = new.env(), mode = "manual")
  expect_true(file.exists(file.path(root, "a.csv")))
  expect_identical(st$remaining(), 0L)
  expect_identical(sum(st$log$method == "permission"), 1L)
})
