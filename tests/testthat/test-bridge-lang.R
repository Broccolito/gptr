# Tests for R/bridge-lang.R (P22): objects passed by name, peter$sql(), peter$py(), peter$knit(),
# builtin:lang.

test_that("objects passed by name take the label of their expression", {
  f = function(query, name = NULL) bridge_object_names(name, "name", f)
  mt = mtcars
  expect_identical(f("q", name = mt), "mt")
  expect_identical(f("q", name = list(a = 1, b = 2)), c("a", "b"))
  expect_error(f("q", name = head(mt)), class = "gptr_error_invalid_argument")
  expect_error(f("q", name = list(1, 2)), class = "gptr_error_invalid_argument")
  expect_error(f("q", name = list()), class = "gptr_error_invalid_argument")
  member = structure(function(query, name = NULL) f(query, name = name),
                     class = c("gptr_member", "function"))
  expect_identical(member("q", name = mt), "mt")
  expect_error(member("q", name = mt[1:2, ]), class = "gptr_error_invalid_argument")
})

test_that("peter$sql() uses the one DBI connection in the calling frame", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  f = function(missing_arg) {
    shop = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(shop), add = TRUE)
    DBI::dbWriteTable(shop, "orders", data.frame(id = 1:30, region = rep(c("n", "s", "e"), 10)))
    x = bridge_sql("SELECT * FROM orders WHERE id > 5")
    agg = bridge_sql("SELECT region, COUNT(*) AS n FROM orders GROUP BY region ORDER BY region")
    upd = bridge_sql("UPDATE orders SET region = 'w' WHERE id < 3")
    other = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(other), add = TRUE)
    amb = tryCatch(bridge_sql("SELECT 1"),
                   gptr_error_invalid_argument = function(e) conditionMessage(e))
    list(x = x, agg = agg, upd = upd, amb = amb)
  }
  r = f()
  expect_s3_class(r$x, "gptr_sql")
  expect_s3_class(r$x, "data.frame")
  expect_identical(nrow(r$x), 25L)
  out = utils::capture.output(print(r$x))
  expect_identical(out[[1L]], "# 25 rows x 2 cols")
  expect_identical(out[[length(out)]], "# ... 15 more rows (all rows are in the value)")
  expect_identical(utils::capture.output(print(r$x["id"]))[[1L]], "# 25 rows x 1 cols")
  expect_identical(as.integer(r$agg$n), c(10L, 10L, 10L))
  expect_identical(utils::capture.output(print(r$upd)), "# 2 rows affected")
  expect_match(r$amb, "(other, shop)", fixed = TRUE)
  g = function() bridge_sql("SELECT 1")
  expect_error(g(), class = "gptr_error_invalid_argument")
  expect_error(bridge_sql("SELECT 1", con = list()), class = "gptr_error_invalid_argument")
})

test_that("name = registers data frames in an in-memory duckdb under their labels", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  log = local_bridge_events()
  big = data.frame(g = rep(letters[1:5], 200), v = seq_len(1000))
  s = bridge_sql("SELECT g, COUNT(*) AS n FROM big GROUP BY g ORDER BY g", name = big)
  expect_identical(s$g, letters[1:5])
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "sql")
  expect_identical(ev$digest, "#> sql: 5 rows x 2 cols")
  two = bridge_sql("SELECT COUNT(*) AS n FROM a JOIN b USING (k)",
                   name = list(a = data.frame(k = 1:3), b = data.frame(k = 2:4)))
  expect_equal(two$n, 2)
  expect_error(bridge_sql("SELECT 1", name = head(big)), class = "gptr_error_invalid_argument")
  expect_error(bridge_sql("SELECT 1", name = list(a = 1)), class = "gptr_error_invalid_argument")
  shop = DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(shop, shutdown = TRUE))
  expect_error(bridge_sql("SELECT 1", name = big, con = shop),
               class = "gptr_error_invalid_argument")
  expect_equal(bridge_sql("SELECT 41 + 1 AS x", con = shop)$x, 42)
})

test_that("a SQL result prints within the helper budget and keeps every row", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  wide = as.data.frame(matrix(seq_len(200 * 40), nrow = 200))
  x = expect_silent(bridge_sql("SELECT * FROM wide", name = wide, n = 200L))
  out = utils::capture.output(print(x))
  expect_lte(est_tokens(out, "r_output"), 1500)
  expect_identical(dim(x), c(200L, 40L))
})

skip_if_no_python = function() {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  vars = c("RETICULATE_PYTHON", "RETICULATE_PYTHON_ENV", "VIRTUAL_ENV")
  configured = any(nzchar(Sys.getenv(vars))) || reticulate::py_available(initialize = FALSE)
  skip_if_not(configured, "Python is not configured (set RETICULATE_PYTHON)")
}

test_that("peter$py() refuses a Python that reticulate would have to provision", {
  skip_if_not_installed("reticulate")
  testthat::local_mocked_bindings(py_available = function(initialize = FALSE) FALSE,
                                  .package = "reticulate")
  withr::local_envvar(RETICULATE_PYTHON = NA, RETICULATE_PYTHON_ENV = NA, VIRTUAL_ENV = NA)
  err = expect_error(bridge_py("1"), class = "gptr_error_not_available")
  expect_identical(err$member, "py")
})

test_that("peter$py() keeps objects in __main__, shows the last value and one-line errors", {
  skip_if_no_python()
  bridge_py("counter = 41")
  r = bridge_py("counter += 1\ncounter")
  expect_s3_class(r, "gptr_py")
  expect_identical(names(unclass(r)), c("name", "output", "repr"))
  expect_identical(r$value, 42L)
  expect_identical(r$repr, "42")
  expect_identical(r$kind, "int")
  expect_output(print(r), "^42$")
  expect_identical(out_get(r$id), "42")
  e = bridge_py("x = 1\ny = undefined_name + x")
  expect_match(e$error, "NameError", fixed = TRUE)
  s = bridge_py("def f(:\n  pass")
  expect_match(s$error, "^SyntaxError")
  expect_false(grepl("\n", s$error, fixed = TRUE))
  expect_identical(bridge_py("x")$value, 1L)
  w = bridge_py("import sys\nsys.stderr.write('to stderr\\n')\nprint('hello')")
  expect_identical(w$output, c("hello", "[stderr]", "to stderr"))
  expect_null(w$value)
})

test_that("peter$py() receives R objects by name and knitr python chunks share __main__", {
  skip_if_no_python()
  skip_if_not(reticulate::py_module_available("pandas"), "pandas is not installed")
  log = local_bridge_events()
  sales = data.frame(region = rep(c("north", "south"), 50), revenue = seq_len(100))
  r = bridge_py("t = sales.groupby('region').revenue.sum()\nt", name = sales)
  expect_identical(r$name, "sales")
  expect_identical(r$kind, "Series 2")
  v = r$value
  expect_equal(as.numeric(v), c(2500, 2550))
  expect_identical(names(v), c("north", "south"))
  expect_identical(log$events[[length(log$events)]]$digest, "#> py: Series 2")
  expect_identical(bridge_py("a + b", name = list(a = 1L, b = 2L))$value, 3L)
  skip_if_not_installed("knitr")
  bridge_py("shared_value = 42")
  opts = knitr::opts_chunk$merge(list(engine = "python", code = "print(shared_value)",
                                      label = "k", echo = FALSE, results = "markup"))
  out = knitr::knit_engines$get("python")(opts)
  expect_match(paste(out, collapse = ""), "42", fixed = TRUE)
})
