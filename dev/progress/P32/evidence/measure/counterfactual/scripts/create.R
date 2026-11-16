# What-if timing of T03 request 1 (the call that creates `raw`) and of a call that modifies `raw`,
# per checkpoint/size variant, MCP route; plus the checkpoint fragment and rewind preview records.
N = as.integer(Sys.getenv("N", "1231"))
REPS = as.integer(Sys.getenv("REPS", "3"))
TAG = paste0("create-mcp-", N, Sys.getenv("SUFFIX"))
source("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual/scripts/workload.R")
VARIANTS = strsplit(Sys.getenv("VARIANTS", "base,share,files,off,all"), ",")[[1]]

P = new.env()
P$k = 0L; P$fn = P$req = character(2e5); P$t = numeric(2e5); P$stage = character(2e5)
P$depth = list(); P$cur = ""
mark = function(fn, stage) {
  d = P$depth[[fn]] %||% 0L
  if (stage == "enter") { P$depth[[fn]] = d + 1L; if (d > 0L) return(invisible()) }
  else { P$depth[[fn]] = d - 1L; if (d > 1L) return(invisible()) }
  k = P$k + 1L; P$k = k
  P$fn[k] = fn; P$stage[k] = stage; P$t[k] = clock(); P$req[k] = P$cur
}
assign("mark", mark, envir = globalenv())
for (fn in c("risk_classify_r", "env_snap_size", "mcp_serve_gate", "checkpoint_before",
             "checkpoint_after", "env_on_agent_end", "context_collect", "ckpt_objects_after",
             "ckpt_files_after", "ckpt_on_agent_end")) {
  if (!exists(fn, envir = ns, inherits = FALSE)) next
  suppressMessages(trace(fn, where = ns, print = FALSE,
    tracer = substitute(get("mark", globalenv())(FN, "enter"), list(FN = fn)),
    exit = substitute(get("mark", globalenv())(FN, "exit"), list(FN = fn))))
}

S = new.env()
S$code = "invisible(0)"; S$id = 0L; S$pending = FALSE
gptr_register(gptr_hook("tool_execution_start", function(event, ctx) {
  S$t_start = clock(); mark("TOOL", "enter"); NULL
}))
gptr_register(gptr_hook("tool_execution_end", function(event, ctx) {
  S$t_end = clock(); mark("TOOL", "exit")
  S$internal = event$elapsed; S$is_error = isTRUE(event$is_error)
  S$text = substr(paste(vapply(event$content %||% list(), function(b) b$text %||% "", ""),
                        collapse = " "), 1, 200)
  NULL
}))
gptr_register(gptr_hook("before_request", function(event, ctx) {
  if (!isTRUE(S$pending)) return(NULL)
  S$pending = FALSE
  S$id = S$id + 1L
  get("mcp_dispatch_local", ns)(list(jsonrpc = "2.0", id = S$id, method = "tools/call",
    params = list(name = "r", arguments = list(code = S$code))), ctx$session)
  NULL
}))
fake = gptr_fake_provider(list("Recorded tool call completed offline."), name = "counterfactual")
home = new.env(parent = globalenv())
s = peter("start", model = fake, mode = "auto", tools = "minimal", envir = home, .run = FALSE)

rows = list(); recs = list(); plans = list()
fragment_rows = function(variant, label, rep, since) {
  ents = ns$session_data(s)$entries
  ents = if (length(ents) > since) ents[(since + 1L):length(ents)] else list()
  ck = Filter(function(e) identical(e$custom_type %||% e$customType %||% "", "gptr.checkpoint"), ents)
  if (!length(ck)) return(data.frame(variant = variant, code = label, rep = rep, checkpointer = "(none)",
    name = "", status = "", how = "", class = "", bytes = NA, restorable = NA, reason = "no checkpoint entry"))
  out = list()
  for (e in ck) {
  fr = (e$data %||% e)$fragments
  for (cp in names(fr)) {
    objs = fr[[cp]]$objects %||% list()
    for (o in objs) {
      out[[length(out) + 1L]] = data.frame(variant = variant, code = label, rep = rep, checkpointer = cp,
        name = o$name %||% "", status = o$status %||% "", how = o$how %||% "", class = o$class %||% "",
        bytes = as.numeric(o$bytes %||% NA), restorable = isTRUE(o$restorable), reason = o$reason %||% "")
    }
    if (!length(objs)) out[[length(out) + 1L]] = data.frame(variant = variant, code = label, rep = rep,
      checkpointer = cp, name = "", status = "", how = "", class = "", bytes = NA,
      restorable = isTRUE(fr[[cp]]$restorable), reason = fr[[cp]]$reason %||% "")
  }
  }
  do.call(rbind, out)
}
one = function(variant, label, code, rep) {
  set_variant(if (variant == "warm") "base" else variant)
  S$code = code; S$pending = TRUE
  S$t_start = S$t_end = S$internal = NA; S$is_error = NA
  P$cur = paste(variant, label, rep, sep = "#")
  invisible(gc())
  since = length(ns$session_data(s)$entries)
  t0 = clock()
  peter(s, prompt = paste("request", variant, label, rep))
  t1 = clock()
  row = data.frame(route = "mcp", n = N, variant = variant, code = label, rep = rep,
                   wall_s = t1 - t0, pre_tool_s = S$t_start - t0, outer_s = S$t_end - S$t_start,
                   internal_s = S$internal, gap_s = S$t_end - S$t_start - S$internal,
                   post_tool_s = t1 - S$t_end, is_error = S$is_error, rss_gb = rss_gb())
  rows[[length(rows) + 1L]] <<- row
  write.csv(do.call(rbind, rows), file.path(OUT, paste0("runs-", TAG, ".csv")), row.names = FALSE)
  k = P$k
  write.csv(data.frame(req = P$req[1:k], fn = P$fn[1:k], stage = P$stage[1:k], t = P$t[1:k]),
            file.path(OUT, paste0("marks-", TAG, ".csv")), row.names = FALSE)
  if (variant != "warm") {
    fr = fragment_rows(variant, label, rep, since)
    if (!is.null(fr)) recs[[length(recs) + 1L]] <<- fr
    pl = tryCatch(gptr_rewind(s, preview = TRUE), error = function(e) data.frame(error = conditionMessage(e)))
    pl = as.data.frame(pl)
    if (nrow(pl)) plans[[length(plans) + 1L]] <<- cbind(data.frame(variant = variant, code = label, rep = rep), pl)
    write.csv(do.call(rbind, recs), file.path(OUT, paste0("ckpt-records-", TAG, ".csv")), row.names = FALSE)
    write.csv(do.call(rbind, lapply(plans, function(x) x[, intersect(names(x), c("variant", "code", "rep", "record", "turn", "action", "checkpointer", "item", "restore", "reason", "error")), drop = FALSE])),
              file.path(OUT, paste0("rewind-preview-", TAG, ".csv")), row.names = FALSE)
  }
  print(row[, c("variant", "code", "rep", "wall_s", "outer_s", "internal_s", "gap_s", "post_tool_s", "is_error", "rss_gb")], row.names = FALSE)
  if (isTRUE(S$is_error)) cat("  error text:", S$text, "\n")
  flush.console()
}
clear = function() {
  rm(list = intersect(ls(home, all.names = TRUE), c("raw", "files", "tables", "reference_gene_ids", "gene_rows",
     "total_gene_counts", "zero_gene_values", "input_audit", "tab", "counts", "i")), envir = home)
  writeLines("placeholder", file.path(proj, "input-audit.csv"))  # same file state before every create
  invisible(gc())
}
writeLines("placeholder", file.path(proj, "input-audit.csv"))  # same file state before every create
one("warm", "w", "invisible(0)", 1L)
one("warm", "w", "invisible(0)", 2L)
for (r in seq_len(REPS)) for (v in VARIANTS) {
  clear()
  one(v, "c1", code1, r)
  one(v, "e", 'raw$note = "x"', r)
}
setwd(W)
unlink(work, recursive = TRUE)
cat("DONE\n")
