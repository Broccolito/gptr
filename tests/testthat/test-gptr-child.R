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

test_that("a value the reader cannot rebuild exactly travels as its summary, never refused", {
  latin = "caf\xe9"
  Encoding(latin) = "latin1"
  bytes = "caf\xc3\xa9"
  Encoding(bytes) = "bytes"
  exact = list(latin = latin, now = .POSIXct(1.5e9), utc = .POSIXct(1.5e9, tz = "UTC"),
               df = data.frame(a = 1:3), named = c(a = 1, b = 2))
  for (k in names(exact)) expect_identical(plain_rt(exact[[k]]), exact[[k]], label = k)
  shown = list(na_level = addNA(factor(c("a", NA))), ordered = factor("a", ordered = TRUE),
               bytes = bytes, native = rawToChar(as.raw(c(0x61, 0xff))),
               dimnames = matrix(1:4, 2L, dimnames = list(c("a", "b"), NULL)),
               rownames = mtcars[1:2, 1:2], subset = data.frame(a = 1:3)[2:3, , drop = FALSE],
               na_name = stats::setNames(1:2, c("a", NA)),
               bad_name = stats::setNames(list(1), rawToChar(as.raw(0xff))))
  path = withr::local_tempfile(fileext = ".json")
  writeLines(json_encode(plain_encode(child_result_new("a", status = "idle", objects = shown))),
             path)
  res = child_read(path)
  for (k in names(shown)) expect_match(res$objects[[k]], "^<", label = k)
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

test_that("a result whose fields have the wrong shape is refused, as a forged one is", {
  path = withr::local_tempfile(fileext = ".json")
  read = function(...) {
    writeLines(json_encode(plain_encode(child_result_new("a", status = "idle", risk = 0L, ...))),
               path)
    child_read(path)
  }
  expect_identical(read(text = "ok", turns = 2L)$turns, 2L)
  bad = list(list(text = c("a", "b")), list(text = 1), list(turns = 1.5), list(turns = c(1L, 2L)),
             list(usage = data.frame(input = "x", output = 1, cost = 0)), list(usage = "x"),
             list(objects = list(1, 2)), list(objects = "x"), list(unmet = 1), list(refusals = "x"),
             list(limit = "3pm"), list(transcript = c("a", "b")), list(first_user = 1),
             list(error = c("a", "b")), list(files = "x"), list(checks = 1))
  for (b in bad) {
    expect_error(do.call(read, b), "has the wrong shape", class = "gptr_error_untrusted",
                 label = names(b))
  }
})

test_that("a value too large or deep for the reader travels as its summary (08 section 3.3)", {
  deep = Reduce(function(x, i) list(x), seq_len(25L), 1)
  wide = lapply(seq_len(60000L), function(i) list(i))
  res = plain_rt(child_result_new("a", status = "idle", text = "kept",
                                  value = as.list(seq_len(150000L)),
                                  objects = list(deep = deep, wide = wide)))
  expect_identical(res$text, "kept")
  expect_match(res$value, "^<list>")
  # nested down to the reader's depth, counted from the result (deep sits at depth 2)
  inner = res$objects$deep
  for (i in seq_len(17L)) inner = inner[[1L]]
  expect_type(inner, "list")
  expect_match(inner[[1L]], "^<list>")
  # the values of one result stay within the reader's count
  expect_identical(res$objects$wide[[1L]], list(1L))
  expect_type(res$objects$wide[[60000L]], "character")
})

test_that("a value that uses up the reader's count leaves the objects a list", {
  testthat::local_mocked_bindings(plain_max = utils::modifyList(plain_max, list(nodes = 5000)))
  path = withr::local_tempfile(fileext = ".json")
  writeLines(json_encode(plain_encode(child_result_new("a", status = "idle",
                                                       value = as.list(rep(1, 4984L)),
                                                       objects = list(a = 1)))), path)
  res = child_read(path)
  expect_identical(res$objects, list(a = 1))
  expect_match(res$value, "^<list>")
})

test_that("a long list's summary prints only what it keeps", {
  skip_on_cran()
  max = getOption("max.print")
  started = proc.time()[["elapsed"]]
  s = plain_summary(as.list(seq_len(2e5)))
  expect_lt(proc.time()[["elapsed"]] - started, 10)
  expect_match(s$data, "^<list>\n\\[\\[1\\]\\]")
  expect_match(s$data, "more characters]", fixed = TRUE)
  expect_identical(getOption("max.print"), max)
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

test_that("a result the parent cannot merge ends its job with an error, and the slot moves on", {
  st = new.env(parent = emptyenv())
  st$i = 1L
  st$risk = 0L
  st$refusals = child_refusals()
  st$unmet = character()
  st$dir = withr::local_tempdir()
  st$result_path = file.path(st$dir, "result.json")
  forged = child_result_new("a", status = "idle")
  forged$refusals = structure(list(id = data.frame(a = 1:2, b = 3:4, c = 5:6), tool = c("t", "u"),
                                   reason = c("r", "s")), row.names = 1:2, class = "data.frame")
  writeLines(json_encode(plain_encode(forged)), st$result_path)
  ctx = new.env(parent = emptyenv())
  ctx$jobs = list(list(id = "a"))
  ctx$kinds = "fake"
  ctx$out = list(NULL)
  ctx$limits = list()
  ln = new.env(parent = emptyenv())
  ln$queue = integer()
  child_exit(ctx, ln, st, 0L)
  expect_identical(ctx$out[[1L]]$status, "error")
  expect_match(ctx$out[[1L]]$error, "differing number of rows", fixed = TRUE)
  expect_true(ln$settled)
  expect_false(dir.exists(st$dir))
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

test_that("the fence denies writes outside, moving away from the folder, installs, R processes", {
  # the run's folder is the project root and the working folder, as in child_main()
  run = path_norm(withr::local_tempdir())
  withr::local_options(gptr.project_root = run)
  withr::local_dir(run)
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
  expect_identical(r(sprintf("write.table(mtcars, '%s')", inside)), "allow")
  expect_identical(r("write.table(mtcars, 'sub/x.csv')"), "allow")
  expect_identical(r(sprintf("x = read.csv('%s')", out)), "allow")
  # a change of working folder is allowed only to the run's folder, written out
  expect_identical(r(sprintf("setwd('%s')", run)), "allow")
  for (to in c(dirname(out), path_norm(tempdir()), file.path(run, "sub"), "..", ".")) {
    expect_identical(r(sprintf("setwd('%s')", to)), "deny", label = to)
  }
  expect_identical(r("setwd(d)"), "deny")
  expect_identical(r("setwd('..'); setwd('..'); writeLines('escaped', 'pwn-setwd.txt')"), "deny")
  expect_identical(r("do.call('setwd', list('..'))"), "deny")
  expect_identical(r("f = function() setwd('..'); f()"), "deny")
  expect_identical(r("withr::with_dir('/tmp', writeLines('x', 'pwn.txt'))"), "deny")
  expect_identical(r(sprintf("withr::with_dir(code = '%s', new = '/tmp')", run)), "deny")
  expect_identical(r("withr::local_dir('/tmp'); writeLines('x', 'pwn.txt')"), "deny")
  expect_identical(r("system('cd .. && cd .. && echo x > pwn')"), "deny")
  expect_identical(r("peter$sh('cd /tmp && echo x > pwn')"), "deny")
  expect_identical(r("system2('sh', c('-c', 'pushd /tmp; echo x > pwn'))"), "deny")
  expect_identical(r("system(\"sh -c 'cd /tmp && echo x > pwn'\")"), "deny")
  expect_identical(r("go = 'cd ..'; system(paste(go, '&& echo x > pwn'))"), "deny")
  expect_identical(r("peter$sh('echo x > pwn', wd = '/tmp')"), "deny")
  expect_identical(r(sprintf("peter$sh('cd %s && echo x > pwn')", run)), "allow")
  # a value that merely spells a shell word is no command where shells tell case apart
  expect_identical(r("n = sum(dx == 'CD')"), if (is_windows()) "deny" else "allow")
  expect_identical(r("install.packages('x')"), "deny")
  expect_identical(r("system('R CMD INSTALL pkg')"), "deny")
  expect_identical(r("peter$sh('R CMD INSTALL .')"), "deny")
  expect_identical(r("system('Rscript -e 1')"), "deny")
  expect_identical(r("callr::r(function() 1)"), "deny")
  # neither R code nor a script call shows which interpreter peter$script() starts
  expect_identical(r("peter$script('x.R')"), "deny")
  expect_identical(r("peter[['script']]('x.py')"), "deny")
  expect_identical(fence("script", list(path = "x.sh")), "deny")
  expect_identical(r("system('python x.py')"), "allow")
  expect_identical(r("m = mean(1:3)"), "allow")
})

test_that("the fence reads a folder changer's name as a move only where R calls it", {
  run = path_norm(withr::local_tempdir())
  withr::local_options(gptr.project_root = run)
  withr::local_dir(run)
  r = function(code) {
    call = list(name = "r", input = list(code = code), risk = gptr_risk(code))
    child_fence(call, NULL)$decision %||% "allow"
  }
  for (code in c("in_dir = 'data'; d = read.csv(file.path(in_dir, 'x.csv'))", "x = 'setwd'",
                 "with_dir = 1", "local_dir = c(a = 1); local_dir[['a']]")) {
    expect_identical(r(code), "allow", label = code)
  }
  far = path_norm(tempdir())
  for (code in c("setwd('/x')", "do.call('setwd', list('/x'))", "f = match.fun('setwd')",
                 sprintf("do.call(setwd, list('%s'))", far), "lapply(dirs, setwd)",
                 "Map('setwd', dirs)", "f = withr::with_dir",
                 "system(\"pwsh -c 'Set-Location /tmp; echo x > pwn'\")",
                 # a text whose first word is cd reads as a shell command (D-284)
                 "labs = c('cd', 'ab')")) {
    expect_identical(r(code), "deny", label = code)
  }
})

test_that("the fence refuses R code that writes to a path or calls a function it computes", {
  run = path_norm(withr::local_tempdir())
  withr::local_options(gptr.project_root = run)
  withr::local_dir(run)
  fence = function(code) {
    child_fence(list(name = "r", input = list(code = code), risk = gptr_risk(code)), NULL)
  }
  # `d` was set by an earlier call, so this call cannot show where the file goes
  expect_match(fence("writeLines('x', file.path(d, 'w.txt'))")$reason,
               "it writes only to paths gptr can read", fixed = TRUE)
  expect_identical(fence("unlink(file.path(d, 'old'))")$decision, "deny")
  for (code in c("do.call(paste0('write', 'Lines'), list('x', '/tmp/w.txt'))",
                 "do.call(paste0('set', 'wd'), list('/tmp'))", "eval(parse(text = code))")) {
    expect_match(fence(code)$reason, "it runs only code gptr can read", fixed = TRUE,
                 label = code)
  }
  for (code in c("write.table(mtcars, 'out.csv')", "writeLines('x', file.path('sub', 'a.txt'))",
                 "d = 'res'; saveRDS(mtcars, file.path(d, 'm.rds'))",
                 "m = lapply(1:3, function(i) i + 1)", "fit = lm(mpg ~ wt, data = mtcars)")) {
    expect_null(fence(code), label = code)
  }
})

test_that("a coaching run cannot write through a path or a function it computes", {
  skip_on_cran()
  local_project()
  far = withr::local_tempdir(tmpdir = dirname(tempdir()))
  fake = gptr_fake_provider(list(
    fake_tool("r", code = sprintf("d = '%s'", far)),
    fake_tool("r", code = "writeLines('x', file.path(d, 'w.txt'))"),
    fake_tool("r", code = "do.call(paste0('write', 'Lines'), list('x', file.path(d, 'dyn.txt')))"),
    fake_tool("r", code = "do.call(paste0('set', 'wd'), list(d))"),
    fake_tool("r", code = "wd = getwd(); write.table(mtcars, 'out.csv')"),
    "done"), name = "dynfake")
  res = child_local(list(id = "w", role = "run", prompt = "Save it.", args = list(mode = "auto"),
                         model = fake))$res
  expect_identical(res$status, "idle")
  expect_identical(list.files(far), character())
  expect_identical(nrow(res$refusals), 3L)
  expect_true(all(grepl("fence", res$refusals$reason, fixed = TRUE)))
  expect_true(path_inside(res$objects$wd, tempdir()))
  expect_identical(res$files$path, "out.csv")
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

test_that("a run's child runs no R script and keeps its shell commands in its folder", {
  skip_on_cran()
  local_project()
  out = path_norm(file.path(dirname(tempdir()), "gptr-child-script.txt"))
  withr::defer(unlink(out))
  far = path_norm(dirname(tempdir()))
  fake = gptr_fake_provider(list(
    fake_tool("r", code = sprintf("writeLines(%s, 'x.R')",
                                  deparse1(sprintf("writeLines('x', '%s')", out)))),
    fake_tool("r", code = "peter$script('x.R')"),
    # a computed call is refused, even when a literal call lists the member
    fake_tool("r", code = "f = peter$script; f('x.R')"),
    fake_tool("r", code = sprintf(paste0("peter$sh('true'); a = list('echo x > %s', '%s'); ",
                                         "names(a) = c('', paste0('w', 'd')); ",
                                         "do.call(peter$sh, a)"), basename(out), far)),
    "done"), name = "scriptfake")
  res = child_local(list(id = "s", role = "run", prompt = "Run it.", args = list(mode = "auto"),
                         model = fake))$res
  expect_identical(res$status, "idle")
  expect_false(file.exists(out))
  expect_identical(nrow(res$refusals), 3L)
  expect_true(all(grepl("fence", res$refusals$reason, fixed = TRUE)))
})

test_that("a value without a label R can use is bound under a name of its own", {
  skip_on_cran()
  local_project()
  expect_identical(child_bind(c("..2", "x", "X..2", "...")), c("X..2.1", "x", "X..2", "X..."))
  # do.call(gptr_coach, list("Average it.", c(1, NA, 3))) labels the vector `..2`
  fake = gptr_fake_provider(list(fake_tool("r", code = "m = mean(X..2, na.rm = TRUE)"),
                                 "done"), name = "dotfake")
  res = child_local(list(id = "d", role = "run", prompt = "Average it.",
                         objects = list("..2" = c(1, NA, 3)), args = list(mode = "auto"),
                         model = fake))$res
  expect_identical(res$status, "idle")
  expect_identical(res$objects, list(m = 2))
  expect_match(res$first_user, "<attached name=\"..2\">", fixed = TRUE)
})

test_that("two objects under one label are bound under two names", {
  skip_on_cran()
  local_project()
  expect_identical(child_bind(c("a", "a", "Xa")), c("a", "Xa.1", "Xa"))
  # gptr_coach("Add them.", x, x = y) labels both objects `x`
  fake = gptr_fake_provider(list(fake_tool("r", code = "s = c(x, Xx)"), "done"), name = "twofake")
  res = child_local(list(id = "d", role = "run", prompt = "Add them.",
                         objects = list(x = 1, x = 2), args = list(mode = "auto"),
                         model = fake))$res
  expect_identical(res$status, "idle")
  expect_identical(res$objects, list(s = c(1, 2)))
})

test_that("a run's result holds its first user message on its own", {
  skip_on_cran()
  local_project()
  prompt = "Clean the survey.\n\n## Rules\n- keep the column names"
  fake = gptr_fake_provider(list("## assistant\ndone"), name = "taskfake")
  res = child_local(list(id = "t", role = "run", prompt = prompt, model = fake))$res
  expect_match(res$first_user, prompt, fixed = TRUE)
  expect_false(grepl("done", res$first_user, fixed = TRUE))
  expect_false(startsWith(res$first_user, "## user"))
})

test_that("a run's result too large for the parent keeps all but its value and objects", {
  skip_on_cran()
  local_project()
  testthat::local_mocked_bindings(plain_max = utils::modifyList(plain_max, list(bytes = 60000)))
  fake = gptr_fake_provider(list(fake_tool("r", code = "big = strrep('x', 1e5); gptr_return(big)"),
                                 "kept text"), name = "bigfake")
  res = child_local(list(id = "b", role = "run", prompt = "Make it big.",
                         args = list(mode = "auto"), model = fake))$res
  expect_identical(res$status, "idle")
  expect_identical(res$text, "kept text")
  expect_s3_class(res$usage, "data.frame")
  expect_match(res$transcript, "## assistant", fixed = TRUE)
  expect_match(res$value, "^<character>")
  expect_lt(nchar(res$value), 3000L)
  expect_match(res$objects$big, "^<character>")
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
  local_gptr_options(subagents.max_workers = 2L)
  res = coach_run_jobs(jobs)
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

test_that("at most max_workers children run; a forged stream line is read in the safe direction", {
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
  local_gptr_options(subagents.max_workers = 2L)
  res = coach_run_jobs(list(job("s", "start"), job("f", "final"), job("x", "final")))
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
  local_gptr_options(subagents.max_workers = 2L)
  utils::capture.output({
    got = tryCatch(coach_run_jobs(jobs), interrupt = function(e) "interrupted")
  })
  expect_identical(got, "interrupted")
  expect_length(box$handles, 2L)
  for (h in box$handles) expect_false(ps::ps_is_running(h))
  expect_length(worker_rows(), 0L)
})

test_that("the fence denies reading the CLI login files and the keychain (08 3.7)", {
  cfg = path_norm(withr::local_tempdir())
  withr::local_envvar(CLAUDE_CONFIG_DIR = cfg, CODEX_HOME = "")
  claude = file.path(cfg, ".credentials.json")
  writeLines("{}", claude)
  fence = function(name, input) {
    risk = if (identical(name, "r")) gptr_risk(input$code)
    child_fence(list(name = name, input = input, risk = risk), NULL)$decision %||% "allow"
  }
  r = function(code) fence("r", list(code = code))
  expect_identical(fence("read", list(path = claude)), "deny")
  expect_identical(fence("grep", list(pattern = "token", path = cfg)), "deny")
  expect_identical(fence("read", list(path = file.path(cfg, "settings.json"))), "allow")
  expect_identical(r(sprintf("x = readLines('%s')", claude)), "deny")
  # CODEX_HOME unset: its default under the home folder
  expect_identical(r("x = jsonlite::read_json('~/.codex/auth.json')"), "deny")
  expect_identical(r("system('cat ~/.codex/auth.json')"), "deny")
  expect_identical(r("x = system('security find-generic-password -s x -w', intern = TRUE)"),
                   "deny")
  expect_identical(r("peter$sh('security find-generic-password -s x -w')"), "deny")
  expect_identical(r("x = readLines('notes.txt')"), "allow")
})

test_that("a call that met a require rule does not raise the run's reported risk", {
  skip_on_cran()
  local_project()
  rules = list(require = list(list(id = "saved", any = "r(fn:saveRDS)", text = "Save it.")))
  spec = harness_spec(gptr_tailor(peter, coaching = list(rules = rules)))
  script = function(name) {
    gptr_fake_provider(list(fake_tool("r", code = "x = 1"),
                            fake_tool("r", code = "saveRDS(x, 'x.rds')"), "Done."), name = name)
  }
  job = list(id = "q", role = "run", prompt = "Save x.", args = list(mode = "auto"))
  met = child_local(c(job, list(spec = spec, model = script("tallyfake"))))
  expect_identical(met$res$status, "idle")
  expect_identical(met$res$risk, 1L)
  expect_identical(met$res$unmet, character())
  levels = vapply(met$lines[child_events(met$lines) == "risk"], function(l) json_decode(l)$level,
                  1L, USE.NAMES = FALSE)
  expect_identical(levels, 1L)
  plain = child_local(c(job, list(spec = harness_spec(gptr_tailor(peter)),
                                  model = script("tallyfake2"))))
  expect_identical(plain$res$risk, 2L)
})
