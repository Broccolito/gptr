# Result objects are parsed entirely offline; no CLI process or account is used.
source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

test_that("a success subtype with an API error reports the failure and its result detail", {
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
