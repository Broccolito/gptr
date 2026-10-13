# Diagnostic-only component. Not a production API or package GC insertion.
bp_gc_observation = function(supervisor_rss) {
  before_rss = supervisor_rss()
  started = proc.time()[["elapsed"]]
  collected = tryCatch(gc(full = TRUE), error = identity, interrupt = identity)
  final = tryCatch(list(after_rss = supervisor_rss(),
    elapsed = proc.time()[["elapsed"]] - started), error = identity, interrupt = identity)
  if (inherits(collected, "condition")) stop(collected)
  if (inherits(final, "condition")) stop(final)
  stopifnot(is.matrix(collected), is.numeric(collected), nrow(collected) == 2L,
    ncol(collected) %in% c(6L, 7L),
    identical(rownames(collected), c("Ncells", "Vcells")),
    is.numeric(final$elapsed), length(final$elapsed) == 1L,
    is.finite(final$elapsed), final$elapsed >= 0)
  columns = c("used", "(Mb)", "gc trigger", "(Mb)", "max used", "(Mb)")
  fields = c("used_cells", "used_mib", "trigger_cells", "trigger_mib",
    "maximum_used_cells", "maximum_used_mib")
  if (ncol(collected) == 7L) {
    columns = append(columns, "limit (Mb)", after = 4L)
    fields = append(fields, "limit_mib", after = 4L)
    limits = collected[, 5L]
    stopifnot(!any(is.nan(limits)), any(!is.na(limits)),
      all(is.na(limits) | (is.finite(limits) & limits >= 0)))
  }
  stopifnot(identical(colnames(collected), columns))
  ordinary = collected[, columns != "limit (Mb)", drop = FALSE]
  stopifnot(all(is.finite(ordinary)), all(ordinary >= 0))
  heap = lapply(seq_len(nrow(collected)), function(i) {
    as.list(stats::setNames(unname(collected[i, ]), fields))
  })
  list(before_rss = before_rss, after_rss = final$after_rss,
    collection_elapsed = final$elapsed,
    gc_columns = unname(colnames(collected)), gc_fields = fields,
    heap = stats::setNames(heap, rownames(collected)),
    diagnostic_only = TRUE, product_acceptance = FALSE)
}
