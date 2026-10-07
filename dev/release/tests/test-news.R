test_that("news_problems() requires the 1.0.0 breaking changes", {
  good = c("# gptr 1.0.0", "", "Intro.", "", "## Breaking changes", "",
           "* `get_response()` was removed.",
           "* `dataframe_to_text()` was removed; nothing of the 0.7.0 API is kept.", "",
           "## New features", "", "* `peter()`.", "", "# gptr 0.7.0", "", "* Old.")
  expect_identical(news_problems(good), character())
  expect_match(news_problems(good[-7]), "must name get_response()", fixed = TRUE)
  expect_match(news_problems(sub("0.7.0 API", "old API", good, fixed = TRUE)),
               "whole gptr 0.7.0 API", fixed = TRUE)
  expect_match(news_problems(sub("# gptr 1.0.0", "# gptr 1.0", good, fixed = TRUE))[1L],
               "first line")
  expect_true(any(grepl("no `## Breaking changes`", news_problems(good[-5]))))
  expect_true(any(grepl("no `## New features`", news_problems(good[-10]))))
})
