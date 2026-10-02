# gptr 1.0 — Implementation plan decomposition

Status: final, design phase, 2026-09-29. Companion to `03-architecture.md` (the architecture), the appended
"Final decisions" section of `01-decision-register.md`, and `dev/plan/00-conventions.md` (Global
Constraints of every plan). An implementer reads the conventions, then `03-architecture.md`, then
`04-interface-contract.md` (written next), then the plan. Every code sample uses `=` and `|>` (S-9).

## How to read this document

- **25 plans, P01-P25, in six milestones.** The order follows the winning skeleton (P-A): the whole S-8 session
  contract runs offline on the fake provider (M1) before any network adapter exists, and every milestone ends
  with working, tested software and a clean `R CMD check --as-cran` on the CI matrix.
- **Ownership.** Every file in `03-architecture.md` §3 is owned by exactly one plan. A plan writes only the
  files it owns, plus generated files (`NAMESPACE` and `man/` through `devtools::document()`), plus the test
  file mirroring each R file it owns (`tests/testthat/test-<area>-<topic>.R`). Exceptions are named in the
  plan. No plan adds an Import (conventions §8): P01 writes the final Imports and Suggests once.
- **Registration without shared lists.** Built-ins are declared in their own files with
  `on_load(ext_declare_builtin("<name>", builtin_<name>))` (P01's `on_load()` registry, P02's declaration
  table); gateway routes (classifier, team, fan-out, document, console) are registry records contributed by
  their owning plans. So later plans never edit an earlier plan's file.
- **Acceptance checks** are commands with expected results. Test commands use conventions §2; "green" means
  `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with n limited to the skips the plan names. Milestone plans also run
  `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`, whose
  expected result is 0 errors, 0 warnings and at most the "New submission" NOTE, on the CI matrix of P01.
- **Research to read** lists report sections; each report's verification log overrides its body. G3 and G5
  exist as digest entries (`dev/research/00-digest.md`) plus scratch prototypes (`scratchpad/work/G3/`,
  `scratchpad/work/G5/`).
- **Copy-safety** (architecture §6.4, rules R1-R10) binds every plan that touches user objects or frames; each
  such plan owns a `test-copy-<area>.R` built on P01's `expect_no_copy()`.

## Milestones

| Milestone | Plans | Ships | Exit test (last plan of the milestone) |
|---|---|---|---|
| M0 Foundation | P01-P04 | skeleton, utilities, registry and extension API, secrets, reactor and process engine | reactor INFRA-01/05/06/21/23 on the mock server; registry conformance; redaction properties; `--as-cran` clean on macOS, Windows, Linux, oldrel-4, no-suggests, `LC_ALL=C` |
| M1 Offline S-8 kernel | P05-P08 | model layer, sessions, loop, dispatcher, store, prompt and context, `gptr()` and the SDK | NS-2/NS-3 shapes on the fake provider; pipe steering of a running session; overlay fork; resume; 20-turn byte-prefix test; gateway copy suite |
| M2 Live R agent and System 1 | P09-P13 | evaluator and workspace, tools and `gptr$`, permissions and plan mode, native adapters, System 1 | NS-2..NS-5 against the fake provider and mock servers; permission matrix; adapter conformance; evaluator copy suite |
| M3 Interactive, recorded, reversible | P14-P17 | console, documents and replay, checkpoints and rewind, skills/templates/agents/plugins | NS-1 through the scripted console; NS-7 in `.R`, Rmd, qmd, ipynb; `/undo` and rewind; NS-10 skills and plugins; NS-12 |
| M4 Interop and scale-out | P18-P21 | MCP client and server, OAuth, sub-agents, CLI providers, background sessions | NS-6 (inline + worker + fake CLI on one reactor), NS-9, NS-10 MCP; INFRA-16/19 |
| M5 Polyglot, apps, measured release | P22-P25 | bridges, artifacts, benchmark suite and end-to-end acceptance, release | NS-8, NS-11; token baselines committed; secrets and injection end-to-end; CRAN submission check |

## Dependency graph (acyclic)

```text
P01 -> P02 -> P03 -> P04
P02, P03 -> P05 ;  P04, P05 -> P06 -> P07 ;  P03, P07 -> P08
P08 -> P09 -> P10 -> P11 ;  P05, P07 -> P12 ;  P08, P12 -> P13
P08, P11 -> P14 ;  P08, P10 -> P15 ;  P11, P15 -> P16 ;  P08 -> P17
P10, P11 -> P18 ;  P11, P17 -> P19 ;  P18, P19 -> P20 ;  P06, P14 -> P21
P10, P11 -> P22 ;  P10, P11, P16 -> P23
P01..P23 -> P24 -> P25
```

| Plan | Title | Milestone | Depends on | R files |
|---|---|---|---|---|
| P01 | Foundation | M0 | - | 14 |
| P02 | Extension API and registry | M0 | P01 | 7 |
| P03 | Secrets and redaction | M0 | P01, P02 | 5 |
| P04 | Reactor and process engine | M0 | P01, P03 | 6 |
| P05 | Model layer core | M1 | P02, P03 | 4 |
| P06 | Session kernel and agent loop | M1 | P04, P05 | 7 |
| P07 | Prompt, context, caching and compaction | M1 | P06 | 5 |
| P08 | Gateway and SDK | M1 | P03, P07 | 4 |
| P09 | Evaluator and workspace | M2 | P08 | 8 |
| P10 | Tools and the `gptr$` namespace | M2 | P09 | 8 |
| P11 | Permissions, UI and plan mode | M2 | P10 | 6 |
| P12 | Native provider adapters | M2 | P05, P07 | 4 |
| P13 | System 1 | M2 | P08, P12 | 5 |
| P14 | Console and front ends | M3 | P08, P11 | 5 |
| P15 | Documents and replay | M3 | P08, P10 | 6 |
| P16 | Checkpoints and rewind | M3 | P11, P15 | 3 |
| P17 | Skills, templates, agent files, plugins | M3 | P08 | 4 |
| P18 | MCP and OAuth | M4 | P10, P11 | 5 |
| P19 | Sub-agents | M4 | P11, P17 | 3 |
| P20 | Subscription CLI providers | M4 | P18, P19 | 3 |
| P21 | Background sessions (experimental) | M4 | P06, P14 | 1 |
| P22 | Polyglot bridges | M5 | P10, P11 | 2 |
| P23 | Artifacts | M5 | P10, P11, P16 | 2 |
| P24 | Token benchmark and end-to-end acceptance | M5 | P01-P23 | 0 |
| P25 | Release | M5 | P24 | 0 |
