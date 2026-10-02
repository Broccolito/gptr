# Independent re-check of G3 finding: rlang quosure capture in gptr() pins the wrapper frame.
steps = c(
  rlang_enquos = "g = function(...) { q = rlang::enquos(...); e = rlang::quo_get_expr(q[[2]]); env = rlang::quo_get_env(q[[2]]); k = class(get(as.character(e), envir = env)); invisible(NULL) }",
  base_dotelt_leaf = "leaf = function(x) class(x); g = function(...) { i = 1L; n = ...length(); k = NULL; while (i <= n) { if (i == 2L) k = leaf(...elt(i)); i = i + 1L }; invisible(NULL) }",
  base_substitute = "g = function(...) { ex = substitute(list(...)); k = class(..2); invisible(NULL) }")
run = function(def) {
  f = tempfile(fileext = ".R")
  writeLines(c(def, 'big = runif(5e6)', 'h = function(d) g("describe", d)', 'res = h(big)',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(steps)) cat(sprintf("%-18s -> %s\n", n, run(steps[[n]])))
