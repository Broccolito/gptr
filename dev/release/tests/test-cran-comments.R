test_that("cran_comments_set_revdeps() records the submission-day result", {
  lines = c("## Submission", "", "Text.", "", "## Reverse dependencies", "", "old", "",
            "## Test environments", "", "* x")
  new = cran_comments_set_revdeps(lines, character(), as.Date("2026-10-20"))
  expect_true(any(grepl("run on 2026-10-20:", new, fixed = TRUE)))
  expect_true("none." %in% new)
  expect_false("old" %in% new)
  expect_identical(utils::tail(new, 3L), c("## Test environments", "", "* x"))
  expect_true("apkg, zpkg." %in% cran_comments_set_revdeps(lines, c("zpkg", "apkg")))
  last = c("## Submission", "", "## Reverse dependencies", "", "old")
  once = cran_comments_set_revdeps(last, character(), as.Date("2026-10-20"))
  expect_identical(cran_comments_set_revdeps(once, character(), as.Date("2026-10-20")), once)
  expect_error(cran_comments_set_revdeps("## Submission", character()), "exactly one")
})

test_that("cran_comments_problems() requires the consent design, precedents and revdeps", {
  lines = c("## Submission", "0.7.0 -> 1.0.0 removes get_response() and dataframe_to_text().",
            "## Consent and side effects",
            paste("'btw' 1.5.0, 'aisdk' 1.4.12, 'ellmer' 0.5.0, 'mcptools' 1.0.3; ?gptr_security;",
                  "SystemRequirements."),
            "## Examples, tests and vignettes",
            paste("gptr_fake_provider(); No example uses `\\dontrun{}`; @examplesIf;",
                  "gptr_login() gptr_mcp_serve()."),
            "## Test environments", "## R CMD check results", "## Reverse dependencies",
            paste0("`tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")`",
                   " run on 2026-09-29:"))
  expect_identical(cran_comments_problems(lines), character())
  expect_true(any(grepl("missing section ## Test environments",
                        cran_comments_problems(lines[-7]))))
  expect_true(any(grepl("must mention 'mcptools' 1.0.3",
                        cran_comments_problems(sub("'mcptools' 1.0.3", "", lines)))))
  expect_true(any(grepl("name the day", cran_comments_problems(sub("2026-09-29", "", lines)))))
  no_sysreq = sub("SystemRequirements", "", lines, fixed = TRUE)
  expect_true(any(grepl("must mention SystemRequirements", cran_comments_problems(no_sysreq))))
})
