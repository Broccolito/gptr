# A base-R mock of LLM provider endpoints for gptr's tests (contract section 12.2, IC-45, IC-64,
# IC-71). Adapted from the verified prototypes of report 15 section 5.1 (mock_sse_base.R:
# serverSocket() + socketSelect(), every client multiplexed in one process) and report 10a
# appendix A.1 (mock_anthropic.R: scenario plans). Started by local_mock_server() as
#   Rscript --vanilla mock_server.R <config.rds>
# config: list(ports, token, scenario, args, log, ready, parent_pid). Only request paths that
# start with /<token>/ are answered; the response depends on the scenario, not on the path.

`%||%` = function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

cfg = readRDS(commandArgs(trailingOnly = TRUE)[[1L]])
args = cfg$args
opt = function(name, default) args[[name]] %||% default
now = function() as.numeric(Sys.time())
json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
obj = function() structure(list(), names = character())

sse = function(event, data) {
  data = if (is.character(data)) data else json(data)
  paste0(if (!is.null(event)) paste0("event: ", event, "\n"), "data: ", data, "\n\n")
}

log_line = function(x) {
  cat(json(x), "\n", file = cfg$log, append = TRUE, sep = "")
}

# With `log_writes = TRUE` every response piece is also logged as kind "write" (INFRA-01 measures
# delivery from the moment the mock writes a delta; DEVIATIONS D-016)
log_writes = isTRUE(opt("log_writes", FALSE))

# ---- Anthropic Messages stream pieces (report 10a A.1; report 15 section 3.2) ----------------

msg_start = function(model) {
  list(
    type = "message_start",
    message = list(
      id = "msg_mock", type = "message", role = "assistant", model = model, content = list(),
      stop_reason = NULL,
      usage = list(input_tokens = 100L, output_tokens = 1L, cache_read_input_tokens = 0L,
                   cache_creation_input_tokens = 0L)
    )
  )
}

block_start = function(index, block) {
  sse("content_block_start", list(type = "content_block_start", index = index,
                                  content_block = block))
}

block_stop = function(index) {
  sse("content_block_stop", list(type = "content_block_stop", index = index))
}

text_delta = function(index, text) {
  sse("content_block_delta", list(type = "content_block_delta", index = index,
                                  delta = list(type = "text_delta", text = text)))
}

json_delta = function(index, text) {
  sse("content_block_delta", list(type = "content_block_delta", index = index,
                                  delta = list(type = "input_json_delta", partial_json = text)))
}

finish = function(reason, out = 20L) {
  c(
    sse("message_delta", list(type = "message_delta", delta = list(stop_reason = reason),
                              usage = list(output_tokens = out))),
    sse("message_stop", list(type = "message_stop"))
  )
}

# A list of list(delay, text): `delay` seconds after the previous write
at = function(delay, text) list(list(delay = delay, text = paste(text, collapse = "")))

anthropic_text = function(model, n, interval, first = interval) {
  items = at(0, c(sse("message_start", msg_start(model)),
                  block_start(0L, list(type = "text", text = ""))))
  for (i in seq_len(n)) {
    items = c(items, at(if (i == 1L) first else interval, text_delta(0L, sprintf("tok%02d ", i))))
  }
  c(items, at(0, c(block_stop(0L), finish("end_turn", n + 10L))))
}

anthropic_tools = function(model, interval) {
  tool = function(index, id, name, input) {
    text = json(input)
    cut = ceiling(nchar(text) / 2)
    c(
      block_start(index, list(type = "tool_use", id = id, name = name, input = obj())),
      json_delta(index, substr(text, 1L, cut)),
      json_delta(index, substr(text, cut + 1L, nchar(text))),
      block_stop(index)
    )
  }
  c(
    at(0, sse("message_start", msg_start(model))),
    at(interval, tool(0L, "toolu_A", "read", list(path = "a.R"))),
    at(interval, tool(1L, "toolu_B", "r", list(code = "1 + 1"))),
    at(0, finish("tool_use"))
  )
}

anthropic_error_body = function(status) {
  type = switch(as.character(status),
    "400" = "invalid_request_error", "401" = "authentication_error",
    "403" = "permission_error", "404" = "not_found_error", "413" = "request_too_large",
    "429" = "rate_limit_error", "529" = "overloaded_error", "api_error"
  )
  json(list(type = "error", error = list(type = type, message = paste("mock", type)),
            request_id = "req_mock"))
}

# ---- other wire shapes (reports 08 section 3.3, 03, 09 section 3.1, 04a) ---------------------

responses_stream = function(model, n, interval) {
  seq_no = 0L
  ev = function(type, data) {
    seq_no <<- seq_no + 1L
    sse(type, c(list(type = type), data, list(sequence_number = seq_no)))
  }
  text = paste(sprintf("tok%02d ", seq_len(n)), collapse = "")
  item = list(id = "msg_mock", type = "message", role = "assistant", status = "in_progress",
              content = list())
  part = list(type = "output_text", text = "", annotations = list())
  items = at(0, c(
    ev("response.created", list(response = list(id = "resp_mock", status = "in_progress"))),
    ev("response.output_item.added", list(output_index = 0L, item = item)),
    ev("response.content_part.added", list(item_id = "msg_mock", output_index = 0L,
                                           content_index = 0L, part = part))
  ))
  for (i in seq_len(n)) {
    items = c(items, at(interval, ev("response.output_text.delta", list(
      item_id = "msg_mock", output_index = 0L, content_index = 0L,
      delta = sprintf("tok%02d ", i), logprobs = list()
    ))))
  }
  done_part = list(type = "output_text", text = text, annotations = list())
  done_item = list(id = "msg_mock", type = "message", role = "assistant", status = "completed",
                   content = list(done_part))
  usage = list(input_tokens = 100L, output_tokens = n + 10L,
               output_tokens_details = list(reasoning_tokens = 0L), total_tokens = n + 110L,
               input_tokens_details = list(cached_tokens = 0L))
  c(items, at(0, c(
    ev("response.output_text.done", list(item_id = "msg_mock", output_index = 0L,
                                         content_index = 0L, text = text)),
    ev("response.content_part.done", list(item_id = "msg_mock", output_index = 0L,
                                          content_index = 0L, part = done_part)),
    ev("response.output_item.done", list(output_index = 0L, item = done_item)),
    ev("response.completed", list(response = list(
      id = "resp_mock", object = "response", status = "completed", model = model,
      output = list(done_item), store = FALSE, usage = usage
    )))
  )))
}

completions_stream = function(model, n, interval) {
  chunk = function(delta, finish_reason = NULL, choices = TRUE, usage = NULL) {
    choice = list(index = 0L, delta = delta, finish_reason = finish_reason)
    sse(NULL, list(
      id = "chatcmpl-mock", object = "chat.completion.chunk", created = 1759100000L,
      model = model, choices = if (choices) list(choice) else list(), usage = usage
    ))
  }
  items = at(0, chunk(list(role = "assistant", content = "")))
  for (i in seq_len(n)) {
    items = c(items, at(interval, chunk(list(content = sprintf("tok%02d ", i)))))
  }
  usage = list(prompt_tokens = 100L, completion_tokens = n + 10L, total_tokens = n + 110L)
  c(items, at(0, c(
    chunk(obj(), finish_reason = "stop"),
    chunk(obj(), choices = FALSE, usage = usage),
    sse(NULL, "[DONE]")
  )))
}

gemini_stream = function(model, n, interval) {
  items = list()
  for (i in seq_len(n)) {
    candidate = list(content = list(parts = list(list(text = sprintf("tok%02d ", i))),
                                    role = "model"), index = 0L)
    data = list(candidates = list(candidate), modelVersion = model, responseId = "resp_mock")
    if (i == n) {
      data$candidates[[1L]]$finishReason = "STOP"
      data$usageMetadata = list(promptTokenCount = 100L, candidatesTokenCount = n + 10L,
                                totalTokenCount = n + 110L)
    }
    items = c(items, at(if (i == 1L) 0 else interval, sse(NULL, data)))
  }
  items
}

systemone_answers = function(body) {
  answers = list()
  for (id in names(body$questions)) {
    q = body$questions[[id]]
    answers[[id]] = switch(q$type %||% "noul",
      choice = {
        labels = names(q$criteria)
        probs = stats::setNames(as.list(c(1, rep(0, length(labels) - 1L))), labels)
        list(type = "choice", choice = labels[[1L]], confidence = 1, probabilities = probs)
      },
      score = {
        k = length(q$criteria)
        list(type = "score", score = 0, confidence = 1,
             legend = stats::setNames(q$criteria, as.character(seq_len(k) - 1L)),
             probabilities = stats::setNames(as.list(c(1, rep(0, k - 1L))),
                                             as.character(seq_len(k) - 1L)))
      },
      list(type = "noul", noul = 0.9)
    )
  }
  answers
}

# ---- scenario plans ---------------------------------------------------------------------------

sse_headers = c(`content-type` = "text/event-stream", `cache-control` = "no-cache")

plan = function(req, k) {
  body = tryCatch(jsonlite::fromJSON(req$body, simplifyVector = FALSE), error = function(e) {
    list()
  })
  model = body$model %||% "mock-1"
  n = as.integer(opt("n", 12L))
  interval = as.numeric(opt("interval", 0.25))
  request_id = c(`request-id` = paste0("req_mock_", k))
  stream = function(items, end = "close", head_delay = 0) {
    list(status = 200L, headers = c(sse_headers, request_id), items = items, end = end,
         head_delay = head_delay, chunked = isTRUE(opt("chunked", TRUE)))
  }
  reply = function(status, text, type = "application/json", headers = character()) {
    list(status = status, headers = c(`content-type` = type, request_id, headers),
         items = at(0, text), end = "close", head_delay = 0, chunked = FALSE,
         length = TRUE)
  }
  short = function() anthropic_text(model, 3L, 0.02)
  switch(cfg$scenario,
    stream = stream(anthropic_text(model, n, interval)),
    slow = stream(anthropic_text(model, as.integer(opt("n", 5L)), as.numeric(opt("interval", 1)))),
    ttft = stream(anthropic_text(model, as.integer(opt("n", 4L)),
                                 as.numeric(opt("interval", 0.05))),
                  head_delay = as.numeric(opt("delay", 3))),
    hold_headers = list(status = 200L, headers = sse_headers, items = list(), end = "hold",
                        head_delay = Inf, chunked = FALSE),
    stall = {
      items = anthropic_text(model, as.integer(opt("n", 3L)), as.numeric(opt("interval", 0.05)))
      stream(items[-length(items)], end = "hold")
    },
    bytes_per_10s = {
      every = as.numeric(opt("every", 10))
      beats = max(1L, floor(as.numeric(opt("duration", 600)) / every))
      bytes = rep(c(":", "\n"), length.out = 2L * ceiling(beats / 2))
      items = c(lapply(bytes, function(b) list(delay = every, text = b)),
                anthropic_text(model, 3L, 0))
      stream(items)
    },
    overload = if (k <= as.integer(opt("attempts", 1L))) {
      after = as.integer(opt("after", 0L))
      items = at(0, sse("message_start", msg_start(model)))
      if (after > 0L) {
        items = c(items, at(0, block_start(0L, list(type = "text", text = ""))))
        for (i in seq_len(after)) {
          items = c(items, at(0.02, text_delta(0L, sprintf("tok%02d ", i))))
        }
      }
      error = list(type = "error", error = list(type = "overloaded_error", message = "Overloaded"))
      stream(c(items, at(0.02, sse("error", error))))
    } else {
      stream(short())
    },
    status = if (k <= as.numeric(opt("succeed_after", Inf))) {
      status = as.integer(opt("status", 500L))
      extra = character()
      if (!is.null(args$retry_after)) extra[["retry-after"]] = as.character(args$retry_after)
      if (!is.null(args$retry_after_ms)) {
        extra[["retry-after-ms"]] = as.character(args$retry_after_ms)
      }
      reply(status, opt("body", anthropic_error_body(status)), headers = extra)
    } else {
      stream(short())
    },
    spend_cap = reply(429L, json(list(
      type = "error",
      error = list(type = "rate_limit_error",
                   message = "You have reached your specified API usage limits.",
                   details = list(error_code = "enforced_spend_limit_reached")),
      request_id = "req_mock"
    ))),
    truncated = {
      items = anthropic_text(model, as.integer(opt("n", 3L)), as.numeric(opt("interval", 0.02)))
      stream(items[-length(items)], end = "truncate")
    },
    parallel_tools = {
      messages = body$messages %||% list()
      last = if (length(messages)) messages[[length(messages)]] else list()
      after_tool = is.list(last$content) && any(vapply(last$content, function(b) {
        identical(b$type, "tool_result")
      }, logical(1)))
      if (after_tool) {
        stream(c(at(0, c(sse("message_start", msg_start(model)),
                         block_start(0L, list(type = "text", text = "")),
                         text_delta(0L, "both done"), block_stop(0L))),
                 at(0, finish("end_turn"))))
      } else {
        stream(anthropic_tools(model, as.numeric(opt("interval", 0.02))))
      }
    },
    openai_responses = stream(responses_stream(model, as.integer(opt("n", 5L)),
                                               as.numeric(opt("interval", 0.05)))),
    chat_completions = stream(completions_stream(model, as.integer(opt("n", 5L)),
                                                 as.numeric(opt("interval", 0.05)))),
    gemini = stream(gemini_stream(model, as.integer(opt("n", 5L)),
                                  as.numeric(opt("interval", 0.05)))),
    systemone = {
      answers = if (is.function(args$answers)) args$answers(body) else systemone_answers(body)
      text = json(list(model = "jev-mock-1.0", answers = answers,
                       usage = list(input_tokens = 100L,
                                    output_tokens = 10L * length(body$questions))))
      reply(200L, text, headers = c(`x-typesafe-request-id` = paste0("req_mock_", k)))
    },
    json = reply(as.integer(opt("status", 200L)), opt("body", "{}"),
                 type = opt("content_type", "application/json")),
    redirect = reply(307L, "", headers = c(location = sprintf(
      "http://127.0.0.1:%d/%s/redirected-to-second-origin", port2, cfg$token
    ))),
    reply(404L, json(list(error = paste("unknown scenario", cfg$scenario))))
  )
}

# ---- HTTP plumbing ----------------------------------------------------------------------------

srv = new.env()
srv$clients = list()
srv$next_id = 0L
srv$next_client = 0L
srv$k = 0L

sensitive = "authorization|api-key|x-api-key|x-goog-api-key|cookie|token|secret|key"

parse_request = function(buf) {
  head_end = grepRaw("\r\n\r\n", buf, fixed = TRUE)
  if (!length(head_end)) return(NULL)
  head = strsplit(rawToChar(buf[seq_len(head_end - 1L)]), "\r\n", fixed = TRUE)[[1L]]
  line = strsplit(head[[1L]], " ", fixed = TRUE)[[1L]]
  hnames = tolower(trimws(sub(":.*$", "", head[-1L])))
  hvalues = trimws(sub("^[^:]*:", "", head[-1L]))
  clen = suppressWarnings(as.integer(hvalues[hnames == "content-length"][1L]))
  if (is.na(clen)) clen = 0L
  start = head_end + 4L
  list(
    method = line[[1L]], target = if (length(line) > 1L) line[[2L]] else "/",
    names = hnames, values = hvalues, length = clen, start = start,
    complete = length(buf) - start + 1L >= clen,
    expect = any(hnames == "expect" & tolower(hvalues) == "100-continue")
  )
}

# Request headers for the log. Values of sensitive headers are redacted, except at the second
# origin of the `redirect` scenario: it stands for a foreign server, so it logs every byte it
# receives and a test can see a key that a client carried across origins (IC-64).
log_headers = function(hnames, hvalues, redact = TRUE) {
  if (redact) hvalues[grepl(sensitive, hnames, ignore.case = TRUE)] = "[redacted]"
  paste(paste0(hnames, ": ", hvalues), collapse = "\n")
}

frame = function(text, chunked) {
  bytes = charToRaw(text)
  if (!chunked || !length(bytes)) return(bytes)
  c(charToRaw(sprintf("%x\r\n", length(bytes))), bytes, charToRaw("\r\n"))
}

status_text = c(`200` = "OK", `307` = "Temporary Redirect", `404` = "Not Found")

response_head = function(res) {
  reason = unname(status_text[as.character(res$status)])
  if (is.na(reason)) reason = "Mock"
  headers = c(res$headers, connection = "close")
  if (isTRUE(res$length)) {
    bytes = vapply(res$items, function(item) length(charToRaw(item$text)), numeric(1))
    headers[["content-length"]] = as.character(sum(bytes))
  } else if (isTRUE(res$chunked)) {
    headers[["transfer-encoding"]] = "chunked"
  }
  extra = unlist(args$headers %||% list())
  if (length(extra)) headers[names(extra)] = extra
  paste0("HTTP/1.1 ", res$status, " ", reason, "\r\n",
         paste0(names(headers), ": ", headers, "\r\n", collapse = ""), "\r\n")
}

# The SSE event a response piece starts with, named in the write log ("" for other bytes)
first_event = function(text) {
  hit = regmatches(text, regexpr("^event: [^\r\n]*", text))
  if (length(hit)) substring(hit, 8L) else ""
}

schedule = function(cl, res) {
  t = now() + res$head_delay
  queue = list(list(due = t, bytes = charToRaw(response_head(res)), event = "head"))
  for (item in res$items) {
    t = t + item$delay
    queue[[length(queue) + 1L]] = list(due = t, bytes = frame(item$text, isTRUE(res$chunked)),
                                       event = first_event(item$text))
  }
  if (res$end == "close" && isTRUE(res$chunked)) {
    queue[[length(queue) + 1L]] = list(due = t, bytes = charToRaw("0\r\n\r\n"), event = "")
  }
  if (is.infinite(res$head_delay)) queue = list()
  cl$queue = queue
  cl$end = res$end
  cl$state = "respond"
  cl
}

finish_client = function(key, disconnected) {
  cl = srv$clients[[key]]
  if (!is.null(cl$req_id)) {
    log_line(list(kind = "end", id = cl$req_id, time = now(), disconnected = disconnected))
  }
  try(close(cl$con), silent = TRUE)
  srv$clients[[key]] = NULL
  invisible(NULL)
}

plain = function(status, text) {
  list(status = status, headers = c(`content-type` = "text/plain"), items = at(0, text),
       end = "close", head_delay = 0, chunked = FALSE, length = TRUE)
}

respond = function(cl, req, body) {
  prefix = paste0("/", cfg$token)
  target = req$target
  known = identical(target, prefix) || startsWith(target, paste0(prefix, "/"))
  path = if (known) substring(target, nchar(prefix) + 1L) else target
  if (!nzchar(path)) path = "/"
  srv$next_id = srv$next_id + 1L
  cl$req_id = srv$next_id
  second = identical(cl$origin, "second")
  log_line(list(
    kind = "request", id = srv$next_id, time = now(), method = req$method, path = path,
    headers = log_headers(req$names, req$values, redact = !second),
    body = if (known) body else ""
  ))
  res = if (!known) {
    plain(404L, "not found")
  } else if (second) {
    plain(200L, "{}")
  } else {
    srv$k = srv$k + 1L
    tryCatch(
      plan(list(method = req$method, path = path, body = body), srv$k),
      error = function(e) plain(500L, paste("mock server error:", conditionMessage(e)))
    )
  }
  schedule(cl, res)
}

handle_read = function(key, chunk) {
  cl = srv$clients[[key]]
  if (!length(chunk)) {
    if (identical(cl$state, "read")) {
      try(close(cl$con), silent = TRUE)
      srv$clients[[key]] = NULL
    } else {
      finish_client(key, disconnected = TRUE)
    }
    return(invisible(NULL))
  }
  if (!identical(cl$state, "read")) return(invisible(NULL))
  cl$buf = c(cl$buf, chunk)
  req = parse_request(cl$buf)
  if (!is.null(req) && !req$complete && req$expect && !isTRUE(cl$continued)) {
    writeBin(charToRaw("HTTP/1.1 100 Continue\r\n\r\n"), cl$con)
    cl$continued = TRUE
  }
  if (!is.null(req) && req$complete) {
    body = if (req$length > 0L) rawToChar(cl$buf[req$start:(req$start + req$length - 1L)]) else ""
    cl = respond(cl, req, body)
  }
  srv$clients[[key]] = cl
  invisible(NULL)
}

write_due = function(key) {
  cl = srv$clients[[key]]
  t = now()
  while (length(cl$queue) && cl$queue[[1L]]$due <= t) {
    at = now()
    ok = tryCatch({
      writeBin(cl$queue[[1L]]$bytes, cl$con)
      flush(cl$con)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) return(finish_client(key, disconnected = TRUE))
    if (log_writes && !is.null(cl$req_id)) {
      log_line(list(kind = "write", id = cl$req_id, time = at, event = cl$queue[[1L]]$event))
    }
    cl$queue = cl$queue[-1L]
  }
  srv$clients[[key]] = cl
  if (!length(cl$queue) && cl$end %in% c("close", "truncate")) {
    finish_client(key, disconnected = FALSE)
  }
  invisible(NULL)
}

# ---- start: listen, report the ports, serve ---------------------------------------------------

listen = function(candidates) {
  for (port in candidates) {
    socket = tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(socket)) return(list(socket = socket, port = port))
  }
  stop("no free port among the candidates")
}

primary = listen(cfg$ports)
servers = list(first = primary$socket)
port2 = NA_integer_
if (identical(cfg$scenario, "redirect")) {
  secondary = listen(setdiff(cfg$ports, primary$port))
  servers$second = secondary$socket
  port2 = secondary$port
}
ready_tmp = paste0(cfg$ready, ".tmp")
writeLines(json(list(port = primary$port, port2 = port2)), ready_tmp)
file.rename(ready_tmp, cfg$ready)

parent = tryCatch(ps::ps_handle(cfg$parent_pid), error = function(e) NULL)
started = now()
last_check = started

repeat {
  t = now()
  if (t - last_check > 1) {
    last_check = t
    alive = !is.null(parent) && isTRUE(tryCatch(ps::ps_is_running(parent), error = function(e) {
      FALSE
    }))
    if (!alive || t - started > 900) break
  }
  keys = names(srv$clients)
  dues = vapply(srv$clients, function(cl) {
    if (length(cl$queue)) cl$queue[[1L]]$due else Inf
  }, numeric(1))
  wait = max(0, min(c(0.25, dues - t)))
  cons = c(servers, lapply(srv$clients, `[[`, "con"))
  ready = socketSelect(cons, write = FALSE, timeout = wait)
  for (i in seq_along(servers)) {
    if (ready[[i]]) {
      srv$next_client = srv$next_client + 1L
      srv$clients[[as.character(srv$next_client)]] = list(
        con = socketAccept(servers[[i]], blocking = FALSE, open = "r+b"), buf = raw(0),
        state = "read", origin = names(servers)[[i]], queue = list()
      )
    }
  }
  for (key in keys[ready[-seq_along(servers)]]) {
    if (is.null(srv$clients[[key]])) next
    chunk = tryCatch(readBin(srv$clients[[key]]$con, "raw", 65536L), error = function(e) raw(0))
    tryCatch(handle_read(key, chunk), error = function(e) {
      finish_client(key, disconnected = TRUE)
    })
  }
  for (key in names(srv$clients)) {
    if (!is.null(srv$clients[[key]]) && length(srv$clients[[key]]$queue)) write_due(key)
  }
}
