## Submission and check results

gptr 1.0.0 is pure R. All 14 precomputed guides and package examples run offline without credentials. CRAN submission is being prepared; no submission is claimed. README installation targets GitHub `main`.

The exact 1f9c189 archive completed `R CMD check --as-cran --no-manual` on macOS arm64 with 30,565 passed assertions, zero test failures/warnings and 445 accounted skips (418 On CRAN/27 specific). It reports one NOTE: unable to verify current time. The strict controller remains NONPASS; this NOTE is not suppressed. Elapsed 573.627 s, sampled family RSS 1,961.375 MiB (487 valid samples, no sampling errors). All 100 traced owned process identities were absent after cleanup. The primary baseline clock probe also fails before datetime parsing; no clock skew or exclusive network/certificate cause is established.

All13 required1f9 hosted checks passed; both Windows hosts independently recorded31646 ordinary assertions/107 skips and1906 native assertions/32 original witnesses/one native skip, zero failures or warnings. Windows oldrel-4 retains its sole9.8Mb installed-size NOTE. Hosted Mac StatusOK is distinct from the local clock NOTE. Five private Mac source sessions pass200 files/4208 cases/33358 assertions/44 admitted skips with caller/connections/cleanup gates. One direct test-owned ps_find_tree warning remains qualified; captured wrapper/production warnings are empty. Four plan tools pass119.475s. These preceding results do not replace current-correction checks or final live Windows verification.

## Size and CRAN consideration

Default byte compilation is retained. Source archive: 2,655,073 B; normal installation: 6,990,541 B, including `R/gptr.rdb` 5,039,747 B. Installed doc/help/html: 1,224,500/486,340/15,771 B (combined 1,726,611 B); extdata 83,185 B/data 0. The Rdb is the largest file, followed by help Rdb (257,642 B), useful logos, risk tables and guides.

Inner build/install: 20.786/14.640 s; outer phases: 22.004/16.210 s; whole family: 44.598 s/516.234 MiB sampled. The separate `R_KEEP_PKG_SOURCE=yes` check installation is 10,070,041 B with Rdb 8,129,227 B; its 10.4 Mb size message is INFO.

The installed 5 MB goal remains unmet. The source archive is below 10 MB; documentation/data are below 5 MB each. We request CRAN's consideration of the necessary byte-compiled pure-R functionality, security, useful debugging support and 14 guides. Historical Windows 9.7/9.8 Mb size NOTES are retained rather than waived.

Earlier safe reductions made the713 archive/install 189/214 B smaller than accepted8bd. The current host-event-yield fix adds673/1,028 B relative to713; these sizes include the latest normal build. Default installation already omits optional source-retention metadata. Review found no duplicated non-R payload or R clone of at least 300 B; shared compiled/environment chunks are not treated as removable duplicates. No further safe removal has been demonstrated.

## Historical measurements retained

Accepted 8bd normal profile: archive 2,654,589 B; installation 6,989,727 B/Rdb 5,039,928 B; doc/help/html 1,224,500/485,484/15,771 B (combined 1,725,755 B); extdata 83,185 B/data 0. Inner build/install 20.414/14.421 s; outer 22.096/15.266 s; whole 43.544 s/547.297 MiB. Its clock-NOTE check took 560.925 s/1,891.109 MiB. Earlier exact f48 check had Status OK; it does not replace the current NOTE.

A matched historical comparison measured 6,962,112 B normally versus 10,047,490 B with `R_KEEP_PKG_SOURCE=yes`; Rdb grew 3,083,893 B. This measures optional debugging cost, not a new reduction.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed 0.177 to 0.571 s (about 3.2 times) and repeated calls 0.567 to 1.167 s (about 2 times). Those measurements do not establish all-eight-state benchmark acceptance. We retained compilation for in-memory execution, optional source retention for debugging, all functions, security controls and 14 guides.

## Remaining verification

The reactor host-event yield passes47 focused cases/239 assertions. Actual native tracing subsequently established that R tool option restoration rolled back a genuine RStudio resize. The new two-file correction preserves only a valid changed host metric already paired with the current width option; other options and ordinary widths restore. All37 focused cases/286 assertions and two configured lints pass, with caller/connections/cleanup gates. The baseline has six failures confined to the new paired-resize case. It is integrated at1d0e40f; fresh normal size/build, combined source/as-cran, native production resizing and final-head CI remain pending. The preceding1f9 sizes and complete check above are not measurements of this correction.

Native Mac clients, reviewed merge/main synchronization and actual current Pages deployment remain open; final live Windows verification is last. Jupyter's seven saved cells/errors0 pass, but its Unknown connection and25ping+one401 host warnings retain strict NONPASS; a private dependency compatibility fix is under review. The approved private UTM image/app/R installer are verified, but no VM is created or booted and isolated R.app verification is unrun. The saved Shiny GUI pass does not erase the genuine live deadline failure. Scientific tool-error, strict Quarto client-closure and allocator-emitter limitations remain recorded in dev/TESTING_PLAN.md. Update outcomes and sizes from settled evidence before submission; no submission or release readiness is claimed.
