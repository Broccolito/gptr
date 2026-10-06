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
  expect_identical(vapply(tl$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
  expect_identical(tl$cacheScope, "private")
  # adapters hold session ids (contract 8.1): the id of a session builtin:mcp saw start works too
  by_id = mcp_dispatch_local(mcp_test_msg("tools/list"), session_data(s)$id)$result
  expect_identical(vapply(by_id$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
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
