# R CMD check runs this original native fixture in a fresh Windows R process.
if (.Platform$OS.type == "windows" && identical(Sys.getenv("NOT_CRAN"), "true")) {
  source("testthat/ci-shard.R", local = TRUE)
  if (ci_native_shard(Sys.getenv("GPTR_CI_TEST_SHARD"))) withCallingHandlers({
    stopifnot(file.exists("testthat/test-bridge-python-native.R"))
    library(testthat)
    library(gptr)
    test_check("gptr", filter = "^bridge-python-native$",
      stop_on_failure = TRUE, stop_on_warning = TRUE)
  }, warning = function(warning) stop(conditionMessage(warning), call. = FALSE))
}
