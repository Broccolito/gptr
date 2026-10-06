# Native Ollama System One decisions (IC-74; 07-local-ollama.md sections 2-6; report 04b; D-120):
# the `ollama-system-one` http_json adapter for Ollama's `POST /v1/systemone` (Clef, Clef Flash;
# Ollama 0.35.1 or later). No key is ever sent to Ollama. Native answers are pinned with the
# identity that gave them, so offline replay needs no discovery (07 section 4).

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

# Half a unit of Ollama's four-decimal rounding, the tolerance of its sums, choices and scores
s1_ollama_round_tol = 5e-5

# Slack between a wire confidence and the entropy confidence of the rounded probabilities (Jev's
# peak formula differs by far more)
s1_ollama_conf_tol = 0.01

# Seconds to the first byte of an answer: a non-streaming decision arrives whole, after the model
# is loaded (a cold Clef load takes a while) and the scoring pass ran
s1_ollama_first_byte = 120

# ---- endpoint, model and limits -----------------------------------------------------------------

#' Is a model a native Ollama decision model (its own api is ollama-system-one)?
#' @noRd
s1_ollama_native = function(model) is.list(model) && identical(model[["api"]], s1_ollama_api)

#' The decision endpoint `<origin><root>/v1/systemone` of an Ollama base URL (a final `/v1` of the
#' root is never doubled); NULL when the base is not one HTTP(S) URL
#' @noRd
s1_ollama_endpoint = function(base_url) {
  if (!rlang::is_string(base_url)) return(NULL)
  parts = url_parse(base_url)
  if (is.null(parts) || !tolower(parts$scheme) %in% c("http", "https")) return(NULL)
  origin = url_origin(base_url)
  if (is.na(origin)) return(NULL)
  path = sub("/+$", "", parts$path %||% "")
  paste0(origin, sub("/v1$", "", path), "/v1/systemone")
}

#' A limit of the adapter, lowered (never raised) by the model's decision record (07 section 2)
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

#' The weight format P05's discovery reported for a model (its own, else its tag's entry with the
#' same digest), NULL when unknown; a pure catalog read
#' @noRd
s1_ollama_format = function(model) {
  fmt = model[["format"]]
  digest = model[["digest"]]
  if (is.null(fmt) && !is.null(digest)) {
    tagged = tryCatch(s1_model(paste0(model[["provider"]], "/", s1_ollama_tag(model[["id"]])),
                               strict = FALSE),
                      error = function(e) NULL)
    if (is.list(tagged) && identical(tagged[["digest"]], digest)) fmt = tagged[["format"]]
  }
  if (rlang::is_string(fmt) && nzchar(fmt)) fmt
}

#' A checked native model the decision endpoint can serve: weights reported in a format other than
#' GGUF are refused (report 04b); an unknown format is left to the server
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

#' Check the call's images against the adapter and the model before any encoding (07 section 4);
#' returns their base64 length, invisibly
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
      rlang::is_string(im[["mime"]])
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

#' The questions of a request checked against the adapter's limits, lowered by the model's: 1 to
#' 64 named questions of types the model answers, with 2 to 26 options or levels
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
    if (!rlang::is_string(type, known)) {
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
#' `opts$credential` is ignored. Question and image problems end the call; an empty or oversized
#' state fails alone (gptr_error_s1_validation, D-120).
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

#' classify$parse of ollama-system-one (s1_wire_parse())
#' @noRd
s1_ollama_parse = function(model, status, headers, body, questions) {
  s1_wire_parse(model, status, headers, body, questions, ollama = TRUE)
}

# ---- replay with the frozen identity ------------------------------------------------------------

#' The pin keys of the states of one question: cache keys whose identity drops the digest and the
#' server version (which only discovery knows), so replay finds them without discovery
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
  list(key = pin_key, answer_key = key,
       identity = list(adapter = model[["api"]], digest = model[["digest"]],
                       server_version = model[["server_version"]],
                       locality = model[["locality"]] %||% "unknown"),
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
  id = if (is.list(pin)) pin[["identity"]] else NULL
  ok = is.list(id) && identical(id[["adapter"]], s1_ollama_api) &&
    rlang::is_string(id[["digest"]]) && rlang::is_string(id[["server_version"]]) &&
    rlang::is_string(id[["locality"]], c("local", "remote", "unknown"))
  if (!ok) s1_ollama_unrecorded(target, "they were recorded without the model identity")
  pinned = target$model[["digest"]]
  if (!is.null(pinned) && !identical(pinned, id[["digest"]])) {
    s1_ollama_unrecorded(target, paste0("the model record pinned the digest ", pinned,
                                        ", and the answers were recorded with ", id[["digest"]]))
  }
  list(digest = id[["digest"]], server_version = id[["server_version"]],
       locality = id[["locality"]])
}

#' Offline replay of a native Ollama target (07 section 4): `list(answers, cached, version,
#' identity)` from the pins, with no discovery or request; a state without a pin is a miss
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
