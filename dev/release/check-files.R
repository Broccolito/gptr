# Checks the release files (plan P25, from Task 5). Usage, from the repository root:
#   Rscript --vanilla dev/release/check-files.R <check> [flags]
source(file.path("dev", "release", "lib.R"))
args = commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("usage: check-files.R <check> [flags]", call. = FALSE)
fun = get0(paste0("files_", gsub("-", "_", args[1L], fixed = TRUE)), mode = "function")
if (is.null(fun)) stop("unknown check: ", args[1L], call. = FALSE)
rel_finish(paste("check-files", args[1L]), fun(".", args[-1L]))
