# Copy-safety rows of P10 (architecture section 6.4; contract sections 1.3 and 12.3): designated
# values under the value policy, tool code evaluated in a function-frame home (moved from P09) and
# the describe member at the console and inside model code. Each row runs in a fresh `Rscript
# --vanilla` through P01's expect_no_copy() and passes when the user's next in-place edit of `big`
# makes no copy. The last row is a negative control: a held reference makes exactly one copy, so
# the zero counts above are not vacuous.

gate_off = "options(gptr.unsafe_no_permissions = TRUE, gptr.quiet = TRUE, gptr.interactive = FALSE)"

go = "s = peter('go', model = fake, envir = globalenv(), mode = 'auto')"

run_r = function(code, call = go) {
  fake = "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = '%s')), 'done'))"
  paste(gate_off, sprintf(fake, code), call, sep = "; ")
}

test_that("a designated value held by name (12 MB) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("gptr_return(big)"),
                 label = "value by name")
})

test_that("a designated value held as a copy (200 KB) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(25000)", action = run_r("gptr_return(big)"),
                 label = "value as copy")
})

test_that("an anonymous designated value (boxed) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("gptr_return(big * 2)"),
                 label = "boxed value")
})

test_that("gptr_return(big) outside a run leaves the object editable in place (IC-48)", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = "gptr_return(big)",
                 label = "outside a run")
})

test_that("tool code `n = 1L; length(d)` in a function-frame home leaves the object in place", {
  home = "f = function(d) peter('count', d, model = fake, mode = 'auto'); s = f(big)"
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("n = 1L; length(d)", call = home),
                 label = "function-frame home")
})

test_that("peter$describe(big) at the console and from model code leaves the object in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = "x = peter$describe(big)",
                 label = "describe (user)")
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("x = peter$describe(big)"),
                 label = "describe (model code)")
})

test_that("the harness counts a held reference (negative control)", {
  copies = expect_no_copy(setup = "big = runif(1.5e6)", action = "keep = list(big)",
                          allow = 1L, label = "negative control")
  expect_identical(copies, 1L)
})
