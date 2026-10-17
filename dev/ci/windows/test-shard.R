test_that("CI partitions run every ordinary file exactly once and reject bad selectors", {
  scope = new.env(parent = baseenv())
  sys.source(testthat::test_path("../../../tests/testthat/helper-ci-shard.R"), envir = scope)
  files = paste0("test-", letters[1:9], ".R")
  groups = lapply(paste0(1:4, "/4"), function(id) scope$ci_test_shard(files, id))
  expect_identical(groups[[1L]], files[c(1L, 5L, 9L)])
  expect_identical(groups[[4L]], files[c(4L, 8L)])
  expect_identical(sort(unlist(groups, use.names = FALSE)), files)
  expect_identical(anyDuplicated(unlist(groups)), 0L)
  expect_identical(scope$ci_test_shard(files, ""), files)
  expect_identical(scope$ci_test_shard(rev(files), "1/4"), groups[[1L]])
  for (id in c("0/4", "5/4", "1/0", "1/100", "1.5/4", "a", "1/4x")) {
    expect_error(scope$ci_test_shard(files, id))
  }
})

test_that("native fixtures keep fresh entries but run only once across the CI shards", {
  scope = new.env(parent = baseenv())
  sys.source(testthat::test_path("../../../tests/testthat/helper-ci-shard.R"), envir = scope)
  expect_true(scope$ci_native_shard(""))
  expect_identical(vapply(paste0(1:4, "/4"), scope$ci_native_shard, logical(1),
    USE.NAMES = FALSE),
                   c(TRUE, FALSE, FALSE, FALSE))
  expect_error(scope$ci_native_shard("0/4"))
})
