# Compare checkpoint fragment rows and rewind previews of each variant with base (same code, rep)
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/counterfactual"
options(width = 220)
tag = commandArgs(TRUE)[1]
key_rows = function(d, cols) {
  if (!nrow(d)) return(character())
  sort(do.call(paste, c(d[, cols, drop = FALSE], sep = " | ")))
}
for (what in c("ckpt-records", "rewind-preview")) {
  d = read.csv(file.path(W, "out", paste0(what, "-", tag, ".csv")), stringsAsFactors = FALSE)
  cols = if (what == "ckpt-records") c("checkpointer", "name", "status", "how", "class", "bytes", "restorable", "reason") else
    intersect(c("action", "checkpointer", "item", "restore", "reason"), names(d))
  cat("\n=====", what, "=====\n")
  for (code in unique(d$code)) for (rep in unique(d$rep)) {
    b = key_rows(d[d$variant == "base" & d$code == code & d$rep == rep, ], cols)
    for (v in setdiff(unique(d$variant), "base")) {
      x = key_rows(d[d$variant == v & d$code == code & d$rep == rep, ], cols)
      same = identical(b, x)
      cat(sprintf("%-6s %-3s rep %d: %s vs base: %s\n", code, v, rep, if (same) "identical" else "DIFFERENT",
                  if (same) "" else paste0("only base: [", paste(setdiff(b, x), collapse = "; "), "]  only ", v, ": [",
                                           paste(setdiff(x, b), collapse = "; "), "]")))
    }
  }
}
