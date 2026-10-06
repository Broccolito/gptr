# System 1 client (contract 7.13, 8.1; IC-64, IC-68, IC-74): wire questions, the
# typesafe-system-one adapter and the bounded concurrent request driver. Wire facts are report
# 04a's: types `noul`, `choice` and `score`; score criteria are an array; choice probabilities come
# in any order, rounded to two decimals; errors are `detail.error_type`/`detail.message`.

s1_max_choices = 255L
s1_max_levels = 10L
s1_logical_labels = c("TRUE", "true", "True", "T", "FALSE", "false", "False", "F")

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
#' Returns `list(id, type, wire, options, factor)`. The model's `decision` record restricts the
#' types and caps options and levels in place of TypeSafe's 255 and 10 (IC-74, 07 section 2).
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

#' A score question: 2 to `max_levels` level descriptions, low to high (0-based on the wire)
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

#' An error body (any shape P04's retry_body_error() reads) as a System 1 condition
#' @noRd
s1_http_error = function(status, body, request_id, model_id) {
  e = retry_body_error(body)
  text = paste0("System 1 request failed with HTTP ", status,
                if (nzchar(e$message)) paste0(": ", e$message))
  s1_condition(s1_status_class(status), text, status, if (nzchar(e$type)) e$type else NA_character_,
               request_id, model_id)
}

#' A failed request as an outcome (contract 2.2): timeouts and network failures are connection
#' errors, a known status gives its class, anything else (an abort, a local failure) is a response
#' error; an abort and P04's final classes are never retried (IC-64)
#' @noRd
s1_failure = function(cls, status, text, request_id, model_id, retry_after = NULL) {
  cls = if (rlang::is_string(cls[1L])) sub("^gptr_error_", "", cls[1L]) else ""
  if (!is.numeric(status) || length(status) != 1L) status = NA_integer_
  sub = if (startsWith(cls, "timeout") || identical(cls, "network")) {
    "s1_connection"
  } else if (is.na(status) || identical(cls, "aborted")) {
    "s1_response"
  } else {
    s1_status_class(status)
  }
  err = s1_condition(sub, text, status, if (nzchar(cls)) cls else NA_character_,
                     as.character(request_id %||% NA_character_)[1L], model_id,
                     retry_after = retry_after)
  final = cls %in% c("aborted", "redirect", "spend_cap", "retry_after")
  list(ok = FALSE, error = err, retry = s1_retry_of(err) && !final, delay = s1_delay(retry_after))
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

#' A reported token count, NA unless it is a nonnegative finite number (IC-74)
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

#' classify$parse of the TypeSafe and Ollama decision APIs: one whole JSON body (contract 8.1)
#'
#' Returns `list(answers, usage, model_version, request_id)` with canonical answers, or an
#' unsignalled `gptr_error_s1_*` condition; Ollama must answer with the model asked (IC-74).
#' @noRd
s1_wire_parse = function(model, status, headers, body, questions, ollama = FALSE) {
  rid = s1_header(headers, if (ollama) "x-request-id" else "x-typesafe-request-id")
  model_id = model[["id"]] %||% NA_character_
  if (!is.numeric(status) || length(status) != 1L) status = NA_integer_
  if (is.na(status) || status < 200L || status > 299L) {
    return(s1_http_error(status, body, rid, model_id))
  }
  obj = tryCatch(json_decode(body), error = function(e) NULL)
  version = if (is.list(obj)) obj[["model"]] %||% model_id
  parsed = if (!is.list(obj) || !is.list(obj[["answers"]])) {
    s1_condition("s1_response", "System 1 returned a response without answers.", model = model_id)
  } else if (ollama && !(rlang::is_string(version) &&
                           identical(s1_ollama_tag(version), s1_ollama_tag(model_id)))) {
    s1_condition("s1_response", paste0("Ollama answered with another model than ", model_id,
                                       if (rlang::is_string(version)) paste0(": ", version), "."),
                 model = model_id)
  } else {
    s1_parse_answers(obj[["answers"]], questions, model_id, ollama)
  }
  if (inherits(parsed, "condition")) {
    parsed$status = as.integer(status)
    parsed$request_id = rid
    return(parsed)
  }
  if (!rlang::is_string(version) || !nzchar(version)) version = model_id
  list(answers = parsed, usage = s1_usage_of(obj[["usage"]]), model_version = version,
       request_id = rid)
}

#' classify$parse of typesafe-system-one
#' @noRd
s1_typesafe_parse = function(model, status, headers, body, questions) {
  s1_wire_parse(model, status, headers, body, questions)
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

#' The legend of a score question: its level descriptions named "0".."n-1" (07 section 3); a
#' description given as a JSON object or array is shown as compact JSON
#' @noRd
s1_legend = function(question, keys) {
  vals = vapply(question[["criteria"]], function(x) {
    if (rlang::is_string(x)) x else json_encode(x)
  }, "")
  stats::setNames(unname(vals), keys)
}

#' One wire answer as a canonical answer, probabilities re-keyed by option name (07 section 3)
#'
#' TypeSafe's answer may leave out its probabilities (NA, not zero), its confidence (recomputed)
#' and its choice or score; Ollama's needs probabilities and a score, is checked at four decimals
#' and its confidence must match the entropy formula (D-120). Problems are unsignalled conditions.
#' @noRd
s1_parse_answer = function(answer, question, model_id = NA_character_, ollama = FALSE) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  type = if (is.list(question)) question[["type"]] else NULL
  if (!rlang::is_string(type, s1_types)) {
    return(bad("System 1 was sent a question without a known type."))
  }
  if (!is.list(answer) || !identical(answer[["type"]], type)) {
    return(bad(paste0("System 1 returned an answer that is not a ", type, " answer.")))
  }
  if (identical(type, "noul")) {
    p = s1_unit(answer[["noul"]])
    if (is.na(p)) return(bad("System 1 returned an invalid probability."))
    return(list(type = "noul", prob = p))
  }
  keys = s1_option_keys(question)
  if (is.null(keys)) return(bad("System 1 was sent a question without valid options."))
  got = answer[["probabilities"]]
  if (ollama && !(is.list(got) && length(got))) {
    return(bad(paste0("System 1 returned a ", type, " answer without probabilities.")))
  }
  tol = if (ollama) s1_ollama_round_tol else s1_round_tol
  p = s1_answer_probs(got, keys, tol)
  if (is.character(p)) return(bad(p))
  conf = if (anyNA(p)) {
    NA_real_
  } else if (ollama) {
    s1_ollama_confidence(p)
  } else if (identical(type, "choice")) {
    s1_confidence_choice(p)
  } else {
    s1_confidence_score(p)
  }
  given = answer[["confidence"]]
  if (!is.null(given) && !anyNA(p)) {
    wire = s1_unit(given)
    if (is.na(wire)) return(bad("System 1 returned an invalid confidence."))
    if (ollama && abs(wire - conf) > s1_ollama_conf_tol) {
      return(bad("System 1 returned a confidence that its probabilities do not give."))
    }
    conf = wire
  }
  if (identical(type, "choice")) {
    return(s1_parse_choice(answer[["choice"]], p, keys, conf, bad, tol))
  }
  legend = answer[["legend"]]
  if (ollama && !is.null(legend) && !(is.list(legend) && length(legend) == length(keys) &&
                                        setequal(names(legend), keys) &&
                                        all(vapply(legend, rlang::is_string, NA)))) {
    return(bad("System 1 returned a score legend that does not name the levels asked."))
  }
  if (ollama && is.null(answer[["score"]])) {
    return(bad("System 1 returned a score answer without a score."))
  }
  s1_parse_score(answer[["score"]], p, keys, conf, s1_legend(question, keys), bad, tol)
}

#' All answers of one response (s1_answers_each()), or the condition of the first problem
#' @noRd
s1_parse_answers = function(answers, questions, model_id = NA_character_, ollama = FALSE) {
  s1_answers_each(answers, questions,
                  function(a, q, id) s1_parse_answer(a, q, model_id, ollama),
                  function(msg) s1_condition("s1_response", msg, model = model_id))
}

# ---- concurrent requests on the reactor ---------------------------------------------------------
# At most `gptr.s1_max_active` jobs in flight and `gptr.s1_rounds` rounds that resubmit only
# retryable failures; waits are reactor timers, never a sleep inside a callback. A model with a
# per-server limit is also admitted per origin across calls (s1_slots(); IC-74, 07 section 2).

#' One HTTP transfer on the reactor; `on_done(status, headers, body)` receives the whole body
#'
#' The reactor's own retries are off (s1_drive() retries in rounds); admission follows
#' `gptr.max_active` and the provider's token bucket (IC-64).
#' @noRd
s1_http = function(spec, provider, on_done, on_fail) {
  buf = new.env(parent = emptyenv())
  buf$chunks = list()
  reactor_http(spec,
               on_bytes = function(raw) {
                 buf$chunks[[length(buf$chunks) + 1L]] = raw
               },
               on_done = function(status, headers) {
                 bytes = do.call(c, buf$chunks)
                 on_done(status, headers, raw_to_utf8(if (is.null(bytes)) raw() else bytes))
               },
               on_fail = on_fail, provider = provider, retry = list(max_attempts = 1L))
}

#' The outcome of one classify result: ok with the result, or a (retryable?) failure
#'
#' A result that is neither a condition nor a list is a response error (never retried).
#' @noRd
s1_outcome = function(res, model_id = NA_character_) {
  if (inherits(res, "condition")) {
    return(list(ok = FALSE, error = res, retry = s1_retry_of(res),
                delay = s1_delay(res[["retry_after"]])))
  }
  if (!is.list(res)) {
    err = s1_condition("s1_response", "System 1 returned a result that is not a list.",
                       model = model_id)
    return(list(ok = FALSE, error = err, retry = FALSE, delay = NULL))
  }
  list(ok = TRUE, value = res)
}

#' Pump the reactor until `until()` holds
#'
#' A nested pump passes no run ids, so it never starts another run's FIFO tool (contract 8.2,
#' IC-57).
#' @noRd
s1_pump = function(until) {
  if (reactor_depth() > 0L) {
    reactor_pump(until = until, allow_runs = character())
  } else {
    reactor_pump(until = until)
  }
}

#' Wait on the reactor (interruptible; never a sleep inside a callback)
#' @noRd
s1_wait = function(seconds) {
  if (seconds <= 0) return(invisible(NULL))
  flag = new.env(parent = emptyenv())
  flag$done = FALSE
  id = reactor_timer(reactor_now() + seconds, function() {
    flag$done = TRUE
  })
  on.exit(if (!flag$done) reactor_cancel(id), add = TRUE)
  s1_pump(function() flag$done)
  invisible(NULL)
}

#' The process-wide table of System 1 requests in flight per server (IC-74 per-server admission)
#' @noRd
s1_slots = function() {
  if (is.null(the$s1_slots)) the$s1_slots = new.env(parent = emptyenv())
  the$s1_slots
}

#' The System 1 requests in flight to a server (a canonical origin)
#' @noRd
s1_slot_used = function(key) {
  v = get0(key, envir = s1_slots(), inherits = FALSE)
  if (is.null(v)) 0L else v
}

#' Take (`by > 0`) or give back (`by < 0`) slots of a server; never below zero
#' @noRd
s1_slot_shift = function(key, by) {
  env = s1_slots()
  n = s1_slot_used(key) + as.integer(by)
  if (n > 0L) {
    assign(key, n, envir = env)
  } else if (exists(key, envir = env, inherits = FALSE)) {
    rm(list = key, envir = env)
  }
  invisible(max(n, 0L))
}

#' The requests a model's own server takes at once (07 section 2): its decision record's
#' `max_active`, else one for a native Ollama model (s1_ollama_max_active), else NULL
#' @noRd
s1_own_active = function(model) {
  d = model[["decision"]]
  own = if (is.list(d)) d[["max_active"]] else NULL
  if (is.numeric(own) && length(own) == 1L && !is.na(own) && own >= 1) {
    return(as.integer(min(own, .Machine$integer.max)))
  }
  if (s1_ollama_native(model)) s1_ollama_max_active else NULL
}

#' The per-server gate of a request (07 section 2): `list(key, cap)` keyed by the endpoint's
#' canonical origin, so every call to that server shares the cap; NULL without s1_own_active()
#' @noRd
s1_gate = function(model, base_url) {
  if (is.null(s1_own_active(model))) return(NULL)
  if (!rlang::is_string(base_url)) return(NULL)
  origin = url_origin(base_url)
  if (is.na(origin)) return(NULL)
  list(key = origin, cap = s1_active_cap(model))
}

#' One round: start the jobs with at most `max_active` in flight and pump until all reported
#'
#' `start(k, done)` returns a reactor id or NULL and calls `done(outcome)` once; a job holds its
#' `gate` slot until then, and on exit unreported jobs are cancelled and their slots given back.
#' @noRd
s1_round = function(idx, start, max_active, gate = NULL) {
  st = new.env(parent = emptyenv())
  st$out = vector("list", length(idx))
  st$next_k = 1L
  st$active = 0L
  st$done = 0L
  st$ids = character()
  st$held = 0L
  n = length(idx)
  free = function() is.null(gate) || s1_slot_used(gate$key) < gate$cap
  finish = function(k) {
    force(k)
    function(res) {
      st$out[[k]] = res
      st$active = st$active - 1L
      st$done = st$done + 1L
      if (!is.null(gate) && st$held > 0L) {
        st$held = st$held - 1L
        s1_slot_shift(gate$key, -1L)
      }
      invisible(NULL)
    }
  }
  launch = function() {
    while (st$active < max_active && st$next_k <= n && free()) {
      k = st$next_k
      st$next_k = k + 1L
      st$active = st$active + 1L
      if (!is.null(gate)) {
        st$held = st$held + 1L
        s1_slot_shift(gate$key, 1L)
      }
      # do.call() passes values: a lazy `idx[k]` or `finish(k)` would be forced after `k` moved on
      id = do.call(start, list(idx[k], finish(k)))
      if (rlang::is_string(id)) st$ids = c(st$ids, id)
    }
    st$done >= n
  }
  on.exit({
    if (st$done < n && length(st$ids)) reactor_cancel(st$ids)
    if (!is.null(gate) && st$held > 0L) s1_slot_shift(gate$key, -st$held)
  }, add = TRUE)
  if (!launch()) s1_pump(launch)
  st$out
}

#' Bounded rounds: resubmit only retryable failures, waiting the largest requested delay
#'
#' Else `min(0.5 * 2^(r - 1), 5)` s, the TypeSafe SDK schedule without its jitter: gptr never
#' touches the RNG (IC-61).
#' @noRd
s1_drive = function(n, start, max_active, rounds, gate = NULL) {
  results = vector("list", n)
  pending = seq_len(n)
  round = 1L
  while (length(pending)) {
    got = s1_round(pending, start, max_active, gate)
    again = integer()
    wait = 0
    for (k in seq_along(pending)) {
      r = got[[k]]
      if (isTRUE(r$ok) || !isTRUE(r$retry) || round >= rounds) {
        results[[pending[k]]] = r
      } else {
        again = c(again, pending[k])
        wait = max(wait, r$delay %||% min(0.5 * 2^(round - 1L), 5))
      }
    }
    if (!length(again)) break
    s1_wait(min(wait, 60))
    pending = again
    round = round + 1L
  }
  results
}

#' The failures of a list of conditions as the `errors` table of meta (NULL when none)
#' @noRd
s1_errors_df = function(conditions) {
  bad = which(!vapply(conditions, is.null, TRUE))
  if (!length(bad)) return(NULL)
  data.frame(index = bad, class = vapply(conditions[bad], function(e) class(e)[1L], ""),
             message = vapply(conditions[bad], conditionMessage, ""), stringsAsFactors = FALSE)
}

# ---- admission and provenance (IC-74) ----------------------------------------------------------

#' The requests one System 1 call may keep in flight: `gptr.s1_max_active`, lowered by
#' s1_own_active()
#' @noRd
s1_active_cap = function(model) {
  cap = check_number(gptr_opt("s1_max_active"), "gptr.s1_max_active", min = 1, int = TRUE)
  own = s1_own_active(model)
  if (!is.null(own)) cap = min(cap, own)
  cap
}

#' The provenance of a call (07 section 3): the checked model's fields come before what an
#' adapter result reports, and locality is "unknown" unless one of them establishes it
#' @noRd
s1_provenance = function(model, values, engine) {
  pick = function(field, own = field, valid = NULL) {
    for (v in c(list(model[[own]]), lapply(values, function(r) r[[field]]))) {
      if (rlang::is_string(v, valid) && nzchar(v)) return(v)
    }
    NULL
  }
  list(provider = model[["provider"]] %||% NA_character_,
       api = model[["api"]] %||% NA_character_,
       execution = if (identical(engine, "emulated:structured")) "emulated" else "native",
       locality = pick("locality", valid = c("local", "remote", "unknown")) %||% "unknown",
       digest = pick("model_digest", "digest") %||% NA_character_,
       server_version = pick("server_version") %||% NA_character_,
       calibration_provenance = Find(Negate(is.null),
                                     lapply(values, function(r) r[["calibration_provenance"]])))
}

#' Deduplicate states, run one job per unique state and shape the result
#'
#' `answers[[i]]` holds state i's canonical answers, or NULL when `conditions[[i]]` holds its
#' failure. Unknown usage stays NA (IC-74, D-076).
#' @noRd
s1_dispatch = function(model, states, questions, start_for, engine, calibrated, gate = NULL) {
  max_active = s1_active_cap(model)
  rounds = check_number(gptr_opt("s1_rounds"), "gptr.s1_rounds", min = 1, int = TRUE)
  n = length(states)
  keys = vapply(states, canonical_json, "")
  uniq = which(!duplicated(keys))
  map = match(keys, keys[uniq])
  results = s1_drive(length(uniq), start_for(states[uniq]), max_active, rounds, gate)
  answers = vector("list", n)
  conditions = vector("list", n)
  usages = vector("list", n)
  input = 0
  output = 0
  version = NULL
  rids = character()
  values = list()
  for (j in seq_along(results)) {
    r = results[[j]]
    if (!isTRUE(r$ok)) {
      # a completed but refused reply was still charged (D-082)
      fu = r[["usage"]]
      if (is.list(fu)) {
        input = input + s1_count(fu[["input"]])
        output = output + s1_count(fu[["output"]])
      }
      next
    }
    # result fields are read with [[ ]]: `$` would partially match a longer field name
    v = r$value
    values[[length(values) + 1L]] = v
    u = if (is.list(v[["usage"]])) v[["usage"]] else list()
    input = input + s1_count(u[["input"]])
    output = output + s1_count(u[["output"]])
    version = version %||% v[["model_version"]]
    engine = v[["engine"]] %||% engine
    rid = s1_request_id(v)
    if (!is.na(rid)) rids = c(rids, rid)
  }
  checked = lapply(results, function(r) {
    if (!isTRUE(r$ok)) return(r$error)
    out = s1_check_answers(r$value[["answers"]], questions, model$id)
    if (inherits(out, "condition")) out$request_id = s1_request_id(r$value)
    out
  })
  for (i in seq_len(n)) {
    got = checked[[map[i]]]
    if (inherits(got, "condition")) {
      conditions[i] = list(got)
    } else {
      answers[i] = list(got)
      usages[i] = list(results[[map[i]]]$value[["usage"]])
    }
  }
  usage = list(input = input, output = output)
  usage$cost = s1_cost(usage, model)
  list(answers = answers, conditions = conditions, errors = s1_errors_df(conditions),
       usages = usages, usage = usage, model_version = version %||% model$id,
       request_ids = rids, engine = engine,
       calibrated = if (length(values)) {
         s1_calib(lapply(values, function(v) v[["calibrated"]] %||% calibrated))
       } else {
         calibrated
       },
       provenance = s1_provenance(model, values, engine))
}

#' The provider's request id of a classify result: one non-empty string, else NA
#' @noRd
s1_request_id = function(value) {
  rid = value[["request_id"]]
  if (rlang::is_string(rid) && nzchar(rid)) rid else NA_character_
}

#' The meta$engine of a classifier model: its provider id (contract 5.2, IC-74),
#' "emulated:structured" for s1-emulate and "fake" for P01's fake classifier (contract 12.1)
#' @noRd
s1_engine = function(model) {
  api = model[["api"]]
  if (identical(api, "s1-emulate")) return("emulated:structured")
  if (identical(api, "fake-classifier")) return("fake")
  model[["provider"]] %||% NA_character_
}

#' Send states to a classifier model (contract 7.13; IC-74): s1_dispatch()'s result
#'
#' The model is preflighted first, under `opts$safety`, the run's frozen safety record (NULL:
#' local-only); a `gptr_error_s1_*` from an adapter's `build` fails that state alone.
#' @noRd
s1_request = function(model, states, questions, opts = list()) {
  provider = opts[["provider"]] %||% s1_provider(model$provider)
  if (is.null(provider)) {
    gptr_abort(paste0("No provider is registered for the System 1 model ", model$provider, "/",
                      model$id, "."), "unknown_model", ref = paste0(model$provider, "/", model$id),
               suggestions = character())
  }
  model = s1_ollama_ready(s1_preflight(model, provider, safety = opts[["safety"]]))
  api = model[["api"]]
  if (!rlang::is_string(api)) api = provider[["api"]]
  adapter = s1_adapter(api)
  cl = adapter[["classify"]]
  run = if (is.list(cl)) cl[["run"]] else NULL
  if (!is.function(run) && !(is.list(cl) && is.function(cl[["build"]]) &&
                               is.function(cl[["parse"]]))) {
    gptr_abort(paste0("Model ", model$provider, "/", model$id, " cannot answer System 1 ",
                      "questions: its adapter ", api, " has no classify functions."),
               "invalid_argument", arg = "model", expected = "a classifier model")
  }
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  keyless = identical(api, s1_ollama_api)
  aopts = list(credential = if (!keyless) s1_credential(provider),
               base_url = s1_base_url(provider), signal = signal, provider = provider,
               images = opts[["images"]])
  gate = if (is.function(run)) NULL else s1_gate(model, aopts$base_url)
  start_for = function(ustates) {
    if (is.function(run)) {
      return(function(j, done) {
        res = tryCatch(run(model, ustates[[j]], questions, aopts), error = function(e) {
          s1_condition("s1_response", conditionMessage(e), model = model$id)
        })
        done(s1_outcome(res, model$id))
        NULL
      })
    }
    function(j, done) {
      spec = tryCatch(cl[["build"]](model, ustates[[j]], questions, aopts),
                      gptr_error_s1 = function(e) e)
      if (inherits(spec, "condition")) {
        done(s1_outcome(spec, model$id))
        return(NULL)
      }
      spec$request_id = id_new("q", 12L)
      spec$model = model$id
      spec$first_byte_timeout = spec[["first_byte_timeout"]] %||% 30
      spec$idle_timeout = spec[["idle_timeout"]] %||% 30
      s1_http(spec, provider[["id"]],
              on_done = function(status, headers, body) {
                res = tryCatch(cl[["parse"]](model, status, headers, body, questions),
                               error = function(e) {
                                 s1_condition("s1_response", conditionMessage(e), status,
                                              model = model$id)
                               })
                done(s1_outcome(res, model$id))
              },
              on_fail = function(cnd) {
                done(s1_failure(class(cnd), cnd[["status"]],
                                paste0("System 1 request failed: ", conditionMessage(cnd)),
                                cnd[["request_id"]], model$id, cnd[["retry_after"]]))
              })
    }
  }
  s1_dispatch(model, states, questions, start_for, s1_engine(model), NA, gate)
}

# ---- builtin:system1 ----------------------------------------------------------------------------

#' The body of the system1 prompt section, architecture 7.3 verbatim; P07 wraps it in <system1>
#' tags and replaces {s1} with the configured alias (contract 9.3)
#' @noRd
s1_section_body = paste0(
  "For fast typed judgements call a System 1 model from R instead of reasoning over each item ",
  "yourself: peter(\"Is this abstract about a randomised trial?\", abstracts, model = {s1}) ",
  "returns a logical vector with attr(, \"prob\"); with choices = c(\"a\", \"b\", \"c\") it ",
  "returns one choice per input. Calls are vectorised, so pass all items at once. Use them ",
  "inside if, for and while, and check items with probabilities near 0.5 yourself. Keep ",
  "open-ended reasoning, writing and code for yourself."
)

#' The system1 section (T0, order 650, budget 150; contract 9.3, IC-68), shown only when
#' model_default("system1") finds a usable System 1 (IC-74)
#' @noRd
s1_section_text = function(ctx) {
  if (is.null(s1_default_ref())) return(NULL)
  s1_section_body
}

#' A Jev model entry for a provider record (report 04 section 2.5); prices are a data frame, the
#' shape P02 validates for model records
#' @noRd
s1_jev_model = function(id, name, context = 64000) {
  list(id = id, name = name, family = "jev", type = "classifier", release_date = "2026-09-15",
       context = context, max_output = 0, reasoning = FALSE, thinking_levels = "off",
       input = "text", tool_call = FALSE, structured_output = TRUE,
       prices = data.frame(from = as.Date("2026-09-15"), tier = "default", input = 0.042,
                           output = 0, cache_read = 0, stringsAsFactors = FALSE),
       status = "active")
}

#' The provider records: `typesafe` (architecture 8.2; static rate of IC-64) and the gateway hosts
#' that serve the same protocol (report 04 sections 2.9 and 4.4)
#' @noRd
s1_provider_records = function() {
  list(
    gptr_provider("typesafe", api = "typesafe-system-one", base_url = "https://api.typesafe.ai/v1/",
                  auth = "TYPESAFE_API_KEY", type = "classifier",
                  rate = list(requests_per_s = 40, tokens_per_s = 1e5),
                  models = list(s1_jev_model("jev-latest", "Jev"),
                                s1_jev_model("jev-preview", "Jev (preview)"),
                                s1_jev_model("jev-1.13.0", "Jev 1.13"))),
    gptr_provider("openrouter-jev", api = "typesafe-system-one",
                  base_url = "https://openrouter.ai/api/v1/", auth = "OPENROUTER_API_KEY",
                  type = "classifier",
                  models = list(s1_jev_model("typesafe/jev-1.13", "Jev 1.13 (OpenRouter)", 32000))),
    gptr_provider("vercel-jev", api = "typesafe-system-one",
                  base_url = "https://ai-gateway.vercel.sh/typesafe/v1/",
                  auth = "AI_GATEWAY_API_KEY", type = "classifier",
                  models = list(s1_jev_model("typesafe-ai/jev", "Jev (Vercel AI Gateway)", 32000)))
  )
}

#' builtin:system1 (contract 7.13, 10.3; IC-74): the three classifier adapters, the provider
#' records, the classifier route (order 10) and the system1 prompt section
#' @noRd
builtin_system1 = function(gptr) {
  gptr$register(gptr_adapter("typesafe-system-one", transport = "http_json",
                             classify = list(build = s1_typesafe_build, parse = s1_typesafe_parse)))
  gptr$register(gptr_adapter(s1_ollama_api, transport = "http_json",
                             classify = list(build = s1_ollama_build, parse = s1_ollama_parse)))
  gptr$register(gptr_adapter("s1-emulate", transport = "inprocess",
                             classify = list(run = s1_emulate_classify)))
  for (p in s1_provider_records()) gptr$register(p)
  gptr$register(gptr_spec("route", "classifier", order = 10, match = s1_match, run = s1_call,
                          description = "System 1 models return typed vectors"))
  gptr$register(gptr_prompt_section("system1", s1_section_text, tier = "T0", order = 650L,
                                    budget = 150L))
  invisible(NULL)
}

on_load(ext_declare_builtin("system1", builtin_system1))
on_load(ext_service_set("s1.decide", s1_decide, provided_by = "P13", builtin = "system1"))
