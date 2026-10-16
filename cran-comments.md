## Submission and check results

gptr 1.0.0 is pure R. Its 14 precomputed guides and package examples run offline without credentials. CRAN submission is being prepared; no submission is claimed.

The exact candidate K archive from source `2bf18595` completed `R CMD check --as-cran --no-manual` with R 4.6.1 on macOS arm64: Status OK, zero errors, warnings or notes. Tests reported 30,643 passed assertions and 446 accounted skips (421 On CRAN and 25 specific); all 59 example sections completed. The check took 491.329 s with a sampled process-family RSS peak of 2,187.625 MiB. All 15 retained raw logs were clear; source, input and cleanup checks passed, including independent absence of all 98 sampled owned process identities.

This Mac check leaves NOT_CRAN unset. Our expanded historical Windows CI profile explicitly set NOT_CRAN=true and took 49m04 for the check (51m33 for the job), including optional integration, security and native tests skipped on CRAN. We retain that longer timing for transparency; the different platform, source and test profile prevent direct comparison or a Windows CRAN-timing claim. Current hosted Windows results and final live Windows verification remain separate. Earlier clock-NOTE and incoming-metadata transport failures remain recorded; the successful Mac check does not establish their cause or a network/clock repair.

## Size and CRAN consideration

K's normal build retains default byte compilation. Its source archive is 2,660,769 B and its normal installation is 7,012,965 B, including `R/gptr.rdb` at 5,046,506 B. Installed doc/help/html occupy 1,225,617/487,994/16,084 B (combined documentation 1,729,695 B); extdata is 83,185 B and data is 0. The largest files are the Rdb, help Rdb (259,281 B), logos, risk table and guides. The separately verified standard-user installation is 7,007,800 B with Rdb 5,046,404 B; installation profiles are measured separately.

The outer normal build/install phases took 22.509/16.595 s; inner R timings were 21.544/14.878 s. The whole normal family took 46.508 s with a sampled RSS peak of 497.359375 MiB. Standard-user update and ordinary loading took 19.226 s with a sampled peak of 333.625 MiB. The separate R_KEEP_PKG_SOURCE=yes check installation is 10,099,974 B with Rdb 8,141,788 B. Its displayed 10.6 Mb installed-size result is INFO, not a NOTE. Normal and source-retaining check installations are distinct profiles.

The project's installed-size goal of less than 5 MB remains unmet. The source archive is below 10 MB, and documentation and data are below 5 MB each. We request CRAN's consideration of the byte-compiled pure-R functionality, security controls, optional debugging support and 14 offline guides. Historical Windows installed-size NOTES at 9.7/9.8 Mb remain reported; the Mac INFO result does not waive them or establish CRAN size acceptance.

A historical safe-reduction comparison made the 713 archive/installation 189/214 B smaller than accepted 8bd. Default installation already omits optional source-retention metadata. The finite size review found no duplicated non-R payload or standalone R clone of at least 300 B; shared compiled/environment chunks were not treated as removable duplicates. No further removal was justified while preserving required functionality, debugging support and guides. K adds 2,340 B installed and 1,353 B archived over J; the measured Rdb increase is 1,780 B. These are size differences, not an attribution to one change.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed from 0.177 to 0.571 s (about 3.2 times) and repeated calls from 0.567 to 1.167 s (about 2 times). This was not a fresh R 4.6.1 benchmark or all-eight-state acceptance. Default byte compilation remains enabled for execution performance; optional source retention remains available for debugging.

## Verification boundaries

These measurements identify K's exact accepted archive. Subsequent release-note-only changes are excluded by .Rbuildignore and must preserve all 667 public inputs. Native client results, hosted CI, merge/main synchronization, deployed-site verification and final live Windows verification have separate evidence in dev/TESTING_PLAN.md and its linked local ledger. Final live Windows verification follows all Mac work. No CRAN submission or release readiness is claimed.
