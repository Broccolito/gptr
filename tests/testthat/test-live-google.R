# Live test of the google-generative-ai adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and GEMINI_API_KEY or GOOGLE_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("google: a text turn and a tool round trip with thought signatures (live)", {
  skip_unless_live(c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  expect_live_round_trip("google/gemini-3.8-flash")
})
