# Per-call check costs of gptr's static risk analysis against a T03-like workspace.
# Usage: Rscript --vanilla check-costs.R <workdir> <n_tables> <rows> <reps> [prof]
# Offline: no provider, no model, no network. Loads a copy of the pinned source.
a = commandArgs(TRUE)
W = normalizePath(a[1])
N = as.integer(a[2])
R = as.integer(a[3])
reps = as.integer(a[4])
prof = length(a) > 4 && a[5] == "prof"
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
out_csv = file.path(W, "results", paste0("check-costs-", tag, ".csv"))
dir.create(dirname(out_csv), showWarnings = FALSE)

calls = jsonlite::read_json(file.path(W, "calls.json"))
code2 = calls$calls[[2]]$input$code
code3 = calls$calls[[3]]$input$code
strip = function(code) sub("(?s)if \\(!exists\\(\"raw\", inherits = FALSE\\)\\) \\{.*?\\n\\}\\n", "", code,
                           perl = TRUE)
code2_nobranch = strip(code2)
code3_nobranch = strip(code3)
stopifnot(!grepl("fread", code2_nobranch), !grepl("fread", code3_nobranch))

# ---- a T03-like workspace: raw = list(files, tables = N data.tables of R x 9) -------------
t0 = clock()
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
home$reference_gene_ids = home$raw$tables[[1L]]$gene_id
home$gene_rows = startsWith(home$reference_gene_ids, "ENSG")
home$input_audit = data.frame(n_files = N, rows_per_file = R, total_gene_counts = 1, zero_gene_values = 1)
home$sample_summary = data.table::data.table(file = files, total_counts = as.numeric(seq_len(N)))
build_s = clock() - t0
cat(sprintf("[%s] built workspace in %.2f s; object.size(raw) = %.2f GB\n", tag, build_s,
            as.numeric(utils::object.size(home$raw)) / 2^30))

# ---- timing helpers -------------------------------------------------------------------------
rows = list()
timeit = function(what, f, n = reps) {
  ts = numeric(n)
  for (k in seq_len(n)) {
    invisible(gc(FALSE))
    s = clock()
    f()
    ts[k] = clock() - s
  }
  rows[[length(rows) + 1L]] <<- data.frame(config = tag, n_tables = N, rows = R, what = what,
                                           reps = n, median_s = stats::median(ts), min_s = min(ts),
                                           max_s = max(ts), all_s = paste(round(ts, 3), collapse = ";"))
  cat(sprintf("[%s] %-34s median %8.3f s  (%s)\n", tag, what, stats::median(ts),
              paste(round(ts, 3), collapse = ", ")))
  utils::write.csv(do.call(rbind, rows), out_csv, row.names = FALSE)
}
classify = function(code, envir) ns$risk_classify(code, envir = envir, root = proj, kind = "r")

# What the classifier reports, and how many env_snap_size() calls one classification makes
cnt = new.env()
cnt$n = 0L
cnt$t = numeric()
trace("env_snap_size", where = ns, print = FALSE,
      tracer = quote(assign("t_enter", as.numeric(proc.time()[["elapsed"]]), envir = get("cnt", .GlobalEnv))),
      exit = quote({
        cc = get("cnt", .GlobalEnv)
        cc$n = cc$n + 1L
        cc$t = c(cc$t, as.numeric(proc.time()[["elapsed"]]) - cc$t_enter)
      }))
r2 = classify(code2, home)
n2 = cnt$n
t2 = cnt$t
cnt$n = 0L
cnt$t = numeric()
r3 = classify(code3, home)
n3 = cnt$n
t3 = cnt$t
untrace("env_snap_size", where = ns)
cat(sprintf("[%s] request 2: level %d (%s); env_snap_size calls %d (%s s); sizes: %s\n", tag, r2$level,
            r2$label, n2, paste(round(t2, 3), collapse = ", "),
            paste(names(r2$sizes), signif(r2$sizes, 4), sep = "=", collapse = ", ")))
cat(sprintf("[%s] request 3: level %d (%s); env_snap_size calls %d (%s s); sizes: %s\n", tag, r3$level,
            r3$label, n3, paste(round(t3, 3), collapse = ", "),
            paste(names(r3$sizes), signif(r3$sizes, 4), sep = "=", collapse = ", ")))
fl = r2$flagged
print(fl[fl$level >= 1L, c("call", "level", "category")], row.names = FALSE)
r2n = classify(code2_nobranch, home)
cat(sprintf("[%s] request 2 without the dead branch: level %d (%s), categories %s\n", tag, r2n$level,
            r2n$label, paste(r2n$categories, collapse = ",")))

# ---- constant-cost parts (code text only) ----------------------------------------------------
timeit("classify_r2_no_envir", function() classify(code2, NULL))
timeit("classify_r3_no_envir", function() classify(code3, NULL))
timeit("secret_scan_r2", function() ns$risk_secret_scan(code2))
timeit("code_targets_r2 (ckpt_predict)", function() ns$code_targets(code2))
timeit("eval_parse_r2", function() ns$eval_parse(code2))
timeit("eval_guard_r2", function() ns$eval_guard(ns$eval_parse(code2), home))
# ---- content-dependent parts ----------------------------------------------------------------
timeit("classify_r2_envir", function() classify(code2, home))
timeit("classify_r2_nobranch_envir", function() classify(code2_nobranch, home))
timeit("classify_r3_envir", function() classify(code3, home))
timeit("classify_r3_nobranch_envir", function() classify(code3_nobranch, home))
timeit("env_snap_size_raw", function() ns$env_snap_size(home$raw, home))
timeit("fingerprint_raw (cache key)", function() ns$fingerprint(home$raw))
timeit("obj_address+class+length_raw", function() {
  x = home$raw
  list(rlang::obj_address(x), class(x)[1L], length(x))
})
timeit("object.size_raw (shallow-ish)", function() utils::object.size(home$raw), n = 1L)
snap = NULL
timeit("env_snapshot_cold", function() snap <<- ns$env_snapshot(home, NULL))
timeit("env_snapshot_warm (cache hit)", function() ns$env_snapshot(home, snap))

if (prof) {
  pf = file.path(W, "results", paste0("rprof-classify-r2-", tag, ".out"))
  utils::Rprof(pf, interval = 0.005)
  invisible(classify(code2, home))
  utils::Rprof(NULL)
  sp = utils::summaryRprof(pf)
  cat(sprintf("[%s] Rprof classify_r2_envir: sampling time %.2f s\n", tag, sp$sampling.time))
  cat("-- by.self (top 15)\n")
  print(utils::head(sp$by.self, 15))
  cat("-- by.total (top 30)\n")
  print(utils::head(sp$by.total, 30))
}
m = gc()
cat(sprintf("[%s] gc max used: %.2f GB (Ncells+Vcells)\n", tag, sum(m[, ncol(m)]) / 1024))
cat(sprintf("[%s] done\n", tag))
