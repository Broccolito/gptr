# Shared setup for the counterfactual drivers: env, gptr copy, T03-like table builder, codes.
# Requires N (tables) and TAG before sourcing.
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual"
GM = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
BENCH = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/bench/gptr-bench/biomedical/v0.5/reports/T03"
envv = function(k, d) { v = Sys.getenv(k); if (nzchar(v)) v else d }
OUT = file.path(W, "out")
dir.create(OUT, showWarnings = FALSE)
work = file.path(W, "tmp", paste0("work-", TAG, "-", Sys.getpid()))
proj = file.path(work, "project")
dir.create(file.path(work, "private"), recursive = TRUE)
dir.create(proj, recursive = TRUE)
setwd(proj)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "private/config"),
           R_USER_DATA_DIR = file.path(work, "private/data"),
           R_USER_CACHE_DIR = file.path(work, "private/cache"), GPTR_PROJECT_ROOT = proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
options(width = 200)
clock = function() as.numeric(proc.time()[["elapsed"]])
`%||%` = function(a, b) if (is.null(a)) b else a

# ---- variants: cf = counterfactual hacks, lm = loop-measure's per-turn patches --------------------
LOOP = c("json", "est", "settings", "model", "shape")
VARS = list(
  base = list(cf = character(), lm = character()),
  reuse = list(cf = "reuse", lm = character()),
  cache = list(cf = "size_cache", lm = character()),
  bound = list(cf = "size_bound", lm = character()),
  skip = list(cf = "size_skip", lm = character()),
  share = list(cf = "share", lm = character()),
  loop = list(cf = "reactor", lm = LOOP),
  rc = list(cf = c("reuse", "size_cache"), lm = character()),
  all = list(cf = c("reuse", "size_cache", "share", "reactor"), lm = LOOP),
  all_bound = list(cf = c("reuse", "size_bound", "share", "reactor"), lm = LOOP),
  files = list(cf = character(), lm = character(), ck = "files"),
  off = list(cf = character(), lm = character(), ck = "off"),
  all_files = list(cf = c("reuse", "size_cache", "share", "reactor"), lm = LOOP, ck = "files"),
  all_off = list(cf = c("reuse", "size_cache", "share", "reactor"), lm = LOOP, ck = "off"))
set_variant = function(v) {
  x = VARS[[v]]
  ck = x$ck %||% "on"
  options(cf.patch = x$cf, lm.patch = x$lm, gptr.checkpoint = ck)
  invisible(v)
}

# ---- T03-like tables: the gate-measure template STAR file, fread once; each table gets fresh
# character STRSXPs (copy(); CHARSXPs shared through R's string cache as fread gives them) and
# one shared set of numeric columns (memory saver; the size walk meets them as seen, O(1))
TF = file.path(GM, "data", "star-chr.tsv")
T0 = data.table::fread(file = TF, skip = "gene_id", header = TRUE, showProgress = FALSE)
NUMS = as.list(T0)[!vapply(T0, is.character, NA)]
cf_table = function(filename = NULL) {
  l = as.list(T0)
  chr = vapply(l, is.character, NA)
  l[chr] = lapply(l[chr], data.table::copy)
  l[!chr] = NUMS
  data.table::setDT(l)
  l
}
assign(".cf_table", cf_table, envir = globalenv())
files = sprintf("TCGA-BRCA/%08d-%04d.rna_seq.augmented_star_gene_counts.tsv", seq_len(N) * 7919L,
                seq_len(N))
# project root as the benchmark lays it out: the N inputs (symlinks) and input-files.txt
dir.create(file.path(proj, "TCGA-BRCA"))
invisible(file.symlink(TF, file.path(proj, files)))
writeLines(files, file.path(proj, "input-files.txt"))

calls = jsonlite::read_json(file.path(BENCH, "mcp-replay-analysis/evidence/calls.json"))
fixn = function(code) gsub("1231L", paste0(N, "L"), code, fixed = TRUE)
fread_call = 'data.table::fread(file = filename, skip = "gene_id", header = TRUE, showProgress = FALSE)'
code1 = sub(fread_call, ".cf_table(filename)", fixn(calls$calls[[1]]$input$code), fixed = TRUE)
code2 = fixn(calls$calls[[2]]$input$code)
code3 = fixn(calls$calls[[3]]$input$code)
stopifnot(grepl(".cf_table(filename)", code1, fixed = TRUE))
rss_gb = function() {
  as.numeric(system2("ps", c("-o", "rss=", "-p", Sys.getpid()), stdout = TRUE)) / 1048576
}
