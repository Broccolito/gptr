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

# Task 2 review round 1 (D-074): R yaml's NA spellings stay text in the string keys.

test_that("frontmatter string keys keep R yaml's NA spellings as text (IC-71, D-074)", {
  fm = frontmatter_parse(c("---", "name: .na.character", "description: .na", "version: .na.real",
                           "model: .na.integer", "license: .na.character", "---", "Body"))
  expect_null(fm$error)
  expect_identical(fm$meta$name, ".na.character")
  expect_identical(fm$meta$description, ".na")
  expect_identical(fm$meta$version, ".na.real")
  expect_identical(fm$meta$model, ".na.integer")
  expect_identical(fm$meta$license, NA_character_)
})

# Task 2 review round 3 (D-074): YAML aliases never expand without bound.

fm_alias_chain = function(levels) {
  out = "x0: &a0 [a, b, c, d, e, f, g, h, i]"
  for (i in seq_len(levels)) {
    refs = paste(rep(sprintf("*a%d", i - 1L), 9L), collapse = ", ")
    out = c(out, sprintf("x%d: &a%d [%s]", i, i, refs))
  }
  out
}

test_that("frontmatter whose YAML aliases expand too far is an error string (D-074)", {
  small = frontmatter_parse(c("---", "name: x", "description: d", "base: &b [read, r]",
                              "allowed-tools: *b", "also: *b", "---", "x"))
  expect_null(small$error)
  expect_identical(fm_chr_list(small$meta[["allowed-tools"]]), c("read", "r"))
  bomb = frontmatter_parse(c("---", "name: bomb", "description: d", fm_alias_chain(7L),
                             "metadata: *a7", "---", "x"))
  expect_null(bomb$meta)
  expect_match(bomb$error %||% "", "too many aliases", fixed = TRUE)
  # Round 5: at most 4 references to anchors reach yaml, so a fixture within that cap shows
  # fm_size_ok() still refusing what they expand to.
  many = paste0("x0: &a0 [", paste(rep("a", 8000L), collapse = ","), "]")
  wide = frontmatter_parse(c("---", "name: wide", "description: d", many,
                             "x1: [*a0, *a0, *a0, *a0]", "---", "x"))
  expect_null(wide$meta)
  expect_match(wide$error %||% "", "too large once its aliases are expanded", fixed = TRUE)
  long = strrep("y", 300000L)
  expect_true(fm_size_ok(rep(list(long), 3L), 1e4, 1e6))
  expect_false(fm_size_ok(rep(list(long), 4L), 1e4, 1e6))
})

test_that("fm_chr_list takes only flat values and never flattens nested lists (D-074)", {
  expect_identical(fm_chr_list(list("read", 1L, NULL)), c("read", "1"))
  expect_identical(fm_chr_list(c("a", "b")), c("a", "b"))
  expect_null(fm_chr_list(list(list("a", "b"), "c")))
  expect_null(fm_chr_list(list(c("a", "b"))))
  nested = letters[1:9]
  for (i in 1:6) nested = rep(list(nested), 9L)
  expect_null(fm_chr_list(nested))
})

# Task 2 review round 4 (D-074 item 9): text that would make yaml slow never reaches yaml.

test_that("frontmatter YAML that would make yaml slow is refused before yaml runs (D-074)", {
  fm = function(...) c("---", "name: x", "description: d", ..., "---", "Body")
  ok = frontmatter_parse(fm(paste0("note: ", strrep("z", 15000L)), "tools: [read, r]",
                            "metadata: {a: [1, [2, [3]]], b: {c: d}}", "base: &b {k: 1}",
                            "merged: {<<: *b, j: 2}", "list:", "  - - a"))
  expect_null(ok$error)
  expect_identical(ok$meta$merged, list(k = 1L, j = 2L))
  expect_identical(unlist(ok$meta$list), "a")
  local_mocked_bindings(fm_load = function(...) stop("yaml must not run"))
  # Round 6: the limit is 16,384 bytes, so a 20 KB text is refused too.
  big = frontmatter_parse(fm(paste0("note: ", strrep("z", 20000L))))
  expect_null(big$meta)
  expect_identical(big$error, "invalid YAML frontmatter: too large (more than 16384 bytes)")
  deep = list(paste0("x: ", strrep("[", 1001L), strrep("]", 1001L)),
              paste0("x: ", strrep("{a: ", 1001L), "b", strrep("}", 1001L)),
              paste0("x: ", strrep("[\"]\", ", 1001L), "z", strrep("]", 1001L)),
              c("x:", paste0("  ", strrep("- ", 65L), "a")),
              c("x:", paste0("  ", strrep("? ", 65L), "a")))
  for (d in deep) {
    res = frontmatter_parse(fm(d))
    expect_null(res$meta)
    expect_match(res$error %||% "", "invalid YAML frontmatter: too deeply nested", fixed = TRUE)
  }
  merges = frontmatter_parse(fm("base: &b {k: 1}", "m: {<<: [*b, *b, *b, *b, *b]}"))
  expect_null(merges$meta)
  expect_match(merges$error %||% "", "invalid YAML frontmatter: too many aliases", fixed = TRUE)
})

# Task 2 review round 5 (D-074 item 9): at most 4 references to anchors reach yaml, however the
# key or merge is spelt.

test_that("frontmatter with more than 4 references to its anchors never reaches yaml (D-074)", {
  fm = function(...) c("---", "name: x", "description: d", ..., "---", "Body")
  four = c("a0: &a0 [a, b]", "a1: &a1 [*a0, *a0, *a0, *a0]")
  ok = frontmatter_parse(fm(four))
  expect_null(ok$error)
  expect_identical(ok$meta$a1, rep(list(c("a", "b")), 4L))
  # Round 6: merge keys and references count together (at most 4 in all), so 2 of each here.
  merged = frontmatter_parse(fm("note: Use *args, *kwargs and **bold** text *freely*.",
                                "base: &base {k: 1}", "m: {<<: *base, j: 2}",
                                "mm:", "  ? <<", "  : *base"))
  expect_null(merged$error)
  expect_identical(merged$meta$m, list(k = 1L, j = 2L))
  expect_identical(merged$meta$mm, list(k = 1L))
  expect_identical(merged$meta$note, "Use *args, *kwargs and **bold** text *freely*.")
  local_mocked_bindings(fm_load = function(...) simpleError("yaml ran"))
  refused = "invalid YAML frontmatter: too many aliases (more than 4 references to anchors)"
  b = "base: &b {k: 1}"
  five = "[*b, *b, *b, *b, *b]"
  bad = list(c(four, "m:", "  ? *a1", "  : 1"), c(four, "m:", "  *a1 : 1"),
             c(four, "m: {*a1 : 1}"), c(four, "m: [*a1]"),
             c(fm_alias_chain(7L), "m:", "  ? *a7", "  : 1"),
             c(b, paste0("m: {<<: ", five, "}")), c(b, "m:", "  ? <<", paste0("  : ", five)),
             c(b, paste0("m: {!!merge x: ", five, "}")),
             c(b, paste0("m: {!<tag:yaml.org,2002:%6Derge> x: ", five, "}")),
             c(b, "m: {<<: [*b,*b,*b,*b,*b]}"),
             c(b, paste0("m: [*b, *b, *b, *b,", intToUtf8(0x2028L), "*b]")))
  for (d in bad) {
    res = frontmatter_parse(fm(d))
    expect_null(res$meta)
    expect_identical(res$error, refused)
  }
  latin = rawToChar(as.raw(c(0x61, 0x3a, 0x20, 0x26, 0x62, 0x20, 0xe9, 0x0a, 0x63, 0x3a, 0x20,
                             0x2a, 0x62)))
  expect_silent(expect_null(fm_text_problem(latin)))
})

# Task 2 review round 6 (D-074 item 9): yaml merges a map under a `<<` key, under any key tagged
# merge (`!!merge`, `!merge`, `!<merge>`, ...) and under an alias of an anchored merge key, each
# merge costing about the square of the merged map's size. At most 4 merge keys, tags and
# references to anchors in all reach yaml.

test_that("frontmatter with more than 4 merge keys, tags and aliases never reaches yaml (D-074)", {
  fm = function(...) c("---", "name: x", "description: d", ..., "---", "Body")
  ok = frontmatter_parse(fm("note: Wow! Use it! Really!! (yes!)", "a: !!str 1.0",
                            "m: {<<: {k: 1}, j: 2}", "t: {!!merge x: {k: 2}}",
                            "base: &b {k: 3}", "u: [*b]"))
  expect_null(ok$error)
  expect_identical(ok$meta$note, "Wow! Use it! Really!! (yes!)")
  expect_identical(ok$meta$a, "1.0")
  expect_identical(ok$meta$m, list(k = 1L, j = 2L))
  expect_identical(ok$meta$t, list(k = 2L))
  expect_identical(ok$meta$u, list(list(k = 3L)))
  chain = frontmatter_parse(fm("chain:", "  <<:", "    <<: {k: 1}", "    j: 2", "  i: 3"))
  expect_null(chain$error)
  expect_identical(chain$meta$chain, list(k = 1L, j = 2L, i = 3L))
  local_mocked_bindings(fm_load = function(...) simpleError("yaml ran"))
  refused = "invalid YAML frontmatter: too many merge keys, tags and aliases (more than 4 in all)"
  nest = function(open, n) paste0("m: ", strrep(open, n), "{a: 1}", strrep("}", n))
  block = c("m:", vapply(1:4, function(i) paste0(strrep("  ", i), "<<:"), ""),
            paste0(strrep("  ", 5L), "<<: {a: 1}"))
  breaks = intToUtf8(c(0x2028L, 0x85L, 0x2029L, 0x2028L, 0x2028L), multiple = TRUE)
  tops = paste0(breaks, "!!merge ", c("v", "w", "x", "z", "u"), ": {b: 1}", collapse = "")
  bad = list(nest("{<<: ", 5L), block, nest("{!!merge x: ", 5L), nest("{!merge x: ", 5L),
             nest("{!<merge> x: ", 5L), nest("{!<tag:yaml.org,2002:merge> x: ", 5L),
             nest("{! <<: ", 3L), nest("{?!!merge x: ", 5L), paste0("a: 1", tops),
             c("k: &m <<", "m: {*m : {*m : {*m : {*m : {a: 1}}}}}"),
             c("base: &b {k: 1}", "m: {<<: *b, !!merge x: {j: 1}}",
               "o: {<<: {i: 1}, !!merge x: {h: 1}}"))
  for (d in bad) {
    res = frontmatter_parse(fm(d))
    expect_null(res$meta)
    expect_identical(res$error, refused)
  }
})

# Task 9: plugin resolution.

test_that("plugin_resolve finds a directory plugin by path and a project plugin by name", {
  d = withr::local_tempdir()
  write_file(file.path(d, "plugin.json"),
             '{"name": "dirplug", "version": "0.2.0", "gptr": {"api": ">= 1.0, < 2"}}')
  p = plugin_resolve(d)
  expect_identical(p$kind, "directory")
  expect_identical(p$name, "dirplug")
  expect_identical(p$path, path_norm(d))
  expect_identical(p$version, "0.2.0")
  expect_identical(p$api, ">= 1.0, < 2")
  files = list()
  files[[".gptr/plugins/clinical-trials/skills/ct/SKILL.md"]] =
    "---\nname: ct\ndescription: Trials.\n---\nx"
  local_project(trust = TRUE, files = files)
  q = plugin_resolve("clinical_trials")
  expect_identical(q$name, "clinical-trials")
  expect_identical(q$kind, "directory")
})

test_that("plugin_resolve finds Claude bundles by path and installed Claude plugins by name", {
  b = withr::local_tempdir()
  write_file(file.path(b, ".claude-plugin", "plugin.json"), '{"name": "deploy-tools"}')
  expect_identical(plugin_resolve(b)$kind, "claude-plugin")
  inst = file.path(user_home(), ".claude", "plugins", "installed_plugins.json")
  entry = list(scope = "user", installPath = b, lastUpdated = "2026-09-01T00:00:00.000Z")
  installed = list(version = 2L, plugins = list("deploy-tools@market" = list(entry)))
  write_file(inst, json_encode(installed))
  withr::defer(unlink(inst))
  r = plugin_resolve("deploy_tools")
  expect_identical(r$kind, "claude-plugin")
  expect_identical(r$path, path_norm(b))
})

test_that("plugin_resolve rejects unknown names and ambiguous normalised names", {
  expect_error(plugin_resolve("no-such-plugin-p17"), class = "gptr_error_invalid_argument")
  expect_error(plugin_resolve("./no/such/dir"), class = "gptr_error_invalid_argument")
  files = list()
  files[[".gptr/plugins/my_plug/skills/a/SKILL.md"]] = "---\nname: a\ndescription: A.\n---\nx"
  files[[".gptr/plugins/my.plug/skills/b/SKILL.md"]] = "---\nname: b\ndescription: B.\n---\nx"
  local_project(trust = TRUE, files = files)
  expect_error(plugin_resolve("my-plug"), class = "gptr_error_invalid_identifier")
})

test_that("plugin_from_package reads DESCRIPTION fields without loading the package", {
  expect_null(plugin_from_package("stats"))
  expect_null(plugin_from_package("no.such.pkg.p17"))
})

# Task 9 adaptations (D-088): behaviour the plan-literal code lacked.

test_that("a plugin manifest that is not a JSON object is a diagnostic, never an error (D-088)", {
  bodies = c(string = '"hello"', number = "42", array = "[1, 2]", null = "null", broken = "{")
  for (k in names(bodies)) {
    d = file.path(withr::local_tempdir(), paste0("p17-man-", k))
    write_file(file.path(d, "plugin.json"), bodies[[k]])
    p = plugin_from_dir(d)
    expect_identical(p$kind, "directory")
    expect_identical(p$name, paste0("p17-man-", k))
    expect_identical(p$manifest, list())
    msgs = gptr_registry(diagnostics = TRUE)$message
    expect_true(any(grepl(paste0("p17-man-", k, "/plugin.json: "), msgs, fixed = TRUE)))
  }
  cb = file.path(withr::local_tempdir(), "p17-man-claude")
  write_file(file.path(cb, ".claude-plugin", "plugin.json"), "true")
  expect_identical(plugin_resolve(cb)$kind, "claude-plugin")
  expect_null(plugin_manifest_read(file.path(cb, ".claude-plugin", "plugin.json")))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("plugin.json: the manifest is not a JSON object", msgs, fixed = TRUE)))
})

test_that("installed Claude plugins use the newest existing path and skip bad entries (D-088)", {
  old = withr::local_tempdir()
  mid = withr::local_tempdir()
  write_file(file.path(mid, ".claude-plugin", "plugin.json"), '{"name": "p17-ship"}')
  gone = file.path(withr::local_tempdir(), "removed")
  inst = file.path(user_home(), ".claude", "plugins", "installed_plugins.json")
  withr::defer(unlink(inst))
  ship = list(
    list(scope = "user", installPath = old, lastUpdated = "2026-01-01T00:00:00.000Z"),
    list(scope = "user", installPath = gone, lastUpdated = "2026-09-01T00:00:00.000Z"),
    list(scope = "user", installPath = mid, lastUpdated = "2026-05-01T00:00:00.000Z"))
  plugins = list("p17-ship@market" = ship,
                 "p17-text@market" = "not a list of entries",
                 "p17-object@market" = list(installPath = old, lastUpdated = "2026-01-01"),
                 "p17-odd@market" = list("x", list(installPath = old, lastUpdated = list(1, 2))))
  write_file(inst, json_encode(list(version = 2L, plugins = plugins)))
  cl = plugin_claude_installed()
  expect_identical(sort(names(cl)), c("p17-odd", "p17-ship"))
  expect_identical(unname(cl["p17-ship"]), mid)
  expect_identical(unname(cl["p17-odd"]), old)
  r = plugin_resolve("p17_ship")
  expect_identical(r$kind, "claude-plugin")
  expect_identical(r$path, path_norm(mid))
  expect_error(plugin_resolve("p17-object"), class = "gptr_error_invalid_argument")
  write_file(inst, '"not an object"')
  expect_identical(plugin_claude_installed(), character())
  expect_error(plugin_resolve("p17-ship"), class = "gptr_error_invalid_argument")
  write_file(inst, '{"version": 2, "plugins": ["a", "b"]}')
  expect_identical(plugin_claude_installed(), character())
})

test_that("a ~ path is expanded with user_home(), never R's own expansion (IC-63, D-088)", {
  alt = withr::local_tempdir()
  write_file(file.path(alt, "p17-home-plugin", "plugin.json"), '{"name": "p17-home"}')
  local_mocked_bindings(user_home = function() alt)
  p = plugin_resolve("~/p17-home-plugin")
  expect_identical(p$name, "p17-home")
  expect_identical(p$path, path_norm(file.path(alt, "p17-home-plugin")))
  expect_error(plugin_resolve("~/p17-no-such-plugin"), class = "gptr_error_invalid_argument")
})

test_that("a package plugin is read from its installed DESCRIPTION without loading it", {
  lib = withr::local_tempdir()
  write_file(file.path(lib, "p17fakeplug", "DESCRIPTION"),
             c("Package: p17fakeplug", "Version: 0.3.1", "Config/gptr/plugin: true",
               "Config/gptr/api: >= 1.0, < 2"))
  write_file(file.path(lib, "p17.dirplug", "DESCRIPTION"),
             c("Package: p17.dirplug", "Version: 1.2.0", "Config/gptr/api: >= 9"))
  write_file(file.path(lib, "p17.dirplug", "gptr", "plugin.json"),
             '{"name": "dirplug", "gptr": {"api": ">= 1.0"}}')
  withr::local_libpaths(lib, action = "prefix")
  p = plugin_resolve("p17fakeplug")
  expect_identical(p$kind, "package")
  expect_identical(p$name, "p17fakeplug")
  expect_identical(p$version, "0.3.1")
  expect_identical(p$api, ">= 1.0, < 2")
  expect_identical(p$manifest$gptr$api, ">= 1.0, < 2")
  expect_identical(p$package_path, path_norm(file.path(lib, "p17fakeplug")))
  q = plugin_resolve("p17_dirplug")
  expect_identical(q$kind, "package")
  expect_identical(q$package, "p17.dirplug")
  expect_identical(q$api, ">= 1.0")
  expect_identical(q$path, path_norm(file.path(lib, "p17.dirplug", "gptr")))
  expect_false(isNamespaceLoaded("p17fakeplug"))
  expect_false(isNamespaceLoaded("p17.dirplug"))
})

test_that("an installed Claude plugin without a manifest name is named by its key (D-088)", {
  cache = file.path(withr::local_tempdir(), "cache", "mk")
  skill = "---\nname: s\ndescription: S.\n---\nx"
  docs = file.path(cache, "doc-skills", "3b600518a637")
  write_file(file.path(docs, ".claude-plugin", "marketplace.json"),
             '{"name": "mk", "owner": {"name": "T"}, "plugins": []}')
  write_file(file.path(docs, "skills", "s", "SKILL.md"), skill)
  empty = file.path(cache, "p17-empty", "0a1b2c3d4e5f")
  dir.create(file.path(empty, ".claude-plugin"), recursive = TRUE)
  bare = file.path(cache, "p17-bare", "1.0.0")
  write_file(file.path(bare, "skills", "s", "SKILL.md"), skill)
  odd = file.path(cache, "p17-odd-name", "2.0.0")
  write_file(file.path(odd, ".claude-plugin", "plugin.json"), '{"name": 42, "version": "2.0.0"}')
  plain = file.path(cache, "p17-plain", "9.9.9")
  dir.create(plain, recursive = TRUE)
  named = file.path(cache, "p17-named", "abc123")
  write_file(file.path(named, ".claude-plugin", "plugin.json"), '{"name": "p17-named-tools"}')
  paths = c("doc-skills" = docs, "p17-empty" = empty, "p17-bare" = bare,
            "p17-odd-name" = odd, "p17-plain" = plain, "p17-named" = named)
  when = "2026-09-11T06:30:08.840Z"
  entry = function(p) list(list(scope = "user", installPath = p, lastUpdated = when))
  plugins = stats::setNames(lapply(paths, entry), paste0(names(paths), "@mk"))
  inst = file.path(user_home(), ".claude", "plugins", "installed_plugins.json")
  withr::defer(unlink(inst))
  write_file(inst, json_encode(list(version = 2L, plugins = plugins)))
  for (k in setdiff(names(paths), "p17-named")) {
    r = plugin_resolve(k)
    expect_identical(r$kind, "claude-plugin")
    expect_identical(r$name, k)
    expect_identical(r$path, path_norm(paths[[k]]))
  }
  expect_identical(plugin_resolve("doc_skills")$name, "doc-skills")
  expect_identical(plugin_resolve("p17-empty")$manifest, list())
  expect_identical(plugin_resolve("p17-odd-name")$version, "2.0.0")
  expect_identical(plugin_resolve("p17-named")$name, "p17-named-tools")
})
