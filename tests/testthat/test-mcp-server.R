# A finished session (fake provider) whose home is a fresh environment with mtcars as `d`
local_served_session = function(mode = "auto", .env = parent.frame()) {
  fake = local_fake_provider(list("ok"), .env = .env)
  e = new.env()
  e$d = mtcars
  s = peter("hello", model = fake, envir = e, mode = mode)
  list(session = s, envir = e)
}

r_call = function(code, id = 1L, modern = TRUE) {
  mcp_test_msg("tools/call", list(name = "r", arguments = list(code = code)), id = id,
               modern = modern)
}

test_that("the dispatcher answers both eras and never throws", {
  x = local_served_session()
  s = x$session
  init = mcp_dispatch_local(mcp_test_msg("initialize", list(protocolVersion = "2025-06-18"),
                                         modern = FALSE), s)
  expect_identical(init$result$protocolVersion, "2025-06-18")
  expect_identical(init$result$serverInfo$name, "gptr")
  disc = mcp_dispatch_local(mcp_test_msg("server/discover"), s)$result
  expect_identical(as.character(unlist(disc$supportedVersions)), "2026-07-28")
  expect_identical(disc$resultType, "complete")
  expect_identical(disc[["_meta"]][["io.modelcontextprotocol/serverInfo"]]$name, "gptr")
  tl = mcp_dispatch_local(mcp_test_msg("tools/list"), s)$result
  expect_identical(vapply(tl$tools, `[[`, "", "name"), c("read", "r", "edit", "write"))
  expect_identical(tl$cacheScope, "private")
  # adapters hold session ids (contract 8.1): the id of a session builtin:mcp saw start works too
  by_id = mcp_dispatch_local(mcp_test_msg("tools/list"), session_data(s)$id)$result
  expect_identical(vapply(by_id$tools, `[[`, "", "name"), c("read", "r", "edit", "write"))
  expect_identical(mcp_dispatch_local(mcp_test_msg("tools/list"), "nobody")$error$code, -32603L)
  expect_identical(mcp_dispatch_local(list(jsonrpc = "2.0", method = "notifications/initialized"),
                                      s)$result, json_obj())
  expect_identical(mcp_dispatch_local(mcp_test_msg("prompts/list"), s)$error$code, -32601L)
  bad = mcp_test_msg("tools/call", list(name = "bash", arguments = json_obj()))
  expect_identical(mcp_dispatch_local(bad, s)$error$code, -32602L)
  old = mcp_test_msg("tools/list")
  old$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]] = "1900-01-01"
  err = mcp_dispatch_local(old, s)$error
  expect_identical(err$code, -32022L)
  expect_identical(as.character(unlist(err$data$supported)), "2026-07-28")
  invalid = mcp_dispatch_local(mcp_test_msg("tools/call", list(name = "r", arguments = list())), s)
  expect_true(invalid$result$isError)
  expect_match(invalid$result$content[[1L]]$text, "Invalid arguments for r", fixed = TRUE)
})

test_that("a served r call evaluates in the session's environment with its mode (idle gate)", {
  x = local_served_session("auto")
  res = mcp_dispatch_local(r_call("a = 1\nnrow(d)"), x$session)$result
  expect_false(res$isError)
  expect_match(res$content[[1L]]$text, "32", fixed = TRUE)
  expect_identical(x$envir$a, 1)
  y = local_served_session("manual")
  res = mcp_dispatch_local(r_call("a = 2", modern = FALSE), y$session)$result
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "Permission denied", fixed = TRUE)
  expect_match(res$content[[1L]]$text, "gptr_permissions(allow", fixed = TRUE)
  expect_false(exists("a", envir = y$envir, inherits = FALSE))
  rd = mcp_dispatch_local(mcp_test_msg("tools/call", list(name = "read",
                                                          arguments = list(path = "nope.txt"))),
                          y$session)$result
  expect_true(rd$isError)
})

test_that("objects made through peter() and a served r call capture the session home (D-189)", {
  fake = local_fake_provider(list(fake_tool("r", code = "f = y ~ x"), fake_text("ok")))
  e = new.env()
  s = peter("make f", model = fake, envir = e, mode = "auto")
  expect_identical(environment(e$f), e)
  res = mcp_dispatch_local(r_call("g = y ~ x\nh = function() 1"), s)$result
  expect_false(res$isError)
  expect_identical(environment(e$g), e)
  expect_identical(environment(e$h), e)
})

test_that("the CLI routes are served the session's frozen tool array (IC-79)", {
  rows = gptr_tool("nrow_of", "Rows of a data frame in the session.",
                   parameters = list(type = "object", required = I("name"),
                                     properties = list(name = list(type = "string"))),
                   execute = function(input, ctx) {
                     gptr_tool_result(paste("rows:", nrow(get(input$name, envir = ctx$envir))))
                   })
  names_of = function(s) {
    vapply(mcp_dispatch_local(mcp_test_msg("tools/list"), s)$result$tools, `[[`, "", "name")
  }
  fake = local_fake_provider(list("ok", "ok", "ok"))
  e = new.env()
  e$d = mtcars
  # a session-scoped (rank-0) direct tool and the extended preset, as an API provider gets them
  s = peter("hello", model = fake, envir = e, mode = "auto", tools = list(rows),
            .opts = list(preset = "extended"))
  frozen = session_data(s)$frozen
  expect_true(all(c("grep", "find", "ls", "nrow_of") %in% frozen$tool_names))
  expect_identical(names_of(s), frozen$tool_names)
  served = mcp_dispatch_local(mcp_test_msg("tools/list"), s)$result$tools
  expect_identical(served[[match("r", names_of(s))]]$inputSchema, mcp_r_schema)
  call = function(args) {
    mcp_dispatch_local(mcp_test_msg("tools/call", list(name = "nrow_of", arguments = args)),
                       s)$result
  }
  expect_match(call(list(name = "d"))$content[[1L]]$text, "rows: 32", fixed = TRUE)
  bad = call(json_obj())
  expect_true(bad$isError)
  expect_match(bad$content[[1L]]$text, "Invalid arguments for nrow_of", fixed = TRUE)
  # the readonly preset declares neither edit nor write, so neither is served
  ro = peter("hello", model = fake, envir = new.env(), mode = "auto", tools = "readonly")
  expect_false(any(c("edit", "write") %in% names_of(ro)))
  wr = mcp_test_msg("tools/call", list(name = "write", arguments = list(path = "x", content = "")))
  expect_identical(mcp_dispatch_local(wr, ro)$error$code, -32602L)
  expect_false(file.exists("x"))
})

test_that("a served call inside a run passes the run's tool_call hooks (IC-79)", {
  probe = gptr_tool("hookprobe", "Calls the MCP dispatcher the way the CLI adapters do.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    execute = function(input, ctx) {
                      res = mcp_dispatch_local(r_call(input$code), ctx$session)$result
                      paste(isTRUE(res$isError), res$content[[1L]]$text)
                    })
  off = gptr_register(probe)
  withr::defer(off())
  hook = gptr_register(gptr_hook("tool_call", function(event, ctx) {
    if (identical(event$tool_name, "r")) list(decision = "block", reason = "served r is held")
  }))
  withr::defer(hook())
  fake = local_fake_provider(list(fake_tool("hookprobe", code = "b = 2"), "done"),
                             name = "hookfake")
  e = new.env()
  peter("Use the probe", model = fake, envir = e, mode = "auto")
  out = fake_requests(fake)[[2L]]$last_results[[1L]]$content[[1L]]$text
  expect_match(out, "^TRUE Tool execution was blocked: served r is held")
  expect_false(exists("b", envir = e, inherits = FALSE))
})

# Serve calls from the first before_request of a run: a live run with no tool on the stack, as
# the CLI routes serve them (D-192). `serve(event, ctx)` runs once; the run's tool events are kept.
serve_in_run = function(serve, .env = parent.frame()) {
  seen = new.env()
  seen$events = list()
  seen$done = FALSE
  keep = function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  }
  offs = list(
    gptr_register(gptr_hook("before_request", function(event, ctx) {
      if (!seen$done) seen$out = serve(event, ctx)
      seen$done = TRUE
      NULL
    })),
    gptr_register(gptr_hook("tool_execution_start", keep)),
    gptr_register(gptr_hook("tool_execution_end", keep)))
  withr::defer(for (off in offs) off(), envir = .env)
  seen$envir = new.env()
  peter("hello", model = local_fake_provider(list("ok"), .env = .env), envir = seen$envir,
        mode = "auto")
  seen
}

test_that("a call served in a live run is reported as a tool call of the run (D-192)", {
  seen = serve_in_run(function(event, ctx) {
    mcp_dispatch_local(r_call("stop('no answer')", id = 4L), ctx$session)
    mcp_dispatch_local(r_call("answer = 21 * 2", id = 5L), ctx$session)$result
  })
  expect_false(seen$out$isError)
  expect_identical(seen$envir$answer, 42)
  ev = Filter(function(e) identical(e$tool_call_id, "mcp_5"), seen$events)
  expect_identical(vapply(ev, function(e) e$type, ""),
                   c("tool_execution_start", "tool_execution_end"))
  expect_identical(ev[[1L]]$input$code, "answer = 21 * 2")
  expect_false(ev[[2L]]$is_error)
  expect_identical(ev[[2L]]$details$objects$added, "answer")
  expect_identical(ev[[2L]]$content[[1L]]$type, "text")
  expect_true(is.numeric(ev[[2L]]$elapsed))
  failed = Filter(function(e) identical(e$tool_call_id, "mcp_4"), seen$events)[[2L]]
  expect_true(failed$is_error)
  expect_identical(failed$details$error, "no answer")
})

test_that("the end of a served call that was refused says why it did not run (console-3)", {
  local_permission_rules()
  gptr_permissions(deny = "r(fn:writeLines)")
  seen = serve_in_run(function(event, ctx) {
    mcp_dispatch_local(r_call("writeLines('x', 'y.txt')", id = 6L), ctx$session)$result
  })
  expect_true(seen$out$isError)
  end = Filter(function(e) identical(e$tool_call_id, "mcp_6"), seen$events)[[2L]]
  expect_true(end$is_error)
  expect_identical(end$refused, "denied by the rule r(fn:writeLines)")
})

test_that("code served in a live run shows what it prints, as the r tool does (Task 31)", {
  shown = utils::capture.output(serve_in_run(function(event, ctx) {
    withr::local_options(gptr.interactive = TRUE)
    mcp_dispatch_local(r_call("cat('served output\\n')"), ctx$session)$result
  }))
  expect_length(grep("served output", shown, fixed = TRUE), 1L)
  x = local_served_session()
  withr::local_options(gptr.interactive = TRUE)
  shown = utils::capture.output(invisible(mcp_dispatch_local(r_call("cat('no run\\n')"),
                                                              x$session)))
  expect_length(grep("no run", shown, fixed = TRUE), 0L)
})

test_that("a plot served in a live run is drawn on the person's device, without a run on none", {
  shown = new.env()
  shown$n = 0L
  screen = function(...) {
    shown$n = shown$n + 1L
    grDevices::pdf(NULL)
  }
  devs = grDevices::dev.list()
  withr::defer(for (d in setdiff(grDevices::dev.list(), devs)) grDevices::dev.off(d))
  images = function(res) Filter(function(b) identical(b$type, "image"), res$content)
  seen = serve_in_run(function(event, ctx) {
    withr::local_options(gptr.interactive = TRUE, device = screen)
    mcp_dispatch_local(r_call("plot(1:3)"), ctx$session)$result
  })
  expect_false(seen$out$isError)
  expect_length(images(seen$out), 1L)
  expect_identical(shown$n, 1L)
  drawn = setdiff(grDevices::dev.list(), devs)
  expect_length(drawn, 1L)
  grDevices::dev.off(drawn)
  x = local_served_session()
  withr::local_options(gptr.interactive = TRUE, device = screen)
  res = mcp_dispatch_local(r_call("plot(1:3)"), x$session)$result
  expect_length(images(res), 1L)
  expect_identical(shown$n, 1L)
  expect_identical(grDevices::dev.list(), devs)
})

test_that("a call served to a CLI route is checkpointed; each change is undone once (#24)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
  seen = new.env()
  off = gptr_register(gptr_hook("before_request", function(event, ctx) {
    if (is.null(seen$out)) {
      # the child's own edit, then its served call
      writeLines("a = 2", file.path(proj, "R", "a.R"))
      code = "zz_obj = 1:5; a1 = 100; writeLines('b', 'b.txt')"
      seen$out = mcp_dispatch_local(r_call(code), ctx$session)$result
    }
    NULL
  }))
  withr::defer(off())
  e = new.env()
  e$a1 = 1
  s = peter("hello", model = local_fake_provider(list("ok")), envir = e, mode = "auto")
  expect_false(seen$out$isError)
  expect_identical(e$a1, 100)
  cp = gptr_checkpoints(s)
  expect_identical(c(cp$objects, cp$files), c("2/2", "2/2"))
  gptr_rewind(s, 0)
  expect_false(exists("zz_obj", envir = e, inherits = FALSE))
  expect_identical(e$a1, 1)
  expect_false(file.exists(file.path(proj, "b.txt")))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
})

test_that("IC-53 covers a call served to a CLI route: control guard and one-shot grants (D-192)", {
  guarded = gptr_tool("guarded", "Reaches a control export the way model code can.",
                      parameters = list(type = "object", properties = json_obj()),
                      annotations = list(read_only = TRUE),
                      execute = function(input, ctx) {
                        tryCatch({
                          ext_control_guard("gptr_register")
                          "passed"
                        }, gptr_error_permission = function(e) "refused")
                      })
  off = gptr_register(guarded)
  withr::defer(off())
  seen = serve_in_run(function(event, ctx) {
    call = function(id) {
      msg = mcp_test_msg("tools/call", list(name = "guarded", arguments = json_obj()), id = id)
      mcp_dispatch_local(msg, ctx$session)$result$content[[1L]]$text
    }
    run = session_live(ctx$session)$run
    out = call(1L)
    ext_control_grant(event$run, "gptr_register")
    out = c(out, call(2L), call(3L))
    ext_control_grant(event$run, "gptr_register")
    run$signal$control = "gptr_fork"
    mcp_dispatch_local(r_call("1 + 1", id = 4L), ctx$session)
    c(out, call(5L), length(run$signal$control))
  })
  expect_identical(seen$out, c("refused", "passed", "refused", "refused", "0"))
})

test_that("a nested run's served calls are its tool calls; a yolo control export runs (D-192)", {
  skip_on_cran()
  seen = new.env()
  seen$events = list()
  keep = function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  }
  # the child pumps inside the parent's r tool, as a CLI sub-agent or a nested CLI peter() does
  offs = list(
    gptr_register(gptr_hook("before_request", function(event, ctx) {
      if (!is.null(run_current()) && is.null(seen$kid)) {
        seen$kid = event$run
        code = paste0("kid_answer = 6 * 7; off_hook = gptr_register(gptr_hook('agent_end', ",
                      "function(event, ctx) NULL)); 'registered'")
        seen$out = mcp_dispatch_local(r_call(code, id = 9L), ctx$session)$result
      }
      NULL
    })),
    gptr_register(gptr_hook("tool_execution_start", keep)),
    gptr_register(gptr_hook("tool_execution_end", keep)))
  withr::defer(for (off in offs) off())
  local_fake_provider(list("kid ok"), name = "kid")
  outer = local_fake_provider(list(fake_tool("r", code = paste0(
    "k = peter('Help.', model = 'kid', envir = w, mode = 'yolo')")), "done"), name = "outer")
  e = new.env()
  e$w = new.env()
  withr::defer(if (is.function(e$w$off_hook)) e$w$off_hook())
  peter("go", model = outer, envir = e, mode = "yolo")
  expect_identical(e$w$kid_answer, 42)
  expect_match(seen$out$content[[1L]]$text, "registered", fixed = TRUE)
  expect_false(seen$out$isError)
  ev = Filter(function(x) identical(x$tool_call_id, "mcp_9"), seen$events)
  expect_identical(vapply(ev, function(x) x$type, ""),
                   c("tool_execution_start", "tool_execution_end"))
  expect_identical(ev[[1L]]$run, seen$kid)
})

test_that("a served tool runs as the loop runs it: frame, source and its state (IC-79)", {
  counter = gptr_tool("counter", "Counts.",
                      parameters = list(type = "object", properties = json_obj()),
                      annotations = list(read_only = TRUE),
                      execute = function(input, ctx) {
                        st = ctx$state()
                        st$n = (st$n %||% 0) + 1
                        paste0("n=", st$n, " src=", toString(ctx_source(ctx)),
                               " run=", !is.null(run_current()))
                      })
  seen = new.env()
  off = gptr_register(gptr_hook("before_request", function(event, ctx) {
    if (is.null(seen$out)) {
      msg = mcp_test_msg("tools/call", list(name = "counter", arguments = json_obj()), id = 7L)
      seen$out = mcp_dispatch_local(msg, ctx$session)$result$content[[1L]]$text
    }
    NULL
  }))
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("counter"), "ok"), name = "counting")
  peter("hello", model = fake, envir = new.env(), mode = "auto", tools = list(counter))
  expect_identical(seen$out, "n=1 src=session run=TRUE")
  expect_identical(fake_requests(fake)[[2L]]$last_results[[1L]]$content[[1L]]$text,
                   "n=2 src=session run=TRUE")
})

test_that("a fork's served calls evaluate in its overlay; a plan-mode parent stays in plan", {
  x = local_served_session("auto")
  f = gptr_fork(x$session)
  res = mcp_dispatch_local(r_call("y_child = 42"), f)$result
  expect_false(res$isError)
  expect_identical(get("y_child", envir = session_home(f), inherits = FALSE), 42)
  expect_false(exists("y_child", envir = x$envir, inherits = FALSE))
  # at an idle console a plan-mode session has no run, hence no scratch overlay (IC-15): P11's
  # plan policy refuses every r call then
  p = local_served_session("plan")
  for (code in c("saveRDS(d, 'd.rds')", "nrow(d)")) {
    res = mcp_dispatch_local(r_call(code), session_data(p$session)$id)$result
    expect_true(res$isError)
    expect_match(res$content[[1L]]$text, "plan mode", fixed = TRUE)
  }
  expect_false(file.exists("d.rds"))
})

test_that("a served call asks a person only while a pump runs (IC-57)", {
  seen = new.env()
  seen$perm = 0L
  local_mocked_bindings(
    perm_check = function(call, run) {
      seen$perm = seen$perm + 1L
      list(decision = "allow", reason = "")
    },
    mcp_gate_idle = function(call, ctx, sid = NULL) list(decision = "deny", reason = "idle"))
  run = structure(new.env(), class = "gptr_run")
  local_mocked_bindings(reactor_depth = function() 0L)
  expect_identical(mcp_serve_gate(list(name = "r"), run, NULL, "s1")$decision, "deny")
  expect_identical(mcp_serve_gate(list(name = "r"), NULL, NULL, "s1")$decision, "deny")
  local_mocked_bindings(reactor_depth = function() 1L)
  expect_identical(mcp_serve_gate(list(name = "r"), run, NULL, "s1")$decision, "allow")
  expect_identical(seen$perm, 1L)
})

test_that("inside a running session the claude route gates through perm_check once", {
  probe = gptr_tool("probe", "Calls the MCP dispatcher the way the claude adapter does.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    execute = function(input, ctx) {
                      res = mcp_dispatch_local(r_call(input$code), ctx$session)
                      json_encode(res$result$isError)
                    })
  off = gptr_register(probe)
  withr::defer(off())
  ui = local_scripted_ui(list("y", "n", "y", "y"))
  fake = local_fake_provider(list(fake_tool("probe", code = "b = 2"),
                                  fake_tool("probe", code = "c = 3"), "done"),
                             name = "probefake")
  e = new.env()
  peter("Use the probe twice", model = fake, envir = e, mode = manual)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(e$c, 3)
  expect_identical(ui$log$method, rep("permission", 4L))
  results = fake_requests(fake)
  expect_identical(results[[2L]]$last_results[[1L]]$content[[1L]]$text, "true")
  expect_identical(results[[3L]]$last_results[[1L]]$content[[1L]]$text, "false")
})

test_that("a served call the person denies with text says it is theirs (cheat-sheet review)", {
  probe = gptr_tool("probe", "Calls the MCP dispatcher the way the claude adapter does.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    execute = function(input, ctx) {
                      mcp_dispatch_local(r_call(input$code), ctx$session)$result$content[[1L]]$text
                    })
  off = gptr_register(probe)
  withr::defer(off())
  local_scripted_ui(list("y", list(decision = "deny", feedback = "use base R")))
  fake = local_fake_provider(list(fake_tool("probe", code = "b = 2"), "done"), name = "probefake")
  peter("Use the probe", model = fake, envir = new.env(), mode = "manual")
  expect_match(fake_requests(fake)[[2L]]$last_results[[1L]]$content[[1L]]$text,
               "^The user declined this call and said: \"use base R\"\\. ")
})

test_that("inside a running plan-mode session served r calls run in the run's scratch overlay", {
  probe = gptr_tool("planprobe", "Calls the MCP dispatcher the way the claude adapter does.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    risk = function(input, ctx) {
                      list(level = 0L, categories = character(), paths = character())
                    },
                    execute = function(input, ctx) {
                      res = mcp_dispatch_local(r_call(input$code), ctx$session)$result
                      paste(isTRUE(res$isError), res$content[[1L]]$text)
                    })
  off = gptr_register(probe)
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("planprobe", code = "z = nrow(d)\nz"),
                                  fake_tool("planprobe", code = "saveRDS(d, 'd.rds')"),
                                  "done"), name = "planfake")
  e = new.env()
  e$d = mtcars
  peter("Plan with the probe", model = fake, envir = e, mode = plan)
  results = fake_requests(fake)
  first = results[[2L]]$last_results[[1L]]$content[[1L]]$text
  expect_match(first, "^FALSE ")
  expect_match(first, "32", fixed = TRUE)
  expect_false(exists("z", envir = e, inherits = FALSE))
  second = results[[3L]]$last_results[[1L]]$content[[1L]]$text
  expect_match(second, "^TRUE Permission denied")
  expect_false(file.exists("d.rds"))
})

skip_without_server = function() {
  skip_on_cran()
  skip_if(!length(find.package("httpuv", quiet = TRUE, verbose = FALSE)),
    "httpuv is not installed")
  skip_if(!length(find.package("later", quiet = TRUE, verbose = FALSE)),
    "later is not installed")
  skip_if(!length(find.package("openssl", quiet = TRUE, verbose = FALSE)),
    "openssl is not installed")
}

test_that("gptr_mcp_serve() binds 127.0.0.1, needs the token, checks Origin and keeps the seed", {
  skip_without_server()
  e = new.env()
  e$d = mtcars
  withr::local_seed(7)
  seed = get(".Random.seed", envir = globalenv())
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_s3_class(h, "gptr_mcp_handle")
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/mcp$")
  expect_identical(the$mcp_server$srv$getHost(), "127.0.0.1")
  expect_identical(h$token_env, "GPTR_MCP_TOKEN")
  expect_s3_class(h$token, "gptr_secret")
  expect_identical(gptr_mcp_serve(envir = e), h)
  expect_true("mcp_serve" %in% job_list()$kind)
  lst = mcp_test_msg("tools/list")
  expect_identical(mcp_test_post(h$url, lst)$status, 401L)
  expect_identical(mcp_test_post(h$url, lst, token = "wrong-token")$status, 401L)
  evil = mcp_test_post(h$url, lst, token = h$token, headers = list(Origin = "http://evil.example"))
  expect_identical(evil$status, 403L)
  ok = mcp_test_post(h$url, lst, token = h$token,
                     headers = list(Origin = paste0("http://localhost:", h$port)))
  expect_identical(ok$status, 200L)
  expect_identical(vapply(ok$json$result$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
  bad_hdr = mcp_test_post(h$url, lst, token = h$token, headers = list(`Mcp-Method` = "tools/call"))
  expect_identical(bad_hdr$status, 400L)
  req = list(PATH_INFO = "/mcp", REQUEST_METHOD = "POST",
             HTTP_AUTHORIZATION = paste("Bearer", secret_value(h$token, h$url)),
             HTTP_MCP_PROTOCOL_VERSION = "2026-07-28", HTTP_MCP_METHOD = "tools/call",
             rook.input = list(read = function() charToRaw(json_encode(lst))))
  expect_identical(json_decode(mcp_http_handle(the$mcp_server, req)$body)$error$code, -32020L)
  req$REQUEST_METHOD = "GET"
  expect_identical(mcp_http_handle(the$mcp_server, req)$status, 405L)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
})

test_that("an r call through the server is gated: read-only runs, writes wait for permission", {
  skip_without_server()
  e = new.env()
  e$d = mtcars
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  call = function(code) mcp_test_post(h$url, r_call(code), token = h$token)$json$result
  res = call("nrow(d)")
  expect_false(res$isError)
  expect_match(res$content[[1L]]$text, "32", fixed = TRUE)
  res = call("x = 1")
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "Permission denied", fixed = TRUE)
  expect_false(exists("x", envir = e, inherits = FALSE))
  # the dedicated session keeps the mode it started with, like any session (IC-58): a new mode
  # setting applies once the server is started again
  local_gptr_options(mode = "auto")
  expect_true(call("x = 1")$isError)
  gptr_mcp_serve(stop = TRUE)
  h = gptr_mcp_serve(envir = e)
  expect_identical(session_data(the$mcp_server$user$session)$mode, "auto")
  expect_false(call("x = 1")$isError)
  expect_identical(e$x, 1)
})

test_that("the user's token has a dedicated chat session; its usage stays its own (IC-58)", {
  skip_without_server()
  x = local_served_session("auto")
  own = gptr_usage(x$session)
  e = new.env()
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  st = the$mcp_server
  s = st$user$session
  d = session_data(s)
  expect_s3_class(s, "gptr_session")
  expect_identical(list(d$kind, d$mode, d$parent_id), list("chat", "manual", NULL))
  expect_identical(session_home(s), e)
  expect_identical(session_live(s)$mcp_token, h$token)
  bearer = paste("Bearer", secret_value(h$token, h$url))
  rec = mcp_token_lookup(bearer)
  expect_identical(c(rec$id, rec$key), c(d$id, st$user$key))
  # the dedicated session's manual mode gates the user's token, not the auto mode of x's session
  res = mcp_test_post(h$url, r_call("w = 1"), token = h$token)$json$result
  expect_true(res$isError)
  expect_false(exists("w", envir = e, inherits = FALSE))
  # served r, read, edit and write calls send no model request; a request charged to the
  # dedicated session (top-level, no parent) rolls up to it alone (P06's usage_add(), IC-66),
  # never to the session the user was working in
  usage_add(s, usage_conform(data.frame(request_id = "mcp-q1", session = d$id, agent = "main",
                                        provider = "fake", model = "fake-1", route = "api",
                                        input = 100, cost = 0.5, stringsAsFactors = FALSE)))
  expect_identical(attr(gptr_usage(s), "totals")[["requests"]], 1)
  expect_true(d$id %in% gptr_usage()$group)
  expect_identical(gptr_usage(x$session), own)
  gptr_mcp_serve(stop = TRUE)
  expect_null(st$user)
  expect_null(mcp_token_lookup(bearer))
})

test_that("both client eras work against gptr's own server, legacy sessions included", {
  skip_without_server()
  e = new.env()
  local_gptr_options(mode = "auto")
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  bearer = paste("Bearer", secret_value(h$token, h$url))
  for (era in c("modern", "legacy")) {
    spec = list(name = paste0("self_", era), transport = "http", url = h$url, protocol = era,
                headers = list(Authorization = bearer))
    conn = mcp_connect(spec)
    expect_identical(conn$era, era)
    expect_identical(vapply(mcp_tools(conn), function(t) t$name, ""),
                     c("r", "read", "edit", "write"))
    res = mcp_call(conn, "r", list(code = paste0("v_", era, " = 2 * 21")))
    expect_false(res$is_error)
    mcp_close(conn)
  }
  expect_identical(e$v_modern, 42)
  expect_identical(e$v_legacy, 42)
  expect_identical(ls(the$mcp_server$legacy), character())
})

test_that("the token of gptr_mcp_serve()'s session is revoked when that session shuts down", {
  skip_without_server()
  h = gptr_mcp_serve(envir = new.env())
  withr::defer(gptr_mcp_serve(stop = TRUE))
  bearer = paste("Bearer", secret_value(h$token, h$url))
  expect_false(is.null(mcp_token_lookup(bearer)))
  id = session_data(the$mcp_server$user$session)$id
  ev_dispatch("session_shutdown", ev_new("session_shutdown", session = id), session = id)
  expect_null(mcp_token_lookup(bearer))
})

test_that("gptr_mcp_serve() refuses a port other than the running socket's", {
  skip_without_server()
  st = mcp_serve_start()
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_error(gptr_mcp_serve(envir = new.env(), port = st$port %% 65535L + 1L),
               class = "gptr_error_invalid_argument")
  expect_identical(gptr_mcp_serve(envir = new.env(), port = st$port)$port, st$port)
})

test_that("client snippets carry a 3,600 s tool timeout and print without the token", {
  skip_without_server()
  h = gptr_mcp_serve(envir = new.env())
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_setequal(names(h$config), c("codex", "claude_code", "claude_desktop", "cursor"))
  value = secret_value(h$token, h$url)
  expect_true("mcp_servers.gptr.tool_timeout_sec=3600" %in% h$config$codex$args)
  expect_true("mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN" %in% h$config$codex$args)
  expect_identical(h$config$codex$env[[h$token_env]], value)
  expect_identical(json_decode(h$config$claude_code)$mcpServers$gptr$timeout, 3600000L)
  expect_true(grepl(value, as.character(h$config$cursor), fixed = TRUE))
  shown = paste(utils::capture.output(print(h$config$cursor)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "Bearer [secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(utils::capture.output(print(h$config$codex)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "GPTR_MCP_TOKEN=[secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(utils::capture.output(print(h)), collapse = "\n")
  expect_match(shown, "<gptr MCP server> http://127.0.0.1:", fixed = TRUE)
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_null(gptr_mcp_serve(stop = TRUE))
  expect_null(the$mcp_server)
  expect_false("mcp_serve" %in% job_list()$kind)
})

test_that("gptr_mcp_serve() validates its arguments and is refused from model code", {
  expect_error(gptr_mcp_serve(tools = "bash"), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_serve(envir = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_serve(port = 0), class = "gptr_error_invalid_argument")
  local_mocked_bindings(ext_control_guard = function(what) {
    gptr_abort("refused", "permission", action = what, tool = "r", risk = 4L,
               how_to_allow = "run it yourself", session = NULL)
  })
  expect_error(gptr_mcp_serve(envir = new.env()), class = "gptr_error_permission")
})
