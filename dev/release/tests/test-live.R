# A live-<date>.csv in the shape P24's dev/bench/tokens/live.R writes, every row in tolerance.
live_rows = function() {
  ids = c(sprintf("ns%02d-task", 1:11), "ns02c-describers")
  data.frame(date = "2026-10-20",
             provider = rep(c("anthropic", "openai"), each = length(ids)),
             model = rep(c("anthropic/claude-sonnet-5-5", "openai/gpt-6-sol"),
                         each = length(ids)),
             fixture = rep(ids, 2L), status = "ok", requests_golden = 2, requests_live = 4,
             input_golden_o200k = 1000, prior = rep(c(1.35, 1.00), each = length(ids)),
             input_live = rep(c(1500, 1180), each = length(ids)), ok = TRUE)
}

test_that("live_problems() accepts a calibration run within the IC-73 tolerances", {
  expect_identical(live_problems(live_rows()), character())
})

test_that("live_problems() reports runs outside the tolerances", {
  df = live_rows()
  df$requests_live[1L] = 5
  expect_identical(live_problems(df),
                   "ns01-task on anthropic/claude-sonnet-5-5: 5 requests vs 2 golden (limit +2)")
  df = live_rows()
  df$requests_golden[2L] = NA
  expect_identical(live_problems(df),
                   "ns02-task on anthropic/claude-sonnet-5-5: 4 requests vs NA golden (limit +2)")
  df = live_rows()
  df$input_live[13L] = 1300
  expect_match(live_problems(df),
               "ns01-task on openai/gpt-6-sol: 1300 input tokens vs 1000 expected", fixed = TRUE)
  df$input_live[13L] = 790
  expect_match(live_problems(df), "790 input tokens", fixed = TRUE)
  df = live_rows()
  df$input_live[1L] = 1700
  expect_match(live_problems(df), "1700 input tokens vs 1350 expected", fixed = TRUE)
})

test_that("live_problems() requires both providers, every fixture and successful runs", {
  expect_match(live_problems(live_rows()[1:12, ]), "no openai model")
  expect_match(live_problems(live_rows()[-3, ]), "anthropic has no row for ns03")
  df = live_rows()
  df$status[14L] = "gptr_error_provider boom"
  df$requests_live[14L] = NA
  expect_identical(live_problems(df),
                   "ns02-task on openai/gpt-6-sol: the run failed: gptr_error_provider boom")
  expect_match(live_problems(live_rows()[, names(live_rows()) != "prior"]),
               "missing column prior")
})

test_that("live_file_name() names the release calibration file by date", {
  expect_identical(live_file_name(as.Date("2026-10-20")),
                   file.path("dev", "bench", "tokens", "live-2026-10-20.csv"))
})
