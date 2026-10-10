# Living testing plan

Updated 2026-10-10. This is the coverage ledger for the current package, documentation and
authorized live testing. Update a row after inspecting its evidence; retain failed runs and
older revision results. It does not replace the numbered implementation plans or authorize a
release, model download, account change or CRAN submission.

## Status and evidence rules

`L` = observed live pass; `LR` = live plus fresh-process strict replay pass;
`O` = focused offline pass; `H` = historical offline/documentation gate;
`P` = planned, not yet executed; `F` = failed reproduction retained; `N/A` = genuinely
inapplicable capability. A pass applies only to its recorded revision, model, fixture and
frontend. A prepared fixture, catalog entry, login or model answer is not a pass.

Primary ledgers: [live harness](progress/live-harness-20261010.md),
[documentation/site](progress/documentation-20261010.md),
[CRAN readiness](progress/cran-readiness-20261010.md), and [handoff](HANDOFF.md).
Use newer dated sections when an earlier section says a now-completed check is pending.
Machine access inventories and raw local evidence belong only in ignored `LOCAL_SETUP.md`
and `dev/.validation/`; do not copy credentials, account details or private inventory into
this plan or public documentation.

| Verified installed revision | Actual scope | Evidence boundary |
|---|---|---|
| `4e66376` | Versa function/pipeline in native RStudio Source and console; independent coefficients/AIC; animated waiting indicator | Repeat passed with per-call recording disabled on both calls. This is older installed evidence. |
| `d1887f2` | Claude CLI, Codex CLI and exact Ollama Qwen function/pipeline; Jev typed Rmd; Versa Quarto and native RStudio Knit live/replay | Numeric oracles and real R objects verified. First notebook run passed computation but exposed a display defect. |
| `fc9f8d4` | Versa actual terminal controls; fixed Jupyter GUI live and new key-free replay kernel | Notebook Markdown/progress, one synced block, zero replay requests/errors/stderr, unchanged source fingerprint. Terminal background completed through an explicit pump; idle-only completion unproven. |
| `c722e6d` | Installed listing/timing, abort/accounting and child-temp changes; native RStudio manual tool created the verified mean 20.09062, excluded approval dwell and displayed bounded `/skills` columns | Install 19.45s, profiled family peak 396 MiB / 20 samples / zero sampling errors. O 464 listing/timing and 1,263 affected abort assertions. Abort tail/accounting and exhaustive installed display checks remain P. |
| `5b772f3` | Installed default Markdown width refresh; install 17.45s, profiler wall 17.74s, family peak 391.6 MiB / 18 samples / zero sampling errors | O 7 focused / 349 affected assertions, one CI-only skip. Actual native resize during output remains P; already-emitted scrollback cannot be reflowed by gptr. |

The coordinator's latest verified installation checkpoint is `f0f3448`.
Do not retag older live rows with it: confirm the installed SHA at every new run.
Native Unix prefix completion at `f0f3448` passed O 71 focused / 476 affected assertions,
one CI-only skip, zero failures/warnings and two-file lint clean. Immutable installation
passed in 13.89s (15 samples, 386.7 MiB peak, zero sampling errors). Actual native R readline
completed `!mtc`, `!!mtc`, a `stats::median` namespace prefix and a quoted file path; median
19.2 and file-existence TRUE matched their oracles. Exit restored the original separators
and preserved the dataset. That PTY's unprivileged profiler could not sample processes
(43 errors); its RAM result is unavailable. This is native terminal integration, not GUI
completion or active window-resize evidence.

Historical final gate `240db69` had 23,865 passing assertions and local CRAN 0/0/0;
it is not a current-artifact claim. Newer hosted results likewise apply to their own SHAs.

## Frontend and provider matrix

Each `P` cell needs a small real request and its numeric/type oracle, then strict replay where
recording applies. GUI observations must use the actual UI, not a headless renderer. Function
coverage is listed separately from executing a recorded `.R` file through an actual Rscript
child and its exit finalizer. CLI provider names must remain CLI routes.

| Requested provider/model | R PTY REPL | Terminal app | macOS R.app | RStudio GUI | VS Code R | Direct Rscript `.R` | Function/pipe in R | R Markdown | Quarto | Jupyter/IRkernel |
|---|---|---|---|---|---|---|---|---|---|---|
| Claude CLI: selected `claude-cli/claude-haiku-4-5` | P | P | P | P | P | P | L `d1887f2` | P | P | P |
| Codex CLI: `codex/default` (retain actual CLI model metadata) | P | P | P | P | P | P | L `d1887f2` | P | P | P |
| Ollama: exactly `ollama/qwen3.8:27b` | P | P | P | P | P | P | L `d1887f2` | P | P | P |
| UCSF Versa Azure: selected Luna deployment | L `fc9f8d4` | P | P | L function `4e66376`; LR Knit `d1887f2`; L manual tool/listing `c722e6d` | P | P | L `4e66376` in IDE | LR `d1887f2`, native Knit | LR `d1887f2` | LR `fc9f8d4`, actual GUI |
| Native Jev: `typesafe/jev-latest` / `jev` alias | P typed | P typed | P typed | P typed | P typed | P typed | P typed | LR `d1887f2` | P typed | P typed |

R PTY evidence does not establish a native terminal-app window or R.app/VS Code behavior.
VS Code 1.140.0 with R extension 3.0.1/syntax extension 0.1.4 and R.app R 4.5.0/GUI 1.81
were inventoried read-only. VS Code's `sess` bridge is absent from the checked R libraries;
its visible R session was unattached. `radian` was not found on the checked PATH/usual paths,
which is not an exhaustive absence claim. Native attachment, completion and rendering remain
P. Retain exact local setup in ignored `LOCAL_SETUP.md`: use the new `r.executablePath`,
`r.consolePath` and `r.consoleArgs` settings in a disposable workspace if needed, and avoid
sourcing an extension profile that also sources user startup files. External session attach
may install the bundled bridge/dependencies without prompting. Native Terminal app control
was unavailable under the computer-use access policy; VS Code inspection took 525s under host
load, which is client inspection latency rather than model/harness timing. Treat the user's
"Cordal" as Quarto unless corrected, and retain the actual application name/version.

Jev is a native decision route: its cells use logical/choice/fractional-score workflows,
not generated R agent loops. Native Jev teams/tool loops are `N/A`. Qwen is the verified
MLX/nvfp4 tag; do not substitute another quantization or infer a full-window context test.
OpenAI API, Anthropic API and Bedrock access have separate inventory-only records; no live
inference pass is claimed for them. Additional API/deployment coverage remains unscheduled
until selected explicitly. Availability, quota, pricing and structured-output support must be
checked separately from catalog/authentication inventory.

Prepared ignored controllers/fixtures are under `dev/.validation/live-20261010/`:
`driver.R`, `matrix-serial.py`, `notebook-headless.py`, `setup.R`, `renderer-support.R`,
`jupyter-support.R`, `timings.R`, regression/typed/team documents and the process-family
profiler. They are execution aids, not evidence. Root coordinates runs and the sole local R
slot. Headless notebook coverage supplements actual GUI observations.

## All guides and tables

Review every section, recipe, example output and table row against the installed APIs.
The current static inventory is 14 guides, 11 tables and 96 table body rows: configuration
5/45; execution model 2/14; interactive console 1/25; language models 1/5;
script as history 1/4; token efficiency 1/3. Recount after source edits. Table rows grouping
settings/options require every listed setting/option, including aliases, not one sample per
group. The documentation ledger reports 32 core settings, 90 runtime options and 63 exports;
cross-check the current manifest/reference before retaining those counts.

All 14 current guides precomputed offline with zero problems (`O`); the previous complete
site/documentation gate remains `H`. The latest README, function/configuration help comments
and [asset README](../man/figures/README.md) must share the in-memory story: work on already
loaded caller objects across turns, bounded model context, preserve originals, and distinguish
opt-in cache/checkpoint serialization from ordinary computation. Latest help comments still
need final private-overlay roxygen generation and affected README/guide precompute/checks.
`eval = FALSE` live/external recipes are `P`
unless a matching run below establishes them; successful fake chunks do not establish a live
provider, permission UI, MCP server or external engine.

| ID / guide | Mandatory coverage, including its tables | Current evidence and remaining check |
|---|---|---|
| G01 [Getting started](../vignettes/getting-started.Rmd.orig) | First call; result/session; same-session pipe; stopping; console; real connection; in-memory reuse | H fake examples; L selected function/pipes. P fresh quickstart through each frontend and preserved caller input. |
| G02 [Why Peter](../vignettes/why-peter.Rmd.orig) | Both namesakes; primary links; gptr/Peter naming; avoid claiming Wason coined System 1/2 | H source/site review. P refreshed links and wording check after rebuild. |
| G03 [Language models](../vignettes/language-models.Rmd.orig) | Provider table (all five rows); APIs; Azure/Bedrock; subscription CLIs; local Ollama; session lifecycle; functions/scripts; loaded-object reuse | L five requested routes in selected cells. P remaining matrix; other access inventory is not inference. |
| G04 [System 1](../vignettes/system-one.Rmd.orig) | Logical/probability; structured batch shape/names; uncertainty in filters/functions/loops; choices/levels/fractional scores; provenance/cache; routing/judging System 2; native/local/emulated engines | LR Jev Rmd logical/choice/score. P default-setting/service routing, emulation, native local classifier, calibration/uncertainty boundary and other frontends. |
| G05 [Interactive console](../vignettes/interactive-console.Rmd.orig) | All command-table rows/aliases and dynamic skill commands; prompt/@file/@object; `!`/`!!`; fences/triple quotes/continuations; approvals; interrupt/continue/steer/follow-up/abort/background | L Versa terminal subset, IDE function waiting and c722 native manual-tool timing/listing. O abort/listing, width refresh and native Unix prefix completion. L installed native Unix inline completion; P full command checklist, installed abort witnesses, active resize and remaining UI controls. |
| G06 [Configuration](../vignettes/configuration.Rmd.orig) | Scope table; all model/execution, context/history, extension/interaction tables; all option groups; precedence/unset/nested overrides; trust/egress; credential loading; matching configuration help for loaded objects and storage opt-ins | O current guide precompute; H config/security suites. P latest help regeneration, isolated user/project/process defaults and every current table row, including inactive registered settings. |
| G07 [Script as history](../vignettes/script-as-history.Rmd.orig) | Scripts/functions/pipes; binding/consent/opt-out; blocks/hash/cache; all four replay modes; R/Rmd/qmd/ipynb; custom-environment limit; notebook display/sync; workflow summaries and executable drafts | LR representative Jev/Versa documents and notebook. P direct exit finalizer, stale/user-edited/undone records, missing cache, all remaining matrix cells and summary/draft validation. |
| G08 [Teams/background](../vignettes/teams-and-background.Rmd.orig) | Named roles; element fan-out; independent parallel calls; deferred SDK; steer/step/wait/cancel; background; checkpoints/usage/history | H fake recipes; L terminal responsive background with pumped completion. P all real child backends, fan-out/team formats and cancellation/replay; idle-only completion unverified. |
| G09 [Tools/artifacts](../vignettes/tools-and-artifacts.Rmd.orig) | Objects/files/output; shell/scripts; background programs; Python/SQL/other engines; artifact versioning, launch, reopen, stop | H fake/read-only recipes and historical offline suites. P representative real optional engines/app UI, failure cleanup and permission prompts; do not assume installed tools. |
| G10 [Skills/plugins](../vignettes/skills-and-plugins.Rmd.orig) | Discovery/use; skill files; templates/instructions; agent definitions; packaged lazy factories; trust and precedence | H docs/offline suites; terminal discovery observed. P real skill invocation, template command, plugin activation/unload and changed-trust rejection. |
| G11 [MCP](../vignettes/mcp.Rmd.orig) | List/lazy connect; register; R tool members; HTTP auth; serve R; tools-only API; imported config/trust | L CLI-served R numerical returns; O isolated client/bridge cases. P standalone stdio/HTTP server, reconnect/auth expiry, allow/deny, disconnect and realistic UI discovery. |
| G12 [Extending gptr](../vignettes/extending-gptr.Rmd.orig) | Tool signatures and return values; permission policy; hooks; prompt/context/command components; other kinds; plugin packaging | H fake recipes/offline suites. P real minimal package/plugin round trip, event cleanup and protected-component refusal. |
| G13 [Execution model](../vignettes/execution-model.Rmd.orig) | Turn flow; caller/home/overlay objects; both interface/reference tables (14 rows); return capture/history; permissions/concurrency; direct in-memory iteration | L real fit/beta values; H fake examples. P repeated caller identity/copy-safety proof and worker/CLI/nested ownership boundaries. |
| G14 [Token efficiency](../vignettes/token-efficiency.Rmd.orig) | Prompt inspection; descriptions/results; reported/estimated/unknown usage; budgets/partial results; all three cache rows; compaction/context; source benchmark | H token ratchet and examples; O abort unknown accounting. P live partial usage, modest workload profiling, compaction/cache/checkpoint serialization and actual large-object headroom run. |

The current 63-export checklist below closes gaps that a guide example may not exercise.
Names have the `gptr_` prefix except `peter`; each needs a current reference/example check
and a behavior oracle, with destructive/authentication effects restricted to disposable
fixtures. Historical full-suite coverage is H; no all-export live pass is claimed.

| ID / API group | Every exported name to account for | Acceptance cross-reference |
|---|---|---|
| A01 gateway | `peter` | G01/G03/G04/G05, X01, all frontend/provider cells |
| A02 setup/security | `init`, `config`, `env`, `trust`, `login`, `logout`, `scrub`, `providers`, `models`, `permissions` | G03/G06, X06/X10/X13; fake vault for login/logout, synthetic temporary content for scrub |
| A03 session SDK | `step`, `wait`, `steer`, `cancel`, `fork`, `on`, `parallel`, `sessions`, `resume`, `last`, `checkpoints`, `rewind`, `jobs`, `usage`, `return` | G08/G13/G14, X01/X04/X07/X11; value return, attributes, ID lineage and listener cleanup |
| A04 introspection | `prob`, `risk`, `describe`, `prompt`, `preimage`, `redact` | G04/G13/G14, IM02/IM03, X10/X11; class/method/display plus retained canonical values |
| A05 documents/artifacts | `doc`, `source`, `blocks`, `cache`, `artifacts` | G07/G09, X02/X03/X09; formats, consent, fingerprint, missing records and lifecycle |
| A06 discovery/MCP | `agents`, `skills`, `plugins`, `mcp`, `mcp_add`, `mcp_remove`, `mcp_serve` | G08/G10/G11, X07/X08; actual discovery/activation/connection boundaries |
| A07 constructors | `tool`, `provider`, `adapter`, `router`, `hook`, `policy`, `agent`, `command`, `prompt_section`, `context_block`, `backend` | G12, X08; valid/invalid specs, registry contracts, priority and protected records |
| A08 extension API | `api`, `spec`, `register`, `registry`, `reload`, `check`, `fake_provider`, `tool_result` | G12, Q01; validation, lazy loading, reload/state cleanup and independent conformance oracle |

## System-wide decisions and capability-gated emulation

Verify source routing as well as output type. `gptr_config(system1 = ..., .scope = "session")`
sets this R process's decision default; `.scope = "user"` sets the user default in an isolated
test user directory. `options(gptr.system1 = ...)` is the options layer. Explicit call model
arguments choose that call; inspect `gptr_config()` and its `sources` attribute. Never change
the real user's defaults for a fixture.

Current source [model_default](../R/catalog-models.R) resolves `system1 = NULL` to enabled
`typesafe/jev-latest` when its key is available, otherwise an already-discovered, verified
local classifier. It starts no discovery and does not opt into emulation. The `ctx$decide()`
service uses that role default. [s1_target](../R/s1-route.R) requires an explicit emulation
setting; a bare `emulate:` call reference alone does not enable it. The `jev` alias uses the
configured emulation route when opted in; separately test explicit native references.

| ID / route | Acceptance | Status |
|---|---|---|
| D01 native Jev explicit | Logical, choice and fractional score; names/shapes; probability/risk/provenance; fresh recording/replay | LR selected Rmd `d1887f2`; P other frontends/uncertainty cases |
| D02 system-wide native default | Isolated user/process/options precedence, remove override, restart; decision service actually uses the role default; compare explicit typed calls and ensure their requested native reference is not silently replaced | P live; H offline semantics, current source inspected |
| D03 no-key/local fallback | No new discovery/network; evidenced local decision model selected; absent/unsuitable model gives an honest actionable error | P installed/live witness; offline cases historical |
| D04 native Ollama Clef/Clef Flash | Actual installed classifier and suitable server; local-only preflight; no cloud fallback; types/provenance/cache/replay | P, conditional on inventory/headroom; Qwen chat pass is not this pass |
| D05 emulated chat decision | Explicit `system1 = "emulate:<provider>/<model>"`; structured response; `calibrated = FALSE`, emulated engine; no accidental native claim; uncertainty/cancel/budget/replay | P Versa/Qwen/API candidate after capability check |
| D06 CLI/emulation boundaries | CLI catalog metadata currently advertises `structured_output = FALSE`; verify supported behavior or explicit failure before scheduling emulated inference | P capability/negative check; do not promise native probabilities or assume CLI emulation |
| D07 route composition | System 1 routes/judges a System 2 answer; intended model and data shape, no unnecessary call on cache hit, no recursion/deadlock | P live, bounded representative provider |

No model-derived probability establishes empirical calibration. Assess calibration separately
on a relevant labeled set; synthetic fixture accuracy is a type/routing oracle.

## Priority: work on objects already in R

| ID | Concrete check | Status / constraints |
|---|---|---|
| IM01 reuse across turns | Start with an existing caller `dat`; fit, inspect residuals and compare a second model in one session. Also attach a loaded numeric `counts` symbol, compute `totals = colSums(counts)`, return six largest totals, then reuse `totals` to assign a named plot. Verify real objects and no reread/export/overwrite requirement. | L small selected function/pipe; P matrix/plot multi-iteration fixture across frontends |
| IM02 caller identity/copy safety | Preserve the original input binding/value, record base `tracemem()`/object lineage where observable, compare after read-only analysis, and verify separately named results. Check classed/reference-containing inputs separately. | P explicit identity witness; numeric success alone is insufficient. Do not promise universal zero-copy or an R sandbox. |
| IM03 model-bound context | Attach only required public objects; inspect bounded matrix descriptions/prompt/tool outputs. R computes on the live object, without an obligatory whole-object upload to the model. Compare summary/names/none, and native decision inputs separately. | P concrete prompt/transport witness. Current conversational `context = "none"` suppresses attached workspace descriptions; model tool results and native typed-input serialization are separate paths. |
| IM04 modest profiling | Seeded statistics/ML fixture, several iterations, bounded returned output; record elapsed/first-feedback/first-text/R-tool time and R-family memory. | P while machine is busy; one local job, no large allocations |
| IM05 actual large-object test | Approximately 4 GiB genuinely loaded R object, reuse over several iterations, identity/invariance plus measured RAM/latency; distinguish model-server allocation from R-family RSS. | P deferred until coordinator confirms headroom. No unrelated model termination, mass copying or fan-out to force the run. |
| IM06 storage boundaries | Contrast direct loaded-object analysis with deliberate file-backed inputs. Test cache/checkpoint/undo serialization, opt-outs, size limits and cleanup independently. | P; in-memory computation does not imply no disk storage when those features are enabled. |

## Native UI, active resizing and completion

Default Markdown rendering now refreshes width per write/final flush (O; installed `5b772f3`),
while an explicit width remains fixed. The scoped native Unix `!` separator fix is O at
`f0f3448`; installed/live completion remains P. Neither proves a native GUI behavior.
Current input uses R's `readline()`; that fact alone does not prove native R completion works
behind the Peter `!`/`!!` prefix in each client.
Editor completion, interactive readline input and rendered document output are different
surfaces. Ordinary R function/script syntax does not gain Peter-chat prefixes.

| Surface | Available/observed behavior | New live UX checks |
|---|---|---|
| R PTY | L streamed output/controls `fc9f8d4`; F bare `!mtc`/`!!mtc` completion on actual R 4.5; ordinary `mtc`/`! mtc` completed; O scoped Unix fix `f0f3448` | P installed prefix completion and restoration; outside-evaluator width changes. No native window-management claim |
| Native Terminal app | Actual computer-use control unavailable under access policy | P resize its actual window during output; native readline completion/input, font/scale and spinner behavior |
| macOS R.app/R Console | Local app metadata inventoried; bundled FAQ documents Tab/Ctrl-. completion and future-output width updates | P actual gptr console resize/completion, multiline input, stop behavior and cleanup; Unix TTY fix does not cover this GUI |
| RStudio | L Source/function, Knit, thinking indicator and c722 manual-tool timing/listing. Native R prompt completed `mtc`/`!mtc`; F Peter-prompt completion for bare/`!` input | P client-owned editor/readline completion integration; active resize/scale/wrapping. AX maximize/restore is not resize proof; partial-stream Esc attempts completed too early (not reached) |
| VS Code R extension / native R / alternative console | Local versions inventoried; visible session unattached and `sess` prerequisite missing in checked libraries; radian availability unproven | P isolated attached-runtime fixture, native completion/prefix handling, active resize, controls and restoration; keep editor/LSP/terminal distinct |
| Jupyter/IRkernel | LR actual GUI safe Markdown, stdout progress and one pending code display | P cell/editor completion versus input prompts, active browser/window/scale changes during output, tables/fences/tool/status wrapping and kernel interrupt cleanup |
| Rmd / Quarto editor and rendered report | LR selected rendering; editor integration P | P editor completion and resize independently; inspect rendered code/tables after render. A report is not a Peter readline console. |
| R functions / direct Rscript | L selected function/pipe; direct exit-finalizer P | P native editor completion independently; bounded noninteractive wrapping/progress and exit cleanup. Autocomplete in an unattended process is N/A. |

The latest RStudio post-exit summary fixture called an unexported `gptr_status`, so its
summary failed (fixture F, not a package regression). Cleanup independently restored the
repository directory, empty workspace, unloaded gptr namespace and disabled live gate.
Native screenshots were unavailable for this probe; AX evidence does not certify aesthetics.

- UX01: resize the active native window/pane **while** model text streams and while a real tool
  is running; capture before/during/after widths and actual scale. Exercise wide tables, code,
  tool previews/results, status and thinking/spinner lines. Check new output uses the available
  width, content stays readable, and no stale/redraw/duplicated indicator or lost input remains.
  A viewport set only before output does not satisfy this case; record capabilities/limits.
  Measure host width outside model R and `!`/`!!`: evaluation temporarily uses capture width
  100, so an inline width result does not establish native pane/window width.
- UX02: establish normal native R completion first, then test loaded object names, functions,
  `pkg::` namespaces, quoted file paths in a disposable directory and multiline expressions
  behind both `!` and `!!`. Observe actual completion suggestions and inserted text, not only
  whether the final expression evaluates. Check prompt/slash command completion separately.
- UX03: repeat native completion after exit, interrupt and error; restore any introduced
  completion handlers, input state, width/options, editor preferences and window/scale changes.
  No persistent interfering R setting is acceptable. Missing prefix-aware completion is a
  recorded product/client integration gap. O Unix separator restoration covers ordinary exit,
  setup cancellation, errors, interrupts and nesting; actual installed restoration remains P.

The Unix fix requires interactive native TTY input with readline available and completion
enabled. It preserves a full custom completer and skips GUI/Jupyter/document/noninteractive/
stdin modes; it does not replace R's completer or implement slash-command completion.

Respect client ownership: RStudio/VS Code/R.app/Jupyter supply their native editor completion,
window/scale controls and some display reflow. gptr owns its generated output width and
prefix/input integration where the client permits hooks. Aim for compatibility with those
clients and libraries; a limitation may require a client-side change. Record exact setup,
the observed boundary and proposed owner rather than promising gptr can replace native UI.

## Cross-cutting acceptance checklist

| ID | Acceptance and failure cases | Current boundary |
|---|---|---|
| X01 values/lifecycle | Numeric/type/shape/names oracles, actual objects, caller environment, nested `gptr_return`, continuation, status/history, resume/fork, deferred `.run = FALSE` and step/wait/cancel | L selected functions; O served-return fix; P direct deferred/Rscript lifecycle matrix |
| X02 recording/workflow exports | Explicit binding consents; persistent off prevents automatic recording; per-call logical FALSE wins even when bound; TRUE grants no new consent. Exactly 1 regression / 3 typed / 2 team blocks; post-exit hashes. Generated narrative/script drafts must be reviewed/run, never labeled an automatic verified export. | O recording guards; LR selected documents; P all mode/finalizer/export cases |
| X03 strict replay | New key-free process/kernel, original provider metadata, zero before-request events, zero fresh usage events and zero new native usage-log rows; unchanged source/cell/gptr fingerprint, correct R results. Team child numeric values require explicit exports; absent exports test cached reports/metadata, not persisted numerics. | LR selected Jev/Versa; P remaining cells and team replay |
| X04 interactive controls | Genuine in-flight request and R-tool steer; follow-up; continue; partial-stream abort then recovery; two idle interrupts/EOF/exit; IDE stop key/fallback; background responsiveness and explicit pumped completion | L Versa terminal subset. RStudio partial-stream interruption not reached; P installed abort repair and other provider/RStudio/Jupyter control cases |
| X05 progress/display | Visible early thinking feedback, delayed first byte/cold model/tool wait, no silent hang, spinner cleanup after pause/continue/steer/abort/error; separate safe final abort tail; quiet/v0 and knitr gates; ordinary IRkernel stdout progress with true errors separate; safe Markdown and one pending code display | L fc9 terminal/Jupyter; O abort/listings/width refresh. L c722 RStudio bounded listing/timing only; P installed abort, active resize and other frontends. No notebook cursor-animation promise. |
| X06 commands/settings | Each G05 row/alias/dynamic command; full resume IDs; bounded readable skills/MCP listings with full invisible values. Every G06 setting/option row, precedence/source/unset/type errors, inactive setting limits, no user-state leaks | L terminal subset and c722 RStudio `/skills`; O bounded listings. P full IDs/MCP installed UI, exhaustive tables and native completion/slash boundaries |
| X07 teams/fan-out | At most two fixture children; names/status/usage; independent mean/median values; worker/coroutine/CLI attribution; queued/in-flight steer, cancellation, budget/depth, nested calls, recording and replay by format | P live; H offline acceptance. Source ownership must not infer preserved child values without exports. |
| X08 skills/plugins/MCP | Real skill/template selection; agent definitions; trusted packaged factory lazy loading; tools-only MCP and server lifetime; transport/auth/reconnect; filtered discovery and trust renewal; no protected-policy replacement | P end-to-end; H/O focused offline and CLI bridge evidence |
| X09 tools/apps | R and bounded shell; optional Python/SQL engines; permission previews/denials; read/write/edit; output/plot truncation; artifact create/version/reopen/stop; Shiny dependency and browser UI; exact owned child cleanup | P representative live/UI; H offline suites, optional-engine skips named |
| X10 security/restoration | No credentials in prompt/events/logs/doc/cache/display; synthetic split-secret/bidi/markup tests; context/egress/local-only/trust restrictions; permission allow/ask/deny and guarded actions; original input invariant; cwd/options/env/libs/seed/listeners/binding restored; no orphaned owned processes | O synthetic guards; L selected cleanup/UI; P new installed/failure-path witnesses. In-process R is not a security sandbox. |
| X11 usage/budget/cache | Known vs estimated vs unknown tokens/cost; abort once/request; preserve known partial usage; no implied zero charge; pricing tier and lower-bound budget behavior; cache-hit no request; compaction/checkpoint/rewind partial restoration | O abort accounting; H suites/ratchet; P live unknown/limit/cache/compaction cases |
| X12 performance/resources | Installed SHA, first visible feedback, first normalized text, request/tool/completion intervals; approval dwell excluded from R execution duration; CLI telemetry gaps labeled. Sample owned process-family peak RSS and server/GPU allocation separately; deadline/cancellation cleanup and cold/warm comparisons | L selected timings/profiles and c722 RStudio exclusion of approval dwell; O execution timing. P comparable matrix/remaining installed repair; client inspection latency is separate |
| X13 transport/auth/availability | API adapter content/usage/error normalization; SSE/JSONL partial streams; connect/first-byte/idle limits; retry/backoff versus definitive quota; CLI model/path/stdin and served token attribution; offline/no-key/absent optional package or executable; login/logout/expiry in isolated fake vaults | H/O provider/auth/HTTP/CLI regressions; L selected routes/quota reproduction. P current installed negative cases; no real shared-account logout or credential changes. |
| X14 other inputs/UI | Bounded images/plots/attachments and unsupported-modality errors; human question/approval deny/cancel; piped stdin EOF and registered JSONL frontend distinct from native console; summary/print/str/format/rich repr without eager optional loading | H/O input/UI/display suites; L selected terminal/Jupyter. P remaining actual frontend/adapter capabilities. |

Every timeout has an outer controller deadline and cleanup limited to the exact spawned tree.
A wait timeout alone does not cancel a session. Existing driver request waits use 180 seconds;
larger renderer/controller deadlines are explicit per-run metadata, not provider performance
targets. Positive live request/usage witnesses distinguish inference from cache/replay. When a
CLI does not expose every MCP tool event, actual R objects and numeric oracles remain mandatory.

## Documentation, site and recurring release gates

| ID | Required recurring check | Latest evidence / next action |
|---|---|---|
| Q01 documentation | All 14 guide precomputes; README, function/configuration help and asset README in-memory wording; man aliases/examples, every options/command table row, source/output consistency and no live chunks; private-overlay generation preserves the maintainer's DESCRIPTION preference | O 14 current guide precomputes with zero problems. H 58 example pages/71 documentation assertions/site gate. P latest help-comment roxygen, affected README/guide regeneration and final consistency checks |
| Q02 site/branding | Homepage/quickstart/Why Peter prominent; all guide/reference links; nine original logo assets unchanged; light/dark/auto; native menu/theme persistence; code/table overflow keyboard focus; representative 320–1920px layouts and doubled text | H 90-page audit, 60 viewport/theme cases and text-scaling check. P rebuilt-site recheck; text scaling is not actual browser zoom coverage. |
| Q03 CRAN periodic | Focused isolated tests/lint then docs/files; examples/precompute when changed; current dependency metadata including optional `Enhances: repr`, absent-optional load/display, pure R/fixed Imports, source/archive exclusions and credential-free offline tests | O focused metadata/display/temp guards; P current exact archive contents, sizes and checks. No eager repr load found. |
| Q04 resource/size/timing | Record install/example/test/vignette timings, slowest pages, actual tarball bytes/hash, installed `du -k` and largest directories; watch source near 10 MB and docs/data near 5 MB; check at most two cores | P fresh artifact; prior static sizes/oldrel installed-size diagnostic are historical, not archive measurements. |
| Q05 platform/current artifact | Existing hosted matrix with exact SHA; current R-release/R-devel exact-tarball `--as-cran`, Windows and reverse dependencies; force-killed child temp cleanup on Windows; manual/incoming/URL checks | Historical gates only; current Windows cleanup and final artifact validation P. Hosted checkout rebuilds do not prove byte-identical upload-tarball validation. |

Reuse existing isolated tools sequentially: `dev/ci/isolated-check.R test <filter>` / `lint`,
`dev/release/check-docs.R`, `check-files.R all`, `check-examples.R` and
`precompute.R --check`. Always use `Rscript --vanilla`; no live models/keys during offline
checks. Do not broaden passed tests without new failures or concerns. Final build/check and
submission remain coordinator/maintainer actions; consult current
[CRAN policy](https://cran.r-project.org/web/packages/policies.html) and the CRAN readiness ledger.

## Next work and unscheduled coverage

1. Finish installing completion checkpoint `f0f3448`; verify native Unix prefix completion
   and restoration, repaired abort tail/unknown usage, bounded
   listing IDs and execution-only durations in the actual terminal without weakening redaction.
   Width refresh is installed at `5b772f3`, but active native window-resize remains P. Client
   inventories are complete; isolated VS Code attachment and GUI integration remain P.
2. Run fresh direct-Rscript/deferred cases and the remaining small provider/frontend cells
   serially; pair each recordable pass with strict replay and the fresh-request witnesses.
3. Run bounded teams/fan-out and in-flight steering per applicable conversational provider,
   then representative team documents/GUI controls; keep nonexported replay-value expectations
   honest. Complete system-wide Jev defaults and capability-gated emulation.
4. Complete every guide/table acceptance checklist, skills/plugins/MCP/tools/artifacts and
   modest in-memory multi-iteration profiling and UX01–UX03 across native surfaces; record
   all omissions as P and identify proposed integration gaps explicitly.
5. Rebuild/inspect the changed site and periodic CRAN gates; schedule the actual 4 GiB object
   only after resource recovery. Current artifact/release gates remain separate.

Before expanding local work, follow AGENTS resource thresholds: inspect CPU/load, memory/
swap, disk and thermal state; do not expand during pressure/active swap, disk below 200 GiB,
low CPU idle or sustained load above 14. Keep the current lanes serial and avoid additional
subagents while those limits are crossed. The large-object/GPU cases need a fresh coordinator
resource decision; preserve unrelated user processes and models.

Unscheduled gaps: additional OpenAI/Anthropic/Bedrock inference, other deployments/models,
native local decision models not already available, idle-only background completion across
frontends, full-window Qwen context/accuracy/calibration, actual browser zoom/accessibility
audit beyond existing reflow checks, large external-engine workloads and other OS GUI tests.
Promote a gap to a concrete planned case before running it; never silently omit it or mark
an unsuitable capability passed. New failures get a minimal reproduction and an offline
test-first fix before repeating the affected live case.

## How to update this ledger

For every case retain: case ID; installed SHA/version and artifact hash; actual R/frontend/
renderer/kernel/CLI versions; exact model/route/deployment metadata; live/replay phase; seeded
public input; independent oracle; request/usage/native-row witnesses; session/child states;
document blocks/fingerprint; visible UX evidence; elapsed and peak-memory scope/sampling
errors; warning classes; controller exit/deadline; restoration booleans and owned-PID cleanup.
Record the evidence path and PASS/FAIL/PENDING/NOT REACHED. A screenshot or answer alone is
insufficient. Keep private logs/tokens/account inventories out of versioned records.

Run the [cross-plan consistency sequence](research/assets/consolidation-tools/README.md)
after a plan edit. These scripts index P01–P25, so also review this ledger's links/counts/statuses:

```sh
T="$PWD/dev/research/assets/consolidation-tools"
python3 "$T/build_index.py" --quiet
cd "$(mktemp -d)" && python3 "$T/extract.py"
Rscript --vanilla "$T/check_r.R"
mkdir lint && for f in blocks/*_r_d0.txt; do cp "$f" "lint/$(basename "$f" _r_d0.txt).R"; done
Rscript --vanilla "$T/lint_all.R" lint
```

`build_index.py` itself launches Rscript; it is not a pure-Python lane. The completed
coordinator check indexed 25 plans/307 tasks/1,446 blocks (746 R), 4,389 definitions and
28,337 resolved calls: 910 findings (821 info, 89 warn, zero error). Extraction/validation
covered 770 R blocks with zero parse/style problems; lint reported zero findings. Nested
P17 skill examples produced `LONG` notes, not failures. The 89 warnings were reviewed by
category: recorded cross-owner edits, call-shaped signatures, prototype/removed names,
historical contract spellings and later functions already present in current runtime; no
new runtime blocker or numbered-plan edit was identified. The checker README's historical
74-warning baseline is stale. A final coordinator rerun after this ledger update remains P;
the ledger itself is not indexed by those P01–P25 scripts.

