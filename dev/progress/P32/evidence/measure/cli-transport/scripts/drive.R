# Drive gptr's real CLI route (cli-codex or cli-claude adapter, process_jsonl transport, the
# real stdio relay for codex) with an offline, timing-instrumented fake CLI in place of codex or
# claude. No model, no network. Session-side phases are marked with trace(); the fake logs its
# own phases. All timestamps are Sys.time() seconds, comparable across the processes.
# Args: <cli codex|claude> <variant trivial|raw10> <n_requests> <n_calls> <outdir> [rprof]
a = commandArgs(TRUE)
cli = a[[1]]; variant = a[[2]]; n_req = as.integer(a[[3]]); n_calls = as.integer(a[[4]])
out = a[[5]]; rprof = length(a) > 5 && identical(a[[6]], "rprof")
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/cli-transport"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
proj = file.path(out, "project")
dir.create(proj, showWarnings = FALSE)
setwd(proj)
Sys.setenv(R_USER_CONFIG_DIR = file.path(out, "private/config"),
           R_USER_DATA_DIR = file.path(out, "private/data"),
           R_USER_CACHE_DIR = file.path(out, "private/cache"),
           GPTR_PROJECT_ROOT = proj, FAKE_LOG = file.path(out, "fake.jsonl"),
           FAKE_CALLS = n_calls)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj,
        gptr.cli_turn_timeout = 600)
pkgload::load_all("/Users/wgu/Desktop/gptr", quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
data.table::setDTthreads(1)
ns = asNamespace("gptr")
now = function() as.numeric(Sys.time())
marks = new.env()
marks$rows = vector("list", 200000L)
marks$n = 0L
marks$req = 0L
MARK = function(fn, stage, info = NA_character_) {
  marks$n = marks$n + 1L
  marks$rows[[marks$n]] = list(req = marks$req, fn = fn, stage = stage, t = now(), info = info)
  invisible(NULL)
}
assign("MARK", MARK, envir = globalenv())
info_of = list(
  pcli_mcp = quote(as.character(msg[["method"]] %||% "")),
  mcp_dispatch_local = quote(as.character(message[["method"]] %||% "")),
  write_utf8 = quote(basename(path)),
  pcli_send = quote(as.character(obj[["type"]] %||% ""))
)
fns = c("run_start", "run_request", "run_build", "pcli_codex_build", "pcli_claude_build",
        "stream_process_start", "pcli_mcp", "mcp_dispatch_local", "mcp_serve_exec",
        "tool_call_hook", "mcp_serve_gate", "checkpoint_before", "mcp_serve_r",
        "checkpoint_after", "pcli_codex_end", "pcli_done", "run_response", "run_settle",
        "ckpt_on_agent_end", "env_view_snapshot", "ckpt_objects_budget", "ckpt_files_turn_scan",
        "pcli_codex_check", "pcli_control_hash", "write_utf8", "pcli_send", "mcp_served_tools",
        "session_append", "pcli_stop_child")
for (fn in fns) {
  inf = info_of[[fn]] %||% NA_character_
  if (identical(fn, "write_utf8")) {
    tr = quote(if (basename(path) %in% c("resp")) get("MARK", globalenv())("write_utf8", "enter", "resp"))
    ex = quote(if (basename(path) %in% c("resp")) get("MARK", globalenv())("write_utf8", "exit", "resp"))
  } else {
    tr = substitute(get("MARK", globalenv())(FN, "enter", INF), list(FN = fn, INF = inf))
    ex = substitute(get("MARK", globalenv())(FN, "exit"), list(FN = fn))
  }
  suppressMessages(trace(fn, where = ns, print = FALSE, tracer = tr, exit = ex))
}
# the fake CLI: Rscript running our instrumented script (probes are answered and cached)
fake = if (identical(cli, "codex")) file.path(W, "scripts/fake_codex.R") else
  file.path(W, "scripts/fake_claude.R")
paths = list()
paths[[cli]] = c(file.path(R.home("bin"), "Rscript"), "--vanilla", fake)
options(gptr.cli_path = paths)
spec = get("pcli_fake_provider", ns)(cli)
gptr_register(spec)
model = paste0(spec$id, "/", spec$models[[1L]]$id)
gptr_config(budget = list(tokens = 1e6, cost = 5, turns = 100), .scope = "session")
home = new.env(parent = globalenv())
pct = if (grepl("^(create|raw)[0-9]+$", variant)) as.integer(sub("^[a-z]+", "", variant)) else 10L
nr = as.integer(round(60664 * pct / 100))
make_raw = paste0("
  set.seed(1)
  nr = ", nr, "L
  ids = c(paste0('N_', 1:4), sprintf('ENSG%011d.%d', seq_len(nr - 4L), 1L))
  files = sprintf('f%04d.tsv', 1:1231)
  tables = lapply(files, function(f) data.table::data.table(gene_id = paste0(ids),
    gene_name = paste0('G', seq_along(ids)), gene_type = rep('protein_coding', nr),
    unstranded = as.numeric(rpois(nr, 50)), stranded_first = as.numeric(rpois(nr, 25)),
    stranded_second = as.numeric(rpois(nr, 25)), tpm_unstranded = runif(nr),
    fpkm_unstranded = runif(nr), fpkm_uq_unstranded = runif(nr)))
  raw = list(files = files, tables = stats::setNames(tables, files))
  rm(tables, ids, files, nr)")
reuse = paste0("if (!exists('raw', inherits = FALSE)) {", make_raw, "\n}\nlength(raw$tables)")
if (startsWith(variant, "raw")) eval(parse(text = make_raw), envir = home)
code_for = function(i) switch(variant, trivial = "1 + 1", reuse)
if (!identical(variant, "trivial")) {
  cat("raw size (object.size) MB:", if (exists("raw", home)) format(utils::object.size(home$raw), units = "MB") else "not yet", "\n")
}
ev = new.env()
ev$rows = list()
hook = function(event, ctx = NULL) {
  ev$rows[[length(ev$rows) + 1L]] = list(req = marks$req, type = event$type, t = now(),
                                          tool = event$tool_name %||% NA_character_,
                                          elapsed = event$elapsed %||% NA_real_,
                                          role = event$role %||% NA_character_)
  NULL
}
t_load = now()
s = peter("request 1", model = model, mode = "auto", tools = "minimal", envir = home, .run = FALSE)
for (e in c("agent_start", "message_end", "tool_execution_start", "tool_execution_end", "turn_end",
            "agent_end", "usage")) gptr_on(s, e, hook)
if (rprof) utils::Rprof(file.path(out, "Rprof.out"), interval = 0.005)
req_rows = list()
for (i in seq_len(n_req)) {
  marks$req = i
  t0 = now()
  Sys.setenv(FAKE_CODE = code_for(i))
  MARK("request", "enter")
  if (i == 1L) gptr_wait(s) else peter(s, prompt = paste("request", i))
  MARK("request", "exit")
  req_rows[[i]] = data.frame(req = i, wall_s = now() - t0, status = s$status)
}
if (rprof) utils::Rprof(NULL)
m = marks$rows[seq_len(marks$n)]
jsonlite::write_json(m, file.path(out, "marks.json"), auto_unbox = TRUE, digits = NA)
jsonlite::write_json(ev$rows, file.path(out, "events.json"), auto_unbox = TRUE, digits = NA)
print(do.call(rbind, req_rows))
cat("status:", s$status, "\n")
