# Only the Windows non-CRAN entry opts in; default and CRAN checks keep the whole suite.
ci_shard_parts = function(selector) {
  stopifnot(grepl("^[1-9][0-9]*/[1-9][0-9]*$", selector))
  parts = as.integer(strsplit(selector, "/", fixed = TRUE)[[1L]])
  stopifnot(!anyNA(parts), parts[[1L]] <= parts[[2L]])
  parts
}

ci_native_shard = function(selector = "") {
  !nzchar(selector) || ci_shard_parts(selector)[[1L]] == 1L
}

ci_test_shard = function(files, selector = "") {
  files = sort(files)
  if (!nzchar(selector)) return(files)
  parts = ci_shard_parts(selector)
  stopifnot(parts[[2L]] <= length(files))
  files[(seq_along(files) - 1L) %% parts[[2L]] == parts[[1L]] - 1L]
}
