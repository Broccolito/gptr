# Windows CI

`.github/workflows/Windows-check.yaml` runs `R CMD check --as-cran` on Windows release and
oldrel-4 as four serial shards each. `GPTR_CI_TEST_SHARD=<n>/4` makes `tests/testthat.R` run every
fourth ordinary test file (`tests/testthat/ci-shard.R`) and fail unless exactly those files ran;
the native fixtures (`tests/native-*.R`) run in shard 1 only. Unset, a check runs the whole suite.

The required contexts `windows-latest (release)` and `windows-latest (oldrel-4)` are gates that
always run and pass only when each of their version's four shards uploaded a pass marker (from
any attempt of the run). Nothing compiles, so the shards install no Rtools and point `R_QPDF` at
the image's qpdf, which R 4.2 does not find. Local test:
`Rscript --vanilla -e 'testthat::test_dir("dev/ci/windows")'`.
