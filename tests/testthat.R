# Windows native files get fresh supervisors under R CMD check. Other checks keep one suite.
library(testthat)
library(gptr)

if (.Platform$OS.type == "windows" && identical(Sys.getenv("NOT_CRAN"), "true")) {
  local({
    native = c(
      "test-bridge-python-native.R",
      "test-proc-marker-family.R",
      "test-proc-rscript-native.R",
      "test-proc-windows-backpressure.R",
      "test-proc-writer-idle-boundary.R",
      "test-proc-writer-idle-slots.R",
      "test-proc-writer-prototype.R",
      "test-proc-writer-retirement.R",
      "test-proc-writer-runtime.R",
      "test-subagent-worker.R"
    )
    files = sort(list.files("testthat", pattern = "^test.*[.][rR]$"))
    stopifnot(length(files) > length(native), !anyDuplicated(files), all(native %in% files))
    stopifnot(all(grepl("^test-[A-Za-z0-9_-]+[.][rR]$", files)))
    ordinary = setdiff(files, native)
    names = sub("[.][rR]$", "", sub("^test[-_]", "", ordinary))
    stopifnot(all(grepl("^[A-Za-z0-9_-]+$", names)), !anyDuplicated(names))
    test_check("gptr", filter = paste0("^(", paste(names, collapse = "|"), ")$"))
  })
} else {
  test_check("gptr")
}
