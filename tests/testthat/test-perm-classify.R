# tests/testthat/test-perm-classify.R -- gptr_risk() and the risk tables (P11)

risk_categories = c("read", "object_write", "file_write", "file_delete", "network", "process",
                    "install", "dynamic", "session", "secret", "interactive", "critical",
                    "control")

test_that("the shipped risk tables have the contract columns and levels (contract 11.15)", {
  fns = risk_read_csv(system.file("extdata", "risk-functions.csv", package = "gptr"))
  expect_identical(names(fns), c("package", "function", "level", "category", "path_arg", "note"))
  expect_type(fns$level, "integer")
  expect_true(all(fns$level %in% 0:4))
  expect_true(all(fns$category %in% risk_categories))
  expect_identical(anyDuplicated(fns[, c("package", "function")]), 0L)
  cmds = risk_read_csv(system.file("extdata", "risk-commands.csv", package = "gptr"))
  expect_identical(names(cmds), c("command", "subcommand", "level", "category", "note"))
  expect_true(all(cmds$level %in% 0:4))
  expect_identical(anyDuplicated(cmds[, c("command", "subcommand")]), 0L)
  raw = readBin(system.file("extdata", "risk-functions.csv", package = "gptr"), "raw", 1e6)
  expect_false(any(raw == as.raw(13L)))
  expect_false(any(raw > as.raw(127L)))
})

test_that("gptr's configuration exports and hooks are level 4 control rows (IC-53)", {
  tab = risk_table("functions")
  control = c("gptr_config", "gptr_permissions", "gptr_trust", "gptr_init", "gptr_env",
              "gptr_register", "gptr_reload", "gptr_on", "gptr_mcp_add", "gptr_mcp_remove",
              "gptr_mcp_serve", "gptr_login", "gptr_logout", "gptr_doc", "gptr_resume",
              "gptr_fork", "gptr_steer", "gptr_cancel", "gptr_rewind")
  for (f in control) {
    row = risk_lookup(f, "gptr", tab)
    expect_identical(row$level, 4L, label = f)
    expect_identical(row$category, "control", label = f)
  }
  expect_identical(risk_lookup("setHook", NA_character_, tab)$category, "control")
  expect_identical(risk_lookup("assignInNamespace", "utils", tab)$level, 4L)
  expect_identical(risk_lookup("q", NA_character_, tab)$category, "critical")
})

test_that("risky packages floor unlisted functions at level 2, delete verbs at 3 (IC-54)", {
  tab = risk_table("functions")
  expect_identical(risk_lookup("tar_anything", "targets", tab)$level, 2L)
  expect_identical(risk_lookup("tar_destroy", "targets", tab)$level, 3L)
  expect_identical(risk_lookup("tar_read", "targets", tab)$level, 0L)
  expect_identical(risk_lookup("create_package", "usethis", tab)$level, 2L)
  expect_identical(risk_lookup("s3_upload", "aws.s3", tab)$level, 2L)
  expect_identical(risk_lookup("s3_list", "paws.storage", tab)$level, 2L)
  expect_identical(risk_lookup("dbWriteTable", "DBI", tab)$level, 2L)
  expect_identical(risk_lookup("dbRemoveTable", "DBI", tab)$level, 3L)
  expect_identical(risk_lookup("req_perform", "httr2", tab)$level, 2L)
  expect_identical(risk_lookup("POST", "httr", tab)$level, 3L)
  expect_identical(risk_lookup("geom_point", "ggplot2", tab)$level, 0L)
  expect_null(risk_lookup("FindClusters", "Seurat", tab))
})

test_that("known read-only rows back the plan-mode allowlist (IC-54)", {
  tab = risk_table("functions")
  for (f in c("summary", "head", "lm", "coef", "nrow", "mean", "print", "str", "table")) {
    row = risk_lookup(f, NA_character_, tab)
    expect_identical(row$level, 0L, label = f)
    expect_identical(row$category, "read", label = f)
  }
  expect_identical(risk_lookup("summary", "base", tab)$package, "base")
  expect_identical(risk_lookup("readRDS", "base", tab)$path_arg, "file")
})

test_that("base-package rows are exact: the `*` operator is no package wildcard (IC-54)", {
  tab = risk_table("functions")
  expect_identical(risk_lookup("*", "base", tab)$category, "read")
  expect_identical(risk_lookup("%*%", NA_character_, tab)$package, "base")
  expect_null(risk_lookup("not_a_base_function", "base", tab))
  expect_null(risk_lookup("%<>%", NA_character_, tab))
  expect_identical(risk_lookup("write.dcf", "base", tab)$category, "file_write")
  expect_identical(risk_lookup("theme_set", "ggplot2", tab)$level, 1L)
  expect_identical(risk_lookup("theme_bw", "ggplot2", tab)$level, 0L)
})

test_that("risk_rule records extend both tables; lowering needs lower = TRUE (10.2 row 33)", {
  rows = data.frame(package = c("mypkg", "base"), `function` = c("wipe", "unlink"),
                    level = c(3L, 1L), category = c("file_delete", "file_delete"),
                    check.names = FALSE)
  off1 = gptr_register(gptr_spec("risk_rule", "p11_test_rows", rows = rows))
  withr::defer(off1())
  tab = risk_table("functions")
  expect_identical(risk_lookup("wipe", "mypkg", tab)$level, 3L)
  expect_identical(risk_lookup("unlink", "base", tab)$level, 3L)
  lower = data.frame(package = "base", `function` = "unlink", level = 1L,
                     category = "file_delete", check.names = FALSE)
  off2 = gptr_register(gptr_spec("risk_rule", "p11_test_lower", rows = lower, lower = TRUE))
  withr::defer(off2())
  expect_identical(risk_lookup("unlink", "base", risk_table("functions"))$level, 1L)
  cmd = data.frame(command = "mytool", level = 1L, category = "process")
  off3 = gptr_register(gptr_spec("risk_rule", "p11_test_cmd", rows = cmd, target = "command"))
  withr::defer(off3())
  cmds = risk_table("commands")
  expect_identical(cmds$level[cmds$command == "mytool"], 1L)
  expect_identical(cmds$subcommand[cmds$command == "mytool"], "*")
  expect_null(risk_lookup("mytool", NA_character_, risk_table("functions")))
})

test_that("a risk_rule row keeps the shipped columns it does not supply", {
  rows = data.frame(package = "base", `function` = "saveRDS", level = 3L, check.names = FALSE)
  off = gptr_register(gptr_spec("risk_rule", "p11_test_raise", rows = rows))
  withr::defer(off())
  row = risk_lookup("saveRDS", "base", risk_table("functions"))
  expect_identical(row$level, 3L)
  expect_identical(row$category, "file_write")
  expect_identical(row$path_arg, "file")
  blank = data.frame(package = c("base", NA), `function` = c("unlink", "wipe"), level = 4L,
                     path_arg = "", note = factor("wipes"), check.names = FALSE)
  off_blank = gptr_register(gptr_spec("risk_rule", "p11_test_blank", rows = blank))
  withr::defer(off_blank())
  tab = risk_table("functions")
  row = risk_lookup("unlink", "base", tab)
  expect_identical(row$level, 4L)
  expect_identical(row$path_arg, "")
  expect_identical(row$note, "wipes")
  expect_false(anyNA(tab$package))
  expect_null(risk_lookup("wipe", "mypkg", tab))
  mixed = data.frame(package = "base", `function` = c("saveRDS", "mywipe"), level = 4L,
                     category = c(NA, "file_delete"), path_arg = c(NA, "x"), check.names = FALSE)
  off_mixed = gptr_register(gptr_spec("risk_rule", "p11_test_mixed", rows = mixed))
  withr::defer(off_mixed())
  tab = risk_table("functions")
  row = risk_lookup("saveRDS", "base", tab)
  expect_identical(row$level, 4L)
  expect_identical(row$category, "file_write")
  expect_identical(row$path_arg, "file")
  row = risk_lookup("mywipe", "base", tab)
  expect_identical(row$category, "file_delete")
  expect_identical(row$path_arg, "x")
  expect_identical(row$note, "")
})

test_that("a command risk_rule row with an NA subcommand covers every subcommand", {
  cmd = data.frame(command = c("git", "mytool"), subcommand = c("push", NA), level = c(4L, 3L),
                   category = "process")
  off = gptr_register(gptr_spec("risk_rule", "p11_test_cmd_na", rows = cmd, target = "command"))
  withr::defer(off())
  cmds = risk_table("commands")
  expect_identical(cmds$level[cmds$command == "git" & cmds$subcommand == "push"], 4L)
  expect_identical(cmds$subcommand[cmds$command == "mytool"], "*")
  expect_identical(cmds$level[cmds$command == "mytool"], 3L)
  expect_false(anyNA(cmds$subcommand))
})

test_that("risk_table() sees a risk_rule registered again under the same name", {
  first = data.frame(package = "mypkg", `function` = "wipe", level = 2L, check.names = FALSE)
  off = gptr_register(gptr_spec("risk_rule", "p11_test_again", rows = first))
  expect_identical(risk_lookup("wipe", "mypkg", risk_table("functions"))$level, 2L)
  off()
  second = data.frame(package = "mypkg", `function` = "wipe", level = 4L, check.names = FALSE)
  off = gptr_register(gptr_spec("risk_rule", "p11_test_again", rows = second))
  withr::defer(off())
  expect_identical(risk_lookup("wipe", "mypkg", risk_table("functions"))$level, 4L)
})
