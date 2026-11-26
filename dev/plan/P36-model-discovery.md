# P36 Models: native discovery for the CLI routes, write-in models, a current catalog (2026-11-26)

**Goal:** gptr learns which models the user's Claude Code and Codex offer, and which one each uses
by default, from the CLIs' own interfaces, so a CLI update changes what gptr shows without a gptr
release. Any model id can be written in for any route or provider. Every provider's catalog is
current and verified, and gptr's provider code follows the APIs of the new models. The
maintainer: "update and revise the code so that GPT-R actually will automatically recognize what
models are available in those CLIs ... take the user's default models as the model to start ...
not doing any hard-coded regex or any hard-coded rule-based things ... use as many native APIs
provided by those coding agents as possible ... give the user somewhat of a write-in option ...
The same thing goes for the other APIs and the other providers ... check all those model providers
comprehensively".

The survey of 2026-11-26 found: `pcli_models()` (`R/cli-common.R`) hard-codes the CLI lists
(claude: default, claude-opus-5-5, claude-sonnet-5-5, claude-haiku-4-5; codex: default, gpt-6-sol,
gpt-6-luna) and `pcli_claude_models()` keeps only ids starting `claude-`; the shipped catalog is a
22-entry seed of 2026-10-03; aliases resolve through name patterns (`^gpt-[0-9.]+-sol$`,
`^gemini-[0-9.]+-pro(-preview)?$`, `^gpt-[0-9.]+-luna$`); `provider_default_models()`,
`google_uses_level()`, `google_major()`, the Bedrock and OpenRouter prefix tests and the shipped
prompt presets match model names; an id the catalog lacks is refused for every non-local provider
and both CLI routes. Native interfaces verified on Claude Code 2.1.323 and Codex 0.157.1, at no
token cost: Claude Code's stream-json control requests `initialize` (`models[]`, documented) and
`get_settings` (`applied.model`); Codex's `app-server` `model/list` (paged;
`supportedReasoningEfforts`, `isDefault`, visibility) and `config/read` (`model`,
`model_provider`, `model_reasoning_effort`), and `codex debug models`.

**Authority:** this plan adds:

| D | Rule | Amends |
|---|---|---|
| D-390 | a CLI route's models come from its CLI: Claude Code's `initialize` and `get_settings` control requests, Codex's `app-server` `model/list` and `config/read` (`codex debug models` when the app-server cannot answer), in one bounded probe per CLI version and login, cached in the catalog's discovered layer; no model name is filtered or matched | P20 CLI model lists (`pcli_models()`) |
| D-391 | a route's `default` is the model the user's CLI uses by default; gptr shows it by name and starts from it | P20 `pcli_default_model()` |
| D-392 | any model id may be written in for any route or provider; an id the catalog lacks is passed through with one notice and conservative capabilities | `04` model resolution (unknown ids refused) |
| D-393 | gptr matches no model name: aliases, defaults, thinking styles, prompt presets and provider request shapes come from catalog data (models.dev and providers' list endpoints) | catalog aliases, `provider_default_models()`, provider adapters |
| D-394 | the shipped snapshot is built from models.dev by `dev/release` at release time and checked against providers' official lists | the 2026-10-03 seed |
| D-395 | provider adapters follow the current APIs: Anthropic API version 2026-10-21, sampling parameters only where a model's data allows them, Gemini thinking levels, xAI and DeepSeek reasoning effort, vLLM `reasoning`, Ollama `/api/show` thinking levels, OpenRouter reasoning objects | provider adapters |

Next free decision: D-396.

**Depends on:** P34 (`claude/v1.3.0`). **Milestone:** 1.3.0.

## Global constraints

`dev/plan/00-conventions.md` in full. No new Imports or Suggests. Discovery is a bounded child
process (short timeout, process-tree kill) that sends no prompt and spends no tokens; it uses the
user's real CLI configuration read-only, so it follows routers, Bedrock, Vertex and custom
providers. gptr's own CLI runs keep their isolation flags. Offline tests use recorded probe
fixtures and the fake provider; live tests run only with `GPTR_LIVE_TESTS=true` and assert shapes,
never model names.

## Tasks

1. CLI discovery and defaults (D-390, D-391), with the console's `/model` and first-run setup.
2. Write-in models (D-392) for CLI routes and providers.
3. Catalog without name rules, and a current shipped snapshot (D-393, D-394).
4. Provider adapters for the current APIs (D-393, D-395).
5. Documentation: `?gptr_models`, `?gptr_providers`, `?gptr_config`, the language-models article,
   README, NEWS.
6. Verification: offline suites, live CLI probes, live provider calls within the live-test rules,
   live tests in a terminal console and in RStudio.

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| 1 | `devtools::test(filter = "catalog-|cli-|provider-|console-")` | | |
| 2 | live probes: `claude` and `codex` discovery, shapes only | | |
| 3 | `GPTR_LIVE_TESTS=true` provider calls (bounded cost) | | |
| 4 | terminal console and RStudio: `/model`, default, write-in | | |
| 5 | `R CMD check --as-cran` | | |
| 6 | CI on the PR | | |
