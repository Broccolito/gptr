# Tests of R/skill-discover.R (plan P17). Task 2: parsing, the bounded walk, gptr_skills().

skill_md = function(name, description, extra = character(), body = "Body.") {
  c("---", paste0("name: ", name), paste0("description: ", description), extra, "---", "", body)
}

write_skill = function(root, dir, lines) {
  d = file.path(root, dir)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, "SKILL.md"), useBytes = TRUE)
  file.path(d, "SKILL.md")
}

# TEMPORARY (D-074). P08's trust.get service (IC-33) does not exist yet: until it does, answer
# it for the calling test from the trust record local_project(trust = TRUE) writes; P08's own
# service wins once it is registered. P08 Task 2 MUST delete this helper and its one call.
local_trust_record = function(.env = parent.frame()) {
  if (ext_service_has("trust.get")) return(invisible(NULL))
  old = the$services[["trust.get"]]
  withr::defer({
    the$services[["trust.get"]] = old
  }, envir = .env)
  ext_service_set("trust.get", function(path = getwd()) {
    file = file.path(gptr_user_dir("config"), "trust.json")
    if (!file.exists(file)) return(FALSE)
    record = json_decode(readLines(file, encoding = "UTF-8"))
    isTRUE(record$projects[[path_key(path_norm(path))]]$trusted)
  }, provided_by = "test")
  invisible(NULL)
}

test_that("skill_parse builds a skill spec from SKILL.md", {
  root = withr::local_tempdir()
  md = skill_md("pdf-tools", "Extract text from PDF files.",
                c("allowed-tools: read r", "version: 1.0"))
  f = write_skill(root, "pdf-tools", md)
  s = skill_parse(f)
  expect_s3_class(s, "gptr_skill")
  expect_identical(s[["name"]], "pdf-tools")
  expect_identical(s[["description"]], "Extract text from PDF files.")
  expect_identical(s[["path"]], path_norm(f))
  expect_identical(s[["dir"]], path_norm(dirname(f)))
  expect_identical(s[["allowed_tools"]], c("read", "r"))
  expect_identical(s[["version"]], "1.0")
  expect_false(s[["disable_model_invocation"]])
  expect_gt(s[["tokens"]], 0)
})

test_that("skills without a description or with an invalid name are skipped and diagnosed", {
  root = withr::local_tempdir()
  expect_null(skill_parse(write_skill(root, "nodesc", c("---", "name: nodesc", "---", "x"))))
  bad = c("---", "description: Named after its folder.", "---", "x")
  expect_null(skill_parse(write_skill(root, "Bad_Name", bad)))
  other = skill_parse(write_skill(root, "folder-a", skill_md("other-name", "Mismatch.")))
  expect_identical(other[["name"]], "other-name")
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("description is required", msgs, fixed = TRUE)))
  expect_true(any(grepl("name contains invalid characters", msgs, fixed = TRUE)))
  expect_true(any(grepl("name does not match the directory name", msgs, fixed = TRUE)))
})

test_that("a SKILL.md with name: on and version: 1.0 keeps both as strings (IC-71)", {
  root = withr::local_tempdir()
  s = skill_parse(write_skill(root, "on", c("---", "name: on", "version: 1.0",
                                            "description: A skill named on.", "---", "x")))
  expect_identical(s[["name"]], "on")
  expect_identical(s[["version"]], "1.0")
})

test_that("a 37-skill corpus in the styles of report 05 parses completely", {
  root = withr::local_tempdir()
  for (i in 1:21) {
    md = c("---", sprintf("name: folded-%02d", i), "description: >",
           "  Use when: the user asks for task", sprintf("  number %d; note: folded scalar", i),
           "version: 1.0.0", "metadata:", "  author: example", "---", "Body")
    write_skill(root, sprintf("folded-%02d", i), md)
  }
  for (i in 1:8) {
    md = c("---", sprintf("name: plain-%02d", i), sprintf("description: \"Quoted: text %d\"", i),
           "tags: [a, b]", "---", "Body")
    write_skill(root, sprintf("plain-%02d", i), md)
  }
  for (i in 1:5) {
    md = c("---", sprintf("name: repair-%02d", i),
           sprintf("description: Use this when: case %d", i), "---", "Body")
    write_skill(root, sprintf("repair-%02d", i), md)
  }
  for (i in 1:3) {
    d = file.path(root, sprintf("crlf-%02d", i))
    dir.create(d)
    lines = c("---", sprintf("name: crlf-%02d", i), sprintf("description: BOM and CRLF %d", i),
              "---", "Body")
    writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)),
               charToRaw(paste0(paste(lines, collapse = "\r\n"), "\r\n"))),
             file.path(d, "SKILL.md"))
  }
  files = skill_walk(root)
  expect_length(files, 37L)
  specs = lapply(files, skill_parse)
  expect_false(any(vapply(specs, is.null, NA)))
  desc = vapply(specs, function(s) s[["description"]], "")
  names(desc) = vapply(specs, function(s) s[["name"]], "")
  expect_identical(unname(desc["folded-07"]),
                   "Use when: the user asks for task number 7; note: folded scalar")
  expect_identical(unname(desc["plain-03"]), "Quoted: text 3")
  expect_identical(unname(desc["repair-02"]), "Use this when: case 2")
  expect_identical(unname(desc["crlf-01"]), "BOM and CRLF 1")
})

test_that("skill_walk skips dot-directories, node_modules and files inside a skill", {
  root = withr::local_tempdir()
  write_skill(root, "a", skill_md("a", "Skill a."))
  write_skill(root, "a/references/inner", skill_md("inner", "Inside skill a."))
  write_skill(root, ".hidden/b", skill_md("b", "Hidden."))
  write_skill(root, "node_modules/c", skill_md("c", "In node_modules."))
  write_skill(root, "group/d", skill_md("d", "One level down."))
  write_skill(root, "l1/l2/l3/l4/e", skill_md("e", "Five levels down."))
  expect_setequal(basename(dirname(skill_walk(root))), c("a", "d"))
})

test_that("gptr_skills lists project and user skills; the project wins a name", {
  p = local_project(trust = TRUE)
  local_trust_record()
  write_skill(file.path(p, ".gptr", "skills"), "shared", skill_md("shared", "Project version."))
  write_skill(file.path(p, ".claude", "skills"), "proj-only", skill_md("proj-only", "Project."))
  user_root = file.path(gptr_user_dir("config"), "skills")
  write_skill(user_root, "shared", skill_md("shared", "User version."))
  withr::defer(unlink(file.path(user_root, "shared"), recursive = TRUE))
  sk = gptr_skills()
  expect_s3_class(sk, "gptr_skills")
  expect_named(sk, c("name", "description", "source", "path", "tokens", "visible"))
  shared = sk[sk$name == "shared", , drop = FALSE]
  expect_identical(shared$source, c("project", "user"))
  expect_identical(shared$visible, c(TRUE, FALSE))
  expect_true("proj-only" %in% gptr_skills("project")$name)
  expect_false("proj-only" %in% gptr_skills("user")$name)
})

test_that("an untrusted project's skills are listed as untrusted and never visible", {
  p = local_project(trust = FALSE)
  write_skill(file.path(p, ".gptr", "skills"), "proj-skill", skill_md("proj-skill", "Project."))
  sk = gptr_skills("project")
  expect_identical(sk$source, "project (untrusted)")
  expect_false(sk$visible)
})

test_that("gptr_skills validates its scope", {
  expect_error(gptr_skills("everything"), class = "gptr_error_invalid_argument")
})

# Task 2 review round 1 (D-074): untrusted SKILL.md text never stops discovery.

test_that("NA spellings in SKILL.md frontmatter never stop gptr_skills() (IC-71)", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  write_skill(root, "na-name", c("---", "name: .na.character", "description: d", "---", "x"))
  write_skill(root, "na-desc", c("---", "name: na-desc", "description: .na.character", "---",
                                 "x"))
  write_skill(root, "na-real", c("---", "name: .na", "description: .na.real", "---", "x"))
  sk = gptr_skills("project")
  expect_setequal(sk$name, c("good", "na-desc"))
  expect_identical(sk$description[sk$name == "na-desc"], ".na.character")
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("na-name/SKILL.md: name contains invalid characters", msgs,
                        fixed = TRUE)))
  expect_true(any(grepl("na-real/SKILL.md: name contains invalid characters", msgs,
                        fixed = TRUE)))
})

test_that("skill_parse treats NA fields as missing and turns a failure into a diagnostic", {
  root = withr::local_tempdir()
  f = write_skill(root, "fallback", skill_md("fallback", "On disk."))
  meta = list(name = NA_character_, description = "From the parser.")
  local_mocked_bindings(frontmatter_read = function(path) {
    list(meta = meta, body = "x", repaired = FALSE, error = NULL, has_frontmatter = TRUE)
  })
  s = skill_parse(f)
  expect_identical(s[["name"]], "fallback")
  expect_identical(s[["description"]], "From the parser.")
  meta = list(name = "fallback", description = NA_character_)
  expect_null(skill_parse(f))
  local_mocked_bindings(frontmatter_read = function(path) stop("simulated parser failure"))
  expect_null(skill_parse(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("fallback/SKILL.md: description is required", msgs, fixed = TRUE)))
  expect_true(any(grepl("simulated parser failure", msgs, fixed = TRUE)))
})

# Task 2 review round 2 (D-074 item 4): a relative skills.paths entry is project content.

test_that("a relative skills.paths entry is a project root and follows project trust (IC-52)", {
  p = local_project(trust = FALSE)
  write_skill(file.path(p, "tools", "skills"), "rel-skill", skill_md("rel-skill", "Relative."))
  abs_root = withr::local_tempdir()
  write_skill(abs_root, "abs-skill", skill_md("abs-skill", "Absolute."))
  withr::local_options(gptr.skills = list(paths = c("tools/skills", abs_root)))
  df = skill_discover()
  rel = df[df$name == "rel-skill", , drop = FALSE]
  expect_identical(rel$source, "project (untrusted)")
  expect_identical(rel$origin, "project")
  expect_identical(rel$rank, 1L)
  expect_false(rel$trusted)
  expect_false(rel$visible)
  ab = df[df$name == "abs-skill", , drop = FALSE]
  expect_identical(ab$source, "user")
  expect_identical(ab$rank, 3L)
  expect_true(ab$visible)
  expect_true("rel-skill" %in% gptr_skills("project")$name)
  expect_false("rel-skill" %in% gptr_skills("user")$name)
})

# Task 2 review round 3 (D-074 items 5-7): bounded parsing, no warnings, `~name` entries.

skill_alias_chain = function(levels) {
  out = "x0: &a0 [a, b, c, d, e, f, g, h, i]"
  for (i in seq_len(levels)) {
    refs = paste(rep(sprintf("*a%d", i - 1L), 9L), collapse = ", ")
    out = c(out, sprintf("x%d: &a%d [%s]", i, i, refs))
  }
  out
}

test_that("a SKILL.md whose YAML aliases expand too far is skipped with a diagnostic", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  # Round 5: at most 4 references to anchors reach yaml, so this stays within that cap.
  many = paste0("x0: &a0 [", paste(rep("a", 8000L), collapse = ","), "]")
  f = write_skill(root, "bomb", c("---", "name: bomb", "description: d", many,
                                  "disable-model-invocation: &a1 [*a0, *a0, *a0]",
                                  "allowed-tools: *a1", "---", "x"))
  expect_identical(gptr_skills("project")$name, "good")
  expect_null(skill_parse_cached(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("bomb/SKILL.md: invalid YAML frontmatter: too large once its aliases",
                        msgs, fixed = TRUE)))
})

test_that("skill_parse reads a scalar disable-model-invocation and flat allowed-tools only", {
  root = withr::local_tempdir()
  f = write_skill(root, "shape", skill_md("shape", "On disk."))
  nested = letters[1:9]
  for (i in 1:6) nested = rep(list(nested), 9L)
  meta = list(name = "shape", description = "d", `disable-model-invocation` = nested,
              `allowed-tools` = nested)
  local_mocked_bindings(frontmatter_read = function(path) {
    list(meta = meta, body = "x", repaired = FALSE, error = NULL, has_frontmatter = TRUE)
  })
  s = skill_parse(f)
  expect_false(s[["disable_model_invocation"]])
  expect_identical(s[["allowed_tools"]], character())
  meta = list(name = "shape", description = "d", `disable-model-invocation` = list("true"),
              `allowed-tools` = list("read", 1L))
  s = skill_parse(f)
  expect_false(s[["disable_model_invocation"]])
  expect_identical(s[["allowed_tools"]], c("read", "1"))
  meta = list(name = "shape", description = "d", `disable-model-invocation` = "True")
  expect_true(skill_parse(f)[["disable_model_invocation"]])
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("shape/SKILL.md: allowed-tools must be a list of tool names", msgs,
                        fixed = TRUE)))
})

test_that("an unreadable SKILL.md is a diagnostic and never a warning (contract 6.3)", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["effective_user"]], "root"), "root reads any file")
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  f = write_skill(root, "noread", skill_md("noread", "Unreadable."))
  Sys.chmod(f, "000")
  withr::defer(Sys.chmod(f, "644"))
  skip_if(file.access(f, 4L) == 0L, "the file stays readable")
  sk = expect_no_warning(gptr_skills("project"))
  expect_identical(sk$name, "good")
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("noread/SKILL.md: cannot read the file", msgs, fixed = TRUE)))
})

test_that("only ~ and ~/ skills.paths entries are home directories; ~name is project content", {
  p = local_project(trust = FALSE)
  home = withr::local_tempdir()
  local_mocked_bindings(user_home = function() home)
  write_skill(file.path(p, "~bob", "skills"), "tilde-user", skill_md("tilde-user", "Tilde."))
  write_skill(file.path(home, "my-skills"), "home-skill", skill_md("home-skill", "Home."))
  withr::local_options(gptr.skills = list(paths = list("~bob/skills", "~/my-skills")))
  df = skill_discover()
  tu = df[df$name == "tilde-user", , drop = FALSE]
  expect_identical(tu$source, "project (untrusted)")
  expect_identical(tu$origin, "project")
  expect_false(tu$trusted)
  expect_false(tu$visible)
  hs = df[df$name == "home-skill", , drop = FALSE]
  expect_identical(hs$source, "user")
  expect_identical(hs$rank, 3L)
  expect_true(hs$visible)
})

# Task 2 review round 4 (D-074 items 8 and 9): a name ends at the end of the string, and
# frontmatter that would make yaml slow is refused before yaml runs.

test_that("a skill name ending in a newline is refused with a diagnostic (contract 11.13)", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  bad = list(
    `block-lit` = c("---", "name: |", "  block-lit", "description: d", "---", "x"),
    `block-fold` = c("---", "name: >", "  block-fold", "description: d", "---", "x"),
    `quoted-nl` = c("---", "name: \"quoted-nl\\n\"", "description: d", "---", "x")
  )
  files = vapply(names(bad), function(d) write_skill(root, d, bad[[d]]), "")
  expect_identical(frontmatter_read(files[["block-lit"]])$meta$name, "block-lit\n")
  expect_identical(gptr_skills("project")$name, "good")
  for (f in files) expect_null(skill_parse(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  for (d in names(bad)) {
    expect_true(any(grepl(paste0(d, "/SKILL.md: name must match"), msgs, fixed = TRUE)))
  }
})

test_that("a skill directory whose name ends in a newline is refused too", {
  skip_on_os("windows")
  root = withr::local_tempdir()
  d = file.path(root, "dir-nl\n")
  made = tryCatch(dir.create(d), warning = function(w) FALSE, error = function(e) FALSE)
  skip_if(!isTRUE(made) || !dir.exists(d), "the file system refuses a newline in a name")
  f = file.path(d, "SKILL.md")
  writeLines(c("---", "description: Named after its folder.", "---", "x"), f)
  expect_null(skill_parse(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("dir-nl\n/SKILL.md: name must match", msgs, fixed = TRUE)))
})

test_that("frontmatter that would make yaml slow is skipped; a sibling skill is still listed", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  # Round 6: the byte limit is 16,384, so `deep` stays below it and `huge` is 20 KB.
  write_skill(root, "deep", skill_md("deep", "d", paste0("x: ", strrep("[", 5000L),
                                                         strrep("]", 5000L))))
  write_skill(root, "huge", skill_md("huge", strrep("y", 20000L)))
  expect_identical(gptr_skills("project")$name, "good")
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("deep/SKILL.md: invalid YAML frontmatter: too deeply nested", msgs,
                        fixed = TRUE)))
  expect_true(any(grepl("huge/SKILL.md: invalid YAML frontmatter: too large (more than 16384",
                        msgs, fixed = TRUE)))
})

# Task 2 review round 5 (D-074 item 9): a chain of aliases used as a mapping key, or merged
# under a `? <<` key, never reaches yaml.

test_that("a SKILL.md with more than 4 references to its anchors is skipped before yaml runs", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  key = write_skill(root, "key", c("---", "name: key", "description: d", skill_alias_chain(7L),
                                   "m:", "  ? *a7", "  : 1", "---", "x"))
  merge = write_skill(root, "merge", c("---", "name: merge", "description: d",
                                       "base: &b {k: 1}", "m:", "  ? <<",
                                       "  : [*b, *b, *b, *b, *b]", "---", "x"))
  real_load = fm_load
  local_mocked_bindings(fm_load = function(txt, raw = FALSE) {
    if (grepl("*", txt, fixed = TRUE)) return(simpleError("yaml ran on the aliases"))
    real_load(txt, raw)
  })
  expect_identical(gptr_skills("project")$name, "good")
  expect_null(skill_parse_cached(key))
  expect_null(skill_parse_cached(merge))
  msgs = gptr_registry(diagnostics = TRUE)$message
  for (d in c("key", "merge")) {
    expect_true(any(grepl(paste0(d, "/SKILL.md: invalid YAML frontmatter: too many aliases ",
                                 "(more than 4 references to anchors)"), msgs, fixed = TRUE)))
  }
})

# Task 2 review round 6 (D-074 item 9): nested merges with no alias, under `<<` or a merge tag,
# never reach yaml.

test_that("a SKILL.md with more than 4 merge keys, tags and aliases is skipped before yaml", {
  p = local_project(trust = FALSE)
  root = file.path(p, ".gptr", "skills")
  write_skill(root, "good", skill_md("good", "A valid skill."))
  keys = paste0("{", paste0("k", 1:500, collapse = ", "), "}")
  bad = list(
    flowmerge = paste0("m: ", strrep("{<<: ", 200L), keys, strrep("}", 200L)),
    blockmerge = c("m:", vapply(1:20, function(i) paste0(strrep(" ", i), "<<:"), ""),
                   paste0(strrep(" ", 21L), "<<: ", keys)),
    tagmerge = paste0("m: ", strrep("{!!merge x: ", 5L), keys, strrep("}", 5L))
  )
  files = vapply(names(bad), function(d) {
    write_skill(root, d, c("---", paste0("name: ", d), "description: d", bad[[d]], "---", "x"))
  }, "")
  real_load = fm_load
  local_mocked_bindings(fm_load = function(txt, raw = FALSE) {
    if (grepl("<<|!", txt)) return(simpleError("yaml ran on the merge keys"))
    real_load(txt, raw)
  })
  expect_identical(gptr_skills("project")$name, "good")
  for (f in files) expect_null(skill_parse_cached(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  for (d in names(bad)) {
    expect_true(any(grepl(paste0(d, "/SKILL.md: invalid YAML frontmatter: too many merge keys, ",
                                 "tags and aliases (more than 4 in all)"), msgs, fixed = TRUE)))
  }
})

# Task 3: the built-in high-performance-r skill and gptr's own manifest.

hpr_line = paste0("- high-performance-r: Fast data work in R: data.table, arrow, duckdb, ",
                  "collapse or qs2 when installed; large CSV/Parquet, grouping, sorting, ",
                  "parallel work, single-cell objects. [skill:high-performance-r/SKILL.md]")

hpr_files = function() {
  list.files(system.file("gptr", "skills", "high-performance-r", package = "gptr"),
             recursive = TRUE, full.names = TRUE)
}

test_that("the built-in high-performance-r skill parses with its catalog line", {
  f = system.file("gptr", "skills", "high-performance-r", "SKILL.md", package = "gptr")
  expect_true(nzchar(f))
  s = skill_parse(f)
  expect_identical(s[["name"]], "high-performance-r")
  expect_identical(skill_line(s[["name"]], s[["description"]]), hpr_line)
  pk = gptr_skills("packages")
  expect_identical(pk$source[pk$name == "high-performance-r"], "builtin")
})

test_that("the shipped skill never recommends str() and states its cost (IC-67)", {
  read_all = function(f) paste(readLines(f, encoding = "UTF-8"), collapse = "\n")
  txt = vapply(hpr_files(), read_all, "")
  expect_length(txt, 3L)
  expect_false(any(grepl("(^|[^A-Za-z0-9_.])str\\(", txt)))
  expect_true(any(grepl("sticky reference", txt, fixed = TRUE)))
  expect_false(any(grepl("<\\-", txt)))
  expect_true(all(vapply(txt, function(x) all(utf8ToInt(x) < 128L), NA)))
})

test_that("every R recipe in the skill parses", {
  n = 0L
  for (f in hpr_files()) {
    lines = readLines(f, encoding = "UTF-8")
    open = which(grepl("^[ ]*```r[ ]*$", lines))
    close = which(grepl("^[ ]*```[ ]*$", lines))
    for (o in open) {
      e = close[close > o][1L]
      expect_no_error(parse(text = lines[seq.int(o + 1L, e - 1L)], keep.source = FALSE))
      n = n + 1L
    }
  }
  expect_gte(n, 15L)
})

test_that("gptr's manifest declares its resource directories", {
  m = json_decode(read_utf8(system.file("gptr", "plugin.json", package = "gptr"))$text)
  expect_identical(m$name, "gptr")
  expect_identical(c(m$skills, m$prompts, m$agents), c("skills", "prompts", "agents"))
  expect_identical(m$gptr$api, ">= 1.0, < 2")
})
