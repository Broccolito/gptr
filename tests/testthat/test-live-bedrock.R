# Live test of the bedrock-converse adapter (plan P26 Task 11). It makes paid API calls and runs
# only with GPTR_LIVE_TESTS=true, a key pair in AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# (AWS_SESSION_TOKEN when the pair is temporary) and the endpoint in GPTR_BEDROCK_BASE_URL,
# GPTR_BEDROCK_REGION and GPTR_BEDROCK_MODEL, for example a SigV4 gateway
# (https://unified-api.ucsf.edu/general/awsai, us-west-2, us.anthropic.claude-opus-4-8).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

# Register the live endpoint for the calling test with extra model-record fields; its reference
local_bedrock_live = function(..., .env = parent.frame()) {
  vars = c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "GPTR_BEDROCK_BASE_URL",
           "GPTR_BEDROCK_REGION", "GPTR_BEDROCK_MODEL")
  testthat::skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"),
                        "live tests need GPTR_LIVE_TESTS=true")
  testthat::skip_if(!all(nzchar(Sys.getenv(vars))), paste(vars, collapse = ", "))
  id = Sys.getenv("GPTR_BEDROCK_MODEL")
  record = c(list(id = id, tool_call = TRUE, input = c("text", "image"), max_output = 4096),
             list(...))
  off = gptr_register(gptr_provider("bedrock-live", api = "bedrock-converse",
                                    base_url = Sys.getenv("GPTR_BEDROCK_BASE_URL"),
                                    auth = "AWS_SECRET_ACCESS_KEY",
                                    compat = list(region = Sys.getenv("GPTR_BEDROCK_REGION")),
                                    models = list(record)))
  withr::defer(off(), envir = .env)
  paste0("bedrock-live/", id)
}

test_that("bedrock-converse: a text turn and a tool round trip through a SigV4 endpoint (live)", {
  ref = local_bedrock_live()
  expect_live_round_trip(ref, thinking = NULL)
})

test_that("bedrock-converse: thinking = 'high' on an adaptive Claude model is signed (live)", {
  ref = local_bedrock_live(reasoning = TRUE,
                           capabilities = list(adaptive_thinking = TRUE, effort = TRUE))
  testthat::skip_if_not(grepl("anthropic\\.claude", ref), "GPTR_BEDROCK_MODEL is not Claude")
  ask = msg_user(paste("A bat and a ball cost 1.10 in total; the bat costs 1.00 more than the",
                       "ball. Work out the price of the ball step by step, then give it."))
  msg = live_stream(model_resolve(ref), live_context(list(ask), list(thinking = "high")))
  signed = vapply(msg$content, function(b) {
    identical(b$type, "thinking") && nzchar(b$signature %||% "")
  }, NA)
  expect_true(any(signed), info = msg$error_message %||% "")
})
