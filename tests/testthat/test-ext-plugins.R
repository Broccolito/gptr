# Tests of R/ext-plugins.R (plan P17). Task 1: names, frontmatter, resource groups, places.

write_file = function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  path
}

test_that("res_norm lower-cases and maps _ and . to - (IC-42)", {
  expect_identical(res_norm(c("single_cell", "High.Performance_R", "x")),
                   c("single-cell", "high-performance-r", "x"))
})

test_that("res_match prefers exact names and flags ambiguous normalised ones", {
  expect_identical(res_match("my-skill", c("my-skill", "my_skill"), "skill"), "my-skill")
  expect_identical(res_match("single_cell", c("single-cell", "other"), "skill"), "single-cell")
  expect_identical(res_match("none", c("a", "b"), "skill"), character())
  cnd = expect_error(res_match("my-plug", c("my_plug", "my.plug"), "plugin"),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$candidates, c("my_plug", "my.plug"))
})

test_that("frontmatter_parse follows Pi's rules: BOM, CRLF, trimmed body", {
  txt = paste0(intToUtf8(0xFEFFL), "---\r\nname: crlf\r\ndescription: BOM and CRLF\r\n",
               "---\r\n\r\nbody line\r\n")
  fm = frontmatter_parse(txt)
  expect_true(fm$has_frontmatter)
  expect_identical(fm$meta$name, "crlf")
  expect_identical(fm$meta$description, "BOM and CRLF")
  expect_identical(fm$body, "body line")
  none = frontmatter_parse("# just markdown\n")
  expect_false(none$has_frontmatter)
  expect_identical(none$meta, list())
  expect_identical(none$body, "# just markdown")
  expect_false(frontmatter_parse("---\nname: x\nno end")$has_frontmatter)
})

test_that("folded scalars parse and unquoted colons are repaired (report 05 section 5.2)", {
  folded = paste("---", "name: pdf-tools", "description: >", "  Extract text: tables and forms",
                 "  from PDF files.", "metadata:", "  version: \"1.0\"", "---", "body", sep = "\n")
  expect_identical(frontmatter_parse(folded)$meta$description,
                   "Extract text: tables and forms from PDF files.\n")
  colon = frontmatter_parse("---\nname: colon\ndescription: Use this skill when: asked\n---\nx")
  expect_true(colon$repaired)
  expect_identical(colon$meta$description, "Use this skill when: asked")
  expect_match(frontmatter_parse("---\nname: [unclosed\n---\nx")$error, "invalid YAML frontmatter")
})

test_that("string keys keep their source text against YAML 1.1 coercion (IC-71)", {
  fm = frontmatter_parse(paste("---", "name: on", "version: 1.0", "description: yes",
                               "argument-hint: 12", "model: null",
                               "disable-model-invocation: true", "---", "", sep = "\n"))
  expect_identical(fm$meta$name, "on")
  expect_identical(fm$meta$version, "1.0")
  expect_identical(fm$meta$description, "yes")
  expect_identical(fm$meta[["argument-hint"]], "12")
  expect_null(fm$meta$model)
  expect_true(isTRUE(fm$meta[["disable-model-invocation"]]))
})

test_that("frontmatter never evaluates !expr tags", {
  withr::local_envvar(GPTR_PWNED = "")
  fm = frontmatter_parse("---\nname: x\ndescription: !expr Sys.setenv(GPTR_PWNED = 'yes')\n---\n")
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_type(fm$meta$description, "character")
})

test_that("fm_chr_list accepts comma strings, space strings and arrays", {
  expect_identical(fm_chr_list("Read, Grep"), c("Read", "Grep"))
  expect_identical(fm_chr_list("a b"), c("a", "b"))
  expect_identical(fm_chr_list(list("x", "y")), c("x", "y"))
  expect_identical(fm_chr_list("Bash(git diff *), Read", ","), c("Bash(git diff *)", "Read"))
  expect_null(fm_chr_list(NULL))
  expect_null(fm_chr_list(""))
})

test_that("plugin_api_ok implements the requirement grammar (G1 section 3.5)", {
  expect_true(plugin_api_ok(">= 1.0, < 2", have = "1.0"))
  expect_true(plugin_api_ok("1.0", have = "1.3"))
  expect_false(plugin_api_ok("1.2", have = "1.0"))
  expect_false(plugin_api_ok("1", have = "2.0"))
  expect_false(plugin_api_ok(">= 2.0", have = "1.0"))
  expect_true(plugin_api_ok(NULL))
  expect_true(plugin_api_ok(">= 1.0, < 2"))
  expect_false(plugin_api_ok("about one", have = "1.0"))
})

test_that("rdepends_missing reads DESCRIPTION versions and loads nothing", {
  expect_identical(rdepends_missing(c("stats", "utils (>= 1.0)")), character())
  expect_identical(rdepends_missing("stats (>= 999.0)"), "stats (>= 999.0)")
  expect_identical(rdepends_missing("notapkg.p17"), "notapkg.p17")
})

test_that("res_register rewrites a group only when its signature changes", {
  withr::defer(res_unregister("test:group"))
  specs = list(gptr_command("p17-cmd-a", function(args, ctx) "a"))
  expect_true(res_register("test:group", specs, source = "user", rank = 3L, sig = "s1"))
  expect_false(res_register("test:group", specs, source = "user", rank = 3L, sig = "s1"))
  expect_false(is.null(registry_get("command", "p17-cmd-a")))
  expect_true(res_register("test:group", list(), source = "user", rank = 3L, sig = "s2"))
  expect_null(registry_get("command", "p17-cmd-a"))
})

test_that("res_cached parses a file again only after it changes", {
  f = withr::local_tempfile(fileext = ".md")
  writeLines("one", f)
  count = new.env()
  count$n = 0L
  parser = function(p) {
    count$n = count$n + 1L
    readLines(p, encoding = "UTF-8")
  }
  expect_identical(res_cached(f, parser, "t"), "one")
  expect_identical(res_cached(f, parser, "t"), "one")
  expect_identical(count$n, 1L)
  writeLines(c("one", "two"), f)
  expect_identical(res_cached(f, parser, "t"), c("one", "two"))
  expect_identical(count$n, 2L)
})

test_that("res_project_dirs walks from the working directory up to the project root", {
  p = local_project()
  dir.create(file.path(p, ".agents", "skills"), recursive = TRUE)
  dir.create(file.path(p, "sub", ".claude", "skills"), recursive = TRUE)
  withr::local_dir(file.path(p, "sub"))
  expect_identical(res_project_dirs(c(".agents/skills", ".claude/skills")),
                   c(path_norm(file.path(p, "sub", ".claude", "skills")),
                     path_norm(file.path(p, ".agents", "skills"))))
  expect_true(res_inside(file.path(p, "sub", "x.R")))
  expect_false(res_inside(tempdir()))
})

test_that("plugin_type_paths honours Claude manifest component keys and refuses escapes", {
  b = withr::local_tempdir()
  write_file(file.path(b, "extra-skills", "x", "SKILL.md"), "---\nname: x\ndescription: X.\n---\n")
  write_file(file.path(b, "cmds", "st.md"), "Status of $1")
  write_file(file.path(b, "skills", "y", "SKILL.md"), "---\nname: y\ndescription: Y.\n---\n")
  manifest = list(name = "mapped", skills = list("./extra-skills/"),
                  commands = list(status = list(source = "./cmds/st.md")),
                  agents = list("../outside"))
  p = list(kind = "claude-plugin", name = "mapped", path = path_norm(b), manifest = manifest)
  expect_identical(plugin_type_paths(p, "skills"),
                   file.path(p$path, c("skills", "extra-skills")))
  cm = plugin_type_paths(p, "commands")
  expect_identical(names(cm), "status")
  expect_identical(unname(cm), file.path(p$path, "cmds", "st.md"))
  expect_identical(plugin_type_paths(p, "agents"), character())
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("a path outside the plugin was ignored: ../outside", msgs, fixed = TRUE)))
  expect_null(plugin_rel(p$path, "..\\outside"))
  g = list(kind = "directory", name = "g", path = path_norm(b), manifest = list())
  expect_identical(plugin_type_paths(g, "skills"), file.path(p$path, "skills"))
  expect_identical(plugin_type_paths(g, "prompts"), character())
})

test_that("res_prune removes stale groups and copes with none", {
  st = res_state()
  old = st$groups
  withr::defer({
    st$groups = old
  })
  st$groups = list()
  expect_identical(res_prune("skills:", character()), character())
  res_register("test:a", list(), source = "user", rank = 3L, sig = "a")
  res_register("test:b", list(), source = "user", rank = 3L, sig = "b")
  expect_identical(res_prune("test:", "test:a"), "test:b")
  expect_identical(names(st$groups), "test:a")
})

# Task 1 adaptations (D-072): behaviour the plan-literal code lacked.

test_that("plugin_type_paths reads a gptr manifest's array of paths (D-072)", {
  b = withr::local_tempdir()
  dir.create(file.path(b, "extra-skills"))
  dir.create(file.path(b, "skills"))
  dir.create(file.path(b, "tpl"))
  m = list(skills = list("extra-skills", "../outside-array"), prompts = list("./tpl/"))
  g = list(kind = "directory", name = "g", path = path_norm(b), manifest = m)
  expect_identical(plugin_type_paths(g, "skills"), file.path(g$path, "extra-skills"))
  expect_identical(plugin_type_paths(g, "prompts"), file.path(g$path, "tpl"))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("a path outside the plugin was ignored: ../outside-array", msgs,
                        fixed = TRUE)))
  g$manifest = list(skills = "extra-skills")
  expect_identical(plugin_type_paths(g, "skills"), file.path(g$path, "extra-skills"))
})

test_that("rdepends_missing reports an unparseable version as missing (D-072)", {
  expect_identical(rdepends_missing("stats (>= 1.)"), "stats (>= 1.)")
  expect_identical(rdepends_missing(c("stats", "utils (>= 1..2)", "stats (>= 1.0)")),
                   "utils (>= 1..2)")
})

test_that("res_match ignores NA candidates and repeated names (D-072)", {
  expect_identical(res_match("a", c(NA, "a", "a"), "skill"), "a")
  expect_identical(res_match("a_b", c(NA, "a-b", "a-b"), "skill"), "a-b")
  expect_identical(res_match("zz", NA_character_, "skill"), character())
})

test_that("res_register skips the NULL of an invalid spec without a diagnostic (D-072)", {
  withr::defer(res_unregister("test:null-spec"))
  specs = list(NULL, gptr_command("p17-cmd-null", function(args, ctx) "n"))
  expect_true(res_register("test:null-spec", specs, source = "plugin:p17-null-spec", rank = 5L,
                           sig = "n1"))
  expect_length(res_state()$groups[["test:null-spec"]]$ids, 1L)
  expect_false(is.null(registry_get("command", "p17-cmd-null")))
  diag = gptr_registry(diagnostics = TRUE)
  expect_false(any(diag$source == "plugin:p17-null-spec"))
})
