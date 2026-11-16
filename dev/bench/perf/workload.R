# The P32 hot-path workloads (plan P32 T1): the investigation's what-if scripts in one file
# (dev/progress/P32/evidence/measure: counterfactual workload, gate, create and loop, the critic's
# valley and cliscan, cli-transport's fake codex and driver), with a table count n. run.R starts
# each repetition from the repository root as
#   Rscript --vanilla dev/bench/perf/workload.R <gate> <library> <n> <result.rds> [full]
# which loads the gptr build installed in <library>, runs the gate's workload and saves a named
# vector of counts and seconds. The codex of the CLI route is this file too:
#   Rscript --vanilla dev/bench/perf/workload.R fake-codex <codex argv>
# Sourced, it only defines functions.

perf_clock = function() proc.time()[["elapsed"]]

# ---- T03's workspace and inputs ---------------------------------------------------------------

# The GDC STAR counts table of T03 (60,664 rows: 4 STAR summary rows, then 60,660 genes; 9
# columns), synthetic as the investigation's template.
perf_t03_template = function() {
  withr::local_seed(1L)
  g = 60660L
  ids = sprintf("ENSG%011d.%d", sort(sample.int(9e5, g)) + 1e4, sample(1:20, g, TRUE))
  nm = sprintf("GN%s%05d", sample(LETTERS, g, TRUE),
               c(seq_len(59400L), sample.int(59400L, g - 59400L)))
  ty = sample(sprintf("type_%02d_%s", 1:40, strrep("x", 1:40 %% 12)), g, TRUE)
  cnt = function() as.integer(rpois(g, 5) * rbinom(g, 1, 0.6) * sample(c(1, 10, 100), g, TRUE))
  u = cnt()
  s1 = cnt()
  s2 = cnt()
  tpm = round(u / sum(u) * 1e6, 4)
  na = rep(NA_real_, 4L)
  data.table::data.table(
    gene_id = c("N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous", ids),
    gene_name = c(rep("", 4L), nm), gene_type = c(rep("", 4L), ty),
    unstranded = c(2397451L, 3190112L, 1840345L, 891234L, u), stranded_first = c(rep(1L, 4L), s1),
    stranded_second = c(rep(2L, 4L), s2), tpm_unstranded = c(na, tpm),
    fpkm_unstranded = c(na, round(tpm / 3.1, 4)), fpkm_uq_unstranded = c(na, round(tpm / 2.7, 4)))
}

# One table as fread() gives it: fresh character vectors (their strings shared through R's string
# cache) and, to save memory, the template's numeric columns, which every table shares.
perf_t03_table = function(tpl) {
  l = as.list(tpl)
  chr = vapply(l, is.character, NA)
  l[chr] = lapply(l[chr], data.table::copy)
  data.table::setDT(l)
  l
}

perf_t03_files = function(n) {
  sprintf("TCGA-BRCA/%08d-%04d.rna_seq.augmented_star_gene_counts.tsv", seq_len(n) * 7919L,
          seq_len(n))
}

# `raw` as T03's first request leaves it
perf_t03_raw = function(n, tpl = perf_t03_template()) {
  files = perf_t03_files(n)
  list(files = files, tables = stats::setNames(lapply(files, function(f) perf_t03_table(tpl)),
                                               files))
}

# nolint start: line_length_linter.
# T03's three request inputs, verbatim (gptr-bench biomedical v0.5,
# reports/T03/mcp-replay-analysis/evidence/calls.json).
perf_t03_inputs = c(
r"---(data.table::setDTthreads(1)
if (!exists("raw", inherits = FALSE)) {
  files = base::readLines("input-files.txt")
  stopifnot(length(files) == 1231L)
  tables = lapply(files, function(filename) data.table::fread(file = filename, skip = "gene_id", header = TRUE, showProgress = FALSE))
  raw = list(files = files, tables = setNames(tables, files))
  rm(tables)
}
stopifnot(length(raw$files) == 1231L, length(raw$tables) == 1231L, identical(names(raw$tables), raw$files))
reference_gene_ids = raw$tables[[1L]]$gene_id
gene_rows = startsWith(reference_gene_ids, "ENSG")
stopifnot(length(reference_gene_ids) == 60664L, sum(gene_rows) == 60660L, identical(which(!gene_rows), 1:4))
total_gene_counts = 0
zero_gene_values = 0
for (i in seq_along(raw$tables)) {
  tab = raw$tables[[i]]
  stopifnot(nrow(tab) == 60664L, ncol(tab) == 9L, identical(tab$gene_id, reference_gene_ids))
  counts = tab$unstranded[gene_rows]
  stopifnot(is.numeric(counts), length(counts) == 60660L, all(is.finite(counts)), all(counts >= 0), all(counts == floor(counts)))
  total_gene_counts = total_gene_counts + sum(counts)
  zero_gene_values = zero_gene_values + sum(counts == 0)
}
input_audit = data.frame(n_files = length(raw$files), rows_per_file = 60664L, columns_per_file = 9L, genes_per_file = sum(gene_rows), total_gene_counts = total_gene_counts, zero_gene_values = zero_gene_values)
data.table::fwrite(input_audit, file = "input-audit.csv", row.names = FALSE)
print(input_audit)
print(list(all_dimensions_valid = TRUE, identical_gene_id_order = TRUE, all_gene_counts_finite_nonnegative_integer = TRUE))
rm(tab, counts, i))---",
r"---(data.table::setDTthreads(1)
if (!exists("raw", inherits = FALSE)) {
  files = base::readLines("input-files.txt")
  stopifnot(length(files) == 1231L)
  tables = lapply(files, function(filename) data.table::fread(file = filename, skip = "gene_id", header = TRUE, showProgress = FALSE))
  raw = list(files = files, tables = setNames(tables, files))
  rm(tables)
}
stopifnot(length(raw$files) == 1231L, length(raw$tables) == 1231L, identical(names(raw$tables), raw$files))
sample_summary = data.table::rbindlist(lapply(seq_along(raw$tables), function(i) {
  tab = raw$tables[[i]]
  stopifnot(nrow(tab) == 60664L, ncol(tab) == 9L, identical(tab$gene_id, raw$tables[[1L]]$gene_id))
  counts = tab$unstranded[startsWith(tab$gene_id, "ENSG")]
  stopifnot(length(counts) == 60660L, is.numeric(counts), all(is.finite(counts)), all(counts >= 0), all(counts == floor(counts)))
  data.table::data.table(file = raw$files[[i]], total_counts = sum(counts), detected_genes = sum(counts > 0), zero_genes = sum(counts == 0), mean_count = mean(counts), max_count = max(counts))
}))
data.table::setorder(sample_summary, file)
stopifnot(nrow(sample_summary) == 1231L, all(sample_summary$detected_genes + sample_summary$zero_genes == 60660L), identical(sample_summary$file, sort(raw$files)))
data.table::fwrite(sample_summary, file = "sample-summary.csv", row.names = FALSE)
print(list(output = "sample-summary.csv", dimensions = dim(sample_summary), total_counts = sum(sample_summary$total_counts), zero_gene_values = sum(sample_summary$zero_genes), sorted_by_file = TRUE, complete_raw_tables_retained = length(raw$tables))))---",
r"---(data.table::setDTthreads(1)
if (!exists("raw", inherits = FALSE)) {
  files = base::readLines("input-files.txt")
  stopifnot(length(files) == 1231L)
  tables = lapply(files, function(filename) data.table::fread(file = filename, skip = "gene_id", header = TRUE, showProgress = FALSE))
  raw = list(files = files, tables = setNames(tables, files))
  rm(tables)
}
stopifnot(length(raw$files) == 1231L, length(raw$tables) == 1231L, identical(names(raw$tables), raw$files))
reference_gene_ids = raw$tables[[1L]]$gene_id
gene_rows = startsWith(reference_gene_ids, "ENSG")
stopifnot(length(reference_gene_ids) == 60664L, sum(gene_rows) == 60660L, identical(which(!gene_rows), 1:4))
gene_totals = numeric(sum(gene_rows))
gene_detected_files = integer(sum(gene_rows))
gene_max_counts = numeric(sum(gene_rows))
for (i in seq_along(raw$tables)) {
  tab = raw$tables[[i]]
  stopifnot(nrow(tab) == 60664L, ncol(tab) == 9L, identical(tab$gene_id, reference_gene_ids))
  counts = tab$unstranded[gene_rows]
  stopifnot(is.numeric(counts), all(is.finite(counts)), all(counts >= 0), all(counts == floor(counts)))
  gene_totals = gene_totals + counts
  gene_detected_files = gene_detected_files + (counts > 0)
  gene_max_counts = pmax(gene_max_counts, counts)
}
gene_summary = data.table::data.table(gene_id = reference_gene_ids[gene_rows], total_counts = gene_totals, detected_files = gene_detected_files, zero_files = length(raw$files) - gene_detected_files, mean_count = gene_totals / length(raw$files), max_count = gene_max_counts)
stopifnot(nrow(gene_summary) == 60660L, identical(gene_summary$gene_id, reference_gene_ids[gene_rows]), all(gene_summary$detected_files + gene_summary$zero_files == 1231L), all(is.finite(gene_summary$total_counts)))
if (exists("input_audit", inherits = FALSE)) stopifnot(sum(gene_summary$total_counts) == input_audit$total_gene_counts, sum(gene_summary$zero_files) == input_audit$zero_gene_values)
if (exists("sample_summary", inherits = FALSE)) stopifnot(sum(gene_summary$total_counts) == sum(sample_summary$total_counts), sum(gene_summary$zero_files) == sum(sample_summary$zero_genes))
data.table::fwrite(gene_summary, file = "gene-summary.csv", row.names = FALSE)
research_report = c(
  "# TCGA-BRCA STAR Counts descriptive file-level report",
  "",
  "## Input scope",
  "",
  sprintf("The input comprises %d original TSV files listed in input-files.txt. Each complete table contains 60,664 rows and 9 columns; all complete tables are retained in raw. The first four rows are STAR summary categories, and the remaining 60,660 rows have gene_id values beginning ENSG. All files have identical gene-ID order. Original gene IDs, including version suffixes, and original gene order were preserved.", length(raw$files)),
  "",
  "All summaries use only unstranded counts on ENSG rows. STAR summary rows are excluded. TPM and other columns are not treated as counts. Every ENSG unstranded value was checked to be finite, nonnegative, and integer-valued.",
  "",
  "## Descriptive summaries",
  "",
  "input-audit.csv records the file count, dimensions, gene count per file, and aggregate count and zero-value checks.",
  "",
  "sample-summary.csv contains one row per original filename, sorted by filename. It reports the sum of ENSG unstranded counts, numbers of genes with positive and zero counts, arithmetic mean across all 60,660 genes (including zeros), and maximum gene count.",
  "",
  "gene-summary.csv contains one row per ENSG gene in original order. It reports total unstranded counts across all 1,231 files, numbers of files with positive and zero counts, arithmetic mean across all files (including zeros), and maximum count across files. Gene-length vectors were accumulated table by table, using numeric totals to avoid integer overflow; no second dense gene-by-file matrix was created.",
  "",
  sprintf("Across %s gene/file cells, total unstranded gene counts are %s and zero-valued cells number %s. There are %s genes detected in at least one file and %s genes with zero counts in every file.", format(length(raw$files) * nrow(gene_summary), scientific = FALSE, trim = TRUE), format(sum(gene_summary$total_counts), scientific = FALSE, trim = TRUE), format(sum(gene_summary$zero_files), scientific = FALSE, trim = TRUE), format(sum(gene_summary$detected_files > 0), scientific = FALSE, trim = TRUE), format(sum(gene_summary$detected_files == 0), scientific = FALSE, trim = TRUE)),
  "",
  "## Interpretation limits",
  "",
  "These are descriptive file-level summaries of raw counts. Filenames identify input files, not necessarily unique patients; files must not be treated as independent patients. Counts have not been normalized for library size or other technical differences, so their magnitudes alone do not establish biological differences.",
  "",
  "No differential-expression model, biological group comparison, protein identification, or clinical conclusion was performed or is supported by this analysis."
)
writeLines(research_report, con = "research-report.md")
print(list(output_files = c("gene-summary.csv", "research-report.md"), gene_summary_dimensions = dim(gene_summary), total_gene_counts = sum(gene_summary$total_counts), zero_gene_values = sum(gene_summary$zero_files), original_gene_order = TRUE, complete_raw_tables_retained = length(raw$tables)))
rm(tab, counts, i))---")
# nolint end

# Request j of T03 for n tables; request 1 builds its tables with perf_table() (the investigation's
# swap of its fread() call), which the home's enclosure binds.
perf_t03_code = function(j, n) {
  code = gsub("1231L", paste0(n, "L"), perf_t03_inputs[[j]], fixed = TRUE)
  if (j == 1L) {
    code = sub(paste0("data.table::fread(file = filename, skip = \"gene_id\", header = TRUE, ",
                      "showProgress = FALSE)"), "perf_table(filename)", code, fixed = TRUE)
  }
  code
}

# A 25-line analysis call (PERF-3) and the writing calls of PERF-7 and PERF-8
perf_code25 = paste(c(
  "d = mtcars", "d$kpl = d$mpg * 0.425", "d$heavy = d$wt > 3.5",
  "fit = lm(kpl ~ wt + hp, data = d)", "cf = coef(summary(fit))",
  "by_cyl = aggregate(kpl ~ cyl, data = d, FUN = mean)",
  "by_cyl$n = as.vector(table(d$cyl)[as.character(by_cyl$cyl)])",
  "q = quantile(d$kpl, c(0.1, 0.5, 0.9))", "top = head(d[order(-d$kpl), c(\"kpl\", \"wt\")], 5)",
  "scale01 = function(x) (x - min(x)) / (max(x) - min(x))",
  "d$score = scale01(d$kpl) - scale01(d$wt)", "ranks = rank(-d$score)",
  "tab = prop.table(table(d$cyl, d$heavy))",
  "res = data.frame(term = rownames(cf), estimate = cf[, 1], se = cf[, 2])",
  "res$t = res$estimate / res$se", "res$sig = FALSE", "for (i in seq_len(nrow(res))) {",
  "  res$sig[i] = abs(res$t[i]) > 2", "}",
  "out = list(r2 = summary(fit)$r.squared, by_cyl = by_cyl, q = q, tab = tab)",
  "stopifnot(nrow(res) == 3L, all(is.finite(res$estimate)))", "str(out, max.level = 1)",
  "print(top)", "print(res)", "invisible(ranks)"), collapse = "\n")
perf_code_write = "y = if (exists(\"y\")) y + 1 else 1\nwriteLines(as.character(y), \"out.txt\")"
perf_code_object = "y = if (exists(\"y\")) y + 1 else 1"

# A project root of n small files (the critic's valley)
perf_project = function(dir, n) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(n)) writeLines(sprintf("a,b\n%d,2", i), file.path(dir, sprintf("f%05d.csv", i)))
  dir
}

perf_project_set = function(dir) {
  setwd(dir)
  Sys.setenv(GPTR_PROJECT_ROOT = dir)
  options(gptr.project_root = dir)
}

# n small objects in `home` (the loop what-if's many-objects workspace)
perf_objects = function(home, n) {
  withr::with_seed(1L, for (i in seq_len(n)) {
    assign(sprintf("obj_%05d", i), switch(i %% 4L + 1L, rnorm(10), letters[1:5],
                                          data.frame(a = 1:5, b = rnorm(5), c = letters[1:5]),
                                          list(x = 1, y = "a")), envir = home)
  })
  home
}

# ---- counters ---------------------------------------------------------------------------------

# Counts in gptr's loaded namespace (a bench script may replace its bindings; package code may
# not). snap() reads every count; logged(key, from, to) the addresses of the plain or shared walks,
# or the seconds of the scans, between two snaps.
perf_counters = function() {
  ns = asNamespace("gptr")
  n = c(classify = 0, parse = 0, json = 0, match = 0, scans = 0, walks = 0, shared = 0)
  walks = shared = character()
  scans = numeric()
  put = function(name, fun) {
    unlockBinding(name, ns)
    assign(name, fun, envir = ns)
    lockBinding(name, ns)
  }
  # risk.classify: the service through which call_risk() (native route, perm_decide()) and
  # mcp_serve_exec() (served route) classify r code; P11 registers risk_classify() as it
  svc = ns$the$services[["risk.classify"]]
  classify = svc$fun
  svc$fun = function(...) {
    n[["classify"]] <<- n[["classify"]] + 1
    classify(...)
  }
  the = ns$the
  the$services[["risk.classify"]] = svc
  # env_snap_size(): every size walk; shared = NULL is a plain walk (T3's env_size_of() calls it
  # on each miss), otherwise the unshared walk of a held image against its current value
  size = ns$env_snap_size
  put("env_snap_size", function(x, home = NULL, shared = NULL, ...) {
    if (is.null(shared)) {
      n[["walks"]] <<- n[["walks"]] + 1
      walks[n[["walks"]]] <<- rlang::obj_address(x)
    } else {
      n[["shared"]] <<- n[["shared"]] + 1
      shared[n[["shared"]]] <<- rlang::obj_address(x)
    }
    size(x, home, shared, ...)
  })
  # ckpt_scan_run(): one scan of the project folder, with its seconds
  scan = ns$ckpt_scan_run
  put("ckpt_scan_run", function(...) {
    t0 = perf_clock()
    on.exit({
      n[["scans"]] <<- n[["scans"]] + 1
      scans[n[["scans"]]] <<- perf_clock() - t0
    }, add = TRUE)
    scan(...)
  })
  # prompt_message_json(): one message encoded for a request build
  json = ns$prompt_message_json
  put("prompt_message_json", function(...) {
    n[["json"]] <<- n[["json"]] + 1
    json(...)
  })
  # match() in the settle step of ckpt_objects_after() (its loop and ckpt_settle_row()): the two
  # are enclosed in an environment whose match() counts
  menv = new.env(parent = ns)
  menv$match = function(...) {
    n[["match"]] <<- n[["match"]] + 1
    base::match(...)
  }
  for (f in intersect(c("ckpt_objects_after", "ckpt_settle_row"), ls(ns))) {
    fun = ns[[f]]
    environment(fun) = menv
    put(f, fun)
  }
  # parse(): every parse of code, from any caller
  suppressMessages(trace("parse", print = FALSE, where = baseenv(), tracer = function() {
    n[["parse"]] <<- n[["parse"]] + 1
  }))
  list(snap = function() n, logged = function(key, from, to) {
    i = seq_len(to[[key]] - from[[key]]) + from[[key]]
    switch(key, walks = walks, shared = shared, scans = scans)[i]
  })
}

# Address of every binding of `home`
perf_addresses = function(home) {
  nms = ls(home, all.names = TRUE, sorted = FALSE)
  vapply(nms, function(nm) rlang::obj_address(get(nm, envir = home, inherits = FALSE)), "")
}

# ---- sessions ---------------------------------------------------------------------------------

# A session on `home`, driven offline, counted by `k` (perf_counters()). ask(code, n, route) runs
# one request of n `r` calls of `code` (stopping if one fails) and returns its wall seconds, each
# call's outer and internal seconds, the counts of the request and of each call, and the plain
# walks of bindings the request left unchanged. Routes: "native" (the fake provider asks for the
# calls), "served" (a before_request hook makes them through mcp_dispatch_local(), as an MCP
# client would) and "codex" (the fake codex through gptr's relay, for a session made with
# codex = TRUE).
perf_session = function(home, k, codex = FALSE, self = NULL) {
  ns = asNamespace("gptr")
  st = new.env(parent = emptyenv())
  st$left = 0L
  st$code = "invisible(0)"
  st$route = "native"
  st$id = 0L
  st$first = TRUE
  script = function(req) {
    if (!identical(st$route, "native") || st$left < 1L) return("Done.")
    st$left = st$left - 1L
    st$id = st$id + 1L
    list(tool = "r", input = list(code = st$code), id = paste0("call_", st$id))
  }
  model = if (codex) {
    options(gptr.cli_path = list(codex = c(file.path(R.home("bin"), "Rscript"), "--vanilla",
                                           self, "fake-codex")))
    spec = ns$pcli_fake_provider("codex")
    gptr::gptr_register(spec)
    gptr::gptr_config(budget = list(tokens = 1e6, cost = 5, turns = 1000), .scope = "session")
    paste0(spec$id, "/", spec$models[[1L]]$id)
  } else {
    gptr::gptr_fake_provider(script, name = "perf")
  }
  s = gptr::peter("Begin.", model = model, mode = "auto", tools = "minimal", envir = home,
                  .run = FALSE)
  gptr::gptr_on(s, "tool_execution_start", function(event, ctx) {
    st$t0 = c(st$t0, perf_clock())
    st$c0 = c(st$c0, list(k$snap()))
    NULL
  })
  gptr::gptr_on(s, "tool_execution_end", function(event, ctx) {
    st$t1 = c(st$t1, perf_clock())
    st$internal = c(st$internal, if (is.null(event$elapsed)) NA else event$elapsed)
    st$c1 = c(st$c1, list(k$snap()))
    st$failed = st$failed || isTRUE(event$is_error)
    NULL
  })
  gptr::gptr_on(s, "before_request", function(event, ctx) {
    while (identical(st$route, "served") && st$left > 0L) {
      st$left = st$left - 1L
      st$id = st$id + 1L
      ns$mcp_dispatch_local(list(jsonrpc = "2.0", id = st$id, method = "tools/call",
                                 params = list(name = "r", arguments = list(code = st$code))),
                            ctx$session)
    }
    NULL
  })
  ask = function(code, n = 1L, route = if (codex) "codex" else "native") {
    st$code = code
    st$left = as.integer(n)
    st$route = route
    st$t0 = st$t1 = st$internal = numeric()
    st$c0 = st$c1 = list()
    st$failed = FALSE
    Sys.setenv(FAKE_CODE = code, FAKE_CALLS = n)
    pre = perf_addresses(home)
    c0 = k$snap()
    t0 = perf_clock()
    if (st$first) gptr::gptr_wait(s) else gptr::peter(s, prompt = "Run the next step.")
    wall = perf_clock() - t0
    if (st$failed || length(st$t1) != n) stop("a call of this request failed: ", code)
    c1 = k$snap()
    post = perf_addresses(home)
    same = intersect(names(pre), names(post))
    same = pre[same][pre[same] == post[same]]
    st$first = FALSE
    list(wall = wall, outer = st$t1 - st$t0, internal = st$internal, from = c0, to = c1,
         delta = c1 - c0, call_from = st$c0, call_to = st$c1,
         calls = Map(function(a, b) b - a, st$c0, st$c1), same = same,
         walks_unchanged = sum(k$logged("walks", c0, c1) %in% same))
  }
  list(ask = ask, session = s)
}

# Messages on the session's active path
perf_messages = function(s) {
  path = asNamespace("gptr")$prompt_path(s)
  sum(vapply(path, function(e) identical(e$type, "message"), NA))
}

# Seconds from starting gptr's Codex relay, with the argv the codex exec gets, to its answer of
# `initialize`; the mailbox is answered at once as the session's relay task would
perf_relay_start = function() {
  dir = tempfile("gptr-relay-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  cfg = perf_codex_cfg(asNamespace("gptr")$pcli_codex_mcp_args(dir))
  t0 = perf_clock()
  p = processx::process$new(cfg$command, cfg$args, stdin = "|", stdout = "|", stderr = "|")
  on.exit(p$kill(), add = TRUE)
  p$write_input("{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{}}\n")
  req = file.path(dir, "req")
  while (!file.exists(req) && perf_clock() - t0 < 60) Sys.sleep(0.001)
  writeLines("{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":{}}", file.path(dir, "resp.tmp"))
  unlink(req)
  file.rename(file.path(dir, "resp.tmp"), file.path(dir, "resp"))
  repeat {
    processx::poll(list(p), 1000L)
    if (length(p$read_output_lines(1L))) break
    if (!p$is_alive() || perf_clock() - t0 > 60) stop("the relay did not answer initialize")
  }
  perf_clock() - t0
}

# The relay's command and arguments from codex's `-c mcp_servers.gptr.*` overrides
perf_codex_cfg = function(argv) {
  val = function(key) {
    hit = grep(paste0("^mcp_servers[.]gptr[.]", key, "="), argv, value = TRUE)
    jsonlite::fromJSON(sub("^[^=]*=", "", hit[[1L]]))
  }
  list(command = val("command"), args = as.character(unlist(val("args"))))
}

# ---- the fake codex ---------------------------------------------------------------------------

# A stand-in for `codex exec --json` (offline): answers gptr's probes; for a run reads the prompt,
# starts the MCP server its `-c mcp_servers.gptr.*` overrides name (gptr's relay), makes the MCP
# handshake, FAKE_CALLS `tools/call` requests of `r` with FAKE_CODE, and ends the turn.
perf_fake_codex = function(argv) {
  if ("--version" %in% argv) return(writeLines("codex-cli 0.157.0"))
  if ("--help" %in% argv) {
    return(writeLines(c("Run Codex non-interactively", "", "Usage: codex exec [OPTIONS] [PROMPT]",
                        "", "Commands:", "  resume  Resume a previous session by id", "",
                        "Options:", "  --json  Print events", "  --ignore-user-config  Skip config",
                        "  --skip-git-repo-check  Allow", "  -s, --sandbox <MODE>",
                        "  -C, --cd <DIR>", "  -m, --model <MODEL>",
                        "  -c, --config <key=value>")))
  }
  out = function(x) {
    writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"), stdout(), useBytes = TRUE)
    flush(stdout())
  }
  con = file("stdin", open = "rb")
  while (length(readBin(con, "raw", 65536L))) NULL
  close(con)
  thread = if (length(argv) >= 3L && identical(argv[[2L]], "resume")) argv[[3L]] else
    "00000000-0000-4000-8000-000000000001"
  out(list(type = "thread.started", thread_id = thread))
  out(list(type = "turn.started"))
  cfg = perf_codex_cfg(argv)
  p = processx::process$new(cfg$command, cfg$args, stdin = "|", stdout = "|", stderr = "|",
                            encoding = "UTF-8")
  ask = function(body) {
    p$write_input(paste0(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"), "\n"))
    if (is.null(body$id)) return(NULL)
    repeat {
      processx::poll(list(p), 1000L)
      ln = p$read_output_lines(1L)
      if (length(ln)) return(jsonlite::fromJSON(ln, simplifyVector = FALSE))
      if (!p$is_alive()) stop("relay died")
    }
  }
  ask(list(jsonrpc = "2.0", id = 0L, method = "initialize",
           params = list(protocolVersion = "2025-06-18",
                         capabilities = structure(list(), names = character()),
                         clientInfo = list(name = "fake-codex", version = "0"))))
  ask(list(jsonrpc = "2.0", method = "notifications/initialized"))
  ask(list(jsonrpc = "2.0", id = 1L, method = "tools/list"))
  code = Sys.getenv("FAKE_CODE", "1 + 1")
  for (i in seq_len(as.integer(Sys.getenv("FAKE_CALLS", "1")))) {
    item = list(id = paste0("item_", i), type = "mcp_tool_call", server = "gptr", tool = "r",
                arguments = list(code = code), status = "in_progress")
    out(list(type = "item.started", item = item))
    ask(list(jsonrpc = "2.0", id = 1L + i, method = "tools/call",
             params = list(name = "r", arguments = list(code = code))))
    item$status = "completed"
    out(list(type = "item.completed", item = item))
  }
  close(p$get_input_connection())
  p$wait(10000L)
  out(list(type = "item.completed", item = list(id = "msg", type = "agent_message",
                                                text = "Done.")))
  out(list(type = "turn.completed",
           usage = list(input_tokens = 100L, cached_input_tokens = 0L,
                        cache_write_input_tokens = 0L, output_tokens = 10L,
                        reasoning_output_tokens = 0L)))
}

# ---- the gates (each returns a named vector; run.R takes the median of three children) ---------

# PERF-3: a one-line and a 25-line r call on an empty workspace, native and served
perf_gate_small = function(k, n, full, self) {
  d = perf_session(new.env(parent = globalenv()), k)
  d$ask("invisible(0)")
  d$ask("invisible(0)", route = "served")
  out = numeric()
  for (route in c("native", "served")) for (code in c("one", "lines25")) {
    r = lapply(1:3, function(i) d$ask(if (code == "one") "1 + 1" else perf_code25, route = route))
    key = paste(route, code, sep = "_")
    out[[paste0("classify_", key)]] = max(vapply(r, function(x) x$delta[["classify"]], 0))
    out[[paste0("parse_", key)]] = stats::median(vapply(r, function(x) x$delta[["parse"]], 0))
    out[[paste0("ms_", key)]] = 1000 * stats::median(vapply(r, function(x) x$outer, 0))
  }
  out
}

# PERF-4: T03's requests 2 and 3 on `raw` of 50, 300 and n tables, served and native
perf_gate_warm = function(k, n, full, self) {
  tpl = perf_t03_template()
  out = numeric()
  for (m in unique(c(50L, 300L, n))) {
    home = new.env(parent = globalenv())
    home$raw = perf_t03_raw(m, tpl)
    d = perf_session(home, k)
    d$ask("invisible(0)")
    d$ask("invisible(0)", route = "served")
    for (route in c("served", "native")) for (j in 2:3) {
      r = d$ask(perf_t03_code(j, m), route = route)
      key = sprintf("%s_%d_n%d", route, j, m)
      out[[paste0("walks_", key)]] = r$walks_unchanged
      out[[paste0("gap_", key)]] = r$outer - r$internal
    }
    rm(d, home)
    gc()
  }
  # each child's own ratio, so a child slowed by the machine's load slows both its sizes
  for (m in setdiff(unique(c(300L, n)), 50L)) for (route in c("served", "native")) {
    out[[sprintf("ratio_%s_n%d", route, m)]] =
      out[[sprintf("gap_%s_2_n%d", route, m)]] / out[[sprintf("gap_%s_2_n50", route)]]
  }
  out
}

# PERF-5: cold walks of the T03 list at 50, n / 4 and n tables, 4e6 strings and (full) a 5e7-string
# vector and a 3 x 2.5e7 character data frame; `off` is the walk with the string budget lifted
perf_gate_cold = function(k, n, full, self) {
  ns = asNamespace("gptr")
  raw = perf_t03_raw(n)
  part = function(m) list(files = raw$files[seq_len(m)], tables = raw$tables[seq_len(m)])
  cases = list(t03_50 = function() part(50L), t03_q = function() part(n %/% 4L),
               t03_n = function() raw, vec4e6 = function() paste0("id_", seq_len(4e6)))
  if (full) {
    cases$vec5e7 = function() paste0("id_", seq_len(5e7))
    cases$long3 = function() {
      withr::local_seed(1L)
      m = 2.5e7
      data.frame(id = paste0("g", seq_len(m)), ty = sample(sprintf("type_%02d", 1:40), m, TRUE),
                 nm = paste0("n", sample.int(1e6, m, TRUE)))
    }
  }
  budget = "env_size_strings_max"
  out = numeric()
  for (nm in names(cases)) {
    x = cases[[nm]]()
    gc()
    t0 = perf_clock()
    b = ns$env_snap_size(x)
    out[[paste0("s_", nm)]] = perf_clock() - t0
    out[[paste0("bytes_", nm)]] = b
    out[[paste0("off_", nm)]] = if (exists(budget, envir = ns, inherits = FALSE)) {
      old = ns[[budget]]
      unlockBinding(budget, ns)
      assign(budget, Inf, envir = ns)
      off = ns$env_snap_size(x)
      assign(budget, old, envir = ns)
      lockBinding(budget, ns)
      off
    } else {
      b  # before T2 every walk reads every string
    }
    rm(x)
    gc()
  }
  out
}

# PERF-6: T03's request 1 (creates `raw`), then `raw$note = "x"`, served, n tables
perf_gate_version = function(k, n, full, self) {
  writeLines(perf_t03_files(n), "input-files.txt")
  tpl = perf_t03_template()
  enc = new.env(parent = globalenv())
  enc$perf_table = function(filename) perf_t03_table(tpl)
  home = new.env(parent = enc)
  d = perf_session(home, k)
  d$ask("invisible(0)", route = "served")
  d$ask("invisible(0)", route = "served")
  r1 = d$ask(perf_t03_code(1L, n), route = "served")
  v1 = rlang::obj_address(home$raw)
  r2 = d$ask("raw$note = \"x\"", route = "served")
  v2 = rlang::obj_address(home$raw)
  walked = k$logged("walks", r1$from, r2$to)
  shared = k$logged("shared", r1$from, r2$to)
  c(walks_v1 = sum(walked == v1), walks_v2 = sum(walked == v2), shared_v1 = sum(shared == v1),
    wall_create = r1$wall, wall_modify = r2$wall)
}

# PERF-7: writing and pure-read requests in project folders of 0 to 1,500 entries, native and
# through the fake codex. 300 entries joins the plan's sizes: under load a scan of 600 entries
# passes the scan budget, and the per-call scans of today's valley move to smaller projects.
perf_gate_project = function(k, n, full, self) {
  work = getwd()
  out = numeric()
  keep = function(key, r) {
    s = k$logged("scans", r$from, r$to)
    out[[paste0("scans_", key)]] <<- length(s)
    out[[paste0("scan_one_", key)]] <<- if (length(s)) mean(s) else 0
    out[[paste0("scan_over_", key)]] <<- sum(s) - 2 * max(s, 0)
  }
  for (e in c(0L, 300L, 600L, 1231L, 1500L)) {
    perf_project_set(perf_project(file.path(work, paste0("project-", e)), e))
    d = perf_session(new.env(parent = globalenv()), k)
    d$ask(perf_code_write)
    d$ask(perf_code_write)
    if (e != 1231L) {
      r = d$ask(perf_code_write, 10L)
      keep(paste0("ten_", e), r)
      later = 4:10
      out[[paste0("scans_4_10_ten_", e)]] = sum(vapply(r$calls[later], `[[`, 0, "scans"))
      out[[paste0("call_4_10_ten_", e)]] = stats::median(r$outer[later])
    }
    if (e %in% c(0L, 600L, 1231L)) {
      keep(paste0("one_native_", e), d$ask(perf_code_write))
      x = perf_session(new.env(parent = globalenv()), k, codex = TRUE, self = self)
      x$ask(perf_code_write)
      x$ask(perf_code_write)
      keep(paste0("one_codex_", e), x$ask(perf_code_write))
      if (e == 1231L) keep("read_codex_1231", x$ask("1 + 1"))
    }
  }
  out
}

# PERF-8: a writing request of five calls on 0, 1,000 and 10,000 small bindings; the warm-up
# requests run in a session of their own, since the first call of each workspace is measured
perf_gate_bindings = function(k, n, full, self) {
  w = perf_session(new.env(parent = globalenv()), k)
  w$ask(perf_code_object, 5L)
  w$ask(perf_code_object, 5L)
  out = numeric()
  for (m in c(0L, 1000L, 10000L)) {
    d = perf_session(perf_objects(new.env(parent = globalenv()), m), k)
    r = d$ask(perf_code_object, 5L)
    later = 2:5
    walked = unlist(lapply(later, function(i) k$logged("walks", r$call_from[[i]], r$call_to[[i]])))
    out[[paste0("call1_s_", m)]] = r$outer[[1L]]
    out[[paste0("call2_5_s_", m)]] = stats::median(r$outer[later])
    out[[paste0("match_", m)]] = max(vapply(r$calls[later], `[[`, 0, "match"))
    out[[paste0("walks_", m)]] = sum(walked %in% r$same)
  }
  out
}

# PERF-9: the native turn at about 0 and 300 messages and with 1,000 objects; the relay start.
# A user settings file, which every setting lookup stats, is cached once 2 s old.
perf_gate_turn = function(k, n, full, self) {
  turn = function(r) 1000 * (r$wall - sum(r$internal)) / (length(r$internal) + 1L)
  cfg = tools::R_user_dir("gptr", "config")
  dir.create(cfg, recursive = TRUE, showWarnings = FALSE)
  writeLines("{\"context\": \"summary\"}", file.path(cfg, "settings.json"))
  t0 = perf_clock()
  d = perf_session(new.env(parent = globalenv()), k)
  d$ask("1 + 1", 10L)
  d$ask("1 + 1", 10L)
  Sys.sleep(max(0, 2.1 - (perf_clock() - t0)))
  r0 = d$ask("1 + 1", 10L)
  while (perf_messages(d$session) < 300L) d$ask("1 + 1", 10L)
  r300 = d$ask("1 + 1", 10L)
  o = perf_session(perf_objects(new.env(parent = globalenv()), 1000L), k)
  o$ask("1 + 1", 10L)
  o$ask("1 + 1", 10L)
  r1000 = o$ask("1 + 1", 10L)
  c(turn_ms_0 = turn(r0), turn_ms_300 = turn(r300), turn_ms_objects = turn(r1000),
    enc_0 = r0$delta[["json"]], enc_300 = r300$delta[["json"]], relay_s = perf_relay_start())
}

perf_gates = list("PERF-3" = perf_gate_small, "PERF-4" = perf_gate_warm, "PERF-5" = perf_gate_cold,
                  "PERF-6" = perf_gate_version, "PERF-7" = perf_gate_project,
                  "PERF-8" = perf_gate_bindings, "PERF-9" = perf_gate_turn)

# One child of run.R: a private home and project, the installed build, the counters, the gate
perf_child = function(gate, lib, n, full) {
  self = normalizePath(file.path("dev", "bench", "perf", "workload.R"))
  source(file.path("dev", "bench", "common.R"), local = TRUE)
  bench_isolate()
  work = tempfile("gptr-perf-")
  dir.create(work)
  perf_project_set(normalizePath(work))
  options(gptr.quiet = TRUE, gptr.interactive = FALSE)
  suppressPackageStartupMessages(library(gptr, lib.loc = lib))
  data.table::setDTthreads(1L)
  perf_gates[[gate]](perf_counters(), n, full, self)
}

if (sys.nframe() == 0L) {
  args = commandArgs(TRUE)
  if (identical(args[1L], "fake-codex")) {
    perf_fake_codex(args[-1L])
  } else {
    saveRDS(perf_child(args[[1L]], args[[2L]], as.integer(args[[3L]]), "full" %in% args),
            args[[4L]])
  }
}
