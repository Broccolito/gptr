test_that("test children inherit temporary directories owned by the suite", {
  root = dirname(Sys.getenv("R_USER_CONFIG_DIR"))
  expected = normalizePath(file.path(root, "child-temp"), winslash = "/", mustWork = TRUE)
  actual = normalizePath(Sys.getenv(c("TMPDIR", "TMP", "TEMP")), winslash = "/",
                         mustWork = TRUE)
  expect_identical(unname(actual), rep(expected, 3L))
  expect_identical(normalizePath(Sys.getenv("MAC_CHROMIUM_TMPDIR"), winslash = "/",
                                 mustWork = TRUE), expected)
  expect_true(dir.exists(expected))
  keep = if (is_windows()) c("TMP", "TEMP") else "TMPDIR"
  for (profile in c("helper", "mcp")) {
    env = normalizePath(child_env(profile)[keep], winslash = "/", mustWork = TRUE)
    expect_identical(unname(env), rep(expected, length(keep)), label = profile)
  }
})

test_that("a killed Windows Rscript expression leaves detritus only in its owned tree", {
  skip_on_cran()
  skip_if_not(is_windows())
  state = new.env(parent = emptyenv())
  (function() {
    state$root = normalizePath(
      withr::local_tempdir("gptr-rscript-owned-", .local_envir = environment()), winslash = "/")
    ready = file.path(state$root, "ready.rds")
    code = paste0(
      "d = Sys.getenv('TMPDIR'); ",
      "files = list.files(d, pattern = sprintf('^Rscript%x', Sys.getpid()), full.names = TRUE); ",
      "saveRDS(list(pid = Sys.getpid(), files = files), ", encodeString(ready, quote = "\""),
      "); Sys.sleep(30)"
    )
    p = processx::process$new(rscript_path(), c("--vanilla", "-e", code),
                              env = c("current", TMPDIR = state$root, TMP = state$root,
                                      TEMP = state$root), stdout = NULL, stderr = NULL,
                              cleanup_tree = TRUE, supervise = supervise_default())
    withr::defer(kill_all(p, grace = 0), envir = environment())
    deadline = Sys.time() + 20
    while (!file.exists(ready) && p$is_alive() && Sys.time() < deadline) p$wait(50L)
    expect_true(file.exists(ready))
    if (!file.exists(ready)) return(invisible(NULL))
    witness = readRDS(ready)
    expect_length(witness$files, 1L)
    expect_true(all(dirname(witness$files) == state$root))
    expect_true(kill_all(p, grace = 0))
    expect_false(pid_alive(witness$pid))
    expect_true(all(file.exists(witness$files)))
  })()
  expect_false(dir.exists(state$root))
})
