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
