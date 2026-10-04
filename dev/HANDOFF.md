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

Continue P01 from the latest completed task in `progress/P01.md`. Task 1 was
committed as `bbc000c` (42 passing assertions). The README rewrite is ready;
root owns GitHub publication. roxygen2 7.3.3 is installed in `dev/.library`;
use `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla` for development checks.
Optional dependency installation has a separate owner. Read active ownership
in `PROGRESS.md` before editing or committing. No API should be described as
available until its implementation is verified.
