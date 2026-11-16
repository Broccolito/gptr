# How many of the N data.tables does env_snap_size() walk before sampling? (small rows, same parts)
a = commandArgs(TRUE); W = normalizePath(a[1]); N = as.integer(a[2]); R = as.integer(a[3])
proj = file.path(W, "proj")
Sys.setenv(R_USER_CONFIG_DIR = file.path(W, "private/config"), R_USER_DATA_DIR = file.path(W, "private/data"),
           R_USER_CACHE_DIR = file.path(W, "private/cache"), GPTR_PROJECT_ROOT = proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
pkgload::load_all(file.path(W, "gptr-src"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
ids = sprintf("ENSG%011d", seq_len(R))
tabs = lapply(seq_len(N), function(i) data.table::data.table(gene_id = ids[seq_len(R)], gene_name = ids[seq_len(R)],
  gene_type = ids[seq_len(R)], a = seq_len(R) + i, b = seq_len(R) + 2L * i, c = seq_len(R) + 3L * i,
  d = (seq_len(R) + i) / 3, e = (seq_len(R) + i) / 7, f = (seq_len(R) + i) / 9))
raw = list(files = as.character(seq_len(N)), tables = tabs)
cnt = new.env(); cnt$dt = 0L; cnt$chr = 0L
trace("env_size_walk", where = ns, print = FALSE, tracer = quote({
  cc = get("cnt", .GlobalEnv)
  if (inherits(x, "data.table")) cc$dt = cc$dt + 1L
  if (is.character(x) && length(x) > 1000L) cc$chr = cc$chr + 1L
}))
b = ns$env_snap_size(raw, globalenv())
untrace("env_size_walk", where = ns)
cat(sprintf("N=%d R=%d: data.tables walked %d of %d; long character vectors walked %d; bytes %.4g\n",
            N, R, cnt$dt, N, cnt$chr, b))
