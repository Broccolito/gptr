source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

usage_fixture = function(session, request_id, cost = 0, input = 100, agent = "main",
                         route = "api") {
  usage_conform(data.frame(request_id = request_id, session = session, agent = agent,
                           parent_id = NA_character_, provider = "fake", model = "fake-1",
                           route = route, input = input, output = 10, cache_read = 0,
                           cache_write_5m = 0, cache_write_1h = 0, reasoning = 0, images = 0,
                           cost = cost, tier = "default", stop_reason = "stop",
                           started = Sys.time(), seconds = 1, estimated = FALSE, multiplier = 1,
                           stringsAsFactors = FALSE))
}

test_that("usage_columns are the 21 section 4.3 columns of P05's usage_empty(), in order", {
  u = usage_empty()
  expect_identical(names(u), usage_columns)
  expect_length(usage_columns, 21L)
  expect_identical(nrow(u), 0L)
  expect_s3_class(u$started, "POSIXct")
})

test_that("usage_conform() orders the columns, fills missing ones and fixes the types", {
  row = data.frame(model = "fake-1", request_id = "q000000000001", input = 5L, output = 2L,
                   started = 0, stringsAsFactors = FALSE)
  u = usage_conform(row)
  expect_identical(names(u), usage_columns)
  expect_identical(u$request_id, "q000000000001")
  expect_true(is.na(u$session))
  expect_identical(u$input, 5)
  # IC-74 (07-local-ollama.md section 5, D-015): a cost the row does not carry is unknown, NA,
  # never a known zero
  expect_identical(u$cost, NA_real_)
  expect_s3_class(u$started, "POSIXct")
  expect_identical(nrow(usage_conform(usage_empty())), 0L)
})

test_that("usage_conform() keeps missing usage unknown and known zeros known (IC-74)", {
  u = usage_conform(data.frame(request_id = "q1", input = 0, cost = 0,
                               stringsAsFactors = FALSE))
  expect_identical(u$input, 0)
  expect_identical(u$cost, 0)
  absent = c("output", "cache_read", "cache_write_5m", "cache_write_1h", "reasoning", "images")
  expect_identical(unlist(u[absent], use.names = FALSE), rep(NA_real_, 6L))
  expect_identical(u$tier, NA_character_)
  expect_identical(u$estimated, NA)
  expect_identical(u$multiplier, NA_real_)
  # an all-NA logical column (a bare NA) becomes the typed NA of its section 4.3 column
  v = usage_conform(list(request_id = "q2", session = NA, cost = NA, estimated = FALSE,
                         started = NA))
  expect_identical(v$session, NA_character_)
  expect_identical(v$cost, NA_real_)
  expect_identical(v$estimated, FALSE)
  expect_s3_class(v$started, "POSIXct")
  expect_true(is.na(v$started))
})

test_that("usage_conform() passes P05's usage_row() rows through unchanged", {
  started = as.POSIXct("2026-10-01 12:00:00", tz = "UTC")
  msg = list(role = "assistant", content = list(), stop_reason = "stop")
  row_of = function(msg) {
    usage_row(msg, session = "s0123456789", agent = "main", parent_id = NA_character_,
              started = started, seconds = 1.5, multiplier = 1)
  }
  # nothing observed and no model to price: P05 records unknown tokens and an unknown cost
  unknown = row_of(msg)
  expect_identical(usage_conform(unknown), unknown)
  expect_true(all(is.na(unlist(unknown[usage_token_columns], use.names = FALSE))))
  # observed tokens (usage_new()'s omitted fields are P05's legacy zeros) and no price evidence
  msg$usage = usage_new(input = 5, output = 2)
  known = row_of(msg)
  expect_identical(usage_conform(known), known)
  expect_identical(known$cache_read, 0)
  expect_identical(known$cost, NA_real_)
  both = usage_conform(rbind(known, unknown))
  expect_identical(nrow(both), 2L)
  expect_identical(usage_conform(both), both)
  expect_identical(both$input, c(5, NA))
})

test_that("usage_conform() refuses values it would otherwise coerce or invent", {
  bad = function(...) {
    expect_error(usage_conform(data.frame(request_id = "q1", ..., stringsAsFactors = FALSE)),
                 class = "gptr_error_invalid_argument")
  }
  bad(input = "5")
  bad(cost = -1)
  bad(seconds = Inf)
  bad(output = NaN)
  bad(session = 1)
  bad(estimated = "yes")
  bad(started = "2026-10-01")
  # a known start must be finite, as P05's usage_time() and usage_rows_check() require
  bad(started = Inf)
  bad(started = -Inf)
  bad(started = NaN)
  bad(started = .POSIXct(Inf, tz = "UTC"))
  expect_error(usage_conform(data.frame(request_id = 1)), class = "gptr_error_invalid_argument")
  expect_error(usage_conform("q1"), class = "gptr_error_invalid_argument")
  # the refusal names the column and what it expects (contract 04 section 2.2)
  err = expect_error(usage_conform(data.frame(request_id = "q1", input = "5",
                                              stringsAsFactors = FALSE)),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "row$input")
  expect_identical(err$expected, "finite nonnegative numbers or NA")
  err = expect_error(usage_conform(data.frame(request_id = "q1", started = Inf)),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "row$started")
})

test_that("usage_conform() refuses a malformed list instead of flattening or recycling it", {
  bad = function(row) {
    err = expect_error(usage_conform(row), class = "gptr_error_invalid_argument")
    expect_identical(err$arg, "row")
  }
  # a nested value would be flattened to `cost.total` and dropped, inventing an unknown cost
  bad(list(request_id = "q1", cost = list(total = 1)))
  bad(list(request_id = c("a", "b", "c"), input = c(1, 2)))
  bad(list(request_id = c("a", "b"), session = "s1"))
  bad(list("q1"))
  bad(list(request_id = "q1", 5))
  bad(list(request_id = "q1", input = 1, input = 2))
  bad(list(request_id = "q1", input = matrix(c(1, 2), 1L)))
  # a NULL element is an absent column; a POSIXlt start is one value, not a nested list
  u = usage_conform(list(request_id = "q1", cost = NULL,
                         started = as.POSIXlt("2026-10-01 12:00:00", tz = "UTC")))
  expect_identical(u$cost, NA_real_)
  expect_identical(as.numeric(u$started), as.numeric(as.POSIXct("2026-10-01 12:00:00", tz = "UTC")))
  expect_identical(nrow(usage_conform(list())), 0L)
})

test_that("usage_totals() sums requests, tokens and cost", {
  u = rbind(usage_fixture("s1", "q1", cost = 0.25), usage_fixture("s1", "q2", cost = 0.5))
  tot = usage_totals(u)
  expect_identical(names(tot), c("requests", "input", "output", "cache_read", "cache_write",
                                 "cost"))
  expect_equal(unname(tot[c("requests", "input", "cost")]), c(2, 200, 0.75))
})

test_that("usage_totals() makes a sum with an unknown value unknown (IC-74)", {
  u = rbind(usage_fixture("s1", "q1", cost = 0.25), usage_fixture("s1", "q2", cost = NA_real_))
  tot = usage_totals(u)
  expect_identical(tot[["cost"]], NA_real_)
  expect_identical(tot[["requests"]], 2)
  expect_identical(tot[["input"]], 200)
  u$cache_write_1h[2L] = NA_real_
  expect_identical(usage_totals(u)[["cache_write"]], NA_real_)
  expect_identical(usage_totals(usage_empty()),
                   c(requests = 0, input = 0, output = 0, cache_read = 0, cache_write = 0,
                     cost = 0))
})

test_that("ledger_empty() has the ledger columns and format_count() abbreviates", {
  expect_identical(names(ledger_empty()), c("request_id", "component", "tokens", "cached"))
  expect_identical(format_count(950), "950")
  expect_identical(format_count(1234), "1.2k")
  expect_identical(format_count(3.4e6), "3.4M")
})

test_that("format_count() prints an unknown count as unknown and rounds across units", {
  expect_identical(format_count(NA_real_), "unknown")
  expect_identical(format_count(c(10, NA)), "unknown")
  expect_identical(format_count(c(400, 550)), "950")
  expect_identical(format_count(numeric()), "0")
  expect_identical(format_count(999.7), "1.0k")
  expect_identical(format_count(999999), "1.0M")
  l = ledger_empty()
  expect_identical(vapply(l, typeof, ""),
                   c(request_id = "character", component = "character", tokens = "double",
                     cached = "logical"))
})

test_that("usage rows roll up to every ancestor and are deduplicated per request", {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  usage_add(child, usage_fixture(session_data(child)$id, "q000000000001", cost = 0.5))
  expect_named(child$usage, usage_columns)
  expect_identical(nrow(root$usage), 1L)
  expect_identical(root$usage$session, session_data(child)$id)
  expect_equal(root$cost, 0.5)
  expect_equal(attr(root$usage, "totals")[["cost"]], 0.5)
  usage_add(child, usage_fixture(session_data(child)$id, "q000000000001", cost = 0.5))
  expect_identical(nrow(root$usage), 1L)
})

test_that("ledger_add() records components and ledger_mark_cached() marks the cached prefix", {
  s = test_session()
  ledger_add(s, "q1", list(t0 = 600, tools = 400, transcript = 300))
  ledger_mark_cached(s, "q1", cache_read = 1000)
  led = session_data(s)$ledger
  expect_identical(led$component, c("t0", "tools", "transcript"))
  expect_identical(led$cached, c(TRUE, TRUE, FALSE))
  expect_null(ledger_add(s, "q2", list()))
})

test_that("an unknown cost or token count rolls up to the ancestors as unknown (IC-74)", {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  cid = session_data(child)$id
  usage_add(child, usage_fixture(cid, "q000000000001", cost = 0.5))
  usage_add(child, usage_fixture(cid, "q000000000002", cost = NA_real_))
  expect_identical(nrow(root$usage), 2L)
  expect_identical(root$cost, NA_real_)
  expect_identical(child$cost, NA_real_)
  tot = attr(root$usage, "totals")
  expect_identical(tot[["cost"]], NA_real_)
  expect_identical(tot[["input"]], 200)
  # a row that leaves its cache columns out has an unknown cache use (D-021)
  usage_add(child, usage_conform(data.frame(request_id = "q000000000003", session = cid,
                                            input = 1, output = 1, cost = 0,
                                            stringsAsFactors = FALSE)))
  expect_identical(attr(root$usage, "totals")[["cache_read"]], NA_real_)
  expect_identical(attr(root$usage, "totals")[["input"]], 201)
})

test_that("usage_add() refuses a row without a request id, the de-duplication key", {
  s = test_session()
  row = usage_fixture(session_data(s)$id, NA_character_, cost = 0.25)
  err = expect_error(usage_add(s, row), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "row$request_id")
  expect_identical(nrow(s$usage), 0L)
  expect_identical(s$cost, 0)
})

test_that("ledger_mark_cached() leaves the cache unknown when the cache read is unknown (IC-74)", {
  s = test_session()
  ledger_add(s, "q1", list(t0 = 600, transcript = 300))
  ledger_add(s, "q2", list(t0 = 600, transcript = 300))
  ledger_mark_cached(s, "q1", cache_read = NA_real_)
  ledger_mark_cached(s, "q2", cache_read = 0)
  led = session_data(s)$ledger
  expect_identical(led$cached, c(NA, NA, FALSE, FALSE))
  expect_null(ledger_mark_cached(s, "q-none", cache_read = 100))
})

test_that("format_cost() prints dollars, and an unknown cost as unknown (IC-74)", {
  expect_identical(format_cost(0.0123), "$0.0123")
  expect_identical(format_cost(c(0.25, 0.5)), "$0.7500")
  expect_identical(format_cost(numeric()), "$0.0000")
  expect_identical(format_cost(0), "$0.0000")
  expect_identical(format_cost(NA_real_), "unknown cost")
  expect_identical(format_cost(c(0.25, NA)), "unknown cost")
})

test_that("the default budget is 2e6 tokens and 5 USD per top-level call; NULL disables (IC-66)", {
  s = test_session()
  lim = run_budget_limits(s, list(), NULL)
  expect_identical(lim$tokens, 2e6)
  expect_identical(lim$cost, 5)
  expect_null(lim$turns)
  lim2 = run_budget_limits(s, list(budget = list(cost = NULL, turns = 3)), NULL)
  expect_null(lim2$cost)
  expect_identical(lim2$turns, 3)
  outer = run_new(s, list(), NULL)
  expect_identical(run_budget_limits(s, list(budget = list(turns = 1)), outer), list(turns = 1))
})

test_that("budget_check() is NULL outside a run and names the kind inside one", {
  s = test_session()
  expect_null(budget_check(s))
  test_run(s, list(budget = list(turns = 1, tokens = 1000)))
  expect_null(budget_check(s))
  expect_identical(budget_check(s, estimate = 2000)$kind, "tokens")
  usage_add(s, usage_fixture(session_data(s)$id, "q-turn"))
  hit = budget_check(s)
  expect_identical(hit$kind, "turns")
  expect_identical(hit$used, 1L)
})

test_that("a child's usage is charged to its root: the root's cost budget stops the child", {
  root = test_session()
  test_run(root, list(budget = list(cost = 5)))
  child = test_session(kind = "child", parent = root)
  # the child's own limits are far above the cost, so only the root's 5 USD can stop it
  test_run(child, list(budget = list(cost = 100, tokens = 1e9)))
  expect_null(budget_check(child))
  usage_add(child, usage_fixture(session_data(child)$id, "q-costly", cost = 6))
  hit = budget_check(child)
  expect_identical(hit$kind, "cost")
  expect_equal(c(hit$budget, hit$used), c(5, 6))
})

test_that("children of a root without a run share one budget through opts$root (IC-66)", {
  team = test_session(kind = "team")
  tid = session_data(team)$id
  a = test_session(kind = "child", parent = team)
  b = test_session(kind = "child", parent = team)
  ra = test_run(a, list(root = tid, budget = list(tokens = 1000)))
  rb = test_run(b, list(root = tid, budget = list(tokens = 1000)))
  # each child keeps only its share; the container holds the one per-call budget
  expect_identical(ra$budget, list(tokens = 1000))
  expect_identical(rb$budget_root, ra$budget_root)
  expect_identical(ra$budget_root$budget$tokens, 1000)
  expect_identical(ra$budget_root$budget$cost, 5)
  usage_add(a, usage_fixture(session_data(a)$id, "q-a", input = 590))
  expect_null(budget_check(a))
  expect_null(budget_check(b))
  usage_add(b, usage_fixture(session_data(b)$id, "q-b", input = 590))
  hit = budget_check(b)
  expect_identical(hit$kind, "tokens")
  expect_equal(c(hit$budget, hit$used), c(1000, 1200))
  expect_identical(budget_check(a)$kind, "tokens")
  # a root that runs is charged through its own run; no pool is made
  top = test_session()
  top_run = test_run(top, list(budget = list(cost = 5)))
  other = test_session()
  ro = test_run(other, list(root = session_data(top)$id))
  expect_null(ro$budget_root)
  expect_identical(ro$budget, list())
  expect_true(top_run$id %in% vapply(run_chain(ro), function(r) r$id, ""))
})

test_that("budget_near is emitted once per kind at 80%", {
  s = test_session()
  ev = local_events("budget_near")
  run = test_run(s, list(budget = list(cost = 1)))
  usage_add(s, usage_fixture(session_data(s)$id, "q1", cost = 0.85))
  budget_near(run)
  budget_near(run)
  near = ev(s)
  expect_length(near, 1L)
  expect_identical(near[[1L]]$kind, "cost")
  expect_equal(near[[1L]]$used, 0.85)
})

# ---------------------------------------------------------------- unknown usage in budgets (IC-74)

test_that("an unknown cost neither reaches nor counts toward a cost budget (IC-74, D-025)", {
  s = test_session()
  sid = session_data(s)$id
  ev = local_events("budget_near")
  run = test_run(s, list(budget = list(cost = 1)))
  # the provider's price is unknown: the request's cost is NA, never a known zero
  usage_add(s, usage_fixture(sid, "q-unpriced", cost = NA_real_))
  expect_identical(s$cost, NA_real_)
  expect_null(budget_check(s))
  budget_near(run)
  expect_length(ev(s), 0L)
  expect_identical(run_used(run)$cost, 0)
  # known costs still count, whatever the unknown ones are
  usage_add(s, usage_fixture(sid, "q-priced", cost = 0.9))
  budget_near(run)
  near = ev(s)
  expect_length(near, 1L)
  expect_equal(near[[1L]]$used, 0.9)
  usage_add(s, usage_fixture(sid, "q-more", cost = 0.2))
  hit = budget_check(s)
  expect_identical(hit$kind, "cost")
  expect_equal(c(hit$budget, hit$used), c(1, 1.1))
})

test_that("a token budget counts the known tokens of a row with an unknown column (IC-74)", {
  s = test_session()
  sid = session_data(s)$id
  run = test_run(s, list(budget = list(tokens = 1000, cost = NULL)))
  row = usage_fixture(sid, "q-cache", input = 900)
  row$cache_read = NA_real_
  usage_add(s, row)
  used = run_used(run)
  # input 900 + output 10 are known; the unknown cache read adds nothing known
  expect_identical(used$tokens, 910)
  expect_identical(used$turns, 1L)
  expect_null(budget_check(s))
  hit = budget_check(s, estimate = 100)
  expect_identical(hit$kind, "tokens")
  expect_identical(hit$used, 910)
  # a request with nothing reported (every token column NA) is one request with no known tokens
  none = usage_fixture(sid, "q-none")
  none[usage_token_columns] = NA_real_
  usage_add(s, none)
  expect_identical(run_used(run)[c("tokens", "turns")], list(tokens = 910, turns = 2L))
})

test_that("budget_check() refuses an estimate that is not a nonnegative number", {
  s = test_session()
  test_run(s)
  for (bad in list(NA_real_, -1, "10", c(1, 2), NULL)) {
    err = expect_error(budget_check(s, estimate = bad), class = "gptr_error_invalid_argument")
    expect_identical(err$arg, "estimate")
  }
  expect_null(budget_check(s, estimate = 0L))
})

test_that("a token budget stops the run before the next request with status budget", {
  local_permissive()
  local_without_builtin("tools")
  ev = local_events(c("budget_exceeded", "budget_near"))
  local_tool("noop", function(input, ctx) "ok")
  fake = local_fake_provider(list(c(fake_tool("noop"), list(usage = usage_new(input = 990,
                                                                              output = 50))),
                                  "never"), name = "fb")
  s = test_session(model = "fb/fb-1")
  run_text(s, "go", list(budget = list(tokens = 1000)))
  expect_identical(s$status, "budget")
  expect_length(fake_requests(fake), 1L)
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_budget_tokens")
  expect_s3_class(cnd, "gptr_error_budget")
  expect_identical(cnd$kind, "tokens")
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, c("budget_near", "budget_exceeded"))
  d = session_data(s)
  last = d$entries[[length(d$entries)]]
  expect_identical(last$custom_type, "gptr.budget")
})

test_that("a budget of 5 USD on a root stops its children (root charging, IC-66)", {
  local_permissive()
  box = new.env()
  local_tool("spawn", function(input, ctx) {
    root = ctx$session
    usage_add(root, usage_fixture(session_data(root)$id, "q-costly", cost = 6))
    child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child", parent = root)
    box$child = child
    run_wait(list(run_start(child, msg_user("child work"))))
    "spawned"
  })
  fake = local_fake_provider(list(fake_tool("spawn"), "never"))
  s = test_session()
  run_text(s, "go", list(budget = list(cost = 5)))
  expect_identical(box$child$status, "budget")
  expect_s3_class(session_data(box$child)$condition, "gptr_error_budget_cost")
  expect_identical(s$status, "budget")
  expect_length(fake_requests(fake), 1L)
})

test_that("interactively a reached budget can be extended by the same amount (ask_human)", {
  local_permissive()
  local_gptr_options(interactive = TRUE)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, select = function(title, choices, default = NULL, ...) 1L)
  })
  local_tool("noop", function(input, ctx) "ok")
  fake = local_fake_provider(list(c(fake_tool("noop"), list(usage = usage_new(input = 990,
                                                                              output = 50))),
                                  "finished"), name = "fb")
  s = test_session(model = "fb/fb-1")
  run_text(s, "go", list(budget = list(tokens = 1000)))
  expect_identical(s$status, "idle")
  expect_length(fake_requests(fake), 2L)
})

# ---------------------------------------------------------------- usage (gptr_usage)

test_that("gptr_usage() aggregates by session, agent, model and route, counting each request once",
          {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  rid = session_data(root)$id
  cid = session_data(child)$id
  usage_add(root, usage_fixture(rid, "q1", cost = 1))
  usage_add(child, usage_fixture(cid, "q2", cost = 2, agent = "stats", route = "plan-cli"))
  u = gptr_usage(list(root, child))
  expect_s3_class(u, "gptr_usage")
  expect_named(u, c("group", "requests", "input", "output", "cache_read", "cache_write", "cost"))
  expect_identical(sort(u$group), sort(c(rid, cid)))
  expect_equal(sum(u$cost), 3)
  expect_equal(attr(u, "totals")[["requests"]], 2)
  expect_identical(sort(gptr_usage(root, by = "agent")$group), c("main", "stats"))
  expect_identical(gptr_usage(root, by = "model")$group, "fake/fake-1")
  expect_identical(sort(gptr_usage(root, by = "route")$group), c("api", "plan-cli"))
})

test_that("gptr_usage() validates x, by and detail", {
  expect_error(gptr_usage(42), class = "gptr_error_invalid_argument")
  expect_error(gptr_usage(by = "colour"), class = "gptr_error_invalid_argument")
  expect_error(gptr_usage(detail = NA), class = "gptr_error_invalid_argument")
})

test_that("gptr_usage() with x = NULL covers the live sessions of this process", {
  s = test_session()
  usage_add(s, usage_fixture(session_data(s)$id, "q-live-1"))
  expect_true(session_data(s)$id %in% gptr_usage()$group)
})

test_that("gptr_usage() counts rows whose group is NA (process-level System 1 rows)", {
  s = test_session()
  usage_add(s, usage_fixture(session_data(s)$id, "q-na", cost = 0.5, agent = NA_character_))
  u = gptr_usage(s, by = "agent")
  expect_identical(u$requests, 1L)
  expect_equal(u$cost, 0.5)
})

test_that("gptr_usage(detail = TRUE) returns the token ledger per request and component", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "hi")
  led = gptr_usage(s, detail = TRUE)
  expect_s3_class(led, "gptr_ledger")
  expect_named(led, c("request_id", "component", "tokens", "cached"))
  expect_true("transcript" %in% led$component)
  expect_identical(unique(led$request_id), s$usage$request_id)
})

# ---------------------------------------------------------------- usage view: unknown usage (IC-74)

test_that("gptr_usage() keeps unknown usage unknown in groups, totals and the footer (IC-74)", {
  s = test_session()
  sid = session_data(s)$id
  usage_add(s, usage_fixture(sid, "q-known", cost = 0.25))
  usage_add(s, usage_fixture(sid, "q-unpriced", cost = NA_real_, agent = "stats"))
  u = gptr_usage(s, by = "agent")
  expect_identical(u$group, c("main", "stats"))
  expect_identical(u$cost, c(0.25, NA))
  expect_identical(u$input, c(100, 100))
  tot = attr(u, "totals")
  expect_identical(tot[["cost"]], NA_real_)
  expect_identical(tot[["requests"]], 2)
  expect_identical(attr(u, "footer"), "2 requests, 200 tokens in, unknown cost")
  printed = paste(utils::capture.output(print(u)), collapse = "\n")
  expect_true(grepl("unknown cost", printed, fixed = TRUE))
  expect_false(grepl("$NA", printed, fixed = TRUE))
  # an unknown cache read makes its group's cache reads and the tokens in unknown, never zero
  row = usage_fixture(sid, "q-cache", cost = 0)
  row$cache_read = NA_real_
  usage_add(s, row)
  u = gptr_usage(s)
  expect_identical(u$group, sid)
  expect_identical(u$cache_read, NA_real_)
  expect_identical(u$input, 300)
  expect_identical(attr(u, "totals")[["cache_read"]], NA_real_)
  expect_identical(attr(u, "footer"), "3 requests, unknown tokens in, unknown cost")
})

test_that("gptr_usage() keeps known zeros and prints an empty view as zero requests", {
  s = test_session()
  u = gptr_usage(s)
  expect_s3_class(u, "gptr_usage")
  expect_identical(nrow(u), 0L)
  expect_identical(vapply(u, typeof, ""),
                   c(group = "character", requests = "integer", input = "double",
                     output = "double", cache_read = "double", cache_write = "double",
                     cost = "double"))
  expect_identical(attr(u, "totals")[["cost"]], 0)
  expect_identical(attr(u, "footer"), "0 requests, 0 tokens in, $0.0000")
  usage_add(s, usage_fixture(session_data(s)$id, "q-local", cost = 0, input = 1200))
  u = gptr_usage(s)
  expect_identical(u$cost, 0)
  expect_identical(u$cache_write, 0)
  expect_identical(attr(u, "footer"), "1 request, 1.2k tokens in, $0.0000")
})

test_that("gptr_usage(by = \"model\") groups an unknown provider or model as unknown", {
  s = test_session()
  sid = session_data(s)$id
  usage_add(s, usage_fixture(sid, "q-m1"))
  row = usage_fixture(sid, "q-m2")
  row$model = NA_character_
  usage_add(s, row)
  row = usage_fixture(sid, "q-m3")
  row$provider = NA_character_
  usage_add(s, row)
  u = gptr_usage(s, by = "model")
  expect_identical(u$group, c("fake/fake-1", NA))
  expect_identical(u$requests, c(1L, 2L))
  expect_false("NA/NA" %in% u$group)
})

test_that("gptr_usage(x = NULL) adds the process System 1 log, counting each request once", {
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  s = test_session()
  sid = session_data(s)$id
  usage_add(s, usage_fixture(sid, "q-s1-shared", cost = 0.5, agent = "s1-probe"))
  usage_log_append(rbind(
    usage_fixture(NA_character_, "q-s1-only", cost = 0.25, agent = "s1-probe",
                  route = "system-one"),
    usage_fixture(sid, "q-s1-shared", cost = 0.5, agent = "s1-probe", route = "system-one")
  ))
  u = gptr_usage(by = "agent")
  probe = u[u$group %in% "s1-probe", , drop = FALSE]
  expect_identical(probe$requests, 2L)
  expect_equal(probe$cost, 0.75)
  expect_true(NA_character_ %in% gptr_usage()$group)
  # an explicit x reads only its sessions, never the process log
  expect_identical(gptr_usage(s, by = "agent")$requests, 1L)
  expect_false(anyNA(gptr_usage(s)$group))
})

test_that("gptr_usage(detail = TRUE) reads the sessions' own ledgers, not their children's", {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  ledger_add(root, "q-root-1", list(t0 = 600, transcript = 40))
  ledger_add(child, "q-child", list(t0 = 500, transcript = 30))
  ledger_add(root, "q-root-2", list(t0 = 600, transcript = 70))
  ledger_mark_cached(child, "q-child", cache_read = NA_real_)
  # a child's request is not in the root's ledger (P14's /context reads the last row as the
  # session's own last request), although usage_add() rolls the child's usage row up to the root
  led = gptr_usage(root, detail = TRUE)
  expect_identical(led$request_id, c("q-root-1", "q-root-1", "q-root-2", "q-root-2"))
  expect_identical(led$request_id[[nrow(led)]], "q-root-2")
  expect_identical(led$cached, c(FALSE, FALSE, FALSE, FALSE))
  expect_identical(rownames(led), as.character(1:4))
  led = gptr_usage(child, detail = TRUE)
  expect_identical(led$request_id, c("q-child", "q-child"))
  expect_identical(led$cached, c(NA, NA))
  # several sessions: their own ledgers in the order given, each (request, component) once
  led = gptr_usage(list(root, child, root), detail = TRUE)
  expect_identical(nrow(led), 6L)
  expect_identical(unique(led$request_id), c("q-root-1", "q-root-2", "q-child"))
  expect_identical(rownames(led), as.character(1:6))
  empty = gptr_usage(test_session(), detail = TRUE)
  expect_s3_class(empty, "gptr_ledger")
  expect_identical(nrow(empty), 0L)
})

test_that("gptr_usage() names the argument it refuses", {
  s = test_session()
  err = expect_error(gptr_usage(list(s, 1)), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "x")
  expect_error(gptr_usage(list()), class = "gptr_error_invalid_argument")
  err = expect_error(gptr_usage(s, by = c("agent", "model")),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "by")
  err = expect_error(gptr_usage(s, detail = "yes"), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "detail")
})
