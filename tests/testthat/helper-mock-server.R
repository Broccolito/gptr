# The base-R mock provider server (contract section 12.2, IC-45, IC-60, IC-64, IC-71; report 15
# section 5.1, report 10a appendix A.1). The server script is fixtures/mock_server.R, run with
# rscript_path() through processx for one test and stopped when the test ends.

mock_scenarios = c(
  "stream", "slow", "ttft", "hold_headers", "stall", "bytes_per_10s", "overload", "status",
  "spend_cap", "truncated", "parallel_tools", "openai_responses", "chat_completions", "gemini",
  "systemone", "json", "redirect"
)

# The adapter api each scenario speaks (every other scenario is Anthropic-shaped)
mock_api = function(scenario) {
  switch(scenario,
    openai_responses = "openai-responses",
    chat_completions = "openai-completions",
    gemini = "google-generative-ai",
    systemone = "typesafe-system-one",
    "anthropic-messages"
  )
}

# A provider record for the mock: offline = TRUE (IC-45), local = TRUE, no credential
mock_provider = function(scenario, url) {
  api = mock_api(scenario)
  type = if (identical(scenario, "systemone")) "classifier" else "chat"
  id = if (identical(type, "chat")) "mock-1" else "mock-s1"
  model = list(
    ref = paste0("mock/", id), provider = "mock", id = id, name = paste("Mock", id),
    family = "mock", api = api, type = type, release_date = NA_character_, context = 200000,
    max_output = 8192, reasoning = TRUE, thinking_levels = c("off", "low", "medium", "high"),
    thinking = NULL, input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
    prices = data.frame(
      from = as.Date("2026-01-01"), tier = "default", input = 0, output = 0, cache_read = 0,
      cache_write_5m = 0, cache_write_1h = 0
    ),
    cache_min = NA_real_,
    capabilities = list(mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
                        operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE),
    aliases = character(), status = "active", local = TRUE
  )
  structure(
    list(
      kind = "provider", name = "mock", id = "mock", api = api, type = type, base_url = url,
      auth = NULL, models = list(model), compat = list(), headers = list(), discover = NULL,
      status = NULL, aliases = character(), local = TRUE, offline = TRUE, rate = NULL,
      api_version = "1.0"
    ),
    class = c("gptr_provider", "gptr_spec")
  )
}

# The JSON records of a mock log; a line the server is still writing is skipped
mock_records = function(file) {
  if (!file.exists(file)) return(list())
  lines = readLines(file, encoding = "UTF-8", warn = FALSE)
  records = lapply(lines[nzchar(lines)], function(line) {
    tryCatch(json_decode(line), error = function(e) NULL)
  })
  Filter(Negate(is.null), records)
}

# The request log as a data frame: one row per request, `disconnected` NA while it is open (the
# end of a request is logged just after its last byte, so poll before asserting it). Header
# values are redacted except at the second origin of `redirect` (IC-64).
mock_log = function(file) {
  records = mock_records(file)
  kinds = vapply(records, function(r) r$kind, "")
  requests = records[kinds == "request"]
  if (!length(requests)) {
    return(data.frame(
      time = as.POSIXct(numeric(), origin = "1970-01-01"), method = character(),
      path = character(), headers = character(), body = character(), disconnected = logical()
    ))
  }
  ends = records[kinds == "end"]
  end_ids = vapply(ends, function(r) as.integer(r$id), integer(1))
  out = data.frame(
    time = as.POSIXct(vapply(requests, function(r) r$time, numeric(1)), origin = "1970-01-01"),
    method = vapply(requests, function(r) r$method, ""),
    path = vapply(requests, function(r) r$path, ""),
    headers = vapply(requests, function(r) r$headers, ""),
    body = vapply(requests, function(r) r$body, ""),
    disconnected = NA
  )
  for (i in seq_along(requests)) {
    hit = which(end_ids == as.integer(requests[[i]]$id))
    if (length(hit)) out$disconnected[[i]] = isTRUE(ends[[hit[[1L]]]]$disconnected)
  }
  out
}

# The writes the mock logged when started with `log_writes = TRUE` (DEVIATIONS D-016): one row
# per response piece, `id` = its request, `time` = wall-clock seconds (Sys.time()) just before the
# write, `event` = the SSE event the piece starts with ("head" for the response head, "" for other
# bytes).
mock_writes = function(file) {
  records = Filter(function(r) identical(r$kind, "write"), mock_records(file))
  if (!length(records)) return(data.frame(id = integer(), time = numeric(), event = character()))
  data.frame(
    id = vapply(records, function(r) as.integer(r$id), integer(1)),
    time = vapply(records, function(r) as.numeric(r$time), numeric(1)),
    event = vapply(records, function(r) r$event, "")
  )
}

# Start the mock server for the calling test; see contract section 12.2 for the scenarios.
# `...` are scenario arguments (n, interval, delay, status, body, retry_after, answers, headers,
# chunked, log_writes, ...); function arguments are sent to the child without their environment.
# Beyond contract 12.2, the result also has `writes()` (mock_writes(), D-016).
local_mock_server = function(scenario, ..., .env = parent.frame()) {
  testthat::skip_on_cran()
  if (!(scenario %in% mock_scenarios)) stop("unknown mock scenario: ", scenario)
  bypass = c("127.0.0.1", "localhost", "::1")
  proxies = lapply(c("no_proxy", "NO_PROXY"), function(name) {
    paste(c(Sys.getenv(name), bypass), collapse = ",")
  })
  names(proxies) = c("no_proxy", "NO_PROXY")
  withr::local_envvar(proxies, .local_envir = .env)
  args = list(...)
  for (name in names(args)) {
    if (is.function(args[[name]])) environment(args[[name]]) = baseenv()
  }
  dir = withr::local_tempdir("gptr-mock-", .local_envir = .env)
  tmp = file.path(dir, "tmp")
  dir.create(tmp)
  token = id_new("", 24L)
  config = list(
    ports = port_candidates(20L), token = token, scenario = scenario, args = args,
    log = file.path(dir, "log.jsonl"), ready = file.path(dir, "ready.json"),
    parent_pid = Sys.getpid()
  )
  config_file = file.path(dir, "config.rds")
  saveRDS(config, config_file)
  script = normalizePath(testthat::test_path("fixtures", "mock_server.R"), winslash = "/")
  env = c(
    "current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
    TMPDIR = tmp, TMP = tmp, TEMP = tmp
  )
  proc = processx::process$new(
    rscript_path(), c("--vanilla", script, config_file), env = env,
    stdout = file.path(dir, "stdout.txt"), stderr = file.path(dir, "stderr.txt"),
    supervise = FALSE, cleanup = TRUE
  )
  stop_server = function() {
    if (proc$is_alive()) proc$kill()
    invisible(NULL)
  }
  withr::defer(stop_server(), envir = .env)
  deadline = Sys.time() + 30
  while (!file.exists(config$ready)) {
    if (!proc$is_alive()) {
      errors = readLines(file.path(dir, "stderr.txt"), encoding = "UTF-8", warn = FALSE)
      stop("the mock server exited: ", paste(errors, collapse = "\n"))
    }
    if (Sys.time() > deadline) stop("the mock server did not start within 30 s")
    Sys.sleep(0.05)
  }
  ready = json_decode(readLines(config$ready, encoding = "UTF-8"))
  url = sprintf("http://127.0.0.1:%d/%s", as.integer(ready$port), token)
  list(
    url = url,
    port = as.integer(ready$port),
    log = function() mock_log(config$log),
    writes = function() mock_writes(config$log),
    stop = stop_server,
    provider = mock_provider(scenario, url)
  )
}

# A streaming request spec for the mock server (its `url` carries the per-run token); `...`
# overrides fields
mock_spec = function(srv, ...) {
  utils::modifyList(list(url = paste0(srv$url, "/v1/messages"), method = "POST",
         headers = list(`content-type` = "application/json", accept = "text/event-stream"),
         body = "{\"model\":\"mock-1\",\"stream\":true,\"messages\":[]}", stream = "sse"),
    list(...))
}
