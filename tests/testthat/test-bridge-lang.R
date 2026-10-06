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

test_that("shell engines run through peter$sh() without registered keys and with a timeout", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")) || !nzchar(Sys.which("pgrep")))
  key = paste0("gptr-fake-", "key-0123456789abcdef")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(GPTR_P22_PLAIN = key)
  secret_register(key, "GPTR_P22_PLAIN", source = "user")
  log = local_bridge_events()
  out = bridge_knit("bash", "echo \"from bash: $((6 * 7))\"; env")
  expect_s3_class(out, "gptr_bridge_text")
  expect_true("from bash: 42" %in% out)
  expect_false(any(grepl(key, out, fixed = TRUE)))
  expect_true("TERM=dumb" %in% out)
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "knit")
  expect_match(ev$digest, "^#> knit bash: exit 0, ")
  testthat::local_mocked_bindings(bridge_knit_timeout = function() 1)
  t0 = proc.time()[["elapsed"]]
  slow = bridge_knit("bash", "sleep 999")
  expect_lt(proc.time()[["elapsed"]] - t0, 10)
  expect_true(any(grepl("timed out after", slow, fixed = TRUE)))
  Sys.sleep(0.5)
  left = processx::run("pgrep", c("-f", "sleep 999"), error_on_status = FALSE)$stdout
  expect_identical(left, "")
})

test_that("interpreter engines run as scripts without registered keys and with a timeout", {
  skip_on_cran()
  key = paste0("gptr-fake-", "key-fedcba9876543210")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(GPTR_P22_PLAIN = key)
  secret_register(key, "GPTR_P22_PLAIN", source = "user")
  log = local_bridge_events()
  code = "cat(sprintf('from R: %d [%s]\\n', 6L * 7L, Sys.getenv('GPTR_P22_PLAIN')))"
  out = bridge_knit("Rscript", code)
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(as.character(out), "from R: 42 []")
  expect_identical(out_get(attr(out, "out_id")), "from R: 42 []")
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "knit")
  expect_identical(ev$digest, "#> knit Rscript: exit 0, 1 line")
  testthat::local_mocked_bindings(bridge_knit_timeout = function() 1)
  t0 = proc.time()[["elapsed"]]
  slow = bridge_knit("Rscript", "Sys.sleep(30)")
  expect_lt(proc.time()[["elapsed"]] - t0, 10)
  expect_true(any(grepl("timed out after", slow, fixed = TRUE)))
  skip_if(!nzchar(Sys.which("perl")))
  pl = bridge_knit("perl", "print \"from perl: \", 6 * 7, \"\\n\";")
  expect_identical(as.character(pl), "from perl: 42")
})

test_that("other engines run through knitr", {
  skip_if_not_installed("knitr")
  knitr::knit_engines$set(gptrp22test = function(options) {
    paste0("engine gptrp22test got: ", paste(options$code, collapse = " | "))
  })
  withr::defer(knitr::knit_engines$delete("gptrp22test"))
  out = bridge_knit("gptrp22test", c("a", "b"))
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(as.character(out), "engine gptrp22test got: a | b")
  expect_identical(out_get(attr(out, "out_id")), "engine gptrp22test got: a | b")
  expect_error(bridge_knit("nosuchengine", "x"), class = "gptr_error_invalid_argument")
})

test_that("the python and sql engines run through peter$py() and peter$sql()", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  f = function() {
    shop = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(shop), add = TRUE)
    DBI::dbWriteTable(shop, "orders", data.frame(id = 1:3))
    bridge_knit("sql", "SELECT COUNT(*) AS n FROM orders")
  }
  out = f()
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(out[[1L]], "# 1 rows x 1 cols")
  expect_true(any(grepl("^ *3$", out)))
  skip_if_no_python()
  py = bridge_knit("python", "6 * 7")
  expect_identical(as.character(py), "42")
  expect_identical(out_get(attr(py, "out_id")), "42")
})

test_that("the cmd engine is refused outside Windows", {
  skip_on_os("windows")
  expect_error(bridge_knit("cmd", "dir"), class = "gptr_error_invalid_argument")
})

lang_line = paste("- Other languages: peter$py(code); peter$sql(query, name = df);",
                  "peter$knit(engine, code).")

test_that("builtin:lang registers py, sql and knit as peter$ members only", {
  for (nm in c("py", "sql", "knit")) {
    spec = registry_get("tool", nm)
    expect_s3_class(spec, "gptr_tool")
    expect_identical(spec$exposure, "r")
    expect_null(spec$namespace)
    expect_true(is.function(spec$execute))
    expect_false(spec$available(NULL))
    expect_true(all(gptr_check(spec)$ok))
    expect_true(inherits(peter[[nm]], "gptr_member"))
  }
  expect_identical(names(formals(registry_get("tool", "py")$fun)), c("code", "name", "max_rows"))
  expect_identical(formals(registry_get("tool", "py")$fun)$max_rows, 10L)
  expect_identical(names(formals(registry_get("tool", "sql")$fun)), c("query", "name", "con", "n"))
  expect_identical(formals(registry_get("tool", "sql")$fun)$n, 10L)
  expect_identical(names(formals(registry_get("tool", "knit")$fun)), c("engine", "code"))
  frag = registry_get("prompt_section", "languages")
  expect_identical(frag$text, lang_line)
  expect_identical(frag$parent, "r_session")
  expect_identical(as.integer(frag$order), 40L)
})

test_that("tool calls named py, sql or knit are refused before the permission check (S-4)", {
  skip_on_cran()
  local_project()
  calls = fake_tools(list("py", list(code = "import os")),
                     list("sql", list(query = "drop table t")),
                     list("knit", list(engine = "bash", code = "rm -rf data")))
  fake = local_fake_provider(list(calls, fake_text("done")))
  # manual mode without a human: a call that reached the permission check would stop the run
  s = peter("run them", model = fake, envir = new.env(), mode = "manual")
  res = Filter(function(m) identical(m$role, "tool_result"), s$messages)
  expect_identical(vapply(res, function(m) m$tool_name, ""), c("py", "sql", "knit"))
  for (m in res) {
    expect_true(isTRUE(m$is_error))
    expect_match(msg_text(m), "is an R function, not a tool", fixed = TRUE)
  }
  expect_identical(s$status, "idle")
})

test_that("SQL, Python and knit risks follow 04 (acceptance 3)", {
  sql = registry_get("tool", "sql")
  expect_identical(as.integer(sql$risk(list(query = "select * from t"), NULL)$level), 0L)
  expect_identical(as.integer(sql$risk(list(query = "drop table t"), NULL)$level), 3L)
  expect_identical(gptr_risk("peter$sql(\"select * from t\")")$level, 0L)
  expect_identical(gptr_risk("peter$sql(\"drop table t\")")$level, 3L)
  expect_gte(registry_get("tool", "py")$risk(list(code = "import subprocess"), NULL)$level, 3L)
  knit = registry_get("tool", "knit")
  expect_identical(as.integer(knit$risk(list(engine = "bash", code = "wc -l data.csv"),
                                        NULL)$level), 0L)
  expect_identical(knit$risk(list(engine = "perl", code = "print 1"), NULL)$level, 3L)
  expect_identical(knit$risk(list(engine = "sql", code = "select 1"), NULL)$level, 3L)
  expect_identical(knit$risk(list(engine = "python", code = "x = 1"), NULL)$level, 3L)
})

test_that("peter$sql(name = df) labels the table by the expression, at the console and in r", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  big = data.frame(v = seq_len(1000))
  expect_equal(peter$sql("SELECT COUNT(*) AS n FROM big", name = big)$n, 1000)
  skip_on_cran()
  local_project()
  e = new.env()
  e$orders = data.frame(id = 1:12)
  code = "n = peter$sql(\"SELECT COUNT(*) AS n FROM orders\", name = orders)$n"
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  peter("count the orders", model = fake, envir = e, mode = "auto")
  expect_equal(e$n, 12)
})

test_that("<r_session> carries the shell and languages lines in order", {
  t0 = gptr_prompt(preset = "standard")$system$t0
  at_shell = regexpr("- There is no shell tool.", t0, fixed = TRUE)
  at_lang = regexpr(lang_line, t0, fixed = TRUE)
  expect_gt(at_shell, 0)
  expect_gt(at_lang, at_shell)
})
