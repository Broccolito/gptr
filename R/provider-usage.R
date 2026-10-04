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
