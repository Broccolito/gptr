# Cache economics (plan P24; architecture 12.7 row "Cache economics"; G4 sections 5.8 and 5.10).
# From the repository root, before changing the prompt layout or the TTL policy:
#   Rscript --vanilla dev/bench/cache-sim/run.R            # prints the three strategies
#   Rscript --vanilla dev/bench/cache-sim/run.R --check    # gptr's cost within +2% of baseline
#   Rscript --vanilla dev/bench/cache-sim/run.R --update   # rewrite the baseline after review
# Tokens are o200k_base counts of the serialised blocks (a proxy for Claude's tokenizer, as in
# G4); output tokens are not priced (G4 fact-check item 3).

source(file.path("dev", "bench", "common.R"), local = TRUE)
source(file.path("dev", "bench", "cache-sim", "sim.R"), local = TRUE)
source(file.path("dev", "bench", "cache-sim", "scenario.R"), local = TRUE)

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  a = bench_args()
  bench_load_gptr(".")
  sc = cache_sim_scenario()
  d = rbind(sim_session(cache_sim_requests(sc), tok_count, "gptr"),
            sim_session(cache_sim_requests(sc, 300, "5m"), tok_count, "all_5m"),
            sim_session(cache_sim_requests(sc, 3600, "1h"), tok_count, "all_1h"))
  s = cache_sim_summary(d)
  print(s, row.names = FALSE)
  path = file.path("dev", "bench", "cache-sim", "baseline.csv")
  if (a$update) bench_write_csv(s, path)
  if (a$check) {
    b = bench_read_csv(path)
    if (is.null(b)) stop("no baseline: run dev/bench/cache-sim/run.R --update after review")
    now = s$cost[s$strategy == "gptr"]
    base = b$cost[b$strategy == "gptr"]
    if (now > base * 1.02) {
      msg = sprintf("Cache economics regression: gptr cost %.6f -> %.6f (%+.1f%%, tolerance 2%%)",
                    base, now, 100 * (now / base - 1))
      stop(bench_regression(msg, fixture = "cache-sim", metric = "cost", baseline = base,
                            value = now))
    }
    message(sprintf("[bench] cache-sim: cost %.6f vs baseline %.6f (within 2%%)", now, base))
  }
}))
