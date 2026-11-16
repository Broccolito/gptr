# Prototype (not gptr code): cheap ways to answer "is this binding above gptr.protect_size?"
# Usage: Rscript --vanilla bounded-size.R <workdir> <n_tables> <rows> <reps>
a = commandArgs(TRUE)
W = normalizePath(a[1])
N = as.integer(a[2])
R = as.integer(a[3])
reps = as.integer(a[4])
proj = file.path(W, "proj")
Sys.setenv(R_USER_CONFIG_DIR = file.path(W, "private/config"),
           R_USER_DATA_DIR = file.path(W, "private/data"),
           R_USER_CACHE_DIR = file.path(W, "private/cache"),
           GPTR_PROJECT_ROOT = proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
pkgload::load_all(file.path(W, "gptr-src"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
tag = sprintf("N%d_R%d", N, R)

g = R - 4L
ids = c(sprintf("ENSG%011d.%d", seq_len(g), 1L + seq_len(g) %% 9L),
        "N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous")
gnm = c(sprintf("GENE%d", seq_len(g) %% max(1L, g - as.integer(g / 50))), rep(NA_character_, 4L))
set.seed(1)
gty = c(sample(sprintf("type%02d", 1:40), g, replace = TRUE), rep(NA_character_, 4L))
idx = seq_len(R)
bi = as.integer(idx %% 997L)
bd = bi / 3
files = sprintf("inputs/%08d.rna_seq.augmented_star_gene_counts.tsv", seq_len(N))
tabs = vector("list", N)
for (i in seq_len(N)) {
  tabs[[i]] = data.table::data.table(gene_id = ids[idx], gene_name = gnm[idx], gene_type = gty[idx],
                                     unstranded = bi + i, stranded_first = bi + 2L * i,
                                     stranded_second = bi + 3L * i, tpm_unstranded = bd + i,
                                     fpkm_unstranded = bd + 2 * i, fpkm_uq_unstranded = bd + 3 * i)
}
home = new.env(parent = globalenv())
home$raw = list(files = files, tables = stats::setNames(tabs, files))
rm(tabs)

# Lower bound of R's allocation: vector headers and element arrays (8 bytes per string pointer,
# string contents not counted, so never above env_snap_size()); stops as soon as it passes `limit`.
size_exceeds = function(x, limit) {
  st = new.env(parent = emptyenv())
  st$b = 0
  per = c(logical = 4, integer = 4, double = 8, complex = 16, raw = 1, character = 8, list = 8,
          expression = 8)
  walk = function(x) {
    if (st$b > limit) return(invisible())
    t = typeof(x)
    p = per[t]
    if (!is.na(p)) st$b = st$b + 48 + 8 * ceiling(length(x) * p / 8)
    if (t %in% c("list", "expression")) {
      i = 1L
      while (i <= length(x) && st$b <= limit) {
        walk(.subset2(x, i))
        i = i + 1L
      }
    }
    invisible()
  }
  walk(x)
  st$b > limit
}

rows = list()
timeit = function(what, f, n = reps) {
  ts = numeric(n)
  val = NULL
  for (k in seq_len(n)) {
    invisible(gc(FALSE))
    s = clock()
    val = f()
    ts[k] = clock() - s
  }
  rows[[length(rows) + 1L]] <<- data.frame(config = tag, what = what, reps = n,
                                           median_s = stats::median(ts), min_s = min(ts),
                                           max_s = max(ts), value = format(val))
  cat(sprintf("[%s] %-44s median %8.4f s  value %s\n", tag, what, stats::median(ts), format(val)))
}
x = home$raw
timeit("env_snap_size (gptr, exact by D-247)", function() ns$env_snap_size(x, home), n = 1L)
timeit("size_exceeds(1e8) lower bound, early exit", function() size_exceeds(x, 1e8))
timeit("size_exceeds(Inf) lower bound, full walk", function() size_exceeds(x, Inf))
timeit("fingerprint (cache key)", function() ns$fingerprint(x))
timeit("utils::object.size (no string dedupe)", function() as.numeric(utils::object.size(x)), n = 1L)
utils::write.csv(do.call(rbind, rows), file.path(W, "results", paste0("bounded-size-", tag, ".csv")),
                 row.names = FALSE)
cat(sprintf("[%s] done\n", tag))
