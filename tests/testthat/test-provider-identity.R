source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("native model identity records matching and distinct wire reports without guessing", {
  reported = function(api, value, missing = FALSE) {
    model = test_model(api)
    parse = switch(api,
      "anthropic-messages" = anthropic_normaliser,
      "google-generative-ai" = google_normaliser,
      "openai-responses" = responses_normaliser,
      "openai-completions" = completions_normaliser)
    event = switch(api,
      "anthropic-messages" = list(type = "message_start",
        message = list(id = "m", model_alias = "not-a-wire-report")),
      "google-generative-ai" = list(responseId = "m", candidates = list(list(
        content = list(role = "model", parts = list(list(text = "ok"))), finishReason = "STOP"))),
      "openai-responses" = list(type = "response.created", response = list(id = "m")),
      "openai-completions" = list(id = "m", choices = list(list(index = 0L,
        delta = list(content = "ok"), finish_reason = "stop"))))
    if (!missing) {
      if (identical(api, "anthropic-messages")) {
        event$message["model"] = list(value)
      } else if (identical(api, "google-generative-ai")) {
        event["modelVersion"] = list(value)
      } else if (identical(api, "openai-responses")) {
        event$response["model"] = list(value)
      } else event["model"] = list(value)
    }
    n = parse(model, list(emit = function(ev) NULL))
    n$push(list(event = event$type %||% "", data = json_encode(event)))
    n$message()$response_model
  }
  for (api in c("anthropic-messages", "google-generative-ai", "openai-responses",
                "openai-completions")) {
    expect_identical(reported(api, "fixture-1"), "fixture-1", info = api)
    expect_identical(reported(api, "wire-model-2"), "wire-model-2", info = api)
    expect_null(reported(api, NULL, missing = TRUE), info = api)
    for (value in list(NULL, "", 42, TRUE, list(id = "wire-model-2"), c("one", "two"))) {
      expect_null(reported(api, value), info = api)
    }
  }
})
