# Tests for R/provider-usage.R (plan P05): usage records, dated price tiers, TTL-split cache
# writes (INFRA-20), usage rows and the process System 1 log.

price_rows = function(...) prices_df(list(...))

opus_like = function() {
  list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 4, output = 20,
                                cache_read = 0.2, cache_write_5m = 5, cache_write_1h = 8)))
}

test_that("usage_new() fills zeros, the total and an empty cost", {
  u = usage_new(input = 10, output = 5, cache_read = 100)
  expect_named(u, c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                    "reasoning", "images", "total", "cost", "estimated"))
  expect_equal(u$total, 115)
  expect_equal(u$cache_write_1h, 0)
  expect_equal(u$cost, list(input = 0, output = 0, cache_read = 0, cache_write = 0, total = 0))
  expect_false(u$estimated)
  expect_true(usage_new(estimated = TRUE)$estimated)
  expect_true(is.na(usage_new(input = NA)$input))
  expect_error(usage_new(inptu = 1), class = "gptr_error_internal")
  expect_error(usage_new(1), class = "gptr_error_internal")
})

test_that("usage_cost() gives the documented dollar amounts (INFRA-20)", {
  # report 07 section 5.2: Opus 5.5, 50 in, 1200 out, 200000 cache reads, 3000 5-minute writes
  u = usage_cost(usage_new(input = 50, output = 1200, cache_read = 200000,
                           cache_write_5m = 3000), opus_like())
  expect_equal(u$cost$total, 0.0792)
  # report 03 verification row 5: 600 5-minute writes at 5 plus 400 1-hour writes at 2 x 4
  one_hour = usage_cost(usage_new(cache_write_5m = 600, cache_write_1h = 400), opus_like())
  expect_equal(one_hour$cost$cache_write, 0.0062)
  expect_equal(one_hour$cost$total, 0.0062)
  implicit = list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 4,
                                           output = 20)))
  derived = usage_cost(usage_new(cache_write_5m = 600, cache_write_1h = 400), implicit)
  expect_equal(derived$cost$cache_write, 0.0062)
  expect_equal(usage_cost(usage_new(cache_read = 1e6), implicit)$cost$cache_read, 0.4)
  # report 07 live call 2 (verification log row 26): a Haiku 4.5 turn with 7,641 1-hour cache
  # writes; the CLI's own total_cost_usd was 0.0178928
  haiku = list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 1,
                                        output = 5, cache_read = 0.1)))
  live = usage_cost(usage_new(input = 946, output = 184, cache_read = 7448,
                              cache_write_1h = 7641), haiku)
  expect_equal(live$cost$total, 0.0178928)
})

test_that("price tiers switch on the prompt size and on the date", {
  sol = list(prices = price_rows(
    list(from = "2000-01-01", tier = "default", input = 2, output = 10, cache_read = 0.1),
    list(from = "2000-01-01", tier = ">272k", input = 4, output = 15, cache_read = 0.2)
  ))
  expect_equal(usage_cost(usage_new(input = 100000), sol)$cost$input, 0.2)
  expect_equal(usage_cost(usage_new(input = 300000), sol)$cost$input, 1.2)
  expect_equal(price_select(sol$prices, 300000)$tier, ">272k")
  expect_equal(price_select(sol$prices, 100000)$tier, "default")
  flash = list(prices = price_rows(
    list(from = "2000-01-01", tier = "default", input = 0.75, output = 3.75),
    list(from = "2027-01-01", tier = "default", input = 1.50, output = 7.50)
  ))
  late = usage_cost(usage_new(input = 1e6), flash, when = as.Date("2026-12-31"))
  new_year = usage_cost(usage_new(input = 1e6), flash, when = as.Date("2027-01-01"))
  expect_equal(late$cost$input, 0.75)
  expect_equal(new_year$cost$input, 1.50)
  expect_true(is.na(usage_cost(usage_new(input = 1e6), list(prices = NULL))$cost$total))
  expect_equal(price_threshold(c("default", ">200k", "<=200k", ">32k")),
               c(NA, 200000, NA, 32000))
})

test_that("unknown observations remain distinct from omitted legacy fields", {
  u = usage_new(input = NA_real_, output = 3, cache_read = NULL,
                cost = list(input = NA_real_, total = NA_real_))
  expect_true(is.na(u$input))
  expect_true(is.na(u$cache_read))
  expect_equal(u$cache_write_5m, 0)
  expect_true(is.na(u$total))
  expect_true(is.na(u$cost$total))
  expect_identical(usage_from_json(usage_to_json(u)), u)
  expect_equal(usage_new()$total, 0)
  for (value in list(NULL, list(), json_obj(), list(extra = "metadata"))) {
    unknown = usage_as(value)
    expect_true(all(is.na(unlist(unknown[usage_fields]))))
    expect_true(is.na(unknown$total))
    expect_true(all(is.na(unlist(unknown$cost))))
    expect_false(unknown$estimated)
  }
  expect_equal(usage_as(list(input = 3))$output, 0)
  expect_true(usage_as(usage_new(input = 3, estimated = TRUE))$estimated)
  reported = usage_new(input = NA, output = NA, total = 123,
                       cost = list(input = NA, output = NA, total = 0.03))
  expect_equal(reported$total, 123)
  expect_equal(reported$cost$total, 0.03)
  expect_identical(usage_as(reported), reported)
  metadata = usage_as(list(estimated = TRUE, cost = list(total = 0.03)))
  expect_true(is.na(metadata$input))
  expect_true(is.na(metadata$total))
  expect_equal(metadata$cost$total, 0.03)
  expect_true(metadata$estimated)
  expect_true(all(is.na(unlist(usage_as(list(cost = NULL))$cost))))
  total_only = usage_as(list(total = 12, cost = list(total = 0.02)))
  expect_true(all(is.na(unlist(total_only[usage_fields]))))
  expect_equal(total_only$total, 12)
  expect_equal(total_only$cost$total, 0.02)
})

test_that("usage and monetary values must be finite nonnegative real scalars or NA", {
  for (value in list(-1, Inf, -Inf, NaN, 1 + 1i, "3", TRUE, c(1, 2))) {
    expect_error(usage_new(input = value), class = "gptr_error_invalid_argument")
    expect_error(cost_new(list(total = value)), class = "gptr_error_invalid_argument")
    expect_error(price_rows(list(input = value)), class = "gptr_error_invalid_argument")
  }
  expect_error(usage_new(input = 1, input = 2), class = "gptr_error_internal")
  expect_error(usage_new(estimated = NA), class = "gptr_error_invalid_argument")
  expect_error(usage_new(cost = 1), class = "gptr_error_invalid_argument")
  expect_error(usage_as(1), class = "gptr_error_invalid_argument")
  expect_error(usage_new(input = 1e308, output = 1e308),
               class = "gptr_error_invalid_argument")
})

test_that("known zero local API rates do not erase unknown tokens", {
  local = list(locality = "local", prices = price_rows(list(input = 0, output = 0)))
  u = usage_cost(NULL, local)
  expect_true(is.na(u$input))
  expect_true(is.na(u$output))
  expect_true(is.na(u$total))
  expect_equal(unlist(u$cost), c(input = 0, output = 0, cache_read = 0,
                                cache_write = 0, total = 0))
  for (model in list(list(local = TRUE), list(locality = "unknown"),
                     list(locality = "remote"), list(locality = "local"))) {
    expect_true(is.na(usage_cost(usage_new(input = 1), model)$cost$total))
  }
  unknown_rates = list(prices = price_rows(list(output = 2)))
  u = usage_cost(usage_new(input = 1, output = 10), unknown_rates)
  expect_true(is.na(u$cost$input))
  expect_equal(u$cost$output, 0.00002)
  expect_true(is.na(u$cost$total))
  u = usage_cost(usage_new(input = NA, output = 10), opus_like())
  expect_true(is.na(u$cost$input))
  expect_equal(u$cost$output, 0.0002)
  expect_true(is.na(u$cost$total))
})

test_that("unknown prompt size does not silently select a cheaper threshold tier", {
  tiers = price_rows(list(input = 1, output = 2),
                     list(tier = ">2k", input = 3, output = 4),
                     list(tier = ">4k", input = 5, output = 6))
  expect_null(price_select(tiers, NA_real_))
  expect_true(is.na(usage_cost(usage_new(input = NA), list(prices = tiers))$cost$total))
  expect_equal(price_select(tiers, 2000)$input, 1)
  expect_equal(price_select(tiers, 2001)$input, 3)
  expect_equal(price_select(tiers, 5000)$input, 5)
  identical_rates = price_rows(list(input = 0, output = 0),
                               list(tier = ">2k", input = 0, output = 0))
  expect_equal(usage_cost(NULL, list(prices = identical_rates))$cost$total, 0)
  no_base = price_rows(list(tier = ">2k", input = 3, output = 4))
  expect_null(price_select(no_base, 1))
})

test_that("price dates and tiers are validated and future rates are not borrowed", {
  prices = price_rows(list(from = "2026-10-01", input = 1, output = 2),
                      list(from = "2026-11-01", input = 2, output = 4))
  expect_null(price_select(prices, 1, as.Date("2026-09-30")))
  expect_equal(price_select(prices, 1, as.Date("2026-10-01"))$input, 1)
  expect_equal(price_select(prices, 1, as.Date("2026-11-01"))$input, 2)
  expect_equal(prices_df(prices), prices)
  expect_identical(nrow(prices_df(NULL)), 0L)
  for (date in list("not-a-date", "2026-02-30", "2026-01-01suffix", NA, Inf,
                    as.Date(NA), c("2026-01-01", "2026-02-01"))) {
    expect_error(price_rows(list(from = date, input = 1)),
                 class = "gptr_error_invalid_argument")
    expect_error(price_select(prices, 1, date), class = "gptr_error_invalid_argument")
  }
  for (tier in list("", NA, ">2.3.4k", ">Infk", "premium", ">-1k", c("default", ">2k"))) {
    expect_error(price_rows(list(tier = tier)), class = "gptr_error_invalid_argument")
  }
  expect_error(price_rows(list(input = 1), list(input = 2)),
               class = "gptr_error_invalid_argument")
  expect_error(price_rows(list(tier = "<=2k"), list(tier = "default")),
               class = "gptr_error_invalid_argument")
  expect_error(price_rows(list(tier = ">2k"), list(tier = ">2.0k")),
               class = "gptr_error_invalid_argument")
})
