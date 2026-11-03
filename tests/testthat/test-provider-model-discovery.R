# Provider inventories describe advertised routes, never prove that inference will succeed.

local_inventory_catalog = function(.env = parent.frame()) {
  local_mocked_bindings(
    catalog_read_base = function() {
      list(generated = "2026-11-02", source = "inventory fixture",
        models = list(list(provider = "openai", id = "known", name = "Known", context = 8192,
                           tool_call = TRUE, prices = list(list(input = 1, output = 2)))))
    },
    check_running = function() FALSE,
    .env = .env
  )
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE), envir = .env)
}

inventory_response = function(body, status = 200L) {
  list(status = status, headers = list(), body = charToRaw(json_encode(body)))
}

test_that("R CMD check suppresses provider inventory before credentials or network", {
  local_mocked_bindings(check_running = function() TRUE,
    provider_credential = function(...) stop("must not resolve credentials"),
    catalog_http_request = function(...) stop("must not contact provider"),
    egress_check = function(...) stop("must not begin setup"))
  p = provider_get("openai")
  expect_null(provider_models(p))
  expect_null(catalog_inventory(p, refresh = TRUE))
})

test_that("native provider inventories use bound headers and sparse metadata", {
  local_mocked_bindings(check_running = function() FALSE)
  key = structure(list(id = "inventory-key", name = "TEST_KEY", fp = "abcdef"),
                  class = "gptr_secret")
  local_mocked_bindings(provider_credential = function(provider, register = TRUE) key)
  local_mocked_bindings(catalog_http_request = function(url, headers, timeout, attempts,
                                                       max_bytes, ...) {
    expect_identical(url, "https://api.openai.com/v1/models")
    expect_identical(headers$authorization, list("Bearer ", key))
    expect_equal(timeout, 1)
    expect_identical(attempts, 1L)
    expect_lte(max_bytes, 8 * 1024^2)
    inventory_response(list(data = list(list(id = "new-id", owned_by = "openai"))))
  })
  got = provider_models(provider_get("openai"))
  expect_identical(got, list(list(id = "new-id", name = "new-id")))
  expect_false(any(c("context", "tool_call", "prices", "reasoning") %in% names(got[[1]])))
})

test_that("Anthropic and Google inventory pages use their native auth and explicit limits", {
  local_mocked_bindings(check_running = function() FALSE)
  key = structure(list(id = "inventory-key", name = "TEST_KEY", fp = "abcdef"),
                  class = "gptr_secret")
  seen = character()
  local_mocked_bindings(provider_credential = function(provider, register = TRUE) key,
    catalog_http_request = function(url, headers, ...) {
      seen <<- c(seen, url)
      expect_false(grepl("key=", url, fixed = TRUE))
      if (startsWith(url, "https://api.anthropic.com")) {
        expect_identical(headers$`x-api-key`, key)
        expect_identical(headers$`anthropic-version`, "2023-06-01")
        if (length(seen) == 1L) return(inventory_response(list(data = list(list(
          id = "claude-fixture", display_name = "Claude fixture", max_input_tokens = 100000,
          max_tokens = 8192, capabilities = list(thinking = list(supported = TRUE),
            image_input = list(supported = TRUE), server_tools = list(supported = TRUE)))),
          has_more = TRUE, last_id = "claude-fixture")))
        expect_match(url, "after_id=claude-fixture", fixed = TRUE)
        return(inventory_response(list(data = list(), has_more = FALSE)))
      }
      expect_identical(headers$`x-goog-api-key`, key)
      if (!grepl("pageToken=", url, fixed = TRUE)) return(inventory_response(list(
        models = list(list(name = "models/gemini-fixture", displayName = "Gemini fixture",
          inputTokenLimit = 32000, outputTokenLimit = 1000, thinking = TRUE,
          supportedGenerationMethods = list("generateContent"))), nextPageToken = "page/2")))
      expect_match(url, "pageToken=page%2F2", fixed = TRUE)
      inventory_response(list(models = list(list(name = "models/embedding-fixture",
        supportedGenerationMethods = list("embedContent")))))
    })
  a = provider_models(provider_get("anthropic"))[[1]]
  expect_identical(a$id, "claude-fixture")
  expect_equal(a$context, 100000)
  expect_equal(a$max_output, 8192)
  expect_true(a$reasoning)
  expect_identical(a$input, c("text", "image"))
  expect_null(a$tool_call) # server tools are not client function calling
  g = provider_models(provider_get("google"))
  expect_length(g, 1L)
  expect_identical(g[[1]]$id, "gemini-fixture")
  expect_true(g[[1]]$reasoning)
  expect_null(g[[1]]$tool_call)
})

test_that("decision API inventory does not invent context, vision, prices or new model names", {
  local_mocked_bindings(check_running = function() FALSE)
  p = provider_get("typesafe")
  local_mocked_bindings(provider_credential = function(...) NULL,
    catalog_http_request = function(url, ...) {
      expect_identical(url, "https://api.typesafe.ai/v1/models")
      inventory_response(list(models = list(list(name = "jev-fixture"))))
    })
  m = provider_models(p)[[1]]
  expect_identical(m$id, "jev-fixture")
  expect_identical(m$type, "classifier")
  expect_identical(m$api, "typesafe-system-one")
  expect_false(m$tool_call)
  expect_null(m$context)
  expect_null(m$prices)
  expect_null(m$input)
  expect_null(m$decision)
})

test_that("compatible APIs contribute only explicitly advertised chat capabilities", {
  local_mocked_bindings(check_running = function() FALSE)
  local_mocked_bindings(provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      inventory_response(list(data = list(
        list(id = "mistral-fixture", max_context_length = 32000,
             capabilities = list(completion_chat = TRUE, function_calling = TRUE, vision = TRUE)),
        list(id = "router-fixture", context_length = 64000,
             top_provider = list(max_completion_tokens = 8192),
             architecture = list(input_modalities = list("text", "image"),
                                 output_modalities = list("text")),
             supported_parameters = list("tools", "reasoning")),
        list(id = "embedding-fixture", capabilities = list(completion_chat = FALSE)))))
    })
  rows = provider_models(provider_get("mistral"))
  expect_length(rows, 2L)
  expect_true(rows[[1]]$tool_call)
  expect_equal(rows[[1]]$context, 32000)
  expect_identical(rows[[1]]$input, c("text", "image"))
  expect_true(rows[[2]]$tool_call)
  expect_true(rows[[2]]$reasoning)
  expect_equal(rows[[2]]$context, 64000)
  expect_equal(rows[[2]]$max_output, 8192)
  expect_null(rows[[2]]$prices)
})

test_that("inventory pages, malformed responses and HTTP failures are bounded and sanitized", {
  local_mocked_bindings(check_running = function() FALSE)
  local_mocked_bindings(provider_credential = function(...) NULL)
  n = 0L
  local_mocked_bindings(catalog_http_request = function(...) {
    n <<- n + 1L
    inventory_response(list(data = list(list(id = paste0("m", n))), has_more = TRUE,
                            last_id = paste0("m", n)))
  })
  expect_error(provider_models(provider_get("anthropic")), class = "gptr_error_network")
  expect_lte(n, 4L)
  local_mocked_bindings(catalog_http_request = function(...) {
    inventory_response(list(error = "sensitive server response"), status = 401L)
  })
  e = expect_error(provider_models(provider_get("openai")), class = "gptr_error_network")
  expect_match(conditionMessage(e), "HTTP 401", fixed = TRUE)
  expect_no_match(conditionMessage(e), "sensitive server response", fixed = TRUE)
  local_mocked_bindings(catalog_http_request = function(...) inventory_response(list()))
  expect_error(provider_models(provider_get("openai")), class = "gptr_error_network")
  local_mocked_bindings(catalog_http_request = function(...) {
    inventory_response(list(data = list(list(id = "partial")), has_more = TRUE))
  })
  expect_error(provider_models(provider_get("anthropic")), class = "gptr_error_network")
})

test_that("provider refresh merges advertised IDs while retaining catalog capability facts", {
  local_inventory_catalog()
  local_mocked_bindings(egress_check = function(...) TRUE, replay_guard = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      inventory_response(list(data = list(list(id = "known"), list(id = "new-id"))))
    })
  old = gptr_models(provider = "openai")
  expect_true(all(old$availability == "unknown"))
  found = gptr_models(provider = "openai", refresh = TRUE)
  expect_true(all(found$availability == "advertised"))
  expect_true(all(!is.na(found$checked_at)))
  expect_true(is.na(found$reasoning[found$ref == "openai/new-id"]))
  known = model_resolve("openai/known")
  expect_equal(known$context, 8192)
  expect_true(known$tool_call)
  added = model_resolve("openai/new-id")
  expect_true(is.na(added$context))
  expect_false(added$tool_call)
  expect_equal(nrow(added$prices), 0L)
  expect_match(attr(found, "footer"), "does not verify inference", fixed = TRUE)
  local_mocked_bindings(catalog_http_request = function(...) {
    inventory_response(list(data = list()))
  })
  empty = gptr_models(provider = "openai", refresh = TRUE)
  expect_identical(empty$ref, "openai/known")
  expect_identical(empty$availability, "unlisted")
})

test_that("the listing footer names failed listings of listed providers once, with the row count", {
  local_inventory_catalog()
  local_mocked_bindings(egress_check = function(...) TRUE, replay_guard = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) inventory_response(list(), status = 405L))
  gptr_models(provider = "openai", refresh = TRUE)
  gptr_models(provider = "anthropic", refresh = TRUE)
  all = gptr_models()
  footer = attr(all, "footer")
  expect_match(footer, paste0(", ", nrow(all), " models;"), fixed = TRUE)
  expect_match(footer, "; listing failed for openai (HTTP 405); prior catalog kept", fixed = TRUE)
  expect_no_match(footer, "anthropic", fixed = TRUE)
  expect_match(attr(gptr_models(provider = "anthropic"), "footer"),
               "listing failed for anthropic (HTTP 405)", fixed = TRUE)
})

test_that("a failed listing without an HTTP status names gptr's own reason, never other text", {
  local_inventory_catalog()
  local_mocked_bindings(egress_check = function(...) TRUE, replay_guard = function(...) TRUE,
    provider_credential = function(...) NULL)
  failed = function() {
    sub(".*listing failed for openai \\((.*)\\); prior.*", "\\1",
        attr(gptr_models(provider = "openai", refresh = TRUE), "footer"))
  }
  local({
    local_mocked_bindings(reactor_pump = function(...) FALSE)
    expect_identical(failed(), "no answer within 1 s")
  })
  local_mocked_bindings(catalog_http_request = function(...) inventory_response(list()))
  expect_identical(failed(), "returned an invalid response")
  local_mocked_bindings(catalog_http_request = function(...) stop("sensitive callback text"))
  expect_identical(failed(), "listing unavailable")
})

test_that("preparation inventories once, explicit refresh bypasses cache, failures keep models", {
  local_inventory_catalog()
  n = 0L
  clock = new.env(parent = emptyenv())
  clock$now = 1
  key = NULL
  local_mocked_bindings(egress_check = function(...) TRUE, replay_guard = function(...) TRUE,
    reactor_now = function() clock$now, provider_credential = function(...) key,
    catalog_http_request = function(...) {
      n <<- n + 1L
      if (n > 2L) stop("sensitive callback text")
      inventory_response(list(data = list(list(id = "new-id"))))
    })
  m = model_resolve("openai/known")
  provider_ready(m, provider_get("openai"), prepare = TRUE)
  provider_ready(m, provider_get("openai"), prepare = TRUE)
  expect_equal(n, 1L)
  gptr_models(provider = "openai", refresh = TRUE)
  expect_equal(n, 2L)
  clock$now = 302
  provider_ready(m, provider_get("openai"), prepare = TRUE)
  expect_equal(n, 3L)
  found = gptr_models(provider = "openai")
  expect_true("openai/new-id" %in% found$ref)
  expect_identical(found$availability[found$ref == "openai/new-id"], "advertised (stale)")
  expect_match(attr(found, "footer"), "listing failed for openai", fixed = TRUE)
  expect_no_match(attr(found, "footer"), "sensitive callback text", fixed = TRUE)
  provider_ready(m, provider_get("openai"), prepare = TRUE)
  expect_equal(n, 3L) # failed attempts are cached too
  key = structure(list(id = "next-key", fp = "next-fp"), class = "gptr_secret")
  provider_ready(m, provider_get("openai"), prepare = TRUE)
  expect_equal(n, 4L)
})

test_that("discovery preserves consent and replay refusals before credentials or I/O", {
  local_inventory_catalog()
  local_mocked_bindings(provider_credential = function(...) stop("credential lookup"),
    catalog_http_request = function(...) stop("network"),
    egress_check = function(...) gptr_abort("consent required", "egress"))
  expect_error(gptr_models(provider = "openai", refresh = TRUE), class = "gptr_error_egress")
  local_mocked_bindings(egress_check = function(...) TRUE,
    replay_guard = function(...) gptr_abort("offline replay", "not_recorded"))
  expect_error(gptr_models(provider = "openai", refresh = TRUE),
               class = "gptr_error_not_recorded")
  # Pure catalog lookup, defaults and listing never inspect credentials or discover.
  expect_identical(model_resolve("openai/known")$id, "known")
  expect_error(model_resolve("openai/unknown"), "gptr_models(provider", fixed = TRUE)
  expect_true(nrow(gptr_models(provider = "openai")) > 0L)
})

test_that("the egress question of a listing says no prompt is sent and what consent covers", {
  local_inventory_catalog()
  local_gptr_options(interactive = TRUE)
  box = new.env(parent = emptyenv())
  local_mocked_bindings(egress_state = function(...) list(exempt = FALSE),
    settings_get = function(...) NULL, gptr_confirm = function(question, default = FALSE) {
      box$q = question
      FALSE
    }, catalog_http_request = function(...) stop("network"))
  expect_error(gptr_models(provider = "openai", refresh = TRUE), class = "gptr_error_egress")
  expect_match(box$q, "^Listing models asks openai for its model list; no prompt is sent\\.")
  expect_match(box$q, "also lets gptr send your prompts to openai together with automatic context",
               fixed = TRUE)
})

test_that("custom discover callbacks support sparse records and successful empty inventories", {
  local_inventory_catalog()
  p = provider_get("openai")
  p$auth = NULL
  p$discover = function() {
    list(list(id = "callback-id", context = 12000, tool_call = TRUE, locality = "local"))
  }
  catalog_discover(p)
  m = model_resolve("openai/callback-id")
  expect_equal(m$context, 12000)
  expect_true(m$tool_call)
  expect_identical(m$locality, "unknown")
  p$discover = function() list()
  catalog_discover(p)
  expect_null(model_resolve("openai/callback-id", strict = FALSE))
  expect_identical(model_resolve("openai/known")$id, "known")
})

test_that("before-use inventory preserves an explicit replay override without opening refresh", {
  local_gw()
  local_inventory_catalog()
  withr::local_options(gptr.replay = "replay")
  n = 0L
  local_mocked_bindings(egress_check = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      n <<- n + 1L
      inventory_response(list(data = list(list(id = "known"))))
    })
  p = provider_get("openai")
  m = model_resolve("openai/known")
  expect_error(provider_ready(m, p, prepare = TRUE), class = "gptr_error_not_recorded")
  expect_identical(provider_ready(m, p, prepare = TRUE, replay = "auto")$id, "known")
  expect_identical(model_prepare(m$ref, replay = "auto")$id, "known")
  call = list(args = list(replay = "auto", opts = list(context = "none")))
  s = session_new(m$ref, "auto", home = new.env())
  expect_invisible(gateway_guards(call, s, NULL))
  run = new.env(parent = emptyenv())
  run$shell = s
  run$opts = list(call = call, safety = list())
  expect_identical(run_model_ready(run, m$ref)$id, "known")
  expect_equal(n, 1L)
  expect_error(gptr_models(provider = "openai", refresh = TRUE),
               class = "gptr_error_not_recorded")
  expect_equal(n, 1L)
})

test_that("tenant header edits invalidate reuse and offline freshness without looking up keys", {
  local_inventory_catalog()
  withr::local_options(gptr.replay = "auto")
  n = 0L
  local_mocked_bindings(egress_check = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      n <<- n + 1L
      inventory_response(list(data = list(list(id = "known"))))
    })
  gptr_models(provider = "openai", refresh = TRUE)
  local_settings(providers = list(openai = list(headers = list(`OpenAI-Project` = "tenant-b"))))
  local({
    local_mocked_bindings(provider_credential = function(...) stop("offline listing read key"))
    expect_identical(gptr_models(provider = "openai")$availability, "advertised (stale)")
  })
  p = provider_get("openai")
  provider_ready(model_resolve("openai/known"), p, prepare = TRUE, replay = "auto")
  expect_equal(n, 2L)
  expect_identical(gptr_models(provider = "openai")$availability, "advertised")
})

test_that("built-in compatible callbacks retry when their optional credential changes", {
  local_inventory_catalog()
  key = NULL
  n = 0L
  local_mocked_bindings(egress_check = function(...) TRUE,
    provider_credential = function(...) key,
    catalog_http_request = function(url, headers, ...) {
      n <<- n + 1L
      if (is.null(key)) return(inventory_response(list(error = "unauthorized"), 401L))
      expect_identical(headers$authorization, list("Bearer ", key))
      inventory_response(list(data = list(list(id = "local-id"))))
    })
  p = provider_get("vllm")
  m = model_resolve("vllm/local-id")
  provider_ready(m, p, prepare = TRUE, replay = "auto")
  key = structure(list(id = "next-key", fp = "new-fp"), class = "gptr_secret")
  provider_ready(m, p, prepare = TRUE, replay = "auto")
  expect_equal(n, 2L)
  expect_identical(gptr_models(provider = "vllm")$availability, "advertised")
})

test_that("reentrant preparation reuses an advisory inventory attempt already in progress", {
  local_inventory_catalog()
  p = provider_get("openai")
  n = 0L
  local_mocked_bindings(egress_check = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      n <<- n + 1L
      if (n == 1L) catalog_inventory(p, replay = "auto")
      inventory_response(list(data = list(list(id = "known"))))
    })
  catalog_inventory(p, replay = "auto")
  expect_equal(n, 1L)
  expect_identical(gptr_models(provider = "openai")$availability, "advertised")
})

test_that("gateways serving the TypeSafe protocol have no TypeSafe model listing", {
  local_inventory_catalog()
  local_mocked_bindings(egress_check = function(...) stop("must not begin setup"),
    catalog_http_request = function(...) stop("must not contact the gateway"))
  for (id in c("openrouter-jev", "vercel-jev")) {
    expect_null(provider_models(provider_get(id), credential = NULL))
    expect_null(catalog_inventory(provider_get(id), refresh = TRUE))
  }
  expect_true(provider_models_supported(provider_get("typesafe")))
})

test_that("hosted decision requests inventory only after their effective replay guard", {
  local_inventory_catalog()
  withr::local_options(gptr.replay = "replay")
  n = 0L
  local_mocked_bindings(egress_check = function(...) TRUE,
    provider_credential = function(...) NULL,
    catalog_http_request = function(...) {
      n <<- n + 1L
      inventory_response(list(models = list(list(name = "jev-latest"))))
    })
  target = s1_target("typesafe/jev-latest")
  expect_error(s1_guards(target, "replay"), class = "gptr_error_not_recorded")
  expect_equal(n, 0L)
  s1_guards(target, "auto")
  s1_guards(target, "auto")
  expect_equal(n, 1L)
})

test_that("credential presence detects session handles without unlocking persistent storage", {
  local_vault()
  st = secrets_state()
  st$auth = list(openai = list(key = structure(list(id = "opaque"), class = "gptr_secret")))
  local_mocked_bindings(auth_store_read = function() list(),
    auth_store_get = function(...) stop("must not unlock"), secret_lookup = function(...) NULL)
  expect_true(model_key_present("openai", character()))
})
