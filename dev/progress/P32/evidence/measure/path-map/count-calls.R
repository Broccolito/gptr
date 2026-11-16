# Call-count map of one `r` tool call through gptr, on the served MCP route and the native loop.
# Usage: Rscript --vanilla count-calls.R <route: mcp|native> <n_files> <n_rows> <outdir>
# Small synthetic STAR-like inputs; counts and attribution, not representative timings.
a = commandArgs(TRUE)
route = a[1]; n_files = as.integer(a[2]); n_rows = as.integer(a[3]); out = a[4]
notrace = length(a) > 4 && a[5] == "notrace"
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/path-map"
src = file.path(W, "src", "gptr")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out = normalizePath(out)
proj = file.path(out, "project"); dir.create(proj, showWarnings = FALSE)
priv = file.path(out, "private"); dir.create(priv, showWarnings = FALSE)
data_dir = file.path(out, "data"); dir.create(data_dir, showWarnings = FALSE)
data.table::setDTthreads(1)

# ---- synthetic inputs: symlinked into the project root as the benchmark's replay.R does -------
set.seed(1)
ids = c("N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous",
        sprintf("ENSG%011d.%d", seq_len(n_rows - 4L), 1L))
gnames = c(rep(NA_character_, 4), sprintf("GENE%d", seq_len(n_rows - 4L)))
gtypes = c(rep(NA_character_, 4), sample(c("protein_coding", "lncRNA", "miRNA"), n_rows - 4L, TRUE))
files = sprintf("%04d-synthetic.tsv", seq_len(n_files))
for (f in files) {
  dt = data.table::data.table(gene_id = ids, gene_name = gnames, gene_type = gtypes,
    unstranded = rpois(n_rows, 5), stranded_first = rpois(n_rows, 2), stranded_second = rpois(n_rows, 2),
    tpm_unstranded = runif(n_rows), fpkm_unstranded = runif(n_rows), fpkm_uq_unstranded = runif(n_rows))
  p = file.path(data_dir, f)
  writeLines("# gene-model: synthetic", p)
  data.table::fwrite(dt, p, sep = "\t", append = TRUE, col.names = TRUE)
  if (!file.exists(file.path(proj, f))) file.symlink(p, file.path(proj, f))
}
writeLines(files, file.path(proj, "input-files.txt"))

# ---- the three recorded T03 tool inputs, sizes substituted --------------------------------------
B = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/bench/gptr-bench/biomedical/v0.5/reports/T03"
calls = jsonlite::read_json(file.path(B, "mcp-replay-analysis/evidence/calls.json"))
codes = vapply(calls$calls, function(x) x$input$code, "")
codes = gsub("1231L", paste0(n_files, "L"), codes, fixed = TRUE)
codes = gsub("== 1231L", paste0("== ", n_files, "L"), codes, fixed = TRUE)
codes = gsub("60664L", paste0(n_rows, "L"), codes, fixed = TRUE)
codes = gsub("60660L", paste0(n_rows - 4L, "L"), codes, fixed = TRUE)
codes = gsub("60,660", format(n_rows - 4L), codes, fixed = TRUE)

setwd(proj)
Sys.setenv(R_USER_CONFIG_DIR = file.path(priv, "config"), R_USER_DATA_DIR = file.path(priv, "data"),
           R_USER_CACHE_DIR = file.path(priv, "cache"), GPTR_PROJECT_ROOT = proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
pkgload::load_all(src, quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")

# ---- counters ----------------------------------------------------------------------------------
G = new.env()
G$req = 0L; G$turn = 0L; G$in_tool = FALSE; G$rows = list(); G$depth = list(); G$t0 = list()
G$sizes = list()
clock = function() as.numeric(proc.time()[["elapsed"]])
sites = c("risk_classify_r", "env_snapshot_rows", "ckpt_unshared_bytes", "tool_result_message",
          "ckpt_note", "risk_binding_leaf", "env_on_agent_end", "env_block_changes",
          "env_block_workspace", "ckpt_objects_before", "ckpt_objects_after", "eval_run",
          "mcp_serve_exec", "dispatch_steps", "perm_decide", "risk_member_flags", "run_settle",
          "gateway_input", "env_view_snapshot", "env_snapshot", "checkpoint_before",
          "checkpoint_after", "context_provide", "ckpt_cp_before", "ckpt_cp_after")
site_of = function() {
  heads = vapply(sys.calls(), function(cl) {
    h = cl[[1L]]; if (is.symbol(h)) as.character(h) else if (is.call(h)) deparse(h)[1] else "?"
  }, "")
  hit = rev(heads[heads %in% sites])
  paste(hit, collapse = "<")
}
G$enter = function(fn, extra = NA_character_) {
  d = (G$depth[[fn]] %||% 0L) + 1L
  G$depth[[fn]] = d
  if (d == 1L) G$t0[[fn]] = clock()
  G$rows[[length(G$rows) + 1L]] = list(fn = fn, req = G$req, turn = G$turn, in_tool = G$in_tool,
                                       outer = d == 1L, extra = extra, t = NA_real_)
  invisible(length(G$rows))
}
G$exit = function(fn) {
  d = G$depth[[fn]] %||% 1L
  if (d == 1L) {
    # attribute the outermost call's inclusive time to its last outer row
    for (k in rev(seq_along(G$rows))) {
      r = G$rows[[k]]
      if (identical(r$fn, fn) && isTRUE(r$outer) && is.na(r$t)) {
        G$rows[[k]]$t = clock() - G$t0[[fn]]
        break
      }
    }
  }
  G$depth[[fn]] = d - 1L
}
G$wait = function(v) G$waits = c(G$waits, v)
`%||%` = function(a, b) if (is.null(a)) b else a
traced = c(
  # risk, parse and policy
  "risk_classify", "risk_classify_r", "risk_scan", "risk_parse", "risk_secret_scan", "secret_scan",
  "risk_binding_info", "risk_binding_leaf", "risk_fn_where", "call_risk", "code_targets",
  "ckpt_predict", "risk_plan_disallowed", "eval_parse", "eval_guard", "perm_check", "perm_decide",
  "perm_policies", "ext_policy_decide", "perm_rules_table", "rule_match", "tool_call_hook",
  "mcp_serve_gate", "mcp_served_tools", "schema_validate", "tool_validate", "risk_norm",
  "perm_policy_mode", "perm_policy_rules", "perm_policy_critical", "perm_policy_secret",
  "perm_policy_protect", "plan_policy_check", "perm_grant_control", "perm_trusted",
  # sizes, walks, hashes
  "env_snap_size", "env_snapshot", "env_view_snapshot", "env_snapshot_rows", "fingerprint",
  "ckpt_unshared_bytes", "serialize_leaf", "ckpt_write_image", "ckpt_state_snapshot",
  "eval_session_state", "ckpt_cons", "hash_sha256", "hash_xxh128", "env_diff",
  # file checkpoints
  "ckpt_scan_run", "ckpt_store_put", "ckpt_files_sync", "ckpt_files_step", "ckpt_files_turn_scan",
  "ckpt_files_before", "ckpt_files_after", "ckpt_call_paths", "ckpt_explicit_state",
  # checkpointers
  "checkpoint_before", "checkpoint_after", "ckpt_objects_before", "ckpt_objects_after",
  "ckpt_state_before", "ckpt_state_after", "ckpt_on_agent_end", "ckpt_objects_budget", "ckpt_gc",
  "ckpt_preimage_modes", "ckpt_capture", "ckpt_settle", "ckpt_note", "ckpt_on_tool_result",
  "ckpt_cp_before", "ckpt_cp_after", "context_collect", "context_provide",
  # events, persistence, encoding
  "ev_dispatch", "session_append", "store_persist", "redact_tree", "json_encode", "entry_prepare",
  "iso_time", "redact", "ev_redact_payload",
  # tool execution
  "mcp_dispatch_local", "mcp_serve_call", "mcp_serve_exec", "mcp_serve_r", "dispatch_call",
  "dispatch_steps", "tool_execute_frame", "tool_run", "eval_r", "eval_run", "format_eval_result",
  "tool_result_message", "dispatch_record", "dispatch_finish", "tool_result_hooks",
  "perm_on_tool_result", "r_tool_execute", "gptr_shim", "eval_assign_targets",
  # per turn and per request
  "run_request", "run_build", "request_build", "project_messages", "prompt_request_estimate",
  "prompt_request_elements", "prompt_request_view", "context_tokens", "run_compact_check",
  "prefix_guard", "ledger_add", "budget_check", "context_turn_blocks", "context_first_message",
  "env_block_changes", "env_block_workspace", "env_on_agent_end", "run_settle",
  "run_settle_persist", "plugin_state_persist", "gateway_run", "user_expr_log",
  "context_instruction_files", "run_freeze", "run_start", "run_tools", "dispatch_tools",
  "run_response", "usage_add_durable", "provider_stream", "run_identity", "prompt_tools_known",
  "entries_path", "images_scan", "run_take", "loop_next",
  # reactor
  "reactor_pump", "reactor_step", "reactor_wait_ms"
)
missing = traced[!vapply(traced, exists, NA, envir = ns, inherits = FALSE)]
if (length(missing)) cat("not found:", missing, "\n")
traced = setdiff(traced, missing)
if (notrace) traced = character()
for (fn in traced) {
  tr = if (fn == "ev_dispatch") {
    quote(get("G", .GlobalEnv)$enter("ev_dispatch", event))
  } else if (fn == "env_snap_size") {
    quote(get("G", .GlobalEnv)$enter("env_snap_size", paste0(
      class(x)[1L], "[", length(x), "]@", get("site_of", .GlobalEnv)())))
  } else if (fn == "ext_policy_decide") {
    quote(get("G", .GlobalEnv)$enter("ext_policy_decide", spec[["name"]]))
  } else if (fn == "context_provide") {
    quote(get("G", .GlobalEnv)$enter("context_provide", sp$name))
  } else if (fn %in% c("ckpt_cp_before", "ckpt_cp_after")) {
    substitute(get("G", .GlobalEnv)$enter(FN, name), list(FN = fn))
  } else if (fn == "risk_binding_info") {
    quote(get("G", .GlobalEnv)$enter("risk_binding_info", name))
  } else if (fn == "reactor_wait_ms") {
    quote(get("G", .GlobalEnv)$enter("reactor_wait_ms", NA_character_))
  } else {
    substitute(get("G", .GlobalEnv)$enter(FN), list(FN = fn))
  }
  ex = if (fn == "reactor_wait_ms") {
    quote({ get("G", .GlobalEnv)$wait(returnValue(NA_real_))
            get("G", .GlobalEnv)$exit("reactor_wait_ms") })
  } else {
    substitute(get("G", .GlobalEnv)$exit(FN), list(FN = fn))
  }
  suppressMessages(trace(fn, where = ns, print = FALSE, tracer = tr, exit = ex))
}

gptr_register(gptr_hook("tool_execution_start", function(event, ctx) {
  G$t_start = clock()
  if (!grepl("/", event$tool_call_id %||% "", fixed = TRUE)) G$in_tool = TRUE
  NULL
}))
gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
  if (!grepl("/", event$tool_call_id %||% "", fixed = TRUE)) {
    G$in_tool = FALSE
    G$tool_elapsed = c(G$tool_elapsed, event$elapsed)
    G$tool_outer = c(G$tool_outer, clock() - G$t_start)
  }
  NULL
}))
gptr_register(gptr_hook("before_request", function(event, ctx) {
  G$turn = G$turn + 1L
  if (identical(route, "mcp")) {
    params = list(name = "r", arguments = list(code = codes[[G$req]]))
    res = get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = G$req, method = "tools/call",
                                             params = params), ctx$session)
    G$rpc[[G$req]] = res
  }
  NULL
}))

home = new.env(parent = globalenv())
prompts = c("Read the inputs into raw and audit them.", "Summarise each file.", "Summarise each gene.")
t_req = numeric()
if (identical(route, "mcp")) {
  fake = gptr_fake_provider(list("Recorded tool call completed offline."), name = "mcp-trace-replay")
} else {
  fake = gptr_fake_provider(list(
    list(tool = "r", input = list(code = codes[[1]])), "done 1",
    list(tool = "r", input = list(code = codes[[2]])), "done 2",
    list(tool = "r", input = list(code = codes[[3]])), "done 3"), name = "native-replay")
}
s = NULL
for (i in 1:3) {
  G$req = i
  t1 = clock()
  if (i == 1) {
    s = peter(prompts[[i]], model = fake, mode = "auto", tools = "minimal", envir = home)
  } else {
    peter(s, prompt = prompts[[i]])
  }
  t_req[i] = clock() - t1
}
G$req = 99L
untrace_all = function() for (fn in traced) suppressMessages(untrace(fn, where = ns))
untrace_all()

if (notrace) G$rows = list(list(fn = "none", req = 0L, turn = 0L, in_tool = FALSE, outer = TRUE,
                                  extra = NA_character_, t = 0))
rows = do.call(rbind, lapply(G$rows, function(r) data.frame(r, stringsAsFactors = FALSE)))
write.csv(rows, file.path(out, "calls-raw.csv"), row.names = FALSE)
agg = aggregate(cbind(n = 1, t = ifelse(is.na(rows$t), 0, rows$t)) ~ fn + req + in_tool,
                data = rows, FUN = sum)
agg = agg[order(agg$req, !agg$in_tool, -agg$t), ]
write.csv(agg, file.path(out, "calls-by-request.csv"), row.names = FALSE)
sz = rows[rows$fn == "env_snap_size", c("req", "turn", "in_tool", "extra", "t")]
write.csv(sz, file.path(out, "env-snap-size-calls.csv"), row.names = FALSE)
ev = rows[rows$fn == "ev_dispatch", ]
evt = as.data.frame(table(req = ev$req, in_tool = ev$in_tool, event = ev$extra))
evt = evt[evt$Freq > 0, ]
write.csv(evt, file.path(out, "events.csv"), row.names = FALSE)
bi = rows[rows$fn == "risk_binding_info", c("req", "in_tool", "extra")]
write.csv(bi, file.path(out, "binding-info.csv"), row.names = FALSE)
cat("route", route, "files", n_files, "rows", n_rows, "\n")
cat("request wall s:", round(t_req, 3), "\n")
cat("tool internal elapsed s:", round(G$tool_elapsed, 3), "\n")
cat("tool outer s:", round(G$tool_outer, 3), "\n")
cat("tool outer minus internal s:", round(G$tool_outer - G$tool_elapsed, 3), "\n")
cat("objects in home:", paste(ls(home), collapse = ", "), "\n")
cat("reactor waits ms (sum, n):", sum(G$waits, na.rm = TRUE), length(G$waits), "\n")
st = vapply(G$rpc %||% list(), function(r) isTRUE(r$result$isError), NA)
cat("rpc errors:", st, "\n")
d = get("session_data", ns)(s)
cat("session entries:", length(d$entries), " status:", d$status, "\n")
if (!is.null(d$reason)) cat("reason:", d$reason, "\n")
