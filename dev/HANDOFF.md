# GPTR implementation handoff

Updated: 2026-10-03. State: active implementation, P01 not yet complete.

## Resume procedure

1. Inspect `git status`, current branch, worktrees and latest remote state.
   Preserve uncommitted work; do not reset or materialize old plan snippets over it.
2. Read `PROGRESS.md`, `DEVIATIONS.md`, active `progress/Pxx.md`, `CLAUDE.md`,
   conventions, definitive contract (including IC-74), and the active plan.
3. Confirm agent ownership before editing. Read the recorded exact command and
   output for the latest check; rerun only when source or environment warrants it.
4. Continue the earliest incomplete dependency. Do not advance milestone tags
   on partial/local-only evidence.

## Known preparation facts

- Working branch: `codex/gptr-1.0-implementation`; base `17a95dd`.
- No `.codegraph/` index. Do not initialize one without the maintainer's decision.
- Use `Rscript --vanilla`; P01 removes the obsolete `.Rprofile`.
- A project-local development library will isolate pinned/missing tooling from
  the user's existing library. Its location and commands belong in local setup
  notes; keep the library ignored and excluded from R builds.
- Local secrets are `.secrets/jev-key.env` and `.secrets/llm-passwords.env`.
  Never print their values. Private `LOCAL_SETUP.md` and the raw discussion stay ignored.
- Ollama 0.35.1 + Clef Flash/Qwen synthetic API tests passed before implementation.
  That does not verify a GPTR provider implementation.
- Follow the host's concurrency limits. Start with a few useful lanes; at most
  two internally parallel local jobs, bounded workers, and one GPU workload.

## Next concrete work

The earliest open gate is hosted P01 portability, now being revalidated together
with the completed P02 implementation. Initial immutable commit `e2a5f57` passed R CMD check but exposed the standalone
supervisor-FIFO gate mismatch. Corrected immutable checkpoint
`55ec31dc99f2d991b4b2d495320b76af25735bf6` now passed 4,474 assertions,
the complete connection comparison, and R CMD check with 0 errors/warnings/notes.
Its local receipts and raw logs live
under ignored `dev/.validation/P02-acceptance/`. This includes the installed-test
mock correction (`d4aabfb`) and Windows/old-R harness corrections (`285deec`).
The previous hosted run at `eea1e36` cannot validate them. The corrected checkpoint is published to draft PR #4, hosted run
`37167848633`; record exact-SHA hosted results when available.

P03 committed tasks are 1–4 and 6–11. P04 committed tasks are 1–9. Read current
ownership in `PROGRESS.md` before edits. P03 scrubber integration and P04 wire/HTTP/retry integration remain. P05 usage is
committed, and its provider/catalog lane may proceed on actual stable
prerequisites; no full P05 acceptance is implied.

Use `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla` for checks, with
roxygen2 7.3.3. The reusable `dev/ci/isolated-check.R` sets temporary home,
config, cache and project paths **before** loading package code. This matters
because orphan sweeping runs before testthat setup. Its `connections` action
explicitly runs the full suite and compares connection tables. For an archived
snapshot, set an absolute library path and record the external runner used.
Only synthetic loopback servers and owned child processes are needed. Keep
live providers disabled, and never load `.secrets/` for offline gates.

Latest component details belong in `dev/progress/`; inspect those and Git rather
than assuming an agent's intended commit happened. The README/About and draft
PR #4 remain development status. Completed plans remain 0/25 until the recorded
plan gates, including hosted checks where required, are actually closed.

## Model allocation requested by the maintainer

Use `gpt-6-astra` for implementation and code fixes, and `gpt-6-luna` for test
execution, lint and validation reporting. Current explicit-model agent ownership
is in `PROGRESS.md`. Prior agents stopped at safe boundaries and transferred all
uncommitted changes. Do not restart their superseded lanes or overwrite those
changes. Keep test evidence tied to the tested source; a model handoff does not
invalidate prior completed checks or authorize skipping pending regressions.
