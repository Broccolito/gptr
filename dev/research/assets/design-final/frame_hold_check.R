# Does holding a function frame as (a) a weakref key, (b) an address string, (c) an env binding reset to NULL
# make the caller's argument sticky after the function returns?
steps = c(
  weakref_key = "reg = new.env(); h = function(d) { force(d); reg$w = rlang::new_weakref(key = environment()); invisible(NULL) }",
  address_string = "reg = new.env(); h = function(d) { force(d); reg$a = rlang::obj_address(environment()); invisible(NULL) }",
  env_binding_reset = "reg = new.env(); h = function(d) { force(d); reg$e = environment(); reg$e = NULL; invisible(NULL) }",
  list_then_drop = "reg = new.env(); h = function(d) { force(d); reg$l = list(environment()); reg$l = NULL; invisible(NULL) }")
run = function(def) {
  f = tempfile(fileext = ".R")
  writeLines(c(def, 'big = runif(5e6)', 'res = h(big)', 'invisible(gc())',
    'invisible(tracemem(big))', 'big[1] = 0', 'cat("END\\n")'), f)
  out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE)
  if (!any(out == "END")) return(paste("ERROR", tail(out, 1)))
  if (any(grepl("^tracemem", out))) "COPY" else "in place"
}
for (n in names(steps)) cat(sprintf("%-18s -> %s\n", n, run(steps[[n]])))
