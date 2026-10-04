# Implementation decisions and deviations

## D-001 — Branch and implementation authorization (2026-10-03)

Use `codex/gptr-1.0-implementation` from synchronized `main` instead of recreating
the already-merged historical `gptr-1.0` branch. This preserves the completed
design history and follows the current branch convention. No design behavior changes.

## D-002 — Isolated tooling and current environment (2026-10-03)

The maintainer's start-to-finish implementation request authorizes necessary
development setup. Missing dependencies and pinned roxygen2 will be installed
in an ignored project-local library rather than replacing the user's packages.
The tool inventory is checked live; old `/Users/wanjun` snapshots are historical.
The task logs will record exact versions and relevant test outcomes without
publishing the private host inventory.

## D-003 — Public transition begins before P25 (2026-10-03)

The maintainer explicitly requested rewriting README and GitHub About now.
Replace obsolete 0.7 examples with an accurate development-status overview.
Working examples and installation promises must track verified implementation;
P25 still owns the final user documentation and release validation.

## D-004 — Available implementation workflow (2026-10-03)

The named `superpowers:*` skills are not installed. Use the available subagent
tools for task-sized implementation and independent review, preserving actual
test-first evidence and plan gates. Do not install unrelated skills or claim
that a named external workflow was run.

## D-005 — Parallel foundation tasks (2026-10-03)

The maintainer authorized parallel implementation. P01 Tasks 19–21 run once
Task 3's service table is stable: their structural checks do not require the
remaining token/message utilities. Tasks 9–12 and 13–18 may proceed in separate
lanes after Task 8. Scope edits and Git commits to each owner, preserve actual
red/green checks, and rerun complete P01 acceptance after integration. No plan
or milestone is declared complete from a partial tree.

P02's independent event-catalogue task also begins after its actual P01
condition/encoding dependencies pass. P02 spec-engine tasks wait for the schema
and fake-provider contracts. This uses the tested interface dependency order;
full P01 acceptance still precedes P02 completion and milestone promotion.
P04 Task 1 (SSE/NDJSON splitters) likewise uses only the verified P01 JSON
decoder. It can run independently before registry/secrets integration; the
remaining transport tasks wait for their actual authentication prerequisites. P04 Tasks 4–5
(process supervision and the job table) also use only P01 interfaces and run in
a separate lane while root validates the immutable foundation snapshot.
Tasks that materialize secrets or persist transport data still wait for P03.

## D-006 — Effective connection cleanup gate (2026-10-03)

Independent review found that setting `_R_CHECK_CONNECTIONS_LEFT_OPEN_` around
`devtools::test()` does not check the test suite's connections: R CMD check uses
that flag for examples. CI now compares the complete R connection table before
and after the suite through `dev/ci/check-connections.R`. A synthetic leaking
connection is an explicit negative control. Ordinary R CMD check example
checks remain enabled. The full wrapper must also pass after P01 integration.

## D-007 — Stream parser boundary corrections (2026-10-03)

The literal P04 splitter silently removed NUL bytes, changing provider data.
Both splitters now signal a typed provider error because R strings cannot
represent NUL; error messages never include the input. This is an explicit R
representation limit, not a claim that NUL is forbidden by the SSE standard.
Invalid retry fields are ignored before choosing the last valid numeric retry.
The contract's deliberate final-event flush behavior is preserved.


## D-008 — Independent usage-accounting component (2026-10-03)

P05 Task 1 consumes only P01 condition/list utilities and can be developed in a
separate file while the M0 registry, secrets and transport integration proceeds.
Its owner reconciles unknown usage and prices with IC-74 instead of copying the
older plan's conversion of missing measurements into zero. No later usage rows
or model resolution are implemented before their dependencies. This parallel
component does not complete P05 or advance the milestone gate.


## D-009 — Portable copy-safety controls (2026-10-03)

Hosted P01 validation exposed two test-harness assumptions. Windows child stdout
uses CRLF, so completion-marker parsing must accept CRLF as well as LF. A
synthetic output regression checks both successful completion and detection of
a copy under CRLF.

The literal plan's `str(big)` negative control makes no observable next-edit
copy on the hosted oldrel-4 R interpreter, although it does on this Mac. Use
`retained = big` as the portable negative control: keeping a second reference
must force the next edit to copy. The zero-copy requirement for the package's
fingerprint/save operations and the real edit tests is unchanged. Full Windows
and old-R acceptance still needs a new hosted run containing these corrections.
