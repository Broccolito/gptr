# tests/testthat/test-console-commands.R -- the slash commands (plan P14, Task 6).

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
  off = gptr_register(gptr_command("boom", function(args, ctx) stop("kaput")))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  r = run_command(rs, "/nope")
  expect_identical(r$res, "unknown")
  expect_true(any(grepl("Unknown command /nope", r$err, fixed = TRUE)))
  r = run_command(rs, "/boom")
  expect_identical(r$res, "error")
  expect_true(any(grepl("Error in /boom: kaput", r$err, fixed = TRUE)))
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

test_that("/help lists the commands and the input syntax", {
  local_console_commands()
  out = run_command(repl_state(NULL, new.env()), "/help")$out
  expect_true(any(grepl("^  /mode", out)))
  expect_true(any(grepl("!!code", out, fixed = TRUE)))
  expect_identical(run_command(repl_state(NULL, new.env()), "/help mode")$out,
                   "/mode  Show or switch the permission mode: /mode [plan|manual|edits|auto]")
})

test_that("/exit, /quit and /q end the REPL", {
  local_console_commands()
  for (cmd in c("/exit", "/quit", "/q")) {
    rs = repl_state(NULL, new.env())
    run_command(rs, cmd)
    expect_true(rs$exit)
  }
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
  expect_match(run_command(rs, "/mode turbo")$out, "Unknown mode 'turbo'", fixed = TRUE)
})

test_that("/mode on a session appends the mode change for the next turn", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  expect_identical(run_command(rs, "/mode auto")$out, "Mode: auto (from the next turn)")
  expect_identical(s$mode, "auto")
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
  expect_match(env_out, "^  counts: ")
  s = idle_session()
  rs$session = s
  status = run_command(rs, "/status")$out
  expect_identical(status[[1L]], paste0("session   ", s$id, "  (idle, 0 turns)"))
  expect_true(any(grepl("^queue     0 steer, 1 follow-up$", status)))
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

test_that("/cost, /context, /fork and /resume work on a session that ran", {
  local_console_commands()
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  rs = repl_state(s, new.env())
  cost = run_command(rs, "/cost")$out
  expect_match(cost[[length(cost)]], "^Total: \\$")
  ctx_out = run_command(rs, "/context")$out
  expect_match(ctx_out[[1L]], "^Last request q[0-9a-f]+:$")
  # an unknown cache read is shown as unknown (IC-74)
  d = session_data(s)
  d$ledger$cached = NA
  expect_match(run_command(rs, "/context")$out[[2L]], "[0-9]  \\(cache unknown\\)$")
  run_command(rs, "/fork")
  expect_false(identical(rs$session$id, s$id))
  listing = run_command(rs, "/resume")$out
  expect_true(any(grepl(s$id, listing, fixed = TRUE)))
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
