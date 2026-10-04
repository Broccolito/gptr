# Live test of the openai-responses adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and OPENAI_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("openai: a text turn and a tool round trip with reasoning replay (live)", {
  skip_unless_live("OPENAI_API_KEY")
  expect_live_round_trip("openai/gpt-6-sol")
})
