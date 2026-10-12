site_fixture = function() {
  root = tempfile("public-source-")
  dir.create(root, mode = "0700")
  for (dir in c("R", "man", "inst", "vignettes", "pkgdown")) {
    dir.create(file.path(root, dir), mode = "0700")
  }
  dir.create(file.path(root, "inst", "gptr", "agents"), recursive = TRUE, mode = "0700")
  text = c("DESCRIPTION", "NAMESPACE", "README.md", "NEWS.md", "LICENSE", "LICENSE.md",
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
