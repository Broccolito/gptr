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

# A private vault for tests that set key variables: P03's process vault has no unregister
# function, and later test files must not find a test key in it.
local_test_vault = function(.env = parent.frame()) {
  vault = new.env(parent = emptyenv())
  previous = list(vault = the$vault, secrets = the$secrets)
  original_register = secret_register
  vault_reset()
  withr::defer({
    the$vault = previous$vault
    the$secrets = previous$secrets
  }, envir = .env)
  testthat::local_mocked_bindings(
    secret_register = function(value, name, source = "user", active = TRUE, origin = NULL) {
      h = original_register(value, name, source, active, origin)
      assign(name, h, envir = vault)
      h
    },
    secret_lookup = function(name) get0(name, envir = vault, inherits = FALSE),
    .env = .env
  )
  vault
}

test_that("credentials: vault, then the environment, bound to the provider origin", {
  vault = local_test_vault()
  withr::local_envvar(ANTHROPIC_API_KEY = "sk-ant-api03-p05test-000000000000000000")
  h = provider_credential(provider_get("anthropic"))
  expect_s3_class(h, "gptr_secret")
  expect_equal(h$name, "ANTHROPIC_API_KEY")
  expect_equal(provider_origin(h$origin), "https://api.anthropic.com")
  printed = paste(c(capture.output(print(h)), format(h)), collapse = "\n")
  expect_false(grepl("p05test", printed, fixed = TRUE))
  expect_identical(get("ANTHROPIC_API_KEY", envir = vault), h)
  expect_identical(provider_credential(provider_get("anthropic"))$id, h$id)
  expect_null(provider_credential(provider_get("ollama")))
  expect_null(provider_credential(gptr_fake_provider(list("hi"))))
  withr::local_envvar(VLLM_API_KEY = "")
  expect_null(provider_credential(provider_get("vllm")))
})

test_that("a keyed provider without any credential signals gptr_error_no_key", {
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL)
  withr::local_envvar(GROQ_API_KEY = "")
  err = expect_error(provider_credential(provider_get("groq")), class = "gptr_error_no_key")
  expect_equal(err$provider, "groq")
  expect_equal(err$variables, "GROQ_API_KEY")
  expect_match(conditionMessage(err), "GROQ_API_KEY", fixed = TRUE)
})

test_that("credential-store and auth-function handles are bound to the provider origin", {
  local_test_vault()
  stored = secret_register("synthetic-stored-key-123456", "auth:openrouter")
  local_mocked_bindings(secret_lookup = function(name) NULL,
                        auth_store_get = function(key) list(type = "api_key", key = stored))
  withr::local_envvar(OPENROUTER_API_KEY = "")
  h = provider_credential(provider_get("openrouter"))
  expect_equal(h$id, stored$id)
  expect_equal(h$origin, "https://openrouter.ai")
  lab = gptr_provider("authfn", api = "openai-completions", base_url = "https://llm.lab.example/v1",
                      auth = function() stored)
  expect_equal(provider_credential(lab)$origin, "https://llm.lab.example")
})

test_that("a vault handle bound to another origin is never used for this provider", {
  elsewhere = structure(list(id = "OPENROUTER_API_KEY#aaaaaa", name = "OPENROUTER_API_KEY",
                             fp = "aaaaaa", origin = "https://evil.example"),
                        class = "gptr_secret")
  local_mocked_bindings(secret_lookup = function(name) elsewhere,
                        auth_store_get = function(key) NULL)
  withr::local_envvar(OPENROUTER_API_KEY = "")
  expect_error(provider_credential(provider_get("openrouter")), class = "gptr_error_no_key")
})

test_that("vault handles: canonical origins match, unbound ones are bound to the provider", {
  vault = local_test_vault()
  key = "sk-proj-p05bind-00000000000000000000000000"
  withr::local_envvar(OPENAI_API_KEY = key)
  ambient = secret_register(key, "OPENAI_API_KEY", source = "environment")
  expect_null(ambient$origin)
  h = provider_credential(provider_get("openai"))
  expect_equal(h$origin, "https://api.openai.com")
  expect_equal(h$fp, ambient$fp)
  canonical = secret_register("synthetic-xai-key-123456", "XAI_API_KEY",
                                origin = "https://api.x.ai:443")
  vault[["XAI_API_KEY"]] = canonical
  withr::local_envvar(XAI_API_KEY = "")
  expect_identical(provider_credential(provider_get("xai")), canonical)
})

test_that("the anthropic provider refuses a Claude subscription OAuth token (sk-ant-oat)", {
  vault = local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  oat = "sk-ant-oat01-p05test-0000000000000000000000"
  withr::local_envvar(ANTHROPIC_API_KEY = oat)
  err = expect_error(provider_credential(provider_get("anthropic")), class = "gptr_error_no_key")
  expect_equal(err$provider, "anthropic")
  expect_equal(err$variables, "ANTHROPIC_API_KEY")
  expect_match(conditionMessage(err), "subscription OAuth token (sk-ant-oat...)", fixed = TRUE)
  expect_match(conditionMessage(err), "model = \"claude_code\"", fixed = TRUE)
  expect_false(grepl("p05test", conditionMessage(err), fixed = TRUE))
  expect_false(exists("ANTHROPIC_API_KEY", envir = vault, inherits = FALSE))
  # ambient discovery registered the same token: its vault handle is refused too
  secret_register(oat, "ANTHROPIC_API_KEY", source = "environment")
  expect_error(provider_credential(provider_get("anthropic")), class = "gptr_error_no_key")
  # an API key held only in the vault (a .env value that was not exported) is still used
  api = secret_register("sk-ant-api03-p05vault-0000000000000000000", "ANTHROPIC_API_KEY",
                        source = "dotenv")
  h = provider_credential(provider_get("anthropic"))
  expect_equal(h$fp, api$fp)
  expect_equal(h$origin, "https://api.anthropic.com")
})

test_that("auth callbacks cannot return credentials bound to a different origin", {
  foreign = structure(list(id = "foreign", name = "KEY", fp = "synthetic",
                            origin = "https://elsewhere.example"), class = "gptr_secret")
  provider = gptr_provider("bound", "openai-completions", base_url = "https://lab.example/v1",
                            auth = function() foreign)
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
  for (origin in list(NA_character_, "not-a-url")) {
    foreign$origin = origin
    expect_error(provider_credential(provider), class = "gptr_error_no_key")
  }
})

test_that("missing or malformed configured origins fail before credential lookup", {
  calls = 0L
  auth = function() {
    calls <<- calls + 1L
    structure(list(id = "unbound", name = "KEY", fp = "synthetic", origin = NULL),
                class = "gptr_secret")
  }
  for (url in list(NULL, "", "not-a-url", "https://")) {
    provider = gptr_provider("unbound", "openai-completions", base_url = url, auth = auth)
    expect_error(provider_credential(provider), class = "gptr_error_no_key")
  }
  expect_identical(calls, 0L)
})

test_that("provider credentials honor both the actual vault and handle origin restrictions", {
  vault_reset()
  withr::defer(vault_reset())
  handle = secret_register("synthetic-provider-bound-key-123456", "BOUND_TEST_KEY",
                             origin = "https://elsewhere.example")
  handle$origin = "https://lab.example"
  provider = gptr_provider("bound", "openai-completions", base_url = "https://lab.example/v1",
                            auth = function() handle)
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
})

test_that("real stored handles bind without exposing values and default Ollama avoids cloud auth", {
  vault_reset()
  withr::defer(vault_reset())
  root = withr::local_tempdir()
  local_mocked_bindings(auth_store_path = function(create = FALSE) file.path(root, "auth.json"))
  value = "synthetic-store-provider-key-123456"
  auth_store_set("openrouter", list(type = "api_key", key = value))
  withr::local_envvar(OPENROUTER_API_KEY = "")
  handle = provider_credential(provider_get("openrouter"))
  expect_s3_class(handle, "gptr_secret")
  expect_identical(provider_origin(handle$origin), "https://openrouter.ai")
  expect_false(any(grepl(value, capture.output(print(handle)), fixed = TRUE)))
  headers = http_headers(list(Authorization = list("Bearer ", handle)), "https://openrouter.ai")
  expect_identical(headers$Authorization, paste0("Bearer ", value))
  expect_error(http_headers(list(Authorization = handle), "https://elsewhere.example"),
                 class = "gptr_error_untrusted")
  local_mocked_bindings(secret_lookup = function(...) stop("unexpected cloud lookup"),
                        auth_store_get = function(...) stop("unexpected cloud lookup"))
  expect_null(provider_credential(provider_get("ollama")))
})

test_that("environment fallback preserves old origin restrictions and distinguishes new keys", {
  vault_reset()
  withr::defer(vault_reset())
  local_mocked_bindings(auth_store_get = function(key) NULL)
  old_value = "synthetic-existing-bound-env-key-123456"
  old = secret_register(old_value, "BOUND_TEST_KEY", origin = "https://old.example")
  withr::local_envvar(BOUND_TEST_KEY = old_value)
  provider = gptr_provider("replacement", "openai-completions",
                            base_url = "https://new.example", auth = "BOUND_TEST_KEY")
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
  expect_identical(secrets_state()$reg[[old$id]]$origin, "https://old.example:443")
  withr::local_envvar(BOUND_TEST_KEY = "synthetic-replacement-env-key-654321")
  replacement = provider_credential(provider)
  expect_false(identical(replacement$id, old$id))
  expect_identical(provider_origin(replacement$origin), "https://new.example")
  expect_identical(secrets_state()$reg[[old$id]]$origin, "https://old.example:443")
  provider$base_url = "https://third.example"
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
})

test_that("a stale credential ID is unavailable before dispatch", {
  vault_reset()
  withr::defer(vault_reset())
  stale = secret_register("synthetic-stale-key-123456", "STALE_TEST_KEY")
  vault_reset()
  provider = gptr_provider("stale", "openai-completions", base_url = "https://lab.example",
                            auth = function() stale)
  expect_false(credential_usable(stale, "https://lab.example"))
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
})
