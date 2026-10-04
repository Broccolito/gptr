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

# ---- provider_stream(): HTTP transports on a scripted reactor ----------------------------

# reactor_retry() follows P04's contract: re-send (TRUE) while nothing is committed, otherwise
# fail the transfer through on_fail() (FALSE).
local_mock_reactor = function(.env = parent.frame()) {
  r = new.env()
  r$http = list()
  r$tasks = list()
  r$retries = list()
  r$cancelled = character()
  testthat::local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL,
                            provider = NULL, retry = NULL) {
      id = paste0("t", length(r$http) + 1L)
      r$http[[id]] = list(spec = spec, on_bytes = on_bytes, on_done = on_done,
                          on_fail = on_fail, on_headers = on_headers, retry = retry,
                          provider = provider)
      id
    },
    reactor_retry = function(id, info) {
      r$retries[[length(r$retries) + 1L]] = list(id = id, info = info)
      tr = r$http[[id]]
      if (is.null(tr)) return(invisible(FALSE))
      if (isTRUE(tr$retry$committed())) {
        tr$on_fail(stream_condition("stream error: overloaded", c("overloaded", "provider"),
                                    status = 529L))
        return(invisible(FALSE))
      }
      invisible(TRUE)
    },
    reactor_task = function(fn, run = NULL) {
      r$tasks[[length(r$tasks) + 1L]] = fn
      paste0("t", 200L + length(r$tasks))
    },
    reactor_cancel = function(ids) {
      r$cancelled = c(r$cancelled, ids)
      invisible(length(ids))
    },
    reactor_now = function() 0,
    .env = .env
  )
  r
}

sse = function(...) charToRaw(paste0("data: ", c(...), "\n\n", collapse = ""))

# A tiny SSE adapter: data {"t":"text","v":...} is a delta, {"t":"overloaded"} a retryable error.
# Like P12's normalisers it cannot know the request id (parse() sees no request context), so
# its start and error events and its messages leave it NULL for provider_stream() to fill.
local_stream_adapter = function(api = "test-sse", auth = NULL, build = NULL, seen = NULL,
                                .env = parent.frame()) {
  parse = function(model, opts) {
    s = new.env()
    s$text = character()
    s$started = FALSE
    current = function(stop = "stop") {
      msg_assistant(list(block_text(paste(s$text, collapse = ""))), api = model$api,
                    provider = model$provider, model = model$id, stop_reason = stop,
                    timestamp = 1)
    }
    list(
      push = function(ev) {
        d = json_decode(ev$data)
        if (!s$started) {
          s$started = TRUE
          opts$emit(ev_new("start", api = model$api, provider = model$provider,
                           model = model$id, request_id = NULL, response_id = NULL))
        }
        if (identical(d$t, "overloaded")) {
          opts$retry(list(class = "overloaded", status = 529L, retry_after = NULL))
          return(FALSE)
        }
        if (identical(d$t, "retry")) {
          opts$retry(list(class = d$class))
          return(FALSE)
        }
        s$text = c(s$text, d$v)
        opts$emit(ev_new("text_delta", index = 1L, delta = d$v))
        FALSE
      },
      finish = function() {
        m = current()
        opts$emit(ev_new("done", reason = "stop", message = m, usage = NULL))
        m
      },
      fail = function(cnd) {
        if (is.environment(seen)) seen$cnd = cnd
        m = current("error")
        m$error_message = conditionMessage(cnd)
        opts$emit(ev_new("error", reason = "error", message = m,
                         error = list(class = class(cnd)[[1]], status = cnd$status,
                                      request_id = NULL, retry_after = NULL)))
        m
      },
      message = function() current()
    )
  }
  build = build %||% function(model, context, opts) {
    list(url = paste0(opts$base_url, "/v1/stream"), method = "POST",
         headers = list(authorization = opts$credential), body = "{}", stream = "sse")
  }
  off1 = gptr_register(gptr_adapter(api, transport = "http_sse", build = build, parse = parse))
  off2 = gptr_register(gptr_provider("streamtest", api = api, base_url = "https://stream.example",
                                     auth = auth, models = list(list(id = "m1"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  model_resolve("streamtest/m1")
}

local_stream_log = function() {
  log = new.env()
  log$events = list()
  log$done = list()
  log$emit = function(ev) {
    log$events[[length(log$events) + 1L]] = ev
  }
  log$finish = function(msg) {
    log$done[[length(log$done) + 1L]] = msg
  }
  log$types = function() vapply(log$events, function(e) e$type, "")
  log
}

stream_context = function(text = "hi") {
  list(system = list(t0 = "", t1 = ""), tools_json = NULL, tools = list(),
       messages = list(msg_user(text, timestamp = 1)),
       cache_plan = list(anchors = character(), tail_ttl = "5m", key = "k"),
       params = list(max_tokens = 100L, thinking = NULL, effort = NULL, tool_choice = "auto",
                     returns = NULL, temperature = NULL),
       session_id = "s0000000000", request_id = "q000000000001", text = text)
}

# A stand-in for P06's gptr_run with the fields of 04 section 7.6 that provider_stream() reads.
local_run = function(status = "requesting") {
  run = new.env()
  run$id = "r0000000001"
  run$session = "s0000000000"
  run$status = status
  run$signal = new.env()
  run$signal$aborted = FALSE
  run$signal$reason = NULL
  run
}

test_that("an SSE stream yields one start, the deltas in order and one done", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_equal(id, "t1")
  t1 = r$http[["t1"]]
  expect_equal(t1$spec$url, "https://stream.example/v1/stream")
  expect_equal(t1$spec$request_id, "q000000000001")
  expect_equal(t1$spec$model, "m1")
  expect_equal(t1$spec$session_id, "s0000000000")
  expect_equal(t1$spec$idle_timeout, gptr_opt("idle_timeout"))
  expect_equal(t1$provider, "streamtest")
  expect_true(is.function(t1$retry$on_retry))
  expect_false(t1$retry$committed())
  t1$on_headers(200L, list())
  t1$on_bytes(sse('{"t":"text","v":"Hel"}'))
  expect_true(t1$retry$committed())
  t1$on_bytes(sse('{"t":"text","v":"lo"}'))
  t1$on_done(200L, list())
  expect_equal(log$types(), c("start", "text_delta", "text_delta", "done"))
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "Hello")
  # the request id the adapter cannot know is filled from the context (04 section 4.5)
  expect_equal(log$events[[1]]$request_id, "q000000000001")
  expect_equal(log$events[[4]]$message$request_id, "q000000000001")
  expect_equal(log$done[[1]]$request_id, "q000000000001")
  t1$on_done(200L, list())
  t1$on_fail(stream_condition("late", "network"))
  expect_length(log$done, 1L)
})

test_that("an in-stream retryable error before any delta is re-sent by the reactor", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  t1 = r$http[["t1"]]
  t1$on_headers(200L, list())
  t1$on_bytes(sse('{"t":"overloaded"}', '{"t":"text","v":"stale"}'))
  expect_length(r$retries, 1L)
  expect_equal(r$retries[[1]]$id, "t1")
  expect_equal(r$retries[[1]]$info$class, "overloaded")
  expect_false(t1$retry$committed())
  # P04 waits, reports the retry and re-sends the spec: a second head means "start over"
  t1$retry$on_retry("retry_start", list(attempt = 1L, delay = 0.5, class = "overloaded"))
  t1$on_headers(200L, list())
  t1$retry$on_retry("retry_end", list(attempt = 2L, ok = TRUE))
  t1$on_bytes(sse('{"t":"text","v":"ok"}'))
  t1$on_done(200L, list())
  expect_named(r$http, "t1")
  expect_equal(log$types(), c("start", "retry_start", "retry_end", "text_delta", "done"))
  expect_equal(log$events[[2]]$delay, 0.5)
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "ok")
})

test_that("a retryable error after a delta ends the stream with the partial message", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"par"}', '{"t":"overloaded"}'))
  expect_length(r$retries, 1L)
  expect_equal(log$types()[[length(log$events)]], "error")
  expect_equal(log$events[[length(log$events)]]$error$request_id, "q000000000001")
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_equal(log$done[[1]]$request_id, "q000000000001")
  expect_equal(msg_text(log$done[[1]]), "par")
})

test_that("setting the abort flag cancels the transfer and ends with an aborted message", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  provider_stream(model, stream_context(), list(signal = signal), emit = log$emit,
                  done = log$finish)
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"part"}'))
  watch = r$tasks[[1]]
  expect_true(watch())
  signal$aborted = TRUE
  expect_false(watch())
  expect_true("t1" %in% r$cancelled)
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "aborted")
  expect_equal(msg_text(log$done[[1]]), "part")
  expect_equal(log$events[[length(log$events)]]$reason, "aborted")
})

test_that("a run that settles while its stream is open lets go of the stream", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  run = local_run("streaming")
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish, run = run)
  watch = r$tasks[[1]]
  expect_true(watch())
  run$status = "error"
  expect_false(watch())
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"late"}'))
  expect_length(log$events, 0L)
  expect_length(log$done, 0L)
})

test_that("an adapter that fails to build ends the stream with one error event", {
  r = local_mock_reactor()
  model = local_stream_adapter(api = "test-broken",
                               build = function(model, context, opts) stop("bad request body"))
  log = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_true(is.na(id))
  expect_equal(log$types(), "error")
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_equal(log$done[[1]]$provider, "streamtest")
  expect_equal(log$done[[1]]$model, "m1")
  expect_match(log$done[[1]]$error_message, "bad request body", fixed = TRUE)
  expect_length(r$http, 0L)
})

test_that("a keyed provider without a credential is refused before anything starts", {
  r = local_mock_reactor()
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL)
  withr::local_envvar(GPTR_P05_TEST_KEY = "")
  model = local_stream_adapter(auth = "GPTR_P05_TEST_KEY")
  log = local_stream_log()
  expect_error(provider_stream(model, stream_context(), list(), emit = log$emit,
                               done = log$finish),
               class = "gptr_error_no_key")
  expect_length(r$http, 0L)
  expect_length(log$events, 0L)
})

test_that("a provider disabled in the settings is refused before anything starts", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  local_settings(providers = list(streamtest = list(enabled = FALSE)))
  log = local_stream_log()
  err = expect_error(provider_stream(model, stream_context(), list(), emit = log$emit,
                                     done = log$finish),
                     class = "gptr_error_not_available")
  expect_equal(err$member, "streamtest")
  expect_length(r$http, 0L)
})

test_that("a static-rate override from the settings reaches the limiter once (IC-64)", {
  local_mock_reactor()
  model = local_stream_adapter()
  local_settings(providers = list(streamtest = list(rate = list(requests_per_s = 2))))
  lim = new.env()
  lim$n = 0L
  lim$rate = NULL
  local_mocked_bindings(
    ratelimit_get = function(provider) list(rate = lim$rate),
    ratelimit_set = function(provider, rate) {
      lim$n = lim$n + 1L
      lim$rate = rate
      invisible(NULL)
    }
  )
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_equal(lim$n, 1L)
  expect_equal(lim$rate, list(requests_per_s = 2))
})

test_that("adapters receive the injected gate, MCP dispatcher and tool-result builder (IC-33)", {
  local_mock_reactor()
  seen = new.env()
  model = local_stream_adapter(build = function(model, context, opts) {
    seen$opts = opts
    list(url = "https://stream.example/v1/stream", method = "POST", headers = list(),
         body = "{}", stream = "sse")
  })
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  o = seen$opts
  expect_equal(o$gate(list(id = "c1", name = "r"))$decision, "deny")
  expect_equal(o$mcp_dispatch(list(jsonrpc = "2.0", id = 7L))$error$code, -32601L)
  tr = o$tool_result(gptr_tool_result("3 rows"), list(id = "c1", name = "r"))
  expect_equal(tr$role, "tool_result")
  expect_equal(tr$tool_call_id, "c1")
  expect_true(all(vapply(list(o$emit, o$retry, o$send), is.function, NA)))
  expect_true(is.environment(o$signal) && is.environment(o$state) && is.environment(o$memo))
  expect_equal(o$base_url, "https://stream.example")
  expect_null(o$credential)
  expect_equal(o$provider$id, "streamtest")
  mine = function(call) list(decision = "allow", reason = "test")
  provider_stream(model, stream_context(), list(gate = mine), emit = log$emit, done = log$finish)
  expect_identical(seen$opts$gate, mine)
  run = local_run()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish, run = run)
  expect_identical(seen$opts$signal, run$signal)
  expect_equal(seen$opts$run, "r0000000001")
  expect_equal(seen$opts$session, "s0000000000")
})

# ---- provider_stream(): beyond the plan's literal tests (IC-74, http_ndjson/http_json) ------

test_that("NDJSON lines and a whole JSON body reach the normaliser", {
  r = local_mock_reactor()
  kind = new.env()
  kind$stream = "ndjson"
  model = local_stream_adapter(build = function(model, context, opts) {
    list(url = "https://stream.example/v1/x", method = "POST", headers = list(), body = "{}",
         stream = kind$stream)
  })
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  t1 = r$http[["t1"]]
  t1$on_headers(200L, list())
  t1$on_bytes(charToRaw('{"t":"text","v":"a"}\n{"t":"text",'))
  t1$on_bytes(charToRaw('"v":"b"}\n{"t":"text","v":"c"}'))
  t1$on_done(200L, list())
  expect_equal(log$types(), c("start", "text_delta", "text_delta", "text_delta", "done"))
  expect_equal(msg_text(log$done[[1]]), "abc")
  kind$stream = "json"
  log2 = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log2$emit, done = log2$finish)
  t2 = r$http[["t2"]]
  t2$on_headers(200L, list())
  t2$on_bytes(charToRaw('{"t":"text",'))
  t2$on_bytes(charToRaw('"v":"whole"}'))
  expect_length(log2$events, 0L)
  t2$on_done(200L, list())
  expect_equal(log2$types(), c("start", "text_delta", "done"))
  expect_equal(msg_text(log2$done[[1]]), "whole")
  kind$stream = "xml"
  log3 = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log3$emit, done = log3$finish)
  expect_true(is.na(id))
  expect_equal(log3$types(), "error")
  expect_length(log3$done, 1L)
  expect_length(r$http, 2L)
})

test_that("transport failures and normaliser errors end the stream exactly once", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  r$http[["t1"]]$on_fail(stream_condition("No first response byte for 120 s.",
                                          c("timeout_first_byte", "timeout")))
  expect_equal(log$types(), "error")
  expect_equal(log$events[[1]]$error$class, "gptr_error_timeout_first_byte")
  expect_equal(log$events[[1]]$error$request_id, "q000000000001")
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "error")
  # a normaliser that throws: one error event, and the live transfer is cancelled
  log2 = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log2$emit, done = log2$finish)
  t2 = r$http[["t2"]]
  t2$on_headers(200L, list())
  t2$on_bytes(sse("not json"))
  t2$on_bytes(sse('{"t":"text","v":"late"}'))
  t2$on_done(200L, list())
  expect_equal(log2$types(), "error")
  expect_equal(log2$events[[1]]$error$class, "gptr_error_internal")
  expect_length(log2$done, 1L)
  expect_true("t2" %in% r$cancelled)
})

test_that("a retry hint the reactor neither re-sends nor fails keeps its parent class", {
  r = local_mock_reactor()
  # P04 already forgot the transfer (a hint flushed at on_done, or any http_json body)
  local_mocked_bindings(reactor_retry = function(id, info) invisible(FALSE))
  seen = new.env()
  model = local_stream_adapter(seen = seen)
  hint = function(cls) {
    log = local_stream_log()
    provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
    t = r$http[[length(r$http)]]
    t$on_headers(200L, list())
    t$on_bytes(sse(paste0('{"t":"retry","class":"', cls, '"}')))
    expect_equal(log$types(), c("start", "error"))
    expect_length(log$done, 1L)
    seen$cnd
  }
  # contract 2.2 / D-012: timeout_* classes have the parent timeout, every other one provider
  cnd = hint("timeout_idle")
  expect_true(inherits(cnd, "gptr_error_timeout_idle") && inherits(cnd, "gptr_error_timeout"))
  expect_false(inherits(cnd, "gptr_error_provider"))
  cnd = hint("overloaded")
  expect_true(inherits(cnd, "gptr_error_overloaded") && inherits(cnd, "gptr_error_provider"))
  expect_false(inherits(cnd, "gptr_error_timeout"))
  expect_true(all(c("t1", "t2") %in% r$cancelled))
})

test_that("a decision-only model never streams as a conversation (IC-74)", {
  r = local_mock_reactor()
  local_mocked_bindings(provider_credential = function(provider) stop("credential looked up"),
                        provider_preflight = function(...) stop("preflight reached"))
  log = local_stream_log()
  clef = model_resolve("ollama/clef-flash")
  expect_equal(clef$type, "classifier")
  err = expect_error(provider_stream(clef, stream_context(), list(), emit = log$emit,
                                     done = log$finish),
                     class = "gptr_error_not_available")
  expect_equal(err$member, "ollama/clef-flash")
  expect_match(conditionMessage(err), "decision-only", fixed = TRUE)
  # a chat-typed model whose adapter only classifies is refused as well
  decide = list(build = function(model, state, questions, opts) list(),
                parse = function(model, status, headers, body, questions) list())
  off = gptr_register(gptr_adapter("test-decide", transport = "http_json", classify = decide))
  withr::defer(off())
  model = local_stream_adapter()
  model$api = "test-decide"
  err = expect_error(provider_stream(model, stream_context(), list(), emit = log$emit,
                                     done = log$finish),
                     class = "gptr_error_not_available")
  expect_equal(err$member, "test-decide")
  expect_length(r$http, 0L)
  expect_length(log$events, 0L)
})

test_that("the checked model of the request preflight reaches the adapter (IC-74)", {
  local_mock_reactor()
  seen = new.env()
  model = local_stream_adapter(build = function(model, context, opts) {
    seen$model = model
    list(url = "https://stream.example/v1/stream", method = "POST", headers = list(),
         body = "{}", stream = "sse")
  })
  local_mocked_bindings(provider_preflight = function(model, provider, safety = NULL) {
    seen$safety = safety
    seen$provider = provider$id
    model$context = 4096
    model
  })
  log = local_stream_log()
  run = local_run()
  run$opts = list(safety = list(ollama_local_only = FALSE))
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish, run = run)
  expect_equal(seen$model$context, 4096)
  expect_equal(seen$provider, "streamtest")
  expect_false(seen$safety$ollama_local_only)
  # no protected record: preflight's default (local-only) applies
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_null(seen$safety)
  # a caller's record can only tighten the run's snapshot
  provider_stream(model, stream_context(), list(safety = list(ollama_local_only = TRUE)),
                  emit = log$emit, done = log$finish, run = run)
  expect_true(seen$safety$ollama_local_only)
  # a run without a snapshot counts as local-only, so a caller's record cannot relax it
  provider_stream(model, stream_context(), list(safety = list(ollama_local_only = FALSE)),
                  emit = log$emit, done = log$finish, run = local_run())
  expect_true(seen$safety$ollama_local_only)
  expect_error(provider_stream(model, stream_context(),
                               list(safety = list(ollama_local_only = NA)),
                               emit = log$emit, done = log$finish),
               class = "gptr_error_invalid_argument")
})

test_that("an Ollama chat model fails before egress unless locality is established (IC-74)", {
  r = local_mock_reactor()
  seen = new.env()
  seen$built = 0L
  off = gptr_register(gptr_adapter(
    "openai-completions", transport = "http_sse",
    build = function(model, context, opts) {
      seen$built = seen$built + 1L
      stop("no payload may be built")
    },
    parse = function(model, opts) stop("no normaliser may be built")
  ))
  withr::defer(off())
  local_mocked_bindings(provider_credential = function(provider) stop("credential looked up"))
  log = local_stream_log()
  go = function(model, opts = list(), run = NULL) {
    provider_stream(model, stream_context(), opts, emit = log$emit, done = log$finish,
                    run = run)
  }
  qwen = model_resolve("ollama/qwen3:1.7b")
  err = expect_error(go(qwen), class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "model_prepare()", fixed = TRUE)
  expect_error(go(model_resolve("ollama/qwen3:1.7b-cloud")), class = "gptr_error_untrusted")
  relaxed = local_run()
  relaxed$opts = list(safety = list(ollama_local_only = FALSE))
  strict = local_run()
  strict$opts = list(safety = list(ollama_local_only = TRUE))
  local_settings(providers = list(ollama = list(base_url = "http://192.0.2.10:11434/v1")))
  err = expect_error(go(model_resolve("ollama/qwen3:1.7b")), class = "gptr_error_untrusted")
  expect_equal(err$origin, "http://192.0.2.10:11434")
  # per-request options cannot relax the run's protected snapshot
  expect_error(go(qwen, list(safety = list(ollama_local_only = FALSE)), strict),
               class = "gptr_error_untrusted")
  # nor can they relax a run that carries no snapshot (missing record = local-only)
  expect_error(go(qwen, list(safety = list(ollama_local_only = FALSE)), local_run()),
               class = "gptr_error_untrusted")
  # relaxing local-only never replaces discovery evidence
  expect_error(go(qwen, run = relaxed), class = "gptr_error_not_available")
  expect_equal(seen$built, 0L)
  expect_length(r$http, 0L)
  expect_length(log$events, 0L)
  expect_length(log$done, 0L)
})

# ---- provider_stream(): P04's real reactor and P01's loopback mock server -------------------

# A minimal Anthropic-shaped adapter for the mock's `overload` scenario: an SSE `error` event is
# the in-stream overload a normaliser reports through opts$retry() (04 section 8.1)
local_loop_adapter = function(url, .env = parent.frame()) {
  parse = function(model, opts) {
    s = new.env()
    s$text = character()
    s$done = FALSE
    current = function(stop = "stop") {
      msg_assistant(list(block_text(paste(s$text, collapse = ""))), api = model$api,
                    provider = model$provider, model = model$id, stop_reason = stop,
                    timestamp = 1)
    }
    list(
      push = function(ev) {
        d = json_decode(ev$data)
        type = ev$event %||% ""
        if (identical(type, "message_start")) {
          opts$emit(ev_new("start", api = model$api, provider = model$provider,
                           model = model$id, request_id = NULL, response_id = NULL))
        } else if (identical(type, "content_block_delta")) {
          s$text = c(s$text, d$delta$text)
          opts$emit(ev_new("text_delta", index = 1L, delta = d$delta$text))
        } else if (identical(type, "error")) {
          opts$retry(list(class = "overloaded", status = 529L))
        } else if (identical(type, "message_stop")) {
          s$done = TRUE
          opts$emit(ev_new("done", reason = "stop", message = current(), usage = NULL))
          return(TRUE)
        }
        FALSE
      },
      finish = function() {
        m = current()
        if (!s$done) opts$emit(ev_new("done", reason = "stop", message = m, usage = NULL))
        m
      },
      fail = function(cnd) {
        m = current("error")
        m$error_message = conditionMessage(cnd)
        opts$emit(ev_new("error", reason = "error", message = m,
                         error = list(class = class(cnd)[[1]], status = cnd$status,
                                      request_id = NULL, retry_after = NULL)))
        m
      },
      message = function() current()
    )
  }
  build = function(model, context, opts) {
    list(url = paste0(opts$base_url, "/v1/messages"), method = "POST",
         headers = list(`content-type` = "application/json"),
         body = "{\"model\":\"mock-1\",\"stream\":true,\"messages\":[]}", stream = "sse")
  }
  off1 = gptr_register(gptr_adapter("test-loop", transport = "http_sse", build = build,
                                    parse = parse))
  off2 = gptr_register(gptr_provider("mockloop", api = "test-loop", base_url = url, local = TRUE,
                                     offline = TRUE, models = list(list(id = "mock-1"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  model_resolve("mockloop/mock-1")
}

test_that("an overload before any delta is re-sent by P04's reactor on the same transfer", {
  srv = local_mock_server("overload", attempts = 1L)
  model = local_loop_adapter(srv$url)
  log = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 30))
  expect_equal(log$types(), c("start", "retry_start", "retry_end", rep("text_delta", 3L),
                              "done"))
  expect_equal(log$events[[2]]$class, "overloaded")
  expect_equal(log$events[[2]]$attempt, 1L)
  expect_true(log$events[[3]]$ok)
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "tok01 tok02 tok03 ")
  expect_equal(log$done[[1]]$request_id, "q000000000001")
  expect_identical(nrow(srv$log()), 2L)
  r = reactor_get()
  expect_false(exists(id, envir = r$transfers, inherits = FALSE))
  expect_identical(ls(r$tasks), character())
})

test_that("an overload after a committed delta fails at once with the partial message", {
  srv = local_mock_server("overload", attempts = 1L, after = 1L)
  model = local_loop_adapter(srv$url)
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 30))
  expect_equal(log$types(), c("start", "text_delta", "error"))
  err = log$events[[3]]$error
  expect_equal(err$class, "gptr_error_overloaded")
  expect_equal(err$status, 529L)
  expect_equal(err$request_id, "q000000000001")
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_equal(msg_text(log$done[[1]]), "tok01 ")
  expect_identical(nrow(srv$log()), 1L)
  expect_identical(ls(reactor_get()$tasks), character())
})

# ---- provider_stream(): inprocess (the fake provider on the real reactor) -------------------

test_that("the fake provider streams through the inprocess transport", {
  local_fake_provider(list("hello there"))
  log = local_stream_log()
  provider_stream(model_resolve("fake/fake-1"), stream_context(), list(), emit = log$emit,
                  done = log$finish)
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 5))
  types = log$types()
  expect_equal(types[[1]], "start")
  expect_equal(types[[length(types)]], "done")
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "hello there")
})

test_that("an aborted inprocess stream ends with stop_reason aborted", {
  local_fake_provider(list(list(hang = TRUE)))
  log = local_stream_log()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  provider_stream(model_resolve("fake/fake-1"), stream_context(), list(signal = signal),
                  emit = log$emit, done = log$finish)
  expect_true(reactor_pump(until = function() length(log$events) > 0L, timeout = 5))
  signal$aborted = TRUE
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 5))
  expect_equal(log$done[[1]]$stop_reason, "aborted")
})

# ---- provider_stream(): process_jsonl on scripted process functions -------------------------

# Additions to the plan's helper: reactor_cancel() of a watcher id it handed out acts as P04's
# (the watcher is gone, its child killed: `killed` counts it); `removed` lists the job rows
# removed; `job$stop` is the row's stop().
local_mock_process = function(.env = parent.frame()) {
  pr = new.env()
  pr$spawned = list()
  pr$watchers = list()
  pr$written = character()
  pr$closed = 0L
  pr$killed = 0L
  pr$watch_ids = character()
  pr$cancelled = character()
  pr$removed = character()
  testthat::local_mocked_bindings(
    reactor_cancel = function(ids) {
      live = ids %in% pr$watch_ids & !ids %in% pr$cancelled
      pr$cancelled = c(pr$cancelled, ids)
      pr$killed = pr$killed + sum(live)
      invisible(sum(live | !ids %in% pr$watch_ids))
    },
    proc_spawn = function(command, args = character(), env = NULL, wd = NULL, stdin = NULL,
                          stdout = "|", stderr = "|", cleanup_tree = TRUE,
                          supervise = TRUE) {
      k = length(pr$spawned) + 1L
      pr$spawned[[k]] = list(command = command, args = args, env = env, stdin = stdin)
      handle = new.env()
      handle$get_pid = function() 4241L + k
      handle
    },
    reactor_proc = function(proc, on_line, on_exit, run = NULL, stream = "stdout",
                            on_stderr = NULL) {
      pr$watchers[[length(pr$watchers) + 1L]] = list(on_line = on_line, on_exit = on_exit)
      pr$on_line = on_line
      pr$on_exit = on_exit
      id = paste0("t", 50L + length(pr$watchers))
      pr$watch_ids = c(pr$watch_ids, id)
      id
    },
    write_all = function(p, data) {
      pr$written = c(pr$written, data)
      invisible(p)
    },
    write_close = function(p) {
      pr$closed = pr$closed + 1L
      invisible(p)
    },
    job_add = function(kind, id, name, pid = NA, stop, status = function() "running") {
      pr$job = list(kind = kind, id = id, name = name, pid = pid, stop = stop)
      invisible(id)
    },
    job_remove = function(id) {
      pr$removed = c(pr$removed, id)
      invisible(TRUE)
    },
    kill_all = function(p, grace = 2) {
      pr$killed = pr$killed + 1L
      invisible(TRUE)
    },
    child_env = function(profile, pass = character(), set = character(), provider = NULL) {
      pr$profile = profile
      pr$env_provider = provider
      c(PATH = "/usr/bin", set)
    },
    .env = .env
  )
  pr
}

# A JSON-lines adapter: `start` only when no child runs (or always with close_stdin),
# {"type":"delta","v":..} are deltas, {"type":"result"} ends the turn, {"type":"ping"} is a
# control request answered with {"type":"pong"} through opts$send(). Additions to the plan's
# helper: `start_with` replaces the scripted `fakecli` start (a real child), `seen$opts` collects
# each turn's opts, `seen$units` each unit pushed, and {"type":"boom"} makes the normaliser fail.
local_process_adapter = function(close_stdin = FALSE, start_with = NULL, seen = NULL,
                                 .env = parent.frame()) {
  build = function(model, context, opts) {
    start = if (close_stdin || is.null(opts$state$process)) {
      start_with %||% list(command = "fakecli", args = c("--json"), env_profile = "cli-claude",
                           env = c(FAKE_CLI = "1"), wd = NULL)
    }
    list(start = start, send = list(list(type = "user", text = context$text)),
         close_stdin = close_stdin)
  }
  parse = function(model, opts) {
    if (is.environment(seen)) seen$opts[[length(seen$opts) + 1L]] = opts
    s = new.env()
    s$text = character()
    current = function() {
      msg_assistant(list(block_text(paste(s$text, collapse = ""))), api = model$api,
                    provider = model$provider, model = model$id, route = "plan-cli",
                    timestamp = 1)
    }
    list(
      push = function(ev) {
        if (is.environment(seen)) seen$units[[length(seen$units) + 1L]] = ev
        type = ev$obj$type
        if (identical(type, "boom")) stop("normaliser broke")
        if (identical(type, "ping")) opts$send(list(type = "pong"))
        if (identical(type, "delta")) {
          if (!length(s$text)) {
            opts$emit(ev_new("start", api = model$api, provider = model$provider,
                             model = model$id, request_id = "q1", response_id = NULL))
          }
          s$text = c(s$text, ev$obj$v)
          opts$emit(ev_new("text_delta", index = 1L, delta = ev$obj$v))
        }
        if (identical(type, "result")) {
          opts$emit(ev_new("done", reason = "stop", message = current(), usage = NULL))
          return(TRUE)
        }
        FALSE
      },
      finish = function() {
        m = current()
        opts$emit(ev_new("done", reason = "stop", message = m, usage = NULL))
        m
      },
      fail = function(cnd) current(),
      message = function() current()
    )
  }
  api = if (close_stdin) "test-proc-eof" else "test-proc"
  off1 = gptr_register(gptr_adapter(api, transport = "process_jsonl", build = build,
                                    parse = parse))
  off2 = gptr_register(gptr_provider("proctest", api = api, type = "cli",
                                     models = list(list(id = "default"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  model_resolve("proctest/default")
}

test_that("process_jsonl: one supervised child, JSON lines both ways, one done per turn", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  state = new.env()
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                  done = log$finish)
  expect_length(pr$spawned, 1L)
  expect_equal(pr$spawned[[1]]$command, "fakecli")
  expect_equal(pr$spawned[[1]]$stdin, "|")
  expect_equal(pr$profile, "cli-claude")
  expect_null(pr$env_provider)
  expect_equal(pr$job$kind, "cli")
  expect_equal(pr$written, "{\"type\":\"user\",\"text\":\"hi\"}\n")
  expect_equal(pr$closed, 0L)
  pr$on_line("{\"type\":\"ping\"}")
  expect_equal(pr$written[[2]], "{\"type\":\"pong\"}\n")
  pr$on_line("not json at all")
  pr$on_line("{\"type\":\"delta\",\"v\":\"Hi!\"}")
  pr$on_line("{\"type\":\"result\"}")
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "Hi!")
  log2 = local_stream_log()
  provider_stream(model, stream_context("again"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  expect_length(pr$spawned, 1L)
  pr$on_line("{\"type\":\"delta\",\"v\":\"Again\"}")
  pr$on_line("{\"type\":\"result\"}")
  expect_equal(msg_text(log2$done[[1]]), "Again")
  expect_length(log$done, 1L)
})

test_that("process_jsonl with close_stdin writes the turn, then closes stdin", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter(close_stdin = TRUE)
  log = local_stream_log()
  provider_stream(model, stream_context("once"), list(state = new.env()), emit = log$emit,
                  done = log$finish)
  expect_length(pr$spawned, 1L)
  expect_equal(pr$spawned[[1]]$stdin, "|")
  expect_equal(pr$written, "{\"type\":\"user\",\"text\":\"once\"}\n")
  expect_equal(pr$closed, 1L)
  pr$on_line("{\"type\":\"delta\",\"v\":\"done\"}")
  pr$on_exit(0L)
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "done")
})

test_that("a replaced child's late output and exit never reach the next turn", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter(close_stdin = TRUE)
  state = new.env()
  log1 = local_stream_log()
  provider_stream(model, stream_context("one"), list(state = state), emit = log1$emit,
                  done = log1$finish)
  first = pr$watchers[[1]]
  first$on_line("{\"type\":\"delta\",\"v\":\"A\"}")
  first$on_line("{\"type\":\"result\"}")
  log2 = local_stream_log()
  provider_stream(model, stream_context("two"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  expect_length(pr$spawned, 2L)
  expect_equal(pr$killed, 1L)
  first$on_line("{\"type\":\"delta\",\"v\":\"stale\"}")
  first$on_exit(0L)
  expect_length(log2$done, 0L)
  second = pr$watchers[[2]]
  second$on_line("{\"type\":\"delta\",\"v\":\"B\"}")
  second$on_exit(0L)
  expect_equal(msg_text(log2$done[[1]]), "B")
  expect_equal(msg_text(log1$done[[1]]), "A")
})

# ---- provider_stream(): the inprocess transport on a scripted reactor -----------------------

# An inprocess adapter whose generator plays `seen$steps` (read when the stream starts; a
# function step is called, so it may throw); `seen$calls` counts the generator calls
local_gen_adapter = function(steps = list(), .env = parent.frame()) {
  seen = new.env()
  seen$steps = steps
  seen$calls = 0L
  stream = function(model, context, opts) {
    steps = seen$steps
    function() {
      seen$calls = seen$calls + 1L
      s = steps[[min(seen$calls, length(steps))]]
      if (is.function(s)) s() else s
    }
  }
  off1 = gptr_register(gptr_adapter("test-gen", transport = "inprocess", stream = stream))
  off2 = gptr_register(gptr_provider("gentest", api = "test-gen", local = TRUE, offline = TRUE,
                                     models = list(list(id = "g1"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  seen$model = model_resolve("gentest/g1")
  seen
}

gen_start = function() {
  ev_new("start", api = "test-gen", provider = "gentest", model = "g1", request_id = NULL,
         response_id = NULL)
}

gen_delta = function(v) ev_new("text_delta", index = 1L, delta = v)

gen_step = function(..., wait = 0) list(events = list(...), wait = wait)

test_that("an inprocess generator that throws, misbehaves or stops early ends the stream once", {
  r = local_mock_reactor()
  seen = local_gen_adapter()
  first = gen_step(gen_start(), gen_delta("a"))
  cases = list(
    list(steps = list(first, function() stop("generator broke")), message = "generator broke"),
    list(steps = list(first, "not a step"), message = "malformed"),
    list(steps = list(first, list(events = list("not an event"))), message = "malformed"),
    list(steps = list(first, NULL), message = "without a terminal event")
  )
  for (case in cases) {
    seen$steps = case$steps
    seen$calls = 0L
    log = local_stream_log()
    id = provider_stream(seen$model, stream_context(), list(), emit = log$emit,
                         done = log$finish)
    expect_equal(id, paste0("t", 200L + length(r$tasks)))
    task = r$tasks[[length(r$tasks)]]
    expect_true(task())
    expect_false(task())
    expect_false(task())
    expect_equal(seen$calls, 2L)
    expect_equal(log$types(), c("start", "text_delta", "error"))
    err = log$events[[3]]
    expect_equal(err$error$class, "internal")
    expect_equal(err$error$request_id, "q000000000001")
    expect_match(err$message$error_message, case$message, fixed = TRUE)
    expect_length(log$done, 1L)
    expect_equal(log$done[[1]]$stop_reason, "error")
    expect_equal(log$done[[1]]$provider, "gentest")
    expect_equal(msg_text(log$done[[1]]), "a")
  }
})

test_that("the inprocess transport calls the generator again after `wait` seconds", {
  r = local_mock_reactor()
  clock = new.env()
  clock$t = 10
  local_mocked_bindings(reactor_now = function() clock$t)
  final = msg_assistant(list(block_text("x")), api = "test-gen", provider = "gentest",
                        model = "g1", timestamp = 1)
  seen = local_gen_adapter(list(gen_step(gen_start(), wait = 2), gen_step(gen_delta("x")),
                                gen_step(ev_new("done", reason = "stop", message = final,
                                                usage = NULL))))
  log = local_stream_log()
  provider_stream(seen$model, stream_context(), list(), emit = log$emit, done = log$finish)
  task = r$tasks[[1]]
  expect_true(task())
  expect_equal(seen$calls, 1L)
  clock$t = 11.9
  expect_true(task())
  expect_equal(seen$calls, 1L)
  clock$t = 12
  expect_true(task())
  expect_equal(seen$calls, 2L)
  expect_false(task())
  expect_equal(seen$calls, 3L)
  expect_equal(log$types(), c("start", "text_delta", "done"))
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$request_id, "q000000000001")
})

test_that("an abort gives the inprocess generator two calls before the glue ends the stream", {
  r = local_mock_reactor()
  seen = local_gen_adapter(list(gen_step(gen_start(), gen_delta("p"), wait = 60), gen_step()))
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  log = local_stream_log()
  provider_stream(seen$model, stream_context(), list(signal = signal), emit = log$emit,
                  done = log$finish)
  task = r$tasks[[1]]
  expect_true(task())
  expect_equal(seen$calls, 1L)
  signal$aborted = TRUE
  # the abort does not wait for the generator's `wait`
  expect_true(task())
  expect_true(task())
  expect_equal(seen$calls, 3L)
  expect_false(task())
  expect_equal(seen$calls, 3L)
  expect_equal(log$types(), c("start", "text_delta", "error"))
  expect_equal(log$events[[3]]$reason, "aborted")
  expect_equal(log$events[[3]]$error$class, "aborted")
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "aborted")
  expect_equal(log$done[[1]]$error_message, "user")
  expect_equal(msg_text(log$done[[1]]), "p")
})

test_that("an inprocess stream whose run settles is let go without a done", {
  r = local_mock_reactor()
  seen = local_gen_adapter(list(gen_step(gen_start()), gen_step(gen_delta("late"))))
  run = local_run("streaming")
  log = local_stream_log()
  provider_stream(seen$model, stream_context(), list(), emit = log$emit, done = log$finish,
                  run = run)
  task = r$tasks[[1]]
  expect_true(task())
  run$status = "error"
  expect_false(task())
  expect_equal(seen$calls, 1L)
  expect_equal(log$types(), "start")
  expect_length(log$done, 0L)
})

# ---- provider_stream(): process_jsonl failures and abort ------------------------------------

test_that("an aborted process_jsonl turn forgets and kills its child", {
  r = local_mock_reactor()
  pr = local_mock_process()
  seen = new.env()
  seen$opts = list()
  model = local_process_adapter(seen = seen)
  state = new.env()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = state, signal = signal),
                  emit = log$emit, done = log$finish)
  first = pr$watchers[[1]]
  first$on_line("{\"type\":\"delta\",\"v\":\"par\"}")
  watch = r$tasks[[1]]
  expect_true(watch())
  signal$aborted = TRUE
  expect_false(watch())
  # through P04's reactor_cancel() of the child's watcher, which kills it; the job row goes
  expect_identical(pr$cancelled, "t51")
  expect_equal(pr$killed, 1L)
  expect_identical(pr$removed, pr$job$id)
  expect_null(state$process)
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "aborted")
  expect_equal(msg_text(log$done[[1]]), "par")
  n = length(log$events)
  first$on_line("{\"type\":\"delta\",\"v\":\"late\"}")
  first$on_exit(0L)
  expect_length(log$events, n)
  expect_length(log$done, 1L)
  # the next turn starts a new child
  signal$aborted = FALSE
  log2 = local_stream_log()
  provider_stream(model, stream_context("again"), list(state = state, signal = signal),
                  emit = log2$emit, done = log2$finish)
  expect_length(pr$spawned, 2L)
  # a late opts$send() of the aborted turn writes nothing; the open turn writes to its child
  n = length(pr$written)
  expect_false(seen$opts[[1]]$send(list(type = "late")))
  expect_length(pr$written, n)
  expect_true(seen$opts[[2]]$send(list(type = "pong")))
  expect_equal(pr$written[[n + 1L]], "{\"type\":\"pong\"}\n")
  pr$watchers[[2]]$on_line("{\"type\":\"delta\",\"v\":\"B\"}")
  pr$watchers[[2]]$on_line("{\"type\":\"result\"}")
  expect_equal(msg_text(log2$done[[1]]), "B")
  expect_length(log$done, 1L)
  # a turn that reuses the session's child stops it through that child's watcher and row
  job2 = pr$job$id
  log3 = local_stream_log()
  provider_stream(model, stream_context("third"), list(state = state, signal = signal),
                  emit = log3$emit, done = log3$finish)
  expect_length(pr$spawned, 2L)
  expect_false(job2 %in% pr$removed)
  signal$aborted = TRUE
  expect_false(r$tasks[[length(r$tasks)]]())
  expect_equal(log3$done[[1]]$stop_reason, "aborted")
  expect_identical(pr$cancelled, c("t51", "t52"))
  expect_equal(pr$killed, 2L)
  expect_true(job2 %in% pr$removed)
  expect_null(state$process)
})

test_that("a process_jsonl turn that fails locally forgets and kills its child", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  state = new.env()
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                  done = log$finish)
  first = pr$watchers[[1]]
  first$on_line("{\"type\":\"delta\",\"v\":\"x\"}")
  first$on_line("{\"type\":\"boom\"}")
  expect_equal(log$types(), c("start", "text_delta", "error"))
  expect_match(log$done[[1]]$error_message, "normaliser broke", fixed = TRUE)
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_identical(pr$cancelled, "t51")
  expect_equal(pr$killed, 1L)
  expect_identical(pr$removed, pr$job$id)
  expect_null(state$process)
  first$on_line("{\"type\":\"delta\",\"v\":\"late\"}")
  first$on_exit(1L)
  expect_length(log$events, 3L)
  expect_length(log$done, 1L)
  # a write that fails after the child started ends the turn and kills that child too
  local_mocked_bindings(write_all = function(p, data) stop("stdin pipe closed"))
  log2 = local_stream_log()
  id = provider_stream(model, stream_context("two"), list(state = state), emit = log2$emit,
                       done = log2$finish)
  expect_true(is.na(id))
  expect_length(pr$spawned, 2L)
  expect_identical(pr$cancelled, c("t51", "t52"))
  expect_equal(pr$killed, 2L)
  expect_true(pr$job$id %in% pr$removed)
  expect_null(state$process)
  expect_equal(log2$types(), "error")
  expect_length(log2$done, 1L)
  expect_match(log2$done[[1]]$error_message, "stdin pipe closed", fixed = TRUE)
  expect_equal(log2$done[[1]]$provider, "proctest")
  # a child whose watcher could not be registered is killed directly; its row goes too
  local_mocked_bindings(reactor_proc = function(...) stop("no watcher"))
  log3 = local_stream_log()
  id = provider_stream(model, stream_context("three"), list(state = state), emit = log3$emit,
                       done = log3$finish)
  expect_true(is.na(id))
  expect_length(pr$spawned, 3L)
  expect_identical(pr$cancelled, c("t51", "t52"))
  expect_equal(pr$killed, 3L)
  expect_true(pr$job$id %in% pr$removed)
  expect_null(state$process)
  expect_match(log3$done[[1]]$error_message, "no watcher", fixed = TRUE)
})

# P06's run_abort() and run_settle() cancel the id provider_stream() returned, which for
# process_jsonl is the abort watch: the turn must still end and drop its child.
test_that("a process_jsonl turn whose watch was cancelled ends at its child's next line or exit", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  # one turn with a delta; then the abort flag (or not), the cancelled id, the run's status
  turn = function(status, abort) {
    run = local_run("streaming")
    state = new.env()
    log = local_stream_log()
    id = provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                         done = log$finish, run = run)
    child = pr$watchers[[length(pr$watchers)]]
    child$on_line("{\"type\":\"delta\",\"v\":\"par\"}")
    run$signal$aborted = abort
    reactor_cancel(id)
    run$status = status
    list(state = state, log = log, child = child)
  }
  # run_settle() mid-turn: the line is not pushed (no pong), the turn is let go without a done
  t1 = turn("error", abort = FALSE)
  n = length(pr$written)
  t1$child$on_line("{\"type\":\"ping\"}")
  expect_length(pr$written, n)
  expect_equal(pr$killed, 1L)
  expect_null(t1$state$process)
  t1$child$on_line("{\"type\":\"delta\",\"v\":\"late\"}")
  t1$child$on_exit(0L)
  expect_equal(t1$log$types(), c("start", "text_delta"))
  expect_length(t1$log$done, 0L)
  # run_abort(): the line ends the turn as aborted (as the watch would) and kills the child
  t2 = turn("aborted", abort = TRUE)
  t2$child$on_line("{\"type\":\"ping\"}")
  expect_length(pr$written, n + 1L)
  expect_equal(pr$killed, 2L)
  expect_null(t2$state$process)
  expect_equal(t2$log$types(), c("start", "text_delta", "error"))
  expect_length(t2$log$done, 1L)
  expect_equal(t2$log$done[[1]]$stop_reason, "aborted")
  expect_equal(msg_text(t2$log$done[[1]]), "par")
  # the exit of an aborted turn's child ends it as aborted (the normaliser's finish() says
  # stop); the child is gone, so nothing is killed
  t3 = turn("streaming", abort = TRUE)
  t3$child$on_exit(0L)
  expect_equal(pr$killed, 2L)
  expect_null(t3$state$process)
  expect_length(t3$log$done, 1L)
  expect_equal(t3$log$done[[1]]$stop_reason, "aborted")
  # the exit after the run settled lets go of the turn
  t4 = turn("error", abort = FALSE)
  t4$child$on_exit(0L)
  expect_equal(pr$killed, 2L)
  expect_null(t4$state$process)
  expect_equal(t4$log$types(), c("start", "text_delta"))
  expect_length(t4$log$done, 0L)
})

test_that("a new turn closes the session's earlier turn whose watch was cancelled", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  state = new.env()
  run1 = local_run("streaming")
  log1 = local_stream_log()
  id1 = provider_stream(model, stream_context("one"), list(state = state), emit = log1$emit,
                        done = log1$finish, run = run1)
  first = pr$watchers[[1]]
  first$on_line("{\"type\":\"delta\",\"v\":\"one-1\"}")
  # P06's run_abort(): the flag, the cancelled id, the settled run; the child stays silent
  run1$signal$aborted = TRUE
  reactor_cancel(id1)
  run1$status = "aborted"
  run2 = local_run("requesting")
  log2 = local_stream_log()
  provider_stream(model, stream_context("two"), list(state = state), emit = log2$emit,
                  done = log2$finish, run = run2)
  expect_length(pr$spawned, 2L)
  expect_true("t51" %in% pr$cancelled)
  expect_equal(pr$killed, 1L)
  expect_length(log1$done, 0L)
  first$on_line("{\"type\":\"delta\",\"v\":\"one-2\"}")
  first$on_line("{\"type\":\"result\"}")
  first$on_exit(0L)
  expect_length(log2$events, 0L)
  expect_length(log2$done, 0L)
  second = pr$watchers[[2]]
  second$on_line("{\"type\":\"delta\",\"v\":\"two-1\"}")
  second$on_line("{\"type\":\"result\"}")
  expect_length(log2$done, 1L)
  expect_equal(msg_text(log2$done[[1]]), "two-1")
  expect_equal(log1$types(), c("start", "text_delta"))
  expect_length(log1$done, 0L)
})

test_that("process_jsonl pushes each JSON line as list(data, obj) and ignores other lines", {
  local_mock_reactor()
  pr = local_mock_process()
  seen = new.env()
  model = local_process_adapter(seen = seen)
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = new.env()), emit = log$emit,
                  done = log$finish)
  line = "{\"type\":\"delta\",\"v\":\"x y\",\"n\":[1,2]}"
  pr$on_line("noise")
  pr$on_line(line)
  expect_length(seen$units, 1L)
  expect_named(seen$units[[1]], c("data", "obj"))
  expect_identical(seen$units[[1]]$data, line)
  expect_identical(seen$units[[1]]$obj, json_decode(line))
  expect_equal(log$types(), c("start", "text_delta"))
})

test_that("stopping a child's job row cancels its watcher; the open turn hears the exit later", {
  local_mock_reactor()
  pr = local_mock_process()
  timers = new.env()
  timers$fns = list()
  local_mocked_bindings(reactor_timer = function(at, fn, run = NULL) {
    timers$fns[[length(timers$fns) + 1L]] = fn
    paste0("t", 300L + length(timers$fns))
  })
  model = local_process_adapter()
  state = new.env()
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                  done = log$finish)
  pr$on_line("{\"type\":\"delta\",\"v\":\"par\"}")
  # gptr_jobs(kill = TRUE) calls the row's stop(): P04's reactor_cancel() of the watcher kills
  # the child and reports no exit, so the row goes now and the exit reaches the turn from the
  # next pump iteration, as P04 reports an exit
  job = pr$job
  job$stop()
  expect_identical(pr$cancelled, "t51")
  expect_equal(pr$killed, 1L)
  expect_identical(pr$removed, job$id)
  expect_null(state$process)
  expect_length(log$done, 0L)
  expect_length(timers$fns, 1L)
  timers$fns[[1]]()
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "par")
  expect_equal(log$types(), c("start", "text_delta", "done"))
  # the next turn starts a new child; stopping it after its turn ended reaches no turn
  log2 = local_stream_log()
  provider_stream(model, stream_context("again"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  expect_length(pr$spawned, 2L)
  pr$on_line("{\"type\":\"result\"}")
  expect_length(log2$done, 1L)
  pr$job$stop()
  expect_identical(pr$cancelled, c("t51", "t52"))
  expect_equal(pr$killed, 2L)
  expect_null(state$process)
  for (fn in timers$fns[-1L]) fn()
  expect_length(log2$done, 1L)
  expect_length(log$done, 1L)
})

test_that("process_jsonl passes start's args to proc_spawn() and its env to child_env()", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = new.env()), emit = log$emit,
                  done = log$finish)
  expect_equal(pr$spawned[[1]]$args, "--json")
  expect_equal(pr$spawned[[1]]$env[["FAKE_CLI"]], "1")
  expect_equal(pr$spawned[[1]]$env[["PATH"]], "/usr/bin")
})

test_that("a list env reaches child_env() as given; list args are flattened", {
  local_mock_reactor()
  pr = local_mock_process()
  got = new.env()
  local_mocked_bindings(child_env = function(profile, pass = character(), set = character(),
                                             provider = NULL) {
    got$profile = profile
    got$set = set
    c(PATH = "/usr/bin")
  })
  # a list env may hold secret handles (P20's codex token), which unlist() would break
  handle = structure(list(id = "k0000001", name = "GPTR_MCP_TOKEN", fp = "abc123"),
                     class = "gptr_secret")
  play = function(start) {
    model = local_process_adapter(close_stdin = TRUE, start_with = start)
    log = local_stream_log()
    provider_stream(model, stream_context("hi"), list(state = new.env()), emit = log$emit,
                    done = log$finish)
  }
  env = list(GPTR_MCP_TOKEN = handle, MODE = "x")
  play(list(command = "fakecli", args = list("exec", "--json"), env_profile = "cli-codex",
            env = env))
  expect_equal(got$profile, "cli-codex")
  expect_identical(got$set, env)
  expect_identical(pr$spawned[[1]]$args, c("exec", "--json"))
  # chr args keep their attributes (the verbatim flag proc_spawn() reads)
  play(list(command = "fakecli", args = structure("--json", verbatim = TRUE),
            env_profile = "cli-codex"))
  expect_identical(got$set, character())
  expect_identical(pr$spawned[[2]]$args, structure("--json", verbatim = TRUE))
})

test_that("malformed process specs end the stream before any child starts", {
  r = local_mock_reactor()
  pr = local_mock_process()
  seen = new.env()
  noop = function(model, opts) {
    list(push = function(ev) FALSE, finish = function() NULL, fail = function(cnd) NULL,
         message = function() NULL)
  }
  off1 = gptr_register(gptr_adapter("test-proc-spec", transport = "process_jsonl",
                                    build = function(model, context, opts) seen$spec,
                                    parse = noop))
  off2 = gptr_register(gptr_provider("procspec", api = "test-proc-spec", type = "cli",
                                     models = list(list(id = "default"))))
  withr::defer({
    off1()
    off2()
  })
  model = model_resolve("procspec/default")
  cases = list(
    list(spec = list(start = NULL, send = list(), close_stdin = FALSE), class = "internal",
         message = "none is running"),
    list(spec = list(start = list(args = "--json"), send = list()), class = "invalid_spec",
         message = "command"),
    list(spec = "nonsense", class = "invalid_spec", message = "process spec"),
    list(spec = list(start = list(command = "fakecli"), send = list(type = "user")),
         class = "invalid_spec", message = "send")
  )
  for (case in cases) {
    seen$spec = case$spec
    log = local_stream_log()
    id = provider_stream(model, stream_context(), list(state = new.env()), emit = log$emit,
                         done = log$finish)
    expect_true(is.na(id))
    expect_equal(log$types(), "error")
    expect_equal(log$events[[1]]$error$class, case$class)
    expect_length(log$done, 1L)
    expect_equal(log$done[[1]]$stop_reason, "error")
    expect_match(log$done[[1]]$error_message, case$message, fixed = TRUE)
  }
  expect_length(pr$spawned, 0L)
  expect_length(pr$written, 0L)
  expect_length(r$tasks, 0L)
})

# ---- provider_stream(): process_jsonl on P04's real process engine --------------------------

test_that("process_jsonl drives a real child through P04's process engine", {
  skip_on_cran()
  # the child reads the turn's line and answers with a noise line, a delta (the line's length
  # and the variable start$env set) and a result
  child = paste0("x = readLines(file('stdin'), n = 1L); cat('noise\\n{\"type\":\"delta\",",
                 "\"v\":\"', nchar(x), ':', Sys.getenv('GPTR_TEST_CHILD'), '\"}\\n",
                 "{\"type\":\"result\"}\\n', sep = '')")
  model = local_process_adapter(close_stdin = TRUE, start_with = list(
    command = rscript_path(), args = c("--vanilla", "-e", child), env_profile = "helper",
    env = c(GPTR_TEST_CHILD = "set-by-start"), wd = NULL
  ))
  state = new.env()
  log = local_stream_log()
  id = provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                       done = log$finish)
  p = state$process
  withr::defer(kill_all(p, grace = 0))
  job = state$job
  expect_true(is.character(job) && exists(job, envir = jobs_env()$table, inherits = FALSE))
  expect_equal(jobs_env()$table[[job]]$kind, "cli")
  expect_true(reactor_pump(until = function() length(log$done) > 0L && is.null(state$process),
                           timeout = 30))
  expect_equal(log$types(), c("start", "text_delta", "done"))
  expect_equal(msg_text(log$done[[1]]),
               paste0(nchar(json_encode(list(type = "user", text = "hi"))), ":set-by-start"))
  expect_false(exists(job, envir = jobs_env()$table, inherits = FALSE))
  expect_true(reactor_pump(until = function() !id %in% ls(reactor_get()$tasks), timeout = 5))
  expect_identical(ls(reactor_get()$procs), character())
})

# A real child that reads the turn's line, answers by its text ("boom": a normaliser failure;
# "done": a result; otherwise it only waits) and then stays alive, stdin open or not
real_child_start = function() {
  child = paste0("con = file('stdin'); open(con); x = readLines(con, n = 1L); ",
                 "v = if (grepl('boom', x)) 'boom' else if (grepl('done', x)) 'result' else ",
                 "'wait'; cat('{\"type\":\"delta\",\"v\":\"part\"}\\n{\"type\":\"', v, ",
                 "'\"}\\n', sep = ''); flush(stdout()); Sys.sleep(60)")
  list(command = rscript_path(), args = c("--vanilla", "-e", child), env_profile = "helper")
}

# The watchers registered since `before`; a failing test cancels them, so none keeps polling
local_new_watchers = function(.env = parent.frame()) {
  before = ls(reactor_get()$procs)
  live = function() setdiff(ls(reactor_get()$procs), before)
  withr::defer(reactor_cancel(live()), envir = .env)
  live
}

job_row = function(job) {
  is.character(job) && exists(job, envir = jobs_env()$table, inherits = FALSE)
}

test_that("a real child whose turn the glue ends leaves no watcher and no job row", {
  skip_on_cran()
  live = local_new_watchers()
  model = local_process_adapter(start_with = real_child_start())
  state = new.env()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  # an abort: P04 must forget the killed child's watcher (it polled closed pipes forever when
  # the glue killed the child under it) and the job row goes with it
  log = local_stream_log()
  provider_stream(model, stream_context("hold"), list(state = state, signal = signal),
                  emit = log$emit, done = log$finish)
  job = state$job
  expect_true(job_row(job))
  expect_length(live(), 1L)
  expect_true(reactor_pump(until = function() "text_delta" %in% log$types(), timeout = 30))
  signal$aborted = TRUE
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 10))
  expect_equal(log$done[[1]]$stop_reason, "aborted")
  expect_null(state$process)
  expect_true(reactor_pump(until = function() !length(live()) && !job_row(job), timeout = 3))
  # a normaliser failure: the next turn starts a new child, which the failure drops the same way
  signal$aborted = FALSE
  log2 = local_stream_log()
  provider_stream(model, stream_context("boom"), list(state = state, signal = signal),
                  emit = log2$emit, done = log2$finish)
  job2 = state$job
  expect_false(identical(job2, job))
  expect_true(job_row(job2))
  expect_true(reactor_pump(until = function() length(log2$done) > 0L, timeout = 30))
  expect_equal(log2$done[[1]]$stop_reason, "error")
  expect_match(log2$done[[1]]$error_message, "normaliser broke", fixed = TRUE)
  expect_null(state$process)
  expect_true(reactor_pump(until = function() !length(live()) && !job_row(job2), timeout = 3))
})

test_that("a real child replaced by the next turn or stopped by its job row leaves no watcher", {
  skip_on_cran()
  live = local_new_watchers()
  model = local_process_adapter(close_stdin = TRUE, start_with = real_child_start())
  state = new.env()
  log1 = local_stream_log()
  provider_stream(model, stream_context("done"), list(state = state), emit = log1$emit,
                  done = log1$finish)
  job1 = state$job
  expect_true(reactor_pump(until = function() length(log1$done) > 0L, timeout = 30))
  expect_equal(msg_text(log1$done[[1]]), "part")
  # the child lives on after its turn; the next turn's `start` replaces it
  expect_false(is.null(state$process))
  log2 = local_stream_log()
  provider_stream(model, stream_context("hold"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  job2 = state$job
  expect_true(reactor_pump(until = function() length(live()) == 1L && !job_row(job1),
                           timeout = 3))
  expect_true(job_row(job2))
  expect_true(reactor_pump(until = function() "text_delta" %in% log2$types(), timeout = 30))
  # gptr_jobs(kill = TRUE) calls the row's stop(): the watcher and the row go, and the open
  # turn ends at the child's exit
  jobs_env()$table[[job2]]$stop()
  expect_true(reactor_pump(until = function() length(log2$done) > 0L, timeout = 10))
  expect_equal(msg_text(log2$done[[1]]), "part")
  expect_null(state$process)
  expect_true(reactor_pump(until = function() !length(live()) && !job_row(job2), timeout = 3))
})

# ---- gptr_providers() ------------------------------------------------------------------------

test_that("gptr_providers() lists providers with fingerprints and no I/O", {
  count = new.env()
  count$transfers = 0L
  local_mocked_bindings(
    reactor_http = function(...) {
      count$transfers = count$transfers + 1L
      "t1"
    },
    proc_spawn = function(...) stop("gptr_providers() must not start a process")
  )
  local_test_vault()
  withr::local_envvar(ANTHROPIC_API_KEY = "sk-ant-api03-p05list-000000000000000000",
                      GROQ_API_KEY = "")
  local_mocked_bindings(auth_store_get = function(key) NULL)
  local_settings(providers = list(cerebras = list(enabled = FALSE)))
  df = gptr_providers()
  expect_equal(df$status[df$id == "cerebras"], "disabled")
  expect_equal(df$status[df$id == "groq"], "no key")
  expect_s3_class(df, "gptr_providers")
  expect_named(df, c("id", "type", "api", "credential", "source", "status", "default_model",
                     "egress", "version"))
  expect_true(all(builtin_ids %in% df$id))
  a = df[df$id == "anthropic", ]
  expect_match(a$credential, "^ANTHROPIC_API_KEY #[0-9a-f]+$")
  expect_equal(a$status, "ready")
  expect_equal(a$default_model, "anthropic/claude-sonnet-5-5")
  expect_equal(a$egress, "needed")
  expect_equal(df$egress[df$id == "ollama"], "ack")
  expect_equal(df$status[df$id == "ollama"], "ready")
  printed = paste(capture.output(print(df)), collapse = "\n")
  expect_false(grepl("p05list", printed, fixed = TRUE))
  expect_equal(count$transfers, 0L)
  expect_error(gptr_providers(check = "yes"), class = "gptr_error_invalid_argument")
})

test_that("gptr_providers(check = TRUE) probes models endpoints without credentials", {
  urls = new.env()
  urls$seen = character()
  local_test_vault()
  # one GET per provider (attempts = 1L): P04's default retry policy would re-send it
  local_mocked_bindings(
    check_running = function() FALSE,
    auth_store_get = function(key) NULL,
    catalog_http_request = function(url, method = "GET", headers = list(), body = NULL,
                                    timeout = 30, attempts = NULL, max_bytes = 64 * 1024^2) {
      urls$seen = c(urls$seen, url)
      expect_equal(method, "GET")
      expect_null(body)
      expect_equal(timeout, 2)
      expect_equal(attempts, 1L)
      expect_length(headers, 0L)
      list(status = 401L, headers = list(), body = raw())
    }
  )
  local_settings(egress = list(anthropic = "ack"))
  df = gptr_providers(check = TRUE)
  expect_equal(df$status[df$id == "anthropic"], "reachable (HTTP 401)")
  expect_true("https://api.anthropic.com/v1/models" %in% urls$seen)
  expect_true("https://api.openai.com/v1/models" %in% urls$seen)
  expect_equal(df$egress[df$id == "anthropic"], "ack")
})

test_that("the probe skips R CMD check and disabled providers; a failed answer is unreachable", {
  local_test_vault()
  seen = new.env()
  seen$urls = character()
  local_mocked_bindings(
    check_running = function() TRUE,
    auth_store_get = function(key) NULL,
    catalog_http_request = function(...) stop("no probe under R CMD check")
  )
  withr::local_envvar(AZURE_OPENAI_ENDPOINT = "")
  local_settings(providers = list(groq = list(enabled = FALSE),
                                  deepseek = list(base_url = "not a url")))
  df = gptr_providers()
  expect_equal(df$status[df$id == "deepseek"], "invalid base url")
  expect_equal(df$status[df$id == "azure"], "no base url")
  df = gptr_providers(check = TRUE)
  expect_equal(df$status[df$id == "anthropic"], "not checked")
  expect_equal(df$status[df$id == "groq"], "disabled")
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, method = "GET", headers = list(), body = NULL,
                                    timeout = 30, attempts = NULL, max_bytes = 64 * 1024^2) {
      seen$urls = c(seen$urls, url)
      if (startsWith(url, "https://api.openai.com/")) {
        # an answer above the probe's body bound still proves the endpoint answered
        expect_lte(max_bytes, 65536)
        gptr_abort("The answer exceeded the bound.", c("network", "provider"),
                   provider = "catalog", status = 200L, curl_code = NA_integer_)
      }
      if (startsWith(url, "https://api.anthropic.com/")) {
        gptr_abort("No answer.", c("network", "provider"), provider = "catalog",
                   status = NA_integer_, curl_code = 28L)
      }
      list(status = 404L, headers = list(), body = raw())
    }
  )
  df = gptr_providers(check = TRUE)
  expect_equal(df$status[df$id == "openai"], "reachable (HTTP 200)")
  expect_equal(df$status[df$id == "anthropic"], "unreachable")
  expect_equal(df$status[df$id == "ollama"], "reachable (HTTP 404)")
  expect_equal(df$status[df$id == "groq"], "disabled")
  expect_false(any(grepl("groq", seen$urls, fixed = TRUE)))
  expect_equal(df$status[df$id == "azure"], "no base url")
  expect_false(any(grepl("azure", seen$urls, fixed = TRUE)))
  expect_equal(df$status[df$id == "deepseek"], "invalid base url")
  expect_false(any(grepl("not a url", seen$urls, fixed = TRUE)))
})

test_that("gptr_providers() reads a provider's status(), registry source and offline flag", {
  local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  calls = new.env()
  calls$check = list()
  checked = function(check = FALSE) {
    calls$check[[length(calls$check) + 1L]] = check
    list(status = if (check) "found (checked)" else "found",
         version = package_version("2.1.0"), available = TRUE)
  }
  models = list(list(id = "judge", type = "classifier", release_date = "2026-01-01"),
                list(id = "chatty", release_date = "2026-02-01"))
  ok = ext_load(function(gptr) {
    gptr$register(gptr_provider("p05-cli", api = "cli-p05", type = "cli", status = checked))
    gptr$register(gptr_provider("p05-gone", api = "cli-p05", type = "cli",
                                status = function() list(available = FALSE)))
    gptr$register(gptr_provider("p05-broken", api = "cli-p05", type = "cli",
                                status = function() stop("boom")))
    gptr$register(gptr_provider("p05-odd", api = "cli-p05", type = "cli",
                                status = function() "not a list"))
    gptr$register(gptr_provider("p05-offline", api = "fake", auth = "P05_OFFLINE_KEY",
                                offline = TRUE))
    gptr$register(gptr_provider("p05-s1", api = "p05-decide", type = "classifier",
                                base_url = "https://s1.example", models = models))
    gptr$register(gptr_provider("p05-chat", api = "openai-completions",
                                base_url = "https://chat.example/v1", models = models))
    gptr$register(gptr_provider("p05-badauth", api = "openai-completions",
                                base_url = "https://badauth.example/v1",
                                auth = function() stop("auth exploded")))
    gptr$register(gptr_provider("p05-rawauth", api = "openai-completions",
                                base_url = "https://rawauth.example/v1",
                                auth = function() "a raw string"))
  }, source = "plugin:p05-status", rank = 5L)
  withr::defer(ext_unload("plugin:p05-status"))
  expect_true(ok)
  local_mocked_bindings(proc_spawn = function(...) stop("no process with check = FALSE"))
  df = gptr_providers()
  cli = df[df$id == "p05-cli", ]
  expect_equal(cli$type, "cli")
  expect_equal(cli$api, "cli-p05")
  expect_equal(cli$status, "found")
  expect_equal(cli$version, "2.1.0")
  expect_equal(cli$source, "plugin:p05-status")
  expect_true(is.na(cli$credential))
  expect_identical(calls$check, list(FALSE))
  expect_equal(df$status[df$id == "p05-gone"], "unavailable")
  expect_true(is.na(df$version[df$id == "p05-gone"]))
  expect_equal(df$status[df$id == "p05-broken"], "error")
  expect_equal(df$status[df$id == "p05-odd"], "unknown")
  off = df[df$id == "p05-offline", ]
  expect_equal(off$status, "ready")
  expect_equal(off$egress, "ack")
  expect_true(is.na(off$credential))
  expect_equal(df$source[df$id == "anthropic"], "builtin:providers")
  # IC-74: a decision-only model is never a chat provider's default, and vice versa
  expect_equal(df$default_model[df$id == "p05-s1"], "p05-s1/judge")
  expect_equal(df$default_model[df$id == "p05-chat"], "p05-chat/chatty")
  expect_true(is.na(df$default_model[df$id == "ollama"]))
  # a failing credential lookup (a plain R error included) marks its row, never the listing
  expect_equal(df$status[df$id == "p05-badauth"], "error")
  expect_equal(df$status[df$id == "p05-rawauth"], "error")
  expect_true(is.na(df$credential[df$id == "p05-badauth"]))
  # check = TRUE: status(check = TRUE) and no HTTP probe for a provider with its own status()
  urls = new.env()
  urls$seen = character()
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, ...) {
      urls$seen = c(urls$seen, url)
      list(status = 200L, headers = list(), body = raw())
    }
  )
  df = gptr_providers(check = TRUE)
  expect_equal(df$status[df$id == "p05-cli"], "found (checked)")
  expect_identical(calls$check, list(FALSE, TRUE))
  expect_equal(df$status[df$id == "p05-offline"], "ready")
  expect_true("https://chat.example/v1/models" %in% urls$seen)
  expect_false(any(grepl("p05-cli|p05-offline", urls$seen)))
  expect_equal(df$status[df$id == "p05-badauth"], "error")
  expect_false(any(grepl("badauth", urls$seen, fixed = TRUE)))
})

test_that("a local provider needs no egress acknowledgement only at a loopback endpoint (IC-74)", {
  local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  local_settings(providers = list(ollama = list(base_url = "https://ollama.example/v1"),
                                  llamacpp = list(base_url = "http://127.0.0.2:8080/v1")))
  df = gptr_providers()
  expect_equal(df$egress[df$id == "ollama"], "needed")
  expect_equal(df$egress[df$id == "llamacpp"], "ack")
  expect_equal(df$egress[df$id == "lmstudio"], "ack")
  expect_equal(df$egress[df$id == "openai"], "needed")
  local_settings(providers = list(ollama = list(base_url = "https://ollama.example/v1")),
                 egress = list(ollama = "ack", openai = "yes"))
  df = gptr_providers()
  expect_equal(df$egress[df$id == "ollama"], "ack")
  expect_equal(df$egress[df$id == "openai"], "needed")
})

test_that("base URL statuses and the probe follow the provider's transport (contract 6.2)", {
  local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  withr::local_envvar(VLLM_API_KEY = "")
  reply = gptr_fake_provider(list("hi"), name = "p05-inproc-fake")
  ok = ext_load(function(gptr) {
    gptr$register(gptr_adapter("p05-inproc", transport = "inprocess",
                               stream = function(model, context, opts) {
                                 opts$provider = reply
                                 fake_stream(model, context, opts)
                               }))
    gptr$register(gptr_adapter("p05-sse", transport = "http_sse",
                               build = function(model, context, opts) list(),
                               parse = function(model, opts) NULL))
    gptr$register(gptr_provider("p05-inproc-prov", api = "p05-inproc"))
    gptr$register(gptr_provider("p05-keyless", api = "p05-sse"))
    gptr$register(gptr_provider("p05-nourl", api = "openai-completions"))
  }, source = "plugin:p05-transport", rank = 5L)
  withr::defer(ext_unload("plugin:p05-transport"))
  expect_true(ok)
  local_settings(providers = list(ollama = list(base_url = "not a url"),
                                  vllm = list(base_url = "not a url either")))
  statuses = function(df) {
    stats::setNames(df$status[match(c("ollama", "vllm", "p05-keyless", "p05-nourl",
                                      "p05-inproc-prov"), df$id)],
                    c("ollama", "vllm", "p05-keyless", "p05-nourl", "p05-inproc-prov"))
  }
  want = c(ollama = "invalid base url", vllm = "invalid base url", `p05-keyless` = "no base url",
           `p05-nourl` = "no base url", `p05-inproc-prov` = "ready")
  # check = FALSE and check = TRUE agree on everything the probe does not answer
  expect_equal(statuses(gptr_providers()), want)
  urls = new.env()
  urls$seen = character()
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, ...) {
      urls$seen = c(urls$seen, url)
      list(status = 401L, headers = list(), body = raw())
    }
  )
  df = gptr_providers(check = TRUE)
  expect_equal(statuses(df), want)
  expect_equal(df$status[df$id == "anthropic"], "reachable (HTTP 401)")
  # only HTTP providers are probed, and never at a malformed or missing base URL
  expect_false(any(grepl("not a url", urls$seen, fixed = TRUE)))
  expect_false(any(grepl("p05-", urls$seen, fixed = TRUE)))
})

test_that("gptr_providers() neither registers nor binds an environment credential", {
  vault = local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  key = "sk-proj-p05peek-00000000000000000000000000"
  vllm_key = "vllm-p05peek-0000000000000000"
  withr::local_envvar(OPENAI_API_KEY = key, VLLM_API_KEY = vllm_key)
  ok = ext_load(function(gptr) {
    gptr$register(gptr_provider("gateway-p05", api = "openai-completions",
                                base_url = "https://gateway.example/v1", auth = "OPENAI_API_KEY"))
  }, source = "plugin:p05-gateway", rank = 5L)
  withr::defer(ext_unload("plugin:p05-gateway"))
  expect_true(ok)
  fp = substr(hash_sha256(key), 1L, 6L)
  df = gptr_providers()
  # gateway-p05 sorts before openai: a binding listing would leave openai without its key
  expect_equal(df$credential[df$id == "gateway-p05"], paste0("OPENAI_API_KEY #", fp))
  expect_equal(df$credential[df$id == "openai"], paste0("OPENAI_API_KEY #", fp))
  expect_equal(df$status[df$id == "openai"], "ready")
  expect_equal(df$credential[df$id == "vllm"],
               paste0("VLLM_API_KEY #", substr(hash_sha256(vllm_key), 1L, 6L)))
  expect_length(ls(vault), 0L)
  # the first real use binds the key; the listing then reports the other provider without it
  h = provider_credential(provider_get("openai"))
  expect_equal(h$fp, fp)
  expect_equal(provider_origin(h$origin), "https://api.openai.com")
  df = gptr_providers()
  expect_equal(df$credential[df$id == "openai"], paste0("OPENAI_API_KEY #", fp))
  expect_equal(df$status[df$id == "gateway-p05"], "no key")
  expect_true(is.na(df$credential[df$id == "gateway-p05"]))
  expect_equal(ls(vault), "OPENAI_API_KEY")
})

test_that("invalid settings for one provider mark its row, never the listing", {
  local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  local_settings(providers = list(groq = list(headers = list(1, 2))))
  expect_error(provider_get("groq"), class = "gptr_error_invalid_argument")
  df = gptr_providers()
  g = df[df$id == "groq", ]
  expect_equal(g$status, "error")
  expect_equal(g$api, "openai-completions")
  expect_equal(g$source, "builtin:providers")
  expect_true(is.na(g$credential))
  expect_true(all(builtin_ids %in% df$id))
  expect_equal(df$status[df$id == "ollama"], "ready")
})
