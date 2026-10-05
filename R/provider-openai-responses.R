# The openai-responses adapter (P12): the stateless Responses API (store = false). Reasoning items,
# message ids with `phase` and `call_|fc_` ids replay byte for byte to the same model only (report
# 08 sections 2.A, 3.1-3.3). Unreported usage stays unknown (IC-74). Stream fields are read with
# `[[` (no `$` partial matching) and typed before use (04 sections 2.2, 4.2).

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

#' The openai-responses normaliser (04 section 8.1; 08 section 3.3)
#' A reasoning item is a thinking block plus an opaque replay block; a message's id and `phase`
#' are the text signature. Missing items and `encrypted_content` come from the final response.
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
    adp_openai_usage(st, r[["usage"]], "input", "output")
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
      adp_openai_usage(st, r[["usage"]], "input", "output")
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

# ---- openai-responses: request body ------------------------------------------------------------

#' Adapter capabilities of openai-responses (04 section 8.1; IC-69, IC-71)
#' @noRd
responses_caps = function() {
  list(images_in_results = TRUE, tool_addition = TRUE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("service_tier", "metadata", "safety_identifier"),
       operator_role = "developer", cache = "openai", max_tool_name = 64L,
       tool_shape = "responses")
}

#' A Responses input_image part (data URL), or an input_text note for a text-only model
#' @noRd
responses_image = function(b, images) {
  if (!images) return(list(type = "input_text", text = adp_image_note()))
  list(type = "input_image", detail = "auto",
       image_url = paste0("data:", b$mime, ";base64,", b$data))
}

#' The input items of a user message; the anchored project block carries an explicit
#' breakpoint when the cache plan names it (G4 section 3.7)
#' @noRd
responses_user = function(m, mark_anchor, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      p = list(type = "input_text", text = b$text)
      if (mark_anchor && type == "context" && isTRUE(b$anchor)) {
        p$prompt_cache_breakpoint = list(mode = "explicit")
      }
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = responses_image(b, images)
    }
  }
  if (!length(parts)) return(list())
  list(list(role = "user", content = parts))
}

#' The message id and `phase` of a text signature `{"v":1,"id":...,"phase":...}`; NULL unless
#' the id is one string, a phase that is not one string is ""
#' @noRd
responses_text_signature = function(signature) {
  sig = adp_json_try(responses_str(signature))
  if (!adp_is_object(sig)) return(NULL)
  id = responses_str(sig[["id"]])
  if (!nzchar(id)) return(NULL)
  list(id = id, phase = responses_str(sig[["phase"]]))
}

#' The input items of an assistant message: reasoning items, message ids with `phase` and
#' `fc_` ids only for the same model; other models get plain text and call ids (Pi 296-306)
#' @noRd
responses_assistant = function(m, model) {
  same = handoff_same_model(m, model)
  items = list()
  for (b in m$content) {
    type = b$type %||% ""
    it = NULL
    if (type == "opaque") {
      if (same) it = json_verbatim(b$json)
    } else if (type == "thinking") {
      if (!same && nzchar(trimws(b$thinking))) it = list(role = "assistant", content = b$thinking)
    } else if (type == "text") {
      if (nzchar(b$text)) {
        sig = if (same) responses_text_signature(b$signature)
        if (!is.null(sig)) {
          it = list(type = "message", role = "assistant", id = sig$id)
          if (nzchar(sig$phase)) it$phase = sig$phase
          it$status = "completed"
          it$content = list(list(type = "output_text", text = b$text, annotations = list()))
        } else {
          it = list(role = "assistant", content = b$text)
        }
      }
    } else if (type == "tool_call") {
      ids = strsplit(b$id, "|", fixed = TRUE)[[1L]]
      it = list(type = "function_call")
      if (same && length(ids) > 1L && startsWith(ids[[2L]], "fc_")) it$id = ids[[2L]]
      it$call_id = ids[[1L]]
      it$name = b$name
      it$arguments = json_encode(if (length(b$arguments)) b$arguments else json_obj())
    }
    if (!is.null(it)) items[[length(items) + 1L]] = it
  }
  items
}

#' The function_call_output item of a tool result (images as input_image parts, acceptance 3)
#' @noRd
responses_tool_result = function(r, images) {
  texts = character()
  imgs = list()
  for (b in r$content) {
    if (identical(b$type, "text")) texts = c(texts, b$text)
    if (identical(b$type, "image")) imgs[[length(imgs) + 1L]] = responses_image(b, images)
  }
  txt = paste(texts, collapse = "\n")
  call_id = strsplit(r$tool_call_id, "|", fixed = TRUE)[[1L]][[1L]]
  output = if (!length(imgs)) {
    if (nzchar(txt)) txt else "(no tool output)"
  } else {
    c(if (nzchar(txt)) list(list(type = "input_text", text = txt)), imgs)
  }
  list(list(type = "function_call_output", call_id = call_id, output = output))
}

#' Responses function tools from the frozen Anthropic-shape array (flat, strict = FALSE)
#' @noRd
responses_tools = function(tools) {
  lapply(tools, function(t) {
    list(type = "function", name = t$name, description = t$description %||% "",
         parameters = t$input_schema, strict = FALSE)
  })
}

#' The input items of an operator message: a developer message and an additional_tools item
#' @noRd
responses_operator = function(m, with_tools) {
  items = list()
  text = adp_operator_text(m)
  if (nzchar(text)) items[[1L]] = list(role = "developer", content = text)
  if (with_tools && length(m$tool_add)) {
    defs = lapply(m$tool_add, function(t) {
      list(name = t$name, description = t$description, input_schema = t$input_schema)
    })
    items[[length(items) + 1L]] = list(type = "additional_tools", role = "developer",
                                       tools = responses_tools(defs))
  }
  items
}

#' The tool_choice field of a Responses request, or NULL for the default `auto`
#' @noRd
responses_tool_choice = function(tc, model, returns) {
  if (identical(tc, "none")) return("none")
  if (!adp_forced(tc) || !adp_forced_ok(model, responses_caps()) || !is.null(returns)) {
    return(NULL)
  }
  if (identical(tc$type, "any")) "required" else list(type = "function", name = tc$name)
}

#' build() of the openai-responses adapter (04 section 8.1; G4 section 3.7)
#' Compat and headers come from `opts$provider` (D-023, D-027); tools and operator tool additions
#' only to a `tool_call` model (IC-74), `tool_choice` only with a tools array (D-029).
#' @noRd
responses_build = function(model, context, opts) {
  params = context$params %||% list()
  plan = adp_cache_plan(context)
  anchors = plan$anchors %||% character()
  compat = compat_flags(adp_provider_record(model, opts), model)
  explicit = isTRUE(compat$explicit_cache_mode)
  images = adp_images_ok(model)
  tools_on = !isFALSE(model[["tool_call"]])
  add_tools = tools_on && isTRUE(adp_model_cap(model, "tool_addition", TRUE))
  msgs = context$messages %||% list()
  anchor_at = adp_anchor_index(msgs)
  tj = if (tools_on) adp_tools_json(opts, "openai-responses", context$tools_json, responses_tools)

  head = list(model = model$id, store = FALSE, stream = TRUE)
  if (!is.null(plan$key) && nzchar(plan$key)) head$prompt_cache_key = substr(plan$key, 1L, 64L)
  if (explicit) head$prompt_cache_options = list(mode = "implicit")
  if (isTRUE(model$reasoning)) {
    level = params$thinking
    if (identical(level, "off")) {
      if ("off" %in% unlist(model$thinking_levels)) head$reasoning = list(effort = "none")
    } else {
      r = list()
      eff = params$effort %||% level
      if (!is.null(eff)) r$effort = eff
      r$summary = "auto"
      head$reasoning = r
      head$include = list("reasoning.encrypted_content")
    }
  }
  if (!is.null(params$max_tokens)) head$max_output_tokens = max(16L, as.integer(params$max_tokens))
  if (!is.null(params$temperature) && !isTRUE(model$reasoning)) {
    head$temperature = params$temperature
  }
  tc = if (!is.null(tj)) responses_tool_choice(params$tool_choice, model, params$returns)
  if (!is.null(tc)) head$tool_choice = tc
  for (f in responses_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  if (!is.null(tj)) extra = c(extra, paste0("\"tools\":", tj))

  elements = character()
  sys = list()
  for (k in c("t0", "t1")) {
    txt = context$system[[k]] %||% ""
    if (!nzchar(txt)) next
    p = list(type = "input_text", text = txt)
    if (explicit && k %in% anchors) p$prompt_cache_breakpoint = list(mode = "explicit")
    sys[[length(sys) + 1L]] = p
  }
  if (length(sys)) {
    key = paste("openai-responses", "system", hash_xxh128(sys), sep = "|")
    elements = c(elements, adp_memo(opts, key, function() {
      json_encode(list(role = "developer", content = sys))
    }))
  }
  mark_project = explicit && "project" %in% anchors
  for (k in seq_along(msgs)) {
    m = msgs[[k]]
    role = m$role %||% ""
    same = handoff_same_model(m, model)
    mark = mark_project && identical(k, anchor_at)
    key = paste("openai-responses", role, adp_msg_key(m), same, mark, images, add_tools,
                sep = "|")
    el = adp_memo(opts, key, function() {
      items = switch(role,
                     user = responses_user(m, mark, images),
                     assistant = responses_assistant(m, model),
                     tool_result = responses_tool_result(m, images),
                     operator = responses_operator(m, add_tools),
                     list())
      if (!length(items)) "" else paste(vapply(items, json_encode, ""), collapse = ",")
    })
    if (nzchar(el)) elements = c(elements, el)
  }
  if (!is.null(params$returns)) {
    elements = c(elements, json_encode(list(role = "developer",
                                            content = adp_returns_instruction(params$returns))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  if (!is.null(opts$credential)) {
    headers$authorization = adp_header_secret(opts$credential, "Bearer ")
  }
  if (!is.null(context$request_id)) headers$`x-client-request-id` = context$request_id
  headers = adp_merge_headers(headers, adp_provider_headers(model, opts), auth = "authorization")

  list(url = adp_url(opts$base_url %||% "https://api.openai.com/v1", "responses"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "input", elements), stream = "sse")
}

#' builtin:openai: registers the openai-responses adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_openai = function(gptr) {
  gptr$register(gptr_adapter("openai-responses", transport = "http_sse",
                             build = responses_build, parse = responses_normaliser,
                             capabilities = responses_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("openai", builtin_openai))
