# Keep the whole check process tree within two CPUs, including nested R children.
if (!identical(Sys.info()[["sysname"]], "Linux")) stop("Linux only", call. = FALSE)
cpus = parallel::mcaffinity()
stopifnot(length(cpus) > 0L)
cpus = head(cpus, 2L)
parallel::mcaffinity(cpus)
stopifnot(identical(parallel::mcaffinity(), cpus))
Sys.setenv(
  TESTTHAT_PARALLEL = if (length(cpus) > 1L) "true" else "false",
  TESTTHAT_CPUS = as.character(length(cpus)),
  OMP_THREAD_LIMIT = "2", OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1", RCPP_PARALLEL_NUM_THREADS = "1"
)
options(Ncpus = length(cpus))
probe = paste0(
  "cpus = parallel::mcaffinity(); ",
  "stopifnot(length(cpus) > 0L, length(cpus) <= 2L); ",
  "cat('inherited CPU ceiling verified\\n')"
)
status = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(probe)))
stopifnot(identical(status, 0L))
args = commandArgs(TRUE)
if (identical(args, "--probe")) quit(status = 0L)
# Match check-r-package's default unless the workflow explicitly overrides it.
if (!nzchar(Sys.getenv("_R_CHECK_FORCE_SUGGESTS_"))) {
  Sys.setenv(`_R_CHECK_FORCE_SUGGESTS_` = "false")
}
rcmdcheck::rcmdcheck(
  args = c("--no-manual", "--as-cran"), build_args = c("--no-manual", args),
  error_on = "warning", check_dir = "check"
)
