test_that("a required status audits one R version's real artifact layout and rejects gaps", {
  scope = new.env(parent = baseenv())
  sys.source(testthat::test_path("audit-shards.R"), envir = scope)
  root = withr::local_tempdir()
  entry = file.path(root, "native-probe.R")
  writeLines('stopifnot(file.exists("testthat/test-native.R"))', entry)
  files = c(paste0("test-", letters[1:4], ".R"), "test-native.R")
  for (i in 1:4) {
    dir = file.path(root, paste0("windows-shard-release-", i))
    dir.create(dir)
    table = data.frame(file = files[[i]], test = "probe", passed = i,
      failed = 0L, warning = 0L, error = FALSE, skipped = FALSE)
    saveRDS(list(selector = paste0(i, "/4"), files = files, native = "test-native.R",
      selected = files[[i]], native_selected = if (i == 1L) "test-native.R" else character(),
      results = table, sha = "same-source"), file.path(dir, "windows-shard-results.rds"))
    writeLines("Status: OK", file.path(dir, "00check.log"))
    writeLines(if (i == 1L) "[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1 ]" else "R header only",
      file.path(dir, "native-probe.Rout"))
  }
  result = scope$audit_shard_artifacts(root, "release", "same-source", files, entry)
  expect_identical(sum(result$passed), 10L)
  expect_error(scope$audit_shard_artifacts(root, "oldrel-4", "same-source", files, entry))
  expect_error(scope$audit_shard_artifacts(root, "unknown", "same-source", files, entry))
  writeLines("R header only", file.path(root, "windows-shard-release-1", "native-probe.Rout"))
  expect_error(scope$audit_shard_artifacts(root, "release", "same-source", files, entry))
})
