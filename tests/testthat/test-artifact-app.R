# Tests of R/artifact-app.R (plan P23)

# Write a model-written working copy (app.R or page.html) of an artifact
write_working = function(id, lines, file = "app.R") {
  dir = artifact_dir(id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_utf8(file.path(dir, file), lines)
  file.path(dir, file)
}

ok_app = c(
  "library(shiny)",
  "ui = fluidPage(textInput('gene', 'Gene'), tableOutput('t'))",
  "server = function(input, output, session) {",
  "  output$t = renderTable(markers[grepl(input$gene, markers$gene, fixed = TRUE), ])",
  "}",
  "shinyApp(ui, server)"
)

test_that("artifact ids follow contract 11.6 and refuse Windows reserved names", {
  expect_identical(artifact_id_check("marker-explorer"), "marker-explorer")
  expect_identical(artifact_id_check(strrep("a", 63)), strrep("a", 63))
  bad = c("con", "aux", "nul", "prn", "com1", "lpt9", "Marker", "-x", "a b", "a/b", "a.b",
          strrep("a", 64), "")
  for (id in bad) expect_error(artifact_id_check(id), class = "gptr_error_invalid_argument")
  expect_error(artifact_id_check(1), class = "gptr_error_invalid_argument")
  cnd = expect_error(artifact_id_check("con"), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "id")
})

test_that("artifacts live under the workspace root", {
  root = local_project()
  expect_identical(artifact_dir("demo"), file.path(root, ".gptr", "artifacts", "demo"))
  expect_identical(basename(artifact_version_dir("demo", 2L)), "v002")
  expect_identical(basename(artifact_version_dir("demo", 1000L)), "v1000")
  expect_identical(basename(artifact_working_file(artifact_dir("demo"), "shiny")), "app.R")
  expect_identical(basename(artifact_working_file(artifact_dir("demo"), "html")), "page.html")
})

test_that("artifact.json round-trips versions, checks and a null port", {
  local_project()
  meta = artifact_meta_new("demo", "Demo")
  rec = list(name = "d", file = "data/001.rds", class = "data.frame", dim = I(c(3L, 2L)),
             bytes = 10)
  meta$versions = list(list(n = 1L, created = artifact_time(), app_sha = "ab",
                            data = list(rec), session = NULL,
                            checks = artifact_checks_json(artifact_checks(parse = TRUE))))
  meta$current = 1L
  artifact_meta_write("demo", meta)
  expect_true(artifact_exists("demo"))
  txt = paste(readLines(artifact_meta_path("demo"), encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "\"port\": null", fixed = TRUE)
  expect_match(txt, "\"launch\": null", fixed = TRUE)
  back = artifact_meta_read("demo")
  expect_identical(back$title, "Demo")
  expect_identical(back$kind, "shiny")
  expect_identical(as.integer(back$current), 1L)
  v = artifact_version_record(back, 1L)
  expect_equal(unlist(v$data[[1]]$dim), c(3, 2))
  expect_null(artifact_version_record(back, 2L))
  checks = artifact_checks_from_json(v$checks)
  expect_true(checks$parse)
  expect_true(is.na(checks$launch))
  artifact_version_checks_set("demo", 1L, artifact_checks(TRUE, TRUE, FALSE, NA))
  expect_false(artifact_meta_read("demo")$versions[[1]]$checks$http)
  artifact_set_current("demo", 0L)
  expect_identical(as.integer(artifact_meta_read("demo")$current), 0L)
  expect_null(artifact_meta_read("absent"))
})

test_that("the handle formats as the NS-8 line with its checks, and prints it", {
  root = local_project()
  h = new_gptr_artifact("marker-explorer", "Marker explorer", "shiny", 1L,
                        url = "http://127.0.0.1:4827/?gptr_token=00ff",
                        path = file.path(root, ".gptr", "artifacts", "marker-explorer", "app.R"),
                        status = "running",
                        checks = artifact_checks(TRUE, TRUE, TRUE, NA, "HTTP-only check"))
  expect_s3_class(h, "gptr_artifact")
  expect_named(h, c("id", "title", "kind", "version", "url", "path", "status", "checks",
                    "screenshot", "session"))
  line = paste0("artifact  marker-explorer  ->  http://127.0.0.1:4827/?gptr_token=00ff   ",
                "(running in background)")
  expect_identical(format(h), c(line, "checks: parse ok | launch ok | http ok | session skipped",
                                "  HTTP-only check"))
  expect_identical(utils::capture.output(print(h))[1], line)
  h$status = "stopped"
  h$url = NA_character_
  h$checks = artifact_checks()
  expect_identical(format(h), paste0("artifact  marker-explorer  ->  ",
                                     ".gptr/artifacts/marker-explorer/app.R   (stopped)"))
})

test_that("static checks accept a well-formed app, also ending in shiny::shinyApp()", {
  skip_if_not_installed("shiny")
  res = artifact_static_check(ok_app)
  expect_true(res$ok)
  expect_identical(res$stage, "ok")
  expect_identical(res$messages, character())
  expect_identical(res$packages, "shiny")
  expect_true(artifact_static_check(sub("^shinyApp", "shiny::shinyApp", ok_app))$ok)
  allowed = c(ok_app[1:3],
              "  up = reactive(read.csv(input$file$datapath))",
              "  extra = readRDS('data/001.rds')",
              "  inline = utils::read.csv(text = 'a,b\\n1,2')",
              "  inline2 = fread('a,b\\n1,2')",
              "  con = file('data/001.rds', 'rb')",
              ok_app[4:6])
  expect_true(artifact_static_check(allowed)$ok)
})

test_that("static checks reject empty code and parse errors at the parse stage", {
  for (code in list("", character(), "   \n  ")) {
    res = artifact_static_check(code)
    expect_false(res$ok)
    expect_identical(res$stage, "parse")
  }
  res = artifact_static_check("ui = fluidPage(")
  expect_identical(res$stage, "parse")
  expect_match(res$messages, "does not parse", fixed = TRUE)
  expect_identical(artifact_static_check("# only a comment")$messages, "app.R has no expressions")
})

test_that("static checks name each forbidden pattern", {
  skip_if_not_installed("shiny")
  with_line = function(line) c(ok_app[1:5], line, ok_app[6])
  msg = function(code) {
    res = artifact_static_check(code)
    expect_false(res$ok)
    expect_identical(res$stage, "static")
    paste(res$messages, collapse = "\n")
  }
  expect_match(msg(with_line("setwd(tempdir())")), "setwd", fixed = TRUE)
  expect_match(msg(with_line("install.packages('DT')")), "install.packages", fixed = TRUE)
  expect_match(msg(with_line("if (FALSE) shiny::runApp('.')")), "runApp", fixed = TRUE)
  expect_match(msg(with_line("library(notARealPkg)")), "package(s) not installed: notARealPkg",
               fixed = TRUE)
  expect_match(msg(with_line("x = notARealPkg2::f()")), "notARealPkg2", fixed = TRUE)
  expect_match(msg(with_line("extra = read.csv('markers.csv')")),
               "not in its snapshot: read.csv(\"markers.csv\")", fixed = TRUE)
  expect_match(msg(with_line("x = readRDS('/home/me/big.rds')")), "readRDS(\"/home/me/big.rds\")",
               fixed = TRUE)
  expect_match(msg(with_line("x = read.csv(header = TRUE, file = 'markers.csv')")),
               "read.csv(\"markers.csv\")", fixed = TRUE)
  expect_match(msg(with_line("key = readLines('.env')")), "secret file (level 3): .env",
               fixed = TRUE)
  expect_match(msg(c(ok_app[1:5], "app = shinyApp(ui, server)", "app")), "last expression",
               fixed = TRUE)
})

test_that("the shiny and html type checks look at the working copy", {
  skip_if_not_installed("shiny")
  local_project()
  dir = artifact_dir("nothing")
  dir.create(dir, recursive = TRUE)
  res = artifact_check_shiny(dir, NULL)
  expect_false(res$ok)
  expect_identical(res$stage, "parse")
  expect_match(res$messages, ".gptr/artifacts/nothing/app.R", fixed = TRUE)
  write_working("nothing", ok_app)
  expect_true(artifact_check_shiny(dir, NULL)$ok)
  expect_false(artifact_check_html(dir, NULL)$ok)
  write_working("nothing", "<html><body>hi</body></html>", "page.html")
  expect_true(artifact_check_html(dir, NULL)$ok)
})

test_that("objects are snapshotted as numbered files with a loader that binds their names", {
  local_project()
  e = new.env()
  e[["a/b"]] = 1:3
  e$markers = data.frame(gene = c("CD14", "LYZ"), p = c(0.01, 0.2))
  vdir = artifact_version_dir("snap", 1L)
  dir.create(vdir, recursive = TRUE)
  recs = artifact_snapshot(vdir, c("a/b", "markers", "a/b"), e)
  expect_length(recs, 2L)
  expect_identical(vapply(recs, function(r) r$file, ""), c("data/001.rds", "data/002.rds"))
  expect_identical(recs[[1]]$name, "a/b")
  expect_identical(recs[[2]]$class, "data.frame")
  expect_identical(as.integer(recs[[2]]$dim), c(2L, 2L))
  expect_identical(as.integer(recs[[1]]$dim), 3L)
  expect_gt(recs[[2]]$bytes, 0)
  expect_true(all(file.exists(file.path(vdir, "data", c("001.rds", "002.rds")))))
  loader = readLines(file.path(vdir, "R", "gptr_data.R"), encoding = "UTF-8")
  expect_identical(loader[2:3], c("`a/b` = readRDS(\"data/001.rds\")",
                                  "markers = readRDS(\"data/002.rds\")"))
  out = new.env()
  withr::with_dir(vdir, sys.source(file.path("R", "gptr_data.R"), envir = out))
  expect_identical(get("a/b", envir = out), 1:3)
  expect_identical(out$markers, e$markers)
  expect_identical(artifact_snapshot(vdir, character(), e), list())
})

test_that("missing objects and oversized snapshots are refused before anything is written", {
  local_project()
  local_gptr_options(artifact_max_bytes = 1000)
  e = new.env()
  e$big = as.numeric(1:10000)
  vdir = artifact_version_dir("big", 1L)
  dir.create(vdir, recursive = TRUE)
  cnd = expect_error(artifact_snapshot(vdir, "nope", e), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "data")
  expect_error(artifact_snapshot(vdir, "", e), class = "gptr_error_invalid_argument")
  cnd = expect_error(artifact_snapshot(vdir, "big", e), class = "gptr_error_artifact_too_large")
  expect_s3_class(cnd, "gptr_error_artifact")
  expect_identical(cnd$stage, "snapshot")
  expect_identical(cnd$id, "big")
  expect_identical(cnd$max, 1000)
  expect_gt(cnd$bytes, 1000)
  expect_match(conditionMessage(cnd), "gptr.artifact_max_bytes", fixed = TRUE)
  expect_false(dir.exists(file.path(vdir, "data")))
})

test_that("builds copy app.R, and the html build wraps page.html and names the data", {
  local_project()
  write_working("plain", ok_app)
  vdir = artifact_version_dir("plain", 1L)
  dir.create(vdir)
  artifact_build_shiny("plain", vdir, list(), NULL)
  expect_identical(readLines(file.path(vdir, "app.R")), ok_app)
  dir.create(artifact_version_dir("plain", 2L))
  unlink(file.path(artifact_dir("plain"), "app.R"))
  expect_error(artifact_build_shiny("plain", artifact_version_dir("plain", 2L), list(), NULL),
               class = "gptr_error_artifact")
  write_working("wrap", "<html><head></head><body>x</body></html>", "page.html")
  vdir = artifact_version_dir("wrap", 1L)
  dir.create(vdir)
  artifact_build_html("wrap", vdir, list(list(name = "markers")), NULL)
  expect_true(file.exists(file.path(vdir, "page.html")))
  code = readLines(file.path(vdir, "app.R"), encoding = "UTF-8")
  expect_true("gptr_names = c(\"markers\")" %in% code)
  expect_true(artifact_ends_with_app(parse(text = code)))
  expect_true("gptr_names = character()" %in% artifact_html_wrapper(character()))
})

test_that("version directories are claimed in order and never reused", {
  local_project()
  dir.create(artifact_dir("vers"), recursive = TRUE)
  expect_identical(artifact_version_claim("vers"), 1L)
  expect_identical(artifact_version_claim("vers"), 2L)
  unlink(artifact_version_dir("vers", 1L), recursive = TRUE)
  expect_identical(artifact_version_claim("vers"), 3L)
  expect_true(dir.exists(artifact_version_dir("vers", 3L)))
  expect_error(artifact_version_claim("absent"), class = "gptr_error_artifact")
})

skip_if_cannot_launch = function() {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
}

tiny_app = c("library(shiny)", "ui = fluidPage('hi')", "server = function(input, output) {}",
             "shinyApp(ui, server)")

# A version directory built from app lines (and data objects of `envir`)
build_version = function(id, lines, data = character(), envir = new.env()) {
  write_working(id, lines)
  vdir = artifact_version_dir(id, artifact_version_claim(id))
  artifact_snapshot(vdir, data, envir, id = id)
  artifact_build_shiny(id, vdir, list(), NULL)
  vdir
}

# Run artifact_serve() in a callr child as the launcher does; the child is killed when the
# calling test ends
serve_child = function(vdir, token, parent_pid = Sys.getpid(), .env = parent.frame()) {
  port_file = file.path(withr::local_tempdir(.local_envir = .env), "port")
  raw = withr::local_tempfile(fileext = ".log", .local_envir = .env)
  p = callr::r_bg(artifact_serve,
                  args = list(dir = vdir, port_file = port_file, parent_pid = parent_pid,
                              token = token),
                  stdout = raw, stderr = "2>&1", supervise = supervise_default(), package = FALSE,
                  user_profile = FALSE, system_profile = FALSE,
                  env = artifact_child_env(port_candidates(5L)), cleanup = TRUE,
                  cleanup_tree = TRUE, encoding = "UTF-8", wd = vdir)
  withr::defer(kill_all(p, grace = 0), envir = .env)
  deadline = Sys.time() + 30
  while (!file.exists(port_file) && p$is_alive() && Sys.time() < deadline) Sys.sleep(0.05)
  list(proc = p, port_file = port_file, raw = raw)
}

# Status of a GET (NA when nothing answers), polled until the app answers
http_status = function(url, wait = 15) {
  deadline = Sys.time() + wait
  repeat {
    h = curl::new_handle(followlocation = 0L)
    s = tryCatch(curl::curl_fetch_memory(url, handle = h)$status_code,
                 error = function(e) NA_integer_)
    if (!is.na(s) || Sys.time() > deadline) return(s)
    Sys.sleep(0.1)
  }
}

test_that("the access token is 128 random bits from openssl or /dev/urandom", {
  tok = artifact_token()
  expect_match(tok, "^[0-9a-f]{32}$")
  expect_false(identical(tok, artifact_token()))
  skip_on_os("windows")
  local_mocked_bindings(artifact_has_openssl = function() FALSE)
  expect_match(artifact_token(), "^[0-9a-f]{32}$")
})

test_that("ports come from port_candidates() after the artifact's previous port", {
  local_project()
  ports = artifact_ports("fresh")
  expect_length(ports, 20L)
  expect_true(all(ports >= 49152L & ports <= 65535L))
  meta = artifact_meta_new("old")
  meta$port = 51234L
  artifact_meta_write("old", meta)
  expect_identical(artifact_ports("old")[1], 51234L)
})

test_that("the child env is the artifact profile with ports, library paths and safe R vars", {
  withr::local_envvar(R_TESTS = "startup.Rs")
  env = artifact_child_env(c(50001L, 50002L))
  expect_identical(env[["GPTR_ARTIFACT_PORTS"]], "50001,50002")
  expect_identical(env[["R_LIBS"]], paste(.libPaths(), collapse = .Platform$path.sep))
  expect_true(nzchar(env[["R_PROFILE_USER"]]))
  expect_identical(unname(file.size(env[["R_PROFILE_USER"]])), 0)
  expect_identical(env[["R_TESTS"]], "")
  expect_identical(env[["R_BROWSER"]], "false")
})

test_that("artifact_serve() publishes a loopback port and serves only requests with the token", {
  skip_if_cannot_launch()
  local_project()
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  vdir = build_version("served", ok_app, "markers", e)
  tok = artifact_token()
  ch = serve_child(vdir, tok)
  expect_true(file.exists(ch$port_file))
  port = as.integer(readLines(ch$port_file))
  expect_true(port >= 49152L && port <= 65535L)
  base = sprintf("http://127.0.0.1:%d/", port)
  expect_identical(http_status(paste0(base, "?gptr_token=", tok)), 200L)
  expect_identical(http_status(base), 403L)
  expect_identical(http_status(paste0(base, "?gptr_token=", strrep("0", 32))), 403L)
  expect_identical(http_status(paste0(base, "shared/shiny.min.js")), 200L)
})

test_that("a broken app ends the child before a port exists, with its error on stderr", {
  skip_if_cannot_launch()
  local_project()
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  ch = serve_child(build_version("broken", broken), "")
  ch$proc$wait(10000)
  expect_false(ch$proc$is_alive())
  expect_false(file.exists(ch$port_file))
  log = readLines(ch$raw, warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("Error: .*no_such_object", log)))
})

test_that("the watchdog stops the app when the parent process is gone", {
  skip_if_cannot_launch()
  local_project()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  ch = serve_child(build_version("orphan", tiny_app), "", parent_pid = dead$get_pid())
  ch$proc$wait(15000)
  expect_false(ch$proc$is_alive())
  log = readLines(ch$raw, warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("parent R process is gone", log, fixed = TRUE)))
})

skip_if_no_chrome = function() {
  skip_if_not_installed("chromote")
  skip_if(!is.null(artifact_chromote_missing()), "no Chrome or Chromium for chromote")
}

# A Chrome that does not start in time (hosted runners) gives the contract's HTTP-only result
skip_if_browser_failed = function(res) {
  skip_if(is.na(res$ok) && is.null(artifact_state$browser), res$messages[1])
}

# A served version as a record the session check reads: its URL, its redacted log
served_record = function(id, lines, data = character(), envir = new.env(),
                         .env = parent.frame()) {
  tok = artifact_token()
  ch = serve_child(build_version(id, lines, data, envir), tok, .env = .env)
  port = as.integer(readLines(ch$port_file))
  rec = artifact_log_new(ch$raw, file.path(artifact_dir(id), "run", "app-v001.log"))
  rec$url = sprintf("http://127.0.0.1:%d/?gptr_token=%s", port, tok)
  expect_identical(http_status(rec$url), 200L)
  rec
}

test_that("server-log errors and warnings are read with the warning's text", {
  local_project()
  log = file.path(artifact_dir("log"), "app.log")
  dir.create(dirname(log), recursive = TRUE)
  writeLines(c("Listening on http://127.0.0.1:50000",
               "Warning in mean.default(x$revnue) :",
               "  argument is not numeric or logical: returning NA",
               "Warning: Error in xy.coords: 'x' and 'y' lengths differ",
               "  [No stack trace available]"), log)
  got = artifact_log_errors(log)
  expect_identical(got$errors, "Warning: Error in xy.coords: 'x' and 'y' lengths differ")
  expect_identical(got$warnings, paste("Warning in mean.default(x$revnue) :",
                                       "argument is not numeric or logical: returning NA"))
  expect_identical(artifact_log_messages(log)[1],
                   "server log: Warning: Error in xy.coords: 'x' and 'y' lengths differ")
  expect_identical(artifact_log_errors(file.path(dirname(log), "none.log")),
                   list(errors = character(), warnings = character()))
  expect_identical(artifact_log_messages(file.path(dirname(log), "none.log")), character())
})

test_that("without chromote the check is HTTP-only: ok is NA and the messages say so", {
  local_project()
  local_mocked_bindings(artifact_chromote_missing = function() "chromote is not installed")
  rec = artifact_log_new(NULL, file.path(artifact_dir("none"), "run", "app-v001.log"))
  res = artifact_session_check(rec, tempfile(fileext = ".png"))
  expect_true(is.na(res$ok))
  expect_null(res$screenshot)
  expect_identical(res$messages,
                   "HTTP-only check: chromote is not installed; the page was not rendered")
})

test_that("the session check passes a working app and returns a 1000x700 screenshot", {
  skip_if_cannot_launch()
  skip_if_no_chrome()
  local_project()
  withr::defer(artifact_browser_close())
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  rec = served_record("good", ok_app, "markers", e)
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  png = file.path(artifact_dir("good"), "run", "shot.png")
  res = artifact_session_check(rec, png)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  skip_if_browser_failed(res)
  expect_true(res$ok)
  expect_identical(res$messages, character())
  expect_identical(res$screenshot, png)
  bytes = readBin(png, "raw", 24L)
  expect_identical(bytes[1:4], as.raw(c(0x89, 0x50, 0x4e, 0x47)))
  expect_identical(c(readBin(bytes[17:20], "integer", endian = "big"),
                     readBin(bytes[21:24], "integer", endian = "big")), c(1000L, 700L))
})

test_that("the session check catches render errors and crashed servers but not validate()", {
  skip_if_cannot_launch()
  skip_if_no_chrome()
  local_project()
  withr::defer(artifact_browser_close())
  render_error = c("library(shiny)", "ui = fluidPage(plotOutput('p'))",
                   "server = function(input, output, session) {",
                   "  output$p = renderPlot(plot(1:3, 1:2))", "}", "shinyApp(ui, server)")
  res = artifact_session_check(served_record("render", render_error), tempfile(fileext = ".png"))
  skip_if_browser_failed(res)
  expect_false(res$ok)
  expect_true(any(grepl("output error in p", res$messages, fixed = TRUE)))
  crash = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) undefined_helper()",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("crash", crash), tempfile(fileext = ".png"))
  skip_if_browser_failed(res)
  expect_false(res$ok)
  expect_true(any(grepl("undefined_helper", res$messages, fixed = TRUE)))
  valid = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) {",
            "  output$t = renderText(validate(need(FALSE, 'Pick a region')))", "}",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("valid", valid), tempfile(fileext = ".png"))
  skip_if_browser_failed(res)
  expect_true(res$ok)
})

# The built-in shiny type as a record, before builtin:artifacts registers it (Task 9)
shiny_type = function() {
  list(build = artifact_build_shiny, check = artifact_check_shiny,
       launch = artifact_launch_shiny, stop = artifact_stop_handle)
}

# Collect the payloads of an event for the calling test
local_events = function(event, .env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$events = list()
  id = hook_add(event, function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(id), envir = .env)
  seen
}

# An artifact.json with `n` versions (current = n)
seed_artifact = function(id, n = 1L) {
  meta = artifact_meta_new(id, paste("Title of", id))
  meta$versions = lapply(seq_len(n), function(i) {
    dir.create(artifact_version_dir(id, i), recursive = TRUE, showWarnings = FALSE)
    list(n = i, created = artifact_time(), data = list(), session = NULL,
         checks = artifact_checks_json(artifact_checks(parse = TRUE)))
  })
  meta$current = n
  artifact_meta_write(id, meta)
}

# An artifact.json whose version 1 is `lines`, ready for artifact_start()
version_one = function(id, lines, data = character(), envir = new.env()) {
  vdir = build_version(id, lines, data, envir)
  seed_artifact(id)
  vdir
}

test_that("the launcher serves a version on a random loopback port behind the token", {
  skip_if_cannot_launch()
  local_project()
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  h = artifact_launch_shiny(build_version("hello", ok_app, "markers", e), NULL)
  withr::defer(h$stop())
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  expect_true(h$port >= 49152L && h$port <= 65535L)
  expect_true(h$alive())
  expect_true(artifact_wait_http(h$url, h$alive)$ok)
  expect_identical(artifact_http_status(h$url), 200L)
  expect_identical(artifact_http_status(sprintf("http://127.0.0.1:%d/", h$port)), 403L)
  expect_identical(basename(h$log), "app-v001.log")
  h$stop()
  expect_false(h$alive())
  expect_true(is.na(artifact_http_status(h$url, timeout = 1)))
})

test_that("the artifact child gets no registered secret in its environment", {
  skip_if_cannot_launch()
  local_project()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("sk-ant-", "api03-", strrep("FAKEartifact", 4L), "00AA")
  withr::local_envvar(GPTR_ARTIFACT_TEST_KEY = fake, GPTR_TEST_PLAIN = fake)
  secret_register(fake, "GPTR_ARTIFACT_TEST_KEY", source = "test")
  h = artifact_launch_shiny(build_version("env-check", tiny_app), NULL)
  withr::defer(h$stop())
  env = tryCatch(ps::ps_environ(ps::ps_handle(h$pid)), error = function(e) NULL)
  skip_if(is.null(env), "ps cannot read the child's environment here")
  expect_false(any(grepl(fake, env, fixed = TRUE)))
  expect_false(any(c("GPTR_ARTIFACT_TEST_KEY", "GPTR_TEST_PLAIN") %in% names(env)))
})

test_that("a broken app fails at the launch stage with the child's error in the log tail", {
  skip_if_cannot_launch()
  local_project()
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  cnd = expect_error(artifact_launch_shiny(build_version("broken", broken), NULL),
                     class = "gptr_error_artifact")
  expect_identical(cnd$id, "broken")
  expect_identical(cnd$stage, "launch")
  expect_true(any(grepl("no_such_object", cnd$log, fixed = TRUE)))
  expect_match(conditionMessage(cnd), "no_such_object", fixed = TRUE)
  expect_true(file.exists(file.path(artifact_dir("broken"), "run", "app-v001.log")))
  expect_length(list.files(tempdir(), pattern = "^gptr-artifact-broken-"), 0L)
})

test_that("artifact_start() runs the ladder, records the run and keeps the port across versions", {
  skip_if_cannot_launch()
  local_project()
  starts = local_events("artifact_start")
  version_one("ladder", tiny_app)
  withr::defer(artifact_stop("ladder", emit = FALSE))
  h = artifact_start("ladder", 1L, shiny_type())
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "running")
  expect_identical(h$version, 1L)
  expect_identical(h$checks[c("parse", "launch", "http")],
                   list(parse = TRUE, launch = TRUE, http = TRUE))
  expect_true(is.na(h$checks$session))
  expect_identical(format(h)[1], paste0("artifact  ladder  ->  ", h$url,
                                        "   (running in background)"))
  run = json_decode(read_utf8(file.path(artifact_dir("ladder"), "run", "run.json"))$text)
  expect_identical(run$url, h$url)
  meta = artifact_meta_read("ladder")
  expect_identical(as.integer(meta$port), artifact_proc_get("ladder")$port)
  expect_true(meta$versions[[1]]$checks$http)
  expect_identical(job_list("artifact")$id, "artifact:ladder")
  expect_length(starts$events, 1L)
  expect_identical(starts$events[[1]]$url, h$url)
  write_working("ladder", sub("'hi'", "'v2'", tiny_app))
  dir.create(artifact_version_dir("ladder", 2L))
  artifact_build_shiny("ladder", artifact_version_dir("ladder", 2L), list(), NULL)
  port1 = artifact_proc_get("ladder")$port
  h2 = artifact_start("ladder", 2L, shiny_type())
  expect_identical(artifact_proc_get("ladder")$port, port1)
  expect_false(identical(h2$url, h$url))
  expect_identical(artifact_proc_get("ladder")$version, 2L)
})

test_that("an app whose page fails stops at the http stage with status failed", {
  skip_if_cannot_launch()
  local_project()
  bad_page = c("library(shiny)", "ui = function(req) stop('the page failed')",
               "server = function(input, output, session) {}", "shinyApp(ui, server)")
  version_one("page", bad_page)
  withr::defer(artifact_stop("page", emit = FALSE))
  cnd = expect_error(artifact_start("page", 1L, shiny_type()), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "http")
  expect_match(conditionMessage(cnd), "HTTP 500", fixed = TRUE)
  expect_identical(artifact_status("page"), "failed")
  expect_false(artifact_meta_read("page")$versions[[1]]$checks$http)
})

test_that("a launch that cannot start reads failed and keeps its checks", {
  local_project()
  version_one("nolaunch", tiny_app)
  broken_type = list(launch = function(version_dir, ctx) stop("no runtime"),
                     stop = function(handle) NULL)
  cnd = expect_error(artifact_start("nolaunch", 1L, broken_type), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "launch")
  expect_match(conditionMessage(cnd), "no runtime", fixed = TRUE)
  expect_identical(artifact_status("nolaunch"), "failed")
  expect_false(artifact_handle("nolaunch")$checks$launch)
  artifact_stop("nolaunch")
  expect_identical(artifact_status("nolaunch"), "stopped")
})

test_that("relaunch refuses a version that was never stored and a kind without a type", {
  local_project()
  version_one("rel", tiny_app)
  cnd = expect_error(artifact_relaunch("rel", 2L), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "version")
  cnd = expect_error(artifact_type_get("no-such-kind"), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "kind")
})

test_that("missing shiny is a missing_package error naming the feature", {
  local_project()
  local_mocked_bindings(artifact_shiny_available = function() FALSE)
  cnd = expect_error(artifact_launch_shiny(artifact_version_dir("x", 1L), NULL),
                     class = "gptr_error_missing_package")
  expect_identical(cnd$package, "shiny")
  expect_identical(cnd$feature, "artifacts")
})

test_that("the viewer opens only when a human is present (13 C-42)", {
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  withr::local_options(viewer = function(url) seen$urls = c(seen$urls, url))
  local_gptr_options(interactive = FALSE)
  expect_false(artifact_view("http://127.0.0.1:50000/"))
  local_gptr_options(interactive = TRUE)
  expect_true(artifact_view("http://127.0.0.1:50000/"))
  expect_false(artifact_view(NA_character_))
  expect_identical(seen$urls, "http://127.0.0.1:50000/")
})

test_that("the ladder with the session check leaves .Random.seed unchanged (IC-61)", {
  skip_if_cannot_launch()
  local_project()
  version_one("seed", tiny_app)
  withr::defer(artifact_stop("seed", emit = FALSE))
  withr::defer(artifact_browser_close())
  withr::local_seed(7)
  seed = get(".Random.seed", envir = globalenv())
  h = artifact_start("seed", 1L, shiny_type(), session_check = TRUE)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(h$status, "running")
})

test_that("the checkpointer records current before and after an r call (G7 3.1)", {
  local_project()
  seed_artifact("ck", n = 1L)
  r_call = list(id = "c1", name = "r", input = list(code = "peter$app('ck')"))
  expect_null(artifact_ckpt_before(list(id = "c0", name = "write", input = list()), NULL))
  token = artifact_ckpt_before(r_call, NULL)
  expect_identical(token$ck, list(current = 1L, running = FALSE))
  expect_null(artifact_ckpt_after(r_call, NULL, token))
  seed_artifact("ck", n = 2L)
  seed_artifact("new", n = 1L)
  frag = artifact_ckpt_after(r_call, NULL, token)
  expect_identical(frag, list(
    list(id = "ck", current_before = 1L, current_after = 2L, running_before = FALSE,
         running_after = FALSE),
    list(id = "new", current_before = 0L, current_after = 1L, running_before = FALSE,
         running_after = FALSE)))
  expect_identical(artifact_ckpt_describe(frag),
                   c("artifact ck: v001 -> v002", "artifact new: (none) -> v001"))
  back = json_decode(json_encode(frag))
  expect_identical(artifact_ckpt_describe(back), artifact_ckpt_describe(frag))
  expect_null(artifact_ckpt_after(r_call, NULL, NULL))
})

test_that("undo and redo move current and report each artifact", {
  local_project()
  seed_artifact("ck", n = 2L)
  frag = list(list(id = "ck", current_before = 1L, current_after = 2L, running_before = FALSE,
                   running_after = FALSE),
              list(id = "gone", current_before = 0L, current_after = 1L,
                   running_before = FALSE, running_after = FALSE))
  rep = artifact_ckpt_undo(frag, NULL, FALSE)
  expect_identical(rep, c("artifact ck: current version 1",
                          "artifact gone: not restored (it no longer exists)"))
  expect_identical(as.integer(artifact_meta_read("ck")$current), 1L)
  expect_true(dir.exists(artifact_version_dir("ck", 2L)))
  expect_identical(artifact_ckpt_redo(frag[1], NULL, FALSE), "artifact ck: current version 2")
  expect_identical(as.integer(artifact_meta_read("ck")$current), 2L)
  failed = list(restorable = FALSE, reason = "boom")
  expect_identical(artifact_ckpt_undo(failed, NULL, FALSE), "artifacts: not restored (boom)")
  expect_identical(artifact_ckpt_describe(failed), "artifacts: not restored (boom)")
})

test_that("the shiny-bslib skill has its catalog line, house style and a valid example app", {
  f = system.file("gptr", "skills", "shiny-bslib", "SKILL.md", package = "gptr", mustWork = TRUE)
  # The frontmatter is read with yaml (an Import, 03 section 9), not P17's skill_parse(): P17 is
  # outside P23's dependency closure (05: P10, P11, P14, P16)
  lines = readLines(f, encoding = "UTF-8")
  end = which(lines == "---")[2L]
  s = yaml::yaml.load(paste(lines[2L:(end - 1L)], collapse = "\n"))
  expect_identical(s[["name"]], "shiny-bslib")
  expect_identical(paste0("- ", s[["name"]], ": ", s[["description"]], " [skill:", s[["name"]],
                          "/SKILL.md]"),
                   paste0("- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, ",
                          "cards, value boxes) for artifacts. [skill:shiny-bslib/SKILL.md]"))
  txt = paste(lines, collapse = "\n")
  expect_false(grepl("(^|[^A-Za-z0-9_.])str\\(", txt))
  expect_false(grepl("<\\-", txt))
  expect_true(all(utf8ToInt(txt) < 128L))
  expect_match(txt, "peter$app(\"<id>\", data = c(\"obj\"))", fixed = TRUE)
  open = which(lines == "```r")
  expect_length(open, 1L)
  close = which(lines == "```")
  code = lines[(open + 1L):(close[close > open][1L] - 1L)]
  expect_no_error(parse(text = code, keep.source = FALSE))
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  expect_true(artifact_static_check(code)$ok)
})

test_that("builtin:artifacts registers the types, the member, the section and the checkpointer", {
  expect_true(is.function(builtin_artifacts))
  for (kind in c("shiny", "html")) {
    spec = registry_get("artifact_type", kind)
    expect_s3_class(spec, "gptr_artifact_type")
    expect_true(all(vapply(spec[c("build", "check", "launch", "stop")], is.function, NA)))
  }
  app = registry_get("tool", "app")
  expect_identical(app$exposure, "r")
  expect_true(is.function(app$fun) && is.function(app$execute))
  expect_identical(names(formals(app$fun)), c("id", "data", "title", "kind", "check", "launch"))
  fmls = formals(app$fun)
  expect_identical(fmls$data, quote(character()))
  expect_null(fmls$title)
  expect_identical(fmls$kind, "shiny")
  expect_true(fmls$check)
  expect_identical(fmls$launch, quote(interactive()))
  expect_identical(app$risk(list(id = "x"), NULL)$level, 3L)
  sec = registry_get("prompt_section", "artifacts")
  expect_identical(sec$tier, "T0")
  expect_identical(sec$order, 600L)
  expect_identical(sec$budget, 150L)
  ck = registry_get("checkpointer", "artifacts")
  expect_identical(ck$scope, "artifacts")
})

test_that("the artifacts section is architecture 7.3 verbatim and needs shiny", {
  expect_identical(artifact_section_text, paste0(
    "For an interactive view (filters, drill-down, dashboards) build a Shiny app, not HTML/JS: ",
    "write app.R in <artifacts>/<id>/ (the directory is named in <environment>), one file ",
    "ending in shinyApp(ui, server) that uses the objects listed in data by name, then launch ",
    "it in r with peter$app(\"<id>\", data = c(\"obj\")). Read the shiny-bslib skill first. ",
    "Revise app.R with edit and call peter$app() again; check the returned screenshot and errors ",
    "before saying it is done."))
  local_mocked_bindings(artifact_shiny_available = function() TRUE)
  expect_identical(artifact_section(NULL), artifact_section_text)
  local_mocked_bindings(artifact_shiny_available = function() FALSE)
  expect_null(artifact_section(NULL))
})

test_that("peter$app() refuses reserved ids, unknown kinds and a missing working copy", {
  local_project()
  expect_error(peter$app("con"), class = "gptr_error_invalid_argument")
  cnd = expect_error(peter$app("x", kind = "nope", launch = FALSE),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "kind")
  expect_match(conditionMessage(cnd), "html, shiny|shiny, html")
  cnd = expect_error(peter$app("nothing-yet", launch = FALSE), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "parse")
  expect_match(conditionMessage(cnd), ".gptr/artifacts/nothing-yet/app.R", fixed = TRUE)
  cnd = expect_error(peter$app("nothing-yet", check = FALSE, launch = FALSE),
                     class = "gptr_error_artifact")
  expect_identical(cnd$stage, "parse")
  expect_match(conditionMessage(cnd), "working copy in .gptr/artifacts/nothing-yet", fixed = TRUE)
})

test_that("a second peter$app() after an edit creates v002 without touching v001", {
  skip_if_not_installed("shiny")
  local_project()
  markers = data.frame(gene = c("CD14", "LYZ"), p = c(0.01, 0.2))
  here = environment()
  here[["a/b"]] = 1:3 # 05 P23 acceptance 5 names the object a/b
  write_working("explorer", ok_app)
  h1 = peter$app("explorer", data = c("markers", "a/b"), title = "Explorer", launch = FALSE)
  expect_s3_class(h1, "gptr_artifact")
  expect_identical(h1$version, 1L)
  expect_identical(h1$status, "stopped")
  expect_identical(h1$checks$parse, TRUE)
  expect_true(is.na(h1$checks$launch))
  v1 = artifact_version_dir("explorer", 1L)
  expect_true(all(file.exists(file.path(v1, c("app.R", "R/gptr_data.R", "data/001.rds",
                                              "data/002.rds")))))
  md5_v1 = tools::md5sum(list.files(v1, recursive = TRUE, full.names = TRUE))
  meta = artifact_meta_read("explorer")
  expect_identical(meta$title, "Explorer")
  expect_identical(vapply(meta$versions[[1]]$data, function(d) d$name, ""), c("markers", "a/b"))
  expect_identical(meta$versions[[1]]$data[[2]]$file, "data/002.rds")
  expect_identical(meta$versions[[1]]$app_sha,
                   hash_sha256(readBin(file.path(v1, "app.R"), "raw", 1e5)))
  write_working("explorer", sub("'Gene'", "'Gene symbol'", ok_app))
  markers$p = markers$p / 2
  h2 = peter$app("explorer", data = "markers", launch = FALSE)
  expect_identical(h2$version, 2L)
  expect_identical(h2$title, "Explorer")
  expect_identical(tools::md5sum(names(md5_v1)), md5_v1)
  expect_true(any(grepl("Gene symbol", readLines(file.path(artifact_version_dir("explorer", 2L),
                                                           "app.R")))))
  expect_identical(readRDS(file.path(artifact_version_dir("explorer", 2L), "data", "001.rds")),
                   markers)
  expect_identical(as.integer(artifact_meta_read("explorer")$current), 2L)
})

test_that("failed static checks raise gptr_error_artifact and leave no version", {
  skip_if_not_installed("shiny")
  local_project()
  write_working("bad", c(ok_app[1:5], "setwd('/')", ok_app[6]))
  cnd = expect_error(peter$app("bad", launch = FALSE), class = "gptr_error_artifact")
  expect_identical(cnd$id, "bad")
  expect_identical(cnd$stage, "static")
  expect_match(cnd$log, "setwd", fixed = TRUE)
  expect_false(dir.exists(artifact_version_dir("bad", 1L)))
  expect_false(artifact_exists("bad"))
  h = peter$app("bad", check = FALSE, launch = FALSE)
  expect_true(is.na(h$checks$parse))
})

test_that("a failed snapshot removes the version it claimed", {
  local_project()
  write_working("snapfail", ok_app)
  expect_error(peter$app("snapfail", data = "no_such_object", check = FALSE, launch = FALSE),
               class = "gptr_error_invalid_argument")
  expect_false(dir.exists(artifact_version_dir("snapfail", 1L)))
})

test_that("kind = \"html\" wraps page.html in a Shiny app version", {
  local_project()
  markers = data.frame(gene = "CD14")
  write_working("page", "<html><head></head><body><div id='x'></div></body></html>", "page.html")
  h = peter$app("page", data = "markers", kind = "html", launch = FALSE)
  expect_identical(h$kind, "html")
  expect_identical(basename(h$path), "page.html")
  vdir = artifact_version_dir("page", 1L)
  expect_true(all(file.exists(file.path(vdir, c("app.R", "page.html", "data/001.rds")))))
  expect_identical(artifact_meta_read("page")$kind, "html")
  expect_identical(artifact_meta_read("page")$versions[[1]]$kind, "html")
})

test_that("the tool form returns the handle's lines and attaches the screenshot to the r call", {
  local_project()
  e = new.env()
  e$markers = data.frame(gene = "CD14")
  write_working("tool", ok_app)
  res = artifact_member_execute(list(id = "tool", data = list("markers"), check = FALSE,
                                     launch = FALSE),
                                list(session = NULL, envir = e))
  expect_s3_class(res, "gptr_tool_result")
  expect_s3_class(res$value, "gptr_artifact")
  expect_identical(res$content[[1]]$text, paste(format(res$value), collapse = "\n"))
  expect_identical(res$details$status, "stopped")
  expect_identical(res$details$path, ".gptr/artifacts/tool/app.R")
  expect_identical(length(res$content), 1L)
  png = file.path(artifact_dir("tool"), "shot.png")
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), png)
  block = artifact_screenshot_block(list(screenshot = png))
  expect_identical(block$source, "screenshot")
  expect_identical(c(block$width, block$height), c(1000L, 700L))
  expect_false(artifact_attach_image(block))
  gptr_r_call = structure(new.env(), class = "gptr_r_call")
  gptr_r_call$images = list()
  gptr_r_call$dropped = 0L
  local_gptr_options(r_max_images = 1L)
  attach_twice = function() c(artifact_attach_image(block), artifact_attach_image(block))
  expect_identical(attach_twice(), c(TRUE, FALSE))
  expect_length(gptr_r_call$images, 1L)
  expect_identical(gptr_r_call$dropped, 1L)
})

test_that("peter$app() launches through the ladder and keeps .Random.seed (IC-61)", {
  skip_if_cannot_launch()
  local_project()
  withr::defer(artifact_browser_close())
  markers = data.frame(gene = c("CD14", "LYZ"))
  write_working("live", ok_app)
  withr::local_seed(11)
  seed = get(".Random.seed", envir = globalenv())
  h = peter$app("live", data = "markers", launch = TRUE, check = TRUE)
  withr::defer(artifact_stop("live", emit = FALSE))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(h$status, "running")
  expect_true(h$checks$parse && h$checks$launch && h$checks$http)
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  pid = artifact_proc_get("live")$pid
  ct = proc_create_time(pid)
  artifact_stop("live")
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_identical(artifact_handle("live")$status, "stopped")
})

test_that("undo relaunches the version that was running, on the same port", {
  skip_if_cannot_launch()
  local_project()
  write_working("rew", tiny_app)
  peter$app("rew", launch = TRUE, check = FALSE)
  withr::defer(artifact_stop("rew", emit = FALSE))
  port = artifact_proc_get("rew")$port
  token = artifact_ckpt_before(list(name = "r"), NULL)
  write_working("rew", sub("'hi'", "'v2'", tiny_app))
  peter$app("rew", launch = TRUE, check = FALSE)
  frag = artifact_ckpt_after(list(name = "r"), NULL, token)
  expect_identical(frag[[1]][c("current_before", "current_after", "running_before",
                               "running_after")],
                   list(current_before = 1L, current_after = 2L, running_before = TRUE,
                        running_after = TRUE))
  expect_identical(artifact_ckpt_undo(frag, NULL, FALSE),
                   "artifact rew: current version 1 (relaunched)")
  expect_identical(artifact_proc_get("rew")$version, 1L)
  expect_identical(artifact_proc_get("rew")$port, port)
  expect_identical(artifact_status("rew"), "running")
})
