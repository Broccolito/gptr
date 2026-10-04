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
P02's first two tasks are uncommitted parallel work, excluded from root's
forthcoming immutable P01 package-check snapshot. The README/About are
updated and draft PR #4 tracks the work. roxygen2 7.3.3 is in `dev/.library`;
use `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla` for development checks.
Optional tooling installation is complete (`progress/tooling.md`). Read ownership
in `PROGRESS.md` before editing or committing. No API should be described as
available until its implementation is verified.

Capture the completed P01 Git archive before
integrating P02. Run full tests, lint, explicit connection gate, and R CMD check
there with the isolated library and local-socket permission. No actual cloud
providers or credentials are needed. Then enable the hosted matrix at that
commit; track cross-platform outcomes separately from local results. P02 can
continue once the snapshot is captured, with serialized docs/Git ownership.
