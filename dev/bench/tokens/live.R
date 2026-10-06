# Live calibration of the token benchmark (architecture 12.5 and 12.7; IC-73). It makes small paid
# requests and one free Anthropic count-tokens request, so it runs only with GPTR_LIVE_TESTS=true.
# From the repository root, after the offline runner has written results.csv:
#   GPTR_LIVE_TESTS=true Rscript --vanilla dev/bench/tokens/live.R
# Optional: GPTR_BENCH_ENV (a .env file read with gptr_env(); keys are never printed),
# GPTR_BENCH_ANTHROPIC (default "sonnet"), GPTR_BENCH_OPENAI (default "gpt") and
# GPTR_BENCH_BUDGET_USD (default 2, the cost limit of each fixture and model). Writes
# dev/bench/tokens/live-<date>.csv and exits 1 when a golden transcript is outside the IC-73
# tolerances: requests within +2 and input tokens within 20% of the golden o200k input scaled by
# the provider prior.

source(file.path("dev", "bench", "common.R"), local = TRUE)

# Provider priors of the estimator (architecture 12.5): projected / o200k tokens.
live_priors = c(anthropic = 1.35, openai = 1.00)

# The golden transcripts in `dir` with their request count and o200k input total from `res`, the
# offline runner's results (NA, so the row fails, when a fixture has no result).
live_fixtures = function(dir, res) {
  lapply(list.files(dir, "[.]json$", full.names = TRUE), function(f) {
    fx = jsonlite::fromJSON(f, simplifyVector = FALSE)
    i = match(fx$id, res$case)
    fx$golden_requests = res$requests[i]
    fx$golden_input = res$input_total[i]
    fx
  })
}

# Requests and input tokens (uncached, cache reads and cache writes) of per-request usage rows
# (contract 4.3); an unknown count stays NA (IC-74), so its row fails.
live_usage = function(u) {
  list(requests = nrow(u), input = sum(u$input, u$cache_read, u$cache_write_5m, u$cache_write_1h),
       cache_read = sum(u$cache_read), cost = sum(u$cost))
}

# One fixture against one real model in mode auto (nobody answers approvals), in a temporary
# project as the golden runner sets it up: the first prompt attaches the fixture's objects by
# name with the fixture's preset, every later turn continues the session. A budget binds one run
# (IC-66), so each turn gets what the earlier turns left of `budget_usd`.
live_run_fixture = function(fx, model, budget_usd) {
  proj = withr::local_tempdir("gptr-live-")
  withr::local_dir(proj)
  withr::local_options(gptr.project_root = proj, gptr.quiet = TRUE)
  dir.create(".gptr")
  for (f in names(fx$files)) {
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    writeLines(fx$files[[f]], f, useBytes = TRUE)
  }
  home = new.env(parent = globalenv())
  for (nm in names(fx$objects)) {
    assign(nm, eval(parse(text = fx$objects[[nm]]), envir = new.env(parent = baseenv())),
           envir = home)
  }
  s = NULL
  status = tryCatch({
    for (turn in fx$turns) {
      budget = list(cost = max(0, budget_usd - sum(s$usage$cost, na.rm = TRUE)))
      s = if (is.null(s)) {
        labels = vapply(turn$context, function(o) o$label, "")
        do.call("peter", c(list(turn$prompt), lapply(labels, as.name),
                           list(model = model, mode = "auto", envir = home, budget = budget,
                                tools = fx$preset)),
                envir = home)
      } else {
        peter(s, prompt = turn$prompt, budget = budget)
      }
    }
    "ok"
  }, error = function(e) paste(class(e)[[1L]], conditionMessage(e)))
  c(list(status = status), if (!is.null(s)) live_usage(s$usage))
}

# The free count-tokens request on the frozen standard prefix, sent as the Anthropic adapter sends
# it, and the prefix's `tok` count: with tok_count() their ratio is the measured prior
# (architecture 12.5 and 12.7).
live_count_prefix = function(model_id, tok) {
  view = gptr_prompt(preset = "standard")
  sys = c(view$system$t0, view$system$t1)
  sys = sys[nzchar(sys)]
  body = list(model = model_id, system = lapply(sys, function(x) list(type = "text", text = x)),
              tools = json_verbatim(as.character(view$tools_json)),
              messages = list(list(role = "user", content = "x")))
  url = "https://api.anthropic.com/v1/messages/count_tokens"
  h = http_handle(list(url = url, body = json_encode(body),
                       headers = list(`content-type` = "application/json",
                                      `anthropic-version` = "2023-06-01",
                                      `x-api-key` = Sys.getenv("ANTHROPIC_API_KEY"))))
  r = curl::curl_fetch_memory(url, handle = h)
  n = if (r$status_code == 200L) json_decode(rawToChar(r$content))$input_tokens
  list(claude = as.numeric(n %||% NA), o200k = sum(tok(c(sys, view$tools_json))))
}

# One row of live-<date>.csv (the columns P25's check-live.R reads); `ok` applies IC-73.
live_row = function(fam, ref, fx, r, prefix) {
  r = utils::modifyList(list(requests = NA_real_, input = NA_real_, cache_read = NA_real_,
                             cost = NA_real_), r)
  prior = live_priors[[fam]]
  ratio = r$input / (fx$golden_input * prior)
  data.frame(date = format(Sys.Date()), provider = fam, model = ref, fixture = fx$id,
             status = r$status, requests_golden = fx$golden_requests, requests_live = r$requests,
             input_golden_o200k = fx$golden_input, prior = prior, input_live = r$input,
             cache_read_live = r$cache_read, cost_live = r$cost, ratio = round(ratio, 3),
             prefix_claude = prefix$claude, prefix_o200k = prefix$o200k,
             cache_read_seen = isTRUE(r$cache_read > 0),
             ok = identical(r$status, "ok") && isTRUE(r$requests <= fx$golden_requests + 2) &&
               isTRUE(abs(ratio - 1) <= 0.2))
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
    message("[bench] live mode is off (set GPTR_LIVE_TESTS=true); nothing was sent")
    return(invisible())
  }
  dir = file.path("dev", "bench", "tokens")
  res = bench_read_csv(file.path(dir, "results.csv"))
  if (is.null(res)) stop("results.csv is missing: run Rscript --vanilla dev/bench/tokens/run.R")
  fixtures = live_fixtures(file.path(dir, "fixtures"), res)
  bench_load_gptr(".")
  Sys.setenv(GPTR_REPLAY = "live")
  env_file = Sys.getenv("GPTR_BENCH_ENV")
  if (nzchar(env_file)) gptr_env(env_file, quiet = TRUE)
  gptr_config(egress = list(anthropic = "ack", openai = "ack"), .scope = "user")
  models = c(anthropic = Sys.getenv("GPTR_BENCH_ANTHROPIC", "sonnet"),
             openai = Sys.getenv("GPTR_BENCH_OPENAI", "gpt"))
  budget = as.numeric(Sys.getenv("GPTR_BENCH_BUDGET_USD", "2"))
  rows = list()
  for (fam in names(models)) {
    ref = model_resolve(models[[fam]])
    prefix = list(claude = NA_real_, o200k = NA_real_)
    if (fam == "anthropic") {
      prefix = live_count_prefix(ref$id, tok_count)
      message(sprintf("[bench] %s: count-tokens / o200k of the standard prefix %.3f (prior %.2f)",
                      ref$ref, prefix$claude / prefix$o200k, live_priors[[fam]]))
    }
    for (fx in fixtures) {
      r = live_run_fixture(fx, models[[fam]], budget)
      rows[[length(rows) + 1L]] = live_row(fam, ref$ref, fx, r, prefix)
    }
  }
  out = do.call(rbind, rows)
  path = file.path(dir, paste0("live-", format(Sys.Date()), ".csv"))
  bench_write_csv(out, path)
  print(out[c("provider", "fixture", "requests_golden", "requests_live", "ratio", "ok")],
        row.names = FALSE)
  message("[bench] wrote ", path)
  bad = out[!out$ok, , drop = FALSE]
  if (nrow(bad)) {
    stop(bench_regression(c("Live calibration outside the IC-73 tolerances:",
                            sprintf("  %s %s: %s, requests %s (golden %s), input ratio %s",
                                    bad$provider, bad$fixture, bad$status, bad$requests_live,
                                    bad$requests_golden, bad$ratio)),
                          fixture = bad$fixture, metric = "live",
                          baseline = bad$input_golden_o200k, value = bad$input_live,
                          details = bad))
  }
}))
