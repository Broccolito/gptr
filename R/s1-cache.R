# System 1 answer cache (contract 7.13 and 11.9; IC-70; IC-74, D-080). One record per element: in
# memory (`the$s1_cache`) before a workspace exists, then <workspace>/cache/s1/<2 hex>/<key>.json.
# Records hold the salted input hash and the question hash, never the input or the question text;
# unknown values are stored as JSON null, never as 0.

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

#' The identity of a System 1 call beyond its reference and endpoint (IC-74, D-080)
#'
#' Adapter api, digest, server version and each image's SHA-256 and MIME type in order; an Ollama
#' model without a digest is `mutable`, and s1_cache_keys() gives it NA keys (07 section 2).
#' @noRd
s1_cache_identity = function(model, images = NULL) {
  api = model[["api"]]
  digest = model[["digest"]]
  if (!rlang::is_string(digest) || !nzchar(digest)) digest = NULL
  # names would make the images a JSON object, which canonical_json() sorts: list order counts
  shown = lapply(unname(images), function(im) {
    list(sha256 = hash_sha256(im[["data"]]), mime = im[["mime"]])
  })
  # an Ollama route as in P05's catalog_ollama_route(): the native api or the ollama provider
  ollama = identical(api, "ollama-system-one") || identical(model[["provider"]], "ollama")
  id = list(adapter = api, digest = digest, server_version = model[["server_version"]],
            images = if (length(shown)) shown,
            mutable = if (ollama && is.null(digest)) TRUE)
  Filter(Negate(is.null), id)
}

#' Cache keys of the states of one question (vectorised over states; contract 11.9, IC-74)
#'
#' A choice key adds its option names in request order (canonical JSON sorts the criteria); a
#' mutable identity gives NA keys, which are never cached.
#' @noRd
s1_cache_keys = function(salt, endpoint, model, question, states, identity = NULL) {
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
  type = answer[["type"]]
  probs = answer[["probabilities"]]
  choice = answer[["choice"]]
  value = switch(type, noul = answer[["prob"]], choice = choice, score = answer[["score"]])
  prob = switch(type, noul = answer[["prob"]],
                choice = if (rlang::is_string(choice) && choice %in% names(probs)) probs[[choice]],
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
#' Checked like a fresh answer (s1_check_answer()); JSON null is NA (unknown).
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
