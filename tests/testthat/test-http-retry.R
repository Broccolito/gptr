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

test_that("a request without a provider is never rate limited", {
  local_mocked_bindings(registry_get = function(kind, name, session = NULL) {
    if (identical(name, "(none)")) list(rate = list(requests_per_s = 0.5))
  })
  expect_equal(ratelimit_get("(none)")$rate$requests_per_s, 0.5)
  expect_true(ratelimit_admit("(none)"))
  expect_false(ratelimit_admit("(none)"))
  expect_true(ratelimit_admit(NULL))
  expect_identical(ratelimit_next(NULL), Inf)
})

retry_spec = function(srv, ...) {
  utils::modifyList(list(url = paste0(srv$url, "/v1/messages"), method = "POST",
         headers = list(`content-type` = "application/json"),
         body = "{\"model\":\"mock-1\",\"stream\":true,\"messages\":[]}", stream = "sse"),
    list(...))
}

# Run one transfer; `normaliser(st, event)` sees every SSE event, `committed` defaults to
# "a content delta was seen", as provider_stream() wires it (contract 8.4)
retry_run = function(spec, provider = NULL, retry = NULL, normaliser = NULL, timeout = 60) {
  st = new.env()
  st$done = FALSE
  st$fail = NULL
  st$status = NA_integer_
  st$deltas = 0L
  st$notes = list()
  sp = sse_splitter()
  retry = c(retry %||% list(), list(on_retry = function(type, info) {
    st$notes[[length(st$notes) + 1L]] = c(list(type = type), info)
  }))
  if (is.null(retry$committed)) retry$committed = function() st$deltas > 0L
  st$t0 = reactor_now()
  on_bytes = function(x) {
    for (e in sp$push(x)) {
      if (identical(e$event, "content_block_delta")) st$deltas = st$deltas + 1L
      if (!is.null(normaliser)) normaliser(st, e)
    }
  }
  on_done = function(status, headers) {
    st$status = status
    st$done = TRUE
  }
  on_fail = function(cnd) {
    st$fail = cnd
    st$done = TRUE
  }
  st$id = reactor_http(spec, on_bytes = on_bytes, on_done = on_done, on_fail = on_fail,
                       provider = provider, retry = retry)
  reactor_pump(until = function() st$done, timeout = timeout)
  st$elapsed = reactor_now() - st$t0
  st
}

test_that("INFRA-06: retry-after: 2 is honoured before the stream succeeds", {
  srv = local_mock_server("status", status = 429L, retry_after = 2, succeed_after = 1L)
  st = retry_run(retry_spec(srv))
  expect_null(st$fail)
  expect_identical(st$status, 200L)
  lg = srv$log()
  expect_identical(nrow(lg), 2L)
  gap = diff(as.numeric(lg$time))
  expect_gte(gap, 1.8)
  expect_lt(gap, 5)
  expect_identical(st$notes[[1]]$type, "retry_start")
  expect_identical(st$notes[[1]]$delay, 2)
  expect_identical(st$notes[[1]]$class, "rate_limit")
  expect_identical(st$notes[[2]]$type, "retry_end")
  expect_true(st$notes[[2]]$ok)
})

test_that("INFRA-06: retry-after: 3600 fails at once and names the delay", {
  srv = local_mock_server("status", status = 429L, retry_after = 3600)
  st = retry_run(retry_spec(srv, request_id = "q00000000abcd"), provider = "mock-ra")
  expect_s3_class(st$fail, "gptr_error_retry_after")
  expect_s3_class(st$fail, "gptr_error_provider")
  expect_identical(st$fail$retry_after, 3600)
  expect_identical(st$fail$status, 429L)
  expect_identical(st$fail$provider, "mock-ra")
  expect_match(conditionMessage(st$fail), "3600")
  expect_lt(st$elapsed, 5)
  expect_identical(nrow(srv$log()), 1L)
})

test_that("INFRA-06: a spend-cap 429 is never retried", {
  srv = local_mock_server("spend_cap")
  st = retry_run(retry_spec(srv))
  expect_s3_class(st$fail, "gptr_error_spend_cap")
  expect_identical(st$fail$status, 429L)
  expect_identical(nrow(srv$log()), 1L)
  expect_length(st$notes, 0L)
})

test_that("INFRA-06: 5xx is retried with backoff up to success, and at most max_attempts", {
  srv = local_mock_server("status", status = 529L, succeed_after = 2L)
  st = retry_run(retry_spec(srv))
  expect_null(st$fail)
  expect_identical(nrow(srv$log()), 3L)
  expect_identical(vapply(st$notes, function(n) n$type, ""),
                   c("retry_start", "retry_start", "retry_end"))
  always = local_mock_server("status", status = 503L)
  st2 = retry_run(retry_spec(always), retry = list(max_attempts = 2L))
  expect_s3_class(st2$fail, "gptr_error_overloaded")
  expect_identical(nrow(always$log()), 2L)
})

test_that("INFRA-06: an overload before the first delta is retried; after deltas it fails", {
  overload = function(st, e) {
    if (identical(e$event, "error")) {
      reactor_retry(st$id, list(class = "overloaded", status = 529L))
    }
  }
  srv = local_mock_server("overload", attempts = 1L)
  st = retry_run(retry_spec(srv), normaliser = overload)
  expect_null(st$fail)
  expect_identical(nrow(srv$log()), 2L)
  expect_gt(st$deltas, 0L)
  srv2 = local_mock_server("overload", attempts = 1L)
  st2 = retry_run(retry_spec(srv2), retry = list(committed = function() TRUE),
                  normaliser = overload)
  expect_s3_class(st2$fail, "gptr_error_overloaded")
  expect_identical(nrow(srv2$log()), 1L)
})

test_that("an in-stream retry abandons the first attempt for good", {
  # the first attempt would stream for 2 s after the retry; none of it may reach the second
  srv = local_mock_server("stream", n = 8L, interval = 0.25)
  st = new.env()
  st$heads = 0L
  st$deltas = 0L
  st$done = FALSE
  st$fail = NULL
  st$sp = sse_splitter()
  on_headers = function(status, headers) {
    st$heads = st$heads + 1L
    st$sp = sse_splitter()
  }
  on_bytes = function(x) {
    for (e in st$sp$push(x)) {
      if (!identical(e$event, "content_block_delta")) next
      st$deltas = st$deltas + 1L
      if (st$heads == 1L) reactor_retry(st$id, list(class = "overloaded", status = 529L))
    }
  }
  st$id = reactor_http(retry_spec(srv), on_bytes = on_bytes,
                       on_done = function(status, headers) st$done = TRUE,
                       on_fail = function(cnd) {
                         st$fail = cnd
                         st$done = TRUE
                       },
                       on_headers = on_headers, retry = list(committed = function() FALSE))
  expect_true(reactor_pump(until = function() st$done, timeout = 30))
  expect_null(st$fail)
  expect_identical(st$heads, 2L)
  expect_identical(st$deltas, 9L)
  lg = srv$log()
  expect_identical(nrow(lg), 2L)
  expect_true(isTRUE(lg$disconnected[1]))
})

test_that("INFRA-21: a 20-transfer fan-out never exceeds the advertised request budget", {
  srv = local_mock_server("stream", n = 2L, interval = 0.05)
  # the budget resets after about 6 s: a sleep inside a callback would stall the timer below
  reset = format(as.POSIXct(Sys.time() + 7), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ratelimit_update("rl-fanout", list(`anthropic-ratelimit-requests-limit` = "5",
                                     `anthropic-ratelimit-requests-remaining` = "5",
                                     `anthropic-ratelimit-requests-reset` = reset))
  t_reset = ratelimit_get("rl-fanout")$req_reset
  # the budget above is the only limit under test: responses of the mock do not change it
  local_mocked_bindings(ratelimit_update = function(provider, headers) invisible(NULL))
  heads = new.env()
  heads$t = numeric()
  done = new.env()
  done$n = 0L
  ticks = new.env()
  ticks$gap = 0
  ticks$last = reactor_now()
  tick = function() {
    ticks$gap = max(ticks$gap, reactor_now() - ticks$last)
    ticks$last = reactor_now()
    if (done$n < 20L) ticks$id = reactor_timer(reactor_now() + 0.1, tick)
  }
  ticks$id = reactor_timer(reactor_now() + 0.1, tick)
  # the ticker may still be armed when the pump returns: never leak it into later tests
  withr::defer(reactor_cancel(ticks$id))
  for (i in 1:20) {
    reactor_http(retry_spec(srv), on_bytes = function(x) NULL,
                 on_done = function(status, headers) done$n = done$n + 1L,
                 on_fail = function(cnd) done$n = done$n + 1L,
                 on_headers = function(status, headers) heads$t = c(heads$t, reactor_now()),
                 provider = "rl-fanout")
  }
  expect_true(reactor_pump(until = function() done$n == 20L, timeout = 60))
  expect_length(heads$t, 20L)
  expect_lte(sum(heads$t < t_reset), 5L)
  # admission never waited inside a callback: the 100 ms timer kept firing throughout
  expect_lt(ticks$gap, 5)
})

test_that("retry_start cancellation leaves neither transfer nor timer", {
  srv = local_mock_server("status", status = 503L, retry_after = 10)
  r = reactor_get()
  before = reactor_ids(r$timers)
  withr::defer(reactor_cancel(setdiff(reactor_ids(r$timers), before)))
  st = new.env()
  st$cancelled = FALSE
  st$terminal = 0L
  st$id = reactor_http(retry_spec(srv), function(x) NULL,
                       function(status, headers) st$terminal = st$terminal + 1L,
                       function(cnd) st$terminal = st$terminal + 1L,
                       provider = "retry-cancel-fixture",
                       retry = list(on_retry = function(type, info) {
                         if (identical(type, "retry_start")) {
                           reactor_cancel(st$id)
                           st$cancelled = TRUE
                         }
                       }))
  withr::defer(reactor_cancel(st$id))
  expect_true(reactor_pump(until = function() st$cancelled, timeout = 5))
  expect_false(exists(st$id, envir = r$transfers, inherits = FALSE))
  # no timer of this transfer survives (timers of earlier tests may fire meanwhile)
  expect_length(setdiff(reactor_ids(r$timers), before), 0L)
  expect_identical(st$terminal, 0L)
})

test_that("retry_end cancellation suppresses headers of the cancelled attempt", {
  srv = local_mock_server("status", status = 503L, succeed_after = 1L)
  st = new.env()
  st$cancelled = FALSE
  st$heads = 0L
  st$terminal = 0L
  st$id = reactor_http(retry_spec(srv), function(x) NULL,
                       function(status, headers) st$terminal = st$terminal + 1L,
                       function(cnd) st$terminal = st$terminal + 1L,
                       on_headers = function(status, headers) st$heads = st$heads + 1L,
                       retry = list(on_retry = function(type, info) {
                         if (identical(type, "retry_end")) {
                           reactor_cancel(st$id)
                           st$cancelled = TRUE
                         }
                       }))
  withr::defer(reactor_cancel(st$id))
  expect_true(reactor_pump(until = function() st$cancelled, timeout = 10))
  expect_identical(st$heads, 0L)
  expect_identical(st$terminal, 0L)
})

test_that("an old callback error cannot terminate a newer retry attempt", {
  srv = local_mock_server("stream", n = 2L, interval = 0.05)
  st = new.env()
  st$restarted = FALSE
  st$done = FALSE
  st$fail = NULL
  st$id = reactor_http(retry_spec(srv), on_bytes = function(x) {
    if (st$restarted) return(NULL)
    st$restarted = TRUE
    reactor_retry(st$id, list(class = "overloaded", status = 529L, retry_after = 0))
    reactor_pump(until = function() {
      tr = reactor_get()$transfers[[st$id]]
      !is.null(tr) && tr$attempt == 2L && identical(tr$state, "active")
    }, timeout = 5)
    stop("the abandoned attempt callback failed")
  }, on_done = function(status, headers) st$done = TRUE,
  on_fail = function(cnd) st$fail = cnd, retry = list(committed = function() FALSE))
  withr::defer(reactor_cancel(st$id))
  expect_true(reactor_pump(until = function() st$done || !is.null(st$fail), timeout = 10))
  expect_true(st$done)
  expect_null(st$fail)
  expect_identical(nrow(srv$log()), 2L)
})

test_that("a malformed committed result fails closed without retrying", {
  srv = local_mock_server("status", status = 503L)
  st = retry_run(retry_spec(srv), retry = list(max_attempts = 2L,
                                             committed = function() NA))
  expect_s3_class(st$fail, "gptr_error_overloaded")
  expect_identical(nrow(srv$log()), 1L)
  expect_length(st$notes, 0L)
})

test_that("cancellation from committed suppresses both retry and terminal delivery", {
  srv = local_mock_server("status", status = 503L)
  r = reactor_get()
  before = reactor_ids(r$timers)
  withr::defer(reactor_cancel(setdiff(reactor_ids(r$timers), before)))
  st = new.env()
  st$cancelled = FALSE
  st$terminal = 0L
  st$id = reactor_http(retry_spec(srv), function(x) NULL,
                       function(status, headers) st$terminal = st$terminal + 1L,
                       function(cnd) st$terminal = st$terminal + 1L,
                       retry = list(committed = function() {
                         reactor_cancel(st$id)
                         st$cancelled = TRUE
                         TRUE
                       }))
  expect_true(reactor_pump(until = function() st$cancelled, timeout = 5))
  expect_identical(st$terminal, 0L)
  expect_length(setdiff(reactor_ids(r$timers), before), 0L)
  expect_false(exists(st$id, envir = r$transfers, inherits = FALSE))
})

test_that("stream retry hints validate delays and preserve nonretryable classes", {
  st = new.env()
  local_mocked_bindings(reactor_failure = function(r, tr, cl, status, ...) {
    st$classification = cl
    FALSE
  })
  id = reactor_http(list(url = "http://127.0.0.1:1/"), function(x) NULL,
                    function(status, headers) NULL, function(cnd) NULL)
  tr = reactor_get()$transfers[[id]]
  tr$state = "active"
  withr::defer(reactor_cancel(id))
  for (value in list(-1, NA_real_, NaN, Inf, c(1, 2), "soon")) {
    expect_error(reactor_retry(id, list(class = "overloaded", retry_after = value)),
                  class = "gptr_error_invalid_argument")
  }
  for (class in c("auth", "spend_cap", "redirect", "retry_after", "timeout_idle",
                  "timeout_first_byte")) {
    expect_false(reactor_retry(id, list(class = class, status = 529L)))
    expect_false(st$classification$retry)
    expect_identical(st$classification$class[1L], class)
  }
})

# Run one transfer and record its retry events and terminal callbacks in order:
# "retry_start", "retry_end:TRUE" / "retry_end:FALSE", "done", "fail". `on_bytes(st, x)` and
# `on_retry(st, type, info)` may act on the transfer (`st$id`); a hook that cancels it sets
# `st$settled` so the pump returns.
retry_trace = function(spec, retry = list(), on_bytes = NULL, on_retry = NULL, timeout = 20,
                       .env = parent.frame()) {
  st = new.env()
  st$trace = character()
  st$fail = NULL
  st$settled = FALSE
  retry$on_retry = function(type, info) {
    note = if (identical(type, "retry_end")) paste0("retry_end:", info$ok) else type
    st$trace = c(st$trace, note)
    if (!is.null(on_retry)) on_retry(st, type, info)
  }
  st$id = reactor_http(spec, on_bytes = function(x) if (!is.null(on_bytes)) on_bytes(st, x),
                       on_done = function(status, headers) {
                         st$trace = c(st$trace, "done")
                         st$settled = TRUE
                       },
                       on_fail = function(cnd) {
                         st$trace = c(st$trace, "fail")
                         st$fail = cnd
                         st$settled = TRUE
                       },
                       retry = retry)
  withr::defer(reactor_cancel(st$id), envir = .env)
  st$pumped = reactor_pump(until = function() st$settled, timeout = timeout)
  # nothing may arrive after the outcome (a cancelled transfer stays silent)
  reactor_pump(timeout = 0.2)
  st
}

test_that("one retry_end closes a retry, also when the re-sent attempt fails after its head", {
  ok = local_mock_server("status", status = 503L, succeed_after = 1L)
  st = retry_trace(retry_spec(ok))
  expect_identical(st$trace, c("retry_start", "retry_end:TRUE", "done"))
  # the default commitment: a 2xx byte reached on_bytes; the failure comes after the head
  expected = c(stream = "gptr_error_overloaded", callback = "gptr_error_internal")
  for (how in names(expected)) {
    srv = local_mock_server("status", status = 503L, succeed_after = 1L)
    on_bytes = function(st, x) {
      if (!is.null(st$seen)) return(NULL)
      st$seen = TRUE
      if (identical(how, "stream")) {
        reactor_retry(st$id, list(class = "overloaded", status = 529L))
      } else {
        stop("the normaliser failed")
      }
    }
    st = retry_trace(retry_spec(srv), on_bytes = on_bytes)
    expect_identical(st$trace, c("retry_start", "retry_end:TRUE", "fail"), label = how)
    expect_s3_class(st$fail, expected[[how]])
    expect_identical(nrow(srv$log()), 2L)
  }
})

test_that("a failed re-send closes the retry before on_fail; cancelling from retry_end stops it", {
  always = local_mock_server("status", status = 503L)
  hold = local_mock_server("hold_headers")
  real = http_handle
  mode = new.env()
  mode$path = "exhausted"
  mode$calls = 0L
  # the re-send (second handle) cannot start, or goes to a server that never answers
  local_mocked_bindings(http_handle = function(spec) {
    mode$calls = mode$calls + 1L
    if (mode$calls >= 2L && identical(mode$path, "start")) {
      gptr_abort("The request could not be prepared.", "internal", detail = "test")
    }
    if (mode$calls >= 2L && identical(mode$path, "first_byte")) {
      spec$url = paste0(hold$url, "/v1/messages")
    }
    real(spec)
  })
  r = reactor_get()
  before = reactor_ids(r$timers)
  withr::defer(reactor_cancel(setdiff(reactor_ids(r$timers), before)))
  cancel_at_end = function(st, type, info) {
    if (identical(type, "retry_end")) {
      st$cancelled = reactor_cancel(st$id)
      st$settled = TRUE
    }
  }
  expected = c(exhausted = "gptr_error_overloaded", start = "gptr_error_internal",
               first_byte = "gptr_error_timeout_first_byte")
  for (path in names(expected)) {
    for (cancel in c(FALSE, TRUE)) {
      mode$path = path
      mode$calls = 0L
      label = paste(path, if (cancel) "cancelled" else "failed")
      st = retry_trace(retry_spec(always, first_byte_timeout = 1),
                       retry = list(max_attempts = 2L),
                       on_retry = if (cancel) cancel_at_end)
      if (cancel) {
        expect_identical(st$trace, c("retry_start", "retry_end:FALSE"), label = label)
        expect_identical(st$cancelled, 1L, label = label)
        expect_null(st$fail)
      } else {
        expect_identical(st$trace, c("retry_start", "retry_end:FALSE", "fail"), label = label)
        expect_s3_class(st$fail, expected[[path]])
      }
      expect_false(exists(st$id, envir = r$transfers, inherits = FALSE))
    }
  }
  expect_length(setdiff(reactor_ids(r$timers), before), 0L)
})

test_that("stream retry hints keep their class, the integer status and the server's request id", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  cases = list(
    list(info = list(class = "overloaded", status = 529, retry_after = 3600), committed = FALSE,
         class = c("gptr_error_retry_after", "gptr_error_provider")),
    list(info = list(class = "overloaded", status = 529), committed = TRUE,
         class = c("gptr_error_overloaded", "gptr_error_provider")),
    list(info = list(class = "timeout_idle", status = 529), committed = FALSE,
         class = c("gptr_error_timeout_idle", "gptr_error_timeout"))
  )
  fails = list()
  for (i in seq_along(cases)) {
    case = cases[[i]]
    on_bytes = function(st, x) {
      if (is.null(st$asked)) st$asked = reactor_retry(st$id, case$info)
    }
    st = retry_trace(retry_spec(srv, idle_timeout = 7),
                     retry = list(committed = function() case$committed), on_bytes = on_bytes)
    expect_false(st$asked)
    expect_identical(st$trace, "fail")
    for (cl in case$class) expect_s3_class(st$fail, cl)
    expect_identical(st$fail$status, 529L)
    # the request id comes from the server's 2xx head, not from the client's label
    expect_identical(st$fail$request_id, paste0("req_mock_", i))
    fails[[i]] = st$fail
  }
  expect_identical(nrow(srv$log()), length(cases))
  # a retryable hint above gptr.max_retry_delay: no retry; class retry_after names the delay
  expect_identical(fails[[1L]]$retry_after, 3600)
  expect_identical(fails[[1L]]$error_type, "retry_after")
  expect_match(conditionMessage(fails[[1L]]), "wait 3600 s")
  # a stream timeout belongs to the timeout family, with the transfer's idle timeout
  expect_false(inherits(fails[[3L]], "gptr_error_provider"))
  expect_identical(fails[[3L]]$seconds, 7)
})

test_that("a stale callback of an abandoned attempt cannot retry the newer attempt", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  on_bytes = function(st, x) {
    if (!is.null(st$first)) return(NULL)
    st$first = reactor_retry(st$id, list(class = "overloaded", status = 529L, retry_after = 0))
    # a nested pump lets the second attempt start while this old chunk is still delivered
    reactor_pump(until = function() {
      tr = reactor_get()$transfers[[st$id]]
      !is.null(tr) && identical(tr$attempt, 2L) && identical(tr$state, "active")
    }, timeout = 5)
    # the next event of the old chunk asks for a retry again
    st$stale = reactor_retry(st$id, list(class = "overloaded", status = 529L, retry_after = 0))
  }
  st = retry_trace(retry_spec(srv), retry = list(committed = function() FALSE),
                   on_bytes = on_bytes)
  expect_true(st$first)
  expect_false(st$stale)
  expect_identical(st$trace, c("retry_start", "retry_end:TRUE", "done"))
  expect_identical(nrow(srv$log()), 2L)
})

test_that("reactor_retry() reports no re-send when retry_start cancelled the transfer", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  r = reactor_get()
  before = reactor_ids(r$timers)
  withr::defer(reactor_cancel(setdiff(reactor_ids(r$timers), before)))
  cancel_at_start = function(st, type, info) {
    if (identical(type, "retry_start")) {
      st$cancelled = reactor_cancel(st$id)
      st$settled = TRUE
    }
  }
  on_bytes = function(st, x) {
    if (is.null(st$asked)) {
      st$asked = reactor_retry(st$id, list(class = "overloaded", status = 529L))
    }
  }
  st = retry_trace(retry_spec(srv), retry = list(committed = function() FALSE),
                   on_bytes = on_bytes, on_retry = cancel_at_start)
  expect_false(st$asked)
  expect_identical(st$cancelled, 1L)
  expect_identical(st$trace, "retry_start")
  expect_false(exists(st$id, envir = r$transfers, inherits = FALSE))
  expect_length(setdiff(reactor_ids(r$timers), before), 0L)
})
