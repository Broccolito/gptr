# The openai-completions adapter (P12): OpenAI-compatible Chat Completions for hosted and local
# servers (Ollama chat models included, IC-74), Azure and Bedrock, driven by the compat record of
# report 09 section 3.3 (Pi's detectCompat()) and a streaming <think> splitter (09 section 4.6).
# Unreported usage stays unknown (IC-74).

#' The compat fields and their defaults (snake_case forms of Pi's OpenAICompletionsCompat)
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
#' Detected from the provider id and base URL like Pi's detectCompat(), then overridden per field
#' by the record's `compat`; OpenRouter's cache_control reaches Anthropic and Google models only.
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

#' A Chat Completions error object -> class suffix, status and retryability (08 section 3.5)
#' A bare string is the message; only a whole code in 100..599 is read, never coerced (D-034).
#' @noRd
completions_error_info = function(err) {
  if (!is.list(err)) err = list(message = adp_chr(err))
  code = err[["code"]]
  status = if (is.numeric(code) && length(code) == 1L && !is.na(code) && code >= 100 &&
                 code <= 599 && code == round(code)) {
    as.integer(code)
  } else {
    NA_integer_
  }
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

#' Record a Chat Completions usage object (Pi's parseChunkUsage, 09 section 2.3)
#' Input = prompt - cache reads and writes; each report replaces the last; null stays NA (IC-74).
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

#' An accumulator of OpenRouter `reasoning_details` fragments (09 section 2.3; Pi 665-676)
#' Consecutive text/summary fragments of one type and `index` merge (linear buffer); other items
#' stay verbatim, nulls drop. `add(x)` takes one item; `items()` closes and returns the list.
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
#' The compat record comes from `opts$provider`: a session-scoped provider's compat applies (D-023).
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

# ---- openai-completions: request body ---------------------------------------------------------

#' Adapter capabilities of openai-completions (04 section 8.1; IC-69, IC-71)
#' `cache = "openrouter"`: markers are written only for `cache_control_format = "anthropic"`.
#' @noRd
completions_caps = function() {
  list(images_in_results = FALSE, tool_addition = FALSE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("service_tier", "metadata", "user"), operator_role = "user",
       cache = "openrouter", max_tool_name = 64L, tool_shape = "chat")
}

#' Chat Completions content of a user message: a string, or text and image_url parts
#' @noRd
completions_user = function(m, model, mark_anchor, cc) {
  images = adp_images_ok(model)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      p = list(type = "text", text = b$text)
      if (cc && mark_anchor && type == "context" && isTRUE(b$anchor)) {
        p$cache_control = list(type = "ephemeral")
      }
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      url = paste0("data:", b$mime, ";base64,", b$data)
      parts[[length(parts) + 1L]] = if (images) {
        list(type = "image_url", image_url = list(url = url))
      } else {
        list(type = "text", text = adp_image_note())
      }
    }
  }
  if (!length(parts)) return(NULL)
  single = length(parts) == 1L && identical(parts[[1L]]$type, "text") &&
    is.null(parts[[1L]]$cache_control)
  if (single) return(list(role = "user", content = parts[[1L]]$text))
  list(role = "user", content = parts)
}

#' A Chat Completions assistant message: content a plain string (a text-part array only when
#' requires_thinking_as_text), reasoning replayed in the field it arrived in (Pi 1296-1396)
#' @noRd
completions_assistant = function(m, model, compat) {
  same = adp_same_model(m, model)
  texts = character()
  thinks = character()
  field = NULL
  calls = list()
  details = NULL
  for (b in m$content) {
    type = b$type %||% ""
    if (type == "text" && nzchar(trimws(b$text))) texts = c(texts, b$text)
    if (type == "thinking" && nzchar(trimws(b$thinking))) {
      thinks = c(thinks, b$thinking)
      field = field %||% b$signature
    }
    if (type == "tool_call") {
      args = if (length(b$arguments)) b$arguments else json_obj()
      calls[[length(calls) + 1L]] = list(id = completions_tool_id(b$id, compat, model$provider),
                                         type = "function",
                                         `function` = list(name = b$name,
                                                           arguments = json_encode(args)))
    }
    if (type == "opaque" && same) details = b$json
  }
  txt = paste(texts, collapse = "")
  as_text = length(thinks) && isTRUE(compat$requires_thinking_as_text)
  a = list(role = "assistant")
  if (as_text) {
    a$content = lapply(c(paste(thinks, collapse = "\n\n"), if (nzchar(txt)) txt),
                       function(x) list(type = "text", text = x))
  } else if (nzchar(txt)) {
    a$content = txt
  } else if (length(calls)) {
    a["content"] = if (isTRUE(compat$requires_assistant_after_tool_result)) list("") else list(NULL)
  } else {
    return(NULL)
  }
  if (length(calls)) a$tool_calls = calls
  fields = c("reasoning_content", "reasoning", "reasoning_text")
  if (length(thinks) && !as_text && same && isTRUE(field %in% fields)) {
    a[[field]] = paste(thinks, collapse = "\n")
  } else if (isTRUE(compat$requires_reasoning_content) && isTRUE(model$reasoning)) {
    a$reasoning_content = ""
  }
  if (!is.null(details)) a$reasoning_details = json_verbatim(details)
  a
}

#' The assistant message a host with requires_assistant_after_tool_result needs between tool
#' results and a user message (report 09 section 3.3; Pi 1233-1238, 1443-1448)
#' @noRd
completions_bridge = function() {
  list(role = "assistant", content = "I have processed the tool results.")
}

#' TRUE when the messages of a group of tool results end with the user message that attaches
#' their images (a model with image input and at least one image)
#' @noRd
completions_attaches = function(group, model) {
  adp_images_ok(model) && any(vapply(group, function(r) {
    any(vapply(r$content, function(b) identical(b$type, "image"), logical(1)))
  }, logical(1)))
}

#' Chat Completions messages of a group of tool results; images follow as one user message
#' A text-only model gets the omission note once per image (D-023 item 4); a required bridging
#' assistant message precedes the image message (Pi 1443-1448).
#' @noRd
completions_tool_results = function(group, model, compat) {
  out = list()
  imgs = list()
  images = adp_images_ok(model)
  for (r in group) {
    txt = paste(vapply(Filter(function(b) identical(b$type, "text"), r$content),
                       function(b) b$text, ""), collapse = "\n")
    n_img = sum(vapply(r$content, function(b) identical(b$type, "image"), logical(1)))
    if (n_img && !images) {
      txt = paste(c(txt[nzchar(txt)], rep(adp_image_note(), n_img)), collapse = "\n")
    }
    content = if (nzchar(txt)) txt else if (n_img) "(see attached image)" else "(no tool output)"
    tm = list(role = "tool",
              tool_call_id = completions_tool_id(r$tool_call_id, compat, model$provider),
              content = content)
    if (isTRUE(compat$requires_tool_result_name)) tm$name = r$tool_name
    out[[length(out) + 1L]] = tm
    if (images) {
      for (b in Filter(function(b) identical(b$type, "image"), r$content)) {
        url = paste0("data:", b$mime, ";base64,", b$data)
        imgs[[length(imgs) + 1L]] = list(type = "image_url", image_url = list(url = url))
      }
    }
  }
  if (length(imgs)) {
    if (isTRUE(compat$requires_assistant_after_tool_result)) {
      out[[length(out) + 1L]] = completions_bridge()
    }
    note = list(type = "text", text = "Attached image(s) from tool result:")
    out[[length(out) + 1L]] = list(role = "user", content = c(list(note), imgs))
  }
  out
}

#' Chat Completions tool definitions from the frozen Anthropic-shape array (04 section 9.2)
#' @noRd
completions_tools = function(tools, compat) {
  lapply(tools, function(t) {
    fn = list(name = t$name, description = t$description %||% "", parameters = t$input_schema)
    if (isTRUE(compat$supports_strict_mode)) fn$strict = FALSE
    list(type = "function", `function` = fn)
  })
}

#' The thinking request fields of a compat thinking_format (report 09 section 3.4)
#' @noRd
completions_thinking = function(head, model, params, compat) {
  if (!isTRUE(model$reasoning) || is.null(params$thinking)) return(head)
  level = params$thinking
  on = !identical(level, "off")
  eff = params$effort %||% (if (on) level else NULL)
  fmt = compat$thinking_format %||% "openai"
  if (fmt == "openrouter") {
    head$reasoning = list(effort = if (on) eff else "none")
  } else if (fmt == "deepseek") {
    head$thinking = list(type = if (on) "enabled" else "disabled")
    if (on && isTRUE(compat$supports_reasoning_effort)) head$reasoning_effort = eff
  } else if (fmt == "zai") {
    head$thinking = if (on) list(type = "enabled", clear_thinking = FALSE) else
      list(type = "disabled")
  } else if (fmt == "qwen") {
    head$enable_thinking = on
  } else if (fmt == "qwen-chat-template") {
    head$chat_template_kwargs = list(enable_thinking = on, preserve_thinking = TRUE)
  } else if (fmt == "together") {
    head$reasoning = list(enabled = on)
  } else if (isTRUE(compat$supports_reasoning_effort)) {
    if (on) {
      head$reasoning_effort = eff
    } else if ("off" %in% unlist(model$thinking_levels)) {
      head$reasoning_effort = "none"
    }
  }
  head
}

#' build() of the openai-completions adapter (04 section 8.1; G4 section 3.7)
#' Compat and headers come from `opts$provider` (D-023, D-027); tools only to a `tool_call` model
#' (IC-74). Elements are memoised per session, keyed by everything that reaches the wire.
#' @noRd
completions_build = function(model, context, opts) {
  params = context$params %||% list()
  compat = compat_flags(adp_provider_record(model, opts) %||% list(id = adp_chr(model$provider)),
                        model)
  ckey = hash_xxh128(compat)
  images = adp_images_ok(model)
  anchors = adp_cache_plan(context)$anchors %||% character()
  cc_ok = identical(compat$cache_control_format, "anthropic")
  cc_sys = cc_ok && any(c("t0", "t1") %in% anchors)
  cc = cc_ok && "project" %in% anchors
  msgs = context$messages %||% list()
  anchor_at = adp_anchor_index(msgs)
  tools_on = !isFALSE(model[["tool_call"]])
  tj = if (tools_on) {
    adp_tools_json(opts, paste("openai-completions", compat$supports_strict_mode),
                   context$tools_json, function(tools) completions_tools(tools, compat))
  }

  head = list(model = completions_model_name(model, compat), stream = TRUE)
  if (isTRUE(compat$supports_usage_in_streaming)) head$stream_options = list(include_usage = TRUE)
  if (isTRUE(compat$supports_store)) head$store = FALSE
  if (!is.null(params$max_tokens)) head[[compat$max_tokens_field]] = as.integer(params$max_tokens)
  if (!is.null(params$temperature)) head$temperature = params$temperature
  head = completions_thinking(head, model, params, compat)
  tc = params$tool_choice
  if (!is.null(tj) && isTRUE(compat$supports_tool_choice)) {
    if (identical(tc, "none")) {
      head$tool_choice = "none"
    } else if (adp_forced(tc) && adp_forced_ok(model, completions_caps()) &&
                 is.null(params$returns)) {
      head$tool_choice = if (identical(tc$type, "any")) "required" else
        list(type = "function", `function` = list(name = tc$name))
    }
  }
  for (f in completions_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  if (!is.null(tj)) {
    extra = c(extra, paste0("\"tools\":", tj))
  } else if (tools_on && adp_has_tool_calls(msgs)) {
    extra = c(extra, "\"tools\":[]")
  }

  elements = character()
  t0 = context$system$t0 %||% ""
  t1 = context$system$t1 %||% ""
  role = if (isTRUE(model$reasoning) && isTRUE(compat$supports_developer_role)) "developer" else
    "system"
  if (nzchar(t0) || nzchar(t1)) {
    sys = if (cc_sys) {
      parts = list()
      if (nzchar(t0)) parts[[length(parts) + 1L]] = list(type = "text", text = t0)
      if (nzchar(t1)) parts[[length(parts) + 1L]] = list(type = "text", text = t1)
      parts[[length(parts)]]$cache_control = list(type = "ephemeral")
      list(role = role, content = parts)
    } else {
      list(role = role, content = paste(c(t0, t1)[nzchar(c(t0, t1))], collapse = "\n\n"))
    }
    elements = c(elements, json_encode(sys))
  }
  n = length(msgs)
  i = 1L
  while (i <= n) {
    m = msgs[[i]]
    r = m$role %||% ""
    if (r == "tool_result") {
      j = i
      while (j <= n && identical(msgs[[j]]$role, "tool_result")) j = j + 1L
      group = msgs[i:(j - 1L)]
      key = paste(c("openai-completions", "results", model$provider, model$id, images, ckey,
                    vapply(group, adp_msg_key, "")), collapse = "|")
      el = adp_memo(opts, key, function() {
        paste(vapply(completions_tool_results(group, model, compat), json_encode, ""),
              collapse = ",")
      })
      elements = c(elements, el)
      # the returns instruction below is a user message too; a group that ends with its image
      # message already carries the bridge (completions_tool_results())
      nxt = if (j <= n) msgs[[j]]$role %||% "" else if (!is.null(params$returns)) "user" else
        "end"
      if (isTRUE(compat$requires_assistant_after_tool_result) && nxt %in% c("user", "operator") &&
            !completions_attaches(group, model)) {
        elements = c(elements, json_encode(completions_bridge()))
      }
      i = j
      next
    }
    same = adp_same_model(m, model)
    mark = identical(i, anchor_at)
    key = paste("openai-completions", r, adp_msg_key(m), model$provider, model$id, same, mark,
                cc, images, isTRUE(model$reasoning), ckey, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (r == "user") x = completions_user(m, model, mark, cc)
      if (r == "assistant") x = completions_assistant(m, model, compat)
      if (r == "operator") {
        txt = adp_operator_text(m)
        if (nzchar(txt)) x = list(role = "user", content = txt)
      }
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) elements = c(elements, el)
    i = i + 1L
  }
  if (!is.null(params$returns)) {
    elements = c(elements, json_encode(list(role = "user",
                                            content = adp_returns_instruction(params$returns))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  cred = opts$credential
  if (!is.null(cred)) {
    if (identical(compat$auth_header, "api-key")) {
      headers$`api-key` = adp_header_secret(cred)
    } else {
      headers$authorization = adp_header_secret(cred, "Bearer ")
    }
  }
  if (identical(compat$session_affinity, "openrouter") && !is.null(context$session_id)) {
    headers$`x-session-id` = context$session_id
  }
  headers = adp_merge_headers(headers, adp_provider_headers(model, opts),
                              auth = c("authorization", "api-key"))

  list(url = adp_url(opts$base_url %||% "https://api.openai.com/v1", "chat/completions"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "messages", elements), stream = "sse")
}

#' builtin:openai-compat: registers the openai-completions adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_openai_compat = function(gptr) {
  gptr$register(gptr_adapter("openai-completions", transport = "http_sse",
                             build = completions_build, parse = completions_normaliser,
                             capabilities = completions_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("openai-compat", builtin_openai_compat))
