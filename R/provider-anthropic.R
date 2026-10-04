# The anthropic-messages adapter (P12) and the normaliser core shared by the four native
# adapters (anthropic-messages, openai-responses, openai-completions, google-generative-ai),
# plus check_adapter(), the check.adapter service behind gptr_check() for adapter specs.
# Contract: dev/spec/04-interface-contract.md sections 4.1-4.5, 7.12, 8.1 and IC-69/IC-71.
# The normaliser follows the verified prototypes of report 07 section 5.1 and report 03
# section 5.3 (verification logs applied: tool names up to 128 characters, mid-conversation
# system messages only after a user turn and before an assistant turn or the end, no
# ANTHROPIC_API_KEY and Bearer together, every string marked UTF-8 by the P01 constructors).
# Request bodies follow G4 section 3.7 (key order, breakpoints) and section 5.4 (bodies are
# concatenations of pieces serialised once per session through opts$memo).

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
#'
#' The list is taken out of the environment and the binding cleared before the element is set:
#' `b$v[[n]] = x` on an environment passed as an argument copies the whole list on every call
#' (measured: 20,000 appends 1.7 s, quadratic), the take-out form 0.013 s (linear, INFRA-23).
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

#' Record one usage field reported by the provider, with cumulative-update semantics: a value
#' replaces the earlier one; a null keeps the earlier value and is unknown (NA, IC-74) only when
#' nothing was recorded before
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
#'
#' IC-74 (07-local-ollama.md section 5, "Missing usage remains unknown"; P05's usage rules):
#' a stream that reported no usage at all has unknown counters, a reported value that is null or
#' not a nonnegative number is unknown (NA), and a field the provider left out of a reported
#' usage keeps P05's legacy zero. The cost comes only from the model's dated price evidence
#' (`usage_cost()`), so an unpriced model's charge is unknown, never a constructor zero.
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

#' The route of a model's messages (04 section 4.2): `plan-cli` for CLI models (P20 reuses the
#' Anthropic normaliser), `system-one` for classifiers, else `api`
#' @noRd
adp_route = function(model) {
  switch(model$type %||% "chat", cli = "plan-cli", classifier = "system-one", "api")
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
                raw_stop_reason = st$raw_stop, route = adp_route(m))
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
                  stop_reason = st$stop_reason, error_message = message, route = adp_route(m))
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
#' @noRd
adp_done = function(st) {
  if (st$terminal) return(st$final)
  for (i in seq_len(st$n)) {
    if (!st$blocks[[i]]$done && st$blocks[[i]]$type != "opaque") adp_close(st, i)
  }
  if (is.null(st$stop_reason)) {
    return(adp_error(st, "The stream ended without a stop reason.", class = "network"))
  }
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
#'
#' A transport that refuses the retry at once may call fail() from inside `retry()`; push()
#' then reports the stream complete (TRUE), as section 8.1 requires once the terminal event
#' was emitted.
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

#' The normaliser's fail(cnd): a transport failure becomes the one terminal error event. After
#' a retry request the transport gave up on, the provider's own error text is reported
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

#' The normaliser list of contract section 8.1 (push, finish, fail, message[, push_parsed]);
#' no function of it signals an R condition (an error becomes the one terminal error event, and
#' message() falls back to an empty error message)
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
                               route = adp_route(m))
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

#' Golden projection of a final assistant message (cost left out: it depends on prices)
#' @noRd
adp_golden_message = function(m) {
  u = m$usage
  out = list(stop_reason = m$stop_reason, raw_stop_reason = m$raw_stop_reason,
             error_message = m$error_message, response_id = m$response_id,
             response_model = m$response_model, content = lapply(m$content, adp_golden_block),
             usage = list(input = u$input, output = u$output, cache_read = u$cache_read,
                          cache_write_5m = u$cache_write_5m, cache_write_1h = u$cache_write_1h,
                          reasoning = u$reasoning, total = u$total))
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

#' The fixture model record (contract section 4.9 shape); `<dir>/model.json` overrides fields
#' @noRd
adp_fixture_model = function(api, dir = NULL) {
  m = list(ref = "fixture/fixture-1", provider = "fixture", id = "fixture-1",
           name = "Fixture model", family = "fixture", api = api, type = "chat",
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

#' Copy Anthropic usage fields into the normaliser state (message_start, message_delta).
#'
#' `[[` only: `$` would let `cache_creation` match `cache_creation_input_tokens` (07 5.2).
#' `message_delta` usage is cumulative and a null in it means "no update" (report 03 section
#' 2.5.1; the SDK's MessageDeltaUsage), so every field goes through `adp_usage_set()`: a null
#' keeps the earlier value and is unknown (NA, IC-74) only when nothing was reported before; an
#' absent field is not set. The 5-minute/1-hour split comes from a `cache_creation` object; a
#' bare `cache_creation_input_tokens` (the current `message_delta` shape, report 07 section
#' 3.14) updates the total of that split (`anthropic_cache_total()`).
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
#'
#' Before any split was reported every cache write counts as a 5-minute write (report 07 section
#' 3.5). After a split (`st$cache_split`) the total updates it: a split that adds up to the total
#' is kept; otherwise the known 1-hour writes are kept and the rest are 5-minute writes (or the
#' known 5-minute writes are kept and the rest are 1-hour writes); an unknown total leaves the
#' 5-minute writes unknown. A null total keeps the earlier values.
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

#' The Anthropic SSE normaliser (contract sections 7.12 and 8.1)
#'
#' `push(ev)` takes decoded SSE events, `push_parsed(obj)` already-parsed stream-event objects
#' (the `stream_event` lines of the claude CLI, P20); `finish()`, `fail(cnd)` and `message()`
#' as in section 8.1. Adapted from the verified accumulator of report 07 section 5.1.
#' @param model A model record (contract section 4.9).
#' @param opts The adapter options of contract section 8.1 (`emit`, `retry`, `signal`).
#' @return A list of functions `push`, `push_parsed`, `finish`, `fail`, `message`.
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
