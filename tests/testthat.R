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
    source("testthat/ci-shard.R", local = TRUE)
    selected = ci_shard_files(ordinary)
    names = sub("[.][rR]$", "", sub("^test[-_]", "", selected))
    stopifnot(all(grepl("^[A-Za-z0-9_-]+$", names)), !anyDuplicated(names))
    result = test_check("gptr", filter = paste0("^(", paste(names, collapse = "|"), ")$"))
    # A CI shard fails unless each of its files, and no other, recorded a test result
    if (nzchar(Sys.getenv("GPTR_CI_TEST_SHARD"))) {
      ran = unique(as.data.frame(result)$file)
      wrong = union(setdiff(selected, ran), setdiff(ran, selected))
      if (length(wrong)) stop("CI shard files that did not run as selected: ", toString(wrong))
    }
  })
} else {
  test_check("gptr")
}
