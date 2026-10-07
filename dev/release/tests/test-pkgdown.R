test_that("pkgdown_yaml() lists every page once, secondary group members never", {
  parsed = yaml::yaml.load(paste(pkgdown_yaml(), collapse = "\n"))
  listed = unlist(lapply(parsed$reference, `[[`, "contents"))
  expect_false(anyDuplicated(listed) > 0L)
  expect_false(any(c("gptr_logout", "gptr_agents", "gptr_mcp_remove", "gptr_resume",
                     "gptr_last", "gptr_checkpoints") %in% listed))
  expect_length(listed, 63L - 6L + 3L)
  expect_true(all(c("peter", "gptr_login", "gptr_sessions", "gptr_security") %in% listed))
  expect_setequal(unlist(lapply(parsed$articles, `[[`, "contents")), rel_vignettes())
})

test_that("pkgdown_extra() and pkgdown_problems() keep the index complete", {
  db = rd_read_dir(toy_man(list(peter = rd_page("peter"),
                                print.gptr_session = rd_page("print.gptr_session"),
                                hidden = rd_page("hidden", keywords = "internal"))))
  expect_identical(pkgdown_extra(db), "print.gptr_session")
  expect_identical(pkgdown_problems(pkgdown_yaml(extra = "print.gptr_session"), db),
                   character())
  expect_match(pkgdown_problems(pkgdown_yaml(), db), "out of date")
})
