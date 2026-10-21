source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# Compare the documented row values with a canonical timezone attribute.
du_rows = function(s) {
  row = usage_conform(session_data(s)$usage)
  row$started = .POSIXct(as.numeric(row$started), tz = "UTC")
  row
}

du_detach = function(s) {
  if (!is.null(s$file)) lock_release(lock_path(s$file))
  live_forget(s)
  invisible(NULL)
}

du_restore = function(s) {
  file = s$file
  du_detach(s)
  gptr_resume(file, envir = new.env())
}

du_row = function(s, request = "q-durable", agent = "stats") {
  d = session_data(s)
  usage_conform(data.frame(
    request_id = request, session = d$id, agent = agent,
    parent_id = d$parent_id %||% NA_character_, provider = "fake", model = "fake-1",
    route = "api", input = 0, output = 7, cache_read = NA_real_, cache_write_5m = 0,
    cache_write_1h = NA_real_, reasoning = NA_real_, images = 0, cost = 1.25,
    tier = "default", stop_reason = "stop", started = .POSIXct(172800.25, tz = "UTC"),
    seconds = 0.125, estimated = FALSE, multiplier = 1.75, stringsAsFactors = FALSE))
}

du_entry = function(s, row) {
  msg = msg_assistant("private charge", api = "fake", provider = "fake", model = "fake-1",
                      usage = usage_new(input = 999, output = 999), request_id = row$request_id)
  entry = entry_message(msg)
  entry$gptr = list(usage = usage_row_store(row))
  entry
}

test_that("ordinary child charges recover their exact row and originating agent", {
  skip_on_cran()
  local_store()
  local_permissive()
  local_fake_provider(list(fake_text("answer", usage = usage_new(input = 0, output = 7))))
  root = test_session()
  child = test_session(kind = "child", parent = root)
  run_text(child, "question", list(agent = "stats"))
  expected = du_rows(child)
  grouped = gptr_usage(root, by = "agent")
  file = child$file
  got = du_restore(child)
  expect_identical(du_rows(got), expected)
  expect_identical(got$usage$agent, "stats")
  expect_identical(got$usage$request_id, expected$request_id)
  expect_identical(gptr_usage(root, by = "agent"), grouped)
  expect_identical(gptr_usage(list(root, got)), gptr_usage(root))
  expect_identical(gptr_resume(file, envir = new.env()), got)
  entries = store_read(file)$entries
  charged = Filter(function(e) {
    identical(e$type, "message") && identical(e$message$role, "assistant")
  }, entries)
  expect_named(charged[[1L]]$gptr$usage, usage_columns)
  expect_identical(entry_messages(charged[[1L]]), list(charged[[1L]]$message))
  expect_null(charged[[1L]]$message$gptr)
})

test_that("a fresh root retains nested team and fanout charges without child files", {
  skip_on_cran()
  local_store()
  local_gptr_options(mode = "auto", model = "fake/fake-1")
  local_permissive()
  local_fake_provider(function(request) {
    if (identical(request$last_user, "check")) return("team answer")
    if (identical(request$last_user, "each")) return("element answer")
    if (length(request$last_results)) return("done")
    fake_tool("r", code = paste0(
      "team = peter(\"check\", agents = list(",
      "stats = agent(model = \"fake/fake-1\"), code = agent(model = \"fake/fake-1\")))\n",
      "fan = peter(\"each\", list(p = 1, q = 2), parallel = 2)"))
  })
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  home = new.env()
  home$canary = list(values = 1:3)
  root = peter("outer", envir = home)
  expected = du_rows(root)
  cost = root$cost
  grouped = gptr_usage(root, by = "agent")
  expect_identical(nrow(expected), 6L)
  expect_true(all(c("stats", "code") %in% expected$agent))
  expect_identical(home$canary, list(values = 1:3))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  kids = c(root$children, home$team$children, home$fan$children)
  files = unique(vapply(kids, function(s) s$file %||% "", ""))
  for (s in kids) du_detach(s)
  unlink(files[nzchar(files)])
  expect_false(any(file.exists(files[nzchar(files)])))
  got = du_restore(root)
  expect_identical(du_rows(got), expected)
  expect_identical(got$cost, cost)
  expect_identical(gptr_usage(got, by = "agent"), grouped)
  expect_length(session_data(got)$children, 0L)
  expect_identical(gptr_usage(list(got, got)), gptr_usage(got))
})

test_that("canonical charge recovery preserves historical prices and unknown observations", {
  skip_on_cran()
  local_store()
  s = test_session()
  row = du_row(s)
  entry = du_entry(s, row)
  entry$message$request_id = NULL
  session_append(s, entry)
  entries = store_read(s$file)$entries
  got = testthat::with_mocked_bindings(
    rebuild_usage(entries, session_data(s)),
    usage_row = function(...) stop("legacy recomputation called"),
    provider_preflight = function(...) stop("current pricing called"))
  expect_identical(got, row)
  expect_identical(got$input, 0)
  expect_true(is.na(got$cache_read))
  expect_identical(got$cost, 1.25)
  expect_identical(got$multiplier, 1.75)
  expect_identical(got$started, .POSIXct(172800.25, tz = "UTC"))
})

test_that("checkpoint and aborted child charges survive fresh ancestor recovery", {
  skip_on_cran()
  local_store()
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  root = test_session()
  child = test_session(kind = "child", parent = root)
  target = list(api = "fake", provider = "fake", id = "fake-1")
  context = list(request_id = "q-checkpoint-durable")
  stub = list(id = "run-checkpoint", opts = list(agent = "checkpoint"))
  compact_charge(child, target, context,
                  msg_assistant("checkpoint", api = "fake", provider = "fake",
                                model = "fake-1", usage = usage_new(input = 0, output = 2)),
                  .POSIXct(172800, tz = "UTC"), stub)
  run = run_start(child, msg_user("hang"), list(agent = "cancelled"))
  run_wait(list(run), timeout = 0.2)
  expect_true(run$busy)
  expect_false(run$request_closed)
  run_abort(run)
  expected = du_rows(child)
  expect_identical(nrow(expected), 2L)
  expect_identical(expected$agent, c("checkpoint", "cancelled"))
  expect_true(is.na(expected$cost[[2L]]))
  expect_true(is.na(expected$input[[2L]]))
  child_got = du_restore(child)
  expect_identical(du_rows(child_got), expected)
  root_got = du_restore(root)
  expect_identical(du_rows(root_got), expected)
  expect_identical(attr(gptr_usage(list(root_got, child_got)), "totals")[["requests"]], 2)
})

test_that("failed ordinary replies retain one exact canonical charge after resume", {
  skip_on_cran()
  local_store()
  local_permissive()
  local_fake_provider(list(fake_error("invalid request", status = 400L)))
  s = test_session()
  run_text(s, "fail", list(agent = "review"))
  expect_identical(s$status, "error")
  expected = du_rows(s)
  expect_identical(nrow(expected), 1L)
  got = du_restore(s)
  expect_identical(du_rows(got), expected)
  expect_identical(got$usage$agent, "review")
})

test_that("exact canonical duplicates count once and conflicting duplicates fail", {
  skip_on_cran()
  local_store()
  s = test_session()
  row = du_row(s)
  a = du_entry(s, row)
  b = a
  b$gptr$usage$started = as.numeric(row$started)
  expect_identical(rebuild_usage(list(a, b), session_data(s)), row)
  b$gptr$usage$cost = 2
  expect_error(rebuild_usage(list(a, b), session_data(s)), class = "gptr_error_invalid_argument")
  expect_error(rebuild_usage(list(b, a), session_data(s)), class = "gptr_error_invalid_argument")
})

test_that("mixed legacy messages use fallback only when the private row is absent", {
  skip_on_cran()
  local_store()
  local_fake_provider(list("unused"))
  s = test_session()
  row = du_row(s)
  canonical = du_entry(s, row)
  legacy = entry_message(msg_assistant("old", api = "fake", provider = "fake", model = "fake-1",
                                       request_id = "q-legacy", usage = usage_new(input = 1)))
  duplicate = canonical
  duplicate$gptr = NULL
  got = rebuild_usage(list(duplicate, legacy, canonical), session_data(s))
  expect_identical(nrow(got), 2L)
  expect_identical(usage_conform(got[got$request_id == row$request_id, , drop = FALSE]), row)
  expect_identical(got$agent[got$request_id == "q-legacy"], "main")
  canonical$gptr$usage = list(request_id = row$request_id)
  expect_error(rebuild_usage(list(canonical), session_data(s)),
               class = "gptr_error_invalid_argument")
  canonical$gptr["usage"] = list(NULL)
  expect_error(rebuild_usage(list(canonical), session_data(s)),
               class = "gptr_error_invalid_argument")
})

test_that("durable rows reject malformed scalars foreign identities and excessive bytes", {
  skip_on_cran()
  local_store()
  s = test_session()
  row = du_row(s)
  stored = usage_row_store(row)
  expect_identical(usage_row_restore(json_decode(json_encode(stored))), row)
  for (bad in list(stored[-1L], c(stored, list(extra = 1)), unname(stored),
                   c(stored, stored[1L]))) {
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  for (key in c("input", "cost", "started", "estimated", "agent")) {
    bad = stored
    bad[[key]] = list(1, 2)
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  for (value in list(Inf, NaN, -1, "1")) {
    bad = stored
    bad$cost = value
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  bad = stored
  bad$agent = paste(rep("x", 65537L), collapse = "")
  expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  bad = du_entry(s, row)
  bad$gptr$usage$session = "foreign"
  expect_error(rebuild_usage(list(bad), session_data(s)), class = "gptr_error_invalid_argument")
  bad = du_entry(s, row)
  bad$gptr$usage$parent_id = "foreign"
  expect_error(rebuild_usage(list(bad), session_data(s)), class = "gptr_error_invalid_argument")
})

test_that("ancestor accounting validates complete bounded receiver lineage", {
  skip_on_cran()
  local_store()
  root = test_session()
  middle = test_session(kind = "team", parent = root)
  child = test_session(kind = "child", parent = middle)
  row = du_row(child)
  usage_add_durable(child, row)
  expected = du_rows(root)
  entries = Filter(function(e) identical(e$custom_type, "gptr.usage"),
                   store_read(root$file)$entries)
  expect_length(entries, 1L)
  expect_length(entry_messages(entries[[1L]]), 0L)
  data = entries[[1L]]$data
  expect_identical(unlist(data$lineage, use.names = FALSE), c(child$id, middle$id, root$id))
  expect_identical(rebuild_usage(entries, session_data(root)), expected)
  for (lineage in list(list(child$id, middle$id), list(child$id, root$id, middle$id),
                       list(child$id, middle$id, child$id, root$id),
                       rep(list(child$id), 33L), list("foreign", middle$id, root$id),
                       list(child$id, "foreign", root$id))) {
    bad = entries
    bad[[1L]]$data$lineage = lineage
    expect_error(rebuild_usage(bad, session_data(root)), class = "gptr_error_invalid_argument")
  }
  bad = entries
  bad[[1L]]$data$receiver_parent = "foreign"
  expect_error(rebuild_usage(bad, session_data(root)), class = "gptr_error_invalid_argument")
  expect_identical(du_rows(middle), expected)
})

test_that("forks exclude inherited charges while rewind retains incurred charges", {
  skip_on_cran()
  local_store()
  local_permissive()
  local_fake_provider(list("one", "two", "fork"))
  s = test_session()
  run_text(s, "one", list(agent = "stats"))
  first = session_data(s)$leaf
  run_text(s, "two", list(agent = "code"))
  expected = du_rows(s)
  f = gptr_fork(s)
  run_text(f, "branch", list(agent = "branch"))
  own = du_rows(f)
  got_fork = du_restore(f)
  expect_identical(du_rows(got_fork), own)
  expect_false(any(expected$request_id %in% got_fork$usage$request_id))
  # The tree branch changes, while recovery must read all incurred requests.
  gptr_rewind(s, to = first, restore = "conversation")
  got = du_restore(s)
  expect_identical(du_rows(got), expected)
})

test_that("ancestor accounting append failure is fatal and never reports durable success", {
  local_store()
  root = test_session()
  child = test_session(kind = "child", parent = root)
  row = du_row(child)
  original = structure(list(message = "accounting store denied", call = NULL),
                        class = c("du_store_error", "error", "condition"))
  got = testthat::with_mocked_bindings(
    tryCatch(usage_add_durable(child, row), error = identity),
    session_append = function(s, entry) stop(original))
  expect_identical(got, original)
  expect_identical(du_rows(root), row)
  expect_identical(du_rows(child), row)
})

test_that("aborted accounting failure is retained after complete abort settlement", {
  skip_on_cran()
  local_store()
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  run = run_start(s, msg_user("hang"))
  run_wait(list(run), timeout = 0.2)
  expect_true(run$busy)
  expect_false(run$request_closed)
  original = structure(list(message = "accounting failed", call = NULL),
                        class = c("du_store_error", "error", "condition"))
  testthat::with_mocked_bindings(run_abort(run),
                                usage_add_durable = function(s, row) stop(original))
  expect_true(run$settled)
  expect_null(session_live(s)$run)
  expect_identical(s$status, "error")
  expect_true(run$signal$aborted)
  expect_identical(run$signal$reason, "user")
  expect_length(session_data(s)$queue$steer, 0L)
  expect_identical(run$accounting_error, original)
  expect_identical(run$signal$accounting_error, original)
  expect_s3_class(run$signal$condition, "gptr_error_internal")
  caught = tryCatch(gateway_signal(s, run), error = identity)
  expected = run$condition
  expected$session = s
  expect_identical(caught, expected)
})

test_that("checkpoint accounting failure preserves an earlier condition and completes settlement", {
  skip_on_cran()
  local_store()
  local_fake_provider(list("unused"))
  s = test_session()
  run = test_run(s)
  original = gptr_condition("original provider failure", "provider", "error")
  accounting = structure(list(message = "accounting failed", call = NULL),
                          class = c("du_store_error", "error", "condition"))
  run$condition = original
  run$compact_finish = function() stop(accounting)
  run_settle(run, "error")
  expect_true(run$settled)
  expect_null(session_live(s)$run)
  expect_identical(run$condition, original)
  expect_identical(run$signal$condition, original)
  expect_identical(run$accounting_error, accounting)
  expect_identical(session_data(s)$accounting_error, accounting)
  expect_identical(s$status, "error")
  caught = tryCatch(gateway_signal(s, run), error = identity)
  expected = original
  expected$session = s
  expect_identical(caught, expected)
})

test_that("aborted reported zero positive and unknown costs remain exact after recovery", {
  skip_on_cran()
  for (cost in c(0, 0.25, NA_real_)) {
    local_store()
    local_permissive()
    local_fake_provider(list(list(hang = TRUE)))
    s = test_session()
    run = run_start(s, msg_user("hang"), list(agent = "interrupted"))
    run_wait(list(run), timeout = 0.2)
    expect_true(run$busy)
    expect_false(run$request_closed)
    partial = msg_assistant("partial", api = "fake", provider = "fake", model = "fake-1",
                            usage = usage_new(input = 0, output = 3, cache_read = NA_real_,
                                              cost = list(total = cost)))
    testthat::with_mocked_bindings(run_abort(run), run_partial_message = function(run) partial)
    expected = du_rows(s)
    expect_identical(nrow(expected), 1L)
    expect_identical(expected$cost, cost)
    expect_identical(expected$input, 0)
    expect_true(is.na(expected$cache_read))
    run_abort(run)
    expect_identical(du_rows(s), expected)
    got = du_restore(s)
    expect_identical(du_rows(got), expected)
  }
})

test_that("durable charging refuses live ancestry cycles and excessive depth before mutation", {
  skip_on_cran()
  local_store()
  root = test_session()
  child = test_session(kind = "child", parent = root)
  root_data = session_data(root)
  root_data$parent_id = child$id
  before = du_rows(child)
  expect_error(usage_add_durable(child, du_row(child)), class = "gptr_error_invalid_argument")
  expect_identical(du_rows(child), before)
  root_data$parent_id = NULL
  cur = root
  for (i in seq_len(32L)) cur = test_session(kind = "child", parent = cur)
  expect_error(usage_add_durable(cur, du_row(cur)), class = "gptr_error_invalid_argument")
  expect_identical(nrow(session_data(cur)$usage), 0L)
  expect_null(root$file)
})


test_that("durable fractional charges preserve exact numeric bits after a fresh disk resume", {
  skip_on_cran()
  local_store()
  s = test_session()
  row = du_row(s)
  row$cost = 0.1
  row$seconds = 0.096337795257568359
  row$multiplier = 1 + .Machine$double.eps
  row$started = .POSIXct(1791799091.5259881, tz = "UTC")
  session_append(s, du_entry(s, row))
  got = du_restore(s)
  expect_identical(du_rows(got), row)
  expect_identical(got$cost, row$cost)
  entry = store_read(got$file)$entries[[1L]]
  expect_identical(usage_row_restore(entry$gptr$usage), row)
  expect_true(is.na(got$usage$cache_read))
  expect_null(entry$gptr$usage$cache_read)
})

test_that("durable numeric recovery preserves finite boundaries and legacy numeric records", {
  skip_on_cran()
  local_store()
  s = test_session()
  values = c(0, -0.0, .Machine$double.xmin * .Machine$double.eps,
             .Machine$double.xmin, .Machine$double.xmax, 1 + .Machine$double.eps, 0.1)
  for (value in values) {
    row = du_row(s)
    for (key in usage_num_columns) row[[key]] = value
    row$started = .POSIXct(-value, tz = "UTC")
    got = usage_row_restore(json_decode(json_encode(usage_row_store(row))))
    expect_identical(got, row)
    expect_identical(writeBin(got$cost, raw(), size = 8L, endian = "big"),
                     writeBin(row$cost, raw(), size = 8L, endian = "big"))
    expect_identical(writeBin(as.numeric(got$started), raw(), size = 8L, endian = "big"),
                     writeBin(as.numeric(row$started), raw(), size = 8L, endian = "big"))
  }
  row = du_row(s)
  legacy = as.list(row)
  legacy$started = as.numeric(row$started)
  legacy = lapply(legacy, function(value) if (is.na(value)) NULL else value)
  legacy = usage_row_restore(json_decode(json_encode(legacy)))
  expect_identical(legacy, row)
  expect_identical(usage_canonical_unique(list(row, legacy)), row)
  stored = json_decode(json_encode(usage_row_store(row)))
  expect_identical(stored$cost, list(ieee754 = "3ff4000000000000"))
  expect_identical(stored$started, list(ieee754 = "4105180200000000"))
})

test_that("durable numeric tags reject nonfinite malformed and wrong-field values", {
  skip_on_cran()
  local_store()
  s = test_session()
  row = du_row(s)
  stored = usage_row_store(row)
  bad_values = list(
    "1", list(ieee754 = "1"), list(ieee754 = "00000000000000000"),
    list(ieee754 = "000000000000000g"), list(ieee754 = "3FF4000000000000"),
    list(ieee754 = NA_character_), list(ieee754 = 1),
    list(ieee754 = c("3ff4000000000000", "3ff4000000000000")),
    list(ieee754 = "3ff4000000000000", extra = TRUE),
    list(ieee754 = "3ff4000000000000", ieee754 = "3ff4000000000000"),
    list("3ff4000000000000"), list(unknown = "3ff4000000000000"),
    list(ieee754 = "7ff0000000000000"), list(ieee754 = "fff0000000000000"),
    list(ieee754 = "7ff8000000000000"), list(ieee754 = "bff0000000000000"))
  for (value in bad_values) {
    bad = stored
    bad$cost = value
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  for (key in c("started", "estimated", "agent")) {
    bad = stored
    bad[key] = list(NULL)
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  for (key in c("estimated", "agent")) {
    bad = stored
    bad[[key]] = stored$cost
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
  for (bits in c("7ff0000000000000", "fff0000000000000", "7ff8000000000000")) {
    bad = stored
    bad$started = list(ieee754 = bits)
    expect_error(usage_row_restore(bad), class = "gptr_error_invalid_argument")
  }
})
