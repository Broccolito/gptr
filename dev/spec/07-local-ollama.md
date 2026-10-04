# Local Ollama conversation and decision models

Status: accepted design amendment, 2026-10-03, requested by the maintainer.
Authority: interface-contract section 15, **IC-74**, incorporates this document.
It overrides earlier Jev-only assumptions in the architecture and plan examples.
This is a design specification; no GPTR implementation is introduced here.

## 1. Required behavior

Ollama is a first-class optional provider for both ordinary conversational LLMs
and native System One decision models. One server may host both kinds at once.
The core remains pure R with the existing Imports; Ollama is an external service
needed only when that provider is selected. A user-supplied compatible endpoint
is supported as well as the default `http://127.0.0.1:11434`.

| Model role | Model reference examples | Adapter and endpoint | Result |
|---|---|---|---|
| Conversation and agent work | `ollama/qwen3:1.7b`, another installed capable LLM | existing `openai-completions`, `/v1/chat/completions` | `gptr_session` |
| Native typed decisions | `ollama/clef-flash`, `ollama/clef` | new `ollama-system-one`, `/v1/systemone` | `gptr_decision`, `gptr_choice`, or `gptr_score` |
| Hosted typed decisions | `typesafe/jev-latest`, alias `jev` | existing `typesafe-system-one` | the same typed R classes |

Clef and Clef Flash require Ollama **0.35.1 or later**. They are native decision
models, not conversational models asked to emit JSON, and do not implement an
agent's tool-calling loop. General LLM tool calling, images, structured output,
streaming and reasoning are enabled only when the selected model supports them.
See the [Ollama release](https://github.com/ollama/ollama/releases/tag/v0.35.1)
and [decision API](https://docs.ollama.com/api/systemone).

## 2. Discovery, routing and model identity

P05 uses `/api/version`, `/api/tags`, and `/api/show` when local discovery is
explicitly requested or needed for a selected Ollama model. No discovery occurs
on package load. Preserve tag, model digest, capabilities, format, quantization,
configured context, and server version. Keep capability booleans in the existing
`capabilities` field; use typed metadata fields for version, digest and limits.
Do not coerce those fields into booleans.

Resolve **model** `type` and `api`, rather than assuming every model has its
provider's default type. `decision` capability selects `type = "classifier"`
and `api = "ollama-system-one"`. Other models use the conversational adapter
when their capabilities permit it. P13 must not reject Clef because the parent
`ollama` provider defaults to chat; both P08 routing and P13 dispatch use the
resolved model. Unknown local IDs require discovery or explicit trusted model
metadata; a model name alone must not grant tools or vision capabilities.

Add an optional model `decision` record: `types` (supported type names),
`images` (logical), `server_min` (version string), `max_questions`,
`max_options`, `max_request_bytes_text`, `max_request_bytes_images`, and
`max_active`. These are validated by type and kept outside the boolean map.
Local Clef concurrency defaults to **one active request per server**; the
global System One cap remains an upper bound. Do not inherit Jev's cloud rate
limits or dollar prices. User changes to concurrency are explicit.

The effective context is the configured and supported runtime context, not the
largest number on a catalog page. Conflicting tag/model-card limits must not
produce an inflated advertised capacity. Cache identity includes model digest;
if an immutable identity is unavailable, do not reuse a durable cached decision
across discoveries of a mutable tag without revalidation.

## 3. Native decision request and normalized response

`ollama-system-one` is a non-streaming `http_json` classifier adapter owned by
P13 (`R/s1-ollama.R`). It accepts text or structured JSON state, named questions,
and optional images. It constructs `/v1/systemone` from the configured Ollama
origin without duplicating `/v1`. It uses the shared curl reactor, cancellation,
redaction, bounded retries and typed-error machinery. Loopback needs no API key;
never attach a Jev/cloud credential to an Ollama request.

The adapter contract normalizes answers exactly once into a named list keyed by
question ID, independent of provider wire/error schemas. Canonical records are:

| Type | Canonical fields |
|---|---|
| `noul` | `list(type = "noul", prob = <P(true)>)` |
| `choice` | `list(type = "choice", choice = <label>, probabilities = <named numeric vector>, confidence = <number>)` |
| `score` | `list(type = "score", score = <fractional zero-based level>, probabilities = <named numeric vector>, confidence = <number>, legend = <named character vector>)` |

The internal classifier callback is amended to
`parse(model, status, headers, body, questions)`. The caller passes the original
ordered question schema. Every native parser and in-process `run()` returns
this canonical shape; TypeSafe, emulation and P01's fake classifier must agree.
Adapters map wire `noul` to canonical `prob` and order probabilities against
the request. Common `s1_dispatch()` validates/consumes canonical fields and
must not call the Jev wire parser a second time. Keep provider-specific raw
decoding inside its adapter, rather than silently accepting two output shapes.
Validate finite values, bounds, expected answer IDs, allowed option names,
probability sums and score reconstruction. Preserve request option order,
including tie behavior. Never convert a fractional score into an integer
category or a normalized 0–1 score without an explicit user transformation.

Ollama's decision API currently accepts 1–64 questions and 2–26 choice options
or score levels. `noul` is thresholded by the existing public `threshold`
option. Choice/score `confidence` describes distribution concentration; it is
not the probability that the answer is scientifically correct. Preserve and
validate Ollama's wire confidence (`1 - H(p)/log(N)`, with zero probabilities
contributing zero entropy); never apply Jev's different fallback formula.
Native decision
probabilities are not automatically empirically calibrated. `meta$calibrated`
may be `NA` (unknown); claiming `TRUE` requires recorded task/domain-specific
calibration evidence. Emulation remains explicitly uncalibrated.

Extend decision metadata with provider ID, adapter API, execution kind
(`native`/`emulated`), locality (`local`/`remote`/`unknown`), model digest,
server version and optional calibration provenance. `engine` may be `ollama`,
`typesafe`, another registered provider, or the existing emulation identifier.
Do not hard-code the set to TypeSafe versus emulated. Typed output formatting
must say unknown when calibration is unknown, and preserve the existing R
control-flow behavior.

## 4. Images and state handling

Add the optional core call option `.opts$system1_images`: a list of image records
with `data` (raw bytes) and `mime` (`image/png`, `image/jpeg`, `image/webp`).
P08 validates the option shape; P13 validates it against the resolved model and
adapter limits before encoding. It applies the same explicitly supplied image
list to each state in a batch. Different images per state require separate
calls in v1; there is no implicit recycling or attachment from the workspace.

The Ollama adapter encodes raw base64 strings, not URLs or data URLs. Images are
shared across the questions for that state. Do not silently replace an image
with its filename, object description, or text-only request. Unsupported images,
video, generation controls or invalid payload sizes give an actionable error.
The current endpoint limits text request bodies to 64 KiB and image-bearing
bodies to 32 MiB; respect the loaded context and fail explicitly on overflow.
These limits are adapter/version metadata, not universal Jev limits.

S1 cache keys include effective origin/path, adapter, server/model identity,
ordered questions, state and ordered image-byte digests plus MIME types. Use
the existing salted hashing policy; do not persist raw states or images in the
decision cache. Live cache lookup validates the currently resolved model identity.
Offline replay uses the frozen identity recorded with the selected result plus
locally supplied image digests; it never calls discovery, `/api/show`, or another
provider endpoint. Reject mismatched pinned identities/images or missing identity
evidence rather than inventing a fresh result. Recorded replay does not establish
that a mutable server tag still names those same weights today. Document
recording follows its existing consent and redaction rules; provider, model,
decision and image provenance are sufficient by default.

## 5. Locality, availability and resource policy

Default Ollama selection is local-only. A loopback connection by itself does
not prove local inference: Ollama can proxy cloud models. A protected user/session
provider setting `providers$ollama$local_only` is a scalar non-NA logical and
defaults to `TRUE`. Its public configuration shape is
`gptr_config(providers = list(ollama = list(local_only = TRUE)), .scope = "user")`.
Only an explicit human user/session configuration can relax it; project settings,
per-call options, model code and extensions cannot do so. `TRUE` is stricter than
`FALSE`; freeze this control with the run's non-removable safety snapshot, and
apply any project restriction only as tightening. Before sending state,
validate the effective endpoint and selected installed model; reject cloud
selectors, `remote_host`/`remote_model` markers, and ambiguous execution locality.
A project or model-generated call cannot relax this setting. No automatic cloud
fallback is allowed. A remote Ollama endpoint or cloud route requires explicit
user configuration, local-only disabled, and the normal egress acknowledgement.
Existing redirect refusal and origin-bound credential rules still apply.

Locality validation must apply to the whole requested workflow: a local decision
model does not make a later cloud LLM, MCP server or network tool local. Treat
server metadata as the user's trusted service declaration, not a security
sandbox or protection against a malicious server. Explain when the route leaves
the machine. See [Ollama local-only settings](https://docs.ollama.com/faq#how-do-i-disable-ollama-cloud-features).

Selecting a local native classifier makes System One usable without a Jev key.
Prompt inclusion and `model_default("system1")` depend on the configured model
and verified capability/availability. They must not depend solely on a TypeSafe
environment variable. Real local inference is still a live call: `offline`
remains reserved for fake providers, and replay mode refuses an uncached call.

Do not start/install/update Ollama or download models from package load, examples,
ordinary inference, or tests. Missing server/model errors explain the required
manual action. Explicitly authorized model downloads are an environment setup
operation. Do not unload unrelated user models. Cancellation and concurrency
must avoid stranding owned requests; residency controls are adapter-specific.
Local usage records actual tokens and elapsed time and zero metered API charge,
without claiming zero compute/energy cost. Missing usage remains unknown.

## 6. Plan ownership and acceptance amendment

The 25-plan structure is retained. This amendment adds required work to those
plans; older literal code snippets and exact PASS counts are historical wherever
they conflict with IC-74. Reconcile those tasks before executing them verbatim.

| Owner | Required design delta and acceptance |
|---|---|
| P01/P02 | Fake classifier fixtures return canonical answers; callback/record validation accepts the amended classifier signature and metadata |
| P05 | Mixed chat/classifier catalog, typed decision metadata, version/capability discovery, digest/locality checks and zero local API pricing; offline mixed-provider fixtures |
| P07/P08 | Model-level route selection; local classifier prompt without keys; validated image option; protected local-only configuration and effective-origin egress checks |
| P12 | Retain Ollama OpenAI chat compatibility; verify streaming, tool support and reasoning/output limits for capable models; classifier adapters receive conformance coverage |
| P13 | Own `s1-ollama.R` and matching tests; canonical answer normalization, images, cache/provenance, no key, per-server admission, calibration semantics; Jev behavior remains separately tested |
| P15 | Preserve local model/digest/image provenance and redacted, consented workflow records; replay invokes no provider |
| P24/P25 | Mixed local/cloud workflow fixtures, quality-adjusted token/cost reporting, local-only failure tests and optional local integration documentation |

Offline acceptance must cover mixed catalogs, all three answer types, shuffled
probability keys, image cache invalidation, unknown calibration, missing/old
servers, unsupported models/formats/modalities, wrong endpoints, cloud markers,
remote overrides, attempted project/call/model relaxation of `local_only`,
replay without discovery, missing recorded identities, replay cache misses and
no hidden fallback. A local-only
selection must fail before egress if locality cannot be established.

Opt-in live tests use `GPTR_LIVE_TESTS=true` plus a running server and installed
models; they skip with clear reasons when unavailable. Cover a conversational
model and Clef Flash; test Clef separately when installed, never infer its result
from Flash. Use synthetic text/images, no project data or keys. Confirm logical,
choice and fractional score semantics, image sensitivity using paired images,
and expected failures for chat on decision-only models and invalid images.
Smoke tests establish API feasibility, not scientific accuracy or general
performance. Research evidence is in `../research/04b-ollama-local-models.md`.
