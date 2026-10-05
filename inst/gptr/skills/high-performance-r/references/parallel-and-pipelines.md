# Parallel workers and pipelines

## Choose a back-end

| Need | Use | Notes |
|---|---|---|
| Map a function over inputs, any OS | `mirai::daemons(n)` + `mirai::mirai_map(x, f, ...)[]` | low per-task overhead; `purrr::map(x, in_parallel(f))` (purrr >= 1.1.0, needs the `carrier` package) uses the same daemons |
| Code that already uses futures (Seurat, furrr, future.apply) | `future::plan(future::multisession, workers = n)` | `future.mirai::mirai_multisession` is a faster drop-in plan |
| Base R only | `cl = parallel::makeCluster(n); parallel::parLapply(cl, x, f); parallel::stopCluster(cl)` | PSOCK works on every OS |
| Fork on Linux/macOS terminal only | `parallel::mclapply(x, f, mc.cores = n)` | fastest start-up; not on Windows; unsafe in RStudio/GUIs and after multi-threaded code |
| Bioconductor functions with `BPPARAM` | `BiocParallel::SnowParam(n)` (all OS) or `MulticoreParam(n)` (Unix) | |
| Cached multi-step pipeline | `targets` + `crew::crew_controller_local(workers = n)` | re-runs only outdated steps |

Measured on an 8-core laptop (loaded machine, indicative only): starting 4 workers took
about 0.3 s (PSOCK), 0.8 s (mirai with dispatcher, future multisession) and 0.02 s
(fork); 200 tiny tasks on warm workers took 1-60 ms; sending an 80 MB data frame to 4
workers took 1.4-2.4 s. So: start workers once, reuse them, and send data once.

## Rules

- Worker count: stay within `<r_env>`; leave one core for the session. Under
  `R CMD check` use at most 2.
- Do not nest parallelism: inside workers set `data.table::setDTthreads(1)`, arrow
  `arrow::set_cpu_count(1)`, duckdb `SET threads = 1`, qs2 `nthreads = 1`.
- Pass what the function needs explicitly (`mirai_map(x, f, big = big)`,
  `in_parallel(f, big = big)`); workers do not see the session's global environment.
  Named `...` objects become free variables of `f`, not arguments: write `f = function(i) g(i, big)`;
  constant *arguments* go in `mirai_map(x, f, .args = list(k = 2))`.
- mirai returns task errors as values (`miraiError`), not as R errors: collect with `[.stop]`
  (or check `mirai::is_error_value()`) so a failure is not mistaken for a result.
- Workers are fresh R processes: they do not inherit `.libPaths()` changes made at run time.
  Before starting them: `Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))`.
- Large shared inputs: write once to disk (Parquet/qs2) and let each worker read its slice,
  instead of serialising the object to every worker.
- `future` blocks globals above 500 MiB: `options(future.globals.maxSize = 8 * 1024^3)` only
  if memory allows (each worker gets a copy).
- Always shut down: `mirai::daemons(0)`, `parallel::stopCluster(cl)`, `future::plan(future::sequential)`.

## Recipes

```r
# mirai
mirai::daemons(2)
sq = mirai::mirai_map(1:8, function(i, k) i^k, .args = list(k = 2))[.stop]   # errors stop
mirai::everywhere(library(stats))                             # set up each worker
mirai::daemons(0)
```

```r
# future + future.apply
future::plan(future::multisession, workers = 2)
r = future.apply::future_lapply(1:8, function(i) i^2, future.seed = TRUE)
future::plan(future::sequential)
```

```r
# base R, portable
cl = parallel::makeCluster(2)
parallel::clusterExport(cl, character(0))                     # export what workers need
r = parallel::parLapply(cl, 1:8, function(i) i^2)
parallel::stopCluster(cl)
```

```r
# BiocParallel
r = BiocParallel::bplapply(1:8, function(i) i^2, BPPARAM = BiocParallel::SnowParam(2))
```

```r
# targets: write _targets.R in the project, then run tar_make()
dir = tempfile()
dir.create(dir)
old = setwd(dir)
writeLines(c(
  'library(targets)',
  'tar_option_set(packages = "stats")',
  'list(',
  '  tar_target(raw, data.frame(x = rnorm(100), g = sample(letters[1:3], 100, TRUE))),',
  '  tar_target(fit, lm(x ~ g, data = raw)),',
  '  tar_target(summary_tbl, coef(summary(fit)))',
  ')'), "_targets.R")
targets::tar_make(reporter = "silent")
res = targets::tar_read(summary_tbl)
setwd(old)
# parallel targets: tar_option_set(controller = crew::crew_controller_local(workers = 2))
```
