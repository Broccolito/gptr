# tests/testthat/test-subagent-team.R -- the scheduler, gptr_parallel(), teams, fan-outs and
# reports (plan P19).

# A stand-in child for scheduler tests: a run that settles `after` seconds after it starts,
# through a reactor timer, and a log of starts, settles and cancels
stub_items = function(n, pool = "inline", after = 0.2, log) {
  lapply(seq_len(n), function(i) {
    force(i)
    list(pool = pool, start = function() {
      run = new.env(parent = emptyenv())
      run$id = paste0("u", i)
      run$settled = FALSE
      log$active = log$active + 1L
      log$peak = max(log$peak, log$active)
      log$started = c(log$started, i)
      reactor_timer(reactor_now() + after, function() {
        run$settled = TRUE
        log$active = log$active - 1L
      })
      list(run = run, cancel = function() log$cancelled = c(log$cancelled, i))
    })
  })
}

stub_log = function() {
  log = new.env(parent = emptyenv())
  log$active = 0L
  log$peak = 0L
  log$started = integer()
  log$settled = integer()
  log$cancelled = integer()
  log
}

# A fake that answers each request with the text of the agent's prompt turn number
local_team_fake = function(script = function(request) paste("reply", request$n),
                           .env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(mode = "auto", model = "fake/fake-1", .env = .env)
  local_fake_provider(script, .env = .env)
}

test_that("the scheduler runs at most max_total children and reports each once", {
  log = stub_log()
  hs = subagent_schedule(stub_items(5L, log = log), 2L, function(i, h) {
    log$settled = c(log$settled, i)
  })
  expect_length(hs, 5L)
  expect_identical(log$peak, 2L)
  expect_identical(sort(log$settled), 1:5)
  expect_identical(log$started, 1:5)
})

test_that("pools keep their own limits: workers 2 under R CMD check, inline unaffected", {
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  local_gptr_options(subagents.max_workers = 4L)
  log = stub_log()
  subagent_schedule(stub_items(4L, pool = "worker", log = log), 8L)
  expect_identical(log$peak, 2L)
  log2 = stub_log()
  subagent_schedule(stub_items(4L, pool = "inline", log = log2), 8L)
  expect_identical(log2$peak, 4L)
})

test_that("a failing start cancels the children already running", {
  log = stub_log()
  items = stub_items(3L, after = 30, log = log)
  items[[3L]]$start = function() stop("start failed")
  expect_error(subagent_schedule(items, 3L), "start failed")
  expect_identical(sort(log$cancelled), 1:2)
})

test_that("at top level the pause menu has no child run to steer or background", {
  seen = integer()
  local_bootstrap_service("console.interrupt_policy", function(expr_fun, runs, mode = "call") {
    seen <<- c(seen, length(runs))
    expr_fun()
  })
  subagent_schedule(stub_items(2L, log = stub_log()), 2L)
  expect_identical(unique(seen), 0L)
})

test_that("gptr_parallel() returns a team of the members (contract 6.5 example)", {
  fake = gptr_fake_provider(list("ok"))
  team = gptr_parallel(planner = peter("Plan it", model = fake, envir = new.env()),
                       lit = peter("Summarise it", model = fake, envir = new.env()))
  expect_identical(names(team$children), c("planner", "lit"))
  expect_identical(team$kind, "team")
  expect_identical(team$planner$status, "idle")
  expect_identical(team$text, "### planner (fake/fake-1)\nok\n\n### lit (fake/fake-1)\nok")
  expect_identical(session_data(team$lit)$parent_id, team$id)
  expect_identical(team$lit$kind, "child")
  expect_identical(nrow(gptr_usage(team, by = "session")) > 0L, TRUE)
  ents = Filter(function(e) identical(e$custom_type, "gptr.subagent"), session_data(team)$entries)
  expect_length(ents, 2L)
  # the members' provider spec is the team's too, so piping the team can call its model
  expect_identical(session_data(peter(team, "Merge them"))$last_text, "ok")
})

test_that("gptr_parallel() members run concurrently, max_active at a time", {
  local_team_fake(list(fake_text("slow", delay = 2)))
  t0 = Sys.time()
  team = gptr_parallel(a = peter("one", envir = new.env()), b = peter("two", envir = new.env()),
                       c = peter("three", envir = new.env()))
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 5)
  expect_identical(unname(vapply(team$children, function(s) s$status, "")), rep("idle", 3L))
  t1 = Sys.time()
  gptr_parallel(a = peter("one", envir = new.env()), b = peter("two", envir = new.env()),
                max_active = 1L)
  expect_gte(as.numeric(difftime(Sys.time(), t1, units = "secs")), 3.5)
})

test_that("gptr_parallel() keeps failed members, or signals the first with on_error = stop", {
  local_team_fake(function(request) {
    if (identical(request$last_user, "bad")) fake_error("bad request", status = 400L) else "fine"
  })
  team = gptr_parallel(ok = peter("good", envir = new.env()), ko = peter("bad", envir = new.env()))
  expect_identical(team$ko$status, "error")
  expect_identical(team$ok$status, "idle")
  cnd = expect_error(gptr_parallel(ok = peter("good", envir = new.env()),
                                   ko = peter("bad", envir = new.env()), on_error = "stop"),
                     class = "gptr_error")
  expect_s3_class(cnd$session, "gptr_session")
  expect_identical(cnd$session$status, "error")
})

test_that("gptr_parallel() refuses unnamed members, non-sessions and accessor names", {
  local_team_fake()
  expect_error(gptr_parallel(peter("x", envir = new.env())), class = "gptr_error_invalid_argument")
  expect_error(gptr_parallel(a = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_parallel(text = peter("x", envir = new.env())),
               class = "gptr_error_invalid_argument")
})

test_that("gptr_parallel() members keep the user's random seed (IC-61)", {
  local_team_fake(function(request) {
    if (length(request$last_results)) "done" else fake_tool("r", code = "z = stats::runif(1)")
  })
  withr::local_seed(3)
  seed = get(".Random.seed", envir = globalenv())
  e1 = new.env()
  e2 = new.env()
  gptr_parallel(a = peter("draw", envir = e1), b = peter("draw", envir = e2))
  expect_true(is.numeric(e1$z) && is.numeric(e2$z))
  expect_false(identical(e1$z, e2$z))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
})

test_that("model-issued teams are limited to gptr.subagents.max_tasks (IC-39)", {
  local_gptr_options(subagents.max_tasks = 2L)
  expect_invisible(subagent_task_limit(5L, NULL))
  cur = list(depth = 1L)
  expect_invisible(subagent_task_limit(2L, cur))
  cnd = expect_error(subagent_task_limit(3L, cur), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(cnd), "gptr.subagents.max_tasks", fixed = TRUE)
})

test_that("replayed children bound to a block are attached to the replayed team (IC-46)", {
  local_team_fake()
  team = session_new("fake/fake-1", "auto", home = new.env(), kind = "replayed")
  td = session_data(team)
  td$block = "abc123"
  kid = session_new("fake/fake-1", "auto", home = new.env(), kind = "replayed")
  kd = session_data(kid)
  kd$last_text = "Looks fine."
  session_replay_bind("abc123", kid, child = "stats")
  out = subagent_replay_attach(team, c("stats", "code"), "team")
  expect_identical(out$kind, "team")
  expect_identical(names(out$children), "stats")
  expect_identical(out$stats, kid)
  expect_identical(out$text, "### stats (fake/fake-1)\nLooks fine.")
})

# ---- Task 4: teams ---------------------------------------------------------------------------

# A gateway call record (P08's call_new(), contract 7.8) for driving the routes directly
team_call = function(prompt, agents = NULL, envir = new.env(), parallel = NULL, context = list(),
                     values = NULL, opts = list(), run = TRUE, background = FALSE,
                     model = NULL) {
  call_new(prompt = prompt, template = prompt, context = context, values = values,
           envir = envir,
           ids = list(model = model, mode = NULL, skills = NULL, plugins = NULL,
                      extensions = NULL, tools = NULL, agents = agents),
           args = list(parallel = parallel, background = background, budget = NULL,
                       replay = NULL, opts = opts, run = run, stdin = FALSE))
}

team_agents = function(...) {
  nms = c(...)
  out = lapply(nms, function(nm) {
    gptr_agent(nm, description = paste("agent", nm), model = "fake/fake-1")
  })
  names(out) = nms
  out
}

test_that("the team route matches calls with agents only", {
  expect_true(route_team_match(team_call("x", agents = team_agents("a"))))
  expect_false(route_team_match(team_call("x")))
})

test_that("a team session holds one child per agent and joins their reports", {
  local_team_fake(function(request) paste("report for", request$last_user))
  team = route_team_run(team_call("Review it", agents = team_agents("stats", "code")))
  expect_s3_class(team, "gptr_session")
  expect_identical(team$kind, "team")
  expect_identical(names(team$children), c("stats", "code"))
  expect_identical(team$stats$text, "report for Review it")
  expect_identical(team$text, paste0("### stats (fake/fake-1)\nreport for Review it\n\n",
                                     "### code (fake/fake-1)\nreport for Review it"))
  expect_identical(session_data(team$code)$agent, "code")
  ents = Filter(function(e) identical(e$custom_type, "gptr.subagent"), session_data(team)$entries)
  expect_identical(vapply(ents, function(e) e$data$status, ""), c("idle", "idle"))
})

test_that("the reports reach a continuation as user-role data (IC-55)", {
  local_team_fake(function(request) "report text that is long")
  team = route_team_run(team_call("Review it", agents = team_agents("stats", "code")))
  txt = subagent_reports_block(list(session = team), 20000L)
  expect_match(txt, "<agent_report from=\"stats\">\nreport text that is long\n</agent_report>",
               fixed = TRUE)
  expect_match(txt, "<agent_report from=\"code\">", fixed = TRUE)
  expect_null(subagent_reports_block(list(session = team$stats), 20000L))
  local_gptr_options(child_text_max = 8L)
  short = subagent_reports_block(list(session = team), 20000L)
  expect_match(short, ">\nreport t\n</agent_report>", fixed = TRUE)
})

test_that("exports return to the caller in task order; a second exporter keeps the first", {
  local_team_fake(function(request) {
    if (length(request$last_results)) return("done")
    fake_tool("r", code = paste0("res = '", if (request$n == 1L) "first" else "second", "'"))
  })
  local_gptr_options(quiet = FALSE)
  e = new.env()
  agents = list(a = gptr_agent("a", description = "a", model = "fake/fake-1", export = "res"),
                b = gptr_agent("b", description = "b", model = "fake/fake-1", export = "res"))
  expect_message(route_team_run(team_call("make res", agents = agents, envir = e,
                                          opts = list(max_active = 1L))),
                 "also exported `res`", fixed = TRUE)
  expect_identical(e$res, "first")
})

test_that("team calls run in the foreground and start new agents", {
  local_team_fake()
  a = team_agents("a")
  cnd = expect_error(route_team_run(team_call("x", agents = a, background = TRUE)),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "background")
  cnd = expect_error(route_team_run(team_call("x", agents = a, run = FALSE)),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, ".run")
  call = team_call("x", agents = a)
  call$session = session_new("fake/fake-1", "auto", home = new.env())
  expect_error(route_team_run(call), class = "gptr_error_invalid_argument")
})


test_that("a settled team dispatches agent_end with its document site (IC-47)", {
  local_team_fake()
  seen = new.env()
  id = hook_add("agent_end", function(event, ctx) {
    if (identical(ctx$session$kind, "team")) {
      seen$doc = event$doc
      seen$status = event$status
    }
    NULL
  })
  withr::defer(hook_remove(id))
  call = team_call("Review", agents = team_agents("a", "b"))
  call$doc = list(note = "the statement's site")
  route_team_run(call)
  expect_identical(seen$doc$note, "the statement's site")
  expect_identical(seen$status, "idle")
})
