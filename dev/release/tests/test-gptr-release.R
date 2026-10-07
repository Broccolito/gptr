# Checks gptr's own release files (plan P25, Tasks 5-15). A failure lists the open problems.
test_that("DESCRIPTION declares the vignette builder (Task 5)", {
  expect_no_problems(files_description(gptr_root(), character()))
})

test_that("the getting-started vignette is precomputed and current (Task 5)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "getting-started"))
})

test_that("the system-one vignette is precomputed and current (Task 6)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "system-one"))
})

test_that("the extending-gptr vignette is precomputed and current (Task 8)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "extending-gptr"))
})

test_that("the token-efficiency vignette is precomputed and current (Task 9)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "token-efficiency"))
})

test_that("the script-as-history vignette is precomputed and current (Task 7)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "script-as-history"))
})

test_that("NEWS.md records the breaking changes (Task 11)", {
  expect_no_problems(files_news(gptr_root(), character()))
})
