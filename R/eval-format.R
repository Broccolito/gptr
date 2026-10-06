# The model-facing text of an evaluation (P09; report 12 section 3.4, 04 section 7.9, IC-67):
# events, plot notices, object and state-change lines and a status line, cut head 40% / tail 60%
# by truncate_output(). Image tokens count against the budget, which halves once the session
# passes half the compaction threshold (G4 section 4.4.5).

#' Cleaned lines of captured text (ANSI/OSC removed, carriage returns collapsed)
#' @noRd
eval_clean_lines = function(text) {
  if (is.null(text) || !length(text)) return(character())
  lines = clean_terminal(paste(text, collapse = ""))
  if (length(lines) && !nzchar(lines[length(lines)])) lines = lines[-length(lines)]
  lines
}

#' Model-facing lines of one event
#' @noRd
eval_event_text = function(e) {
  type = e$type
  if (type %in% c("output", "message")) return(eval_clean_lines(e$text))
  if (identical(type, "warning")) {
    where = if (is.null(e$call)) "" else paste0(" in ", e$call)
    return(paste0("Warning", where, ": ", paste(eval_clean_lines(e$text), collapse = "\n")))
  }
  if (identical(type, "error")) {
    where = if (is.null(e$call)) "" else paste0(" in ", e$call)
    at = ""
    if (!is.null(e$line) && !is.na(e$line)) at = sprintf("  [expression at line %d]", e$line)
    head = paste0("Error", where, ": ", paste(eval_clean_lines(e$message), collapse = "\n"), at)
    tb = if (length(e$traceback)) c("Traceback (outermost first):", e$traceback) else NULL
    return(c(head, tb))
  }
  if (identical(type, "interrupt")) {
    return(sprintf("[interrupted by the user after %.1f s; side effects may have occurred]",
                   e$seconds %||% 0))
  }
  if (identical(type, "plot") && isTRUE(e$attached)) {
    return(sprintf("[plot %d attached]", e$index))
  }
  character()
}

#' Plot notices, state-change lines and the status line appended after the events
#' @noRd
eval_tail_lines = function(res) {
  out = character()
  plots = Filter(function(e) identical(e$type, "plot"), res$events)
  stored = vapply(plots, function(e) !isTRUE(e$attached) && !is.null(e$path), NA)
  if (any(stored)) {
    k = vapply(plots[stored], function(e) as.integer(e$index), 1L)
    out = c(out, if (length(k) == 1L) {
      sprintf("[plot %d not attached: peter$plot(%d)]", k, k)
    } else {
      sprintf("[plots %d-%d not attached: peter$plot(k)]", min(k), max(k))
    })
  }
  lost = vapply(plots, function(e) is.null(e$path), NA)
  if (any(lost)) out = c(out, sprintf("[%d plots not rendered]", sum(lost)))
  obj = res$changes$objects$lines %||% character()
  if (length(obj) > 12L) {
    obj = c(obj[1:12], sprintf("(+ %d more object changes)", length(obj) - 12L))
  }
  out = c(out, obj)
  ch = res$changes
  if (length(ch$wd)) {
    out = c(out, sprintf("[working directory changed: %s -> %s]", ch$wd[["from"]],
                         ch$wd[["to"]]))
  }
  if (length(ch$options)) {
    out = c(out, sprintf("[options changed: %s]", paste(ch$options, collapse = ", ")))
  }
  if (length(ch$envvars)) {
    out = c(out, sprintf("[environment variables changed: %s]",
                         paste(ch$envvars, collapse = ", ")))
  }
  if (length(ch$attached)) {
    out = c(out, sprintf("[attached: %s]", paste(ch$attached, collapse = ", ")))
  }
  if (!identical(res$status, "ok")) {
    out = c(out, if (res$status %in% c("blocked", "parse_error")) {
      sprintf("[status: %s; nothing was evaluated]", res$status)
    } else {
      sprintf("[status: %s; %d of %d top-level expressions completed; %.2fs]", res$status,
              res$n_done, res$n_total, res$elapsed)
    })
  }
  out
}

#' Is the running session's context above half of the compaction threshold?
#' Asks `compact.should` (P07) at twice the session's own last request (a child's rows, IC-66, are
#' skipped); FALSE without evidence, all-unknown counts included (IC-74, D-058).
#' @noRd
eval_pressure = function(s = eval_session()) {
  if (is.null(s) || !ext_service_has("compact.should")) return(FALSE)
  d = session_data(s)
  u = d$usage
  if (!is.data.frame(u) || !nrow(u)) return(FALSE)
  u = u[u$session %in% d$id, , drop = FALSE]
  if (!nrow(u)) return(FALSE)
  last = u[nrow(u), , drop = FALSE]
  counts = c(last$input, last$cache_read, last$cache_write_5m, last$cache_write_1h,
             last$output)
  if (all(is.na(counts))) return(FALSE)
  tokens = sum(counts, na.rm = TRUE)
  should = ext_service_get("compact.should")
  isTRUE(tryCatch(should(s, 2 * tokens, 0), error = function(e) FALSE))
}

#' The budget in force: halved above half the compaction threshold (at least 200 tokens)
#' @noRd
eval_budget = function(budget_tokens, pressure = eval_pressure()) {
  if (isTRUE(pressure)) max(200, budget_tokens %/% 2) else budget_tokens
}

#' Model text of an evaluation within the token budget (04 section 7.9)
#' `budget_tokens` covers text and images; returns list(text, images, truncated, out_id, spill).
#' @noRd
format_eval_result = function(res, budget_tokens) {
  check_class(res, "gptr_eval_result", "res")
  check_number(budget_tokens, "budget_tokens", min = 1)
  budget = eval_budget(budget_tokens)
  image_tokens = 0
  for (b in res$images) {
    image_tokens = image_tokens + est_image_tokens(b$width %||% 768L, b$height %||% 512L)
  }
  lines = c(unlist(lapply(res$events, eval_event_text)), eval_tail_lines(res))
  if (!length(lines)) lines = "[no output]"
  parts = strsplit(lines, "\n", fixed = TRUE)
  lines = unlist(lapply(parts, function(x) if (length(x)) x else ""))
  tr = truncate_output(lines, max(200, budget - image_tokens), class = "r_output")
  list(text = tr$text, images = res$images, truncated = isTRUE(tr$truncated),
       out_id = tr$out_id, spill = tr$spill)
}
