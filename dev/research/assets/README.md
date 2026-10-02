# Research assets

Text artifacts copied out of the session's temporary scratch directory on 2026-09-30, so the specs and plans do
not depend on files that disappear with the design session. Code here is prototype code: it may use `<-` and
must be converted to the house style (`=`, `|>`) when copied into the package.

| Directory | What it is | Referenced by |
|---|---|---|
| `G2/` | token-efficiency benchmark: the 20 Shiny-vs-HTML apps (`a_apps/`, `a_revised/`), their checker, corpus builders (`f_*.R`), measurement scripts and outputs (`out/`) | `G2-token-efficiency-benchmarks.md`, P24 (`dev/bench/`) |
| `design-final/` | the lead architect's verification scripts, prompt measurements and decision notes | `03-architecture.md` Appendix A |
| `design-review-resolution/` | scripts used to check review fixes, prompt re-measurements (`prompt/measure3.R`), and the §15 draft | `06-review-resolution.md`, contract §15 |
| `lead/` | the lead designer's first-hand prototypes: gateway dispatch (`gateway.R`), live Jev calls (`jev_live*.R`; read the key from a `.env` file, never print it), digest and gap-report builders | `01-decision-register.md`, `04a-jev-live-verification.md` |

The G3 and G5 prototypes are embedded directly in `G3-session-object-pipe-steering.md` and
`G5-polyglot-glue-helpers.md`. Binary artifacts (screenshots, `.rds` corpora) were not copied; the scripts
that produce them are here.
