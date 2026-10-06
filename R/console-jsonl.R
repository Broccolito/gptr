# console-jsonl.R -- the `jsonl` built-in (P14, layer L5, area console; architecture 6.17,
# contract 7.14, 10.3): one redacted JSON object per line for every catalogued event, in the JSON
# form of contract 4.5. Worker children (P19, contract 11.11) and agentic layers in other
# languages read it. The sink writes to a connection its caller owns and opens none (IC-59).
# Rendering never reaches the sink, so the transcript does not depend on the verbosity (INFRA-27).

#' Stream events as JSON lines to `con`
#'
#' @param session A `gptr_session` (its events only, through session hooks that P02 drops at its
#'   `session_shutdown`), or `NULL` for the events of every session.
#' @param con An open connection owned by the caller (`stdout()`, or a file opened with
#'   `open = "wb"`).
#' @return A function that detaches the sink, invisibly.
#' @noRd
jsonl_sink = function(session, con) {
  check_class(session, "gptr_session", "session", null = TRUE)
  if (!inherits(con, "connection") || !isOpen(con)) {
    gptr_abort("`con` must be an open connection.", "invalid_argument", arg = "con",
               expected = "an open connection")
  }
  sid = if (is.null(session)) NULL else session_data(session)$id
  # a write error must not fail the run: fail-closed events would deny
  handler = function(event, ctx) {
    tryCatch(jsonl_write(con, event), error = function(e) NULL)
    NULL
  }
  ids = vapply(ev_catalogue()$event, function(ev) {
    if (is.null(sid)) {
      hook_add(ev, handler)
    } else {
      hook_add(ev, handler, rank = 0L, source = "session", session = sid)
    }
  }, "")
  invisible(function() {
    for (id in ids) hook_remove(id)
    invisible(NULL)
  })
}

#' Write one event as one line of UTF-8 bytes, flushed so a reading parent sees it at once
#' @noRd
jsonl_write = function(con, event) {
  writeLines(as_utf8(jsonl_line(event)), con, useBytes = TRUE)
  flush(con)
}

#' One event as JSON text with the `persist` profile applied to the tree, then to the text (on
#' top of the `stream` profile of ev_dispatch(), contract 1.4)
#' @noRd
jsonl_line = function(event) {
  redact(json_encode(redact(jsonl_event(event))))
}

#' The contract 4.5 JSON form of an event: `ts` as ISO 8601 UTC; the messages of `message_end`
#' and `turn_end` and the blocks of `tool_result` in their 4.1-4.2 JSON shapes
#' @noRd
jsonl_event = function(event) {
  out = jsonl_value(event)
  out$ts = iso_time(event$ts)
  if (!is.null(event$message)) out$message = msg_to_json(event$message)
  if (length(event$results)) out$results = lapply(event$results, msg_to_json)
  if (length(event$content)) out$content = lapply(event$content, block_to_json)
  out
}

#' A JSON-able copy of a payload value: lists, data frames (their atomic columns) and atomic
#' vectors are kept, with times as ISO strings and dates and factors as strings; functions,
#' environments, language and other live objects are dropped
#' @noRd
jsonl_value = function(x) {
  if (inherits(x, "POSIXt")) return(iso_time(as.numeric(x)))
  if (inherits(x, "Date") || is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) {
    return(as.data.frame(lapply(Filter(is.atomic, x), jsonl_value), optional = TRUE))
  }
  if (is.list(x)) {
    out = Filter(Negate(is.null), lapply(unclass(x), jsonl_value))
    return(if (!is.null(names(x)) && !length(out)) json_obj() else out)
  }
  if (is.atomic(x)) as.vector(unclass(x))
}

#' run() of the `jsonl` frontend; nothing but JSON lines is printed (gptr.verbose is 0)
#'
#' Without `.stdin`: the events of `session` (queued or running) until it settles. With
#' `peter(.stdin = TRUE, .opts = list(frontend = "jsonl"))`: each input line is a prompt (plain
#' text or `{"type":"prompt","text":...}`; `/exit` ends) sent like a console prompt; the events of
#' every session are written, and a failed prompt gives an `error` line.
#' @noRd
jsonl_frontend_run = function(session, ..., call = NULL, con = stdout()) {
  old = options(gptr.verbose = 0L)
  on.exit(options(old), add = TRUE)
  if (!isTRUE(call$args$stdin)) {
    if (!inherits(session, "gptr_session")) {
      gptr_abort(c("The jsonl frontend streams a session or reads prompts from standard input:",
                   "s |> peter(.opts = list(frontend = \"jsonl\")) at a console, or",
                   "peter(.stdin = TRUE, .opts = list(frontend = \"jsonl\")) from a script."),
                 "invalid_argument", arg = "session", expected = "a gptr_session")
    }
    off = jsonl_sink(session, con)
    on.exit(off(), add = TRUE)
    gptr_wait(session)
    return(invisible(session))
  }
  rs = repl_state(session, call$envir, stdin = TRUE, call = call)
  rs$reader = console_reader(stdin = TRUE, echo = FALSE)
  on.exit(repl_close(rs), add = TRUE)
  off = jsonl_sink(NULL, con)
  on.exit(off(), add = TRUE)
  repeat {
    line = trimws(rs$reader$read())
    if (is.na(line)) break
    x = if (startsWith(line, "{")) tryCatch(json_decode(line), error = function(e) NULL)
    text = if (rlang::is_string(x$text)) trimws(x$text) else line
    if (!nzchar(text)) next
    if (text %in% c("/exit", "/quit")) break
    res = console_send(rs, text)
    if (identical(res$status, "error")) {
      sid = if (is.null(rs$session)) NULL else session_data(rs$session)$id
      jsonl_write(con, ev_new("error", session = sid, reason = "error", error = list(
        class = class(res$error)[[1L]], message = conditionMessage(res$error))))
    }
  }
  invisible(rs$session)
}

#' builtin:jsonl (contract 7.14, 10.3): the `jsonl` frontend
#' @noRd
builtin_jsonl = function(gptr) {
  gptr$register(gptr_spec("frontend", "jsonl", run = jsonl_frontend_run))
  invisible(NULL)
}

on_load(ext_declare_builtin("jsonl", builtin_jsonl))
