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
