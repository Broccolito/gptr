# Native Ollama System One decisions (IC-74; 07-local-ollama.md sections 2-6; research report
# 04b): the `ollama-system-one` classifier adapter, a non-streaming `http_json` adapter for
# Ollama's `POST /v1/systemone` (Clef, Clef Flash; Ollama 0.35.1 or later). Layer L4 of the s1
# area: the model layer is reached through s1-types.R's wrappers only.
#
# The request is `{model, state, questions, images?}`: the state is text, a JSON object or an
# array; 1 to 64 named questions of the types `noul`, `choice` (2 to 26 options) and `score` (2 to
# 26 levels); images are raw base64 PNG, JPEG or WebP strings (never URLs or data URLs), the same
# for every state of a call. Text bodies are limited to 64 KiB and image-bearing bodies to 32 MiB,
# and a model's decision record may only lower these limits. No key is ever sent: the loopback
# server needs none, and a TypeSafe or other cloud credential never travels to Ollama. The
# response `{model, answers, usage}` is normalised exactly once into the canonical records of 07
# section 3 (s1_check_answer()'s shape), validated against the request: answer ids, types,
# option names, probability bounds and sums, Ollama's own confidence `1 - H(p) / log(N)` (zero
# probabilities add no entropy; Jev's formulas never apply), choices their probabilities support
# and fractional scores their probabilities give (sums, choices and scores at Ollama's
# four-decimal rounding). Errors are `{"error": "..."}` bodies. A native model is admitted one
# request at a time per server unless its decision record sets its own `max_active` (s1_gate()).
#
# The identity of a native answer is the model digest and server version that P05's discovery
# established. Live cache keys carry it (s1_cache_identity()); next to each cached answer a pin
# records that identity under a key without it, so offline replay finds the answer, and the
# identity frozen with it, without discovery, /api/show or any request (07 section 4).

s1_ollama_api = "ollama-system-one"

# The adapter's limits (07 sections 3-4; report 04b): questions, options or levels, body bytes
s1_ollama_max_questions = 64L
s1_ollama_max_options = 26L
s1_ollama_max_text = 65536
s1_ollama_max_images = 33554432

# The image MIME types the decision endpoint takes
s1_ollama_mimes = c("image/png", "image/jpeg", "image/webp")

# Requests one Ollama server answers at once unless the model's decision record sets its own
# `max_active` (07 section 2: local Clef concurrency defaults to one active request per server)
s1_ollama_max_active = 1L

# Half a unit of the fourth decimal: Ollama rounds probabilities and scores to four decimals, so
# each value is off by at most this much; probability sums, the support of a choice and the
# reconstruction of a score are checked at this rounding (TypeSafe's is s1_round_tol)
s1_ollama_round_tol = 5e-5

# Slack between a wire confidence and the entropy confidence of the reported probabilities: the
# probabilities come rounded, and Jev's peak formula differs by far more on any distribution
# that is not uniform or certain
s1_ollama_conf_tol = 0.01

# Seconds to the first byte of an answer: a non-streaming decision arrives whole, after the model
# is loaded (a cold Clef load takes a while) and the scoring pass ran
s1_ollama_first_byte = 120

# ---- endpoint, model and limits -----------------------------------------------------------------

#' Is a model a native Ollama decision model (its own api is ollama-system-one)?
#' @noRd
s1_ollama_native = function(model) is.list(model) && identical(model[["api"]], s1_ollama_api)

#' The decision endpoint of a configured Ollama base URL: `<origin><root>/v1/systemone`, where the
#' root is the base path without trailing slashes and without a final `/v1` (as P05's discovery
#' reads `/api/...` from the same root), so `/v1` is never doubled; query and fragment are
#' dropped. NULL when the base is not one HTTP(S) URL.
#' @noRd
s1_ollama_endpoint = function(base_url) {
  if (!is.character(base_url) || length(base_url) != 1L || is.na(base_url)) return(NULL)
  parts = http_url_parts(base_url)
  if (is.null(parts) || !tolower(parts$scheme) %in% c("http", "https")) return(NULL)
  origin = url_origin(base_url)
  if (is.na(origin)) return(NULL)
  path = sub("/+$", "", parts$path %||% "")
  paste0(origin, sub("/v1$", "", path), "/v1/systemone")
}

#' A limit of the adapter, lowered by the model's decision record (07 section 2: typed metadata),
#' never raised
#' @noRd
s1_ollama_limit = function(model, field, adapter) {
  d = if (is.list(model)) model[["decision"]] else NULL
  own = if (is.list(d)) d[[field]] else NULL
  if (!is.numeric(own) || length(own) != 1L || is.na(own) || own < 1) return(adapter)
  min(adapter, own)
}

#' The largest request body for a text-only (`images = FALSE`) or an image-bearing request
#' @noRd
s1_ollama_body_limit = function(model, images) {
  if (isTRUE(images)) {
    s1_ollama_limit(model, "max_request_bytes_images", s1_ollama_max_images)
  } else {
    s1_ollama_limit(model, "max_request_bytes_text", s1_ollama_max_text)
  }
}

#' The weight format P05's discovery reported for a model: its own `format`, else that of the
#' discovered entry of its tag when that entry has the same digest (a bare catalog name such as
#' `clef-flash` stands for `clef-flash:latest`); NULL when unknown. A pure catalog read.
#' @noRd
s1_ollama_format = function(model) {
  chr1 = function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  if (chr1(model[["format"]])) return(model[["format"]])
  digest = model[["digest"]]
  if (!chr1(digest) || !chr1(model[["provider"]]) || !chr1(model[["id"]])) return(NULL)
  tagged = tryCatch(s1_model(paste0(model[["provider"]], "/", s1_ollama_tag(model[["id"]])),
                             strict = FALSE),
                    error = function(e) NULL)
  if (is.list(tagged) && identical(tagged[["digest"]], digest) && chr1(tagged[["format"]])) {
    return(tagged[["format"]])
  }
  NULL
}

#' A checked native model the decision endpoint can serve (after P05's preflight or preparation):
#' weights that P05's discovery reports in a format other than GGUF are refused, since MLX or
#' Safetensors variants are not served by `/v1/systemone` (report 04b); an unknown format is left
#' to the server. Returns the model.
#' @noRd
s1_ollama_ready = function(model) {
  if (!s1_ollama_native(model)) return(model)
  fmt = s1_ollama_format(model)
  if (!is.null(fmt) && !identical(tolower(fmt), "gguf")) {
    ref = model[["ref"]] %||% paste0(model[["provider"]], "/", model[["id"]])
    gptr_abort(paste0("Model ", ref, " cannot be used: Ollama serves native decisions from GGUF ",
                      "weights, and this model's weights are ", fmt, ". Install a GGUF variant ",
                      "yourself; gptr never downloads models."),
               "not_available", member = ref, provided_by = "a GGUF decision model")
  }
  model
}

# ---- the request --------------------------------------------------------------------------------

#' The MIME type that the leading bytes of an image show (PNG, JPEG, WebP), or NA
#' @noRd
s1_ollama_sniff = function(data) {
  starts = function(sig) length(data) >= length(sig) && identical(data[seq_along(sig)], sig)
  if (starts(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)))) return("image/png")
  if (starts(as.raw(c(0xff, 0xd8, 0xff)))) return("image/jpeg")
  if (length(data) >= 12L && identical(data[1:4], charToRaw("RIFF")) &&
        identical(data[9:12], charToRaw("WEBP"))) {
    return("image/webp")
  }
  NA_character_
}

#' Check the call's images against the adapter and the model before any encoding (07 section 4):
#' a list of `list(data = <raw bytes>, mime)` records whose MIME type the endpoint takes and whose
#' bytes are that format; a model whose decision record (P05's evidence) shows no vision takes
#' none, and their base64 must fit the image body limit. Returns the base64 length, invisibly.
#' @noRd
s1_ollama_images_check = function(images, model) {
  expected = paste0("a list of image records list(data = <raw bytes>, mime = ",
                    paste0("\"", s1_ollama_mimes, "\"", collapse = " | "), ")")
  if (!is.list(images) || is.object(images)) arg_abort(images, ".opts$system1_images", expected)
  d = model[["decision"]]
  if (length(images) && !(is.list(d) && isTRUE(d[["images"]]))) {
    ref = model[["ref"]] %||% paste0(model[["provider"]], "/", model[["id"]])
    gptr_abort(c(paste0("The System 1 model ", ref, " does not take images: its server reports ",
                        "no vision support for it."),
                 "Leave out .opts$system1_images, or use a decision model with vision weights."),
               "invalid_argument", arg = ".opts$system1_images",
               expected = "images only for a decision model that accepts them")
  }
  total = 0
  for (k in seq_along(images)) {
    im = images[[k]]
    ok = is.list(im) && is.raw(im[["data"]]) && length(im[["data"]]) > 0L &&
      is.character(im[["mime"]]) && length(im[["mime"]]) == 1L && !is.na(im[["mime"]])
    if (!ok) arg_abort(im, ".opts$system1_images", expected)
    if (!im[["mime"]] %in% s1_ollama_mimes) {
      gptr_abort(paste0("Image ", k, " is ", im[["mime"]], ": Ollama's decision endpoint takes ",
                        "PNG, JPEG or WebP images only (no video or other formats)."),
                 "invalid_argument", arg = ".opts$system1_images", expected = expected)
    }
    seen = s1_ollama_sniff(im[["data"]])
    if (!identical(seen, im[["mime"]])) {
      gptr_abort(paste0("The bytes of image ", k, " are not a ", im[["mime"]], " image",
                        if (!is.na(seen)) paste0(" (they are ", seen, ")"), ". Give the image's ",
                        "own bytes and their MIME type, never a path, a URL or a description."),
                 "invalid_argument", arg = ".opts$system1_images", expected = expected)
    }
    total = total + 4 * ceiling(length(im[["data"]]) / 3)
  }
  limit = s1_ollama_body_limit(model, TRUE)
  if (total > limit) {
    gptr_abort(paste0("The images take ", format(total, scientific = FALSE), " bytes as base64; ",
                      "Ollama's decision endpoint accepts at most ",
                      format(limit, scientific = FALSE), " bytes for a request with images. ",
                      "Send fewer or smaller images."),
               "invalid_argument", arg = ".opts$system1_images",
               expected = "images within the decision endpoint's body limit")
  }
  invisible(total)
}

#' The questions of a request checked against the adapter and the model: 1 to 64 named questions
#' (or the model's lower limit), each a known type the model answers, with 2 to 26 options or
#' levels (or the model's lower limit)
#' @noRd
s1_ollama_questions_check = function(questions, model) {
  bad = function(msg) {
    gptr_abort(msg, "invalid_argument", arg = "questions",
               expected = "named noul, choice or score questions within the endpoint's limits")
  }
  ids = names(questions)
  maxq = s1_ollama_limit(model, "max_questions", s1_ollama_max_questions)
  if (!is.list(questions) || !length(questions) || length(questions) > maxq || is.null(ids) ||
        anyNA(ids) || !all(nzchar(trimws(ids))) || anyDuplicated(ids)) {
    bad(paste0("Ollama's decision endpoint takes 1 to ", maxq, " questions with unique ",
               "non-blank names."))
  }
  types = model[["decision"]][["types"]] %||% s1_types
  maxo = s1_ollama_limit(model, "max_options", s1_ollama_max_options)
  for (id in ids) {
    q = questions[[id]]
    type = if (is.list(q)) q[["type"]] else NULL
    known = intersect(types, s1_types)
    if (!is.character(type) || length(type) != 1L || !isTRUE(type %in% known)) {
      bad(paste0("The question ", id, " has a type this model does not answer (",
                 paste(known, collapse = ", "), ")."))
    }
    if (identical(type, "noul")) next
    n = length(q[["criteria"]])
    keys = s1_option_keys(q)
    if (is.null(keys) || n < 2L || n > maxo) {
      bad(paste0("The question ", id, " needs 2 to ", maxo, " unique options or levels."))
    }
  }
  invisible(TRUE)
}

#' Is a state one the endpoint takes: non-empty text, or a non-empty JSON object or array?
#' @noRd
s1_ollama_state_ok = function(state) {
  if (is.character(state)) return(length(state) == 1L && !is.na(state) && nzchar(state))
  is.list(state) && length(state) > 0L
}

#' classify$build of ollama-system-one: the request spec of one state (contract 8.1, IC-74)
#'
#' `opts$base_url` is the provider's configured base URL and `opts$images` the call's images (the
#' same for every state). `opts$credential` is ignored: no key is ever attached to an Ollama
#' request. Question and image problems are the call's (gptr_error_invalid_argument, raised before
#' the first request); an empty state, or one whose body exceeds the endpoint's limit, fails that
#' element alone (gptr_error_s1_validation, which s1_request() records as the element's failure).
#' @noRd
s1_ollama_build = function(model, state, questions, opts) {
  url = s1_ollama_endpoint(opts[["base_url"]])
  ref = model[["ref"]] %||% paste0(model[["provider"]], "/", model[["id"]])
  if (is.null(url)) {
    gptr_abort(paste0("Model ", ref, " cannot be used: its provider has no valid HTTP base URL."),
               "not_available", member = ref, provided_by = "a configured Ollama base_url")
  }
  s1_ollama_questions_check(questions, model)
  if (!s1_ollama_state_ok(state)) {
    stop(s1_condition("s1_validation", paste0("Ollama's decision endpoint needs a state: ",
                                              "non-empty text, a JSON object or an array."),
                      error_type = "invalid_state", model = model[["id"]]))
  }
  images = opts[["images"]]
  body = list(model = model[["id"]], state = state, questions = questions)
  if (length(images)) {
    s1_ollama_images_check(images, model)
    body$images = lapply(unname(images), function(im) {
      gsub("[\r\n]", "", jsonlite::base64_enc(im[["data"]]))
    })
  }
  text = json_encode(body)
  limit = s1_ollama_body_limit(model, length(images) > 0L)
  size = nchar(text, type = "bytes")
  if (size > limit) {
    stop(s1_condition("s1_validation", paste0(
      "The System 1 request for this state takes ", format(size, scientific = FALSE),
      " bytes; Ollama's decision endpoint accepts at most ", format(limit, scientific = FALSE),
      " bytes for a ", if (length(images)) "request with images" else "text-only request",
      ". Shorten the state", if (length(images)) " or send fewer or smaller images", "."),
      error_type = "request_too_large", model = model[["id"]]))
  }
  list(url = url, method = "POST",
       headers = list(`Content-Type` = "application/json", Accept = "application/json",
                      `User-Agent` = s1_user_agent()),
       body = text, stream = "json", first_byte_timeout = s1_ollama_first_byte)
}

# ---- the answers --------------------------------------------------------------------------------

#' The canonical tag of an Ollama model name, for matching only (a bare name means `:latest`)
#' @noRd
s1_ollama_tag = function(id) {
  id = tolower(as.character(id)[1L])
  if (grepl(":", sub("^.*/", "", id), fixed = TRUE)) id else paste0(id, ":latest")
}

#' Ollama's confidence of a choice or score distribution: 1 - H(p) / log(N), with zero
#' probabilities contributing no entropy (report 04b; never Jev's formulas)
#' @noRd
s1_ollama_confidence = function(p) {
  n = length(p)
  if (n <= 1L) return(1)
  tot = sum(p)
  q = if (tot > 0) p / tot else rep(1 / n, n)
  q = q[q > 0]
  min(1, max(0, 1 - (-sum(q * log(q))) / log(n)))
}

#' One wire answer as a canonical record (07 section 3), or an unsignalled gptr_error_s1_response
#'
#' Probabilities are required and re-keyed into request order; their sum, the support of a
#' choice and the reconstruction of a score are checked at Ollama's four-decimal rounding
#' (s1_ollama_round_tol, never TypeSafe's two decimals); the wire confidence is kept when it
#' matches the entropy confidence of the probabilities (within s1_ollama_conf_tol) and computed
#' with that formula when absent; a score's legend, when sent, must name exactly its levels (the
#' canonical legend is the request's level descriptions).
#' @noRd
s1_ollama_answer = function(answer, question, model_id) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  type = if (is.list(question)) question[["type"]] else NULL
  if (!is.character(type) || length(type) != 1L || is.na(type) || !(type %in% s1_types)) {
    return(bad("Ollama was sent a question without a known type."))
  }
  if (!is.list(answer) || !identical(answer[["type"]], type)) {
    return(bad(paste0("Ollama returned an answer that is not a ", type, " answer.")))
  }
  if (identical(type, "noul")) {
    p = s1_unit(answer[["noul"]])
    if (is.na(p)) return(bad("Ollama returned an invalid noul probability."))
    return(list(type = "noul", prob = p))
  }
  keys = s1_option_keys(question)
  if (is.null(keys)) return(bad("Ollama was sent a question without valid options."))
  got = answer[["probabilities"]]
  if (!is.list(got) || !length(got)) {
    return(bad(paste0("Ollama returned a ", type, " answer without probabilities.")))
  }
  p = s1_answer_probs(got, keys, s1_ollama_round_tol)
  if (is.character(p)) return(bad(sub("^System 1", "Ollama", p)))
  conf = s1_ollama_confidence(p)
  given = answer[["confidence"]]
  if (!is.null(given)) {
    wire = s1_unit(given)
    if (is.na(wire)) return(bad("Ollama returned an invalid confidence."))
    if (abs(wire - conf) > s1_ollama_conf_tol) {
      return(bad(paste0("Ollama returned a confidence that its probabilities do not give ",
                        "(1 - H(p) / log(N)).")))
    }
    conf = wire
  }
  if (identical(type, "choice")) {
    return(s1_parse_choice(answer[["choice"]], p, keys, conf, bad, s1_ollama_round_tol))
  }
  legend = answer[["legend"]]
  if (!is.null(legend)) {
    ln = names(legend)
    ok = is.list(legend) && !is.null(ln) && !anyNA(ln) && !anyDuplicated(ln) &&
      length(ln) == length(keys) && setequal(ln, keys) &&
      all(vapply(legend, function(x) is.character(x) && length(x) == 1L && !is.na(x), NA))
    if (!ok) return(bad("Ollama returned a score legend that does not name the levels asked."))
  }
  if (is.null(answer[["score"]])) return(bad("Ollama returned a score answer without a score."))
  s1_parse_score(answer[["score"]], p, keys, conf, s1_legend(question, keys), bad,
                 s1_ollama_round_tol)
}

#' Every answer of one response by question id, in question order, or the first problem
#' @noRd
s1_ollama_answers = function(answers, questions, model_id) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  ids = names(questions)
  got = names(answers)
  if (!is.list(answers) || !length(answers) || is.null(got) || anyNA(got) || anyDuplicated(got)) {
    return(bad("Ollama returned answers that are not keyed by question."))
  }
  extra = setdiff(got, ids)
  if (length(extra)) {
    return(bad(paste0("Ollama returned answers to questions that were not asked: ",
                      paste(extra, collapse = ", "), ".")))
  }
  out = vector("list", length(ids))
  names(out) = ids
  for (id in ids) {
    if (!(id %in% got)) return(bad(paste0("Ollama returned no answer for the question ", id, ".")))
    a = s1_ollama_answer(answers[[id]], questions[[id]], model_id)
    if (inherits(a, "condition")) return(a)
    out[[id]] = a
  }
  out
}

#' classify$parse of ollama-system-one: one whole JSON body (contract 8.1, IC-74)
#'
#' `questions` are the ordered wire questions of the request. Returns `list(answers, usage =
#' list(input, output), model_version, request_id)` with canonical answers, or an unsignalled
#' `gptr_error_s1_*` condition: an error body (`{"error": "..."}`) by its status (P04's reactor
#' sends a non-2xx answer to on_fail() instead, s1_transport_outcome()), and a malformed or
#' inconsistent 200 body, or one answered by another model, as `s1_response`. The model version is
#' the model name the server reports; its identity is the digest in the call's provenance.
#' Unreported usage stays unknown (NA).
#' @noRd
s1_ollama_parse = function(model, status, headers, body, questions) {
  model_id = model[["id"]] %||% NA_character_
  rid = s1_header(headers, "x-request-id")
  if (!is.numeric(status) || length(status) != 1L) status = NA_integer_
  obj = tryCatch(json_decode(body), error = function(e) NULL)
  if (is.na(status) || status < 200L || status > 299L) {
    err = if (is.list(obj)) obj[["error"]] else NULL
    if (is.character(err)) obj = list(error = list(message = paste(err, collapse = "; ")))
    return(s1_http_error(status, obj, rid, model_id))
  }
  fail = function(msg) {
    s1_condition("s1_response", msg, status, NA_character_, rid, model_id)
  }
  answers = if (is.list(obj)) obj[["answers"]] else NULL
  if (!is.list(answers)) return(fail("Ollama returned a response without answers."))
  version = obj[["model"]]
  if (is.null(version)) version = model_id
  if (!is.character(version) || length(version) != 1L || is.na(version) || !nzchar(version)) {
    return(fail("Ollama returned a response with an invalid model name."))
  }
  if (!identical(s1_ollama_tag(version), s1_ollama_tag(model_id))) {
    return(fail(paste0("Ollama answered with the model ", version, ", not ", model_id, ".")))
  }
  parsed = s1_ollama_answers(answers, questions, model_id)
  if (inherits(parsed, "condition")) {
    parsed$status = as.integer(status)
    parsed$request_id = rid
    return(parsed)
  }
  list(answers = parsed, usage = s1_usage_of(obj[["usage"]]), model_version = version,
       request_id = rid)
}

# ---- replay with the frozen identity ------------------------------------------------------------

#' The pin keys of the states of one question: the cache keys of s1_cache_keys() whose identity
#' keeps the adapter and the images but not the digest or the server version, which only P05's
#' discovery knows, so replay can find them without discovery
#' @noRd
s1_ollama_pin_keys = function(salt, target, wire, states, images = NULL) {
  id = s1_cache_identity(target$model, images)
  id = id[setdiff(names(id), c("digest", "server_version", "mutable"))]
  id$pin = TRUE
  s1_cache_keys(salt, target$endpoint, target$ref, wire, states, id)
}

#' The pin record of a cached native answer: the answer's cache key and the identity of the
#' checked model that gave it (adapter, digest, server version, locality); no state, no image
#' @noRd
s1_ollama_pin = function(pin_key, key, model) {
  chr1 = function(x) if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)) x
  list(key = pin_key, answer_key = key,
       identity = list(adapter = chr1(model[["api"]]), digest = chr1(model[["digest"]]),
                       server_version = chr1(model[["server_version"]]),
                       locality = chr1(model[["locality"]]) %||% "unknown"),
       date = format(Sys.Date()))
}

#' Refuse a recorded answer under replay (gptr_error_not_recorded, contract IC-47)
#' @noRd
s1_ollama_unrecorded = function(target, why) {
  gptr_abort(c(paste0("Replay mode: the recorded System 1 answers of ", target$ref,
                      " cannot be used: ", why, "."),
               paste0("Replay never asks the model, its server or its discovery endpoints; ",
                      "record the answers again with replay = \"auto\".")),
             "not_recorded", document = NA_character_, prompt = NA_character_)
}

#' The identity frozen in a pin, checked: adapter, digest, server version and locality; a model
#' record that pins a digest must name the recorded one
#' @noRd
s1_ollama_frozen = function(pin, target) {
  chr1 = function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  id = if (is.list(pin)) pin[["identity"]] else NULL
  ok = is.list(id) && identical(id[["adapter"]], s1_ollama_api) && chr1(id[["digest"]]) &&
    chr1(id[["server_version"]]) && isTRUE(id[["locality"]] %in% c("local", "remote", "unknown")) &&
    chr1(pin[["answer_key"]])
  if (!ok) s1_ollama_unrecorded(target, "they were recorded without the model identity")
  pinned = target$model[["digest"]]
  if (chr1(pinned) && !identical(pinned, id[["digest"]])) {
    s1_ollama_unrecorded(target, paste0("the model record pinned the digest ", pinned,
                                        ", and the answers were recorded with ", id[["digest"]]))
  }
  list(digest = id[["digest"]], server_version = id[["server_version"]],
       locality = id[["locality"]])
}

#' Offline replay of a native Ollama target (07 section 4): the answers recorded for these states,
#' this question and these images, with the identity frozen with them; no discovery, no preflight,
#' no request. A state without a pin or a record is a miss (the caller's replay guard refuses it);
#' a pin without its identity, a pinned digest it does not match, a record under another key or
#' answers recorded under different identities are refused. Returns `list(answers, cached,
#' version, identity)`.
#' @noRd
s1_ollama_replay = function(states, wire, target, salt, images = NULL) {
  n = length(states)
  answers = vector("list", n)
  cached = rep(FALSE, n)
  version = NULL
  identity = NULL
  pins = s1_ollama_pin_keys(salt, target, wire, states, images)
  for (i in seq_len(n)) {
    pin = s1_cache_get(pins[i])
    if (is.null(pin)) next
    id = s1_ollama_frozen(pin, target)
    if (!is.null(identity) && !identical(id, identity)) {
      s1_ollama_unrecorded(target, "the states were recorded with different model identities")
    }
    model = target$model
    model[names(id)] = id
    key = s1_cache_keys(salt, target$endpoint, target$ref, wire, states[i],
                        s1_cache_identity(model, images))
    if (!identical(key, pin[["answer_key"]])) {
      s1_ollama_unrecorded(target, "the recorded identity or images do not match the answer")
    }
    rec = s1_cache_get(key)
    a = if (is.null(rec)) NULL else s1_cache_answer(rec, wire)
    if (is.null(a)) next
    answers[i] = list(a)
    cached[i] = TRUE
    identity = id
    version = version %||% s1_cached_version(rec)
  }
  list(answers = answers, cached = cached, version = version, identity = identity)
}
