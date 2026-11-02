test_that("waited background parents show delegation while ordinary background work is silent", {
  local_console_test()
  local_gptr_options(mode = "auto", verbose = 2L, quiet = FALSE)
  withr::local_options(cli.dynamic = FALSE, cli.num_colors = 1L, cli.unicode = FALSE)
  local_fake_provider(list("child report"), name = "wait-kid")
  chat = local_fake_provider(function(req) {
    if (length(req$last_results)) return("parent done")
    fake_tool("r", code = paste0(
      "peter('each', list(alpha = 1, beta = 2, gamma = 3), ",
      "model = 'wait-kid/wait-kid-1', parallel = 2)"))
  }, name = "wait-main")
  state = console_state()
  old = state$waited
  withr::defer({
    state$waited = old
  })
  run_case = function(waited) {
    s = peter("delegate", model = chat, .run = FALSE, envir = new.env())
    live = session_live(s)
    live$background = list(id = paste0("b-", s$id))
    run = run_start(s, NULL, list(background = TRUE))
    on.exit(run_abort(run, reason = "test cleanup"), add = TRUE)
    state$waited = c(old, if (waited) s$id)
    out = utils::capture.output(gptr_wait(s))
    expect_identical(s$status, "idle")
    expect_length(console_kids(), 0L)
    expect_null(the$live_row)
    paste(out, collapse = "\n")
  }
  expect_false(grepl("sub-agent", run_case(FALSE), fixed = TRUE))
  waited = run_case(TRUE)
  expect_match(waited, "sub-agents 0/3 done - 2 active - 1 queued", fixed = TRUE)
  expect_match(waited, "active  alpha (wait-kid/wait-kid-1)", fixed = TRUE)
  expect_match(waited, "queued  gamma (wait-kid/wait-kid-1)", fixed = TRUE)
  expect_match(waited, "sub-agent gamma done (3/3)", fixed = TRUE)
})

test_that("aborting a scheduled fanout cancels active work and leaves queued work unsent", {
  local_console_test()
  local_live_console()
  local_gptr_options(mode = "auto", verbose = 2L, quiet = FALSE, interactive = TRUE)
  withr::local_options(cli.dynamic = TRUE, cli.num_colors = 1L, cli.unicode = FALSE)
  seen = new.env(parent = emptyenv())
  kid = local_fake_provider(function(req) {
    if (is.null(seen$timer)) {
      seen$timer = reactor_timer(reactor_now() + 0.02, function() {
        seen$what = console_live_state(the$live_row$rec)$what
        stop(structure(list(message = "test abort", call = NULL),
                       class = c("interrupt", "condition")))
      })
    }
    list(text = "UNFINISHED CHILD", delay = 30)
  }, name = "abort-kid")
  withr::defer(if (!is.null(seen$timer)) reactor_cancel(seen$timer))
  chat = local_fake_provider(function(req) {
    if (req$n > 1L) return("not reached")
    seen$parent = the$live_row$rec$session
    session_enqueue(seen$parent, "keep this unsent", as = "steer", source = "api_user")
    fake_tool("r", code = paste0(
      "peter('each', list(alpha = 1, beta = 2, gamma = 3), ",
      "model = 'abort-kid/abort-kid-1', parallel = 2)"))
  }, name = "abort-main")
  interrupted = NULL
  out = written(function() {
    interrupted <<- tryCatch(peter("delegate", model = chat, envir = new.env()),
                             interrupt = identity)
  })
  expect_s3_class(interrupted, "interrupt")
  expect_match(seen$what, "sub-agents 0/3 done - 2 active - 1 queued", fixed = TRUE)
  expect_length(fake_requests(kid), 2L)
  expect_length(fake_requests(chat), 1L)
  expect_identical(seen$parent$status, "aborted")
  expect_identical(vapply(session_data(seen$parent)$dropped, function(x) x$text, ""),
                   "keep this unsent")
  rows = term_rows(out)
  expect_length(grep("sub-agent (alpha|beta) failed", rows), 2L)
  expect_false(any(grepl("sub-agent gamma", rows, fixed = TRUE)))
  expect_null(the$live_row)
  expect_length(console_kids(), 0L)
})

test_that("a retry keeps its scheduled slot and names its phase before resuming", {
  local_console_test()
  local_live_console()
  local_gptr_options(mode = "auto", verbose = 2L, quiet = FALSE, interactive = TRUE)
  withr::local_options(cli.dynamic = TRUE, cli.num_colors = 1L, cli.unicode = FALSE)
  local_mocked_bindings(agent_retry_delay = function(attempt) 0.1)
  seen = new.env(parent = emptyenv())
  retry = local_fake_provider(function(req) {
    if (req$n == 1L) {
      seen$timer = reactor_timer(reactor_now() + 0.02, function() {
        seen$waiting = console_live_state(the$live_row$rec)$what
      })
      return(fake_error("overloaded", status = 529L))
    }
    seen$resumed = console_live_state(the$live_row$rec)$what
    "retry report"
  }, name = "retry-kid")
  withr::defer(if (!is.null(seen$timer)) reactor_cancel(seen$timer))
  local_fake_provider(list(list(text = "slow report", delay = 1)), name = "slow-kid")
  local_fake_provider(list("queued report"), name = "queued-kid")
  result = NULL
  out = written(function() {
    result <<- peter("review", agents = list(
      retryer = agent(model = "retry-kid/retry-kid-1"),
      slow = agent(model = "slow-kid/slow-kid-1"),
      pending = agent(model = "queued-kid/queued-kid-1")
    ), .opts = list(max_active = 2L))
  })
  expect_identical(result$status, "idle")
  expect_length(fake_requests(retry), 2L)
  expect_match(seen$waiting, "sub-agents 0/3 done - 2 active - 1 queued", fixed = TRUE)
  expect_match(seen$waiting, "retryer retrying", fixed = TRUE)
  expect_match(seen$resumed, "retryer thinking", fixed = TRUE)
  expect_length(grep("sub-agent retryer retrying in 0.1 s", term_rows(out), fixed = TRUE), 1L)
  expect_match(out, "retryer (retry-kid/retry-kid-1)", fixed = TRUE)
  expect_null(the$live_row)
  expect_length(console_kids(), 0L)
})

test_that("a failed child hands the live row to its sibling and drains the scheduled queue", {
  local_console_test()
  local_live_console()
  local_gptr_options(mode = "auto", verbose = 2L, quiet = FALSE, interactive = TRUE)
  withr::local_options(cli.dynamic = TRUE, cli.num_colors = 1L, cli.unicode = FALSE)
  local_fake_provider(list(fake_error("bad request", status = 400L)), name = "bad-kid")
  local_fake_provider(list(list(text = "slow report", delay = 1)), name = "slow-kid")
  seen = new.env(parent = emptyenv())
  queued = local_fake_provider(function(req) {
    seen$what = console_live_state(the$live_row$rec)$what
    seen$owner = the$live_row$rec$child$label
    "queued report"
  }, name = "queued-kid")
  result = NULL
  out = written(function() {
    result <<- peter("review", agents = list(
      bad = agent(model = "bad-kid/bad-kid-1"),
      slow = agent(model = "slow-kid/slow-kid-1"),
      pending = agent(model = "queued-kid/queued-kid-1")
    ), .opts = list(max_active = 2L))
  })
  expect_identical(result$status, "error")
  expect_identical(result$slow$status, "idle")
  expect_identical(result$pending$status, "idle")
  expect_length(fake_requests(queued), 1L)
  expect_identical(seen$owner, "slow")
  expect_match(seen$what, "sub-agents 1/3 done - 2 active - 0 queued", fixed = TRUE)
  rows = term_rows(out)
  expect_length(grep("sub-agent bad failed (1/3)", rows, fixed = TRUE), 1L)
  expect_match(out, "sub-agents 2/3 done", fixed = TRUE)
  expect_match(out, "sub-agent slow done (3/3)", fixed = TRUE)
  expect_null(the$live_row)
  expect_length(console_kids(), 0L)
})

test_that("a terminal fanout keeps its roster, phases and the parent's composer", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 80L)",
    "kid = gptr_fake_provider(function(req) {",
    "  if (!length(req$last_results)) return(list(tool = 'r',",
    "    input = list(code = 'Sys.sleep(2); 1L')))",
    "  list(text = 'PRIVATE-CHILD-REPORT', delay = 4)",
    "}, name = 'kid')",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$n == 1L) return(list(tool = 'r', input = list(code = paste0(",
    "    'fan = peter(\"each\", list(alpha = 1, beta = 2, gamma = 3), ',",
    "    'model = kid, parallel = 2, .opts = list(backend = \"inline\")); 1L'))))",
    "  if (req$n > 2L) return(paste0('NEXT [', req$last_user, ']'))",
    "  ops = Filter(function(m) identical(m$role, 'operator'), req$messages)",
    "  if (!length(ops)) return('PARENT MISSING STEER')",
    "  text = sub('^.*working: ', '', gptr:::msg_text(ops[[1L]]))",
    "  paste0('PARENT STEER [', text, ']')",
    "})",
    "main = peter(model = fake, mode = 'auto', envir = new.env())",
    "ops = sum(vapply(kid$log$requests, function(req) sum(vapply(req$messages,",
    "  function(m) identical(m$role, 'operator'), NA)), 0L))",
    "cat('CHILD OPERATORS ', ops, '\\n', sep = '')",
    "cat('ROW CLEARED ', is.null(gptr:::the$live_row), '\\n', sep = '')"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "\u203a" else ">>"
  sep = if (utf8) " \u00b7 " else " - "
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait(paste0("sub-agents 0/3 done", sep, "2 active", sep, "1 queued")))
  expect_true(pty$wait("active  alpha (kid/kid-1), beta (kid/kid-1)"))
  expect_true(pty$wait("queued  gamma (kid/kid-1)"))
  expect_true(pty$wait("sub-agent alpha r"))
  expect_true(pty$wait("keys show when r returns"))
  # Typed during a child tool, then read while child models wait: it still steers the parent.
  pty$paste("use-median")
  expect_true(pty$wait(paste0(person, " use-median")))
  pty$send("\r")
  expect_true(pty$wait("1 queued"))
  pty$paste("next-draft")
  expect_true(pty$wait(paste0(person, " next-draft"), timeout = 5), info = pty$all)
  expect_true(pty$wait("PARENT STEER [use-median]", timeout = 20), info = pty$all)
  expect_true(pty$wait("peter[auto]> "))
  pty$send("\r")
  expect_true(pty$wait("NEXT [next-draft]", timeout = 5), info = pty$all)
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD OPERATORS 0"))
  expect_true(pty$wait("ROW CLEARED TRUE"))
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("PRIVATE-CHILD-REPORT"), 0L)
  expect_identical(pty$seen("PARENT STEER [use-median]"), 1L)
  expect_identical(pty$seen("NEXT [next-draft]"), 1L)
  rows = term_rows(pty$all)
  done = grep("sub-agent .* done", rows)
  expect_length(done, 3L)
  expect_true(any(grepl("sub-agents 2/3", rows, fixed = TRUE)))
})

test_that("a terminal direct fanout prints each report once and leaves no live row", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 80L)",
    "kid = gptr_fake_provider(list(list(text = 'DIRECT-CHILD-REPORT', delay = 2)),",
    "                         name = 'direct-kid')"
  ), term = "xterm")
  expect_true(pty$wait("CHILD DONE", timeout = 120))
  expect_true(pty$wait("> "))
  # At R's actual prompt, so the normal autoprint path must display this visible result.
  pty$send(paste0("peter('each', list(alpha = 1, beta = 2, gamma = 3), model = kid, ",
                   "parallel = 2, mode = 'auto', .opts = list(backend = 'inline'))\r"))
  expect_true(pty$wait("active  alpha (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("beta (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("queued  gamma (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("sub-agents 2/3"))
  expect_true(pty$wait("sub-agent gamma done (3/3)"))
  expect_true(pty$wait("DIRECT-CHILD-REPORT"))
  expect_true(pty$wait("> "))
  expect_identical(pty$seen("DIRECT-CHILD-REPORT"), 3L)
  expect_match(pty$all, "\r[^\r\n]*sub-agents 2/3[^\r\n]*\033\\[K")
  pty$send(paste0("cat('ROW CLEARED ', is.null(gptr:::the$live_row), '\\n', sep = ''); ",
                   "gptr:::reactor_pump(timeout = 1.2); cat('IDLE AGAIN\\n')\r"))
  expect_true(pty$wait("ROW CLEARED TRUE"))
  expect_true(pty$wait("IDLE AGAIN\r\n"))
  expect_false(grepl("sub-agents", pty$pending(), fixed = TRUE))
})
