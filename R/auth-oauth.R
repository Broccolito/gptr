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

#' Validate a redirect (a full URL, or with a state the pasted query) and return the code: the
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
    got = url_parse(input)
    if (is.null(got)) {
      gptr_abort("The sign-in redirect is not a valid URL.", "invalid_argument", arg = "input",
                 expected = "an absolute URL")
    }
    keys = c("scheme", "host", "port", "path")
    if (!identical(got[keys], url_parse(redirect_uri)[keys])) {
      untrusted("it went to another address than the one gptr registered")
    }
    q = query_parse(got$query)
  } else {
    # without a state, only the full address (its random path) ties the redirect to this sign-in
    if (is.null(state)) untrusted("it is not the full address gptr registered")
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

# ---- Suggests, randomness, PKCE ------------------------------------------------------------

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

# ---- HTTP on the reactor, discovery, client registration ---------------------------------------

#' One HTTP exchange on the reactor (followlocation = 0L, one attempt; IC-64): list(status, body,
#' error); a non-2xx answer arrives as `error` carrying its status
#' @noRd
oauth_http = function(url, method = "GET", headers = list(), body = NULL, timeout = 30) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$status = NA_integer_
  st$chunks = list()
  st$error = NULL
  spec = list(url = url, method = method, headers = headers, body = body,
              first_byte_timeout = timeout, idle_timeout = timeout)
  id = reactor_http(spec,
    on_bytes = function(raw) {
      st$chunks[[length(st$chunks) + 1L]] = raw
    },
    on_done = function(status, headers) {
      st$status = as.integer(status)
      st$done = TRUE
    },
    on_fail = function(cnd) {
      st$error = cnd
      st$status = cnd$status %||% NA_integer_
      st$done = TRUE
    },
    retry = list(max_attempts = 1L))
  if (!reactor_pump(until = function() st$done, slice_ms = 50L, timeout = timeout + 5)) {
    reactor_cancel(id)
    gptr_abort(paste0("No answer from ", url_origin(url), " within ", timeout, " s."), "timeout",
               seconds = timeout, what = "OAuth request")
  }
  body = if (length(st$chunks)) raw_to_utf8(do.call(c, st$chunks)) else ""
  list(status = st$status, body = body, error = st$error)
}

#' GET a JSON document; NULL unless the answer is a 2xx JSON object
#' @noRd
oauth_get_json = function(url) {
  r = tryCatch(oauth_http(url, "GET", headers = list(Accept = "application/json")),
               gptr_error = function(e) NULL)
  if (is.null(r) || !is.null(r$error)) return(NULL)
  x = tryCatch(json_decode(r$body), error = function(e) NULL)
  if (is.list(x) && length(x) && !is.null(names(x))) x else NULL
}

#' Validated authorization-server metadata of an issuer (RFC 8414 and OpenID discovery, in the
#' order of the MCP authorization specification; report 16 section 3.5)
#' @noRd
oauth_as_metadata = function(issuer) {
  base = url_origin(issuer)
  path = sub("/$", "", url_parse(issuer)$path %||% "")
  cands = if (nzchar(path)) {
    c(paste0(base, "/.well-known/oauth-authorization-server", path),
      paste0(base, "/.well-known/openid-configuration", path),
      paste0(base, path, "/.well-known/openid-configuration"))
  } else {
    c(paste0(base, "/.well-known/oauth-authorization-server"),
      paste0(base, "/.well-known/openid-configuration"))
  }
  for (m in cands) {
    meta = oauth_get_json(m)
    if (!is.null(meta)) return(oauth_check_metadata(meta, issuer))
  }
  gptr_abort(paste0("No OAuth metadata was found for the authorization server ", issuer, "."),
             "provider", provider = issuer, status = NA_integer_)
}

#' RFC 9728 discovery for a protected resource: the challenge's resource_metadata, then the two
#' well-known URLs; NULL when the resource publishes no metadata (it offers no OAuth). Metadata
#' whose `resource` is not the URL gptr asked about is refused (RFC 9728 section 3.3), so a
#' server cannot send the user to sign in for another resource.
#' @noRd
oauth_discover = function(resource_url, www_authenticate = NULL) {
  ch = oauth_parse_challenge(www_authenticate)
  base = url_origin(resource_url)
  path = sub("/$", "", url_parse(resource_url)$path %||% "")
  cands = unique(c(ch$resource_metadata,
                   if (nzchar(path)) paste0(base, "/.well-known/oauth-protected-resource", path),
                   paste0(base, "/.well-known/oauth-protected-resource")))
  prm = NULL
  for (p in cands) {
    prm = oauth_get_json(p)
    if (!is.null(prm) && length(prm$authorization_servers)) break
    prm = NULL
  }
  if (is.null(prm)) return(NULL)
  named = as.character(unlist(prm$resource))[1L]
  same = function(a, b) identical(sub("/$", "", a), sub("/$", "", b))
  if (!is.na(named) && !same(named, resource_url)) {
    gptr_abort(paste0("The protected-resource metadata of ", base, " names another resource (",
                      named, "); gptr refuses to sign in."), "untrusted",
               what = "protected resource metadata", path = NA_character_, origin = base)
  }
  issuer = as.character(unlist(prm$authorization_servers))[1L]
  scopes = if (!is.null(ch$scope)) {
    strsplit(ch$scope, " ", fixed = TRUE)[[1L]]
  } else {
    as.character(unlist(prm$scopes_supported))
  }
  list(resource = resource_url, issuer = issuer, metadata = oauth_as_metadata(issuer),
       scopes = scopes)
}

#' POST `fields` as a form (token endpoints) or as JSON; the decoded answer, which must carry the
#' character `field`, or gptr_error_provider
#' @noRd
oauth_post = function(url, fields, field, provider, form = FALSE, timeout = 30) {
  type = if (form) "application/x-www-form-urlencoded" else "application/json"
  r = oauth_http(url, "POST", headers = list(Accept = "application/json", `Content-Type` = type),
                 body = if (form) form_encode(fields) else json_encode(fields), timeout = timeout)
  x = if (is.null(r$error)) tryCatch(json_decode(r$body), error = function(e) NULL)
  if (!is.list(x) || !is.character(x[[field]])) {
    gptr_abort(paste0(url_origin(url), " refused the request (HTTP ", format(r$status), ")."),
               "provider", provider = provider, status = r$status)
  }
  x
}

#' Dynamic client registration (RFC 7591, application_type "native"); the client_id, or NULL
#' when the server has no registration endpoint
#' @noRd
oauth_register_client = function(meta, redirect_uri, scope) {
  if (!is.character(meta$registration_endpoint)) return(NULL)
  body = list(client_name = "gptr (R)", redirect_uris = I(redirect_uri),
              grant_types = I(c("authorization_code", "refresh_token")),
              response_types = I("code"), token_endpoint_auth_method = "none",
              application_type = "native")
  if (nzchar(scope)) body$scope = scope
  oauth_post(meta$registration_endpoint, body, "client_id", meta$issuer)$client_id
}

# ---- access tokens: the vault and the credential store -----------------------------------------

#' Epoch milliseconds
#' @noRd
oauth_now_ms = function() as.numeric(Sys.time()) * 1000

#' Expiry of a token response in epoch ms, five minutes early (Pi's skew)
#' @noRd
oauth_expiry = function(tok) {
  oauth_now_ms() + (as.numeric(tok$expires_in %||% 3600) - 300) * 1000
}

#' Vault name of the in-memory access token of a credential key
#' @noRd
oauth_access_name = function(key) paste0("auth:", key, ":access")

#' Keep an access token in memory only: registered in the vault, bound to the resource's origin;
#' the Authorization value list("Bearer ", <handle>) is materialised only by P04 (contract 7.3)
#' @noRd
oauth_remember = function(key, access, origin) {
  h = secret_register(access, oauth_access_name(key), source = "oauth", origin = origin)
  list("Bearer ", h)
}

#' The Authorization value for `key`, or NULL when nothing is stored: an API key, or a valid
#' in-memory access token, else an OAuth refresh under a lock (`force` = refresh now, after a 401).
#' A record that names its `resource` is handed only to that resource's origin: a server whose
#' URL changed (another config reusing the name) gets no credential and asks for a sign-in.
#' @noRd
oauth_access = function(key, origin, force = FALSE) {
  rec = auth_store_get(key)
  if (is.null(rec)) return(NULL)
  if (is.character(rec$resource) && !is.null(origin) &&
        !identical(url_origin(rec$resource), url_origin(origin))) {
    return(NULL)
  }
  if (identical(rec$type, "api_key") && inherits(rec$key, "gptr_secret")) {
    return(list("Bearer ", rec$key))
  }
  if (!identical(rec$type, "oauth")) return(NULL)
  h = secret_lookup(oauth_access_name(key))
  fresh = isTRUE(as.numeric(rec$expires %||% 0) > oauth_now_ms() + 60000)
  if (!isTRUE(force) && !is.null(h) && fresh) return(list("Bearer ", h))
  oauth_refresh(key, origin)
}

#' Refresh an OAuth credential. The store is re-read under a lock, so two R processes never
#' redeem the same rotating refresh token (report 03's double-checked refresh). The stored
#' refresh token leaves the vault only here, for the token endpoint's own origin, as the form
#' field RFC 6749 section 6 requires (P04 bodies cannot carry handles; plan ambiguity 2).
#' @noRd
oauth_refresh = function(key, origin) {
  lock = file.path(gptr_user_dir("config", create = TRUE),
                   paste0("oauth-", substr(hash_sha256(key), 1L, 16L)))
  lock_with(lock, function() {
    rec = auth_store_get(key)
    if (!inherits(rec$refresh, "gptr_secret") || !is.character(rec$token_endpoint)) return(NULL)
    refresh = secret_value(rec$refresh, url_origin(rec$token_endpoint))
    # 20 s: the request ends before P03's staleness rule (30 s) lets another process break the
    # lock and redeem the same rotating refresh token
    tok = oauth_post(rec$token_endpoint,
                     list(grant_type = "refresh_token", refresh_token = refresh,
                          client_id = rec$client_id, resource = rec$resource),
                     "access_token", url_origin(rec$token_endpoint), form = TRUE, timeout = 20)
    rec$refresh = tok$refresh_token %||% refresh
    rec$expires = oauth_expiry(tok)
    header = oauth_remember(key, tok$access_token, origin)
    auth_store_set(key, rec)
    header
  })
}

#' Deactivate the in-memory access tokens of `key` (gptr_logout(), contract 6.2): secret_lookup()
#' no longer finds them, while their values stay registered and redacted. P03 has no unregister
#' function, so its registry entries (secrets_state()$reg, same `auth` area) are marked inactive,
#' the state P03's own `active = FALSE` registrations produce; TRUE when one was active.
#' @noRd
oauth_forget_access = function(key) {
  st = secrets_state()
  hit = vapply(st$reg, function(e) identical(e$name, oauth_access_name(key)) && e$active, NA)
  for (id in names(st$reg)[hit]) st$reg[[id]]$active = FALSE
  any(hit)
}

# ---- the authorization-code flow ---------------------------------------------------------------

#' Load-time callbacks of the layers above (architecture 2.2: L0 talks upward only through
#' callbacks), like P10's namespace providers: `target(name)` resolves gptr_login("mcp:<name>")
#' to list(url, oauth). No credentials and no run state live here.
#' @noRd
oauth_hooks = new.env(parent = emptyenv())

#' Register the callbacks (mcp-namespace.R does at load)
#' @noRd
oauth_hooks_set = function(target = NULL) {
  if (!is.null(target)) assign("target", target, envir = oauth_hooks)
  invisible(NULL)
}

#' Provider sign-ins gptr knows without discovery (report 03 section 3, Pi openrouter.ts:19-22):
#' OpenRouter's PKCE flow returns a permanent, user-controlled API key
#' @noRd
oauth_builtin_flows = function() {
  list(openrouter = list(authorize = "https://openrouter.ai/auth",
                         token = "https://openrouter.ai/api/v1/auth/keys",
                         origin = "https://openrouter.ai"))
}

#' The UI of this process (the ui.get service of P11)
#' @noRd
oauth_ui = function() ext_service_get("ui.get")(NULL)

#' Can the loopback redirect be served (httpuv and later installed)?
#' @noRd
oauth_loopback_ok = function() {
  with_seed_preserved(requireNamespace("httpuv", quietly = TRUE) &&
                        requireNamespace("later", quietly = TRUE))
}

#' Open the sign-in page in a browser, only at an interactive R prompt (13 C-42)
#' @noRd
oauth_open_browser = function(url) {
  if (gptr_is_interactive()) utils::browseURL(url)
  invisible(NULL)
}

#' Show the sign-in URL through the UI and open the browser
#' @noRd
oauth_notify_url = function(url) {
  oauth_ui()$notify(paste0("Sign in at: ", url), level = "info")
  oauth_open_browser(url)
  invisible(NULL)
}

#' A small HTML page for the loopback listener
#' @noRd
oauth_page = function(status, text) {
  list(status = as.integer(status),
       headers = list(`Content-Type` = "text/html; charset=utf-8", `Cache-Control` = "no-store"),
       body = paste0("<!doctype html><meta charset='utf-8'><title>gptr</title><p>", text, "</p>"))
}

#' Where the browser comes back: a loopback listener on 127.0.0.1 (a port from
#' port_candidates(), started with the seed preserved; IC-61) that keeps the whole query string,
#' `iss` included (IC-71), or, without httpuv and later, a paste prompt. Returns
#' list(redirect_uri, wait(timeout), close()).
#' @noRd
oauth_redirect_setup = function(port = NULL, path = "/callback", state = NULL) {
  st = new.env(parent = emptyenv())
  st$query = NULL
  if (!oauth_loopback_ok()) {
    p = if (is.null(port)) port_candidates(1L)[1L] else as.integer(port)
    uri = paste0("http://127.0.0.1:", p, path)
    return(list(redirect_uri = uri, close = function() invisible(NULL),
                wait = function(timeout = 300) {
                  oauth_ui()$input(paste0("After signing in, paste the full address of the ",
                                          "page your browser opened: "))
                }))
  }
  app = list(call = function(req) {
    if (!identical(req$REQUEST_METHOD, "GET") || !identical(req$PATH_INFO, path)) {
      return(oauth_page(404L, "Not found."))
    }
    if (!is.null(st$query)) return(oauth_page(409L, "This sign-in was already handled."))
    q = sub("^\\?", "", req$QUERY_STRING %||% "")
    if (!is.null(state) && !identical(query_parse(q)$state, state)) {
      return(oauth_page(400L, "This page does not belong to the current sign-in."))
    }
    st$query = q
    oauth_page(200L, "Signed in. You can close this page and return to R.")
  })
  ports = if (is.null(port)) port_candidates(20L) else as.integer(port)
  srv = NULL
  with_seed_preserved({
    for (p in ports) {
      srv = tryCatch(httpuv::startServer("127.0.0.1", p, app), error = function(e) NULL)
      if (!is.null(srv)) {
        st$port = p
        break
      }
    }
  })
  if (is.null(srv)) {
    gptr_abort("Could not open a local port for the sign-in redirect.", "spawn",
               command = "httpuv::startServer")
  }
  uri = paste0("http://127.0.0.1:", st$port, path)
  list(redirect_uri = uri,
       close = function() with_seed_preserved(try(httpuv::stopServer(srv), silent = TRUE)),
       wait = function(timeout = 300) {
         ok = reactor_pump(until = function() !is.null(st$query), slice_ms = 100L,
                           timeout = timeout)
         if (!ok) {
           gptr_abort(paste0("No sign-in arrived within ", timeout, " s."), "timeout",
                      seconds = timeout, what = "OAuth redirect")
         }
         sep = if (nzchar(st$query)) "?" else ""
         paste0(uri, sep, st$query)
       })
}

#' OAuth authorization-code flow with PKCE S256 (contract 7.18)
#'
#' `issuer_or_provider`: an issuer URL, a discovery result of oauth_discover(), or a built-in
#' provider id (oauth_builtin_flows()); `client`: list(client_id, callback_port, resource, key).
#' The access token stays in the vault; returns the credential record to store (the refresh
#' token as a value, never the access token).
#' @noRd
oauth_flow = function(issuer_or_provider, scopes = NULL, client = NULL) {
  flows = oauth_builtin_flows()
  if (is.character(issuer_or_provider) && issuer_or_provider %in% names(flows)) {
    return(oauth_key_exchange(issuer_or_provider, flows[[issuer_or_provider]], client))
  }
  disc = if (is.list(issuer_or_provider)) {
    issuer_or_provider
  } else {
    list(issuer = issuer_or_provider, metadata = oauth_as_metadata(issuer_or_provider),
         resource = client$resource, scopes = character())
  }
  meta = disc$metadata
  scope = paste(unique(c(scopes, disc$scopes)), collapse = " ")
  key = client$key %||% disc$issuer
  state = rand_hex(16L)
  pk = pkce_new()
  cb = oauth_redirect_setup(client$callback_port, state = state)
  on.exit(cb$close(), add = TRUE)
  client_id = client$client_id %||% oauth_register_client(meta, cb$redirect_uri, scope) %||%
    oauth_ask(paste("Client id registered with", disc$issuer))
  oauth_notify_url(oauth_authorize_url(meta, client_id, cb$redirect_uri, scope, state,
                                       pk$challenge, disc$resource))
  code = oauth_parse_redirect(cb$wait(300), cb$redirect_uri, state, disc$issuer,
                              isTRUE(meta$authorization_response_iss_parameter_supported))
  tok = oauth_post(meta$token_endpoint,
                   list(grant_type = "authorization_code", code = code,
                        redirect_uri = cb$redirect_uri, code_verifier = pk$verifier,
                        client_id = client_id, resource = disc$resource),
                   "access_token", url_origin(meta$token_endpoint), form = TRUE)
  oauth_remember(key, tok$access_token, url_origin(disc$resource %||% disc$issuer))
  list(type = "oauth", issuer = disc$issuer, client_id = client_id,
       token_endpoint = meta$token_endpoint, resource = disc$resource, scope = scope,
       expires = oauth_expiry(tok), refresh = tok$refresh_token)
}

#' A provider's PKCE flow that returns an API key (OpenRouter). The protocol has no state, so
#' the redirect path carries a random segment and only that path is accepted.
#' @noRd
oauth_key_exchange = function(id, flow, client) {
  pk = pkce_new()
  cb = oauth_redirect_setup(client$callback_port, path = paste0("/callback/", rand_hex(8L)))
  on.exit(cb$close(), add = TRUE)
  oauth_notify_url(paste0(flow$authorize, "?",
                          form_encode(list(callback_url = cb$redirect_uri,
                                           code_challenge = pk$challenge,
                                           code_challenge_method = "S256"))))
  code = oauth_parse_redirect(cb$wait(300), cb$redirect_uri, NULL, flow$origin)
  body = list(code = code, code_verifier = pk$verifier, code_challenge_method = "S256")
  list(type = "api_key", key = oauth_post(flow$token, body, "key", id)$key)
}

#' Masked entry of a key, token or client id through the UI (P11: rstudioapi::askForPassword()
#' or a no-echo read)
#' @noRd
oauth_ask = function(what) {
  v = oauth_ui()$input(paste0(what, ": "), secret = TRUE)
  if (!rlang::is_string(v) || !nzchar(trimws(v))) {
    gptr_abort("Nothing was entered.", "invalid_argument", arg = "input",
               expected = "a non-empty value")
  }
  trimws(v)
}

# ---- gptr_login() and gptr_logout() ------------------------------------------------------------

#' Sign in to a model provider or an MCP server
#'
#' Stores a credential for a model provider (for example `"openrouter"`) or for an MCP server
#' (`"mcp:<server>"`). With `method = "auto"`, providers and MCP servers that support OAuth
#' get the authorization-code flow with PKCE (S256): a page on 127.0.0.1 receives the redirect
#' when 'httpuv' and 'later' are installed; otherwise you paste the address your browser ends
#' on. Everything else gets masked key entry. Credentials go to the credential store
#' (`auth.json`, readable only by you, or a keyring reference); access tokens stay in memory.
#' A tool call never opens a browser: when an MCP server needs a sign-in, the call fails with
#' an error naming this function.
#'
#' @param provider A provider id such as `"openrouter"`, or `"mcp:<server>"` for an MCP server.
#' @param method `"auto"` (default), `"oauth"` (the browser flow only) or `"key"` (key entry).
#' @return `gptr_login()` returns `TRUE` invisibly; `gptr_logout()` removes the stored
#'   credential and forgets the access token held in memory, and returns `TRUE` invisibly when
#'   it removed something, else `FALSE`.
#' @examplesIf interactive()
#' gptr_login("openrouter")
#' gptr_logout("openrouter")
#' @export
gptr_login = function(provider, method = c("auto", "oauth", "key")) {
  provider = check_string(provider, "provider")
  method = check_choice(method, c("auto", "oauth", "key"), "method")
  ext_control_guard("gptr_login")
  if (!gptr_can_prompt()) {
    gptr_abort("gptr_login() needs a person to sign in; run it in an interactive R session.",
               "noninteractive", what = "gptr_login()", questions = NULL)
  }
  if (startsWith(provider, "mcp:")) {
    oauth_login_mcp(substring(provider, 5L), method)
    return(invisible(TRUE))
  }
  flow = oauth_builtin_flows()[[provider]]
  if (is.null(flow) && is.null(registry_get("provider", provider))) {
    gptr_abort(paste0("Unknown provider: ", provider, "."), "invalid_argument", arg = "provider",
               expected = "a provider id from gptr_providers(), or \"mcp:<server>\"")
  }
  if (identical(method, "oauth") && is.null(flow)) {
    gptr_abort(paste0("Provider ", provider, " has no sign-in flow in gptr; use method = \"key\"."),
               "invalid_argument", arg = "method",
               expected = "\"key\" or \"auto\" for this provider")
  }
  rec = if (!is.null(flow) && !identical(method, "key")) {
    oauth_flow(provider, client = list(key = provider))
  } else {
    list(type = "api_key", key = oauth_ask(paste("API key for", provider)))
  }
  auth_store_set(provider, rec)
  invisible(TRUE)
}

#' The MCP branch of gptr_login(): RFC 9728 discovery and OAuth, or a bearer token entered by
#' hand when the server offers no OAuth
#' @noRd
oauth_login_mcp = function(name, method) {
  target_fun = get0("target", envir = oauth_hooks, inherits = FALSE)
  if (!is.function(target_fun)) {
    gptr_abort("MCP support is not loaded (builtin:mcp is filtered out).", "not_available",
               member = "gptr_login(\"mcp:...\")", provided_by = "P18")
  }
  key = paste0("mcp:", name)
  target = target_fun(name)
  disc = if (!identical(method, "key")) oauth_discover(target$url)
  if (is.null(disc)) {
    if (identical(method, "oauth")) {
      gptr_abort(paste0("MCP server ", name, " does not offer OAuth; use method = \"key\"."),
                 "invalid_argument", arg = "method", expected = "\"key\" for this server")
    }
    token = oauth_ask(paste("Bearer token for MCP server", name))
    auth_store_set(key, list(type = "api_key", key = token, resource = target$url))
    return(invisible(TRUE))
  }
  rec = oauth_flow(disc, scopes = target$oauth$scope,
                   client = list(client_id = target$oauth$clientId,
                                 callback_port = target$oauth$callbackPort,
                                 resource = target$url, key = key))
  auth_store_set(key, rec)
  invisible(TRUE)
}

#' @rdname gptr_login
#' @export
gptr_logout = function(provider) {
  provider = check_string(provider, "provider")
  ext_control_guard("gptr_logout")
  stored = isTRUE(auth_store_remove(provider))
  memory = oauth_forget_access(provider)
  invisible(stored || memory)
}
