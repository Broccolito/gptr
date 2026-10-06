bench_source_only("tokens", "live.R")

test_that("live.R is off unless GPTR_LIVE_TESTS is true, and sends nothing", {
  skip_if_not_installed("processx")
  res = processx::run(file.path(R.home("bin"), "Rscript"),
                      c("--vanilla", file.path("dev", "bench", "tokens", "live.R")),
                      wd = bench_root(), env = c("current", GPTR_LIVE_TESTS = "false"),
                      error_on_status = FALSE)
  expect_identical(res$status, 0L)
  expect_match(res$stderr, "live mode is off", fixed = TRUE)
})

test_that("live_fixtures() joins every fixture with its golden numbers", {
  dir = withr::local_tempdir()
  writeLines('{"id": "nsx", "turns": [{"prompt": "p"}]}', file.path(dir, "nsx.json"))
  writeLines('{"id": "nsy", "turns": [{"prompt": "p"}]}', file.path(dir, "nsy.json"))
  fx = live_fixtures(dir, data.frame(case = "nsx", requests = 3L, input_total = 9000L))
  expect_identical(vapply(fx, function(f) f$id, ""), c("nsx", "nsy"))
  expect_identical(fx[[1L]]$golden_requests, 3L)
  expect_identical(fx[[1L]]$golden_input, 9000L)
  expect_true(is.na(fx[[2L]]$golden_input))
})

test_that("live_usage() sums per-request rows and keeps unknown usage unknown", {
  rows = data.frame(input = c(100, 20), cache_read = c(0, 3000), cache_write_5m = c(0, 0),
                    cache_write_1h = c(3000, 0), output = c(50, 40), cost = c(0.01, 0.002))
  u = live_usage(rows)
  expect_identical(u$requests, 2L)
  expect_identical(u$input, 6120)
  expect_identical(u$cache_read, 3000)
  rows$cache_read[[2L]] = NA
  expect_true(is.na(live_usage(rows)$input))
})

test_that("live_row() applies +2 requests and 20% input after the provider prior", {
  expect_identical(live_priors, c(anthropic = 1.35, openai = 1.00))
  fx = list(id = "nsx", golden_requests = 2, golden_input = 1000)
  prefix = list(claude = NA_real_, o200k = NA_real_)
  run = function(requests, input) {
    list(status = "ok", requests = requests, input = input, cache_read = 0, cost = 0)
  }
  expect_true(live_row("anthropic", "a", fx, run(4, 1350 * 1.19), prefix)$ok)
  expect_false(live_row("anthropic", "a", fx, run(5, 1350), prefix)$ok)
  expect_false(live_row("openai", "o", fx, run(2, 1250), prefix)$ok)
  expect_false(live_row("openai", "o", fx, run(2, NA), prefix)$ok)
  failed = live_row("openai", "o", fx, list(status = "gptr_error_provider boom"), prefix)
  expect_false(failed$ok)
  expect_true(is.na(failed$requests_live))
  expect_named(failed, c("date", "provider", "model", "fixture", "status", "requests_golden",
                         "requests_live", "input_golden_o200k", "prior", "input_live",
                         "cache_read_live", "cost_live", "ratio", "prefix_claude",
                         "prefix_o200k", "cache_read_seen", "ok"))
})

test_that("live_run_fixture() runs every turn on the fixture's attached objects and preset", {
  bench_test_load_gptr()
  fake = gptr_fake_provider(list("first", "second"))
  fx = list(files = list(AGENTS.md = "# AGENTS.md"), objects = list(scores = "c(a = 1, b = 2)"),
            preset = "minimal",
            turns = list(list(prompt = "Summarise them.", context = list(list(label = "scores"))),
                         list(prompt = "Thanks.")))
  r = live_run_fixture(fx, fake, 1)
  expect_identical(r$status, "ok")
  expect_identical(r$requests, 2L)
  texts = vapply(fake$log$requests[[1L]]$messages[[1L]]$content, function(b) b$text, "")
  expect_true(any(startsWith(texts, "<attached name=\"scores\">")))
  for (rq in fake$log$requests) {
    expect_identical(rq$system$t0, gptr_prompt(preset = "minimal")$system$t0)
  }
})

test_that("live_run_fixture() caps the cost of the whole fixture, not of each turn", {
  bench_test_load_gptr()
  local_mocked_bindings(usage_cost = function(...) list(cost = list(total = 1.2)),
                        .package = "gptr")
  fake = gptr_fake_provider(list("a"))
  r = live_run_fixture(list(turns = list(list(prompt = "One."), list(prompt = "Two."))), fake, 1)
  expect_match(r$status, "^gptr_error_budget")
  expect_identical(r$requests, 1L)
})
