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
