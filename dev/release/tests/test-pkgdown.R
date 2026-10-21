test_that("pkgdown_yaml() lists every page once, secondary group members never", {
  parsed = yaml::yaml.load(paste(pkgdown_yaml(root = gptr_root()), collapse = "\n"))
  expect_identical(parsed$url, "https://broccolito.github.io/gptr/")
  expect_identical(parsed$repo$branch, "main")
  listed = unlist(lapply(parsed$reference, `[[`, "contents"))
  expect_false(anyDuplicated(listed) > 0L)
  expect_false(any(c("gptr_logout", "gptr_agents", "gptr_mcp_remove", "gptr_resume",
                     "gptr_last", "gptr_checkpoints") %in% listed))
  expect_length(listed, 64L - 6L + 4L)
  expect_true(all(c("peter", "gptr_login", "gptr_sessions", "gptr_export",
                    "gptr_security") %in% listed))
  expect_setequal(unlist(lapply(parsed$articles, `[[`, "contents")), rel_vignettes())
  menu = vapply(parsed$navbar$components$cheatsheet$menu, `[[`, "", "href")
  expect_identical(menu, c("cheatsheet.html", "gptr-cheatsheet.pdf"))
  # the Authors page links the three authors to their emails and carries no other text
  expect_identical(names(parsed$authors), c("Wanjun Gu", "Tianlu Zhu", "Gianmarco Bellucci"))
  expect_identical(unname(vapply(parsed$authors, `[[`, "", "href")),
                   c("mailto:wanjun.gu@ucsf.edu", "mailto:tianluz2013@gmail.com",
                     "mailto:Gianmarco.Bellucci@ucsf.edu"))
  expect_true(all(file.exists(file.path(gptr_root(), "pkgdown", "assets", menu))))
})

test_that("pkgdown_extra() and pkgdown_problems() keep the index complete", {
  db = rd_read_dir(toy_man(list(peter = rd_page("peter"),
                                print.gptr_session = rd_page("print.gptr_session"),
                                hidden = rd_page("hidden", keywords = "internal"))))
  expect_identical(pkgdown_extra(db), "print.gptr_session")
  root = gptr_root()
  expect_identical(pkgdown_problems(pkgdown_yaml("print.gptr_session", root), db, root),
                   character())
  expect_match(pkgdown_problems(pkgdown_yaml(root = root), db, root), "out of date")
})
