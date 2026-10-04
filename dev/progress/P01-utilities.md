# P01 utilities task evidence

Tasks 9–12 are implemented in the shared implementation checkout after Task 8
commit `e6fc6c3`, under an explicit handoff from the foundation owner. Commands
run from the repository root with `R_LIBS_USER="$PWD/dev/.library" Rscript
--vanilla`; roxygen2 is pinned to 7.3.3. Raw logs remain ignored under
`dev/.validation/P01-Tnn-{red,green}.log`. All tests are offline and no
credentials are read. Shared documentation generation and Git commits are
serialized with the foundation owner.

## Task 9 — calibrated token estimator

Created `R/utils-tokens.R`, its focused tests and the 12-sample token fixture.
The estimator uses content classes and Unicode weights, supports provider image
formulas and updates the session multiplier only for sufficiently large samples.

- Red: `testthat::set_max_fails(Inf); devtools::test(filter = "^utils-tokens$")`:
  FAIL 5, WARN 0, SKIP 0, PASS 1; missing estimator functions as expected.
- Green: `devtools::document(); devtools::test(filter = "^utils-tokens$")`:
  FAIL 0, WARN 0, SKIP 0, PASS 20; documentation exits successfully.
- Green command additionally asserts zero failed expectations and no test errors
  from the returned testthat results.
- Installed rtiktoken 0.11.0.3 exactly reproduces all 12 fixture counts with
  `get_token_count(text, model = "o200k_base")`. This does not establish the
  later P07 benchmark's baseline or timing gate.
- Testthat emits its existing package-build warning outside test results
  (built under R 4.5.2, runtime R 4.5.0); test warnings remain zero.
- Commit: `feat(utils): add the calibrated token estimator and its fixture`.

## Task 10 — output budgets and listings

Created `R/utils-text.R` and focused tests for token-budgeted head/tail output,
session/process output stores, redacted spill-file recovery, terminal cleanup
and listing output. The session lookup falls back to the process store and then
the spill file, as IC-71 requires.

- Red filter `^utils-text$`: FAIL 8, WARN 0, SKIP 0, PASS 0; missing functions.
- Green after documentation: FAIL 0, WARN 0, SKIP 0, PASS 40, with zero-failure
  assertions on the returned test results.
- Shared `NAMESPACE` diff contains only `S3method(print,gptr_listing)`.
- Focused `git diff --check` passes. The pre-existing testthat build-version
  warning remains outside test results.
- Commit: `feat(utils): add output truncation, the out store, spill files and listings`.

## Task 11 — streaming partial JSON

Created `R/json-partial.R` and focused tests for incremental tool-argument
previews, partial scalars/strings/containers, repaired control characters,
UTF-8 byte boundaries, completed values and preview throttling.

- Red filter `^json-partial$`: FAIL 7, WARN 0, SKIP 0, PASS 0; missing scanner.
- Green after documentation: FAIL 0, WARN 0, SKIP 0, PASS 626, with zero-failure
  assertions on the returned test results.
- The suite exercised every split of the compound JSON fixture, incomplete
  multibyte characters, and the 20,000-delta performance case under its five
  second bound.
- Commit: `feat(json): add the streaming partial-JSON scanner`.

## Task 12 — schema validation and signatures

Created `R/json-schema.R` and focused tests for required properties, scalar
types, explicit integer/array coercions, enums, nested objects/arrays, unknown
properties, schema structure and concise tool signatures.

- Red filter `^json-schema$`: FAIL 7, WARN 0, SKIP 0, PASS 0; missing validator
  and schema helpers.
- Green after documentation: FAIL 0, WARN 0, SKIP 0, PASS 28, with zero-failure
  assertions on the returned test results.
- Scoped lint of all eight source/test files from Tasks 9–12, after
  `pkgload::load_all(quiet = TRUE)`, returns zero lints. Raw log:
  `dev/.validation/P01-utilities-lint.log`.
- No direct IC-74 changes are needed in these four utility tasks; amended fake
  classifier metadata/records remain with the foundation owner in Task 15.
- Commit: `feat(json): add JSON Schema validation and one-line signatures`.

Tasks 9–12 have actual red/green evidence, with 714 passing expectations across
their four focused green runs. The complete P01 package/milestone gates remain
the foundation owner's responsibility.

## Task 12 follow-up — schema boundary review

Review beyond the literal plan fixtures exposed additional accepted-input
errors. Nullable object schemas skipped required/unknown-property checks or
converted allowed null into an empty object; enum matching coerced JSON types
and flattened nested values; JSON numbers accepted infinities/complex values;
empty JSON arrays passed object schemas.

- Regression-first run: FAIL 22, WARN 0, SKIP 0, PASS 47. Raw log:
  `dev/.validation/P01-T12-edge-red.log`.
- Corrected focused suite: FAIL 0, WARN 0, SKIP 0, PASS 69. The original 28
  expectations still pass; 41 additional expectations cover union/null,
  nested/type-aware enum, finite-number and empty-container behavior.
- Enum equality preserves numeric integer/double equivalence, object key-order
  independence, array order, and explicit null entries (`enum = list(NULL)`).
- Empty objects remain named empty lists (`json_obj()`); unnamed empty lists
  are arrays, per conventions section 6 and interface-contract section 4.1.
  The existing `NULL` shorthand for a non-nullable object schema remains valid.
- Focused lint: zero. No shared documentation output changed.
- Independent review reproduced the original failures and checked corrected
  nullable unions and null enums; no actionable issue remained in the fix.
- Commit: `fix(json): preserve JSON types and nullable schema constraints`.

## Task 9 follow-up — finite estimator inputs

Review found that infinite image dimensions failed with an untyped condition,
and non-finite provider usage could produce a NaN calibration multiplier.
Added local estimator guards without changing the shared numeric validator.

- Regression-first run: FAIL 12, WARN 2, SKIP 0, PASS 28. Raw log:
  `dev/.validation/P01-T09-edge-red.log`.
- Corrected focused suite: FAIL 0, WARN 0, SKIP 0, PASS 69, with zero lint.
  The original 20 expectations still pass, including all normal provider image
  formulas and EWMA updates.
- Non-finite/complex dimensions now produce typed invalid-argument conditions.
  Non-finite/complex observed usage preserves the current calibration state.
  New calibration requires a positive finite real prior; calls with existing
  state still do not evaluate an omitted prior.
- Independent review found no actionable issue in the guards or regression
  coverage. No shared documentation output changed.
- Commit: `fix(utils): reject invalid estimator dimensions and calibration inputs`.
