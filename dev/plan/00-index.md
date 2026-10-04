# gptr 1.0 implementation index

Start here. This page tells an implementation session what to read, what to install, the order of
the 25 plans, the gate at the end of each milestone, and what is still open. Counts, commands and
paths were checked against the plan files on 2026-10-01 (307 `### Task` headings in P01-P25).

The preflight table below is the historical 2026-10-01 snapshot, not a current availability check.
Verify tools locally and keep any machine-specific inventory in the ignored `dev/LOCAL_SETUP.md`.

**Local Ollama amendment:** contract IC-74 and `../spec/07-local-ollama.md`
add native Clef/Clef Flash decisions alongside local chat. Read its plan ownership
matrix before executing affected plans; the 307-task/PASS-count snapshot predates
this amendment. Ollama >= 0.35.1 and installed compatible models are optional
requirements for its live tests, not core dependencies. Tests never pull models.

Quick start:

1. Read the files of section 1, in order.
2. Run the preflight of section 2 (installs need the maintainer's approval).
3. Create the branch `gptr-1.0` off `main`.
4. Execute P01 to P25 in numeric order (section 4), task by task (section 3).
5. After the last plan of each milestone, run its gate (section 5) and tag it.

## 1. Purpose and read order

| # | File | Why |
|---|---|---|
| 1 | `CLAUDE.md` (repository root) | non-negotiable rules: `=` and `\|>`, `Rscript --vanilla`, no R LLM packages, offline tests, key hygiene |
| 2 | `dev/plan/00-conventions.md` | Global Constraints of every plan: commands, layout, style, errors, JSON, tests, dependencies, commits |
| 3 | `dev/spec/03-architecture.md` | layers, file ownership (§3.2), mechanisms, dependencies (§9), risks (§13) |
| 4 | `dev/spec/04-interface-contract.md` | every export, internal interface, class, option and file format; **§15 (IC-32..IC-73) wins over earlier sections** |
| 5 | `dev/spec/05-plan-decomposition.md` | scope, dependencies and acceptance checks of each plan; the milestone table |
| 6 | `dev/plan/Pxx-*.md` | the plan you implement: Global Constraints, File Structure, Tasks, Plan acceptance |

Authority when texts disagree: 04 (§15 first) > 03 > 05 > plans. `00-conventions.md` wins over a
plan unless the plan names the exception. Reference while working: `dev/spec/02-north-star-examples.md`
(NS-1..NS-12, the end-to-end shapes the tests name) and `dev/spec/06-review-resolution.md` (origin of
IC-32..IC-73).

Research lives in `dev/research/`: start with `README.md` and `00-digest.md`; open a full report only
for the exact section a plan cites. **A report's Verification log overrides its body.** Prototype code
in reports may use `<-`; convert it to the house style when copying.

## 2. Preflight (one time)

Installing anything needs the maintainer's approval. Plan steps never install packages: when a
tool is missing, the step stops for the maintainer (conventions §1).

| Item | State on the development machine (checked 2026-10-01) | Action |
|---|---|---|
| R >= 4.2.0 | R 4.4.3 at `/usr/local/bin/R`; `capabilities("profmem")` TRUE; locales `C`, `en_US.UTF-8`, `de_DE.UTF-8` present | none |
| Imports (8) | jsonlite, curl, processx, callr, rlang, cli, yaml, ps: all installed | none |
| Suggests | installed except **chromote, duckdb, keyring** | install (below) |
| Dev tools | devtools 2.5.0, roxygen2 7.3.3, lintr 3.3.0-1, styler 1.11.0, pkgload, rcmdcheck, urlchecker, pkgdown 2.2.0 installed; **rtiktoken, spelling, covr** missing | install (below) |
| pandoc | 3.11 (`/opt/homebrew/bin/pandoc`) | none (P25 vignettes) |
| Chrome | `/Applications/Google Chrome.app` | none (chromote: P23 test, P24 Shiny ladder) |
| Quarto CLI | **not installed** | optional; without it P15 Task 18's Quarto test in `test-doc-knitr.R` skips (the only Quarto-dependent test) |
| claude, codex CLIs | claude 2.1.261, codex-cli 0.157.0 | needed only for P20's opt-in live test |
| Other programs | git, bash, perl, pgrep, rg, sqlite3, make, python3 (with pandas), gh 2.100.0 | none; `rg` gates one P10 test, `bash`/`pgrep`/`perl` gate P22 tests |

Install the missing packages (one call, from the repository root):

```bash
Rscript --vanilla -e 'install.packages(c("chromote", "duckdb", "keyring", "rtiktoken", "spelling", "covr"), repos = "https://cloud.r-project.org")'
```

Who needs them: chromote (P23, P24), duckdb (P22), keyring (P03); rtiktoken (o200k counts for
`dev/bench/tokens/run.R` from P07 on, and P24's benches), spelling (P25 Task 15; P25's tests skip
without it). covr is not used by any plan command; it is an optional coverage tool. The plans'
token baselines were measured with rtiktoken 0.0.7; CRAN now ships 0.11.0.3. P07's first
`run.R --check` (its acceptance C8) shows whether the counts still match; if they drift, stop for
the maintainer (0.0.7 is in the CRAN archive as `rtiktoken_0.0.7.tar.gz`; Rust is installed here).

Other one-time facts:

- **Credentials.** `.secrets/jev-key.env` (variable `jev-key`) and `.secrets/llm-passwords.env`,
  relative to the repository root. Only opt-in live tests read them through `gptr_env()` once
  implemented. Never print, log, copy or commit them. Preserve the Git and R build exclusions.
- **Old `.Rprofile`.** It sources a missing `renv/activate.R`; P01 Task 1 deletes it. Until then,
  always run `Rscript --vanilla`.
- **Git.** Work on a feature branch (`gptr-1.0`) off `main`. One commit per task with the message the
  plan gives, adding only the files the task lists (conventions §10). Never commit `.env` files
  (P01's `.gitignore` adds `.env` and `*.env`). Tag each milestone after its gate, for example
  `git tag -a gptr-1.0-m0 -m "M0 gate passed"`. Pushing, opening a pull request and pushing tags
  leave this machine: ask the maintainer first.
- **Versioned design files.** `dev/` and `CLAUDE.md` were committed on `gptr-1.0` and consolidated
  into `main` on 2026-10-03. Plans should still commit only the files for their own task;
  local machine inventories and raw source conversations remain ignored.
- **Network.** P05 Task 6 downloads the models.dev catalog (about 5 MB; `--offline` builds a
  seed-only snapshot that must be rebuilt online before release). P25 Task 15 needs the network
  for URL checks, CI, win-builder and the submission. Tests never use the network.

## 3. How to execute

- Use **superpowers:subagent-driven-development** (recommended): one fresh subagent per task, given
  the task text, the plan's Global Constraints and `00-conventions.md`; review the result between
  tasks before the next one starts. Or use **superpowers:executing-plans** (batches with review
  checkpoints).
- Every task has the same five steps: write the failing test; run it and see the stated failure;
  implement; run it and see the stated `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]`; commit. A different
  result means the code differs from the plan: investigate before moving on
  (superpowers:systematic-debugging). P01, P04, P18 and P23 prefix red runs with
  `testthat::set_max_fails(Inf)`, because testthat otherwise stops after 10 failures without a
  summary line; do the same for any red run with many failures.
- Expected counts were measured on this machine (macOS, R 4.4.3) with the listed packages.
- A step that says "stop for the maintainer" (missing tool, paid live run, network, submission)
  stops and asks.
- Each plan ends with its **Plan acceptance** section; run it before starting the next plan. Each
  milestone ends with its **gate** (section 5).

## 4. Execution order

Numeric order is a valid topological order of 05's dependency graph: every plan depends only on
lower-numbered plans. "Depends on" lists 05's direct dependencies.

| # | Plan | M | Depends on | Tasks | Goal |
|---|---|---|---|---|---|
| 1 | [P01 Foundation](P01-foundation.md) | M0 | - | 21 | package skeleton, L0 utilities, JSON, message and event model, fake provider, test helpers, CI matrix |
| 2 | [P02 Extension API and registry](P02-extension-api-registry.md) | M0 | P01 | 11 | registry by (kind, name), spec kinds and constructors, events, factory API and `ctx` |
| 3 | [P03 Secrets and redaction](P03-secrets-redaction.md) | M0 | P01, P02 | 11 | vault with origin-bound handles, redactor for every sink, `.env` loader, credential store, scrubbed child env |
| 4 | [P04 Reactor and process engine](P04-reactor-process-engine.md) | M0 | P01, P03 | 12 | one reactor for HTTP streams and child pipes, supervision, SSE/NDJSON splitters, retries, rate limits |
| 5 | [P05 Model layer core](P05-model-layer-core.md) | M1 | P02, P03, P04 | 12 | provider records, `provider_stream()`, transcript projection and hand-off, usage and cost, offline catalog |
| 6 | [P06 Session kernel and agent loop](P06-session-kernel-agent-loop.md) | M1 | P04, P05 | 16 | S-8 session object, JSONL store (fork, resume, replay), agent loop, tool dispatcher, permission kernel |
| 7 | [P07 Prompt, context, caching, compaction](P07-prompt-context-caching-compaction.md) | M1 | P06 | 16 | frozen cache-anchored context, system prompt, compaction, token baselines in `dev/bench/tokens/` |
| 8 | [P08 Gateway and SDK](P08-gateway-sdk.md) | M1 | P03, P07 | 12 | `gptr()` capture and routing, identifiers, settings, trust, egress and replay controls, SDK verbs |
| 9 | [P09 Evaluator and workspace](P09-evaluator-workspace.md) | M2 | P08 | 11 | evaluate model R code in the live session (output, conditions, plots) and describe the workspace without copies |
| 10 | [P10 Tools and the `gptr$` namespace](P10-tools-namespace.md) | M2 | P09 | 13 | `r`, `read`, `edit`, `write` (+ `grep`, `find`, `ls`) and the `gptr$` namespace |
| 11 | [P11 Permissions, UI and plan mode](P11-permissions-ui-plan-mode.md) | M2 | P10 | 11 | `gptr_risk()`, rules and policies, UI backends and approval prompt, `ask` tool, plan mode |
| 12 | [P12 Native provider adapters](P12-native-provider-adapters.md) | M2 | P05, P07 | 10 | Anthropic, OpenAI Responses and Completions, Google adapters with byte-exact replay |
| 13 | [P13 System 1](P13-system-one.md) | M2 | P08, P09, P12 | 13 | typed, vectorised Jev decisions for `if`/`for`/`while`, cached per element |
| 14 | [P14 Console and front ends](P14-console-front-ends.md) | M3 | P08, P11 | 8 | REPL, slash commands, `!expr`, Ctrl-C pause menu, markdown renderer, JSONL sink |
| 15 | [P15 Documents and replay](P15-documents-replay.md) | M3 | P08, P10 | 19 | `.R`/`.Rmd`/`.qmd`/`.ipynb` as harness and history: record, replay with zero model calls |
| 16 | [P16 Checkpoints and rewind](P16-checkpoints-rewind.md) | M3 | P11, P15 | 8 | reversible objects, files and session state; `gptr_rewind()`, `/undo`, `/redo`, `/rewind` |
| 17 | [P17 Skills, templates, agent files, plugins](P17-skills-templates-agents-plugins.md) | M3 | P08, P10 | 12 | Agent Skills, prompt templates, agent files, plugin packages and `.claude-plugin` bundles |
| 18 | [P18 MCP and OAuth](P18-mcp-oauth.md) | M4 | P10, P11 | 10 | MCP client (both eras, stdio and HTTP), gptr as MCP server, OAuth PKCE and login |
| 19 | [P19 Sub-agents](P19-sub-agents.md) | M4 | P11, P14, P15, P17 | 12 | teams, fan-outs, `gptr_parallel()`; inline, worker and CLI backends on one reactor |
| 20 | [P20 Subscription CLI providers](P20-subscription-cli-providers.md) | M4 | P12, P18, P19 | 11 | `claude-cli` (alias `claude_code`) and `codex` routes with live R through gptr's gate |
| 21 | [P21 Background sessions (experimental)](P21-background-sessions.md) | M4 | P06, P14 | 7 | `background = TRUE`; pipe steering of a running session at the idle console |
| 22 | [P22 Polyglot bridges](P22-polyglot-bridges.md) | M5 | P10, P11 | 11 | `gptr$sh`, `script`, `bg`, `jobs`, `py`, `sql`, `knit`; no shell tool |
| 23 | [P23 Artifacts](P23-artifacts.md) | M5 | P10, P11, P14, P16 | 12 | Shiny apps in supervised background R processes, validation ladder, `gptr_artifacts()` |
| 24 | [P24 Token benchmark and e2e acceptance](P24-token-benchmark-acceptance.md) | M5 | P01-P23 | 13 | `dev/bench/` suites; secrets, injection, north-star and S-11 end-to-end tests |
| 25 | [P25 Release](P25-release.md) | M5 | P24 | 15 | manual for 63 exports, vignettes, README, NEWS, cran-comments, pkgdown, live calibration, CRAN submission |

Tasks per milestone: M0 55, M1 56, M2 58, M3 47, M4 40, M5 51; total 307.

## 5. Milestone gates

Run every command from `/Users/wanjun/Desktop/gptr`. A gate adds no code; a failure is fixed in the
plan that owns the failing file.

### 5.1 Common gate (every milestone)

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test()'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'
env -u TYPESAFE_API_KEY Rscript --vanilla dev/bench/tokens/run.R --check   # from M1 on (P07 adds it)
Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'
```

| Command | Expected |
|---|---|
| `document()` | exit 0 |
| `test()` | `[ FAIL 0 \| WARN 0 \| SKIP n \| PASS m ]`; skips only those the plans name (section 6) |
| lint (namespace loaded first, or `object_usage_linter` flags every internal call) | no lint listed, exit 0 |
| `run.R --check` | last line `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`, with n = 2 (M1), 4 (M2), 5 (M3), 7 (M4), 14 (M5); M3 and M4 are the counts of fixture files the plans create |
| `check()` | `0 errors \| 0 warnings \| 1 note`: the incoming-feasibility NOTE naming the maintainer (it may also mention the `.9000` version component); gptr 0.7.0 is on CRAN, so there is no "New submission" NOTE |

Then the CI matrix (ask the maintainer first). P01's `.github/workflows/R-CMD-check.yaml` runs on
pushes to `main` and on pull requests only, so a pushed feature branch needs an open pull request:

```bash
git push -u origin gptr-1.0                                # origin = the GitHub remote
gh pr create --draft --fill --base main --head gptr-1.0   # once; later pushes re-run CI
gh run list --workflow R-CMD-check.yaml --branch gptr-1.0 --limit 1 --json headSha,status,conclusion
git rev-parse HEAD
```

Expected: `status` `completed`, `conclusion` `success`, `headSha` equal to `HEAD`. The jobs:
`R-CMD-check` (macOS release; Windows release and oldrel-4; Ubuntu devel, release, oldrel-1,
oldrel-4), `no-suggests`, `c-locale` (`LC_ALL=C`), `copy-safety` (release, devel), `connections`
(`_R_CHECK_CONNECTIONS_LEFT_OPEN_=true`) and `bench` (token ratchet; P24 appends three steps,
including the INFRA suite under 60 s). Before P07 the `bench` job prints that `run.R` does not exist
yet, and before P08 `copy-safety` prints that no `test-copy-*.R` suite exists. Then tag the
milestone.

### 5.2 Milestone-specific checks

**M0 Foundation** (after P04; P04 "M0 exit commands"; 05: install with top-level `on_load()`,
reactor INFRA-01/05/06/21/23, registry conformance, redaction properties, no connection left open)

| Command | Expected |
|---|---|
| `lib=$(mktemp -d) && R CMD INSTALL --library="$lib" . && Rscript --vanilla -e "library(gptr, lib.loc = '$lib'); print(gptr_jobs())"` | `* DONE (gptr)` into a temporary library (never the user library), then an empty `gptr_jobs` listing (IC-32) |
| `Rscript --vanilla -e 'devtools::test(filter = "http\|proc\|lint\|arch")'` | `FAIL 0 \| WARN 0` |
| `Rscript --vanilla -e 'devtools::document()'` (common gate) | exits 0; `NAMESPACE` contains `export(gptr_jobs)` next to P01-P03's exports |

No token benchmark yet. Per-plan counts: P04 Plan acceptance rows 1-7.

**M1 Offline S-8 kernel** (after P08; P08 acceptance 7; 05: NS-2/NS-3 shapes, pipe steering, overlay
fork, resume, 20-turn byte prefix, gateway copy suite)

| Command | Expected |
|---|---|
| `Rscript --vanilla -e 'devtools::test(filter = "session\|agent")'` | green (P06 acceptance 1-8: fork, resume, steering, INFRA-09/10 and 12-15) |
| `Rscript --vanilla -e 'devtools::test(filter = "prompt\|context-prefix\|bench-context")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 579 ]` (P07 C1; `context-prefix` holds the 20-turn byte-prefix test) |
| `Rscript --vanilla -e 'devtools::test(filter = "gptr-\|copy-gateway")'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 506 ]` (the skip is the P11 leg; P08 acceptance 1) |
| common gate `check()` | every exported example runs offline on the fake provider |

**M2 Live R agent and System 1** (after P13; P13 commands 1-5; 05: NS-2..NS-5 on the fake provider
and mock servers, permission matrix, adapter conformance, evaluator copy suite)

| Command | Expected |
|---|---|
| `Rscript --vanilla -e 'devtools::test(filter = "s1-\|copy-s1")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 586 ]` (without profmem `SKIP 4 \| PASS 582`) |
| `Rscript --vanilla -e 'devtools::test(filter = "live-jev")'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 0 ]` (gated) |
| `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers\|lint-rules)$")'` | `FAIL 0` (anchored: a bare `arch` also selects P10's `test-tool-search.R`) |
| `Rscript --vanilla -e 'devtools::test(filter = "eval\|env-\|copy-eval")'`, `"tool-\|copy-tools"`, `"perm\|console-ui\|tool-ask"`, `"provider-(anthropic\|openai\|google)"` | green (P09, P10, P11 permission matrix, P12 adapter conformance) |

**M3 Interactive, recorded, reversible** (after P17, once P14-P16 are complete; P17 "Milestone gate
(M3 exit, acceptance 5)"; 05: NS-1 through the scripted console, NS-7 in `.R`/Rmd/qmd/ipynb, `/undo`
and rewind, NS-10 skills and plugins, NS-12)

| Command | Expected |
|---|---|
| common gate `test()` | skips limited to: live tests, P14's INFRA-03 off CI, P15's Quarto case without the CLI, platform skips (P15's SIGTERM test on Windows), copy rows without profmem |
| `Rscript --vanilla -e 'devtools::test(filter = "skill\|subagent-defs\|ext-plugins")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 444 ]` (P17 acceptance 1) |
| `"console"`, `"doc-"`, `"ckpt\|copy-ckpt"` filters | green (P14, P15, P16 acceptance 1) |
| common gate `check()` | toy-package tests skip under `--as-cran` |

Also run P14's "Manual check" in a terminal `R --vanilla` session (not automated).

**M4 Interop and scale-out** (P20 "Milestone gate" steps 1-4 at the end of P20; step 5 is P21's
command 5, after P21; 05: NS-6, NS-9, NS-10 MCP, INFRA-16/19)

| Command | Expected |
|---|---|
| `Rscript --vanilla -e 'devtools::test(filter = "mcp\|auth-oauth")'`, `"subagent\|copy-subagent"` | green (P18, P19) |
| `Rscript --vanilla -e 'devtools::test(filter = "cli-")'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 427 ]` (INFRA-16 leg skips unless the version under test is installed; then `SKIP 0 \| PASS 433`) |
| `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 158 ]` (P21 command 1) |
| `Rscript --vanilla -e 'pkgload::load_all(".", quiet = TRUE); fix = normalizePath("tests/testthat/fixtures/cli"); options(gptr.cli_path = list(claude = pcli_fake_command("claude", "text", fix, tempfile()), codex = pcli_fake_command("codex", "text", fix, tempfile()))); p = gptr_providers(check = TRUE); print(p[p$type == "cli", c("id", "status", "version")])'` | rows `claude-cli ready 2.1.261` and `codex ready 0.157.0` (NS-9, P20 gate step 3) |
| common gate `check()` (P21 command 5) | NS-6 and the INFRA-16 CLI leg run here, because R CMD check installs the package for the worker children |

Also run P21's "Manual check" in a terminal `R --vanilla` session.

**M5 Polyglot, apps, measured release** (P24 Task 13 is the pre-check; P25 Task 15 Step 4 is the
final gate; 05: NS-8, NS-11, token baselines committed, secrets and injection end to end, CRAN
submission check)

| Command | Expected |
|---|---|
| P24 acceptance A1-A18, for example `NOT_CRAN=true Rscript --vanilla -e 'devtools::test(filter = "secrets-e2e\|injection-e2e\|northstar\|s11-conformance")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 367 ]` |
| `Rscript --vanilla dev/bench/polyglot/run.R --check` | `[bench] polyglot: B and C totals within 10% of the baseline`, exit 0 |
| `Rscript --vanilla -e 'testthat::test_dir("dev/bench/tests", stop_on_failure = TRUE)'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 513 ]` |
| `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 136 ]` |
| `Rscript --vanilla dev/release/check-docs.R && Rscript --vanilla dev/release/check-examples.R && Rscript --vanilla dev/release/check-files.R all && Rscript --vanilla dev/release/check-live.R "$(ls dev/bench/tokens/live-*.csv \| tail -n 1)"` (the last argument is the newest calibration record) | `check-docs: 0 problems`, `check-examples: 0 problems`, `check-files all: 0 problems`, `check-live: 0 problems` |
| `Rscript --vanilla dev/release/precompute.R --check` | `precompute: 5 vignette(s) knitted in <s> s` with s < 60; `0 problems` |
| `Rscript --vanilla -e 'print(spelling::spell_check_package())'` | `No spelling errors found.` |
| `Rscript --vanilla -e 'urlchecker::url_check()'` (network) | `All URLs are correct!` |
| `Rscript --vanilla dev/release/build-site.R` | `build-site: 0 problems` |
| common gate `check()`, run **last** on the final tree | `0 errors \| 0 warnings \| 1 note`, `Maintainer: 'Wanjun Gu <wanjun.gu@ucsf.edu>'` |

Then P25 Task 15 Steps 5-6 (commit, then maintainer-approved steps): CI on that exact commit,
`devtools::check_win_devel()` (`Status: 1 NOTE`), the reverse-dependency record
(`Rscript --vanilla dev/release/check-files.R cran-comments --revdeps`, after which
`git status --porcelain --untracked-files=no` shows only ` M cran-comments.md`), and
`devtools::submit_cran()` from an interactive R session.

## 6. Live and optional tests

Tests are offline by default. P01's `setup.R` redirects home and user directories, blanks every
provider key unless `GPTR_LIVE_TESTS=true`, and sets `GPTR_REPLAY=replay`.

| Test | Plan | Enable with | Notes |
|---|---|---|---|
| `test-live-anthropic.R`, `test-live-openai.R`, `test-live-google.R` | P12 Task 10 | `GPTR_LIVE_TESTS=true` plus `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` or `GOOGLE_API_KEY` | paid; `GPTR_LIVE_TESTS=true Rscript --vanilla -e 'devtools::test(filter = "^live-(anthropic\|openai\|google)$")'`; skipped: `SKIP 3` |
| `test-live-jev.R` | P13 Task 12 | `GPTR_LIVE_TESTS=true` | reads the Jev key file through `gptr_env()` (default path above; override `GPTR_JEV_KEY_FILE`); under one cent; `PASS 14` |
| `test-live-cli.R` | P20 Task 11 | `GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME"` | spends plan quota; needs signed-in `claude` and `codex` (setup.R moves `HOME`); `PASS 7`, skipped: `SKIP 2` |
| All live files at once | conventions §2 | `GPTR_LIVE_TESTS=true Rscript --vanilla -e 'devtools::test(filter = "live")'` | also selects P06's `test-session-live.R` (offline, harmless) |
| INFRA-03 (real SIGINTs into an interactive R child) | P14 Task 7 | `CI=true` | Linux and macOS; skipped elsewhere |
| Quarto record and replay | P15 Task 18 | `quarto` on `PATH` | `SKIP 1` without it |
| Worker legs (INFRA-16, NS-6) | P19, P20 Task 10 | the version under test installed | run under `devtools::check()`; skip under `devtools::test()` otherwise |
| Python bridge | P22 | `RETICULATE_PYTHON` (or a configured reticulate Python) | gptr never lets reticulate download a Python |
| Process and mock-server tests | P01 onward | default (`NOT_CRAN=true` under devtools) | `NOT_CRAN=false` makes them skip, as on CRAN |
| Copy-safety rows (`test-copy-*.R`) | P08 onward | `capabilities("profmem")` | skip on CRAN |
| Suggests-gated tests | for example P03 keyring; P09, P22 DBI/RSQLite; P18, P20 httpuv/later/openssl; P21 later; P22 duckdb/reticulate; P23 httpuv/later/shiny/chromote | the package installed | skip otherwise |

The benchmark tree `dev/bench/` (P07's `tokens/` runner, P24's suites; see `dev/bench/README.md`
once P24 writes it) needs:

- **rtiktoken** (o200k counts) and **pkgload**; runners exit 0 on pass, 1 on a regression or error,
  2 when a tool is missing. Run the token runner with `env -u TYPESAFE_API_KEY`: the golden rows were
  recorded without a System 1 key (a key adds the `system1` prompt section, about 130 tokens).
- **Shiny ladder** (`dev/bench/shiny-html/`): shiny, bslib, plotly, DT, httpuv, chromote and Chrome
  or Edge.
- **Polyglot baseline** (`dev/bench/polyglot/run.R --update`, recorded on the maintainer's machine):
  git, sh, grep, python3 with pandas and `RETICULATE_PYTHON`, sqlite3, curl, make, bash.
- **Live calibration** (`dev/bench/tokens/live.R`, run in P25 Task 14): `GPTR_LIVE_TESTS=true` and
  `ANTHROPIC_API_KEY` plus `OPENAI_API_KEY` (or `GPTR_BENCH_ENV=<.env path>`, loaded with
  `gptr_env()`); optional `GPTR_BENCH_ANTHROPIC`, `GPTR_BENCH_OPENAI`, `GPTR_BENCH_BUDGET_USD`
  (default 2), `GPTR_BENCH_ONLY`. Writes `dev/bench/tokens/live-<date>.csv`; paid, maintainer only.

## 7. Known open items for the maintainer

| Item | Status | Pointer |
|---|---|---|
| Claude-plan route vs Anthropic's terms | policy UNCERTAIN; ships experimental and opt-in with a one-time notice; ask Anthropic before advertising it | 01 D-15, 03 §13, research 07 §2.18, P20 |
| `{gptr}` knitr chunk engine | deferred; maintainer decision pending; v1 uses `gptr("...")` in R chunks with `knit_print` | 03 §1.3, research 14 §4.6 |
| Sign in with ChatGPT; Codex app-server | deferred to v1.x plugins; v1 uses `codex exec --json` | 03 §1.3, research 08 |
| Other v1.x deferrals | nested-call cassettes, `apply_patch` tool, fork backend and mirai, Bedrock/Vertex/Copilot, provider-native compaction, Claude plugin hooks and `.codex` agents, file-inbox steering | 03 §1.3 |
| Windows | untested locally; relies on CI (Windows release and oldrel-4) and win-builder; some process tests skip on Windows; the Codex Windows sandbox probe is UNCERTAIN; worker stdin polling verified on macOS only | 03 §13, P20 ambiguity 9, P19 ambiguity 23(d), P25 Task 15 |
| Interactive front ends | pause menu, background pumping and readline unverified in RStudio, Positron, Jupyter, Rgui and Windows consoles; run the manual checks and record results in P21's support matrix | 03 §13, P14 and P21 "Manual check" |
| CI trigger | the workflow runs on pushes to `main` and on pull requests; P04's M0 step and P25 Task 15 Step 6 say "push the branch", which alone starts no run: open a draft PR | P01 Task 21 |
| Spec additions for 04's next revision | `gptr_warning_cli_sandbox` (§2.2); child-only `GPTR_ARTIFACT_PORTS` and test-only `GPTR_LIVE_HOME`, `GPTR_JEV_KEY_FILE` (§3.2); `secret_live_entries_set()` (§7.3); `write_close()` (§7.4); MCP tool `output_schema` and handle `token` (§7.18, §5.11); artifact `run.json` fields `create_time`, `parent_pid`, `parent_create_time` (§11.6) | P20 amb. 4 and 16, P23 Global Constraints and amb. 8, P13 Task 12, P03 A1, P06 amb. 20, P04 amb. 10, P18 amb. 3 and 8 |
| 04 text to correct | `\dontrun{}` for `gptr_login`/`gptr_mcp_add`/`gptr_mcp_serve` (the plans use `@examplesIf` and offline examples); `gptr.checkpoint_rng` defers to a `.Random.seed` restore that IC-61 forbids; `cli_version()`/`cli_probe()` collide with the §12.3 `cli_*()` lint rule (implemented as `pcli_*` with aliases) | P25 amb. 2 and 7, P18 amb. 6, P20 amb. 22 |
| Contract readings | every plan records the reading it implemented where 04 is silent or ambiguous: "Contract ambiguities" in the Self-review of P02-P09, P11-P16, P18-P25 (about 470 items); P01, P10, P17 under "Type and name consistency with 04" | each plan's Self-review |
| Plugin document formats | `gptr_doc()` binds only `.R`, `.Rmd`, `.qmd`, `.ipynb`, so a plugin `doc_format` works only by shadowing a built-in name | P24 amb. 22 |
| Token benchmark | the whole `run.R` cannot meet the 5 s bound with rtiktoken (needs a persistent memo in P07's `bench_counter()`); the machine-dependent `<r_env>` section can make a baseline recorded on the maintainer's Mac fail on another machine (CI `bench` job) | P24 amb. 1 and its Executed validation |
| Model catalog | P05 Task 6 downloads models.dev; an `--offline` snapshot must be rebuilt online before release | P05 Task 6 |
| pkgdown site | no site URL yet (the github.io address returns 404), so `_pkgdown.yml` has none | P25 amb. 9 |
| Release steps outside this machine | paid live calibration, CI, win-builder, reverse dependencies, `submit_cran()`: maintainer only, asked step by step | P25 Tasks 14-15 |

## 8. Where the evidence is

| What | Where |
|---|---|
| Research reports 01-21, G1-G7 | `dev/research/` (`README.md` index, `00-digest.md` summaries; each report ends with its Verification log) |
| Prototypes and measurement scripts | `dev/research/assets/` (`G2/` benchmark apps and scripts, `design-final/`, `design-review-resolution/`, `lead/`; `assets/README.md`); `consolidation-lint-results.csv` (plan-code lint run of 2026-10-01) |
| Design decisions | `dev/spec/00-vision-brief.md`, `01-decision-register.md` ("Final decisions"), `dev/spec/proposals/` (P-A, P-B, P-C skeletons) |
| Review of the design | `dev/spec/06-review-resolution.md`; contract §13 (reconciliation) and §15 (IC-32..IC-73); 03 Appendix A (checks) and B (judges' grafts) |
| Per-plan evidence | each plan's Self-review (spec coverage, contract ambiguities, executed validation), "Plan review log" (adversarial review) and "Cross-plan consolidation log" (2026-10-01); every log row has a verdict (applied, rejected or no change) |
| Benchmarks and release tooling | `dev/bench/` (P07, P24) and `dev/release/` (P25), created during implementation |
