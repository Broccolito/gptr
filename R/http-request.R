# Request specs to curl handles (contract 8.1-8.2, IC-64, INFRA-05).
#
# Every handle sets `pipewait = 0L` (since curl 6.1.0 PIPEWAIT serialises HTTP/1.1 streams on a
# shared pool; report 15 section 2.2 and its verification), `followlocation = 0L` (libcurl
# forwards custom key headers across origins on a redirect; IC-64) and `connecttimeout`. There
# is no total timeout: the reactor enforces the first-byte and idle timers itself after every
# curl::multi_run() (report 10a INFRA-05). libcurl's low-speed check is deliberately not set:
# it averages bytes per second, so `low_speed_limit = 1` ended a stream sending one byte every
# 10 s after `low_speed_time` seconds (measured with curl 7.0.0: "Operation too slow" at
# idle + 30 = 42 s), which INFRA-05's accept test forbids (see the plan's ambiguity 5). This
# file is the only place where secret handles are materialised (`secret_value(handle,
# origin)`, P03), and only for the request URL's own origin.

#' The origin (`scheme://host:port`) of a URL, lower-cased, default ports dropped
#' @return chr(1), or NA when the URL cannot be parsed.
#' @noRd
url_origin = function(url) {
  parts = http_url_parts(url)
  if (is.null(parts)) return(NA_character_)
  scheme = tolower(parts$scheme)
  host = tolower(parts$host)
  port = parts$port %||% ""
  if ((scheme == "https" && port == "443") || (scheme == "http" && port == "80")) port = ""
  paste0(scheme, "://", host, if (nzchar(port)) paste0(":", port))
}

#' Parse with the same URL rules used by the transport, without making a request
#' @noRd
http_url_parts = function(url) {
  if (!is.character(url) || length(url) != 1L || is.na(url) || !validUTF8(url) ||
      grepl("[[:cntrl:]\\\\]", url) ||
      !grepl("\\A[A-Za-z][A-Za-z0-9+.-]*://", url, perl = TRUE)) return(NULL)
  parts = tryCatch(curl::curl_parse_url(url), error = function(e) NULL)
  if (is.null(parts) || is.null(parts$host) || !nzchar(parts$host)) return(NULL)
  parts
}

#' A URL for logs: origin and path, never the query, fragment or credentials
#' @noRd
url_for_log = function(url) {
  o = url_origin(url)
  if (is.na(o)) return("")
  paste0(o, http_url_parts(url)$path %||% "")
}

#' Materialise header values for one origin
#'
#' A header value is chr(1), a `gptr_secret` handle, or an unnamed list of chr(1) pieces and
#' handles concatenated in order (for example `list("Bearer ", handle)`). Handles are turned
#' into values with `secret_value(handle, origin)`, which signals `gptr_error_untrusted` when
#' the handle is bound to another origin.
#' @return named list of chr(1)
#' @noRd
http_headers = function(headers, origin) {
  check_list(headers, "headers", named = TRUE)
  if (!length(headers)) return(list())
  token = "\\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\\z"
  if (anyNA(names(headers)) || any(!grepl(token, names(headers), perl = TRUE)) ||
      anyDuplicated(tolower(names(headers)))) {
    arg_abort(headers, "headers", "a list with unique HTTP header names")
  }
  piece = function(x) {
    if (inherits(x, "gptr_secret")) x = secret_value(x, origin)
    check_string(x, "header value", empty = TRUE)
    if (grepl("[\\r\\n]", x, perl = TRUE)) {
      arg_abort(x, "header value", "a string without CR or LF")
    }
    as_utf8(x)
  }
  out = vector("list", length(headers))
  names(out) = names(headers)
  for (i in seq_along(headers)) {
    v = headers[[i]]
    out[[i]] = if (is.list(v) && !inherits(v, "gptr_secret")) {
      if (!is.null(names(v))) arg_abort(v, "header value", "an unnamed list of pieces")
      paste(vapply(v, piece, ""), collapse = "")
    } else {
      piece(v)
    }
  }
  out
}

#' The connect, first-byte and idle timeouts of a request (seconds)
#'
#' Optional spec fields `connect_timeout`, `first_byte_timeout`, `idle_timeout` override the
#' options `gptr.connect_timeout` (20), `gptr.first_byte_timeout` (120), `gptr.idle_timeout` (90).
#' @noRd
http_timeouts = function(spec) {
  check_list(spec, "spec", named = TRUE)
  connect = spec[["connect_timeout"]] %||% gptr_opt("connect_timeout") %||% 20
  first_byte = spec[["first_byte_timeout"]] %||% gptr_opt("first_byte_timeout") %||% 120
  idle = spec[["idle_timeout"]] %||% gptr_opt("idle_timeout") %||% 90
  out = list(connect = connect, first_byte = first_byte, idle = idle)
  for (name in names(out)) {
    value = out[[name]]
    if (!is.numeric(value) || length(value) != 1L || is.na(value) || !is.finite(value) ||
        value <= 0 || (name == "connect" && value > .Machine$integer.max)) {
      arg_abort(value, paste0(name, "_timeout"), "a finite positive number in range")
    }
  }
  lapply(out, as.numeric)
}

#' Which layered timeout has expired, if any
#'
#' Before the first response byte the first-byte timer runs; afterwards the idle timer
#' (time since the last byte). There is no total timeout.
#' @return NULL or `list(class = chr, seconds = num(1), what = chr(1))`
#' @noRd
http_timeout_check = function(t_start, t_first, t_last, timeouts, now) {
  if (is.na(t_first)) {
    if (now - t_start > timeouts$first_byte) {
      return(list(class = c("timeout_first_byte", "timeout"), seconds = timeouts$first_byte,
                  what = "first byte"))
    }
    return(NULL)
  }
  if (now - t_last > timeouts$idle) {
    return(list(class = c("timeout_idle", "timeout"), seconds = timeouts$idle,
                what = "idle stream"))
  }
  NULL
}

#' When the next layered timeout of a transfer would expire (reactor clock)
#' @noRd
http_timeout_next = function(t_start, t_first, t_last, timeouts) {
  if (is.na(t_first)) t_start + timeouts$first_byte else t_last + timeouts$idle
}

#' Build the curl handle of a request spec
#'
#' `spec` is the `build()` result of an adapter (contract 8.1): `url`, `method` (default POST
#' with a body, else GET), `headers` (see http_headers()), `body` (chr(1) UTF-8 text or raw).
#' @return a `curl_handle`; errors (for example `gptr_error_untrusted`) are signalled.
#' @noRd
http_handle = function(spec) {
  check_list(spec, "spec", named = TRUE)
  url = spec[["url"]]
  origin = url_origin(url)
  if (is.na(origin) || !http_url_parts(url)$scheme %in% c("http", "https")) {
    arg_abort(url, "url", "an absolute HTTP or HTTPS URL")
  }
  method = spec[["method"]] %||% (if (is.null(spec[["body"]])) "GET" else "POST")
  check_string(method, "method")
  method = toupper(method)
  if (!grepl("\\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\\z", method, perl = TRUE)) {
    arg_abort(method, "method", "an HTTP method token")
  }
  body = spec[["body"]]
  if (!is.null(body) && !is.raw(body)) check_string(body, "body", empty = TRUE)
  t = http_timeouts(spec)
  h = curl::new_handle(url = url)
  curl::handle_setopt(h, pipewait = 0L, followlocation = 0L,
                      connecttimeout = as.integer(ceiling(t$connect)), tcp_keepalive = 1L,
                      nosignal = 1L)
  if (!is.null(body)) {
    if (!is.raw(body)) body = charToRaw(as_utf8(body))
    curl::handle_setopt(h, copypostfields = body)
    if (method != "POST") curl::handle_setopt(h, customrequest = method)
  } else if (method == "GET") {
    curl::handle_setopt(h, httpget = 1L)
  } else {
    curl::handle_setopt(h, customrequest = method)
  }
  # CUSTOMREQUEST changes only the verb; HEAD also needs bodyless response semantics.
  if (method == "HEAD") curl::handle_setopt(h, nobody = 1L)
  hdrs = http_headers(spec[["headers"]] %||% list(), origin)
  # an empty Expect header stops libcurl from waiting for "100 Continue" before large bodies
  if (!"expect" %in% tolower(names(hdrs))) hdrs[["Expect"]] = ""
  curl::handle_setheaders(h, .list = hdrs)
  h
}
