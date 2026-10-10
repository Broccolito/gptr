# Azure's Responses route uses the same api-key compatibility switch as completions.
# Bound handles must reach only the selected auth header; record headers cannot replace them.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("Responses sends a bound credential in the selected Azure auth header", {
  model = test_model("openai-responses", provider = "azure-work", id = "deployment")
  key = fake_handle("AZURE_OPENAI_API_KEY")
  provider = gptr_provider(
    "azure-work", api = "openai-responses", compat = list(auth_header = "api-key"),
    headers = list(`API-Key` = "record-value", Authorization = "Bearer record-value",
                   `X-Org` = "analysis")
  )
  req = responses_build(model, ctx_fixture(list(first_message())),
                        list(provider = provider, credential = key))
  expect_identical(req$headers$`api-key`, key)
  expect_false(any(tolower(names(req$headers)) == "authorization"))
  expect_identical(anyDuplicated(tolower(names(req$headers))), 0L)
  expect_identical(req$headers$`X-Org`, "analysis")
})

test_that("Responses default Bearer auth does not admit a second api-key credential", {
  model = test_model("openai-responses", provider = "openai-work", id = "model")
  key = fake_handle("OPENAI_API_KEY")
  provider = gptr_provider("openai-work", api = "openai-responses",
                           headers = list(`api-key` = "record-value"))
  req = responses_build(model, ctx_fixture(list(first_message())),
                        list(provider = provider, credential = key))
  expect_identical(req$headers$authorization, list("Bearer ", key))
  expect_null(req$headers$`api-key`)
})
