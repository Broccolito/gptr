## Submission and check results

gptr 1.0.0 is pure R. All 14 precomputed guides and package examples run offline without credentials. CRAN submission is being prepared; no submission is claimed. README installation targets GitHub `main`.

The exact 713ba29 archive completed `R CMD check --as-cran --no-manual` on macOS arm64 with 30,550 passed assertions, zero test failures/warnings and 445 accounted skips (418 On CRAN/27 specific). It reports one NOTE: unable to verify current time. The strict controller remains NONPASS; this NOTE is not suppressed. Elapsed 554.842 s, sampled family RSS 1,877.578 MiB. The primary baseline clock probe also fails before datetime parsing; no clock skew or exclusive network/certificate cause is established.

All 13 required current713 hosted checks succeed, including both Windows hosts: 1,906 native assertions/32 complete witnesses and 31,631 ordinary assertions each, zero failures/warnings, 107 ordinary skips/one native skip. The Windows oldrel-4 installed-size NOTE of 9.8 Mb remains disclosed. Five independent Mac source sessions separately pass 200 files/4,205 cases/33,343 assertions/44 admitted skips; four plan tools pass in 118.110 s. These do not replace final live Windows verification.

## Size and CRAN consideration

Default byte compilation is retained. Source archive: 2,654,400 B; normal installation: 6,989,513 B, including `R/gptr.rdb` 5,039,714 B. Installed doc/help/html: 1,224,500/485,368/15,771 B (combined 1,725,639 B); extdata 83,185 B/data 0. The Rdb is the largest file, followed by help Rdb (256,680 B), useful logos, risk tables and guides.

Inner build/install: 21.017/14.759 s; outer phases: 22.325/16.445 s; whole family: 45.252 s/516.516 MiB sampled. The separate `R_KEEP_PKG_SOURCE=yes` check installation is 10,069,662 B with Rdb 8,129,040 B; its 10.5 Mb size message is INFO.

The installed 5 MB goal remains unmet. The source archive is below 10 MB; documentation/data are below 5 MB each. We request CRAN's consideration of the necessary byte-compiled pure-R functionality, security, useful debugging support and 14 guides. Historical Windows 9.7/9.8 Mb size NOTES are retained rather than waived.

Compared with accepted 8bd, archive/install are 189/214 B smaller. Default installation already omits optional source-retention metadata. Review found no duplicated non-R payload or R clone of at least 300 B; shared compiled/environment chunks are not treated as removable duplicates. No further safe removal has been demonstrated.

## Historical measurements retained

Accepted 8bd normal profile: archive 2,654,589 B; installation 6,989,727 B/Rdb 5,039,928 B; doc/help/html 1,224,500/485,484/15,771 B (combined 1,725,755 B); extdata 83,185 B/data 0. Inner build/install 20.414/14.421 s; outer 22.096/15.266 s; whole 43.544 s/547.297 MiB. Its clock-NOTE check took 560.925 s/1,891.109 MiB. Earlier exact f48 check had Status OK; it does not replace the current NOTE.

A matched historical comparison measured 6,962,112 B normally versus 10,047,490 B with `R_KEEP_PKG_SOURCE=yes`; Rdb grew 3,083,893 B. This measures optional debugging cost, not a new reduction.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed 0.177 to 0.571 s (about 3.2 times) and repeated calls 0.567 to 1.167 s (about 2 times). Those measurements do not establish all-eight-state benchmark acceptance. We retained compilation for in-memory execution, optional source retention for debugging, all functions, security controls and 14 guides.

## Remaining verification

A subsequent minimal reactor host-event yield passes 47 focused cases/239 assertions and two configured lints, preserving measured caller state and cleanup. Its fresh combined build/check, affected live workflows, native resizing and current-head CI are pending; the measurements above remain exact713 evidence.

Native Mac client/event-yield verification, reviewed merge/main synchronization and current public deployment remain open; live Windows client verification is last. The saved Shiny GUI pass does not erase the genuine live deadline failure. Original scientific tool-error, strict Quarto client-closure and Jupyter host-warning NONPASS scopes remain recorded in `dev/TESTING_PLAN.md`. R.app's outstanding window/preference isolation needs a suitable separate GUI environment or deferral; its private test permission is already granted. Update remaining outcomes from settled evidence before submission.
