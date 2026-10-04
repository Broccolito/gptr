# Tests for R/s1-cache.R (plan P13): the per-element System 1 cache (contract 7.13, 11.1, 11.9;
# IC-70; IC-74: 07-local-ollama.md sections 2-4).

source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

noul_q = function() list(type = "noul", instructions = "Is it a dog? The input is in `text`.")
choice_q = function() {
  list(type = "choice", instructions = "Which animal? The input is in `text`.",
       criteria = list(dog = NULL, cat = NULL))
}

test_that("before a workspace exists the cache lives in memory and writes no file", {
  dir = s1_fresh(gptr = FALSE)
  expect_identical(s1_cache_salt(), "")
  key = s1_cache_keys("", "offline:judge", "judge/judge-s1", noul_q(), list(list(text = "a")))
  expect_match(key, "^[0-9a-f]{64}$")
  expect_null(s1_cache_get(key))
  rec = s1_cache_record(key, list(type = "noul", prob = 0.9), "judge-s1-1.0", "judge-s1",
                        noul_q(), list(text = "a"), "", list(input = 10, output = 1))
  s1_cache_put(key, rec)
  expect_identical(s1_cache_get(key)$answer, 0.9)
  expect_identical(list.files(dir, recursive = TRUE, all.files = TRUE), character())
})

test_that("with a workspace the salt is created once and the records are files", {
  dir = s1_fresh(gptr = TRUE)
  salt = s1_cache_salt()
  expect_match(salt, "^[0-9a-f]{32}$")
  expect_identical(s1_cache_salt(), salt)
  expect_true(file.exists(file.path(dir, ".gptr", "cache", "s1", "salt")))
  expect_false(file.exists(file.path(dir, ".gptr", "cache", "s1", ".gitignore")))
  key = s1_cache_keys(salt, "https://api.typesafe.ai/v1/systemone", "typesafe/jev-latest",
                      noul_q(), list(list(text = "A puppy.")))
  rec = s1_cache_record(key, list(type = "noul", prob = 0.97), "jev-1.13.0", "jev-latest",
                        noul_q(), list(text = "A puppy."), salt, list(input = 296, output = 3))
  s1_cache_put(key, rec)
  path = file.path(dir, ".gptr", "cache", "s1", substr(key, 1L, 2L), paste0(key, ".json"))
  expect_true(file.exists(path))
  got = s1_cache_get(key)
  expect_identical(got$model, "jev-1.13.0")
  expect_identical(got$alias, "jev-latest")
  expect_identical(got$usage, list(input_tokens = 296L, output_tokens = 3L))
})

test_that("cache_commit = list(s1 = FALSE) keeps the System 1 cache out of git", {
  dir = s1_fresh(gptr = TRUE)
  local_gptr_options(cache_commit = list(s1 = FALSE, s2 = FALSE))
  s1_cache_salt()
  ignore = file.path(dir, ".gptr", "cache", "s1", ".gitignore")
  expect_identical(trimws(read_utf8(ignore)$text), "*")
  local_gptr_options(cache_commit = list(s1 = TRUE, s2 = FALSE))
  s1_cache_salt()
  expect_false(file.exists(ignore))
})

test_that("cache files contain neither the input nor the question text (IC-70)", {
  dir = s1_fresh(gptr = TRUE)
  salt = s1_cache_salt()
  q = noul_q()
  state = list(text = "Patient 0042 reported chest pain on 2026-09-01.")
  key = s1_cache_keys(salt, "offline:judge", "judge/judge-s1", q, list(state))
  s1_cache_put(key, s1_cache_record(key, list(type = "noul", prob = 0.4), "judge-s1-1.0",
                                    "judge-s1", q, state, salt, list(input = 50, output = 1)))
  path = file.path(dir, ".gptr", "cache", "s1", substr(key, 1L, 2L), paste0(key, ".json"))
  text = read_utf8(path)$text
  expect_false(grepl("chest pain", text, fixed = TRUE))
  expect_false(grepl("Patient 0042", text, fixed = TRUE))
  expect_false(grepl("Is it a dog", text, fixed = TRUE))
  rec = json_decode(text)
  expect_identical(rec$input_hash, hash_sha256(paste0(salt, canonical_json(state))))
  expect_identical(rec$question_sha256,
                   hash_sha256(canonical_json(list(question = q$instructions, type = q$type,
                                                   criteria = q$criteria))))
  expect_setequal(names(rec), c("key", "model", "alias", "question_sha256", "input_hash",
                                "answer", "prob", "probabilities", "confidence", "date", "usage"))
})

test_that("keys are schema 2, salted, and change with the input, question and model", {
  st = list(list(text = "a"))
  k = s1_cache_keys("s", "e", "m", noul_q(), st)
  want = list(schema = 2L, salt = "s", endpoint = "e", model = "m",
              question = noul_q()$instructions, type = "noul", criteria = NULL, input = st[[1]])
  expect_identical(k, hash_sha256(canonical_json(want)))
  expect_false(identical(k, s1_cache_keys("t", "e", "m", noul_q(), st)))
  expect_false(identical(k, s1_cache_keys("s", "e", "m2", noul_q(), st)))
  expect_false(identical(k, s1_cache_keys("s", "e", "m", choice_q(), st)))
  expect_false(identical(k, s1_cache_keys("s", "e", "m", noul_q(), list(list(text = "b")))))
  two = s1_cache_keys("s", "e", "m", noul_q(), list(list(text = "a"), list(text = "b")))
  expect_length(two, 2L)
  expect_identical(two[1], k)
})

test_that("a hit touches the record's modification time", {
  dir = s1_fresh(gptr = TRUE)
  key = s1_cache_keys(s1_cache_salt(), "e", "m", noul_q(), list(list(text = "x")))
  s1_cache_put(key, list(key = key, answer = 0.5))
  path = file.path(dir, ".gptr", "cache", "s1", substr(key, 1L, 2L), paste0(key, ".json"))
  Sys.setFileTime(path, as.POSIXct("2020-01-01", tz = "UTC"))
  s1_cache_get(key)
  expect_gt(as.numeric(file.mtime(path)), as.numeric(as.POSIXct("2025-01-01", tz = "UTC")))
})

test_that("records round-trip noul, choice and score answers", {
  noul = list(type = "noul", prob = 0.3)
  rec = s1_cache_record("k", noul, "m", "a", noul_q(), list(), "", list())
  expect_identical(s1_cache_answer(rec, noul_q()), noul)
  q = choice_q()
  ch = list(type = "choice", choice = "cat", probabilities = c(dog = 0.2, cat = 0.8),
            confidence = 0.6)
  back = s1_cache_answer(json_decode(json_encode(s1_cache_record("k", ch, "m", "a", q, list(), "",
                                                                 list()))), q)
  expect_identical(back, ch)
  sq = list(type = "score", instructions = "How?", criteria = list("low", "mid", "high"))
  # IC-74 (07 section 3): a canonical score carries the legend of its levels; the record does not
  # store it (level descriptions are question text, IC-70) and the answer rebuilds it
  sc = list(type = "score", score = 1.5, probabilities = c(`0` = 0, `1` = 0.5, `2` = 0.5),
            confidence = 0.5, legend = c(`0` = "low", `1` = "mid", `2` = "high"))
  text = json_encode(s1_cache_record("k", sc, "m", "a", sq, list(), "", list()))
  expect_false(grepl("high", text, fixed = TRUE))
  back = s1_cache_answer(json_decode(text), sq)
  expect_identical(back, sc)
})

# ---- IC-74 (07-local-ollama.md sections 2-4) ----------------------------------------------------

clef_model = function(...) {
  utils::modifyList(list(provider = "ollama", id = "clef-flash", ref = "ollama/clef-flash",
                         type = "classifier", api = "ollama-system-one",
                         digest = strrep("a", 64L), server_version = "0.35.1",
                         locality = "local"),
                    list(...))
}
clef_endpoint = "http://127.0.0.1:11434/v1/systemone"

test_that("keys carry the adapter, the model digest and the server version (IC-74)", {
  st = list(list(text = "a"))
  id = s1_cache_identity(clef_model())
  expect_identical(id, list(adapter = "ollama-system-one", digest = strrep("a", 64L),
                            server_version = "0.35.1"))
  k = s1_cache_keys("s", clef_endpoint, "ollama/clef-flash", noul_q(), st, id)
  want = list(schema = 2L, salt = "s", endpoint = clef_endpoint, model = "ollama/clef-flash",
              question = noul_q()$instructions, type = "noul", criteria = NULL, input = st[[1]],
              identity = id)
  expect_identical(k, hash_sha256(canonical_json(want)))
  expect_false(identical(k, s1_cache_keys("s", clef_endpoint, "ollama/clef-flash", noul_q(), st)))
  keys_of = function(model) {
    s1_cache_keys("s", clef_endpoint, "ollama/clef-flash", noul_q(), st, s1_cache_identity(model))
  }
  # new weights under the same tag, a new server, another adapter: other keys
  expect_false(identical(k, keys_of(clef_model(digest = strrep("b", 64L)))))
  expect_false(identical(k, keys_of(clef_model(server_version = "0.36.0"))))
  expect_false(identical(k, keys_of(clef_model(api = "typesafe-system-one"))))
  expect_identical(k, keys_of(clef_model(locality = "unknown")))
  # Jev: no digest and no server version; the alias stays the key (contract 11.9)
  jev = list(provider = "typesafe", id = "jev-latest", ref = "typesafe/jev-latest",
             type = "classifier", api = "typesafe-system-one")
  expect_identical(s1_cache_identity(jev), list(adapter = "typesafe-system-one"))
  expect_identical(s1_cache_identity(list()), stats::setNames(list(), character()))
  expect_error(s1_cache_identity("ollama/clef-flash"), class = "gptr_error_invalid_argument")
  expect_error(s1_cache_keys("s", "e", "m", noul_q(), st, identity = "x"),
               class = "gptr_error_invalid_argument")
})

test_that("image bytes and MIME types are keyed in order and never stored (IC-74)", {
  dir = s1_fresh(gptr = TRUE)
  salt = s1_cache_salt()
  png = list(data = as.raw(c(0x89, 0x50, 0x4e, 0x47, 1:40)), mime = "image/png")
  jpg = list(data = as.raw(c(0xff, 0xd8, 0xff, 41:80)), mime = "image/jpeg")
  st = list(list(text = "a"))
  key_with = function(images) {
    s1_cache_keys(salt, clef_endpoint, "ollama/clef-flash", noul_q(), st,
                  s1_cache_identity(clef_model(), images))
  }
  id = s1_cache_identity(clef_model(), list(png, jpg))
  expect_identical(id$images, list(list(sha256 = hash_sha256(png$data), mime = "image/png"),
                                   list(sha256 = hash_sha256(jpg$data), mime = "image/jpeg")))
  k = key_with(list(png, jpg))
  edited = png
  edited$data[5L] = as.raw(0xee)
  webp = png
  webp$mime = "image/webp"
  expect_false(identical(k, key_with(list(jpg, png))))
  expect_false(identical(k, key_with(list(edited, jpg))))
  expect_false(identical(k, key_with(list(webp, jpg))))
  expect_false(identical(k, key_with(list(png))))
  expect_false(identical(k, key_with(NULL)))
  expect_identical(key_with(NULL), key_with(list()))
  expect_null(s1_cache_identity(clef_model(), list())$images)
  # list order is the request order: names are ignored and never reorder the key
  expect_identical(s1_cache_identity(clef_model(), list(front = png, back = jpg))$images,
                   id$images)
  expect_identical(key_with(list(front = png, back = jpg)), k)
  expect_false(identical(key_with(list(front = png, back = jpg)),
                         key_with(list(back = jpg, front = png))))
  # neither the identity nor the record holds image bytes or image digests
  b64 = jsonlite::base64_enc(png$data)
  expect_false(grepl(b64, canonical_json(id), fixed = TRUE))
  s1_cache_put(k, s1_cache_record(k, list(type = "noul", prob = 0.8), "clef-flash",
                                  "clef-flash", noul_q(), st[[1]], salt,
                                  list(input = 900, output = 1)))
  path = file.path(dir, ".gptr", "cache", "s1", substr(k, 1L, 2L), paste0(k, ".json"))
  text = read_utf8(path)$text
  expect_false(grepl(b64, text, fixed = TRUE))
  expect_false(grepl(hash_sha256(png$data), text, fixed = TRUE))
  expect_identical(s1_cache_get(k)$answer, 0.8)
  bad = list(list(data = "x", mime = "image/png"), list(data = png$data),
             list(data = raw(0), mime = "image/png"), list(data = png$data, mime = NA_character_))
  for (b in bad) {
    expect_error(s1_cache_identity(clef_model(), list(b)), class = "gptr_error_invalid_argument")
  }
  expect_error(s1_cache_identity(clef_model(), png), class = "gptr_error_invalid_argument")
})

test_that("an Ollama model without a digest gives answers the cache never keeps (IC-74)", {
  dir = s1_fresh(gptr = TRUE)
  salt = s1_cache_salt()
  states = list(list(text = "a"), list(text = "b"))
  for (digest in list(NULL, NA_character_, "")) {
    tag = clef_model()
    tag["digest"] = list(digest)
    id = s1_cache_identity(tag)
    expect_true(id$mutable)
    keys = s1_cache_keys(salt, clef_endpoint, "ollama/clef-flash", noul_q(), states, id)
    expect_identical(keys, c(NA_character_, NA_character_))
  }
  cache = file.path(dir, ".gptr", "cache", "s1")
  before = list.files(cache, recursive = TRUE, all.files = TRUE)
  rec = s1_cache_record(NA_character_, list(type = "noul", prob = 0.9), "clef-flash",
                        "clef-flash", noul_q(), states[[1]], salt, list(input = 5, output = 1))
  s1_cache_put(NA_character_, rec)
  expect_null(s1_cache_get(NA_character_))
  expect_identical(list.files(cache, recursive = TRUE, all.files = TRUE), before)
  # another api without a digest keeps its keys: an alias such as jev-latest stays cacheable
  jev = list(provider = "typesafe", id = "jev-latest", api = "typesafe-system-one")
  expect_null(s1_cache_identity(jev)$mutable)
  # an Ollama chat model (an emulation target) under a mutable tag is just as uncacheable; with
  # a digest it keys normally, and another provider's chat model without one stays cacheable
  chat = list(provider = "ollama", id = "qwen3:1.7b", ref = "ollama/qwen3:1.7b", type = "chat",
              api = "openai-completions", server_version = "0.35.1")
  id = s1_cache_identity(chat)
  expect_true(id$mutable)
  expect_identical(s1_cache_keys(salt, "http://127.0.0.1:11434/v1/chat/completions",
                                 "ollama/qwen3:1.7b", noul_q(), states, id),
                   c(NA_character_, NA_character_))
  chat$digest = strrep("c", 64L)
  expect_identical(s1_cache_identity(chat), list(adapter = "openai-completions",
                                                 digest = strrep("c", 64L),
                                                 server_version = "0.35.1"))
  expect_null(s1_cache_identity(list(provider = "openai", api = "openai-responses"))$mutable)
  # nothing reaches the memory cache either
  s1_fresh(gptr = FALSE)
  s1_cache_put(NA_character_, rec)
  expect_identical(ls(s1_cache_mem(), all.names = TRUE), character())
})

test_that("a choice key keeps the request order of the options (IC-74)", {
  st = list(list(text = "a"))
  flipped = choice_q()
  flipped$criteria = flipped$criteria[c("cat", "dog")]
  expect_false(identical(s1_cache_keys("s", "e", "m", choice_q(), st),
                         s1_cache_keys("s", "e", "m", flipped, st)))
  ch = list(type = "choice", choice = "cat", probabilities = c(dog = 0.2, cat = 0.8),
            confidence = 0.6)
  rec = json_decode(json_encode(s1_cache_record("k", ch, "m", "a", choice_q(), list(), "",
                                                list())))
  expect_identical(s1_cache_answer(rec, flipped)$probabilities, c(cat = 0.8, dog = 0.2))
})

test_that("unknown values stay unknown and invalid records are misses (IC-74)", {
  dir = s1_fresh(gptr = TRUE)
  salt = s1_cache_salt()
  q = choice_q()
  unknown = list(type = "choice", choice = "dog", probabilities = c(dog = NA_real_, cat = NA_real_),
                 confidence = NA_real_)
  key = s1_cache_keys(salt, "e", "m", q, list(list(text = "u")))
  s1_cache_put(key, s1_cache_record(key, unknown, "m-1", "m", q, list(text = "u"), salt,
                                    list(input = NA_real_)))
  path = file.path(dir, ".gptr", "cache", "s1", substr(key, 1L, 2L), paste0(key, ".json"))
  expect_false(grepl("\"NA\"", read_utf8(path)$text, fixed = TRUE))
  rec = s1_cache_get(key)
  expect_identical(rec$usage, list(input_tokens = NULL, output_tokens = NULL))
  expect_null(rec$prob)
  expect_null(rec$confidence)
  expect_identical(s1_cache_answer(rec, q), unknown)
  noul = s1_cache_record("k", list(type = "noul", prob = 0.5), "m", "a", noul_q(), list(), "",
                         list(input = NA_real_, output = 7))
  expect_identical(noul$usage, list(input_tokens = NULL, output_tokens = 7))
  expect_identical(s1_cache_record("k", list(type = "noul", prob = 0.5), "m", "a", noul_q(),
                                   list(), "", NULL)$usage,
                   list(input_tokens = NULL, output_tokens = NULL))
  # a record the question cannot have produced is a miss, never an answer
  ok = list(key = "k", answer = "cat", probabilities = list(dog = 0.2, cat = 0.8),
            confidence = 0.6)
  edit = function(...) {
    out = ok
    changes = list(...)
    out[names(changes)] = changes
    out
  }
  sq = list(type = "score", instructions = "How?", criteria = list("low", "mid", "high"))
  expect_identical(s1_cache_answer(ok, q)$choice, "cat")
  expect_null(s1_cache_answer(edit(answer = "bird"), q))
  expect_null(s1_cache_answer(edit(probabilities = list(dog = 0.9, cat = 0.8)), q))
  expect_null(s1_cache_answer(edit(probabilities = list(dog = 0.2, bird = 0.8)), q))
  expect_null(s1_cache_answer(edit(probabilities = list(dog = "x", cat = 0.8)), q))
  expect_null(s1_cache_answer(edit(probabilities = list(dog = 0.8, cat = 0.2)), q))
  expect_null(s1_cache_answer(edit(confidence = 1.5), q))
  expect_null(s1_cache_answer(list(answer = 1.7), noul_q()))
  expect_null(s1_cache_answer(list(answer = "yes"), noul_q()))
  expect_null(s1_cache_answer(list(answer = 0.4), q))
  expect_null(s1_cache_answer(list(answer = 1.9, probabilities = list(`0` = 0, `1` = 0.5,
                                                                      `2` = 0.5)), sq))
  expect_null(s1_cache_answer("0.5", noul_q()))
})

test_that("a file under another key or with broken JSON is a miss; a malformed key errors", {
  dir = s1_fresh(gptr = TRUE)
  keys = s1_cache_keys(s1_cache_salt(), "e", "m", noul_q(), list(list(text = "1"),
                                                                 list(text = "2")))
  s1_cache_put(keys[1], list(key = keys[1], answer = 0.5))
  path_of = function(k) {
    file.path(dir, ".gptr", "cache", "s1", substr(k, 1L, 2L), paste0(k, ".json"))
  }
  dir.create(dirname(path_of(keys[2])), recursive = TRUE, showWarnings = FALSE)
  file.copy(path_of(keys[1]), path_of(keys[2]))
  expect_null(s1_cache_get(keys[2]))
  write_atomic(path_of(keys[2]), "{not json")
  expect_null(s1_cache_get(keys[2]))
  expect_identical(s1_cache_get(keys[1])$answer, 0.5)
  for (k in list("../../salt", "k", NA, c(keys[1], keys[2]), 1)) {
    expect_error(s1_cache_get(k), class = "gptr_error_invalid_argument")
    expect_error(s1_cache_put(k, list()), class = "gptr_error_invalid_argument")
  }
  expect_error(s1_cache_swap(list()), class = "gptr_error_invalid_argument")
})
