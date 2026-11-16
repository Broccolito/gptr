# Phase-time served (MCP) or native `r` tool calls against a T03-like workspace.
# Env: N (tables), KIND (chr|num), VARIANTS (comma list), REPS, MODE (trace|rprof|plain),
#      ROUTE (mcp|native), TAG (output prefix), SRC (gptr source, default the checkout).
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
BENCH = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/bench/gptr-bench/biomedical/v0.5/reports/T03"
env = function(k, d) { v = Sys.getenv(k); if (nzchar(v)) v else d }
N = as.integer(env("N", "25"))
KIND = env("KIND", "chr")
VARIANTS = strsplit(env("VARIANTS", "a2,a3,b2,b3,c,d,e"), ",")[[1]]
REPS = as.integer(env("REPS", "3"))
MODE = env("MODE", "trace")
ROUTE = env("ROUTE", "mcp")
TAG = env("TAG", paste(ROUTE, KIND, N, MODE, sep = "-"))
SRC = env("SRC", "/Users/wgu/Desktop/gptr")
OUT = file.path(W, "out")
dir.create(OUT, showWarnings = FALSE)
work = file.path(W, "tmp", paste0("work-", TAG, "-", Sys.getpid()))
dir.create(file.path(work, "private"), recursive = TRUE)
setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "private/config"),
           R_USER_DATA_DIR = file.path(work, "private/data"),
           R_USER_CACHE_DIR = file.path(work, "private/cache"), GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
pkgload::load_all(SRC, quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])

# ---- T03-like workspace: fread output of a synthetic GDC STAR Counts file -------------------------
template = function(kind) {
  f = file.path(W, "data", paste0("star-", kind, ".tsv"))
  if (file.exists(f)) return(f)
  dir.create(dirname(f), showWarnings = FALSE)
  set.seed(1)
  g = 60660L
  ids = sprintf("ENSG%011d.%d", sort(sample.int(9e5, g)) + 1e4, sample(1:20, g, TRUE))
  nm = sprintf("GN%s%05d", sample(LETTERS, g, TRUE), c(seq_len(59400L), sample.int(59400L, g - 59400L)))
  ty = sample(sprintf("type_%02d_%s", 1:40, strrep("x", 1:40 %% 12)), g, TRUE)
  cnt = function() as.integer(rpois(g, 5) * rbinom(g, 1, 0.6) * sample(c(1, 10, 100), g, TRUE))
  u = cnt(); s1 = cnt(); s2 = cnt()
  tpm = round(u / sum(u) * 1e6, 4)
  head = data.frame(gene_id = c("N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous"),
                    gene_name = "", gene_type = "", unstranded = c(2397451L, 3190112L, 1840345L, 891234L),
                    stranded_first = 1L, stranded_second = 2L, tpm_unstranded = NA, fpkm_unstranded = NA,
                    fpkm_uq_unstranded = NA)
  body = data.frame(gene_id = ids, gene_name = nm, gene_type = ty, unstranded = u, stranded_first = s1,
                    stranded_second = s2, tpm_unstranded = tpm, fpkm_unstranded = round(tpm / 3.1, 4),
                    fpkm_uq_unstranded = round(tpm / 2.7, 4))
  d = rbind(head, body)
  if (kind == "num") {  # character columns replaced by random integers (no compact sequences)
    d$gene_id = sample.int(1e9, nrow(d)); d$gene_name = sample.int(1e9, nrow(d))
    d$gene_type = sample.int(40L, nrow(d), TRUE)
  }
  writeLines("# gene-model: GENCODE v36", f)
  data.table::fwrite(d, f, sep = "\t", append = TRUE, col.names = TRUE, na = "")
  f
}
tf = template(KIND)
files = sprintf("TCGA-BRCA/%08d-%04d.rna_seq.augmented_star_gene_counts.tsv", seq_len(N) * 7919L, seq_len(N))
t_build = clock()
# every table is its own fread() result: fresh STRSXPs whose CHARSXPs live in R's global cache
rd = function() data.table::fread(file = tf, skip = "gene_id", header = TRUE, showProgress = FALSE)
SHARENUM = env("SHARENUM", "0") == "1"
shared = if (SHARENUM) as.list(rd())
tables = lapply(seq_len(N), function(i) {
  x = rd()
  if (!SHARENUM) return(x)
  # memory saver for large N: numeric columns are one shared vector set (the size walk meets them
  # as already seen, O(1) either way); character columns stay fresh per table, as fread gives them
  l = unclass(x)
  num = which(!vapply(l, is.character, NA))
  l[num] = shared[num]
  attr(l, ".internal.selfref") = NULL
  data.table::setDT(l)
  l
})
home = new.env(parent = globalenv())
home$raw = list(files = files, tables = setNames(tables, files))
rm(tables)
t_build = clock() - t_build
invisible(gc())
raw_size = as.numeric(utils::object.size(home$raw))
cat(sprintf("built raw: N=%d kind=%s object.size=%.2f GB in %.1f s\n", N, KIND, raw_size / 1e9, t_build))

# ---- code variants --------------------------------------------------------------------------------
calls = jsonlite::read_json(file.path(BENCH, "mcp-replay-analysis/evidence/calls.json"))
fixn = function(code) gsub("1231L", paste0(N, "L"), code, fixed = TRUE)
strip = function(code) {  # drop the dead `if (!exists("raw", ...)) { ... }` fallback block
  l = strsplit(code, "\n", fixed = TRUE)[[1]]
  a = grep('^if \\(!exists\\("raw"', l)
  b = a + which(l[(a + 1):length(l)] == "}")[1]
  paste(l[-(a:b)], collapse = "\n")
}
code2 = fixn(calls$calls[[2]]$input$code)
code3 = fixn(calls$calls[[3]]$input$code)
variant_code = function(v, rep) switch(v,
  a2 = code2, a3 = code3, b2 = strip(code2), b3 = strip(code3),
  c = "sum(vapply(raw$tables, nrow, 1L))",
  d = sprintf("new_obj_%d = length(raw$tables)", rep),
  e = "raw$x = 1",
  f = 'if (!exists("raw", inherits = FALSE)) raw = list(); length(raw$tables)',
  w = "invisible(0)",
  stop("unknown variant ", v))

# ---- markers --------------------------------------------------------------------------------------
P = new.env()
P$k = 0L; P$fn = P$stage = P$caller = P$req = character(1e5); P$t = numeric(1e5)
P$cur = ""
P$written = 0L
caller_of = function(fn) {
  h = vapply(sys.calls(), function(cl) paste(deparse(cl[[1L]], nlines = 1L), collapse = ""), "")
  i = max(which(h == fn | endsWith(h, paste0(":", fn))), 0L)
  if (i <= 1L) return("")
  up = h[seq_len(i - 1L)]
  up = up[!grepl("^(function|eval|tryCatch|tryCatchList|tryCatchOne|doTryCatch|withCallingHandlers|\\.doTrace|checked|FUN|lapply|do.call|ctx_with_source|force)", up)]
  paste(rev(utils::tail(up, 4L)), collapse = "<")
}
mark = function(fn, stage) {
  k = P$k + 1L
  P$k = k
  P$fn[k] = fn; P$stage[k] = stage; P$t[k] = clock(); P$req[k] = P$cur
  P$caller[k] = if (stage == "enter" && fn %in% c("env_snap_size", "call_risk", "risk_classify_r",
                                                   "risk_scan", "env_snapshot", "risk_binding_info")) caller_of(fn) else ""
}
assign("mark", mark, envir = globalenv())
fns = c("mcp_serve_call", "mcp_serve_exec", "schema_validate", "mcp_serve_envir", "risk_classify_r",
        "risk_scan", "risk_secret_scan", "tool_call_hook", "mcp_serve_gate", "perm_check",
        "perm_decide", "call_risk", "perm_policies", "ext_policy_decide", "eval_guard",
        "perm_grant_control", "risk_binding_info", "env_snap_size", "checkpoint_before",
        "ckpt_objects_before", "ckpt_files_before", "env_snapshot", "ckpt_predict", "checkpoint_after",
        "ckpt_objects_after", "ckpt_files_after", "mcp_serve_r", "dispatch_steps", "tool_validate",
        "tool_execute_frame", "tool_result_hooks", "fingerprint")
fns = fns[vapply(fns, exists, NA, envir = ns, inherits = FALSE)]
if (MODE == "trace") {
  for (fn in fns) {
    suppressMessages(trace(fn, where = ns, print = FALSE,
      tracer = substitute(get("mark", globalenv())(FN, "enter"), list(FN = fn)),
      exit = substitute(get("mark", globalenv())(FN, "exit"), list(FN = fn))))
  }
}

# ---- runs -----------------------------------------------------------------------------------------
S = new.env()
S$rows = list(); S$start = NA; S$code = "invisible(0)"; S$id = 0L; S$prof = ""
gptr_register(gptr_hook("tool_execution_start", function(event, ctx) {
  if (nzchar(S$prof)) utils::Rprof(S$prof, interval = 0.005, event = Sys.getenv("RPROF_EVENT", "elapsed"), gc.profiling = TRUE)
  S$start = clock()
  mark("TOOL", "enter")
  NULL
}))
gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
  t = clock()
  if (nzchar(S$prof)) utils::Rprof(NULL)
  mark("TOOL", "exit")
  S$outer = t - S$start
  S$internal = event$elapsed
  S$is_error = isTRUE(event$is_error)
  S$refused = paste(event$refused %||% "", collapse = " ")
  NULL
}))
if (ROUTE == "mcp") {
  gptr_register(gptr_hook("before_request", function(event, ctx) {
    if (!isTRUE(S$pending)) return(NULL)
    S$pending = FALSE
    S$id = S$id + 1L
    res = get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = S$id, method = "tools/call",
      params = list(name = "r", arguments = list(code = S$code))), ctx$session)
    S$rpc_error = !is.null(res$error) || isTRUE(res$result$isError)
    S$text = substr(paste(vapply(res$result$content %||% list(), function(b) b$text %||% "", ""),
                          collapse = " "), 1, 300)
    NULL
  }))
  script = list("Recorded tool call completed offline.")
} else {
  script = function(req) {
    if (length(req$last_results)) return("Recorded tool call completed offline.")
    S$id = S$id + 1L
    list(tool = "r", input = list(code = S$code), id = paste0("call_", S$id))
  }
}
fake = gptr_fake_provider(script, name = "gate-measure")
s = peter("start", model = fake, mode = "auto", tools = "minimal", envir = home, .run = FALSE)
one = function(variant, rep) {
  S$code = if (variant == "warm") "invisible(0)" else variant_code(variant, rep)
  S$pending = TRUE; S$outer = NA; S$internal = NA; S$is_error = NA; S$refused = ""
  P$cur = paste(variant, rep, sep = "#")
  S$prof = if (MODE == "rprof" && variant != "warm") file.path(OUT, sprintf("rprof-%s-%s-%d.out", TAG, variant, rep)) else ""
  invisible(gc())
  t0 = clock()
  peter(s, prompt = paste("request", variant, rep))
  wall = clock() - t0
  row = data.frame(tag = TAG, route = ROUTE, kind = KIND, n = N, mode = MODE, variant = variant,
                   rep = rep, wall_s = wall, outer_s = S$outer, internal_s = S$internal,
                   gap_s = S$outer - S$internal, is_error = S$is_error, refused = S$refused,
                   raw_object_size_gb = raw_size / 1e9)
  S$rows[[length(S$rows) + 1L]] = row
  fr = file.path(OUT, paste0("runs-", TAG, ".csv"))
  write.table(row, fr, sep = ",", row.names = FALSE, append = file.exists(fr) && length(S$rows) > 1L,
              col.names = length(S$rows) == 1L)
  k = P$k
  sl = (P$written + 1L):k
  fm = file.path(OUT, paste0("marks-", TAG, ".csv"))
  write.table(data.frame(req = P$req[sl], fn = P$fn[sl], stage = P$stage[sl], t = P$t[sl], caller = P$caller[sl]),
              fm, sep = ",", row.names = FALSE, append = P$written > 0L, col.names = P$written == 0L)
  P$written = k
  print(row[, c("variant", "rep", "wall_s", "outer_s", "internal_s", "gap_s", "is_error")])
  if (!is.null(S$text) && isTRUE(S$is_error)) cat("  text:", S$text, "\n")
  if (nzchar(S$refused)) cat("  refused:", S$refused, "\n")
}
one("warm", 1L)
one("warm", 2L)
for (v in VARIANTS) for (r in seq_len(REPS)) one(v, r)

setwd(W)
unlink(work, recursive = TRUE)
