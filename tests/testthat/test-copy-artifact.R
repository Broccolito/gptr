# Copy-safety rows of the artifact area (architecture 6.4 R1, R2, R4, R7; contract 1.3; 05 P23
# acceptance 3): snapshotting an object into an artifact leaves it editable in place, whether the
# user or model code calls peter$app(). Each row runs in a fresh Rscript through expect_no_copy()
# and stops unless the snapshot was written (so that zero copies cannot pass vacuously).

copy_setup = c(
  "big = runif(5e6)",
  "root = file.path(tempdir(), 'copy-artifact')",
  "dir.create(file.path(root, '.gptr', 'artifacts', 'big-view'), recursive = TRUE)",
  "writeLines(c('library(shiny)', 'ui = fluidPage(textOutput(\"n\"))',",
  "             'server = function(input, output, session) output$n = renderText(length(big))',",
  "             'shinyApp(ui, server)'),",
  "           file.path(root, '.gptr', 'artifacts', 'big-view', 'app.R'))",
  "options(gptr.project_root = root)",
  "snap = file.path(root, '.gptr', 'artifacts', 'big-view', 'v001', 'data', '001.rds')"
)

test_that("peter$app() called by the user snapshots big and leaves it editable in place", {
  skip_if_not_installed("shiny")
  expect_no_copy(setup = copy_setup,
                 action = c("a = peter$app(\"big-view\", data = \"big\", launch = FALSE)",
                            "stopifnot(file.exists(snap))"),
                 edit = "big[1] = 0", object = "big", allow = 0L,
                 label = "peter$app() snapshot by the user")
})

test_that("peter$app() called by model code snapshots big and leaves it editable in place", {
  skip_if_not_installed("shiny")
  action = c(
    "app_code = 'a = peter$app(\"big-view\", data = \"big\", launch = FALSE)'",
    "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = app_code)), 'done'))",
    "s = peter('Snapshot big into the app', model = fake, mode = 'auto', envir = globalenv())",
    "stopifnot(file.exists(snap))"
  )
  expect_no_copy(setup = copy_setup, action = action, edit = "big[1] = 0", object = "big",
                 allow = 0L, label = "peter$app() snapshot by model code")
})
