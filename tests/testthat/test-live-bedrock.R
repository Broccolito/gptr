# Live test of the bedrock-converse adapter (plan P26 Task 11). It makes paid API calls and runs
# only with GPTR_LIVE_TESTS=true, a key pair in AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# (AWS_SESSION_TOKEN when the pair is temporary) and the endpoint in GPTR_BEDROCK_BASE_URL,
# GPTR_BEDROCK_REGION and GPTR_BEDROCK_MODEL, for example a SigV4 gateway
# (https://unified-api.ucsf.edu/general/awsai, us-west-2, us.anthropic.claude-opus-4-8).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("bedrock-converse: a text turn and a tool round trip through a SigV4 endpoint (live)", {
  vars = c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "GPTR_BEDROCK_BASE_URL",
           "GPTR_BEDROCK_REGION", "GPTR_BEDROCK_MODEL")
  testthat::skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"),
                        "live tests need GPTR_LIVE_TESTS=true")
  testthat::skip_if(!all(nzchar(Sys.getenv(vars))), paste(vars, collapse = ", "))
  id = Sys.getenv("GPTR_BEDROCK_MODEL")
  off = gptr_register(gptr_provider("bedrock-live", api = "bedrock-converse",
                                    base_url = Sys.getenv("GPTR_BEDROCK_BASE_URL"),
                                    auth = "AWS_SECRET_ACCESS_KEY",
                                    compat = list(region = Sys.getenv("GPTR_BEDROCK_REGION")),
                                    models = list(list(id = id, tool_call = TRUE,
                                                       input = c("text", "image"),
                                                       max_output = 4096))))
  withr::defer(off())
  expect_live_round_trip(paste0("bedrock-live/", id), thinking = NULL)
})
