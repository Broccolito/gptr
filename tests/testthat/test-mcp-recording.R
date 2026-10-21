source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

mcp_record_entries = function(s) {
  Filter(function(e) {
    identical(e$type, "custom") && identical(e$custom_type, "gptr.mcp_r")
  }, session_data(s)$entries)
}

local_mcp_record_probe = function(.env = parent.frame()) {
  probe = gptr_tool("record_probe", "Serve R through the same dispatcher as a native CLI.",
                    parameters = list(type = "object", required = I("code"),
                                      properties = list(code = list(type = "string"))),
                    execute = function(input, ctx) {
                      msg = mcp_test_msg("tools/call", list(name = "r", arguments = input))
                      ans = mcp_dispatch_local(msg, ctx$session)$result
                      gptr_tool_result(ans$content[[1L]]$text, is_error = ans$isError)
                    })
  off = gptr_register(probe)
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

test_that("relayed MCP code records once and replays a callable result without a CLI", {
  skip_on_cran()
  root = local_project()
  local_gptr_options(record = "auto", replay = "auto", mode = "auto")
  f = local_fake_cli("codex", "mcp-return")
  path = file.path(root, "native.R")
  writeLines(c("dat = datasets::mtcars", paste0("res = peter(\"Fit the public data\", model = ",
                                                dQuote(f$model, q = FALSE),
                                                ", mode = \"auto\")")), path)
  work = new.env(parent = globalenv())
  gptr_source(path, replay = "record", envir = work)
  expected = stats::coef(stats::lm(mpg ~ wt + hp, data = datasets::mtcars))
  expect_equal(work$res$value, expected)
  expect_equal(work$beta, expected)
  expect_s3_class(work$fit, "lm")
  trace = mcp_record_entries(work$res)
  expect_length(trace, 1L)
  if (length(trace)) {
    expect_match(trace[[1L]]$data$code, "fit = stats::lm", fixed = TRUE)
    expect_identical(trace[[1L]]$data$status, "ok")
  }
  before = readLines(path, encoding = "UTF-8")
  expect_true(any(grepl("fit = stats::lm", before, fixed = TRUE)))
  expect_true(any(grepl("beta = stats::coef", before, fixed = TRUE)))
  expect_false(any(grepl("gptr_return", before, fixed = TRUE)))
  expect_identical(length(fake_log(f, "mcp")), 1L)
  requests = length(fake_argv(f))
  again = new.env(parent = globalenv())
  expect_no_error(gptr_source(path, replay = "replay", envir = again))
  expect_s3_class(again$fit, "lm")
  expect_equal(again$beta, expected)
  expect_equal(again$res$value, expected)
  expect_identical(length(fake_argv(f)), requests)
  expect_identical(length(fake_log(f, "mcp")), 1L)
  expect_identical(readLines(path, encoding = "UTF-8"), before)
})

test_that("SDK-dispatched successful R uses approved code and the existing secret history rules", {
  skip_on_cran()
  root = local_project()
  local_gptr_options(record = "auto", replay = "auto", mode = "auto")
  local_mcp_record_probe()
  local_user_dirs()
  secret = "synthetic-mcp-recording-key-123456789"
  secret_register(secret, "MCP_RECORD_TEST_KEY", "test")
  permitted = paste0('key = "', secret, '"\nanswer = 42\nanswer')
  check = perm_check
  local_mocked_bindings(perm_check = function(call, run) {
    if (identical(call$name, "r")) return(list(decision = "allow", input = list(code = permitted)))
    check(call, run)
  })
  fake = local_fake_provider(list(fake_tool("record_probe", code = "answer = -1"), "Done."))
  path = file.path(root, "sdk.R")
  writeLines('res = peter("Use the SDK bridge", mode = "auto")', path)
  local_gptr_options(model = paste0(fake$id, "/", fake$models[[1L]]$id))
  work = new.env(parent = globalenv())
  gptr_source(path, replay = "record", envir = work)
  expect_identical(work$answer, 42)
  trace = mcp_record_entries(work$res)
  expect_length(trace, 1L)
  txt = readLines(path, encoding = "UTF-8")
  expect_true(any(grepl('key = Sys.getenv("MCP_RECORD_TEST_KEY")', txt, fixed = TRUE)))
  expect_true(any(grepl("#> [1] 42", txt, fixed = TRUE)))
  expect_false(any(grepl("answer = -1", txt, fixed = TRUE)))
  expect_false(any(grepl(secret, txt, fixed = TRUE)))
  expect_false(grepl(secret, json_encode(session_data(work$res)$entries), fixed = TRUE))
  expect_identical(sum(grepl("answer = 42", txt, fixed = TRUE)), 1L)
})

test_that("failed, plan, non-recording and idle served R do not add executable history", {
  skip_on_cran()
  root = local_project()
  local_gptr_options(record = "auto", replay = "auto", mode = "auto")
  local_mcp_record_probe()
  cases = list(
    failed = list(code = "partial = 1\nstop('not successful')", mode = "auto", record = TRUE),
    plan = list(code = "scratch = 1", mode = "plan", record = TRUE),
    off = list(code = "unrecorded = 1", mode = "auto", record = FALSE))
  for (nm in names(cases)) {
    z = cases[[nm]]
    fake = local_fake_provider(list(fake_tool("record_probe", code = z$code), "Done."),
                               name = paste0("record-", nm))
    path = file.path(root, paste0(nm, ".R"))
    ref = paste0(fake$id, "/", fake$models[[1L]]$id)
    line = paste0('res = peter("Serve R", model = "', ref, '", mode = "', z$mode,
                   '", .opts = list(record = ', if (z$record) "TRUE" else "FALSE", "))")
    writeLines(line, path)
    work = new.env(parent = globalenv())
    gptr_source(path, replay = "record", envir = work)
    expect_length(mcp_record_entries(work$res), 0L)
    expect_false(any(readLines(path) %in% c("partial = 1", "scratch = 1", "unrecorded = 1")),
                 info = nm)
    if (identical(nm, "plan")) expect_false(exists("scratch", envir = work, inherits = FALSE))
    # Once settled, the same session's standalone server retains no automatic recording.
    before = readLines(path)
    msg = mcp_test_msg("tools/call", list(name = "r", arguments = list(code = "idle = 2")))
    mcp_dispatch_local(msg, work$res)
    expect_length(mcp_record_entries(work$res), 0L)
    expect_identical(readLines(path), before, info = nm)
  }
})

test_that("a native execution trace belongs only to its still-active document owner", {
  root = local_project()
  own_env = new.env(parent = baseenv())
  owner = session_new("fake/fake-1", "auto", home = own_env)
  other = session_new("fake/fake-1", "auto", home = new.env(parent = baseenv()))
  run = run_new(owner, list(doc = list(path = file.path(root, "owned.R"))), NULL)
  live = session_live(owner)
  live$run = run
  evaluate = function(target) {
    mcp_serve_r(list(code = "x = 1"), own_env, run, target)
  }
  evaluate(other)
  expect_length(mcp_record_entries(other), 0L)
  expect_length(mcp_record_entries(owner), 0L)
  evaluate(owner)
  expect_length(mcp_record_entries(owner), 1L)
  expect_named(mcp_record_entries(owner)[[1L]]$data, c("code", "record", "status", "outputs"))
  run$signal$aborted = TRUE
  evaluate(owner)
  expect_length(mcp_record_entries(owner), 1L)
  run$signal$aborted = FALSE
  run$settled = TRUE
  evaluate(owner)
  expect_length(mcp_record_entries(owner), 1L)
  run$settled = FALSE
  live$run = NULL
  evaluate(owner)
  expect_length(mcp_record_entries(owner), 1L)
  live$run = run
  run$opts$doc = NULL
  evaluate(owner)
  expect_length(mcp_record_entries(owner), 1L)
  expect_length(mcp_record_entries(other), 0L)
  expect_identical(own_env$x, 1)
})
