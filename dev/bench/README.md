# gptr benchmark suites

Development only (`dev/` is excluded from the package build). Run every command from the
repository root with `Rscript --vanilla`. Token counts use rtiktoken `o200k_base`, a development
tool that is never in DESCRIPTION. P24's runners exit 0 when they pass, 1 when a gate fails
(`gptr_error_token_regression`) or an error occurs, and 2 when a development tool is missing (the
step stops for the maintainer; nothing is installed).

| Suite | Command | Gate (architecture 12.7) |
|---|---|---|
| Golden transcripts NS-1..NS-11 (P07's runner) | `dev/bench/tokens/run.R [--check] [--update [ids]]` | prefix +2%, input and output totals +5%, requests and image tokens +0, describer facts no loss, catalogs +5% |
| Shiny vs HTML/JS (G2 part a), on demand; needs Chrome or Edge | `dev/bench/shiny-html/check.R [--set=apps\|revised\|mutants]`, `dev/bench/shiny-html/tokens.R` | apps and revisions pass the ladder, mutants fail; ratio and edit-vs-rewrite tracked in `results.csv` |
| Live calibration (IC-73), at release (P25); paid requests | `GPTR_LIVE_TESTS=true dev/bench/tokens/live.R` after `run.R` | requests +2 and input 20% of the golden transcript (o200k x provider prior), in `live-<date>.csv` |
| Polyglot tasks (G5); a task whose program or R package is missing is skipped | `dev/bench/polyglot/run.R [--check] [--update]` | B and C totals within 10% (at least 6 tasks in common) |
| Cache economics (G4), before layout or TTL changes | `dev/bench/cache-sim/run.R [--check] [--update]` | simulated session cost +2% |
| Development tests | `Rscript --vanilla -e 'testthat::test_dir("dev/bench/tests")'` | green |

`dev/bench/tokens/run.R`, its NS-2/NS-3 fixtures and `baseline.csv` belong to P07; P10, P13, P15,
P18, P19, P22, P23 and P24 add fixtures and baseline rows; every other file here belongs to P24. A
fixture without a baseline row fails `run.R --check`: review the replayed numbers, then run
`Rscript --vanilla dev/bench/tokens/run.R --update <fixture id>`. A row is refreshed only by the
plan that owns its fixture, never to make a regression pass.

`dev/bench/cache-sim/baseline.csv` holds for the machine that recorded it (T1's `<r_env>` and the
`<environment>` block are measured live): on another machine, run `--update` on the unchanged tree
before measuring a change.
