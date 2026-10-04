# Atomic writes (Task 5); paths, homes, workspace, serialisation leaves and path classes (Task 6).

test_that("write_atomic() writes UTF-8 lines with LF, or raw bytes, and replaces files", {
  dir = withr::local_tempdir()
  path = file.path(dir, "out.txt")
  write_atomic(path, c("caf\u00e9", "two"))
  expect_identical(
    readBin(path, "raw", 100),
    c(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)), charToRaw("\ntwo\n"))
  )
  write_atomic(path, as.raw(c(0x61, 0x0d, 0x0a)))
  expect_identical(readBin(path, "raw", 100), as.raw(c(0x61, 0x0d, 0x0a)))
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 1L)
  expect_error(
    write_atomic(file.path(dir, "no", "such.txt"), "x"), class = "gptr_error_invalid_argument"
  )
  expect_error(write_atomic(path, 1:3), class = "gptr_error_invalid_argument")
})

test_that("write_atomic() falls back to an in-place write when rename keeps failing (IC-51)", {
  dir = withr::local_tempdir()
  path = file.path(dir, "locked.txt")
  writeLines("old", path)
  local_mocked_bindings(file_rename = function(from, to) FALSE)
  write_atomic(path, "new")
  expect_identical(readLines(path, encoding = "UTF-8"), "new")
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 1L)
})

test_that("write_atomic() refuses the in-place write when the file changed meanwhile", {
  dir = withr::local_tempdir()
  path = file.path(dir, "busy.txt")
  writeLines("old", path)
  local_mocked_bindings(file_rename = function(from, to) {
    writeLines("changed by someone else", to)
    FALSE
  })
  expect_error(write_atomic(path, "new"), class = "gptr_error_doc_write")
  expect_identical(readLines(path, encoding = "UTF-8"), "changed by someone else")
})

test_that("write_atomic() keeps the permission bits of the file it replaces", {
  skip_on_os("windows")
  dir = withr::local_tempdir()
  path = file.path(dir, "run.sh")
  writeLines("echo old", path)
  Sys.chmod(path, "0755", use_umask = FALSE)
  write_atomic(path, "echo new")
  expect_identical(format(file.info(path)$mode), "755")
})
