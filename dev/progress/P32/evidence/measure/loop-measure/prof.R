# Usage: Rscript --vanilla prof.R <rprof file> [n]
a = commandArgs(TRUE)
n = if (length(a) > 1) as.integer(a[2]) else 60L
x = utils::summaryRprof(a[1])
cat("sampling time", x$sampling.time, "s\n")
bt = x$by.total
bt = bt[!grepl("^\"(tryCatch|tryCatchList|tryCatchOne|doTryCatch|withCallingHandlers|do.call|eval|FUN|lapply|vapply|Reduce|Filter|withVisible|force|identity|local|evalq|suppressMessages|withRestarts|withOneRestart|doWithOneRestart)\"$", rownames(bt)), ]
print(head(bt, n))
cat("\nby.self:\n")
print(head(x$by.self, 30))
