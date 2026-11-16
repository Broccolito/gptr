# Cost drivers inside env_snap_size() for a T03-shaped object: list(files, tables = <k data.tables>),
# each 60,664 x 9 with three character columns whose strings are shared across tables (as fread of
# identical gene IDs gives). Counts how many tables the sampled walk visits and where time goes.
# Usage: Rscript --vanilla probe-size.R <k> <reps> <outdir>
a = commandArgs(TRUE)
k = as.integer(a[1]); reps = as.integer(a[2]); out = a[3]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
data.table::setDTthreads(1)
pkgload::load_all("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/path-map/src/gptr",
                  quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
size = get("env_snap_size", ns)
n = 60664L
set.seed(2)
ids = c(paste0("N_", 1:4), sprintf("ENSG%011d.%d", seq_len(n - 4L), 1L))
gn = c(rep(NA_character_, 4), sprintf("GENE%05d", seq_len(n - 4L) %% 59000L))
gt = c(rep(NA_character_, 4), sample(sprintf("type_%02d", 1:50), n - 4L, TRUE))
mk = function() data.table::data.table(gene_id = ids, gene_name = gn, gene_type = gt,
  unstranded = rpois(n, 5) + 0, stranded_first = rpois(n, 2) + 0, stranded_second = rpois(n, 2) + 0,
  tpm_unstranded = runif(n), fpkm_unstranded = runif(n), fpkm_uq_unstranded = runif(n))
files = sprintf("%04d.tsv", seq_len(k))
# fresh character vectors per table (as fread allocates), strings shared through R's CHARSXP cache
tables = lapply(seq_len(k), function(i) { d = mk(); d$gene_id = paste0(d$gene_id, ""); d })
raw = list(files = files, tables = stats::setNames(tables, files))
rm(tables)
home = new.env(parent = globalenv()); home$raw = raw; rm(raw)
cat("k", k, "object.size MB", round(as.numeric(utils::object.size(home$raw)) / 2^20), "\n")

# how many tables does the sampled walk visit? count env_size_walk() calls on data.tables
cnt = new.env(); cnt$dt = 0L; cnt$uniq = 0L; cnt$strs = 0L; cnt$strs_len = 0
inc = function(key) cnt[[key]] = cnt[[key]] + 1L
trace("env_size_walk", where = ns, print = FALSE,
      tracer = quote(if (inherits(x, "data.table")) get("inc", .GlobalEnv)("dt")))
trace("env_size_strings", where = ns, print = FALSE,
      tracer = quote(get("inc", .GlobalEnv)("strs")))
b = size(home$raw, home)
untrace("env_size_walk", where = ns); untrace("env_size_strings", where = ns)
cat("bytes reported:", b, " data.tables walked:", cnt$dt, "of", k, " env_size_strings calls:", cnt$strs, "\n")

t = numeric(reps)
for (i in seq_len(reps)) {
  gc()
  t[i] = system.time(size(home$raw, home))[["elapsed"]]
}
cat("env_snap_size elapsed s:", round(t, 3), " median:", round(stats::median(t), 3), "\n")
prof = file.path(out, paste0("rprof-k", k, ".out"))
utils::Rprof(prof, interval = 0.005)
size(home$raw, home)
utils::Rprof(NULL)
sp = utils::summaryRprof(prof)
print(utils::head(sp$by.self, 12))
print(utils::head(sp$by.total[grepl("env_|unique|unlist|mget|nchar|object.size", rownames(sp$by.total)), ], 15))
