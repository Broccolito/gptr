# Compaction: the threshold and the cold rule, the in-conversation checkpoint request, harness
# state extraction and the compaction entry (P07). Adapted from G4 section 5.5 (compaction.R):
# the checkpoint prompt is G4 section 3.6 verbatim; the harness, not the model, writes the
# user's messages, the objects with their creating code, decisions, files, skills and the plan.
# keep_recent = 0: the compaction entry replaces everything before it.

#' Compaction threshold (contract section 7.7; architecture section 6.11)
#'
#' @param window Context window in tokens (`NA`: unknown).
#' @param max_output Maximum output tokens of the model (`NA` counts as 0).
#' @param r_cap The `r` result budget (`gptr.r_output_tokens`).
#' @return `num(1)`: `min(window - min(max(30000, 0.10 * window), 0.25 * window), window -
#'   max(16384, max_output + 2 * r_cap), compact_at)`, where `compact_at` is the setting
#'   `compact_at` read through `setting_get()` (without P08's settings service: the option
#'   `gptr.compact_at`, default 200000). Settings are process-wide (contract 5:
#'   `gptr_config(.scope = "session")` is this R process), so no session is passed. A `null`
#'   setting disables the cap (contract 3.1 and 11.2: `num|null`); R options cannot hold `NULL`,
#'   so `Inf` or `NA` in the option disables it too. An unknown window gives the cap alone.
#' @noRd
compact_threshold = function(window, max_output, r_cap = 4000) {
  cap = setting_get("compact_at")
  cap = if (is.null(cap) || !length(cap) || is.na(cap[[1]])) Inf else as.numeric(cap[[1]])
  if (is.null(window) || !length(window) || is.na(window)) return(cap)
  mo = if (is.null(max_output) || !length(max_output) || is.na(max_output)) 0 else max_output
  min(window - min(max(30000, 0.10 * window), 0.25 * window),
      window - max(16384, mo + 2 * r_cap), cap)
}
