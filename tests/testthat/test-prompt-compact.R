# P07 compaction: the threshold (Task 6), harness state (Task 12), the trigger, the checkpoint
# compactor and INFRA-26 (Task 13).

test_that("compact_threshold follows architecture 6.11", {
  expect_equal(compact_threshold(32768, 4096), 16384)
  expect_equal(compact_threshold(131072, 8192), 101072)
  expect_equal(compact_threshold(200000, 8192), 170000)
  expect_equal(compact_threshold(200000, 64000), 128000)
  expect_equal(compact_threshold(1e6, 64000), 200000)
  expect_equal(compact_threshold(8192, 1024), -8192)
  expect_equal(compact_threshold(NA, 1024), 200000)
  expect_equal(compact_threshold(200000, NA), 170000)
  local_gptr_options(compact_at = Inf)
  expect_equal(compact_threshold(1e6, 64000), 900000)
  local_gptr_options(compact_at = 50000)
  expect_equal(compact_threshold(200000, 8192), 50000)
})

test_that("NA in gptr.compact_at disables the cap", {
  local_gptr_options(compact_at = NA)
  expect_equal(compact_threshold(1e6, 64000), 900000)
  expect_equal(compact_threshold(NA, 1024), Inf)
})

test_that("compact_threshold keeps the contract 7.7 signature", {
  expect_identical(names(formals(compact_threshold)), c("window", "max_output", "r_cap"))
  expect_identical(formals(compact_threshold)$r_cap, 4000)
})

test_that("compact_at comes from the settings service; a null setting disables the cap", {
  local_gptr_options(compact_at = NULL)
  seen = new.env()
  local_mocked_bindings(service_lookup = function(name) {
    if (identical(name, "settings.get")) {
      function(key, session = NULL) {
        seen$key = key
        seen$value
      }
    }
  })
  expect_equal(compact_threshold(1e6, 64000), 900000)
  expect_identical(seen$key, "compact_at")
  seen$value = 120000
  expect_equal(compact_threshold(200000, 8192), 120000)
  expect_equal(compact_threshold(NA, 1024), 120000)
})
