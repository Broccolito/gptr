# Result objects are parsed entirely offline; no CLI process or account is used.
source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

test_that("a success subtype with an API error reports the failure and its result detail", {
  skip_on_cran()
  cases = list(
    list(status = 429L, class = "rate_limit", label = "rate limit"),
    list(status = 401L, class = "auth", label = "authentication"),
    list(status = 503L, class = "overloaded", label = "overloaded"),
    list(status = 400L, class = "provider", label = "an error")
  )
  for (case in cases) {
    opts = stub_opts()
    n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
    detail = "Synthetic account notice; try again after its reset."
    expect_true(push_obj(n, list(type = "result", subtype = "success", is_error = TRUE,
                                 api_error_status = case$status, result = detail)))
    ev = utils::tail(opts$log$events, 1L)[[1L]]
    expect_identical(ev$type, "error")
    expect_identical(ev$error$class, case$class)
    expect_identical(ev$error$status, case$status)
    expect_match(ev$message$error_message, case$label, fixed = TRUE)
    expect_match(ev$message$error_message, detail, fixed = TRUE)
    expect_false(grepl("reported success", ev$message$error_message, fixed = TRUE))
    expect_identical(msg_text(ev$message), detail)
  }
})

test_that("explicit CLI errors keep precedence over result text", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  push_obj(n, list(type = "result", subtype = "success", is_error = TRUE,
                   api_error_status = 429L, result = "Synthetic summary.",
                   errors = list("Synthetic explicit reason.")))
  ev = utils::tail(opts$log$events, 1L)[[1L]]
  expect_match(ev$message$error_message, "Synthetic explicit reason.", fixed = TRUE)
  expect_false(grepl("Synthetic summary.", ev$message$error_message, fixed = TRUE))
  expect_false(grepl("reported success", ev$message$error_message, fixed = TRUE))
})

test_that("a failed success subtype without detail stays an honest generic failure", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  push_obj(n, list(type = "result", subtype = "success", is_error = TRUE))
  ev = utils::tail(opts$log$events, 1L)[[1L]]
  expect_identical(ev$error$class, "provider")
  expect_match(ev$message$error_message, "it reported an error", fixed = TRUE)
  expect_false(grepl("reported success", ev$message$error_message, fixed = TRUE))
})

test_that("a successful result remains a successful turn", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  push_obj(n, list(type = "result", subtype = "success", is_error = FALSE,
                   result = "Synthetic answer."))
  ev = utils::tail(opts$log$events, 1L)[[1L]]
  expect_identical(ev$type, "done")
  expect_identical(ev$message$stop_reason, "stop")
  expect_null(ev$message$error_message)
  expect_identical(msg_text(ev$message), "Synthetic answer.")
})

test_that("a resumed CLI session's total_cost_usd costs its increase; a fresh one counts whole", {
  skip_on_cran()
  local_fake_cli_path("claude", "text")
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          state$process = NULL
                          invisible(TRUE)
                        })
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
             params = list(cli_budget = list(cost = 5)))
  opts = stub_opts(run = "r0000000001")
  build = function(run) {
    opts$run = run
    "--resume" %in% pcli_claude_build(stub_model("claude"), ctx, opts)$start$args
  }
  cost = function(total) {
    n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
    push_obj(n, list(type = "result", subtype = "success", result = "ok",
                     total_cost_usd = total))
    n$message()$usage$cost$total
  }
  expect_false(build("r0000000001"))
  opts$state$claude_session = "11111111-1111-4111-8111-111111111111"
  expect_equal(cost(0.20), 0.20)
  opts$state$process = stub_process()
  expect_true(build("r0000000002"))
  expect_equal(cost(0.30), 0.10)
  opts$state$claude_session = NULL
  expect_false(build("r0000000003"))
  expect_equal(cost(0.45), 0.45)
  pcli_untrack("s0123456789")
})


# Real fake-CLI children emit a terminal result, then await another stdin request.
# Capture ownership at message_end, before the built-in agent_end retirement hook.
cli_terminal_snapshot = function() {
  list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths(),
    search = search(), rng = RNGkind(),
    seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
    globals = mget(ls(envir = globalenv(), all.names = TRUE), envir = globalenv()))
}

# The fake CLI helpers are sourced above at run time, where lintr cannot resolve them.
cli_terminal_wait = function(case, failed) {
  local_project()
  local_gptr_options(context = "none", max_attempts = 1L)
  fake = local_fake_cli("claude", case) # nolint: object_usage_linter.
  seen = new.env(parent = emptyenv())
  seen$events = character()
  seen$messages = 0L
  off = gptr_register(gptr_hook("message_end", function(event, ctx) {
    if (!identical(event$role, "assistant")) return(NULL)
    seen$messages = seen$messages + 1L
    seen$session = ctx$session
    seen$run = ctx_run(ctx)
    seen$state = pcli_tracked(ctx$session$id)
    seen$process = seen$state$process
    seen$pid = seen$process$get_pid()
    seen$handle = ps::ps_handle(seen$pid)
    seen$ctime = ps::ps_create_time(seen$handle)
    seen$alive = ps::ps_is_running(seen$handle)
    seen$record = proc_record(seen$pid, seen$process)
    seen$watch = seen$state$watch
    seen$job = seen$state$job
    seen$timer = seen$state$turn_timer
    seen$stream_task = seen$state$stream_turn$id
    seen$events = c(seen$events, "message_end")
    NULL
  }))
  withr::defer(off())
  removers = list()
  withr::defer(for (remove in rev(removers)) remove())
  for (name in c("turn_end", "agent_end")) {
    removers[[length(removers) + 1L]] = gptr_register(gptr_hook(name, function(event, ctx) {
      seen$events = c(seen$events, event$type)
      NULL
    }))
  }
  withr::defer({
    if (exists("session", envir = seen, inherits = FALSE)) {
      state = pcli_tracked(seen$session$id)
      if (!is.null(state)) pcli_stop_child(state, wait_ack = FALSE)
      pcli_untrack(seen$session$id)
    }
  })
  # Initialize the process-identity diagnostic before measuring the public call.
  ps::ps_handle(Sys.getpid())
  home = new.env(parent = baseenv())
  home$sentinel = c(2L, 5L, 7L)
  before = cli_terminal_snapshot()
  started = proc.time()[["elapsed"]]
  value = tryCatch(peter("Give the fixed synthetic fixture result.", model = fake$model,
    envir = home), error = identity)
  seconds = proc.time()[["elapsed"]] - started
  after = cli_terminal_snapshot()
  # Snapshot precedes any failure formatting; no state restoration wraps peter().
  expect_identical(vapply(names(before), function(k) identical(before[[k]], after[[k]]), NA),
    stats::setNames(rep(TRUE, 8L), names(before)))
  expect_identical(home$sentinel, c(2L, 5L, 7L))
  expect_lt(seconds, 20)
  expect_identical(seen$messages, 1L)
  expect_identical(seen$events, c("message_end", "turn_end", "agent_end"))
  expect_true(seen$alive)
  expect_true(is.finite(seen$ctime))
  expect_identical(fake_pids(fake), seen$pid) # nolint: object_usage_linter.
  expect_false(seen$process$is_alive())
  expect_false(ps::ps_is_running(seen$handle))
  expect_true(isTRUE(seen$run$settled))
  expect_null(session_live(seen$session)$run)
  expect_null(seen$state$process)
  expect_null(seen$state$turn_timer)
  expect_false(isTRUE(seen$state$turn_open))
  reactor = reactor_get()
  for (id in c(seen$watch, seen$timer, seen$stream_task, seen$run$task)) {
    expect_true(is.character(id) && length(id) == 1L && nzchar(id))
    expect_false(exists(id, envir = reactor$procs, inherits = FALSE))
    expect_false(exists(id, envir = reactor$timers, inherits = FALSE))
    expect_false(exists(id, envir = reactor$tasks, inherits = FALSE))
  }
  expect_false(exists(as.character(seen$pid), envir = reactor$stdin, inherits = FALSE))
  expect_true(is.list(seen$record) && proc_marker_valid(seen$record$marker))
  expect_null(proc_record(seen$pid, seen$process))
  tree = proc_tree(seen$record$marker)
  expect_false(isTRUE(attr(tree, "unavailable")))
  expect_length(tree, 0L)
  expect_false(file.exists(file.path(proc_dir(create = FALSE),
    paste0(seen$record$marker, ".json"))))
  expect_false(seen$job %in% gptr_jobs()$id)
  expect_false(exists(seen$run$id, envir = reactor$runs, inherits = FALSE))
  expect_true(isTRUE(seen$state$stream_turn$finished))
  expect_identical(nrow(seen$session$usage), 1L)
  expect_identical(length(fake_log(fake, "turn")), 1L) # nolint: object_usage_linter.
  expect_identical(length(fake_log(fake, "handshake")), 1L) # nolint: object_usage_linter.
  if (failed) {
    expect_s3_class(value, "gptr_error_auth")
    stored = session_data(seen$session)$condition
    expect_identical(stored, seen$run$condition)
    expect_identical(value$session, seen$session)
    # gateway_signal adds the public session handle; every original field stays exact.
    signalled = value
    signalled$session = stored$session
    expect_identical(signalled, stored)
    expect_identical(seen$session$status, "error")
  } else {
    expect_identical(value, seen$session)
    expect_identical(value$status, "idle")
    expect_identical(value$text, "Hello from the fake claude CLI.")
  }
  invisible(NULL)
}

test_that("a foreground auth failure retires the fake CLI waiting for more stdin", {
  skip_on_cran()
  cli_terminal_wait("auth-wait", failed = TRUE)
})

test_that("a foreground success retires the fake CLI waiting for more stdin", {
  skip_on_cran()
  cli_terminal_wait("text", failed = FALSE)
})
