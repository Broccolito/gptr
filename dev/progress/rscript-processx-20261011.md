# Bounded Rscript/processx launcher replacement — 2026-10-11

The maintainer authorized replacing GPTR's two callr launches: workers (P19) and Shiny
serving (P23). This is a tests-first change in `codex/skipped-platform-tests`. All new
native RPX01–07 acceptance and fresh plan gates are PENDING. Tests-first checkpoint `1cabcfc` is
pushed. The initial Mac helper packet is expected RED: 5 test errors, 0 passes/test warnings/
skips, caused by missing `proc_rscript`/library helper and `.on_spawn`. Its separate outer
startup warning says testthat was built under R 4.5.2; dependency remedy remains pending.
Evidence: ignored `dev/.validation/rscript-processx-20261011/red-launcher.log` in the candidate.
The focused Mac working-tree helper now passes 33 assertions with 0 failures/test warnings/
skips in `green-launcher.log`; the outer advisory remains. Its runtime commit has not yet been
nominated. Core launcher/callback source preparation is ongoing; worker/Shiny native parity
and the complete replacement remain unproved. No dependency removal has occurred. DESCRIPTION, installed
runtime and every other Import stay unchanged by this documentation checkpoint.

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

Root/worker/artifact lanes are preparing the remaining tests; the two-file tests-first
checkpoint above precedes the launcher source work. Review/commit this plan checkpoint
before proceeding with worker/Shiny migration. Keep meaningful errors, unexpected skips,
warning classes, missing/duplicate/zero-assertion cases and unknown settlement fatal. Use existing bounded
supervisors; record exact source/library/artifact identities, observed memory scope, elapsed
and child cleanup. Do not infer a Mac pass from hosted Windows/Linux or a devtools pass from
installed-package tests.

At the retained coordinator 22:12 PDT snapshot, load was 15.04/19.74/18.26, CPU idle 26.72%,
RAM 111 GiB used/16 GiB unused, swap 21717.94 MiB (sampled delta 0), disk 302 GiB and no
recorded thermal warning. Local-heavy work stays HELD on load. The shared Ollama model,
user workspace and libraries remain untouched. Native Mac execution waits for clearance.

## Required plan checks after this edit

Root should run the [four consolidation checks](../research/assets/consolidation-tools/README.md)
serially on the exact reviewed/committed source in the hosted Linux lane. The existing bounded
controller executes index, extract, R parse/style, then single-worker lint; it verifies the exact
P01–P25 set and equal before/after source hashes. Use a fresh output path (replace REVIEWED_SHA):

```sh
python -I -B dev/ci/test-check-plans.py
python -I -B dev/ci/check-plans.py \
  --out dev/.validation/rscript-processx-20261011/plan-checks-REVIEWED_SHA
```

The controller caps each stage at 600 seconds, owns its process group, disables live tests,
and caps BLAS/build/lint workers at one. It retains stage logs and source provenance; soft
index errors, missing blocks, parse/style problems and any lint are fatal. Historical index
warnings need the existing classification plus review of new findings. This fresh run is
PENDING; old successful gates do not validate this edit. The controller indexes P01–P25,
so independently review this living-plan/contract text and links as well. No local R job was run.
