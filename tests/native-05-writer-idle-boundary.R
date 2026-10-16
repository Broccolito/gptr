# R CMD check runs this original native fixture in a fresh Windows R process.
if (.Platform$OS.type == "windows" && identical(Sys.getenv("NOT_CRAN"), "true")) {
  withCallingHandlers({
    stopifnot(file.exists("testthat/test-proc-writer-idle-boundary.R"))
    library(testthat)
    library(gptr)
    test_check("gptr", filter = "^proc-writer-idle-boundary$",
      stop_on_failure = TRUE, stop_on_warning = TRUE)
  }, warning = function(warning) stop(conditionMessage(warning), call. = FALSE))
}
