# The openai-completions adapter (P12): OpenAI-compatible Chat Completions for OpenRouter,
# Groq, DeepSeek, Mistral, Together, xAI, Cerebras, Fireworks, the local servers (Ollama chat
# models included, IC-74), Azure and Bedrock, driven by the compat record of report 09 section
# 3.3 (Pi's OpenAICompletionsCompat and detectCompat(), openai-completions.ts:1585-1726) and a
# streaming <think> splitter (09 section 4.6). The normaliser is adapted from the verified
# prototypes of report 09 section 5.1 and report 03 section 5.3 (verification log rows 11-14
# applied: cache_control only for OpenRouter, the finish-reason map, thinking as a text-part
# array). Usage follows IC-74 (07-local-ollama.md section 5): usage the stream never reported,
# or reported as null, stays unknown.

#' The compat fields and their defaults (snake_case forms of Pi's OpenAICompletionsCompat;
#' the names P05's provider records use)
#' @noRd
compat_defaults = function() {
  list(supports_store = TRUE, supports_developer_role = TRUE,
       supports_reasoning_effort = TRUE, supports_usage_in_streaming = TRUE,
       supports_finish_reason = TRUE, supports_strict_mode = FALSE, supports_tool_choice = TRUE,
       max_tokens_field = "max_completion_tokens", requires_tool_result_name = FALSE,
       requires_assistant_after_tool_result = FALSE, requires_thinking_as_text = FALSE,
       requires_reasoning_content = FALSE, thinking_format = "openai",
       thinking_in_content = FALSE, think_tags = FALSE, cache_control_format = "none",
       session_affinity = "none", image_mode = "base64", tool_id = "default",
       auth_header = "authorization", deployment_model = FALSE, explicit_cache_mode = FALSE)
}

#' Pi's camelCase compat names -> the snake_case field names of compat_defaults()
#' @noRd
compat_snake = function(x) {
  alias = c(requiresReasoningContentOnAssistantMessages = "requires_reasoning_content",
            sessionAffinityFormat = "session_affinity",
            supportsExplicitPromptCacheMode = "explicit_cache_mode")
  out = ifelse(x %in% names(alias), alias[x], x)
  tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", out))
}

#' The compat record of a provider and model (04 section 7.12; report 09 section 3.3)
#'
#' Field names, `max_tokens` vs `max_completion_tokens`, reasoning replay, tool-id rules and
#' image and auth modes: detected from the provider id and base URL like Pi's detectCompat(),
#' then overridden field by field by the provider record's `compat` (snake_case or Pi's
#' camelCase names). OpenRouter forwards `cache_control` only to Anthropic and Google models
#' (G4 sections 2.6 and 3.7), so other OpenRouter model ids get `cache_control_format = "none"`.
#' @param provider A provider id (chr(1)) or a provider record.
#' @param model A model record (04 section 4.9) or NULL.
#' @return A named list with the fields of compat_defaults().
#' @noRd
compat_flags = function(provider, model) {
  rec = if (is.character(provider)) provider_get(provider) else provider
  id = if (is.character(provider)) provider else rec[["id"]] %||% rec[["name"]] %||% ""
  base = tolower(rec[["base_url"]] %||% "")
  mid = tolower(model[["id"]] %||% "")
  out = compat_defaults()
  hosts = paste0("cerebras\\.ai|api\\.x\\.ai|together\\.(ai|xyz)|deepseek\\.com|api\\.z\\.ai|",
                 "moonshot|nvidia\\.com|chutes\\.ai")
  nonstd = id %in% c("cerebras", "xai", "together", "deepseek", "zai", "moonshot", "nvidia",
                     "chutes", "fireworks", "mistral") || grepl(hosts, base)
  local = id %in% c("ollama", "lmstudio", "llamacpp", "vllm") || isTRUE(rec[["local"]])
  openrouter = identical(id, "openrouter") || grepl("openrouter\\.ai", base)
  if (nonstd || local) {
    out$supports_store = FALSE
    out$supports_developer_role = FALSE
  }
  if (local) {
    out$supports_reasoning_effort = id %in% c("ollama", "vllm")
    out$max_tokens_field = "max_tokens"
  }
  if (openrouter) {
    out$supports_store = FALSE
    out$thinking_format = "openrouter"
    out$session_affinity = "openrouter"
    out$supports_developer_role = grepl("^(anthropic|openai)/", mid)
    out$cache_control_format = "anthropic"
  }
  if (id == "deepseek") {
    out$thinking_format = "deepseek"
    out$requires_reasoning_content = TRUE
    out$max_tokens_field = "max_tokens"
  }
  if (id == "mistral") {
    out$tool_id = "alnum9"
    out$thinking_in_content = TRUE
  }
  if (id == "together") {
    out$thinking_format = "together"
    out$max_tokens_field = "max_tokens"
    out$think_tags = TRUE
  }
  if (id == "xai") out$supports_reasoning_effort = FALSE
  if (id == "azure") {
    out$auth_header = "api-key"
    out$deployment_model = TRUE
  }
  if (id == "openai") out$explicit_cache_mode = TRUE
  over = rec[["compat"]]
  if (length(over) && !is.null(names(over))) {
    names(over) = compat_snake(names(over))
    for (k in intersect(names(over), names(out))) if (!is.null(over[[k]])) out[[k]] = over[[k]]
  }
  if (openrouter && !grepl("^(anthropic|google)/", mid)) out$cache_control_format = "none"
  out
}

#' The model name sent to the API: Azure deployments through AZURE_OPENAI_DEPLOYMENT_NAME_MAP
#' (`model=deployment,model2=dep2`, report 09 section 2.5), else the model id
#' @noRd
completions_model_name = function(model, compat) {
  if (!isTRUE(compat$deployment_model)) return(model$id)
  map = Sys.getenv("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "")
  if (!nzchar(map)) return(model$id)
  pairs = strsplit(strsplit(map, ",", fixed = TRUE)[[1L]], "=", fixed = TRUE)
  for (p in pairs) {
    if (length(p) == 2L && identical(trimws(p[[1L]]), model$id)) return(trimws(p[[2L]]))
  }
  model$id
}

#' A streaming <think>...</think> splitter: `push(x)` returns segments list(kind, text), with
#' tags that may be split across chunks held back; `flush()` returns the rest
#' @noRd
think_splitter = function() {
  st = new.env(parent = emptyenv())
  st$inside = FALSE
  st$hold = ""
  kind = function() if (st$inside) "thinking" else "text"
  push = function(x) {
    buf = paste0(st$hold, x)
    st$hold = ""
    out = list()
    repeat {
      tag = if (st$inside) "</think>" else "<think>"
      pos = regexpr(tag, buf, fixed = TRUE)
      if (pos > 0L) {
        before = substr(buf, 1L, pos - 1L)
        if (nzchar(before)) out[[length(out) + 1L]] = list(kind = kind(), text = before)
        buf = substr(buf, pos + nchar(tag), nchar(buf))
        st$inside = !st$inside
        next
      }
      keep = 0L
      for (k in seq_len(min(nchar(tag) - 1L, nchar(buf)))) {
        if (endsWith(buf, substr(tag, 1L, k))) keep = k
      }
      emit = substr(buf, 1L, nchar(buf) - keep)
      st$hold = substr(buf, nchar(buf) - keep + 1L, nchar(buf))
      if (nzchar(emit)) out[[length(out) + 1L]] = list(kind = kind(), text = emit)
      break
    }
    out
  }
  flush = function() {
    out = if (nzchar(st$hold)) list(list(kind = kind(), text = st$hold)) else list()
    st$hold = ""
    out
  }
  list(push = push, flush = flush)
}

#' Chat Completions tool-call ids: `call|item` ids joined and capped at 40 characters with a
#' hash suffix, Mistral's 9 alphanumeric characters, OpenAI's 40-character cap (Pi 1194-1218)
#' @noRd
completions_tool_id = function(id, compat, provider = "") {
  if (identical(compat$tool_id, "alnum9")) {
    if (grepl("^[A-Za-z0-9]{9}$", id)) return(id)
    return(substr(hash_sha256(id), 1L, 9L))
  }
  if (grepl("|", id, fixed = TRUE)) {
    p = strsplit(id, "|", fixed = TRUE)[[1L]]
    call = gsub("[^A-Za-z0-9_-]", "_", p[[1L]])
    item = if (length(p) > 1L) gsub("[^A-Za-z0-9_-]", "_", p[[2L]]) else ""
    combined = if (nzchar(item)) paste0(call, "_", item) else call
    if (nchar(combined) <= 40L) return(combined)
    return(paste0(substr(call, 1L, 31L), "_", substr(hash_sha256(id), 1L, 8L)))
  }
  if (identical(provider, "openai") && nchar(id) > 40L) return(substr(id, 1L, 40L))
  id
}

#' A Chat Completions error object -> class suffix, status and retryability (08 section 3.5);
#' an error given as a bare string is its message
#' @noRd
completions_error_info = function(err) {
  if (!is.list(err)) err = list(message = adp_chr(err))
  code = err[["code"]]
  status = if (is.numeric(code) && length(code) == 1L) as.integer(code) else NA_integer_
  txt = tolower(paste(adp_chr(err[["type"]]), adp_chr(if (is.character(code)) code)))
  if (grepl("spend_limit|usage_limit|credit_balance|insufficient_quota", txt)) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  if (identical(status, 429L) || grepl("rate_limit|slow_down", txt)) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if ((!is.na(status) && status >= 500L) || grepl("overload|server_error|unavailable", txt)) {
    return(list(class = "overloaded", status = if (is.na(status)) 503L else status, retry = TRUE))
  }
  list(class = "provider", status = status, retry = FALSE)
}

#' A Chat Completions finish_reason -> gptr stop reason (04 section 4.2; Pi 1554-1578): a value
#' that is not one string is an error, never matched by position
#' @noRd
completions_stop = function(reason) {
  if (!is.character(reason) || length(reason) != 1L || is.na(reason)) return("error")
  switch(reason, stop = , end = "stop", length = "length",
         tool_calls = , function_call = "tool_use", "error")
}

#' One count of a reported usage object: NULL when the provider left the field out, else the
#' count, NA for a null or a value that is not a nonnegative number (IC-74)
#' @noRd
completions_count = function(x, key) {
  if (!is.list(x) || !(key %in% names(x))) return(NULL)
  adp_count(x[[key]])
}

#' The first known of several reported counts: NA when only unknown ones were reported, P05's
#' legacy zero when none was (D-022)
#' @noRd
completions_first = function(...) {
  vals = Filter(Negate(is.null), list(...))
  if (!length(vals)) return(0)
  known = Filter(Negate(is.na), vals)
  if (length(known)) known[[1L]] else NA_real_
}

#' Record a Chat Completions usage object (Pi's parseChunkUsage, 09 section 2.3): the cache read
#' from `prompt_tokens_details.cached_tokens`, DeepSeek's `prompt_cache_hit_tokens` or Kimi's
#' `cached_tokens`; input is the prompt minus cache reads and writes. Each report replaces the
#' last (the counts are totals, not deltas); a reported null stays unknown (IC-74)
#' @noRd
completions_usage = function(st, u) {
  if (!is.list(u)) return(invisible(NULL))
  details = u[["prompt_tokens_details"]]
  cached = completions_first(completions_count(details, "cached_tokens"),
                             completions_count(u, "prompt_cache_hit_tokens"),
                             completions_count(u, "cached_tokens"))
  cwrite = completions_first(completions_count(details, "cache_write_tokens"))
  prompt = completions_first(completions_count(u, "prompt_tokens"))
  reasoning = completions_count(u[["completion_tokens_details"]], "reasoning_tokens")
  st$usage = list(input = max(0, prompt - cached - cwrite),
                  output = completions_first(completions_count(u, "completion_tokens")),
                  cache_read = cached, cache_write_5m = cwrite,
                  reasoning = completions_first(reasoning))
  invisible(NULL)
}

#' An accumulator of OpenRouter `reasoning_details` fragments (report 09 section 2.3; Pi
#' openai-completions.ts:665-676)
#'
#' The stream sends one fragment per reasoning delta. Consecutive `reasoning.text` or
#' `reasoning.summary` fragments of the same type and `index` (and no conflicting `id`) are merged
#' into one item: the text is collected in a linear buffer and joined once (04 section 8.1), and a
#' later non-null field, such as the closing `signature`, is kept. Every other item, such as
#' `reasoning.encrypted`, stays discrete and verbatim; a null item is dropped. `add(x)` takes one
#' item; `items()` closes the open item and returns the list.
#' @noRd
completions_details = function() {
  st = new.env(parent = emptyenv())
  st$items = adp_buffer()
  st$open = NULL
  st$key = NULL
  st$text = NULL
  text_key = function(x) {
    type = if (is.list(x) && !is.null(names(x))) adp_chr(x[["type"]]) else ""
    switch(type, reasoning.text = "text", reasoning.summary = "summary", NULL)
  }
  same = function(a, b) {
    ida = adp_chr(a[["id"]])
    idb = adp_chr(b[["id"]])
    identical(adp_chr(a[["type"]]), adp_chr(b[["type"]])) &&
      identical(adp_chr(a[["index"]]), adp_chr(b[["index"]])) &&
      (!nzchar(ida) || !nzchar(idb) || identical(ida, idb))
  }
  add_text = function(x) {
    if (is.character(x) && length(x) == 1L && !is.na(x)) adp_buffer_add(st$text, x)
  }
  close = function() {
    if (is.null(st$open)) return(invisible(NULL))
    item = st$open
    if (st$text$n > 0L) item[[st$key]] = adp_buffer_text(st$text)
    adp_buffer_add(st$items, item)
    st$open = NULL
    invisible(NULL)
  }
  add = function(x) {
    if (is.null(x)) return(invisible(NULL))
    key = text_key(x)
    if (!is.null(key) && !is.null(st$open) && identical(key, st$key) && same(st$open, x)) {
      add_text(x[[key]])
      item = st$open
      for (k in setdiff(names(x), key)) {
        if (!is.null(x[[k]])) {
          item[k] = list(x[[k]])
        } else if (!(k %in% names(item))) {
          item[k] = list(NULL)
        }
      }
      st$open = item
      return(invisible(NULL))
    }
    close()
    if (is.null(key)) {
      adp_buffer_add(st$items, x)
      return(invisible(NULL))
    }
    st$open = x
    st$key = key
    st$text = adp_buffer()
    add_text(x[[key]])
    invisible(NULL)
  }
  items = function() {
    close()
    st$items$v[seq_len(st$items$n)]
  }
  list(add = add, items = items)
}

#' The openai-completions normaliser (04 section 8.1; Pi openai-completions.ts:553-700)
#'
#' The compat record comes from the provider record provider_stream() resolved (`opts$provider`,
#' the session's own record first; D-023), so a session-scoped provider's compat applies.
#' @param model A model record (contract section 4.9).
#' @param opts The adapter options of contract section 8.1 (`emit`, `retry`, `signal`,
#'   `provider`, `session`).
#' @return A list of functions `push`, `finish`, `fail`, `message`.
#' @noRd
completions_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  compat = compat_flags(adp_provider_record(model, opts) %||% list(id = adp_chr(model$provider)),
                        model)
  cur = new.env(parent = emptyenv())
  cur$text = NULL
  cur$think = NULL
  cur$field = NULL
  cur$by_index = list()
  cur$by_id = list()
  cur$finish = FALSE
  details = completions_details()
  splitter = if (isTRUE(compat$think_tags)) think_splitter() else NULL

  add = function(kind, x) {
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) return(invisible(NULL))
    slot = if (kind == "thinking") "think" else "text"
    if (is.null(cur[[slot]])) {
      sig = if (kind == "thinking") cur$field else NULL
      assign(slot, adp_open(st, kind, signature = sig), envir = cur)
    }
    adp_delta(st, cur[[slot]], x)
  }

  add_text = function(x) {
    if (is.null(splitter)) return(add("text", x))
    for (seg in splitter$push(x)) add(seg$kind, seg$text)
  }

  on_tool = function(tc) {
    if (!is.list(tc)) return(invisible(NULL))
    fn = tc[["function"]]
    if (!is.list(fn)) fn = list()
    tid = tc[["id"]]
    has_id = is.character(tid) && length(tid) == 1L && !is.na(tid) && nzchar(tid)
    idx = if (!is.null(tc[["index"]])) adp_chr(tc[["index"]]) else ""
    i = if (nzchar(idx)) cur$by_index[[idx]] else NULL
    if (is.null(i) && has_id) i = cur$by_id[[tid]]
    if (is.null(i)) {
      i = adp_open(st, "tool_call", id = if (has_id) tid else "", name = fn[["name"]] %||% "",
                   pj = partial_json())
    }
    if (nzchar(idx)) cur$by_index[[idx]] = i
    b = st$blocks[[i]]
    if (has_id) {
      cur$by_id[[tid]] = i
      if (!nzchar(adp_chr(b$id))) b$id = tid
    }
    nm = fn[["name"]]
    if (!nzchar(adp_chr(b$name)) && is.character(nm)) b$name = nm
    args = fn[["arguments"]]
    # arguments are JSON text; a server that sends the parsed object gets it serialised back
    if (is.list(args)) args = json_encode(if (length(args)) args else json_obj())
    if (is.character(args) && length(args) == 1L && !is.na(args)) adp_delta(st, i, args)
  }

  on_content = function(content) {
    if (is.character(content)) {
      for (x in content) add_text(x)
      return(invisible(NULL))
    }
    if (!is.list(content)) return(invisible(NULL))
    for (item in content) {
      if (!is.list(item)) next
      if (identical(item[["type"]], "thinking")) {
        # Mistral: {type: thinking, thinking: [{type: text, text}]} (or a bare string)
        th = item[["thinking"]]
        if (is.character(th)) {
          for (x in th) add("thinking", x)
        } else {
          for (t in th) if (is.list(t)) add("thinking", t[["text"]])
        }
      } else if (is.character(item[["text"]])) {
        add_text(item[["text"]])
      }
    }
    invisible(NULL)
  }

  complete = function() {
    if (!is.null(splitter)) for (seg in splitter$flush()) add(seg$kind, seg$text)
    rd = details$items()
    if (length(rd)) {
      i = adp_open(st, "opaque")
      adp_set_opaque(st, i, json_encode(rd))
    }
    if (!cur$finish) {
      if (isFALSE(compat$supports_finish_reason)) {
        has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
        st$stop_reason = if (has_tool) "tool_use" else "stop"
      } else {
        adp_error(st, "The stream ended without a finish_reason.", class = "network")
        return(TRUE)
      }
    }
    adp_done(st)
    TRUE
  }

  on_finish = function(fr) {
    cur$finish = TRUE
    raw = adp_chr(fr)
    st$raw_stop = if (nzchar(raw)) raw
    st$stop_reason = completions_stop(fr)
    if (identical(st$stop_reason, "error")) {
      st$error_message = paste0("Provider finish_reason: ", if (nzchar(raw)) raw else "unknown")
    }
    has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
    if (identical(st$stop_reason, "stop") && has_tool) st$stop_reason = "tool_use"
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = trimws(ev$data %||% "")
    if (!nzchar(data)) return(FALSE)
    if (identical(data, "[DONE]")) return(complete())
    ch = adp_json_try(data)
    if (!adp_is_object(ch)) {
      adp_error(st, paste0("Could not parse a chat completion chunk: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    err = ch[["error"]]
    if (!is.null(err)) {
      info = completions_error_info(err)
      text = if (is.list(err)) adp_chr(err[["message"]]) else adp_chr(err)
      if (!nzchar(text)) text = "The provider reported an error."
      return(adp_stream_error(st, opts, text, class = info$class, status = info$status,
                              retryable = info$retry))
    }
    rid = adp_chr(ch[["id"]])
    if (is.null(st$response_id) && nzchar(rid)) st$response_id = rid
    rmodel = adp_chr(ch[["model"]])
    if (nzchar(rmodel) && !identical(rmodel, model$id)) st$response_model = rmodel
    if (!is.null(ch[["usage"]])) completions_usage(st, ch[["usage"]])
    choices = ch[["choices"]]
    choice = if (is.list(choices) && length(choices)) choices[[1L]] else NULL
    if (!is.list(choice)) return(FALSE)
    if (is.null(ch[["usage"]]) && !is.null(choice[["usage"]])) {
      completions_usage(st, choice[["usage"]])
    }
    d = choice[["delta"]]
    if (is.list(d)) {
      on_content(d[["content"]])
      for (f in c("reasoning_content", "reasoning", "reasoning_text")) {
        v = d[[f]]
        if (is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)) {
          cur$field = cur$field %||% f
          add("thinking", v)
          break
        }
      }
      rd = d[["reasoning_details"]]
      if (length(rd)) {
        for (x in if (is.list(rd) && is.null(names(rd))) rd else list(rd)) details$add(x)
      }
      for (tc in d[["tool_calls"]] %||% list()) on_tool(tc)
    }
    fr = choice[["finish_reason"]]
    if (!is.null(fr)) on_finish(fr)
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    complete()
    st$final
  }

  adp_normaliser(st, push, finish)
}
