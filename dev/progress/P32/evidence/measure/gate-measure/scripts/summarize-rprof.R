# summaryRprof() of one or more Rprof files: top 15 by total (wrapper frames that span the whole
# call, and generic evaluation frames, dropped) and top 15 by self time
args = commandArgs(TRUE)
top = as.integer(Sys.getenv("TOP", "15"))
generic = c("<Anonymous>", "tryCatch", "tryCatchList", "tryCatchOne", "doTryCatch", "eval", "lapply",
            "FUN", "fn", "fun", "force", "withCallingHandlers", "do.call", "suppressWarnings",
            "withVisible", "Reduce", "vapply", "sapply", "mapply", "ctx_with_source", "checked")
for (f in args) {
  s = utils::summaryRprof(f)
  cat("==", basename(f), " sampling.time =", s$sampling.time, "s\n")
  bt = s$by.total
  bt = bt[bt$total.pct < 99.5 & !rownames(bt) %in% sprintf('"%s"', generic), ]
  cat("-- by.total (whole-call wrappers and generic frames dropped)\n"); print(utils::head(bt, top))
  cat("-- by.self\n"); print(utils::head(s$by.self, top))
}
