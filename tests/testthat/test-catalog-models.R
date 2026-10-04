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
