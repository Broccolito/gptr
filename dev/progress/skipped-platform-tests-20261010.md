# Skipped integration and Windows coverage follow-up

User request: repair Quarto discovery and missing optional dependencies, rerun applicable
skipped tests when resources allow, add actual Windows security and child-process coverage,
keep the testing plan current, and preserve the shared Ollama model.

## Authority and resource boundary

The candidate starts from `718e81e4bf54f1d265cac19112ff71cea26511bf` on
`codex/skipped-platform-tests` in the attached managed worktree. The primary checkout,
maintainer DESCRIPTION edit, old prepared regression edits, secrets and shared model stay intact.
At 22:06 PDT, load was 30.46/32.84/38.27, physical memory 76 GiB used/51 GiB unused,
swap 14,021.94 MiB, free disk 114 GiB, with no recorded thermal/performance warning.
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

New R cases were prepared before actual-platform execution. The unchanged Windows file runner
collected the initial failures; the strict integration runner independently rejects warnings,
missing mandatory cases and unexpected skips before any GREEN claim. All four mandatory
cross-plan checks passed on candidate `245de54`. Runtime implementation remains unchanged.

## Execution ledger

| Item | State | Evidence |
| --- | --- | --- |
| Quarto/tool-path discovery helper | Source prepared; Python unit tests passed | Agent-owned 8-case stdlib run; no tools launched |
| Local pandas/NumPy install | Waiting for resources | Existing private Python 3.12 lacks both modules |
| Actual Windows security baseline | Failed fixtures; corrected source ready | Run `38112622473`: raw 6 errors, 3 failed assertions, 6 warnings, 53 passes, 0 skips |
| Actual Windows/Unix child-process baseline | Windows runtime RED; Unix pending | Same run: 3 watchdog failures, 24 passes, 0 skips, no observed process-test warnings |
| Strict optional integration workflow | Corrected rerun running | `38113687980` at39f3248 corrects both setup failures; actual integration still pending |
| Index/extract/R-parse/lintr plan checks | Passed exact `245de54`; rerun with plan updates | All four Linux stages succeeded and source hashes matched before/after |
| Owned-writer transport prototype | Source prepared; independent peer review clear | Four bounded cases retain original native-runtime RED tests;92 expected assertions, no actual execution yet; not a production fix |
| Shared Ollama model | Preserved | No model stop, unload or inference request |

Initial hosted baseline: [Windows run 38112622473](https://github.com/Broccolito/gptr/actions/runs/38112622473).
It uses the unchanged legacy file runner to collect failures, not to certify warning/skip coverage.
All three process cases reached the 30-second case bound in about 32 seconds; owned families
settled, peak family RSS was 348-374 MB, output about 10 KB, and sampling errors were zero.
Cancellation reached the queued phase before hanging, consistent with the native write inside
the drain preventing later output/timer/timeout handling. Public processx pipe writes also use
the blocking Windows write operation. An independently owned writer prototype is being reviewed;
no speculative runtime fix has been applied.

Six security cases stopped before link creation because positional `local_tempfile()` used its
deprecated binding mode rather than returning a path. The two timestamp fixtures lost fractional
mtime precision in `Sys.setFileTime()`; settings also reported an options-restoration mismatch.
The corrected fixtures name `pattern` explicitly and assert an exactly representable integer
mtime before priming settings or recording trust. Strict stamp equality remains; changed option
names will be diagnosed without exposing their values. Link/caching runtime failures are not yet
established by this scaffold run. The legacy numeric summary misses raw expectation errors;
the new strict runner counts raw error/failure/warning conditions independently.

The plan-check diagnostic controller passed six stdlib regression tests after a test-first RED.
The subsequent strict [run `38113192422`](https://github.com/Broccolito/gptr/actions/runs/38113192422)
executed all four actual plan stages successfully on Linux at exact `245de54`: index about
90 seconds, extraction 0.3 seconds, parse 1 second and lint 53 seconds, with unchanged39-file
source hashes. The25-plan index had0 error-level and90 historical warning-level findings;
770 R blocks had0 parse/style problems and scoped plan lint had0 findings. Its retained
Linux artifact SHA256 is75c33efa0c44799c1b7d9d231d6414114112e93fa18a08696663f7f854552466.
Integration setup failed separately: Python `3.12.12` has no Windows x64 archive,
and `test_file()` changes into `dev/ci`, making the unit helper's root-relative source path
invalid. The reviewed correction selects Python `3.12.10`, available for both hosts, and a
helper path valid in either controlled working directory. Optional integration cases, their
scoped R lint, and corrected Windows fixtures have not run yet. Source syntax and Python tests
are preparation only; the corrected exact39f3248 hosted rerun38113687980 is running.

The test-only owned writer keeps the actual target's ordinary processx stdin pipe and moves
its potentially blocking write into a separately tracked child. Private atomic mailbox files
carry bounded raw input; ACK totals advance only for bytes accepted by the real pipe write.
Four probes require exact40000-line stdout/stderr, typed no-reader timeout, queued cancellation
without a late exit callback, and ordered binary/NUL/UTF-8 bytes. An independent source review
found no blocker; Windows handle inheritance, raw FD1 writes, native ACLs and cleanup still
require actual hosted proof. The final helper SHA256 is27e36707f08a208da0b52f520b78e40113b2c9e8fff0b3035de75053f196dfb4.
The strict registry adds these four mandatory, unskipped cases on both hosts. Its pure negative
tests reject a missing title, zero assertions or skipped probe. This is not a production fix
or closure of D-019; the original native-runtime regression cases remain unchanged.
The complete older exact-archive run `38102472275` has finished: all five consumers failed.
Mac's two failures are the old notebook stdout assertion already corrected at `ad4e6a9`;
Linux devel reports the same two plus the known mock-path fixture assertions. These older
archives do not include this new packet or prove current-source regressions.
