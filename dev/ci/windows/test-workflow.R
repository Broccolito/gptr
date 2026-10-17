test_that("required Windows checks aggregate every serial shard without weakening CRAN mode", {
  workflow = yaml::read_yaml(testthat::test_path(
    "../../../.github/workflows/Windows-check.yaml"))
  shards = workflow$jobs$shards
  expect_identical(unlist(shards$strategy$matrix$shard), 1:4)
  expect_identical(vapply(shards$strategy$matrix$config, function(x) x$r, character(1)),
                   c("release", "oldrel-4"))
  expect_identical(shards$env$TESTTHAT_PARALLEL, "false")
  expect_false(any(grepl("runner[.]", unlist(shards$env))))
  gate = workflow$jobs$verify
  expect_identical(gate$name, "windows-latest (${{ matrix.r }})")
  expect_identical(gate$needs, "shards")
  expect_identical(gate$`if`, "always()")
  expect_identical(unlist(gate$strategy$matrix$r), c("release", "oldrel-4"))
  expect_match(gate$steps[[1L]]$run, "needs.shards.result", fixed = TRUE)
  expect_true(any(vapply(gate$steps, function(x) {
    !is.null(x$run) && grepl("audit-shards.R", x$run, fixed = TRUE)
  }, logical(1))))
  original = yaml::read_yaml(testthat::test_path(
    "../../../.github/workflows/R-CMD-check.yaml"))
  expect_false(any(vapply(original$jobs$`R-CMD-check`$strategy$matrix$config,
    function(x) identical(x$os, "windows-latest"), logical(1))))
  cran = original$jobs$`cran-mode`
  expect_false(cran$env$NOT_CRAN)
  expect_null(cran$env$TESTTHAT_PARALLEL)
})
