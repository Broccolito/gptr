# Per-turn / per-request harness overhead of gptr's native agent loop (fake provider, offline).
# Usage: Rscript --vanilla loop.R key=value ...
#   scenario = empty | big | small | history ; tools = minimal | default ; mode = auto | default
#   K = tool calls per request ; reps = measured requests ; warm = warm-up requests
#   ntab = data.tables in `raw` (big) ; nobj = objects (small) ; hist = prior prompts (history)
#   code = tool code ; rprof = 0/1 ; trace = 0/1 ; tag = output label
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/loop-measure"
cfg = list(scenario = "empty", tools = "minimal", mode = "auto", K = 10L, reps = 3L, warm = 2L,
           ntab = 300L, nobj = 1000L, hist = 50L, code = "1 + 1", rprof = 0L, trace = 1L,
           tag = "run", hooks = 1L,
           hcode = "x = rnorm(100); summary(x)")
for (a in commandArgs(TRUE)) {
  kv = strsplit(a, "=", fixed = TRUE)[[1]]
  key = kv[1]
  val = paste(kv[-1], collapse = "=")
  cfg[[key]] = if (is.numeric(cfg[[key]]) || is.integer(cfg[[key]])) as.integer(val) else val
}
tag = cfg$tag
home_dir = file.path(W, "home", tag)
proj = file.path(home_dir, "project")
dir.create(proj, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(R_USER_CONFIG_DIR = file.path(home_dir, "config"),
           R_USER_DATA_DIR = file.path(home_dir, "data"),
           R_USER_CACHE_DIR = file.path(home_dir, "cache"), GPTR_PROJECT_ROOT = proj)
setwd(proj)
options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = proj)
gcinfo(FALSE)
invisible(gc.time(TRUE))
pkgload::load_all(file.path(W, cfg$src %||% "src/gptr"), quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
clock = function() as.numeric(proc.time()[["elapsed"]])

# ---- workspace -------------------------------------------------------------------------------
home = new.env(parent = globalenv())
t_ws = clock()
if (cfg$scenario == "big") {
  set.seed(1)
  n = 60664L
  ids = sprintf("ENSG%011d.%d", seq_len(n), 1L + seq_len(n) %% 20L)
  gnames = sprintf("GENE%06d", seq_len(n))
  gtype = sample(c("protein_coding", "lncRNA", "miRNA", "snRNA", "pseudogene"), n, TRUE)
  base = data.table::data.table(gene_id = ids, gene_name = gnames, gene_type = gtype,
    unstranded = rpois(n, 50), stranded_first = rpois(n, 25), stranded_second = rpois(n, 25),
    tpm_unstranded = runif(n), fpkm_unstranded = runif(n), fpkm_uq_unstranded = runif(n))
  # distinct column vectors per table (copy), strings shared via R's CHARSXP cache as with fread()
  home$raw = lapply(seq_len(cfg$ntab), function(i) data.table::copy(base))
  rm(base)
  names(home$raw) = sprintf("sample_%04d", seq_len(cfg$ntab))
  home$files = sprintf("/data/star/%04d.tsv", seq_len(cfg$ntab))
} else if (cfg$scenario == "small") {
  for (i in seq_len(cfg$nobj)) {
    nm = sprintf("obj_%04d", i)
    v = switch(i %% 4L + 1L, rnorm(10), letters[1:5], data.frame(a = 1:5, b = rnorm(5), c = letters[1:5]),
               list(x = 1, y = "a"))
    assign(nm, v, envir = home)
  }
}
t_ws = clock() - t_ws
ws_bytes = sum(vapply(ls(home), function(n) as.numeric(utils::object.size(get(n, home))), 0))
cat(sprintf("workspace %s built in %.1fs, object.size total %.3f GB, %d bindings\n",
            cfg$scenario, t_ws, ws_bytes / 1e9, length(ls(home))))

# ---- fake provider: K tool calls per request, then a final answer ------------------------------
ctl = new.env()
ctl$left = 0L
ctl$code = cfg$code
ctl$answer = "Done."
script = function(req) {
  if (ctl$left > 0L) {
    ctl$left = ctl$left - 1L
    list(tool = "r", input = list(code = ctl$code))
  } else {
    ctl$answer
  }
}
fake = gptr_fake_provider(script, name = "loopfake")

# ---- event log ----------------------------------------------------------------------------------
ev = new.env()
ev$t = numeric()
ev$type = character()
ev$x = numeric()
ev$err = logical()
ev$req = integer()
ev$cur = 0L
evtypes = c("agent_start", "agent_end", "turn_start", "turn_end", "before_request", "message_end",
            "tool_execution_start", "tool_execution_end", "usage", "tool_call")
for (et in if (cfg$hooks == 1L) evtypes else character()) {
  local({
    et = et
    gptr_register(gptr_hook(et, function(event, ctx) {
      t = clock()
      extra = NA_real_
      err = NA
      tp = et
      if (et == "tool_execution_end") {
        extra = as.numeric(event$elapsed %||% NA)
        err = isTRUE(event$is_error)
      }
      if (et == "message_end") tp = paste0("message_end:", event$role %||% "?")
      ev$t = c(ev$t, t)
      ev$type = c(ev$type, tp)
      ev$x = c(ev$x, extra)
      ev$err = c(ev$err, err)
      ev$req = c(ev$req, ev$cur)
      NULL
    }))
  })
}
`%||%` = function(a, b) if (is.null(a)) b else a

# ---- inclusive phase timers via trace() ----------------------------------------------------------
ph = new.env()
ph$depth = list()
ph$start = list()
ph$name = character()
ph$t0 = numeric()
ph$t1 = numeric()
ph$req = integer()
.ph_enter = function(fn) {
  d = (ph$depth[[fn]] %||% 0L) + 1L
  ph$depth[[fn]] = d
  if (d == 1L) ph$start[[fn]] = clock()
}
.ph_exit = function(fn) {
  d = ph$depth[[fn]] %||% 1L
  ph$depth[[fn]] = d - 1L
  if (d == 1L) {
    ph$name = c(ph$name, fn)
    ph$t0 = c(ph$t0, ph$start[[fn]])
    ph$t1 = c(ph$t1, clock())
    ph$req = c(ph$req, ev$cur)
  }
}
assign(".ph_enter", .ph_enter, envir = globalenv())
assign(".ph_exit", .ph_exit, envir = globalenv())
traced = c(
  # gateway / run start and end
  "gateway_dispatch", "session_new", "run_start", "run_freeze", "run_wire", "run_settle",
  "run_settle_persist", "session_attach", "doc_locate", "doc_route_match", "replay_notice",
  # per-turn request side
  "run_begin_request", "run_request", "run_compact_check", "run_target", "run_build",
  "budget_check", "ledger_add", "run_request_params", "provider_stream", "request_build",
  "prompt_request_estimate", "prompt_request_view", "context_collect", "prefix_guard",
  # response side
  "run_response", "usage_add_durable", "run_estimator_update", "run_on_event",
  # tools
  "run_tools", "dispatch_tools", "dispatch_call", "tool_validate", "call_risk", "tool_call_hook",
  "perm_check", "perm_decide", "checkpoint_before", "checkpoint_after", "tool_run",
  "tool_result_hooks", "dispatch_finish", "eval_r",
  # loop, events, persistence
  "loop_next", "run_finish_turn", "session_emit", "session_append", "store_append",
  "store_write_lines", "store_persist",
  # workspace description and size
  "env_view_snapshot", "env_snap_size", "user_expr_log",
  # fake provider (not harness)
  "fake_request", "fake_plan", "fake_pick",
  # reactor
  "reactor_step", "reactor_io")
traced = traced[vapply(traced, function(f) exists(f, envir = ns, inherits = FALSE), NA)]
if (cfg$trace == 1L) {
  for (fn in traced) {
    suppressMessages(trace(fn, where = ns, print = FALSE,
      tracer = substitute(.ph_enter(FN), list(FN = fn)),
      exit = substitute(.ph_exit(FN), list(FN = fn))))
  }
}

# ---- driver ----------------------------------------------------------------------------------
peter_args = list(model = fake, envir = home)
if (cfg$tools == "minimal") peter_args$tools = "minimal"
if (cfg$mode == "auto") peter_args$mode = "auto"
reqlog = list()
s = NULL
ask = function(prompt, k, label) {
  ctl$left = k
  ev$cur = ev$cur + 1L
  g0 = gc.time()[1]
  t0 = clock()
  if (is.null(s)) {
    s <<- do.call(peter, c(list(prompt), peter_args))
  } else {
    s <<- peter(s, prompt = prompt)
  }
  t1 = clock()
  g1 = gc.time()[1]
  reqlog[[length(reqlog) + 1L]] <<- data.frame(req = ev$cur, label = label, k = k, t0 = t0, t1 = t1,
                                                wall = t1 - t0, gc_s = g1 - g0)
  invisible(t1 - t0)
}
long_answer = paste(rep("The summary shows the values are centred near zero with unit spread.", 12),
                    collapse = " ")
if (cfg$scenario == "history") {
  ctl$code = cfg$hcode
  ctl$answer = long_answer
  for (h in seq_len(cfg$hist)) {
    ask(sprintf("History step %d: simulate 100 normal values and summarise them briefly.", h), 1L,
        "history")
  }
  ctl$code = cfg$code
  ctl$answer = "Done."
}
# the session is created by the first request of the run (warm-up) unless history built it
for (w in seq_len(cfg$warm)) ask("Warm-up: compute 1 + 1 a few times with the r tool.", cfg$K, "warm")
if (cfg$rprof == 1L) utils::Rprof(file.path(W, "logs", paste0(tag, ".rprof")), interval = 0.005,
                                  memory.profiling = FALSE)
for (r in seq_len(cfg$reps)) ask(sprintf("Measured request %d: compute 1 + 1 with the r tool.", r),
                                 cfg$K, "measured")
if (cfg$rprof == 1L) utils::Rprof(NULL)
if (cfg$trace == 1L) for (fn in traced) suppressMessages(untrace(fn, where = ns))

# ---- outputs ---------------------------------------------------------------------------------
out = file.path(W, "logs", tag)
dir.create(out, showWarnings = FALSE, recursive = TRUE)
events = data.frame(req = ev$req, t = ev$t, type = ev$type, x = ev$x, err = ev$err)
phases = data.frame(req = ph$req, name = ph$name, t0 = ph$t0, t1 = ph$t1)
reqs = do.call(rbind, reqlog)
write.csv(events, file.path(out, "events.csv"), row.names = FALSE)
write.csv(phases, file.path(out, "phases.csv"), row.names = FALSE)
write.csv(reqs, file.path(out, "requests.csv"), row.names = FALSE)
d = session_data(s)
info = list(cfg = cfg, ws_gb = ws_bytes / 1e9, ws_build_s = t_ws,
            entries = length(d$entries %||% list()), turns = d$turns,
            mode = d$mode %||% NA, preset = d$frozen$preset %||% NA,
            text = substr(s$text %||% "", 1, 60),
            maxrss_gb = NA)
jsonlite::write_json(info, file.path(out, "info.json"), auto_unbox = TRUE, pretty = TRUE)
cat("requests:\n")
print(reqs)
cat("done", tag, "\n")
