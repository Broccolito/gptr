# Copy-safety rows for System 1 (plan P13; architecture 6.4 "System 1 on data and on a session",
# contract 1.3 and 12.3). Each row runs in a fresh `Rscript --vanilla` through P01's
# expect_no_copy(), which skips on CRAN and without capabilities("profmem"), and counts the
# tracemem copies of `object` made by `edit` after `action`.

# The child sees only the exports. Until P08 exports gptr() (its Task 12; D-113 item 3), the
# child takes the gateway closure from the namespace, as test-copy-eval.R does for internals;
# once gptr() is exported this line does nothing.
with_gptr = function(setup) {
  paste("if (!('gptr' %in% getNamespaceExports('gptr'))) gptr = get('gptr', asNamespace('gptr'))",
        setup, sep = "\n")
}

test_that("System 1 over a vector leaves the vector editable in place", {
  expect_no_copy(
    setup = with_gptr("big = runif(200)"),
    action = paste("judge = gptr_fake_provider(list(0.7), name = 'judge', type = 'classifier')",
                   "d = gptr('Is it above one half?', big, model = judge)", sep = "\n"),
    label = "gptr(question, big, model = judge)"
  )
})

test_that("a large matrix is one described state and stays editable in place", {
  expect_no_copy(
    setup = with_gptr("big = matrix(runif(4e6), 2000)"),
    action = paste("judge = gptr_fake_provider(list(0.7), name = 'judge', type = 'classifier')",
                   "d = gptr('Is the matrix plausible?', big, model = judge)", sep = "\n"),
    label = "gptr(question, matrix, model = judge)"
  )
})

test_that("a large named list is described, not held", {
  expect_no_copy(
    setup = with_gptr("lst = list(a = runif(2e5), b = 'x')"),
    action = paste("judge = gptr_fake_provider(list(0.7), name = 'judge', type = 'classifier')",
                   "d = gptr('Is the list fine?', lst, model = judge)", sep = "\n"),
    edit = "lst$a[1] = 0", object = "lst",
    label = "gptr(question, named list, model = judge)"
  )
})

test_that("a piped session is judged without touching the objects of its home", {
  expect_no_copy(
    setup = with_gptr("big = runif(5e6)"),
    action = paste("fake = gptr_fake_provider(list('The fit converged.'))",
                   "judge = gptr_fake_provider(list(0.9), name = 'judge', type = 'classifier')",
                   "s = gptr('Summarise the fit', model = fake, envir = globalenv())",
                   "d = s |> gptr('Did it work?', model = judge)", sep = "\n"),
    label = "s |> gptr(question, model = judge)"
  )
})
