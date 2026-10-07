# Runs the examples of every Rd page in a fresh R process: no keys, no network, home and user
# directories redirected, R CMD check's environment (plan P25, Task 4).
# Usage, from the repository root: Rscript --vanilla dev/release/check-examples.R
source(file.path("dev", "release", "lib.R"))
run = ex_run_all(".")
res = run$results[order(-run$results$seconds), ]
writeLines(sprintf("check-examples: %d pages; slowest %s (%.2f s)", nrow(res), res$page[1L],
                   res$seconds[1L]))
rel_finish("check-examples", run$problems)
