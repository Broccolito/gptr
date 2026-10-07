toy_vignette_package = function(vignette_code) {
  root = file.path(tempfile("toyvig-"), "toyvig")
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "vignettes"))
  writeLines(c("Package: toyvig", "Title: Toy Package for the Vignette Runner", "Version: 0.0.1",
               "Authors@R: person(\"A\", \"B\", email = \"a@b.org\", role = c(\"aut\", \"cre\"))",
               "Description: A toy package used by the gptr release self-tests.",
               "License: MIT", "Encoding: UTF-8"),
             file.path(root, "DESCRIPTION"))
  writeLines("export(twice)", file.path(root, "NAMESPACE"))
  writeLines("twice = function(x) 2 * x", file.path(root, "R", "twice.R"))
  writeLines(c("---", "title: \"Intro\"", "output: rmarkdown::html_vignette", "vignette: >",
               "  %\\VignetteIndexEntry{Intro}", "  %\\VignetteEngine{knitr::rmarkdown}",
               "  %\\VignetteEncoding{UTF-8}", "---", "",
               "```{r setup, include = FALSE}",
               "knitr::opts_chunk$set(collapse = TRUE, comment = \"#>\", error = FALSE)",
               "```", "", "Some text.", "", "```{r}", vignette_code, "```", "",
               "```{r, eval = FALSE}", "twice(\"not run\")", "```"),
             file.path(root, "vignettes", "intro.Rmd.orig"))
  writeLines(c("---", "output: github_document", "---", "",
               "```{r setup, include = FALSE}",
               "knitr::opts_chunk$set(collapse = TRUE, comment = \"#>\", error = FALSE)",
               "```", "", "```{r}", "library(toyvig)", "twice(21)", "```"),
             file.path(root, "README.Rmd"))
  root
}

test_that("rmd_chunks() and md_code_blocks() see the same code", {
  src = c("```{r setup, include = FALSE}", "hidden = 1", "```", "text", "```{r}", "x = 1", "",
          "x", "```", "```{r, eval = FALSE}", "y = 2", "```")
  knitted = c("text", "```r", "x = 1", "", "x", "#> [1] 1", "```", "", "```r", "y = 2", "```")
  expect_identical(rel_code_lines(rmd_chunks(src)), c("x = 1", "x", "y = 2"))
  expect_identical(rel_code_lines(md_code_blocks(knitted)), c("x = 1", "x", "y = 2"))
  expect_identical(stale_problems(src, knitted, "v"), character())
  expect_match(stale_problems(sub("x = 1", "x = 2", src), knitted, "v"), "code differs")
})

test_that("vig_precompute() knits offline, writes Markdown and detects stale or bad vignettes", {
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  root = toy_vignette_package(c("library(toyvig)", "twice(21)"))
  problems = vig_precompute(root, names = "intro", write = TRUE, readme = TRUE)
  expect_identical(as.character(problems), character())
  rmd = readLines(file.path(root, "vignettes", "intro.Rmd"))
  expect_true("#> [1] 42" %in% rmd)
  expect_false(any(grepl("^```+\\s*\\{", rmd)))
  expect_true(file.exists(file.path(root, "README.md")))
  expect_true("#> [1] 42" %in% readLines(file.path(root, "README.md")))
  expect_lt(attr(problems, "seconds"), 60)
  unlink(file.path(root, "README.md"))
  expect_identical(as.character(vig_precompute(root, names = character(), readme = TRUE)),
                   character())
  expect_true(file.exists(file.path(root, "README.md")))

  orig = file.path(root, "vignettes", "intro.Rmd.orig")
  writeLines(sub("twice(21)", "twice(20)", readLines(orig), fixed = TRUE), orig)
  expect_true(any(grepl("code differs from its source",
                        vig_precompute(root, names = "intro", write = FALSE))))

  bad = toy_vignette_package(c("library(toyvig)", paste0("x <", "- twice(1)"),
                               "stop(\"broken\")"))
  out = vig_precompute(bad, names = "intro", write = TRUE)
  expect_true(any(grepl("knitting failed", out)))
  expect_true(any(grepl("uses the left arrow", out)))
  expect_match(vig_precompute(bad, names = "missing", write = TRUE), "missing.Rmd.orig is missing")
})
