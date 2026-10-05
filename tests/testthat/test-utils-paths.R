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

test_that("write_atomic() writes privately and keeps the permission bits it replaces", {
  skip_on_os("windows")
  dir = withr::local_tempdir()
  writer = write_bytes
  modes = character()
  local_mocked_bindings(write_bytes = function(path, bytes) {
    modes <<- c(modes, format(file.info(path)$mode))
    writer(path, bytes)
  })
  for (mode in c("755", "600", "444")) {
    target = file.path(dir, mode)
    writeLines("old", target)
    Sys.chmod(target, mode, use_umask = FALSE)
    write_atomic(target, "new")
    expect_identical(readLines(target), "new")
    expect_identical(format(file.info(target)$mode), mode)
  }
  expect_identical(modes, rep("600", 3L))
})

test_that("project_root() honours the option, then GPTR_PROJECT_ROOT (IC-63)", {
  dir = withr::local_tempdir()
  withr::local_options(gptr.project_root = dir)
  expect_identical(project_root(), path_norm(dir))
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = dir)
  expect_identical(project_root("/"), path_norm(dir))
})

test_that("project_root() finds the nearest marked ancestor, else the start directory", {
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  dir = withr::local_tempdir()
  deep = file.path(dir, "proj", "R", "sub")
  dir.create(deep, recursive = TRUE)
  file.create(file.path(dir, "proj", "_quarto.yml"))
  expect_identical(project_root(deep), path_norm(file.path(dir, "proj")))
  dir.create(file.path(dir, "proj", "R", ".gptr"))
  expect_identical(project_root(deep), path_norm(file.path(dir, "proj", "R")))
})

test_that("user_home() uses USERPROFILE on Windows and HOME elsewhere (IC-63)", {
  withr::local_envvar(USERPROFILE = "C:\\Users\\me", HOME = "/home/me")
  local_mocked_bindings(is_windows = function() TRUE)
  expect_identical(user_home(), "C:/Users/me")
  local_mocked_bindings(is_windows = function() FALSE)
  expect_identical(user_home(), "/home/me")
})

test_that("app_config_dir() follows each platform's convention", {
  withr::local_envvar(
    APPDATA = "C:\\Users\\me\\AppData\\Roaming", HOME = "/home/me", XDG_CONFIG_HOME = NA
  )
  local_mocked_bindings(is_windows = function() TRUE, is_macos = function() FALSE)
  expect_identical(app_config_dir("Claude"), "C:/Users/me/AppData/Roaming/Claude")
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() TRUE)
  expect_identical(app_config_dir("Claude"), "/home/me/Library/Application Support/Claude")
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  expect_identical(app_config_dir("codex"), "/home/me/.config/codex")
  withr::local_envvar(XDG_CONFIG_HOME = "/xdg")
  expect_identical(app_config_dir("codex"), "/xdg/codex")
})

test_that("rscript_path() points into R.home('bin'), never at a PATH lookup (IC-60)", {
  path = rscript_path()
  expect_identical(dirname(path), R.home("bin"))
  expect_true(file.exists(path))
})

test_that("gptr_user_dir() is tools::R_user_dir() and is created only on request", {
  dir = gptr_user_dir("cache")
  expect_identical(dir, tools::R_user_dir("gptr", "cache"))
  expect_match(dir, "gptr-tests-", fixed = TRUE)
  unlink(dir, recursive = TRUE)
  gptr_user_dir("cache")
  expect_false(dir.exists(dir))
  gptr_user_dir("cache", create = TRUE)
  expect_true(dir.exists(dir))
  expect_error(gptr_user_dir("home"), class = "gptr_error_invalid_argument")
})

test_that("path_norm() resolves symlinked ancestors, '..' and '~' for missing paths", {
  dir = path_norm(withr::local_tempdir())
  expect_identical(path_norm(file.path(dir, "a", "..", "b", "c.txt")), file.path(dir, "b", "c.txt"))
  expect_identical(path_norm("~/x"), paste0(path_norm(user_home()), "/x"))
  withr::local_dir(dir)
  expect_identical(path_norm("rel.R"), file.path(dir, "rel.R"))
})

# CI-5 (D-111): path_norm() promises forward slashes whatever user_home() returns. The Windows
# tests mock user_home() with withr::local_tempdir(), whose path has backslashes there, and "~/x"
# became a relative path under the working directory (hosted test-ext-plugins.R:481 and
# test-skill-discover.R:295-297).
test_that("path_norm() expands '~' before it turns backslashes into slashes (CI-5)", {
  home = path_norm(withr::local_tempdir())
  dir.create(file.path(home, "sub"))
  local_mocked_bindings(user_home = function() gsub("/", "\\", home, fixed = TRUE))
  expect_identical(path_norm("~/sub"), file.path(home, "sub"))
  expect_identical(path_norm("~\\sub\\x.R"), file.path(home, "sub", "x.R"))
  expect_identical(path_norm("~"), home)
  expect_identical(path_norm(c("~/a", "~b/c")), c(file.path(home, "a"), path_norm("~b/c")))
  expect_false(any(grepl("\\", path_norm(c("~", "~/sub", "~/no/such")), fixed = TRUE)))
})

# CI-5 (D-111): R >= 4.6's tools::file_ext() and tools::file_path_sans_ext() call basename(),
# which stops on a marked UTF-8 non-ASCII path in a non-UTF-8 locale. path_ext() and
# path_sans_ext() keep R 4.6's rule (an alphanumeric extension after at least one character that
# is not a dot) and never translate the path, in every locale and on every R.
test_that("path_ext() and path_sans_ext() follow R 4.6's rule without basename() (CI-5)", {
  p = c("a/report.Rmd", "C:\\dir\\x.tar.gz", "noext", ".Rprofile", "dir.d/.env", "dir\\.env",
        "a/b.c/file", "x.", "..R", "a.b-c", "trail.R/", "caf\u00e9.R", "d\u00e9/caf\u00e9",
        "x.\u00e9", NA)
  ext = c("Rmd", "gz", "", "", "", "", "", "", "", "", "", "R", "", "", "")
  sans = c("a/report", "C:\\dir\\x.tar", "noext", ".Rprofile", "dir.d/.env", "dir\\.env",
           "a/b.c/file", "x.", "..R", "a.b-c", "trail.R/", "caf\u00e9", "d\u00e9/caf\u00e9",
           "x.\u00e9", NA)
  expect_identical(path_ext(p), ext)
  expect_identical(path_sans_ext(p), sans)
  expect_identical(path_ext(character()), character())
  expect_identical(path_sans_ext(character()), character())
  # The same answers in a locale where basename() cannot translate the non-ASCII names
  local_name_locale()
  local_r46_file_ext()
  expect_identical(path_ext(p), ext)
  expect_identical(path_sans_ext(p), sans)
  expect_identical(Encoding(path_sans_ext("caf\u00e9.R")), "UTF-8")
  # and R 4.6's own functions agree on the names basename() can take, except where D-111 item 1
  # differs on purpose: "\\" separates components on every OS ("dir\\.env" has no extension;
  # tools gives "env" on macOS and Linux) and a trailing separator leaves no extension
  # (tools::file_ext("trail.R/") is "trail.R/")
  ascii = !is.na(p) & !grepl("[^ -~]", p) & !grepl("\\\\|/$", p)
  expect_identical(tools::file_ext(p[ascii]), ext[ascii])
  expect_identical(tools::file_path_sans_ext(p[ascii]), sans[ascii])
})

test_that("path_key() lower-cases on Windows and macOS only (IC-51)", {
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() TRUE)
  expect_identical(path_key("/TMP/Foo"), tolower(path_norm("/TMP/Foo")))
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  # path_norm() adds the drive letter on Windows, so compare with it, then check the case
  expect_identical(path_key("/no/such/Foo"), path_norm("/no/such/Foo"))
  expect_true(endsWith(path_key("/no/such/Foo"), "/no/such/Foo"))
})

test_that("workspace_root() is .gptr/ when it exists, else tempdir()/gptr", {
  dir = withr::local_tempdir()
  withr::local_options(gptr.project_root = dir)
  expect_null(workspace_dir())
  expect_identical(workspace_root(), file.path(tempdir(), "gptr"))
  dir.create(file.path(dir, ".gptr"))
  expect_identical(path_norm(workspace_root()), path_norm(file.path(dir, ".gptr")))
  path = ws_path("cache", "tmp", "x.txt")
  expect_true(dir.exists(dirname(path)))
  expect_false(file.exists(path))
})

test_that("save_rds() and serialize_leaf() round-trip without ascii serialisation (R7)", {
  file = withr::local_tempfile(fileext = ".rds")
  save_rds(mtcars, file)
  expect_identical(readRDS(file), mtcars)
  bytes = serialize_leaf(letters)
  expect_true(is.raw(bytes))
  expect_identical(unserialize(bytes), letters)
})

test_that("path_rel() is root-relative inside the root and absolute outside", {
  root = path_norm(withr::local_tempdir())
  expect_identical(path_rel(file.path(root, "R", "a.R"), root), "R/a.R")
  expect_identical(path_rel(root, root), ".")
  expect_identical(path_rel("/elsewhere/x", root), path_norm("/elsewhere/x"))
})

test_that("reserved_name() recognises Windows device names", {
  expect_identical(reserved_name(c("con", "NUL.txt", "com1", "lpt9.R", "console", "data")),
                   c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE))
})

test_that("path_class() assigns the classes of report 18 and IC-54", {
  root = path_norm(withr::local_tempdir())
  home = path_norm(user_home())
  cls = function(p) path_class(p, root)
  expect_identical(cls("https://example.org/data.csv"), "url")
  expect_identical(cls("R/*.R"), "wildcard")
  expect_identical(cls(NA_character_), "unknown")
  expect_identical(cls(".gptr/settings.json"), "control")
  expect_identical(cls(".gptr/settings.local.json"), "control")
  expect_identical(cls(".gptr/mcp.json"), "control")
  expect_identical(cls(".gptr/extensions/tool.R"), "control")
  expect_identical(cls(".gptr/SYSTEM.md"), "control")
  expect_identical(cls(".git/hooks/pre-commit"), "control")
  expect_identical(cls("sub/.Rprofile"), "control")
  expect_identical(cls(file.path(tools::R_user_dir("gptr", "config"), "settings.json")), "control")
  expect_identical(cls(file.path(home, ".R", "Makevars")), "control")
  expect_identical(cls(root), "critical")
  expect_identical(cls("/"), "critical")
  expect_identical(cls(home), "critical")
  expect_identical(cls(tempdir()), "critical")
  expect_identical(cls(".git/HEAD"), "protected")
  expect_identical(cls(".env"), "protected")
  expect_identical(cls("renv.lock"), "protected")
  expect_identical(cls(file.path(home, ".ssh", "id_rsa")), "protected")
  expect_identical(cls("AGENTS.md"), "instructions")
  expect_identical(cls("CLAUDE.md"), "instructions")
  expect_identical(cls(".gptr/vignette.Rmd"), "instructions")
  expect_identical(cls(".gptr/skills/x/SKILL.md"), "instructions")
  expect_identical(cls("R/analysis.R"), "workspace")
  expect_identical(cls(file.path(tempdir(), "scratch.csv")), "temp")
  expect_identical(cls("/opt/elsewhere/file.txt"), "outside")
  # Linux keeps the case of path keys: ~/.R/Makevars is still a control file there
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  expect_identical(path_class(file.path(home, ".R", "Makevars"), root), "control")
})

test_that("path_class protects local credential directories and env files", {
  root = path_norm(withr::local_tempdir())
  paths = c(".secrets", ".secrets/jev-key.env", "keys/llm-passwords.env")
  expect_identical(path_class(paths, root), rep("protected", length(paths)))
})

test_that("lexical control and secret paths stay protected when they are symlinks", {
  skip_on_os("windows")
  root = path_norm(withr::local_tempdir())
  dir.create(file.path(root, ".gptr"))
  plain = file.path(root, "plain.json")
  writeLines("{}", plain)
  links = c(".gptr/settings.json", "credentials.env", "AGENTS.md")
  ok = vapply(links, function(link) file.symlink(plain, file.path(root, link)), logical(1))
  skip_if_not(all(ok), "symlinks are unavailable")
  expect_identical(path_class(links, root), c("control", "protected", "instructions"))
  dir.create(file.path(root, ".gptr", "tmp"))
  aliases = c(".gptr/./settings.json", ".gptr/tmp/../settings.json")
  expect_identical(path_class(aliases, root), rep("control", 2L))
  target = file.path(root, ".gptr", "mcp.json")
  writeLines("{}", target)
  expect_true(file.symlink(target, file.path(root, "ordinary.json")))
  expect_identical(path_class("ordinary.json", root), "control")
})

test_that("path_rel handles filesystem roots without dropping a character", {
  path = path_norm(file.path(tempdir(), "example.txt"))
  root = if (.Platform$OS.type == "windows") paste0(substr(path, 1L, 2L), "/") else "/"
  expect_identical(path_rel(path, root), substring(path, nchar(root) + 1L))
  expect_identical(path_rel(root, root), ".")
})
