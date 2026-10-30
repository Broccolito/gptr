# session-budget.R -- usage rows, the token ledger, budgets and gptr_usage() (P06, layer L3).
# A row is added to the requesting session and every ancestor, so budgets charge the root (IC-66).
# Missing usage stays unknown (IC-74): NA, never zero, and a sum over it is NA; budgets compare
# only the known part (run_used(), D-025), so the `used` they report is then a lower bound.

usage_columns = c("request_id", "session", "agent", "parent_id", "provider", "model", "route",
                  "input", "output", "cache_read", "cache_write_5m", "cache_write_1h", "reasoning",
                  "images", "cost", "tier", "stop_reason", "started", "seconds", "estimated",
                  "multiplier")
usage_token_columns = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                        "reasoning", "images", "cost")

#' Conform usage rows (from P05's usage_row()) to the section 4.3 columns, types and order; a
#' missing or all-NA column is the typed NA of usage_empty() (unknown, IC-74)
#' @noRd
usage_conform = function(row) {
  row = as.data.frame(row, stringsAsFactors = FALSE)
  empty = usage_empty()
  for (col in usage_columns) {
    if (is.null(row[[col]]) || all(is.na(row[[col]]))) {
      row[[col]] = rep(empty[[col]][NA_integer_], nrow(row))
    }
  }
  row = row[usage_columns]
  for (col in c(usage_token_columns, "seconds", "multiplier")) row[[col]] = as.numeric(row[[col]])
  row$estimated = as.logical(row$estimated)
  if (!inherits(row$started, "POSIXct")) row$started = .POSIXct(as.numeric(row$started), tz = "UTC")
  rownames(row) = NULL
  row
}

#' Totals of usage rows; a sum over an unknown (`NA`) value is unknown (IC-74)
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

# ---------------------------------------------------------------------------- rows and the ledger

#' Add a usage row to the session and every live ancestor (root charging, IC-66)
#' Rows are conformed (D-021); a row without its request id, the de-duplication key, is refused.
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

#' A bounded canonical charged row, with normalized epoch metadata
#' @noRd
usage_row_canonical = function(row) {
  row = usage_rows_check(usage_conform(row), "durable usage row")
  if (nrow(row) != 1L || !session_id_ok(row$session) ||
      !(is.na(row$parent_id) || session_id_ok(row$parent_id)) ||
      !rlang::is_string(row$agent) || !nzchar(row$agent)) {
    usage_invalid("durable usage row", "one charged row with valid session and agent identity")
  }
  for (key in usage_chr_columns) {
    value = row[[key]]
    if (!is.na(value) && nchar(value, type = "bytes") > 8192L) {
      usage_invalid("durable usage row", "bounded scalar strings")
    }
  }
  row$started = .POSIXct(as.numeric(row$started), tz = "UTC")
  row
}

#' Exact finite IEEE-754 bits for the private durable journal, independent of JSON digits
#' @noRd
usage_double_store = function(value) {
  bytes = writeBin(as.numeric(value), raw(), size = 8L, endian = "big")
  list(ieee754 = paste(sprintf("%02x", as.integer(bytes)), collapse = ""))
}

#' Decode only the exact private numeric tag; field policy is checked by usage_row_restore()
#' @noRd
usage_double_restore = function(value) {
  if (!is.list(value) || !identical(names(value), "ieee754") ||
      !rlang::is_string(value[[1L]]) || is.na(value[[1L]]) ||
      nchar(value[[1L]], type = "bytes") != 16L ||
      !grepl("^[0-9a-f]{16}$", value[[1L]])) {
    usage_invalid("durable usage number", "one exact 16-digit finite IEEE-754 tag")
  }
  starts = seq.int(1L, 15L, by = 2L)
  bytes = as.raw(strtoi(substring(value[[1L]], starts, starts + 1L), base = 16L))
  number = readBin(bytes, "double", n = 1L, size = 8L, endian = "big")
  if (!is.finite(number)) {
    usage_invalid("durable usage number", "one finite IEEE-754 number")
  }
  number
}

#' Persist every canonical column; JSON null represents an unknown value
#' @noRd
usage_row_store = function(row) {
  row = usage_row_canonical(row)
  stored = as.list(row)
  stored$started = as.numeric(row$started)
  stored = lapply(stored, function(value) if (is.na(value)) NULL else value)
  for (key in c(usage_num_columns, "started")) {
    if (!is.null(stored[[key]])) stored[key] = list(usage_double_store(stored[[key]]))
  }
  if (nchar(json_encode(stored), type = "bytes") > 65536L) {
    usage_invalid("durable usage row", "at most 65536 serialized bytes")
  }
  stored
}

#' Restore an exact scalar schema without provider lookup or repricing
#' @noRd
usage_row_restore = function(stored) {
  if (!is.list(stored) || !identical(names(stored), usage_columns)) {
    usage_invalid("durable usage row", "the exact ordered 21-column scalar schema")
  }
  row = stored
  for (key in usage_columns) {
    value = stored[[key]]
    if (is.null(value) && key %in% c(usage_chr_columns, usage_num_columns)) {
      row[key] = list(if (key %in% usage_chr_columns) NA_character_ else NA_real_)
      next
    }
    if (key %in% c(usage_num_columns, "started") && is.list(value)) {
      value = usage_double_restore(value)
      row[key] = list(value)
    }
    valid = length(value) == 1L &&
      if (key %in% usage_chr_columns) {
        is.character(value) && !is.na(value)
      } else if (key == "estimated") {
        is.logical(value) && !is.na(value)
      } else {
        is.numeric(value) && is.finite(value) && (key == "started" || value >= 0)
      }
    if (!isTRUE(valid)) usage_invalid("durable usage row", "typed scalar values or JSON null")
  }
  row = usage_row_canonical(usage_conform(row))
  usage_row_store(row)
  row
}

#' Require a canonical own charge to match its receiver's header
#' @noRd
usage_own_check = function(row, d) {
  if (!identical(row$session, d$id) ||
      !identical(row$parent_id, d$parent_id %||% NA_character_)) {
    usage_invalid("durable usage identity", "the owning session and its recorded parent")
  }
  invisible(row)
}

#' Recover an ancestor journal row from a bounded origin-to-receiver prefix
#' @noRd
usage_ancestor_restore = function(data, d) {
  if (!is.list(data) || !identical(names(data), c("row", "lineage", "receiver_parent"))) {
    usage_invalid("durable usage ancestry", "one exact accounting record")
  }
  row = usage_row_restore(data$row)
  ids = data$lineage
  if (!is.list(ids) || !is.null(names(ids)) || length(ids) < 2L || length(ids) > 32L ||
      !all(vapply(ids, session_id_ok, NA))) {
    usage_invalid("durable usage ancestry", "two to 32 scalar session ids")
  }
  ids = unlist(ids, use.names = FALSE)
  if (anyDuplicated(ids) || !identical(ids[[1L]], row$session) ||
      !identical(ids[[2L]], row$parent_id) || !identical(utils::tail(ids, 1L), d$id) ||
      !(is.null(data$receiver_parent) || session_id_ok(data$receiver_parent)) ||
      !identical(data$receiver_parent, d$parent_id)) {
    usage_invalid("durable usage ancestry",
                   "a unique origin-to-receiver prefix matching its header")
  }
  if (nchar(json_encode(data), type = "bytes") > 65536L) {
    usage_invalid("durable usage ancestry", "at most 65536 serialized bytes")
  }
  row
}

#' Charge memory and persist originating rows in every already-live ancestor
#' No child file or registry aggregate is read; a failed append remains fatal.
#' @noRd
usage_add_durable = function(s, row) {
  row = usage_row_canonical(row)
  usage_own_check(row, session_data(s))
  chain = list(s)
  ids = session_data(s)$id
  cur = s
  repeat {
    pid = session_data(cur)$parent_id
    if (is.null(pid)) break
    if (pid %in% ids || length(ids) >= 32L) {
      usage_invalid("durable usage ancestry", "an acyclic chain of at most 32 live sessions")
    }
    cur = session_by_id(pid)
    if (is.null(cur)) break
    if (!identical(session_data(cur)$id, pid)) {
      usage_invalid("durable usage ancestry", "the exact live parent")
    }
    chain[[length(chain) + 1L]] = cur
    ids = c(ids, pid)
  }
  stored = usage_row_store(row)
  usage_add(s, row)
  for (i in seq_along(chain)[-1L]) {
    receiver = chain[[i]]
    data = list(row = stored, lineage = as.list(ids[seq_len(i)]),
                receiver_parent = session_data(receiver)$parent_id)
    usage_ancestor_restore(data, session_data(receiver))
    session_append(receiver, entry_custom("gptr.usage", data))
  }
  invisible(row)
}

#' A charged assistant entry keeps accounting outside the projected message
#' @noRd
usage_message_entry = function(msg, row) {
  entry = entry_message(msg)
  entry$gptr = list(usage = usage_row_store(row))
  entry
}

#' Count identical canonical rows once; conflicting request identities fail closed
#' @noRd
usage_canonical_unique = function(rows) {
  seen = new.env(hash = TRUE, parent = emptyenv())
  out = list(usage_empty())
  for (row in rows) {
    row = usage_row_canonical(row)
    stored = usage_row_store(row)
    previous = get0(row$request_id, envir = seen, inherits = FALSE)
    if (!is.null(previous)) {
      if (!identical(previous, stored)) {
        usage_invalid("durable usage duplicate", "one identical canonical row per request id")
      }
    } else {
      assign(row$request_id, stored, envir = seen)
      out[[length(out) + 1L]] = row
    }
  }
  out = do.call(rbind, out)
  out$started = .POSIXct(as.numeric(out$started), tz = "UTC")
  rownames(out) = NULL
  out
}

#' The usage rows of a session and its children, one per request, as a `gptr_usage` listing with
#' attribute `totals` (usage_totals())
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

#' Mark the leading components of a request as cached, up to the reported cache-read tokens; an
#' unknown cache read leaves the flags unknown (`NA`, IC-74)
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

#' Budget limits of a new run: the call's budget over the settings default for a root run, else
#' only the call's own share (the root's limits still apply through run_chain(), IC-66)
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
  if (!rlang::is_string(rid)) return(NULL)
  if (identical(rid, session_data(s)$id)) return(NULL)
  session_by_id(rid)
}

#' The shared budget pool of a root without a run of its own (a team or fan-out container that
#' P19 passes as `opts$root`), created once on its live record: one budget per top-level call
#' (IC-66); NULL when there is none
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
#' The known part, column by column (IC-74, D-025): `tokens` and `cost` are lower bounds when a
#' row is unknown; `turns` counts every request.
#' @noRd
run_used = function(run) {
  u = session_data(run$shell)$usage
  u = u[seq_len(nrow(u)) > run$usage_start, , drop = FALSE]
  usage_used(u[!duplicated(u$request_id), , drop = FALSE])
}

#' Tokens, cost and requests of usage rows, the known part column by column (IC-74, D-025)
#' @noRd
usage_used = function(u) {
  known = function(col) sum(u[[col]], na.rm = TRUE)
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  list(tokens = sum(vapply(cols, known, numeric(1L))), cost = known("cost"), turns = nrow(u))
}

#' Check the budgets that apply to a session's current run against run_used() (IC-74, D-025)
#' @param estimate Estimated input tokens of the next request.
#' @return `NULL` or `list(kind, budget, used, estimate)`.
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
    hit = function(kind) {
      list(kind = kind, budget = lim[[kind]], used = used[[kind]], estimate = estimate)
    }
    if (!is.null(lim$tokens) && used$tokens + estimate > lim$tokens) return(hit("tokens"))
    if (!is.null(lim$cost) && used$cost >= lim$cost) return(hit("cost"))
    if (!is.null(lim$turns) && used$turns >= lim$turns) return(hit("turns"))
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
  budget_unpriced(run)
  invisible(NULL)
}

#' Say once per call that its own cost limit is not enforced when a request since the run started
#' has an unknown cost, which counts nothing (D-025, D-251); the settings default says nothing, and
#' the runs sharing a team or fan-out pool say it once
#' @noRd
budget_unpriced = function(run) {
  lim = run$opts$budget$cost
  holder = run$budget_root %||% run
  if (is.null(lim) || "cost_unknown" %in% holder$near) return(invisible(NULL))
  u = session_data(run$shell)$usage
  u = u[seq_len(nrow(u)) > run$usage_start & is.na(u$cost), , drop = FALSE]
  if (!nrow(u)) return(invisible(NULL))
  holder$near = c(holder$near, "cost_unknown")
  model = paste0(u$provider[[1L]], "/", u$model[[1L]])
  gptr_inform(paste0("The cost budget of this call (", format_cost(lim), ") is not enforced: ",
                     model, " has no prices, so its cost is unknown; tokens and turns limits ",
                     "still apply."), "budget_unpriced", budget = lim, model = model)
}

# ---------------------------------------------------------------------------- usage (gptr_usage)

#' Token usage and cost
#'
#' Aggregates the usage rows of sessions (children included, each request counted once) and, for
#' `x = NULL`, of every live session of this process plus the process System 1 log. Reads only.
#'
#' Unknown usage stays unknown: a token count or cost that a provider did not report is `NA`,
#' never zero, so a group or total that includes it is `NA`. The footer prints such tokens as
#' `unknown` and adds the known cost to a count of the requests of unknown cost
#' (`$1.2000 + 1 request of unknown cost`). A known zero, such as the metered charge of a local
#' model, stays zero. Rows without a session, agent, model or route (process-level System 1
#' calls) form the `NA` group. On `claude-cli` models, billed to a Claude plan, the dollar figures
#' are the CLI's API-equivalent estimate, not a charge; cost limits use them.
#'
#' The detailed component ledger contains estimates; its sum can differ from provider-reported
#' usage. A run's token budget checks estimated next-input tokens and recorded usage before
#' requests; cost limits check recorded cost. The next output or an unknown final charge can
#' exceed a remaining allowance, so these stopping policies are not billing reservations.
#' Teams and fan-outs count child requests against their shared root budget.
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
#' session = peter("hi", model = gptr_fake_provider(list("hello")))
#' gptr_usage(session)
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
  # %in% and unnamed results: a group may be NA (System 1 rows); no na.rm: unknown stays unknown
  agg = function(col) {
    vapply(keys, function(k) sum(rows[[col]][group %in% k]), 1, USE.NAMES = FALSE)
  }
  df = data.frame(group = keys,
                  requests = vapply(keys, function(k) sum(group %in% k), 1L, USE.NAMES = FALSE),
                  input = agg("input"), output = agg("output"), cache_read = agg("cache_read"),
                  cache_write = agg("cache_write_5m") + agg("cache_write_1h"), cost = agg("cost"),
                  stringsAsFactors = FALSE)
  rownames(df) = NULL
  out = new_listing(df, "gptr_usage", footer = format_usage(rows))
  attr(out, "totals") = usage_totals(rows)
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
