historical_news = function() {
  c("# gptr 1.0.0", "", "Intro.", "", "## Breaking changes", "",
    "* `get_response()` was removed.",
    "* `dataframe_to_text()` was removed; nothing of the 0.7.0 API is kept.", "",
    "## New features", "", "* `peter()`.", "", "# gptr 0.7.0", "", "* Old.")
}

test_that("news_problems() requires the 1.0.0 breaking changes", {
  good = historical_news()
  expect_identical(news_problems(good), character())
  expect_match(news_problems(good[-7]), "must name get_response()", fixed = TRUE)
  expect_match(news_problems(sub("0.7.0 API", "old API", good, fixed = TRUE)),
               "whole gptr 0.7.0 API", fixed = TRUE)
  expect_match(news_problems(sub("# gptr 1.0.0", "# gptr 1.0", good, fixed = TRUE))[1L],
               "first line")
  expect_true(any(grepl("no `## Breaking changes`", news_problems(good[-5]))))
  expect_true(any(grepl("no `## New features`", news_problems(good[-10]))))
})

test_that("patch NEWS keeps the historical rewrite without requiring new breaking changes", {
  patch = c("# gptr 1.0.1", "", "## Bug fixes", "", "* Faster startup.", "", historical_news())
  expect_identical(news_problems(patch), character())
  expect_match(news_problems(sub("get_response()", "old helper", patch, fixed = TRUE)),
               "must name get_response()", fixed = TRUE)
  expect_match(news_problems(patch[1:6]), "historical `# gptr 1.0.0` section", fixed = TRUE)
  expect_true(any(grepl("first line", news_problems(c("# gptr 1.0.1.9000", patch[-1])))))
})

test_that("files_news matches the first heading to DESCRIPTION", {
  root = withr::local_tempdir()
  patch = c("# gptr 1.0.1", "", "* Faster startup.", "", historical_news())
  writeLines(patch, file.path(root, "NEWS.md"))
  writeLines(c("Package: gptr", "Version: 1.0.1"), file.path(root, "DESCRIPTION"))
  expect_identical(files_news(root, character()), character())
  writeLines(c("Package: gptr", "Version: 1.0.2"), file.path(root, "DESCRIPTION"))
  expect_match(files_news(root, character()), "DESCRIPTION version 1.0.2", fixed = TRUE)
})
