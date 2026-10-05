# Tests for R/s1-route.R (plan P13): states and the batch rule (Task 7), the classifier route
# core (Task 8), INFRA-18's acceptance tests through gptr() (Task 9; architecture 6.18) and the
# jev-router example (Task 11) (contract 6.1.1, 7.13; architecture 4.1.5; IC-47, IC-66, IC-69,
# IC-71).

source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

# ---- Task 7: states and the batch rule ----------------------------------------------------------

test_that("the batch rule gives one state per element or unnamed list item", {
  expect_identical(s1_states(c(a = "A puppy.", b = "A car."), "text"),
                   list(a = list(text = "A puppy."), b = list(text = "A car.")))
  expect_identical(s1_states(1:3, "n")[[3]], list(n = 3L))
  expect_identical(s1_states(c(NA, TRUE), "v")[[1]], list(v = NULL))
  expect_identical(s1_states(factor(c("x", "y")), "f")[[2]], list(f = "y"))
  expect_identical(s1_states(as.Date("2026-09-29"), "d"), list(list(d = "2026-09-29")))
  expect_identical(s1_states(list(1, "b"), "u"), list(list(u = 1), list(u = "b")))
  expect_identical(s1_states(list(a = 1, b = "x"), "cfg"), list(list(cfg = list(a = 1, b = "x"))))
  expect_identical(s1_states(NULL, "none"), list(list(none = NULL)))
  expect_identical(s1_states(character(), "e"), list())
  expect_identical(names(s1_states(c(x = 1, y = 2), "v", labels = c("p", "q"))), c("p", "q"))
})

test_that("a data frame gives one record per row and marks the split; I() keeps it whole", {
  df = data.frame(a = 1:2, b = c("u", "v"))
  st = s1_states(df, "row")
  expect_identical(st[[2]], list(row = list(a = 2L, b = "v")))
  expect_true(isTRUE(attr(st, "split")))
  expect_null(names(st))
  named = data.frame(a = 1:2, row.names = c("r1", "r2"))
  expect_identical(names(s1_states(named, "row")), c("r1", "r2"))
  expect_null(attr(s1_states(df[1, , drop = FALSE], "row"), "split"))
  whole = s1_states(I(df), "tab")
  expect_length(whole, 1L)
  expect_identical(whole[[1]]$tab, list(list(a = 1L, b = "u"), list(a = 2L, b = "v")))
})

test_that("matrices, environments and functions are one described state", {
  local_mocked_bindings(gptr_describe = function(x, budget = 150L, ...) {
    paste0("<", class(x)[1L], ">")
  })
  expect_identical(s1_states(matrix(1:4, 2), "m"), list(list(m = "<matrix>")))
  expect_identical(s1_states(new.env(), "e"), list(list(e = "<environment>")))
  expect_identical(s1_states(mean, "f"), list(list(f = "<function>")))
})

test_that("large values are described instead of sent, and long text is cut", {
  local_mocked_bindings(
    describe_binding = function(name, envir, budget = 150L) c("<numeric> 5000 values", name),
    gptr_describe = function(x, budget = 150L, ...) "<numeric> described"
  )
  e = new.env()
  e$big = I(seq_len(5000) / 7)
  inner = new.env(parent = e)
  st = s1_states_at(e$big, "big", name = "big", envir = inner)
  expect_identical(st[[1]]$big, "<numeric> 5000 values\nbig")
  el = s1_states(list(seq_len(5000) / 7, "short"), "item")
  expect_identical(el[[1]]$item, "<numeric> described")
  expect_identical(el[[2]]$item, "short")
  long = s1_states(strrep("a", 100001L), "t")[[1]]$t
  expect_true(endsWith(long, " [truncated]"))
  expect_identical(nchar(long), 100000L + nchar(" [truncated]"))
})

test_that("more states than gptr.s1_max_elements fail before any state is built", {
  local_gptr_options(s1_max_elements = 5L)
  err = expect_error(s1_states(as.character(1:6), "x"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "chunks", fixed = TRUE)
  expect_error(s1_states(data.frame(a = 1:6), "x"), class = "gptr_error_invalid_argument")
  expect_length(s1_states(as.character(1:5), "x"), 5L)
})

test_that("a session becomes at most gptr.s1_state_max characters of facts and answer", {
  local_mocked_bindings(session_data = function(s) {
    list(status = "error", reason = "timeout", last_text = strrep("word ", 1000),
         values = list(list(name = "fit", class = "lm")))
  })
  s = structure(new.env(), class = "gptr_session")
  txt = as_state(s, "session")
  expect_lte(nchar(txt), 2000L)
  expect_match(txt, "^Status: error \\(timeout\\)\nValue: fit <lm>\nAnswer: word word")
  expect_true(endsWith(txt, "..."))
  local_gptr_options(s1_state_max = 100L)
  expect_lte(nchar(as_state(s, "session")), 100L)
})

test_that("inputs combine element-wise and must share one length", {
  z = s1_zip(list(s1_part(c(x = 1, y = 2), "a"), s1_part("ctx", "b")))
  expect_identical(z$states, list(list(a = 1, b = "ctx"), list(a = 2, b = "ctx")))
  expect_identical(z$names, c("x", "y"))
  expect_identical(z$labels, c("a", "b"))
  expect_null(z$split)
  expect_error(s1_zip(list(s1_part(1:2, "a"), s1_part(1:3, "b"))),
               class = "gptr_error_invalid_argument")
  expect_error(s1_zip(list()), class = "gptr_error_invalid_argument")
  split = s1_zip(list(s1_part(data.frame(v = 1:2), "input", display = "diagnostics(fit)")))
  expect_identical(split$split, "diagnostics(fit)")
})

test_that("context labels become state keys", {
  expect_identical(s1_key_name("abstracts"), "abstracts")
  expect_identical(s1_key_name("samples$description"), "samples_description")
  expect_identical(s1_key_name("my.data"), "my_data")
  expect_identical(s1_key_name("diagnostics(fit)"), "input")
  expect_identical(s1_key_name(NULL), "input")
})

test_that("s1_inputs() reads symbols by name and adds the piped session last", {
  local_mocked_bindings(session_data = function(s) {
    list(status = "idle", reason = NULL, last_text = "All good.", values = list())
  })
  s = structure(new.env(), class = "gptr_session")
  call = s1_test_call("Q?", samples = c(a = "x", b = "y"), model = "judge/judge-s1", session = s)
  parts = s1_inputs(call)
  expect_identical(vapply(parts, function(p) p$label, ""), c("samples", "session"))
  expect_identical(parts[[1]]$states$a, list(samples = "x"))
  expect_identical(parts[[2]]$states, list(list(session = "Answer: All good.")))
})

# ---- Task 7 beyond the plan: the batch rule for further classes and the session cap ------------

test_that("date-time vectors give one state per element, POSIXlt as POSIXct", {
  lt = as.POSIXlt(c("2026-09-29 10:00:00", "2026-09-30 11:30:00"), tz = "UTC")
  st = s1_states(lt, "t")
  expect_identical(st, list(list(t = "2026-09-29 10:00:00"), list(t = "2026-09-30 11:30:00")))
  expect_identical(s1_states(as.POSIXct(lt), "t"), st)
})

test_that("a row record reads matrix, data-frame, list and date-time columns by row", {
  df = data.frame(id = 1:2)
  df$m = matrix(1:4, 2, dimnames = list(NULL, c("x", "y")))
  df$s = data.frame(p = 1:2, q = c("a", "b"))
  df$l = list(1:2, "z")
  df$k = I(list("one", "two"))
  df$t = as.POSIXlt(c("2026-09-29 10:00:00", "2026-09-30 11:30:00"), tz = "UTC")
  df$f = factor(c("lo", "hi"))
  st = s1_states(df, "row")
  expect_length(st, 2L)
  expect_identical(st[[2]]$row, list(id = 2L, m = list(x = 2L, y = 4L),
                                      s = list(p = 2L, q = "b"), l = "z", k = "two",
                                      t = "2026-09-30 11:30:00", f = "hi"))
  expect_identical(st[[1]]$row$l, list(1L, 2L))
})

test_that("I() of a small list is one state carrying the list", {
  expect_identical(s1_states(I(list(1, "b")), "u"), list(list(u = list(1, "b"))))
  expect_identical(s1_states(I(c(a = 1, b = 2)), "v"), list(list(v = list(a = 1, b = 2))))
})

test_that("classed elements are sent without their names, which stay on the list of states", {
  expect_identical(s1_states(factor(c(a = "x", b = "y")), "f"), s1_states(c(a = "x", b = "y"), "f"))
  dates = as.Date(c("2026-09-29", "2026-09-30"))
  names(dates) = c("a", "b")
  expect_identical(s1_states(dates, "d"),
                   list(a = list(d = "2026-09-29"), b = list(d = "2026-09-30")))
  lt = as.POSIXlt(c("2026-09-29 10:00:00", "2026-09-30 11:30:00"), tz = "UTC")
  names(lt) = c("a", "b")
  expect_identical(s1_states(lt, "t"),
                   list(a = list(t = "2026-09-29 10:00:00"), b = list(t = "2026-09-30 11:30:00")))
  expect_identical(s1_states(list(lt = lt), "cfg"),
                   list(list(cfg = list(lt = list(a = "2026-09-29 10:00:00",
                                                  b = "2026-09-30 11:30:00")))))
})

test_that("nested data-frame and matrix columns give row records with their inner names", {
  df = data.frame(id = 1:2)
  df$s1 = data.frame(p = 3:4)
  inner = data.frame(q = 1:2)
  inner$l = list(1:2, "z")
  df$s2 = inner
  df$m1 = matrix(1:2, 2, dimnames = list(NULL, "x"))
  df$lm = matrix(list(1, "a", "b", 2:3), 2, dimnames = list(NULL, c("u", "v")))
  expect_identical(s1_states(df, "row")[[2]]$row,
                   list(id = 2L, s1 = list(p = 4L), s2 = list(q = 2L, l = "z"), m1 = list(x = 2L),
                        lm = list(u = "a", v = list(2L, 3L))))
})

test_that("states leave I() lists, date-times and nested data frames editable in place", {
  states = "s1_states = get('s1_states', envir = asNamespace('gptr'))"
  expect_no_copy(
    setup = paste("lst = I(list(runif(2e5), 'b'))", "small = I(list(c(1, 2, 3), 'b'))",
                  "invisible(tracemem(small[[1]]))", states, sep = "; "),
    action = "st = s1_states(lst, 'u'); st = s1_states(small, 'u'); invisible(gc())",
    edit = "lst[[1]][1] = 0; small[[1]][1] = 0", object = "lst[[1]]",
    label = "s1_states() of a large and a small I() list"
  )
  expect_no_copy(
    setup = paste("t0 = as.POSIXct('2026-09-29', tz = 'UTC')",
                  "big = as.POSIXlt(t0 + seq_len(2000))",
                  "held = list(a = as.POSIXlt(t0 + seq_len(50)))",
                  "invisible(tracemem(.subset2(held$a, 'sec')))", states, sep = "; "),
    action = "st = s1_states(big, 't'); st = s1_states(held, 'cfg'); invisible(gc())",
    edit = "big$sec[1] = 0; held$a$sec[1] = 0", object = ".subset2(big, 'sec')",
    label = "s1_states() of a POSIXlt vector and of a list holding one"
  )
  # one column assignment per data frame: base R's data-frame `$` assignment copies the frame, so
  # base R itself copies the columns of a data frame on its second edit
  expect_no_copy(
    setup = paste("df = data.frame(id = 1:2)", "inner = data.frame(p = 1:2)",
                  "inner$l = list(runif(2e5), 'z')", "df$s = inner", "rm(inner)",
                  "dm = data.frame(id = 1:2)", "m = matrix(list(NULL, 'a', 'b', 'c'), 2)",
                  "m[[1]] = runif(2e5)", "dm$m = m", "rm(m)", "invisible(tracemem(dm$m[[1]]))",
                  states, sep = "; "),
    action = "st = s1_states(df, 'row'); st = s1_states(dm, 'row'); invisible(gc())",
    edit = "df$s$l[[1]][1] = 0; dm$m[[1]][1] = 0", object = "df$s$l[[1]]",
    label = "s1_states() of data frames with nested data-frame and list-matrix columns"
  )
})

test_that("a session state stays within gptr.s1_state_max even when its facts are long", {
  local_mocked_bindings(session_data = function(s) {
    list(status = "error", reason = strrep("r", 300), last_text = "Fine.",
         values = list(list(name = "fit", class = "lm")))
  })
  s = structure(new.env(), class = "gptr_session")
  local_gptr_options(s1_state_max = 100L)
  txt = as_state(s, "session")
  expect_identical(nchar(txt), 100L)
  expect_true(startsWith(txt, "Status: error (rrr"))
  expect_true(endsWith(txt, "..."))
})

test_that("a session without an answer or a value name still gives a state", {
  local_mocked_bindings(session_data = function(s) {
    list(status = "idle", reason = NULL, last_text = NA_character_,
         values = list(list(class = "data.frame")))
  })
  s = structure(new.env(), class = "gptr_session")
  expect_identical(as_state(s, "session"),
                   "Value: (unnamed) <data.frame>\nAnswer: (no answer yet)")
  expect_identical(s1_states(s, "session"),
                   list(list(session = "Value: (unnamed) <data.frame>\nAnswer: (no answer yet)")))
})

# ---- Task 8: the classifier route core ----------------------------------------------------------

test_that("s1_match() takes classifier specs, references, provider ids and emulate refs", {
  judge = local_fake_provider(list(0.5), name = "judge", type = "classifier")
  chat = local_fake_provider(list("hi"), name = "chatty")
  m = function(model, prompt = "Q?") s1_match(call_new(prompt = prompt, ids = list(model = model)))
  expect_true(m(judge))
  expect_true(m("judge/judge-s1"))
  expect_true(m("judge"))
  expect_true(m("emulate:chatty/chatty-1"))
  expect_false(m(chat))
  expect_false(m("chatty/chatty-1"))
  expect_false(m(NULL))
  expect_false(m("no-such-model-anywhere"))
  expect_false(m(judge, prompt = NULL))
})

test_that("s1_target() resolves specs, references and provider ids; emulation is opt-in", {
  judge = local_fake_provider(list(0.5), name = "judge", type = "classifier")
  local_fake_provider(list("hi"), name = "chatty")
  t1 = s1_target(judge)
  expect_identical(t1$ref, "judge/judge-s1")
  expect_identical(t1$endpoint, "offline:judge")
  expect_identical(t1$engine, "fake")
  expect_identical(s1_target("judge/judge-s1")$alias, "judge-s1")
  expect_identical(s1_target("judge")$ref, "judge/judge-s1")
  expect_error(s1_target("chatty/chatty-1"), class = "gptr_error_invalid_argument")
  local_gptr_options(system1 = NULL)
  expect_error(s1_target("emulate:chatty/chatty-1"), class = "gptr_error_invalid_argument")
  local_gptr_options(system1 = "emulate:chatty/chatty-1")
  te = s1_target("emulate:chatty/chatty-1")
  expect_identical(te$engine, "emulated:structured")
  expect_false(te$calibrated)
  expect_identical(te$model$provider, "chatty")
  expect_identical(s1_target("jev")$engine, "emulated:structured")
})

test_that("s1_build() and s1_abstain() follow the threshold and the uncertain band", {
  q = list(type = "noul", options = NULL)
  ans = list(list(prob = 0.9), list(prob = 0.55), NULL, list(prob = 0.3))
  out = s1_build(q, ans, c("a", "b", "c", "d"), 0.5, list(cached = rep(FALSE, 4)))
  expect_identical(as.logical(out), c(a = TRUE, b = TRUE, c = NA, d = FALSE))
  hi = s1_build(q, ans, NULL, 0.6, list())
  expect_identical(as.logical(hi), c(TRUE, FALSE, NA, FALSE))
  a = s1_check_args(q, list(min_confidence = 0.3, uncertain = NULL))
  ab = s1_abstain(out, q, a, list())
  expect_identical(as.logical(ab), c(a = TRUE, b = NA, c = NA, d = FALSE))
  expect_identical(attr(ab, "prob"), c(0.9, 0.55, NA, 0.3))
  cq = list(type = "choice", options = c("x", "y"))
  cans = list(list(choice = "y", probabilities = c(x = 0.3, y = 0.7), confidence = 0.4))
  ch = s1_build(cq, cans, NULL, 0.5, list())
  expect_identical(as.character(ch), "y")
  expect_error(s1_check_args(cq, list(uncertain = TRUE)), class = "gptr_error_invalid_argument")
  expect_error(s1_check_args(q, list(threshold = 1)), class = "gptr_error_invalid_argument")
  stop_args = s1_check_args(cq, list(min_confidence = 0.5, uncertain = "stop"))
  expect_error(s1_abstain(ch, cq, stop_args, list()), class = "gptr_error_s1_uncertain")
  fun_args = s1_check_args(cq, list(min_confidence = 0.5, uncertain = function(state, answer) "x"))
  expect_identical(as.character(s1_abstain(ch, cq, fun_args, list(list()))), "x")
  bad_args = s1_check_args(cq, list(min_confidence = 0.5, uncertain = function(state, answer) "z"))
  expect_error(s1_abstain(ch, cq, bad_args, list(list())), class = "gptr_error_invalid_argument")
})

test_that("summaries match the document line format of contract 11.5", {
  d = new_gptr_decision(c(TRUE, TRUE, FALSE, NA), c(0.9, 0.8, 0.1, NA))
  meta = list(model = "jev-1.13.0", date = "2026-09-29")
  expect_identical(s1_summary(d, meta),
                   "gptr_decision: 2 TRUE / 1 FALSE / 1 NA (jev-1.13.0, 2026-09-29)")
  ch = new_gptr_choice(c("liver", "lung", "liver", "other"), c("liver", "lung", "other"),
                       NULL, rep(0.9, 4))
  expect_identical(s1_summary(ch, meta),
                   "gptr_choice: liver 2, lung 1, other 1 (jev-1.13.0, 2026-09-29)")
  sc = new_gptr_score(c(1, 2), c("a", "b", "c"), NULL, c(0.9, 0.9))
  expect_identical(s1_summary(sc, meta), "gptr_score: mean 1.5 (jev-1.13.0, 2026-09-29)")
})

test_that("s1_call() answers from a call record and caches per element", {
  s1_fresh()
  judge = local_fake_provider(list(0.9, 0.2), name = "judge", type = "classifier")
  call = s1_test_call("Is it about dogs?", text = c(a = "A puppy.", b = "A car."), model = judge)
  d = s1_call(call)
  expect_identical(as.logical(d), c(a = TRUE, b = FALSE))
  expect_identical(attr(d, "meta")$question, "Is it about dogs?")
  expect_identical(attr(d, "meta")$cached, c(FALSE, FALSE))
  expect_identical(attr(d, "meta")$engine, "fake")
  expect_identical(attr(d, "meta")$model, "judge-s1-1.0")
  # IC-74 (07 section 3): P01's fake makes no calibration claim, so calibration is unknown (NA)
  expect_identical(attr(d, "meta")$calibrated, NA)
  again = s1_call(s1_test_call("Is it about dogs?", text = c(a = "A puppy.", b = "A car."),
                               model = judge))
  expect_identical(attr(again, "meta")$cached, c(TRUE, TRUE))
  expect_identical(attr(again, "meta")$model, "judge-s1-1.0")
  expect_length(fake_requests(judge), 2L)
  live = s1_call(s1_test_call("Is it about dogs?", text = c(a = "A puppy.", b = "A car."),
                              model = judge, args = list(replay = "live")))
  expect_identical(attr(live, "meta")$cached, c(FALSE, FALSE))
  expect_length(fake_requests(judge), 4L)
})

test_that("System 1 calls are logged in the process System 1 accounting log", {
  s1_fresh()
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  n = nrow(usage_log())
  s1_call(s1_test_call("Q?", text = "a", model = judge))
  log = usage_log()
  expect_identical(nrow(log), n + 1L)
  expect_identical(log$route[nrow(log)], "system-one")
  expect_identical(log$agent[nrow(log)], "s1")
  expect_identical(log$provider[nrow(log)], "judge")
})

test_that("the document summary is written through doc.s1_block, never from model code", {
  s1_fresh()
  local_fake_provider(list(0.9), name = "judge", type = "classifier")
  seen = new.env()
  seen$summary = character()
  s1_local_service("doc.s1_block", function(call, summary) {
    seen$summary = c(seen$summary, summary)
    seen$meta = attr(summary, "meta")
    invisible(NULL)
  })
  s1_call(s1_test_call("Q?", text = "a", model = "judge/judge-s1"))
  expect_identical(seen$summary,
                   paste0("gptr_decision: 1 TRUE / 0 FALSE (judge-s1-1.0, ", Sys.Date(), ")"))
  # P15 writes the block header's model= and date= from the summary's meta (contract 11.5)
  expect_identical(seen$meta, list(model = "judge-s1-1.0", date = format(Sys.Date())))
  local_mocked_bindings(run_current = function() list(id = "u00000001", session = "s0000000000"))
  s1_call(s1_test_call("Q?", text = "b", model = "judge/judge-s1"))
  expect_length(seen$summary, 1L)
})

test_that("ctx$decide() goes through the s1.decide service to the configured System 1", {
  s1_fresh()
  local_fake_provider(function(state, question) c(standard = 0.3, complex = 0.7),
                      name = "judge", type = "classifier")
  local_gptr_options(system1 = "judge/judge-s1")
  rating = s1_decide("How demanding is the work?", "Refactor the cache layer.",
                     choices = c(standard = "Ordinary work", complex = "Hard work"))
  expect_identical(as.character(rating), "complex")
  expect_identical(unname(gptr_prob(rating, "probabilities")[1, "complex"]), 0.7)
  expect_error(s1_decide("Q?", "x", output = "factor"), class = "gptr_error_invalid_argument")
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  local_gptr_options(system1 = NULL)
  expect_error(s1_decide("Q?", "x"), class = "gptr_error_no_key")
})

# ---- Task 8, IC-74 (07-local-ollama.md sections 2-5), IC-47 -------------------------------------

# An in-process classifier adapter for the calling test: `run(model, state, questions, opts)`
# returns canonical answers (07 section 3)
local_s1_test_adapter = function(api, run, .env = parent.frame()) {
  off = gptr_register(gptr_adapter(api, transport = "inprocess", classify = list(run = run)))
  withr::defer(off(), envir = .env)
  invisible(api)
}

# A registered classifier provider for the calling test with one model `<id>-s1`
local_s1_test_provider = function(id, api, ..., model = list(), .env = parent.frame()) {
  spec = gptr_provider(id, api = api, type = "classifier", ...,
                       models = list(c(list(id = paste0(id, "-s1"), type = "classifier"), model)))
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  spec
}

test_that("the route follows the model's own type, not its provider's default (IC-74)", {
  s1_fresh()
  # a provider whose default is chat serves a classifier model, and the reverse
  mixed = gptr_fake_provider(list(0.8), name = "mixed", type = "classifier")
  mixed$type = "chat"
  mixed$api = "fake"
  off = gptr_register(mixed)
  withr::defer(off())
  odd = gptr_fake_provider(list("hi"), name = "oddly")
  odd$type = "classifier"
  off2 = gptr_register(odd)
  withr::defer(off2())
  m = function(model) s1_match(call_new(prompt = "Q?", ids = list(model = model)))
  expect_true(m(mixed))
  expect_true(m("mixed"))
  expect_true(m("mixed/mixed-s1"))
  expect_false(m(odd))
  expect_false(m("oddly"))
  expect_false(m("oddly/oddly-1"))
  expect_identical(s1_target("mixed")$ref, "mixed/mixed-s1")
  expect_error(s1_target(odd), class = "gptr_error_invalid_argument")
  d = s1_call(s1_test_call("Q?", text = "a", model = "mixed/mixed-s1"))
  expect_identical(as.logical(d), TRUE)
  meta = attr(d, "meta")
  expect_identical(meta[c("provider", "api", "execution", "locality")],
                   list(provider = "mixed", api = "fake-classifier", execution = "native",
                        locality = "local"))
  expect_identical(meta$model_digest, NA_character_)
  expect_identical(meta$server_version, NA_character_)
  expect_identical(meta$calibrated, NA)
  again = attr(s1_call(s1_test_call("Q?", text = "a", model = "mixed/mixed-s1")), "meta")
  expect_identical(again$cached, TRUE)
  expect_identical(again[c("provider", "api", "execution", "engine")],
                   list(provider = "mixed", api = "fake-classifier", execution = "native",
                        engine = "fake"))
  expect_identical(again$calibrated, NA)
})

test_that("emulated answers say so in their metadata and their usage row (IC-19, IC-74)", {
  s1_fresh()
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  chat = local_fake_provider(list(list(json = list(answers = list(answer = 0.8)))),
                             name = "chatty")
  local_gptr_options(system1 = "emulate:chatty/chatty-1")
  d = s1_call(s1_test_call("Q?", text = "a", model = "jev"))
  expect_identical(as.logical(d), TRUE)
  meta = attr(d, "meta")
  expect_identical(meta$engine, "emulated:structured")
  expect_false(meta$calibrated)
  expect_identical(meta$execution, "emulated")
  expect_identical(meta$provider, "chatty")
  expect_identical(meta$alias, "emulate:chatty/chatty-1")
  log = usage_log()
  expect_identical(log$route[nrow(log)], "emulated")
  expect_identical(log$provider[nrow(log)], "chatty")
  again = attr(s1_call(s1_test_call("Q?", text = "a", model = "jev")), "meta")
  expect_identical(again$cached, TRUE)
  expect_false(again$calibrated)
  expect_identical(again$execution, "emulated")
  expect_length(fake_requests(chat), 1L)
})

test_that("unreported usage stays unknown; an answer from the cache used none (IC-74)", {
  s1_fresh()
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  local_s1_test_adapter("s1-quiet-test", function(model, state, questions, opts) {
    list(answers = list(answer = list(type = "noul", prob = 0.6)), model_version = "quiet-1.0")
  })
  quiet = local_s1_test_provider("quiet", "s1-quiet-test", local = TRUE, offline = TRUE,
                                 model = list(prices = data.frame(from = "2026-01-01",
                                                                  tier = "default", input = 1,
                                                                  output = 1)))
  n = nrow(usage_log())
  d = s1_call(s1_test_call("Q?", text = "a", model = quiet))
  expect_identical(attr(d, "meta")$usage, list(input = NA_real_, output = NA_real_,
                                               cost = NA_real_))
  log = usage_log()
  expect_identical(nrow(log), n + 1L)
  expect_true(is.na(log$input[nrow(log)]))
  expect_true(is.na(log$cost[nrow(log)]))
  again = s1_call(s1_test_call("Q?", text = "a", model = quiet))
  expect_identical(attr(again, "meta")$cached, TRUE)
  expect_identical(attr(again, "meta")$usage, list(input = 0, output = 0, cost = 0))
  expect_identical(nrow(usage_log()), n + 1L)
})

test_that("a cached record that no longer answers the question is a miss (IC-74)", {
  s1_fresh()
  judge = local_fake_provider(list(0.9, 0.2), name = "judge", type = "classifier")
  s1_call(s1_test_call("Q?", text = "a", model = judge))
  mem = the$s1_cache
  key = ls(mem)
  expect_length(key, 1L)
  rec = get(key, envir = mem)
  rec$answer = 7
  assign(key, rec, envir = mem)
  d = s1_call(s1_test_call("Q?", text = "a", model = judge))
  expect_identical(attr(d, "meta")$cached, FALSE)
  expect_identical(as.logical(d), FALSE)
  expect_length(fake_requests(judge), 2L)
})

test_that("the request preflight runs before the call's values are read (IC-74)", {
  s1_fresh()
  local_mocked_bindings(catalog_ollama_discover = function(...) stop("discovery must not run"),
                        s1_inputs = function(call) stop("the call's values were read"))
  local_no_network()
  clef = function(id, base_url) {
    gptr_provider(id, api = "ollama-system-one", type = "classifier", base_url = base_url,
                  models = list(list(id = "clef-flash", type = "classifier",
                                     api = "ollama-system-one")))
  }
  # a live call (the test process replays, and replay uses the frozen identity instead, IC-74)
  live = list(replay = "auto")
  lp = clef("lclef", "http://127.0.0.1:11434")
  expect_true(s1_match(call_new(prompt = "Q?", ids = list(model = lp))))
  expect_error(s1_call(s1_test_call("Q?", text = "a", model = lp, args = live)),
               class = "gptr_error_not_available")
  remote = clef("rclef", "https://ollama.example.invalid")
  expect_error(s1_call(s1_test_call("Q?", text = "a", model = remote, args = live)),
               class = "gptr_error_untrusted")
})

test_that("System 1 images are checked against the model, keyed and handed over (IC-74)", {
  s1_fresh()
  img = function(b) list(data = as.raw(b), mime = "image/png")
  with_images = function(model, images) {
    s1_test_call("Q?", text = "a", model = model, args = list(opts = list(system1_images = images)))
  }
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  expect_error(s1_call(with_images(judge, list(img(1:4)))), class = "gptr_error_invalid_argument")
  expect_length(fake_requests(judge), 0L)
  seen = new.env(parent = emptyenv())
  seen$images = list()
  local_s1_test_adapter("s1-vision-test", function(model, state, questions, opts) {
    seen$images[length(seen$images) + 1L] = list(opts[["images"]])
    list(answers = list(answer = list(type = "noul", prob = 0.7)),
         usage = list(input = 3, output = 1), model_version = "vision-1.0")
  })
  vis = local_s1_test_provider("vision", "s1-vision-test", local = TRUE, offline = TRUE,
                               model = list(decision = list(images = TRUE)))
  d = s1_call(with_images(vis, list(img(1:4), img(5:8))))
  expect_identical(as.logical(d), TRUE)
  expect_identical(seen$images, list(list(img(1:4), img(5:8))))
  expect_identical(attr(s1_call(with_images(vis, list(img(1:4), img(5:8)))), "meta")$cached, TRUE)
  # the images and their order are part of the cache key; no images is another key
  expect_identical(attr(s1_call(with_images(vis, list(img(5:8), img(1:4)))), "meta")$cached,
                   FALSE)
  expect_identical(attr(s1_call(s1_test_call("Q?", text = "a", model = vis)), "meta")$cached,
                   FALSE)
  expect_length(seen$images, 3L)
  expect_null(seen$images[[3]])
  # emulation sends no images: refused, never dropped
  chat = local_fake_provider(list(list(json = list(answers = list(answer = 0.8)))),
                             name = "chatty")
  local_gptr_options(system1 = "emulate:chatty/chatty-1")
  expect_error(s1_call(with_images("emulate:chatty/chatty-1", list(img(1:4)))),
               class = "gptr_error_invalid_argument")
  expect_length(fake_requests(chat), 0L)
})

test_that("egress and the call's replay mode guard requests, not cache hits (IC-47, IC-74)", {
  s1_fresh()
  seen = new.env(parent = emptyenv())
  seen$n = 0L
  local_s1_test_adapter("s1-guard-test", function(model, state, questions, opts) {
    seen$n = seen$n + 1L
    list(answers = list(answer = list(type = "noul", prob = 0.8)),
         usage = list(input = 2, output = 1), model_version = "guard-1.0")
  })
  near = local_s1_test_provider("nearby", "s1-guard-test", local = TRUE,
                                base_url = "http://127.0.0.1:9/v1")
  far = local_s1_test_provider("faraway", "s1-guard-test", local = TRUE,
                               base_url = "https://s1.example.invalid/v1")
  # the test process replays (setup.R): a miss for a provider that is not offline is refused
  expect_error(s1_call(s1_test_call("Q?", text = "a", model = near)),
               class = "gptr_error_not_recorded")
  expect_identical(seen$n, 0L)
  # the call's own replay mode decides, as for System 2 calls (P08's gateway_replay_guard())
  s1_call(s1_test_call("Q?", text = "a", model = near, args = list(replay = "auto")))
  expect_identical(seen$n, 1L)
  hit = s1_call(s1_test_call("Q?", text = "a", model = near))
  expect_identical(attr(hit, "meta")$cached, TRUE)
  expect_identical(seen$n, 1L)
  local_gptr_options(replay = "auto")
  expect_error(s1_call(s1_test_call("Q?", text = "b", model = near,
                                    args = list(replay = "replay"))),
               class = "gptr_error_not_recorded")
  # a `local` hint with a remote endpoint still needs the egress acknowledgement (D-099)
  expect_error(s1_call(s1_test_call("Q?", text = "a", model = far)), class = "gptr_error_egress")
  expect_identical(seen$n, 1L)
})

test_that("a piped session gets a gptr.decision entry and the decision event its question type", {
  s1_fresh()
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  local_fake_provider(list("hello"))
  judge = local_fake_provider(list(0.9), name = "judge", type = "classifier")
  seen = new.env(parent = emptyenv())
  seen$events = list()
  off = gptr_register(gptr_hook("decision", function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  }))
  withr::defer(off())
  s = session_new("fake/fake-1", "auto", home = new.env())
  n0 = length(session_data(s)$entries)
  turns = session_data(s)$turns
  s1_call(s1_test_call("Is the work done?", model = judge, session = s))
  entries = session_data(s)$entries
  expect_length(entries, n0 + 1L)
  e = entries[[length(entries)]]
  expect_identical(e$custom_type, "gptr.decision")
  expect_identical(e$data[c("question", "type", "model", "alias", "n", "cached")],
                   list(question = "Is the work done?", type = "noul", model = "judge-s1-1.0",
                        alias = "judge-s1", n = 1L, cached = 0L))
  expect_identical(e$data$summary,
                   paste0("gptr_decision: 1 TRUE / 0 FALSE (judge-s1-1.0, ", Sys.Date(), ")"))
  expect_identical(e$data$answers, list(TRUE))
  expect_identical(e$data$probs, list(0.9))
  expect_identical(session_data(s)$turns, turns)
  expect_length(seen$events, 1L)
  ev = seen$events[[1L]]
  expect_identical(ev$type, "decision")
  expect_identical(ev$question_type, "noul")
  expect_identical(ev$cached, 0L)
  log = usage_log()
  expect_identical(log$session[nrow(log)], session_data(s)$id)
})

test_that("an answer whose confidence is unknown is inside the uncertain band (IC-74)", {
  # an empty probability map leaves the confidence unknown (report 04 section 2.9), and an unknown
  # confidence cannot show that min_confidence is met; a failed element stays as it is
  cq = list(type = "choice", options = c("x", "y"))
  unknown = c(x = NA_real_, y = NA_real_)
  cans = list(list(choice = "x", probabilities = unknown, confidence = NA_real_), NULL,
              list(choice = "y", probabilities = c(x = 0.02, y = 0.98), confidence = 0.95))
  ch = s1_build(cq, cans, c("a", "b", "c"), 0.5, list())
  na_args = s1_check_args(cq, list(min_confidence = 0.9, uncertain = NULL))
  expect_identical(unname(as.character(s1_abstain(ch, cq, na_args, list()))), c(NA, NA, "y"))
  zero = s1_check_args(cq, list(min_confidence = 0, uncertain = "stop"))
  expect_identical(s1_abstain(ch, cq, zero, list()), ch)
  stop_args = s1_check_args(cq, list(min_confidence = 0.9, uncertain = "stop"))
  err = expect_error(s1_abstain(ch, cq, stop_args, list()), class = "gptr_error_s1_uncertain")
  expect_identical(err$prob, NA_real_)
  seen = new.env(parent = emptyenv())
  seen$states = list()
  fun = function(state, answer) {
    seen$states[[length(seen$states) + 1L]] = state
    "y"
  }
  fun_args = s1_check_args(cq, list(min_confidence = 0.9, uncertain = fun))
  expect_identical(unname(as.character(s1_abstain(ch, cq, fun_args, list("s1", "s2", "s3")))),
                   c("y", NA, "y"))
  expect_identical(seen$states, list("s1"))
  sq = list(type = "score", options = c("lo", "mid", "hi"))
  sc = s1_build(sq, list(list(score = 1.5, probabilities = c(lo = NA_real_, mid = NA_real_,
                                                             hi = NA_real_),
                              confidence = NA_real_)), NULL, 0.5, list())
  expect_error(s1_abstain(sc, sq, s1_check_args(sq, list(min_confidence = 0.5,
                                                          uncertain = "stop")), list()),
               class = "gptr_error_s1_uncertain")
  # through the route: an in-process classifier that reports no probabilities
  s1_fresh()
  local_s1_test_adapter("s1-unsure-test", function(model, state, questions, opts) {
    list(answers = list(answer = list(type = "choice", choice = "x", probabilities = unknown,
                                      confidence = NA_real_)),
         model_version = "unsure-1.0")
  })
  unsure = local_s1_test_provider("unsure", "s1-unsure-test", local = TRUE, offline = TRUE)
  ask = function(...) {
    s1_call(s1_test_call("Which?", text = "a", model = unsure,
                         args = list(choices = c("x", "y"), ...)))
  }
  expect_error(ask(min_confidence = 0.9, uncertain = "stop"), class = "gptr_error_s1_uncertain")
  expect_identical(as.character(ask(min_confidence = 0.9)), NA_character_)
  d = ask()
  expect_identical(as.character(d), "x")
  expect_identical(unname(gptr_prob(d, "confidence")), NA_real_)
})

test_that("a value from an uncertain() function must be a value of the question", {
  sq = list(type = "score", options = c("lo", "mid", "hi"))
  sc = s1_build(sq, list(list(score = 1.2, probabilities = c(lo = 0.2, mid = 0.4, hi = 0.4),
                              confidence = 0.1)), NULL, 0.5, list())
  esc = function(q, v) {
    s1_check_args(q, list(min_confidence = 0.5, uncertain = function(state, answer) v))
  }
  expect_identical(as.double(s1_abstain(sc, sq, esc(sq, 1.5), list(list()))), 1.5)
  expect_identical(as.double(s1_abstain(sc, sq, esc(sq, 2L), list(list()))), 2)
  expect_identical(as.double(s1_abstain(sc, sq, esc(sq, NA), list(list()))), NA_real_)
  for (v in list(7, -1, Inf, "high", c(1, 2), list(1))) {
    expect_error(s1_abstain(sc, sq, esc(sq, v), list(list())),
                 class = "gptr_error_invalid_argument")
  }
  q = list(type = "noul", options = NULL)
  d = s1_build(q, list(list(prob = 0.55)), NULL, 0.5, list())
  expect_identical(as.logical(s1_abstain(d, q, esc(q, FALSE), list(list()))), FALSE)
  expect_identical(as.logical(s1_abstain(d, q, esc(q, NA), list(list()))), NA)
  expect_error(s1_abstain(d, q, esc(q, "maybe"), list(list())),
               class = "gptr_error_invalid_argument")
})
