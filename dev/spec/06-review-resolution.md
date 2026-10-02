# gptr 1.0 — Review resolution (2026-09-30)

An adversarial review of the design (`03-architecture.md`, `04-interface-contract.md`, `05-plan-decomposition.md`,
the "Final decisions" of `01-decision-register.md` and `dev/plan/00-conventions.md`) raised **144 issues** through
six lenses: requirements (36), CRAN and Windows (22), consistency (23), research fidelity (21), plugins and tokens
(18), safety and failure (24). This document records the verdict on each one and what changed. The normative text of
every change is the contract's §15 (decisions IC-32..IC-73, cited as `IC-nn`); the sections the changes touch were
also edited in place, so `03`, `04`, `05`, the register and the conventions agree. All code in the design files
uses `=` and `|>` (S-9).

## Outcome

- **Verdicts.** Every issue was checked against the cited sections and research and found valid. 139 were applied
  as proposed or with an equivalent alternative (named in the row). 5 were applied in part: one sub-proposal was
  declined for a stated reason (cran-4, cran-18, plug-7, safe-8, safe-19). No issue was rejected outright.
- **How issues were verified.** Every row was checked against the text it cites. The following claims were also
  re-run with `Rscript --vanilla` (scratch: `dev/research/assets/design-review-resolution/checks.R`):
  - processx rejects `NA` in `env`;
  - `supervise = NULL` makes processx fail with "argument is of length zero";
  - `httpuv::randomPort()` changes `.Random.seed`;
  - a weak reference whose key is a session is collected by the first `gc()`;
  - R 4.4.3 opens 125 file connections and then fails with "all 128 connections are in use";
  - `enc2utf8()` rewrites an unmarked `"café"` to `caf<c3><a9>` under `LC_ALL=C`.

  The critics' `wv4.R`/`wv6.R` (`withVisible` sticky references: 1 copy before the fix, 0 after) and `dots_hold.R`
  (a forced dot copies on an in-run edit) were re-run with the same results. Evidence the critics had already
  reproduced was accepted: collation order, lintr, the redirect key leak, the torn-line merge, SIGTERM skipping
  finalizers, the fork replay, the condition detection and the undeclared-`ps` WARNING.
- **Token effects** were measured with rtiktoken o200k (`review-resolution/prompt/measure3.R`). New static prefixes:
  minimal 1,271 (was 1,299), standard core 2,360 (2,385), standard with every section 2,844 (2,818), interactive
  with every section 2,987 (2,980). Behind these totals:
  - the `r` schema variants save 9-79 tokens per request;
  - the `readonly` rules are 115 tokens shorter;
  - skill pseudo-paths save 9 tokens;
  - the `trusted="false"` sentence adds 35 and the `record = false` rule adds 12.
- **Structural outcomes.**
  - The export count stays 63: `gptr_map()` becomes internal (S-1) and `gptr_scrub()` is new.
  - Imports gain `ps`, which is already in the closure.
  - The registry has 38 kinds; the new ones are `preset`, `risk_rule`, `service`, `renderer`, `search_source`,
    `store` and `evaluator`.
  - A new file, `R/aaa-state.R`, collates first.

## Requirements lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| req-1 | blocker | 04 §11.5, §6.6, §9.4; 03 §6.9.3, §7.3; 05 P10, P15 | applied | `gptr_return(x)` outside a run returns `invisible(x)` (the `not_in_run` class is removed); `doc_block_lines()` drops top-level `gptr_return()` and `record = FALSE` member calls; `out`, `plot`, `help`, `search`, `describe` are `record = FALSE` and `<r_session>` says so; P10 acceptance 5 and a P15 re-source test changed (IC-48) |
| req-2 | blocker | 04 §11.5, §6.5, route 50; 03 §6.9.3, §10.2 | applied | replay binds the fork it creates to the block id (`the$replay_blocks`); fork turns are wrapped `local({...}, envir = gptr_resume(block = "<id>")$envir)`, which errors `replay_unbound` and never falls back to the caller; rebuilt forks get fresh overlays; P06 `session_replay_bind()`/`replay_lookup()`; P15 re-sources NS-3 twice (IC-46) |
| req-3 | blocker | 04 §11.4; 03 §5.8, §6.12, §9.1; conventions §8; lint | applied (alternative for `parallel`) | `ps` joins Imports (closure unchanged) behind `pid_alive()`; `parallel` is not imported: `rng_swap()` assigns an L'Ecuyer `.Random.seed` from hash-derived seeds without `set.seed()`, and the lint allows `.Random.seed` assignment only there and in `with_seed_preserved()` (IC-59, IC-61) |
| req-4 | major | 04 §6.1.1, §1.3, §12.2; 03 §6.4 | applied | plain-symbol dots are read through a `get0()` leaf and never forced; calls and forwarded dots are forced (one in-run copy documented); `expect_no_copy(in_run_edit = TRUE)` rows for the three shapes (IC-41) |
| req-5 | major | 04 route 50, §7.6, §7.15; 03 §6.9.3 | applied | a piped session is advanced in place by `session_replay_apply()`; otherwise `session_replay_new()` rebuilds from the JSONL or reconstructs the history from the document (`history_source = "reconstructed"`); fresh-clone test (IC-46) |
| req-6 | major | 04 §6.1.1, §11.5; 03 §6.9.3, §7.3 | applied | top-level team and fan-out statements own one block (`kind=`, `children=`, one line per child, export wrappers, S2 text per child); block-nested `gptr()` statements replay from S2 by (block, ordinal); System 1 in blocks uses its cache; zero-request replay tests (IC-47) |
| req-7 | major | 04 route 50, §6.4, §11.2-11.3; 03 §4.1.1, §6.9.3; 05 P15 | applied | the route matches a located document that holds a block for the call, and replay needs no consent; write consent (`gptr_doc()` for every call of the process, the `record` option or user setting, an interactive yes) is checked only in `doc_upsert()`; the "trusted `record = auto`" wording is deleted because `record` only tightens (IC-45) |
| req-8 | major | 04 §11.5; 03 §6.9.3 | applied | transcripts record `s_<hex> = gptr("...")` then `s_<hex> \|> gptr("...")`; `## Steer:`/`## Follow-up:` lines inside blocks, excluded from hashes; P15 test (IC-49) |
| req-9 | major | 04 §7.7, §7.8, §7.9; 03 §7.4 | applied | context placement `both`; `attached` and preloaded skills use it; P07 acceptance checks `<attached name="mtcars">` in the first request (IC-38) |
| req-10 | major | 04 §6.1, §7.6, §7.8; 03 §5.1 | applied | precedence explicit `envir` (by `missing()`) > kept home > caller frame; a context symbol invisible from the evaluation environment fails fast; P08 test (IC-40) |
| req-11 | major | 04 §7.1, §6.1.1, §7.7, §7.8, §6.2, §11.5 | applied (alternative predicate) | instead of making `gptr_has_human()` TRUE in IRkernel, a separate `gptr_can_prompt()` (TRUE with `jupyter.in_kernel`) decides every question (cran-6's split keeps streaming decisions separate); Jupyter blocks are shown as cell output and kept pending; `gptr_doc(path, sync = TRUE)` writes them (IC-43, IC-50) |
| req-12 | major | 04 §6.1.3, §11.13 | applied | `name_norm()` (lower case, `_`/`.` -> `-`) for skills, plugins, extensions and agents; ambiguous matches error with candidates; P17 tests (IC-42) |
| req-13 | major | 03 §2.2; 04 §7, §12.2 | applied | function-level kernel SDK allowlist; L1 adapters get injected `opts$gate`, `opts$mcp_dispatch`, `opts$tool_result`; the `trust.get` service (IC-33) |
| req-14 | major | 04 §10.1, §10.3 | applied | a lower-rank record shadows only the same `(kind, name)`; whole built-ins are disabled only by explicit filters; P02 test with a `read` override (IC-69) |
| req-15 | major | 04 §6.1, §7.2, §7.17, §10.1 | applied | `ext_load(session =)`; session-scoped records and hooks, removed at shutdown; P02/P17 test (IC-69) |
| req-16 | major | 03 §6.8.1-6.8.2; 04 §11.15 | applied | `control` risk category at level 4 (`ask_human`) for gptr's configuration exports and `gptr.*` options, plus `run_current()` checks in the exports; P11 acceptance in manual and plan (IC-53) |
| req-17 | major | 04 §8.2, §7.13, §7.18, §6.3; 03 §2.3, §6.1 | applied | pump depth; `allow_runs` defaults to none inside a run; `later::run_now(0)` only in the outermost pump or for a served CLI child (other sessions get a retryable busy error); P04/P19 test (IC-57). The `serverSocket()` alternative was not taken: it has no host argument and listens on every interface |
| req-18 | major | 04 §6.3, §7.18; 03 §6.13, §8.3 | applied | one socket, one bearer token per client bound to its session (environment, mode, rules, budget, usage); tests with a fork and a plan-mode parent (IC-58) |
| req-19 | major | 04 §3.1, §6.5; 03 §6.13 | applied | `max_tasks` applies only to teams and fan-outs started at depth >= 1; user fan-outs queue every element; test with 20 elements and `parallel = 4` (IC-39) |
| req-20 | minor | 04 §6.7, §6.8 | applied | `gptr_fake_provider(type =)` and `gptr_context_block(order =)` signatures fixed with the other constructor fixes (IC-35) |
| req-21 | minor | register D-28; conventions §4 | applied | D-28 says 63 exports; `@examplesIf` uses `nzchar(Sys.getenv(...))` or the fake; `on.exit()` in `R/`, withr in tests only (IC-72) |
| req-22 | minor | NS-8; 04 §5.10; 05 P23 | applied | `print` shows `(running in background)`; P14's renderer prints the NS-8 line on `artifact_start` (IC-71) |
| req-23 | minor | NS-9; 04 §6.2 | applied | `gptr_config(.scope = NULL)` means the project when a workspace exists, else the session (IC-71) |
| req-24 | minor | 03 §4.1.5, §10.3; 04 §2.2 | applied | the `I()` hint claim is dropped (a function cannot see a condition context; verified by the critic); `s1_batch` removed; a once-per-session `s1_split` message (IC-71) |
| req-25 | minor | NS-12; 03 §7.1, §7.4 | applied | `ask` stays declared in non-interactive `manual` runs (+145 tokens) and calling it stops the run with `gptr_error_noninteractive`; a manual-mode suffix (IC-68) |
| req-26 | minor | 03 §6.8.5, §6.9.3; 04 §11.5 | applied | plan-mode code is never recorded; the block holds one `## Plan:` line (IC-48) |
| req-27 | minor | 04 §7.1; 03 §2.2 | applied | the `out` store is per session, with a spill-file fallback and RNG-free `o` + 6 hex ids (IC-71) |
| req-28 | minor | S-9; 04 §11.5 | applied | best-effort rewrite of top-level `LEFT_ASSIGN` to `=` (never inside call arguments) (IC-48) |
| req-29 | minor | 04 §6.5; S-1 | applied | `gptr_map()` is internal (behind `parallel =`); the export count stays 63 with `gptr_scrub()` (IC-36) |
| req-30 | minor | 04 §9.4 | applied | `gptr$find(sort = "relevance")`; `gptr$grep(sort =)` for files and counts (IC-71) |
| req-31 | minor | 05 P19, P20 | applied | the fake CLI and the CLI leg of INFRA-16 move to P20 (IC-36) |
| req-32 | minor | 03 §2.2; 04 §12.2 | applied | `helper-arch.R` parses `R/` (`test_path()` or `00_pkg_src`) and skips with a message when sources are missing (IC-33) |
| req-33 | minor | 04 §8.5; 03 §8.3 | applied | `--allowedTools mcp__gptr__*` so the gate runs once, in `mcp_message`; `--permission-mode default`; per-session wire logs (IC-65) |
| req-34 | minor | 03 §12.4 | applied | cost rows for `!expr` notes (budget 300), tool additions (about 480), router switches, the Claude-CLI framing (UNCERTAIN), Codex's view of gptr's MCP schemas, images, non-interactive `ask` (IC-73) |
| req-35 | minor | 03 §1.2, §11.1; 04 §10.2, §10.4 | applied | experimental `store` and `evaluator` kinds with the built-ins registered on them; the missing message transform is documented with `compactor`, `context_block` and `request_params` as alternatives (IC-69) |
| req-36 | minor | 04 §7.8 | applied | `.opts$images` sends image files, ggplots and recorded plots as image blocks (532 tokens each) (IC-44) |

## CRAN and Windows lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| cran-1 | blocker | 03 §5.1, §6.9.2; 04 §6.1.5, §7.6, §11.4 | applied | the store is open-append-close (no connection outlives a gptr call); wire log and `.stdin` audited; tests: connection count unchanged, 300 kept sessions, CI with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true` (IC-59) |
| cran-2 | major | 04 §11.4, §7.23; 03 §3.2, §9.1; D-20; conventions §8 | applied | `ps` in Imports; `pid_alive()` with a creation-time check; lint rejects `tools::pskill(` (IC-59) |
| cran-3 | major | 04 §7.8, §3.2, IC-30; 03 §6.9.3; 05 P13, P15, P20 | applied | replay is forced only when `check_running()` and `TESTTHAT` is not `"true"`; mock-server and fake-CLI providers are `offline = TRUE` (setup.R's `GPTR_REPLAY=replay` would have blocked them even under `devtools::test()`); "vignette build" deleted (IC-45) |
| cran-4 | major | 05 P01, P25; 03 §3.3 | applied in part | P01 writes `Authors@R` with `cph` for the maintainer and `person("Mario", "Zechner", role = c("ctb", "cph"))`, `Copyright: file inst/COPYRIGHTS`, `URL`, `BugReports`, `Language`. Declined: writing `VignetteBuilder` in P01, because a `VignetteBuilder` without vignettes is a NOTE (verified in cons-14); P25 adds it (IC-72) |
| cran-5 | major | 04 §6.3, §11.7, §12.2; 03 §6.14; 05 P17, P18 | applied | `user_home()` (USERPROFILE on Windows) and `app_config_dir()` for every foreign-harness path and `${userHome}`; setup.R redirects the home variables; Windows CI test (IC-63) |
| cran-6 | major | 04 §7.1, §7.6, §7.11, §6.2; 03 §6.8.5 | applied | `gptr_can_prompt()` (IRkernel counts) for asks, `ask`, `gptr_confirm()`, `gptr_init()`, egress and the mode block (IC-43) |
| cran-7 | major | conventions §4, §6; 03 §6.6 | applied | `as_utf8()` at every ingress; bare `enc2utf8()` is a lint error outside `utils-encoding.R`; `readLines(encoding = "UTF-8")`; `LC_ALL=C` end-to-end test (IC-62; the corruption was re-verified) |
| cran-8 | major | 03 §5.8, §6.10, §6.12, §8.3; 04 §7.9, §6.3, §12.3 | applied | the `rng_swap()` leaf and hash-derived seeds; `port_candidates()` with bind retries, never `httpuv::randomPort()` (re-verified to change the seed); lint exemption documented; `.Random.seed` identity tests (IC-61) |
| cran-9 | major | 04 §7.20, §6.2; 03 §6.7, §8.3 | applied | `cli_find()` with a `gptr.cli_path` override and known install locations; the `claude.cmd` shim refused (so empty argv strings are safe); `status()` reads caches only; Codex on Windows read-only until its sandbox probe passes (IC-65) |
| cran-10 | major | 04 §12.2, §12.4, §7.4 | applied | `rscript_path()` for every helper, fixture and fake CLI; lint rejects bare `R`/`Rscript` commands (IC-60) |
| cran-11 | minor | 04 §3.1, §7.4; 03 §6.13, §6.15 | applied | `supervise_default()` resolves the option (default per safe-9: TRUE except under check) (IC-60) |
| cran-12 | minor | conventions §4 | applied | the "files the package writes" bullet adds named or confirmed documents and approved tool writes (IC-72) |
| cran-13 | minor | conventions §4, §8 | applied | `on.exit()` in `R/`; withr only in tests; lint rule for `withr::` in `R/` (IC-72) |
| cran-14 | minor | conventions line 107 | applied | the example is now a literal `\u00e9` escape and the file is ASCII (IC-72) |
| cran-15 | minor | 04 §7.9; 03 §6.12 | applied | `pdf(NULL)` with the display list when no device is open and no human sees one; the prior device restored; no-`Rplots.pdf` test (IC-67) |
| cran-16 | minor | 04 §1.2, §12.2; 05 P01; conventions §7 | applied | `gptr.project_root` / `GPTR_PROJECT_ROOT` set by setup.R; `.Rbuildignore` gains `CLAUDE.md`, `AGENTS.md`, `.claude` (IC-63, IC-72) |
| cran-17 | minor | 03 §6.9.3; 04 §7.15, §11.8, §11.1 | applied | `file.rename()` retries then an in-place write after an md5 re-check; `path_key()` for bindings, trust, locks and site matching (IC-51) |
| cran-18 | minor | 04 §12.2; 03 §3.4 | applied in part | the MCP fixture's HTTP transport and `gptr_mcp_serve()` bind 127.0.0.1 through httpuv with RNG-free ports. Declined: moving the SSE mock to httpuv, which cannot stream a response without promises (excluded by the conventions); the mock stays on `serverSocket()`, lives for one test under `skip_on_cran()`, and answers only per-run token paths (IC-71) |
| cran-19 | minor | 03 §6.13; 04 §3.1; 05 P18, P20 | applied | every child-process pool is capped at 2 under check; every process-spawning test calls `skip_on_cran()` (IC-60) |
| cran-20 | minor | 04 §11.6; 03 §5.7 | applied | Windows reserved ids refused; snapshots `data/001.rds`, ... with the mapping in `artifact.json` (IC-63) |
| cran-21 | minor | 04 §6.6; 03 §7.5 | applied | describers for packages outside Suggests use only base generics and slots, guarded by `isNamespaceLoaded()` (IC-71) |
| cran-22 | minor | 05 how-to-read, P01, P25 | applied | the expected check result is no NOTE apart from the maintainer line (gptr 0.7.0 is on CRAN); P25 records the reverse-dependency check (IC-72) |

## Consistency lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| cons-1 | blocker | 05 how-to-read; 04 §7.0, §7.1; 03 §2.2, §3.1-3.2 | applied | option (a): `R/aaa-state.R` (P01) holds `the`, `on_load()`, `on_unload()`, the service table, the redaction hook and `%||%`, and collates first; M0 exit checks `R CMD INSTALL` (IC-32) |
| cons-2 | major | 03 §2.2; 04 §12.2 and the consumer columns | applied | the kernel SDK allowlist in `helper-arch.R`; trust through a service (IC-33; same fix as req-13) |
| cons-3 | major | 04 §7.1-7.8 | applied | `redactor_set()` in P01; the `trust.get` (fallback untrusted) and `identifier.resolve` services; `gptr_agent()` stores raw expressions; P06 gets tools only through `prompt.freeze` (IC-34) |
| cons-4 | major | 04 §7.0, §10.6; 05 P02 | applied | services `ctx.kernel`, `ctx.input`, `secret.lookup`, `eval.r`, `describe`, `ns.names`, `router.call`, `session.add_tools`, `search.sources`; `ctx_new()` fetches them lazily (IC-34) |
| cons-5 | major | 04 §6.7, §6.8; IC-21, IC-22 | applied | signatures unified; `build = NULL` with a per-transport validator; provider fields `status`, `aliases`, `local`, `offline`, `rate`; P02 acceptance: every §6.8 example runs (IC-35) |
| cons-6 | major | 04 §6.6; 05 P08 | applied | `gptr_prob()` moves to P13 (`s1-types.R`), so the M1 examples need no later plan (IC-36) |
| cons-7 | major | 04 §5.3; 05 P08, P10; 03 §3.2 | applied | P08 owns every `gptr_gateway` method; P10 provides `ns.resolve`/`ns.names` (IC-36) |
| cons-8 | major | 04 §9.4, §7.22; 03 §3.2; 05 P22 | applied | `gptr$out()` is P10's only (IC-36) |
| cons-9 | major | 04 §9.1, §9.4, §10.1-10.2, §7.10, §5.3 | applied | exposure is a default visibility; one spec per capability with `execute` and `fun`; presets choose direct tools from any spec with an `execute`; `$` resolves any un-namespaced spec with a `fun` (IC-37) |
| cons-10 | major | 04 §7.9, §10.3, §7.7; 03 §7.4; 05 P07 | applied | placement `both` (IC-38; same fix as req-9) |
| cons-11 | major | 04 §6.1.1; 03 §4.1.1 | applied | route order: `team` 15 and `fanout` 16 before `nested` 20, with nesting inherited (IC-39) |
| cons-12 | major | 04 §7.0, §6.5; 03 §4.1.1, §6.4 R10 | applied | `the$last` holds the last session strongly (shells hold no frames or user objects) (IC-71; re-verified that a weak one is collected) |
| cons-13 | major | 05 P01; conventions §4; 04 §12.3 | applied | `.lintr` with `operator = c("=", "<<-")` and an S3-method regex; `<-` found through parse tokens (IC-72) |
| cons-14 | major | 05 P01, P25; 03 §3.5 | applied | P25 adds `VignetteBuilder: knitr` with the vignettes, a named exception (IC-72) |
| cons-15 | major | 05 P19, P20; 03 §6.13, §6.18 | applied | the CLI leg of INFRA-16 and the fake CLI are P20's; P19 tests inline and worker (IC-36) |
| cons-16 | minor | 05 P17, P09, P07 | applied | P17 depends on P10; P09 acceptance 3 uses `eval_r()` and the `gptr()` form moves to P10; P07 baselines use a fixed T1 fixture and compare only P07's texts byte for byte (IC-36, IC-68) |
| cons-17 | minor | 04 §7.1, §7.8, §5.3, §6.7, §7.12; 03 §2.2 | applied | `setting_get()` is the only reader; `ns.resolve`; `check_adapter()`; `registry_all("route")`; `fake_classify(model, state, questions, opts)` (IC-71) |
| cons-18 | minor | 03 §5-§11 vs 04 | applied | 03's signature blocks now point to 04; the listed drifts fixed (reactor and evaluator signatures, tool-result fields, `detached`, queue `blocks`, `tool_call` error = block, doc-format fields, project-settings wording, `gptr_warning_deprecated`, experimental kinds incl. `route`, the manifest's `trials/search`, `tools.presets`) (IC-71) |
| cons-19 | minor | register D-28; conventions §3-§5 | applied | D-28 = 63; the example predicate, the class-list pointer, `on.exit()`, the `:::` wording, the layout (`aaa-state.R`, `inst/templates/`, `inst/extdata/`) and `LICENSE.md` ownership fixed (IC-72) |
| cons-20 | minor | 04 §7.2, §6.2, §10.4, §2.2, §4.2, §3.1, §11.2 | applied | `child_env` resolves `first`; `project_trust` is a first decision and `gptr_trust()` emits nothing; `egress_ack` is P08's; message source enums unified; one knob per limit (`gptr.subagents.*`); `gptr_parallel()` has its own default (IC-71) |
| cons-21 | minor | 04 §6.2, §7.20 | applied | `gptr_providers(check = FALSE)` never spawns a process (IC-65) |
| cons-22 | minor | 04 route 50; 03 §6.9.3 | applied | replay advances the piped session in place; `identical()` test (IC-46) |
| cons-23 | minor | 04 §5.1, §6.1, §6.5, §12.2 | applied | agent names equal to accessors are rejected; `gptr_jobs()` moves to P04; `pkgload::load_all()` appears only inside generated script text (IC-71, IC-36) |

## Research-fidelity lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| fid-1 | major | 03 §7.3; 04 §9.3 | applied | no shipped text recommends `str()`; `gptr$describe(x)`, `dim()`, `head()` instead; a P07 test forbids `str(` in texts and skills; the skill states the cost (IC-67) |
| fid-2 | major | 03 §6.4 R8, §6.12; 04 §2 R8; 05 P09 | applied | the evaluator clears every `withVisible()` result in place; rows `L$a`, `(x)`, `get("x")`, `x@slot`, `x[["a"]]` (IC-67; re-ran wv4/wv6: 1 copy before, 0 after) |
| fid-3 | major | 03 §5.1, §6.9.2 | applied | same fix as cran-1 (IC-59) |
| fid-4 | major | 04 §7.3, §7.4; 03 §6.5 | applied | `child_env()` returns the complete vector; `child_env_callr()` gives callr's `NA` form; P03 test (IC-60; re-verified that processx rejects `NA`) |
| fid-5 | major | 04 §3.2; 03 §6.5 | applied | every profile points `R_ENVIRON_USER`/`R_PROFILE_USER` at empty files and drops `R_ENVIRON`; P03 test with an Rscript child (IC-60) |
| fid-6 | major | 04 §7.4, §8.2; 03 §6.6-6.7, §6.13 | applied | `encoding = "UTF-8"` for `proc_spawn()` and every `callr::r_bg()`; raw stdin writes; `LC_ALL=C` pipe-path test (IC-60) |
| fid-7 | major | 03 §8.3, §10.4; 04 §8.5; 05 P20 | applied | codex argv with `--skip-git-repo-check`, `-m`, `-C`, `default_tools_approval_mode="approve"`, `required=true`; resume with `-c sandbox_mode=`; the evidence citation corrected; a live test in a non-git directory (IC-65) |
| fid-8 | major | 04 §3.2; 03 §6.5, §8.3 | applied | G6 §3.7's lists verbatim (enclosing-agent variables, `ANTHROPIC_PROFILE`, `CODEX_MANAGED_*`, ...); a `--bare` capability probe; an `apiKeySource` check that aborts with `gptr_error_billing` (IC-65) |
| fid-9 | major | 03 §6.10, §6.15; 04 §6.3 | applied | `with_seed_preserved()` around chromote, shiny and httpuv; RNG-free ports; `.Random.seed` tests (IC-61) |
| fid-10 | minor | conventions line 107 | applied | same fix as cran-14 (IC-72) |
| fid-11 | minor | 04 §8.3; 03 §6.1 | applied | LF, CRLF and lone CR with a held CR, BOM stripped, last `event:` wins, `id`/`retry`; new SSE test cases (IC-64) |
| fid-12 | minor | 03 §6.1, §8.2; 04 §8.2, §7.13 | applied | a static provider `rate` (typesafe 40 requests and 1e5 tokens per second) in the token bucket; process-wide System 1 admission (IC-64) |
| fid-13 | minor | 04 §8.2; 05 P04 | applied | a locale-independent `parse_http_date()` with backoff fallback; tests under `de_DE` and `retry-after: soon` (IC-64) |
| fid-14 | minor | 03 §6.18; 04 §8.1 | applied | model capability `forced_tool_choice`; `returns =` through `output_config.format` on Anthropic; `gptr_check()` rejects list `tool_choice` where unsupported (IC-71) |
| fid-15 | minor | 04 §7.9; 03 §6.12 | applied | `q`/`quit` flagged in any position; alias tests (IC-67) |
| fid-16 | minor | 03 §4.2; 05 P22 | applied | knitr shell engines run through `gptr$sh()` with the helper environment and a timeout (IC-67) |
| fid-17 | minor | 03 §6.14; 04 §7.18; 05 P18 | applied | refuse metadata without S256 PKCE; `iss` validation with gptr's own reader; state and redirect checks; negative mock cases (IC-71) |
| fid-18 | minor | 04 §7.4 | applied | non-blocking buffered stdin drained by the reactor with a deadline; 4 MB echo test (IC-60) |
| fid-19 | minor | 05 P17; conventions §4 | applied | string frontmatter keys keep their source text; `%||%` defined internally (IC-71, IC-32) |
| fid-20 | minor | 04 §6.4, §7.4; 03 §6.13, §6.15 | applied | `stop_requested` in the job table; an exit after a requested stop is `stopped`/`aborted` (IC-60) |
| fid-21 | minor | 03 §6.1, §6.2; register C-30, D-13 | applied | the PIPEWAIT figures are the fact-check's; `later_fd` on Windows is marked LIKELY (IC-71) |

## Plugins and tokens lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| plug-1 | major | 04 §10.2 router, §7.8; 03 §11.1; 05 | applied | the router contract gets messages, per-branch state, the previous model and the reason; P06 calls it before each request through P08's `router.call`; 2 s timeout with fallback; `model_change` and `gptr.router` entries; P13 ships a tested Jev router example; cost stated (IC-69) |
| plug-2 | major | 03 §7.3; 04 §9.3, IC-27; 05 P07 | applied | `<rules>` comes from the active tools' guidelines; `<r_session>` from P07's core plus fragments (`prompt_section(parent =)`); `documents`, `artifacts`, `system1` are registered by P15, P23, P13; the readonly preset is 115 tokens shorter (measured) (IC-68) |
| plug-3 | major | 04 §7.0; 03 §2.2 | applied | services are owned by built-ins and filtered with them; a `service` kind for third parties; literal `ext_service_get()` calls visible to the layering test; `ctx$eval()`, `ctx$describe()`, `ctx$tokens()`; a `search_source` kind (IC-34, IC-69) |
| plug-4 | major | 04 §11.11, §7.19 | applied | the worker spec carries rank-0 and user records, plugins and filters, re-registered by `worker_main()`; the serialisability rule; P19 test (IC-69) |
| plug-5 | major | 03 §12.7, §3.5; 05 P01, P07, P24, P25 | applied | a CI `bench` job; the runner and NS-2/NS-3 in P07 (M1); per-plan fixtures; every gate in P24; a live release calibration with tolerances in P25 (IC-73) |
| plug-6 | major | 03 §6.12, §12.2, §12.4; 04 §5.8, §7.9, §3.1 | applied | `gptr.r_max_images` = 3; later plots stored for `gptr$plot(k)`; image tokens in the budget; elision above provider limits; P09 test (IC-67) |
| plug-7 | major | 04 §1.1, §6.1, §6.8, §7.7, §9.3, §9.4; 03 §11.1; 05 P24 | applied in part | `backend`, `gptr$app(kind =)`, `frontend` and `preset` are validated against the registry; a `preset` kind; a `frontend` setting; P24's `test-s11-conformance.R`. Declined: making `mode` a registry kind, because the permission model (levels x modes, `ask_human`, plan allowlist) is defined on the four modes; plugins extend it through `policy` records (IC-69) |
| plug-8 | major | 04 §6.1, §7.8; 03 §11.1 | applied | `.opts` entries named by a plugin namespace, validated by its settings; named `gptr()` arguments documented as context (IC-44) |
| plug-9 | major | 04 §10.6, §10.4, §4.9; 03 §6.11 | applied | `ctx$set_model()`, `ctx$add_tools()` with `session_add_tools()` (also for continuations with `tools =`), tool `render`, a `renderer` kind, the `request_params` patch event (IC-69) |
| plug-10 | minor | 03 §7.2, §12.3-12.4; 04 §9.2 | applied | four frozen `r` schema variants (198 -> 189/170/138/119 tokens, measured) (IC-68) |
| plug-11 | minor | 04 §5.3, §7.10, §9.1, §9.4, §7.22; 03 §3.2 | applied | reserved member and namespace names; plugin members require a namespace; `out` has one owner (IC-37, IC-36) |
| plug-12 | minor | 04 §11.15, §10.2 | applied | an additive `risk_rule` kind (highest level wins; lowering explicit) (IC-69) |
| plug-13 | minor | 03 §11.3; 04 §6.1.3, §6.8 | applied | package-facing examples use strings and `gptr::gptr_agent()`; `gptr_check()` flags bare identifiers in packages (IC-42) |
| plug-14 | minor | 04 §6.8, §10.2 | applied | `order` in the signature; turn blocks deduplicated by text hash (`ctx$input$last_hash`) (IC-35, IC-38) |
| plug-15 | minor | 03 §7.3, §12.1-12.2 | applied | `[skill:<name>/SKILL.md]` pseudo-paths that `read` resolves (152 -> 143 tokens, measured) (IC-68) |
| plug-16 | minor | 03 §11.1, §11.4, §12.6; 04 §10.6 | applied | `ctx$tokens()`, `gptr_check(tokens = TRUE)`, truncation policies and catalog formatters recorded as v1.x kinds (IC-69) |
| plug-17 | minor | 03 §6.11, §7.1, §8.4; 04 §11.2 | applied | shipped `tools.presets` defaults for Gemini 3 and Haiku 4.5, gated by `cache_min` and break-even (IC-73) |
| plug-18 | minor | 03 §12.1, §12.8, §12.5 | applied | o200k and projected Claude tokens both reported; NS-1 is about $0.025 in Claude tokens (IC-73) |

## Safety and failure lens

| # | Sev. | Location | Verdict | What changed (or why a sub-proposal was declined) |
|---|---|---|---|---|
| safe-1 | blocker | 03 §6.8.1-6.8.2, §11.1; 04 §7.6, route table, §3.1, §6.2, §6.5, §10.1, §10.3; 05 P06; D-11 | applied | the gate fails closed without a mode policy; the permission kernel cannot be filtered out (escape only through `gptr.unsafe_no_permissions` set outside a run); safety options snapshotted per run; `control` category at level 4 plus `run_current()` checks in the exports; mode inheritance for every route during a run; worker requests re-classified by the parent; adversarial e2e tests (IC-53) |
| safe-2 | blocker | 04 §11.1-11.3, §6.2; 03 §5.9, §6.8.3, §6.9.1, §6.9.3, §6.10 | applied | remembered answers, the transcript target and record consent live in `R_user_dir("gptr", "config")/projects/<hash>.json`; a legacy `.gptr/settings.local.json` only adds deny/ask in trusted projects; targets validated; clone test (IC-52) |
| safe-3 | major | 03 §6.10, §7.3; C-20; 04 §4.2, §10.2 | applied | `trusted="false"` rendering and a `<context>` sentence (+35 tokens); the trust question asked once; non-interactive `auto`/`edits` runs omit untrusted instructions, skills and agents; only trusted-project skills catalogued; project-file updates are user-role `project_instructions_update` context blocks; operator authority only from rank >= 3 (IC-52) |
| safe-4 | major | 03 §6.8.1, §10.8; 04 §6.6, §11.15 | applied | level 0 means known read-only; unlisted non-base functions are level 1; a risky-package list at level 2 or more; plan mode runs only allowlisted read-only calls; 18 §2.5's blind spots in P11 acceptance (IC-54) |
| safe-5 | major | 04 §7.1, §9.4; 03 §6.8.1, §11.1 | applied | path classes `control` (level 4: `.gptr` control files, the user config directory, `.Rprofile`, `Makevars`, git hooks) and `instructions` (level 3: AGENTS.md, CLAUDE.md, vignette, skills, prompts) for every write path; changed control files need confirmation (IC-54) |
| safe-6 | major | 03 §6.8.2; 04 §7.6, §10.4, §10.7 | applied | `ask` vs `ask_human` tiers; a hook's allow for `ask_human` is ignored; `modify` re-checked once; only `r(secret:NAME)` pre-approves the secret guard (IC-53) |
| safe-7 | major | 04 §4.2, §10.6; 03 §6.2; C-16 | applied | relays by source: user sources as operator relays, extensions and agents as user-role data, refused from model code; test (IC-55) |
| safe-8 | major | 04 §8.2, §7.21, §6.3; 03 §2.3, §6.1, §6.2; C-30 | applied in part | pump depth; `run_now(0)` only in the outermost pump (or for a served CLI child, with a busy error for others); background pump a no-op at depth; asks never prompt from callbacks (`waiting` status, or a denial for served requests); an idle-tick notice. Declined: answering httpuv requests asynchronously by queuing them, which needs the promises package (excluded by the conventions and S-10's dependency discipline) (IC-57) |
| safe-9 | major | 04 §3.1, §11.11; 03 §6.7, §6.13, §6.15; 05 P04, P19, P20 | applied | supervision TRUE except under check; workers exit on EOF, EPIPE or a dead parent; tree markers and a mandatory orphan sweep; SIGTERM test; the 03 snippets fixed (IC-60) |
| safe-10 | major | 03 §6.9.2; 04 §7.6, §11.4; 05 P06 | applied | LF plus `gptr.recovered` before new entries; the reader skips bad lines and re-parents; ps-based locks with creation time; a 10-minute heartbeat; the extended INFRA-13 test (IC-59) |
| safe-11 | major | 03 §12.6, §6.13, §8.3; 04 §6.1, §7.6, §3.1, §8.5; D-05, D-12 | applied | default ceiling of 5 USD and 2e6 tokens per top-level call (ask to extend, or stop); root-charged hierarchical budgets; caps on nested calls per evaluation and on System 1 elements; claude `--max-turns`/`--max-budget-usd`; a Codex turn counter and wall clock; a notice when sourcing makes live nested calls (IC-66, IC-65) |
| safe-12 | major | 03 §8.3; 04 §8.5 | applied | plan/manual/edits map to `read-only` (file changes through gptr's gated tools); `auto` to `workspace-write` with control-file hashes and a checkpointer walk; the Windows sandbox probe; the notice (IC-65) |
| safe-13 | major | 03 §6.1, §6.5; 04 §8.2 | applied | `followlocation = 0L` on every transfer; 3xx is a classed error, never retried; redirect mock in the secrets test (IC-64) |
| safe-14 | major | D-22; 03 §6.5; 04 §11.1, §11.6; 05 P03, P24 | applied (checker folded into one export) | `gptr_scrub(paths, dry_run, error)` is exported, and its `error = TRUE` mode is the pre-commit check, so no separate `gptr_check_secrets()` is added (the export count stays 63); late-registration warning; child output persisted only through the redactor; MCP logs in `tempdir()`; new sinks in the e2e test (IC-70) |
| safe-15 | major | 03 §6.9.3; 04 §6.1.4, §11.5, §11.9 | applied | an `args=` header key; the S2 key includes it; parameterised-report test (IC-45) |
| safe-16 | minor | 03 §6.9.3; 04 §11.9; 05 P15 | applied | the sidecar holds block upserts with a base md5, is flushed per call, is recovered by the next call without overwriting user edits, is never pruned automatically and respects document locks (IC-51) |
| safe-17 | minor | 04 §6.2, §11.1, §11.14; 03 §6.16 | applied | short `mkdir` locks with pid liveness for settings, trust, MCP and project files; pid-aware document locks; blob GC across the project's sessions (IC-71) |
| safe-18 | minor | 03 §6.8.3, §6.3; 04 §7.11 | applied | approval displays escape control, bidi and zero-width characters; the prompt lists every flagged call and `+N more lines` (IC-53) |
| safe-19 | minor | 03 §6.8.5; 04 §7.11 | applied in part | the plan goes only to the next top-level call (not nested, not in a run or loop); an intervening call discards it; the step list is printed. Declined: requiring an interactive session or a pipe from the plan session, which would break NS-12's two consecutive script statements (IC-56) |
| safe-20 | minor | 03 §6.11, §12.2; 04 §7.7 | applied | a floor check at freeze with reduced re-injection budgets or refusal; a 20%-growth rule between threshold compactions (IC-71) |
| safe-21 | minor | 04 §11.1, §11.9; C-31 | applied (salted hash) | S1 values store the question's hash, not its text; input hashes are salted with a committed per-project salt, which serves the stated goal (defeating precomputed dictionaries) as an HMAC would; `transcripts/` gitignored; PHI named on the security page (IC-70) |
| safe-22 | minor | 03 §6.15; 04 §11.6, §7.23 | applied | a per-launch 128-bit token (openssl, else `/dev/urandom`, else a notice on Windows); static checks flag secret-file reads (IC-71) |
| safe-23 | minor | 03 §6.10; 04 §6.2, §11.8 | applied | trust records a fingerprint of the trust-gated files; changes are shown and asked again, or ignored non-interactively (IC-52) |
| safe-24 | minor | 04 §6.5, §7.6; 03 §6.16 | applied | foreign session files resume with a freshly frozen prompt and imported user turns; restores confined to the project and `tempdir()` (IC-52) |

## Declined sub-proposals (summary)

| Issue | Declined part | Reason |
|---|---|---|
| cran-4 | writing `VignetteBuilder: knitr` in P01 | a `VignetteBuilder` without vignettes gives a check NOTE (verified in cons-14); P25 adds it with the vignettes |
| cran-18 | running the SSE mock on httpuv | httpuv cannot stream a response without promises, which the conventions exclude; the mock keeps `serverSocket()` with token paths and one-test lifetime under `skip_on_cran()` |
| plug-7 | a registry kind for permission modes | the permission model (levels x modes, `ask_human`, the plan allowlist) is defined on the four modes; plugins extend behaviour with `policy` records |
| safe-8 | answering MCP-server requests asynchronously by queuing them | synchronous httpuv handlers can only defer through promises (excluded); the pump-depth rule and a retryable busy error give the same isolation |
| safe-19 | handing a plan only to interactive calls or pipes from the plan session | NS-12 runs `gptr("...", mode = plan)` and `gptr("Go ahead ...", mode = auto)` as two script statements; the next-top-level-call rule keeps that working |

## Files changed

- `dev/spec/04-interface-contract.md`: §15 added (IC-32..IC-73). Edited in place: header, §0.3, §2.2, §3.1-3.2, §4.2,
  §4.6, §5.1, §5.3, §5.10, §6.1-6.8 (including the new `gptr_scrub()`), §7.0-7.23, §8.1-8.5, §9.1-9.4, §10.1-10.6,
  §11.1-11.15, §12.2-12.4, §13 and §14.
- `dev/spec/03-architecture.md`: header, §1.2-1.3, §2.2-2.3, §3.1-3.5, §4, §5, §6.1-6.18, §7.1-7.4, §8.2-8.3, §9.1,
  §10, §11, §12 and §13.
- `dev/spec/05-plan-decomposition.md`: how-to-read, milestones, dependency graph and table, and a "Review amendments"
  bullet plus acceptance additions in P01-P25.
- `dev/spec/01-decision-register.md`: Final decisions D-08, D-09, D-11, D-12, D-13, D-14, D-15, D-20, D-22, D-27,
  D-28, C-3, C-20, C-30, C-31, and a "Review amendments (2026-09-30)" block.
- `dev/plan/00-conventions.md`: sections 2-8 (ASCII-only now, with a literal `\u00e9` escape example).
