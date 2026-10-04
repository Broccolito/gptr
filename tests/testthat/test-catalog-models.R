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
  vault_reset()
  withr::defer(vault_reset())
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
