# Performance of the pure-R hot paths (plan P24; architecture 12.7 row "Performance"; report 21).
# From the repository root, on demand:
#   Rscript --vanilla dev/bench/perf/run.R [--check]   # --check: exit 1 when a path is over its bar
# Report 21's bar: a typical operation under 200 ms, a large workload under 1 s; INFRA-23 adds
# 20,000 SSE deltas in under 1 s of CPU. A path over its bar is marked INVESTIGATE: run report
# 21's procedure (Rcpp only on its RCPP JUSTIFIED verdict, with a pure-R reference; conventions 9).

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

# One row per hot path on gptr's loaded source tree.
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
  s = c(perf_median(function() search_grep("TODO", repo, glob = "*.R", fixed = TRUE)),
        system.time(read_file(big, offset = 1190000L, limit = 2000L))[["elapsed"]],
        perf_median(function() read_file(big, offset = 1190000L, limit = 2000L)),
        sum(system.time(stream())[c("user.self", "sys.self")]),
        perf_median(function() diff_lines(old, new, max_tokens = Inf), times = 3L),
        perf_median(function() diff_lines(old[1:2000], new[1:2000], max_tokens = Inf)))
  bar = c(0.2, 1, 0.2, 1, 1, 0.2)
  data.frame(path = c("grep", "read", "read", "sse", "diff", "diff"),
             workload = c("2,100 files, fixed string, limit 100",
                          "lines 1,190,000-1,192,000 of 1.2e6 (first read)",
                          "same slice again (index cached)", "20,000 deltas in 16 KB chunks",
                          "20,000 lines, 30% changed", "2,000 lines, 30% changed"),
             seconds = round(s, 4), bar = bar,
             verdict = ifelse(s <= bar, "PURE R IS ENOUGH", "INVESTIGATE"),
             measure = c("median elapsed", "elapsed", "median elapsed", "CPU seconds",
                         "median elapsed", "median elapsed"))
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  check = bench_args()$check
  bench_load_gptr(".")
  res = perf_run()
  print(res, row.names = FALSE)
  bad = res$verdict == "INVESTIGATE"
  if (check && any(bad)) {
    stop("hot path over its bar: ", paste(res$path[bad], res$workload[bad], collapse = "; "),
         " (run report 21's procedure)")
  }
}))
