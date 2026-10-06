# Polyglot token benchmark (plan P24; architecture 12.7 row "Polyglot tasks"; G5 p10).
# From the repository root:
#   Rscript --vanilla dev/bench/polyglot/run.R            # writes dev/bench/polyglot/results.csv
#   Rscript --vanilla dev/bench/polyglot/run.R --check    # B and C totals within 10% of baseline
#   Rscript --vanilla dev/bench/polyglot/run.R --update   # rewrite the baseline after review
# Counted: o200k tokens of the tool-call arguments (wire JSON) plus the tool-result text, as G5.

source(file.path("dev", "bench", "common.R"), local = TRUE)
source(file.path("dev", "bench", "polyglot", "tasks.R"), local = TRUE)

# Failures of the B and C totals over the tasks available in both runs, beyond `tol` of the
# baseline, named by variant (empty when both pass).
polyglot_check = function(res, base, tol = 0.10) {
  fails = character()
  for (v in c("B", "C")) {
    r = res[res$variant == v & res$available, , drop = FALSE]
    b = base[base$variant == v & base$available, , drop = FALSE]
    common = intersect(r$task, b$task)
    if (length(common) < 6L) {
      fails[[v]] = sprintf("variant %s: only %d comparable tasks (at least 6 needed)", v,
                           length(common))
      next
    }
    rt = sum(r$total[match(common, r$task)])
    bt = sum(b$total[match(common, b$task)])
    message(sprintf("[bench] variant %s: %d tokens over %d tasks (baseline %d, %+.1f%%)", v,
                    as.integer(rt), length(common), as.integer(bt), 100 * (rt / bt - 1)))
    if (rt > bt * (1 + tol)) {
      fails[[v]] = sprintf("variant %s total %d -> %d (%+.1f%%, tolerance %d%%)", v,
                           as.integer(bt), as.integer(rt), 100 * (rt / bt - 1), 100 * tol)
    }
  }
  fails
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  a = bench_args()
  bench_load_gptr(".")
  res = polyglot_run(tok_count)
  dir = file.path("dev", "bench", "polyglot")
  bench_write_csv(res, file.path(dir, "results.csv"))
  print(res, row.names = FALSE)
  if (a$update) bench_write_csv(res, file.path(dir, "baseline.csv"))
  if (a$check) {
    base = bench_read_csv(file.path(dir, "baseline.csv"))
    if (is.null(base)) stop("no baseline: run dev/bench/polyglot/run.R --update after review")
    fails = polyglot_check(res, base)
    if (length(fails)) {
      stop(bench_regression(c("Polyglot token regression:", paste0("  ", fails)),
                            fixture = paste0("polyglot-", names(fails)), metric = "total",
                            baseline = NA_real_, value = NA_real_))
    }
    message("[bench] polyglot: B and C totals within 10% of the baseline")
  }
}))
