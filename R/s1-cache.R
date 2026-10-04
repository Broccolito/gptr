# System 1 answer cache (contract 7.13 and 11.9; IC-70; IC-74). One record per element: in memory
# (`the$s1_cache`) before a workspace exists, then <workspace>/cache/s1/<first 2 hex>/<sha256>.json.
# Records hold the salted input hash and the question hash, never the input or the question text.
# Report 14 section 3.5 gave the first key shape; IC-70 added the per-project salt and schema 2.
# The `cache_commit` setting (`{s1: true}` by default, C-31) decides whether the directory is
# committed: with `s1: false` it gets a `.gitignore` holding `*`.
#
# IC-74 (07-local-ollama.md sections 2 and 4): a call's identity beyond its reference and endpoint
# (the adapter api, the model digest, the server version and the ordered digests and MIME types of
# its images) joins the key, so new weights under the same tag, another server or other images
# never answer from the cache; a choice key keeps the request order of its options. An Ollama
# model (native or an emulation target) without a digest has no immutable identity: its answers
# get NA keys, which the cache never stores. A cached record becomes a canonical answer only
# after the same validation as a fresh one (s1_check_answer()); unknown values (usage,
# probabilities, confidence) are stored as JSON null, never as 0 or "NA".

s1_cache_schema = 2L

#' The in-memory System 1 cache (created on first use)
#' @noRd
s1_cache_mem = function() {
  if (is.null(the$s1_cache)) the$s1_cache = new.env(parent = emptyenv())
  the$s1_cache
}

#' Replace the in-memory cache and return the previous one (tests, cache clearing)
#' @noRd
s1_cache_swap = function(env = new.env(parent = emptyenv())) {
  if (!is.environment(env)) arg_abort(env, "env", "an environment")
  old = s1_cache_mem()
  the$s1_cache = env
  invisible(old)
}

#' Keep `cache/s1/.gitignore` in line with the `cache_commit` setting
#' @noRd
s1_cache_ignore = function(dir) {
  path = file.path(dir, ".gitignore")
  commit = setting_get("cache_commit", default = list(s1 = TRUE))
  keep = if (is.list(commit)) commit[["s1"]] else NULL
  if (isFALSE(keep)) {
    if (!file.exists(path)) write_atomic(path, "*")
  } else if (file.exists(path) && identical(trimws(read_utf8(path)$text), "*")) {
    unlink(path)
  }
  invisible(NULL)
}

#' The per-project salt: "" without a workspace, else `cache/s1/salt` (32 hex, created once from
#' RNG-free id bits; committed with the cache, IC-70)
#' @noRd
s1_cache_salt = function(ws = workspace_dir()) {
  if (is.null(ws)) return("")
  dir = file.path(ws, "cache", "s1")
  path = file.path(dir, "salt")
  if (file.exists(path)) {
    salt = trimws(read_utf8(path)$text)
    if (grepl("^[0-9a-f]{32}$", salt)) {
      s1_cache_ignore(dir)
      return(salt)
    }
  }
  salt = id_new("", 32L)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_atomic(path, salt)
  s1_cache_ignore(dir)
  salt
}

#' The identity of a System 1 call beyond its reference and endpoint (07-local-ollama.md sections
#' 2 and 4; IC-74)
#'
#' `model` is the resolved and preflighted model record: its api names the adapter, and P05's
#' discovery evidence gives a native model its `digest` and `server_version`. `images` is the
#' call's `.opts$system1_images`, a list of `list(data = <raw>, mime)` records applied to every
#' state; only the SHA-256 of their bytes is kept, in list order (names are ignored), with their
#' MIME types (full checks against the model's limits belong to the request). Absent fields are
#' left out, so TypeSafe's Jev gives `list(adapter = "typesafe-system-one")` and its alias stays
#' the key (contract 11.9). An Ollama model (api `ollama-system-one`, or provider `ollama`, such
#' as an emulation target) without a digest has only a mutable tag that the next discovery may
#' point at other weights: `mutable = TRUE`, and s1_cache_keys() gives its answers NA keys (07
#' section 2: no durable reuse without an immutable identity).
#' @noRd
s1_cache_identity = function(model, images = NULL) {
  if (!is.list(model)) arg_abort(model, "model", "a resolved model record (a list)")
  if (!is.null(images) && !is.list(images)) {
    arg_abort(images, "images", "a list of image records list(data = <raw>, mime) or NULL")
  }
  chr1 = function(x) if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)) x
  api = chr1(model[["api"]])
  digest = chr1(model[["digest"]])
  # names would make the images a JSON object, which canonical_json() sorts: list order counts
  shown = lapply(unname(images), function(im) {
    ok = is.list(im) && is.raw(im[["data"]]) && length(im[["data"]]) > 0L &&
      !is.null(chr1(im[["mime"]]))
    if (!ok) {
      arg_abort(im, "images", "image records list(data = <raw bytes>, mime = <MIME type>)")
    }
    list(sha256 = hash_sha256(im[["data"]]), mime = im[["mime"]])
  })
  # an Ollama route as in P05's catalog_ollama_route(): the native api or the ollama provider
  ollama = identical(api, "ollama-system-one") || identical(model[["provider"]], "ollama")
  id = list(adapter = api, digest = digest, server_version = chr1(model[["server_version"]]),
            images = if (length(shown)) shown,
            mutable = if (ollama && is.null(digest)) TRUE)
  Filter(Negate(is.null), id)
}

#' Cache keys of the states of one question (vectorised over states; contract 11.9, IC-74)
#'
#' Without `identity` the key is contract 11.9's `list(schema = 2L, salt, endpoint, model,
#' question, type, criteria, input)`; a choice question adds its option names in request order
#' (`options`; canonical JSON sorts the criteria by name), and a non-empty `identity`
#' (s1_cache_identity()) joins as `identity`. A mutable identity gives NA keys: such answers are
#' never cached.
#' @noRd
s1_cache_keys = function(salt, endpoint, model, question, states, identity = NULL) {
  check_string(salt, "salt", empty = TRUE)
  check_string(endpoint, "endpoint")
  check_string(model, "model")
  text = if (is.list(question)) question[["instructions"]] else NULL
  if (!is.character(text) || length(text) != 1L || is.na(text) ||
        !isTRUE(question[["type"]] %in% s1_types)) {
    arg_abort(question, "question", "a wire question with instructions and a type")
  }
  if (!is.list(states)) arg_abort(states, "states", "a list of states")
  named = is.list(identity) && (!length(identity) || !is.null(names(identity)))
  if (!is.null(identity) && !named) {
    arg_abort(identity, "identity", "a call identity from s1_cache_identity() or NULL")
  }
  if (!length(states)) return(character())
  if (isTRUE(identity[["mutable"]])) return(rep(NA_character_, length(states)))
  base = list(schema = s1_cache_schema, salt = salt, endpoint = endpoint, model = model,
              question = question[["instructions"]], type = question[["type"]],
              criteria = question[["criteria"]])
  if (identical(question[["type"]], "choice")) {
    base$options = as.list(names(question[["criteria"]]))
  }
  if (length(identity)) base$identity = identity
  texts = vapply(states, function(st) canonical_json(c(base, list(input = st))), "")
  hash_sha256(texts)
}

#' Can `key` be looked up or stored? FALSE for NA_character_ (an answer the cache never keeps,
#' s1_cache_keys()); anything but 64 lower-case hex digits is refused, since keys become paths
#' @noRd
s1_cache_usable = function(key) {
  if (is.character(key) && length(key) == 1L && is.na(key)) return(FALSE)
  if (!is.character(key) || length(key) != 1L || !grepl("^[0-9a-f]{64}$", key)) {
    arg_abort(key, "key", "a cache key from s1_cache_keys() (64 hex digits) or NA")
  }
  TRUE
}

#' The path of a cache record inside a workspace
#' @noRd
s1_cache_path = function(ws, key) {
  file.path(ws, "cache", "s1", substr(key, 1L, 2L), paste0(key, ".json"))
}

#' Look up a cache record (touching the file's modification time on a hit), or NULL
#'
#' A file that cannot be read or parsed, or that holds another key's record, is a miss.
#' @noRd
s1_cache_get = function(key) {
  if (!s1_cache_usable(key)) return(NULL)
  ws = workspace_dir()
  if (is.null(ws)) return(get0(key, envir = s1_cache_mem(), inherits = FALSE))
  path = s1_cache_path(ws, key)
  if (!file.exists(path)) return(NULL)
  rec = tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
  if (!is.list(rec) || !identical(rec[["key"]], key)) return(NULL)
  Sys.setFileTime(path, Sys.time())
  rec
}

#' Store a cache record: in memory before a workspace exists, else an atomic JSON file; an NA key
#' stores nothing
#' @noRd
s1_cache_put = function(key, record) {
  if (!s1_cache_usable(key)) return(invisible(NULL))
  ws = workspace_dir()
  if (is.null(ws)) {
    assign(key, record, envir = s1_cache_mem())
    return(invisible(key))
  }
  path = s1_cache_path(ws, key)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_atomic(path, json_encode(record))
  invisible(key)
}

#' A finite number, or NULL (JSON null) when it is unknown
#' @noRd
s1_cache_num = function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x)) as.double(x)
}

#' The cache record of one canonical answer (contract 11.9: no input, no question text)
#'
#' `usage` is `list(input, output)`; unknown counts, probabilities and confidences are stored as
#' JSON null (IC-74), and a score's legend (level descriptions, i.e. question text) is not stored.
#' @noRd
s1_cache_record = function(key, answer, model_version, alias, question, state, salt, usage) {
  type = if (is.list(answer)) answer[["type"]] else NULL
  if (!is.character(type) || length(type) != 1L || is.na(type) || !(type %in% s1_types)) {
    arg_abort(answer, "answer", "a canonical System 1 answer")
  }
  probs = answer[["probabilities"]]
  choice = answer[["choice"]]
  value = switch(type, noul = answer[["prob"]], choice = choice, score = answer[["score"]])
  prob = switch(type, noul = answer[["prob"]],
                choice = if (is.character(choice) && length(choice) == 1L &&
                               choice %in% names(probs)) probs[[choice]],
                score = NULL)
  list(key = key, model = model_version, alias = alias,
       question_sha256 = hash_sha256(canonical_json(list(question = question[["instructions"]],
                                                         type = question[["type"]],
                                                         criteria = question[["criteria"]]))),
       input_hash = hash_sha256(paste0(salt, canonical_json(state))),
       answer = if (is.numeric(value)) s1_cache_num(value) else value,
       prob = s1_cache_num(prob),
       probabilities = if (!is.null(probs)) lapply(as.list(probs), s1_cache_num),
       confidence = s1_cache_num(answer[["confidence"]]),
       date = format(Sys.Date()),
       usage = list(input_tokens = s1_cache_num(s1_count(usage[["input"]])),
                    output_tokens = s1_cache_num(s1_count(usage[["output"]]))))
}

#' Rebuild the canonical answer of a cache record, or NULL (a miss) when the record does not hold
#' a valid answer to `question`
#'
#' Probabilities are re-keyed into the question's request order and checked like a fresh answer
#' (s1_check_answer()): a choice among the options that its probabilities support, a probability
#' map over exactly the options, a fractional score that its probabilities give. A score's legend
#' comes from the question. JSON null is NA (unknown).
#' @noRd
s1_cache_answer = function(record, question) {
  if (!is.list(record) || !is.list(question)) return(NULL)
  type = question[["type"]]
  num = function(x) {
    if (is.null(x)) return(NA_real_)
    if (is.numeric(x) && length(x) == 1L) as.double(x) else NULL
  }
  if (identical(type, "noul")) {
    a = list(type = "noul", prob = num(record[["answer"]]) %||% NA_real_)
  } else {
    keys = s1_option_keys(question)
    stored = record[["probabilities"]]
    if (is.null(keys) || !(is.null(stored) || is.list(stored))) return(NULL)
    if (is.null(stored)) stored = stats::setNames(vector("list", length(keys)), keys)
    p = lapply(stored, num)
    if (any(vapply(p, is.null, TRUE))) return(NULL)
    conf = num(record[["confidence"]])
    if (is.null(conf)) return(NULL)
    a = if (identical(type, "choice")) {
      list(type = "choice", choice = record[["answer"]], probabilities = unlist(p),
           confidence = conf)
    } else {
      list(type = "score", score = num(record[["answer"]]) %||% NA_real_,
           probabilities = unlist(p), confidence = conf, legend = s1_legend(question, keys))
    }
  }
  out = s1_check_answer(a, question, function(msg) s1_condition("s1_response", msg))
  if (inherits(out, "condition")) NULL else out
}
