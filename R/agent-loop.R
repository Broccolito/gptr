# agent-loop.R -- the pure agent-loop state machine (P06, layer L2).
# Pi's two nested loops (report 02 section 2.2) as a state machine the run engine drives from
# reactor callbacks: loop_next() gives the next action, loop_response()/loop_results() report it.
# gptr adds `max_turns` and finish_turn() decisions that end the run (report 02 section 4.11).

queue_user_sources = c("pipe", "pause_menu", "repl", "api_user")
queue_sources = c(queue_user_sources, "extension", "agent")

#' Create a loop state machine (class `gptr_loop`)
#' `steering`/`follow_up` return at most one queued message each (Pi's one-at-a-time delivery);
#' `finish_turn(turn)` returns NULL or `list(action = "end", reason)`.
#' @noRd
loop_new = function(max_turns = NULL, steering = function() list(), follow_up = function() list(),
                    finish_turn = function(turn) NULL, emit = function(type, ...) invisible(NULL)) {
  lp = new.env(parent = emptyenv())
  lp$advancing = FALSE
  lp$state = "begin"
  lp$turn = 0L
  lp$first = TRUE
  lp$has_more = TRUE
  lp$pending = list()
  lp$message = NULL
  lp$calls = list()
  lp$results = list()
  lp$reason = NULL
  lp$max_turns = if (is.null(max_turns)) NULL else as.integer(max_turns)
  lp$steering = steering
  lp$follow_up = follow_up
  lp$finish_turn = finish_turn
  lp$emit = emit
  class(lp) = "gptr_loop"
  lp
}

#' The next action of the loop
#' @return `list(action = "request", messages)`, `"tools"` (`calls, message, truncated`), `"end"`
#'   (`reason`) or `"wait"` while a response or a tool batch is outstanding.
#' @noRd
loop_next = function(lp) {
  if (isTRUE(lp$advancing)) return(list(action = "wait"))
  lp$advancing = TRUE
  on.exit({
    lp$advancing = FALSE
  }, add = TRUE)
  repeat {
    st = lp$state
    if (identical(st, "begin")) {
      if (loop_at_limit(lp)) return(loop_end(lp, "max_turns"))
      lp$pending = lp$steering()
      if (identical(lp$state, "done")) next
      lp$has_more = TRUE
      lp$state = "inner"
    } else if (identical(st, "inner")) {
      lp$state = if (lp$has_more || length(lp$pending) > 0L) "turn" else "outer"
    } else if (identical(st, "turn")) {
      if (loop_at_limit(lp)) return(loop_end(lp, "max_turns"))
      if (!lp$first) {
        if (!length(lp$pending)) lp$pending = lp$steering()
        if (identical(lp$state, "done")) next
        lp$emit("turn_start")
        if (identical(lp$state, "done")) next
      }
      lp$first = FALSE
      msgs = lp$pending
      lp$pending = list()
      lp$turn = lp$turn + 1L
      lp$state = "await_response"
      return(list(action = "request", messages = msgs))
    } else if (identical(st, "tools")) {
      lp$state = "await_tools"
      stop_reason = lp$message$stop_reason %||% "stop"
      return(list(action = "tools", calls = lp$calls, message = lp$message,
                  truncated = stop_reason %in% c("length", "refusal")))
    } else if (identical(st, "failed")) {
      lp$finish_turn(list(message = lp$message, results = list(), turn = lp$turn))
      lp$emit("turn_end", message = lp$message, results = list())
      return(loop_end(lp, lp$message$stop_reason %||% "error"))
    } else if (identical(st, "after_turn")) {
      decision = lp$finish_turn(list(message = lp$message, results = lp$results, turn = lp$turn))
      lp$emit("turn_end", message = lp$message, results = lp$results)
      if (identical(lp$state, "done")) next
      if (is.list(decision) && identical(decision$action, "end")) {
        return(loop_end(lp, decision$reason %||% "stop"))
      }
      # never dequeue input a capped run cannot send; it stays queued for the next run
      if (loop_at_limit(lp)) {
        return(loop_end(lp, if (lp$has_more) "max_turns" else "stop"))
      }
      lp$pending = lp$steering()
      if (identical(lp$state, "done")) next
      lp$state = "inner"
    } else if (identical(st, "outer")) {
      fu = lp$follow_up()
      if (identical(lp$state, "done")) next
      if (!length(fu)) return(loop_end(lp, "stop"))
      lp$pending = fu
      lp$has_more = TRUE
      lp$state = "inner"
    } else if (identical(st, "done")) {
      return(list(action = "end", reason = lp$reason))
    } else {
      return(list(action = "wait"))
    }
  }
}

#' Record the assistant message of the current request
#' @noRd
loop_response = function(lp, message) {
  if (identical(lp$state, "done")) return(invisible(lp))
  loop_expect_state(lp, "await_response")
  lp$message = message
  lp$results = list()
  lp$calls = list()
  if (msg_failed(message)) {
    lp$state = "failed"
    return(invisible(lp))
  }
  lp$calls = msg_calls(message)
  lp$has_more = FALSE
  lp$state = if (length(lp$calls)) "tools" else "after_turn"
  invisible(lp)
}

#' Record the tool results of the current turn; `terminate = TRUE` ends the run after this batch
#' @noRd
loop_results = function(lp, results, terminate = FALSE) {
  if (identical(lp$state, "done")) return(invisible(lp))
  loop_expect_state(lp, "await_tools")
  lp$results = results
  lp$has_more = !isTRUE(terminate)
  lp$state = "after_turn"
  invisible(lp)
}

#' End the loop with a reason
#' @noRd
loop_end = function(lp, reason) {
  if (identical(lp$state, "done")) return(list(action = "end", reason = lp$reason))
  lp$state = "done"
  lp$reason = reason
  list(action = "end", reason = reason)
}

#' Whether another model request would exceed this run's cap
#' @noRd
loop_at_limit = function(lp) {
  !is.null(lp$max_turns) && lp$turn >= lp$max_turns
}

#' Reject a callback that does not belong to the current outstanding action
#' @noRd
loop_expect_state = function(lp, expected) {
  if (!identical(lp$state, expected)) {
    gptr_abort("Agent loop received an out-of-order callback.", "internal",
               detail = paste0("Expected ", expected, "; found ", lp$state))
  }
  invisible(NULL)
}

#' Turn one queue item into the message delivered to the model (IC-55)
#' A user-source steer is an operator relay once the run has made a request (`relay`); extension
#' notes and agent reports are user-role data. Items were checked by session_enqueue().
#' @noRd
queue_item_message = function(item, which, relay = FALSE) {
  text = item$text
  blocks = item$blocks %||% list()
  if (item$source %in% queue_user_sources) {
    if (identical(which, "steer") && isTRUE(relay)) {
      message = msg_operator("steer_relay",
                              paste0("The user sent this message while you were working: ", text),
                              origin_text = text)
      message$content = c(blocks, message$content)
      return(message)
    }
    return(msg_user(c(blocks, list(block_text(text))), source = which))
  }
  if (identical(item$source, "extension")) {
    note = paste0("Extension ", item$name %||% "plugin", " sent this note (not from the user): ",
                  text)
    return(msg_user(c(blocks, list(block_text(note))), source = "extension"))
  }
  content = if (length(blocks)) {
    blocks
  } else {
    list(block_context("agent_report", text, attrs = list(from = item$name %||% "agent")))
  }
  msg_user(content, source = "agent")
}

#' Did a message fail (`stop_reason` error or aborted)?
#' @noRd
msg_failed = function(m) isTRUE((m$stop_reason %||% "stop") %in% c("error", "aborted"))

#' The tool-call blocks of a message
#' @noRd
msg_calls = function(m) Filter(function(b) identical(b$type, "tool_call"), m$content %||% list())

#' Is a message a final answer: an assistant message that did not fail and calls no tool?
#' @noRd
msg_final = function(m) identical(m$role, "assistant") && !msg_failed(m) && !length(msg_calls(m))
