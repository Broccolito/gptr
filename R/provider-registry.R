# Provider records as data, credentials, the provider_stream() glue and gptr_providers() (P05;
# contract 6.2, 7.5, 8.1, 8.4, 10.2; architecture 6.5, 8.1). IC-08 (builtin:fake declared here),
# IC-33 (callbacks injected, never looked up), IC-45, IC-64, IC-65. Compat flags are Pi's
# OpenAICompletionsCompat in snake_case (report 09 3.3); credential order per G6 section 4.5.

on_load(ext_declare_builtin("fake", builtin_fake))
on_load(ext_declare_builtin("providers", builtin_providers))

#' The built-in provider records of architecture section 8.1, as gptr_provider() arguments
#' (`typesafe` is P13's builtin:system1; `claude-cli` and `codex` are P20's builtin:cli)
#' @noRd
provider_table = function() {
  list(
    list(id = "anthropic", api = "anthropic-messages", base_url = "https://api.anthropic.com",
         auth = "ANTHROPIC_API_KEY"),
    list(id = "openai", api = "openai-responses", base_url = "https://api.openai.com/v1",
         auth = "OPENAI_API_KEY", compat = list(explicit_cache_mode = TRUE)),
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
         compat = list(tool_id = "alnum9", thinking_in_content = TRUE, supports_store = FALSE,
                       supports_developer_role = FALSE)),
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
         base_url = "https://api.fireworks.ai/inference/v1", auth = "FIREWORKS_API_KEY",
         compat = list(supports_store = FALSE, supports_developer_role = FALSE)),
    list(id = "ollama", api = "openai-completions", base_url = "http://127.0.0.1:11434/v1",
         auth = NULL, local = TRUE, discover = provider_ollama_discoverer("ollama"),
         compat = list(supports_reasoning_effort = TRUE, supports_tool_choice = FALSE)),
    list(id = "lmstudio", api = "openai-completions", base_url = "http://localhost:1234/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("lmstudio")),
    list(id = "llamacpp", api = "openai-completions", base_url = "http://127.0.0.1:8080/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("llamacpp")),
    list(id = "vllm", api = "openai-completions", base_url = "http://localhost:8000/v1",
         auth = provider_optional_auth("vllm", "VLLM_API_KEY"), local = TRUE,
         discover = provider_discoverer("vllm"),
         compat = list(supports_reasoning_effort = TRUE)),
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
#' Its `gptr_optional_auth` attribute names the variables for the read-only listing.
#' @noRd
provider_optional_auth = function(id, vars) {
  force(id)
  force(vars)
  structure(function() {
    p = provider_get(id)
    if (is.null(p)) return(NULL)
    p[["auth"]] = vars
    tryCatch(provider_credential(p), gptr_error_no_key = function(e) NULL)
  }, gptr_optional_auth = vars)
}

#' A `discover` function for a loopback server: GET <base>/models with a 1 s timeout
#' Runs only on request (gptr_models(refresh = TRUE)), never at load or under R CMD check.
#' @noRd
provider_discoverer = function(id) {
  force(id)
  function() {
    if (check_running()) return(NULL)
    p = provider_get(id)
    url = if (is.null(p)) NULL else provider_base_url(p)
    if (is.null(url)) return(NULL)
    res = tryCatch(catalog_http_request(paste0(url, "/models"), timeout = 1),
                   gptr_error = function(e) NULL)
    if (is.null(res) || !identical(res$status, 200L)) return(NULL)
    body = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
    ids = vapply(body[["data"]] %||% list(), function(m) as.character(m[["id"]] %||% ""), "")
    data.frame(id = ids[nzchar(ids)], stringsAsFactors = FALSE)
  }
}

#' The `discover` function of the Ollama record: native discovery (07 section 2), on request only
#' gptr_models() and model_prepare() call catalog_ollama_discover() directly, so a replaced
#' `discover` can never supply the private evidence preflight accepts.
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
#' P03 stores bound origins canonically with the port, so both pass provider_origin().
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

#' Bind a handle to the provider origin (contract section 7.5)
#' An unbound handle gets the origin in its own `origin` field (checked by P03's secret_value());
#' a bound handle is returned unchanged. P05 never sees the value.
#' @noRd
credential_bind = function(h, origin) {
  if (is.null(origin) || !inherits(h, "gptr_secret") || !is.null(h[["origin"]])) return(h)
  h[["origin"]] = origin
  h
}

#' A handle from a credential-store record (P03 returns handles for stored values)
#' @noRd
credential_from_store = function(rec, name, origin, register = TRUE) {
  if (is.null(rec)) return(NULL)
  if (inherits(rec, "gptr_secret")) return(rec)
  for (k in c("handle", "key")) {
    v = rec[[k]]
    if (inherits(v, "gptr_secret")) return(v)
  }
  key = rec[["key"]]
  if (is.character(key) && length(key) == 1L && nzchar(key)) {
    if (!register) return(credential_peek(key, name, origin))
    return(credential_register(key, name, "store", origin))
  }
  NULL
}

#' What credential_register() would yield, without registering or binding (the listing's view)
#' NULL when the vault holds `name` bound to another origin; else a `gptr_credential_peek`
#' record (name and P03 fingerprint), never the value.
#' @noRd
credential_peek = function(value, name, origin) {
  fp = substr(hash_sha256(as_utf8(value)), 1L, 6L)
  st = the$secrets
  entry = if (is.environment(st)) st$reg[[paste0(name, "#", fp)]] else NULL
  if (is.list(entry)) {
    h = structure(list(id = entry[["id"]], name = name, fp = fp, origin = entry[["origin"]]),
                  class = "gptr_secret")
    if (!credential_usable(h, origin)) return(NULL)
  }
  structure(list(name = name, fp = fp), class = "gptr_credential_peek")
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

#' The credential handle of a provider (contract section 7.5; architecture section 8)
#' Order: `auth` function > vault > credential store > environment (registered, origin-bound);
#' never a value. `register = FALSE` (the listing) peeks without registering or binding.
#' @noRd
provider_credential = function(provider, register = TRUE) {
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
    optional = attr(auth, "gptr_optional_auth", exact = TRUE)
    if (!register && is.character(optional)) {
      provider[["auth"]] = optional
      return(tryCatch(provider_credential(provider, register = FALSE),
                      gptr_error_no_key = function(e) NULL))
    }
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
  # Architecture 8.1: anthropic refuses subscription OAuth tokens (sk-ant-oat...); their P03
  # fingerprints mark vault handles holding the same token (ambiguity 8)
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
  h = credential_from_store(rec, vars[[1]], origin, register)
  if (inherits(h, "gptr_credential_peek")) return(h)
  if (credential_usable(h, origin)) return(credential_bind(h, origin))
  for (v in vars) {
    if (v %in% names(refused)) next
    value = Sys.getenv(v, unset = "")
    if (nzchar(value)) {
      h = if (register) {
        credential_register(value, v, "env", origin)
      } else {
        credential_peek(value, v, origin)
      }
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

# ---- provider_stream(): the glue between the reactor and the adapters (04 sections 8.1, 8.4) ---

#' A classed, unsignalled condition for stream failures (04 section 2.2), redacted like any
#' gptr condition (an adapter's error text may quote a request)
#' @noRd
stream_condition = function(message, class, ...) {
  gptr_condition(message, class, "error", list(...))
}

#' The route of a model's messages (contract section 4.2)
#' @noRd
stream_route = function(model) {
  switch(model[["type"]] %||% "chat", cli = "plan-cli", classifier = "system-one", "api")
}

#' Fail-closed defaults for the callbacks provider_stream() injects (IC-33)
#' @noRd
stream_gate_closed = function(call) {
  list(decision = "deny", reason = "No permission gate is attached to this model stream.")
}

#' The default tool-result builder (P06 passes tool_result_message() in `opts` instead)
#' @noRd
stream_tool_result = function(result, call) {
  content = result[["content"]] %||% list(block_text("(no output)"))
  msg_tool_result(call[["id"]], call[["name"]], content, is_error = isTRUE(result[["is_error"]]),
                  details = result[["details"]])
}

#' The MCP dispatcher bound to a session (the mcp.dispatch_local service of P18)
#' @noRd
stream_mcp_dispatch = function(session) {
  force(session)
  function(message) {
    if (!ext_service_has("mcp.dispatch_local")) {
      return(list(jsonrpc = "2.0", id = message[["id"]],
                  error = list(code = -32601L, message = "gptr's MCP dispatcher is not loaded")))
    }
    ext_service_get("mcp.dispatch_local")(message, session)
  }
}

#' Diagnostics for callback errors that must not escape a stream
#' @noRd
stream_diagnostic = function(event, e) {
  tryCatch(registry_diagnostic("provider_stream", event, class(e)[[1]], conditionMessage(e)),
           error = function(e2) NULL)
  invisible(NULL)
}

#' Fill the request id an adapter cannot know (04 section 4.5: start, error and the message
#' carry it; P12's normalisers emit NULL); an id the adapter set is kept
#' @noRd
stream_request_id = function(st, ev, type) {
  rid = st$context[["request_id"]]
  if (is.null(rid)) return(ev)
  if (identical(type, "start")) ev[["request_id"]] = ev[["request_id"]] %||% rid
  if (identical(type, "error") && is.list(ev[["error"]])) {
    err = ev[["error"]]
    err[["request_id"]] = err[["request_id"]] %||% rid
    ev[["error"]] = err
  }
  if (type %in% c("done", "error") && is.list(ev[["message"]])) {
    ev[["message"]][["request_id"]] = ev[["message"]][["request_id"]] %||% rid
  }
  ev
}

#' Emit one event: at most one start, the request id, commit tracking, terminal detection
#' @noRd
stream_emit = function(st, ev) {
  if (st$finished) return(invisible(NULL))
  type = ev[["type"]] %||% ""
  if (identical(type, "start")) {
    if (st$started) return(invisible(NULL))
    st$started = TRUE
  }
  ev = stream_request_id(st, ev, type)
  if (endsWith(type, "_delta")) st$committed = TRUE
  tryCatch(st$acc$push(ev), error = function(e) NULL)
  tryCatch(st$emit_cb(ev), error = function(e) stream_diagnostic("emit", e))
  if (type %in% c("done", "error")) stream_finish(st, ev[["message"]])
  invisible(NULL)
}

#' Deliver the final message exactly once (with the request id when the adapter left it out)
#' @noRd
stream_finish = function(st, msg) {
  if (st$finished) return(invisible(FALSE))
  st$finished = TRUE
  rid = st$context[["request_id"]]
  if (is.list(msg) && is.null(msg[["request_id"]]) && !is.null(rid)) msg[["request_id"]] = rid
  tryCatch(st$done_cb(msg), error = function(e) stream_diagnostic("done", e))
  invisible(TRUE)
}

#' The partial message known so far (normaliser, accumulator, or an empty message of the model)
#' Before `start` the accumulator knows no model, so the model record is used.
#' @noRd
stream_partial = function(st) {
  msg = if (is.null(st$norm)) NULL else tryCatch(st$norm$message(), error = function(e) NULL)
  if (!is.list(msg) && st$started) {
    msg = tryCatch(st$acc$message(), error = function(e) NULL)
  }
  if (is.list(msg)) return(msg)
  m = st$model
  msg_assistant(list(), api = m[["api"]] %||% "unknown", provider = m[["provider"]] %||% "unknown",
                model = m[["id"]] %||% "unknown", stop_reason = "error",
                route = stream_route(m), request_id = st$context[["request_id"]])
}

#' End the stream with a transport-level terminal event (setup failure, abort, missing end)
#' @noRd
stream_fail_local = function(st, reason, message, class, status = NA_integer_,
                             retry_after = NULL) {
  if (st$finished) return(invisible(NULL))
  msg = stream_partial(st)
  msg[["stop_reason"]] = reason
  msg[["error_message"]] = message
  ev = ev_new("error", reason = reason, message = msg,
              error = list(class = class, status = status,
                           request_id = st$context[["request_id"]], retry_after = retry_after))
  stream_emit(st, ev)
  if (!st$finished) stream_finish(st, msg)
  invisible(NULL)
}

#' Cancel the stream's transfer, or forget and kill its child (a no-op once P04 forgot the
#' transfer or the turn let go of its child)
#' @noRd
stream_cancel = function(st) {
  if (identical(st$transport, "http") && !is.na(st$id)) {
    tryCatch(reactor_cancel(st$id), error = function(e) NULL)
  }
  if (identical(st$transport, "process")) stream_process_drop(st)
  invisible(NULL)
}

#' Forget and kill the child of a process_jsonl turn the glue ends itself (D-018)
#' Forgotten first: its late output and exit reach no turn, and the next turn starts a new child.
#' @noRd
stream_process_drop = function(st) {
  p = st$process
  if (is.null(p)) return(invisible(FALSE))
  st$process = NULL
  state = st$opts$state
  if (is.environment(state) && identical(state$process, p)) state$process = NULL
  stream_process_kill(p, st$watch, st$job)
  invisible(TRUE)
}

#' Stop a session child the glue lets go of, through P04's watcher; its job row goes too
#' Never kill_all() under a living watcher: it would never see the closed pipes end (no exit,
#' the job row stays). A child without a watcher is killed directly.
#' @noRd
stream_process_kill = function(p, watch, job) {
  n = 0L
  if (is.character(watch)) n = tryCatch(reactor_cancel(watch), error = function(e) 0L)
  if (!isTRUE(n > 0L)) tryCatch(kill_all(p), error = function(e) NULL)
  if (is.character(job)) tryCatch(job_remove(job), error = function(e) NULL)
  invisible(NULL)
}

#' The `stop()` of a session child's job row (gptr_jobs(kill = TRUE), the unload cleanup)
#' A cancelled watcher reports no exit, so the exit reaches the child's last turn from a timer.
#' @noRd
stream_process_stop = function(state, p, watch, job) {
  current = identical(state$process, p)
  f = if (current) state$route_exit else NULL
  if (current) state$process = NULL
  stream_process_kill(p, watch, job)
  if (is.function(f)) {
    reactor_timer(reactor_now(), function() {
      status = tryCatch(p$get_exit_status(), error = function(e) NULL)
      f(if (is.null(status)) NA_integer_ else status)
    })
  }
  invisible(NULL)
}

#' Hand a transport failure to the normaliser (which emits the terminal error event)
#' @noRd
stream_normaliser_fail = function(st, cnd) {
  if (st$finished) return(invisible(NULL))
  if (!is.null(st$norm)) {
    tryCatch(st$norm$fail(cnd), error = function(e) stream_diagnostic("fail", e))
  }
  if (!st$finished) {
    cls = sub("^gptr_error_", "", class(cnd)[[1]])
    stream_fail_local(st, "error", conditionMessage(cnd), cls,
                      status = cnd[["status"]] %||% NA_integer_,
                      retry_after = cnd[["retry_after"]])
  }
  invisible(NULL)
}

#' End the stream for a local failure while its transfer may be live: the normaliser's terminal
#' event, then the transfer is cancelled so it holds no reactor slot
#' @noRd
stream_fail_live = function(st, cnd) {
  stream_normaliser_fail(st, cnd)
  stream_cancel(st)
}

#' A classed condition for an error caught inside the glue (a gptr condition is kept)
#' @noRd
stream_error_condition = function(e, detail) {
  if (inherits(e, "gptr_error")) return(e)
  stream_condition(conditionMessage(e), "internal", detail = detail)
}

#' Push one decoded unit into the normaliser; an error there ends the stream
#' @noRd
stream_push = function(st, unit) {
  if (st$finished) return(invisible(NULL))
  tryCatch(st$norm$push(unit), error = function(e) {
    stream_fail_live(st, stream_condition(conditionMessage(e), "internal",
                                          detail = "adapter normaliser push()"))
  })
  invisible(NULL)
}

#' End of input: the normaliser emits the terminal event (done, or error when truncated)
#' @noRd
stream_normaliser_finish = function(st) {
  if (st$finished) return(invisible(NULL))
  msg = tryCatch(st$norm$finish(), error = function(e) {
    stream_normaliser_fail(st, stream_condition(conditionMessage(e), "internal",
                                                detail = "adapter normaliser finish()"))
    NULL
  })
  if (!st$finished) {
    if (is.list(msg)) {
      stream_finish(st, msg)
    } else {
      stream_fail_local(st, "error", "The stream ended without a terminal event.", "internal")
    }
  }
  invisible(NULL)
}

#' Abort: cancel the transfer or kill the child, then an `aborted` terminal event
#' @noRd
stream_abort = function(st) {
  if (st$finished) return(invisible(NULL))
  stream_cancel(st)
  reason = st$opts$signal$reason %||% "aborted"
  stream_fail_local(st, "aborted", as.character(reason)[[1]], "aborted")
}

#' Has the caller's run settled (a terminal status of contract section 7.6)?
#' @noRd
stream_run_settled = function(run) {
  if (!is.environment(run)) return(FALSE)
  status = run[["status"]]
  is.character(status) && length(status) == 1L &&
    !status %in% c("queued", "requesting", "streaming", "tools", "boundary")
}

#' Let go of a stream whose run settled without it: no more events, no `done`
#' @noRd
stream_detach = function(st) {
  if (st$finished) return(invisible(NULL))
  st$finished = TRUE
  stream_cancel(st)
  st$emit_cb = function(ev) NULL
  st$done_cb = function(msg) NULL
  invisible(NULL)
}

#' Turn `opts$signal$aborted` into stream_abort() and let go of a stream whose run settled;
#' TRUE when the stream is over (it was before, or it ends now)
#' @noRd
stream_over = function(st) {
  if (st$finished) return(TRUE)
  if (isTRUE(st$opts$signal$aborted)) {
    stream_abort(st)
    return(TRUE)
  }
  if (stream_run_settled(st$run)) {
    stream_detach(st)
    return(TRUE)
  }
  FALSE
}

#' A reactor task that runs stream_over() every iteration until the stream is over; returns
#' the task id
#' @noRd
stream_watch = function(st) {
  reactor_task(function() !stream_over(st), run = st$run)
}

#' The retry callback normalisers call for a retryable failure seen inside the stream
#' HTTP goes to P04's reactor_retry() (same spec after backoff while nothing was committed);
#' other transports, or a refused hint, end the stream at once (04 section 8.1).
#' @noRd
stream_retry = function(st, info) {
  if (st$finished) return(invisible(FALSE))
  info = info %||% list()
  sent = FALSE
  if (identical(st$transport, "http") && !is.na(st$id)) {
    sent = isTRUE(tryCatch(reactor_retry(st$id, info), error = function(e) FALSE))
  }
  if (st$finished) return(invisible(FALSE))
  if (sent) {
    st$hold = TRUE
    return(invisible(TRUE))
  }
  cls = info[["class"]]
  cls = if (is.character(cls) && length(cls) && !anyNA(cls) && all(nzchar(cls))) {
    cls[[1]]
  } else {
    "overloaded"
  }
  # contract 2.2 (D-012), as reactor_retry(): timeout_* has the parent timeout, others provider
  parent = if (grepl("^timeout(_|$)", cls)) "timeout" else "provider"
  cnd = stream_condition(paste0("The provider reported a retryable failure (", cls, ")."),
                         unique(c(cls, parent)), status = info[["status"]] %||% NA_integer_,
                         retry_after = info[["retry_after"]])
  stream_fail_live(st, cnd)
  invisible(FALSE)
}

#' Write one JSON line to the stream's child (process_jsonl `opts$send`); only the open turn's
#' own child (the session may already run another)
#' @noRd
stream_send = function(st, obj) {
  if (st$finished) return(invisible(FALSE))
  p = st$process
  if (is.null(p)) return(invisible(FALSE))
  write_all(p, paste0(json_encode(obj), "\n"))
  invisible(TRUE)
}

#' The opts every adapter function receives (contract section 8.1); `gate`, `tool_result` and
#' `mcp_dispatch` are the caller's, else fail-closed defaults (IC-33)
#' @noRd
stream_opts = function(st, opts, session, run) {
  signal = opts[["signal"]] %||% (if (is.environment(run)) run[["signal"]] else NULL)
  if (is.null(signal)) {
    signal = new.env(parent = emptyenv())
    signal$aborted = FALSE
    signal$reason = NULL
  }
  opts$emit = function(ev) stream_emit(st, ev)
  opts$retry = function(info) stream_retry(st, info)
  opts$send = function(obj) stream_send(st, obj)
  opts$signal = signal
  opts$state = opts[["state"]] %||% new.env(parent = emptyenv())
  opts$memo = opts[["memo"]] %||% new.env(parent = emptyenv())
  opts$gate = opts[["gate"]] %||% stream_gate_closed
  opts$tool_result = opts[["tool_result"]] %||% stream_tool_result
  opts$mcp_dispatch = opts[["mcp_dispatch"]] %||% stream_mcp_dispatch(session)
  opts$session = session
  opts$run = opts[["run"]] %||% (if (is.environment(run)) run[["id"]] else run)
  opts$first_byte_timeout = opts[["first_byte_timeout"]] %||% gptr_opt("first_byte_timeout")
  opts$idle_timeout = opts[["idle_timeout"]] %||% gptr_opt("idle_timeout")
  opts$connect_timeout = opts[["connect_timeout"]] %||% gptr_opt("connect_timeout")
  opts
}

#' The request spec of an HTTP adapter with the optional fields P04 reads (`request_id`, `model`,
#' `session_id` label the wire log; the three timeouts override the options)
#' @noRd
stream_http_spec = function(st, spec) {
  if (!is.list(spec)) {
    gptr_abort("The adapter's build() returned no request spec.", "invalid_spec",
               kind = "adapter", name = st$model[["api"]] %||% "", field = "build",
               problem = "build() must return a request spec (a list)")
  }
  sid = st$opts[["session"]]
  if (!is.character(sid) || length(sid) != 1L || is.na(sid)) sid = st$context[["session_id"]]
  fill = list(request_id = st$context[["request_id"]], model = st$model[["id"]],
              session_id = sid, connect_timeout = st$opts[["connect_timeout"]],
              first_byte_timeout = st$opts[["first_byte_timeout"]],
              idle_timeout = st$opts[["idle_timeout"]])
  for (k in names(fill)) {
    if (is.null(spec[[k]]) && !is.null(fill[[k]])) spec[[k]] = fill[[k]]
  }
  spec
}

#' A static-rate override of a provider: settings `providers.<id>.rate`, else the merged
#' catalog's providers section (IC-64); NULL when none or when ratelimit_rate() refuses it
#' @noRd
provider_rate_override = function(id) {
  ok = function(r) {
    is.list(r) && length(r) > 0L &&
      !is.null(tryCatch(ratelimit_rate(r), gptr_error = function(e) NULL))
  }
  r = provider_settings(id)[["rate"]]
  if (ok(r)) return(r)
  r = tryCatch(catalog_get()$providers[[id]][["rate"]], error = function(e) NULL)
  if (ok(r)) r else NULL
}

#' Feed a rate override into P04's limiter: ratelimit_set() refills the bucket, so it runs only
#' when the override differs from the limiter's current static rate
#' @noRd
stream_rate_sync = function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id)) return(invisible(FALSE))
  rate = provider_rate_override(id)
  if (is.null(rate)) return(invisible(FALSE))
  current = tryCatch(ratelimit_get(id)$rate, error = function(e) NULL)
  if (identical(current, rate)) return(invisible(FALSE))
  ratelimit_set(id, rate)
  invisible(TRUE)
}

#' HTTP transports (http_sse, http_ndjson, http_json): one transfer for the whole request
#' A second on_headers() (a re-send) resets the normaliser and the splitter; a splitter failure
#' ends the stream like a normaliser failure.
#' @noRd
stream_http = function(st, adapter) {
  st$transport = "http"
  st$adapter = adapter
  st$spec = stream_http_spec(st, adapter$build(st$model, st$context, st$opts))
  kind = st$spec[["stream"]] %||%
    switch(adapter[["transport"]] %||% "", http_ndjson = "ndjson", http_json = "json", "sse")
  if (!is.character(kind) || length(kind) != 1L || !kind %in% c("sse", "ndjson", "json")) {
    gptr_abort("The adapter's request spec names no known stream format.", "invalid_spec",
               kind = "adapter", name = adapter[["api"]] %||% "", field = "stream",
               problem = "stream must be \"sse\", \"ndjson\" or \"json\"")
  }
  reset = function() {
    st$norm = adapter$parse(st$model, st$opts)
    st$split = switch(kind, sse = sse_splitter(), ndjson = ndjson_splitter(), NULL)
    st$body = list()
    st$hold = FALSE
  }
  reset()
  st$heads = 0L
  on_headers = function(status, headers) {
    if (st$finished) return(invisible(NULL))
    st$heads = st$heads + 1L
    if (st$heads > 1L) reset()
    st$hold = FALSE
  }
  on_bytes = function(raw) {
    if (st$finished || isTRUE(st$hold)) return(invisible(NULL))
    if (identical(kind, "json")) {
      st$body[[length(st$body) + 1L]] = raw
      return(invisible(NULL))
    }
    units = tryCatch(st$split$push(raw), error = function(e) {
      stream_fail_live(st, stream_error_condition(e, "stream splitter"))
      list()
    })
    for (u in units) {
      if (st$finished || isTRUE(st$hold)) break
      stream_push(st, if (identical(kind, "ndjson")) list(data = u) else u)
    }
  }
  on_done = function(status, headers) {
    if (st$finished) return(invisible(NULL))
    ok = tryCatch({
      if (identical(kind, "json")) {
        body = if (length(st$body)) do.call(c, st$body) else raw()
        stream_push(st, list(data = raw_to_utf8(body), status = status, headers = headers))
      } else {
        rest = st$split$flush()
        if (identical(kind, "ndjson")) {
          for (u in rest) stream_push(st, list(data = u))
        } else if (!is.null(rest)) {
          stream_push(st, rest)
        }
      }
      TRUE
    }, error = function(e) {
      stream_normaliser_fail(st, stream_error_condition(e, "stream end"))
      FALSE
    })
    if (ok) stream_normaliser_finish(st)
  }
  on_fail = function(cnd) if (!st$finished) stream_normaliser_fail(st, cnd)
  on_retry = function(type, info) {
    if (!st$finished) stream_emit(st, do.call(ev_new, c(list(type), info)))
  }
  retry = list(max_attempts = as.integer(gptr_opt("max_attempts") %||% 4L),
               committed = function() isTRUE(st$committed), on_retry = on_retry)
  stream_rate_sync(st$model[["provider"]])
  st$id = reactor_http(st$spec, on_bytes = on_bytes, on_done = on_done, on_fail = on_fail,
                       on_headers = on_headers, run = st$run, provider = st$model[["provider"]],
                       retry = retry)
  stream_watch(st)
  st$id
}

#' One generator step of an inprocess adapter (IC-16, contract 8.1 `stream()`)
#' After an abort the generator gets two calls to end the stream itself; a settled run lets go
#' (INFRA-15); a throwing or malformed step, or an early NULL, ends it with one `error` event.
#' @noRd
stream_inprocess_step = function(st, gen) {
  if (st$finished) return(FALSE)
  if (stream_run_settled(st$run)) {
    stream_detach(st)
    return(FALSE)
  }
  if (isTRUE(st$opts$signal$aborted)) {
    st$aborts = st$aborts + 1L
    if (st$aborts > 2L) {
      stream_abort(st)
      return(FALSE)
    }
  } else if (reactor_now() < st$next_at) {
    return(TRUE)
  }
  res = tryCatch(gen(), error = function(e) {
    stream_normaliser_fail(st, stream_error_condition(e, "inprocess generator"))
    NULL
  })
  if (st$finished) return(FALSE)
  if (is.null(res)) {
    stream_fail_local(st, "error", "The stream ended without a terminal event.", "internal")
    return(FALSE)
  }
  events = if (is.list(res)) res[["events"]] %||% list() else NULL
  if (!is.list(events) || !all(vapply(events, is.list, NA))) {
    stream_fail_local(st, "error", "The inprocess generator returned a malformed step.",
                      "internal")
    return(FALSE)
  }
  for (ev in events) {
    stream_emit(st, ev)
    if (st$finished) break
  }
  wait = suppressWarnings(as.numeric(res[["wait"]] %||% 0)[1L])
  if (is.na(wait) || wait < 0) wait = 0
  st$next_at = reactor_now() + wait
  !st$finished
}

#' The inprocess transport: a generator pumped by reactor_task() (04 sections 8.1, 8.4 step 4)
#' Returns the task id; an error inside a step ends the stream, so `done` is still called once.
#' @noRd
stream_inprocess = function(st, adapter) {
  st$transport = "inprocess"
  st$adapter = adapter
  gen = adapter$stream(st$model, st$context, st$opts)
  if (!is.function(gen)) {
    gptr_abort("The adapter's stream() returned no generator.", "invalid_spec",
               kind = "adapter", name = adapter[["api"]] %||% "", field = "stream",
               problem = "stream() must return a generator function")
  }
  st$next_at = -Inf
  st$aborts = 0L
  st$id = reactor_task(function() {
    tryCatch(stream_inprocess_step(st, gen), error = function(e) {
      stream_normaliser_fail(st, stream_error_condition(e, "inprocess transport"))
      FALSE
    })
  }, run = st$run)
  st$id
}

#' Refuse a malformed process_jsonl spec of an adapter (before any child starts)
#' @noRd
stream_process_spec_abort = function(st, field, problem) {
  gptr_abort(paste0("The adapter's process spec is malformed: ", problem, "."), "invalid_spec",
             kind = "adapter", name = st$adapter[["api"]] %||% st$model[["api"]] %||% "",
             field = field, problem = problem)
}

#' Start the child of a process_jsonl adapter and watch its stdout
#' Only the session's current child routes to the open turn; no key reaches the child (IC-65).
#' The child, job row and watcher are the turn's as soon as each exists (stream_cancel()).
#' @noRd
stream_process_start = function(st, start) {
  state = st$opts$state
  args = start[["args"]] %||% character()
  if (is.list(args)) args = as.character(unlist(args))
  env = child_env(start[["env_profile"]] %||% "helper", set = start[["env"]] %||% character())
  p = proc_spawn(start[["command"]], args, env = env, wd = start[["wd"]], stdin = "|",
                 stdout = "|", stderr = "|")
  st$process = p
  job = id_new("j", 8L)
  st$job = job
  watch = NULL
  job_add("cli", job, st$model[["provider"]] %||% "", pid = p$get_pid(),
          stop = function() stream_process_stop(state, p, watch, job))
  state$process = p
  state$job = job
  state$watch = NULL
  watch = reactor_proc(p,
                       on_line = function(line) {
                         if (!identical(state$process, p)) return(invisible(NULL))
                         f = state$route
                         if (is.function(f)) f(line)
                       },
                       on_exit = function(status) {
                         job_remove(job)
                         if (!identical(state$process, p)) return(invisible(NULL))
                         state$process = NULL
                         f = state$route_exit
                         if (is.function(f)) f(status)
                       },
                       run = st$run)
  st$watch = watch
  state$watch = watch
  p
}

#' The process_jsonl transport (04 section 8.4 step 3): one supervised child per session
#' `build()` returns `start` (a new child) or NULL (reuse); returns the abort watch task id. A
#' line or exit runs stream_over() first, so the turn does not depend on that watch (D-018).
#' @noRd
stream_process = function(st, adapter) {
  st$transport = "process"
  st$adapter = adapter
  state = st$opts$state
  if (!is.environment(state)) {
    gptr_abort("A process_jsonl stream needs `opts$state` to be an environment.",
               "invalid_argument", arg = "opts$state", expected = "an environment")
  }
  # an earlier turn of the session still open was abandoned (its watch was cancelled)
  prev = state$stream_turn
  if (is.environment(prev) && !isTRUE(prev$finished)) stream_detach(prev)
  state$stream_turn = st
  spec = adapter$build(st$model, st$context, st$opts)
  if (!is.list(spec)) {
    stream_process_spec_abort(st, "build", "build() must return a process spec (a list)")
  }
  send = spec[["send"]] %||% list()
  if (!is.list(send) || !is.null(names(send))) {
    stream_process_spec_abort(st, "send", "send must be an unnamed list of JSON objects")
  }
  start = spec[["start"]]
  if (!is.null(start)) {
    cmd = if (is.list(start)) start[["command"]] else NULL
    if (!is.character(cmd) || length(cmd) != 1L || is.na(cmd) || !nzchar(cmd)) {
      stream_process_spec_abort(st, "start", "start must be a list with a command string")
    }
  }
  st$norm = adapter$parse(st$model, st$opts)
  lines = vapply(send, function(o) json_encode(o), "")
  p = state$process
  if (!is.null(start)) {
    if (!is.null(p)) {
      # forget the running child first, so its late output and exit reach no turn
      state$process = NULL
      stream_process_kill(p, state$watch, state$job)
    }
    p = stream_process_start(st, start)
  } else {
    st$watch = state$watch
    st$job = state$job
  }
  if (is.null(p)) {
    gptr_abort("The adapter reused a child process, but none is running for this session.",
               "internal", detail = "process_jsonl without start")
  }
  st$process = p
  state$route = function(line) {
    if (stream_over(st)) return(invisible(NULL))
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (is.list(obj)) stream_push(st, list(data = line, obj = obj))
    invisible(NULL)
  }
  state$route_exit = function(status) {
    st$process = NULL
    if (!stream_over(st)) stream_normaliser_finish(st)
    invisible(NULL)
  }
  for (l in lines) write_all(p, paste0(l, "\n"))
  if (isTRUE(spec[["close_stdin"]])) write_close(p)
  st$id = stream_watch(st)
  st$id
}

#' The stream driver of an adapter transport, or NULL when provider_stream() has none
#' @noRd
stream_driver = function(transport) {
  switch(transport, http_sse = , http_ndjson = , http_json = stream_http,
         inprocess = stream_inprocess, process_jsonl = stream_process, NULL)
}

#' The protected safety record for the request preflight (07-local-ollama.md section 2.1)
#' Local-only holds unless every record present relaxes it: the run's frozen snapshot (a run
#' without one is local-only) and `opts$safety`. NULL (local-only) without both.
#' @noRd
stream_safety = function(opts, run) {
  rs = NULL
  if (is.environment(run)) {
    ro = run[["opts"]]
    rs = (if (is.list(ro)) ro[["safety"]]) %||% list(ollama_local_only = TRUE)
  }
  recs = Filter(Negate(is.null), list(rs, opts[["safety"]]))
  if (!length(recs)) return(NULL)
  list(ollama_local_only = any(vapply(recs, catalog_local_only, NA)))
}

#' Refuse a decision-only (classifier) model before anything starts (IC-74): it answers typed
#' System One questions through s1_request() (P13), never a conversation
#' @noRd
stream_chat_model = function(model) {
  if (!identical(model[["type"]], "classifier")) return(invisible(TRUE))
  ref = model[["ref"]] %||% model[["id"]] %||% ""
  gptr_abort(paste0("Model ", ref, " is a decision-only (classifier) model: it answers typed ",
                    "System One questions and cannot hold a conversation. Choose a ",
                    "conversational model."),
             "not_available", member = ref, provided_by = "a conversational model")
}

#' The stream driver of a conversational adapter (IC-74), refused before anything starts when
#' the adapter lacks its transport's stream functions or no driver exists
#' @noRd
stream_conversational = function(model, adapter) {
  api = adapter[["api"]] %||% model[["api"]] %||% ""
  transport = adapter[["transport"]] %||% "http_sse"
  need = if (identical(transport, "inprocess")) "stream" else c("build", "parse")
  if (!all(vapply(need, function(f) is.function(adapter[[f]]), NA))) {
    gptr_abort(paste0("The adapter for the api ", api, " has no stream functions for its ",
                      transport, " transport, so it cannot hold a conversation."),
               "not_available", member = api, provided_by = "a conversational adapter")
  }
  driver = stream_driver(transport)
  if (is.null(driver)) {
    gptr_abort(paste0("provider_stream() has no driver for the ", transport,
                      " transport of the api ", api, "."),
               "not_available", member = transport, provided_by = "provider_stream()")
  }
  driver
}

#' Start one model request on the reactor (contract sections 7.5 and 8.4)
#' Refusals (model type, adapter, disabled provider, preflight IC-74, key) signal before anything
#' starts; later failures end the stream with an `error` event, and `done(msg)` runs once.
#' @noRd
provider_stream = function(model, context, opts, emit, done, run = NULL) {
  opts = opts %||% list()
  session = opts[["session"]] %||% (if (is.environment(run)) run[["session"]] else NULL)
  scoped = function(kind, name) {
    if (is.null(session) || is.null(name)) NULL else registry_get(kind, name, session = session)
  }
  stream_chat_model(model)
  adapter = scoped("adapter", model[["api"]]) %||% adapter_get(model[["api"]])
  driver = stream_conversational(model, adapter)
  provider = provider_effective(scoped("provider", model[["provider"]])) %||%
    provider_get(model[["provider"]])
  if (isFALSE(provider[["enabled"]])) {
    pid = provider[["id"]] %||% provider[["name"]]
    gptr_abort(paste0("Provider ", pid, " is disabled in the settings (providers.", pid,
                      ".enabled)."), "not_available", member = pid, provided_by = "settings")
  }
  model = provider_preflight(model, provider, stream_safety(opts, run))
  opts$credential = provider_credential(provider)
  opts$base_url = if (is.null(provider)) NULL else provider_base_url(provider)
  opts$provider = provider
  st = new.env(parent = emptyenv())
  st$model = model
  st$context = context
  st$emit_cb = emit
  st$done_cb = done
  st$run = run
  st$started = FALSE
  st$committed = FALSE
  st$finished = FALSE
  st$transport = NA_character_
  st$id = NA_character_
  st$acc = acc_new()
  st$opts = stream_opts(st, opts, session, run)
  tryCatch(driver(st, adapter), error = function(e) {
    cls = if (inherits(e, "gptr_error")) sub("^gptr_error_", "", class(e)[[1]]) else "internal"
    cnd = stream_condition(conditionMessage(e), cls)
    stream_cancel(st)
    stream_fail_local(st, "error", conditionMessage(cnd), cls)
    NA_character_
  })
}

# ---- gptr_providers(): the provider listing (04 sections 5.12 and 6.2, IC-65) -----------------

#' A scalar string from a provider's `status()` field (a `package_version` included), else NA
#' @noRd
provider_status_text = function(x) {
  if (inherits(x, "numeric_version")) x = as.character(x)
  if (!is.atomic(x) || !length(x)) return(NA_character_)
  v = as.character(x[[1]])
  if (is.na(v) || !nzchar(v)) NA_character_ else v
}

#' One reachability probe: one GET of <base>/models without credentials, 2 s (IC-65)
#' One attempt; any HTTP status proves reachability (a 401 included); never under R CMD check.
#' @noRd
provider_ping = function(p) {
  if (check_running()) return("not checked")
  url = provider_base_url(p)
  if (is.null(url)) return("no base url")
  if (is.null(provider_origin(url))) return("invalid base url")
  path = if (identical(p[["api"]], "anthropic-messages")) "/v1/models" else "/models"
  res = tryCatch(catalog_http_request(paste0(url, path), "GET", list(), NULL, timeout = 2,
                                      attempts = 1L, max_bytes = 65536),
                 gptr_error = function(e) list(status = e[["status"]]))
  code = suppressWarnings(as.integer(res[["status"]] %||% NA_integer_))
  if (length(code) != 1L || is.na(code)) "unreachable" else paste0("reachable (HTTP ", code, ")")
}

#' Does a provider speak HTTP (contract 6.2: only HTTP providers are probed)?
#' Its adapter's transport, else whether its api is one of P12's and P13's built-in wire apis.
#' @noRd
provider_http = function(p) {
  api = p[["api"]]
  if (!is.character(api) || length(api) != 1L || is.na(api) || !nzchar(api)) return(FALSE)
  a = tryCatch(registry_get("adapter", api), error = function(e) NULL)
  tr = if (is.list(a)) a[["transport"]] else NULL
  if (is.character(tr) && length(tr) == 1L && !is.na(tr)) return(startsWith(tr, "http"))
  api %in% c("anthropic-messages", "openai-responses", "openai-completions",
             "google-generative-ai", "typesafe-system-one", "ollama-system-one")
}

#' Status and version of a provider; `check = TRUE` adds a reachability probe
#' `disabled` by settings, else the provider's own `status()`, else from the transport and the
#' credential lookup `h`; the probe replaces only `ready` and `no key` of an HTTP provider.
#' @noRd
provider_status = function(p, h, check) {
  if (isFALSE(p[["enabled"]])) return(list(status = "disabled", version = NA_character_))
  f = p[["status"]]
  if (is.function(f)) {
    s = tryCatch(if ("check" %in% names(formals(f))) f(check = check) else f(),
                 error = function(e) list(status = "error"))
    if (!is.list(s)) s = list()
    status = provider_status_text(s[["status"]])
    if (is.na(status)) {
      avail = s[["available"]]
      status = if (isTRUE(avail)) "ready" else if (isFALSE(avail)) "unavailable" else "unknown"
    }
    return(list(status = status, version = provider_status_text(s[["version"]])))
  }
  offline = isTRUE(p[["offline"]])
  http = !offline && provider_http(p)
  keyed = !is.null(p[["auth"]]) && !is.function(p[["auth"]]) && !offline
  failed = inherits(h, "condition")
  url = provider_base_url(p)
  status = if (failed && !inherits(h, "gptr_error_no_key")) {
    "error"
  } else if (http && is.null(url)) {
    "no base url"
  } else if (http && is.null(provider_origin(url))) {
    "invalid base url"
  } else if (failed || (keyed && is.null(h))) {
    "no key"
  } else {
    "ready"
  }
  if (check && http && status %in% c("ready", "no key")) status = provider_ping(p)
  list(status = status, version = NA_character_)
}

#' The default model reference shown for a provider: architecture 8.4, else its newest active
#' catalog model; never a classifier for a conversational provider, or the reverse (IC-74)
#' @noRd
provider_default_model = function(p, idx) {
  id = p[["id"]] %||% p[["name"]]
  d = provider_default_models()[id]
  if (!is.na(d)) return(paste0(id, "/", d))
  if (!is.data.frame(idx) || !nrow(idx)) return(NA_character_)
  decision = identical(p[["type"]], "classifier")
  ok = idx$provider == id & idx$status == "active" & (idx$type == "classifier") == decision
  rows = idx[!is.na(ok) & ok, , drop = FALSE]
  if (!nrow(rows)) return(NA_character_)
  rows$ref[order(rows$release_date, decreasing = TRUE, method = "radix")][[1]]
}

#' Egress acknowledgment state of a provider (the acknowledgment itself is P08's)
#' None needed offline or for a loopback local endpoint (IC-74); else `egress.<id>` decides.
#' @noRd
provider_egress = function(p) {
  if (isTRUE(p[["offline"]])) return("ack")
  if (isTRUE(p[["local"]]) && isTRUE(catalog_endpoint(p)[["loopback"]])) return("ack")
  eg = setting_get("egress", default = list())
  if (!is.list(eg)) eg = list()
  if (identical(eg[[p[["id"]] %||% p[["name"]]]], "ack")) "ack" else "needed"
}

#' A provider for the listing: its effective record, else the registered record with the
#' settings condition as `err` (NULL when the record disappeared)
#' @noRd
provider_listing_get = function(id) {
  tryCatch(list(p = provider_get(id), err = NULL), error = function(e) {
    p = tryCatch(registry_get("provider", id), error = function(e2) NULL)
    list(p = if (is.null(p)) list(id = id) else p, err = e)
  })
}

#' One row of the provider listing (the credential lookup registers and binds nothing)
#' @noRd
provider_listing_row = function(id, p, err, check, reg, idx) {
  # a failing settings entry or `auth` function marks its own row, never the whole listing
  h = if (is.null(err)) {
    tryCatch(provider_credential(p, register = FALSE), error = function(e) e)
  } else {
    err
  }
  s = if (is.null(err)) {
    provider_status(p, h, check)
  } else {
    list(status = "error", version = NA_character_)
  }
  src = if (is.null(reg)) character() else reg$source[reg$name == id & reg$state == "active"]
  list(id = id, type = provider_status_text(p[["type"]] %||% "chat"),
       api = provider_status_text(p[["api"]]),
       credential = if (inherits(h, c("gptr_secret", "gptr_credential_peek"))) {
         paste0(h[["name"]], " #", h[["fp"]])
       } else {
         NA_character_
       },
       source = if (length(src)) src[[1]] else NA_character_, status = s$status,
       default_model = provider_default_model(p, idx), egress = provider_egress(p),
       version = s$version)
}

#' List the configured model providers
#'
#' Shows every registered provider record: its wire api, where its credential comes from (as
#' `NAME #fingerprint`, never the value), the registry source of the record, its status, default
#' model, egress acknowledgment and, for subscription command-line tools, their version.
#'
#' `status` is `ready`, `no key`, `no base url` or `invalid base url` (HTTP providers),
#' `disabled` (the settings say `providers.<id>.enabled: false`), `error` (the provider's
#' settings or its credential lookup failed) or what a command-line provider reports; with
#' `check = TRUE` the `ready` or `no key` of an HTTP provider becomes `reachable (HTTP <code>)`
#' for a reachable endpoint (a 401 without a key still proves reachability), otherwise
#' `unreachable`, or `not checked` under `R CMD check`. `egress` is `ack` when no
#' acknowledgment is needed (offline providers, local servers at a loopback address) or the
#' user has given it. Listing reads credentials only: it never registers an environment
#' variable or binds it to a provider.
#'
#' `ready` means the required configuration is present; it does not validate the credential,
#' account quota or access to a specific model. `check = TRUE` tests reachability, not login.
#' See `vignette("language-models", package = "gptr")` for API, command-line and local setup.
#'
#' @param check `FALSE` (default) performs no network or process input/output unless
#'   `check_login = TRUE`. `TRUE` also
#'   probes each HTTP provider's models endpoint once without credentials (2 s timeout; skipped
#'   under `R CMD check`) and lets command-line providers check their tool; it never sends a
#'   paid request.
#' @param check_login Also check Codex and Claude Code's CLI-reported login status using
#'   their supported status commands (3 s timeout per subprocess, no model request).
#'   Adds a `login` column: `signed in`, `not signed in`, or `unknown`. Unsupported CLI
#'   versions, missing tools and failed checks report `unknown`; other providers report
#'   `not applicable`. This does not verify credentials online. Defaults to `FALSE`.
#' @return A `gptr_providers` data frame with columns `id`, `type`, `api`, `credential`,
#'   `source`, `status`, `default_model`, `egress` (`ack` or `needed`) and `version`, plus
#'   `login` when `check_login = TRUE`.
#' @examples
#' gptr_providers()
#' @export
gptr_providers = function(check = FALSE, check_login = FALSE) {
  check_flag(check, "check")
  check_flag(check_login, "check_login")
  ids = sort(registry_names("provider"), method = "radix")
  provs = lapply(ids, provider_listing_get)
  keep = !vapply(provs, function(x) is.null(x$p), NA)
  ids = ids[keep]
  provs = provs[keep]
  reg = tryCatch(gptr_registry("provider"), gptr_error = function(e) NULL)
  idx = tryCatch(catalog_get()$index, gptr_error = function(e) NULL)
  rows = Map(function(id, x) provider_listing_row(id, x$p, x$err, check, reg, idx), ids, provs)
  col = function(f) vapply(rows, function(r) r[[f]], "", USE.NAMES = FALSE)
  df = data.frame(id = col("id"), type = col("type"), api = col("api"),
                  credential = col("credential"), source = col("source"),
                  status = col("status"), default_model = col("default_model"),
                  egress = col("egress"), version = col("version"), stringsAsFactors = FALSE)
  if (check_login) {
    df$login = vapply(seq_len(nrow(df)), function(i) {
      cli = c(`cli-codex` = "codex", `cli-claude` = "claude")[df$api[i]]
      if (is.na(cli)) return("not applicable")
      if (!df$status[i] %in% c("found", "ready")) return("unknown")
      pcli_login_status(unname(cli))
    }, "")
  }
  new_listing(df, "gptr_providers",
              footer = "Credentials show variable names and fingerprints only.")
}
