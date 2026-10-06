test_that("url helpers split URLs; hdr_value reads headers case-insensitively", {
  u = url_parse("https://Example.org:8443/a/b?x=1&y=2")
  expect_identical(u$scheme, "https")
  expect_identical(u$host, "example.org")
  expect_identical(u$port, "8443")
  expect_identical(u$path, "/a/b")
  expect_identical(u$query, "x=1&y=2")
  expect_identical(url_parse("http://h/a%2Fb?c=d%26e")[c("path", "query")],
                   list(path = "/a%2Fb", query = "c=d%26e"))
  expect_identical(url_parse("http://[::1]:5000/cb")$host, "[::1]")
  expect_null(url_parse("no scheme"))
  expect_identical(hdr_value(list(`Www-Authenticate` = "Bearer x"), "WWW-Authenticate"), "Bearer x")
  expect_null(hdr_value(list(a = "1"), "b"))
  expect_null(hdr_value(NULL, "b"))
})

test_that("form and query encoding round-trip", {
  expect_identical(form_encode(list(a = "x y", b = NULL, c = "p&q=r")), "a=x%20y&c=p%26q%3Dr")
  q = query_parse("?code=abc&state=s%201&iss=https%3A%2F%2Fas.example&empty")
  expect_identical(q$code, "abc")
  expect_identical(q$state, "s 1")
  expect_identical(q$iss, "https://as.example")
  expect_identical(q$empty, "")
  expect_identical(query_parse(""), json_obj())
})

test_that("PKCE follows the RFC 7636 appendix B vector; tokens never touch the RNG", {
  skip_if_not_installed("openssl")
  p = pkce_new("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
  expect_identical(p$challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  expect_identical(p$method, "S256")
  withr::local_seed(1)
  seed = get(".Random.seed", envir = globalenv())
  expect_match(pkce_new()$verifier, "^[A-Za-z0-9_-]{43}$")
  expect_match(rand_hex(24L), "^[0-9a-f]{48}$")
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
})

test_that("the WWW-Authenticate challenge is parsed", {
  ch = oauth_parse_challenge(paste0(
    "Bearer realm=\"OAuth\", resource_metadata=",
    "\"https://mcp.example/.well-known/oauth-protected-resource/mcp\", scope=\"read write\""))
  expect_identical(ch$resource_metadata,
                   "https://mcp.example/.well-known/oauth-protected-resource/mcp")
  expect_identical(ch$scope, "read write")
  expect_identical(oauth_parse_challenge(NULL), list())
})

test_that("metadata without S256 PKCE or for another issuer is refused (IC-71)", {
  good = list(issuer = "https://as.example", authorization_endpoint = "https://as.example/auth",
              token_endpoint = "https://as.example/token",
              code_challenge_methods_supported = list("S256"))
  expect_invisible(oauth_check_metadata(good, "https://as.example"))
  no_pkce = good
  no_pkce$code_challenge_methods_supported = NULL
  expect_error(oauth_check_metadata(no_pkce, "https://as.example"), "PKCE",
               class = "gptr_error_untrusted")
  plain = good
  plain$code_challenge_methods_supported = list("plain")
  expect_error(oauth_check_metadata(plain, "https://as.example"), "S256",
               class = "gptr_error_untrusted")
  expect_error(oauth_check_metadata(good, "https://other.example"), "another issuer",
               class = "gptr_error_untrusted")
})

test_that("the authorization URL carries PKCE, state and the resource", {
  meta = list(authorization_endpoint = "https://as.example/authorize")
  url = oauth_authorize_url(meta, "c1", "http://127.0.0.1:50000/callback", "read", "st", "CH",
                            resource = "https://mcp.example/mcp")
  q = query_parse(url_parse(url)$query)
  expect_identical(q$response_type, "code")
  expect_identical(q$code_challenge_method, "S256")
  expect_identical(q$code_challenge, "CH")
  expect_identical(q$state, "st")
  expect_identical(q$resource, "https://mcp.example/mcp")
  expect_identical(q$redirect_uri, "http://127.0.0.1:50000/callback")
})

test_that("redirects are checked for target, state and iss before the code is used", {
  redirect = "http://127.0.0.1:50000/callback"
  iss = "https://as.example"
  ok = paste0(redirect, "?code=abc&state=st&iss=https%3A%2F%2Fas.example")
  expect_identical(oauth_parse_redirect(ok, redirect, "st", iss, TRUE), "abc")
  expect_identical(oauth_parse_redirect("code=abc&state=st", redirect, "st", iss, FALSE), "abc")
  expect_error(oauth_parse_redirect(paste0(redirect, "?code=abc&state=bad"), redirect, "st", iss),
               "state", class = "gptr_error_untrusted")
  wrong = paste0(redirect, "?code=abc&state=st&iss=https%3A%2F%2Fevil.example")
  expect_error(oauth_parse_redirect(wrong, redirect, "st", iss), "issuer",
               class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect(paste0(redirect, "?code=abc&state=st"), redirect, "st", iss,
                                    TRUE), "missing", class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect("http://127.0.0.1:1/other?code=abc&state=st", redirect, "st",
                                    iss), "another address", class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect(paste0(redirect, "?error=access_denied&state=st"), redirect,
                                    "st", iss), "declined", class = "gptr_error_provider")
  expect_error(oauth_parse_redirect("", redirect, "st", iss), "nothing",
               class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect(paste0(redirect, "?code=a\001b&state=st"), redirect, "st", iss),
               class = "gptr_error_invalid_argument")
  expect_error(oauth_parse_redirect("http://127.0.0.1:50000\\@evil.example/callback?state=st",
                                    redirect, "st", iss), class = "gptr_error_invalid_argument")
})

test_that("lock_with() serialises, waits for a live holder and breaks stale locks", {
  path = file.path(withr::local_tempdir(), "mcp.json")
  lock = paste0(path, ".lock")
  expect_true(lock_with(path, function() dir.exists(lock)))
  expect_false(dir.exists(lock))
  dir.create(lock)
  me = paste(Sys.getpid(), format(as.numeric(ps::ps_create_time(ps::ps_handle())), digits = 15))
  writeLines(me, file.path(lock, "pid"))
  expect_error(lock_with(path, function() "ran", tries = 3L, wait = 0.01),
               class = "gptr_error_timeout")
  unlink(lock, recursive = TRUE)
  skip_on_cran()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  withr::defer(dead$kill())
  dead$wait(10000)
  dir.create(lock)
  writeLines(paste(dead$get_pid(), 1), file.path(lock, "pid"))
  expect_identical(lock_with(path, function() "ran"), "ran")
  expect_false(dir.exists(lock))
})

test_that("encoding keeps percent signs, padding and malformed escapes; fields match exactly", {
  expect_identical(form_encode(list(v = "50%25")), "v=50%2525")
  expect_identical(form_encode(list(a = NULL)), "")
  q = query_parse("x=abc==&&y=a%")
  expect_identical(q$x, "abc==")
  expect_identical(q$y, "a%")
  ch = oauth_parse_challenge("Bearer error=invalid_token, Scope=\"a \\\"b\\\"\"")
  expect_identical(ch$error, "invalid_token")
  expect_identical(ch$scope, "a \"b\"")
  expect_error(oauth_parse_redirect("state=st&code_x=abc", "http://127.0.0.1:1/cb", "st",
                                    "https://as.example"), "no authorization code",
               class = "gptr_error_untrusted")
  two = list(issuer = "https://as.example", authorization_endpoint = "https://as.example/auth",
             token_endpoint = c("https://as.example/t1", "https://as.example/t2"),
             code_challenge_methods_supported = list("S256"))
  expect_error(oauth_check_metadata(two, "https://as.example"), "endpoint",
               class = "gptr_error_untrusted")
  url = oauth_authorize_url(list(authorization_endpoint = "https://as.example/authorize?p=1"),
                            "c1", "http://127.0.0.1:1/cb", c("read", "write"), "st", "CH")
  expect_identical(query_parse(url_parse(url)$query)$scope, "read write")
})

test_that("gptr_login() signs in to an MCP server: PKCE S256, DCR, loopback redirect, 0600 store", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(secure = mock$url))
  browser = local_browser()
  ui = local_scripted_ui()
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  expect_invisible(gptr_login("mcp:secure"))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_length(browser$urls, 1L)
  expect_true(any(grepl("Sign in at:", ui$log$prompt, fixed = TRUE)))
  rec = auth_store_get("mcp:secure")
  expect_identical(rec$type, "oauth")
  expect_identical(rec$client_id, "client-1")
  expect_identical(rec$issuer, mock$base)
  expect_identical(secret_value(rec$refresh, mock$base), "refresh-1")
  expect_null(rec$access)
  path = file.path(gptr_user_dir("config"), "auth.json")
  txt = paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("access-1", txt, fixed = TRUE))
  if (.Platform$OS.type == "unix") expect_identical(format(file.info(path)$mode), "600")
  log = mock$log()
  expect_identical(log$what[log$path == "/register"], "native")
  expect_identical(log$what[log$path == "/authorize"], "S256")
  expect_identical(log$what[log$path == "/token"], "authorization_code")
  header = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(header[[1L]], "Bearer ")
  expect_s3_class(header[[2L]], "gptr_secret")
  expect_identical(secret_value(header[[2L]], mock$url), "access-1")
  expect_error(secret_value(header[[2L]], "https://evil.example"), class = "gptr_error_untrusted")
})

test_that("an expired access token is refreshed under the lock; a stale lock is broken", {
  skip_on_cran()
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(secure = mock$url))
  local_browser()
  local_scripted_ui()
  gptr_login("mcp:secure")
  rec = auth_store_get("mcp:secure")
  rec$refresh = secret_value(rec$refresh, mock$base)
  rec$expires = 0
  auth_store_set("mcp:secure", rec)
  lock = file.path(gptr_user_dir("config"),
                   paste0("oauth-", substr(hash_sha256("mcp:secure"), 1L, 16L), ".lock"))
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  dir.create(lock)
  writeLines(paste(dead$get_pid(), 1), file.path(lock, "pid"))
  header = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(secret_value(header[[2L]], mock$url), "access-2")
  expect_false(dir.exists(lock))
  expect_identical(secret_value(auth_store_get("mcp:secure")$refresh, mock$base), "refresh-2")
  expect_identical(tail(mock$log()$what[mock$log()$path == "/token"], 1L), "refresh_token")
  again = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(secret_value(again[[2L]], mock$url), "access-2")
  expect_identical(sum(mock$log()$what == "refresh_token"), 1L)
})

test_that("a refused OAuth request is gptr_error_provider with its HTTP status", {
  mock = local_oauth_mock()
  err = expect_error(oauth_post(paste0(mock$base, "/token"), list(grant_type = "none"),
                                "access_token", mock$base, form = TRUE),
                     "refused", class = "gptr_error_provider")
  expect_equal(err$status, 400)
})

test_that("authorization servers without S256 PKCE or with a wrong iss are refused (IC-71)", {
  local_user_dirs()
  mock = local_oauth_mock(pkce = "no")
  mock2 = local_oauth_mock(iss = "wrong")
  local_login_target(c(nopkce = mock$url, badiss = mock2$url))
  local_browser()
  local_scripted_ui()
  expect_error(gptr_login("mcp:nopkce"), "PKCE", class = "gptr_error_untrusted")
  expect_false("/authorize" %in% mock$log()$path)
  expect_error(gptr_login("mcp:badiss"), "issuer", class = "gptr_error_untrusted")
  expect_true("/authorize" %in% mock2$log()$path)
  expect_false("/token" %in% mock2$log()$path)
  expect_null(auth_store_get("mcp:nopkce"))
  expect_null(auth_store_get("mcp:badiss"))
})

test_that("a server without OAuth metadata gets masked token entry", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(plain = paste0(mock$base, "/plain")))
  ui = local_scripted_ui(list("manual-token-123"))
  gptr_login("mcp:plain")
  expect_identical(ui$log$method, "input")
  rec = auth_store_get("mcp:plain")
  expect_identical(rec$type, "api_key")
  expect_identical(rec$resource, paste0(mock$base, "/plain"))
  header = oauth_access("mcp:plain", mock$base)
  expect_identical(secret_value(header[[2L]], mock$base), "manual-token-123")
  expect_null(oauth_access("mcp:plain", "https://elsewhere.example"))
  expect_error(gptr_login("mcp:plain", method = "oauth"), "does not offer OAuth",
               class = "gptr_error_invalid_argument")
})

test_that("protected-resource metadata naming another resource is refused (RFC 9728)", {
  local_mocked_bindings(oauth_get_json = function(url) {
    list(resource = "https://other.example/mcp", authorization_servers = list("https://as.example"))
  })
  expect_error(oauth_discover("https://mcp.example/mcp"), "another resource",
               class = "gptr_error_untrusted")
})

test_that("key entry stores an API key; gptr_logout() removes it; no person means no login", {
  local_user_dirs()
  key = paste0("sk-or-v1-", "testkeyabcdefghijklmnopqrstuv")
  local_scripted_ui(list(key))
  gptr_login("openrouter", method = "key")
  rec = auth_store_get("openrouter")
  expect_identical(rec$type, "api_key")
  expect_false(grepl("testkeyabcdef", redact(key), fixed = TRUE))
  expect_true(gptr_logout("openrouter"))
  expect_null(auth_store_get("openrouter"))
  expect_false(gptr_logout("openrouter"))
  withr::local_options(gptr.interactive = FALSE)
  expect_error(gptr_login("openrouter"), class = "gptr_error_noninteractive")
  expect_error(gptr_login("nope", method = "key"), class = "gptr_error_noninteractive")
  withr::local_options(gptr.interactive = TRUE)
  expect_error(gptr_login("nope", method = "key"), "Unknown provider",
               class = "gptr_error_invalid_argument")
})

test_that("the OpenRouter-style PKCE key exchange stores the returned key", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_mocked_bindings(oauth_builtin_flows = function() {
    list(openrouter = list(authorize = paste0(mock$base, "/auth"),
                           token = paste0(mock$base, "/api/v1/auth/keys"), origin = mock$base))
  })
  local_browser()
  local_scripted_ui()
  gptr_login("openrouter")
  expect_identical(secret_value(auth_store_get("openrouter")$key, NULL),
                   paste0("sk-or-v1-", "mockkeyabcdefghijklmnopqrst"))
  expect_identical(mock$log()$what[mock$log()$path == "/auth"], "S256")
  expect_true("/api/v1/auth/keys" %in% mock$log()$path)
  gptr_logout("openrouter")
})

test_that("without httpuv and later the redirect is pasted, iss included", {
  skip_if_not_installed("openssl")
  local_mocked_bindings(oauth_loopback_ok = function() FALSE)
  ui = local_scripted_ui(list("http://127.0.0.1:1/x"))
  cb = oauth_redirect_setup(port = 50111L)
  expect_identical(cb$redirect_uri, "http://127.0.0.1:50111/callback")
  expect_identical(cb$wait(), "http://127.0.0.1:1/x")
  expect_identical(ui$log$method, "input")
  expect_error(oauth_parse_redirect("code=abc", cb$redirect_uri, NULL, "https://or.example"),
               "full address", class = "gptr_error_untrusted")
})
