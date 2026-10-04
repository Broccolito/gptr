# CI-only resource check. R's _R_CHECK_CONNECTIONS_LEFT_OPEN_ covers examples;
# this explicit comparison also checks the complete test suite.
#
# The suite runs to its end (stop_on_failure = FALSE), so the connection table is compared even
# when tests fail; the gate then fails on failed tests, on a suite error and on any change of the
# table, reporting every one of them.
check_connections = function(code, failures = function(value) 0L) {
  # Match IC-60's R CMD check mode: processx's optional process-wide supervisor
  # deliberately retains two FIFOs until R exits. Child cleanup and orphan
  # recovery are still exercised; the table comparison has no exemptions.
  old = options(gptr.supervise = FALSE)
  on.exit(options(old), add = TRUE)
  before = showConnections(all = TRUE)
  value = tryCatch(force(code), error = function(e) e)
  after = showConnections(all = TRUE)
  problems = character()
  if (inherits(value, "error")) {
    problems = conditionMessage(value)
  } else {
    failed = failures(value)
    if (failed > 0L) problems = sprintf("the test suite had %d failed test(s)", failed)
  }
  if (!identical(before, after)) {
    leak = sprintf("R connection table changed during tests (before: %d, after: %d)",
                   nrow(before), nrow(after))
    problems = c(problems, leak)
  }
  if (length(problems)) stop(paste(problems, collapse = "\n"), call. = FALSE)
  invisible(value)
}

# Failed expectations plus errored tests of a testthat_results object
suite_failures = function(results) {
  df = as.data.frame(results)
  if (!nrow(df)) return(0L)
  as.integer(sum(df$failed) + sum(df$error))
}

# Run the whole suite through `test`, then fail on its failures and on leaked connections
run_gate = function(test = devtools::test, failures = suite_failures) {
  check_connections(test(stop_on_failure = FALSE), failures = failures)
}

if (sys.nframe() == 0L) {
  invisible(loadNamespace("devtools"))
  testthat::set_max_fails(Inf)
  run_gate()
}
