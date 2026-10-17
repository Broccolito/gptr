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
    source("testthat/helper-ci-shard.R", local = TRUE)
    selector = Sys.getenv("GPTR_CI_TEST_SHARD")
    selected = ci_test_shard(ordinary, selector)
    names = sub("[.][rR]$", "", sub("^test[-_]", "", selected))
    stopifnot(all(grepl("^[A-Za-z0-9_-]+$", names)), !anyDuplicated(names))
    result = test_check("gptr", filter = paste0("^(", paste(names, collapse = "|"), ")$"))
    if (nzchar(selector)) {
      table = as.data.frame(result)
      stopifnot(setequal(unique(table$file), selected))
      table = table[, !vapply(table, is.list, logical(1)), drop = FALSE]
      native_selected = if (ci_native_shard(selector)) native else character()
      out = Sys.getenv("GPTR_CI_TEST_RESULTS")
      if (nzchar(out)) saveRDS(list(selector = selector, files = files, native = native,
        native_selected = native_selected, selected = selected, results = table,
        sha = Sys.getenv("GITHUB_SHA")), out)
    }
  })
} else {
  test_check("gptr")
}
