# Live System 1 test against api.typesafe.ai (plan P13; opt-in with GPTR_LIVE_TESTS=true). The key
# is read only through gptr_env() from the maintainer's key file (conventions section 1; override
# the path with GPTR_JEV_KEY_FILE) and is never printed. About ten requests of about 300 input
# tokens at $0.042 per million: well below a cent.

test_that("live: Jev answers decisions, choices and scores through peter()", {
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"))
  skip_on_cran()
  key_file = Sys.getenv("GPTR_JEV_KEY_FILE", test_path("..", "..", ".secrets", "jev-key.env"))
  skip_if_not(file.exists(key_file), "no Jev key file")
  # "auto", not "live": live mode asks System 1 afresh and skips cache reads (ambiguity 6), and
  # the last call below must come from the cache; "auto" still lets misses reach the service.
  # The gptr.replay option (setup.R sets "replay") wins over GPTR_REPLAY, so both are set.
  withr::local_envvar(GPTR_REPLAY = "auto", TYPESAFE_API_KEY = NA,
                      R_USER_CONFIG_DIR = withr::local_tempdir())
  local_gptr_options(replay = "auto")
  # gptr_env() registers the key in the process vault, which provider credentials consult before
  # the environment: start from an empty vault, so the key file is the only Jev credential, and
  # forget the key when the test ends, so no later test finds it
  local_vault()
  gptr_env(key_file, quiet = TRUE)
  skip_if_not(nzchar(Sys.getenv("TYPESAFE_API_KEY")), "the key file holds no Jev key")
  local_project(gptr = FALSE)
  old = s1_cache_swap()
  withr::defer(s1_cache_swap(old))
  gptr_config(egress = list(typesafe = "ack"), .scope = "user")

  text = "A golden retriever puppy fetched the ball and wagged its tail."
  hit = if (peter("Does this text describe a dog?", text, model = jev)) "dog" else "other"
  expect_identical(hit, "dog")

  texts = c(dog = "A puppy chewed my shoe.", wolf = "A wolf howled at the moon.",
            car = "The car would not start.")
  d = peter("Does this text describe a dog?", texts, model = jev)
  expect_identical(class(d), c("gptr_decision", "gptr_s1", "logical"))
  expect_identical(names(d), names(texts))
  expect_true(d[["dog"]])
  expect_false(d[["car"]])
  expect_true(all(gptr_prob(d) >= 0 & gptr_prob(d) <= 1))
  expect_match(attr(d, "meta")$model, "^jev-")
  expect_identical(attr(d, "meta")$engine, "typesafe")
  # the three states are new to the cache, so each made one request, and every TypeSafe reply
  # carries x-typesafe-request-id (report 04): one id per state; all(nzchar()) alone would also
  # hold for no ids at all, since s1_dispatch() drops a reply's missing id
  ids = attr(d, "meta")$request_ids
  expect_true(length(ids) == length(texts) && all(nzchar(ids)))
  # IC-74 provenance (07-local-ollama.md section 3): the hosted service, through its own adapter
  expect_identical(attr(d, "meta")[c("provider", "api", "execution")],
                   list(provider = "typesafe", api = "typesafe-system-one", execution = "native"))

  animal = peter("Which animal does the text describe?", texts, model = jev,
                choices = c("dog", "wolf", "none"))
  expect_identical(unname(animal[["dog"]] == "dog"), TRUE)
  expect_identical(colnames(gptr_prob(animal, "probabilities")), c("dog", "wolf", "none"))
  mood = peter("How positive is the text?", texts, model = jev,
              levels = c("negative", "neutral", "positive"))
  expect_true(all(as.double(mood) >= 0 & as.double(mood) <= 2))

  again = peter("Does this text describe a dog?", texts, model = jev)
  expect_true(all(attr(again, "meta")$cached))

  key = Sys.getenv("TYPESAFE_API_KEY")
  shown = paste(c(utils::capture.output(print(d)), json_encode(attr(d, "meta"))), collapse = "\n")
  expect_false(grepl(key, shown, fixed = TRUE))
})
