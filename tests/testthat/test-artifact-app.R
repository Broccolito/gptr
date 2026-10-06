# Tests of R/artifact-app.R (plan P23)

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
