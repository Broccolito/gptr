# The google-generative-ai adapter (P12): streamGenerateContent?alt=sse with the key in the
# x-goog-api-key header (report 09 verification row 2: the header keeps the key out of URLs);
# thought signatures kept on the exact part they arrived on and replayed only to the same model;
# unknown finish reasons map to error with the raw value (report 09 sections 2.1-2.2, 3.1, 4.5
# and verification rows 4-9). The normaliser is adapted from the verified Gemini accumulator of
# report 09 section 5.1 and report 03 section 5.3. Usage follows IC-74 (07-local-ollama.md
# section 5): usage the stream never reported, or reported as null, stays unknown. Stream fields
# are read with `[[` (no `$` partial matching) and typed before use (04 sections 2.2, 4.2).

#' The Gemini major version of a model id, NA when unknown
#' @noRd
google_major = function(id) {
  m = regmatches(tolower(id), regexec("^gemini(?:-live)?-([0-9]+)", tolower(id), perl = TRUE))
  m = m[[1L]]
  if (length(m) < 2L) NA_integer_ else as.integer(m[[2L]])
}

#' Does the model take thinkingLevel (Gemini 3.x) rather than thinkingBudget (2.5)?
#' (Pi usesGoogleThinkingLevel(), google-shared.ts:72-83)
#' @noRd
google_uses_level = function(id) {
  id = tolower(id)
  grepl("gemini-3(\\.[0-9]+)?-(pro|flash)", id) ||
    id %in% c("gemini-flash-latest", "gemini-flash-lite-latest") || grepl("gemma-?4", id)
}

#' Do function calls and responses carry ids for this model? (Pi requiresToolCallId)
#' @noRd
google_needs_id = function(id) {
  isTRUE(google_major(id) >= 3L) || grepl("^(claude-|gpt-oss-)", tolower(id))
}

#' A replayable thought signature: base64 with a length that is a multiple of 4
#' @noRd
google_valid_sig = function(s) {
  is.character(s) && length(s) == 1L && !is.na(s) && nzchar(s) && nchar(s) %% 4L == 0L &&
    grepl("^[A-Za-z0-9+/]+={0,2}$", s)
}

#' The thinking budget of a Gemini 2.5 model for a level, -1 (dynamic) when unknown
#' @noRd
google_budget = function(id, level) {
  id = tolower(id)
  lv = if (level %in% c("xhigh", "max")) "high" else level
  tab = if (grepl("2\\.5-pro", id)) {
    c(minimal = 128L, low = 2048L, medium = 8192L, high = 32768L)
  } else if (grepl("2\\.5-flash-lite", id)) {
    c(minimal = 512L, low = 2048L, medium = 8192L, high = 24576L)
  } else if (grepl("2\\.5-flash", id)) {
    c(minimal = 128L, low = 2048L, medium = 8192L, high = 24576L)
  } else {
    NULL
  }
  if (is.null(tab) || !(lv %in% names(tab))) -1L else tab[[lv]]
}

#' A Google error object -> class suffix, HTTP status and retryability (09 section 2.1)
#'
#' Only one string is read as a status and only one whole number from 100 to 599 (an HTTP
#' status) as a code; anything else (a bare string error, a vector, a list, a fraction or a number
#' outside that range) is never matched or coerced, so no integer overflow can warn (04 section
#' 8.1), and gives a provider error unless the status names another class.
#' @noRd
google_error_info = function(err) {
  if (!is.list(err)) err = list()
  st = responses_str(err[["status"]])
  code = err[["code"]]
  code = if (is.numeric(code) && length(code) == 1L && !is.na(code) && code >= 100 &&
               code <= 599 && code == round(code)) {
    as.integer(code)
  } else {
    NA_integer_
  }
  if (st == "RESOURCE_EXHAUSTED" || identical(code, 429L)) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if (st %in% c("UNAVAILABLE", "INTERNAL") || (!is.na(code) && code >= 500L)) {
    return(list(class = "overloaded", status = if (is.na(code)) 503L else code, retry = TRUE))
  }
  if (st %in% c("UNAUTHENTICATED", "PERMISSION_DENIED")) {
    return(list(class = "auth", status = if (is.na(code)) 401L else code, retry = FALSE))
  }
  list(class = "provider", status = code, retry = FALSE)
}

#' Record a Gemini usageMetadata object (09 section 2.1; Pi google-generative-ai.ts:232-251)
#'
#' `promptTokenCount` includes the cached content and thoughts are billed as output, so input is
#' the prompt minus the cache reads and output the candidates plus the thoughts. Each report
#' replaces the last (the counts are totals). A field the provider left out keeps P05's legacy
#' zero, a reported null or a value that is not a nonnegative number is unknown (NA, IC-74), and
#' `"usageMetadata": null` is no report (D-022, D-027).
#' @noRd
google_usage = function(st, u) {
  if (!is.list(u)) return(invisible(NULL))
  cached = completions_first(completions_count(u, "cachedContentTokenCount"))
  thoughts = completions_first(completions_count(u, "thoughtsTokenCount"))
  prompt = completions_first(completions_count(u, "promptTokenCount"))
  output = completions_first(completions_count(u, "candidatesTokenCount"))
  st$usage = list(input = prompt - cached, output = output + thoughts, cache_read = cached,
                  reasoning = thoughts)
  invisible(NULL)
}

#' The google-generative-ai normaliser (04 section 8.1; Pi google-generative-ai.ts:106-278)
#'
#' Parts with `thought: true` stream as thinking and other text parts as text; a thought
#' signature stays on the block its part belongs to (the last non-empty one of a streamed block),
#' so a signature on an empty text part attaches to the open text block or opens an empty one.
#' Function calls arrive whole: the arguments are one delta and the block closes at once, with
#' the call's own signature; a missing or repeated call id is generated as
#' `<name>_<response id fragment>_<n>`, n the call's position or the next number whose id is not
#' yet in the message. `STOP` is `stop` (`tool_use` with calls), `MAX_TOKENS` is `length`, every
#' other finish reason, a blocked prompt or a stream without a finish reason ends in one `error`
#' event; error chunks are retryable before any delta.
#' @param model A model record (contract section 4.9).
#' @param opts The adapter options of contract section 8.1 (`emit`, `retry`, `signal`).
#' @return A list of functions `push`, `finish`, `fail`, `message`.
#' @noRd
google_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  cur = new.env(parent = emptyenv())
  cur$open = NULL
  cur$calls = 0L
  cur$finish = FALSE

  close_open = function() {
    if (!is.null(cur$open)) adp_close(st, cur$open)
    cur$open = NULL
  }

  on_text = function(p) {
    kind = if (isTRUE(p[["thought"]])) "thinking" else "text"
    if (is.null(cur$open) || st$blocks[[cur$open]]$type != kind) {
      close_open()
      cur$open = adp_open(st, kind)
    }
    adp_delta(st, cur$open, p[["text"]])
    sig = responses_str(p[["thoughtSignature"]])
    if (nzchar(sig)) {
      b = st$blocks[[cur$open]]
      b$signature = sig
    }
  }

  on_call = function(p) {
    close_open()
    fc = p[["functionCall"]]
    cur$calls = cur$calls + 1L
    name = responses_str(fc[["name"]])
    seen = vapply(Filter(function(b) identical(b$type, "tool_call"), st$blocks),
                  function(b) adp_chr(b$id), "")
    id = responses_str(fc[["id"]])
    if (!nzchar(id) || id %in% seen) {
      frag = substr(gsub("[^A-Za-z0-9]", "", st$response_id %||% ""), 1L, 12L)
      if (!nzchar(frag)) frag = "x"
      prefix = if (nzchar(name)) gsub("[^A-Za-z0-9_-]", "_", name) else "call"
      n = cur$calls
      id = paste0(prefix, "_", frag, "_", n)
      while (id %in% seen) {
        n = n + 1L
        id = paste0(prefix, "_", frag, "_", n)
      }
    }
    args = fc[["args"]]
    if (!adp_is_object(args) || !length(args)) args = json_obj()
    sig = responses_str(p[["thoughtSignature"]])
    i = adp_open(st, "tool_call", id = id, name = name, args = args,
                 thought_signature = if (nzchar(sig)) sig)
    adp_delta(st, i, json_encode(args))
    adp_close(st, i)
  }

  on_finish = function(fr, detail) {
    cur$finish = TRUE
    raw = adp_chr(fr)
    st$raw_stop = if (nzchar(raw)) raw
    reason = responses_str(fr)
    has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
    st$stop_reason = if (reason == "STOP") {
      if (has_tool) "tool_use" else "stop"
    } else if (reason == "MAX_TOKENS") {
      "length"
    } else {
      "error"
    }
    st$error_message = NULL
    if (identical(st$stop_reason, "error")) {
      detail = responses_str(detail)
      st$error_message = paste0("Provider stopped with: ", if (nzchar(raw)) raw else "unknown",
                                if (nzchar(detail)) paste0(": ", detail))
    }
  }

  on_error = function(err) {
    info = google_error_info(err)
    if (!is.list(err)) err = list(message = err)
    status = responses_str(err[["status"]])
    message = responses_str(err[["message"]])
    text = paste0(if (nzchar(status)) status else "error", ": ",
                  if (nzchar(message)) message else "unknown error")
    adp_stream_error(st, opts, text, class = info$class, status = info$status,
                     retryable = info$retry)
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = responses_str(ev[["data"]])
    if (!nzchar(trimws(data))) return(FALSE)
    ch = adp_json_try(data)
    if (!adp_is_object(ch)) {
      adp_error(st, paste0("Could not parse a Gemini stream chunk: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    if (!is.null(ch[["error"]])) return(on_error(ch[["error"]]))
    rid = responses_str(ch[["responseId"]])
    if (is.null(st$response_id) && nzchar(rid)) st$response_id = rid
    mv = responses_str(ch[["modelVersion"]])
    if (nzchar(mv) && !identical(mv, model$id)) st$response_model = mv
    google_usage(st, ch[["usageMetadata"]])
    cands = ch[["candidates"]]
    cand = if (is.list(cands) && length(cands)) cands[[1L]]
    if (!adp_is_object(cand)) {
      fb = ch[["promptFeedback"]]
      reason = if (is.list(fb)) adp_chr(fb[["blockReason"]]) else ""
      if (nzchar(reason)) {
        adp_error(st, paste0("The prompt was blocked: ", reason), class = "provider")
        return(TRUE)
      }
      return(FALSE)
    }
    content = cand[["content"]]
    parts = if (is.list(content)) content[["parts"]]
    if (!is.list(parts)) parts = list()
    for (p in parts) {
      if (!adp_is_object(p)) next
      text = p[["text"]]
      if (is.character(text) && length(text) == 1L && !is.na(text)) on_text(p)
      if (adp_is_object(p[["functionCall"]])) on_call(p)
    }
    fr = cand[["finishReason"]]
    if (!is.null(fr)) on_finish(fr, cand[["finishMessage"]])
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    close_open()
    if (!cur$finish) {
      return(adp_error(st, "The Google stream ended without a finish reason.",
                       class = "network"))
    }
    adp_done(st)
  }

  adp_normaliser(st, push, finish)
}

# ---- google-generative-ai: request body --------------------------------------------------------

#' Adapter capabilities of google-generative-ai (04 section 8.1; IC-69, IC-71)
#' @noRd
google_caps = function() {
  list(images_in_results = TRUE, tool_addition = FALSE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("labels", "service_tier"), operator_role = "user", cache = "gemini",
       max_tool_name = 128L, tool_shape = "gemini")
}

#' Remove the JSON Schema keywords Gemini rejects in parametersJsonSchema
#' @noRd
google_schema = function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x))) x = x[!(names(x) %in% c("$schema", "$id", "$comment"))]
  if (length(x)) x[] = lapply(x, google_schema)
  x
}

#' A Gemini inlineData part, or a text note for a text-only model
#' @noRd
google_image = function(b, images) {
  if (!images) return(list(text = adp_image_note()))
  list(inlineData = list(mimeType = b$mime, data = b$data))
}

#' The Gemini content of a user message
#' @noRd
google_user = function(m, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      parts[[length(parts) + 1L]] = list(text = b$text)
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = google_image(b, images)
    }
  }
  if (!length(parts)) return(NULL)
  list(role = "user", parts = parts)
}

#' The Gemini model content of an assistant message; thought signatures stay on the part they
#' arrived on and are replayed only to the same model (09 section 2.1)
#' @noRd
google_assistant = function(m, model) {
  same = adp_same_model(m, model)
  needs_id = google_needs_id(model$id)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    p = NULL
    if (type == "text") {
      sig = if (same && google_valid_sig(b$signature)) b$signature else NULL
      if (nzchar(trimws(b$text)) || !is.null(sig)) p = list(text = b$text)
      if (!is.null(p) && !is.null(sig)) p$thoughtSignature = sig
    } else if (type == "thinking") {
      sig = if (same && google_valid_sig(b$signature)) b$signature else NULL
      if (nzchar(trimws(b$thinking)) || !is.null(sig)) {
        p = if (same) list(thought = TRUE, text = b$thinking) else list(text = b$thinking)
        if (!is.null(sig)) p$thoughtSignature = sig
      }
    } else if (type == "tool_call") {
      sig = if (same && google_valid_sig(b$thought_signature)) b$thought_signature else NULL
      fc = list(name = b$name, args = if (length(b$arguments)) b$arguments else json_obj())
      if (needs_id) fc$id = adp_sanitize_id(b$id)
      p = c(list(functionCall = fc), if (!is.null(sig)) list(thoughtSignature = sig))
    }
    if (!is.null(p)) parts[[length(parts) + 1L]] = p
  }
  if (!length(parts)) return(NULL)
  list(role = "model", parts = parts)
}

#' The Gemini contents of a group of tool results: one user content of functionResponse parts;
#' images inside functionResponse.parts on Gemini 3+, else a following user content. A model
#' without image input gets the omission note in the result's output, once per image, and no
#' image content (D-023 item 4, D-029.3)
#' @noRd
google_tool_results = function(group, model) {
  needs_id = google_needs_id(model$id)
  v3 = isTRUE(google_major(model$id) >= 3L)
  images = adp_images_ok(model)
  parts = list()
  extra = list()
  for (r in group) {
    txt = paste(vapply(Filter(function(b) identical(b$type, "text"), r$content),
                       function(b) b$text, ""), collapse = "\n")
    imgs = Filter(function(b) identical(b$type, "image"), r$content)
    if (length(imgs) && !images) {
      txt = paste(c(txt[nzchar(txt)], rep(adp_image_note(), length(imgs))), collapse = "\n")
      imgs = list()
    }
    fr = list(name = r$tool_name,
              response = if (isTRUE(r$is_error)) list(error = txt) else list(output = txt))
    if (needs_id) fr$id = adp_sanitize_id(r$tool_call_id)
    imgs = lapply(imgs, google_image, images = images)
    if (length(imgs) && v3) fr$parts = imgs
    if (length(imgs) && !v3) extra = c(extra, imgs)
    parts[[length(parts) + 1L]] = list(functionResponse = fr)
  }
  out = list(list(role = "user", parts = parts))
  if (length(extra)) {
    out[[2L]] = list(role = "user", parts = c(list(list(text = "Tool result image:")), extra))
  }
  out
}

#' The generationConfig of a request: maxOutputTokens, temperature and thinkingConfig
#' (thinkingLevel for Gemini 3.x, thinkingBudget for 2.5; 09 sections 2.1 and 4.5)
#' @noRd
google_generation = function(model, params) {
  gen = json_obj()
  if (!is.null(params$max_tokens)) gen$maxOutputTokens = as.integer(params$max_tokens)
  if (!is.null(params$temperature)) gen$temperature = params$temperature
  if (!isTRUE(model$reasoning)) return(gen)
  level = params$thinking
  if (google_uses_level(model$id)) {
    if (is.null(level)) {
      gen$thinkingConfig = list(includeThoughts = TRUE)
    } else if (identical(level, "off")) {
      low = if ("minimal" %in% unlist(model$thinking_levels)) "MINIMAL" else "LOW"
      gen$thinkingConfig = list(thinkingLevel = low)
    } else {
      lv = if (level %in% c("xhigh", "max")) "high" else level
      gen$thinkingConfig = list(includeThoughts = TRUE, thinkingLevel = toupper(lv))
    }
  } else if (identical(level, "off")) {
    gen$thinkingConfig = list(thinkingBudget = 0L)
  } else {
    budget = if (is.null(level)) -1L else google_budget(model$id, level)
    gen$thinkingConfig = list(includeThoughts = TRUE, thinkingBudget = budget)
  }
  gen
}

#' build() of the google-generative-ai adapter (04 section 8.1; G4 section 3.7:
#' systemInstruction, tools, toolConfig, generationConfig, contents; implicit caching only)
#'
#' The provider headers come from the provider record provider_stream() resolved (`opts$provider`,
#' the session's own record first) and are merged by name, so a record never repeats or
#' replaces an adapter header or the key (D-023). Tools and toolConfig go only to a model that
#' calls tools (`tool_call`; IC-74, 07-local-ollama.md section 1; D-029, D-032), and toolConfig
#' only with a tools array.
#' @noRd
google_build = function(model, context, opts) {
  params = context$params %||% list()
  msgs = context$messages %||% list()
  images = adp_images_ok(model)
  tools_on = !isFALSE(model[["tool_call"]])
  head = json_obj()
  sys = list()
  for (k in c("t0", "t1")) {
    txt = context$system[[k]] %||% ""
    if (nzchar(txt)) sys[[length(sys) + 1L]] = list(text = txt)
  }
  if (length(sys)) head$systemInstruction = list(parts = sys)
  extra = character()
  tj = if (tools_on) adp_tools_json(opts, "google", context$tools_json, function(tools) {
    decl = lapply(tools, function(t) {
      list(name = t$name, description = t$description %||% "",
           parametersJsonSchema = google_schema(t$input_schema))
    })
    list(list(functionDeclarations = decl))
  })
  if (!is.null(tj)) {
    extra = c(extra, paste0("\"tools\":", tj))
    tc = params$tool_choice
    fcc = if (identical(tc, "none")) {
      list(mode = "NONE")
    } else if (adp_forced(tc) && adp_forced_ok(model, google_caps()) && is.null(params$returns)) {
      if (identical(tc$type, "any")) list(mode = "ANY") else
        list(mode = "ANY", allowedFunctionNames = list(tc$name))
    } else {
      list(mode = "AUTO")
    }
    extra = c(extra, paste0("\"toolConfig\":", json_encode(list(functionCallingConfig = fcc))))
  }
  gen = google_generation(model, params)
  if (length(gen)) extra = c(extra, paste0("\"generationConfig\":", json_encode(gen)))
  if (!is.null(params$labels)) extra = c(extra, paste0("\"labels\":", json_encode(params$labels)))
  if (!is.null(params$service_tier)) {
    extra = c(extra, paste0("\"serviceTier\":", json_encode(params$service_tier)))
  }

  elements = character()
  n = length(msgs)
  i = 1L
  while (i <= n) {
    m = msgs[[i]]
    r = m$role %||% ""
    if (r == "tool_result") {
      j = i
      while (j <= n && identical(msgs[[j]]$role, "tool_result")) j = j + 1L
      group = msgs[i:(j - 1L)]
      key = paste(c("google", "results", model$id, images, vapply(group, adp_msg_key, "")),
                  collapse = "|")
      el = adp_memo(opts, key, function() {
        paste(vapply(google_tool_results(group, model), json_encode, ""), collapse = ",")
      })
      elements = c(elements, el)
      i = j
      next
    }
    same = adp_same_model(m, model)
    key = paste("google", r, adp_msg_key(m), same, model$id, images, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (r == "user") x = google_user(m, images)
      if (r == "assistant") x = google_assistant(m, model)
      if (r == "operator") {
        txt = adp_operator_text(m)
        if (nzchar(txt)) x = list(role = "user", parts = list(list(text = txt)))
      }
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) elements = c(elements, el)
    i = i + 1L
  }
  if (!is.null(params$returns)) {
    text = adp_returns_instruction(params$returns)
    elements = c(elements, json_encode(list(role = "user", parts = list(list(text = text)))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  if (!is.null(opts$credential)) headers$`x-goog-api-key` = adp_header_secret(opts$credential)
  headers = adp_merge_headers(headers, adp_provider_headers(model, opts), auth = "x-goog-api-key")
  path = paste0("models/", model$id, ":streamGenerateContent?alt=sse")
  list(url = adp_url(opts$base_url %||% "https://generativelanguage.googleapis.com/v1beta", path),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "contents", elements), stream = "sse")
}

#' builtin:google: registers the google-generative-ai adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_google = function(gptr) {
  gptr$register(gptr_adapter("google-generative-ai", transport = "http_sse",
                             build = google_build, parse = google_normaliser,
                             capabilities = google_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("google", builtin_google))
