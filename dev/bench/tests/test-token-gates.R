# Every gate of architecture 12.7 on P07's golden-transcript runner (plan P24; IC-73; 05 P24
# acceptance 1 and 4). P07's dev/bench/tokens/run.R owns the gates; these tests prove that each
# one trips just above its tolerance and passes at it, that the committed baseline covers every
# fixture, that the replay is fast and independent of the machine's <r_env>, and that
# `run.R --check` exits non-zero on a regression.

tokens_dir = file.path(bench_root(), "dev", "bench", "tokens")
standins_dir = file.path(bench_root(), "tests", "testthat", "fixtures", "bench")
gate_fixtures = sub("[.]json$", "", sort(list.files(file.path(tokens_dir, "fixtures"),
                                                     pattern = "[.]json$")))

# P07's runner as functions: sourcing defines them; bench_main() runs only from Rscript.
# GPTR_BENCH_RUNNER points the tests at another copy (the red step uses a loosened one).
load_runner = function() {
  env = new.env(parent = globalenv())
  sys.source(Sys.getenv("GPTR_BENCH_RUNNER", file.path(tokens_dir, "run.R")), envir = env)
  env
}

# Architecture 12.7: prefix +2%, input and output totals +5%, request count and image tokens +0,
# catalogs +5%, describer facts no loss.
gate_tolerance = c(prefix = 0.02, input_total = 0.05, output_total = 0.05, requests = 0,
                   image_tokens = 0, catalog = 0.05)

gate_base = function(case = "fx") {
  data.frame(case = case, requests = 4, prefix = 2750, input_total = 10000, output_total = 400,
             image_tokens = 532, catalog = 542, facts = 10, est_prefix = 2930,
             est_input_total = 10500, stringsAsFactors = FALSE)
}

test_that("P07's runner carries exactly the tolerances of architecture 12.7", {
  r = load_runner()
  expect_identical(r$bench_tolerance, gate_tolerance)
  expect_identical(r$bench_columns, c("case", "requests", "prefix", "input_total",
                                      "output_total", "image_tokens", "catalog", "facts",
                                      "est_prefix", "est_input_total"))
})

test_that("each gate passes at its tolerance and raises gptr_error_token_regression above it", {
  bench_test_load_gptr()
  r = load_runner()
  base = gate_base()
  for (m in names(gate_tolerance)) {
    at = base
    at[[m]] = base[[m]] * (1 + gate_tolerance[[m]])
    expect_true(r$bench_compare(at, base), info = m)
    over = base
    over[[m]] = at[[m]] + 1
    cnd = tryCatch(r$bench_compare(over, base), gptr_error_token_regression = function(e) e)
    expect_s3_class(cnd, "gptr_error_token_regression")
    expect_identical(cnd$fixture, "fx", info = m)
    expect_identical(cnd$metric, m)
    expect_equal(cnd$baseline, base[[m]], info = m)
    expect_equal(cnd$value, over[[m]], info = m)
    expect_match(conditionMessage(cnd), paste0("fx: ", m, " "), fixed = TRUE)
  }
})

test_that("a lost describer fact fails, while more facts and smaller totals pass", {
  bench_test_load_gptr()
  r = load_runner()
  base = gate_base()
  lost = base
  lost$facts = base$facts - 1
  cnd = tryCatch(r$bench_compare(lost, base), gptr_error_token_regression = function(e) e)
  expect_s3_class(cnd, "gptr_error_token_regression")
  expect_identical(cnd$metric, "facts")
  better = base
  better[names(gate_tolerance)] = 0
  better$facts = base$facts + 5
  expect_true(r$bench_compare(better, base))
})

test_that("a fixture without a baseline row fails instead of passing unmeasured", {
  bench_test_load_gptr()
  r = load_runner()
  cnd = tryCatch(r$bench_compare(gate_base("new-fixture"), gate_base()),
                 gptr_error_token_regression = function(e) e)
  expect_s3_class(cnd, "gptr_error_token_regression")
  expect_match(conditionMessage(cnd), "new-fixture: no baseline row", fixed = TRUE)
})

test_that("the committed baseline has exactly one row per golden transcript", {
  base = utils::read.csv(file.path(tokens_dir, "baseline.csv"), stringsAsFactors = FALSE)
  expect_identical(names(base), load_runner()$bench_columns)
  expect_false(anyDuplicated(base$case) > 0L)
  expect_setequal(base$case, gate_fixtures)
  expect_true(all(base$requests >= 1 & base$prefix > 0 & base$input_total > base$prefix))
})

# The runner with the stand-ins sourced (`r`, `standins`) and a fixture reader, replaying as
# bench_main() does in a temporary user home until `env` returns
local_replay = function(env = parent.frame()) {
  home = withr::local_tempdir(.local_envir = env)
  withr::local_envvar(GPTR_REPLAY = "replay", R_USER_CONFIG_DIR = file.path(home, "config"),
                      R_USER_DATA_DIR = file.path(home, "data"),
                      R_USER_CACHE_DIR = file.path(home, "cache"), .local_envir = env)
  r = load_runner()
  sys.source(file.path(standins_dir, "standins.R"), envir = r)
  pb = jsonlite::fromJSON(file.path(standins_dir, "prefix-baseline.json"), simplifyVector = FALSE)
  list(r = r, standins = pb$standins, fixture = function(id) {
    jsonlite::fromJSON(file.path(tokens_dir, "fixtures", paste0(id, ".json")),
                       simplifyVector = FALSE)
  })
}

# The tokenizer is replaced by a character count: the replay tests measure the replay itself
# (fake provider, context assembly, request building), not rtiktoken's encoder construction.
char_tok = function(x) if (is.null(x) || !nzchar(x)) 0 else nchar(x, "chars") / 4

test_that("every golden transcript replays offline in under 5 s (05 P24 acceptance 1)", {
  bench_test_load_gptr()
  rp = local_replay()
  t0 = proc.time()[["elapsed"]]
  res = do.call(rbind, lapply(gate_fixtures, function(id) {
    rp$r$bench_case(rp$fixture(id), rp$standins, char_tok)
  }))
  secs = proc.time()[["elapsed"]] - t0
  expect_setequal(res$case, gate_fixtures)
  expect_true(all(res$requests >= 1))
  expect_lt(secs, 5)
})

test_that("a golden transcript's prefix does not depend on the machine's <r_env> (CI-18)", {
  bench_test_load_gptr()
  rp = local_replay()
  fx = rp$fixture("ns02-mixed-model")
  here = rp$r$bench_case(fx, rp$standins, char_tok)
  local_mocked_bindings(r_env_probe = function() "R 4.6.1, x86_64-pc-linux-gnu; 4 cores",
                        .package = "gptr")
  expect_identical(rp$r$bench_case(fx, rp$standins, char_tok)$prefix, here$prefix)
})

test_that("run.R --check exits 0 on the baseline and non-zero when a prefix grows over 2%", {
  skip_if_not_installed("pkgload")
  skip_if_not_installed("rtiktoken")
  skip_if_not_installed("processx")
  root = bench_root()
  shadow = withr::local_tempdir()
  for (f in c("DESCRIPTION", "NAMESPACE")) file.copy(file.path(root, f), shadow)
  for (d in c("R", "inst")) file.copy(file.path(root, d), shadow, recursive = TRUE)
  dir.create(file.path(shadow, "tests", "testthat", "fixtures"), recursive = TRUE)
  file.copy(file.path(root, "tests", "testthat", "fixtures", "bench"),
            file.path(shadow, "tests", "testthat", "fixtures"), recursive = TRUE)
  dir.create(file.path(shadow, "dev", "bench", "tokens", "fixtures"), recursive = TRUE)
  file.copy(file.path(tokens_dir, "run.R"), file.path(shadow, "dev", "bench", "tokens"))
  file.copy(file.path(tokens_dir, "fixtures", "ns02-mixed-model.json"),
            file.path(shadow, "dev", "bench", "tokens", "fixtures"))
  base = utils::read.csv(file.path(tokens_dir, "baseline.csv"), stringsAsFactors = FALSE)
  base = base[base$case == "ns02-mixed-model", , drop = FALSE]
  expect_identical(nrow(base), 1L)
  shadow_base = file.path(shadow, "dev", "bench", "tokens", "baseline.csv")
  run_check = function() {
    processx::run(file.path(R.home("bin"), "Rscript"),
                  c("--vanilla", file.path("dev", "bench", "tokens", "run.R"), "--check"),
                  wd = shadow, error_on_status = FALSE)
  }
  utils::write.csv(base, shadow_base, row.names = FALSE)
  ok = run_check()
  expect_identical(ok$status, 0L, info = ok$stderr)
  expect_match(ok$stderr, "OK: 4 static prefixes and 1 golden transcripts", fixed = TRUE)
  base$prefix = base$prefix * 0.97
  utils::write.csv(base, shadow_base, row.names = FALSE)
  bad = run_check()
  expect_false(identical(bad$status, 0L))
  expect_match(bad$stderr, "Token-efficiency regression:", fixed = TRUE)
  expect_match(bad$stderr, "ns02-mixed-model: prefix", fixed = TRUE)
})
