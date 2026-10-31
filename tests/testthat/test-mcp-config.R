# Configurations of every harness gptr reads, in a temporary home and project
local_foreign_configs = function(trust = FALSE, files = list(), .env = parent.frame()) {
  home = local_mcp_home(.env)
  proj = local_project(files = files, .env = .env)
  write_json_file(file.path(proj, ".mcp.json"), list(mcpServers = list(
    filesystem = list(command = "npx",
                      args = I(c("-y", "@modelcontextprotocol/server-filesystem", "."))),
    sentry = list(type = "http", url = "https://mcp.sentry.dev/mcp"))))
  claude = list(numStartups = 3L, mcpServers = list(github = list(
    type = "http", url = "https://api.githubcopilot.com/mcp/",
    headers = list(Authorization = "Bearer ${GITHUB_TOKEN}"), timeout = 120000L)))
  claude$projects = list()
  claude$projects[[proj]] = list(mcpServers = list(`local-db` = list(
    type = "stdio", command = "uvx",
    args = I(c("mcp-server-sqlite", "--db-path", "${CLAUDE_PROJECT_DIR:-.}/data.db")))))
  write_json_file(file.path(home, ".claude.json"), claude)
  write_json_file(file.path(app_config_dir("Claude"), "claude_desktop_config.json"),
                  list(mcpServers = list(filesystem = list(
                    command = "npx",
                    args = I(c("-y", "@modelcontextprotocol/server-filesystem", "."))))))
  dir.create(file.path(home, ".codex"), showWarnings = FALSE)
  writeLines(c("model = \"gpt-5.5\"", "[mcp_servers.context7]", "command = \"npx\"",
               "args = [\"-y\", \"@upstash/context7-mcp@latest\"]", "tool_timeout_sec = 90",
               "env_vars = [\"HOME\"]",
               "[mcp_servers.figma]", "url = \"https://mcp.figma.com/mcp\"",
               "bearer_token_env_var = \"FIGMA_OAUTH_TOKEN\"", "enabled_tools = [\"get_file\"]",
               "enabled = false"), file.path(home, ".codex", "config.toml"))
  write_json_file(file.path(proj, ".vscode", "mcp.json"), list(
    inputs = list(list(type = "promptString", id = "k", password = TRUE)),
    servers = list(perplexity = list(type = "stdio", command = "npx",
                                     args = I("server-perplexity-ask"),
                                     env = list(PERPLEXITY_API_KEY = "${input:k}")))))
  write_json_file(file.path(home, ".pi", "agent", "mcp.json"), list(mcpServers = list(
    docs = list(url = "https://example.com/mcp", exposure = "deferred"))))
  # trusted after the project files are written: they are trust-gated
  if (trust) gptr_trust(proj, trust = TRUE)
  list(home = home, project = proj)
}

test_that("the TOML subset reads a Codex config", {
  x = mcp_toml_read(text = c(
    "# comment", "model = \"gpt-5.5\"", "[mcp_servers.context7]", "command = \"npx\"",
    "args = [\"-y\", \"pkg\"]   # trailing", "tool_timeout_sec = 60.5",
    "[mcp_servers.context7.env]", "K = \"v\"", "\"QUOTED.KEY\" = 'C:\\Users'",
    "[mcp_servers.\"r-session\"]", "command = 'Rscript'", "env_vars = [\"HOME\"]",
    "[[skills.config]]", "path = \"a\"", "[[skills.config]]", "path = \"b\"",
    "[misc]", "hex = 0xDEAD_BEEF", "big = 9_007_199_254_740_991",
    "ml = \"\"\"", "Roses \\", "   violets\"\"\"", "empty = []", "t = { a = 1, b = [1, 2] }",
    "when = 1979-05-27T07:32:00Z"))
  expect_identical(x$model, "gpt-5.5")
  expect_identical(x$mcp_servers$context7$args, c("-y", "pkg"))
  expect_identical(x$mcp_servers$context7$tool_timeout_sec, 60.5)
  expect_identical(x$mcp_servers$context7$env$QUOTED.KEY, "C:\\Users")
  expect_identical(x$mcp_servers[["r-session"]]$env_vars, "HOME")
  expect_identical(vapply(x$skills$config, `[[`, "", "path"), c("a", "b"))
  expect_identical(x$misc$hex, 3735928559)
  expect_identical(x$misc$big, 9007199254740991)
  expect_identical(x$misc$ml, "Roses violets")
  expect_identical(x$misc$empty, list())
  expect_identical(x$misc$t$b, 1:2)
  expect_identical(x$misc$when, "1979-05-27T07:32:00Z")
  expect_error(mcp_toml_read(text = "a = [1, 2\nb = 3"), "line 2",
               class = "gptr_error_invalid_argument")
})

test_that("long TOML strings are read in linear time (F-116)", {
  skip_on_cran()
  line = paste0(strrep("w", 48), "\\n")
  value = strrep(paste0(strrep("w", 48), "\n"), 1200)
  text = c(paste0("a = \"", strrep(line, 1200), "\""),
           "b = \"\"\"", paste0(strrep(line, 1200), "\"\"\""))
  t0 = proc.time()[["elapsed"]]
  x = mcp_toml_read(text = text)
  expect_lt(proc.time()[["elapsed"]] - t0, 3)
  expect_identical(x$a, value)
  expect_identical(x$b, value)
})

test_that("foreign configs are found under user_home() and app_config_dir() and merged (IC-63)", {
  fx = local_foreign_configs()
  specs = mcp_config_all(fx$project)
  expect_setequal(names(specs), c("local-db", "filesystem", "sentry", "github", "context7",
                                  "figma", "perplexity", "docs"))
  expect_identical(specs$`local-db`$source, "claude-code:local")
  # an untrusted project's copy of a user's server joins the user's entry (F-111)
  expect_identical(specs$filesystem$source, "claude-desktop:user")
  expect_identical(specs$filesystem$also_in, "claude-code:project")
  expect_identical(specs$github$timeout, 120)
  expect_identical(specs$github$headers[["Authorization"]], "Bearer ${GITHUB_TOKEN}")
  expect_identical(specs$context7$timeout, 90)
  expect_identical(specs$context7$env, c(HOME = "${HOME}"))
  expect_identical(specs$figma$headers[["Authorization"]], "Bearer ${FIGMA_OAUTH_TOKEN}")
  expect_false(specs$figma$enabled)
  expect_identical(specs$figma$toolExposure, list(get_file = "r", `*` = "hidden"))
  expect_true(specs$perplexity$needs_input)
  expect_identical(specs$docs$exposure, "deferred")
  expect_true(specs$filesystem$startable)
  expect_false(specs$sentry$startable)
  expect_true(specs$github$startable)
  expect_false(specs$github$trusted)
})

test_that("timeouts: seconds in gptr's and Codex's files, milliseconds in Claude Code's", {
  tmo = function(x, harness) {
    mcp_entry_norm("s", c(list(command = "srv"), x), harness, "user", "p")$timeout
  }
  expect_identical(tmo(list(timeout = 3600), "gptr"), 3600)
  expect_identical(tmo(list(tool_timeout_sec = 3600), "codex"), 3600)
  expect_identical(tmo(list(timeout = 3600000), "claude-code"), 3600)
  expect_identical(tmo(list(timeout = 90000), "cursor"), 90)
  expect_identical(tmo(list(timeout = 120), "cursor"), 120)
})

test_that("gptr's own files win, defaults apply, and the import setting limits the harnesses", {
  project_mcp = json_encode(list(mcpServers = list(
    sentry = list(url = "https://sentry.example/mcp"))))
  fx = local_foreign_configs(trust = TRUE, files = list(".gptr/mcp.json" = project_mcp))
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(github = list(url = "https://gh.example/mcp", trusted = TRUE)),
    defaults = list(exposure = "deferred", timeout = 30)))
  specs = mcp_config_all(fx$project)
  expect_identical(specs$github$source, "gptr:user")
  expect_true(specs$github$trusted)
  expect_identical(specs$github$exposure, "deferred")
  expect_identical(specs$github$timeout, 30)
  expect_identical(specs$sentry$source, "gptr:project")
  expect_true(specs$sentry$startable)
  expect_identical(specs$`claude-code_github`$source, "claude-code:user")
  expect_identical(specs$`claude-code_sentry`$source, "claude-code:project")
  expect_identical(gptr_mcp()$status[gptr_mcp()$name == "perplexity"], "needs input")
  local_gptr_options(mcp = list(import = "codex"))
  expect_setequal(names(mcp_config_all(fx$project)), c("github", "sentry", "context7", "figma"))
})

test_that("gptr_mcp() lists servers without connecting; untrusted project servers never start", {
  fx = local_foreign_configs(files = list(".gptr/mcp.json" = json_encode(list(
    mcpServers = list(old = list(command = "evil"))))))
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(old = list(type = "sse", url = "https://old.example/sse"))))
  spec = list(command = "npx", args = c("-y", "@upstash/context7-mcp@latest"),
              env = c(HOME = "${HOME}"))
  mcp_era_put(spec, "modern", "2026-07-28")
  procs = length(ps::ps_children(ps::ps_handle()))
  x = gptr_mcp()
  expect_s3_class(x, c("gptr_mcp_servers", "gptr_listing", "data.frame"))
  expect_identical(names(x), c("name", "source", "transport", "era", "status", "tools",
                               "exposure", "tokens", "trusted"))
  expect_identical(length(ps::ps_children(ps::ps_handle())), procs)
  row = function(n) x[x$name == n, ]
  expect_identical(row("context7")$era, "modern")
  expect_identical(row("figma")$status, "disabled")
  expect_identical(row("sentry")$status, "untrusted")
  expect_false(row("sentry")$trusted)
  expect_identical(row("perplexity")$status, "untrusted")
  expect_identical(row("old")$status, "unsupported (sse)")
  expect_identical(row("old")$source, "gptr:user")
  expect_identical(row("github")$status, "configured")
  expect_false(row("github")$trusted)
  expect_error(gptr_mcp("sentry", tools = TRUE), class = "gptr_error_untrusted")
  expect_error(gptr_mcp("nope"), class = "gptr_error_unknown_member")
  expect_error(gptr_mcp(tools = NA), class = "gptr_error_invalid_argument")
})

test_that("gptr_mcp()'s trusted is the spec's: a user mcp.json entry marked trusted", {
  fx = local_foreign_configs(files = list(".gptr/mcp.json" = json_encode(list(
    mcpServers = list(proj = list(command = "srv"))))))
  row = function(n) {
    x = gptr_mcp()
    x[x$name == n, ]
  }
  spec = gptr_mcp_add("docs", url = "http://127.0.0.1:8000/mcp")
  expect_false(spec$trusted)
  expect_identical(row("docs")$trusted, spec$trusted)
  path = file.path(gptr_user_dir("config"), "mcp.json")
  x = json_decode(read_utf8(path)$text)
  x$mcpServers$docs$trusted = TRUE
  write_json_file(path, x)
  expect_true(mcp_config_all(fx$project)$docs$trusted)
  expect_true(row("docs")$trusted)
  expect_identical(row("proj")$status, "untrusted")
  expect_false(row("proj")$trusted)
  gptr_trust(fx$project, trust = TRUE)
  expect_identical(row("proj")$status, "configured")
  expect_false(row("proj")$trusted)
})

test_that("a .claude.json under the user's profile is listed (Windows home, IC-63)", {
  home = local_mcp_home()
  other = withr::local_tempdir("not-home-")
  if (.Platform$OS.type == "windows") withr::local_envvar(HOME = other)
  write_json_file(file.path(home, ".claude.json"), list(mcpServers = list(
    winsrv = list(command = "uvx", args = I("mcp-server-time")))))
  local_project()
  x = gptr_mcp()
  expect_identical(x$source[x$name == "winsrv"], "claude-code:user")
})

test_that("gptr_mcp_add() and gptr_mcp_remove() write gptr's own mcp.json only", {
  fx = local_foreign_configs()
  seen = new.env()
  seen$events = list()
  off = hook_add("mcp_servers_change", function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(off))
  claude_before = readLines(file.path(fx$home, ".claude.json"), encoding = "UTF-8")
  spec = gptr_mcp_add("fs", command = "npx", args = c("-y", "server-fs"),
                      env = c(LOG_LEVEL = "info", API_KEY = "${FS_KEY}"), timeout = 120)
  expect_s3_class(spec, "gptr_mcp_server")
  expect_identical(spec$source, "gptr:user")
  path = file.path(gptr_user_dir("config"), "mcp.json")
  x = json_decode(read_utf8(path)$text)
  expect_identical(x$mcpServers$fs$command, "npx")
  expect_identical(x$mcpServers$fs$args, list("-y", "server-fs"))
  expect_identical(x$mcpServers$fs$env$API_KEY, "${FS_KEY}")
  expect_identical(x$mcpServers$fs$timeout, 120L)
  gptr_mcp_add("web", url = "https://web.example/mcp",
                headers = c(Authorization = "Bearer ${WEB_TOKEN}"), exposure = "direct")
  expect_setequal(names(json_decode(read_utf8(path)$text)$mcpServers), c("fs", "web"))
  expect_identical(readLines(file.path(fx$home, ".claude.json"), encoding = "UTF-8"),
                   claude_before)
  expect_true(gptr_mcp_remove("fs"))
  expect_false(gptr_mcp_remove("fs"))
  expect_identical(names(json_decode(read_utf8(path)$text)$mcpServers), "web")
  expect_identical(vapply(seen$events, function(e) length(e$added), 0L), c(1L, 1L, 0L))
  expect_identical(seen$events[[3L]]$removed, "fs")
  expect_false(dir.exists(paste0(path, ".lock")))
  gptr_mcp_add("proj", command = "srv", scope = "project")
  expect_identical(names(json_decode(read_utf8(file.path(fx$project, ".gptr", "mcp.json"))$text)$
                           mcpServers), "proj")
  expect_true(gptr_mcp_remove("proj", scope = "project"))
})

test_that("gptr_mcp_add() validates its arguments and refuses literal secrets", {
  local_mcp_home()
  local_project(gptr = FALSE)
  expect_error(gptr_mcp_add("bad name", command = "x"), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x"), "exactly one", class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x", command = "a", url = "https://b"), "exactly one",
               class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x", command = "a", exposure = "loud"),
               class = "gptr_error_invalid_argument")
  literal = paste0("Bearer sk-ant-api03-", "abcdefghijklmnopqrstuvwxyz0123456789")
  err = expect_error(gptr_mcp_add("x", url = "https://b/mcp", headers = c(Authorization = literal)),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "headers$Authorization")
  expect_false(grepl("abcdefghijklmnop", conditionMessage(err), fixed = TRUE))
  expect_error(gptr_mcp_add("x", command = "a", scope = "project"), class = "gptr_error_workspace")
  expect_false(file.exists(file.path(gptr_user_dir("config"), "mcp.json")))
  path = file.path(gptr_user_dir("config", create = TRUE), "mcp.json")
  writeLines("{\"mcpServers\": {", path)
  expect_error(gptr_mcp_add("x", command = "a"), class = "gptr_error_workspace")
  expect_identical(readLines(path), "{\"mcpServers\": {")
  writeLines("[1, 2]", path)
  expect_error(gptr_mcp_add("x", command = "a"), class = "gptr_error_workspace")
  writeLines(" ", path)
  gptr_mcp_add("x", command = "a")
  expect_named(json_decode(read_utf8(path)$text)$mcpServers, "x")
})

test_that("gptr_mcp(tools = TRUE) uses a fresh tool cache and connects only when needed", {
  local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  gptr_mcp_add("fixture", command = fx$spec$command, args = fx$spec$args, env = fx$spec$env,
               timeout = 30)
  x = gptr_mcp("fixture", tools = TRUE)
  expect_identical(names(x), c("server", "tool", "signature", "exposure", "tokens"))
  expect_identical(x$tool, c("echo", "add", "slow", "fail", "elicit"))
  expect_identical(x$signature[1L], "echo(text: string)  # Echo the text back.")
  n = sum(fx$log()$method == "tools/list")
  mcp_close_all()
  y = gptr_mcp("fixture", tools = TRUE)
  expect_identical(sum(fx$log()$method == "tools/list"), n)
  expect_identical(gptr_mcp()$tools[gptr_mcp()$name == "fixture"], 5L)
  gptr_mcp("fixture", tools = TRUE, refresh = TRUE)
  expect_identical(sum(fx$log()$method == "tools/list"), n + 1L)
  expect_identical(gptr_mcp()$status[gptr_mcp()$name == "fixture"], "connected")
  write_json_file(file.path(app_config_dir("Claude"), "claude_desktop_config.json"),
                  list(mcpServers = list(stale = list(command = "definitely-not-installed-xyz"))))
  expect_identical(unique(gptr_mcp(tools = TRUE)$server), "fixture")
  expect_error(gptr_mcp("stale", tools = TRUE), class = "gptr_error_spawn")
  gptr_mcp_remove("fixture")
})

test_that("gptr's own project mcp.json writes keep the project trusted (F-82)", {
  local_mcp_home()
  proj = local_project(trust = TRUE)
  gptr_mcp_add("proj", command = "srv", scope = "project")
  expect_true(trust_ok(proj))
  expect_true(gptr_trust(proj))
  x = gptr_mcp()
  expect_identical(x$status[x$name == "proj"], "configured")
  expect_true(gptr_mcp_remove("proj", scope = "project"))
  expect_true(trust_ok(proj))
  expect_true(gptr_trust(proj))
})

test_that("the MCP files of other harnesses in a project are trust-gated (F-83)", {
  fx = local_foreign_configs(trust = TRUE)
  x = gptr_mcp()
  expect_identical(x$status[x$name == "sentry"], "configured")
  write_json_file(file.path(fx$project, ".mcp.json"), list(mcpServers = list(
    pulled = list(command = "sh"))))
  x = gptr_mcp()
  expect_identical(x$status[x$name == "pulled"], "untrusted")
  expect_identical(gptr_trust(fx$project), NA)
  proj = local_project(gptr = FALSE)
  write_json_file(file.path(proj, ".mcp.json"), list(mcpServers = list(only = list(command = "x"))))
  expect_true(trust_resources_present(proj))
})

test_that("foreign servers that differ only in env, headers or cwd stay apart (F-109)", {
  home = local_mcp_home()
  local_project()
  gh = function(token) list(command = "gh-mcp", env = list(GITHUB_TOKEN = token))
  web = function(token) {
    list(type = "http", url = "https://mcp.example.org/mcp", headers = list(Authorization = token))
  }
  write_json_file(file.path(home, ".claude.json"), list(mcpServers = list(
    `gh-work` = gh("${WORK_TOKEN}"), `gh-personal` = gh("${HOME_TOKEN}"),
    `web-a` = web("Bearer ${A_TOKEN}"), `web-b` = web("Bearer ${B_TOKEN}"),
    `dir-a` = list(command = "srv", cwd = "/a"), `dir-b` = list(command = "srv", cwd = "/b"))))
  specs = mcp_config_all()
  nm = c("gh-work", "gh-personal", "web-a", "web-b", "dir-a", "dir-b")
  expect_true(all(nm %in% names(specs)))
  expect_length(unique(vapply(specs[nm], mcp_cache_key, "")), 6L)
})

test_that("an empty env or headers object is the same server as none (F-109)", {
  home = local_mcp_home()
  local_project()
  write_atomic(file.path(home, ".claude.json"), paste0('{"mcpServers": {',
    '"a": {"command": "x", "args": [], "env": {}},',
    '"h": {"type": "http", "url": "https://mcp.example.org/mcp", "headers": {}}}}'))
  write_json_file(file.path(home, ".cursor", "mcp.json"), list(mcpServers = list(
    a = list(command = "x"), h = list(url = "https://mcp.example.org/mcp"))))
  specs = mcp_config_all()
  expect_setequal(names(specs), c("a", "h"))
  expect_identical(specs$a$also_in, "cursor:user")
  expect_identical(specs$h$also_in, "cursor:user")
})

test_that("colliding foreign names are made unique; no entry is lost (F-110)", {
  home = local_mcp_home()
  proj = local_project()
  claude = list(mcpServers = list(gh = list(command = "gh-user")))
  claude$projects = list()
  claude$projects[[proj]] = list(mcpServers = list(gh = list(command = "gh-local")))
  write_json_file(file.path(home, ".claude.json"), claude)
  write_json_file(file.path(proj, ".mcp.json"), list(mcpServers = list(
    gh = list(command = "gh-project"))))
  gptr_trust(proj, trust = TRUE)
  specs = Filter(function(s) startsWith(s$source, "claude-code:"), mcp_config_all(proj))
  expect_length(unique(names(specs)), 3L)
  expect_setequal(vapply(specs, function(s) s$command, ""),
                  c("gh-local", "gh-project", "gh-user"))
  expect_identical(specs$gh$command, "gh-local")
})

test_that("an untrusted project's servers never take a user server's name (F-111)", {
  home = local_mcp_home()
  proj = local_project(files = list(".gptr/mcp.json" = json_encode(list(
    mcpServers = list(fs = list(command = "repo-fs"))))))
  write_json_file(file.path(proj, ".mcp.json"), list(mcpServers = list(
    github = list(command = "repo-gh"))))
  write_json_file(file.path(home, ".claude.json"), list(mcpServers = list(
    github = list(command = "user-gh"))))
  write_json_file(file.path(home, ".cursor", "mcp.json"), list(mcpServers = list(
    fs = list(command = "user-fs"))))
  specs = mcp_config_all(proj)
  expect_identical(specs$github$command, "user-gh")
  expect_true(specs$github$startable)
  expect_identical(specs$fs$command, "user-fs")
  repo = Filter(function(s) s$command %in% c("repo-gh", "repo-fs"), specs)
  expect_length(repo, 2L)
  expect_false(any(vapply(repo, function(s) s$startable, NA)))
})

test_that("a live connection follows its server's configuration (F-119)", {
  local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  path = file.path(gptr_user_dir("config", create = TRUE), "mcp.json")
  conf = function(args) {
    write_json_file(path, list(mcpServers = list(fixture = list(
      command = fx$spec$command, args = I(args), env = as.list(fx$spec$env)))))
  }
  conf(fx$spec$args)
  old = mcp_conn_get("fixture")
  expect_identical(mcp_conn_get("fixture"), old)
  conf(c(fx$spec$args, "--extra=1"))
  new = mcp_conn_get("fixture")
  expect_false(old$alive)
  expect_identical(new$spec$args, c(fx$spec$args, "--extra=1"))
  expect_identical(mcp_call(new, "echo", list(text = "new"))$text, "new")
  unlink(path)
  expect_error(mcp_conn_get("fixture"), class = "gptr_error_unknown_member")
})
