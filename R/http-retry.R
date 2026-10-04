# Retry classification and bounded backoff (INFRA-06, contract 8.2, IC-64).
#
# Rules from report 07 section 2.11 (Anthropic error table; the spend-cap 429 whose
# `error.details.error_code` is `enforced_spend_limit_reached` is never retried), report 02
# section 5.3 (`provider_retry_delay_ms()`, with the locale-independent `parse_http_date()`
# its verification log added) and report 10a INFRA-06. Jitter comes from the clock, never the
# RNG. Conditions are created, not signalled: they travel to `on_fail` callbacks.

#' Lower-case the names of a header list
#' @noRd
retry_headers = function(headers) {
  if (is.null(headers) || !length(headers)) return(list())
  h = as.list(headers)
  names(h) = tolower(names(h))
  h
}

#' One header value as chr(1), or NULL when absent or blank
#' @noRd
retry_header = function(headers, name) {
  v = headers[[name]]
  if (!is.character(v) || length(v) != 1L) return(NULL)
  if (is.na(v) || !nzchar(trimws(v))) return(NULL)
  trimws(v)
}

#' Parse an IMF-fixdate HTTP date without the locale
#'
#' `strptime("%a, %d %b ...")` follows LC_TIME and fails in a German locale (report 02
#' verification log), so months are matched against the English constant `month.abb`.
#' @return num(1) seconds since the epoch, or NA when unparsable.
#' @noRd
parse_http_date = function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(NA_real_)
  pat = "^[A-Za-z]{3}, ([0-9]{1,2}) ([A-Za-z]{3}) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$"
  m = regmatches(trimws(x), regexec(pat, trimws(x)))[[1L]]
  if (length(m) != 7L) return(NA_real_)
  mon = match(tolower(m[3L]), tolower(month.abb))
  if (is.na(mon)) return(NA_real_)
  t = ISOdatetime(as.integer(m[4L]), mon, as.integer(m[2L]), as.integer(m[5L]),
                  as.integer(m[6L]), as.integer(m[7L]), tz = "GMT")
  as.numeric(t)
}

#' Parse an RFC 3339 timestamp (rate-limit reset headers) without the locale
#' @return num(1) seconds since the epoch, or NA.
#' @noRd
parse_rfc3339 = function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(NA_real_)
  pat = paste0("^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2}):([0-9]{2})",
               "(\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$")
  m = regmatches(trimws(x), regexec(pat, trimws(x)))[[1L]]
  if (length(m) != 9L) return(NA_real_)
  t = as.numeric(ISOdatetime(as.integer(m[2L]), as.integer(m[3L]), as.integer(m[4L]),
                             as.integer(m[5L]), as.integer(m[6L]), as.integer(m[7L]), tz = "GMT"))
  if (nzchar(m[8L])) t = t + as.numeric(m[8L])
  off = m[9L]
  if (!toupper(off) %in% "Z") {
    sgn = if (startsWith(off, "-")) -1 else 1
    hm = as.integer(strsplit(substring(off, 2L), ":", fixed = TRUE)[[1L]])
    if (hm[1L] > 23L || hm[2L] > 59L) return(NA_real_)
    t = t - sgn * (hm[1L] * 3600 + hm[2L] * 60)
  }
  t
}

#' Parse an OpenAI-style duration ("1s", "6m0s", "20ms", "1h2m3.5s") or seconds
#' @return num(1) seconds, or NA.
#' @noRd
parse_duration = function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(NA_real_)
  x = trimws(x)
  num = suppressWarnings(as.numeric(x))
  if (!is.na(num)) return(if (is.finite(num) && num >= 0) num else NA_real_)
  m = regmatches(x, gregexpr("[0-9]+(\\.[0-9]+)?(ms|s|m|h)", x))[[1L]]
  if (!length(m) || !identical(paste(m, collapse = ""), x)) return(NA_real_)
  unit = sub("^[0-9.]+", "", m)
  val = as.numeric(sub("(ms|s|m|h)$", "", m))
  mult = c(ms = 0.001, s = 1, m = 60, h = 3600)[unit]
  total = sum(val * mult)
  if (is.finite(total)) total else NA_real_
}

#' The server-requested delay: `retry-after-ms`, then `retry-after` (seconds or HTTP date)
#' @return num(1) seconds, or NULL when absent or unparsable (exponential backoff applies).
#' @noRd
retry_after_seconds = function(headers) {
  headers = retry_headers(headers)
  ms = retry_header(headers, "retry-after-ms")
  if (!is.null(ms)) {
    v = suppressWarnings(as.numeric(ms))
    if (is.finite(v) && v >= 0) return(v / 1000)
  }
  ra = retry_header(headers, "retry-after")
  if (is.null(ra)) return(NULL)
  v = suppressWarnings(as.numeric(ra))
  if (is.finite(v) && v >= 0) return(v)
  d = parse_http_date(ra)
  if (is.na(d)) return(NULL)
  max(0, d - as.numeric(Sys.time()))
}

#' One validation entry of a FastAPI `detail` array as "loc: msg"
#' @noRd
retry_detail_entry = function(e) {
  if (!is.list(e)) return(paste(as.character(unlist(e)), collapse = " "))
  loc = paste(as.character(unlist(e[["loc"]])), collapse = ".")
  msg = as.character(unlist(e[["msg"]] %||% "invalid"))[1L]
  if (nzchar(loc)) paste0(loc, ": ", msg) else msg
}

#' The type, the service's message and the spend-cap code of an error body
#'
#' Shapes: `{"error": {"type"|"status", "message", "code", "details"}}` (Anthropic, OpenAI,
#' Gemini) and `{"error": "text"}`; then the FastAPI `detail` shapes of the TypeSafe System One
#' API (report 04a): `{"detail": {"error_type", "message"}}`, `{"detail": [{"loc", "msg"}]}`
#' (HTTP 422) and `{"detail": "text"}`; last a top-level `{"message", "error_type"}`.
#' @noRd
retry_body_error = function(body) {
  txt = if (is.null(body)) {
    ""
  } else if (is.raw(body)) {
    raw_to_utf8(body)
  } else {
    as_utf8(paste(body, collapse = "\n"))
  }
  out = list(type = "", message = "", code = "")
  if (!nzchar(txt)) return(out)
  j = tryCatch(json_decode(txt), error = function(e) NULL)
  err = if (is.list(j)) j[["error"]] else NULL
  det = if (is.list(j)) j[["detail"]] else NULL
  if (is.list(err)) {
    out$type = as.character(err[["type"]] %||% err[["status"]] %||% "")[1L]
    out$message = as.character(err[["message"]] %||% "")[1L]
    det = err[["details"]]
    code = if (is.list(det)) det[["error_code"]] else NULL
    out$code = as.character(code %||% err[["code"]] %||% "")[1L]
  } else if (is.character(err)) {
    out$message = err[1L]
  } else if (is.list(det) && !is.null(names(det))) {
    out$type = as.character(unlist(det[["error_type"]] %||% det[["type"]] %||% ""))[1L]
    out$message = as.character(unlist(det[["message"]] %||% det[["msg"]] %||% ""))[1L]
  } else if (is.list(det) && length(det)) {
    out$message = paste(vapply(det, retry_detail_entry, ""), collapse = "; ")
  } else if (is.character(det)) {
    out$message = det[1L]
  } else if (is.list(j) && is.character(j[["message"]])) {
    out$type = as.character(unlist(j[["error_type"]] %||% ""))[1L]
    out$message = j[["message"]][1L]
  }
  out[is.na(unlist(out))] = ""
  if (!nzchar(out$code) && identical(out$type, "enforced_spend_limit_reached")) {
    out$code = "enforced_spend_limit_reached"
  }
  out
}

#' Classify a failed attempt
#'
#' @param status HTTP status (int), or NA for a transport failure.
#' @param headers response headers (named list, names in any case).
#' @param body response body (raw or chr) of a non-2xx response.
#' @param curl_error the libcurl error message of a transport failure.
#' @return `list(retry = lgl(1), delay = num(1) | NULL, class = chr, retry_after = num(1) | NULL,
#'   message = chr(1))`: `delay` is the server-requested wait (`NULL` means exponential
#'   backoff); `class` holds the condition suffixes for `gptr_abort()`, most specific first.
#' @noRd
retry_classify = function(status, headers, body = NULL, curl_error = NULL) {
  headers = retry_headers(headers)
  max_delay = gptr_opt("max_retry_delay") %||% 60
  if (!is.numeric(max_delay) || length(max_delay) != 1L || !is.finite(max_delay) || max_delay < 0) {
    arg_abort(max_delay, "gptr.max_retry_delay", "a finite nonnegative number")
  }
  res = function(retry, class, message, delay = NULL, retry_after = NULL) {
    list(retry = retry, delay = delay, class = class, retry_after = retry_after,
         message = substr(redact(as_utf8(message), "persist"), 1L, 500L))
  }
  if (!is.null(curl_error)) {
    msg = as_utf8(paste(curl_error, collapse = " "))
    if (grepl("Operation too slow|Operation timed out", msg, ignore.case = TRUE)) {
      return(res(FALSE, c("timeout_idle", "timeout"), paste0("stream stalled: ", msg)))
    }
    connect = "Connection timed out|Connect timeout|Resolving timed out"
    if (grepl(connect, msg, ignore.case = TRUE)) {
      return(res(TRUE, c("timeout_connect", "timeout"), paste0("connection timed out: ", msg)))
    }
    return(res(TRUE, c("network", "provider"), paste0("network error: ", msg)))
  }
  status = suppressWarnings(as.integer(status))
  if (length(status) != 1L || is.na(status) || status <= 0L) {
    return(res(TRUE, c("network", "provider"), "network error: no HTTP status"))
  }
  be = retry_body_error(body)
  what = paste0("HTTP ", status, if (nzchar(be$type)) paste0(" ", be$type),
                if (nzchar(be$message)) paste0(": ", be$message))
  if (status >= 300L && status < 400L) {
    loc = retry_header(headers, "location")
    where = if (is.null(loc)) "another location" else url_origin(loc)
    return(res(FALSE, c("redirect", "provider"),
               paste0("HTTP ", status, " redirect to ", where,
                      " refused (redirects are never followed)")))
  }
  if (status %in% c(401L, 403L)) return(res(FALSE, c("auth", "provider"), what))
  if (status == 429L && identical(be$code, "enforced_spend_limit_reached")) {
    return(res(FALSE, c("spend_cap", "provider"), paste0(what, " (spend limit reached)")))
  }
  if (status %in% c(408L, 409L, 429L) || (status >= 500L && status < 600L)) {
    ra = retry_after_seconds(headers)
    if (!is.null(ra) && ra > max_delay) {
      return(res(FALSE, c("retry_after", "provider"),
                 paste0(what, "; the server asked to wait ", format(round(ra, 1)),
                        " s (retry-after), above gptr.max_retry_delay = ", max_delay, " s"),
                 retry_after = ra))
    }
    cls = if (status == 429L) {
      c("rate_limit", "provider")
    } else if (status >= 500L) {
      c("overloaded", "provider")
    } else {
      "provider"
    }
    return(res(TRUE, cls, what, delay = ra, retry_after = ra))
  }
  res(FALSE, "provider", what)
}

#' Exponential backoff with clock-derived jitter: 0.5 s * 2^(attempt - 1), capped at 8 s
#' @param attempt the number of the attempt that failed (1 for the first).
#' @noRd
retry_backoff = function(attempt) {
  if (!is.numeric(attempt) || length(attempt) != 1L || !is.finite(attempt) ||
      attempt < 1 || attempt != floor(attempt)) {
    arg_abort(attempt, "attempt", "a finite positive integer")
  }
  frac = (as.numeric(Sys.time()) * 1e6) %% 1000 / 1000
  (0.5 * 2^(min(attempt, 5) - 1)) * (1 - 0.25 * frac)
}

#' A classed, unsignalled transport condition built by gptr_abort()
#' @noRd
transport_error = function(message, class, ...) {
  tryCatch(gptr_abort(message, class, ...), gptr_error = function(e) e)
}

# ---- per-provider rate limiter (INFRA-21, IC-64) -------------------------------------------
# Header-derived request and token windows plus the provider record's static `rate` feed one
# state per provider, held in the reactor (`r$limits`, so System 1 admission is process-wide).
# Admission never waits: a blocked provider's transfers stay queued and the pump sleeps until
# ratelimit_next(). The static bucket is driven by `requests_per_s`; reactor_http() has no
# per-request token estimate, so `tokens_per_s` is kept with the rate but does not gate.

#' Validate a static provider rate before changing limiter state
#' @noRd
ratelimit_rate = function(rate) {
  if (is.null(rate)) return(NULL)
  nm = names(rate)
  if (!is.list(rate) || (length(rate) && (is.null(nm) || anyNA(nm) || anyDuplicated(nm) ||
      any(!nm %in% c("requests_per_s", "tokens_per_s"))))) {
    arg_abort(rate, "rate", "a named list of requests_per_s and tokens_per_s")
  }
  for (name in nm) {
    value = rate[[name]]
    if (is.null(value)) next
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value <= 0) {
      arg_abort(value, paste0("rate.", name), "a finite positive number or NULL")
    }
  }
  rate
}

#' Add a wait without overflowing the monotonic deadline
#' @noRd
ratelimit_deadline = function(now, delay) {
  if (!is.finite(delay) || delay > .Machine$double.xmax - now) return(.Machine$double.xmax)
  now + delay
}

#' The limiter state of one provider, created on first use
#' @noRd
ratelimit_get = function(provider) {
  check_string(provider, "provider", null = TRUE)
  lim = reactor_get()$limits
  key = if (is.null(provider)) "anonymous" else paste0("provider:", provider)
  st = lim[[key]]
  if (!is.null(st)) return(st)
  st = new.env(parent = emptyenv())
  st$req_remaining = NA_real_
  st$req_reset = NA_real_
  st$tok_remaining = NA_real_
  st$tok_reset = NA_real_
  st$token_windows = list()
  st$retry_at = NA_real_
  st$rate = if (is.null(provider)) NULL else ratelimit_static(provider)
  rps = st$rate$requests_per_s
  st$bucket = if (is.null(rps)) NA_real_ else max(1, rps)
  st$bucket_at = reactor_now()
  assign(key, st, envir = lim)
  st
}

#' The static rate of a provider record (IC-64), or NULL
#' @noRd
ratelimit_static = function(provider) {
  spec = tryCatch(registry_get("provider", provider), error = function(e) NULL)
  rate = if (is.list(spec)) spec[["rate"]] else NULL
  ratelimit_rate(rate)
}

#' Set or override the static rate of a provider (settings and catalog overrides, IC-64)
#' @param rate `list(requests_per_s = num(1) | NULL, tokens_per_s = num(1) | NULL)` or NULL.
#' @noRd
ratelimit_set = function(provider, rate) {
  check_string(provider, "provider")
  rate = ratelimit_rate(rate)
  st = ratelimit_get(provider)
  st$rate = rate
  rps = rate$requests_per_s
  st$bucket = if (is.null(rps)) NA_real_ else max(1, rps)
  st$bucket_at = reactor_now()
  invisible(st)
}

#' Seconds from now until a reset given as RFC 3339, a duration or seconds
#' @noRd
ratelimit_reset_in = function(x) {
  if (is.null(x)) return(NA_real_)
  t = parse_rfc3339(x)
  if (!is.na(t)) return(max(0, t - as.numeric(Sys.time())))
  parse_duration(x)
}

#' Feed response headers into a provider's bucket
#'
#' Reads `anthropic-ratelimit-{requests,tokens,input-tokens,output-tokens}-{remaining,reset}`,
#' `x-ratelimit-{remaining,reset}-{requests,tokens}` and `retry-after(-ms)`. A remaining count
#' without a reset is taken as a 60 s window.
#' @noRd
ratelimit_update = function(provider, headers) {
  check_string(provider, "provider", null = TRUE)
  if (is.null(provider)) return(invisible(NULL))
  h = retry_headers(headers)
  if (!length(h)) return(invisible(NULL))
  ra = retry_after_seconds(h)
  if (!is.null(ra) && ra > 0) {
    cap = gptr_opt("max_retry_delay") %||% 60
    if (!is.numeric(cap) || length(cap) != 1L || !is.finite(cap) || cap < 0) {
      arg_abort(cap, "gptr.max_retry_delay", "a finite nonnegative number")
    }
    ra = min(ra, cap)
  }
  st = ratelimit_get(provider)
  now = reactor_now()
  num = function(name) {
    v = retry_header(h, name)
    if (is.null(v)) return(NA_real_)
    n = suppressWarnings(as.numeric(v))
    if (is.finite(n)) max(0, floor(n)) else NA_real_
  }
  reset = function(name) ratelimit_reset_in(retry_header(h, name))
  req_rem = num("anthropic-ratelimit-requests-remaining")
  req_rst = reset("anthropic-ratelimit-requests-reset")
  if (is.na(req_rem)) {
    req_rem = num("x-ratelimit-remaining-requests")
    req_rst = reset("x-ratelimit-reset-requests")
  }
  if (!is.na(req_rem)) {
    st$req_remaining = req_rem
    st$req_reset = ratelimit_deadline(now, if (is.na(req_rst)) 60 else req_rst)
  }
  for (key in c("tokens", "input-tokens", "output-tokens", "x-tokens")) {
    remaining_header = if (key == "x-tokens") {
      "x-ratelimit-remaining-tokens"
    } else {
      paste0("anthropic-ratelimit-", key, "-remaining")
    }
    reset_header = if (key == "x-tokens") {
      "x-ratelimit-reset-tokens"
    } else {
      paste0("anthropic-ratelimit-", key, "-reset")
    }
    remaining = num(remaining_header)
    if (is.na(remaining)) next
    wait = reset(reset_header)
    st$token_windows[[key]] = list(remaining = remaining,
      reset = ratelimit_deadline(now, if (is.na(wait)) 60 else wait))
  }
  if (!is.null(ra) && ra > 0) {
    st$retry_at = max(st$retry_at, ratelimit_deadline(now, ra), na.rm = TRUE)
  }
  ratelimit_refresh(st, now)
  invisible(NULL)
}

#' Refill the static bucket (capacity: one second of requests, at least one request)
#' @noRd
ratelimit_refill = function(st, now) {
  rps = st$rate$requests_per_s
  if (is.null(rps) || is.na(st$bucket)) return(invisible(st))
  capacity = max(1, rps)
  elapsed = max(0, now - st$bucket_at)
  needed = max(0, capacity - st$bucket)
  st$bucket = if (elapsed >= needed / rps) capacity else st$bucket + elapsed * rps
  st$bucket_at = max(st$bucket_at, now)
  invisible(st)
}

#' Expire each observed window independently and refresh summary fields
#' @noRd
ratelimit_refresh = function(st, now) {
  if (!is.na(st$req_reset) && now >= st$req_reset) {
    st$req_remaining = NA_real_
    st$req_reset = NA_real_
  }
  if (!is.na(st$retry_at) && now >= st$retry_at) st$retry_at = NA_real_
  for (key in names(st$token_windows)) {
    if (now >= st$token_windows[[key]]$reset) st$token_windows[[key]] = NULL
  }
  windows = st$token_windows
  st$tok_remaining = if (length(windows)) {
    min(vapply(windows, function(x) x$remaining, 0))
  } else {
    NA_real_
  }
  blocked = Filter(function(x) x$remaining <= 0, windows)
  st$tok_reset = if (length(blocked)) {
    max(vapply(blocked, function(x) x$reset, 0))
  } else {
    NA_real_
  }
  ratelimit_refill(st, now)
  invisible(st)
}

#' May a new request start? Consume one request unit only on admission; never wait.
#' @return lgl(1)
#' @noRd
ratelimit_admit = function(provider) {
  st = ratelimit_get(provider)
  ratelimit_refresh(st, reactor_now())
  if (!is.na(st$retry_at)) return(FALSE)
  if (!is.na(st$req_remaining) && st$req_remaining < 1) return(FALSE)
  if (!is.na(st$tok_remaining) && st$tok_remaining <= 0) return(FALSE)
  if (!is.na(st$bucket)) {
    if (st$bucket < 1) return(FALSE)
    st$bucket = st$bucket - 1
  }
  if (!is.na(st$req_remaining)) st$req_remaining = st$req_remaining - 1
  TRUE
}

#' The earliest time every currently blocking admission constraint can clear
#' @noRd
ratelimit_next = function(provider) {
  st = ratelimit_get(provider)
  now = reactor_now()
  ratelimit_refresh(st, now)
  waits = numeric()
  if (!is.na(st$retry_at)) waits = c(waits, st$retry_at)
  if (!is.na(st$req_remaining) && st$req_remaining < 1 && !is.na(st$req_reset)) {
    waits = c(waits, st$req_reset)
  }
  if (!is.na(st$tok_remaining) && st$tok_remaining <= 0 && !is.na(st$tok_reset)) {
    waits = c(waits, st$tok_reset)
  }
  rps = st$rate$requests_per_s
  if (!is.null(rps) && !is.na(st$bucket) && st$bucket < 1) {
    waits = c(waits, ratelimit_deadline(now, (1 - st$bucket) / rps))
  }
  if (length(waits)) max(waits) else Inf
}
