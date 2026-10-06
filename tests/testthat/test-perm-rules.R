# tests/testthat/test-perm-rules.R -- permission rules and gptr_permissions() (P11)

r_call = function(code, envir = NULL, root = project_root()) {
  list(id = "c1", name = "r", input = list(code = code), nested = FALSE,
       risk = gptr_risk(code, envir = envir, root = root))
}
path_call = function(tool, path, level = 2L) {
  list(id = "c2", name = tool, input = list(path = path), nested = FALSE,
       risk = list(level = level, categories = "file_write", paths = path))
}

test_that("rule_parse() reads report 18's grammar with G5 and G6 specs (3.7)", {
  p = rule_parse("r(fn:write.csv, saveRDS)")
  expect_identical(p, list(tool = "r", kind = "fn", value = c("write.csv", "saveRDS")))
  expect_identical(rule_parse("r(level<=1)")$value, 1L)
  expect_identical(rule_parse("write(results/**)"),
                   list(tool = "write", kind = "glob", value = "results/**"))
  expect_identical(rule_parse("mcp__github__*")$kind, "any")
  expect_identical(rule_parse("r")$kind, "any")
  expect_identical(rule_parse("r(sh:git status*)")$value, "git status*")
  expect_identical(rule_parse("r(sql:select, with)")$value, c("select", "with"))
  expect_identical(rule_parse("r(category:network)")$kind, "category")
  expect_identical(rule_parse("r(secret:GITHUB_PAT)"),
                   list(tool = "r", kind = "secret", value = "GITHUB_PAT"))
  for (bad in list("write(x", "read(fn:x)", "r(level<=9)", "r(secret:not a name)", "r(fn:)",
                   "x(y(z))", 1, c("r", "r"), NA_character_)) {
    cnd = expect_error(rule_parse(bad), class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "rule")
  }
})

test_that("rule path globs are anchored at the project root (gitignore style)", {
  expect_true(grepl(rule_glob_re("results/**"), "results/a.csv", perl = TRUE))
  expect_true(grepl(rule_glob_re("results/**"), "results/sub/b.rds", perl = TRUE))
  expect_false(grepl(rule_glob_re("results/**"), "other/results/a.csv", perl = TRUE))
  expect_true(grepl(rule_glob_re("*.csv"), "deep/dir/a.csv", perl = TRUE))
  expect_false(grepl(rule_glob_re("*.csv"), "a.csv.bak", perl = TRUE))
  expect_true(grepl(rule_glob_re("data/**/raw.txt"), "data/raw.txt", perl = TRUE))
  expect_true(grepl(rule_glob_re("data/**/raw.txt"), "data/a/b/raw.txt", perl = TRUE))
  expect_true(grepl(rule_glob_re("~/notes/?.md"), "~/notes/a.md", perl = TRUE))
  expect_true(grepl(rule_glob_re("//etc/**"), "//etc/hosts", perl = TRUE))
  expect_false(grepl(rule_glob_re("a+b(c).txt"), "aab(c).txt", perl = TRUE))
  # a glob without "/" matches at any depth INSIDE the project only (never ~/ or //...)
  expect_true(grepl(rule_glob_re("notes.md"), "sub/notes.md", perl = TRUE))
  expect_false(grepl(rule_glob_re("notes.md"), "//etc/notes.md", perl = TRUE))
  expect_false(grepl(rule_glob_re("*.csv"), "~/a.csv", perl = TRUE))
})

test_that("rule_match(): allow covers every flagged call, deny and ask any (7.11)", {
  root = local_project()
  m = rule_match(list(allow = "r(fn:write.csv)"), r_call("write.csv(df, 'a.csv')"))
  expect_identical(m$allow, "r(fn:write.csv)")
  m = rule_match(list(allow = "r(fn:write.csv)", deny = "r(fn:unlink)"),
                 r_call("write.csv(df, 'a.csv'); unlink('x')"))
  expect_identical(m$allow, character())
  expect_identical(m$deny, "r(fn:unlink)")
  m = rule_match(list(allow = "write(results/**)"), path_call("write", "results/t.csv"))
  expect_identical(m$allow, "write(results/**)")
  m = rule_match(list(allow = "write(results/**)"), path_call("write", "data/t.csv"))
  expect_identical(m$allow, character())
  m = rule_match(list(allow = "write(results/**)"), path_call("edit", "results/t.csv"))
  expect_identical(m$allow, character())
  m = rule_match(list(allow = "r(sh:git commit*)"), r_call("peter$sh(\"git commit -am wip\")"))
  expect_identical(m$allow, "r(sh:git commit*)")
  m = rule_match(list(deny = "r(sql:drop)"), r_call("peter$sql(\"SELECT 1; DROP TABLE t\")"))
  expect_identical(m$deny, "r(sql:drop)")
  m = rule_match(list(ask = "r(category:network)"),
                 r_call("download.file('https://x.org/a', 'a')"))
  expect_identical(m$ask, "r(category:network)")
  m = rule_match(list(allow = "r(level<=1)"), r_call("fit = lm(mpg ~ wt, mtcars)"))
  expect_identical(m$allow, "r(level<=1)")
  m = rule_match(list(allow = c("mcp__github__*", "broken(")),
                 list(name = "mcp__github__issues", input = list(), risk = NULL))
  expect_identical(m$allow, "mcp__github__*")
})

test_that("r(secret:NAME) is the only allow rule that covers a registered secret read", {
  root = local_project()
  call = r_call("Sys.getenv('OPENAI_API_KEY')")
  call$risk$secrets = "OPENAI_API_KEY"
  expect_identical(rule_match(list(allow = "r(secret:OPENAI_API_KEY)"), call)$allow,
                   "r(secret:OPENAI_API_KEY)")
  expect_identical(rule_match(list(allow = "r(secret:OTHER)"), call)$allow, character())
})

test_that("rule_suggest() covers exactly the flagged calls, never level 4 or control (7.11)", {
  root = local_project()
  code = "write.csv(df, 'results/summary.csv')\nsaveRDS(df, 'results/df.rds')"
  expect_identical(rule_suggest(r_call(code)), "r(fn:write.csv,saveRDS)")
  expect_identical(rule_suggest(r_call("pbmc = FindNeighbors(pbmc); pbmc = FindClusters(pbmc)")),
                   "r(fn:FindNeighbors,FindClusters)")
  expect_identical(rule_suggest(path_call("write", "results/t.csv")), "write(results/**)")
  expect_identical(rule_suggest(path_call("write", "notes.md")), "write(notes.md)")
  expect_null(rule_suggest(path_call("write", ".gptr/settings.json")))
  expect_null(rule_suggest(r_call("rm(list = ls())")))
  expect_null(rule_suggest(r_call("gptr_permissions(allow = 'r')")))
  expect_identical(rule_suggest(r_call("fit = lm(mpg ~ wt, mtcars)")), "r(level<=1)")
  expect_identical(rule_suggest(r_call("peter$sh(\"git commit -am wip\")")), "r(sh:git commit*)")
  expect_identical(rule_suggest(r_call("peter$sql(\"UPDATE t SET a = 1\")")), "r(sql:update)")
  expect_null(rule_suggest(list(name = "ask", input = list(), risk = NULL)))
  expect_identical(rule_suggest(list(name = "mcp__github__issues", input = list(), risk = NULL)),
                   "mcp__github__issues")
  sug = rule_suggest(r_call("x = FindNeighbors(x); write.csv(x, 'a.csv')"))
  expect_identical(sug, "r(fn:FindNeighbors,write.csv)")
  expect_identical(rule_match(list(allow = sug), r_call("write.csv(y, 'b.csv')"))$allow, sug)
  both = r_call("write.csv(y, 'b.csv'); unlink('z')")
  expect_identical(rule_match(list(allow = sug), both)$allow, character())
})

test_that("rules read every code-argument row; dynamic or mixed code gets no rule (D-159)", {
  root = local_project()
  expect_true(grepl(rule_glob_re("results/**"), "results/a\nb", perl = TRUE))
  m = rule_match(list(deny = "r(sql:drop)"), r_call("DBI::dbExecute(con, 'DROP TABLE t')"))
  expect_identical(m$deny, "r(sql:drop)")
  pipe_call = r_call("pipe('git commit -m x')")
  expect_identical(rule_suggest(pipe_call), "r(sh:git commit*)")
  expect_identical(rule_match(list(allow = "r(sh:git commit*)"), pipe_call)$allow,
                   "r(sh:git commit*)")
  for (code in c("peter$sh(\"echo $(date)\")", "peter$sh(\"git commit -m $(date)\")",
                 "system(cmd)", "x[[i]](1)",
                 "write.csv(x, 'a.csv'); peter$sql(\"UPDATE t SET a = 1\")")) {
    expect_null(rule_suggest(r_call(code)), label = code)
  }
  for (path in c("~/data/x.csv", "/x.txt")) {
    sug = rule_suggest(path_call("read", path, 1L))
    expect_identical(rule_match(list(allow = sug), path_call("read", path))$allow, sug)
    expect_identical(rule_match(list(allow = sug), path_call("read", "/z.R"))$allow, character())
  }
})

test_that("gptr_permissions() adds, lists and removes session rules (6.2)", {
  root = local_project()
  local_permission_rules()
  x = gptr_permissions(allow = "r(level<=1)")
  expect_s3_class(x, c("gptr_permissions", "gptr_listing", "data.frame"))
  expect_identical(names(x), c("rule", "list", "scope", "source"))
  expect_true(any(x$rule == "r(level<=1)" & x$list == "allow" & x$scope == "session"))
  expect_visible(gptr_permissions())
  expect_invisible(gptr_permissions(deny = "r(fn:install.packages)"))
  expect_identical(perm_rules_effective()$deny, "r(fn:install.packages)")
  gptr_permissions(remove = c("r(level<=1)", "r(fn:install.packages)"))
  expect_false(any(gptr_permissions()$rule %in% c("r(level<=1)", "r(fn:install.packages)")))
})

test_that("project rules go to the user-level project file, never the project tree (IC-52)", {
  root = local_project()
  gptr_permissions(deny = "r(fn:install.packages)", scope = "project")
  pf = perm_project_file(root)
  expect_true(file.exists(pf))
  expect_match(pf, "projects/[0-9a-f]{16}[.]json$")
  expect_false(startsWith(path_norm(pf), path_norm(root)))
  saved = json_decode(read_utf8(pf)$text)
  expect_identical(unlist(saved$permissions$deny), "r(fn:install.packages)")
  expect_identical(saved$root, root)
  x = gptr_permissions()
  expect_true(any(x$rule == "r(fn:install.packages)" & x$scope == "project" &
                    x$source == "user-level project file"))
  gptr_permissions(remove = "r(fn:install.packages)", scope = "project")
  expect_identical(unlist(json_decode(read_utf8(pf)$text)$permissions$deny), NULL)
  expect_false(file.exists(file.path(root, ".gptr", "settings.local.json")))
})

test_that("user rules go to the user settings file and keep its other keys", {
  root = local_project()
  uf = perm_user_file()
  dir.create(dirname(uf), recursive = TRUE, showWarnings = FALSE)
  write_atomic(uf, "{\"model\": \"sonnet\", \"permissions\": {\"ask\": [\"r(category:network)\"]}}")
  withr::defer(unlink(uf))
  gptr_permissions(allow = "write(results/**)", scope = "user")
  saved = json_decode(read_utf8(uf)$text)
  expect_identical(saved$model, "sonnet")
  expect_identical(unlist(saved$permissions$allow), "write(results/**)")
  expect_identical(unlist(saved$permissions$ask), "r(category:network)")
  expect_true(any(gptr_permissions()$scope == "user"))
})

test_that("an invalid rule signals invalid_argument and writes nothing (6.2)", {
  root = local_project()
  local_permission_rules()
  cnd = expect_error(gptr_permissions(allow = c("r(level<=1)", "bad(")),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "allow")
  expect_false(grepl("bad(", conditionMessage(cnd), fixed = TRUE))
  expect_false("r(level<=1)" %in% perm_store()$allow)
  expect_error(gptr_permissions(allow = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_permissions(allow = "r", scope = "global"),
               class = "gptr_error_invalid_argument")
})

test_that("model code needs a one-shot approval to change rules during a run (IC-53)", {
  root = local_project()
  local_permission_rules()
  run = fake_run(session = "s0000000001")
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(gptr_permissions(allow = "r(level<=3)"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_permissions")
  expect_identical(cnd$session, "s0000000001")
  expect_false("r(level<=3)" %in% perm_store()$allow)
  run$signal$control = c("gptr_config", "gptr_permissions")
  gptr_permissions(allow = "r(level<=2)")
  expect_true("r(level<=2)" %in% perm_store()$allow)
  expect_identical(run$signal$control, "gptr_config")
  expect_error(gptr_permissions(allow = "r(level<=3)"), class = "gptr_error_permission")
  expect_s3_class(gptr_permissions(), "gptr_permissions")
})

test_that("a cloned settings.local.json only tightens, and only when trusted (IC-52)", {
  root = local_project(files = list(
    ".gptr/settings.local.json" = paste0("{\"permissions\": {\"allow\": [\"r(level<=3)\"], ",
                                         "\"deny\": [\"r(fn:system)\"]}}"),
    ".gptr/settings.json" = paste0("{\"permissions\": {\"allow\": [\"write(**)\"], ",
                                   "\"ask\": [\"r(category:network)\"]}}")))
  local_gptr_options(quiet = FALSE)
  expect_message(perm_rules_table(), "Ignoring allow rules", class = "gptr_message_notice")
  tab = perm_rules_table()
  expect_false(any(tab$rule %in% c("r(level<=3)", "r(fn:system)", "write(**)")))
  expect_true("r(category:network)" %in% tab$rule)
  local_mocked_bindings(perm_trusted = function(root = project_root()) TRUE)
  tab = perm_rules_table()
  expect_false("r(level<=3)" %in% tab$rule)
  expect_true(all(c("r(fn:system)", "write(**)") %in% tab$rule))
})

test_that("the allow-rule notice keeps P08's notice of ignored settings.local.json keys (IC-52)", {
  root = local_project(files = list(".gptr/settings.local.json" = paste0(
    "{\"permissions\": {\"allow\": [\"r(level<=3)\"]}, \"transcript\": {\"target\": \"a.R\"}}")),
    trust = TRUE)
  local_gptr_options(quiet = FALSE)
  expect_message(perm_rules_table(), "Ignoring allow rules", class = "gptr_message_notice")
  expect_message(settings_layered("permissions"), "transcript", class = "gptr_message_notice")
})
