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
                  stdout = raw, stderr = "2>&1", supervise = TRUE, package = FALSE,
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
  expect_false(res$ok)
  expect_true(any(grepl("output error in p", res$messages, fixed = TRUE)))
  crash = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) undefined_helper()",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("crash", crash), tempfile(fileext = ".png"))
  expect_false(res$ok)
  expect_true(any(grepl("undefined_helper", res$messages, fixed = TRUE)))
  valid = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) {",
            "  output$t = renderText(validate(need(FALSE, 'Pick a region')))", "}",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("valid", valid), tempfile(fileext = ".png"))
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

# An artifact.json whose version 1 is `lines`, ready for artifact_start()
version_one = function(id, lines, data = character(), envir = new.env()) {
  vdir = build_version(id, lines, data, envir)
  meta = artifact_meta_new(id, paste("Title of", id))
  meta$versions = list(list(n = 1L, created = artifact_time(), data = list(), session = NULL,
                            checks = artifact_checks_json(artifact_checks(parse = TRUE))))
  meta$current = 1L
  artifact_meta_write(id, meta)
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
