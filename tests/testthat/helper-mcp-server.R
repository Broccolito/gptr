# MCP and OAuth test helpers (P18; contract 12.2). Fixture scripts live in fixtures/mcp/: the
# pure-R MCP server speaking either era over stdio or Streamable HTTP on 127.0.0.1 (server.R),
# the OAuth authorization server and protected resource (oauth.R), a stand-in browser
# (browser.R) and a stand-in CLI child that speaks HTTP MCP with its GPTR_MCP_TOKEN (client.R).
# Children start with rscript_path() (IC-60), run only off CRAN, and stop when the test ends.

# The library path of this process, for children started with --vanilla
mcp_fixture_libs = function() paste(.libPaths(), collapse = .Platform$path.sep)

# Fresh user directories (config, cache) and an empty vault for the calling test: credential
# stores, mcp.json files, caches and registered secrets of one test never reach another (P03's
# test convention: vault_reset() before and after)
local_user_dirs = function(.env = parent.frame()) {
  root = withr::local_tempdir("gptr-user-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = file.path(root, "config"),
                      R_USER_CACHE_DIR = file.path(root, "cache"), .local_envir = .env)
  vault_reset()
  withr::defer(vault_reset(), envir = .env)
  invisible(root)
}

# The fixture scripts, resolved once while the working directory is tests/testthat (tests may
# change it with local_project())
mcp_fixture_dir = normalizePath(testthat::test_path("fixtures", "mcp"))

# Start an HTTP fixture script on a free 127.0.0.1 port (port_candidates(), IC-61) and wait for
# its READY line; skips the test when no port works
mcp_fixture_http = function(script, args, .env) {
  for (port in port_candidates(20L)) {
    p = processx::process$new(rscript_path(),
                              c("--vanilla", script, args, paste0("--port=", port)),
                              stdout = "|", stderr = "|", cleanup_tree = TRUE,
                              env = c("current", R_LIBS = mcp_fixture_libs(),
                                      GPTR_FIXTURE_PARENT = Sys.getpid()))
    ready = FALSE
    t0 = Sys.time()
    while (p$is_alive() && difftime(Sys.time(), t0, units = "secs") < 30) {
      p$poll_io(200L)
      if (any(grepl("^READY", p$read_output_lines()))) {
        ready = TRUE
        break
      }
    }
    if (ready) {
      withr::defer(p$kill_tree(), envir = .env)
      return(list(process = p, port = port))
    }
    p$kill_tree()
  }
  testthat::skip("could not start an HTTP fixture on a free port")
}

# The OAuth authorization server and protected MCP resource (fixtures/mcp/oauth.R):
# list(url (the resource, ".../mcp"), base (the issuer), port, log = function() df(path, what))
local_oauth_mock = function(pkce = "yes", iss = "good", .env = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("httpuv")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("openssl")
  log = withr::local_tempfile(fileext = ".jsonl", .local_envir = .env)
  srv = mcp_fixture_http(file.path(mcp_fixture_dir, "oauth.R"),
                         c(paste0("--pkce=", pkce), paste0("--iss=", iss), paste0("--log=", log)),
                         .env)
  base = paste0("http://127.0.0.1:", srv$port)
  list(url = paste0(base, "/mcp"), base = base, port = srv$port,
       log = function() {
         if (!file.exists(log)) return(data.frame(path = character(), what = character()))
         rows = lapply(readLines(log, warn = FALSE, encoding = "UTF-8"), function(l) {
           as.data.frame(jsonlite::fromJSON(l), stringsAsFactors = FALSE)
         })
         do.call(rbind, rows)
       })
}

# A stand-in browser: oauth_open_browser() starts fixtures/mcp/browser.R, which follows the
# redirects of the sign-in URL to gptr's loopback listener; returns the record of opened URLs
local_browser = function(.env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  seen$procs = list()
  script = file.path(mcp_fixture_dir, "browser.R")
  testthat::local_mocked_bindings(oauth_open_browser = function(url) {
    seen$urls = c(seen$urls, url)
    seen$procs[[length(seen$procs) + 1L]] = processx::process$new(
      rscript_path(), c("--vanilla", script, url), stdout = "|", stderr = "|",
      env = c("current", R_LIBS = mcp_fixture_libs()), cleanup_tree = TRUE)
    invisible(NULL)
  }, .env = .env)
  withr::defer(for (p in seen$procs) p$kill_tree(), envir = .env)
  invisible(seen)
}

# Point gptr_login("mcp:<name>") at fixed URLs for the calling test: `urls` is a named chr
# (server name -> resource URL); the previous login-target callback is restored afterwards
local_login_target = function(urls, .env = parent.frame()) {
  old = get0("target", envir = oauth_hooks, inherits = FALSE)
  oauth_hooks_set(target = function(name) list(url = urls[[name]], oauth = list()))
  withr::defer({
    if (is.null(old)) {
      if (exists("target", envir = oauth_hooks)) rm("target", envir = oauth_hooks)
    } else {
      oauth_hooks_set(target = old)
    }
  }, envir = .env)
  invisible(urls)
}

# Rows of a fixture server's JSONL request log: df(t, method, id, era, via)
mcp_fixture_log = function(path) {
  empty = data.frame(t = numeric(), method = character(), id = character(), era = character(),
                     via = character(), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  lines = readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!length(lines)) return(empty)
  rows = lapply(lines, function(l) {
    x = jsonlite::fromJSON(l, simplifyVector = FALSE)
    data.frame(t = x$t, method = x$method, id = as.character(x$id %||% NA), era = x$era,
               via = x$via, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# The MCP fixture server (contract 12.2): list(spec, log = function() df, stop = function()).
# The spec is a plain list in the shape of a `mcp_server` spec, connectable with mcp_connect().
local_mcp_fixture = function(era = c("modern", "legacy"), transport = c("stdio", "http"),
                             tools = c("echo", "add", "slow", "fail", "elicit"), n_extra = 0L,
                             .env = parent.frame()) {
  era = era[1L]
  transport = transport[1L]
  stopifnot(era %in% c("modern", "legacy"), transport %in% c("stdio", "http"))
  testthat::skip_on_cran()
  log = withr::local_tempfile(fileext = ".jsonl", .local_envir = .env)
  script = file.path(mcp_fixture_dir, "server.R")
  args = c(paste0("--era=", era), paste0("--tools=", paste(tools, collapse = ",")),
           paste0("--extra=", n_extra), paste0("--log=", log))
  spec = if (identical(transport, "stdio")) {
    list(name = "fixture", transport = "stdio", command = rscript_path(),
         args = c("--vanilla", script, args, "--transport=stdio"),
         env = c(R_LIBS = mcp_fixture_libs()), timeout = 30, protocol = "auto")
  } else {
    testthat::skip_if_not_installed("httpuv")
    srv = mcp_fixture_http(script, c(args, "--transport=http"), .env)
    list(name = "fixture", transport = "http",
         url = paste0("http://127.0.0.1:", srv$port, "/mcp"), timeout = 30, protocol = "auto")
  }
  withr::defer(mcp_close_all(), envir = .env)
  list(spec = spec, log = function() mcp_fixture_log(log), stop = function() mcp_close_all())
}

# A fresh user config directory, home and vault for the calling test, so that gptr's user
# mcp.json, the foreign harness files and the secrets of one test never reach another; the
# registry is re-synced last, after the home and the project are restored
local_mcp_home = function(.env = parent.frame()) {
  withr::defer(mcp_sync(force = TRUE), envir = .env)
  home = path_norm(withr::local_tempdir("home-", .local_envir = .env))
  withr::local_envvar(HOME = home, USERPROFILE = home,
                      APPDATA = file.path(home, "AppData", "Roaming"),
                      XDG_CONFIG_HOME = file.path(home, ".config"), CODEX_HOME = "",
                      R_USER_CONFIG_DIR = file.path(home, "gptr-config"),
                      R_USER_CACHE_DIR = file.path(home, "gptr-cache"), .local_envir = .env)
  vault_reset()
  withr::defer(vault_reset(), envir = .env)
  home
}

write_json_file = function(path, x) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_atomic(path, json_encode(x, pretty = TRUE))
}

# Register a fixture (local_mcp_fixture()) as gptr's user server `name` for the calling test
local_mcp_server = function(fx, name = "fixture", .env = parent.frame()) {
  s = fx$spec
  if (identical(s$transport, "stdio")) {
    gptr_mcp_add(name, command = s$command, args = s$args, env = s$env, timeout = 30)
  } else {
    gptr_mcp_add(name, url = s$url, timeout = 30)
  }
  withr::defer(gptr_mcp_remove(name), envir = .env)
  invisible(name)
}

# A JSON-RPC request in either era: modern requests carry the 2026-07-28 `_meta` fields
mcp_test_msg = function(method, params = json_obj(), id = 1L, modern = TRUE) {
  if (modern) {
    params[["_meta"]] = stats::setNames(
      list("2026-07-28", json_obj(), list(name = "test", version = "1")),
      c("io.modelcontextprotocol/protocolVersion", "io.modelcontextprotocol/clientCapabilities",
        "io.modelcontextprotocol/clientInfo"))
  }
  msg = list(jsonrpc = "2.0", method = method, params = params)
  if (!is.null(id)) msg$id = id
  msg
}

# One HTTP POST to a gptr server from this process, through the reactor (its outermost pump
# services httpuv with later::run_now(0), IC-57): list(status, body, json, headers)
mcp_test_post = function(url, msg, token = NULL, headers = list(), timeout = 20) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$chunks = list()
  st$status = NA_integer_
  h = c(list(`Content-Type` = "application/json",
             Accept = "application/json, text/event-stream"), headers)
  if (!is.null(token)) h$Authorization = list("Bearer ", token)
  ver = if (is.list(msg)) msg$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]]
  if (!is.null(ver)) {
    h[["MCP-Protocol-Version"]] = h[["MCP-Protocol-Version"]] %||% ver
    h[["Mcp-Method"]] = h[["Mcp-Method"]] %||% msg$method
  }
  body = if (is.character(msg)) msg else json_encode(msg)
  reactor_http(list(url = url, method = "POST", headers = h, body = body),
               on_bytes = function(raw) st$chunks[[length(st$chunks) + 1L]] = raw,
               on_done = function(status, hd) {
                 st$status = status
                 st$headers = hd
                 st$done = TRUE
               },
               on_fail = function(cnd) {
                 st$status = cnd$status
                 st$done = TRUE
               },
               retry = list(max_attempts = 1L))
  reactor_pump(until = function() isTRUE(st$done), timeout = timeout)
  txt = if (length(st$chunks)) rawToChar(do.call(c, st$chunks)) else ""
  list(status = as.integer(st$status), body = txt,
       json = if (nzchar(txt)) jsonlite::fromJSON(txt, simplifyVector = FALSE),
       headers = st$headers)
}

# A stand-in CLI child of a session (fixtures/mcp/client.R): a separate R process whose
# environment carries GPTR_MCP_TOKEN (child_env(), IC-58; `token` is the handle's token handle,
# or the value of its Codex snippet as P20 passes it) posts `msgs` to `url` while this process
# pumps the reactor; returns one list(status, body) per message
mcp_cli_child = function(url, token, msgs, timeout = 60) {
  env = child_env("mcp", set = list(GPTR_MCP_TOKEN = token, R_LIBS = mcp_fixture_libs()))
  bodies = vapply(msgs, json_encode, "")
  p = proc_spawn(rscript_path(), c("--vanilla", file.path(mcp_fixture_dir, "client.R"), url,
                                   bodies), env = env, stdin = NULL, stdout = "|", stderr = "|")
  on.exit(kill_all(p, grace = 0), add = TRUE)
  got = new.env(parent = emptyenv())
  got$lines = character()
  reactor_pump(until = function() {
    got$lines = c(got$lines, p$read_output_lines())
    !p$is_alive()
  }, timeout = timeout)
  lines = c(got$lines, p$read_output_lines())
  lapply(lines[nzchar(lines)], function(l) jsonlite::fromJSON(l, simplifyVector = FALSE))
}
