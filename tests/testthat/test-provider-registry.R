# Tests for R/provider-registry.R (plan P05): provider records as data, base URLs and origins,
# credentials, provider_stream() on every transport, and gptr_providers().

builtin_ids = c("anthropic", "openai", "google", "openrouter", "groq", "deepseek", "mistral",
                "together", "xai", "cerebras", "fireworks", "ollama", "lmstudio", "llamacpp",
                "vllm", "azure", "bedrock")

# Settings come from P08's layers later; tests pin them by mocking the one reader.
local_settings = function(..., .env = parent.frame()) {
  values = list(...)
  testthat::local_mocked_bindings(
    setting_get = function(key, session = NULL, default = NULL) {
      if (key %in% names(values)) values[[key]] else default
    },
    .env = .env
  )
}

test_that("builtin:providers registers the architecture section 8.1 providers as data", {
  a = provider_get("anthropic")
  expect_true(all(builtin_ids %in% registry_names("provider")))
  expect_s3_class(a, "gptr_provider")
  expect_equal(a$api, "anthropic-messages")
  expect_equal(a$base_url, "https://api.anthropic.com")
  expect_equal(a$auth, "ANTHROPIC_API_KEY")
  expect_equal(provider_get("google")$auth, c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  expect_equal(provider_get("mistral")$compat$tool_id, "alnum9")
  expect_true(provider_get("deepseek")$compat$requires_reasoning_content)
  expect_true(provider_get("ollama")$local)
  expect_null(provider_get("ollama")$auth)
  expect_equal(provider_get("openrouter")$headers$`X-OpenRouter-Title`, "gptr")
  expect_false(any(vapply(builtin_ids, function(id) isTRUE(provider_get(id)$offline), NA)))
  expect_null(provider_get("no-such-provider"))
  expect_error(provider_get(1), class = "gptr_error_invalid_argument")
})

test_that("builtin:fake is declared here, and the fake provider passes gptr_check() (INFRA-17)", {
  expect_equal(adapter_get("fake")$transport, "inprocess")
  expect_false(is.null(registry_get("adapter", "fake-classifier")))
  res = gptr_check(gptr_fake_provider(list("hi")))
  expect_s3_class(res, "gptr_check")
  expect_true(all(res$ok))
  err = expect_error(adapter_get("no-such-api"), class = "gptr_error_not_available")
  expect_equal(err$member, "no-such-api")
})

test_that("a plugin adapter passes gptr_check() (INFRA-17)", {
  # an inprocess adapter whose generator plays a one-line fake reply (P01's fake_stream())
  reply = gptr_fake_provider(list("plugin reply"), name = "p05-plugin-fake")
  one_line = function(model, context, opts) {
    opts$provider = reply
    fake_stream(model, context, opts)
  }
  ok = ext_load(function(gptr) {
    gptr$register(gptr_adapter("p05-plugin", transport = "inprocess", stream = one_line))
  }, source = "plugin:p05-plugin", rank = 5L)
  withr::defer(ext_unload("plugin:p05-plugin"))
  expect_true(ok)
  a = adapter_get("p05-plugin")
  expect_identical(a, registry_get("adapter", "p05-plugin"))
  expect_equal(a$transport, "inprocess")
  model = list(id = "p05-plugin-1", api = "p05-plugin", provider = "p05-plugin")
  expect_true(is.function(a$stream(model, list(messages = list()), list())))
  res = gptr_check(a)
  expect_s3_class(res, "gptr_check")
  expect_true(all(res$ok))
})

test_that("base URLs come from settings, the record or an environment template", {
  local_settings(providers = list(openai = list(base_url = "https://proxy.example/v1/"),
                                  openrouter = list(headers = list(`X-Title` = "lab", bad = 1)),
                                  groq = list(enabled = FALSE)))
  expect_equal(provider_base_url(provider_get("openai")), "https://proxy.example/v1")
  expect_equal(provider_base_url(provider_get("anthropic")), "https://api.anthropic.com")
  expect_equal(provider_get("openrouter")$headers$`X-Title`, "lab")
  expect_equal(provider_get("openrouter")$headers$`X-OpenRouter-Title`, "gptr")
  expect_null(provider_get("openrouter")$headers$bad)
  expect_false(provider_get("groq")$enabled)
  expect_true(provider_get("openai")$enabled)
  withr::local_envvar(AZURE_OPENAI_ENDPOINT = "https://res.openai.azure.com/",
                      AWS_REGION = "", AWS_DEFAULT_REGION = "")
  expect_equal(provider_base_url(provider_get("azure")), "https://res.openai.azure.com/openai/v1")
  expect_equal(provider_base_url(provider_get("bedrock")),
               "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1")
  withr::local_envvar(AZURE_OPENAI_ENDPOINT = "https://res.openai.azure.com/openai/v1",
                      AWS_REGION = "eu-central-1")
  expect_equal(provider_base_url(provider_get("azure")), "https://res.openai.azure.com/openai/v1")
  expect_equal(provider_base_url(provider_get("bedrock")),
               "https://bedrock-runtime.eu-central-1.amazonaws.com/openai/v1")
  expect_equal(provider_origin("https://API.Anthropic.com:443/v1/messages"),
               "https://api.anthropic.com")
  expect_equal(provider_origin("http://user:pw@localhost:11434/v1"), "http://localhost:11434")
  expect_null(provider_origin(NULL))
})

test_that("provider origins match transport normalization and reject malformed URLs", {
  expect_identical(provider_origin("http://127.1:80/v1"), "http://127.0.0.1")
  expect_identical(provider_origin("http://[0:0:0:0:0:0:0:1]:80/v1"), "http://[::1]")
  for (url in list(NA_character_, 42, "https://", "not-a-url", "https://a.example/\r\nx")) {
    expect_null(provider_origin(url))
  }
})

test_that("provider records preserve mixed model metadata without granting capabilities", {
  decision = list(types = c("noul", "choice", "score"), images = TRUE,
                   server_min = "0.35.1", max_questions = 64L, max_options = 26L,
                   max_request_bytes_text = 65536L, max_request_bytes_images = 33554432L,
                   max_active = 1L)
  models = list(
    chat = list(id = "chat", type = "chat", api = "openai-completions",
                  capabilities = list(tools = FALSE)),
    decision = list(id = "decision", type = "classifier", api = "ollama-system-one",
                    decision = decision,
                    context = NA_real_, digest = "sha256:synthetic", server_version = "0.35.1",
                    format = "gguf", quantization = "Q4_K_M", locality = "unknown",
                    remote_host = "cloud.example", remote_model = "remote",
                    capabilities = list(vision = FALSE)))
  provider = gptr_provider("mixed", "openai-completions", models = models)
  expect_identical(provider_effective(provider)$models, models)
  expect_identical(adapter_provided_by("ollama-system-one"), "P13")
  expect_null(provider_get("ollama")$auth)
  expect_false(provider_get("ollama")$offline)
})

test_that("settings header overrides use HTTP name identity and reject ambiguous names", {
  local_settings(providers = list(openrouter = list(
    headers = list(`http-referer` = "https://lab.example"))))
  headers = provider_get("openrouter")$headers
  expect_equal(sum(tolower(names(headers)) == "http-referer"), 1L)
  expect_identical(unname(unlist(headers[tolower(names(headers)) == "http-referer"])),
                    "https://lab.example")
  expect_no_error(http_headers(headers, "https://openrouter.ai"))
  for (nms in list(NA_character_, c("X-Lab", "x-lab"), "bad name", "X-Lab\n")) {
    headers = stats::setNames(rep(list("value"), length(nms)), nms)
    local_settings(providers = list(openrouter = list(headers = headers)))
    expect_error(provider_get("openrouter"), class = "gptr_error_invalid_argument")
  }
})
