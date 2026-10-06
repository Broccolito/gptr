# OAuth 2.1 authorization server and protected MCP resource for gptr's tests (127.0.0.1 only).
# Adapted from dev/research/03-pi-ai-providers-auth.md 5.6 (a mock server verifying the PKCE
# challenge) and 16 section 3.5 (discovery documents, the WWW-Authenticate challenge).
# Usage: Rscript --vanilla oauth.R --port=N --pkce=yes|no --iss=good|wrong|absent --log=<path>
args = commandArgs(trailingOnly = TRUE)
arg = function(name, default = NULL) {
  hit = grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1L]) else default
}
# base R has `%||%` only from R 4.4.0 (the fixture runs on R >= 4.2); an operator keeps its name
`%||%` = function(a, b) if (is.null(a)) b else a # nolint: object_name_linter.
port = as.integer(arg("port"))
pkce = arg("pkce", "yes")
iss_mode = arg("iss", "good")
log_path = arg("log", tempfile())
base = paste0("http://127.0.0.1:", port)
state = new.env()
state$challenge = NULL
state$redirect = NULL
state$tokens = c("access-1", "access-2", "access-3")
json = function(status, x, headers = list()) {
  list(status = status, headers = c(list(`Content-Type` = "application/json"), headers),
       body = as.character(jsonlite::toJSON(x, auto_unbox = TRUE)))
}
b64url = function(bytes) {
  chartr("+/", "-_", gsub("=+$", "", gsub("[\r\n]", "", jsonlite::base64_enc(bytes))))
}
form = function(txt) {
  txt = sub("^\\?", "", txt)
  if (!nzchar(txt)) return(list())
  kv = strsplit(strsplit(txt, "&", fixed = TRUE)[[1L]], "=", fixed = TRUE)
  vals = lapply(kv, function(p) {
    utils::URLdecode(gsub("+", " ", paste(p[-1L], collapse = "="), fixed = TRUE))
  })
  stats::setNames(vals, vapply(kv, `[[`, "", 1L))
}
log = function(path, what) {
  cat(as.character(jsonlite::toJSON(list(path = path, what = what), auto_unbox = TRUE)), "\n",
      sep = "", file = log_path, append = TRUE)
}
authorized = function(req) {
  a = req$HTTP_AUTHORIZATION %||% ""
  a %in% paste("Bearer", c(state$tokens, "manual-token-123"))
}
mcp = function(req, body) {
  if (!authorized(req)) {
    log("/mcp", "401")
    challenge = paste0("Bearer realm=\"OAuth\", resource_metadata=\"", base,
                       "/.well-known/oauth-protected-resource/mcp\", scope=\"read\"")
    return(json(401L, list(error = "invalid_token"), list(`WWW-Authenticate` = challenge)))
  }
  msg = jsonlite::fromJSON(body, simplifyVector = FALSE)
  log("/mcp", msg$method %||% "notification")
  if (is.null(msg$id)) return(list(status = 202L, headers = list(), body = ""))
  empty = structure(list(), names = character())
  res = switch(msg$method,
    `server/discover` = list(resultType = "complete", supportedVersions = I("2026-07-28"),
                             capabilities = list(tools = empty)),
    `tools/list` = list(resultType = "complete", tools = list(list(
      name = "whoami", description = "Who am I?",
      inputSchema = list(type = "object", properties = empty)))),
    `tools/call` = list(resultType = "complete",
                        content = list(list(type = "text", text = "you are signed in"))),
    NULL)
  if (is.null(res)) {
    return(json(404L, list(jsonrpc = "2.0", id = msg$id,
                           error = list(code = -32601L, message = "Method not found"))))
  }
  json(200L, list(jsonrpc = "2.0", id = msg$id, result = res))
}
app = list(call = function(req) {
  path = req$PATH_INFO
  body = rawToChar(req$rook.input$read())
  if (identical(path, "/mcp")) return(mcp(req, body))
  if (identical(path, "/.well-known/oauth-protected-resource/mcp")) {
    log(path, "prm")
    return(json(200L, list(resource = paste0(base, "/mcp"), authorization_servers = I(base),
                           scopes_supported = I("read"))))
  }
  if (identical(path, "/.well-known/oauth-authorization-server")) {
    log(path, "as")
    meta = list(issuer = base, authorization_endpoint = paste0(base, "/authorize"),
                token_endpoint = paste0(base, "/token"),
                registration_endpoint = paste0(base, "/register"), scopes_supported = I("read"),
                authorization_response_iss_parameter_supported = !identical(iss_mode, "absent"))
    if (identical(pkce, "yes")) meta$code_challenge_methods_supported = I("S256")
    return(json(200L, meta))
  }
  if (identical(path, "/register")) {
    x = jsonlite::fromJSON(body, simplifyVector = FALSE)
    log(path, x$application_type %||% "none")
    return(json(201L, list(client_id = "client-1", redirect_uris = x$redirect_uris)))
  }
  if (identical(path, "/authorize") || identical(path, "/auth")) {
    q = form(req$QUERY_STRING %||% "")
    state$challenge = q$code_challenge
    state$redirect = q$redirect_uri %||% q$callback_url
    log(path, q$code_challenge_method %||% "none")
    extra = switch(iss_mode,
                   good = paste0("&iss=", utils::URLencode(base, reserved = TRUE)),
                   wrong = "&iss=http%3A%2F%2Fevil.example",
                   "")
    loc = if (identical(path, "/auth")) {
      paste0(state$redirect, "?code=or-code-1")
    } else {
      paste0(state$redirect, "?code=code-1&state=",
             utils::URLencode(q$state %||% "", reserved = TRUE), extra)
    }
    return(list(status = 302L, headers = list(Location = loc), body = ""))
  }
  if (identical(path, "/token")) {
    f = form(body)
    log(path, f$grant_type %||% "none")
    if (identical(f$grant_type, "authorization_code")) {
      verified = identical(b64url(openssl::sha256(charToRaw(f$code_verifier %||% ""))),
                           state$challenge)
      ok = identical(f$code, "code-1") && identical(f$redirect_uri, state$redirect) && verified
      if (!ok) return(json(400L, list(error = "invalid_grant")))
      return(json(200L, list(access_token = "access-1", refresh_token = "refresh-1",
                             expires_in = 3600, token_type = "Bearer")))
    }
    if (identical(f$grant_type, "refresh_token")) {
      n = match(f$refresh_token, c("refresh-1", "refresh-2"))
      if (is.na(n)) return(json(400L, list(error = "invalid_grant")))
      return(json(200L, list(access_token = state$tokens[n + 1L],
                             refresh_token = paste0("refresh-", n + 1L), expires_in = 3600)))
    }
    return(json(400L, list(error = "unsupported_grant_type")))
  }
  if (identical(path, "/api/v1/auth/keys")) {
    x = jsonlite::fromJSON(body, simplifyVector = FALSE)
    log(path, "key")
    verified = identical(b64url(openssl::sha256(charToRaw(x$code_verifier %||% ""))),
                         state$challenge)
    if (!identical(x$code, "or-code-1") || !verified) {
      return(json(400L, list(error = "invalid_code")))
    }
    return(json(200L, list(key = paste0("sk-or-v1-", "mockkeyabcdefghijklmnopqrst"))))
  }
  json(404L, list(error = "not_found"))
})
srv = tryCatch(httpuv::startServer("127.0.0.1", port, app), error = function(e) NULL)
if (is.null(srv)) quit(save = "no", status = 3L)
cat("READY", port, "\n")
flush(stdout())
parent = suppressWarnings(as.integer(Sys.getenv("GPTR_FIXTURE_PARENT")))
repeat {
  httpuv::service(100)
  alive = is.na(parent) ||
    tryCatch(ps::ps_is_running(ps::ps_handle(parent)), error = function(e) FALSE)
  if (!alive) break
}
