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

Continue P01 from the latest completed task in `progress/P01.md` and the
parallel utilities/providers/infrastructure logs. All 21 tasks have
focused passing checks. Task 18 completed at `7d816e9`; full acceptance is pending.
P02 Tasks 1–8 are committed and Tasks 9–11 are in progress. Root captured P01 at
`eea1e36` before these commits; its 1,599 assertions, connection gate and lint
passed. Installed-package checking found one mock-package inference issue;
the reviewed one-line correction (`d4aabfb`) passed R CMD check with
0 errors, 0 warnings and 0 notes in that snapshot. See
`progress/P01-acceptance.md` for exact evidence and pending hosted results. The README/About are
updated and draft PR #4 tracks the work. roxygen2 7.3.3 is in `dev/.library`;
use `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla` for development checks.
Optional tooling installation is complete (`progress/tooling.md`). Read ownership
in `PROGRESS.md` before editing or committing. No API should be described as
available until its implementation is verified.

P01 local acceptance is complete on `eea1e36` plus the test correction from
`d4aabfb`. Hosted CI on `eea1e36` is expected to expose the pre-fix installed-test
error plus Windows CRLF-marker and oldrel-4 negative-control failures.
The reviewed portability fixes passed focused local checks; they also need
hosted verification. Publish a coherent later snapshot containing the corrections after P02
acceptance, then record exact-SHA hosted outcomes. Do not mark the old CI as a
pass. P04 Tasks 1–2 and 4–6 have focused green checks; remaining transport work continues.
P03 vault/parser are committed, other auth components are in progress; before loading their source
locally, isolate home/cache/config at process startup because the orphan sweep
runs before test setup. No real secrets or providers are needed for these gates.
