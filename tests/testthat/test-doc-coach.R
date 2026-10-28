# Tests of plan P29 task T8 (08 sections 1.10 and 3.6): harness calls and coaching calls in
# documents. Stand-ins route through the document services as the real functions do: a harness
# call reaches the `document` route as the rewritten peter() call carrying the `gptr_harness`
# attribute (P29 interface 7), and gptr_coach() builds the call record doc.coach takes
# (interface 10). gptr_tailor() is always a stand-in here, so the harnesses it makes call the
# stand-ins; coaching_hash() and coaching_validate() are T6's when loaded, else stand-ins.

coach_hash = function(coaching) ns_fun("coaching_hash")(coaching)

# A sourcing environment with stand-ins for peter(), harnesses, gptr_tailor() and gptr_coach();
# `log$runs` counts model runs, `log$decision` keeps doc.coach's last answer, `log$result` makes
# a coaching call's harness and `log$record` its record. `log$console = TRUE` marks the calls as
# console turns (the attribute the console REPL sets), so a test's own srcrefs never locate them.
coach_world = function(.env = parent.frame()) {
  e = new.env(parent = globalenv())
  log = new.env()
  log$runs = 0L
  e$log = log
  turn = function(sc) {
    if (isTRUE(log$console)) attr(sc, "gptr_console") = TRUE
    sc
  }
  run = function(call, prompt) {
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(invisible(res))
    }
    log$runs = log$runs + 1L
    s = doc_test_session(list(doc_test_turn("n = 1", prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    invisible(s)
  }
  make = function(spec) {
    structure(function(prompt, ..., replay = NULL) {
      sc = sys.call()
      rw = sc
      rw[[1L]] = as.name("peter")
      h = attr(sys.function(), "gptr_harness")
      attr(rw, "gptr_harness") = list(fn = as.character(sc[[1L]]), hash = coach_hash(h$coaching),
                                      call = sc)
      run(call_new(prompt, envir = parent.frame(), args = list(replay = replay),
                   sys_call = turn(rw), nframe = sys.nframe()), prompt)
    }, class = c("gptr_harness", "function"), gptr_harness = spec)
  }
  e$peter = function(prompt, ..., replay = NULL) {
    run(call_new(prompt, envir = parent.frame(), args = list(replay = replay),
                 sys_call = turn(sys.call()), nframe = sys.nframe()), prompt)
  }
  e$gptr_tailor = function(x, ..., coaching = NULL) {
    old = attr(x, "gptr_harness") %||% list(args = list())
    if (!is.null(coaching)) coaching = ns_fun("coaching_validate")(coaching)
    make(list(args = c(old$args, list(...)), rules = NULL, coaching = coaching %||% old$coaching,
              record = NULL, id = id_new("", 8L), gptr = "1.0.0"))
  }
  e$gptr_coach = function(prompt, ..., harness = NULL, replay = NULL) {
    start = harness %||% e$peter
    call = call_new(prompt, envir = parent.frame(), args = list(replay = replay),
                    sys_call = turn(sys.call()), nframe = sys.nframe())
    call$start_hash = coach_hash(attr(start, "gptr_harness")$coaching)
    d = doc_coach_service(call)
    log$decision = d
    if (d$action %in% c("replay", "ask")) return(d$harness)
    log$runs = log$runs + 1L
    h = log$result(start)
    if (identical(d$action, "record")) h = doc_coach_block_service(d$site, h, log$record)
    h
  }
  log$result = function(start) {
    e$gptr_tailor(start, coaching = list(note = "Read the codebook first."))
  }
  log$record = list(model = "fake/fake-1", coach = "fake/fake-2", tokens = c(120, 30), cost = 0,
                    runs = c("start: ended normally, 3 turns, risk 1",
                             "final: ended normally, 2 turns, risk 1"),
                    decision = "kept (risk 1 <= 1)")
  real = ns_fun
  stub = list(
    coaching_hash = function(coaching) {
      substr(hash_sha256(canonical_json(list(schema = 1L, coaching = coaching %||% list()))),
             1L, 8L)
    },
    coaching_validate = function(coaching, surface = NULL) coaching
  )
  testthat::local_mocked_bindings(ns_fun = function(name) {
    if (identical(name, "gptr_tailor")) return(e$gptr_tailor)
    real(name) %||% stub[[name]]
  }, .env = .env)
  e
}

# The coaching of a harness
coaching_of = function(h) attr(h, "gptr_harness")$coaching

test_that("a harness call and a peter() call with one prompt each own their block", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "survey.R")
  writeLines(c("a = peter(\"Clean the data\")", "b = survey_peter(\"Clean the data\")"), f)
  e = coach_world()
  e$survey_peter = e$gptr_tailor(e$peter, coaching = list(note = "Weights first."))
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$log$runs, 2L)
  b = doc_find_blocks(readLines(f))
  expect_null(b$header[[1]]$harness)
  expect_identical(b$header[[2]]$harness,
                   paste0("survey_peter:", coach_hash(coaching_of(e$survey_peter))))
  for (keep in c(TRUE, FALSE)) source(f, local = e, keep.source = keep)
  expect_identical(e$log$runs, 2L)
  expect_identical(gptr_blocks(f)$status, c("fresh", "fresh"))
})

test_that("under Rscript a harness call is located in its own statement and owns its block", {
  local_project()
  f = file.path(getwd(), "run.R")
  ph = prompt_hash("Clean")
  writeLines(c("a = peter(\"Clean\")", paste0("# >>> gptr:aaaaaa model=m prompt=", ph),
               "# <<< gptr:aaaaaa", "b = survey_peter(\"Clean\")",
               paste0("# >>> gptr:bbbbbb model=m prompt=", ph, " harness=survey_peter:1234abcd"),
               "# <<< gptr:bbbbbb"), f)
  testthat::local_mocked_bindings(doc_command_args = function() c("R", paste0("--file=", f)))
  rw = quote(peter("Clean"))
  attr(rw, "gptr_harness") = list(fn = "survey_peter", hash = "1234abcd",
                                  call = quote(survey_peter("Clean")))
  s2 = doc_locate(call_new("Clean", sys_call = rw, nframe = 0L))
  s1 = doc_locate(call_new("Clean", sys_call = quote(peter("Clean")), nframe = 0L))
  expect_identical(c(s1$kind, s2$kind), c("rscript", "rscript"))
  expect_identical(c(s1$stmt, s2$stmt), c(1L, 1L, 4L, 4L))
  expect_identical(c(s1$block$id, s2$block$id), c("aaaaaa", "bbbbbb"))
  expect_identical(c(s1$block$status, s2$block$status), c("fresh", "fresh"))
  expect_identical(s2$harness, "survey_peter:1234abcd")
})

test_that("a harness call's block is stale once the coaching changes; replay refuses it", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "survey.R")
  writeLines("out = survey_peter(\"Clean the data\")", f)
  e = coach_world()
  e$survey_peter = e$gptr_tailor(e$peter, coaching = list(note = "Weights first."))
  gptr_source(f, envir = e)
  expect_identical(gptr_source(f, replay = "replay", envir = e)$action, "replayed")
  expect_identical(e$log$runs, 1L)
  e$survey_peter = e$gptr_tailor(e$peter, coaching = list(note = "Weights last."))
  expect_error(gptr_source(f, replay = "replay", envir = e), class = "gptr_error_stale_block")
  expect_identical(gptr_source(f, envir = e)$action, "regenerated")
  expect_identical(e$log$runs, 2L)
  expect_identical(doc_find_blocks(readLines(f))$header[[1]]$harness,
                   paste0("survey_peter:", coach_hash(coaching_of(e$survey_peter))))
})

test_that("a coaching call is recorded as a coach block and replays from it without a run", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines(c("survey_peter = gptr_coach(\"Clean the survey\")", "z = 1"), f)
  e = coach_world()
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$log$decision$action, "record")
  hash = coach_hash(coaching_of(e$survey_peter))
  lines = readLines(f)
  b = doc_find_blocks(lines)
  h = b$header[[1]]
  expect_identical(h[c("kind", "harness", "start", "coach", "tokens")],
                   list(kind = "coach", harness = paste0("survey_peter:", hash),
                        start = paste0("peter:", coach_hash(NULL)), coach = "fake/fake-2",
                        tokens = "120/30"))
  expect_identical(h$gptr, as.character(utils::packageVersion("gptr")))
  expect_null(h$session)
  body = doc_block_body(lines, b[1, ])
  expect_true(startsWith(body[1], "survey_peter = gptr_tailor(peter, coaching = list("))
  expect_identical(body[grepl("^##", body)],
                   c("## Run start: ended normally, 3 turns, risk 1",
                     "## Run final: ended normally, 2 turns, risk 1",
                     "## Decision: kept (risk 1 <= 1)"))
  expect_identical(gptr_blocks(f)$status, "fresh")
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$log$decision$action, "replay")
  expect_identical(e$log$runs, 1L)
  expect_identical(coach_hash(coaching_of(e$log$decision$harness)), hash)
  expect_identical(coach_hash(coaching_of(e$survey_peter)), hash)
  expect_length(list.files(file.path(getwd(), ".gptr", "cache", "s2"), recursive = TRUE), 0L)
})

test_that("coaching text that ends its string and adds R code is written as one string", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  note = "Done\")); stop(\"injected\"); x = c((\"\nsecond line"
  e = coach_world()
  e$log$result = function(start) e$gptr_tailor(start, coaching = list(note = note))
  source(f, local = e, keep.source = TRUE)
  lines = readLines(f)
  body = doc_block_body(lines, doc_find_blocks(lines)[1, ])
  expect_length(doc_parse_text(body, keep_source = FALSE), 1L)
  expect_no_error(source(f, local = e, keep.source = TRUE))
  expect_identical(e$log$decision$action, "replay")
  expect_identical(coaching_of(e$survey_peter)$note, note)
})

test_that("a coaching call whose result was not kept replays as the starting harness", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\", harness = auto_peter)", f)
  e = coach_world()
  e$auto_peter = e$gptr_tailor(e$peter, mode = "auto", coaching = list(note = "Be brief."))
  e$log$result = function(start) e$gptr_tailor(start)
  source(f, local = e, keep.source = TRUE)
  lines = readLines(f)
  b = doc_find_blocks(lines)
  start = coach_hash(coaching_of(e$auto_peter))
  expect_identical(doc_block_body(lines, b[1, ])[1], "survey_peter = gptr_tailor(auto_peter)")
  expect_identical(b$header[[1]][c("harness", "start")],
                   list(harness = paste0("survey_peter:", start),
                        start = paste0("auto_peter:", start)))
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$log$decision$action, "replay")
  expect_identical(e$log$runs, 1L)
  expect_identical(coach_hash(coaching_of(e$log$decision$harness)), start)
})

test_that("a hand-edited note replays as written and makes the harness's blocks stale", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines(c("survey_peter = gptr_coach(\"Clean the survey\")",
               "out = survey_peter(\"Clean this year's survey\")"), f)
  e = coach_world()
  gptr_source(f, envir = e)
  expect_identical(e$log$runs, 2L)
  writeLines(sub("codebook first", "codebook twice", readLines(f), fixed = TRUE), f)
  out = gptr_source(f, envir = e)
  expect_identical(e$log$decision$action, "replay")
  expect_identical(coaching_of(e$survey_peter)$note, "Read the codebook twice.")
  expect_identical(out$action, c("replayed", "regenerated"))
  expect_identical(out$status, c("user-edited", "fresh"))
  expect_identical(e$log$runs, 3L)
})

test_that("a coach block that is not literal gives the starting harness and a notice", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  e = coach_world()
  source(f, local = e, keep.source = TRUE)
  writeLines(sub("\"Read the codebook first.\"", "paste(\"a\", \"b\")", readLines(f),
                 fixed = TRUE), f)
  local_gptr_options(quiet = FALSE)
  expect_message(source(f, local = e, keep.source = TRUE), class = "gptr_message_notice")
  expect_identical(e$log$decision$action, "replay")
  expect_identical(e$log$decision$harness, e$peter)
  expect_identical(coaching_of(e$survey_peter)$note, "a b")
  expect_identical(e$log$runs, 1L)
})

test_that("a coaching call is recorded only as `<name> = gptr_coach(...)`, and says why not", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines(c("print(gptr_coach(\"one\"))", "x = list(gptr_coach(\"two\"))",
               "gptr_coach(\"three\")", "y = gptr_coach(\"four\", harness = e$peter)"), f)
  local_gptr_options(quiet = FALSE)
  e = coach_world()
  e$e = e
  expect_message(capture.output(source(f, local = e, keep.source = TRUE)),
                 class = "gptr_message_notice")
  expect_identical(e$log$runs, 4L)
  expect_identical(e$log$decision$action, "none")
  expect_identical(nrow(doc_find_blocks(readLines(f))), 0L)
})

test_that("replay mode refuses a coaching call that has no recorded block", {
  local_project()
  local_gptr_options(record = "auto", replay = NULL)
  withr::local_envvar(GPTR_REPLAY = "replay")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  e = coach_world()
  expect_error(source(f, local = e, keep.source = TRUE), class = "gptr_error_not_recorded")
  expect_identical(e$log$runs, 0L)
})

test_that("a stale coach block asks under auto, replays when no one can answer, and recodes", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  e = coach_world()
  gptr_source(f, envir = e)
  id = doc_find_blocks(readLines(f))$id
  writeLines(sub("Clean the survey", "Clean the new survey", readLines(f), fixed = TRUE), f)
  expect_warning(gptr_source(f, envir = e), class = "gptr_warning_replay_downgraded")
  expect_identical(e$log$decision$action, "replay")
  local_gptr_options(interactive = TRUE)
  gptr_source(f, envir = e)
  expect_identical(e$log$decision$action, "ask")
  local_gptr_options(interactive = FALSE)
  out = gptr_source(f, replay = "record", envir = e)
  expect_identical(e$log$decision$action, "record")
  expect_identical(c(out$id, out$status), c(id, "fresh"))
  expect_identical(e$log$runs, 2L)
})

test_that("a coach block that a document_write hook patched defines the harness returned", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(lines = sub("codebook first", "codebook as patched", event$lines, fixed = TRUE))
  }))
  withr::defer(off())
  e = coach_world()
  source(f, local = e, keep.source = TRUE)
  expect_identical(coaching_of(e$survey_peter)$note, "Read the codebook as patched.")
  expect_identical(gptr_blocks(f)$status, "fresh")
})

test_that("gptr_export() refuses a document that holds a coach block", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "coach.R")
  writeLines("survey_peter = gptr_coach(\"Clean the survey\")", f)
  e = coach_world()
  source(f, local = e, keep.source = TRUE)
  err = expect_error(gptr_export(f, file.path(getwd(), "out.R")),
                     class = "gptr_error_doc_export")
  expect_match(err$reason, "coach block")
})

test_that("a console transcript defines a harness once and calls it by that definition", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  testthat::local_mocked_bindings(doc_command_args = function() "R",
                                  doc_ide_available = function() FALSE)
  tr = file.path(getwd(), "session.R")
  local_doc_binding(tr, "transcript")
  e = coach_world()
  e$log$console = TRUE
  e$survey_peter = e$gptr_tailor(e$peter, mode = "auto", extensions = function(gptr) NULL,
                                 coaching = list(note = "Weights first."))
  head = paste0("h_", attr(e$survey_peter, "gptr_harness")$id)
  evalq(survey_peter("Weigh the survey"), e)
  evalq(survey_peter("Weigh it again"), e)
  lines = readLines(tr)
  def = grep(paste0("^", head, " = "), lines, value = TRUE)
  expect_length(def, 1L)
  expect_true(startsWith(def, paste0(head, " = gptr_tailor(peter, mode = \"auto\", coaching = ")))
  expect_true(paste0("# gptr: ", head, " needs fixed arguments that are not recorded: ",
                     "extensions") %in% lines)
  expect_length(grep(paste0("^s_[0-9a-f]{6} = ", head, "\\(\"Weigh"), lines), 2L)
  hash = coach_hash(coaching_of(e$survey_peter))
  expect_identical(vapply(doc_find_blocks(lines)$header, function(h) h$harness, ""),
                   rep(paste0(head, ":", hash), 2L))
  expect_no_error(doc_parse_text(lines))
  evalq({
    coached = gptr_coach("Coach it", harness = survey_peter)
  }, e)
  coached = paste0("h_", attr(e$coached, "gptr_harness")$id)
  expect_length(grep(paste0("^", coached, " = gptr_tailor\\(peter, mode = "), readLines(tr)), 1L)
})
