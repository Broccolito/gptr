# Usage: Rscript --vanilla callers.R <rprof file> <function> [depth]
# Distribution of the call chains (nearest `depth` named callers) above <function> in Rprof samples
a = commandArgs(TRUE)
f = a[2]
depth = if (length(a) > 2) as.integer(a[3]) else 3L
lines = readLines(a[1])
hdr = lines[1]
iv = as.numeric(sub(".*sample.interval=([0-9]+).*", "\\1", hdr)) / 1e6
lines = lines[-1]
lines = lines[!grepl("^#", lines)]
skip = c("tryCatch", "tryCatchList", "tryCatchOne", "doTryCatch", "withCallingHandlers", "do.call",
         "eval", "FUN", "lapply", "vapply", "withVisible", "force", "identity", "local", "evalq",
         "suppressMessages", "withRestarts", "withOneRestart", "doWithOneRestart", "%||%", "isTRUE",
         "fn", "fun", "<Anonymous>", "Reduce", "Filter", "Map", "mapply", "sapply")
key = character()
for (ln in lines) {
  st = scan(text = ln, what = "", quiet = TRUE)
  k = match(f, st)
  if (is.na(k)) next
  up = st[-seq_len(k)]
  up = up[!up %in% skip]
  key = c(key, paste(head(up, depth), collapse = " < "))
}
cat(sprintf("%s: %d samples = %.3f s of %d samples (%.3f s)\n", f, length(key), length(key) * iv,
            length(lines), length(lines) * iv))
tb = sort(table(key), decreasing = TRUE)
print(head(data.frame(secs = as.numeric(tb) * iv, chain = names(tb)), 25), right = FALSE)
