# Bounded Rscript/processx launcher replacement — 2026-10-11

Current candidate is `codex/skipped-platform-tests`, pushed through `3cf34ef9b865aeba1bb163a8fde0f779ec36adb8`.
Runtime checkpoint `963665c` replaces both launches; test/CI checkpoint `f0915fb` adds
native source and installed execution, complete-parent-state, protocol and lifecycle controls.
Independent source review is clear. callr remains imported until native acceptance passes.

Actual Mac focused packet: 156 assertions, 0 failures/test warnings/skips (`focused-final.log`).
This includes the final launcher failure/interrupt guard and worker settlement regressions.
The external startup advisory remains: testthat was built under R4.5.2 but this host runs
R4.5.0. It is not a warning-free full validation. Native Mac/Windows source+installed worker,
Shiny, secrets, architecture, supervision and browser-cleanup checks are ONGOING in
[run38208873408](https://github.com/Broccolito/gptr/actions/runs/38208873408), exact `3cf34ef`.
No result is inferred from workflow dispatch or source review.

Fresh four-stage plan checks on exact `a9d8a2242218aa244f6182bea7fd807aba6f6c3b` PASSED:
25 plans, 1523 extracted blocks, 770 R blocks, 0 parse/style problems/lints, 39 equal
before/after source hashes. The index retains90 historical warnings, distinct from runtime
warnings. Raw artifacts were downloaded and inspected. Source/living-plan link review passed.

Tests-first checkpoints `1cabcfc` and `c36b13e` retain baseline failures and the cleanup
contracts. The initial helper RED is5errors/0passes from missing helpers and callback;
33-assertion initial GREEN predates the final156-assertion packet. Historical logs are intact.
The comprehensive readiness request is active: remaining storage, frontend/provider/compaction,
security, documentation and exact-archive package checks follow alongside RPX01–07.

## Scope and phases

1. Freeze the current source/library and append tests before implementation. Test the actual
   worker and artifact paths in installed-package and devtools contexts, with offline providers
   and independent numeric/object/HTTP oracles. Retain baseline RED and scaffold failures.
2. Implement two fixed trusted scripts through existing `proc_spawn()` and absolute
   `rscript_path()`, with `--vanilla`, UTF-8 and complete `child_env()` passed directly.
   Set captured `.libPaths()` before worker namespace load; preserve private worker spec/
   result serialization and JSONL. Keep Shiny's serving function self-contained without
   loading gptr. No generic callr clone, namespace hook or serialized payload in argv.
3. Prove native macOS/Windows parity and Linux regression: exact parent objects/options/
   raw environment/cwd/RNG/connections after construct, success, startup error, cancellation
   and cleanup;
   permitted empty/absent/nonempty/case/UTF-8 child values, library/startup/PATH/key filtering;
   record R/processx essential-variable restoration and platform case-matching separately;
   paths with spaces, split UTF-8, stdout/stderr, partial writes, EOF, permission/exports,
   loopback ready/HTTP/token/revision, unsupervised parent death and watchdogs. R Core startup
   normalization stays distinct from the parent preservation oracle; invalid native seeds
   remain scaffold evidence, never preservation proof.
4. Retain exact PID/creation-time/marker ownership and foreign sentinels. Unknown/failed
   launch or settlement must retain a recoverable owner/job and private files. In particular,
   watcher cancellation must not hide a failed first kill, and a partial artifact launch must
   not lose its owner while unwinding. Preserve the original condition, bounds and statuses.
5. Only after RPX01–06 acceptance, remove callr and its unused adapter; verify zero production
   callr use and unchanged remaining dependency/pure-R contracts. Rerun metadata/docs,
   affected native suites and exact-archive CRAN/release gates (RPX07).

Detailed cases are [RPX01–07](../TESTING_PLAN.md#bounded-rscriptprocessx-replacement--accepted-2026-10-11).
The narrow [architecture amendment](../spec/03-architecture.md#9-dependencies-d-20-d-21-d-23)
and [IC-60](../spec/04-interface-contract.md) govern the launcher change. Numbered P19/P23
examples remain baseline history. No new Import or compiled code is authorized.

## Historical proof and current boundary

Exact callr experiment source `189e2025db66518d56c0eb8d22beb3338d04cd92`,
[run 38182630356](https://github.com/Broccolito/gptr/actions/runs/38182630356), passed required
native Windows/Linux gates: patched strict six cases 187P per host, upstream nine 36P,
and four unchanged compatibility files/20 titles 49P for each stock/patched host profile.
All have zero failures/warnings/skips/fixture errors. All 30 owned families settled with
zero survivors/controller warnings. See [the full callr ledger](skipped-platform-tests-20261010.md).
Those private upstream installs prove selected callr behavior; they do not prove GPTR's new
entrypoints, a released dependency fix, production adoption or universal startup-variable
restoration. CE05/06 admissions and CE07 publication/release integration remain OPEN.

The runtime source is committed; native acceptance and dependency retirement are pending.
Require meaningful assertions, fatal unexpected skips/warnings, exact provenance and owned
settlement. No local model/GPU workload was started; shared Ollama and main dirty tree remain
preserved. At22:40PDT load15.20/14.18/14.73, CPU55.60%idle, RAM117GiBused/10GiBunused,
swap21645.94MiB with sampled0swapout,301GiBdisk and no thermal warning keep local-heavy
work held. Small serial offline regressions and hosted native checks continue.
