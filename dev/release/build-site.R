# Builds the pkgdown site outside the repository and without keys (plan P25, Task 12).
# Usage, from the repository root: Rscript --vanilla dev/release/build-site.R [destination]
source(file.path("dev", "release", "lib.R"))
args = commandArgs(trailingOnly = TRUE)
dest = if (length(args)) args[1L] else file.path(dirname(tempdir()), "gptr-site")
problems = site_build(".", dest)
if (!length(problems)) writeLines(sprintf("build-site: site written to %s", dest))
rel_finish("build-site", problems)
