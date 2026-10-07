test_that("rel_child_env() removes credentials and redirects home and user directories", {
  # LANGUAGE, NO_COLOR and OMP_THREAD_LIMIT are set here so that the duplicate-name check below
  # fails if an inherited value is kept next to the forced one.
  withr::local_envvar(ANTHROPIC_API_KEY = paste0("sk-", "ant-not-real"), MY_SERVICE_TOKEN = "x",
                      AWS_SECRET_ACCESS_KEY = "x", AZURE_OPENAI_ENDPOINT = "https://x",
                      GPTR_REPLAY = "live", LANGUAGE = "de", NO_COLOR = "0",
                      OMP_THREAD_LIMIT = "16")
  env = rel_child_env("/h", "/t", "/p", lib = "/l", offline = TRUE, check_pkg = "gptr")
  expect_false(any(c("ANTHROPIC_API_KEY", "MY_SERVICE_TOKEN", "AWS_SECRET_ACCESS_KEY",
                     "AZURE_OPENAI_ENDPOINT", "GPTR_REPLAY") %in% names(env)))
  expect_identical(unname(env[["HOME"]]), "/h")
  expect_identical(unname(env[["R_USER_CACHE_DIR"]]), file.path("/h", "r-user", "cache"))
  expect_identical(unname(env[["GPTR_PROJECT_ROOT"]]), "/p")
  expect_identical(unname(env[["https_proxy"]]), "http://127.0.0.1:9")
  expect_identical(unname(env[["_R_CHECK_PACKAGE_NAME_"]]), "gptr")
  expect_match(env[["R_LIBS"]], "^/l")
  expect_false(anyDuplicated(names(env)) > 0L)
  expect_false(anyNA(env))
})

test_that("ex_run_all() passes clean examples and reports every kind of side effect", {
  root = file.path(tempfile("toyex-"), "toyex")
  dir.create(file.path(root, "R"), recursive = TRUE)
  writeLines(c("Package: toyex", "Title: Toy Package for the Example Runner", "Version: 0.0.1",
               "Authors@R: person(\"A\", \"B\", email = \"a@b.org\", role = c(\"aut\", \"cre\"))",
               "Description: A toy package used by the gptr release self-tests.",
               "License: MIT", "Encoding: UTF-8"),
             file.path(root, "DESCRIPTION"))
  writeLines("export(f)", file.path(root, "NAMESPACE"))
  writeLines("f = function(x) x", file.path(root, "R", "f.R"))
  file.rename(toy_man(list(
    clean = rd_page("clean", aliases = c("clean", "f"), examples = "f(1)"),
    userdir = rd_page("userdir", examples = c(
      "d = tools::R_user_dir(\"toyex\", \"cache\")", "dir.create(d, recursive = TRUE)",
      "writeLines(\"x\", file.path(d, \"x.txt\"))")),
    conn = rd_page("conn", examples = "con = file(tempfile(), \"w\")"),
    cwd = rd_page("cwd", examples = "writeLines(\"x\", \"left-behind.txt\")"),
    fails = rd_page("fails", examples = "stop(\"boom\")")
  )), file.path(root, "man"))
  run = ex_run_all(root, pkg = "toyex")
  expect_setequal(run$results$page, c("clean", "conn", "cwd", "fails", "userdir"))
  expect_identical(run$results$status[run$results$page == "clean"], 0L)
  expect_false(any(startsWith(run$problems, "clean:")))
  expect_true(any(grepl("^userdir: wrote outside the session temp directory", run$problems)))
  expect_true(any(grepl("^conn: example failed .*connections left open", run$problems)))
  expect_true(any(grepl("^cwd: wrote into the working directory: left-behind.txt", run$problems)))
  expect_true(any(grepl("^fails: example failed .*boom", run$problems)))
})
