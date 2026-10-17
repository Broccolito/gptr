# Windows CI

The Windows workflow runs four independent serial R CMD checks for each of release
and oldrel-4. Ordinary files are partitioned without overlap; all native fixtures stay
in their original fresh R CMD check entry processes, in shard1 only. Default and
CRAN-mode entry paths keep their original complete suite.

Required contexts `windows-latest (release)` and `windows-latest (oldrel-4)` are
aggregate gates. Every shard must pass, then the gate audits the exact commit's actual
file inventory, native output and check status. Failed, missing, duplicate or foreign
results cannot produce a green required status. The existing serial Linux
`NOT_CRAN=false` job is unchanged.

Rtools is not additionally installed: gptr has no compilation and a cold-cache oldrel
dependency/source-install probe passed (42 assertions), run `39002216479`. The hosted
image's preinstalled tools remain. Every full check still uses the standard check
action, `--as-cran --no-manual`, warning failure and the completed Status-line guard.
No package runtime dependency, test body, resource limit or deadline is relaxed.

Local regressions:
`Rscript --vanilla -e 'testthat::test_dir("dev/ci/windows", stop_on_failure = TRUE)'`.
Expected: 45 pass, 0 failures/warnings/skips.

Baseline passing run `38993976551`: release 46m24s, oldrel-4 51m27s. A newer main
release run took 33m29s; hosted-runner variation matters. Two file workers alone
passed release in 31m54s and missed the target. Independent serial shards and removal
of redundant native execution are measured separately; complete production-workflow
timing and aggregate coverage are still pending validation. Target: <30m, preferably <20m.
