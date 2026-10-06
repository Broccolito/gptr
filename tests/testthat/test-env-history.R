local_history = function(.env = parent.frame()) {
  user_log_stop()
  withr::defer(user_log_stop(), envir = .env)
}

# The name of an LC_CTYPE locale that is UTF-8 here (the current one first), or NA. Each
# candidate is set and checked, and the current locale is restored.
utf8_ctype_name = function() {
  old = Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  for (loc in unique(c(old, "C.UTF-8", "en_US.UTF-8", "UTF-8"))) {
    set = suppressWarnings(Sys.setlocale("LC_CTYPE", loc))
    if (nzchar(set) && isTRUE(l10n_info()[["UTF-8"]])) return(loc)
  }
  NA_character_
}

# Switch LC_CTYPE to a UTF-8 locale until the calling block ends; FALSE when there is none
local_utf8_ctype = function(.env = parent.frame()) {
  loc = utf8_ctype_name()
  if (is.na(loc)) return(FALSE)
  old = Sys.getlocale("LC_CTYPE")
  Sys.setlocale("LC_CTYPE", loc)
  withr::defer(Sys.setlocale("LC_CTYPE", old), envir = .env)
  TRUE
}

test_that("the callback logs successful user expressions and skips peter() calls", {
  local_history()
  user_log_callback(str2lang("x = 1"), 1, TRUE, FALSE)
  user_log_callback(str2lang("stop('no')"), NULL, FALSE, FALSE)
  user_log_callback(str2lang("s = peter('prompt', mtcars)"), NULL, TRUE, FALSE)
  user_log_callback(str2lang("mtcars |> gptr::peter('again')"), NULL, TRUE, FALSE)
  user_log_callback(str2lang("m[6000, 5000] = -1"), NULL, TRUE, FALSE)
  expect_equal(user_expr_log(), c("x = 1", "m[6000, 5000] = -1"))
})

test_that("entries are cut to 120 characters and only the last 20 are kept", {
  local_history()
  user_log_push(str2lang(paste0("f(", strrep("a", 200), ")")))
  expect_equal(nchar(user_expr_log()), 120L)
  expect_match(user_expr_log(), "\\.\\.\\.$")
  for (i in 1:30) user_log_push(str2lang(sprintf("x%d = %d", i, i)))
  log = user_expr_log()
  expect_length(log, 20L)
  expect_equal(log[20], "x30 = 30")
  expect_equal(user_expr_log(n = 2L), c("x29 = 29", "x30 = 30"))
})

test_that("since filters by time", {
  local_history()
  user_log_push(str2lang("a = 1"))
  t = as.numeric(Sys.time())
  user_log_state$time = t - 10
  user_log_push(str2lang("b = 2"))
  expect_equal(user_expr_log(since = t - 5), "b = 2")
  expect_equal(user_expr_log(since = NULL), c("a = 1", "b = 2"))
  expect_error(user_expr_log(since = "x"), class = "gptr_error_invalid_argument")
})

test_that("the task callback is registered per session and removed with the last one", {
  local_history()
  user_log_start("s0000000001")
  user_log_start("s0000000002")
  user_log_start("s0000000001")
  expect_true("gptr_history" %in% getTaskCallbackNames())
  user_log_release("s0000000001")
  expect_true("gptr_history" %in% getTaskCallbackNames())
  user_log_release("s0000000002")
  expect_false("gptr_history" %in% getTaskCallbackNames())
})

# Added for D-045. Every block but the UTF-8 one failed against the plan-literal source; that
# one guards the IC-62 text in every locale.

test_that("multi-line expressions are logged on one line, not as their first line", {
  local_history()
  user_log_push(str2lang("for (i in 1:3) {\n  y = i\n  z = y + 1\n}"))
  user_log_push(str2lang("f = function(x) {\n  x + 1\n}"))
  user_log_push(str2lang("{\n  a = 1\n  b = 2\n}"))
  user_log_push(str2lang("if (TRUE) {\n  1\n} else {\n  2\n}"))
  expect_equal(user_expr_log(), c(
    "for (i in 1:3) { y = i; z = y + 1 }", "f = function(x) { x + 1 }", "{ a = 1; b = 2 }",
    "if (TRUE) { 1 } else { 2 }"
  ))
  user_log_push(str2lang(paste0("{\n", paste0("  v", 1:60, " = 1", collapse = "\n"), "\n}")))
  last = user_expr_log(n = 1L)
  expect_equal(nchar(last), 120L)
  expect_match(last, "^\\{ v1 = 1; v2 = 1; .*\\.\\.\\.$")
  # Review round 2: inside braces deparse() breaks an `if` after `if (cond) ` and before
  # `else`; those breaks are inside one statement and take a space, not "; "
  ifs = c(
    "for (i in 1:10) { if (i %% 2 == 0) next; print(i) }",
    "f = function(x) { if (x > 1) \"big\" else \"small\" }",
    "{ if (a) b else if (c) d else e }",
    "{ function(x) if (x) 1 else 2 }",
    "{ if (x) { a } else b }",
    "{ if (a) b; elsewhere = 1 }",
    "{ lapply(x, function(i) { if (i) a else b }); z = 1 }"
  )
  user_log_stop()
  for (line in ifs) user_log_push(str2lang(line))
  log = user_expr_log()
  expect_equal(log, c(
    "for (i in 1:10) { if (i%%2 == 0) next; print(i) }",
    "f = function(x) { if (x > 1) \"big\" else \"small\" }",
    "{ if (a) b else if (c) d else e }", "{ function(x) if (x) 1 else 2 }",
    "{ if (x) { a } else b }", "{ if (a) b; elsewhere = 1 }",
    "{ lapply(x, function(i) { if (i) a else b }); z = 1 }"
  ))
  # Each entry is code with the meaning typed: it parses back to the same expression
  for (i in seq_along(ifs)) expect_identical(str2lang(log[i]), str2lang(ifs[i]))
})

test_that("every way of naming peter() is filtered and other gptr functions are logged", {
  local_history()
  user_log_push(quote(gptr:::peter("p")))
  user_log_push(str2lang("\"gptr\"::\"peter\"(\"p\")"))
  user_log_push(quote(print(peter("p"))))
  user_log_push(quote(x[, 1] |> peter("p")))
  # Review round 2: argument names that are formals of c() do not end the walk
  user_log_push(str2lang("f(recursive = g(peter(\"p\")))"))
  user_log_push(str2lang("h(use.names = k(peter(\"p\")))"))
  user_log_push(quote(gptr::gptr_last()))
  user_log_push(str2lang("f = peter"))
  user_log_push(quote(x[, 1]))
  expect_equal(user_expr_log(), c("gptr::gptr_last()", "f = peter", "x[, 1]"))
})

test_that("wide and deep expressions are logged quickly and never make the callback throw", {
  local_history()
  wide = str2lang(paste0("x = c(", paste(1:1e5, collapse = ", "), ")"))
  elapsed = system.time(expect_true(user_log_callback(wide, NULL, TRUE, TRUE)))[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_match(user_expr_log(n = 1L), "^x = c\\(1, 2, 3, .*\\.\\.\\.$")
  shallow = str2lang(paste(rep("a", 3000), collapse = " + "))
  expect_true(user_log_callback(shallow, NULL, TRUE, TRUE))
  expect_match(user_expr_log(n = 1L), "^a \\+ a \\+ a .*\\.\\.\\.$")
  for (n in c(20000L, 100000L)) {
    deep = str2lang(paste0("f = function() ", paste(rep("a", n), collapse = " + ")))
    expect_true(user_log_callback(deep, NULL, TRUE, TRUE))
    expect_equal(user_expr_log(n = 1L), "<expression nested more than 5000 calls deep>")
  }
  # Review round 2: the cap holds under an argument named like a formal of c()
  body = paste(rep("a", 6000L), collapse = " + ")
  for (nm in c("recursive", "use.names")) {
    deep = str2lang(sprintf("x = list(%s = function() %s)", nm, body))
    expect_true(user_log_callback(deep, NULL, TRUE, TRUE))
    expect_equal(user_expr_log(n = 1L), "<expression nested more than 5000 calls deep>")
  }
  expect_length(user_expr_log(), 6L)
})

test_that("entries are valid UTF-8 and cut by characters", {
  local_history()
  user_log_push(call("=", quote(x), strrep("\u00e9", 200)))
  user_log_push(call("=", quote(y), "\xff\xfe"))
  # The bytes of a symbol typed in the session's own encoding (no translation in any locale)
  user_log_push(call("=", as.name(rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))), 1))
  log = user_expr_log()
  expect_true(all(validUTF8(log)))
  expect_equal(nchar(log[1]), 120L)
  expect_match(log[1], "^x = \"")
  expect_match(log[2], "^y = \"")
  expect_match(log[3], "= 1$")
})

# Added in review round 1: the parser accepts both inputs below, and deparse() signals an error
# on each, which the callback must not pass on to R.

test_that("names deparse() rejects in a UTF-8 locale are logged as a note", {
  local_history()
  skip_if_not(local_utf8_ctype(), "no UTF-8 locale is available")
  lines = c("`\\xff` = 1", "`a\\xe9b` = 2", "x = list(`\\xfe` = 1)", "f = function(`\\xff`) 1")
  for (line in lines) expect_true(user_log_callback(str2lang(line), NULL, TRUE, TRUE))
  expect_true(user_log_callback(str2lang("z = 2"), NULL, TRUE, TRUE))
  expect_equal(user_expr_log(), c(rep("<expression that cannot be deparsed>", 4L), "z = 2"))
})

test_that("a call chain that exhausts deparse()'s C stack check does not make the callback throw", {
  local_history()
  # f(1)(1)...(1) evaluates at the top level when f returns itself. At 3,000 calls it is under
  # the 5,000-call cap, and deparse() of it as a whole expression fails its C stack check
  # with an 8 MB stack (from about 800 calls); a larger stack deparses it and cuts the text.
  chain = str2lang(paste0("f", strrep("(1)", 3000L)))
  expect_true(user_log_callback(chain, NULL, TRUE, TRUE))
  expect_match(user_expr_log(n = 1L), "^(<expression that cannot be deparsed>|.{117}\\.\\.\\.)$")
  expect_true(user_log_callback(str2lang("z = 2"), NULL, TRUE, TRUE))
  expect_equal(user_expr_log(n = 1L), "z = 2")
})

# Added in review round 3: the formals of function() are a pairlist, not a call, and their
# defaults are walked too.

test_that("default arguments are walked for peter() calls and for depth", {
  local_history()
  expect_equal(user_log_scan(str2lang("g = function(x = peter('p')) x")), "gptr")
  expect_equal(user_log_scan(str2lang("function(a, b = function(c = gptr::peter('p')) c) a")),
               "gptr")
  expect_equal(user_log_scan(str2lang("h = function(x, y = 2) x")), "show")
  expect_equal(user_log_scan(quote(x[, 1])), "show")
  body = paste(rep("a", 6000L), collapse = " + ")
  deep = str2lang(sprintf("f = function(x = %s) 1", body))
  expect_true(user_log_callback(deep, NULL, TRUE, TRUE))
  expect_true(user_log_callback(str2lang("g = function(x = peter('p')) x"), NULL, TRUE, TRUE))
  expect_true(user_log_callback(str2lang("h = function(x, y = 2) x"), NULL, TRUE, TRUE))
  expect_equal(user_expr_log(), c(
    "<expression nested more than 5000 calls deep>", "h = function(x, y = 2) x"
  ))
})

test_that("a callback that R or the user removed is registered again by the next session", {
  local_history()
  user_log_start("s0000000001")
  removeTaskCallback(which(getTaskCallbackNames() == "gptr_history"))
  expect_false("gptr_history" %in% getTaskCallbackNames())
  user_log_start("s0000000002")
  expect_equal(sum(getTaskCallbackNames() == "gptr_history"), 1L)
  user_log_start("s0000000002")
  expect_equal(sum(getTaskCallbackNames() == "gptr_history"), 1L)
  user_log_stop()
  expect_false("gptr_history" %in% getTaskCallbackNames())
})

test_that("session ids must be single strings, so no callback outlives every session", {
  local_history()
  expect_error(user_log_start(NULL), class = "gptr_error_invalid_argument")
  expect_error(user_log_start(NA_character_), class = "gptr_error_invalid_argument")
  expect_error(user_log_release(c("a", "b")), class = "gptr_error_invalid_argument")
  expect_false("gptr_history" %in% getTaskCallbackNames())
  expect_equal(user_log_state$sessions, character())
})

test_that("the registered callback logs real top-level expressions in a fresh R process", {
  skip_on_cran()
  # A UTF-8 LC_CTYPE in the child makes deparse() reject a name typed as `\xfe` (review round 1)
  loc = utf8_ctype_name()
  script = withr::local_tempfile(fileext = ".R")
  writeLines(c(
    tracemem_loader(),
    if (!is.na(loc)) sprintf("invisible(Sys.setlocale('LC_CTYPE', %s))", deparse(loc)),
    "ns = asNamespace('gptr')",
    "user_log_start = get('user_log_start', ns)",
    "user_expr_log = get('user_expr_log', ns)",
    "peter = function(...) invisible(NULL)",
    "user_log_start('s0000000001')",
    "x = 1",
    if (!is.na(loc)) "w = list(`\\xfe` = 1)",
    "for (i in 1:2) {", "  y = i", "}",
    "if (x > 0) {", "  if (x > 1) 'a' else 'b'", "}",
    "s = peter('prompt', mtcars)",
    "mtcars |> peter('again')",
    paste0("f = function() ", paste(rep("a", 6000), collapse = " + ")),
    "z = 2",
    "cat(paste0('LOG: ', user_expr_log()), sep = '\\n')",
    "cat('REGISTERED:', 'gptr_history' %in% getTaskCallbackNames(), '\\n')"
  ), script)
  res = processx::run(
    rscript_path(), c("--vanilla", script), error_on_status = FALSE, timeout = 120,
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  )
  expect_equal(res$status, 0L, info = res$stderr)
  out = strsplit(res$stdout, "\r?\n", perl = TRUE)[[1L]]
  expect_equal(sub("^LOG: ", "", grep("^LOG: ", out, value = TRUE)), c(
    "user_log_start(\"s0000000001\")", "x = 1",
    if (!is.na(loc)) "<expression that cannot be deparsed>", "for (i in 1:2) { y = i }",
    "if (x > 0) { if (x > 1) \"a\" else \"b\" }",
    "<expression nested more than 5000 calls deep>", "z = 2"
  ))
  expect_true("REGISTERED: TRUE " %in% out)
  expect_false(grepl("Error", res$stderr, fixed = TRUE))
})
