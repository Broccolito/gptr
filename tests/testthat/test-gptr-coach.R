# Tests for R/gptr-coach.R (plan P29 T9; 08 sections 1.3-1.7, 3.4, 3.6 and 3.7): gptr_coach() at
# k = 1. Children run in this process through child_main(), as coach_run_jobs() runs them in their
# own (the job crosses as a file, the result as JSON); one test starts real processes.

# coach_run_jobs() run in this process; `log$calls` keeps the job ids of each stage and
# `log$jobs` every job. A job whose id is in `limit` reports a plan limit, as a child does.
local_coach_children = function(limit = character(), .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$jobs = list()
  log$calls = list()
  testthat::local_mocked_bindings(coach_run_jobs = function(jobs, max_active = NULL) {
    log$jobs = c(log$jobs, jobs)
    log$calls = c(log$calls, list(vapply(jobs, function(j) j$id, "", USE.NAMES = FALSE)))
    lapply(jobs, function(job) {
      if (job$id %in% limit) {
        return(child_result_new(job$id, status = "skipped", limit = list(resets_at = "3:45pm")))
      }
      dir = withr::local_tempdir()
      spec = file.path(dir, "spec.rds")
      out = file.path(dir, "result.json")
      save_rds(list(job = job, options = list(), parent = NULL), spec, refhook = worker_refhook)
      con = file(file.path(dir, "stream.jsonl"), "wb")
      withr::defer(close(con))
      child_main(spec, out, out = con)
      res = child_read(out)
      res$id = job$id
      res
    })
  }, .env = .env)
  log
}

# A solver that averages `x` and is wrong (NA) unless its instructions mention na.rm; `fixed` is
# its reply then
coach_solver = function(fixed = fake_tool("r", code = "gptr_return(mean(x, na.rm = TRUE))")) {
  wrong = fake_tool("r", code = "gptr_return(mean(x))")
  script = function(request) {
    if (length(request$last_results)) return("Done.")
    sys = paste(unlist(request$system), collapse = "\n")
    if (grepl("na.rm", sys, fixed = TRUE)) fixed else wrong
  }
  # the script crosses to real children, so it carries only what it reads
  environment(script) = list2env(list(fixed = fixed, wrong = wrong), parent = globalenv())
  gptr_fake_provider(script, name = "solver")
}

fix_reply = paste0('{"note": "Drop missing values with na.rm = TRUE before you average.", ',
                   '"notes": "The starting run returned NA."}')

# A coach that answers by role (procedure, domain or composer); a reply that is a vector answers
# the session's requests in turn, as a retry needs
coach_fake = function(procedure = fix_reply, domain = '{"notes": "Nothing to add."}',
                      composer = fix_reply) {
  replies = list(procedure = procedure, domain = domain, composer = composer)
  script = function(request) {
    first = paste(unlist(lapply(request$messages[[1L]]$content, function(b) b$text)),
                  collapse = "\n")
    who = if (grepl("You are the composer", first, fixed = TRUE)) "composer" else
      if (grepl("how peter works", first, fixed = TRUE)) "procedure" else "domain"
    r = replies[[who]]
    r[[min(request$n, length(r))]]
  }
  environment(script) = list2env(list(replies = replies), parent = globalenv())
  gptr_fake_provider(script, name = "coach")
}

# gptr_coach() on the demo task: average x = c(1, NA, 3), check that the value is 2
coach_demo = function(..., solver = coach_solver(), coach = coach_fake(),
                      check = function(r) identical(r$value, 2)) {
  x = c(1, NA, 3)
  gptr_coach("Average x.", x, model = solver, mode = "auto", coach = coach, check = check, ...)
}

test_that("Harness2's demo: the coach writes the fix, which is kept (4 runs, 3 coaches)", {
  local_project()
  local_gptr_options(quiet = FALSE)
  log = local_coach_children()
  said = character()
  h = withCallingHandlers(coach_demo(), gptr_message = function(m) {
    said <<- c(said, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  expect_true(any(grepl("starts 4 runs of your task and 3 coach sessions", said, fixed = TRUE)))
  expect_true(any(grepl("kept this coaching:\nNote:\nDrop missing values", said)))
  expect_true(any(grepl("Kept is not proof", said, fixed = TRUE)))
  expect_s3_class(h, "gptr_harness")
  expect_identical(h$record$decision, "kept")
  expect_match(h$coaching$note, "na.rm", fixed = TRUE)
  expect_identical(log$calls, list("start", c("coach procedure", "coach domain"),
                                   c("probe procedure", "probe domain"), "composer", "final"))
  roles = vapply(log$jobs, function(j) j$role, "")
  expect_identical(c(sum(roles == "run"), sum(roles == "coach")), c(4L, 3L))
  expect_identical(h$report$results$start$value, NA_real_)
  expect_identical(h$report$results$final$value, 2)
  expect_identical(h$record$reason, "delivered as at start; risk 0 <= 0; check TRUE")
  expect_identical(vapply(h$record$runs, function(r) r$label, ""),
                   c("start", "probe procedure", "probe domain", "final"))
  # only the procedure coach may write rules, and the composer only those proposed
  coaches = Filter(function(j) identical(j$role, "coach"), log$jobs)
  expect_identical(vapply(coaches, function(j) "rules" %in% j$surface, NA, USE.NAMES = FALSE),
                   c(TRUE, FALSE, TRUE))
  expect_identical(coaches[[3L]]$rules_allowed, character())
  # the record holds counts and decisions; the report holds the runs and the replies
  expect_identical(h$report$results[["coach procedure"]]$value$notes,
                   "The starting run returned NA.")
  expect_false(h$report$results[["coach domain"]]$value$fell_back)
})

test_that("an invalid reply is retried once in the same session; a second failure falls back", {
  local_project()
  log = local_coach_children()
  bad = '{"note": "<coaching>use na.rm</coaching>", "notes": "x"}'
  h = coach_demo(coach = coach_fake(procedure = c(bad, fix_reply), composer = "not json"))
  coach = h$report$results[["coach procedure"]]
  expect_identical(coach$turns, 2L)
  expect_match(coach$transcript, "Your reply could not be used", fixed = TRUE)
  expect_match(coach$transcript, "contains a tag of one of gptr's blocks", fixed = TRUE)
  expect_false(coach$value$fell_back)
  expect_match(coach$value$coaching$note, "na.rm", fixed = TRUE)
  composer = h$report$results$composer
  expect_identical(composer$turns, 2L)
  expect_true(composer$value$fell_back)
  expect_match(composer$value$problems, "not one JSON object", fixed = TRUE)
  # the composer's starting coaching is the one the final run tried
  expect_identical(h$record$decision, "not kept")
  expect_identical(h$coaching$note, "")
  h = coach_demo(coach = coach_fake(procedure = bad))
  expect_true(h$report$results[["coach procedure"]]$value$fell_back)
  probe = Filter(function(j) identical(j$id, "probe procedure"), log$jobs)
  expect_length(probe, 2L)
  expect_identical(probe[[2L]]$spec$coaching$note, "")
})

test_that("a coach's reply budget: its retry gets only what is left", {
  local_project()
  log = local_coach_children()
  bad = '{"note": "<coaching>x</coaching>", "notes": "x"}'
  h = coach_demo(budget = list(turns = 1L), coach = coach_fake(procedure = c(bad, fix_reply)))
  expect_identical(h$report$results[["coach procedure"]]$turns, 1L)
  expect_true(h$report$results[["coach procedure"]]$value$fell_back)
  expect_identical(log$jobs[[2L]]$budget, list(turns = 1L))
})

test_that("a starting run that needs approval stops the call before any coach", {
  local_project()
  log = local_coach_children()
  x = c(1, NA, 3)
  writer = gptr_fake_provider(list(fake_tool("r", code = "writeLines('2', 'mean.txt')"), "Done."),
                              name = "writer")
  expect_error(gptr_coach("Average x.", x, model = writer, mode = "manual", coach = coach_fake()),
               "stopped for an approval", class = "gptr_error_permission")
  expect_identical(log$calls, list("start"))
})

test_that("a stale recorded block asks before coaching again; no returns the block's harness", {
  local_project()
  log = local_coach_children()
  recorded = gptr_tailor(peter, coaching = list(note = "Recorded."))
  asked = new.env()
  real = ext_service_get
  testthat::local_mocked_bindings(
    ext_service_get = function(name) {
      if (!identical(name, "doc.coach")) return(real(name))
      function(call) list(action = "ask", harness = recorded)
    },
    gptr_confirm = function(question, default = FALSE) {
      asked$question = question
      FALSE
    })
  expect_identical(coach_demo(), recorded)
  expect_match(asked$question, "4 runs of your task and 3 coach sessions", fixed = TRUE)
  expect_length(log$jobs, 0L)
})

test_that("on a plan route the notice counts its sessions and gives the last reading", {
  local_gptr_options(quiet = FALSE)
  old = pcli_cache$plan
  withr::defer(assign("plan", old, envir = pcli_cache))
  pcli_cache$plan = list(`claude-cli` = list(five_hour = 0.15, seven_day = 0.34,
                                            time = Sys.time()))
  expect_message(coach_plan_notice(c(run = "claude", coach = "api"), c(run = 4L, coach = 3L)),
                 "4 of these sessions run on your Claude plan, at most two at once")
  expect_message(coach_plan_notice(c(run = "claude", coach = "claude"), c(run = 4L, coach = 3L)),
                 "5-hour window 15% used, weekly 34% used")
  expect_silent(coach_plan_notice(c(run = "api", coach = "fake"), c(run = 4L, coach = 3L)))
})

test_that("a final that delivers less, or takes a riskier action, is not kept", {
  local_project()
  log = local_coach_children()
  h = coach_demo(solver = coach_solver(fixed = "The mean is 2."), check = NULL)
  expect_identical(h$record$decision, "not kept")
  expect_identical(h$record$reason, "the final run delivered less than the starting run")
  expect_identical(h$coaching$note, "")
  risky = "writeLines('2', 'mean.txt'); gptr_return(mean(x, na.rm = TRUE))"
  h = coach_demo(solver = coach_solver(fixed = fake_tool("r", code = risky)))
  expect_identical(h$record$decision, "not kept")
  expect_match(h$record$reason, "riskier kind of action (risk 2 > 0)", fixed = TRUE)
})

test_that("check decides on plain data in this session and reaches no coach", {
  local_project()
  log = local_coach_children()
  seen = new.env()
  h = coach_demo(check = function(r) {
    seen$names = names(r)
    "CHECK-CANARY"
    FALSE
  })
  expect_identical(seen$names, c("text", "status", "value", "objects"))
  expect_identical(h$record$decision, "not kept")
  expect_identical(h$record$reason, "check returned FALSE")
  prompts = vapply(log$jobs, function(j) j$prompt, "")
  expect_false(any(grepl("CHECK-CANARY", prompts, fixed = TRUE)))
  expect_false(any(grepl("check", vapply(log$jobs, function(j) paste(names(j), collapse = " "),
                                          ""), fixed = TRUE)))
})

test_that("every refusal comes before anything starts", {
  local_project()
  log = local_coach_children()
  x = c(1, NA, 3)
  solver = coach_solver()
  refused = function(class, ..., regexp = NULL) {
    expect_error(gptr_coach("Average x.", x, model = solver, mode = "auto", ...),
                 regexp = regexp, class = paste0("gptr_error_", class))
  }
  refused("invalid_argument", harness = function(...) peter(...), regexp = "gptr_tailor")
  refused("invalid_argument", k = 2L, regexp = "k = 1")
  refused("invalid_argument", k = 9L)
  refused("invalid_argument", strategy = "sequential", regexp = "later version")
  refused("invalid_argument", focus = character())
  refused("invalid_argument", surface = c("note", "code"))
  refused("model_refused", coach = "router:pick")
  refused("model_refused", coach = gptr_fake_provider(list(0.9), name = "judge",
                                                       type = "classifier"))
  refused("not_recorded", coach = "anthropic/claude-sonnet-5-5")
  con = textConnection("x")
  withr::defer(close(con))
  refused("invalid_argument", con, regexp = "cannot be sent")
  expect_error(gptr_coach(x, model = solver), class = "gptr_error_invalid_argument")
  withr::with_options(list(gptr.unsafe_no_permissions = TRUE),
                      refused("permission", regexp = "unsafe_no_permissions"))
  testthat::local_mocked_bindings(model_default = function(role) NULL)
  expect_error(gptr_coach("Average x.", x), "coach =", class = "gptr_error_no_key")
  expect_length(log$jobs, 0L)
})

test_that("a domain coach cannot write rules and the composer cannot add one", {
  local_project()
  log = local_coach_children()
  rule = '{"rules": {"never": [{"rule": "r(category:install)", "why": "No installs."}]}, '
  h = coach_demo(coach = coach_fake(domain = paste0(rule, '"notes": "x"}'),
                                    composer = paste0(rule, '"note": "Use na.rm.", ',
                                                      '"notes": "x"}')))
  domain = h$report$results[["coach domain"]]$value
  expect_true(domain$fell_back)
  expect_match(domain$problems, "rules", fixed = TRUE)
  composer = h$report$results$composer$value
  expect_true(composer$fell_back)
  expect_match(composer$problems, "no candidate proposed: r(category:install)", fixed = TRUE)
})

test_that("a plan limit stops the call with the starting harness and a record", {
  local_project()
  log = local_coach_children(limit = "coach domain")
  start = gptr_tailor(peter, coaching = list(note = "Be brief."))
  h = coach_demo(harness = start)
  expect_identical(h$record$decision, "stopped")
  expect_identical(h$record$reason, "stopped at the coaches: plan limit, resets at 3:45pm")
  expect_identical(h$coaching, start$coaching)
  expect_false(identical(harness_spec(h)$id, harness_spec(start)$id))
  expect_identical(log$calls, list("start", c("coach procedure", "coach domain")))
})

test_that("the record holds no data from the runs; $report holds the full report", {
  local_project()
  log = local_coach_children()
  canary = "CANARY-41b7"
  h = coach_demo(label = canary)
  rec = paste(deparse(h$record), collapse = "\n")
  expect_false(grepl(canary, rec, fixed = TRUE))
  expect_match(h$report$results$start$transcript, canary, fixed = TRUE)
  expect_match(log$jobs[[2L]]$prompt, canary, fixed = TRUE)
  expect_identical(h$report$record, h$record)
  expect_identical(names(h$report$candidates), c("procedure", "domain", "composer"))
  expect_named(h$record$runs[[1L]], c("label", "status", "turns", "tokens", "cost", "risk",
                                      "unmet"))
  expect_identical(c(h$record$model, h$record$coach), c("solver/solver-1", "coach/coach-1"))
})

test_that("a recorded coaching call replays from its block with no process", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  log = local_coach_children()
  f = file.path(getwd(), "coach.R")
  writeLines(c("x = c(1, NA, 3)",
               paste0("mean_peter = gptr_coach(\"Average x.\", x, model = solver, mode = \"auto\",",
                      " coach = coach)")), f)
  e = new.env(parent = globalenv())
  e$solver = coach_solver()
  e$coach = coach_fake()
  source(f, local = e, keep.source = TRUE)
  expect_length(log$jobs, 7L)
  hash = coaching_hash(e$mean_peter$coaching)
  b = doc_find_blocks(readLines(f))
  expect_identical(b$header[[1L]][c("kind", "harness", "model", "coach")],
                   list(kind = "coach", harness = paste0("mean_peter:", hash),
                        model = "solver/solver-1", coach = "coach/coach-1"))
  body = doc_block_body(readLines(f), b[1L, ])
  expect_true(any(grepl("## Decision: kept (delivered as at start; risk 0 <= 0)", body,
                        fixed = TRUE)))
  e$mean_peter = NULL
  expect_identical(gptr_source(f, replay = "replay", envir = e)$action, "replayed")
  expect_length(log$jobs, 7L)
  expect_identical(coaching_hash(e$mean_peter$coaching), hash)
})

# ---- real child processes (skipped on CRAN; gptr must be installed for Rscript children) ------

# Children load gptr with loadNamespace(): under R CMD check the installed package is on the
# library path; from a source tree it is installed once per R session into a temporary library
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

test_that("the demo in real processes, at most two at once, leaves no child behind", {
  local_worker_lib()
  local_project()
  local_gptr_options(subagents.max_workers = 2L)
  h = coach_demo()
  expect_identical(h$record$decision, "kept")
  expect_identical(h$report$results$final$value, 2)
  expect_match(h$coaching$note, "na.rm", fixed = TRUE)
  jobs = gptr_jobs()
  expect_false(any(jobs$kind == "worker"))
})
