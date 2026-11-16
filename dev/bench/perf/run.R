# Performance of gptr's hot paths (plans P24, P32; architecture 12.7 row "Performance"; report 21).
# From the repository root, on demand:
#   Rscript --vanilla dev/bench/perf/run.R [--check] [--full] [--only=PERF-4,PERF-5]
# --check exits 1 when a row misses its bar; --full runs P32's gates at 1,231 tables (about 12 GB);
# --only runs the gates named.
# PERF-1 (report 21: a typical operation under 200 ms, a large workload under 1 s; INFRA-23 adds
# 20,000 SSE deltas in under 1 s of CPU) and PERF-2 (a peter() call over a fake 50 KB streamed
# reply in under 3 s) run on the loaded source tree; a miss means report 21's procedure (Rcpp only
# on its RCPP JUSTIFIED verdict, with a pure-R reference; conventions 9).
# PERF-3 to PERF-9 (plan P32) install the tree byte compiled into a temporary library and run each
# gate in three child processes (workload.R) that load that build; a row is the children's median.
# Counts are hard bars; a time is barred as a ratio to a baseline of the same run; a time whose bar
# is NA prints only, until the task that meets it sets the bar at twice the value that task records
# in P32's progress log.

source(file.path("dev", "bench", "common.R"), local = TRUE)

perf_median = function(fun, times = 5L) {
  stats::median(vapply(seq_len(times), function(i) system.time(fun())[["elapsed"]], 0))
}

# 2,100 R files of 80 lines, a TODO in every 7th (report 21's 2.1k-file repository).
perf_repo = function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (k in 1:2100) {
    x = sprintf("f%04d_%02d = function(x) x + %d  # helper %d", k, 1:80, 1:80, k)
    if (k %% 7L == 0L) x[[40L]] = sprintf("# TODO: vectorise f%04d", k)
    writeLines(x, file.path(dir, sprintf("file%04d.R", k)))
  }
  dir
}

# 1.2 million lines (about 40 MB) for a paged read near the end of a big file.
perf_big_file = function(path) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  for (b in 1:12) {
    i = (b - 1L) * 100000L + seq_len(100000L)
    writeLines(sprintf("%09d,sample_%06d,%.4f,ok", i, i %% 999983L, sin(i)), con)
  }
  path
}

# n Anthropic-shaped text deltas as raw SSE bytes.
perf_sse_bytes = function(n = 20000L) {
  ev = sprintf(paste0("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",",
                      "\"index\":0,\"delta\":{\"type\":\"text_delta\",",
                      "\"text\":\"token %d \"}}\n\n"), seq_len(n))
  charToRaw(paste(ev, collapse = ""))
}

# One result row; `bar` NA prints only.
perf_row = function(gate, measure, value, bar = NA, op = "<=") {
  data.frame(gate = gate, measure = measure, value = signif(value, 4), bar = bar, op = op)
}

# PERF-1 and PERF-2 on gptr's loaded source tree.
perf_run = function() {
  work = tempfile("gptr-perf-")
  repo = perf_repo(file.path(work, "repo"))
  big = perf_big_file(file.path(work, "big.csv"))
  sse = perf_sse_bytes()
  chunks = split(sse, ceiling(seq_along(sse) / 16384))
  stream = function() {
    sp = sse_splitter()
    n = sum(vapply(chunks, function(ch) length(sp$push(ch)), 0L)) + !is.null(sp$flush())
    if (n != 20000L) stop("the SSE splitter returned ", n, " events instead of 20000")
  }
  old = sprintf("line %05d: value = %d", 1:20000, 1:20000)
  new = ifelse(1:20000 %% 10L < 3L, paste0(old, " # changed"), old)
  proj = withr::local_tempdir("gptr-perf-project-")
  withr::local_dir(proj)
  withr::local_options(gptr.project_root = proj)
  fake = gptr_fake_provider(function(request) strrep("A line of a long report.\n", 2000L),
                            name = "perf-reply")
  reply = function() suppressMessages(peter(prompt = "x", model = fake, mode = "auto"))
  rbind(
    perf_row("PERF-1", "grep s, 2,100 files, fixed string, limit 100 (median)",
             perf_median(function() search_grep("TODO", repo, glob = "*.R", fixed = TRUE)), 0.2),
    perf_row("PERF-1", "read s, lines 1,190,000-1,192,000 of 1.2e6 (first read)",
             system.time(read_file(big, offset = 1190000L, limit = 2000L))[["elapsed"]], 1),
    perf_row("PERF-1", "read s, same slice again, index cached (median)",
             perf_median(function() read_file(big, offset = 1190000L, limit = 2000L)), 0.2),
    perf_row("PERF-1", "sse CPU s, 20,000 deltas in 16 KB chunks",
             sum(system.time(stream())[c("user.self", "sys.self")]), 1),
    perf_row("PERF-1", "diff s, 20,000 lines, 30% changed (median)",
             perf_median(function() diff_lines(old, new, max_tokens = Inf), times = 3L), 1),
    perf_row("PERF-1", "diff s, 2,000 lines, 30% changed (median)",
             perf_median(function() diff_lines(old[1:2000], new[1:2000], max_tokens = Inf)), 0.2),
    perf_row("PERF-2", "peter() s, fake 50 KB reply streamed in 3,125 deltas (median)",
             perf_median(reply), 3))
}

# PERF-3 to PERF-9: the median of three children of workload.R on the installed build `lib`.
perf_children = function(gate, lib, n, full, times = 3L) {
  res = lapply(seq_len(times), function(i) {
    out = tempfile(fileext = ".rds")
    log = tempfile(fileext = ".log")
    status = system2(file.path(R.home("bin"), "Rscript"),
                     c("--vanilla", file.path("dev", "bench", "perf", "workload.R"), gate,
                       shQuote(lib), n, shQuote(out), if (full) "full"), stdout = log, stderr = log)
    if (!identical(status, 0L) || !file.exists(out)) {
      stop(gate, " child ", i, " failed:\n",
           paste(utils::tail(readLines(log), 30L), collapse = "\n"))
    }
    readRDS(out)
  })
  apply(do.call(rbind, res), 2L, stats::median)
}

# PERF-5's exact cases as 5e2992b sizes them (recorded by P32 T1)
perf_main_bytes = c(t03_50 = 83809728, vec4e6 = 287920056)

# gptr.checkpoint_scan_budget's default, seconds
perf_scan_budget = 0.25

# The rows of one P32 gate from the children's medians `m` (plan P32, "Performance gates"; the
# bars of times marked NA are set by the task named).
perf_p32_rows = function(gate, m, n) {
  row = function(...) perf_row(gate, ...)
  pick = function(pattern) m[grepl(pattern, names(m))]
  switch(gate,
    "PERF-3" = rbind(
      row("classifications per call, native and served, one-line and 25-line",
          max(pick("^classify_")), 1, "=="),
      do.call(rbind, lapply(c("native_one", "native_lines25", "served_one", "served_lines25"),
                            function(key) {
        rbind(row(paste("parses per call,", key), m[[paste0("parse_", key)]]),
              row(paste("ms per call,", key, "(bar set in T5)"), m[[paste0("ms_", key)]]))
      }))),
    "PERF-4" = {
      gap = function(route, m_) sum(pick(sprintf("^gap_%s_[23]_n%d$", route, m_)))
      big = setdiff(unique(c(300L, n)), 50L)
      rbind(
        row("plain walks of an unchanged binding per request, requests 2-3",
            max(pick("^walks_")), 0),
        do.call(rbind, lapply(big, function(b) {
          rbind(row(sprintf("gap(%d) / gap(50), served, requests 2+3", b),
                    gap("served", b) / gap("served", 50L), 1.3),
                row(sprintf("gap(%d) / gap(50), native, requests 2+3", b),
                    gap("native", b) / gap("native", 50L), 1.3))
        })),
        row(sprintf("gap s at %d, served, requests 2+3", n), gap("served", n)),
        row(sprintf("gap s at %d, native, requests 2+3", n), gap("native", n)))
    },
    "PERF-5" = {
      sampled = setdiff(sub("^bytes_", "", names(pick("^bytes_"))), names(perf_main_bytes))
      rbind(
        do.call(rbind, lapply(names(perf_main_bytes), function(key) {
          row(paste("bytes less 5e2992b's, exact case", key),
              abs(m[[paste0("bytes_", key)]] - perf_main_bytes[[key]]), 0)
        })),
        do.call(rbind, lapply(sampled, function(key) {
          row(paste("bytes / budget-off walk, sampled case", key),
              m[[paste0("bytes_", key)]] / m[[paste0("off_", key)]], 0.98, ">=")
        })),
        row(sprintf("time(%d) / time(%d), the T03 list", n, n %/% 4L),
            m[["s_t03_n"]] / m[["s_t03_q"]], 1.5),
        do.call(rbind, lapply(setdiff(sub("^s_", "", names(pick("^s_"))), c("t03_50", "t03_q")),
                              function(key) row(paste("walk s,", key), m[[paste0("s_", key)]]))))
    },
    "PERF-6" = rbind(
      row("plain walks of raw's version made by request 1", m[["walks_v1"]], 1, "=="),
      row("plain walks of raw's version made by raw$note = \"x\"", m[["walks_v2"]], 1, "=="),
      row("shared walks of raw's held version", m[["shared_v1"]], 1),
      row(sprintf("request 1 wall s at %d (bar set in T3)", n), m[["wall_create"]]),
      row(sprintf("raw$note = \"x\" wall s at %d (bar set in T3)", n), m[["wall_modify"]])),
    "PERF-7" = rbind(
      row("scans per ten-call writing request, 600 entries", m[["scans_ten_600"]], 4),
      row("scan s per ten-call request less two scans, max of 0 to 1,500 entries",
          max(pick("^scan_over_ten_")), perf_scan_budget),
      row("scans in calls 4-10, 600 entries", m[["scans_4_10_ten_600"]], 0),
      row("s per call 4-10, 600 / 0 entries", m[["call_4_10_ten_600"]] / m[["call_4_10_ten_0"]],
          1.3),
      do.call(rbind, lapply(c("one_native_0", "one_native_600", "one_native_1231",
                              "one_codex_0", "one_codex_600", "one_codex_1231",
                              "read_codex_1231"), function(key) {
        row(paste("s per scan,", key, "(bar set by T7)"), m[[paste0("scan_one_", key)]])
      })),
      row("scans per pure-read request, codex, 1,231 entries", m[["scans_read_codex_1231"]])),
    "PERF-8" = rbind(
      row("plain walks of unchanged bindings in calls 2-5, 1,000 and 10,000 bindings",
          max(m[["walks_1000"]], m[["walks_10000"]]), 0),
      row("match() calls in the settle step per call, calls 2-5", max(pick("^match_")), 1),
      row("ms per call 2-5, 1,000 less 0 bindings (bar set in T8)",
          1000 * (m[["call2_5_s_1000"]] - m[["call2_5_s_0"]])),
      row("s per call 2-5, 10,000 less 0 bindings (bar set in T8)",
          m[["call2_5_s_10000"]] - m[["call2_5_s_0"]]),
      row("s of the first call, 10,000 bindings (bar set in T8)", m[["call1_s_10000"]])),
    "PERF-9" = rbind(
      row("messages encoded by a request at 300 messages less at 0", m[["enc_300"]] - m[["enc_0"]],
          0, "=="),
      row("turn(300) / turn(0)", m[["turn_ms_300"]] / m[["turn_ms_0"]], 1.3),
      row("ms per turn, 0 messages (bar set in T9)", m[["turn_ms_0"]]),
      row("ms per turn, 300 messages (bar set in T9)", m[["turn_ms_300"]]),
      row("ms per turn, 1,000 objects (bar set in T9)", m[["turn_ms_objects"]]),
      row("s from relay spawn to initialize answered (bar set in T10)", m[["relay_s"]])))
}

# TRUE when a value meets its bar, NA without a bar; a missing value misses it
perf_pass = function(value, bar, op) {
  ok = ifelse(op == "==", value == bar, ifelse(op == ">=", value >= bar, value <= bar))
  ifelse(is.na(bar), NA, !is.na(ok) & ok)
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  a = bench_args()
  n = if (a$full) 1231L else 300L
  gates = if (is.null(a$only)) paste0("PERF-", 1:9) else a$only
  rows = NULL
  if (any(c("PERF-1", "PERF-2") %in% gates)) {
    bench_load_gptr(".")
    rows = perf_run()
    rows = rows[rows$gate %in% gates, ]
  }
  p32 = intersect(gates, paste0("PERF-", 3:9))
  if (length(p32)) {
    bench_isolate()
    lib = bench_install_gptr(".")
    for (g in p32) {
      t0 = proc.time()[["elapsed"]]
      rows = rbind(rows, perf_p32_rows(g, perf_children(g, lib, n, a$full), n))
      message(sprintf("[bench] %s: %.0f s", g, proc.time()[["elapsed"]] - t0))
    }
  }
  ok = perf_pass(rows$value, rows$bar, rows$op)
  rows$verdict = ifelse(is.na(ok), "-", ifelse(ok, "pass", "FAIL"))
  rows$value = formatC(rows$value, digits = 4L, format = "fg")
  withr::with_options(list(width = 200L), print(rows, row.names = FALSE, right = FALSE))
  bad = !is.na(ok) & !ok
  if (a$check && any(bad)) {
    stop("over its bar: ", paste(rows$gate[bad], rows$measure[bad], collapse = "; "),
         " (PERF-1, PERF-2: run report 21's procedure)")
  }
}))
