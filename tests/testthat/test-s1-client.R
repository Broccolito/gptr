# Tests for R/s1-client.R (plan P13): questions, the typesafe-system-one adapter and its wire
# fixtures (Task 3), requests on the reactor (Task 4), builtin:system1 and the classifier route
# through gptr() (Task 9) (contract 7.13, 8.1, 9.3; reports 04 and 04a; IC-74: classify$parse
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
    fx = jev_fixture(case)
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

test_that("the adapter's classify functions pass P02's classifier signature check (IC-74)", {
  # contract 8.1 as amended by IC-74: parse(model, status, headers, body, questions)
  spec = gptr_adapter("typesafe-system-one", transport = "http_json",
                      classify = list(build = s1_typesafe_build, parse = s1_typesafe_parse))
  expect_s3_class(spec, "gptr_adapter")
  local({
    local_s1_adapter()
    expect_false(is.null(registry_get("adapter", "typesafe-system-one")))
  })
})

test_that("responses parse by name: choice probabilities come back in request order", {
  fx = jev_fixture("choice")
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

test_that("a multi-question response parses noul, choice and score answers together", {
  fx = jev_fixture("multi")
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
  fx = jev_fixture("extra-fields")
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
    fx = jev_fixture(case)
    cnd = s1_typesafe_parse(jev_model(), as.integer(fx$status), list(), json_encode(fx$response),
                            q)
    expect_s3_class(cnd, cases[[case]])
    expect_s3_class(cnd, "gptr_error_s1")
    expect_identical(cnd$status, as.integer(fx$status))
    expect_identical(cnd$model, "jev-latest")
  }
  body401 = json_encode(jev_fixture("error-401")$response)
  e401 = s1_typesafe_parse(jev_model(), 401L, list(), body401, q)
  expect_match(conditionMessage(e401), "Cannot authenticate", fixed = TRUE)
  expect_identical(e401$error_type, "authentication_error")
  body422 = json_encode(jev_fixture("error-422")$response)
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
