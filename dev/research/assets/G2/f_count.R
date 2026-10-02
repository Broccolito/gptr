# G2 (f) step 1: count o200k and cl100k tokens per chunk (up to 50 chunks per class; memoised).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
C = readRDS(file.path(G2, "f_corpus.rds"))
set.seed(5)
rows = list()
for (k in names(C)) {
  x = C[[k]]
  if (length(x) > 50) x = x[sort(sample(length(x), 50))]
  for (i in seq_along(x)) {
    rows[[length(rows) + 1]] = data.frame(class = k, i = i, text = x[i], chars = nchar(x[i], "chars"),
                                          o200k = tok_o200k(x[i]), cl100k = tok_cl100k(x[i]))
  }
  tok_save()
  cat(k, "done\n")
}
d = do.call(rbind, rows)
saveRDS(d, file.path(G2, "f_counts.rds"))
cat("chunks:", nrow(d), " chars:", sum(d$chars), "\n")
