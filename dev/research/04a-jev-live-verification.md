# 04a — Jev (System One) live verification from R

First-hand verification by the lead designer on 2026-09-29, R 4.4.3,
httr2 1.2.2, macOS. Scripts: `scratchpad/work/main/jev_live.R`,
`jev_live2.R`. Every statement below was observed in a real response.
This note supplements `04-system-one-jev.md`; where they differ, this note
wins because it was measured against the live API.

## Endpoint and authentication

| Item | Value |
|------|-------|
| Base URL | `https://api.typesafe.ai/v1/` |
| Decision endpoint | `POST https://api.typesafe.ai/v1/systemone` |
| Model list | `GET https://api.typesafe.ai/v1/models` |
| Auth header | `Authorization: Bearer <key>` |
| Body encoding | JSON (`Content-Type: application/json`) |
| Response content type | `application/json` (not streamed) |
| Request id header | `x-typesafe-request-id` |
| Rate-limit headers | none observed |
| Canonical env var | `TYPESAFE_API_KEY` (Pi: `packages/ai/src/env-api-keys.ts:93`) |

Available models (from `GET /v1/models`):

```json
{"models":[
 {"name":"jev-latest","description":"The latest iteration of TypeSafe's System One Model: Jev","release_date":"2026-09-10T18:38:01.391457+00:00"},
 {"name":"jev-preview","description":"A preview version of `jev-latest`: should be better in most ways","release_date":"2026-09-10T18:39:06.057655+00:00"}
]}
```

A response to `jev-latest` reports the resolved version: `"model": "jev-1.13.0"`.

## Request

```json
{
  "model": "jev-latest",
  "state": { "text": "A golden retriever puppy fetched the ball and wagged its tail." },
  "questions": {
    "is_dog":   { "type": "noul",   "instructions": "Does `text` describe a dog?",
                  "criteria": { "true": "The text describes a dog", "false": "The text does not describe a dog" } },
    "animal":   { "type": "choice", "instructions": "Which animal does `text` describe?",
                  "criteria": { "dog": "A dog", "cat": "A cat", "bird": "A bird", "other": "None of these" } },
    "cuteness": { "type": "score",  "instructions": "How positive is the sentiment of `text`?",
                  "criteria": ["Very negative", "Neutral", "Very positive"] }
  }
}
```

- `state` is a JSON object of named program state. Instructions refer to state
  fields by name in backticks.
- Several questions can be asked about one state in a single request; all are
  answered together.
- Question types on the wire are exactly `noul`, `choice`, `score`.
  **`"type": "bool"` is rejected with HTTP 400.** The friendly name `bool`
  exists only in Pi's public API; gptr must translate to `noul`.
- `criteria` is an object keyed `true`/`false` for `noul`, an object keyed by
  choice label for `choice`, and an **array** of level descriptions for `score`.
  With jsonlite, a score's criteria must be built as an unnamed `list(...)` so
  it serialises as a JSON array, and the body must be sent with
  `auto_unbox = TRUE`.

## Response (verbatim)

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "is_dog": { "type": "noul", "noul": 0.99 },
    "animal": { "type": "choice", "choice": "dog", "confidence": 1.0,
                "probabilities": { "other": 0.0, "bird": 0.0, "dog": 1.0, "cat": 0.0 } },
    "cuteness": { "type": "score", "score": 1.98, "confidence": 0.97,
                  "legend": { "0": "Very negative", "1": "Neutral", "2": "Very positive" },
                  "probabilities": { "0": 0.0, "1": 0.02, "2": 0.98 } }
  },
  "usage": { "input_tokens": 443, "output_tokens": 79 }
}
```

Observations that matter for the R design:

- A `noul` answer is a **probability of true**, not a boolean. gptr decides the
  logical value by thresholding (default 0.5) and keeps the probability.
- `choice.probabilities` key order is **not** the request order. gptr must
  reorder by the requested criteria names, never by position.
- A `score` is a continuous expectation over zero-based level indices
  (`1.98` on a 0–2 scale). The response also carries `legend` and a per-level
  `probabilities` object; Pi's TypeScript types do not declare these two
  fields, so they are easy to miss.
- Probabilities are rounded to two decimals.

## Errors (verbatim)

| Cause | Status | Body |
|-------|--------|------|
| Unknown question type | 400 | `{"detail":{"error_type":"api_usage_error","message":"Invalid request."}}` |
| Unknown model | 400 | `{"detail":{"error_type":"api_usage_error","message":"Unknown model: no-such-model"}}` |
| Invalid key | 401 | `{"detail":{"error_type":"authentication_error","message":"Cannot authenticate with the server. Please check your API key and try again."}}` |

The error envelope is `detail.error_type` + `detail.message`. Schema errors
give only "Invalid request." with no field path, so **gptr must validate
questions client-side** and produce its own precise messages before sending.

## Latency and throughput

| Workload | Wall time |
|----------|-----------|
| 1 request, 3 questions | 342 ms |
| 20 requests, 1 question each, `httr2::req_perform_parallel(max_active = 10)` | 407 ms total, 20/20 HTTP 200 |

Twenty vectorised decisions cost about the same wall time as one. This
confirms that a vectorised System One call over an R vector is practical inside
ordinary control flow, using only `httr2` and no worker processes.

Classification quality on the 20-sentence check ("does the text describe a
dog?") was 20/20 correct, including the near-miss "A wolf howled." (0.05).

## Verified R request builder

> **Caveat added after track 04 reported back.** The builder below ran
> correctly against the live service, but track 04 found that
> `httr2::req_perform_parallel()` (httr2 1.2.2) retries HTTP 429/503 responses
> without an upper bound and ignores `max_tries`; a prototype against a
> throttling mock looped for over 180 s. The production implementation must
> therefore disable httr2's own retry on every request
> (`req_retry(max_tries = 1, retry_on_failure = FALSE,
> is_transient = function(resp) FALSE)`) and run its own bounded retry rounds
> that resubmit only the failed elements, honouring `retry-after`. Use the
> builder in `04-system-one-jev.md` for implementation; the code here documents
> what was measured.

```r
s1_request <- function(state, questions, model = "jev-latest",
                       key = Sys.getenv("TYPESAFE_API_KEY")) {
  httr2::request("https://api.typesafe.ai/v1/systemone") |>
    httr2::req_headers(Authorization = paste("Bearer", key),
                       .redact = "Authorization") |>
    httr2::req_body_json(list(model = model, state = state,
                              questions = questions), auto_unbox = TRUE) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_timeout(30)
}
reqs  <- lapply(texts, function(t) s1_request(list(text = t), questions))
resps <- httr2::req_perform_parallel(reqs, max_active = 10,
                                     on_error = "continue", progress = FALSE)
p   <- vapply(resps, function(r) httr2::resp_body_json(r)$answers$is_dog$noul, 0)
out <- structure(p >= 0.5, class = c("gptr_decision", "logical"), prob = p)
```

## The maintainer's key file

`/Users/wanjun/Downloads/jev-key.env` contains one line of the form
`jev-key=<value>`. The variable name contains a hyphen, so it cannot be
exported by a shell, but R reads it fine. The `.env` loader must treat
`jev-key`, `JEV_KEY`, `JEV_API_KEY` and `TYPESAFE_API_KEY` as aliases for
`TYPESAFE_API_KEY`.

## Open points

- Input size limit, maximum number of questions per request, and the 255-choice
  ceiling from the announcement were not probed.
- No rate-limit headers were returned; behaviour under throttling is unknown.
- Image inputs are announced as not yet available.
