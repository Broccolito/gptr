## Submission and verification

gptr 1.0.0 rewrites 0.7.0 as a pure-R agent harness in the live R session; no native compilation. Model access is opt-in; examples and the 14
precomputed guides run offline without keys. External programs/providers serve only selected features.

On macOS arm64/R 4.5.0, the exact accepted 2e228d3 archive passes R CMD check
--as-cran --no-manual: Status OK, zero errors/warnings/notes, 30,187 test passes and 442
recorded skips. These are 415 On CRAN, 10 development, 9 live-provider, 5 missing-optional
(duckdb 4/keyring 1 in this check profile), 1 C-locale and 2 namespace guards. Current-time
verification is OK. Earlier clock NOTE/probes remain recorded, without inferred cause; guards stay enabled.
The check took 492.663 s, peak sampled process-family RSS 1,976.671875 MiB, 418 samples
without sampling errors. Logs and source/parent/owned cleanup pass; this is not R caller all-eight or live Windows acceptance.

## Size, reductions and CRAN consideration

Normal default-byte-compiled sizes (logical bytes): source archive 2,641,484; installed
package 6,980,069; R/gptr.rdb 5,030,313; doc/help/html 1,224,500/485,942/15,771, combined
1,726,213; extdata 83,185; data 0. All 14 guides remain. Largest installed: R/gptr.rdb and help/gptr.rdb (257,235). Largest source:
permission classifier (128,904) and replay tests (107,055). Archive, documentation and data meet our
10/5/5 MB targets; installation remains above the 5 MB target.

Default installation already omits optional source-retention metadata. A historical matched
archive comparison measured installed 6,962,112 bytes normally versus 10,047,490 with
R_KEEP_PKG_SOURCE=yes; Rdb 5,009,974 versus 8,093,867 (3,083,893-byte increase). This
measures opt-in debug cost, not a new source/code reduction. No duplicated non-R payload or
R clone of at least 300 bytes was found; shared byte-compiled/environment chunks are not
assumed duplicates. No further safe payload removal preserved functions, security, debugging and guides. We rejected disabling byte compilation: a matched
historical installation shrank from 6,973,589 to 3,660,393 bytes, but first calls slowed
0.177→0.571 s (3.2x), repeated calls 0.567→1.167 s (about 2x). Default compilation supports
in-memory execution; optional source retention remains available, not forcibly disabled.

Guarded outer build/install phases took 22.374/15.257 s; inner R tools 20.699/14.454 s;
Whole 43.818 s/556.5 MiB sampled RSS (35 samples/no errors).
The check uses R_KEEP_PKG_SOURCE=yes: its final logical installed tree is 10,063,849 bytes,
R/gptr.rdb 8,119,033. The log's total 10.5 Mb/R 8.5 Mb is INFO, distinct from the normal
installation and these logical counts; no displayed-unit conversion is inferred.
Current Windows oldrel-4/R 4.2.3 retains installed-size NOTE 9.8 Mb; historical 9.7 Mb
(Rdb 8,117,319 bytes) remains recorded. The Mac check has no size NOTE. Our 5 MB target
is not a universal CRAN total-size rule. We request CRAN's consideration of the necessary
byte-compiled pure-R code and unmet installed-size goal.

## Remaining release gates

All 200 source files ran; batches 1/3/4 are accepted. Batches 2/5 retain cold-state NONPASS;
Repr/magick/observer/provenance/writer/SDK persistence fixes are integrated in code checkpoint
5ec8642; fresh artifact/combined and hosted checks are pending.
Haiku input fidelity, fresh model-summary fidelity, Shiny/native Chrome and Mac native/
provider/IM05 checks remain open. Fixed-width PTY is a scoped pass, without default ANSI or
active-resize proof. CI finished 12 successes/1 Windows release startup failure; oldrel-4
success does not cure it. Earlier plan setup failure remains; the source-checked correction awaits hosted proof. Single-session 4 GiB refusal remains.
Win-builder, reviewed main merge/publication and final live Windows verification after Mac
work remain pending. Submission/release readiness is false; full history remains in Git and development records.
