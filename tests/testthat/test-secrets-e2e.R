# End-to-end secrets test (plan P24; INFRA-22, IC-64, IC-70; architecture 6.5): G6 section 5.8
# (test_e2e.R) on the real package. FAKE keys only. The in-process test runs everywhere; tests
# that start processes skip on CRAN. The negative control pushes a non-secret canary through the
# same paths and must find it in the same sinks, which proves the scan sees what flows there
# (value redaction cannot be switched off, architecture 6.5). The printed request view
# (gptr_prompt(s)) stands for INFRA-22's "format(request)".

e2e_keys = c(TYPESAFE_API_KEY = "ts_FAKE0000jev0key0for0tests00001",
             ANTHROPIC_API_KEY = paste0("sk-ant-api03-", strrep("FAKEant0", 11L), "xxxxxAA"),
             GITHUB_PAT = "ghp_FAKEfakeFAKEfakeFAKEfakeFAKEfake1234",
             NEW_SERVICE_TOKEN = "FAKEnewtoken12345678")
e2e_canary = "canaryvalue-alpha-bravo-charlie-delta"

e2e_needles = function(values) {
  unique(c(unname(values), vapply(unname(values), utils::URLencode, "", reserved = TRUE)))
}

e2e_count_raw = function(raw, needles) {
  sum(vapply(needles, function(n) {
    length(grepRaw(charToRaw(n), raw, fixed = TRUE, all = TRUE))
  }, 0L))
}

e2e_count_text = function(text, needles) {
  e2e_count_raw(charToRaw(paste(text, collapse = "\n")), needles)
}

# .rds files (sidecars, worker specs) are compared after decompression.
e2e_file_raw = function(f) {
  if (grepl("[.]rdsx?$", f)) {
    obj = tryCatch(readRDS(f), error = function(e) NULL)
    if (!is.null(obj)) return(serialize(obj, NULL, ascii = FALSE))
  }
  readBin(f, "raw", file.size(f))
}

e2e_scan_files = function(files, needles) {
  # An empty file holds no key; this also skips the named pipes of processx supervisors.
  files = files[file.exists(files) & !dir.exists(files) & file.size(files) > 0]
  stats::setNames(vapply(files, function(f) e2e_count_raw(e2e_file_raw(f), needles), 0L), files)
}

e2e_scan_dir = function(dir, needles) {
  e2e_scan_files(list.files(dir, recursive = TRUE, all.files = TRUE, full.names = TRUE,
                            no.. = TRUE), needles)
}

# Files under `dirs` created or modified since `since`.
e2e_recent_files = function(dirs, since) {
  f = unlist(lapply(dirs[dir.exists(dirs)], list.files, recursive = TRUE, all.files = TRUE,
                    full.names = TRUE, no.. = TRUE))
  f[!is.na(file.mtime(f)) & file.mtime(f) >= since - 1]
}

e2e_leaks = function(counts) paste(names(counts)[counts > 0], collapse = ", ")

# Registers the fake Jev key through a .env file (gptr_env()); returns that file's path, which
# every scan excludes. TYPESAFE_API_KEY is restored when the calling test ends.
e2e_register = function(.env = parent.frame()) {
  withr::local_envvar(TYPESAFE_API_KEY = "", .local_envir = .env)
  f = withr::local_tempfile(fileext = ".env", .local_envir = .env)
  writeLines(paste0("jev-key=", e2e_keys[["TYPESAFE_API_KEY"]]), f)
  gptr_env(f, quiet = TRUE)
  invisible(f)
}

# Worker children load gptr with library(): under R CMD check the installed package is on the
# library path; from a source tree (devtools::test()) the tree is installed once per R session
# into a temporary library that is put first on .libPaths() (never the user library). Copied
# from P19's test-subagent-worker.R: testthat sources each test file on its own and 05 gives
# P24 no helper file.
local_worker_lib = function(.env = parent.frame()) {
  testthat::skip_on_cran()
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (!file.exists(file.path(path, "R", "aaa-state.R"))) return(invisible(NULL))
  lib = file.path(tempdir(), "gptr-worker-lib")
  if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
    dir.create(lib, showWarnings = FALSE, recursive = TRUE)
    cmd = sprintf(paste0("install.packages('%s', lib = '%s', repos = NULL, type = 'source', ",
                         "INSTALL_opts = c('--no-docs', '--no-multiarch', '--no-test-load'))"),
                  normalizePath(path, winslash = "/"), normalizePath(lib, winslash = "/"))
    res = processx::run(rscript_path(), c("--vanilla", "-e", cmd), error_on_status = FALSE,
                        timeout = 600)
    if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
      testthat::skip(paste("could not install gptr for worker children:", res$stderr))
    }
  }
  withr::local_libpaths(lib, action = "prefix", .local_envir = .env)
  invisible(lib)
}

test_that("fake keys reach no in-process sink, and the canary reaches them (control)", {
  root = local_project()
  local_gptr_options(quiet = FALSE, verbose = 2L)
  withr::local_envvar(c(ANTHROPIC_API_KEY = e2e_keys[["ANTHROPIC_API_KEY"]],
                        GITHUB_PAT = e2e_keys[["GITHUB_PAT"]], GPTR_E2E_CANARY = e2e_canary,
                        NEW_SERVICE_TOKEN = NA))
  e2e_register()
  gptr_permissions(allow = "r(secret:TYPESAFE_API_KEY)")
  withr::defer(gptr_permissions(remove = "r(secret:TYPESAFE_API_KEY)"))
  doc = file.path(root, "analysis.R")
  # The run is a block of the bound document: P15 records no peter() call nested in another
  # sourced file, and this test file is one.
  writeLines(c("library(gptr)",
               "s = peter(\"Inspect the environment and summarise the configuration.\",",
               "          model = \"fake/fake-1\", mode = \"auto\")"), doc)
  gptr_doc(doc)
  withr::defer(gptr_doc(FALSE))
  code = paste(c("k = Sys.getenv('TYPESAFE_API_KEY')", "cv = Sys.getenv('GPTR_E2E_CANARY')",
                 "print(k)", "print(cv)", "message('key is ', k, ' canary ', cv)",
                 "warning('key ', k)",
                 "cat(paste(rep(c(k, cv), 3000L), collapse = '\\n'))"), collapse = "\n")
  # r(secret:NAME) pre-approves a call only when its secret reads are its only flagged calls
  # (P11), so the late secret has a call of its own.
  late = paste(c("Sys.setenv(NEW_SERVICE_TOKEN = paste0('FAKEnew', 'token12345678'))",
                 "cat(Sys.getenv('NEW_SERVICE_TOKEN'), '\\n')"), collapse = "\n")
  fake = local_fake_provider(list(
    fake_tool("r", code = code, note = paste("checked", e2e_canary),
              .text = "Let me inspect the environment first."),
    fake_tool("r", code = late),
    fake_text(paste0("I found ", e2e_keys[["ANTHROPIC_API_KEY"]], " and ", e2e_canary,
                     " in the output."))))
  judge = local_fake_provider(function(state, question) 0.1, name = "judge", type = "classifier")
  errfake = local_fake_provider(list(fake_error(
    message = paste0("HTTP 401: invalid key ", e2e_keys[["TYPESAFE_API_KEY"]], " ", e2e_canary),
    status = 401L)), name = "errfake")
  e = new.env()
  # evaluate_promise() collects stdout, messages (cli output arrives as messages under
  # testthat) and warnings; every one of them is a sink that must hold no key.
  ep = testthat::evaluate_promise({
    gptr_source(doc, replay = "auto", envir = e)
    s = e$s
    print(s)
    print(summary(s))
    str(s)
    print(s$history)
    print(s$usage)
    print(gptr_prompt(s))
    d = peter(paste("Is the token", e2e_keys[["GITHUB_PAT"]], "safe to share?"),
             paste("config:", e2e_keys[["GITHUB_PAT"]], e2e_canary), model = judge)
    print(d)
    print(gptr_providers())
    print(secret_lookup("TYPESAFE_API_KEY"))
    err = tryCatch(peter("Any error?", model = errfake, envir = e),
                   gptr_error = function(cnd) cnd)
    print(conditionMessage(err))
  })
  console = c(ep$output, ep$messages)
  conds = c(ep$warnings, conditionMessage(err))
  expect_s3_class(err, "gptr_error_provider")
  keys = e2e_needles(e2e_keys)
  sinks = c(e2e_scan_dir(root, keys),
            console = e2e_count_text(console, keys),
            conditions = e2e_count_text(conds, keys),
            serialized_session = e2e_count_raw(serialize(s, NULL), keys),
            egress_chat = e2e_count_raw(serialize(fake_requests(fake), NULL), keys),
            egress_s1 = e2e_count_raw(serialize(fake_requests(judge), NULL), keys))
  expect_identical(sum(sinks), 0L, info = e2e_leaks(sinks))
  expect_identical(nrow(gptr_scrub(root)), 0L)
  expect_no_error(gptr_scrub(root, error = TRUE))
  expect_match(paste(console, collapse = "\n"), "[secret:TYPESAFE_API_KEY]", fixed = TRUE)
  canary = e2e_needles(e2e_canary)
  files = e2e_scan_dir(root, canary)
  expect_gt(sum(files[grepl("/sessions/.*[.]jsonl$", names(files))]), 0L)
  expect_gt(sum(files[grepl("/cache/tmp/", names(files))]), 0L)
  expect_gt(e2e_count_text(readLines(doc, encoding = "UTF-8"), canary), 0L)
  expect_gt(e2e_count_text(console, canary), 0L)
  expect_gt(e2e_count_raw(serialize(fake_requests(fake), NULL), canary), 0L)
  expect_gt(e2e_count_raw(serialize(fake_requests(judge), NULL), canary), 0L)
})

test_that("a redirect to a second origin receives no key and the wire log holds none (IC-64)", {
  skip_on_cran()
  # The server first: its helper finds its script relative to the test directory.
  srv = local_mock_server("redirect")
  root = local_project()
  withr::local_envvar(ANTHROPIC_API_KEY = e2e_keys[["ANTHROPIC_API_KEY"]])
  local_gptr_options(wire_log = TRUE)
  prov = srv$provider
  prov$auth = "ANTHROPIC_API_KEY"
  off = gptr_register(prov)
  withr::defer(off())
  ref = paste0(prov$id, "/", prov$models[[1L]]$id)
  err = tryCatch(peter("hello", model = ref, envir = new.env()), gptr_error = function(cnd) cnd)
  expect_s3_class(err, "gptr_error_redirect")
  expect_s3_class(err, "gptr_error_provider")
  log = srv$log()
  expect_identical(nrow(log), 1L)
  expect_false(any(grepl("redirected-to-second-origin", log$path, fixed = TRUE)))
  keys = e2e_needles(e2e_keys)
  expect_identical(e2e_count_text(conditionMessage(err), keys), 0L)
  files = e2e_scan_dir(root, keys)
  expect_identical(sum(files), 0L, info = e2e_leaks(files))
})

test_that("worker spec and result files and worker output carry no key (IC-70)", {
  skip_on_cran()
  skip_if_not_installed("callr")
  local_worker_lib()
  root = local_project()
  env_file = e2e_register()
  started = Sys.time()
  keys = e2e_needles(e2e_keys)
  # The worker's spec and result files are removed when it exits: they are scanned just before.
  seen = integer()
  cleanup = worker_cleanup
  local_mocked_bindings(worker_cleanup = function(st) {
    if (!is.null(st$dir)) seen <<- c(seen, e2e_scan_dir(st$dir, keys))
    cleanup(st)
  })
  wfake = local_fake_provider(list("summary ok"), name = "wfake")
  team = peter(paste("Summarise the configuration; the token is", e2e_keys[["TYPESAFE_API_KEY"]]),
              agents = list(w = agent(model = wfake, backend = "worker")), mode = "auto",
              envir = new.env())
  expect_identical(team$kind, "team")
  expect_identical(e2e_count_text(team$text, keys), 0L)
  expect_true(all(c("spec.rds", "result.rds") %in% basename(names(seen))))
  recent = setdiff(e2e_recent_files(c(tempdir(), root), started), env_file)
  files = c(e2e_scan_files(recent, keys), seen)
  expect_identical(sum(files), 0L, info = e2e_leaks(files))
})

test_that("an MCP tool result and the MCP logs are redacted (IC-70)", {
  skip_on_cran()
  root = local_project()
  e2e_register()
  fx = local_mcp_fixture(tools = "echo")
  # fx$spec is a plain list, not a spec: P18's helper local_mcp_server() adds it as gptr's user
  # server "fixture" (gptr_mcp_add()) and removes it when the test ends.
  local_mcp_server(fx)
  gptr_permissions(allow = "r(secret:TYPESAFE_API_KEY)")
  withr::defer(gptr_permissions(remove = "r(secret:TYPESAFE_API_KEY)"))
  started = Sys.time()
  # The read and the MCP call are two calls: r(secret:NAME) covers secret reads only (P11). The
  # fixture's echo writes text starting with "stderr:" to its stderr.
  code = sprintf("peter$mcp[[%s]]$echo(text = paste0('stderr:', k))", deparse(fx$spec$name))
  fake = local_fake_provider(list(fake_tool("r", code = "k = Sys.getenv('TYPESAFE_API_KEY')"),
                                  fake_tool("r", code = code), "echoed"))
  s = peter("Echo the key through MCP.", model = fake, mode = "auto", envir = new.env())
  # Closing the server flushes the rest of its redacted stderr log.
  fx$stop()
  logs = e2e_recent_files(file.path(tempdir(), "gptr", "mcp-logs"), started)
  expect_match(paste(unlist(lapply(logs, readLines, warn = FALSE)), collapse = "\n"),
               "[secret:TYPESAFE_API_KEY]", fixed = TRUE)
  keys = e2e_needles(e2e_keys)
  files = c(e2e_scan_dir(root, keys), e2e_scan_files(logs, keys))
  expect_identical(sum(files), 0L, info = e2e_leaks(files))
  expect_identical(e2e_count_raw(serialize(fake_requests(fake), NULL), keys), 0L)
})

test_that("an artifact's log gets the child's key output redacted (IC-70)", {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("httpuv")
  root = local_project()
  e2e_register()
  dir = file.path(root, ".gptr", "artifacts", "keylog")
  dir.create(dir, recursive = TRUE)
  writeLines(c("library(shiny)",
               "message('startup ', paste0('ts_FAKE0000', 'jev0key0for0tests00001'))",
               "shinyApp(fluidPage('ok'), function(input, output) NULL)"),
             file.path(dir, "app.R"))
  a = peter$app("keylog", check = FALSE, launch = TRUE)
  expect_s3_class(a, "gptr_artifact")
  # The listing syncs the child's output into the log (IC-70); stopping flushes the rest.
  for (i in 1:50) {
    gptr_artifacts()
    logs = list.files(file.path(dir, "run"), pattern = "^app-v[0-9]+[.]log$", full.names = TRUE)
    if (length(logs) && any(file.size(logs) > 0)) break
    Sys.sleep(0.2)
  }
  gptr_artifacts("keylog", stop = TRUE)
  logs = list.files(file.path(dir, "run"), pattern = "^app-v[0-9]+[.]log$", full.names = TRUE)
  expect_true(length(logs) > 0)
  text = unlist(lapply(logs, readLines, encoding = "UTF-8", warn = FALSE))
  expect_match(paste(text, collapse = "\n"), "[secret:TYPESAFE_API_KEY]", fixed = TRUE)
  files = e2e_scan_dir(root, e2e_needles(e2e_keys))
  expect_identical(sum(files), 0L, info = e2e_leaks(files))
})

test_that("a CLI child sees no billing key (G6 3.7)", {
  skip_on_cran()
  withr::local_envvar(ANTHROPIC_API_KEY = e2e_keys[["ANTHROPIC_API_KEY"]])
  env = suppressWarnings(child_env("cli-claude"))
  expect_false("ANTHROPIC_API_KEY" %in% names(env))
  res = processx::run(rscript_path(),
                      c("--vanilla", "-e", "cat(nzchar(Sys.getenv('ANTHROPIC_API_KEY')))"),
                      env = env)
  expect_identical(res$stdout, "FALSE")
})

test_that("an Rscript run with a bound document leaves no key in documents or sidecars", {
  skip_on_cran()
  proj = withr::local_tempdir("proj")
  dir.create(file.path(proj, ".gptr"))
  doc = file.path(proj, "analysis.R")
  side = withr::local_tempdir("side")
  src = normalizePath(testthat::test_path("..", ".."), winslash = "/", mustWork = FALSE)
  use_src = file.exists(file.path(src, "DESCRIPTION")) && dir.exists(file.path(src, "R"))
  # The run is the bound document itself (P15 records the blocks of the script it runs); its last
  # line copies the deferred-write sidecars, which the exit applies and removes.
  writeLines(c(
    if (use_src) sprintf("pkgload::load_all(%s, quiet = TRUE)", deparse(src)) else "library(gptr)",
    "options(gptr.quiet = TRUE)",
    sprintf("setwd(%s)", deparse(proj)),
    paste0("fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = ",
           "\"k = Sys.getenv('TYPESAFE_API_KEY'); cat(k)\")), 'done'))"),
    sprintf("gptr_doc(%s)", deparse(doc)),
    "gptr_permissions(allow = 'r(secret:TYPESAFE_API_KEY)')",
    "s = peter('print the key', model = fake, mode = 'auto', envir = globalenv())",
    sprintf("invisible(file.copy(Sys.glob('.gptr/cache/tmp/pending-*.rds'), %s))",
            deparse(side))), doc)
  res = processx::run(rscript_path(), c("--vanilla", doc), error_on_status = FALSE,
                      env = c("current", TYPESAFE_API_KEY = e2e_keys[["TYPESAFE_API_KEY"]],
                              GPTR_PROJECT_ROOT = proj, GPTR_REPLAY = "auto", NOT_CRAN = "true"))
  expect_identical(res$status, 0L, info = res$stderr)
  expect_match(paste(readLines(doc), collapse = "\n"), "[secret:TYPESAFE_API_KEY]", fixed = TRUE)
  expect_gt(length(list.files(side)), 0L)
  keys = e2e_needles(e2e_keys)
  files = c(e2e_scan_dir(proj, keys), e2e_scan_dir(side, keys))
  expect_identical(sum(files), 0L, info = e2e_leaks(files))
  expect_identical(e2e_count_text(c(res$stdout, res$stderr), keys), 0L)
})
