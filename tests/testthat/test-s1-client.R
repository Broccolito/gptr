# Tests for R/s1-client.R (plan P13): questions, the typesafe-system-one adapter and its wire
# fixtures (Task 3), requests on the reactor (Task 4), builtin:system1 and the classifier route
# through peter() (Task 9) (contract 7.13, 8.1, 9.3; reports 04 and 04a; IC-74: classify$parse
# takes the ordered questions and returns canonical answers, 07-local-ollama.md section 3).

source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

jev_model = function() list(provider = "typesafe", id = "jev-latest", api = "typesafe-system-one")

# A stand-in credential handle (never materialised: only P04's http-request.R turns handles into
# values, and only for the handle's own origin)
fake_handle = function() {
  structure(list(id = "TYPESAFE_API_KEY#000000", name = "TYPESAFE_API_KEY", fp = "000000",
                 origin = "https://api.typesafe.ai"), class = "gptr_secret")
}

# A 200 body of the System One API holding the given wire answers
jev_body = function(answers, usage = list(input_tokens = 10, output_tokens = 2)) {
  json_encode(list(model = "jev-1.13.0", answers = answers, usage = usage))
}

# ---- Task 3: questions and the wire adapter -----------------------------------------------------

test_that("a yes/no question uses the wire type noul and names the state fields", {
  q = s1_question("Does this text describe a dog?", "text")
  expect_identical(q$type, "noul")
  ins = "Does this text describe a dog? The input is in `text`."
  expect_identical(q$wire, list(type = "noul", instructions = ins))
  expect_null(q$options)
  two = s1_question("Is a larger than b?", c("a", "b"))
  expect_identical(two$wire$instructions, "Is a larger than b? The inputs are in `a` and `b`.")
  three = s1_question("Q?", c("a", "b", "c"))
  expect_match(three$wire$instructions, "The inputs are in `a`, `b` and `c`.", fixed = TRUE)
  expect_false(grepl("bool", json_encode(q$wire), fixed = TRUE))
})

test_that("choices become a choice question; names carry descriptions; factors are remembered", {
  q = s1_question("Which animal?", "text", choices = c("dog", "cat"))
  expect_identical(q$type, "choice")
  expect_identical(q$options, c("dog", "cat"))
  expect_identical(json_encode(q$wire$criteria), "{\"dog\":null,\"cat\":null}")
  d = s1_question("Which?", "text", choices = c(standard = "Ordinary work", complex = "Hard work"))
  expect_identical(d$options, c("standard", "complex"))
  expect_identical(d$wire$criteria, list(standard = "Ordinary work", complex = "Hard work"))
  f = s1_question("Which?", "text", choices = factor(c("b", "a"), levels = c("b", "a")))
  expect_true(f$factor)
  expect_identical(f$options, c("b", "a"))
})

test_that("labels that if() reads as logical are rejected before any request", {
  for (lab in c("TRUE", "true", "True", "T", "FALSE", "false", "False", "F")) {
    err = expect_error(s1_question("Q?", "x", choices = c(lab, "maybe")),
                       class = "gptr_error_s1_labels")
    expect_s3_class(err, "gptr_error_s1")
    expect_identical(err$labels, lab)
  }
  expect_error(s1_question("Q?", "x", choices = "only"), class = "gptr_error_invalid_argument")
  expect_error(s1_question("Q?", "x", choices = c("a", "a")), class = "gptr_error_invalid_argument")
  expect_error(s1_question("Q?", "x", choices = c("a", "b"), levels = c("lo", "hi")),
               class = "gptr_error_invalid_argument")
})

test_that("levels become a score question with an array of 2 to 10 level descriptions", {
  q = s1_question("How positive?", "text", levels = c("Negative", "Neutral", "Positive"))
  expect_identical(q$type, "score")
  expect_identical(json_encode(q$wire$criteria), "[\"Negative\",\"Neutral\",\"Positive\"]")
  expect_error(s1_question("Q?", "x", levels = "one"), class = "gptr_error_invalid_argument")
  expect_error(s1_question("Q?", "x", levels = as.character(1:11)),
               class = "gptr_error_invalid_argument")
})

test_that("a model's decision record sets the question limits instead of TypeSafe's (IC-74)", {
  # 07-local-ollama.md section 2: Clef's decision record; its 2-26 options or levels replace
  # Jev's documented 255 options and 2-10 levels (04b: "do not assume Jev's limits apply")
  clef = list(types = c("noul", "choice", "score"), max_options = 26L)
  wide = s1_question("How?", "x", levels = as.character(1:11), decision = clef)
  expect_identical(wide$type, "score")
  expect_length(wide$wire$criteria, 11L)
  expect_error(s1_question("How?", "x", levels = as.character(1:27), decision = clef),
               class = "gptr_error_invalid_argument")
  many = paste0("o", 1:27)
  expect_length(s1_question("Which?", "x", choices = many)$options, 27L)
  expect_error(s1_question("Which?", "x", choices = many, decision = clef),
               class = "gptr_error_invalid_argument")
  expect_length(s1_question("Which?", "x", choices = many[1:26], decision = clef)$options, 26L)
  # a decision record without limits keeps TypeSafe's
  expect_error(s1_question("How?", "x", levels = as.character(1:11),
                           decision = list(types = "score")),
               class = "gptr_error_invalid_argument")
  only_noul = list(types = "noul", max_options = 26L)
  expect_identical(s1_question("Ok?", "x", decision = only_noul)$type, "noul")
  err = expect_error(s1_question("Which?", "x", choices = c("a", "b"), decision = only_noul),
                     class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "noul", fixed = TRUE)
  expect_error(s1_question("How?", "x", levels = c("lo", "hi"), decision = only_noul),
               class = "gptr_error_invalid_argument")
  expect_error(s1_question("Ok?", "x", decision = "clef"), class = "gptr_error_invalid_argument")
  expect_error(s1_question("Ok?", c("x", NA)), class = "gptr_error_invalid_argument")
})

test_that("the request body equals the recorded wire fixtures", {
  questions = list(
    noul = s1_question("Does this text describe a dog?", "text"),
    choice = s1_question("Which animal does the text describe?", "text",
                         choices = c("dog", "cat", "bird", "other")),
    score = s1_question("How positive is the sentiment of the text?", "text",
                        levels = c("Very negative", "Neutral", "Very positive"))
  )
  for (case in names(questions)) {
    fx = wire_fixture(case)
    q = questions[[case]]
    spec = s1_typesafe_build(jev_model(), fx$request$state, list(answer = q$wire),
                             list(base_url = "https://api.typesafe.ai/v1/", credential = NULL))
    expect_identical(json_decode(spec$body), fx$request, label = case)
    expect_identical(spec$url, "https://api.typesafe.ai/v1/systemone")
    expect_identical(spec$method, "POST")
    expect_identical(spec$stream, "json")
    expect_null(spec$headers$Authorization)
  }
})

test_that("the bearer credential stays a handle in the request spec", {
  opts = list(base_url = "https://api.typesafe.ai/v1", credential = fake_handle())
  spec = s1_typesafe_build(jev_model(), list(text = "x"),
                           list(answer = list(type = "noul", instructions = "Q?")), opts)
  auth = spec$headers$Authorization
  expect_identical(auth[[1L]], "Bearer ")
  expect_s3_class(auth[[2L]], "gptr_secret")
  expect_false(grepl("TYPESAFE_API_KEY#", spec$body, fixed = TRUE))
  expect_match(spec$headers$`User-Agent`, "^gptr/")
  expect_error(s1_typesafe_build(jev_model(), list(text = "x"), list(), list()),
               class = "gptr_error_invalid_argument")
})

test_that("responses parse by name: choice probabilities come back in request order", {
  fx = wire_fixture("choice")
  questions = list(answer = fx$request$questions$answer)
  res = s1_typesafe_parse(jev_model(), 200L, list(`x-typesafe-request-id` = "req_1"),
                          json_encode(fx$response), questions)
  expect_identical(res$model_version, "jev-1.13.0")
  expect_identical(res$request_id, "req_1")
  expect_identical(res$usage, list(input = 312, output = 12))
  a = res$answers
  expect_identical(names(a), "answer")
  expect_identical(a$answer$choice, "dog")
  expect_identical(names(a$answer$probabilities), c("dog", "cat", "bird", "other"))
  expect_identical(unname(a$answer$probabilities), c(1, 0, 0, 0))
  expect_identical(a$answer$confidence, 1)
  # the adapter normalises exactly once: the result equals parsing the wire answers directly
  expect_identical(s1_parse_answers(fx$response$answers, questions), a)
})

test_that("a non-ASCII choice matches labels marked 'unknown', as readLines() gives them", {
  skip_if_not(l10n_info()[["UTF-8"]])
  labels = c("caf\u00e9", "th\u00e9")
  Encoding(labels) = "unknown"
  q = list(answer = s1_question("Which drink?", "x", choices = labels)$wire)
  wire = list(answer = list(type = "choice", choice = "caf\u00e9",
                            probabilities = stats::setNames(list(0.8, 0.2), labels)))
  a = s1_typesafe_parse(jev_model(), 200L, list(), jev_body(wire), q)$answers$answer
  expect_identical(a$choice, "caf\u00e9")
  expect_identical(s1_cache_record("k", a, "m", "a", q$answer, list(), "", list())$prob, 0.8)
})

test_that("a multi-question response parses noul, choice and score answers together", {
  fx = wire_fixture("multi")
  res = s1_typesafe_parse(jev_model(), 200L, list(), json_encode(fx$response),
                          fx$request$questions)
  a = res$answers
  expect_identical(names(a), c("is_dog", "animal", "cuteness"))
  expect_identical(a$is_dog, list(type = "noul", prob = 0.99))
  expect_identical(names(a$animal$probabilities), c("dog", "cat", "bird", "other"))
  expect_identical(a$cuteness$score, 1.98)
  expect_identical(unname(a$cuteness$probabilities), c(0, 0.02, 0.98))
  expect_identical(names(a$cuteness$probabilities), c("0", "1", "2"))
  expect_identical(a$cuteness$confidence, 0.97)
  # canonical score records carry the legend of the requested levels (07 section 3)
  expect_identical(names(a$cuteness), c("type", "score", "probabilities", "confidence", "legend"))
  expect_identical(a$cuteness$legend, c(`0` = "Very negative", `1` = "Neutral",
                                        `2` = "Very positive"))
  expect_identical(names(a$animal), c("type", "choice", "probabilities", "confidence"))
  expect_true(is.na(res$request_id))
})

test_that("unknown response fields are ignored", {
  fx = wire_fixture("extra-fields")
  res = s1_typesafe_parse(jev_model(), 200L, list(), json_encode(fx$response),
                          fx$request$questions)
  a = res$answers
  expect_identical(a$positive$prob, 0.98)
  expect_identical(a$genre$choice, "fiction")
  expect_identical(a$positive, list(type = "noul", prob = 0.98))
})

test_that("error bodies become classed System 1 conditions with the service's message", {
  cases = list(`error-400` = "gptr_error_s1_validation", `error-401` = "gptr_error_s1_auth",
               `error-422` = "gptr_error_s1_validation", `error-429` = "gptr_error_s1_rate_limit")
  q = list(answer = list(type = "noul", instructions = "Q?"))
  for (case in names(cases)) {
    fx = wire_fixture(case)
    cnd = s1_typesafe_parse(jev_model(), as.integer(fx$status), list(), json_encode(fx$response),
                            q)
    expect_s3_class(cnd, cases[[case]])
    expect_s3_class(cnd, "gptr_error_s1")
    expect_identical(cnd$status, as.integer(fx$status))
    expect_identical(cnd$model, "jev-latest")
  }
  body401 = json_encode(wire_fixture("error-401")$response)
  e401 = s1_typesafe_parse(jev_model(), 401L, list(), body401, q)
  expect_match(conditionMessage(e401), "Cannot authenticate", fixed = TRUE)
  expect_identical(e401$error_type, "authentication_error")
  body422 = json_encode(wire_fixture("error-422")$response)
  e422 = s1_typesafe_parse(jev_model(), 422L, list(), body422, q)
  expect_match(conditionMessage(e422), "body.state: Field required", fixed = TRUE)
  flat = s1_typesafe_parse(jev_model(), 400L, list(),
                           "{\"message\": \"questions.q.type: bad\", \"error_type\": \"invalid\"}",
                           q)
  expect_match(conditionMessage(flat), "questions.q.type: bad", fixed = TRUE)
  bad = s1_typesafe_parse(jev_model(), 200L, list(), "{\"model\": \"jev-1.13.0\"}", q)
  expect_s3_class(bad, "gptr_error_s1_response")
  odd = s1_typesafe_parse(jev_model(), 400L, list(), "{\"detail\": [\"no field path\"]}", q)
  expect_s3_class(odd, "gptr_error_s1_validation")
  expect_match(conditionMessage(odd), "no field path", fixed = TRUE)
  html = s1_typesafe_parse(jev_model(), 502L, list(), "<html>Bad gateway</html>", q)
  expect_s3_class(html, "gptr_error_s1_overloaded")
})

test_that("malformed answers are response errors, never wrong values", {
  q = list(type = "noul", instructions = "Q?")
  expect_s3_class(s1_parse_answer(list(type = "noul", noul = 1.5), q), "gptr_error_s1_response")
  expect_s3_class(s1_parse_answer(list(type = "choice"), q), "gptr_error_s1_response")
  expect_s3_class(s1_parse_answer(NULL, q), "gptr_error_s1_response")
  ch = list(type = "choice", instructions = "Q?", criteria = list(a = NULL, b = NULL))
  expect_s3_class(s1_parse_answer(list(type = "choice", choice = "c",
                                       probabilities = list(a = 0.5, b = 0.5)), ch),
                  "gptr_error_s1_response")
  expect_s3_class(s1_parse_answer(list(type = "choice", choice = "a",
                                       probabilities = list(a = 1)), ch),
                  "gptr_error_s1_response")
})

test_that("answers are validated against the request before they become canonical (IC-74)", {
  # 07 section 3: finite values, bounds, expected answer IDs, allowed option names,
  # probability sums and score reconstruction
  is_bad = function(x) inherits(x, "gptr_error_s1_response")
  ch = list(type = "choice", instructions = "Q?", criteria = list(a = NULL, b = NULL, c = NULL))
  sc = list(type = "score", instructions = "Q?", criteria = list("low", "mid", "high"))
  ok_probs = list(c = 0.1, a = 0.7, b = 0.2)
  expect_false(is_bad(s1_parse_answer(list(type = "choice", choice = "a",
                                           probabilities = ok_probs), ch)))
  extra = list(a = 0.7, b = 0.2, c = 0.1, d = 0)
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a",
                                          probabilities = extra), ch)))
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a",
                                          probabilities = list(a = 1.2, b = 0, c = 0)), ch)))
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a",
                                          probabilities = list(a = 0.7, b = 0.7, c = 0)), ch)))
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a",
                                          probabilities = list(a = "x", b = 0.5, c = 0.5)), ch)))
  # a choice its own probabilities contradict is a wrong value
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "b",
                                          probabilities = ok_probs), ch)))
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a", confidence = 1.5,
                                          probabilities = ok_probs), ch)))
  expect_true(is_bad(s1_parse_answer(list(type = "choice", choice = "a", confidence = "high",
                                          probabilities = ok_probs), ch)))
  # two-decimal rounding (report 04a) is tolerated; ties keep the request order
  tie = s1_parse_answer(list(type = "choice", probabilities = list(c = 0.33, b = 0.33, a = 0.33)),
                        ch)
  expect_identical(tie$choice, "a")
  expect_identical(names(tie$probabilities), c("a", "b", "c"))
  # scores: within [0, levels - 1], equal to the expected level of their probabilities
  p3 = list(`0` = 0, `1` = 0.02, `2` = 0.98)
  expect_true(is_bad(s1_parse_answer(list(type = "score", score = 2.5, probabilities = p3), sc)))
  expect_true(is_bad(s1_parse_answer(list(type = "score", score = -0.1), sc)))
  expect_true(is_bad(s1_parse_answer(list(type = "score", score = 1.2, probabilities = p3), sc)))
  expect_true(is_bad(s1_parse_answer(list(type = "score", score = "high", probabilities = p3),
                                     sc)))
  doc = list(type = "score", instructions = "Q?", criteria = as.list(c("a", "b", "c", "d")))
  four = s1_parse_answer(list(type = "score", score = 2.52, confidence = 0.52,
                              probabilities = list(`3` = 0.52, `2` = 0.48, `1` = 0, `0` = 0)),
                         doc)
  expect_identical(four$score, 2.52)
  expect_identical(unname(four$probabilities), c(0, 0, 0.48, 0.52))
  # a missing score is the expected level, fractional and never rounded to a category
  rebuilt = s1_parse_answer(list(type = "score", probabilities = list(`0` = 0.1, `1` = 0.43,
                                                                       `2` = 0.47)), sc)
  expect_equal(rebuilt$score, 1.37, tolerance = 1e-12)
  expect_identical(rebuilt$legend, c(`0` = "low", `1` = "mid", `2` = "high"))
  expect_true(is_bad(s1_parse_answer(list(type = "noul", noul = TRUE), list(type = "noul"))))
  expect_true(is_bad(s1_parse_answer(list(type = "noul", noul = 0.5), list(type = "bool"))))
  # answer IDs: every question answered, nothing else
  qs = list(x = list(type = "noul", instructions = "Q?"), y = list(type = "noul",
                                                                    instructions = "R?"))
  expect_true(is_bad(s1_parse_answers(list(x = list(type = "noul", noul = 0.4)), qs)))
  expect_true(is_bad(s1_parse_answers(list(x = list(type = "noul", noul = 0.4),
                                           y = list(type = "noul", noul = 0.6),
                                           z = list(type = "noul", noul = 0.1)), qs)))
  expect_true(is_bad(s1_parse_answers(list(list(type = "noul", noul = 0.4)), qs)))
  both = s1_parse_answers(list(y = list(type = "noul", noul = 0.6),
                               x = list(type = "noul", noul = 0.4)), qs)
  expect_identical(names(both), c("x", "y"))
  # a malformed answer inside a 200 response carries the response's status and request id
  cnd = s1_typesafe_parse(jev_model(), 200L, list(`X-TypeSafe-Request-Id` = "req_9"),
                          jev_body(list(x = list(type = "noul", noul = 2))), qs["x"])
  expect_s3_class(cnd, "gptr_error_s1_response")
  expect_identical(cnd$status, 200L)
  expect_identical(cnd$request_id, "req_9")
  expect_identical(cnd$model, "jev-latest")
})

test_that("an empty probability map (a gateway rerun) is missing, not zero", {
  ch = list(type = "choice", instructions = "Q?", criteria = list(a = NULL, b = NULL))
  a = s1_parse_answer(list(type = "choice", choice = "a", probabilities = json_obj(),
                           confidence = 0), ch)
  expect_identical(a$choice, "a")
  expect_true(all(is.na(a$probabilities)))
  expect_true(is.na(a$confidence))
  sc = list(type = "score", instructions = "Q?", criteria = list("lo", "hi"))
  s = s1_parse_answer(list(type = "score", score = 0.7, probabilities = json_obj(),
                           confidence = 0), sc)
  expect_identical(s$score, 0.7)
  expect_identical(names(s$probabilities), c("0", "1"))
  expect_true(all(is.na(s$probabilities)))
  expect_true(is.na(s$confidence))
  expect_identical(s$legend, c(`0` = "lo", `1` = "hi"))
})

test_that("usage the service does not report stays unknown (IC-74)", {
  qs = list(x = list(type = "noul", instructions = "Q?"))
  answers = list(x = list(type = "noul", noul = 0.4))
  none = s1_typesafe_parse(jev_model(), 200L, list(),
                           json_encode(list(model = "jev-1.13.0", answers = answers)), qs)
  expect_identical(none$usage, list(input = NA_real_, output = NA_real_))
  part = s1_typesafe_parse(jev_model(), 200L, list(),
                           jev_body(answers, list(input_tokens = NULL, output_tokens = -1)), qs)
  expect_identical(part$usage, list(input = NA_real_, output = NA_real_))
  known = s1_typesafe_parse(jev_model(), 200L, list(), jev_body(answers), qs)
  expect_identical(known$usage, list(input = 10, output = 2))
  # without a physical id in the response, the requested model id stands for it
  bare = s1_typesafe_parse(jev_model(), 200L, list(), json_encode(list(answers = answers)), qs)
  expect_identical(bare$model_version, "jev-latest")
})

test_that("missing confidences are recomputed with TypeSafe's formulas (report 04 2.4)", {
  # the documented confidences agree with the formulas up to the two-decimal rounding of the
  # documented probabilities (report 04 verification log item 5)
  expect_lt(abs(s1_confidence_choice(c(0.61, 0.35, 0.04)) - 0.42), 0.01)
  expect_lt(abs(s1_confidence_choice(c(0.40, 0.34, 0.24, 0.02)) - 0.20), 0.01)
  expect_lt(abs(s1_confidence_score(c(0, 0, 0.48, 0.52)) - 0.52), 0.01)
  expect_lt(abs(s1_confidence_score(c(0, 0.14, 0.86, 0, 0)) - 0.89), 0.01)
  ch = list(type = "choice", instructions = "Q?", criteria = list(a = NULL, b = NULL, c = NULL))
  a = s1_parse_answer(list(type = "choice", choice = "a",
                           probabilities = list(c = 0.04, b = 0.35, a = 0.61)), ch)
  expect_equal(a$confidence, 0.415, tolerance = 1e-9)
})

test_that("HTTP statuses map to the System 1 classes of report 04 section 4.12", {
  expect_identical(s1_status_class(401L), "s1_auth")
  expect_identical(s1_status_class(403L), "s1_auth")
  expect_identical(s1_status_class(400L), "s1_validation")
  expect_identical(s1_status_class(422L), "s1_validation")
  expect_identical(s1_status_class(408L), "s1_connection")
  expect_identical(s1_status_class(429L), "s1_rate_limit")
  expect_identical(s1_status_class(529L), "s1_overloaded")
  expect_identical(s1_status_class(503L), "s1_overloaded")
  expect_identical(s1_status_class(NA_integer_), "s1_connection")
  expect_identical(s1_status_class(418L), "s1_response")
  expect_true(s1_retry_of(s1_condition("s1_rate_limit", "x")))
  expect_false(s1_retry_of(s1_condition("s1_auth", "x")))
  expect_identical(s1_delay(120), 60)
  expect_null(s1_delay(NULL))
})

# ---- Task 4: requests on the reactor ------------------------------------------------------------

noul_questions = function() list(answer = list(type = "noul", instructions = "Is it a dog?"))

states_of = function(texts) lapply(texts, function(t) list(text = t))

# An offline provider record that speaks the typesafe protocol; its transfers are faked below
wire_provider = function(id = "wiretest") {
  gptr_provider(id, api = "typesafe-system-one", base_url = "http://127.0.0.1:9/v1/",
                type = "classifier", local = TRUE, offline = TRUE,
                models = list(list(id = "wire-s1", type = "classifier")))
}

# Replace s1_http() with a reactor-timer stand-in: each transfer completes after `delay` seconds
# with the reply of `respond(body)` (`list(status, body, headers, retry_after)`); returns the log
local_fake_transfers = function(respond, delay = 0.02, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$active = 0L
  log$max_active = 0L
  log$bodies = list()
  local_mocked_bindings(s1_http = function(spec, provider, on_done, on_fail) {
    log$active = log$active + 1L
    log$max_active = max(log$max_active, log$active)
    body = json_decode(spec$body)
    log$bodies[[length(log$bodies) + 1L]] = body
    reply = respond(body)
    reactor_timer(reactor_now() + delay, function() {
      log$active = log$active - 1L
      if (is.null(reply$status) || reply$status < 300L) {
        on_done(200L, reply$headers %||% list(), json_encode(reply$body))
      } else {
        cls = if (reply$status == 429L) "rate_limit" else "overloaded"
        on_fail(gptr_condition(paste("HTTP", reply$status), c(cls, "provider"), "error",
                               list(status = reply$status, retry_after = reply$retry_after,
                                    request_id = "q000000000001", error_type = cls)))
      }
    })
  }, .env = .env)
  log
}

ok_reply = function(body, p = 0.9) {
  list(body = list(model = "wire-1.0", answers = list(answer = list(type = "noul", noul = p)),
                   usage = list(input_tokens = 100L, output_tokens = 2L)))
}

test_that("a fake classifier answers every state; identical states are sent once", {
  judge = local_fake_provider(function(state, question) {
    if (grepl("puppy", state$text)) 0.95 else 0.05
  }, name = "judge", type = "classifier")
  res = s1_request(s1_model(judge), states_of(c("a puppy", "a car", "a puppy")),
                   noul_questions(), list(provider = judge))
  expect_length(res$answers, 3L)
  expect_identical(res$answers[[1]]$answer$prob, 0.95)
  expect_identical(res$answers[[2]]$answer$prob, 0.05)
  expect_identical(res$answers[[3]]$answer$prob, 0.95)
  expect_length(fake_requests(judge), 2L)
  expect_identical(res$model_version, "judge-s1-1.0")
  expect_identical(res$engine, "fake")
  # IC-74 (07 section 3): synthetic probabilities carry no calibration claim; unknown stays NA
  expect_identical(res$calibrated, NA)
  expect_null(res$errors)
  expect_identical(res$provenance[c("provider", "api", "execution", "locality")],
                   list(provider = "judge", api = "fake-classifier", execution = "native",
                        locality = "local"))
})

test_that("at most gptr.s1_max_active requests are in flight", {
  log = local_fake_transfers(function(body) ok_reply(body), delay = 0.05)
  p = wire_provider()
  res = s1_request(s1_model(p), states_of(paste("item", 1:30)), noul_questions(),
                   list(provider = p))
  expect_identical(log$max_active, 8L)
  expect_length(log$bodies, 30L)
  expect_true(all(vapply(res$answers, function(a) identical(a$answer$prob, 0.9), NA)))
  expect_identical(res$usage$input, 3000)
  expect_identical(res$model_version, "wire-1.0")
  # IC-74: the engine is the provider id, and an adapter that states no calibration leaves it NA
  expect_identical(res$engine, "wiretest")
  expect_identical(res$calibrated, NA)
  local_gptr_options(s1_max_active = 3L)
  log3 = local_fake_transfers(function(body) ok_reply(body), delay = 0.02)
  s1_request(s1_model(p), states_of(paste("other", 1:10)), noul_questions(), list(provider = p))
  expect_identical(log3$max_active, 3L)
})

test_that("bounded rounds resubmit only failed elements, honouring retry-after up to 60 s", {
  seen = new.env(parent = emptyenv())
  seen$calls = list()
  seen$waits = numeric()
  local_mocked_bindings(s1_wait = function(seconds) {
    seen$waits = c(seen$waits, seconds)
    invisible(NULL)
  })
  local_fake_transfers(function(body) {
    t = body$state$text
    seen$calls[[t]] = (seen$calls[[t]] %||% 0L) + 1L
    if (identical(t, "flaky") && seen$calls[[t]] == 1L) {
      return(list(status = 429L, retry_after = 120))
    }
    if (identical(t, "down")) return(list(status = 503L))
    ok_reply(body)
  })
  p = wire_provider()
  res = s1_request(s1_model(p), states_of(c("fine", "flaky", "down")), noul_questions(),
                   list(provider = p))
  expect_identical(seen$calls$fine, 1L)
  expect_identical(seen$calls$flaky, 2L)
  expect_identical(seen$calls$down, 3L)
  expect_identical(seen$waits, c(60, 1))
  expect_identical(res$answers[[2]]$answer$prob, 0.9)
  expect_null(res$answers[[3]])
  expect_s3_class(res$conditions[[3]], "gptr_error_s1_overloaded")
  expect_identical(res$errors$index, 3L)
  local_gptr_options(s1_rounds = 1L)
  seen$calls = list()
  s1_request(s1_model(p), states_of("down"), noul_questions(), list(provider = p))
  expect_identical(seen$calls$down, 1L)
})

test_that("transport failures map to retryable or final System 1 conditions", {
  # a reactor failure's class (contract 2.2) as s1_request() hands it over
  fail = function(cls, status = NA_integer_, retry_after = NULL) {
    s1_failure(paste0("gptr_error_", cls), status, "x", NA, "jev-latest", retry_after)
  }
  net = fail("network")
  expect_s3_class(net$error, "gptr_error_s1_connection")
  expect_true(net$retry)
  auth = fail("auth", 401L)
  expect_s3_class(auth$error, "gptr_error_s1_auth")
  expect_false(auth$retry)
  rl = fail("rate_limit", 429L, retry_after = 3)
  expect_true(rl$retry)
  expect_identical(rl$delay, 3)
  idle = fail("timeout_idle")
  expect_s3_class(idle$error, "gptr_error_s1_connection")
  redirect = fail("redirect", 307L)
  expect_false(redirect$retry)
  # a server delay above gptr.max_retry_delay is final (IC-64), as on the emulation path
  expect_false(fail("retry_after", 429L, 120)$retry)
})

test_that("an unregistered provider without a spec is an unknown model", {
  expect_error(s1_request(list(provider = "nobody", id = "x"), states_of("a"), noul_questions()),
               class = "gptr_error_unknown_model")
})

test_that("against a mocked /systemone the client parses real HTTP replies within 8 active", {
  srv = local_mock_server("systemone", answers = function(body) {
    p = if (grepl("7", unlist(body$state), fixed = TRUE)) 0.1 else 0.9
    list(answer = list(type = "noul", noul = p))
  })
  p = srv$provider
  real = s1_http
  seen = new.env(parent = emptyenv())
  seen$active = 0L
  seen$max = 0L
  local_mocked_bindings(s1_http = function(spec, provider, on_done, on_fail) {
    seen$active = seen$active + 1L
    seen$max = max(seen$max, seen$active)
    real(spec, provider,
         on_done = function(status, headers, body) {
           seen$active = seen$active - 1L
           on_done(status, headers, body)
         },
         on_fail = function(cnd) {
           seen$active = seen$active - 1L
           on_fail(cnd)
         })
  })
  x = paste("item", 1:40)
  res = s1_request(s1_model(p), states_of(x), noul_questions(), list(provider = p))
  probs = vapply(res$answers, function(a) a$answer$prob, 0)
  expect_identical(probs, ifelse(grepl("7", x, fixed = TRUE), 0.1, 0.9))
  expect_identical(res$model_version, "jev-mock-1.0")
  expect_true(all(startsWith(res$request_ids, "req_mock_")))
  expect_lte(seen$max, 8L)
  expect_gt(seen$max, 1L)
  expect_identical(nrow(srv$log()), 40L)
})

# ---- Task 4, IC-74 (07-local-ollama.md sections 2-5) and IC-57 ---------------------------------

test_that("the adapter follows the resolved model's api, not its provider's (IC-74)", {
  log = local_fake_transfers(function(body) ok_reply(body, 0.3))
  mixed = gptr_provider("mixedwire", api = "openai-completions",
                        base_url = "http://127.0.0.1:9/v1/", local = TRUE, offline = TRUE,
                        models = list(list(id = "decider", type = "classifier",
                                           api = "typesafe-system-one")))
  m = s1_model(mixed)
  expect_identical(m$api, "typesafe-system-one")
  res = s1_request(m, states_of("x"), noul_questions(), list(provider = mixed))
  expect_identical(res$answers[[1]]$answer$prob, 0.3)
  expect_identical(res$engine, "mixedwire")
  expect_identical(res$provenance$api, "typesafe-system-one")
  expect_identical(res$provenance$locality, "unknown")
  expect_length(log$bodies, 1L)
  # a model whose adapter has no classify functions is refused before any request
  chatty = local_fake_provider(list("hello"), name = "chatty")
  expect_error(s1_request(s1_model(chatty), states_of("x"), noul_questions(),
                          list(provider = chatty)),
               class = "gptr_error_invalid_argument")
  expect_length(fake_requests(chatty), 0L)
})

test_that("the request preflight runs before any adapter, credential or transfer (IC-74)", {
  local_mocked_bindings(catalog_ollama_discover = function(...) stop("discovery must not run"),
                        s1_adapter = function(api) stop("an adapter was looked up"),
                        s1_credential = function(provider) stop("a credential was looked up"))
  local_no_network()
  clef = function(id, base_url) {
    gptr_provider(id, api = "ollama-system-one", type = "classifier", base_url = base_url,
                  models = list(list(id = "clef-flash", type = "classifier",
                                     api = "ollama-system-one")))
  }
  lp = clef("lclef", "http://127.0.0.1:11434")
  expect_error(s1_request(s1_model(lp), states_of("a"), noul_questions(), list(provider = lp)),
               class = "gptr_error_not_available")
  remote = clef("rclef", "https://ollama.example.invalid")
  expect_error(s1_request(s1_model(remote), states_of("a"), noul_questions(),
                          list(provider = remote)),
               class = "gptr_error_untrusted")
  # only the protected safety record relaxes local-only; evidence is still required
  expect_error(s1_request(s1_model(remote), states_of("a"), noul_questions(),
                          list(provider = remote, safety = list(ollama_local_only = FALSE))),
               class = "gptr_error_not_available")
  # an option that only starts with "safety" is not the safety record (no partial matching)
  expect_error(s1_request(s1_model(remote), states_of("a"), noul_questions(),
                          list(provider = remote,
                               safety_snapshot = list(ollama_local_only = FALSE))),
               class = "gptr_error_untrusted")
})

test_that("a model's decision record lowers the requests in flight (IC-74)", {
  log = local_fake_transfers(function(body) ok_reply(body), delay = 0.02)
  p = gptr_provider("pairwise", api = "typesafe-system-one", base_url = "http://127.0.0.1:9/v1/",
                    type = "classifier", local = TRUE, offline = TRUE,
                    models = list(list(id = "pair-s1", type = "classifier",
                                       decision = list(max_active = 2L))))
  m = s1_model(p)
  expect_identical(m$decision$max_active, 2L)
  res = s1_request(m, states_of(paste("item", 1:6)), noul_questions(), list(provider = p))
  expect_identical(log$max_active, 2L)
  expect_length(log$bodies, 6L)
  expect_null(res$errors)
  # the global System 1 cap stays an upper bound
  local_gptr_options(s1_max_active = 1L)
  log1 = local_fake_transfers(function(body) ok_reply(body), delay = 0.02)
  s1_request(m, states_of(paste("other", 1:4)), noul_questions(), list(provider = p))
  expect_identical(log1$max_active, 1L)
  local_gptr_options(s1_max_active = 0L)
  expect_error(s1_request(m, states_of("z"), noul_questions(), list(provider = p)),
               class = "gptr_error_invalid_argument")
})

test_that("dispatch validates canonical answers and never runs a wire parser again (IC-74)", {
  local_mocked_bindings(s1_parse_answers = function(...) stop("a wire parser ran again"),
                        s1_parse_answer = function(...) stop("a wire parser ran again"))
  seen = new.env(parent = emptyenv())
  seen$n = 0L
  pick = function(p, conf = 0.6) {
    list(type = "choice", choice = "dog", probabilities = p, confidence = conf)
  }
  rate = function(score = 1.2, p = c(`0` = 0.1, `1` = 0.6, `2` = 0.3)) {
    list(type = "score", score = score, probabilities = p, confidence = 0.5,
         legend = c(`0` = "low", `1` = "mid", `2` = "high"))
  }
  run = function(model, state, questions, opts) {
    seen$n = seen$n + 1L
    t = state$text
    good = list(pick = pick(c(cat = 0.2, dog = 0.8)), rate = rate())
    answers = switch(t,
      good = , calibrated = , uncalibrated = good,
      wire = list(pick = list(type = "choice", choice = "dog",
                              probabilities = list(dog = 0.8, cat = 0.2)), rate = rate()),
      sum = list(pick = pick(c(dog = 0.4, cat = 0.1)), rate = rate()),
      extra = c(good, list(other = list(type = "noul", prob = 0.5))),
      score = list(pick = pick(c(dog = 0.8, cat = 0.2)), rate = rate(score = 2)),
      unknown = list(pick = pick(c(dog = NA_real_, cat = NA_real_), NA_real_),
                     rate = rate(1.5, c(`0` = NA_real_, `1` = NA_real_, `2` = NA_real_))))
    out = list(answers = answers, model_version = "canon-1.0", locality = "local")
    if (!identical(t, "unknown")) out$usage = list(input = 5, output = 1)
    if (identical(t, "calibrated")) out$calibrated = TRUE
    if (identical(t, "uncalibrated")) out$calibrated = FALSE
    out
  }
  off = gptr_register(gptr_adapter("canon-test", transport = "inprocess",
                                   classify = list(run = run)))
  withr::defer(off())
  p = gptr_provider("canon", api = "canon-test", type = "classifier", local = TRUE,
                    offline = TRUE,
                    models = list(list(id = "canon-s1", type = "classifier",
                                       prices = data.frame(from = "2026-01-01",
                                                           tier = "default", input = 1,
                                                           output = 1))))
  m = s1_model(p)
  qs = list(pick = list(type = "choice", instructions = "Which?",
                        criteria = list(dog = NULL, cat = NULL)),
            rate = list(type = "score", instructions = "How much?",
                        criteria = list("low", "mid", "high")))
  texts = c("good", "wire", "sum", "extra", "score", "unknown")
  res = s1_request(m, states_of(texts), qs, list(provider = p))
  expect_identical(seen$n, 6L)
  ok = res$answers[[1]]
  expect_identical(names(ok), c("pick", "rate"))
  expect_identical(ok$pick$probabilities, c(dog = 0.8, cat = 0.2))
  expect_identical(ok$pick$choice, "dog")
  expect_identical(ok$rate$score, 1.2)
  expect_identical(ok$rate$legend, c(`0` = "low", `1` = "mid", `2` = "high"))
  for (i in 2:5) {
    expect_null(res$answers[[i]])
    expect_s3_class(res$conditions[[i]], "gptr_error_s1_response")
  }
  expect_identical(res$errors$index, 2:5)
  unknown = res$answers[[6]]
  expect_identical(unknown$pick$probabilities, c(dog = NA_real_, cat = NA_real_))
  expect_identical(unknown$pick$confidence, NA_real_)
  expect_identical(unknown$rate$score, 1.5)
  # one request without usage makes the total unknown, never a known zero (IC-74, D-076)
  expect_identical(res$usage$input, NA_real_)
  expect_identical(res$usage$cost, NA_real_)
  expect_identical(res$calibrated, NA)
  expect_identical(res$provenance$locality, "local")
  known = s1_request(m, states_of(c("calibrated", "good")), qs, list(provider = p))
  expect_identical(known$usage$input, 10)
  expect_false(is.na(known$usage$cost))
  expect_identical(known$calibrated, NA)
  expect_identical(s1_request(m, states_of("calibrated"), qs, list(provider = p))$calibrated,
                   TRUE)
  mixed = s1_request(m, states_of(c("calibrated", "uncalibrated")), qs, list(provider = p))
  expect_identical(mixed$calibrated, FALSE)
})

test_that("a score the wire parser fills in passes the dispatch check (IC-74)", {
  # two-decimal probabilities may sum below 1 (report 04a); the parser's expected level of a
  # missing score and the check of a given score use the same normalised expectation
  rounded = list(`0` = 0, `1` = 0, `2` = 0, `3` = 0, `4` = 0.98)
  local_fake_transfers(function(body) {
    rate = switch(body$state$text,
      filled = list(type = "score", probabilities = rounded),
      given = list(type = "score", score = 3.96, probabilities = rounded),
      wrong = list(type = "score", score = 3.5, probabilities = rounded))
    list(body = list(model = "wire-1.0", answers = list(rate = rate),
                     usage = list(input_tokens = 10L, output_tokens = 2L)))
  })
  p = wire_provider()
  qs = list(rate = list(type = "score", instructions = "How much?",
                        criteria = list("a", "b", "c", "d", "e")))
  res = s1_request(s1_model(p), states_of(c("filled", "given", "wrong")), qs, list(provider = p))
  expect_identical(res$answers[[1]]$rate$score, 4)
  expect_identical(res$answers[[2]]$rate$score, 3.96)
  expect_null(res$answers[[3]])
  expect_s3_class(res$conditions[[3]], "gptr_error_s1_response")
  expect_identical(res$errors$index, 3L)
  # what the parser makes of the wire answer is exactly what the dispatch check accepts
  sc = qs$rate
  parsed = s1_parse_answer(list(type = "score", probabilities = rounded), sc)
  expect_identical(s1_check_answer(parsed, sc, function(msg) stop(msg)), parsed)
})

test_that("a System 1 call inside a pump never runs another run's FIFO tool (IC-57)", {
  local_fake_transfers(function(body) ok_reply(body), delay = 0.02)
  p = wire_provider()
  seen = new.env(parent = emptyenv())
  seen$res = NULL
  seen$inside = FALSE
  seen$tool = NA
  tool = reactor_enqueue_tool("r_other", function() {
    seen$tool = seen$inside
  })
  withr::defer(reactor_cancel(tool))
  timer = reactor_timer(reactor_now(), function() {
    seen$inside = TRUE
    seen$res = s1_request(s1_model(p), states_of(c("a", "b", "c")), noul_questions(),
                          list(provider = p))
    seen$inside = FALSE
  })
  withr::defer(reactor_cancel(timer))
  reactor_pump(until = function() !is.null(seen$res) && !is.na(seen$tool), timeout = 30)
  expect_false(seen$tool)
  expect_length(seen$res$answers, 3L)
  expect_null(seen$res$errors)
})

# ---- Task 9: builtin:system1 and peter() end to end (NS-4, NS-5) --------------------------------
# INFRA-18's acceptance tests (architecture 6.18) are in test-s1-route.R, the file P24's INFRA
# suite runs.

abstracts20 = function() {
  x = c(
    "A randomised controlled trial of metformin in 240 adults.",
    "A retrospective cohort of 12,000 statin users.",
    "Participants were randomised to exercise or usual care.",
    "A case report of a rare hepatic tumour.",
    "A double-blind randomised trial of vitamin D.",
    "A cross-sectional survey of sleep in nurses.",
    "A cluster randomised trial of hand washing.",
    "A systematic review of mindfulness programmes.",
    "Patients were randomised to two surgical techniques.",
    "A prospective cohort of smokers over 20 years.",
    "A randomised crossover trial of two inhalers.",
    "A qualitative interview study of caregivers.",
    "A pragmatic randomised trial in 40 practices.",
    "A case-control study of pesticide exposure.",
    "An open-label randomised trial of early feeding.",
    "A registry analysis of hip replacements.",
    "A non-inferiority randomised trial of antibiotics.",
    "An ecological study of air pollution.",
    "A stepped-wedge randomised trial of a sepsis protocol.",
    "A diagnostic accuracy study of an antigen test."
  )
  names(x) = sprintf("a%02d", seq_along(x))
  x
}

rct_judge = function(name = "judge", .env = parent.frame()) {
  local_fake_provider(function(state, question) {
    text = paste(unlist(state), collapse = " ")
    if (grepl("randomised", text, fixed = TRUE)) 0.93 else 0.07
  }, name = name, type = "classifier", .env = .env)
}

test_that("builtin:system1 registers the providers, adapters, route, section and service", {
  tp = registry_get("provider", "typesafe")
  expect_identical(tp$api, "typesafe-system-one")
  expect_identical(tp$base_url, "https://api.typesafe.ai/v1/")
  expect_identical(tp$auth, "TYPESAFE_API_KEY")
  expect_identical(tp$type, "classifier")
  expect_identical(tp$rate, list(requests_per_s = 40, tokens_per_s = 1e5))
  expect_true("jev-latest" %in% vapply(tp$models, function(m) m$id, ""))
  expect_identical(ratelimit_static("typesafe"), list(requests_per_s = 40, tokens_per_s = 1e5))
  expect_identical(registry_get("provider", "openrouter-jev")$api, "typesafe-system-one")
  expect_identical(registry_get("adapter", "typesafe-system-one")$transport, "http_json")
  expect_true(is.function(registry_get("adapter", "s1-emulate")$classify$run))
  # IC-74 (07-local-ollama.md section 3; D-120 item 11): the native Ollama decision adapter
  ol = registry_get("adapter", "ollama-system-one")
  expect_identical(ol$transport, "http_json")
  expect_true(is.function(ol$classify$build) && is.function(ol$classify$parse))
  routes = Filter(function(r) identical(r$name, "classifier"), registry_all("route"))
  expect_length(routes, 1L)
  expect_identical(routes[[1]]$order, 10)
  sec = registry_get("prompt_section", "system1")
  expect_identical(sec$tier, "T0")
  expect_identical(sec$order, 650L)
  expect_identical(sec$budget, 150L)
  expect_true(ext_service_has("s1.decide"))
  jev = model_resolve("jev")
  expect_identical(jev$provider, "typesafe")
  expect_identical(jev$type, "classifier")
})

test_that("the system1 section is architecture 7.3 verbatim and shown only when usable", {
  pb = json_decode(read_utf8(testthat::test_path("fixtures", "bench",
                                                 "prefix-baseline.json"))$text)
  st = Filter(function(x) identical(x$name, "system1"), pb$standins$sections)[[1]]
  expect_identical(s1_section_body, st$text)
  expect_false(grepl("[^ -~]", s1_section_body))
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  local_gptr_options(system1 = NULL)
  expect_null(s1_section_text(NULL))
  local_gptr_options(system1 = "judge/judge-s1")
  expect_identical(s1_section_text(NULL), s1_section_body)
  # IC-74 (07 section 5): a verified local native classifier makes System 1 usable without a
  # TypeSafe key, so the section does not depend on the key alone
  local_gptr_options(system1 = NULL)
  local_mocked_bindings(catalog_local_classifier = function() "ollama/clef-flash")
  expect_identical(s1_section_text(NULL), s1_section_body)
})

test_that("NS-4: if (peter(..., model = judge)) works and creates no session", {
  s1_fresh()
  judge = rct_judge()
  abstract = abstracts20()[["a01"]]
  before = names(live_all())
  included = character()
  if (peter("Is this abstract about a randomised controlled trial?", abstract, model = judge)) {
    included = c(included, "a01")
  }
  expect_identical(included, "a01")
  expect_length(setdiff(names(live_all()), before), 0L)
  req = fake_requests(judge)[[1]]
  expect_identical(req$state, list(abstract = abstract))
  expect_identical(req$question$type, "noul")
  expect_match(req$question$instructions, "The input is in `abstract`.", fixed = TRUE)
})

test_that("NS-4: a vector gives a named decision vector; repeats come from the cache", {
  s1_fresh()
  judge = rct_judge()
  abstracts = abstracts20()
  is_rct = peter("Is this abstract about a randomised controlled trial?", abstracts, model = judge)
  expect_identical(class(is_rct), c("gptr_decision", "gptr_s1", "logical"))
  expect_identical(names(is_rct), names(abstracts))
  expect_identical(sum(is_rct), 10L)
  expect_identical(as.vector(table(is_rct)), c(10L, 10L))
  expect_identical(unname(attr(is_rct, "prob")[1:2]), c(0.93, 0.07))
  expect_identical(attr(is_rct, "meta")$model, "judge-s1-1.0")
  expect_length(fake_requests(judge), 20L)
  again = peter("Is this abstract about a randomised controlled trial?", abstracts, model = judge)
  expect_length(fake_requests(judge), 20L)
  expect_true(all(attr(again, "meta")$cached))
  expect_identical(as.logical(again), as.logical(is_rct))
})

test_that("levels give a gptr_score of expected 0-based levels", {
  s1_fresh()
  local_fake_provider(list(c(0, 0.02, 0.98)), name = "rater", type = "classifier")
  mood = peter("How positive is the review?", c(r1 = "Loved it."), model = "rater/rater-s1",
              levels = c("negative", "neutral", "positive"))
  expect_identical(class(mood), c("gptr_score", "gptr_s1", "numeric"))
  expect_equal(as.double(mood), c(r1 = 1.98))
  expect_identical(attr(mood, "s1_levels"), c("negative", "neutral", "positive"))
})

test_that("NS-4: a data frame split into rows prints the once-per-session s1_split message", {
  s1_fresh()
  local_gptr_options(quiet = FALSE)
  local_once_reset("s1_split")
  local_fake_provider(list(0.9), name = "rows", type = "classifier")
  diagnostics = data.frame(check = c("normality", "variance"), ok = c(TRUE, TRUE))
  msg = expect_message(peter("Is the residual plot acceptable?", diagnostics,
                            model = "rows/rows-s1"),
                       class = "gptr_message_s1_split")
  expect_match(conditionMessage(msg), "I(diagnostics)", fixed = TRUE)
  expect_no_message(peter("Is the residual plot acceptable?", diagnostics, model = "rows/rows-s1"))
  n = 0L
  while (peter("Is the residual plot acceptable?", I(diagnostics), model = "rows/rows-s1")) {
    n = n + 1L
    if (n == 2L) break
  }
  expect_identical(n, 2L)
})

test_that("a piped session gives one state: no turn, a gptr.decision entry, at most 2,000 chars", {
  s1_fresh()
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_fake_provider(list(strrep("The fit converged and the residuals look fine. ", 100)))
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  s = peter("Fit the model", model = "fake/fake-1", envir = new.env())
  turns = s$turns
  done = s |> peter("done?", model = judge)
  expect_s3_class(done, "gptr_decision")
  expect_true(done)
  expect_identical(s$turns, turns)
  entries = session_data(s)$entries
  last = entries[[length(entries)]]
  expect_identical(last$type, "custom")
  expect_identical(last$custom_type, "gptr.decision")
  expect_identical(last$data$question, "done?")
  expect_identical(last$data$type, "noul")
  expect_identical(last$data$n, 1L)
  state = fake_requests(judge)[[1]]$state$session
  expect_lte(nchar(state), 2000L)
  expect_match(state, "^Answer: The fit converged")
})

test_that("System 1 emits a decision event and writes one summary line at top level", {
  s1_fresh()
  local_fake_provider(list(0.9, 0.1), name = "judge", type = "classifier")
  events = new.env()
  events$list = list()
  off = gptr_register(gptr_hook("decision", function(event, ctx) {
    events$list[[length(events$list) + 1L]] = event
    NULL
  }))
  withr::defer(off())
  lines = new.env()
  lines$summary = character()
  s1_local_service("doc.s1_block", function(call, summary) {
    lines$summary = c(lines$summary, summary)
    invisible(NULL)
  })
  d = peter("Q?", c(a = "x", b = "y"), model = "judge/judge-s1")
  expect_length(events$list, 1L)
  expect_identical(events$list[[1]]$n, 2L)
  # `type` stays the event name (contract 4.5); the question type travels as question_type
  expect_identical(events$list[[1]]$type, "decision")
  expect_identical(events$list[[1]]$question_type, "noul")
  expect_identical(lines$summary,
                   paste0("gptr_decision: 1 TRUE / 1 FALSE (judge-s1-1.0, ", Sys.Date(), ")"))
})

test_that("failures: a scalar call signals, a vector gives NA and one s1_errors warning", {
  s1_fresh()
  # the state key is the context label (`one`, or `input` for the call c(...)), so read the value
  local_fake_provider(function(state, question) {
    bad = identical(unlist(state, use.names = FALSE)[1L], "bad")
    if (bad) list(error = "overloaded", status = 529L) else 0.8
  }, name = "flaky", type = "classifier")
  local_gptr_options(s1_rounds = 1L)
  one = "bad"
  expect_error(peter("Q?", one, model = "flaky/flaky-s1"), class = "gptr_error_s1_overloaded")
  seen = new.env()
  out = withCallingHandlers(
    peter("Q?", c("ok", "bad"), model = "flaky/flaky-s1"),
    gptr_warning_s1_errors = function(w) {
      seen$w = w
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(seen$w, "gptr_warning_s1_errors")
  expect_identical(seen$w$errors$class, "gptr_error_s1_overloaded")
  expect_identical(as.logical(out), c(TRUE, NA))
  expect_identical(attr(out, "meta")$errors$index, 2L)
})

test_that("calls above gptr.s1_max_elements fail with a hint to chunk", {
  s1_fresh()
  local_fake_provider(list(0.5), name = "judge", type = "classifier")
  local_gptr_options(s1_max_elements = 5L)
  err = expect_error(peter("Q?", as.character(1:6), model = "judge/judge-s1"),
                     class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "chunks", fixed = TRUE)
})

test_that("replay mode serves cached answers and refuses a miss (IC-47)", {
  s1_fresh()
  spec = gptr_fake_provider(list(0.9), name = "remote", type = "classifier")
  spec$offline = FALSE
  spec$local = TRUE
  # a `local` hint alone is not exempt from the egress acknowledgement (D-099): the provider
  # names a loopback endpoint, as a local server would
  spec$base_url = "http://127.0.0.1:9/v1"
  off = gptr_register(spec)
  withr::defer(off())
  # the process mode is the gptr.replay option (setup.R sets it, and it wins over GPTR_REPLAY)
  local_gptr_options(replay = "live")
  peter("Q?", c(a = "x"), model = "remote/remote-s1")
  local_gptr_options(replay = "replay")
  again = peter("Q?", c(a = "x"), model = "remote/remote-s1")
  expect_true(all(attr(again, "meta")$cached))
  expect_error(peter("Q?", c(b = "new"), model = "remote/remote-s1"),
               class = "gptr_error_not_recorded")
})

test_that("jev without a key fails cleanly: egress first, then no_key; nothing is sent", {
  s1_fresh()
  local_no_network()
  withr::local_envvar(TYPESAFE_API_KEY = "", GPTR_REPLAY = "live",
                      R_USER_CONFIG_DIR = withr::local_tempdir())
  # the process mode is the gptr.replay option (setup.R), which wins over GPTR_REPLAY
  local_gptr_options(replay = "live")
  local_mocked_bindings(secret_lookup = function(name) NULL)
  ticket = "The printer is on fire."
  expect_error(peter("Is it urgent?", ticket, model = jev), class = "gptr_error_egress")
  gptr_config(egress = list(typesafe = "ack"), .scope = "user")
  expect_error(peter("Is it urgent?", ticket, model = jev), class = "gptr_error_no_key")
})

test_that("the gptr_prob() example runs", {
  s1_fresh()
  judge = gptr_fake_provider(list(0.9, 0.2), name = "judge", type = "classifier")
  d = peter("Is this about dogs?", c(a = "A puppy.", b = "A car."), model = judge)
  expect_identical(gptr_prob(d), c(a = 0.9, b = 0.2))
  expect_identical(as.logical(d), c(a = TRUE, b = FALSE))
})

test_that("NS-5: System 1 routes each task to a strong or a cheap System 2 model", {
  s1_fresh()
  local_fake_provider(function(state, question) {
    if (grepl("subtle", state$task, fixed = TRUE)) 0.9 else 0.1
  }, name = "hardness", type = "classifier")
  strong_fake = local_fake_provider(list("strong answer"), name = "fstrong")
  cheap_fake = local_fake_provider(list("cheap answer"), name = "fcheap")
  strong = "fstrong/fstrong-1"
  cheap = "fcheap/fcheap-1"
  tasks = c("Fix the subtle race in the cache.", "Rename a variable.")
  answers = character()
  for (task in tasks) {
    hard = peter("Is this task subtle enough to need the strongest model?", task,
                model = "hardness/hardness-s1")
    res = peter(task, model = if (hard) strong else cheap, mode = auto, envir = new.env())
    answers = c(answers, res$text)
  }
  expect_identical(answers, c("strong answer", "cheap answer"))
  expect_length(fake_requests(strong_fake), 1L)
  expect_length(fake_requests(cheap_fake), 1L)
})

test_that("a provider's static rate of 40 requests per second caps System 1 admission (IC-64)", {
  # the server starts before s1_fresh() moves the working directory into a temporary project
  srv = local_mock_server("systemone")
  s1_fresh()
  spec = gptr_provider("ratetest", api = "typesafe-system-one", base_url = srv$url,
                       type = "classifier", local = TRUE, offline = TRUE,
                       rate = list(requests_per_s = 40, tokens_per_s = 1e5),
                       models = list(list(id = "ratetest-s1", type = "classifier")))
  off = gptr_register(spec)
  withr::defer(off())
  withr::defer(ratelimit_set("ratetest", NULL))
  d = peter("Is it fine?", paste("abstract", 1:100), model = "ratetest/ratetest-s1")
  expect_length(d, 100L)
  log = srv$log()
  expect_identical(nrow(log), 100L)
  t = sort(as.numeric(log$time))
  k = seq_along(t)
  # P04's token bucket holds 40 and refills 40 per second (ambiguity 18): after the first 40,
  # request k starts no earlier than (k - 40) / 40 seconds after the first, so the sustained rate
  # never exceeds 40 per second (0.25 s allowance for clock and logging jitter; a slower machine
  # only makes the requests later, so the bound cannot fail from slowness)
  expect_true(all(t - t[1] >= (k - 40) / 40 - 0.25))
  expect_gte(t[100] - t[1], 1.25)
})
