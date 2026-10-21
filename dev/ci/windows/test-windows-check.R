shard = new.env(parent = baseenv())
sys.source(testthat::test_path("../../../tests/testthat/ci-shard.R"), envir = shard)
root = testthat::test_path("../../..")
path = file.path(root, ".github", "workflows", "Windows-check.yaml")
jobs = yaml::read_yaml(path)$jobs
files = paste0("test-", letters[1:9], ".R")

test_that("the shards run each ordinary test file once, whatever the listing order", {
  groups = lapply(1:4, function(i) shard$ci_shard_files(rev(files), c(i, 4L)))
  expect_identical(groups[[1L]], files[c(1L, 5L, 9L)])
  expect_identical(sort(unlist(groups)), files)
  expect_identical(shard$ci_shard("3/4"), c(3L, 4L))
  for (selector in c("0/4", "5/4", "1/0", "a", "1/4x")) {
    expect_error(shard$ci_shard(selector), label = selector)
  }
  expect_error(shard$ci_shard_files(files[1:3], c(1L, 4L)))
})

test_that("unset, a check runs the whole suite; the native fixtures run in shard 1 only", {
  withr::local_envvar(GPTR_CI_TEST_SHARD = NA)
  expect_identical(shard$ci_shard(), c(1L, 1L))
  expect_identical(shard$ci_shard_files(rev(files)), files)
  entries = list.files(file.path(root, "tests"), pattern = "^native-.*[.]R$", full.names = TRUE)
  expect_length(entries, 10L)
  for (entry in entries) {
    guard = "  if (ci_shard()[[1L]] == 1L) withCallingHandlers({"
    expect_true(guard %in% readLines(entry), label = entry)
  }
})

test_that("each required context gates the four shards of its own R version", {
  shards = jobs$shards
  gate = jobs$gates
  expect_identical(gate$name, "windows-latest (${{ matrix.r }})")
  expect_identical(gate$strategy$matrix$r, shards$strategy$matrix$r)
  expect_identical(unlist(shards$strategy$matrix$shard), 1:4)
  expect_identical(shards$env$GPTR_CI_TEST_SHARD, "${{ matrix.shard }}/4")
  # A skipped required check counts as passing, so the gate always runs and fails closed
  expect_identical(gate[c("needs", "if")], list(needs = "shards", `if` = "always()"))
  marker = shards$steps[[length(shards$steps)]]
  expect_null(marker[["if"]])
  expect_identical(marker$with$name, "windows-ok-${{ matrix.r }}-${{ matrix.shard }}")
  expect_identical(gate$steps[[1L]]$with$pattern, "windows-ok-${{ matrix.r }}-*")
  expect_match(gate$steps[[2L]]$run, "for n in 1 2 3 4;", fixed = TRUE)
  # read_yaml reads yes as TRUE, but R keeps package sources only for the string "yes"
  expect_true("      R_KEEP_PKG_SOURCE: yes" %in% readLines(path))
})
