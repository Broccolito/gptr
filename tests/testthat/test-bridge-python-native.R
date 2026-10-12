# Provisioned native acceptance; missing capabilities remain fatal in the strict CI lane.
test_that("native GPTR Python startup preserves R state and uses its private numerical runtime", {
  skip_on_cran()
  py_native_expect("first")
})

test_that("native GPTR Python startup admits an unrelated unchanged empty entry", {
  skip_on_cran()
  py_native_expect("unrelated")
})

test_that("native GPTR Python startup restores absent setup entries and supports later imports", {
  skip_on_cran()
  py_native_expect("absent")
})

test_that(
  "native Windows Python startup refuses an empty known setup entry before initialization", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "native Windows startup refusal")
  py_native_expect("empty")
})

test_that("native Windows Python startup refuses an empty case alias before initialization", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "native Windows startup refusal")
  py_native_expect("alias")
})

test_that("native Windows initialized Python preserves an untouched empty setup entry", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "native Windows initialized empty entry")
  py_native_expect("initialized")
})
