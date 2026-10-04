# The provider-neutral message model (contract sections 4.1-4.3, 4.8; INFRA-07; report 03
# section 4.2). Records are unclassed named lists; every field is always present (NULL when
# unset). JSON uses Pi v3 field names at top level and puts gptr-only fields in a `gptr` object;
# NULL fields are omitted from JSON. Opaque provider data is kept byte for byte.

#' @noRd
msg_sources = c(
  "prompt", "pipe", "steer", "follow_up", "repl", "parent", "replay", "extension", "agent",
  "imported"
)

#' @noRd
msg_stop_reasons = c("stop", "length", "tool_use", "aborted", "error", "refusal", "pause")

#' @noRd
msg_routes = c("api", "plan-cli", "system-one", "emulated")

#' @noRd
msg_operator_kinds = c(
  "steer_relay", "mode", "model", "section_patch", "tool_change", "plan", "workspace", "reminder"
)

#' @noRd
image_sources = c("plot", "file", "screenshot", "user", "mcp")

#' Milliseconds since the epoch
#' @noRd
now_ms = function() {
  floor(as.numeric(Sys.time()) * 1000)
}

#' @noRd
block_text = function(text, signature = NULL) {
  check_string(signature, "signature", null = TRUE, empty = TRUE)
  text = paste(as_utf8(as.character(text)), collapse = "\n")
  list(type = "text", text = text, signature = signature)
}

#' @noRd
block_thinking = function(thinking, signature = NULL, redacted = FALSE, data = NULL,
                          origin = NULL) {
  check_string(signature, "signature", null = TRUE, empty = TRUE)
  check_flag(redacted, "redacted")
  check_string(data, "data", null = TRUE, empty = TRUE)
  check_list(origin, "origin", null = TRUE)
  list(
    type = "thinking", thinking = paste(as_utf8(as.character(thinking)), collapse = "\n"),
    signature = signature, redacted = redacted, data = data, origin = origin
  )
}

#' An image block; `data` is base64 text or a raw vector (encoded without line breaks)
#' @noRd
block_image = function(data, mime = "image/png", source = "plot", width = NULL, height = NULL) {
  if (is.raw(data)) data = gsub("\n", "", jsonlite::base64_enc(data), fixed = TRUE)
  check_string(data, "data", empty = TRUE)
  check_string(mime, "mime")
  source = check_choice(source, image_sources, "source")
  if (!is.null(width)) width = check_number(width, "width", min = 1, int = TRUE)
  if (!is.null(height)) height = check_number(height, "height", min = 1, int = TRUE)
  list(type = "image", mime = mime, data = data, source = source, width = width, height = height)
}

#' A tool call; `arguments` is a named list (a JSON object, empty = json_obj())
#' @noRd
block_tool_call = function(id, name, arguments, raw_arguments = NULL, thought_signature = NULL) {
  check_string(id, "id")
  check_string(name, "name")
  if (is.null(arguments) || !length(arguments)) arguments = json_obj()
  check_list(arguments, "arguments", named = TRUE)
  check_string(raw_arguments, "raw_arguments", null = TRUE, empty = TRUE)
  check_string(thought_signature, "thought_signature", null = TRUE, empty = TRUE)
  list(
    type = "tool_call", id = id, name = name, arguments = arguments,
    raw_arguments = raw_arguments, thought_signature = thought_signature
  )
}

#' Provider data replayed verbatim to the same model only
#' @noRd
block_opaque = function(provider, api, model, json) {
  check_string(provider, "provider")
  check_string(api, "api")
  check_string(model, "model")
  check_string(json, "json")
  list(type = "opaque", provider = provider, api = api, model = model, json = as_utf8(json))
}

#' A context block rendered as `<kind a="v">\ntext\n</kind>` (attribute values escape `"`)
#' @noRd
block_context = function(kind, text, attrs = list(), anchor = FALSE) {
  check_string(kind, "kind")
  check_list(attrs, "attrs", named = TRUE)
  check_flag(anchor, "anchor")
  attrs = lapply(attrs, function(value) as_utf8(as.character(value))[1L])
  attr_text = if (length(attrs)) {
    values = gsub("\"", "&quot;", unlist(attrs, use.names = FALSE), fixed = TRUE)
    paste0(" ", names(attrs), "=\"", values, "\"", collapse = "")
  } else {
    ""
  }
  body = paste(as_utf8(as.character(text)), collapse = "\n")
  list(
    type = "context", kind = kind, attrs = attrs,
    text = paste0("<", kind, attr_text, ">\n", body, "\n</", kind, ">"),
    anchor = anchor
  )
}

#' Content given as text becomes one text block; one block becomes a list of one
#' @noRd
as_content = function(content) {
  if (is.null(content)) return(list())
  if (is.character(content)) return(list(block_text(content)))
  if (is.list(content) && !is.null(content$type) && is.character(content$type)) {
    return(list(content))
  }
  check_list(content, "content")
  content
}

#' @noRd
msg_user = function(content, source = "prompt", timestamp = NULL) {
  source = check_choice(source, msg_sources, "source")
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "user", content = as_content(content), source = source,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_assistant = function(content, api, provider, model, usage = NULL, stop_reason = "stop",
                         response_id = NULL, response_model = NULL, error_message = NULL,
                         raw_stop_reason = NULL, thinking_level = NULL, route = "api",
                         request_id = NULL, timestamp = NULL) {
  check_string(api, "api")
  check_string(provider, "provider")
  check_string(model, "model")
  check_list(usage, "usage", null = TRUE)
  stop_reason = check_choice(stop_reason, msg_stop_reasons, "stop_reason")
  route = check_choice(route, msg_routes, "route")
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "assistant", content = as_content(content), api = api, provider = provider,
    model = model, response_id = response_id, response_model = response_model, usage = usage,
    stop_reason = stop_reason, error_message = error_message, raw_stop_reason = raw_stop_reason,
    thinking_level = thinking_level, route = route, request_id = request_id,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_tool_result = function(tool_call_id, tool_name, content, is_error = FALSE, details = NULL,
                           usage = NULL, timestamp = NULL) {
  check_string(tool_call_id, "tool_call_id")
  check_string(tool_name, "tool_name")
  check_flag(is_error, "is_error")
  check_list(details, "details", null = TRUE)
  check_list(usage, "usage", null = TRUE)
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "tool_result", tool_call_id = tool_call_id, tool_name = tool_name,
    content = as_content(content), is_error = is_error, details = details, usage = usage,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_operator = function(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL) {
  kind = check_choice(kind, msg_operator_kinds, "kind")
  check_list(tool_add, "tool_add", null = TRUE)
  check_string(origin_text, "origin_text", null = TRUE, empty = TRUE)
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "operator", kind = kind, content = list(block_text(text)), tool_add = tool_add,
    origin_text = origin_text, timestamp = timestamp %||% now_ms()
  )
}

#' Concatenated text blocks of a message (context blocks excluded), "" when there are none
#' @noRd
msg_text = function(msg) {
  texts = vapply(msg$content %||% list(), function(block) {
    if (identical(block$type, "text")) block$text else NA_character_
  }, "")
  texts = texts[!is.na(texts)]
  if (!length(texts)) return("")
  paste(texts, collapse = "\n")
}

#' Block types allowed per role
#' @noRd
msg_block_types = list(
  user = c("text", "image", "context"),
  assistant = c("text", "thinking", "tool_call", "opaque"),
  tool_result = c("text", "image"),
  operator = "text"
)

#' Required string fields of each block type
#' @noRd
msg_block_fields = list(
  text = "text", thinking = "thinking", image = c("mime", "data"), tool_call = c("id", "name"),
  opaque = c("provider", "api", "model", "json"), context = c("kind", "text")
)

#' Validate a message record; returns it invisibly or signals gptr_error_internal naming the field
#' @noRd
msg_validate = function(msg) {
  bad = function(field, problem) {
    gptr_abort(paste0("Invalid message: `", field, "` ", problem, "."), "internal", detail = field)
  }
  is_string = function(x) is.character(x) && length(x) == 1L && !is.na(x)
  in_set = function(x, set) is_string(x) && x %in% set
  if (!is.list(msg) || !in_set(msg$role, names(msg_block_types))) {
    bad("role", "must be one of user, assistant, tool_result, operator")
  }
  if (!is.list(msg$content)) bad("content", "must be a list of blocks")
  for (i in seq_along(msg$content)) {
    block = msg$content[[i]]
    field = paste0("content[[", i, "]]")
    if (!is.list(block) || !is_string(block$type)) bad(field, "must be a block with a type")
    if (!(block$type %in% msg_block_types[[msg$role]])) {
      bad(
        paste0(field, "$type"),
        paste0("\"", block$type, "\" is not allowed in a ", msg$role, " message")
      )
    }
    for (name in msg_block_fields[[block$type]]) {
      if (!is_string(block[[name]])) bad(paste0(field, "$", name), "must be a single string")
    }
    if (identical(block$type, "tool_call")) {
      arguments = block$arguments
      nms = names(arguments)
      if (!is.list(arguments) || is.null(nms) || anyNA(nms) ||
            any(!nzchar(nms)) || anyDuplicated(nms)) {
        bad(paste0(field, "$arguments"), "must be a list with unique, nonempty names")
      }
    }
  }
  if (!is.numeric(msg$timestamp) || is.complex(msg$timestamp) ||
        length(msg$timestamp) != 1L || !is.finite(msg$timestamp)) {
    bad("timestamp", "must be a finite real number")
  }
  if (msg$role == "user" && !in_set(msg$source, msg_sources)) {
    bad("source", "is not a known source")
  }
  if (msg$role == "assistant") {
    for (name in c("api", "provider", "model")) {
      if (!is_string(msg[[name]])) bad(name, "must be a single string")
    }
    if (!in_set(msg$stop_reason, msg_stop_reasons)) bad("stop_reason", "is not a known reason")
    if (!in_set(msg$route, msg_routes)) bad("route", "is not a known route")
  }
  if (msg$role == "tool_result") {
    for (name in c("tool_call_id", "tool_name")) {
      if (!is_string(msg[[name]])) bad(name, "must be a single string")
    }
    if (!is.logical(msg$is_error) || length(msg$is_error) != 1L || is.na(msg$is_error)) {
      bad("is_error", "must be TRUE or FALSE")
    }
  }
  if (msg$role == "operator" && !in_set(msg$kind, msg_operator_kinds)) {
    bad("kind", "is not a known operator kind")
  }
  invisible(msg)
}

# JSON mapping (contract section 4.8) ------------------------------------------------------------

#' The one R-to-JSON field mapping table (contract section 4.8); other names keep their spelling
#'
#' `cache_write_5m + cache_write_1h` -> `cacheWrite` is computed by usage_to_json(); `tool_use`
#' -> `toolUse` is a value mapping of `stop_reason` done by msg_to_json().
#' @noRd
json_field_map = c(
  tool_call = "toolCall", tool_result = "toolResult", thought_signature = "thoughtSignature",
  mime = "mimeType", tool_call_id = "toolCallId", tool_name = "toolName", is_error = "isError",
  stop_reason = "stopReason", error_message = "errorMessage", raw_stop_reason = "rawStopReason",
  response_id = "responseId", response_model = "responseModel",
  thinking_level = "thinkingLevel", cache_read = "cacheRead", cache_write_1h = "cacheWrite1h",
  total = "totalTokens", parent_id = "parentId", model_id = "modelId",
  custom_type = "customType", first_kept_entry_id = "firstKeptEntryId",
  tokens_before = "tokensBefore", parent_session = "parentSession", fork_of = "forkOf"
)

#' Rename the top-level names of a named list with json_field_map (to = "json" or "r")
#'
#' Used for session entries (P06); messages and blocks use msg_to_json(), which also handles
#' the per-block `signature` names (`textSignature`, `thinkingSignature`).
#' @noRd
json_rename = function(x, to = c("json", "r")) {
  to = check_choice(to, c("json", "r"), "to")
  nms = names(x)
  if (is.null(nms)) return(x)
  map = json_field_map
  if (identical(to, "r")) map = stats::setNames(names(json_field_map), json_field_map)
  hit = nms %in% names(map)
  nms[hit] = unname(map[nms[hit]])
  names(x) = nms
  x
}

#' Drop NULL elements of a list
#' @noRd
compact = function(x) {
  x[!vapply(x, is.null, logical(1))]
}

#' Drop NULL elements; NULL when nothing is left (so an empty `gptr` object is omitted)
#' @noRd
compact_or_null = function(x) {
  x = compact(x)
  if (length(x)) x else NULL
}

#' A named list for a JSON object (json_obj() when empty)
#' @noRd
as_json_object = function(x) {
  if (is.null(x) || !length(x)) json_obj() else x
}

#' @noRd
stop_reason_to_json = function(x) {
  if (identical(x, "tool_use")) "toolUse" else x
}

#' @noRd
stop_reason_from_json = function(x) {
  if (identical(x, "toolUse")) "tool_use" else x
}

#' Usage record to Pi's JSON shape
#' @noRd
usage_to_json = function(usage) {
  if (is.null(usage)) return(NULL)
  num = function(x) {
    value = as.numeric(x %||% 0)
    if (is.na(value)) NULL else value
  }
  cost = usage$cost %||% list()
  write_5m = usage$cache_write_5m %||% 0
  write_1h = usage$cache_write_1h %||% 0
  list(
    input = num(usage$input), output = num(usage$output), cacheRead = num(usage$cache_read),
    cacheWrite = num(write_5m + write_1h), cacheWrite1h = num(write_1h),
    reasoning = num(usage$reasoning),
    totalTokens = num(usage$total),
    cost = list(
      input = num(cost$input), output = num(cost$output), cacheRead = num(cost$cache_read),
      cacheWrite = num(cost$cache_write), total = num(cost$total)
    ),
    gptr = list(images = num(usage$images), estimated = isTRUE(usage$estimated))
  )
}

#' Pi's JSON usage to the usage record
#' @noRd
usage_from_json = function(x) {
  if (is.null(x)) return(NULL)
  # An explicit JSON null is unknown, whereas absent legacy fields retain their
  # documented zero defaults (for example Pi records without cacheWrite1h).
  num = function(record, name) {
    if (!(name %in% names(record))) return(0)
    value = record[[name]]
    if (is.null(value)) NA_real_ else as.numeric(value)
  }
  cost = x$cost %||% list()
  write_1h = num(x, "cacheWrite1h")
  list(
    input = num(x, "input"), output = num(x, "output"), cache_read = num(x, "cacheRead"),
    cache_write_5m = num(x, "cacheWrite") - write_1h, cache_write_1h = write_1h,
    reasoning = num(x, "reasoning"), images = num(x$gptr, "images"),
    total = num(x, "totalTokens"),
    cost = list(
      input = num(cost, "input"), output = num(cost, "output"),
      cache_read = num(cost, "cacheRead"), cache_write = num(cost, "cacheWrite"),
      total = num(cost, "total")
    ),
    estimated = isTRUE(x$gptr$estimated)
  )
}

#' One content block in JSON shape
#' @noRd
block_to_json = function(block) {
  switch(block$type,
    text = compact(list(type = "text", text = block$text, textSignature = block$signature)),
    thinking = compact(list(
      type = "thinking", thinking = block$thinking, thinkingSignature = block$signature,
      redacted = if (isTRUE(block$redacted)) TRUE,
      gptr = compact_or_null(list(data = block$data, origin = block$origin))
    )),
    image = compact(list(
      type = "image", data = block$data, mimeType = block$mime,
      gptr = compact_or_null(list(
        source = block$source, width = block$width, height = block$height
      ))
    )),
    tool_call = compact(list(
      type = "toolCall", id = block$id, name = block$name,
      arguments = as_json_object(block$arguments), thoughtSignature = block$thought_signature,
      gptr = compact_or_null(list(raw = block$raw_arguments))
    )),
    opaque = list(
      type = "opaque", provider = block$provider, api = block$api, model = block$model,
      json = block$json
    ),
    context = list(
      type = "text", text = block$text,
      gptr = compact(list(
        context = block$kind, attrs = as_json_object(block$attrs),
        anchor = if (isTRUE(block$anchor)) TRUE
      ))
    ),
    block
  )
}

#' One content block from JSON shape (unknown block types are kept as they are)
#' @noRd
block_from_json = function(x) {
  extra = x$gptr %||% list()
  switch(x$type %||% "",
    text = if (!is.null(extra$context)) {
      list(
        type = "context", kind = extra$context,
        attrs = if (length(extra$attrs)) extra$attrs else list(),
        text = x$text, anchor = isTRUE(extra$anchor)
      )
    } else {
      list(type = "text", text = x$text, signature = x$textSignature)
    },
    thinking = list(
      type = "thinking", thinking = x$thinking, signature = x$thinkingSignature,
      redacted = isTRUE(x$redacted), data = extra$data, origin = extra$origin
    ),
    image = list(
      type = "image", mime = x$mimeType, data = x$data, source = extra$source %||% "user",
      width = if (!is.null(extra$width)) as.integer(extra$width),
      height = if (!is.null(extra$height)) as.integer(extra$height)
    ),
    toolCall = list(
      type = "tool_call", id = x$id, name = x$name, arguments = as_json_object(x$arguments),
      raw_arguments = extra$raw, thought_signature = x$thoughtSignature
    ),
    opaque = list(
      type = "opaque", provider = x$provider, api = x$api, model = x$model, json = x$json
    ),
    x
  )
}

#' A message in JSON shape (a named list, not yet serialised)
#' @noRd
msg_to_json = function(msg) {
  content = lapply(msg$content, block_to_json)
  out = switch(msg$role,
    user = compact(list(
      role = "user", content = content, timestamp = msg$timestamp,
      gptr = list(source = msg$source)
    )),
    assistant = compact(list(
      role = "assistant", content = content, api = msg$api, provider = msg$provider,
      model = msg$model, responseId = msg$response_id, responseModel = msg$response_model,
      usage = usage_to_json(msg$usage), stopReason = stop_reason_to_json(msg$stop_reason),
      errorMessage = msg$error_message, rawStopReason = msg$raw_stop_reason,
      thinkingLevel = msg$thinking_level, timestamp = msg$timestamp,
      gptr = compact_or_null(list(route = msg$route, requestId = msg$request_id))
    )),
    tool_result = compact(list(
      role = "toolResult", toolCallId = msg$tool_call_id, toolName = msg$tool_name,
      content = content, details = if (!is.null(msg$details)) as_json_object(msg$details),
      isError = isTRUE(msg$is_error), usage = usage_to_json(msg$usage),
      timestamp = msg$timestamp
    )),
    operator = compact(list(
      role = "operator", customType = "gptr.operator", content = content,
      display = identical(msg$kind, "steer_relay"),
      details = compact(list(
        kind = msg$kind, toolAdd = msg$tool_add, originText = msg$origin_text
      )),
      timestamp = msg$timestamp
    ))
  )
  if (is.null(out)) {
    gptr_abort(
      paste0("Cannot serialise a message with role '", msg$role, "'."), "internal",
      detail = "role"
    )
  }
  for (name in names(msg$extra)) out[[name]] = msg$extra[[name]]
  out
}

#' Fields of each JSON message shape; anything else is kept under `extra`
#' @noRd
msg_json_fields = list(
  user = c("role", "content", "timestamp", "gptr"),
  assistant = c(
    "role", "content", "api", "provider", "model", "responseId", "responseModel", "usage",
    "stopReason", "errorMessage", "rawStopReason", "thinkingLevel", "timestamp", "gptr"
  ),
  toolResult = c(
    "role", "toolCallId", "toolName", "content", "details", "isError", "usage", "timestamp"
  ),
  operator = c("role", "customType", "content", "display", "details", "timestamp")
)

#' A message from its JSON shape (the inverse of msg_to_json())
#' @noRd
msg_from_json = function(x) {
  role = x$role %||% (if (identical(x$customType, "gptr.operator")) "operator")
  if (is.null(role) || !(role %in% names(msg_json_fields))) {
    gptr_abort("Cannot read a message without a known role.", "internal", detail = "role")
  }
  content = x$content
  if (is.character(content)) content = list(list(type = "text", text = content))
  content = lapply(content %||% list(), block_from_json)
  timestamp = as.numeric(x$timestamp %||% now_ms())
  msg = switch(role,
    user = list(
      role = "user", content = content, source = x$gptr$source %||% "prompt",
      timestamp = timestamp
    ),
    assistant = list(
      role = "assistant", content = content, api = x$api, provider = x$provider,
      model = x$model, response_id = x$responseId, response_model = x$responseModel,
      usage = usage_from_json(x$usage),
      stop_reason = stop_reason_from_json(x$stopReason %||% "stop"),
      error_message = x$errorMessage, raw_stop_reason = x$rawStopReason,
      thinking_level = x$thinkingLevel, route = x$gptr$route %||% "api",
      request_id = x$gptr$requestId, timestamp = timestamp
    ),
    toolResult = list(
      role = "tool_result", tool_call_id = x$toolCallId, tool_name = x$toolName,
      content = content, is_error = isTRUE(x$isError), details = x$details,
      usage = usage_from_json(x$usage), timestamp = timestamp
    ),
    operator = list(
      role = "operator", kind = x$details$kind, content = content,
      tool_add = x$details$toolAdd, origin_text = x$details$originText, timestamp = timestamp
    )
  )
  extra = x[setdiff(names(x), msg_json_fields[[role]])]
  if (length(extra)) msg$extra = extra
  msg
}
