# Provider model inventories — 2026-11-02

Implemented native provider inventory on explicit `gptr_models(provider = ..., refresh = TRUE)`
and before real use of a known selected provider. Pure listing, resolution and defaults remain
offline. Egress and replay refusals precede credential lookup and HTTP. Native Ollama selected-model
evidence and local-only policy retain their existing behavior; explicit inventory uses the same
guards. No provider inference or live credential test was performed in this lane.

The existing process discovery layer now accepts sparse callback records as well as the older
data-frame shape. A five-minute process cache bounds successful and failed advisory attempts;
explicit refresh bypasses it. The cache uses endpoint hashes, provider lifecycle and native API
credential fingerprints, never credential values. Failure retains prior catalog entries. An empty
successful response replaces only the provider discovery layer. `availability` and `checked_at`
record historical provider advertisement, with stale and failed refresh reporting; they do not
establish entitlement, inference capability or billing access. Unknown remote ids give an explicit
provider-refresh hint without initiating discovery. Newly advertised ids gain only reported fields;
absent tools, token limits and prices are not guessed. Session credential presence uses metadata and
handles without unlocking keyring during ordinary offline lookup.

Native listing requests use the existing reactor/HTTP/credential services, at most four pages,
four seconds total, one second per request, eight MiB per response and 4096 mapped records. The
same flow invokes registered CLI callbacks supplied by the CLI discovery lane. In-run router and
model-switch integration is owned by that lane's small `run_model_ready()` handoff.
Providers without a supported listing API or callback keep the offline catalog. A callback's
`NULL`, unsupported HTTP endpoint, malformed response or timeout never establishes availability;
failed supported listings report the failure in the footer. This does not implement every
provider-specific deployment or subscription-entitlement API.

## Primary-source checks

Checked official endpoint documentation on 2026-11-02:

- [OpenAI models](https://developers.openai.com/api/reference/resources/models/methods/list):
  `/models` advertises ids and basic ownership metadata; it supplies no tool/context/price fields.
- [Anthropic models](https://platform.claude.com/docs/en/api/typescript/models/list):
  `/v1/models` has cursor pagination. Positive reported input/output limits, image/PDF input and
  thinking support can be mapped. Server-tool support does not attest client function calling.
- [Google models](https://ai.google.dev/api/models): native names, page tokens, token limits,
  thinking and generation methods. Explicit embedding-only entries are excluded from chat discovery.
- [Mistral models](https://docs.mistral.ai/api/endpoint/models) and
  [OpenRouter models](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties):
  compatible listings can explicitly report chat/tool/vision support and token limits. Only these
  reported fields are mapped; native pricing is not converted into an account quote.
- [TypeSafe OpenAPI](https://api.typesafe.ai/openapi.json): `/v1/models` reports `models[].name`.
  The SystemOne protocol establishes the classifier route, not new model capacities, vision or cost.
- [Ollama tags](https://docs.ollama.com/api/tags): the existing tags/show/version evidence mechanism
  remains responsible for installed chat and Clef/Clef Flash decision models. No models are pulled.

## Verification

Tests were written before implementation. The initial execution was deferred while the parent
paused R jobs for host memory/load pressure. Once the sole R slot was granted:

```r
devtools::test(filter = "provider-model-discovery|catalog-models|arch-layers", reporter = "summary")
```

All three focused files passed: new provider inventory assertions (85), architecture assertions
(44), and the existing catalog/Ollama cases, with no failures or warnings. The reactor fixture
needed permitted synthetic loopback sockets; it never called an external endpoint. Fixtures cover
native authentication headers without materialization, pagination and response bounds, sanitization,
sparse capabilities, successful empty listings, cache expiry/key changes, failure retention,
consent/replay ordering, pure lookup and session-key metadata. Two matching Rd topics were
regenerated with roxygen2 and passed `tools::checkRd()`. A final comment-only clarity correction
was mirrored in its Rd after the R slot was handed off. `git diff --check` is clean.

Live availability, CLI picker outputs and actual Peter interaction remain root's integrated
acceptance responsibility. The public listing adds two columns; existing columns and the
`gptr_models()` signature are unchanged. No dependency, option, credential-storage format,
usage-table field or model-resolution network behavior was added.

## Review follow-up

The final review pass preserves the effective per-call replay override through gateway,
in-run and decision-model preparation; ordinary explicit refresh still obeys process replay.
Hosted by-reference decision requests now inventory after their existing guards. Endpoint and
canonical effective-header hashes bind both cache reuse and offline freshness. Built-in
OpenAI-compatible callbacks reuse the native credential path, so entering or rotating an optional
vLLM key invalidates a prior failed attempt. Advisory attempts are recorded before listing I/O,
so reactor reentry reuses the pending attempt without a separate inflight framework. Missing
reasoning metadata is displayed as `NA`; conservative model capability defaults are unchanged.

Offline regressions were added before the fixes. The final focused run passed
`provider-model-discovery` (105 assertions), `arch-layers`, `catalog-models` and `s1-route` with
no failures or warnings. The replay regression covers both gateway and in-run preparation plus
the continuing refusal of ordinary explicit refresh in replay mode. The matching model-list Rd
was regenerated and checked. Named architecture edges describe the actual consent guards and
the CLI footer's read-only session path lookup. The sole R slot was then released to root for
integrated installation and live Peter acceptance.
