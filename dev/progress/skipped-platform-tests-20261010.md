# Skipped integration and Windows coverage follow-up

User request: repair Quarto discovery and missing optional dependencies, rerun applicable
skipped tests when resources allow, add actual Windows security and child-process coverage,
keep the testing plan current, and preserve the shared Ollama model.

## Authority and resource boundary

The candidate starts from `718e81e4bf54f1d265cac19112ff71cea26511bf` on
`codex/skipped-platform-tests` in the attached managed worktree. The primary checkout,
maintainer DESCRIPTION edit, old prepared regression edits, secrets and shared model stay intact.
At 22:45 PDT, load was345.73/290.05/184.73, CPU0%idle, physical memory100GiB used/27GiB
unused, swap12,767.69MiB, free disk213GiB, with no recorded thermal/performance warning.
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
  Python modules. Its eleven stdlib unit tests now pass, including mocked Windows argv/env/
  exact-exit propagation. The local bundled
  Quarto exists; the private Python environment still needs pandas/NumPy before local integration.

New R cases were prepared before actual-platform execution. The unchanged Windows file runner
collected the initial failures; the strict integration runner independently rejects warnings,
missing mandatory cases and unexpected skips before any GREEN claim. All four mandatory
cross-plan checks passed on candidate `245de54`. Runtime implementation remains unchanged.

## Execution ledger

| Item | State | Evidence |
| --- | --- | --- |
| Quarto/tool-path discovery helper | Actual hosted Windows launch/preflight passed89f804d | Python11/Rgate41 and0 scoped lints; realQuarto/Python/Chrome/rg/Perl oracles passed, no model events |
| Local pandas/NumPy install | Waiting for resources | Existing private Python 3.12 lacks both modules |
| Actual Windows security baseline | Failed fixtures; corrected source ready | Run `38112622473`: raw 6 errors, 3 failed assertions, 6 warnings, 53 passes, 0 skips |
| Actual Windows/Unix child-process baseline | Windows runtime RED; actual Unix control passed89f804d | Windows baseline:3 watchdog failures/24 passes/0 skips; Linux:60 passes/0 failures/warnings/skips |
| Strict optional integration workflow | Controller lifecycle RED; correction ongoing | `38114220610` at89f804d: Windows setup/unit/lint/preflight passed, nine subsequent per-file children failed before test bodies with supervisor-pipe error |
| Index/extract/R-parse/lintr plan checks | Passed exact245de54,39f3248 and89f804d; rerun with plan updates | All four Linux stages succeeded three times and source hashes matched before/after |
| Owned-writer transport prototype | Linux3 cases passed; cancellation resource guard RED; Windows waiting | Actual Linux duplex25/timeout23/binary22 assertions passed; cancellation2 failures/4 passes and1 sampling error; owned families stopped. Not a production fix |
| Quarto/Python/search/history integrations | Six complete Linux files passed89f804d |486 assertions/0 failures/warnings/skips; Quarto71, notebook protocol44, compact history58, bridge128, search125, Unix child60 |
| App browser integrations | Linux2 mandatory cases skipped | HTTP200 controls and separate Chrome preflight passed; constructor error text was not retained. Diagnostics and actual rerun ongoing |
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
are preparation only. The corrected exact39f3248 hosted rerun38113687980 completed:
dependency provisioning succeeded and both hosts passed9 Python tests plus21 R gate assertions,
with0 failures/warnings/skips. Windows then reported launcher exit139 before R lint; Linux
reported exactly two brace-linter findings in the runner and0 in the pure R gate file. No
optional integration or corrected security/prototype case ran. The minimal follow-up uses
Windows `subprocess.run(..., shell=False, env=owned_environment)` with exact exit propagation,
preserves POSIX exec, and adds the two missing function braces without disabling lint rules.
Its two mock launcher tests were RED before the correction and GREEN afterwards; that does
not prove actual Windows R launch. All four Linux plan stages again passed39f3248 (index164s,
extraction0.5s, parse1.8s, lint101s), within their original bounds and with unchanged source
manifests. The prototype packet is committed at3a17f9e and awaits the corrected nine-file run.

The next [nine-file run38114220610](https://github.com/Broccolito/gptr/actions/runs/38114220610)
uses exact89f804d. Windows actually passed11 Python tests,41 R gate assertions, both scoped
R lint files, source installation and real dependency preflight: Quarto1.10.19, configured
Python3.12.10 with pandas/NumPy and sum6, ripgrep15.1.0, Perl42, Chrome expression2 and owned
close under the unchanged10s startup bound. Preflight observed0 request events/usage events/
native usage rows. Artifact SHA2565ecf57addd82a70d599fcaec72f6157dab0e6f9bbca7a3450a8264fef93f353f
is retained and verified. Each of the nine subsequent per-file launches failed in0.06–0.10s
before any test body, with empty test logs and a closed processx supervisor pipe (system232).
One cleanup witness had root stopped but1 marked process remaining. The controller's
per-child supervisor/marker interaction and actual five-second family settlement are being
corrected; these are infrastructure failures, not executed package/prototype regressions.
The Linux job also completed. Six files passed486 assertions with0 failures/warnings/skips:
Quarto71 (actual initial fake requests2/replay0/source hash checks), notebook protocol44,
compact history58, Python/SQL/shell bridge128, ripgrep comparison125 and Unix child control60.
Notebook protocol cases do not replace actual IRkernel execution. Eight security cases used
expected Linux platform guards and do not establish Windows coverage. The app gate rejected
two mandatory browser-constructor skips despite passing HTTP200 controls and Chrome preflight;
the old location reporter omitted the reasons. The prototype passed duplex25, timeout23 and
binary22 assertions; cancellation had2 failures/4 passes with1 resource-observation error.
Its phases reached completion and owned families stopped, but the discarded condition prevents
exact attribution. All four plan stages passed exact89f804d with unchanged source hashes.
Linux artifact SHA256f4f48a597f93cf829e9725c0b78177e259fd3aa5b11cd02004e8f76f116d7b93 is verified.

The next correction disables callr's shared singleton supervisor for these already-owned,
bounded children: first-child marker cleanup otherwise kills the marker-inheriting shared
server and later launches write its closed Windows pipe. No broad supervisor reset is used.
The controller retains cleanup_tree and checks both root exit and an empty exact-marker family
for up to5 seconds; --vanilla/--slave preserves startup isolation without bootstrap echo.
It writes bounded raw condition rows before failing warning/mandatory gates, so browser reasons
survive. Fake-clock settlement and diagnostic tests are source-prepared; actual rerun is pending.
The sampler separately handles an identified enumeration race only when the same original
parent handle is definitively dead; alive/unknown failures remain fatal. Four pure tests and
structured stage/class/errno/pid diagnostics preserve all resource limits and ownership checks.
This source-confirmed race is not a confirmed attribution of the prior cancellation failure.

Reviewed corrections are pushed at `b6fff3d001d0fab6bde14c3d87f4296d937839c7`.
The actual ten-file Windows/Linux rerun is complete; both strict gates failed:
[38115064744](https://github.com/Broccolito/gptr/actions/runs/38115064744).
It includes all prior nine suites plus four mandatory pure sampler regressions, with unchanged
security/native-process/browser/prototype oracles. The strict runner and sampler packet both
passed independent source review. Current-source hosted unit/lint/plan/integration results
are retained separately from any production-repair claim.

Atb6fff3d both hosts passed11 Python tests,74 R gate assertions, both scoped R lints,
installation and real dependency preflight. All11 exact child-family cleanup witnesses passed
on each host. Windows actual Quarto71, notebook protocol44, history58, bridge118 (2 named OS
guards), prototype92 and sampler21 passed404 assertions/0 failures/warnings. Linux same
files plus search passed539 assertions/0 failures/warnings/skips. The four original process
prototype cases passed on BOTH actual operating systems; production transport is unchanged.
All four plan gates passedb6fff3d,770 selected R blocks/0 parse/style problems/0 lints,
with unchanged39-file source manifests. Verified Windows artifact SHA256
c99b8734dad4119a5256efc81ff6c73e05d9b3f63bed45d2664b672a6125426a;
Linux6da9cf308a1ff38949f96eda1f44110f9d4403a26452d7f021f07b6bfd24378e.

Open witnessed failures are now specific:

- Windows security:92 passed expectations,6 native-tag inspection timeout errors,4 failed
  assertions,0 warnings/skips. Link creation succeeded and deferred nonrecursive deletion
  preserved foreign targets. The two exact-stamp rewrite cases reproduce stale settings and
  retained trust/fingerprint; a Windows-only content-sensitive cache stamp is being prepared.
  The extra options-restoration failure names only diffobj reporter defaults initialized by
  its failure rendering; package options mutations must still fail the oracle.
- Windows search:122 passes/3 failures/0 warnings/skips; ripgrep returns native relative
  spelling `.\\a.R` while gptr returns`a.R`. Normalize spelling in the independent fixture;
  retain exact file and line comparisons.
- Windows app:357 passes/0 failures/warnings/1 named OS guard, but an unhandled asynchronous
  `Browser.close` timeout printed during a later test. Strict gate correctly fails; owned
  browser shutdown is being corrected without changing startup/close bounds.
- Linux app:346 passes/0 failures/warnings/2 mandatory skips. Retained Chrome FATAL diagnostics
  identify an overlong SingletonSocket path inside the deeply nested fixture TMPDIR. Use an
  exact owned private short Linux test root; preflight had already passed in its shorter root.
- Original native Windows child cases:24 passes/3 bounded watchdog failures,0 warnings/skips.
  D-019 remains open pending a secure minimal runtime correction and actual production proof.
- Linux native timeout:48 passes/2 failed assertions,0 warnings/skips;1 resource-observation
  error, all owned processes stopped. Its structured error was physically overwritten by
  independent stdout/stderr handles sharing one log. Separate logs and scan both for unhandled
  promises before diagnosing that condition; no sampler guard is weakened.

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
