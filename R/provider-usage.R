# Usage records and dated prices (P05; contract 4.3/7.5 and IC-74).
# Omitted constructor fields retain legacy zeros. Explicit unknown observations
# are NA, and absent observed usage is not a known zero-token request.

#' Token fields in contract order
#' @noRd
usage_fields = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                 "reasoning", "images")

#' Signal an invalid usage or price field without including its value
#' @noRd
usage_invalid = function(arg, expected) {
  gptr_abort(paste0("Invalid ", arg, "; expected ", expected, "."),
             "invalid_argument", arg = arg, expected = expected)
}

#' A known nonnegative finite real scalar, or an explicitly unknown NA
#' @noRd
usage_num = function(x, default = 0, arg = "usage") {
  if (is.null(x)) return(default)
  if (length(x) == 1L && (is.numeric(x) || is.logical(x)) &&
      is.na(x) && !is.nan(x)) return(NA_real_)
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0) {
    usage_invalid(arg, "a finite nonnegative number or NA")
  }
  as.numeric(x)
}

#' Read a counter: omission is legacy zero, explicit NULL/NA is unknown
#' @noRd
usage_field = function(x, name) {
  if (!(name %in% names(x))) return(0)
  usage_num(x[[name]], default = NA_real_, arg = name)
}

#' Require a named record with unique fields
#' @noRd
usage_record_check = function(x, arg) {
  nm = names(x)
  if (!is.list(x) || (length(x) &&
      (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)))) {
    usage_invalid(arg, "a named list with unique fields")
  }
  invisible(NULL)
}

#' A cost record in USD, preserving unknown components
#' @noRd
cost_new = function(x = NULL) {
  x = x %||% list()
  usage_record_check(x, "cost")
  out = list(input = usage_field(x, "input"), output = usage_field(x, "output"),
             cache_read = usage_field(x, "cache_read"), cache_write = usage_field(x, "cache_write"))
  out$total = if ("total" %in% names(x)) {
    usage_field(x, "total")
  } else {
    usage_num(sum(unlist(out)), arg = "cost.total")
  }
  out
}

#' An entirely unknown cost, distinct from zero metered charge
#' @noRd
cost_unknown = function() {
  list(input = NA_real_, output = NA_real_, cache_read = NA_real_,
       cache_write = NA_real_, total = NA_real_)
}

#' Build a usage record with zeros for omitted legacy fields and NA for unknowns
#' @noRd
usage_new = function(...) {
  x = list(...)
  known = c(usage_fields, "total", "cost", "estimated")
  nm = names(x) %||% rep("", length(x))
  if (anyNA(nm) || any(!nm %in% known) || anyDuplicated(nm)) {
    gptr_abort("usage_new() requires unique known field names.", "internal", detail = "usage_new")
  }
  u = stats::setNames(lapply(usage_fields, function(k) usage_field(x, k)), usage_fields)
  u$total = if ("total" %in% nm) {
    usage_field(x, "total")
  } else {
    usage_num(usage_prompt_tokens(u) + u[["output"]], arg = "total")
  }
  u$cost = if ("cost" %in% nm && is.null(x[["cost"]])) cost_unknown() else cost_new(x[["cost"]])
  estimated = x[["estimated"]] %||% FALSE
  if (!is.logical(estimated) || length(estimated) != 1L || is.na(estimated)) {
    usage_invalid("estimated", "a non-missing logical scalar")
  }
  u$estimated = estimated
  u
}

#' Normalise observed usage; an absent observation has unknown counters and cost
#' @noRd
usage_as = function(usage) {
  usage = usage %||% list()
  usage_record_check(usage, "usage")
  if (!any(usage_fields %in% names(usage))) {
    fields = stats::setNames(as.list(rep(NA_real_, length(usage_fields))), usage_fields)
    if ("total" %in% names(usage)) fields["total"] = usage["total"]
    fields$cost = usage[["cost"]] %||% cost_unknown()
    fields$estimated = usage[["estimated"]] %||% FALSE
    return(do.call(usage_new, fields))
  }
  keep = intersect(names(usage), c(usage_fields, "total", "cost", "estimated"))
  do.call(usage_new, usage[keep])
}

#' Prompt-side tokens selecting the context price tier
#' @noRd
usage_prompt_tokens = function(u) {
  u[["input"]] + u[["cache_read"]] + u[["cache_write_5m"]] + u[["cache_write_1h"]]
}

#' One finite ISO date (or Date scalar)
#' @noRd
price_date = function(x, arg = "from") {
  if (inherits(x, "Date") && length(x) == 1L && is.finite(as.numeric(x))) return(x)
  if (!is.character(x) || length(x) != 1L || is.na(x) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) {
    usage_invalid(arg, "one valid YYYY-MM-DD date")
  }
  date = tryCatch(as.Date(x, format = "%Y-%m-%d"), error = function(e) as.Date(NA))
  if (is.na(date) || !identical(format(date, "%Y-%m-%d"), x)) {
    usage_invalid(arg, "one valid YYYY-MM-DD date")
  }
  date
}

#' Validate tier labels and return premium thresholds in tokens
#' @noRd
price_threshold = function(tier) {
  pattern = "^(>|<=)([0-9]+(\\.[0-9]+)?)k$"
  if (!is.character(tier) || anyNA(tier) || any(!(tier == "default" | grepl(pattern, tier)))) {
    usage_invalid("tier", "default, <=Nk, or >Nk with a finite nonnegative threshold")
  }
  out = rep(NA_real_, length(tier))
  numeric_tiers = tier != "default"
  values = as.numeric(sub("^(>|<=)(.*)k$", "\\2", tier[numeric_tiers])) * 1000
  if (any(!is.finite(values))) usage_invalid("tier", "a finite threshold")
  out[numeric_tiers] = values
  out[!startsWith(tier, ">")] = NA_real_
  out
}

#' A validated dated price table; absent rates are unknown
#' @noRd
prices_df = function(x) {
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  rows = if (is.data.frame(x)) {
    lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
  } else {
    x %||% list()
  }
  if (!is.list(rows)) usage_invalid("prices", "a list of price records or a data frame")
  out = data.frame(from = as.Date(character()), tier = character(), stringsAsFactors = FALSE)
  for (k in cols) out[[k]] = numeric()
  for (row in rows) {
    usage_record_check(row, "price")
    date = price_date(if ("from" %in% names(row)) row[["from"]] else "2000-01-01")
    tier = if ("tier" %in% names(row)) row[["tier"]] else "default"
    if (length(tier) != 1L) usage_invalid("tier", "one price tier label")
    price_threshold(tier)
    entry = data.frame(from = date, tier = tier, stringsAsFactors = FALSE)
    for (k in cols) entry[[k]] = usage_num(row[[k]], default = NA_real_, arg = paste0("price.", k))
    out = rbind(out, entry)
  }
  threshold = price_threshold(out$tier)
  identity = paste(out$from, ifelse(is.na(threshold), "base", threshold))
  if (anyDuplicated(identity)) usage_invalid("prices", "unique date/tier thresholds")
  rownames(out) = NULL
  out
}

#' Rates per million tokens, with documented defaults for unspecified cache rates
#' @noRd
price_rates = function(row) {
  num = function(k) usage_num(row[[k]], default = NA_real_, arg = paste0("price.", k))
  input = num("input")
  cache = function(k, multiplier) {
    rate = num(k)
    usage_num(if (is.na(rate)) input * multiplier else rate, arg = paste0("price.", k))
  }
  list(input = input, output = num("output"), cache_read = cache("cache_read", 0.1),
       cache_write_5m = cache("cache_write_5m", 1.25),
       cache_write_1h = cache("cache_write_1h", 2))
}

#' The latest price set in force, selecting the highest exceeded prompt threshold
#'
#' Unknown prompt size selects a row only when every possible tier has identical
#' effective rates and a base tier covers small prompts. Future rates are not
#' evidence of the charge before their effective date.
#' @noRd
price_select = function(prices, prompt_tokens, when = Sys.Date()) {
  when = price_date(when, "when")
  prompt_tokens = usage_num(prompt_tokens, default = NA_real_, arg = "prompt_tokens")
  prices = prices_df(prices)
  cand = prices[prices$from <= when, , drop = FALSE]
  if (!nrow(cand)) return(NULL)
  cand = cand[cand$from == max(cand$from), , drop = FALSE]
  threshold = price_threshold(cand$tier)
  base = which(is.na(threshold))
  if (is.na(prompt_tokens)) {
    if (!length(base)) return(NULL)
    rates = lapply(seq_len(nrow(cand)), function(i) price_rates(cand[i, , drop = FALSE]))
    if (!all(vapply(rates, identical, NA, rates[[1L]]))) return(NULL)
    return(cand[base, , drop = FALSE])
  }
  above = which(!is.na(threshold) & prompt_tokens > threshold)
  i = if (length(above)) above[which.max(threshold[above])] else base
  if (!length(i)) NULL else cand[i, , drop = FALSE]
}

#' Metered charge for one token component, retaining unknown measurements
#' @noRd
usage_charge = function(tokens, rate) {
  # A declared zero rate proves zero metered API charge even without token usage.
  # This does not estimate compute or energy cost, or infer pricing from a URL.
  if (isTRUE(rate == 0) || isTRUE(tokens == 0)) return(0)
  usage_num(tokens / 1e6 * rate, arg = "cost")
}

#' Fill metered API cost from the model's dated price evidence
#' @noRd
usage_cost = function(usage, model, when = Sys.Date()) {
  u = usage_as(usage)
  row = price_select(model[["prices"]], usage_prompt_tokens(u), when)
  if (is.null(row)) {
    u$cost = cost_unknown()
    return(u)
  }
  rates = price_rates(row)
  costs = lapply(names(rates), function(k) usage_charge(u[[k]], rates[[k]]))
  names(costs) = names(rates)
  u$cost = cost_new(list(input = costs$input, output = costs$output,
                         cache_read = costs$cache_read,
                         cache_write = costs$cache_write_5m + costs$cache_write_1h))
  u
}

# ---- Usage rows, roll-up and the process System 1 log (P05 Task 9) ------------------------------
# Contract sections 4.3, 5.12 and 7.5; architecture section 5.5 (INFRA-20); IC-74: an unknown
# observation or an unknown price stays NA in the row and in every roll-up sum.

#' Character columns of a usage row
#' @noRd
usage_chr_columns = c("request_id", "session", "agent", "parent_id", "provider", "model", "route",
                      "tier", "stop_reason")

#' Numeric columns of a usage row (known values finite and nonnegative, unknown values NA)
#' @noRd
usage_num_columns = c(usage_fields, "cost", "seconds", "multiplier")

#' One string, or NA when `na` (a logical NA counts as missing); NULL gives `default`
#' @noRd
usage_chr1 = function(x, arg, default = NA_character_, na = TRUE) {
  if (is.null(x)) return(default)
  if (na && is.logical(x) && length(x) == 1L && is.na(x)) return(NA_character_)
  ok = is.character(x) && length(x) == 1L && (if (is.na(x)) na else nzchar(x))
  if (!ok) usage_invalid(arg, if (na) "one non-empty string or NA" else "one non-empty string")
  x
}

#' A POSIXct request start from a POSIXct, epoch seconds or NULL (now)
#' @noRd
usage_time = function(x) {
  if (is.null(x)) return(Sys.time())
  if (inherits(x, "POSIXlt")) x = as.POSIXct(x)
  if (inherits(x, "POSIXct")) {
    if (length(x) == 1L && is.finite(as.numeric(x))) return(x)
  } else if (is.numeric(x) && length(x) == 1L && is.finite(x)) {
    return(.POSIXct(as.numeric(x)))
  }
  usage_invalid("started", "one finite POSIXct time or epoch seconds")
}

#' A zero-row usage table with the contract section 4.3 columns and types
#' @noRd
usage_empty = function() {
  data.frame(request_id = character(), session = character(), agent = character(),
             parent_id = character(), provider = character(), model = character(),
             route = character(), input = numeric(), output = numeric(),
             cache_read = numeric(), cache_write_5m = numeric(), cache_write_1h = numeric(),
             reasoning = numeric(), images = numeric(), cost = numeric(), tier = character(),
             stop_reason = character(), started = .POSIXct(numeric()), seconds = numeric(),
             estimated = logical(), multiplier = numeric(), stringsAsFactors = FALSE)
}

#' Validate usage rows (contract section 4.3) and return their columns in contract order
#' @noRd
usage_rows_check = function(rows, arg) {
  cols = names(usage_empty())
  if (!is.data.frame(rows) || !all(cols %in% names(rows))) {
    usage_invalid(arg, "a data frame of usage rows built by usage_row()")
  }
  col = function(k) paste0(arg, "$", k)
  for (k in usage_chr_columns) {
    if (!is.character(rows[[k]])) usage_invalid(col(k), "a character column")
  }
  if (anyNA(rows$request_id) || !all(nzchar(rows$request_id))) {
    usage_invalid(col("request_id"), "non-empty request ids")
  }
  if (!all(rows$route %in% msg_routes)) {
    usage_invalid(col("route"), paste0("one of ", paste(msg_routes, collapse = ", ")))
  }
  for (k in usage_num_columns) {
    x = rows[[k]]
    if (!is.numeric(x) || any(is.nan(x)) || any(!is.na(x) & (!is.finite(x) | x < 0))) {
      usage_invalid(col(k), "finite nonnegative numbers or NA")
    }
  }
  if (!inherits(rows$started, "POSIXct") || !all(is.finite(as.numeric(rows$started)))) {
    usage_invalid(col("started"), "finite POSIXct times")
  }
  if (!is.logical(rows$estimated) || anyNA(rows$estimated)) {
    usage_invalid(col("estimated"), "TRUE or FALSE")
  }
  out = rows[cols]
  rownames(out) = NULL
  out
}

#' The cost a plan CLI reported itself (`total_cost_usd`, contract section 8.5)
#'
#' Read from the message's own usage record: a reported `cost$total` (zero included) is kept, a
#' missing one is unknown (IC-74), and so is the cost of an estimated record, since `estimated`
#' means the provider reported nothing (contract section 4.3). A canonical record from
#' `usage_new()` always carries a total (the legacy zero when `cost` was omitted), so an adapter
#' with no reported cost passes `cost = NULL`.
#' @noRd
usage_reported_cost = function(usage) {
  if (is.list(usage) && isTRUE(usage[["estimated"]])) return(NA_real_)
  cost = if (is.list(usage) && "cost" %in% names(usage)) usage[["cost"]]
  if (!is.list(cost) || !("total" %in% names(cost))) return(NA_real_)
  usage_num(cost[["total"]], default = NA_real_, arg = "cost.total")
}

#' One usage row (contract section 4.3) for an assistant message
#'
#' The model record is resolved from the message's provider and model and checked with the same
#' pure, no-I/O request preflight (`provider_preflight()`), so a local model whose current
#' discovery evidence establishes local execution is priced at its zero metered charge whichever
#' catalog name (bare or tagged) reached it (07-local-ollama.md section 5); a record the
#' preflight refuses (no current evidence, as in a rebuild) keeps its catalog prices. The cost is
#' recomputed from the dated price tier in force on the request date (UTC), except on the
#' `plan-cli` route, whose cost is the CLI's own estimate (`total_cost_usd`, 04 section 8.5).
#' Unknown tokens, an unresolved model, a request before the first known price and a missing CLI
#' estimate give `NA` (IC-74); `tier` is `NA` when no price tier applies. Scalar arguments are
#' validated so that one call never recycles into several accounting rows.
#' @noRd
usage_row = function(msg, session, agent, parent_id, started, seconds, multiplier) {
  check_list(msg, "msg")
  u = usage_as(msg[["usage"]])
  route = msg[["route"]] %||% "api"
  if (!is.character(route) || length(route) != 1L || !(route %in% msg_routes)) {
    usage_invalid("route", paste0("one of ", paste(msg_routes, collapse = ", ")))
  }
  provider = usage_chr1(msg[["provider"]], "provider")
  model_id = usage_chr1(msg[["model"]], "model")
  request_id = usage_chr1(msg[["request_id"]], "request_id", default = id_new("q", 12L),
                          na = FALSE)
  stop_reason = usage_chr1(msg[["stop_reason"]], "stop_reason")
  session = usage_chr1(session, "session")
  agent = usage_chr1(agent, "agent", default = "main", na = FALSE)
  parent_id = usage_chr1(parent_id, "parent_id")
  started = usage_time(started)
  seconds = usage_num(seconds, default = NA_real_, arg = "seconds")
  multiplier = usage_num(multiplier, default = 1, arg = "multiplier")
  model = NULL
  if (!is.na(provider) && !is.na(model_id)) {
    model = model_resolve(paste0(provider, "/", model_id), strict = FALSE)
  }
  if (!is.null(model)) {
    p = provider_get(model[["provider"]])
    model = tryCatch(provider_preflight(model, p), gptr_error = function(e) model)
  }
  when = as.Date(started, tz = "UTC")
  sel = if (!is.null(model)) price_select(model[["prices"]], usage_prompt_tokens(u), when)
  cost = if (identical(route, "plan-cli")) {
    usage_reported_cost(msg[["usage"]])
  } else if (is.null(model)) {
    NA_real_
  } else {
    usage_cost(u, model, when)$cost$total
  }
  data.frame(request_id = request_id, session = session, agent = agent, parent_id = parent_id,
             provider = provider, model = model_id, route = route,
             input = u[["input"]], output = u[["output"]], cache_read = u[["cache_read"]],
             cache_write_5m = u[["cache_write_5m"]], cache_write_1h = u[["cache_write_1h"]],
             reasoning = u[["reasoning"]], images = u[["images"]], cost = cost,
             tier = if (is.null(sel)) NA_character_ else sel$tier, stop_reason = stop_reason,
             started = started, seconds = seconds, estimated = isTRUE(u[["estimated"]]),
             multiplier = multiplier, stringsAsFactors = FALSE)
}

#' Append usage rows to the process System 1 accounting log (append-only; `the$s1_log`)
#'
#' The rows are validated before the log changes; returns the number of rows appended,
#' invisibly.
#' @noRd
usage_log_append = function(row) {
  row = usage_rows_check(row, "row")
  if (!nrow(row)) return(invisible(0L))
  rows = the$s1_log %||% list()
  rows[[length(rows) + 1L]] = row
  the$s1_log = rows
  invisible(nrow(row))
}

#' The process System 1 accounting log as one usage table
#'
#' Rows appended since the last read are bound once and kept bound, so repeated reads do not
#' re-bind the whole log; the content and order of the log never change.
#' @noRd
usage_log = function() {
  rows = the$s1_log
  if (!length(rows)) return(usage_empty())
  if (length(rows) > 1L) {
    out = do.call(rbind, unname(rows))
    rownames(out) = NULL
    the$s1_log = list(out)
  }
  the$s1_log[[1L]]
}

#' The root session of each distinct session in usage rows
#'
#' A session's parent is the `parent_id` its rows record (an `NA` row records none, as in P13's
#' System 1 rows of a child session; two different recorded parents are refused); a parent
#' without rows of its own is a root, as is a session with no recorded parent. Cyclic ancestry
#' is refused.
#' @noRd
usage_roots = function(session, parent_id) {
  known = !is.na(session)
  ids = unique(session[known])
  parents = split(parent_id[known], factor(session[known], levels = ids))
  parent = vapply(parents, function(p) {
    p = unique(p[!is.na(p)])
    if (length(p) > 1L) usage_invalid("rows$parent_id", "at most one parent_id per session")
    if (length(p)) p else NA_character_
  }, NA_character_, USE.NAMES = FALSE)
  names(parent) = ids
  vapply(ids, function(s) {
    seen = s
    repeat {
      p = parent[[s]]
      if (is.na(p)) return(s)
      if (!(p %in% ids)) return(p)
      if (p %in% seen) usage_invalid("rows$parent_id", "an acyclic session ancestry")
      seen = c(seen, p)
      s = p
    }
  }, NA_character_)
}

#' Roll usage rows up to their root sessions (INFRA-20)
#'
#' Each row's session is followed through the `session -> parent_id` pairs of `rows` to its
#' root (a parent without rows of its own is a root), so child sessions (team members, fan-out
#' elements, nested calls) are charged to the session that started them. Rows without a session
#' (process-level System 1 calls) form the `NA` group. Returns one row per root in order of first
#' appearance, with the columns of the aggregated `gptr_usage` view (04 section 5.12): `group`,
#' `requests`, `input`, `output`, `cache_read`, `cache_write`, `cost`. An unknown (`NA`) value
#' makes its group's sum unknown (IC-74).
#' @noRd
usage_rollup = function(rows) {
  rows = usage_rows_check(rows %||% usage_empty(), "rows")
  sums = c("input", "output", "cache_read", "cache_write", "cost")
  if (!nrow(rows)) {
    out = data.frame(group = character(), requests = integer(), stringsAsFactors = FALSE)
    for (k in sums) out[[k]] = numeric()
    return(out)
  }
  roots = usage_roots(rows$session, rows$parent_id)
  root = unname(roots[match(rows$session, names(roots))])
  groups = unique(root)
  key = match(root, groups)
  m = rowsum(cbind(input = rows$input, output = rows$output, cache_read = rows$cache_read,
                   cache_write = rows$cache_write_5m + rows$cache_write_1h, cost = rows$cost),
             key, reorder = FALSE)
  out = data.frame(group = groups, requests = tabulate(key, length(groups)),
                   stringsAsFactors = FALSE)
  for (k in sums) out[[k]] = unname(m[, k])
  out
}
