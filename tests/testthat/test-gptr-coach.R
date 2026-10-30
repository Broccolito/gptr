# Tests for R/gptr-coach.R (plan P29 T9; 08 sections 1.3-1.7, 3.4, 3.6 and 3.7): gptr_coach() at
# k = 1. Children run in this process through child_main(), as coach_run_jobs() runs them in their
# own (the job crosses as a file, the result as JSON); one test starts real processes.

# coach_run_jobs() run in this process; `log$calls` keeps the job ids of each stage and
# `log$jobs` every job. A job whose id is in `limit` reports a plan limit, as a child does.
local_coach_children = function(limit = character(), .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$jobs = list()
  log$calls = list()
  local_coach_log(.env)
  testthat::local_mocked_bindings(coach_run_jobs = function(jobs) {
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

# Coaching charges its usage rows to the session-less log and merges plan readings: both are put
# back when the test ends
local_coach_log = function(.env = parent.frame()) {
  log = the$s1_log
  plan = pcli_cache$plan
  withr::defer({
    assign("s1_log", log, envir = the)
    assign("plan", plan, envir = pcli_cache)
  }, envir = .env)
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
  expect_identical(log$calls, list("start1", c("proc1", "dom1"),
                                   c("probe-proc1", "probe-dom1"), "compose1", "final1"))
  roles = vapply(log$jobs, function(j) j$role, "")
  expect_identical(c(sum(roles == "run"), sum(roles == "coach")), c(4L, 3L))
  expect_identical(h$report$results$start1$value, NA_real_)
  expect_identical(h$report$results$final1$value, 2)
  expect_identical(h$record$reason, "delivered as at start; risk 0 <= 0; check TRUE")
  expect_identical(vapply(h$record$runs, function(r) r$label, ""),
                   c("start1", "probe-proc1", "probe-dom1", "final1"))
  # only the procedure coach may write rules, and the composer only those proposed
  coaches = Filter(function(j) identical(j$role, "coach"), log$jobs)
  expect_identical(vapply(coaches, function(j) "rules" %in% j$surface, NA, USE.NAMES = FALSE),
                   c(TRUE, FALSE, TRUE))
  expect_identical(coaches[[3L]]$rules_allowed, character())
  # the record holds counts and decisions; the report holds the runs and the replies
  expect_identical(h$report$results$proc1$value$notes,
                   "The starting run returned NA.")
  expect_false(h$report$results$dom1$value$fell_back)
})

test_that("an invalid reply is retried once in the same session; a second failure falls back", {
  local_project()
  log = local_coach_children()
  bad = '{"note": "<coaching>use na.rm</coaching>", "notes": "x"}'
  h = coach_demo(coach = coach_fake(procedure = c(bad, fix_reply), composer = "not json"))
  coach = h$report$results$proc1
  expect_identical(coach$turns, 2L)
  expect_match(coach$transcript, "Your reply could not be used", fixed = TRUE)
  expect_match(coach$transcript, "contains a tag of one of gptr's blocks", fixed = TRUE)
  expect_false(coach$value$fell_back)
  expect_match(coach$value$coaching$note, "na.rm", fixed = TRUE)
  composer = h$report$results$compose1
  expect_identical(composer$turns, 2L)
  expect_true(composer$value$fell_back)
  expect_match(composer$value$problems, "not one JSON object", fixed = TRUE)
  # the composer's starting coaching is the one the final run tried
  expect_identical(h$record$decision, "not kept")
  expect_identical(h$coaching$note, "")
  h = coach_demo(coach = coach_fake(procedure = bad))
  expect_true(h$report$results$proc1$value$fell_back)
  probe = Filter(function(j) identical(j$id, "probe-proc1"), log$jobs)
  expect_length(probe, 2L)
  expect_identical(probe[[2L]]$spec$coaching$note, "")
})

test_that("a coach's reply budget: its retry gets only what is left", {
  local_project()
  log = local_coach_children()
  bad = '{"note": "<coaching>x</coaching>", "notes": "x"}'
  h = coach_demo(budget = list(turns = 1L), coach = coach_fake(procedure = c(bad, fix_reply)))
  expect_identical(h$report$results$proc1$turns, 1L)
  expect_true(h$report$results$proc1$value$fell_back)
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
  expect_identical(log$calls, list("start1"))
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
  n = c(run = 4L, coach = 3L, judge = 0L)
  expect_message(coach_plan_notice(c(run = "claude", coach = "api"), n),
                 "4 of these sessions run on your Claude plan, at most two at once")
  expect_message(coach_plan_notice(c(run = "claude", coach = "claude"), n),
                 "5-hour window 15% used, weekly 34% used")
  expect_silent(coach_plan_notice(c(run = "api", coach = "fake"), n))
  # at k = 2 the judge runs on the coach model, if it runs
  n = c(run = 8L, coach = 6L, judge = 1L)
  expect_message(coach_plan_notice(c(run = "claude", coach = "api"), n), "^8 of these sessions")
  expect_message(coach_plan_notice(c(run = "api", coach = "claude"), n), "^Up to 7 of these")
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
  refused("invalid_argument", k = 0L)
  refused("invalid_argument", k = 6L, regexp = "between 1 and 5")
  refused("invalid_argument", k = 1.5)
  refused("invalid_argument", strategy = "serial", regexp = "\"sequential\"")
  refused("invalid_argument", focus = character())
  refused("invalid_argument", surface = c("note", "code"))
  refused("model_refused", coach = "router:pick")
  refused("model_refused", coach = gptr_fake_provider(list(0.9), name = "judge",
                                                       type = "classifier"))
  refused("not_recorded", coach = "anthropic/claude-sonnet-5-5")
  con = textConnection("x")
  withr::defer(close(con))
  refused("invalid_argument", con, regexp = "cannot be sent")
  # peter() arguments an unattended run cannot use, and those peter() would refuse
  unusable = list(.run = FALSE, background = TRUE, .stdin = TRUE, envir = new.env(),
                  parallel = 2L, choices = c("a", "b"), levels = c("low", "high"),
                  threshold = 0.4, min_confidence = 0.5, uncertain = "stop")
  for (nm in names(unusable)) {
    do.call(refused, c(list("invalid_argument", regexp = paste0("`", nm, " =`")), unusable[nm]))
  }
  refused("invalid_argument", tools = c("r", "nosuchtool"), regexp = "'nosuchtool'")
  refused("invalid_argument", budget = list(dollars = 1), regexp = "Unknown budget field")
  refused("invalid_argument", harness = gptr_tailor(peter, background = TRUE),
          regexp = "`background =`")
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
  domain = h$report$results$dom1$value
  expect_true(domain$fell_back)
  expect_match(domain$problems, "rules", fixed = TRUE)
  composer = h$report$results$compose1$value
  expect_true(composer$fell_back)
  expect_match(composer$problems, 'no candidate proposed: {"never":"r(category:install)"}',
               fixed = TRUE)
  # a rule is its kind and its whole content: a never rule turned into a require, or a require
  # that gains a condition, is a new rule; other prose and another id are not
  proposed = paste0('{"rules": {"never": [{"rule": "r(fn:write.csv)", "why": "No files."}], ',
                    '"require": [{"id": "avg", "any": "r(fn:mean)", "text": "Average."}]}, ',
                    '"note": "Use na.rm.", "notes": "x"}')
  composed = function(require) {
    reply = paste0('{"rules": {"require": [', require, ']}, "notes": "x"}')
    coach_demo(coach = coach_fake(procedure = proposed, composer = reply),
               check = NULL)$report$results$compose1$value
  }
  flipped = composed('{"id": "csv", "any": "r(fn:write.csv)", "text": "Write it."}')
  expect_match(flipped$problems, '{"require":{"any":"r(fn:write.csv)"}}', fixed = TRUE)
  narrowed = composed('{"id": "avg", "any": "r(fn:mean)", "contains": "wave3", "text": "Average."}')
  expect_match(narrowed$problems, '"contains":"wave3"', fixed = TRUE)
  expect_false(composed('{"id": "mean-first", "any": "r(fn:mean)", "text": "Mean."}')$fell_back)
})

test_that("a plan limit stops the call with the starting harness and a record", {
  local_project()
  log = local_coach_children(limit = "dom1")
  start = gptr_tailor(peter, coaching = list(note = "Be brief."))
  h = coach_demo(harness = start)
  expect_identical(h$record$decision, "stopped")
  expect_identical(h$record$reason, "stopped at the coaches: plan limit, resets at 3:45pm")
  expect_identical(h$coaching, start$coaching)
  expect_false(identical(harness_spec(h)$id, harness_spec(start)$id))
  expect_identical(log$calls, list("start1", c("proc1", "dom1")))
})

test_that("the record holds no data from the runs; $report holds the full report", {
  local_project()
  log = local_coach_children()
  canary = "CANARY-41b7"
  h = coach_demo(label = canary)
  rec = paste(deparse(h$record), collapse = "\n")
  expect_false(grepl(canary, rec, fixed = TRUE))
  expect_match(h$report$results$start1$transcript, canary, fixed = TRUE)
  expect_match(log$jobs[[2L]]$prompt, canary, fixed = TRUE)
  expect_identical(h$report$record, h$record)
  expect_identical(names(h$report$candidates), c("proc1", "dom1", "compose1"))
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

# ---- coach_run_jobs() stubbed: k > 1, sequential, the parent's own checks ------------------------

# coach_run_jobs() stubbed: `answer(job)` gives the fields of each job's result; `log` keeps the
# job ids of each stage and every job
local_coach_stub = function(answer, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$jobs = list()
  log$calls = list()
  local_coach_log(.env)
  testthat::local_mocked_bindings(coach_run_jobs = function(jobs) {
    log$jobs = c(log$jobs, jobs)
    log$calls = c(log$calls, list(vapply(jobs, function(j) j$id, "", USE.NAMES = FALSE)))
    lapply(jobs, function(job) do.call(child_result_new, c(list(job$id), answer(job))))
  }, .env = .env)
  log
}

# Stubbed sessions: a run returns 2 and answers "ran <its note>", with a transcript canary; a
# coach proposes the note "<its id> note"; the judge answers as `judge(job)` does (by default it
# fails)
coach_answer = function(judge = function(job) list(error = "the judge failed")) {
  function(job) {
    if (identical(job$role, "judge")) return(judge(job))
    if (identical(job$role, "coach")) {
      return(list(status = "idle", turns = 1L, value = list(
        coaching = list(note = paste(job$id, "note")), notes = paste(job$id, "notes"),
        fell_back = FALSE)))
    }
    list(status = "idle", turns = 1L, value = 2, text = paste("ran", job$spec$coaching$note),
         transcript = paste("TRANSCRIPT-CANARY", job$id))
  }
}

# A judge that picks the attempt whose answer contains `text`
judge_picks = function(text) {
  function(job) {
    at = regmatches(job$prompt, gregexpr("## Attempt [A-Z]\nAnswer:\n[^\n]*", job$prompt))[[1L]]
    list(status = "idle", value = list(label = substr(at[grepl(text, at, fixed = TRUE)], 12L, 12L)))
  }
}

coach_k = function(...) {
  x = c(1, NA, 3)
  gptr_coach("Average x.", x, model = coach_solver(), mode = "auto", coach = coach_fake(), ...)
}

job_by_id = function(log, id) Find(function(j) identical(j$id, id), log$jobs)

test_that("k = 2 in parallel: the counts, composers that see every probe, labels, the judge", {
  local_project()
  local_gptr_options(quiet = FALSE)
  log = local_coach_stub(coach_answer(judge = judge_picks("compose2")))
  said = character()
  h = withCallingHandlers(coach_k(k = 2L), gptr_message = function(m) {
    said <<- c(said, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  expect_true(any(grepl(paste0("starts 8 runs of your task and 6 coach sessions, plus up to one ",
                               "judge session"), said, fixed = TRUE)))
  expect_identical(log$calls, list(c("start1", "start2"), c("proc1", "dom1", "proc2", "dom2"),
                                   c("probe-proc1", "probe-dom1", "probe-proc2", "probe-dom2"),
                                   c("compose1", "compose2"), c("final1", "final2"), "judge"))
  roles = vapply(log$jobs, function(j) j$role, "")
  expect_identical(c(sum(roles == "run"), sum(roles == "coach"), sum(roles == "judge")),
                   c(8L, 6L, 1L))
  # the coaches are blind to each other and see both starting runs; each composer sees all
  for (id in c("proc1", "dom2")) {
    p = job_by_id(log, id)$prompt
    expect_match(p, "(?s)## Run start1\n.*## Run start2\n", perl = TRUE)
    expect_false(grepl("Candidate|probe-", p))
  }
  for (id in c("compose1", "compose2")) {
    p = job_by_id(log, id)$prompt
    for (r in c("start1", "start2", "probe-proc1", "probe-dom1", "probe-proc2", "probe-dom2")) {
      expect_match(p, paste0("## Run ", r, "\n"), fixed = TRUE)
    }
    expect_match(p, "## Candidate dom2\n", fixed = TRUE)
  }
  expect_identical(job_by_id(log, "probe-dom2")$spec$coaching$note, "dom2 note")
  expect_identical(job_by_id(log, "final2")$spec$coaching$note, "compose2 note")
  # the judge picked final2 among the two that passed
  expect_identical(h$record$decision, "kept")
  expect_identical(h$coaching$note, "compose2 note")
  expect_match(h$record$reason, "^final2, picked by the judge: delivered as at start")
  label = function(rows) vapply(rows, function(r) r$label, "")
  expect_identical(label(h$record$runs), c("start1", "start2", "probe-proc1", "probe-dom1",
                                           "probe-proc2", "probe-dom2", "final1", "final2"))
  expect_identical(label(h$record$coaches), c("proc1", "dom1", "proc2", "dom2", "compose1",
                                              "compose2", "judge"))
  expect_identical(h$record[c("k", "strategy")], list(k = 2L, strategy = "parallel"))
})

test_that("the judge sees only the passing finals' deliverables, under shuffled labels", {
  local_project()
  withr::local_seed(7L)
  seed = .Random.seed
  log = local_coach_stub(coach_answer(judge = judge_picks("compose1")))
  h = coach_k(k = 3L, check = function(r) {
    "CHECK-CANARY"
    !grepl("compose3", r$text, fixed = TRUE)
  })
  expect_identical(.Random.seed, seed)
  judge = job_by_id(log, "judge")
  expect_identical(judge$schema$properties$label$enum, list("A", "B"))
  expect_null(judge$spec)
  expect_null(judge$base)
  p = judge$prompt
  for (no in c("compose3", "TRANSCRIPT-CANARY", "## Run", "Transcript", "CHECK-CANARY",
               "proc1 note", "notes", "rules", "harness", "coaching")) {
    expect_false(grepl(no, p, fixed = TRUE), label = no)
  }
  expect_match(p, "# The task\nAverage x.", fixed = TRUE)
  # the attempts follow the call's own shuffle, and a label names the final shown under it
  shown = c("compose1", "compose2")[coach_shuffle(paste(coaching_hash(NULL), "Average x."), 2L)]
  expect_match(p, paste0("## Attempt A\nAnswer:\nran ", shown[[1L]], " note\nValue:\n num 2\n",
                         "Objects:\nnone\nFiles:\nnone\n## Attempt B\nAnswer:\nran ", shown[[2L]]),
               fixed = TRUE)
  expect_identical(h$coaching$note, "compose1 note")
  expect_match(h$record$reason, "^final1, picked by the judge")
  # the shuffle repeats for one seed, is a permutation, and differs between seeds
  expect_identical(coach_shuffle("s", 5L), coach_shuffle("s", 5L))
  expect_setequal(coach_shuffle("s", 5L), 1:5)
  expect_false(all(vapply(c("a", "b", "c", "d"), function(s) {
    identical(coach_shuffle(s, 5L), coach_shuffle("s", 5L))
  }, NA)))
})

test_that("a failing judge falls back to the first passing final", {
  local_project()
  log = local_coach_stub(coach_answer())
  h = coach_k(k = 2L)
  expect_identical(h$record$decision, "kept")
  expect_identical(h$coaching$note, "compose1 note")
  expect_match(h$record$reason, "^final1, the first that passed: delivered")
  expect_match(h$record$notes, "judge: its answer could not be used", fixed = TRUE)
  log = local_coach_stub(coach_answer(judge = function(job) {
    list(status = "idle", value = list(label = "Z"))
  }))
  h = coach_k(k = 2L)
  expect_identical(h$coaching$note, "compose1 note")
})

test_that("none passing keeps the start; one passing needs no judge", {
  local_project()
  log = local_coach_stub(coach_answer())
  start = gptr_tailor(peter, coaching = list(note = "Be brief."))
  h = coach_k(k = 2L, harness = start, check = function(r) FALSE)
  expect_identical(h$record$decision, "not kept")
  expect_identical(h$record$reason, "final1: check returned FALSE; final2: check returned FALSE")
  expect_identical(h$coaching, start$coaching)
  expect_null(job_by_id(log, "judge"))
  h = coach_k(k = 2L, check = function(r) grepl("compose2", r$text, fixed = TRUE))
  expect_identical(h$coaching$note, "compose2 note")
  expect_identical(h$record$reason, "final2: delivered as at start; risk 0 <= 0; check TRUE")
  expect_null(job_by_id(log, "judge"))
})

test_that("sequential rounds share the starting runs, see earlier rounds and build on them", {
  local_project()
  local_gptr_options(quiet = FALSE)
  log = local_coach_stub(coach_answer())
  said = character()
  # round 1's composition fails check, and round 2 still builds on it
  h = withCallingHandlers(
    coach_k(k = 2L, strategy = "sequential",
            check = function(r) !grepl("compose1", r$text, fixed = TRUE)),
    gptr_message = function(m) {
      said <<- c(said, conditionMessage(m))
      invokeRestart("muffleMessage")
    })
  expect_true(any(grepl(paste0("starts 8 runs of your task and 6 coach sessions, plus up to one ",
                               "judge session"), said, fixed = TRUE)))
  expect_identical(log$calls, list(c("start1", "start2"), c("proc1", "dom1"),
                                   c("probe-proc1", "probe-dom1"), "compose1", "final1",
                                   c("proc2", "dom2"), c("probe-proc2", "probe-dom2"), "compose2",
                                   "final2"))
  roles = vapply(log$jobs, function(j) j$role, "")
  expect_identical(c(sum(roles == "run"), sum(roles == "coach")), c(8L, 6L))
  p1 = job_by_id(log, "proc1")$prompt
  expect_match(p1, "(?s)## Run start1\n.*## Run start2\n", perl = TRUE)
  expect_false(grepl("Earlier rounds", p1, fixed = TRUE))
  for (id in c("dom2", "compose2")) {
    p = job_by_id(log, id)$prompt
    expect_match(p, "(?s)## Run start1\n.*## Run start2\n.*# Earlier rounds\n", perl = TRUE)
    for (seen in c("## Candidate proc1", "## Run probe-proc1", "proc1 notes", "## Candidate dom1",
                   "## Candidate compose1", "## Run final1")) {
      expect_match(p, seen, fixed = TRUE)
    }
    expect_match(p, "# The current coaching\n{\"note\":\"compose1 note\"", fixed = TRUE)
    expect_identical(job_by_id(log, id)$base$note, "compose1 note")
  }
  expect_match(job_by_id(log, "compose2")$prompt, "# The candidates\n## Candidate proc2",
               fixed = TRUE)
  expect_identical(h$coaching$note, "compose2 note")
  expect_identical(h$record$reason, "final2: delivered as at start; risk 0 <= 0; check TRUE")
  expect_identical(h$record$strategy, "sequential")
})

test_that("the judge runs as a tool-less session whose value is its label", {
  local_project()
  log = local_coach_children()
  x = list(models = list(coach = gptr_fake_provider(list('{"label": "B"}'), name = "picker")))
  res = coach_run_jobs(list(coach_job_judge(x, "Pick one.", c("A", "B"))))
  expect_identical(res[[1L]][c("status", "value")],
                   list(status = "idle", value = list(label = "B")))
})

test_that("starting runs that all failed or took no turns stop the call before any coach", {
  local_project()
  failed = function(job) {
    if (identical(job$id, "start1")) return(list(error = "`tools =` names 'nosuch'."))
    list(status = "idle", turns = 0L)
  }
  log = local_coach_stub(failed)
  expect_error(coach_k(k = 2L), "did not coach: `tools =` names 'nosuch'.",
               class = "gptr_error_invalid_argument")
  expect_identical(log$calls, list(c("start1", "start2")))
  log = local_coach_stub(function(job) list(status = "idle", turns = 0L))
  expect_error(coach_k(), "did not coach: it took no turns", class = "gptr_error_invalid_argument")
  # one starting run that worked is evidence enough
  answer = coach_answer()
  log = local_coach_stub(function(job) if (identical(job$id, "start1")) list() else answer(job))
  expect_identical(coach_k(k = 2L)$record$decision, "kept")
})

test_that("tool names only a run's session can know are left to the run", {
  start = harness_spec(peter)
  expect_invisible(coach_args_check(list(tools = c("r", "-sh", "readonly")), start))
  expect_invisible(coach_args_check(list(tools = "mcp__srv__lookup"), start))
  expect_invisible(coach_args_check(list(tools = "mine", extensions = function(gptr) NULL), start))
})

test_that("the coaches and the judge see the starting run's whole first message as the task", {
  local_project()
  task = "Average x.\n\n## Rules\n- keep the column names\n\nx: a numeric vector of length 3"
  answer = coach_answer(judge = judge_picks("compose2"))
  log = local_coach_stub(function(job) {
    c(answer(job), if (job$id == "start1") list(first_user = task))
  })
  coach_k(k = 2L)
  for (id in c("proc1", "compose2", "judge")) {
    expect_match(job_by_id(log, id)$prompt, paste0("# The task\n", task, "\n#"), fixed = TRUE)
  }
})

test_that("peter() arguments are taken from their own frames when gptr_coach() is wrapped", {
  local_project()
  log = local_coach_stub(coach_answer())
  wrap = function(...) gptr_coach(...)
  use = function() {
    lim = list(turns = 3)
    x = c(1, NA, 3)
    wrap("Average x.", x, model = coach_solver(), mode = "auto", coach = coach_fake(), budget = lim)
  }
  use()
  expect_identical(job_by_id(log, "start1")$args$budget, list(turns = 3))
  # an identifier resolves as peter() resolves it through a wrapper: a variable from its own frame
  fa = gptr_fake_provider(list("a"), name = "fa")
  m = fa
  g = function() {
    m = coach_solver()
    x = c(1, NA, 3)
    wrap("Average x.", x, model = m, mode = "auto", coach = coach_fake())
  }
  expect_identical(g()$record$model, "solver/solver-1")
  expect_identical(job_by_id(log, "start1")$model$name, "solver")
})

test_that("a budget fixed in the starting harness also caps the coaches and the judge", {
  local_project()
  log = local_coach_stub(coach_answer(judge = judge_picks("compose2")))
  lim = list(turns = 9L)
  coach_k(k = 2L, harness = gptr_tailor(peter, budget = lim))
  for (id in c("proc1", "compose2", "judge")) {
    expect_identical(job_by_id(log, id)$budget, lim, label = id)
  }
  expect_error(coach_k(harness = gptr_tailor(peter, budget = list(dollars = 1))),
               "Unknown budget field", class = "gptr_error_invalid_argument")
})

test_that("a tool of a user extension file is known before any session synced it", {
  local_gw()
  dir = file.path(gptr_user_dir("config"), "extensions")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  f = file.path(dir, "coach-mytool.R")
  writeLines(paste0("function(gptr) gptr$register(gptr::gptr_tool(\"coach_mytool\", \"Mine.\", ",
                    "execute = function(input, ctx) \"ok\"))"), f)
  withr::defer({
    unlink(f)
    for (r in registry_candidates("tool", "coach_mytool", NULL)) registry_remove(r$id)
  })
  args = list(tools = c("minimal", "coach_mytool"))
  expect_invisible(coach_args_check(args, harness_spec(peter)))
})

test_that("a coaching skill whose name you took since is refused before any process starts", {
  withr::defer(res_prune("skills:", character()))
  local_project()
  log = local_coach_children()
  h = gptr_tailor(peter, coaching = list(skills = list(list(name = "late-tips",
                                                             description = "D.", text = "T."))))
  off = gptr_register(gptr_spec("skill", "late-tips", description = "Mine.", text = "Mine."))
  withr::defer(off())
  expect_error(coach_demo(harness = h), "reuse the skill name late-tips", fixed = TRUE,
               class = "gptr_error_coaching")
  expect_length(log$jobs, 0L)
})

# A usage row of request `id`
usage_of = function(id, cost = 0.5) {
  usage_conform(data.frame(request_id = id, session = "s0000000001", agent = "main",
                           provider = "fake", model = "fake-1", route = "api", input = 100,
                           output = 10, cost = cost, started = Sys.time(), estimated = FALSE))
}

test_that("coaching spend reaches gptr_usage(), each request once", {
  local_project()
  answer = coach_answer()
  log = local_coach_stub(function(job) {
    id = if (startsWith(job$id, "probe")) "q-probe" else paste0("q-", job$id)
    c(answer(job), list(usage = usage_of(id)))
  })
  requests = function() attr(gptr_usage(), "totals")[["requests"]]
  # the session-less log only: live sessions of earlier tests drop out when R collects them
  testthat::local_mocked_bindings(live_all = function() list())
  before = requests()
  coach_k()
  expect_identical(requests() - before, 6)
  added = utils::tail(usage_log()$request_id, 6L)
  expect_setequal(added, paste0("q-", c("start1", "proc1", "dom1", "probe", "compose1", "final1")))
})

test_that("inside a run, coaching spend is charged to the run's session; a forged row is not", {
  local_project()
  s = peter("Hi.", model = gptr_fake_provider(list("Hello.")))
  run = list(shell = s)
  testthat::local_mocked_bindings(run_current = function() run)
  n = nrow(session_data(s)$usage)
  coach_charge(list(list(usage = usage_of("q-a")), list(usage = usage_of("q-a")),
                    list(usage = data.frame(input = "x")), list(usage = NULL)))
  coach_charge(list(list(usage = usage_of("q-a"))))
  u = session_data(s)$usage
  expect_identical(nrow(u), n + 1L)
  expect_identical(u$request_id[[nrow(u)]], "q-a")
})

test_that("plan readings from the runs reach this session when newer, checked and clipped", {
  local_project()
  now = Sys.time()
  reading = function(at, five) {
    list(`claude-cli` = list(status = "allowed", five_hour = five, seven_day = 0.2, time = at),
         elsewhere = list(five_hour = 0.1, time = at))
  }
  answer = coach_answer()
  log = local_coach_stub(function(job) {
    plan = switch(job$id, start1 = reading(now - 60, 1.7), final1 = reading(now - 120, 0.9),
                  `probe-dom1` = list(`claude-cli` = list(five_hour = "x", time = "today")))
    c(answer(job), list(plan = plan))
  })
  pcli_cache$plan = NULL
  coach_k()
  rd = pcli_cache$plan$`claude-cli`
  expect_identical(names(pcli_cache$plan), "claude-cli")
  expect_identical(rd[c("status", "five_hour", "seven_day", "time")],
                   list(status = "allowed", five_hour = 1, seven_day = 0.2, time = now - 60))
})

test_that("the call record tells the document route whether every model is offline", {
  local_project()
  log = local_coach_stub(coach_answer())
  seen = new.env()
  real = ext_service_get
  testthat::local_mocked_bindings(ext_service_get = function(name) {
    if (!identical(name, "doc.coach")) return(real(name))
    function(call) {
      seen$offline = c(seen$offline, call$offline)
      list(action = "replay", harness = peter)
    }
  })
  x = c(1, NA, 3)
  for (coach in list(coach_fake(), "anthropic/claude-sonnet-5-5")) {
    gptr_coach("Average x.", x, model = coach_solver(), mode = "auto", coach = coach)
  }
  expect_identical(seen$offline, c(TRUE, FALSE))
  expect_length(log$jobs, 0L)
})

# ---- real child processes (skipped on CRAN; gptr must be installed for Rscript children) ------

test_that("the demo in real processes, at most two at once, leaves no child behind", {
  local_worker_lib()
  local_project()
  local_coach_log()
  local_gptr_options(subagents.max_workers = 2L)
  h = coach_demo()
  expect_identical(h$record$decision, "kept")
  expect_identical(h$report$results$final1$value, 2)
  expect_match(h$coaching$note, "na.rm", fixed = TRUE)
  jobs = gptr_jobs()
  expect_false(any(jobs$kind == "worker"))
})

test_that("a registered secret in a run's objects reaches its child's model redacted (D-295)", {
  local_worker_lib()
  local_project()
  local_vault()
  key = "sk-coachfake-0123456789abcdef"
  secret_register(key, "COACH_FAKE_KEY")
  seen = withr::local_tempfile()
  # the child's model writes every request's text where this test reads it
  script = function(request) {
    cat(unlist(request$messages), file = seen, sep = "\n", append = TRUE)
    if (length(request$last_results)) "Done." else list(tool = "r", input = list(code = "cfg"))
  }
  environment(script) = list2env(list(seen = seen), parent = globalenv())
  job = list(id = "start1", role = "run", spec = harness_spec(peter), prompt = "Show cfg.",
             objects = list(cfg = list(token = key)), args = list(mode = "auto"),
             model = gptr_fake_provider(script, name = "echo"), direction = "start")
  res = coach_run_jobs(list(job))
  expect_identical(res[[1L]]$status, "idle")
  sent = paste(readLines(seen), collapse = "\n")
  expect_match(sent, "[secret:COACH_FAKE_KEY]", fixed = TRUE)
  expect_false(grepl(key, sent, fixed = TRUE))
})
