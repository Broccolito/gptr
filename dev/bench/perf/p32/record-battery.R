# Record the P32 decision battery and rewind fixtures (tests/testthat/fixtures/perm/) from this
# tree, through the test file itself in record mode. P32 records them once, at main 5e2992b; a
# later task re-records only for a change its plan names. From the repository root:
#   R_LIBS_USER=<dev library> Rscript --vanilla dev/bench/perf/p32/record-battery.R
unlink(file.path("tests", "testthat", "fixtures", "perm", c("battery.json", "rewind.json")))
Sys.setenv(GPTR_RECORD_BATTERY = "true")
status = system2(file.path(R.home("bin"), "Rscript"),
                 c("--vanilla", "dev/ci/isolated-check.R", "test", "perm-battery"))
stopifnot(status == 0L)
