# Shared test harness of P06 (session kernel and agent loop). The first line of every P06 test
# file sources this file with local = TRUE, locating it through testthat::test_path().
# It lives in P06's own fixture directory (P06 owns no helper-*.R file) and holds the loader of
# report 02's oracle checks plus small helpers built only on P01's test helpers (contract 04
# section 12.2) and the P02 registry API.

#' The report 02 oracle checks of one group ("loop", "store", "recovery"), keyed by id
oracle = function(group) {
  path = testthat::test_path("fixtures", "oracles", "report02", paste0(group, ".json"))
  recs = json_decode(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"))
  stats::setNames(recs, vapply(recs, function(r) r$id, ""))
}

#' The title of the test of one oracle check: "<id> <gptr assertion>"
oracle_title = function(recs, id) paste(id, recs[[id]]$gptr)

#' Every oracle id of `recs` has a test_that() titled with oracle_title() in `file`
expect_oracles_covered = function(recs, file) {
  src = paste(readLines(testthat::test_path(file), encoding = "UTF-8", warn = FALSE),
              collapse = "\n")
  hits = regmatches(src, gregexpr("oracle_title\\([a-z_]+, \"[A-Z][0-9]{2}\"\\)", src))[[1L]]
  ids = sub("^.*\"([A-Z][0-9]{2})\"\\)$", "\\1", hits)
  testthat::expect_setequal(unique(ids), names(recs))
}

#' A temporary project with a .gptr/ workspace that project_root() resolves to
local_store = function(.env = parent.frame()) {
  dir = local_project(.env = .env)
  withr::local_envvar(GPTR_PROJECT_ROOT = dir, .local_envir = .env)
  withr::local_options(gptr.project_root = dir, .local_envir = .env)
  dir
}

#' Register a test tool (rank 3) for the calling test
local_tool = function(name, execute, parameters = list(type = "object", properties = json_obj()),
                      execution = "sequential", annotations = list(), risk = NULL,
                      .env = parent.frame()) {
  spec = gptr_tool(name, paste("Test tool", name), parameters = parameters, execute = execute,
                   execution = execution, annotations = annotations, risk = risk)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

#' Register a test policy (rank 3) for the calling test
local_policy = function(name, check, .env = parent.frame()) {
  off = gptr_register(gptr_policy(name, check))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

#' Hide bootstrap services of later plans for the calling test (the fallbacks of 04 section 7.0)
#'
#' P07, P11, ... register their services in P01's bootstrap table from on_load(), so in the full
#' suite `ext_service_has()` is TRUE for them; a test of a P06 fallback hides them first. Records
#' added with local_service() live in the registry and are not affected.
local_without_services = function(names, .env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = .env)
  svc = old
  for (nm in names) svc[[nm]] = NULL
  assign("services", svc, envir = the)
  invisible(NULL)
}

#' A process-wide hook, or a session listener when `session` (an id) is given
local_hook = function(event, handler, session = NULL, .env = parent.frame()) {
  id = hook_add(event, handler, rank = if (is.null(session)) 3L else 0L,
                source = if (is.null(session)) "user" else "session", session = session)
  withr::defer(hook_remove(id), envir = .env)
  invisible(id)
}

#' Record events of the given types; returns an accessor `function(s = NULL)`
local_events = function(types, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$events = list()
  for (type in types) {
    local_hook(type, function(event, ctx) {
      log$events[[length(log$events) + 1L]] = event
      NULL
    }, .env = .env)
  }
  function(s = NULL) {
    ev = log$events
    if (is.null(s)) ev else Filter(function(e) identical(e$session, session_data(s)$id), ev)
  }
}

#' Allow every tool call in the calling test (the IC-53 escape hatch, set outside the run)
local_permissive = function(.env = parent.frame()) {
  local_gptr_options(unsafe_no_permissions = TRUE, .env = .env)
}

#' A fresh session on the fake provider (register one with local_fake_provider() first)
test_session = function(mode = "auto", home = new.env(), model = "fake/fake-1", ...) {
  session_new(model, mode, home = home, ...)
}

#' A run record attached to a session without starting it (unit tests of gates and budgets)
test_run = function(s, opts = list(), .env = parent.frame()) {
  run = run_new(s, opts, NULL)
  live = session_live(s)
  live$run = run
  withr::defer(assign("run", NULL, envir = live), envir = .env)
  run
}

#' A stored session with one prompt turn, a tool round trip and unicode text, built by appends
written_session = function(.env = parent.frame()) {
  local_store(.env = .env)
  s = test_session(home = globalenv())
  d = session_data(s)
  d$turns = 1L
  call = block_tool_call("c1", "read", list(path = "R/a.R"))
  session_append(s, entry_message(msg_user("Refactor a.R")))
  session_append(s, entry_message(msg_assistant(list(call), api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "tool_use")))
  session_append(s, entry_message(msg_tool_result("c1", "read", "contents of R/a.R",
                                                  details = list(lines = 1L))))
  session_append(s, entry_message(msg_assistant("All done \u2713", api = "fake", provider = "fake",
                                                model = "fake-1")))
  s
}

#' A one-turn session built by appends, with one usage row (no run needed). The row states its
#' cache columns as known zeros: under IC-74 a column the row leaves out is unknown, which would
#' make the footer's token count unknown.
answered_session = function(text = "The data has 32 rows.") {
  s = test_session()
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("How many rows?")))
  session_append(s, entry_message(msg_assistant(text, api = "fake", provider = "fake",
                                                model = "fake-1")))
  d$last_text = text
  usage_add(s, usage_conform(data.frame(request_id = "q000000000001", session = d$id,
                                        agent = "main",
                                        provider = "fake", model = "fake-1", route = "api",
                                        input = 1200, output = 34, cache_read = 0,
                                        cache_write_5m = 0, cache_write_1h = 0, cost = 0.0123,
                                        stringsAsFactors = FALSE)))
  s
}

# The two helpers of test-agent-dispatch.R (P06 Task 7), kept here so that lintr's
# object_usage_linter sees the harness helpers they call (as written_session() above).

#' Dispatch one assistant message's tool calls on a run that is attached but not started
dispatch = function(s, blocks, stop_reason = "tool_use", opts = list(), .env = parent.frame()) {
  run = test_run(s, opts, .env = .env)
  run$message = msg_assistant(blocks, api = "fake", provider = "fake", model = "fake-1",
                              stop_reason = stop_reason)
  calls = lapply(blocks, function(b) call_record(run, b))
  out = dispatch_tools(run, calls)
  list(run = run, out = out, msgs = tool_results(s))
}

#' Tools that throw, warn under warn = 2, hit a time limit and signal an interrupt (INFRA-10)
failing_tools = function(.env = parent.frame()) {
  local_tool("throw", function(input, ctx) stop("boom"), .env = .env)
  local_tool("warn2", function(input, ctx) {
    old = options(warn = 2)
    on.exit(options(old), add = TRUE)
    warning("warned")
    "not reached"
  }, .env = .env)
  local_tool("slowloop", function(input, ctx) {
    setTimeLimit(elapsed = 0.3, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
    repeat NULL
  }, .env = .env)
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "not reached"
  }, .env = .env)
}

# The projection fixture of test-agent-run.R's recovery checks R16-R17 (P06 Task 8), kept here
# for the same reason: it calls the harness's test_session().

#' A session whose transcript holds two tool calls, one result, an aborted reply and a new prompt
projection_session = function() {
  local_fake_provider(list("x"), .env = parent.frame())
  s = test_session()
  call = function(id) block_tool_call(id, "read", list(path = "a"))
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant(list(call("c1"), call("c2")), api = "fake",
                                                provider = "fake", model = "fake-1",
                                                stop_reason = "tool_use")))
  session_append(s, entry_message(msg_tool_result("c1", "read", "ok")))
  session_append(s, entry_message(msg_assistant("partial", api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "aborted")))
  session_append(s, entry_message(msg_user("next")))
  s
}

# The helpers of the engine tests of test-agent-loop.R and test-session-store.R (P06 Task 10),
# kept here for the same reason: they call the harness helpers above.

#' Register the `add` tool (two numbers)
add_tool = function(.env = parent.frame()) {
  local_tool("add", function(input, ctx) as.character(input$a + input$b),
             parameters = num_schema(a = "number", b = "number"), .env = .env)
}

#' A slow tool whose start enqueues two steers and a follow-up from the pipe
steer_during_slow = function(box, .env = parent.frame()) {
  local_tool("slow", function(input, ctx) "slow done", .env = .env)
  local_hook("tool_execution_start", function(event, ctx) {
    if (identical(event$tool_name, "slow")) {
      session_enqueue(box$s, "STEER-1: actually use metric units", "steer", source = "pipe")
      session_enqueue(box$s, "STEER-2: and be brief", "steer", source = "pipe")
      session_enqueue(box$s, "FOLLOWUP: now summarise", "follow_up", source = "pipe")
    }
    NULL
  }, .env = .env)
}

#' A run whose first tool signals an interrupt (the second call never runs)
interrupting_run = function(.env = parent.frame()) {
  add_tool(.env = .env)
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "not reached"
  }, .env = .env)
  fake = local_fake_provider(list(fake_tools(list(name = "spin", input = json_obj()),
                                             list(name = "add", input = list(a = 1, b = 1))),
                                  "after the interrupt"), .env = .env)
  s = test_session()
  res = tryCatch({
    run_text(s, "go")
    "returned"
  }, interrupt = function(cnd) "interrupted")
  list(s = s, res = res, fake = fake)
}

#' A fake compactor (the compact.should/compact.run services of P07) that logs its calls
local_compactor = function(should = function(s, tokens, idle_s) FALSE, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$calls = list()
  log$tokens = numeric()
  local_service("compact.should", function(s, tokens, idle_s) {
    log$tokens = c(log$tokens, tokens)
    should(s, tokens, idle_s)
  }, .env = .env)
  local_service("compact.run", function(s, reason, focus = NULL) {
    d = session_data(s)
    last = d$entries[[length(d$entries)]]
    log$calls[[length(log$calls) + 1L]] = list(reason = reason, last = last)
    users = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "user"),
                   entries_path(d))
    session_append(s, list(type = "compaction", summary = "## Goal\nsummary",
                           first_kept_entry_id = users[[length(users)]]$id, tokens_before = 1234,
                           details = list(readFiles = list("R/a.R")),
                           gptr = list(blocks = list(block_context("checkpoint", "summary",
                                                                   attrs = list(n = "1"))),
                                       state = list(), n = 1L)))
    invisible(s)
  }, .env = .env)
  log
}

#' Two runs on a stored session; the second compacts once at its first request (threshold)
compacting_run = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_tool("read", function(input, ctx) paste(rep("lorem ipsum", 50), collapse = " "),
             .env = .env)
  once = new.env()
  once$done = FALSE
  log = local_compactor(should = function(s, tokens, idle_s) {
    if (once$done || session_data(s)$turns < 2L) return(FALSE)
    once$done = TRUE
    TRUE
  }, .env = .env)
  fake = local_fake_provider(list("first answer", fake_tool("read", path = "R/a.R"),
                                  "second answer"),
                             .env = .env)
  s = test_session()
  run_text(s, "Task 1")
  n_before = length(session_data(s)$entries)
  run_text(s, "Task 2")
  list(s = s, log = log, fake = fake, n_before = n_before)
}

# The fixtures of the fork tests of test-session-object.R and test-session-store.R (P06 Task 12),
# kept here for the same reason: they call the harness helpers.

#' A two-turn source session ("first" -> A, "second" -> B) whose kept home binds `x = 1`; the fake
#' provider has two more answers (C, D) for runs on the source and its forks
fork_source = function(.env = parent.frame()) {
  local_permissive(.env = .env)
  local_fake_provider(list("A", "B", "C", "D"), .env = .env)
  home = new.env()
  home$x = 1
  s = test_session(home = home)
  run_text(s, "first")
  run_text(s, "second")
  list(s = s, home = home)
}

# The read tool of stored_run(). It is defined at the top level of the file on purpose: a closure
# created inside stored_run() would keep that frame, and with it the session, alive in the
# registry, so the garbage-collection tests of the session files could never collect it.
stored_read = function(input, ctx) {
  gptr_tool_result(paste("contents of", input$path), details = list(lines = 1L))
}

#' One stored run: a read tool round trip, then "All done"; one more answer for a fork's run
stored_run = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_tool("read", stored_read,
             parameters = list(type = "object", required = I("path"),
                               properties = list(path = list(type = "string"))), .env = .env)
  local_fake_provider(list(fake_tool("read", path = "R/a.R"), "All done \u2713", "branch answer"),
                      .env = .env)
  s = test_session(home = globalenv())
  run_text(s, "Refactor a.R")
  s
}

# The branch fixture of the reader tests S15-S17 of test-session-store.R (P06 Task 13), kept here
# for the same reason: it calls the harness helpers.

#' A stored session continued by a detached copy after its original is gone: the copy's turn 2
#' is a sibling of the original's turn 2 in the same file
branch_in_file = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_fake_provider(list("first", "second", "third"), .env = .env)
  s = test_session(home = globalenv())
  run_text(s, "one")
  snap = serialize(s, NULL)
  run_text(s, "two")
  main_leaf = session_data(s)$leaf
  file = s$file
  other = test_session()
  rm(s)
  invisible(gc())
  copy = unserialize(snap)
  run_text(copy, "two, rephrased")
  list(copy = copy, file = file, main_leaf = main_leaf, other = other)
}

run_text = function(s, text, opts = list()) session_run(s, msg_user(text), opts)
roles = function(s) vapply(s$messages, function(m) m$role, "")
tool_results = function(s) Filter(function(m) identical(m$role, "tool_result"), s$messages)
req_roles = function(req) vapply(req$messages, function(m) m$role, "")
num_schema = function(...) {
  props = lapply(list(...), function(type) list(type = type))
  list(type = "object", required = I(names(props)), properties = props)
}
