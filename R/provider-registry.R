# Provider records as data, credentials, the provider_stream() glue and gptr_providers() (P05).
# Contract: dev/spec/04-interface-contract.md sections 6.2 (gptr_providers()), 7.5, 8.1, 8.4 and
# 10.2 row 1; architecture sections 8.1 and 6.5; IC-08 (builtin:fake declared here), IC-33
# (opts$gate, opts$mcp_dispatch and opts$tool_result are injected, never looked up by an
# adapter), IC-45 (offline), IC-64 (rate), IC-65 (check = FALSE spawns nothing).
# Provider table: architecture section 8.1 and report 09 section 3.5 (base URLs, key variables);
# compat flags are the snake_case form of Pi's OpenAICompletionsCompat (report 09 section 3.3,
# section 4.6). Credential order: report 03 section 4.5 as amended by G6 section 4.5.

on_load(ext_declare_builtin("fake", builtin_fake))
on_load(ext_declare_builtin("providers", builtin_providers))

#' Compat defaults shared by the loopback OpenAI-compatible servers (report 09 section 4.6)
#' @noRd
provider_local_compat = function() {
  list(supports_store = FALSE, supports_developer_role = FALSE,
       supports_reasoning_effort = FALSE, supports_strict_mode = FALSE,
       max_tokens_field = "max_tokens", image_mode = "base64")
}

#' The built-in provider records of architecture section 8.1, as gptr_provider() arguments
#'
#' `typesafe` (section 8.2) is registered by P13's builtin:system1 (04 section 7.13) and the
#' plan routes `claude-cli` and `codex` by P20's builtin:cli (04 section 7.20).
#' @noRd
provider_table = function() {
  local = provider_local_compat()
  list(
    list(id = "anthropic", api = "anthropic-messages", base_url = "https://api.anthropic.com",
         auth = "ANTHROPIC_API_KEY"),
    list(id = "openai", api = "openai-responses", base_url = "https://api.openai.com/v1",
         auth = "OPENAI_API_KEY"),
    list(id = "google", api = "google-generative-ai",
         base_url = "https://generativelanguage.googleapis.com/v1beta",
         auth = c("GEMINI_API_KEY", "GOOGLE_API_KEY")),
    list(id = "openrouter", api = "openai-completions", base_url = "https://openrouter.ai/api/v1",
         auth = "OPENROUTER_API_KEY",
         compat = list(thinking_format = "openrouter", supports_developer_role = FALSE,
                       cache_control_format = "anthropic", session_affinity = "openrouter"),
         headers = list(`HTTP-Referer` = "https://cran.r-project.org/package=gptr",
                        `X-OpenRouter-Title` = "gptr")),
    list(id = "groq", api = "openai-completions", base_url = "https://api.groq.com/openai/v1",
         auth = "GROQ_API_KEY", compat = list(requires_tool_result_name = FALSE)),
    list(id = "deepseek", api = "openai-completions", base_url = "https://api.deepseek.com",
         auth = "DEEPSEEK_API_KEY",
         compat = list(thinking_format = "deepseek", max_tokens_field = "max_tokens",
                       requires_reasoning_content = TRUE, supports_store = FALSE,
                       supports_developer_role = FALSE)),
    list(id = "mistral", api = "openai-completions", base_url = "https://api.mistral.ai/v1",
         auth = "MISTRAL_API_KEY",
         compat = list(tool_id = "alnum9", thinking_in_content = TRUE, supports_store = FALSE)),
    list(id = "together", api = "openai-completions", base_url = "https://api.together.ai/v1",
         auth = "TOGETHER_API_KEY",
         compat = list(thinking_format = "together", max_tokens_field = "max_tokens",
                       supports_store = FALSE, supports_developer_role = FALSE,
                       supports_reasoning_effort = FALSE, think_tags = TRUE)),
    list(id = "xai", api = "openai-completions", base_url = "https://api.x.ai/v1",
         auth = "XAI_API_KEY",
         compat = list(supports_store = FALSE, supports_developer_role = FALSE,
                       supports_reasoning_effort = FALSE)),
    list(id = "cerebras", api = "openai-completions", base_url = "https://api.cerebras.ai/v1",
         auth = "CEREBRAS_API_KEY",
         compat = list(supports_store = FALSE, supports_developer_role = FALSE,
                       image_mode = "base64")),
    list(id = "fireworks", api = "openai-completions",
         base_url = "https://api.fireworks.ai/inference/v1", auth = "FIREWORKS_API_KEY"),
    list(id = "ollama", api = "openai-completions", base_url = "http://127.0.0.1:11434/v1",
         auth = NULL, local = TRUE, discover = provider_ollama_discoverer("ollama"),
         compat = utils::modifyList(local, list(supports_reasoning_effort = TRUE,
                                                supports_tool_choice = FALSE))),
    list(id = "lmstudio", api = "openai-completions", base_url = "http://localhost:1234/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("lmstudio"), compat = local),
    list(id = "llamacpp", api = "openai-completions", base_url = "http://127.0.0.1:8080/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("llamacpp"), compat = local),
    list(id = "vllm", api = "openai-completions", base_url = "http://localhost:8000/v1",
         auth = provider_optional_auth("vllm", "VLLM_API_KEY"), local = TRUE,
         discover = provider_discoverer("vllm"),
         compat = utils::modifyList(local, list(supports_reasoning_effort = TRUE))),
    list(id = "azure", api = "openai-completions", base_url = NULL, auth = "AZURE_OPENAI_API_KEY",
         compat = list(auth_header = "api-key", deployment_model = TRUE,
                       base_url_env = "AZURE_OPENAI_ENDPOINT",
                       base_url_template = "{value}/openai/v1")),
    list(id = "bedrock", api = "openai-completions", base_url = NULL,
         auth = "AWS_BEARER_TOKEN_BEDROCK",
         compat = list(
           base_url_env = c("AWS_REGION", "AWS_DEFAULT_REGION"), base_url_default = "us-east-1",
           base_url_template = "https://bedrock-runtime.{value}.amazonaws.com/openai/v1"
         ))
  )
}

#' Default model id per built-in provider (architecture section 8.4)
#' @noRd
provider_default_models = function() {
  c(anthropic = "claude-sonnet-5-5", openai = "gpt-6-sol", google = "gemini-3.8-flash")
}

#' An `auth` function for an optional key (vLLM): a bound handle when the key exists, else NULL
#' @noRd
provider_optional_auth = function(id, vars) {
  force(id)
  force(vars)
  function() {
    p = provider_get(id)
    if (is.null(p)) return(NULL)
    p[["auth"]] = vars
    tryCatch(provider_credential(p), gptr_error_no_key = function(e) NULL)
  }
}

#' A `discover` function for a loopback server: GET <base>/models with a 1 s timeout
#'
#' Runs only on request (gptr_models(refresh = TRUE, provider = <id>)), never at load and
#' never under R CMD check (report 09 section 4.6).
#' @noRd
provider_discoverer = function(id) {
  force(id)
  function() {
    if (check_running()) return(NULL)
    p = provider_get(id)
    url = if (is.null(p)) NULL else provider_base_url(p)
    if (is.null(url)) return(NULL)
    res = tryCatch(catalog_http_get(paste0(url, "/models"), timeout = 1),
                   gptr_error = function(e) NULL)
    if (is.null(res) || !identical(res$status, 200L)) return(NULL)
    body = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
    ids = vapply(body[["data"]] %||% list(), function(m) as.character(m[["id"]] %||% ""), "")
    data.frame(id = ids[nzchar(ids)], stringsAsFactors = FALSE)
  }
}

#' The `discover` function of the Ollama record: P05's native discovery (07-local-ollama.md
#' section 2; /api/version, /api/tags and /api/show of the record's own endpoint)
#'
#' Runs only on request, never at load and never under R CMD check; returns the listed ids.
#' gptr_models(refresh = TRUE) and model_prepare() call catalog_ollama_discover() directly, so a
#' replaced `discover` function can never supply the private evidence preflight accepts.
#' @noRd
provider_ollama_discoverer = function(id) {
  force(id)
  function() {
    p = provider_get(id)
    if (is.null(p)) return(NULL)
    data.frame(id = catalog_ollama_discover(p), stringsAsFactors = FALSE)
  }
}

#' builtin:providers: registers the provider records of architecture section 8.1 as data
#' @noRd
builtin_providers = function(gptr) {
  for (row in provider_table()) gptr$register(do.call(gptr_provider, row))
  invisible(NULL)
}

#' The settings entry `providers.<id>` (`base_url`, `models`, `headers`, `enabled`; 04 section
#' 11.2), or an empty list
#' @noRd
provider_settings = function(id) {
  cfg = setting_get("providers", default = list()) %||% list()
  s = if (is.list(cfg) && is.character(id) && length(id) == 1L) cfg[[id]] else NULL
  if (is.list(s)) s else list()
}

#' A provider record with its settings applied: extra non-secret `headers` (single strings
#' only) are merged over the record's, and `enabled` is `FALSE` only when the settings say so
#' @noRd
provider_effective = function(p) {
  if (is.null(p)) return(NULL)
  s = provider_settings(p[["id"]] %||% p[["name"]])
  h = s[["headers"]]
  check_list(h, "provider headers", named = TRUE, null = TRUE)
  if (length(h)) {
    token = "\\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\\z"
    if (any(!grepl(token, names(h), perl = TRUE)) || anyDuplicated(tolower(names(h)))) {
      arg_abort(h, "provider headers", "a list with unique HTTP header names")
    }
    hs = p[["headers"]] %||% list()
    for (k in names(h)) {
      v = h[[k]]
      if (is.character(v) && length(v) == 1L && !is.na(v)) {
        hs = hs[tolower(names(hs)) != tolower(k)]
        hs[[k]] = v
      }
    }
    p[["headers"]] = hs
  }
  p[["enabled"]] = !isFALSE(s[["enabled"]])
  p
}

#' The provider spec registered as `id` (or under that alias), with its settings applied; NULL
#' when none
#' @noRd
provider_get = function(id) {
  check_string(id, "id")
  p = registry_get("provider", id)
  if (!is.null(p)) return(provider_effective(p))
  for (nm in registry_names("provider")) {
    q = registry_get("provider", nm)
    if (id %in% (q[["aliases"]] %||% character())) return(provider_effective(q))
  }
  NULL
}

#' The plan that provides a built-in adapter (for the not_available condition)
#' @noRd
adapter_provided_by = function(api) {
  switch(api,
         "anthropic-messages" = , "openai-responses" = , "openai-completions" = ,
         "google-generative-ai" = "P12",
         "typesafe-system-one" = , "ollama-system-one" = , "s1-emulate" = "P13",
         "cli-claude" = , "cli-codex" = "P20",
         "fake" = , "fake-classifier" = "P01",
         "a plugin")
}

#' The adapter spec registered for a wire api, or gptr_error_not_available
#' @noRd
adapter_get = function(api) {
  check_string(api, "api")
  a = registry_get("adapter", api)
  if (is.null(a)) {
    gptr_abort(paste0("No adapter is registered for the api ", api, "."), "not_available",
               member = api, provided_by = adapter_provided_by(api))
  }
  a
}

#' The configured base URL of a provider (settings > record > environment template)
#' @noRd
provider_base_url = function(provider) {
  id = provider[["id"]] %||% provider[["name"]]
  url = provider_settings(id)[["base_url"]]
  if (!is.character(url) || length(url) != 1L || is.na(url)) url = NULL
  if (is.null(url) || !nzchar(url)) url = provider[["base_url"]]
  if (is.null(url) || !nzchar(url)) {
    comp = provider[["compat"]] %||% list()
    vars = comp[["base_url_env"]]
    if (length(vars)) {
      vals = Sys.getenv(vars, unset = "")
      vals = vals[nzchar(vals)]
      val = sub("/+$", "", if (length(vals)) vals[[1]] else comp[["base_url_default"]] %||% "")
      tmpl = comp[["base_url_template"]]
      if (nzchar(val)) {
        suffix = if (is.null(tmpl)) "" else sub("^\\{value\\}", "", tmpl)
        url = if (is.null(tmpl) || (nzchar(suffix) && endsWith(val, suffix))) {
          val
        } else {
          gsub("{value}", val, tmpl, fixed = TRUE)
        }
      }
    }
  }
  if (is.null(url) || !nzchar(url)) NULL else sub("/+$", "", url)
}

#' The origin (scheme, host and non-default port) using the transport's URL normalization
#' @noRd
provider_origin = function(url) {
  origin = url_origin(url)
  if (is.na(origin)) NULL else origin
}

#' Is a handle usable for a provider origin (unbound, or bound to the same origin)?
#'
#' P03 stores bound origins in canonical form with the port (`https://api.anthropic.com:443`),
#' so the bound origin passes provider_origin() before the comparison.
#' @noRd
credential_usable = function(h, origin) {
  origin = provider_origin(origin)
  if (is.null(origin) || !inherits(h, "gptr_secret") || !is.list(h)) return(FALSE)
  id = h[["id"]]
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(FALSE)
  st = the$secrets
  entry = if (is.environment(st)) st$reg[[id]] else NULL
  if (!is.list(entry) || !identical(entry[["id"]], id)) return(FALSE)
  stored = entry[["origin"]]
  # A mutable handle may narrow an unbound credential; it cannot replace the vault's
  # independent origin restriction. Inspect metadata only, never the secret value.
  bounds = list(h[["origin"]], stored)
  all(vapply(bounds, function(bound) {
    is.null(bound) || identical(provider_origin(bound), origin)
  }, NA))
}

#' Bind a handle to the provider origin (contract section 7.5: "a handle bound to the provider's
#' configured origin")
#'
#' An unbound handle (ambient discovery, a vault-only `.env` value, a credential-store record, an
#' `auth` function's result) gets the provider origin in its own `origin` field, which P03's
#' secret_value() checks before the origin of the vault entry (P03 plan, Task 1: "how P05 binds
#' a looked-up handle"); the vault entry itself stays as it is for other consumers. A handle that
#' is already bound is returned unchanged; provider_credential() never uses one that is bound to
#' another origin. P05 never sees the value.
#' @noRd
credential_bind = function(h, origin) {
  if (is.null(origin) || !inherits(h, "gptr_secret") || !is.null(h[["origin"]])) return(h)
  h[["origin"]] = origin
  h
}

#' A handle from a credential-store record (P03 returns handles for stored values)
#' @noRd
credential_from_store = function(rec, name, origin) {
  if (is.null(rec)) return(NULL)
  if (inherits(rec, "gptr_secret")) return(rec)
  for (k in c("handle", "key")) {
    v = rec[[k]]
    if (inherits(v, "gptr_secret")) return(v)
  }
  key = rec[["key"]]
  if (is.character(key) && length(key) == 1L && nzchar(key)) {
    return(credential_register(key, name, "store", origin))
  }
  NULL
}

#' Register an ambient value without overwriting an existing origin restriction
#' @noRd
credential_register = function(value, name, source, origin) {
  h = secret_register(value, name, source = source)
  if (!credential_usable(h, origin)) return(NULL)
  # Only compatible registrations may acquire a persistent origin restriction.
  # This also prevents an unchanged environment value following endpoint edits.
  secret_register(value, name, source = source, origin = origin)
}

#' The credential handle of a provider (contract section 7.5)
#'
#' Order (architecture section 8): an explicit `auth` function > the vault (gptr_env(), ambient
#' discovery) > the credential store (gptr_login(); keyring references are resolved by P03) >
#' the provider's environment variables, registered at once and bound to the provider's origin.
#' NULL for providers without auth; gptr_error_no_key otherwise. Never returns a value. The
#' anthropic provider refuses a subscription OAuth token (`sk-ant-oat`, architecture section
#' 8.1) found in its variable, and the vault handle holding the same token: gptr_error_no_key
#' naming the token type when nothing else is found.
#' @noRd
provider_credential = function(provider) {
  if (is.null(provider)) return(NULL)
  id = provider[["id"]] %||% provider[["name"]]
  auth = provider[["auth"]]
  if (is.null(auth) || isTRUE(provider[["offline"]])) return(NULL)
  origin = provider_origin(provider_base_url(provider))
  if (is.null(origin)) {
    gptr_abort(paste0("Provider ", id, " needs a valid configured origin before credentials ",
                      "can be bound."), "no_key", provider = id, variables = character())
  }
  if (is.function(auth)) {
    h = auth()
    if (is.null(h)) return(NULL)
    if (inherits(h, "gptr_secret")) {
      if (credential_usable(h, origin)) return(credential_bind(h, origin))
      gptr_abort(paste0("The auth function of provider ", id,
                        " returned a credential unavailable for its configured origin."),
                 "no_key", provider = id, variables = character())
    }
    gptr_abort(paste0("The auth function of provider ", id, " returned no secret handle."),
               "invalid_spec", kind = "provider", name = id, field = "auth",
               problem = "auth() must return a gptr_secret handle or NULL")
  }
  vars = as.character(auth)
  # Architecture section 8.1: the anthropic provider refuses Claude subscription OAuth tokens
  # (sk-ant-oat...). Their fingerprints (P03: the first 6 hex of hash_sha256(value)) mark the
  # vault handles that hold the same token (ambient discovery registers the environment's
  # values); a token that exists only in the vault cannot be recognised here (ambiguity 8).
  refused = character()
  if (identical(id, "anthropic")) {
    for (v in vars) {
      value = Sys.getenv(v, unset = "")
      if (startsWith(value, "sk-ant-oat")) refused[[v]] = substr(hash_sha256(value), 1L, 6L)
    }
  }
  for (v in vars) {
    h = secret_lookup(v)
    if (v %in% names(refused) && identical(h[["fp"]], refused[[v]])) next
    if (credential_usable(h, origin)) return(credential_bind(h, origin))
  }
  rec = tryCatch(auth_store_get(id), gptr_error = function(e) NULL)
  h = credential_from_store(rec, vars[[1]], origin)
  if (credential_usable(h, origin)) return(credential_bind(h, origin))
  for (v in vars) {
    if (v %in% names(refused)) next
    value = Sys.getenv(v, unset = "")
    if (nzchar(value)) {
      h = credential_register(value, v, "env", origin)
      if (!is.null(h)) return(h)
    }
  }
  if (length(refused)) {
    gptr_abort(paste0(names(refused)[[1]], " holds a Claude subscription OAuth token ",
                      "(sk-ant-oat...), which the API provider refuses; use an API key, or ",
                      "model = \"claude_code\" for the subscription CLI."),
               "no_key", provider = id, variables = vars)
  }
  gptr_abort(paste0("No credential found for provider ", id, ". Set ",
                    paste(vars, collapse = " or "),
                    " (for example with gptr_env()) or store one with gptr_login()."),
             "no_key", provider = id, variables = vars)
}
