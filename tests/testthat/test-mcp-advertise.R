# gptr_mcp_serve()'s discovery record (`advertise`), `mode` and the served `inspect` tool, for
# local clients that find a running session without copying its address and token.

# A served session in a fresh user cache (setup.R redirects it once per suite; each test here gets
# its own), stopped when the test ends
local_advertised = function(..., .env = parent.frame()) {
  skip_on_cran()
  for (package in c("httpuv", "later", "openssl")) skip_if_not_installed(package)
  local_user_dirs(.env = .env)
  handle = gptr_mcp_serve(...)
  withr::defer(gptr_mcp_serve(stop = TRUE), envir = .env)
  withr::defer(reactor_shutdown(), envir = .env)
  handle
}

record_path = function(pid = Sys.getpid()) {
  file.path(tools::R_user_dir("gptr", "cache"), "mcp-serve", paste0("serve-", pid, ".json"))
}

read_record = function(path = record_path()) jsonlite::fromJSON(path, simplifyVector = FALSE)

tool_call = function(name, code) {
  mcp_test_msg("tools/call", list(name = name, arguments = list(code = code)))
}

test_that("a server writes no discovery record unless asked to advertise", {
  local_advertised(envir = new.env())
  expect_false(file.exists(record_path()))
  expect_false(dir.exists(dirname(record_path())))
})

test_that("an advertised server's record is private, complete and removed at stop", {
  local_gptr_options(mode = "manual")
  e = new.env()
  e$d = mtcars
  h = local_advertised(envir = e, advertise = TRUE)
  path = record_path()
  expect_true(file.exists(path))
  rec = read_record(path)
  expect_identical(names(rec), c("format", "pid", "url", "port", "token", "started", "wd", "label",
                                 "mode", "tools", "r_version", "gptr_version", "front_end"))
  token = secret_value(h$token, h$url)
  expect_identical(rec[c("format", "pid", "url", "port", "token")],
                   list(format = 1L, pid = Sys.getpid(), url = h$url, port = h$port,
                        token = token))
  expect_identical(rec$wd, getwd())
  expect_identical(rec$label, basename(getwd()))
  expect_identical(rec$mode, "manual")
  expect_identical(unlist(rec$tools), c("inspect", "r", "read", "edit", "write"))
  expect_identical(rec$r_version, as.character(getRversion()))
  expect_identical(rec$gptr_version, as.character(utils::packageVersion("gptr")))
  expect_identical(rec$front_end, front_end())
  expect_match(rec$started, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$")
  if (.Platform$OS.type == "unix") {
    expect_identical(format(file.info(path)$mode), "600")
    expect_identical(format(file.info(dirname(path))$mode), "700")
  }
  # the record's token is the server's: a client that reads it is served
  ok = mcp_test_post(rec$url, mcp_test_msg("tools/list"), token = rec$token)
  expect_identical(ok$status, 200L)
  # print() names the record and format() is the environment's; neither shows the token
  shown = paste(utils::capture.output(print(h)), collapse = "\n")
  expect_match(shown, paste0("advertised to local clients: ", path), fixed = TRUE)
  expect_false(grepl(token, shown, fixed = TRUE))
  expect_false(any(grepl(token, format(h), fixed = TRUE)))
  gptr_mcp_serve(stop = TRUE)
  expect_false(file.exists(path))
  expect_null(the$mcp_server)
})

test_that("a label names the session, and advertising a running server writes its record", {
  h = local_advertised(envir = new.env())
  expect_false(file.exists(record_path()))
  expect_identical(gptr_mcp_serve(advertise = "other"), h)
  expect_identical(read_record()$label, "other")
  shown = paste(utils::capture.output(print(h)), collapse = "\n")
  expect_match(shown, "advertised to local clients", fixed = TRUE)
  # a call without advertise neither withdraws nor rewrites it
  expect_identical(gptr_mcp_serve(), h)
  expect_identical(read_record()$label, "other")
  for (bad in list(NA, "", c("a", "b"), 1)) {
    expect_error(gptr_mcp_serve(advertise = bad), class = "gptr_error_invalid_argument")
  }
})

test_that("records of R processes that are gone are pruned when gptr loads", {
  local_user_dirs()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  p$wait(10000)
  dead = p$get_pid()
  skip_if(p$is_alive(), "the short-lived R process did not exit")
  dir = dirname(record_path())
  dir.create(dir, recursive = TRUE)
  gone = record_path(dead)
  live = record_path()
  other = file.path(dir, "notes.txt")
  for (f in c(gone, live, other)) writeLines("{}", f)
  expect_identical(mcp_advertise_prune(), 1L)
  expect_identical(file.exists(c(gone, live, other)), c(FALSE, TRUE, TRUE))
  expect_identical(mcp_advertise_prune(), 0L)
  unlink(dir, recursive = TRUE)
  expect_identical(mcp_advertise_prune(), 0L)
})

test_that("the record is removed when R exits", {
  skip_on_cran()
  for (package in c("httpuv", "later", "openssl")) skip_if_not_installed(package)
  root = local_user_dirs()
  local_worker_lib()
  code = paste(
    "options(gptr.quiet = TRUE)",
    "h = gptr::gptr_mcp_serve(envir = new.env(), advertise = TRUE)",
    "p = file.path(tools::R_user_dir('gptr', 'cache'), 'mcp-serve',",
    "              paste0('serve-', Sys.getpid(), '.json'))",
    "cat(file.exists(p), p, sep = '\\n')", sep = "\n")
  res = processx::run(rscript_path(), c("--vanilla", "-e", code), error_on_status = FALSE,
                      env = c("current", R_LIBS = mcp_fixture_libs(), GPTR_LIVE_TESTS = "false"),
                      timeout = 120)
  out = strsplit(trimws(res$stdout), "\n", fixed = TRUE)[[1L]]
  expect_identical(res$status, 0L)
  expect_identical(out[[1L]], "TRUE")
  expect_true(startsWith(out[[2L]], root))
  expect_false(file.exists(out[[2L]]))
})

test_that("mode chooses the served mode; a running server refuses another", {
  local_gptr_options(mode = "manual")
  e = new.env()
  h = local_advertised(envir = e, mode = "auto", advertise = TRUE)
  expect_identical(session_data(the$mcp_server$user$session)$mode, "auto")
  expect_identical(read_record()$mode, "auto")
  res = mcp_test_post(h$url, tool_call("r", "x = 1"), token = h$token)$json$result
  expect_false(res$isError)
  expect_identical(e$x, 1)
  shown = paste(utils::capture.output(print(h)), collapse = "\n")
  expect_match(shown, "mode: auto", fixed = TRUE)
  expect_identical(gptr_mcp_serve(mode = "auto"), h)
  expect_identical(gptr_mcp_serve(), h)
  expect_error(gptr_mcp_serve(mode = "manual"), class = "gptr_error_invalid_argument")
  for (bad in list("yolo", "Auto", NA, 1)) {
    expect_error(gptr_mcp_serve(mode = bad), class = "gptr_error_invalid_argument")
  }
})

test_that("inspect runs only level-0 code, in every mode, and is annotated read-only", {
  e = new.env()
  e$d = mtcars
  h = local_advertised(envir = e, mode = "auto")
  tools = mcp_test_post(h$url, mcp_test_msg("tools/list"), token = h$token)$json$result$tools
  names = vapply(tools, `[[`, "", "name")
  expect_identical(names, c("inspect", "r", "read", "edit", "write"))
  ins = tools[[1L]]
  expect_identical(ins$annotations[c("readOnlyHint", "destructiveHint")],
                   list(readOnlyHint = TRUE, destructiveHint = FALSE))
  expect_identical(ins$inputSchema$required, list("code"))
  expect_true(tools[[2L]]$annotations$destructiveHint)
  call = function(code) {
    mcp_test_post(h$url, tool_call("inspect", code), token = h$token)$json$result
  }
  res = call("nrow(d)")
  expect_false(res$isError)
  expect_match(res$content[[1L]]$text, "32", fixed = TRUE)
  # auto mode would run these through r; inspect refuses them before anything runs
  res = call("y = 1")
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "level 1 (local)", fixed = TRUE)
  expect_match(res$content[[1L]]$text, "Use r for it. Nothing in this call ran.", fixed = TRUE)
  expect_false(exists("y", envir = e, inherits = FALSE))
  res = call("d$mpg[1] = 0")
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "level 2", fixed = TRUE)
  expect_identical(e$d, mtcars)
  # the user's rules for r cover inspect: a deny rule refuses even level-0 code
  local_permission_rules()
  gptr_permissions(deny = "r(sh:cat *)")
  expect_identical(gptr_risk("peter$sh('cat notes.txt')")$level, 0L)
  res = call("peter$sh('cat notes.txt')")
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "r(sh:cat *)", fixed = TRUE)
  expect_match(res$content[[1L]]$text, "Nothing in this call ran.", fixed = TRUE)
})

test_that("inspect also runs in manual and plan mode, where r refuses writes", {
  for (mode in c("manual", "plan")) {
    e = new.env()
    e$d = mtcars
    h = local_advertised(envir = e, mode = mode)
    res = mcp_test_post(h$url, tool_call("inspect", "dim(d)"), token = h$token)$json$result
    expect_false(res$isError, label = mode)
    expect_match(res$content[[1L]]$text, "32 11", fixed = TRUE, label = mode)
    gptr_mcp_serve(stop = TRUE)
  }
  h = local_advertised(envir = new.env(), tools = c("r", "read"))
  tools = mcp_test_post(h$url, mcp_test_msg("tools/list"), token = h$token)$json$result$tools
  expect_identical(vapply(tools, `[[`, "", "name"), c("r", "read"))
  res = mcp_test_post(h$url, tool_call("inspect", "1"), token = h$token)$json
  expect_identical(res$error$code, -32602L)
})

test_that("an outside client's instructions guide it; the CLI routes keep their short ones", {
  h = local_advertised(envir = new.env())
  init = mcp_test_post(h$url, mcp_test_msg("initialize", list(protocolVersion = "2025-06-18"),
                                           modern = FALSE), token = h$token)$json$result
  text = init$instructions
  expect_match(text, "Use inspect to look", fixed = TRUE)
  expect_match(text, "never reload or recompute data that is already in memory", fixed = TRUE)
  expect_match(text, "do not reword the code to get around it", fixed = TRUE)
  expect_match(text, "a new R process, such as Rscript from a shell", fixed = TRUE)
  disc = mcp_test_post(h$url, mcp_test_msg("server/discover"), token = h$token)$json$result
  expect_identical(disc$instructions, text)
  gptr_mcp_serve(stop = TRUE)
  h = local_advertised(envir = new.env(), tools = "read")
  init = mcp_test_post(h$url, mcp_test_msg("server/discover"), token = h$token)$json$result
  expect_false(grepl("inspect", init$instructions, fixed = TRUE))
  expect_false(grepl("never reload", init$instructions, fixed = TRUE))
  fake = local_fake_provider(list("ok"))
  s = peter("hello", model = fake, envir = new.env(), mode = "auto")
  local = mcp_dispatch_local(mcp_test_msg("server/discover"), s)$result
  expect_identical(local$instructions, paste("Tools run inside the user's live R session;",
                                             "objects persist. Every call passes the user's",
                                             "permission settings."))
})

test_that("geterrmessage() and .Traceback read at level 0", {
  for (code in c("geterrmessage()", ".Traceback", "traceback()", "cat(geterrmessage())")) {
    expect_identical(gptr_risk(code)$level, 0L, label = code)
  }
})

test_that("reading a discovery record is a guarded secret read", {
  for (code in c("readLines('/u/.cache/R/gptr/mcp-serve/serve-4242.json')",
                 "jsonlite::fromJSON('C:\\\\Users\\\\u\\\\R\\\\gptr\\\\mcp-serve\\\\serve-7.json')",
                 "peter$sh('cat ~/.cache/R/gptr/mcp-serve/serve-4242.json')")) {
    r = gptr_risk(code)
    expect_true(r$secret_guard, label = code)
    expect_gte(r$level, 3L)
  }
  expect_false(gptr_risk("readLines('/u/mcp-serve/notes.json')")$secret_guard)
  # so a served client cannot read a token from a record, even in auto mode (not through
  # inspect either, which runs level 0 only)
  h = local_advertised(envir = new.env(), mode = "auto", advertise = TRUE)
  code = paste0("readLines('", record_path(), "')")
  for (name in c("r", "inspect")) {
    res = mcp_test_post(h$url, tool_call(name, code), token = h$token)$json$result
    expect_true(res$isError, label = name)
    expect_match(res$content[[1L]]$text, "Nothing in this call ran.", fixed = TRUE, label = name)
    expect_false(grepl(secret_value(h$token, h$url), res$content[[1L]]$text, fixed = TRUE))
  }
})
