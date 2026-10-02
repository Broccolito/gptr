args = commandArgs(TRUE)
dir = args[[1]]
cat("lintr", as.character(packageVersion("lintr")), "\n")
linters = lintr::linters_with_defaults(
  assignment_linter = lintr::assignment_linter(operator = c("=", "<<-")),
  line_length_linter = lintr::line_length_linter(100L),
  object_name_linter = lintr::object_name_linter(
    styles = "snake_case",
    regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$")
  ),
  object_usage_linter = NULL,
  indentation_linter = NULL
)
fs = list.files(dir, pattern = "\\.R$", full.names = TRUE)
res = parallel::mclapply(fs, function(f) {
  l = tryCatch(lintr::lint(f, linters = linters, parse_settings = FALSE), error = function(e) e)
  if (inherits(l, "error")) return(data.frame(file = basename(f), line = NA_integer_, linter = "ERROR",
                                              message = conditionMessage(l)))
  if (!length(l)) return(NULL)
  df = as.data.frame(l)
  data.frame(file = basename(f), line = df$line_number, linter = df$linter, message = df$message)
}, mc.cores = 8L)
out = do.call(rbind, res)
utils::write.csv(out, file.path(dir, "..", "lint_results.csv"), row.names = FALSE)
if (is.null(out)) { cat("no lints\n"); quit(save = "no") }
print(table(out$linter))
out$plan = substr(out$file, 1, 3)
print(table(out$plan, out$linter))
