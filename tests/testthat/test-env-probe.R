fake_lib = function(dir, pkg, version, imports = NA_character_, ...) {
  path = file.path(dir, pkg)
  dir.create(file.path(path, "Meta"), recursive = TRUE)
  desc = c(Package = pkg, Version = version, Imports = imports, ...)
  writeLines(sprintf("Package: %s\nVersion: %s\n", pkg, version), file.path(path, "DESCRIPTION"))
  saveRDS(list(DESCRIPTION = desc), file.path(path, "Meta", "package.rds"))
  path
}

test_that("r_env_probe leaves loadedNamespaces() unchanged and is cached", {
  env_probe_cache$text = NULL
  withr::defer({
    env_probe_cache$text = NULL
  })
  loadNamespace("ps")  # an Import of gptr, loaded on first use of ps::
  before = loadedNamespaces()
  txt = r_env_probe()
  expect_setequal(loadedNamespaces(), before)
  expect_type(txt, "character")
  expect_length(txt, 1L)
  expect_match(txt, "^R [0-9]+\\.[0-9]+\\.[0-9]+, ")
  expect_match(txt, "cores \\(use <= [0-9]+ workers\\)")
  expect_identical(r_env_probe(), txt)
  expect_lte(est_tokens(txt, "prose"), 450)
})

test_that("the registry has the 36 steered packages of report 19", {
  reg = env_probe_registry()
  expect_equal(nrow(reg), 36L)
  expect_equal(reg$repo[reg$pkg == "BPCells"], "GitHub")
  expect_equal(reg$repo[reg$pkg == "SingleCellExperiment"], "Bioc")
})

test_that("env_probe_packages reads versions and missing dependencies without loading", {
  lib = withr::local_tempdir()
  fake_lib(lib, "p09fastpkg", "1.2.3-4")
  fake_lib(lib, "p09brokenpkg", "0.9", imports = "p09nothere (>= 1.0), stats")
  reg = data.frame(pkg = c("p09fastpkg", "p09brokenpkg", "p09absent"), cat = c("io", "io", "sc"),
                   repo = c("CRAN", "CRAN", "Bioc"), stringsAsFactors = FALSE)
  caps = env_probe_packages(reg, lib = lib)
  expect_equal(caps$version, c("1.2.3-4", "0.9", NA))
  expect_equal(caps$missing, c(NA, "p09nothere", NA))
  sess = list(r = "4.4.3", platform = "aarch64-apple-darwin20", utf8 = TRUE, cores = 8L,
              workers = 7L, ram_gb = 24)
  expect_equal(strsplit(env_probe_render(caps, sess), "\n", fixed = TRUE)[[1]], c(
    "R 4.4.3, aarch64-apple-darwin20, UTF-8 locale; 8 cores (use <= 7 workers); RAM 24 GB",
    "Installed: io: p09fastpkg 1.2.3",
    paste("Installed but NOT loadable (do not library() them):",
          "p09brokenpkg (missing dependency p09nothere)"),
    "Not installed (ask before installing; Bioc = BiocManager, GitHub = remotes): p09absent[Bioc]"
  ))
})

test_that("R CMD check limits the advertised workers to 2", {
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "TRUE")
  expect_equal(env_probe_session()$workers, 2L)
  deps = env_probe_deps("R (>= 4.2.0), jsonlite,\n  cli (>= 3.6), utils")
  expect_equal(deps, c("jsonlite", "cli"))
})

test_that("_R_CHECK_LIMIT_CORES_=false outside R CMD check does not limit the workers", {
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "false", `_R_CHECK_PACKAGE_NAME_` = NA)
  s = env_probe_session()
  expect_equal(s$workers, if (is.na(s$cores)) 1L else max(1L, as.integer(s$cores) - 1L))
})

test_that("only Depends and Imports make a package not loadable, never LinkingTo", {
  lib = withr::local_tempdir()
  fake_lib(lib, "p09cpppkg", "2.0", LinkingTo = "p09headers, p09moreheaders (>= 1.2)")
  fake_lib(lib, "p09deppkg", "1.0", imports = "p09cpppkg, methods,\n  p09lost (>= 2.0)",
           Depends = "R (>= 4.2.0), p09gone", LinkingTo = "p09headers")
  reg = data.frame(pkg = c("p09cpppkg", "p09deppkg"), cat = c("io", "io"),
                   repo = c("CRAN", "CRAN"), stringsAsFactors = FALSE)
  caps = env_probe_packages(reg, lib = lib)
  expect_equal(caps$version, c("2.0", "1.0"))
  expect_equal(caps$missing, c(NA, "p09gone, p09lost"))
  sess = list(r = "4.4.3", platform = "x86_64-pc-linux-gnu", utf8 = FALSE, cores = NA_integer_,
              workers = 1L, ram_gb = NA_real_)
  expect_equal(strsplit(env_probe_render(caps, sess), "\n", fixed = TRUE)[[1]], c(
    "R 4.4.3, x86_64-pc-linux-gnu, NON-UTF-8 locale; ? cores (use <= 1 workers)",
    "Installed: io: p09cpppkg 2.0",
    paste("Installed but NOT loadable (do not library() them):",
          "p09deppkg (missing dependency p09gone, p09lost)")
  ))
})

test_that("a library directory without Meta/package.rds is not installed, silently", {
  lib = withr::local_tempdir()
  dir.create(file.path(lib, "p09srcpkg"))
  writeLines(c("Package: p09srcpkg", "Version: 1.0"), file.path(lib, "p09srcpkg", "DESCRIPTION"))
  reg = data.frame(pkg = "p09srcpkg", cat = "io", repo = "CRAN", stringsAsFactors = FALSE)
  caps = expect_silent(env_probe_packages(reg, lib = lib))
  expect_identical(caps$version, NA_character_)
  expect_identical(caps$missing, NA_character_)
})

test_that("a loaded namespace is installed at its loaded version, also from a source tree", {
  # Under devtools::test() gptr is loaded from the source tree, which has no Meta/package.rds.
  reg = data.frame(pkg = c("gptr", "ps"), cat = c("io", "io"), repo = c("CRAN", "CRAN"),
                   stringsAsFactors = FALSE)
  loadNamespace("ps")
  caps = expect_silent(env_probe_packages(reg))
  expect_identical(caps$version, c(unname(getNamespaceVersion("gptr")),
                                   unname(getNamespaceVersion("ps"))))
  expect_identical(caps$missing, c(NA_character_, NA_character_))
})

test_that("a dependency without Meta/package.rds is missing; a loaded dependency is found", {
  lib = withr::local_tempdir()
  dir.create(file.path(lib, "p09srcdep"))
  writeLines(c("Package: p09srcdep", "Version: 1.0"), file.path(lib, "p09srcdep", "DESCRIPTION"))
  fake_lib(lib, "p09user", "1.0", imports = "p09srcdep, gptr")
  reg = data.frame(pkg = c("p09user", "p09srcdep"), cat = c("io", "io"), repo = c("CRAN", "CRAN"),
                   stringsAsFactors = FALSE)
  caps = expect_silent(env_probe_packages(reg, lib = lib))
  expect_identical(caps$version, c("1.0", NA))
  expect_identical(caps$missing, c("p09srcdep, gptr", NA))
  # With lib = NULL the loaded gptr counts as found, also when loaded from a source tree.
  withr::local_libpaths(lib, action = "prefix")
  caps = expect_silent(env_probe_packages(reg))
  expect_identical(caps$version, c("1.0", NA))
  expect_identical(caps$missing, c("p09srcdep", NA))
})
