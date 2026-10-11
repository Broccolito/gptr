# Living testing plan

Updated 2026-10-10 with resumed heavy-compute evidence and explicit storage, extension,
file/network and compaction acceptance cases. New rows use ongoing/done/waiting notation.
This is the coverage ledger for the current package, documentation and
authorized live testing. Update a row after inspecting its evidence; retain failed runs and
older revision results. It does not replace the numbered implementation plans or authorize a
release, model download, account change or CRAN submission.

## Status and evidence rules

`L` = observed live pass; `LR` = live plus fresh-process strict replay pass;
`O` = focused offline pass; `H` = historical offline/documentation gate;
`P` = planned, not yet executed; `F` = failed reproduction retained; `N/A` = genuinely
inapplicable capability; `LGUI-O` = observed native GUI pass with an offline scripted provider,
without live inference. A pass applies only to its recorded revision, model, fixture and
frontend. A prepared fixture, catalog entry, login or model answer is not a pass.

Primary ledgers: [live harness](progress/live-harness-20261010.md),
[documentation/site](progress/documentation-20261010.md),
[CRAN readiness](progress/cran-readiness-20261010.md), and [handoff](HANDOFF.md).
Use newer dated sections when an earlier section says a now-completed check is pending.
Machine access inventories and raw local evidence belong only in ignored `LOCAL_SETUP.md`
and `dev/.validation/`; do not copy credentials, account details or private inventory into
this plan or public documentation.

## Resumed execution

The maintainer explicitly requested completion of the remaining local-heavy cases after
freeing compute. At 16:37 PDT CPU idle was 49.55%, load 6.61/9.17/18.23 and physical RAM
had 23 GiB unused. Swap remained 43,625.81 MiB used; free disk was only 12 GiB. Thermal and
performance warnings were not recorded. Resume with two compute lanes, at most two workers
per internally parallel check, BLAS one thread, one new GPU request at a time, fresh owned
run directories, bounded deadlines and periodic resource checks. Keep small artifacts;
preserve unrelated processes/models and all failed evidence. This authorization supersedes
the earlier deferral; it does not authorize cleanup of user files or broad process killing.

One lane performs exact-artifact/CRAN validation, after correcting any discovered package
defects. The other performs live provider/frontends, team/fan-out, steering, native/local/
emulated decisions and in-memory performance cases. Read-only agents audit current hosted CI,
coverage and client integration. Native UI observations remain distinct from scripted stdin
and headless renderers. Recheck the installed source manifest after every runtime change.

Hosted `68017d0` exposed two forbidden IC-33 edges in the native MCP recording repair.
The reviewed refactor `d136a9d` passed 642 affected assertions; spinner-width repair
`3d92b05` passed 177 affected assertions. The normal `3d92b05` archive passed local
`--as-cran` on R 4.5.0 with 22,603 assertions, zero errors/warnings/notes and 386 skips.
Its compressed size is 2,216,695 bytes, SHA256
`5ced56de6454cba771af7fff4a6459a22a5fb2258b351ee92ce678e0a9899d05`, with 14 built guides;
normal installed size is 6,592 KiB. Installed-size INFO is retained, not suppressed. Docs,
files, full lint, fresh examples and all-14 precompute checks also passed. This is a local
R 4.5.0 diagnostic; current-release/devel/Windows exact-byte checks remain pending.

Fresh `3d92b05` Azure emulated decisions/cache, Azure team/fan-out and native Jev typed
source workflows passed live and fresh-process replay. Initial fan-out and empty-settings
fixture failures remain preserved; context names and canonical empty settings resolved them
without increasing budgets. Queued/background steering failed input discovery, and a
simulation changed an input integer type after returning the correct result. Corrected
input visibility/protected bindings are prepared for fresh repeats; no pass is inferred.
Actual VS Code active streaming/tool resize passed with widths 73/92/37, two tools and all
eight restoration checks true. Azure/Jev GUI live and same-process fresh-namespace replay
passed; Claude CLI reported a session limit resetting at 18:00 PDT and its remaining cases
are blocked until then. A notice printed into a thinking row is under separate review.
See [artifact evidence](progress/artifact-resume-20261010.md),
[coverage audit](progress/coverage-resume-20261010.md), and
[client evidence](progress/client-integration-resume-20261010.md).

| Verified installed revision | Actual scope | Evidence boundary |
|---|---|---|
| `4e66376` | Versa function/pipeline in native RStudio Source and console; independent coefficients/AIC; animated waiting indicator | Repeat passed with per-call recording disabled on both calls. This is older installed evidence. |
| `d1887f2` | Claude CLI, Codex CLI and exact Ollama Qwen function/pipeline; Jev typed Rmd; Versa Quarto and native RStudio Knit live/replay | Numeric oracles and real R objects verified. First notebook run passed computation but exposed a display defect. |
| `fc9f8d4` | Versa actual terminal controls; fixed Jupyter GUI live and new key-free replay kernel | Notebook Markdown/progress, one synced block, zero replay requests/errors/stderr, unchanged source fingerprint. Terminal background completed through an explicit pump; idle-only completion unproven. |
| `c722e6d` | Installed listing/timing, abort/accounting and child-temp changes; native RStudio manual tool created the verified mean 20.09062, excluded approval dwell and displayed bounded `/skills` columns | Install 19.45s, profiled family peak 396 MiB / 20 samples / zero sampling errors. O 464 listing/timing and 1,263 affected abort assertions. Abort tail/accounting and exhaustive installed display checks remain P. |
| `5b772f3` | Installed default Markdown width refresh; install 17.45s, profiler wall 17.74s, family peak 391.6 MiB / 18 samples / zero sampling errors | O 7 focused / 349 affected assertions, one CI-only skip. Actual native resize during output remains P; already-emitted scrollback cannot be reflowed by gptr. |
| `390485f` | LR Versa direct Rscript/Rmd/Quarto and native Jev recorded R/Rmd/Quarto; LGUI-O actual R.app streamed resize | Install 20.09s, profiler wall 20.52s, 399.6 MiB / 21 samples / zero sampling errors. Six document cells passed live/replay. Claude direct Rscript live passed, fresh replay failed with an empty recorded R body; retained F. |
| `8d13b58` | Installed CLI MCP recording repair; LR all nine Claude CLI/Codex CLI/exact Qwen direct Rscript/Rmd/Quarto cells | Install 29.51s, 417.1 MiB / 31 samples / zero sampling errors. O 48 focused / 1,601 affected assertions, zero failures/warnings/skips, three-file lint clean. All 18 document phases passed with one nonempty block per cell and zero replay requests/fresh usage/native rows. GUI and other outstanding cells remain P. |
| `3d92b05` | Verified normal archive installed; local CRAN check/source gates; LR Azure emulated decisions/team-fanout and native Jev typed source; VS Code active width and Azure/Jev live/replay | Exact archive/hash above. Native GUI replay uses a fresh namespace/vault in the same R process, distinct from LR. First post-install verifier incorrectly counted generated index.html; installation DONE and a separate 14-guide/loadability certificate passed without reinstalling. |

The coordinator's latest verified installation checkpoint is `8952567`: normal archive
SHA256 `e22172a337fe8efd6383aa570675061aae193fc7b1c7bff5680490e85550c6a8`,
2,218,170 bytes, 14 built guides, install14.19s/421.5MiB sampled family peak/zero sampling
errors. The notice fix passed42 focused/184 affected assertions, one CI-only skip and zero
counted warnings. Exact local and hosted archive checks for this revision are ongoing.
Do not retag older live rows with it: confirm the installed SHA at every new run.

Resumed completions: native VS Code Codex/Qwen live and same-process fresh-namespace replay
passed at `3d92b05`; native RStudio active resize passed widths199/122, two tools and all eight
restoration checks. Native R.app's newer probe passed static layout/computation/restoration,
but its automation call blocked through execution, so that run does not establish active
resizing. Direct Jev Rscript passed live and fresh-child replay at `3d92b05`. Corrected Azure
running-session and pumped-background steering passed at `8952567` (8.693s); protected seeded
simulation passed (4.720s). The earlier failures remain retained. A canonical offline request
spy proves the original queued-steer fixture omitted the initial prompt/context; no runtime
queue-order change or budget increase was needed. Latest headless IRkernel and native RStudio
provider/decision cells are ongoing; completed cell details belong in the resumed progress
ledger. RStudio emitted repeated warnings despite numeric passes and requires diagnosis.

The true4GiB fresh-Rscript Azure probe passed at `3d92b05`: three exact read-only R aggregate
tools on the same ordinary536,870,912-double vector, unchanged identity/input, six bounded
requests,17.261s controller elapsed,4,287.75MiB sampled family peak and all cleanup witnesses.
No tracemem duplication was observed; retained owned files peaked27,290bytes. This closes the
specific IM05 synthetic read-only case, not universal zero-copy or all GUI memory behavior.
Qwen's separate17.945GiB server allocation expired naturally after its default keep-alive;
R-family RSS and external model residency remain separate measurements.

## Added file, extension, storage and compaction execution cases

The maintainer requested these explicitly during resumed execution. `DONE` means only the
scoped evidence stated here; `ONGOING` has an active investigation/run; `WAITING` has a concrete
case awaiting its serial slot or a required capability. Run each case in its own disposable
project/user root, preserving the real repository `.gptr`, caller objects and all failed
evidence. Pair live file-producing cases with independent reopened-file oracles. Public
network fixtures have bounded response/file sizes, timeouts and no confidential inputs.
Skill upload means import/install into the owned local fixture registry unless a specific
external destination is authorized. Never expose the test MCP server publicly.

| Case | Required execution and independent oracle | State |
|---|---|---|
| FT01 load/write | Text/CSV/JSON/RDS and R/Rmd/qmd/ipynb: read public seeded inputs, write through approved tools, reopen and compare bytes/types/numeric content; check overwrite refusal, invalid format/path and interrupted write cleanup | WAITING live; earlier installed tiny file tests O |
| FT02 web/data | Distinguish model-native web search from the gptr tool-catalog search; test available route, citations/URL provenance, bounded HTTPS public data download, parse and numerical oracle; failed/oversized download leaves no partial final file | ONGOING capability audit; unavailable native search is recorded N/A with the supported alternative |
| EX01 skills/plugins | Discover and actually use a trusted skill, import a local skill, template and named agent; package/directory plugin lazy activation, unload/reload, changed-trust refusal; no protected registry replacement or persistent caller-state change | ONGOING fixture preparation; earlier installed local activation/import O |
| EX02 MCP | Owned stdio and loopback HTTP server: list/lazy connect, real numerical/file tool use, progress/error, cancellation, disconnect/reconnect/remove; expiry/allow/deny with synthetic auth; exact child/server cleanup and no secret in generated contexts | ONGOING storage/transport review; earlier standalone stdio/bridge O |
| EX03 named workers | Explicit agent definitions and roles, fan-out over named inputs, workflow reports/Peter/bare-R drafts, strict replay; shared-budget/depth refusal, worker cancellation/failure isolation and parent session remains usable | ONGOING notebook teams; Azure source team/fan-out LR at3d; draft fixtures O |
| ST01 layout/deltas | Snapshot relative paths, file sizes/hashes/permissions in isolated `.gptr` after init, instruction/context/skill/plugin/MCP discovery, calls, tools, summaries, recording and cleanup; compare to expected ownership/schema/location | ONGOING independent source audit; live operation snapshots WAITING |
| ST02 storage safety | Path traversal, secret includes, symlink targets, unsafe overwrite, private file permissions, atomic writes/recovery, concurrent writers, truncation/malformed records, sidecar trust and size limits; failure cannot corrupt originals or parent state | ONGOING independent source audit; reproducible issues need offline RED tests before fixes |
| CP01 triggers | Forced manual and automatic threshold compaction; before/after prompt token counts, compaction event/usage/status, bounded latency and visible progress; no repeated compaction loop | WAITING source/offline then live |
| CP02 continuity | Retain governing instructions, loaded-object references, recent steering, complete tool call/result pairs and unresolved approvals; continue a seeded multi-step task after compaction and independently verify final R value/input invariance | WAITING |
| CP03 failure/cancel | Compactor unavailable, malformed summary, timeout, budget exhausted and interrupt: recover or return a clear error, preserve usable session/history and owned child cleanup; count actual charges honestly | WAITING |
| CP04 persistence | Snapshot `.gptr` context/workflow/session/checkpoint deltas before/after compaction; restart/resume/rewind from each supported boundary; corruption is rejected and no secret/context content leaks | WAITING; connects ST01/ST02 and IM06 |
| CP05 teams/replay | Child-only versus parent compaction, fan-out shared-budget attribution, cancellation and recorded summary/Peter/R documents; fresh strict replay has zero new provider requests/usage with stable fingerprints | WAITING |
| CP06 frontends/resources | Representative PTY and native GUI progress/interrupt, Rscript/Rmd/Quarto/IRkernel execution; Claude/Codex native compaction scope distinguished from harness compaction, Qwen/Azure route capability stated; RSS/output growth bounded | WAITING; no universal model/client pass from one probe |

Execute source/offline safety checks first, then serial live capability cases, then their
fresh-process replay/cleanup checks. Update this table and the detailed progress ledgers after
reviewing actual evidence. Completion must distinguish unsupported provider/client features
from tests that remain waiting. All original G01–G14, A01–A08, D01–D07, IM01–IM06, UX01–UX03,
X01–X14 and Q01–Q05 acceptance clauses remain in scope alongside these added cases.
Native Unix prefix completion at `f0f3448` passed O 71 focused / 476 affected assertions,
one CI-only skip, zero failures/warnings and two-file lint clean. Immutable installation
passed in 13.89s (15 samples, 386.7 MiB peak, zero sampling errors). Actual native R readline
completed `!mtc`, `!!mtc`, a `stats::median` namespace prefix and a quoted file path; median
19.2 and file-existence TRUE matched their oracles. Exit restored the original separators
and preserved the dataset. That PTY's unprivileged profiler could not sample processes
(43 errors); its RAM result is unavailable. This is native terminal integration, not GUI
completion or active window-resize evidence.

The newer document runs preserve the earlier `390485f` Claude failure: live 9.563s passed,
fresh replay 1.081s failed because beta was absent from an empty recorded MCP R body.
The `8d13b58` repair applies to new recordings; it does not repair or overwrite that artifact.
All nine repaired CLI/Qwen cells passed fresh replay, independently checking fit/coefficient,
child exit and unchanged recorded source. Native GUI replay at `8d13b58` has not run.

Two small serial offline integrations on the unchanged `8d13b58` runtime passed after the
documentation checkpoint `7d7a39a`: optional tools/skills/plugins/stdio MCP (14 stages,
13.707s, 568.3 MiB / 15 samples) and workflow summary/drafts/template/Peter history (four fresh
children, 4.046s, 243.3 MiB / five samples). Both had zero counted warnings and sampling errors,
independent sum 7 / mean 3.5 oracles, unchanged inputs and successful owned cleanup. The
optional run made one fake request; workflow phases made seven fake requests. External model
requests were zero. Native `summary()` and fresh history replay made no request; narrative
and bare-R drafts were explicitly synthetic model output, not a guaranteed native export.

Hosted `390485f` Windows release exposed a fixture cleanup error: its mocked Unix completion
case introduced `rl_word_breaks`, which Windows R cannot later delete. The narrow test-only
correction skips native Unix positive fixtures before Windows platform mocking and retains
all 13 unsupported-mode variants without creating that option. Independent review and local
Unix validation passed 71 assertions with zero failures/countable warnings/skips and no lints;
the environment's testthat build-version advisory is retained. Actual corrected Windows CI is P.

Historical final gate `240db69` had 23,865 passing assertions and local CRAN 0/0/0;
it is not a current-artifact claim. Newer hosted results likewise apply to their own SHAs.

## Frontend and provider matrix

Each `P` cell needs a small real request and its numeric/type oracle, then strict replay where
recording applies. GUI observations must use the actual UI, not a headless renderer. Function
coverage is listed separately from executing a recorded `.R` file through an actual Rscript
child and its exit finalizer. CLI provider names must remain CLI routes.

| Requested provider/model | R PTY REPL | Terminal app | macOS R.app | RStudio GUI | VS Code R | Direct Rscript `.R` | Function/pipe in R | R Markdown | Quarto | Jupyter/IRkernel |
|---|---|---|---|---|---|---|---|---|---|---|
| Claude CLI: selected `claude-cli/claude-haiku-4-5` | P | P | P | P | P | LR `8d13b58`; F `390485f` retained | L `d1887f2` | LR `8d13b58` | LR `8d13b58` | P |
| Codex CLI: `codex/default` (retain actual CLI model metadata) | P | P | P | P | P | LR `8d13b58` | L `d1887f2` | LR `8d13b58` | LR `8d13b58` | P |
| Ollama: exactly `ollama/qwen3.8:27b` | P | P | P | P | P | LR `8d13b58` | L `d1887f2` | LR `8d13b58` | LR `8d13b58` | P |
| UCSF Versa Azure: selected Luna deployment | L `fc9f8d4` | P | P | L function `4e66376`; LR Knit `d1887f2`; L manual tool/listing `c722e6d` | L/replay same GUI process `3d92b05` | LR `390485f` | L `4e66376` in IDE | LR `390485f`; older native Knit | LR `390485f` | LR `fc9f8d4`, actual GUI |
| Native Jev: `typesafe/jev-latest` / `jev` alias | P typed | P typed | P typed | P typed | L/replay same GUI process `3d92b05` | P typed child | P typed | LR `390485f` | LR `390485f` | P typed |

The Jev recorded `.R` case at `390485f` also passed LR through `gptr_source()`; it does not
establish an actual direct-Rscript child/exit-finalizer cell. Azure's three cells recorded one
block each and emitted two fresh request/usage events live, zero on replay. Jev's three cells
recorded three blocks each and native usage rows 3 live / 0 replay, with no agent request/usage
events in either phase. All six cells had zero warning classes. The repaired nine-cell batch
also had zero warnings: each CLI live phase emitted one request/usage event; Qwen emitted two
in direct Rscript and three in each rendered format. Their 18 phases are document evidence,
not a full frontend/provider pass. Exact durations and retained runs are in the live ledger.

R PTY evidence does not establish a native terminal-app window or R.app/VS Code behavior.
VS Code 1.140.0 with R extension 3.0.1/syntax extension 0.1.4 and R.app R 4.5.0/GUI 1.81
were inventoried read-only. The official bundled `sess` 3.0.1 bridge was subsequently installed
in the private development library and attached in the disposable VS Code workspace, without
sourcing user startup files. Active output-width rendering now has the observed scope above;
native editor/prefix completion and its error/interrupt restoration remain P. `radian` was not
found on the checked PATH/usual paths, which is not an exhaustive absence claim.
Retain exact local setup in ignored `LOCAL_SETUP.md`: use the new `r.executablePath`,
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
profiler. `optional-smoke.R` and `workflow-summary.R` now have the scoped offline evidence
above. `system-one-emulation.R` now has actual Azure live/cache and fresh-process replay
evidence at `3d92b05`; Qwen and unsupported CLI negative cases remain P. Fixtures alone are
execution aids, not evidence. Root coordinates bounded compute lanes and GPU requests.
Headless notebook coverage supplements actual GUI observations.

## All guides and tables

Review every section, recipe, example output and table row against the installed APIs.
The current static inventory is 14 guides, 11 tables and 96 table body rows: configuration
5/45; execution model 2/14; interactive console 1/25; language models 1/5;
script as history 1/4; token efficiency 1/3. Recount after source edits. Table rows grouping
settings/options require every listed setting/option, including aliases, not one sample per
group. The documentation ledger reports 32 core settings, 90 runtime options and 63 exports;
cross-check the current manifest/reference before retaining those counts.

Documentation checkpoint `82a7db3` regenerated README/help and all 14 in-memory guides with
zero documentation/file errors; guide knits took 10.963s, the private-overlay run 47.539s
(574.8 MiB peak family RSS / 48 samples / zero sampling errors). Source fingerprints and the
maintainer's DESCRIPTION roxygen preference `8.1.0` were preserved; NAMESPACE stayed identical.
The subsequent final prose refresh rendered all 14 guides in separate, fresh offline R
processes, using the installed `8d13b58` runtime without another installation. Guide knits
took 11.029s; total validation 12.720s, 250.8 MiB peak family RSS / 13 samples / zero sampling
errors and zero documentation/file problems. Only affected generated files were copied back;
unchanged guide snapshots were retained to avoid unrelated session-ID churn.
The updated static site was rebuilt and inspected locally; it is not publicly deployed.
The README, function/configuration help and [asset README](../man/figures/README.md) now share
the in-memory story: work on already
loaded caller objects across turns, bounded model context, preserve originals, and distinguish
opt-in cache/checkpoint serialization from ordinary computation. Repeat generation/checks
after any later documentation change.
`eval = FALSE` live/external recipes are `P`
unless a matching run below establishes them; successful fake chunks do not establish a live
provider, permission UI, MCP server or external engine.

| ID / guide | Mandatory coverage, including its tables | Current evidence and remaining check |
|---|---|---|
| G01 [Getting started](../vignettes/getting-started.Rmd.orig) | First call; result/session; same-session pipe; stopping; console; real connection; in-memory reuse | H fake examples; L selected function/pipes. P fresh quickstart through each frontend and preserved caller input. |
| G02 [Why Peter](../vignettes/why-peter.Rmd.orig) | Both namesakes; primary links; gptr/Peter naming; avoid claiming Wason coined System 1/2 | O rebuilt article browser wording check and reopened primary source content; H earlier source review. Full automated external URL scan stays separate. |
| G03 [Language models](../vignettes/language-models.Rmd.orig) | Provider table (all five rows); APIs; Azure/Bedrock; subscription CLIs; local Ollama; session lifecycle; functions/scripts; loaded-object reuse | L five requested routes in selected cells. P remaining matrix; other access inventory is not inference. |
| G04 [System 1](../vignettes/system-one.Rmd.orig) | Logical/probability; structured batch shape/names; uncertainty in filters/functions/loops; choices/levels/fractional scores; provenance/cache; routing/judging System 2; native/local/emulated engines | LR Jev recorded R/Rmd/Quarto logical/choice/score `390485f`. P default-setting/service routing, prepared emulation, native local classifier, calibration/uncertainty boundary and other frontends. |
| G05 [Interactive console](../vignettes/interactive-console.Rmd.orig) | All command-table rows/aliases and dynamic skill commands; prompt/@file/@object; `!`/`!!`; fences/triple quotes/continuations; approvals; interrupt/continue/steer/follow-up/abort/background | L Versa terminal subset, IDE function waiting and c722 native manual-tool timing/listing; L native Unix inline completion `f0f3448`. O abort/listing/width/completion regressions; LGUI-O active R.app streamed resize `390485f`. P full commands, installed abort witnesses, IDE/VS Code resize and remaining controls. |
| G06 [Configuration](../vignettes/configuration.Rmd.orig) | Scope table; all model/execution, context/history, extension/interaction tables; all option groups; precedence/unset/nested overrides; trust/egress; credential loading; matching configuration help for loaded objects and storage opt-ins | O guide/help regeneration `82a7db3`; H config/security suites. P isolated user/project/process defaults and every current table row, including inactive registered settings. |
| G07 [Script as history](../vignettes/script-as-history.Rmd.orig) | Scripts/functions/pipes; binding/consent/opt-out; blocks/hash/cache; all four replay modes; R/Rmd/qmd/ipynb; custom-environment limit; notebook display/sync; workflow summaries and executable drafts | LR direct Rscript/Rmd/Quarto for four conversational providers, Jev recorded R/Rmd/Quarto, and older Versa notebook. F earlier CLI empty body preserved; O recording fix and 8d offline summary/draft/Peter-history fresh replay. P stale/user-edited/undone records, missing cache, latest notebooks, remaining GUI cells and real-model summary quality. |
| G08 [Teams/background](../vignettes/teams-and-background.Rmd.orig) | Named roles; element fan-out; independent parallel calls; deferred SDK; steer/step/wait/cancel; background; checkpoints/usage/history | H fake recipes; L terminal responsive background with pumped completion. P all real child backends, fan-out/team formats and cancellation/replay; idle-only completion unverified. |
| G09 [Tools/artifacts](../vignettes/tools-and-artifacts.Rmd.orig) | Objects/files/output; shell/scripts; background programs; Python/SQL/other engines; artifact versioning, launch, reopen, stop | O installed 8d files, shell/nonzero error, background wait, pandas mean, DuckDB mean and bash engine with owned cleanup. H recipes/suites. P real-provider tools, app UI/versioning, failure cleanup and permission prompts. |
| G10 [Skills/plugins](../vignettes/skills-and-plugins.Rmd.orig) | Discovery/use; skill files; templates/instructions; agent definitions; packaged lazy factories; trust and precedence | O installed 8d skill read, packaged factory checks, actual lazy directory-plugin activation, file-template discovery and scripted-stdin quoted expansion. P live-model skill use, native GUI command UX, package installation/unload and changed-trust rejection. |
| G11 [MCP](../vignettes/mcp.Rmd.orig) | List/lazy connect; register; R tool members; HTTP auth; serve R; tools-only API; imported config/trust | L CLI-served R numerical returns; O installed 8d standalone local stdio list/lazy connect/tools/progress/error/reconnect/remove and isolated bridge cases. P independent HTTP/auth expiry/allow-deny and realistic UI discovery. |
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
| D01 native Jev explicit | Logical, choice and fractional score; names/shapes; probability/risk/provenance; fresh recording/replay | LR recorded R/Rmd/Quarto `390485f`; P actual direct child/other frontends/uncertainty cases |
| D02 system-wide native default | Isolated user/process/options precedence, remove override, restart; decision service actually uses the role default; compare explicit typed calls and ensure their requested native reference is not silently replaced | P live; H offline semantics, current source inspected |
| D03 no-key/local fallback | No new discovery/network; evidenced local decision model selected; absent/unsuitable model gives an honest actionable error | P installed/live witness; offline cases historical |
| D04 native Ollama Clef/Clef Flash | Actual installed classifier and suitable server; local-only preflight; no cloud fallback; types/provenance/cache/replay | P, conditional on inventory/headroom; Qwen chat pass is not this pass |
| D05 emulated chat decision | Explicit `system1 = "emulate:<provider>/<model>"`; structured response; `calibrated = FALSE`, emulated engine; no accidental native claim; uncertainty/cancel/budget/replay | LR Azure `3d92b05`: logical/choice/score, provenance, unchanged settings and same/fresh-process strict cache replay with zero replay inference. P Qwen, CLI negatives and remaining failure/budget controls. Qwen same-process replay requires a discovered digest; fresh replay needs rediscovery and is not claimed by this fixture. |
| D06 CLI/emulation boundaries | CLI catalog metadata currently advertises `structured_output = FALSE`; verify explicit unsupported failure without inference before any new capability-based scheduling | Source-unsupported inference for current Claude/Codex CLI routes; P prepared negative/no-call checks. No native probability or CLI emulation pass. |
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
while an explicit width remains fixed. Actual R.app streamed resize is LGUI-O at `390485f`:
71 update events observed widths 79 then 383, change at 24.159s of a 32.337s run, exact final
text, idle status and unchanged empty input environment; the window was restored. This is an
offline provider GUI pass, not live inference or historical-scrollback reflow. Active RStudio
and VS Code resize remains P. The native Unix `!` separator fix is O and L at `f0f3448`
for the evidenced PTY completion/ordinary-exit restoration subset; it does not cover GUI APIs.
Current input uses R's `readline()`; that fact alone does not prove native R completion works
behind the Peter `!`/`!!` prefix in each client.
Editor completion, interactive readline input and rendered document output are different
surfaces. Ordinary R function/script syntax does not gain Peter-chat prefixes.

| Surface | Available/observed behavior | New live UX checks |
|---|---|---|
| R PTY | L streamed output/controls `fc9f8d4`; earlier F bare-bang completion retained; O/L scoped fix `f0f3448` completed `!mtc`, `!!mtc`, namespace and quoted path, restoring separators on exit | P error/interrupt completion restoration and outside-evaluator width changes. No native window-management claim |
| Native Terminal app | Actual computer-use control unavailable under access policy | P resize its actual window during output; native readline completion/input, font/scale and spinner behavior |
| macOS R.app/R Console | LGUI-O actual streamed resize `390485f`, widths 79→383 and exact text/input/restoration; R 4.5.0 / GUI 1.81 | P live inference, completion, multiline input, stop behavior and other wrapping/scale cases. Unix TTY fix does not cover this GUI; no memory peak measured for this streamed probe. |
| RStudio | L Source/function, Knit, thinking indicator and c722 manual-tool timing/listing. Native R prompt completed `mtc`/`!mtc`; F Peter-prompt completion for bare/`!` input | P client-owned editor/readline completion integration; active resize/scale/wrapping. AX maximize/restore is not resize proof; partial-stream Esc attempts completed too early (not reached) |
| VS Code R extension / native R / alternative console | Local versions inventoried; visible session unattached and `sess` prerequisite missing in checked libraries; radian availability unproven | P isolated attached-runtime fixture, native completion/prefix handling, active resize, controls and restoration; keep editor/LSP/terminal distinct |
| Jupyter/IRkernel | LR actual GUI safe Markdown, stdout progress and one pending code display | P cell/editor completion versus input prompts, active browser/window/scale changes during output, tables/fences/tool/status wrapping and kernel interrupt cleanup |
| Rmd / Quarto editor and rendered report | LR selected rendering; editor integration P | P editor completion and resize independently; inspect rendered code/tables after render. A report is not a Peter readline console. |
| R functions / direct Rscript | L selected function/pipe; LR direct exit-finalizer for Versa `390485f` and Claude/Codex/Qwen `8d13b58`; Jev `.R` source is separate | P native editor completion independently, deferred lifecycle and remaining failures/wrapping. Autocomplete in an unattended process is N/A. |

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
  LGUI-O VS Code `3d92b05` observed widths 73/92/37 during streaming and two R tools, with
  readable prose/fences/table/results and clean exit; all eight cleanup witnesses true.
  This uses an offline delayed provider. Other native clients, scale controls and live
  provider progress/interrupt cases retain their separate pending clauses.
- UX02: establish normal native R completion first, then test loaded object names, functions,
  `pkg::` namespaces, quoted file paths in a disposable directory and multiline expressions
  behind both `!` and `!!`. Observe actual completion suggestions and inserted text, not only
  whether the final expression evaluates. Check prompt/slash command completion separately.
- UX03: repeat native completion after exit, interrupt and error; restore any introduced
  completion handlers, input state, width/options, editor preferences and window/scale changes.
  No persistent interfering R setting is acceptable. Missing prefix-aware completion is a
  recorded product/client integration gap. O Unix separator restoration covers ordinary exit,
  setup cancellation, errors, interrupts and nesting; L installed ordinary exit restoration
  at `f0f3448`. Actual error/interrupt/nested UI restoration remains P.

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
| X02 recording/workflow exports | Explicit binding consents; persistent off prevents automatic recording; per-call logical FALSE wins even when bound; TRUE grants no new consent. Exactly 1 regression / 3 typed / 2 team blocks; post-exit hashes. Generated narrative/script drafts must be reviewed/run, never labeled an automatic verified export. | O guards, CLI trace repair and 8d zero-call summary/reviewed synthetic draft/native Peter history with one fresh nonempty block and fresh-child zero-call replay. LR existing live document cells. F old CLI block retained. P other modes/edited records/team blocks and real model summaries. |
| X03 strict replay | New key-free process/kernel, original provider metadata, zero before-request events, zero fresh usage events and zero new native usage-log rows; unchanged source/cell/gptr fingerprint, correct R results. Team child numeric values require explicit exports; absent exports test cached reports/metadata, not persisted numerics. | LR six Versa/Jev cells `390485f` and nine Claude/Codex/Qwen cells `8d13b58`; older notebook LR `fc9f8d4`. P latest notebooks, remaining GUI/provider cells and teams. |
| X04 interactive controls | Genuine in-flight request and R-tool steer; follow-up; continue; partial-stream abort then recovery; two idle interrupts/EOF/exit; IDE stop key/fallback; background responsiveness and explicit pumped completion | L Versa terminal subset. RStudio partial-stream interruption not reached; P installed abort repair and other provider/RStudio/Jupyter control cases |
| X05 progress/display | Visible early thinking feedback, delayed first byte/cold model/tool wait, no silent hang, spinner cleanup after pause/continue/steer/abort/error; separate safe final abort tail; quiet/v0 and knitr gates; ordinary IRkernel stdout progress with true errors separate; safe Markdown and one pending code display | L fc9 terminal/Jupyter; O abort/listings/width refresh; L c722 RStudio listing/timing; LGUI-O R.app streaming resize `390485f`. P installed abort, active IDE/VS Code resize and remaining surfaces. No notebook cursor-animation promise. |
| X06 commands/settings | Each G05 row/alias/dynamic command; full resume IDs; bounded readable skills/MCP listings with full invisible values. Every G06 setting/option row, precedence/source/unset/type errors, inactive setting limits, no user-state leaks | L terminal subset and c722 RStudio `/skills`; O bounded listings. P full IDs/MCP installed UI, exhaustive tables and native completion/slash boundaries |
| X07 teams/fan-out | At most two fixture children; names/status/usage; independent mean/median values; worker/coroutine/CLI attribution; queued/in-flight steer, cancellation, budget/depth, nested calls, recording and replay by format | P live; H offline acceptance. Source ownership must not infer preserved child values without exports. |
| X08 skills/plugins/MCP | Real skill/template selection; agent definitions; trusted packaged factory lazy loading; tools-only MCP and server lifetime; transport/auth/reconnect; filtered discovery and trust renewal; no protected-policy replacement | O installed 8d plugin activation/template expansion/skill read/local stdio MCP lifecycle and numeric oracles. H/O bridge suites. P real-provider/GUI and auth/trust/agent-file cases |
| X09 tools/apps | R and bounded shell; optional Python/SQL engines; permission previews/denials; read/write/edit; output/plot truncation; artifact create/version/reopen/stop; Shiny dependency and browser UI; exact owned child cleanup | O installed 8d tiny Python/SQL/bash/files/shell/background and exact owned cleanup. P representative live/UI/apps/permissions; H broader offline suites |
| X10 security/restoration | No credentials in prompt/events/logs/doc/cache/display; synthetic split-secret/bidi/markup tests; context/egress/local-only/trust restrictions; permission allow/ask/deny and guarded actions; original input invariant; cwd/options/env/libs/seed/listeners/binding restored; no orphaned owned processes | O synthetic guards; L selected cleanup/UI; P new installed/failure-path witnesses. In-process R is not a security sandbox. |
| X11 usage/budget/cache | Known vs estimated vs unknown tokens/cost; abort once/request; preserve known partial usage; no implied zero charge; pricing tier and lower-bound budget behavior; cache-hit no request; compaction/checkpoint/rewind partial restoration | O abort accounting; H suites/ratchet; P live unknown/limit/cache/compaction cases |
| X12 performance/resources | Installed SHA, first visible feedback, first normalized text, request/tool/completion intervals; approval dwell excluded from R execution duration; CLI telemetry gaps labeled. Sample owned process-family peak RSS and server/GPU allocation separately; deadline/cancellation cleanup and cold/warm comparisons | L documented install/document profiles and c722 approval-dwell exclusion; O timing. Latest live family RSS 249.4–876.4 MiB excludes the model server and may double-count shared pages/miss children. Qwen Rscript 70.008s versus rendered 20.685/22.963s under rising host load is not a causal model-performance diagnosis. Remaining comparisons P. |
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
| Q01 documentation | All 14 guide precomputes; README, function/configuration help and asset README in-memory wording; man aliases/examples, every options/command table row, source/output consistency and no live chunks; private-overlay generation preserves the maintainer's DESCRIPTION preference | O `82a7db3` help generation and final README/all14 fresh-process guide refresh, zero documentation/file problems; NAMESPACE unchanged, DESCRIPTION `8.1.0` preserved. H 58 example pages/71 assertions. Static-site refresh did not rerun reference examples or install. P current full artifact checks. |
| Q02 site/branding | Homepage/quickstart/Why Peter prominent; all guide/reference links; canonical logo files unchanged; light/dark/auto; native menu/theme persistence; code/table overflow keyboard focus; representative 320–1920px layouts and doubled text | O refreshed 90-page site: all14 guides/63 exports, zero broken local links, all8 image assets hash-identical. Browser18 cases: light five pages and dark homepage at320/768/1440, no page overflow, white light background, matching logos; theme/viewport restored. H prior60 cases and doubled-text check. P actual browser zoom and expanded current-site accessibility. |
| Q03 CRAN periodic | Focused isolated tests/lint then docs/files; examples/precompute when changed; current dependency metadata including optional `Enhances: repr`, absent-optional load/display, pure R/fixed Imports, source/archive exclusions and credential-free offline tests | O normal `3d92b05` archive exclusions/14 guides, local R4.5 `--as-cran` 0 errors/warnings/notes, docs/files/full lint/fresh examples/all-14 precompute. P remaining optional-dependency and final platform clauses. |
| Q04 resource/size/timing | Record install/example/test/vignette timings, slowest pages, actual tarball bytes/hash, installed `du -k` and largest directories; watch source near 10 MB and docs/data near 5 MB; check at most two cores | O normal `3d92b05`: 2,216,695-byte archive, installed 6,592 KiB, doc content 555,401 bytes; build19.955/install13.430/check437.603s with two workers and BLAS1; checker-family peak2,002.1MiB/472samples/0errors. Installed-size INFO retained. Large-object/live performance remains separate. |
| Q05 platform/current artifact | Existing hosted matrix with exact SHA; current R-release/R-devel exact-tarball `--as-cran`, Windows and reverse dependencies; force-killed child temp cleanup on Windows; manual/incoming/URL checks | O local `3d92b05` archive/manual/incoming. Hosted `68017d0` Windows release/oldrel completion/temp checks settled, but sole IC-33 failure persisted; corrected `3d92b05` matrix pending. P build-once current-release archive with identical-byte consumers on release/devel Windows/Linux/macOS and local adoption; reverse dependencies pending. Checkout rebuilds do not prove identical bytes. |

Reuse existing isolated tools sequentially: `dev/ci/isolated-check.R test <filter>` / `lint`,
`dev/release/check-docs.R`, `check-files.R all`, `check-examples.R` and
`precompute.R --check`. Always use `Rscript --vanilla`; no live models/keys during offline
checks. Do not broaden passed tests without new failures or concerns. Final build/check and
submission remain coordinator/maintainer actions; consult current
[CRAN policy](https://cran.r-project.org/web/packages/policies.html) and the CRAN readiness ledger.

## Next work and unscheduled coverage

1. After resource recovery, verify repaired abort tail/unknown usage, full listing IDs and
   execution-only durations in the actual terminal without weakening redaction. Native Unix
   prefix completion/ordinary exit at `f0f3448` and offline R.app streamed resize at `390485f`
   are verified subsets; IDE/VS Code completion/active resize and other client integration stay P.
2. Extend the passed direct-Rscript/Rmd/Quarto cells to deferred cases and remaining GUI,
   notebook and provider/frontend cells serially; pair each recordable pass with strict replay
   and fresh-request witnesses. Do not repeat the passed matrix without a new concern/change.
3. Run bounded teams/fan-out and in-flight steering per applicable conversational provider,
   then representative team documents/GUI controls; keep nonexported replay-value expectations
   honest. Complete system-wide Jev defaults and capability-gated emulation.
4. Complete every guide/table acceptance checklist, skills/plugins/MCP/tools/artifacts and
   modest in-memory multi-iteration profiling and UX01–UX03 across native surfaces; record
   all omissions as P and identify proposed integration gaps explicitly.
5. Run the mandatory full cross-plan checks after this update and retain their outcome in
   the documentation ledger. Periodic full CRAN/artifact gates remain resource-deferred; the
   fresh static site and tiny offline optional/workflow lanes are validated. Emulation stays
   deferred. Schedule the actual 4 GiB object only with new
   headroom evidence. Current artifact/release gates remain separate; testing is not complete.

At 15:32 PDT, CPU idle was 0%, load 152.44/74.37/52.51, memory 127 GiB used with 296 MiB
unused, swap 42,098.5 MiB used and free disk 49 GiB. No owned gptr live jobs remained active;
unrelated user processes were retained. Hold new inference, heavy builds, full checks,
optional/emulated lanes and large allocations until the coordinator observes recovered
headroom. At 16:02 PDT the later snapshot had CPU idle 0.32%, load 28.40/31.76/41.92,
physical memory 125 GiB used, swap 41,690.5 MiB used and free disk 32 GiB; thermal status
was unavailable. Memory-pressure's 67% system-wide-free metric is distinct from physical
unused memory. Bounded serial offline documentation, tiny integrations and mandatory
consolidation checks are allowed separately; they do not clear the gate for larger workloads.

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
74-warning baseline is stale. The ledger itself is not indexed by those P01–P25 scripts.
The coordinator records each subsequent full rerun's result in the linked documentation
progress ledger; do not infer a current gate from the historical counts alone.

