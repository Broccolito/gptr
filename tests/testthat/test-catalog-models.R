# Tests for R/catalog-models.R (plan P05): snapshot structure, models.dev conversion, merge
# layers, the resolver, defaults, explicit refresh and gptr_models().

test_that("the shipped snapshot has the documented structure (04 section 11.10)", {
  path = system.file("extdata", "models.json.gz", package = "gptr")
  expect_true(nzchar(path))
  expect_lt(file.size(path), 1e6)
  snap = catalog_read(path)
  expect_identical(snap$schema_version, 1L)
  expect_match(snap$generated, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
  expect_true(all(c("anthropic", "openai", "google", "ollama", "typesafe") %in%
                    names(snap$providers)))
  expect_equal(snap$providers$anthropic$api, "anthropic-messages")
  expect_equal(unlist(snap$providers$google$env), c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  refs = vapply(snap$models, function(m) paste0(m$provider, "/", m$id), "")
  expect_true(all(c("anthropic/claude-sonnet-5-5", "anthropic/claude-opus-5-5",
                    "anthropic/claude-haiku-4-5", "openai/gpt-6-sol", "google/gemini-3.8-flash",
                    "typesafe/jev-latest") %in% refs))
  expect_true(all(c("sonnet", "opus", "haiku", "gemini", "flash", "gpt", "jev", "claude_code",
                    "codex") %in% names(snap$aliases)))
  sonnet = snap$models[[match("anthropic/claude-sonnet-5-5", refs)]]
  expect_equal(sonnet$prices[[1]]$input, 2)
  expect_equal(sonnet$cache_min, 512)
  expect_false(sonnet$capabilities$forced_tool_choice)
})

test_that("models.dev entries are pruned and converted; overrides only patch", {
  api = list(
    anthropic = list(id = "anthropic", env = list("ANTHROPIC_API_KEY"), models = list(
      `claude-sonnet-5-5` = list(
        id = "claude-sonnet-5-5", name = "Claude Sonnet 5.5", family = "claude-sonnet",
        reasoning = TRUE, tool_call = TRUE, structured_output = TRUE, release_date = "2026-09",
        reasoning_options = list(list(type = "effort",
                                      values = list("low", "medium", "high", "xhigh", "max"))),
        modalities = list(input = list("text", "image", "pdf", "video"), output = list("text")),
        limit = list(context = 1e6, output = 128000),
        cost = list(input = 3, output = 15, cache_read = 0.3, cache_write = 3.75,
                    context_over_200k = list(input = 6, output = 22.5)),
        canonical_model_id = "anthropic/claude-sonnet-5-5"
      ),
      `old-model` = list(id = "old-model", tool_call = TRUE, status = "deprecated",
                         modalities = list(input = list("text"), output = list("text"))),
      `no-tools` = list(id = "no-tools", tool_call = FALSE,
                        modalities = list(input = list("text"), output = list("text")))
    )),
    elsewhere = list(id = "elsewhere", models = list(x = list(id = "x", tool_call = TRUE)))
  )
  decision = list(`typesafe/jev-latest` = list(
    id = "typesafe/jev-latest", type = "decision", name = "Jev", release_date = "2026-09-15",
    limit = list(context = 64000, output = 0), structured_output = TRUE
  ))
  x = catalog_from_modelsdev(api, decision)
  expect_setequal(names(x), c("anthropic/claude-sonnet-5-5", "typesafe/jev-latest"))
  s = x[["anthropic/claude-sonnet-5-5"]]
  expect_equal(as.character(s$thinking_levels), c("low", "medium", "high", "xhigh", "max"))
  expect_equal(as.character(s$input), c("text", "image", "pdf"))
  expect_equal(s$release_date, "2026-09-01")
  expect_equal(vapply(s$prices, function(p) p$tier, ""), c("default", ">200k"))
  expect_equal(s$owner, "anthropic")
  expect_equal(x[["typesafe/jev-latest"]]$type, "classifier")
  snap = catalog_snapshot(api, decision, generated = "2026-09-30")
  expect_equal(snap$source, "models.dev (MIT) + gptr overrides")
  refs = vapply(snap$models, function(m) paste0(m$provider, "/", m$id), "")
  expect_identical(refs, sort(refs, method = "radix"))
  merged = snap$models[[match("anthropic/claude-sonnet-5-5", refs)]]
  expect_equal(merged$prices[[1]]$input, 2)
  expect_equal(merged$name, "Claude Sonnet 5.5")
  offline = catalog_snapshot(generated = "2026-09-30")
  expect_equal(offline$source, "gptr seed + overrides")
  expect_true(all(vapply(offline$models, function(m) !is.null(m$name), NA)))
  expect_type(json_encode(offline), "character")
})

test_that("native decisions bypass chat pruning and retain typed IC-74 metadata", {
  decision = list(
    id = "ollama/clef-flash", name = "Clef Flash", type = "decision", tool_call = FALSE,
    capabilities = list(decision = TRUE, tools = FALSE, vision = TRUE),
    modalities = list(input = list("text", "image"), output = list("decision")),
    limit = list(context = 8192, output = 0),
    decision = list(types = list("noul", "choice", "score"), images = TRUE,
                    server_min = "0.35.1", max_questions = 64, max_options = 26,
                    max_request_bytes_text = 65536, max_request_bytes_images = 33554432,
                    max_active = 1),
    digest = "sha256:fixture", server_version = "0.35.1", locality = "unknown",
    format = "gguf", quantization = "Q8_0", configured_context = 4096,
    remote_host = "cloud.example", remote_model = "clef-flash"
  )
  chat = list(id = "qwen3:1.7b", tool_call = TRUE,
               modalities = list(input = list("text"), output = list("text")))
  x = catalog_from_modelsdev(list(ollama = list(models = list(chat, decision))))
  expect_setequal(names(x), c("ollama/qwen3:1.7b", "ollama/clef-flash"))
  model = x[["ollama/clef-flash"]]
  expect_identical(model$type, "classifier")
  expect_identical(model$api, "ollama-system-one")
  expect_false(model$tool_call)
  expect_identical(as.character(model$input), c("text", "image"))
  expect_identical(model$decision$types, c("noul", "choice", "score"))
  expect_identical(model$decision$max_active, 1L)
  expect_identical(model$capabilities, decision$capabilities)
  expect_identical(model$digest, decision$digest)
  expect_identical(model$server_version, "0.35.1")
  expect_identical(model$locality, "unknown")
  expect_identical(model$format, "gguf")
  expect_identical(model$quantization, "Q8_0")
  expect_identical(model$context, 4096)
  expect_identical(model$remote_host, "cloud.example")
  expect_identical(model$remote_model, "clef-flash")
  expect_null(model$ollama)
  expect_identical(catalog_entry_decision(decision)$api, "ollama-system-one")
  decision$decision$images = "yes"
  expect_error(catalog_entry_decision(decision), class = "gptr_error_invalid_spec")
})

test_that("decision-only snapshots and offline Clef seeds do not claim availability", {
  decision = list(id = "ollama/fixture", type = "decision",
                   modalities = list(input = list("text", "image")))
  snap = catalog_snapshot(decision = list(decision), generated = "2026-10-03")
  refs = vapply(snap$models, function(m) paste0(m$provider, "/", m$id), "")
  expect_true("ollama/fixture" %in% refs)
  for (id in c("clef", "clef-flash")) {
    model = snap$models[[match(paste0("ollama/", id), refs)]]
    expect_identical(model$type, "classifier")
    expect_identical(model$api, "ollama-system-one")
    expect_identical(model$locality, "unknown")
    expect_identical(model$decision$server_min, "0.35.1")
    expect_false(model$tool_call)
    expect_null(model$context)
    expect_null(model$ollama)
  }
})

test_that("chat catalog conversion retains locality markers and configured context", {
  chat = list(id = "qwen3:1.7b", tool_call = TRUE,
               modalities = list(input = list("text"), output = list("text")),
               capabilities = list(tools = TRUE), digest = "sha256:chat-fixture",
               server_version = "0.35.1", locality = "remote", format = "gguf",
               quantization = "Q4_K_M", configured_context = 4096,
               limit = list(context = 8192), remote_host = "cloud.example",
               remote_model = "qwen3")
  model = catalog_entry_modelsdev(chat, "ollama")
  for (field in c("capabilities", "digest", "server_version", "locality", "format",
                  "quantization", "configured_context", "remote_host", "remote_model")) {
    expect_identical(model[[field]], chat[[field]])
  }
  expect_identical(model$context, 4096)
  chat$capabilities$tools = "yes"
  expect_error(catalog_entry_modelsdev(chat, "ollama"), class = "gptr_error_invalid_spec")
})

test_that("catalog metadata uses exact names and context must be a finite scalar", {
  entry = list(id = "ollama/fixture", decision = list(types_future = "score"))
  model = catalog_entry_decision(entry)
  expect_null(model$decision[["types"]])
  expect_identical(model$decision[["types_future"]], "score")
  entry$configured_context = Inf
  expect_error(catalog_entry_decision(entry), class = "gptr_error_invalid_argument")
  entry$configured_context = 4096
  for (limit in list(c(8192, 16384), Inf)) {
    entry$limit = list(context = limit)
    expect_error(catalog_entry_decision(entry), class = "gptr_error_invalid_argument")
  }
})

fx_model = function(provider, id, family, date = NULL, levels = list("low", "medium", "high"),
                    owner = provider, ...) {
  c(list(provider = provider, id = id, name = id, family = family, release_date = date,
         context = 1e6, max_output = 64000, reasoning = TRUE, thinking_levels = levels,
         input = list("text", "image"), tool_call = TRUE, status = "active", owner = owner),
    list(...))
}

fx_models = function() {
  adaptive = list("low", "medium", "high", "xhigh", "max")
  list(
    fx_model("anthropic", "claude-sonnet-5-5", "claude-sonnet", "2026-09-28", adaptive),
    fx_model("anthropic", "claude-sonnet-5", "claude-sonnet", "2026-05-01", adaptive),
    fx_model("anthropic", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive),
    fx_model("anthropic", "claude-haiku-4-5", "claude-haiku", "2025-10-15",
             list("off", "minimal", "low", "medium", "high")),
    fx_model("anthropic", "claude-haiku-4-5-20251001", "claude-haiku", "2025-10-15",
             list("off", "minimal", "low", "medium", "high")),
    fx_model("azure", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive,
             owner = "anthropic"),
    fx_model("bedrock", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive,
             owner = "anthropic"),
    fx_model("openai", "gpt-6.1-sol", "gpt-sol", "2026-09-29", adaptive),
    fx_model("openai", "gpt-6-luna", "gpt-luna", "2026-09-22"),
    fx_model("openrouter", "anthropic/claude-sonnet-5.5", "claude-sonnet", "2026-09-28",
             owner = "anthropic"),
    list(provider = "typesafe", id = "jev-latest", name = "Jev", type = "classifier",
         reasoning = FALSE, tool_call = FALSE, status = "active")
  )
}

local_catalog = function(models = fx_models(), .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  path = file.path(dir, "models.json")
  snap = list(schema_version = 1L, generated = "2026-09-30", source = "test fixture",
              providers = list(), models = models, aliases = list())
  writeLines(json_encode(snap), path, useBytes = TRUE)
  testthat::local_mocked_bindings(
    catalog_snapshot_path = function() path,
    catalog_cache_path = function() file.path(dir, "cache-models.json"),
    catalog_etag_path = function() file.path(dir, "cache-models.etag"),
    .env = .env
  )
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE), envir = .env)
  invisible(dir)
}

test_that("references resolve: exact, alias, family, normalised, owner, thinking", {
  local_catalog()
  expect_equal(model_resolve("anthropic/claude-sonnet-5-5")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("sonnet")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-sonnet")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-sonnet-5.5")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  expect_equal(model_resolve("openrouter/anthropic/claude-sonnet-5-5")$ref,
               "openrouter/anthropic/claude-sonnet-5.5")
  expect_equal(model_resolve("gpt")$ref, "openai/gpt-6.1-sol")
  opus = model_resolve("opus:xhigh")
  expect_equal(opus$ref, "anthropic/claude-opus-5-5")
  expect_equal(opus$thinking, "xhigh")
  expect_equal(model_resolve("opus:minimal")$thinking, "low")
  expect_equal(model_resolve("haiku:max")$thinking, "high")
  expect_equal(model_resolve("haiku")$ref, "anthropic/claude-haiku-4-5")
  expect_null(model_resolve("sonnet")$thinking)
  jev = model_resolve("jev")
  expect_equal(jev$type, "classifier")
  expect_equal(jev$api, "typesafe-system-one")
})

test_that("a model record has every contract field (04 section 4.9)", {
  local_catalog()
  r = model_resolve("sonnet")
  expect_named(r, c("ref", "provider", "id", "name", "family", "api", "type", "release_date",
                    "context", "max_output", "reasoning", "thinking_levels", "thinking",
                    "input", "tool_call", "structured_output", "prices", "cache_min",
                    "max_images", "capabilities", "aliases", "status", "local"))
  expect_equal(r$api, "anthropic-messages")
  expect_equal(r$aliases, "sonnet")
  expect_s3_class(r$prices, "data.frame")
  expect_named(r$prices, c("from", "tier", "input", "output", "cache_read", "cache_write_5m",
                           "cache_write_1h"))
  expect_equal(r$cache_min, 512)
  expect_equal(r$max_images, 600)
  expect_named(r$capabilities, c("mid_system", "tool_addition", "images_in_results",
                                 "operator_role", "adaptive_thinking", "effort",
                                 "forced_tool_choice"))
  expect_false(r$capabilities$forced_tool_choice)
  expect_true(model_resolve("openai/gpt-6.1-sol")$capabilities$forced_tool_choice)
  expect_equal(r$thinking_levels, c("off", "low", "medium", "high", "xhigh", "max"))
  expect_equal(model_resolve("sonnet:off")$thinking, "off")
  expect_equal(model_resolve("opus:off")$thinking, "low")
})

test_that("unknown references fail with suggestions, or NULL when not strict", {
  local_catalog()
  err = expect_error(model_resolve("claude-sonet-5-5"), class = "gptr_error_unknown_model")
  expect_true("claude-sonnet-5-5" %in% err$suggestions)
  expect_equal(err$ref, "claude-sonet-5-5")
  expect_null(model_resolve("sonnet:turbo", strict = FALSE))
  expect_error(model_resolve("anthropic/claude-nope"), class = "gptr_error_unknown_model")
  expect_error(model_resolve(42), class = "gptr_error_invalid_argument")
  skip_if_not(is.null(provider_get("claude-cli")), "builtin:cli (P20) registers claude-cli")
  expect_error(model_resolve("claude_code"), "claude-cli", class = "gptr_error_unknown_model")
})

test_that("local providers accept unknown ids; a provider added by data resolves (INFRA-17)", {
  local_catalog()
  qwen = model_resolve("ollama/qwen3.5:9b:high")
  expect_equal(qwen$id, "qwen3.5:9b")
  expect_equal(qwen$thinking, "off")
  expect_false(qwen$reasoning)
  expect_false(qwen$tool_call)
  expect_identical(qwen$locality, "unknown")
  llama = model_resolve("ollama/llama3.2:3b")
  expect_equal(llama$id, "llama3.2:3b")
  expect_null(llama$thinking)
  expect_true(llama$local)
  expect_equal(llama$api, "openai-completions")
  off = gptr_register(gptr_provider("labserver", api = "openai-completions",
                                    base_url = "http://127.0.0.1:9999/v1", local = TRUE,
                                    models = list(list(id = "qwen-lab", context = 32768))))
  withr::defer(off())
  lab = model_resolve("labserver/qwen-lab")
  expect_equal(lab$context, 32768)
  expect_equal(lab$api, "openai-completions")
  expect_true(lab$local)
  expect_null(provider_credential(provider_get("labserver")))
  spec = gptr_fake_provider(list("hi"), name = "specfake")
  expect_equal(model_resolve(spec)$ref, "specfake/specfake-1")
})

test_that("user configuration is a merge layer above the snapshot", {
  local_catalog()
  local_settings(providers = list(anthropic = list(models = list(
    list(id = "claude-sonnet-5-5", context = 2e6)
  ))))
  expect_equal(model_resolve("sonnet")$context, 2e6)
  expect_equal(model_resolve("sonnet")$prices$input[[1]], 2)
})

test_that("a bare id of several providers goes to the one with a credential, then the owner", {
  local_catalog()
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  local_mocked_bindings(model_key_present = function(id, vars) identical(id, "azure"))
  expect_equal(model_resolve("claude-opus-5-5")$ref, "azure/claude-opus-5-5")
  local_mocked_bindings(model_key_present = function(id, vars) id %in% c("azure", "anthropic"))
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  # two credentialed resellers and an owner without a key: ambiguous, never the keyless owner
  local_mocked_bindings(model_key_present = function(id, vars) id %in% c("azure", "bedrock"))
  err = expect_error(model_resolve("claude-opus-5-5"), class = "gptr_error_unknown_model")
  expect_setequal(err$suggestions, c("azure/claude-opus-5-5", "bedrock/claude-opus-5-5"))
  expect_match(conditionMessage(err), "several providers", fixed = TRUE)
})

test_that("a model registered as a `model` spec joins the catalog (04 section 10.2 row 3)", {
  local_catalog()
  off = gptr_register(gptr_spec("model", "anthropic/claude-lab-1", label = "Claude Lab 1",
                                family = "claude-lab", context = 4096, status = "preview"))
  withr::defer(off())
  m = model_resolve("anthropic/claude-lab-1")
  expect_equal(m$name, "Claude Lab 1")
  expect_equal(m$context, 4096)
  expect_equal(m$api, "anthropic-messages")
  expect_equal(m$status, "preview")
})

test_that("a fake provider used only as a session's spec still resolves by reference", {
  local_catalog()
  fake = gptr_fake_provider(list("hi"), name = "p05fake")
  m = model_resolve("p05fake/p05fake-1")
  expect_equal(m$ref, "p05fake/p05fake-1")
  expect_equal(m$api, "fake")
  expect_true(m$local)
  expect_null(m$fake)
  expect_equal(model_resolve("p05fake/p05fake-1:high")$thinking, "high")
  expect_null(model_resolve("p05fake/other", strict = FALSE))
})


test_that("mixed provider models resolve their own native route and typed metadata", {
  local_catalog()
  entry = list(id = "clef-test", type = "classifier", api = "ollama-system-one",
                 tool_call = FALSE, decision = list(types = c("noul", "choice", "score"),
                   images = TRUE, server_min = "0.35.1", max_questions = 64L, max_active = 1L),
                 digest = "sha256:fixture", server_version = "0.35.1", locality = "unknown",
                 format = "gguf", quantization = "Q8_0", configured_context = 4096,
                 context = 8192, remote_host = "cloud.example", remote_model = "clef-test")
  off = gptr_register(gptr_provider("mixed", api = "openai-completions", type = "chat",
    local = TRUE, base_url = "http://127.0.0.1:11434/v1", models = list(entry,
      list(id = "chat-test", type = "chat", tool_call = TRUE))))
  withr::defer(off())
  model = model_resolve("mixed/clef-test")
  expect_identical(model$type, "classifier")
  expect_identical(model$api, "ollama-system-one")
  expect_false(model$tool_call)
  for (field in c("decision", "digest", "server_version", "locality", "format",
                  "quantization", "configured_context", "remote_host", "remote_model")) {
    expect_identical(model[[field]], entry[[field]])
  }
  expect_identical(model$context, 4096)
  expect_identical(model_resolve("mixed/chat-test")$api, "openai-completions")
  expect_identical(model_resolve("mixed/chat-test")$type, "chat")
})

test_that("unknown Ollama model names never grant tools vision or configured capacity", {
  local_catalog()
  model = model_resolve("ollama/unknown-model:7b")
  expect_false(model$tool_call)
  expect_false(model$reasoning)
  expect_identical(model$input, "text")
  expect_true(is.na(model$context))
  expect_identical(model$locality, "unknown")
  expect_null(model$ollama)
})

test_that("credential presence checks do not register store values or query keyring", {
  local_vault()
  local_mocked_bindings(
    secret_lookup = function(name) NULL,
    auth_store_get = function(...) stop("must not resolve credentials"),
    auth_record_values = function(...) stop("must not resolve keyring"),
    auth_store_read = function() {
      list(lab = list(type = "api_key", key = "synthetic-catalog-presence-key-123456"),
           locked = list(type = "api_key", keyring = list(service = "gptr", username = "locked")))
    }
  )
  expect_true(model_key_present("lab", character()))
  expect_true(model_key_present("locked", character()))
  expect_false(model_key_present("missing", character()))
  expect_length(secrets_state()$reg, 0L)
})

test_that("pure resolution does not invoke provider discovery and rejects malformed capabilities", {
  local_catalog()
  off = gptr_register(gptr_provider("pure-local", api = "openai-completions", local = TRUE,
    base_url = "http://127.0.0.1:1234/v1", discover = function() stop("unexpected discovery"),
    models = list(list(id = "tag:high", tool_call = TRUE))))
  withr::defer(off())
  expect_identical(model_resolve("pure-local/tag:high")$id, "tag:high")
  expect_null(model_resolve("pure-local/tag:high")$thinking)
  expect_false(model_resolve("pure-local/unknown")$tool_call)
  local_settings(providers = list(ollama = list(models = list(
    list(id = "broken", capabilities = list(vision = "0.35.1"))
  ))))
  expect_error(model_resolve("ollama/broken"), class = "gptr_error_invalid_spec")
})

# ---- Task 8: the bounded catalog HTTP request, gptr_models(), defaults, explicit refresh, local
# discovery and request preflight (IC-74, 07-local-ollama.md sections 2 and 2.1) -----------------

test_that("catalog HTTP GET uses the reactor and preserves status headers and bytes", {
  local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL,
                            run = NULL, provider = NULL, retry = NULL) {
      expect_identical(spec$url, "https://catalog.example/models")
      expect_identical(spec$method, "GET")
      expect_null(spec$body)
      expect_identical(spec$headers, list(accept = "application/json"))
      expect_identical(provider, "catalog")
      on_headers(200L, list(etag = "fixture"))
      on_bytes(charToRaw("first"))
      on_bytes(charToRaw("second"))
      on_done(200L, list(etag = "fixture"))
      "catalog-test"
    },
    reactor_pump = function(until, timeout) {
      expect_identical(timeout, 1)
      until()
    },
    reactor_cancel = function(...) stop("completed request must not be cancelled")
  )
  out = catalog_http_request("https://catalog.example/models",
                             headers = list(accept = "application/json"), timeout = 1)
  expect_identical(out$status, 200L)
  expect_identical(out$headers$etag, "fixture")
  expect_identical(out$body, charToRaw("firstsecond"))
})

test_that("catalog HTTP supports metadata POST and HTTP error status", {
  local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL,
                            run = NULL, provider = NULL, retry = NULL) {
      expect_identical(spec$method, "POST")
      expect_identical(spec$body, '{"model":"clef"}')
      on_fail(gptr_condition("HTTP error", "network",
                             fields = list(status = 404L, curl_code = NA_integer_)))
      "catalog-test"
    },
    reactor_pump = function(until, timeout) until()
  )
  out = catalog_http_request("http://127.0.0.1:11434/api/show", method = "POST",
                             body = '{"model":"clef"}')
  expect_identical(out$status, 404L)
  expect_identical(out$body, raw())
})

test_that("catalog HTTP cancels only its own transfer on timeout, interrupt or oversize", {
  cancelled = character()
  local_mocked_bindings(
    reactor_http = function(...) "catalog-owned",
    reactor_pump = function(...) FALSE,
    reactor_cancel = function(ids) {
      cancelled <<- c(cancelled, ids)
      invisible(NULL)
    }
  )
  expect_error(catalog_http_request("https://catalog.example", timeout = 1),
               class = "gptr_error_network")
  expect_identical(cancelled, "catalog-owned")
  cancelled = character()
  local_mocked_bindings(reactor_pump = function(...) stop("interrupted pump"))
  expect_error(catalog_http_request("https://catalog.example"), "interrupted pump")
  expect_identical(cancelled, "catalog-owned")
  cancelled = character()
  local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL,
                            run = NULL, provider = NULL, retry = NULL) {
      expect_identical(retry, list(max_attempts = 1L))
      on_headers(200L, list())
      on_bytes(as.raw(1:8))
      "catalog-large"
    },
    reactor_pump = function(until, timeout) until()
  )
  expect_error(catalog_http_request("https://catalog.example", attempts = 1L, max_bytes = 4),
               class = "gptr_error_network")
  expect_identical(cancelled, "catalog-large")
})

test_that("catalog HTTP validates arguments before dispatch and handles transport failure", {
  local_mocked_bindings(reactor_http = function(...) stop("unexpected dispatch"))
  expect_error(catalog_http_request("https://catalog.example", timeout = Inf),
               class = "gptr_error_invalid_argument")
  expect_error(catalog_http_request("not-a-url"), class = "gptr_error_invalid_argument")
  expect_error(catalog_http_request("ftp://catalog.example/x"),
               class = "gptr_error_invalid_argument")
  local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL,
                            run = NULL, provider = NULL, retry = NULL) {
      on_fail(gptr_condition("unreachable", "network",
                             fields = list(status = NA_integer_, curl_code = 7L)))
      "catalog-test"
    },
    reactor_pump = function(until, timeout) until()
  )
  err = expect_error(catalog_http_request("https://catalog.example"),
                     class = "gptr_error_network")
  expect_identical(err$curl_code, 7L)
})

test_that("catalog_http_request() runs on the real reactor against loopback fixtures", {
  ok = local_mock_server("json", body = "{\"version\":\"0.35.1\"}")
  got = catalog_http_request(paste0(ok$url, "/api/version"), timeout = 5, attempts = 1L)
  expect_identical(got$status, 200L)
  expect_identical(json_decode(raw_to_utf8(got$body))$version, "0.35.1")
  posted = catalog_http_request(paste0(ok$url, "/api/show"), method = "POST",
                                headers = list(`content-type` = "application/json"),
                                body = "{\"model\":\"clef\"}", timeout = 5, attempts = 1L)
  expect_identical(posted$status, 200L)
  log = ok$log()
  expect_identical(log$method, c("GET", "POST"))
  expect_identical(log$body[[2]], "{\"model\":\"clef\"}")
  missing = local_mock_server("json", status = 404L, body = "{\"error\":\"none\"}")
  expect_identical(catalog_http_request(paste0(missing$url, "/api/tags"), timeout = 5)$status,
                   404L)
  hold = local_mock_server("hold_headers")
  before = ls(reactor_get()$transfers)
  err = expect_error(catalog_http_request(hold$url, timeout = 1, attempts = 1L),
                     class = "gptr_error_network")
  # the reactor's first-byte timer or the pump deadline, whichever fires first: both are 1 s
  expect_match(conditionMessage(err), "1 s", fixed = TRUE)
  expect_identical(ls(reactor_get()$transfers), before)
})

test_that("a loopback server's listed models join the catalog only on request", {
  local_catalog()
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, headers = list(), timeout = 30, ...) {
      expect_equal(url, "http://localhost:1234/v1/models")
      expect_equal(timeout, 1)
      list(status = 200L, headers = list(),
           body = charToRaw('{"data":[{"id":"llama3.2:3b"},{"id":"qwen3.5:9b"}]}'))
    }
  )
  expect_equal(nrow(gptr_models(provider = "lmstudio")), 0L)
  found = gptr_models(provider = "lmstudio", refresh = TRUE)
  expect_setequal(found$ref, c("lmstudio/llama3.2:3b", "lmstudio/qwen3.5:9b"))
  # IC-74: a listed name grants no tools, vision or locality
  m = model_resolve("lmstudio/qwen3.5:9b")
  expect_false(m$tool_call)
  expect_identical(m$input, "text")
  expect_identical(m$locality, "unknown")
})

test_that("gptr_models() searches the catalog and lists prices in force", {
  local_catalog()
  df = gptr_models("sonnet")
  expect_s3_class(df, "gptr_models")
  expect_named(df, c("ref", "provider", "name", "context", "max_output", "input_price",
                     "output_price", "reasoning", "aliases", "status"))
  expect_equal(df$ref[[1]], "anthropic/claude-sonnet-5-5")
  expect_equal(df$input_price[[1]], 2)
  expect_equal(df$aliases[[1]], "sonnet")
  claude = gptr_models("claude", provider = "anthropic")
  expect_true(all(claude$provider == "anthropic"))
  expect_true(nrow(claude) >= 4L)
  expect_equal(nrow(gptr_models("[unclosed")), 0L)
  expect_error(gptr_models(query = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_models(refresh = NA), class = "gptr_error_invalid_argument")
})

test_that("model_default() follows the settings, then the first available key", {
  local_catalog()
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL,
                        auth_store_read = function() list(),
                        model_cli_available = function(id) FALSE)
  withr::local_envvar(ANTHROPIC_API_KEY = "", OPENAI_API_KEY = "", GEMINI_API_KEY = "",
                      GOOGLE_API_KEY = "", TYPESAFE_API_KEY = "")
  expect_null(model_default("chat"))
  expect_null(model_default("system1"))
  withr::local_envvar(OPENAI_API_KEY = "sk-test-openai-000000000000")
  expect_equal(model_default("chat"), "openai/gpt-6-sol")
  expect_equal(model_default("small"), "openai/gpt-6-luna")
  withr::local_envvar(TYPESAFE_API_KEY = "ts-test-000000000000")
  expect_equal(model_default("system1"), "typesafe/jev-latest")
  local_settings(model = "sonnet")
  expect_equal(model_default("chat"), "sonnet")
  expect_equal(model_default("small"), "anthropic/claude-haiku-4-5")
  expect_true(all(c("sonnet", "jev", "claude_code") %in% catalog_aliases()))
  expect_error(model_default("large"), class = "gptr_error_invalid_argument")
})

test_that("model_default() skips providers disabled in the settings", {
  local_catalog()
  local_mocked_bindings(model_cli_available = function(id) FALSE,
                        model_key_present = function(id, vars) id %in% c("anthropic", "openai"))
  expect_equal(model_default("chat"), "anthropic/claude-sonnet-5-5")
  local_settings(providers = list(anthropic = list(enabled = FALSE)))
  expect_equal(model_default("chat"), "openai/gpt-6-sol")
})

test_that("a detected subscription CLI is the last default route", {
  local_catalog()
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  off = gptr_register(gptr_provider("claude-cli", api = "cli-claude", type = "cli",
                                    status = function(check) {
                                      list(available = identical(check, FALSE))
                                    }))
  withr::defer(off())
  expect_true(model_cli_available("claude-cli"))
  expect_equal(model_default("chat"), "claude-cli/default")
  expect_false(model_cli_available("no-such-cli"))
})

test_that("an explicit refresh revalidates with the ETag and caches in R_user_dir", {
  dir = local_catalog()
  api = list(anthropic = list(id = "anthropic", models = list(`claude-sonnet-6` = list(
    id = "claude-sonnet-6", name = "Claude Sonnet 6", family = "claude-sonnet", reasoning = TRUE,
    tool_call = TRUE, release_date = "2026-12-01", limit = list(context = 1e6, output = 128000),
    modalities = list(input = list("text"), output = list("text")),
    cost = list(input = 2, output = 10)
  ))))
  seen = new.env()
  seen$headers = list()
  local_mocked_bindings(catalog_http_request = function(url, headers = list(), timeout = 30, ...) {
    if (!identical(url, catalog_source_url)) return(list(status = 404L, headers = list(),
                                                         body = raw()))
    seen$headers[[length(seen$headers) + 1L]] = headers
    if (identical(headers[["if-none-match"]], "W/\"v1\"")) {
      return(list(status = 304L, headers = list(), body = raw()))
    }
    list(status = 200L, headers = list(ETag = "W/\"v1\""), body = charToRaw(json_encode(api)))
  })
  expect_true(catalog_refresh())
  expect_true(file.exists(file.path(dir, "cache-models.json")))
  expect_equal(readLines(file.path(dir, "cache-models.etag"), warn = FALSE), "W/\"v1\"")
  expect_equal(model_resolve("sonnet")$ref, "anthropic/claude-sonnet-6")
  expect_false(catalog_refresh())
  expect_equal(seen$headers[[2]][["if-none-match"]], "W/\"v1\"")
  local_mocked_bindings(catalog_http_request = function(url, headers = list(), timeout = 30, ...) {
    list(status = 503L, headers = list(), body = raw())
  })
  unlink(file.path(dir, "cache-models.etag"))
  expect_error(catalog_refresh(), class = "gptr_error_network")
})

test_that("resolution is offline: builtins and gptr_models('sonnet') start no transfer", {
  count = new.env()
  count$transfers = 0L
  local_mocked_bindings(reactor_http = function(...) {
    count$transfers = count$transfers + 1L
    "t1"
  })
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE))
  api = new.env()
  api$specs = list()
  api$register = function(spec) {
    api$specs[[length(api$specs) + 1L]] = spec
    invisible(function() NULL)
  }
  builtin_providers(api)
  expect_length(api$specs, 17L)
  expect_true(all(vapply(api$specs, function(s) inherits(s, "gptr_provider"), NA)))
  expect_null(the$catalog)
  df = gptr_models("sonnet")
  expect_match(df$ref[[1]], "^anthropic/claude-sonnet-")
  expect_equal(df$ref[[1]], model_resolve("sonnet")$ref)
  expect_equal(count$transfers, 0L)
})

# Synthetic answers of a native Ollama server (07-local-ollama.md section 2): /api/version,
# /api/tags and /api/show in the documented JSON shapes. No server runs and no request leaves
# the process: catalog_http_request() is replaced and records what it was asked.
ollama_fixture = function() {
  list(
    `qwen3:1.7b` = list(
      tag = list(name = "qwen3:1.7b", model = "qwen3:1.7b", size = 1359293444,
                 digest = strrep("1", 64),
                 details = list(format = "gguf", family = "qwen3", parameter_size = "2.0B",
                                quantization_level = "Q4_K_M")),
      show = list(capabilities = list("completion", "tools", "thinking"),
                  parameters = "num_ctx                        8192\nstop \"<|im_end|>\"",
                  details = list(format = "gguf", family = "qwen3",
                                 quantization_level = "Q4_K_M"),
                  model_info = list(general.architecture = "qwen3",
                                    qwen3.context_length = 40960))),
    `clef-flash:latest` = list(
      tag = list(name = "clef-flash:latest", model = "clef-flash:latest", size = 11e9,
                 digest = strrep("2", 64),
                 details = list(format = "gguf", family = "clef", quantization_level = "Q8_0")),
      show = list(capabilities = list("decision"), parameters = "num_ctx 16384",
                  details = list(format = "gguf", family = "clef", quantization_level = "Q8_0"),
                  model_info = list(general.architecture = "clef", clef.context_length = 262144),
                  projector_info = list(clip.has_vision_encoder = TRUE))),
    `gpt-oss:120b-cloud` = list(
      tag = list(name = "gpt-oss:120b-cloud", model = "gpt-oss:120b-cloud", size = 384,
                 digest = strrep("3", 64), remote_model = "gpt-oss:120b",
                 remote_host = "https://ollama.com:443",
                 details = list(format = "", family = "gptoss", quantization_level = "")),
      show = list(capabilities = list("completion", "tools", "thinking"),
                  remote_model = "gpt-oss:120b", remote_host = "https://ollama.com:443",
                  details = list(format = "", family = "gptoss")))
  )
}

local_ollama_server = function(models = ollama_fixture(), version = "0.35.1",
                               .env = parent.frame()) {
  srv = new.env(parent = emptyenv())
  srv$models = models
  srv$version = version
  srv$down = FALSE
  srv$slow = character()
  srv$calls = character()
  srv$timeouts = numeric()
  answer = function(x) list(status = 200L, headers = list(), body = charToRaw(json_encode(x)))
  testthat::local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, method = "GET", headers = list(), body = NULL,
                                    timeout = 30, ...) {
      srv$calls = c(srv$calls, paste(method, url))
      srv$timeouts = c(srv$timeouts, timeout)
      if (srv$down) {
        gptr_abort("Could not reach the fixture: connection refused", c("network", "provider"),
                   provider = "catalog", status = NA_integer_, curl_code = 7L)
      }
      path = sub("^https?://[^/]+", "", url)
      if (identical(path, "/api/version")) return(answer(list(version = srv$version)))
      if (identical(path, "/api/tags")) {
        return(answer(list(models = unname(lapply(srv$models, function(m) m$tag)))))
      }
      if (identical(path, "/api/show") && identical(method, "POST")) {
        name = json_decode(body)$model
        if (name %in% srv$slow) {
          gptr_abort("No answer from the fixture within 1 s.", c("network", "provider"),
                     provider = "catalog", status = NA_integer_, curl_code = 28L)
        }
        m = srv$models[[name]]
        if (!is.null(m)) return(answer(m$show))
      }
      list(status = 404L, headers = list(), body = raw())
    },
    .env = .env
  )
  srv
}

test_that("native Ollama discovery reads version, tags and show only on explicit request", {
  local_catalog()
  srv = local_ollama_server()
  expect_equal(nrow(gptr_models(provider = "ollama")), 0L)
  expect_length(srv$calls, 0L)
  found = gptr_models(provider = "ollama", refresh = TRUE)
  expect_setequal(found$ref, c("ollama/qwen3:1.7b", "ollama/clef-flash:latest",
                               "ollama/gpt-oss:120b-cloud"))
  root = "http://127.0.0.1:11434"
  expect_identical(srv$calls, c(paste0("GET ", root, c("/api/version", "/api/tags")),
                                rep(paste0("POST ", root, "/api/show"), 3L)))
  expect_true(all(srv$timeouts == 1))
  expect_equal(found$input_price[found$ref == "ollama/qwen3:1.7b"], 0)
  expect_true(is.na(found$input_price[found$ref == "ollama/gpt-oss:120b-cloud"]))
  qwen = model_resolve("ollama/qwen3:1.7b")
  expect_identical(qwen$type, "chat")
  expect_identical(qwen$api, "openai-completions")
  expect_true(qwen$tool_call)
  expect_true(qwen$reasoning)
  expect_identical(qwen$input, "text")
  expect_identical(qwen$context, 8192)
  expect_identical(qwen$locality, "local")
  expect_identical(qwen$digest, strrep("1", 64))
  expect_identical(qwen$server_version, "0.35.1")
  expect_identical(qwen$quantization, "Q4_K_M")
  expect_true(qwen$capabilities$tools)
  expect_identical(qwen$prices$input, 0)
  clef = model_resolve("ollama/clef-flash:latest")
  expect_identical(clef$type, "classifier")
  expect_identical(clef$api, "ollama-system-one")
  expect_false(clef$tool_call)
  expect_identical(clef$input, c("text", "image"))
  expect_true(clef$decision$images)
  expect_identical(clef$decision$server_min, "0.35.1")
  expect_identical(clef$decision$max_active, 1L)
  expect_identical(clef$context, 16384)
  cloud = model_resolve("ollama/gpt-oss:120b-cloud")
  expect_identical(cloud$locality, "remote")
  expect_identical(cloud$remote_host, "https://ollama.com:443")
  expect_equal(nrow(cloud$prices), 0L)
  # listing, resolution and defaults afterwards contact nothing
  n = length(srv$calls)
  gptr_models("qwen")
  model_resolve("ollama/qwen3:1.7b")
  model_default("chat")
  expect_length(srv$calls, n)
  # the provider record's discover() is the same native path
  expect_setequal(provider_get("ollama")$discover()$id, names(ollama_fixture()))
  # never under R CMD check: no request and nothing discovered
  catalog_reset(discovered = TRUE)
  n = length(srv$calls)
  local_mocked_bindings(check_running = function() TRUE)
  expect_equal(nrow(gptr_models(provider = "ollama", refresh = TRUE)), 0L)
  expect_length(srv$calls, n)
})

test_that("provider_preflight() is pure and passes other providers' models through", {
  local_catalog()
  local_mocked_bindings(catalog_http_request = function(...) stop("preflight did I/O"),
                        reactor_http = function(...) stop("preflight started a transfer"))
  m = model_resolve("sonnet")
  expect_identical(provider_preflight(m, provider_get("anthropic")), m)
  expect_error(provider_preflight(m, provider_get("anthropic"),
                                  safety = list(ollama_local_only = NA)),
               class = "gptr_error_invalid_argument")
  expect_error(provider_preflight("sonnet", provider_get("anthropic")),
               class = "gptr_error_invalid_argument")
  err = expect_error(provider_preflight(model_resolve("ollama/qwen3:1.7b"), provider_get("ollama")),
                     class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "model_prepare", fixed = TRUE)
  expect_error(provider_preflight(model_resolve("ollama/qwen3:1.7b"), provider_get("lmstudio")),
               class = "gptr_error_invalid_argument")
})

test_that("catalog fields, model specs and settings cannot self-attest local execution", {
  local_catalog()
  local_mocked_bindings(catalog_http_request = function(...) stop("no request expected"))
  claimed = list(id = "qwen3:1.7b", type = "chat", tool_call = TRUE, locality = "local",
                 digest = strrep("1", 64), server_version = "0.35.1",
                 capabilities = list(completion = TRUE, tools = TRUE))
  local_settings(providers = list(ollama = list(local_only = FALSE, models = list(claimed))))
  m = model_resolve("ollama/qwen3:1.7b")
  expect_identical(m$locality, "local")
  m$ollama = list(verified = TRUE, source = "discovery")
  expect_error(provider_preflight(m, provider_get("ollama")), class = "gptr_error_not_available")
  off = gptr_register(gptr_spec("model", "ollama/clef-claimed", type = "classifier",
                                api = "ollama-system-one", locality = "local",
                                server_version = "0.35.1", digest = strrep("2", 64),
                                decision = list(types = "noul", server_min = "0.35.1")))
  withr::defer(off())
  expect_error(provider_preflight(model_resolve("ollama/clef-claimed"), provider_get("ollama")),
               class = "gptr_error_not_available")
  # the provider's `local` hint is not evidence either
  lab = gptr_register(gptr_provider("labollama", api = "ollama-system-one", local = TRUE,
                                    base_url = "http://127.0.0.1:11434/v1",
                                    models = list(list(id = "clef", type = "classifier"))))
  withr::defer(lab())
  expect_error(provider_preflight(model_resolve("labollama/clef"), provider_get("labollama")),
               class = "gptr_error_not_available")
})

test_that("preflight checks evidence: locality, decision capability and server version", {
  local_catalog()
  srv = local_ollama_server()
  gptr_models(provider = "ollama", refresh = TRUE)
  n = length(srv$calls)
  p = provider_get("ollama")
  qwen = provider_preflight(model_resolve("ollama/qwen3:1.7b"), p)
  expect_identical(qwen$ref, "ollama/qwen3:1.7b")
  expect_true(qwen$tool_call)
  expect_identical(qwen$locality, "local")
  clef = provider_preflight(model_resolve("ollama/clef-flash:latest"), p)
  expect_identical(clef$api, "ollama-system-one")
  expect_identical(clef$server_version, "0.35.1")
  expect_error(provider_preflight(model_resolve("ollama/gpt-oss:120b-cloud"), p),
               class = "gptr_error_untrusted")
  as_chat = model_resolve("ollama/clef-flash:latest")
  as_chat$type = "chat"
  as_chat$api = "openai-completions"
  expect_error(provider_preflight(as_chat, p), class = "gptr_error_not_available")
  as_s1 = model_resolve("ollama/qwen3:1.7b")
  as_s1$type = "classifier"
  as_s1$api = "ollama-system-one"
  expect_error(provider_preflight(as_s1, p), class = "gptr_error_not_available")
  # claimed capabilities shrink to the evidence
  vision = model_resolve("ollama/qwen3:1.7b")
  vision$input = c("text", "image")
  expect_identical(provider_preflight(vision, p)$input, "text")
  # a bare tag means :latest
  bare = model_resolve("ollama/clef-flash:latest")
  bare$id = "clef-flash"
  bare$ref = "ollama/clef-flash"
  expect_identical(provider_preflight(bare, p)$digest, strrep("2", 64))
  expect_length(srv$calls, n)
  # an older server: classifiers are refused, chat still passes
  srv$version = "0.35.0"
  gptr_models(provider = "ollama", refresh = TRUE)
  err = expect_error(provider_preflight(model_resolve("ollama/clef-flash:latest"), p),
                     class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "0.35.1", fixed = TRUE)
  expect_identical(provider_preflight(model_resolve("ollama/qwen3:1.7b"), p)$server_version,
                   "0.35.0")
})

test_that("discovery evidence is bound to endpoint, path, registry lifecycle and identity", {
  local_catalog()
  srv = local_ollama_server()
  gptr_models(provider = "ollama", refresh = TRUE)
  m = model_resolve("ollama/qwen3:1.7b")
  expect_identical(provider_preflight(m, provider_get("ollama"))$digest, strrep("1", 64))
  for (url in c("http://127.0.0.1:11435/v1", "http://127.0.0.1:11434/proxy/v1")) {
    local({
      local_settings(providers = list(ollama = list(base_url = url)))
      err = expect_error(provider_preflight(m, provider_get("ollama")),
                         class = "gptr_error_not_available")
      expect_match(conditionMessage(err), "endpoint", fixed = TRUE)
    })
  }
  local({
    off = gptr_register(gptr_provider("ollama", api = "openai-completions", local = TRUE,
                                      base_url = "http://127.0.0.1:11434/v1"))
    withr::defer(off())
    expect_error(provider_preflight(m, provider_get("ollama")),
                 class = "gptr_error_not_available")
  })
  expect_identical(provider_preflight(m, provider_get("ollama"))$ref, m$ref)
  reg = registry_env()
  local({
    generation = reg$generation
    assign("generation", generation + 1L, envir = reg)
    withr::defer(assign("generation", generation, envir = reg))
    expect_error(provider_preflight(m, provider_get("ollama")),
                 class = "gptr_error_not_available")
  })
  # a prepared model keeps its identity: a moved tag is not silently replaced
  n = length(srv$calls)
  frozen = model_prepare("ollama/qwen3:1.7b")
  expect_length(srv$calls, n)
  expect_identical(frozen$digest, strrep("1", 64))
  srv$models[["qwen3:1.7b"]]$tag$digest = strrep("4", 64)
  gptr_models(provider = "ollama", refresh = TRUE)
  err = expect_error(provider_preflight(frozen, provider_get("ollama")),
                     class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "changed", fixed = TRUE)
  expect_identical(provider_preflight(model_resolve("ollama/qwen3:1.7b"),
                                      provider_get("ollama"))$digest, strrep("4", 64))
})

test_that("only the protected safety record relaxes local-only; settings and models cannot", {
  local_catalog()
  srv = local_ollama_server()
  gptr_models(provider = "ollama", refresh = TRUE)
  n = length(srv$calls)
  p = provider_get("ollama")
  cloud = model_resolve("ollama/gpt-oss:120b-cloud")
  local_settings(providers = list(ollama = list(local_only = FALSE)))
  expect_error(provider_preflight(cloud, provider_get("ollama")), class = "gptr_error_untrusted")
  expect_error(provider_preflight(cloud, p, safety = list()), class = "gptr_error_untrusted")
  claimed = cloud
  claimed$remote_host = NULL
  claimed$remote_model = NULL
  claimed$locality = "local"
  claimed$local_only = FALSE
  expect_error(provider_preflight(claimed, p), class = "gptr_error_untrusted")
  relaxed = provider_preflight(cloud, p, safety = list(ollama_local_only = FALSE))
  expect_identical(relaxed$locality, "remote")
  expect_true(relaxed$tool_call)
  expect_equal(nrow(relaxed$prices), 0L)
  for (bad in list(NA, "false", c(FALSE, FALSE), 0L)) {
    expect_error(provider_preflight(cloud, p, safety = list(ollama_local_only = bad)),
                 class = "gptr_error_invalid_argument")
  }
  expect_error(provider_preflight(cloud, p, safety = "off"),
               class = "gptr_error_invalid_argument")
  expect_length(srv$calls, n)
})

test_that("model_prepare() discovers only missing or stale evidence and fails before egress", {
  local_catalog()
  srv = local_ollama_server()
  root = "http://127.0.0.1:11434"
  m = model_prepare("ollama/qwen3:1.7b")
  expect_identical(srv$calls, c(paste0("GET ", root, c("/api/version", "/api/tags")),
                                paste0("POST ", root, "/api/show")))
  expect_identical(m$locality, "local")
  expect_identical(m$digest, strrep("1", 64))
  expect_identical(m$server_version, "0.35.1")
  expect_true(m$tool_call)
  n = length(srv$calls)
  expect_identical(model_prepare("ollama/qwen3:1.7b")$ref, "ollama/qwen3:1.7b")
  expect_identical(model_prepare("sonnet")$ref, "anthropic/claude-sonnet-5-5")
  expect_length(srv$calls, n)
  err = expect_error(model_prepare("ollama/llama3.2:3b"), class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "ollama pull llama3.2:3b", fixed = TRUE)
  catalog_reset(discovered = TRUE)
  srv$down = TRUE
  err = expect_error(model_prepare("ollama/qwen3:1.7b"), class = "gptr_error_network")
  expect_match(conditionMessage(err), "ollama serve", fixed = TRUE)
  srv$down = FALSE
  local({
    local_mocked_bindings(check_running = function() TRUE)
    n = length(srv$calls)
    expect_error(model_prepare("ollama/qwen3:1.7b"), class = "gptr_error_not_available")
    expect_length(srv$calls, n)
  })
  local({
    local_settings(providers = list(ollama = list(base_url = "http://192.0.2.10:11434/v1")))
    n = length(srv$calls)
    expect_error(model_prepare("ollama/qwen3:1.7b"), class = "gptr_error_untrusted")
    expect_error(gptr_models(provider = "ollama", refresh = TRUE),
                 class = "gptr_error_untrusted")
    expect_length(srv$calls, n)
    remote = model_prepare("ollama/qwen3:1.7b", safety = list(ollama_local_only = FALSE))
    expect_identical(remote$locality, "remote")
    expect_identical(srv$calls[[n + 1L]], "GET http://192.0.2.10:11434/api/version")
  })
})

test_that("model_default('system1') uses a verified local classifier without discovering", {
  local_catalog()
  srv = local_ollama_server()
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  expect_null(model_default("system1"))
  expect_length(srv$calls, 0L)
  gptr_models(provider = "ollama", refresh = TRUE)
  n = length(srv$calls)
  expect_identical(model_default("system1"), "ollama/clef-flash:latest")
  expect_length(srv$calls, n)
  # a provider disabled in the settings is no default route, verified or not
  local({
    local_settings(providers = list(ollama = list(enabled = FALSE)))
    expect_false(provider_get("ollama")$enabled)
    expect_null(model_default("system1"))
  })
  expect_identical(model_default("system1"), "ollama/clef-flash:latest")
  srv$version = "0.35.0"
  gptr_models(provider = "ollama", refresh = TRUE)
  expect_null(model_default("system1"))
  local_mocked_bindings(model_key_present = function(id, vars) identical(id, "typesafe"))
  expect_identical(model_default("system1"), "typesafe/jev-latest")
})

test_that("a bare catalog name prepared through its :latest evidence costs nothing locally", {
  # the shipped snapshot describes ollama/clef-flash by its bare name (no price, no locality)
  bare = list(provider = "ollama", id = "clef-flash", name = "Clef Flash", family = "clef",
              type = "classifier", api = "ollama-system-one", locality = "unknown",
              reasoning = FALSE, thinking_levels = list("off"), input = list("text", "image"),
              tool_call = FALSE, structured_output = TRUE, status = "active",
              decision = list(types = list("noul", "choice", "score"), images = TRUE,
                              server_min = "0.35.1", max_active = 1L))
  local_catalog(c(fx_models(), list(bare)))
  srv = local_ollama_server()
  usage = usage_new(input = 100, output = 2)
  expect_equal(nrow(model_resolve("ollama/clef-flash")$prices), 0L)
  m = model_prepare("ollama/clef-flash")
  expect_identical(m$ref, "ollama/clef-flash")
  expect_identical(m$locality, "local")
  expect_identical(m$digest, strrep("2", 64))
  expect_identical(usage_cost(usage, m)$cost$total, 0)
  tagged = model_prepare("ollama/clef-flash:latest")
  expect_identical(usage_cost(usage, tagged)$cost$total, 0)
  expect_identical(m$prices, tagged$prices)
  # the same evidence reached through a full listing
  catalog_reset(discovered = TRUE)
  gptr_models(provider = "ollama", refresh = TRUE)
  n = length(srv$calls)
  checked = provider_preflight(model_resolve("ollama/clef-flash"), provider_get("ollama"))
  expect_identical(usage_cost(usage, checked)$cost$total, 0)
  expect_length(srv$calls, n)
})

test_that("usage rows price a bare local model through the same evidence (P05 Task 9)", {
  # IC-74 (07 section 5): local usage records a zero metered API charge. The row applies the
  # request's pure preflight to the resolved record; without current evidence it stays unknown.
  bare = list(provider = "ollama", id = "clef-flash", name = "Clef Flash", family = "clef",
              type = "classifier", api = "ollama-system-one", locality = "unknown",
              reasoning = FALSE, thinking_levels = list("off"), input = list("text", "image"),
              tool_call = FALSE, structured_output = TRUE, status = "active",
              decision = list(types = list("noul", "choice", "score"), images = TRUE,
                              server_min = "0.35.1", max_active = 1L))
  local_catalog(c(fx_models(), list(bare)))
  srv = local_ollama_server()
  started = as.POSIXct("2026-09-30 12:00:00", tz = "UTC")
  row = function(m) {
    msg = msg_assistant(list(), api = m$api, provider = m$provider, model = m$id,
                        usage = usage_new(input = 100, output = 2), route = "system-one")
    usage_row(msg, NA_character_, "s1", NA_character_, started, 0.2, 1)
  }
  unprepared = row(model_resolve("ollama/clef-flash"))
  expect_true(is.na(unprepared$cost))
  expect_true(is.na(unprepared$tier))
  m = model_prepare("ollama/clef-flash")
  n = length(srv$calls)
  local = row(m)
  expect_identical(local$model, "clef-flash")
  expect_identical(local$cost, 0)
  expect_identical(local$tier, "default")
  expect_identical(row(model_prepare("ollama/clef-flash:latest"))$cost, 0)
  expect_length(srv$calls, n)
  # a cloud model behind the same loopback server is not local: its cost stays unknown
  gptr_models(provider = "ollama", refresh = TRUE)
  n = length(srv$calls)
  cloud = row(model_resolve("ollama/gpt-oss:120b-cloud"))
  expect_true(is.na(cloud$cost))
  expect_length(srv$calls, n)
  # without current evidence (a rebuild or replay) the zero is never borrowed
  catalog_reset(discovered = TRUE)
  expect_true(is.na(row(m)$cost))
  expect_length(srv$calls, n)
})

test_that("a model /api/show cannot describe does not hide the others or blame the server", {
  local_catalog()
  srv = local_ollama_server()
  srv$slow = "clef-flash:latest"
  found = gptr_models(provider = "ollama", refresh = TRUE)
  expect_setequal(found$ref, c("ollama/qwen3:1.7b", "ollama/gpt-oss:120b-cloud"))
  expect_length(srv$calls, 5L)
  expect_null(model_default("system1"))
  catalog_reset(discovered = TRUE)
  err = expect_error(model_prepare("ollama/clef-flash"), class = "gptr_error_network")
  expect_match(conditionMessage(err), "/api/show", fixed = TRUE)
  expect_match(conditionMessage(err), "clef-flash:latest", fixed = TRUE)
  expect_false(grepl("ollama serve", conditionMessage(err), fixed = TRUE))
  expect_identical(err$curl_code, 28L)
  expect_identical(model_prepare("ollama/qwen3:1.7b")$locality, "local")
  # a server that stops answering after /api/tags lists nothing and names /api/show
  catalog_reset(discovered = TRUE)
  srv$slow = names(ollama_fixture())
  err = expect_error(gptr_models(provider = "ollama", refresh = TRUE),
                     class = "gptr_error_network")
  expect_match(conditionMessage(err), "/api/show", fixed = TRUE)
})
