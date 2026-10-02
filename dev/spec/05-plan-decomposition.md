# gptr 1.0 — Implementation plan decomposition

Status: final, design phase, 2026-09-29. Companion to `03-architecture.md` (the architecture), the appended
"Final decisions" section of `01-decision-register.md`, and `dev/plan/00-conventions.md` (Global
Constraints of every plan). An implementer reads the conventions, then `03-architecture.md`, then
`04-interface-contract.md` (the interface contract: every exported and cross-plan function, record, class, file
format, option and test helper; its §13 lists the reconciliation edits made here), then the plan. The review round
of 2026-09-30 (`06-review-resolution.md`; contract §15, IC-32..IC-73) amended the scopes and acceptance checks
below; each plan's "Review amendments" bullet lists what it must add. Every code sample uses `=` and `|>` (S-9).

## How to read this document

- **25 plans, P01-P25, in six milestones.** The order follows the winning skeleton (P-A): the whole S-8 session
  contract runs offline on the fake provider (M1) before any network adapter exists, and every milestone ends
  with working, tested software and a clean `R CMD check --as-cran` on the CI matrix.
- **Ownership.** Every file in `03-architecture.md` §3 is owned by exactly one plan. A plan writes only the
  files it owns, plus generated files (`NAMESPACE` and `man/` through `devtools::document()`), plus the test
  file mirroring each R file it owns (`tests/testthat/test-<area>-<topic>.R`). Exceptions are named in the
  plan. No plan adds an Import (conventions §8): P01 writes the final Imports (now including `ps`, IC-59) and
  Suggests once; P25 adds `VignetteBuilder: knitr` with the vignettes (IC-72), the one named DESCRIPTION exception.
- **Registration without shared lists.** Built-ins are declared in their own files with
  `on_load(ext_declare_builtin("<name>", builtin_<name>))` (P01's `on_load()` registry in `R/aaa-state.R`, which
  collates first so that top-level `on_load()` calls work at install time, IC-32; P02's declaration table);
  gateway routes (classifier, team, fan-out, document, console), services (owned by their built-in, IC-34), prompt
  sections and `r_session` fragments (IC-68) are registry records contributed by their owning plans. So later
  plans never edit an earlier plan's file.
- **Acceptance checks** are commands with expected results. Test commands use conventions §2; "green" means
  `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with n limited to the skips the plan names. Milestone plans also run
  `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`, whose
  expected result is 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the
  maintainer (gptr 0.7.0 is on CRAN, so 1.0.0 is an update and gets no "New submission" NOTE; IC-72), on the CI
  matrix of P01. Tests that spawn processes call `skip_on_cran()`, and every child-process pool is capped at 2
  under check (IC-60).
- **Research to read** lists report sections; each report's verification log overrides its body. G3 and G5
  are materialised as `dev/research/G3-session-object-pipe-steering.md` and
  `dev/research/G5-polyglot-glue-helpers.md` (prototypes embedded verbatim, fact-check corrections appended).
- **Copy-safety** (architecture §6.4, rules R1-R10) binds every plan that touches user objects or frames; each
  such plan owns a `test-copy-<area>.R` built on P01's `expect_no_copy()`.

## Milestones

| Milestone | Plans | Ships | Exit test (last plan of the milestone) |
|---|---|---|---|
| M0 Foundation | P01-P04 | skeleton, utilities, registry and extension API, secrets, reactor and process engine | `R CMD INSTALL` succeeds with top-level `on_load()` calls in later-collating files (IC-32); reactor INFRA-01/05/06/21/23 on the mock server; registry conformance; redaction properties; no connection left open; `--as-cran` clean on macOS, Windows, Linux, oldrel-4, no-suggests, `LC_ALL=C` |
| M1 Offline S-8 kernel | P05-P08 | model layer, sessions, loop, dispatcher, store, prompt and context, `gptr()` and the SDK | NS-2/NS-3 shapes on the fake provider; pipe steering of a running session; overlay fork; resume; 20-turn byte-prefix test; gateway copy suite |
| M2 Live R agent and System 1 | P09-P13 | evaluator and workspace, tools and `gptr$`, permissions and plan mode, native adapters, System 1 | NS-2..NS-5 against the fake provider and mock servers; permission matrix; adapter conformance; evaluator copy suite |
| M3 Interactive, recorded, reversible | P14-P17 | console, documents and replay, checkpoints and rewind, skills/templates/agents/plugins | NS-1 through the scripted console; NS-7 in `.R`, Rmd, qmd, ipynb; `/undo` and rewind; NS-10 skills and plugins; NS-12 |
| M4 Interop and scale-out | P18-P21 | MCP client and server, OAuth, sub-agents, CLI providers, background sessions | NS-6 (inline + worker + fake CLI on one reactor; the CLI leg in P20, IC-36) and its replay with zero requests, NS-9, NS-10 MCP; INFRA-16/19 |
| M5 Polyglot, apps, measured release | P22-P25 | bridges, artifacts, benchmark suite and end-to-end acceptance, release | NS-8, NS-11; token baselines committed; secrets and injection end-to-end; CRAN submission check |

## Dependency graph (acyclic)

```text
P01 -> P02 -> P03 -> P04
P02, P03, P04 -> P05 ;  P04, P05 -> P06 -> P07 ;  P03, P07 -> P08
P08 -> P09 -> P10 -> P11 ;  P05, P07 -> P12 ;  P08, P09, P12 -> P13
P08, P11 -> P14 ;  P08, P10 -> P15 ;  P11, P15 -> P16 ;  P08, P10 -> P17
P10, P11 -> P18 ;  P11, P14, P15, P17 -> P19 ;  P12, P18, P19 -> P20 ;  P06, P14 -> P21
P10, P11 -> P22 ;  P10, P11, P14, P16 -> P23
P01..P23 -> P24 -> P25
```

| Plan | Title | Milestone | Depends on | R files |
|---|---|---|---|---|
| P01 | Foundation | M0 | - | 15 |
| P02 | Extension API and registry | M0 | P01 | 7 |
| P03 | Secrets and redaction | M0 | P01, P02 | 5 |
| P04 | Reactor and process engine | M0 | P01, P03 | 6 |
| P05 | Model layer core | M1 | P02, P03, P04 | 4 |
| P06 | Session kernel and agent loop | M1 | P04, P05 | 7 |
| P07 | Prompt, context, caching and compaction | M1 | P06 | 5 |
| P08 | Gateway and SDK | M1 | P03, P07 | 4 |
| P09 | Evaluator and workspace | M2 | P08 | 8 |
| P10 | Tools and the `gptr$` namespace | M2 | P09 | 8 |
| P11 | Permissions, UI and plan mode | M2 | P10 | 6 |
| P12 | Native provider adapters | M2 | P05, P07 | 4 |
| P13 | System 1 | M2 | P08, P09, P12 | 5 |
| P14 | Console and front ends | M3 | P08, P11 | 5 |
| P15 | Documents and replay | M3 | P08, P10 | 6 |
| P16 | Checkpoints and rewind | M3 | P11, P15 | 3 |
| P17 | Skills, templates, agent files, plugins | M3 | P08, P10 | 4 |
| P18 | MCP and OAuth | M4 | P10, P11 | 5 |
| P19 | Sub-agents | M4 | P11, P14, P15, P17 | 3 |
| P20 | Subscription CLI providers | M4 | P12, P18, P19 | 3 |
| P21 | Background sessions (experimental) | M4 | P06, P14 | 1 |
| P22 | Polyglot bridges | M5 | P10, P11 | 2 |
| P23 | Artifacts | M5 | P10, P11, P14, P16 | 2 |
| P24 | Token benchmark and end-to-end acceptance | M5 | P01-P23 | 0 |
| P25 | Release | M5 | P24 | 0 |

## Requirements coverage

Every requirement of `00-vision-brief.md` and every settled decision of `01-decision-register.md` has a plan that
delivers it (primary plan first) and an acceptance check in that plan; P24's `test-northstar.R` and golden
transcripts check the requirements end to end. INFRA-01..28 map to plans and test files in architecture §6.18.

| Requirement | Plans | Requirement | Plans |
|---|---|---|---|
| REQ-01 R only, Rcpp only when benchmark-proven | P01 (`NeedsCompilation: no`), P24 (`dev/bench/perf/`) | REQ-22 evaluate in the caller's environment | P08 (`envir` capture), P09 |
| REQ-02 CRAN compliance | P01 (CI matrix, lint), every milestone exit, P25 | REQ-23 output, warnings, errors and plots captured | P09 |
| REQ-03 cross-platform, all front ends | P01 (Windows, `LC_ALL=C` CI), P04 (process engine), P11 (UI backends), P14, P15 (knitr, Quarto, IRkernel, IDEs) | REQ-24 runnable history document | P15 |
| REQ-04 old API purged | P01, P25 (`NEWS.md`) | REQ-25 real-time and non-interactive recording | P15 |
| REQ-05 read, write | P10 | REQ-26 code, prompts and System 1 in one document; editing earlier code | P15, P10 (`edit` through the document backend), P13 (System 1 lines) |
| REQ-06 edit with diff output | P10 | REQ-27 `.gptr/` workspace and `vignette.Rmd` | P08 (`gptr_init()`, templates), P07 (instruction discovery) |
| REQ-07 grep in R | P10 | REQ-28 skills | P17 |
| REQ-08 find, list, sort | P10 | REQ-29 extensions and plugins in R | P02, P17 |
| REQ-09 R execution tool, shell through R | P09, P10 (`r`), P22 | REQ-30 MCP client, stdio and HTTP | P18 |
| REQ-10 minimal tool surface, high-performance packages | P10, P07 (presets, `r_performance`), P09 (`env-probe.R`), P17 (high-performance-r skill) | REQ-31 system prompt, templates, slash commands | P07, P17, P14 |
| REQ-11 native HTTP providers | P04, P05, P12 | REQ-32 sub-agents | P19, P08 (`nested` route) |
| REQ-12 subscription (plan) providers | P20, P18 (in-session MCP server) | REQ-33 parallel execution | P04 (reactor), P19 |
| REQ-13 Jev System 1, `.env` aliases, key hygiene | P13, P03, P24 (`test-secrets-e2e.R`) | REQ-34 cross-LLM collaboration | P19, P05 (hand-off), P20 |
| REQ-14 routing, model switches, hand-off | P05, P06 (router calls), P08, P13 (`jev-router.R`) | REQ-35 workflows as R control flow | P08, P13, P15, P19, P24 (NS-11) |
| REQ-15 provider setup from R | P08 (`gptr_config()`), P03 (`gptr_env()`), P05 (`gptr_providers()`, `gptr_models()`), P18 (`gptr_login()`) | REQ-36 ask the user | P11 |
| REQ-16 `gptr()` interactive console | P14, P08 | REQ-37 permission modes | P11, P06 (`perm_check()`) |
| REQ-17 programmatic `gptr()` | P08, P06 | REQ-38 interrupt, abort, steer | P14, P06 (queues), P21 |
| REQ-18 pipe steers one session | P06, P08, P21, P15 (pipe-chain transcripts) | REQ-39 Shiny artifacts | P23 |
| REQ-19 bare identifiers | P08 | REQ-40 own LLM infrastructure | P04, P05, P06, P12, P01 (dependency lists) |
| REQ-20 typed, vectorised System 1 | P13 | REQ-41 everything a plugin | P02, P17, every built-in plan, P24 (`test-s11-conformance.R`) |
| REQ-21 inspect the session cheaply | P09, P10 (`gptr$describe()`) | REQ-42 token efficiency, measured | P01 (estimator, truncation), P07, P10, P13, P22, P24 |
| S-1 single gateway, S-2 quoted prompts | P08 | S-7 old API gone | P01, P25 |
| S-3 R only, narrow Rcpp exception | P01, P24 | S-8 pipe steering on one session object | P06, P08, P21 |
| S-4 no bash tool | P10, P22 | S-9 `=` and `\|>` house style | P01 (`.lintr`, `test-lint-rules.R`), P15 (recorded code) |
| S-5 Shiny artifacts | P23 | S-10 own infrastructure, no R LLM package | P01 (DESCRIPTION), P04, P05, P12 |
| S-6 `.gptr/vignette.Rmd` | P08, P07 | S-11 everything a plugin; S-12 token efficiency | P02, P17, P24; P07, P24 |

---

## M0 Foundation

### P01 Foundation

- **Goal.** A buildable, lint-clean, CRAN-checkable package skeleton with every L0 utility, the JSON layer, the
  provider-neutral message and event model, the fake provider and the shared test infrastructure, on a CI
  matrix that mirrors CRAN's.
- **Scope.**
  - Rewrite `DESCRIPTION`: Package gptr, Version 0.99.0.9000, Title "Language Model Agents Inside the Live 'R'
    Session", one-paragraph Description per 13 §3 (software names single-quoted), `Authors@R` with the current
    maintainer in roles `aut`, `cre`, `cph` plus `person("Mario", "Zechner", role = c("ctb", "cph"), comment =
    "Author of 'pi' (MIT), from which tool texts and templates are derived")`, `Copyright: file inst/COPYRIGHTS`,
    `URL`, `BugReports`, `Language: en-US`, `License: MIT + file LICENSE` (year 2026 in `LICENSE`, plus
    `LICENSE.md`), `Depends: R (>= 4.2.0)`, the final Imports (jsonlite, curl, processx, callr, rlang, cli, yaml,
    ps, methods, stats, tools, utils, grDevices, graphics) and Suggests (architecture §9.2) with floors,
    `SystemRequirements`, `Config/testthat/edition: 3`, `Encoding: UTF-8`, `Roxygen: list(markdown = TRUE)`; no
    `VignetteBuilder` (P25 adds it) (IC-72).
  - Delete `.Rprofile` (it sources a missing `renv/activate.R`); keep `man/img/`; the old API files are
    already deleted (S-7).
  - `.lintr` with `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`,
    `object_name_linter(styles = "snake_case", regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$"))`
    (IC-72); `.Rbuildignore` (`^dev$`, `^\.github$`, `^\.lintr$`, `^cran-comments\.md$`, `^CRAN-SUBMISSION$`,
    `^_pkgdown\.yml$`, `^vignettes/.*\.Rmd\.orig$`, `^\.gptr$`, `^README\.Rmd$`, `^LICENSE\.md$`, `^CLAUDE\.md$`,
    `^AGENTS\.md$`, `^\.claude$`, Rproj entries); `.gitignore`; `dev/style.R` (`gptr_style()`, conventions §4).
  - `.github/workflows/R-CMD-check.yaml`: r-lib check-standard (macOS, Windows, Ubuntu release, devel,
    oldrel-1), oldrel-4, `_R_CHECK_FORCE_SUGGESTS_=false` no-suggests job, an `LC_ALL=C` job, a
    copy-safety job running `devtools::test(filter = "copy")` on R-release and R-devel, a job running
    `devtools::test()` with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true` (IC-59), and a `bench` job that installs
    rtiktoken and runs `Rscript --vanilla dev/bench/tokens/run.R --check` once P07 adds the runner (IC-73).
  - R files: `aaa-state.R` (collates first: `the`, `on_load()`, `on_unload()`, the bootstrap service table, the
    redaction hook, the internal `%||%`; IC-32, IC-34), `utils-conditions.R`, `utils-hash.R`, `utils-encoding.R`,
    `utils-options.R`, `utils-paths.R`, `utils-text.R`, `utils-tokens.R`, `json-encode.R`, `json-partial.R`,
    `json-schema.R`, `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` (architecture §3.2).
  - `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` returns a classed provider
    spec (`c("gptr_provider", "gptr_spec")`, fields of contract §12.1, `offline = TRUE`) that later plans accept
    as `model = <spec>`; its engine turns a script (list of replies, or a function of the request) into INFRA-02
    event sequences, including tool calls, thinking, errors and truncation, and a classifier script into System 1
    answers; `builtin_fake()` registers the `fake` and `fake-classifier` adapters (declared by P05, IC-08).
  - `on_load(expr)` registry in `aaa-state.R`, run by `.onLoad` in `zzz.R`; `.onUnload` calls registered
    cleanups; the service table `ext_service_set()`/`ext_service_get()`/`ext_service_has()` (services owned by
    built-ins, IC-34) and `setting_get()` (contract IC-09, §7.0-7.1), through which earlier plans reach services
    of later ones.
  - Review amendments (contract §15): `gptr_can_prompt()` (IC-43), `supervise_default()` (IC-60), `as_utf8()`
    applied at every ingress (IC-62), `rscript_path()` (IC-60), `user_home()`, `app_config_dir()`,
    `project_root()` honouring `gptr.project_root`/`GPTR_PROJECT_ROOT` (IC-63), `path_key()` and the
    `write_atomic()` rename fallback (IC-51), `path_class()` classes `control` and `instructions` (IC-54),
    `with_seed_preserved()` and `port_candidates()` (IC-61), the per-session `out` store (IC-71),
    `redactor_set()`/`redact_hook()` (IC-34); `setup.R` redirects `HOME`, `USERPROFILE`, `APPDATA`,
    `LOCALAPPDATA`, `XDG_CONFIG_HOME` and sets `GPTR_PROJECT_ROOT`; `expect_no_copy(in_run_edit =)` (IC-41);
    `local_mock_server()` returns an `offline = TRUE` provider, answers only token paths and gains a `redirect`
    scenario (IC-45, IC-64, IC-71); `helper-arch.R` parses `R/` and holds the kernel SDK allowlist (IC-33);
    `test-lint-rules.R` gains the IC-72 rules and detects `<-` through `getParseData()`.
  - The leaf `save_rds()`/`serialize_leaf()` wrappers in `utils-paths.R` (always `ascii = FALSE`, rule R7);
    every later plan serialises user data only through them.
  - `inst/COPYRIGHTS`.
- **Owns.** The 15 R files above and their tests; `tests/testthat.R`, `setup.R`, `helper-fake.R`
  (`fake_text()`, `fake_tool()`, `fake_tools()`, `fake_error()`, `local_fake_provider()`, `fake_requests()`,
  `local_project()`, `local_gptr_options()`; contract §12.2),
  `helper-tracemem.R` (`expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L)` in a
  fresh `Rscript --vanilla`),
  `helper-mock-server.R` + `fixtures/mock_server.R` (`local_mock_server(scenario, ...)`: base-R SSE mock over
  `serverSocket()`/`socketSelect()` with the scenarios of contract §12.2: stream, slow, ttft, hold_headers,
  stall, bytes_per_10s, overload, status (401, 429, 5xx, retry_after), spend_cap, truncated, parallel_tools,
  openai_responses, chat_completions, gemini, systemone, json),
  `helper-arch.R` + `test-arch-layers.R` (layer table of architecture §2.2; codetools; skip without it),
  `test-lint-rules.R` (scans `R/`: no `:::`, ASCII only, no `rlang::enquo`/`enquos`/`quo`, no `cli_*()` or
  `glue` call with a non-literal first argument, no `.GlobalEnv`, no `lockBinding`/`unlockBinding`, no
  `processx::run(`, no `serialize(`/`saveRDS(` without `ascii = FALSE` outside the leaf wrapper, and the
  further rules of contract §12.3),
  `fixtures/tokens/` (a 12-class sample of G2's corpus with o200k counts); `DESCRIPTION`, `.lintr`,
  `.Rbuildignore`, `.gitignore`, `LICENSE`, `LICENSE.md`, `.github/workflows/R-CMD-check.yaml`, `dev/style.R`,
  `inst/COPYRIGHTS`.
- **Test files.** One per owned R file: `test-aaa-state.R`, `test-utils-conditions.R`, `test-utils-hash.R`, `test-utils-encoding.R`, `test-utils-options.R`, `test-utils-paths.R`, `test-utils-text.R`, `test-utils-tokens.R`, `test-json-encode.R`, `test-json-partial.R`, `test-json-schema.R`, `test-provider-message.R`, `test-provider-events.R`, `test-provider-fake.R`, `test-zzz.R` (plus the extra test files named under Owns).
- **Research.** Conventions (all); 13 §2-§5 and C-01..C-58 (DESCRIPTION, tests, CI, C-36); 10a §14
  INFRA-02, 07, 23, 24; 02 §2.4, §4.4 (events, delta-only updates); 03 §4.2 (message model); 19 §2.2 (JSON
  serialised once); G2 (f) and fact-check (estimator constants); G5 (truncation notice, `out` store) and its
  fact-check 13-15; 12 §5.4 and G3 fact-check (tracemem harness); 15 §5.1 (mock server); P-B §2.4 (layer
  test); architecture §2, §5.2-5.4, §6.3, §6.4, §6.6, §12.5.
- **Depends on.** None.
- **Milestone.** M0.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::document()'` exits 0; `NAMESPACE` exports `gptr_fake_provider`.
  2. `Rscript --vanilla -e 'devtools::test(filter = "aaa-state|utils|json|provider-message|provider-events|provider-fake|zzz|arch|lint")'`
     is green (skips only: codetools missing).
  3. `Rscript --vanilla -e 'lintr::lint_package()'` prints no lints.
  4. Tests assert: `gptr_abort("{Sys.setenv(GPTR_PWNED = \"1\")}", "x")` leaves `GPTR_PWNED` unset and the
     condition class is `c("gptr_error_x", "gptr_error", "error", "condition")`; `.Random.seed` is identical
     before and after 1,000 id generations; `canonical_json()` gives the same bytes under `LC_ALL=C` and
     `en_US.UTF-8`; `est_tokens()` has a median absolute error of at most 15% on `fixtures/tokens/`; the
     head/tail truncation keeps 40%/60% by lines and returns an `out` id; the partial-JSON scanner yields the
     final object for every prefix split; schema validation of `{"n":3}` against a schema requiring `code`
     returns an error naming `code`; the fake provider emits the golden event sequences for text, thinking,
     two parallel tool calls, an error after deltas and a truncated stream.
  5. `helper-tracemem.R` self-test: `str(big)` is reported as COPY and `big[1] = 0` alone as in place.
  6. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`: 0
     errors, 0 warnings, no NOTE apart from the maintainer line; the CI matrix (incl. Windows, oldrel-4,
     no-suggests, `LC_ALL=C`, connections-left-open) is green.
  7. Review additions: `R CMD INSTALL` of the package succeeds with a test file collating after `utils-*.R` that
     calls `on_load()` at top level (IC-32); a DESCRIPTION assertion test checks `Authors@R` roles (`cph` for the
     maintainer, `ctb`/`cph` for Mario Zechner), `Copyright`, `URL`, `BugReports`, `Language`, `ps` in Imports
     and no `VignetteBuilder`; `as_utf8("caf\xc3\xa9")` keeps the bytes under `LC_ALL=C` while `enc2utf8()` would
     not (IC-62); `lintr::lint_package()` passes on fixtures defining `.DollarNames.gptr_session`,
     `knit_print.gptr_session`, `vec_proxy.gptr_s1` and a closure using `<<-`; `.Random.seed` is unchanged by
     `with_seed_preserved(httpuv::randomPort())` (skip without httpuv); `user_home()` equals `USERPROFILE` in a
     mocked Windows test.

### P02 Extension API and registry

- **Goal.** The one public, versioned extension API on which every capability and every built-in registers
  (S-11).
- **Scope.** Registry keyed by (kind, name) with ranks (session 0, project 1, user 3, plugin 5, built-in 6),
  filters (`-builtin:<name>`, `-<kind>:<name>`, `+...`; project filters cannot disable user or built-in
  policies and hooks), diagnostics and a generation counter, exported as `gptr_register()` and `gptr_registry()`
  (with the `tokens` column); the 37 kinds of `ext-specs.R` and their validators
  (architecture §11.1 minus `interpreter`, plus `route`, `preset`, `risk_rule`, `service`, `renderer`,
  `search_source`, `store`, `evaluator`; contract IC-02, IC-34, IC-69 and §10.2); `ctx` members bound lazily through
  P01's service table (contract IC-09, IC-34, §7.0); `gptr_spec()` and the 11 exported
  constructors; `gptr_tool_result()`; the factory API object with
  `register()`, generated `register_<kind>()` sugar for every kind, `on()`, `require()`, `has()`, `state`;
  the `ctx` object (`session`, `envir`, `mode()`, `model()`, `has_ui()`, `ui()`, `risk()`, `redact()`,
  `execute_tool()`, `send()`, `append_entry()`, `abort()`, `decide()`, `usage()`, `state()`, `emit()`; members
  whose services arrive later return a classed "not available" error until their plan registers them);
  the event catalogue with dispatch semantics (notify, transform, patch, first decision, block) and fail-closed
  `tool_call`, `permission_request`, `document_write`; transactional factory loading (stage, commit, rollback),
  lazy activation from manifests with `declarations`, API requirements, `gptr_reload()` with stale-API errors;
  `gptr_check()` conformance for specs and factories; `gptr_api()`; the built-in declaration table filled by
  `on_load(ext_declare_builtin(...))` and loaded in dependency order.
- **Review amendments (contract §15).** Overrides are per `(kind, name)`; a whole built-in is disabled only by an
  explicit filter (IC-69); no filter disables `builtin:permissions`, `builtin:plan` or the guards, and filters that
  remove policies or hooks are refused inside a run (IC-53); `ext_load(..., session =)` and session-scoped hooks
  and lazy activation (IC-69); the constructor signatures of IC-35 (adapter validation per transport, provider
  fields `status`, `aliases`, `local`, `offline`, `rate`, router `timeout`, section `parent`, context-block
  `placement = "both"` and `order`); `gptr_agent()` stores raw expressions (IC-34); the `ctx` members of IC-69
  (`set_model`, `add_tools`, `tokens`, `eval`, `describe`) and `ctx$send()` with `source = "extension"` (IC-55);
  the `request_params` event; `gptr_check(tokens =)` (IC-69); context blocks with `authority = "operator"` only from
  rank >= 3 (IC-52).
- **Owns.** `ext-registry.R`, `ext-specs.R`, `ext-api.R`, `ext-events.R`, `ext-load.R`, `ext-check.R`,
  `ext-builtins.R` and their tests.
- **Test files.** One per owned R file: `test-ext-registry.R`, `test-ext-specs.R`, `test-ext-api.R`, `test-ext-events.R`, `test-ext-load.R`, `test-ext-check.R`, `test-ext-builtins.R` (plus the extra test files named under Owns).
- **Research.** G1 §3 (registry, kinds, events, ranks, filters), §4.2-4.6 (factories, transactional loading,
  lazy activation, versioning, SDK) and fact-check (permission_request must be implemented fail-closed; 15
  uncatalogued Pi events); 05 §4 (Pi's extension API, patch returns); 16 §4.9 (manifests); architecture
  §5.4, §5.10, §11.
- **Depends on.** P01.
- **Milestone.** M0.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "ext")'` is green.
  2. Ported G1 checks pass: precedence by rank, filters, a replaceable built-in overridden by a user spec,
     rollback of a factory that errors after two registrations, unmet API requirement disables only that
     factory, stale API object raises `gptr_error_stale_api` after `gptr_reload()`, a throwing `policy` and a
     throwing `permission_request` hook both deny, a throwing `document_write` hook blocks, a notify hook
     error becomes a diagnostic, a plugin-defined kind is registered and resolved.
  3. `gptr_check()` returns a passing `gptr_check` data frame for a valid spec of every kind and names the
     failing field for an invalid one; a direct tool description over 400 tokens fails.
  4. Registering 100 lazy manifests takes under 50 ms (G1 measured 8-16 ms).
  5. Review additions: every §6.8 example of the contract runs; a user `read` override leaves `edit` and the
     `gptr$grep` member working; a factory loaded with `session = <id>` is invisible to another session and removed
     at its shutdown; a `-builtin:permissions` filter from user settings, a call and `gptr_config()` is refused; a
     plugin `service` record replaces a built-in service and disappears with its plugin; an `operator` context block
     registered at rank 1 is refused.

### P03 Secrets and redaction

- **Goal.** Keys never reach any transcript, log, document, cache, spill file, console or child process that
  does not need them (REQ-13, INFRA-22).
- **Scope.** Vault and `gptr_secret` handles; ambient discovery; origin-bound materialisation; `gptr_env()`
  with gptr's own `.env` parser (BOM, CRLF, `export`, quotes, multi-line values, ` #` comments, hyphenated
  names) and the alias table (`jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` -> `TYPESAFE_API_KEY`);
  the redactor with profiles `persist`, `context`, `stream`, `code`, `user_data`, derived forms, 12
  gitleaks-derived patterns (with `PRIVATE KEY(?: BLOCK)?`), `NAME=value`, markers `[secret:NAME]`, one PCRE
  alternation, streaming hold-back, the `code` rewrite to `Sys.getenv("NAME")`; `gptr_redact()`; the
  credential store `auth.json` (0600, lock, keyring references); child-environment profiles `mcp`, `worker`,
  `cli-claude`, `cli-codex`, `helper`, `artifact` with empty `R_ENVIRON_USER`/`R_PROFILE_USER` files and
  billing-switch removal; `builtin:secrets` registering the secret sources, redaction rules, env aliases and
  child-env profiles as specs.
- **Review amendments (contract §15).** `child_env()` returns complete vectors without removed names (processx
  rejects `NA`) and `child_env_callr()` gives the callr form; every profile gets the empty
  `R_ENVIRON_USER`/`R_PROFILE_USER` files and drops `R_ENVIRON` (IC-60); the CLI profiles follow G6 §3.7 verbatim
  (enclosing-agent variables, `ANTHROPIC_PROFILE`, `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`,
  `CODEX_MANAGED_*`, `CODEX_SANDBOX*`; IC-65); `redact()` is installed with `redactor_set()` (IC-34);
  `gptr_scrub()` (exported) and the `secret_late` warning of `secret_register()` (IC-70); the `secret.lookup`
  service.
- **Owns.** `auth-secrets.R`, `auth-redact.R`, `auth-dotenv.R`, `auth-store.R`, `auth-childenv.R` and their
  tests.
- **Test files.** One per owned R file: `test-auth-secrets.R`, `test-auth-redact.R`, `test-auth-dotenv.R`, `test-auth-store.R`, `test-auth-childenv.R` (plus the extra test files named under Owns).
- **Research.** G6 §1-§4 and fact-check (callr `~/.Renviron` re-injection, PGP blocks, billing precedence);
  13 C-36; 07 §4.5; 08 (never read `~/.codex/auth.json`); 03 §2.11; architecture §6.5.
- **Depends on.** P01, P02.
- **Milestone.** M0.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "auth")'` is green (skips: keyring missing).
  2. G6's 17 parser checks and 40 redactor checks pass; streaming redaction equals whole-text redaction over
     1,400 random chunkings; `format()` and `serialize()` of a handle contain no key bytes.
  3. With a fake key in a temporary `.Renviron` (`withr::local_envvar(R_ENVIRON_USER = <file>)`), a callr
     child started with `child_env("worker")` sees neither the key nor the file (skip_on_cran).
  4. A handle bound to `https://api.anthropic.com` refuses to materialise for any other origin with
     `gptr_error_untrusted`.
  5. `auth.json` is created with mode `0600` on Unix; the store round-trips a keyring reference.
  6. Review additions: an Rscript child started through `proc_spawn()` with the `mcp` and `helper` profiles and a
     `.Renviron` defining a fake key does not see it (skip_on_cran); `child_env()` contains no `NA` and
     `processx::process$new(env = child_env("helper"))` starts; the claude profile removes `CLAUDECODE` and
     `ANTHROPIC_PROFILE` and keeps `CLAUDE_CONFIG_DIR`; `gptr_scrub()` finds a value registered after it was
     written, rewrites it with `dry_run = FALSE` and `error = TRUE` signals `gptr_error_secret_found`.

### P04 Reactor and process engine

- **Goal.** gptr's own transport and process layer: one reactor for every stream and child pipe (S-10,
  INFRA-01/05/06/16/21/23).
- **Scope.** `proc-spawn.R` (G5 engine: `process$new` with file redirection, `os_bytes()` argv, `write_all()`,
  line reader, UTF-8 decode with code-page fallback, Git Bash / PowerShell `-EncodedCommand` / cmd
  resolution, `.cmd`/`.bat` via `cmd.exe /d /c call` with metacharacter refusal); `proc-supervise.R`
  (`kill_all()`, grace, process tables, orphan sweep, `.onUnload` cleanup through `on_load()`);
  `http-reactor.R` (architecture §6.1 API, `allow_runs`, admission, `later::run_now(0)` when loaded, the opt-in
  redacted JSONL wire log); `http-request.R` (`pipewait = 0L`, connect, first-byte and idle timers, no total
  timeout, handle materialisation); `http-sse.R` (vectorised byte splitter, final-event flush, NDJSON);
  `http-retry.R` (classes, bounded backoff with time jitter, Retry-After cap, spend-cap rule, per-provider
  limiter).
- **Review amendments (contract §15).** Processes created with `encoding = "UTF-8"`; non-blocking `write_all()`
  drained by the reactor with `gptr.stdin_timeout` (IC-60); `supervise_default()`; tree markers under
  `R_user_dir("gptr", "cache")/procs/` and a mandatory orphan sweep at load; job-table `stop_requested`
  (IC-60); `pid_alive()` with ps and creation times (IC-59); `gptr_jobs()` moves here (IC-36); reactor depth,
  the `allow_runs` default inside a run and `later::run_now(0)` only in the outermost pump or for a served CLI
  child (IC-57); `followlocation = 0L` and the `redirect` class (IC-64); the SSE splitter per the specification
  (CR/LF/CRLF, BOM, last `event:` wins) (IC-64); locale-independent `parse_http_date()` and static provider
  rates in the limiter (IC-64); every child pool capped at 2 under check (IC-60); per-session wire logs written
  open-append-close (IC-59, IC-65).
- **Owns.** The six R files and their tests.
- **Test files.** One per owned R file: `test-proc-spawn.R`, `test-proc-supervise.R`, `test-http-reactor.R`, `test-http-request.R`, `test-http-sse.R`, `test-http-retry.R` (plus the extra test files named under Owns).
- **Research.** 15 §2.2-2.5, §4.1-4.2, §5.1-5.2, §5.9 and verifier; 10a §14 INFRA-01, 05, 06, 16, 21, 23 with
  their acceptance tests; 21 §2.6; 02 (curl multi survives resumed interrupts); 07 §4 (spend-cap 429); 08
  fact-check (`write_input()` truncation); G5 (engine, Windows notes) and fact-check 1-4, 16-18, 24; 16 §6.2;
  13 §2.10 (supervise fifos); architecture §6.1, §6.7.
- **Depends on.** P01, P03.
- **Milestone.** M0.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "http|proc")'` is green (mock-server tests skip on CRAN).
  2. INFRA-01: on the mock (12 events every 0.25 s) the first text delta reaches the callback within 0.35 s and
     every inter-delta gap is under 0.35 s; six streams of 1.00-2.25 s finish within 10% of the slowest.
  3. INFRA-05: held headers give `gptr_error_timeout_first_byte`; a stream sending one byte every 10 s for
     60 s completes; a stall gives `gptr_error_timeout_idle`.
  4. INFRA-06/21: `retry-after: 2` retried after about 2 s; `retry-after: 3600` fails at once naming the delay;
     a spend-cap 429 is not retried; with low remaining-request headers a 20-transfer fan-out never exceeds the
     budget.
  5. INFRA-23: 20,000 deltas are consumed in under 1 s of CPU; random re-chunking including splits inside
     multi-byte characters gives identical events.
  6. Process engine: under `LC_ALL=C` a child printing `"café"` and a CJK string is decoded byte-exact, both
     through redirected files and through the pipe path read by `reactor_proc()`; a 2 MB stdin payload arrives
     complete, and a 4 MB payload to a child that echoes each line completes without deadlock; `kill_all()` leaves
     no descendant; a `.cmd` argument containing `&` is refused with `gptr_error_invalid_argument` (logic test on
     every OS).
  7. Review additions: a parent killed with SIGTERM leaves children that the next load's sweep removes; the
     redirect mock receives no key bytes and the transfer fails with `gptr_error_redirect`; `test-http-sse.R`
     covers CRLF, CR-only, split-CRLF, a BOM and duplicate `event:` fields; `retry-after` as an HTTP-date under
     `LC_ALL=de_DE.UTF-8` and `retry-after: soon` fall back correctly; a nested pump started inside a FIFO tool
     never runs a sibling's queued tool and never calls `later::run_now(0)`; `pid_alive()` is FALSE for a reused
     pid with another creation time; `nrow(showConnections())` is unchanged after the wire log wrote 100 lines.
  8. **M0 exit** (once P01-P04 are complete): `devtools::check(args = c("--as-cran", "--no-manual"),
     error_on = "warning")` clean on the full CI matrix including Windows, and `R CMD INSTALL` succeeds with the
     built-ins' top-level `on_load()` declarations (IC-32).

---

## M1 Offline S-8 kernel

### P05 Model layer core

- **Goal.** Provider records as data, the hand-off transform, usage and cost, and the model catalog.
- **Scope.** `provider-transform.R` (projection: drop aborted/errored assistant entries, synthetic results for
  orphaned calls; hand-off across provider/model/api; id normalisation); `provider-registry.R` (records for
  every provider of architecture §8.1-8.2 as data, compat table [09 §3], auth resolvers returning handles,
  origin binding (the egress acknowledgement is P08's `egress_check()`), `provider_stream()` (contract §8.4),
  `builtin:providers`, the
  `builtin:fake` declaration of P01's factory (contract IC-08), `gptr_providers()`); `provider-usage.R`
  (usage rows of §5.5, dated price tiers, TTL-split cache writes, routes, roll-up, the process System 1 log;
  `gptr_usage()` itself is P06's, contract IC-05); `catalog-models.R` (snapshot load, merge layers, aliases, `provider/id[:thinking]`
  resolver, thinking clamp, `adist()` suggestions, explicit ETag refresh into `R_user_dir()`,
  `gptr_models()`); `inst/extdata/models.json.gz` and `dev/catalog/build_models.R`.
- **Review amendments (contract §15).** Provider records carry `offline` (no remote model is called; the fake,
  mock-server and fake-CLI providers) and static `rate` fields (IC-45, IC-64); `provider_stream()` injects
  `opts$gate`, `opts$mcp_dispatch` and `opts$tool_result` from the run so L1 adapters never call L2+ (IC-33); the
  catalog carries `forced_tool_choice`, `max_images` and `cache_min` per model (IC-67, IC-71, IC-73);
  `gptr_providers(check = FALSE)` spawns no process (IC-65).
- **Owns.** The four R files and tests; `inst/extdata/models.json.gz`; `dev/catalog/build_models.R`.
- **Test files.** One per owned R file: `test-provider-transform.R`, `test-provider-registry.R`, `test-provider-usage.R`, `test-catalog-models.R` (plus the extra test files named under Owns).
- **Research.** 03 §2.1-2.9, §4; 09 §3-4 and fact-check; 10a INFRA-04, 08, 17, 20; 07 §1 (prices, cache
  multipliers); G2 fact-check (dated tiers, cache-read multipliers); 02 §2.7; architecture §5.5, §8.
- **Depends on.** P02, P03, P04 (`provider_stream()` runs on the reactor, contract §8.4).
- **Milestone.** M1.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "provider-transform|provider-registry|provider-usage|catalog")'`
     is green.
  2. INFRA-04: after a recorded 401 and after an abort, the projected message list has no assistant content
     for them and every tool call has exactly one result.
  3. INFRA-08: an Anthropic conversation with thinking and tools, projected for `openai-responses` and
     `google-generative-ai`, contains no foreign signature, encrypted item or thought signature.
  4. INFRA-17: an `ollama` record added by data resolves without code; the fake provider passes
     `gptr_check()`.
  5. INFRA-20: the fixture usage for a turn with 1 h cache writes gives the documented dollar amount; child
     usage rolls up; the `route` column is present.
  6. `gptr_models("sonnet")` resolves offline from the snapshot in under 0.1 s; no network request happens at
     load (a test counts reactor transfers).

### P06 Session kernel and agent loop

- **Goal.** The S-8 session object and the agent runtime: loop, dispatcher, store, fork, resume, budgets.
- **Scope.** `session-object.R` (shell + `.d`, accessors, print/format/summary (no `knit_print`: P15, contract
  IC-07), `$<-` refusal, value policy, `gptr_fork()` with the overlay default); `session-live.R` (weak
  live registry, home-workspace policy with the frame reset at settlement, pid locks, split-brain rules,
  `gptr_last()`); `session-store.R` (Pi-v3 JSONL tree, appends in `suspendInterrupts()`, torn-line tolerant
  reader, lazy fork files, `gptr_sessions()`, `gptr_resume()`); `session-budget.R` (budgets, token ledger,
  `gptr_usage()`, contract IC-05);
  `agent-loop.R` (pure state machine with injected stream function, context builder and tool executor;
  steer/follow-up queues; `max_turns`); `agent-run.R` (run lifecycle on the reactor, agent-level retry,
  overflow and one compact-and-retry via the registry's compactor, nested runs with `allow_runs`, abort,
  structured final answers for `.opts$returns`, the plan-mode scratch overlay `run_eval_env()`, contract IC-15);
  `agent-dispatch.R` (validate -> gate -> execute; never throws; FIFO; results in source order; nested-call
  gating entry point; `perm_check()`: the combination of `policy` records, `permission_request` hooks, the UI
  and the non-interactive stop, contract IC-04; with no `mode` policy registered the gate asks, fail closed,
  IC-53).
- **Review amendments (contract §15).** The store appends open-append-close, recovers torn lines at resume, skips
  unparsable lines, and locks with pid, creation time and a 10-minute heartbeat (IC-59); `the$last` is strong
  (IC-71); the replay functions `session_replay_apply()`, `session_replay_new()`, `session_replay_bind()`,
  `replay_lookup()` and `gptr_resume(block =, child =)`, with fresh overlays for rebuilt forks and reconstructed
  histories (IC-46); `perm_check()` with `ask_human`, a single modify re-check, the run's safety snapshot and mode
  inheritance for every call made during a run (IC-53); relays and queue items by source (IC-55); budgets with the
  default ceiling, root charging, `gptr.max_nested_calls` (IC-66); router calls before each request through
  `router.call` (IC-69); the `ctx.kernel` service (IC-34); per-session `out` stores (IC-71); image elision entries
  (IC-67); the `store` kind's built-in record (IC-69); re-classification of worker-forwarded permission requests
  (IC-53).
- **Owns.** The seven R files and tests; `tests/testthat/fixtures/oracles/report02/` (the 24 loop, 42 store
  and 26 recovery checks of report 02, converted to R test data).
- **Test files.** One per owned R file: `test-session-object.R`, `test-session-live.R`, `test-session-store.R`, `test-session-budget.R`, `test-agent-loop.R`, `test-agent-run.R`, `test-agent-dispatch.R` (plus the extra test files named under Owns).
- **Research.** G3 (all) and fact-check; 02 §2.2-2.12, §4.1-4.11, §5.1-5.9; 10a INFRA-09, 10, 12, 13, 14, 15,
  25, 26; 12 §3.10 (overturned return value, for context); G1 §4.6; 15 §4.2; architecture §2.3, §5.1-5.3,
  §6.2, §6.9.2.
- **Depends on.** P04, P05.
- **Milestone.** M1.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "session|agent")'` is green (SIGKILL test skips on CRAN).
  2. Report 02's 24 loop, 42 store and 26 recovery checks pass.
  3. INFRA-09/10: `{"n":3}` without `code` gives an error result and the function is not called; a
     `length` stop mid-call gives an error result and `done(length)`; a property test with throw, interrupt,
     warn-as-error and a 30 s timeout inside tools completes with paired events.
  4. INFRA-12: a steer enqueued during a tool is on the wire after the tool-result message; `max_turns = 3`
     stops with status `max_turns`.
  5. INFRA-13: SIGKILL during a streamed turn, then `gptr_resume()`: the file parses, the last complete message
     is present, nothing is duplicated; `.Random.seed` is unchanged over 1,000 appends; a forked file replays
     to the source path's context.
  6. INFRA-14/15: a listener on `gptr_fork(s)` never fires for `s`; overlay writes do not reach `s$envir`; two
     concurrent sessions keep separate usage.
  7. G3 analogues: `identical(s |> step, s)`; `$<-` refused; an unreferenced settled session is finalised and
     its lock removed (except the one `gptr_last()` holds); a same-process duplicate continues with
     `gptr_error_split_brain`.
  8. Review additions: `nrow(showConnections())` is unchanged after `gptr()` returns, errors or is interrupted, and
     after 300 sessions kept in a list; SIGKILL mid-append, resume, three appends: all present and the tree
     connected; `gptr_last()` survives `gc()`; with no policy registered a mutating tool asks (and is `blocked`
     without a UI); a hook answering allow to an `ask_human` is ignored; an option changed by model code mid-run
     does not change the run's gate; a budget of 5 USD on a root stops its children; `session_replay_apply()` keeps
     `identical()` along a replayed pipe chain.

### P07 Prompt, context, caching and compaction

- **Goal.** A frozen, cache-anchored, append-only context whose token cost is measured.
- **Scope.** `prompt-sections.R` (section registry, presets `minimal`/`standard`/`readonly`/`extended`,
  freeze, section patches, `builtin:prompt` registering sections, the gap-based `cache_policy` and the default
  `estimator`, `gptr_prompt()`); `prompt-text.R` (the verbatim texts of architecture §7.3-7.4); `prompt-context.R`
  (project-instructions discovery root to cwd with vignette.Rmd last and additive, `<environment>`, `<mode>`,
  `<plan>`, first-message rendering reused after compaction, per-turn deltas, `builtin:context`; until P09
  registers the `attached` and `workspace` blocks, attached objects render as a one-line `name <class>`);
  `prompt-cache.R` (request assembly by concatenation, per-provider breakpoint plans, gap-based tail TTL, prefix
  guard with `cache_break`); `prompt-compact.R` (threshold formula, cold rule, in-conversation checkpoint with
  G4's verbatim prompt, harness state extraction, `builtin:compaction`).
- **Review amendments (contract §15).** Context placement `both` and turn-block deduplication (IC-38); the four
  `preset` records and `preset_tools()` from them (IC-69), with `ask` kept in non-interactive `manual` runs and
  the manual suffix (IC-68); `<rules>` composed from the active tools' guidelines plus P07's closing lines and
  `<r_session>` from P07's core plus fragments; P07 no longer owns `documents`, `artifacts`, `system1` (IC-68);
  the `str()`-free texts and the `trusted="false"` sentence (IC-67, IC-52); `project_instructions` rendered
  `trusted="false"` in untrusted projects and omitted non-interactively in `auto`/`edits` (IC-52);
  `session_add_tools()` and the `session.add_tools` and `ctx.input` services (IC-69, IC-34); the compaction floor
  check (IC-71); shipped `tools.presets` defaults for Gemini 3 and Haiku 4.5 (IC-73); the golden-transcript runner
  `dev/bench/tokens/run.R` with the NS-2 and NS-3 fixtures (IC-73).
- **Owns.** The five R files and tests; `test-context-prefix.R`; `test-bench-context.R`;
  `tests/testthat/fixtures/bench/prefix-baseline.json`; `dev/bench/tokens/run.R` and the NS-2/NS-3 golden
  transcripts (IC-73).
- **Test files.** One per owned R file: `test-prompt-sections.R`, `test-prompt-text.R`, `test-prompt-context.R`, `test-prompt-cache.R`, `test-prompt-compact.R` (plus the extra test files named under Owns).
- **Research.** G4 §2-§5 and fact-check (gap-based TTL, 33-pair prefix test); G2 (b), (f), (g); 20 §4.2,
  §4.5; 14 §4.8; 07 §2.5 (append-only for preserved thinking); 05 §4.2; architecture §6.11, §7, §12.
- **Depends on.** P06.
- **Milestone.** M1.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "prompt|context-prefix|bench-context")'` is green.
  2. P07-owned rendered sections are byte-identical to architecture §7.3 as amended (the other owners' texts are
     compared in their plans and composed in P24); each section is within its budget; with a fixed T1 fixture
     (`<r_env>` plus the two built-in skills, 542 tokens) standing in for P09's and P17's sections, the preset
     estimates are within 5% of `prefix-baseline.json` (initial values: 1,271 / 2,360 / 2,844 / 2,987 measured
     o200k tokens, stored with the estimator's figures; IC-68); no shipped text mentions `str(` (IC-67).
  3. The 20-turn scenario: all same-target consecutive request pairs (33 of 33 in G4's scenario) are byte
     prefixes across turns, model switches and returns, tool and skill activation, steering and mode changes;
     tools, system and the anchored project block are identical across compaction; the negative controls
     (re-rendered system prompt, edited entry) are detected and emit `cache_break`.
  4. INFRA-26: a mock overflow triggers exactly one compaction entry and one retry; a second overflow surfaces
     as an error.
  5. The tail TTL switches to 1 h after a simulated 241 s gap and not after 239 s.
  6. Review additions: the first request of `gptr("x", mtcars)` contains `<attached name="mtcars">` after
     `<workspace>` (with a stub `attached` block until P09); an unchanged plugin turn block is sent once; the
     `readonly` preset has no edit or write rules; a session in an untrusted project renders
     `<project_instructions trusted="false">`; a model with an 8K window and a large project block is refused for
     the standard preset with the suggestion; `Rscript --vanilla dev/bench/tokens/run.R --check` passes on NS-2 and
     NS-3.

### P08 Gateway and SDK

- **Goal.** `gptr()` itself: copy-safe capture, identifier resolution, routing through the registry, and the
  SDK verbs; M1's offline S-8 contract.
- **Scope.** `gptr-gateway.R` (the classed closure `gptr` with `$`, `[[`, `.DollarNames`, `$<-` refusal and
  `print` methods, `$`/`[[`/`.DollarNames` through the `ns.resolve`/`ns.names` services of P10 (IC-36); dispatch
  steps 1-5 of architecture §4.1.1 with routes looked up in the registry; return visibility; the registration point
  for routes contributed by later plans); `gptr-capture.R` (base-R capture under rules R2-R3, prompt selection,
  identifier resolution table §4.1.3 including `!!` and `I()`, `{identifier}` interpolation); `gptr-sdk.R`
  (`gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()`; `gptr_prob()` is
  P13's, IC-36); `gptr-config.R` (settings layers,
  `gptr_config()`, `gptr_init()` without a default path, `gptr_trust()`, egress acknowledgement, the settings I/O
  that P11's `gptr_permissions()` uses (contract IC-06), `replay_mode()` and `replay_guard()`); the
  `builtin:gateway` factory registering the routes `nested`, `continue`, `new` and the core `setting` specs
  (contract IC-24); `inst/templates/vignette.Rmd`, `settings.json`, `gitignore`.
- **Review amendments (contract §15).** Plain-symbol dots read through a `get0()` leaf without forcing (IC-41);
  the evaluation-environment precedence and the visibility check for continuations (IC-40); identifier
  normalisation for skills, plugins, extensions and agents (IC-42); namespaced `.opts`, `.opts$images`,
  `.opts$seed`, `.opts$frontend` (IC-44, IC-61, IC-69); route orders (IC-39); mode and filter inheritance for
  every call made during a run (IC-53); router models stored as `router:<name>` and the `router.call` service
  (IC-69); `gptr_can_prompt()` for the human check and questions (IC-43); `gptr_return()` returning `invisible(x)`
  outside a run (IC-48); `gptr_config(.scope = NULL)` (IC-71); `replay_mode()` forcing replay only outside
  testthat (IC-45); trust fingerprints and `project_trust` as a first decision (IC-52, IC-71); the `trust.get`
  and `identifier.resolve` services (IC-33, IC-34); `control`-category run checks in the setup exports (IC-53);
  the egress acknowledgement as an `ask_human`; the `interp` record behind the `args=` header key (IC-45).
- **Owns.** The four R files and tests; `test-copy-gateway.R`; `inst/templates/`.
- **Test files.** One per owned R file: `test-gptr-gateway.R`, `test-gptr-capture.R`, `test-gptr-sdk.R`, `test-gptr-config.R` (plus the extra test files named under Owns).
- **Research.** G3 (3)-(4), (7), (12), t2, t2b, t5 and fact-check (capture rules); 12 §2.D-§3.11; 13 §2.3-2.4,
  C-24, C-34 (consent, egress); 05 §4.1 (formals after dots); 18 §4.2; 14 §4.4.2 (document route interface);
  16 §7.1(3) (trust); architecture §4.1, §4.3, §6.4, §6.10.
- **Depends on.** P03, P07.
- **Milestone.** M1.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "gptr-|copy-gateway")'` is green (copy tests skip on CRAN
     and without profmem).
  2. Call shapes on the fake provider: `gptr("a", mice)` and `mice |> gptr("a")` create sessions with a
     `mice` context label; `gptr("a") |> gptr("b") |> gptr("c", model = <second fake>)` returns the same
     object with three turns and a `model_change` entry; a test tool that pipes into its own running session
     enqueues a steer delivered after the tool result; `gptr()` non-interactively errors with
     `gptr_error_noninteractive`.
  3. Identifier table: each row of §4.1.3 including a wrapper `w = function(...) gptr("x", ...)` with a local
     `m` resolving to the caller's value (G3 t2b), an alias shadowed by a character variable (notice), `!!m`,
     `I(m)`, `if (hard) a else b`.
  4. Copy suite: every gateway row of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded
     dots, alias and if/else models, `$value` reads, print/summary/str of a session, fork, `saveRDS`) is in
     place, and the in-run edit rows of IC-41 (`gptr("x", big)`, `big |> gptr("x")`, `s |> gptr("x", big)` with
     `in_run_edit = TRUE`) report 0 copies.
  5. `gptr_init()` without `path` errors non-interactively; with a path it creates the template files and does
     not touch `.Rbuildignore`; a project without `gptr_trust()` ignores project settings beyond tightening;
     a non-interactive first use of a provider without an acknowledgement raises `gptr_error_egress`.
  6. Review additions: `f = function(s, d) s |> gptr("filter d", d)` with `s` homed in `globalenv()` either
     evaluates where `d` is visible or fails fast naming `d`; `skills = single_cell` resolves to `single-cell`;
     `gptr_return(x)` outside a run returns `x` invisibly; `gptr_config(mode = manual)` writes the project file when a
     workspace exists; under `_R_CHECK_PACKAGE_NAME_` with `TESTTHAT=true` replay is not forced; a model-code call of
     `gptr_permissions(allow = "r(level<=3)")` during a run is refused with `gptr_error_permission`; `.opts =
     list(panel = list(size = 3))` reaches `ctx$input$opts$panel` when a `panel.size` setting is registered.
  7. **M1 exit** (once P05-P08 are complete): `devtools::check(args = c("--as-cran", "--no-manual"),
     error_on = "warning")` clean; every exported example runs offline on the fake provider (the `gptr_prob()`
     example is P13's, so none needs a later plan; IC-36).

---

## M2 Live R agent and System 1

### P09 Evaluator and workspace

- **Goal.** Evaluate model code in the live session, capture everything REQ-23 asks for, and describe the
  workspace compactly, without ever copying a user object (headline benefit 1).
- **Scope.** `eval-core.R` (hand-rolled evaluator of architecture §6.12: parse with `srcfilecopy()`, sink
  capture cleaned up in `suspendInterrupts()`, per-expression `setTimeLimit()` with no timeout when a human is
  present, calling handlers created outside the frame holding the home, interruption recorded with
  `on.exit()`, symbols printed by name, state diff); `eval-plots.R` (recorded device, PNG at 768x512 res 120,
  ragg when installed, `gptr$plot()` support); `eval-guard.R` (forbidden calls, interactive traps, the
  `gptr::` shim when `gptr` is not attached); `eval-format.R` (model text within the 4,000-token budget, head
  40% / tail 60%, state-change lines, `gptr$out(id)` notices, tighter budget above half the compaction
  threshold); `env-snapshot.R` (names, addresses, fingerprints, diff; `builtin:workspace` registering the
  `workspace`, `workspace_changes`, `attached` and `r_env` context blocks); `env-describe.R` (`gptr_describe()`
  generic, level-based methods listed in architecture §7.5); `env-history.R` (task-callback log, last 20);
  `env-probe.R` (capability probe for `<r_env>` without loading packages).
- **Review amendments (contract §15).** R8 clears every `withVisible()` result in place (IC-67); plots on
  `pdf(NULL)` when no device is open and no human sees one, the prior device restored; at most
  `gptr.r_max_images` images per result, the rest stored for `gptr$plot(k)`, image tokens in the budget, image
  elision above provider limits (IC-67); `rng_swap()` with hash-derived L'Ecuyer seeds (IC-61); `eval_guard()`
  flags `q`/`quit` in any position (IC-67); describers for packages outside Suggests use slots and base generics
  only (IC-71); `attached` and preloaded `skill_content` blocks with `placement = "both"` (IC-38); the `evaluator`
  record `r` and the `eval.r` and `describe` services (IC-69, IC-34).
- **Owns.** The eight R files and tests; `test-copy-eval.R`.
- **Test files.** One per owned R file: `test-eval-core.R`, `test-eval-plots.R`, `test-eval-guard.R`, `test-eval-format.R`, `test-env-snapshot.R`, `test-env-describe.R`, `test-env-history.R`, `test-env-probe.R` (plus the extra test files named under Owns).
- **Research.** 12 §2-§5 and fact-check (evaluate defects, sticky references, withVisible, plots); G2 (c)
  describers and fact-check (Seurat meta.data at 150 tokens is a design requirement), (g) plots; 19 §3.2
  (probe); 21 §2.9 (fingerprints); G3 fact-check (tool code in a function-frame home copies unless R2/R3 are
  followed); G7 §1 (interplay with pre-images); 18 §4.8; architecture §6.4, §6.12, §7.5.
- **Depends on.** P08.
- **Milestone.** M2.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "eval|env-|copy-eval")'` is green.
  2. Report 12's torture cases: sinks and `options()` restored after errors and interrupts; warnings and
     messages captured in order; an error stops at the first failing expression with a trimmed traceback;
     `q()` and `readline()` are refused without evaluation; a plot yields one 768x512 PNG block.
  3. Copy suite: evaluation at top level, in `globalenv()` from a function, and **in a function-frame home**
     (`eval_r("n = 1L; length(d)", <the frame of f>)` called inside `f = function(d) ...`) leaves the caller's 40 MB
     object editable in place; the rows `L$a`, `(x)`, `get("x")`, `x@slot` and `x[["a"]]` evaluated at top level
     leave it in place (IC-67). The `gptr()` form of the function-frame case is in `test-copy-tools.R` (P10).
  4. Describers keep at least 90% of G2's 98 facts at a 150-token budget, including Seurat-like
     `meta.data` dimensions and columns, Dates, dgCMatrix dims and nnz, formula text and nested names; ALTREP
     `1:1e9` is described without materialising.
  5. `env-probe` leaves `loadedNamespaces()` unchanged; `<workspace>` for six objects is at most 600 tokens and
     never forces a promise or an active binding.
  6. Review additions: a plotting `r` call under Rscript leaves no `Rplots.pdf` in `getwd()`; a 50-plot loop
     attaches 3 images and lists the rest; `.Random.seed` is identical before and after an evaluation with an agent
     stream; `g = q; g()` is blocked.

### P10 Tools and the `gptr$` namespace

- **Goal.** The model-visible tools `r`, `read`, `edit`, `write` and the namespace that makes every other
  capability an R function (S-12 composition).
- **Scope.** `tool-namespace.R` (gateway methods resolving members from `exposure = "r"` tool specs, generated
  closures from JSON Schema, side-effect-free `$`, `.DollarNames` completion, `gptr$help()`, `gptr$search()`
  (BM25 over members, plugin and MCP tools, skills), `gptr$describe()`, `gptr$plot()`, `gptr$out()`,
  `builtin:tools`); `tool-r.R` (`r` tool schema of §7.2, record/note/timeout, results through the evaluator,
  nested-call gating hook, `builtin:r`); `tool-read.R` (encodings, windows, images by magic bytes, large-file
  index, 12,000-token cap, line numbers off); `tool-write.R` (atomic, EOL- and encoding-preserving); `tool-edit.R`
  (multi-edit, fuzzy fallback, `*** Begin Patch` envelopes, diff only on deviation, routing to the document
  backend when the path is a bound document); `tool-diff.R`; `tool-walk.R` (pruned walker, gitignore engine,
  glob to PCRE, Pi's `**/` prefix rule); `tool-search.R` (`gptr$grep/find/ls` with raw prefilters, radix
  sorting, early stop, 1,500-token prints).
- **Review amendments (contract §15).** P10 is the only owner of `gptr$out()` (IC-36); the gateway methods are
  P08's and P10 provides `ns.resolve`, `ns.names` and `search.sources` (IC-36, IC-69); one spec per capability for
  `read`, `edit`, `write`, `grep`, `find`, `ls` with both forms, reserved member names and required plugin
  namespaces (IC-37); `record = FALSE` for `out`, `plot`, `help`, `search`, `describe` (IC-48); the tools'
  `guidelines` for `<rules>` and the `r_session` fragments for helpers and `out` (IC-68); the `r` tool's
  `parameters` as a function giving the four schema variants (IC-68); `gptr$find(sort = "relevance")`,
  `gptr$grep(sort =)` (IC-71); `gptr$plot(which =)` (IC-67); `read` resolves `skill:<name>/<path>` pseudo-paths
  (IC-68); `edit`/`write` apply the `control` and `instructions` path classes (IC-54).
- **Owns.** The eight R files and tests; `test-copy-tools.R`.
- **Test files.** One per owned R file: `test-tool-namespace.R`, `test-tool-r.R`, `test-tool-read.R`, `test-tool-write.R`, `test-tool-edit.R`, `test-tool-diff.R`, `test-tool-walk.R`, `test-tool-search.R` (plus the extra test files named under Owns).
- **Research.** 01 §2-§4 and fact-check (Pi schemas and strings, `**/` semantics); 11 §2-§5 and fact-check;
  19 §2; 21 §2.1-2.3; G5 (gateway pattern, `gwtoy` check, budgets); G1 §2.5, §4.7-4.8; 14 §4 (record, note,
  editing blocks); P-C §4.2 and C-29; architecture §4.2, §7.1-7.2.
- **Depends on.** P09.
- **Milestone.** M2.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "tool-|copy-tools")'` is green.
  2. Pi's read/edit/write oracle cases (01) and report 11's grep/find/ls oracles pass; `find` sorts by path,
     mtime and size; grep respects `.gitignore`.
  3. `gptr$nope` errors listing the members; `.DollarNames` completion lists `read`, `grep`, `find`, `ls`,
     `help`, `search`, `describe`, `plot`, `out`; accessing a member performs no I/O.
  4. Model code `gptr$grep("x")` evaluated in an environment where `gptr` is not visible runs through the
     shim, and the recorded code keeps `gptr$grep("x")`.
  5. Value policy: a 12 MB bound object is held by name, a 200 KB one as a copy, an anonymous value boxed;
     `gptr_return(x)` outside a run returns `x` invisibly and changes nothing (IC-48); the copy rows for all three
     stay in place, as does tool code `n = 1L` and `length(d)` in `f = function(d) gptr(..., d)` (moved from P09).
  6. An edit whose `oldText` matched only through the fuzzy fallback returns the message plus a diff of at most
     400 tokens; an exact edit returns the message only.
  7. Review additions: a plugin member with `namespace = "grep"` or without a namespace is refused; `gptr$read` and
     the direct `read` tool come from one spec; `gptr$find("tst", sort = "relevance")` ranks `test.R` first; the
     `r` schema frozen without a document has no `record`/`note`; P10's NS fixture and baseline rows are added to
     `dev/bench/tokens/` (IC-73).

### P11 Permissions, UI and plan mode

- **Goal.** The permission model of architecture §6.8: modes, levels, rules, guards, UI backends, the `ask`
  tool, plan mode with the pending plan, and the non-interactive stop.
- **Scope.** `perm-classify.R` (`gptr_risk()`: R classifier of 18 with path classes and object-overwrite
  sizes, command, SQL and Python classifiers of G5, secret rules of G6, reading `inst/extdata/risk-*.csv`);
  `perm-rules.R` (rule grammar, session/project/user persistence, exposure through `gptr_permissions()`);
  `perm-gate.R` (the built-in policies: mode table, rules, critical and secret guards, protect size;
  `builtin:permissions`; the combination and the non-interactive stop are P06's `perm_check()`, contract IC-04);
  `perm-plan.R` (`readonly` preset wiring, scratch
  environment, `<proposed_plan>` capture, pending plan keyed by address string, the execute menu,
  `builtin:plan`); `console-ui.R` (UI backends `console`, `none`, `scripted`, `rstudio`; the one-line prompt
  and its detail view; `builtin:ui`); `tool-ask.R` (trimmed schema, UI mapping, `builtin:ask`).
- **Review amendments (contract §15).** Risk rows of category `control` for gptr's own configuration exports and
  options, the risky-package list, level 1 for unlisted functions of non-base packages, additive `risk_rule`
  records (IC-53, IC-54, IC-69); the plan-mode allowlist (IC-54); the `ask_human` tier and the policies'
  non-removability (IC-53); display sanitisation and the full flagged-call list in prompts (IC-53); rules
  remembered "in this project" go to the user-level project file, and a legacy `.gptr/settings.local.json` only
  tightens (IC-52); `gptr_can_prompt()` for UI resolution and the `ask` tool, `ask` declared in non-interactive
  `manual` runs and stopping the run when called (IC-43, IC-68); the pending-plan hand-off rules of IC-56.
- **Owns.** The six R files and tests; `inst/extdata/risk-functions.csv`, `inst/extdata/risk-commands.csv`;
  `helper-scripted-ui.R`.
- **Test files.** One per owned R file: `test-perm-classify.R`, `test-perm-rules.R`, `test-perm-gate.R`, `test-perm-plan.R`, `test-console-ui.R`, `test-tool-ask.R` (plus the extra test files named under Owns).
- **Research.** 18 §2-§4 and fact-check (critical paths list); G5 §5 and fact-check 20 (edits parity); G6 §3.8
  (secret guard); 10a INFRA-11; 20 §2.11 (proposed plan); P-A §6.7; P-C §9.3-9.4; architecture §6.8.
- **Depends on.** P10.
- **Milestone.** M2.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "perm|console-ui|tool-ask")'` is green.
  2. 18's 101 classifier cases and 11-row mode x risk matrix pass; a throwing policy denies; `modify` changes
     the arguments and is recorded; allow rules never loosen plan or pre-approve level 4.
  3. Non-interactive: an action needing approval stops the run with status `blocked` and
     `gptr_error_permission` naming the action and how to allow it; with
     `options(gptr.noninteractive_ask = "deny")` the model receives a denial result instead.
  4. Plan mode on the fake provider: a write is denied, level-1 R runs in the scratch environment and its
     assignments do not persist, the `<proposed_plan>` is saved, and the next non-plan call in the same
     environment receives `<plan>` exactly once; the pending-plan store holds no environment reference (copy
     row).
  5. The scripted UI answers `[a]lways`, producing a session rule that covers exactly the flagged calls.
  6. Review additions: 18 §2.5's blind-spot cases get the new levels (`targets::tar_destroy()` >= 2,
     `usethis::create_package(".")` >= 2) and are denied in plan mode; in `manual` and `plan`, model code calling
     `gptr_permissions(allow =)`, `gptr_trust(".", TRUE)`, `gptr_register(gptr_hook("permission_request", ...))`,
     `options(gptr.critical_guard = FALSE)` or writing `.gptr/extensions/x.R` needs a human (`blocked` without one);
     an ESC or bidi payload in code is escaped in the prompt; a cloned fixture with `settings.local.json` allow
     rules and an AGENTS.md instruction still asks; the pending plan is not handed to a call inside a loop or to a
     call after an intervening `gptr()`; with `jupyter.in_kernel = TRUE` mocked and a mocked `gptr_readline()`, an
     ask is answered.

### P12 Native provider adapters

- **Goal.** The four native wire adapters with byte-exact round trips and conformance fixtures (REQ-11).
- **Scope.** `provider-anthropic.R`, `provider-openai-responses.R`, `provider-openai-completions.R` (with the
  compat flags of 09 §3 and a streaming `<think>` splitter), `provider-google.R`; each registers its adapter
  through its own `builtin_<name>()`; request bodies follow the cache plans of `prompt-cache.R` (G4 §3.7) and
  `.opts$returns` structured output (INFRA-25); wire fixtures under `tests/testthat/fixtures/sse/`; gated live
  tests.
- **Review amendments (contract §15).** The adapter capability `forced_tool_choice` (`FALSE` for Anthropic 5.x);
  `returns =` through `output_config.format` on Anthropic, else `auto` + instruction + validation; declared
  `request_params` fields; `check_adapter()` fails a list `tool_choice` sent while the capability is `FALSE`
  (IC-69, IC-71).
- **Owns.** The four R files and tests; `fixtures/sse/`; `test-live-anthropic.R`, `test-live-openai.R`,
  `test-live-google.R`.
- **Test files.** One per owned R file: `test-provider-anthropic.R`, `test-provider-openai-responses.R`, `test-provider-openai-completions.R`, `test-provider-google.R` (plus the extra test files named under Owns).
- **Research.** 07 §2-§5 and fact-check (tool-name regex, mid-conversation system messages, oauth beta,
  UTF-8 marking); 08 §3 and fact-check (encrypted reasoning backfill, `phase`, request ids); 09 §2-§4 and
  fact-check (Gemini signatures, compat flags); 03 §3-§5; 10a INFRA-02, 07, 08, 25; G4 §3.7;
  architecture §8.1.
- **Depends on.** P05, P07.
- **Milestone.** M2.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "provider-(anthropic|openai|google)")'` is green; live
     tests skip unless `GPTR_LIVE_TESTS=true`.
  2. `gptr_check()` passes for each adapter: golden event sequences per fixture; a server error event and a
     truncated connection each give exactly one `error` event with the partial; chunk invariance; byte-identical
     re-serialisation of thinking + signature + redacted thinking + parallel tool use (Anthropic), encrypted
     reasoning with `fc_`/`call_` ids (Responses), thought signatures (Gemini).
  3. A PNG tool result is sent as a native image block to Anthropic and Responses.
  4. Request bodies place breakpoints as in G4 §3.7 and keep the frozen prefix byte-identical across turns.
  5. With `.opts$returns`, a run with tool calls yields a typed `$value` and a transcript that still holds the
     tool calls (INFRA-25).
  6. End-to-end on the mock server (skip on CRAN): streaming, retry and abort through the reactor.

### P13 System 1

- **Goal.** Typed, vectorised System 1 decisions usable inside `if`, `for` and `while` (REQ-20, INFRA-18).
- **Scope.** `s1-types.R` (the three classes and methods of architecture §5.6; delayed vctrs methods;
  `gptr_prob()`, moved from P08, IC-36);
  `s1-client.R` (the `typesafe-system-one` adapter, question building with wire `noul`, concurrent requests on
  the reactor with at most 8 active and 3 bounded rounds, `builtin:system1` registering providers and the
  classifier route); `s1-route.R` (batch rule, `as_state()` for piped sessions with a `gptr.decision` entry,
  threshold, `min_confidence`/`uncertain` including function escalation, logical-label rejection, top-level
  one-line document summary through the `doc.s1_block` service); `s1-cache.R` (per-element cache, memory before
  init, salted input hash and question hash only, IC-70); `s1-emulate.R` (opt-in emulation through structured
  output, uncalibrated flag).
- **Review amendments (contract §15).** `gptr_prob()` and its example (IC-36); the `system1` prompt section
  (IC-68); `inst/gptr/examples/jev-router.R` with its test (IC-69); the typesafe record's static `rate` and
  process-wide admission (IC-64); `gptr.s1_max_elements` (IC-66); the `s1_split` message instead of the `s1_batch`
  error (IC-71); S1 cache schema 2 with the committed salt (IC-70); System 1 calls inside recorded blocks use the
  cache and error `not_recorded` on a miss under `replay` (IC-47).
- **Owns.** The five R files and tests; `fixtures/jev/`; `test-copy-s1.R`; `test-live-jev.R`;
  `inst/gptr/examples/jev-router.R`.
- **Test files.** One per owned R file: `test-s1-types.R`, `test-s1-client.R`, `test-s1-route.R`, `test-s1-cache.R`, `test-s1-emulate.R` (plus the extra test files named under Owns).
- **Research.** 04 §2-§4 and fact-check; 04a (wire names, reordered probabilities); 10a INFRA-18; G3 (12);
  14 §3.5; 13 (egress); architecture §4.1.5, §8.2.
- **Depends on.** P08, P09 (`describe_binding()` for non-character states, contract §7.13), P12.
- **Milestone.** M2.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "s1-|copy-s1")'` is green; the live test skips unless
     `GPTR_LIVE_TESTS=true` and reads the key only through `gptr_env()`.
  2. Against a mocked `/systemone`: `if (gptr("q", x, model = jev))` works; a 100-element vector issues
     concurrent requests never exceeding 8 active; cached elements make zero requests; `choices` returns a
     classed character whose `==` gives a plain logical; `choices = factor(...)` returns a factor; a label
     `"TRUE"` is rejected; `min_confidence` with `uncertain = NA`, `"stop"` and a function behave as
     specified; splitting a data frame into several states prints the once-per-session `s1_split` message naming
     `I()` (a function cannot see that it is a condition; IC-71).
  3. `s |> gptr("done?", model = jev)` adds no turn and appends a `gptr.decision` entry; the state sent is at
     most 2,000 characters.
  4. Emulation never happens without `gptr_config(system1 = "emulate:<model>")`.
  4b. Review additions: the `gptr_prob()` example runs; a fake-classifier router loaded from the example switches
     models after the first successful `edit`, with exactly one `model_change`; 100 concurrent System 1 states never
     exceed 40 requests per second; the S1 cache files contain neither the input nor the question text; P13's NS
     fixtures are added to `dev/bench/tokens/` (IC-73).
  5. **M2 exit** (once P09-P13 are complete): the NS-2, NS-3, NS-4 and NS-5 shapes pass in the plans' own
     tests on the fake provider and mocks; `devtools::check(args = c("--as-cran", "--no-manual"),
     error_on = "warning")` clean on the CI matrix.

---

## M3 Interactive, recorded, reversible

### P14 Console and front ends

- **Goal.** The interactive face of `gptr()` (REQ-16, REQ-38) and the event-driven front ends (INFRA-27).
- **Scope.** `console-repl.R` (the `console` frontend: `readline()` or one persistent `file("stdin")` under
  `.stdin = TRUE`, input grammar of architecture §6.17, long-line warning, optional `timestamp()` history,
  banner, route "no prompt" registration, `builtin:console`); `console-render.R` (chunk-invariant markdown
  stream renderer, tool lines, status line, spinner ticked from the reactor, verbosity levels, rule C1:
  `cli_verbatim()` for untrusted text); `console-interrupt.R` (pause menu through the `resume` restart with
  steer, follow-up, continue, abort, background; second Ctrl-C aborts; menu on stderr; abort-only fallback);
  `console-commands.R` (the slash commands of §6.17 as `command` specs, templates as `/<name>`);
  `console-jsonl.R` (the `jsonl` frontend: redacted Pi-named events on a connection).
- **Review amendments (contract §15).** The renderer prints the NS-8 artifact line on `artifact_start` and uses
  tool `render` functions and `renderer` records (IC-69, IC-71); approval displays are sanitised and list every
  flagged call (IC-53); the `console` route and the REPL use `gptr_can_prompt()` (IC-43); the pause-menu steer and
  follow-up enter the queue with `source = "pause_menu"` and are recorded as `## Steer:`/`## Follow-up:` lines by
  P15 (IC-49, IC-55); asks of background runs are shown at the next blocking call (IC-57); `!expr` notes within
  300 tokens (IC-73); the `.stdin` connection closes on `/exit` and on exit (IC-59); `frontend` selectable by
  setting (IC-69).
- **Owns.** The five R files and tests.
- **Test files.** One per owned R file: `test-console-repl.R`, `test-console-render.R`, `test-console-interrupt.R`, `test-console-commands.R`, `test-console-jsonl.R` (plus the extra test files named under Owns).
- **Research.** 18 §2-§4, Appendix A and fact-check (readline limits, UTF-8 locale for width); 02 §5.4-5.5; G3
  (5) and t9 (menu fixes); 10a INFRA-03, 27; 13 C-36, C-46; architecture §6.2, §6.17.
- **Depends on.** P08, P11.
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "console")'` is green (SIGINT tests skip on CRAN).
  2. Through `gptr(.stdin = TRUE)` with a scripted UI: a prompt, `!dim(x)` (added to the next prompt's
     context), `!!x` (not added), `/mode auto` (mode entry at the next turn), `"""` multi-line input and `/exit`
     returning the session invisibly.
  3. The renderer gives identical output over 200 random chunkings (UTF-8 locale); a reply containing
     `{Sys.setenv(GPTR_PWNED = "1")}` is printed verbatim and nothing is evaluated.
  4. INFRA-27: the same fake-provider run gives byte-identical JSONL transcripts at verbosity 0, 1 and 2.
  5. INFRA-03 (processx-driven `R --interactive`, CI only): SIGINT during TTFT then "continue" completes the
     request; mid-tool "steer" delivers after the tool result; "abort" closes the mock socket and the partial
     equals what was received.
  6. The JSONL sink contains no registered secret (fake key).
  7. Review additions: `artifact_start` prints `artifact  <id>  ->  <url>   (running in background)`; an ESC
     sequence in a tool preview is escaped; with `jupyter.in_kernel = TRUE` mocked, `gptr()` with no prompt starts the
     console on a mocked `gptr_readline()`.

### P15 Documents and replay

- **Goal.** The script is the harness and the history (REQ-24-26).
- **Scope.** `doc-locate.R` (precedence of architecture §6.9.3; content matching; `source()` frame reads in
  `tryCatch` with an off switch); `doc-blocks.R` (block grammar incl. `session`, `turn`, `value`, `fork`,
  `plan`, `status=undone`; ownership; idempotent upsert; stale and user-edited detection); `doc-io.R` (raw-byte
  atomic writes preserving EOL/BOM, md5 conflict checks with re-locate and retry, deferred Rscript writes with
  a sidecar, rstudioapi and Positron backends, never writing an open notebook); `doc-formats.R` (`r`, `rmd`,
  `qmd`, `ipynb` with gptr's serializer, `transcript`; `builtin:documents` with the `document_write` event and
  the gateway's "document" route); `doc-replay.R` (replay decisions per mode (the mode itself comes from P08's
  `replay_mode()`, which also forces replay under check), the S2 cache,
  `gptr_doc()`, `gptr_source()`, `gptr_blocks()`, `gptr_cache()`, the console-transcript target question);
  `doc-knitr.R` (`knit_print` methods for sessions and System 1 vectors registered lazily, the scoped label
  hook for regeneration).
- **Review amendments (contract §15).** The route matches a top-level call located in a document that holds a block
  for it, and replay needs no consent; write consent (`gptr_doc()` for every call of the process, the `record`
  option or user setting, an interactive yes) is checked only in `doc_upsert()` (IC-45); the `args=` header key and
  S2 key (IC-45); replay in place for piped sessions, replayed sessions from the JSONL or reconstructed from the
  document, fork blocks bound by block id and wrapped with `gptr_resume(block =)` (IC-46); team and fan-out blocks
  and block-nested calls replayed from S2 (IC-47); dropping top-level `gptr_return()` and `record = FALSE` member
  calls, the best-effort `<-` rewrite, no recording in plan mode (IC-48); console transcripts as pipe chains and
  `## Steer:`/`## Follow-up:` lines (IC-49); Jupyter pending blocks and `gptr_doc(sync = TRUE)` (IC-50); the
  sidecar of block upserts with recovery, rename retries with an in-place fallback, `path_key()` matching (IC-51);
  transcript targets validated and stored in the user-level project file (IC-52); forced replay only outside
  testthat (IC-45); the `documents` prompt section and services owned by `builtin:documents`, including
  `doc.replay` for the team and fan-out routes (IC-68, IC-34, IC-47).
- **Owns.** The six R files and tests; `fixtures/docs/`.
- **Test files.** One per owned R file: `test-doc-locate.R`, `test-doc-blocks.R`, `test-doc-io.R`, `test-doc-formats.R`, `test-doc-replay.R`, `test-doc-knitr.R` (plus the extra test files named under Owns).
- **Research.** 14 (all) and fact-check (ipynb floats, radix keys, grey zone); G3 (11) (keys, overlay-fork
  replay); G7 (inert blocks); 13 §2.4 (write consent); architecture §6.9.
- **Depends on.** P08, P10.
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "doc-")'` is green (knitr/Quarto/IDE cases skip when
     unavailable).
  2. Report 14's prototypes pass as tests: record then replay under `source()` with zero model calls;
     `keep.source = FALSE`; an Rscript run writes its blocks only at exit (sidecar survives a crash); a stale
     prompt regenerated through `gptr_source(replay = "record")` without executing the old block; CRLF, BOM and
     missing final newline preserved; a concurrent edit detected by md5; `.Random.seed` unchanged; knitr and
     Quarto record/replay; a Python-written ipynb round-trips byte for byte.
  3. With `_R_CHECK_PACKAGE_NAME_` set and `TESTTHAT` unset, replay is forced; with `TESTTHAT=true` it is not;
     with `GPTR_REPLAY=replay`, a call nested in a loop raises `gptr_error_not_recorded`.
  4. Replay of a block with `value=markers` yields a session whose `$value` resolves `markers` by name; no
     generated document contains a `$value =` line.
  5. No document is written without `gptr_doc()`, `options(gptr.record = "auto")` or user-scope `record =
     "auto"`, or an interactive yes; a project `record = "auto"` is ignored (tighten-only); a fresh clone without
     any consent replays with zero model calls and executes no block twice (IC-45).
  6. Review additions: a block whose code called `gptr_return(fit)` and `gptr$out("o1")` re-sources cleanly under
     `source()` and Rscript and `$value` resolves `fit` (IC-48); re-sourcing NS-3 twice leaves the main-line
     `qc_flags` and `qc$value` unchanged and the fork's objects only in its overlay (IC-46); a replayed pipe chain
     returns one object; in a fresh clone without `sessions/` a continuation replays from the reconstructed history;
     a parameterised document rendered with two values of `{gene}` does not replay the first block for the second
     (IC-45); a two-turn console session plus one menu steer produces a transcript that re-sources as one session
     (IC-49); a plan-mode run records no code; a block containing a nested sub-agent call (the `nested` route)
     replays under `GPTR_REPLAY=replay` with zero requests (IC-47; NS-6's team block is P19's acceptance 6); an Rscript run killed with SIGTERM after two calls
     leaves a sidecar whose upserts the next run applies without overwriting user edits (IC-51); a notebook is
     never written while `jupyter.in_kernel` is mocked, and `gptr_doc(path, sync = TRUE)` applies its pending
     blocks (IC-50); P15's NS-7 fixture is added to `dev/bench/tokens/` (IC-73).

### P16 Checkpoints and rewind

- **Goal.** Reversible agent actions without copying user objects (G7).
- **Scope.** `ckpt-objects.R` (pre-images as private-environment bindings released with `rm()`, defusing of
  list and S4 pre-images, capture policy and budgets of architecture §6.16, eager disk images with
  `serialize(ascii = FALSE, xdr = FALSE)`, data.table deep copies, settle); `ckpt-files.R` (content-addressed
  store with XXH128, baseline and pruned walk, 3-way restore, symlink and `.git` guards); `ckpt-rewind.R`
  (`gptr.checkpoint` and `gptr.rewind` entries, `gptr_rewind()`, `gptr_checkpoints()`, `/undo`, `/redo`,
  `/rewind`, `/checkpoints` commands, `builtin:checkpoints` registering the `checkpointer` kind's built-ins for
  objects, files and state, and the exported `gptr_preimage()` S3 generic, contract IC-01).
- **Review amendments (contract §15).** File restores stay inside the project root and `tempdir()` unless the user
  confirms each outside path (`ask_human`, IC-52); blob garbage collection keeps blobs referenced by any session
  file of the project and skips while another live pid holds a session lock (IC-71); after a Codex
  `workspace-write` exec the files checkpointer walks, so `/undo` covers it (IC-65).
- **Owns.** The three R files and tests; `test-copy-ckpt.R`.
- **Test files.** One per owned R file: `test-ckpt-objects.R`, `test-ckpt-files.R`, `test-ckpt-rewind.R` (plus the extra test files named under Owns).
- **Research.** G7 (all) and fact-check (timing ranges, rm() path, hash speed); architecture §6.16.
- **Depends on.** P11, P15.
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "ckpt|copy-ckpt")'` is green.
  2. G7's 24-verdict tracemem matrix reproduces (including c03: a dropped pre-image leaves no sticky reference,
     and the serialize case).
  3. `gptr_rewind(s, 1)` after three mutating turns restores objects and files, appends one `gptr.rewind` entry,
     leaves the JSONL byte-append-only and the next request's prefix byte-identical; a user edit made after the
     turn survives the 3-way restore; a partial restore warns `gptr_warning_rewind_partial`; a running session
     errors `gptr_error_busy`.
  4. Undone blocks in a bound document become inert (`#~ `, `status=undone`) and re-sourcing reproduces the
     rewound workspace.
  5. Review additions: a checkpoint record whose path lies outside the project is not restored without a human;
     pruning in one process does not delete a blob another live session references.

### P17 Skills, templates, agent files and plugins

- **Goal.** Declarative extensibility: skills, prompt templates, agent definitions and plugin packages or
  directories (REQ-28, REQ-29, REQ-31).
- **Scope.** `skill-discover.R` (discovery from `.gptr/skills`, user directories, `~/.agents/skills` style
  locations, attached packages' `inst/gptr/skills` and `inst/skills`; lenient frontmatter with yaml; the
  compact catalog within 1,500 tokens with least-recently-used trimming; activation through `read`;
  `skills =` preloading; `gptr_skills()`; `builtin:skills`); `skill-templates.R` (Pi's template grammar,
  `/name args`, `builtin:prompts`); `subagent-defs.R` (agent files from `.gptr`, `.claude`, `.codex` (md) and
  `.pi` agent directories with Claude-compatible frontmatter, tool-name map with Bash and PowerShell -> `r`,
  `gptr_agents()`, `builtin:agents`); `ext-plugins.R` (plugin packages via `Config/gptr/plugin` and
  `inst/gptr/plugin.json`, plugin directories, `.claude-plugin` bundles for skills, commands, agents and MCP,
  trust gating of project plugin code, `gptr_plugins()`); `inst/gptr/plugin.json`,
  `inst/gptr/skills/high-performance-r/`, `inst/gptr/prompts/review.md`, `explain.md`.
- **Review amendments (contract §15).** Name normalisation for skills, plugins, extensions and agents (IC-42);
  untrusted project skills and agents are listed but not catalogued, and omitted non-interactively in `auto`/
  `edits` (IC-52); `[skill:<name>/SKILL.md]` pseudo-paths in the catalog (IC-68); string frontmatter keys keep
  their source text against YAML 1.1 coercion (IC-71); user and foreign-harness directories through
  `user_home()`/`app_config_dir()` (IC-63); plugins and extensions enabled for a call are scoped to that session
  (IC-69); the high-performance-r skill says `str()` copies large objects (IC-67).
- **Owns.** The four R files and tests; `fixtures/oracles/pi-templates/`; the `inst/gptr/` files listed.
- **Test files.** One per owned R file: `test-skill-discover.R`, `test-skill-templates.R`, `test-subagent-defs.R`, `test-ext-plugins.R` (plus the extra test files named under Owns).
- **Research.** 05 §2-§4 and fact-check; 16 §2-§4.9 (skills, plugins, `.claude-plugin`, trust); G1 §4.4 and the
  toy packages; 19 §3 (skill content); 20 §4.4 (agent files); 15 §4.3 (agent loader); G2 (b) (compact
  catalog); architecture §11.
- **Depends on.** P08, P10 (the `plugins` section, `ns_catalog()` and activation through `read`; IC-36).
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "skill|subagent-defs|ext-plugins")'` is green.
  2. Pi's 67 template tests pass; the 37-skill corpus of report 05 parses completely, including folded
     scalars.
  3. A toy plugin package installed into a temporary library (G1's `gptrpanel` shape) is discovered, its
     tool signature appears in the frozen prompt through `declarations` before activation, and its factory
     runs on first use; a failing factory rolls back and is reported in `gptr_registry(diagnostics = TRUE)`.
  4. A `.claude-plugin` fixture contributes a skill, a command, an agent and an MCP entry; project plugin code
     is ignored until `gptr_trust()`.
  4b. Review additions: `skills = single_cell` resolves to `single-cell` and `skills = high_performance_r` to the
     built-in; a SKILL.md with `name: on` and `version: 1.0` keeps both as strings; a plugin passed with `plugins =`
     is invisible to the next `gptr()` call; an untrusted project's skill is not in the catalog.
  5. **M3 exit** (once P14-P17 are complete): NS-1 through the scripted console (P14), NS-7 in `.R`, Rmd, qmd and ipynb (P15), `/undo`
     and rewind (P16), NS-10 skills and plugins and NS-12 (P11) all pass on the fake provider;
     `devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")` clean.

---

## M4 Interop and scale-out

### P18 MCP and OAuth

- **Goal.** Harness-agnostic MCP (REQ-30) as a client of both protocol eras and as a server exposing the live
  session, plus OAuth and credential login.
- **Scope.** `mcp-client.R` (era probe and cache, stdio through the process engine and HTTP on the reactor,
  pagination, progress, cancel, MRTR at most 5 rounds, elicitation to the ask UI); `mcp-config.R` (gptr's
  `mcp.json` at user and trusted-project level, read-only listing and on-request import of Claude Code, Claude
  Desktop, Codex (TOML subset), Cursor, VS Code and Pi configs, `gptr_mcp()`, `gptr_mcp_add()`,
  `gptr_mcp_remove()`); `mcp-namespace.R` (`gptr$mcp$<server>$<tool>()` closures with lazy connect, the T1
  `<mcp>` catalog within 1,500 tokens, per-tool exposure, `builtin:mcp`); `mcp-server.R` (dispatcher over
  `r`, `read`, `edit`, `write` through the permission gate; the claude `sdk` transport helpers; loopback
  Streamable HTTP with bearer token and Origin validation; `gptr_mcp_serve()`); `auth-oauth.R` (PKCE S256,
  loopback or paste callback, locked refresh, RFC 9728 discovery for MCP, `gptr_login()`, `gptr_logout()`).
- **Review amendments (contract §15).** One listening socket with a bearer token per client bound to its session
  (evaluation environment, mode, rules, budget) through `mcp.serve_ensure(session)` (IC-58); requests served only
  by the outermost pump or at an idle console, a busy JSON-RPC error for other sessions in a nested pump, denial
  instead of prompts from callbacks (IC-57); ports from `port_candidates()` (IC-61); stderr read and redacted, logs
  in `tempdir()` unless `gptr.mcp_debug` (IC-70); OAuth refuses metadata without S256 PKCE and validates `iss`
  (IC-71); foreign-harness configs and `${userHome}` through `user_home()`/`app_config_dir()` (IC-63); the
  fixture server's HTTP transport binds 127.0.0.1 through httpuv (IC-71); `mcp_dispatch_local()` is the single gate
  for the claude route (IC-65); `followlocation = 0L` on MCP HTTP (IC-64).
- **Owns.** The five R files and tests; `helper-mcp-server.R`; `fixtures/mcp/`.
- **Test files.** One per owned R file: `test-mcp-client.R`, `test-mcp-config.R`, `test-mcp-namespace.R`, `test-mcp-server.R`, `test-auth-oauth.R` (plus the extra test files named under Owns).
- **Research.** 16 (all) and fact-check; 06 §4 (MCP as code); 07 §2.13-2.16 and fact-check (sdk transport,
  60 s per-request timer); 08 (in-session HTTP MCP with Codex); G1 §2.5; G6 §4 (tokens in the store); 03 §5
  (PKCE); 13 C-42/C-43 (ports); architecture §6.14.
- **Depends on.** P10, P11.
- **Milestone.** M4.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "mcp|auth-oauth")'` is green (server and OAuth tests skip
     without httpuv/later/openssl and on CRAN).
  2. The fixture server in each era: probe then fallback, era cached, tools listed and called over stdio and
     HTTP, a progress notification re-arms the idle timer, an interrupt sends `notifications/cancelled`, an
     `input_required` round is answered through the scripted UI.
  3. `gptr$mcp$fixture$echo(text = "x")` inside `r` passes the gate as a nested call and returns an R value; the
     `<mcp>` catalog stays within budget with 125 fixture tools and `gptr$search()` finds the rest.
  4. `gptr_mcp_serve()`: requests without the token get 401, a foreign Origin is rejected, the server binds
     127.0.0.1 only, and an `r` call through it is gated.
  5. OAuth against a mock authorization server: PKCE S256 exchange, refresh under a lock, tokens only in the
     store (0600) and in memory; a tool call never opens a browser.
  6. A `.cmd` MCP command is launched through `cmd.exe /d /c call` on Windows CI.
  7. Review additions: an `r` call from a CLI child of a fork evaluates in the fork's overlay, and one from a
     child of a plan-mode parent is gated in plan mode; OAuth mock servers without `code_challenge_methods_supported`
     or with a wrong `iss` are refused; a Windows CI test plants `.claude.json` under a fake `USERPROFILE` and
     `gptr_mcp()` lists it; `.Random.seed` is unchanged by `gptr_mcp_serve()`; an MCP server's stderr containing a
     registered fake key is persisted redacted; P18's NS-10 fixture is added to `dev/bench/tokens/` (IC-73).

### P19 Sub-agents

- **Goal.** Sub-agents in parallel and across providers, sharing memory without copies (REQ-32-35).
- **Scope.** `subagent-backends.R` (`inline`, `worker`, `cli` backends as `backend` specs with the `auto` rule
  and limits of architecture §6.13, `builtin:subagents`, routes "team" and "fanout"); `subagent-team.R`
  (`agents =` data mask, team and fan-out sessions, `<agent_reports>`, usage roll-up, `gptr_parallel()`, the
  internal `gptr_map()` behind `parallel =`); `subagent-worker.R` (`worker_main()` for callr children: spec file in, JSONL events out,
  permission and ask forwarding, exports); `inst/gptr/skills/gptr-orchestration/`,
  `inst/gptr/agents/reviewer.md`, `explorer.md`.
- **Review amendments (contract §15).** Routes `team` (15) and `fanout` (16) precede `nested`, with nesting
  inherited inside a run; `max_tasks` only for model-issued teams and fan-outs, user fan-outs queue every element
  (IC-39); `gptr_map()` internal (IC-36); the worker spec carries the session's registry records, plugins and
  filters (IC-69); workers start with `supervise_default()`, `encoding = "UTF-8"`, `child_env_callr()` and exit on
  parent death (IC-60); the parent re-classifies forwarded permission requests (IC-53); child pools capped at 2 under
  check (IC-60); budgets charged to the root (IC-66); `rng_swap()` states for inline children (IC-61); team and
  fan-out session data P15 needs for their document blocks, and the `doc.replay` service call that lets the team
  and fan-out routes replay a fresh block (IC-47); the sub-agent `r_session` fragment (IC-68);
  the `cli` backend's tests move to P20 (IC-36).
- **Owns.** The three R files and tests; `test-copy-subagent.R`; the `inst/gptr/` files listed.
- **Test files.** One per owned R file: `test-subagent-backends.R`, `test-subagent-team.R`, `test-subagent-worker.R` (plus the extra test files named under Owns).
- **Research.** 15 (all) and fact-check; 06 §2-§3; G6 fact-check (callr environ); 13 C-40; P-A §6.12; P-C
  §4.1.6; architecture §4.1.6, §6.13.
- **Depends on.** P11, P14 (the `jsonl` frontend that worker children write, contract §7.14), P15 (acceptance 6
  replays NS-6 from its team block through the `doc.replay` service, IC-47), P17.
- **Milestone.** M4.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "subagent|copy-subagent")'` is green (worker tests skip on
     CRAN).
  2. INFRA-16 shape: two inline fake agents and two workers interleave on one reactor within about the slowest
     agent's wall time; R tools never overlap (the fake-CLI leg is P20's acceptance 2, IC-36).
  3. Team and fan-out results are sessions: `res$stats` is a child session, `res$text` joins reports,
     `res |> gptr("...")` continues the team with `<agent_reports>`.
  4. Inline children read a 40 MB parent object at the same address with no copy (copy row) and their writes
     stay in the overlay; code with `<<-` is denied in parallel runs.
  5. A worker started with a fake key in a temporary `~/.Renviron` does not see it; at most 2 workers run when
     `_R_CHECK_PACKAGE_NAME_` is set; `gptr_cancel()` leaves no process.
  6. Review additions: `gptr("Summarise", x, parallel = 4)` over 20 elements runs all 20, four at a time; a team
     and a fan-out started inside an `r` evaluation become children of the running session; a plugin `r` member and
     a `gptr_fake_provider()` spec work inside a worker; an inline agent calling System 1 while a sibling has a
     queued tool does not run the sibling's tool inside its evaluation (IC-57); a worker whose parent is killed exits
     within 10 s; NS-6 replays with zero requests from its team block (with P15); P19's NS-6 fixture is added to
     `dev/bench/tokens/` (IC-73).

### P20 Subscription CLI providers

- **Goal.** Use the user's Claude plan through the claude CLI and the ChatGPT plan through the Codex CLI, with
  live R access (REQ-12, INFRA-19).
- **Scope.** `cli-common.R` (discovery through `gptr.cli_path`, PATH and known install locations, native
  binaries only for claude (the `claude.cmd` shim refused), minimum-version and capability probes, one-time notice,
  billing-switch scrub with warning, cached `status()` data, `builtin:cli`; IC-65); `cli-claude.R` (the flags of architecture §8.3, stream-json
  input/output, control protocol, in-process `sdk` MCP via `mcp-server.R`, `can_use_tool` through
  `perm_check()`, interrupt, session continuity, usage as plan estimate); `cli-codex.R` (`codex exec --json
  --ignore-user-config` with MCP `-c` overrides pointing at `gptr_mcp_serve()`, prompt on stdin via
  `write_all()`, sandbox mapping, resume when supported, overhead notice); `inst/gptr/fixtures/fake_cli.R`;
  `fixtures/cli/`; gated live test.
- **Review amendments (contract §15).** claude argv with `--permission-mode default`, `--allowedTools
  mcp__gptr__*` and, under a budget, `--max-turns`/`--max-budget-usd`; one gate through `opts$mcp_dispatch`;
  `opts$gate` for other `can_use_tool` requests; the `--bare` probe; the `apiKeySource` check and
  `gptr_error_billing`; G6 §3.7 environment lists; codex argv with `--skip-git-repo-check`, `-m`, `-C`,
  `default_tools_approval_mode="approve"`, `required=true`, resume with `-c sandbox_mode=`; sandbox mapping
  plan/manual/edits -> read-only, auto -> workspace-write with control-file hashing and a checkpointer walk; the
  Windows sandbox probe; the turn counter and `gptr.cli_turn_timeout`; per-session wire logs; per-session MCP tokens
  (IC-58, IC-65, IC-66); fake CLIs run through `rscript_path()` with `offline = TRUE` records (IC-60, IC-45); the
  CLI leg of INFRA-16 (IC-36).
- **Owns.** The three R files and tests; `inst/gptr/fixtures/fake_cli.R`; `fixtures/cli/`; `test-live-cli.R`.
- **Test files.** One per owned R file: `test-cli-common.R`, `test-cli-claude.R`, `test-cli-codex.R` (plus the extra test files named under Owns).
- **Research.** 07 §2.13-§4 and fact-check; 08 §2.E-F, §4-§5 and fact-check (`--ignore-user-config`,
  `write_input()` truncation); 15 §2.9, §5.15; G6 (billing variables and precedence); 16 (sdk transport);
  architecture §8.3.
- **Depends on.** P12 (the Anthropic normaliser reused for `stream_event` lines, contract §7.12), P18, P19.
- **Milestone.** M4.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "cli-")'` is green; the live test skips unless
     `GPTR_LIVE_TESTS=true`.
  2. With the fake CLI: the claude argv equals §8.3 exactly; an `mcp_message` round trip evaluates R in the live
     session and is gated once (no second prompt from `can_use_tool`); a Ctrl-C sends the interrupt control request
     then `kill_all()`; three concurrent fake-CLI agents stream into the reactor and an abort leaves no process tree
     (INFRA-19); usage fields are populated; a fake CLI joins two inline agents and two workers on one reactor
     within about the slowest agent's wall time (the INFRA-16 CLI leg, IC-36); an `init` line with
     `apiKeySource: "ANTHROPIC_API_KEY"` aborts the turn with `gptr_error_billing`.
  3. The codex invocation passes `--skip-git-repo-check`, `-m <full id>`, `-C`, the MCP overrides including
     `default_tools_approval_mode="approve"` and `required=true`, and a 50 KB prompt on stdin intact; the resume
     form uses `-c sandbox_mode=`; `edits` maps to `read-only`; `ANTHROPIC_API_KEY`, `ANTHROPIC_PROFILE`,
     `CLAUDECODE`, `OPENAI_API_KEY`, `CODEX_API_KEY` and `CODEX_SANDBOX` are absent from the children's environment and
     a warning names the billing ones; `gptr_providers()` spawns no process with `check = FALSE`; a `.cmd` fake claude
     is refused with the install hint; the gated live test runs Codex in a non-git temporary directory and requires a
     call of the gptr `r` tool.
  4. **M4 exit** (once P18-P21 are complete): NS-6 (two inline fakes, one worker and fake codex on one reactor), NS-9
     (`gptr_config(model = sonnet, mode = manual)` writing project defaults after `gptr_init()`, and
     `gptr_providers(check = TRUE)` with the fake CLIs) and NS-10 MCP pass; `devtools::check(args =
     c("--as-cran", "--no-manual"), error_on = "warning")` clean.

### P21 Background sessions (experimental)

- **Goal.** Console pipe-steering of a running session (S-8) through `gptr(..., background = TRUE)`.
- **Scope.** `agent-background.R`: registration of a running session with a `later`-driven pump (50 ms timer
  polling, no `later_fd`; a no-op while the reactor is on the stack, IC-57), idle-tick execution of R tools
  (`gptr.background_tools = "idle" | "wait"`, with a notice when a tool changed user bindings at an idle tick),
  asks moving the session to `waiting` until the next blocking gptr call (IC-57), the pause menu's
  `[b]ackground` option, session rows in the job table that P04's `gptr_jobs()` lists (IC-36), cleanup in
  `.onUnload`; documentation of the support matrix and the experimental status.
- **Owns.** `agent-background.R` and its test.
- **Test files.** One per owned R file: `test-agent-background.R` (plus the extra test files named under Owns).
- **Research.** G3 (5), t8, t9, p6; 15 §2.5 and verifier (later and processx pipes on Windows); 10a INFRA-16;
  architecture §6.2.
- **Depends on.** P06, P14.
- **Milestone.** M4.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'` is green; tests skip without later
     and on CRAN.
  2. A background run on the fake provider progresses while the test pumps `later::run_now()`; `s |> gptr("x")`
     returns invisibly at once and the steer is delivered after the current tool result; `gptr_wait(s)` settles
     it; `gptr_cancel(s)` aborts it; an unreferenced settled background session is collected.
  3. `background = TRUE` without later errors with `gptr_error_missing_package`; it is never used in examples.

---

## M5 Polyglot, apps, measured release

### P22 Polyglot bridges

- **Goal.** R as token-efficient glue for shell programs, scripts, Python, SQL and knitr engines, with no shell
  tool (S-4, REQ-42).
- **Scope.** `bridge-sh.R` (`gptr$sh`, `gptr$script`, `gptr$bg`, `gptr$jobs` on the process engine (`gptr$out` is
  P10's, IC-36);
  the `interpreter` kind registered through `kind` and the built-in interpreters; budgeted head+tail prints;
  `bridge_call` events and `#>` digests; `builtin:bridges`); `bridge-lang.R` (`gptr$py` with reticulate's
  persistent `__main__` and uv-provisioning guard, `gptr$sql` with duckdb registration or the DBI connection in
  scope, `gptr$knit` for other engines, whose shell engines run through `gptr$sh()` with the `helper` environment
  and a timeout (IC-67); `builtin:lang`).
- **Review amendments (contract §15).** The shell and languages `r_session` fragments (IC-68); bridge children
  through `proc_spawn()` with `encoding = "UTF-8"`, the complete `helper` environment and non-blocking stdin
  (IC-60); the pool cap of 2 under check (IC-60).
- **Owns.** The two R files and tests; `test-copy-bridge.R`.
- **Test files.** One per owned R file: `test-bridge-sh.R`, `test-bridge-lang.R` (plus the extra test files named under Owns).
- **Research.** G5 (all) and fact-check; 16 §6.2; 13 §2.10; architecture §4.2, §6.7.
- **Depends on.** P10, P11.
- **Milestone.** M5.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "bridge|copy-bridge")'` is green (Python, duckdb and knitr
     engine cases skip when unavailable).
  2. G5's behaviours: argv without a shell, a simple command line run directly and pipelines through the
     resolved shell; C-locale UTF-8 output correct; timeout kills the process tree and suggests `gptr$bg`; a
     background job's `$wait(until = "ready")`; truncation notice `gptr$out(<id>)` returns the full output; the
     print budget of 1,500 tokens holds with stderr floors.
  3. Classifier hooks: `gptr$sh("rm -rf data")` is level 3, `gptr$sh(c("git", "status"))` level 0,
     `gptr$sql("select ...")` level 0 and `drop table` level 3; computed commands are re-checked at run time.
  4. The copy row documents exactly one copy after `gptr$sql(name = df)` (duckdb registration) and none for
     `gptr$sh()`.
  5. Review additions: `gptr$knit("bash", "sleep 999")` times out and kills the process, and its environment lacks a
     registered fake key; `-builtin:bridges` removes the shell line from `<r_session>`; P22's NS fixtures are added to
     `dev/bench/tokens/` (IC-73).

### P23 Artifacts

- **Goal.** Artifacts are Shiny apps (S-5, REQ-39) launched from the live session in supervised background
  processes.
- **Scope.** `artifact-app.R` (`gptr$app()`: static checks, immutable `vNNN/` snapshots with the leaf `saveRDS`
  wrapper and size cap, callr child with the `artifact` environment, random port file, parent-PID watchdog,
  HTTP 200 check, optional chromote session check and 1000x700 screenshot, `html` kind, `artifact_start/stop`
  events, the artifacts `checkpointer`, `builtin:artifacts`); `artifact-registry.R` (`gptr_artifacts()`, open,
  relaunch a version, stop, lazy orphan sweep, `.onUnload` cleanup); `inst/gptr/skills/shiny-bslib/`.
- **Review amendments (contract §15).** The `artifacts` prompt section (IC-68); ids that are Windows reserved names
  refused and numbered data files with the mapping in `artifact.json` (IC-63); a per-launch access token in the URL
  (IC-71); ports from `port_candidates()` and `with_seed_preserved()` around chromote and shiny in the parent
  (IC-61); logs read and redacted by the parent (IC-70); `supervise_default()`, `encoding = "UTF-8"`,
  `child_env_callr()` and `stopped` (not `error`) after a requested stop (IC-60); `gptr$app(kind =)` accepts any
  registered `artifact_type` (IC-69); static checks flag reads of secret files (IC-71).
- **Owns.** The two R files and tests; `test-copy-artifact.R`; `inst/gptr/skills/shiny-bslib/`.
- **Test files.** One per owned R file: `test-artifact-app.R`, `test-artifact-registry.R` (plus the extra test files named under Owns).
- **Research.** 17 (all) and fact-check; G2 (a); G7 (artifact records); G6 (artifact child environment); 13
  C-42, C-43; architecture §5.7, §6.15.
- **Depends on.** P10, P11, P14 (acceptance 4 checks the renderer's NS-8 line on `artifact_start`), P16.
- **Milestone.** M5.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "artifact|copy-artifact")'` is green (launch tests skip on
     CRAN and without shiny; the chromote step skips without chromote).
  2. The validation ladder on a fixture app: parse, launch, HTTP 200, session check; a broken app returns the
     child's error to the model; the child's environment contains no registered secret; the port is random and
     loopback; `gptr_artifacts(id, stop = TRUE)` leaves no process.
  3. A second `gptr$app()` after an edit creates `v002` without touching `v001`; the snapshot leaves the source
     object editable in place (copy row).
  4. NS-8 on the fake provider writes `.gptr/artifacts/marker-explorer/app.R` and P14's renderer prints the NS-8
     line `artifact  marker-explorer  ->  <url>   (running in background)` on `artifact_start` (IC-71).
  5. Review additions: `gptr$app("con")` is refused; a data object named `a/b` snapshots as `data/001.rds`; a request
     without the token is rejected; `.Random.seed` is unchanged by `gptr$app(check = TRUE)`; a stopped artifact's
     status is `stopped`; P23's NS-8 fixture is added to `dev/bench/tokens/` (IC-73).

### P24 Token benchmark and end-to-end acceptance

- **Goal.** Make token efficiency and the cross-cutting guarantees measurable and regression-proof (S-12,
  INFRA-22/24, rule C1).
- **Scope.** `dev/bench/tokens/` (golden transcripts for NS-1..NS-11 as JSON, replayed through the fake
  provider; rtiktoken counts; committed baseline; ratchet gates of architecture §12.7; `live.R` calibration mode
  behind `GPTR_LIVE_TESTS`); `dev/bench/polyglot/` (G5's 8 tasks); `dev/bench/shiny-html/` (G2's 20-app
  ladder); `dev/bench/cache-sim/` (G4's simulator); `dev/bench/perf/` (grep, read, SSE and diff benchmarks);
  `tests/testthat/test-secrets-e2e.R`; `test-injection-e2e.R`; `test-northstar.R`; a CI step asserting the
  offline INFRA suite finishes in under 60 s.
- **Review amendments (contract §15).** `tests/testthat/test-s11-conformance.R` (a fixture plugin registers one
  record of every kind; each is used at run time) (IC-73); every §12.7 gate in `run.R --check` (IC-73); the
  composed system prompt with every built-in loaded compared byte for byte with architecture §7.3 (IC-68); the
  secrets e2e sinks of IC-70 and the redirect mock (IC-64); the adversarial gate paths of IC-53 in
  `test-injection-e2e.R`; the NS-1 and remaining fixtures not added by earlier plans.
- **Owns.** No R files. The `dev/bench/` tree except P07's runner and fixtures (IC-73), and the four test files.
- **Test files.** Only the files named under Owns.
- **Research.** G2 (all) and fact-check; G4 §4.9, §5.10 and fact-check; G5 p10 and fact-check; G6 test_e2e;
  13 C-36; 02-north-star-examples.md; architecture §6.3, §6.5, §12.
- **Depends on.** P01-P23. `rtiktoken` is a development tool used only under `dev/bench`; if it is not
  installed, the step stops for the maintainer (conventions §1).
- **Milestone.** M5.
- **Acceptance.**
  1. `Rscript --vanilla dev/bench/tokens/run.R` replays all golden transcripts offline in under 5 s and writes
     `dev/bench/tokens/results.csv`; `Rscript --vanilla dev/bench/tokens/run.R --check` exits 0 against the
     committed baseline and exits non-zero (raising `gptr_error_token_regression`) when a fixture's prefix grows
     by more than 2%.
  2. `Rscript --vanilla dev/bench/polyglot/run.R --check` exits 0 (B and C totals within 10% of baseline).
  3. `Rscript --vanilla -e 'devtools::test(filter = "secrets-e2e|injection-e2e|northstar|s11-conformance")'` is
     green: zero key bytes across every sink with redaction on (JSONL, wire logs, documents, caches, spill files,
     sidecars, MCP and artifact logs, worker spec and result files), a positive count in the negative control; no
     `{...}` payload evaluated through any printer or condition constructor; every IC-53 path an injected model tries
     ends in a human ask or `blocked`; NS-1..NS-12 pass on the fake provider; every kind's fixture record is used.
  4. `run.R --check` fails when a fixture's input or output total grows by more than 5%, its request count or image
     tokens by any amount, a catalog by more than 5%, or the describers lose a fact (IC-73).

### P25 Release

- **Goal.** gptr 1.0.0 on CRAN.
- **Scope.** Roxygen documentation review for all 63 exports (`@return`, offline examples, "Security
  considerations" and data-egress help pages); precomputed vignettes from `.Rmd.orig` (getting-started,
  system-one, script-as-history, extending-gptr, token-efficiency); `README.Rmd`/`README.md`; `NEWS.md` with a
  "Breaking changes" section for the removal of `get_response()` and `dataframe_to_text()` (S-7, no shims);
  `cran-comments.md` citing the consent design and precedents and recording
  `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on submission day; `_pkgdown.yml`;
  `DESCRIPTION` Version set to 1.0.0 and `VignetteBuilder: knitr` added with the vignettes (the only DESCRIPTION
  fields this plan may change; IC-72); the release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against
  one Anthropic and one OpenAI model and records request counts (within +2) and input tokens (within 20%) of the
  golden transcripts in `dev/bench/tokens/live-<date>.csv` (IC-73); the Security considerations page covers PHI in
  committed caches and the non-isolating worker backend (IC-70, IC-53).
- **Owns.** `README.Rmd`, `README.md`, `NEWS.md`, `cran-comments.md`, `_pkgdown.yml`, `vignettes/`.
- **Test files.** Only the files named under Owns.
- **Research.** 13 §3-§5 (DESCRIPTION wording, release, cran-comments template, precomputed vignettes,
  urlchecker, spelling); 10 (prior-art credits); conventions.
- **Depends on.** P24.
- **Milestone.** M5.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`
     gives 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the maintainer (an
     update of gptr 0.7.0; IC-72) on the full CI matrix (macOS, Windows, Ubuntu release/devel/oldrel-1, oldrel-4,
     no-suggests, `LC_ALL=C`).
  2. `devtools::check_win_devel()` result: Status OK apart from the maintainer NOTE.
  3. `Rscript --vanilla -e 'urlchecker::url_check()'` and `Rscript --vanilla -e 'spelling::spell_check_package()'`
     report nothing actionable; `Rscript --vanilla -e 'pkgdown::build_site()'` succeeds (these are development
     tools; if one is not installed, the step stops for the maintainer).
  4. Every example runs offline in a fresh session with no keys; vignette code runs offline in under 60 s.
