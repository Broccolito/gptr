# Usage: Rscript --vanilla callees.R <rprof file> <function> [depth]
# Time below <function> split by the next `depth` named callees (inclusive), from Rprof samples
a = commandArgs(TRUE)
f = a[2]
depth = if (length(a) > 2) as.integer(a[3]) else 1L
lines = readLines(a[1])
iv = as.numeric(sub(".*sample.interval=([0-9]+).*", "\\1", lines[1])) / 1e6
lines = lines[-1]
lines = lines[!grepl("^#", lines)]
skip = c("tryCatch", "tryCatchList", "tryCatchOne", "doTryCatch", "withCallingHandlers", "do.call",
         "eval", "FUN", "lapply", "vapply", "withVisible", "force", "identity", "local", "evalq",
         "suppressMessages", "withRestarts", "withOneRestart", "doWithOneRestart", "%||%", "isTRUE",
         "fn", "fun", "<Anonymous>", "Reduce", "Filter", "Map", "mapply", "sapply", "suspendInterrupts",
         "tryCatchOne", "h", "f", "e", "unlist", "structure", "paste", "paste0", "c", "list")
key = character()
for (ln in lines) {
  st = scan(text = ln, what = "", quiet = TRUE)
  k = match(f, st)
  if (is.na(k)) next
  below = rev(st[seq_len(k - 1L)])
  below = below[!below %in% skip]
  key = c(key, if (length(below)) paste(head(below, depth), collapse = " > ") else "<self>")
}
cat(sprintf("%s: %.3f s inclusive (%d samples)\n", f, length(key) * iv, length(key)))
tb = sort(table(key), decreasing = TRUE)
print(head(data.frame(secs = as.numeric(tb) * iv, callee = names(tb)), 30), right = FALSE)
