## Submission and verification

gptr 1.0.0 is pure R. Examples and all 14 precomputed guides run offline without credentials. CRAN submission is being prepared; final integration, Mac validation and live Windows verification remain open.

The exact 8bd0669 archive completed R CMD check --as-cran --no-manual on macOS arm64 with 30,538 passes, zero test failures/warnings and 445 accounted skips (418 On CRAN and 27 specific contexts or optional dependencies). The check reports one NOTE: unable to verify current time. Its strict controller result remains NONPASS; this environment check is not suppressed. The check took 560.925 s; sampled process-family peak RSS was 1,891.109 MiB. Earlier exact f48f825 checks passed with Status OK; those historical results do not replace the current NOTE. New fixes await a fresh combined check.

All 13 required 8bd0669 hosted checks passed, including actual Windows security/child-process bodies: 1,906 native assertions and 32 complete witnesses on each Windows host. Final live Windows client verification remains separate and last. New commits require current-head checks.

## Size and CRAN consideration

The default-byte-compiled 8bd0669 source archive is 2,654,589 B and installed package 6,989,727 B, including R/gptr.rdb 5,039,928 B. Installed doc/help/html are 1,224,500/485,484/15,771 B (combined documentation 1,725,755 B); extdata is 83,185 B and data 0. Inner build/install took 20.414/14.421 s; outer phases 22.096/15.266 s; whole family 43.544 s, sampled peak RSS 547.297 MiB.

The installed 5 MB goal remains unmet. Source is below 10 MB and documentation/data below 5 MB each. The keep-source check installation is a separate profile: 10,069,946 B with Rdb 8,129,353 B; its 10.5 Mb size message is INFO. Windows oldrel-4/R 4.2.3 retains the installed-size NOTE of 9.8 Mb; earlier 9.7 Mb NOTES remain disclosed. We request CRAN's consideration of the necessary byte-compiled pure-R code, security and debugging support, and useful guides.

Default installation already omits optional source-retention metadata. A matched historical comparison measured 6,962,112 B normally versus 10,047,490 B with R_KEEP_PKG_SOURCE=yes; Rdb grew by 3,083,893 B. This measures optional debugging cost, not a new reduction. No duplicated non-R payload or R clone of at least 300 bytes was found; shared byte-compiled/environment chunks are not assumed duplicates.

Disabling byte compilation reduced a matched historical installation from 6,973,589 to 3,660,393 B, but first calls slowed 0.177 to 0.571 s and repeated calls 0.567 to 1.167 s. Those measurements do not establish all-eight-state benchmark acceptance. We retained compilation for in-memory execution, optional source retention for debugging, all functions, security controls and 14 guides. No further safe removal has been demonstrated.

## Remaining checks

Fresh combined build/install, relevant regressions, as-cran and current-head CI follow the tested helper, Shiny guidance and browser shutdown corrections. Native Mac frontend/browser workflows, responsive documentation publication and reviewed merge remain open. Strict Quarto renderer-closure serialization and model-output style limitations retain their documented scopes. Complete Mac work before final live Windows verification and submission. See dev/TESTING_PLAN.md for the live status and preserved evidence.
