## Submission and verification

gptr 1.0.0 is a pure-R agent harness in the live R session; no native compilation.
Models are opt-in; examples and all 14 precomputed guides run offline without keys.
The accepted package source/normal artifact is b240e63; later changes only touch excluded
plan, CI and checkpoint files. Build/install is accepted; its
complete original-archive as-cran check and release acceptance remain pending.

## Current size and CRAN consideration

Normal default-byte-compiled logical bytes: archive 2,652,699; installed 6,989,699;
R/gptr.rdb 5,038,679; doc/help/html 1,224,500/487,099/15,771 (combined 1,727,370);
data 0. The largest installed files are R/gptr.rdb and help/gptr.rdb (258,375).
All 121 R sources/14 guide pairs and 79 read-only installed files/five MD5s match.
Archive, documentation and data meet our 10/5/5 MB goals; installation exceeds 5 MB.
Root/independent receipts 4f6f72cc/52883847 accept build/install only, certificate `77b5b4bb`.
Five logs are quiet; build/install/owned cleanup pass. Whole 45.366 s/522.921875 MiB,
36 samples/no sampling errors; outer build/install 22.288/16.545 s, inner 21.130/14.874 s.
No source stripping, disabled byte compilation or new code reduction is claimed.

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

Current B2/B5 pass 80 files/1,488 cases/9,276 assertions/14 admitted skips with caller
states/connections/cleanup preserved; prior B1/B3/B4 remain scoped at 2e228d3. Six current
frontend cells pass narrowly; strict Quarto serialized-state NONPASS remains. Shiny v002
is overall NONPASS (300 s GUI lease/CV/websocket); saved v002 model-free GUI is prepared.
IM05's 4 GiB allocation/8 GiB cap fails private head/tail namespace; V5 is queued. Stronger
fan-out private assertions fail; V2 is prepared, with no production defect/retry claimed.
Next plan/CI/full archive checks, native Mac/GUI, site/docs, win-builder, reviewed merge/
publication and final live Windows verification remain pending; old Windows jobs are separate.
Finish Mac work first. Submission/release readiness is false; historical failures remain recorded.
