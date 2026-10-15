## Submission and check results

gptr 1.0.0 is pure R. All 14 precomputed guides and package examples run offline without credentials. CRAN submission is being prepared; no submission is claimed. README installation targets GitHub `main`.

As of source revision `f5f389c`, the exact archive completed `R CMD check --as-cran --no-manual` using R 4.6.1 on macOS arm64 with Status OK: zero errors, warnings or notes. Tests reported 30,599 passed assertions and 446 accounted skips (421 On CRAN and 25 specific); all 59 example sections completed. The bounded check took 486.845 s with a sampled process-family RSS peak of 2,084.56 MiB. Raw logs, source inputs and cleanup checks passed.

This result applies to the f5 archive. The final integration archive and its build/check results remain pending. Earlier clock-NOTE results remain historical failures; the successful f5 check does not establish their cause or a clock/network repair. Windows native test bodies are guarded out of this Mac check, so it provides no new Windows acceptance.

## Size and CRAN consideration

The f5 normal build retains default byte compilation. Source archive: 2,656,461 B; normal installation: 7,006,968 B, including `R/gptr.rdb` 5,044,669 B. Installed doc/help/html: 1,223,506/486,051/16,084 B (combined documentation 1,725,641 B); extdata 83,185 B and data 0. The Rdb is the largest file, followed by help Rdb (257,357 B), logos, risk tables and guides.

The normal build/install phases took 20.771/15.132 s; the whole family took 41.779 s with a sampled RSS peak of 496.08 MiB. The separate `R_KEEP_PKG_SOURCE=yes` check installation is 10,095,041 B with Rdb 8,139,179 B. Its displayed 10.5 Mb installed-size result is INFO, not a NOTE. These are f5 measurements, not final integration measurements.

The project's installed 5 MB goal remains unmet. The source archive is below 10 MB; documentation and data are below 5 MB each. We request CRAN's consideration of the byte-compiled pure-R functionality, security controls, optional debugging support and 14 offline guides. Historical Windows 9.7/9.8 Mb installed-size NOTES remain reported; the Mac INFO result does not waive them or establish CRAN size acceptance.

A historical safe-reduction comparison made the 713 archive/installation 189/214 B smaller than accepted 8bd. Default installation already omits optional source-retention metadata. The recorded size review found no duplicated non-R payload or standalone R clone of at least 300 B; shared compiled/environment chunks were not treated as removable duplicates. That review did not justify further removal while preserving the required functionality, debugging support and guides. Final integration sizes remain to be measured.

## Historical measurements retained

Accepted 8bd normal profile: archive 2,654,589 B; installation 6,989,727 B/Rdb 5,039,928 B; doc/help/html 1,224,500/485,484/15,771 B (combined 1,725,755 B); extdata 83,185 B/data 0. Inner build/install 20.414/14.421 s; outer 22.096/15.266 s; whole 43.544 s/547.297 MiB. Its clock-NOTE check took 560.925 s/1,891.109 MiB. The later 1f9 check also retained the unable-to-verify-current-time NOTE. Those outcomes remain recorded alongside the newer f5 Status OK result.

A matched historical comparison measured 6,962,112 B normally versus 10,047,490 B with `R_KEEP_PKG_SOURCE=yes`; Rdb grew 3,083,893 B. This measures optional debugging cost, not a new reduction.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed 0.177 to 0.571 s (about 3.2 times) and repeated calls 0.567 to 1.167 s (about 2 times). These are historical measurements, not a fresh R 4.6.1 benchmark or all-eight-state acceptance. We retained byte compilation for execution performance and optional source retention for debugging, with all functions, security controls and 14 guides preserved.

## Remaining verification

Final integration build/install/check results, remaining native Mac frontend/workspace and GUI verification, final live Windows verification, final-head CI, merge/main synchronization and current deployed-site verification remain separate release gates. Detailed live failures and scoped acceptances are retained in `dev/TESTING_PLAN.md`; neither this Mac check nor earlier GUI evidence establishes their completion. Update this document from the final settled archive before submission. No CRAN submission or release readiness is claimed.
