# P32: counts calls of gptr functions while the originals run unchanged.
# `n = local_calls(c("env_snap_size", "call_risk"))`, then `n()` is a named count of each.
local_calls = function(names, .env = parent.frame()) {
  n = stats::setNames(integer(length(names)), names)
  ns = asNamespace("gptr")
  wrap = lapply(names, function(f) {
    orig = get(f, envir = ns)
    function(...) {
      n[[f]] <<- n[[f]] + 1L
      orig(...)
    }
  })
  do.call(testthat::local_mocked_bindings, c(stats::setNames(wrap, names), list(.env = .env)))
  function() n
}
