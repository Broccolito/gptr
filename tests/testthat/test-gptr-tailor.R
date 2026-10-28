# test-gptr-tailor.R -- gptr_tailor(), the harness object and its call, the coaching checks, its
# hash and its factory (plan P29 T6; 08 sections 3.1 and 3.2)

# A route of order 1 that records what each gateway call captured and answers "probed"
local_tailor_probe = function(.env = parent.frame()) {
  box = new.env(parent = emptyenv())
  box$calls = list()
  spec = gptr_spec("route", "tailor_probe", order = 1, description = "test probe",
                   match = function(call) TRUE,
                   run = function(call) {
                     n = length(call$context)
                     box$calls[[length(box$calls) + 1L]] = list(
                       prompt = call$prompt, template = call$template, interp = call$interp,
                       ids = call$ids, args = call$args, envir = call$envir,
                       labels = vapply(call$context, function(it) it$label, ""),
                       kinds = vapply(call$context, function(it) it$kind, ""),
                       classes = vapply(seq_len(n), function(i) class(call_value(call, i))[1L], ""),
                       harness = attr(call$sys_call, "gptr_harness"))
                     "probed"
                   })
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  box
}

# The last `2 * k` probed calls as two halves that must agree (environments are checked apart)
expect_same_calls = function(box, k = 1L) {
  n = length(box$calls)
  strip = function(x) x[setdiff(names(x), c("envir", "harness"))]
  for (i in seq_len(k)) {
    expect_identical(strip(box$calls[[n - 2L * k + i]]), strip(box$calls[[n - k + i]]))
  }
}

tips_skill = list(name = "coach-tips", description = "Tips for this task.",
                  text = "Check the units first.")

test_that("gptr_tailor() returns a harness built on peter (08 3.1)", {
  local_gw()
  h = gptr_tailor(peter, mode = auto, tools = "-write")
  expect_s3_class(h, c("gptr_harness", "function"), exact = TRUE)
  expect_identical(environment(h), environment(peter))
  expect_identical(formals(h), formals(function(...) NULL))
  expect_identical(body(h), quote(harness_call(sys.function(), sys.call(), parent.frame())))
  spec = attr(h, "gptr_harness")
  expect_named(spec, c("args", "rules", "coaching", "record", "id", "gptr"))
  expect_identical(spec$args, list(mode = "auto", tools = "-write"))
  expect_identical(spec$coaching, list(note = "", skills = list(), review = NULL, rules = NULL))
  expect_null(spec$record)
  expect_match(spec$id, "^[0-9a-f]{12}$")
  expect_identical(spec$gptr, as.character(utils::packageVersion("gptr")))
  expect_identical(harness_spec(h), spec)
  expect_identical(harness_spec(peter)$args, list())
  # every harness gets a new id and an empty record
  expect_false(identical(harness_spec(gptr_tailor(h))$id, spec$id))
  for (x in list(function(...) peter(...), mean, "peter")) {
    expect_error(gptr_tailor(x), "gptr_tailor(peter", fixed = TRUE,
                 class = "gptr_error_invalid_argument")
  }
  expect_error(gptr_tailor(peter, "auto"), "named", class = "gptr_error_invalid_argument")
  expect_error(gptr_tailor(peter, temperature = 1), "temperature",
               class = "gptr_error_invalid_argument")
  expect_error(gptr_tailor(peter, mode = "auto", mode = "edits"), "once",
               class = "gptr_error_invalid_argument")
  expect_error(gptr_tailor(peter, plugins = "-builtin:x"), "plugins",
               class = "gptr_error_invalid_argument")
  expect_error(gptr_tailor(peter, mode = fast), class = "gptr_error_invalid_argument")
})

test_that("a harness call is the same call as peter's (08 3.1)", {
  local_gw()
  box = local_tailor_probe()
  h = gptr_tailor(peter, mode = "auto")
  mice = data.frame(weight = c(20, 22, 25))
  n = 3L
  # binding sites, {name} interpolation and the calling frame
  h("Count {n} rows", mice)
  peter("Count {n} rows", mice, mode = "auto")
  expect_same_calls(box)
  expect_identical(box$calls[[1L]]$kinds, "symbol")
  expect_identical(box$calls[[1L]]$interp, "n=3")
  expect_identical(box$calls[[1L]]$envir, environment())
  expect_identical(box$calls[[2L]]$envir, environment())
  # pipes
  mice |> h("a")
  mice |> peter("a", mode = "auto")
  expect_same_calls(box)
  expect_identical(box$calls[[3L]]$labels, "mice")
  # lapply() and do.call()
  lapply(c("a", "b"), h, mice)
  lapply(c("a", "b"), peter, mice, mode = "auto")
  expect_same_calls(box, 2L)
  do.call(h, list("a", mice))
  do.call(peter, list("a", mice, mode = "auto"))
  expect_same_calls(box)
  # a function frame serves only that call, as with peter
  f = function(g, ...) {
    g("a", mice, ...)
    environment()
  }
  e1 = f(h)
  e2 = f(peter, mode = "auto")
  k = length(box$calls)
  expect_identical(box$calls[[k - 1L]]$envir, e1)
  expect_identical(box$calls[[k]]$envir, e2)
  # the rewritten call names the harness, its coaching hash and the call as written
  hit = box$calls[[1L]]$harness
  expect_identical(hit$fn, "h")
  expect_identical(hit$hash, coaching_hash(NULL))
  expect_identical(deparse(hit$call), "h(\"Count {n} rows\", mice)")
  expect_null(box$calls[[2L]]$harness)
  expect_identical(box$calls[[5L]]$harness$fn, "FUN")
  expect_identical(box$calls[[9L]]$harness$fn, NA_character_)
})

test_that("a harness call runs like peter: its session, gptr_last() and a continuation", {
  local_gw()
  fake = local_fake_provider(list("one", "two"))
  h = gptr_tailor(peter, model = fake)
  s = h("How many rows?", mtcars, envir = new.env())
  expect_s3_class(s, "gptr_session")
  expect_identical(gptr_last(), s)
  expect_identical(s$text, "one")
  s |> h("And columns?")
  expect_identical(s$text, "two")
  expect_identical(gptr_last(), s)
  expect_length(fake_requests(fake), 2L)
})

test_that("fixed arguments merge: list-like ones combine and single values yield (08 3.1)", {
  local_gw()
  local_gptr_options(quiet = TRUE)
  box = local_tailor_probe()
  f1 = function(gptr) NULL
  f2 = function(gptr) NULL
  h = gptr_tailor(peter, mode = auto, tools = "-write", extensions = f1,
                  .opts = list(max_turns = 3L, context = "names"))
  h("a")
  got = box$calls[[1L]]
  expect_identical(got$ids$mode, "auto")
  expect_identical(got$ids$tools, "-write")
  expect_identical(got$ids$extensions, f1)
  expect_identical(got$args$opts, list(max_turns = 3L, context = "names"))
  h("a", mode = edits, tools = "-edit", extensions = f2, .opts = list(context = "none"))
  got = box$calls[[2L]]
  expect_identical(got$ids$mode, "edits")
  expect_identical(got$ids$tools, c("-write", "-edit"))
  expect_identical(got$ids$extensions, list(f1, f2))
  expect_identical(got$args$opts, list(max_turns = 3L, context = "none"))
  # tailoring a harness merges the same way; NULL drops a fixed single value
  h2 = gptr_tailor(h, mode = "plan", tools = "-edit", extensions = f2,
                   .opts = list(max_turns = 5L))
  expect_identical(harness_spec(h2)$args,
                   list(mode = "plan", tools = c("-write", "-edit"), extensions = list(f1, f2),
                        .opts = list(max_turns = 5L, context = "names")))
  expect_named(harness_spec(gptr_tailor(h2, mode = NULL))$args, c("tools", "extensions", ".opts"))
})

test_that("a harness that loads code or loosens checks says so when it is made", {
  local_gw()
  local_gptr_options(quiet = FALSE)
  ext = function(gptr) NULL
  expect_message(gptr_tailor(peter, extensions = ext), "extensions = function (gptr)",
                 fixed = TRUE, class = "gptr_message_notice")
  expect_message(gptr_tailor(peter, mode = "yolo"), "mode = \"yolo\"", fixed = TRUE,
                 class = "gptr_message_notice")
  expect_no_message(gptr_tailor(peter, mode = "auto"))
})

test_that("a continuation loads the coaching factory once per session (gptr_key)", {
  local_gw()
  fake = local_fake_provider(list("one", "two"))
  h = gptr_tailor(peter, coaching = list(note = "Check the units first."))
  key = attr(harness_factory(harness_spec(h)), "gptr_key")
  expect_identical(key, paste0("gptr_harness:", coaching_hash(harness_spec(h)$coaching), ":",
                               coaching_hash(list(rules = NULL))))
  expect_null(harness_factory(harness_spec(gptr_tailor(peter))))
  s = h("a", model = fake, envir = new.env())
  s |> h("b")
  sid = session_data(s)$id
  exts = registry_env()$exts
  keys = unlist(lapply(ls(exts), function(eid) {
    info = get(eid, envir = exts)
    if (identical(info$session, sid)) attr(info$factory, "gptr_key", exact = TRUE)
  }))
  expect_identical(keys, key)
})

test_that("the note is a T1 section after gptr's first line, never cut at 8,000 characters", {
  local_gw()
  fake = local_fake_provider(list("done"))
  note = paste0(strrep("abcd ", 1599L), "abcd.")
  expect_identical(nchar(note), 8000L)
  h = gptr_tailor(peter, coaching = list(note = note))
  h("a", model = fake, envir = new.env())
  t1 = fake_requests(fake)[[1L]]$system$t1
  expect_match(t1, paste0("<coaching>\n", coaching_first_line, "\n", note, "\n</coaching>"),
               fixed = TRUE)
})

test_that("a coaching skill is listed in the catalog and opens through read", {
  withr::defer(res_prune("skills:", character()))
  local_gw()
  read_tips = list(fake_tool("read", path = "skill:coach-tips/SKILL.md"), "done")
  fake = local_fake_provider(read_tips)
  h = gptr_tailor(peter, coaching = list(skills = list(tips_skill)))
  h("Clean the data", model = fake, envir = new.env())
  req = fake_requests(fake)
  expect_match(req[[1L]]$system$t1,
               "- coach-tips: Tips for this task. [skill:coach-tips/SKILL.md]", fixed = TRUE)
  expect_identical(msg_text(utils::tail(req[[2L]]$messages, 1L)[[1L]]), "Check the units first.")
})

test_that("the review follows a final answer once per round in each run (08 3.2)", {
  local_gw()
  last = function(r) msg_text(utils::tail(r$messages, 1L)[[1L]])
  review = list(text = "Open the output again.", rounds = 1L)
  fake = local_fake_provider(list("first", "second", "third", "fourth"))
  h = gptr_tailor(peter, coaching = list(review = review))
  s = h("a", model = fake, envir = new.env())
  s |> h("b")
  req = fake_requests(fake)
  expect_length(req, 4L)
  expect_match(last(req[[2L]]), "Open the output again.", fixed = TRUE)
  expect_identical(last(req[[3L]]), "b")
  expect_match(last(req[[4L]]), "Open the output again.", fixed = TRUE)
  expect_identical(s$text, "fourth")
  # two rounds
  fake2 = local_fake_provider(list("1", "2", "3", "4"), name = "fake2")
  review$rounds = 2L
  gptr_tailor(peter, coaching = list(review = review))("a", model = fake2, envir = new.env())
  expect_length(fake_requests(fake2), 3L)
})

test_that("no review at the turn limit, after a refusal or with .opts$returns (08 3.2)", {
  local_gw()
  h = gptr_tailor(peter, coaching = list(review = list(text = "Open it again.", rounds = 2L)))
  # the turn limit: nothing is left queued for the next run either
  fake = local_fake_provider(list("done", "more"))
  s = h("a", model = fake, envir = new.env(), .opts = list(max_turns = 1L))
  expect_length(fake_requests(fake), 1L)
  expect_length(session_data(s)$queue$follow_up, 0L)
  # a call the person's own hook refused
  blocker = function(gptr) {
    gptr$on("tool_call", function(event, ctx) list(decision = "block", reason = "not now"))
  }
  fake2 = local_fake_provider(list(fake_tool("read", path = "x.txt"), "done", "more"),
                              name = "fake2")
  h("a", model = fake2, extensions = blocker, envir = new.env())
  expect_length(fake_requests(fake2), 2L)
  # a structured answer
  fake3 = local_fake_provider(list("{\"n\": 1}", "more"), name = "fake3")
  h("a", model = fake3, envir = new.env(), .opts = list(returns = list(type = "object")))
  expect_length(fake_requests(fake3), 1L)
})

test_that("the review stays in the harness's own session, out of a nested peter() (S13)", {
  local_gw()
  inner = local_fake_provider(list("inner answer", "inner again"), name = "inner")
  outer = local_fake_provider(list(fake_tool("r", code = "x = peter('Count.', model = 'inner')"),
                                   "Done.", "Checked."), name = "outer")
  h = gptr_tailor(peter, mode = "auto",
                  coaching = list(review = list(text = "Look again.", rounds = 1L)))
  s = h("Tidy.", model = outer, envir = new.env())
  expect_length(fake_requests(inner), 1L)
  expect_length(fake_requests(outer), 3L)
  expect_identical(s$text, "Checked.")
})

test_that("coaching_validate() normalises the four parts and keeps tabs and newlines", {
  local_gw()
  empty = list(note = "", skills = list(), review = NULL, rules = NULL)
  expect_identical(coaching_validate(NULL), empty)
  expect_identical(coaching_validate(list()), empty)
  co = coaching_validate(list(note = "a\n\tb", skills = list(tips_skill),
                              review = list(text = "Again.", rounds = 2)))
  expect_identical(co, list(note = "a\n\tb", skills = list(tips_skill),
                            review = list(text = "Again.", rounds = 2L), rules = NULL))
  expect_identical(coaching_validate(list(review = list(text = "x")))$review$rounds, 1L)
})

test_that("coaching_validate() refuses every invalid part by name (08 3.2)", {
  local_gw()
  off = gptr_register(gptr_spec("skill", "my-tips", description = "Mine.", text = "Mine."))
  withr::defer(off())
  skill = function(...) utils::modifyList(tips_skill, list(...))
  big = strrep("a", 40000L)
  from_extension = msg_text(queue_item_message(list(source = "extension", name = "x",
                                                    text = "go"), "follow_up"))
  from_person = msg_text(queue_item_message(list(source = "pipe", text = "go"), "steer",
                                            relay = TRUE))
  bad = list(
    note = list(note = strrep("a", 8001L)),
    note = list(note = c("a", "b")),
    note = list(note = NA_character_),
    note = list(note = "a\u200bb"),
    note = list(note = "a\u202eb"),
    note = list(note = "a\001b"),
    note = list(note = "a\rb"),
    note = list(note = "See <Coaching> here."),
    note = list(note = "</plan>"),
    note = list(note = "<project_instructions a=\"1\">"),
    note = list(note = "<HARNESS>"),
    note = list(note = from_extension),
    note = list(note = from_person),
    skills = list(skills = list(skill(name = "Bad_Name"))),
    skills = list(skills = list(tips_skill, tips_skill)),
    skills = list(skills = list(skill(description = strrep("d", 1025L)))),
    skills = list(skills = list(skill(text = big), skill(name = "more", text = big))),
    skills = list(skills = list(skill(name = "my-tips"))),
    skills = list(skills = list(tips_skill[c("name", "text")])),
    skills = list(skills = list(skill(text = "<tools>"))),
    skills = list(skills = "coach-tips"),
    review = list(review = list(text = strrep("a", 2001L), rounds = 1L)),
    review = list(review = list(text = "x", rounds = 3L)),
    review = list(review = list(text = "x", rounds = 1.5)),
    review = list(review = list(text = "x\u2066", rounds = 1L)),
    review = list(review = list(text = "x", rounds = 1L, model = "opus")),
    coaching = list(tools = "read"),
    coaching = "note"
  )
  for (i in seq_along(bad)) {
    cnd = expect_error(coaching_validate(bad[[i]]), class = "gptr_error_coaching",
                       label = paste("case", i))
    expect_identical(cnd$part, names(bad)[i], label = paste("case", i))
    expect_match(conditionMessage(cnd), names(bad)[i], fixed = TRUE, label = paste("case", i))
  }
  # a surface limits which parts may differ from a base
  base = list(note = "a", skills = list(tips_skill))
  expect_identical(coaching_validate(list(note = "b", skills = list(tips_skill)), "note",
                                     base)$note, "b")
  cnd = expect_error(coaching_validate(list(note = "b"), "note", base),
                     class = "gptr_error_coaching")
  expect_identical(cnd$part, "skills")
  rules = list(never = list(list(rule = "r(fn:stepAIC)", why = "No stepwise selection.")))
  expect_identical(coaching_validate(c(base, list(rules = rules)), c("note", "rules"),
                                     base)$rules, c(rules, list(require = list())))
  cnd = expect_error(coaching_validate(c(base, list(rules = rules)), "note", base),
                     class = "gptr_error_coaching")
  expect_identical(cnd$part, "rules")
  expect_error(coaching_validate(base, "budget", base), class = "gptr_error_coaching")
})

test_that("every gptr block name is refused as a tag in coaching text", {
  local_gw()
  builtin = gptr_registry()
  builtin = builtin[startsWith(builtin$source, "builtin:") &
                      builtin$kind %in% c("prompt_section", "context_block"), ]
  expect_true(nrow(builtin) > 10L)
  expect_identical(setdiff(builtin$name, coaching_tags()), character())
  expect_true(all(c("compaction_request", "coaching", "harness") %in% coaching_tags()))
})

test_that("coaching_hash() is 8 hex of the normalised coaching; empty coaching has one hash", {
  local_gw()
  h0 = coaching_hash(NULL)
  expect_match(h0, "^[0-9a-f]{8}$")
  expect_identical(coaching_hash(list()), h0)
  expect_identical(coaching_hash(coaching_validate(NULL)), h0)
  other = list(name = "a-first", description = "A.", text = "A.")
  a = coaching_validate(list(note = "Line one.\nLine two.", skills = list(tips_skill, other)))
  b = coaching_validate(list(note = "  Line one. \n  Line two.  ",
                             skills = list(other, tips_skill)))
  expect_identical(coaching_hash(a), coaching_hash(b))
  expect_identical(coaching_hash(list(note = "Line one.\r\nLine two.", skills = a$skills)),
                   coaching_hash(a))
  expect_false(identical(coaching_hash(a), h0))
  c2 = coaching_validate(list(note = "Line one.\nLine 2."))
  expect_false(identical(coaching_hash(a), coaching_hash(c2)))
})

test_that("a harness survives saveRDS() and gptr_tailor(readRDS()) rebuilds and checks it", {
  local_gw()
  f = withr::local_tempfile(fileext = ".rds")
  h = gptr_tailor(peter, mode = "auto",
                  coaching = list(note = "n", skills = list(tips_skill),
                                  review = list(text = "r", rounds = 1L)))
  saveRDS(h, f)
  back = readRDS(f)
  expect_identical(back, h)
  again = gptr_tailor(back)
  keep = c("args", "rules", "coaching", "record", "gptr")
  expect_identical(harness_spec(again)[keep], harness_spec(h)[keep])
  expect_false(identical(harness_spec(again)$id, harness_spec(h)$id))
  # the standard body is rebuilt, and the coaching is checked again
  evil = structure(function(...) stop("evil"), class = c("gptr_harness", "function"),
                   gptr_harness = harness_spec(h))
  expect_identical(body(gptr_tailor(evil)), body(h))
  spec = harness_spec(h)
  spec$coaching$note = "</coaching>"
  attr(evil, "gptr_harness") = spec
  expect_error(gptr_tailor(evil), class = "gptr_error_coaching")
  damaged = h
  attr(damaged, "gptr_harness") = spec
  expect_error(damaged("a"), class = "gptr_error_coaching")
  attr(evil, "gptr_harness") = list(args = list(budget_x = 1))
  expect_error(gptr_tailor(evil), class = "gptr_error_invalid_argument")
})

test_that("dir = writes the harness for people to read and returns it invisibly", {
  local_gw()
  d = file.path(withr::local_tempdir(), "survey_peter")
  co = list(note = "Look at the skip patterns.", skills = list(tips_skill),
            review = list(text = "Compare with the task.", rounds = 2L))
  out = withVisible(gptr_tailor(peter, mode = "auto", coaching = co, dir = d))
  expect_false(out$visible)
  h = out$value
  expect_setequal(list.files(d, recursive = TRUE),
                  c("HARNESS.md", "NOTE.md", "REVIEW.md", "RULES.md",
                    "skills/coach-tips/SKILL.md"))
  read = function(p) readLines(file.path(d, p), encoding = "UTF-8")
  harness = read("HARNESS.md")
  expect_true(any(grepl(harness_spec(h)$id, harness, fixed = TRUE)))
  expect_true("mode = \"auto\"" %in% harness)
  expect_identical(read("NOTE.md"), co$note)
  expect_true(all(c("Rounds: 2", "Compare with the task.") %in% read("REVIEW.md")))
  expect_identical(read("skills/coach-tips/SKILL.md"),
                   c("---", "name: coach-tips", "description: Tips for this task.", "---",
                     "Check the units first."))
  expect_identical(withVisible(gptr_tailor(peter))$visible, TRUE)
})

test_that("$coaching, $record and $report are read-only views (08 3.1)", {
  local_gw()
  h = gptr_tailor(peter, coaching = list(note = "n"))
  expect_identical(h$coaching, harness_spec(h)$coaching)
  expect_identical(h[["coaching"]], harness_spec(h)$coaching)
  expect_null(h$record)
  expect_null(h$report)
  old = the$coach_reports
  withr::defer(assign("coach_reports", old, envir = the))
  the$coach_reports = list()
  the$coach_reports[[harness_spec(h)$id]] = list(runs = 3L)
  expect_identical(h$report, list(runs = 3L))
  expect_error(h$nope, class = "gptr_error_unknown_member")
  expect_error({
    h$coaching = list()
  }, "gptr_tailor(h", fixed = TRUE, class = "gptr_error_readonly")
  expect_error({
    h[["record"]] = list()
  }, class = "gptr_error_readonly")
  expect_identical(h$coaching$note, "n")
})

test_that("print() shows the fixed arguments, the coaching sizes and the record", {
  local_gw()
  local_gptr_options(quiet = TRUE)
  testthat::local_reproducible_output(width = 80)
  ext = function(gptr) NULL
  h = gptr_tailor(peter, mode = "auto", extensions = list(ext, "plugin:x"),
                  .opts = list(max_turns = 3L),
                  coaching = list(note = "abc", skills = list(tips_skill),
                                  review = list(text = "r", rounds = 2L)))
  id = harness_spec(h)$id
  expect_identical(capture.output(print(h)), c(
    paste0("<gptr_harness ", id, "> built on peter (gptr ", utils::packageVersion("gptr"), ")"),
    paste0("fixed: mode = \"auto\", extensions = list(<function>, \"plugin:x\"), ",
           ".opts = list(max_turns = 3L)"),
    "your rules: none",
    "coaching: note 3 characters, 1 skill(s), review 2 round(s), rules none",
    "record: none"
  ))
  rules = list(never = list(list(rule = "r(fn:stepAIC)", why = "No stepwise selection.")))
  expect_identical(capture.output(print(gptr_tailor(peter, rules = rules)))[2:4],
                   c("fixed: none", "your rules: 1 never, 0 require",
                     "coaching: note 0 characters, 0 skill(s), review none, rules none"))
})

test_that("gptr_tailor() is refused from model code during a run (S12, IC-53)", {
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(gptr_tailor(peter, mode = "auto"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_tailor")
  run$signal$control = "gptr_tailor"
  expect_s3_class(gptr_tailor(peter, mode = "auto"), "gptr_harness")
})

test_that("gptr_tailor() and gptr_coach() are level 4 control rows (08 3.1)", {
  root = local_project()
  tab = risk_table("functions")
  for (f in c("gptr_tailor", "gptr_coach")) {
    row = risk_lookup(f, "gptr", tab)
    expect_identical(row$level, 4L, label = f)
    expect_identical(row$category, "control", label = f)
    r = gptr_risk(paste0("gptr::", f, "(peter)"), root = root)
    expect_identical(r$level, 4L, label = f)
    expect_true("control" %in% r$categories, label = f)
  }
})

# ---------------------------------------------------------- rules (plan P29 T10; 08 1.8, 3.2)

# The text of a session's last tool result
last_result = function(s) {
  res = Filter(function(m) identical(m$role, "tool_result"), s$messages)
  msg_text(res[[length(res)]])
}

# The ids a session recorded as unmet (its gptr.unmet entries)
unmet_ids = function(s) {
  as.character(unlist(lapply(session_data(s)$entries, function(e) {
    if (identical(e$custom_type, "gptr.unmet")) e$data$ids
  })))
}

never_of = function(rule, why = "Not here.") list(never = list(list(rule = rule, why = why)))

need_of = function(...) {
  list(require = list(utils::modifyList(list(id = "a-need", any = "r(fn:set.seed)",
                                             text = "Set a seed."), list(...))))
}

test_that("the nine rules of 08 1.8 match or miss as stated, with the three widenings", {
  local_gw()
  # helpers the person defined earlier, as in a workspace
  e = new.env(parent = globalenv())
  evalq({
    to_raw = function(d) write.csv(d, "data/raw/z.csv")
    save_it = function(d) saveRDS(d, "out.rds")
    check_survey = function(d) stopifnot(nrow(d) > 0L)
  }, e)
  r_call = function(code) list(name = "r", input = list(code = code), risk = gptr_risk(code, e))
  never = list(
    "r(category:install)" = c("install.packages('MASS')" = TRUE,
                              "system('R CMD INSTALL p.tar.gz')" = TRUE,
                              "peter$sh('R CMD INSTALL .')" = TRUE, "library(MASS)" = FALSE),
    "write(data/raw/**)" = c("write.csv(d, 'data/raw/a.csv')" = TRUE,
                             "peter$write('data/raw/a.csv', 'x')" = TRUE,
                             "system('cp a.csv data/raw/b.csv')" = TRUE, "to_raw(d)" = TRUE,
                             "write.csv(d, 'data/clean/a.csv')" = FALSE,
                             "x = read.csv('data/raw/a.csv')" = FALSE),
    "r(category:network)" = c("x = read.csv('https://example.org/a.csv')" = TRUE,
                              "download.file('https://example.org/a.csv', 'a.csv')" = TRUE,
                              "x = read.csv('a.csv')" = FALSE),
    "r(fn:stepAIC)" = c("fit = MASS::stepAIC(m)" = TRUE, "fit = stepAIC(m)" = TRUE,
                        "a = AIC(m)" = FALSE))
  for (rule in names(never)) {
    for (code in names(never[[rule]])) {
      expect_identical(coaching_hit(rule_parse(rule), r_call(code)), never[[rule]][[code]],
                       label = paste(rule, code))
    }
  }
  write = function(path) list(name = "write", input = list(path = path, content = "x"))
  expect_true(coaching_hit(rule_parse("write(data/raw/**)"), write("data/raw/a.csv")))
  expect_false(coaching_hit(rule_parse("write(data/raw/**)"), write("data/a.csv")))
  need = list(
    list(any = "r(fn:write.csv,saveRDS)", hits = c("write.csv(d, 'a.csv')" = TRUE,
                                                   "saveRDS(d, 'a.rds')" = TRUE,
                                                   "save_it(d)" = TRUE,
                                                   "write.table(d, 'a.txt')" = FALSE)),
    list(any = "r(fn:set.seed)", hits = c("set.seed(1)" = TRUE, "x = rnorm(1)" = FALSE)),
    list(any = "r(fn:check_survey)", hits = c("check_survey(d)" = TRUE, "summary(d)" = FALSE)),
    list(any = list("r(fn:read.csv)", "r(fn:readLines)"), contains = "codebook",
         hits = c("x = read.csv('codebook.csv')" = TRUE, "x = readLines('doc/codebook.txt')" = TRUE,
                  "x = read.csv('data.csv')" = FALSE)))
  for (q in need) {
    rules = coaching_rules(list(require = list(list(id = "q", any = q$any,
                                                    contains = q$contains, text = "Do it."))))
    for (code in names(q$hits)) {
      expect_identical(harness_require_hit(rules$require[[1L]], r_call(code)), q$hits[[code]],
                       label = code)
    }
  }
})

test_that("a never rule denies in auto and yolo, in a nested shell call and a sub-agent (S3)", {
  local_gw()
  why = "denied by the coaching rule r(category:install): Use the installed packages."
  h = gptr_tailor(peter, coaching = list(rules = never_of("r(category:install)",
                                                          "Use the installed packages.")))
  for (mode in c("auto", "yolo")) {
    fake = local_fake_provider(list(fake_tool("r", code = "install.packages('nothing')"), "Done."),
                               name = paste0("never-", mode))
    s = h("Go.", model = fake, mode = mode, envir = new.env())
    expect_match(last_result(s), why, fixed = TRUE, label = mode)
  }
  nested = "cmd = paste('R CMD', 'INSTALL x.tar.gz'); peter$sh(cmd)"
  fake = local_fake_provider(list(fake_tool("r", code = nested), "Done."), name = "never-sh")
  s = h("Go.", model = fake, mode = "yolo", envir = new.env())
  expect_match(last_result(s), why, fixed = TRUE)
  local_fake_provider(list(fake_tool("r", code = "install.packages('nothing')"), "Inner."),
                      name = "never-inner")
  nest = "s2 = peter('Go.', model = 'never-inner')"
  outer = local_fake_provider(list(fake_tool("r", code = nest), "Done."), name = "never-outer")
  e = new.env()
  h("Go.", model = outer, mode = "auto", envir = e)
  expect_match(last_result(e$s2), why, fixed = TRUE)
})

test_that("a requirement is reminded at most twice, then recorded as unmet (08 3.2)", {
  local_gw()
  local_gptr_options(quiet = FALSE)
  last = function(r) msg_text(utils::tail(r$messages, 1L)[[1L]])
  rules = need_of(id = "save-results", any = "r(fn:write.csv,saveRDS)",
                  text = "Save the table with write.csv().")
  h = gptr_tailor(peter, coaching = list(rules = rules))
  fake = local_fake_provider(list("one", "two", "three", "four"))
  expect_message({
    s = h("a", model = fake, envir = new.env())
  }, "This run finished without: save-results", fixed = TRUE, class = "gptr_message_notice")
  req = fake_requests(fake)
  expect_length(req, 3L)
  expect_match(last(req[[2L]]), "Save the table with write.csv().", fixed = TRUE)
  expect_match(last(req[[3L]]), "Save the table with write.csv().", fixed = TRUE)
  expect_identical(unmet_ids(s), "save-results")
  # never at the turn limit, and the run is still recorded as unmet
  fake2 = local_fake_provider(list("one", "two"), name = "fake2")
  s2 = suppressMessages(h("a", model = fake2, envir = new.env(), .opts = list(max_turns = 1L)))
  expect_length(fake_requests(fake2), 1L)
  expect_length(session_data(s2)$queue$follow_up, 0L)
  expect_identical(unmet_ids(s2), "save-results")
})

test_that("the review and the requirements share one follow-up and the budget of two", {
  local_gw()
  local_gptr_options(quiet = TRUE)
  last = function(r) msg_text(utils::tail(r$messages, 1L)[[1L]])
  rules = need_of(text = "Call set.seed() first.")
  h = gptr_tailor(peter, coaching = list(rules = rules,
                                         review = list(text = "Look again.", rounds = 1L)))
  fake = local_fake_provider(list("one", "two", "three", "four"))
  h("a", model = fake, envir = new.env())
  req = fake_requests(fake)
  expect_length(req, 3L)
  expect_match(last(req[[2L]]), "Call set.seed() first.\n\nLook again.", fixed = TRUE)
  expect_match(last(req[[3L]]), "first.$")
  # met: only the review, as many rounds as it has
  h2 = gptr_tailor(peter, coaching = list(rules = rules,
                                          review = list(text = "Look again.", rounds = 2L)))
  fake2 = local_fake_provider(list(fake_tool("r", code = "set.seed(1)"), "one", "two", "three",
                                   "four"), name = "fake2")
  s = h2("a", model = fake2, envir = new.env(), mode = "auto")
  req = fake_requests(fake2)
  expect_length(req, 4L)
  expect_match(last(req[[3L]]), "): Look again.", fixed = TRUE)
  expect_match(last(req[[4L]]), "): Look again.", fixed = TRUE)
  expect_identical(unmet_ids(s), character())
})

test_that("a requirement is met by a helper from an earlier turn, a plot or a new file", {
  local_gw()
  local_gptr_options(quiet = TRUE)
  writeLines("var,meaning", "codebook.csv")
  codebook = need_of(any = "r(fn:read.csv,readLines)", contains = "codebook",
                     text = "Read the codebook.")
  h = gptr_tailor(peter, mode = "auto", coaching = list(rules = codebook))
  fake = local_fake_provider(list(fake_tool("r", code = "rd = function(f) read.csv(f)"),
                                  fake_tool("r", code = "cb = rd('codebook.csv')"), "Done.",
                                  "again"))
  # a workspace outside gptr's namespace, as the person's own is
  s = h("a", model = fake, envir = new.env(parent = globalenv()))
  expect_length(fake_requests(fake), 3L)
  expect_identical(unmet_ids(s), character())
  # a call that failed meets nothing
  fake2 = local_fake_provider(list(fake_tool("r", code = "x = read.csv('codebook-none.csv')"),
                                   "Done.", "Done.", "Done."), name = "fake2")
  expect_identical(unmet_ids(h("a", model = fake2, envir = new.env())), "a-need")
  # a plot
  plot_peter = gptr_tailor(peter, mode = "auto",
                           coaching = list(rules = need_of(any = NULL, made = "plot")))
  fake3 = local_fake_provider(list(fake_tool("r", code = "plot(1:3)"), "Done.", "again"),
                              name = "fake3")
  expect_identical(unmet_ids(plot_peter("a", model = fake3, envir = new.env())), character())
  # made = "file:...": a file changed during the run, not an older one
  dir.create("results")
  writeLines("old", "results/old.csv")
  Sys.setFileTime("results/old.csv", Sys.time() - 3600)
  file_peter = gptr_tailor(peter, mode = "auto", coaching = list(
    rules = need_of(any = NULL, made = "file:results/*.csv", text = "Write results/x.csv.")))
  fake4 = local_fake_provider(list(fake_tool("r", code = "x = 1"), "Done.", "Done.", "Done."),
                              name = "fake4")
  expect_identical(unmet_ids(file_peter("a", model = fake4, envir = new.env())), "a-need")
  fake5 = local_fake_provider(list(fake_tool("r", code = "write.csv(mtcars, 'results/x.csv')"),
                                   "Done.", "again"), name = "fake5")
  expect_identical(unmet_ids(file_peter("a", model = fake5, envir = new.env())), character())
  expect_length(fake_requests(fake5), 2L)
})

test_that("a refusal stops the reminders, but a coaching denial does not (08 3.2)", {
  local_gw()
  local_gptr_options(quiet = TRUE)
  review = list(text = "Look again.", rounds = 1L)
  rules = never_of("r(fn:stepAIC)", "Choose variables by hand.")
  # a coaching denial: the review still follows
  h = gptr_tailor(peter, mode = "auto", coaching = list(rules = rules, review = review))
  fake = local_fake_provider(list(fake_tool("r", code = "fit = stepAIC(m)"), "Done.", "Checked.",
                                  "more"))
  s = h("a", model = fake, envir = new.env())
  expect_match(msg_text(s$messages[[3L]]), "denied by the coaching rule", fixed = TRUE)
  expect_length(fake_requests(fake), 3L)
  # your own rule's denial: no review
  mine = gptr_tailor(peter, mode = "auto", rules = rules, coaching = list(review = review))
  fake2 = local_fake_provider(list(fake_tool("r", code = "fit = stepAIC(m)"), "Done.", "more"),
                              name = "fake2")
  s2 = mine("a", model = fake2, envir = new.env())
  expect_match(last_result(s2), "denied by your rule r(fn:stepAIC): Choose variables by hand.",
               fixed = TRUE)
  expect_length(fake_requests(fake2), 2L)
})

test_that("your own rules stay in your half: enforced as yours, kept by every coaching", {
  local_gw()
  mine = list(never = never_of("r(fn:stepAIC)", "Choose variables by hand.")$never,
              require = need_of()$require)
  h = gptr_tailor(peter, mode = "auto", rules = mine)
  spec = harness_spec(h)
  expect_identical(spec$rules, mine)
  expect_null(spec$coaching$rules)
  # coaching, written by hand or by a coach, never reaches your rules
  coached = gptr_tailor(h, coaching = list(rules = never_of("r(fn:lm)")))
  expect_identical(harness_spec(coached)$rules, mine)
  expect_identical(harness_spec(coached)$coaching$rules,
                   c(never_of("r(fn:lm)"), list(require = list())))
  expect_identical(harness_spec(gptr_tailor(h, rules = list()))$rules, NULL)
  # the factory key covers your rules as well as the coaching
  key = function(x) attr(harness_factory(harness_spec(x)), "gptr_key")
  expect_false(identical(key(h), key(gptr_tailor(h, rules = never_of("r(fn:glm)")))))
  expect_error(gptr_tailor(peter, rules = list(allow = list("r(level<=1)"))), "Your rules",
               class = "gptr_error_coaching")
  # a console transcript defines the harness with your rules, and the definition rebuilds them
  def = doc_harness_def(spec)
  expect_match(def$define, "rules = list(never = list(list(rule = \"r(fn:stepAIC)\"", fixed = TRUE)
  back = eval(str2lang(sub("^h_[0-9A-Za-z]+ = ", "", def$define)))
  expect_identical(harness_spec(back)$rules, mine)
})

test_that("coaching rules are checked field by field; inert and risky patterns are refused", {
  local_gw()
  ok = list(never = never_of("r(category:install)")$never,
            require = list(list(id = "save-results", any = "r(fn:write.csv,saveRDS)",
                                text = "Save the table."),
                           list(id = "codebook", any = list("r(fn:read.csv)", "r(fn:readLines)"),
                                contains = "codebook", text = "Read it."),
                           list(id = "a-plot", made = "plot", text = "Plot it."),
                           list(id = "a-file", made = "file:results/**", text = "Save it.")))
  got = coaching_validate(list(rules = ok))$rules
  expect_identical(got$require[[2L]]$any, c("r(fn:read.csv)", "r(fn:readLines)"))
  ok$require[[2L]]$any = c("r(fn:read.csv)", "r(fn:readLines)")
  expect_identical(got, ok)
  expect_null(coaching_validate(list(rules = list(never = list())))$rules)
  for (fine in c("r(sh:R CMD INSTALL*)", "r(sql:drop)", "write(data/raw/**)", "*(~/.ssh/**)",
                 "r(fn:peter$sh)", "r(category:unlisted)")) {
    expect_identical(coaching_rules(never_of(fine))$never[[1L]]$rule, fine, label = fine)
  }
  never = function(...) {
    list(never = list(utils::modifyList(never_of("r(fn:stepAIC)")$never[[1L]], list(...))))
  }
  five = lapply(1:5, function(i) list(id = paste0("n", i), any = "r(fn:set.seed)", text = "x"))
  bad = list(
    list(allow = list("r(level<=1)")), list(ask = list()), "r(fn:x)",
    list(never = list(list(rule = "r(fn:x)"))),
    list(never = rep(never_of("r(fn:x)")$never, 9L)),
    never(rule = "r(fn:MASS::stepAIC)"), never(rule = "r(category:wizardry)"),
    never(rule = "r(level<=1)"), never(rule = "r(secret:API_KEY)"), never(rule = "r"),
    never(rule = "*"), never(rule = "write"), never(rule = "r(*)"), never(rule = "not a rule("),
    never(rule = paste0("r(fn:", strrep("a", 200L), ")")), never(rule = 1),
    never(why = strrep("w", 301L)), never(why = "a\u202eb"), never(why = "<tools>"),
    need_of(any = "r(fn:install.packages)"), need_of(any = "r(fn:system)"),
    need_of(any = "r(fn:peter$sh)"), need_of(any = "r(fn:dbGetQuery)"),
    need_of(any = "r(category:file_write)"), need_of(any = "r(sh:ls *)"),
    need_of(any = "r(sql:select)"), need_of(any = "write(results/**)"),
    need_of(any = list("r(fn:set.seed)", 1)), need_of(any = character()),
    need_of(any = rep("r(fn:set.seed)", 20L)),
    need_of(id = "Save Results"), need_of(id = strrep("a", 201L)), need_of(made = "plot"),
    need_of(any = NULL), need_of(any = NULL, made = "table"),
    need_of(any = NULL, made = "file:../x.csv"), need_of(any = NULL, made = "file:~/x.csv"),
    need_of(any = NULL, made = "file:/etc/x"), need_of(any = NULL, made = "file:"),
    need_of(contains = strrep("c", 101L)), need_of(text = strrep("t", 501L)),
    need_of(text = "x\u200by"), need_of(extra = 1),
    list(require = c(need_of()$require, need_of()$require)), list(require = five))
  for (i in seq_along(bad)) {
    cnd = expect_error(coaching_validate(list(rules = bad[[i]])), class = "gptr_error_coaching",
                       label = paste("case", i))
    expect_identical(cnd$part, "rules", label = paste("case", i))
    expect_match(conditionMessage(cnd), "^The coaching's rules ", label = paste("case", i))
  }
})

test_that("dir = writes your rules and the coaching's rules", {
  local_gw()
  d = file.path(withr::local_tempdir(), "h")
  gptr_tailor(peter, rules = never_of("r(fn:stepAIC)", "By hand."),
              coaching = list(rules = need_of(contains = "seed")), dir = d)
  expect_true("- never `r(fn:stepAIC)`: By hand." %in% readLines(file.path(d, "HARNESS.md")))
  expect_identical(readLines(file.path(d, "RULES.md")),
                   "- require a-need (`r(fn:set.seed)`, contains \"seed\"): Set a seed.")
})
