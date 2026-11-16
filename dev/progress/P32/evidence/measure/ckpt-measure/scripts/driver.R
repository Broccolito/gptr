# Checkpoint cost driver: served `r` calls through gptr:::mcp_dispatch_local from a
# before_request hook (as the benchmark's profile-mcp.R), fake provider, no network.
# Usage: Rscript --vanilla driver.R <scenario> <rep> <outdir> [key=value ...]
#   keys: ckpt=on|off|files  spill=0|1  prof=0|1  trace=1|0  n=<tables or objects>  files=<n>
a = commandArgs(TRUE)
scenario = a[1]; rep_id = a[2]; outdir = a[3]
kv = list(ckpt = "on", spill = "0", prof = "0", trace = "1", n = "500", files = "0", fine = "1", link = "sym")
for (x in a[-(1:3)]) { p = strsplit(x, "=", fixed = TRUE)[[1]]; kv[[p[1]]] = p[2] }
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/ckpt-measure"
tag = paste(scenario, paste(names(kv), unlist(kv), sep = "", collapse = "_"), rep_id, sep = "__")
work = file.path(outdir, tag)
unlink(work, recursive = TRUE)
dir.create(file.path(work, "proj"), recursive = TRUE)
dir.create(file.path(work, "private"), recursive = TRUE)
work = normalizePath(work)
proj = file.path(work, "proj")
setwd(proj)
Sys.setenv(R_USER_CONFIG_DIR = file.path(work, "private/config"),
           R_USER_DATA_DIR = file.path(work, "private/data"),
           R_USER_CACHE_DIR = file.path(work, "private/cache"),
           GPTR_PROJECT_ROOT = proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj,
        gptr.checkpoint = kv$ckpt)
if (kv$spill == "1") dir.create(file.path(proj, ".gptr"))
suppressMessages(pkgload::load_all(file.path(W, "src/gptr"), quiet = TRUE, helpers = FALSE,
                                   attach_testthat = FALSE))
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])

# ---- trace accumulators: total and count per function and per (function @ traced parent) ----
TT = new.env()
TT$tot = list(); TT$cnt = list(); TT$stack = character(); TT$t0 = numeric()
mark = function(fn, stage) {
  if (stage == "enter") {
    TT$stack = c(TT$stack, fn); TT$t0 = c(TT$t0, clock()); return(invisible())
  }
  i = max(which(TT$stack == fn))
  dt = clock() - TT$t0[i]
  parent = if (i > 1L) TT$stack[i - 1L] else "-"
  for (k in c(fn, paste0(fn, "@", parent))) {
    TT$tot[[k]] = (if (is.null(TT$tot[[k]])) 0 else TT$tot[[k]]) + dt
    TT$cnt[[k]] = (if (is.null(TT$cnt[[k]])) 0L else TT$cnt[[k]]) + 1L
  }
  TT$stack = TT$stack[-i]; TT$t0 = TT$t0[-i]
  invisible()
}
coarse = c("mcp_serve_exec", "mcp_serve_gate", "mcp_serve_r", "checkpoint_before",
           "checkpoint_after", "ckpt_objects_before", "ckpt_objects_after", "ckpt_files_before",
           "ckpt_files_after", "ckpt_state_before", "ckpt_state_after", "env_snapshot",
           "ckpt_write_image", "ckpt_capture_disk", "ckpt_files_sync", "ckpt_scan_run",
           "ckpt_files_step", "ckpt_files_explicit", "ckpt_state_snapshot", "run_append_custom",
           "ckpt_on_agent_end", "ckpt_objects_budget", "ckpt_spill", "ckpt_gc", "ckpt_note",
           "ckpt_preimage_modes", "ckpt_capture", "ckpt_settle", "ckpt_predict",
           "env_on_agent_end", "eval_r", "ckpt_on_tool_result", "ckpt_obj_sweep",
           "ckpt_files_scan", "ckpt_files_observe")
fine = c("env_snap_size", "ckpt_unshared_bytes", "ckpt_store_put", "settings_get",
         "ckpt_explicit_state", "serialize_leaf", "write_atomic", "fingerprint")
traced = if (kv$trace == "1") c(coarse, if (kv$fine == "1") fine) else character()
for (fn in traced) {
  suppressMessages(trace(fn, where = ns, print = FALSE,
    tracer = substitute(get("mark", .GlobalEnv)(FN, "enter"), list(FN = fn)),
    exit = substitute(get("mark", .GlobalEnv)(FN, "exit"), list(FN = fn))))
}

# ---- disk accounting --------------------------------------------------------------------------
du = function(p) {
  f = list.files(p, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  c(n = length(f), bytes = sum(file.size(f), na.rm = TRUE))
}
disk = function() {
  list(tmp_ckpt = du(file.path(tempdir(), "gptr", "checkpoints")),
       tmp_objects = du(file.path(tempdir(), "gptr", "checkpoints", "objects")),
       tmp_sessions = du(file.path(tempdir(), "gptr", "sessions")),
       ws_objects = du(file.path(proj, ".gptr", "checkpoints", "objects")),
       ws_ckpt = du(file.path(proj, ".gptr", "checkpoints")),
       private = du(file.path(work, "private")),
       ws_sessions = du(file.path(proj, ".gptr", "sessions")))
}
rss = function() as.numeric(ps::ps_memory_info()[["rss"]]) / 2^30
held = function() tryCatch({
  ws = get("ckpt_ext_state", ns)()$sessions
  nm = ls(ws)
  if (!length(nm)) return(list(none = TRUE))
  ck = rlang::wref_value(get(nm[1], envir = ws))
  idx = ck$obj$index
  list(rows = nrow(idx), mem_bytes = sum(idx$bytes[idx$where == "memory"], na.rm = TRUE),
       disk_rows = sum(idx$where == "disk"), roles = as.list(table(idx$role)),
       slots = length(ls(ck$obj$slots, all.names = TRUE)), per_turn = isTRUE(ck$files$per_turn),
       files_complete = isTRUE(ck$files$complete), stat_rows = NROW(ck$files$stat),
       hashed = length(ck$files$hash))
}, error = function(e) list(err = conditionMessage(e)))

# ---- scenario ----------------------------------------------------------------------------------
source(file.path(W, "scripts", "scenarios.R"))
sc = scenarios[[scenario]](kv, proj)
home = new.env(parent = globalenv())
if (is.function(sc$setup)) sc$setup(home, proj)
gc()

res_file = file.path(outdir, paste0(tag, ".jsonl"))
unlink(res_file)
state = new.env(); state$request = 0L
emit = function(x) cat(jsonlite::toJSON(x, auto_unbox = TRUE, digits = 8, null = "null"), "\n",
                       file = res_file, append = TRUE)
snapTT = function() list(tot = TT$tot, cnt = TT$cnt)
delta = function(b, a) {
  ks = names(a$tot)
  out = list()
  for (k in ks) {
    t0 = if (is.null(b$tot[[k]])) 0 else b$tot[[k]]
    c0 = if (is.null(b$cnt[[k]])) 0L else b$cnt[[k]]
    if (a$cnt[[k]] > c0) out[[k]] = list(s = a$tot[[k]] - t0, n = a$cnt[[k]] - c0)
  }
  out
}
call_no = 0L
gptr_register(gptr_hook("before_request", function(event, ctx) {
  state$request = state$request + 1L
  codes = sc$requests[[state$request]]
  for (j in seq_along(codes)) {
    call_no <<- call_no + 1L
    label = names(codes)[j]
    prof_file = NULL
    if (kv$prof == "1" && label %in% (sc$profile %||% names(codes))) {
      prof_file = file.path(outdir, paste0(tag, "__", label, ".Rprof"))
      utils::Rprof(prof_file, interval = 0.005, memory.profiling = FALSE)
    }
    b = snapTT(); d0 = disk(); t0 = clock()
    params = list(name = "r", arguments = list(code = codes[[j]]))
    result = get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = call_no,
                                                method = "tools/call", params = params),
                                           ctx$session)
    t1 = clock()
    if (!is.null(prof_file)) utils::Rprof(NULL)
    a = snapTT(); d1 = disk()
    err = !is.null(result$error) || isTRUE(result$result$isError)
    txt = tryCatch(paste(vapply(result$result$content, function(x) x$text %||% "", ""),
                         collapse = "\n"), error = function(e) "")
    emit(list(scenario = scenario, rep = rep_id, kv = kv, request = state$request, call = call_no,
              label = label, outer_s = t1 - t0, error = err, text = substr(txt, 1, 600),
              phases = delta(b, a), disk_before = d0, disk_after = d1, rss_gb = rss(), held = held()))
    if (err) message("CALL ERROR in ", label, ": ", substr(txt, 1, 400))
  }
  NULL
}))
gptr_register(gptr_hook("agent_end", function(event, ctx) {
  state$agent_end_t = clock()
  NULL
}))
fake = gptr_fake_provider(list("ok"), name = "ckpt-measure")
for (r in seq_along(sc$requests)) {
  b = snapTT(); t0 = clock()
  if (r == 1L) {
    s = peter("request 1", model = fake, mode = "auto", tools = "minimal", envir = home)
  } else {
    peter(s, prompt = paste("request", r))
  }
  a = snapTT()
  emit(list(scenario = scenario, rep = rep_id, kv = kv, request = r, label = "__request__",
            request_s = clock() - t0, phases = delta(b, a), disk_after = disk(), rss_gb = rss(),
            held = held()))
}
emit(list(scenario = scenario, rep = rep_id, kv = kv, label = "__final__",
          checkpoint_setting = get("setting_get", ns)("checkpoint", default = "on"),
          tempdir = tempdir(), proj = proj, disk = disk(),
          max_rss_gb = rss()))
cat("done", tag, "\n")
