# gptr development

gptr 1.0 is a ground-up rebuild: an AI agent harness that lives inside the R session (CRAN package, pure R).
All design material is under `dev/` and excluded from the package build.
Machine-specific inventories belong in the ignored `dev/LOCAL_SETUP.md`, if needed.

## Read before working

1. `dev/plan/00-index.md`: execution order, milestone gates, preflight.
2. `dev/plan/00-conventions.md`: global constraints for every plan.
3. `dev/spec/03-architecture.md`, `dev/spec/04-interface-contract.md` (§15 wins over earlier sections),
   `dev/spec/05-plan-decomposition.md`.
4. The plan you are implementing, `dev/plan/Pxx-*.md`. Follow it task by task (test first, then code, then commit).

Research is in `dev/research/` (start with `README.md` and `00-digest.md`). A report's Verification log
overrides its body.

## Non-negotiable rules

- R style: assign with `=`, never `<-`; pipe with `|>`, never `%>%`. `.lintr` (created by P01 Task 1) enforces it.
- After editing any plan, re-run the cross-plan checks in `dev/research/assets/consolidation-tools/README.md`.
- Run R as `Rscript --vanilla`. Tests: `Rscript --vanilla -e 'devtools::test(filter = "<name>")'`.
- Do not depend on or bridge to any R LLM package (ellmer, tidyllm, btw, mcptools, ...). Do not use httr2.
  Imports are fixed in `03-architecture.md` §9; no plan adds one.
- No compiled code in v1.
- Tests are offline. Use the fake provider and helpers from P01. Live tests only run with
  `GPTR_LIVE_TESTS=true`.
- Local credentials are in `.secrets/jev-key.env` (Jev variable `jev-key`) and
  `.secrets/llm-passwords.env`. The directory is owner-only and excluded from Git and R builds.
  Load keys only through `gptr_env()` in explicitly enabled live tests once implemented.
  Never print, log, copy or commit them; preserve the ignore rules when replacing setup files.
- Never write to `.GlobalEnv` by name, never leave `options()`, working directory, seed or env vars changed, and
  keep user objects copy-safe (architecture §6.4).
- Commit one task at a time with the conventional message the plan gives.
