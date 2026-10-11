# Actual Windows filesystem witnesses; all paths and subprocesses belong to one test.

wsec_local = function(.env = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if(.Platform$OS.type != "windows", "requires an actual Windows filesystem")
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), seed = seed(),
                 names = sort(ls(envir = globalenv(), all.names = TRUE)))
  # Registered first, so this observes restoration after every owned cleanup callback.
  # Boolean assertions never print user option, environment or seed contents on failure.
  withr::defer({
    testthat::expect_true(identical(options(), before$options), info = "options restored")
    testthat::expect_true(identical(Sys.getenv(), before$env), info = "environment restored")
    testthat::expect_true(identical(getwd(), before$cwd), info = "working directory restored")
    testthat::expect_true(identical(seed(), before$seed), info = "RNG unchanged")
    testthat::expect_true(identical(sort(ls(envir = globalenv(), all.names = TRUE)), before$names),
                           info = "no global bindings introduced or removed")
  }, envir = .env)
  old_gateway = the$gateway
  old_settings = the$settings_session
  old_vault = the$vault
  old_secrets = the$secrets
  the$gateway = NULL
  the$settings_session = list()
  vault_reset()
  withr::defer({
    the$gateway = old_gateway
    the$settings_session = old_settings
    the$vault = old_vault
    the$secrets = old_secrets
  }, envir = .env)
  user = withr::local_tempdir("gptr-wsec-user-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = file.path(user, "config"),
                      R_USER_CACHE_DIR = file.path(user, "cache"),
                      R_USER_DATA_DIR = file.path(user, "data"), .local_envir = .env)
  withr::local_options(gptr.quiet = TRUE, .local_envir = .env)
  local_project(.env = .env)
}

wsec_bytes = function(path) readBin(path, "raw", n = file.size(path))

# Register before creating links, so the sentinel is checked after link detachment.
wsec_preserve = function(path, .env = parent.frame()) {
  force(path)
  before = wsec_bytes(path)
  withr::defer({
    testthat::expect_true(file.exists(path), info = "foreign sentinel survives cleanup")
    if (file.exists(path)) testthat::expect_identical(wsec_bytes(path), before)
  }, envir = .env)
  before
}

wsec_link_info = function(target, link) {
  list(target = normalizePath(target, winslash = "/", mustWork = FALSE),
       link = normalizePath(link, winslash = "/", mustWork = FALSE),
       target_exists = file.exists(target), exists = file.exists(link),
       target_directory = dir.exists(target), directory = dir.exists(link),
       readlink = Sys.readlink(link))
}

# R's Windows unlink() can ask for a junction tag when deleting a true symbolic link.
# Delete precisely the link via .NET's nonrecursive native operation before withr teardown.
wsec_unlink = function(link, directory, script) {
  entries = list.files(dirname(link), all.files = TRUE, no.. = TRUE)
  if (!(basename(link) %in% entries)) return(invisible(NULL))
  shell = Sys.which("powershell.exe")
  if (!nzchar(shell)) stop("Windows link cleanup requires powershell.exe", call. = FALSE)
  processx::run(shell, c("-NoProfile", "-NonInteractive", "-File", script,
                        "-Link", link, "-Directory", if (directory) "yes" else "no"),
                timeout = 5, error_on_status = TRUE, windows_hide_window = TRUE,
                cleanup_tree = TRUE, env = character())
  testthat::expect_false(basename(link) %in%
                          list.files(dirname(link), all.files = TRUE, no.. = TRUE))
  invisible(NULL)
}

wsec_link = function(target, link, .env = parent.frame()) {
  force(target)
  force(link)
  directory = dir.exists(target)
  script = withr::local_tempfile("gptr-wsec-unlink-", fileext = ".ps1", .local_envir = .env)
  writeLines(c("param([string]$Link, [string]$Directory, [string]$Action = 'remove')",
               "$ErrorActionPreference = 'Stop'",
               "if ($Action -eq 'inspect') {",
               "  $item = Get-Item -LiteralPath $Link -Force",
               "  if ($item.LinkType -cne 'SymbolicLink') { throw 'Not a true symbolic link' }",
               "  Write-Output $item.LinkType; exit 0",
               "}",
               "if ($Directory -eq 'yes') { [System.IO.Directory]::Delete($Link, $false) }",
               "else { [System.IO.File]::Delete($Link) }"), script)
  ok = file.symlink(target, link)
  if (isTRUE(ok)) {
    withr::defer({
      wsec_unlink(link, directory, script)
      testthat::expect_true(file.exists(target), info = "detaching a link preserves its target")
    }, envir = .env)
  }
  testthat::expect_true(isTRUE(ok), info = "actual Windows CreateSymbolicLink must succeed")
  if (!isTRUE(ok)) stop("Windows symbolic-link creation failed", call. = FALSE)
  info = wsec_link_info(target, link)
  label = paste(utils::capture.output(dput(info)), collapse = " ")
  testthat::expect_true(info$target_exists, info = label)
  testthat::expect_true(info$exists, info = label)
  testthat::expect_identical(info$directory, directory, info = label)
  shell = Sys.which("powershell.exe")
  if (!nzchar(shell)) stop("Windows link inspection requires powershell.exe", call. = FALSE)
  native = processx::run(shell, c("-NoProfile", "-NonInteractive", "-File", script,
                                  "-Link", link, "-Action", "inspect"),
                         timeout = 5, error_on_status = TRUE, windows_hide_window = TRUE,
                         cleanup_tree = TRUE, env = character())
  testthat::expect_identical(trimws(native$stdout), "SymbolicLink", info = label)
  if (!directory) {
    testthat::expect_identical(wsec_bytes(link), wsec_bytes(target), info = label)
  }
  info$cleanup_script = script
  invisible(info)
}

wsec_stamp = function(path) {
  info = file.info(path, extra_cols = FALSE)
  list(size = unname(info$size), mtime = as.numeric(info$mtime), ctime = as.numeric(info$ctime))
}

wsec_rewrite = function(path, text) {
  before = wsec_stamp(path)
  bytes = wsec_bytes(path)
  writeLines(text, path, useBytes = TRUE)
  testthat::expect_true(Sys.setFileTime(path, as.POSIXct(before$mtime, origin = "1970-01-01")))
  testthat::expect_identical(wsec_stamp(path), before,
                             info = "Windows creation time, restored mtime and size are unchanged")
  testthat::expect_false(identical(wsec_bytes(path), bytes),
                          info = "file contents actually changed")
  invisible(before)
}
