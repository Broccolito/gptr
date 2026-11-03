# Cross-process regressions: do not use mcp_test_post(), which pumps for its caller.
mcp_wait_client = function(handle, message, seconds = 3) {
  list(command = rscript_path(),
       args = c("--vanilla", file.path(mcp_fixture_dir, "client.R"), handle$url,
                as.character(seconds)),
       input = json_encode(message),
       env = child_env("helper", set = c(R_LIBS = mcp_fixture_libs(),
                                         GPTR_MCP_TOKEN = secret_value(handle$token, handle$url))))
}

mcp_wait_server = function(envir, .env = parent.frame()) {
  skip_on_cran()
  for (package in c("httpuv", "later", "openssl")) skip_if_not_installed(package)
  handle = gptr_mcp_serve(envir = envir)
  withr::defer(gptr_mcp_serve(stop = TRUE), envir = .env)
  withr::defer(reactor_shutdown(), envir = .env)
  handle
}

test_that("child waits serve an independent MCP client without another input or helper pump", {
  local_project()
  local_gptr_options(mode = "manual")
  envir = new.env(parent = baseenv())
  envir$value = 41
  handle = mcp_wait_server(envir)
  client = mcp_wait_client(handle, mcp_test_msg("tools/call",
    list(name = "r", arguments = list(code = "value + 1"))))
  withr::local_seed(17)
  seed = get(".Random.seed", globalenv())
  # proc_run() and the merged bridge have separate redirected-output wait paths.
  for (merge in c(FALSE, TRUE)) {
    result = if (!merge) {
      do.call(proc_run, c(client, list(timeout = 5)))
    } else {
      bridge_sh(c(client$command, client$args), input = client$input,
                env = c(R_LIBS = mcp_fixture_libs(),
                        GPTR_MCP_TOKEN = secret_value(handle$token, handle$url)),
                timeout = 5, merge = TRUE)
    }
    expect_identical(result$status, 0L, info = result$stderr)
    expect_false(result$timed_out)
    response = if (identical(result$status, 0L)) json_decode(result$stdout)
    expect_false(isTRUE(response$result$isError))
    expect_match(paste(unlist(response$result$content), collapse = " "), "42", fixed = TRUE)
  }
  expect_identical(envir$value, 41)
  expect_identical(get(".Random.seed", globalenv()), seed)
})

test_that("HTTP requests during a child wait cannot ask for input or change the wrong workspace", {
  local_project()
  local_gptr_options(mode = "manual")
  ui = local_scripted_ui()
  envir = new.env(parent = baseenv())
  envir$value = 41
  value = -1
  handle = mcp_wait_server(envir)
  client = mcp_wait_client(handle, mcp_test_msg("tools/call",
    list(name = "r", arguments = list(code = "value = 99"))))
  result = do.call(proc_run, c(client, list(timeout = 5)))
  expect_identical(result$status, 0L, info = result$stderr)
  response = if (identical(result$status, 0L)) json_decode(result$stdout)
  expect_true(isTRUE(response$result$isError))
  expect_match(paste(unlist(response$result$content), collapse = " "), "nobody can approve")
  expect_length(ui$log$method, 0L)
  expect_identical(envir$value, 41)
  expect_identical(value, -1)
})

test_that("a nested child wait leaves HTTP callbacks and sibling tools for the outer pump", {
  local_project()
  local_gptr_options(mode = "manual")
  envir = new.env(parent = baseenv())
  envir$value = 41
  handle = mcp_wait_server(envir)
  seen = new.env(parent = emptyenv())
  seen$phase = "before"
  seen$http = character()
  seen$order = character()
  original = mcp_http_handle
  local_mocked_bindings(mcp_http_handle = function(st, request) {
    seen$http = c(seen$http, seen$phase)
    original(st, request)
  })
  client = mcp_wait_client(handle, mcp_test_msg("tools/call",
    list(name = "r", arguments = list(code = "value + 1"))), seconds = 0.5)
  reactor_enqueue_tool("owner", function() {
    seen$phase = "inside"
    seen$order = c(seen$order, "start")
    seen$result = do.call(proc_run, c(client, list(timeout = 3)))
    seen$http_inside = seen$http
    seen$order = c(seen$order, "end")
    seen$phase = "after"
  })
  reactor_enqueue_tool("sibling", function() seen$order = c(seen$order, "sibling"))
  expect_true(reactor_pump(until = function() {
    length(seen$http) > 0L && "sibling" %in% seen$order
  }, timeout = 5))
  expect_length(seen$http_inside, 0L)
  expect_true(all(seen$http == "after"))
  expect_identical(seen$order, c("start", "end", "sibling"))
  expect_false(identical(seen$result$status, 0L))
  expect_identical(envir$value, 41)
})

test_that("idle served tools do not reenter later callbacks or sibling tools during child waits", {
  skip_on_cran()
  skip_if_not_installed("later")
  local_project()
  withr::defer(reactor_shutdown())
  home = new.env()
  chat = peter("hello", model = gptr_fake_provider(list("ok")), envir = home, mode = "yolo",
                .run = FALSE)
  seen = new.env(parent = emptyenv())
  for (merge in c(FALSE, TRUE)) {
    seen$order = "start"
    home$wait = function() {
      command = rscript_path()
      args = c("--vanilla", "-e", "Sys.sleep(0.3)")
      result = if (merge) bridge_sh(c(command, args), merge = TRUE) else proc_run(command, args)
      seen$inside = seen$order
      result$status
    }
    reactor_enqueue_tool("sibling", function() seen$order = c(seen$order, "sibling"))
    later::later(function() seen$order = c(seen$order, "later"), 0)
    response = mcp_dispatch_local(mcp_test_msg("tools/call",
      list(name = "r", arguments = list(code = "wait()"))), chat)
    seen$order = c(seen$order, "end")
    expect_false(isTRUE(response$result$isError))
    expect_identical(seen$inside, "start")
    expect_identical(reactor_depth(), 0L)
    expect_identical(reactor_get()$tool_depth, 0L)
    expect_true(reactor_pump(until = function() all(c("later", "sibling") %in% seen$order),
                             timeout = 2))
    expect_identical(seen$order, c("start", "end", "later", "sibling"))
  }
})

test_that("an idle served-tool guard is released after evaluation errors and interrupts", {
  skip_on_cran()
  local_project()
  withr::defer(reactor_shutdown())
  home = new.env()
  chat = peter("hello", model = gptr_fake_provider(list("ok")), envir = home, mode = "yolo",
                .run = FALSE)
  home$wait = function() proc_run(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"))
  for (code in c("stop('test error')", "wait()")) {
    if (identical(code, "wait()")) {
      reactor_timer(reactor_now() + 0.1, function() {
        stop(structure(list(message = "test interrupt"), class = c("interrupt", "condition")))
      })
    }
    response = mcp_dispatch_local(mcp_test_msg("tools/call",
      list(name = "r", arguments = list(code = code))), chat)
    expect_true(isTRUE(response$result$isError))
    expect_identical(reactor_get()$tool_depth, 0L)
    expect_identical(reactor_depth(), 0L)
  }
})

test_that("an interrupt during a cooperative child wait kills the child and releases its files", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  seen = new.env(parent = emptyenv())
  original = proc_spawn
  local_mocked_bindings(proc_spawn = function(...) {
    seen$child = original(...)
    seen$child
  })
  files = function() list.files(tempdir(), pattern = "^gptr-(out|err|in)-", full.names = TRUE)
  before = files()
  reactor_timer(reactor_now() + 0.1, function() {
    stop(structure(list(message = "test interrupt"), class = c("interrupt", "condition")))
  })
  result = tryCatch(proc_run(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"), timeout = 1),
                    interrupt = identity)
  expect_s3_class(result, "interrupt")
  expect_false(seen$child$is_alive())
  expect_null(proc_record(seen$child$get_pid()))
  expect_identical(files(), before)
  expect_identical(reactor_depth(), 0L)
})

mcp_serve_command = function(rs) {
  .gptr_repl = rs
  force(.gptr_repl)
  cmd_mcp("serve", ctx_new(rs$session))
}

test_that("MCP serving hands the chat's workspace and mode to R, never a looser session mode", {
  skip_on_cran()
  for (package in c("httpuv", "later", "openssl")) skip_if_not_installed(package)
  local_gw()
  local_gptr_options(mode = "auto")
  gptr_config(mode = "yolo", .scope = "session")
  withr::defer(gptr_mcp_serve(stop = TRUE))
  home = new.env()
  chat = peter("hello", model = gptr_fake_provider(list("ok")), envir = home, mode = "plan",
                .run = FALSE)
  rs = repl_state(chat, new.env())
  output = mcp_serve_command(rs)
  expect_true(rs$exit)
  expect_identical(the$mcp_server$envir, home)
  expect_identical(the$mcp_server$user$session$mode, "plan")
  expect_identical(gptr_last(), chat)
  expect_match(paste(output, collapse = " "), "mode: plan;", fixed = TRUE)
  expect_match(paste(output, collapse = " "), "gptr_last() |> peter()", fixed = TRUE)
  expect_identical(getOption("gptr.mode"), "auto")
  # a running server keeps its workspace and mode for another chat's /mcp serve
  other = peter("again", model = gptr_fake_provider(list("ok")), envir = new.env(),
                mode = "yolo", .run = FALSE)
  output = mcp_serve_command(repl_state(other, new.env()))
  expect_identical(the$mcp_server$envir, home)
  expect_identical(the$mcp_server$user$session$mode, "plan")
  expect_match(paste(output, collapse = " "), "keeps its workspace and mode", fixed = TRUE)
  # a new chat with no session yet serves in the configured default
  gptr_mcp_serve(stop = TRUE)
  rs = repl_state(NULL, new.env())
  mcp_serve_command(rs)
  expect_identical(the$mcp_server$user$session$mode, "yolo")
  expect_null(rs$session)
})

test_that("a failed or piped serving handoff does not leave the console or read another line", {
  local_project()
  chat = peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  rs = repl_state(chat, new.env())
  local_mocked_bindings(ns_fun = function(name) function(...) stop("could not start"))
  expect_error(mcp_serve_command(rs), "could not start")
  expect_false(rs$exit)
  expect_identical(gptr_last(), chat)
  rs$stdin = TRUE
  expect_match(paste(mcp_serve_command(rs), collapse = " "), "interactive R prompt", fixed = TRUE)
  expect_false(rs$exit)
})

test_that("the serving handoff closes the reader, preserves typeahead and keeps the server", {
  skip_on_cran()
  for (package in c("httpuv", "later", "openssl")) skip_if_not_installed(package)
  local_console_test()
  local_gptr_options(mode = "auto")
  local_mocked_bindings(console_class = function() "L")
  home = new.env()
  chat = peter("hello", model = gptr_fake_provider(list("ok")), envir = home, mode = "plan",
                .run = FALSE)
  rs = repl_state(chat, new.env())
  input = local_readline(c("/mcp serve", "!stop('typeahead must not run')"))
  seen = new.env(parent = emptyenv())
  original = console_reader
  local_mocked_bindings(console_reader = function(...) {
    reader = original(...)
    close = reader$close
    reader$close = function() {
      seen$closed = TRUE
      close()
    }
    reader
  })
  withr::defer(gptr_mcp_serve(stop = TRUE))
  result = NULL
  output = utils::capture.output({
    result = repl_main(rs)
  })
  expect_identical(result, chat)
  expect_identical(gptr_last(), chat)
  expect_identical(input$i, 1L)
  expect_true(seen$closed)
  expect_null(rs$envir)
  expect_identical(the$mcp_server$envir, home)
  expect_identical(the$mcp_server$user$session$mode, "plan")
  expect_true(the$mcp_server$srv$isRunning())
  token = secret_value(the$mcp_server$handle$token, the$mcp_server$url)
  expect_false(any(grepl(token, output, fixed = TRUE)))
  expect_identical(getOption("gptr.mode"), "auto")
})
