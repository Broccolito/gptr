# Atomic writes (Task 5); paths, homes, workspace, serialisation leaves and path classes (Task 6).

test_that("write_atomic() writes UTF-8 lines with LF, or raw bytes, and replaces files", {
  skip_on_cran()
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
  skip_on_cran()
  dir = withr::local_tempdir()
  path = file.path(dir, "locked.txt")
  writeLines("old", path)
  local_mocked_bindings(file_rename = function(from, to) FALSE)
  write_atomic(path, "new")
  expect_identical(readLines(path, encoding = "UTF-8"), "new")
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 1L)
})

test_that("write_atomic() refuses the in-place write when the file changed meanwhile", {
  skip_on_cran()
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

test_that("write_atomic() writes privately, keeps replaced permission bits, else `mode`", {
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
    write_atomic(target, "new", mode = "0640")
    expect_identical(readLines(target), "new")
    expect_identical(format(file.info(target)$mode), mode)
  }
  write_atomic(file.path(dir, "new"), "x", mode = "0640")
  expect_identical(format(file.info(file.path(dir, "new"))$mode), "640")
  write_atomic(file.path(dir, "private"), "x")
  expect_identical(format(file.info(file.path(dir, "private"))$mode), "600")
  expect_identical(modes, rep("600", 5L))
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

test_that("project_root() lists a directory for *.Rproj again only when its mtime changes", {
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  dir = withr::local_tempdir()
  dir.create(file.path(dir, "a", "b"), recursive = TRUE)
  a = path_norm(file.path(dir, "a"))
  b = file.path(a, "b")
  n = 0L
  local_mocked_bindings(dir_list_rproj = function(dir) {
    if (dir %in% c(a, b)) n <<- n + 1L
    length(list.files(dir, pattern = "\\.Rproj$")) > 0L
  })
  expect_identical(project_root(b), b)
  for (i in seq_len(10L)) project_root(b)
  expect_identical(n, 2L)
  file.create(file.path(a, "x.Rproj"))
  Sys.setFileTime(a, Sys.time() + 5)
  expect_identical(project_root(b), a)
  unlink(file.path(a, "x.Rproj"))
  Sys.setFileTime(a, Sys.time() + 10)
  expect_identical(project_root(b), b)
})

test_that("an unpinned peter() call lists each ancestor for *.Rproj once per mtime", {
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  withr::local_dir(withr::local_tempdir())
  seen = character()
  local_mocked_bindings(dir_list_rproj = function(dir) {
    seen <<- c(seen, paste(dir, format(unclass(file.mtime(dir)), digits = 22L)))
    length(list.files(dir, pattern = "\\.Rproj$")) > 0L
  })
  s = peter("How many rows?", mtcars, model = local_fake_provider(list("32 rows.")),
            envir = new.env())
  expect_identical(s$text, "32 rows.")
  expect_gt(length(seen), 0L)
  expect_identical(anyDuplicated(seen), 0L)
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
  skip_on_cran()
  home = path_norm(withr::local_tempdir())
  dir.create(file.path(home, "sub"))
  local_mocked_bindings(user_home = function() gsub("/", "\\", home, fixed = TRUE))
  expect_identical(path_norm("~/sub"), file.path(home, "sub"))
  expect_identical(path_norm("~\\sub\\x.R"), file.path(home, "sub", "x.R"))
  expect_identical(path_norm("~"), home)
  expect_identical(path_norm(c("~/a", "~b/c")), c(file.path(home, "a"), path_norm("~b/c")))
  expect_false(any(grepl("\\", path_norm(c("~", "~/sub", "~/no/such")), fixed = TRUE)))
})

test_that("path_lexical() normalises without the file system, keeping roots and leading ..", {
  skip_on_cran()
  expect_identical(path_lexical("/a/./b/../c//d/"), "/a/c/d")
  expect_identical(path_lexical("C:\\x\\..\\y\\.\\z"), "C:/y/z")
  expect_identical(path_lexical("C:/.."), "C:/")
  expect_identical(path_lexical("\\\\server\\share\\..\\x"), "//server/share/x")
  expect_identical(path_lexical("/.."), "/")
  expect_identical(path_lexical("../../a"), "../../a")
  expect_identical(path_lexical("a/../.."), "..")
  expect_identical(path_lexical("./"), ".")
  expect_true(is_abs_path("C:\\x") && is_abs_path("/x") && !is_abs_path("x/y"))
})

# CI-5 (D-111): R >= 4.6's tools::file_ext() and tools::file_path_sans_ext() call basename(),
# which stops on a marked UTF-8 non-ASCII path in a non-UTF-8 locale. path_ext() and
# path_sans_ext() keep R 4.6's rule (an alphanumeric extension after at least one character that
# is not a dot) and never translate the path, in every locale and on every R.
test_that("path_ext() and path_sans_ext() follow R 4.6's rule without basename() (CI-5)", {
  skip_on_cran()
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
  expect_identical(path_ext(p), ext)
  expect_identical(path_sans_ext(p), sans)
  expect_identical(Encoding(path_sans_ext("caf\u00e9.R")), "UTF-8")
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
  skip_on_cran()
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

test_that("a project in a protected folder classes a path by its part below the root (D-292)", {
  base = path_norm(withr::local_tempdir())
  root = file.path(base, ".claude", "worktrees", "proj")
  dir.create(file.path(root, "sub"), recursive = TRUE)
  root = path_norm(root)
  cls = function(p) path_class(p, root)
  expect_identical(cls(c("a.csv", "sub/out.txt", file.path(root, "x.R"))), rep("workspace", 3L))
  expect_identical(cls(c(".git/config", ".env", "AGENTS.md", ".git/HEAD")),
                   c("control", "protected", "instructions", "protected"))
  expect_identical(cls(root), "critical")
  expect_identical(cls(file.path(base, ".claude", "settings.json")), "protected")
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

test_that("Windows junctions and file links keep control and secret paths guarded", {
  root = wsec_local()
  plain = file.path(root, "plain")
  dir.create(plain)
  writeLines("{}", file.path(plain, "plain.json"))
  dir.create(file.path(root, ".secrets"))
  writeLines("{}", file.path(root, ".gptr", "mcp.json"))
  wsec_junction(plain, file.path(root, ".gptr", "agents"))
  wsec_junction(file.path(root, ".secrets"), file.path(root, "keys"))
  wsec_link(file.path(plain, "plain.json"), file.path(root, "credentials.env"))
  wsec_link(file.path(root, ".gptr", "mcp.json"), file.path(root, "ordinary.json"))
  paths = c(".gptr/agents/a.md", "keys/token.txt", "credentials.env", "ordinary.json")
  expect_identical(path_class(paths, root), c("control", "protected", "protected", "control"))
})

test_that("path_info() gives a link to nothing no metadata and no warning on every OS", {
  skip_on_cran()
  td = withr::local_tempdir()
  writeLines("x", file.path(td, "file"))
  link = file.path(td, "dangling")
  local_dangling_link(link)
  p = file.path(td, c("file", "dangling", "absent"))
  info = expect_no_warning(path_info(p))
  keep = setdiff(names(info), "atime")   # reading a file may update its access time
  expect_identical(info[1L, keep], file.info(p[1L], extra_cols = FALSE)[keep])
  expect_true(all(is.na(info[-1L, ])))
  expect_identical(info$isdir %in% FALSE, c(TRUE, FALSE, FALSE))
  expect_true(path_dangling(link))
  # R's Windows file.info() for such a link: stat()'s size and kind, NA times, a warning
  windows = path_info
  environment(windows) = list2env(list(file.info = function(...) {
    warning("cannot open file 'dangling': The system cannot find the file specified")
    na = .POSIXct(NA_real_)
    info = data.frame(size = 0, isdir = TRUE, mtime = na, ctime = na, atime = na)
    info$mode = as.octmode("777")   # R 4.2's data.frame() cannot coerce an octmode column
    info
  }), parent = environment(path_info))
  expect_true(all(is.na(expect_no_warning(windows(link)))))
})

test_that("a case variant is a dangling link only where file names ignore case", {
  skip_on_cran()
  td = withr::local_tempdir()
  writeLines("x", file.path(td, "File"))
  local_dangling_link(file.path(td, "Link"))
  fold = file.exists(file.path(td, "FILE"))
  expect_false(path_dangling(file.path(td, "file")))
  expect_identical(path_dangling(file.path(td, "link")), fold)
})

test_that("readers and file tools take a link to nothing for an absent file on every OS", {
  skip_on_cran()
  # A Windows file symlink needs a privilege CRAN may lack; R takes its kind from an existing target
  if (is_windows()) skip_on_cran()
  proj = local_project(files = list(a.R = "a = 1"))
  for (nm in c("gone.txt", ".env")) {
    writeLines("x", file.path(proj, "target"))
    expect_true(file.symlink(file.path(proj, "target"), file.path(proj, nm)))
    expect_true(file.remove(file.path(proj, "target")))
  }
  link = file.path(proj, "gone.txt")
  tr = ckpt_files_tr(ckpt_ck_new("s0000000077"))
  expect_no_warning({
    expect_error(read_utf8(link), "not an existing file", class = "gptr_error_invalid_argument")
    expect_error(read_core(link), "^ENOENT: ", class = "gptr_error_invalid_argument")
    expect_error(edit_file(link, list(list(oldText = "x", newText = "y"))), "Error code: ENOENT.",
                 fixed = TRUE)
    expect_error(patch_apply("*** Begin Patch\n*** Delete File: gone.txt\n*** End Patch", proj),
                 "it names no file", class = "gptr_error_invalid_argument")
    expect_error(search_grep("x", link), "^Path not found: ")
    expect_error(gateway_images_check(link), "existing PNG/JPEG path",
                 class = "gptr_error_invalid_argument")
    expect_identical(search_ls(proj)$path, c(".gptr", "a.R"))
    ckpt_files_sync(tr)
    expect_identical(dotenv_discover(proj, trusted = TRUE), 0L)
  })
  expect_identical(names(tr$hash), "a.R")
  expect_true(all(c("gone.txt", ".env") %in% list.files(proj, all.files = TRUE)))
})

test_that("path_rel handles filesystem roots without dropping a character", {
  path = path_norm(file.path(tempdir(), "example.txt"))
  root = if (.Platform$OS.type == "windows") paste0(substr(path, 1L, 2L), "/") else "/"
  expect_identical(path_rel(path, root), substring(path, nchar(root) + 1L))
  expect_identical(path_rel(root, root), ".")
})


test_that("an absent rename-fallback target is private before payload writing", {
  skip_on_os("windows")
  dir = withr::local_tempdir()
  umask = Sys.umask("0022")
  withr::defer(Sys.umask(umask))
  paths = file.path(dir, c("private.txt", "shared.txt", "existing.txt"))
  writer = write_bytes
  modes = character()
  local_mocked_bindings(file_rename = function(from, to) FALSE,
                        write_bytes = function(path, bytes) {
                          if (path %in% paths && length(bytes)) {
                            modes <<- c(modes, format(file.info(path)$mode))
                          }
                          writer(path, bytes)
                        })
  local_mocked_bindings(Sys.sleep = function(time) NULL, .package = "base")
  write_atomic(paths[1], "synthetic private content", expected_md5 = NA_character_)
  expect_identical(modes, "600")
  expect_identical(format(file.info(paths[1])$mode), "600")
  write_atomic(paths[2], "shared intentionally", mode = "0640")
  expect_identical(format(file.info(paths[2])$mode), "640")
  writeLines("old", paths[3])
  Sys.chmod(paths[3], "0640", use_umask = FALSE)
  write_atomic(paths[3], "replacement")
  expect_identical(format(file.info(paths[3])$mode), "640")
  expect_identical(readLines(paths[3]), "replacement")
  expect_identical(modes, c("600", "600", "640"))
})

test_that("a fallback permission failure removes only its newly created empty target", {
  skip_on_os("windows")
  dir = withr::local_tempdir()
  path = file.path(dir, "private.txt")
  writer = write_bytes
  writes = 0L
  changed = FALSE
  original = base::Sys.chmod
  local_mocked_bindings(file_rename = function(from, to) FALSE,
                        write_bytes = function(file, bytes) {
                          if (identical(file, path) && length(bytes)) writes <<- writes + 1L
                          writer(file, bytes)
                        })
  local_mocked_bindings(Sys.sleep = function(time) NULL,
                        Sys.chmod = function(paths, mode = "0777", use_umask = TRUE) {
                          if (identical(paths, path)) {
                            if (changed) writeLines("foreign edit", path)
                            return(FALSE)
                          }
                          original(paths, mode, use_umask)
                        }, .package = "base")
  expect_error(write_atomic(path, "private content", expected_md5 = NA_character_),
               class = "gptr_error_doc_write")
  expect_false(file.exists(path))
  expect_identical(writes, 0L)
  changed = TRUE
  expect_error(write_atomic(path, "private content", expected_md5 = NA_character_),
               class = "gptr_error_doc_write")
  expect_identical(readLines(path), "foreign edit")
  expect_identical(writes, 0L)
})

test_that("an absent-target expectation rejects existing files even with an unknown MD5", {
  dir = withr::local_tempdir()
  path = file.path(dir, "occupied.txt")
  writeLines("foreign content", path)
  original = tools::md5sum
  local_mocked_bindings(md5sum = function(files) {
    if (identical(files, path)) return(stats::setNames(NA_character_, path))
    original(files)
  }, .package = "tools")
  expect_error(write_atomic(path, "private replacement", expected_md5 = NA_character_),
               class = "gptr_error_doc_write")
  expect_identical(readLines(path), "foreign content")
})
