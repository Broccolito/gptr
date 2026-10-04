# The openai-responses adapter (P12): the stateless Responses API with store = false. Reasoning
# items (with encrypted_content), message ids with `phase`, and `call_|fc_` ids are replayed
# byte for byte to the same model only (report 08 sections 2.A, 3.1-3.3; verification log rows
# 32 (backfill encrypted_content from response.completed), 37 (keep `phase`) and 40 (a unique
# X-Client-Request-Id per request)). The normaliser is adapted from the verified prototypes of
# report 08 section 5.7 and report 03 section 5.3. Usage follows IC-74 (07-local-ollama.md
# section 5): usage the stream never reported, or reported as null, stays unknown. Stream fields
# are read with `[[` (no `$` partial matching) and typed before use (04 sections 2.2, 4.2).

#' A provider value that must be one string: the string, else "" (a number, list, vector or NA
#' is never taken as text)
#' @noRd
responses_str = function(x) {
  if (is.character(x) && length(x) == 1L && !is.na(x)) x else ""
}

#' A Responses error code -> class suffix, status and retryability (08 sections 2.D, 3.5); a
#' code that is not one string is a provider error
#' @noRd
responses_error_info = function(code) {
  code = responses_str(code)
  if (grepl("spend_limit|usage_limit|credit_balance|insufficient_quota", code)) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  if (code %in% c("rate_limit_exceeded", "slow_down")) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if (code %in% c("server_error", "server_is_overloaded", "overloaded")) {
    return(list(class = "overloaded", status = 503L, retry = TRUE))
  }
  list(class = "provider", status = NA_integer_, retry = FALSE)
}

#' The replay form of a reasoning item: only the fields accepted as input (08 section 3.2)
#' @noRd
responses_reasoning_item = function(item) {
  keep = c("type", "id", "summary", "encrypted_content", "content")
  item[intersect(keep, names(item))]
}

#' The tool-call id of a function_call item: `<call_id>|<fc_id>` (04 section 4.1, "provider id
#' verbatim, e.g. call_1|fc_2"); the call id alone when the item has no id
#' @noRd
responses_call_id = function(item) {
  ids = c(responses_str(item[["call_id"]]), responses_str(item[["id"]]))
  paste(ids[nzchar(ids)], collapse = "|")
}

#' The texts of a reasoning item's `summary` or `content` parts
#' @noRd
responses_texts = function(parts) {
  if (!is.list(parts)) return(character())
  texts = vapply(parts, function(x) if (is.list(x)) responses_str(x[["text"]]) else "", "")
  texts[nzchar(texts)]
}

#' The text of one message content part: `output_text` text, else the `refusal` text
#' @noRd
responses_part_text = function(x) {
  if (!is.list(x)) return("")
  if (identical(x[["type"]], "output_text")) {
    return(responses_str(x[["text"]]))
  }
  responses_str(x[["refusal"]])
}

#' Record a Responses usage object (08 section 3.3; Pi openai-responses-shared.ts 561-577)
#'
#' `input_tokens` includes the cached and cache-write tokens, so the uncached input is the rest;
#' the reasoning tokens are part of `output_tokens`. A field the provider left out keeps P05's
#' legacy zero, a reported null or a value that is not a nonnegative number is unknown (NA,
#' IC-74), and `"usage": null` is no report (D-022, D-027).
#' @noRd
responses_usage = function(st, u) {
  if (!is.list(u)) return(invisible(NULL))
  details = u[["input_tokens_details"]]
  cached = completions_first(completions_count(details, "cached_tokens"))
  cwrite = completions_first(completions_count(details, "cache_write_tokens"))
  input = completions_first(completions_count(u, "input_tokens"))
  reasoning = completions_count(u[["output_tokens_details"]], "reasoning_tokens")
  st$usage = list(input = max(0, input - cached - cwrite),
                  output = completions_first(completions_count(u, "output_tokens")),
                  cache_read = cached, cache_write_5m = cwrite,
                  reasoning = completions_first(reasoning))
  invisible(NULL)
}

#' The openai-responses normaliser (04 section 8.1; 08 section 3.3)
#'
#' A reasoning item opens two slots: a thinking block with the summary text, and an opaque
#' block holding the reasoning item for replay. A message item's id and `phase` are kept as
#' the text block's signature `{"v":1,"id":...,"phase":...}` (Pi's textSignature). Items are
#' found by `item_id`, then by `output_index`; an item missing from `response.output_item.done`
#' is finished from the terminal response, and a reasoning item's missing `encrypted_content`
#' is backfilled from it (verification log row 32).
#' @param model A model record (contract section 4.9).
#' @param opts The adapter options of contract section 8.1 (`emit`, `retry`, `signal`).
#' @return A list of functions `push`, `finish`, `fail`, `message`.
#' @noRd
responses_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  by_index = new.env(parent = emptyenv())
  by_id = new.env(parent = emptyenv())

  slot_index = function(oi, id) {
    id = responses_str(id)
    i = if (nzchar(id)) by_id[[id]]
    key = adp_chr(oi)
    if (is.null(i) && nzchar(key)) i = by_index[[key]]
    i
  }

  open_item = function(oi, item) {
    i = slot_index(oi, item[["id"]])
    if (!is.null(i)) return(i)
    type = responses_str(item[["type"]])
    if (type == "reasoning") {
      i = adp_open(st, "thinking")
      adp_open(st, "opaque")
    } else if (type == "message") {
      i = adp_open(st, "text", item_id = responses_str(item[["id"]]),
                   phase = responses_str(item[["phase"]]))
    } else if (type == "function_call") {
      i = adp_open(st, "tool_call", id = responses_call_id(item),
                   name = responses_str(item[["name"]]), pj = partial_json())
      adp_delta(st, i, responses_str(item[["arguments"]]))
    } else {
      i = adp_open(st, "opaque")
    }
    key = adp_chr(oi)
    if (nzchar(key)) assign(key, i, envir = by_index)
    id = responses_str(item[["id"]])
    if (nzchar(id)) assign(id, i, envir = by_id)
    i
  }

  slot_of = function(e, kind) {
    i = slot_index(e[["output_index"]], e[["item_id"]])
    if (is.null(i) || st$blocks[[i]]$type != kind || st$blocks[[i]]$done) return(NULL)
    i
  }

  set_reasoning = function(i, item) {
    o = st$blocks[[i + 1L]]
    o$item = item
    adp_set_opaque(st, i + 1L, json_encode(responses_reasoning_item(item)))
  }

  finish_item = function(oi, item) {
    if (!adp_is_object(item) || !length(item)) return(invisible(NULL))
    i = open_item(oi, item)
    b = st$blocks[[i]]
    type = responses_str(item[["type"]])
    if (type == "reasoning" && b$type == "thinking") {
      texts = responses_texts(item[["summary"]])
      if (!length(texts)) texts = responses_texts(item[["content"]])
      if (length(texts)) b$text_override = paste(texts, collapse = "\n\n")
      adp_close(st, i)
      set_reasoning(i, item)
    } else if (type == "message" && b$type == "text") {
      parts = item[["content"]]
      if (is.list(parts) && length(parts)) {
        b$text_override = paste(vapply(parts, responses_part_text, ""), collapse = "")
      }
      id = responses_str(item[["id"]])
      if (!nzchar(id)) id = b$item_id %||% ""
      if (nzchar(id)) {
        sig = list(v = 1L, id = id)
        phase = responses_str(item[["phase"]])
        if (!nzchar(phase)) phase = b$phase %||% ""
        if (nzchar(phase)) sig$phase = phase
        b$signature = json_encode(sig)
      }
      adp_close(st, i)
    } else if (type == "function_call" && b$type == "tool_call") {
      args = item[["arguments"]]
      if (is.character(args) && length(args) == 1L && !is.na(args)) b$raw_override = args
      adp_close(st, i)
    } else if (b$type == "opaque" && !b$done) {
      adp_set_opaque(st, i, json_encode(item))
    }
    invisible(i)
  }

  on_terminal = function(type, r) {
    if (!is.list(r)) r = list()
    rid = responses_str(r[["id"]])
    if (nzchar(rid)) st$response_id = rid
    responses_usage(st, r[["usage"]])
    outs = r[["output"]]
    if (!is.list(outs)) outs = list()
    for (k in seq_along(outs)) {
      item = outs[[k]]
      if (!adp_is_object(item) || !length(item)) next
      i = slot_index(k - 1L, item[["id"]])
      if (is.null(i) || !st$blocks[[i]]$done) {
        finish_item(k - 1L, item)
      } else if (identical(item[["type"]], "reasoning") && st$blocks[[i]]$type == "thinking" &&
                   !is.null(item[["encrypted_content"]])) {
        kept = st$blocks[[i + 1L]]$item
        if (is.list(kept) && is.null(kept[["encrypted_content"]])) {
          kept[["encrypted_content"]] = item[["encrypted_content"]]
          set_reasoning(i, kept)
        }
      }
    }
    status = responses_str(r[["status"]])
    if (!nzchar(status)) status = sub("^response[.]", "", type)
    details = r[["incomplete_details"]]
    reason = if (is.list(details)) responses_str(details[["reason"]]) else ""
    st$raw_stop = if (nzchar(reason)) paste0(status, ".", reason) else status
    if (status == "completed") {
      st$stop_reason = "stop"
    } else if (status == "incomplete" && reason == "max_output_tokens") {
      st$stop_reason = "length"
    } else {
      st$stop_reason = "error"
      st$error_message = paste0("Response ", status, ": ",
                                if (nzchar(reason)) reason else "no reason given")
    }
    has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
    if (identical(st$stop_reason, "stop") && has_tool) st$stop_reason = "tool_use"
    adp_done(st)
    TRUE
  }

  stream_error = function(code, message, no_code, no_message) {
    info = responses_error_info(code)
    code = responses_str(code)
    message = responses_str(message)
    text = paste0(if (nzchar(code)) code else no_code, ": ",
                  if (nzchar(message)) message else no_message)
    adp_stream_error(st, opts, text, class = info$class, status = info$status,
                     retryable = info$retry)
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = responses_str(ev[["data"]])
    if (!nzchar(data) || identical(trimws(data), "[DONE]")) return(FALSE)
    e = adp_json_try(data)
    if (!adp_is_object(e)) {
      adp_error(st, paste0("Could not parse a Responses stream event: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    type = responses_str(e[["type"]])
    if (!nzchar(type)) type = responses_str(ev[["event"]])
    if (!nzchar(type) && !is.null(e[["error"]])) type = "error"
    if (type %in% c("response.created", "response.in_progress", "response.queued")) {
      r = e[["response"]]
      if (is.list(r)) {
        rid = responses_str(r[["id"]])
        if (nzchar(rid)) st$response_id = rid
        rm = responses_str(r[["model"]])
        if (nzchar(rm) && !identical(rm, model$id)) st$response_model = rm
      }
    } else if (type == "response.output_item.added") {
      item = e[["item"]]
      if (adp_is_object(item) && length(item)) open_item(e[["output_index"]], item)
    } else if (type == "response.reasoning_summary_part.added") {
      i = slot_of(e, "thinking")
      if (!is.null(i) && isTRUE(adp_count(e[["summary_index"]]) > 0)) adp_delta(st, i, "\n\n")
    } else if (type %in% c("response.reasoning_summary_text.delta",
                           "response.reasoning_text.delta")) {
      i = slot_of(e, "thinking")
      if (!is.null(i)) adp_delta(st, i, responses_str(e[["delta"]]))
    } else if (type %in% c("response.output_text.delta", "response.refusal.delta")) {
      i = slot_of(e, "text")
      if (!is.null(i)) adp_delta(st, i, responses_str(e[["delta"]]))
    } else if (type == "response.function_call_arguments.delta") {
      i = slot_of(e, "tool_call")
      if (!is.null(i)) adp_delta(st, i, responses_str(e[["delta"]]))
    } else if (type == "response.function_call_arguments.done") {
      i = slot_of(e, "tool_call")
      full = e[["arguments"]]
      if (!is.null(i) && is.character(full) && length(full) == 1L && !is.na(full)) {
        prev = adp_buffer_text(st$blocks[[i]]$buf)
        if (startsWith(full, prev) && nchar(full) > nchar(prev)) {
          adp_delta(st, i, substr(full, nchar(prev) + 1L, nchar(full)))
        } else if (!identical(full, prev)) {
          st$blocks[[i]]$raw_override = full
        }
      }
    } else if (type == "response.output_item.done") {
      finish_item(e[["output_index"]], e[["item"]])
    } else if (type %in% c("response.completed", "response.incomplete")) {
      return(on_terminal(type, e[["response"]]))
    } else if (type == "response.failed") {
      r = e[["response"]]
      if (!is.list(r)) r = list()
      responses_usage(st, r[["usage"]])
      err = r[["error"]]
      if (!is.list(err)) err = list(message = err)
      return(stream_error(err[["code"]], err[["message"]], "unknown", "no message"))
    } else if (type == "error") {
      err = e[["error"]]
      if (!is.list(err)) err = list(message = err)
      return(stream_error(e[["code"]] %||% err[["code"]], e[["message"]] %||% err[["message"]],
                          "error", "unknown error"))
    }
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    adp_error(st, "The Responses stream ended before a terminal response event.",
              class = "network")
  }

  adp_normaliser(st, push, finish)
}
