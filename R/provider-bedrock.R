# The bedrock-converse adapter (P26 Task 11, IC-80): Amazon Bedrock's ConverseStream API signed
# with AWS Signature Version 4, for IAM key pairs on AWS and for SigV4 gateways. Region and
# endpoint are provider-record data (`compat$region`, `base_url`). The response is AWS
# event-stream framing (prelude, headers, payload, CRC-32), decoded here from the raw body chunks
# (`stream = "raw"`); http-request.R signs each attempt through the request spec's `sign`, the
# only place the key pair is materialised. Unreported usage stays unknown (IC-74).

# ---- SigV4 (HMAC-SHA256 on cli's SHA-256) ----------------------------------------------------

#' The raw bytes of a hex digest
#' @noRd
hex_raw = function(hex) {
  n = nchar(hex)
  as.raw(strtoi(substring(hex, seq(1L, n, 2L), seq(2L, n, 2L)), 16L))
}

#' HMAC-SHA256 (RFC 2104) of `msg` (text or raw) under the raw `key`, as raw bytes
#' @noRd
hmac_sha256 = function(key, msg) {
  if (is.character(msg)) msg = charToRaw(as_utf8(msg))
  if (length(key) > 64L) key = hex_raw(hash_sha256(key))
  key = c(key, raw(64L - length(key)))
  inner = hex_raw(hash_sha256(c(xor(key, as.raw(0x36)), msg)))
  hex_raw(hash_sha256(c(xor(key, as.raw(0x5c)), inner)))
}

#' AWS Signature Version 4 of one request
#' `headers` are the headers to sign besides host and x-amz-date; the canonical URI encodes the
#' path as sent once more (the SDKs' rule for every service but S3). Returns the canonical
#' request, the string to sign, the signature and the headers to send (all signed but host,
#' then authorization).
#' @noRd
sigv4 = function(method, url, headers, payload_hash, key_id, secret, region, service,
                 time = Sys.time()) {
  date = format(time, "%Y%m%dT%H%M%SZ", tz = "UTC")
  day = substr(date, 1L, 8L)
  path = url_parse(url)$path %||% ""
  if (!nzchar(path)) path = "/"
  uri = gsub("%2F", "/", utils::URLencode(path, reserved = TRUE, repeated = TRUE), fixed = TRUE)
  h = c(list(host = sub("^[a-z]+://", "", url_origin(url)), `x-amz-date` = date), headers)
  names(h) = tolower(names(h))
  h = h[order(names(h), method = "radix")]
  signed = paste(names(h), collapse = ";")
  canonical = paste(c(toupper(method), uri, "", paste0(names(h), ":", trimws(unlist(h))), "",
                      signed, payload_hash), collapse = "\n")
  scope = paste(day, region, service, "aws4_request", sep = "/")
  sts = paste("AWS4-HMAC-SHA256", date, scope, hash_sha256(canonical), sep = "\n")
  k = charToRaw(as_utf8(paste0("AWS4", secret)))
  for (part in c(day, region, service, "aws4_request")) k = hmac_sha256(k, part)
  sig = paste(as.character(hmac_sha256(k, sts)), collapse = "")
  auth = paste0("AWS4-HMAC-SHA256 Credential=", key_id, "/", scope, ", SignedHeaders=", signed,
                ", Signature=", sig)
  list(canonical = canonical, string_to_sign = sts, signature = sig,
       headers = c(h[names(h) != "host"], list(authorization = auth)))
}

#' The `sign` function of a request spec (04 section 8.1): SigV4 for service `bedrock` with the
#' payload hash and, with a session token, x-amz-security-token. It holds handles only;
#' http-request.R passes `value()`, which materialises them for the request's own origin.
#' @noRd
bedrock_signer = function(key_id, secret, token, region) {
  force(key_id)
  force(secret)
  force(token)
  force(region)
  function(method, url, body, value) {
    hash = hash_sha256(body)
    h = list(`x-amz-content-sha256` = hash)
    if (!is.null(token)) h[["x-amz-security-token"]] = value(token)
    sigv4(method, url, h, hash, value(key_id), value(secret), region, "bedrock")$headers
  }
}

#' A handle for one variable of the key pair: the vault, else the environment (registered for
#' redaction and bound to `origin`); NULL when it is not set
#' @noRd
bedrock_handle = function(name, origin) {
  h = secret_lookup(name)
  if (credential_usable(h, origin)) return(credential_bind(h, origin))
  value = Sys.getenv(name, unset = "")
  if (nzchar(value)) credential_register(value, name, "env", origin)
}

# ---- AWS event-stream framing ------------------------------------------------------------------

#' The CRC-32 (IEEE) table split as top 8 and low 24 bits, so every value is an R integer
#' @noRd
bedrock_crc_table = local({
  th = integer(256L)
  tl = integer(256L)
  for (n in 0:255) {
    a = 0L
    r = n
    for (k in 1:8) {
      odd = bitwAnd(r, 1L) == 1L
      r = bitwOr(bitwShiftL(bitwAnd(a, 1L), 23L), bitwShiftR(r, 1L))
      a = bitwShiftR(a, 1L)
      if (odd) {
        a = bitwXor(a, 0xEDL)
        r = bitwXor(r, 0xB88320L)
      }
    }
    th[[n + 1L]] = a
    tl[[n + 1L]] = r
  }
  list(th = th, tl = tl)
})

#' The CRC-32 of raw bytes as a number (the register is kept as top 8 and low 24 bits)
#' @noRd
bedrock_crc32 = function(bytes) {
  th = bedrock_crc_table$th
  tl = bedrock_crc_table$tl
  a = 255L
  r = 16777215L
  for (x in as.integer(bytes)) {
    i = bitwXor(bitwAnd(r, 255L), x) + 1L
    r = bitwXor(bitwOr(bitwShiftL(a, 16L), bitwShiftR(r, 8L)), tl[[i]])
    a = th[[i]]
  }
  (255 - a) * 16777216 + (16777215 - r)
}

#' A big-endian unsigned integer of 2 or 4 bytes, as a number
#' @noRd
bedrock_uint = function(b) sum(as.numeric(as.integer(b)) * 256^(rev(seq_along(b)) - 1L))

#' The headers of one frame; string values are kept, other types skipped by their size
#' @noRd
bedrock_headers = function(b) {
  out = list()
  pos = 1L
  while (pos <= length(b)) {
    len = as.integer(b[[pos]])
    name = rawToChar(b[pos + seq_len(len)])
    type = as.integer(b[[pos + len + 1L]])
    pos = pos + len + 2L
    if (type %in% 6:7) {
      size = bedrock_uint(b[pos + 0:1])
      pos = pos + 2L
      if (type == 7L) out[[name]] = raw_to_utf8(b[pos + seq_len(size) - 1L])
    } else {
      size = c(0, 0, 1, 2, 4, 8, NA, NA, 8, 16)[type + 1L]
      if (is.na(size)) stop("unknown header value type ", type)
    }
    pos = pos + size
  }
  out
}

#' An AWS event-stream decoder: `push(raw)` returns the frames completed so far as
#' `list(headers, payload)`; a prelude or message CRC-32 mismatch or impossible lengths stop
#' @noRd
bedrock_decoder = function() {
  st = new.env(parent = emptyenv())
  st$buf = raw()
  function(bytes) {
    st$buf = c(st$buf, bytes)
    out = list()
    while (length(st$buf) >= 12L) {
      b = st$buf
      total = bedrock_uint(b[1:4])
      hlen = bedrock_uint(b[5:8])
      if (bedrock_crc32(b[1:8]) != bedrock_uint(b[9:12])) stop("prelude CRC mismatch")
      if (total < 16 || hlen > total - 16) stop("impossible frame lengths")
      if (length(b) < total) break
      if (bedrock_crc32(b[seq_len(total - 4)]) != bedrock_uint(b[total - 3:0])) {
        stop("message CRC mismatch")
      }
      out[[length(out) + 1L]] = list(headers = bedrock_headers(b[12L + seq_len(hlen)]),
                                     payload = b[12L + hlen + seq_len(total - 16 - hlen)])
      st$buf = b[-seq_len(total)]
    }
    out
  }
}

# ---- bedrock-converse: normaliser --------------------------------------------------------------

#' A Bedrock exception type -> class suffix (04 section 2.2), HTTP status and retryability
#' @noRd
bedrock_error_info = function(type) {
  switch(type,
         throttlingException = list(class = "rate_limit", status = 429L, retry = TRUE),
         serviceUnavailableException = list(class = "overloaded", status = 503L, retry = TRUE),
         internalServerException = list(class = "overloaded", status = 500L, retry = TRUE),
         modelStreamErrorException = list(class = "overloaded", status = 424L, retry = TRUE),
         validationException = list(class = "provider", status = 400L, retry = FALSE),
         list(class = "provider", status = NA_integer_, retry = FALSE))
}

#' The ConverseStream normaliser (04 section 8.1): pushes are raw body chunks; event frames
#' become content slots by `contentBlockIndex`, `messageStop` the stop reason, `metadata` the
#' usage and the terminal event; an exception frame is a stream error
#' @noRd
bedrock_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  decode = bedrock_decoder()
  slots = new.env(parent = emptyenv())
  usage_keys = c(input = "inputTokens", output = "outputTokens",
                 cache_read = "cacheReadInputTokens", cache_write_5m = "cacheWriteInputTokens")

  slot = function(e, type, ...) {
    key = paste0("i", adp_chr(e[["contentBlockIndex"]]))
    i = slots[[key]]
    if (is.null(i)) {
      i = adp_open(st, type, ...)
      assign(key, i, envir = slots)
    }
    i
  }

  # the slot is opened before adp_delta() reads st$blocks (a lazy index would read the old list)
  on_delta = function(e) {
    d = e[["delta"]]
    rc = d[["reasoningContent"]]
    if (!is.null(d[["text"]])) {
      i = slot(e, "text")
      adp_delta(st, i, adp_chr(d[["text"]]))
    } else if (is.list(d[["toolUse"]])) {
      i = slot(e, "tool_call", pj = partial_json())
      adp_delta(st, i, adp_chr(d[["toolUse"]][["input"]]))
    } else if (is.list(rc)) {
      i = slot(e, "thinking", signature = "")
      b = st$blocks[[i]]
      adp_delta(st, i, adp_chr(rc[["text"]]))
      b$signature = paste0(b$signature, adp_chr(rc[["signature"]]))
      if (!is.null(rc[["redactedContent"]])) {
        b$redacted = TRUE
        b$data = paste0(b$data %||% "", adp_chr(rc[["redactedContent"]]))
      }
    }
  }

  on_event = function(type, e) {
    if (type == "messageStart") {
      adp_start(st)
    } else if (type == "contentBlockStart") {
      tu = e[["start"]][["toolUse"]]
      if (is.list(tu)) {
        slot(e, "tool_call", id = adp_chr(tu[["toolUseId"]]), name = adp_chr(tu[["name"]]),
             pj = partial_json())
      }
    } else if (type == "contentBlockDelta") {
      on_delta(e)
    } else if (type == "contentBlockStop") {
      i = slots[[paste0("i", adp_chr(e[["contentBlockIndex"]]))]]
      if (!is.null(i)) adp_close(st, i)
    } else if (type == "messageStop") {
      raw = adp_chr(e[["stopReason"]])
      st$raw_stop = if (nzchar(raw)) raw
      filtered = raw %in% c("guardrail_intervened", "content_filtered")
      st$stop_reason = if (filtered) "refusal" else anthropic_stop(raw)
      if (filtered) st$error_message = paste0("The provider's filter stopped the answer: ", raw)
      if (st$stop_reason == "error") st$error_message = paste0("Provider stopped with: ", raw)
    } else if (type == "metadata") {
      u = e[["usage"]]
      for (f in names(usage_keys)) {
        if (is.list(u) && usage_keys[[f]] %in% names(u)) adp_usage_set(st, f, u[[usage_keys[[f]]]])
      }
      if (!is.null(st$stop_reason)) {
        adp_done(st)
        return(TRUE)
      }
    }
    FALSE
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    frames = tryCatch(decode(ev[["data"]]), error = function(e) e)
    if (inherits(frames, "error")) {
      adp_error(st, paste0("Could not decode the Bedrock event stream: ",
                           conditionMessage(frames)), class = "network")
      return(TRUE)
    }
    for (f in frames) {
      h = f$headers
      e = adp_json_try(raw_to_utf8(f$payload))
      kind = h[[":message-type"]] %||% "event"
      if (kind == "event") {
        if (on_event(h[[":event-type"]] %||% "", e)) return(TRUE)
        next
      }
      type = h[[":exception-type"]] %||% h[[":error-code"]] %||% kind
      text = adp_chr(e[["message"]])
      if (!nzchar(text)) text = h[[":error-message"]] %||% "no message"
      info = bedrock_error_info(type)
      return(adp_stream_error(st, opts, paste0(type, ": ", text), class = info$class,
                              status = info$status, retryable = info$retry))
    }
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    if (!is.null(st$stop_reason)) return(adp_done(st))
    adp_error(st, "The Bedrock stream ended before messageStop.", class = "network")
  }

  adp_normaliser(st, push, finish)
}

# ---- bedrock-converse: request body ------------------------------------------------------------

#' Adapter capabilities of bedrock-converse (04 section 8.1)
#' @noRd
bedrock_caps = function() {
  list(images_in_results = TRUE, reasoning_replay = TRUE, parallel_tools = TRUE,
       forced_tool_choice = FALSE, operator_role = "user", cache = "none", max_tool_name = 64L)
}

#' A Converse image block (base64 bytes), or a text note for a text-only model
#' @noRd
bedrock_image = function(b, images) {
  if (!images) return(list(text = adp_image_note()))
  format = sub("^image/", "", b$mime)
  list(image = list(format = if (format == "jpg") "jpeg" else format,
                    source = list(bytes = b$data)))
}

#' The blocks of a tool result: one toolResult (non-blank text and images, `status` for an
#' error), or without tools (`tools = FALSE`) the same content after a text label
#' @noRd
bedrock_tool_result = function(r, images, tools) {
  content = list()
  for (b in r$content) {
    if (identical(b$type, "text") && nzchar(trimws(b$text))) {
      content[[length(content) + 1L]] = list(text = b$text)
    } else if (identical(b$type, "image")) {
      content[[length(content) + 1L]] = bedrock_image(b, images)
    }
  }
  if (!length(content)) content = list(list(text = "(no tool output)"))
  if (!tools) return(c(list(list(text = paste0("[tool result of ", r$tool_name, "]"))), content))
  out = list(toolUseId = id_sanitize(r$tool_call_id, 64L), content = content)
  if (isTRUE(r$is_error)) out$status = "error"
  list(list(toolResult = out))
}

#' The content blocks of one message; signed or redacted reasoning is replayed only to the
#' model that produced it. Converse refuses toolUse and toolResult blocks without a toolConfig,
#' so with no tools to send (`tools = FALSE`) past calls and results are text.
#' @noRd
bedrock_content = function(m, model, images, tools) {
  role = m$role %||% ""
  if (role == "tool_result") return(bedrock_tool_result(m, images, tools))
  if (role == "operator") {
    text = adp_operator_text(m)
    return(if (nzchar(trimws(text))) list(list(text = text)) else list())
  }
  same = handoff_same_model(m, model)
  out = list()
  for (b in m$content) {
    type = b$type %||% ""
    p = NULL
    if (type %in% c("text", "context")) {
      if (nzchar(trimws(b$text))) p = list(text = b$text)
    } else if (type == "image") {
      p = bedrock_image(b, images)
    } else if (type == "tool_call") {
      args = if (length(b$arguments)) b$arguments else json_obj()
      p = if (tools) {
        list(toolUse = list(toolUseId = id_sanitize(b$id, 64L), name = b$name, input = args))
      } else {
        list(text = paste0("[tool call ", b$name, " ", json_encode(args), "]"))
      }
    } else if (type == "thinking" && same) {
      if (isTRUE(b$redacted) && !is.null(b$data)) {
        p = list(reasoningContent = list(redactedContent = b$data))
      } else if (nzchar(b$signature %||% "")) {
        p = list(reasoningContent = list(reasoningText = list(text = b$thinking,
                                                              signature = b$signature)))
      }
    }
    if (!is.null(p)) out[[length(out) + 1L]] = p
  }
  out
}

#' Converse tool specs from the frozen Anthropic-shape array
#' @noRd
bedrock_tools = function(tools) {
  lapply(tools, function(t) {
    d = t$description %||% ""
    list(toolSpec = list(name = t$name, description = if (nzchar(d)) d else t$name,
                         inputSchema = list(json = t$input_schema)))
  })
}

#' Anthropic's thinking fields for a Claude model, sent in `additionalModelRequestFields` (the
#' anthropic-messages rules, D-250); another model's level is not sent, said once per model
#' @noRd
bedrock_thinking = function(model, params) {
  if (grepl("anthropic\\.claude", model$id)) return(anthropic_thinking(model, params))
  level = params$thinking
  if (!is.null(level) && !identical(level, "off")) {
    ref = paste0(model$provider, "/", model$id)
    gptr_inform(paste0("Thinking level \"", level, "\" is not sent to ", ref, ": api = ",
                       "\"bedrock-converse\" sends thinking levels to Claude models only."),
                "notice", .once = paste0("bedrock_thinking:", ref))
  }
  list()
}

#' build() of the bedrock-converse adapter (04 section 8.1; IC-80)
#' Messages of one role in a row are one Converse message (tool results, operator text, the
#' `returns` instruction); with a credential the spec carries the SigV4 `sign` for
#' `compat$region` of the provider record.
#' @noRd
bedrock_build = function(model, context, opts) {
  params = context$params %||% list()
  images = adp_images_ok(model)
  tools = if (adp_tools_on(model, context)) {
    adp_tools_json(opts, "bedrock-converse", context$tools_json, bedrock_tools)
  }
  th = bedrock_thinking(model, params)
  inference = list()
  max_tokens = if (is.null(th$budget)) params$max_tokens else th$max_tokens
  if (!is.null(max_tokens)) inference$maxTokens = as.integer(max_tokens)
  if (!is.null(params$temperature) && !isTRUE(model$reasoning)) {
    inference$temperature = params$temperature
  }
  head = if (length(inference)) list(inferenceConfig = inference) else list()
  fields = list(thinking = th$thinking,
                output_config = if (!is.null(th$effort)) list(effort = th$effort),
                anthropic_beta = if (length(th$betas)) as.list(th$betas))
  fields = Filter(Negate(is.null), fields)
  if (length(fields)) head$additionalModelRequestFields = fields

  extra = character()
  sys = Filter(nzchar, c(context$system$t0 %||% "", context$system$t1 %||% ""))
  if (length(sys)) {
    key = paste("bedrock-converse", "system", hash_xxh128(sys), sep = "|")
    sys_json = adp_memo(opts, key, function() json_encode(lapply(sys, function(s) list(text = s))))
    extra = c(extra, paste0("\"system\":", sys_json))
  }
  sent = !is.null(tools)
  if (sent) extra = c(extra, paste0("\"toolConfig\":{\"tools\":", tools, "}"))

  roles = character()
  parts = character()
  add = function(role, part) {
    n = length(roles)
    if (n && roles[[n]] == role) {
      parts[[n]] <<- paste0(parts[[n]], ",", part)
    } else {
      roles <<- c(roles, role)
      parts <<- c(parts, part)
    }
  }
  for (m in context$messages %||% list()) {
    role = switch(m$role %||% "", assistant = "assistant", user = , tool_result = ,
                  operator = "user", "")
    key = paste("bedrock-converse", adp_msg_key(m), handoff_same_model(m, model), images, sent,
                sep = "|")
    part = adp_memo(opts, key, function() {
      blocks = bedrock_content(m, model, images, sent)
      if (!length(blocks)) "" else paste(vapply(blocks, json_encode, ""), collapse = ",")
    })
    if (nzchar(role) && nzchar(part)) add(role, part)
  }
  if (!is.null(params$returns)) {
    add("user", json_encode(list(text = adp_returns_instruction(params$returns))))
  }
  elements = paste0("{\"role\":\"", roles, "\",\"content\":[", parts, "]}")

  id = utils::URLencode(model$id, reserved = TRUE, repeated = TRUE)
  url = adp_url(opts$base_url %||% "", paste0("model/", id, "/converse-stream"))
  sign = NULL
  if (!is.null(opts$credential)) {
    pid = model$provider %||% ""
    region = adp_provider_record(model, opts)[["compat"]][["region"]]
    if (!rlang::is_string(region) || !nzchar(region)) {
      gptr_abort(paste0("Provider ", pid, " needs compat = list(region = ...) to sign its ",
                        "requests (AWS Signature Version 4)."),
                 "invalid_spec", kind = "provider", name = pid, field = "compat",
                 problem = "compat$region must be the region the endpoint signs for")
    }
    origin = provider_origin(url)
    key_id = bedrock_handle("AWS_ACCESS_KEY_ID", origin)
    if (is.null(key_id)) {
      gptr_abort(paste0("Provider ", pid, " needs AWS_ACCESS_KEY_ID with its secret key (for ",
                        "example from gptr_env())."),
                 "no_key", provider = pid, variables = "AWS_ACCESS_KEY_ID")
    }
    sign = bedrock_signer(key_id, opts$credential, bedrock_handle("AWS_SESSION_TOKEN", origin),
                          region)
  }
  headers = adp_merge_headers(list(`content-type` = "application/json"),
                              adp_provider_headers(model, opts))
  list(url = url, method = "POST", headers = headers,
       body = adp_body(head, extra, "messages", elements), stream = "raw", sign = sign)
}

#' builtin:bedrock: registers the bedrock-converse adapter (04 sections 7.12, 10.3; IC-80)
#' @noRd
builtin_bedrock = function(gptr) {
  gptr$register(gptr_adapter("bedrock-converse", transport = "http_sse", build = bedrock_build,
                             parse = bedrock_normaliser, capabilities = bedrock_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("bedrock", builtin_bedrock))
