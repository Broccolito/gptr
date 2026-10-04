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
# known zero (a zero metered local charge, a reported zero) stays zero. Budgets compare only the
# known part (run_used(), D-025): an unknown value adds nothing known, so it cannot reach a limit,
# and the `used` a budget reports is then a lower bound.

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

#' A short cost in USD: "$0.0123"; "unknown cost" when any cost is unknown (IC-74)
#' @noRd
format_cost = function(x) {
  x = sum(x)
  if (is.na(x)) return("unknown cost")
  sprintf("$%.4f", x)
}

# ---------------------------------------------------------------------------- rows and the ledger

#' Add a usage row to the session and every live ancestor (root charging, IC-66)
#'
#' The rows are conformed first (an absent observation stays unknown, D-021). Every row needs its
#' request id: the id is the key that de-duplicates a request recorded twice, so rows without one
#' could not be told apart and are refused (`gptr_error_invalid_argument`, `arg =
#' "row$request_id"`); P05's `usage_row()` always sets one.
#' @noRd
usage_add = function(s, row) {
  row = usage_conform(row)
  if (anyNA(row$request_id)) {
    gptr_abort("Invalid usage rows; every row needs its request id.", "invalid_argument",
               arg = "row$request_id", expected = "a request id in every row")
  }
  cur = s
  seen = character()
  while (!is.null(cur)) {
    d = session_data(cur)
    if (d$id %in% seen) break
    seen = c(seen, d$id)
    d$usage = rbind(d$usage, row)
    cur = if (is.null(d$parent_id)) NULL else session_by_id(d$parent_id)
  }
  invisible(row)
}

#' The usage rows of a session and its children, one per request, as a `gptr_usage` listing
#'
#' Attribute `totals` (usage_totals()): a total over an unknown value is unknown (IC-74).
#' @noRd
session_usage_rows = function(s) {
  u = session_data(s)$usage
  u = u[!duplicated(u$request_id), , drop = FALSE]
  rownames(u) = NULL
  out = new_listing(u, "gptr_usage")
  attr(out, "totals") = usage_totals(u)
  out
}

#' Add the per-component token estimate of one request (the ledger of gptr_usage(detail = TRUE))
#' @param components Named list or vector: component -> estimated tokens (`t0`, `t1`, `tools`,
#'   `project`, `environment`, `workspace`, `attached`, `transcript`, `tool_results`, `images`,
#'   `other`).
#' @noRd
ledger_add = function(s, request_id, components) {
  comp = unlist(components)
  if (!length(comp)) return(invisible(NULL))
  d = session_data(s)
  rows = data.frame(request_id = request_id, component = names(comp), tokens = as.numeric(comp),
                    cached = FALSE, stringsAsFactors = FALSE)
  d$ledger = rbind(d$ledger, rows)
  invisible(rows)
}

#' Mark the leading components of a request as cached, up to the reported cache-read tokens
#'
#' An unknown cache read (`NA`: the provider reported no usage, IC-74) leaves the request's
#' `cached` flags unknown (`NA`) rather than claiming that nothing was cached; a known zero
#' leaves them `FALSE`.
#' @noRd
ledger_mark_cached = function(s, request_id, cache_read) {
  d = session_data(s)
  i = which(d$ledger$request_id == request_id)
  if (!length(i)) return(invisible(NULL))
  led = d$ledger
  if (length(cache_read) == 1L && is.na(cache_read)) {
    led$cached[i] = NA
  } else if (isTRUE(cache_read > 0)) {
    led$cached[i] = cumsum(led$tokens[i]) <= cache_read
  } else {
    return(invisible(NULL))
  }
  d$ledger = led
  invisible(NULL)
}

# ---------------------------------------------------------------------------- budgets (IC-66)

#' Budget limits of a new run: the call's budget over the settings default for a root run; for a
#' nested run, or a child whose run option `root` names another session (IC-66), only the call's
#' own share (the root's limits still apply through run_chain(): min(share, root remaining))
#' @noRd
run_budget_limits = function(s, opts, outer) {
  own = as.list(opts$budget %||% list())
  if (!is.null(outer) || !is.null(run_budget_root(s, opts))) return(own)
  defaults = setting_get("budget", session = s,
                         default = list(tokens = 2e6, cost = 5, turns = NULL))
  utils::modifyList(as.list(defaults), own)
}

#' The live root session named by the run option `root` (04 section 7.6: "the root session id
#' for budgets, IC-66") when it is another session than `s`, else NULL
#' @noRd
run_budget_root = function(s, opts) {
  rid = opts$root
  if (!is.character(rid) || length(rid) != 1L || is.na(rid)) return(NULL)
  if (identical(rid, session_data(s)$id)) return(NULL)
  session_by_id(rid)
}

#' The shared budget pool of a root that has no run of its own: the container of a top-level team
#' or fan-out (P19 passes its id as `opts$root`). Created once, on the root's live record, with
#' the per-call default merged with the call's budget; it is charged with the root's usage since
#' its creation (usage_add() rolls every child's rows up to the root). P19 creates one container
#' per top-level call, so one pool per container is one budget per top-level call (IC-66).
#' @return An environment with the fields run_chain(), run_used() and budget_near() read (`id`,
#'   `shell`, `budget`, `usage_start`, `near`), or NULL.
#' @noRd
run_budget_pool = function(s, opts) {
  root = run_budget_root(s, opts)
  if (is.null(root)) return(NULL)
  rl = session_live(root)
  if (is.null(rl) || !is.null(rl$run)) return(NULL)
  if (is.null(rl$budget_root)) {
    rd = session_data(root)
    pool = new.env(parent = emptyenv())
    pool$id = paste0("root:", rd$id)
    pool$shell = root
    pool$budget = run_budget_limits(root, list(budget = opts$budget), NULL)
    pool$usage_start = nrow(rd$usage)
    pool$near = character()
    rl$budget_root = pool
  }
  rl$budget_root
}

#' The runs whose budgets apply to a run: itself, its outer runs, the live runs of its session's
#' ancestors (children charge the root), and the root named by the run option `root`: its run, or
#' the shared pool of a root without a run (IC-66)
#' @noRd
run_chain = function(run) {
  out = list()
  ids = character()
  add = function(r) {
    if (!is.null(r) && !(r$id %in% ids)) {
      out[[length(out) + 1L]] <<- r
      ids <<- c(ids, r$id)
    }
  }
  r = run
  while (!is.null(r)) {
    add(r)
    r = r$outer
  }
  pid = session_data(run$shell)$parent_id
  while (!is.null(pid)) {
    p = session_by_id(pid)
    if (is.null(p)) break
    pl = session_live(p)
    if (!is.null(pl$run)) add(pl$run)
    pid = session_data(p)$parent_id
  }
  root = run_budget_root(run$shell, run$opts)
  if (!is.null(root)) {
    rl = session_live(root)
    if (!is.null(rl$run)) add(rl$run)
  }
  add(run$budget_root)
  out
}

#' Tokens, cost and requests charged to a run's session since the run started (children included)
#'
#' The known part of the usage (IC-74, D-025): an unknown (`NA`) token count or cost adds nothing
#' known, so it can neither reach a budget nor be claimed as zero; each column is summed on its
#' own, so a row's known input still counts when its cache read is unknown. `tokens` and `cost`
#' are therefore lower bounds when a row is unknown; `turns` counts every request.
#' @noRd
run_used = function(run) {
  u = session_data(run$shell)$usage
  u = u[seq_len(nrow(u)) > run$usage_start, , drop = FALSE]
  u = u[!duplicated(u$request_id), , drop = FALSE]
  known = function(col) sum(u[[col]], na.rm = TRUE)
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  list(tokens = sum(vapply(cols, known, numeric(1L))), cost = known("cost"), turns = nrow(u))
}

#' Check the budgets that apply to a session's current run
#'
#' Budgets compare the known usage of run_used() (IC-74, D-025): a request whose cost is unknown
#' (an unpriced model) cannot reach the cost budget, and the token budget still applies to it.
#' @param estimate Estimated input tokens of the next request (a nonnegative number).
#' @return `NULL` or `list(kind, budget, used)`.
#' @noRd
budget_check = function(s, estimate = 0) {
  check_number(estimate, "estimate", min = 0)
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (is.null(run)) return(NULL)
  for (r in run_chain(run)) {
    lim = r$budget
    if (!length(lim)) next
    used = run_used(r)
    if (!is.null(lim$tokens) && used$tokens + estimate > lim$tokens) {
      return(list(kind = "tokens", budget = lim$tokens, used = used$tokens))
    }
    if (!is.null(lim$cost) && used$cost >= lim$cost) {
      return(list(kind = "cost", budget = lim$cost, used = used$cost))
    }
    if (!is.null(lim$turns) && used$turns >= lim$turns) {
      return(list(kind = "turns", budget = lim$turns, used = used$turns))
    }
  }
  NULL
}

#' Emit `budget_near` once per kind when a budget that applies to the run passes 80%
#' @noRd
budget_near = function(run) {
  for (r in run_chain(run)) {
    lim = r$budget
    if (!length(lim)) next
    used = run_used(r)
    for (kind in intersect(names(lim), c("tokens", "cost", "turns"))) {
      b = lim[[kind]]
      if (is.null(b) || kind %in% r$near) next
      if (used[[kind]] >= 0.8 * b) {
        r$near = c(r$near, kind)
        run_emit(run, "budget_near", kind = kind, budget = b, used = used[[kind]])
      }
    }
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------- usage (gptr_usage)

#' Token usage and cost
#'
#' Aggregates the usage rows of sessions (children included, each request counted once) and, for
#' `x = NULL`, of every live session of this process plus the process System 1 log. Reads only.
#'
#' Unknown usage stays unknown: a token count or cost that a provider did not report is `NA`,
#' never zero, so a group or total that includes it is `NA` and the footer prints it as
#' `unknown`. A known zero, such as the metered charge of a local model, stays zero. Rows without
#' a session, agent, model or route (process-level System 1 calls) form the `NA` group.
#'
#' @param x A `gptr_session`, a list of sessions, or `NULL` (every live session of this process
#'   and the System 1 log).
#' @param by Grouping of the summary: `"session"`, `"agent"`, `"model"` or `"route"`.
#' @param detail `FALSE`: a `gptr_usage` data frame (`group`, `requests`, `input`, `output`,
#'   `cache_read`, `cache_write`, `cost`) with attribute `totals`; `TRUE`: the `gptr_ledger` per
#'   request and context component (`request_id`, `component`, `tokens`, `cached`) of the
#'   sessions' own requests, session by session in request order (a child's requests are in the
#'   child's ledger).
#' @return A `gptr_usage` or `gptr_ledger` data frame.
#' @examples
#' gptr_usage()
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_usage(s)
#' @export
gptr_usage = function(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE) {
  by = check_choice(by, c("session", "agent", "model", "route"), "by")
  check_flag(detail, "detail")
  sessions = usage_sessions(x)
  if (detail) {
    rows = do.call(rbind, c(list(ledger_empty()), lapply(sessions,
                                                         function(s) session_data(s)$ledger)))
    rows = rows[!duplicated(rows[c("request_id", "component")]), , drop = FALSE]
    rownames(rows) = NULL
    return(new_listing(rows, "gptr_ledger"))
  }
  rows = do.call(rbind, c(list(usage_empty()), lapply(sessions, function(s) session_data(s)$usage)))
  if (is.null(x)) {
    s1 = usage_log()
    if (nrow(s1)) rows = rbind(rows, usage_conform(s1))
  }
  rows = rows[!duplicated(rows$request_id), , drop = FALSE]
  group = usage_group(rows, by)
  keys = unique(group)
  # %in%, not ==, and unnamed results: a group may be NA (process-level System 1 rows have no
  # session) and must still be counted; NA names would make data.frame() fail on its row names.
  # sum() without na.rm: a group with an unknown value is unknown (IC-74)
  agg = function(col) {
    vapply(keys, function(k) sum(rows[[col]][group %in% k]), 1, USE.NAMES = FALSE)
  }
  df = data.frame(group = keys,
                  requests = vapply(keys, function(k) sum(group %in% k), 1L, USE.NAMES = FALSE),
                  input = agg("input"), output = agg("output"), cache_read = agg("cache_read"),
                  cache_write = agg("cache_write_5m") + agg("cache_write_1h"), cost = agg("cost"),
                  stringsAsFactors = FALSE)
  rownames(df) = NULL
  totals = usage_totals(rows)
  n = as.integer(totals[["requests"]])
  footer = paste0(n, if (n == 1L) " request, " else " requests, ",
                  format_count(c(totals[["input"]], totals[["cache_read"]])), " tokens in, ",
                  format_cost(totals[["cost"]]))
  out = new_listing(df, "gptr_usage", footer = footer)
  attr(out, "totals") = totals
  out
}

#' The sessions gptr_usage() reads: every live one for NULL, else the given ones
#' @noRd
usage_sessions = function(x) {
  if (is.null(x)) return(live_all())
  if (inherits(x, "gptr_session")) return(list(x))
  if (is.list(x) && length(x) && all(vapply(x, function(s) inherits(s, "gptr_session"),
                                            NA))) return(x)
  gptr_abort("`x` must be a gptr_session, a list of sessions or NULL", "invalid_argument",
             arg = "x",
             expected = "a gptr_session, a list of sessions or NULL")
}

#' The group of each usage row for gptr_usage(by =): a model is `provider/model`, and unknown
#' (`NA`) when either part is unknown, never the string "NA/NA" (IC-74)
#' @noRd
usage_group = function(rows, by) {
  if (!identical(by, "model")) return(rows[[by]])
  group = paste(rows$provider, rows$model, sep = "/")
  group[is.na(rows$provider) | is.na(rows$model)] = NA_character_
  group
}
