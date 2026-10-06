# Tests of R/artifact-registry.R (P23). Tests that start processes skip on CRAN.

# An artifact.json with `n` versions (current = n); returns the id invisibly
seed_artifact = function(id, n = 1L, kind = "shiny") {
  meta = artifact_meta_new(id, paste("Title of", id), kind)
  meta$versions = lapply(seq_len(n), function(i) {
    dir.create(artifact_version_dir(id, i), recursive = TRUE, showWarnings = FALSE)
    list(n = i, created = artifact_time(), app_sha = NULL, data = list(), session = NULL,
         checks = artifact_checks_json(artifact_checks(parse = TRUE)))
  })
  meta$current = as.integer(n)
  artifact_meta_write(id, meta)
  invisible(id)
}

# A sleeping R child with a handle shaped like the launcher's (closures over the process only).
# R_TESTS is blanked: R CMD check sets it to a relative startup file that R's base profile
# sources in every R child, which would end the child at once (as callr::rcmd_safe_env() does)
sleeper_handle = function(.env = parent.frame()) {
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
                            env = c("current", R_TESTS = ""), cleanup = TRUE,
                            cleanup_tree = TRUE)
  withr::defer(kill_all(p, grace = 0), envir = .env)
  list(url = "http://127.0.0.1:50000/?gptr_token=ab", pid = p$get_pid(), port = 50000L,
       alive = function() p$is_alive(), stop = function() kill_all(p, grace = 1))
}

sleeper_type = list(stop = function(handle) handle$stop())

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

test_that("a record's status is running, then stopped after a requested stop (IC-60)", {
  skip_on_cran()
  local_project()
  seed_artifact("rec")
  stops = local_events("artifact_stop")
  expect_identical(artifact_status("rec"), "stopped")
  rec = artifact_record_new("rec", 1L, sleeper_type, sleeper_handle())
  assign("rec", rec, envir = artifact_state$procs)
  withr::defer(if (!is.null(artifact_proc_get("rec"))) artifact_stop("rec", emit = FALSE))
  expect_identical(artifact_status("rec"), "running")
  expect_false(is.na(rec$create_time))
  artifact_job_add("rec", "Title of rec", rec$pid)
  expect_identical(job_list("artifact")$id, "artifact:rec")
  expect_identical(job_list("artifact")$status, "running")
  expect_true(artifact_stop("rec"))
  expect_false(isTRUE(pid_alive(rec$pid, rec$create_time)))
  expect_identical(artifact_status("rec"), "stopped")
  expect_identical(nrow(job_list("artifact")), 0L)
  expect_length(stops$events, 1L)
  expect_identical(stops$events[[1]]$id, "rec")
  expect_identical(stops$events[[1]]$reason, "user")
  expect_identical(stops$events[[1]]$version, 1L)
  expect_false(artifact_stop("rec"))
})

test_that("a process that ends without a stop request reads failed", {
  skip_on_cran()
  local_project()
  seed_artifact("crash")
  h = sleeper_handle()
  rec = artifact_record_new("crash", 1L, sleeper_type, h)
  assign("crash", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("crash", emit = FALSE))
  ps::ps_kill(ps::ps_handle(h$pid))
  deadline = Sys.time() + 10
  while (h$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_identical(artifact_status("crash"), "failed")
})

test_that("child output reaches the log in complete lines, redacted, and the raw file goes", {
  local_project()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("sk-ant-", "api03-", strrep("FAKEartifact", 4L), "00AA")
  secret_register(fake, "GPTR_ARTIFACT_TEST_KEY", source = "test")
  raw = withr::local_tempfile(fileext = ".log")
  log = file.path(artifact_dir("logs"), "run", "app-v001.log")
  rec = artifact_log_new(raw, log)
  write_bytes = function(text) {
    con = file(raw, "ab")
    on.exit(close(con))
    writeBin(charToRaw(text), con)
  }
  write_bytes(paste0("Listening on http://127.0.0.1:5000\nkey=", fake, "\npartial"))
  artifact_log_sync(rec)
  got = readLines(log, encoding = "UTF-8")
  expect_identical(got[1], "Listening on http://127.0.0.1:5000")
  expect_false(any(grepl(fake, got, fixed = TRUE)))
  expect_false(any(grepl("partial", got, fixed = TRUE)))
  write_bytes(" line\nWarning: Error in f: boom\n")
  artifact_log_sync(rec, final = TRUE)
  got = readLines(log, encoding = "UTF-8")
  expect_true("partial line" %in% got)
  expect_identical(artifact_log_tail(log, 1L), "Warning: Error in f: boom")
  expect_false(file.exists(raw))
  expect_null(rec$raw)
  expect_identical(artifact_tail_text(character(), log), "")
  expect_match(artifact_tail_text("x", log), "Last lines of .gptr/artifacts/logs/run/app-v001.log",
               fixed = TRUE)
})

test_that("run.json carries the contract fields and the owner; the handle reads both tables", {
  skip_on_cran()
  local_project()
  seed_artifact("hand", n = 2L)
  expect_identical(artifact_handle("hand")$status, "stopped")
  expect_true(is.na(artifact_handle("hand")$url))
  rec = artifact_record_new("hand", 2L, sleeper_type, sleeper_handle())
  rec$checks = artifact_checks(TRUE, TRUE, TRUE, NA, "HTTP-only check")
  assign("hand", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("hand", emit = FALSE))
  artifact_run_write(rec)
  info = json_decode(read_utf8(file.path(artifact_dir("hand"), "run", "run.json"))$text)
  expect_true(all(c("pid", "port", "url", "version", "started") %in% names(info)))
  expect_identical(as.integer(info$parent_pid), Sys.getpid())
  h = artifact_handle("hand")
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "running")
  expect_identical(h$version, 2L)
  expect_identical(h$url, rec$url)
  expect_identical(h$title, "Title of hand")
  expect_identical(h$checks$messages, "HTTP-only check")
  expect_identical(basename(h$path), "app.R")
  artifact_stop("hand", emit = FALSE)
  expect_false(file.exists(file.path(artifact_dir("hand"), "run", "run.json")))
  expect_error(artifact_handle("absent"), class = "gptr_error_invalid_argument")
})

test_that("the orphan sweep kills children of dead owners and spares the rest", {
  skip_on_cran()
  local_project()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  plant = function(id, pid, create_time, owner) {
    seed_artifact(id)
    dir.create(file.path(artifact_dir(id), "run"), showWarnings = FALSE)
    write_utf8(file.path(artifact_dir(id), "run", "run.json"),
               json_encode(list(pid = pid, port = 50001L, url = "http://127.0.0.1:50001/",
                                version = 1L, started = artifact_time(),
                                create_time = create_time, parent_pid = owner)))
  }
  orphan = sleeper_handle()
  plant("orphan", orphan$pid, proc_create_time(orphan$pid), dead$get_pid())
  reused = sleeper_handle()
  plant("reused", reused$pid, proc_create_time(reused$pid) - 100, dead$get_pid())
  owned = sleeper_handle()
  owner = sleeper_handle()
  plant("owned", owned$pid, proc_create_time(owned$pid), owner$pid)
  expect_identical(artifact_sweep(), "orphan")
  deadline = Sys.time() + 10
  while (orphan$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_false(orphan$alive())
  expect_true(reused$alive())
  expect_true(owned$alive())
  expect_false(file.exists(file.path(artifact_dir("orphan"), "run", "run.json")))
  expect_true(file.exists(file.path(artifact_dir("owned"), "run", "run.json")))
  expect_true(artifact_state$swept)
})

tiny_app = c("library(shiny)", "ui = fluidPage('hi')", "server = function(input, output) {}",
             "shinyApp(ui, server)")

# Write a model-written working copy of an artifact
write_working = function(id, lines, file = "app.R") {
  dir = artifact_dir(id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_utf8(file.path(dir, file), lines)
  file.path(dir, file)
}

skip_if_cannot_launch = function() {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
}

test_that("gptr_artifacts() lists nothing when no artifact exists", {
  local_project()
  out = gptr_artifacts()
  expect_s3_class(out, c("gptr_artifacts", "gptr_listing", "data.frame"))
  expect_identical(names(out), c("id", "title", "version", "status", "url", "pid", "bytes",
                                 "path"))
  expect_identical(nrow(out), 0L)
  expect_output(print(out), "# 0 rows", fixed = TRUE)
})

test_that("gptr_artifacts() lists every artifact of the workspace", {
  local_project()
  seed_artifact("alpha", n = 2L)
  seed_artifact("beta")
  writeLines("x", file.path(artifact_version_dir("alpha", 1L), "app.R"))
  dir.create(artifact_dir("conflicted"))
  writeLines(c("<<<<<<< HEAD", "{\"id\": \"conflicted\"}"), artifact_meta_path("conflicted"))
  out = gptr_artifacts()
  expect_match(attr(out, "footer"), "not readable (skipped): conflicted", fixed = TRUE)
  expect_identical(out$id, c("alpha", "beta"))
  expect_identical(out$title, c("Title of alpha", "Title of beta"))
  expect_identical(out$version, c(2L, 1L))
  expect_identical(out$status, c("stopped", "stopped"))
  expect_true(all(is.na(out$url)) && all(is.na(out$pid)))
  expect_true(all(out$bytes > 0))
  expect_identical(basename(out$path), c("app.R", "app.R"))
})

test_that("gptr_artifacts() validates its arguments", {
  local_project()
  seed_artifact("alpha")
  expect_error(gptr_artifacts("absent"), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("con"), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts(stop = TRUE), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts(version = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", stop = TRUE, version = 1),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", version = 1.5), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", version = 3), "has no stored version 3",
               class = "gptr_error_invalid_argument")
  seed_artifact("empty", n = 0L)
  expect_error(gptr_artifacts("empty", open = TRUE), "call peter$app() first", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  h = gptr_artifacts("alpha")
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "stopped")
  expect_invisible(gptr_artifacts("alpha", stop = TRUE))
})

test_that("version = relaunches a stored version; stop = TRUE leaves no process", {
  skip_if_cannot_launch()
  local_project()
  stops = local_events("artifact_stop")
  write_working("rel", tiny_app)
  peter$app("rel", check = FALSE, launch = FALSE)
  write_working("rel", sub("'hi'", "'v2'", tiny_app))
  peter$app("rel", check = FALSE, launch = FALSE)
  withr::defer(artifact_stop("rel", emit = FALSE))
  h = gptr_artifacts("rel", version = 1)
  expect_identical(h$status, "running")
  expect_identical(h$version, 1L)
  expect_identical(as.integer(artifact_meta_read("rel")$current), 1L)
  out = gptr_artifacts()
  expect_identical(out$status, "running")
  expect_identical(out$url, h$url)
  pid = out$pid
  expect_true(is.integer(pid) && !is.na(pid))
  ct = proc_create_time(pid)
  expect_identical(job_list("artifact")$status, "running")
  stopped = gptr_artifacts("rel", stop = TRUE)
  expect_identical(stopped$status, "stopped")
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_false(file.exists(file.path(artifact_dir("rel"), "run", "run.json")))
  expect_identical(nrow(job_list("artifact")), 0L)
  expect_identical(gptr_artifacts()$status, "stopped")
  expect_identical(vapply(stops$events, function(e) e$reason, ""), "user")
})

test_that("open = TRUE relaunches a stopped artifact; the viewer opens only for a human", {
  skip_if_cannot_launch()
  local_project()
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  withr::local_options(viewer = function(url) seen$urls = c(seen$urls, url))
  write_working("viewed", tiny_app)
  peter$app("viewed", check = FALSE, launch = FALSE)
  withr::defer(artifact_stop("viewed", emit = FALSE))
  local_gptr_options(interactive = FALSE)
  h = gptr_artifacts("viewed", open = TRUE)
  expect_identical(h$status, "running")
  expect_identical(seen$urls, character())
  local_gptr_options(interactive = TRUE)
  gptr_artifacts("viewed", open = TRUE)
  expect_identical(seen$urls, h$url)
  expect_identical(artifact_proc_get("viewed")$url, h$url)
})

test_that("unloading the package stops every artifact of the process", {
  skip_if_cannot_launch()
  local_project()
  write_working("unl", tiny_app)
  peter$app("unl", check = FALSE, launch = TRUE)
  pid = artifact_proc_get("unl")$pid
  ct = proc_create_time(pid)
  artifact_unload()
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_null(artifact_proc_get("unl"))
  expect_null(artifact_state$browser)
})

# NS-8 (02-north-star-examples.md section 8; architecture 10.6) on the fake provider
explorer_app = c(
  "library(shiny)",
  "ui = fluidPage(",
  "  titlePanel('Marker explorer'),",
  "  sidebarLayout(sidebarPanel(textInput('gene', 'Gene search')),",
  "                mainPanel(plotOutput('volcano'), tableOutput('table')))",
  ")",
  "server = function(input, output, session) {",
  "  shown = reactive(markers[grepl(input$gene, markers$gene, ignore.case = TRUE), ])",
  "  output$volcano = renderPlot(plot(markers$avg_log2FC, -log10(markers$p_val_adj),",
  "                                   xlab = 'log2 fold change', ylab = '-log10 adjusted p'))",
  "  output$table = renderTable(head(shown(), 20))",
  "}",
  "shinyApp(ui, server)"
)

ns08_prompt = paste("Build me an explorer for the marker table with a gene search box and a",
                    "volcano plot")

ns08_markers = function() {
  data.frame(gene = c("S100A9", "LYZ", "CD14", "MS4A1", "CD79A"),
             avg_log2FC = c(2.41, 3.05, 1.87, 2.9, 2.2),
             p_val_adj = c(1e-280, 3.4e-276, 9.8e-247, 1e-120, 2e-98))
}

test_that("NS-8: the agent writes app.R, peter$app() launches it, the renderer prints the line", {
  skip_if_cannot_launch()
  root = local_project()
  withr::defer(artifact_stop("marker-explorer", emit = FALSE))
  withr::defer(artifact_browser_close())
  starts = local_events("artifact_start")
  e = new.env()
  e$markers = ns08_markers()
  code = paste0("a = peter$app(\"marker-explorer\", data = \"markers\", ",
                "title = \"Marker explorer\", launch = TRUE)\na")
  fake = local_fake_provider(list(
    fake_tool("write", path = ".gptr/artifacts/marker-explorer/app.R",
              content = paste(explorer_app, collapse = "\n")),
    fake_tool("r", code = code),
    "The marker explorer is running."
  ))
  local_gptr_options(verbose = 2L)
  invisible(utils::capture.output(peter(prompt = ns08_prompt, model = fake, envir = e,
                                       mode = auto)))
  expect_true(file.exists(file.path(root, ".gptr", "artifacts", "marker-explorer", "app.R")))
  expect_length(starts$events, 1L)
  ev = starts$events[[1]]
  expect_identical(ev$id, "marker-explorer")
  expect_identical(ev$version, 1L)
  expect_match(ev$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  line = paste0("artifact  marker-explorer  ->  ", ev$url, "   (running in background)")
  # The event fired inside the model's r evaluation, whose output P09 captures (tee only with a
  # human), so the payload goes through the registered hooks again, where P14's renderer prints
  printed = utils::capture.output(invisible(ev_dispatch("artifact_start", ev)))
  expect_true(line %in% printed)
  seen = msg_text(fake_requests(fake)[[3L]]$last_results[[1L]])
  expect_match(seen, line, fixed = TRUE)
  expect_match(seen, "checks: parse ok | launch ok | http ok", fixed = TRUE)
  entries = session_data(gptr_last())$entries
  r_results = Filter(function(x) {
    identical(x$type, "message") && identical(x$message$role, "tool_result") &&
      identical(x$message$tool_name, "r")
  }, entries)
  expect_identical(unlist(r_results[[1]]$message$details$artifacts),
                   ".gptr/artifacts/marker-explorer/app.R")
  art = Filter(function(x) identical(x$custom_type, "gptr.artifact"), entries)
  expect_length(art, 1L)
  expect_identical(art[[1]]$data$id, "marker-explorer")
  expect_identical(as.integer(art[[1]]$data$version), 1L)
  expect_identical(art[[1]]$data$status, "running")
  expect_s3_class(e$a, "gptr_artifact")
  pid = artifact_proc_get("marker-explorer")$pid
  ct = proc_create_time(pid)
  gptr_artifacts("marker-explorer", stop = TRUE)
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_identical(gptr_artifacts()$status, "stopped")
})

test_that("a broken app returns the child's error to the model", {
  skip_if_cannot_launch()
  local_project()
  withr::defer(artifact_stop("broken", emit = FALSE))
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  fake = local_fake_provider(list(
    fake_tool("write", path = ".gptr/artifacts/broken/app.R",
              content = paste(broken, collapse = "\n")),
    fake_tool("r", code = "a = peter$app(\"broken\", launch = TRUE)"),
    "The app did not start."
  ))
  peter("Build an app", model = fake, envir = new.env(), mode = auto)
  seen = msg_text(fake_requests(fake)[[3L]]$last_results[[1L]])
  expect_match(seen, "stage launch", fixed = TRUE)
  expect_match(seen, "no_such_object", fixed = TRUE)
  expect_identical(gptr_artifacts("broken")$status, "failed")
})
