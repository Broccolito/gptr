# P05 Model Layer Core Implementation Plan

> **Design amendment IC-74 (2026-10-03):** Read
> [`../spec/07-local-ollama.md`](../spec/07-local-ollama.md), especially the
> ownership and acceptance matrix in section 6, before executing this plan.
> Mixed Ollama chat/decision models, image decisions, model-level dispatch,
> locality and calibration rules override conflicting code examples below.
> The original task count and exact PASS counts predate this amendment;
> reconcile the affected steps before implementation. No implementation has
> been performed as part of this design update.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give gptr its provider-neutral model layer: provider records as data with origin-bound credentials, the `provider_stream()` transport glue, transcript projection and cross-provider hand-off, usage rows with dated cost, and an offline model catalog with a resolver.

**Architecture:** Four L1 files. `provider-registry.R` declares `builtin:providers` (17 provider records as data) and `builtin:fake`, resolves credentials and base URLs, and drives every adapter transport (`http_*`, `inprocess`, `process_jsonl`) on P04's reactor so that each request emits INFRA-02 events and calls `done()` exactly once; `provider-transform.R` projects a session's JSONL tree into the message list a target model may see and applies Pi's hand-off rules. `catalog-models.R` merges a shipped models.dev snapshot with gptr's overrides and live layers and resolves `provider/id[:thinking]` references, and `provider-usage.R` prices usage rows with dated tiers and TTL-split cache writes.

**Tech Stack:** base R (>= 4.2.0), jsonlite, curl (only through P04's reactor), cli (through P01's `hash_sha256()`), testthat 3e, withr (tests only); curl and pkgload in the maintainer script `dev/catalog/build_models.R` only.

**Spec:** dev/spec/03-architecture.md (sections 2.2, 3.2, 5.2, 5.5, 6.5, 8.1-8.4), dev/spec/04-interface-contract.md (sections 1.1-1.2, 2.2, 3.1-3.2, 4.1-4.9, 5.9, 5.12, 6.2 `gptr_providers()` and `gptr_models()`, 7.0-7.5, 8.1-8.5, 10.1-10.3, 11.2, 11.8-11.10, 12.1-12.3, 15: IC-33, IC-35, IC-45, IC-64, IC-65, IC-67, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P05).

**Depends on:** P02, P03, P04 (and P01 through them). **Milestone:** M1.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full (house style `=` and `|>`, ASCII-only sources, `pkg::fun()`, `gptr_abort()`/`gptr_warn()`/`gptr_inform()`, no `:::` in `R/`, no `.GlobalEnv`, `readLines(..., encoding = "UTF-8")`, connections closed with `on.exit()` in the opening function, testthat 3e, no network in tests, TDD, one commit per task). Plan-specific requirements, copied from the specification:

- Owned files (05 P05): `R/provider-transform.R`, `R/provider-registry.R`, `R/provider-usage.R`, `R/catalog-models.R`, `tests/testthat/test-provider-transform.R`, `tests/testthat/test-provider-registry.R`, `tests/testthat/test-provider-usage.R`, `tests/testthat/test-catalog-models.R`, `inst/extdata/models.json.gz`, `dev/catalog/build_models.R`; plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`.
- Exports (04 section 14.1, P05): `gptr_providers(check = FALSE)` and `gptr_models(query = NULL, provider = NULL, refresh = FALSE)`.
- Internal contract (04 section 7.5), exact signatures: `project_messages(entries, leaf, target)`, `handoff_transform(messages, target)`, `provider_get(id)`, `adapter_get(api)`, `provider_credential(provider)`, `provider_stream(model, context, opts, emit, done, run = NULL)`, `builtin_providers(gptr)`, `usage_new(...)`, `usage_cost(usage, model, when = Sys.Date())`, `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)`, `usage_log_append(row)`, `usage_log()`, `catalog_get()`, `model_resolve(ref, strict = TRUE)`, `catalog_aliases()`, `model_default(role = c("chat", "small", "system1"))`.
- Built-ins (04 section 10.3, IC-08): `builtin:providers` (`provider-registry.R`, replaceable) and `builtin:fake` (factory `builtin_fake()` of P01's `provider-fake.R`, declared here), both through top-level `on_load(ext_declare_builtin("<name>", builtin_<name>))`.
- Package state owned (04 section 7.0): `the$catalog` (merged model catalog) and `the$s1_log` (process System 1 accounting log). Nothing else global; no run state (INFRA-15).
- Conditions (04 section 2.2): `gptr_error_no_key` (fields `provider`, `variables`), `gptr_error_unknown_model` (`ref`, `suggestions`), `gptr_error_not_available` (`member`, `provided_by`), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_network` with parent `gptr_error_provider` (`provider`, `status`, `curl_code`), `gptr_error_invalid_spec` (`kind`, `name`, `field`, `problem`), `gptr_error_internal` (`detail`). Stream failures are classed, unsignalled condition objects carried in `error` events, never signalled after `provider_stream()` returns (INFRA-02).
- Options read through `gptr_opt()` (04 section 3.1): `gptr.max_attempts` = `4L`, `gptr.max_retry_delay` = `60`, `gptr.first_byte_timeout` = `120`, `gptr.idle_timeout` = `90`, `gptr.connect_timeout` = `20`. Settings read through `setting_get()` (04 section 11.2): `providers` = `{<id>: {base_url, models, headers, enabled}}` (a project `base_url` needs trust and a one-time confirmation, enforced by P08's layers; `enabled: false` keeps a provider out of `model_default()` and refuses `provider_stream()`; an optional `rate` is IC-64's settings override of the static rate), `egress` = `{<provider>: "ack"}` (user file only), `model`, `small_model`, `system1`.
- Provider key variables (04 section 3.2): `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `DEEPSEEK_API_KEY`, `MISTRAL_API_KEY`, `TOGETHER_API_KEY`, `XAI_API_KEY`, `CEREBRAS_API_KEY`, `FIREWORKS_API_KEY`, `VLLM_API_KEY`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT` (not secret), `AWS_BEARER_TOKEN_BEDROCK`, `TYPESAFE_API_KEY`. Values are registered at once with `secret_register(..., origin = <provider origin>)`; nothing but a `gptr_secret` handle leaves `provider_credential()`.
- Provider records (04 section 10.2 row 1, IC-35, IC-45, IC-64): fields `id`, `api`, `base_url`, `auth`, `models`, `compat`, `type`, `headers`, `discover`, `status`, `aliases`, `local`, `offline`, `rate`; `offline = TRUE` only for providers that call no remote model (the fake, mock-server and fake-CLI providers); static `rate = list(requests_per_s, tokens_per_s)` (the `typesafe` record of P13: 40 and 1e5), "overridable by settings and catalog" (IC-64): `provider_stream()` passes a `providers.<id>.rate` setting or a catalog `providers.<id>.rate` to P04's `ratelimit_set()`.
- Adapter `opts` (04 section 8.1, IC-33): `emit`, `retry`, `signal`, `credential`, `base_url`, `state`, `memo`, `send`, `gate`, `mcp_dispatch`, `tool_result`, `run`, `session`, `first_byte_timeout`, `idle_timeout`, `connect_timeout`, plus `provider` (the provider record; P01's fake adapter reads `opts$provider$log`). `retry(info)` is wired to P04's `reactor_retry()` (P04 plan, Task 12). `provider_stream()` injects `gate`, `mcp_dispatch` (the `mcp.dispatch_local` service) and `tool_result`; adapters never call L2+ functions.
- Model record (04 section 4.9) plus IC-67 `max_images` and IC-71 `capabilities$forced_tool_choice` (`FALSE` for Anthropic 5.x); IC-73 `cache_min` per model. Thinking levels `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`; a requested level is clamped upwards first, then downwards (Pi `models.ts:1215-1247`).
- Aliases (architecture section 8.4, 04 section 11.10): `sonnet`, `opus`, `haiku`, `gemini`, `flash`, `gpt`, `jev`, `claude_code`, `codex`; a family alias resolves to the newest `active` model of the family by `release_date`. Default chat route: an Anthropic key -> `anthropic/claude-sonnet-5-5`; OpenAI -> `openai/gpt-6-sol`; Gemini -> `google/gemini-3.8-flash`; otherwise a detected CLI.
- Snapshot (04 section 11.10): `inst/extdata/models.json.gz` with `schema_version` 1, `generated`, `source`, `providers`, `models`, `aliases`; merge order snapshot < cache < overrides < user config `providers.*.models` < live discovery of local servers; refresh only on explicit request with ETag into `tools::R_user_dir("gptr", "cache")` as `models.json` + `models.etag` (04 section 11.9). No disk write, network or process at load.
- Usage (04 section 4.3, architecture section 5.5): per-request columns `request_id` (`q` + 12 hex), `session`, `agent`, `parent_id`, `provider`, `model`, `route` (`api`, `plan-cli`, `system-one`, `emulated`), `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`, `reasoning`, `images`, `cost`, `tier`, `stop_reason`, `started`, `seconds`, `estimated`, `multiplier`. Cost from the dated price tier in force on the request date; 1-hour cache writes at 2x input, 5-minute writes at 1.25x input (07 section 3.5).
- Every test runs offline: the fake provider (`gptr_fake_provider()`, `local_fake_provider()`), P04's reactor and process functions replaced with `testthat::local_mocked_bindings()`, and no helper file of our own (05: a plan writes only the files it owns, so small test helpers live at the top of the test file that uses them).

## File Structure

| File | Responsibility |
|---|---|
| `R/provider-usage.R` | usage records (`usage_new()`), dated price tiers and TTL-split cost (`usage_cost()`), usage rows (`usage_row()`), roll-up to root sessions, the process System 1 log (`usage_log_append()`, `usage_log()`) |
| `R/provider-registry.R` | `builtin:providers` and `builtin:fake` declarations; the provider table (architecture section 8.1, compat flags of 09 section 3.3); `provider_get()`, `adapter_get()`, base URLs and origins; `provider_credential()`; `provider_stream()` for the `http_sse`, `http_ndjson`, `http_json`, `inprocess` and `process_jsonl` transports; `gptr_providers()` |
| `R/provider-transform.R` | `handoff_transform()` (Pi `transformMessages()` pass 1 and tool-id normalisers) and `project_messages()` (path walk, compaction cut, failed-turn drop, orphan results, held operator relays) |
| `R/catalog-models.R` | seed entries, gptr overrides, models.dev conversion, snapshot I/O, merge layers, the lookup index, the resolver `model_resolve()`, `catalog_get()`, `catalog_aliases()`, `model_default()`, the explicit ETag refresh, local discovery, `gptr_models()` |
| `tests/testthat/test-provider-usage.R` | usage records, documented dollar amounts, tiers, rows, roll-up, System 1 log |
| `tests/testthat/test-provider-registry.R` | provider records, `builtin:fake`, base URLs, credentials, `provider_stream()` on every transport, `gptr_providers()` |
| `tests/testthat/test-provider-transform.R` | hand-off (INFRA-08) and projection (INFRA-04) |
| `tests/testthat/test-catalog-models.R` | snapshot structure, models.dev conversion, resolver, record fields, local providers (INFRA-17), merge layers, defaults, refresh, offline resolution |
| `inst/extdata/models.json.gz` | the shipped catalog snapshot (built by the script below) |
| `dev/catalog/build_models.R` | maintainer script: models.dev (MIT) + seed + overrides -> `inst/extdata/models.json.gz` |
| `NAMESPACE`, `man/gptr_models.Rd`, `man/gptr_providers.Rd` | generated by `devtools::document()` |

Every command runs from the repository root (`/Users/wanjun/Desktop/gptr`) with `Rscript --vanilla`. The task order follows the dependencies inside the plan: usage records first (the catalog reads their price tables), provider records before the transform (tool-id rules read a provider's compat flags), the catalog before usage rows and the stream glue (both resolve model records).

## Tasks

1. Usage records and dated price tiers (`provider-usage.R`)
2. Provider records as data and the builtin:fake declaration (`provider-registry.R`)
3. Origin-bound provider credentials (`provider-registry.R`)
4. Cross-provider hand-off transform (`provider-transform.R`)
5. Projection of the transcript tree (`provider-transform.R`)
6. Catalog data, models.dev conversion and the shipped snapshot (`catalog-models.R`, `dev/catalog/build_models.R`, `inst/extdata/models.json.gz`)
7. Merged catalog and the model resolver (`catalog-models.R`)
8. `gptr_models()`, defaults, explicit refresh and local discovery (`catalog-models.R`)
9. Usage rows, roll-up and the process System 1 log (`provider-usage.R`)
10. `provider_stream()` glue and the HTTP transports (`provider-registry.R`)
11. The inprocess and process_jsonl transports (`provider-registry.R`)
12. `gptr_providers()` (`provider-registry.R`)

---

### Task 1: Usage records and dated price tiers

**Files:**
- Create: `R/provider-usage.R`
- Test: `tests/testthat/test-provider-usage.R` (create)

**Interfaces:**
- Consumes: `gptr_abort(message, class, ..., .data = NULL, call = NULL)` and the internal `` `%||%` `` (P01, 04 sections 2.1 and 7.1).
- Produces: `usage_new(...)` -> a usage record with fields `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`, `reasoning`, `images`, `total`, `cost` (`list(input, output, cache_read, cache_write, total)`, USD), `estimated` (04 section 4.3); `usage_cost(usage, model, when = Sys.Date())` -> the usage record with `cost` filled from `model$prices` (04 section 7.5). Private helpers used by later tasks: `prices_df(x)` (a model's price table as a data frame with columns `from`, `tier`, `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`), `price_select(prices, prompt_tokens, when = Sys.Date())` (the price row in force), `price_threshold(tier)`.

Price-tier semantics (from Pi's `calculateCost()`, report 03 sections 2.7 and 3.4, extended with dates): the latest price set whose `from` is not after the request date applies; within it a `>Nk` row applies when the prompt (`input + cache_read + cache_write_5m + cache_write_1h`) exceeds N thousand tokens (the highest matching threshold wins), otherwise the base row (`default` or `<=Nk`). Missing cache rates default to the multipliers of report 07 section 3.5 and G2: reads 0.1x input, 5-minute writes 1.25x input, 1-hour writes 2x input.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-usage.R`:

```r
# Tests for R/provider-usage.R (plan P05): usage records, dated price tiers, TTL-split cache
# writes (INFRA-20), usage rows and the process System 1 log.

price_rows = function(...) prices_df(list(...))

opus_like = function() {
  list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 4, output = 20,
                                cache_read = 0.2, cache_write_5m = 5, cache_write_1h = 8)))
}

test_that("usage_new() fills zeros, the total and an empty cost", {
  u = usage_new(input = 10, output = 5, cache_read = 100)
  expect_named(u, c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                    "reasoning", "images", "total", "cost", "estimated"))
  expect_equal(u$total, 115)
  expect_equal(u$cache_write_1h, 0)
  expect_equal(u$cost, list(input = 0, output = 0, cache_read = 0, cache_write = 0, total = 0))
  expect_false(u$estimated)
  expect_true(usage_new(estimated = TRUE)$estimated)
  expect_equal(usage_new(input = NA)$input, 0)
  expect_error(usage_new(inptu = 1), class = "gptr_error_internal")
  expect_error(usage_new(1), class = "gptr_error_internal")
})

test_that("usage_cost() gives the documented dollar amounts (INFRA-20)", {
  # report 07 section 5.2: Opus 5.5, 50 in, 1200 out, 200000 cache reads, 3000 5-minute writes
  u = usage_cost(usage_new(input = 50, output = 1200, cache_read = 200000,
                           cache_write_5m = 3000), opus_like())
  expect_equal(u$cost$total, 0.0792)
  # report 03 verification row 5: 600 5-minute writes at 5 plus 400 1-hour writes at 2 x 4
  one_hour = usage_cost(usage_new(cache_write_5m = 600, cache_write_1h = 400), opus_like())
  expect_equal(one_hour$cost$cache_write, 0.0062)
  expect_equal(one_hour$cost$total, 0.0062)
  implicit = list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 4,
                                           output = 20)))
  derived = usage_cost(usage_new(cache_write_5m = 600, cache_write_1h = 400), implicit)
  expect_equal(derived$cost$cache_write, 0.0062)
  expect_equal(usage_cost(usage_new(cache_read = 1e6), implicit)$cost$cache_read, 0.4)
  # report 07 live call 2 (verification log row 26): a Haiku 4.5 turn with 7,641 1-hour cache
  # writes; the CLI's own total_cost_usd was 0.0178928
  haiku = list(prices = price_rows(list(from = "2000-01-01", tier = "default", input = 1,
                                        output = 5, cache_read = 0.1)))
  live = usage_cost(usage_new(input = 946, output = 184, cache_read = 7448,
                              cache_write_1h = 7641), haiku)
  expect_equal(live$cost$total, 0.0178928)
})

test_that("price tiers switch on the prompt size and on the date", {
  sol = list(prices = price_rows(
    list(from = "2000-01-01", tier = "default", input = 2, output = 10, cache_read = 0.1),
    list(from = "2000-01-01", tier = ">272k", input = 4, output = 15, cache_read = 0.2)
  ))
  expect_equal(usage_cost(usage_new(input = 100000), sol)$cost$input, 0.2)
  expect_equal(usage_cost(usage_new(input = 300000), sol)$cost$input, 1.2)
  expect_equal(price_select(sol$prices, 300000)$tier, ">272k")
  expect_equal(price_select(sol$prices, 100000)$tier, "default")
  flash = list(prices = price_rows(
    list(from = "2000-01-01", tier = "default", input = 0.75, output = 3.75),
    list(from = "2027-01-01", tier = "default", input = 1.50, output = 7.50)
  ))
  late = usage_cost(usage_new(input = 1e6), flash, when = as.Date("2026-12-31"))
  new_year = usage_cost(usage_new(input = 1e6), flash, when = as.Date("2027-01-01"))
  expect_equal(late$cost$input, 0.75)
  expect_equal(new_year$cost$input, 1.50)
  expect_equal(usage_cost(usage_new(input = 1e6), list(prices = NULL))$cost$total, 0)
  expect_equal(price_threshold(c("default", ">200k", "<=200k", ">32k")),
               c(NA, 200000, NA, 32000))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-usage")'`
Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 0 ]`, with errors such as ``Error in `usage_new(input = 10, output = 5, cache_read = 100)`: could not find function "usage_new"``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-usage.R`:

```r
# Usage records, dated price tiers, cost and the process System 1 log (P05).
# Contract: dev/spec/04-interface-contract.md sections 4.3 and 7.5; architecture section 5.5
# (INFRA-20). The cost rule is Pi's calculateCost() (report 03 sections 2.7 and 3.4; R prototype
# calculate_cost() in 03 section 5.3), extended with dated price rows (G2 fact-check: Gemini 3.8
# Flash promotional prices end 2026-12-31) and TTL-split cache writes (07 section 3.5:
# 5-minute writes 1.25x input, 1-hour writes 2x input). Usage fields are read with `[[`, never
# `$`, because `$` partially matches (07 section 5.2, 08 pitfall c).

#' Token fields of a usage record, in contract order
#' @noRd
usage_fields = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                 "reasoning", "images")

#' A length-1 numeric from a usage field (NULL, NA and empty become 0)
#' @noRd
usage_num = function(x) {
  if (is.null(x) || !length(x)) return(0)
  v = suppressWarnings(as.numeric(x[[1]]))
  if (is.na(v)) 0 else v
}

#' A cost list (USD) with zeros for missing entries
#' @noRd
cost_new = function(x = NULL) {
  x = x %||% list()
  out = list(input = usage_num(x[["input"]]), output = usage_num(x[["output"]]),
             cache_read = usage_num(x[["cache_read"]]),
             cache_write = usage_num(x[["cache_write"]]))
  out$total = if (is.null(x[["total"]])) {
    out$input + out$output + out$cache_read + out$cache_write
  } else {
    usage_num(x[["total"]])
  }
  out
}

#' Build a usage record (contract section 4.3) with zeros for missing fields
#' @noRd
usage_new = function(...) {
  x = list(...)
  known = c(usage_fields, "total", "cost", "estimated")
  nm = names(x) %||% rep("", length(x))
  bad = nm[!nm %in% known]
  if (length(bad)) {
    gptr_abort(paste0("usage_new() got unknown or unnamed fields: ",
                      paste(ifelse(nzchar(bad), bad, "<unnamed>"), collapse = ", ")),
               "internal", detail = "usage_new")
  }
  u = list()
  for (k in usage_fields) u[[k]] = usage_num(x[[k]])
  u$total = if (is.null(x[["total"]])) {
    u$input + u$output + u$cache_read + u$cache_write_5m + u$cache_write_1h
  } else {
    usage_num(x[["total"]])
  }
  u$cost = cost_new(x[["cost"]])
  u$estimated = isTRUE(x[["estimated"]])
  u
}

#' Normalise any usage-like list (or NULL) to a complete usage record
#' @noRd
usage_as = function(usage) {
  if (is.null(usage)) return(usage_new())
  keep = intersect(names(usage), c(usage_fields, "total", "cost", "estimated"))
  do.call(usage_new, usage[keep])
}

#' Prompt-side tokens that decide the context price tier
#' @noRd
usage_prompt_tokens = function(u) {
  u[["input"]] + u[["cache_read"]] + u[["cache_write_5m"]] + u[["cache_write_1h"]]
}

#' The price table of a model record as a data frame (contract section 4.9)
#' @noRd
prices_df = function(x) {
  cols = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
  if (is.data.frame(x)) {
    df = x
    for (k in cols) if (is.null(df[[k]])) df[[k]] = rep(NA_real_, nrow(df))
    df[["from"]] = as.Date(df[["from"]] %||% rep("2000-01-01", nrow(df)))
    df[["tier"]] = as.character(df[["tier"]] %||% rep("default", nrow(df)))
    return(df[c("from", "tier", cols)])
  }
  rows = x %||% list()
  chr = function(r, k, d) {
    v = r[[k]]
    if (is.null(v) || !length(v) || is.na(v[[1]])) d else as.character(v[[1]])
  }
  num = function(r, k) {
    v = r[[k]]
    if (is.null(v) || !length(v)) NA_real_ else suppressWarnings(as.numeric(v[[1]]))
  }
  df = data.frame(from = as.Date(vapply(rows, chr, "", k = "from", d = "2000-01-01")),
                  tier = vapply(rows, chr, "", k = "tier", d = "default"),
                  stringsAsFactors = FALSE)
  for (k in cols) df[[k]] = vapply(rows, num, 0, k = k)
  df
}

#' Context thresholds of price tier labels (">200k" -> 200000; base tiers -> NA)
#' @noRd
price_threshold = function(tier) {
  out = rep(NA_real_, length(tier))
  m = grepl("^>[0-9.]+k$", tier)
  out[m] = as.numeric(sub("^>([0-9.]+)k$", "\\1", tier[m])) * 1000
  out
}

#' The price row in force on `when` for a request with `prompt_tokens` prompt tokens
#'
#' The latest price set whose `from` is not after `when` applies (the earliest set when
#' `when` precedes them all); within it the `>Nk` tier with the highest threshold below the
#' prompt size wins, else the base row (`default` or `<=Nk`), as in Pi's calculateCost().
#' @noRd
price_select = function(prices, prompt_tokens, when = Sys.Date()) {
  if (is.null(prices) || !nrow(prices)) return(NULL)
  when = as.Date(when)
  cand = prices[!is.na(prices$from) & prices$from <= when, , drop = FALSE]
  if (!nrow(cand)) cand = prices[prices$from == min(prices$from, na.rm = TRUE), , drop = FALSE]
  cand = cand[cand$from == max(cand$from), , drop = FALSE]
  thr = price_threshold(cand$tier)
  above = which(!is.na(thr) & prompt_tokens > thr)
  i = if (length(above)) {
    above[which.max(thr[above])]
  } else {
    base = which(is.na(thr))
    if (length(base)) base[[1]] else 1L
  }
  cand[i, , drop = FALSE]
}

#' Rates (USD per million tokens) of a price row, with the TTL multipliers as defaults
#' @noRd
price_rates = function(row) {
  na0 = function(v) if (is.null(v) || is.na(v)) 0 else as.numeric(v)
  input = na0(row[["input"]])
  or = function(k, mult) if (is.na(row[[k]])) mult * input else as.numeric(row[[k]])
  list(input = input, output = na0(row[["output"]]), cache_read = or("cache_read", 0.1),
       cache_write_5m = or("cache_write_5m", 1.25), cache_write_1h = or("cache_write_1h", 2))
}

#' Cost of a usage record under a model's dated price tiers (contract section 7.5)
#' @noRd
usage_cost = function(usage, model, when = Sys.Date()) {
  u = usage_as(usage)
  row = price_select(prices_df(model[["prices"]]), usage_prompt_tokens(u), when)
  if (is.null(row)) {
    u$cost = cost_new(NULL)
    return(u)
  }
  r = price_rates(row)
  cost = list(input = r$input * u[["input"]] / 1e6,
              output = r$output * u[["output"]] / 1e6,
              cache_read = r$cache_read * u[["cache_read"]] / 1e6,
              cache_write = (r$cache_write_5m * u[["cache_write_5m"]] +
                               r$cache_write_1h * u[["cache_write_1h"]]) / 1e6)
  cost$total = cost$input + cost$output + cost$cache_read + cost$cache_write
  u$cost = cost
  u
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-usage")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 23 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-usage.R tests/testthat/test-provider-usage.R
git commit -m "feat(provider): usage records and dated price tiers"
```

---

### Task 2: Provider records as data and the builtin:fake declaration

**Files:**
- Create: `R/provider-registry.R`
- Test: `tests/testthat/test-provider-registry.R` (create)

**Interfaces:**
- Consumes: `on_load(expr)` (P01 `aaa-state.R`), `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (P02), `builtin_fake(gptr)` (P01 `provider-fake.R`), `gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat", "classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)` (P02), `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)` (P02), `check_string(x, arg, null = FALSE, empty = FALSE)`, `setting_get(key, session = NULL, default = NULL)`, `check_running()`, `json_decode(text)`, `raw_to_utf8(x, fallback = "CP1252")` (P01), `gptr_check(x, error = FALSE, tokens = FALSE)` and `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` in the tests; for the plugin-adapter test of INFRA-17 (architecture section 6.18 row 17: "the fake provider and a plugin adapter pass `gptr_check()`"), `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)` -> `lgl(1)`, `ext_unload(source)` (P02 `ext-load.R`), `gptr_adapter(api, transport, build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())` (P02) and `fake_stream(model, context, opts)` (P01 `provider-fake.R`, which plays the script of the provider spec in `opts$provider`).
- Produces: `builtin_providers(gptr)` (registers 17 provider specs), `provider_get(id)` -> `<spec:provider>` or `NULL` (also by provider alias; the record carries the settings `providers.<id>.headers` merged over its own non-secret `headers` and a logical `enabled`, `FALSE` only when `providers.<id>.enabled` is `false`; 04 section 11.2 gives the `providers` key to P05), `adapter_get(api)` -> `<spec:adapter>` or `gptr_error_not_available` (fields `member`, `provided_by`); private `provider_table()` (the provider data; also read by the catalog in Task 6), `provider_settings(id)` (the `providers.<id>` settings entry), `provider_effective(p)`, `provider_base_url(provider)` (settings `providers.<id>.base_url` > record `base_url` > the `base_url_env`/`base_url_default`/`base_url_template` compat fields), `provider_origin(url)` (lower-case scheme, host and non-default port). The compat field names below are the contract P12's `compat_flags()` reads (snake_case forms of Pi's `OpenAICompletionsCompat`, report 09 section 3.3): `supports_store`, `supports_developer_role`, `supports_reasoning_effort`, `supports_strict_mode`, `supports_tool_choice`, `max_tokens_field`, `requires_tool_result_name`, `requires_reasoning_content`, `thinking_format`, `thinking_in_content`, `think_tags`, `cache_control_format`, `session_affinity`, `image_mode`, `tool_id` (`"alnum9"` = Mistral's 9-character ids), `auth_header`, `deployment_model`, `base_url_env`, `base_url_default`, `base_url_template`.

The provider table is architecture section 8.1 (base URLs and key variables cross-checked with report 09 section 3.5). `typesafe` (section 8.2) is registered by P13's `builtin_system1()` (04 section 7.13) and the plan routes `claude-cli`/`codex` by P20's `builtin_cli()` (04 section 7.20); registering them here too would create same-rank collisions. The loopback servers get `discover` functions that run only on request (Task 8) and never under `R CMD check`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-registry.R`:

```r
# Tests for R/provider-registry.R (plan P05): provider records as data, base URLs and origins,
# credentials, provider_stream() on every transport, and gptr_providers().

builtin_ids = c("anthropic", "openai", "google", "openrouter", "groq", "deepseek", "mistral",
                "together", "xai", "cerebras", "fireworks", "ollama", "lmstudio", "llamacpp",
                "vllm", "azure", "bedrock")

# Settings come from P08's layers later; tests pin them by mocking the one reader.
local_settings = function(..., .env = parent.frame()) {
  values = list(...)
  testthat::local_mocked_bindings(
    setting_get = function(key, session = NULL, default = NULL) {
      if (key %in% names(values)) values[[key]] else default
    },
    .env = .env
  )
}

test_that("builtin:providers registers the architecture section 8.1 providers as data", {
  a = provider_get("anthropic")
  expect_true(all(builtin_ids %in% registry_names("provider")))
  expect_s3_class(a, "gptr_provider")
  expect_equal(a$api, "anthropic-messages")
  expect_equal(a$base_url, "https://api.anthropic.com")
  expect_equal(a$auth, "ANTHROPIC_API_KEY")
  expect_equal(provider_get("google")$auth, c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  expect_equal(provider_get("mistral")$compat$tool_id, "alnum9")
  expect_true(provider_get("deepseek")$compat$requires_reasoning_content)
  expect_true(provider_get("ollama")$local)
  expect_null(provider_get("ollama")$auth)
  expect_equal(provider_get("openrouter")$headers$`X-OpenRouter-Title`, "gptr")
  expect_false(any(vapply(builtin_ids, function(id) isTRUE(provider_get(id)$offline), NA)))
  expect_null(provider_get("no-such-provider"))
  expect_error(provider_get(1), class = "gptr_error_invalid_argument")
})

test_that("builtin:fake is declared here, and the fake provider passes gptr_check() (INFRA-17)", {
  expect_equal(adapter_get("fake")$transport, "inprocess")
  expect_false(is.null(registry_get("adapter", "fake-classifier")))
  res = gptr_check(gptr_fake_provider(list("hi")))
  expect_s3_class(res, "gptr_check")
  expect_true(all(res$ok))
  err = expect_error(adapter_get("no-such-api"), class = "gptr_error_not_available")
  expect_equal(err$member, "no-such-api")
})

test_that("a plugin adapter passes gptr_check() (INFRA-17)", {
  # an inprocess adapter whose generator plays a one-line fake reply (P01's fake_stream())
  reply = gptr_fake_provider(list("plugin reply"), name = "p05-plugin-fake")
  one_line = function(model, context, opts) {
    opts$provider = reply
    fake_stream(model, context, opts)
  }
  ok = ext_load(function(gptr) {
    gptr$register(gptr_adapter("p05-plugin", transport = "inprocess", stream = one_line))
  }, source = "plugin:p05-plugin", rank = 5L)
  withr::defer(ext_unload("plugin:p05-plugin"))
  expect_true(ok)
  a = adapter_get("p05-plugin")
  expect_identical(a, registry_get("adapter", "p05-plugin"))
  expect_equal(a$transport, "inprocess")
  model = list(id = "p05-plugin-1", api = "p05-plugin", provider = "p05-plugin")
  expect_true(is.function(a$stream(model, list(messages = list()), list())))
  res = gptr_check(a)
  expect_s3_class(res, "gptr_check")
  expect_true(all(res$ok))
})

test_that("base URLs come from settings, the record or an environment template", {
  local_settings(providers = list(openai = list(base_url = "https://proxy.example/v1/"),
                                  openrouter = list(headers = list(`X-Title` = "lab", bad = 1)),
                                  groq = list(enabled = FALSE)))
  expect_equal(provider_base_url(provider_get("openai")), "https://proxy.example/v1")
  expect_equal(provider_base_url(provider_get("anthropic")), "https://api.anthropic.com")
  expect_equal(provider_get("openrouter")$headers$`X-Title`, "lab")
  expect_equal(provider_get("openrouter")$headers$`X-OpenRouter-Title`, "gptr")
  expect_null(provider_get("openrouter")$headers$bad)
  expect_false(provider_get("groq")$enabled)
  expect_true(provider_get("openai")$enabled)
  withr::local_envvar(AZURE_OPENAI_ENDPOINT = "https://res.openai.azure.com/",
                      AWS_REGION = "", AWS_DEFAULT_REGION = "")
  expect_equal(provider_base_url(provider_get("azure")), "https://res.openai.azure.com/openai/v1")
  expect_equal(provider_base_url(provider_get("bedrock")),
               "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1")
  withr::local_envvar(AZURE_OPENAI_ENDPOINT = "https://res.openai.azure.com/openai/v1",
                      AWS_REGION = "eu-central-1")
  expect_equal(provider_base_url(provider_get("azure")), "https://res.openai.azure.com/openai/v1")
  expect_equal(provider_base_url(provider_get("bedrock")),
               "https://bedrock-runtime.eu-central-1.amazonaws.com/openai/v1")
  expect_equal(provider_origin("https://API.Anthropic.com:443/v1/messages"),
               "https://api.anthropic.com")
  expect_equal(provider_origin("http://user:pw@localhost:11434/v1"), "http://localhost:11434")
  expect_null(provider_origin(NULL))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 1 ]`, with errors such as ``could not find function "provider_get"`` and ``could not find function "adapter_get"`` (the one pass is the plugin test's `expect_true(ok)`: P02's `ext_load()` already exists).

- [ ] **Step 3: Write the implementation**

Create `R/provider-registry.R` (the two `on_load()` lines are evaluated by `.onLoad`, after the whole namespace exists, IC-32):

```r
# Provider records as data, credentials, the provider_stream() glue and gptr_providers() (P05).
# Contract: dev/spec/04-interface-contract.md sections 6.2 (gptr_providers()), 7.5, 8.1, 8.4 and
# 10.2 row 1; architecture sections 8.1 and 6.5; IC-08 (builtin:fake declared here), IC-33
# (opts$gate, opts$mcp_dispatch and opts$tool_result are injected, never looked up by an
# adapter), IC-45 (offline), IC-64 (rate), IC-65 (check = FALSE spawns nothing).
# Provider table: architecture section 8.1 and report 09 section 3.5 (base URLs, key variables);
# compat flags are the snake_case form of Pi's OpenAICompletionsCompat (report 09 section 3.3,
# section 4.6). Credential order: report 03 section 4.5 as amended by G6 section 4.5.

on_load(ext_declare_builtin("fake", builtin_fake))
on_load(ext_declare_builtin("providers", builtin_providers))

#' Compat defaults shared by the loopback OpenAI-compatible servers (report 09 section 4.6)
#' @noRd
provider_local_compat = function() {
  list(supports_store = FALSE, supports_developer_role = FALSE,
       supports_reasoning_effort = FALSE, supports_strict_mode = FALSE,
       max_tokens_field = "max_tokens", image_mode = "base64")
}

#' The built-in provider records of architecture section 8.1, as gptr_provider() arguments
#'
#' `typesafe` (section 8.2) is registered by P13's builtin:system1 (04 section 7.13) and the
#' plan routes `claude-cli` and `codex` by P20's builtin:cli (04 section 7.20).
#' @noRd
provider_table = function() {
  local = provider_local_compat()
  list(
    list(id = "anthropic", api = "anthropic-messages", base_url = "https://api.anthropic.com",
         auth = "ANTHROPIC_API_KEY"),
    list(id = "openai", api = "openai-responses", base_url = "https://api.openai.com/v1",
         auth = "OPENAI_API_KEY"),
    list(id = "google", api = "google-generative-ai",
         base_url = "https://generativelanguage.googleapis.com/v1beta",
         auth = c("GEMINI_API_KEY", "GOOGLE_API_KEY")),
    list(id = "openrouter", api = "openai-completions", base_url = "https://openrouter.ai/api/v1",
         auth = "OPENROUTER_API_KEY",
         compat = list(thinking_format = "openrouter", supports_developer_role = FALSE,
                       cache_control_format = "anthropic", session_affinity = "openrouter"),
         headers = list(`HTTP-Referer` = "https://cran.r-project.org/package=gptr",
                        `X-OpenRouter-Title` = "gptr")),
    list(id = "groq", api = "openai-completions", base_url = "https://api.groq.com/openai/v1",
         auth = "GROQ_API_KEY", compat = list(requires_tool_result_name = FALSE)),
    list(id = "deepseek", api = "openai-completions", base_url = "https://api.deepseek.com",
         auth = "DEEPSEEK_API_KEY",
         compat = list(thinking_format = "deepseek", max_tokens_field = "max_tokens",
                       requires_reasoning_content = TRUE, supports_store = FALSE,
                       supports_developer_role = FALSE)),
    list(id = "mistral", api = "openai-completions", base_url = "https://api.mistral.ai/v1",
         auth = "MISTRAL_API_KEY",
         compat = list(tool_id = "alnum9", thinking_in_content = TRUE, supports_store = FALSE)),
    list(id = "together", api = "openai-completions", base_url = "https://api.together.ai/v1",
         auth = "TOGETHER_API_KEY",
         compat = list(thinking_format = "together", max_tokens_field = "max_tokens",
                       supports_store = FALSE, supports_developer_role = FALSE,
                       supports_reasoning_effort = FALSE, think_tags = TRUE)),
    list(id = "xai", api = "openai-completions", base_url = "https://api.x.ai/v1",
         auth = "XAI_API_KEY",
         compat = list(supports_store = FALSE, supports_developer_role = FALSE,
                       supports_reasoning_effort = FALSE)),
    list(id = "cerebras", api = "openai-completions", base_url = "https://api.cerebras.ai/v1",
         auth = "CEREBRAS_API_KEY",
         compat = list(supports_store = FALSE, supports_developer_role = FALSE,
                       image_mode = "base64")),
    list(id = "fireworks", api = "openai-completions",
         base_url = "https://api.fireworks.ai/inference/v1", auth = "FIREWORKS_API_KEY"),
    list(id = "ollama", api = "openai-completions", base_url = "http://localhost:11434/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("ollama"),
         compat = utils::modifyList(local, list(supports_reasoning_effort = TRUE,
                                                supports_tool_choice = FALSE))),
    list(id = "lmstudio", api = "openai-completions", base_url = "http://localhost:1234/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("lmstudio"), compat = local),
    list(id = "llamacpp", api = "openai-completions", base_url = "http://127.0.0.1:8080/v1",
         auth = NULL, local = TRUE, discover = provider_discoverer("llamacpp"), compat = local),
    list(id = "vllm", api = "openai-completions", base_url = "http://localhost:8000/v1",
         auth = provider_optional_auth("vllm", "VLLM_API_KEY"), local = TRUE,
         discover = provider_discoverer("vllm"),
         compat = utils::modifyList(local, list(supports_reasoning_effort = TRUE))),
    list(id = "azure", api = "openai-completions", base_url = NULL, auth = "AZURE_OPENAI_API_KEY",
         compat = list(auth_header = "api-key", deployment_model = TRUE,
                       base_url_env = "AZURE_OPENAI_ENDPOINT",
                       base_url_template = "{value}/openai/v1")),
    list(id = "bedrock", api = "openai-completions", base_url = NULL,
         auth = "AWS_BEARER_TOKEN_BEDROCK",
         compat = list(
           base_url_env = c("AWS_REGION", "AWS_DEFAULT_REGION"), base_url_default = "us-east-1",
           base_url_template = "https://bedrock-runtime.{value}.amazonaws.com/openai/v1"
         ))
  )
}

#' Default model id per built-in provider (architecture section 8.4)
#' @noRd
provider_default_models = function() {
  c(anthropic = "claude-sonnet-5-5", openai = "gpt-6-sol", google = "gemini-3.8-flash")
}

#' An `auth` function for an optional key (vLLM): a bound handle when the key exists, else NULL
#' @noRd
provider_optional_auth = function(id, vars) {
  force(id)
  force(vars)
  function() {
    p = provider_get(id)
    if (is.null(p)) return(NULL)
    p[["auth"]] = vars
    tryCatch(provider_credential(p), gptr_error_no_key = function(e) NULL)
  }
}

#' A `discover` function for a loopback server: GET <base>/models with a 1 s timeout
#'
#' Runs only on request (gptr_models(refresh = TRUE, provider = <id>)), never at load and
#' never under R CMD check (report 09 section 4.6).
#' @noRd
provider_discoverer = function(id) {
  force(id)
  function() {
    if (check_running()) return(NULL)
    p = provider_get(id)
    url = if (is.null(p)) NULL else provider_base_url(p)
    if (is.null(url)) return(NULL)
    res = tryCatch(catalog_http_get(paste0(url, "/models"), timeout = 1),
                   gptr_error = function(e) NULL)
    if (is.null(res) || !identical(res$status, 200L)) return(NULL)
    body = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
    ids = vapply(body[["data"]] %||% list(), function(m) as.character(m[["id"]] %||% ""), "")
    data.frame(id = ids[nzchar(ids)], stringsAsFactors = FALSE)
  }
}

#' builtin:providers: registers the provider records of architecture section 8.1 as data
#' @noRd
builtin_providers = function(gptr) {
  for (row in provider_table()) gptr$register(do.call(gptr_provider, row))
  invisible(NULL)
}

#' The settings entry `providers.<id>` (`base_url`, `models`, `headers`, `enabled`; 04 section
#' 11.2), or an empty list
#' @noRd
provider_settings = function(id) {
  cfg = setting_get("providers", default = list()) %||% list()
  s = if (is.list(cfg) && is.character(id) && length(id) == 1L) cfg[[id]] else NULL
  if (is.list(s)) s else list()
}

#' A provider record with its settings applied: extra non-secret `headers` (single strings
#' only) are merged over the record's, and `enabled` is `FALSE` only when the settings say so
#' @noRd
provider_effective = function(p) {
  if (is.null(p)) return(NULL)
  s = provider_settings(p[["id"]] %||% p[["name"]])
  h = s[["headers"]]
  if (is.list(h) && length(h) && !is.null(names(h))) {
    hs = p[["headers"]] %||% list()
    for (k in names(h)) {
      v = h[[k]]
      if (nzchar(k) && is.character(v) && length(v) == 1L && !is.na(v)) hs[[k]] = v
    }
    p[["headers"]] = hs
  }
  p[["enabled"]] = !isFALSE(s[["enabled"]])
  p
}

#' The provider spec registered as `id` (or under that alias), with its settings applied; NULL
#' when none
#' @noRd
provider_get = function(id) {
  check_string(id, "id")
  p = registry_get("provider", id)
  if (!is.null(p)) return(provider_effective(p))
  for (nm in registry_names("provider")) {
    q = registry_get("provider", nm)
    if (id %in% (q[["aliases"]] %||% character())) return(provider_effective(q))
  }
  NULL
}

#' The plan that provides a built-in adapter (for the not_available condition)
#' @noRd
adapter_provided_by = function(api) {
  switch(api,
         "anthropic-messages" = , "openai-responses" = , "openai-completions" = ,
         "google-generative-ai" = "P12",
         "typesafe-system-one" = , "s1-emulate" = "P13",
         "cli-claude" = , "cli-codex" = "P20",
         "fake" = , "fake-classifier" = "P01",
         "a plugin")
}

#' The adapter spec registered for a wire api, or gptr_error_not_available
#' @noRd
adapter_get = function(api) {
  check_string(api, "api")
  a = registry_get("adapter", api)
  if (is.null(a)) {
    gptr_abort(paste0("No adapter is registered for the api ", api, "."), "not_available",
               member = api, provided_by = adapter_provided_by(api))
  }
  a
}

#' The configured base URL of a provider (settings > record > environment template)
#' @noRd
provider_base_url = function(provider) {
  id = provider[["id"]] %||% provider[["name"]]
  url = provider_settings(id)[["base_url"]]
  if (!is.character(url) || length(url) != 1L || is.na(url)) url = NULL
  if (is.null(url) || !nzchar(url)) url = provider[["base_url"]]
  if (is.null(url) || !nzchar(url)) {
    comp = provider[["compat"]] %||% list()
    vars = comp[["base_url_env"]]
    if (length(vars)) {
      vals = Sys.getenv(vars, unset = "")
      vals = vals[nzchar(vals)]
      val = sub("/+$", "", if (length(vals)) vals[[1]] else comp[["base_url_default"]] %||% "")
      tmpl = comp[["base_url_template"]]
      if (nzchar(val)) {
        suffix = if (is.null(tmpl)) "" else sub("^\\{value\\}", "", tmpl)
        url = if (is.null(tmpl) || (nzchar(suffix) && endsWith(val, suffix))) {
          val
        } else {
          gsub("{value}", val, tmpl, fixed = TRUE)
        }
      }
    }
  }
  if (is.null(url) || !nzchar(url)) NULL else sub("/+$", "", url)
}

#' The origin (scheme, host and non-default port, lower case) of a URL
#' @noRd
provider_origin = function(url) {
  if (is.null(url) || !nzchar(url)) return(NULL)
  o = tolower(sub("^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+).*$", "\\1", url))
  o = sub("://[^/@]*@", "://", o)
  o = sub("^(https://[^/]+):443$", "\\1", o)
  sub("^(http://[^/]+):80$", "\\1", o)
}
```

`provider_discoverer()` calls `catalog_http_get()` and `provider_optional_auth()` calls `provider_credential()`; both are defined in Tasks 8 and 3 and are only reached when those closures run.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 40 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-registry.R tests/testthat/test-provider-registry.R
git commit -m "feat(provider): provider records as data and the builtin:fake declaration"
```

---

### Task 3: Origin-bound provider credentials

**Files:**
- Modify: `R/provider-registry.R` (append)
- Test: `tests/testthat/test-provider-registry.R` (append)

**Interfaces:**
- Consumes: `secret_lookup(name)` -> handle or `NULL`, `secret_register(value, name, source = "user", active = TRUE, origin = NULL)` -> handle, `auth_store_get(key)` (P03, 04 section 7.3; P03's `auth_store_get()` returns the record with every secret field already registered and replaced by an unbound handle); the `gptr_secret` fields `id`, `name`, `fp`, `origin` (04 section 5.9; P03's `secret_value()` checks the handle's own `origin` before its vault entry's, P03 plan Task 1); `hash_sha256(x)` (P01: the fingerprint of a refused `sk-ant-oat` token, and the test vault); `gptr_provider()` (P02, in the tests); `provider_base_url()`, `provider_origin()` (Task 2).
- Produces: `provider_credential(provider)` -> a `gptr_secret` handle bound to the provider's origin, `NULL` for providers without `auth` (and for `offline` providers), else `gptr_error_no_key` with `provider` and `variables` (04 section 7.5); for the `anthropic` provider a Claude subscription OAuth token (`sk-ant-oat...`) in `ANTHROPIC_API_KEY` is refused (architecture section 8.1: "refuses subscription tokens (`sk-ant-oat`)"), as is the vault handle with the same fingerprint, and when nothing else is found the `gptr_error_no_key` message names the token type and points to an API key or `model = "claude_code"`.

Order (architecture section 8; report 03 section 4.5 as amended by G6 section 4.5): an `auth` function (the explicit form: it returns a handle or `NULL`) > the vault (`gptr_env()`, ambient discovery) > the credential store (`gptr_login()`; P03 resolves keyring references and returns handles) > the provider's environment variables, registered at once with the provider origin. A vault handle bound to another origin is never used; origins are compared after `provider_origin()`, because P03's `secret_register()` stores them in canonical form with the port (`https://api.anthropic.com:443`, P03 `origin_of()`). Every handle `provider_credential()` returns is origin-bound as 04 section 7.5 requires: an unbound handle (ambient discovery and `.env` values register without an origin; P03's credential store registers its fields without one; an `auth` function may return one) gets the provider origin in its own `origin` field, the binding P03's `secret_value()` honours first (P03 plan, Task 1). A key read from the environment exists only inside `provider_credential()` long enough to call `secret_register()` or, for the `anthropic` provider, to recognise a subscription token by its `sk-ant-oat` prefix and compute its fingerprint (`substr(hash_sha256(value), 1, 6)`, P03's `fp`), which marks a vault handle holding the same token (ambient discovery registers the environment's values); no other function takes a secret value (G6 section 4.3). An API key held only in the vault (a `.env` value not exported) has another fingerprint and is still used. Tests that set a key variable use `local_test_vault()`, which mocks `secret_register()` and `secret_lookup()` with a private environment: P03's process vault has no unregister function, and a test key left in it would change `model_default()` and credential lookups in later test files.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-registry.R`:

```r
# A private vault for tests that set key variables: P03's process vault has no unregister
# function, and later test files must not find a test key in it.
local_test_vault = function(.env = parent.frame()) {
  vault = new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    secret_register = function(value, name, source = "user", active = TRUE, origin = NULL) {
      fp = substr(hash_sha256(value), 1L, 6L)
      h = structure(list(id = paste0(name, "#", fp), name = name, fp = fp, origin = origin),
                    class = "gptr_secret")
      assign(name, h, envir = vault)
      h
    },
    secret_lookup = function(name) get0(name, envir = vault, inherits = FALSE),
    .env = .env
  )
  vault
}

test_that("credentials: vault, then the environment, bound to the provider origin", {
  vault = local_test_vault()
  withr::local_envvar(ANTHROPIC_API_KEY = "sk-ant-api03-p05test-000000000000000000")
  h = provider_credential(provider_get("anthropic"))
  expect_s3_class(h, "gptr_secret")
  expect_equal(h$name, "ANTHROPIC_API_KEY")
  expect_equal(h$origin, "https://api.anthropic.com")
  printed = paste(c(capture.output(print(h)), format(h)), collapse = "\n")
  expect_false(grepl("p05test", printed, fixed = TRUE))
  expect_identical(get("ANTHROPIC_API_KEY", envir = vault), h)
  expect_identical(provider_credential(provider_get("anthropic"))$id, h$id)
  expect_null(provider_credential(provider_get("ollama")))
  expect_null(provider_credential(gptr_fake_provider(list("hi"))))
  withr::local_envvar(VLLM_API_KEY = "")
  expect_null(provider_credential(provider_get("vllm")))
})

test_that("a keyed provider without any credential signals gptr_error_no_key", {
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL)
  withr::local_envvar(GROQ_API_KEY = "")
  err = expect_error(provider_credential(provider_get("groq")), class = "gptr_error_no_key")
  expect_equal(err$provider, "groq")
  expect_equal(err$variables, "GROQ_API_KEY")
  expect_match(conditionMessage(err), "GROQ_API_KEY", fixed = TRUE)
})

test_that("credential-store and auth-function handles are bound to the provider origin", {
  stored = structure(list(id = "auth:openrouter#cccccc", name = "auth:openrouter", fp = "cccccc",
                          origin = NULL), class = "gptr_secret")
  local_mocked_bindings(secret_lookup = function(name) NULL,
                        auth_store_get = function(key) list(type = "api_key", key = stored))
  withr::local_envvar(OPENROUTER_API_KEY = "")
  h = provider_credential(provider_get("openrouter"))
  expect_equal(h$id, "auth:openrouter#cccccc")
  expect_equal(h$origin, "https://openrouter.ai")
  lab = gptr_provider("authfn", api = "openai-completions", base_url = "https://llm.lab.example/v1",
                      auth = function() stored)
  expect_equal(provider_credential(lab)$origin, "https://llm.lab.example")
})

test_that("a vault handle bound to another origin is never used for this provider", {
  elsewhere = structure(list(id = "OPENROUTER_API_KEY#aaaaaa", name = "OPENROUTER_API_KEY",
                             fp = "aaaaaa", origin = "https://evil.example"),
                        class = "gptr_secret")
  local_mocked_bindings(secret_lookup = function(name) elsewhere,
                        auth_store_get = function(key) NULL)
  withr::local_envvar(OPENROUTER_API_KEY = "")
  expect_error(provider_credential(provider_get("openrouter")), class = "gptr_error_no_key")
})

test_that("vault handles: canonical origins match, unbound ones are bound to the provider", {
  vault = local_test_vault()
  key = "sk-proj-p05bind-00000000000000000000000000"
  withr::local_envvar(OPENAI_API_KEY = key)
  ambient = secret_register(key, "OPENAI_API_KEY", source = "environment")
  expect_null(ambient$origin)
  h = provider_credential(provider_get("openai"))
  expect_equal(h$origin, "https://api.openai.com")
  expect_equal(h$fp, ambient$fp)
  canonical = structure(list(id = "XAI_API_KEY#bbbbbb", name = "XAI_API_KEY", fp = "bbbbbb",
                             origin = "https://api.x.ai:443"), class = "gptr_secret")
  vault[["XAI_API_KEY"]] = canonical
  withr::local_envvar(XAI_API_KEY = "")
  expect_identical(provider_credential(provider_get("xai")), canonical)
})

test_that("the anthropic provider refuses a Claude subscription OAuth token (sk-ant-oat)", {
  vault = local_test_vault()
  local_mocked_bindings(auth_store_get = function(key) NULL)
  oat = "sk-ant-oat01-p05test-0000000000000000000000"
  withr::local_envvar(ANTHROPIC_API_KEY = oat)
  err = expect_error(provider_credential(provider_get("anthropic")), class = "gptr_error_no_key")
  expect_equal(err$provider, "anthropic")
  expect_equal(err$variables, "ANTHROPIC_API_KEY")
  expect_match(conditionMessage(err), "subscription OAuth token (sk-ant-oat...)", fixed = TRUE)
  expect_match(conditionMessage(err), "model = \"claude_code\"", fixed = TRUE)
  expect_false(grepl("p05test", conditionMessage(err), fixed = TRUE))
  expect_false(exists("ANTHROPIC_API_KEY", envir = vault, inherits = FALSE))
  # ambient discovery registered the same token: its vault handle is refused too
  secret_register(oat, "ANTHROPIC_API_KEY", source = "environment")
  expect_error(provider_credential(provider_get("anthropic")), class = "gptr_error_no_key")
  # an API key held only in the vault (a .env value that was not exported) is still used
  api = secret_register("sk-ant-api03-p05vault-0000000000000000000", "ANTHROPIC_API_KEY",
                        source = "dotenv")
  h = provider_credential(provider_get("anthropic"))
  expect_equal(h$fp, api$fp)
  expect_equal(h$origin, "https://api.anthropic.com")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 41 ]`, with ``could not find function "provider_credential"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-registry.R`:

```r
#' Is a handle usable for a provider origin (unbound, or bound to the same origin)?
#'
#' P03 stores bound origins in canonical form with the port (`https://api.anthropic.com:443`),
#' so the bound origin passes provider_origin() before the comparison.
#' @noRd
credential_usable = function(h, origin) {
  if (!inherits(h, "gptr_secret")) return(FALSE)
  bound = h[["origin"]]
  is.null(bound) || identical(provider_origin(bound), origin)
}

#' Bind a handle to the provider origin (contract section 7.5: "a handle bound to the provider's
#' configured origin")
#'
#' An unbound handle (ambient discovery, a vault-only `.env` value, a credential-store record, an
#' `auth` function's result) gets the provider origin in its own `origin` field, which P03's
#' secret_value() checks before the origin of the vault entry (P03 plan, Task 1: "how P05 binds
#' a looked-up handle"); the vault entry itself stays as it is for other consumers. A handle that
#' is already bound is returned unchanged; provider_credential() never uses one that is bound to
#' another origin. P05 never sees the value.
#' @noRd
credential_bind = function(h, origin) {
  if (is.null(origin) || !inherits(h, "gptr_secret") || !is.null(h[["origin"]])) return(h)
  h[["origin"]] = origin
  h
}

#' A handle from a credential-store record (P03 returns handles for stored values)
#' @noRd
credential_from_store = function(rec, name, origin) {
  if (is.null(rec)) return(NULL)
  if (inherits(rec, "gptr_secret")) return(rec)
  for (k in c("handle", "key")) {
    v = rec[[k]]
    if (inherits(v, "gptr_secret")) return(v)
  }
  key = rec[["key"]]
  if (is.character(key) && length(key) == 1L && nzchar(key)) {
    return(secret_register(key, name, source = "store", origin = origin))
  }
  NULL
}

#' The credential handle of a provider (contract section 7.5)
#'
#' Order (architecture section 8): an explicit `auth` function > the vault (gptr_env(), ambient
#' discovery) > the credential store (gptr_login(); keyring references are resolved by P03) >
#' the provider's environment variables, registered at once and bound to the provider's origin.
#' NULL for providers without auth; gptr_error_no_key otherwise. Never returns a value. The
#' anthropic provider refuses a subscription OAuth token (`sk-ant-oat`, architecture section
#' 8.1) found in its variable, and the vault handle holding the same token: gptr_error_no_key
#' naming the token type when nothing else is found.
#' @noRd
provider_credential = function(provider) {
  if (is.null(provider)) return(NULL)
  id = provider[["id"]] %||% provider[["name"]]
  auth = provider[["auth"]]
  if (is.null(auth) || isTRUE(provider[["offline"]])) return(NULL)
  origin = provider_origin(provider_base_url(provider))
  if (is.function(auth)) {
    h = auth()
    if (is.null(h)) return(NULL)
    if (inherits(h, "gptr_secret")) return(credential_bind(h, origin))
    gptr_abort(paste0("The auth function of provider ", id, " returned no secret handle."),
               "invalid_spec", kind = "provider", name = id, field = "auth",
               problem = "auth() must return a gptr_secret handle or NULL")
  }
  vars = as.character(auth)
  # Architecture section 8.1: the anthropic provider refuses Claude subscription OAuth tokens
  # (sk-ant-oat...). Their fingerprints (P03: the first 6 hex of hash_sha256(value)) mark the
  # vault handles that hold the same token (ambient discovery registers the environment's
  # values); a token that exists only in the vault cannot be recognised here (ambiguity 8).
  refused = character()
  if (identical(id, "anthropic")) {
    for (v in vars) {
      value = Sys.getenv(v, unset = "")
      if (startsWith(value, "sk-ant-oat")) refused[[v]] = substr(hash_sha256(value), 1L, 6L)
    }
  }
  for (v in vars) {
    h = secret_lookup(v)
    if (v %in% names(refused) && identical(h[["fp"]], refused[[v]])) next
    if (credential_usable(h, origin)) return(credential_bind(h, origin))
  }
  rec = tryCatch(auth_store_get(id), gptr_error = function(e) NULL)
  h = credential_from_store(rec, vars[[1]], origin)
  if (credential_usable(h, origin)) return(credential_bind(h, origin))
  for (v in vars) {
    if (v %in% names(refused)) next
    value = Sys.getenv(v, unset = "")
    if (nzchar(value)) return(secret_register(value, v, source = "env", origin = origin))
  }
  if (length(refused)) {
    gptr_abort(paste0(names(refused)[[1]], " holds a Claude subscription OAuth token ",
                      "(sk-ant-oat...), which the API provider refuses; use an API key, or ",
                      "model = \"claude_code\" for the subscription CLI."),
               "no_key", provider = id, variables = vars)
  }
  gptr_abort(paste0("No credential found for provider ", id, ". Set ",
                    paste(vars, collapse = " or "),
                    " (for example with gptr_env()) or store one with gptr_login()."),
             "no_key", provider = id, variables = vars)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 71 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-registry.R tests/testthat/test-provider-registry.R
git commit -m "feat(provider): origin-bound provider credentials"
```

---

### Task 4: Cross-provider hand-off transform

**Files:**
- Create: `R/provider-transform.R`
- Test: `tests/testthat/test-provider-transform.R` (create)

**Interfaces:**
- Consumes: `block_text(text, signature = NULL)`, `hash_sha256(x)` (P01); `registry_get(kind, name, session = NULL)` (P02, for the target adapter's `capabilities$reasoning_replay`, 04 section 8.1); `provider_get(id)` (Task 2, for the `tool_id` compat flag). Tests also use `msg_user()`, `msg_assistant()`, `msg_tool_result()`, `msg_to_json()`, `block_thinking()`, `block_opaque()`, `block_tool_call()`, `block_image()`, `json_encode()` (P01, 04 sections 4.1-4.2), `gptr_register()` and `gptr_adapter()` (P02).
- Produces: `handoff_transform(messages, target)` -> the messages for `target` (a model record, 04 section 4.9) (04 section 7.5); private `handoff_thinking_as_text()`, `id_sanitize()`, `id_completions()`, `id_responses()`, `id_alnum9_normaliser()`.

Rules (Pi `transformMessages()` pass 1, `transform-messages.ts:64-235`; report 03 section 2.9; INFRA-08): same model = provider, api and model id equal; a same-model turn is kept byte for byte (signatures, redacted thinking, opaque blocks of that model), except empty unsigned thinking. A foreign turn: thinking becomes a plain `text` block without tags (dropped when the target model record or, failing that, the registered adapter of the target api declares `reasoning_replay = FALSE`, 04 section 8.1), redacted thinking and opaque blocks of other models are dropped, text signatures and tool-call thought signatures are removed, tool ids are normalised for the target api and results follow the new ids. Images in user messages and tool results become one placeholder text per run when the target reads no images.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-transform.R`:

```r
# Tests for R/provider-transform.R (plan P05): the hand-off transform (INFRA-08) and the
# projection of the transcript tree (INFRA-04).

tx_model = function(provider, id, api, input = c("text", "image")) {
  list(ref = paste0(provider, "/", id), provider = provider, id = id, api = api,
       input = input, reasoning = TRUE, capabilities = list())
}

anthropic_msg = function(content, stop = "tool_use", ts = 1000, model = "claude-sonnet-5-5",
                         error = NULL) {
  msg_assistant(content, api = "anthropic-messages", provider = "anthropic", model = model,
                stop_reason = stop, error_message = error, timestamp = ts)
}

block_types = function(msg) vapply(msg$content, function(b) b$type, "")

test_that("hand-off keeps a same-model turn byte for byte", {
  a = anthropic_msg(list(block_thinking("plan the fit", signature = "sig-abc"),
                         block_thinking("", redacted = TRUE, data = "opaque-redacted"),
                         block_text("Fitting now.", signature = "txt-sig"),
                         block_opaque("anthropic", "anthropic-messages", "claude-sonnet-5-5",
                                      "{\"server\":1}"),
                         block_tool_call("toolu_01", "r", list(code = "fit = lm(y ~ x)"))))
  same = handoff_transform(list(a), tx_model("anthropic", "claude-sonnet-5-5",
                                             "anthropic-messages"))
  expect_identical(same[[1]]$content, a$content)
})

test_that("hand-off to other providers drops every foreign signature and opaque item (INFRA-08)", {
  a = anthropic_msg(list(block_thinking("plan the fit", signature = "sig-abc"),
                         block_thinking("", redacted = TRUE, data = "opaque-redacted"),
                         block_text("Fitting now.", signature = "txt-sig"),
                         block_opaque("anthropic", "anthropic-messages", "claude-sonnet-5-5",
                                      "{\"server\":1}"),
                         block_tool_call("toolu_01", "r", list(code = "fit = lm(y ~ x)"),
                                         thought_signature = "ts-1")))
  msgs = list(msg_user("Fit a model", timestamp = 900), a,
              msg_tool_result("toolu_01", "r", "done", timestamp = 1100))
  targets = list(tx_model("openai", "gpt-6.1-sol", "openai-responses"),
                 tx_model("google", "gemini-3.8-flash", "google-generative-ai"))
  for (target in targets) {
    out = handoff_transform(msgs, target)
    blocks = out[[2]]$content
    expect_equal(block_types(out[[2]]), c("text", "text", "tool_call"))
    expect_equal(blocks[[1]]$text, "plan the fit")
    expect_true(all(vapply(blocks, function(b) is.null(b$signature), NA)))
    expect_null(blocks[[3]]$thought_signature)
    expect_false(any(grepl("sig-abc|txt-sig|opaque-redacted|ts-1|server",
                           json_encode(lapply(out, msg_to_json)))))
    expect_identical(out[[3]]$tool_call_id, blocks[[3]]$id)
  }
  expect_length(msgs, 3L)
  expect_equal(msgs[[2]]$content[[1]]$signature, "sig-abc")
})

test_that("tool ids are normalised per target api and results follow them", {
  src = msg_assistant(list(block_tool_call("call_1|fc_ab+/=", "r", list(code = "1"))),
                      api = "openai-responses", provider = "openai", model = "gpt-6.1-sol",
                      stop_reason = "tool_use", timestamp = 1)
  res = msg_tool_result("call_1|fc_ab+/=", "r", "1", timestamp = 2)
  to_anthropic = handoff_transform(list(src, res),
                                   tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages"))
  expect_equal(to_anthropic[[1]]$content[[1]]$id, "call_1_fc_ab___")
  expect_equal(to_anthropic[[2]]$tool_call_id, "call_1_fc_ab___")
  to_mistral = handoff_transform(list(src, res),
                                 tx_model("mistral", "mistral-large", "openai-completions"))
  expect_match(to_mistral[[1]]$content[[1]]$id, "^[0-9a-zA-Z]{9}$")
  expect_identical(to_mistral[[2]]$tool_call_id, to_mistral[[1]]$content[[1]]$id)
  long = paste0("call_", strrep("x", 30), "|fc_", strrep("y", 30))
  expect_match(id_completions(long, "groq"), "^call_x+_[0-9a-f]{8}$")
  expect_lte(nchar(id_completions(long, "groq")), 40L)
  expect_equal(id_completions("call_a|fc_b", "groq"), "call_a_fc_b")
  expect_equal(id_completions(strrep("z", 50), "openai"), strrep("z", 40))
  responses = tx_model("openai", "gpt-6.1-sol", "openai-responses")
  foreign = list(provider = "anthropic", api = "anthropic-messages")
  expect_equal(id_responses("call_9|rs_77", responses, foreign),
               paste0("call_9|fc_", substr(hash_sha256("rs_77"), 1, 12)))
  expect_equal(id_responses("call_9|fc_77", responses, list(provider = "openai",
                                                            api = "openai-responses")),
               "call_9|fc_77")
  norm = id_alnum9_normaliser()
  expect_identical(norm("toolu_01ABC", NULL), norm("toolu_01ABC", NULL))
  expect_equal(norm("abcdefghi", NULL), "abcdefghi")
})

test_that("images become one placeholder for a target that reads no images", {
  u = msg_user(list(block_text("look"), block_image("AAAA"), block_image("BBBB")), timestamp = 1)
  r = msg_tool_result("c1", "r", list(block_image("CCCC")), timestamp = 2)
  target = tx_model("deepseek", "deepseek-v4-pro", "openai-completions", input = "text")
  out = handoff_transform(list(u, r), target)
  expect_equal(vapply(out[[1]]$content, function(b) b$text, ""),
               c("look", "(image omitted: model does not support images)"))
  expect_equal(out[[2]]$content[[1]]$text,
               "(tool image omitted: model does not support images)")
})

test_that("foreign thinking becomes text unless the target refuses reasoning replay", {
  a = anthropic_msg(list(block_thinking("why"), block_thinking("  "), block_text("answer")),
                    stop = "stop", model = "claude-opus-5-5")
  target = tx_model("openai", "gpt-6.1-sol", "openai-responses")
  expect_equal(vapply(handoff_transform(list(a), target)[[1]]$content, function(b) b$text, ""),
               c("why", "answer"))
  target$capabilities = list(reasoning_replay = FALSE)
  expect_equal(vapply(handoff_transform(list(a), target)[[1]]$content, function(b) b$text, ""),
               "answer")
  # the capability usually comes from the target api's adapter (04 section 8.1)
  off = gptr_register(gptr_adapter("test-noreplay", transport = "inprocess",
                                   stream = function(model, context, opts) function() NULL,
                                   capabilities = list(reasoning_replay = FALSE)))
  withr::defer(off())
  lab = tx_model("lab", "lab-1", "test-noreplay")
  expect_equal(vapply(handoff_transform(list(a), lab)[[1]]$content, function(b) b$text, ""),
               "answer")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-transform")'`
Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`, with ``could not find function "handoff_transform"``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-transform.R`:

```r
# Projection of the transcript tree and the cross-provider hand-off transform (P05).
# Contract: dev/spec/04-interface-contract.md section 7.5 (project_messages(),
# handoff_transform()); architecture section 5.2; INFRA-04 and INFRA-08 (report 10a section 14).
# Ported from Pi transformMessages() (packages/ai/src/api/transform-messages.ts:64-235; report 03
# sections 2.9 and 3.5; R prototype transform_messages() in 03 section 5.5) and from report 02
# section 5.3 project_for_provider() with the verifier's fix (a system/operator message that
# lands between tool calls and their results is held back, 02 section 2.7). Tool-id rules:
# anthropic-messages.ts:1215-1218, openai-completions.ts:1194-1218,
# openai-responses-shared.ts:154-177, mistral-conversations.ts:237-267 (hash = the first hex
# digits of SHA-256 instead of Pi's 53-bit string hash, as in report 03 section 4.3).

#' Placeholder texts for images a target model cannot read (Pi transform-messages.ts)
#' @noRd
handoff_image_text = c(user = "(image omitted: model does not support images)",
                       tool = "(tool image omitted: model does not support images)")

#' Cross-provider hand-off of already projected messages to `target` (a model record)
#'
#' Same model (provider, api and id equal): signatures, redacted thinking and opaque blocks of
#' that model are kept; empty unsigned thinking is dropped. Otherwise thinking becomes plain text
#' (dropped when the target or its adapter says `reasoning_replay = FALSE`), redacted thinking,
#' opaque blocks of other models, text signatures and thought signatures are dropped, and tool
#' ids are normalised to the target api's rules. Images become a placeholder when the target
#' reads no images.
#' @noRd
handoff_transform = function(messages, target) {
  images = "image" %in% as.character(unlist(target[["input"]] %||% "text"))
  normalise = handoff_id_normaliser(target)
  as_text = handoff_thinking_as_text(target)
  id_map = character()
  out = vector("list", length(messages))
  for (k in seq_along(messages)) {
    m = messages[[k]]
    if (is.null(m[["content"]])) m[["content"]] = list()
    role = m[["role"]] %||% ""
    if (!images && role %in% c("user", "tool_result")) {
      text = handoff_image_text[[if (identical(role, "user")) "user" else "tool"]]
      m[["content"]] = handoff_strip_images(m[["content"]], text)
    }
    if (identical(role, "tool_result")) {
      new_id = id_map[m[["tool_call_id"]] %||% ""]
      if (!is.na(new_id)) m[["tool_call_id"]] = unname(new_id)
    } else if (identical(role, "assistant")) {
      same = handoff_same_model(m, target)
      blocks = list()
      for (b in m[["content"]]) {
        nb = if (same) handoff_block_same(b, target) else handoff_block_foreign(b, target, as_text)
        if (is.null(nb)) next
        if (!same && identical(nb[["type"]], "tool_call") && !is.null(normalise)) {
          nid = normalise(nb[["id"]], m)
          if (!identical(nid, nb[["id"]])) {
            id_map[[nb[["id"]]]] = nid
            nb[["id"]] = nid
          }
        }
        blocks[[length(blocks) + 1L]] = nb
      }
      m[["content"]] = blocks
    }
    out[[k]] = m
  }
  out
}

#' Does the target take foreign thinking as plain text (reasoning replay)?
#'
#' `reasoning_replay` is an adapter capability (04 section 8.1); a model record may override it.
#' FALSE only when the model record or the registered adapter of the target api says FALSE
#' explicitly; otherwise foreign thinking becomes text, as in Pi.
#' @noRd
handoff_thinking_as_text = function(target) {
  v = target[["capabilities"]][["reasoning_replay"]]
  api = target[["api"]]
  if (is.null(v) && is.character(api) && length(api) == 1L && !is.na(api) && nzchar(api)) {
    a = tryCatch(registry_get("adapter", api), error = function(e) NULL)
    v = a[["capabilities"]][["reasoning_replay"]]
  }
  !isFALSE(v)
}

#' Is the assistant message from the target model (provider, api and model id equal)?
#' @noRd
handoff_same_model = function(m, target) {
  identical(m[["provider"]], target[["provider"]]) && identical(m[["api"]], target[["api"]]) &&
    identical(m[["model"]], target[["id"]])
}

#' Does an opaque or thinking block belong to the target model?
#' @noRd
handoff_block_owned = function(b, target) {
  o = if (identical(b[["type"]], "opaque")) b else b[["origin"]]
  if (is.null(o)) return(TRUE)
  identical(o[["model"]], target[["id"]]) &&
    (is.null(o[["provider"]]) || identical(o[["provider"]], target[["provider"]])) &&
    (is.null(o[["api"]]) || identical(o[["api"]], target[["api"]]))
}

#' A block of a same-model assistant message (NULL = dropped)
#' @noRd
handoff_block_same = function(b, target) {
  type = b[["type"]] %||% ""
  if (identical(type, "opaque")) return(if (handoff_block_owned(b, target)) b else NULL)
  if (identical(type, "thinking")) {
    if (!handoff_block_owned(b, target)) return(handoff_block_foreign(b, target, TRUE))
    if (isTRUE(b[["redacted"]]) || nzchar(b[["signature"]] %||% "")) return(b)
    if (!nzchar(trimws(b[["thinking"]] %||% ""))) return(NULL)
  }
  b
}

#' A block of a foreign assistant message (NULL = dropped)
#' @noRd
handoff_block_foreign = function(b, target, as_text) {
  type = b[["type"]] %||% ""
  if (identical(type, "thinking")) {
    if (isTRUE(b[["redacted"]])) return(NULL)
    txt = b[["thinking"]] %||% ""
    if (!nzchar(trimws(txt)) || !as_text) return(NULL)
    return(block_text(txt))
  }
  if (identical(type, "text")) return(block_text(b[["text"]] %||% ""))
  if (identical(type, "tool_call")) {
    b[["thought_signature"]] = NULL
    return(b)
  }
  if (identical(type, "opaque")) return(if (handoff_block_owned(b, target)) b else NULL)
  b
}

#' Replace each run of image blocks with one placeholder text block
#' @noRd
handoff_strip_images = function(content, placeholder) {
  out = list()
  prev = FALSE
  for (b in content) {
    if (identical(b[["type"]], "image")) {
      if (!prev) out[[length(out) + 1L]] = block_text(placeholder)
      prev = TRUE
      next
    }
    out[[length(out) + 1L]] = b
    prev = identical(b[["type"]], "text") && identical(b[["text"]], placeholder)
  }
  out
}

#' The compat record of the target's provider (empty when the provider is not registered)
#' @noRd
handoff_compat = function(target) {
  id = target[["provider"]]
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(list())
  provider_get(id)[["compat"]] %||% list()
}

#' The tool-id normaliser `function(id, source_message)` for the target api (NULL = keep ids)
#' @noRd
handoff_id_normaliser = function(target) {
  if (identical(handoff_compat(target)[["tool_id"]], "alnum9")) return(id_alnum9_normaliser())
  switch(target[["api"]] %||% "",
         "anthropic-messages" = ,
         "google-generative-ai" = function(id, source) id_sanitize(id, 64L),
         "openai-completions" = function(id, source) id_completions(id, target[["provider"]]),
         "openai-responses" = function(id, source) id_responses(id, target, source),
         NULL)
}

#' Replace characters outside `[A-Za-z0-9_-]` and cut to `max` characters
#' @noRd
id_sanitize = function(id, max) substr(gsub("[^a-zA-Z0-9_-]", "_", id), 1L, max)

#' The first `n` hex digits of the SHA-256 of `x` (RNG-free)
#' @noRd
id_hash = function(x, n = 12L) substr(hash_sha256(x), 1L, n)

#' Chat Completions tool ids: `call|item` joined, at most 40 characters (hash suffix if longer)
#' @noRd
id_completions = function(id, provider) {
  if (grepl("|", id, fixed = TRUE)) {
    sep = regexpr("|", id, fixed = TRUE)
    call = gsub("[^a-zA-Z0-9_-]", "_", substr(id, 1L, sep - 1L))
    item = gsub("[^a-zA-Z0-9_-]", "_", substring(id, sep + 1L))
    combined = if (nzchar(item)) paste0(call, "_", item) else call
    if (nchar(combined) <= 40L) return(combined)
    h = id_hash(id, 8L)
    return(paste0(substr(call, 1L, max(1L, 40L - nchar(h) - 1L)), "_", h))
  }
  if (identical(provider, "openai") && nchar(id) > 40L) return(substr(id, 1L, 40L))
  id
}

#' Responses tool ids: `call_id|item_id`, parts sanitised to 64, foreign items `fc_<hash>`
#' @noRd
id_responses = function(id, target, source) {
  part = function(x) sub("_+$", "", substr(gsub("[^a-zA-Z0-9_-]", "_", x), 1L, 64L))
  if (!grepl("|", id, fixed = TRUE)) return(part(id))
  sep = regexpr("|", id, fixed = TRUE)
  call = part(substr(id, 1L, sep - 1L))
  item_raw = substring(id, sep + 1L)
  foreign = !identical(source[["provider"]], target[["provider"]]) ||
    !identical(source[["api"]], target[["api"]])
  item = if (foreign) substr(paste0("fc_", id_hash(item_raw)), 1L, 64L) else part(item_raw)
  if (!startsWith(item, "fc_")) item = part(paste0("fc_", item))
  paste0(call, "|", item)
}

#' One candidate 9-character alphanumeric id (Mistral), `attempt` > 0 re-hashes on collision
#' @noRd
id_alnum9 = function(id, attempt) {
  norm = gsub("[^a-zA-Z0-9]", "", id)
  if (attempt == 0L && nchar(norm) == 9L) return(norm)
  base = if (nzchar(norm)) norm else id
  seed = if (attempt == 0L) base else paste0(base, ":", attempt)
  substr(hash_sha256(seed), 1L, 9L)
}

#' A collision-free 9-character id normaliser for one transform (Mistral)
#' @noRd
id_alnum9_normaliser = function() {
  fwd = character()
  back = character()
  function(id, source) {
    known = fwd[id]
    if (!is.na(known)) return(unname(known))
    attempt = 0L
    repeat {
      cand = id_alnum9(id, attempt)
      owner = back[cand]
      if (is.na(owner) || identical(unname(owner), id)) {
        fwd[[id]] <<- cand
        back[[cand]] <<- id
        return(cand)
      }
      attempt = attempt + 1L
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-transform")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 32 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-transform.R tests/testthat/test-provider-transform.R
git commit -m "feat(provider): cross-provider hand-off transform"
```

---

### Task 5: Projection of the transcript tree

**Files:**
- Modify: `R/provider-transform.R` (append)
- Test: `tests/testthat/test-provider-transform.R` (append)

**Interfaces:**
- Consumes: `msg_user(content, source = "prompt", timestamp = NULL)`, `msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL, usage = NULL, timestamp = NULL)`, `msg_operator(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL)`, `block_context(kind, text, attrs = list(), anchor = FALSE)`, `block_text()` (P01); `handoff_transform()` (Task 4).
- Produces: `project_messages(entries, leaf, target)` (04 section 7.5), consumed by P06 and P07.

Entries are in their R shape (04 section 4.6 with the section 4.8 name mapping), exactly as P06's store writes and reads them (`entry_message()`, `entry_from_json()` in P06's plan): every entry has `type`, `id`, `parent_id`, `timestamp`; a `message` entry holds `message` (a section 4.2 message); a `gptr.operator` `custom_message` entry holds the operator message itself as `message` (P06's shape, which has no `custom_type` field), or, in the flat form, `custom_type = "gptr.operator"`, `content` (text blocks) and `details = list(kind, tool_add, origin_text)`; other `custom_message` types (P06 keeps them under `raw`) are not model context; a `compaction` entry holds `summary`, `first_kept_entry_id`, `tokens_before` and `gptr = list(blocks, state, n)`. Other types (`model_change`, `thinking_level_change`, `custom`) are not model context.

Projection (INFRA-04; report 02 sections 2.7 and 5.3 with the verifier's held-message fix): walk root -> `leaf` (a missing parent re-parents to the previous entry in file order); the newest compaction's blocks become the first user message, followed by its kept range and everything after it; errored and aborted assistant messages are dropped; every tool call gets exactly one result: an orphan closed by an aborted turn gets `interrupted after <s> s; side effects may have occurred` (s from the two message timestamps), any other orphan `No result provided`, results that match no open call are dropped; operator messages that arrive while results are pending (steering relays) are held until the results are complete. Entries are never edited, and synthetic results take the timestamp of their assistant message so projections are byte-stable across turns (the prefix cache depends on it).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-transform.R`:

```r
tx_entry = function(id, parent, message) {
  list(type = "message", id = id, parent_id = parent, timestamp = "2026-09-30T10:00:00.000Z",
       message = message)
}

target_sonnet = function() tx_model("anthropic", "claude-sonnet-5-5", "anthropic-messages")

test_that("a recorded 401 and an abort are projected out; every call has one result (INFRA-04)", {
  entries = list(
    tx_entry("e1", NULL, msg_user("hello", timestamp = 1000)),
    tx_entry("e2", "e1", anthropic_msg(list(), "error", 1100, error = "401 invalid x-api-key")),
    tx_entry("e3", "e2", msg_user("again", timestamp = 1200)),
    tx_entry("e4", "e3", anthropic_msg(list(block_tool_call("toolu_a", "r", list(code = "1")),
                                            block_tool_call("toolu_b", "r", list(code = "2"))),
                                       "tool_use", 2000)),
    tx_entry("e5", "e4", msg_tool_result("toolu_a", "r", "1", timestamp = 2100)),
    tx_entry("e6", "e5", anthropic_msg(list(block_text("partial")), "aborted", 4300)),
    tx_entry("e7", "e6", msg_user("continue", timestamp = 5000))
  )
  before = entries
  out = project_messages(entries, "e7", target_sonnet())
  expect_identical(entries, before)
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "user", "assistant", "tool_result", "tool_result", "user"))
  assistant = Filter(function(x) identical(x$role, "assistant"), out)
  expect_false(any(vapply(assistant, function(x) x$stop_reason %in% c("error", "aborted"), NA)))
  expect_false(any(grepl("401|partial", vapply(out, msg_text, ""))))
  results = vapply(Filter(function(x) identical(x$role, "tool_result"), out),
                   function(x) x$tool_call_id, "")
  expect_equal(sort(results), c("toolu_a", "toolu_b"))
  synthetic = out[[5]]
  expect_true(synthetic$is_error)
  expect_equal(synthetic$content[[1]]$text,
               "interrupted after 2.3 s; side effects may have occurred")
})

test_that("a call left open by a new user turn gets 'No result provided'", {
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list())), ts = 2)),
    tx_entry("e3", "e2", msg_user("never mind", timestamp = 3)),
    tx_entry("e4", "e3", msg_tool_result("c1", "r", "late result", timestamp = 4))
  )
  out = project_messages(entries, "e4", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""), c("user", "assistant", "tool_result", "user"))
  expect_equal(out[[3]]$content[[1]]$text, "No result provided")
  expect_true(out[[3]]$is_error)
})

test_that("operator relays wait until the tool results are complete", {
  relay = list(type = "custom_message", id = "e4", parent_id = "e3",
               timestamp = "2026-09-30T10:00:00.004Z", custom_type = "gptr.operator",
               content = list(block_text(
                 "The user sent this message while you were working: use TPM"
               )),
               display = FALSE, details = list(kind = "steer_relay", origin_text = "use TPM"))
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list()),
                                            block_tool_call("c2", "r", list())), ts = 2)),
    tx_entry("e3", "e2", msg_tool_result("c1", "r", "one", timestamp = 3)),
    relay,
    tx_entry("e5", "e4", msg_tool_result("c2", "r", "two", timestamp = 5))
  )
  out = project_messages(entries, "e5", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "assistant", "tool_result", "tool_result", "operator"))
  expect_equal(out[[5]]$kind, "steer_relay")
  expect_match(msg_text(out[[5]]), "use TPM", fixed = TRUE)
})

test_that("operator entries in the session kernel's shape (a `message` field) are projected", {
  op = msg_operator("steer_relay", "The user sent this message while you were working: use TPM",
                    origin_text = "use TPM", timestamp = 4)
  entries = list(
    tx_entry("e1", NULL, msg_user("go", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_tool_call("c1", "r", list())), ts = 2)),
    list(type = "custom_message", id = "e3", parent_id = "e2",
         timestamp = "2026-09-30T10:00:00.003Z", message = op),
    tx_entry("e4", "e3", msg_tool_result("c1", "r", "one", timestamp = 5)),
    list(type = "custom_message", id = "e5", parent_id = "e4",
         timestamp = "2026-09-30T10:00:00.006Z",
         message = msg_operator("mode", "Mode is now auto.", timestamp = 6)),
    list(type = "custom_message", id = "e6", parent_id = "e5",
         timestamp = "2026-09-30T10:00:00.007Z",
         raw = list(customType = "pi.note", content = list(), display = TRUE))
  )
  out = project_messages(entries, "e6", target_sonnet())
  expect_equal(vapply(out, function(x) x$role, ""),
               c("user", "assistant", "tool_result", "operator", "operator"))
  expect_identical(out[[4]], op)
  expect_equal(out[[5]]$kind, "mode")
})

test_that("the newest compaction replaces everything before its first kept entry", {
  checkpoint = block_context("checkpoint", "Summary: fitted lm.", attrs = list(n = "1"))
  entries = list(
    tx_entry("e1", NULL, msg_user("old question", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_text("old answer")), "stop", 2)),
    tx_entry("e3", "e2", msg_user("kept question", timestamp = 3)),
    tx_entry("e4", "e3", anthropic_msg(list(block_text("kept answer")), "stop", 4)),
    list(type = "compaction", id = "e5", parent_id = "e4", timestamp = "2026-09-30T10:00:05.000Z",
         summary = "fitted lm", first_kept_entry_id = "e3", tokens_before = 1234,
         gptr = list(blocks = list(checkpoint), n = 1L)),
    tx_entry("e6", "e5", msg_user("new question", timestamp = 6))
  )
  out = project_messages(entries, "e6", target_sonnet())
  expect_equal(length(out), 4L)
  expect_equal(out[[1]]$content[[1]]$type, "context")
  expect_match(out[[1]]$content[[1]]$text, "Summary: fitted lm.", fixed = TRUE)
  expect_equal(vapply(out[-1], msg_text, ""), c("kept question", "kept answer", "new question"))
  bare = entries
  bare[[5]]$gptr = NULL
  out2 = project_messages(bare, "e6", target_sonnet())
  expect_match(out2[[1]]$content[[1]]$text, "fitted lm", fixed = TRUE)
})

test_that("the path follows parent ids, tolerates a missing parent and rejects an unknown leaf", {
  entries = list(
    tx_entry("e1", NULL, msg_user("root", timestamp = 1)),
    tx_entry("e2", "e1", anthropic_msg(list(block_text("branch a")), "stop", 2)),
    tx_entry("e3", "e1", anthropic_msg(list(block_text("branch b")), "stop", 3)),
    tx_entry("e4", "gone", msg_user("after a torn line", timestamp = 4))
  )
  expect_equal(vapply(project_messages(entries, "e2", target_sonnet()), msg_text, ""),
               c("root", "branch a"))
  expect_equal(vapply(project_messages(entries, "e3", target_sonnet()), msg_text, ""),
               c("root", "branch b"))
  expect_equal(vapply(project_messages(entries, "e4", target_sonnet()), msg_text, ""),
               c("root", "branch b", "after a torn line"))
  expect_equal(project_messages(entries, NULL, target_sonnet()), list())
  expect_error(project_messages(entries, "nope", target_sonnet()), class = "gptr_error_internal")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-transform")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 32 ]`, with ``could not find function "project_messages"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-transform.R`:

```r
#' The model-context message list for `target` along the path root -> `leaf`
#'
#' Never edits `entries` (R lists are values). Steps: walk the path; the newest compaction
#' entry replaces everything before its first kept entry; entries become messages; errored and
#' aborted assistant messages are dropped; orphaned tool calls get one synthetic error result;
#' operator messages that arrive while tool results are pending are held until the results are
#' complete; results that match no pending call are dropped; then [handoff_transform()].
#' @noRd
project_messages = function(entries, leaf, target) {
  path = entry_compaction_cut(entry_path(entries, leaf))
  msgs = unlist(lapply(path, entry_messages), recursive = FALSE) %||% list()
  handoff_transform(project_structure(msgs), target)
}

#' Entries on the path root -> `leaf` (a missing parent re-parents to the previous entry)
#' @noRd
entry_path = function(entries, leaf) {
  if (is.null(leaf) || !length(entries)) return(list())
  ids = vapply(entries, function(e) as.character(e[["id"]] %||% NA_character_), "")
  pos = match(leaf, ids)
  if (is.na(pos)) {
    gptr_abort(paste0("The leaf entry ", leaf, " is not in the transcript."), "internal",
               detail = "project_messages: unknown leaf")
  }
  chain = integer(length(entries))
  seen = logical(length(entries))
  k = 0L
  while (!is.na(pos) && !seen[pos]) {
    seen[pos] = TRUE
    k = k + 1L
    chain[k] = pos
    parent = entries[[pos]][["parent_id"]]
    if (is.null(parent) || is.na(parent[1])) break
    nxt = match(parent, ids)
    if (is.na(nxt)) nxt = if (pos > 1L) pos - 1L else NA_integer_
    pos = nxt
  }
  entries[rev(chain[seq_len(k)])]
}

#' Apply the newest compaction entry: it first, then its kept range, then what follows it
#' @noRd
entry_compaction_cut = function(path) {
  if (!length(path)) return(path)
  types = vapply(path, function(e) as.character(e[["type"]] %||% ""), "")
  ci = which(types == "compaction")
  if (!length(ci)) return(path)
  ci = max(ci)
  first = path[[ci]][["first_kept_entry_id"]]
  ids = vapply(path, function(e) as.character(e[["id"]] %||% ""), "")
  from = if (is.null(first)) NA_integer_ else match(first, ids)
  kept = if (!is.na(from) && from < ci) path[from:(ci - 1L)] else list()
  after = if (ci < length(path)) path[(ci + 1L):length(path)] else list()
  c(path[ci], kept, after)
}

#' Epoch milliseconds from an entry timestamp (ISO 8601 UTC); 0 when unparsable
#' @noRd
entry_ms = function(ts) {
  if (is.numeric(ts) && length(ts)) return(as.numeric(ts[[1]]))
  if (!is.character(ts) || !length(ts) || is.na(ts[[1]])) return(0)
  t = as.POSIXct(sub("Z$", "", ts[[1]]), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  if (is.na(t)) 0 else round(as.numeric(t) * 1000)
}

#' The model-context messages of one entry (a list of 0 or 1 messages)
#' @noRd
entry_messages = function(e) {
  type = e[["type"]] %||% ""
  if (identical(type, "message")) {
    return(if (is.null(e[["message"]])) list() else list(e[["message"]]))
  }
  if (identical(type, "custom_message")) {
    # P06 keeps a gptr.operator entry as list(type = "custom_message", message = <operator>);
    # the flat form (custom_type, content, details) is accepted too. Other custom types are not
    # model context.
    m = e[["message"]]
    if (is.list(m) && identical(m[["role"]], "operator")) return(list(m))
    ct = e[["custom_type"]] %||% e[["raw"]][["customType"]]
    if (identical(ct, "gptr.operator")) return(list(entry_operator(e)))
    return(list())
  }
  if (identical(type, "compaction")) return(list(entry_compaction_message(e)))
  list()
}

#' The operator message of a flat `gptr.operator` custom_message entry
#' @noRd
entry_operator = function(e) {
  d = e[["details"]] %||% list()
  texts = vapply(e[["content"]] %||% list(), function(b) as.character(b[["text"]] %||% ""), "")
  msg_operator(d[["kind"]] %||% "reminder", paste(texts, collapse = "\n"),
               tool_add = d[["tool_add"]], origin_text = d[["origin_text"]],
               timestamp = entry_ms(e[["timestamp"]]))
}

#' The first user message a compaction entry stands for (its stored context blocks)
#' @noRd
entry_compaction_message = function(e) {
  blocks = e[["gptr"]][["blocks"]]
  if (!length(blocks)) {
    tb = e[["tokens_before"]]
    attrs = if (is.null(tb)) list() else list(tokens_before = format(tb, scientific = FALSE))
    blocks = list(block_context("checkpoint", as.character(e[["summary"]] %||% ""),
                                attrs = attrs))
  }
  msg_user(blocks, source = "prompt", timestamp = entry_ms(e[["timestamp"]]))
}

#' The synthetic result of an orphaned tool call (INFRA-04 wording)
#'
#' A call left open by an aborted run (the next assistant message is `aborted`) says how long
#' after the call the run was interrupted; any other orphan says "No result provided".
#' @noRd
orphan_result = function(call, owner, next_msg) {
  text = "No result provided"
  aborted_turn = is.list(next_msg) && identical(next_msg[["role"]], "assistant") &&
    identical(next_msg[["stop_reason"]], "aborted")
  if (aborted_turn) {
    s = (as.numeric(next_msg[["timestamp"]] %||% NA_real_) -
           as.numeric(owner[["timestamp"]] %||% NA_real_)) / 1000
    if (!is.na(s) && s >= 0) {
      text = paste0("interrupted after ", format(round(s, 1), nsmall = 1),
                    " s; side effects may have occurred")
    }
  }
  msg_tool_result(call[["id"]], call[["name"]], list(block_text(text)), is_error = TRUE,
                  timestamp = owner[["timestamp"]] %||% 0)
}

#' Structural projection: drop failed turns, close orphans, hold operator messages
#' @noRd
project_structure = function(msgs) {
  out = list()
  pending = list()
  owner = NULL
  answered = character()
  held = list()
  close_pending = function(next_msg) {
    for (call in pending) {
      if (!(call[["id"]] %in% answered)) {
        out[[length(out) + 1L]] <<- orphan_result(call, owner, next_msg)
      }
    }
    for (h in held) out[[length(out) + 1L]] <<- h
    pending <<- list()
    owner <<- NULL
    answered <<- character()
    held <<- list()
  }
  for (m in msgs) {
    role = m[["role"]] %||% ""
    if (identical(role, "assistant")) {
      close_pending(m)
      if ((m[["stop_reason"]] %||% "") %in% c("error", "aborted")) next
      out[[length(out) + 1L]] = m
      calls = Filter(function(b) identical(b[["type"]], "tool_call"), m[["content"]] %||% list())
      if (length(calls)) {
        pending = calls
        owner = m
      }
    } else if (identical(role, "tool_result")) {
      id = m[["tool_call_id"]] %||% ""
      open = vapply(pending, function(b) as.character(b[["id"]]), "")
      if (id %in% open && !(id %in% answered)) {
        answered = c(answered, id)
        out[[length(out) + 1L]] = m
      }
    } else if (identical(role, "operator") && length(pending)) {
      held[[length(held) + 1L]] = m
    } else if (identical(role, "user")) {
      close_pending(m)
      out[[length(out) + 1L]] = m
    } else {
      out[[length(out) + 1L]] = m
    }
  }
  close_pending(NULL)
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-transform")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 58 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-transform.R tests/testthat/test-provider-transform.R
git commit -m "feat(provider): projection of the transcript tree for model requests"
```

---

### Task 6: Catalog data, models.dev conversion and the shipped snapshot

**Files:**
- Create: `R/catalog-models.R`
- Create: `dev/catalog/build_models.R`
- Create: `inst/extdata/models.json.gz` (generated by the script)
- Test: `tests/testthat/test-catalog-models.R` (create)

**Interfaces:**
- Consumes: `json_obj()`, `json_decode(text)`, `json_encode(x, pretty = FALSE)`, `gptr_user_dir(which = c("config", "cache", "data"), create = FALSE)` (P01); `provider_table()` (Task 2).
- Produces: the snapshot format of 04 section 11.10; private `catalog_snapshot(api = NULL, decision = NULL, generated = format(Sys.Date(), "%Y-%m-%d"))`, `catalog_from_modelsdev(api, decision = NULL)`, `catalog_read(path)`, `catalog_merge_models(base, layer, patch_only = FALSE)`, `catalog_seed()`, `catalog_overrides()`, the path helpers `catalog_snapshot_path()`, `catalog_cache_path()`, `catalog_etag_path()`, and `catalog_thinking_levels`.

A snapshot is built as seed < models.dev < overrides. The seed holds complete entries for the models the specification names (so an offline build still resolves every alias the architecture uses); models.dev entries are pruned to gptr's providers, tool-capable, text-output, non-deprecated models (report 09 section 4.8: about 700 models, about 22 KB gzipped); the overrides carry gptr's reviewed prices (dated tiers), `cache_min`, `max_images`, capabilities and aliases, and only patch existing entries unless they are complete. models.dev is MIT licensed and credited in P01's `inst/COPYRIGHTS`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-catalog-models.R`:

```r
# Tests for R/catalog-models.R (plan P05): snapshot structure, models.dev conversion, merge
# layers, the resolver, defaults, explicit refresh and gptr_models().

test_that("the shipped snapshot has the documented structure (04 section 11.10)", {
  path = system.file("extdata", "models.json.gz", package = "gptr")
  expect_true(nzchar(path))
  expect_lt(file.size(path), 1e6)
  snap = catalog_read(path)
  expect_identical(snap$schema_version, 1L)
  expect_match(snap$generated, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
  expect_true(all(c("anthropic", "openai", "google", "ollama", "typesafe") %in%
                    names(snap$providers)))
  expect_equal(snap$providers$anthropic$api, "anthropic-messages")
  expect_equal(unlist(snap$providers$google$env), c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  refs = vapply(snap$models, function(m) paste0(m$provider, "/", m$id), "")
  expect_true(all(c("anthropic/claude-sonnet-5-5", "anthropic/claude-opus-5-5",
                    "anthropic/claude-haiku-4-5", "openai/gpt-6-sol", "google/gemini-3.8-flash",
                    "typesafe/jev-latest") %in% refs))
  expect_true(all(c("sonnet", "opus", "haiku", "gemini", "flash", "gpt", "jev", "claude_code",
                    "codex") %in% names(snap$aliases)))
  sonnet = snap$models[[match("anthropic/claude-sonnet-5-5", refs)]]
  expect_equal(sonnet$prices[[1]]$input, 2)
  expect_equal(sonnet$cache_min, 512)
  expect_false(sonnet$capabilities$forced_tool_choice)
})

test_that("models.dev entries are pruned and converted; overrides only patch", {
  api = list(
    anthropic = list(id = "anthropic", env = list("ANTHROPIC_API_KEY"), models = list(
      `claude-sonnet-5-5` = list(
        id = "claude-sonnet-5-5", name = "Claude Sonnet 5.5", family = "claude-sonnet",
        reasoning = TRUE, tool_call = TRUE, structured_output = TRUE, release_date = "2026-09",
        reasoning_options = list(list(type = "effort",
                                      values = list("low", "medium", "high", "xhigh", "max"))),
        modalities = list(input = list("text", "image", "pdf", "video"), output = list("text")),
        limit = list(context = 1e6, output = 128000),
        cost = list(input = 3, output = 15, cache_read = 0.3, cache_write = 3.75,
                    context_over_200k = list(input = 6, output = 22.5)),
        canonical_model_id = "anthropic/claude-sonnet-5-5"
      ),
      `old-model` = list(id = "old-model", tool_call = TRUE, status = "deprecated",
                         modalities = list(input = list("text"), output = list("text"))),
      `no-tools` = list(id = "no-tools", tool_call = FALSE,
                        modalities = list(input = list("text"), output = list("text")))
    )),
    elsewhere = list(id = "elsewhere", models = list(x = list(id = "x", tool_call = TRUE)))
  )
  decision = list(`typesafe/jev-latest` = list(
    id = "typesafe/jev-latest", type = "decision", name = "Jev", release_date = "2026-09-15",
    limit = list(context = 64000, output = 0), structured_output = TRUE
  ))
  x = catalog_from_modelsdev(api, decision)
  expect_setequal(names(x), c("anthropic/claude-sonnet-5-5", "typesafe/jev-latest"))
  s = x[["anthropic/claude-sonnet-5-5"]]
  expect_equal(as.character(s$thinking_levels), c("low", "medium", "high", "xhigh", "max"))
  expect_equal(as.character(s$input), c("text", "image", "pdf"))
  expect_equal(s$release_date, "2026-09-01")
  expect_equal(vapply(s$prices, function(p) p$tier, ""), c("default", ">200k"))
  expect_equal(s$owner, "anthropic")
  expect_equal(x[["typesafe/jev-latest"]]$type, "classifier")
  snap = catalog_snapshot(api, decision, generated = "2026-09-30")
  expect_equal(snap$source, "models.dev (MIT) + gptr overrides")
  refs = vapply(snap$models, function(m) paste0(m$provider, "/", m$id), "")
  expect_identical(refs, sort(refs, method = "radix"))
  merged = snap$models[[match("anthropic/claude-sonnet-5-5", refs)]]
  expect_equal(merged$prices[[1]]$input, 2)
  expect_equal(merged$name, "Claude Sonnet 5.5")
  offline = catalog_snapshot(generated = "2026-09-30")
  expect_equal(offline$source, "gptr seed + overrides")
  expect_true(all(vapply(offline$models, function(m) !is.null(m$name), NA)))
  expect_type(json_encode(offline), "character")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`, with ``could not find function "catalog_read"`` and ``could not find function "catalog_from_modelsdev"``.

- [ ] **Step 3: Write the implementation**

Create `R/catalog-models.R`:

```r
# Model catalog: snapshot, merge layers, aliases, the model resolver, explicit refresh and
# gptr_models() (P05).
# Contract: dev/spec/04-interface-contract.md sections 4.9, 6.2 (gptr_models()), 7.5 and 11.10;
# architecture section 8.4; IC-67 (max_images), IC-71 (forced_tool_choice), IC-73 (cache_min).
# The resolver is report 09 section 5.5's verified algorithm (match_pattern(), break_tie(),
# norm_id(), resolve_alias(); verification log row 34: a tie goes to the single provider with a
# credential first, then to the owner of models.dev's canonical_model_id) with Pi's last-colon
# thinking rule (model-resolver.ts:204-257) and Pi's clamp (models.ts:1215-1249; report 03
# section 3.4). Catalog strategy: 09 section 4.8 (snapshot built by a maintainer script,
# refreshed only on explicit request with ETag into R_user_dir(); nothing at load).

#' Thinking levels in order (Pi EXTENDED_THINKING_LEVELS)
#' @noRd
catalog_thinking_levels = c("off", "minimal", "low", "medium", "high", "xhigh", "max")

#' models.dev endpoints used by the maintainer build and by gptr_models(refresh = TRUE)
#' @noRd
catalog_source_url = "https://models.dev/api.json"

#' The models.dev System 1 (decision) endpoint
#' @noRd
catalog_decision_url = "https://models.dev/models.json?type=decision"

#' Path of the shipped snapshot
#' @noRd
catalog_snapshot_path = function() system.file("extdata", "models.json.gz", package = "gptr")

#' Path of the refreshed catalog in the user cache
#' @noRd
catalog_cache_path = function() file.path(gptr_user_dir("cache"), "models.json")

#' Path of the ETag of the refreshed catalog
#' @noRd
catalog_etag_path = function() file.path(gptr_user_dir("cache"), "models.etag")

#' gptr provider ids and the models.dev provider ids they are built from
#' @noRd
catalog_modelsdev_ids = function() {
  c(anthropic = "anthropic", openai = "openai", google = "google", openrouter = "openrouter",
    groq = "groq", deepseek = "deepseek", mistral = "mistral", together = "togetherai",
    xai = "xai", cerebras = "cerebras", fireworks = "fireworks-ai", lmstudio = "lmstudio",
    azure = "azure", bedrock = "amazon-bedrock")
}

#' One price row in catalog (JSON) shape; NULL rates are omitted
#' @noRd
catalog_price = function(tier, input, output, cache_read = NULL, cache_write_5m = NULL,
                         cache_write_1h = NULL, from = "2000-01-01") {
  Filter(Negate(is.null),
         list(from = from, tier = tier, input = input, output = output, cache_read = cache_read,
              cache_write_5m = cache_write_5m, cache_write_1h = cache_write_1h))
}

#' Complete entries for the models the specification names (the base of every snapshot)
#'
#' Values from reports 07 section 2.1, 03 section 2.10, 08 finding 10, 09 section 5.6 and G2
#' section 2.4 (all verified 2026-09-29/30). models.dev entries replace these fields when the
#' maintainer build downloads models.dev; `--offline` builds ship them alone.
#' @noRd
catalog_seed = function() {
  claude = function(id, name, family, date, context, output, levels) {
    list(provider = "anthropic", id = id, name = name, family = family, release_date = date,
         context = context, max_output = output, reasoning = TRUE, thinking_levels = I(levels),
         input = I(c("text", "image", "pdf")), tool_call = TRUE, structured_output = TRUE,
         status = "active", owner = "anthropic")
  }
  adaptive = c("low", "medium", "high", "xhigh", "max")
  list(
    claude("claude-sonnet-5-5", "Claude Sonnet 5.5", "claude-sonnet", "2026-09-28", 1e6, 128000,
           c("off", adaptive)),
    claude("claude-opus-5-5", "Claude Opus 5.5", "claude-opus", "2026-09-22", 1e6, 128000,
           adaptive),
    claude("claude-fable-5-1", "Claude Fable 5.1", "claude-fable", NULL, 1e6, 128000, adaptive),
    claude("claude-haiku-4-5", "Claude Haiku 4.5", "claude-haiku", "2025-10-01", 200000, 64000,
           c("off", "minimal", "low", "medium", "high")),
    list(provider = "openai", id = "gpt-6.1-sol", name = "GPT-6.1 Sol", family = "gpt-sol",
         release_date = "2026-09-29", context = 1050000, max_output = 128000, reasoning = TRUE,
         thinking_levels = I(adaptive), input = I(c("text", "image")), tool_call = TRUE,
         structured_output = TRUE, status = "active", owner = "openai"),
    list(provider = "openai", id = "gpt-6-sol", name = "GPT-6 Sol", family = "gpt-sol",
         context = 1050000, max_output = 128000, reasoning = TRUE,
         thinking_levels = I(c("off", "low", "medium", "high")), input = I(c("text", "image")),
         tool_call = TRUE, structured_output = TRUE, status = "active", owner = "openai"),
    list(provider = "google", id = "gemini-3.8-flash", name = "Gemini 3.8 Flash",
         family = "gemini-flash", release_date = "2026-09-02", context = 1048576,
         max_output = 65536, reasoning = TRUE, thinking_levels = I(c("low", "medium", "high")),
         input = I(c("text", "image", "pdf")), tool_call = TRUE, structured_output = TRUE,
         status = "active", owner = "google")
  )
}

#' gptr's reviewed corrections, applied on top of every source (snapshot, cache, refresh)
#'
#' Prices and cache multipliers: 07 section 2.1 (Anthropic), 08 finding 10 (OpenAI, the 272K
#' context tier: 2x input and cache, 1.5x output), G2 fact-check row 7 (Gemini 3.8 Flash
#' promotional prices end 2026-12-31). cache_min: 07 section 2.7 and G4 (512 on Fable 5.1, Opus
#' 5.5, Sonnet 5.5; 4,096 on Haiku 4.5 and Gemini 3.x; 1,024 on OpenAI). max_images: 07 section
#' 2.8 (600 per request, 100 for 200K-context models). forced_tool_choice FALSE on Anthropic 5.x
#' (IC-71). Thinking: Opus 5.5 and Fable 5.1 think always (no "off"); Sonnet 5.5 also accepts
#' "off" (07 section 2.1 table: "adaptive (off = between_tools)"). Aliases: architecture section
#' 8.4 and 04 section 11.10.
#' @noRd
catalog_overrides = function() {
  claude5 = list(mid_system = TRUE, tool_addition = TRUE, images_in_results = TRUE,
                 operator_role = TRUE, adaptive_thinking = TRUE, effort = TRUE,
                 forced_tool_choice = FALSE)
  anthropic = function(id, input, output, read, w5, w1, cache_min, max_images, caps,
                       levels = NULL) {
    Filter(Negate(is.null),
           list(provider = "anthropic", id = id,
                thinking_levels = if (is.null(levels)) NULL else I(levels),
                prices = list(catalog_price("default", input, output, read, w5, w1)),
                cache_min = cache_min, max_images = max_images, capabilities = caps))
  }
  adaptive = c("low", "medium", "high", "xhigh", "max")
  list(
    providers = list(
      anthropic = list(capabilities = list(tool_addition = TRUE, images_in_results = TRUE,
                                           operator_role = TRUE)),
      openai = list(capabilities = list(images_in_results = TRUE, operator_role = TRUE)),
      google = list(capabilities = list(images_in_results = TRUE)),
      typesafe = list(api = "typesafe-system-one", base_url = "https://api.typesafe.ai/v1/",
                      env = I("TYPESAFE_API_KEY"), compat = json_obj(), local = FALSE)
    ),
    models = list(
      anthropic("claude-opus-5-5", 4, 20, 0.20, 5, 8, 512, 600, claude5, adaptive),
      anthropic("claude-sonnet-5-5", 2, 10, 0.20, 2.50, 4, 512, 600, claude5,
                c("off", adaptive)),
      anthropic("claude-fable-5-1", 10, 50, 0.25, 12.50, 20, 512, 600, claude5),
      anthropic("claude-haiku-4-5", 1, 5, 0.10, 1.25, 2, 4096, 100,
                list(mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
                     operator_role = TRUE, adaptive_thinking = FALSE, effort = FALSE,
                     forced_tool_choice = TRUE)),
      list(provider = "openai", id = "gpt-6.1-sol", cache_min = 1024,
           prices = list(catalog_price("default", 2, 10, 0.10, 2.50),
                         catalog_price(">272k", 4, 15, 0.20, 5))),
      list(provider = "openai", id = "gpt-6-sol", cache_min = 1024,
           prices = list(catalog_price("default", 2, 10, 0.20, 2.50),
                         catalog_price(">272k", 4, 15, 0.40, 5))),
      list(provider = "google", id = "gemini-3.8-flash", cache_min = 4096,
           prices = list(catalog_price("default", 0.75, 3.75, 0.075),
                         catalog_price("default", 1.50, 7.50, 0.15, from = "2027-01-01"))),
      list(provider = "typesafe", id = "jev-latest", name = "Jev", family = "jev",
           type = "classifier", release_date = "2026-09-15", context = 64000, max_output = 0,
           reasoning = FALSE, thinking_levels = I("off"), input = I("text"), tool_call = FALSE,
           structured_output = TRUE, prices = list(catalog_price("default", 0.042, 0, 0)),
           status = "active", owner = "typesafe")
    ),
    aliases = list(
      sonnet = list(provider = "anthropic", family = "claude-sonnet"),
      opus = list(provider = "anthropic", family = "claude-opus"),
      haiku = list(provider = "anthropic", family = "claude-haiku"),
      gemini = list(provider = "google", family = "gemini-pro",
                    pattern = "^gemini-[0-9.]+-pro(-preview)?$"),
      flash = list(provider = "google", family = "gemini-flash"),
      gpt = list(provider = "openai", pattern = "^gpt-[0-9.]+-sol$"),
      jev = list(ref = "typesafe/jev-latest"),
      claude_code = list(ref = "claude-cli/default"),
      codex = list(ref = "codex/default")
    ),
    small = list(
      anthropic = list(provider = "anthropic", family = "claude-haiku"),
      openai = list(provider = "openai", pattern = "^gpt-[0-9.]+-luna$"),
      google = list(provider = "google", family = "gemini-flash-lite")
    )
  )
}

#' The providers section of a snapshot, from the built-in provider table and the overrides
#' @noRd
catalog_providers_section = function() {
  out = list()
  for (r in provider_table()) {
    out[[r[["id"]]]] = list(api = r[["api"]], base_url = r[["base_url"]],
                            env = I(if (is.character(r[["auth"]])) r[["auth"]] else character()),
                            compat = if (length(r[["compat"]])) r[["compat"]] else json_obj(),
                            local = isTRUE(r[["local"]]))
  }
  utils::modifyList(out, catalog_overrides()[["providers"]])
}

#' ISO date of a models.dev date ("YYYY-MM" becomes the first of the month)
#' @noRd
catalog_date = function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]])) return(NULL)
  x = as.character(x[[1]])
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) return(x)
  if (grepl("^[0-9]{4}-[0-9]{2}$", x)) return(paste0(x, "-01"))
  NULL
}

#' gptr status of a models.dev status
#' @noRd
catalog_status = function(x) {
  if (is.null(x) || !length(x)) return("active")
  switch(as.character(x[[1]]), deprecated = "deprecated", beta = , alpha = "preview", "active")
}

#' Thinking levels from models.dev reasoning options (Pi generate-models.ts rules)
#' @noRd
catalog_levels_from = function(m) {
  if (!isTRUE(m[["reasoning"]])) return("off")
  effort = NULL
  toggle = FALSE
  for (o in m[["reasoning_options"]] %||% list()) {
    if (identical(o[["type"]], "effort")) effort = as.character(unlist(o[["values"]]))
    if (identical(o[["type"]], "toggle")) toggle = TRUE
  }
  if (is.null(effort)) return(c("off", "minimal", "low", "medium", "high"))
  out = intersect(c("minimal", "low", "medium", "high", "xhigh", "max"), effort)
  if ("none" %in% effort || toggle) out = c("off", out)
  if (length(out)) out else "off"
}

#' Price rows from a models.dev cost object (context tiers become `>Nk` rows)
#' @noRd
catalog_prices_from = function(cost) {
  if (!is.list(cost) || is.null(cost[["input"]])) return(list())
  row = function(tier, x) {
    catalog_price(tier, x[["input"]], x[["output"]], x[["cache_read"]], x[["cache_write"]])
  }
  out = list(row("default", cost))
  for (t in cost[["tiers"]] %||% list()) {
    size = t[["tier"]][["size"]]
    if (identical(t[["tier"]][["type"]], "context") && is.numeric(size)) {
      out[[length(out) + 1L]] = row(paste0(">", round(size / 1000), "k"), t)
    }
  }
  if (is.list(cost[["context_over_200k"]])) {
    out[[length(out) + 1L]] = row(">200k", cost[["context_over_200k"]])
  }
  out
}

#' A catalog entry from one models.dev model (NULL when pruned)
#'
#' Pruning (09 section 4.8): tool-capable, text output, not deprecated.
#' @noRd
catalog_entry_modelsdev = function(m, provider) {
  if (!is.list(m) || is.null(m[["id"]])) return(NULL)
  outputs = as.character(unlist(m[["modalities"]][["output"]]))
  status = catalog_status(m[["status"]])
  pruned = !isTRUE(m[["tool_call"]]) || identical(status, "deprecated") ||
    (length(outputs) && !"text" %in% outputs)
  if (pruned) return(NULL)
  input = intersect(c("text", "image", "pdf"), as.character(unlist(m[["modalities"]][["input"]])))
  canonical = m[["canonical_model_id"]]
  e = list(provider = provider, id = as.character(m[["id"]]),
           name = as.character(m[["name"]] %||% m[["id"]]), family = m[["family"]],
           release_date = catalog_date(m[["release_date"]]),
           context = m[["limit"]][["context"]], max_output = m[["limit"]][["output"]],
           reasoning = isTRUE(m[["reasoning"]]), thinking_levels = I(catalog_levels_from(m)),
           input = I(if (length(input)) input else "text"), tool_call = TRUE,
           structured_output = isTRUE(m[["structured_output"]]),
           prices = catalog_prices_from(m[["cost"]]), status = status,
           owner = if (is.null(canonical)) NULL else sub("/.*$", "", as.character(canonical)))
  Filter(Negate(is.null), e)
}

#' A catalog entry from one models.dev decision (System 1) model
#' @noRd
catalog_entry_decision = function(m) {
  ref = as.character(m[["id"]] %||% "")
  if (!grepl("/", ref, fixed = TRUE)) return(NULL)
  e = list(provider = sub("/.*$", "", ref), id = sub("^[^/]*/", "", ref),
           name = as.character(m[["name"]] %||% ref), family = m[["family"]],
           type = "classifier", release_date = catalog_date(m[["release_date"]]),
           context = m[["limit"]][["context"]], max_output = m[["limit"]][["output"]],
           reasoning = FALSE, thinking_levels = I("off"), input = I("text"), tool_call = FALSE,
           structured_output = isTRUE(m[["structured_output"]]),
           prices = catalog_prices_from(m[["cost"]]), status = catalog_status(m[["status"]]))
  Filter(Negate(is.null), e)
}

#' Catalog entries (named by ref) from models.dev `api.json` and the decision endpoint
#' @noRd
catalog_from_modelsdev = function(api, decision = NULL) {
  ids = catalog_modelsdev_ids()
  out = list()
  for (gid in names(ids)) {
    p = api[[ids[[gid]]]]
    if (!is.list(p)) next
    for (m in p[["models"]] %||% list()) {
      e = catalog_entry_modelsdev(m, gid)
      if (!is.null(e)) out[[paste0(gid, "/", e[["id"]])]] = e
    }
  }
  for (m in decision %||% list()) {
    e = catalog_entry_decision(m)
    if (!is.null(e)) out[[paste0(e[["provider"]], "/", e[["id"]])]] = e
  }
  out
}

#' Merge one entry into another (later fields win; capabilities merge by name)
#' @noRd
catalog_entry_merge = function(old, new) {
  for (k in names(new)) {
    if (identical(k, "capabilities") && is.list(old[[k]]) && is.list(new[[k]])) {
      old[[k]] = utils::modifyList(old[[k]], new[[k]])
    } else {
      old[k] = list(new[[k]])
    }
  }
  old
}

#' Merge a layer of entries into a named list of entries (keyed `provider/id`)
#'
#' With `patch_only = TRUE` (the overrides) an entry for an unknown ref is added only when it is
#' complete (has a `name`), so a correction never creates a half-described model.
#' @noRd
catalog_merge_models = function(base, layer, patch_only = FALSE) {
  for (e in layer %||% list()) {
    if (!is.list(e) || is.null(e[["provider"]]) || is.null(e[["id"]])) next
    ref = paste0(e[["provider"]], "/", e[["id"]])
    old = base[[ref]]
    if (is.null(old) && patch_only && is.null(e[["name"]])) next
    base[[ref]] = if (is.null(old)) e else catalog_entry_merge(old, e)
  }
  base
}

#' A snapshot (04 section 11.10): seed < models.dev < overrides, models sorted by ref
#' @noRd
catalog_snapshot = function(api = NULL, decision = NULL,
                            generated = format(Sys.Date(), "%Y-%m-%d")) {
  models = catalog_merge_models(list(), catalog_seed())
  if (!is.null(api)) models = catalog_merge_models(models, catalog_from_modelsdev(api, decision))
  ov = catalog_overrides()
  models = catalog_merge_models(models, ov[["models"]], patch_only = TRUE)
  models = models[order(names(models), method = "radix")]
  list(schema_version = 1L, generated = generated,
       source = if (is.null(api)) "gptr seed + overrides" else "models.dev (MIT) + gptr overrides",
       providers = catalog_providers_section(), models = unname(models),
       aliases = ov[["aliases"]])
}

#' Read a catalog file (gzip or plain JSON); NULL when absent or of another schema
#' @noRd
catalog_read = function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }
  con = gzfile(path, "rt")
  on.exit(close(con), add = TRUE)
  txt = readLines(con, encoding = "UTF-8", warn = FALSE)
  x = tryCatch(json_decode(paste(txt, collapse = "\n")), error = function(e) NULL)
  if (!is.list(x) || !identical(as.integer(x[["schema_version"]] %||% 0L), 1L)) return(NULL)
  x
}
```

Create `dev/catalog/build_models.R` (a maintainer tool; `dev/` is in `.Rbuildignore`, so nothing here runs on CRAN):

```r
# Builds inst/extdata/models.json.gz: models.dev (MIT) pruned to gptr's providers, gptr's seed
# entries for the models the specification names, and gptr's reviewed overrides (plan P05;
# contract section 11.10; report 09 section 4.8). A maintainer tool: dev/ is excluded from the
# package build and nothing here runs on CRAN.
#
# Run from the repository root:
#   Rscript --vanilla dev/catalog/build_models.R                  # download models.dev
#   Rscript --vanilla dev/catalog/build_models.R --api api.json [--decision decision.json]
#   Rscript --vanilla dev/catalog/build_models.R --offline        # seed + overrides only
args = commandArgs(trailingOnly = TRUE)
arg_value = function(flag) {
  i = match(flag, args)
  if (is.na(i) || i == length(args)) NULL else args[[i + 1L]]
}
read_json_file = function(path) {
  txt = readLines(path, encoding = "UTF-8", warn = FALSE)
  jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = FALSE)
}
fetch_json = function(url) {
  path = tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  curl::curl_download(url, path, quiet = TRUE, handle = curl::new_handle(followlocation = 0L))
  read_json_file(path)
}

pkgload::load_all(".", quiet = TRUE)
ns = asNamespace("gptr")
if ("--offline" %in% args) {
  api = NULL
  decision = NULL
} else if (!is.null(arg_value("--api"))) {
  api = read_json_file(arg_value("--api"))
  decision_path = arg_value("--decision")
  decision = if (is.null(decision_path)) NULL else read_json_file(decision_path)
} else {
  api = fetch_json(get("catalog_source_url", envir = ns))
  decision = tryCatch(fetch_json(get("catalog_decision_url", envir = ns)),
                      error = function(e) NULL)
}
snap = get("catalog_snapshot", envir = ns)(api, decision,
                                           generated = format(Sys.Date(), "%Y-%m-%d"))
text = get("json_encode", envir = ns)(snap)
out = file.path("inst", "extdata", "models.json.gz")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
con = gzfile(out, "wb", compression = 9)
writeLines(text, con, useBytes = TRUE)
close(con)
cat(sprintf("wrote %s: %d models, %d providers, %d aliases, %.1f KB (%s)\n", out,
            length(snap$models), length(snap$providers), length(snap$aliases),
            file.size(out) / 1024, snap$source))
```

Generate the snapshot (the download is models.dev's free public catalog, about 5 MB; no model is called):

Run: `Rscript --vanilla dev/catalog/build_models.R`
Expected (counts drift with models.dev; this line is from the 2026-09-29 `api.json`): `wrote inst/extdata/models.json.gz: 709 models, 18 providers, 9 aliases, 21.6 KB (models.dev (MIT) + gptr overrides)`

With an `api.json` downloaded earlier, `Rscript --vanilla dev/catalog/build_models.R --api api.json` builds the same snapshot without a download. Without network access, build the seed-only snapshot instead and rebuild online before the release:

Run: `Rscript --vanilla dev/catalog/build_models.R --offline`
Expected: `wrote inst/extdata/models.json.gz: 8 models, 18 providers, 9 aliases, 1.9 KB (gptr seed + overrides)`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 26 ]` (with either snapshot)

- [ ] **Step 5: Commit**

```bash
git add R/catalog-models.R dev/catalog/build_models.R inst/extdata/models.json.gz tests/testthat/test-catalog-models.R
git commit -m "feat(catalog): model catalog snapshot from models.dev, seed and overrides"
```

---

### Task 7: Merged catalog and the model resolver

**Files:**
- Modify: `R/catalog-models.R` (append)
- Test: `tests/testthat/test-catalog-models.R` (append)

**Interfaces:**
- Consumes: `registry_get()`, `registry_names()`, `registry_all(kind, session = NULL)` (P02; `gptr_spec()` and `gptr_register()` in the tests), `secret_lookup(name)`, `auth_store_get(key)` (P03), `setting_get()`, `check_string()`, `check_flag(x, arg, null = FALSE)`, `gptr_abort()` (P01), `fake_engine(model, opts = list())` and `fake_model_record(name, type, api, log)` (P01's `provider-fake.R`: the weak index of live fake engines by name that P01 keeps for exactly this lookup; not listed in 04), `provider_get()` (Task 2), `prices_df()` (Task 1), `provider_credential()` (Task 3, in the tests).
- Produces: `catalog_get()` -> the merged catalog (a list: `schema_version`, `generated`, `source`, `providers`, `models` named by `provider/id`, `aliases`, `small`, `index` (data frame `ref`, `provider`, `id`, `name`, `family`, `release_date`, `status`, `type`, `owner`, `norm`, `aliases`), `alias_targets`); `model_resolve(ref, strict = TRUE)` -> the model record of 04 section 4.9 (fields `ref`, `provider`, `id`, `name`, `family`, `api`, `type`, `release_date`, `context`, `max_output`, `reasoning`, `thinking_levels`, `thinking`, `input`, `tool_call`, `structured_output`, `prices`, `cache_min`, `max_images`, `capabilities` (`mid_system`, `tool_addition`, `images_in_results`, `operator_role`, `adaptive_thinking`, `effort`, `forced_tool_choice`), `aliases`, `status`, `local`) or `gptr_error_unknown_model` with `ref` and up to three `suggestions` (`NULL` with `strict = FALSE`); `catalog_aliases()` -> chr; private `catalog_reset(discovered = FALSE)`, `catalog_model_specs()`, `model_key_present(id, vars)` (also used by `model_default()` in Task 8), `model_provider_keyed(pid)`, `model_fake_entry(pid, id)`.

Merge order (04 section 11.10): the newer of the shipped snapshot and the refreshed cache < overrides < models declared by registered provider specs (`gptr_register(gptr_provider(..., models = ))`, INFRA-17) < registered `model` specs (`gptr_spec("model", "<provider>/<id>", ...)`, 04 section 10.2 row 3, whose display name is the spec's `label`) < user configuration `providers.<id>.models` < live discovery. The cached catalog is rebuilt only when one of those layers changes (registered provider and model specs, the `providers` setting, the cache file's mtime, discovered models). Resolution (report 09 section 5.5, verified; verification log rows 33-35): exact `provider/id`; a known provider prefix (ids and provider aliases) then exact id, normalised id (`.`/`_` -> `-`), an alias of that provider, family, substring; else exact id and normalised id across providers (a tie goes to the single candidate whose provider has a credential, then to the owner's own listing: row 34 corrected the report's summary, which had the order reversed), alias, family, substring. Only when nothing matches is the last `:suffix` peeled as a thinking level (Pi's rule); a local provider accepts unknown ids. A `fake/fake-1` reference whose provider is registered only for a session (`gptr(model = gptr_fake_provider(...))` registers it at rank 0, invisible without the session) resolves through P01's index of live fake engines. A family alias picks the newest non-deprecated model by `release_date` (an `active` one when there is one); on a date tie the undated id beats its `-YYYYMMDD` twin (models.dev lists both `claude-haiku-4-5` and `claude-haiku-4-5-20251001`, and only the undated id carries gptr's overrides). `model_resolve()` also accepts a `gptr_provider` spec (its first model), which is how a session-scoped `model = <spec>` resolves without a registry lookup.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-catalog-models.R` (helpers first, then the tests):

```r
fx_model = function(provider, id, family, date = NULL, levels = list("low", "medium", "high"),
                    owner = provider, ...) {
  c(list(provider = provider, id = id, name = id, family = family, release_date = date,
         context = 1e6, max_output = 64000, reasoning = TRUE, thinking_levels = levels,
         input = list("text", "image"), tool_call = TRUE, status = "active", owner = owner),
    list(...))
}

fx_models = function() {
  adaptive = list("low", "medium", "high", "xhigh", "max")
  list(
    fx_model("anthropic", "claude-sonnet-5-5", "claude-sonnet", "2026-09-28", adaptive),
    fx_model("anthropic", "claude-sonnet-5", "claude-sonnet", "2026-05-01", adaptive),
    fx_model("anthropic", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive),
    fx_model("anthropic", "claude-haiku-4-5", "claude-haiku", "2025-10-15",
             list("off", "minimal", "low", "medium", "high")),
    fx_model("anthropic", "claude-haiku-4-5-20251001", "claude-haiku", "2025-10-15",
             list("off", "minimal", "low", "medium", "high")),
    fx_model("azure", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive,
             owner = "anthropic"),
    fx_model("bedrock", "claude-opus-5-5", "claude-opus", "2026-09-22", adaptive,
             owner = "anthropic"),
    fx_model("openai", "gpt-6.1-sol", "gpt-sol", "2026-09-29", adaptive),
    fx_model("openai", "gpt-6-luna", "gpt-luna", "2026-09-22"),
    fx_model("openrouter", "anthropic/claude-sonnet-5.5", "claude-sonnet", "2026-09-28",
             owner = "anthropic"),
    list(provider = "typesafe", id = "jev-latest", name = "Jev", type = "classifier",
         reasoning = FALSE, tool_call = FALSE, status = "active")
  )
}

# Settings come from P08's layers later; tests pin them by mocking the one reader.
local_settings = function(..., .env = parent.frame()) {
  values = list(...)
  testthat::local_mocked_bindings(
    setting_get = function(key, session = NULL, default = NULL) {
      if (key %in% names(values)) values[[key]] else default
    },
    .env = .env
  )
}

local_catalog = function(models = fx_models(), .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  path = file.path(dir, "models.json")
  snap = list(schema_version = 1L, generated = "2026-09-30", source = "test fixture",
              providers = list(), models = models, aliases = list())
  writeLines(json_encode(snap), path, useBytes = TRUE)
  testthat::local_mocked_bindings(
    catalog_snapshot_path = function() path,
    catalog_cache_path = function() file.path(dir, "cache-models.json"),
    catalog_etag_path = function() file.path(dir, "cache-models.etag"),
    .env = .env
  )
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE), envir = .env)
  invisible(dir)
}

test_that("references resolve: exact, alias, family, normalised, owner, thinking", {
  local_catalog()
  expect_equal(model_resolve("anthropic/claude-sonnet-5-5")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("sonnet")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-sonnet")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-sonnet-5.5")$ref, "anthropic/claude-sonnet-5-5")
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  expect_equal(model_resolve("openrouter/anthropic/claude-sonnet-5-5")$ref,
               "openrouter/anthropic/claude-sonnet-5.5")
  expect_equal(model_resolve("gpt")$ref, "openai/gpt-6.1-sol")
  opus = model_resolve("opus:xhigh")
  expect_equal(opus$ref, "anthropic/claude-opus-5-5")
  expect_equal(opus$thinking, "xhigh")
  expect_equal(model_resolve("opus:minimal")$thinking, "low")
  expect_equal(model_resolve("haiku:max")$thinking, "high")
  expect_equal(model_resolve("haiku")$ref, "anthropic/claude-haiku-4-5")
  expect_null(model_resolve("sonnet")$thinking)
  jev = model_resolve("jev")
  expect_equal(jev$type, "classifier")
  expect_equal(jev$api, "typesafe-system-one")
})

test_that("a model record has every contract field (04 section 4.9)", {
  local_catalog()
  r = model_resolve("sonnet")
  expect_named(r, c("ref", "provider", "id", "name", "family", "api", "type", "release_date",
                    "context", "max_output", "reasoning", "thinking_levels", "thinking",
                    "input", "tool_call", "structured_output", "prices", "cache_min",
                    "max_images", "capabilities", "aliases", "status", "local"))
  expect_equal(r$api, "anthropic-messages")
  expect_equal(r$aliases, "sonnet")
  expect_s3_class(r$prices, "data.frame")
  expect_named(r$prices, c("from", "tier", "input", "output", "cache_read", "cache_write_5m",
                           "cache_write_1h"))
  expect_equal(r$cache_min, 512)
  expect_equal(r$max_images, 600)
  expect_named(r$capabilities, c("mid_system", "tool_addition", "images_in_results",
                                 "operator_role", "adaptive_thinking", "effort",
                                 "forced_tool_choice"))
  expect_false(r$capabilities$forced_tool_choice)
  expect_true(model_resolve("openai/gpt-6.1-sol")$capabilities$forced_tool_choice)
  expect_equal(r$thinking_levels, c("off", "low", "medium", "high", "xhigh", "max"))
  expect_equal(model_resolve("sonnet:off")$thinking, "off")
  expect_equal(model_resolve("opus:off")$thinking, "low")
})

test_that("unknown references fail with suggestions, or NULL when not strict", {
  local_catalog()
  err = expect_error(model_resolve("claude-sonet-5-5"), class = "gptr_error_unknown_model")
  expect_true("claude-sonnet-5-5" %in% err$suggestions)
  expect_equal(err$ref, "claude-sonet-5-5")
  expect_null(model_resolve("sonnet:turbo", strict = FALSE))
  expect_error(model_resolve("anthropic/claude-nope"), class = "gptr_error_unknown_model")
  expect_error(model_resolve(42), class = "gptr_error_invalid_argument")
  skip_if_not(is.null(provider_get("claude-cli")), "builtin:cli (P20) registers claude-cli")
  expect_error(model_resolve("claude_code"), "claude-cli", class = "gptr_error_unknown_model")
})

test_that("local providers accept unknown ids; a provider added by data resolves (INFRA-17)", {
  local_catalog()
  qwen = model_resolve("ollama/qwen3.5:9b:high")
  expect_equal(qwen$id, "qwen3.5:9b")
  expect_equal(qwen$thinking, "high")
  llama = model_resolve("ollama/llama3.2:3b")
  expect_equal(llama$id, "llama3.2:3b")
  expect_null(llama$thinking)
  expect_true(llama$local)
  expect_equal(llama$api, "openai-completions")
  off = gptr_register(gptr_provider("labserver", api = "openai-completions",
                                    base_url = "http://127.0.0.1:9999/v1", local = TRUE,
                                    models = list(list(id = "qwen-lab", context = 32768))))
  withr::defer(off())
  lab = model_resolve("labserver/qwen-lab")
  expect_equal(lab$context, 32768)
  expect_equal(lab$api, "openai-completions")
  expect_true(lab$local)
  expect_null(provider_credential(provider_get("labserver")))
  spec = gptr_fake_provider(list("hi"), name = "specfake")
  expect_equal(model_resolve(spec)$ref, "specfake/specfake-1")
})

test_that("user configuration is a merge layer above the snapshot", {
  local_catalog()
  local_settings(providers = list(anthropic = list(models = list(
    list(id = "claude-sonnet-5-5", context = 2e6)
  ))))
  expect_equal(model_resolve("sonnet")$context, 2e6)
  expect_equal(model_resolve("sonnet")$prices$input[[1]], 2)
})

test_that("a bare id of several providers goes to the one with a credential, then the owner", {
  local_catalog()
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  local_mocked_bindings(model_key_present = function(id, vars) identical(id, "azure"))
  expect_equal(model_resolve("claude-opus-5-5")$ref, "azure/claude-opus-5-5")
  local_mocked_bindings(model_key_present = function(id, vars) id %in% c("azure", "anthropic"))
  expect_equal(model_resolve("claude-opus-5-5")$ref, "anthropic/claude-opus-5-5")
  # two credentialed resellers and an owner without a key: ambiguous, never the keyless owner
  local_mocked_bindings(model_key_present = function(id, vars) id %in% c("azure", "bedrock"))
  err = expect_error(model_resolve("claude-opus-5-5"), class = "gptr_error_unknown_model")
  expect_setequal(err$suggestions, c("azure/claude-opus-5-5", "bedrock/claude-opus-5-5"))
  expect_match(conditionMessage(err), "several providers", fixed = TRUE)
})

test_that("a model registered as a `model` spec joins the catalog (04 section 10.2 row 3)", {
  local_catalog()
  off = gptr_register(gptr_spec("model", "anthropic/claude-lab-1", label = "Claude Lab 1",
                                family = "claude-lab", context = 4096, status = "preview"))
  withr::defer(off())
  m = model_resolve("anthropic/claude-lab-1")
  expect_equal(m$name, "Claude Lab 1")
  expect_equal(m$context, 4096)
  expect_equal(m$api, "anthropic-messages")
  expect_equal(m$status, "preview")
})

test_that("a fake provider used only as a session's spec still resolves by reference", {
  local_catalog()
  fake = gptr_fake_provider(list("hi"), name = "p05fake")
  m = model_resolve("p05fake/p05fake-1")
  expect_equal(m$ref, "p05fake/p05fake-1")
  expect_equal(m$api, "fake")
  expect_true(m$local)
  expect_null(m$fake)
  expect_equal(model_resolve("p05fake/p05fake-1:high")$thinking, "high")
  expect_null(model_resolve("p05fake/other", strict = FALSE))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 26 ]`, with ``could not find function "catalog_reset"``.

- [ ] **Step 3: Write the implementation**

Append to `R/catalog-models.R`:

```r
#' The newer of the shipped snapshot and the refreshed cache
#' @noRd
catalog_read_base = function() {
  snap = catalog_read(catalog_snapshot_path())
  cache = catalog_read(catalog_cache_path())
  if (is.null(cache)) {
    return(snap %||% list(schema_version = 1L, generated = NA_character_, source = "none",
                          providers = list(), models = list(), aliases = list()))
  }
  if (is.null(snap)) return(cache)
  newer = as.character(cache[["generated"]] %||% "") >= as.character(snap[["generated"]] %||% "")
  if (newer) cache else snap
}

#' Model entries declared by a provider spec, with the provider id filled in
#' @noRd
catalog_spec_models = function(p) {
  if (is.null(p)) return(list())
  lapply(p[["models"]] %||% list(), function(m) {
    m[["id"]] = m[["id"]] %||% sub("^[^/]*/", "", m[["ref"]] %||% "")
    m[["provider"]] = p[["id"]] %||% p[["name"]]
    m[["ref"]] = NULL
    m
  })
}

#' Model entries registered as `model` specs (04 section 10.2 row 3; name `provider/id`)
#'
#' A spec's `name` is its registry key, so the display name comes from `label` (else the id);
#' the spec bookkeeping fields are dropped.
#' @noRd
catalog_model_specs = function() {
  specs = tryCatch(registry_all("model"), error = function(e) list())
  lapply(unname(specs), function(s) {
    e = unclass(s)
    e[["name"]] = e[["label"]] %||% e[["id"]]
    e[c("kind", "label", "api_version", "ref")] = NULL
    e
  })
}

#' Normalised model id for matching ("claude-sonnet-5.5" equals "claude-sonnet-5-5")
#' @noRd
catalog_norm_id = function(x) gsub("[._]", "-", tolower(x))

#' The lookup index of a named list of entries
#' @noRd
catalog_index = function(models) {
  f = function(k, d = NA_character_) {
    vapply(models, function(m) {
      v = m[[k]]
      if (is.null(v) || !length(v) || is.na(v[[1]])) d else as.character(v[[1]])
    }, "", USE.NAMES = FALSE)
  }
  idx = data.frame(ref = names(models) %||% character(), provider = f("provider"),
                   id = f("id"), name = f("name"), family = f("family"),
                   release_date = f("release_date"), status = f("status", "active"),
                   type = f("type", "chat"), owner = f("owner"), stringsAsFactors = FALSE)
  idx$name = ifelse(is.na(idx$name), idx$id, idx$name)
  idx$norm = catalog_norm_id(idx$id)
  idx
}

#' The ref an alias resolves to now (newest active model; the owner's listing preferred when
#' no provider is given; on a release-date tie the undated id wins over its `-YYYYMMDD` twin)
#' @noRd
catalog_alias_target = function(a, idx) {
  if (!is.null(a[["ref"]])) return(as.character(a[["ref"]]))
  ok = idx$status != "deprecated"
  if (!is.null(a[["provider"]])) ok = ok & idx$provider == a[["provider"]]
  if (!is.null(a[["id"]])) ok = ok & idx$id == a[["id"]]
  if (!is.null(a[["family"]])) ok = ok & !is.na(idx$family) & idx$family == a[["family"]]
  if (!is.null(a[["pattern"]])) ok = ok & grepl(a[["pattern"]], idx$id)
  cand = idx[ok, , drop = FALSE]
  if (!nrow(cand)) return(NA_character_)
  act = cand[cand$status == "active", , drop = FALSE]
  if (nrow(act)) cand = act
  if (is.null(a[["provider"]])) {
    own = cand[!is.na(cand$owner) & cand$provider == cand$owner, , drop = FALSE]
    if (nrow(own)) cand = own
  }
  dated = grepl("-[0-9]{8}$", cand$id)
  cand = cand[order(cand$release_date, dated, cand$id, decreasing = c(TRUE, FALSE, TRUE),
                    method = "radix"), , drop = FALSE]
  cand$ref[[1]]
}

#' Alias name -> target ref (NA when an alias resolves to nothing)
#' @noRd
catalog_alias_targets = function(aliases, idx) {
  if (!length(aliases)) return(character())
  vapply(aliases, catalog_alias_target, "", idx = idx)
}

#' Build the merged catalog: base < overrides < provider specs < model specs < user config <
#' discovery
#' @noRd
catalog_build = function() {
  base = catalog_read_base()
  ov = catalog_overrides()
  models = catalog_merge_models(list(), base[["models"]])
  models = catalog_merge_models(models, ov[["models"]], patch_only = TRUE)
  for (nm in sort(registry_names("provider"))) {
    models = catalog_merge_models(models, catalog_spec_models(registry_get("provider", nm)))
  }
  models = catalog_merge_models(models, catalog_model_specs())
  cfg = setting_get("providers", default = list()) %||% list()
  for (pid in names(cfg)) {
    layer = lapply(cfg[[pid]][["models"]] %||% list(), function(m) {
      m[["provider"]] = pid
      m
    })
    models = catalog_merge_models(models, layer)
  }
  disc = the$catalog[["discovered"]] %||% list()
  for (pid in names(disc)) models = catalog_merge_models(models, disc[[pid]])
  aliases = base[["aliases"]] %||% list()
  for (nm in names(ov[["aliases"]])) aliases[[nm]] = ov[["aliases"]][[nm]]
  ctg = list(schema_version = 1L, generated = base[["generated"]] %||% NA_character_,
             source = base[["source"]] %||% "none",
             providers = utils::modifyList(base[["providers"]] %||% list(),
                                           ov[["providers"]] %||% list()),
             models = models, aliases = aliases, small = ov[["small"]])
  ctg$index = catalog_index(models)
  ctg$alias_targets = catalog_alias_targets(ctg$aliases, ctg$index)
  targets = ctg$alias_targets
  ctg$index$aliases = vapply(ctg$index$ref, function(r) {
    paste(names(targets)[!is.na(targets) & targets == r], collapse = ",")
  }, "", USE.NAMES = FALSE)
  ctg
}

#' What the cached catalog depends on (registered providers and model specs, user config, cache
#' file, discovery)
#' @noRd
catalog_key = function() {
  specs = lapply(sort(registry_names("provider")), function(nm) {
    p = registry_get("provider", nm)
    list(nm, p[["models"]], p[["api"]], p[["local"]])
  })
  list(specs = specs, models = tryCatch(registry_all("model"), error = function(e) list()),
       config = setting_get("providers", default = NULL),
       cache = file.info(catalog_cache_path())[["mtime"]],
       discovered = the$catalog[["discovered"]])
}

#' The merged catalog (04 section 11.10), rebuilt only when a layer changed
#' @noRd
catalog_get = function() {
  key = catalog_key()
  st = the$catalog
  if (is.list(st) && identical(st[["key"]], key) && !is.null(st[["value"]])) {
    return(st[["value"]])
  }
  value = catalog_build()
  the$catalog = list(key = key, value = value, discovered = st[["discovered"]])
  value
}

#' Forget the merged catalog (and, with `discovered = TRUE`, live-discovered local models)
#' @noRd
catalog_reset = function(discovered = FALSE) {
  st = the$catalog
  the$catalog = if (discovered) NULL else list(discovered = st[["discovered"]])
  invisible(NULL)
}

#' Canonical provider id for a reference prefix (provider ids and provider aliases)
#' @noRd
model_provider_id = function(prefix, ctg) {
  lp = tolower(prefix)
  known = unique(c(ctg$index$provider, names(ctg$providers), registry_names("provider")))
  if (lp %in% known) return(lp)
  for (nm in registry_names("provider")) {
    if (lp %in% tolower(registry_get("provider", nm)[["aliases"]] %||% character())) return(nm)
  }
  NA_character_
}

#' An entry for an alias target ref (a registered provider may serve an uncatalogued id)
#' @noRd
model_alias_entry = function(target, ctg) {
  if (is.na(target)) return(NULL)
  e = ctg$models[[target]]
  if (!is.null(e)) return(e)
  pv = sub("/.*$", "", target)
  if (is.null(provider_get(pv))) return(NULL)
  list(provider = pv, id = sub("^[^/]*/", "", target))
}

#' Is a credential for these variables (or this provider's store entry) present?
#'
#' Checks only: the environment, the vault and the credential store; never registers a value.
#' @noRd
model_key_present = function(id, vars) {
  if (any(nzchar(Sys.getenv(vars, unset = "")))) return(TRUE)
  if (any(vapply(vars, function(v) !is.null(secret_lookup(v)), NA))) return(TRUE)
  rec = tryCatch(auth_store_get(id), error = function(e) NULL)
  !is.null(rec)
}

#' Does a provider with key variables have a credential now?
#' @noRd
model_provider_keyed = function(pid) {
  p = provider_get(pid)
  vars = p[["auth"]]
  if (!is.character(vars) || !length(vars)) return(FALSE)
  isTRUE(tryCatch(model_key_present(pid, vars), error = function(e) FALSE))
}

#' Pick one row among several candidates: the single provider with a credential, else the
#' owner's own listing among the credentialed ones (among all when none has a credential), else
#' ambiguous (report 09 break_tie(), verification log row 34)
#' @noRd
model_pick = function(w, ctg, how) {
  idx = ctg$index
  if (length(w) == 1L) return(list(entry = ctg$models[[w]], how = how))
  keyed = w[vapply(idx$provider[w], model_provider_keyed, NA, USE.NAMES = FALSE)]
  if (length(keyed) == 1L) {
    return(list(entry = ctg$models[[keyed]], how = paste0(how, " (credential)")))
  }
  if (length(keyed) > 1L) w = keyed
  own = w[!is.na(idx$owner[w]) & idx$provider[w] == idx$owner[w]]
  if (length(own) == 1L) return(list(entry = ctg$models[[own]], how = paste0(how, " (owner)")))
  list(entry = NULL, how = "ambiguous", candidates = idx$ref[w])
}

#' Match by exact then normalised id within the selected rows
#' @noRd
model_match_id = function(pat, ctg, sel) {
  idx = ctg$index
  w = which(sel & tolower(idx$id) == tolower(pat))
  if (length(w)) return(model_pick(w, ctg, "exact id"))
  w = which(sel & idx$norm == catalog_norm_id(pat))
  if (length(w)) return(model_pick(w, ctg, "normalised id"))
  NULL
}

#' Match by family (newest active, owner preferred) then substring within the selected rows
#' @noRd
model_match_fuzzy = function(pat, ctg, sel) {
  idx = ctg$index
  lp = tolower(pat)
  fam = sel & !is.na(idx$family) & tolower(idx$family) == lp & idx$status != "deprecated"
  if (any(fam)) {
    target = catalog_alias_target(list(family = idx$family[which(fam)[1]]),
                                  idx[sel, , drop = FALSE])
    if (!is.na(target)) return(list(entry = ctg$models[[target]], how = "family"))
  }
  if (nchar(lp) >= 3L) {
    part = which(sel & (grepl(lp, tolower(idx$id), fixed = TRUE) |
                          grepl(lp, tolower(idx$name), fixed = TRUE)))
    if (length(part)) {
      own = part[!is.na(idx$owner[part]) & idx$provider[part] == idx$owner[part]]
      if (length(own)) part = own
      pref = part[!grepl("-[0-9]{8}$", idx$id[part])]
      pool = if (length(pref)) pref else part
      ord = order(idx$release_date[pool], idx$id[pool], decreasing = TRUE, method = "radix")
      return(list(entry = ctg$models[[pool[ord][1]]], how = "substring"))
    }
  }
  NULL
}

#' The model entry of a live fake provider (P01) that no registry record shows
#'
#' gptr(model = gptr_fake_provider(...)) registers the spec at rank 0 for its session only
#' (04 section 10.1), and model_resolve() has no session argument, so P06 resolving the
#' session's "fake/fake-1" would miss it. P01 keeps a weak index of live fake engines by name
#' (`fake_engine()`); the record is P01's `fake_model_record()` without its `fake` engine field,
#' so provider_stream() picks the session's own spec through `opts$provider`.
#' @noRd
model_fake_entry = function(pid, id) {
  engine = tryCatch(fake_engine(list(provider = pid)), error = function(e) NULL)
  if (!is.environment(engine)) return(NULL)
  type = if (identical(id, paste0(pid, "-1"))) {
    "chat"
  } else if (identical(id, paste0(pid, "-s1"))) {
    "classifier"
  } else {
    return(NULL)
  }
  api = if (identical(type, "chat")) "fake" else "fake-classifier"
  e = fake_model_record(pid, type, api, engine)
  e[["fake"]] = NULL
  e
}

#' Resolve a reference without its thinking suffix (report 09 match_pattern())
#' @noRd
model_match = function(pat, ctg) {
  idx = ctg$index
  lp = tolower(pat)
  w = which(tolower(idx$ref) == lp)
  if (length(w) == 1L) return(list(entry = ctg$models[[w]], how = "exact provider/id"))
  targets = ctg$alias_targets
  alias = if (length(targets)) targets[match(lp, tolower(names(targets)))] else NA_character_
  sl = regexpr("/", pat, fixed = TRUE)
  if (sl > 0L) {
    pv = model_provider_id(substr(pat, 1L, sl - 1L), ctg)
    if (is.na(pv)) {
      fe = model_fake_entry(substr(pat, 1L, sl - 1L), substring(pat, sl + 1L))
      if (!is.null(fe)) return(list(entry = fe, how = "live fake provider"))
    }
    if (!is.na(pv)) {
      rest = substring(pat, sl + 1L)
      sel = idx$provider == pv
      r = model_match_id(rest, ctg, sel)
      if (!is.null(r)) return(r)
      sub_alias = if (length(targets)) {
        targets[match(tolower(rest), tolower(names(targets)))]
      } else {
        NA_character_
      }
      if (!is.na(sub_alias) && startsWith(sub_alias, paste0(pv, "/"))) {
        e = model_alias_entry(sub_alias, ctg)
        if (!is.null(e)) return(list(entry = e, how = "alias"))
      }
      r = model_match_fuzzy(rest, ctg, sel)
      if (!is.null(r)) return(r)
      return(list(entry = NULL, how = "unknown id for known provider", provider = pv, id = rest))
    }
  }
  every = rep(TRUE, nrow(idx))
  r = model_match_id(pat, ctg, every)
  if (!is.null(r)) return(r)
  e = model_alias_entry(alias, ctg)
  if (!is.null(e)) return(list(entry = e, how = "alias"))
  r = model_match_fuzzy(pat, ctg, every)
  if (!is.null(r)) return(r)
  list(entry = NULL, how = "no match")
}

#' Is a provider local (loopback server: unknown model ids allowed)?
#' @noRd
model_provider_local = function(pid, ctg) {
  p = provider_get(pid)
  isTRUE(p[["local"]] %||% ctg$providers[[pid]][["local"]])
}

#' Resolve a reference with Pi's last-colon thinking rule and local-provider fallback
#' @noRd
model_lookup = function(text, ctg) {
  hit = model_match(text, ctg)
  if (!is.null(hit$entry)) return(hit)
  thinking = NULL
  pos = regexpr(":[^:]*$", text)
  if (pos > 0L) {
    suffix = substring(text, pos + 1L)
    if (suffix %in% catalog_thinking_levels) {
      hit2 = model_match(substr(text, 1L, pos - 1L), ctg)
      if (!is.null(hit2$entry)) {
        hit2$thinking = suffix
        return(hit2)
      }
      if (!is.null(hit2$provider)) {
        hit = hit2
        thinking = suffix
      }
    }
  }
  if (!is.null(hit$provider) && model_provider_local(hit$provider, ctg)) {
    entry = list(provider = hit$provider, id = hit$id, status = "active",
                 reasoning = !is.null(thinking))
    return(list(entry = entry, how = "local id", thinking = thinking))
  }
  hit
}

#' Up to three suggestions for an unresolved reference (utils::adist(), report 09)
#' @noRd
model_suggestions = function(text, ctg, candidates = NULL) {
  if (length(candidates)) return(utils::head(candidates, 3L))
  known = unique(c(ctg$index$ref, ctg$index$id, names(ctg$aliases)))
  if (!length(known)) return(character())
  d = utils::adist(tolower(sub(":.*$", "", text)), tolower(known))[1, ]
  known[order(d, known, method = "radix")][seq_len(min(3L, length(known)))]
}

#' Clamp a requested thinking level to the supported ones: upwards first, then downwards
#' @noRd
model_clamp_thinking = function(levels, level) {
  first = if (length(levels)) levels[[1]] else "off"
  if (level %in% levels) return(level)
  i = match(level, catalog_thinking_levels)
  if (is.na(i)) return(first)
  up = catalog_thinking_levels[i:length(catalog_thinking_levels)]
  hit = up[up %in% levels]
  if (length(hit)) return(hit[[1]])
  down = rev(catalog_thinking_levels[seq_len(i - 1L)])
  hit = down[down %in% levels]
  if (length(hit)) return(hit[[1]])
  first
}

#' A length-1 number or NA
#' @noRd
catalog_num = function(x) {
  if (is.null(x) || !length(x)) return(NA_real_)
  suppressWarnings(as.numeric(x[[1]]))
}

#' Model capabilities (contract section 4.9 plus forced_tool_choice, IC-71)
#' @noRd
model_capabilities = function(e, pinfo) {
  caps = list(mid_system = FALSE, tool_addition = FALSE, images_in_results = FALSE,
              operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE,
              forced_tool_choice = TRUE)
  caps = utils::modifyList(caps, pinfo[["capabilities"]] %||% list())
  caps = utils::modifyList(caps, e[["capabilities"]] %||% list())
  lapply(caps, isTRUE)
}

#' The model record (contract section 4.9) of a catalog entry
#' @noRd
model_record = function(e, ctg, provider = NULL) {
  pid = as.character(e[["provider"]])
  p = provider %||% provider_get(pid)
  info = ctg$providers[[pid]] %||% list()
  reasoning = isTRUE(e[["reasoning"]])
  levels = as.character(unlist(e[["thinking_levels"]]))
  if (!length(levels)) {
    levels = if (reasoning) c("off", "minimal", "low", "medium", "high") else "off"
  }
  type = as.character(e[["type"]] %||% p[["type"]] %||% "chat")
  id = as.character(e[["id"]])
  ref = paste0(pid, "/", id)
  targets = ctg$alias_targets %||% character()
  list(ref = ref, provider = pid, id = id, name = as.character(e[["name"]] %||% id),
       family = as.character(e[["family"]] %||% NA_character_),
       api = as.character(e[["api"]] %||% p[["api"]] %||% info[["api"]] %||% NA_character_),
       type = type, release_date = as.character(e[["release_date"]] %||% NA_character_),
       context = catalog_num(e[["context"]]), max_output = catalog_num(e[["max_output"]]),
       reasoning = reasoning, thinking_levels = levels, thinking = NULL,
       input = as.character(unlist(e[["input"]] %||% "text")),
       tool_call = isTRUE(e[["tool_call"]] %||% identical(type, "chat")),
       structured_output = isTRUE(e[["structured_output"]]), prices = prices_df(e[["prices"]]),
       cache_min = catalog_num(e[["cache_min"]]), max_images = catalog_num(e[["max_images"]]),
       capabilities = model_capabilities(e, info),
       aliases = names(targets)[!is.na(targets) & targets == ref],
       status = as.character(e[["status"]] %||% "active"),
       local = isTRUE(p[["local"]] %||% info[["local"]] %||% e[["local"]]))
}

#' Resolve a model reference to a model record (contract sections 4.9 and 7.5)
#'
#' `ref` is `provider/id[:thinking]`, an alias (dynamic by family and release date), a
#' provider-less id, or a `gptr_provider` spec (its first model; used for `model = <spec>`).
#' @noRd
model_resolve = function(ref, strict = TRUE) {
  check_flag(strict, "strict")
  ctg = catalog_get()
  if (inherits(ref, "gptr_provider")) {
    models = catalog_spec_models(ref)
    if (!length(models)) {
      gptr_abort(paste0("Provider ", ref[["id"]] %||% "", " declares no models."),
                 "unknown_model", ref = ref[["id"]] %||% "", suggestions = character())
    }
    return(model_record(models[[1]], ctg, provider = ref))
  }
  check_string(ref, "ref")
  hit = model_lookup(ref, ctg)
  if (is.null(hit$entry)) {
    if (!strict) return(NULL)
    targets = ctg$alias_targets
    target = if (length(targets)) targets[match(tolower(ref), tolower(names(targets)))] else NA
    if (!is.na(target)) {
      gptr_abort(paste0("The model alias '", ref, "' points to ", target, ", but its provider ",
                        sub("/.*$", "", target), " is not registered."),
                 "unknown_model", ref = ref, suggestions = character())
    }
    sugg = model_suggestions(ref, ctg, hit$candidates)
    lead = if (identical(hit$how, "ambiguous")) {
      paste0("The model reference '", ref, "' is listed by several providers; name one as ",
             "provider/id.")
    } else {
      paste0("Unknown model reference '", ref, "'.")
    }
    gptr_abort(paste0(lead, if (length(sugg)) paste0(" Did you mean: ",
                                                     paste(sugg, collapse = ", "), "?") else ""),
               "unknown_model", ref = ref, suggestions = sugg)
  }
  rec = model_record(hit$entry, ctg)
  if (!is.null(hit$thinking)) rec$thinking = model_clamp_thinking(rec$thinking_levels, hit$thinking)
  rec
}

#' Alias names of the merged catalog (for identifier_known(), P08)
#' @noRd
catalog_aliases = function() names(catalog_get()$aliases) %||% character()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 90 ]`

- [ ] **Step 5: Commit**

```bash
git add R/catalog-models.R tests/testthat/test-catalog-models.R
git commit -m "feat(catalog): merged catalog and model resolver"
```

---

### Task 8: gptr_models(), defaults, explicit refresh and local discovery

**Files:**
- Modify: `R/catalog-models.R` (append)
- Modify: `NAMESPACE`, `man/gptr_models.Rd` (generated)
- Test: `tests/testthat/test-catalog-models.R` (append)

**Interfaces:**
- Consumes: `reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL, retry = NULL)`, `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_cancel(ids)` (P04, 04 section 8.2); `write_atomic(path, content)`, `gptr_user_dir(..., create = TRUE)`, `new_listing(df, class, footer = NULL)`, `check_choice(x, choices, arg)`, `raw_to_utf8()` (P01); `model_key_present()` (Task 7), `provider_settings()` (Task 2).
- Produces: the export `gptr_models(query = NULL, provider = NULL, refresh = FALSE)` -> `c("gptr_models", "gptr_listing", "data.frame")` with columns `ref`, `provider`, `name`, `context`, `max_output`, `input_price`, `output_price`, `reasoning`, `aliases`, `status` (04 sections 5.12, 6.2); `model_default(role = c("chat", "small", "system1"))` -> chr(1) or `NULL` (04 section 7.5); private `catalog_http_get(url, headers = list(), timeout = 30)` -> `list(status, headers, body)` (one GET on the reactor; P04 sets `followlocation = 0L`, IC-64), `catalog_refresh()` -> `TRUE` (written) or `FALSE` (304), `model_route_ready(id, vars)`, `model_cli_available(id)`.

`refresh = TRUE` is the only network use of `gptr_models()`: a conditional GET of `https://models.dev/api.json` with the stored ETag (304 keeps the cache), converted with Task 6's `catalog_snapshot()` and written atomically to `R_user_dir("gptr", "cache")`; with `provider = <a local provider>` it asks that loopback server for its models instead (1 s timeout, never under `R CMD check`). `model_default()` never registers or materialises a key: it only checks whether one exists (environment, vault, store; `model_key_present()` of Task 7), and it skips a provider whose `providers.<id>.enabled` setting is `false`. A subscription CLI counts as available when its provider's `status()` (called with `check = FALSE` when it has that formal, so it reads cached data only) returns `available = TRUE` (P20 contract).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-catalog-models.R`:

```r
test_that("discovered local models join the catalog only on request", {
  local_catalog()
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_get = function(url, headers = list(), timeout = 30) {
      expect_equal(url, "http://localhost:11434/v1/models")
      expect_equal(timeout, 1)
      list(status = 200L, headers = list(),
           body = charToRaw('{"data":[{"id":"llama3.2:3b"},{"id":"qwen3.5:9b"}]}'))
    }
  )
  expect_equal(nrow(gptr_models(provider = "ollama")), 0L)
  found = gptr_models(provider = "ollama", refresh = TRUE)
  expect_setequal(found$ref, c("ollama/llama3.2:3b", "ollama/qwen3.5:9b"))
})

test_that("gptr_models() searches the catalog and lists prices in force", {
  local_catalog()
  df = gptr_models("sonnet")
  expect_s3_class(df, "gptr_models")
  expect_named(df, c("ref", "provider", "name", "context", "max_output", "input_price",
                     "output_price", "reasoning", "aliases", "status"))
  expect_equal(df$ref[[1]], "anthropic/claude-sonnet-5-5")
  expect_equal(df$input_price[[1]], 2)
  expect_equal(df$aliases[[1]], "sonnet")
  claude = gptr_models("claude", provider = "anthropic")
  expect_true(all(claude$provider == "anthropic"))
  expect_true(nrow(claude) >= 4L)
  expect_equal(nrow(gptr_models("[unclosed")), 0L)
  expect_error(gptr_models(query = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_models(refresh = NA), class = "gptr_error_invalid_argument")
})

test_that("model_default() follows the settings, then the first available key", {
  local_catalog()
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL,
                        model_cli_available = function(id) FALSE)
  withr::local_envvar(ANTHROPIC_API_KEY = "", OPENAI_API_KEY = "", GEMINI_API_KEY = "",
                      GOOGLE_API_KEY = "", TYPESAFE_API_KEY = "")
  expect_null(model_default("chat"))
  expect_null(model_default("system1"))
  withr::local_envvar(OPENAI_API_KEY = "sk-test-openai-000000000000")
  expect_equal(model_default("chat"), "openai/gpt-6-sol")
  expect_equal(model_default("small"), "openai/gpt-6-luna")
  withr::local_envvar(TYPESAFE_API_KEY = "ts-test-000000000000")
  expect_equal(model_default("system1"), "typesafe/jev-latest")
  local_settings(model = "sonnet")
  expect_equal(model_default("chat"), "sonnet")
  expect_equal(model_default("small"), "anthropic/claude-haiku-4-5")
  expect_true(all(c("sonnet", "jev", "claude_code") %in% catalog_aliases()))
})

test_that("model_default() skips providers disabled in the settings", {
  local_catalog()
  local_mocked_bindings(model_cli_available = function(id) FALSE,
                        model_key_present = function(id, vars) id %in% c("anthropic", "openai"))
  expect_equal(model_default("chat"), "anthropic/claude-sonnet-5-5")
  local_settings(providers = list(anthropic = list(enabled = FALSE)))
  expect_equal(model_default("chat"), "openai/gpt-6-sol")
})

test_that("a detected subscription CLI is the last default route", {
  local_catalog()
  local_mocked_bindings(model_key_present = function(id, vars) FALSE)
  off = gptr_register(gptr_provider("claude-cli", api = "cli-claude", type = "cli",
                                    status = function(check) {
                                      list(available = identical(check, FALSE))
                                    }))
  withr::defer(off())
  expect_true(model_cli_available("claude-cli"))
  expect_equal(model_default("chat"), "claude-cli/default")
  expect_false(model_cli_available("no-such-cli"))
})

test_that("an explicit refresh revalidates with the ETag and caches in R_user_dir", {
  dir = local_catalog()
  api = list(anthropic = list(id = "anthropic", models = list(`claude-sonnet-6` = list(
    id = "claude-sonnet-6", name = "Claude Sonnet 6", family = "claude-sonnet", reasoning = TRUE,
    tool_call = TRUE, release_date = "2026-12-01", limit = list(context = 1e6, output = 128000),
    modalities = list(input = list("text"), output = list("text")),
    cost = list(input = 2, output = 10)
  ))))
  seen = new.env()
  seen$headers = list()
  local_mocked_bindings(catalog_http_get = function(url, headers = list(), timeout = 30) {
    if (!identical(url, catalog_source_url)) return(list(status = 404L, headers = list(),
                                                         body = raw()))
    seen$headers[[length(seen$headers) + 1L]] = headers
    if (identical(headers[["if-none-match"]], "W/\"v1\"")) {
      return(list(status = 304L, headers = list(), body = raw()))
    }
    list(status = 200L, headers = list(ETag = "W/\"v1\""), body = charToRaw(json_encode(api)))
  })
  expect_true(catalog_refresh())
  expect_true(file.exists(file.path(dir, "cache-models.json")))
  expect_equal(readLines(file.path(dir, "cache-models.etag"), warn = FALSE), "W/\"v1\"")
  expect_equal(model_resolve("sonnet")$ref, "anthropic/claude-sonnet-6")
  expect_false(catalog_refresh())
  expect_equal(seen$headers[[2]][["if-none-match"]], "W/\"v1\"")
  local_mocked_bindings(catalog_http_get = function(url, headers = list(), timeout = 30) {
    list(status = 503L, headers = list(), body = raw())
  })
  unlink(file.path(dir, "cache-models.etag"))
  expect_error(catalog_refresh(), class = "gptr_error_network")
})

test_that("resolution is offline: builtins and gptr_models('sonnet') start no transfer", {
  count = new.env()
  count$transfers = 0L
  local_mocked_bindings(reactor_http = function(...) {
    count$transfers = count$transfers + 1L
    "t1"
  })
  catalog_reset(discovered = TRUE)
  api = new.env()
  api$specs = list()
  api$register = function(spec) {
    api$specs[[length(api$specs) + 1L]] = spec
    invisible(function() NULL)
  }
  builtin_providers(api)
  expect_length(api$specs, 17L)
  expect_true(all(vapply(api$specs, function(s) inherits(s, "gptr_provider"), NA)))
  expect_null(the$catalog)
  df = gptr_models("sonnet")
  expect_match(df$ref[[1]], "^anthropic/claude-sonnet-")
  expect_equal(df$ref[[1]], model_resolve("sonnet")$ref)
  expect_equal(count$transfers, 0L)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 93 ]`, with ``Can't find binding for `catalog_http_get` `` and ``could not find function "gptr_models"``.

- [ ] **Step 3: Write the implementation**

Append to `R/catalog-models.R`:

```r
#' Is a provider usable as a default route: not disabled in the settings and holding a key?
#' @noRd
model_route_ready = function(id, vars) {
  !isFALSE(provider_settings(id)[["enabled"]]) && model_key_present(id, vars)
}

#' Is a subscription CLI provider registered and reported available by its status()?
#' @noRd
model_cli_available = function(id) {
  p = provider_get(id)
  f = p[["status"]]
  if (!is.function(f) || isFALSE(p[["enabled"]])) return(FALSE)
  s = tryCatch(if ("check" %in% names(formals(f))) f(check = FALSE) else f(),
               error = function(e) NULL)
  isTRUE(s[["available"]])
}

#' Default model reference for a role (contract section 7.5; architecture section 8.4)
#'
#' The setting (`model`, `small_model`, `system1`) wins; otherwise the first available route:
#' an Anthropic key, then OpenAI, then Gemini, then a detected CLI. A provider whose settings say
#' `enabled: false` is no route.
#' @noRd
model_default = function(role = c("chat", "small", "system1")) {
  role = check_choice(role, c("chat", "small", "system1"), "role")
  key = switch(role, chat = "model", small = "small_model", system1 = "system1")
  v = setting_get(key)
  if (is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)) return(v)
  if (identical(role, "system1")) {
    return(if (model_route_ready("typesafe", "TYPESAFE_API_KEY")) "typesafe/jev-latest" else NULL)
  }
  if (identical(role, "small")) {
    base = setting_get("model")
    rec = if (is.character(base) && length(base) == 1L && !is.na(base) && nzchar(base)) {
      tryCatch(model_resolve(base, strict = FALSE), gptr_error = function(e) NULL)
    }
    chat = if (is.null(rec)) model_default("chat") else rec$ref
    if (is.null(chat)) return(NULL)
    ctg = catalog_get()
    spec = ctg$small[[sub("/.*$", "", chat)]]
    small = if (is.null(spec)) NA_character_ else catalog_alias_target(spec, ctg$index)
    return(if (is.na(small)) chat else small)
  }
  if (model_route_ready("anthropic", "ANTHROPIC_API_KEY")) {
    "anthropic/claude-sonnet-5-5"
  } else if (model_route_ready("openai", "OPENAI_API_KEY")) {
    "openai/gpt-6-sol"
  } else if (model_route_ready("google", c("GEMINI_API_KEY", "GOOGLE_API_KEY"))) {
    "google/gemini-3.8-flash"
  } else if (model_cli_available("claude-cli")) {
    "claude-cli/default"
  } else if (model_cli_available("codex")) {
    "codex/default"
  } else {
    NULL
  }
}

#' A case-insensitive header value from a named list or character vector
#' @noRd
catalog_header = function(headers, name) {
  if (!length(headers)) return(NULL)
  h = headers[tolower(names(headers)) == tolower(name)]
  if (!length(h)) NULL else as.character(h[[1]])
}

#' One GET on the reactor (followlocation = 0 is set by the transport, IC-64)
#'
#' Returns `list(status, headers, body)` for any HTTP status; a transport failure without a
#' status signals `gptr_error_network`.
#' @noRd
catalog_http_get = function(url, headers = list(), timeout = 30) {
  st = new.env(parent = emptyenv())
  st$chunks = list()
  st$done = FALSE
  st$status = NA_integer_
  st$headers = list()
  st$cnd = NULL
  spec = list(url = url, method = "GET", headers = headers, body = NULL, stream = "json")
  id = reactor_http(spec,
                    on_bytes = function(raw) {
                      st$chunks[[length(st$chunks) + 1L]] = raw
                    },
                    on_done = function(status, hdrs) {
                      st$status = status
                      st$headers = hdrs
                      st$done = TRUE
                    },
                    on_fail = function(cnd) {
                      st$cnd = cnd
                      st$done = TRUE
                    },
                    on_headers = function(status, hdrs) {
                      st$status = status
                      st$headers = hdrs
                    },
                    provider = "catalog")
  origin = sub("^([A-Za-z]+://[^/?#]+).*$", "\\1", url)
  if (!isTRUE(reactor_pump(until = function() st$done, timeout = timeout))) {
    reactor_cancel(id)
    gptr_abort(paste0("No answer from ", origin, " within ", timeout, " s."),
               c("network", "provider"), provider = "catalog", status = NA_integer_,
               curl_code = NA_integer_)
  }
  status = suppressWarnings(as.integer(st$status))
  if (is.na(status) && !is.null(st$cnd)) status = suppressWarnings(as.integer(st$cnd$status))
  if (!length(status) || is.na(status)) {
    msg = if (is.null(st$cnd)) "no response" else conditionMessage(st$cnd)
    gptr_abort(paste0("Could not reach ", origin, ": ", msg), c("network", "provider"),
               provider = "catalog", status = NA_integer_,
               curl_code = st$cnd$curl_code %||% NA_integer_)
  }
  list(status = status, headers = st$headers,
       body = if (length(st$chunks)) do.call(c, st$chunks) else raw())
}

#' Refresh the catalog from models.dev with ETag revalidation (explicit request only)
#'
#' Writes `models.json` and `models.etag` into `R_user_dir("gptr", "cache")`; returns TRUE when
#' a new catalog was written and FALSE on 304 Not Modified.
#' @noRd
catalog_refresh = function() {
  gptr_user_dir("cache", create = TRUE)
  json_path = catalog_cache_path()
  etag_path = catalog_etag_path()
  hdr = list(accept = "application/json")
  if (file.exists(json_path) && file.exists(etag_path)) {
    etag = readLines(etag_path, encoding = "UTF-8", warn = FALSE)[1]
    if (!is.na(etag) && nzchar(etag)) hdr[["if-none-match"]] = etag
  }
  res = catalog_http_get(catalog_source_url, headers = hdr, timeout = 30)
  if (identical(res$status, 304L)) return(invisible(FALSE))
  if (!identical(res$status, 200L)) {
    gptr_abort(paste0("models.dev answered HTTP ", res$status, "; the catalog was not refreshed."),
               c("network", "provider"), provider = "models.dev", status = res$status,
               curl_code = NA_integer_)
  }
  api = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
  if (!is.list(api)) {
    gptr_abort("models.dev returned text that is not a JSON object; the catalog was not refreshed.",
               c("network", "provider"), provider = "models.dev", status = res$status,
               curl_code = NA_integer_)
  }
  decision = tryCatch({
    d = catalog_http_get(catalog_decision_url, headers = list(accept = "application/json"),
                         timeout = 30)
    if (identical(d$status, 200L)) json_decode(raw_to_utf8(d$body)) else NULL
  }, error = function(e) NULL)
  snap = catalog_snapshot(api, decision, generated = format(Sys.Date(), "%Y-%m-%d"))
  write_atomic(json_path, json_encode(snap))
  etag = catalog_header(res$headers, "etag")
  if (is.null(etag)) unlink(etag_path) else write_atomic(etag_path, etag)
  catalog_reset(discovered = FALSE)
  invisible(TRUE)
}

#' Run a local provider's discover() and add its models as the discovery layer
#' @noRd
catalog_discover = function(p) {
  df = tryCatch(p[["discover"]](), error = function(e) NULL)
  if (!is.data.frame(df) || !nrow(df) || is.null(df[["id"]])) return(invisible(0L))
  pid = p[["id"]] %||% p[["name"]]
  entries = lapply(as.character(df[["id"]]), function(i) {
    list(provider = pid, id = i, name = i, status = "active", tool_call = TRUE)
  })
  st = the$catalog %||% list()
  disc = st[["discovered"]] %||% list()
  disc[[pid]] = entries
  st[["discovered"]] = disc
  st[["value"]] = NULL
  the$catalog = st
  invisible(length(entries))
}

#' Regular-expression search with a fixed-string fallback for invalid patterns
#' @noRd
catalog_grepl = function(pattern, x) {
  tryCatch(suppressWarnings(grepl(pattern, x, ignore.case = TRUE, perl = TRUE)),
           error = function(e) grepl(tolower(pattern), tolower(x), fixed = TRUE))
}

#' List models from the model catalog
#'
#' Searches the merged model catalog: the shipped snapshot (models.dev plus gptr's reviewed
#' prices and capabilities), a refreshed copy in `tools::R_user_dir("gptr", "cache")`, models
#' declared by registered providers, user configuration and discovered local servers. Offline
#' by default: only `refresh = TRUE` touches the network.
#'
#' @param query `NULL` or a regular expression or alias (for example `"sonnet"`), matched
#'   against the reference, the name and the aliases; the model an alias resolves to is listed
#'   first.
#' @param provider `NULL` or a provider id (for example `"anthropic"`).
#' @param refresh `TRUE` downloads the current models.dev catalog with ETag revalidation into
#'   the user cache; for a local provider (`provider = "ollama"`, ...) it asks that server for
#'   its models instead. The only network use of this function.
#' @return A `gptr_models` data frame with columns `ref`, `provider`, `name`, `context`,
#'   `max_output`, `input_price`, `output_price` (USD per million tokens, in force today),
#'   `reasoning`, `aliases` and `status`.
#' @examples
#' gptr_models("sonnet")
#' gptr_models(provider = "anthropic")
#' @export
gptr_models = function(query = NULL, provider = NULL, refresh = FALSE) {
  check_string(query, "query", null = TRUE)
  check_string(provider, "provider", null = TRUE)
  check_flag(refresh, "refresh")
  if (refresh) {
    p = if (is.null(provider)) NULL else provider_get(provider)
    if (isTRUE(p[["local"]]) && is.function(p[["discover"]])) {
      catalog_discover(p)
    } else {
      catalog_refresh()
    }
  }
  ctg = catalog_get()
  idx = ctg$index
  keep = rep(TRUE, nrow(idx))
  if (!is.null(provider)) keep = keep & idx$provider == provider
  first = character()
  if (!is.null(query)) {
    hit = tryCatch(model_resolve(query, strict = FALSE), gptr_error = function(e) NULL)
    if (!is.null(hit)) first = hit$ref
    found = catalog_grepl(query, idx$ref) | catalog_grepl(query, idx$name) |
      catalog_grepl(query, idx$aliases)
    keep = keep & (found | idx$ref %in% first)
  }
  rows = idx[keep, , drop = FALSE]
  rows = rows[order(!(rows$ref %in% first), rows$provider, rows$ref, method = "radix"), ,
              drop = FALSE]
  entries = ctg$models[rows$ref]
  today = lapply(entries, function(e) {
    price_select(prices_df(e[["prices"]]), 0, Sys.Date())
  })
  rate = function(k) vapply(today, function(r) if (is.null(r)) NA_real_ else r[[k]][[1]], 0)
  df = data.frame(ref = rows$ref, provider = rows$provider, name = rows$name,
                  context = vapply(entries, function(e) catalog_num(e[["context"]]), 0),
                  max_output = vapply(entries, function(e) catalog_num(e[["max_output"]]), 0),
                  input_price = rate("input"), output_price = rate("output"),
                  reasoning = vapply(entries, function(e) isTRUE(e[["reasoning"]]), NA),
                  aliases = rows$aliases, status = rows$status, stringsAsFactors = FALSE)
  rownames(df) = NULL
  new_listing(df, "gptr_models",
              footer = paste0("catalog ", ctg$generated, " (", ctg$source, "), ",
                              nrow(idx), " models; gptr_models(refresh = TRUE) updates it"))
}
```

Regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`
Expected: `Writing 'NAMESPACE'` and `Writing 'gptr_models.Rd'`; `NAMESPACE` now contains `export(gptr_models)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 130 ]`

- [ ] **Step 5: Commit**

```bash
git add R/catalog-models.R NAMESPACE man/gptr_models.Rd tests/testthat/test-catalog-models.R
git commit -m "feat(catalog): gptr_models(), model defaults and explicit ETag refresh"
```

---

### Task 9: Usage rows, roll-up and the process System 1 log

**Files:**
- Modify: `R/provider-usage.R` (append)
- Test: `tests/testthat/test-provider-usage.R` (append)

**Interfaces:**
- Consumes: `id_new(prefix = "", n = 10L)` (P01), `model_resolve()` (Task 7), `usage_cost()`, `price_select()`, `prices_df()` (Task 1); tests use `gptr_provider()`, `gptr_register()` (P02) and `msg_assistant()` (P01).
- Produces: `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)` -> a one-row data frame with the 21 columns of 04 section 4.3 (consumed by P06, P12, P13, P20); `usage_log_append(row)`, `usage_log()` (the append-only process System 1 log in `the$s1_log`, consumed by P13 and P06); private `usage_empty()` (the zero-row table with the section 4.3 columns and types) and `usage_rollup(rows)` (one row per root session with the columns of the aggregated `gptr_usage` view of 04 section 5.12: `group`, `requests`, `input`, `output`, `cache_read`, `cache_write`, `cost`).

The row's model record is resolved from the message's `provider` and `model`; its cost is recomputed from the dated price tier in force on the request date, except on the `plan-cli` route, which keeps the CLI's own `total_cost_usd` estimate (04 section 8.5). Storing rows in `.d$usage` and `gptr_usage()` are P06's (IC-05); the roll-up rule is P05's (05 scope: "routes, roll-up"): every row's session is followed through the `session -> parent_id` pairs to its root, so a child session's requests are charged to the session that started it and the per-agent sum equals the session total (INFRA-20).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-usage.R`:

```r
local_priced_provider = function(.env = parent.frame()) {
  spec = gptr_provider("pricetest", api = "fake", models = list(list(
    id = "m1", prices = list(list(from = "2000-01-01", tier = "default", input = 4, output = 20,
                                  cache_read = 0.2, cache_write_5m = 5, cache_write_1h = 8))
  )))
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  spec
}

usage_msg = function(usage, route = "api", request_id = "q000000000001") {
  msg_assistant("ok", api = "fake", provider = "pricetest", model = "m1", usage = usage,
                route = route, request_id = request_id)
}

test_that("usage_row() prices a request and attributes it (INFRA-20)", {
  local_priced_provider()
  started = as.POSIXct("2026-09-30 12:00:00", tz = "UTC")
  row = usage_row(usage_msg(usage_new(input = 50, output = 1200, cache_read = 200000,
                                      cache_write_5m = 3000)),
                  session = "s0123456789", agent = "main", parent_id = NA_character_,
                  started = started, seconds = 1.5, multiplier = 1.1)
  expect_named(row, names(usage_empty()))
  expect_equal(nrow(row), 1L)
  expect_equal(row$cost, 0.0792)
  expect_equal(row$route, "api")
  expect_equal(row$tier, "default")
  expect_equal(row$request_id, "q000000000001")
  expect_equal(row$provider, "pricetest")
  expect_equal(row$model, "m1")
  expect_equal(row$multiplier, 1.1)
  expect_s3_class(row$started, "POSIXct")
  generated = usage_row(usage_msg(usage_new(input = 1), request_id = NULL), "s0123456789",
                        "main", NA_character_, started, 0.1, 1)
  expect_match(generated$request_id, "^q[0-9a-f]{12}$")
})

test_that("plan-cli rows keep the CLI's own cost estimate", {
  local_priced_provider()
  row = usage_row(usage_msg(usage_new(input = 20, output = 172, cost = list(total = 0.0179)),
                            route = "plan-cli"),
                  "s0123456789", "main", NA_character_, Sys.time(), 2.7, 1)
  expect_equal(row$cost, 0.0179)
  expect_equal(row$route, "plan-cli")
})

test_that("child usage rolls up to the parent session (INFRA-20)", {
  local_priced_provider()
  t0 = as.POSIXct("2026-09-30 12:00:00", tz = "UTC")
  row = function(input, output, session, agent, parent_id) {
    usage_row(usage_msg(usage_new(input = input, output = output, cache_write_1h = 10)),
              session, agent, parent_id, t0, 1, 1)
  }
  rows = rbind(row(1000, 100, "s0000000001", "main", NA_character_),
               row(500, 50, "s0000000002", "stats", "s0000000001"),
               row(400, 40, "s0000000003", "code", "s0000000001"),
               row(100, 10, "s0000000004", "helper", "s0000000003"),
               row(300, 30, "s0000000009", "main", NA_character_))
  expect_true("route" %in% names(rows))
  up = usage_rollup(rows)
  expect_named(up, c("group", "requests", "input", "output", "cache_read", "cache_write",
                     "cost"))
  expect_equal(up$group, c("s0000000001", "s0000000009"))
  expect_equal(up$requests, c(4L, 1L))
  expect_equal(up$input, c(2000, 300))
  expect_equal(up$cache_write, c(40, 10))
  tree = rows[rows$session != "s0000000009", ]
  expect_equal(up$cost[[1]], sum(tree$cost))
  expect_equal(sum(tapply(tree$cost, tree$agent, sum)), up$cost[[1]])
  expect_equal(sum(up$cost), sum(rows$cost))
  expect_equal(nrow(usage_rollup(usage_empty())), 0L)
})

test_that("the process System 1 log is append-only", {
  old = the$s1_log
  withr::defer(assign("s1_log", old, envir = the))
  assign("s1_log", NULL, envir = the)
  expect_equal(nrow(usage_log()), 0L)
  expect_named(usage_log(), names(usage_empty()))
  local_priced_provider()
  row = usage_row(usage_msg(usage_new(input = 250, output = 3), route = "system-one"),
                  NA_character_, "s1", NA_character_, Sys.time(), 0.4, 1)
  usage_log_append(row)
  usage_log_append(row)
  log = usage_log()
  expect_equal(nrow(log), 2L)
  expect_equal(log$route, c("system-one", "system-one"))
  expect_error(usage_log_append(list(a = 1)), class = "gptr_error_invalid_argument")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-usage")'`
Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 23 ]`, with ``could not find function "usage_row"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-usage.R`:

```r
#' A POSIXct from a POSIXct, epoch seconds or NULL (now)
#' @noRd
usage_time = function(x) {
  if (is.null(x)) return(Sys.time())
  if (inherits(x, "POSIXct")) return(x)
  .POSIXct(as.numeric(x))
}

#' A zero-row usage table with the contract section 4.3 columns and types
#' @noRd
usage_empty = function() {
  data.frame(request_id = character(), session = character(), agent = character(),
             parent_id = character(), provider = character(), model = character(),
             route = character(), input = numeric(), output = numeric(),
             cache_read = numeric(), cache_write_5m = numeric(), cache_write_1h = numeric(),
             reasoning = numeric(), images = numeric(), cost = numeric(), tier = character(),
             stop_reason = character(), started = .POSIXct(numeric()), seconds = numeric(),
             estimated = logical(), multiplier = numeric(), stringsAsFactors = FALSE)
}

#' One usage row (contract section 4.3) for an assistant message
#'
#' The model record is resolved from the message's provider and model; the cost is recomputed
#' from the dated price tier in force on the request date, except on the `plan-cli` route,
#' whose cost is the CLI's own estimate (`total_cost_usd`, 04 section 8.5).
#' @noRd
usage_row = function(msg, session, agent, parent_id, started, seconds, multiplier) {
  u = usage_as(msg[["usage"]])
  route = msg[["route"]] %||% "api"
  model = NULL
  if (!is.null(msg[["provider"]]) && !is.null(msg[["model"]])) {
    model = model_resolve(paste0(msg[["provider"]], "/", msg[["model"]]), strict = FALSE)
  }
  started = usage_time(started)
  when = as.Date(started)
  sel = if (is.null(model)) {
    NULL
  } else {
    price_select(prices_df(model[["prices"]]), usage_prompt_tokens(u), when)
  }
  cost = if (is.null(sel) || identical(route, "plan-cli")) {
    u$cost$total
  } else {
    usage_cost(u, model, when)$cost$total
  }
  data.frame(request_id = msg[["request_id"]] %||% id_new("q", 12L),
             session = session %||% NA_character_, agent = agent %||% "main",
             parent_id = parent_id %||% NA_character_,
             provider = msg[["provider"]] %||% NA_character_,
             model = msg[["model"]] %||% NA_character_, route = route,
             input = u[["input"]], output = u[["output"]], cache_read = u[["cache_read"]],
             cache_write_5m = u[["cache_write_5m"]], cache_write_1h = u[["cache_write_1h"]],
             reasoning = u[["reasoning"]], images = u[["images"]], cost = cost,
             tier = if (is.null(sel)) "default" else sel$tier,
             stop_reason = msg[["stop_reason"]] %||% NA_character_, started = started,
             seconds = as.numeric(seconds %||% NA_real_), estimated = isTRUE(u[["estimated"]]),
             multiplier = as.numeric(multiplier %||% 1), stringsAsFactors = FALSE)
}

#' Append a row to the process System 1 accounting log (append-only; `the$s1_log`)
#' @noRd
usage_log_append = function(row) {
  cols = names(usage_empty())
  if (!is.data.frame(row) || !all(cols %in% names(row))) {
    gptr_abort("usage_log_append() needs a usage row built by usage_row().",
               "invalid_argument", arg = "row", expected = "a usage row data frame")
  }
  rows = the$s1_log %||% list()
  rows[[length(rows) + 1L]] = row[cols]
  the$s1_log = rows
  invisible(nrow(row))
}

#' The process System 1 accounting log as one usage table
#' @noRd
usage_log = function() {
  rows = the$s1_log
  if (!length(rows)) return(usage_empty())
  out = do.call(rbind, rows)
  rownames(out) = NULL
  out
}

#' Roll usage rows up to their root sessions (INFRA-20)
#'
#' Each row's session is followed through the `session -> parent_id` pairs of `rows` to its
#' root (a parent without rows of its own is a root), so child sessions (team members, fan-out
#' elements, nested calls) are charged to the session that started them. Returns one row per
#' root in order of first appearance, with the columns of the aggregated `gptr_usage` view
#' (04 section 5.12): `group`, `requests`, `input`, `output`, `cache_read`, `cache_write`,
#' `cost`.
#' @noRd
usage_rollup = function(rows) {
  sums = c("input", "output", "cache_read", "cache_write", "cost")
  if (!is.data.frame(rows) || !nrow(rows)) {
    out = data.frame(group = character(), requests = integer(), stringsAsFactors = FALSE)
    for (k in sums) out[[k]] = numeric()
    return(out)
  }
  parent = rows$parent_id
  names(parent) = rows$session
  parent = parent[!is.na(names(parent)) & !duplicated(names(parent))]
  root = vapply(rows$session, function(s) {
    seen = character()
    while (!is.na(s) && !(s %in% seen)) {
      seen = c(seen, s)
      p = if (s %in% names(parent)) parent[[s]] else NA_character_
      if (is.na(p)) break
      s = p
    }
    s
  }, "", USE.NAMES = FALSE)
  groups = unique(root)
  key = match(root, groups)
  m = rowsum(cbind(input = rows$input, output = rows$output, cache_read = rows$cache_read,
                   cache_write = rows$cache_write_5m + rows$cache_write_1h, cost = rows$cost),
             key, reorder = FALSE)
  out = data.frame(group = groups, requests = tabulate(key, length(groups)),
                   stringsAsFactors = FALSE)
  for (k in sums) out[[k]] = unname(m[, k])
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-usage")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 51 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-usage.R tests/testthat/test-provider-usage.R
git commit -m "feat(provider): usage rows, roll-up and the process System 1 log"
```

---

### Task 10: provider_stream() glue and the HTTP transports

**Files:**
- Modify: `R/provider-registry.R` (append)
- Test: `tests/testthat/test-provider-registry.R` (append)

**Interfaces:**
- Consumes: `reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL, retry = NULL)` with `retry = list(max_attempts, committed, on_retry)`, `reactor_task(fn, run = NULL)`, `reactor_cancel(ids)`, `reactor_now()` (P04, 04 section 8.2); from P04's plan (internal, documented there for exactly this wiring): `reactor_retry(id, info)` (Task 12: "the transport side of the adapters' `opts$retry(info)` ... P05 wires `opts$retry = function(info) reactor_retry(<transfer id>, info)`": the reactor re-sends the same spec on the same transfer id after its backoff while `committed()` is `FALSE`, reporting `on_retry("retry_start" | "retry_end", info)`, and otherwise fails the transfer through `on_fail`), `ratelimit_get(provider)` and `ratelimit_set(provider, rate)` (Task 9: "settings and catalog overrides of the static rate, IC-64"); `sse_splitter()`, `ndjson_splitter()` (P04, 04 section 8.3); `gptr_condition(message, class, kind = "error", fields = list(), call = NULL)` (P01 plan, `utils-conditions.R`: the redacted, unsignalled condition objects of 04 section 2.2, last paragraph), `acc_new()`, `ev_new(type, ...)`, `msg_assistant()`, `msg_tool_result()`, `block_text()`, `json_encode()`, `raw_to_utf8()`, `gptr_opt(name)`, `gptr_abort()`, `ext_service_has(name)`, `ext_service_get(name)` (P01); `registry_get(kind, name, session = NULL)`, `registry_diagnostic(source, event, class, message)` (P02); `write_all(p, data)` (P04, for `opts$send`); `adapter_get()`, `provider_get()`, `provider_effective()`, `provider_settings()`, `provider_base_url()`, `provider_credential()` (Tasks 2-3), `catalog_get()` (Task 7). The `gptr_run` fields read are those of 04 section 7.6 (`id`, `session`, `status`, `signal`). Tests use `gptr_adapter(api, transport, build, parse, stream, classify, capabilities)`, `gptr_tool_result()` (P02) and `local_mocked_bindings()` on the P04 functions.
- Produces: `provider_stream(model, context, opts, emit, done, run = NULL)` (04 sections 7.5 and 8.4) -> the transfer id (`http_*`; one id for the whole request, retries included, so the caller's `reactor_cancel(id)` always reaches the live transfer), the generator task id (`inprocess`) or the stream-watch task id (`process_jsonl`), or `NA_character_` when the adapter failed to build the request; every INFRA-02 event, plus the transport's `retry_start`/`retry_end` notes (P06's `run_on_event()` turns them into the agent events of 04 section 10.4), reaches `emit(ev)`; `done(msg)` runs exactly once with the final assistant message; nothing is signalled after it returns. The context's `request_id` (04 section 4.5) is filled into the `start` event, the `error` event's `error` list and the assistant message of the `done`/`error` event and of `done(msg)` wherever the adapter left it `NULL` (P12's normalisers cannot know it: `parse(model, opts)` sees no request context), so P14's `jsonl` sink, the wire and the stored message carry it. Private `stream_request_id(st, ev, type)` and `stream_condition(message, class, ...)` (a classed, unsignalled, redacted condition, through P01's `gptr_condition()`).

Glue rules (04 sections 8.1 and 8.4, with the decisions this plan records in its self-review): the adapter and provider are looked up among the session's rank-0 records first (`opts$session`), then globally, and the provider's settings are applied (`provider_effective()`); a missing adapter (`gptr_error_not_available`), a provider whose settings say `enabled: false` (`gptr_error_not_available`, `member` = the provider id) or a missing key (`gptr_error_no_key`) is signalled before anything starts. `opts` receives `credential`, `base_url`, `provider` (the provider record found, so P01's fake adapter, whose `fake_engine(model, opts)` reads `opts$provider$log`, plays the session's own spec), `emit`, `retry`, `send`, `signal` (the caller's, else `run$signal`, else a new one), `state`, `memo`, and the injected `gate`, `tool_result` and `mcp_dispatch` (IC-33): the caller's (P06's `run_request()` passes the run's `perm_check()` closure and `tool_result_message()` in `opts`), else fail-closed defaults (deny; a minimal `msg_tool_result()`; the `mcp.dispatch_local` service bound to the session, or a JSON-RPC `-32601` error when P18 is absent). The request spec gets the optional fields P04 reads (`request_id`, `model`, `session_id`, `connect_timeout`, `first_byte_timeout`, `idle_timeout` from `opts`), and a static-rate override from the settings (`providers.<id>.rate`) or the catalog's providers section reaches P04's limiter once (IC-64). At most one `start` event reaches `emit`; `retry$committed` turns `TRUE` at the first `*_delta` event. An in-stream retryable failure reported through `opts$retry(info)` goes to P04's `reactor_retry()`: the reactor re-sends the same spec on the same transfer id while nothing was committed (a second `on_headers()` call resets the normaliser and splitter; the rest of the abandoned attempt's chunk is not pushed), and otherwise fails the transfer, so the normaliser's `fail()` ends the stream with the partial message; for transports without a transfer the stream fails at once. A reactor task watches `opts$signal$aborted`: it cancels the transfer and ends the stream with `stop_reason = "aborted"` and the partial message; it also lets go of the stream (without calling `done`) once the caller's run has settled, because P06's `run_settle()` cancels a transfer without callbacks and a watcher that kept polling would hold the run (INFRA-15).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-registry.R`:

```r
# ---- provider_stream(): HTTP transports on a scripted reactor ----------------------------

# reactor_retry() follows P04's contract: re-send (TRUE) while nothing is committed, otherwise
# fail the transfer through on_fail() (FALSE).
local_mock_reactor = function(.env = parent.frame()) {
  r = new.env()
  r$http = list()
  r$tasks = list()
  r$retries = list()
  r$cancelled = character()
  testthat::local_mocked_bindings(
    reactor_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL,
                            provider = NULL, retry = NULL) {
      id = paste0("t", length(r$http) + 1L)
      r$http[[id]] = list(spec = spec, on_bytes = on_bytes, on_done = on_done,
                          on_fail = on_fail, on_headers = on_headers, retry = retry,
                          provider = provider)
      id
    },
    reactor_retry = function(id, info) {
      r$retries[[length(r$retries) + 1L]] = list(id = id, info = info)
      tr = r$http[[id]]
      if (is.null(tr)) return(invisible(FALSE))
      if (isTRUE(tr$retry$committed())) {
        tr$on_fail(stream_condition("stream error: overloaded", c("overloaded", "provider"),
                                    status = 529L))
        return(invisible(FALSE))
      }
      invisible(TRUE)
    },
    reactor_task = function(fn, run = NULL) {
      r$tasks[[length(r$tasks) + 1L]] = fn
      paste0("t", 200L + length(r$tasks))
    },
    reactor_cancel = function(ids) {
      r$cancelled = c(r$cancelled, ids)
      invisible(length(ids))
    },
    reactor_now = function() 0,
    .env = .env
  )
  r
}

sse = function(...) charToRaw(paste0("data: ", c(...), "\n\n", collapse = ""))

# A tiny SSE adapter: data {"t":"text","v":...} is a delta, {"t":"overloaded"} a retryable error.
# Like P12's normalisers it cannot know the request id (parse() sees no request context), so
# its start and error events and its messages leave it NULL for provider_stream() to fill.
local_stream_adapter = function(api = "test-sse", auth = NULL, build = NULL,
                                .env = parent.frame()) {
  parse = function(model, opts) {
    s = new.env()
    s$text = character()
    s$started = FALSE
    current = function(stop = "stop") {
      msg_assistant(list(block_text(paste(s$text, collapse = ""))), api = model$api,
                    provider = model$provider, model = model$id, stop_reason = stop,
                    timestamp = 1)
    }
    list(
      push = function(ev) {
        d = json_decode(ev$data)
        if (!s$started) {
          s$started = TRUE
          opts$emit(ev_new("start", api = model$api, provider = model$provider,
                           model = model$id, request_id = NULL, response_id = NULL))
        }
        if (identical(d$t, "overloaded")) {
          opts$retry(list(class = "overloaded", status = 529L, retry_after = NULL))
          return(FALSE)
        }
        s$text = c(s$text, d$v)
        opts$emit(ev_new("text_delta", index = 1L, delta = d$v))
        FALSE
      },
      finish = function() {
        m = current()
        opts$emit(ev_new("done", reason = "stop", message = m, usage = NULL))
        m
      },
      fail = function(cnd) {
        m = current("error")
        m$error_message = conditionMessage(cnd)
        opts$emit(ev_new("error", reason = "error", message = m,
                         error = list(class = class(cnd)[[1]], status = cnd$status,
                                      request_id = NULL, retry_after = NULL)))
        m
      },
      message = function() current()
    )
  }
  build = build %||% function(model, context, opts) {
    list(url = paste0(opts$base_url, "/v1/stream"), method = "POST",
         headers = list(authorization = opts$credential), body = "{}", stream = "sse")
  }
  off1 = gptr_register(gptr_adapter(api, transport = "http_sse", build = build, parse = parse))
  off2 = gptr_register(gptr_provider("streamtest", api = api, base_url = "https://stream.example",
                                     auth = auth, models = list(list(id = "m1"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  model_resolve("streamtest/m1")
}

local_stream_log = function() {
  log = new.env()
  log$events = list()
  log$done = list()
  log$emit = function(ev) {
    log$events[[length(log$events) + 1L]] = ev
  }
  log$finish = function(msg) {
    log$done[[length(log$done) + 1L]] = msg
  }
  log$types = function() vapply(log$events, function(e) e$type, "")
  log
}

stream_context = function(text = "hi") {
  list(system = list(t0 = "", t1 = ""), tools_json = NULL, tools = list(),
       messages = list(msg_user(text, timestamp = 1)),
       cache_plan = list(anchors = character(), tail_ttl = "5m", key = "k"),
       params = list(max_tokens = 100L, thinking = NULL, effort = NULL, tool_choice = "auto",
                     returns = NULL, temperature = NULL),
       session_id = "s0000000000", request_id = "q000000000001", text = text)
}

# A stand-in for P06's gptr_run with the fields of 04 section 7.6 that provider_stream() reads.
local_run = function(status = "requesting") {
  run = new.env()
  run$id = "r0000000001"
  run$session = "s0000000000"
  run$status = status
  run$signal = new.env()
  run$signal$aborted = FALSE
  run$signal$reason = NULL
  run
}

test_that("an SSE stream yields one start, the deltas in order and one done", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_equal(id, "t1")
  t1 = r$http[["t1"]]
  expect_equal(t1$spec$url, "https://stream.example/v1/stream")
  expect_equal(t1$spec$request_id, "q000000000001")
  expect_equal(t1$spec$model, "m1")
  expect_equal(t1$spec$session_id, "s0000000000")
  expect_equal(t1$spec$idle_timeout, gptr_opt("idle_timeout"))
  expect_equal(t1$provider, "streamtest")
  expect_true(is.function(t1$retry$on_retry))
  expect_false(t1$retry$committed())
  t1$on_headers(200L, list())
  t1$on_bytes(sse('{"t":"text","v":"Hel"}'))
  expect_true(t1$retry$committed())
  t1$on_bytes(sse('{"t":"text","v":"lo"}'))
  t1$on_done(200L, list())
  expect_equal(log$types(), c("start", "text_delta", "text_delta", "done"))
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "Hello")
  # the request id the adapter cannot know is filled from the context (04 section 4.5)
  expect_equal(log$events[[1]]$request_id, "q000000000001")
  expect_equal(log$events[[4]]$message$request_id, "q000000000001")
  expect_equal(log$done[[1]]$request_id, "q000000000001")
  t1$on_done(200L, list())
  t1$on_fail(stream_condition("late", "network"))
  expect_length(log$done, 1L)
})

test_that("an in-stream retryable error before any delta is re-sent by the reactor", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  t1 = r$http[["t1"]]
  t1$on_headers(200L, list())
  t1$on_bytes(sse('{"t":"overloaded"}', '{"t":"text","v":"stale"}'))
  expect_length(r$retries, 1L)
  expect_equal(r$retries[[1]]$id, "t1")
  expect_equal(r$retries[[1]]$info$class, "overloaded")
  expect_false(t1$retry$committed())
  # P04 waits, reports the retry and re-sends the spec: a second head means "start over"
  t1$retry$on_retry("retry_start", list(attempt = 1L, delay = 0.5, class = "overloaded"))
  t1$on_headers(200L, list())
  t1$retry$on_retry("retry_end", list(attempt = 2L, ok = TRUE))
  t1$on_bytes(sse('{"t":"text","v":"ok"}'))
  t1$on_done(200L, list())
  expect_named(r$http, "t1")
  expect_equal(log$types(), c("start", "retry_start", "retry_end", "text_delta", "done"))
  expect_equal(log$events[[2]]$delay, 0.5)
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "ok")
})

test_that("a retryable error after a delta ends the stream with the partial message", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"par"}', '{"t":"overloaded"}'))
  expect_length(r$retries, 1L)
  expect_equal(log$types()[[length(log$events)]], "error")
  expect_equal(log$events[[length(log$events)]]$error$request_id, "q000000000001")
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_equal(log$done[[1]]$request_id, "q000000000001")
  expect_equal(msg_text(log$done[[1]]), "par")
})

test_that("setting the abort flag cancels the transfer and ends with an aborted message", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  provider_stream(model, stream_context(), list(signal = signal), emit = log$emit,
                  done = log$finish)
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"part"}'))
  watch = r$tasks[[1]]
  expect_true(watch())
  signal$aborted = TRUE
  expect_false(watch())
  expect_true("t1" %in% r$cancelled)
  expect_length(log$done, 1L)
  expect_equal(log$done[[1]]$stop_reason, "aborted")
  expect_equal(msg_text(log$done[[1]]), "part")
  expect_equal(log$events[[length(log$events)]]$reason, "aborted")
})

test_that("a run that settles while its stream is open lets go of the stream", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  log = local_stream_log()
  run = local_run("streaming")
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish, run = run)
  watch = r$tasks[[1]]
  expect_true(watch())
  run$status = "error"
  expect_false(watch())
  r$http[["t1"]]$on_bytes(sse('{"t":"text","v":"late"}'))
  expect_length(log$events, 0L)
  expect_length(log$done, 0L)
})

test_that("an adapter that fails to build ends the stream with one error event", {
  r = local_mock_reactor()
  model = local_stream_adapter(api = "test-broken",
                               build = function(model, context, opts) stop("bad request body"))
  log = local_stream_log()
  id = provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_true(is.na(id))
  expect_equal(log$types(), "error")
  expect_equal(log$done[[1]]$stop_reason, "error")
  expect_equal(log$done[[1]]$provider, "streamtest")
  expect_equal(log$done[[1]]$model, "m1")
  expect_match(log$done[[1]]$error_message, "bad request body", fixed = TRUE)
  expect_length(r$http, 0L)
})

test_that("a keyed provider without a credential is refused before anything starts", {
  r = local_mock_reactor()
  local_mocked_bindings(secret_lookup = function(name) NULL, auth_store_get = function(key) NULL)
  withr::local_envvar(GPTR_P05_TEST_KEY = "")
  model = local_stream_adapter(auth = "GPTR_P05_TEST_KEY")
  log = local_stream_log()
  expect_error(provider_stream(model, stream_context(), list(), emit = log$emit,
                               done = log$finish),
               class = "gptr_error_no_key")
  expect_length(r$http, 0L)
  expect_length(log$events, 0L)
})

test_that("a provider disabled in the settings is refused before anything starts", {
  r = local_mock_reactor()
  model = local_stream_adapter()
  local_settings(providers = list(streamtest = list(enabled = FALSE)))
  log = local_stream_log()
  err = expect_error(provider_stream(model, stream_context(), list(), emit = log$emit,
                                     done = log$finish),
                     class = "gptr_error_not_available")
  expect_equal(err$member, "streamtest")
  expect_length(r$http, 0L)
})

test_that("a static-rate override from the settings reaches the limiter once (IC-64)", {
  local_mock_reactor()
  model = local_stream_adapter()
  local_settings(providers = list(streamtest = list(rate = list(requests_per_s = 2))))
  lim = new.env()
  lim$n = 0L
  lim$rate = NULL
  local_mocked_bindings(
    ratelimit_get = function(provider) list(rate = lim$rate),
    ratelimit_set = function(provider, rate) {
      lim$n = lim$n + 1L
      lim$rate = rate
      invisible(NULL)
    }
  )
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  expect_equal(lim$n, 1L)
  expect_equal(lim$rate, list(requests_per_s = 2))
})

test_that("adapters receive the injected gate, MCP dispatcher and tool-result builder (IC-33)", {
  local_mock_reactor()
  seen = new.env()
  model = local_stream_adapter(build = function(model, context, opts) {
    seen$opts = opts
    list(url = "https://stream.example/v1/stream", method = "POST", headers = list(),
         body = "{}", stream = "sse")
  })
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  log = local_stream_log()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish)
  o = seen$opts
  expect_equal(o$gate(list(id = "c1", name = "r"))$decision, "deny")
  expect_equal(o$mcp_dispatch(list(jsonrpc = "2.0", id = 7L))$error$code, -32601L)
  tr = o$tool_result(gptr_tool_result("3 rows"), list(id = "c1", name = "r"))
  expect_equal(tr$role, "tool_result")
  expect_equal(tr$tool_call_id, "c1")
  expect_true(all(vapply(list(o$emit, o$retry, o$send), is.function, NA)))
  expect_true(is.environment(o$signal) && is.environment(o$state) && is.environment(o$memo))
  expect_equal(o$base_url, "https://stream.example")
  expect_null(o$credential)
  expect_equal(o$provider$id, "streamtest")
  mine = function(call) list(decision = "allow", reason = "test")
  provider_stream(model, stream_context(), list(gate = mine), emit = log$emit, done = log$finish)
  expect_identical(seen$opts$gate, mine)
  run = local_run()
  provider_stream(model, stream_context(), list(), emit = log$emit, done = log$finish, run = run)
  expect_identical(seen$opts$signal, run$signal)
  expect_equal(seen$opts$run, "r0000000001")
  expect_equal(seen$opts$session, "s0000000000")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 71 ]`, every new test failing with ``could not find function "provider_stream"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-registry.R`:

```r
#' A classed, unsignalled condition for stream failures (04 section 2.2, last paragraph)
#'
#' Built by P01's gptr_condition(), so the message passes the redaction hook like every other
#' gptr condition (an adapter's error text may quote a request).
#' @noRd
stream_condition = function(message, class, ...) {
  gptr_condition(message, class, "error", list(...))
}

#' The route of a model's messages (contract section 4.2)
#' @noRd
stream_route = function(model) {
  switch(model[["type"]] %||% "chat", cli = "plan-cli", classifier = "system-one", "api")
}

#' Fail-closed defaults for the callbacks provider_stream() injects (IC-33)
#' @noRd
stream_gate_closed = function(call) {
  list(decision = "deny", reason = "No permission gate is attached to this model stream.")
}

#' The default tool-result builder (P06 passes tool_result_message() in `opts` instead)
#' @noRd
stream_tool_result = function(result, call) {
  content = result[["content"]] %||% list(block_text("(no output)"))
  msg_tool_result(call[["id"]], call[["name"]], content, is_error = isTRUE(result[["is_error"]]),
                  details = result[["details"]])
}

#' The MCP dispatcher bound to a session (the mcp.dispatch_local service of P18)
#' @noRd
stream_mcp_dispatch = function(session) {
  force(session)
  function(message) {
    if (!ext_service_has("mcp.dispatch_local")) {
      return(list(jsonrpc = "2.0", id = message[["id"]],
                  error = list(code = -32601L, message = "gptr's MCP dispatcher is not loaded")))
    }
    ext_service_get("mcp.dispatch_local")(message, session)
  }
}

#' Diagnostics for callback errors that must not escape a stream
#' @noRd
stream_diagnostic = function(event, e) {
  tryCatch(registry_diagnostic("provider_stream", event, class(e)[[1]], conditionMessage(e)),
           error = function(e2) NULL)
  invisible(NULL)
}

#' Fill the request id an adapter cannot know (04 section 4.5: the `start` event, the `error`
#' event's `error` list and the assistant message carry it; P12's normalisers emit NULL because
#' `parse(model, opts)` sees no request context); an id the adapter set is kept
#' @noRd
stream_request_id = function(st, ev, type) {
  rid = st$context[["request_id"]]
  if (is.null(rid)) return(ev)
  if (identical(type, "start")) ev[["request_id"]] = ev[["request_id"]] %||% rid
  if (identical(type, "error") && is.list(ev[["error"]])) {
    err = ev[["error"]]
    err[["request_id"]] = err[["request_id"]] %||% rid
    ev[["error"]] = err
  }
  if (type %in% c("done", "error") && is.list(ev[["message"]])) {
    ev[["message"]][["request_id"]] = ev[["message"]][["request_id"]] %||% rid
  }
  ev
}

#' Emit one event: at most one start, the request id, commit tracking, terminal detection
#' @noRd
stream_emit = function(st, ev) {
  if (st$finished) return(invisible(NULL))
  type = ev[["type"]] %||% ""
  if (identical(type, "start")) {
    if (st$started) return(invisible(NULL))
    st$started = TRUE
  }
  ev = stream_request_id(st, ev, type)
  if (endsWith(type, "_delta")) st$committed = TRUE
  tryCatch(st$acc$push(ev), error = function(e) NULL)
  tryCatch(st$emit_cb(ev), error = function(e) stream_diagnostic("emit", e))
  if (type %in% c("done", "error")) stream_finish(st, ev[["message"]])
  invisible(NULL)
}

#' Deliver the final message exactly once (with the request id when the adapter left it out)
#' @noRd
stream_finish = function(st, msg) {
  if (st$finished) return(invisible(FALSE))
  st$finished = TRUE
  rid = st$context[["request_id"]]
  if (is.list(msg) && is.null(msg[["request_id"]]) && !is.null(rid)) msg[["request_id"]] = rid
  tryCatch(st$done_cb(msg), error = function(e) stream_diagnostic("done", e))
  invisible(TRUE)
}

#' The partial message known so far (normaliser, accumulator, or an empty message of the model)
#'
#' Before any `start` event the accumulator knows no api, provider or model (P01's acc_new()
#' answers "unknown"), so the message is built from the model record instead.
#' @noRd
stream_partial = function(st) {
  msg = if (is.null(st$norm)) NULL else tryCatch(st$norm$message(), error = function(e) NULL)
  if (!is.list(msg) && st$started) {
    msg = tryCatch(st$acc$message(), error = function(e) NULL)
  }
  if (is.list(msg)) return(msg)
  m = st$model
  msg_assistant(list(), api = m[["api"]] %||% "unknown", provider = m[["provider"]] %||% "unknown",
                model = m[["id"]] %||% "unknown", stop_reason = "error",
                route = stream_route(m), request_id = st$context[["request_id"]])
}

#' End the stream with a transport-level terminal event (setup failure, abort, missing end)
#' @noRd
stream_fail_local = function(st, reason, message, class, status = NA_integer_,
                             retry_after = NULL) {
  if (st$finished) return(invisible(NULL))
  msg = stream_partial(st)
  msg[["stop_reason"]] = reason
  msg[["error_message"]] = message
  ev = ev_new("error", reason = reason, message = msg,
              error = list(class = class, status = status,
                           request_id = st$context[["request_id"]], retry_after = retry_after))
  stream_emit(st, ev)
  if (!st$finished) stream_finish(st, msg)
  invisible(NULL)
}

#' Hand a transport failure to the normaliser (which emits the terminal error event)
#' @noRd
stream_normaliser_fail = function(st, cnd) {
  if (st$finished) return(invisible(NULL))
  if (!is.null(st$norm)) {
    tryCatch(st$norm$fail(cnd), error = function(e) stream_diagnostic("fail", e))
  }
  if (!st$finished) {
    cls = sub("^gptr_error_", "", class(cnd)[[1]])
    stream_fail_local(st, "error", conditionMessage(cnd), cls,
                      status = cnd[["status"]] %||% NA_integer_,
                      retry_after = cnd[["retry_after"]])
  }
  invisible(NULL)
}

#' Push one decoded unit into the normaliser; an error there ends the stream
#' @noRd
stream_push = function(st, unit) {
  if (st$finished) return(invisible(NULL))
  tryCatch(st$norm$push(unit), error = function(e) {
    stream_normaliser_fail(st, stream_condition(conditionMessage(e), "internal",
                                                detail = "adapter normaliser push()"))
  })
  invisible(NULL)
}

#' End of input: the normaliser emits the terminal event (done, or error when truncated)
#' @noRd
stream_normaliser_finish = function(st) {
  if (st$finished) return(invisible(NULL))
  msg = tryCatch(st$norm$finish(), error = function(e) {
    stream_normaliser_fail(st, stream_condition(conditionMessage(e), "internal",
                                                detail = "adapter normaliser finish()"))
    NULL
  })
  if (!st$finished) {
    if (is.list(msg)) {
      stream_finish(st, msg)
    } else {
      stream_fail_local(st, "error", "The stream ended without a terminal event.", "internal")
    }
  }
  invisible(NULL)
}

#' Abort: cancel the transfer or kill the child, then an `aborted` terminal event
#' @noRd
stream_abort = function(st) {
  if (st$finished) return(invisible(NULL))
  if (!is.null(st$process)) {
    # forget the child first, so its late output and exit reach no turn
    if (identical(st$opts$state$process, st$process)) st$opts$state$process = NULL
    tryCatch(kill_all(st$process), error = function(e) NULL)
  }
  if (identical(st$transport, "http") && !is.na(st$id)) {
    tryCatch(reactor_cancel(st$id), error = function(e) NULL)
  }
  reason = st$opts$signal$reason %||% "aborted"
  stream_fail_local(st, "aborted", as.character(reason)[[1]], "aborted")
}

#' Has the caller's run settled (a terminal status of contract section 7.6)?
#' @noRd
stream_run_settled = function(run) {
  if (!is.environment(run)) return(FALSE)
  status = run[["status"]]
  is.character(status) && length(status) == 1L &&
    !status %in% c("queued", "requesting", "streaming", "tools", "boundary")
}

#' Let go of a stream whose run settled without it: no more events, no `done`
#' @noRd
stream_detach = function(st) {
  if (st$finished) return(invisible(NULL))
  st$finished = TRUE
  if (identical(st$transport, "http") && !is.na(st$id)) {
    tryCatch(reactor_cancel(st$id), error = function(e) NULL)
  }
  st$emit_cb = function(ev) NULL
  st$done_cb = function(msg) NULL
  invisible(NULL)
}

#' A reactor task that turns `opts$signal$aborted` into stream_abort() and lets go of a stream
#' whose run settled; returns the task id
#' @noRd
stream_watch = function(st) {
  reactor_task(function() {
    if (st$finished) return(FALSE)
    if (isTRUE(st$opts$signal$aborted)) {
      stream_abort(st)
      return(FALSE)
    }
    if (stream_run_settled(st$run)) {
      stream_detach(st)
      return(FALSE)
    }
    TRUE
  }, run = st$run)
}

#' The retry callback normalisers call for a retryable failure seen inside the stream
#'
#' HTTP transfers go to P04's reactor_retry(): it re-sends the same spec on the same transfer
#' after its backoff while nothing was committed (on_retry() reports retry_start/retry_end), and
#' otherwise fails the transfer through on_fail(). Other transports end the stream at once
#' (04 section 8.1, `retry(info)`).
#' @noRd
stream_retry = function(st, info) {
  if (st$finished) return(invisible(FALSE))
  info = info %||% list()
  sent = FALSE
  if (identical(st$transport, "http") && !is.na(st$id)) {
    sent = isTRUE(tryCatch(reactor_retry(st$id, info), error = function(e) FALSE))
  }
  if (st$finished) return(invisible(FALSE))
  if (sent) {
    st$hold = TRUE
    return(invisible(TRUE))
  }
  cls = as.character(info[["class"]] %||% "overloaded")[[1]]
  cnd = stream_condition(paste0("The provider reported a retryable failure (", cls, ")."),
                         unique(c(cls, "provider")), status = info[["status"]] %||% NA_integer_,
                         retry_after = info[["retry_after"]])
  stream_normaliser_fail(st, cnd)
  invisible(FALSE)
}

#' Write one JSON line to the stream's child (process_jsonl `opts$send`)
#' @noRd
stream_send = function(st, obj) {
  p = st$process %||% st$opts$state$process
  if (is.null(p)) return(invisible(FALSE))
  write_all(p, paste0(json_encode(obj), "\n"))
  invisible(TRUE)
}

#' The opts every adapter function receives (contract section 8.1)
#'
#' `gate`, `tool_result` and `mcp_dispatch` are the caller's (P06 passes the run's), else
#' fail-closed defaults (IC-33).
#' @noRd
stream_opts = function(st, opts, session, run) {
  signal = opts[["signal"]] %||% (if (is.environment(run)) run[["signal"]] else NULL)
  if (is.null(signal)) {
    signal = new.env(parent = emptyenv())
    signal$aborted = FALSE
    signal$reason = NULL
  }
  opts$emit = function(ev) stream_emit(st, ev)
  opts$retry = function(info) stream_retry(st, info)
  opts$send = function(obj) stream_send(st, obj)
  opts$signal = signal
  opts$state = opts[["state"]] %||% new.env(parent = emptyenv())
  opts$memo = opts[["memo"]] %||% new.env(parent = emptyenv())
  opts$gate = opts[["gate"]] %||% stream_gate_closed
  opts$tool_result = opts[["tool_result"]] %||% stream_tool_result
  opts$mcp_dispatch = opts[["mcp_dispatch"]] %||% stream_mcp_dispatch(session)
  opts$session = session
  opts$run = opts[["run"]] %||% (if (is.environment(run)) run[["id"]] else run)
  opts$first_byte_timeout = opts[["first_byte_timeout"]] %||% gptr_opt("first_byte_timeout")
  opts$idle_timeout = opts[["idle_timeout"]] %||% gptr_opt("idle_timeout")
  opts$connect_timeout = opts[["connect_timeout"]] %||% gptr_opt("connect_timeout")
  opts
}

#' The request spec of an HTTP adapter with the optional fields P04 reads (P04 plan, Task 11:
#' `request_id`, `model`, `session_id` label the wire log and the conditions; the three timeouts
#' override the options)
#' @noRd
stream_http_spec = function(st, spec) {
  fill = list(request_id = st$context[["request_id"]], model = st$model[["id"]],
              session_id = st$opts[["session"]] %||% st$context[["session_id"]],
              connect_timeout = st$opts[["connect_timeout"]],
              first_byte_timeout = st$opts[["first_byte_timeout"]],
              idle_timeout = st$opts[["idle_timeout"]])
  for (k in names(fill)) {
    if (is.null(spec[[k]]) && !is.null(fill[[k]])) spec[[k]] = fill[[k]]
  }
  spec
}

#' A static-rate override of a provider: settings `providers.<id>.rate`, else the merged
#' catalog's providers section (IC-64: "overridable by settings and catalog"); NULL when none
#' @noRd
provider_rate_override = function(id) {
  ok = function(r) {
    is.list(r) && length(r) && !is.null(names(r)) &&
      all(names(r) %in% c("requests_per_s", "tokens_per_s")) &&
      all(vapply(r, function(v) is.numeric(v) && length(v) == 1L && !is.na(v) && v > 0, NA))
  }
  r = provider_settings(id)[["rate"]]
  if (ok(r)) return(r)
  r = tryCatch(catalog_get()$providers[[id]][["rate"]], error = function(e) NULL)
  if (ok(r)) r else NULL
}

#' Feed a rate override into P04's limiter: ratelimit_set() refills the bucket, so it runs only
#' when the override differs from the limiter's current static rate
#' @noRd
stream_rate_sync = function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id)) return(invisible(FALSE))
  rate = provider_rate_override(id)
  if (is.null(rate)) return(invisible(FALSE))
  current = tryCatch(ratelimit_get(id)$rate, error = function(e) NULL)
  if (identical(current, rate)) return(invisible(FALSE))
  ratelimit_set(id, rate)
  invisible(TRUE)
}

#' HTTP transports (http_sse, http_ndjson, http_json): one transfer for the whole request
#'
#' P04 calls on_headers() once per attempt with a 2xx head; a second call follows a re-send
#' (a transport retry or reactor_retry()) and resets the normaliser and the splitter.
#' @noRd
stream_http = function(st, adapter) {
  st$transport = "http"
  st$adapter = adapter
  st$spec = stream_http_spec(st, adapter$build(st$model, st$context, st$opts))
  kind = st$spec[["stream"]] %||% "sse"
  reset = function() {
    st$norm = adapter$parse(st$model, st$opts)
    st$split = switch(kind, sse = sse_splitter(), ndjson = ndjson_splitter(), NULL)
    st$body = list()
    st$hold = FALSE
  }
  reset()
  st$heads = 0L
  on_headers = function(status, headers) {
    if (st$finished) return(invisible(NULL))
    st$heads = st$heads + 1L
    if (st$heads > 1L) reset()
    st$hold = FALSE
  }
  on_bytes = function(raw) {
    if (st$finished || isTRUE(st$hold)) return(invisible(NULL))
    if (identical(kind, "json")) {
      st$body[[length(st$body) + 1L]] = raw
      return(invisible(NULL))
    }
    for (u in st$split$push(raw)) {
      if (st$finished || isTRUE(st$hold)) break
      stream_push(st, if (identical(kind, "ndjson")) list(data = u) else u)
    }
  }
  on_done = function(status, headers) {
    if (st$finished) return(invisible(NULL))
    if (identical(kind, "json")) {
      body = if (length(st$body)) do.call(c, st$body) else raw()
      stream_push(st, list(data = raw_to_utf8(body), status = status, headers = headers))
    } else {
      rest = st$split$flush()
      if (identical(kind, "ndjson")) {
        for (u in rest) stream_push(st, list(data = u))
      } else if (!is.null(rest)) {
        stream_push(st, rest)
      }
    }
    stream_normaliser_finish(st)
  }
  on_fail = function(cnd) if (!st$finished) stream_normaliser_fail(st, cnd)
  on_retry = function(type, info) {
    if (!st$finished) stream_emit(st, do.call(ev_new, c(list(type), info)))
  }
  retry = list(max_attempts = as.integer(gptr_opt("max_attempts") %||% 4L),
               committed = function() isTRUE(st$committed), on_retry = on_retry)
  stream_rate_sync(st$model[["provider"]])
  st$id = reactor_http(st$spec, on_bytes = on_bytes, on_done = on_done, on_fail = on_fail,
                       on_headers = on_headers, run = st$run, provider = st$model[["provider"]],
                       retry = retry)
  stream_watch(st)
  st$id
}

#' Start one model request on the reactor (contract sections 7.5 and 8.4)
#'
#' Looks up the adapter and provider (session-scoped records first; the provider's settings
#' applied), fills `opts` (credential, base URL, provider, emit/retry/send, signal, state, memo,
#' the injected gate, MCP dispatcher and tool-result builder, timeouts), then runs the adapter's
#' transport. Every event reaches `emit`; `done(msg)` is called exactly once with the final
#' assistant message; nothing is thrown after the function returns. A missing adapter or a
#' disabled provider (gptr_error_not_available) or a missing key (gptr_error_no_key) is
#' signalled before anything starts; an adapter that fails while building the request ends the
#' stream with an `error` event instead.
#' @noRd
provider_stream = function(model, context, opts, emit, done, run = NULL) {
  opts = opts %||% list()
  session = opts[["session"]] %||% (if (is.environment(run)) run[["session"]] else NULL)
  scoped = function(kind, name) {
    if (is.null(session) || is.null(name)) NULL else registry_get(kind, name, session = session)
  }
  adapter = scoped("adapter", model[["api"]]) %||% adapter_get(model[["api"]])
  provider = provider_effective(scoped("provider", model[["provider"]])) %||%
    provider_get(model[["provider"]])
  if (isFALSE(provider[["enabled"]])) {
    pid = provider[["id"]] %||% provider[["name"]]
    gptr_abort(paste0("Provider ", pid, " is disabled in the settings (providers.", pid,
                      ".enabled)."), "not_available", member = pid, provided_by = "settings")
  }
  opts$credential = provider_credential(provider)
  opts$base_url = if (is.null(provider)) NULL else provider_base_url(provider)
  opts$provider = provider
  st = new.env(parent = emptyenv())
  st$model = model
  st$context = context
  st$emit_cb = emit
  st$done_cb = done
  st$run = run
  st$started = FALSE
  st$committed = FALSE
  st$finished = FALSE
  st$transport = NA_character_
  st$id = NA_character_
  st$acc = acc_new()
  st$opts = stream_opts(st, opts, session, run)
  transport = adapter[["transport"]] %||% "http_sse"
  tryCatch({
    if (identical(transport, "inprocess")) {
      stream_inprocess(st, adapter)
    } else if (identical(transport, "process_jsonl")) {
      stream_process(st, adapter)
    } else {
      stream_http(st, adapter)
    }
  }, error = function(e) {
    cls = if (inherits(e, "gptr_error")) sub("^gptr_error_", "", class(e)[[1]]) else "internal"
    stream_fail_local(st, "error", conditionMessage(e), cls)
    NA_character_
  })
}
```

`stream_inprocess()` and `stream_process()` are added in Task 11; until then only HTTP adapters stream.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 143 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-registry.R tests/testthat/test-provider-registry.R
git commit -m "feat(provider): provider_stream() glue for HTTP adapters"
```

---

### Task 11: The inprocess and process_jsonl transports

**Files:**
- Modify: `R/provider-registry.R` (append)
- Test: `tests/testthat/test-provider-registry.R` (append)

**Interfaces:**
- Consumes: `child_env(profile, pass = character(), set = character(), provider = NULL)` (P03; called without `provider`, which would copy the provider's key into the child after the profile removed the billing variables), `proc_spawn(command, args = character(), env = NULL, wd = NULL, stdin = NULL, stdout = "|", stderr = "|", cleanup_tree = TRUE, supervise = supervise_default())`, `reactor_proc(proc, on_line, on_exit, run = NULL, stream = "stdout", on_stderr = NULL)`, `write_all(p, data)`, `kill_all(p, grace = 2)`, `job_add(kind, id, name, pid = NA, stop, status = function() "running")`, `job_remove(id)` (P04), `write_close(p)` (P04's plan, Task 8, internal: "closes stdin once the queued bytes are written; P20's codex route closes stdin after the prompt", named there for P05's `close_stdin`), `id_new()`, `json_decode()`, `json_encode()` (P01); the fake adapter of `builtin:fake` (P01) and `local_fake_provider()` (P01 `helper-fake.R`) in the tests; `reactor_pump()` (P04).
- Produces: steps 3 and 4 of 04 section 8.4 inside `provider_stream()`: `inprocess` adapters (IC-16) return a generator pumped by `reactor_task()` (events emitted in order, the next call after `wait` seconds, a throwing generator ends the stream with an `error` event, an abort gives the generator two calls to finish itself before the glue ends the stream); `process_jsonl` adapters get one supervised child per session (`proc_spawn()` with `stdin = "|"` and `child_env(<env_profile>, set = <env>)`, kept in `opts$state$process`, recorded in the job table as kind `cli`), `send` objects written as JSON lines with `write_all()` and, with `close_stdin = TRUE`, the child's stdin closed after them with `write_close()` (EOF once the bytes are written); child stdout lines are parsed and pushed as `list(data, obj)` (non-JSON lines ignored), and the child's exit ends the turn. Only the session's current child reaches a turn: the late lines and the exit of a child that was replaced or killed are dropped.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-registry.R`:

```r
# ---- provider_stream(): inprocess (the fake provider on the real reactor) -------------------

test_that("the fake provider streams through the inprocess transport", {
  local_fake_provider(list("hello there"))
  log = local_stream_log()
  provider_stream(model_resolve("fake/fake-1"), stream_context(), list(), emit = log$emit,
                  done = log$finish)
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 5))
  types = log$types()
  expect_equal(types[[1]], "start")
  expect_equal(types[[length(types)]], "done")
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "hello there")
})

test_that("an aborted inprocess stream ends with stop_reason aborted", {
  local_fake_provider(list(list(hang = TRUE)))
  log = local_stream_log()
  signal = new.env()
  signal$aborted = FALSE
  signal$reason = "user"
  provider_stream(model_resolve("fake/fake-1"), stream_context(), list(signal = signal),
                  emit = log$emit, done = log$finish)
  expect_true(reactor_pump(until = function() length(log$events) > 0L, timeout = 5))
  signal$aborted = TRUE
  expect_true(reactor_pump(until = function() length(log$done) > 0L, timeout = 5))
  expect_equal(log$done[[1]]$stop_reason, "aborted")
})

# ---- provider_stream(): process_jsonl on scripted process functions -------------------------

local_mock_process = function(.env = parent.frame()) {
  pr = new.env()
  pr$spawned = list()
  pr$watchers = list()
  pr$written = character()
  pr$closed = 0L
  pr$killed = 0L
  testthat::local_mocked_bindings(
    proc_spawn = function(command, args = character(), env = NULL, wd = NULL, stdin = NULL,
                          stdout = "|", stderr = "|", cleanup_tree = TRUE,
                          supervise = TRUE) {
      k = length(pr$spawned) + 1L
      pr$spawned[[k]] = list(command = command, args = args, env = env, stdin = stdin)
      handle = new.env()
      handle$get_pid = function() 4241L + k
      handle
    },
    reactor_proc = function(proc, on_line, on_exit, run = NULL, stream = "stdout",
                            on_stderr = NULL) {
      pr$watchers[[length(pr$watchers) + 1L]] = list(on_line = on_line, on_exit = on_exit)
      pr$on_line = on_line
      pr$on_exit = on_exit
      paste0("t", 50L + length(pr$watchers))
    },
    write_all = function(p, data) {
      pr$written = c(pr$written, data)
      invisible(p)
    },
    write_close = function(p) {
      pr$closed = pr$closed + 1L
      invisible(p)
    },
    job_add = function(kind, id, name, pid = NA, stop, status = function() "running") {
      pr$job = list(kind = kind, id = id, name = name, pid = pid)
      invisible(id)
    },
    job_remove = function(id) invisible(TRUE),
    kill_all = function(p, grace = 2) {
      pr$killed = pr$killed + 1L
      invisible(TRUE)
    },
    child_env = function(profile, pass = character(), set = character(), provider = NULL) {
      pr$profile = profile
      pr$env_provider = provider
      c(PATH = "/usr/bin", set)
    },
    .env = .env
  )
  pr
}

# A JSON-lines adapter: `start` only when no child runs (or always with close_stdin),
# {"type":"delta","v":..} are deltas, {"type":"result"} ends the turn, {"type":"ping"} is a
# control request answered with {"type":"pong"} through opts$send().
local_process_adapter = function(close_stdin = FALSE, .env = parent.frame()) {
  build = function(model, context, opts) {
    start = if (close_stdin || is.null(opts$state$process)) {
      list(command = "fakecli", args = c("--json"), env_profile = "cli-claude",
           env = c(FAKE_CLI = "1"), wd = NULL)
    }
    list(start = start, send = list(list(type = "user", text = context$text)),
         close_stdin = close_stdin)
  }
  parse = function(model, opts) {
    s = new.env()
    s$text = character()
    current = function() {
      msg_assistant(list(block_text(paste(s$text, collapse = ""))), api = model$api,
                    provider = model$provider, model = model$id, route = "plan-cli",
                    timestamp = 1)
    }
    list(
      push = function(ev) {
        type = ev$obj$type
        if (identical(type, "ping")) opts$send(list(type = "pong"))
        if (identical(type, "delta")) {
          if (!length(s$text)) {
            opts$emit(ev_new("start", api = model$api, provider = model$provider,
                             model = model$id, request_id = "q1", response_id = NULL))
          }
          s$text = c(s$text, ev$obj$v)
          opts$emit(ev_new("text_delta", index = 1L, delta = ev$obj$v))
        }
        if (identical(type, "result")) {
          opts$emit(ev_new("done", reason = "stop", message = current(), usage = NULL))
          return(TRUE)
        }
        FALSE
      },
      finish = function() {
        m = current()
        opts$emit(ev_new("done", reason = "stop", message = m, usage = NULL))
        m
      },
      fail = function(cnd) current(),
      message = function() current()
    )
  }
  api = if (close_stdin) "test-proc-eof" else "test-proc"
  off1 = gptr_register(gptr_adapter(api, transport = "process_jsonl", build = build,
                                    parse = parse))
  off2 = gptr_register(gptr_provider("proctest", api = api, type = "cli",
                                     models = list(list(id = "default"))))
  withr::defer({
    off1()
    off2()
  }, envir = .env)
  model_resolve("proctest/default")
}

test_that("process_jsonl: one supervised child, JSON lines both ways, one done per turn", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter()
  state = new.env()
  log = local_stream_log()
  provider_stream(model, stream_context("hi"), list(state = state), emit = log$emit,
                  done = log$finish)
  expect_length(pr$spawned, 1L)
  expect_equal(pr$spawned[[1]]$command, "fakecli")
  expect_equal(pr$spawned[[1]]$stdin, "|")
  expect_equal(pr$profile, "cli-claude")
  expect_null(pr$env_provider)
  expect_equal(pr$job$kind, "cli")
  expect_equal(pr$written, "{\"type\":\"user\",\"text\":\"hi\"}\n")
  expect_equal(pr$closed, 0L)
  pr$on_line("{\"type\":\"ping\"}")
  expect_equal(pr$written[[2]], "{\"type\":\"pong\"}\n")
  pr$on_line("not json at all")
  pr$on_line("{\"type\":\"delta\",\"v\":\"Hi!\"}")
  pr$on_line("{\"type\":\"result\"}")
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "Hi!")
  log2 = local_stream_log()
  provider_stream(model, stream_context("again"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  expect_length(pr$spawned, 1L)
  pr$on_line("{\"type\":\"delta\",\"v\":\"Again\"}")
  pr$on_line("{\"type\":\"result\"}")
  expect_equal(msg_text(log2$done[[1]]), "Again")
  expect_length(log$done, 1L)
})

test_that("process_jsonl with close_stdin writes the turn, then closes stdin", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter(close_stdin = TRUE)
  log = local_stream_log()
  provider_stream(model, stream_context("once"), list(state = new.env()), emit = log$emit,
                  done = log$finish)
  expect_length(pr$spawned, 1L)
  expect_equal(pr$spawned[[1]]$stdin, "|")
  expect_equal(pr$written, "{\"type\":\"user\",\"text\":\"once\"}\n")
  expect_equal(pr$closed, 1L)
  pr$on_line("{\"type\":\"delta\",\"v\":\"done\"}")
  pr$on_exit(0L)
  expect_length(log$done, 1L)
  expect_equal(msg_text(log$done[[1]]), "done")
})

test_that("a replaced child's late output and exit never reach the next turn", {
  local_mock_reactor()
  pr = local_mock_process()
  model = local_process_adapter(close_stdin = TRUE)
  state = new.env()
  log1 = local_stream_log()
  provider_stream(model, stream_context("one"), list(state = state), emit = log1$emit,
                  done = log1$finish)
  first = pr$watchers[[1]]
  first$on_line("{\"type\":\"delta\",\"v\":\"A\"}")
  first$on_line("{\"type\":\"result\"}")
  log2 = local_stream_log()
  provider_stream(model, stream_context("two"), list(state = state), emit = log2$emit,
                  done = log2$finish)
  expect_length(pr$spawned, 2L)
  expect_equal(pr$killed, 1L)
  first$on_line("{\"type\":\"delta\",\"v\":\"stale\"}")
  first$on_exit(0L)
  expect_length(log2$done, 0L)
  second = pr$watchers[[2]]
  second$on_line("{\"type\":\"delta\",\"v\":\"B\"}")
  second$on_exit(0L)
  expect_equal(msg_text(log2$done[[1]]), "B")
  expect_equal(msg_text(log1$done[[1]]), "A")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 147 ]`: the five new tests fail (nine failed expectations), for example ``Expected `types[[1]]` to equal "start".`` (the stream ends at once with an `error` event whose `error_message` reads ``could not find function "stream_inprocess"``) (the stream's `error_message` reads ``could not find function "stream_inprocess"``) and ``Error in `pr$spawned[[1]]`: subscript out of bounds``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-registry.R`:

```r
#' One generator step of an inprocess adapter (IC-16)
#' @noRd
stream_inprocess_step = function(st, gen) {
  if (st$finished) return(FALSE)
  if (isTRUE(st$opts$signal$aborted)) {
    st$aborts = st$aborts + 1L
    if (st$aborts > 2L) {
      stream_abort(st)
      return(FALSE)
    }
  } else if (reactor_now() < st$next_at) {
    return(TRUE)
  }
  res = tryCatch(gen(), error = function(e) {
    stream_fail_local(st, "error", conditionMessage(e), "internal")
    NULL
  })
  if (st$finished) return(FALSE)
  if (is.null(res)) {
    stream_fail_local(st, "error", "The stream ended without a terminal event.", "internal")
    return(FALSE)
  }
  for (ev in res[["events"]] %||% list()) {
    stream_emit(st, ev)
    if (st$finished) break
  }
  st$next_at = reactor_now() + as.numeric(res[["wait"]] %||% 0)
  !st$finished
}

#' The inprocess transport: a generator pumped by reactor_task() (04 section 8.1)
#' @noRd
stream_inprocess = function(st, adapter) {
  st$transport = "inprocess"
  gen = adapter$stream(st$model, st$context, st$opts)
  st$next_at = 0
  st$aborts = 0L
  st$id = reactor_task(function() stream_inprocess_step(st, gen), run = st$run)
  st$id
}

#' Start the child of a process_jsonl adapter and watch its stdout
#'
#' stdin is a pipe fed by write_all() (non-blocking, IC-60). Only the session's current child
#' (`opts$state$process`) routes lines and its exit to the open turn, so the late output of a
#' child that was replaced or killed reaches no turn. The child environment is the profile's
#' (`child_env()` without `provider`: no key is added to a CLI child, IC-65).
#' @noRd
stream_process_start = function(st, start) {
  state = st$opts$state
  env = child_env(start[["env_profile"]] %||% "helper",
                  set = unlist(start[["env"]]) %||% character())
  p = proc_spawn(start[["command"]], as.character(unlist(start[["args"]]) %||% character()),
                 env = env, wd = start[["wd"]], stdin = "|", stdout = "|", stderr = "|")
  job = id_new("j", 8L)
  job_add("cli", job, st$model[["provider"]], pid = p$get_pid(), stop = function() kill_all(p))
  state$process = p
  state$job = job
  reactor_proc(p,
               on_line = function(line) {
                 if (!identical(state$process, p)) return(invisible(NULL))
                 f = state$route
                 if (is.function(f)) f(line)
               },
               on_exit = function(status) {
                 job_remove(job)
                 if (!identical(state$process, p)) return(invisible(NULL))
                 state$process = NULL
                 f = state$route_exit
                 if (is.function(f)) f(status)
               },
               run = st$run)
  p
}

#' The process_jsonl transport (04 section 8.4 step 3)
#' @noRd
stream_process = function(st, adapter) {
  st$transport = "process"
  st$adapter = adapter
  spec = adapter$build(st$model, st$context, st$opts)
  st$norm = adapter$parse(st$model, st$opts)
  state = st$opts$state
  lines = vapply(spec[["send"]] %||% list(), function(o) json_encode(o), "")
  p = state$process
  if (!is.null(spec[["start"]])) {
    if (!is.null(p)) {
      state$process = NULL
      tryCatch(kill_all(p), error = function(e) NULL)
    }
    p = stream_process_start(st, spec[["start"]])
  }
  if (is.null(p)) {
    gptr_abort("The adapter reused a child process, but none is running for this session.",
               "internal", detail = "process_jsonl without start")
  }
  st$process = p
  state$route = function(line) {
    if (st$finished) return(invisible(NULL))
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (is.list(obj)) stream_push(st, list(data = line, obj = obj))
  }
  state$route_exit = function(status) stream_normaliser_finish(st)
  for (l in lines) write_all(p, paste0(l, "\n"))
  if (isTRUE(spec[["close_stdin"]])) write_close(p)
  st$id = stream_watch(st)
  st$id
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 176 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-registry.R tests/testthat/test-provider-registry.R
git commit -m "feat(provider): inprocess and process_jsonl transports"
```

---

### Task 12: gptr_providers()

**Files:**
- Modify: `R/provider-registry.R` (append)
- Modify: `NAMESPACE`, `man/gptr_providers.Rd` (generated)
- Test: `tests/testthat/test-provider-registry.R` (append)

**Interfaces:**
- Consumes: `gptr_registry(kind = NULL, diagnostics = FALSE)` (P02), `new_listing()`, `check_flag()`, `check_running()`, `setting_get()` (P01), `catalog_http_get()`, `catalog_get()` (Tasks 7-8), `provider_credential()`, `provider_base_url()` (Tasks 2-3). A provider's optional `status` function (P20 contributes them for `claude-cli` and `codex`) is called as `status(check = check)` when it has a `check` formal, else `status()`, and may return `status`, `version` and `available`.
- Produces: the export `gptr_providers(check = FALSE)` -> `c("gptr_providers", "gptr_listing", "data.frame")` with columns `id`, `type`, `api`, `credential` (`"NAME #fp"` or `NA`), `source` (the registry source of the provider's active record: `builtin:providers`, `user`, `plugin:<pkg>`, ...; self-review ambiguity 23), `status`, `default_model`, `egress` (`ack`/`needed`), `version` (04 sections 5.12 and 6.2).

`check = FALSE` performs no network or process I/O (IC-65): statuses come from the settings (`disabled` when `providers.<id>.enabled` is `false`), the credential lookup (`ready`/`no key`) or the provider's own cached `status()`. `check = TRUE` sends one unauthenticated GET to each HTTP provider's models endpoint with a 2 s timeout (`reachable (HTTP <status>)`/`unreachable`; a 401 proves reachability without sending a key) and is skipped under `R CMD check`. Local and offline providers need no egress acknowledgement (`ack`).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-registry.R`:

```r
# ---- gptr_providers() ------------------------------------------------------------------------

test_that("gptr_providers() lists providers with fingerprints and no I/O", {
  count = new.env()
  count$transfers = 0L
  local_mocked_bindings(
    reactor_http = function(...) {
      count$transfers = count$transfers + 1L
      "t1"
    },
    proc_spawn = function(...) stop("gptr_providers() must not start a process")
  )
  local_test_vault()
  withr::local_envvar(ANTHROPIC_API_KEY = "sk-ant-api03-p05list-000000000000000000",
                      GROQ_API_KEY = "")
  local_mocked_bindings(auth_store_get = function(key) NULL)
  local_settings(providers = list(cerebras = list(enabled = FALSE)))
  df = gptr_providers()
  expect_equal(df$status[df$id == "cerebras"], "disabled")
  expect_equal(df$status[df$id == "groq"], "no key")
  expect_s3_class(df, "gptr_providers")
  expect_named(df, c("id", "type", "api", "credential", "source", "status", "default_model",
                     "egress", "version"))
  expect_true(all(builtin_ids %in% df$id))
  a = df[df$id == "anthropic", ]
  expect_match(a$credential, "^ANTHROPIC_API_KEY #[0-9a-f]+$")
  expect_equal(a$status, "ready")
  expect_equal(a$default_model, "anthropic/claude-sonnet-5-5")
  expect_equal(a$egress, "needed")
  expect_equal(df$egress[df$id == "ollama"], "ack")
  expect_equal(df$status[df$id == "ollama"], "ready")
  printed = paste(capture.output(print(df)), collapse = "\n")
  expect_false(grepl("p05list", printed, fixed = TRUE))
  expect_equal(count$transfers, 0L)
  expect_error(gptr_providers(check = "yes"), class = "gptr_error_invalid_argument")
})

test_that("gptr_providers(check = TRUE) probes models endpoints without credentials", {
  urls = new.env()
  urls$seen = character()
  local_mocked_bindings(
    check_running = function() FALSE,
    catalog_http_get = function(url, headers = list(), timeout = 30) {
      urls$seen = c(urls$seen, url)
      expect_equal(timeout, 2)
      expect_length(headers, 0L)
      list(status = 401L, headers = list(), body = raw())
    }
  )
  local_settings(egress = list(anthropic = "ack"))
  df = gptr_providers(check = TRUE)
  expect_equal(df$status[df$id == "anthropic"], "reachable (HTTP 401)")
  expect_true("https://api.anthropic.com/v1/models" %in% urls$seen)
  expect_true("https://api.openai.com/v1/models" %in% urls$seen)
  expect_equal(df$egress[df$id == "anthropic"], "ack")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 176 ]`, with ``could not find function "gptr_providers"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-registry.R`:

```r
#' One reachability probe: GET <base>/models without credentials, 2 s (IC-65)
#' @noRd
provider_ping = function(p) {
  if (check_running()) return("not checked")
  url = provider_base_url(p)
  if (is.null(url)) return("no base url")
  path = if (identical(p[["api"]], "anthropic-messages")) "/v1/models" else "/models"
  res = tryCatch(catalog_http_get(paste0(url, path), timeout = 2), gptr_error = function(e) NULL)
  if (is.null(res)) "unreachable" else paste0("reachable (HTTP ", res$status, ")")
}

#' Status and version of a provider; `check = TRUE` adds a reachability probe
#' @noRd
provider_status = function(p, handle, check) {
  if (isFALSE(p[["enabled"]])) return(list(status = "disabled", version = NA_character_))
  f = p[["status"]]
  if (is.function(f)) {
    s = tryCatch(if ("check" %in% names(formals(f))) f(check = check) else f(),
                 error = function(e) list(status = "error"))
    return(list(status = as.character(s[["status"]] %||% "unknown")[[1]],
                version = as.character(s[["version"]] %||% NA_character_)[[1]]))
  }
  keyed = !is.null(p[["auth"]]) && !is.function(p[["auth"]]) && !isTRUE(p[["offline"]])
  status = if (keyed && is.null(handle)) "no key" else "ready"
  if (check && !isTRUE(p[["offline"]])) status = provider_ping(p)
  list(status = status, version = NA_character_)
}

#' The default model reference shown for a provider
#' @noRd
provider_default_model = function(p) {
  id = p[["id"]] %||% p[["name"]]
  d = provider_default_models()[id]
  if (!is.na(d)) return(paste0(id, "/", d))
  idx = catalog_get()$index
  rows = idx[idx$provider == id & idx$status == "active", , drop = FALSE]
  if (!nrow(rows)) return(NA_character_)
  rows$ref[order(rows$release_date, decreasing = TRUE, method = "radix")][[1]]
}

#' Egress acknowledgement state of a provider (the acknowledgement itself is P08's)
#' @noRd
provider_egress = function(p) {
  if (isTRUE(p[["local"]]) || isTRUE(p[["offline"]])) return("ack")
  eg = setting_get("egress", default = list()) %||% list()
  if (identical(eg[[p[["id"]] %||% p[["name"]]]], "ack")) "ack" else "needed"
}

#' List the configured model providers
#'
#' Shows every registered provider record: its wire api, where its credential comes from (as
#' `NAME #fingerprint`, never the value), its status, default model, egress acknowledgement and,
#' for subscription command-line tools, their version.
#'
#' @param check `FALSE` (default) performs no network or process input/output. `TRUE` also
#'   probes each HTTP provider's models endpoint without credentials (2 s timeout) and lets
#'   command-line providers check their tool; it never sends a paid request.
#' @return A `gptr_providers` data frame with columns `id`, `type`, `api`, `credential`,
#'   `source`, `status`, `default_model`, `egress` (`ack` or `needed`) and `version`.
#' @examples
#' gptr_providers()
#' @export
gptr_providers = function(check = FALSE) {
  check_flag(check, "check")
  ids = sort(registry_names("provider"))
  reg = tryCatch(gptr_registry("provider"), error = function(e) NULL)
  rows = lapply(ids, function(id) {
    p = provider_get(id)
    h = tryCatch(provider_credential(p), gptr_error = function(e) NULL)
    s = provider_status(p, h, check)
    src = if (is.null(reg)) character() else reg$source[reg$name == id & reg$state == "active"]
    data.frame(id = id, type = p[["type"]] %||% "chat", api = p[["api"]] %||% NA_character_,
               credential = if (inherits(h, "gptr_secret")) {
                 paste0(h$name, " #", h$fp)
               } else {
                 NA_character_
               },
               source = if (length(src)) src[[1]] else NA_character_, status = s$status,
               default_model = provider_default_model(p), egress = provider_egress(p),
               version = s$version, stringsAsFactors = FALSE)
  })
  df = if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(id = character(), type = character(), api = character(),
               credential = character(), source = character(), status = character(),
               default_model = character(), egress = character(), version = character(),
               stringsAsFactors = FALSE)
  }
  rownames(df) = NULL
  new_listing(df, "gptr_providers",
              footer = "Credentials show variable names and fingerprints only.")
}
```

Regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`
Expected: `Writing 'NAMESPACE'` and `Writing 'gptr_providers.Rd'`; `NAMESPACE` now contains `export(gptr_providers)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 226 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-registry.R NAMESPACE man/gptr_providers.Rd tests/testthat/test-provider-registry.R
git commit -m "feat(provider): gptr_providers() status listing"
```

---

## Plan acceptance

Every acceptance check of 05 P05 (including its review amendments), the task and test that prove it, and the command with its expected result. Run from the repository root after Task 12, with P01-P04 in place.

| # | Acceptance check (05 P05) | Proven by | Command and expected result |
|---|---|---|---|
| 1 | The four P05 test files are green | Tasks 1-12 | `Rscript --vanilla -e 'devtools::test(filter = "provider-transform\|provider-registry\|provider-usage\|catalog")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 465 ]` |
| 2 | INFRA-04: after a recorded 401 and after an abort, the projected message list has no assistant content for them and every tool call has exactly one result | Task 5, `test-provider-transform.R`: "a recorded 401 and an abort are projected out; every call has one result (INFRA-04)" (the synthetic result reads `interrupted after 2.3 s; side effects may have occurred`), plus "a call left open by a new user turn gets 'No result provided'" (a late result for a closed call is dropped) | `Rscript --vanilla -e 'devtools::test(filter = "provider-transform")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 58 ]` |
| 3 | INFRA-08: an Anthropic conversation with thinking and tools, projected for `openai-responses` and `google-generative-ai`, contains no foreign signature, encrypted item or thought signature | Task 4, `test-provider-transform.R`: "hand-off to other providers drops every foreign signature and opaque item (INFRA-08)" (both targets; the JSON form of every message is searched for each signature, the redacted payload, the thought signature and the opaque item) | same command as row 2 |
| 4 | INFRA-17: an `ollama` record added by data resolves without code; the fake provider passes `gptr_check()` (architecture section 6.18 row 17 adds: "and a plugin adapter") | Task 2 ("builtin:providers registers the architecture section 8.1 providers as data", "builtin:fake is declared here, and the fake provider passes gptr_check() (INFRA-17)", "a plugin adapter passes gptr_check() (INFRA-17)": an `inprocess` adapter loaded by P02's `ext_load()` from source `plugin:p05-plugin` at rank 5, found by `adapter_get()`, whose `gptr_check()` rows are all `ok`); Task 7 ("local providers accept unknown ids; a provider added by data resolves (INFRA-17)": the built-in `ollama` record serves `ollama/llama3.2:3b` and `ollama/qwen3.5:9b:high`, and a user-registered `labserver` record resolves with no new code) | `Rscript --vanilla -e 'devtools::test(filter = "provider-registry\|catalog-models")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 356 ]` |
| 5 | INFRA-20: the fixture usage for a turn with 1 h cache writes gives the documented dollar amount; child usage rolls up; the `route` column is present | Task 1 ("usage_cost() gives the documented dollar amounts (INFRA-20)": $0.0792 of report 07 section 5.2, the $0.0062 cache-write cost of report 03's 1-hour fixture, line 4452, and $0.0178928 for report 07's live Haiku 4.5 call with 7,641 1-hour cache writes, verification log row 26), Task 9 ("usage_row() prices a request and attributes it (INFRA-20)", "child usage rolls up to the parent session (INFRA-20)": a grandchild rolls up to the root, the per-agent sum equals the session total, `route` is a column) | `Rscript --vanilla -e 'devtools::test(filter = "provider-usage")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 51 ]` |
| 6a | `gptr_models("sonnet")` resolves offline from the snapshot in under 0.1 s | Task 8 ("resolution is offline: builtins and gptr_models('sonnet') start no transfer"); the time is checked by a command, because tests assert no wall-clock bound tighter than 5 s (conventions section 7). It is measured on an installed (byte-compiled) build in a temporary library, never the user library: under `pkgload::load_all()` R's JIT compiles every function on first use and the same call takes 0.11-0.12 s | `Rscript --vanilla -e 'lib = file.path(tempdir(), "lib"); dir.create(lib); utils::install.packages(".", repos = NULL, type = "source", lib = lib, quiet = TRUE); library(gptr, lib.loc = lib); t = system.time(gptr_models("sonnet"))[["elapsed"]]; message(sprintf("cold gptr_models(sonnet): %.3f s, under 0.1 s: %s", t, t < 0.1))'` -> `cold gptr_models(sonnet): 0.050 s, under 0.1 s: TRUE` (0.050-0.072 s measured with the 709-model snapshot; the warm call takes about 0.015 s) |
| 6b | No network request happens at load (a test counts reactor transfers) | Task 8 (same test: `builtin_providers()` runs on a recording API object and leaves `the$catalog` unbuilt, then `gptr_models("sonnet")` and `model_resolve("sonnet")` run while `reactor_http()` counts calls: 0) | `Rscript --vanilla -e 'devtools::test(filter = "catalog-models")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 130 ]` |
| R1 | Review amendment: provider records carry `offline` and static `rate` fields (IC-45, IC-64) | Task 2 (records are built with `gptr_provider()`, whose `offline = FALSE` and `rate = NULL` defaults every built-in keeps; the test asserts no built-in is `offline`); Task 3 (the `offline` fake provider needs no credential); Task 10 ("a static-rate override from the settings reaches the limiter once (IC-64)"); Task 12 (an `offline` provider needs no egress acknowledgement) | row 4 command |
| R2 | Review amendment: `provider_stream()` injects `opts$gate`, `opts$mcp_dispatch` and `opts$tool_result` so L1 adapters never call L2+ (IC-33) | Task 10 ("adapters receive the injected gate, MCP dispatcher and tool-result builder (IC-33)"); P01's `test-arch-layers.R` (no L1 -> L2 call by name) | `Rscript --vanilla -e 'devtools::test(filter = "provider-registry\|arch")'` -> `[ FAIL 0 \| WARN 0 \| SKIP n \| PASS m ]` (`n` only for a missing codetools) |
| R3 | Review amendment: the catalog carries `forced_tool_choice`, `max_images` and `cache_min` per model (IC-67, IC-71, IC-73) | Task 6 ("the shipped snapshot has the documented structure": `cache_min` 512 and `forced_tool_choice` FALSE for Sonnet 5.5), Task 7 ("a model record has every contract field": `max_images` 600, `cache_min` 512, `forced_tool_choice` FALSE for Anthropic 5.x and TRUE elsewhere) | row 6b command |
| R4 | Review amendment: `gptr_providers(check = FALSE)` spawns no process (IC-65) | Task 12 ("gptr_providers() lists providers with fingerprints and no I/O": `reactor_http()` is counted and `proc_spawn()` fails the test if called) | `Rscript --vanilla -e 'devtools::test(filter = "provider-registry")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 226 ]` |
| H | House rules: documentation generated, lint clean, lint and layering suites green | all tasks | `Rscript --vanilla -e 'devtools::document()'` -> no change to `NAMESPACE` or `man/` after Task 12; `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'` -> no lint printed; exit 0 (the namespace is loaded first because lintr's `object_usage_linter` resolves internal functions through `getNamespace("gptr")` and otherwise reports every internal call of an uninstalled tree: P01 acceptance A3 and the note below it); `Rscript --vanilla -e 'devtools::test(filter = "lint\|arch")'` -> `[ FAIL 0 \| WARN 0 \| SKIP n \| PASS m ]` |

`R CMD check` is not a P05 gate: the M1 exit check runs after P08 (05 milestones table).

---

## Self-review

### Spec coverage

| 05 P05 scope item | Task |
|---|---|
| `provider-transform.R`: projection (drop aborted/errored assistant entries, synthetic results for orphaned calls) | 5 |
| hand-off across provider/model/api; id normalisation | 4 |
| `provider-registry.R`: records for every provider of architecture section 8.1-8.2 as data | 2 (section 8.1; `typesafe` of section 8.2 is registered by P13 per 04 section 7.13 and carried in the snapshot's providers section, Task 6) |
| compat table [09 section 3] | 2 (`provider_table()` compat fields; P12 reads them) |
| auth resolvers returning handles, origin binding | 3 (`provider_credential()`: every returned handle is origin-bound, store and `auth`-function handles included; the `anthropic` provider refuses `sk-ant-oat` subscription tokens, architecture section 8.1), 2 (`provider_origin()`, `provider_base_url()`) |
| `provider_stream()` (contract section 8.4) | 10 (glue, HTTP: P04's `reactor_retry()` for in-stream retries, the retry notes forwarded to `emit`, the optional spec fields P04 reads, rate overrides, disabled providers, release of streams whose run settled), 11 (inprocess, process_jsonl: `write_close()` for `close_stdin`, only the current child reaches a turn) |
| `builtin:providers`, the `builtin:fake` declaration (IC-08) | 2 |
| `gptr_providers()` | 12 |
| `provider-usage.R`: usage rows of section 5.5, dated price tiers, TTL-split cache writes, routes, roll-up, the process System 1 log | 1 (records, tiers, cost), 9 (rows, routes, roll-up, log) |
| `catalog-models.R`: snapshot load, merge layers, aliases | 6 (snapshot), 7 (merge, aliases) |
| `provider/id[:thinking]` resolver, thinking clamp, `adist()` suggestions | 7 |
| explicit ETag refresh into `R_user_dir()` | 8 |
| `gptr_models()` | 8 |
| `inst/extdata/models.json.gz` and `dev/catalog/build_models.R` | 6 |
| Review amendments: `offline`, `rate` (with IC-64's settings and catalog overrides); injected `gate`/`mcp_dispatch`/`tool_result`; `forced_tool_choice`, `max_images`, `cache_min`; `check = FALSE` spawns no process | 2 and 10, 10, 6-7, 12 |
| 04 section 7.5 also lists `catalog_get()`, `catalog_aliases()`, `model_default()`, `usage_log_append()`, `usage_log()` | 7, 7, 8, 9, 9 |

Every acceptance check (1-6 and the four review amendments) maps to a named test in the table above.

### Placeholder scan

The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task" and "write tests for the above": none occur. Every step that changes code shows the complete code; every function the code calls is defined in this plan or in an earlier plan, and was checked against those plans' code (`dev/plan/P01-foundation.md` .. `P04-reactor-process-engine.md`). Listed in 04: P01 `gptr_abort`, `check_*`, `gptr_opt`, `setting_get`, `on_load`, `ext_service_has/get`, `hash_sha256`, `id_new`, `json_*`, `raw_to_utf8`, `write_atomic`, `gptr_user_dir`, `new_listing`, `check_running`, `block_*`, `msg_*`, `ev_new`, `acc_new`, `builtin_fake`, `gptr_fake_provider`; P02 `ext_declare_builtin`, `registry_get/names/all/diagnostic`, `gptr_provider`, `gptr_adapter`, `gptr_spec`, `gptr_register`, `gptr_registry`, `gptr_check`, `gptr_tool_result`; P03 `secret_lookup`, `secret_register`, `auth_store_get`, `child_env`; P04 `reactor_*` of 04 section 8.2, `sse_splitter`, `ndjson_splitter`, `proc_spawn`, `kill_all`, `job_add`, `job_remove`, `write_all`. Not listed in 04 but defined by an earlier plan for exactly this use: P01 `gptr_condition()` (unsignalled conditions, `utils-conditions.R`), `fake_engine()` and `fake_model_record()` (`provider-fake.R`); P04 `reactor_retry()` (Task 12: "P05 wires `opts$retry`"), `write_close()` (Task 8: "for ... P05's `close_stdin`"), `ratelimit_get()` and `ratelimit_set()` (Task 9: "settings and catalog overrides of the static rate, IC-64"). Test helpers are P01's (`local_fake_provider()`) or defined at the top of the test file that uses them (`local_settings()`, `local_test_vault()`, `local_catalog()`, `local_mock_reactor()`, `local_mock_process()`, `local_stream_adapter()`, `local_stream_log()`, `local_run()`, `local_priced_provider()`, ...), because 05 lets a plan add no helper file; `local_settings()` is therefore defined in both `test-provider-registry.R` and `test-catalog-models.R`.

### Type and name consistency with 04

- Signatures match 04 section 7.5 and section 6.2 exactly (listed under Global Constraints); argument names and defaults were compared one by one, and with the consumers' plans (P06 calls `provider_stream(target, req$context, opts, emit =, done =, run = run)` with `opts$signal`, `state`, `memo`, `run`, `session`, `gate`, `tool_result` and, when P18 is loaded, `mcp_dispatch`; P06 also reads `usage_empty()`, `usage_row()`, `usage_new()`, `usage_log()`, `project_messages()`, `model_resolve()`, `model_default()` and `adapter_get()`; P07 and P08 read `project_messages()`, `model_resolve()`, `model_default()`, `catalog_aliases()` and `provider_get()`).
- Records: usage (section 4.3) field and column names and order; model record (section 4.9) field order, plus `max_images` (IC-67, after `cache_min`) and `capabilities$forced_tool_choice` (IC-71); listing classes `gptr_models` and `gptr_providers` with the section 5.12 columns in order.
- Conditions use only section 2.2 classes and fields (`no_key`: `provider`, `variables`; `unknown_model`: `ref`, `suggestions`; `not_available`: `member`, `provided_by`; `network` under `provider`: `provider`, `status`, `curl_code`; `invalid_spec`: `kind`, `name`, `field`, `problem`; `internal`: `detail`).
- Events: the INFRA-02 types (`start`, `*_delta`, `done`, `error` with `reason`, `message`, `error = list(class, status, request_id, retry_after)`), section 4.5, with the context's `request_id` filled into the `start` event, the `error` list and the assistant message where the adapter left it `NULL` (`stream_request_id()`, Task 10), plus the transport's `retry_start` (`attempt`, `delay`, `class`) and `retry_end` (`attempt`, `ok`) notes, which P06's `run_on_event()` turns into the section 10.4 agent events.
- Options and settings keys as in sections 3.1 and 11.2 (`gptr_opt("max_attempts")` etc.); `the` fields `catalog` and `s1_log` as in section 7.0.
- The `gptr_secret` handle fields read or set (`id`, `name`, `fp`, `origin`) are those of section 5.9; the registry listing columns read (`name`, `source`, `state`) are those of section 5.5; the run fields read (`id`, `session`, `status`, `signal`) are those of section 7.6.

### Ambiguities in 04 and the reading this plan implements

The plans of P01-P04 exist in `dev/plan/`; every name this plan consumes was checked against them as well as against 04, and the readings below were checked against their code where they touch it.

1. **R shape of session entries.** Section 4.6 gives the JSON shape only. This plan reads the section 4.8 snake_case mapping: `parent_id`, `custom_type`, `first_kept_entry_id`, `tokens_before`, `details = list(kind, tool_add, origin_text)`, compaction blocks under `gptr$blocks`; P06's `entry_message()` stores an operator entry as `list(type = "custom_message", custom_type = "gptr.operator", message = <operator>)`, which is projected as is, and the flat form is accepted too.
2. **Which orphan text.** Section 7.5 names both `"interrupted after <s> s; side effects may have occurred"` and `"No result provided"`. An orphan closed by an aborted assistant turn gets the first (s = the two message timestamps apart, one decimal), every other orphan the second. Results for unknown or already answered calls are dropped so every call has exactly one result (INFRA-04).
3. **Held messages.** Operator messages (steering relays, the only "system" role gptr has) are held while results are pending (Pi's held system messages); a user message closes pending calls, as in Pi.
4. **Missing parents** ("re-parented to the nearest valid ancestor in projection", section 7.6): the previous entry in file order is used, since the missing entry's own parent is unknown.
5. **"Dropped when the target lacks reasoning replay"** (section 7.5): `reasoning_replay` is an adapter capability (section 8.1); it is read from the target model record's `capabilities`, else from the adapter registered for the target api. Only an explicit `FALSE` drops foreign thinking; otherwise it becomes text (Pi), although section 8.1 says missing capability entries mean `FALSE`, because dropping reasoning for every adapter that omits the entry would silently lose context.
6. **Compat flag names** are not fixed by 04; this plan fixes them as snake_case forms of Pi's flags (Task 2 lists them) and P12's `compat_flags()` must read these names.
7. **`typesafe`**: 05 says section 8.1-8.2 providers, but 04 section 7.13 has P13's `builtin_system1()` register `typesafe` with its rate; registering it in both would collide at rank 6, so P05 keeps it only in the snapshot's providers section (which also lets `model_resolve("jev")` report `api = "typesafe-system-one"` before P13). Likewise the `fake` row of architecture section 8.1 is served by `gptr_fake_provider()` specs (which carry their script); `builtin:fake` registers only the adapters (section 10.3).
8. **Credential binding.** `secret_value()` may be called only by P04 and P03 (section 7.3), so P05 never sees a stored value. Every handle `provider_credential()` returns is bound to the provider origin: an unbound handle (ambient discovery, `.env` values, P03's credential-store handles, an `auth` function's result) gets the origin in its own `origin` field, which P03's `secret_value()` checks first (P03 plan, Task 1, "how P05 binds a looked-up handle"); a handle bound to another origin is skipped; environment values are registered with the origin. A store record may hold a handle (`handle`/`key`) or, defensively, a raw `key` value that is registered at once. **Subscription tokens.** Architecture section 8.1 says the `anthropic` provider "refuses subscription tokens (`sk-ant-oat`)"; 04 names no owner, adapters see handles only (P12 self-review, ambiguity 9), and only `provider_credential()` reads the environment value, so the check lives there: an `ANTHROPIC_API_KEY` value starting with `sk-ant-oat` is not registered, the vault handle with the same fingerprint (P03's `fp`, the first 6 hex of `hash_sha256(value)`; ambient discovery registers the environment's values) is skipped, and when nothing else is found `gptr_error_no_key` (`provider = "anthropic"`, `variables`) says the variable holds a subscription OAuth token and points to an API key or `model = "claude_code"`. P05 never reads vault values (`secret_value()` is P03's and P04's), so a token that exists only in the vault (a `.env` value read with `gptr_env(set_env = FALSE)` or by the trusted-project discovery, or a credential-store record) cannot be recognised here; an API key held only in the vault next to an `sk-ant-oat` environment value has another fingerprint and is used.
9. **Injected callbacks (IC-33).** An L1 file cannot name `perm_check()` or `tool_result_message()` (the kernel SDK allowlist covers L3-L6 and L4 built-ins), so `provider_stream()` keeps the `gate` and `tool_result` its caller passes in `opts` (P06's `run_request()` passes the run's) and otherwise installs fail-closed defaults (deny; a minimal `msg_tool_result()`); `mcp_dispatch` is the caller's or the `mcp.dispatch_local` service bound to the session.
10. **Retries.** Section 8.1 lets a normaliser report an in-stream retryable failure through `opts$retry(info)` and says "the transport" retries only while nothing was committed. P04's plan provides that transport side as `reactor_retry(id, info)`; `opts$retry` calls it, so a retry keeps the transfer id P06 recorded (P06 cancels by that id), passes P04's backoff, wire log and `on_retry` notes, and a second `on_headers()` call resets the normaliser and splitter. P04 reports `retry_start`/`retry_end` through the `on_retry` callback of the `retry` list; `provider_stream()` forwards them to `emit` as events, where P06's `run_on_event()` expects them (P04 plan, ambiguity 3).
11. **Abort.** A reactor task watches `opts$signal$aborted` and ends the stream (`stop_reason = "aborted"`, partial message kept); for `process_jsonl` it kills the child after forgetting it. A protocol-level interrupt (the claude `control_request`) is P20's, from its normaliser, which sees `opts$signal` on every line.
12. **`close_stdin`.** The turn's JSON lines go through the non-blocking `write_all()` and P04's `write_close(p)` closes stdin once they are written (P04 plan, Task 8, written for this flag and P20's codex route); with a reused child the flag closes that child's stdin, so an adapter that keeps a child alive across turns sets it `FALSE`.
13. **`model = <spec>`.** A session-scoped provider spec (rank 0) is invisible to `registry_get()` without the session, so `model_resolve()` also accepts a `gptr_provider` spec; `provider_stream()` looks up the session's records first through `opts$session` and passes the record found as `opts$provider`, which P01's `fake_engine(model, opts)` reads so a session plays its own fake script even when another live fake has the same name (04 section 8.1 does not list `opts$provider`; adapters ignore unknown `opts` fields).
14. **Model record extras.** `max_images` is a top-level field and `forced_tool_choice` a capability (IC-67, IC-71); capabilities default to `FALSE` except `forced_tool_choice`, which defaults to `TRUE` (only Anthropic 5.x models say `FALSE`).
15. **Aliases.** Entries take the forms `{provider, family}`, `{provider, pattern}` and `{ref}`; `gemini` is limited to `^gemini-[0-9.]+-pro(-preview)?$` because models.dev files research previews under the `gemini-pro` family; on a release-date tie the undated id wins over its `-YYYYMMDD` twin. `claude_code` and `codex` resolve only once P20 registers their providers; turning `default` into a full CLI model id is P20's (section 11.10: "through the CLI provider's status()").
16. **Price tiers.** Labels are `default`, `<=Nk` (base) and `>Nk` (threshold); a dated set applies from its `from` date; missing cache rates default to 0.1x/1.25x/2x input.
17. **HTTP details of `catalog_http_get()`.** P04's `http_handle()` sends a GET when `method = "GET"` and `body = NULL`; a 304 (a 3xx, which P04 fails as class `redirect` and never follows) is read from the failure condition's `status` field, which P04's `reactor_fail_final()` sets.
18. **Provider `status()` contract.** Called as `status(check = check)` when it has a `check` formal, else `status()`; the fields read are `status`, `version` and `available`. P20 must return these names.
19. **Discovery trigger.** "Live discovery of local servers" runs on `gptr_models(refresh = TRUE, provider = <local id>)` only; the default `refresh = TRUE` refreshes models.dev.
20. **Egress column.** Local and offline providers show `ack` (no acknowledgement is needed for them, section 10.2 row 1).
21. **Image elision** (`gptr.image_elision`, IC-67) is not applied by `project_messages()`: 04 defines no image id, and P06 owns that entry; P06 or P07 apply it to the projected list.
22. **Timing.** Acceptance 6's 0.1 s bound is checked by a command, not a test (conventions section 7 forbids tighter wall-clock assertions than 5 s), on an installed build (byte-compiled, as users run it).
23. **`source` column of `gptr_providers()`.** Section 5.12 lists `credential` (`"NAME #fp"`) and `source` separately, and the handle of section 5.9 carries no credential source; `source` is read as the provider record's registry source (`builtin:providers`, `user`, `plugin:<pkg>`, `project`, `session`) of the active record.
24. **Snapshot < cache.** The refreshed cache is a complete catalog, so it replaces the shipped snapshot when its `generated` date is at least as new; an older cache left from a previous package version is ignored rather than merged (merging would resurrect models models.dev dropped).
25. **Roll-up.** 05 gives P05 "roll-up" while IC-05 gives `gptr_usage()` to P06; `usage_rollup(rows)` is a private P05 helper whose output columns are those of the aggregated `gptr_usage` view (section 5.12); P06's plan aggregates its own way (its ambiguity 12) and agrees on totals.
26. **`new_listing(df, class, footer = NULL)`.** P01's `new_listing()` prepends `gptr_` only when the class lacks it, so passing `"gptr_models"` and `"gptr_providers"` gives `c("gptr_<name>", "gptr_listing", "data.frame")` (section 5.12).
27. **Disabled providers.** Section 11.2 gives the `providers.<id>.enabled` key to P05 without its effect: a provider whose settings say `false` is skipped by `model_default()`, refused by `provider_stream()` before anything starts (`gptr_error_not_available`, `member` = the provider id, `provided_by` = `"settings"`) and listed with status `disabled`.
28. **Static-rate overrides (IC-64: "overridable by settings and catalog").** 04 names no reader; P05 owns the `providers` settings key and the catalog, so `provider_stream()` passes a `providers.<id>.rate` setting, else a `rate` in the merged catalog's providers section, to P04's `ratelimit_set()` before an HTTP transfer, and only when it differs from the limiter's current static rate (`ratelimit_set()` refills the bucket).
29. **Streams of settled runs.** P06's `run_settle()` cancels a run's transfers without callbacks (P04: "removed from the pool without callbacks"); the stream's watch task then sees a terminal run status (section 7.6) and lets go of the stream without calling `done`, so no task keeps polling and holding the run (INFRA-15).
30. **Child environment of `process_jsonl`.** Section 8.4 says `child_env(<profile>)`; P03's `provider =` argument would copy the provider's key into the child after the profile removed the billing variables (IC-65), and fails for a provider registered only for a session, so it is not passed.

### Executed validation

- Every `r` block of the plan (25 blocks) was extracted into `scratchpad/work/plans/review-P05/` and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse. `getParseData()` finds no `LEFT_ASSIGN` `<-` token (only the closure-state `<<-` of `project_structure()` and `id_alnum9_normaliser()`), and the blocks contain no `%>%`, no `:::`, no non-ASCII byte and no line over 100 characters.
- A scratch package (in the scratchpad, never the repository) was assembled from the code blocks of the **current** P01, P02, P03 and P04 plans (their `R/` files, `setup.R`, `helper-*.R` and fixtures) plus this plan's blocks, with `inst/extdata/models.json.gz` built by this plan's `dev/catalog/build_models.R --offline`. Staged assemblies ran every red and green step: each Step 2 and Step 4 summary in this plan is the measured one (Task 1: 3 failures, then 23 passes; Task 10: 10 failures and 71 passes, then 143 passes; Task 12: 2 failures and 176 passes, then 226 passes). The four files together: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 465 ]` (444 before the cross-plan consolidation, which added 21 expectations to `test-provider-registry.R`; re-measured with the seed-only snapshot on the P01-P04 plans of 2026-10-01).
- `dev/catalog/build_models.R` ran both ways: `--offline` wrote 8 models, 18 providers, 9 aliases (1.9 KB); `--api` with the models.dev `api.json` downloaded for report 09's verification wrote 709 models (21.6 KB). No model API was called.
- P01's `test-lint-rules.R` and `test-arch-layers.R`, run over the same assembly, pass for the P05 files (the arch test's only failure is its "one home per function" check, triggered by P03/P04 definitions that their plans replace in place and the scratch assembler appended). `lintr::lint()` with the repository linters (`assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`, the snake_case `object_name_linter` with the S3 regex) finds nothing in the four R files, the four test files and the build script, apart from `object_usage_linter` notes that appear for every file of the scratch package because lintr cannot load its namespace there. With the namespace loaded first (`pkgload::load_all(quiet = TRUE)`, as acceptance row H now runs it) and P01's `.lintr`, `lintr::lint()` gives 0 lints on the four R files and the four test files, notes included (cross-plan consolidation).
- On the 709-model snapshot: cold `gptr_models("sonnet")` 0.050-0.072 s on an installed build in a temporary library (0.11-0.12 s under `pkgload::load_all()`, whose functions R compiles on first use), warm 0.013-0.016 s; `sonnet` -> `anthropic/claude-sonnet-5-5` (`cache_min` 512), `opus:xhigh` -> `anthropic/claude-opus-5-5` (`xhigh`), `opus:minimal` -> `low`, `haiku` and `haiku:max` -> `anthropic/claude-haiku-4-5` (`high`, `cache_min` 4096), `gpt` -> `openai/gpt-6.1-sol`, `flash` -> `google/gemini-3.8-flash`, `gemini` -> `google/gemini-3.1-pro-preview`, `gpt-6-sol` -> `openai/gpt-6-sol` (owner tie-break), `openrouter/anthropic/claude-sonnet-5-5` -> `openrouter/anthropic/claude-sonnet-5.5`, `ollama/qwen3.5:9b:high` -> local id `qwen3.5:9b` with `high`, `jev` -> `typesafe/jev-latest`, `claude-sonet-5-5` -> `gptr_error_unknown_model` suggesting `claude-sonnet-5-5, claude-sonnet-4-5, claude-sonnet-4-6`.
- Not executed: the live HTTP paths (no network in this review), and the P06-P20 consumers, whose plans were read for the names and shapes they pass and expect.

## Plan review log

Adversarial review of 2026-10-01 against 05 (P05), 04 (sections 4, 7.1-7.6, 8, 10, 11, 15), the current P01-P04 plans (whose code was assembled and run with this plan's) and the P06-P08 plans that consume P05. Every applied fix is in the task text above; counts were re-measured.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 10 `stream_retry()` | In-stream retries were reimplemented (new transfer per attempt, own timers) instead of P04's `reactor_retry(id, info)`, which P04's plan provides for exactly this wiring; the new transfer id never reached P06 (which cancels by the id it recorded), no `retry_start`/`retry_end` reached P06's `run_on_event()`, and P04's backoff and wire-log lines were bypassed | applied | `opts$retry` calls `reactor_retry()` on the one transfer; the `retry` list passes `on_retry`, whose notes `provider_stream()` forwards to `emit`; the rest of an abandoned attempt's chunk is not pushed; tests rewritten around a scripted `reactor_retry()` |
| 2 | major | Task 10 `stream_http()` | The request spec lacked the optional fields P04 reads (`request_id`, `model`, `session_id`, the three timeouts): `opts$*_timeout` never reached the reactor and wire-log lines and transport conditions carried no request id or model | applied | `stream_http_spec()` fills them from the context, model and `opts`; asserted in the first SSE test |
| 3 | major | Task 11 `stream_process_start()` | `state$route`/`route_exit` are per session, so a replaced or killed child's late lines and exit were routed into the next turn (a codex child exiting after the next turn started ended that turn empty) | applied | only `identical(state$process, p)` routes; the old child is forgotten before it is killed (also in `stream_abort()`); new test "a replaced child's late output and exit never reach the next turn" |
| 4 | major | Task 11 `stream_process_start()` | `child_env(..., provider = <model provider>)` copies the provider's key into the CLI child after the profile removed the billing variables (IC-65), and aborts for a provider registered only for a session; 04 section 8.4 says `child_env(<profile>)` | applied | `provider` is no longer passed; the test asserts it |
| 5 | major | Task 11 `close_stdin` | The turn's prompt was written to a temporary stdin file instead of P04's `write_close(p)`, which P04's plan wrote for this flag | applied | pipe stdin, `write_all()` per line, then `write_close()`; test rewritten |
| 6 | major | Task 3 `credential_bind()` | Handles from the credential store, vault-only `.env` values and `auth` functions were returned unbound, contrary to 04 section 7.5; the self-review (ambiguity 8) contradicted the code | applied | an unbound handle gets the provider origin in its `origin` field (the binding P03's `secret_value()` checks first, P03 plan Task 1); new test for store and `auth`-function handles; ambiguity 8 rewritten |
| 7 | major | Task 10 `stream_partial()` | P01's `acc_new()$message()` never returns NULL; before a `start` event it answers api/provider/model `"unknown"`, so a build failure or early abort produced a terminal message P06 records with provider `unknown` | applied | the accumulator is used only after `start`; otherwise the message is built from the model record; test asserts provider and model |
| 8 | major | Task 10 `stream_watch()` | When P06's `run_settle()` cancels a transfer without callbacks and without setting the abort flag, the watch task kept polling every iteration and held the run | applied | the watch lets go of the stream (no `done`) once the run's status is terminal (04 section 7.6); new test |
| 9 | major | Task 10 `provider_stream()` | `opts$provider` was not set, although P01's `fake_engine(model, opts)` reads it and Task 7's `model_fake_entry()` documented it; two live fakes with the same name shared the newest script | applied | `opts$provider` = the provider record found (session first); asserted in the IC-33 test; ambiguity 13 |
| 10 | minor | Task 10 `stream_condition()` | Duplicated P01's `gptr_condition()` without the redaction hook, so adapter error text reached events unredacted | applied | `stream_condition()` calls `gptr_condition(message, class, "error", list(...))` |
| 11 | minor | Tasks 10, 12 | `providers.<id>.enabled: false` only affected `model_default()`; such a provider still streamed and listed as `ready` | applied | `provider_stream()` refuses it with `gptr_error_not_available`; `gptr_providers()` shows `disabled`; two tests; ambiguity 27 |
| 12 | minor | Task 10 | IC-64's "overridable by settings and catalog" static rate had no reader, although P04's plan provides `ratelimit_set()` for it | applied | `provider_rate_override()` and `stream_rate_sync()`; new test; Global Constraints and ambiguity 28 |
| 13 | minor | Task 7 `model_pick()` | With two credentialed resellers and a keyless owner, the tie went to the owner, which has no credential (report 09 `break_tie()` restricts to authenticated rows first) | applied | ties are restricted to the credentialed rows before the owner rule; an ambiguous id says so in the message; test with a `bedrock` fixture row |
| 14 | minor | Task 4 `handoff_transform()` | `reasoning_replay` was read only from the model record, which never carries it (an adapter capability, 04 section 8.1), so "dropped when the target lacks reasoning replay" was dead code | applied | `handoff_thinking_as_text()` falls back to the registered adapter's capability; test with an adapter declaring `FALSE`; ambiguity 5 |
| 15 | minor | Task 1 test | The documented 1-hour-cache-write turn of report 07 (live call 2, $0.0178928, verification row 26) was not used | applied | expectation added (INFRA-20) |
| 16 | minor | Task 8 test | Acceptance 6b's "no network at load" did not show that registration builds no catalog | applied | `expect_null(the$catalog)` after `builtin_providers()` |
| 17 | major | Plan acceptance 6a | The timing command used `pkgload::load_all()`; with the real P01-P04 code the call takes 0.11-0.12 s there (JIT compilation), so the command printed `FALSE` | applied | measured on an installed build in a temporary library (0.050-0.072 s); ambiguity 22 |
| 18 | major | Steps 2 and 4 of Tasks 1-12, acceptance | The expected summaries were computed with stand-ins and were wrong against the real P01-P04 code (for example Task 2: 29 passes claimed, 34 measured; Task 7 red: 5 failures claimed, 8 measured; total 374 claimed, 404 measured before this review) | applied | every summary re-measured on staged assemblies of the current P01-P04 plans plus this plan (total 444) |
| 19 | minor | Task 7 test | A test name made a line of 102 characters (`line_length_linter(100)`) | applied | shortened |
| 20 | minor | Self-review | Stale statements: "No plan of P01-P04 exists yet", ambiguities 8, 10, 12 and 26 described superseded code or an open question P01 answers | applied | intro and items rewritten; items 27-30 added; executed validation rewritten with what was run |
| 21 | minor | Task 5 `entry_compaction_cut()` | Concern that an older compaction entry inside the kept range is projected as a second summary | rejected | Pi's `buildContextEntries()` keeps every kept entry, compaction entries included (`session-manager.ts`), and P05 follows it |
| 22 | minor | Task 10 `opts` | The earlier review draft read `run$gate`, `run$tool_result` and `run$mcp_dispatch` from the run as a fallback | rejected | those are not `gptr_run` fields of 04 section 7.6; P06's `run_request()` passes them in `opts` |
| 23 | minor | Task 11 abort of `process_jsonl` | `kill_all()` (2 s grace) blocks the reactor and skips the claude interrupt `control_request` | rejected | 04 section 8.5 makes the protocol interrupt P20's, from its normaliser; the glue's kill is the fallback 04 describes ("then `kill_all()` after the grace period"); recorded as ambiguity 11 |

## Cross-plan consolidation log

Cross-plan check of 2026-10-01 (obligations and trace lenses) against 04, 03, 05 and the related plans (P01, P02, P03, P12, P14). Every applied change is in the task text above; the test counts of Tasks 2, 3 and 10-12 and of acceptance rows 1, 4 and R4 were re-measured on staged scratch assemblies of the current P01-P04 plans plus this plan (Task 2: 4 failures and 1 pass, then 40 passes; Task 3: 6 failures and 41 passes, then 71; Task 10: 10 failures and 71 passes, then 143; Task 11: 9 failures and 147 passes, then 176; Task 12: 2 failures and 176 passes, then 226; the four files 465; `provider-registry|catalog-models` 356). Every `r` block (25) was re-extracted and parses with `Rscript --vanilla`; no `<-`, `%>%`, `:::`, non-ASCII byte or line over 100 characters.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| C1 | obligations | minor | Task 10 `stream_emit()` | applied | Valid: 04 section 4.5 puts `request_id` in the `start` event, in the `error` event's `error` list and (section 4.1) in the assistant message; P12's normalisers emit `NULL` because `parse(model, opts)` sees no request context (P12 ambiguity 4), and only P05 holds `context$request_id`. New private `stream_request_id(st, ev, type)`, called by `stream_emit()` after the start check, fills `ev$request_id` (`start`), `ev$error$request_id` (`error`) and `ev$message$request_id` (`done`/`error`) with `%||%`, so an id the adapter set is kept; `stream_finish()` also fills the message handed to `done(msg)`. The test adapter now leaves the id `NULL` like P12's; the first SSE test asserts the `start` event's id, the `done` event's message id and the delivered message's id, and the "retryable error after a delta" test asserts the `error` list's id and the message's id (+5 expectations). |
| C2 | obligations | minor | Task 3 `provider_credential()` | applied (refined) | Valid: architecture section 8.1 says the `anthropic` provider "refuses subscription tokens (`sk-ant-oat`)" and no plan implemented it (P12 ambiguity 9). For `id == "anthropic"` an environment value starting with `sk-ant-oat` is skipped in the `Sys.getenv()` fallback, and in the `secret_lookup()` loop the vault handle is skipped when its fingerprint equals that value's (P03's `fp` = first 6 hex of `hash_sha256(value)`) rather than whenever the environment holds a token, so an API key held only in the vault (a `.env` value that was not exported) is still used. With nothing else found, `gptr_error_no_key` (`provider = "anthropic"`, `variables`) says "ANTHROPIC_API_KEY holds a Claude subscription OAuth token (sk-ant-oat...), which the API provider refuses; use an API key, or model = "claude_code" for the subscription CLI." New Task 3 test with a fake `sk-ant-oat01-...` value (+10 expectations: refusal, message, no value in the message, nothing registered, the mirrored vault handle refused, a vault-only API key used and bound); Interfaces, Produces, the Task 3 paragraph, ambiguity 8 (vault-only tokens cannot be checked: P05 never reads vault values) and the spec-coverage row updated. |
| C3 | obligations | minor | Plan acceptance row H | applied | Valid: P01 acceptance A3 and its note: an uninstalled tree makes lintr's `object_usage_linter` report every internal call. Row H now runs `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'` -> no lint printed; exit 0. Measured: with the namespace loaded and P01's `.lintr`, 0 lints in the four R files and the four test files; executed validation updated. |
| C4 | trace | minor | Task 2 tests; Plan acceptance row 4 | applied | Valid: architecture section 6.18 row 17 asks that "the fake provider and a plugin adapter pass `gptr_check()` (`test-provider-registry.R`; P05)", and only the fake provider was tested. New Task 2 test "a plugin adapter passes gptr_check() (INFRA-17)": P02's `ext_load()` loads a factory registering `gptr_adapter("p05-plugin", transport = "inprocess", stream = <fake_stream() playing a one-line reply>)` from source `plugin:p05-plugin` at rank 5; the test asserts the load, that `adapter_get()` finds the same record as `registry_get()` (so the test fails until P05's code exists), its transport, that its `stream` returns a generator, and `all(gptr_check(a)$ok)` (without P12 P02 checks the fields; with P12 its `check_adapter()` passes `inprocess` adapters as `adapter.replay`); `withr::defer(ext_unload("plugin:p05-plugin"))` removes it (+6 expectations). Task 2 Interfaces list `ext_load()`, `ext_unload()`, `gptr_adapter()` and `fake_stream()`; row 4 cites the test and its count is re-measured, as are rows 1 and R4. |
| C5 | trace | minor | Plan acceptance row H | applied (same change as C3) | Duplicate of C3; the one replacement covers both. |
