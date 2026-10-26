# tests/testthat/test-console-commands.R -- the slash commands (plan P14, Task 6).
source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The console's command specs for this test unless builtin:console registered them already
local_console_commands = function(.env = parent.frame()) {
  for (spec in console_commands()) {
    if (!is.null(registry_get("command", spec$name))) next
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  invisible(NULL)
}

# Run `fun()` from a frame that binds the REPL state, as the REPL loop does
in_repl = function(rs, fun) {
  .gptr_repl = rs
  force(.gptr_repl)
  fun()
}

# Run a command line inside `rs`; returns list(out = stdout lines, err = stderr lines, res)
run_command = function(rs, text, send = NULL) {
  res = NULL
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output({
      res = in_repl(rs, function() console_command(text, rs$session, send))
    }, type = "message")
  })
  list(out = out, err = err, res = res)
}

idle_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

test_that("command_parse() splits names, sub-names and arguments", {
  expect_identical(command_parse("/mode auto"),
                   list(name = "mode", args = "auto", full = "mode", rest = "auto"))
  expect_identical(command_parse("/help"), list(name = "help", args = "", full = "help", rest = ""))
  expect_identical(command_parse("/skill:stats run it"),
                   list(name = "skill", args = "stats run it", full = "skill:stats",
                        rest = "run it"))
  expect_null(command_parse("not a command"))
})

test_that("a command named <plugin>:<cmd> wins over the /skill:<name> split (04 11.12)", {
  off = gptr_register(gptr_command("tidy:review", function(args, ctx) paste("reviewing", args)))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/tidy:review analysis.R")$out, "reviewing analysis.R")
})

test_that("every command of architecture 6.17 that P14 owns is a command spec", {
  nms = vapply(console_commands(), function(x) x$name, "")
  expect_true(all(c("help", "exit", "model", "mode", "plan", "tools", "env", "compact", "cost",
                    "context", "status", "clear", "resume", "fork", "doc", "skills", "skill",
                    "mcp", "retry", "permissions") %in% nms))
  expect_true(all(vapply(console_commands(), function(x) inherits(x, "gptr_command"), NA)))
})

test_that("unknown commands and failing handlers are reported; the input counts as handled", {
  local_console_commands()
  off = gptr_register(gptr_command("boom", function(args, ctx) stop("kaput\nsecond row")))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  r = run_command(rs, "/nope")
  expect_identical(r$res, "unknown")
  expect_true(any(grepl("Unknown command /nope", r$err, fixed = TRUE)))
  r = run_command(rs, "/boom")
  expect_identical(r$res, "error")
  # a message of two lines is two rows
  expect_identical(r$err, c("Error in /boom: kaput", "second row"))
  # in the margin the notice ends with a blank row, as a command's output does
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  for (cmd in c("/nope", "/boom")) {
    expect_identical(run_command(rs, cmd)$out, "", info = cmd)
  }
})

test_that("a command's text is printed escaped and a list(prompt =) is sent", {
  off = gptr_register(gptr_command("echo", function(args, ctx) paste("got", args, "\033")))
  withr::defer(off())
  off2 = gptr_register(gptr_command("ask", function(args, ctx) list(prompt = "the prompt")))
  withr::defer(off2())
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/echo {x}")$out, "got {x} <U+001B>")
  sent = new.env(parent = emptyenv())
  r = run_command(rs, "/ask", send = function(text) {
    sent$text = text
  })
  expect_identical(r$res, "prompt")
  expect_identical(sent$text, "the prompt")
})

test_that("commands pass the input event (source repl): recorded, handled or transformed", {
  local_console_commands()
  got = new.env(parent = emptyenv())
  got$texts = character()
  got$recorded = character()
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (!identical(event$source, "repl")) return(NULL)
    got$texts = c(got$texts, event$text)
    if (identical(event$text, "/swallow")) return(list(action = "handled", text = ""))
    if (identical(event$text, "/m")) return(list(action = "transform", text = "/mode plan"))
    if (identical(event$text, "/p")) return(list(action = "transform", text = "summarise x"))
    NULL
  }))
  withr::defer(off())
  # the channel P15's doc_on_console_command() subscribes to (data = list(text))
  off2 = gptr_register(gptr_hook("console:command", function(event, ctx) {
    got$recorded = c(got$recorded, event$data$text)
    NULL
  }))
  withr::defer(off2())
  rs = repl_state(NULL, new.env())
  run_command(rs, "/mode auto")
  expect_identical(got$texts, "/mode auto")
  expect_identical(run_command(rs, "/swallow")$res, "done")
  r = run_command(rs, "/m")
  expect_identical(r$out, "Mode: plan (used from the first prompt)")
  expect_identical(rs$mode, "plan")
  run_command(rs, "/model opus")
  expect_identical(rs$model, "opus")
  sent = new.env(parent = emptyenv())
  r = run_command(rs, "/p", send = function(text) {
    sent$text = text
  })
  expect_identical(r$res, "prompt")
  expect_identical(sent$text, "summarise x")
  # handled lines and lines sent as prompts are not recorded; a transformed command is recorded
  # as it ran
  expect_identical(got$recorded, c("/mode auto", "/mode plan", "/model opus"))
})

# /help's text in console class `cls` of front end `fe`, its reader completing or not
help_text = function(cls = "T", fe = "terminal", complete = TRUE) {
  local_mocked_bindings(console_class = function() cls, front_end = function() fe)
  rs = repl_state(NULL, new.env())
  rs$reader = list(complete = complete)
  run_command(rs, "/help")$out
}

test_that("/help lists the commands and the input syntax", {
  local_console_commands()
  local_gptr_options(interactive = TRUE)
  out = help_text()
  expect_true(any(grepl("^  /mode", out)))
  expect_true(any(grepl("!!code", out, fixed = TRUE)))
  # the keys of the composer, the two kinds of queued message and the trigger characters (D-242,
  # D-244)
  text = paste(trimws(out), collapse = " ")
  for (word in c("enter", "tab", "up", "steer", "follow-up", "@, !, !!, / or peter$")) {
    expect_true(grepl(word, text, fixed = TRUE), info = word)
  }
  # the descriptions of commands, input and keys start in one column (review of Tasks 22-27)
  rows = out[grepl("^  \\S", out)]
  expect_true(all(grepl("^  .{17}\\S", rows) & !grepl("^  .{16}\\S\\S", rows)))
  expect_identical(run_command(repl_state(NULL, new.env()), "/help mode")$out,
                   "/mode  show or switch the permission mode: /mode [plan|manual|edits|auto|yolo]")
})

test_that("/help's keys follow the console, as the banner does (review of Tasks 22-27)", {
  local_console_commands()
  local_gptr_options(interactive = TRUE)
  words = function(...) gsub("\\s+", " ", paste(help_text(...), collapse = " "))
  # RStudio: no composer (enter, up), its triggers ! and / (a $ or @ word there gets RStudio's own
  # completion, P28 Task 91), a typed line the next prompt
  rstudio = words("L", "rstudio")
  expect_false(any(grepl("^  (enter|up) ", help_text("L", "rstudio"))))
  for (w in c("@, !, !!", "In other consoles")) {
    expect_false(grepl(w, rstudio, fixed = TRUE), info = w)
  }
  for (w in c("tab after ! or /, complete the word", "esc pause the answer",
              "A line typed while peter works is the next prompt.")) {
    expect_true(grepl(w, rstudio, fixed = TRUE), info = w)
  }
  # Positron: no completion, and typed text waits as R code, as its banner says
  positron = words("L", "positron", complete = FALSE)
  expect_false(any(grepl("^  tab ", help_text("L", "positron", complete = FALSE))))
  expect_true(grepl("Text typed while peter works waits as R code; ctrl-c, then s, to steer.",
                    positron, fixed = TRUE))
  # TERM=dumb: each line is queued as type_ahead says
  expect_true(grepl("A line typed while peter works is queued as type_ahead says",
                    words("D", complete = FALSE), fixed = TRUE))
})

test_that("template commands exist before the first prompt, and a template saved later too", {
  local_console_commands()
  withr::defer(res_prune("prompts:", character()))
  p = local_project(list(".gptr/prompts/check.md" = "Check $1."), trust = TRUE)
  res_prune("prompts:", character())
  rs = repl_state(NULL, new.env())
  sent = new.env(parent = emptyenv())
  send = function(text) sent$text = text
  expect_identical(run_command(rs, "/check mtcars", send)$res, "prompt")
  expect_identical(sent$text, "Check mtcars.")
  res_prune("prompts:", character())
  listed = sub("^  /([^ ]+) .*", "\\1", cmd_help("", ctx_new(NULL)))
  expect_true(all(c("check", "review", "explain") %in% listed))
  writeLines("Later $1.", file.path(p, ".gptr", "prompts", "later.md"))
  expect_identical(run_command(rs, "/later z", send)$res, "prompt")
  expect_identical(sent$text, "Later z.")
})

test_that("a template command is the console's first input (end to end)", {
  skip_on_cran()
  local_console_test()
  withr::defer(res_prune("prompts:", character()))
  root = getOption("gptr.project_root")
  dir.create(file.path(root, ".gptr", "prompts"))
  writeLines("Check $1.", file.path(root, ".gptr", "prompts", "check.md"))
  gptr_trust(root, trust = TRUE)
  res_prune("prompts:", character())
  fake = gptr_fake_provider(list("checked"))
  local_console_stdin(c("/check mtcars", "/exit"))
  res = NULL
  err = utils::capture.output(invisible(utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, envir = new.env())
  })), type = "message")
  expect_false(any(grepl("Unknown command", err, fixed = TRUE)))
  expect_true(grepl("Check mtcars.", fake$log$requests[[1L]]$last_user, fixed = TRUE))
  expect_identical(res$text, "checked")
})

test_that("in the console margin command output wraps inside it; listings fit its width", {
  local_console_commands()
  local_project()
  peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  testthat::local_reproducible_output(width = 60)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  rs = repl_state(NULL, list2env(list(alpha = 1:10)))
  out = run_command(rs, "/help")$out
  expect_true(all(startsWith(out[nzchar(out)], "  ")))
  expect_true(all(nchar(out, type = "width") <= 60L))
  words = function(x) strsplit(trimws(paste(x, collapse = " ")), "[[:space:]]+")[[1L]]
  expect_identical(words(out), words(cmd_help("", list())))
  # a description wraps under its own column, so no row looks like another command
  cmds = out[seq(2L, match("  Input:", out) - 1L)]
  expect_true(all(grepl("^.{18} {3}\\S", cmds)))
  # never inside a usage or between a key and its word, and names bold (visual round 2)
  expect_false(any(grepl(" [sfcab]$|\\[[^]]*$", out)))
  bold = withr::with_options(list(cli.num_colors = 256L), run_command(rs, "/help")$out)
  names = bold[grepl("^ {4}\\S", cli::ansi_strip(bold))]
  expect_true(length(names) > 20L && all(startsWith(names, "    \033[1m")))
  expect_identical(run_command(rs, "/mode")$out, c("  Mode: manual", ""))
  expect_match(run_command(rs, "/env")$out[[1L]], "^  alpha: <integer>")
  # a listing is printed at the content width (60 - 4), not wrapped again
  listing = withr::with_options(list(width = 56L, cli.width = 56L),
                                utils::capture.output(print(gptr::gptr_sessions())))
  expect_identical(run_command(rs, "/resume")$out,
                   c(ifelse(nzchar(listing), paste0("  ", listing), ""), ""))
  expect_equal(c(getOption("width"), getOption("cli.width")), c(60, 60))
})

test_that("a command's output ends with a blank row before the next prompt (visual round 2)", {
  local_console_commands()
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  testthat::local_reproducible_output(width = 80)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  rs = repl_state(s, new.env())
  # as after a run's status line, also after one row, as /compact's follows its progress notice
  expect_identical(utils::tail(run_command(rs, "/context")$out, 2L) != "", c(TRUE, FALSE))
  expect_identical(utils::tail(run_command(rs, "/mode")$out, 2L) != "", c(TRUE, FALSE))
})

test_that("/exit, /quit and /q end the REPL", {
  local_console_commands()
  for (cmd in c("/exit", "/quit", "/q")) {
    rs = repl_state(NULL, new.env())
    expect_identical(run_command(rs, cmd)$out, character())
    expect_true(rs$exit)
  }
  # a background session still running is named, in the banner's words (visual round 3: R's
  # prompt got its end notice 20 s later, unannounced)
  s = peter("bg", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  running = c("running", "idle")
  local_mocked_bindings(job_list = function(kind = NULL) {
    data.frame(id = c(s$id, "s0000000002"), status = running)
  })
  rs = repl_state(s, new.env())
  expect_identical(run_command(rs, "/exit")$out,
                   "1 background session still runs - gptr_wait(gptr_last()) shows it")
  expect_true(rs$exit)
  # live (FIX-21): another session ran in the background, and gptr_last() was the console's
  running = c("idle", "running")
  expect_identical(run_command(rs, "/exit")$out,
                   "1 background session still runs - gptr_jobs() lists it")
  running = c("running", "running")
  expect_identical(run_command(rs, "/exit")$out,
                   "2 background sessions still run - gptr_jobs() lists them")
})

test_that("/model and /mode before the first prompt set the first prompt's arguments", {
  local_console_commands()
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/model haiku")$out,
                   "Model: haiku (used from the first prompt)")
  expect_identical(rs$model, "haiku")
  run_command(rs, "/plan")
  expect_identical(rs$mode, "plan")
  expect_identical(run_command(rs, "/mode")$out, "Mode: plan")
  expect_identical(run_command(rs, "/mode turbo")$out,
                   "Unknown mode 'turbo': use plan, manual, edits, auto or yolo.")
  local_gptr_options(quiet = FALSE)
  rm(list = intersect("message:mode_yolo", ls(the$once)), envir = the$once)
  withr::defer(rm(list = intersect("message:mode_yolo", ls(the$once)), envir = the$once))
  expect_message(run_command(rs, "/mode yolo"), "not a sandbox", class = "gptr_message_notice")
  expect_identical(rs$mode, "yolo")
})

test_that("/model checks a reference before the first prompt; provider names resolve", {
  local_console_commands()
  rs = repl_state(NULL, new.env())
  bad = run_command(rs, "/model codex-clu")
  expect_match(paste(bad$err, collapse = "\n"), "Unknown model reference 'codex-clu'",
               fixed = TRUE)
  expect_null(rs$model)
  expect_identical(run_command(rs, "/model claude-cli")$out,
                   "Model: claude-cli (used from the first prompt)")
  expect_identical(rs$model, "claude-cli")
  off = gptr_register(gptr_router("cheapest", route = function(request, ctx) "fake/fake-1"))
  withr::defer(off())
  expect_identical(run_command(rs, "/model cheapest")$out,
                   "Model: cheapest (used from the first prompt)")
  s = idle_session()
  rs2 = repl_state(s, new.env())
  expect_identical(run_command(rs2, "/model claude-code")$out,
                   "Model: claude-cli/default (from the next request)")
  expect_identical(run_command(rs2, "/model codex-cli")$out,
                   "Model: codex/default (from the next request)")
})

test_that("/model and /status name the model a CLI's default runs (#44)", {
  local_console_commands()
  off = gptr_register(pcli_fake_provider("claude"))
  withr::defer(off())
  local_mocked_bindings(pcli_default_model = function(api) paste0(api, "-id"))
  shown = "fakeclaude/default (cli-claude-id)"
  rs = repl_state(NULL, new.env())
  run_command(rs, "/model fakeclaude/default")
  expect_identical(run_command(rs, "/model")$out, paste0("Model: ", shown))
  expect_true(paste0("model     ", shown) %in% run_command(rs, "/status")$out)
  rs$session = idle_session()
  run_command(rs, "/model fakeclaude/default")
  expect_identical(run_command(rs, "/model")$out, paste0("Model: ", shown))
  expect_true(paste0("model     ", shown) %in% run_command(rs, "/status")$out)
  run_command(rs, "/model fakeclaude/claude-sonnet-5-5")
  expect_identical(run_command(rs, "/model")$out, "Model: fakeclaude/claude-sonnet-5-5")
  # another CLI adapter decides what its `default` runs
  off2 = gptr_register(gptr_provider("mycli", api = "mycli-api", type = "cli",
                                     models = list(list(id = "default"))))
  withr::defer(off2())
  run_command(rs, "/model mycli/default")
  expect_identical(run_command(rs, "/model")$out, "Model: mycli/default")
})

test_that("/mode on a session appends the mode change for the next turn", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  expect_identical(run_command(rs, "/mode auto")$out, "Mode: auto (from the next turn)")
  expect_identical(s$mode, "auto")
  expect_identical(run_command(rs, "/mode yolo")$out, "Mode: yolo (from the next turn)")
  expect_identical(s$mode, "yolo")
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% "", "")
  expect_true("gptr.mode_change" %in% types)
})

test_that("/status, /tools and /env describe the console", {
  local_console_commands()
  e = new.env()
  e$counts = matrix(1:4, 2)
  rs = repl_state(NULL, e)
  expect_match(run_command(rs, "/status")$out[[1L]], "session   (none yet", fixed = TRUE)
  expect_match(run_command(rs, "/tools")$out[[1L]], "Direct tools:", fixed = TRUE)
  env_out = run_command(rs, "/env count")$out
  expect_match(env_out, "^counts: ")
  s = idle_session()
  rs$session = s
  status = run_command(rs, "/status")$out
  expect_identical(status[[1L]], paste0("session   ", s$id, "  (idle, 0 turns)"))
  expect_true(any(grepl("^queue     0 steer, 1 follow-up$", status)))
  d = session_data(s)
  d$turns = 1L
  expect_identical(run_command(rs, "/status")$out[[1L]],
                   paste0("session   ", s$id, "  (idle, 1 turn)"))
})

test_that("/env and the banner in a fork list what the fork reads, a nearer binding shadowing", {
  local_console_commands()
  home = list2env(list(alpha = 1L, shared = "home"))
  ov = overlay_new(home, "s1")
  ov$beta = 2L
  rs = repl_state(NULL, ov)
  expect_identical(sub(":.*", "", run_command(rs, "/env")$out), c("alpha", "beta", "shared"))
  expect_match(run_command(rs, "/env alp")$out, "^alpha: <integer>")
  ov$shared = c("fork", "fork")
  expect_match(run_command(rs, "/env shared")$out, "^shared: <character> length 2")
  expect_identical(run_command(rs, "/env zz")$out, "(no objects)")
  expect_identical(utils::capture.output(repl_banner(rs))[[2L]], "objects: alpha, beta, shared")
})

test_that("in the margin a label keeps a value wider than the row on its row", {
  local_console_commands()
  s = idle_session()
  d = session_data(s)
  d$file = paste0("/var/folders/j_/", strrep("f", 32), "/T//RtmpAbCdEf/gptr/sessions/",
                  strrep("a", 25), ".jsonl")
  testthat::local_reproducible_output(width = 80)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  out = run_command(repl_state(s, new.env()), "/status")$out
  expect_true(paste0("  file      ", d$file) %in% out)
  # prose still wraps at the content width, and a value that fits a row goes to the next
  expect_identical(console_wrap(paste(rep("word", 24), collapse = " "), 40),
                   rep(paste(rep("word", 8), collapse = " "), 3))
  expect_identical(console_wrap(paste0("  ", strrep("l", 15), "  ", strrep("v", 30)), 40),
                   paste0("  ", c(strrep("l", 15), strrep("v", 30))))
})

test_that("/doc and /status name a gptr_doc() binding before the first prompt", {
  local_console_commands()
  root = local_project()
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = NULL
  expect_null(cmd_doc_site(NULL))
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/doc")$out, "No document is bound.")
  expect_true("document  (none)" %in% run_command(rs, "/status")$out)
  log = file.path(root, "log.R")
  gptr_doc(log)
  expect_identical(cmd_doc_site(NULL), list(path = log, format = "r"))
  expect_identical(run_command(rs, "/doc")$out, paste0("Document: ", log, " (r)"))
  status = run_command(rs, "/status")$out
  expect_match(status[[1L]], "session   (none yet", fixed = TRUE)
  expect_true(paste0("document  ", log) %in% status)
})

test_that("/doc and /status name the console transcript the project remembers", {
  local_console_commands()
  root = local_project()
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = NULL
  s = peter("hi", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  local_gptr_options(interactive = TRUE)
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/doc")$out, "No document is bound.")
  target = file.path(root, ".gptr", "transcripts", "t.R")
  doc_project_transcript(doc_rel(target))
  expect_identical(run_command(rs, "/doc")$out, paste0("Document: ", target, " (transcript)"))
  expect_true(paste0("document  ", target) %in% run_command(rs, "/status")$out)
  expect_true(paste0("document  ", target) %in%
                run_command(repl_state(s, new.env()), "/status")$out)
  # a console call records nothing where nobody can answer, and nothing after "Nowhere"
  local_gptr_options(interactive = FALSE)
  expect_identical(run_command(rs, "/doc")$out, "No document is bound.")
  local_gptr_options(interactive = TRUE)
  doc_project_transcript("off")
  expect_identical(run_command(rs, "/doc")$out, "No document is bound.")
  expect_true("document  (none)" %in% run_command(rs, "/status")$out)
})

test_that("/clear starts a new conversation and keeps model and mode", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  rs$notes = "> x"
  run_command(rs, "/clear")
  expect_null(rs$session)
  expect_identical(rs$model, s$model)
  expect_identical(rs$notes, character())
})

test_that("/clear keeps the thinking level of the session it ends", {
  local_console_commands()
  local_project()
  s = peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env(),
            .opts = list(thinking = "high"))
  expect_identical(session_data(s)$thinking, "high")
  rs = repl_state(s, new.env())
  run_command(rs, "/clear")
  expect_identical(rs$model, paste0(s$model, ":high"))
  expect_identical(model_canonical(rs$model)$thinking, "high")
})

test_that("/clear keeps the workspace the conversation used, a fork's too", {
  local_console_commands()
  local_project()
  home = new.env()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = home)
  rs = repl_state(s, new.env())
  home$z = 1
  run_command(rs, "/fork")
  assign("y", 5, envir = repl_eval_env(rs))
  run_command(rs, "/clear")
  expect_null(rs$session)
  expect_identical(get0("y", repl_eval_env(rs)), 5)
  expect_identical(get0("z", repl_eval_env(rs)), 1)
})

test_that("/cost, /context, /fork and /resume work on a session that ran", {
  local_console_commands()
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  rs = repl_state(s, new.env())
  cost = run_command(rs, "/cost")$out
  expect_match(cost[[length(cost)]], "^Total: 1 request, ")
  ctx_out = run_command(rs, "/context")$out
  expect_match(ctx_out[[1L]], "^Last request q[0-9a-f]+:$")
  # the ledger is gptr's estimate of what it sent, the context left from what the provider reported
  expect_match(ctx_out[[length(ctx_out) - 1L]], "^  total \\(est\\.\\) +[0-9,]+$")
  # the context left, as the run's status line says it (IC-77)
  left = console_context_left(session_data(s)$usage)
  expect_true(left > 90)
  expect_identical(ctx_out[[length(ctx_out)]],
                   sprintf("  %-14s %9s", "context left", paste0(left, "%")))
  # an unknown cache read is shown as unknown (IC-74)
  d = session_data(s)
  d$ledger$cached = NA
  expect_match(run_command(rs, "/context")$out[[2L]], "[0-9]  \\(cache unknown\\)$")
  run_command(rs, "/fork")
  expect_false(identical(rs$session$id, s$id))
  listing = run_command(rs, "/resume")$out
  expect_true(any(grepl(s$id, listing, fixed = TRUE)))
})

test_that("/cost lists the agents and one total that keeps the known cost (#38)", {
  local_console_commands()
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  rs = repl_state(s, new.env())
  row = function(id, agent, cost, write = 0) {
    usage_conform(data.frame(request_id = id, session = s$id, agent = agent, input = 1000,
                             output = 10, cache_read = 200, cache_write_5m = write,
                             cache_write_1h = write / 4, cost = cost, stringsAsFactors = FALSE))
  }
  d = session_data(s)
  # cache writes are input tokens too: a fresh claude-cli child sent 2 uncached ones (smoke)
  d$usage = rbind(row("q1", "main", 1.2), row("q2", "stats", NA, write = 800),
                  row("q3", "main", 0.3))
  expect_identical(run_command(rs, "/cost")$out, c(
    "  main   2 requests, 2.4k tokens in, $1.5000",
    "  stats  1 request, 2.2k tokens in, unknown cost",
    "Total: 3 requests, 4.6k tokens in, $1.5000 + 1 request of unknown cost"))
})

test_that("/context on a CLI route says the CLI keeps its own transcript (#38)", {
  skip_on_cran()
  local_console_commands()
  f = local_fake_cli("claude", "text")
  s = peter("Say hello", model = f$model, envir = new.env(), mode = "auto")
  local_cli_cleanup(s)
  out = run_command(repl_state(s, new.env()), "/context")$out
  expect_match(out[[length(out) - 1L]], "^  total ")
  expect_identical(out[[length(out)]], paste0("  The CLI keeps its own transcript; its last ",
                                              "turn reported 12 input tokens over all its ",
                                              "model calls."))
})

test_that("/compact reports its saving and /context names the compaction request (console-4)", {
  local_console_commands()
  local_project()
  long = strrep("mpg falls with wt. ", 300)
  s = peter("q1", model = gptr_fake_provider(list(long, long, "## Goal\nx\n## Progress\ny", "ok")),
            envir = new.env())
  s = peter(s, "q2")
  rs = repl_state(s, new.env())
  out = run_command(rs, "/compact")$out
  expect_match(out[[length(out)]], "^compacted - \\S+ to \\S+ tokens$")
  figure = function(out, pattern) {
    as.numeric(gsub("[^0-9]", "", grep(pattern, out, value = TRUE)))
  }
  ctx_out = run_command(rs, "/context")$out
  # the estimate is a ledger row, `~` its value in the column of the others (review of Tasks 22-27)
  expect_match(ctx_out[[1L]], "^Last request q[0-9a-f]+ \\(the compaction request\\):$")
  compaction_total = figure(ctx_out, "^  total ")
  expect_match(ctx_out, "^  next request +~[0-9,]+$", all = FALSE)
  expect_identical(unique(nchar(grep("^  (total|next request|context left) ", ctx_out,
                                     value = TRUE))), 26L)
  expect_lt(figure(ctx_out, "^  next request "), compaction_total)
  s = peter(s, "q3")
  ctx_out = run_command(rs, "/context")$out
  expect_match(ctx_out[[1L]], "^Last request q[0-9a-f]+:$")
  expect_false(any(grepl("next request", ctx_out, fixed = TRUE)))
  expect_lt(figure(ctx_out, "^  total "), compaction_total)
})

test_that("commands of later plans answer when their plan is absent", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  local_mocked_bindings(ns_fun = function(name) NULL)
  expect_identical(run_command(rs, "/skills")$out, "Skills are not available.")
  expect_identical(run_command(rs, "/mcp")$out, "MCP is not available.")
  expect_identical(run_command(rs, "/doc analysis.R")$out,
                   "Binding a document needs gptr_doc(), which is not available.")
  expect_identical(run_command(rs, "/retry")$out, "There is no answer to retry.")
})

test_that("/retry sends the undone prompt again, and nothing when the rewind is cancelled", {
  local_console_commands()
  local_project()
  e = new.env()
  s = peter("A", model = gptr_fake_provider(list("a1", "a2")), envir = e)
  rs = repl_state(s, e)
  sent = new.env(parent = emptyenv())
  sent$texts = character()
  send = function(text) {
    sent$texts = c(sent$texts, text)
    peter(s, text, envir = e)
  }
  expect_identical(run_command(rs, "/retry", send)$res, "prompt")
  off = gptr_register(gptr_hook("session_before_tree", function(event, ctx) list(cancel = TRUE)))
  withr::defer(off())
  expect_identical(run_command(rs, "/retry", send)$out, "The last turn was not undone.")
  expect_identical(sent$texts, "A")
  expect_equal(s$turns, 1)
})

test_that("/retry preloads the undone prompt's skills again, and none of a later prompt", {
  local_console_commands()
  withr::defer(res_prune("skills:", character()))
  local_project(trust = TRUE, files = list(
    ".gptr/skills/stats/SKILL.md" = "---\nname: stats\ndescription: Statistics.\n---\nUse lm().\n"))
  e = new.env()
  fake = local_fake_provider(list("a1", "a2"))
  s = peter("A", skills = "stats", model = fake, envir = e)
  rs = repl_state(s, e)
  sent = new.env(parent = emptyenv())
  send = function(text) sent$text = text
  expect_identical(run_command(rs, "/retry", send)$res, "prompt")
  expect_identical(sent$text, "A")
  expect_identical(rs$next_skills, "stats")
  rs$next_skills = NULL
  peter(s, "B", model = fake, envir = e)
  run_command(rs, "/retry", send)
  expect_identical(sent$text, "B")
  expect_null(rs$next_skills)
})

test_that("/skill:<name> preloads the skill for the next prompt", {
  local_console_commands()
  old = the$services
  withr::defer({
    the$services = old
  })
  ext_service_set("skill.body", function(name) list(text = "Use lm().", dir = tempdir()),
                  provided_by = "test")
  rs = repl_state(NULL, new.env())
  sent = new.env(parent = emptyenv())
  run_command(rs, "/skill:stats fit a model", send = function(text) {
    sent$text = text
  })
  expect_identical(rs$next_skills, "stats")
  expect_identical(sent$text, "fit a model")
})

test_that("/permissions shows and changes the rules of this R session", {
  local_console_commands()
  local_permission_rules()
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/permissions allow r(fn:saveRDS)")$out,
                   "Added allow rule r(fn:saveRDS) for this R session.")
  expect_true(any(grepl("r(fn:saveRDS)", run_command(rs, "/permissions")$out, fixed = TRUE)))
  expect_match(run_command(rs, "/permissions maybe x")$out, "^Use /permissions")
  r = run_command(rs, "/permissions allow r(fn:")
  expect_identical(r$res, "error")
})
