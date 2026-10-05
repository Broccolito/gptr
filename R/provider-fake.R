# The fake provider (contract sections 6.7, 12.1; IC-08, IC-21; INFRA-24a). It plays a script
# instead of calling a model and emits the same INFRA-02 events as a real adapter, so every later
# plan tests the agent loop, tools, queues, stores and documents offline.

# Weak references (key = the log environment) to the most recent fake provider of each name: a
# fallback for model records that lost their `fake` field. They never keep a script alive.
the$fakes = list()

#' A scripted, offline fake model provider
#'
#' `gptr_fake_provider()` returns a provider spec that plays a script instead of calling a
#' model. It needs no network and no keys, so examples, tests and documents can run gptr end to
#' end offline. Use it as `model = <spec>` or register it with `gptr_register()`.
#'
#' A chat script is a list of replies (request `i` gets reply `min(i, length(script))`, so the
#' last reply repeats) or a function of the request returning one reply. The request is a list
#' with `n`, `model`, `system`, `tools`, `messages`, `last_user`, `last_results` and `params`. A
#' reply is a string (the answer text) or a list with any of: `text`; `thinking` and
#' `signature`; `tool` with `input` and `id` (one tool call); `tools` (a list of
#' `list(name, input)` for parallel calls); `stop` (`"length"`, `"refusal"`, `"pause"` or
#' `"stop"`); `error` with `status` and `after` (fail after `after` text deltas);
#' `overflow = TRUE`; `hang = TRUE`; `json` (a structured answer); and the modifiers `delay`,
#' `gap`, `chunk` and `usage`.
#'
#' A classifier script (`type = "classifier"`) answers System 1 questions: a list of answers
#' (recycled the same way, one answer per question asked) or `function(state, question)`. An
#' answer is a probability for yes/no questions, a named probability vector for choices, a
#' vector of level probabilities for scores, or `list(error =, status =)`. Classifier results
#' use the provider-neutral decision shape and report calibration as unknown (`NA`).
#'
#' @param script A list of replies or a function (see Details).
#' @param name Provider id: lower-case letters, digits and `-`.
#' @param type `"chat"` (the default) or `"classifier"`.
#' @return A provider spec: a list of class `c("gptr_provider", "gptr_spec")` with `id = name`,
#'   `api` `"fake"` or `"fake-classifier"`, one model (`"<name>/<name>-1"`, or
#'   `"<name>/<name>-s1"` for classifiers), `offline = TRUE`, the `script`, and `log`, an
#'   environment whose `requests` element lists every request the provider received.
#' @export
#' @examples
#' fake = gptr_fake_provider(list(
#'   list(tool = "r", input = list(code = "n = nrow(d)")),
#'   "There are 32 rows."
#' ))
#' fake$models[[1]]$ref
#' fake$offline
#'
#' judge = gptr_fake_provider(list(0.93), name = "judge", type = "classifier")
#' judge$models[[1]]$ref
gptr_fake_provider = function(script, name = "fake", type = c("chat", "classifier")) {
  type = check_choice(type, c("chat", "classifier"), "type")
  check_string(name, "name")
  if (!grepl("^[a-z0-9][a-z0-9-]*$", name)) {
    arg_abort(name, "name", "lower-case letters, digits and '-', starting with a letter or digit")
  }
  if (is.character(script)) script = as.list(script)
  if (!is.function(script) && !is.list(script)) {
    arg_abort(script, "script", "a list of replies or a function")
  }
  api = if (identical(type, "chat")) "fake" else "fake-classifier"
  log = new.env(parent = emptyenv())
  log$requests = list()
  log$n = 0L
  log$script = script
  log$name = name
  log$type = type
  the$fakes[[name]] = rlang::new_weakref(key = log)
  structure(
    list(
      kind = "provider", name = name, id = name, api = api, type = type, base_url = NULL,
      auth = NULL, local = TRUE, models = list(fake_model_record(name, type, api, log)),
      compat = list(), headers = list(), aliases = character(), offline = TRUE,
      script = script, log = log, api_version = "1.0"
    ),
    class = c("gptr_provider", "gptr_spec")
  )
}

#' The one model record of a fake provider (contract section 4.9 fields plus `fake`, the log)
#' @noRd
fake_model_record = function(name, type, api, log) {
  id = paste0(name, if (identical(type, "chat")) "-1" else "-s1")
  list(
    ref = paste0(name, "/", id), provider = name, id = id, name = paste("Fake", id),
    family = name, api = api, type = type, release_date = NA_character_, context = 200000,
    max_output = 8192, reasoning = TRUE,
    thinking_levels = c("off", "minimal", "low", "medium", "high"), thinking = NULL,
    input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
    prices = data.frame(
      from = as.Date("2026-01-01"), tier = "default", input = 0, output = 0, cache_read = 0,
      cache_write_5m = 0, cache_write_1h = 0
    ),
    cache_min = NA_real_,
    capabilities = list(
      mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
      operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE
    ),
    aliases = character(), status = "active", local = TRUE, fake = log
  )
}

#' The script and request log of a fake model: `model$fake`, else `opts$provider$log`, else the
#' most recent live fake provider of that name in this process
#' @noRd
fake_engine = function(model, opts = list()) {
  if (is.environment(model$fake)) return(model$fake)
  provider = opts$provider
  if (inherits(provider, "gptr_provider") && is.environment(provider$log)) return(provider$log)
  ref = the$fakes[[model$provider %||% ""]]
  engine = if (is.null(ref)) NULL else rlang::wref_key(ref)
  if (is.environment(engine)) engine else NULL
}

#' The request object a chat script function receives (contract section 12.1)
#' @noRd
fake_request = function(n, model, context) {
  messages = context$messages %||% list()
  last_user = ""
  for (msg in rev(messages)) {
    if (identical(msg$role, "user")) {
      last_user = msg_text(msg)
      break
    }
  }
  k = length(messages)
  results = list()
  while (k >= 1L && identical(messages[[k]]$role, "tool_result")) {
    results = c(list(messages[[k]]), results)
    k = k - 1L
  }
  list(
    n = n, model = model$ref %||% model$id %||% "fake",
    system = context$system %||% list(t0 = "", t1 = ""), tools = fake_tool_names(context),
    messages = messages, last_user = last_user, last_results = results,
    params = context$params %||% list()
  )
}

#' Names of the direct tools of a request context
#' @noRd
fake_tool_names = function(context) {
  tools = context[["tools"]]
  if (!length(tools) && !is.null(context[["tools_json"]])) {
    tools = tryCatch(json_decode(context$tools_json), error = function(e) list())
  }
  if (!length(tools)) return(character())
  vapply(tools, function(tool) as.character(tool$name %||% "")[1L], "")
}

#' Usage record with zeros for everything but input and output tokens
#' @noRd
fake_usage = function(input, output) {
  list(
    input = input, output = output, cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
    reasoning = 0, images = 0, total = input + output,
    cost = list(input = 0, output = 0, cache_read = 0, cache_write = 0, total = 0),
    estimated = FALSE
  )
}

#' Split text into deltas of `chunk` characters
#' @noRd
fake_chunks = function(text, chunk) {
  n = nchar(text)
  if (!n) return(character())
  starts = seq.int(1L, n, by = chunk)
  substring(text, starts, pmin(starts + chunk - 1L, n))
}

#' Reply `n` of a script (the last one repeats), or what a script function returns for `args`;
#' a failing or empty script is an error reply labelled `label`
#' @noRd
fake_script_reply = function(script, n, args, label) {
  if (is.function(script)) {
    return(tryCatch(do.call(script, args), error = function(e) {
      list(error = paste(label, "script failed:", conditionMessage(e)), status = 500L)
    }))
  }
  if (!length(script)) return(list(error = paste0(label, ": the script is empty"), status = 500L))
  script[[min(n, length(script))]]
}

#' Pick the reply of request `n` from the script
#' @noRd
fake_pick = function(script, request) {
  reply = fake_script_reply(script, request$n, list(request), "fake provider")
  if (is.character(reply) && length(reply) == 1L) reply = list(text = reply)
  if (!is.list(reply)) {
    reply = list(error = "fake provider: a reply must be a string or a list", status = 500L)
  }
  if (!is.null(reply$json)) reply$text = json_encode(reply$json)
  reply
}

#' The failure class suffix of an HTTP status: auth, rate_limit, overloaded, else `other`
#' @noRd
fake_status_class = function(status, other) {
  if (is.null(status) || is.na(status)) return(other)
  if (status %in% c(401L, 403L)) return("auth")
  if (status == 429L) return("rate_limit")
  if (status >= 500L) return("overloaded")
  other
}

#' Plan the event steps of one reply: list(steps = list of list(events, wait), hang, request_id)
#' @noRd
fake_plan = function(reply, request, model, context, engine) {
  n = request$n
  request_id = context$request_id %||% id_new("q", 12L)
  api = model$api %||% "fake"
  provider = model$provider %||% engine$name
  model_id = model$id %||% paste0(engine$name, "-1")
  chunk = as.integer(reply$chunk %||% 16L)
  gap = as.numeric(reply$gap %||% 0)
  steps = list()
  current = list()
  flush = function(wait) {
    steps[[length(steps) + 1L]] <<- list(events = current, wait = wait)
    current <<- list()
  }
  emit = function(ev, delta = FALSE) {
    current[[length(current) + 1L]] <<- ev
    if (delta && gap > 0) flush(gap)
  }
  if (!is.null(reply$delay) && reply$delay > 0) flush(as.numeric(reply$delay))
  emit(ev_new(
    "start", api = api, provider = provider, model = model_id, request_id = request_id,
    response_id = paste0("fake-", n)
  ))
  if (isTRUE(reply$hang)) {
    flush(0)
    return(list(steps = steps, hang = TRUE, request_id = request_id))
  }
  content = list()
  index = 0L
  add_text_deltas = function(type, text) {
    for (delta in fake_chunks(text, chunk)) emit(ev_new(type, index = index, delta = delta), TRUE)
  }
  if (!is.null(reply$error) || isTRUE(reply$overflow)) {
    after = as.integer(reply$after %||% 0L)
    if (after > 0L) {
      index = 1L
      emit(ev_new("text_start", index = index))
      pieces = if (!is.null(reply$text)) fake_chunks(reply$text, chunk) else character()
      pieces = c(pieces, paste0("partial ", seq_len(max(0L, after - length(pieces))), " "))
      partial = pieces[seq_len(after)]
      for (delta in partial) emit(ev_new("text_delta", index = index, delta = delta), TRUE)
      content = list(block_text(paste(partial, collapse = "")))
    }
    if (isTRUE(reply$overflow)) {
      window = model$context %||% 200000
      message = paste0(
        "prompt is too long: ", format(window + 1000, scientific = FALSE), " tokens > ",
        format(window, scientific = FALSE), " maximum"
      )
      status = 400L
      class = "context_overflow"
    } else {
      message = as.character(reply$error)[1L]
      status = as.integer(reply$status %||% 500L)
      class = fake_status_class(status, "provider")
    }
    msg = msg_assistant(
      content, api = api, provider = provider, model = model_id, stop_reason = "error",
      error_message = message, response_id = paste0("fake-", n), request_id = request_id
    )
    emit(ev_new(
      "error", reason = "error", message = msg,
      error = list(
        class = class, status = status, request_id = request_id, retry_after = reply$retry_after
      )
    ))
    flush(0)
    return(list(steps = steps, hang = FALSE, request_id = request_id))
  }
  if (!is.null(reply$thinking)) {
    index = index + 1L
    emit(ev_new("thinking_start", index = index))
    add_text_deltas("thinking_delta", reply$thinking)
    block = block_thinking(reply$thinking, signature = reply$signature)
    emit(ev_new("thinking_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  if (!is.null(reply$text)) {
    index = index + 1L
    emit(ev_new("text_start", index = index))
    add_text_deltas("text_delta", reply$text)
    block = block_text(reply$text)
    emit(ev_new("text_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  calls = if (!is.null(reply[["tool"]])) {
    list(list(name = reply[["tool"]], input = reply[["input"]], id = reply[["id"]]))
  } else {
    reply[["tools"]] %||% list()
  }
  truncated = identical(reply$stop, "length")
  for (k in seq_along(calls)) {
    call = calls[[k]]
    index = index + 1L
    id = call$id %||% paste0("fake_", n, "_", k)
    input = call$input
    if (is.null(input) || !length(input)) input = json_obj()
    json = json_encode(input)
    cut = ceiling(nchar(json) / 2)
    deltas = c(substr(json, 1L, cut), substr(json, cut + 1L, nchar(json)))
    if (truncated) deltas = deltas[1L]
    emit(ev_new("toolcall_start", index = index, id = id, name = call$name))
    scanner = partial_json()
    for (delta in deltas) {
      scanner$push(delta)
      emit(ev_new("toolcall_delta", index = index, delta = delta, preview = scanner$value()), TRUE)
    }
    raw = paste(deltas, collapse = "")
    arguments = if (truncated) scanner$value() %||% json_obj() else input
    block = block_tool_call(id, call$name, arguments, raw_arguments = raw)
    emit(ev_new("toolcall_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  stop_reason = reply$stop %||% (if (length(calls)) "tool_use" else "stop")
  call_json = vapply(calls, function(x) json_encode(x$input %||% json_obj()), "")
  usage = reply$usage %||% fake_usage(
    est_tokens(c(request$system$t0, request$system$t1, vapply(request$messages, msg_text, ""))),
    est_tokens(c(reply$thinking, reply$text, call_json))
  )
  msg = msg_assistant(
    content, api = api, provider = provider, model = model_id, usage = usage,
    stop_reason = stop_reason, response_id = paste0("fake-", n), request_id = request_id
  )
  emit(ev_new("done", reason = stop_reason, message = msg, usage = usage))
  flush(0)
  list(steps = steps, hang = FALSE, request_id = request_id)
}

#' The `inprocess` stream of the fake adapter (contract 8.1): a generator of `list(events, wait)`
#' `opts$signal$aborted` is checked before every step and ends the stream with an "aborted" error.
#' @noRd
fake_stream = function(model, context, opts) {
  state = new.env(parent = emptyenv())
  state$engine = fake_engine(model, opts)
  state$plan = NULL
  state$step = 0L
  state$started = FALSE
  state$done = FALSE
  state$acc = acc_new()
  state$request_id = context$request_id %||% id_new("q", 12L)
  function() {
    if (state$done) return(NULL)
    if (isTRUE(opts$signal$aborted)) {
      state$done = TRUE
      return(list(events = fake_abort_events(state, model, opts), wait = 0))
    }
    if (is.null(state$plan)) {
      engine = state$engine
      if (is.null(engine)) {
        state$done = TRUE
        return(list(events = fake_missing_events(model, state$request_id), wait = 0))
      }
      engine$n = engine$n + 1L
      request = fake_request(engine$n, model, context)
      engine$requests[[engine$n]] = request
      reply = fake_pick(engine$script, request)
      context$request_id = state$request_id
      state$plan = fake_plan(reply, request, model, context, engine)
    }
    steps = state$plan$steps
    if (state$step < length(steps)) {
      state$step = state$step + 1L
      step = steps[[state$step]]
      for (ev in step$events) {
        if (identical(ev$type, "start")) state$started = TRUE
        state$acc$push(ev)
      }
      if (state$step == length(steps) && !isTRUE(state$plan$hang)) state$done = TRUE
      return(step)
    }
    list(events = list(), wait = 0.05)
  }
}

#' Events that end an aborted fake stream
#' @noRd
fake_abort_events = function(state, model, opts) {
  events = list()
  if (!state$started) {
    start = ev_new(
      "start", api = model$api %||% "fake", provider = model$provider %||% "fake",
      model = model$id %||% "fake", request_id = state$request_id, response_id = NULL
    )
    state$acc$push(start)
    events = list(start)
  }
  partial = state$acc$message(stop_reason = "aborted")
  partial$error_message = opts$signal$reason %||% "aborted"
  error = list(class = "aborted", status = NULL, request_id = state$request_id, retry_after = NULL)
  c(events, list(ev_new("error", reason = "aborted", message = partial, error = error)))
}

#' Events of a fake model whose script cannot be found (or of a classifier used for chat)
#' @noRd
fake_missing_events = function(model, request_id,
                               message = "no script found for this model") {
  api = model$api %||% "fake"
  provider = model$provider %||% "fake"
  model_id = model$id %||% "fake"
  text = paste0("fake provider '", provider, "': ", message)
  list(
    ev_new("start", api = api, provider = provider, model = model_id, request_id = request_id,
           response_id = NULL),
    ev_new(
      "error", reason = "error",
      message = msg_assistant(list(), api = api, provider = provider, model = model_id,
                              stop_reason = "error", error_message = text,
                              request_id = request_id),
      error = list(class = "provider", status = 500L, request_id = request_id, retry_after = NULL)
    )
  )
}

#' The `stream` of the fake classifier adapter: a classifier answers System 1 questions only
#' @noRd
fake_classifier_stream = function(model, context, opts) {
  done = FALSE
  function() {
    if (done) return(NULL)
    done <<- TRUE
    request_id = context$request_id %||% id_new("q", 12L)
    list(
      events = fake_missing_events(model, request_id, "a classifier answers System 1 only"),
      wait = 0
    )
  }
}

#' The classifier fake (contract 8.1 `classify$run`, 12.1): canonical IC-74 answers or an
#' unsignalled `gptr_error_s1_*` condition; synthetic probabilities report `calibrated = NA`.
#' @noRd
fake_classify = function(model, state, questions, opts) {
  engine = fake_engine(model, opts)
  if (is.null(engine)) {
    return(fake_s1_error("fake classifier: no script found for this model", 500L, model))
  }
  answers = list()
  for (id in names(questions)) {
    question = questions[[id]]
    question$id = id
    engine$n = engine$n + 1L
    engine$requests[[engine$n]] = list(n = engine$n, state = state, question = question)
    answer = fake_script_reply(engine$script, engine$n, list(state, question), "fake classifier")
    if (is.list(answer) && !is.null(answer$error)) {
      return(fake_s1_error(answer$error, answer$status %||% 500L, model))
    }
    canonical = fake_answer(question, answer, model)
    if (inherits(canonical, "condition")) return(canonical)
    answers[[id]] = canonical
  }
  list(
    answers = answers,
    usage = list(
      input = est_tokens(json_encode(list(state = state, questions = questions)), "json"),
      output = 10 * length(questions)
    ),
    model_version = paste0(engine$name, "-s1-1.0"),
    engine = "fake",
    calibrated = NA,
    provider = model$provider,
    api = model$api,
    locality = "local",
    model_digest = model$digest,
    server_version = NULL,
    calibration_provenance = NULL
  )
}

#' One validated canonical IC-74 answer; never a provider-specific wire record
#' @noRd
fake_answer = function(question, answer, model = list()) {
  bad = function(message) {
    fake_s1_error(paste0("fake classifier: ", message), 200L, model, class = "s1_response")
  }
  type = question$type
  if (!is.numeric(answer) || !length(answer) || any(!is.finite(answer)) ||
      any(answer < 0 | answer > 1)) {
    return(bad("answers must contain finite numeric probabilities between zero and one"))
  }
  if (identical(type, "noul")) {
    if (length(answer) != 1L) return(bad("a noul answer requires one probability"))
    return(list(type = "noul", prob = unname(as.numeric(answer))))
  }
  labels = if (identical(type, "choice")) {
    names(question$criteria)
  } else {
    as.character(seq_along(question$criteria) - 1L)
  }
  if (length(answer) != length(labels) || abs(sum(answer) - 1) > 1e-8) {
    return(bad("probabilities must cover all options and sum to one"))
  }
  keys = names(answer)
  if (!is.null(keys) || identical(type, "choice")) {
    if (is.null(keys) || anyNA(keys) || anyDuplicated(keys) || !setequal(keys, labels)) {
      return(bad("probability names must match the requested options exactly"))
    }
    answer = answer[match(labels, keys)]
  }
  probs = stats::setNames(as.numeric(answer), labels)
  if (identical(type, "choice")) {
    return(list(type = "choice", choice = labels[[which.max(probs)]],
                probabilities = probs, confidence = max(probs)))
  }
  list(
    type = "score", score = sum((seq_along(probs) - 1) * probs), probabilities = probs,
    confidence = max(probs),
    legend = stats::setNames(as.character(unlist(question$criteria, use.names = FALSE)), labels)
  )
}

#' An unsignalled System 1 error condition classified by HTTP status
#' @noRd
fake_s1_error = function(message, status, model, class = NULL) {
  status = as.integer(status)
  other = if (status %in% c(400L, 422L)) "validation" else "response"
  class = class %||% paste0("s1_", fake_status_class(status, other))
  gptr_condition(message, c(class, "s1"), "error", list(
    status = status, error_type = class, request_id = NULL, model = model$id %||% NA_character_
  ))
}

#' The `builtin:fake` factory (IC-08): registers the `fake` and `fake-classifier` adapters
#' @noRd
builtin_fake = function(gptr) {
  gptr$register_adapter(
    "fake", api = "fake", transport = "inprocess", stream = fake_stream,
    capabilities = list(
      images_in_results = TRUE, tool_addition = TRUE, structured_output = TRUE,
      reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
      operator_role = "user", cache = "none", tool_shape = "anthropic"
    )
  )
  gptr$register_adapter(
    "fake-classifier", api = "fake-classifier", transport = "inprocess",
    stream = fake_classifier_stream, classify = list(run = fake_classify)
  )
  invisible(NULL)
}
