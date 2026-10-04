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

test_that("the limiter gates admission from headers and never waits", {
  ratelimit_update("rl-unit-a", list(`x-ratelimit-remaining-requests` = "2",
                                     `x-ratelimit-reset-requests` = "400ms"))
  expect_true(ratelimit_admit("rl-unit-a"))
  expect_true(ratelimit_admit("rl-unit-a"))
  expect_false(ratelimit_admit("rl-unit-a"))
  expect_gt(ratelimit_next("rl-unit-a"), reactor_now())
  Sys.sleep(0.45)
  expect_true(ratelimit_admit("rl-unit-a"))
  expect_true(ratelimit_admit(NULL))
  ratelimit_update("rl-unit-a2", list(`x-ratelimit-remaining-requests` = "0",
                                      `x-ratelimit-reset-requests` = "30s"))
  t0 = reactor_now()
  expect_false(ratelimit_admit("rl-unit-a2"))
  # the window lasts 30 s: an admission that waited for it would take that long
  expect_lt(reactor_now() - t0, 5)
})

test_that("a 429 retry-after blocks the provider and static rates feed the same bucket", {
  ratelimit_update("rl-unit-b", list(`retry-after` = "1"))
  expect_false(ratelimit_admit("rl-unit-b"))
  ratelimit_set("rl-unit-c", list(requests_per_s = 2))
  expect_true(ratelimit_admit("rl-unit-c"))
  expect_true(ratelimit_admit("rl-unit-c"))
  expect_false(ratelimit_admit("rl-unit-c"))
  expect_lt(ratelimit_next("rl-unit-c") - reactor_now(), 0.6)
})

test_that("Anthropic token headers block until their reset", {
  reset = format(as.POSIXct(Sys.time() + 30), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ratelimit_update("rl-unit-d", list(`anthropic-ratelimit-tokens-remaining` = "0",
                                     `anthropic-ratelimit-tokens-reset` = reset))
  expect_false(ratelimit_admit("rl-unit-d"))
  expect_gt(ratelimit_next("rl-unit-d") - reactor_now(), 20)
})

test_that("a retry-after longer than gptr.max_retry_delay parks the provider for the cap only", {
  local_gptr_options(max_retry_delay = 2)
  ratelimit_update("rl-unit-e", list(`retry-after` = "3600"))
  expect_false(ratelimit_admit("rl-unit-e"))
  expect_lt(ratelimit_next("rl-unit-e") - reactor_now(), 2.1)
  expect_true(ratelimit_admit("rl-unit-unknown"))
})

test_that("static rates come from the provider record through the registry", {
  local_mocked_bindings(registry_get = function(kind, name, session = NULL) {
    if (identical(kind, "provider") && identical(name, "rl-unit-typesafe")) {
      list(rate = list(requests_per_s = 40, tokens_per_s = 1e5))
    }
  })
  st = ratelimit_get("rl-unit-typesafe")
  expect_identical(st$rate$requests_per_s, 40)
  admitted = sum(vapply(1:60, function(i) ratelimit_admit("rl-unit-typesafe"), NA))
  expect_gte(admitted, 40L)
  expect_lt(admitted, 60L)
})

test_that("fractional static rates permit one request and refill without moving deadlines", {
  clock = new.env()
  clock$now = 100
  local_mocked_bindings(reactor_now = function() clock$now)
  ratelimit_set("rl-fractional", list(requests_per_s = 0.5))
  expect_true(ratelimit_admit("rl-fractional"))
  expect_false(ratelimit_admit("rl-fractional"))
  expect_equal(ratelimit_next("rl-fractional"), 102)
  clock$now = 101
  expect_equal(ratelimit_next("rl-fractional"), 102)
  clock$now = 102
  expect_identical(ratelimit_next("rl-fractional"), Inf)
  expect_true(ratelimit_admit("rl-fractional"))
  expect_false(ratelimit_admit("rl-fractional"))
})

test_that("static rates and provider identities reject invalid values without mutation", {
  st = ratelimit_set("rl-validation", list(requests_per_s = 2))
  for (value in list(0, -1, Inf, NA_real_, NaN, 1 + 1i, "2", TRUE, c(1, 2))) {
    expect_error(ratelimit_set("rl-validation", list(requests_per_s = value)),
                 class = "gptr_error_invalid_argument")
    expect_identical(st$rate$requests_per_s, 2)
    expect_error(ratelimit_set("rl-validation", list(tokens_per_s = value)),
                 class = "gptr_error_invalid_argument")
  }
  expect_error(ratelimit_set("rl-validation", list(2)), class = "gptr_error_invalid_argument")
  expect_error(ratelimit_set("rl-validation", list(other = 2)),
               class = "gptr_error_invalid_argument")
  for (provider in list("", NA_character_, character(), c("a", "b"), 1)) {
    expect_error(ratelimit_get(provider), class = "gptr_error_invalid_argument")
  }
  local_mocked_bindings(registry_get = function(...) list(rate = list(requests_per_s = Inf)))
  expect_error(ratelimit_get("rl-invalid-registry"), class = "gptr_error_invalid_argument")
})

test_that("retry cooldown does not exhaust a positive long-lived request window", {
  clock = new.env()
  clock$now = 100
  local_mocked_bindings(reactor_now = function() clock$now)
  local_gptr_options(max_retry_delay = 2)
  ratelimit_update("rl-cooldown", list(`x-ratelimit-remaining-requests` = "5",
    `x-ratelimit-reset-requests` = "3600s", `retry-after` = "10"))
  expect_false(ratelimit_admit("rl-cooldown"))
  expect_equal(ratelimit_next("rl-cooldown"), 102)
  clock$now = 103
  expect_true(ratelimit_admit("rl-cooldown"))
  expect_equal(ratelimit_get("rl-cooldown")$req_remaining, 4)
  for (cap in list(NA_real_, Inf, -1, "2", c(1, 2), 1 + 1i)) {
    withr::with_options(list(gptr.max_retry_delay = cap), {
      expect_error(ratelimit_update("rl-cooldown", list(`retry-after` = "1")),
                   class = "gptr_error_invalid_argument")
    })
  }
})

test_that("independent token windows retain their own exhaustion and reset times", {
  clock = new.env()
  clock$now = 100
  local_mocked_bindings(reactor_now = function() clock$now)
  ratelimit_update("rl-token-windows", list(
    `anthropic-ratelimit-input-tokens-remaining` = "0",
    `anthropic-ratelimit-input-tokens-reset` = "2s",
    `anthropic-ratelimit-output-tokens-remaining` = "100",
    `anthropic-ratelimit-output-tokens-reset` = "30s"))
  expect_false(ratelimit_admit("rl-token-windows"))
  expect_equal(ratelimit_next("rl-token-windows"), 102)
  clock$now = 103
  expect_true(ratelimit_admit("rl-token-windows"))
  ratelimit_update("rl-partial-tokens", list(
    `anthropic-ratelimit-input-tokens-remaining` = "0",
    `anthropic-ratelimit-input-tokens-reset` = "10s"))
  ratelimit_update("rl-partial-tokens", list(
    `anthropic-ratelimit-output-tokens-remaining` = "5",
    `anthropic-ratelimit-output-tokens-reset` = "20s"))
  expect_false(ratelimit_admit("rl-partial-tokens"))
  expect_equal(ratelimit_next("rl-partial-tokens"), 113)
})

test_that("malformed headers cannot poison known budgets or create infinite deadlines", {
  clock = new.env()
  clock$now = 100
  local_mocked_bindings(reactor_now = function() clock$now)
  ratelimit_update("rl-header-values", list(`X-RateLimit-Remaining-Requests` = "2",
    `X-RateLimit-Reset-Requests` = "10s"))
  for (value in list("Inf", "-Inf", "NaN", "junk", c("1", "2"), list("3"))) {
    ratelimit_update("rl-header-values", list(`x-ratelimit-remaining-requests` = value))
    expect_equal(ratelimit_get("rl-header-values")$req_remaining, 2)
    expect_equal(ratelimit_get("rl-header-values")$req_reset, 110)
  }
  ratelimit_update("rl-negative-header", list(`x-ratelimit-remaining-requests` = "-2"))
  expect_false(ratelimit_admit("rl-negative-header"))
  expect_equal(ratelimit_get("rl-negative-header")$req_remaining, 0)
  clock$now = 1e308
  ratelimit_update("rl-overflow", list(`x-ratelimit-remaining-requests` = "0",
    `x-ratelimit-reset-requests` = "1e308"))
  expect_true(is.finite(ratelimit_next("rl-overflow")))
  st = ratelimit_set("rl-refill-overflow", list(requests_per_s = 1e308))
  st$bucket = 0
  st$bucket_at = 0
  ratelimit_refill(st, clock$now)
  expect_equal(st$bucket, 1e308)
})

test_that("a provider named like the anonymous marker has its own static bucket", {
  local_mocked_bindings(registry_get = function(kind, name, session = NULL) {
    if (identical(name, "(none)")) list(rate = list(requests_per_s = 0.5))
  })
  named = ratelimit_get("(none)")
  anonymous = ratelimit_get(NULL)
  expect_false(identical(named, anonymous))
  expect_equal(named$rate$requests_per_s, 0.5)
  expect_true(ratelimit_admit("(none)"))
  expect_false(ratelimit_admit("(none)"))
  expect_true(ratelimit_admit(NULL))
})
