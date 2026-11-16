# Building blocks of the objects checkpointer on a T03-like list of data.tables, measured directly.
# Usage: Rscript --vanilla unit_size.R <n_tables> <outdir> [serialize=0|1] [prof=0|1]
a = commandArgs(TRUE)
n = as.integer(a[1]); outdir = a[2]
do_ser = length(a) > 2 && a[3] == "serialize=1"
do_prof = length(a) > 3 && a[4] == "prof=1"
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/ckpt-measure"
work = file.path(outdir, paste0("unit_n", n)); unlink(work, recursive = TRUE); dir.create(work, recursive = TRUE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "config"), R_USER_DATA_DIR = file.path(work, "data"),
           R_USER_CACHE_DIR = file.path(work, "cache"), GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
suppressMessages(pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE,
                                   attach_testthat = FALSE))
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
med3 = function(f) { t = numeric(3); for (k in 1:3) { gc(); t0 = clock(); v = f(); t[k] = clock() - t0 }; list(median = median(t), all = t, value = v) }
out = list(n = n)

home = new.env(parent = globalenv())
t0 = clock()
ids = c(paste0("N_", c("unmapped", "multimapping", "noFeature", "ambiguous")), sprintf("ENSG%011d.%d", seq_len(60660L), 1L))
gname = c(rep("", 4L), sprintf("GENE%05d", (seq_len(60660L) %% 59000L) + 1L))
gtype = c(rep("", 4L), sprintf("type_%02d", seq_len(60660L) %% 40L))
files = sprintf("file_%04d.tsv", seq_len(n))
tables = lapply(seq_len(n), function(i) data.table::data.table(gene_id = ids[seq_along(ids)], gene_name = gname[seq_along(gname)], gene_type = gtype[seq_along(gtype)], unstranded = (seq_len(60664L) * (i + 3L)) %% 9973L, stranded_first = (seq_len(60664L) * (i + 5L)) %% 9967L, stranded_second = (seq_len(60664L) * (i + 7L)) %% 9949L, tpm_unstranded = ((seq_len(60664L) * (i + 3L)) %% 9973L) / 7, fpkm_unstranded = ((seq_len(60664L) * (i + 5L)) %% 9967L) / 11, fpkm_uq_unstranded = ((seq_len(60664L) * (i + 7L)) %% 9949L) / 13))
assign("raw", list(files = files, tables = setNames(tables, files)), envir = home)
rm(tables)
out$build_s = clock() - t0
raw_size = function() get("env_snap_size", ns)(get("raw", envir = home), home)
r = med3(raw_size); out$env_snap_size_s = r$median; out$env_snap_size_all = r$all; out$env_snap_size_bytes = r$value
out$object_size_bytes = as.numeric(utils::object.size(get("raw", envir = home)))
out$object_size_s = med3(function() utils::object.size(get("raw", envir = home)))$median
out$fingerprint_s = med3(function() get("fingerprint", ns)(get("raw", envir = home)))$median
# snapshot cold (no previous: size computed) and warm (previous reused)
cold = med3(function() get("env_snapshot", ns)(home))
out$env_snapshot_cold_s = cold$median
prev = cold$value
out$env_snapshot_warm_s = med3(function() get("env_snapshot", ns)(home, prev))$median
# one table, and the string/walk split for one table
tab1 = get("raw", envir = home)$tables[[1]]
out$one_table_size_s = med3(function() get("env_snap_size", ns)(tab1))$median
out$one_table_bytes = get("env_snap_size", ns)(tab1)
# the shared walk (ckpt_unshared_bytes: image vs current, as after a reassign)
img = get("raw", envir = home)
cur = c(img, list(note = "x"))
r = med3(function() get("env_snap_size", ns)(img, home, cur))
out$unshared_s = r$median; out$unshared_bytes = r$value
rm(img, cur)
# string-store cost: walk with character columns replaced by NULL (structure only)
if (do_prof) {
  pf = file.path(outdir, paste0("unit_n", n, "_env_snap_size.Rprof"))
  utils::Rprof(pf, interval = 0.005)
  for (k in 1:3) raw_size()
  utils::Rprof(NULL)
  sp = summaryRprof(pf)
  out$prof_self = head(sp$by.self, 15)
  out$prof_total = head(sp$by.total, 25)
  print(head(sp$by.self, 15)); print(head(sp$by.total, 25))
}
if (do_ser) {
  f = file.path(work, "image.rdsx")
  t0 = clock(); b = get("serialize_leaf", ns)(get("raw", envir = home), xdr = FALSE); out$serialize_s = clock() - t0
  out$serialize_bytes = length(b)
  rm(b); gc()
  r = med3(function() { get("ckpt_write_image", ns)(f, home, "raw"); file.size(f) })
  out$write_image_s = r$median; out$write_image_all = r$all; out$image_file_bytes = r$value
  unlink(f)
}
out$rss_gb = as.numeric(ps::ps_memory_info()[["rss"]]) / 2^30
out$gc = gc()[, 6]
str(out[setdiff(names(out), c("prof_self", "prof_total"))])
jsonlite::write_json(out, file.path(outdir, paste0("unit_n", n, ".json")), auto_unbox = TRUE, digits = 8, pretty = TRUE)
unlink(work, recursive = TRUE)
