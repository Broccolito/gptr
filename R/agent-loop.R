# agent-loop.R -- the pure agent-loop state machine (P06, layer L2).
#
# Pi's two nested loops (packages/agent/src/agent-loop.ts:102-321 at 1b347794, restated in
# dev/research/02-pi-agent-loop-sessions.md section 2.2 and prototyped in section 5.1 as
# `run_agent_loop()`), rewritten as a state machine so that the run engine (agent-run.R) can drive
# it from reactor callbacks. The loop knows nothing about sessions, stores, providers or the
# reactor: the engine asks `loop_next()` for the next action, performs it and reports the outcome
# with `loop_response()` or `loop_results()`. gptr additions (report 02 section 4.11): a finite
# `max_turns` that caps the model requests of one run, and `finish_turn()` decisions that end the
# run (`blocked`, `aborted`, `budget`).

queue_user_sources = c("pipe", "pause_menu", "repl", "api_user")
queue_sources = c(queue_user_sources, "extension", "agent")

#' Create a loop state machine
#'
#' @param max_turns Integer or NULL: the most model requests this run may make.
#' @param steering,follow_up Functions of no argument returning a list of messages (at most one
#'   queue item each, one-at-a-time delivery as in Pi).
#' @param finish_turn Function of `list(message, results, turn)` returning `NULL` or
#'   `list(action = "end", reason = chr(1))`.
#' @param emit Function `(type, ...)` for the loop-owned events `turn_start` and `turn_end`.
#' @return An environment of class `gptr_loop`.
#' @noRd
loop_new = function(max_turns = NULL, steering = function() list(), follow_up = function() list(),
                    finish_turn = function(turn) NULL, emit = function(type, ...) invisible(NULL)) {
  max_turns = check_number(max_turns, "max_turns", min = 0, int = TRUE, null = TRUE)
  check_function(steering, "steering")
  check_function(follow_up, "follow_up")
  check_function(finish_turn, "finish_turn")
  check_function(emit, "emit")
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
#'
#' @return One of `list(action = "request", messages)` (the queued messages to append before the
#'   request), `list(action = "tools", calls, message, truncated)`, `list(action = "end", reason)`
#'   or `list(action = "wait")` while a response or a tool batch is outstanding.
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
      # Queue callbacks remove items. Never take input that the capped run cannot send.
      # A completed text turn is still a normal stop; queued input remains for the next run.
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
  if ((message$stop_reason %||% "stop") %in% c("error", "aborted")) {
    lp$state = "failed"
    return(invisible(lp))
  }
  lp$calls = Filter(function(b) identical(b$type, "tool_call"), message$content %||% list())
  lp$has_more = FALSE
  lp$state = if (length(lp$calls)) "tools" else "after_turn"
  invisible(lp)
}

#' Record the tool results of the current turn; `terminate = TRUE` ends the run after this batch
#' @noRd
loop_results = function(lp, results, terminate = FALSE) {
  if (identical(lp$state, "done")) return(invisible(lp))
  loop_expect_state(lp, "await_tools")
  check_list(results, "results")
  check_flag(terminate, "terminate")
  lp$results = results
  lp$has_more = !isTRUE(terminate)
  lp$state = "after_turn"
  invisible(lp)
}

#' End the loop with a reason
#' @noRd
loop_end = function(lp, reason) {
  if (identical(lp$state, "done")) return(list(action = "end", reason = lp$reason))
  check_string(reason, "reason")
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
#'
#' Steers from user sources become operator relays once the run has made a request (`relay =
#' TRUE`); before that, and for follow-ups, they are ordinary user messages. Extension notes and
#' agent reports are user-role data and never relays.
#' @param item A queue item `list(text, blocks, source, t)` (optionally `name` for extension and
#'   agent items).
#' @param which `"steer"` or `"follow_up"`.
#' @noRd
queue_item_message = function(item, which, relay = FALSE) {
  check_list(item, "item", named = TRUE)
  check_string(item$source, "source")
  check_choice(item$source, queue_sources, "source")
  which = check_choice(which, c("steer", "follow_up"), "which")
  check_flag(relay, "relay")
  text = item$text
  check_string(text, "text", empty = TRUE)
  blocks = item$blocks %||% list()
  check_list(blocks, "blocks")
  if (item$source %in% queue_user_sources) {
    if (identical(which, "steer") && isTRUE(relay)) {
      if (!all(vapply(blocks, function(b) is.list(b) && identical(b$type, "text"), TRUE))) {
        gptr_abort("Steering relays support text blocks only; send attachments as a follow-up.",
                   "invalid_argument", arg = "blocks", expected = "text blocks")
      }
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
