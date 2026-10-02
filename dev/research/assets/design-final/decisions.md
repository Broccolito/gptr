

## Final decisions (design phase, 2026-09-29)

Resolved by the lead architect from proposals P-A, P-B and P-C, the three judge verdicts (requirements
`J-req`, CRAN/security `J-cran`, implementation `J-impl`) and the research. The architecture is
`03-architecture.md`; the plans are `05-plan-decomposition.md`. Two of three judges ranked P-A first, so its
lean core is the skeleton; P-C's user-facing design and P-B's plugin-enforcement mechanisms are grafted on.
Where a decision departs from all judges, the evidence is named. Section references (§) are to
`03-architecture.md`.

### Decisions D-01..D-28

**D-01 Provider layer.** Settled by S-10: gptr's own layer on curl multi handles only; no httr2 anywhere, no R
LLM package in Imports or Suggests. httr2 blocks during the header wait and batches output (10a E1/E2), its
parallel path retries 429/503 without bound (04 §2.16), and dropping it removes 7 packages from the closure.
All proposals and judges agree. (§6.1, §9)

**D-02 Object system.** S3 classes: environments for mutable objects (session shell with a hidden data
environment, registry, API object, ctx, reactor, runs, jobs), classed lists and base-typed vectors for values.
No R6 or S7. G1 measured about 2x cheaper method calls and 13-16x cheaper creation than R6 (ratios, per its
fact-check); G3 measured 5.5 KB vs 21 KB serialised sessions; System 1 values must be base-typed for `if()`
(04). Unanimous. (§5)

**D-03 Model-visible tools.** Direct tools `r`, `read`, `edit`, `write`, plus `ask` only when a human is
present (trimmed schema, 145 tokens). `grep`, `find`, `ls` and every other capability are `gptr$` namespace
members; the `extended` preset promotes grep/find/ls per model. No shell tool, not even opt-in (S-4; G5 §8); no
todo tool (20 §4); `edit` accepts `*** Begin Patch` envelopes and `apply_patch` is v1.x. Measured: 675 tokens
for the four schemas vs 1,199 for seven (G4 §2.8); about 36 vs 328 tokens per tool as an R signature
(G1 §2.5). (§7.1)

**D-04 Evaluation environment.** `envir = parent.frame()` with an explicit override and the magrittr-mask fix
(12 §2.B4); never name `.GlobalEnv`. Inline sub-agents and forks evaluate in overlays
`new.env(parent = envir)`. No binding locks anywhere: `lockBinding()`/`unlockBinding()` makes the next in-place
edit copy (judge checks, PB-E1, P-A experiment), which was P-C's fatal flaw. A function-frame home is held only
during a run, in an environment binding reset at settlement (G3; rule R2). (§6.4)

**D-05 Return value and pipe semantics.** `gptr()` returns the session environment for every System 2 shape;
teams, fan-outs, children and replayed sessions are session kinds (P-C; P-B's `gptr_group` broke S-8).
Piping into an idle session starts a follow-up turn on the same object and file; piping into a running one
enqueues a steer and returns at once; it never forks. One queue per session is fed by the pipe, the pause
menu, `gptr_steer()` and `ctx$send()`. `gptr_fork(s, at, envir = "overlay")` is the only branch, recorded as
`fork=` in the block header. `$value` follows G3's policy: large bound objects by name and address, small ones
copied, anonymous values boxed (judge copy check: holding the value copies, holding the name does not);
`$<-` is refused and replay reads `value=` from the block header. `background = TRUE` ships as an
experimental, opt-in feature (own plan) because S-8 makes console pipe-steering of a running session a core
idea and G3 verified it end to end in terminal R; J-cran and J-impl preferred deferral, which is why it is
isolated and excluded from examples and CRAN tests. System 1 accepts a piped session through `as_state()`.
(§4.1, §5.1, §6.2)

**D-06 System 1 API.** `gptr(q, x, model = jev, choices =, levels =, threshold = 0.5, min_confidence =,
uncertain =)` returns `gptr_decision` (logical), `gptr_choice` (classed character; a factor only on request)
or `gptr_score` (double) with probabilities as attributes, vectorised on the reactor (at most 8 active, 3
bounded rounds). A factor is truthy in `if()` and `switch()` uses its integer code (04 §2.15). Abstention is
off by default; `min_confidence` + `uncertain` (NA, TRUE/FALSE, "stop", or a function that escalates) is the
INFRA-18 `na_below`/`stop_below` policy. Logical-looking labels are rejected (04 verifier). Emulation is
opt-in only, never silent (J-cran). No `decide()`/`classify()` exports (S-1). (§4.1.5, §5.6)

**D-07 Non-standard evaluation.** Base-R capture under G3's copy-safety rules, not rlang quosures. All
judges recommended `rlang::enquo()` (12 §2.D2), but G3 showed that garbage quosures keep a forwarding
wrapper's frame alive so the caller's object copies on its next edit, while base capture that forces promises
in leaf functions is copy-safe and resolves forwarded dots correctly (G3 t2b, t5; verified by its fact-check);
the architect's re-run confirmed `enquos` COPY vs `...elt` leaf in place (`final/capture_check.R`).
Resolution rule: a known identifier (alias, registered model/provider/router, mode, skill, plugin, agent) wins
over a same-named variable (as `library()` does; 10 Q4), with `!!x` and `I(x)` escapes and a one-time notice;
other bound symbols take their character value or spec object, other classes error; unknown unbound symbols
are literal names; calls are evaluated in an alias mask. (§4.1.3, §6.4 R3)

**D-08 Document harness.** Report 14's block grammar below top-level calls, with header keys `model`, `date`,
`prompt`, `sha`, `call`, `tokens`, `cost`, `session`, `turn`, `value`, `fork`, `plan`, `status`; replay
modes `auto`/`replay`/`live`/`record`; `gptr()` never executes a recorded block; under base `source()`/Rscript
`live` downgrades to replay with a warning; replay forced under R CMD check. Nested calls in loops get no
block: they run live on re-source (REQ-24 allows non-determinism) and fail with "not recorded" under
`GPTR_REPLAY=replay`. Cassettes are a v1.x plugin with J-cran's HMAC and trust rules and J-impl's content keys,
because hidden recorded code was P-C's fatal flaw. Writes only to designated or confirmed documents. (§6.9.3)

**D-09 Session persistence.** Pi-v3-shaped JSONL tree, strictly append-only (compaction, rewind and checkpoints
are appended entries), one kept-open connection, appends inside `suspendInterrupts()`, torn-line tolerant,
redacted at ingress, in `.gptr/sessions/` (gitignored) or `tempdir()`; plus the runnable document. Sessions
hold data only; split-brain rules for detached copies (G3). Pi-readability is best effort, not a contract
(J-cran). (§6.9.2)

**D-10 Workspace and global state.** `.gptr/` only through `gptr_init(path)` (no default path: interactive
confirmation, error otherwise) or an interactive yes; creating it is consent to write, not trust. Without a
workspace, sessions, artifacts, caches and checkpoints live in `tempdir()` and the System 1 cache in memory.
User state only under `tools::R_user_dir("gptr", ...)`, small and pruned; the `.Rbuildignore` line is offered,
never written silently (13 §2.3-2.4; J-cran). (§6.9.1, §6.10)

**D-11 Permission modes.** `plan`, `manual` (default), `edits`, `auto`; risk levels 0-4 from an advisory
classifier (R, shell, SQL, Python; tables as data) documented as not a security boundary; deny > ask > modify >
allow; a throwing policy denies; project settings only tighten; level 4 and the secret guard ask even in auto.
A non-interactive ask stops the run with status `blocked` and `gptr_error_permission` naming how to allow it
(NS-12; P-A); `gptr.noninteractive_ask = "deny"` opts into denial. Plan mode runs level-1 R in a scratch
environment and hands a pending plan to the next call once (P-C). (§6.8)

**D-12 Sub-agent backends.** `backend = "auto"` everywhere: inline (overlay, zero-copy reads, no locks, own RNG
stream), except `cli` for CLI-only models; `worker` through callr with `user_profile = FALSE`, an empty
`R_ENVIRON_USER`/`R_PROFILE_USER` (callr otherwise re-injects `~/.Renviron` keys, G6 fact-check) and
NA-unset secrets; `cli` for claude/codex. Limits: 8 tasks, 8 inline / 4 CLI / `min(4, cores - 1)` workers, 2
when `_R_CHECK_PACKAGE_NAME_` is set (13 C-40); depth 1 (configurable to 2). `fork` and mirai/mori are v1.x.
Five inline agents took 5.2 s vs 14.0 s sequentially (15 §2.3). (§6.13)

**D-13 Concurrency engine.** One gptr-owned process reactor: curl multi with `pipewait = 0L`,
`processx::poll()` over curl fds and child pipes, timers, one R-tool FIFO, admission control, re-entrant for
nested calls with `allow_runs` (J-impl); `later::run_now(0)` only to service httpuv servers and experimental
background sessions. No coro or promises. (15 §4.1-4.2; §6.1)

**D-14 MCP.** Own client for both protocol eras (probe, era cached per server), stdio through the G5 process
engine (`.cmd` shims via `cmd.exe /d /c call` with metacharacter refusal) and Streamable HTTP on the reactor;
default exposure `r` as `gptr$mcp$<server>$<tool>()` with a 1,500-token signature catalog; other harnesses'
configs listed read-only and imported on request; project configs only when trusted. gptr as a server: the
in-process `sdk` transport for the claude CLI, and a loopback HTTP server (`gptr_mcp_serve()`: 127.0.0.1, random
port, 192-bit token, Origin check, permission gate, tool timeout >= 3,600 s) so Codex and external agents reach
the live session; this fixes P-A's "Codex cannot see live R" flaw. (16 §4; §6.14)

**D-15 Subscription providers.** Claude plan: the user's unmodified `claude` CLI (stream-json, control
protocol, in-process sdk MCP), experimental and opt-in with a one-time notice, neutral provider id
`claude-cli` with alias `claude_code`, minimum-version probe, billing-switch variables removed with a warning,
never touching Claude credentials; the maintainer asks Anthropic before advertising it (07 §2.18 policy
UNCERTAIN). ChatGPT plan: `codex exec --json --ignore-user-config` with the prompt on stdin and live R through
the in-session MCP server. Sign in with ChatGPT and the Codex app-server are v1.x plugins (preview never run end
to end; experimental schema drift; 08; J-cran, J-impl). Never port Pi's legacy Codex backend. (§8.3)

**D-16 Skills, extensions, plugins.** Agent Skills folders; extensions are `function(gptr)` factories;
plugins are R packages or directories with `inst/gptr/plugin.json` (and `Config/gptr/plugin` in DESCRIPTION),
discovered, never self-registered in `.onLoad` (13 C-29), activated lazily with `declarations` so the cached
prefix is stable, loaded transactionally with rollback; `.claude-plugin` bundles consumed for skills,
commands, agents and MCP. Every built-in is a `builtin_<name>()` factory using only the public API, enforced by
a codetools layering test (P-B). (G1 §4.4; §11)

**D-17 Artifacts.** Shiny apps: the model writes `<root>/artifacts/<id>/app.R` (a 124-token section and the
`shiny-bslib` skill instead of an artifact tool) and launches it with `gptr$app(id, data =)`; immutable `vNNN/`
snapshots with data through the leaf `saveRDS(ascii = FALSE)` wrapper; a supervised `callr::r_bg` child with a
secret-free environment, a random loopback port and a parent-PID watchdog; validation ladder parse, launch,
HTTP 200, optional chromote check and screenshot. `.gptr/artifacts/marker-explorer/app.R` is literal (NS-8).
Shiny costs 2.35x fewer tokens than HTML/JS (G2 (a)); HTML inside Shiny is the fallback (S-5). (§6.15)

**D-18 Model references and catalog.** `provider/id[:thinking]` plus dynamic aliases; a pruned models.dev
snapshot (about 51 KB) with dated price tiers in `inst/extdata`; refresh only on request into `R_user_dir()`
with ETag; canonical quoted ids written into documents; default model from the first available route
(Anthropic key -> `anthropic/claude-sonnet-5-5`). (09 §4; §8.4)

**D-19 Context management.** Provider usage plus G2's class-aware estimator (median error 11.4% vs 43% for
chars/4) with an EWMA provider multiplier; compaction at `min(G4 threshold, window - max(16384, max_output +
2 * r_cap), 200k)` with the cold rule, an in-conversation checkpoint and no in-place micro-compaction (+32% in
G4); `r` results capped at about 4,000 tokens (head 40% / tail 60%, spill file, `gptr$out(id)`); read line
numbers off; the tail TTL switches to 1 h after an inter-request gap over 240 s (G4's adaptive rule was 33%
worse in the fast loop per its fact-check). (§6.11, §12)

**D-20 Dependency budget.** Imports: jsonlite, curl, processx, callr, rlang, cli, yaml (7; closure 9, 10 with
callr 3.8.0's otel) plus base methods, stats, tools, utils, grDevices, graphics. openssl, httpuv and later are
Suggests (only opt-in OAuth, the MCP server and background sessions need them). Full Suggests list in §9.2;
no R LLM package anywhere. (J-cran and J-impl verified closures; §9)

**D-21 Compiled code.** None in v1 (`NeedsCompilation: no`); report 21's watch list and procedure stand. No hot
path met REQ-01's bar (21 and its verifier). (§9.3)

**D-22 Secrets.** G6 in full: vault and origin-bound handles; own `.env` parser with the `jev-key` ->
`TYPESAFE_API_KEY` alias table; one ingress redactor at every sink with sink profiles; credential store
`auth.json` (0600); child-environment profiles with empty `R_ENVIRON_USER`/`R_PROFILE_USER` and billing-switch
removal; a secret guard in the classifier; never reading other harnesses' credential files. Plus the hard rule
that untrusted text is never a cli/glue format string (J-cran reproduced code execution through
`cli::cli_text(reply)`). (§6.3, §6.5)

**D-23 Minimum R version.** `Depends: R (>= 4.2.0)`, proven by an oldrel-4 CI job (UTF-8 native on current
Windows, the `_` placeholder; 13 §2.7). Unanimous. (§9)

**D-24 Testing strategy.** Exported fake provider for every example; base-R mock SSE server (processx child,
skip on CRAN); wire fixtures replayed through the real parsers; `gptr_check()` conformance; fake CLIs; a pure-R
MCP fixture server for both eras; fresh-process tracemem suites for every entry point incl. function-frame
homes, on R-release and R-devel; the 20-turn prefix test and the offline prefix-budget test (CRAN-safe); the
codetools layering test; lint rules for the invariants; ported report-02 and Pi oracles; secrets and injection
end-to-end tests; an INFRA acceptance table; CI with check-standard, oldrel-4, no-suggests, `LC_ALL=C` and
Windows from M0; live tests only under `GPTR_LIVE_TESTS=true`. (§3.4, §6.18)

**D-25 Hook and event taxonomy.** Pi-derived canonical names with Pi's dispatch semantics plus gptr events
(`permission_request`, `decision`, `document_write`, `route`, `model_select`, `subagent_*`, `artifact_*`,
`usage`, `budget_near`, `budget_exceeded`, `cache_break`, `bridge_call`, `checkpoint`, `session_before_tree`,
`session_tree`); `tool_call`, `permission_request` and `document_write` fail closed; handlers return patches;
Claude/Codex names only through the v1.x hook importer's alias map. (G1 §3.2; §5.4)

**D-26 Console UX.** cli rendering with a chunk-invariant markdown stream and rule C1; Ctrl-C pause menu
(steer, follow-up, continue, abort, background) through the `resume` restart feeding the same queue as the
pipe, with an abort-only fallback where unverified; `!` and `!!`; slash commands incl. `/undo`, `/redo`,
`/rewind`, `/context`; UI backends `console`, `none`, `scripted`, `rstudio`; never `askYesNo()` for
permissions. (18 §4; §6.17)

**D-27 knitr / Quarto.** No `{gptr}` chunk engine in v1 (it relaxes S-2; 14 §4.6); `gptr()` in R chunks with
`knit_print` is the supported path; replay forced under R CMD check and vignette builds. J-cran and J-impl
deferred it; J-req's opt-in plugin becomes v1.x. (§6.9.3)

**D-28 Exported API naming.** 62 exports: `gptr` plus `gptr_*` (P-A's small surface plus the SDK verbs and
constructors needed for S-11), none colliding (G1 §4.7). The tools-as-functions dispatcher is the classed-closure
gateway namespace `gptr$...` (passes R CMD check, G5; one name for gateway, tools, bridges and MCP); `agent()`
exists only in the `agents =` mask; no `tools`, `mcp`, `decide` or unprefixed exports. Other kinds use
`gptr_spec(kind, ...)` and the factory API's `register_<kind>()` sugar. (§4)

### Cross-track conflicts C-1..C-33 (the known conflicts 1-18 are C-1..C-18)

**C-1 R6 vs S3 + environments.** S3 + environments (D-02). R6 arrives transitively through processx and is
not used. (G1, G3)

**C-2 HTTP transport and SSE parsing.** One curl-multi reactor for every HTTP request (providers, System 1,
MCP HTTP, OAuth, catalog refresh) with gptr's own vectorised byte-level SSE/NDJSON splitter that flushes a final
unterminated event (21 §2.6: about 17x faster than `resp_stream_sse()`, which drops that event per the 08
verifier). No httr2, so its minimum-version disagreement disappears. (D-01, D-13)

**C-3 Imports budget.** Seven Imports: jsonlite, curl, processx, callr, rlang, cli, yaml. openssl, later and
httpuv in Suggests; R6 not used; httr2 excluded. yaml in Imports because skills are core and a hand parser lost
real skills (05). (D-20)

**C-4 NSE capture and ambiguity rule.** Base-R capture under G3's rules (D-07 overturns the judges' rlang
choice with G3's verified evidence); a known identifier wins over a same-named variable with `!!`/`I()`
escapes. 09's and 05's "bound variable wins" rules are rejected because attached packages exporting `codex` or
`plan` would hijack identifiers (10 Q4).

**C-5 Evaluator and plot capture.** Hand-rolled evaluator (12 §2.A2: evaluate's sink, device and
sticky-reference defects); evaluate is not a dependency. Plots for the model at 768x512 res 120 (532 tokens,
legible per G2); larger views on request with `gptr$plot()`; artifact screenshots at 1000x700.

**C-6 Tool surface, R tool name, todo, edit result.** Four direct tools plus `ask`; the tool is `r`; no todo
tool; `apply_patch` v1.x with patch envelopes accepted by `edit`; edit results are Pi's message, with a diff of
at most 400 tokens only when the fuzzy fallback or normalisation changed the match. (D-03)

**C-7 Dispatcher and MCP naming.** The gateway namespace `gptr$...`; MCP tools under `gptr$mcp$<server>$<tool>()`;
no `tools` object (base package name) and no `mcp` export (collision with mcptools); member access has no side
effects; an evaluator shim resolves `gptr` for model code when the package is not attached. (D-28)

**C-8 Default sub-agent backend and limits.** `auto` = inline except CLI-only models; worker via callr with a
scrubbed environment; limits and depth of D-12; naming "worker". (15)

**C-9 System 1 API shape and transport.** Classed-character choices; single gateway; `min_confidence` +
`uncertain`; requests on the reactor with bounded rounds, never `req_perform_parallel`. (D-06)

**C-10 Return value.** The session object itself with `$value` by name (D-05); report 12's `gptr_result` fields
become session accessors; report 15's result lists become team and fan-out sessions.

**C-11 Claude plan bridge.** Unmodified CLI with stream-json, the control protocol and the in-process `sdk`
MCP server as the only v1 transport (no port, no token; the httpuv fallback is not used for claude, avoiding the
60 s per-request timer issue); opt-in with a notice; provider id `claude-cli`, alias `claude_code`; name use
flagged for the maintainer. (D-15; 07 and its verifier)

**C-12 ChatGPT plan route.** `codex exec --json` plus the in-session HTTP MCP server in v1; Sign in with ChatGPT
and the app-server as v1.x plugins after a live end-to-end test and a schema probe. (D-15; 08)

**C-13 MCP protocol eras.** Speak both; `server/discover` probe with 5 s timeout, fallback to `initialize`,
era cached per server; fixtures per era; the versioning page re-checked each release. (16 §4)

**C-14 Session format vs compaction.** Strictly append-only Pi-v3-shaped tree; failed attempts projected out,
never edited; compaction appended as an in-conversation checkpoint; no in-place micro-compaction (preserved
thinking and caches; G4 §2.10). (D-09, D-19)

**C-15 Workspace consent and locations.** `gptr_init(path)` with no default and interactive confirmation (NS-9's
`gptr_init()` works at the console); tempdir otherwise; artifacts under `.gptr/artifacts/` when a workspace
exists (NS-8 literal), else `tempdir()/gptr`; the System 1 cache in memory before init; trust recorded
separately with `gptr_trust()`. (D-10)

**C-16 Steering channels.** One in-memory queue per session with steer and follow-up lists; producers: the
pipe into a running session, the pause menu, `gptr_steer()`, `ctx$send()` and sibling agents; delivery after
the complete tool-result message (INFRA-12). No file inbox in core (an injection path from shared folders,
J-cran); the httpuv side channel is not a steering channel. (§6.2)

**C-17 Script-as-history under Rscript and source().** Deferred Rscript writes through
`reg.finalizer(onexit = TRUE)` with a crash sidecar; srcref validated by content, then the `source()` frame read
inside `tryCatch` with an off switch (CRAN grey zone per 14's verifier), then content and ordinal matching;
`live` only via `gptr_source()`, knitr or line-by-line IDE runs, otherwise replay with a warning. (D-08)

**C-18 Copy safety vs snapshots, guards and hashing.** A cross-layer invariant with rules R1-R10 (§6.4): no
held user objects or frames (values by name, frames only in reset environment bindings, no weak references to
frames), base-R capture, leaf introspection, no binding locks, no `mget()` snapshots (G7 pre-images released
with `rm()` and defused), `serialize(ascii = FALSE)` everywhere, sampled fingerprints plus static assignment
targets instead of full hashes; a fresh-process tracemem suite on R-release and R-devel, including tool code in
function-frame homes (G3 fact-check). Evidence: judge checks, G3, G7, `final/frame_hold_check.R`.

**C-19 System 1 decisions in the history document.** Calls inside control flow write nothing (the user's
control-flow code is the REQ-26(c) record, 14 item 14); decisions are cached per element and recorded as
`gptr.decision` entries when a session is active; a top-level System 1 statement gets a one-line `#>` summary
block (04 wanted recording; P-A). (§6.9.3)

**C-20 Project instructions placement and precedence.** User-role data in the first user message with a 1 h
cache anchor: AGENTS.md and CLAUDE.md from root to cwd, then `.gptr/vignette.Rmd` last and additive (never
executed, YAML and HTML comments stripped); precedence stated once in the frozen `<context>` section; the
system prompt is frozen at session start (07, G4 §4.2). Context files are data, not trust-gated; SYSTEM and
APPEND_SYSTEM files are. (§6.11, §7.4)

**C-21 Hook and event taxonomy.** Pi-derived names plus gptr events, fail-closed trio, patch returns (D-25);
20's Claude/Codex names only through the importer.

**C-22 Permission mode names and plan mode.** `plan`/`manual`/`edits`/`auto` (18, D-11, north star); plan mode
evaluates level-1 R in a scratch environment, denies writes, ends with a `<proposed_plan>` saved under
`plans/` and kept as the pending plan; without a UI an ask stops the run (NS-12) rather than silently denying.
(§6.8.5)

**C-23 Compaction thresholds and token estimation.** G4's threshold combined with G2's output reserve and a
200k soft cap, the cold rule, and G2's class-aware estimator (printed R at 2.13 chars per token) with an EWMA
multiplier; Pi's 16,384 reserve and chars/4 are superseded. (D-19)

**C-24 Skill catalog budget and activation.** Compact catalog (descriptions at most 160 characters, 33-50
tokens per skill) within 1,500 tokens with least-recently-used trimming and `gptr$search()` beyond it;
activation through `read` (no skill tool whose enum would change the cached tool array); `skills =` preloads
bodies as `<skill_content>`. (G2 (b), 16; §7.3)

**C-25 Bash mapping and agent-file directories.** Bash and PowerShell in foreign agent definitions map to `r`
(15, 16, G5; S-4), never to a shell tool; directories read: `.gptr/agents`, `.claude/agents`, `.codex/agents`
(markdown), `.pi/agents`, user-level equivalents and packages' `inst/gptr/agents`. (§11.1)

**C-26 Opt-in shell tool vs S-4.** No shell tool in gptr, not even opt-in; `gptr$sh()` and the other bridges
cover the need (G5 §8: 22.9x fewer tokens R-composed than a bash tool); a third-party plugin may add one only by
routing through `gptr$sh()` and the `r` pipeline. (D-03)

**C-27 Exported names vs collisions.** Only `gptr` and `gptr_*` (D-28); report 16's `mcp_*`, 17's `artifact*`,
04's `decide/classify/rate/judge` and 06's `tools` become namespace members, `gptr_*` exports or internal.

**C-28 knitr chunk engine.** Not in v1 (D-27); replay-only behaviour would be required if it is added in v1.x.

**C-29 File-tool implementation recipes.** grep: `readBin` per file, `grepRaw(fixed = TRUE)` prefilter for
literals, whole-file `(?m)` PCRE prefilter for regex, NUL sniff, early stop, never per-file `readLines` (21
§2.1), with 11's `readChar` batching for many small files; read: raw newline index up to 16 MiB, streaming
index above, cached sparse index above 20 MB (11 + 21); diff: patience anchors plus Myers capped at D = 256,
no diffobj (21 §2.3); find: Pi's `**/` prefix rule (11 verifier). (P-C C-29)

**C-30 One event loop for reactor, later and httpuv.** The reactor calls `later::run_now(0)` each iteration
when later is loaded (servicing `gptr_mcp_serve()` and OAuth callbacks, never `httpuv::service()`); background
sessions are pumped by a `later` timer (no `later_fd`, which cannot watch processx pipes on Windows); core
flows never require later. (§6.1-6.2)

**C-31 S2 cache committed vs privacy.** S2 answer text gitignored by default and redacted at ingress; the S1
cache (input hashes and answers only) committed by default. (§6.9.3)

**C-32 Default models.** First available route: Anthropic -> `anthropic/claude-sonnet-5-5` (the north-star
banner), OpenAI -> `openai/gpt-6-sol`, Gemini -> `google/gemini-3.8-flash`, else a detected CLI; aliases resolve
to full ids and CLI invocations always pass full ids (07). (§8.4)

**C-33 Retry policy constants.** Transport: retry 408/409/429/5xx/529 and network errors before the first
committed delta, `0.5 s * 2^i` with time-derived jitter (never the RNG), cap 8 s, at most 4 attempts, Retry-After
honoured up to 60 s then fail fast, spend-cap 429 never retried (10a INFRA-06, 07); agent level: 2 retries of
classified transient errors after committed deltas (02); System 1: 3 bounded rounds resubmitting failed
elements only (04 §4.7). (§6.1)
