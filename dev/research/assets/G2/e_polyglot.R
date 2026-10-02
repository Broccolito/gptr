# G2 (e): polyglot work through compact R helpers inside the r tool vs a bash tool.
# Every command below is executed; token counts are o200k of the tool-call arguments and of the result text.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
Sys.setenv(RETICULATE_PYTHON = Sys.which("python3"), RETICULATE_USE_MANAGED_VENV = "no")
proj = file.path(G2, "e_proj"); unlink(proj, recursive = TRUE); dir.create(file.path(proj, "data"), recursive = TRUE); dir.create(file.path(proj, "scripts"))
owd = setwd(proj)
source(file.path(G2, "a_apps/data.R"))
utils::write.csv(sales, "data/sales.csv", row.names = FALSE)
utils::write.csv(cars_df, "data/cars.csv", row.names = FALSE)
writeLines(c("#!/bin/sh", "set -e", "in=$1; out=$2", "mkdir -p \"$out\"", "for f in \"$in\"/*.csv; do", "  n=$(wc -l < \"$f\")", "  echo \"$(basename \"$f\"): $n lines\"", "  cp \"$f\" \"$out\"/", "done", "echo done"), "scripts/prep.sh")
Sys.chmod("scripts/prep.sh", "755")
git = function(...) system2("git", c("-c", "user.name=G2", "-c", "user.email=g2@example.invalid", ...), stdout = FALSE, stderr = FALSE)
git("init", "-q"); for (i in 1:6) { writeLines(sprintf("step %d", i), sprintf("notes%d.txt", i)); git("add", "."); git("commit", "-q", "-m", shQuote(sprintf("Add analysis step %d", i))) }
con = DBI::dbConnect(RSQLite::SQLite(), "data/sales.sqlite"); DBI::dbWriteTable(con, "sales", sales, overwrite = TRUE); DBI::dbDisconnect(con)

# ---- the proposed helpers (prototype; exported by gptr and documented in one system-prompt section) ----
sh = function(cmd, args = character(), wd = ".", timeout = 60) {
  r = processx::run(cmd, args, wd = wd, error_on_status = FALSE, timeout = timeout)
  structure(list(status = r$status, stdout = r$stdout, stderr = r$stderr), class = "gptr_sh")
}
print.gptr_sh = function(x, ...) {
  cat(x$stdout)
  if (nzchar(x$stderr)) cat("[stderr] ", x$stderr, sep = "")
  if (!identical(x$status, 0L)) cat(sprintf("[exit status %d]\n", x$status))
  invisible(x)
}
py = function(code, ...) {                      # R objects passed by name; returns the value of `result` if set
  m = reticulate::import_main(convert = TRUE)
  args = list(...)
  for (nm in names(args)) m[[nm]] = args[[nm]]
  reticulate::py_run_string(code, convert = TRUE)
  if (reticulate::py_has_attr(m, "result")) m$result else invisible(NULL)
}
.sql_con = new.env()
sql = function(query, con = NULL) {
  if (is.null(con)) {
    if (is.null(.sql_con$duck)) .sql_con$duck = DBI::dbConnect(duckdb::duckdb())
    con = .sql_con$duck
  }
  DBI::dbGetQuery(con, query)
}
eng = function(engine, code) {                  # a knitr language engine, output only
  o = knitr::opts_chunk$merge(list(engine = engine, code = code, echo = FALSE, eval = TRUE, results = "markup", comment = NA))
  out = knitr::knit_engines$get(engine)(o)
  cat(gsub("```[a-z]*\n?", "", out), "\n")
  invisible(out)
}
helpers_doc = "<r_helpers>\nPolyglot work goes through R (no bash tool): sh(cmd, args) runs a program without assuming a shell and returns status/stdout/stderr; py(code, ...) runs Python via reticulate with R objects passed by name (set `result` to return a value); sql(query, con) runs SQL through DBI (default: in-memory duckdb, which reads CSV/Parquet paths directly); eng(engine, code) runs a knitr language engine.\n</r_helpers>"

cap = function(code) {
  res = NULL
  out = utils::capture.output({ res = withVisible(eval(parse(text = code), envir = globalenv())) })
  if (res$visible) out = c(out, utils::capture.output(print(res$value)))
  paste(out, collapse = "\n")
}
bash = function(cmd) paste(suppressWarnings(system2("bash", c("-c", shQuote(cmd)), stdout = TRUE, stderr = TRUE)), collapse = "\n")
tasks = list(
  list(name = "shell command: line counts of data files", bash = "wc -l data/*.csv",
       r = "sapply(Sys.glob(\"data/*.csv\"), \\(f) length(readLines(f)))"),
  list(name = "shell script with arguments", bash = "scripts/prep.sh data out",
       r = "sh(\"scripts/prep.sh\", c(\"data\", \"out\"))"),
  list(name = "git: last 5 commits", bash = "git log -5 --oneline",
       r = "sh(\"git\", c(\"log\", \"-5\", \"--oneline\"))"),
  list(name = "Python on an in-memory R object", bash = "python3 -c \"import csv, statistics; r = [float(x['revenue']) for x in csv.DictReader(open('data/sales.csv'))]; print(round(statistics.pstdev(r), 2), round(statistics.median(r), 2))\"",
       r = "py(\"import statistics\\nresult = [round(statistics.pstdev(x), 2), round(statistics.median(x), 2)]\", x = sales$revenue)"),
  list(name = "SQL on SQLite", bash = "sqlite3 -header -column data/sales.sqlite \"SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC\"",
       r = "sql(\"SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC\", DBI::dbConnect(RSQLite::SQLite(), \"data/sales.sqlite\"))"),
  list(name = "SQL on a CSV file (duckdb)", bash = NA_character_,
       r = "sql(\"SELECT month, AVG(price) AS avg_price FROM 'data/sales.csv' GROUP BY month ORDER BY avg_price DESC LIMIT 3\")"),
  list(name = "knitr engine chunk (bash)", bash = "for f in data/*.csv; do echo \"$f $(head -1 $f | tr ',' '\\n' | wc -l)\"; done",
       r = "eng(\"bash\", \"for f in data/*.csv; do echo \\\"$f $(head -1 $f | tr ',' '\\\\n' | wc -l)\\\"; done\")"))
rows = list()
for (tk in tasks) {
  r_out = cap(tk$r)
  b_out = if (is.na(tk$bash)) NA_character_ else bash(tk$bash)
  rows[[length(rows) + 1]] = data.frame(task = tk$name,
    bash_call = if (is.na(tk$bash)) NA else tok_o200k(j(list(command = tk$bash))), bash_result = if (is.na(tk$bash)) NA else tok_o200k(b_out),
    r_call = tok_o200k(j(list(code = tk$r))), r_result = tok_o200k(r_out))
  cat(sprintf("\n## %s\n$ %s\n%s\n> %s\n%s\n", tk$name, tk$bash, if (is.na(b_out)) "(no duckdb CLI installed; n/a)" else b_out, tk$r, r_out))
}
d = do.call(rbind, rows)
cat("\nTokens (o200k): tool-call arguments and result text per task\n"); print(d, row.names = FALSE)
cat(sprintf("\nSums over the tasks both can run: bash %d call + %d result; r %d call + %d result\n",
            sum(d$bash_call, na.rm = TRUE), sum(d$bash_result, na.rm = TRUE), sum(d$r_call[!is.na(d$bash_call)]), sum(d$r_result[!is.na(d$bash_call)])))
bash_def = tok_o200k(j(list(name = "bash", description = pi_tools$bash$description, input_schema = pi_tools$bash$parameters)))
cat(sprintf("Fixed prefix cost: bash tool declaration %d tokens (Pi's schema; Anthropic's own bash tool adds 325) vs <r_helpers> section %d tokens\n",
            bash_def, tok_o200k(helpers_doc)))

# ---- a composed polyglot pipeline: git -> SQL -> Python -> summary, one r call vs four bash calls ----
pipe_r = paste("log = sh(\"git\", c(\"log\", \"--format=%s\"))$stdout |> strsplit(\"\\n\") |> unlist()",
               "rev = sql(\"SELECT region, SUM(revenue) AS rev FROM 'data/sales.csv' GROUP BY region\")",
               "sdev = py(\"import statistics\\nresult = statistics.pstdev(x)\", x = rev$rev)",
               "list(commits = length(log), top_region = rev$region[which.max(rev$rev)], sd_between_regions = round(sdev, 1))", sep = "\n")
pipe_r_out = cap(pipe_r)
pipe_bash = c("git log --format=%s | wc -l",
              "sqlite3 -header -csv data/sales.sqlite \"SELECT region, SUM(revenue) AS rev FROM sales GROUP BY region\" > out/rev.csv && cat out/rev.csv",
              "python3 -c \"import csv, statistics; r=[float(x['rev']) for x in csv.DictReader(open('out/rev.csv'))]; print(statistics.pstdev(r))\"",
              "sort -t, -k2 -nr out/rev.csv | head -1")
pb = vapply(pipe_bash, bash, "")
cat("\n## composed pipeline in one r call\n", pipe_r, "\n", pipe_r_out, "\n", sep = "")
cat("\n## the same with four bash calls\n"); for (i in seq_along(pipe_bash)) cat("$ ", pipe_bash[i], "\n", pb[i], "\n", sep = "")
cat(sprintf("\nPipeline: r = 1 call, %d call + %d result tokens; bash = 4 calls, %d call + %d result tokens (and the results are text, not R objects)\n",
            tok_o200k(j(list(code = pipe_r))), tok_o200k(pipe_r_out), sum(vapply(pipe_bash, function(x) tok_o200k(j(list(command = x))), 1)), sum(vapply(pb, tok_o200k, 1))))
setwd(owd)
tok_save()
