# A temporary home and project with the fixture server registered as gptr's user server
local_fixture_server = function(..., name = "fixture", .env = parent.frame()) {
  local_mcp_home(.env)
  local_project(.env = .env)
  fx = local_mcp_fixture(..., .env = .env)
  local_mcp_server(fx, name, .env = .env)
  fx
}

test_that("peter$mcp$<server>$<tool>() closures connect lazily and return R values", {
  fx = local_fixture_server("modern", "stdio")
  expect_identical(nrow(fx$log()), 0L)
  node = peter$mcp
  expect_s3_class(node, "gptr_ns")
  expect_identical(names(node), "fixture")
  echo = peter$mcp$fixture$echo
  expect_s3_class(echo, "gptr_member")
  expect_identical(names(formals(echo)), "text")
  expect_identical(attr(echo, "signature"),
                   "peter$mcp$fixture$echo(text: string)  # Echo the text back.")
  expect_identical(echo(text = "x"), list(text = "x"))
  expect_identical(fx$log()$method[1L], "server/discover")
  expect_identical(peter$mcp$fixture$add(a = 2, b = 40), list(sum = 42L))
  expect_identical(names(formals(peter$mcp$fixture$slow)), c("steps", "step_ms", "progress"))
  expect_null(formals(peter$mcp$fixture$slow)$steps)
  expect_setequal(names(peter$mcp$fixture), c("echo", "add", "slow", "fail", "elicit"))
  err = expect_error(peter$mcp$fixture$fail(), class = "gptr_error_mcp_tool")
  expect_identical(err$server, "fixture")
  expect_identical(err$tool, "fail")
  expect_error(peter$mcp$fixture$echo(), "text", class = "gptr_error_invalid_argument")
  expect_error(peter$mcp$fixture$nope, class = "gptr_error_unknown_member")
  expect_error(peter$mcp$nobody, class = "gptr_error_unknown_member")
  expect_output(print(peter$mcp$fixture), "fixture: 5 tools")
})

test_that("an unlisted server tells how to list it; printing it connects and lists the tools", {
  fx = local_fixture_server("modern", "stdio")
  expect_match(mcp_catalog_text(NULL),
               "fixture: tools not listed yet; print(peter$mcp$fixture) lists them", fixed = TRUE)
  expect_identical(nrow(fx$log()), 0L)
  expect_output(print(peter$mcp$fixture), "echo(text: string)", fixed = TRUE)
  expect_identical(fx$log()$method[1L], "server/discover")
  expect_setequal(names(peter$mcp$fixture), c("echo", "add", "slow", "fail", "elicit"))
  expect_match(mcp_catalog_text(NULL), "fixture: 5 tools, 5 shown", fixed = TRUE)
})

test_that("an MCP call inside r passes the gate as a nested call and returns an R value", {
  fx = local_fixture_server("modern", "stdio")
  code = paste("res = peter$mcp$fixture$echo(text = \"x\")",
               "bad = tryCatch(peter$mcp$fixture$fail(),",
               "               gptr_error_mcp_tool = function(e) 'caught')", sep = "\n")
  fake = local_fake_provider(list(fake_tool("r", code = code), "done"))
  e = new.env()
  s = peter("Echo x through MCP", model = fake, envir = e, mode = auto)
  expect_identical(e$res, list(text = "x"))
  expect_identical(e$bad, "caught")
  res = fake_requests(fake)[[2L]]$last_results[[1L]]
  tools = vapply(res$details$nested, function(n) n$tool, "")
  expect_identical(tools, c("mcp__fixture__echo", "mcp__fixture__fail"))
  expect_false(res$details$nested[[1L]]$is_error)
})

test_that("a nested MCP call that needs approval is asked separately and can be denied", {
  fx = local_fixture_server("modern", "stdio")
  ui = local_scripted_ui(list("y", "n"))
  code = "res = tryCatch(peter$mcp$fixture$echo(text = 'x'), gptr_error = function(e) class(e)[1])"
  fake = local_fake_provider(list(fake_tool("r", code = code), "done"))
  e = new.env()
  peter("Echo x", model = fake, envir = e, mode = manual)
  expect_identical(e$res, "gptr_error_tool")
  expect_identical(ui$log$method, c("permission", "permission"))
  expect_false("tools/call" %in% fx$log()$method)
})

test_that("the <mcp> catalog fits 1,500 tokens with 125 tools; peter$search() finds the rest", {
  fx = local_fixture_server("modern", "stdio", n_extra = 120L)
  gptr_mcp("fixture", tools = TRUE)
  txt = mcp_catalog_text(NULL, 1500)
  body = sub("^[^\n]*\n", "", txt)
  expect_lte(est_tokens(mcp_catalog_header(), "prose") + est_tokens(body, "code"), 1500)
  first = strsplit(body, "\n", fixed = TRUE)[[1L]][1L]
  shown = as.integer(sub("^fixture: 125 tools, ([0-9]+) shown$", "\\1", first))
  expect_true(shown < 125L)
  full = mcp_catalog_lines(Filter(mcp_advertised, mcp_sync()), 1e6)
  expect_gt(est_tokens(paste(full, collapse = "\n"), "code"), 1500)
  hits = peter$search("Generated tool 117")
  expect_identical(hits$name[1L], "fixture/tool_117")
  expect_identical(hits$kind[1L], "mcp")
  fake = local_fake_provider(list("hi"))
  s = peter("hi", model = fake, envir = new.env(), mode = auto)
  t1 = session_data(s)$frozen$t1
  expect_match(t1, "<mcp>\nMCP tools are R functions called inside r", fixed = TRUE)
  expect_match(t1, "fixture: 125 tools", fixed = TRUE)
})

test_that("the least recently used tools lose their descriptions first", {
  fx = local_fixture_server("modern", "stdio", tools = "echo", n_extra = 20L)
  gptr_mcp("fixture", tools = TRUE)
  expect_identical(peter$mcp$fixture$tool_020(query = "q"), "20")
  specs = Filter(mcp_advertised, mcp_sync())
  cost = function(lines) {
    est_tokens(mcp_catalog_header(), "prose") + est_tokens(paste(lines, collapse = "\n"), "code")
  }
  full = cost(mcp_catalog_lines(specs, 1e6))
  bare = cost(mcp_server_lines(specs$fixture, bare = sprintf("tool_%03d", 1:20)))
  lines = mcp_catalog_lines(specs, floor((full + bare) / 2))
  expect_lte(cost(lines), floor((full + bare) / 2))
  expect_identical(lines[1L], "fixture: 21 tools, 21 shown")
  expect_true(any(grepl("tool_020(query: string, limit?: integer)  # Generated tool 20",
                        lines, fixed = TRUE)))
  expect_true(any(lines == "  tool_001(query: string, limit?: integer)"))
})

test_that("per-tool exposure: direct tools enter the tool array, hidden ones are unreachable", {
  home = local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(fixture = list(command = fx$spec$command, args = I(fx$spec$args),
                                     env = as.list(fx$spec$env),
                                     toolExposure = list(echo = "direct", fail = "hidden")))))
  mcp_sync(force = TRUE)
  fake = local_fake_provider(list(fake_tool("mcp__fixture__echo", text = "direct call"), "done"))
  s = peter("Call echo directly", model = fake, envir = new.env(), mode = auto)
  expect_true("mcp__fixture__echo" %in% session_data(s)$frozen$tool_names)
  res = fake_requests(fake)[[2L]]$last_results[[1L]]
  expect_identical(res$content[[1L]]$text, "direct call")
  expect_error(peter$mcp$fixture$fail, class = "gptr_error_unknown_member")
  expect_false(grepl("fail(", mcp_catalog_text(NULL), fixed = TRUE))
  expect_identical(mcp_tool_level(list(trusted = FALSE),
                                  list(annotations = list(readOnlyHint = TRUE))), 3L)
  expect_identical(mcp_tool_level(list(trusted = TRUE),
                                  list(annotations = list(readOnlyHint = TRUE))), 0L)
  expect_identical(mcp_tool_level(list(trusted = FALSE),
                                  list(annotations = list(destructiveHint = FALSE))), 2L)
})

test_that("servers of other harnesses are reachable by name but not advertised (D-14)", {
  home = local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  write_json_file(file.path(home, ".cursor", "mcp.json"), list(mcpServers = list(
    cur = list(command = fx$spec$command, args = I(fx$spec$args), env = as.list(fx$spec$env)))))
  mcp_sync(force = TRUE)
  expect_null(mcp_catalog_text(NULL))
  expect_identical(peter$mcp$cur$echo(text = "y"), list(text = "y"))
  expect_match(mcp_catalog(NULL, 1500), "cur: 5 tools", fixed = TRUE)
})

test_that("tool arguments named like the member closure's own variables reach the server", {
  props = list(tool = list(type = "string"), server = list(type = "string"),
               fm = list(type = "string"), label = list(type = "string"))
  spec = list(name = "mcp__s__t", signature = "peter$mcp$s$t(tool: string)",
              parameters = list(type = "object", properties = props, required = list("tool")))
  seen = NULL
  local_mocked_bindings(mcp_member_call = function(server, tool, wire, input) {
    seen <<- list(server, tool, wire, input)
    "ok"
  })
  f = mcp_member_closure(spec, "s", "t")
  expect_identical(f(tool = "a", server = "b", fm = "c", label = "d"), "ok")
  expect_identical(seen, list("s", "t", "mcp__s__t",
                              list(tool = "a", server = "b", fm = "c", label = "d")))
})

test_that("signatures name the closure's formals when property names are not syntactic", {
  schema = list(type = "object", properties = list(`file-path` = list(type = "string")),
                required = list("file-path"))
  tool = list(name = "read-file", description = "Read a file.", input_schema = schema)
  s = list(name = "srv", exposure = "r")
  local_mocked_bindings(mcp_tools_known = function(s) list(tool),
                        mcp_member_call = function(server, tool, wire, input) input)
  spec = mcp_tool_spec(s, tool, "r")
  line = "  read_file(file_path: string)  # Read a file."
  expect_identical(spec$signature, paste0("peter$mcp$srv$", trimws(line)))
  expect_identical(mcp_catalog_lines(list(s), 1e6)[2L], line)
  expect_identical(mcp_server_lines(s)[2L], line)
  expect_identical(mcp_member_closure(spec, "srv", tool$name)(file_path = "x"),
                   list(`file-path` = "x"))
})

test_that("tool specs follow their server: a trust change re-registers them, removal drops them", {
  local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  conf = function(...) {
    write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
      mcpServers = list(fixture = list(command = fx$spec$command, args = I(fx$spec$args),
                                       env = as.list(fx$spec$env), ...))))
    mcp_sync(force = TRUE)
  }
  level = function() attr(peter$mcp$fixture$echo, "spec")$risk(list(), NULL)$level
  conf(trusted = TRUE)
  expect_identical(level(), 0L)
  conf()
  expect_identical(level(), 3L)
  conf(toolExposure = list(echo = "direct"))
  expect_identical(attr(peter$mcp$fixture$echo, "spec")$exposure, "direct")
  gptr_mcp()
  expect_identical(registry_get("tool", "mcp__fixture__echo")$exposure, "direct")
  gptr_mcp_remove("fixture")
  expect_null(registry_get("tool", "mcp__fixture__echo"))
})

test_that("setting mcp.exposure = \"direct\" declares the tools of a server without exposure", {
  local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio", tools = c("echo", "add"))
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(fixture = list(command = fx$spec$command, args = I(fx$spec$args),
                                     env = as.list(fx$spec$env)))))
  mcp_sync(force = TRUE)
  withr::local_options(gptr.mcp.exposure = "direct")
  fake = local_fake_provider(list("hi"))
  s = peter("hi", model = fake, envir = new.env(), mode = auto)
  expect_true(all(c("mcp__fixture__echo", "mcp__fixture__add") %in%
                    session_data(s)$frozen$tool_names))
})

test_that("the login target of an MCP server is its expanded URL; a stdio server has none", {
  local_mcp_home()
  local_project()
  withr::local_envvar(MCP_TEST_HOST = "mcp.example.org")
  gptr_mcp_add("remote", url = "https://${MCP_TEST_HOST}/mcp")
  gptr_mcp_add("local", command = "server")
  expect_identical(get("target", envir = oauth_hooks)("remote"),
                   list(url = "https://mcp.example.org/mcp", oauth = NULL))
  expect_error(mcp_login_target("local"), "local process", class = "gptr_error_invalid_argument")
})
