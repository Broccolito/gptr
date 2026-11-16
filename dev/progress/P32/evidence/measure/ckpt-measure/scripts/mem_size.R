# Transient memory of env_snap_size() and of a disk image on a T03-like list of data.tables.
# Usage: Rscript --vanilla mem_size.R <n_tables> <outdir> [image=0|1]
a = commandArgs(TRUE)
n = as.integer(a[1]); outdir = a[2]; do_img = length(a) > 2 && a[3] == "image=1"
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/ckpt-measure"
work = file.path(outdir, paste0("mem_n", n)); unlink(work, recursive = TRUE); dir.create(work, recursive = TRUE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "config"), R_USER_DATA_DIR = file.path(work, "data"),
           R_USER_CACHE_DIR = file.path(work, "cache"), GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
suppressMessages(pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE,
                                   attach_testthat = FALSE))
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
ids = c(paste0("N_", c("unmapped", "multimapping", "noFeature", "ambiguous")), sprintf("ENSG%011d.%d", seq_len(60660L), 1L))
gname = c(rep("", 4L), sprintf("GENE%05d", (seq_len(60660L) %% 59000L) + 1L))
gtype = c(rep("", 4L), sprintf("type_%02d", seq_len(60660L) %% 40L))
files = sprintf("file_%04d.tsv", seq_len(n))
home = new.env(parent = globalenv())
tables = lapply(seq_len(n), function(i) data.table::data.table(gene_id = ids[seq_along(ids)], gene_name = gname[seq_along(gname)], gene_type = gtype[seq_along(gtype)], unstranded = (seq_len(60664L) * (i + 3L)) %% 9973L, stranded_first = (seq_len(60664L) * (i + 5L)) %% 9967L, stranded_second = (seq_len(60664L) * (i + 7L)) %% 9949L, tpm_unstranded = ((seq_len(60664L) * (i + 3L)) %% 9973L) / 7, fpkm_unstranded = ((seq_len(60664L) * (i + 5L)) %% 9967L) / 11, fpkm_uq_unstranded = ((seq_len(60664L) * (i + 7L)) %% 9949L) / 13))
assign("raw", list(files = files, tables = setNames(tables, files)), envir = home)
rm(tables, ids, gname, gtype)
peak = function(f) {
  invisible(gc(reset = TRUE)); base = sum(gc()[, 2]); rss0 = as.numeric(ps::ps_memory_info()[["rss"]])
  t0 = clock(); v = f(); dt = clock() - t0
  g = gc(); list(s = dt, base_mb = base, peak_mb = sum(g[, 6 + 1]), extra_peak_mb = sum(g[, 7]) - base,
                 rss_before_gb = rss0 / 2^30, rss_after_gb = as.numeric(ps::ps_memory_info()[["rss"]]) / 2^30)
}
out = list(n = n)
out$env_snap_size = peak(function() get("env_snap_size", ns)(get("raw", envir = home), home))
out$env_snap_size2 = peak(function() get("env_snap_size", ns)(get("raw", envir = home), home))
if (do_img) {
  f = file.path(work, "image.rdsx")
  out$write_image = peak(function() get("ckpt_write_image", ns)(f, home, "raw"))
  out$write_image$file_bytes = file.size(f)
  unlink(f)
}
str(out)
jsonlite::write_json(out, file.path(outdir, paste0("mem_n", n, ".json")), auto_unbox = TRUE, digits = 8, pretty = TRUE)
unlink(work, recursive = TRUE)
