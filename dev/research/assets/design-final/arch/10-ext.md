
---

## 11. Extensibility map (S-11, REQ-41)

Pi's expandability comes from one extension API that every feature uses. gptr matches and extends it: one
registry keyed by (kind, name), one registration verb, 30 kinds (a plugin can add more), per-kind contracts
validated at registration, lazy activation that never breaks the cached prompt prefix, transactional loading,
a versioned API, a conformance checker, and a test that proves built-ins use only the public API.

### 11.1 Every capability category

Registration paths, all equivalent: inside a factory `function(gptr)` with `gptr$register(spec)` or the
generated sugar `gptr$register_<kind>(...)`; at top level with `gptr_register(spec)` (rank "user"); as a call
argument (`gptr(..., tools = list(spec))`, rank 0 "session"); or declaratively (files discovered in
`.gptr/`, user directories and `inst/gptr/` of installed packages). Built-ins register through the same calls
as `builtin:<name>` (rank 6) and can be overridden or disabled with filters (`-builtin:<name>`,
`-<kind>:<name>`), except that project settings cannot disable user or built-in policies and hooks.

| Category | Kind: contract | Built-ins implemented on it | How an R package ships it | What a third-party agentic layer does with it |
|---|---|---|---|---|
| Native API providers | `provider` (`gptr_provider()`): data record (id, api, base_url, auth resolver returning a secret handle, models, compat, `type = "chat"`) | `builtin:providers` (anthropic, openai, google, openrouter, groq, deepseek, mistral, together, xai, cerebras, fireworks, ollama, lmstudio, llamacpp, vllm, azure, bedrock) | factory or `inst/gptr/plugin.json` `provides: {provider: [...]}` | a company gateway registers its endpoint and auth by data; `model = "corp/model"` |
| Wire formats | `adapter` (`gptr_adapter()`): `build(model, request, opts)` -> url/headers/body; `parse()` -> normaliser emitting INFRA-02 events, never throwing after `start`; `capabilities` | `builtin:anthropic`, `builtin:openai`, `builtin:openai-compat`, `builtin:google`; `fake` | exported factory + wire fixtures for `gptr_check()` | a Bedrock Converse adapter package |
| Subscription CLI providers | `provider` with `type = "cli"` + adapter transport `process_jsonl` with a control handler | `builtin:cli`: `claude-cli`, `codex` | factory | drive another agent CLI as a provider or sub-agent |
| System 1 providers | `provider` with `type = "classifier"` + adapter `classify(model, state, questions, opts)` | `builtin:system1`: `typesafe`, gateway records, `emulate:` | factory | a domain classifier used as `model = mymodel` inside `if()` |
| Models | `model`: catalog entries (context, max output, reasoning, input types, prices, aliases) | the shipped snapshot | `inst/gptr/models.json` | private fine-tunes with prices |
| Model routers | `router` (`gptr_router()`): `route(request, ctx)` returns a registered model within 50 ms; errors fall back to the default | none enabled; a Jev complexity router ships as a documented example | factory | cost-aware routing (`model = cheapest`) using `ctx$decide()` |
| Tools | `tool` (`gptr_tool()`): schema, `execute(input, ctx)` or `fun`, `exposure` (`direct`, `r`, `deferred`, `hidden`), `namespace`, `execution`, `risk(input, ctx)`, `snippet`, `guidelines`, `signature`, `output_tokens`, `record`, `available()` | `builtin:r` (`r`), `builtin:tools` (`read`, `edit`, `write`, members `read/write/edit/grep/find/ls/help/search/describe/plot/out`), `builtin:ask`, `builtin:bridges` (`sh`, `script`, `bg`, `jobs`), `builtin:lang` (`py`, `sql`, `knit`), `builtin:artifacts` (`app`) | factory; lazy with manifest `declarations` so signatures are in the frozen prefix before activation | whole toolkits callable from model code: `gptr$trials$search(condition)` |
| Interpreters | `interpreter`: extension, candidate programs, args, `windows_only` (for `gptr$script()`) | `.sh`, `.py`, `.R`, `.js`, `.pl`, `.rb`, `.jl` | factory | Stata, SAS or remote runners |
| MCP servers | `mcp_server` (`gptr_spec("mcp_server", ...)` or `gptr_mcp_add()`): command/url, env, headers, exposure, per-tool exposure, timeout, protocol era | `builtin:mcp` (client, config import, namespace, server) | `inst/gptr/mcp.json` | a plugin bundling servers, skills and tools (`plugins = clinical_trials`) |
| Skills | `skill`: Agent Skills directory (`SKILL.md` with frontmatter) | `high-performance-r`, `shiny-bslib`, `gptr-orchestration` | `inst/gptr/skills/<name>/SKILL.md` (also `inst/skills`); available when the package is attached, as untrusted prompt text | domain playbooks referenced by agent definitions |
| Prompt templates | `prompt_template`: Pi template grammar, `/name args` | `review`, `explain` | `inst/gptr/prompts/<name>.md` | workflow commands (`/triage`) |
| Slash commands | `command` (`gptr_command()`): `handler(args, ctx)`, completion | the console command set (§6.17) | factory | `/panel`, `/deploy` |
| Hooks and events | `hook` (`gptr_hook()`, `gptr_on()`, `gptr$on()`): event, handler, matcher; dispatch semantics of §5.4; fail-closed events | the session store writer's listeners, `builtin:documents` writer, console renderer, usage accounting, prefix guard | factory (eager activation for audit loggers) | audit logs, cost guards (`budget_exceeded`), CI gates |
| Permission policies | `policy` (`gptr_policy()`): `check(call, ctx)` -> allow/deny/ask/modify | `builtin:permissions` (mode, rules, critical guard, secret guard, protect size), `builtin:plan` | factory (user- or call-enabled) | organisation policy packs; a System 1 reviewer answering `permission_request` |
| Context / environment describers | `context_block` (`gptr_context_block()`): `provide(ctx, budget)`, placement `first`/`turn`, authority `data`/`operator`; S3 generic `gptr_describe()` | `builtin:context` (project instructions, environment, mode, plan), `builtin:workspace` (workspace, workspace_changes, attached, r_env); describers for base classes, Seurat, SCE, dgCMatrix, data.table, Arrow, DBI | `S3method(gptr::gptr_describe, cls)` with gptr in Suggests (delayed registration); factories for blocks | lab-notebook or database-schema context; Bioconductor-aware descriptions |
| System prompt sections | `prompt_section` (`gptr_prompt_section()`): text or `function(ctx)`, tier, order, budget | every section of §7.3 (`builtin:prompt`) | factory | house rules, a domain preamble |
| Compaction strategies | `compactor`: `should(session, ctx)`, `compact(session, ctx)`; reports usage; errors fall back | the in-conversation checkpoint compactor (`builtin:compaction`) | factory | provider-native compaction plugins (v1.x) |
| Cache policies | `cache_policy`: breakpoint plan and TTL per provider | gap-based tail TTL (`builtin:prompt`) | factory | provider-specific caching strategies |
| Token estimators | `estimator`: `estimate(x, class)`, calibration | G2's class-aware estimator | factory | a tokenizer-backed estimator package |
| Document formats and history writers | `doc_format`: `ext`, `locate`, `render`, `write` | `r`, `rmd`, `qmd`, `ipynb`, `transcript` (`builtin:documents`) | factory | an Org-mode or `targets` writer |
| Artifact types | `artifact_type`: `build`, `check`, `launch`, `stop` | `shiny`, `html` (`builtin:artifacts`) | factory | Plumber APIs, Quarto dashboards |
| Sub-agent backends | `backend` (`gptr_backend()`): `start(spec, ctx)` -> handle with fds, `poll`, `cancel`; must not block the reactor for more than 50 ms; cancel kills the tree | `inline`, `worker`, `cli` (`builtin:subagents`) | factory | a mirai or HPC-cluster backend |
| Agent definitions | `agent` (`gptr_agent()`): model, tools, skills, system text, backend, preset, returns; Claude-compatible `.md` files | `reviewer`, `explorer` (`builtin:agents`), plus `.gptr/agents`, `.claude/agents`, `.codex/agents` (md), `.pi/agents` | `inst/gptr/agents/<name>.md` | named specialists used in `agents =` |
| UI backends | `ui`: `select`, `input`, `questions`, `notify`, `has_ui`; a failing dialog is not an approval | `console`, `none`, `scripted`, `rstudio` (`builtin:ui`) | factory | RStudio dialogs, a Shiny gadget |
| Front ends | `frontend`: `run(session, ...)` | `console` REPL, `jsonl` event sink; `knit_print` | factory | an RPC server or Shiny chat front end |
| Settings | `setting`: name, default, scope, validator | core settings | factory | plugin configuration through `gptr_config()` |
| Secret sources | `secret_source`: resolver returning handles | `.env`, environment, `auth.json`, keyring (`builtin:secrets`) | factory | a vault or cloud secret manager |
| Redaction rules | `redaction_rule`: pattern, marker | 12 gitleaks-derived patterns, `NAME=value` | factory | PHI/identifier redaction for clinical data |
| Environment aliases | `env_alias`: alias -> canonical name | `jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` -> `TYPESAFE_API_KEY` | factory | a provider's alternative key names |
| Child environments | `child_env`: profile name, allowlist, pass-through rules | `mcp`, `worker`, `cli-claude`, `cli-codex`, `helper`, `artifact` | factory | stricter profiles for regulated sites |
| Checkpointers | `checkpointer`: `before`, `after`, `undo`, `redo`, `prune`, `describe`; S3 generic `gptr_preimage()` | objects, files, state, artifacts (`builtin:checkpoints`) | factory; `gptr_preimage()` methods | a shadow-git backend |
| New categories | `kind`: `validate(spec)`, `resolve = "first" \| "all"`; then `gptr_spec(kind, ...)` | `interpreter` is registered this way by `builtin:bridges` | factory | a plugin defines e.g. a `dataset_source` kind for its own sub-plugins |

### 11.2 Shipping plugins in R packages [G1 §4.4]

```text
DESCRIPTION   Imports: gptr (SDK users)  or  Suggests: gptr (describers, skills only)
              Config/gptr/plugin: true
              Config/gptr/api: >= 1.0, < 2
NAMESPACE     export(gptr_plugin)                      # the factory named in plugin.json
              S3method(gptr::gptr_describe, cohort)    # delayed registration
inst/gptr/plugin.json   {"name", "version", "gptr": {"api": ">= 1.0, < 2"},
                         "skills": "skills", "prompts": "prompts", "agents": "agents",
                         "mcpServers": "mcp.json",
                         "extension": {"entry": "pkg::gptr_plugin", "activation": "lazy",
                                       "provides": {"tool": ["trial_search"]},
                                       "declarations": {"trial_search": {"signature": "trial_search(condition)"}}}}
inst/gptr/skills/  inst/gptr/prompts/  inst/gptr/agents/  inst/gptr/mcp.json
```

Rules: discovery, never `.onLoad` self-registration (13 C-29: loading must be side-effect free); code runs
only when enabled by a call argument, user settings or trusted project settings; declarative resources of
attached packages are available immediately (skills and templates as untrusted text); factories run lazily on
first use of anything in `provides`, and `declarations` put tool signatures into the frozen prompt before
activation, so lazy loading never breaks the cache; registrations are staged and committed only when the
factory returns, so a failing or version-incompatible factory is rolled back, reported in
`gptr_registry(diagnostics = TRUE)`, and never breaks start-up; an unloaded package's records are removed and
captured API objects raise `gptr_error_stale_api` [G1 §3, §4.4]. `.claude-plugin` bundles are consumed
unmodified for skills, commands, agents and MCP servers (hooks import is v1.x).

```r
gptr_plugin = function(gptr) {
  gptr$require(">= 1.0, < 2")
  gptr$register(gptr::gptr_tool(
    name = "search", namespace = "trials",
    description = "Search ClinicalTrials.gov for recruiting trials",
    parameters = list(type = "object", required = I("condition"),
                      properties = list(condition = list(type = "string"))),
    fun = function(condition) search_trials(condition),
    exposure = "r",
    risk = function(input, ctx) list(level = 2L, categories = "network"),
    signature = "search(condition)  # data frame of trials"))
  gptr$on("tool_result", function(event, ctx) NULL)
}
```

### 11.3 Third-party agentic layers

A layer (orchestrator, review panel, workflow engine, domain agent) needs only exported verbs and the
constructors: `gptr(.run = FALSE)`, `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`,
`gptr_on()`, `gptr_fork()`, `gptr_parallel()`, `gptr_map()`, `gptr_usage()`, plus `ctx$decide()` (System 1
inside plugins), `ctx$execute_tool()` (nested calls through the same gate), `ctx$send()` (steering),
`ctx$state()` (per-session plugin state) and `ctx$emit()` (inter-plugin bus). Layers written in other
languages drive gptr through the JSONL event sink and worker protocol. G1 verified the shape with a toy
`gptrpanel` package built only on the SDK (21/21 checks, no `:::`).

```r
panel_review = function(file, models = c("opus", "gemini")) {
  runs = lapply(models, function(m) gptr::gptr(paste("Review", file, "for statistical errors"),
                                               model = I(m), .run = FALSE))
  names(runs) = models
  res = gptr::gptr_parallel(.list = runs)                  # one team session, one reactor
  ok = gptr::gptr("Do these reviews agree that the analysis is sound?", res$text,
                  model = jev)                             # System 1 judge
  if (all(ok)) res else res |> gptr::gptr("Reconcile the reviews into one list of fixes")
}
```

### 11.4 API versioning and conformance [G1 §4.5]

- `gptr_api()$version` starts at 1.0 with gptr 1.0.0 and changes only when the extension API changes. MINOR
  releases are additive (new kinds, events, ctx members, optional fields; handlers must ignore unknown payload
  fields). MAJOR releases break and require the CRAN notice period to reverse dependencies found with
  `tools::package_dependencies(reverse = TRUE, which = "most")` (which covers plugins that only Suggest gptr).
- Plugins state requirements with caret semantics (`">= 1.2, < 2"`) in the manifest, `Config/gptr/api` or
  `gptr$require()`, and negotiate features with `gptr$has("kind.router")`; an unmet requirement disables only
  that plugin.
- Deprecation: an internal `gptr_deprecated()` warns once per session (class `gptr_deprecated`;
  `options(gptr.deprecations = "error")` for plugin CI); a deprecated member lives at least one MINOR release
  and six months.
- `gptr_check(x, error = FALSE)` runs conformance suites: specs (fields, schema validity, direct tool
  descriptions at most 400 tokens, section budgets, empty input handled), factories (every `provides` entry
  registered, no action at load), packages (manifest, API requirement), adapters (fixture replay, error as
  event, chunk invariance, byte-identical opaque round trip), policies (the 18 §4.7 matrix), backends (cancel
  leaves no process). `gptr_fake_provider()` drives plugin tests offline.
- `artifact_type`, `frontend`, `interpreter`, `checkpointer` and plugin-defined kinds are marked experimental
  in API 1.0.
- `test-arch-layers.R` keeps built-ins honest (§2.2 rule 4): a `builtin_<name>()` factory that reaches an
  internal outside the extension API and its declared services fails the test.
