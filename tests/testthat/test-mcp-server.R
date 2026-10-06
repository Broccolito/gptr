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

skip_without_server = function() {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
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

test_that("a CLI child's token evaluates in its fork's overlay (IC-58)", {
  skip_without_server()
  x = local_served_session("auto")
  f = gptr_fork(x$session)
  h = ext_service_get("mcp.serve_ensure")(f)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_s3_class(h, "gptr_mcp_handle")
  expect_identical(session_live(f)$mcp_token, h$token)
  # P20's request_params hook calls the service with the session object before every codex
  # request (pcli_codex_ensure(ctx$session)) and puts the value of the Codex snippet's env into
  # the child's environment; an id (contract 8.1) resolves to the same session: every call gives
  # the same usable token
  again = ext_service_get("mcp.serve_ensure")(f)
  by_id = ext_service_get("mcp.serve_ensure")(session_data(f)$id)
  expect_identical(list(again$token, by_id$token), list(h$token, h$token))
  expect_error(ext_service_get("mcp.serve_ensure")("no-such-session"),
               class = "gptr_error_invalid_argument")
  value = again$config$codex$env[[again$token_env]]
  expect_identical(value, secret_value(h$token, h$url))
  out = mcp_cli_child(h$url, value, list(r_call("y_child = 42", id = 1L),
                                         r_call("exists('d')", id = 2L)))
  expect_identical(vapply(out, function(o) o$status, 0L), c(200L, 200L))
  expect_false(jsonlite::fromJSON(out[[1L]]$body, simplifyVector = FALSE)$result$isError)
  expect_identical(get("y_child", envir = session_home(f), inherits = FALSE), 42)
  expect_false(exists("y_child", envir = x$envir, inherits = FALSE))
  h$stop()
  expect_identical(mcp_test_post(h$url, r_call("1"), token = h$token)$status, 401L)
})

test_that("a session's token is revoked when the session shuts down (IC-58)", {
  skip_without_server()
  x = local_served_session("auto")
  h = ext_service_get("mcp.serve_ensure")(x$session)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  bearer = paste("Bearer", secret_value(h$token, h$url))
  expect_false(is.null(mcp_token_lookup(bearer)))
  id = session_data(x$session)$id
  ev_dispatch("session_shutdown", ev_new("session_shutdown", session = id), session = id)
  expect_null(mcp_token_lookup(bearer))
})

test_that("gptr_mcp_serve() refuses a port other than the shared socket's", {
  skip_without_server()
  x = local_served_session("auto")
  h = ext_service_get("mcp.serve_ensure")(x$session)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_error(gptr_mcp_serve(envir = new.env(), port = h$port %% 65535L + 1L),
               class = "gptr_error_invalid_argument")
  expect_identical(gptr_mcp_serve(envir = new.env(), port = h$port)$port, h$port)
})

test_that("a CLI child of a plan-mode parent is gated in plan mode", {
  skip_without_server()
  x = local_served_session("plan")
  # by id (contract 8.1 gives L1 adapters only ids; P18 accepts one beside the session object
  # that P20's request_params hook and P19's cli backend pass)
  h = ext_service_get("mcp.serve_ensure")(session_data(x$session)$id)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  out = mcp_cli_child(h$url, h$token, list(r_call("saveRDS(d, 'd.rds')", id = 1L),
                                           r_call("nrow(d)", id = 2L),
                                           r_call("z = 1", id = 3L)))
  body = lapply(out, function(o) jsonlite::fromJSON(o$body, simplifyVector = FALSE)$result)
  expect_true(all(vapply(body, function(b) isTRUE(b$isError), NA)))
  expect_match(body[[1L]]$content[[1L]]$text, "plan mode", fixed = TRUE)
  expect_false(file.exists("d.rds"))
  # at an idle console a plan-mode session has no run, hence no scratch overlay (IC-15): P11's
  # plan policy refuses every r call then
  expect_match(body[[2L]]$content[[1L]]$text, "plan mode needs a scratch environment",
               fixed = TRUE)
  expect_false(exists("z", envir = x$envir, inherits = FALSE))
})

test_that("in a nested pump only the runs it serves are answered; others get -32002 (IC-57)", {
  skip_without_server()
  x = local_served_session("auto")
  h = ext_service_get("mcp.serve_ensure")(x$session)
  user = gptr_mcp_serve(envir = new.env())
  withr::defer(gptr_mcp_serve(stop = TRUE))
  rec_user = mcp_token_lookup(paste("Bearer", secret_value(user$token, user$url)))
  rec_s = mcp_token_lookup(paste("Bearer", secret_value(h$token, h$url)))
  expect_false(mcp_serve_busy(rec_user))
  local_mocked_bindings(reactor_allow_runs = function() "u00000000")
  expect_true(mcp_serve_busy(rec_user))
  expect_true(mcp_serve_busy(rec_s))
  req = list(PATH_INFO = "/mcp", REQUEST_METHOD = "POST",
             HTTP_AUTHORIZATION = paste("Bearer", secret_value(h$token, h$url)),
             HTTP_MCP_PROTOCOL_VERSION = "2026-07-28", HTTP_MCP_METHOD = "tools/call",
             rook.input = list(read = function() charToRaw(json_encode(r_call("1")))))
  res = mcp_http_handle(the$mcp_server, req)
  expect_identical(res$status, 200L)
  expect_identical(json_decode(res$body)$error$code, -32002L)
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
  shown = paste(cli::cli_fmt(print(h$config$cursor)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "Bearer [secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(cli::cli_fmt(print(h$config$codex)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "GPTR_MCP_TOKEN=[secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(cli::cli_fmt(print(h)), collapse = "\n")
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
