---
name: high-performance-r
description: "Fast data work in R: data.table, arrow, duckdb, collapse or qs2 when installed; large CSV/Parquet, grouping, sorting, parallel work, single-cell objects."
license: MIT
metadata:
  source: "gptr research report 19, section 3.4 (verified recipes)"
---

# High-performance R

You are working inside the user's live R session. The objects in memory are the asset:
a 5 GB object may have taken minutes to build. Every rule below serves two goals: finish
fast, and never lose or duplicate what is already in memory.

## Ground rules

1. **Use what is installed.** The `<r_env>` section lists installed packages. Use them
   opportunistically; if the best tool is missing, use the base-R fallback from the table
   and *mention* the faster option. Never run `install.packages()`, `BiocManager::install()`,
   `remotes::install_*()` or `update.packages()` without the user's explicit yes (see
   "Installing" at the end).
2. **Look before you load or print.** `dim(x)`, `nrow(x)`, `object.size(x)`, `file.size(path)`,
   `head(x)` and `peter$describe(x)`. Never print a whole large object into the transcript.
   Do not call the base function `str` on a large object: it leaves a sticky reference, so
   the next in-place edit of that object copies all of it. `peter$describe(x)` is copy-free.
3. **Do not copy big objects.** `y = x; y$col = ...` copies `x` on write. Prefer
   `data.table` in-place updates (`:=`, `set()`, `setorder()`, `setnames()`), work on column
   subsets, and `rm(tmp); invisible(gc())` large temporaries.
4. **Probe before `library()` of an unloaded compiled package** when the session holds
   valuable objects: `callr::r(function() loadNamespace("pkg"))` first. In R 4.4 (and,
   probably, every release before 4.6.1) one failed `dyn.load()` with a long error can corrupt
   the session so the *next* package load crashes R.
5. **Measure.** `system.time()` for one-off timing, `bench::mark()` to compare, `profvis`
   to find hotspots. Optimise the slowest step only.
6. **Threads and workers.** Stay within the worker count in `<r_env>`. data.table, arrow,
   duckdb and qs2 are already multi-threaded; do not also run them inside parallel workers
   without lowering their threads (`data.table::setDTthreads(1)`,
   `DBI::dbExecute(con, "SET threads = 1")`, `qs2` `nthreads = 1`).

## Decision table

| Task | Best tool (if installed) | Prefer when | Base-R fallback |
|---|---|---|---|
| Read CSV/TSV | `data.table::fread()` | general default; auto-detects types, multi-threaded | `read.csv(colClasses=, nrows=)` |
| | `arrow::read_csv_arrow()` | fastest on big files; also need Parquet later | |
| | `vroom::vroom()` | only a few columns will be touched (lazy ALTREP) | |
| | `readr::read_csv()` | tidyverse-consistent parsing; small/medium files | |
| Write CSV | `data.table::fwrite()` | always (about 30x faster than `write.csv`) | `write.csv(row.names = FALSE)` |
| Read a window of a huge text file | `vroom::vroom_lines(skip=, n_max=)` | random access deep into a file | `readLines(con, n=)` on an open connection |
| Parquet read/write | `arrow::read_parquet()`/`write_parquet()` | nested types, datasets, cloud | none (use CSV or RDS) |
| | `nanoparquet::read_parquet()`/`write_parquet()` | flat tables, zero dependencies | |
| Query data larger than RAM | `duckdb` SQL on `read_parquet()`/`read_csv_auto()` | joins/aggregations over files; spills to disk | loop over chunks with `read.csv(skip=, nrows=)` |
| | `arrow::open_dataset()` + dplyr verbs + `collect()` | partitioned Parquet directories | |
| | `duckplyr` (`read_parquet_duckdb()`) | user wants dplyr syntax on duckdb | |
| In-memory wrangling | `data.table` | >1e6 rows, joins, in-place updates, grouped ops | `split()`/`lapply()`, `merge()`, `aggregate()` |
| | `collapse` | fastest grouped statistics, low overhead | `rowsum()`, `tapply()` |
| | `dplyr` (+ `dtplyr`/`tidytable` backends) | readability; <1e6 rows or few groups | |
| Grouped statistics | `collapse::fmean(x, g)`, data.table `dt[, .(m = mean(x)), by = g]` | many groups | `rowsum(x, g) / tabulate(g)`, `tapply()` |
| Matrix row/col stats | `matrixStats::colMedians()`, `colSds()`; `collapse::fsd()` | dense numeric matrices | `colMeans()`, `rowSums()` (fast); `apply()` (slow) |
| Strings | `stringi` (`stri_detect_fixed`, `stri_replace_all_fixed`, `stri_trans_general`) | Unicode-correct ops, locales, transliteration | `grepl(fixed = TRUE)`, `gsub(perl = TRUE)`, `startsWith()` |
| Regex search | base `grepl(pattern, x, perl = TRUE)` | regex over many strings (fastest here) | same (avoid the default TRE engine: roughly 5-75x slower, pattern-dependent) |
| Sort | `order(x, method = "radix")`, `data.table::setorder()` (in place) | numbers, factors, byte-order strings | `order()` |
| Locale/natural sort | `stringi::stri_sort(x, numeric = TRUE)`, `stri_order(x, locale = "en")` | file names like `file2 < file10` | `order()` (locale collation, slow) |
| Top-k of a large vector | `kit::topn(x, k)` | k much smaller than n | `sort(x, partial = n - k + 1)` or `order(x, decreasing = TRUE)[1:k]` |
| Save/load R objects | `qs2::qs_save()`/`qs_read()` | any object; fast, compact, multi-threaded | `saveRDS(x, f, compress = FALSE)` (fast, large) |
| | `qs2::qd_save()`/`qd_read()` | plain data (no formulas/closures) | `saveRDS()` (gzip, slow to write) |
| | `fst::write_fst()`/`read_fst(columns=, from=, to=)` | data frames, read a column/row subset | |
| Sparse matrices | `Matrix` (`dgCMatrix`) | mostly zeros (single-cell, text) | dense `matrix` only if small |
| Larger-than-RAM matrices | `DelayedArray`/`HDF5Array`, `BPCells`, `bigmemory` | on-disk, block-wise processing | process column blocks from files |
| Parallel map | `mirai::mirai_map()`, `future.apply::future_lapply()`, `furrr` | portable, all OSes | `parallel::parLapply()` (PSOCK), `mclapply()` (Unix only) |
| Bioconductor parallel | `BiocParallel::bplapply(BPPARAM = SnowParam(n))` | Bioc functions take `BPPARAM` | `parallel` |
| Multi-step pipeline with caching | `targets` (+ `crew` workers) | long pipelines re-run after edits | scripts + `saveRDS()` checkpoints |
| Profile / benchmark | `profvis::profvis()`, `bench::mark()` | find hotspots, compare options with memory | `Rprof()` + `summaryRprof()`, `system.time()` |
| Plot >1e5 points | `scattermore::geom_scattermore()`, `ggrastr::rasterise()`, `geom_hex()` | millions of points, vector output | `png()` + `plot(pch = ".")`, `smoothScatter()` |
| Single-cell | Seurat v5 layers + BPCells on disk; SingleCellExperiment + HDF5Array | >100k cells | `Matrix` sparse |

Not recommended by default: `polars` (not on CRAN; R-multiverse only), `qs` (archived on
CRAN 2026-01-17; its `.qs` files are not readable by qs2), `disk.frame` (archived).

## Recipes

### Delimited files
```r
path = tempfile(fileext = ".csv")
df = data.frame(id = 1:1e5, g = sample(letters, 1e5, TRUE), x = runif(1e5))
data.table::fwrite(df, path)                       # write
dt = data.table::fread(path)                       # read everything
dt2 = data.table::fread(path, select = c("g", "x"), nrows = 1000)   # columns / first rows only
tb = arrow::read_csv_arrow(path, col_select = c("id", "x"))
peek = readLines(path, n = 5)                      # look at the head before parsing
```

### Parquet and queries on files (larger than memory)
```r
pq = tempfile(fileext = ".parquet")
df = data.frame(g = sample(letters, 1e5, TRUE), k = sample(1:100, 1e5, TRUE), x = runif(1e5))
arrow::write_parquet(df, pq)                       # or nanoparquet::write_parquet(df, pq)
small = nanoparquet::read_parquet(pq)              # flat tables, zero dependencies
# duckdb: SQL straight on the file, nothing loaded until the result
con = DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", file.path(tempdir(), "duckdb_tmp")))
res = DBI::dbGetQuery(con, sprintf(
  "SELECT g, avg(x) AS mean_x, count(*) AS n FROM read_parquet('%s') WHERE k > 50 GROUP BY g ORDER BY g", pq))
DBI::dbDisconnect(con, shutdown = TRUE)
# arrow datasets: lazy dplyr pipeline, collect() at the end
library(dplyr)
res2 = arrow::open_dataset(pq) |> filter(k > 50) |> group_by(g) |>
  summarise(mean_x = mean(x), n = n()) |> collect()
```
Partitioned output: `arrow::write_dataset(df, dir, partitioning = "g")`; read it back with
`arrow::open_dataset(dir)`. duckdb uses up to 80% of RAM by default; lower it with
`SET memory_limit = '4GB'` when the R session itself holds large objects.

### data.table idioms (fast and in place)
```r
library(data.table)
dt = data.table(g = sample(1e4, 1e6, TRUE), x = rnorm(1e6), y = runif(1e6))
agg = dt[, .(m = mean(x), s = sum(y), n = .N), by = g]    # GForce: keep mean/sum unqualified
dt[, z := x * 2]                                           # add a column without copying
dt[x < 0, x := 0]                                          # conditional update in place
setorder(dt, g, -x)                                        # sort in place
setkey(dt, g)
lookup = data.table(g = 1:10, label = letters[1:10], key = "g")
joined = lookup[dt, on = "g", nomatch = NULL]              # inner join
wide = dcast(agg[g <= 5], . ~ g, value.var = "m")
```
Check the optimisation with `dt[, .(m = mean(x)), by = g, verbose = TRUE]` ("GForce optimized j").
Writing `base::mean(x)` or `stats::median(x)` in `j` turns GForce off (measured up to 36x slower).

### collapse (fastest grouped statistics)
```r
library(collapse)                                   # attach it: fsummarise needs unqualified names
df = data.frame(g = sample(1e4, 1e6, TRUE), h = sample(letters, 1e6, TRUE), x = rnorm(1e6))
m1 = fmean(df$x, g = df$g)                          # vector API, named by group
out = df |> fgroup_by(g, h) |> fsummarise(mx = fmean(x), n = fnobs(x))
```
`collapse::fsummarise(..., m = collapse::fmean(x))` with the `collapse::` prefix inside is
evaluated group by group (measured 100x slower on 250k groups).

### Strings and regex
```r
x = c("file10.R", "file2.R", "File1.R", "na\u00efve.R")
hit_fixed = grepl(".R", x, fixed = TRUE)            # literal
hit_re = grepl("^file[0-9]+\\.R$", x, perl = TRUE, ignore.case = TRUE)
first_pos = regexpr("[0-9]+", x, perl = TRUE)       # prefer regexpr over gregexpr on big vectors
stringi::stri_sort(x, numeric = TRUE)               # natural order: File1, file2, file10
stringi::stri_trans_general("na\u00efve", "Latin-ASCII")   # "naive"
```

### Sorting and top-k
```r
x = runif(1e6)
s = sprintf("id_%06d", sample(1e6))
o = order(x, method = "radix")
os = order(s, method = "radix")                     # fast, byte order (C locale), not dictionary order
top = kit::topn(x, 10L)                             # indices of the 10 largest
top_base = order(x, decreasing = TRUE)[1:10]        # fallback
```

### Saving objects
```r
obj = list(df = data.frame(a = 1:10), fit = lm(mpg ~ wt, mtcars))
f = tempfile(fileext = ".qs2")
qs2::qs_save(obj, f, nthreads = 2)                  # any R object
obj2 = qs2::qs_read(f, nthreads = 2)
qs2::qs_to_rds(f, sub("qs2$", "rds", f))            # convert to plain RDS when sharing
saveRDS(obj, tempfile(fileext = ".rds"), compress = FALSE)   # base: fast write, larger file
```
`qd_save()` silently drops language objects (formulas, calls, model terms) with only a
warning; the file is still written and a model fit comes back broken. Use `qs_save()` for
model fits. RDS with default gzip is slow to write for big objects (measured about 20x
slower than `qs2` with 4 threads on a 50 MB data frame).

### Matrices
```r
library(Matrix)
sp = rsparsematrix(20000, 5000, density = 0.02)     # never as.matrix() this
cs = colSums(sp)
rm_ = rowMeans(sp)                                  # Matrix methods stay sparse
m = matrix(rnorm(1e6), 1000)
med = matrixStats::colMedians(m)                    # vs apply(m, 2, median)
sds = matrixStats::colSds(m)
```

### Parallel work
Read `references/parallel-and-pipelines.md` (mirai, future, BiocParallel, targets + crew,
thread oversubscription, library paths in workers): `read skill:high-performance-r/references/parallel-and-pipelines.md`.

### Profiling
```r
f = function(n) { x = numeric(0); for (i in 1:n) x = c(x, i); sum(x) }
g = function(n) sum(seq_len(n))
print(system.time(f(2e4)))
b = bench::mark(f(2e4), g(2e4), check = TRUE, min_iterations = 3)
print(b[, c("expression", "median", "mem_alloc")])
# p = profvis::profvis(f(5e4))   # interactive flame graph (opens a viewer)
```

### Plotting many points
```r
library(ggplot2)
d = data.frame(x = rnorm(1e6), y = rnorm(1e6))
p1 = ggplot(d, aes(x, y)) + scattermore::geom_scattermore(pointsize = 1, pixels = c(1000, 1000))
p2 = ggplot(d, aes(x, y)) + ggrastr::rasterise(geom_point(size = 0.1), dpi = 150)
p3 = ggplot(d, aes(x, y)) + geom_hex(bins = 100)    # needs the hexbin package
ggsave(tempfile(fileext = ".png"), p1, width = 5, height = 5, dpi = 100)
```

### Single-cell
Read `references/single-cell.md` (Seurat v5 layers, BPCells on-disk counts, sketching,
SingleCellExperiment + HDF5Array/DelayedArray, `future.globals.maxSize`):
`read skill:high-performance-r/references/single-cell.md`.

## Pitfalls that cost the most time

- `pkg::fun` inside `data.table` `j` or `collapse::fsummarise` disables the fast path.
- `order()` / `sort()` on character vectors without `method = "radix"` uses locale collation
  (40x slower on 1e6 strings); radix gives byte order (`"B" < "a"`).
- Default regex engine (TRE) on 1e5+ strings: use `perl = TRUE` or `fixed = TRUE`.
- `gregexpr()` on big vectors allocates heavily; use `regexpr()` or `grepl()` if one match suffices.
- `object.size()` over-counts shared and ALTREP objects (`1:1e9` reports 3.7 GB); `lobstr::obj_size()` is accurate but slower.
- `vroom()` returns lazy (ALTREP) columns: the read is fast, the first full pass pays the parsing cost.
- `saveRDS()` default gzip is slow on big objects; `compress = FALSE` or `qs2`.
- Building a result with `x = c(x, new)` or `paste0(acc, piece)` in a loop is quadratic; collect pieces in a pre-sized list/vector and combine once.
- `mclapply()`/`plan(multicore)` forks: unavailable on Windows, discouraged in RStudio/GUIs.
- Worker processes do not see `.libPaths()` changes made in the session; set `R_LIBS` before starting workers or call `.libPaths()` on each worker.
- `future` refuses to export globals over 500 MiB (`options(future.globals.maxSize = ...)`); sending a big object to workers costs seconds per 100 MB. Prefer workers that read the data from disk themselves.
- duckdb writes spill files to `.tmp` in the working directory when memory runs out; set `temp_directory`.
- `duckplyr::read_parquet_duckdb()` returns a "prudent" lazy frame: `nrow()`, printing or other
  implicit materialisation of more than 1,000,000 cells (rows x columns, e.g. 125,000 rows of an
  8-column table) is an error; aggregate first, then `collect()`.

## Installing (only after the user says yes)

| Source | Command |
|---|---|
| CRAN | `install.packages("duckdb")` |
| Bioconductor (`DelayedArray`, `HDF5Array`, `SingleCellExperiment`, `BiocParallel`) | `BiocManager::install("HDF5Array")` |
| BPCells (GitHub / R-universe, needs HDF5 system library) | `install.packages("BPCells", repos = c("https://bnprks.r-universe.dev", "https://cloud.r-project.org"))` |
| polars (R-multiverse) | `install.packages("polars", repos = "https://community.r-multiverse.org")` |

After installing, re-check `<r_env>` (gptr refreshes it) and prefer binary packages on
Windows and macOS (`type = "binary"` is the default there).
