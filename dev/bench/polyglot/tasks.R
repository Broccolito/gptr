# The eight polyglot tasks of G5 p10_tokens.R and their measurement (plan P24; architecture 12.3
# and 12.7), rebuilt offline and deterministically: a local file:// download, arithmetic data
# instead of RNG, a generated tree instead of the Pi clone, grep instead of rg, git with fixed
# identity and dates. Variants:
#   A = a bash tool with Pi semantics (reference only, not gated)
#   B = the r tool calling the same command through peter$sh / $script / $py / $sql (contract 9.4)
#   C = the r tool composing those helpers with R and printing only what is needed

polyglot_programs = function() {
  p = Sys.which(c("git", "sh", "grep", "python3", "sqlite3", "curl", "make", "bash"))
  stats::setNames(nzchar(p), names(p))
}

polyglot_git = function(repo, ...) {
  # An empty global config file instead of /dev/null, which git for Windows cannot open.
  empty = file.path(tempdir(), "p24-empty-gitconfig")
  if (!file.exists(empty)) file.create(empty)
  env = c("current", GIT_AUTHOR_NAME = "p24", GIT_AUTHOR_EMAIL = "p24@example.org",
          GIT_COMMITTER_NAME = "p24", GIT_COMMITTER_EMAIL = "p24@example.org",
          GIT_AUTHOR_DATE = "2026-09-01T00:00:00Z", GIT_COMMITTER_DATE = "2026-09-01T00:00:00Z",
          GIT_CONFIG_NOSYSTEM = "1", GIT_CONFIG_GLOBAL = empty)
  invisible(processx::run("git", c("-C", repo, ...), env = env))
}

# Builds every fixture under `dir` and returns the paths the tasks need.
polyglot_fixture = function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  repo = file.path(dir, "repo")
  dir.create(repo, showWarnings = FALSE)
  for (k in 1:12) {
    i = 1:120
    body = sprintf(paste("export function tool_%02d_%03d(input: string): string {",
                         "return input.slice(%d); }"), k, i, i)
    writeLines(body, file.path(repo, sprintf("tool%02d.ts", k)))
  }
  if (polyglot_programs()[["git"]]) {
    polyglot_git(repo, "init", "-q")
    polyglot_git(repo, "add", ".")
    polyglot_git(repo, "commit", "-q", "-m", "init")
    for (k in c(1L, 2L, 3L)) {
      f = file.path(repo, sprintf("tool%02d.ts", k))
      x = readLines(f)
      at = round(seq(5, length(x) - 5, length.out = c(12L, 8L, 6L)[[k]]))
      x[at] = paste0(x[at], " // reviewed")
      writeLines(x, f)
    }
    writeLines("export const x = 1;", file.path(repo, "new-tool.ts"))
    writeLines("notes", file.path(repo, "NOTES.md"))
    invisible(file.remove(file.path(repo, "tool12.ts")))
  }
  writeLines(c("#!/bin/sh", "echo '== configure'",
               paste("i=1; while [ $i -le 400 ]; do echo",
                     "\"[step $i/400] processing chunk_$i.parquet ... ok ($((i*3)) rows/s)\";",
                     "i=$((i+1)); done"),
               "echo 'WARNING: 3 chunks had missing timestamps' 1>&2",
               "echo '== done: 400 chunks, 1,203,300 rows, output in out/'"),
             file.path(dir, "build.sh"))
  n = 5000L
  i = seq_len(n)
  sales = data.frame(region = rep_len(c("north", "south", "east", "west"), n),
                     month = (i * 7L) %% 12L + 1L, revenue = round(((i * 37L) %% 1000L) / 3.7, 2))
  utils::write.csv(sales, file.path(dir, "sales.csv"), row.names = FALSE)
  j = seq_len(20000L)
  orders = data.frame(id = j, region = rep_len(c("north", "south", "east", "west"), 20000L),
                      customer = sprintf("C%05d", (j * 13L) %% 3000L + 1L),
                      amount = round(exp(4 + ((j * 29L) %% 1000L) / 400), 2))
  shop_db = file.path(dir, "shop.sqlite")
  if (requireNamespace("RSQLite", quietly = TRUE) && requireNamespace("DBI", quietly = TRUE)) {
    withr::local_preserve_seed() # dbWriteTable() draws random numbers
    con = DBI::dbConnect(RSQLite::SQLite(), shop_db)
    DBI::dbWriteTable(con, "orders", orders, overwrite = TRUE)
    DBI::dbDisconnect(con)
  }
  writeLines(c("all:",
               paste0("\t@for i in $$(seq 1 300); do echo \"cc -O2 -Wall -Iinclude -c ",
                      "src/module_$$i.c -o build/module_$$i.o\"; done"),
               paste0("\t@echo \"src/module_17.c:42:9: warning: unused variable 'tmp' ",
                      "[-Wunused-variable]\" 1>&2"),
               paste0("\t@echo \"src/module_211.c:88:3: warning: implicit conversion loses ",
                      "precision [-Wshorten-64-to-32]\" 1>&2"),
               "\t@echo \"ld -o build/app build/*.o\"",
               "\t@echo \"built build/app (300 objects)\""),
             file.path(dir, "Makefile"))
  writeLines(c("import time", "for i in range(1, 241):",
               paste0("    print(f'[{i:3d}/240] epoch {i // 20 + 1} batch {i % 20:2d} ",
                      "loss={2.0 / (1 + i / 40):.4f} lr=3e-4', flush=True)"),
               "    time.sleep(0.005)",
               "print('DONE best_loss=0.2857 checkpoint=ckpt/best.pt', flush=True)"),
             file.path(dir, "long.py"))
  src = file.path(dir, "src")
  dir.create(src, showWarnings = FALSE)
  for (k in 1:40) {
    i = 1:80
    txt = ifelse(i %% ((k %% 7L) + 3L) == 0L,
                 sprintf("  if (signal.aborted) return; // module %d line %d", k, i),
                 sprintf("  const value_%d = compute(%d, %d);", i, k, i))
    writeLines(c(sprintf("// module %d", k), txt), file.path(src, sprintf("module%02d.ts", k)))
  }
  m = 234L
  q = seq_len(m)
  mpg = data.frame(manufacturer = rep_len(c("audi", "chevrolet", "dodge", "ford", "honda"), m),
                   model = sprintf("m%03d", q), displ = round(1.6 + (q %% 50L) / 10, 1),
                   year = ifelse(q %% 2L == 0L, 1999L, 2008L), cyl = rep_len(c(4L, 6L, 8L), m),
                   trans = rep_len(c("auto(l5)", "manual(m5)"), m),
                   drv = rep_len(c("f", "4", "r"), m),
                   cty = 9L + q %% 20L, hwy = 12L + q %% 30L, fl = rep_len(c("p", "r", "e"), m),
                   class = rep_len(c("compact", "midsize", "suv", "pickup"), m))
  mpg_path = file.path(dir, "mpg.csv")
  utils::write.csv(mpg, mpg_path, row.names = FALSE)
  list(dir = dir, repo = repo, shop_db = shop_db, sales = sales,
       mpg_url = paste0("file://", normalizePath(mpg_path, winslash = "/")), mpg_path = mpg_path)
}

# The tasks: wd, the programs they need, and the calls of each variant.
polyglot_tasks = function(fx) {
  q = function(...) paste(c(...), collapse = "\n")
  list(
    T1_git = list(wd = fx$repo, needs = "git",
      A = list("git status && git diff"),
      B = list('peter$sh("git status && git diff")'),
      C = list(q('st = strsplit(peter$sh(c("git", "status", "--porcelain"))$stdout, "\\n")[[1]]',
                 "table(substr(st, 1, 2))", 'peter$sh(c("git", "diff", "--numstat"))',
                 'peter$sh(c("git", "diff", "-U1"), max_tokens = 1000)'))),
    T2_script = list(wd = fx$dir, needs = "sh",
      A = list("sh build.sh"),
      B = list('peter$script("build.sh")'),
      C = list(q('b = peter$script("build.sh")', "b$stderr", 'out = strsplit(b$stdout, "\\n")[[1]]',
                 "tail(out, 2)", "length(out)"))),
    T3_grep = list(wd = fx$dir, needs = "grep",
      A = list("grep -rn signal src"),
      B = list('peter$sh("grep -rn signal src")'),
      C = list(q('m = strsplit(peter$sh(c("grep", "-rn", "signal", "src"))$stdout, "\\n")[[1]]',
                 'hits = table(sub(":.*", "", m))',
                 "length(m); head(sort(hits, decreasing = TRUE), 8)"))),
    T4_python = list(wd = fx$dir, needs = "python3", r_pkgs = "reticulate",
      A = list(q("python3 - <<'EOF'", "import pandas as pd", "sales = pd.read_csv('sales.csv')",
                 "print(sales.groupby(['region','month']).revenue.sum().unstack().round(0))",
                 "EOF")),
      B = list(paste0('peter$py("import pandas as pd\\nsales = pd.read_csv(\'sales.csv\')\\n',
                      "sales.groupby(['region','month']).revenue.sum().unstack().round(0)\")")),
      C = list(q(paste0('tab = peter$py("sales.groupby([\'region\',\'month\']).revenue.sum()',
                        '.unstack().round(0)", name = sales)$value'),
                 "range(as.matrix(tab))"))),
    T5_sql = list(wd = fx$dir, needs = "sqlite3", r_pkgs = c("DBI", "RSQLite"),
      A = list(paste("sqlite3 -header -column shop.sqlite '.schema orders'",
                     "'SELECT * FROM orders LIMIT 5'"),
               "sqlite3 -header -column shop.sqlite 'SELECT * FROM orders WHERE amount > 400'",
               paste("sqlite3 -header -column shop.sqlite 'SELECT region, COUNT(*) n,",
                     "ROUND(AVG(amount),2) avg FROM orders GROUP BY region ORDER BY n DESC'")),
      B = list('peter$sql("SELECT * FROM orders LIMIT 5", con = shop)',
               'peter$sql("SELECT * FROM orders WHERE amount > 400", con = shop)',
               paste0('peter$sql("SELECT region, COUNT(*) n, ROUND(AVG(amount),2) avg FROM orders ',
                      'GROUP BY region ORDER BY n DESC", con = shop)')),
      C = list(q('big = peter$sql("SELECT * FROM orders WHERE amount > 400", con = shop)',
                 "dim(big); summary(big$amount)",
                 paste0('peter$sql("SELECT region, COUNT(*) n, ROUND(AVG(amount),2) avg ',
                        'FROM orders GROUP BY region ORDER BY n DESC", con = shop)')))),
    T6_download = list(wd = fx$dir, needs = "curl",
      A = list(sprintf("curl -sSL -o mpg2.csv %s && head -5 mpg2.csv && wc -l mpg2.csv",
                       fx$mpg_url)),
      B = list(sprintf('peter$sh("curl -sSL -o mpg2.csv %s && head -5 mpg2.csv && wc -l mpg2.csv")',
                       fx$mpg_url)),
      C = list(q(sprintf('mpg = read.csv("%s")', fx$mpg_path), "dim(mpg); head(mpg, 3)"))),
    T7_make = list(wd = fx$dir, needs = "make",
      A = list("make"),
      B = list('peter$sh("make")'),
      C = list(q('b = peter$sh("make")', "b$status; b$stderr",
                 'tail(strsplit(b$stdout, "\\n")[[1]], 2)'))),
    T8_long = list(wd = fx$dir, needs = "python3",
      A = list("python3 long.py"),
      B = list('peter$sh("python3 long.py")'),
      C = list(q('j = peter$bg(c("python3", "long.py"))',
                 'invisible(j$wait(timeout = 60, until = "DONE"))', "tail(j$read(), 2)"))))
}

# A bash tool with Pi semantics (report 01 section 3.5): bash -c, stdout and stderr merged,
# tail truncation to 2,000 lines or 50 KB with Pi's notice, "Command exited with code N".
polyglot_pi_bash = function(command, wd) {
  f = tempfile("pi-bash-", fileext = ".log")
  r = processx::run("bash", c("-c", command), wd = wd, stdout = f, stderr = "2>&1",
                    error_on_status = FALSE)
  lines = readLines(f, warn = FALSE)
  out = paste(lines, collapse = "\n")
  total = length(lines)
  if (total > 2000L || file.size(f) > 51200) {
    keep = character()
    bytes = 0
    for (l in rev(lines)) {
      b = nchar(l, "bytes") + 1
      if (length(keep) >= 2000L || bytes + b > 51200) break
      keep = c(l, keep)
      bytes = bytes + b
    }
    s = total - length(keep) + 1L
    notice = "[Showing lines %d-%d of %d%s. Full output: /tmp/pi-bash-0123456789abcdef.log]"
    out = sprintf(paste0("%s\n\n", notice), paste(keep, collapse = "\n"), s, total, total,
                  if (length(keep) < 2000L) " (50.0KB limit)" else "")
  }
  if (!nzchar(out)) out = "(no output)"
  if (!identical(r$status, 0L)) out = paste0(out, "\n\nCommand exited with code ", r$status)
  list(args = as.character(jsonlite::toJSON(list(command = command), auto_unbox = TRUE)),
       result = out)
}

# The r tool path of gptr: eval_r() + format_eval_result() in the workspace environment. A call
# that does not finish ok is not measured (its variant becomes unavailable).
polyglot_r_tool = function(code, wd, envir) {
  old = setwd(wd)
  on.exit(setwd(old), add = TRUE)
  res = eval_r(code, envir = envir, plots = "none", tee = FALSE)
  txt = format_eval_result(res, gptr_opt("r_output_tokens"))$text
  if (!identical(res$status, "ok")) stop(res$status, ": ", txt, call. = FALSE)
  list(args = json_encode(list(code = code)), result = txt)
}

# Every task and variant on gptr's loaded source tree; `count` gives the o200k tokens of texts.
polyglot_run = function(count) {
  have = polyglot_programs()
  fx = polyglot_fixture(file.path(tempdir(), "polyglot"))
  work_env = new.env(parent = globalenv())
  work_env$sales = fx$sales
  if (file.exists(fx$shop_db)) work_env$shop = DBI::dbConnect(RSQLite::SQLite(), fx$shop_db)
  on.exit(if (!is.null(work_env$shop)) DBI::dbDisconnect(work_env$shop), add = TRUE)
  rows = list()
  tasks = polyglot_tasks(fx)
  for (tn in names(tasks)) {
    t = tasks[[tn]]
    pkgs_ok = all(vapply(t$r_pkgs, requireNamespace, NA, quietly = TRUE))
    for (v in c("A", "B", "C")) {
      avail = isTRUE(have[[t$needs]]) && pkgs_ok && (v != "A" || isTRUE(have[["bash"]]))
      calls = if (!avail) list() else tryCatch(lapply(t[[v]], function(x) {
        if (v == "A") polyglot_pi_bash(x, t$wd) else polyglot_r_tool(x, t$wd, work_env)
      }), error = function(e) {
        message("[bench] ", tn, " ", v, ": ", conditionMessage(e))
        NULL
      })
      ok = avail && !is.null(calls)
      call_tok = if (ok) sum(count(vapply(calls, function(k) k$args, ""))) else NA_real_
      result_tok = if (ok) sum(count(vapply(calls, function(k) k$result, ""))) else NA_real_
      rows[[length(rows) + 1L]] = data.frame(task = tn, variant = v, calls = length(t[[v]]),
                                             call_tok = call_tok, result_tok = result_tok,
                                             total = call_tok + result_tok, available = ok,
                                             stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}
