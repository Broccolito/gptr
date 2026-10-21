# Prepared native stdlib capability cases; execution/CI registration remain pending.
bp_disk_test_state = function(.env = parent.frame()) {
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), seed = seed(),
    kind = RNGkind(), libs = .libPaths(),
    names = sort(ls(envir = globalenv(), all.names = TRUE)))
  withr::defer({
    expect_identical(options(), before$options)
    expect_identical(Sys.getenv(), before$env)
    expect_identical(getwd(), before$cwd)
    expect_identical(seed(), before$seed)
    expect_identical(RNGkind(), before$kind)
    expect_identical(.libPaths(), before$libs)
    expect_identical(sort(ls(envir = globalenv(), all.names = TRUE)), before$names)
  }, envir = .env)
}

bp_disk_test_detach = function(link, directory, .env = parent.frame()) {
  script = withr::local_tempfile(pattern = "observer-detach-", fileext = ".ps1",
    .local_envir = .env)
  writeLines(c("param([string]$Link, [string]$Directory)", "$ErrorActionPreference = 'Stop'",
    "if ($Directory -eq 'yes') { [System.IO.Directory]::Delete($Link, $false) }",
    "else { [System.IO.File]::Delete($Link) }"), script)
  withr::defer({
    if (.Platform$OS.type == "windows") {
      wsec_unlink(link, directory, script)
    } else {
      expect_identical(unlink(link, recursive = FALSE), 0L)
    }
    expect_false(basename(link) %in% list.files(dirname(link), all.files = TRUE, no.. = TRUE))
  }, envir = .env)
}

bp_disk_test_main = function() {
  bp_disk_preserve(function() {
    bp_disk_env_preflight(Sys.getenv(),
      initialized = reticulate::py_available(initialize = FALSE))
    builtins = reticulate::import_builtins(convert = FALSE)
    main = builtins$vars(reticulate::import_main(convert = FALSE))
    keys = unlist(reticulate::py_to_r(builtins$list(main$keys())), use.names = FALSE)
    if (!is.character(keys) || anyNA(keys) || anyDuplicated(keys) || length(keys) > 4096L) {
      stop("Synthetic main namespace exceeds its fixed bound")
    }
    keys = sort(keys)
    identities = vapply(keys, function(key) {
      reticulate::py_to_r(builtins$str(builtins$id(main[[key]])))
    }, character(1))
    list(keys = keys, identities = identities)
  })
}

bp_disk_test_python = function() {
  skip_if(!length(find.package("reticulate", quiet = TRUE)), "{reticulate} is not installed")
  skip_if(!nzchar(Sys.getenv("RETICULATE_PYTHON")),
    "optional observer has no explicit provisioned Python")
  skip_if(!nzchar(Sys.getenv("RETICULATE_USE_MANAGED_VENV")),
    "optional observer has no explicit managed-provisioning policy")
  # A configured invalid executable, identity or policy must reach the wrapper
  # and fail. Availability guards cannot convert configured errors into skips.
}

test_that("the optional observer initializes privately and restores wrapper failures", {
  skip_on_cran()
  bp_disk_test_python()
  bp_disk_test_state()
  root = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  source = withr::local_tempfile(fileext = ".py")
  # The new alias is deliberately absent from __main__; class defaults and
  # methods must resolve it from the same private execution dictionary.
  before = bp_disk_test_main()
  expect_false("GPTR_PRIVATE_PATH" %in% before$keys)
  writeLines(c("from os import path as GPTR_PRIVATE_PATH", "class DiskObserver:",
    "    def __init__(self, root, declarations=(), selected=GPTR_PRIVATE_PATH.basename):",
    "        self.name = selected(root)", "    def snapshot(self, *, declared_only=False):",
    "        if declared_only: raise RuntimeError('synthetic-private-declared-mode')",
    "        return dict(entries=0, directories=1, declared_links=0, disappeared=0,",
    "                    bytes=len(self.name)*0, max_depth=0, elapsed_s=0)"), source)
  observe = bp_disk_observer(root, source = source)
  expect_identical(as.numeric(observe()$bytes), 0)
  declared = bp_disk_observer(root,
    list(list(entry = "dangling-file", target = "missing-target")), source = source,
    declared_only = TRUE)
  expect_error(declared(), "synthetic-private-declared-mode")
  expect_identical(bp_disk_test_main(), before)
  writeLines(c("from os import path as GPTR_PRIVATE_PATH", "class DiskObserver:",
    "    def __init__(self, root, declarations=(), selected=GPTR_PRIVATE_PATH.basename):",
    "        raise RuntimeError('synthetic-private-init-error')"), source)
  expect_error(bp_disk_observer(root, source = source), "synthetic-private-init-error")
  expect_identical(bp_disk_test_main(), before)
  writeLines(c("from os import path as GPTR_PRIVATE_PATH", "class DiskObserver:",
    "    def __init__(self, root, declarations=(), selected=GPTR_PRIVATE_PATH.basename):",
    "        self.name = selected(root)", "    def snapshot(self, *, declared_only=False):",
    "        raise RuntimeError('synthetic-private-snapshot-error')"), source)
  failure = bp_disk_observer(root, source = source)
  expect_error(failure(), "synthetic-private-snapshot-error")
  expect_identical(bp_disk_test_main(), before)
})

test_that("the optional observer charges a real dangling link without following its target", {
  skip_on_cran()
  bp_disk_test_python()
  bp_disk_test_state()
  root = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  target = file.path(root, "missing-target")
  link = file.path(root, "dangling-file")
  writeBin(charToRaw("seven!!"), target)
  bp_disk_test_detach(link, FALSE)
  expect_true(isTRUE(file.symlink(target, link)))
  expect_identical(wsec_bytes(link), charToRaw("seven!!"))
  if (.Platform$OS.type == "windows") {
    native = processx::run(Sys.which("fsutil.exe"), c("reparsepoint", "query", link),
      timeout = 5, error_on_status = TRUE, windows_hide_window = TRUE,
      cleanup_tree = TRUE, env = character())
    tag = regmatches(native$stdout, regexpr("0x[[:xdigit:]]{8}\\b", native$stdout))
    expect_identical(tolower(tag), "0xa000000c")
  }
  expect_true(file.remove(target))
  observe = bp_disk_observer(root,
    list(list(entry = "dangling-file", target = "missing-target")))
  sample = observe()
  expect_identical(as.integer(sample$declared_links), 1L)
  expect_identical(as.numeric(sample$bytes), 16384)
  expect_false(file.exists(target))
  expect_true("dangling-file" %in% list.files(root, all.files = TRUE, no.. = TRUE))
})

test_that("the optional observer refuses a real foreign directory link and preserves its canary", {
  skip_on_cran()
  bp_disk_test_python()
  bp_disk_test_state()
  base = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  root = file.path(base, "owned")
  foreign = file.path(base, "foreign")
  expect_true(dir.create(root))
  expect_true(dir.create(foreign))
  canary = file.path(foreign, "canary")
  writeBin(charToRaw("FOREIGN-CANARY"), canary)
  withr::defer(expect_identical(wsec_bytes(canary), charToRaw("FOREIGN-CANARY")))
  link = file.path(root, "foreign-alias")
  bp_disk_test_detach(link, TRUE)
  expect_true(isTRUE(file.symlink(foreign, link)))
  expect_error(bp_disk_observer(link), "observer-root-not-direct-directory")
  observe = bp_disk_observer(root)
  expect_error(observe(), "observer-undeclared-reparse-entry")
  expect_identical(wsec_bytes(canary), charToRaw("FOREIGN-CANARY"))
  # The constructor must also reject an ordinary descendant whose parent is an
  # alias; lexical root validation cannot silently resolve that parent.
  expect_error(bp_disk_observer(file.path(link, "missing-child")), "parent-not-direct-directory")
})

test_that("the optional observer restores caller state after initialization and errors", {
  skip_on_cran()
  bp_disk_test_python()
  bp_disk_test_state()
  value = list(numbers = c(3L, 4L))
  bytes = serialize(value, NULL)
  prior = options()
  failure = tryCatch(bp_disk_preserve(function() {
    options(gptr_observer_fixture = TRUE)
    Sys.setenv(GPTR_OBSERVER_FIXTURE = "synthetic")
    setwd(tempdir())
    RNGkind("L'Ecuyer-CMRG")
    stats::runif(2)
    stop("synthetic-observer-error")
  }), error = identity)
  expect_s3_class(failure, "error")
  expect_match(conditionMessage(failure), "synthetic-observer-error", fixed = TRUE)
  expect_identical(options(), prior)
  expect_identical(serialize(value, NULL), bytes)
  root = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  observe = bp_disk_observer(root)
  expect_identical(as.numeric(observe()$bytes), 0)
})

test_that("the optional observer refuses a root replaced by a foreign directory link", {
  skip_on_cran()
  bp_disk_test_python()
  bp_disk_test_state()
  base = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  root = file.path(base, "owned")
  saved = file.path(base, "saved-owned")
  foreign = file.path(base, "foreign")
  expect_true(dir.create(root))
  expect_true(dir.create(foreign))
  canary = file.path(foreign, "canary")
  writeBin(charToRaw("ROOT-FOREIGN-CANARY"), canary)
  observe = bp_disk_observer(root)
  first = observe()
  expect_identical(as.numeric(first$bytes), 0)
  expect_true(first$entries > 0 && first$entries <= 4096)
  expect_true(first$elapsed_s >= 0 && first$elapsed_s < 1)
  expect_true(file.rename(root, saved))
  withr::defer({
    expect_true(file.rename(saved, root))
    expect_identical(wsec_bytes(canary), charToRaw("ROOT-FOREIGN-CANARY"))
  })
  bp_disk_test_detach(root, TRUE)
  expect_true(isTRUE(file.symlink(foreign, root)))
  expect_error(observe(), "observer-directory-identity-changed")
  expect_identical(wsec_bytes(canary), charToRaw("ROOT-FOREIGN-CANARY"))
})

test_that("the optional observer preserves unchanged empty environment entries and rejects loss", {
  skip_on_cran()
  state = new.env(parent = emptyenv())
  original = c(EMPTY = "", VALUE = "original")
  expect_silent(bp_disk_env_preflight(original, windows = TRUE))
  expect_silent(bp_disk_env_preflight(original[["VALUE"]], windows = TRUE))
  expect_silent(bp_disk_env_preflight(original, windows = FALSE))
  keys = c("PATH", "VIRTUAL_ENV", "R_SESSION_INITIALIZED", "LD_LIBRARY_PATH",
    "PYTHONPATH", "PYTHONIOENCODING")
  for (key in keys) {
    unsafe = c(original, stats::setNames("", key))
    expect_error(bp_disk_env_preflight(unsafe, windows = TRUE), "actual-empty")
    expect_silent(bp_disk_env_preflight(unsafe, windows = TRUE, initialized = TRUE))
    expect_silent(bp_disk_env_preflight(unsafe, windows = FALSE))
    alias = c(original, stats::setNames("", tolower(key)))
    expect_error(bp_disk_env_preflight(alias, windows = TRUE), "actual-empty")
    safe = c(original, stats::setNames("synthetic", key))
    expect_silent(bp_disk_env_preflight(safe, windows = TRUE))
  }
  expect_identical(original, c(EMPTY = "", VALUE = "original"))
  state$values = c(EMPTY = "", VALUE = "changed", ADDED = "synthetic")
  state$set = character()
  get = function() state$values
  set = function(values) {
    state$set = c(state$set, names(values))
    state$values[names(values)] = values
  }
  unset = function(names) {
    state$values = state$values[!names(state$values) %in% names]
  }
  bp_disk_env_restore(original, get, set, unset, windows = TRUE)
  expect_identical(state$values, original)
  expect_identical(state$set, "VALUE")
  state$values = c(VALUE = "original")
  expect_error(bp_disk_env_restore(original, get, set, unset, windows = TRUE),
    "cannot exactly restore")
  expect_false("EMPTY" %in% names(state$values))
  state$values = c(EMPTY = "changed", VALUE = "original")
  expect_error(bp_disk_env_restore(original, get, set, unset, windows = TRUE),
    "cannot exactly restore")
  expect_identical(state$values[["EMPTY"]], "changed")
  expect_identical(original, c(EMPTY = "", VALUE = "original"))
})

test_that("the optional observer restores changed and missing POSIX empty environment entries", {
  original = c(EMPTY = "", VALUE = "original")
  state = new.env(parent = emptyenv())
  get = function() state$values
  set = function(values) {
    state$set = c(state$set, names(values))
    state$values[names(values)] = values
  }
  unset = function(keys) {
    state$values = state$values[!names(state$values) %in% keys]
  }
  for (missing in c(FALSE, TRUE)) {
    state$values = if (missing) {
      c(VALUE = "original", ADDED = "synthetic")
    } else {
      c(EMPTY = "changed", VALUE = "original", ADDED = "synthetic")
    }
    state$set = character()
    expect_silent(bp_disk_env_restore(original, get, set, unset, windows = FALSE))
    expect_identical(state$values[sort(names(state$values))], original[sort(names(original))])
    expect_identical(state$values[["EMPTY"]], "")
    expect_identical(state$set, "EMPTY")
    expect_false("ADDED" %in% names(state$values))
  }
  expect_identical(original, c(EMPTY = "", VALUE = "original"))
})


test_that("the optional observer restores library paths after success and failure", {
  bp_disk_test_state()
  prior = .libPaths()
  owned = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  bytes = serialize(list(public = c(3L, 4L)), NULL)
  for (failing in c(FALSE, TRUE)) {
    state = new.env(parent = emptyenv())
    state$entered = FALSE
    original = simpleError("synthetic-library-path-error")
    result = tryCatch(bp_disk_preserve(function() {
      .libPaths(c(owned, prior))
      state$entered = identical(.libPaths()[[1L]], normalizePath(owned, winslash = "/"))
      if (failing) stop(original)
      list(public = c(3L, 4L))
    }), error = identity)
    expect_true(state$entered)
    expect_identical(.libPaths(), prior)
    if (failing) {
      expect_identical(result, original)
    } else {
      expect_identical(serialize(result, NULL), bytes)
    }
  }
})

test_that("the optional observer charges a real Windows delete-pending file until it closes", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires an actual Windows delete-pending file")
  bp_disk_test_python()
  bp_disk_test_state()
  root = withr::local_tempdir(tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  writeBin(charToRaw("seven!!"), file.path(root, "data"))
  writeBin(as.raw(rep(42L, 180L)), file.path(root, "marker.json"))
  observe = bp_disk_observer(root)
  scope = environment(observe)
  # FileDispositionInfo is the classic disposition, not the POSIX one DeleteFileW may use: the
  # name stays listed but unopenable until this, its last handle, closes.
  code = c(
    "import ctypes, os, time",
    "def control(observer, pending):",
    "    kernel = ctypes.WinDLL('kernel32.dll', use_last_error=True)",
    "    kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,",
    "        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]",
    "    kernel.CreateFileW.restype = ctypes.c_void_p",
    "    kernel.SetFileInformationByHandle.argtypes = [ctypes.c_void_p, ctypes.c_int,",
    "        ctypes.c_void_p, ctypes.c_uint32]",
    "    kernel.CloseHandle.argtypes = [ctypes.c_void_p]",
    "    def sample():",
    "        try:",
    "            x = observer.snapshot()",
    "        except Exception as error:",
    "            return str(error)",
    "        return '%d %d %d' % (x['bytes'], x['disappeared'], x['directories'])",
    "    marker, data = (os.path.join(observer.root, x) for x in ('marker.json', 'data'))",
    "    result = dict(ordinary=pending(data), absent=pending(marker + '.absent'))",
    "    handle = kernel.CreateFileW(marker, 0x10000, 7, None, 3, 0x80, None)",
    "    if handle in (None, ctypes.c_void_p(-1).value):",
    "        raise ctypes.WinError(ctypes.get_last_error())",
    "    try:",
    "        flag = ctypes.c_ubyte(1)",
    "        if not kernel.SetFileInformationByHandle(handle, 4, ctypes.byref(flag), 1):",
    "            raise ctypes.WinError(ctypes.get_last_error())",
    "        result.update(listed='marker.json' in os.listdir(observer.root),",
    "                      unopened=os.lstat(marker).st_ino == 0,",
    "                      opened=os.lstat(data).st_ino > 0, pending=pending(marker),",
    "                      held=';'.join(sample() for _ in range(3)))",
    "    finally:",
    "        result['closed'] = bool(kernel.CloseHandle(handle))",
    "    deadline = time.monotonic() + 10",
    "    while 'marker.json' in os.listdir(observer.root) and time.monotonic() < deadline:",
    "        time.sleep(0.05)",
    "    result.update(gone='marker.json' not in os.listdir(observer.root),",
    "                  after=pending(marker), released=sample())",
    "    return result")
  result = bp_disk_preserve(function() {
    builtins = reticulate::import_builtins(convert = FALSE)
    control = builtins$dict()
    builtins$exec(paste(code, collapse = "\n"), control, control)
    reticulate::py_to_r(control[["control"]](get("observer", envir = scope, inherits = FALSE),
      get("namespace", envir = scope, inherits = FALSE)[["_windows_delete_pending"]]))
  })
  # Listed but unopenable, the file is charged its 180 listed bytes; once closed it is gone.
  expect_identical(result, list(ordinary = FALSE, absent = FALSE, listed = TRUE,
    unopened = TRUE, opened = TRUE, pending = TRUE, held = "187 0 1;187 0 1;187 0 1",
    closed = TRUE, gone = TRUE, after = FALSE, released = "7 0 1"))
})
