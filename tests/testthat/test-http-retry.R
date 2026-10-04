test_that("parse_http_date() is locale-independent and rejects junk", {
  expect_identical(parse_http_date("Wed, 21 Oct 2015 07:28:00 GMT"), 1445412480)
  expect_true(is.na(parse_http_date("soon")))
  expect_true(is.na(parse_http_date("Wed, 21 Okt 2015 07:28:00 GMT")))
  old = Sys.getlocale("LC_TIME")
  withr::defer(Sys.setlocale("LC_TIME", old))
  ok = nzchar(suppressWarnings(Sys.setlocale("LC_TIME", "de_DE.UTF-8")))
  skip_if_not(ok, "the de_DE.UTF-8 locale is not installed")
  expect_identical(parse_http_date("Wed, 21 Oct 2015 07:28:00 GMT"), 1445412480)
  lt = as.POSIXlt(Sys.time() + 3, tz = "GMT")
  http = sprintf("%s, %02d %s %d %02d:%02d:%02d GMT",
                 c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[lt$wday + 1L], lt$mday,
                 month.abb[lt$mon + 1L], lt$year + 1900L, lt$hour, lt$min, as.integer(lt$sec))
  s = retry_after_seconds(list(`Retry-After` = http))
  expect_gt(s, 0.5)
  expect_lt(s, 4)
})

test_that("retry-after values: ms first, then seconds; unparsable falls back to backoff", {
  expect_identical(retry_after_seconds(list(`retry-after-ms` = "1500", `retry-after` = "9")), 1.5)
  expect_identical(retry_after_seconds(list(`retry-after` = "2")), 2)
  expect_null(retry_after_seconds(list(`retry-after` = "soon")))
  cl = retry_classify(429L, list(`retry-after` = "soon"))
  expect_true(cl$retry)
  expect_null(cl$delay)
  expect_identical(cl$class, c("rate_limit", "provider"))
})

test_that("retry_classify() implements the retry table", {
  r2 = retry_classify(429L, list(`retry-after` = "2"))
  expect_true(r2$retry)
  expect_identical(r2$delay, 2)
  far = retry_classify(429L, list(`retry-after` = "3600"))
  expect_false(far$retry)
  expect_identical(far$class, c("retry_after", "provider"))
  expect_identical(far$retry_after, 3600)
  expect_match(far$message, "3600")
  spend_body = charToRaw(paste0("{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",",
                                "\"message\":\"limit\",\"details\":{\"error_code\":",
                                "\"enforced_spend_limit_reached\"}}}"))
  spend = retry_classify(429L, list(), body = spend_body)
  expect_false(spend$retry)
  expect_identical(spend$class, c("spend_cap", "provider"))
  expect_identical(retry_classify(401L, list())$class, c("auth", "provider"))
  expect_false(retry_classify(403L, list())$retry)
  over_body = paste0("{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",",
                     "\"message\":\"Overloaded\"}}")
  over = retry_classify(529L, list(), body = over_body)
  expect_true(over$retry)
  expect_identical(over$class, c("overloaded", "provider"))
  expect_match(over$message, "overloaded_error: Overloaded", fixed = TRUE)
  expect_true(retry_classify(408L, list())$retry)
  expect_true(retry_classify(409L, list())$retry)
  expect_false(retry_classify(400L, list())$retry)
  red = retry_classify(307L, list(location = "https://evil.example:8443/steal?x=1"))
  expect_false(red$retry)
  expect_identical(red$class, c("redirect", "provider"))
  expect_match(red$message, "https://evil.example:8443", fixed = TRUE)
  expect_false(grepl("steal", red$message, fixed = TRUE))
})

test_that("retry_classify() keeps the service's message from FastAPI detail bodies (report 04a)", {
  auth_body = charToRaw(paste0("{\"detail\":{\"error_type\":\"authentication_error\",",
                               "\"message\":\"Cannot authenticate with the server.\"}}"))
  auth = retry_classify(401L, list(), body = auth_body)
  expect_identical(auth$class, c("auth", "provider"))
  expect_identical(auth$message,
                   "HTTP 401 authentication_error: Cannot authenticate with the server.")
  rl_body = paste0("{\"detail\":{\"error_type\":\"rate_limit_error\",",
                   "\"message\":\"Rate limit exceeded.\"}}")
  rl = retry_classify(429L, list(), body = rl_body)
  expect_true(rl$retry)
  expect_identical(rl$message, "HTTP 429 rate_limit_error: Rate limit exceeded.")
  invalid_body = paste0("{\"detail\":[{\"loc\":[\"body\",\"state\"],\"msg\":\"Field required\",",
                        "\"type\":\"missing\"},{\"loc\":[\"body\",\"model\"],",
                        "\"msg\":\"Field required\",\"type\":\"missing\"}]}")
  invalid = retry_classify(422L, list(), body = invalid_body)
  expect_false(invalid$retry)
  expect_identical(invalid$message,
                   "HTTP 422: body.state: Field required; body.model: Field required")
  plain = retry_classify(400L, list(), body = "{\"detail\":\"Not authenticated\"}")
  expect_identical(plain$message, "HTTP 400: Not authenticated")
  top_body = paste0("{\"error_type\":\"FUNCTION_INVOCATION_FAILED\",",
                    "\"message\":\"A server error occurred\"}")
  top = retry_classify(500L, list(), body = top_body)
  expect_identical(top$message, "HTTP 500 FUNCTION_INVOCATION_FAILED: A server error occurred")
  text = retry_classify(503L, list(), body = "upstream connect error")
  expect_identical(text$message, "HTTP 503")
})

test_that("transport failures are classified from the libcurl message", {
  slow = retry_classify(NA, list(), curl_error = "Operation too slow. Less than 1 bytes/sec")
  expect_identical(slow$class, c("timeout_idle", "timeout"))
  expect_false(slow$retry)
  conn = retry_classify(NA, list(), curl_error = "Connection timed out after 20001 milliseconds")
  expect_identical(conn$class, c("timeout_connect", "timeout"))
  expect_true(conn$retry)
  net = retry_classify(NA, list(), curl_error = "Could not resolve host: nowhere.invalid")
  expect_identical(net$class, c("network", "provider"))
  expect_true(net$retry)
})

test_that("backoff is 0.5 s * 2^(attempt - 1), capped at 8 s, and RNG-free", {
  seed_before = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  d = vapply(1:8, retry_backoff, 0)
  expect_identical(get0(".Random.seed", envir = globalenv(), inherits = FALSE), seed_before)
  expect_true(all(d > 0))
  expect_lte(d[1], 0.5)
  expect_gte(d[1], 0.375)
  expect_lte(max(d), 8)
  expect_gte(d[8], 6)
})

test_that("transport_error() builds an unsignalled classed condition", {
  cnd = transport_error("HTTP 429", c("rate_limit", "provider"), provider = "anthropic",
                        retry_after = 2)
  expect_identical(class(cnd), c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error",
                                 "error", "condition"))
  expect_identical(cnd$retry_after, 2)
  expect_identical(cnd$provider, "anthropic")
})

test_that("RFC 3339 and duration resets parse without the locale", {
  expect_identical(parse_rfc3339("2015-10-21T07:28:00Z"), 1445412480)
  expect_identical(parse_rfc3339("2015-10-21T09:28:00+02:00"), 1445412480)
  expect_identical(parse_rfc3339("2015-10-21T07:28:00.500Z"), 1445412480.5)
  expect_identical(parse_duration("6m0s"), 360)
  expect_identical(parse_duration("20ms"), 0.02)
  expect_identical(parse_duration("1.5"), 1.5)
  expect_true(is.na(parse_duration("later")))
})

test_that("reset parsing rejects impossible offsets and nonfinite or negative durations", {
  for (x in c("2015-10-21T07:28:00+25:00", "2015-10-21T07:28:00-02:99",
              "2015-02-31T07:28:00Z", "2015-10-21T25:00:00Z")) {
    expect_true(is.na(parse_rfc3339(x)))
  }
  for (x in c("Inf", "-1", "1e999", paste0(strrep("9", 320), "h"))) {
    expect_true(is.na(parse_duration(x)))
  }
  expect_identical(parse_duration("0"), 0)
  expect_null(retry_after_seconds(list(`retry-after` = "Inf")))
  expect_identical(retry_after_seconds(list(`retry-after-ms` = "Inf", `retry-after` = "2")), 2)
})

test_that("retry limits and attempt counters reject malformed configuration", {
  for (attempt in list(NA_real_, Inf, -1, 0, 1.5, TRUE, "2", c(1, 2))) {
    expect_error(retry_backoff(attempt), class = "gptr_error_invalid_argument")
  }
  expect_true(is.finite(retry_backoff(1e12)))
  for (limit in list(NA_real_, Inf, -1, "2", c(1, 2))) {
    withr::with_options(list(gptr.max_retry_delay = limit), {
      expect_error(retry_classify(429L, list()), class = "gptr_error_invalid_argument")
    })
  }
  expect_false(retry_classify(600L, list())$retry)
})

test_that("invalid text in an error body does not replace the transport failure", {
  result = retry_classify(503L, list(), body = as.raw(c(65, 0, 66)))
  expect_identical(result$class, c("overloaded", "provider"))
  expect_identical(result$message, "HTTP 503")
  expect_true(result$retry)
})

test_that("only recognized error code fields can indicate the spend cap", {
  body = paste0('{"error":{"type":"rate_limit_error","message":"retry later"},',
                 '"trace_id":"enforced_spend_limit_reached"}')
  result = retry_classify(429L, list(), body = body)
  expect_true(result$retry)
  expect_identical(result$class, c("rate_limit", "provider"))
  expect_null(retry_after_seconds(list(`retry-after` = list(character()))))
})
