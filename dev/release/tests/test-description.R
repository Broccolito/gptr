dcf_of = function(...) {
  fields = list(Package = "gptr", Title = "Language Model Agents Inside the Live 'R' Session",
                Version = "1.0.0", Depends = "R (>= 4.2.0)",
                Imports = "jsonlite, curl, processx, callr, rlang, cli, yaml, ps",
                Suggests = "testthat (>= 3.2.0), withr, knitr, rmarkdown",
                VignetteBuilder = "knitr")
  fields = utils::modifyList(fields, list(...))
  matrix(unlist(fields), nrow = 1L, dimnames = list(NULL, names(fields)))
}

test_that("description_problems() checks the two fields P25 owns and guards the others", {
  expect_identical(description_problems(dcf_of(), "release"), character())
  expect_identical(description_problems(dcf_of(Version = "0.99.0.9000"), "vignettes"),
                   character())
  expect_match(description_problems(dcf_of(Version = "0.99.0.9000"), "release"),
               "Version must be 1.0.0")
  expect_match(description_problems(dcf_of(VignetteBuilder = NULL), "vignettes"),
               "VignetteBuilder must be knitr")
  expect_match(description_problems(dcf_of(Suggests = "testthat, ellmer, knitr, rmarkdown")),
               "ellmer must not be a dependency")
  expect_match(description_problems(dcf_of(Title = "Something Else")), "Title differs")
})
