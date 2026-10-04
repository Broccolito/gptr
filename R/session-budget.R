# session-budget.R -- usage rows, the token ledger, budgets and gptr_usage() (P06, layer L3).
#
# Usage rows (contract 04 section 4.3) live in the session's `.d$usage`; a row is added to the
# session that made the request and to every ancestor, so a root's rows include its children's
# and budgets are charged to the root (IC-66). gptr_usage() aggregates live sessions and the
# process System 1 log; no usage lives in the package namespace (INFRA-15). IC-05 moved
# gptr_usage() here from P05's provider-usage.R; the zero-row table `usage_empty()` and the rows
# themselves (`usage_row()`) are P05's.
#
# IC-74 (07-local-ollama.md section 5): "Missing usage remains unknown". A token or cost value a
# row does not carry is NA, never a known zero, and a sum over an unknown value is unknown; a
# known zero (a zero metered local charge, a reported zero) stays zero.

usage_columns = c("request_id", "session", "agent", "parent_id", "provider", "model", "route",
                  "input", "output", "cache_read", "cache_write_5m", "cache_write_1h", "reasoning",
                  "images", "cost", "tier", "stop_reason", "started", "seconds", "estimated",
                  "multiplier")
usage_token_columns = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                        "reasoning", "images", "cost")

#' Conform usage rows (from P05's usage_row()) to the section 4.3 columns, types and order
#'
#' Every missing column, the token and cost columns included, is the typed NA of P05's
#' `usage_empty()`: an absent observation is unknown (IC-74), never a known zero. A bare logical
#' `NA` column becomes its typed NA; other values of the wrong type are refused rather than
#' coerced, and known numbers and start times must be finite, numbers also nonnegative (P05's
#' rule for usage rows). Numeric `started` values are epoch seconds. A list input must be named
#' columns of equal length (a `NULL` element is an absent column), never nested values to flatten
#' or scalars to recycle. Extra columns are dropped.
#' @noRd
usage_conform = function(row) {
  if (!is.data.frame(row)) row = usage_conform_list(row)
  row = as.data.frame(row, stringsAsFactors = FALSE)
  empty = usage_empty()
  for (col in setdiff(usage_columns, names(row))) {
    row[[col]] = rep(empty[[col]][NA_integer_], nrow(row))
  }
  row = row[usage_columns]
  for (col in usage_columns) row[[col]] = usage_conform_column(row[[col]], empty[[col]], col)
  rownames(row) = NULL
  row
}

#' A named list of usage columns, checked before as.data.frame() could flatten or recycle it
#' @noRd
usage_conform_list = function(row) {
  expected = "a data frame or a named list of equal-length usage columns"
  if (!is.list(row)) {
    gptr_abort("Invalid usage rows; expected a data frame or a named list.", "invalid_argument",
               arg = "row", expected = expected)
  }
  row = row[!vapply(row, is.null, logical(1L))]
  column = function(x) {
    inherits(x, "POSIXlt") || (is.atomic(x) && !is.null(x) && is.null(dim(x)))
  }
  keys = names(row)
  ok = (length(row) == 0L || (!is.null(keys) && !anyNA(keys) && all(nzchar(keys)))) &&
    !anyDuplicated(keys) && all(vapply(row, column, logical(1L))) &&
    length(unique(vapply(row, length, integer(1L)))) <= 1L
  if (!ok) {
    gptr_abort("Invalid usage rows; expected a data frame or a named list.", "invalid_argument",
               arg = "row", expected = expected)
  }
  row
}

#' One usage column in its section 4.3 type (`proto` is the column of usage_empty())
#' @noRd
usage_conform_column = function(x, proto, col) {
  bad = function(expected) {
    gptr_abort(paste0("Invalid usage column `", col, "`; expected ", expected, "."),
               "invalid_argument", arg = paste0("row$", col), expected = expected)
  }
  if (is.logical(x) && all(is.na(x)) && !is.logical(proto)) {
    return(rep(proto[NA_integer_], length(x)))
  }
  if (inherits(proto, "POSIXct")) {
    if (inherits(x, "POSIXlt")) x = as.POSIXct(x)
    if (!inherits(x, "POSIXct") && !is.numeric(x)) bad("POSIXct times or epoch seconds")
    secs = as.numeric(x)
    if (any(is.nan(secs) | is.infinite(secs))) {
      bad("finite POSIXct times or epoch seconds, or NA")
    }
    return(if (inherits(x, "POSIXct")) x else .POSIXct(secs, tz = "UTC"))
  }
  if (is.character(proto)) {
    if (!is.character(x)) bad("a character column")
    return(x)
  }
  if (is.logical(proto)) {
    if (!is.logical(x)) bad("a logical column")
    return(x)
  }
  if (!is.numeric(x) || any(is.nan(x)) || any(!is.na(x) & (!is.finite(x) | x < 0))) {
    bad("finite nonnegative numbers or NA")
  }
  as.numeric(x)
}

#' Totals of usage rows: requests, input, output, cache reads, cache writes and cost
#'
#' A sum over an unknown (`NA`) value is unknown (IC-74), as in P05's usage_rollup().
#' @noRd
usage_totals = function(u) {
  c(requests = nrow(u), input = sum(u$input), output = sum(u$output),
    cache_read = sum(u$cache_read), cache_write = sum(u$cache_write_5m + u$cache_write_1h),
    cost = sum(u$cost))
}

#' An empty token ledger: one row per request and context component (04 section 4.3)
#' @noRd
ledger_empty = function() {
  data.frame(request_id = character(), component = character(), tokens = numeric(),
             cached = logical(), stringsAsFactors = FALSE)
}

#' A short token count: 950, 1.2k, 3.4M; "unknown" when any count is unknown (IC-74)
#'
#' The unit follows the printed value, so 999.7 is "1.0k" and 999999 is "1.0M".
#' @noRd
format_count = function(n) {
  n = sum(n)
  if (is.na(n)) return("unknown")
  if (round(n) < 1000) return(as.character(round(n)))
  k = sprintf("%.1f", n / 1000)
  if (as.numeric(k) < 1000) return(paste0(k, "k"))
  paste0(sprintf("%.1f", n / 1e6), "M")
}
