# Track 04b - Ollama local chat and decision models

Research date: 2026-10-03. Scope: REQ-13/14/15/20, provider discovery, P05/P12/P13.
This supplements reports 04/04a and 09. **VERIFIED (documentation)** means an official
source was inspected; **VERIFIED (local)** means a synthetic live request was
observed. Untested cases are identified explicitly. This report changes the design, not the implementation.

## Provider roles

**VERIFIED (documentation).** Retain GPTR's planned `openai-completions` adapter for
ordinary Ollama chat at `http://127.0.0.1:11434/v1/chat/completions`. Ollama supports a
subset of the OpenAI interface; chat streaming, tools, vision and thinking must be
gated by the selected model's capabilities and compatibility profile. Local requests
need no real API key; clients that require a value can use a dummy value. The same
local server can also access cloud models, so a loopback URL alone does not establish
local inference. [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).

Keep decision models in GPTR's separate typed decision path. Ollama's native
`POST /v1/systemone` accepts decision questions rather than conversation messages.
Clef and Clef Flash require **Ollama 0.35.1 or later**; generic System One support
began in 0.35.0. Decision models must not appear as chat/code-generation choices.
[Decision guide](https://docs.ollama.com/capabilities/decision),
[0.35.1 release](https://github.com/ollama/ollama/releases/tag/v0.35.1).

## Models and resource planning

**VERIFIED (documentation).** Cloudflare's Clef is a 27B model; Clef Flash is 9B.
Both accept text and images and produce schema-bound decisions in a non-autoregressive
pass. Their weights use Apache-2.0. Cloudflare describes compatibility with Jev's
primitives, but benchmark quality varies by task; this is not evidence of universal
equivalence or superiority. [Cloudflare announcement](https://blog.cloudflare.com/clef-decision-models/).

The inspected official defaults are `clef:latest` at approximately 18 GB, Q4_K_M,
and `clef-flash:latest` at approximately 11 GB, Q8_0; both include vision projectors.
These are download sizes, not peak memory requirements. Preserve exact tags and
digests in validation records because aliases can move.
[Clef artifact](https://ollama.com/library/clef:latest),
[Clef Flash artifact](https://ollama.com/library/clef-flash:latest).

Context documentation disagrees: library listings display 256K, model readmes describe
64K, and the inspected default artifacts configure `num_ctx` as 16,384. GPTR must record
the effective loaded context and enforce that limit, not promise the largest advertised
number. Downloading a larger model or expanding context is an explicit setup action.
[Clef library](https://ollama.com/library/clef),
[Clef Flash artifact parameters](https://ollama.com/library/clef-flash:latest).

## Decision wire contract

**VERIFIED (documentation).** Required fields are `model`, `state` and `questions`.
`state` is nonempty text, an object, or an array; it is not a chat-message envelope.
Questions share the state, and answers are not fed into subsequent questions.
Optional `images` contains raw base64 PNG/JPEG/WebP content, not URLs or data URLs;
image input requires compatible vision weights. Optional `keep_alive` controls model
residency. The endpoint returns one JSON response with `model`, named `answers` and
token `usage`. It does not support streaming, video, tools or generation controls.
Text-only bodies are limited to 64 KiB; image-bearing bodies to 32 MiB including
encoding. Complete input must fit the loaded context; it is not silently truncated.
Compatible GGUF weights and a scoring-capable runner are required: listed MLX or
Safetensors variants are not interchangeable with this endpoint.
[System One API](https://docs.ollama.com/api/systemone).

There are 1-64 named questions, each with a `type` and `instructions`:

| Type | Criteria | Result meaning |
|---|---|---|
| `noul` | Optional true/false descriptions | Numeric probability of true, not a Boolean |
| `choice` | 2-26 ordered option keys with text or null descriptions | Winning key, candidate probabilities, confidence |
| `score` | 2-26 ordered level descriptions | Fractional weighted zero-based level, legend, probabilities, confidence |

Preserve option order and the score's original scale. Do not normalize scores to
0-1 or assume Jev's documented candidate limits apply. Ollama confidence measures
distribution concentration, `1 - H(p)/log(N)`, rather than calibrated correctness;
it must not inherit Jev-specific confidence formulas. Noul has no separate confidence
field. [Official schema](https://github.com/ollama/ollama/blob/main/docs/openapi.yaml),
[scoring implementation](https://github.com/ollama/ollama/blob/main/decision/systemone.go).

## Discovery and locality

**Design requirement grounded in official metadata.** Discovery is opt-in, never a
package-load side effect. Inspect `/api/version`, `/api/tags` and `/api/show`; distinguish
completion, decision, tools, thinking and image support. Inspect projector metadata
when determining decision vision support; do not infer it from chat capability.
Store model format, quantization, configured context and digest.
[Show metadata](https://docs.ollama.com/api-reference/show-model-details),
[model listing](https://docs.ollama.com/api/tags).

For local-only operation, reject upstream `remote_model`/`remote_host` metadata and
cloud model selections, and fail closed when locality cannot be established. Never
silently fall back to hosted Jev or a cloud LLM. Ollama additionally supports disabling
cloud features through `OLLAMA_NO_CLOUD=1`; this needs a server restart and is an explicit
operator setting, not something package loading should change.
[Official response types](https://github.com/ollama/ollama/blob/main/api/types.go),
[local-only configuration](https://docs.ollama.com/faq#how-do-i-disable-ollama-cloud-features).

## Verification log

**VERIFIED (documentation):** official references above were inspected on the research
date. **VERIFIED (local, 2026-10-03):** synthetic HTTP tests from R using only
`curl` and `jsonlite` ran against Ollama 0.35.1. No GPTR package implementation,
cloud credentials or project data were used.

| Check | Observed result |
|---|---|
| Qwen3 1.7B, OpenAI-compatible chat | HTTP 200; arithmetic answer in assistant content |
| Streaming chat | SSE content completed and `[DONE]` received |
| Tool round-trip | `sum_numbers(7, 5)` requested; tool result returned; assistant answered 12 |
| Clef Flash structured state, three question types | HTTP 200; P(needs R) 0.9595; category `analysis`; fractional readiness score 1.9176 on levels 0–2 |
| Negative text control | P(needs R) 0.0044 for a poetry request |
| Blue rectangle image | selected blue; P(blue rectangle) 0.9728 |
| Paired red rectangle image, same text/questions | selected red and P(blue rectangle) below 0.5 |
| URL in image field | rejected with HTTP 400 |
| Clef Flash used as a chat model | rejected with HTTP 400 |
| Probability/score checks | finite values, probability bounds/sums and expected-score reconstruction passed |

The tested decision artifact was `clef-flash:latest`, GGUF Q8_0, digest
`2aa4d39fd93b09c84236c5721a4a482c9c376ec32028f7a800b192d33adaad45`.
The loaded context was 16,384. `/api/show` advertised only `decision`, despite
successful image inference: absence of a separate `vision` flag is not sufficient
to reject images when the verified projector/version metadata establishes support.
Both test models were unloaded after requests; downloaded weights remain installed.

The first chat attempt exhausted a 64-token budget in the reasoning field and
returned empty content with `finish_reason = "length"`. Repeating with a
512-token budget completed. This is a useful compatibility case: a successful
HTTP status alone is not a successful answer, and hidden reasoning consumes the
output budget. It is not a measured regression in GPTR.

These are feasibility/conformance smoke checks, not an accuracy, calibration,
latency or token-efficiency benchmark. The larger Clef model was not downloaded
or tested. Cloud-marker rejection, old-server handling and future GPTR cache,
permissions and routing behavior remain implementation acceptance requirements.

Acceptance should exercise ordinary chat, streaming and a tool round-trip with an
appropriate installed model; then test all three decision types with synthetic text
and a synthetic image whose answer is not disclosed by its text state. Check answer
IDs, finite ranges, probability sums, score reconstruction and usage. Verify actionable
errors for missing models, unsupported capabilities, invalid schemas and context/body
limits, plus rejection of cloud selections in local-only mode. Record server version,
model tag/digest, quantization, effective context, elapsed time and actual outcomes.
Smoke success establishes compatibility, not decision calibration or task accuracy.
