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
