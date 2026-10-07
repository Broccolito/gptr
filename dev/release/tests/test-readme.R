test_that("readme_problems() checks mentions, style and staleness", {
  rmd = c("---", "output: github_document", "---", "", "```{r}", "library(gptr)",
          "fake = gptr_fake_provider(list(\"hi\"))", "```",
          "install.packages(\"gptr\")", "vignette(\"getting-started\", package = \"gptr\")",
          "See ?gptr_security.")
  md = c("``` r", "library(gptr)", "fake = gptr_fake_provider(list(\"hi\"))", "```")
  expect_identical(readme_problems(rmd, md), character())
  expect_true(any(grepl("README.md: code differs", readme_problems(rmd, md[-2]))))
  expect_true(any(grepl("must mention ?gptr_security", readme_problems(rmd[-11], md),
                        fixed = TRUE)))
  bad = sub("fake = ", paste0("fake <", "- "), rmd, fixed = TRUE)
  expect_true(any(grepl("README.Rmd: uses the left arrow", readme_problems(bad, md))))
})
