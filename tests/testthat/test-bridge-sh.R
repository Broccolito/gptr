# Tests for R/bridge-sh.R (P22): command resolution and views, gptr_cmd results, scripts and the
# interpreter kind, background jobs, builtin:bridges.

test_that("simple command lines split into words and shell syntax does not", {
  expect_identical(bridge_split("git status --porcelain"), c("git", "status", "--porcelain"))
  expect_identical(bridge_split("echo 'quoted words' plain"), c("echo", "quoted words", "plain"))
  expect_identical(bridge_split("printf \"a b\""), c("printf", "a b"))
  expect_identical(bridge_split("Rscript -e 'cat(1)' \"a|b\""), c("Rscript", "-e", "cat(1)", "a|b"))
  expect_identical(bridge_split("rm\v-rf\f/"), "rm\v-rf\f/")
  expect_null(bridge_split("ls | head"))
  expect_null(bridge_split("echo $HOME"))
  expect_null(bridge_split("FOO=1 make"))
  expect_null(bridge_split("cat ~/x"))
  expect_null(bridge_split("echo \"$USER\""))
  expect_null(bridge_split("echo 'open"))
  expect_null(bridge_split("make > log.txt"))
  expect_null(bridge_split("   "))
})

test_that("argv vectors, simple lines and shell lines resolve differently", {
  r = bridge_resolve(c("git", "status"))
  expect_identical(r[c("command", "args", "via")], list(command = "git", args = "status",
                                                        via = "argv"))
  expect_identical(bridge_resolve(c("Rscript", "-e", "1"))$command, rscript_path())
  skip_on_os("windows")
  d = bridge_resolve(paste(shQuote(rscript_path()), "--version"))
  expect_identical(d$via, "direct")
  expect_identical(d$command, rscript_path())
  expect_identical(d$args, "--version")
  s = bridge_resolve("echo a | sort")
  sh = shell_resolve("echo a | sort")
  expect_identical(s$via, "shell")
  expect_identical(s$command, sh$command)
  expect_identical(s$args, sh$args)
  expect_identical(bridge_resolve("gptr-no-such-program-p22 --flag")$via, "shell")
})

test_that("validated JSON arrays flatten back to character vectors", {
  expect_identical(bridge_chr(list("git", "status")), c("git", "status"))
  expect_identical(bridge_chr("ls"), "ls")
  expect_null(bridge_chr(NULL))
  expect_identical(bridge_chr(list()), character())
  expect_identical(bridge_chr(list(1, 2)), list(1, 2))
  expect_identical(bridge_chr(list(GIT_DIR = ".git")), c(GIT_DIR = ".git"))
})

test_that("views keep head and tail within the budget and name the out id", {
  lines = sprintf("line %05d of the output with some words", 1:20000)
  v = bridge_view_lines(lines, 300L, id = "o1a2b3c")
  expect_lte(est_tokens(v, "r_output"), 300)
  expect_identical(v[[1L]], lines[[1L]])
  expect_identical(v[[length(v)]], lines[[20000L]])
  notice = grep("lines omitted", v, value = TRUE, fixed = TRUE)
  expect_length(notice, 1L)
  expect_match(notice, "all: peter$out(\"o1a2b3c\")]", fixed = TRUE)
  omitted = as.integer(sub("^\\[\\.\\.\\. ([0-9]+) lines.*$", "\\1", notice))
  expect_identical(omitted + length(v) - 1L, 20000L)
  share = (match(notice, v) - 1) / (length(v) - 1)
  expect_gt(share, 0.3)
  expect_lt(share, 0.5)
  expect_identical(bridge_view_lines(c("a", "b"), 300L), c("a", "b"))
  expect_identical(bridge_view_lines(character(), 300L), character())
  e = bridge_view_lines(lines, 250L, head = 0.2, id = "o9", stream = "stderr")
  expect_match(grep("omitted", e, value = TRUE), "peter$out(\"o9\", \"stderr\")", fixed = TRUE)
  expect_identical(bridge_notice(3L), "[... 3 lines omitted]")
})

test_that("the print budget is the option, capped at 0.6 x the r budget inside a run", {
  expect_identical(bridge_budget(NULL), 1500L)
  expect_identical(bridge_budget(120), 120L)
  local_gptr_options(helper_output_tokens = 900L)
  expect_identical(bridge_budget(NULL), 900L)
  testthat::local_mocked_bindings(run_current = function() list(session = "s0000000001"))
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 1000L)
  expect_identical(bridge_budget(NULL), 600L)
  expect_identical(bridge_budget(2000), 2000L)
})

test_that("labels are one line of at most 50 characters", {
  expect_identical(bridge_label(c("git", "status", "--porcelain")), "git status --porcelain")
  long = bridge_label(paste(rep("word", 30), collapse = "  "))
  expect_identical(nchar(long), 50L)
  expect_true(endsWith(long, "..."))
})

r_cmd = function(code) c(rscript_path(), "--vanilla", "-e", code)

test_that("the argv form passes arguments without a shell and decodes UTF-8", {
  skip_on_cran()
  x = bridge_sh(r_cmd(paste0("cat('a b', rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))), ",
                             "sep = '\\n')")))
  expect_s3_class(x, "gptr_cmd")
  expect_identical(names(unclass(x)),
                   c("cmd", "status", "ok", "stdout", "stderr", "elapsed", "timed_out", "id"))
  expect_identical(attr(x, "via"), "argv")
  expect_true(x$ok)
  expect_identical(x$status, 0L)
  expect_false(x$timed_out)
  lines = strsplit(x$stdout, "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[[1L]], "a b")
  expect_identical(charToRaw(lines[[2L]]), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  expect_identical(Encoding(lines[[2L]]), "UTF-8")
  expect_identical(format(x), x$stdout)
  expect_identical(as.character(x), x$stdout)
  expect_match(x$id, "^o[0-9a-f]{6}$")
})

test_that("output and arguments stay correct UTF-8 in a C locale", {
  skip_on_cran()
  skip_on_os("windows")
  withr::local_locale(c(LC_CTYPE = "C"))
  x = bridge_sh(r_cmd("cat(rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))))"))
  expect_identical(Encoding(x$stdout), "UTF-8")
  expect_identical(charToRaw(x$stdout), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  arg = bridge_sh(c(rscript_path(), "--vanilla", "-e",
                    "cat(as.character(charToRaw(commandArgs(TRUE)[1])))", "caf\u00e9"))
  expect_identical(arg$stdout, "63 61 66 c3 a9")
})

test_that("a simple command line runs directly and a pipeline through the shell", {
  skip_on_cran()
  skip_on_os("windows")
  d = bridge_sh("echo 'quoted words' plain")
  expect_identical(attr(d, "via"), "direct")
  expect_identical(d$stdout, "quoted words plain\n")
  p = bridge_sh("printf 'x\\ny\\nx\\n' | sort | uniq -c | sort -rn")
  expect_identical(attr(p, "via"), "shell")
  expect_match(strsplit(p$stdout, "\n", fixed = TRUE)[[1L]][[1L]], "2 x", fixed = TRUE)
})

test_that("stderr stays separate, exits are reported and check = TRUE raises", {
  skip_on_cran()
  x = bridge_sh(r_cmd("cat('out\\n'); message('oops'); quit(status = 3)"))
  expect_identical(x$status, 3L)
  expect_false(x$ok)
  expect_identical(x$stdout, "out\n")
  expect_identical(x$stderr, "oops\n")
  expect_identical(bridge_cmd_view(x), c("out", "[stderr]", "oops", "[exit 3]"))
  expect_identical(out_get(x$id, "stderr"), "oops")
  err = expect_error(bridge_sh(r_cmd("quit(status = 4)"), check = TRUE),
                     class = "gptr_error_process")
  expect_identical(err$status, 4L)
  m = bridge_sh(r_cmd("cat('a\\n'); message('b')"), merge = TRUE)
  expect_identical(m$stderr, "")
  expect_identical(m$stdout, "a\nb\n")
  expect_error(bridge_sh(character()), class = "gptr_error_invalid_argument")
  expect_error(bridge_sh("ls", wd = file.path(tempdir(), "no-such-dir-p22")),
               class = "gptr_error_invalid_argument")
})

test_that("input reaches stdin as lines, as CSV or as bytes; env sets variables", {
  skip_on_cran()
  x = bridge_sh(r_cmd("cat(rev(readLines(file('stdin'))), sep = '\\n')"), input = c("a", "b", "c"))
  expect_identical(strsplit(x$stdout, "\n", fixed = TRUE)[[1L]], c("c", "b", "a"))
  y = bridge_sh(r_cmd("d = read.csv(file('stdin')); cat(nrow(d), names(d))"),
                input = head(mtcars[, 1:3], 5))
  expect_identical(y$stdout, "5 mpg cyl disp")
  z = bridge_sh(r_cmd("cat(length(readBin(file('stdin', 'rb'), 'raw', 100)))"),
                input = as.raw(1:7))
  expect_identical(z$stdout, "7")
  expect_error(bridge_sh("ls", input = 1:3), class = "gptr_error_invalid_argument")
  expect_error(bridge_sh("ls", input = c("a", NA)), class = "gptr_error_invalid_argument")
  e = bridge_sh(r_cmd("cat(Sys.getenv('GPTR_P22_SET'))"), env = c(GPTR_P22_SET = "set-value"))
  expect_identical(e$stdout, "set-value")
})

test_that("a timeout kills the process tree and suggests peter$bg()", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("pgrep")))
  t0 = proc.time()[["elapsed"]]
  x = bridge_sh("sleep 57 & sleep 58; wait", timeout = 1)
  expect_lt(proc.time()[["elapsed"]] - t0, 10)
  expect_true(x$timed_out)
  expect_true(is.na(x$status))
  expect_false(x$ok)
  v = bridge_cmd_view(x)
  expect_match(v[[length(v)]], "timed out after", fixed = TRUE)
  expect_match(v[[length(v)]], "peter$bg()", fixed = TRUE)
  Sys.sleep(0.5)
  left = processx::run("pgrep", c("-f", "sleep 5[78]"), error_on_status = FALSE)$stdout
  expect_identical(left, "")
  expect_error(bridge_sh("sleep 5", timeout = 0.5, check = TRUE), class = "gptr_error_timeout")
})

test_that("long output is cut in the view and peter$out() returns all of it", {
  skip_on_cran()
  x = bridge_sh(r_cmd("cat(seq_len(20000), sep = '\\n')"), max_tokens = 120L)
  expect_identical(attr(x, "max_tokens"), 120L)
  v = bridge_cmd_view(x)
  expect_lte(est_tokens(v, "r_output"), 120)
  notice = grep("lines omitted", v, value = TRUE, fixed = TRUE)
  expect_match(notice, paste0("peter$out(\"", x$id, "\")"), fixed = TRUE)
  full = out_get(x$id)
  expect_length(full, 20000L)
  expect_identical(full[[20000L]], "20000")
  expect_output(print(x), "lines omitted", fixed = TRUE)
  log = local_bridge_events()
  mid = bridge_sh(r_cmd("cat(sprintf('line %d', 1:200), sep = '\\n')"), max_tokens = 120L)
  expect_true(any(grepl("lines omitted", bridge_cmd_view(mid), fixed = TRUE)))
  expect_true(file.exists(log$events[[length(log$events)]]$spill))
})

test_that("the default print budget of 1,500 tokens holds with the stderr floors", {
  skip_on_cran()
  x = bridge_sh(r_cmd(paste0("cat(sprintf('stdout line %d', 1:20000), sep = '\\n'); ",
                             "message(paste(sprintf('stderr line %d', 1:5000), ",
                             "collapse = '\\n')); quit(status = 2)")))
  v = bridge_cmd_view(x)
  expect_lte(est_tokens(v, "r_output"), 1500)
  expect_identical(v[[length(v)]], "[exit 2]")
  err_part = v[seq.int(match("[stderr]", v), length(v) - 1L)]
  err_tokens = est_tokens(err_part, "r_output")
  expect_gte(err_tokens, 300)
  expect_lte(err_tokens, 380)
  expect_match(grep("lines omitted", err_part, value = TRUE),
               paste0("peter$out(\"", x$id, "\", \"stderr\")"), fixed = TRUE)
  expect_length(out_get(x$id, "stderr"), 5000L)
  expect_lte(est_tokens(bridge_cmd_view(x, max_tokens = 400L), "r_output"), 400)
})

test_that("each call emits bridge_call with a #> digest", {
  skip_on_cran()
  log = local_bridge_events()
  x = bridge_sh(r_cmd("cat('a\\nb\\n')"))
  ev = log$events[[length(log$events)]]
  expect_identical(ev$type, "bridge_call")
  expect_identical(ev$bridge, "sh")
  expect_identical(ev$id, x$id)
  expect_identical(ev$status, "ok")
  expect_identical(ev$bytes_out, 4L)
  expect_null(ev$spill)
  expect_match(ev$digest, "^#> sh .*: exit 0, 2 lines$")
  big = bridge_sh(r_cmd("cat(sprintf('row %d of a long listing', 1:3000), sep = '\\n')"))
  ev = log$events[[length(log$events)]]
  expect_true(file.exists(ev$spill))
  expect_identical(basename(ev$spill), paste0("gptr-output-", big$id, ".txt"))
})

test_that("a registered value is redacted before the digest label or cmd is cut", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("zqFAKE", strrep("bridge", 4L), "0042")
  secret_register(fake, "GPTR_P22_TEST_TOKEN", source = "test")
  log = local_bridge_events()
  bridge_sh(c("Rscript", "--vanilla", "-e", "invisible(0)", paste0("--key=", fake)))
  expect_false(grepl("zqFAKE", log$events[[length(log$events)]]$digest, fixed = TRUE))
  bridge_sh(c("Rscript", "--vanilla", "-e", "invisible(0)", strrep("p", 450L),
              paste0("--key=", fake)))
  expect_false(grepl("zqFAKE", log$events[[length(log$events)]]$cmd, fixed = TRUE))
})

test_that("the interpreter validator normalises extensions and rejects bad fields", {
  sp = interpreter_validate(list(kind = "interpreter", name = "tcl", ext = ".TCL",
                                 programs = "tclsh"))
  expect_identical(sp$ext, "tcl")
  expect_false(sp$windows_only)
  expect_identical(sp$args("a.tcl", "x"), c("a.tcl", "x"))
  bad = function(...) interpreter_validate(list(kind = "interpreter", name = "bad", ...))
  expect_error(bad(ext = 1, programs = "x"), class = "gptr_error_invalid_spec")
  expect_error(bad(ext = "x", programs = character()), class = "gptr_error_invalid_spec")
  expect_error(bad(ext = "x", programs = "x", args = function(p) p),
               class = "gptr_error_invalid_spec")
  err = expect_error(bad(ext = "x", programs = "x", windows_only = NA),
                     class = "gptr_error_invalid_spec")
  expect_identical(err$field, "windows_only")
})

test_that("builtin:bridges defines the interpreter kind and the seven built-in interpreters", {
  expect_true("kind.interpreter" %in% gptr_api()$features)
  expect_true(all(c("sh", "py", "r", "js", "pl", "rb", "jl") %in% registry_names("interpreter")))
  expect_identical(registry_get("interpreter", "r")$programs, rscript_path())
  expect_identical(registry_get("interpreter", "js")$ext, c("js", "mjs", "cjs"))
  sp = gptr_spec("interpreter", "tcl", ext = "tcl", programs = "tclsh",
                 args = function(path, args) c(path, args), windows_only = FALSE)
  off = gptr_register(sp)
  withr::defer(off())
  expect_identical(registry_get("interpreter", "tcl")$ext, "tcl")
  expect_identical(tryCatch(gptr_spec("interpreter", "bad", ext = 1, programs = "x",
                                      args = function(path, args) path, windows_only = FALSE),
                            gptr_error_invalid_spec = function(e) e$field), "ext")
})

test_that("scripts run with the interpreter of their extension, a name or a program", {
  skip_on_cran()
  d = withr::local_tempdir()
  f = file.path(d, "c.R")
  writeLines("cat('R script', commandArgs(TRUE))", f)
  x = bridge_script(f, c("x", "y z"))
  expect_identical(x$stdout, "R script x y z")
  expect_identical(attr(x, "via"), "argv")
  expect_identical(bridge_script(f, "a", interpreter = "r")$stdout, "R script a")
  expect_identical(bridge_script(f, "b", interpreter = c(rscript_path(), "--vanilla"))$stdout,
                   "R script b")
  expect_identical(bridge_script(f, list("c"), wd = d, timeout = 30)$stdout, "R script c")
  g = file.path(d, "rev.R")
  writeLines("cat(rev(readLines(file('stdin'))))", g)
  expect_identical(bridge_script(g, input = c("1", "2"))$stdout, "2 1")
  log = local_bridge_events()
  bridge_script(f, "q")
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "script")
  expect_identical(ev$digest, "#> script c.R q: exit 0, 1 line")
  expect_identical(ev$level, 3L)
})

test_that("a user interpreter named like the extension overrides the built-in one", {
  skip_on_cran()
  d = withr::local_tempdir()
  f = file.path(d, "u.R")
  writeLines("cat('ran', commandArgs(TRUE))", f)
  off = gptr_register(gptr_spec("interpreter", "r", ext = "r", programs = rscript_path(),
                                args = function(path, args) c("--vanilla", path, "via-user"),
                                windows_only = FALSE))
  withr::defer(off())
  expect_identical(bridge_script(f)$stdout, "ran via-user")
})

test_that("shell scripts and #! lines run on Unix", {
  skip_on_cran()
  skip_on_os("windows")
  d = withr::local_tempdir()
  writeLines("echo \"sh script args: $@\"", file.path(d, "a.sh"))
  expect_identical(bridge_script(file.path(d, "a.sh"), c("x", "y z"))$stdout,
                   "sh script args: x y z\n")
  writeLines(c("#!/bin/sh", "echo shebang ok"), file.path(d, "tool"))
  expect_identical(bridge_script(file.path(d, "tool"))$stdout, "shebang ok\n")
})

test_that("unknown extensions, missing scripts and unknown options are argument errors", {
  d = withr::local_tempdir()
  writeLines("x", file.path(d, "a.unknownext"))
  expect_error(bridge_script(file.path(d, "a.unknownext")), class = "gptr_error_invalid_argument")
  expect_error(bridge_script(file.path(d, "missing.R")), class = "gptr_error_invalid_argument")
  writeLines("1", file.path(d, "b.R"))
  expect_error(bridge_script(file.path(d, "b.R"), shell = "zsh"),
               class = "gptr_error_invalid_argument")
})

test_that("a background job is read incrementally and waited for until a pattern", {
  skip_on_cran()
  j = bridge_bg(r_cmd("cat('ready\\n'); flush(stdout()); Sys.sleep(1); cat('DONE acc=0.93\\n')"),
                name = "trainer")
  withr::defer(j$kill())
  expect_s3_class(j, "gptr_job")
  expect_identical(j$name, "trainer")
  expect_true(all(c("id", "cmd", "name", "pid", "read", "wait", "write", "kill", "status") %in%
                    ls(j)))
  first = j$wait(timeout = 20, until = "ready")
  expect_s3_class(first, "gptr_bridge_text")
  expect_true("ready" %in% first)
  rest = j$wait(timeout = 20)
  expect_true("DONE acc=0.93" %in% rest)
  expect_false("ready" %in% rest)
  expect_identical(j$status(), "done")
  expect_output(print(j), "^<job j[0-9a-f]{6} trainer [0-9]+ done>$")
  expect_output(print(rest), "DONE acc=0.93", fixed = TRUE)
  expect_output(print(rest), paste0("[", j$id, " done, "), fixed = TRUE)
  expect_length(j$read(), 0L)
})

test_that("wait(until =) returns once the matching line is complete", {
  skip_on_cran()
  j = bridge_bg(r_cmd(paste0("cat('rea'); flush(stdout()); Sys.sleep(1); cat('dy\\n'); ",
                             "flush(stdout()); Sys.sleep(30)")))
  withr::defer(j$kill())
  first = j$wait(timeout = 20, until = "rea")
  expect_true("ready" %in% first)
})

test_that("a job with stdin = TRUE talks over stdin and kill() stops it", {
  skip_on_cran()
  code = paste("con = file('stdin'); open(con); cat('ready\\n'); flush(stdout());",
               "repeat { l = readLines(con, n = 1L); if (!length(l)) break;",
               "cat('echo:', toupper(l), '\\n'); flush(stdout()) }")
  j = bridge_bg(r_cmd(code), stdin = TRUE)
  withr::defer(j$kill())
  j$wait(timeout = 20, until = "ready")
  j$write(c("hello", "gptr"))
  out = j$wait(timeout = 20, until = "echo: GPTR")
  expect_true(any(grepl("echo: HELLO", out, fixed = TRUE)))
  expect_true(any(grepl("echo: GPTR", out, fixed = TRUE)))
  j$kill()
  expect_identical(j$status(), "stopped")
  tab = bridge_jobs()
  expect_identical(tab$status[match(j$id, tab$id)], "stopped")
  expect_error(j$write("again"), class = "gptr_error_process")
})

test_that("separate stderr is read on request and a failing job reads error", {
  skip_on_cran()
  j = bridge_bg(r_cmd("cat('o\\n'); message('e'); quit(status = 1)"), merge = FALSE)
  withr::defer(j$kill())
  j$wait(timeout = 20)
  expect_true("e" %in% j$read("stderr"))
  expect_identical(j$status(), "error")
})

test_that("bg jobs are in gptr_jobs(), write() needs stdin and kill = TRUE stops them", {
  skip_on_cran()
  j = bridge_bg(r_cmd("Sys.sleep(30)"))
  withr::defer(j$kill())
  tab = gptr_jobs()
  expect_true(j$id %in% tab$id)
  expect_identical(tab$kind[match(j$id, tab$id)], "bg")
  expect_error(j$write("x"), class = "gptr_error_invalid_argument")
  expect_error(j$read("stderr"), class = "gptr_error_invalid_argument")
  invisible(bridge_jobs(kill = TRUE))
  expect_identical(j$status(), "stopped")
  expect_identical(gptr_jobs()$status[match(j$id, gptr_jobs()$id)], "stopped")
})

test_that("at most two jobs run at once under R CMD check (IC-60)", {
  skip_on_cran()
  invisible(bridge_jobs(kill = TRUE))
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  a = bridge_bg(r_cmd("Sys.sleep(30)"))
  withr::defer(a$kill())
  b = bridge_bg(r_cmd("Sys.sleep(30)"))
  withr::defer(b$kill())
  expect_error(bridge_bg(r_cmd("Sys.sleep(30)")), class = "gptr_error_spawn")
})

shell_line = paste0(
  "- There is no shell tool. Run programs from R: peter$sh(c(\"git\", \"status\")) (argv, no ",
  "shell) or peter$sh(\"cmd | filter\"); peter$script(path); peter$bg(cmd) for long jobs. Assign ",
  "results and print only what you need."
)

# The tool results of one tool in a session, in order
tool_results = function(s, name) {
  Filter(function(m) identical(m$role, "tool_result") && identical(m$tool_name, name), s$messages)
}

test_that("builtin:bridges registers sh, script, bg and jobs as peter$ members only", {
  for (nm in c("sh", "script", "bg", "jobs")) {
    spec = registry_get("tool", nm)
    expect_s3_class(spec, "gptr_tool")
    expect_identical(spec$exposure, "r")
    expect_null(spec$namespace)
    expect_true(is.function(spec$fun))
    expect_true(is.function(spec$execute))
    expect_true(spec$record)
    expect_false(spec$available(NULL))
    expect_true(all(gptr_check(spec)$ok))
    expect_true(inherits(peter[[nm]], "gptr_member"))
  }
  expect_identical(names(formals(registry_get("tool", "sh")$fun)),
                   c("cmd", "input", "wd", "timeout", "env", "merge", "check", "max_tokens"))
  expect_identical(formals(registry_get("tool", "sh")$fun)$timeout, 120)
  expect_identical(names(formals(registry_get("tool", "script")$fun)),
                   c("path", "args", "interpreter", "..."))
  expect_identical(names(formals(registry_get("tool", "bg")$fun)),
                   c("cmd", "name", "stdin", "merge"))
  expect_identical(names(formals(registry_get("tool", "jobs")$fun)), "kill")
  expect_true(all(c("sh", "script", "bg", "jobs") %in% utils::.DollarNames(peter, "")))
  for (preset in c("minimal", "standard", "readonly", "extended")) {
    expect_false(any(c("sh", "script", "bg", "jobs") %in% preset_tools(preset, human = TRUE)))
  }
  expect_false(grepl("\"name\":\"sh\"", gptr_prompt(preset = "extended")$tools_json,
                     fixed = TRUE))
})

test_that("the members run through the gateway with the contract defaults", {
  skip_on_cran()
  x = peter$sh(r_cmd("cat('hi')"))
  expect_s3_class(x, "gptr_cmd")
  expect_identical(x$stdout, "hi")
  expect_output(print(x), "^hi$")
  d = withr::local_tempdir()
  writeLines("cat('via member')", file.path(d, "m.R"))
  expect_identical(peter$script(file.path(d, "m.R"))$stdout, "via member")
  j = peter$bg(r_cmd("Sys.sleep(30)"), name = "sleeper")
  withr::defer(j$kill())
  tab = peter$jobs()
  expect_identical(tab$name[match(j$id, tab$id)], "sleeper")
  invisible(peter$jobs(kill = TRUE))
  expect_identical(j$status(), "stopped")
  long = peter$sh(r_cmd("cat(seq_len(5000), sep = '\\n')"), max_tokens = 100L)
  expect_output(print(long), paste0("peter$out(\"", long$id, "\")"), fixed = TRUE)
  expect_length(peter$out(long$id), 5000L)
})

test_that("member risks follow the command classifier; script and bg are at least 3", {
  sh = registry_get("tool", "sh")
  expect_identical(as.integer(sh$risk(list(cmd = "rm -rf data"), NULL)$level), 3L)
  expect_identical(as.integer(sh$risk(list(cmd = c("git", "status")), NULL)$level), 0L)
  expect_identical(as.integer(sh$risk(list(cmd = list("git", "status")), NULL)$level), 0L)
  expect_identical(registry_get("tool", "script")$risk(list(path = "a.sh"), NULL)$level, 3L)
  expect_identical(registry_get("tool", "bg")$risk(list(cmd = c("git", "status")), NULL)$level,
                   3L)
  expect_identical(registry_get("tool", "jobs")$risk(list(kill = FALSE), NULL)$level, 0L)
  expect_identical(registry_get("tool", "jobs")$risk(list(kill = TRUE), NULL)$level, 3L)
  passed = sh$risk(list(cmd = c("git", "status"), env = "GITHUB_TOKEN"), NULL)
  expect_identical(as.integer(passed$level), 3L)
  expect_true("secret" %in% passed$categories)
  set_only = sh$risk(list(cmd = c("git", "status"), env = c(GIT_DIR = ".git")), NULL)
  expect_identical(as.integer(set_only$level), 0L)
})

test_that("r code calling peter$sh() is classified by the command it runs (acceptance 3)", {
  expect_identical(gptr_risk("peter$sh(\"rm -rf data\")")$level, 3L)
  expect_identical(gptr_risk("peter$sh(c(\"git\", \"status\"))")$level, 0L)
  expect_identical(gptr_risk("x = paste(\"rm\", f); peter$sh(x)")$level, 3L)
})

test_that("the shell line of <r_session> is registered byte for byte", {
  frag = registry_get("prompt_section", "shell")
  expect_identical(frag$text, shell_line)
  expect_identical(frag$parent, "r_session")
  expect_identical(frag$tier, "T0")
  expect_identical(as.integer(frag$order), 30L)
  expect_true(grepl(shell_line, gptr_prompt(preset = "standard")$system$t0, fixed = TRUE))
})

test_that("-builtin:bridges removes the shell line from <r_session> and the members", {
  old = registry_env()$filters[["session"]] %||% character()
  registry_filters_set(c(old, "-builtin:bridges"), "session")
  withr::defer(registry_filters_set(old, "session"))
  t0 = gptr_prompt(preset = "standard")$system$t0
  expect_false(grepl("There is no shell tool", t0, fixed = TRUE))
  expect_true(grepl("<r_session>", t0, fixed = TRUE))
  expect_error(peter$sh("ls"), class = "gptr_error_unknown_member")
})

test_that("model code runs peter$sh() inside r; the event and the nested record belong to it", {
  skip_on_cran()
  local_project()
  log = local_bridge_events()
  code = paste0("res = peter$sh(c(", deparse(rscript_path()),
                ", \"--vanilla\", \"-e\", \"cat('hi')\"))\nres$ok")
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  e = new.env()
  s = peter("run it", model = fake, envir = e, mode = "auto")
  expect_true(e$res$ok)
  expect_identical(e$res$stdout, "hi")
  ev = log$events[[length(log$events)]]
  expect_identical(ev$session, s$id)
  expect_identical(ev$bridge, "sh")
  expect_match(ev$digest, "^#> sh .*: exit 0, 1 line$")
  res = tool_results(s, "r")[[1L]]
  expect_identical(res$details$nested[[1L]]$tool, "sh")
  expect_identical(res$details$bridge, ev$digest)
})

test_that("the tool_call hook blocks top-level bridge calls and lets nested ones pass", {
  h = bridge_block_hook(c("sh", "bg"))
  blocked = h(list(tool_name = "sh", nested = FALSE), NULL)
  expect_identical(blocked$decision, "block")
  expect_match(blocked$reason, "peter$sh() is an R function, not a tool", fixed = TRUE)
  expect_null(h(list(tool_name = "sh", nested = TRUE), NULL))
  expect_null(h(list(tool_name = "r", nested = FALSE), NULL))
})

test_that("a tool call named sh is refused before the permission check: no shell tool (S-4)", {
  skip_on_cran()
  local_project()
  marker = file.path(getwd(), "direct-marker.txt")
  script = list(
    fake_tool("sh", cmd = list(rscript_path(), "-e", "file.create('direct-marker.txt')")),
    fake_text("done")
  )
  fake = local_fake_provider(script)
  # manual mode without a human: a call that reached the permission check would stop the run
  # (gptr.noninteractive_ask = "stop"), so finishing idle shows the hook blocked it first
  s = peter("run it", model = fake, envir = new.env(), mode = "manual")
  res = tool_results(s, "sh")[[1L]]
  expect_true(isTRUE(res$is_error))
  expect_match(msg_text(res), "is an R function, not a tool", fixed = TRUE)
  expect_false(file.exists(marker))
  expect_identical(s$status, "idle")
})

test_that("computed commands are re-checked at run time with the actual command", {
  skip_on_cran()
  local_project()
  local_gptr_options(noninteractive_ask = "deny")
  testthat::local_mocked_bindings(bridge_risk = function(x, kind) {
    level = if (any(grepl("marker", x, fixed = TRUE))) 4L else 0L
    list(level = level, categories = if (level == 4L) "critical" else "read",
         paths = character())
  })
  rs = deparse(rscript_path())
  code = paste0("cmd = c(", rs, ", \"-e\", \"file.create('marker.txt')\")\nres = peter$sh(cmd)")
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  s = peter("make the marker", model = fake, envir = new.env(), mode = "auto")
  expect_false(file.exists("marker.txt"))
  expect_match(msg_text(tool_results(s, "r")[[1L]]), "Permission denied", fixed = TRUE)
  ok_code = paste0("cmd = c(", rs, ", \"-e\", \"file.create('fine.txt')\")\nres = peter$sh(cmd)")
  fake2 = local_fake_provider(list(fake_tool("r", code = ok_code), fake_text("done")),
                              name = "fake2")
  peter("make the file", model = fake2, envir = new.env(), mode = "auto")
  expect_true(file.exists("fine.txt"))
  # the re-check runs the input a policy's modify approved (IC-53 item 7)
  local_gptr_options(critical_guard = FALSE)
  off = gptr_register(gptr_policy("p22_safer", function(call, ctx) {
    if (identical(call$name, "sh") && any(grepl("marker", unlist(call$input$cmd), fixed = TRUE))) {
      list(decision = "modify",
           input = list(cmd = c(rscript_path(), "-e", "file.create('safe.txt')")))
    }
  }))
  withr::defer(off())
  fake3 = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")), name = "fake3")
  peter("make the marker", model = fake3, envir = new.env(), mode = "auto")
  expect_false(file.exists("marker.txt"))
  expect_true(file.exists("safe.txt"))
})
