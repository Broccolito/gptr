# Actual Windows filesystem witnesses; all paths and subprocesses belong to one test.

wsec_local = function(.env = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if(.Platform$OS.type != "windows", "requires an actual Windows filesystem")
  # testthat's failure formatter initializes diffobj defaults through waldo. Do this
  # before the caller-state snapshot; later assertions must not hide option mutations.
  testthat::expect_failure(testthat::expect_identical(1L, 2L))
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), seed = seed(),
                 names = sort(ls(envir = globalenv(), all.names = TRUE)))
  # Registered first, so this observes restoration after every owned cleanup callback.
  # Boolean assertions never print user option, environment or seed contents on failure.
  withr::defer({
    current = options()
    keys = union(names(current), names(before$options))
    same = function(key) identical(current[[key]], before$options[[key]])
    changed = keys[!vapply(keys, same, NA)]
    label = paste("options restored; changed names:", paste(changed, collapse = ", "))
    testthat::expect_true(identical(current, before$options), info = label)
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

# Read to EOF, independently of link metadata. Every synthetic sentinel is below 1 MiB;
# fail rather than silently truncating if a fixture violates that bound.
wsec_bytes = function(path) {
  con = file(path, "rb")
  on.exit(close(con), add = TRUE)
  bytes = readBin(con, "raw", n = 1024L^2)
  if (length(readBin(con, "raw", n = 1L))) {
    stop("Windows security fixture exceeds its 1 MiB byte-oracle bound", call. = FALSE)
  }
  bytes
}

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
       size = unname(file.size(link)), target_size = unname(file.size(target)),
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
  script = withr::local_tempfile(pattern = "gptr-wsec-unlink-", fileext = ".ps1",
                                 .local_envir = .env)
  writeLines(c("param([string]$Link, [string]$Directory)",
               "$ErrorActionPreference = 'Stop'",
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
  # Read the native reparse tag without PowerShell's Get-Item/module initialization.
  # A junction's mount-point tag (0xa0000003) does not satisfy the symbolic-link oracle.
  query = Sys.which("fsutil.exe")
  if (!nzchar(query)) stop("Windows link inspection requires fsutil.exe", call. = FALSE)
  native = processx::run(query, c("reparsepoint", "query", link),
                         timeout = 5, error_on_status = TRUE, windows_hide_window = TRUE,
                         cleanup_tree = TRUE, env = character())
  tag = regmatches(native$stdout, regexpr("0x[[:xdigit:]]{8}\\b", native$stdout))
  testthat::expect_identical(tolower(tag), "0xa000000c", info = label)
  if (!identical(tolower(tag), "0xa000000c")) {
    stop("Windows link inspection did not confirm a true symbolic link", call. = FALSE)
  }
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

# Start from an exactly representable mtime; fractional file times can lose precision on reset.
wsec_mtime = function(path) {
  time = floor(as.numeric(Sys.time())) - 10
  testthat::expect_true(Sys.setFileTime(path, as.POSIXct(time, origin = "1970-01-01")))
  testthat::expect_identical(wsec_stamp(path)$mtime, time)
  invisible(time)
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


# A real junction is a known MOUNT_POINT reparse entry, never a symbolic-link substitute.
# Only the fresh link is removed; each subprocess has its own unchanged five-second limit.
wsec_junction = function(target, link, .env = parent.frame()) {
  force(target)
  force(link)
  testthat::expect_true(dir.exists(target), info = "junction target is an owned directory")
  if (!dir.exists(target) || basename(link) %in%
      list.files(dirname(link), all.files = TRUE, no.. = TRUE)) {
    stop("Windows junction fixture requires a fresh link and existing target", call. = FALSE)
  }
  system = Sys.getenv("SystemRoot", unset = "")
  shell = file.path(system, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  query = file.path(system, "System32", "fsutil.exe")
  if (!is_abs_path(system) || !file.exists(shell) || !file.exists(query)) {
    stop("Windows junction fixture requires native system utilities", call. = FALSE)
  }
  create = withr::local_tempfile(pattern = "gptr-wsec-junction-", fileext = ".ps1",
                                 .local_envir = .env)
  cleanup = withr::local_tempfile(pattern = "gptr-wsec-unlink-", fileext = ".ps1",
                                  .local_envir = .env)
  writeLines(c("param([string]$Target, [string]$Link)",
    "$ErrorActionPreference = 'Stop'",
    "$null = New-Item -ItemType Junction -Path $Link -Value $Target -ErrorAction Stop"), create)
  writeLines(c("param([string]$Link, [string]$Directory)",
    "$ErrorActionPreference = 'Stop'",
    "[System.IO.Directory]::Delete($Link, $false)"), cleanup)
  # Registered before launch, so a partially completed native creation is still detached.
  withr::defer({
    wsec_unlink(link, TRUE, cleanup)
    testthat::expect_true(dir.exists(target), info = "detaching a junction preserves its target")
  }, envir = .env)
  run = function(exe, args) {
    x = processx::run(exe, args, timeout = 5, error_on_status = FALSE,
      windows_hide_window = TRUE, cleanup_tree = TRUE, env = child_env("helper"))
    if (!identical(x$status, 0L) || nchar(x$stdout, type = "bytes") > 131072L ||
        nchar(x$stderr, type = "bytes") > 131072L) {
      stop("Windows junction utility failed its bounded native proof", call. = FALSE)
    }
    x
  }
  run(shell, c("-NoProfile", "-NonInteractive", "-File", create,
    "-Target", target, "-Link", link))
  native = run(query, c("reparsepoint", "query", link))
  tag = regmatches(native$stdout, regexpr("0x[[:xdigit:]]{8}\\b", native$stdout))
  testthat::expect_identical(tolower(tag), "0xa0000003")
  if (!identical(tolower(tag), "0xa0000003")) {
    stop("Windows junction inspection did not confirm the mount-point tag", call. = FALSE)
  }
  info = wsec_link_info(target, link)
  testthat::expect_true(info$target_exists && info$exists && info$directory)
  info$cleanup_script = cleanup
  invisible(info)
}
