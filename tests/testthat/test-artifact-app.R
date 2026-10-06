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
