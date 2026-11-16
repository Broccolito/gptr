# Count and time the checks of one served `r` call (mcp_dispatch_local from a before_request hook,
# as the benchmark's profile-mcp.R does), against a T03-shaped workspace of reduced size.
# Usage: Rscript --vanilla replay-count.R <workdir> <n_tables> <rows>
a = commandArgs(TRUE)
W = normalizePath(a[1])
N = as.integer(a[2])
R = as.integer(a[3])
work = file.path(W, "replay")
dir.create(work, showWarnings = FALSE)
setwd(work)
Sys.setenv(R_USER_CONFIG_DIR = file.path(W, "private/config"),
           R_USER_DATA_DIR = file.path(W, "private/data"),
           R_USER_CACHE_DIR = file.path(W, "private/cache"),
           GPTR_PROJECT_ROOT = work)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
pkgload::load_all(file.path(W, "gptr-src"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])
calls = jsonlite::read_json(file.path(W, "calls.json"))
fit = function(code) {
  code = gsub("1231L", paste0(N, "L"), code, fixed = TRUE)
  code = gsub("60664L", paste0(R, "L"), code, fixed = TRUE)
  gsub("60660L", paste0(R - 4L, "L"), code, fixed = TRUE)
}
codes = list(fit(calls$calls[[2]]$input$code), fit(calls$calls[[3]]$input$code))

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
home$input_audit = data.frame(n_files = N, total_gene_counts = 1, zero_gene_values = 1)

st = new.env()
st$req = 0L
st$rows = list()
mark = function(fn, stage) {
  st$rows[[length(st$rows) + 1L]] = data.frame(request = st$req, fn = fn, stage = stage, t = clock())
}
traced = c("risk_classify", "env_snap_size", "perm_decide", "mcp_serve_gate", "tool_call_hook",
           "checkpoint_before", "checkpoint_after", "env_snapshot", "mcp_serve_r", "eval_guard",
           "risk_secret_scan", "code_targets")
for (fn in traced) {
  trace(fn, where = ns, print = FALSE,
        tracer = substitute(get("mark", .GlobalEnv)(FN, "enter"), list(FN = fn)),
        exit = substitute(get("mark", .GlobalEnv)(FN, "exit"), list(FN = fn)))
}
gptr_register(gptr_hook("before_request", function(event, ctx) {
  st$req = st$req + 1L
  params = list(name = "r", arguments = list(code = codes[[st$req]]))
  params[["_meta"]] = list("io.modelcontextprotocol/protocolVersion" = "2026-07-28",
                           "io.modelcontextprotocol/clientCapabilities" = structure(list(), names = character()),
                           "io.modelcontextprotocol/clientInfo" = list(name = "offline-count", version = "1"))
  mark("served_call", "enter")
  res = get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = 2L, method = "tools/call",
                                           params = params), ctx$session)
  mark("served_call", "exit")
  st$err = c(st$err, isTRUE(res$result$isError) || !is.null(res$error))
  NULL
}))
fake = gptr_fake_provider(list("Recorded tool call completed offline."), name = "offline-count")
s = peter("Request 2 (offline replay).", model = fake, mode = "auto", tools = "minimal", envir = home)
peter(s, prompt = "Request 3 (offline replay).")
for (fn in traced) untrace(fn, where = ns)

ev = do.call(rbind, st$rows)
# pair enter/exit per function (calls nest only for distinct functions here, except env_snapshot)
out = list()
for (rq in unique(ev$request)) {
  e = ev[ev$request == rq, ]
  for (fn in unique(e$fn)) {
    en = e$t[e$fn == fn & e$stage == "enter"]
    ex = e$t[e$fn == fn & e$stage == "exit"]
    k = min(length(en), length(ex))
    out[[length(out) + 1L]] = data.frame(request = rq + 1L, fn = fn, calls = length(en),
                                         total_s = round(sum(ex[seq_len(k)] - en[seq_len(k)]), 3),
                                         each_s = paste(round(ex[seq_len(k)] - en[seq_len(k)], 3), collapse = ";"))
  }
}
tab = do.call(rbind, out)
print(tab, row.names = FALSE)
cat("tool errors:", paste(st$err, collapse = ","), "\n")
dir.create(file.path(W, "results"), showWarnings = FALSE)
utils::write.csv(tab, file.path(W, "results", sprintf("replay-count-N%d_R%d.csv", N, R)), row.names = FALSE)
