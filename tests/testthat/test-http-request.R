test_that("url_origin() and url_for_log() keep scheme, host and port only", {
  expect_identical(url_origin("https://API.Anthropic.com/v1/messages"), "https://api.anthropic.com")
  expect_identical(url_origin("https://api.anthropic.com:443/v1"), "https://api.anthropic.com")
  expect_identical(url_origin("http://127.0.0.1:8123/tok/v1/messages?x=1"), "http://127.0.0.1:8123")
  expect_identical(url_origin("http://user:pw@example.test:80/p"), "http://example.test")
  expect_true(is.na(url_origin("not a url")))
  expect_identical(url_for_log("https://g.test/v1beta/models/m:stream?key=SECRET#f"),
                   "https://g.test/v1beta/models/m:stream")
})

test_that("header handles materialise only for their own origin", {
  h = secret_register("sk-hdr-test-0123456789abcdef", "GPTR_TEST_HDR_KEY",
                      origin = "https://api.example.test")
  out = http_headers(list(`x-api-key` = h, authorization = list("Bearer ", h),
                          accept = "text/event-stream"), "https://api.example.test")
  expect_identical(out$`x-api-key`, "sk-hdr-test-0123456789abcdef")
  expect_identical(out$authorization, "Bearer sk-hdr-test-0123456789abcdef")
  expect_identical(out$accept, "text/event-stream")
  expect_error(http_headers(list(`x-api-key` = h), "https://evil.example.test"),
               class = "gptr_error_untrusted")
  bad = list(url = "https://evil.example.test/v1", headers = list(`x-api-key` = h))
  expect_error(http_handle(bad), class = "gptr_error_untrusted")
  ok = http_handle(list(url = "https://api.example.test/v1", headers = list(`x-api-key` = h),
                        body = "{}"))
  expect_s3_class(ok, "curl_handle")
})

test_that("layered timeouts: first byte, then idle; no total timeout", {
  local_gptr_options(connect_timeout = 5, first_byte_timeout = 7, idle_timeout = 3)
  t = http_timeouts(list())
  expect_identical(t, list(connect = 5, first_byte = 7, idle = 3))
  expect_identical(http_timeouts(list(idle_timeout = 1))$idle, 1)
  expect_null(http_timeout_check(0, NA_real_, 0, t, now = 6))
  expect_identical(http_timeout_check(0, NA_real_, 0, t, now = 7.5)$class,
                   c("timeout_first_byte", "timeout"))
  expect_null(http_timeout_check(0, 1, 500, t, now = 502))
  expect_identical(http_timeout_check(0, 1, 500, t, now = 504)$class, c("timeout_idle", "timeout"))
  expect_identical(http_timeout_next(0, NA_real_, 0, t), 7)
  expect_identical(http_timeout_next(0, 1, 500, t), 503)
})

test_that("origins use complete validated authorities and canonical IP addresses", {
  for (url in c("http://example.test:bad/path", "http://example.test:99999/",
                "http://example.test:80suffix/", "http://example.test\r\n/path",
                "http://[not-ipv6]/")) {
    expect_true(is.na(url_origin(url)))
  }
  expect_identical(url_origin("http://[::1]:11434/v1"), "http://[::1]:11434")
  expect_identical(url_origin("http://127.1/v1"), "http://127.0.0.1")
  expect_identical(url_origin("http://2130706433/v1"), "http://127.0.0.1")
  expect_identical(url_for_log("http://user:pass@example.test:80/p?key=hidden#f"),
                   "http://example.test/p")
})

test_that("header names and values must match the scalar request contract", {
  bad = list(list("unnamed"), list(x = NA_character_), list(x = c("a", "b")),
             list(x = 12), list(x = "secret\r\nInjected: yes"),
             list("bad\nname" = "x"), list(x = list(named = "piece")),
             list(X = "one", x = "two"))
  for (headers in bad) {
    expect_error(http_headers(headers, "https://example.test"),
                 class = "gptr_error_invalid_argument")
  }
  expect_identical(http_headers(list(x = list("a", "b")), "https://example.test"),
                   list(x = "ab"))
})

test_that("invalid request specs and timeouts fail before curl can send", {
  for (value in list(NA_real_, Inf, -1, 0, c(1, 2), "1", TRUE)) {
    expect_error(http_timeouts(list(connect_timeout = value)),
                 class = "gptr_error_invalid_argument")
    expect_error(http_timeouts(list(idle_timeout = value)),
                 class = "gptr_error_invalid_argument")
  }
  for (spec in list(list(url = "file:///private/file"),
                   list(url = "http://example.test:bad"),
                   list(url = "https://example.test", method = "POST\r\nExtra"),
                   list(url = "https://example.test", body = c("a", "b")),
                   list(url = "https://example.test", body = list(a = 1)))) {
    expect_error(http_handle(spec), class = "gptr_error_invalid_argument")
  }
  expect_s3_class(http_handle(list(url = "https://example.test", body = charToRaw("{}"))),
                  "curl_handle")
})

test_that("request fields match exactly and HEAD configures a bodyless response", {
  local_gptr_options(idle_timeout = 90)
  captured = new.env(parent = emptyenv())
  captured$options = list()
  local_mocked_bindings(
    new_handle = function(...) new.env(parent = emptyenv()),
    handle_setopt = function(handle, ...) {
      captured$options = utils::modifyList(captured$options, list(...))
      invisible(handle)
    },
    handle_setheaders = function(handle, .list) {
      captured$headers = .list
      invisible(handle)
    },
    .package = "curl"
  )
  spec = list(url = "https://example.test", method_override = "DELETE",
              body_hash = "metadata", headers_extra = list(x = "metadata"),
              idle_timeout_extra = 0.2)
  http_handle(spec)
  expect_identical(captured$options$httpget, 1L)
  expect_null(captured$options$customrequest)
  expect_null(captured$options$copypostfields)
  expect_identical(captured$headers, list(Expect = ""))
  expect_identical(http_timeouts(spec)$idle, 90)
  captured$options = list()
  http_handle(list(url = "https://example.test", method = "HEAD"))
  expect_identical(captured$options$nobody, 1L)
})

request_spec = function(srv, ...) {
  utils::modifyList(list(url = paste0(srv$url, "/v1/messages"), method = "POST",
         headers = list(`content-type` = "application/json"),
         body = "{\"model\":\"mock-1\",\"stream\":true,\"messages\":[]}", stream = "sse"),
    list(...))
}

# Run one transfer until it ends (not called run_request(): P06 defines that internal function)
request_until_done = function(spec, timeout = 120, provider = NULL) {
  st = new.env()
  st$bytes = 0
  st$done = FALSE
  st$fail = NULL
  st$status = NA_integer_
  st$t0 = reactor_now()
  reactor_http(spec, on_bytes = function(x) st$bytes = st$bytes + length(x),
               on_done = function(status, headers) {
                 st$status = status
                 st$done = TRUE
               },
               on_fail = function(cnd) {
                 st$fail = cnd
                 st$done = TRUE
               },
               provider = provider)
  reactor_pump(until = function() st$done, timeout = timeout)
  st$elapsed = reactor_now() - st$t0
  st
}

test_that("INFRA-05: held headers give gptr_error_timeout_first_byte", {
  local_gptr_options(first_byte_timeout = 1)
  srv = local_mock_server("hold_headers")
  st = request_until_done(request_spec(srv), timeout = 30, provider = "mock")
  expect_s3_class(st$fail, "gptr_error_timeout_first_byte")
  expect_s3_class(st$fail, "gptr_error_timeout")
  expect_identical(st$fail$seconds, 1)
  expect_identical(st$fail$provider, "mock")
  expect_lt(st$elapsed, 5)
})

test_that("INFRA-05: a stall mid-stream gives gptr_error_timeout_idle", {
  local_gptr_options(idle_timeout = 1)
  srv = local_mock_server("stall")
  st = request_until_done(request_spec(srv), timeout = 30)
  expect_gt(st$bytes, 0)
  expect_s3_class(st$fail, "gptr_error_timeout_idle")
  expect_lt(st$elapsed, 5)
})

test_that("INFRA-05: a stream sending one byte every 10 s for 60 s completes", {
  # idle 15 s: the 10 s gaps stay under the idle timer, while 60 s is far beyond idle + 30 s,
  # where libcurl's low-speed check (1 byte/s averaged) would have ended the stream
  local_gptr_options(idle_timeout = 15)
  srv = local_mock_server("bytes_per_10s", duration = 60)
  st = request_until_done(request_spec(srv), timeout = 120)
  expect_null(st$fail)
  expect_identical(st$status, 200L)
  expect_gte(st$elapsed, 55)
})

test_that("IC-64: a redirect is never followed and never carries the key", {
  srv = local_mock_server("redirect")
  key = "sk-redirect-test-0123456789abcdef"
  h = secret_register(key, "GPTR_TEST_REDIRECT_KEY", origin = url_origin(srv$url))
  st = request_until_done(request_spec(srv, headers = list(`x-api-key` = h)), timeout = 30)
  expect_s3_class(st$fail, "gptr_error_redirect")
  expect_s3_class(st$fail, "gptr_error_provider")
  expect_false(is.na(st$fail$location_origin))
  expect_false(identical(st$fail$location_origin, url_origin(srv$url)))
  # P01's mock logs the requests of both origins; the first redacts key headers in its log, the
  # second (the foreign server) logs every header byte it receives. One logged request, on the
  # first origin's path, proves that the redirect target received nothing at all.
  lg = srv$log()
  expect_identical(nrow(lg), 1L)
  expect_identical(lg$path, "/v1/messages")
  expect_false(any(grepl(key, lg$headers, fixed = TRUE)))
  expect_false(grepl(key, conditionMessage(st$fail), fixed = TRUE))
})
