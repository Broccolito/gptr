# Knits vignettes/*.Rmd.orig into the shipped vignettes/*.Rmd and renders README.Rmd, offline
# (plan P25, Tasks 5-10). The package is installed into a temporary library first, so the
# vignettes always run against the current source.
# Usage, from the repository root:
#   Rscript --vanilla dev/release/precompute.R [name ...]           knit the named (default: all)
#   Rscript --vanilla dev/release/precompute.R --check [name ...]   knit into a scratch copy
#   Rscript --vanilla dev/release/precompute.R --readme             render README.Rmd
source(file.path("dev", "release", "lib.R"))
args = commandArgs(trailingOnly = TRUE)
readme = "--readme" %in% args
wanted = setdiff(args, c("--check", "--readme"))
if (!length(wanted) && !readme) wanted = rel_vignettes()
problems = vig_precompute(".", wanted, write = !"--check" %in% args, readme = readme)
writeLines(sprintf("precompute: %d vignette(s) knitted in %.1f s", length(wanted),
                   attr(problems, "seconds")))
rel_finish("precompute", problems)
