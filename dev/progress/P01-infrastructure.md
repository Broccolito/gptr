# P01 infrastructure task evidence

Root owns Tasks 19–21. Task 19 depends on Task 3's service table, which passed
before this lane started. These independent checks run alongside the remaining
foundation tasks; the complete P01 acceptance suite still runs after integration.
Commands use `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla` from the root.
Raw output is under ignored `dev/.validation/P01-Tnn-{red,green}.log`.

## Task 19 — architecture layering

- Added source/function ownership mapping, allowed layer/service edges and
  negative controls for prohibited cross-layer calls.
- IC-74 reconciliation: the table contains 119 files, including P13's
  `s1-ollama.R` at layer L4, with explicit assertions for its ownership.
- Red: `testthat::set_max_fails(Inf); devtools::test(filter = "arch-layers")`:
  FAIL 6, WARN 0, SKIP 0, PASS 0 (missing architecture helpers).
- Green: `devtools::test(filter = "arch-layers", stop_on_failure = TRUE)`:
  FAIL 0, WARN 0, SKIP 0, PASS 13.
- Commit: `test(arch): enforce package layering and kernel SDK boundaries`.
- Runtime diagnostic outside the test results: installed testthat was built
  under R 4.5.2, while the current runtime is R 4.5.0.

## Task 20 — source rule scanner

- Added parser-based checks for forbidden assignments, dependencies, shared
  state writes, serialization and source conventions. Negative controls prove
  that each rule detects its violation; S3/closure fixtures check exemptions.
- Red filter `lint-rules`: FAIL 4, WARN 0, SKIP 0, PASS 0 (missing scanner).
- Green with `stop_on_failure = TRUE`: FAIL 0, WARN 0, SKIP 0, PASS 5.
- Commit: `test(lint): enforce R source rules with negative controls`.
