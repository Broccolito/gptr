# The anthropic-messages adapter (P12), the normaliser core shared by the four native adapters,
# and check_adapter(), the check.adapter service of gptr_check() (stream and classifier fixtures;
# IC-74, FIX-6). Contract 04 sections 4.1-4.5, 7.12, 8.1, IC-69/IC-71. Request bodies follow G4
# 3.7 (key order, breakpoints) and 5.4 (pieces serialised once per session through opts$memo).

# ---- shared normaliser core -----------------------------------------------------------------

#' A growable chunk buffer: deltas are appended to a preallocated list and joined once
#' @noRd
adp_buffer = function() {
  b = new.env(parent = emptyenv())
  b$v = vector("list", 32L)
  b$n = 0L
  b
}

#' Append one chunk to a buffer (the list doubles when full)
#' Take-out form: `b$v[[n]] = x` on a still-bound list copies it every call (quadratic, INFRA-23).
#' @noRd
adp_buffer_add = function(b, x) {
  n = b$n + 1L
  v = b$v
  b$v = NULL
  if (n > length(v)) length(v) = 2L * length(v)
  v[[n]] = x
  b$v = v
  b$n = n
  invisible(NULL)
}

#' The joined text of a buffer
#' @noRd
adp_buffer_text = function(b) {
  if (b$n == 0L) return("")
  paste(unlist(b$v[seq_len(b$n)], use.names = FALSE), collapse = "")
}

#' The state of one normaliser: content slots, stop reason, usage and the terminal flag
#' @noRd
adp_state = function(model, opts) {
  st = new.env(parent = emptyenv())
  st$model = model
  st$emit_fun = opts$emit
  st$signal = opts$signal
  st$blocks = list()
  st$n = 0L
  st$started = FALSE
  st$terminal = FALSE
  st$deltas = FALSE
  st$pending = NULL
  st$stop_reason = NULL
  st$raw_stop = NULL
  st$error_message = NULL
  st$response_id = NULL
  st$response_model = NULL
  st$usage = list()
  st$final = NULL
  st
}

#' Emit one INFRA-02 event (contract section 4.5) through opts$emit
#' @noRd
adp_emit = function(st, type, ...) {
  if (is.function(st$emit_fun)) st$emit_fun(ev_new(type, ...))
  invisible(NULL)
}

#' Emit the start event once, before the first content event or the terminal event
#' @noRd
adp_start = function(st) {
  if (st$started) return(invisible(NULL))
  st$started = TRUE
  m = st$model
  adp_emit(st, "start", api = m$api, provider = m$provider, model = m$id, request_id = NULL,
           response_id = st$response_id)
}

#' Open a content slot (text, thinking, tool_call or opaque) and emit its start event
#' @noRd
adp_open = function(st, type, ...) {
  adp_start(st)
  b = new.env(parent = emptyenv())
  b$type = type
  b$buf = adp_buffer()
  b$done = FALSE
  b$block = NULL
  fields = list(...)
  for (k in names(fields)) assign(k, fields[[k]], envir = b)
  st$n = st$n + 1L
  st$blocks[[st$n]] = b
  i = st$n
  if (type %in% c("text", "thinking")) {
    adp_emit(st, paste0(type, "_start"), index = i)
  } else if (type == "tool_call") {
    adp_emit(st, "toolcall_start", index = i, id = b$id, name = b$name)
  }
  i
}

#' Append a delta to slot i and emit the matching *_delta event (empty deltas are dropped)
#' @noRd
adp_delta = function(st, i, text) {
  if (is.null(text) || !nzchar(text)) return(invisible(NULL))
  b = st$blocks[[i]]
  adp_buffer_add(b$buf, text)
  if (b$type == "opaque") return(invisible(NULL))
  st$deltas = TRUE
  if (b$type == "tool_call") {
    preview = NULL
    if (!is.null(b$pj)) {
      b$pj$push(text)
      preview = b$pj$preview()
    }
    adp_emit(st, "toolcall_delta", index = i, delta = text, preview = preview)
  } else {
    adp_emit(st, paste0(b$type, "_delta"), index = i, delta = text)
  }
}

#' Parse JSON text, NULL when it is empty or not valid JSON
#' @noRd
adp_json_try = function(text) {
  if (is.null(text) || !is.character(text) || !nzchar(text)) return(NULL)
  tryCatch(json_decode(text), error = function(e) NULL)
}

#' Is x a JSON object (a named list, possibly empty)?
#' @noRd
adp_is_object = function(x) is.list(x) && (length(x) == 0L || !is.null(names(x)))

#' A provider value as one string ("" for NULL, NA or a non-scalar)
#' @noRd
adp_chr = function(x) {
  if (is.null(x) || !is.atomic(x) || length(x) != 1L || is.na(x)) return("")
  as.character(x)
}

#' The content block of slot b, final or partial (contract section 4.1)
#' @noRd
adp_block = function(st, b) {
  m = st$model
  if (b$type == "text") {
    return(block_text(b$text_override %||% adp_buffer_text(b$buf), signature = b$signature))
  }
  if (b$type == "thinking") {
    sig = b$signature
    if (!is.null(sig) && !nzchar(sig)) sig = NULL
    return(block_thinking(b$text_override %||% adp_buffer_text(b$buf), signature = sig,
                          redacted = isTRUE(b$redacted), data = b$data,
                          origin = list(api = m$api, provider = m$provider, model = m$id)))
  }
  if (b$type == "tool_call") {
    raw_keep = NULL
    if (!is.null(b$args)) {
      args = b$args
    } else {
      raw = b$raw_override %||% adp_buffer_text(b$buf)
      parsed = adp_json_try(raw)
      if (!nzchar(raw)) {
        args = json_obj()
      } else if (adp_is_object(parsed)) {
        args = parsed
      } else {
        args = json_obj()
        raw_keep = raw
      }
    }
    if (length(args) == 0L) args = json_obj()
    id = adp_chr(b$id)
    if (!nzchar(id)) id = paste0("call_", b$slot %||% 0L)
    name = adp_chr(b$name)
    if (!nzchar(name)) name = "unknown_tool"
    return(block_tool_call(id, name, args, raw_arguments = raw_keep,
                           thought_signature = b$thought_signature))
  }
  if (is.null(b$json)) return(NULL)
  block_opaque(provider = m$provider, api = m$api, model = m$id, json = b$json)
}

#' Close slot i: build its final block and emit the *_end event
#' @noRd
adp_close = function(st, i) {
  b = st$blocks[[i]]
  if (b$done) return(invisible(b$block))
  b$slot = i
  b$block = adp_block(st, b)
  b$done = TRUE
  if (b$type == "tool_call") {
    adp_emit(st, "toolcall_end", index = i, block = b$block)
  } else if (b$type %in% c("text", "thinking")) {
    adp_emit(st, paste0(b$type, "_end"), index = i, block = b$block)
  }
  invisible(b$block)
}

#' Finalise an opaque slot from its JSON text (no event: opaque data is never streamed)
#' @noRd
adp_set_opaque = function(st, i, json) {
  b = st$blocks[[i]]
  b$json = json
  b$slot = i
  b$block = adp_block(st, b)
  b$done = TRUE
  invisible(b$block)
}

#' A provider token count as a number: NA unless it is one finite nonnegative number
#' @noRd
adp_count = function(x) {
  ok = is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0
  if (ok) as.numeric(x) else NA_real_
}

#' One count of a reported usage object: NULL when the field is left out, else adp_count()
#' @noRd
adp_count_at = function(x, key) {
  if (!is.list(x) || !(key %in% names(x))) return(NULL)
  adp_count(x[[key]])
}

#' The first known of several reported counts: NA when only unknown ones were reported, P05's
#' legacy zero when none was (D-022)
#' @noRd
adp_first = function(...) {
  vals = Filter(Negate(is.null), list(...))
  if (!length(vals)) return(0)
  known = Filter(Negate(is.na), vals)
  if (length(known)) known[[1L]] else NA_real_
}

#' Record an OpenAI usage object: Chat Completions (`prompt`/`completion` tokens, cache hits also
#' under `hits`) or Responses (`input`/`output`); input excludes cache reads and writes, each
#' report replaces the last and a null stays NA (IC-74; Pi parseChunkUsage, 08 section 3.3)
#' @noRd
adp_openai_usage = function(st, u, input, output, hits = character()) {
  if (!is.list(u)) return(invisible(NULL))
  details = u[[paste0(input, "_tokens_details")]]
  cached = do.call(adp_first, c(list(adp_count_at(details, "cached_tokens")),
                                lapply(hits, adp_count_at, x = u)))
  cwrite = adp_first(adp_count_at(details, "cache_write_tokens"))
  prompt = adp_first(adp_count_at(u, paste0(input, "_tokens")))
  reasoning = adp_count_at(u[[paste0(output, "_tokens_details")]], "reasoning_tokens")
  st$usage = list(input = max(0, prompt - cached - cwrite),
                  output = adp_first(adp_count_at(u, paste0(output, "_tokens"))),
                  cache_read = cached, cache_write_5m = cwrite, reasoning = adp_first(reasoning))
  invisible(NULL)
}

#' An HTTP status in a provider error code: a whole number in 100..599, never coerced (D-034)
#' @noRd
adp_http_status = function(code) {
  ok = is.numeric(code) && length(code) == 1L && !is.na(code) && code >= 100 && code <= 599 &&
    code == round(code)
  if (ok) as.integer(code) else NA_integer_
}

#' Record one reported usage field: a value replaces the earlier one; a null keeps it and is NA
#' (IC-74) only when nothing was recorded before
#' @noRd
adp_usage_set = function(st, field, value) {
  if (!is.null(value)) {
    st$usage[[field]] = value
  } else if (!(field %in% names(st$usage))) {
    st$usage[[field]] = NA_real_
  }
  invisible(NULL)
}

#' The usage record of contract section 4.3 from the provider-reported numbers, with cost
#' No report, null or invalid is NA (IC-74); an absent field keeps the legacy zero. Cost comes
#' only from dated price evidence (`usage_cost()`).
#' @noRd
adp_usage = function(st) {
  u = st$usage
  rec = if (!length(u)) {
    usage_as(NULL)
  } else {
    num = function(k) if (k %in% names(u)) adp_count(u[[k]]) else 0
    usage_new(input = num("input"), output = num("output"), cache_read = num("cache_read"),
              cache_write_5m = num("cache_write_5m"), cache_write_1h = num("cache_write_1h"),
              reasoning = num("reasoning"))
  }
  tryCatch(usage_cost(rec, st$model), error = function(e) {
    rec$cost = cost_unknown()
    rec
  })
}

#' The current assistant message (materialised on demand, never per delta)
#' @noRd
adp_message = function(st) {
  if (!is.null(st$final)) return(st$final)
  m = st$model
  content = list()
  for (i in seq_len(st$n)) {
    b = st$blocks[[i]]
    b$slot = i
    blk = if (b$done) b$block else adp_block(st, b)
    if (!is.null(blk)) content[[length(content) + 1L]] = blk
  }
  msg_assistant(content, api = m$api, provider = m$provider, model = m$id, usage = adp_usage(st),
                stop_reason = st$stop_reason %||% "stop", response_id = st$response_id,
                response_model = st$response_model, error_message = st$error_message,
                raw_stop_reason = st$raw_stop, route = stream_route(m))
}

#' Emit the one terminal error event with the partial message
#' @noRd
adp_error = function(st, message, class = "provider", status = NA_integer_, retry_after = NULL,
                     aborted = FALSE) {
  if (st$terminal) return(st$final)
  if (length(status) != 1L || is.na(status)) status = NULL
  st$stop_reason = if (aborted) "aborted" else "error"
  st$error_message = message
  m = st$model
  msg = tryCatch(adp_message(st), error = function(e) {
    msg_assistant(list(), api = m$api, provider = m$provider, model = m$id,
                  stop_reason = st$stop_reason, error_message = message, route = stream_route(m))
  })
  st$final = msg
  st$terminal = TRUE
  adp_start(st)
  adp_emit(st, "error", reason = st$stop_reason, message = msg,
           error = list(class = class, status = status, request_id = NULL,
                        retry_after = retry_after))
  msg
}

#' Close open slots and emit the terminal event: done, or error for an error stop reason
#' A `stop` with a tool call is `tool_use` (04 section 4.2).
#' @noRd
adp_done = function(st) {
  if (st$terminal) return(st$final)
  calls = FALSE
  for (i in seq_len(st$n)) {
    b = st$blocks[[i]]
    calls = calls || b$type == "tool_call"
    if (!b$done && b$type != "opaque") adp_close(st, i)
  }
  if (is.null(st$stop_reason)) {
    return(adp_error(st, "The stream ended without a stop reason.", class = "network"))
  }
  if (calls && identical(st$stop_reason, "stop")) st$stop_reason = "tool_use"
  if (st$stop_reason %in% c("error", "aborted")) {
    return(adp_error(st, st$error_message %||% "The provider reported an error.",
                     aborted = identical(st$stop_reason, "aborted")))
  }
  msg = adp_message(st)
  st$final = msg
  st$terminal = TRUE
  adp_start(st)
  adp_emit(st, "done", reason = msg$stop_reason, message = msg, usage = msg$usage)
  msg
}

#' A failure seen inside the stream: ask the transport to retry while no delta was committed
#' (04 section 8.1, `retry(info)`), otherwise end the stream with the error event
#' @noRd
adp_stream_error = function(st, opts, message, class, status = NA_integer_, retry_after = NULL,
                            retryable = FALSE) {
  if (retryable && !st$deltas && is.function(opts$retry)) {
    st$pending = list(message = message, class = class, status = status,
                      retry_after = retry_after)
    opts$retry(list(class = class, status = status, retry_after = retry_after))
    return(isTRUE(st$terminal))
  }
  adp_error(st, message, class = class, status = status, retry_after = retry_after)
  TRUE
}

#' End of input after a retry request the transport did not act on
#' @noRd
adp_finish_pending = function(st) {
  p = st$pending
  adp_error(st, p$message, class = p$class, status = p$status, retry_after = p$retry_after)
}

#' The normaliser's fail(cnd): the one terminal error event (after a dropped retry request, the
#' provider's own error text)
#' @noRd
adp_fail = function(st, cnd) {
  if (st$terminal) return(st$final)
  if (!is.null(st$pending) && !isTRUE(st$signal$aborted)) return(adp_finish_pending(st))
  cls = sub("^gptr_error_", "", class(cnd)[[1L]])
  adp_error(st, conditionMessage(cnd), class = cls, status = cnd[["status"]] %||% NA_integer_,
            retry_after = cnd[["retry_after"]], aborted = isTRUE(st$signal$aborted))
}

#' Run one normaliser step; an R error inside it ends the stream with the one terminal error
#' event instead of escaping (04 section 8.1: no R condition after `start`)
#' @noRd
adp_guard = function(st, f) {
  force(f)
  function(...) {
    tryCatch(f(...), error = function(e) {
      adp_error(st, paste0("The adapter could not process the stream: ", conditionMessage(e)),
                class = "internal")
      TRUE
    })
  }
}

#' The normaliser list of contract section 8.1; no function of it signals an R condition (an
#' error becomes the terminal error event; message() falls back to an empty error message)
#' @noRd
adp_normaliser = function(st, push, finish, push_parsed = NULL) {
  out = list(push = adp_guard(st, push),
             finish = function() {
               tryCatch(finish(), error = function(e) {
                 adp_error(st, paste0("The adapter could not finish the stream: ",
                                      conditionMessage(e)), class = "internal")
               })
             },
             fail = function(cnd) {
               tryCatch(adp_fail(st, cnd), error = function(e) {
                 adp_error(st, paste0("The adapter could not record a transport failure: ",
                                      conditionMessage(e)), class = "internal")
               })
             },
             message = function() {
               tryCatch(adp_message(st), error = function(e) {
                 m = st$model
                 msg_assistant(list(), api = m$api, provider = m$provider, model = m$id,
                               stop_reason = "error",
                               error_message = paste0("The partial message could not be built: ",
                                                      conditionMessage(e)),
                               route = stream_route(m))
               })
             })
  if (!is.null(push_parsed)) out$push_parsed = adp_guard(st, push_parsed)
  out
}

# ---- golden projection and fixture replay (tests and check_adapter()) -----------------------

#' Golden projection of a content block: the contract fields only (04 sections 4.1, 12.4)
#' @noRd
adp_golden_block = function(b) {
  keep = c("type", "text", "thinking", "signature", "redacted", "data", "id", "name", "arguments",
           "raw_arguments", "thought_signature", "json")
  out = b[intersect(keep, names(b))]
  if (identical(out$redacted, FALSE)) out$redacted = NULL
  out[!vapply(out, is.null, logical(1))]
}

#' Golden projection of an event: volatile fields (ts, session, run, preview) and the terminal
#' message are left out; the final message is compared on its own
#' @noRd
adp_golden_event = function(ev) {
  keep = c("type", "index", "id", "name", "delta", "reason", "response_id")
  out = ev[intersect(keep, names(ev))]
  out = out[!vapply(out, is.null, logical(1))]
  if (!is.null(ev$block)) out$block = adp_golden_block(ev$block)
  if (!is.null(ev$error)) out$error = list(class = ev$error$class, status = ev$error$status)
  out
}

#' Golden projection of a final assistant message (cost left out: it depends on prices); an
#' unknown count (NA, IC-74) is JSON null, as in the session file's usage (`usage_to_json()`)
#' @noRd
adp_golden_message = function(m) {
  u = m$usage
  n = function(x) if (length(x) == 1L && is.na(x)) NULL else x
  out = list(stop_reason = m$stop_reason, raw_stop_reason = m$raw_stop_reason,
             error_message = m$error_message, response_id = m$response_id,
             response_model = m$response_model, content = lapply(m$content, adp_golden_block),
             usage = list(input = n(u$input), output = n(u$output), cache_read = n(u$cache_read),
                          cache_write_5m = n(u$cache_write_5m),
                          cache_write_1h = n(u$cache_write_1h), reasoning = n(u$reasoning),
                          total = n(u$total)))
  out[!vapply(out, is.null, logical(1))]
}

#' Deterministic pseudo-random chunk sizes (1-17 bytes) from hash bits; RNG-free (IC-61)
#' @noRd
adp_chunk_sizes = function(key) {
  h = hash_sha256(key)
  as.integer(strtoi(substring(h, seq(1L, 63L, 2L), seq(2L, 64L, 2L)), 16L) %% 17L) + 1L
}

#' Split raw bytes into chunks of the given sizes (recycled)
#' @noRd
adp_split_raw = function(bytes, sizes) {
  out = list()
  pos = 1L
  k = 1L
  n = length(bytes)
  while (pos <= n) {
    end = min(n, pos + sizes[[(k - 1L) %% length(sizes) + 1L]] - 1L)
    out[[length(out) + 1L]] = bytes[pos:end]
    pos = end + 1L
    k = k + 1L
  }
  out
}

#' Events of a splitter's flush(): NULL, one event, or a list of events
#' @noRd
adp_flushed = function(fl) {
  if (is.null(fl) || !length(fl)) return(list())
  if (!is.null(names(fl))) list(fl) else fl
}

#' Replay fixture bytes through an adapter's normaliser in chunks of the given sizes, the way
#' provider_stream() does (P05): splitter -> push(); end of input -> finish()
#' @noRd
adp_replay = function(adapter, model, bytes, sizes) {
  log = new.env(parent = emptyenv())
  log$events = list()
  emit = function(ev) log$events[[length(log$events) + 1L]] = ev
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  opts = list(emit = emit, base_url = "http://127.0.0.1:1", signal = signal,
              send = function(obj) invisible(NULL))
  res = tryCatch({
    n = adapter$parse(model, opts)
    chunks = adp_split_raw(bytes, sizes)
    if (identical(adapter$transport, "http_json")) {
      n$push(list(data = raw_to_utf8(bytes), status = 200L, headers = list()))
    } else if (adapter$transport %in% c("http_ndjson", "process_jsonl")) {
      sp = ndjson_splitter()
      lines = character()
      for (chunk in chunks) lines = c(lines, sp$push(chunk))
      lines = c(lines, sp$flush())
      for (ln in lines[nzchar(lines)]) {
        if (identical(adapter$transport, "process_jsonl")) {
          n$push(list(data = ln, obj = json_decode(ln)))
        } else {
          n$push(list(data = ln))
        }
      }
    } else {
      sp = sse_splitter()
      for (chunk in chunks) for (ev in sp$push(chunk)) n$push(ev)
      for (ev in adp_flushed(sp$flush())) n$push(ev)
    }
    list(message = n$finish(), condition = NULL)
  }, error = function(e) list(message = NULL, condition = e))
  c(res, list(events = log$events))
}

#' The fixture model record (contract section 4.9 shape) of a `chat` or `classifier` model;
#' `<dir>/model.json` overrides fields
#' @noRd
adp_fixture_model = function(api, dir = NULL, type = "chat") {
  m = list(ref = "fixture/fixture-1", provider = "fixture", id = "fixture-1",
           name = "Fixture model", family = "fixture", api = api, type = type,
           release_date = NA_character_, context = 200000, max_output = 8192, reasoning = TRUE,
           thinking_levels = c("off", "low", "medium", "high"), thinking = NULL,
           input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
           cache_min = NA_real_,
           capabilities = list(mid_system = TRUE, tool_addition = TRUE, images_in_results = TRUE,
                               adaptive_thinking = TRUE, effort = TRUE),
           aliases = character(), status = "active", local = TRUE)
  f = if (is.null(dir)) "" else file.path(dir, "model.json")
  if (nzchar(f) && file.exists(f)) {
    over = json_decode(read_utf8(f)$text)
    for (k in names(over)) m[[k]] = over[[k]]
  }
  m
}

# ---- anthropic-messages: normaliser -----------------------------------------------------------

#' Anthropic stop reason -> gptr stop reason (contract section 4.2; report 07 section 2.10)
#' @noRd
anthropic_stop = function(reason) {
  if (!is.character(reason) || length(reason) != 1L) return("error")
  switch(reason,
         end_turn = , stop_sequence = "stop",
         max_tokens = , model_context_window_exceeded = "length",
         tool_use = "tool_use", pause_turn = "pause", refusal = "refusal",
         "error")
}

#' Anthropic error type -> class suffix (04 section 2.2), HTTP status and retryability
#' (report 07 section 2.11; the spend cap is never retried)
#' @noRd
anthropic_error_info = function(err) {
  type = adp_chr(err$type)
  if (identical(err$details$error_code, "enforced_spend_limit_reached")) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  switch(type,
         overloaded_error = list(class = "overloaded", status = 529L, retry = TRUE),
         api_error = list(class = "overloaded", status = 500L, retry = TRUE),
         timeout_error = list(class = "overloaded", status = 504L, retry = TRUE),
         rate_limit_error = list(class = "rate_limit", status = 429L, retry = TRUE),
         authentication_error = list(class = "auth", status = 401L, retry = FALSE),
         permission_error = list(class = "auth", status = 403L, retry = FALSE),
         billing_error = list(class = "provider", status = 402L, retry = FALSE),
         not_found_error = list(class = "provider", status = 404L, retry = FALSE),
         request_too_large = list(class = "provider", status = 413L, retry = FALSE),
         invalid_request_error = list(class = "provider", status = 400L, retry = FALSE),
         list(class = "provider", status = NA_integer_, retry = FALSE))
}

#' Copy Anthropic usage fields into the normaliser state (message_start, message_delta)
#' `[[` only: `$` would let `cache_creation` match `cache_creation_input_tokens` (07 5.2).
#' `message_delta` usage is cumulative, a null means "no update" (report 03 section 2.5.1).
#' @noRd
anthropic_usage = function(st, u) {
  if (!is.list(u)) return(invisible(NULL))
  take = function(field, key) {
    if (key %in% names(u)) adp_usage_set(st, field, u[[key]])
  }
  take("input", "input_tokens")
  take("output", "output_tokens")
  take("cache_read", "cache_read_input_tokens")
  cc = u[["cache_creation"]]
  keys = c(cache_write_5m = "ephemeral_5m_input_tokens",
           cache_write_1h = "ephemeral_1h_input_tokens")
  split = if (is.list(cc)) keys[keys %in% names(cc)] else character()
  if (length(split)) {
    st$cache_split = TRUE
    for (field in names(split)) adp_usage_set(st, field, cc[[split[[field]]]])
  } else if ("cache_creation_input_tokens" %in% names(u)) {
    anthropic_cache_total(st, u[["cache_creation_input_tokens"]])
  }
  details = u[["output_tokens_details"]]
  if (is.list(details) && "thinking_tokens" %in% names(details)) {
    adp_usage_set(st, "reasoning", details[["thinking_tokens"]])
  }
  invisible(NULL)
}

#' A bare `cache_creation_input_tokens` total (no `cache_creation` object in the same usage)
#' Without an earlier split it is all 5-minute writes (report 07 section 3.5); a split that does
#' not add up keeps its known 1-hour (else 5-minute) part and gives the rest to the other.
#' @noRd
anthropic_cache_total = function(st, value) {
  if (is.null(value)) {
    if (!isTRUE(st$cache_split)) adp_usage_set(st, "cache_write_5m", NULL)
    return(invisible(NULL))
  }
  total = adp_count(value)
  if (!isTRUE(st$cache_split) || is.na(total)) {
    st$usage[["cache_write_5m"]] = total
    return(invisible(NULL))
  }
  w5 = adp_count(st$usage[["cache_write_5m"]])
  w1 = adp_count(st$usage[["cache_write_1h"]])
  if (!is.na(w5) && !is.na(w1) && w5 + w1 == total) return(invisible(NULL))
  if (!is.na(w1)) {
    w1 = min(w1, total)
    st$usage[["cache_write_1h"]] = w1
    st$usage[["cache_write_5m"]] = total - w1
  } else if (!is.na(w5)) {
    w5 = min(w5, total)
    st$usage[["cache_write_5m"]] = w5
    st$usage[["cache_write_1h"]] = total - w5
  }
  invisible(NULL)
}

#' The Anthropic SSE normaliser (contract sections 7.12 and 8.1; report 07 section 5.1)
#' `push_parsed(obj)` takes already-parsed stream events (the claude CLI's `stream_event`, P20).
#' @noRd
anthropic_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  map = new.env(parent = emptyenv())
  seen = new.env(parent = emptyenv())
  seen$start = FALSE

  on_block_start = function(obj) {
    cb = obj$content_block
    type = cb$type %||% ""
    i = if (type == "text") {
      adp_open(st, "text")
    } else if (type == "thinking") {
      adp_open(st, "thinking", signature = cb$signature %||% "")
    } else if (type == "redacted_thinking") {
      adp_open(st, "thinking", redacted = TRUE, data = cb$data, signature = "")
    } else if (type == "tool_use") {
      adp_open(st, "tool_call", id = cb$id, name = cb$name, pj = partial_json())
    } else {
      adp_open(st, "opaque", raw_block = cb)
    }
    assign(as.character(obj$index), i, envir = map)
    if (type == "text") adp_delta(st, i, cb$text)
    if (type == "thinking") adp_delta(st, i, cb$thinking)
    FALSE
  }

  on_block_delta = function(obj) {
    i = map[[as.character(obj$index)]]
    if (is.null(i)) return(FALSE)
    b = st$blocks[[i]]
    d = obj$delta
    dt = d$type %||% ""
    if (dt == "text_delta" && b$type == "text") {
      adp_delta(st, i, d$text)
    } else if (dt == "thinking_delta" && b$type == "thinking") {
      adp_delta(st, i, d$thinking)
    } else if (dt == "signature_delta" && b$type == "thinking") {
      b$signature = paste0(b$signature %||% "", d$signature)
    } else if (dt == "input_json_delta" && b$type %in% c("tool_call", "opaque")) {
      adp_delta(st, i, d$partial_json)
    }
    FALSE
  }

  on_block_stop = function(obj) {
    i = map[[as.character(obj$index)]]
    if (is.null(i)) return(FALSE)
    b = st$blocks[[i]]
    if (b$type == "opaque") {
      cb = b$raw_block
      input = adp_json_try(adp_buffer_text(b$buf))
      if (adp_is_object(input)) cb$input = if (length(input)) input else json_obj()
      adp_set_opaque(st, i, json_encode(cb))
    } else {
      adp_close(st, i)
    }
    FALSE
  }

  on_message_delta = function(obj) {
    reason = obj$delta$stop_reason
    if (!is.null(reason)) {
      raw = adp_chr(reason)
      st$raw_stop = if (nzchar(raw)) raw
      st$stop_reason = anthropic_stop(reason)
      if (identical(reason, "refusal")) {
        st$error_message = obj$delta$stop_details$explanation %||% "The model declined to answer."
      } else if (identical(st$stop_reason, "error")) {
        st$error_message = paste0("Provider stopped with: ", raw)
      }
    }
    anthropic_usage(st, obj$usage)
    FALSE
  }

  on_error = function(obj) {
    info = anthropic_error_info(obj$error)
    msg = paste0(obj$error$type %||% "error", ": ", obj$error$message %||% "unknown error")
    adp_stream_error(st, opts, msg, class = info$class, status = info$status,
                     retryable = info$retry)
  }

  push_parsed = function(obj) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    type = obj$type %||% ""
    if (type == "message_start") {
      seen$start = TRUE
      m = obj$message
      st$response_id = m$id
      if (!is.null(m$model) && !identical(m$model, model$id)) st$response_model = m$model
      anthropic_usage(st, m$usage)
      return(FALSE)
    }
    if (type == "content_block_start") return(on_block_start(obj))
    if (type == "content_block_delta") return(on_block_delta(obj))
    if (type == "content_block_stop") return(on_block_stop(obj))
    if (type == "message_delta") return(on_message_delta(obj))
    if (type == "message_stop") {
      adp_done(st)
      return(TRUE)
    }
    if (type == "error") return(on_error(obj))
    FALSE
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = ev$data %||% ""
    if (!nzchar(data)) return(FALSE)
    obj = adp_json_try(data)
    if (!adp_is_object(obj)) {
      adp_error(st, paste0("Could not parse an Anthropic stream event: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    if (identical(ev$event, "error")) obj$type = "error"
    push_parsed(obj)
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    if (!seen$start) {
      return(adp_error(st, "The Anthropic stream ended before any event.", class = "network"))
    }
    adp_error(st, "The Anthropic stream ended before message_stop.", class = "network")
  }

  adp_normaliser(st, push, finish, push_parsed)
}

# ---- shared request helpers -------------------------------------------------------------------

#' A model capability: the record's `capabilities` entry, then a top-level field, then `default`
#' @noRd
adp_model_cap = function(model, name, default = FALSE) {
  v = model$capabilities[[name]] %||% model[[name]]
  if (is.null(v) || length(v) != 1L || is.na(v)) default else v
}

#' Does the model take image input? (images are otherwise replaced by a one-line note)
#' @noRd
adp_images_ok = function(model) "image" %in% unlist(model$input %||% "text")

#' The note sent in place of an image to a model without image input
#' @noRd
adp_image_note = function() "(image omitted: this model does not accept images)"

#' A header value that holds a secret handle; only http-request.R (P04) materialises it
#' @noRd
adp_header_secret = function(handle, prefix = "") {
  if (is.null(handle)) return(NULL)
  if (!nzchar(prefix)) return(handle)
  list(prefix, handle)
}

#' Join a base URL and a path with exactly one slash
#' @noRd
adp_url = function(base, path) paste0(sub("/+$", "", base), "/", sub("^/+", "", path))

#' The provider record of the model (D-023): `opts$provider` when it is the model's provider,
#' else the session's own record (`opts$session`), else the global one; NULL when none
#' @noRd
adp_provider_record = function(model, opts = NULL) {
  id = model$provider %||% ""
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(NULL)
  rec = opts[["provider"]]
  names_of = function(p) c(p[["id"]], p[["name"]], p[["aliases"]])
  if (is.list(rec) && id %in% names_of(rec)) return(rec)
  sid = opts[["session"]]
  scoped = if (is.null(sid)) NULL else registry_get("provider", id, session = sid)
  provider_effective(scoped) %||% provider_get(id)
}

#' The non-secret headers of the model's provider record (for example OpenRouter attribution)
#' @noRd
adp_provider_headers = function(model, opts = NULL) {
  h = adp_provider_record(model, opts)[["headers"]]
  if (is.null(h) || !length(h)) list() else as.list(h)
}

#' An adapter's own headers with a provider record's non-secret headers merged in (D-023)
#' Case-insensitive; the adapter's headers win except `lists` (tokens of both, adapter's first);
#' an `auth` header is dropped while the adapter sends a credential.
#' @noRd
adp_merge_headers = function(base, extra, lists = character(), auth = character()) {
  base = as.list(base)
  if (!length(extra)) return(base)
  extra = as.list(extra)
  low = tolower(names(extra))
  extra = extra[!duplicated(low, fromLast = TRUE)]
  lists = tolower(lists)
  auth = tolower(auth)
  has_cred = any(tolower(names(base)) %in% auth)
  tokens = function(x) {
    t = trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
    t[nzchar(t)]
  }
  for (k in names(extra)) {
    lk = tolower(k)
    v = extra[[k]]
    at = match(lk, tolower(names(base)))
    if (!is.na(at)) {
      own = base[[at]]
      if (lk %in% lists && is.character(own) && length(own) == 1L &&
            is.character(v) && length(v) == 1L && !is.na(v)) {
        base[[at]] = paste(unique(c(tokens(own), tokens(v))), collapse = ",")
      }
    } else if (!(has_cred && lk %in% auth)) {
      base[[k]] = v
    }
  }
  base
}

#' The instruction sent with `returns =` where no native structured output is used (IC-71)
#' @noRd
adp_returns_instruction = function(schema) {
  paste0("When your work is complete, reply with only a JSON value that matches this JSON ",
         "Schema, with no other text and no code fence: ", json_encode(schema))
}

#' Serialise once per session: the value stored in opts$memo under `key`, computed on a miss
#' @noRd
adp_memo = function(opts, key, fun) {
  memo = opts$memo
  if (!is.environment(memo)) return(fun())
  hit = get0(key, envir = memo, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  val = fun()
  assign(key, val, envir = memo)
  val
}

#' The memo key of a message: projected messages carry no entry id, so a hash of the fields
#' that reach the wire (timestamps, usage and details are left out so a rebuilt copy hits)
#' @noRd
adp_msg_key = function(msg) {
  keep = c("role", "content", "api", "provider", "model", "tool_call_id", "tool_name",
           "is_error", "kind", "tool_add")
  hash_xxh128(msg[intersect(keep, names(msg))])
}

#' The frozen tool array converted once per session for an api; NULL when there are no tools
#' @noRd
adp_tools_json = function(opts, api, tools_json, convert) {
  if (is.null(tools_json)) return(NULL)
  text = as.character(tools_json)
  key = paste(api, "tools", hash_xxh128(text), sep = "|")
  out = adp_memo(opts, key, function() {
    tools = json_decode(text)
    if (!length(tools)) "" else json_encode(convert(tools))
  })
  if (nzchar(out)) out else NULL
}

#' Does any projected message hold a tool call or a tool result?
#' @noRd
adp_has_tool_calls = function(msgs) {
  for (m in msgs) {
    if (identical(m$role, "tool_result")) return(TRUE)
    if (identical(m$role, "assistant")) {
      for (b in m$content) if (identical(b$type, "tool_call")) return(TRUE)
    }
  }
  FALSE
}

#' Consecutive messages as runs: a stretch of one of `roles` is one run, any other message its own
#' Each run is `list(at, role, msgs, after)`: first index, role, messages and the next role (NULL
#' at the end).
#' @noRd
adp_runs = function(msgs, roles) {
  n = length(msgs)
  out = list()
  i = 1L
  while (i <= n) {
    role = msgs[[i]]$role %||% ""
    j = i + 1L
    if (role %in% roles) while (j <= n && identical(msgs[[j]]$role, role)) j = j + 1L
    out[[length(out) + 1L]] = list(at = i, role = role, msgs = msgs[i:(j - 1L)],
                                   after = if (j <= n) msgs[[j]]$role %||% "")
    i = j
  }
  out
}

#' Index of the first user message that holds an anchored context block (the BP2 anchor)
#' @noRd
adp_anchor_index = function(msgs) {
  for (k in seq_along(msgs)) {
    m = msgs[[k]]
    if (!identical(m$role, "user")) next
    for (b in m$content) if (identical(b$type, "context") && isTRUE(b$anchor)) return(k)
  }
  0L
}

#' The text of an operator message
#' @noRd
adp_operator_text = function(m) {
  paste(vapply(m$content, function(b) b$text %||% "", ""), collapse = "\n")
}

#' The effort for a thinking level: `minimal` maps to `low`, `off` and NULL to none
#' @noRd
adp_level_effort = function(level) {
  if (is.null(level) || identical(level, "off")) return(NULL)
  if (identical(level, "minimal")) "low" else level
}

#' Thinking budget in tokens for budget-based models (report 03 section 5.5 defaults)
#' @noRd
adp_budget = function(level) {
  switch(level, minimal = 1024L, low = 2048L, medium = 8192L, 16384L)
}

#' Assemble a JSON body: the head fields, the extra members, then the growing array last
#' @noRd
adp_body = function(head, extra, key, elements) {
  h = json_encode(head)
  inner = substr(h, 2L, nchar(h) - 1L)
  parts = c(if (nzchar(inner)) inner, extra,
            paste0("\"", key, "\":[", paste(elements, collapse = ","), "]"))
  paste0("{", paste(parts, collapse = ","), "}")
}

#' The cache plan of the request context (04 section 8.1), or the Anthropic default
#' @noRd
adp_cache_plan = function(context) {
  context$cache_plan %||% list(anchors = c("t0", "project"), tail_ttl = "5m", key = NULL)
}

#' Is a tool_choice a forced choice (a list naming a tool, or `any`)?
#' @noRd
adp_forced = function(tc) {
  is.list(tc) && !((tc$type %||% "") %in% c("auto", "none"))
}

#' May a forced tool_choice be sent? Model capability first, then the adapter's (IC-71)
#' @noRd
adp_forced_ok = function(model, caps) {
  isTRUE(adp_model_cap(model, "forced_tool_choice", isTRUE(caps$forced_tool_choice)))
}

# ---- anthropic-messages: request body ---------------------------------------------------------

#' Adapter capabilities of anthropic-messages (04 section 8.1; IC-69, IC-71)
#' @noRd
anthropic_caps = function() {
  list(images_in_results = TRUE, tool_addition = TRUE, structured_output = TRUE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = FALSE,
       request_params = c("service_tier", "metadata"), operator_role = "system",
       cache = "anthropic", max_tool_name = 128L, tool_shape = "anthropic")
}

#' An Anthropic image content block (base64 source), or a text note for a text-only model
#' @noRd
anthropic_image = function(b, images) {
  if (!images) return(list(type = "text", text = adp_image_note()))
  list(type = "image", source = list(type = "base64", media_type = b$mime, data = b$data))
}

#' A user message; the anchored context block carries the 1 h BP2 marker
#' @noRd
anthropic_user = function(m, mark_anchor, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type == "text" && nzchar(trimws(b$text))) {
      parts[[length(parts) + 1L]] = list(type = "text", text = b$text)
    } else if (type == "context") {
      p = list(type = "text", text = b$text)
      if (mark_anchor && isTRUE(b$anchor)) p$cache_control = list(type = "ephemeral", ttl = "1h")
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = anthropic_image(b, images)
    }
  }
  if (!length(parts)) return(NULL)
  list(role = "user", content = parts)
}

#' An assistant message; signed thinking, redacted thinking and opaque blocks are replayed
#' byte for byte only to the model that produced them (INFRA-07)
#' @noRd
anthropic_assistant = function(m, model) {
  same = handoff_same_model(m, model)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    p = NULL
    if (type == "text") {
      if (nzchar(trimws(b$text))) p = list(type = "text", text = b$text)
    } else if (type == "thinking") {
      if (isTRUE(b$redacted)) {
        if (same && !is.null(b$data)) p = list(type = "redacted_thinking", data = b$data)
      } else if (same && nzchar(b$signature %||% "")) {
        p = list(type = "thinking", thinking = b$thinking, signature = b$signature)
      } else if (nzchar(trimws(b$thinking))) {
        p = list(type = "text", text = b$thinking)
      }
    } else if (type == "tool_call") {
      args = if (length(b$arguments)) b$arguments else json_obj()
      p = list(type = "tool_use", id = id_sanitize(b$id, 64L), name = b$name, input = args)
    } else if (type == "opaque") {
      if (same) p = json_verbatim(b$json)
    }
    if (!is.null(p)) parts[[length(parts) + 1L]] = p
  }
  if (!length(parts)) return(NULL)
  list(role = "assistant", content = parts)
}

#' One tool_result block: text first, images as native image blocks (acceptance 3)
#' Whitespace-only text blocks are left out (the Messages API refuses them).
#' @noRd
anthropic_tool_result = function(r, images) {
  content = list()
  has_text = FALSE
  for (b in r$content) {
    if (identical(b$type, "text") && nzchar(trimws(b$text))) {
      content[[length(content) + 1L]] = list(type = "text", text = b$text)
      has_text = TRUE
    } else if (identical(b$type, "image")) {
      content[[length(content) + 1L]] = anthropic_image(b, images)
    }
  }
  if (!has_text && images && length(content)) {
    content = c(list(list(type = "text", text = "(see attached image)")), content)
  }
  out = list(type = "tool_result", tool_use_id = id_sanitize(r$tool_call_id, 64L))
  if (length(content)) out$content = content
  if (isTRUE(r$is_error)) out$is_error = TRUE
  out
}

#' A run of operator messages as ONE message: a mid-conversation system message where the
#' placement rule allows it, else user text (G4 section 2.3; report 07 section 2.3)
#' @noRd
anthropic_operator = function(group, as_system, with_tools) {
  parts = list()
  for (m in group) {
    text = adp_operator_text(m)
    if (nzchar(text)) parts[[length(parts) + 1L]] = list(type = "text", text = text)
    if (!with_tools) next
    for (t in m$tool_add %||% list()) {
      def = list(name = t$name, description = t$description, input_schema = t$input_schema)
      parts[[length(parts) + 1L]] = list(type = "tool_addition",
                                         tool = list(type = "tool_definition", definition = def))
    }
  }
  if (!length(parts)) return(NULL)
  list(role = if (as_system) "system" else "user", content = parts)
}

#' The messages array elements (JSON text), each serialised once per session through opts$memo
#' `tail = TRUE`: a `returns` instruction follows, so a trailing operator run is user text.
#' @noRd
anthropic_elements = function(model, msgs, opts, anchors = "project", tail = FALSE) {
  out = character()
  betas = character()
  mid = isTRUE(adp_model_cap(model, "mid_system", FALSE))
  add_tools = isTRUE(adp_model_cap(model, "tool_addition", TRUE))
  images = adp_images_ok(model)
  anchor_at = if ("project" %in% anchors) adp_anchor_index(msgs) else 0L
  prev = "none"
  for (run in adp_runs(msgs, c("tool_result", "operator"))) {
    role = run$role
    group = run$msgs
    if (role == "tool_result") {
      key = paste(c("anthropic", "results", images, vapply(group, adp_msg_key, "")),
                  collapse = "|")
      el = adp_memo(opts, key, function() {
        json_encode(list(role = "user",
                         content = lapply(group, anthropic_tool_result, images = images)))
      })
      out = c(out, el)
      prev = "user"
      next
    }
    if (role == "operator") {
      nxt = run$after %||% (if (tail) "user" else "end")
      as_system = mid && identical(prev, "user") && nxt %in% c("assistant", "end")
      with_tools = as_system && add_tools &&
        any(vapply(group, function(op) length(op$tool_add) > 0L, logical(1)))
      if (with_tools) betas = c(betas, "inline-tools-2026-09-15")
      key = paste(c("anthropic", "operator", vapply(group, adp_msg_key, ""), as_system,
                    with_tools), collapse = "|")
      el = adp_memo(opts, key, function() {
        x = anthropic_operator(group, as_system, with_tools)
        if (is.null(x)) "" else json_encode(x)
      })
      if (nzchar(el)) {
        out = c(out, el)
        prev = if (as_system) "system" else "user"
      }
      next
    }
    m = group[[1L]]
    same = handoff_same_model(m, model)
    mark = identical(run$at, anchor_at)
    key = paste("anthropic", role, adp_msg_key(m), same, mark, images, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (role == "user") x = anthropic_user(m, mark, images)
      if (role == "assistant") x = anthropic_assistant(m, model)
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) {
      out = c(out, el)
      prev = role
    }
  }
  list(elements = out, betas = unique(betas), prev = prev, mid = mid)
}

#' Thinking, effort and budget of a request: adaptive models get adaptive thinking and an
#' effort, budget models `enabled` with a budget and the interleaved beta (07 section 2.6)
#' @noRd
anthropic_thinking = function(model, params) {
  out = list(thinking = NULL, effort = NULL, budget = NULL, betas = character())
  if (!isTRUE(model$reasoning)) return(out)
  level = params$thinking
  if (isTRUE(adp_model_cap(model, "adaptive_thinking", FALSE))) {
    if (!identical(level, "off")) {
      out$thinking = list(type = "adaptive",
                          display = if (gptr_has_human()) "summarized" else "omitted")
    }
    if (isTRUE(adp_model_cap(model, "effort", TRUE))) {
      out$effort = params$effort %||% adp_level_effort(level)
    }
  } else if (!is.null(level) && !identical(level, "off")) {
    out$budget = adp_budget(level)
    out$thinking = list(type = "enabled", budget_tokens = out$budget)
    out$betas = "interleaved-thinking-2025-05-14"
  }
  out
}

#' The tool_choice field of a request, or NULL for the default `auto` (IC-71)
#' @noRd
anthropic_tool_choice = function(tc, model, thinking, returns) {
  if (identical(tc, "none")) return(list(type = "none"))
  if (!adp_forced(tc) || !adp_forced_ok(model, anthropic_caps())) return(NULL)
  if (!is.null(thinking) || !is.null(returns)) return(NULL)
  if (identical(tc$type, "any")) return(list(type = "any"))
  list(type = "tool", name = tc$name)
}

#' build() of the anthropic-messages adapter (04 section 8.1): the request spec
#' Body key order per G4 section 3.7; BP1 on T0 and BP2 on the project block are 1 h markers.
#' @noRd
anthropic_build = function(model, context, opts) {
  params = context$params %||% list()
  plan = adp_cache_plan(context)
  anchors = plan$anchors %||% character()
  msgs = context$messages %||% list()
  cc1h = list(type = "ephemeral", ttl = "1h")
  native_returns = !is.null(params$returns) && isTRUE(model$structured_output)
  tail = !is.null(params$returns) && !native_returns
  rendered = anthropic_elements(model, msgs, opts, anchors, tail)
  th = anthropic_thinking(model, params)

  max_tokens = params$max_tokens %||% model$max_output %||% 64000L
  if (is.null(max_tokens) || is.na(max_tokens)) max_tokens = 64000L
  cap = model$max_output
  if (is.null(cap) || is.na(cap)) cap = Inf
  asked = min(max_tokens, cap)
  max_tokens = asked
  if (!is.null(th$budget)) {
    max_tokens = min(max(asked, th$budget + 1024L), cap)
    budget = min(th$budget, max(1024L, max_tokens - 1024L))
    if (budget < max_tokens) {
      th$thinking = list(type = "enabled", budget_tokens = as.integer(budget))
    } else {
      # the API needs 1024 <= budget_tokens < max_tokens: no room to think, so no thinking
      th = list(thinking = NULL, effort = th$effort, budget = NULL, betas = character())
      max_tokens = asked
    }
  }
  betas = c(rendered$betas, th$betas)

  head = list(model = model$id, max_tokens = as.integer(max_tokens), stream = TRUE)
  head$cache_control = if (identical(plan$tail_ttl, "1h")) cc1h else list(type = "ephemeral")
  if (!is.null(th$thinking)) head$thinking = th$thinking
  oc = list()
  if (!is.null(th$effort)) oc$effort = th$effort
  if (native_returns) oc$format = list(type = "json_schema", schema = params$returns)
  if (length(oc)) head$output_config = oc
  tc = anthropic_tool_choice(params$tool_choice, model, th$thinking, params$returns)
  if (!is.null(tc)) head$tool_choice = tc
  # report 07 section 2.3: a non-default temperature is a 400 on every 5.x (adaptive) model
  adaptive = isTRUE(adp_model_cap(model, "adaptive_thinking", FALSE))
  if (!is.null(params$temperature) && is.null(th$thinking) && !adaptive) {
    head$temperature = params$temperature
  }
  for (f in anthropic_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  tools = context$tools_json
  if (!is.null(tools) && !identical(trimws(as.character(tools)), "[]")) {
    extra = c(extra, paste0("\"tools\":", as.character(tools)))
  }
  sys = list()
  t0 = context$system$t0 %||% ""
  t1 = context$system$t1 %||% ""
  if (nzchar(t0)) {
    s = list(type = "text", text = t0)
    if ("t0" %in% anchors) s$cache_control = cc1h
    sys[[length(sys) + 1L]] = s
  }
  if (nzchar(t1)) {
    s = list(type = "text", text = t1)
    no_anchor = "project" %in% anchors && adp_anchor_index(msgs) == 0L
    if ("t1" %in% anchors || no_anchor) s$cache_control = cc1h
    sys[[length(sys) + 1L]] = s
  }
  if (length(sys)) {
    sys_json = adp_memo(opts, paste("anthropic", "system", hash_xxh128(sys), sep = "|"),
                        function() json_encode(sys))
    extra = c(extra, paste0("\"system\":", sys_json))
  }

  elements = rendered$elements
  if (tail) {
    as_system = rendered$mid && identical(rendered$prev, "user")
    instr = list(role = if (as_system) "system" else "user",
                 content = list(list(type = "text",
                                     text = adp_returns_instruction(params$returns))))
    elements = c(elements, json_encode(instr))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream",
                 `anthropic-version` = "2023-06-01")
  cred = opts$credential
  if (!is.null(cred)) {
    if (identical(cred$name, "ANTHROPIC_AUTH_TOKEN")) {
      headers$authorization = adp_header_secret(cred, "Bearer ")
      betas = c(betas, "oauth-2025-04-20")
    } else {
      headers$`x-api-key` = adp_header_secret(cred)
    }
  }
  if (length(betas)) headers$`anthropic-beta` = paste(unique(betas), collapse = ",")
  headers = adp_merge_headers(headers, adp_provider_headers(model, opts),
                              lists = "anthropic-beta", auth = c("x-api-key", "authorization"))

  list(url = adp_url(opts$base_url %||% "https://api.anthropic.com", "v1/messages"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "messages", elements), stream = "sse")
}

#' builtin:anthropic: registers the anthropic-messages adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_anthropic = function(gptr) {
  gptr$register(gptr_adapter("anthropic-messages", transport = "http_sse",
                             build = anthropic_build, parse = anthropic_normaliser,
                             capabilities = anthropic_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("anthropic", builtin_anthropic))

# ---- conformance: check_adapter() (the check.adapter service) ---------------------------------

#' A request context of 04 section 8.1 for conformance builds: the assistant message `msg`
#' followed by one result per tool call, with the tools those calls name
#' @noRd
adp_check_context = function(msg = NULL, tool_choice = "auto") {
  calls = list()
  if (!is.null(msg)) calls = Filter(function(b) identical(b$type, "tool_call"), msg$content)
  tool_names = unique(c("read", vapply(calls, function(b) b$name, "")))
  tools = lapply(tool_names, function(n) {
    list(name = n, description = "A conformance fixture tool.",
         input_schema = list(type = "object", properties = json_obj()))
  })
  msgs = list(msg_user("Run the conformance fixture.", timestamp = 0))
  if (!is.null(msg)) {
    msgs[[2L]] = msg
    for (b in calls) {
      msgs[[length(msgs) + 1L]] = msg_tool_result(b$id, b$name, "ok", timestamp = 0)
    }
  }
  list(system = list(t0 = "You are a conformance fixture.", t1 = ""),
       tools_json = json_verbatim(json_encode(tools)), tools = list(), messages = msgs,
       cache_plan = list(anchors = c("t0", "project"), tail_ttl = "5m",
                         key = "gptr:000000000000"),
       params = list(max_tokens = 1024L, thinking = NULL, effort = NULL,
                     tool_choice = tool_choice, returns = NULL, temperature = NULL),
       session_id = "s0000000000", request_id = "q000000000000")
}

#' The opaque strings of a message that must reach the wire byte for byte (INFRA-07)
#' @noRd
adp_opaque_strings = function(msg) {
  quoted = character()
  verbatim = character()
  for (b in msg$content) {
    type = b$type %||% ""
    if (type == "thinking") quoted = c(quoted, b$signature, b$data)
    if (type == "tool_call") quoted = c(quoted, b$thought_signature)
    if (type == "text" && !is.null(b$signature) && !startsWith(b$signature, "{")) {
      quoted = c(quoted, b$signature)
    }
    if (type == "opaque") verbatim = c(verbatim, b$json)
  }
  list(quoted = quoted, verbatim = verbatim)
}

#' Byte-identical re-serialisation: the message and its JSON round trip build the same body,
#' with and without the memo, and every opaque string is on the wire verbatim
#' @noRd
adp_roundtrip = function(adapter, model, msg) {
  opts = list(base_url = "http://127.0.0.1:1", memo = NULL)
  b1 = adapter$build(model, adp_check_context(msg), opts)$body
  msg2 = msg_from_json(json_decode(json_encode(msg_to_json(msg))))
  b2 = adapter$build(model, adp_check_context(msg2), opts)$body
  memo = new.env(parent = emptyenv())
  mopts = list(base_url = "http://127.0.0.1:1", memo = memo)
  b3 = adapter$build(model, adp_check_context(msg), mopts)$body
  b4 = adapter$build(model, adp_check_context(msg), mopts)$body
  s = adp_opaque_strings(msg)
  needles = c(vapply(s$quoted, function(x) {
    q = json_encode(x)
    substr(q, 2L, nchar(q) - 1L)
  }, ""), s$verbatim)
  missing = needles[!vapply(needles, function(x) grepl(x, b1, fixed = TRUE), logical(1))]
  same = identical(b1, b2) && identical(b1, b3) && identical(b1, b4)
  message = ""
  if (length(missing)) message = "an opaque value is not on the wire verbatim"
  if (!same) message = "re-serialisation changed the request body"
  list(ok = same && !length(missing), message = message)
}

#' Is a forced tool choice in a request body? (Anthropic, Responses, Chat and Gemini shapes)
#' @noRd
adp_body_forced = function(body) {
  tc = body$tool_choice
  adp_forced(tc) || identical(tc, "required") || identical(tc, "any") ||
    identical(body$toolConfig$functionCallingConfig$mode, "ANY")
}

#' Does a list tool_choice stay off the wire while forced_tool_choice is FALSE? (IC-71)
#' @noRd
adp_check_tool_choice = function(adapter) {
  ctx = adp_check_context(NULL, tool_choice = list(type = "tool", name = "read"))
  opts = list(base_url = "http://127.0.0.1:1")
  model = adp_fixture_model(adapter$api)
  model$reasoning = FALSE
  model$capabilities$forced_tool_choice = FALSE
  ok = !adp_body_forced(json_decode(adapter$build(model, ctx, opts)$body))
  if (isFALSE(adapter$capabilities$forced_tool_choice)) {
    model$capabilities$forced_tool_choice = NULL
    ok = ok && !adp_body_forced(json_decode(adapter$build(model, ctx, opts)$body))
  }
  ok
}

#' The fixture directory: `fixtures`, else fixtures/<sub> under the test directory or the
#' package sources
#' @noRd
adp_fixture_dir = function(sub, fixtures = NULL) {
  cands = fixtures %||% file.path(c("fixtures", file.path("tests", "testthat", "fixtures")), sub)
  for (d in cands) if (nzchar(d) && dir.exists(d)) return(normalizePath(d, winslash = "/"))
  NULL
}

#' adp_replay() for conformance: the first warning or message ends the replay as its condition
#' (04 section 8.1); exiting handlers, since signalCondition() offers no muffle restart.
#' @noRd
adp_check_replay = function(adapter, model, bytes, sizes) {
  stopped = function(cnd) list(message = NULL, condition = cnd, events = list())
  tryCatch(adp_replay(adapter, model, bytes, sizes), warning = stopped, message = stopped)
}

#' Compare an R value with a golden JSON file (key order ignored)
#' @noRd
adp_same_golden = function(x, path) {
  if (!file.exists(path)) return(FALSE)
  want = json_decode(read_utf8(path)$text)
  identical(canonical_json(json_decode(json_encode(x))), canonical_json(want))
}

# ---- conformance of classifier adapters (IC-74: 07 sections 3 and 6, P12 row; FIX-6) -----------
# Cases are contract 12.4 wire fixtures (`fixtures/jev`, `fixtures/ollama`; other apis
# `fixtures/classifier/<api>`) with a golden `<case>.answers.json` or `<case>.error.json`,
# optionally `<case>.usage.json` (null = unreported, stays NA); `model.json` overrides the model.

#' One case `{request, status, headers?, response}`: `list(questions, state, status, headers,
#' body)` or a chr(1) problem; a JSON string `response` is the body text byte for byte
#' @noRd
adp_classifier_case = function(path) {
  x = tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
  if (!is.list(x) || is.null(names(x))) return("the fixture is not a JSON object")
  req = x[["request"]]
  questions = if (is.list(req)) req[["questions"]]
  ids = names(questions)
  # a recorded error may have no request (12.4); a request holds its questions
  if (!is.null(req) && (!is.list(questions) || !length(questions) || is.null(ids) ||
                          anyNA(ids) || !all(nzchar(ids)))) {
    return("the fixture request has no questions keyed by id")
  }
  status = x[["status"]] %||% 200L
  if (!is.numeric(status) || length(status) != 1L || !is.finite(status)) {
    return("the fixture status is not one number")
  }
  headers = x[["headers"]] %||% list()
  if (!is.list(headers)) return("the fixture headers are not an object")
  body = x[["response"]]
  text = if (rlang::is_string(body)) body else if (is.null(body)) "" else json_encode(body)
  list(questions = questions, state = req[["state"]], status = as.integer(status),
       headers = headers, body = text)
}

#' One classifier call for conformance: `list(value, condition, notices)`
#' The first condition ends the call (04 section 8.1); with `notices = TRUE` a `gptr_message`
#' notice that can be muffled is recorded and muffled instead (gptr_inform(), IC-19).
#' @noRd
adp_check_classify = function(fun, args, notices = FALSE) {
  heard = new.env(parent = emptyenv())
  heard$text = character()
  muffle = function(cnd) {
    if (is.null(findRestart("muffleMessage"))) return(invisible(NULL))
    heard$text = c(heard$text, trimws(conditionMessage(cnd)))
    invokeRestart("muffleMessage")
  }
  call = function() {
    if (!notices) return(do.call(fun, args))
    withCallingHandlers(do.call(fun, args), gptr_message = muffle)
  }
  stopped = function(cnd) list(value = NULL, condition = cnd, notices = heard$text)
  tryCatch({
    value = call()
    list(value = value, condition = NULL, notices = heard$text)
  }, error = stopped, warning = stopped, message = stopped)
}

#' Clear the once slots (04 section 2.1 `.once`) a conformance replay set, since the check
#' never showed them; `before` is the slot names before the replay
#' @noRd
adp_once_restore = function(before) {
  added = setdiff(ls(the$once, all.names = TRUE), before)
  if (length(added)) rm(list = added, envir = the$once)
  invisible(NULL)
}

#' Is a classifier result one of the two shapes of 04 section 8.1: `list(answers, usage =
#' list(input, output), model_version = chr(1))` or an unsignalled `gptr_error_s1` condition?
#' @noRd
adp_classifier_result_ok = function(res) {
  if (inherits(res, "condition")) return(inherits(res, "gptr_error_s1"))
  if (!is.list(res) || !is.list(res[["answers"]])) return(FALSE)
  count = function(x) {
    is.numeric(x) && length(x) == 1L && (is.na(x) || (is.finite(x) && x >= 0))
  }
  u = res[["usage"]]
  v = res[["model_version"]]
  is.list(u) && count(u[["input"]]) && count(u[["output"]]) &&
    is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
}

#' The usage row of an answered case: `.golden_usage` against `<case>.usage.json` (`{"input",
#' "output"}`; null = unreported, stays NA, IC-74); NULL without that file or for a failed case
#' @noRd
adp_classifier_usage = function(dir, case, res) {
  path = file.path(dir, paste0(case, ".usage.json"))
  if (!file.exists(path) || inherits(res, "condition") || !is.list(res)) return(NULL)
  want = tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
  same = function(k) {
    got = if (is.list(res[["usage"]])) res[["usage"]][[k]]
    exp = want[[k]]
    is.numeric(got) && length(got) == 1L &&
      (if (is.null(exp)) is.na(got) else is.numeric(exp) && isTRUE(got == exp))
  }
  ok = is.list(want) && all(c("input", "output") %in% names(want)) && same("input") &&
    same("output")
  list(check = paste0("adapter.", case, ".golden_usage"), ok = ok,
       message = paste0("the usage differs from ", case, ".usage.json (unreported stays NA)"))
}

#' Are the answers canonical? P13's s1_check_answers() must return them unchanged (07 section 3)
#' @noRd
adp_check_canonical = function(answers, questions, model_id) {
  checked = tryCatch(s1_check_answers(answers, questions, model_id), error = function(e) e)
  if (inherits(checked, "condition")) return(list(ok = FALSE, message = conditionMessage(checked)))
  list(ok = identical(checked, answers),
       message = "not canonical: question order, probabilities in request order (07 section 3)")
}

#' Classifier answers as JSON data for their golden file: named vectors (probabilities, legend)
#' become objects and NA becomes null; names and order are kept
#' @noRd
adp_answers_json = function(x) {
  if (is.list(x)) return(lapply(x, adp_answers_json))
  if (is.atomic(x) && !is.null(names(x))) return(lapply(as.list(x), adp_answers_json))
  if (is.atomic(x) && length(x) == 1L && is.na(x)) return(NULL)
  x
}

#' The golden row of a case: `.typed_error` against `<case>.error.json` (`{"class", "status"}`),
#' else `.golden_answers` against `<case>.answers.json` (order included)
#' @noRd
adp_classifier_golden = function(dir, case, res) {
  failed = inherits(res, "condition")
  got = if (failed) {
    paste0(class(res)[[1L]], " (status ", format(res[["status"]] %||% NA), "): ",
           conditionMessage(res))
  } else {
    "answers"
  }
  golden = function(ext) {
    tryCatch(json_decode(read_utf8(file.path(dir, paste0(case, ext)))$text),
             error = function(e) NULL)
  }
  if (file.exists(file.path(dir, paste0(case, ".error.json")))) {
    want = golden(".error.json")
    cls = if (is.list(want)) want[["class"]]
    ok = failed && rlang::is_string(cls) && inherits(res, "gptr_error_s1") && inherits(res, cls) &&
      (is.null(want[["status"]]) ||
         identical(as.integer(res[["status"]]), as.integer(want[["status"]])))
    return(list(check = paste0("adapter.", case, ".typed_error"), ok = ok,
                message = paste0("expected the error of ", case, ".error.json, got ", got)))
  }
  want = golden(".answers.json")
  ok = !failed && !is.null(want) && tryCatch({
    identical(json_encode(adp_answers_json(res[["answers"]])), json_encode(want))
  }, error = function(e) FALSE)
  message = if (!file.exists(file.path(dir, paste0(case, ".answers.json")))) {
    paste0("no golden ", case, ".answers.json or ", case, ".error.json")
  } else {
    paste0("expected the answers of ", case, ".answers.json (values and order), got ",
           if (failed) got else "other answers")
  }
  list(check = paste0("adapter.", case, ".golden_answers"), ok = ok, message = message)
}

#' Conformance of a classifier adapter (IC-74: 07 sections 3 and 6, P12 row; FIX-6)
#' Each case through `classify$parse()` (or `run()`): rows `.no_condition`, `.result`,
#' `.canonical`, `.golden_answers`/`.typed_error`, `.golden_usage`; unreadable case `.fixture`.
#' @noRd
adp_check_classifier = function(adapter, fixtures, add) {
  api = adapter$api %||% adapter$name
  cls = adapter[["classify"]]
  wire = !identical(adapter[["transport"]], "inprocess")
  fun = cls[[if (wire) "parse" else "run"]]
  dir = adp_fixture_dir(switch(api, `typesafe-system-one` = "jev", `ollama-system-one` = "ollama",
                               file.path("classifier", api)), fixtures)
  files = if (is.null(dir)) character() else
    list.files(dir, pattern = "\\.json$", full.names = TRUE)
  files = files[!grepl("\\.(answers|error|usage)\\.json$", files) &
                  basename(files) != "model.json"]
  if (!is.function(fun)) {
    add("adapter.replay", FALSE, paste0("the classifier adapter has no classify$",
                                        if (wire) "parse" else "run", " function"))
    return(invisible(NULL))
  }
  if (!length(files) && !wire && is.null(fixtures)) {
    add("adapter.replay", TRUE,
        note = "nothing to replay: an inprocess classifier without classifier fixtures")
    return(invisible(NULL))
  }
  if (!length(files)) {
    add("adapter.fixtures", FALSE,
        paste0("no classifier fixtures found for ", api, "; pass fixtures = <directory>"))
    return(invisible(NULL))
  }
  model = adp_fixture_model(api, dir, type = "classifier")
  shape = paste0("the result is neither list(answers, usage = list(input, output), ",
                 "model_version) nor an unsignalled gptr_error_s1 condition (04 section 8.1)")
  once = ls(the$once, all.names = TRUE)
  on.exit(adp_once_restore(once), add = TRUE)
  for (f in sort(files)) {
    case = sub("\\.json$", "", basename(f))
    fx = adp_classifier_case(f)
    if (is.character(fx)) {
      add(paste0("adapter.", case, ".fixture"), FALSE, fx)
      next
    }
    args = if (wire) {
      list(model, fx[["status"]], fx[["headers"]], fx[["body"]], fx[["questions"]])
    } else {
      list(model, fx[["state"]], fx[["questions"]], list())
    }
    r = adp_check_classify(fun, args, notices = !wire)
    heard = if (length(r$notices)) {
      paste0("muffled notice: ", paste(r$notices, collapse = " | "))
    } else {
      ""
    }
    add(paste0("adapter.", case, ".no_condition"), is.null(r$condition),
        if (is.null(r$condition)) "" else conditionMessage(r$condition), note = heard)
    if (!is.null(r$condition)) next
    res = r$value
    add(paste0("adapter.", case, ".result"), adp_classifier_result_ok(res), shape)
    if (!inherits(res, "condition")) {
      answers = if (is.list(res)) res[["answers"]] else NULL
      chk = adp_check_canonical(answers, fx[["questions"]], model[["id"]])
      add(paste0("adapter.", case, ".canonical"), chk$ok, chk$message)
    }
    g = adp_classifier_golden(dir, case, res)
    add(g$check, g$ok, g$message)
    u = adp_classifier_usage(dir, case, res)
    if (!is.null(u)) add(u$check, u$ok, u$message)
  }
  invisible(NULL)
}

#' Conformance of an adapter (04 section 7.12; the check.adapter service of gptr_check())
#' Replays every fixture whole, byte by byte and in three pseudo-random chunkings against its
#' goldens; also opaque re-serialisation and forced tool_choice (IC-71). Returns a `gptr_check`.
#' @noRd
check_adapter = function(adapter, fixtures = NULL) {
  check_list(adapter, "adapter")
  check_string(fixtures, "fixtures", null = TRUE)
  api = adapter$api %||% adapter$name
  target = paste0("adapter:", api)
  rows = new.env(parent = emptyenv())
  rows$check = character()
  rows$ok = logical()
  rows$message = character()
  add = function(check, ok, message = "", note = "") {
    rows$check = c(rows$check, check)
    rows$ok = c(rows$ok, isTRUE(ok))
    rows$message = c(rows$message, if (isTRUE(ok)) note else message)
  }
  frame = function() {
    df = data.frame(target = rep(target, length(rows$check)), check = rows$check, ok = rows$ok,
                    message = rows$message, stringsAsFactors = FALSE)
    class(df) = c("gptr_check", "data.frame")
    df
  }
  # classifier adapters (`classify`) replay classifier fixtures, never stream fixtures
  if (is.list(adapter[["classify"]])) {
    adp_check_classifier(adapter, fixtures, add)
    return(frame())
  }
  transport = adapter$transport %||% ""
  # nothing to replay: inprocess generators
  streams = transport %in% c("http_sse", "http_ndjson", "http_json", "process_jsonl")
  if (!streams || !is.function(adapter$parse)) {
    add("adapter.replay", TRUE,
        note = "nothing to replay: no stream normaliser (an inprocess adapter)")
    return(frame())
  }
  if (is.function(adapter$build)) {
    sent = "a list tool_choice was sent although forced_tool_choice is FALSE"
    tc = tryCatch(list(ok = adp_check_tool_choice(adapter), message = sent),
                  error = function(e) {
                    list(ok = FALSE, message = paste0("build() failed: ", conditionMessage(e)))
                  })
    add("adapter.tool_choice", tc$ok, tc$message)
  }
  dir = adp_fixture_dir(file.path("sse", api), fixtures)
  ext = switch(transport, http_sse = "sse", http_ndjson = "ndjson", http_json = "json",
               process_jsonl = "jsonl")
  files = if (is.null(dir)) character() else
    list.files(dir, pattern = paste0("\\.", ext, "$"), full.names = TRUE)
  # `.json` wire fixtures (http_json) share their extension with the golden files and model.json
  is_golden = grepl("\\.(events|message)\\.json$", files) | basename(files) == "model.json"
  files = files[!is_golden]
  if (!length(files)) {
    add("adapter.fixtures", FALSE,
        paste0("no fixtures found for ", api, "; pass fixtures = <directory>"))
    return(frame())
  }
  model = adp_fixture_model(api, dir)
  for (f in sort(files)) {
    case = sub(paste0("\\.", ext, "$"), "", basename(f))
    bytes = readBin(f, "raw", file.size(f))
    whole = adp_check_replay(adapter, model, bytes, length(bytes))
    add(paste0("adapter.", case, ".no_condition"), is.null(whole$condition),
        if (is.null(whole$condition)) "" else conditionMessage(whole$condition))
    if (!is.null(whole$condition)) next
    types = vapply(whole$events, function(e) e$type %||% "", "")
    one_start = length(types) > 0L && types[[1L]] == "start" && sum(types == "start") == 1L
    one_term = sum(types %in% c("done", "error")) == 1L &&
      types[[length(types)]] %in% c("done", "error")
    add(paste0("adapter.", case, ".event_order"), one_start && one_term,
        paste0("event types: ", paste(types, collapse = " ")))
    golden = lapply(whole$events, adp_golden_event)
    add(paste0("adapter.", case, ".golden_events"),
        adp_same_golden(golden, file.path(dir, paste0(case, ".events.json"))),
        paste0("events differ from ", case, ".events.json"))
    add(paste0("adapter.", case, ".golden_message"),
        adp_same_golden(adp_golden_message(whole$message),
                        file.path(dir, paste0(case, ".message.json"))),
        paste0("the final message differs from ", case, ".message.json"))
    sizes = list(1L, adp_chunk_sizes(paste0(case, "-1")), adp_chunk_sizes(paste0(case, "-2")),
                 adp_chunk_sizes(paste0(case, "-3")))
    invariant = TRUE
    for (sz in sizes) {
      r = adp_check_replay(adapter, model, bytes, sz)
      if (!is.null(r$condition) || !identical(lapply(r$events, adp_golden_event), golden)) {
        invariant = FALSE
      }
    }
    add(paste0("adapter.", case, ".chunk_invariance"), invariant,
        "events differ between chunkings of the same bytes")
    ended = whole$message$stop_reason %||% "error"
    if (is.function(adapter$build) && !(ended %in% c("error", "aborted"))) {
      rt = tryCatch(adp_roundtrip(adapter, model, whole$message),
                    error = function(e) list(ok = FALSE, message = conditionMessage(e)))
      add(paste0("adapter.", case, ".roundtrip"), rt$ok, rt$message)
    }
  }
  frame()
}

on_load(ext_service_set("check.adapter", check_adapter, provided_by = "P12",
                        builtin = "anthropic"))
