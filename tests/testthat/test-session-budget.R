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
