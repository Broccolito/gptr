# OAuth 2.1 with PKCE S256 and credential login (REQ-15, REQ-30; contract 6.2, 7.18; IC-71).
#
# Adapted from dev/research/03-pi-ai-providers-auth.md section 5.6 (PKCE checked against the
# RFC 7636 appendix B vector, the loopback receiver, the double-checked locked refresh) and
# dev/research/16-mcp-skills-plugins.md sections 2.9, 3.5 and 5.15 (RFC 9728 discovery, the
# authorization-server metadata order, the iss rule). Report 16's verification-log fixes are
# applied: metadata without code_challenge_methods_supported, or without S256, is refused (#7),
# and the redirect is read by gptr's own listener or paste reader so that `iss` survives (#17).
# httr2 is never used (conventions section 8); every transfer runs on P04's reactor, whose
# handles set followlocation = 0L (IC-64). Layer L0: the MCP layer reaches gptr_login("mcp:")
# through the callback it registers with oauth_hooks_set() at load (architecture 2.2).
# Credentials: refresh tokens and API keys live in P03's credential store (auth.json, 0600);
# access tokens live only in the vault (secret "auth:<key>:access", bound to the resource's
# origin) with their expiry in the store record (contract 11.8).

# ---- URLs, headers, forms (pure) -----------------------------------------------------------

#' Split a URL into scheme, host, port, path and query (the query without "?")
#' @noRd
url_parts = function(url) {
  pat = "^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)([^?#]*)(\\?[^#]*)?"
  url = as.character(url %||% "")
  m = if (length(url) == 1L && !is.na(url)) regmatches(url, regexec(pat, url))[[1L]]
  if (!length(m)) {
    gptr_abort("A URL must start with a scheme such as https://.", "invalid_argument",
               arg = "url", expected = "an absolute URL")
  }
  hostport = sub("^.*@", "", m[3L])
  if (startsWith(hostport, "[")) {
    host = sub("^(\\[[^]]*\\]).*$", "\\1", hostport)
    port = sub("^\\[[^]]*\\]:?", "", hostport)
  } else {
    host = sub(":.*$", "", hostport)
    port = if (grepl(":", hostport, fixed = TRUE)) sub("^[^:]*:", "", hostport) else ""
  }
  list(scheme = tolower(m[2L]), host = tolower(host), port = port, path = m[4L],
       query = sub("^\\?", "", m[5L]))
}

#' One header value from a named list or vector (case-insensitive), or NULL
#' @noRd
hdr_value = function(headers, name) {
  if (is.null(headers) || !length(headers) || is.null(names(headers))) return(NULL)
  i = match(tolower(name), tolower(names(headers)))
  if (is.na(i)) return(NULL)
  as.character(unlist(headers[[i]]))[1L]
}

#' An application/x-www-form-urlencoded body; NULL fields are dropped
#'
#' Every byte outside the RFC 3986 unreserved set is percent-encoded from the value's UTF-8
#' bytes (curl_escape(); utils::URLencode() would return a value that already contains "%xx"
#' unchanged).
#' @noRd
form_encode = function(fields) {
  fields = fields[!vapply(fields, is.null, NA)]
  if (!length(fields)) return("")
  vals = vapply(fields, function(v) curl::curl_escape(as_utf8(as.character(v)[1L])), "")
  paste(paste0(curl::curl_escape(as_utf8(names(fields))), "=", vals), collapse = "&")
}

#' Parse a query string into a named list of UTF-8 strings
#'
#' Each pair is split at its first "=" (a value keeps its own "=" padding); "+" is a space; a
#' malformed percent sequence is kept as typed (pasted redirects come from the user).
#' @noRd
query_parse = function(q) {
  q = sub("^\\?", "", as.character(q %||% "")[1L])
  if (is.na(q) || !nzchar(q)) return(json_obj())
  pairs = strsplit(q, "&", fixed = TRUE)[[1L]]
  pairs = pairs[nzchar(pairs)]
  if (!length(pairs)) return(json_obj())
  dec = function(x) as_utf8(curl::curl_unescape(gsub("+", " ", x, fixed = TRUE)))
  keys = dec(sub("=.*$", "", pairs))
  vals = dec(sub("^[^=]*=", "", pairs))
  vals[!grepl("=", pairs, fixed = TRUE)] = ""
  stats::setNames(as.list(vals), keys)
}

#' base64url without padding (RFC 4648 section 5)
#' @noRd
b64url = function(bytes) {
  x = gsub("[\r\n]", "", jsonlite::base64_enc(as.raw(bytes)))
  chartr("+/", "-_", sub("=+$", "", x))
}

#' Parse the parameters of a WWW-Authenticate challenge (RFC 7235: quoted strings or tokens;
#' parameter names are case-insensitive and returned in lower case)
#' @noRd
oauth_parse_challenge = function(h) {
  h = as.character(h %||% "")[1L]
  if (is.na(h) || !nzchar(h)) return(list())
  pat = "([A-Za-z0-9_.-]+)[ \t]*=[ \t]*(\"([^\"\\\\]|\\\\.)*\"|[^ \t,\"]+)"
  kv = regmatches(h, gregexpr(pat, h))[[1L]]
  if (!length(kv)) return(list())
  keys = tolower(sub("[ \t]*=.*$", "", kv))
  vals = sub("^[^=]*=[ \t]*", "", kv)
  quoted = startsWith(vals, "\"")
  vals[quoted] = gsub("\\\\(.)", "\\1", substr(vals[quoted], 2L, nchar(vals[quoted]) - 1L))
  stats::setNames(as.list(vals), keys)
}

#' Refuse authorization-server metadata for another issuer, or without S256 PKCE (IC-71)
#' @noRd
oauth_check_metadata = function(meta, issuer) {
  refuse = function(why) {
    gptr_abort(paste0("The authorization server ", issuer, " ", why, "; gptr refuses to sign in."),
               "untrusted", what = "authorization server metadata", path = NA_character_,
               origin = issuer)
  }
  if (!is.list(meta) || !identical(meta[["issuer"]], issuer)) {
    refuse("returned metadata for another issuer")
  }
  methods = unlist(meta[["code_challenge_methods_supported"]])
  if (is.null(methods)) {
    refuse("does not declare PKCE support (code_challenge_methods_supported is missing)")
  }
  if (!"S256" %in% methods) refuse("does not support S256 PKCE")
  endpoint_ok = function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  if (!endpoint_ok(meta[["authorization_endpoint"]]) || !endpoint_ok(meta[["token_endpoint"]])) {
    refuse("does not name an authorization and a token endpoint")
  }
  invisible(meta)
}

#' The authorization URL of the code flow (state, PKCE S256, RFC 8707 resource)
#' @noRd
oauth_authorize_url = function(meta, client_id, redirect_uri, scope, state, challenge,
                               resource = NULL) {
  scope = paste(scope[!is.na(scope) & nzchar(scope)], collapse = " ")
  q = form_encode(list(response_type = "code", client_id = client_id, redirect_uri = redirect_uri,
                       scope = if (nzchar(scope)) scope, state = state,
                       code_challenge = challenge, code_challenge_method = "S256",
                       resource = resource))
  endpoint = meta[["authorization_endpoint"]]
  sep = if (grepl("?", endpoint, fixed = TRUE)) "&" else "?"
  paste0(endpoint, sep, q)
}

#' Validate a redirect (a full URL, or the pasted query) and return the authorization code: the
#' redirect target, the state and, per RFC 9207, `iss` are checked before the code is redeemed
#' @noRd
oauth_parse_redirect = function(input, redirect_uri, state, issuer, iss_supported = FALSE) {
  input = trimws(as.character(input %||% ""))
  untrusted = function(why) {
    gptr_abort(paste0("The sign-in redirect was refused: ", why, "."), "untrusted",
               what = "OAuth redirect", path = NA_character_, origin = issuer)
  }
  if (!length(input) || is.na(input[1L]) || !nzchar(input[1L])) untrusted("nothing was received")
  input = input[1L]
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", input)) {
    got = url_parts(input)
    want = url_parts(redirect_uri)
    keys = c("scheme", "host", "port", "path")
    if (!identical(got[keys], want[keys])) {
      untrusted("it went to another address than the one gptr registered")
    }
    q = query_parse(got$query)
  } else {
    q = query_parse(input)
  }
  if (!is.null(q[["error"]])) {
    gptr_abort(paste0("The sign-in was declined: ", q[["error_description"]] %||% q[["error"]],
                      "."),
               "provider", provider = issuer, status = NA_integer_, error_type = q[["error"]])
  }
  if (!identical(q[["state"]], state)) untrusted("the state parameter does not match")
  if (!is.null(q[["iss"]])) {
    if (!identical(q[["iss"]], issuer)) untrusted("it came from another issuer (iss)")
  } else if (isTRUE(iss_supported)) {
    untrusted("the issuer (iss) is missing although the server promises to send it")
  }
  code = q[["code"]]
  if (is.null(code) || !nzchar(code)) untrusted("it carries no authorization code")
  code
}

# ---- Suggests, randomness, PKCE, locks -----------------------------------------------------

#' Abort with gptr_error_missing_package unless a Suggests package loads; loading never moves
#' the user's .Random.seed (IC-61)
#' @noRd
oauth_need = function(pkg, feature) {
  ok = with_seed_preserved(requireNamespace(pkg, quietly = TRUE))
  if (!isTRUE(ok)) {
    gptr_abort(paste0(feature, " needs the '", pkg, "' package; install it with ",
                      "install.packages(\"", pkg, "\")."), "missing_package", package = pkg,
               feature = feature)
  }
  invisible(TRUE)
}

#' A cryptographically random hex string of n bytes (openssl; never R's RNG, IC-61)
#' @noRd
rand_hex = function(n) {
  oauth_need("openssl", "A random sign-in token")
  paste(as.character(openssl::rand_bytes(as.integer(n))), collapse = "")
}

#' A PKCE pair (RFC 7636, S256); 32 random bytes give a 43-character verifier
#' @noRd
pkce_new = function(verifier = NULL) {
  oauth_need("openssl", "OAuth sign-in")
  if (is.null(verifier)) verifier = b64url(openssl::rand_bytes(32L))
  list(verifier = verifier, challenge = b64url(openssl::sha256(charToRaw(verifier))),
       method = "S256")
}

#' Run fun() holding the short mkdir lock `<path>.lock/` (IC-71: pid and process creation time,
#' `tries` x `wait` seconds, a stale lock is broken with P03's auth_lock_stale()); used for the
#' OAuth refresh and for gptr's mcp.json
#' @noRd
oauth_lock_with = function(path, fun, tries = 50L, wait = 0.1) {
  lock = paste0(path, ".lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  got = FALSE
  for (i in seq_len(tries)) {
    if (dir.create(lock, showWarnings = FALSE)) {
      got = TRUE
      break
    }
    if (auth_lock_stale(lock)) {
      unlink(lock, recursive = TRUE, force = TRUE)
      next
    }
    Sys.sleep(wait)
  }
  if (!got) {
    gptr_abort(paste0("Could not lock ", basename(path), ": another R process holds the lock."),
               "timeout", seconds = tries * wait, what = "lock")
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  created = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA)
  writeLines(paste(Sys.getpid(), format(created, digits = 15)), file.path(lock, "pid"))
  fun()
}
