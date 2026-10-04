# Tests for R/s1-types.R (plan P13): the System 1 vectors, gptr_prob() and the model-layer access
# helpers (contract 5.2, 6.6, 7.13; architecture 5.6; IC-36; IC-74).

s1_dec = function() {
  new_gptr_decision(c(a = TRUE, b = FALSE, c = TRUE), prob = c(0.9, 0.2, 0.7),
                    meta = list(model = "jev-1.13.0", alias = "jev-latest", engine = "typesafe",
                                calibrated = TRUE, question = "q", date = "2026-09-29",
                                cached = c(FALSE, TRUE, FALSE)))
}
s1_cho = function() {
  p = rbind(c(0.81, 0.19, 0), c(0.1, 0.7, 0.2))
  new_gptr_choice(c(x = "liver", y = "lung"), levels = c("liver", "lung", "other"),
                  probabilities = p, confidence = c(0.72, 0.55),
                  meta = list(model = "jev-1.13.0", calibrated = TRUE, date = "2026-09-29"))
}
s1_sco = function() {
  p = rbind(c(0, 0.02, 0.98), c(0.5, 0.5, 0))
  new_gptr_score(c(1.98, 0.5), levels = c("Very negative", "Neutral", "Very positive"),
                 probabilities = p, confidence = c(0.97, 0.4), meta = list())
}

test_that("the three classes carry the contract's class vectors and base types", {
  expect_identical(class(s1_dec()), c("gptr_decision", "gptr_s1", "logical"))
  expect_identical(class(s1_cho()), c("gptr_choice", "gptr_s1", "character"))
  expect_identical(class(s1_sco()), c("gptr_score", "gptr_s1", "numeric"))
  expect_identical(typeof(s1_dec()), "logical")
  expect_identical(typeof(s1_cho()), "character")
  expect_identical(typeof(s1_sco()), "double")
  expect_identical(attr(s1_cho(), "s1_levels"), c("liver", "lung", "other"))
  expect_null(attr(s1_cho(), "levels"))
  expect_identical(colnames(attr(s1_cho(), "probabilities")), c("liver", "lung", "other"))
  expect_error(new_gptr_decision(TRUE, c(0.1, 0.2)), class = "gptr_error_internal")
})

test_that("decisions work in if, while, isTRUE, ifelse, table, sum and mean like bare vectors", {
  d = s1_dec()
  expect_identical(if (d[[1]]) "yes" else "no", "yes")
  expect_identical(if (d[["b"]]) "yes" else "no", "no")
  n = 0L
  k = 1L
  while (d[[k]]) {
    n = n + 1L
    k = k + 1L
  }
  expect_identical(n, 1L)
  expect_true(isTRUE(d[[1]]))
  expect_false(isTRUE(d[[2]]))
  expect_identical(ifelse(d, "y", "n"), c(a = "y", b = "n", c = "y"))
  expect_identical(as.vector(table(d)), c(1L, 2L))
  expect_identical(sum(d), 2L)
  expect_equal(mean(d), 2 / 3)
  expect_identical(as.vector(d), c(TRUE, FALSE, TRUE))
})

test_that("[ and [[ subset the values and every per-element attribute", {
  d = s1_dec()
  s = d[c("c", "a")]
  expect_s3_class(s, "gptr_decision")
  expect_identical(names(s), c("c", "a"))
  expect_identical(attr(s, "prob"), c(0.7, 0.9))
  expect_identical(attr(s, "meta")$cached, c(FALSE, FALSE))
  one = d[[2]]
  expect_identical(length(one), 1L)
  expect_null(names(one))
  expect_identical(attr(one, "prob"), 0.2)
  ch = s1_cho()[2]
  expect_identical(unname(attr(ch, "probabilities")[1, "lung"]), 0.7)
  expect_identical(attr(ch, "confidence"), 0.55)
  expect_error(d[[5]], class = "gptr_error_invalid_argument")
})

test_that("[<- keeps the class for same-kind or bare base values and degrades otherwise", {
  d = s1_dec()
  d2 = d
  d2[2] = d[1]
  expect_s3_class(d2, "gptr_decision")
  expect_identical(attr(d2, "prob"), c(0.9, 0.9, 0.7))
  d3 = d
  d3[5] = TRUE
  expect_s3_class(d3, "gptr_decision")
  expect_identical(length(attr(d3, "prob")), 5L)
  expect_true(is.na(attr(d3, "prob")[4]))
  d4 = d
  d4[1] = "x"
  expect_false(inherits(d4, "gptr_s1"))
  expect_identical(d4[["a"]], "x")
  c1 = s1_cho()
  c1[[1]] = "other"
  expect_s3_class(c1, "gptr_choice")
  expect_true(all(is.na(attr(c1, "probabilities")[1, ])))
})

test_that("c, rep, rev, unique and sort follow the contract", {
  d = s1_dec()
  both = c(d, d)
  expect_s3_class(both, "gptr_decision")
  expect_identical(attr(both, "prob"), c(0.9, 0.2, 0.7, 0.9, 0.2, 0.7))
  expect_identical(attr(both, "meta")$cached, rep(c(FALSE, TRUE, FALSE), 2))
  mixed = c(d, s1_cho())
  expect_false(inherits(mixed, "gptr_s1"))
  r = rep(d, 2)
  expect_s3_class(r, "gptr_decision")
  expect_identical(length(attr(r, "prob")), 6L)
  rv = rev(d)
  expect_identical(attr(rv, "prob"), c(0.7, 0.2, 0.9))
  expect_false(inherits(unique(d), "gptr_s1"))
  expect_false(inherits(sort(d), "gptr_s1"))
})

test_that("Ops, Math and Summary return bare vectors", {
  ch = s1_cho()
  eq = ch == "liver"
  expect_identical(eq, c(x = TRUE, y = FALSE))
  expect_false(is.object(eq))
  expect_false(is.object(!s1_dec()))
  expect_false(is.object(round(s1_sco())))
  expect_identical(max(s1_sco()), 1.98)
  expect_true(any(s1_dec()))
})

test_that("as.logical, as.character and as.double give the bare vector", {
  expect_identical(as.logical(s1_dec()), c(a = TRUE, b = FALSE, c = TRUE))
  expect_identical(as.character(s1_cho()), c(x = "liver", y = "lung"))
  expect_identical(as.double(s1_sco()), c(1.98, 0.5))
})

test_that("format and print show values with probabilities and a dim footer", {
  expect_identical(format(s1_dec()),
                   c(a = "TRUE (p=0.90)", b = "FALSE (p=0.20)", c = "TRUE (p=0.70)"))
  expect_identical(unname(format(s1_cho())), c("liver (p=0.81)", "lung (p=0.70)"))
  expect_identical(format(s1_sco()), c("1.98 (conf 0.97)", "0.50 (conf 0.40)"))
  expect_identical(format(new_gptr_decision(NA, NA_real_)), "NA (p=NA)")
  testthat::local_reproducible_output(width = 80)
  expect_output(expect_invisible(print(s1_dec())), "jev-1.13.0 . calibrated . 2026-09-29",
                fixed = TRUE)
  expect_snapshot(print(s1_dec()))
  expect_snapshot(print(s1_cho()))
  expect_snapshot(print(new_gptr_score(numeric(), "a", NULL, numeric())))
})

test_that("as.data.frame gives one row per element with probability columns", {
  df = as.data.frame(s1_cho())
  expect_identical(names(df), c("value", "confidence", "p_liver", "p_lung", "p_other"))
  expect_identical(row.names(df), c("x", "y"))
  expect_identical(names(as.data.frame(s1_dec())), c("value", "prob"))
  expect_identical(names(as.data.frame(s1_sco())), c("value", "confidence", "p_0", "p_1", "p_2"))
})

test_that("as.data.frame and Summary take the generics' row.names and na.rm through ...", {
  d = s1_dec()
  expect_identical(row.names(as.data.frame(d, row.names = c("r1", "r2", "r3"))),
                   c("r1", "r2", "r3"))
  expect_identical(row.names(as.data.frame(d, c("p", "q", "r"))), c("p", "q", "r"))
  expect_identical(row.names(as.data.frame(d, optional = TRUE)), c("a", "b", "c"))
  expect_identical(names(data.frame(k = 1:3, s = d)), c("k", "s.value", "s.prob"))
  na = new_gptr_decision(c(TRUE, NA, TRUE), c(0.9, NA, 0.8))
  expect_identical(sum(na), NA_integer_)
  expect_identical(sum(na, na.rm = TRUE), 2L)
  expect_identical(range(s1_sco(), 3), c(0.5, 3))
  expect_identical(max(s1_sco(), na.rm = TRUE), 1.98)
})

test_that("gptr_prob() reads prob, confidence and probabilities", {
  d = s1_dec()
  expect_identical(gptr_prob(d), c(a = 0.9, b = 0.2, c = 0.7))
  expect_equal(gptr_prob(d, "confidence"), c(a = 0.8, b = 0.6, c = 0.4))
  m = gptr_prob(d, "probabilities")
  expect_identical(colnames(m), c("FALSE", "TRUE"))
  expect_equal(unname(m[1, ]), c(0.1, 0.9))
  expect_identical(gptr_prob(s1_cho()), c(x = 0.81, y = 0.7))
  expect_identical(gptr_prob(s1_sco()), c(0.97, 0.4))
  expect_identical(rownames(gptr_prob(s1_cho(), "probabilities")), c("x", "y"))
  expect_error(gptr_prob(TRUE), class = "gptr_error_invalid_argument")
  expect_error(gptr_prob(d, "odds"), class = "gptr_error_invalid_argument")
})

test_that("vctrs methods keep the probabilities through slicing and combining", {
  skip_if_not_installed("vctrs")
  d = s1_dec()
  s = vctrs::vec_slice(d, 3:2)
  expect_s3_class(s, "gptr_decision")
  expect_identical(attr(s, "prob"), c(0.7, 0.2))
  cc = vctrs::vec_c(d, d)
  expect_identical(attr(cc, "prob"), rep(c(0.9, 0.2, 0.7), 2))
  expect_identical(vctrs::vec_ptype2(d, TRUE), logical())
  expect_identical(unname(vctrs::vec_cast(d, logical())), c(TRUE, FALSE, TRUE))
  ch = vctrs::vec_slice(s1_cho(), 2L)
  expect_identical(attr(ch, "confidence"), 0.55)
  expect_identical(vctrs::vec_ptype_abbr(d), "s1_lgl")
})

test_that("unknown calibration prints as unknown and native metadata travels (IC-74)", {
  testthat::local_reproducible_output(width = 80)
  meta = list(model = "clef-flash", engine = "ollama", api = "ollama-system-one",
              execution = "native", locality = "local", model_digest = "sha256:0a1b",
              calibrated = NA, date = "2026-10-03", cached = c(FALSE, TRUE))
  d = new_gptr_decision(c(TRUE, FALSE), c(0.8, 0.3), meta = meta)
  expect_output(print(d), "clef-flash . calibration unknown . 2026-10-03", fixed = TRUE)
  expect_identical(attr(d[2], "meta")[c("engine", "api", "execution", "locality")],
                   meta[c("engine", "api", "execution", "locality")])
  expect_identical(attr(d[2], "meta")$cached, TRUE)
  no_claim = new_gptr_decision(TRUE, 0.6, meta = list(model = "clef", date = "2026-10-03"))
  expect_output(print(no_claim), "clef . calibration unknown . 2026-10-03", fixed = TRUE)
  emulated = new_gptr_decision(TRUE, 0.6, meta = list(model = "m", engine = "emulated:structured",
                                                      calibrated = FALSE, date = "2026-10-03"))
  expect_output(print(emulated), "m . uncalibrated . 2026-10-03", fixed = TRUE)
  sc = new_gptr_score(1.37, levels = c("low", "mid", "high"),
                      probabilities = rbind(c(0.1, 0.43, 0.47)), confidence = 0.21)
  expect_identical(as.double(sc), 1.37)
  expect_identical(format(sc), "1.37 (conf 0.21)")
  expect_identical(gptr_prob(sc), 0.21)
})

s1_jev = function() {
  new_gptr_decision(c(a = TRUE), 0.9, meta = list(model = "jev-1.13.0", engine = "typesafe",
                                                  calibrated = TRUE, date = "2026-09-29",
                                                  cached = FALSE))
}
s1_clef = function() {
  new_gptr_decision(c(b = FALSE), 0.3, meta = list(model = "clef-flash", engine = "ollama",
                                                   calibrated = NA, date = "2026-10-03",
                                                   cached = TRUE))
}
s1_emu = function() {
  new_gptr_decision(c(e = TRUE), 0.6, meta = list(model = "m", engine = "emulated:structured",
                                                  calibrated = FALSE, date = "2026-10-03",
                                                  cached = FALSE))
}

test_that("c() and [<- never claim calibration that a combined part lacks (IC-74)", {
  testthat::local_reproducible_output(width = 80)
  jev = s1_jev()
  clef = s1_clef()
  emu = s1_emu()
  calib = function(x) attr(x, "meta", exact = TRUE)$calibrated
  expect_identical(calib(c(jev, jev)), TRUE)
  expect_identical(calib(c(jev, clef)), NA)
  expect_identical(calib(c(clef, jev)), NA)
  expect_output(print(c(jev, clef)), "jev-1.13.0 . calibration unknown . 2026-09-29",
                fixed = TRUE)
  expect_identical(calib(c(jev, emu)), FALSE)
  expect_identical(calib(c(clef, emu)), FALSE)
  expect_output(print(c(jev, emu)), "jev-1.13.0 . uncalibrated . 2026-09-29", fixed = TRUE)
  expect_identical(calib(c(jev, new_gptr_decision(TRUE, 0.5))), NA)
  expect_null(calib(c(s1_sco(), s1_sco())))
  expect_identical(attr(c(jev, clef), "meta")$cached, c(FALSE, TRUE))
  j2 = jev
  j2[2] = clef
  expect_identical(calib(j2), NA)
  expect_output(print(j2), "calibration unknown", fixed = TRUE)
  j3 = c(jev, jev)
  j3[[2]] = emu
  expect_identical(calib(j3), FALSE)
  j4 = c(jev, jev)
  j4[2] = FALSE
  expect_identical(calib(j4), TRUE)
  j5 = jev
  j5[integer()] = clef
  expect_identical(calib(j5), TRUE)
})

test_that("[<- with NA subscripts assigns like base R and keeps the attributes aligned", {
  d = s1_dec()
  mask = new_gptr_decision(c(NA, TRUE, FALSE), c(NA, 0.8, 0.1))
  r = replace(d, mask, d[3])
  base = as.logical(d)
  base[as.logical(mask)] = TRUE
  expect_s3_class(r, "gptr_decision")
  expect_identical(as.logical(r), base)
  expect_identical(attr(r, "prob"), c(0.9, 0.7, 0.7))
  expect_identical(attr(r, "meta")$cached, c(FALSE, FALSE, FALSE))
  d2 = d
  d2[c(NA, 2L)] = d[3]
  expect_identical(attr(d2, "prob"), c(0.9, 0.7, 0.7))
  expect_identical(attr(d2, "meta")$cached, c(FALSE, FALSE, FALSE))
  d3 = d
  d3[c(NA, TRUE, FALSE)] = FALSE
  expect_identical(attr(d3, "prob"), c(0.9, NA, 0.7))
  expect_identical(attr(d3, "meta")$cached, c(FALSE, NA, FALSE))
  d4 = d
  d4[NA_character_] = d[2]
  expect_identical(names(d4), c("a", "b", "c", NA))
  expect_identical(attr(d4, "prob"), c(0.9, 0.2, 0.7, 0.2))
  expect_identical(attr(d4, "meta")$cached, c(FALSE, TRUE, FALSE, TRUE))
  ch = s1_cho()
  ch[c(NA, 2L)] = ch[1]
  expect_s3_class(ch, "gptr_choice")
  expect_identical(as.character(ch), c(x = "liver", y = "liver"))
  expect_identical(attr(ch, "probabilities")[2, ], attr(s1_cho(), "probabilities")[1, ])
  expect_identical(attr(ch, "confidence"), c(0.72, 0.72))
  jev = s1_jev()
  jev[NA] = s1_clef()
  expect_identical(as.logical(jev), c(a = TRUE))
  expect_identical(attr(jev, "meta")$calibrated, TRUE)
  expect_error({
    d5 = d
    d5[[NA_integer_]] = d[1]
  }, class = "gptr_error_invalid_argument")
  expect_error({
    d6 = d
    d6[[1:2]] = TRUE
  }, class = "gptr_error_invalid_argument")
})

test_that("cached stays per element through zero-length extension and mixed combining", {
  e = s1_dec()[0]
  e[2] = TRUE
  expect_identical(attr(e, "meta")$cached, c(NA, NA))
  expect_identical(attr(e, "prob"), c(NA_real_, NA_real_))
  plain = new_gptr_decision(c(p = TRUE), 0.5, meta = list(model = "m"))
  expect_identical(attr(c(s1_dec(), plain), "meta")$cached, c(FALSE, TRUE, FALSE, NA))
  expect_identical(attr(c(plain, s1_dec()), "meta")$cached, c(NA, FALSE, TRUE, FALSE))
  expect_null(attr(c(plain, plain), "meta")$cached)
  skip_if_not_installed("vctrs")
  v = vctrs::vec_c(e, s1_dec())
  expect_s3_class(v, "gptr_decision")
  expect_identical(attr(v, "meta")$cached, c(NA, NA, FALSE, TRUE, FALSE))
  expect_identical(attr(v, "prob"), c(NA, NA, 0.9, 0.2, 0.7))
  expect_identical(attr(vctrs::vec_c(s1_dec(), plain), "meta")$cached, c(FALSE, TRUE, FALSE, NA))
  w = vctrs::vec_c(plain, s1_dec())
  expect_identical(attr(w, "meta")$cached, c(NA, FALSE, TRUE, FALSE))
  expect_identical(attr(w, "prob"), c(0.5, 0.9, 0.2, 0.7))
  expect_null(attr(vctrs::vec_c(plain, plain), "meta")$cached)
  expect_null(attr(vctrs::vec_slice(s1_cho(), 2L), "meta")$cached)
  df1 = data.frame(k = 1L)
  df1$d = plain
  df2 = data.frame(k = 2:4)
  df2$d = s1_dec()
  rows = vctrs::vec_rbind(df1, df2)
  expect_s3_class(rows$d, "gptr_decision")
  expect_identical(attr(rows$d, "meta")$cached, c(NA, FALSE, TRUE, FALSE))
})

test_that("vctrs combining never claims calibration that a combined part lacks (IC-74)", {
  skip_if_not_installed("vctrs")
  testthat::local_reproducible_output(width = 80)
  calib = function(x) attr(x, "meta", exact = TRUE)$calibrated
  expect_identical(calib(vctrs::vec_c(s1_jev(), s1_jev())), TRUE)
  expect_identical(calib(vctrs::vec_c(s1_jev(), s1_clef())), NA)
  expect_identical(calib(vctrs::vec_c(s1_jev(), s1_emu())), FALSE)
  expect_identical(calib(vctrs::vec_c(s1_jev(), s1_clef(), s1_emu())), FALSE)
  expect_identical(calib(vctrs::vec_ptype2(s1_jev(), s1_clef())), NA)
  out = vctrs::vec_c(s1_jev(), s1_clef())
  expect_identical(attr(out, "prob"), c(0.9, 0.3))
  expect_identical(attr(out, "meta")$cached, c(FALSE, TRUE))
  expect_output(print(out), "jev-1.13.0 . calibration unknown . 2026-09-29", fixed = TRUE)
  df1 = data.frame(k = 1L)
  df1$d = s1_jev()
  df2 = data.frame(k = 2L)
  df2$d = s1_emu()
  rows = vctrs::vec_rbind(df1, df2)
  expect_s3_class(rows$d, "gptr_decision")
  expect_identical(calib(rows$d), FALSE)
})

# ---- Task 2: model-layer access for the System 1 area ------------------------------------------

priced_provider = function() {
  gptr_provider("pricey", api = "fake-classifier", type = "classifier", local = TRUE,
                offline = TRUE,
                models = list(list(id = "pricey-s1", type = "classifier",
                                   prices = data.frame(from = "2026-01-01", tier = "default",
                                                       input = 0.042, output = 0))))
}

test_that("s1_provider() passes specs through and looks ids up", {
  spec = priced_provider()
  expect_identical(s1_provider(spec), spec)
  off = gptr_register(spec)
  withr::defer(off())
  expect_identical(s1_provider("pricey")$id, "pricey")
  expect_null(s1_provider("no-such-provider"))
  expect_null(s1_provider(NA_character_))
  expect_null(s1_provider(42))
})

test_that("s1_model() resolves a provider spec to its first model record", {
  rec = s1_model(priced_provider())
  expect_identical(rec$provider, "pricey")
  expect_identical(rec$id, "pricey-s1")
  expect_identical(rec$type, "classifier")
  expect_identical(s1_adapter("fake-classifier")$api, "fake-classifier")
  expect_error(s1_adapter("no-such-api"), class = "gptr_error_not_available")
})

test_that("s1_cost() prices input tokens at the model's dated rate", {
  rec = s1_model(priced_provider())
  expect_equal(s1_cost(list(input = 1e6, output = 500), rec), 0.042)
  # IC-74 (07 section 5, D-015): missing usage remains unknown, never a zero-token request
  expect_identical(s1_cost(list(), rec), NA_real_)
})

test_that("s1_usage_log() appends one System 1 row to the process log", {
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  off = gptr_register(priced_provider())
  withr::defer(off())
  rec = s1_model("pricey/pricey-s1")
  n = nrow(usage_log())
  s1_usage_log(rec, "system-one", 300, 2, "q000000000001", NA_character_, Sys.time(), 0.2)
  log = usage_log()
  expect_identical(nrow(log), n + 1L)
  row = log[nrow(log), ]
  expect_identical(row$agent, "s1")
  expect_identical(row$route, "system-one")
  expect_identical(row$provider, "pricey")
  expect_equal(row$input, 300)
  expect_equal(row$cost, 300 * 0.042 / 1e6)
})

test_that("s1_default_ref() is the configured System 1 model, NULL without one", {
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  local_gptr_options(system1 = NULL)
  expect_null(s1_default_ref())
  local_gptr_options(system1 = "judge/judge-s1")
  expect_identical(s1_default_ref(), "judge/judge-s1")
})

test_that("s1_base_url(), s1_credential() and s1_stream() delegate to the model layer", {
  p = gptr_provider("based", api = "typesafe-system-one", type = "classifier",
                    base_url = "https://example.invalid/v1/")
  expect_identical(s1_base_url(p), "https://example.invalid/v1")
  expect_null(s1_credential(priced_provider()))
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done, run = NULL) {
    "t42"
  })
  expect_identical(s1_stream(list(), list(), list(), function(ev) NULL, function(msg) NULL), "t42")
})

# ---- Task 2, IC-74 (07-local-ollama.md sections 2, 2.1 and 5) -----------------------------------

clef_provider = function(id, base_url) {
  gptr_provider(id, api = "ollama-system-one", type = "classifier", base_url = base_url,
                models = list(list(id = "clef-flash", type = "classifier",
                                   api = "ollama-system-one")))
}

test_that("s1_model() keeps a model's own type and api on a mixed provider (IC-74)", {
  mixed = gptr_provider("mixedlocal", api = "openai-completions",
                        base_url = "http://127.0.0.1:11434/v1", local = TRUE,
                        models = list(list(id = "chatty"),
                                      list(id = "clef-flash", type = "classifier",
                                           api = "ollama-system-one")))
  off = gptr_register(mixed)
  withr::defer(off())
  clef = s1_model("mixedlocal/clef-flash")
  expect_identical(clef$type, "classifier")
  expect_identical(clef$api, "ollama-system-one")
  chat = s1_model("mixedlocal/chatty")
  expect_identical(chat$type, "chat")
  expect_identical(chat$api, "openai-completions")
})

test_that("s1_cost() keeps unknown tokens and prices unknown and a zero rate known (IC-74)", {
  rec = s1_model(priced_provider())
  expect_identical(s1_cost(list(input = NA, output = 2), rec), NA_real_)
  expect_identical(s1_cost(NULL, rec), NA_real_)
  free = s1_model(gptr_provider("free", api = "fake-classifier", type = "classifier",
                                local = TRUE, offline = TRUE,
                                models = list(list(id = "free-s1", type = "classifier",
                                                   prices = data.frame(from = "2026-01-01",
                                                                       tier = "default",
                                                                       input = 0, output = 0)))))
  expect_identical(s1_cost(list(input = 300, output = 2), free), 0)
  expect_identical(s1_cost(list(), free), 0)
  unpriced = s1_model(gptr_provider("unpriced", api = "fake-classifier", type = "classifier",
                                    offline = TRUE,
                                    models = list(list(id = "unpriced-s1", type = "classifier"))))
  expect_identical(s1_cost(list(input = 300, output = 2), unpriced), NA_real_)
})

test_that("s1_usage_log() keeps unknown tokens unknown and fills a missing request id (IC-74)", {
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  off = gptr_register(priced_provider())
  withr::defer(off())
  rec = s1_model("pricey/pricey-s1")
  n = nrow(usage_log())
  s1_usage_log(rec, "system-one", NA, NA, NA_character_, "s_local", Sys.time(), 0.1)
  s1_usage_log(rec, "emulated", NULL, NULL, NULL, NA_character_, Sys.time(), 0.3)
  log = usage_log()
  expect_identical(nrow(log), n + 2L)
  rows = log[n + 1:2, ]
  expect_identical(rows$route, c("system-one", "emulated"))
  expect_identical(rows$agent, c("s1", "s1"))
  expect_identical(rows$session, c("s_local", NA))
  expect_identical(rows$input, c(NA_real_, NA_real_))
  expect_identical(rows$output, c(NA_real_, NA_real_))
  expect_identical(rows$cost, c(NA_real_, NA_real_))
  expect_true(all(nzchar(rows$request_id)) && !anyNA(rows$request_id))
  expect_false(identical(rows$request_id[1], rows$request_id[2]))
  expect_equal(rows$seconds, c(0.1, 0.3))
})

test_that("s1_usage_log() refuses a malformed request id rather than replacing it (D-015)", {
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  off = gptr_register(priced_provider())
  withr::defer(off())
  rec = s1_model("pricey/pricey-s1")
  n = nrow(usage_log())
  bad = list(c("q000000000001", "q000000000002"), 42, list("q000000000001"))
  for (rid in bad) {
    expect_error(s1_usage_log(rec, "system-one", 300, 2, rid, NA_character_, Sys.time(), 0.1),
                 class = "gptr_error_invalid_argument")
  }
  expect_identical(nrow(usage_log()), n)
  # no reported id (empty string, logical NA) still gets a fresh one
  s1_usage_log(rec, "system-one", 300, 2, "", NA_character_, Sys.time(), 0.1)
  s1_usage_log(rec, "system-one", 300, 2, NA, NA_character_, Sys.time(), 0.1)
  rows = usage_log()[n + 1:2, ]
  expect_identical(nrow(rows), 2L)
  expect_match(rows$request_id, "^q[0-9a-f]{12}$")
})

test_that("s1_default_ref() offers a verified local classifier without a TypeSafe key (IC-74)", {
  local_mocked_bindings(model_key_present = function(id, vars) FALSE,
                        catalog_local_classifier = function() "ollama/clef-flash")
  local_gptr_options(system1 = NULL)
  expect_identical(s1_default_ref(), "ollama/clef-flash")
})

test_that("a keyless loopback classifier gets no credential, even beside a TypeSafe key (IC-74)", {
  withr::local_envvar(TYPESAFE_API_KEY = "test-placeholder-not-a-key")
  lp = clef_provider("lollama", "http://127.0.0.1:11434/")
  expect_null(s1_credential(lp))
  expect_identical(s1_base_url(lp), "http://127.0.0.1:11434")
  # the built-in loopback `ollama` record that hosts Clef needs no key either
  ollama = s1_provider("ollama")
  expect_null(s1_credential(ollama))
  expect_identical(s1_base_url(ollama), "http://127.0.0.1:11434/v1")
})

test_that("s1_preflight() and s1_prepare() check a model before any request (IC-74)", {
  local_mocked_bindings(catalog_ollama_discover = function(...) {
    stop("discovery must not run in this test")
  })
  spec = priced_provider()
  rec = s1_model(spec)
  expect_identical(s1_preflight(rec, spec), rec)
  lp = clef_provider("lollama", "http://127.0.0.1:11434")
  expect_error(s1_preflight(s1_model(lp), lp), class = "gptr_error_not_available")
  remote = clef_provider("rollama", "https://ollama.example.invalid")
  rclef = s1_model(remote)
  expect_error(s1_preflight(rclef, remote), class = "gptr_error_untrusted")
  expect_error(s1_preflight(rclef, remote, safety = list(ollama_local_only = FALSE)),
               class = "gptr_error_not_available")
  off = gptr_register(spec)
  withr::defer(off())
  expect_identical(s1_prepare("pricey/pricey-s1")$id, "pricey-s1")
  expect_error(s1_prepare("pricey/pricey-s1", safety = list(ollama_local_only = NA)),
               class = "gptr_error_invalid_argument")
})
