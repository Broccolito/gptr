.libPaths(c("/Users/wgu/Desktop/gptr/dev/.library", .libPaths()))
`%||%` = function(a, b) if (is.null(a)) b else a
d = jsonlite::fromJSON("/private/tmp/claude-501/-Users-wgu-Desktop-gptr/0e1ce390-ccb6-46f4-bcb0-3e36676bd924/scratchpad/simplicity/rename/prefix-baseline.HEAD.json", simplifyVector = FALSE)
f = function(x) rtiktoken::get_token_count(x, "o200k_base")
rn = function(x) {
  x = gsub("(?<![A-Za-z0-9_.$])gptr(?=[($\\[])", "peter", x, perl = TRUE)
  gsub("the gptr object", "the peter object", x, fixed = TRUE)
}
tot = 0
show = function(nm, x) if (is.character(x) && length(x) == 1 && grepl("gptr", x)) {
  a = f(x); b = f(rn(x)); cat(sprintf("%-45s %5d -> %5d (%+d)\n", nm, a, b, b - a))
}
for (k in names(d$expected$rendered)) show(paste0("rendered/", k), d$expected$rendered[[k]])
for (s in d$standins$sections) show(paste0("standin section ", s$name), s$text)
for (s in d$standins$fragments) show(paste0("standin fragment ", s$name %||% s$id %||% ""), s$text)
for (t in d$standins$tools) { show(paste0("standin tool ", t$name, " description"), t$description); for (g in t$guidelines) show(paste0("standin tool ", t$name, " guideline"), g) }
cat("\nchar-estimate (prose, chars/cpt) budgets check:\n")
for (k in names(d$expected$rendered)) { x = d$expected$rendered[[k]]; if (grepl("gptr", x)) cat(sprintf("%-30s chars %5d -> %5d (+%d)\n", k, nchar(x), nchar(rn(x)), nchar(rn(x)) - nchar(x))) }
for (s in d$standins$sections) if (grepl("gptr", s$text)) cat(sprintf("standin %-22s chars %5d -> %5d (+%d) budget %s\n", s$name, nchar(s$text), nchar(rn(s$text)), nchar(rn(s$text)) - nchar(s$text), s$budget %||% "?"))
