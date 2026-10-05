# Normalised provider events (INFRA-02; contract section 4.5; report 02 sections 2.4 and 4.4) and
# the linear-time accumulator that builds the assistant message from them. Streaming updates are
# delta-only: no event ever carries the cumulative partial message (rebuilding it per delta is
# quadratic in R).

#' A new event: list(type, session, run, agent, turn, ts, ...)
#' @noRd
ev_new = function(type, ...) {
  check_string(type, "type")
  ev = list(type = type, session = NULL, run = NULL, agent = "main", turn = NULL,
            ts = as.numeric(Sys.time()))
  fields = list(...)
  nms = names(fields)
  if (length(fields) && (is.null(nms) || !all(nzchar(nms)))) {
    arg_abort(fields, "...", "named event fields")
  }
  for (name in nms) ev[name] = list(fields[[name]])
  ev
}

#' An accumulator of INFRA-02 events: an environment with `push(ev)` and `message(stop_reason)`
#' Per-block buffers grow by doubling and join once (linear, INFRA-23); `message()` is the
#' terminal event's message after `done`/`error`, else the partial message.
#' @noRd
acc_new = function() {
  state = new.env(parent = emptyenv())
  state$meta = list()
  state$blocks = list()
  state$final = NULL

  new_buffer = function(kind, ev) {
    buffer = new.env(parent = emptyenv())
    buffer$kind = kind
    buffer$parts = vector("list", 16L)
    buffer$n = 0L
    buffer$id = ev$id
    buffer$name = ev$name
    buffer$block = NULL
    buffer
  }

  push = function(ev) {
    type = ev$type
    if (identical(type, "start")) {
      state$meta = list(
        api = ev$api, provider = ev$provider, model = ev$model,
        request_id = ev$request_id, response_id = ev$response_id
      )
    } else if (grepl("^(text|thinking|toolcall)_(start|delta|end)$", type)) {
      buffer = state$blocks[ev$index][[1L]]
      if (is.null(buffer) || endsWith(type, "_start")) {
        buffer = new_buffer(sub("_.*$", "", type), ev)
        state$blocks[[ev$index]] = buffer
      }
      if (endsWith(type, "_end")) buffer$block = ev$block
      if (endsWith(type, "_delta")) {
        # Take-out form: setting an element of a still-bound list copies it (quadratic, INFRA-23)
        parts = buffer$parts
        buffer$parts = NULL
        if (buffer$n == length(parts)) length(parts) = 2L * length(parts)
        buffer$n = buffer$n + 1L
        parts[[buffer$n]] = ev$delta
        buffer$parts = parts
      }
    } else if (type %in% c("done", "error")) {
      state$final = ev$message
    }
    invisible(NULL)
  }

  joined = function(buffer) {
    if (!buffer$n) return("")
    paste(unlist(buffer$parts[seq_len(buffer$n)], use.names = FALSE), collapse = "")
  }

  block_of = function(buffer) {
    if (!is.null(buffer$block)) return(buffer$block)
    text = joined(buffer)
    switch(buffer$kind,
      text = block_text(text),
      thinking = block_thinking(text),
      toolcall = {
        scanner = partial_json()
        scanner$push(text)
        block_tool_call(
          buffer$id %||% "unknown", buffer$name %||% "unknown", scanner$value() %||% json_obj(),
          raw_arguments = text
        )
      }
    )
  }

  message = function(stop_reason = "stop") {
    if (!is.null(state$final)) return(state$final)
    buffers = Filter(Negate(is.null), state$blocks)
    meta = state$meta
    msg_assistant(
      lapply(buffers, block_of),
      api = meta$api %||% "unknown", provider = meta$provider %||% "unknown",
      model = meta$model %||% "unknown", stop_reason = stop_reason,
      response_id = meta$response_id, request_id = meta$request_id
    )
  }

  acc = new.env(parent = emptyenv())
  acc$push = push
  acc$message = message
  class(acc) = "gptr_accumulator"
  acc
}
