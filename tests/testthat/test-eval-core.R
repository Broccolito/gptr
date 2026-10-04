test_that("rng_seeds derives a valid L'Ecuyer vector from a key without the RNG", {
  env = globalenv()
  before = get0(".Random.seed", envir = env, inherits = FALSE)
  s = rng_seeds("s0123456789")
  expect_type(s, "integer")
  expect_length(s, 7L)
  expect_equal(s[1], 10407L)
  expect_identical(rng_seeds("s0123456789"), s)
  expect_false(identical(rng_seeds("s0123456789:b"), s))
  expect_identical(get0(".Random.seed", envir = env, inherits = FALSE), before)
})

test_that("rng_swap keeps the user's .Random.seed and advances the agent's stream", {
  withr::local_seed(42)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  st1 = new.env()
  st1$id = "s0123456789"
  x1 = rng_swap(st1, stats::runif(3))
  expect_identical(get(".Random.seed", envir = env), before)
  expect_equal(st1$seed[1], 10407L)
  st2 = new.env()
  st2$id = "s0123456789"
  expect_identical(rng_swap(st2, stats::runif(3)), x1)
  expect_false(identical(rng_swap(st2, stats::runif(3)), x1))
  expect_identical(stats::runif(1), withr::with_seed(42, stats::runif(1)))
})

test_that("rng_swap removes .Random.seed again when the user had none", {
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  withr::defer({
    if (!is.null(saved)) env[[".Random.seed"]] = saved
  })
  if (!is.null(saved)) rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s1"
  x = rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  expect_true(is.numeric(x))
  expect_equal(st$seed[1], 10407L)
  expect_error(rng_swap(list(), 1), class = "gptr_error_invalid_argument")
})

test_that("rng_swap leaves R's generator kind as it found it when the user had no seed", {
  env = globalenv()
  withr::local_preserve_seed()
  set.seed(42)
  ref = stats::runif(1)
  rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s2"
  rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

# Added beyond the plan's blocks (P09 Task 7 evidence in dev/progress/P09.md).

test_that("rng_seeds matches IC-61's derivation word for word", {
  # Reference vectors computed independently (Python hashlib): the first 24 bytes of
  # sha256(key) as six big-endian 32-bit words, three modulo m1 and three modulo m2, in
  # two's complement. Pinned so that reproducible streams (.opts$seed) stay stable.
  expect_identical(
    rng_seeds("s0123456789"),
    c(10407L, -146143283L, 119445096L, -844057359L, 1765153392L, 252959532L, -1668458951L)
  )
  expect_identical(
    rng_seeds("7:worker"),
    c(10407L, -1139394146L, 1575112895L, 1638773665L, -378824907L, -253925496L, 1846536792L)
  )
  s = rng_seeds("s0123456789:b")
  u = ifelse(is.na(s[-1L]), 2147483648, ifelse(s[-1L] < 0L, s[-1L] + 4294967296, s[-1L]))
  expect_true(all(u[1:3] < 4294967087))
  expect_true(all(u[4:6] < 4294944443))
})

test_that("rng_seeds stores the word 2^31 as NA silently and never yields an all-zero group", {
  local_mocked_bindings(hash_sha256 = function(x) {
    paste0(strrep("80000000", 3L), strrep("00000000", 3L), strrep("0", 16L))
  })
  s = expect_no_warning(rng_seeds("k"))
  expect_identical(s, c(10407L, NA, NA, NA, 1L, 0L, 0L))
  local_mocked_bindings(hash_sha256 = function(x) {
    paste0("ffffff2f", "00000000", "00000000", "ffffa6bb", "00000001", "7fffffff",
           strrep("0", 16L))
  })
  expect_identical(rng_seeds("k"), c(10407L, 1L, 0L, 0L, 0L, 1L, 2147483647L))
})

test_that("a vector with NA words is a valid, reproducible stream for R", {
  withr::local_seed(7)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  seed = c(10407L, NA, NA, NA, 1L, 0L, 0L)
  st1 = new.env()
  st1$seed = seed
  st2 = new.env()
  st2$seed = seed
  a = expect_no_warning(rng_swap(st1, stats::runif(2)))
  expect_identical(rng_swap(st2, stats::runif(2)), a)
  expect_identical(get(".Random.seed", envir = env), before)
})

test_that("rng_swap restores the user's seed after an error and keeps the advanced stream", {
  withr::local_seed(11)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  st = new.env()
  st$id = "s-err"
  expect_error(rng_swap(st, {
    stats::runif(1)
    stop("boom")
  }), "boom")
  expect_identical(get(".Random.seed", envir = env), before)
  expect_equal(st$seed[1], 10407L)
  expect_false(identical(st$seed, rng_seeds("s-err")))
  ref = new.env()
  ref$id = "s-err"
  first = rng_swap(ref, stats::runif(2))
  expect_identical(rng_swap(st, stats::runif(1)), first[2])
})

test_that("rng_swap derives the stream from the id, or from 'gptr' without one, and returns expr", {
  withr::local_seed(3)
  st = new.env()
  expect_identical(rng_swap(st, "value"), "value")
  expect_identical(st$seed, rng_seeds("gptr"))
  st2 = new.env()
  st2$id = "3:worker"
  expect_identical(rng_swap(st2, 1L), 1L)
  expect_identical(st2$seed, rng_seeds("3:worker"))
})

test_that("rng_swap keeps a non-default generator kind when the user had no seed", {
  env = globalenv()
  withr::local_preserve_seed()
  old = RNGkind("Knuth-TAOCP-2002")
  withr::defer(RNGkind(old[1L], old[2L], old[3L]))
  set.seed(42)
  ref = stats::runif(1)
  rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s3"
  rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  expect_equal(st$seed[1], 10407L)
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

# Review round 1: the branch where the user had a seed.

test_that("rng_swap leaves R's generator kind as it found it when the user had a seed", {
  # R keeps the kind internally; the restored vector alone left L'Ecuyer-CMRG in force, so a
  # user who then removed .Random.seed drew other numbers after set.seed(42).
  env = globalenv()
  withr::local_preserve_seed()
  set.seed(42)
  ref = stats::runif(1)
  set.seed(1)
  before = get(".Random.seed", envir = env)
  st = new.env()
  st$id = "s5"
  rng_swap(st, stats::runif(1))
  expect_identical(get(".Random.seed", envir = env), before)
  rm(list = ".Random.seed", envir = env)
  set.seed(42)
  expect_identical(stats::runif(1), ref)
  rm(list = ".Random.seed", envir = env)
  rng_swap(st, stats::runif(1))
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})

test_that("rng_swap restores a .Random.seed that R would reject, silently and identically", {
  env = globalenv()
  withr::local_preserve_seed()
  withr::defer({
    if (exists(".Random.seed", envir = env, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = env)
    }
  })
  st = new.env()
  st$id = "s6"
  bad = list(c(10403L, 1L, 2L), c(1.5, 2), 10403L, c(NA_integer_, 1L))
  for (b in bad) {
    env[[".Random.seed"]] = b
    expect_no_warning(rng_swap(st, stats::runif(1)))
    expect_identical(get(".Random.seed", envir = env), b)
  }
})
