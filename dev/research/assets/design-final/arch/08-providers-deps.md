
---

## 8. Provider matrix

Providers are data records bound to one of a closed set of wire adapters (INFRA-17); an OpenAI-compatible host
is added by data alone; plugins may add adapters through `gptr_adapter()`. Credentials resolve per request in
this order: an explicit argument (registered as a handle) > the vault (`gptr_env()`, ambient environment
variables) > the credential store (`gptr_login()`) > keyring references; every handle is origin-bound (§6.5).
The first use of each provider requires the egress acknowledgement (§6.10).

### 8.1 Native API providers (v1)

| Provider id | Adapter | Authentication | Key variable(s) | Notes |
|---|---|---|---|---|
| `anthropic` | `anthropic-messages` | `x-api-key` header; `anthropic-version`; betas per model capability | `ANTHROPIC_API_KEY` | refuses subscription tokens (`sk-ant-oat`); never sends both `x-api-key` and Bearer; adaptive thinking (display summarized when interactive); BP1/BP2 + automatic tail caching; mid-conversation system messages for operator entries where supported; `refusal`, `pause_turn`, `max_tokens` handled [07 §4] |
| `openai` | `openai-responses` | `Authorization: Bearer` | `OPENAI_API_KEY` | stateless (`store: false`); encrypted reasoning and `phase` replayed byte for byte to the same model; `prompt_cache_key`; `X-Client-Request-Id` unique per request [08 §3] |
| `google` | `google-generative-ai` | `x-goog-api-key` header | `GEMINI_API_KEY`, then `GOOGLE_API_KEY` | `streamGenerateContent?alt=sse`; thought signatures kept on the exact part and replayed only to the same model; `thinkingLevel` on 3.x; unknown finish reasons map to error with the raw value [09] |
| `openrouter` | `openai-completions` | Bearer | `OPENROUTER_API_KEY`, or `gptr_login("openrouter")` (PKCE) | comment lines and mid-stream error chunks; `session_id`; `cache_control` for anthropic/google models |
| `groq`, `deepseek`, `mistral`, `together`, `xai`, `cerebras`, `fireworks` | `openai-completions` | Bearer | `GROQ_API_KEY`, `DEEPSEEK_API_KEY`, `MISTRAL_API_KEY`, `TOGETHER_API_KEY`, `XAI_API_KEY`, `CEREBRAS_API_KEY`, `FIREWORKS_API_KEY` | compat flags per 09 §3: Groq rejects `messages[].name`; DeepSeek needs `reasoning_content` replayed with tools; Mistral needs 9-character tool ids; Cerebras base64 images only |
| `ollama`, `lmstudio`, `llamacpp`, `vllm` | `openai-completions` | none (vLLM optional Bearer) | `VLLM_API_KEY` (optional) | loopback defaults; discovery `GET /v1/models` with a 1 s timeout, only on request, never at load or under check; unknown model ids allowed for local providers only |
| `azure` | `openai-completions` (v1 API) | `api-key` header | `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT` | `model` is the deployment name; no `api-version` [09] |
| `bedrock` | `openai-completions` (Bedrock's OpenAI-compatible endpoint) | Bearer | `AWS_BEARER_TOKEN_BEDROCK` | Converse/SigV4 is v1.x |
| `fake` | `fake` | none | - | `gptr_fake_provider()`; examples and tests |

Base URLs, compat flags and model lists are catalog data (`inst/extdata/models.json.gz`, 09 §3-4; refreshed
only on request with ETag into `R_user_dir("gptr", "cache")`; merge order snapshot < cache < overrides < user
config < live discovery for local servers).

### 8.2 System 1

| Provider id | Adapter | Authentication | Notes |
|---|---|---|---|
| `typesafe` | `typesafe-system-one` | `Authorization: Bearer`, key `TYPESAFE_API_KEY`; `gptr_env()` maps `jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` to it (REQ-13) | `POST {base}/systemone` with `{model, state, questions}`; types `choice`, `score`, boolean (wire `noul`); model alias `jev` -> `jev-latest` (physical id recorded in `meta`); vectorised on the reactor, at most 8 concurrent, 3 bounded rounds; about 250-280 input tokens per request at $0.042/M; 20 requests in about 0.4 s [04, 04a] |
| gateway records | `typesafe-system-one` | the gateway's key | other hosts of the System One API listed in 04 §4 are data records on the same adapter |
| `emulate:<model>` | `inprocess` over a System 2 adapter's structured output | the System 2 provider's | opt-in only; `meta$calibrated = FALSE`; never silent, never offered non-interactively |

### 8.3 Subscription (plan) routes

**Claude plan: provider id `claude-cli`, user alias `claude_code`** (experimental; opt-in with a one-time
notice). The user's own, unmodified `claude` CLI, one long-lived processx child per session:

```text
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
       --tools "" --strict-mcp-config --setting-sources "" --disable-slash-commands
       --mcp-config <file> --permission-prompt-tool stdio --system-prompt-file <file> --model <full id>
```

Never `--bare`. Authentication is the user's own `claude` login; gptr never reads, stores or brokers Claude
credentials and never offers a Claude.ai login [07 §2.18]. The minimum CLI version is probed (>= 2.0.0, the
Agent SDK's floor; 2.1.261 tested). Variables that silently switch plan billing to the API
(`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_*`) are removed from the child environment
with a warning; profile and gateway precedence cases are documented as UNCERTAIN [G6 fact-check]. gptr's tools
reach the CLI through the in-process `sdk` MCP server over the control protocol (`mcp_message`), so Claude
evaluates R in the live session; `can_use_tool` requests go through `perm_check()`; Ctrl-C sends a
`control_request` interrupt, then `kill_all()`. Stream events reuse the Anthropic normaliser; continuity uses
the CLI's session id (`--resume` with the same system-prompt file); usage records `total_cost_usd` as a plan
estimate and the rate-limit event as plan status. Concurrency: one `claude-cli` child per session by default.
The provider id avoids the Claude Code product name; `claude_code` is only an alias; the maintainer asks
Anthropic before advertising the route (policy status UNCERTAIN) [07, J-cran].

**ChatGPT plan: provider id `codex`** (via the user's Codex CLI). One `codex exec` per turn, prompt on stdin:

```text
codex exec --json --ignore-user-config
      -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp
      -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN
      -c mcp_servers.gptr.tool_timeout_sec=3600
      --sandbox <read-only | workspace-write> -
```

Authentication is the user's own Codex login; gptr never reads `~/.codex/auth.json`; `CODEX_API_KEY` and
`OPENAI_API_KEY` are removed from the child environment with a warning [08, G6]. Live R: `gptr_mcp_serve()`
starts automatically (loopback, random port, 192-bit token passed only in the child's environment) so Codex
evaluates R in the live session through the permission gate, which can prompt at the console because the
call arrives in R [08: in-session HTTP MCP verified listed and called by Codex]. Without httpuv/later/openssl
the route works on files only, with a notice. Permission mapping (headless exec cannot prompt): `plan` ->
`--sandbox read-only`; `manual` -> read-only sandbox, R tools gated by gptr; `edits`/`auto` ->
`workspace-write`; never bypass the sandbox. Continuity: `codex exec resume <thread>` when supported
(UNCERTAIN), else a new thread with a synthetic history. The console states Codex's 19-38K extra input tokens
per turn [08]. The Codex app-server driver (dynamic tools calling back into R, steer, interrupt) and Sign in
with ChatGPT (the native `openai` provider with `auth = "chatgpt"`, avoiding Codex's overhead) are v1.x plugins
behind a schema probe and a maintainer's live end-to-end test respectively (§1.3).

### 8.4 Model references and defaults (D-18)

References are `provider/id[:thinking]` strings or aliases resolved dynamically from family and release date
(`sonnet`, `opus`, `haiku`, `gemini`, `flash`, `gpt`, `jev`, `claude_code`, `codex`), with Pi's last-colon
thinking-suffix rule, `.`/`-`/`_` normalisation and `adist()` suggestions [09 §4]. Thinking levels are clamped
to the model's map. The default chat model is taken from the first available route: an Anthropic key ->
`anthropic/claude-sonnet-5-5` (the north-star banner; $2/$10 vs $4/$20 for Opus 5.5); OpenAI ->
`openai/gpt-6-sol`; Gemini -> `google/gemini-3.8-flash`; otherwise a detected CLI. `small_model` serves
compaction, emulation and cheap sub-agents. CLI invocations always receive full ids (CLI aliases lag the
API [07]). Documents record quoted canonical ids.

---

## 9. Dependencies (D-20, D-21, D-23)

`Depends: R (>= 4.2.0)` (UTF-8 native encoding on current Windows, the `_` pipe placeholder; oldrel-4 today;
proven by an oldrel-4 CI job) [13 §2.7]. `NeedsCompilation: no`. `License: MIT + file LICENSE`.

### 9.1 Imports (7 non-base; dependency closure 9 packages, 10 with callr 3.8.0's otel)

| Package | Floor (raised by P01 to what CI proves) | Load-bearing use | Why not base R or another package |
|---|---|---|---|
| jsonlite | 1.8.8 | every wire body, JSONL, settings, schemas | no JSON in base |
| curl | 6.0.0 | the reactor: multi handles, `multi_fdset()`, `multi_cancel()`, `pipewait = 0L`; one transport for streams, System 1, MCP HTTP, OAuth and catalog refresh | only curl multi streams interruptibly [02, 10a INFRA-01]; httr2 blocks on headers and batches output [10a E1/E2] |
| processx | 3.8.0 | `poll()` over curl fds and pipes; MCP stdio, CLI providers, bridges; `kill_tree()` | `system2()` cannot poll or stream |
| callr | 3.7.0 | worker sub-agents and artifact children running package functions (Rscript path, libpaths, `_R_CHECK_R_ON_PATH_`) | a hand-written worker re-opens solved Windows problems [J-cran, J-impl] |
| rlang | 1.1.0 | `new_weakref()` (live index), `obj_address()`, `env_binding_are_lazy()/_active()`, `hash()`/`hash_file()` (XXH128), `duplicate()`, `check_installed()` | no weak references or addresses in base R; rlang is required anyway when cli condition helpers are used [13 §2.6]; **quosures are not used in the gateway** (§6.4 R3) |
| cli | 3.6.0 | console rendering and capability detection, `hash_sha256()` for ids and cache keys | front-end quirks are encoded there [18 §2.1.5] |
| yaml | 2.3.0 | SKILL.md, agent and template frontmatter | a hand parser lost 4 of 37 real skills to folded scalars [05] |

Base packages imported: `methods` (G7 pre-image defusing of S4), `stats`, `tools`, `utils`, `grDevices`,
`graphics`. The closure (these plus R6 and ps via processx and callr) was verified with
`tools::package_dependencies()` by J-cran and J-impl; it is far below the 20-Import NOTE [13 §2.6]. No httr2
(its closure adds 7 packages; its parallel path retries without bound), no openssl in Imports (only opt-in
OAuth and the MCP server need it).

### 9.2 Suggests (each behind `requireNamespace()`/`rlang::check_installed()` with a base fallback or `gptr_error_missing_package`)

| Package | Feature |
|---|---|
| testthat (>= 3.2.0), withr | tests |
| knitr, rmarkdown | `knit_print`, stale-chunk hooks, vignettes |
| later, httpuv, openssl | `gptr_mcp_serve()` and the Codex live-R route; OAuth loopback (paste fallback without them); experimental background sessions (later) |
| shiny, bslib, chromote, ragg | artifacts; headless session check and screenshot (HTTP-only check without chromote); faster headless PNG plots (fallback `grDevices::png()`) |
| rstudioapi | IDE document backend |
| reticulate, DBI, duckdb, RSQLite | `gptr$py()`, `gptr$sql()` |
| data.table | checkpoint deep copy of `:=`/`set()` targets (only when the target is a data.table, so it is loaded already) |
| vctrs | delayed S3 methods for System 1 vectors in tidy workflows |
| stringi | NFKC in the fuzzy edit fallback; natural sort |
| magick | image resize for oversized image reads (fallback: send within limits or refuse) |
| keyring | credential-store references |
| codetools | the layering test |

Never used: httr2, R6 (arrives transitively; not used), S7, evaluate, digest, glue, promises, coro, mirai, fs,
and any R LLM package (ellmer, tidyllm, chattr, gptstudio, mall, btw, mcptools, openai, rollama, corteza,
aisdk, agenticr) in Imports or Suggests (S-10). rtiktoken is used only in `dev/bench`.
`SystemRequirements`: optional external programs `claude` (Claude Code CLI) and `codex` (Codex CLI); a
Chrome-family browser for chromote screenshots. They are discovered with `Sys.which()` and never invoked
through a shell.

### 9.3 Compiled code

None in v1 (D-21): no hot path met REQ-01's bar [21 summary and verifier]. Report 21's watch list (SSE
splitting, grep over huge trees, JSON canonicalisation) and its procedure (recorded benchmark, pure-R reference
implementation, cross-check test on random inputs, no system libraries) stand for v1.x.
