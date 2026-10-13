# Builds the pkgdown site outside the repository and without keys (plan P25, Task 12).
# Usage: Rscript --vanilla dev/release/build-site.R [destination] [--pandoc DIRECTORY]
source(file.path("dev", "release", "lib.R"))
args = site_build_args(commandArgs(trailingOnly = TRUE))
dest = args$dest
problems = site_build(".", dest, pandoc = args$pandoc)
if (!length(problems)) writeLines(sprintf("build-site: site written to %s", dest))
rel_finish("build-site", problems)
