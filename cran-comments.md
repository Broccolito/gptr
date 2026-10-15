## Submission and check results

gptr 1.0.0 is pure R. Its 14 precomputed guides and package examples run offline without credentials. CRAN submission is being prepared; no submission is claimed.

As of source revision `bc13abaa` (candidate J), the exact archive completed `R CMD check --as-cran --no-manual` using R 4.6.1 on macOS arm64 with Status OK: zero errors, warnings or notes. Tests reported 30,600 passed assertions and 446 accounted skips (421 On CRAN and 25 specific); all 59 example sections completed. The check took 474.206 s with a sampled process-family RSS peak of 2,120.171875 MiB. All 15 retained raw logs were clear under the strengthened warning/error matcher; source, input and cleanup checks passed.

This result applies to J only. The next candidate, incorporating three additional small fixes, requires a fresh normal build/install and full check. Earlier clock-NOTE and incoming-metadata transport failures remain recorded; this successful check does not establish their cause or a network/clock repair. Windows native bodies are guarded out of this Mac check, so it provides no new Windows acceptance.

## Size and CRAN consideration

J's normal build retains default byte compilation. Its source archive is 2,659,416 B and its normal installation is 7,010,625 B, including `R/gptr.rdb` at 5,044,726 B. Installed doc/help/html occupy 1,225,617/487,454/16,084 B (combined documentation 1,729,155 B); extdata is 83,185 B and data is 0. The largest files are the Rdb, help Rdb (258,743 B), logos, risk table and guides.

The outer build/install phases took 22.104/15.105 s; their inner R timings were 20.470/14.274 s. The whole normal family took 43.471 s with a sampled RSS peak of 527.90625 MiB. The separate `R_KEEP_PKG_SOURCE=yes` check installation is 10,097,097 B with Rdb 8,139,173 B. Its displayed 10.5 Mb installed-size result is INFO, not a NOTE. Normal and source-retaining check installations are distinct profiles.

The project's installed-size goal of less than 5 MB remains unmet. The source archive is below 10 MB, and documentation and data are below 5 MB each. We request CRAN's consideration of the byte-compiled pure-R functionality, security controls, optional debugging support and 14 offline guides. Historical Windows installed-size NOTES at 9.7/9.8 Mb remain reported; the Mac INFO result does not waive them or establish CRAN size acceptance.

A historical safe-reduction comparison made the 713 archive/installation 189/214 B smaller than accepted 8bd. Default installation already omits optional source-retention metadata. The recorded size review found no duplicated non-R payload or standalone R clone of at least 300 B; shared compiled/environment chunks were not treated as removable duplicates. That review did not justify further removal while preserving the required functionality, debugging support and guides. The next candidate's sizes remain to be measured.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed from 0.177 to 0.571 s (about 3.2 times) and repeated calls from 0.567 to 1.167 s (about 2 times). This was not a fresh R 4.6.1 benchmark or all-eight-state acceptance. Default byte compilation remains enabled for execution performance; optional source retention remains available for debugging.

## Remaining verification

The next candidate's normal build/install and full check, remaining native frontend/workspace and GUI verification, final live Windows verification, final-head CI, merge/main synchronization and deployed-site verification remain separate release gates. Detailed failures and scoped acceptances are retained in `dev/TESTING_PLAN.md`. Update the measurements from the final settled archive before submission. No CRAN submission or release readiness is claimed.
