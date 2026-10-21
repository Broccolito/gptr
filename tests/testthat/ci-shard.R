# Windows CI sets GPTR_CI_TEST_SHARD to "i/n": shard i runs every n-th ordinary test file from the
# i-th, and only shard 1 runs the native fixtures. Unset, every check is shard 1/1: the whole suite.
ci_shard = function(selector = Sys.getenv("GPTR_CI_TEST_SHARD", "1/1")) {
  stopifnot(grepl("^[1-9][0-9]*/[1-9][0-9]*$", selector))
  shard = as.integer(strsplit(selector, "/", fixed = TRUE)[[1L]])
  stopifnot(shard[[1L]] <= shard[[2L]])
  shard
}

ci_shard_files = function(files, shard = ci_shard()) {
  stopifnot(shard[[2L]] <= length(files))
  files = sort(files)
  files[(seq_along(files) - 1L) %% shard[[2L]] == shard[[1L]] - 1L]
}
