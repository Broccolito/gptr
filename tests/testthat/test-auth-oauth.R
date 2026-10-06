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
