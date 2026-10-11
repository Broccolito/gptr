# Skipped integration and Windows coverage follow-up

User request: repair Quarto discovery and missing optional dependencies, rerun applicable
skipped tests when resources allow, add actual Windows security and child-process coverage,
keep the testing plan current, and preserve the shared Ollama model.

## Authority and resource boundary

The candidate starts from `718e81e4bf54f1d265cac19112ff71cea26511bf` on
`codex/skipped-platform-tests` in the attached managed worktree. The primary checkout,
maintainer DESCRIPTION edit, old prepared regression edits, secrets and shared model stay intact.
At23:30 PDT, load was63.32/62.65/105.60, CPU12.54%idle, physical memory102GiB used/25GiB
unused, swap11,686.06MiB, free disk222GiB, with no recorded thermal/performance warning.
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
  Python modules. Its twelve stdlib unit tests now pass, including mocked Windows argv/env/
  exact-exit propagation. The local bundled
  Quarto exists; the private Python environment still needs pandas/NumPy before local integration.

New R cases were prepared before actual-platform execution. The unchanged Windows file runner
collected the initial failures; the strict integration runner independently rejects warnings,
missing mandatory cases and unexpected skips before any GREEN claim. All four mandatory
cross-plan checks passed through candidate `38cc8dc`. Initial RED baselines used unchanged
production transport; its independently reviewed Windows correction is now source-only and
requires actual production execution before integration.

## Execution ledger

| Item | State | Evidence |
| --- | --- | --- |
| Quarto/tool-path discovery helper | DONE hostedb6fff3d; local child discovery DONE38cc8dc | Actual Quarto/Python/Chrome/rg/Perl preflights and record/replay71 on both hosts; local parent environment unchanged/no child started |
| Local pandas/NumPy install | WAITING resources | Existing private Python lacks both modules; no dependency installation during resource hold |
| Actual Windows security | RED native links63a2454; settings/trust GREEN |192 passes/12 failed assertions+1 raw error/0 warnings/skips; cache28 and native exact-stamp28 pass. EOF fixture reads and runtime alias reading/writing/checkpoint labels SOURCE-CLEAR54ad94b; native validation waiting |
| Actual Windows/Unix child baseline | Windows production RED; Unix control retained | Original Windows3 watchdog failures/24passes/0skips; earlier Linux60passes; latest Linux sampler diagnostic must be recovered from distinct logs |
| Strict optional workflow | Core DONE63a2454; transport316a5e6 stopped before bodies | Both hosts Python12/Rgate619/all12 scoped lints0; seven exact marked-family cleanup witnesses passed per host |
| Index/extract/R-parse/lintr plan checks | DONE through63a2454; latest plan edits awaiting next candidate gates | Six actual Linux runs; unchanged39-file manifests,25 plans/770 selected R blocks/0 parse-style problems/0 lints |
| Owned-writer prototype | DONE actual Windows AND Linuxb6fff3d | Four cases92assertions each/0failures/warnings/skips; pure sampler21each. Does not certify production transport |
| Production owned-writer correction | SOURCE-CLEAR; formatting-only correction4b75650 after actual38118221551 lint stop |20 runtime/guard cases and native3/prototype/sampler unchanged; full eight-file transport run on both hosts. ACL/startup/byte limits/Unix lifecycle/ownership/performance remain unverified |
| Quarto/Python/search/history integrations | DONE complete subsetsb6fff3d | Windows6files404passes+2namedOSguards; Linux7files539passes/0failures/warnings/skips. Protocol notebook is not actual IRkernel |
| App browser/search integrations | DONE actual63a2454 | Linux506 and Windows502 assertions across search/app/cleanup,0 failures/warnings; one named Windows app OS guard. Mandatory actual-browser cases executed, no unhandled close promise |
| Shared Ollama model | PRESERVED | No stop, unload, reconfiguration or inference request |

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


Reviewed cache, native-tag fixture, owned-browser shutdown, short private Linux temp root,
Windows search comparison and distinct-log/strict-gate corrections are pushed task by task
through `38cc8dc023c2c2ec2fa22e6aaaee94d3ea5e3caa`. The six affected full files are running on
actual Windows and Linux in [38116814583](https://github.com/Broccolito/gptr/actions/runs/38116814583);
new cache/cleanup regressions and full existing configuration coverage are included. Scoped
lintr and all four cross-plan checks remain required on that exact source. No result is
claimed before evidence completes.

Local child-only discovery at38cc8dc confirms the existing RStudio bundled Quarto is on
the isolated child PATH, the existing private Python is selected, and the parent environment
is unchanged. The discovery launched no R/browser/model, imported no optional dependency
and does not establish rendering or installed pandas/NumPy. The23:04 PDT resource snapshot
(load157.27/149.57/168.73, CPU0.7%idle, swap12,679.62MiB, disk246GiB, no thermal warning)
keeps local installation, rendering, native UI and model inference held. Shared Ollama is
preserved.

The Windows-only production writer packet is frozen for independent security review. Its
new five actual-Windows lifecycle cases and nine pure guard/accounting cases are prepared,
not executed. Original native/prototype/sampler oracles and timeout/resource guards remain
unchanged; Unix retains its original write path. Secure DACL startup, acceptance accounting,
shutdown/orphan ownership and measured overhead must pass actual hosted production tests
before D-019 can close.


The38cc8dc six-file rerun stopped before package bodies on both hosts. Actual Windows
Rscript rejected the multiline inline lint expression (`unexpected end of input`). Linux
ran lint and found a syntax error in the new cleanup fixture: deferred member assignment
requires a braced expression. Other10scoped files were lint-clean. Both corrections preserve
rules/oracles and are being reviewed. All four plan stages passed38cc8dc with unchanged
39-file source manifests,770 selected R blocks/0 parse/style problems/0 lints. Verified
Windows artifact SHA256c2dec42d3e9f6ec935c3b98278e63456c6c45dfddba9637e5565c38808857445;
Linux4baa83ed51b26deef9bec2591091edc021d5702fcc91132c0aa1a177893084bb.
These infrastructure failures add no package integration coverage.

Independent production source review also caught the Windows R Core9998-byte single-expression
limit and Unix ENOENT marker-release behavior; both are being corrected before runtime
execution. Stable root/owner/child-alias validation is included in both the parent and actor.
Source review is not production validation; D-019 remains open.


Saved lint-file launch and braced teardown corrections were pushed through
`63a24543183ba00e236b6ee3a89d3daf42766617`. Actual six-file Windows/Linux rerun
[38117605612](https://github.com/Broccolito/gptr/actions/runs/38117605612) is ONGOING;
source review was clear, but actual raw results remain pending.

The six-file production writer packet is now independently SOURCE-CLEAR and copied into
the isolated candidate. It has20prepared cases (five actual-Windows lifecycle cases and
fifteen pure guards), original native3/prototype/sampler remain byte-identical, and obsolete
D-019 skips are removed from the existing proc-spawn tests. The separate actual Rscript
expression guard is9998 UTF-8 bytes and the conservative overall argv cap stays12000.
Mailbox root/owner/child-alias checks guard both parent and actor; Unix marker release retains
its old path. No production parser/lint/ACL/bootstrap/lifecycle/performance pass is claimed.
Strict final registry/gate and31-path lint packet also passed independent source review;
unexpected capability skips (including existing Codex permission/link cases) remain fatal.
Start production hosted tests only after the two current hosted jobs finish. Local resource
hold and shared-model preservation remain unchanged.


## Actual core completion and next native transport run —23:31 PDT

[Run38117605612](https://github.com/Broccolito/gptr/actions/runs/38117605612), exact63a2454,
completed. Linux five complete core files passed1026 assertions/0 failures/warnings/skips;
its eight Windows-only security cases are explicit OS guards. Windows five complete core
files passed1018 assertions/0 failures/warnings plus3 named OS guards. Both hosts passed
Python12/R gate619/all12 scoped file lints, dependency preflight and all7 recorded owned-family
cleanup witnesses. Linux's4 plan stages passed:39-file before/after manifests equal,25 plans,
770 selected R blocks/0 parse-style problems/0 lints;90 historical index warnings remain.
Verified Linux artifact SHA256:f234d980b77667da4ba35ca06088e291e047e4dd3665543781a68115ee8e0bb4.
Verified Windows artifact SHA256:1a022c2918cf7dad380829c52549a4e58ba29b65a891067fbf81ee579826c2e8.

Actual Windows security remains RED with192 passes/12 failed assertions and1 raw error,
0 warnings/skips. The native-link byte helper incorrectly sizes reads using zero-sized alias
metadata; runtime read_utf8 does the same. Writing through a file alias replaces the link and
leaves its real target unchanged; walker/checkpoint listings omit directory-link labels.
The settings and trust exact-stamp cases now pass14 assertions each. A disjoint source lane
is preparing minimal alias-read/write/listing fixes with focused policy tests and independent
review; none is claimed as executed. Canonical existing-path checks do not establish dangling
Windows-link detection or protection against concurrent same-user reparse replacement.

The independently reviewed Windows writer is pushed at316a5e6. Hosted
[run38118221551](https://github.com/Broccolito/gptr/actions/runs/38118221551) is ONGOING with
8 full transport files,20 new lifecycle/guard cases and31 scoped lint paths. Production startup,
actual private-mailbox ACL/size, native backpressure, cancellation, orphan cleanup, Unix
regressions and performance still require evidence. The updated plan must pass4 cross-plan
stages on the next exact candidate. No local heavy job, model inference, shared-model stop,
unload or reconfiguration was performed.


## Source-reviewed corrections after the lint gate —23:37 PDT

Actual38118221551 stopped on both hosts before package bodies:6 scoped formatting findings
in proc-spawn and3 process helpers. Other scoped paths were clean. Four-file correction4b75650
adds braces/newlines only; independent review reverse-recovered all four frozen baseline hashes.
Native3, prototype, sampler and runtime test files are unchanged; helper generated-code whitespace
changed without altering failure classes, cases, resource limits or ownership checks.

Observed valid-target Windows link fixes54ad94b are independently SOURCE-CLEAR. Five runtime
files use canonical-target reads/writes and direct-entry canonical-alias classification for
walker/checkpoint safety. The bounded EOF fixture reader no longer relies on zero-sized link
metadata. All eight native security test bodies remain byte-identical. Five new pure policy cases
are mandatory on both hosts under5fd86c0; all37 scoped lint paths are checked. Short final-component
spellings can be conservatively excluded from capture; missing Windows targets remain unproved.
Next ten-file actual transport/security rerun is WAITING dispatch on a fresh exact candidate,
including4 serial Linux plan stages for this update. Nothing is production GREEN yet.
