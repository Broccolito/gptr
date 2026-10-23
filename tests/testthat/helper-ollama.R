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
