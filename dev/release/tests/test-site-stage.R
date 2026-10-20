site_fixture = function() {
  root = tempfile("public-source-")
  dir.create(root, mode = "0700")
  for (dir in c("R", "man", "inst", "vignettes", "pkgdown")) {
    dir.create(file.path(root, dir), mode = "0700")
  }
  dir.create(file.path(root, "inst", "gptr", "agents"), recursive = TRUE, mode = "0700")
  text = c("DESCRIPTION", "NAMESPACE", "README.md", "NEWS.md", "LICENSE.md",
           "_pkgdown.yml", "R/public.R", "man/public.Rd", "inst/public.txt",
           "vignettes/public.Rmd", "pkgdown/extra.css", "inst/gptr/agents/reviewer.md")
  for (path in text) writeLines(paste("public bytes", path), file.path(root, path))
  writeBin(as.raw(c(0, 255, 10, 13, 128)), file.path(root, "pkgdown", "logo.bin"))
  private = c("dev", ".git", ".github", ".secrets", "inst/.secrets", "vignettes/dev")
  for (dir in private) dir.create(file.path(root, dir), mode = "0700")
  poison = c("AGENTS.md", "CLAUDE.md", "unexpected.md", "dev/notes.md", ".git/config",
             ".github/notes.md", ".secrets/key.env", "inst/.secrets/key.env",
             "vignettes/dev/notes.md", "vignettes/CLAUDE.md", "pkgdown/AGENTS.md")
  for (path in poison) writeLines("fixture-only private sentinel", file.path(root, path))
  list(root = normalizePath(root, winslash = "/"), public = c(text, "pkgdown/logo.bin"))
}

site_fixture_hashes = function(root) {
  files = list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  tools::md5sum(files)
}

# Writes the owned child proof at the fixed transport path; no renderer is executed.
site_mock_report = function(project, warnings = 0L, version = "3.10") {
  scripts = file.path(dirname(project), "scripts")
  executable = file.path(scripts, if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc")
  writeLines("fixture-only executable bytes", executable)
  saveRDS(list(status = 0L, warnings = warnings,
               pandoc = list(version = version, directory = normalizePath(scripts, winslash = "/"),
                             executable = normalizePath(executable, winslash = "/"),
                             md5 = unname(tools::md5sum(executable)))),
          file.path(scripts, "site-result.rds"))
}

site_renderer_fixture = function() {
  directory = tempfile("site-pandoc-")
  dir.create(directory, mode = "0700")
  executable = file.path(directory, if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc")
  writeLines("fixture-only renderer bytes", executable)
  Sys.chmod(executable, "0700")
  directory = normalizePath(directory, winslash = "/")
  list(directory = directory, executable = normalizePath(executable, winslash = "/"),
       proof = file.path(directory, "result.rds"))
}

test_that("site staging copies exact public bytes and leaves private source files untouched", {
  src = site_fixture()
  dest = tempfile("public-stage-")
  withr::defer(unlink(c(src$root, dest), recursive = TRUE))
  before = site_fixture_hashes(src$root)
  expect_identical(site_stage(src$root, dest), normalizePath(dest, winslash = "/"))
  expect_setequal(list.files(dest, recursive = TRUE, all.files = TRUE, no.. = TRUE), src$public)
  source = unname(tools::md5sum(file.path(src$root, src$public)))
  staged = unname(tools::md5sum(file.path(dest, src$public)))
  expect_identical(staged, source)
  expect_identical(site_fixture_hashes(src$root), before)
  expect_false(file.exists(file.path(dest, "CLAUDE.md")))
  expect_false(dir.exists(file.path(dest, ".secrets")))
  expect_identical(readBin(file.path(dest, "pkgdown", "logo.bin"), "raw", 5L),
                   as.raw(c(0, 255, 10, 13, 128)))
})

test_that("site staging refuses existing destinations without changing either tree", {
  src = site_fixture()
  dest = tempfile("occupied-stage-")
  dir.create(dest)
  writeLines("owned destination sentinel", file.path(dest, "keep.txt"))
  withr::defer(unlink(c(src$root, dest), recursive = TRUE))
  before = site_fixture_hashes(src$root)
  occupied = site_fixture_hashes(dest)
  expect_error(site_stage(src$root, dest), "must be fresh", fixed = TRUE)
  expect_identical(site_fixture_hashes(dest), occupied)
  expect_identical(site_fixture_hashes(src$root), before)
  unlink(file.path(dest, "keep.txt"))
  expect_error(site_stage(src$root, dest), "must be fresh", fixed = TRUE)
  expect_true(dir.exists(dest))
})

test_that("site staging refuses an incomplete whitelist and destinations inside the source", {
  src = site_fixture()
  dest = tempfile("incomplete-stage-")
  withr::defer(unlink(c(src$root, dest), recursive = TRUE))
  unlink(file.path(src$root, "NAMESPACE"))
  before = site_fixture_hashes(src$root)
  expect_error(site_stage(src$root, dest), "missing required public input", fixed = TRUE)
  expect_false(file.exists(dest))
  expect_error(site_stage(src$root, file.path(src$root, "stage")),
               "outside the source", fixed = TRUE)
  expect_identical(site_fixture_hashes(src$root), before)
})

test_that("site staging refuses an aliased public entry before creating its destination", {
  src = site_fixture()
  dest = tempfile("aliased-stage-")
  withr::defer(unlink(c(src$root, dest), recursive = TRUE))
  target = file.path(src$root, "R", "public.R")
  real_readlink = Sys.readlink
  stage = site_stage
  scope = new.env(parent = environment(stage))
  scope$Sys.readlink = function(paths) {
    out = real_readlink(paths)
    out[paths == target] = "fixture-only foreign target"
    out
  }
  environment(stage) = scope
  before = site_fixture_hashes(src$root)
  expect_error(stage(src$root, dest), "aliased public input", fixed = TRUE)
  expect_false(file.exists(dest))
  expect_identical(site_fixture_hashes(src$root), before)
})


test_that("site staging refuses canonical aliases when readlink has no link target", {
  src = site_fixture()
  dest = tempfile("canonical-stage-")
  withr::defer(unlink(c(src$root, dest), recursive = TRUE))
  target = file.path(src$root, "R", "public.R")
  real_normalize = normalizePath
  stage = site_stage
  scope = new.env(parent = environment(stage))
  scope$normalizePath = function(path, ...) {
    out = real_normalize(path, ...)
    if (identical(path, target)) paste0(out, "-foreign") else out
  }
  scope$Sys.readlink = function(path) ""
  environment(stage) = scope
  before = site_fixture_hashes(src$root)
  expect_error(stage(src$root, dest), "aliased public input", fixed = TRUE)
  expect_false(file.exists(dest))
  expect_identical(site_fixture_hashes(src$root), before)
})


test_that("site building uses the public stage and keeps its child bounds", {
  src = site_fixture()
  dest = tempfile("public-site-")
  call = new.env(parent = emptyenv())
  call$proj = NULL
  withr::defer({
    unlink(c(src$root, dest), recursive = TRUE)
    if (!is.null(call$proj)) unlink(dirname(call$proj), recursive = TRUE)
  })
  local_mocked_bindings(run = function(command, args, env, error_on_status, timeout) {
    call$command = command
    call$args = args
    call$proj = unname(env[["GPTR_PROJECT_ROOT"]])
    call$error_on_status = error_on_status
    call$timeout = timeout
    site_mock_report(call$proj)
    list(status = 0L, stdout = "", stderr = "")
  }, .package = "processx")
  before = site_fixture_hashes(src$root)
  expect_identical(site_build(src$root, dest), character())
  stage = file.path(call$proj, "source")
  expect_setequal(list.files(stage, recursive = TRUE, all.files = TRUE, no.. = TRUE), src$public)
  expect_identical(site_fixture_hashes(src$root), before)
  expect_true(grepl(deparse(stage), call$args[3L], fixed = TRUE))
  expect_true(grepl(deparse(dest), call$args[3L], fixed = TRUE))
  expect_identical(call$args[1:2], c("--vanilla", "-e"))
  expect_identical(call$timeout, 1800)
  expect_identical(call$error_on_status, FALSE)
})

test_that("site building refuses its original root alias before launching a child", {
  src = site_fixture()
  owned = tempfile("alias-build-")
  dest = tempfile("alias-output-")
  withr::defer(unlink(c(src$root, owned, dest), recursive = TRUE))
  caller_root = file.path(src$root, ".")
  real_readlink = Sys.readlink
  real_dirs = rel_dirs
  scope = new.env(parent = environment(site_stage))
  scope$Sys.readlink = function(path) {
    out = real_readlink(path)
    out[path == caller_root] = "fixture-only root alias"
    out
  }
  scope$rel_dirs = function(work) real_dirs(owned)
  stage = site_stage
  environment(stage) = scope
  scope$site_stage = stage
  build = site_build
  environment(build) = scope
  call = new.env(parent = emptyenv())
  call$launched = FALSE
  local_mocked_bindings(run = function(...) {
    call$launched = TRUE
    list(status = 0L, stdout = "", stderr = "")
  }, .package = "processx")
  before = site_fixture_hashes(src$root)
  expect_error(build(caller_root, dest), "aliased public input", fixed = TRUE)
  expect_identical(call$launched, FALSE)
  expect_false(dir.exists(file.path(owned, "proj", "source")))
  expect_identical(site_fixture_hashes(src$root), before)
})

test_that("site render selects and rereads compatible Pandoc through public child APIs", {
  fixture = site_renderer_fixture()
  withr::defer(unlink(fixture$directory, recursive = TRUE))
  seen = new.env(parent = emptyenv())
  seen$calls = list()
  local_mocked_bindings(find_pandoc = function(cache = TRUE, dir = NULL, version = NULL) {
    seen$calls[[length(seen$calls) + 1L]] = list(cache = cache, dir = dir, version = version)
    list(dir = fixture$directory, version = numeric_version("3.10"))
  }, .package = "rmarkdown")
  local_mocked_bindings(build_site = function(pkg, preview, new_process, override) {
    seen$build = list(pkg, preview, new_process, override)
  }, .package = "pkgdown")
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths())
  site_render("owned-stage", "owned-destination", fixture$directory, fixture$proof)
  expect_identical(seen$calls[[1L]], list(cache = FALSE, dir = fixture$directory, version = "3.10"))
  expect_identical(seen$calls[[2L]], list(cache = TRUE, dir = NULL, version = NULL))
  expect_identical(seen$build, list("owned-stage", FALSE, FALSE,
                                  list(destination = "owned-destination")))
  report = readRDS(fixture$proof)
  expect_identical(report$status, 0L)
  expect_identical(report$warnings, 0L)
  expect_identical(report$pandoc$executable, fixture$executable)
  expect_identical(report$pandoc$md5, unname(tools::md5sum(fixture$executable)))
  expect_identical(list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths()),
                   before)
})

test_that("site render rejects unavailable incompatible or changed renderer identity", {
  fixture = site_renderer_fixture()
  withr::defer(unlink(fixture$directory, recursive = TRUE))
  seen = new.env(parent = emptyenv())
  seen$builds = 0L
  seen$version = "3.12"
  seen$directory = fixture$directory
  local_mocked_bindings(find_pandoc = function(...) {
    list(dir = seen$directory, version = numeric_version(seen$version))
  }, .package = "rmarkdown")
  local_mocked_bindings(build_site = function(...) {
    seen$builds = seen$builds + 1L
    writeLines("changed renderer bytes", fixture$executable)
  }, .package = "pkgdown")
  expect_error(site_render("stage", "dest", NULL, fixture$proof), "Pandoc 3.10", fixed = TRUE)
  expect_identical(seen$builds, 0L)
  seen$version = "3.10"
  seen$directory = file.path(fixture$directory, "absent")
  expect_error(site_render("stage", "dest", NULL, fixture$proof))
  expect_identical(seen$builds, 0L)
  seen$directory = fixture$directory
  expect_error(site_render("stage", "dest", fixture$directory, fixture$proof),
               "renderer changed", fixed = TRUE)
  expect_identical(seen$builds, 1L)
  expect_identical(readRDS(fixture$proof)$status, 1L)
})

test_that("site render rejects a different cached directory after rendering", {
  fixture = site_renderer_fixture()
  other = site_renderer_fixture()
  withr::defer(unlink(c(fixture$directory, other$directory), recursive = TRUE))
  local_mocked_bindings(find_pandoc = function(cache = TRUE, ...) {
    list(dir = if (cache) other$directory else fixture$directory,
         version = numeric_version("3.10"))
  }, .package = "rmarkdown")
  local_mocked_bindings(build_site = function(...) invisible(NULL), .package = "pkgdown")
  expect_error(site_render("stage", "dest", fixture$directory, fixture$proof),
               "renderer changed", fixed = TRUE)
  expect_identical(readRDS(fixture$proof)$status, 1L)
})

test_that("site render counts unmuffled setup render and publication warnings", {
  fixture = site_renderer_fixture()
  withr::defer(unlink(fixture$directory, recursive = TRUE))
  seen = new.env(parent = emptyenv())
  seen$phase = "setup"
  real_save = saveRDS
  local_mocked_bindings(find_pandoc = function(cache = TRUE, ...) {
    if (!cache && seen$phase == "setup") warning("fixture R warning", call. = FALSE)
    list(dir = fixture$directory, version = numeric_version("3.10"))
  }, .package = "rmarkdown")
  local_mocked_bindings(build_site = function(...) {
    if (seen$phase == "render") warning("fixture R warning", call. = FALSE)
  }, .package = "pkgdown")
  scope = new.env(parent = environment(site_render))
  scope$saveRDS = function(object, file) {
    if (seen$phase == "publication") warning("fixture R warning", call. = FALSE)
    real_save(object, file)
  }
  render = site_render
  environment(render) = scope
  for (phase in c("setup", "render", "publication")) {
    seen$phase = phase
    expect_warning(expect_error(render("stage", "dest", NULL, fixture$proof),
                                "emitted R warnings", fixed = TRUE),
                   "fixture R warning", fixed = TRUE)
  }
})

test_that("site render preserves original errors and interrupts if proof publication fails", {
  fixture = site_renderer_fixture()
  withr::defer(unlink(fixture$directory, recursive = TRUE))
  original = simpleError("original render failure")
  local_mocked_bindings(find_pandoc = function(...) {
    list(dir = fixture$directory, version = numeric_version("3.10"))
  }, .package = "rmarkdown")
  local_mocked_bindings(build_site = function(...) stop(original), .package = "pkgdown")
  scope = new.env(parent = environment(site_render))
  scope$saveRDS = function(...) stop("failed fixture publication")
  render = site_render
  environment(render) = scope
  caught = tryCatch(render("stage", "dest", NULL, fixture$proof), error = function(e) e)
  expect_identical(caught, original)
  original = structure(list(message = "original interrupt", call = NULL),
                       class = c("interrupt", "condition"))
  caught = tryCatch(render("stage", "dest", NULL, fixture$proof), interrupt = function(e) e)
  expect_identical(caught, original)
})

test_that("site building preserves raw streams and rejects zero-status native warnings", {
  src = site_fixture()
  scope = new.env(parent = environment(site_build))
  real_dirs = rel_dirs
  seen = new.env(parent = emptyenv())
  seen$dirs = character()
  seen$status = 0L
  seen$text = "[WARNING] Deprecated: --mathml"
  scope$rel_dirs = function(work) {
    seen$dirs = c(seen$dirs, work)
    real_dirs(work)
  }
  build = site_build
  environment(build) = scope
  withr::defer(unlink(c(src$root, seen$dirs), recursive = TRUE))
  local_mocked_bindings(run = function(command, args, env, ...) {
    site_mock_report(unname(env[["GPTR_PROJECT_ROOT"]]))
    list(status = seen$status, stdout = paste0(seen$text, "\n"), stderr = "")
  }, .package = "processx")
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths())
  output = capture.output({
    seen$problems = build(src$root, tempfile("site-"))
  })
  expect_true(any(grepl(seen$text, output, fixed = TRUE)))
  expect_match(seen$problems, "native warnings", fixed = TRUE)
  seen$status = 1L
  seen$text = "ordinary failed render status"
  output = capture.output({
    seen$problems = build(src$root, tempfile("site-"))
  })
  expect_true(any(grepl(seen$text, output, fixed = TRUE)))
  expect_match(seen$problems, "failed", fixed = TRUE)
  expect_identical(list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths()),
                   before)
})

test_that("site building requires complete unchanged compatible child proof", {
  src = site_fixture()
  scope = new.env(parent = environment(site_build))
  real_dirs = rel_dirs
  seen = new.env(parent = emptyenv())
  seen$dirs = character()
  seen$mode = "absent"
  scope$rel_dirs = function(work) {
    seen$dirs = c(seen$dirs, work)
    real_dirs(work)
  }
  build = site_build
  environment(build) = scope
  withr::defer(unlink(c(src$root, seen$dirs), recursive = TRUE))
  local_mocked_bindings(run = function(command, args, env, ...) {
    project = unname(env[["GPTR_PROJECT_ROOT"]])
    if (seen$mode != "absent") site_mock_report(project,
                                                warnings = as.integer(seen$mode == "warning"),
                                                version = if (seen$mode == "version") {
                                                  "3.12"
                                                } else {
                                                  "3.10"
                                                })
    if (seen$mode == "changed") {
      writeLines("replacement renderer", file.path(dirname(project), "scripts",
                                                if (.Platform$OS.type == "windows") {
                                                  "pandoc.exe"
                                                } else {
                                                  "pandoc"
                                                }))
    }
    list(status = 0L, stdout = "", stderr = "")
  }, .package = "processx")
  for (mode in c("absent", "warning", "version", "changed")) {
    seen$mode = mode
    expect_match(build(src$root, tempfile("site-")), "child proof", fixed = TRUE)
  }
})

test_that("site CLI keeps destination defaults and accepts only one explicit Pandoc directory", {
  expect_identical(site_build_args(character(), "default"), list(dest = "default", pandoc = NULL))
  expect_identical(site_build_args("site", "default"), list(dest = "site", pandoc = NULL))
  expect_identical(site_build_args(c("site", "--pandoc", "tools"), "default"),
                   list(dest = "site", pandoc = "tools"))
  expect_identical(site_build_args(c("--pandoc", "tools"), "default"),
                   list(dest = "default", pandoc = "tools"))
  for (args in list(c("--pandoc"), c("--pandoc", "a", "--pandoc", "b"),
                   c("a", "b"), c("--unknown"), c("--pandoc", ""))) {
    expect_error(site_build_args(args, "default"), "Usage", fixed = TRUE)
  }
  seen = new.env(parent = baseenv())
  seen$source = function(...) invisible(NULL)
  seen$commandArgs = function(...) c("owned-site", "--pandoc", "owned-tools")
  seen$site_build_args = site_build_args
  seen$site_build = function(root, dest, pandoc) {
    seen$called = list(root, dest, pandoc)
    character()
  }
  seen$rel_finish = function(label, problems) {
    seen$finished = list(label, problems)
  }
  capture.output(sys.source(file.path("..", "build-site.R"), envir = seen))
  expect_identical(seen$called, list(".", "owned-site", "owned-tools"))
  expect_identical(seen$finished, list("build-site", character()))
})
