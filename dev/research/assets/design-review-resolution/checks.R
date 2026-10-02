# 1. processx env NA
r1 = tryCatch({p = processx::process$new("/usr/bin/env", env = c("current", X = NA), stdout = "|"); p$wait(); "ok"}, error = function(e) conditionMessage(e))
cat("processx NA env:", r1, "\n")
# 2. supervise = NULL
r2 = tryCatch({p = processx::process$new("/bin/echo", "x", supervise = NULL); p$wait(); "ok"}, error = function(e) conditionMessage(e))
cat("supervise NULL:", r2, "\n")
# 3. httpuv randomPort and seed
if (requireNamespace("httpuv", quietly = TRUE)) {
  set.seed(1); a = .Random.seed; invisible(httpuv::randomPort()); cat("randomPort changes seed:", !identical(a, .Random.seed), "\n")
}
# 4. weakref for last
s = local({e = new.env(); e})
the = new.env()
the$last = rlang::new_weakref(key = s)
rm(s); invisible(gc())
cat("weakref key after gc:", !is.null(rlang::wref_key(the$last)), "\n")
# 5. curl default followlocation
h = curl::new_handle(); cat("curl handle_data present; default followlocation option set in curl::new_handle? ", "\n")
# 6. file connection limit quickly
cons = list(); n = 0
res = tryCatch({for (i in 1:200) { cons[[i]] = file(tempfile(), "ab"); n = i }; "no limit"}, error = function(e) conditionMessage(e))
cat("connections opened:", n, res, "\n")
for (cc in cons) try(close(cc), silent = TRUE)
