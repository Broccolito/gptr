# tests/testthat/test-console-interrupt.R -- the interrupt policy and the pause menu (plan P14).
# Task 3: menu, steering, abort and nesting with simulated interrupts. Task 7 appends the
# INFRA-03 test with real SIGINTs.

# A simulated Ctrl-C: an `interrupt` condition with a `resume` restart, as R's onintr() signals
# it during a computation (report 18 section 2.2.1). One that is neither resumed nor caught fails
# the test instead of jumping to the top level.
fake_interrupt = function() {
  cnd = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  resumed = withRestarts({
    signalCondition(cnd)
    FALSE
  }, resume = function() TRUE)
  if (!isTRUE(resumed)) stop("the interrupt was neither resumed nor caught")
  invisible(TRUE)
}

# Menu answers for gptr_readline(), in order (a function answer is called: it may signal a
# second interrupt); a terminal front end where someone can answer
local_menu_answers = function(answers, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$answers = as.list(answers)
  log$prompts = character()
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    log$prompts = c(log$prompts, prompt)
    a = if (length(log$answers)) log$answers[[1L]] else "a"
    log$answers = log$answers[-1L]
    if (is.function(a)) a() else a
  }, front_end = function() "terminal", .env = .env)
  local_gptr_options(interactive = TRUE, .env = .env)
  log
}

# run_abort() replaced by a recorder (the runs below are stand-ins with the 04 section 7.6
# fields the policy reads: id, status, opts)
local_abort_log = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$aborted = character()
  testthat::local_mocked_bindings(run_abort = function(run, reason = "user") {
    log$aborted = c(log$aborted, run$id)
    run$status = "aborted"
    invisible(run)
  }, .env = .env)
  log
}

stand_in_run = function(id = "u0000run1", status = "streaming", background = FALSE) {
  run = new.env(parent = emptyenv())
  run$id = id
  run$status = status
  run$opts = list(background = background)
  class(run) = "gptr_run"
  run
}

policy_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

local_tracked = function(run, s, .env = parent.frame()) {
  console_track(run$id, s)
  withr::defer(console_drop(run$id), envir = .env)
  invisible(run)
}

notices = function(expr) {
  utils::capture.output(expr, type = "message")
}

test_that("continue resumes the interrupted computation", {
  log = local_menu_answers("c")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "finished"
    }, list(), mode = "call")
  })
  expect_identical(res, "finished")
  expect_true(any(grepl("[gptr] paused: [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_true(any(grepl("[gptr] continuing", err, fixed = TRUE)))
})

test_that("steer and follow-up queue the text with source pause_menu (IC-55)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  log = local_menu_answers(c("s", "use only mpg", "f", "then plot it"))
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      fake_interrupt()
      "done"
    }, list(run), mode = "call")
  })
  expect_identical(res, "done")
  q = session_data(s)$queue
  expect_identical(q$steer[[1L]]$text, "use only mpg")
  expect_identical(q$steer[[1L]]$source, "pause_menu")
  texts = vapply(q$follow_up, function(i) i$text, "")
  expect_true("then plot it" %in% texts)
  expect_true(any(grepl("[s]teer, [f]ollow-up, [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_identical(log$prompts, c("? ", "steer> ", "? ", "follow-up> "))
})

test_that("pause-menu text passes the input event with source steer", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (identical(event$source, "steer")) list(action = "transform", text = toupper(event$text))
  }))
  withr::defer(off())
  local_menu_answers(c("s", "use mpg"))
  notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "call"))
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "USE MPG")
})

test_that("abort in mode repl aborts the runs and returns NULL", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = "not set"
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
  expect_true(any(grepl("[gptr] aborted; the session is kept.", err, fixed = TRUE)))
})

test_that("abort in mode call re-signals the interrupt so loops stop", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = NULL
  notices({
    res = tryCatch(with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "call"), interrupt = function(e) "outer handler saw it")
  })
  expect_identical(res, "outer handler saw it")
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("a second Ctrl-C while the menu waits aborts", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  second = function() {
    signalCondition(structure(class = c("interrupt", "condition"),
                              list(message = "", call = NULL)))
    "c"
  }
  local_menu_answers(list(second))
  res = "not set"
  notices({
    res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("the policy is abort-only where resuming is unverified (RStudio, Rgui, Jupyter)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  log = local_menu_answers("c")
  for (fe in c("rstudio", "rgui", "jupyter")) {
    local_mocked_bindings(front_end = function() fe)
    run$status = "streaming"
    res = "not set"
    notices({
      res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
    })
    expect_null(res)
  }
  expect_identical(log$prompts, character())
  expect_identical(aborted$aborted, rep("u0000run1", 3L))
})

test_that("nested policies show one menu and the inner runs join the outer one", {
  s = policy_session()
  outer_run = local_tracked(stand_in_run("u0000run1"), s)
  inner_run = local_tracked(stand_in_run("u0000run2"), s)
  aborted = local_abort_log()
  log = local_menu_answers("a")
  box = new.env(parent = emptyenv())
  res = "not set"
  notices({
    res = with_interrupt_policy(function() {
      with_interrupt_policy(function() {
        box$seen = vapply(policy_find()$runs, function(r) r$id, "")
        fake_interrupt()
      }, list(inner_run), mode = "call")
    }, list(outer_run), mode = "repl")
  })
  expect_null(res)
  expect_identical(box$seen, c("u0000run1", "u0000run2"))
  expect_identical(log$prompts, "? ")
  expect_setequal(aborted$aborted, c("u0000run1", "u0000run2"))
})

test_that("[b]ackground hands a foreground run to bg.register (P21) and resumes", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  old = the$services
  withr::defer({
    the$services = old
  })
  got = new.env(parent = emptyenv())
  ext_service_set("bg.register", function(session) {
    got$session = session
    invisible(session)
  }, provided_by = "test")
  local_menu_answers("b")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "kept running"
    }, list(run), mode = "call")
  })
  expect_identical(res, "kept running")
  expect_identical(got$session, s)
  expect_true(any(grepl("[b]ackground", err, fixed = TRUE)))
  local_menu_answers(c("b", "c"))
  err = notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl"))
  expect_false(any(grepl("[b]ackground", err, fixed = TRUE)))
})

test_that("a steer typed while a tool runs is queued once no tool is on the stack", {
  s = policy_session()
  tool_run = stand_in_run("u0000tool")
  local({
    local_mocked_bindings(run_current = function() tool_run)
    notices(policy_enqueue(s, "after the tool", "steer"))
    expect_length(session_data(s)$queue$steer, 0L)
  })
  reactor_pump(until = function() length(session_data(s)$queue$steer) > 0L, slice_ms = 10L,
               timeout = 5)
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "after the tool")
  expect_identical(session_data(s)$queue$steer[[1L]]$source, "pause_menu")
})

test_that("a steer typed while a tool runs reaches the request after the tool result", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "ack", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  local_menu_answers(c("s", "use mpg"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  notices(with_interrupt_policy(function() run_wait(run), list(run), mode = "call"))
  msgs = fake_requests(fake)[[2L]]$messages
  expect_identical(msgs[[length(msgs)]]$role, "operator")
  expect_match(json_encode(msgs[[length(msgs)]]), "use mpg", fixed = TRUE)
})

test_that("a steer typed in a tool and then aborted is listed as dropped, never sent later", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    fake_interrupt()
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "done", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  local_menu_answers(c("s", "use mpg", "a"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  err = notices({
    with_interrupt_policy(function() run_wait(run), list(run), mode = "repl")
    run_wait(run_start(s, msg_user("an unrelated prompt")))
  })
  expect_identical(run$status, "aborted")
  expect_true(any(grepl("[gptr] dropped queued messages: 'use mpg'", err, fixed = TRUE)))
  expect_length(session_data(s)$queue$steer, 0L)
  reqs = fake_requests(fake)
  expect_no_match(json_encode(reqs[[length(reqs)]]$messages), "use mpg", fixed = TRUE)
})

test_that("a steer typed in a tool that pumps the reactor reaches the next request", {
  local_project()
  local_gptr_options(unsafe_no_permissions = TRUE)
  off = gptr_register(gptr_tool("slow", "Test tool slow", execute = function(input, ctx) {
    fake_interrupt()
    reactor_pump(slice_ms = 1L, allow_runs = character(), timeout = 0.001)
    "slow done"
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("slow"), "ack", "done"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  # the tool_execution_end hook of builtin:console (Task 7); the steer is queued when it returns
  box = new.env(parent = emptyenv())
  off_hook = gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
    console_on_tool_end(event, ctx)
    box$queued = length(session_data(s)$queue$steer)
    NULL
  }))
  withr::defer(off_hook())
  local_menu_answers(c("s", "use mpg"))
  run = local_tracked(run_start(s, msg_user("go")), s)
  notices(with_interrupt_policy(function() run_wait(run), list(run), mode = "call"))
  expect_identical(box$queued, 1L)
  msgs = fake_requests(fake)[[2L]]$messages
  expect_identical(msgs[[length(msgs)]]$role, "operator")
  expect_match(json_encode(msgs[[length(msgs)]]), "use mpg", fixed = TRUE)
})

test_that("a [b]ackground refusal is a notice and the menu asks again", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  old = the$services
  withr::defer({
    the$services = old
  })
  ext_service_set("bg.register", function(session) {
    gptr_abort("Background sessions need the 'later' package.", "missing_package")
  }, provided_by = "test")
  log = local_menu_answers(c("b", "c"))
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "kept running"
    }, list(run), mode = "call")
  })
  expect_identical(res, "kept running")
  expect_true(any(grepl("[gptr] cannot run in the background: Background sessions need",
                        err, fixed = TRUE)))
  expect_identical(log$prompts, c("? ", "? "))
})

test_that("the policy is the console.interrupt_policy service of builtin:console", {
  expect_identical(the$services[["console.interrupt_policy"]]$provided_by, "P14")
  expect_identical(the$services[["console.interrupt_policy"]]$builtin, "console")
  expect_identical(names(formals(the$services[["console.interrupt_policy"]]$fun)),
                   c("expr_fun", "runs", "mode"))
})

# ---------------------------------------------------------------- Task 7: INFRA-03 (real SIGINTs)

# Drives an interactive R child through processx like a user at a terminal (report 18 A.8
# e2_driver.R): reads its merged stdout/stderr, waits for markers, sends lines
infra03_driver = function(p) {
  st = new.env(parent = emptyenv())
  st$out = ""
  st$seen = 0L
  pump = function(ms = 200L) {
    p$poll_io(ms)
    x = p$read_output()
    if (nzchar(x)) st$out = paste0(st$out, x)
    invisible(NULL)
  }
  st$wait_for = function(pattern, timeout = 30) {
    deadline = Sys.time() + timeout
    repeat {
      pump()
      rest = substring(st$out, st$seen + 1L)
      pos = regexpr(pattern, rest, fixed = TRUE)
      if (pos > 0L) {
        st$seen = st$seen + pos + nchar(pattern) - 1L
        return(TRUE)
      }
      if (!p$is_alive() || Sys.time() > deadline) return(FALSE)
    }
  }
  st$send = function(x) {
    Sys.sleep(0.2)
    p$write_input(paste0(x, "\n"))
  }
  st$has = function(pattern) grepl(pattern, st$out, fixed = TRUE)
  st$value = function(key) {
    m = regmatches(st$out, regexpr(paste0(key, "\\[[^]]*\\]"), st$out))
    if (!length(m)) return(NA_character_)
    sub("\\]$", "", sub(paste0("^", key, "\\["), "", m))
  }
  st
}

# The child script: loads gptr (tracemem_loader(), P01), defines one function per scenario
infra03_child = function(providers) {
  c(
    tracemem_loader(),
    paste0("options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off', ",
           "cli.num_colors = 1L)"),
    sprintf("prov = readRDS('%s')", providers),
    "e = new.env(parent = globalenv())",
    "msg_texts = function(msgs) vapply(msgs, function(m) {",
    "  paste(vapply(Filter(function(b) identical(b$type, 'text'), m$content),",
    "               function(b) b$text, ''), collapse = '')",
    "}, '')",
    "step_ttft = function() {",
    "  s = peter('first', model = prov$ttft, envir = e, mode = auto)",
    "  cat('STATUS-TTFT', s$status, '\\n')",
    "}",
    "step_tool = function() {",
    "  fake = gptr_fake_provider(list(",
    "    list(tool = 'r', input = list(code = 'Sys.sleep(3); 1')), 'after the tool'))",
    "  peter('tool', model = fake, envir = e, mode = auto)",
    "  req = fake$log$requests[[2L]]$messages",
    "  roles = vapply(req, function(m) m$role, '')",
    "  steer = which(grepl('use base R only', msg_texts(req), fixed = TRUE))",
    "  tool = which(roles == 'tool_result')",
    "  ok = length(steer) == 1L && length(tool) >= 1L && steer[[1L]] > tool[[1L]]",
    "  cat('STEER-AFTER-TOOL', ok, '\\n')",
    "}",
    "step_abort = function() {",
    "  res = tryCatch(peter('stream', model = prov$stream, envir = e, mode = auto),",
    "                 interrupt = function(i) 'INTERRUPTED')",
    "  s = gptr_last()",
    "  m = s$messages[[length(s$messages)]]",
    "  cat('STOP', m$stop_reason, '\\n')",
    "  cat('PARTIAL[', msg_texts(list(m)), ']\\n', sep = '')",
    "  cat('ABORT-DONE', identical(res, 'INTERRUPTED'), '\\n')",
    "}",
    "cat('CHILD READY\\n')"
  )
}

test_that("INFRA-03: real SIGINTs continue, steer and abort runs (acceptance 5)", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not(identical(Sys.getenv("CI"), "true"), "INFRA-03 drives an interactive R on CI")
  ttft = local_mock_server("ttft", delay = 3, n = 4L, interval = 0.05)
  stream = local_mock_server("stream", n = 40L, interval = 0.25)
  dir = withr::local_tempdir("gptr-infra03-")
  providers = file.path(dir, "providers.rds")
  saveRDS(list(ttft = ttft$provider, stream = stream$provider), providers)
  child = file.path(dir, "child.R")
  writeLines(infra03_child(normalizePath(providers, winslash = "/")), child)
  # a complete environment (processx rejects NA, IC-60) without the IDE variables that would
  # make front_end() report RStudio, Positron, VS Code or Jupyter (abort-only, no menu)
  env = unclass(Sys.getenv())
  env = env[!names(env) %in% c("RSTUDIO", "POSITRON", "TERM_PROGRAM", "JPY_SESSION_NAME",
                               "QUARTO_DOCUMENT_PATH", "QUARTO_DOCUMENT_FILE")]
  env[["TERM"]] = "xterm"
  env[["LANG"]] = "en_US.UTF-8"
  env[["R_LIBS"]] = paste(.libPaths(), collapse = .Platform$path.sep)
  # `R --interactive`, not rscript_path(): only R reads its console from a pipe interactively
  # (report 18 A.8); an absolute path, so R CMD check's dummy `R` on PATH is never used (IC-60)
  p = processx::process$new(file.path(R.home("bin"), "R"),
                            c("--vanilla", "--interactive", "--quiet", "--no-echo"),
                            stdin = "|", stdout = "|", stderr = "2>&1", env = env,
                            cleanup = TRUE)
  withr::defer(if (p$is_alive()) p$kill())
  drv = infra03_driver(p)
  p$write_input(sprintf("source('%s')\n", normalizePath(child, winslash = "/")))
  expect_true(drv$wait_for("CHILD READY", timeout = 120))

  # 1. SIGINT once the mock holds the request (3 s to the first byte), then [c]ontinue: the
  # request completes
  drv$send("step_ttft()")
  deadline = Sys.time() + 30
  while (!nrow(ttft$log()) && Sys.time() < deadline) Sys.sleep(0.05)
  expect_identical(nrow(ttft$log()), 1L)
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("c")
  expect_true(drv$wait_for("STATUS-TTFT idle"))
  expect_true(drv$has("tok04"))

  # 2. SIGINT while a tool runs, then [s]teer: the steer arrives after the tool result
  drv$send("step_tool()")
  expect_true(drv$wait_for("Sys.sleep(3)"))
  Sys.sleep(0.5)
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("s")
  expect_true(drv$wait_for("steer>"))
  drv$send("use base R only")
  expect_true(drv$wait_for("STEER-AFTER-TOOL TRUE"))

  # 3. SIGINT mid-stream, then [a]bort: the socket closes and the partial is what arrived
  drv$send("step_abort()")
  expect_true(drv$wait_for("tok03"))
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("a")
  expect_true(drv$wait_for("ABORT-DONE TRUE"))
  expect_true(drv$has("STOP aborted"))
  partial = drv$value("PARTIAL")
  full = paste(sprintf("tok%02d ", 1:40), collapse = "")
  expect_true(nzchar(partial))
  expect_true(startsWith(full, partial))
  expect_lt(nchar(partial), nchar(full))
  deadline = Sys.time() + 15
  closed = FALSE
  while (!closed && Sys.time() < deadline) {
    closed = any(stream$log()$disconnected %in% TRUE)
    if (!closed) Sys.sleep(0.25)
  }
  expect_true(closed)
  p$write_input("q('no')\n")
})
