# Live test of the anthropic-messages adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and ANTHROPIC_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("anthropic: a text turn and a tool round trip with thinking replay (live)", {
  skip_unless_live("ANTHROPIC_API_KEY")
  expect_live_round_trip("anthropic/claude-sonnet-5-5")
})
