# Copy-safety rows of P22 (architecture 6.4 rules R1, R3 and R9; contract 1.3 and 12.3). Each row
# runs in a fresh `Rscript --vanilla` through P01's expect_no_copy(), which skips on CRAN and
# without capabilities("profmem"), and counts the copies the user's next in-place edit makes.

rscript_code = paste0("file.path(R.home('bin'), if (.Platform$OS.type == 'windows') ",
                      "'Rscript.exe' else 'Rscript')")

test_that("peter$sh() at the console leaves a big vector editable in place", {
  action = paste0("res = peter$sh(c(", rscript_code, ", '--vanilla', '-e', 'invisible(1)'))")
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, label = "peter$sh()")
  expect_identical(n, 0L)
})

test_that("peter$sh(input = big) leaves the input vector editable in place", {
  action = paste0("res = peter$sh(c(", rscript_code, ", '--vanilla', '-e', ",
                  "'invisible(readLines(file(\"stdin\")))'), input = big)")
  n = expect_no_copy(setup = "big = as.character(seq_len(2e5))", action = action,
                     edit = "big[1] = 'a'", label = "peter$sh(input = big)")
  expect_identical(n, 0L)
})

test_that("peter$sh(input = <raw>) leaves the raw vector editable in place", {
  action = paste0("res = peter$sh(c(", rscript_code, ", '--vanilla', '-e', 'invisible(1)'), ",
                  "input = big)")
  n = expect_no_copy(setup = "big = as.raw(rep(65L, 1e6))", action = action,
                     edit = "big[1] = as.raw(66L)", label = "peter$sh(input = <raw>)")
  expect_identical(n, 0L)
})

test_that("peter$sh() called from model code leaves a big vector editable in place", {
  code = paste0("res = peter$sh(c(", rscript_code, ", \"--vanilla\", \"-e\", \"invisible(1)\"))")
  action = paste0(
    "options(gptr.quiet = TRUE, gptr.interactive = FALSE); ",
    "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = ", deparse(code),
    ")), 'done')); s = peter('run it', model = fake, envir = globalenv(), mode = 'auto')"
  )
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, label = "peter$sh() in r")
  expect_identical(n, 0L)
})

test_that("a negative control: a reference kept by the action makes the next edit copy", {
  action = paste0("keep = list(big); res = peter$sh(c(", rscript_code,
                  ", '--vanilla', '-e', 'invisible(1)'))")
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, allow = 1L,
                     label = "negative control")
  expect_identical(n, 1L)
})

test_that("peter$sql(name = df) costs exactly the one documented copy on the next edit (R9)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  # A frame made by data.frame() copies its column on the first `big$v[1] = 0` even without gptr,
  # which would hide the bridge's copy; this one, built by setting class and row.names on a list,
  # edits in place, so the control counts 0 and the peter$sql() row exactly the copy that
  # duckdb's registration causes (measured with R 4.4.3 and duckdb 1.5.0: 0 and 1).
  setup = paste("big = list(v = runif(5e6)); class(big) = 'data.frame';",
                "attr(big, 'row.names') = c(NA, -5000000L)")
  control = expect_no_copy(setup = setup, action = "invisible(NULL)", edit = "big$v[1] = 0",
                           object = "big$v", label = "data frame column edit without gptr")
  expect_identical(control, 0L)
  n = expect_no_copy(setup = setup,
                     action = "x = peter$sql('SELECT count(*) AS n FROM big', name = big)",
                     edit = "big$v[1] = 0", object = "big$v", allow = 1L,
                     label = "peter$sql(name = big)")
  expect_identical(n, 1L)
})
