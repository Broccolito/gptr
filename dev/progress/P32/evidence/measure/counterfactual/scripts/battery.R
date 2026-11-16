# Behaviour battery: perm_decide() decision, level, reasons, flags and sizes per variant and mode.
# Nothing in the battery is executed: calls go through classification and perm_decide() only.
N = as.integer(Sys.getenv("N", "100"))
TAG = paste0("battery-", N)
source("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual/scripts/workload.R")
VARIANTS = strsplit(Sys.getenv("VARIANTS", "base,reuse,cache,bound,skip,share,loop,rc,all,all_bound"), ",")[[1]]
MODES = strsplit(Sys.getenv("MODES", "auto,manual,edits,plan"), ",")[[1]]
writeLines("a,b\n1,2", file.path(proj, "x.csv"))
home = new.env(parent = globalenv())
home$raw = list(files = files, tables = setNames(lapply(files, cf_table), files))
home$small = 1:10
home$files = files
cat(sprintf("raw env_snap_size = %.3e bytes (protect_size 1e8)\n", ns$env_snap_size(home$raw, home)))

snippets = list(
  rm_all = "rm(list = ls())",
  file_remove = 'file.remove("x.csv")',
  unlink_dot = 'unlink(".", recursive = TRUE)',
  system_ls = 'system("ls")',
  setenv = 'Sys.setenv(A = "1")',
  write_tmp = 'writeLines("a", "/tmp/out.txt")',
  raw_null = "raw = NULL",
  small_assign = "small = 2",
  sum_raw = "sum(raw$tables[[1]]$unstranded)",
  t03_r2 = code2,
  t03_r3 = code3)

rows = list()
decide = function(run, key, code, mode, variant, modify_to = NULL, unguarded = FALSE) {
  env = ns$run_eval_env(run)
  spec = ns$registry_get("tool", "r", session = ns$session_data(run$shell)$id)
  t0 = clock()
  risk0 = ns$ext_service_get("risk.classify")(code, envir = env, root = ns$project_root(), kind = "r")
  call = list(id = paste0("bat_", key), name = "r", input = list(code = code), tool = spec,
              nested = FALSE, risk = risk0, envir = env)
  if (ns$cf_on("reuse")) call$risk_input = call$input
  if (!is.null(modify_to)) {  # what a tool_call hook's `modify` does to the call (tool_call_hook())
    call$input = list(code = modify_to)
    if (unguarded) call$risk_input = call$input
  }
  d = ns$perm_decide(call, run)
  el = clock() - t0
  run$blocked = NULL
  run$condition = NULL
  fl = d$risk$flagged
  flags = if (is.data.frame(fl) && nrow(fl)) paste(sprintf("%s [%d]", fl$call, fl$level), collapse = " | ") else ""
  sz = d$risk$sizes
  sizes = if (length(sz)) paste(sprintf("%s=%s", names(sz), format(sz, digits = 4)), collapse = ";") else ""
  rows[[length(rows) + 1L]] <<- data.frame(mode = mode, variant = variant, snippet = key,
    decision = d$decision, reason = d$reason, how = d$how %||% "", rule = paste(d$rule %||% "", collapse = ","),
    level = as.integer(d$risk$level %||% NA), label = d$risk$label %||% "", flags = flags,
    sizes = sizes, secs = el, stringsAsFactors = FALSE)
}
B = new.env(); B$mode = ""
gptr_register(gptr_hook("before_request", function(event, ctx) {
  if (!nzchar(B$mode)) return(NULL)
  run = ns$session_live(ctx$session)$run
  for (v in VARIANTS) {
    set_variant(v)
    for (k in names(snippets)) decide(run, k, snippets[[k]], B$mode, v)
    decide(run, "hook_modify", "sum(1)", B$mode, v, modify_to = "rm(list = ls())")
    if ("reuse" %in% VARS[[v]]$cf) {
      decide(run, "hook_modify_unguarded", "sum(1)", B$mode, v, modify_to = "rm(list = ls())",
             unguarded = TRUE)
    }
    cat(sprintf("mode %s variant %s done\n", B$mode, v)); flush.console()
  }
  set_variant("base")
  B$mode = ""
  NULL
}))
fake = gptr_fake_provider(list("ok"), name = "battery")
for (m in MODES) {
  set_variant("base")
  # manual_r2 / manual_r3: manual mode with a session allow rule r(level<=2) / r(level<=3)
  lv = if (grepl("^manual_r[0-9]$", m)) sub("^manual_r", "", m)
  rule = if (!is.null(lv)) sprintf("r(level<=%s)", lv)
  if (!is.null(rule)) gptr_permissions(allow = rule, scope = "session")
  s = peter("start", model = fake, mode = if (is.null(rule)) m else "manual", tools = "minimal",
            envir = home, .run = FALSE)
  B$mode = m
  peter(s, prompt = paste("battery", m))
  if (!is.null(rule)) gptr_permissions(remove = rule, scope = "session")
}
res = do.call(rbind, rows)
write.csv(res, file.path(OUT, paste0(TAG, ".csv")), row.names = FALSE)

# compare each variant with base (same mode, snippet)
base = res[res$variant == "base", ]
cmp = merge(res[res$variant != "base", ], base, by = c("mode", "snippet"), suffixes = c("", ".base"), all.x = TRUE)
cmp$same_decision = cmp$decision == cmp$decision.base
cmp$same_level = cmp$level == cmp$level.base
cmp$same_reason = cmp$reason == cmp$reason.base
cmp$same_flags = cmp$flags == cmp$flags.base
cmp$same_sizes = cmp$sizes == cmp$sizes.base
diffs = cmp[!(cmp$same_decision & cmp$same_level & cmp$same_reason & cmp$same_flags & cmp$same_sizes) |
              is.na(cmp$same_decision),
            c("mode", "variant", "snippet", "decision.base", "decision", "level.base", "level",
              "same_reason", "same_flags", "same_sizes", "reason.base", "reason", "flags.base", "flags")]
write.csv(diffs, file.path(OUT, paste0(TAG, "-diffs.csv")), row.names = FALSE)
cat("\n==== base decisions ====\n")
print(base[, c("mode", "snippet", "decision", "level", "reason")], row.names = FALSE, right = FALSE)
cat("\n==== differences from base ====\n")
print(diffs[, c("mode", "variant", "snippet", "decision.base", "decision", "level.base", "level",
                "same_reason", "same_flags", "same_sizes")], row.names = FALSE)
summ = aggregate(cbind(same_decision, same_level, same_reason, same_flags, same_sizes) ~ variant,
                 data = cmp[cmp$snippet != "hook_modify_unguarded", ], FUN = function(x) sum(!x))
cat("\n==== count of differing rows per variant (excluding the unguarded contrast) ====\n")
print(summ, row.names = FALSE)
setwd(W)
unlink(work, recursive = TRUE)
cat("DONE\n")
