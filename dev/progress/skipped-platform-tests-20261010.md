# Skipped integration and Windows coverage follow-up

User request: repair Quarto discovery and missing optional dependencies, rerun applicable
skipped tests when resources allow, add actual Windows security and child-process coverage,
keep the testing plan current, and preserve the shared Ollama model.

## Authority and resource boundary

The candidate starts from `718e81e4bf54f1d265cac19112ff71cea26511bf` on
`codex/skipped-platform-tests` in the attached managed worktree. The primary checkout,
maintainer DESCRIPTION edit, old prepared regression edits, secrets and shared model stay intact.
At 21:43 PDT, load was 24.96/38.68/31.81, physical memory 123 GiB used/4.424 GiB unused,
swap 22,675.94 MiB, free disk 114 GiB, with no recorded thermal/performance warning.
Local R, browser, model, build and dependency-install jobs remain waiting. Hosted Windows and
Linux runners have separate resources and can exercise the offline cases without model access.

## Prepared cases

- Eight actual-Windows security tests cover true symbolic links and native nonrecursive
  detachment, instruction containment, cache/checkpoint cleanup, scrub/lock boundaries,
  checkpoint restoration, linked writes/duplicate edits, settings freshness and trust revocation.
  Native filesystem witnesses and state/foreign-target restoration must pass; Windows skips
  cannot count as coverage.
- Three actual child-process cases cover 4,000,000-byte duplex output, a no-reader typed stdin
  timeout, and cancellation of a queued write. A fresh external controller bounds each case,
  samples family RSS/output and terminates only processes whose owned identities were recorded.
  They run on both Windows and Unix; only the usual CRAN opt-in gate applies.
- The optional-tool helper discovers executable paths without launching tools or importing
  Python modules. Its eight stdlib unit tests passed in 0.023 seconds. The local bundled
  Quarto exists; the private Python environment still needs pandas/NumPy before local integration.

All new R cases are test-first source preparation, not a passing live or native-platform claim.
The unchanged Windows file runner will collect the initial actual-platform failures; the later
strict integration runner must independently reject warnings, missing mandatory cases and
unexpected skips before any GREEN claim. Four mandatory cross-plan checks are pending on
the candidate's plan amendments. Runtime implementation is unchanged in the initial candidate.

## Execution ledger

| Item | State | Evidence |
| --- | --- | --- |
| Quarto/tool-path discovery helper | Source prepared; Python unit tests passed | Agent-owned 8-case stdlib run; no tools launched |
| Local pandas/NumPy install | Waiting for resources | Existing private Python 3.12 lacks both modules |
| Actual Windows security baseline | Ready to dispatch | Eight real-filesystem tests; no R run yet |
| Actual Windows/Unix child-process baseline | Ready to dispatch | Three externally bounded cases; no R run yet |
| Strict optional integration workflow | In progress | Explicit dependencies, named coverage and bounded jobs |
| Index/extract/R-parse/lintr plan checks | Pending hosted execution | New serial checker rejects soft diagnostic failures |
| Shared Ollama model | Preserved | No model stop, unload or inference request |
