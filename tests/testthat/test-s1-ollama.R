# Tests for R/s1-ollama.R (plan P13, the IC-74 task after Task 8; 07-local-ollama.md sections 2-6):
# the ollama-system-one adapter (request, limits, images, canonical answers), per-server
# admission, preparation and the local-only preflight on the classifier route, the cache identity
# and replay with the identity frozen with the recorded answers. Offline: discovery answers are
# synthetic (P05's catalog_http_request() is replaced, as in P05's own tests), transfers are
# replaced or go to P01's loopback mock server, and no Ollama server is ever contacted.

source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

# ---- helpers ------------------------------------------------------------------------------------

# Ollama's confidence of a probability vector: 1 - H(p) / log(N); zero probabilities add nothing
ent_conf = function(p) {
  q = p[p > 0]
  1 - (-sum(q * log(q))) / log(length(p))
}

png_bytes = function(n = 8L) {
  as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, seq_len(n) %% 256L))
}
jpeg_bytes = function(n = 8L) as.raw(c(0xff, 0xd8, 0xff, 0xe0, seq_len(n) %% 256L))
webp_bytes = function(n = 8L) {
  c(charToRaw("RIFF"), as.raw(c(20, 0, 0, 0)), charToRaw("WEBP"), as.raw(seq_len(n) %% 256L))
}
img = function(data, mime = "image/png") list(data = data, mime = mime)
b64 = function(raw) gsub("[\r\n]", "", jsonlite::base64_enc(raw))

states_of = function(texts) lapply(texts, function(t) list(text = t))
noul_q = function() list(answer = list(type = "noul", instructions = "Is it a dog?"))

# A native Clef record as P05's catalog describes it (07 section 2), with overrides
clef_record = function(...) {
  base = list(provider = "ollama", id = "clef-flash", ref = "ollama/clef-flash",
              type = "classifier", api = "ollama-system-one",
              decision = list(types = c("noul", "choice", "score"), images = TRUE,
                              server_min = "0.35.1", max_questions = 64L, max_options = 26L,
                              max_request_bytes_text = 65536L,
                              max_request_bytes_images = 33554432L, max_active = 1L))
  utils::modifyList(base, list(...))
}

# The installed models of a synthetic native Ollama server: /api/tags and /api/show answers
ollama_models = function(digest = strrep("2", 64)) {
  list(
    `clef-flash:latest` = list(
      tag = list(name = "clef-flash:latest", model = "clef-flash:latest", digest = digest,
                 details = list(format = "gguf", family = "clef", quantization_level = "Q8_0")),
      show = list(capabilities = list("decision"), parameters = "num_ctx 16384",
                  details = list(format = "gguf", family = "clef", quantization_level = "Q8_0"),
                  model_info = list(clef.context_length = 262144),
                  projector_info = list(clip.has_vision_encoder = TRUE))),
    `qwen3:1.7b` = list(
      tag = list(name = "qwen3:1.7b", model = "qwen3:1.7b", digest = strrep("1", 64),
                 details = list(format = "gguf", family = "qwen3")),
      show = list(capabilities = list("completion", "tools"), parameters = "num_ctx 8192",
                  details = list(format = "gguf", family = "qwen3")))
  )
}

# Synthetic native discovery for the calling test (07 section 2): /api/version, /api/tags and
# /api/show answered in process; no server runs and no request leaves the process. Discovered
# models and their private evidence are forgotten before and after the test.
local_ollama_discovery = function(models = ollama_models(), version = "0.35.1",
                                  .env = parent.frame()) {
  srv = new.env(parent = emptyenv())
  srv$models = models
  srv$version = version
  srv$down = FALSE
  srv$calls = character()
  answer = function(x) list(status = 200L, headers = list(), body = charToRaw(json_encode(x)))
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE), envir = .env)
  testthat::local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_request = function(url, method = "GET", headers = list(), body = NULL, ...) {
      srv$calls = c(srv$calls, paste(method, url))
      if (srv$down) {
        gptr_abort("Could not reach the fixture: connection refused", c("network", "provider"),
                   provider = "catalog", status = NA_integer_, curl_code = 7L)
      }
      if (endsWith(url, "/api/version")) return(answer(list(version = srv$version)))
      if (endsWith(url, "/api/tags")) {
        return(answer(list(models = unname(lapply(srv$models, function(m) m$tag)))))
      }
      if (endsWith(url, "/api/show") && identical(method, "POST")) {
        m = srv$models[[json_decode(body)$model]]
        if (!is.null(m)) return(answer(m$show))
      }
      list(status = 404L, headers = list(), body = raw())
    },
    .env = .env
  )
  srv
}

# A valid wire answer of the documented decision API for one question: noul 0.9; a choice gives
# its first option 0.7 and shares 0.3; a score gives its top level 0.6 and shares 0.4
ollama_answer = function(q) {
  if (identical(q$type, "choice")) {
    keys = names(q$criteria)
    p = stats::setNames(c(0.7, rep(0.3 / (length(keys) - 1), length(keys) - 1)), keys)
    return(list(type = "choice", choice = keys[[1]], confidence = ent_conf(p),
                probabilities = as.list(rev(p))))
  }
  if (identical(q$type, "score")) {
    k = length(q$criteria)
    p = stats::setNames(c(rep(0.4 / (k - 1), k - 1), 0.6), as.character(seq_len(k) - 1L))
    return(list(type = "score", score = sum((seq_len(k) - 1) * p), confidence = ent_conf(p),
                legend = stats::setNames(q$criteria, names(p)), probabilities = as.list(rev(p))))
  }
  list(type = "noul", noul = 0.9)
}

ollama_reply = function(body) {
  list(body = list(model = body$model, answers = lapply(body$questions, ollama_answer),
                   usage = list(input_tokens = 40L, output_tokens = length(body$questions))))
}

# Replace System 1 HTTP transfers for the calling test: `respond(body)` gives list(status, body,
# headers); every transfer is recorded with its spec, its decoded body and its start time
local_ollama_transfers = function(respond = ollama_reply, delay = 0.01, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$specs = list()
  log$bodies = list()
  log$started = numeric()
  log$active = 0L
  log$max_active = 0L
  testthat::local_mocked_bindings(s1_http = function(spec, provider, on_done, on_fail) {
    log$active = log$active + 1L
    log$max_active = max(log$max_active, log$active)
    log$specs[[length(log$specs) + 1L]] = spec
    log$started = c(log$started, reactor_now())
    body = json_decode(spec$body)
    log$bodies[[length(log$bodies) + 1L]] = body
    reply = respond(body)
    reactor_timer(reactor_now() + delay, function() {
      log$active = log$active - 1L
      status = reply$status %||% 200L
      if (status < 300L) {
        on_done(status, reply$headers %||% list(), json_encode(reply$body))
      } else {
        on_fail(gptr_condition(paste("HTTP", status), c("overloaded", "provider"), "error",
                               list(status = status)))
      }
    })
  }, .env = .env)
  log
}

# ---- the request --------------------------------------------------------------------------------

test_that("the endpoint is /v1/systemone on the configured origin, never a doubled /v1", {
  ep = "http://127.0.0.1:11434/v1/systemone"
  for (base in c("http://127.0.0.1:11434/v1", "http://127.0.0.1:11434/v1/",
                 "http://127.0.0.1:11434", "http://127.0.0.1:11434/",
                 "HTTP://127.0.0.1:11434/v1?x=1#f")) {
    expect_identical(s1_ollama_endpoint(base), ep)
  }
  expect_identical(s1_ollama_endpoint("http://localhost:8080/proxy/v1"),
                   "http://localhost:8080/proxy/v1/systemone")
  expect_identical(s1_ollama_endpoint("https://lab.example.invalid/ollama"),
                   "https://lab.example.invalid/ollama/v1/systemone")
  for (bad in list(NULL, NA_character_, "", "ftp://127.0.0.1/v1", "127.0.0.1:11434",
                   c("http://a.invalid", "http://b.invalid"))) {
    expect_null(s1_ollama_endpoint(bad))
  }
  # the route keys answers by the same endpoint, from the built-in record or from settings
  expect_identical(s1_target("ollama/clef-flash")$endpoint, ep)
  local_settings(providers = list(ollama = list(base_url = "http://127.0.0.1:11434")))
  expect_identical(s1_target("ollama/clef-flash")$endpoint, ep)
})

test_that("a request sends the state, the questions and raw base64 images, never a key", {
  q = list(seen = list(type = "noul", instructions = "Is it a dog?"),
           kind = list(type = "choice", instructions = "Which?",
                       criteria = list(dog = NULL, cat = "A cat")),
           mood = list(type = "score", instructions = "How happy?", criteria = list("sad", "glad")))
  key = structure(list(id = "TYPESAFE_API_KEY#000000", name = "TYPESAFE_API_KEY", fp = "000000",
                       origin = "https://api.typesafe.ai"), class = "gptr_secret")
  pics = list(img(png_bytes()), img(jpeg_bytes(), "image/jpeg"), img(webp_bytes(), "image/webp"))
  spec = s1_ollama_build(clef_record(), list(text = "a"), q,
                         list(base_url = "http://127.0.0.1:11434/v1", credential = key,
                              images = pics))
  expect_identical(spec$url, "http://127.0.0.1:11434/v1/systemone")
  expect_identical(spec$method, "POST")
  expect_identical(spec$headers$`Content-Type`, "application/json")
  expect_false(any(tolower(names(spec$headers)) %in% c("authorization", "x-api-key", "api-key")))
  expect_false(grepl("Bearer|TYPESAFE", spec$body))
  body = json_decode(spec$body)
  expect_identical(names(body), c("model", "state", "questions", "images"))
  expect_identical(body$model, "clef-flash")
  expect_identical(body$state, list(text = "a"))
  expect_identical(body$questions, json_decode(json_encode(q)))
  # raw base64 strings in list order: never URLs or data URLs
  expect_identical(body$images, lapply(pics, function(p) b64(p$data)))
  expect_false(any(grepl("^data:|://", unlist(body$images))))
  expect_identical(spec$first_byte_timeout, s1_ollama_first_byte)
  # no images, no images field; text and arrays are states too
  plain = s1_ollama_build(clef_record(), "Just text.", q["seen"],
                          list(base_url = "http://127.0.0.1:11434"))
  expect_identical(names(json_decode(plain$body)), c("model", "state", "questions"))
  expect_identical(json_decode(plain$body)$state, "Just text.")
  arr = s1_ollama_build(clef_record(), list(1, 2), q["seen"],
                        list(base_url = "http://127.0.0.1:11434"))
  expect_identical(json_decode(arr$body)$state, list(1L, 2L))
  # the synthetic fixtures are exactly what the adapter sends for their inputs
  for (nm in c("noul", "choice", "score", "image")) {
    fx = wire_fixture(nm, "ollama")
    images = lapply(fx$request$images, function(s) img(jsonlite::base64_dec(s)))
    sent = s1_ollama_build(clef_record(), fx$request$state, fx$request$questions,
                           list(base_url = "http://127.0.0.1:11434/v1", images = images))
    expect_identical(json_decode(sent$body), fx$request)
  }
})

test_that("requests outside the adapter's limits fail explicitly before anything is sent", {
  base = list(base_url = "http://127.0.0.1:11434/v1")
  noul = function(k) {
    stats::setNames(rep(list(list(type = "noul", instructions = "Q?")), k), paste0("q", seq_len(k)))
  }
  build = function(questions, model = clef_record(), state = list(text = "a"), opts = base) {
    s1_ollama_build(model, state, questions, opts)
  }
  expect_silent(build(noul(64)))
  expect_error(build(noul(65)), class = "gptr_error_invalid_argument")
  expect_error(build(list()), class = "gptr_error_invalid_argument")
  # a model's decision record lowers an adapter limit, never raises it
  expect_error(build(noul(3), clef_record(decision = list(max_questions = 2L))),
               class = "gptr_error_invalid_argument")
  expect_error(build(noul(65), clef_record(decision = list(max_questions = 100L))),
               class = "gptr_error_invalid_argument")
  choice = function(k) {
    opts = stats::setNames(rep(list(NULL), k), paste0("o", seq_len(k)))
    list(answer = list(type = "choice", instructions = "Which?", criteria = opts))
  }
  expect_silent(build(choice(26)))
  expect_error(build(choice(27)), class = "gptr_error_invalid_argument")
  expect_error(build(choice(1)), class = "gptr_error_invalid_argument")
  expect_error(build(list(answer = list(type = "score", instructions = "How?",
                                        criteria = list("low")))),
               class = "gptr_error_invalid_argument")
  expect_error(build(list(answer = list(type = "bool", instructions = "Q?"))),
               class = "gptr_error_invalid_argument")
  expect_error(build(choice(2), clef_record(decision = list(types = "noul"))),
               class = "gptr_error_invalid_argument")
  # bodies: 64 KiB of text, 32 MiB with images; a model's record may lower them
  err = expect_error(build(noul(1), state = list(text = strrep("x", 70000))),
                     class = "gptr_error_s1_validation")
  expect_match(conditionMessage(err), "65536 bytes", fixed = TRUE)
  expect_silent(build(noul(1), state = list(text = strrep("x", 60000))))
  expect_silent(build(noul(1), state = list(text = strrep("x", 70000)),
                      opts = c(base, list(images = list(img(png_bytes()))))))
  # 408 image bytes are 544 bytes of base64: within a limit of 600, but not with the rest
  tight = clef_record(decision = list(max_request_bytes_images = 600L))
  big_image = c(base, list(images = list(img(png_bytes(400)))))
  err = expect_error(build(noul(1), tight, opts = big_image), class = "gptr_error_s1_validation")
  expect_match(conditionMessage(err), "600 bytes", fixed = TRUE)
  # an empty state is refused; no valid base URL is not available
  for (st in list(NULL, "", list(), character())) {
    expect_error(build(noul(1), state = st), class = "gptr_error_s1_validation")
  }
  expect_error(build(noul(1), opts = list(base_url = "ftp://127.0.0.1/v1")),
               class = "gptr_error_not_available")
})

test_that("images must be PNG, JPEG or WebP bytes that the model accepts", {
  base = list(base_url = "http://127.0.0.1:11434/v1")
  build = function(images, model = clef_record()) {
    s1_ollama_build(model, list(text = "a"), noul_q(), c(base, list(images = images)))
  }
  bad = list(
    gif = list(img(c(charToRaw("GIF89a"), as.raw(1:8)), "image/gif")),
    video = list(img(as.raw(c(0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70)), "video/mp4")),
    mislabelled = list(img(jpeg_bytes(), "image/png")),
    text = list(img(charToRaw("not an image at all"), "image/png")),
    url = list(list(data = "https://example.invalid/cat.png", mime = "image/png")),
    data_url = list(list(data = paste0("data:image/png;base64,", b64(png_bytes())),
                         mime = "image/png")),
    path = list("cat.png"),
    empty = list(img(raw(0))),
    no_mime = list(list(data = png_bytes())),
    not_list = "cat.png"
  )
  for (b in bad) expect_error(build(b), class = "gptr_error_invalid_argument")
  # a model whose evidence shows no vision takes no images; its text questions still go
  blind = clef_record(decision = list(images = FALSE))
  expect_error(build(list(img(png_bytes())), blind), class = "gptr_error_invalid_argument")
  expect_silent(s1_ollama_build(blind, list(text = "a"), noul_q(), base))
  expect_silent(build(list(img(png_bytes()), img(webp_bytes(), "image/webp"))))
})

# ---- the answers --------------------------------------------------------------------------------

test_that("answers of all three types become canonical records once, in request order", {
  for (nm in c("noul", "choice", "score", "image")) {
    fx = wire_fixture(nm, "ollama")
    res = s1_ollama_parse(clef_record(), 200L, list(), json_encode(fx$response),
                          fx$request$questions)
    expect_identical(res$model_version, "clef-flash")
    expect_identical(res$usage, list(input = as.double(fx$response$usage$input_tokens),
                                     output = 1))
    expect_identical(res$request_id, NA_character_)
    # the common dispatch check accepts the canonical records as they are
    expect_identical(s1_check_answers(res$answers, fx$request$questions), res$answers)
  }
  parse = function(nm) {
    fx = wire_fixture(nm, "ollama")
    s1_ollama_parse(clef_record(), 200L, list(), json_encode(fx$response),
                    fx$request$questions)$answers$answer
  }
  expect_identical(parse("noul"), list(type = "noul", prob = 0.9595))
  # shuffled probability keys come back in request order; the wire confidence is kept
  expect_identical(parse("choice"),
                   list(type = "choice", choice = "dog",
                        probabilities = c(dog = 0.9411, cat = 0.0382, bird = 0.0207, other = 0),
                        confidence = 0.810923))
  # a fractional score stays fractional, with the request's legend
  expect_identical(parse("score"),
                   list(type = "score", score = 1.9094,
                        probabilities = c(`0` = 0.0082, `1` = 0.0742, `2` = 0.9176),
                        confidence = 0.716651,
                        legend = c(`0` = "Very negative", `1` = "Neutral", `2` = "Very positive")))
  expect_identical(parse("image")$probabilities, c(red = 0.0272, blue = 0.9728))
  # several questions: answers in question order whatever order the server used
  qs = list(kind = wire_fixture("choice", "ollama")$request$questions$answer,
            ok = wire_fixture("noul", "ollama")$request$questions$answer,
            tone = wire_fixture("score", "ollama")$request$questions$answer)
  wire = list(tone = wire_fixture("score", "ollama")$response$answers$answer,
              ok = wire_fixture("noul", "ollama")$response$answers$answer,
              kind = wire_fixture("choice", "ollama")$response$answers$answer)
  res = s1_ollama_parse(clef_record(), 200L, list(),
                        json_encode(list(model = "clef-flash:latest", answers = wire)), qs)
  expect_identical(names(res$answers), c("kind", "ok", "tone"))
  # usage the server did not report stays unknown
  expect_identical(res$usage, list(input = NA_real_, output = NA_real_))
  expect_identical(res$model_version, "clef-flash:latest")
})

test_that("malformed or inconsistent answers are refused, never repaired", {
  qs = list(pick = list(type = "choice", instructions = "Which?",
                        criteria = list(dog = NULL, cat = NULL)),
            rate = list(type = "score", instructions = "How?",
                        criteria = list("low", "mid", "high")),
            ok = list(type = "noul", instructions = "Ok?"))
  pd = c(dog = 0.8, cat = 0.2)
  pr = c(`0` = 0.1, `1` = 0.3, `2` = 0.6)
  good = list(pick = list(type = "choice", choice = "dog", confidence = ent_conf(pd),
                          probabilities = as.list(pd)),
              rate = list(type = "score", score = sum(0:2 * pr), confidence = ent_conf(pr),
                          legend = list(`0` = "low", `1` = "mid", `2` = "high"),
                          probabilities = as.list(pr)),
              ok = list(type = "noul", noul = 0.3))
  parse = function(answers, model = "clef-flash") {
    s1_ollama_parse(clef_record(), 200L, list(),
                    json_encode(list(model = model, answers = answers,
                                     usage = list(input_tokens = 9, output_tokens = 3))), qs)
  }
  with = function(id, field, value) {
    a = good
    a[[id]][field] = list(value)
    a
  }
  without = function(id, field) {
    a = good
    a[[id]][[field]] = NULL
    a
  }
  res = parse(good)
  expect_identical(names(res$answers), names(qs))
  expect_identical(res$answers$rate$score, 1.5)
  bad = list(
    missing_answer = good[c("pick", "rate")],
    extra_answer = c(good, list(more = list(type = "noul", noul = 0.5))),
    wrong_type = with("ok", "type", "choice"),
    noul_range = with("ok", "noul", 1.2),
    noul_text = with("ok", "noul", "0.3"),
    noul_missing = without("ok", "noul"),
    unknown_choice = with("pick", "choice", "bird"),
    unsupported_choice = with("pick", "choice", "cat"),
    missing_option = with("pick", "probabilities", list(dog = 1)),
    extra_option = with("pick", "probabilities", list(dog = 0.8, cat = 0.1, bird = 0.1)),
    no_sum = with("pick", "probabilities", list(dog = 0.5, cat = 0.2)),
    negative = with("pick", "probabilities", list(dog = 1.1, cat = -0.1)),
    empty_map = with("pick", "probabilities", json_obj()),
    no_map = without("pick", "probabilities"),
    confidence_range = with("pick", "confidence", 1.5),
    # Jev's peak formula is not Ollama's entropy formula (07 section 3)
    jev_confidence = with("pick", "confidence", s1_confidence_choice(pd)),
    score_range = with("rate", "score", 2.5),
    score_mismatch = with("rate", "score", 0.5),
    legend_keys = with("rate", "legend", list(`1` = "low", `2` = "mid", `3` = "high")),
    legend_values = with("rate", "legend", list(`0` = 1, `1` = 2, `2` = 3))
  )
  for (nm in names(bad)) {
    expect_s3_class(parse(bad[[nm]]), "gptr_error_s1_response")
  }
  # an answer from another model, a body without answers, a body that is not JSON
  other = expect_s3_class(parse(good, model = "clef:latest"), "gptr_error_s1_response")
  expect_match(conditionMessage(other), "clef:latest", fixed = TRUE)
  expect_s3_class(s1_ollama_parse(clef_record(), 200L, list(), "{\"model\": \"clef-flash\"}", qs),
                  "gptr_error_s1_response")
  expect_s3_class(s1_ollama_parse(clef_record(), 200L, list(), "<html>", qs),
                  "gptr_error_s1_response")
  # a missing confidence is Ollama's own formula, never Jev's
  conf = parse(without("pick", "confidence"))$answers$pick$confidence
  expect_equal(conf, ent_conf(pd))
  expect_false(isTRUE(all.equal(conf, s1_confidence_choice(pd))))
  # zero probabilities contribute no entropy; a tie keeps the request order
  sure = with("pick", "probabilities", list(cat = 0, dog = 1))
  sure$pick$confidence = 1
  expect_identical(parse(sure)$answers$pick$probabilities, c(dog = 1, cat = 0))
  tie = with("pick", "probabilities", list(cat = 0.5, dog = 0.5))
  tie$pick$confidence = 0
  expect_identical(parse(tie)$answers$pick$choice, "dog")
  tie$pick$choice = "cat"
  expect_identical(parse(tie)$answers$pick$choice, "cat")
  tie$pick$choice = NULL
  expect_identical(parse(tie)$answers$pick$choice, "dog")
  # error bodies by status ({"error": "..."}); 5xx is retryable
  for (st in c(400L, 404L, 413L)) {
    expect_s3_class(s1_ollama_parse(clef_record(), st, list(), "{\"error\": \"bad\"}", qs),
                    "gptr_error_s1_validation")
  }
  e = s1_ollama_parse(clef_record(), 500L, list(), "{\"error\": \"processing failed\"}", qs)
  expect_s3_class(e, "gptr_error_s1_overloaded")
  expect_match(conditionMessage(e), "processing failed", fixed = TRUE)
  fx = wire_fixture("error-400", "ollama")
  e = s1_ollama_parse(clef_record(), fx$status, list(), json_encode(fx$response), qs)
  expect_match(conditionMessage(e), "not URLs", fixed = TRUE)
})

test_that("sums, choices and scores are checked at Ollama's four-decimal rounding", {
  # Ollama rounds probabilities and scores to four decimals: each value is off by at most
  # 5e-5, so TypeSafe's two-decimal slack (0.13 on a 26-level sum) would let bad answers through
  lv = as.character(0:25)
  q = list(rate = list(type = "score", instructions = "How?",
                       criteria = as.list(paste("level", lv))),
           pick = list(type = "choice", instructions = "Which?",
                       criteria = list(a = NULL, b = NULL, c = NULL)))
  uni = stats::setNames(rep(round(1 / 26, 4), 26), lv)
  pc = c(a = 0.5, b = 0.4999, c = 0.0001)
  good = list(rate = list(type = "score", score = 12.5, confidence = 0,
                          probabilities = as.list(uni)),
              pick = list(type = "choice", choice = "a", confidence = ent_conf(pc),
                          probabilities = as.list(pc)))
  parse = function(answers) {
    s1_ollama_parse(clef_record(), 200L, list(),
                    json_encode(list(model = "clef-flash", answers = answers)), q)
  }
  with = function(id, field, value) {
    a = good
    a[[id]][field] = list(value)
    a
  }
  # rounded values that sum to 1.001 over 26 levels, a score within the rounding of its
  # expectation and a choice tied within the rounding are answers
  res = parse(good)
  expect_identical(res$answers$rate$score, 12.5)
  expect_identical(s1_check_answers(res$answers, q), res$answers)
  expect_identical(parse(with("rate", "score", 12.51))$answers$rate$score, 12.51)
  expect_identical(parse(with("pick", "choice", "b"))$answers$pick$choice, "b")
  # outside the rounding they are refused (each with the confidence its probabilities give)
  pick = function(p, choice) {
    a = good
    a$pick = list(type = "choice", choice = choice, confidence = ent_conf(p / sum(p)),
                  probabilities = as.list(p))
    a
  }
  bad = list(
    score_far = with("rate", "score", 14),
    score_near = with("rate", "score", 12.53),
    scaled_sum = with("rate", "probabilities", as.list(round(uni * 0.9, 4))),
    choice_sum = pick(c(a = 0.5, b = 0.49, c = 0.0002), "a"),
    unsupported = pick(c(a = 0.5, b = 0.4998, c = 0.0002), "b")
  )
  for (nm in names(bad)) {
    expect_s3_class(parse(bad[[nm]]), "gptr_error_s1_response")
  }
})

# ---- requests on the reactor --------------------------------------------------------------------

test_that("a prepared Clef answers on the reactor without a key, one request at a time", {
  local_ollama_discovery()
  model = s1_prepare("ollama/clef-flash")
  expect_identical(model$digest, strrep("2", 64))
  local_mocked_bindings(s1_credential = function(provider) stop("a credential was looked up"))
  log = local_ollama_transfers()
  res = s1_request(model, states_of(c("a", "b", "c", "a")), noul_q(),
                   list(provider = provider_get("ollama"), images = list(img(png_bytes()))))
  expect_length(log$specs, 3L)
  expect_identical(log$max_active, 1L)
  urls = vapply(log$specs, function(s) s$url, "")
  expect_true(all(urls == "http://127.0.0.1:11434/v1/systemone"))
  hdr = unlist(lapply(log$specs, function(s) tolower(names(s$headers))))
  expect_false(any(hdr %in% c("authorization", "x-api-key", "api-key")))
  expect_true(all(vapply(log$bodies, function(b) identical(b$images, list(b64(png_bytes()))), NA)))
  expect_identical(res$answers[[4]]$answer, list(type = "noul", prob = 0.9))
  expect_identical(res$engine, "ollama")
  expect_identical(res$calibrated, NA)
  expect_identical(res$model_version, "clef-flash")
  expect_identical(res$provenance,
                   list(provider = "ollama", api = "ollama-system-one", execution = "native",
                        locality = "local", digest = strrep("2", 64), server_version = "0.35.1",
                        calibration_provenance = NULL))
  expect_identical(res$usage$input, 120)
  expect_equal(res$usage$cost, 0)
  # an overflowing state fails alone; the other states are answered
  big = s1_request(model, states_of(c("short", strrep("x", 70000))), noul_q(),
                   list(provider = provider_get("ollama")))
  expect_identical(big$answers[[1]]$answer$prob, 0.9)
  expect_s3_class(big$conditions[[2]], "gptr_error_s1_validation")
  expect_length(log$specs, 4L)
})

test_that("per-server admission holds one request at a time across calls (IC-74)", {
  local_ollama_discovery()
  model = s1_prepare("ollama/clef-flash")
  log = local_ollama_transfers(delay = 0.02)
  origin = "http://127.0.0.1:11434"
  expect_identical(s1_slot_used(origin), 0L)
  # another call holds the server's only slot for 0.3 s
  s1_slot_shift(origin, 1L)
  t0 = reactor_now()
  reactor_timer(t0 + 0.3, function() s1_slot_shift(origin, -1L))
  res = s1_request(model, states_of(c("a", "b")), noul_q(), list(provider = provider_get("ollama")))
  expect_null(res$errors)
  expect_gte(min(log$started) - t0, 0.29)
  expect_identical(log$max_active, 1L)
  expect_identical(s1_slot_used(origin), 0L)
  # a transfer that cannot start gives its slot back
  local_mocked_bindings(s1_http = function(...) stop("no transfer"))
  expect_error(s1_request(model, states_of("z"), noul_q(), list(provider = provider_get("ollama"))),
               "no transfer")
  expect_identical(s1_slot_used(origin), 0L)
})

test_that("a native Ollama model without max_active still gets one request per server", {
  local_ollama_discovery()
  s1_prepare("ollama/clef-flash")
  # a provider spec whose Clef has no decision record: P05's preflight passes against the
  # discovery evidence and adds none, so the default is Ollama's (07 section 2), not the global cap
  spec = gptr_provider("ollama", api = "openai-completions", base_url = "http://127.0.0.1:11434/v1",
                       local = TRUE, models = list(list(id = "clef-flash", type = "classifier",
                                                        api = "ollama-system-one")))
  model = s1_preflight(s1_model(spec), spec)
  expect_identical(model$digest, strrep("2", 64))
  expect_null(model$decision$max_active)
  local_gptr_options(s1_max_active = 8L)
  expect_equal(s1_active_cap(model), 1)
  origin = "http://127.0.0.1:11434"
  expect_equal(s1_gate(model, s1_base_url(spec)), list(key = origin, cap = 1))
  log = local_ollama_transfers(delay = 0.02)
  res = s1_request(model, states_of(letters[1:6]), noul_q(), list(provider = spec))
  expect_null(res$errors)
  expect_length(log$specs, 6L)
  expect_identical(log$max_active, 1L)
  # across calls: the request waits while another call holds the server's slot
  s1_slot_shift(origin, 1L)
  t0 = reactor_now()
  reactor_timer(t0 + 0.3, function() s1_slot_shift(origin, -1L))
  s1_request(model, states_of("g"), noul_q(), list(provider = spec))
  expect_gte(log$started[[7]] - t0, 0.29)
  expect_identical(s1_slot_used(origin), 0L)
  # only an explicit decision record raises it, and the global cap stays an upper bound
  three = model
  three$decision = list(max_active = 3L)
  expect_equal(s1_active_cap(three), 3)
  expect_equal(s1_gate(three, s1_base_url(spec))$cap, 3)
  local_gptr_options(s1_max_active = 2L)
  expect_equal(s1_active_cap(three), 2)
  expect_equal(s1_active_cap(model), 1)
  # a TypeSafe model keeps P04's process-wide admission and no per-server gate
  jev = list(provider = "typesafe", id = "jev-latest", type = "classifier",
             api = "typesafe-system-one")
  expect_null(s1_gate(jev, "https://api.typesafe.ai/v1"))
  expect_equal(s1_active_cap(jev), 2)
})

test_that("a real loopback transfer reaches /v1/systemone with no key (P01's mock server)", {
  fx = wire_fixture("choice", "ollama")
  srv = local_mock_server("json", body = json_encode(fx$response))
  local_settings(providers = list(ollama = list(base_url = paste0(srv$url, "/v1"))))
  disc = local_ollama_discovery()
  model = s1_prepare("ollama/clef-flash")
  expect_identical(disc$calls[1:2], paste0("GET ", srv$url, c("/api/version", "/api/tags")))
  res = s1_request(model, list(fx$request$state), fx$request$questions,
                   list(provider = provider_get("ollama")))
  expect_identical(res$answers[[1]]$answer$choice, "dog")
  log = srv$log()
  expect_identical(nrow(log), 1L)
  expect_identical(log$method, "POST")
  expect_match(log$path, "/v1/systemone$")
  expect_false(grepl("authorization", tolower(log$headers)))
  expect_identical(json_decode(log$body)$questions, fx$request$questions)
})

test_that("an Ollama error body on the reactor fails its element, not retried (error-404)", {
  fx = wire_fixture("error-404", "ollama")
  srv = local_mock_server("json", status = fx$status, body = json_encode(fx$response))
  local_settings(providers = list(ollama = list(base_url = paste0(srv$url, "/v1"))))
  local_ollama_discovery()
  model = s1_prepare("ollama/clef-flash")
  res = s1_request(model, states_of("a"), noul_q(), list(provider = provider_get("ollama")))
  e = res$conditions[[1]]
  expect_s3_class(e, "gptr_error_s1_validation")
  expect_identical(e$status, 404L)
  expect_match(conditionMessage(e), "try pulling it first", fixed = TRUE)
  expect_null(res$answers[[1]])
  # a 4xx is the request's own fault: one transfer whatever gptr.s1_rounds allows
  log = srv$log()
  expect_identical(nrow(log), 1L)
  expect_match(log$path, "/v1/systemone$")
})

# ---- the classifier route -----------------------------------------------------------------------

test_that("the route prepares Clef once and answers with provenance and unknown calibration", {
  s1_fresh()
  srv = local_ollama_discovery()
  log = local_ollama_transfers()
  live = list(replay = "auto")
  d = ollama_call("Is it a dog?", text = c(a = "a puppy", b = "a car"), args = live)
  expect_s3_class(d, "gptr_decision")
  expect_identical(as.logical(d), c(a = TRUE, b = TRUE))
  m = attr(d, "meta")
  expect_identical(m[c("model", "engine", "provider", "api", "execution", "locality",
                       "model_digest", "server_version")],
                   list(model = "clef-flash", engine = "ollama", provider = "ollama",
                        api = "ollama-system-one", execution = "native", locality = "local",
                        model_digest = strrep("2", 64), server_version = "0.35.1"))
  expect_identical(m$calibrated, NA)
  expect_null(m$calibration_provenance)
  expect_output(print(d), "calibration unknown", fixed = TRUE)
  n = length(srv$calls)
  expect_gt(n, 0L)
  # the same call again comes from the cache: no transfer and no discovery
  again = ollama_call("Is it a dog?", text = c(a = "a puppy", b = "a car"), args = live)
  expect_identical(attr(again, "meta")$cached, c(TRUE, TRUE))
  expect_length(log$specs, 2L)
  expect_length(srv$calls, n)
  # choices and levels
  ch = ollama_call("Which animal?", text = "a puppy",
                 args = c(live, list(choices = c("dog", "cat", "bird"))))
  expect_identical(as.character(ch), "dog")
  expect_identical(colnames(gptr_prob(ch, "probabilities")), c("dog", "cat", "bird"))
  expect_equal(unname(gptr_prob(ch, "confidence")), ent_conf(c(0.7, 0.15, 0.15)))
  sc = ollama_call("How happy?", text = "a puppy",
                 args = c(live, list(levels = c("sad", "neutral", "happy"))))
  expect_equal(unname(as.double(sc)), 1.4)
  expect_identical(log$bodies[[4]]$questions$answer$criteria, list("sad", "neutral", "happy"))
  expect_length(srv$calls, n)
})

test_that("images join the cache key: other images, another order or none are asked again", {
  s1_fresh()
  local_ollama_discovery()
  log = local_ollama_transfers()
  red = img(png_bytes(8))
  blue = img(png_bytes(9))
  ask = function(images) {
    ollama_call("Which colour?", text = "a rectangle",
              args = list(replay = "auto", choices = c("red", "blue"),
                          opts = list(system1_images = images)))
  }
  cached = function(x) attr(x, "meta")$cached
  expect_false(cached(ask(list(red, blue))))
  expect_true(cached(ask(list(red, blue))))
  expect_false(cached(ask(list(blue, red))))
  expect_false(cached(ask(list(img(png_bytes(10)), blue))))
  expect_false(cached(ask(NULL)))
  expect_length(log$specs, 4L)
  expect_identical(log$bodies[[1]]$images, list(b64(red$data), b64(blue$data)))
  expect_identical(log$bodies[[2]]$images, list(b64(blue$data), b64(red$data)))
  expect_null(log$bodies[[4]]$images)
  # the cache holds neither the state nor the images
  recs = json_encode(mget(ls(s1_cache_mem()), envir = s1_cache_mem()))
  expect_false(grepl(b64(red$data), recs, fixed = TRUE))
  expect_false(grepl("a rectangle", recs, fixed = TRUE))
  # oversized images are refused before anything is sent
  local_mocked_bindings(s1_ollama_body_limit = function(model, images) 200)
  expect_error(ask(list(img(png_bytes(300)))), class = "gptr_error_invalid_argument")
  expect_length(log$specs, 4L)
})

test_that("replay uses the identity frozen with the answers and never discovers (IC-74)", {
  s1_fresh(gptr = TRUE)
  srv = local_ollama_discovery()
  log = local_ollama_transfers()
  pics = list(img(png_bytes()))
  ask = function(text, images = pics, args = list(), model = "ollama/clef-flash") {
    ollama_call("Is it a dog?", text = text, model = model,
              args = c(args, list(opts = list(system1_images = images))))
  }
  first = ask(c("a puppy", "a car"), args = list(replay = "auto"))
  n_sent = length(log$specs)
  n_disc = length(srv$calls)
  # a fresh process: no discovery evidence; discovery, the preflight and the network fail the test
  catalog_reset(discovered = TRUE)
  local_mocked_bindings(catalog_ollama_discover = function(...) stop("discovery must not run"),
                        provider_preflight = function(...) stop("the preflight must not run"))
  local_no_network()
  again = ask(c("a puppy", "a car"))
  expect_identical(as.logical(again), as.logical(first))
  m = attr(again, "meta")
  expect_identical(m$cached, c(TRUE, TRUE))
  expect_identical(m[c("model", "provider", "api", "execution", "locality", "model_digest",
                       "server_version")],
                   list(model = "clef-flash", provider = "ollama", api = "ollama-system-one",
                        execution = "native", locality = "local",
                        model_digest = strrep("2", 64), server_version = "0.35.1"))
  expect_identical(m$calibrated, NA)
  expect_length(srv$calls, n_disc)
  expect_length(log$specs, n_sent)
  # replay cache misses: another state, other images, no images
  expect_error(ask("a bird"), class = "gptr_error_not_recorded")
  expect_error(ask("a puppy", list(img(png_bytes(9)))), class = "gptr_error_not_recorded")
  expect_error(ask("a puppy", NULL), class = "gptr_error_not_recorded")
  # a pinned model identity must match the recorded one
  pinned = function(digest) {
    gptr_provider("ollama", api = "openai-completions", base_url = "http://127.0.0.1:11434/v1",
                  local = TRUE,
                  models = list(list(id = "clef-flash", type = "classifier",
                                     api = "ollama-system-one", digest = digest,
                                     decision = list(images = TRUE))))
  }
  expect_identical(attr(ask("a puppy", model = pinned(strrep("2", 64))), "meta")$cached, TRUE)
  err = expect_error(ask("a puppy", model = pinned(strrep("9", 64))),
                     class = "gptr_error_not_recorded")
  expect_match(conditionMessage(err), "pinned", fixed = TRUE)
  # a replay miss never asks for the egress acknowledgement of a remote endpoint
  local({
    local_settings(providers = list(ollama = list(base_url = "https://ollama.example.invalid/v1")))
    expect_error(ask("a puppy"), class = "gptr_error_not_recorded")
  })
  # a recorded answer without its model identity is refused, not reinvented
  target = s1_target("ollama/clef-flash")
  wire = s1_question("Is it a dog?", "text")$wire
  pk = s1_ollama_pin_keys(s1_cache_salt(), target, wire, list(list(text = "a puppy")), pics)
  pin = s1_cache_get(pk)
  expect_identical(pin$identity$digest, strrep("2", 64))
  pin$identity$digest = NULL
  s1_cache_put(pk, pin)
  err = expect_error(ask("a puppy"), class = "gptr_error_not_recorded")
  expect_match(conditionMessage(err), "identity", fixed = TRUE)
  expect_length(log$specs, n_sent)
})

test_that("an Ollama model without a digest is asked every time and never pinned", {
  s1_fresh()
  models = ollama_models()
  models[["clef-flash:latest"]]$tag$digest = NULL
  local_ollama_discovery(models)
  log = local_ollama_transfers()
  a = ollama_call("Ok?", text = "a", args = list(replay = "auto"))
  b = ollama_call("Ok?", text = "a", args = list(replay = "auto"))
  expect_identical(attr(b, "meta")$cached, FALSE)
  expect_identical(attr(a, "meta")$model_digest, NA_character_)
  expect_length(log$specs, 2L)
  expect_length(ls(s1_cache_mem()), 0L)
})

# ---- failures before egress ---------------------------------------------------------------------

test_that("missing or old servers and unsupported models or inputs fail before anything is sent", {
  s1_fresh()
  srv = local_ollama_discovery()
  log = local_ollama_transfers()
  ask = function(model = "ollama/clef-flash", opts = list()) {
    ollama_call("Ok?", text = "a", model = model, args = list(replay = "auto", opts = opts))
  }
  srv$down = TRUE
  err = expect_error(ask(), class = "gptr_error_network")
  expect_match(conditionMessage(err), "ollama serve", fixed = TRUE)
  srv$down = FALSE
  srv$models = ollama_models()["qwen3:1.7b"]
  err = expect_error(ask(), class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "ollama pull clef-flash", fixed = TRUE)
  srv$models = ollama_models()
  srv$version = "0.35.0"
  err = expect_error(ask(), class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "0.35.1", fixed = TRUE)
  catalog_reset(discovered = TRUE)
  srv$version = "0.35.1"
  # a conversational model is not a System 1 model; a claimed classifier needs the capability
  expect_error(ask("ollama/qwen3:1.7b"), class = "gptr_error_invalid_argument")
  off = gptr_register(gptr_spec("model", "ollama/qwen3:1.7b", type = "classifier",
                                api = "ollama-system-one"))
  withr::defer(off())
  expect_error(ask("ollama/qwen3:1.7b"), class = "gptr_error_not_available")
  # weights that are not GGUF are not served by the decision endpoint
  local({
    safetensors = ollama_models()
    safetensors[["clef-flash:latest"]]$tag$details$format = "safetensors"
    safetensors[["clef-flash:latest"]]$show$details$format = "safetensors"
    srv$models = safetensors
    catalog_reset(discovered = TRUE)
    withr::defer(catalog_reset(discovered = TRUE))
    withr::defer(assign("models", ollama_models(), envir = srv))
    err = expect_error(ask(), class = "gptr_error_not_available")
    expect_match(conditionMessage(err), "GGUF", fixed = TRUE)
  })
  # images: a model without vision, a video, a format the endpoint does not take
  blind = ollama_models()
  blind[["clef-flash:latest"]]$show$projector_info = NULL
  srv$models = blind
  catalog_reset(discovered = TRUE)
  expect_error(ask(opts = list(system1_images = list(img(png_bytes())))),
               class = "gptr_error_invalid_argument")
  srv$models = ollama_models()
  catalog_reset(discovered = TRUE)
  expect_error(ask(opts = list(system1_images = list(img(as.raw(1:12), "video/mp4")))),
               class = "gptr_error_invalid_argument")
  expect_error(ask(opts = list(system1_images = list(img(jpeg_bytes(), "image/png")))),
               class = "gptr_error_invalid_argument")
  expect_length(log$specs, 0L)
})

test_that("local-only refuses cloud markers and remote endpoints; only a run record relaxes it", {
  s1_fresh()
  models = ollama_models()
  models[["clef-flash:cloud"]] = list(
    tag = list(name = "clef-flash:cloud", model = "clef-flash:cloud", digest = strrep("5", 64),
               remote_host = "https://ollama.com:443", remote_model = "clef-flash",
               details = list(format = "gguf", family = "clef")),
    show = list(capabilities = list("decision"), remote_host = "https://ollama.com:443",
                remote_model = "clef-flash", details = list(format = "gguf", family = "clef")))
  models[["clef:27b-cloud"]] = list(
    tag = list(name = "clef:27b-cloud", model = "clef:27b-cloud", digest = strrep("6", 64),
               details = list(format = "gguf", family = "clef")),
    show = list(capabilities = list("decision"), details = list(format = "gguf")))
  srv = local_ollama_discovery(models)
  log = local_ollama_transfers()
  ask = function(model = "ollama/clef-flash", opts = list()) {
    ollama_call("Ok?", text = "a", model = model, args = list(replay = "auto", opts = opts))
  }
  # discovery lists them as classifiers; local-only refuses both before anything is sent
  gptr_models(provider = "ollama", refresh = TRUE)
  expect_error(ask("ollama/clef-flash:cloud"), class = "gptr_error_untrusted")
  expect_error(ask("ollama/clef:27b-cloud"), class = "gptr_error_untrusted")
  n = length(srv$calls)
  # a remote endpoint: refused before any discovery request; settings and call options cannot
  # relax local-only (07 section 2.1: only the protected record of a run can)
  local({
    local_settings(providers = list(ollama = list(base_url = "http://10.1.2.3:11434/v1",
                                                  local_only = FALSE)))
    expect_error(ask(), class = "gptr_error_untrusted")
    expect_error(ask(opts = list(safety = list(ollama_local_only = FALSE), local_only = FALSE)),
                 class = "gptr_error_untrusted")
    expect_length(srv$calls, n)
  })
  # nor can a model record that claims to be local
  claimed = gptr_provider("ollama", api = "openai-completions",
                          base_url = "https://ollama.example.invalid/v1", local = TRUE,
                          models = list(list(id = "clef-flash", type = "classifier",
                                             api = "ollama-system-one", locality = "local")))
  expect_error(ask(claimed), class = "gptr_error_untrusted")
  # the frozen safety record of a run relaxes it: discovery and the preflight then pass for the
  # remote server, and the egress acknowledgement is still required
  local({
    local_settings(providers = list(ollama = list(base_url = "http://10.1.2.3:11434/v1")))
    local_mocked_bindings(run_current = function() {
      list(id = "u00000001", session = NULL, opts = list(safety = list(ollama_local_only = FALSE)))
    })
    expect_error(ask(), class = "gptr_error_egress")
    expect_true(any(startsWith(srv$calls, "GET http://10.1.2.3:11434/api/version")))
  })
  expect_length(log$specs, 0L)
})

test_that("no hidden fallback: a failing Ollama System 1 never asks another model", {
  s1_fresh()
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  chat = local_fake_provider(list(list(json = list(answers = list(answer = 0.8)))),
                             name = "chatty")
  srv = local_ollama_discovery()
  srv$down = TRUE
  local_gptr_options(system1 = "ollama/clef-flash", replay = "auto")
  expect_error(s1_decide("Is it done?", "x"), class = "gptr_error_network")
  # failed requests are NA with one warning in a vector call and an error in a scalar call
  srv$down = FALSE
  local_mocked_bindings(s1_wait = function(seconds) invisible(NULL))
  log = local_ollama_transfers(function(body) list(status = 500L))
  expect_warning(ollama_call("Ok?", text = c("a", "b"), args = list(replay = "auto")),
                 class = "gptr_warning_s1_errors")
  d = suppressWarnings(ollama_call("Ok?", text = c("a", "b"), args = list(replay = "auto")))
  expect_identical(unname(as.logical(d)), c(NA, NA))
  expect_error(ollama_call("Ok?", text = "a", args = list(replay = "auto")),
               class = "gptr_error_s1_overloaded")
  # two states twice and one state once, each asked in every bounded round
  expect_length(log$specs, 5L * gptr_opt("s1_rounds"))
  expect_length(fake_requests(judge), 0L)
  expect_length(fake_requests(chat), 0L)
})
