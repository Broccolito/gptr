# Scenario definitions: setup(home, proj) and requests (a list of named code vectors, one per
# request; every element is one served `r` call).
gen_code = function(n) {
  sprintf(paste(
    'data.table::setDTthreads(1)',
    'if (!exists("raw", inherits = FALSE)) {',
    '  files = sprintf("file_%%04d.tsv", seq_len(%dL))',
    '  ids = c(paste0("N_", c("unmapped", "multimapping", "noFeature", "ambiguous")), sprintf("ENSG%%011d.%%d", seq_len(60660L), 1L))',
    '  gname = c(rep("", 4L), sprintf("GENE%%05d", (seq_len(60660L) %%%% 59000L) + 1L))',
    '  gtype = c(rep("", 4L), sprintf("type_%%02d", seq_len(60660L) %%%% 40L))',
    '  tables = lapply(seq_len(%dL), function(i) data.table::data.table(gene_id = ids[seq_along(ids)], gene_name = gname[seq_along(gname)], gene_type = gtype[seq_along(gtype)], unstranded = (seq_len(60664L) * (i + 3L)) %%%% 9973L, stranded_first = (seq_len(60664L) * (i + 5L)) %%%% 9967L, stranded_second = (seq_len(60664L) * (i + 7L)) %%%% 9949L, tpm_unstranded = ((seq_len(60664L) * (i + 3L)) %%%% 9973L) / 7, fpkm_unstranded = ((seq_len(60664L) * (i + 5L)) %%%% 9967L) / 11, fpkm_uq_unstranded = ((seq_len(60664L) * (i + 7L)) %%%% 9949L) / 13))',
    '  raw = list(files = files, tables = setNames(tables, files))',
    '  rm(tables, ids, gname, gtype)',
    '}',
    'input_audit = data.frame(n_files = length(raw$files), total = sum(vapply(raw$tables, function(t) sum(t$tpm_unstranded), 0)))',
    'data.table::fwrite(input_audit, file = "input-audit.csv")',
    'print(input_audit)', sep = "\n"), n, n)
}

scenarios = list()

# (1)-(3): one large list of data.tables, created, read, modified
scenarios$big = function(kv, proj) {
  n = as.integer(kv$n)
  list(
    requests = list(
      c(create = gen_code(n)),
      c(read_write_csv = paste(
          'if (!exists("raw", inherits = FALSE)) raw = NULL',
          'sample_summary = data.table::rbindlist(lapply(seq_along(raw$tables), function(i) { tab = raw$tables[[i]]; data.table::data.table(file = raw$files[[i]], total = sum(tab$tpm_unstranded)) }))',
          'data.table::fwrite(sample_summary, file = "sample-summary.csv")',
          'dim(sample_summary)', sep = "\n"),
        pure_read = 'sum(vapply(raw$tables, nrow, 1L))',
        read_assign = 'n_rows = sum(vapply(raw$tables, nrow, 1L))'),
      c(modify = 'raw$tables[[1]]$x = 1',
        byref = 'data.table::set(raw$tables[[2]], j = "y", value = 2)',
        read_after_modify = 'n_rows2 = sum(vapply(raw$tables, nrow, 1L))'),
      c(fallback_modify = paste('if (!exists("raw", inherits = FALSE)) raw = NULL',
          'raw$tables[[3]]$z = 3', sep = "\n"),
        reassign = 'raw = c(raw, list(note = "x"))')
    ),
    profile = c("create", "read_write_csv", "read_assign", "modify", "fallback_modify", "reassign"))
}

# (4): many small objects
scenarios$many = function(kv, proj) {
  n = as.integer(kv$n)
  list(
    setup = function(home, proj) {
      for (i in seq_len(n)) assign(sprintf("o%05d", i), as.numeric(1:10) + i, envir = home)
    },
    requests = list(
      c(read_assign_cold = 'v = sum(o00001)', modify_one = 'o00002[1] = 0'),
      c(create_one = 'new_obj = 1:3 + 0', pure_read = 'sum(o00003)',
        read_assign_warm = 'v2 = sum(o00004)')
    ))
}

# (5): a project folder with many files, a few large
scenarios$files = function(kv, proj) {
  n = as.integer(kv$files)
  list(
    setup = function(home, proj) {
      per = 100L
      dirs = sprintf("d%03d", seq_len(ceiling(n / per)))
      for (d in dirs) dir.create(file.path(proj, d))
      ext = c(".csv", ".txt", ".R", ".json", ".dat")
      txt = paste(rep("0123456789abcdef", 128), collapse = "")  # 2 KB
      for (i in seq_len(n)) {
        f = file.path(proj, dirs[(i - 1L) %/% per + 1L], sprintf("f%05d%s", i, ext[i %% 5L + 1L]))
        writeLines(c(txt, i), f)
      }
      big = function(f, mb) writeBin(as.raw(rep_len(0:255, mb * 2^20)), file.path(proj, f))
      big("big_30mb_a.dat", 30); big("big_30mb_b.csv", 30); big("big_80mb.bin", 80)
      for (k in 1:5) big(sprintf("med_%d.csv", k), 2)
      writeLines("first", file.path(proj, "d001", "tracked.txt"))
    },
    requests = list(
      c(write_one = 'writeLines(c("a", "b"), "result.txt")',
        write_csv = 'data.table::fwrite(data.frame(a = 1:10), "res2.csv")'),
      c(obj_only = 'z = 1:10 + 0',
        append_existing = 'cat("more\\n", file = "d001/tracked.txt", append = TRUE)',
        write_20mb = 'writeBin(as.raw(rep_len(0:255, 2e7)), "big_out.bin")')
    ))
}

# (5b): a T03-like project root: 1,231 input TSVs of ~4.2 MB (symbolic or hard links to one file,
# as the benchmark's replay links its inputs) plus input-files.txt; calls write one CSV each
scenarios$files_t03 = function(kv, proj) {
  n = as.integer(kv$files)
  link = kv$link %||% "sym"
  list(
    setup = function(home, proj) {
      src = file.path(dirname(proj), "input-src.tsv")
      writeBin(as.raw(rep_len(c(48:57, 9L, 10L), 4.2e6)), src)
      names = sprintf("%08x-0000-0000-0000-%012d.tsv", seq_len(n), seq_len(n))
      for (f in names) {
        if (link == "sym") file.symlink(src, file.path(proj, f)) else file.link(src, file.path(proj, f))
      }
      writeLines(names, file.path(proj, "input-files.txt"))
    },
    requests = list(
      c(write_csv_1 = 'data.table::fwrite(data.frame(a = 1:10), "input-audit.csv")'),
      c(write_csv_2 = 'data.table::fwrite(data.frame(a = 1:10), "sample-summary.csv")'),
      c(write_csv_3 = 'data.table::fwrite(data.frame(a = 1:10), "gene-summary.csv")',
        obj_only = 'z = 1:10 + 0')
    ))
}

# (6): copy-safety cost of by-reference pre-images: 12 numeric vectors of 90 MB (each under
# gptr.undo_capture_max = 1e8), three modified in place per request; held images pass
# gptr.undo_max_bytes = 1e9 in request 4, so the turn-end budget spills (with .gptr) or drops
scenarios$vec = function(kv, proj) {
  mod = function(k) paste(sprintf("x%02d[1] = 0", k), collapse = "\n")
  list(
    setup = function(home, proj) {
      len = if (identical(kv$n, "500")) 11.25e6 else as.numeric(kv$n)
      for (i in 1:12) assign(sprintf("x%02d", i), as.numeric(seq_len(len)) + i, envir = home)
    },
    requests = list(c(modify_3_a = mod(1:3)), c(modify_3_b = mod(4:6)), c(modify_3_c = mod(7:9)),
                    c(modify_3_d = mod(10:12)), c(modify_again = mod(1:3)))
  )
}
