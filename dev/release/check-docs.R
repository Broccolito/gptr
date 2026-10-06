# Audits the Rd pages of the 63 exports and the P25 help topics (plan P25, Task 1).
# Usage, from the repository root: Rscript --vanilla dev/release/check-docs.R
source(file.path("dev", "release", "lib.R"))
rel_finish("check-docs", docs_problems(rd_read_dir()))
