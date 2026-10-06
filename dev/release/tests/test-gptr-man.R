# Checks gptr's own manual (plan P25, Tasks 2 and 3). A failure lists the open problems.
test_that("gptr's help topics exist and ?peter links them (Task 2)", {
  db = rd_read_dir(file.path(gptr_root(), "man"))
  expect_no_problems(grep("^(gptr_options|gptr_security|gptr_egress): |^peter: @seealso",
                          docs_problems(db), value = TRUE))
})
