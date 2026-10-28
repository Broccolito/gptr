# Tests for R/gptr-child.R (plan P29 T7; 08 section 3.3): plain data across processes, the
# child entry with its fence and event stream, the safe reading of reports, and the scheduler.

plain_rt = function(x) plain_decode(json_encode(plain_encode(x)))

# child_main() in this process for one job: its result as the parent reads it and its stream
child_local = function(job, ...) {
  dir = withr::local_tempdir()
  spec = file.path(dir, "spec.rds")
  out = file.path(dir, "result.json")
  save_rds(c(list(job = job, options = list(), parent = NULL), list(...)), spec,
           refhook = worker_refhook)
  stream = file.path(dir, "stream.jsonl")
  con = file(stream, "wb")
  child_main(spec, out, out = con)
  close(con)
  list(res = child_read(out), lines = readLines(stream, encoding = "UTF-8"))
}

# The coaching event lines of a child's stdout, by type
child_events = function(lines) {
  vapply(lines, function(l) json_decode(l)$gptr_coach, "", USE.NAMES = FALSE)
}

coach_schema = list(type = "object", properties = list(note = list(type = "string")),
                    required = list("note"))

test_that("plain data round-trips exactly (08 section 3.3)", {
  x = c(pi, 1 / 3, NA, NaN, -0, Inf, -Inf, 5e-324)
  y = plain_rt(x)
  expect_identical(y, x)
  expect_true(is.na(y[[3L]]) && !is.nan(y[[3L]]))
  expect_true(is.nan(y[[4L]]))
  expect_identical(1 / y[[5L]], -Inf)
  vals = list(c(a = 1L, b = NA), c(TRUE, NA, FALSE), c("x", NA, "caf\u00e9"), matrix(1:6, 2L),
              factor(c("b", NA, "a"), levels = c("b", "a")), as.Date(c("2026-10-28", NA)),
              as.POSIXct("2026-10-28 12:34:56.25", tz = "America/Los_Angeles"),
              data.frame(n = c(1.5, NA), s = c("x", NA), f = factor(c("u", "v")),
                         d = as.Date(c("2026-01-01", NA)), l = c(TRUE, NA)),
              list(a = 1, b = list(c = "x", d = NULL), 3L), character(), list())
  for (v in vals) expect_identical(plain_rt(v), v)
  expect_null(plain_rt(NULL))
})

test_that("closures, environments, S4 and other classes travel as printed summaries", {
  x = list(f = function(x) x + 1, e = new.env(), s4 = methods::getClass("numeric"),
           fit = stats::lm(mpg ~ wt, data = mtcars), dt = as.difftime(1, units = "secs"))
  expect_identical(vapply(plain_encode(x)$data, function(n) n$type, ""), rep("summary", 5L))
  y = plain_rt(x)
  expect_true(all(vapply(y, rlang::is_string, NA)))
  expect_match(y$f, "^<function>")
  expect_match(y$e, "^<environment>")
  env = new.env()
  delayedAssign("p", stop("forced"), assign.env = env)
  makeActiveBinding("a", function() stop("forced"), env)
  env$made = 1
  objs = child_objects(env, list(made = 2))
  expect_identical(objs$p, "<an unevaluated promise or active binding>")
  expect_identical(objs$a, "<an unevaluated promise or active binding>")
  expect_identical(objs$made, 1)
  expect_false("made" %in% names(child_objects(env, list(made = 1))))
})

test_that("the parent refuses unknown keys, types, classes and sizes", {
  refused = function(json) expect_error(plain_decode(json), class = "gptr_error_untrusted")
  expect_identical(plain_decode('{"type":"double","len":1,"data":"AAAAAAAA8D8="}'), 1)
  refused('{"type":"double","len":1,"data":"AAAAAAAA8D8=","class":"lm"}')
  refused('{"type":"closure","len":1,"data":"x"}')
  refused('{"type":"environment","len":0,"data":[]}')
  refused('{"type":"double","len":10000000,"data":""}')
  refused('{"type":"double","len":2,"data":"AAAAAAAA8D8="}')
  refused('{"type":"factor","len":1,"data":"BQAAAA==","levels":["a"]}')
  deep = Reduce(function(n, i) list(type = "list", len = 1L, data = list(n)), 1:25,
                list(type = "logical", len = 0L, data = ""))
  refused(json_encode(deep))
  path = withr::local_tempfile(fileext = ".json")
  writeLines(json_encode(plain_encode(list(id = "a", status = "idle", risk = 0L, run = "x"))),
             path)
  expect_error(child_read(path), class = "gptr_error_untrusted")
  writeLines(json_encode(plain_encode(list(id = "a", status = "idle", risk = 7L))), path)
  expect_error(child_read(path), class = "gptr_error_untrusted")
})

test_that("a report is read in the safe direction (08 section 3.3)", {
  stream = function(...) {
    st = new.env(parent = emptyenv())
    st$risk = 0L
    st$refusals = child_refusals()
    st$unmet = character()
    for (line in c(...)) child_line(st, line)
    st
  }
  st = stream('{"gptr_coach":"risk","level":3}', "not json", '{"type":"permission_request"}',
              '{"gptr_coach":"risk","level":9}',
              '{"gptr_coach":"refusal","id":"c1","tool":"r","reason":"denied"}',
              '{"gptr_coach":"unmet","id":"save-results"}')
  path = withr::local_tempfile(fileext = ".json")
  writeLines(json_encode(plain_encode(child_result_new("a", status = "idle", risk = 1L))), path)
  final = child_merge(child_read(path), st, "final")
  expect_identical(final$risk, 3L)
  expect_identical(final$refusals$id, "c1")
  expect_identical(final$unmet, "save-results")
  start = child_merge(child_read(path), stream('{"gptr_coach":"risk","level":4}'), "start")
  expect_identical(start$risk, 1L)
})

test_that("plan jobs share at most two slots per account; a reported limit skips the rest", {
  lanes = child_lanes(c("claude", "api", "claude", "claude", "codex", "fake"))
  expect_identical(lanes, list(c(1L, 4L), 2L, 3L, 5L, 6L))
  ctx = new.env(parent = emptyenv())
  ctx$jobs = list(list(id = "a"))
  ctx$kinds = "claude"
  ctx$out = list(NULL)
  ctx$limits = list(claude = list(resets_at = "3:45pm"))
  h = child_lane(ctx, 1L)
  expect_true(h$run$settled)
  expect_identical(ctx$out[[1L]]$status, "skipped")
  expect_identical(ctx$out[[1L]]$limit$resets_at, "3:45pm")
})

test_that("an object that cannot cross processes is refused before anything starts", {
  con = textConnection("x")
  withr::defer(close(con))
  job = list(id = "a", role = "run", prompt = "p", objects = list(con = con),
             model = "fake/fake-1")
  expect_error(coach_run_jobs(list(job)), "`con` cannot be sent",
               class = "gptr_error_invalid_argument")
  expect_false(any(gptr_jobs()$kind == "worker"))
})

test_that("a run's child gets the person's rules anchored to their project, options, files", {
  root = local_project(files = list(AGENTS.md = "Be brief."))
  local_permission_rules()
  gptr_permissions(deny = c("write(data/**)", "edit(notes.md)", "r(fn:saveRDS)"))
  local_gptr_options(max_turns = 7L)
  expect_identical(child_instructions(), list(list(label = "AGENTS.md", text = "Be brief.\n")))
  expect_identical(child_options()$gptr.max_turns, 7L)
  expect_identical(child_options()$gptr.replay, replay_mode())
  rules = child_rules()
  expect_true(paste0("write(/", root, "/data/**)") %in% rules$deny)
  expect_true(paste0("edit(/", root, "/**/notes.md)") %in% rules$deny)
  expect_true("r(fn:saveRDS)" %in% rules$deny)
  withr::local_options(gptr.project_root = withr::local_tempdir())
  call = list(name = "write", input = list(path = file.path(root, "data", "x.csv")))
  expect_identical(rule_match(rules, call)$deny, paste0("write(/", root, "/data/**)"))
})

test_that("the fence denies writes outside, setwd away, installs and other R processes", {
  out = path_norm(file.path(dirname(tempdir()), "gptr-fence.csv"))
  inside = path_norm(file.path(tempdir(), "gptr-fence.csv"))
  fence = function(name, input) {
    risk = if (identical(name, "r")) gptr_risk(input$code)
    child_fence(list(name = name, input = input, risk = risk), NULL)$decision %||% "allow"
  }
  r = function(code) fence("r", list(code = code))
  expect_identical(fence("write", list(path = out)), "deny")
  expect_identical(fence("edit", list(path = out)), "deny")
  expect_identical(fence("write", list(path = inside)), "allow")
  expect_identical(fence("read", list(path = out)), "allow")
  expect_identical(r(sprintf("write.csv(mtcars, '%s')", out)), "deny")
  expect_identical(r(sprintf("peter$write('%s', 'x')", out)), "deny")
  expect_identical(r(sprintf("write.csv(mtcars, '%s')", inside)), "allow")
  expect_identical(r(sprintf("x = read.csv('%s')", out)), "allow")
  expect_identical(r(sprintf("setwd('%s')", dirname(out))), "deny")
  expect_identical(r(sprintf("setwd('%s')", path_norm(tempdir()))), "allow")
  expect_identical(r("setwd(d)"), "deny")
  expect_identical(r("install.packages('x')"), "deny")
  expect_identical(r("system('R CMD INSTALL pkg')"), "deny")
  expect_identical(r("peter$sh('R CMD INSTALL .')"), "deny")
  expect_identical(r("system('Rscript -e 1')"), "deny")
  expect_identical(r("callr::r(function() 1)"), "deny")
  expect_identical(r("system('python x.py')"), "allow")
  expect_identical(r("m = mean(1:3)"), "allow")
})

test_that("a run's child: a fresh folder, the fence in the run and its sub-agent, events", {
  skip_on_cran()
  local_project()
  out = path_norm(file.path(dirname(tempdir()), "gptr-child-fence.csv"))
  fake = gptr_fake_provider(list(
    fake_tool("r", code = "wd = getwd(); seen = list.files(all.files = TRUE, no.. = TRUE)"),
    fake_tool("write", path = out, content = "x"),
    fake_tool("r", code = "install.packages('nothing')"),
    fake_tool("r", code = "system('R CMD INSTALL nothing')"),
    fake_tool("r", code = sprintf("setwd('%s')", dirname(out))),
    fake_tool("r", code = "s = peter('Write it.')"),
    fake_tool("write", path = out, content = "x"),
    "sub done",
    fake_tool("r", code = "m = mean(d); gptr_return(m)"),
    "all done"), name = "childfake")
  got = child_local(list(id = "r1", role = "run", prompt = "Do it.",
                         objects = list(d = c(1, 2, 3)), args = list(mode = "auto"),
                         model = fake))
  res = got$res
  expect_identical(res$id, "r1")
  expect_identical(res$status, "idle")
  expect_identical(res$text, "all done")
  expect_identical(res$value, 2)
  expect_identical(res$objects$m, 2)
  expect_identical(res$objects$seen, character())
  expect_true(path_inside(res$objects$wd, tempdir()))
  expect_false(dir.exists(res$objects$wd))
  expect_false(file.exists(out))
  expect_identical(nrow(res$refusals), 5L)
  expect_true(all(grepl("fence", res$refusals$reason, fixed = TRUE)))
  events = child_events(got$lines)
  expect_identical(sum(events == "refusal"), 5L)
  levels = vapply(got$lines[events == "risk"], function(l) json_decode(l)$level, 1L)
  expect_identical(res$risk, max(levels))
  expect_s3_class(res$usage, "data.frame")
  expect_match(res$transcript, "## assistant", fixed = TRUE)
  expect_identical(nrow(res$files), 0L)
  expect_null(the$model_gate)
  expect_null(the$coach_role)
  expect_false("fence" %in% names(registry_all("policy")))
})

test_that("a run that needs approval ends blocked", {
  skip_on_cran()
  local_project()
  fake = gptr_fake_provider(list(fake_tool("r", code = "x = 1"), "never"), name = "blockfake")
  res = child_local(list(id = "b", role = "run", prompt = "Set x.",
                         args = list(mode = "manual"), model = fake))$res
  expect_identical(res$status, "blocked")
  expect_match(res$error, "approval", fixed = TRUE)
  expect_identical(nrow(res$refusals), 1L)
})

test_that("a run's child is unattended, inline and gated; a login token reaches only its CLI", {
  skip_on_cran()
  local_project()
  local_vault()
  token = "sk-ant-oat01-synthetic-not-a-token"
  withr::local_envvar(CLAUDE_CODE_OAUTH_TOKEN = token)
  # the job travels as a file, so the fake reports through one
  seen = withr::local_tempfile()
  fake = gptr_fake_provider(function(request) {
    saveRDS(list(r = Sys.getenv("CLAUDE_CODE_OAUTH_TOKEN", unset = NA),
                 cli = child_env("cli-claude")[["CLAUDE_CODE_OAUTH_TOKEN"]],
                 inline = identical(registry_get("backend", "worker")$start,
                                    registry_get("backend", "inline")$start),
                 role = the$coach_role, gate = identical(the$model_gate, coach_model_kind),
                 options = options()[c("gptr.interactive", "gptr.noninteractive_ask",
                                       "gptr.record")]), seen)
    "done"
  }, name = "tokenfake")
  res = child_local(list(id = "t", role = "run", prompt = "Hi.", model = fake))$res
  expect_identical(res$status, "idle")
  expect_identical(readRDS(seen), list(
    r = NA_character_, cli = token, inline = TRUE, role = "run", gate = TRUE,
    options = list(gptr.interactive = FALSE, gptr.noninteractive_ask = "stop",
                   gptr.record = "off")))
  expect_identical(Sys.getenv("CLAUDE_CODE_OAUTH_TOKEN"), token)
  builtin = child_env_profiles_builtin()[["cli-claude"]]
  expect_identical(child_env_profile("cli-claude")$set, builtin$set)
})

test_that("a coach's child has no tool and answers in its schema; a tool call voids it", {
  skip_on_cran()
  local_project()
  ok = child_local(list(id = "c1", role = "coach", prompt = "Coach.", schema = coach_schema,
                        model = gptr_fake_provider(list('{"note": "use mean()"}'),
                                                   name = "coachfake")))$res
  expect_identical(ok$status, "idle")
  expect_identical(ok$value, list(note = "use mean()"))
  expect_identical(nrow(ok$refusals), 0L)
  fake = gptr_fake_provider(list(fake_tool("r", code = "1"), '{"note": "x"}'),
                            name = "coachfake")
  bad = child_local(list(id = "c2", role = "coach", prompt = "Coach.", schema = coach_schema,
                         model = fake))$res
  expect_identical(bad$status, "error")
  expect_null(bad$value)
  expect_match(bad$error, "tool", fixed = TRUE)
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

worker_rows = function() {
  jobs = gptr_jobs()
  jobs$pid[jobs$kind == "worker"]
}

test_that("a run and a coach each run in their own process and return plain data", {
  local_worker_lib()
  local_project()
  run_fake = gptr_fake_provider(list(fake_tool("r", code = "m = mean(d); gptr_return(m)"),
                                     "the mean is 2"), name = "runfake")
  jobs = list(
    list(id = "run", role = "run", prompt = "Average d.", objects = list(d = c(1, 2, 3)),
         args = list(mode = "auto"), model = run_fake),
    list(id = "coach", role = "coach", prompt = "Coach.", schema = coach_schema,
         model = gptr_fake_provider(list('{"note": "use mean()"}'), name = "coachfake")))
  res = coach_run_jobs(jobs, max_active = 2L)
  expect_identical(vapply(res, function(r) r$id, ""), c("run", "coach"))
  expect_identical(res[[1L]]$status, "idle")
  expect_identical(res[[1L]]$text, "the mean is 2")
  expect_identical(res[[1L]]$value, 2)
  expect_identical(res[[1L]]$objects$m, 2)
  expect_match(res[[1L]]$transcript, "mean(d)", fixed = TRUE)
  expect_identical(res[[2L]]$status, "idle")
  expect_identical(res[[2L]]$value, list(note = "use mean()"))
  expect_length(worker_rows(), 0L)
})

test_that("at most max_active children run; a forged stream line is read in the safe direction", {
  local_worker_lib()
  skip_on_os("windows")
  local_project()
  forged = paste0("echo '", '{"gptr_coach":"risk","level":4}', "'")
  fake = gptr_fake_provider(list(fake_tool("r", code = paste0("system(", deparse(forged), ")")),
                                 list(text = "done", delay = 1)), name = "forgefake")
  job = function(id, direction) {
    list(id = id, role = "run", prompt = "Echo.", args = list(mode = "auto"), model = fake,
         direction = direction)
  }
  box = new.env(parent = emptyenv())
  box$peak = 0L
  task = reactor_task(function() {
    box$peak = max(box$peak, length(worker_rows()))
    0.05
  })
  withr::defer(reactor_cancel(task))
  res = coach_run_jobs(list(job("s", "start"), job("f", "final"), job("x", "final")),
                       max_active = 2L)
  expect_identical(box$peak, 2L)
  expect_identical(vapply(res, function(r) r$status, ""), rep("idle", 3L))
  expect_lt(res[[1L]]$risk, 4L)
  expect_identical(res[[2L]]$risk, 4L)
})

test_that("interrupting coach_run_jobs() kills every child", {
  local_worker_lib()
  local_project()
  hang = gptr_fake_provider(list(list(hang = TRUE)), name = "hangfake")
  job = list(role = "run", prompt = "Wait.", model = hang)
  jobs = list(c(list(id = "a"), job), c(list(id = "b"), job))
  box = new.env(parent = emptyenv())
  task = reactor_task(function() {
    pids = worker_rows()
    if (length(pids) < 2L) return(0.1)
    box$handles = lapply(pids, ps::ps_handle)
    rlang::interrupt()
  })
  withr::defer(reactor_cancel(task))
  # the console's interrupt policy says that the call was aborted
  utils::capture.output({
    got = tryCatch(coach_run_jobs(jobs, max_active = 2L), interrupt = function(e) "interrupted")
  })
  expect_identical(got, "interrupted")
  expect_length(box$handles, 2L)
  for (h in box$handles) expect_false(ps::ps_is_running(h))
  expect_length(worker_rows(), 0L)
})
