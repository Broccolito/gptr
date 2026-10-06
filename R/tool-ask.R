# tool-ask.R -- the `ask` tool (builtin:ask, P11): contract section 9.2's schema, its UI mapping
# through ctx$ui() and report 18 section 3.6's result texts. Without a person the `mode` policy
# gates it `ask_human`, so the run stops `blocked` (IC-68, NS-12) before execute is reached.

#' The ask tool's input schema, in contract section 9.2's key order
#' @noRd
ask_parameters = function() {
  list(type = "object", required = list("questions"),
       properties = list(questions = list(
         type = "array", maxItems = 4L,
         items = list(type = "object", required = list("id", "question"),
                      properties = list(
                        id = list(type = "string"),
                        question = list(type = "string"),
                        type = list(enum = list("single", "multi", "text")),
                        options = list(type = "array", maxItems = 9L,
                                       items = list(type = "string")),
                        default = list(type = "string"))))))
}

#' The type of a question: `single` when it has options, else `text`
#' @noRd
ask_type = function(q) q$type %||% (if (length(q$options)) "single" else "text")

#' Validate ask input beyond the schema (report 18 validate_ask_input()); NULL when valid
#' @noRd
ask_validate = function(input) {
  qs = input$questions
  if (!is.list(qs) || !length(qs)) return("`questions` must be a non-empty array")
  if (length(qs) > 4L) return("at most 4 questions per call")
  ids = vapply(qs, function(q) if (rlang::is_string(q$id)) q$id else "", "")
  if (any(!nzchar(ids)) || anyDuplicated(ids)) {
    return("every question needs a unique non-empty `id`")
  }
  for (q in qs) {
    type = ask_type(q)
    if (!rlang::is_string(type, c("single", "multi", "text"))) {
      return(paste0("question '", q$id, "' has an unknown type"))
    }
    n = length(q$options)
    if (type != "text" && n < 2L) return(paste0("question '", q$id, "' needs at least 2 options"))
    if (n > 9L) return(paste0("question '", q$id, "' has more than 9 options"))
  }
  NULL
}

#' The questions as ui$questions() takes them: id, question, type, options (chr), default
#' @noRd
ask_normalise = function(qs) {
  lapply(qs, function(q) {
    list(id = q$id, question = as.character(q$question %||% q$id), type = ask_type(q),
         options = as.character(unlist(q$options)),
         default = if (!is.null(q$default)) as.character(q$default))
  })
}

#' The result text for answers (report 18 section 3.6)
#' @noRd
ask_text_answers = function(qs, answers) {
  lines = vapply(qs, function(q) {
    a = answers[[q$id]]
    shown = if (is.null(a)) {
      "(no answer)"
    } else if (isTRUE(attr(a, "other"))) {
      paste0("(typed) ", a)
    } else {
      paste(a, collapse = ", ")
    }
    paste0("- ", q$id, ": ", shown)
  }, "")
  paste(c("The user answered:", lines), collapse = "\n")
}

#' Execute the ask tool; a failing dialog counts as cancelled
#' @noRd
ask_execute = function(input, ctx) {
  err = ask_validate(input)
  if (!is.null(err)) return(gptr_tool_result(paste0("Invalid ask call: ", err), is_error = TRUE))
  qs = ask_normalise(input$questions)
  if (!isTRUE(ctx$has_ui())) {
    # reached only with gptr.unsafe_no_permissions: end the batch rather than guess (NS-12)
    res = gptr_tool_result(paste0("No one can answer questions in this run, so the question was ",
                                  "not asked and the run stops. Questions: ",
                                  paste(vapply(qs, function(q) q$question, ""), collapse = " | ")),
                           is_error = TRUE)
    res$terminate = TRUE
    return(res)
  }
  res = tryCatch(ctx$ui()$questions(qs), error = function(e) NULL)
  if (!is.list(res)) res = list(cancelled = TRUE)
  answers = res$answers %||% json_obj()
  if (isTRUE(res$cancelled)) {
    return(gptr_tool_result(paste(
      "The user dismissed the questions without answering. Do not guess silently: either stop",
      "and summarise what you need, or proceed with clearly stated assumptions."),
      details = list(answers = answers, cancelled = TRUE)))
  }
  gptr_tool_result(ask_text_answers(qs, answers),
                   details = list(answers = answers, cancelled = FALSE))
}

#' Declared when a person can answer, and in manual mode without one (IC-68 wins over the
#' has_ui-only rule of contract section 7.11)
#' @noRd
ask_available = function(ctx) isTRUE(ctx$has_ui()) || identical(ctx$mode(), "manual")

#' builtin:ask -- the ask direct tool
#' @noRd
builtin_ask = function(gptr) {
  gptr$register(gptr_tool(
    "ask", paste0(
      "Ask the user one to four questions and wait for the answers, when a decision changes the ",
      "result and cannot be inferred. The user may always type their own answer. Not for ",
      "permission to run code: the harness asks for that itself."),
    parameters = ask_parameters(), execute = ask_execute, exposure = "direct",
    execution = "sequential",
    risk = function(input, ctx) list(level = 0L, categories = "interactive", paths = character()),
    snippet = "Ask the user one to four questions when a decision changes the result",
    available = ask_available, annotations = list(read_only = TRUE, requires_user = TRUE)))
  invisible(NULL)
}

on_load(ext_declare_builtin("ask", builtin_ask, after = "ui"))
