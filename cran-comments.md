## Submission and verification

gptr 1.0.0 is pure R. Examples and all 14 precomputed guides run offline without credentials.

The certified f48f825 archive completed R CMD check --as-cran --no-manual with Status OK: no errors, warnings or notes. Tests passed 30,538 assertions with 445 accounted skips (418 On CRAN and 27 for specific contexts or optional dependencies). The check took 495.431 s; sampled process-family peak RSS was 2,025.234375 MiB. This does not establish native Windows or live-provider/GUI acceptance; current required CI and final submission checks remain pending.

## Current size and CRAN consideration

The default-byte-compiled archive is 2,654,286 B and installed package 6,989,229 B, including R/gptr.rdb 5,039,928 B. Installed doc/help/html are 1,224,500/485,171/15,771 B (combined documentation 1,725,442 B); extdata is 83,185 B and data 0. Build took 22.139 s; install 15.277 s; whole build/install family 43.790 s, sampled peak RSS 520.84375 MiB.

The installed 5 MB target remains unmet. Byte compilation, all guides and security/debug support are retained; no new source stripping or reduction is claimed. Please consider the necessary package contents and the measured reductions discussed below. Size NOTES from earlier checks remain disclosed. This current check instead reports installed 10.5 Mb (R 8.5 Mb) as INFO, not a NOTE: its keep-source installation is 10,069,760 B with Rdb 8,129,421 B, a separate profile from the normal installation above.

Historical comparisons and remaining-gate wording below retain their earlier snapshots. Tested guidance/Windows fixture changes are integrated in source 2654a21; fresh combined normal/check validation is pending; submission, merge and publication are not yet complete.

Default installation already omits optional source-retention metadata. A historical matched
archive comparison measured installed 6,962,112 bytes normally versus 10,047,490 with
R_KEEP_PKG_SOURCE=yes; Rdb 5,009,974 versus 8,093,867 (3,083,893-byte increase). This
measures opt-in debug cost, not a new source/code reduction. No duplicated non-R payload or
R clone of at least 300 bytes was found; shared byte-compiled/environment chunks are not
assumed duplicates. No further safe payload removal preserved functions, security, debugging and guides. We rejected disabling byte compilation: a matched
historical installation shrank from 6,973,589 to 3,660,393 bytes, but first calls slowed
0.177→0.571 s (3.2x), repeated calls 0.567→1.167 s (about 2x). Default compilation supports
in-memory execution; optional source retention remains available, not forcibly disabled.


The unmet installed-size goal remains visible. Historical Windows oldrel-4/R 4.2.3
installed-size NOTE 9.8 Mb and earlier 9.7 Mb remain recorded. We request CRAN's
consideration of the necessary byte-compiled pure-R code and retained useful guides.

The complete check and remaining-gates wording below retain their historical snapshot.

## Historical complete check — exact 2e228d3 archive

On macOS arm64/R 4.5.0, the exact accepted 2e228d3 archive passes R CMD check
--as-cran --no-manual: Status OK, zero errors/warnings/notes, 30,187 test passes and 442
recorded skips. These are 415 On CRAN, 10 development, 9 live-provider, 5 missing-optional
(duckdb 4/keyring 1 in this check profile), 1 C-locale and 2 namespace guards. Current-time
verification is OK. Earlier clock NOTE/probes remain recorded, without inferred cause; guards stay enabled.
The check took 492.663 s, peak sampled process-family RSS 1,976.671875 MiB, 418 samples
without sampling errors. Logs and source/parent/owned cleanup pass; this is not R caller all-eight or live Windows acceptance.


That keep-source check tree is 10,063,849 B/Rdb 8,119,033 B; displayed 10.5 Mb/R 8.5 Mb
is INFO, distinct from the current default installation. No new full check is claimed.

## Remaining release gates

Accepted b240 source B2/B5 and six frontend scopes remain separate from fresh batches/native checks pending after the next build.
Browser/compact-prompt/three-line skill/four APT dependencies are integrated in clean 6619619; next normal/short-label check/new CI are queued.
Worker V2 and locked 4 GiB IM05 pass narrowly; original fan-out omission remains, corrected LIVE pending. Compact controls 57/334,44/308,9/97+lints 3 pass.
Qwen BASE/STEER dat/model-frame/numerics/all-eight/W0/replay0 pass without a connection-table claim; BASE false narration/orphan `</think>` and raw `<-` remain.
Modified Shiny widths/keyboard/200% pass under a private flag; original clipping/focus/CV/deadline failures and unmeasured R connections remain.
PTY retry 39.361 s is overall NONPASS: ioctl 120→80→120, only first incoming width observed; `!` Tab/error/REPL unreached. Earlier failures remain.
Guarded AppleScript/System Events RStudio fallback is user-authorized; fresh-artifact actual pending/Main untouched. Current CI/native Mac/GUI/site/docs/win-builder/merge/publication/final live Windows remain open.
At most four bounded families/10 GiB R caps/CPU 1: source batches 4 GiB each, at most two plus one 2 GiB light; internally parallel ≤2/CPU workers ≤12.
Finish Mac work first. Submission/release readiness is false; historical failures remain recorded.
