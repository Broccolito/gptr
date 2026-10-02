
---

## 3. Package file layout

### 3.1 Area prefixes

`R/<area>-<topic>.R`, one topic per file (conventions §3). Final areas, in layer order:
`utils`, `json`, `ext`, `auth`, `proc`, `http` (L0); `provider`, `catalog`, `s1` (L1/L4); `agent` (L2/L3);
`session`, `prompt` (L3); `eval`, `env`, `tool`, `bridge`, `perm`, `ckpt`, `skill`, `mcp`, `subagent`, `cli`,
`doc`, `artifact` (L4); `console` (L5); `gptr` (L6); plus `zzz.R`. `cli` means the subscription-CLI
providers, never the cli package.

### 3.2 `R/` files (114 files)

Every file has exactly one owning plan (`05-plan-decomposition.md`). "Builtin" names the factory the file
declares, if any.

| File | Layer | Responsibility | Builtin | Plan |
|---|---|---|---|---|
| `utils-conditions.R` | L0 | `gptr_abort()/gptr_warn()/gptr_inform()` with the `gptr_error_<class>` scheme; `msg_verbatim()` (safe rendering of untrusted text); condition redaction hook | - | P01 |
| `utils-hash.R` | L0 | sha256 via `cli::hash_sha256()`, `canonical_json()` (radix key order), RNG-free ids (session, entry, block), sampled fingerprints | - | P01 |
| `utils-encoding.R` | L0 | UTF-8 marking before every parse/serialise, `os_bytes()`, binary-connection text I/O, C-locale guards | - | P01 |
| `utils-options.R` | L0 | documented `gptr.*` option defaults; `gptr_has_human()`, front-end detection, verbosity; mockable `gptr_is_interactive()`, `gptr_readline()`, `gptr_confirm()`; `on_load()` registry | - | P01 |
| `utils-paths.R` | L0 | project root, `gptr_user_dir(which)` = `tools::R_user_dir("gptr", which)`, workspace root (`.gptr` or `tempdir()/gptr`), atomic write (temp + `file.rename`), path classes, Windows reserved names | - | P01 |
| `utils-text.R` | L0 | head 40% / tail 60% truncation to a token budget, spill files, the `out(id)` store (last 20 results), ANSI/OSC and carriage-return cleanup, 400-char line caps | - | P01 |
| `utils-tokens.R` | L0 | class-aware estimator `est_tokens(x, class)` (G2 constants), image-token formulas, per-session EWMA multiplier | - | P01 |
| `json-encode.R` | L0 | `json_encode()`, once-serialised entries (`json_verbatim`), bodies assembled by concatenation | - | P01 |
| `json-partial.R` | L0 | incremental partial-JSON scanner for streamed tool arguments (throttled previews) | - | P01 |
| `json-schema.R` | L0 | argument validation and explicit coercion (INFRA-09); one-line R-signature rendering of schemas | - | P01 |
| `provider-message.R` | L1 | message and content-block constructors, validation, camelCase/snake_case mapping | - | P01 |
| `provider-events.R` | L1 | INFRA-02 event constructors; linear closure-buffer accumulator | - | P01 |
| `provider-fake.R` | L1 | the `fake` adapter (scripted replies or functions of the request); `gptr_fake_provider()` | - | P01 |
| `zzz.R` | - | `.onLoad` (runs the `on_load()` registry: built-in declarations, lazy S3 registration for knitr/vctrs), `.onUnload` (stops children) | - | P01 |
| `ext-registry.R` | L0 | registry keyed by (kind, name) and rank; filters; diagnostics; generation counter; `gptr_register()`, `gptr_registry()` | - | P02 |
| `ext-specs.R` | L0 | the kind table and validators (30 kinds, §11.1); `gptr_spec()`; exported constructors; `gptr_tool_result()` | - | P02 |
| `ext-api.R` | L0 | the factory API object (`register`, `register_<kind>` sugar for every kind, `on`, `require`, `has`, `state`) and the `ctx` object handlers receive | - | P02 |
| `ext-events.R` | L0 | event catalogue and dispatch semantics (notify, transform, patch, first decision, block), fail-closed events, `gptr_on()` internals | - | P02 |
| `ext-load.R` | L0 | transactional factory loading with rollback, lazy activation from manifests, API requirements, stale-API errors, `gptr_reload()` | - | P02 |
| `ext-check.R` | L0 | `gptr_check()` conformance suites, `gptr_api()`, deprecation helper | - | P02 |
| `ext-builtins.R` | L0 | built-in declaration table filled by `on_load()`, load order, `-builtin:<name>` filters | - | P02 |
| `auth-secrets.R` | L0 | vault, `gptr_secret` handles, ambient discovery, origin-bound materialisation | secrets | P03 |
| `auth-redact.R` | L0 | one redactor with sink profiles; streaming hold-back; `gptr_redact()` | - | P03 |
| `auth-dotenv.R` | L0 | own `.env` parser, alias table (`jev-key` -> `TYPESAFE_API_KEY`), `gptr_env()` | - | P03 |
| `auth-store.R` | L0 | `auth.json` credential store (0600, lock, keyring references) | - | P03 |
| `auth-childenv.R` | L0 | child-environment profiles (mcp, worker, cli-claude, cli-codex, helper, artifact); empty `R_ENVIRON_USER`/`R_PROFILE_USER` files | - | P03 |
| `proc-spawn.R` | L0 | G5 process engine: `processx::process$new` with file redirection, argv via `os_bytes()`, `.cmd`/`.bat` via `cmd.exe /d /c call` with metacharacter refusal, PowerShell `-EncodedCommand`, `write_all()`, line reader, UTF-8 decode with code-page fallback | - | P04 |
| `proc-supervise.R` | L0 | `kill_all()` (kill_tree, then Windows `taskkill /F /T`, then group kill), grace periods, process tables, orphan sweep | - | P04 |
| `http-reactor.R` | L0 | the process reactor: curl multi pool, `processx::poll()` over curl fds and pipes, timers, tool FIFO, admission, `allow_runs`, `later::run_now(0)` when loaded | - | P04 |
| `http-request.R` | L0 | request spec to curl handle (`pipewait = 0L`, connect/first-byte/idle timeouts, header handles materialised here only) | - | P04 |
| `http-sse.R` | L0 | vectorised byte-level SSE and NDJSON splitters with final-event flush [21 §2.6] | - | P04 |
| `http-retry.R` | L0 | error classes, bounded backoff, `retry-after(-ms)` cap, spend-cap 429 rule, per-provider rate limiter | - | P04 |
| `provider-transform.R` | L1 | projection (drop aborted/errored, close orphans) and cross-provider hand-off (INFRA-04/08) | - | P05 |
| `provider-registry.R` | L1 | provider records as data, compat table [09 §3], resolution, origin binding, egress check, `gptr_providers()` | providers | P05 |
| `provider-usage.R` | L1 | usage rows, dated price tiers, TTL-split cache writes, cost, route attribution, `gptr_usage()` | - | P05 |
| `catalog-models.R` | L1 | snapshot load, merge layers, aliases, `provider/id[:thinking]` resolver, explicit ETag refresh, `gptr_models()` | - | P05 |
| `session-object.R` | L3 | `gptr_session` shell and hidden data env, `$`/`[[`/`.DollarNames`/print/format/summary/`knit_print`, value policy, `gptr_fork()` | - | P06 |
| `session-live.R` | L3 | weak live registry, home-workspace policy, file locks, split-brain rules, `gptr_last()` | - | P06 |
| `session-store.R` | L3 | Pi-v3-shaped JSONL tree writer/reader, crash-safe appends, fork files, `gptr_sessions()`, `gptr_resume()` | - | P06 |
| `session-budget.R` | L3 | budgets (tokens, cost, turns), token ledger per request and component | - | P06 |
| `agent-loop.R` | L2 | pure loop state machine (injected stream function, context builder, tool executor), steer/follow-up queues | - | P06 |
| `agent-run.R` | L3 | run lifecycle on the reactor: recovery, agent-level retry, overflow and compact-and-retry, settle, nested runs, abort | - | P06 |
| `agent-dispatch.R` | L2 | tool dispatcher: validate -> gate -> execute; never throws; FIFO; nested-call gating | - | P06 |
| `prompt-sections.R` | L3 | section registry, presets, freeze, section patches, `gptr_prompt()` | prompt | P07 |
| `prompt-text.R` | L3 | the verbatim built-in section texts and mode blocks (§7.3-7.4) | - | P07 |
| `prompt-context.R` | L3 | context blocks (project instructions discovery, environment, mode, plan), first user message, per-turn deltas | context | P07 |
| `prompt-cache.R` | L3 | request assembly by concatenation, breakpoints per provider, gap-based tail TTL, prefix guard | - | P07 |
| `prompt-compact.R` | L3 | compaction trigger, in-conversation checkpoint, harness state extraction | compaction | P07 |
| `gptr-gateway.R` | L6 | `gptr()` dispatch and route lookup | - | P08 |
| `gptr-capture.R` | L6 | copy-safe base-R capture: dot facts via leaves, prompt selection, identifier resolution, `{identifier}` interpolation | - | P08 |
| `gptr-sdk.R` | L6 | `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()`, `gptr_prob()` | - | P08 |
| `gptr-config.R` | L6 | settings layers, `gptr_config()`, `gptr_init()`, `gptr_trust()`, egress acknowledgement, `gptr_permissions()` storage | - | P08 |
| `eval-core.R` | L4 svc | hand-rolled evaluator: parse, capture, per-expression time limit, interrupts, state diff [12 §4.3] | - | P09 |
| `eval-plots.R` | L4 svc | plot capture and replay to PNG (768x512, res 120) | - | P09 |
| `eval-guard.R` | L4 svc | static guard (forbidden calls), interactive-function traps, `gptr` symbol shim | - | P09 |
| `eval-format.R` | L4 svc | model text of an evaluation within the token budget, state-change lines, `gptr$out(id)` notices | - | P09 |
| `env-snapshot.R` | L4 svc | copy-safe snapshot (names, addresses, fingerprints) and diff | workspace | P09 |
| `env-describe.R` | L4 svc | `gptr_describe()` generic and level-based methods (incl. Seurat, SCE, dgCMatrix, data.table, Arrow, DBI) | - | P09 |
| `env-history.R` | L4 svc | task-callback log of the user's top-level expressions | - | P09 |
| `env-probe.R` | L4 svc | installed-package capability probe for `<r_env>` without loading packages [19 §3.2] | - | P09 |
| `tool-namespace.R` | L4 | `gptr$` gateway methods (`$`, `[[`, `.DollarNames`, print), member resolution, generated closures, `gptr$help`, `gptr$search` (BM25), `gptr$describe`, `gptr$plot` | tools | P10 |
| `tool-r.R` | L4 | the `r` tool (code, record, note, timeout) and its result | r | P10 |
| `tool-read.R` | L4 | `read`: encodings, windows, images by magic bytes, large-file index | - | P10 |
| `tool-write.R` | L4 | `write`: atomic, encoding- and EOL-preserving | - | P10 |
| `tool-edit.R` | L4 | `edit`: multi-edit, fuzzy fallback, `*** Begin Patch` envelopes, routed through the document backend for recorded documents | - | P10 |
| `tool-diff.R` | L4 | diff engine (prefix/suffix trim, patience anchors, Myers capped at D = 256) | - | P10 |
| `tool-walk.R` | L4 svc | pruned walker, gitignore engine, glob to PCRE | - | P10 |
| `tool-search.R` | L4 | `gptr$grep()`, `gptr$find()`, `gptr$ls()` (radix sorting, raw prefilters, early stop) | - | P10 |
| `perm-classify.R` | L4 | `gptr_risk()`: R, command, SQL and Python classifiers over data tables | - | P11 |
| `perm-rules.R` | L4 | rule grammar, rule persistence (`settings.local.json`) | - | P11 |
| `perm-gate.R` | L4 | policy combination, mode table, critical and secret guards, protect size, non-interactive block | permissions | P11 |
| `perm-plan.R` | L4 | plan mode: scratch environment, `<proposed_plan>`, pending-plan hand-off | plan | P11 |
| `console-ui.R` | L5 | UI backends `console`, `none`, `scripted`, `rstudio`; one-line permission prompt | ui | P11 |
| `tool-ask.R` | L4 | the `ask` tool and its UI mapping | ask | P11 |
| `provider-anthropic.R` | L1 | `anthropic-messages` adapter: build, decoder, breakpoints, operator messages | anthropic | P12 |
| `provider-openai-responses.R` | L1 | `openai-responses` adapter: stateless replay of encrypted items and `phase` | openai | P12 |
| `provider-openai-completions.R` | L1 | `openai-completions` adapter + compat flags; `<think>` splitter | openai-compat | P12 |
| `provider-google.R` | L1 | `google-generative-ai` adapter: thought signatures, finish reasons | google | P12 |
| `s1-types.R` | L1 | `gptr_decision`, `gptr_choice`, `gptr_score` and methods; delayed vctrs methods | - | P13 |
| `s1-client.R` | L4 | `typesafe-system-one` adapter; bounded rounds on the reactor | system1 | P13 |
| `s1-route.R` | L4 | System 1 route: batch rule, `as_state()`, thresholds, abstention and escalation | - | P13 |
| `s1-cache.R` | L4 | per-element decision cache (memory, then `.gptr/cache/s1/`) | - | P13 |
| `s1-emulate.R` | L4 | opt-in emulation through structured output (uncalibrated flag) | - | P13 |
| `console-repl.R` | L5 | REPL loop, input grammar (`!`, `!!`, `/cmd`, fences, `"""`, `@mentions`), banner | console | P14 |
| `console-render.R` | L5 | chunk-invariant markdown stream renderer, tool lines, status line, verbosity | - | P14 |
| `console-interrupt.R` | L5 | interrupt policy: pause menu (steer, follow-up, continue, abort) via the `resume` restart | - | P14 |
| `console-commands.R` | L5 | built-in slash commands | - | P14 |
| `console-jsonl.R` | L5 | JSONL event-sink front end (Pi-named events, redacted) | jsonl | P14 |
| `doc-locate.R` | L4 | locate the calling statement (srcref, source frame, knitr, Quarto, IRkernel, Rscript, IDE, console) | - | P15 |
| `doc-blocks.R` | L4 | block grammar, ownership, idempotent upsert, stale and user-edited detection | - | P15 |
| `doc-io.R` | L4 | atomic raw I/O (EOL/BOM), md5 conflict checks, deferred Rscript writes, IDE backends | - | P15 |
| `doc-formats.R` | L4 | formats `r`, `rmd`, `qmd`, `ipynb` (own serializer), `transcript` | documents | P15 |
| `doc-replay.R` | L4 | replay modes, S2 answer cache, `gptr_doc()`, `gptr_source()`, `gptr_blocks()`, `gptr_cache()` | - | P15 |
| `doc-knitr.R` | L5 | `knit_print` methods, stale-chunk label hooks | - | P15 |
| `ckpt-objects.R` | L4 | copy-safe object pre-images, capture policy, settle, spill [G7] | - | P16 |
| `ckpt-files.R` | L4 | content-addressed file store, baseline and walk, 3-way restore | - | P16 |
| `ckpt-rewind.R` | L4 | checkpoint records, `gptr_rewind()`, `gptr_checkpoints()`, `/undo`, `/redo`, `/rewind` | checkpoints | P16 |
| `skill-discover.R` | L4 | skill discovery, lenient frontmatter (yaml), compact budgeted catalog, activation, `gptr_skills()` | skills | P17 |
| `skill-templates.R` | L4 | prompt templates, `/name args` expansion | prompts | P17 |
| `subagent-defs.R` | L4 | agent files (`.gptr`, `.claude`, `.codex`, `.pi` agents), tool-name map (Bash -> r), `gptr_agents()` | agents | P17 |
| `ext-plugins.R` | L0 | plugin packages and directories, `.claude-plugin` bundles, trust gating, `gptr_plugins()` | - | P17 |
| `mcp-client.R` | L4 | MCP client for both protocol eras; stdio and Streamable HTTP on the reactor; MRTR, progress, cancel | - | P18 |
| `mcp-config.R` | L4 | `mcp.json`, other harnesses' configs, TOML subset, `gptr_mcp()`, `gptr_mcp_add()`, `gptr_mcp_remove()` | - | P18 |
| `mcp-namespace.R` | L4 | `gptr$mcp$<server>$<tool>()`, budgeted signature catalog, lazy connect | mcp | P18 |
| `mcp-server.R` | L4 | MCP dispatcher over the session's tools; claude `sdk` transport; loopback HTTP; `gptr_mcp_serve()` | - | P18 |
| `auth-oauth.R` | L0 | PKCE S256, loopback or paste callback, locked refresh; `gptr_login()`, `gptr_logout()` | - | P18 |
| `subagent-backends.R` | L4 | backends `inline`, `worker` (callr), `cli`; limits; `auto` rule | subagents | P19 |
| `subagent-team.R` | L4 | teams (`agents =`), fan-out (`parallel =`), `gptr_parallel()`, `gptr_map()` | - | P19 |
| `subagent-worker.R` | L4 | `worker_main()` run inside callr children (JSONL events out, answers in) | - | P19 |
| `cli-common.R` | L1 | CLI discovery (native binaries preferred), minimum-version probe, one-time notice, billing-switch scrub | cli | P20 |
| `cli-claude.R` | L1 | `cli-claude` adapter: stream-json, control protocol, in-process `sdk` MCP, `can_use_tool` | - | P20 |
| `cli-codex.R` | L1 | `cli-codex` adapter: `codex exec --json --ignore-user-config -`, sandbox mapping, MCP via `-c` | - | P20 |
| `agent-background.R` | L3 | experimental background runs serviced by `later`; `gptr_jobs()` | - | P21 |
| `bridge-sh.R` | L4 | `gptr$sh/script/bg/jobs/out()`; the `interpreter` kind and built-in interpreters | bridges | P22 |
| `bridge-lang.R` | L4 | `gptr$py()`, `gptr$sql()`, `gptr$knit()` | lang | P22 |
| `artifact-app.R` | L4 | `gptr$app()`: working copy, immutable snapshots, callr child, validation ladder, screenshot | artifacts | P23 |
| `artifact-registry.R` | L4 | `gptr_artifacts()`, stop, relaunch, lazy orphan sweep | - | P23 |

### 3.3 `inst/` and shipped data

```text
inst/COPYRIGHTS                              Pi (MIT: tool schemas and strings, edit guidelines, overflow
                                             patterns, template grammar), models.dev (MIT), gitleaks-derived
                                             secret patterns (MIT); ideas credited to ellmer, tidyllm, btw (P01)
inst/extdata/models.json.gz                  pruned models.dev snapshot + dated price tiers + gptr overrides,
                                             schema_version, about 51 KB [09 §4] (P05)
inst/extdata/risk-functions.csv              R classifier table: package, function, level, category (P11)
inst/extdata/risk-commands.csv               shell command classifier table (G5 levels 0-4) (P11)
inst/gptr/plugin.json                        gptr's own manifest: its declarative resources are discovered
                                             exactly like any plugin package's (P17)
inst/gptr/skills/high-performance-r/         SKILL.md + references [19 §3] (P17)
inst/gptr/skills/shiny-bslib/SKILL.md        artifact house style [17 §4.4, G4 §3.1 artifacts text] (P23)
inst/gptr/skills/gptr-orchestration/SKILL.md sub-agents, teams, System 1 loops in scripts (P19)
inst/gptr/agents/reviewer.md, explorer.md    small default agent definitions (P19)
inst/gptr/prompts/review.md, explain.md      prompt templates (P17)
inst/gptr/fixtures/fake_cli.R                fake claude/codex CLI for tests and examples (P20)
inst/templates/vignette.Rmd, settings.json, gitignore     used by gptr_init() (P08)
```

### 3.4 Tests

One `tests/testthat/test-<area>-<topic>.R` per R file, owned by the same plan as the R file. Additional files:

| File | Purpose | Plan |
|---|---|---|
| `setup.R` | redirect `R_USER_CONFIG_DIR`/`R_USER_DATA_DIR`/`R_USER_CACHE_DIR` to a temp dir; blank provider keys unless `GPTR_LIVE_TESTS=true`; `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`; `GPTR_REPLAY=replay`; `OMP_THREAD_LIMIT=2` [13 §4] | P01 |
| `helper-fake.R` | scripted fake-provider scenarios | P01 |
| `helper-tracemem.R` | `expect_no_copy()`: fresh `Rscript --vanilla` process, `tracemem()` on the user object, skip without `capabilities("profmem")` | P01 |
| `helper-mock-server.R` + `fixtures/mock_server.R` | base-R SSE mock (serverSocket/socketSelect) run with processx; scenarios slow, TTFT, overload, 401, 429, truncated, parallel tools; `skip_on_cran()` [10a INFRA-24, 15 §5.1] | P01 |
| `helper-arch.R` + `test-arch-layers.R` | layer table of §2.2 and the codetools layering test | P01 |
| `test-copy-gateway.R` | tracemem rows for every gateway entry point (G3 t5 shape) | P08 |
| `test-copy-eval.R` | evaluator rows, including tool code in a function-frame home (G3 fact-check) | P09 |
| `test-copy-tools.R` | namespace members and designated values | P10 |
| `test-copy-s1.R`, `test-copy-ckpt.R`, `test-copy-subagent.R`, `test-copy-bridge.R`, `test-copy-artifact.R` | per-area copy rows | P13, P16, P19, P22, P23 |
| `test-context-prefix.R` | G4 20-turn byte-prefix property across turns, model switches, tool and skill activation, steering, modes, compaction | P07 |
| `test-bench-context.R` | offline CRAN-safe static budgets per preset and per section (§12.1) | P07 |
| `helper-scripted-ui.R` | scripted UI backend driver for REPL and permission tests | P11 |
| `helper-mcp-server.R` + `fixtures/mcp/server.R` | pure-R MCP fixture server speaking both eras | P18 |
| `test-secrets-e2e.R` | G6 end-to-end grep across all sinks with fake keys; negative control | P24 |
| `test-injection-e2e.R` | `{...}` payloads in model, tool, MCP and error text through every printer and condition constructor; asserts nothing evaluated (rule C1) | P24 |
| `test-northstar.R` | NS-1..NS-12 end to end on the fake provider and scripted UI | P24 |
| `test-live-anthropic.R`, `test-live-openai.R`, `test-live-google.R` | gated by `GPTR_LIVE_TESTS=true` and a key | P12 |
| `test-live-jev.R` | gated; reads the key only through `gptr_env()` | P13 |
| `test-live-cli.R` | gated; real `claude`/`codex` | P20 |

Fixture directories: `fixtures/sse/` (P12: anthropic, openai, completions, gemini streams incl. thinking,
redacted, encrypted reasoning, parallel tools, overload, truncation), `fixtures/jev/` (P13, 04a shapes),
`fixtures/cli/` (P20: redacted claude call-2 NDJSON, codex exec JSONL), `fixtures/mcp/` (P18),
`fixtures/docs/` (P15: `.R`, `.Rmd`, `.qmd`, `.ipynb` incl. Python-written floats), `fixtures/oracles/`
(P06: report 02's loop, store and recovery checks; P17: Pi's 67 template tests).

### 3.5 Repository and development files

| Path | Content | Plan |
|---|---|---|
| `DESCRIPTION`, `NAMESPACE` (roxygen), `.lintr`, `.Rbuildignore`, `.gitignore`, `LICENSE` (year 2026) | package skeleton; `.Rprofile` deleted | P01 |
| `.github/workflows/R-CMD-check.yaml` | r-lib check-standard (macOS, Windows, Ubuntu release/devel/oldrel-1) + oldrel-4 + no-suggests + `LC_ALL=C` job + copy-safety job on R-release and R-devel | P01 |
| `dev/style.R` | `gptr_style()` styler helper (conventions §4) | P01 |
| `dev/catalog/build_models.R` | builds `inst/extdata/models.json.gz` from models.dev | P05 |
| `dev/bench/tokens/`, `dev/bench/polyglot/`, `dev/bench/shiny-html/`, `dev/bench/cache-sim/`, `dev/bench/perf/` | token-efficiency and performance benchmark suite (§12.6) | P24 |
| `vignettes/*.Rmd.orig -> *.Rmd` | precomputed: getting-started, system-one, script-as-history, extending-gptr, token-efficiency | P25 |
| `README.Rmd`, `README.md`, `NEWS.md`, `cran-comments.md`, `_pkgdown.yml` | release documentation | P25 |
