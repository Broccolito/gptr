# tests/testthat/test-subagent-worker.R -- worker children: the protocol of contract 11.11 on
# the child side, the parent's proxy adapter and the worker backend (plan P19).

# The worker's stdin as a processx pipe pair with a blocking read end, as fd 0 may be (the test
# writes, the worker reads), and its stdout as a text connection
local_worker_io = function(.env = parent.frame()) {
  pp = processx::conn_create_pipepair(nonblocking = c(FALSE, FALSE))
  tc = textConnection("out", "w", local = TRUE)
  io = worker_io_open(con = pp[[1L]], out = tc)
  withr::defer({
    try(close(pp[[1L]]), silent = TRUE)
    try(close(pp[[2L]]), silent = TRUE)
    try(close(tc), silent = TRUE)
  }, envir = .env)
  write = function(obj) processx::conn_write(pp[[2L]], paste0(json_encode(obj), "\n"))
  list(io = io, write = write, pp = pp,
       close_in = function() close(pp[[2L]]),
       sent = function() lapply(textConnectionValue(tc), json_decode))
}

test_that("a permission request goes to the parent and its answer comes back", {
  w = local_worker_io()
  w$write(list(type = "permission", id = "p1", decision = "allow"))
  ans = worker_ui_permission(w$io, list(tool = "r", input = list(code = "x = 1"),
                                        summary = "x = 1", reason = "level 1", turn = 1L,
                                        risk = structure(list(level = 1L), class = "gptr_risk")))
  expect_identical(ans$decision, "allow")
  sent = w$sent()
  expect_identical(sent[[1L]]$type, "permission_request")
  expect_identical(sent[[1L]]$id, "p1")
  expect_identical(sent[[1L]]$request$input$code, "x = 1")
  expect_null(sent[[1L]]$request$risk)
  w$write(list(type = "permission", id = "p2", decision = "deny", feedback = "no"))
  ans2 = worker_ui_permission(w$io, list(tool = "write", input = list(path = "a")))
  expect_identical(ans2$decision, "deny")
  expect_identical(ans2$feedback, "no")
})

test_that("questions, select and input are forwarded as ask lines", {
  w = local_worker_io()
  w$write(list(type = "answer", id = "q1", answers = list(choice = "B")))
  expect_identical(worker_ui_select(w$io, "Which?", c("A", "B")), 2L)
  w$write(list(type = "answer", id = "q2", answers = list(text = "hello")))
  expect_identical(worker_ui_input(w$io, "Say", ""), "hello")
  w$write(list(type = "answer", id = "q3", answers = list(a = "yes"), cancelled = FALSE))
  res = worker_ui_questions(w$io, list(list(id = "a", question = "ok?")))
  expect_identical(res$answers$a, "yes")
  expect_false(res$cancelled)
  sent = w$sent()
  expect_identical(vapply(sent, function(x) x$type, ""), c("ask", "ask", "ask"))
  expect_identical(sent[[1L]]$questions[[1L]]$options, list("A", "B"))
})

test_that("a reply that arrives early is kept until it is asked for", {
  w = local_worker_io()
  w$write(list(type = "answer", id = "q9", answers = list(x = "later")))
  w$write(list(type = "permission", id = "p1", decision = "allow"))
  expect_identical(worker_ui_permission(w$io, list(tool = "r", input = list()))$decision,
                   "allow")
  expect_length(w$io$stash, 1L)
})

test_that("cancel aborts a pending request and end of input cancels questions", {
  w = local_worker_io()
  w$write(list(type = "cancel"))
  ans = worker_ui_permission(w$io, list(tool = "write", input = list(path = "a")))
  expect_identical(ans$decision, "abort")
  expect_true(w$io$cancel)
  w$io$cancel = FALSE
  w$close_in()
  q = worker_ui_questions(w$io, list(list(id = "a", question = "x?")))
  expect_true(q$cancelled)
  expect_true(w$io$eof)
  expect_false(worker_ui_spec(w$io)$has_ui())
})

test_that("a partial line on a blocking stdin waits for its end without blocking", {
  w = local_worker_io()
  line = paste0(json_encode(list(type = "answer", id = "q1", answers = list(a = "x"))), "\n")
  processx::conn_write(w$pp[[2L]], substr(line, 1L, 10L))
  worker_io_poll(w$io, 100L)
  expect_length(w$io$stash, 0L)
  worker_io_poll(w$io, 0L)
  processx::conn_write(w$pp[[2L]], substring(line, 11L))
  worker_io_poll(w$io, 100L)
  expect_identical(w$io$stash[[1L]]$answers$a, "x")
  expect_false(w$io$eof)
})

test_that("the worker UI is a ui spec named worker", {
  w = local_worker_io()
  ui = worker_ui_spec(w$io)
  expect_s3_class(ui, "gptr_spec")
  expect_identical(ui$name, "worker")
  expect_true(ui$has_ui())
  expect_null(ui$notify("hi"))
})

test_that("exports are saved by name only on success", {
  d = withr::local_tempdir()
  e = new.env()
  e$fit = 1:3
  e$other = "x"
  path = file.path(d, "result.rds")
  expect_identical(worker_exports_save(c("fit", "missing"), e, path, "idle"), "fit")
  res = readRDS(path)
  expect_identical(res$status, "idle")
  expect_identical(res$exports, list(fit = 1:3))
  worker_exports_save("fit", e, path, "error")
  expect_identical(readRDS(path)$exports, list())
})

test_that("the registry of the parent is re-registered, a fake provider made again (IC-69)", {
  local_project()
  s = session_new("wfake/wfake-1", "auto", home = new.env())
  sid = session_data(s)$id
  tool = gptr_tool("hello", "Say hello", fun = function() "hi", exposure = "r",
                   namespace = "wdemo")
  fake = gptr_fake_provider(list("from the worker"), name = "wfake")
  ids = worker_registry_apply(list(specs = list(list(spec = tool, session = FALSE),
                                                list(spec = fake, session = TRUE)),
                                   plugins = NULL,
                                   filters = list(user = character(), project = character(),
                                                  session = character())), sid)
  withr::defer(for (id in ids) registry_remove(id))
  expect_length(ids, 2L)
  expect_s3_class(registry_get("tool", "wdemo/hello"), "gptr_tool")
  expect_null(registry_get("provider", "wfake"))
  pr = registry_get("provider", "wfake", session = sid)
  expect_s3_class(pr, "gptr_provider")
  expect_false(identical(pr$log, fake$log))
})

test_that("bare filters, as IC-69 writes them, count as session filters", {
  local_registry()
  worker_registry_apply(list(specs = list(), plugins = NULL, filters = "-builtin:wx"), "sid")
  expect_identical(registry_env()$filters$session, "-builtin:wx")
})

test_that("parent plugins are re-enabled by package name, else by path (IC-69)", {
  local_project()
  s = session_new("fake/fake-1", "auto", home = new.env())
  sid = session_data(s)$id
  # a directory plugin outside the project: plugin_resolve() finds it by its path, not its name
  d = withr::local_tempdir()
  dir.create(file.path(d, "skills", "wplug-skill"), recursive = TRUE)
  writeLines('{"name": "wplug"}', file.path(d, "plugin.json"))
  writeLines(c("---", "name: wplug-skill", "description: A skill of a directory plugin.",
               "---", "Body."), file.path(d, "skills", "wplug-skill", "SKILL.md"))
  withr::defer(plugin_forget(d))
  pl = data.frame(name = "wplug", kind = "directory", path = path_norm(d), rank = 3L,
                  session = NA_character_, stringsAsFactors = FALSE)
  worker_registry_apply(list(specs = list(), plugins = pl,
                             filters = list(user = character(), project = character(),
                                            session = character())), sid)
  expect_false(is.null(registry_get("skill", "wplug-skill")))
  expect_true(path_norm(d) %in% plugins_enabled()$path)
  expect_identical(worker_plugin_ref("package", "pkgplug", "/lib/pkgplug"), "pkgplug")
  expect_identical(worker_plugin_ref("directory", "wplug", "/x/wplug"), "/x/wplug")
  b = withr::local_tempdir()
  dir.create(file.path(b, ".claude-plugin"))
  expect_identical(worker_plugin_ref("claude-plugin", "deploy-tools", b), b)
  expect_identical(worker_plugin_ref("claude-plugin", "deploy-tools", file.path(b, "none")),
                   "deploy-tools")
})

test_that("the result line of a worker session carries status, text, usage and turns", {
  local_project()
  s = session_new("fake/fake-1", "auto", home = new.env())
  out = worker_outcome(s)
  expect_identical(out$status, "idle")
  expect_identical(out$text, "")
  expect_identical(out$turns, 0L)
  expect_identical(out$usage$input, 0)
})

test_that("worker_exit_now() refuses to quit outside a worker process", {
  withr::local_envvar(GPTR_WORKER = NA)
  expect_error(worker_exit_now(), class = "gptr_error_internal")
})

# ---- Task 8: the worker backend, its proxy adapter and real worker processes --------------------

# Test helpers shared with test-subagent-team.R (each test file defines its own, as 05 names no
# helper file for P19)
local_team_fake = function(script = function(request) paste("reply", request$n),
                           .env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(mode = "auto", model = "fake/fake-1", .env = .env)
  local_fake_provider(script, .env = .env)
}

team_call = function(prompt, agents = NULL, envir = new.env(), opts = list()) {
  call_new(prompt = prompt, template = prompt, envir = envir,
           ids = list(model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                      extensions = NULL, tools = NULL, agents = agents),
           args = list(parallel = NULL, background = FALSE, budget = NULL, replay = NULL,
                       opts = opts, run = TRUE, stdin = FALSE))
}

local_active = function(.env = parent.frame()) {
  box = new.env(parent = emptyenv())
  box$active = 0L
  box$peak = 0L
  ids = c(hook_add("subagent_start", function(event, ctx) {
    box$active = box$active + 1L
    box$peak = max(box$peak, box$active)
    NULL
  }), hook_add("subagent_end", function(event, ctx) {
    box$active = box$active - 1L
    NULL
  }))
  withr::defer(for (id in ids) hook_remove(id), envir = .env)
  box
}

# A fake script that a worker child can run: its environment is the base environment, so it is
# sent without the test's environment and uses base functions only (the test helpers
# fake_text() and fake_tool() do not exist in the child)
worker_script = function(fn) {
  environment(fn) = baseenv()
  fn
}

# The state of one worker request, as worker_stream() builds it, with a recording gate (the
# tests record the replies by mocking worker_reply())
stub_worker_state = function(gate = function(call) list(decision = "allow", reason = "ok")) {
  st = new.env(parent = emptyenv())
  st$provider = "fake"
  st$model_id = "fake-1"
  st$request_id = "q000000000001"
  st$stderr = character()
  st$opts = list(gate = gate, signal = new.env())
  st$replies = list()
  st
}

test_that("worker requests are re-classified by the parent's gate and answered (IC-53)", {
  seen = new.env()
  st = stub_worker_state(gate = function(call) {
    seen$call = call
    if (grepl("unlink", call$input$code, fixed = TRUE)) {
      list(decision = "deny", reason = "deletes files")
    } else if (grepl("rewrite", call$input$code, fixed = TRUE)) {
      list(decision = "allow", reason = "rewritten", input = list(code = "x = 2"))
    } else {
      list(decision = "allow", reason = "level 1")
    }
  })
  local_mocked_bindings(worker_reply = function(st, obj) {
    st$replies[[length(st$replies) + 1L]] = obj
    invisible(NULL)
  })
  worker_on_line(st, json_encode(list(type = "permission_request", id = "p1",
                                      request = list(tool = "r", input = list(code = "x = 1"),
                                                     summary = "harmless", tier = "ask"))))
  worker_on_line(st, json_encode(list(type = "permission_request", id = "p2",
                                      request = list(tool = "r",
                                                     input = list(code = "unlink('d')"),
                                                     summary = "looks harmless"))))
  expect_identical(seen$call$name, "r")
  expect_identical(seen$call$input$code, "unlink('d')")
  expect_s3_class(seen$call$tool, "gptr_tool")
  expect_identical(st$replies[[1L]], list(type = "permission", id = "p1", decision = "allow",
                                          feedback = NULL))
  expect_identical(st$replies[[2L]]$decision, "deny")
  expect_identical(st$replies[[2L]]$feedback, "deletes files")
  # an approval of a changed input is not one of the worker's call
  worker_on_line(st, json_encode(list(type = "permission_request", id = "p3",
                                      request = list(tool = "r", input = list(code = "rewrite")))))
  expect_identical(st$replies[[3L]]$decision, "deny")
  expect_match(st$replies[[3L]]$feedback, "changed this call", fixed = TRUE)
  # non-JSON lines and the jsonl events (its permission_request event has no request) are ignored
  worker_on_line(st, "not json")
  worker_on_line(st, json_encode(list(type = "permission_request", tool = "r",
                                      input = list(code = "q()"))))
  expect_length(st$replies, 3L)
  worker_on_line(st, json_encode(list(type = "result", status = "idle", text = "done",
                                      usage = list(input = 10, output = 2), turns = 1L)))
  expect_identical(st$result$text, "done")
})

test_that("questions from a worker without a human are answered as cancelled", {
  st = stub_worker_state()
  local_mocked_bindings(worker_reply = function(st, obj) {
    st$replies[[length(st$replies) + 1L]] = obj
    invisible(NULL)
  })
  local_gptr_options(interactive = FALSE)
  worker_on_line(st, json_encode(list(type = "ask", id = "q1",
                                      questions = list(list(id = "a", question = "x?")))))
  expect_identical(st$replies[[1L]]$type, "answer")
  expect_true(st$replies[[1L]]$cancelled)
})

test_that("a finished worker ends the request with its text and imports its exports", {
  st = stub_worker_state()
  st$home = new.env()
  dir = withr::local_tempdir()
  st$dir = dir
  st$result_path = file.path(dir, "result.rds")
  save_rds(list(status = "idle", exports = list(m = 3.5)), st$result_path)
  st$result = list(type = "result", status = "idle", text = "mean is 3.5",
                   usage = list(input = 100, output = 20, cost = 0.01), turns = 1L)
  worker_on_exit(st, 0L)
  expect_identical(st$home$m, 3.5)
  types = vapply(st$final, function(ev) ev$type, "")
  expect_identical(types, c("text_start", "text_delta", "text_end", "done"))
  msg = st$final[[4L]]$message
  expect_identical(msg_text(msg), "mean is 3.5")
  expect_identical(msg$provider, "fake")
  expect_identical(msg$usage$input, 100)
  expect_identical(msg$usage$cost$total, 0.01)
  expect_false(dir.exists(dir))
  expect_null(st$dir)
})

test_that("a worker that dies without a result ends the request with an error", {
  st = stub_worker_state()
  st$result_path = tempfile()
  st$stderr = "Error: cannot allocate vector of size 500.0 Mb"
  worker_on_exit(st, 1L)
  ev = st$final[[1L]]
  expect_identical(ev$type, "error")
  expect_match(ev$message$error_message, "exited (status 1) without a result: Error: cannot",
               fixed = TRUE)
  expect_identical(ev$error$class, "process")
  # never retried: a retry would run the agent again (its stderr matches P06's transient texts)
  expect_false(run_retryable(ev$message, ev$error))
})

test_that("a stopped worker ends its open request as aborted, never error (IC-60)", {
  st = stub_worker_state()
  local_mocked_bindings(kill_all = function(p, grace = 2) invisible(NULL))
  worker_kill(st)
  ev = st$final[[1L]]
  expect_identical(c(ev$reason, ev$message$stop_reason, ev$error$class), rep("aborted", 3L))
})

test_that("the user's abort of a forwarded request aborts the proxy run", {
  local_team_fake(list("never"))
  local_scripted_ui(list("abort"))
  local_mocked_bindings(worker_spawn = function(st) {
    worker_on_line(st, json_encode(list(type = "permission_request", id = "p1",
                                        request = list(tool = "r",
                                                       input = list(code = "unlink('d')")))))
    invisible(st)
  })
  parent = session_new("fake/fake-1", "auto", home = new.env(), kind = "team")
  h = subagent_start(list(agent = gptr_agent("w", description = "worker", model = "fake/fake-1",
                                             backend = "worker"),
                          prompt = "go", mode = "manual", parent = parent, base = new.env()),
                     NULL)
  expect_true(run_wait(list(h$run), timeout = 10))
  expect_identical(h$session$status, "aborted")
})

test_that("a proxy session without a worker spec fails its request", {
  gen = worker_stream(list(api = "subagent-worker"), list(messages = list()),
                      list(state = new.env(), signal = new.env()))
  step = gen()
  types = vapply(step$events, function(ev) ev$type, "")
  expect_identical(types, c("start", "error"))
  expect_null(gen())
})

test_that("specs that cannot be serialised are found; others are not (IC-69)", {
  expect_false(worker_unserialisable(list(a = 1, f = function(x) x + 1)))
  con = file(tempfile(), "w")
  withr::defer(close(con))
  holder = local({
    k = con
    function() k
  })
  expect_true(worker_unserialisable(holder))
  expect_true(worker_unserialisable(list(x = list(y = con))))
  expect_true(worker_unserialisable(structure(list2env(list(k = con)), class = "foo")))
  expect_false(worker_unserialisable(peter))
})

test_that("a registry is a reference: a closure reaching it ships none of its records (IC-69)", {
  local_registry()
  con = file(tempfile(), "w")
  withr::defer(close(con))
  # another extension keeps a connection in its state, inside the registry
  ext_load(local(function(gptr) gptr$state$con = con,
                 envir = list2env(list(con = con), parent = globalenv())),
           source = "user", rank = 3L)
  off = gptr_register(gptr_command("w-cmd", function(args, ctx) "ok"))
  expect_false(worker_unserialisable(off))
  f = withr::local_tempfile(fileext = ".rds")
  save_rds(off, f, refhook = worker_refhook)
  expect_identical(environment(readRDS(f, refhook = worker_refhook))$reg, emptyenv())
})

test_that("a lazily loaded source file is a reference, a user's ships its lines (IC-69, IC-70)", {
  # closures of baseenv(): the source of this file, which they would reach, holds the marker
  fun = eval(parse(text = "function() 'ok'", keep.source = TRUE), baseenv())
  user = eval(parse(text = "function(x) {\n  x + 1\n}", keep.source = TRUE), baseenv())
  # a package installed with its source keeps `lines` as a lazy-load promise whose environment
  # reaches every environment of the package, the secret vault included
  delayedAssign("lines", k, eval.env = list2env(list(k = "p19-held-by-the-promise")),
                assign.env = attr(attr(fun, "srcref"), "srcfile"))
  f = withr::local_tempfile(fileext = ".rds")
  save_rds(list(fun = fun, user = user), f, refhook = worker_refhook)
  expect_length(grepRaw("p19-held-by-the-promise", readBin(f, "raw", file.size(f)), fixed = TRUE),
                0L)
  back = readRDS(f, refhook = worker_refhook)
  expect_identical(back$fun(), "ok")
  expect_match(gptr_describe(back$user), "x + 1", fixed = TRUE, all = FALSE)
})

test_that("worker_main() goes to callr without its source references (IC-70)", {
  fun = NULL
  local_mocked_bindings(r_bg = function(func, ...) {
    fun <<- func
    stop("not started")
  }, .package = "callr")
  st = new.env()
  st$spec = list(depth = 1L, settings = list(project_root = tempdir()))
  st$home = new.env()
  withr::defer(unlink(st$dir, recursive = TRUE))
  expect_error(worker_spawn(st), "not started")
  # callr drops a function's srcref but keeps the source files of its body, as above a promise
  expect_length(grepRaw("srcfile", serialize(fun, NULL), fixed = TRUE), 0L)
})

test_that("objects are shipped by name from the caller's environment", {
  e = new.env()
  e$d = 1:3
  expect_identical(worker_ship_objects("d", e), list(d = 1:3))
  expect_error(worker_ship_objects("nope", e), class = "gptr_error_invalid_argument")
})

test_that("only remote providers registered for the process pass their key to a worker", {
  local_fake_provider(list("x"))
  expect_null(worker_key_provider("fake/fake-1"))
  expect_null(worker_key_provider("nosuch/model"))
})

test_that("the worker registry ships the filters of each scope by name (IC-69)", {
  reg = worker_registry(character())
  expect_named(reg$filters, c("user", "project", "session"))
})

test_that("an explicit worker for a remote model is refused in replay mode before it starts", {
  local_project()
  local_gptr_options(mode = "auto", replay = "replay")
  off = gptr_register(gptr_provider("wremote", api = "openai-completions",
                                    base_url = "https://llm.example.test/v1",
                                    models = list(list(id = "m1"))))
  withr::defer(off())
  parent = session_new("wremote/m1", "auto", home = new.env(), kind = "team")
  agent = gptr_agent("w", description = "worker", model = "wremote/m1", backend = "worker")
  expect_error(subagent_start(list(agent = agent, prompt = "x", parent = parent,
                                   base = new.env(), opts = list(context = "none")), NULL),
               class = "gptr_error_not_recorded")
})

# ---- real worker processes (skipped on CRAN; gptr must be installed for callr children) ------

# Worker children load gptr with library(): under R CMD check the installed package is on the
# library path; from a source tree (devtools::test()) the tree is installed once per R session
# into a temporary library that is put first on .libPaths() (never the user library)
local_worker_lib = function(.env = parent.frame()) {
  testthat::skip_on_cran()
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (!file.exists(file.path(path, "R", "aaa-state.R"))) return(invisible(NULL))
  lib = file.path(tempdir(), "gptr-worker-lib")
  if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
    dir.create(lib, showWarnings = FALSE, recursive = TRUE)
    cmd = sprintf(paste0("install.packages('%s', lib = '%s', repos = NULL, type = 'source', ",
                         "INSTALL_opts = c('--no-docs', '--no-multiarch', '--no-test-load'))"),
                  normalizePath(path, winslash = "/"), normalizePath(lib, winslash = "/"))
    res = processx::run(rscript_path(), c("--vanilla", "-e", cmd), error_on_status = FALSE,
                        timeout = 600)
    if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
      testthat::skip(paste("could not install gptr for worker children:", res$stderr))
    }
  }
  withr::local_libpaths(lib, action = "prefix", .local_envir = .env)
  invisible(lib)
}

# A worker child of a team-like parent; the fake is registered for the process, so the worker
# receives it with the user's registry records
start_worker = function(parent, prompt, base = new.env(), ...) {
  subagent_start(list(agent = gptr_agent("w", description = "worker", model = "fake/fake-1",
                                         backend = "worker", ...),
                      prompt = prompt, parent = parent, base = base), NULL)
}

worker_pids = function() {
  jobs = gptr_jobs()
  jobs$pid[jobs$kind == "worker"]
}

test_that("a worker child answers through its proxy session and returns its exports", {
  local_worker_lib()
  local_team_fake(worker_script(function(request) {
    if (length(request$last_results)) "the mean is 2" else
      list(tool = "r", input = list(code = "m = mean(d)"))
  }))
  parent = session_new("fake/fake-1", "auto", home = new.env(), kind = "team")
  e = new.env()
  e$d = c(1, 2, 3)
  h = start_worker(parent, "average d", base = e, objects = "d", export = "m")
  expect_true(run_wait(list(h$run), timeout = 120))
  d = session_data(h$session)
  expect_identical(d$status, "idle")
  expect_identical(d$backend, "worker")
  expect_identical(d$model, "worker/worker")
  expect_identical(h$session$text, "the mean is 2")
  expect_identical(subagent_export(h, e), "m")
  expect_identical(e$m, 2)
  expect_length(worker_pids(), 0L)
})

test_that("a plugin r member and a fake provider spec work inside a worker (IC-69)", {
  local_worker_lib()
  local_project()
  local_gptr_options(mode = "auto")
  member = gptr_tool("hello", "Say hello", exposure = "r", namespace = "wdemo",
                     fun = local(function() "hello from the parent",
                                 envir = new.env(parent = globalenv())))
  off = gptr_register(member)
  withr::defer(off())
  fake = gptr_fake_provider(worker_script(function(request) {
    if (length(request$last_results)) "said it" else
      list(tool = "r", input = list(code = "v = peter$wdemo$hello()"))
  }), name = "wspec")
  parent = session_new("fake/fake-1", "auto", home = new.env(), kind = "team")
  e = new.env()
  h = subagent_start(list(agent = gptr_agent("w", description = "worker", backend = "worker",
                                             export = "v"),
                          model = fake, prompt = "say hello", parent = parent, base = e), NULL)
  expect_true(run_wait(list(h$run), timeout = 120))
  expect_identical(h$session$text, "said it")
  subagent_export(h, e)
  expect_identical(e$v, "hello from the parent")
})

# The variable's name is not secret-like, so the secret guard does not stop the read: the test
# is about R reading ~/.Renviron at start-up, which child_env() prevents (IC-60)
test_that("a worker never sees a key from ~/.Renviron (P19 acceptance 5)", {
  local_worker_lib()
  local_team_fake(worker_script(function(request) {
    if (length(request$last_results)) "ok" else
      list(tool = "r", input = list(code = "k = Sys.getenv('GPTR_TEST_RENVIRON')"))
  }))
  home = withr::local_tempdir()
  writeLines("GPTR_TEST_RENVIRON=sk-ant-api03-fakefakefakefakefakefake",
             file.path(home, ".Renviron"))
  withr::local_envvar(HOME = home, GPTR_TEST_RENVIRON = NA)
  parent = session_new("fake/fake-1", "auto", home = new.env(), kind = "team")
  e = new.env()
  h = start_worker(parent, "read the key", base = e, export = "k")
  run_wait(list(h$run), timeout = 120)
  subagent_export(h, e)
  expect_identical(e$k, "")
})

test_that("at most 2 workers run under R CMD check (IC-60)", {
  local_worker_lib()
  local_team_fake(list(fake_text("done", delay = 1)))
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  local_gptr_options(subagents.max_workers = 4L)
  box = local_active()
  agents = lapply(c("a", "b", "c"), function(nm) {
    gptr_agent(nm, description = nm, model = "fake/fake-1", backend = "worker")
  })
  names(agents) = c("a", "b", "c")
  team = route_team_run(team_call("work", agents = agents))
  expect_identical(box$peak, 2L)
  expect_identical(unname(vapply(team$children, function(s) s$status, "")), rep("idle", 3L))
})

test_that("gptr_cancel() of a worker child leaves no process (P19 acceptance 5)", {
  local_worker_lib()
  local_team_fake(list(list(hang = TRUE)))
  parent = session_new("fake/fake-1", "auto", home = new.env(), kind = "team")
  h = start_worker(parent, "hang")
  reactor_pump(until = function() length(worker_pids()) > 0L, timeout = 60)
  pid = worker_pids()
  expect_length(pid, 1L)
  # a handle, unlike a pid, outlives its process
  ph = ps::ps_handle(as.integer(pid))
  gptr_cancel(h$session)
  reactor_pump(until = function() !ps::ps_is_running(ph), timeout = 30)
  expect_false(ps::ps_is_running(ph))
  expect_identical(h$session$status, "aborted")
  expect_length(worker_pids(), 0L)
})

test_that("a worker exits within 10 s when its parent is killed (IC-60)", {
  local_worker_lib()
  skip_on_os("windows")
  root = local_project()
  script = file.path(root, "parent.R")
  writeLines(c(
    tracemem_loader(),
    "options(gptr.supervise = FALSE, gptr.mode = 'auto', gptr.quiet = TRUE)",
    "fake = gptr_fake_provider(list(list(hang = TRUE)))",
    "invisible(gptr_register(fake))",
    "a = gptr::gptr_agent('w', description = 'w', model = 'fake/fake-1', backend = 'worker')",
    "parent = gptr:::session_new('fake/fake-1', 'auto', home = new.env(), kind = 'team')",
    paste("h = gptr:::subagent_start(list(agent = a, prompt = 'hang', parent = parent,",
          "base = new.env()), NULL)"),
    "jobs = function() { j = gptr::gptr_jobs(); j$pid[j$kind == 'worker'] }",
    "gptr:::reactor_pump(until = function() length(jobs()) > 0L, timeout = 60)",
    "cat('WORKER', jobs(), '\\n')",
    "gptr:::reactor_pump(timeout = 300)"), script)
  libs = paste(.libPaths(), collapse = .Platform$path.sep)
  p = processx::process$new(rscript_path(), c("--vanilla", script), wd = root, stdout = "|",
                            stderr = "|", env = c("current", R_LIBS = libs))
  withr::defer(if (p$is_alive()) p$kill())
  out = ""
  deadline = Sys.time() + 120
  while (!grepl("WORKER [0-9]+", out) && Sys.time() < deadline && p$is_alive()) {
    p$poll_io(1000L)
    out = paste0(out, p$read_output())
  }
  pid = suppressWarnings(as.integer(sub(".*WORKER ([0-9]+).*", "\\1", out)))
  expect_false(is.na(pid))
  ph = ps::ps_handle(pid)
  p$kill()
  gone = Sys.time() + 10
  while (ps::ps_is_running(ph) && Sys.time() < gone) Sys.sleep(0.2)
  expect_false(ps::ps_is_running(ph))
})

test_that("builtin:subagents registers the worker backend, its provider and its adapter", {
  be = registry_get("backend", "worker")
  expect_s3_class(be, "gptr_backend")
  expect_identical(be$capabilities$parallel, "cpu")
  pr = registry_get("provider", "worker")
  expect_true(isTRUE(pr$offline) && isTRUE(pr$local))
  expect_identical(registry_get("adapter", "subagent-worker")$transport, "inprocess")
})
