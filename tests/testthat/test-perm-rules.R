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
