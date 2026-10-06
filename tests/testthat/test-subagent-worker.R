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
