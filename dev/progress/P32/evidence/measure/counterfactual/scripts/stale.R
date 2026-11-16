# Staleness of a size keyed by the snapshot facts (address, class, shape, fingerprint): a by-reference
# data.table edit deep inside `raw` keeps the key, so the cached size goes stale. Run outside a session.
N = as.integer(Sys.getenv("N", "100"))
TAG = paste0("stale-", N)
source("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual/scripts/workload.R")
home = new.env(parent = globalenv())
home$raw = list(files = files, tables = setNames(lapply(files, cf_table), files))
classify = function(v) {
  set_variant(v)
  r = ns$risk_classify("raw = NULL", envir = home, root = proj, kind = "r")
  c(level = r$level, bytes = unname(r$sizes[["raw"]]))
}
key0 = ns$cf_key(ns$env_snap_leaf(home$raw))
b0 = classify("base"); c0 = classify("cache")
for (k in 1:5) {  # by reference: five new 60,664-string columns in five tables
  data.table::set(home$raw$tables[[k]], j = "extra", value = sprintf("extra_%s_%07d", k, seq_len(nrow(T0))))
}
key1 = ns$cf_key(ns$env_snap_leaf(home$raw))
b1 = classify("base"); c1 = classify("cache")
print(data.frame(when = c("before edit", "after by-reference edit"),
                 key_unchanged = c(NA, identical(key0, key1)),
                 base_bytes = c(b0[["bytes"]], b1[["bytes"]]), cache_bytes = c(c0[["bytes"]], c1[["bytes"]]),
                 base_level = c(b0[["level"]], b1[["level"]]), cache_level = c(c0[["level"]], c1[["level"]])))
setwd(W); unlink(work, recursive = TRUE)
