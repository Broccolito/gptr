# CI-only resource check. R's _R_CHECK_CONNECTIONS_LEFT_OPEN_ covers examples;
# this explicit comparison also checks the complete test suite.
check_connections = function(code) {
  before = showConnections(all = TRUE)
  value = force(code)
  after = showConnections(all = TRUE)
  if (!identical(before, after)) {
    stop(sprintf("R connection table changed during tests (before: %d, after: %d)",
                 nrow(before), nrow(after)), call. = FALSE)
  }
  invisible(value)
}

if (sys.nframe() == 0L) {
  invisible(loadNamespace("devtools"))
  check_connections(devtools::test(stop_on_failure = TRUE))
}
