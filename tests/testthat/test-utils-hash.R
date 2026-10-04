# Hashes, canonical JSON, ids, seed preservation, ports and fingerprints (Task 8); the
# copy-safety harness self-test (Task 17).

test_that("hash_sha256() hashes UTF-8 bytes, vectorised, and raw vectors", {
  expect_identical(
    hash_sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
  expect_identical(hash_sha256(c("abc", NA))[2], NA_character_)
  expect_identical(hash_sha256(charToRaw("abc")), hash_sha256("abc"))
  expect_identical(hash_sha256("caf\xc3\xa9"), hash_sha256("caf\u00e9"))
  expect_identical(hash_sha256("caf\u00e9"), hash_sha256(charToRaw("caf\u00e9")))
})

test_that("hash_xxh128() and hash_file() are 32-hex rlang hashes", {
  expect_match(hash_xxh128(mtcars), "^[0-9a-f]{32}$")
  file = withr::local_tempfile()
  writeLines("a", file)
  expect_match(hash_file(file), "^[0-9a-f]{32}$")
})

test_that("canonical_json() sorts keys at every level", {
  x = list(b = 1, a = list(d = "x", c = list()), B = TRUE, e = json_obj())
  expect_identical(canonical_json(x), "{\"B\":true,\"a\":{\"c\":[],\"d\":\"x\"},\"b\":1,\"e\":{}}")
})

test_that("canonical_json() gives the same bytes under LC_ALL=C and en_US.UTF-8", {
  x = list(zeta = "caf\u00e9", Alpha = list(beta = 1.5, alpha = c("\u4e2d", "b")), `_x` = NULL)
  old = c(LC_COLLATE = Sys.getlocale("LC_COLLATE"), LC_CTYPE = Sys.getlocale("LC_CTYPE"))
  withr::defer({
    Sys.setlocale("LC_COLLATE", old[["LC_COLLATE"]])
    Sys.setlocale("LC_CTYPE", old[["LC_CTYPE"]])
  })
  out = character()
  for (locale in c("C", "en_US.UTF-8")) {
    ok = suppressWarnings(nzchar(Sys.setlocale("LC_COLLATE", locale)) &&
                            nzchar(Sys.setlocale("LC_CTYPE", locale)))
    if (ok) out[locale] = canonical_json(x)
  }
  skip_if(length(out) < 2L, "the C and en_US.UTF-8 locales are not both available")
  expect_identical(charToRaw(out[["C"]]), charToRaw(out[["en_US.UTF-8"]]))
  expect_identical(Encoding(out[["C"]]), "UTF-8")
})

test_that("ids have the documented shapes (IC-20)", {
  expect_match(id_new("s", 10L), "^s[0-9a-f]{10}$")
  expect_match(id_new("q", 12L), "^q[0-9a-f]{12}$")
  expect_false(identical(id_new(), id_new()))
  expect_match(id_entry(), "^[0-9a-f]{8}$")
  block = id_block()
  expect_match(block, "^[0-9a-f]{6}$")
  expect_match(block, "[a-f]")
  taken = character()
  for (i in 1:200) taken = c(taken, id_block(taken))
  expect_false(anyDuplicated(taken) > 0)
})

test_that(".Random.seed is identical before and after 1,000 id generations (IC-61)", {
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  for (i in 1:1000) id_new("x", 12L)
  invisible(id_entry())
  invisible(id_block())
  invisible(port_candidates())
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that("with_seed_preserved() restores or removes .Random.seed", {
  withr::local_seed(1)
  before = get(".Random.seed", envir = globalenv())
  expect_identical(with_seed_preserved({
    stats::runif(3)
    "value"
  }), "value")
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  rm(".Random.seed", envir = globalenv())
  with_seed_preserved(stats::runif(1))
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})

test_that("with_seed_preserved(httpuv::randomPort()) leaves .Random.seed unchanged (IC-61)", {
  skip_if_not_installed("httpuv")
  withr::local_seed(7)
  before = get(".Random.seed", envir = globalenv())
  port = with_seed_preserved(httpuv::randomPort())
  expect_true(is.numeric(port))
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that("port_candidates() gives distinct RNG-free ports in 49152-65535", {
  ports = port_candidates(50L)
  expect_length(ports, 50L)
  expect_false(anyDuplicated(ports) > 0)
  expect_true(all(ports >= 49152L & ports <= 65535L))
})

test_that("fingerprint() is stable, sensitive to sampled values and cheap on ALTREP", {
  x = as.numeric(1:1000)
  expect_identical(fingerprint(x), fingerprint(x))
  y = x
  y[1] = 0
  expect_false(identical(fingerprint(x), fingerprint(y)))
  expect_match(fingerprint(mtcars), "^[0-9a-f]{64}$")
  big = 1:1e9
  elapsed = system.time(fingerprint(big))[["elapsed"]]
  expect_lt(elapsed, 5)
  df = data.frame(a = 1:3, b = c("x", "y", "z"))
  expect_false(identical(fingerprint(df), fingerprint(transform(df, a = a + 1L))))
  expect_match(fingerprint(new.env()), "^[0-9a-f]{64}$")
})
