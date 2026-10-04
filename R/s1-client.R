# System 1 client (contract 7.13, 8.1; IC-64, IC-68, IC-74): questions with the wire type `noul`,
# the typesafe-system-one adapter and answer parsing. Wire facts are those of report 04a, measured
# against the live API: the types are `noul`, `choice` and `score` ("bool" is rejected with HTTP
# 400), a score's criteria are a JSON array, choice probabilities do not come in request order,
# probabilities are rounded to two decimals, and errors are `detail.error_type`/`detail.message`.
# Adapted from report 04 section 5.2 (s1_client.R): httr2 was replaced by gptr's reactor (report
# 04 verification log item 14: req_perform_parallel() retries without bound) and "<-" became "=".
#
# IC-74 (07-local-ollama.md section 3): classify$parse(model, status, headers, body, questions)
# receives the ordered questions and normalises the wire answers exactly once into canonical
# records keyed by question id: `list(type = "noul", prob)`, `list(type = "choice", choice,
# probabilities, confidence)` and `list(type = "score", score, probabilities, confidence,
# legend)`, probabilities named in request order. Values are validated against the request
# (finite values, bounds, answer ids, option names, probability sums, score reconstruction); a
# score stays the fractional expected level. Unreported usage stays unknown (NA).

s1_max_choices = 255L
s1_max_levels = 10L
s1_types = c("noul", "choice", "score")
s1_logical_labels = c("TRUE", "true", "True", "T", "FALSE", "false", "False", "F")

# Half a unit of the two-decimal rounding of TypeSafe's probabilities (report 04a; report 04
# section 2.4): the slack of one rounded probability
s1_round_tol = 0.005

# ---- questions --------------------------------------------------------------------------------

#' The sentence naming the state fields, appended to the instructions (04a: instructions refer
#' to state fields by name in backticks; the question id is never seen by the model)
#' @noRd
s1_input_sentence = function(labels) {
  if (!length(labels)) return("")
  q = paste0("`", labels, "`")
  if (length(q) == 1L) return(paste0(" The input is in ", q, "."))
  paste0(" The inputs are in ", paste(q[-length(q)], collapse = ", "), " and ", q[length(q)], ".")
}

#' Build the wire question (id "answer") from the prompt and the answer shape
#'
#' Returns `list(id, type, wire, options, factor)`: `wire` is the question object of report 04a,
#' `options` the choice labels or level descriptions in request order, `factor` TRUE when
#' `choices` was a factor. `decision` is the resolved model's decision record (07-local-ollama.md
#' section 2): its `types` restrict the question type and its `max_options` caps choice options
#' and score levels in place of TypeSafe's documented 255 options and 10 levels (IC-74).
#' @noRd
s1_question = function(prompt, labels = character(), choices = NULL, levels = NULL,
                       decision = NULL) {
  check_string(prompt, "prompt")
  check_strings(labels, "labels")
  if (!is.null(decision) && !is.list(decision)) {
    arg_abort(decision, "decision", "a model's decision record (a list) or NULL")
  }
  if (!is.null(choices) && !is.null(levels)) {
    gptr_abort("Give either choices or levels, not both.", "invalid_argument", arg = "levels",
               expected = "NULL when choices is given")
  }
  type = if (!is.null(choices)) "choice" else if (!is.null(levels)) "score" else "noul"
  s1_question_supported(type, decision)
  instructions = paste0(prompt, s1_input_sentence(labels))
  if (!is.null(choices)) {
    return(s1_question_choice(instructions, choices,
                              decision[["max_options"]] %||% s1_max_choices))
  }
  if (!is.null(levels)) {
    return(s1_question_score(instructions, levels, decision[["max_options"]] %||% s1_max_levels))
  }
  list(id = "answer", type = "noul", wire = list(type = "noul", instructions = instructions),
       options = NULL, factor = FALSE)
}

#' Refuse a question type the model's decision record does not list
#' @noRd
s1_question_supported = function(type, decision) {
  types = decision[["types"]]
  if (is.null(types) || type %in% types) return(invisible(TRUE))
  gptr_abort(paste0("This System 1 model answers only ", paste(types, collapse = ", "),
                    " questions, not ", type, " questions."),
             "invalid_argument", arg = "model",
             expected = paste0("a model whose decision types include ", type))
}

#' A choice question: names are options with descriptions, else the values are the options
#' @noRd
s1_question_choice = function(instructions, choices, max_options) {
  is_factor = is.factor(choices)
  labels = if (is_factor) levels(choices) else choices
  if (!is.character(labels)) {
    gptr_abort("choices must be a character vector or a factor.", "invalid_argument",
               arg = "choices", expected = "a character vector or a factor")
  }
  nm = names(labels)
  described = !is_factor && !is.null(nm) && all(nzchar(nm)) && !anyNA(nm)
  opts = if (described) nm else unname(labels)
  if (length(opts) < 2L || length(opts) > max_options || anyNA(opts) || !all(nzchar(opts)) ||
        anyDuplicated(opts)) {
    gptr_abort(paste0("choices must hold 2 to ", max_options, " unique, non-empty labels."),
               "invalid_argument", arg = "choices",
               expected = paste0("2 to ", max_options, " unique labels"))
  }
  bad = opts[opts %in% s1_logical_labels]
  if (length(bad)) {
    gptr_abort(c(paste0("Choice labels that if() reads as TRUE or FALSE are not allowed: ",
                        paste(bad, collapse = ", "), "."),
                 "Use words such as \"yes\" and \"no\", or ask a yes/no question without choices."),
               c("s1_labels", "s1"), labels = bad)
  }
  criteria = vector("list", length(opts))
  names(criteria) = opts
  if (described) {
    for (k in seq_along(opts)) {
      d = labels[[k]]
      if (!is.na(d) && nzchar(d)) criteria[k] = list(d)
    }
  }
  list(id = "answer", type = "choice",
       wire = list(type = "choice", instructions = instructions, criteria = criteria),
       options = opts, factor = is_factor)
}

#' A score question: 2 to `max_levels` level descriptions, low to high (0-based levels on the
#' wire)
#' @noRd
s1_question_score = function(instructions, levels, max_levels) {
  lv = as.character(levels)
  if (length(lv) < 2L || length(lv) > max_levels || anyNA(lv)) {
    gptr_abort(paste0("levels must hold 2 to ", max_levels, " level descriptions, low to high."),
               "invalid_argument", arg = "levels",
               expected = paste0("2 to ", max_levels, " descriptions"))
  }
  list(id = "answer", type = "score",
       wire = list(type = "score", instructions = instructions, criteria = unname(as.list(lv))),
       options = lv, factor = FALSE)
}

# ---- conditions -------------------------------------------------------------------------------

#' An unsignalled System 1 condition: class `gptr_error_<sub>`, parent `gptr_error_s1`, fields
#' `status`, `error_type`, `request_id`, `model` and `retry_after` (contract 2.2; report 04
#' section 4.12)
#' @noRd
s1_condition = function(sub, message, status = NA_integer_, error_type = NA_character_,
                        request_id = NA_character_, model = NA_character_, retry_after = NULL) {
  gptr_condition(message, c(sub, "s1"), "error",
                 list(status = as.integer(status), error_type = as.character(error_type),
                      request_id = as.character(request_id), model = as.character(model),
                      retry_after = retry_after))
}

#' The System 1 condition class of an HTTP status (report 04 section 4.12; 400 from report 04a)
#' @noRd
s1_status_class = function(status) {
  if (!is.numeric(status) || length(status) != 1L || is.na(status)) return("s1_connection")
  if (status %in% c(401L, 403L)) return("s1_auth")
  if (status %in% c(400L, 404L, 409L, 413L, 422L)) return("s1_validation")
  if (status == 408L) return("s1_connection")
  if (status == 429L) return("s1_rate_limit")
  if (status >= 500L) return("s1_overloaded")
  "s1_response"
}

#' Is a failed element worth another round? (408, 429, 5xx and network failures)
#' @noRd
s1_retry_of = function(cnd) {
  inherits(cnd, "gptr_error_s1_connection") || inherits(cnd, "gptr_error_s1_rate_limit") ||
    inherits(cnd, "gptr_error_s1_overloaded")
}

#' A server-requested delay in seconds, capped at 60, or NULL
#' @noRd
s1_delay = function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x)) min(max(x, 0), 60) else NULL
}

#' A message or type field of an error body as one string, NULL when absent
#'
#' Strings are joined; any other JSON value is shown as compact JSON. The text is the service's
#' (untrusted): gptr_condition() pastes and redacts it, never interpolates it.
#' @noRd
s1_text = function(x) {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) && !anyNA(x)) return(paste(x, collapse = "; "))
  json_encode(x)
}

#' One element of a `{"detail": [...]}` body: `loc.path: msg` for FastAPI's 422 records
#' @noRd
s1_error_item = function(e) {
  if (!is.list(e) || is.null(names(e))) return(s1_text(e) %||% "invalid")
  msg = s1_text(e[["msg"]]) %||% "invalid"
  loc = unlist(e[["loc"]], use.names = FALSE)
  if (!length(loc)) return(msg)
  paste0(paste(loc, collapse = "."), ": ", msg)
}

#' An error body in any of the shapes of report 04 section 3.6 as a System 1 condition:
#' `{"detail": {"error_type", "message"}}`, `{"detail": [{"loc", "msg"}]}` (422),
#' `{"message", "error_type"}` (Vercel) and `{"error": {"message", "type"}}` (OpenAI-style)
#' @noRd
s1_http_error = function(status, obj, request_id, model_id, retry_after = NULL) {
  msg = NULL
  type = NULL
  d = if (is.list(obj)) obj[["detail"]] else NULL
  if (is.list(d) && !is.null(names(d))) {
    msg = s1_text(d[["message"]])
    type = s1_text(d[["error_type"]])
  } else if (is.list(d) && length(d)) {
    msg = paste(vapply(d, s1_error_item, ""), collapse = "; ")
    type = "validation_error"
  } else if (is.character(d)) {
    msg = s1_text(d)
  } else if (is.list(obj) && !is.null(obj[["message"]])) {
    msg = s1_text(obj[["message"]])
    type = s1_text(obj[["error_type"]])
  } else if (is.list(obj) && is.list(obj[["error"]])) {
    e = obj[["error"]]
    msg = s1_text(e[["message"]])
    type = s1_text(e[["type"]] %||% e[["code"]])
  }
  text = paste0("System 1 request failed with HTTP ", status,
                if (length(msg)) paste0(": ", msg) else "")
  s1_condition(s1_status_class(status), text, status, type %||% NA_character_, request_id,
               model_id, retry_after = retry_after)
}

# ---- the typesafe-system-one adapter ------------------------------------------------------------

#' The evaluation endpoint `POST {base}/systemone` (architecture 8.2; report 04a)
#' @noRd
s1_endpoint = function(base_url) paste0(sub("/+$", "", base_url), "/systemone")

#' The User-Agent header (report 04 section 3.1: gptr's own, nothing that imitates the SDK)
#' @noRd
s1_user_agent = function() paste0("gptr/", utils::packageVersion("gptr"))

#' A header value by case-insensitive name, NA when absent
#' @noRd
s1_header = function(headers, name) {
  if (!length(headers) || is.null(names(headers))) return(NA_character_)
  k = match(tolower(name), tolower(names(headers)))
  if (is.na(k)) NA_character_ else as.character(headers[[k]])[1L]
}

#' A finite number or NA
#' @noRd
s1_num = function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x)) as.double(x) else NA_real_
}

#' A finite number in [0, 1] (a probability or a confidence) or NA
#' @noRd
s1_unit = function(x) {
  p = s1_num(x)
  if (is.na(p) || p < 0 || p > 1) NA_real_ else p
}

#' A token count the service reported, NA unless it is a nonnegative finite number (IC-74: missing
#' usage remains unknown)
#' @noRd
s1_count = function(x) {
  n = s1_num(x)
  if (is.na(n) || n < 0) NA_real_ else n
}

#' The `usage` object of a response as `list(input, output)`, unknown counts NA
#' @noRd
s1_usage_of = function(u) {
  if (!is.list(u)) return(list(input = NA_real_, output = NA_real_))
  list(input = s1_count(u[["input_tokens"]]), output = s1_count(u[["output_tokens"]]))
}

#' classify$build of typesafe-system-one: the request spec (contract 8.1)
#'
#' The bearer header is `list("Bearer ", <handle>)`: P04's http-request.R joins the pieces and
#' materialises the handle only for the URL's own origin, so no key value exists here.
#' @noRd
s1_typesafe_build = function(model, state, questions, opts) {
  base_url = opts[["base_url"]]
  check_string(base_url, "base_url")
  headers = list(`Content-Type` = "application/json", Accept = "application/json",
                 `User-Agent` = s1_user_agent())
  credential = opts[["credential"]]
  if (!is.null(credential)) headers$Authorization = list("Bearer ", credential)
  list(url = s1_endpoint(base_url), method = "POST", headers = headers,
       body = json_encode(list(model = model[["id"]], state = state, questions = questions)),
       stream = "json")
}

#' classify$parse of typesafe-system-one: one whole JSON body (contract 8.1, IC-74)
#'
#' `questions` are the ordered wire questions of the request, by id. Returns
#' `list(answers, usage = list(input, output), model_version, request_id)` with canonical answers
#' (s1_parse_answers()), or an unsignalled `gptr_error_s1_*` condition: an error body by its
#' status, a malformed 200 body as `s1_response` carrying the status and request id.
#' @noRd
s1_typesafe_parse = function(model, status, headers, body, questions) {
  rid = s1_header(headers, "x-typesafe-request-id")
  model_id = model[["id"]] %||% NA_character_
  if (!is.numeric(status) || length(status) != 1L) status = NA_integer_
  obj = tryCatch(json_decode(body), error = function(e) NULL)
  if (is.na(status) || status < 200L || status > 299L) {
    return(s1_http_error(status, obj, rid, model_id))
  }
  answers = if (is.list(obj)) obj[["answers"]] else NULL
  if (!is.list(answers)) {
    return(s1_condition("s1_response", "System 1 returned a response without answers.", status,
                        NA_character_, rid, model_id))
  }
  parsed = s1_parse_answers(answers, questions, model_id)
  if (inherits(parsed, "condition")) {
    parsed$status = as.integer(status)
    parsed$request_id = rid
    return(parsed)
  }
  version = obj[["model"]]
  if (!is.character(version) || length(version) != 1L || is.na(version) || !nzchar(version)) {
    version = model_id
  }
  list(answers = parsed, usage = s1_usage_of(obj[["usage"]]), model_version = version,
       request_id = rid)
}

# ---- answers ----------------------------------------------------------------------------------

#' TypeSafe's choice confidence (n * peak - 1) / (n - 1), clamped to [0, 1] (report 04 2.4)
#' @noRd
s1_confidence_choice = function(p) {
  n = length(p)
  if (n <= 1L) return(1)
  tot = sum(p)
  q = if (tot == 0) rep(1 / n, n) else p / tot
  min(1, max(0, (n * max(q) - 1) / (n - 1)))
}

#' TypeSafe's score confidence 1 - E|level - mode| / MAD(uniform), floored at 0 (report 04 2.4)
#' @noRd
s1_confidence_score = function(p) {
  n = length(p)
  if (n <= 1L) return(1)
  tot = sum(p)
  q = if (tot == 0) rep(1 / n, n) else p / tot
  lv = seq_len(n) - 1
  mode = which.max(q) - 1
  max(0, 1 - sum(q * abs(lv - mode)) / mean(abs(lv - (n - 1) / 2)))
}

#' The option keys of a wire question in request order: choice names, or "0".."n-1" for score
#' levels; NULL when the question has no valid options
#' @noRd
s1_option_keys = function(question) {
  criteria = question[["criteria"]]
  if (!is.list(criteria) && !is.character(criteria)) return(NULL)
  if (identical(question[["type"]], "choice")) {
    keys = names(criteria)
    ok = length(keys) >= 2L && !anyNA(keys) && all(nzchar(keys)) && !anyDuplicated(keys)
    return(if (ok) keys else NULL)
  }
  if (length(criteria) < 2L) return(NULL)
  as.character(seq_along(criteria) - 1L)
}

#' The legend of a score question: its level descriptions named "0".."n-1" (07 section 3); a
#' description given as a JSON object or array is shown as compact JSON
#' @noRd
s1_legend = function(question, keys) {
  vals = vapply(question[["criteria"]], function(x) {
    if (is.character(x) && length(x) == 1L && !is.na(x)) x else json_encode(x)
  }, "")
  stats::setNames(unname(vals), keys)
}

#' A probability map re-keyed into request order
#'
#' Returns a named double vector, all NA when the map is absent or empty (a gateway that re-ran
#' the question elsewhere, report 04 section 2.9: unavailable, not zero), or a chr(1) problem
#' when the keys are not exactly the options asked, a value is not a probability, or the values
#' do not sum to 1 within the two-decimal rounding of every value.
#' @noRd
s1_answer_probs = function(got, keys) {
  p = stats::setNames(rep(NA_real_, length(keys)), keys)
  if (is.null(got) || (is.list(got) && !length(got))) return(p)
  nm = names(got)
  if (!is.list(got) || is.null(nm) || anyNA(nm) || anyDuplicated(nm)) {
    return("System 1 returned probabilities that are not keyed by option.")
  }
  if (!all(keys %in% nm)) return("System 1 returned incomplete probabilities.")
  if (!all(nm %in% keys)) return("System 1 returned probabilities for options that were not asked.")
  for (k in keys) p[[k]] = s1_unit(got[[k]])
  if (anyNA(p)) return("System 1 returned an invalid probability.")
  if (abs(sum(p) - 1) > s1_round_tol * length(p) + 1e-9) {
    return("System 1 returned probabilities that do not sum to 1.")
  }
  p
}

#' One wire answer as a canonical answer, probabilities re-keyed by option name (IC-74)
#'
#' Canonical answers are `list(type = "noul", prob)`, `list(type = "choice", choice,
#' probabilities, confidence)` or `list(type = "score", score, probabilities, confidence,
#' legend)`; `probabilities` is a named double vector in request order. The service's confidence
#' is kept and recomputed with TypeSafe's formulas only when it is absent (report 04
#' verification log item 5). An empty probability map is missing, not zero: probabilities and
#' confidence are NA. A missing choice is the most probable option (the first in request order
#' on a tie); a missing score is the expected level, kept fractional. Malformed or inconsistent
#' answers are unsignalled `gptr_error_s1_response` conditions, never values.
#' @noRd
s1_parse_answer = function(answer, question, model_id = NA_character_) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  type = if (is.list(question)) question[["type"]] else NULL
  if (!is.character(type) || length(type) != 1L || is.na(type) || !(type %in% s1_types)) {
    return(bad("System 1 was sent a question without a known type."))
  }
  if (!is.list(answer)) return(bad("System 1 returned no answer for the question."))
  got_type = answer[["type"]]
  if (!identical(got_type, type)) {
    shown = if (is.character(got_type) && length(got_type) == 1L) got_type else "missing"
    return(bad(paste0("System 1 returned a ", shown, " answer for a ", type, " question.")))
  }
  if (identical(type, "noul")) {
    p = s1_unit(answer[["noul"]])
    if (is.na(p)) return(bad("System 1 returned an invalid probability."))
    return(list(type = "noul", prob = p))
  }
  keys = s1_option_keys(question)
  if (is.null(keys)) return(bad("System 1 was sent a question without valid options."))
  p = s1_answer_probs(answer[["probabilities"]], keys)
  if (is.character(p)) return(bad(p))
  known = !anyNA(p)
  conf = NA_real_
  if (known) {
    given = answer[["confidence"]]
    if (is.null(given)) {
      conf = if (identical(type, "choice")) s1_confidence_choice(p) else s1_confidence_score(p)
    } else {
      conf = s1_unit(given)
      if (is.na(conf)) return(bad("System 1 returned an invalid confidence."))
    }
  }
  if (identical(type, "choice")) return(s1_parse_choice(answer[["choice"]], p, keys, conf, bad))
  s1_parse_score(answer[["score"]], p, keys, conf, s1_legend(question, keys), bad)
}

#' The choice of a choice answer, checked against the options and its own probabilities
#' @noRd
s1_parse_choice = function(ch, p, keys, conf, bad) {
  known = !anyNA(p)
  if (is.null(ch) && known) ch = keys[which.max(p)]
  if (!is.character(ch) || length(ch) != 1L || is.na(ch) || !(ch %in% keys)) {
    return(bad("System 1 returned an unknown choice."))
  }
  if (known && p[[ch]] < max(p) - 2 * s1_round_tol - 1e-9) {
    return(bad("System 1 returned a choice that its probabilities do not support."))
  }
  list(type = "choice", choice = ch, probabilities = p, confidence = conf)
}

#' The score of a score answer: within [0, levels - 1] and, when probabilities are known, their
#' expected level within the rounding of the probabilities; never rounded to a level
#' @noRd
s1_parse_score = function(given, p, keys, conf, legend, bad) {
  known = !anyNA(p)
  lv = seq_along(keys) - 1
  if (is.null(given)) {
    sc = if (known && sum(p) > 0) sum(lv * p / sum(p)) else NA_real_
  } else {
    sc = s1_num(given)
    if (!is.na(sc) && known && abs(sc - sum(lv * p)) > s1_round_tol * (sum(lv) + 1) + 1e-9) {
      return(bad("System 1 returned a score that its probabilities do not give."))
    }
  }
  if (is.na(sc) || sc < 0 || sc > max(lv)) return(bad("System 1 returned an invalid score."))
  list(type = "score", score = sc, probabilities = p, confidence = conf, legend = legend)
}

#' All answers of one response by question id, or the condition of the first problem
#'
#' Every question must be answered and nothing else (07 section 3: expected answer ids); the
#' result follows the order of `questions`.
#' @noRd
s1_parse_answers = function(answers, questions, model_id = NA_character_) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  ids = names(questions)
  got = names(answers)
  if (!is.list(answers) || (length(answers) && (is.null(got) || anyNA(got) ||
                                                  anyDuplicated(got)))) {
    return(bad("System 1 returned answers that are not keyed by question."))
  }
  extra = setdiff(got, ids)
  if (length(extra)) {
    return(bad(paste0("System 1 returned answers to questions that were not asked: ",
                      paste(extra, collapse = ", "), ".")))
  }
  out = vector("list", length(ids))
  names(out) = ids
  for (id in ids) {
    if (!(id %in% got)) {
      return(bad(paste0("System 1 returned no answer for the question ", id, ".")))
    }
    a = s1_parse_answer(answers[[id]], questions[[id]], model_id)
    if (inherits(a, "condition")) return(a)
    out[[id]] = a
  }
  out
}
