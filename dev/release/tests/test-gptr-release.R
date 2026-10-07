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

test_that("README.md is rendered from README.Rmd (Task 10)", {
  expect_no_problems(files_readme(gptr_root(), character()))
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

test_that("_pkgdown.yml indexes every page (Task 12)", {
  expect_no_problems(files_pkgdown(gptr_root(), character()))
})

test_that("cran-comments.md and DESCRIPTION are ready for submission (Task 13)", {
  expect_no_problems(files_cran_comments(gptr_root(), character()))
  expect_no_problems(files_description(gptr_root(), "--release"))
})

test_that("the manual, vignettes and release files have no unknown words (Task 15)", {
  testthat::skip_if_not_installed("spelling")
  root = gptr_root()
  found = spelling::spell_check_package(root)
  expect_no_problems(sprintf("%s (%s)", found$word, vapply(found$found, paste, "",
                                                           collapse = ", ")))
  wl = file.path(root, "inst", "WORDLIST")
  wordlist = if (file.exists(wl)) readLines(wl, warn = FALSE) else character()
  cc = spelling::spell_check_files(file.path(root, "cran-comments.md"), ignore = wordlist,
                                   lang = "en_US")
  expect_no_problems(sprintf("cran-comments.md: %s", cc$word))
})
