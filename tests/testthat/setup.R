# Test environment (contract section 3.2 and 12.2, IC-63): nothing a test does may touch the
# user's home directory, the user's R_user_dir() folders, a real `.gptr/` workspace, real keys,
# an installed claude or codex CLI or the network. Everything below is restored when the test run
# ends.
local({
  linux = identical(Sys.info()[["sysname"]], "Linux")
  # Chromium adds a Unix socket suffix; nested CI roots can exceed sun_path's 108-byte limit.
  # CRAN allows writes only under tempdir() and skips every Chromium test.
  short_root = linux && identical(Sys.getenv("NOT_CRAN"), "true")
  evidence = Sys.getenv("GPTR_TEST_ROOT_EVIDENCE", unset = "")
  diagnostic = linux && nzchar(evidence)
  if (diagnostic) {
    state = new.env(parent = emptyenv())
    state$schema = 1L
    state$pid = Sys.getpid()
    state$unlink_attempted = FALSE
    state$unlink_returned = FALSE
    state$unlink_status = NULL
    state$unlink_condition_classes = list()
    state$last_priority_reached = FALSE
  }
  root = withr::local_tempdir("gptr-tests-", tmpdir = if (short_root) "/tmp" else tempdir(),
                            .local_envir = testthat::teardown_env(), clean = !diagnostic)
  if (diagnostic) {
    # This replaces only local_tempdir's original callback, in the same registration slot.
    withr::defer({
      state$unlink_attempted = TRUE
      condition = tryCatch({
        state$unlink_status = unlink(root, recursive = TRUE)
        state$unlink_returned = TRUE
        NULL
      }, error = identity, interrupt = identity)
      if (!is.null(condition)) {
        state$unlink_condition_classes = as.list(class(condition))
        stop(condition)
      }
    }, envir = testthat::teardown_env())
    state$root = root
    reader = Sys.getenv("GPTR_TEST_ROOT_READER", unset = "")
    python = Sys.getenv("GPTR_TEST_ROOT_PYTHON", unset = "")
    record = file.path(evidence, paste0("suite-", state$pid, "-", basename(root), ".json"))
    publish = function() {
      jsonlite::write_json(as.list(state), paste0(record, ".tmp"), auto_unbox = TRUE,
                          pretty = TRUE, null = "null")
      stopifnot(file.rename(paste0(record, ".tmp"), record))
    }
    # Observe after existing suite callbacks; metadata failure cannot replace the test error.
    withr::defer({
      state$last_priority_reached = TRUE
      tryCatch({
        publish()
        status = system2(python, c("-I", "-B", shQuote(reader), "teardown", shQuote(record)),
                         timeout = 5)
        if (!identical(status, 0L)) message("GPTR_TEST_ROOT_READER_NONZERO")
      }, error = function(e) message("GPTR_TEST_ROOT_PUBLICATION_ERROR:", class(e)[1L]),
      interrupt = function(e) message("GPTR_TEST_ROOT_PUBLICATION_INTERRUPT"))
    }, envir = testthat::teardown_env(), priority = "last")
    stopifnot(dir.exists(evidence), file.exists(reader), file.exists(python), !file.exists(record))
    publish()
  }
  if (linux) stopifnot(Sys.chmod(root, "0700"))
  # The home is a Windows profile: Google Chrome refuses DevTools when the shell cannot resolve
  # its default profile folder under %USERPROFILE%\AppData\Local
  dirs = c(
    config = "user-config", data = "user-data", cache = "user-cache", home = "home",
    appdata = "home/AppData/Roaming", localappdata = "home/AppData/Local", xdg = "xdg-config",
    project = "project", temp = "child-temp"
  )
  paths = stats::setNames(file.path(root, dirs), names(dirs))
  for (path in paths) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (short_root) {
    socket = file.path(paths[["temp"]], "org.chromium.Chromium.XXXXXX", "SingletonSocket")
    stopifnot(nchar(socket, type = "bytes") <= 107L)
  }
  withr::local_envvar(
    R_USER_CONFIG_DIR = paths[["config"]],
    R_USER_DATA_DIR = paths[["data"]],
    R_USER_CACHE_DIR = paths[["cache"]],
    HOME = paths[["home"]],
    USERPROFILE = paths[["home"]],
    APPDATA = paths[["appdata"]],
    LOCALAPPDATA = paths[["localappdata"]],
    XDG_CONFIG_HOME = paths[["xdg"]],
    # Windows Rscript -e leaves its input file after a force-kill; suite teardown owns this tree.
    TMPDIR = paths[["temp"]], TMP = paths[["temp"]], TEMP = paths[["temp"]],
    # Chromium uses its own temp override on macOS.
    MAC_CHROMIUM_TMPDIR = paths[["temp"]],
    GPTR_PROJECT_ROOT = paths[["project"]],
    GPTR_REPLAY = "replay",
    OMP_THREAD_LIMIT = "2",
    # Windows Terminal: console_style() draws its UTF-8 glyphs wherever cli's unicode output is on;
    # a test of a Windows console that lacks them unsets WT_SESSION (D-245)
    WT_SESSION = "gptr-tests",
    .local_envir = testthat::teardown_env()
  )
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
    # every variable that session start would register as a secret (secret_discover_env())
    keys = names(Sys.getenv())
    keys = keys[is_secret_name(keys)]
    withr::local_envvar(
      stats::setNames(rep("", length(keys)), keys),
      .local_envir = testthat::teardown_env()
    )
    # tests that need a CLI point this option at the fake CLI (P20)
    none = file.path(root, "no-cli")
    withr::local_options(
      gptr.cli_path = list(claude = none, codex = none),
      .local_envir = testthat::teardown_env()
    )
  }
  withr::local_options(
    gptr.project_root = paths[["project"]],
    gptr.replay = "replay",
    gptr.interactive = FALSE,
    gptr.quiet = TRUE,
    # waiting rows clear with spaces whether or not the runner's stderr is a terminal
    cli.ansi = FALSE,
    .local_envir = testthat::teardown_env()
  )
})

# Cache this process's real identity before any test mocks proc_create_time() (children check it)
proc_self()

# chromote always starts processx's supervisor; when gptr does not supervise (IC-60), end it
# with the run, after the tests have closed the browser
withr::defer(if (!supervise_default()) processx::supervisor_kill(),
             envir = testthat::teardown_env())
