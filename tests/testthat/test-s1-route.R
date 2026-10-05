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
