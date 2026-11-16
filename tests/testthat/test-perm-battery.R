# P32 decision battery (plan T1): the gate's answers for twelve snippets in six permission
# settings on both routes, sequenced size-change-overwrite rows, and checkpoint and rewind plans,
# against fixtures/perm/ as main (5e2992b) gave them, but for the six `huge` rows, which T2's string
# budget sizes (D-356); dev/bench/perf/p32/record-battery.R records them (GPTR_RECORD_BATTERY=true).
# Every hot-path task keeps them identical.

bat_record = identical(Sys.getenv("GPTR_RECORD_BATTERY"), "true")
bat_dir = normalizePath(testthat::test_path("fixtures", "perm"))
bat_routes = c("native", "served")

# Compare rows (named character vectors) with fixture `name`, or record them into it
expect_fixture = function(rows, name) {
  path = file.path(bat_dir, paste0(name, ".json"))
  old = if (file.exists(path)) lapply(jsonlite::read_json(path), unlist) else list()
  if (!bat_record) return(expect_identical(rows, old[names(rows)]))
  old[names(rows)] = rows
  jsonlite::write_json(lapply(old, as.list), path, auto_unbox = TRUE, pretty = TRUE)
  succeed()
}

# The size of 1:1e6 here: its serialized state, whose header names the locale's encoding
bat_seq = sprintf("\\b%d\\b", length(serialize(1:1e6, NULL)))

# Text with the project root and the temporary directory masked, and the size of 1:1e6 as UTF-8
# gives it (133 B; 136 B under LC_ALL=C on macOS)
bat_text = function(x) {
  x = if (is.numeric(x)) format(x, scientific = FALSE, trim = TRUE, digits = 15) else
    as.character(x)
  x[is.na(x)] = "NA"
  for (p in unique(c(project_root(), path_norm(tempdir()), tempdir()))) {
    x = gsub(p, "<tmp>", x, fixed = TRUE)
  }
  gsub(bat_seq, "133", x)
}

# What the gate answered: perm_check()'s result, the question it asked (permission_request) and
# why a run nobody can answer would stop
bat_row = function(d, req, run) {
  fl = d$risk$flagged
  sz = d$risk$sizes
  row = c(decision = d$decision, reason = d$reason, rule = paste(d$rule, collapse = ","),
          how = d$how %||% "", level = d$risk$level %||% NA, label = d$risk$label %||% "",
          flags = paste(fl$call, fl$fn, fl$level, fl$category, fl$path_class, sep = " | ",
                        collapse = "\n"),
          sizes = paste(sprintf("%s=%.0f", names(sz), sz), collapse = ";"),
          asked = req$reason %||% "", suggested = req$suggested_rule %||% "",
          undo_note = req$undo_note %||% "", blocked = run$blocked$how_to_allow %||% "")
  stats::setNames(bat_text(row), names(row))
}

# Record every perm_check() answer in `log$rows`; a call whose code is in `log$run` then runs,
# whatever the answer, and any other is refused, so no battery row acts and no run blocks
local_battery = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$rows = list()
  log$run = character()
  check = perm_check
  testthat::local_mocked_bindings(perm_check = function(call, run, ...) {
    log$req = NULL
    d = check(call, run, ...)
    log$rows[[length(log$rows) + 1L]] = bat_row(d, log$req, run)
    run$blocked = NULL
    run$condition = NULL
    if (call$input$code %in% log$run) {
      d$decision = "allow"
      return(d)
    }
    perm_result("deny", "not run by the battery", call$input, d$risk)
  }, .env = .env)
  off = gptr_register(gptr_hook("permission_request", function(event, ctx) {
    log$req = event
    NULL
  }))
  withr::defer(off(), envir = .env)
  log
}

# A runner `function(home, route, mode, codes, s = NULL)`: one request of a new session (or of
# `s`) whose r calls are the codes, made by the model (native) or served from its before_request
# hook through mcp_dispatch_local(), as the CLI routes serve them. Mode manual_r<k> is manual with
# the session rule r(level<=k). An interrupt ends the request.
local_runner = function(.env = parent.frame()) {
  q = new.env(parent = emptyenv())
  q$native = q$served = list()
  q$k = 0L
  fake = local_fake_provider(function(req) {
    q$k = q$k + 1L
    if (q$k > length(q$native)) return("done")
    list(tool = "r", input = list(code = q$native[[q$k]]), id = paste0("bat_", q$k))
  }, name = "battery", .env = .env)
  off = gptr_register(gptr_hook("before_request", function(event, ctx) {
    codes = q$served
    q$served = list()
    for (i in seq_along(codes)) {
      mcp_dispatch_local(list(jsonrpc = "2.0", id = i, method = "tools/call",
                              params = list(name = "r", arguments = list(code = codes[[i]]))),
                         ctx$session)
    }
    NULL
  }))
  withr::defer(off(), envir = .env)
  function(home, route, mode, codes, s = NULL) {
    q$k = 0L
    q[[route]] = as.list(codes)
    rule = if (startsWith(mode, "manual_r")) paste0("r(level<=", sub("manual_r", "", mode), ")")
    if (!is.null(rule)) gptr_permissions(allow = rule)
    on.exit({
      q$native = q$served = list()
      if (!is.null(rule)) gptr_permissions(remove = rule)
    })
    # the console's notice of an interrupt goes nowhere
    withr::with_output_sink(nullfile(), tryCatch(if (is.null(s)) {
      peter("battery", model = fake, mode = sub("_r[0-9]$", "", mode), envir = home)
    } else {
      peter(s, "battery")
    }, interrupt = function(cnd) NULL))
  }
}

# The rows of one request, keyed "<route> <mode> <name of the code>"
bat_rows = function(log, runner, home, route, mode, codes) {
  log$rows = list()
  runner(home, route, mode, codes)
  expect_identical(length(log$rows), length(codes))
  stats::setNames(log$rows, paste(route, mode, names(codes)))
}

# A T03-shaped table (data frames: no battery row depends on data.table)
bat_table = function(i, genes = 200L) {
  ids = c("N_unmapped", "N_multimapping", "N_noFeature", "N_ambiguous",
          sprintf("ENSG%011d.%d", seq_len(genes), i))
  data.frame(gene_id = ids, gene_name = c(rep(NA, 4L), sprintf("G%d", seq_len(genes))),
             gene_type = c(rep(NA, 4L), rep(c("protein_coding", "lncRNA"), length.out = genes)),
             unstranded = as.numeric(seq_along(ids) * i), stranded_first = 0,
             stranded_second = 0, tpm_unstranded = 0.5, fpkm_unstranded = 0.25,
             fpkm_uq_unstranded = 0.125)
}

# The workspace after T03's first request, with three tables
bat_home = function() {
  home = new.env()
  home$files = sprintf("TCGA-BRCA/%04d.rna_seq.tsv", 1:3)
  home$raw = list(files = home$files, tables = stats::setNames(lapply(1:3, bat_table), home$files))
  home$reference_gene_ids = home$raw$tables[[1L]]$gene_id
  home$gene_rows = startsWith(home$reference_gene_ids, "ENSG")
  home$input_audit = data.frame(n_files = 3L, rows_per_file = 204L)
  home$small = 1:10
  home
}

# T03's requests 2 and 3 in short: a dead branch that would build `raw`, summaries, file writes
bat_t03 = c(
  "data.table::setDTthreads(1)",
  "if (!exists(\"raw\", inherits = FALSE)) {",
  "  files = base::readLines(\"input-files.txt\")",
  "  tables = lapply(files, function(f) data.table::fread(file = f, skip = \"gene_id\"))",
  "  raw = list(files = files, tables = setNames(tables, files))",
  "  rm(tables)",
  "}",
  "stopifnot(length(raw$tables) == 3L, identical(names(raw$tables), raw$files))")
bat_snippets = list(
  rm_all = "rm(list = ls())",
  file_remove = "file.remove(\"x.csv\")",
  unlink_dot = "unlink(\".\", recursive = TRUE)",
  system_ls = "system(\"ls\")",
  setenv = "Sys.setenv(A = \"1\")",
  write_tmp = "writeLines(\"a\", \"/tmp/out.txt\")",
  raw_null = "raw = NULL",
  small_assign = "small = 2",
  sum_raw = "sum(raw$tables[[1]]$unstranded)",
  t03_r2 = paste(c(
    bat_t03,
    "sample_summary = data.table::rbindlist(lapply(seq_along(raw$tables), function(i) {",
    "  tab = raw$tables[[i]]",
    "  counts = tab$unstranded[startsWith(tab$gene_id, \"ENSG\")]",
    "  data.table::data.table(file = raw$files[[i]], total = sum(counts), zeros = sum(!counts))",
    "}))",
    "data.table::setorder(sample_summary, file)",
    "data.table::fwrite(sample_summary, file = \"sample-summary.csv\")",
    "print(dim(sample_summary))"), collapse = "\n"),
  t03_r3 = paste(c(
    bat_t03,
    "reference_gene_ids = raw$tables[[1L]]$gene_id",
    "gene_rows = startsWith(reference_gene_ids, \"ENSG\")",
    "gene_totals = numeric(sum(gene_rows))",
    "for (i in seq_along(raw$tables)) {",
    "  tab = raw$tables[[i]]",
    "  counts = tab$unstranded[gene_rows]",
    "  gene_totals = gene_totals + counts",
    "}",
    "gene_summary = data.table::data.table(gene_id = reference_gene_ids[gene_rows],",
    "                                      total = gene_totals)",
    "if (exists(\"input_audit\", inherits = FALSE)) stopifnot(input_audit$n_files == 3L)",
    "data.table::fwrite(gene_summary, file = \"gene-summary.csv\")",
    "writeLines(c(\"# Report\", sprintf(\"%d files\", length(raw$files))), con = \"report.md\")",
    "rm(tab, counts, i)"), collapse = "\n"))

bat_modes = c("auto", "manual", "edits", "plan", "manual_r2", "manual_r3")

test_that("the gate answers the twelve snippets in six settings on both routes as main did", {
  skip_on_cran()
  local_project(files = list(x.csv = c("a,b", "1,2")))
  local_permission_rules()
  local_gptr_options(protect_size = 5e4)
  log = local_battery()
  runner = local_runner()
  rows = list()
  for (route in bat_routes) for (mode in bat_modes) {
    rows = c(rows, bat_rows(log, runner, bat_home(), route, mode, bat_snippets))
  }
  # a tool_call hook rewrites the input after its classification
  off = gptr_register(gptr_hook("tool_call", function(event, ctx) {
    list(decision = "modify", input = list(code = "rm(list = ls())"))
  }))
  withr::defer(off())
  for (route in bat_routes) for (mode in bat_modes) {
    rows = c(rows, bat_rows(log, runner, bat_home(), route, mode, list(hook_modify = "sum(1)")))
  }
  expect_length(rows, 144L)
  expect_fixture(rows, "battery")
})

# Objects the gate sizes, a call that runs changes and the gate sizes again before an overwrite,
# each changed in a way a size kept by address could miss: an environment's binding, a closure's
# <<-, a compact sequence a read expands, sourced code, an R6 method, data.table::set() on nested
# tables by path and through an alias, and an in-place loop interrupted half-way (last: it ends
# the request)
bat_sequences = function(home) {
  home$cache = new.env(parent = emptyenv())
  home$payload = as.numeric(1:2000)
  home$acc = eval(quote(local({
    v = NULL
    function(n) v <<- c(v, as.numeric(seq_len(n)))
  })), home)
  home$x = 1:1e6
  home$nest = list(list(numeric(10)))
  home$parts = list(a = numeric(200), b = numeric(200))
  # an R6 object as R6 builds one (R6 is no dependency): its method's enclosure holds `self`
  home$box = new.env(parent = emptyenv())
  home$box$.__enclos_env__ = list2env(list(self = home$box), parent = baseenv())
  home$box$d = NULL
  home$box$grow = eval(quote(function(n) {
    self$d = c(self$d, as.numeric(seq_len(n)))
    invisible(self)
  }), home$box$.__enclos_env__)
  class(home$box) = c("Box", "R6")
  seqs = list(env = c("cache = NULL", "cache$d = payload"),
              closure = c("acc = NULL", "acc(2000)"),
              compact = c("x = NULL", "which.max(x)"),
              source = c("nest = NULL", "source(\"grow.R\", local = TRUE)"),
              r6 = c("box = NULL", "box$grow(2000)"))
  if (requireNamespace("data.table", quietly = TRUE)) {
    home$tabs = list(t = list(data.table::data.table(a = as.numeric(1:400)),
                              data.table::data.table(b = as.numeric(1:400))))
    seqs$set = c("tabs = NULL", paste(
      "data.table::set(tabs$t[[1]], j = \"x\", value = as.numeric(1:400))",
      "alias = tabs$t[[2]]",
      "data.table::set(alias, j = \"y\", value = as.numeric(1:400))", sep = "\n"))
  }
  seqs$loop = c("parts = NULL", paste(
    "for (k in names(parts)) {",
    "  parts[[k]] = c(parts[[k]], as.numeric(1:1000))",
    "  if (k == \"b\") rlang::interrupt()",
    "}", sep = "\n"))
  seqs
}

test_that("the gate sizes each object again after a change, as main did (sequenced rows)", {
  skip_on_cran()
  local_project(files = list(grow.R = "nest[[1]][[1]] = c(nest[[1]][[1]], as.numeric(1:2000))"))
  local_permission_rules()
  local_gptr_options(protect_size = 1e4)
  log = local_battery()
  runner = local_runner()
  rows = list()
  for (route in bat_routes) for (mode in c("manual", "edits", "manual_r2")) {
    home = new.env()
    seqs = bat_sequences(home)
    log$run = vapply(seqs, function(s) s[[2L]], "")
    steps = unlist(lapply(seqs, function(s) {
      c(size = s[[1L]], change = s[[2L]], overwrite = s[[1L]])
    }))
    n = length(steps)
    rows = c(rows, bat_rows(log, runner, home, route, mode, as.list(steps[-n])),
             bat_rows(log, runner, home, route, mode, as.list(steps[n])))
  }
  expect_fixture(rows, "battery")
})

# Only manual with r(level<=2) runs it: there its level decides (manual and edits ask at 2 and 3)
test_that("an object of 13 million strings near gptr.protect_size is sized by sampling (D-356)", {
  skip_on_cran()
  local_project(gptr = FALSE)
  local_permission_rules()
  log = local_battery()
  runner = local_runner()
  home = new.env()
  home$huge = rep(c("alpha", "beta", "gamma"), length.out = 1.3e7)
  withr::defer(rm("huge", envir = home))
  steps = list(huge.size = "huge = NULL", huge.change = "huge[1] = \"omega\"",
               huge.overwrite = "huge = NULL")
  log$run = steps$huge.change
  rows = list()
  for (route in bat_routes) rows = c(rows, bat_rows(log, runner, home, route, "manual_r2", steps))
  expect_fixture(rows, "battery")
})

# gptr_checkpoints() rows (without entry ids and times), the rewind plan of the last turn and the
# last turn's checkpoint records of objects and files (without addresses, hashes, times, and
# file sizes, which line ends make platform-dependent)
bat_rewind_rows = function(s, key) {
  text = function(x) unlist(lapply(x, bat_text))
  cp = as.data.frame(gptr_checkpoints(s))
  plan = gptr_rewind(s, preview = TRUE)
  ck = Filter(function(e) identical(e$custom_type, "gptr.checkpoint"), session_data(s)$entries)
  frags = Filter(function(f) identical(f$turn, session_data(s)$turns),
                 unlist(lapply(ck, function(e) e$data$fragments), recursive = FALSE))
  objs = unlist(lapply(frags, function(f) f$objects), recursive = FALSE)
  files = unlist(lapply(frags, function(f) f$files), recursive = FALSE)
  cp = cp[setdiff(names(cp), c("id", "time"))]
  plan = plan[names(plan) != "record"]
  fields = c("name", "status", "how", "class", "bytes", "restorable", "reason", "where",
             "held_bytes")
  rows = c(lapply(seq_len(nrow(cp)), function(i) text(cp[i, ])),
           lapply(seq_len(nrow(plan)), function(i) text(plan[i, ])),
           lapply(objs, function(o) text(o[fields])),
           lapply(files, function(f) text(f[c("path", "status", "restorable", "reason")])))
  stats::setNames(rows, paste(key, c(sprintf("checkpoint %d", seq_len(nrow(cp))),
                                     sprintf("plan %d", seq_len(nrow(plan))),
                                     sprintf("object %s", vapply(objs, function(o) o$name, "")),
                                     sprintf("file %s", vapply(files, function(f) f$path, "")))))
}

test_that("checkpoints and rewind plans of a create and a modify are main's (rewind fixture)", {
  skip_on_cran()
  local_project(files = list("input-files.txt" = sprintf("TCGA-BRCA/%04d.rna_seq.tsv", 1:3)))
  runner = local_runner()
  create = paste(
    "files = base::readLines(\"input-files.txt\")",
    "tables = lapply(seq_along(files), function(i) data.frame(",
    "  gene_id = sprintf(\"ENSG%011d\", 1:200), unstranded = as.numeric(1:200) * i))",
    "raw = list(files = files, tables = setNames(tables, files))",
    "rm(tables)",
    "input_audit = data.frame(n_files = length(raw$files))",
    "write.csv(input_audit, \"input-audit.csv\", row.names = FALSE)", sep = "\n")
  rows = list()
  for (route in bat_routes) {
    # a served call is checkpointed as on the CLI routes
    if (route == "served") local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
    home = new.env()
    s = runner(home, route, "auto", create)
    rows = c(rows, bat_rewind_rows(s, paste(route, "create")))
    s = runner(home, route, "auto", "raw$note = \"x\"", s)
    rows = c(rows, bat_rewind_rows(s, paste(route, "modify")))
    unlink("input-audit.csv")
  }
  expect_fixture(rows, "rewind")
})
