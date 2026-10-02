from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/01-decision-register.md"
pairs = [
("""`03-architecture.md`.""" + "\n\n### Decisions D-01..D-28",
"""`03-architecture.md`. The adversarial review of 2026-09-30 amended several decisions below; the amended text is
marked "(review)" and the full record is `06-review-resolution.md` and contract §15 (IC-32..IC-73).

### Decisions D-01..D-28"""),
("""**D-08 Document harness.** Report 14's block grammar below top-level calls, with header keys `model`, `date`,
`prompt`, `sha`, `call`, `tokens`, `cost`, `session`, `turn`, `value`, `fork`, `plan`, `status`; replay
modes `auto`/`replay`/`live`/`record`; `gptr()` never executes a recorded block; under base `source()`/Rscript
`live` downgrades to replay with a warning; replay forced under R CMD check. Nested calls in loops get no
block: they run live on re-source (REQ-24 allows non-determinism) and fail with "not recorded" under
`GPTR_REPLAY=replay`.""",
"""**D-08 Document harness.** Report 14's block grammar below top-level calls, with header keys `model`, `date`,
`prompt`, `args` (review), `sha`, `call`, `tokens`, `cost`, `session`, `turn`, `value`, `fork`, `plan`, `kind`,
`children` (review), `status`; replay modes `auto`/`replay`/`live`/`record`; `gptr()` never executes a recorded
block; under base `source()`/Rscript `live` downgrades to replay with a warning; replay forced under R CMD check
outside testthat, i.e. in examples (review, IC-45). (review) Replay needs no write consent (the route matches a
located block); a piped session is advanced in place; forks are bound by block id; teams, fan-outs and
block-nested calls replay from the S2 cache; recorded code drops `gptr_return()` and inspection-member calls
(IC-45..IC-49). Nested calls in loops get no block: they run live on re-source (REQ-24 allows non-determinism)
and fail with "not recorded" under `GPTR_REPLAY=replay`."""),
("""**D-09 Session persistence.** Pi-v3-shaped JSONL tree, strictly append-only (compaction, rewind and checkpoints
are appended entries), one kept-open connection, appends inside `suspendInterrupts()`, torn-line tolerant,""",
"""**D-09 Session persistence.** Pi-v3-shaped JSONL tree, strictly append-only (compaction, rewind and checkpoints
are appended entries), open-append-close per entry or batch (review: a kept-open connection per session leaves
connections open in examples and exhausts R's 125 connections, IC-59), appends inside `suspendInterrupts()`,
torn-line recovery at resume and ps-checked pid locks (review),"""),
("""A non-interactive ask stops the run with status `blocked` and `gptr_error_permission` naming how to allow it
(NS-12; P-A); `gptr.noninteractive_ask = "deny"` opts into denial. Plan mode runs level-1 R in a scratch
environment and hands a pending plan to the next call once (P-C). (§6.8)""",
"""A non-interactive ask stops the run with status `blocked` and `gptr_error_permission` naming how to allow it
(NS-12; P-A); `gptr.noninteractive_ask = "deny"` opts into denial. Plan mode runs only calls known to be read-only
in a scratch environment (review, IC-54) and hands a pending plan to the next top-level call once (P-C; IC-56).
(review) The gate fails closed without a mode policy; the permission kernel cannot be filtered out; safety options
are snapshotted per run; gptr's own configuration exports and control-plane files are a level-4 `control`
category answered only by a human (`ask_human`); unlisted functions of non-base packages are level 1 (IC-53,
IC-54). (§6.8)"""),
("""**D-12 Sub-agent backends.** `backend = "auto"` everywhere: inline (overlay, zero-copy reads, no locks, own RNG
stream), except `cli` for CLI-only models; `worker` through callr with `user_profile = FALSE`, an empty
`R_ENVIRON_USER`/`R_PROFILE_USER` (callr otherwise re-injects `~/.Renviron` keys, G6 fact-check) and
NA-unset secrets; `cli` for claude/codex. Limits: 8 tasks, 8 inline / 4 CLI / `min(4, cores - 1)` workers, 2
when `_R_CHECK_PACKAGE_NAME_` is set (13 C-40); depth 1 (configurable to 2).""",
"""**D-12 Sub-agent backends.** `backend = "auto"` everywhere: inline (overlay, zero-copy reads, no locks, own RNG
stream), except `cli` for CLI-only models; `worker` through callr with `user_profile = FALSE`, an empty
`R_ENVIRON_USER`/`R_PROFILE_USER` (callr otherwise re-injects `~/.Renviron` keys, G6 fact-check; review: every
child profile gets them, IC-60) and NA-unset secrets, inheriting the session's registry records (review, IC-69);
`cli` for claude/codex. Limits: 8 tasks per team or fan-out started by model code (review: user fan-outs queue
every element, IC-39), 8 inline / 4 CLI / `min(4, cores - 1)` workers, every child pool 2 when
`_R_CHECK_PACKAGE_NAME_` is set (13 C-40); depth 1 (configurable to 2)."""),
("""**D-13 Concurrency engine.** One gptr-owned process reactor: curl multi with `pipewait = 0L`,
`processx::poll()` over curl fds and child pipes, timers, one R-tool FIFO, admission control, re-entrant for
nested calls with `allow_runs` (J-impl); `later::run_now(0)` only to service httpuv servers and experimental
background sessions. No coro or promises. (15 §4.1-4.2; §6.1)""",
"""**D-13 Concurrency engine.** One gptr-owned process reactor: curl multi with `pipewait = 0L` and
`followlocation = 0L` (review), `processx::poll()` over curl fds and child pipes, timers, one R-tool FIFO,
admission control, re-entrant for nested calls with `allow_runs` (J-impl), which defaults to none inside a run
(review); `later::run_now(0)` only in the outermost pump (or one waiting for a served CLI child) to service httpuv
servers and experimental background sessions (review, IC-57). No coro or promises. (15 §4.1-4.2; §6.1)"""),
("""in-process `sdk` transport for the claude CLI, and a loopback HTTP server (`gptr_mcp_serve()`: 127.0.0.1, random
port, 192-bit token, Origin check, permission gate, tool timeout >= 3,600 s) so Codex and external agents reach
the live session; this fixes P-A's "Codex cannot see live R" flaw. (16 §4; §6.14)""",
"""in-process `sdk` transport for the claude CLI, and a loopback HTTP server (`gptr_mcp_serve()`: 127.0.0.1, an
RNG-free port, one 192-bit token per client bound to its session (review, IC-58), Origin check, permission gate,
tool timeout >= 3,600 s) so Codex and external agents reach the live session; this fixes P-A's "Codex cannot see
live R" flaw. (16 §4; §6.14)"""),
("""UNCERTAIN). ChatGPT plan: `codex exec --json --ignore-user-config` with the prompt on stdin and live R through
the in-session MCP server.""",
"""UNCERTAIN). ChatGPT plan: `codex exec --json --ignore-user-config --skip-git-repo-check -m <id> -C <wd>` with the
MCP server marked approved and required, the prompt on stdin and live R through the in-session MCP server; every
mode except `auto` runs Codex's read-only sandbox (review, IC-65)."""),
("""**D-20 Dependency budget.** Imports: jsonlite, curl, processx, callr, rlang, cli, yaml (7; closure 9, 10 with
callr 3.8.0's otel) plus base methods, stats, tools, utils, grDevices, graphics.""",
"""**D-20 Dependency budget.** Imports: jsonlite, curl, processx, callr, rlang, cli, yaml, ps (8; review: ps for pid
liveness, already in the closure through processx, IC-59; closure 9, 10 with callr 3.8.0's otel) plus base
methods, stats, tools, utils, grDevices, graphics; not `parallel` (review: RNG streams are swapped without it,
IC-61)."""),
("""**D-22 Secrets.** G6 in full: vault and origin-bound handles; own `.env` parser with the `jev-key` ->
`TYPESAFE_API_KEY` alias table; one ingress redactor at every sink with sink profiles; credential store
`auth.json` (0600); child-environment profiles with empty `R_ENVIRON_USER`/`R_PROFILE_USER` and billing-switch
removal; a secret guard in the classifier; never reading other harnesses' credential files.""",
"""**D-22 Secrets.** G6 in full: vault and origin-bound handles; own `.env` parser with the `jev-key` ->
`TYPESAFE_API_KEY` alias table; one ingress redactor at every sink with sink profiles; credential store
`auth.json` (0600); child-environment profiles (complete vectors) with empty `R_ENVIRON_USER`/`R_PROFILE_USER` in
every profile and G6 §3.7's CLI removal lists (review, IC-60, IC-65); a secret guard in the classifier; never
reading other harnesses' credential files; `gptr_scrub()` and the late-registration warning restored from G6 §4.7;
child logs persisted only through the redactor; no redirects followed (review, IC-64, IC-70)."""),
("""**D-27 knitr / Quarto.** No `{gptr}` chunk engine in v1 (it relaxes S-2; 14 §4.6); `gptr()` in R chunks with
`knit_print` is the supported path; replay forced under R CMD check and vignette builds.""",
"""**D-27 knitr / Quarto.** No `{gptr}` chunk engine in v1 (it relaxes S-2; 14 §4.6); `gptr()` in R chunks with
`knit_print` is the supported path; replay forced in R CMD check's examples (review: not in its tests, and
vignettes are precomputed, IC-45)."""),
("""**D-28 Exported API naming.** 62 exports: `gptr` plus `gptr_*` (P-A's small surface plus the SDK verbs and
constructors needed for S-11), none colliding (G1 §4.7).""",
"""**D-28 Exported API naming.** 63 exports (IC-01 added `gptr_preimage()`; review: `gptr_map()` is internal because
S-1 keeps one gateway, and `gptr_scrub()` is new, IC-36, IC-70): `gptr` plus `gptr_*` (P-A's small surface plus the
SDK verbs and constructors needed for S-11), none colliding (G1 §4.7)."""),
("""**C-3 Imports budget.** Seven Imports: jsonlite, curl, processx, callr, rlang, cli, yaml. openssl, later and
httpuv in Suggests; R6 not used; httr2 excluded.""",
"""**C-3 Imports budget.** Eight Imports: jsonlite, curl, processx, callr, rlang, cli, yaml, ps (review, IC-59).
openssl, later and httpuv in Suggests; R6 not used; httr2 excluded."""),
("""cache anchor: AGENTS.md and CLAUDE.md from root to cwd, then `.gptr/vignette.Rmd` last and additive (never
executed, YAML and HTML comments stripped); precedence stated once in the frozen `<context>` section; the
system prompt is frozen at session start (07, G4 §4.2). Context files are data, not trust-gated; SYSTEM and
APPEND_SYSTEM files are. (§6.11, §7.4)""",
"""cache anchor: AGENTS.md and CLAUDE.md from root to cwd, then `.gptr/vignette.Rmd` last and additive (never
executed, YAML and HTML comments stripped); precedence stated once in the frozen `<context>` section; the
system prompt is frozen at session start (07, G4 §4.2). Context files are data; SYSTEM and APPEND_SYSTEM files
are trust-gated. (review) Their *authority* is trust-gated: in an untrusted project they render
`trusted="false"` as information, not commands, and non-interactive `auto`/`edits` runs omit them (IC-52).
(§6.11, §7.4)"""),
("""**C-30 One event loop for reactor, later and httpuv.** The reactor calls `later::run_now(0)` each iteration
when later is loaded (servicing `gptr_mcp_serve()` and OAuth callbacks, never `httpuv::service()`); background
sessions are pumped by a `later` timer (no `later_fd`, which cannot watch processx pipes on Windows); core
flows never require later.""",
"""**C-30 One event loop for reactor, later and httpuv.** The outermost reactor pump calls `later::run_now(0)`
each iteration when later is loaded (servicing `gptr_mcp_serve()` and OAuth callbacks, never `httpuv::service()`);
nested pumps do not, unless they wait for a served CLI child (review, IC-57); background sessions are pumped by a
`later` timer that is a no-op while the reactor is on the stack (no `later_fd`, which LIKELY cannot watch processx
pipes on Windows: inferred from its documentation, untested, per the 15 fact-check); core flows never require
later."""),
("""**C-31 S2 cache committed vs privacy.** S2 answer text gitignored by default and redacted at ingress; the S1
cache (input hashes and answers only) committed by default. (§6.9.3)""",
"""**C-31 S2 cache committed vs privacy.** S2 answer text gitignored by default and redacted at ingress; the S1
cache (salted input hashes, question hashes and answers only; review, IC-70) committed by default; console
transcripts gitignored by default (review). (§6.9.3)"""),
]
apply(P, pairs)
