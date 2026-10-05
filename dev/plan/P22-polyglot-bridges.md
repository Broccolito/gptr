# P22 Polyglot Bridges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make R the token-efficient glue for shell programs, scripts, background jobs, Python, SQL and knitr engines through the `gptr$` members `sh`, `script`, `bg`, `jobs`, `py`, `sql` and `knit`, with no shell tool (S-4, REQ-09, REQ-42).

**Architecture:** Two built-in plugins (layer L4, area `bridge`). `builtin:bridges` (`R/bridge-sh.R`) defines the `interpreter` kind through the `kind` meta-kind, registers seven built-in interpreters, the members `sh`, `script`, `bg`, `jobs` and the `<r_session>` fragment `shell`; `builtin:lang` (`R/bridge-lang.R`) registers `py`, `sql`, `knit` and the fragment `languages`. Every child runs on P04's process engine (`proc_run()`/`proc_spawn()`: redirected files, `encoding = "UTF-8"`, P03's complete `helper` environment, non-blocking stdin), every result prints a budgeted head+tail view whose notice names a `gptr$out()` id, every call emits a `bridge_call` event whose `#> ` digest P10 collects into the `r` result and P15 writes into history documents, and model code reaches the members through P06's `dispatch_nested()` with a run-time re-check of computed arguments.

**Tech Stack:** base R (>= 4.2.0); processx (only through P04), rlang (`env_binding_are_lazy()`/`env_binding_are_active()`), methods, utils, tools (Imports); reticulate, DBI, duckdb, knitr (Suggests, behind `requireNamespace()`); RSQLite, withr, testthat 3e (tests); rtiktoken only through P07's development runner `dev/bench/tokens/run.R`.

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2 `bridge-sh.R`/`bridge-lang.R`, §4.2, §6.4 R1/R3/R9, §6.5 child environments, §6.6, §6.7, §6.8.4, §7.3 `<r_session>`, §11.1 interpreters, §12.7), dev/spec/04-interface-contract.md (§1.1, §1.3, §2.2, §3.1, §4.4 `details$bridge`, §4.5, §5.10, §7.0 `risk.classify`, §7.1-§7.4, §7.6, §7.10, §7.11, §7.22, §8.2 `reactor_pump()`, §9.1, §9.3 `r_session`, §9.4, §10.2 rows 6 and 30, §10.3, §10.4 `bridge_call`, §11.5, §12.2-§12.4, §15 IC-36, IC-37, IC-41, IC-60, IC-62, IC-67, IC-68, IC-70, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P22).

**Depends on:** P10, P11 (and through them P01-P09). **Milestone:** M5.

All commands run from the repository root `/Users/wanjun/Desktop/gptr`.

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment and `|>` for pipes (never `<-` or `%>%`), ASCII-only R sources (non-ASCII as `\u` escapes), `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` conditions, testthat 3e, no network in tests, `Rscript --vanilla` for every command, no new Imports or Suggests, every changed state restored with `on.exit(..., add = TRUE)`, `withr` only in tests, no `:::`, no `.GlobalEnv`, no `processx::run()` in `R/`, every `readLines()` with `encoding = "UTF-8"`, R children only through `rscript_path()`. Plan-specific values, copied from the spec:

- One commit per task, whose message ends with the attribution line the executing harness specifies (conventions §10); the commit steps below show the subject lines.
- No shell tool, not even opt-in (S-4, decision C-26): the bridges are `gptr$` members only; a third-party shell tool may only route through `gptr$sh()` and the `r` pipeline.
- Member signatures (04 §9.4), exactly: `gptr$sh(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE, max_tokens = NULL)` (`cmd` chr: length > 1 = argv without a shell; length 1 = a command line through `shell_resolve()` when it has shell syntax); `gptr$script(path, args = character(), interpreter = NULL, ...)`; `gptr$bg(cmd, name = NULL, stdin = FALSE, merge = TRUE)`; `gptr$jobs(kill = FALSE)`; `gptr$py(code, name = NULL, max_rows = 10L)`; `gptr$sql(query, name = NULL, con = NULL, n = 10L)`; `gptr$knit(engine, code)`. `gptr$out()` is P10's only (IC-36).
- Returns (04 §9.4): `sh`, `script` -> `gptr_cmd`; `bg` -> `gptr_job` (added to the job table); `jobs` -> "df of `bg` jobs"; `py` -> `gptr_py`; `sql` -> "data frame (all rows; prints dims + `n` rows)"; `knit` -> "chr: output of a knitr engine".
- Risks (04 §9.4): `sh` "command classifier (G5 levels); computed commands 3"; `script` 3; `bg` 3; `jobs` "0 (kill: 3)"; `py` "Python classifier"; `sql` "SQL classifier (select 0, drop 3)"; `knit` "3 (shell engines: the command classifier)". The classifiers are P11's service `risk.classify` = `function(code, envir = NULL, root = NULL, kind = c("r", "command", "sql", "python")) <gptr_risk>` (04 §7.0).
- Result classes (04 §5.10): `gptr_cmd` = "list(cmd (chr), status (int), ok (lgl), stdout (chr(1)), stderr (chr(1)), elapsed, timed_out (lgl), id (out id))", print "head 40% / tail 60% within `max_tokens`, stderr at most 25% with 200/100-token floors", "`format`/`as.character` give stdout"; `gptr_job` = "environment: `id`, `cmd`, `name`, `pid`; methods as closures `read(stream = "stdout", n = NULL)`, `wait(timeout = Inf, until = NULL)`, `write(text)`, `kill()`, `status()`", print "one line `<job id name pid status>`"; `gptr_py` = "list(name, output (chr), repr (chr)); `$value` converts to R through reticulate", print "output within budget".
- Options (04 §3.1): `gptr.helper_output_tokens` = `1500L` ("print budget of `gptr$` members"); members print "at most 0.6x the remaining `r` budget when called inside `r`" (04 §9.4) with `gptr.r_output_tokens` = `4000L`; `gptr.out_keep` = `20L` (results kept per session in the `gptr$out()` store, IC-71); `gptr.stdin_timeout` = `60`; `gptr.supervise` = `NULL` (`supervise_default()`). P22 adds no option.
- Event `bridge_call` (04 §10.4): origin gptr, notify, payload `bridge`, `id`, `cmd` (redacted), `level`, `status`, `seconds`, `bytes_out`, `bytes_err`, `spill`, `digest`; emitted by P22. The `r` tool's `details$bridge` holds "`#>` digests of bridge calls (`#> sh git status --porcelain: exit 0, 6 lines`)" (04 §4.4), collected verbatim from `bridge_call` events by P10, so `digest` carries the `#> ` prefix; P15 writes these lines into history documents (04 §11.5).
- Kind `interpreter` (04 §10.2 row 6): resolve `first`; fields "`ext` chr, `programs` chr (candidates, first found wins), `args` `function(path, args)` -> chr, `windows_only` lgl(1)"; "used by `gptr$script()`"; [experimental]; defined by P22 through the `kind` kind (IC-02, IC-69). Built-in interpreters "`.sh`, `.py`, `.R`, `.js`, `.pl`, `.rb`, `.jl`" (04 §7.22).
- Built-ins (04 §10.3): `builtin:bridges` (`bridge-sh.R`) and `builtin:lang` (`bridge-lang.R`) register "kind `interpreter`, interpreters, members, `r_session` fragments"; replaceable: yes. Declared with `on_load(ext_declare_builtin("bridges", builtin_bridges))` and `on_load(ext_declare_builtin("lang", builtin_lang))`.
- `<r_session>` fragments (03 §7.3, IC-68), byte for byte, `prompt_section` specs with `parent = "r_session"`, tier `T0`, named and ordered as P07's stand-ins (`shell` order 30, `languages` order 40, after P10's `helpers` 10 and `out` 20): `- There is no shell tool. Run programs from R: gptr$sh(c("git", "status")) (argv, no shell) or gptr$sh("cmd | filter"); gptr$script(path); gptr$bg(cmd) for long jobs. Assign results and print only what you need.` and `- Other languages: gptr$py(code); gptr$sql(query, name = df); gptr$knit(engine, code).`; "`-builtin:bridges` removes its line" (IC-68).
- Children (IC-60): bridge children only through `proc_spawn()`/`proc_run()` (P04, `encoding = "UTF-8"`), the complete `helper` environment from `child_env("helper")` (P03: inherit minus secret-like names and registered values, plus `NO_COLOR=1`, `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1`, empty `R_ENVIRON_USER`/`R_PROFILE_USER`), non-blocking stdin through `write_all()`, "Under `check_running()` every child-process pool (CLI, MCP stdio, bridges, fixtures, workers) is capped at 2"; "A requested stop is recorded ... any exit after it maps to status `stopped` (artifacts, bridges)".
- `gptr$knit()` (IC-67): "routes the shell engines (`bash`, `sh`, `zsh`, `powershell`, `cmd`) through `gptr$sh()` with the `helper` environment and a timeout, and classifies the others like `gptr$script()`". Engines that name a registered interpreter (`Rscript`, `perl`, `ruby`, `node`, `julia`, ...) also run like `gptr$script()` (a temporary script through the `gptr$sh()` engine), so that no bridge child receives the session's complete environment (IC-60); only engines without an interpreter record run through knitr itself.
- Copy safety (03 §6.4, 04 §1.3): R1 (no user object kept in a list, closure or attribute), R3 (dots reach leaves through `...elt()`, never `list(...)`), R9 "Bridges that hand objects to other runtimes (reticulate, duckdb registration) cause one copy on the next edit; this is documented, and happens only for objects the model or user passes by name". P22 owns `tests/testthat/test-copy-bridge.R`.
- Layering (03 §2.2, IC-33): the `bridge` files call only the extension API, L0 helpers (`utils`, `json`, `ext`, `http`, `proc`, `auth`), their own area, the declared services and the kernel SDK (`run_current()`, `run_eval_env()`, `run_emit()`, `session_live()`, `perm_check()`).
- Conditions used (04 §2.2): `gptr_error_invalid_argument` (`arg`, `expected`; never the argument's value), `gptr_error_invalid_spec` (`kind`, `name`, `field`, `problem`), `gptr_error_missing_package` (`package`, `feature`), `gptr_error_not_available` (`member`, `provided_by`), `gptr_error_permission` (`action`, `tool`, `risk`, `how_to_allow`, `session`), `gptr_error_process` (`command`, `status`, `stderr` (tail, redacted)), `gptr_error_spawn` (`command`), `gptr_error_timeout` (`seconds`, `what`).
- Files P22 writes: job output under `file.path(tempdir(), "gptr-jobs")` (raw child output is never persisted, IC-70); redacted spill files `gptr-output-<id>.txt` under `ws_path("cache", "tmp")` (P01 `spill_write()`); stdin temp files deleted on exit.
- P22 adds no export (63 exports unchanged); its S3 methods carry `@export` with `@noRd`, so `devtools::document()` only adds `S3method()` lines to `NAMESPACE`.
- Golden transcripts (IC-73): "P10, P13, P15, P18, P19, P22 and P23 each add their NS fixture and baseline rows" to `dev/bench/tokens/` with P07's runner.

## File Structure

| File | Responsibility |
|---|---|
| `R/bridge-sh.R` (create, Tasks 1-5) | command resolution (argv, direct, resolved shell), budgeted head+tail views, `gptr$sh()` and the `gptr_cmd` result, `bridge_call` emission, the `interpreter` kind and `gptr$script()`, background jobs (`gptr$bg()`, `gptr$jobs()`, `gptr_job`), the member specs, risks, the S-4 `tool_call` hook and refusal and the run-time re-check, `builtin:bridges` with the `shell` fragment |
| `R/bridge-lang.R` (create, Tasks 6-9) | objects passed by name, `gptr$sql()` (duckdb registration, `con =`, the DBI connection in scope), `gptr$py()` (reticulate's `__main__`, the provisioning guard), `gptr$knit()` (shell engines and engines with a registered interpreter through the `sh` engine), `builtin:lang` with the `languages` fragment and its S-4 `tool_call` hook |
| `tests/testthat/test-bridge-sh.R` (create, Tasks 1-5) | tests of `R/bridge-sh.R` |
| `tests/testthat/test-bridge-lang.R` (create, Tasks 6-9) | tests of `R/bridge-lang.R` |
| `tests/testthat/test-copy-bridge.R` (create, Task 10) | copy-safety rows: `gptr$sh()` (console, `input =`, model code) and `gptr$sql(name = df)`, with negative controls |
| `NAMESPACE` (regenerated, Tasks 2, 4, 6, 7) | `S3method()` lines for `print`/`format`/`as.character` of `gptr_cmd`, `print` of `gptr_bridge_text`, `gptr_job`, `gptr_sql`, `gptr_py` and `$` of `gptr_py` (via `devtools::document()`) |
| `dev/bench/tokens/fixtures/ns01b-polyglot-build.json` (create, Task 11) | P22's golden transcript (IC-73) |
| `dev/bench/tokens/baseline.csv` (modify, Task 11, written by P07's runner) | the `ns01b-polyglot-build` baseline row |

Tasks:

1. Command resolution and budgeted views
2. `gptr$sh()` and the `gptr_cmd` result
3. The `interpreter` kind and `gptr$script()`
4. Background jobs: `gptr$bg()` and `gptr$jobs()`
5. `builtin:bridges`: member specs, risks, the S-4 refusal, the run-time re-check and the `shell` fragment
6. Objects passed by name and `gptr$sql()`
7. `gptr$py()`
8. `gptr$knit()`
9. `builtin:lang`: member specs, risks and the `languages` fragment
10. Copy-safety rows (`tests/testthat/test-copy-bridge.R`)
11. P22's golden transcript and baseline row (`dev/bench/tokens/`)

Expected test counts are those of the development machine of conventions §1 (macOS, R 4.4.3, `bash`, `perl` and `pgrep` on `PATH`, R built with memory profiling) with testthat, withr, DBI, RSQLite, knitr and reticulate installed. Each step states the result without duckdb and without a configured Python (the maintainer's library at the time of writing) and, where it differs, with duckdb installed and `RETICULATE_PYTHON` pointing at a Python that has pandas (all skips gone). Tests that start processes call `skip_on_cran()`; Windows-only and Unix-only cases skip on the other platform.

### Task 1: Command resolution and budgeted views

The pure helpers every bridge shares: how a `cmd` becomes a program plus arguments (an argv vector runs without a shell; a simple command line whose program is on the `PATH` runs directly; anything with shell syntax runs with P04's resolved shell; G5 `sh_split()`/`resolve_command()`), how child output becomes cleaned display lines, how a head (40%) plus tail (60%) view is cut to a token budget with a notice that names the `gptr$out()` handle (G5 `budget_view()`, kept in memory because P04 already returns decoded text), and the print budget rule of 04 §9.4. `R` and `Rscript` words always mean the running R (`rscript_path()`), never a `PATH` lookup (IC-60).

**Files:**
- Create: `R/bridge-sh.R`
- Test: `tests/testthat/test-bridge-sh.R` (create)

**Interfaces:**
- Consumes: `shell_resolve(cmd)` -> `list(command, args)` (P04 `proc-spawn.R`, 04 §7.4); `clean_terminal(x)`, `est_tokens(x, class)`, `gptr_opt(name)`, `as_utf8(x)`, `rscript_path()`, `` `%||%` `` (P01, 04 §7.1); `est_tokens_each(x, class)` (P01 `utils-tokens.R`: the per-element costs whose sum bounds `est_tokens()` of the joined text) and `truncation_notice(omitted, id)` (P01 `utils-text.R`: `[... n lines omitted; all: gptr$out("<id>")]`, the notice of `truncate_output()`); `run_current()` (P06, kernel SDK); test helper `local_gptr_options(..., .env)` (P01).
- Produces (internal to P22): `bridge_split(cmd)` -> chr or `NULL`; `bridge_program_word(word)`; `bridge_resolve(cmd)` -> `list(command, args, via = "argv" | "direct" | "shell")`; `bridge_chr(x)`; `bridge_decode(x)`; `bridge_lines(text)`; `bridge_count_lines(text)`; `bridge_notice(omitted, id = NULL, stream = "stdout")`; `bridge_view_lines(lines, budget, head = 0.4, id = NULL, stream = "stdout")`; `bridge_budget(max_tokens = NULL)` -> int(1); `bridge_write(lines)`; `bridge_label(cmd, width = 50L)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-bridge-sh.R`:

```r
# Tests for R/bridge-sh.R (P22): command resolution and views, gptr_cmd results, scripts and the
# interpreter kind, background jobs, builtin:bridges.

test_that("simple command lines split into words and shell syntax does not", {
  expect_identical(bridge_split("git status --porcelain"), c("git", "status", "--porcelain"))
  expect_identical(bridge_split("echo 'quoted words' plain"), c("echo", "quoted words", "plain"))
  expect_identical(bridge_split("printf \"a b\""), c("printf", "a b"))
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
  expect_match(notice, "all: gptr$out(\"o1a2b3c\")]", fixed = TRUE)
  omitted = as.integer(sub("^\\[\\.\\.\\. ([0-9]+) lines.*$", "\\1", notice))
  expect_identical(omitted + length(v) - 1L, 20000L)
  share = (match(notice, v) - 1) / (length(v) - 1)
  expect_gt(share, 0.3)
  expect_lt(share, 0.5)
  expect_identical(bridge_view_lines(c("a", "b"), 300L), c("a", "b"))
  expect_identical(bridge_view_lines(character(), 300L), character())
  e = bridge_view_lines(lines, 250L, head = 0.2, id = "o9", stream = "stderr")
  expect_match(grep("omitted", e, value = TRUE), "gptr$out(\"o9\", \"stderr\")", fixed = TRUE)
  expect_identical(bridge_notice(3L), "[... 3 lines omitted]")
})

test_that("display lines drop ANSI codes and carriage-return progress", {
  expect_identical(bridge_lines("\033[31mred\033[0m\n10%\r50%\r100%\ndone\n"),
                   c("red", "100%", "done"))
  expect_identical(bridge_lines(""), character())
  expect_identical(bridge_count_lines("a\nb\n"), 2L)
  expect_identical(bridge_count_lines(""), 0L)
  expect_identical(bridge_decode("a\r\nb\r\n"), "a\nb\n")
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: every test errors with `could not find function "bridge_split"` (and `"bridge_resolve"`, `"bridge_chr"`, `"bridge_view_lines"`, `"bridge_lines"`, `"bridge_budget"`, `"bridge_label"`); summary `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`.

- [ ] **Step 3: Write the implementation**

Create `R/bridge-sh.R`:

```r
# Polyglot bridges, shell side (P22): gptr$sh(), gptr$script(), gptr$bg(), gptr$jobs(), the
# `interpreter` kind and builtin:bridges (contract 7.22, 9.4, 10.2 row 6; architecture 4.2, 6.7).
# Adapted from the verified G5 prototype (dev/research/G5-polyglot-glue-helpers.md, g5_helpers.R:
# sh_split(), resolve_command(), budget_view(), format.gptr_cmd(), g5_sh(), g5_script(),
# g5_bg()) with the fixes of its verification log: processx::run() is never used (item 1; P04's
# proc_run() and proc_spawn() redirect to files and decode UTF-8), stderr gets max(200, 25%) of
# the print budget and stdout keeps a 100-token floor (item 15), and a foreground timeout kills
# the process tree and suggests gptr$bg() instead of moving the job to the background.

#' Characters that make a command line need a shell (G5 sh_split)
#' @noRd
bridge_shell_meta = c("|", "&", ";", "<", ">", "(", ")", "$", "`", "*", "?", "[", "]", "{", "}",
                      "!", "\n", "\r")

#' Split a simple command line into words, or NULL when it needs a shell (G5 sh_split)
#'
#' Single and double quotes group words; `$`, backquotes and backslashes inside double quotes, any
#' shell metacharacter, a leading `~` or `#`, and a leading `NAME=value` assignment all need the
#' shell.
#' @noRd
bridge_split = function(cmd) {
  if (grepl("^\\s*[A-Za-z_][A-Za-z0-9_]*=", cmd)) return(NULL)
  chars = strsplit(cmd, "", fixed = TRUE)[[1L]]
  out = character()
  cur = ""
  has = FALSE
  quote = ""
  for (ch in chars) {
    if (identical(quote, "'")) {
      if (ch == "'") quote = "" else cur = paste0(cur, ch)
    } else if (identical(quote, "\"")) {
      if (ch == "\"") {
        quote = ""
      } else if (ch %in% c("$", "`", "\\")) {
        return(NULL)
      } else {
        cur = paste0(cur, ch)
      }
    } else if (ch %in% c(" ", "\t")) {
      if (has) {
        out = c(out, cur)
        cur = ""
        has = FALSE
      }
    } else if (ch %in% c("'", "\"")) {
      quote = ch
      has = TRUE
    } else if (ch %in% bridge_shell_meta || ch == "\\" || (!has && ch %in% c("~", "#"))) {
      return(NULL)
    } else {
      cur = paste0(cur, ch)
      has = TRUE
    }
  }
  if (nzchar(quote)) return(NULL)
  if (has) out = c(out, cur)
  if (length(out)) out else NULL
}

#' The program of a word: R and Rscript mean the running R (never a PATH lookup, IC-60)
#' @noRd
bridge_program_word = function(word) {
  exe = if (identical(.Platform$OS.type, "windows")) ".exe" else ""
  if (word %in% c("Rscript", "Rscript.exe")) return(rscript_path())
  if (word %in% c("R", "R.exe")) return(file.path(R.home("bin"), paste0("R", exe)))
  word
}

#' Resolve cmd to a program and its arguments
#'
#' Length > 1: an argv run without a shell. Length 1: a simple command line whose program is on
#' the PATH (and is not a Windows batch file) runs directly; anything else runs with the shell of
#' P04's shell_resolve() (sh on Unix; Git Bash, PowerShell or cmd on Windows), whose `args` may
#' carry the `verbatim` attribute that proc_spawn() honours.
#' @return `list(command = chr(1), args = chr, via = "argv" | "direct" | "shell")`
#' @noRd
bridge_resolve = function(cmd) {
  if (length(cmd) > 1L) {
    return(list(command = bridge_program_word(cmd[[1L]]), args = cmd[-1L], via = "argv"))
  }
  words = bridge_split(cmd)
  if (!is.null(words)) {
    prog = bridge_program_word(words[[1L]])
    path = if (grepl("[/\\\\]", prog)) prog else unname(Sys.which(prog))
    if (nzchar(path) && file.exists(path) && !grepl("\\.(cmd|bat)$", path, ignore.case = TRUE)) {
      return(list(command = prog, args = words[-1L], via = "direct"))
    }
  }
  sh = shell_resolve(cmd)
  list(command = sh$command, args = sh$args, via = "shell")
}

#' Flatten a validated JSON array (a list of strings) back to a character vector, keeping names
#'
#' Nested member calls reach the member through P06's schema validation, which turns a character
#' vector given for an `array` property into a list of strings, and `character()` into `list()`.
#' @noRd
bridge_chr = function(x) {
  if (!is.list(x)) return(x)
  if (!length(x)) return(character())
  one = vapply(x, function(e) is.character(e) && length(e) == 1L, TRUE)
  if (all(one)) unlist(x) else x
}

#' Normalise decoded child output: marked UTF-8 and LF line ends
#' @noRd
bridge_decode = function(x) {
  x = as_utf8(if (is.null(x) || !length(x) || is.na(x[[1L]])) "" else x[[1L]])
  gsub("\r\n", "\n", x, fixed = TRUE)
}

#' Display lines of an output text: ANSI and OSC removed, carriage-return progress collapsed,
#' lines capped at 400 characters (P01 clean_terminal())
#' @noRd
bridge_lines = function(text) {
  if (!length(text) || is.na(text[[1L]]) || !nzchar(text[[1L]])) return(character())
  clean_terminal(sub("\n$", "", text[[1L]]))
}

#' Number of lines of an output text
#' @noRd
bridge_count_lines = function(text) {
  if (!length(text) || is.na(text[[1L]]) || !nzchar(text[[1L]])) return(0L)
  length(strsplit(sub("\n$", "", text[[1L]]), "\n", fixed = TRUE)[[1L]])
}

#' The truncation notice naming the gptr$out() handle of the full text
#' @noRd
bridge_notice = function(omitted, id = NULL, stream = "stdout") {
  if (is.null(id)) return(paste0("[... ", omitted, " lines omitted]"))
  if (identical(stream, "stdout")) return(truncation_notice(omitted, id))
  paste0("[... ", omitted, " lines omitted; all: gptr$out(\"", id, "\", \"", stream, "\")]")
}

#' Head and tail of lines within a token budget (G5 budget_view, kept in memory)
#'
#' The head gets `head` of the budget left after the notice, the tail the rest; at least one
#' line is omitted when the lines do not fit. Per-line costs come from P01's est_tokens_each(),
#' whose sum bounds est_tokens() of the joined view, so the view never exceeds `budget`.
#' @noRd
bridge_view_lines = function(lines, budget, head = 0.4, id = NULL, stream = "stdout") {
  n = length(lines)
  if (!n) return(character())
  costs = est_tokens_each(paste0(lines, "\n"), "r_output")
  if (sum(costs) <= budget) return(lines)
  notice_cost = est_tokens_each(paste0(bridge_notice(n, id, stream), "\n"), "r_output")
  avail = max(budget - notice_cost, 0)
  head_cum = cumsum(costs)
  head_n = sum(head_cum <= avail * head)
  left = avail - if (head_n > 0L) head_cum[[head_n]] else 0
  tail_cum = cumsum(rev(costs))
  tail_n = min(sum(tail_cum <= left), n - head_n - 1L)
  c(lines[seq_len(head_n)], bridge_notice(n - head_n - tail_n, id, stream),
    if (tail_n > 0L) lines[seq.int(n - tail_n + 1L, n)])
}

#' The print budget: max_tokens when given, else gptr.helper_output_tokens, at most 0.6 x the
#' `r` budget while a run executes (contract 9.4; the rule of P10's member prints)
#' @noRd
bridge_budget = function(max_tokens = NULL) {
  if (!is.null(max_tokens)) return(as.integer(max_tokens))
  budget = as.numeric(gptr_opt("helper_output_tokens"))
  if (!is.null(run_current())) {
    budget = min(budget, floor(0.6 * as.numeric(gptr_opt("r_output_tokens"))))
  }
  as.integer(budget)
}

#' Write display lines to standard output as UTF-8 bytes; the text is data, never a format
#' string (rule C1), and the r evaluator's sink captures it
#' @noRd
bridge_write = function(lines) {
  writeLines(as_utf8(as.character(lines)), useBytes = TRUE)
  invisible(NULL)
}

#' A one-line label of a command for digests and job listings
#' @noRd
bridge_label = function(cmd, width = 50L) {
  x = gsub("\\s+", " ", paste(cmd, collapse = " "))
  if (nchar(x) > width) x = paste0(substr(x, 1L, width - 3L), "...")
  x
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 51 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-sh.R tests/testthat/test-bridge-sh.R
git commit -m "feat(bridge): command resolution and budgeted head+tail views"
```

### Task 2: `gptr$sh()` and the `gptr_cmd` result

`bridge_sh()` is the `fun` behind `gptr$sh()` (registered in Task 5) and `bridge_exec()` the engine that `gptr$script()` (Task 3) and the knit shell engines (Task 8) reuse. It resolves the command (Task 1), builds the complete `helper` child environment (P03; named `env` values are set, unnamed ones name variables passed through although they look secret, `child_env(pass =)`), sends `input` on stdin (character lines, a data frame as CSV, raw bytes), runs the child through P04's `proc_run()` (or `proc_spawn()` with one output file when `merge = TRUE`), stores stdout and stderr under one `gptr$out()` id in the running session's store (the process store at the console, IC-71), writes a redacted spill file when stdout exceeds the call's print budget (or the helper budget), so a truncation notice's `gptr$out()` id keeps working after the session store (`gptr.out_keep` = 20 entries) has dropped the entry, emits `bridge_call` with a `#> ` digest, and returns the `gptr_cmd`. A timeout kills the process tree and the status line suggests `gptr$bg()` (G5 verification log: never move the job to the background).

Copy safety: `input` is turned into new raw bytes through a temporary file before it reaches `proc_run()`, whose `tryCatch()` handlers would otherwise keep the user's vector referenced after the call (rules R1 and R3; measured for this plan: passing a character or raw `input` on as is cost one copy on the next edit, this route none; Task 10 holds the rows). The record has exactly the eight fields of 04 §5.10; the call's print budget and the resolution route travel as the attributes `max_tokens` and `via`.

The event goes into the running run with `run_emit()` (kernel SDK), so that P10's session hook collects the digest into the `r` result's `details$bridge`; at the console it is dispatched at process level with `ev_dispatch()` and the event fields of 04 §4.5 built here (`ev_new()` lives in an L1 file the `bridge` area may not call). The live record of the running session is `session_live(run$shell)`: 04 §7.6 lists the run's session id (`run$session`) among its readable fields, and P06 binds the session object itself as `run$shell` (see the self-review).

**Files:**
- Modify: `R/bridge-sh.R` (append)
- Test: `tests/testthat/test-bridge-sh.R` (append)
- Generate: `NAMESPACE` (`devtools::document()`)

**Interfaces:**
- Consumes: `proc_run(command, args = character(), input = NULL, timeout = 120, env = NULL, wd = NULL, echo = FALSE)` -> `list(status, stdout, stderr, timed_out, elapsed)`, `proc_spawn(command, args = character(), env = NULL, wd = NULL, stdin = NULL, stdout = "|", stderr = "|", cleanup_tree = TRUE, supervise = supervise_default())`, `kill_all(p, grace = 2)`, `reactor_now()` (P04, 04 §7.4, §1.2); `proc_input_file(input)` (P04 `proc-spawn.R`: chr or raw -> a temporary stdin file) and `proc_read_text(path)` (P04: a redirect file decoded as UTF-8 with the code-page fallback); `child_env(profile, pass = character(), set = character(), provider = NULL)` (P03, 04 §7.3); `out_put(text, stream = "stdout", meta = list(), session = NULL)`, `out_get(id, stream, lines, session)` (tests), `spill_write(text, prefix)` (`prefix` is the full file stem), `redact_hook(x, profile)`, `ext_service_has(name)`, `ext_service_get(name)`, `project_root()`, `check_strings()`, `check_string()`, `check_number()`, `check_flag()`, `gptr_abort()` (P01); `ev_dispatch(event, payload, session = NULL, ctx = NULL)` (P02); `run_current()`, `run_emit(run, type, ...)`, `session_live(s)` (P06 kernel SDK) and the run binding `run$shell`; the service `risk.classify` (P11, 04 §7.0) with its documented fallback (level 3 when absent); tests: `gptr_register(spec)`, `gptr_hook(event, handler, matcher = NULL)` (P02), `rscript_path()`, `est_tokens()` (P01), `withr::local_locale()`.
- Produces: `bridge_sh(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE, max_tokens = NULL)` -> `gptr_cmd` (the `fun` of member `sh`, 04 §9.4); `bridge_exec(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE, max_tokens = NULL, bridge = "sh", label = NULL, level = NULL, target = NULL)`; `bridge_risk(x, kind)` -> `list(level, categories, paths)`; `bridge_level(x, kind)` -> int(1); `bridge_emit(payload)` (the `bridge_call` event of 04 §10.4); `bridge_out_session()`; `bridge_cmd_view(x, max_tokens = NULL)`, `bridge_cmd_lines(x)`, `bridge_cmd_digest(x, bridge, label)`, `bridge_opts()`, `bridge_child_env(env = NULL)`, `bridge_check_cmd(cmd)`, `bridge_wd(wd)`; S3 methods `print.gptr_cmd(x, max_tokens = NULL, ...)`, `format.gptr_cmd()`, `as.character.gptr_cmd()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-sh.R`:

```r
r_cmd = function(code) c(rscript_path(), "--vanilla", "-e", code)

local_bridge_events = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$events = list()
  off = gptr_register(gptr_hook("bridge_call", function(event, ctx) {
    log$events[[length(log$events) + 1L]] = event
    NULL
  }))
  withr::defer(off(), envir = .env)
  log
}

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

test_that("a timeout kills the process tree and suggests gptr$bg()", {
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
  expect_match(v[[length(v)]], "gptr$bg()", fixed = TRUE)
  Sys.sleep(0.5)
  left = processx::run("pgrep", c("-f", "sleep 5[78]"), error_on_status = FALSE)$stdout
  expect_identical(left, "")
  expect_error(bridge_sh("sleep 5", timeout = 0.5, check = TRUE), class = "gptr_error_timeout")
})

test_that("long output is cut in the view and gptr$out() returns all of it", {
  skip_on_cran()
  x = bridge_sh(r_cmd("cat(seq_len(20000), sep = '\\n')"), max_tokens = 120L)
  expect_identical(attr(x, "max_tokens"), 120L)
  v = bridge_cmd_view(x)
  expect_lte(est_tokens(v, "r_output"), 120)
  notice = grep("lines omitted", v, value = TRUE, fixed = TRUE)
  expect_match(notice, paste0("gptr$out(\"", x$id, "\")"), fixed = TRUE)
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
               paste0("gptr$out(\"", x$id, "\", \"stderr\")"), fixed = TRUE)
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: the nine new tests error with `could not find function "bridge_sh"`; summary `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 51 ]`.

- [ ] **Step 3: Write the implementation**

Append to `R/bridge-sh.R`:

```r
# ---- gptr$sh(): running a command and the gptr_cmd result ----------------------------------------

#' Classify text with P11's classifiers through the risk.classify service
#'
#' Level 3 when the service is absent or fails (the classifier is advisory; contract 7.0).
#' @param kind "command", "sql" or "python".
#' @noRd
bridge_risk = function(x, kind) {
  fallback = list(level = 3L, categories = "unclassified", paths = character())
  if (!ext_service_has("risk.classify")) return(fallback)
  tryCatch(ext_service_get("risk.classify")(x, envir = NULL, root = project_root(), kind = kind),
           error = function(e) fallback)
}

#' The classified level of text as an integer
#' @noRd
bridge_level = function(x, kind) {
  as.integer(bridge_risk(x, kind)$level %||% 3L)
}

#' The live record of the running session (its gptr$out() store, IC-71), else NULL (the process
#' store). P06 binds the session object of a run as `run$shell`; P10's gptr$out() reads the same
#' store.
#' @noRd
bridge_out_session = function() {
  run = run_current()
  if (is.null(run) || is.null(run$shell)) NULL else session_live(run$shell)
}

#' Emit bridge_call (contract 10.4): into the running run, so that the `r` tool's session hook
#' collects the digest into `details$bridge` (contract 4.4), else at process level with the event
#' fields of contract 4.5 (ev_new() is L1, so the record is built here)
#'
#' `cmd` (at most 500 characters) and `digest` are redacted with the persist profile; the digest
#' becomes the `#> ` line of history documents (contract 4.4 and 11.5).
#' @noRd
bridge_emit = function(payload) {
  payload$cmd = redact_hook(substr(paste(payload$cmd, collapse = " "), 1L, 500L), "persist")
  payload$digest = redact_hook(paste0("#> ", payload$digest), "persist")
  run = run_current()
  if (is.null(run)) {
    ev = c(list(type = "bridge_call", session = NULL, run = NULL, agent = "main", turn = NULL,
                ts = as.numeric(Sys.time())), payload)
    ev_dispatch("bridge_call", ev)
  } else {
    do.call(run_emit, c(list(run, "bridge_call"), payload))
  }
  invisible(NULL)
}

#' Validate cmd: a non-empty character vector
#' @noRd
bridge_check_cmd = function(cmd) {
  check_strings(cmd, "cmd")
  if (!length(cmd) || !nzchar(trimws(cmd[[1L]]))) {
    gptr_abort("`cmd` must name a program or hold a command line.", "invalid_argument",
               arg = "cmd", expected = "a non-empty character vector")
  }
  invisible(cmd)
}

#' The sh options shared by gptr$sh(), gptr$script() and the knit shell engines; NULL means the
#' default (a validated nested call omits arguments the model did not give)
#' @noRd
bridge_opts = function(wd = NULL, timeout = NULL, merge = NULL, check = NULL,
                       max_tokens = NULL) {
  dir = wd %||% "."
  check_string(dir, "wd")
  secs = timeout %||% 120
  check_number(secs, "timeout", min = 0)
  mrg = merge %||% FALSE
  check_flag(mrg, "merge")
  chk = check %||% FALSE
  check_flag(chk, "check")
  budget = check_number(max_tokens, "max_tokens", min = 1, int = TRUE, null = TRUE)
  list(wd = dir, timeout = secs, merge = mrg, check = chk, max_tokens = budget)
}

#' The child's working directory, normalised
#' @noRd
bridge_wd = function(wd) {
  if (!dir.exists(wd)) {
    gptr_abort("The directory given as `wd` does not exist.", "invalid_argument", arg = "wd",
               expected = "an existing directory")
  }
  normalizePath(wd, winslash = "/", mustWork = TRUE)
}

#' The helper child environment (IC-60): named values of `env` are set, unnamed ones name
#' variables passed through although they look secret (for example a token the program needs)
#' @noRd
bridge_child_env = function(env = NULL) {
  if (is.null(env)) return(child_env("helper"))
  check_strings(env, "env")
  nms = names(env) %||% rep("", length(env))
  child_env("helper", pass = unname(env[!nzchar(nms)]), set = env[nzchar(nms)])
}

#' Standard input for proc_run() as new raw bytes: character lines as UTF-8 with a final newline,
#' a data frame as CSV, raw bytes as they are
#'
#' The bytes go through a temporary file (writeLines(), write.csv(), writeBin()) and are read back
#' as a new vector: paste() would put the user's vector into a list (its `...`), and proc_run()'s
#' frame creates tryCatch() handlers that keep its arguments referenced after the call, so the
#' user's next in-place edit would copy the object (architecture 6.4 rules R1 and R3; measured
#' for this plan: a character or raw `input` passed on as is cost one copy, this route none).
#' @noRd
bridge_input = function(input) {
  if (is.null(input)) return(NULL)
  if (is.character(input) && anyNA(input)) {
    gptr_abort("`input` must not contain NA.", "invalid_argument", arg = "input",
               expected = "character lines without NA")
  }
  if (!is.character(input) && !is.data.frame(input) && !is.raw(input)) {
    gptr_abort("`input` must be a character vector, a data frame or a raw vector.",
               "invalid_argument", arg = "input", expected = "character, data frame or raw")
  }
  f = tempfile("gptr-input-")
  on.exit(unlink(f), add = TRUE)
  if (is.data.frame(input)) {
    utils::write.csv(input, f, row.names = FALSE, fileEncoding = "UTF-8")
  } else if (is.raw(input)) {
    writeBin(input, f)
  } else {
    bridge_write_lines(input, f)
  }
  readBin(f, "raw", file.size(f))
}

#' Write character lines to a file as UTF-8 bytes with LF line ends; the connection is opened in
#' binary mode and closed before returning (conventions 6, IC-59)
#' @noRd
bridge_write_lines = function(lines, path) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(as_utf8(lines), con, useBytes = TRUE)
  invisible(path)
}

#' Run a child to completion through P04; merge = TRUE sends stderr into the stdout file
#' @noRd
bridge_run = function(target, input, wd, timeout, env, merge) {
  if (!isTRUE(merge)) {
    return(proc_run(target$command, target$args, input = input, timeout = timeout, env = env,
                    wd = wd))
  }
  out_f = tempfile("gptr-bridge-")
  in_f = if (is.null(input)) NULL else proc_input_file(input)
  on.exit(unlink(c(out_f, in_f)), add = TRUE)
  t0 = reactor_now()
  p = proc_spawn(target$command, target$args, env = env, wd = wd, stdin = in_f, stdout = out_f,
                 stderr = "2>&1")
  on.exit(kill_all(p, grace = 0), add = TRUE, after = FALSE)
  timed_out = FALSE
  repeat {
    p$wait(200L)
    if (!p$is_alive()) break
    if (reactor_now() - t0 > timeout) {
      timed_out = TRUE
      kill_all(p, grace = 0)
      break
    }
  }
  status = tryCatch(p$get_exit_status(), error = function(e) NULL)
  list(status = if (is.null(status)) NA_integer_ else as.integer(status),
       stdout = proc_read_text(out_f), stderr = "", timed_out = timed_out,
       elapsed = reactor_now() - t0)
}

#' The status word of a result for bridge_call
#' @noRd
bridge_cmd_status = function(x) {
  if (isTRUE(x$timed_out)) return("timeout")
  if (isTRUE(x$ok)) "ok" else paste("exit", x$status)
}

#' The digest of a result (G5 p09: "sh git status --porcelain: exit 0, 6 lines"); bridge_emit()
#' adds the `#> ` prefix
#' @noRd
bridge_cmd_digest = function(x, bridge, label) {
  n_out = bridge_count_lines(x$stdout)
  n_err = bridge_count_lines(x$stderr)
  state = if (isTRUE(x$timed_out)) "timed out" else paste("exit", x$status)
  paste0(bridge, " ", label, ": ", state, ", ", n_out, if (n_out == 1L) " line" else " lines",
         if (n_err > 0L) paste0(", ", n_err, " stderr") else "")
}

#' The status line of a view: a timeout (with the gptr$bg() hint) or a non-zero exit
#' @noRd
bridge_status_line = function(x) {
  if (isTRUE(x$timed_out)) {
    return(paste0("[timed out after ", format(round(x$elapsed, 1)),
                  "s; process tree killed; for long jobs use gptr$bg()]"))
  }
  if (!isTRUE(x$ok)) return(paste0("[exit ", x$status, "]"))
  character()
}

#' The budgeted view of a gptr_cmd: stdout head 40% + tail 60%, then "[stderr]" within
#' max(200, 25%) of the budget (head 20%), then the status line (G5 format.gptr_cmd, item 15)
#' @noRd
bridge_cmd_view = function(x, max_tokens = NULL) {
  budget = bridge_budget(max_tokens %||% attr(x, "max_tokens", exact = TRUE))
  status = bridge_status_line(x)
  err = bridge_lines(x$stderr)
  err_view = character()
  if (length(err)) {
    err_view = c("[stderr]", bridge_view_lines(err, max(200L, floor(0.25 * budget)), head = 0.2,
                                               id = x$id, stream = "stderr"))
  }
  used = sum(est_tokens_each(paste0(c(err_view, status), "\n"), "r_output"))
  out_view = bridge_view_lines(bridge_lines(x$stdout), max(100L, budget - used), head = 0.4,
                               id = x$id)
  view = c(out_view, err_view, status)
  if (length(view)) view else "(no output)"
}

#' All display lines of a gptr_cmd (stdout, [stderr], status) without truncation
#' @noRd
bridge_cmd_lines = function(x) {
  err = bridge_lines(x$stderr)
  c(bridge_lines(x$stdout), if (length(err)) c("[stderr]", err), bridge_status_line(x))
}

#' check = TRUE: a timeout or a non-zero exit becomes a classed error
#' @noRd
bridge_check = function(x, bridge, label, timeout) {
  if (isTRUE(x$timed_out)) {
    gptr_abort(c(paste0("gptr$", bridge, "() timed out after ", timeout, " s: ", label),
                 "The process tree was killed; run long jobs with gptr$bg()."),
               "timeout", seconds = timeout, what = paste0("gptr$", bridge, "()"))
  }
  if (!isTRUE(x$ok)) {
    tail_err = utils::tail(bridge_lines(x$stderr), 20L)
    gptr_abort(c(paste0("gptr$", bridge, "() exited with status ", x$status, ": ", label),
                 tail_err),
               "process", command = label, status = x$status,
               stderr = redact_hook(paste(tail_err, collapse = "\n"), "persist"))
  }
  invisible(x)
}

#' Run a command and build its gptr_cmd: the engine behind sh, script and the knit engines
#'
#' The record has exactly the fields of contract 5.10 (cmd, status, ok, stdout, stderr, elapsed,
#' timed_out, id); the print budget and the resolution route travel as the attributes
#' `max_tokens` and `via`. stdout and stderr are kept under one gptr$out() id (stderr as its
#' "stderr" stream); stdout that a print may cut (more than this call's print budget, or the
#' helper budget) is also written to the redacted spill file `gptr-output-<id>`, which P01's
#' out_get() reads once the store (gptr.out_keep entries) has dropped the entry, so the
#' truncation notice's gptr$out() id stays valid.
#' @noRd
bridge_exec = function(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE,
                       check = FALSE, max_tokens = NULL, bridge = "sh", label = NULL,
                       level = NULL, target = NULL) {
  target = target %||% bridge_resolve(cmd)
  res = bridge_run(target, bridge_input(input), bridge_wd(wd), timeout, bridge_child_env(env),
                   merge)
  timed_out = isTRUE(res$timed_out)
  status = if (timed_out) NA_integer_ else as.integer(res$status)
  out = bridge_decode(res$stdout)
  err = bridge_decode(res$stderr)
  lab = label %||% bridge_label(cmd)
  id = out_put(out, stream = "stdout",
               meta = list(stderr = err, bridge = bridge, cmd = lab),
               session = bridge_out_session())
  spill = NULL
  limit = min(as.numeric(gptr_opt("helper_output_tokens")), bridge_budget(max_tokens))
  if (est_tokens(out, "r_output") > limit) {
    spill = spill_write(out, prefix = paste0("gptr-output-", id))
  }
  x = structure(list(cmd = cmd, status = status, ok = !timed_out && identical(status, 0L),
                     stdout = out, stderr = err, elapsed = as.numeric(res$elapsed),
                     timed_out = timed_out, id = id),
                class = "gptr_cmd", max_tokens = max_tokens, via = target$via)
  bridge_emit(list(bridge = bridge, id = id, cmd = cmd,
                   level = level %||% bridge_level(cmd, "command"),
                   status = bridge_cmd_status(x), seconds = x$elapsed,
                   bytes_out = nchar(out, type = "bytes"), bytes_err = nchar(err, type = "bytes"),
                   spill = spill, digest = bridge_cmd_digest(x, bridge, lab)))
  if (isTRUE(check)) bridge_check(x, bridge, lab, timeout)
  x
}

#' gptr$sh(): run a program (argv) or a command line; UTF-8 stdout, stderr and the status
#' @noRd
bridge_sh = function(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE,
                     check = FALSE, max_tokens = NULL) {
  argv = bridge_chr(cmd)
  bridge_check_cmd(argv)
  opts = bridge_opts(wd, timeout, merge, check, max_tokens)
  bridge_exec(argv, input = input, wd = opts$wd, timeout = opts$timeout, env = bridge_chr(env),
              merge = opts$merge, check = opts$check, max_tokens = opts$max_tokens,
              bridge = "sh")
}

#' Print a command result within its budget
#' @param x A `gptr_cmd`.
#' @param max_tokens Print budget; `NULL` uses the result's own, else the helper budget.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_cmd = function(x, max_tokens = NULL, ...) {
  bridge_write(bridge_cmd_view(x, max_tokens))
  invisible(x)
}

#' A command result formats as its standard output
#' @param x A `gptr_cmd`.
#' @param ... Unused.
#' @return chr(1).
#' @export
#' @noRd
format.gptr_cmd = function(x, ...) {
  x$stdout
}

#' A command result converts to its standard output
#' @param x A `gptr_cmd`.
#' @param ... Unused.
#' @return chr(1).
#' @export
#' @noRd
as.character.gptr_cmd = function(x, ...) {
  x$stdout
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `devtools::document()` adds `S3method(as.character,gptr_cmd)`, `S3method(format,gptr_cmd)` and `S3method(print,gptr_cmd)` to `NAMESPACE` and writes no Rd file (the methods are `@noRd`); the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 120 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-sh.R tests/testthat/test-bridge-sh.R NAMESPACE
git commit -m 'feat(bridge): gptr$sh() engine, gptr_cmd results and bridge_call digests'
```

### Task 3: The `interpreter` kind and `gptr$script()`

P22 defines the 38th kind, `interpreter` (04 §10.2 row 6, IC-02, IC-69), by registering a `kind` spec from its built-in factory: P02's `ext_register()` stages a `kind` spec at once (`kind_stage()`), so the same factory can then build `interpreter` specs with `gptr_spec()`. The validator normalises `ext` (lower case, no dot) and checks the four fields; a failing field is `gptr_error_invalid_spec` naming it. The seven built-in interpreters are `sh` (`.sh`, `.bash`: bash, sh, Git Bash), `py` (python3, python, py), `r` (the running R's `Rscript`), `js` (`.js`, `.mjs`, `.cjs`: node), `pl` (perl), `rb` (ruby) and `jl` (julia); program candidates are resolved when a script runs, never at load (no disk or process work at load, 04 §7.1 `zzz.R`). `gptr$script()` picks, in order: `interpreter =` (a registered name, else a program plus leading arguments), the interpreter named like the extension (so a user record of that name overrides the built-in, IC-69), any interpreter listing the extension, then the `#!` line. Windows stubs (`System32\bash.exe`, the WindowsApps aliases) are skipped (G5 Windows notes). The `...` options of `gptr$script()` are the `gptr$sh()` options, read one by one with `...elt()` (rule R3: `list(...)` would keep a user's `input` referenced). The script's risk is 3 (Task 5).

This task adds the first version of `builtin_bridges()` (the kind and the interpreters) and its `on_load()` declaration as the last section of `R/bridge-sh.R`; Task 4 inserts its section above it and Task 5 replaces it.

**Files:**
- Modify: `R/bridge-sh.R` (append)
- Test: `tests/testthat/test-bridge-sh.R` (append)

**Interfaces:**
- Consumes: `gptr_spec(kind, name, ...)` and the `kind` meta-kind (fields `validate` `function(spec)`, `resolve`, `fields`, `order_field`, `experimental`; P02, 04 §10.2 row 30), `registry_get(kind, name, session = NULL)`, `registry_all(kind, session = NULL)` (for a `first`-resolving kind: the winning spec of each name), `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (P02); `on_load(expr)`, `rscript_path()`, `gptr_abort()`, `check_string()`, `check_strings()` (P01); `run_current()` (P06) and its field `session` (the session id, 04 §7.6); Tasks 1-2 (`bridge_program_word()`, `bridge_chr()`, `bridge_label()`, `bridge_opts()`, `bridge_exec()`); tests: `gptr_api()`, `registry_names()`, `gptr_register()` (P02), `withr::local_tempdir()`.
- Produces: the kind `interpreter` [experimental] (source `builtin:bridges`); the interpreter specs `sh`, `py`, `r`, `js`, `pl`, `rb`, `jl`; `interpreter_validate(spec)`; `bridge_script(path, args = character(), interpreter = NULL, ...)` -> `gptr_cmd` (the `fun` of member `script`, 04 §9.4); `bridge_program(programs)` -> path or `NULL`; `bridge_script_argv(path, args, interpreter = NULL)`; `bridge_session_id()`; `bridge_sh_option_names`; `builtin_bridges(gptr)` (first version) declared as `builtin:bridges`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-sh.R`:

```r
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
  expect_error(gptr_spec("interpreter", "bad", ext = 1, programs = "x",
                         args = function(path, args) path, windows_only = FALSE),
               class = "gptr_error_invalid_spec")
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 120 ]`. The six new tests fail: `could not find function "interpreter_validate"` and `could not find function "bridge_script"`; `"kind.interpreter" %in% gptr_api()$features` is `FALSE`, and `registry_names("interpreter")` and `gptr_spec("interpreter", ...)` signal `Unknown capability kind 'interpreter'; registered kinds are listed by gptr_api()$features.`

- [ ] **Step 3: Write the implementation**

Append to `R/bridge-sh.R` (the interpreter kind and `gptr$script()`):

```r
# ---- the interpreter kind and gptr$script() ------------------------------------------------------

#' Fields of the interpreter kind (contract 10.2 row 6)
#' @noRd
bridge_interpreter_fields = c("ext", "programs", "args", "windows_only")

#' Validator of the interpreter kind: ext (chr, normalised to lower case without the dot),
#' programs (chr candidates, first found wins), args (function(path, args) -> chr), windows_only
#' @noRd
interpreter_validate = function(spec) {
  name = if (is.character(spec$name) && length(spec$name) == 1L) spec$name else "?"
  bad = function(field, problem) {
    gptr_abort(paste0("Invalid interpreter spec '", name, "': field '", field, "' ", problem, "."),
               "invalid_spec", kind = "interpreter", name = name, field = field,
               problem = problem)
  }
  ext = spec$ext
  if (!is.character(ext) || !length(ext) || anyNA(ext) || !all(nzchar(ext))) {
    bad("ext", "must be a non-empty character vector")
  }
  spec$ext = tolower(sub("^\\.", "", ext))
  progs = spec$programs
  if (!is.character(progs) || !length(progs) || anyNA(progs) || !all(nzchar(progs))) {
    bad("programs", "must be a non-empty character vector")
  }
  args = spec$args %||% bridge_interpreter_args
  if (!is.function(args) || !all(c("path", "args") %in% names(formals(args)))) {
    bad("args", "must be a function(path, args)")
  }
  spec$args = args
  only = spec$windows_only %||% FALSE
  if (!is.logical(only) || length(only) != 1L || is.na(only)) {
    bad("windows_only", "must be TRUE or FALSE")
  }
  spec$windows_only = only
  spec
}

#' Default argv after the program: the script path, then its arguments
#' @noRd
bridge_interpreter_args = function(path, args) {
  c(path, args)
}

#' Git Bash candidates on Windows (never System32\bash.exe, the WSL launcher; architecture 6.7);
#' paths only, nothing is read at load time
#' @noRd
bridge_git_bash = function() {
  if (!identical(.Platform$OS.type, "windows")) return(character())
  la = Sys.getenv("LOCALAPPDATA")
  roots = c(Sys.getenv("ProgramFiles"), Sys.getenv("ProgramW6432"),
            if (nzchar(la)) file.path(la, "Programs"))
  file.path(roots[nzchar(roots)], "Git", "bin", "bash.exe")
}

#' The built-in interpreters .sh, .py, .R, .js, .pl, .rb, .jl (contract 7.22), as interpreter
#' specs; called inside builtin_bridges() after the kind is registered (P02's ext_register()
#' defines a staged `kind` at once through kind_stage(), so gptr_spec("interpreter", ...) works
#' in the same factory)
#' @noRd
bridge_interpreters = function() {
  one = function(name, ext, programs) {
    gptr_spec("interpreter", name, ext = ext, programs = programs,
              args = bridge_interpreter_args, windows_only = FALSE)
  }
  list(
    one("sh", c("sh", "bash"), c("bash", "sh", bridge_git_bash())),
    one("py", "py", c("python3", "python", "py")),
    one("r", "r", rscript_path()),
    one("js", c("js", "mjs", "cjs"), "node"),
    one("pl", "pl", "perl"),
    one("rb", "rb", "ruby"),
    one("jl", "jl", "julia")
  )
}

#' The first candidate program found (an existing path, else a PATH lookup); Windows stubs are
#' skipped: System32\bash.exe (WSL) and the WindowsApps aliases (G5 Windows notes)
#' @noRd
bridge_program = function(programs) {
  windows = identical(.Platform$OS.type, "windows")
  for (cand in programs) {
    word = bridge_program_word(cand)
    path = if (grepl("[/\\\\]", word)) word else unname(Sys.which(word))
    if (!nzchar(path) || !file.exists(path)) next
    stub = grepl("system32[/\\\\]bash\\.exe$|windowsapps", path, ignore.case = TRUE)
    if (windows && stub) next
    return(path)
  }
  NULL
}

#' argv of a script from an interpreter spec
#' @noRd
bridge_interpreter_argv = function(spec, path, args) {
  if (isTRUE(spec$windows_only) && !identical(.Platform$OS.type, "windows")) {
    gptr_abort(paste0("Interpreter '", spec$name, "' runs only on Windows."), "invalid_argument",
               arg = "interpreter", expected = "an interpreter available on this platform")
  }
  prog = bridge_program(spec$programs)
  if (is.null(prog)) {
    gptr_abort(paste0("No program was found for interpreter '", spec$name, "' (tried ",
                      paste(spec$programs, collapse = ", "), ")."),
               "spawn", command = spec$programs[[1L]])
  }
  c(prog, spec$args(path, args))
}

#' argv prefix from a script's #! line, or NULL
#' @noRd
bridge_shebang = function(path) {
  first = tryCatch(readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8"),
                   error = function(e) character())
  if (!length(first) || !startsWith(first, "#!")) return(NULL)
  words = strsplit(trimws(sub("^#!", "", first)), "\\s+")[[1L]]
  if (length(words) && identical(basename(words[[1L]]), "env")) words = words[-1L]
  if (!length(words) || !nzchar(words[[1L]])) return(NULL)
  prog = bridge_program(unique(c(words[[1L]], basename(words[[1L]]))))
  if (is.null(prog)) return(NULL)
  c(prog, words[-1L])
}

#' The session whose registry records apply: the running run's, else NULL
#' @noRd
bridge_session_id = function() {
  run = run_current()
  if (is.null(run)) NULL else run$session
}

#' The argv of a script: interpreter = (a registered name, else a program and its leading
#' arguments), else the interpreter registered for the extension (one named like the extension
#' first, so a user record of that name overrides the built-in, IC-69), else the #! line
#' @noRd
bridge_script_argv = function(path, args, interpreter = NULL) {
  sid = bridge_session_id()
  if (!is.null(interpreter)) {
    spec = if (length(interpreter) == 1L) registry_get("interpreter", interpreter, session = sid)
    if (!is.null(spec)) return(bridge_interpreter_argv(spec, path, args))
    return(c(interpreter, path, args))
  }
  ext = tolower(tools::file_ext(path))
  if (nzchar(ext)) {
    specs = registry_all("interpreter", session = sid)
    named = Filter(function(s) identical(s$name, ext) && ext %in% s$ext, specs)
    hits = if (length(named)) named else Filter(function(s) ext %in% s$ext, specs)
    if (length(hits)) return(bridge_interpreter_argv(hits[[1L]], path, args))
  }
  prefix = bridge_shebang(path)
  if (!is.null(prefix)) return(c(prefix, path, args))
  gptr_abort(c("No interpreter is registered for this script's extension and it has no #! line.",
               "Pass interpreter = (a registered interpreter name or a program)."),
             "invalid_argument", arg = "interpreter",
             expected = "a registered interpreter name or a program")
}

#' Names of the sh options gptr$script() forwards through `...`
#' @noRd
bridge_sh_option_names = c("input", "wd", "timeout", "env", "merge", "check", "max_tokens")

#' gptr$script(): run a script by its interpreter; `...` takes the gptr$sh() options
#'
#' The options are read one by one with `...elt()`, never collected with `list(...)`: a list
#' holding the user's `input` object would keep it referenced after the call (architecture 6.4
#' rule R3).
#' @noRd
bridge_script = function(path, args = character(), interpreter = NULL, ...) {
  check_string(path, "path")
  script_args = bridge_chr(args %||% character())
  check_strings(script_args, "args")
  interp = bridge_chr(interpreter)
  check_strings(interp, "interpreter", null = TRUE)
  nms = ...names()
  if (is.null(nms)) nms = rep("", ...length())
  nms[is.na(nms)] = ""
  if (length(setdiff(nms, bridge_sh_option_names))) {
    gptr_abort("`...` of gptr$script() takes the named options of gptr$sh().",
               "invalid_argument", arg = "...",
               expected = paste(bridge_sh_option_names, collapse = ", "))
  }
  at = match(bridge_sh_option_names, nms)
  input = if (is.na(at[[1L]])) NULL else ...elt(at[[1L]])
  wd = if (is.na(at[[2L]])) NULL else ...elt(at[[2L]])
  timeout = if (is.na(at[[3L]])) NULL else ...elt(at[[3L]])
  env = if (is.na(at[[4L]])) NULL else ...elt(at[[4L]])
  merge = if (is.na(at[[5L]])) NULL else ...elt(at[[5L]])
  check = if (is.na(at[[6L]])) NULL else ...elt(at[[6L]])
  max_tokens = if (is.na(at[[7L]])) NULL else ...elt(at[[7L]])
  if (!file.exists(path) || dir.exists(path)) {
    gptr_abort("The script given as `path` does not exist.", "invalid_argument", arg = "path",
               expected = "an existing script file")
  }
  file = normalizePath(path, winslash = "/", mustWork = TRUE)
  opts = bridge_opts(wd, timeout, merge, check, max_tokens)
  argv = bridge_script_argv(file, script_args, interp)
  bridge_exec(argv, input = input, wd = opts$wd, timeout = opts$timeout, env = bridge_chr(env),
              merge = opts$merge, check = opts$check, max_tokens = opts$max_tokens,
              bridge = "script", label = bridge_label(c(basename(file), script_args)),
              level = 3L)
}
```

Then append the first version of the built-in, which stays the last section of the file:

```r
# ---- builtin:bridges -----------------------------------------------------------------------------

#' builtin:bridges (contract 7.22), first part: the interpreter kind and the built-in
#' interpreters (Task 5 adds the members and the <r_session> shell line)
#' @noRd
builtin_bridges = function(gptr) {
  gptr$register(gptr_spec("kind", "interpreter", validate = interpreter_validate,
                          resolve = "first", fields = bridge_interpreter_fields,
                          experimental = TRUE))
  for (spec in bridge_interpreters()) gptr$register(spec)
  invisible(NULL)
}

on_load(ext_declare_builtin("bridges", builtin_bridges))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 149 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-sh.R tests/testthat/test-bridge-sh.R
git commit -m 'feat(bridge): the interpreter kind, seven built-in interpreters and gptr$script()'
```

### Task 4: Background jobs: `gptr$bg()` and `gptr$jobs()`

`gptr$bg()` starts a program through `proc_spawn()` with stdout (and stderr unless merged) redirected to files under `tempdir()/gptr-jobs`, so an unread job never blocks (G5 `g5_bg()`), and returns a `gptr_job` environment (04 §5.10) whose closures read new complete lines incrementally, wait for the exit, for a regular expression in new complete lines of stdout (`until`; a match in a partial last line keeps waiting, because `read()` holds partial lines back) or for a timeout while pumping P04's reactor (`reactor_pump()` with its default `allow_runs`, 04 §8.2, so stdin queued by `write()` drains meanwhile), write to stdin through P04's non-blocking `write_all()` (IC-60), kill the process tree and report the status. A killed job reads `stopped`, never `error` (IC-60). Each job is kept in this file's job process table (`bridge_state$jobs`, the kind of table 03 §2.2 rule 5 allows) and added to P04's job table with kind `bg`, so `gptr_jobs()` lists it and P04's unload cleanup stops it (IC-12, IC-36). While `check_running()` holds at most two jobs run at once (IC-60, through P04's `proc_pool_cap()`). `bridge_job_new()` creates every closure (the job's methods and the job-table callbacks) in a frame that holds no user object (rule R1).

**Files:**
- Modify: `R/bridge-sh.R` (insert above the `# ---- builtin:bridges` section of Task 3)
- Test: `tests/testthat/test-bridge-sh.R` (append)
- Generate: `NAMESPACE` (`devtools::document()`)

**Interfaces:**
- Consumes: `proc_spawn()`, `kill_all()`, `write_all(p, data)`, `job_add(kind, id, name, pid = NA, stop, status = function() "running")`, `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_now()`, `gptr_jobs(kill = FALSE)` (tests) (P04, 04 §7.4, §8.2, §6.5); `proc_pool_cap(n)` (P04 `proc-supervise.R`: `n`, or at most 2 while `check_running()`); `child_env("helper")` (P03); `raw_to_utf8(x)`, `id_new(prefix, n)`, `check_choice()`, `check_number()`, `check_string()`, `check_strings()`, `check_flag()`, `est_tokens()` (P01); Tasks 1-2 (`bridge_chr()`, `bridge_check_cmd()`, `bridge_resolve()`, `bridge_label()`, `bridge_lines()`, `bridge_view_lines()`, `bridge_budget()`, `bridge_write()`, `bridge_level()`, `bridge_emit()`); tests: `withr::local_envvar()`, `withr::defer()`.
- Produces: `bridge_bg(cmd, name = NULL, stdin = FALSE, merge = TRUE)` -> `gptr_job` (the `fun` of member `bg`); `bridge_jobs(kill = FALSE)` -> df(`id`, `name`, `pid`, `status`, `seconds`, `cmd`) (the `fun` of member `jobs`); the `gptr_job` environment: fields `id`, `cmd`, `name`, `pid`, closures `read(stream = "stdout", n = NULL)`, `wait(timeout = Inf, until = NULL)`, `write(text)`, `kill()`, `status()` (`running`, `done`, `error`, `stopped`); `bridge_text(lines, footer = NULL, out_id = NULL)` -> class `c("gptr_bridge_text", "character")` (job reads, knit output); S3 methods `print.gptr_job()`, `print.gptr_bridge_text()`; `bridge_state`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-sh.R`:

```r
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: the six new tests error with `could not find function "bridge_bg"` (or `"bridge_jobs"`); summary `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 149 ]`.

- [ ] **Step 3: Write the implementation**

Insert into `R/bridge-sh.R`, directly above the line `# ---- builtin:bridges -----...` that Task 3 added:

```r
# ---- background jobs: gptr$bg() and gptr$jobs() ------------------------------------------------

#' The gptr_job objects of this process: a job process table, which architecture 2.2 rule 5
#' allows in the namespace; each job also has a row in P04's job table, which gptr_jobs() lists
#' and whose unload cleanup stops it
#' @noRd
bridge_state = new.env(parent = emptyenv())
bridge_state$jobs = list()

#' Output lines with a budgeted print (job reads, knit output): a character vector
#' @noRd
bridge_text = function(lines, footer = NULL, out_id = NULL) {
  structure(as_utf8(as.character(lines)), class = c("gptr_bridge_text", "character"),
            footer = footer, out_id = out_id)
}

#' Print bridge output lines within the helper budget, then the footer
#' @param x A `gptr_bridge_text`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_bridge_text = function(x, ...) {
  footer = attr(x, "footer", exact = TRUE)
  budget = bridge_budget(NULL)
  if (length(footer)) budget = max(50L, budget - est_tokens(footer, "r_output"))
  view = bridge_view_lines(as.character(unclass(x)), budget, id = attr(x, "out_id", exact = TRUE))
  bridge_write(c(if (length(view)) view else "(no output)", footer))
  invisible(x)
}

#' Directory of job output files: tempdir() only, raw child output is never persisted (IC-70)
#' @noRd
bridge_job_dir = function() {
  dir = file.path(tempdir(), "gptr-jobs")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' Number of background jobs still running
#' @noRd
bridge_running_jobs = function() {
  sum(vapply(bridge_state$jobs, function(j) isTRUE(j$.proc$is_alive()), TRUE))
}

#' Default job name: the program's base name
#' @noRd
bridge_job_name = function(cmd) {
  first = if (length(cmd) > 1L) cmd[[1L]] else strsplit(trimws(cmd[[1L]]), "\\s+")[[1L]][[1L]]
  basename(first)
}

#' Bytes [from, from + n) of a file; the connection is closed before returning (IC-59)
#' @noRd
bridge_read_span = function(path, from, n) {
  if (n <= 0) return(raw())
  con = file(path, "rb")
  on.exit(close(con), add = TRUE)
  if (from > 0) seek(con, from)
  readBin(con, "raw", n)
}

#' Status of a job: running, done, error (non-zero exit) or stopped (after kill(), IC-60)
#' @noRd
bridge_job_status = function(job) {
  p = job$.proc
  if (isTRUE(p$is_alive())) return("running")
  if (isTRUE(job$.stop_requested)) return("stopped")
  if (identical(p$get_exit_status(), 0L)) "done" else "error"
}

#' New complete lines of one stream since the last read (a partial last line waits while the
#' job runs), as a gptr_bridge_text with the footer "[<id> <status>, <s>s]"
#' @noRd
bridge_job_read = function(job, stream = "stdout", n = NULL) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  n = check_number(n, "n", min = 1, int = TRUE, null = TRUE)
  path = job$.files[[stream]]
  if (is.na(path)) {
    gptr_abort("This job merges stderr into stdout (merge = TRUE); read stdout.",
               "invalid_argument", arg = "stream", expected = "\"stdout\" for a merged job")
  }
  size = if (file.exists(path)) file.size(path) else 0
  pos = job$.pos[[stream]]
  bytes = bridge_read_span(path, pos, size - pos)
  if (length(bytes) && isTRUE(job$.proc$is_alive())) {
    nl = which(bytes == as.raw(10L))
    bytes = bytes[seq_len(if (length(nl)) max(nl) else 0L)]
  }
  job$.pos[[stream]] = pos + length(bytes)
  lines = bridge_lines(raw_to_utf8(bytes))
  if (!is.null(n) && length(lines) > n) lines = utils::tail(lines, n)
  footer = paste0("[", job$id, " ", bridge_job_status(job), ", ",
                  round(reactor_now() - job$.started), "s]")
  bridge_text(lines, footer = footer)
}

#' Wait for the exit, for `until` (a regular expression) in new complete lines of stdout, or for
#' `timeout` seconds; then read() the new stdout
#'
#' `until` is matched against complete lines only, the lines read() returns, so a match in a
#' partial last line keeps waiting until the line is complete. The wait pumps P04's reactor with
#' its default `allow_runs` (contract 8.2: every run at the console, none inside an `r`
#' evaluation), so stdin queued by write() is drained meanwhile.
#' @noRd
bridge_job_wait = function(job, timeout = Inf, until = NULL) {
  check_number(timeout, "timeout", min = 0)
  check_string(until, "until", null = TRUE)
  path = job$.files[["stdout"]]
  settled = function() {
    if (!isTRUE(job$.proc$is_alive())) return(TRUE)
    if (is.null(until)) return(FALSE)
    size = if (file.exists(path)) file.size(path) else 0
    pos = job$.pos[["stdout"]]
    if (size <= pos) return(FALSE)
    bytes = bridge_read_span(path, pos, size - pos)
    nl = which(bytes == as.raw(10L))
    length(nl) > 0L && grepl(until, raw_to_utf8(bytes[seq_len(max(nl))]), perl = TRUE)
  }
  reactor_pump(until = settled, slice_ms = 200L, timeout = timeout)
  bridge_job_read(job)
}

#' Send lines to a job's stdin through P04's non-blocking write_all() (IC-60): outside a pump it
#' writes them at once; inside a running tool it queues them for the reactor
#' @noRd
bridge_job_write = function(job, text) {
  if (!isTRUE(job$.stdin)) {
    gptr_abort("This job was started without stdin = TRUE.", "invalid_argument", arg = "text",
               expected = "a job started with gptr$bg(..., stdin = TRUE)")
  }
  check_strings(text, "text")
  if (!isTRUE(job$.proc$is_alive())) {
    gptr_abort(paste0("Job ", job$id, " has exited and cannot read input."), "process",
               command = job$cmd, status = job$.proc$get_exit_status(), stderr = "")
  }
  write_all(job$.proc, paste0(paste(as_utf8(text), collapse = "\n"), "\n"))
  invisible(job)
}

#' Stop a running job and its tree; the status reads stopped, never error (IC-60)
#' @noRd
bridge_job_kill = function(job) {
  if (isTRUE(job$.proc$is_alive())) {
    job$.stop_requested = TRUE
    kill_all(job$.proc)
    job$.proc$wait(1000L)
  }
  invisible(job)
}

#' The gptr_job environment (contract 5.10): fields id, cmd, name, pid; closures read(), wait(),
#' write(), kill(), status(); private fields start with a dot. The job is added to this process's
#' job table and to P04's (kind "bg"). This frame holds no user object, so the closures it
#' creates keep none alive (architecture 6.4 rule R1).
#' @noRd
bridge_job_new = function(id, label, name, proc, out_f, err_f, stdin) {
  job = new.env(parent = emptyenv())
  job$id = id
  job$cmd = label
  job$name = name
  job$pid = proc$get_pid()
  job$.proc = proc
  job$.files = c(stdout = out_f, stderr = err_f %||% NA_character_)
  job$.pos = c(stdout = 0, stderr = 0)
  job$.started = reactor_now()
  job$.stdin = stdin
  job$.stop_requested = FALSE
  job$read = function(stream = "stdout", n = NULL) bridge_job_read(job, stream, n)
  job$wait = function(timeout = Inf, until = NULL) bridge_job_wait(job, timeout, until)
  job$write = function(text) bridge_job_write(job, text)
  job$kill = function() bridge_job_kill(job)
  job$status = function() bridge_job_status(job)
  class(job) = "gptr_job"
  bridge_state$jobs[[id]] = job
  job_add("bg", id, name, pid = job$pid, stop = function() bridge_job_kill(job),
          status = function() bridge_job_status(job))
  job
}

#' gptr$bg(): start a program in the background; stdout (and stderr unless merged) go to files
#' in tempdir(), so an unread job never blocks (G5 g5_bg)
#' @noRd
bridge_bg = function(cmd, name = NULL, stdin = FALSE, merge = TRUE) {
  argv = bridge_chr(cmd)
  bridge_check_cmd(argv)
  check_string(name, "name", null = TRUE)
  use_stdin = stdin %||% FALSE
  check_flag(use_stdin, "stdin")
  merged = merge %||% TRUE
  check_flag(merged, "merge")
  label = bridge_label(argv)
  if (bridge_running_jobs() >= proc_pool_cap(.Machine$integer.max)) {
    gptr_abort(paste("At most 2 background jobs run at once while R CMD check runs;",
                     "kill one with gptr$jobs(kill = TRUE) or job$kill()."),
               "spawn", command = label)
  }
  target = bridge_resolve(argv)
  id = id_new("j", 6L)
  dir = bridge_job_dir()
  out_f = file.path(dir, paste0(id, ".out"))
  err_f = if (merged) NULL else file.path(dir, paste0(id, ".err"))
  p = proc_spawn(target$command, target$args, env = child_env("helper"), wd = getwd(),
                 stdin = if (use_stdin) "|" else NULL, stdout = out_f,
                 stderr = if (merged) "2>&1" else err_f)
  job = bridge_job_new(id, bridge_label(argv, 60L), name %||% bridge_job_name(argv), p, out_f,
                       err_f, use_stdin)
  bridge_emit(list(bridge = "bg", id = id, cmd = argv,
                   level = max(3L, bridge_level(argv, "command")), status = "running",
                   seconds = 0, bytes_out = 0L, bytes_err = 0L, spill = NULL,
                   digest = paste0("bg ", job$name, " ", id, " started: ", label)))
  job
}

#' One line per job: <job id name pid status>
#' @param x A `gptr_job`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_job = function(x, ...) {
  bridge_write(paste0("<job ", x$id, " ", x$name, " ", x$pid, " ", x$status(), ">"))
  invisible(x)
}

#' The data frame of background jobs (id, name, pid, status, seconds, cmd)
#' @noRd
bridge_jobs_frame = function(jobs) {
  if (!length(jobs)) {
    return(data.frame(id = character(), name = character(), pid = integer(),
                      status = character(), seconds = numeric(), cmd = character()))
  }
  now = reactor_now()
  data.frame(id = vapply(jobs, function(j) j$id, ""),
             name = vapply(jobs, function(j) j$name, ""),
             pid = vapply(jobs, function(j) as.integer(j$pid), 1L),
             status = vapply(jobs, function(j) j$status(), ""),
             seconds = vapply(jobs, function(j) round(now - j$.started), 1),
             cmd = vapply(jobs, function(j) j$cmd, ""),
             row.names = NULL)
}

#' gptr$jobs(): the background jobs; kill = TRUE stops the running ones first and returns the
#' table invisibly
#' @noRd
bridge_jobs = function(kill = FALSE) {
  stop_all = kill %||% FALSE
  check_flag(stop_all, "kill")
  jobs = bridge_state$jobs
  if (!stop_all) return(bridge_jobs_frame(jobs))
  for (job in jobs) bridge_job_kill(job)
  invisible(bridge_jobs_frame(jobs))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `devtools::document()` adds `S3method(print,gptr_bridge_text)` and `S3method(print,gptr_job)` to `NAMESPACE`; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 176 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-sh.R tests/testthat/test-bridge-sh.R NAMESPACE
git commit -m 'feat(bridge): background jobs with gptr$bg() and gptr$jobs()'
```

### Task 5: `builtin:bridges`: member specs, risks, the S-4 refusal, the run-time re-check and the `shell` fragment

The members `sh`, `script`, `bg` and `jobs` are tool specs (04 §9.1, §9.4) with `exposure = "r"`, no namespace (reserved member names, IC-37), a `fun` with the 04 signature (P10 builds the `gptr$` closure from its formals), an `execute` for nested calls (P06's `dispatch_nested()` calls it when model code runs a member), `execution = "sequential"`, a `risk(input, ctx)` on the actual arguments, `record = TRUE` (04 §9.1: "bridges record digests") and `available = function(ctx) FALSE`, so no preset can put a bridge into the tool array (S-4; P07 leaves unavailable tools out).

Two guards protect the members:

- **No shell tool (S-4).** P06 looks up any registered spec with an `execute` when a model names a tool, so a model could call `sh` directly. A `tool_call` hook registered by the built-in (`gptr$on()`, 04 §10.5; decision event, 04 §10.4) blocks a top-level call that names one of its members before P06's permission check and checkpoints run, so no one is asked to approve a shell tool that does not exist; the model reads `Tool execution was blocked: gptr$sh() is an R function, not a tool: call it inside r code (there is no shell tool).` As a second line of defence the `execute` refuses the same call: P06 binds the executing call record as `run$tool_call` (04 §4.4 shape), and when that record names the bridge itself and is not nested, the call is refused with the same sentence.
- **Computed commands are re-checked at run time** (05 P22 acceptance 3; G5 design 5; 03 §6.8.4). `dispatch_nested()` runs a member without a second check when the outer `r` call's static analysis listed it at a level no higher than the level approved for the outer call; P11 lists a command computed at run time at level 3. The `execute` therefore classifies the actual arguments with the member's own `risk()` and, when they are above the approved level (`run$tool_call$approved_level`, set by P06's dispatcher), passes the call through `perm_check()` (kernel SDK) once more; a refusal is a `gptr_error_permission`, which P06's `dispatch_nested()` turns into an error result and a `gptr_error_tool` in the model's code.

The task also registers the `<r_session>` fragment `shell` (IC-68) and replaces the first version of `builtin_bridges()` (Task 3).

**Files:**
- Modify: `R/bridge-sh.R` (replace the `# ---- builtin:bridges` section of Task 3)
- Test: `tests/testthat/test-bridge-sh.R` (append)

**Interfaces:**
- Consumes: `gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL, exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL, execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL, guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE, available = NULL, annotations = list())`, `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`, `gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`, `registry_get()` (P02, 04 §6.7-§6.8); the factory API's `gptr$on(event, handler, matcher = NULL)` and the `tool_call` decision event (payload `tool_name`, `tool_call_id`, `input`, `nested`, `parent_tool_call_id`, `risk`; returns `NULL` or `list(decision = "block", reason)`; P02, 04 §10.4-§10.5); `perm_check(call, run)` -> `list(decision, reason, input, risk, rule)` (P06 kernel SDK, 04 §7.6) and the run bindings `tool_call` (with `id`, `name`, `nested`, `risk$flagged`, `approved_level`) and `session`; the service `risk.classify` (P11); tests: `gptr_check(x)`, `registry_env()`, `registry_filters_set(filters, scope)` (P02), `preset_tools(preset, human, ...)`, `gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)` (P07), `gptr_risk(code, envir = NULL, root = NULL)` (P11), the gateway `gptr` with `$`, `[[` and `.DollarNames` (P08 through P10's services), `gptr$out()` (P10), `local_project()`, `local_fake_provider()`, `fake_tool()`, `fake_text()`, `local_gptr_options()`, `msg_text()` (P01), the session accessors `$id`, `$status` and `$messages` (P06).
- Produces: the member specs `sh`, `script`, `bg`, `jobs` (04 §9.4); the `tool_call` hook of `builtin:bridges`; `bridge_block_hook(names)` (reused by Task 9); the prompt section `shell` (`parent = "r_session"`, T0, order 30); `builtin_bridges(gptr)` (final: the `interpreter` kind, the interpreters, the four members, the fragment); `bridge_member(name, description, properties, required, fun, risk, signature)`, `bridge_execute(fun, name)`, `bridge_refuse_direct(name)`, `bridge_recheck(name, input)`, `bridge_summary(name, value)`, `bridge_never_direct(ctx)`, `bridge_prop()`, `bridge_strings()`, `bridge_any()`, `bridge_sh_properties()` (reused by Task 9); `bridge_risk_sh()`, `bridge_risk_script()`, `bridge_risk_bg()`, `bridge_risk_jobs()`; `bridge_shell_fragment`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-sh.R`:

```r
shell_line = paste0(
  "- There is no shell tool. Run programs from R: gptr$sh(c(\"git\", \"status\")) (argv, no ",
  "shell) or gptr$sh(\"cmd | filter\"); gptr$script(path); gptr$bg(cmd) for long jobs. Assign ",
  "results and print only what you need."
)

# The tool results of one tool in a session, in order
tool_results = function(s, name) {
  Filter(function(m) identical(m$role, "tool_result") && identical(m$tool_name, name), s$messages)
}

test_that("builtin:bridges registers sh, script, bg and jobs as gptr$ members only", {
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
    expect_true(inherits(gptr[[nm]], "gptr_member"))
  }
  expect_identical(names(formals(registry_get("tool", "sh")$fun)),
                   c("cmd", "input", "wd", "timeout", "env", "merge", "check", "max_tokens"))
  expect_identical(formals(registry_get("tool", "sh")$fun)$timeout, 120)
  expect_identical(names(formals(registry_get("tool", "script")$fun)),
                   c("path", "args", "interpreter", "..."))
  expect_identical(names(formals(registry_get("tool", "bg")$fun)),
                   c("cmd", "name", "stdin", "merge"))
  expect_identical(names(formals(registry_get("tool", "jobs")$fun)), "kill")
  expect_true(all(c("sh", "script", "bg", "jobs") %in% utils::.DollarNames(gptr, "")))
  for (preset in c("minimal", "standard", "readonly", "extended")) {
    expect_false(any(c("sh", "script", "bg", "jobs") %in% preset_tools(preset, human = TRUE)))
  }
  expect_false(grepl("\"name\":\"sh\"", gptr_prompt(preset = "extended")$tools_json,
                     fixed = TRUE))
})

test_that("the members run through the gateway with the contract defaults", {
  skip_on_cran()
  x = gptr$sh(r_cmd("cat('hi')"))
  expect_s3_class(x, "gptr_cmd")
  expect_identical(x$stdout, "hi")
  expect_output(print(x), "^hi$")
  d = withr::local_tempdir()
  writeLines("cat('via member')", file.path(d, "m.R"))
  expect_identical(gptr$script(file.path(d, "m.R"))$stdout, "via member")
  j = gptr$bg(r_cmd("Sys.sleep(30)"), name = "sleeper")
  withr::defer(j$kill())
  tab = gptr$jobs()
  expect_identical(tab$name[match(j$id, tab$id)], "sleeper")
  invisible(gptr$jobs(kill = TRUE))
  expect_identical(j$status(), "stopped")
  long = gptr$sh(r_cmd("cat(seq_len(5000), sep = '\\n')"), max_tokens = 100L)
  expect_output(print(long), paste0("gptr$out(\"", long$id, "\")"), fixed = TRUE)
  expect_length(gptr$out(long$id), 5000L)
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

test_that("r code calling gptr$sh() is classified by the command it runs (acceptance 3)", {
  expect_identical(gptr_risk("gptr$sh(\"rm -rf data\")")$level, 3L)
  expect_identical(gptr_risk("gptr$sh(c(\"git\", \"status\"))")$level, 0L)
  expect_identical(gptr_risk("x = paste(\"rm\", f); gptr$sh(x)")$level, 3L)
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
  expect_error(gptr$sh("ls"), class = "gptr_error_unknown_member")
})

test_that("model code runs gptr$sh() inside r; the event and the nested record belong to it", {
  skip_on_cran()
  local_project()
  log = local_bridge_events()
  code = paste0("res = gptr$sh(c(", deparse(rscript_path()),
                ", \"--vanilla\", \"-e\", \"cat('hi')\"))\nres$ok")
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  e = new.env()
  s = gptr("run it", model = fake, envir = e, mode = "auto")
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
  expect_match(blocked$reason, "gptr$sh() is an R function, not a tool", fixed = TRUE)
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
  s = gptr("run it", model = fake, envir = new.env(), mode = "manual")
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
  code = paste0("cmd = c(", rs, ", \"-e\", \"file.create('marker.txt')\")\nres = gptr$sh(cmd)")
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  s = gptr("make the marker", model = fake, envir = new.env(), mode = "auto")
  expect_false(file.exists("marker.txt"))
  expect_match(msg_text(tool_results(s, "r")[[1L]]), "Permission denied", fixed = TRUE)
  ok_code = paste0("cmd = c(", rs, ", \"-e\", \"file.create('fine.txt')\")\nres = gptr$sh(cmd)")
  fake2 = local_fake_provider(list(fake_tool("r", code = ok_code), fake_text("done")),
                              name = "fake2")
  gptr("make the file", model = fake2, envir = new.env(), mode = "auto")
  expect_true(file.exists("fine.txt"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: the 176 expectations of Tasks 1-4 still pass and eight of the ten new tests fail (`FAIL` is 8 or more): `bridge_block_hook()` does not exist yet; `registry_get("tool", "sh")` is `NULL`, so `expect_s3_class()` fails and `spec$risk(...)`/`spec$available(NULL)` error with `attempt to apply non-function`; `gptr$sh` signals `gptr_error_unknown_member`; `registry_get("prompt_section", "shell")` is `NULL`; in the gateway runs the model code fails on the unknown member, so `e$res` is never created and the direct `sh` call reads `Tool sh not found`. Two tests already pass: P11 classifies `gptr$sh()` calls (acceptance 3's static half), and with Task 3's built-in there is no shell line to remove.

- [ ] **Step 3: Write the implementation**

Replace the `# ---- builtin:bridges` section of `R/bridge-sh.R` (from that heading line to the end of the file, added in Task 3) with:

```r
# ---- member specs shared by builtin:bridges and builtin:lang -------------------------------------

#' S-4: a `tool_call` hook (decision event, contract 10.4) that blocks a top-level tool call
#' naming one of `names` before P06's permission check and checkpoints run, so no one is asked
#' to approve a shell tool that does not exist; nested calls (model code inside `r`) pass. The
#' closure holds only the names.
#' @noRd
bridge_block_hook = function(names) {
  force(names)
  function(event, ctx) {
    name = event$tool_name
    direct = is.character(name) && length(name) == 1L && name %in% names &&
      !isTRUE(event$nested)
    if (!direct) return(NULL)
    list(decision = "block",
         reason = paste0("gptr$", name, "() is an R function, not a tool: call it inside r ",
                         "code (there is no shell tool)."))
  }
}

#' S-4, second line of defence (after bridge_block_hook()): refuse a bridge called as a top-level
#' tool. P06's tool lookup accepts any registered spec with an `execute`, so a model could name
#' `sh` in a tool call; the call record P06 binds while a tool executes (`run$tool_call`) then
#' names the bridge itself and is not nested.
#' @noRd
bridge_refuse_direct = function(name) {
  run = run_current()
  outer = if (is.null(run)) NULL else run$tool_call
  if (identical(outer$name, name) && !isTRUE(outer$nested)) {
    gptr_abort(paste0("gptr$", name, "() is an R function, not a tool: call it inside r code ",
                      "(there is no shell tool)."),
               "not_available", member = name, provided_by = "the r tool")
  }
  invisible(NULL)
}

#' Re-check a nested call at run time with its actual arguments (G5 section 5, architecture
#' 6.8.4)
#'
#' P06's dispatch_nested() runs a member without a second prompt when the outer `r` code's static
#' analysis listed it at a level no higher than the level approved for the outer call; a command
#' computed at run time is listed at level 3. When the actual arguments classify above the
#' approved level, the call passes perm_check() once more with the member's own risk().
#' @noRd
bridge_recheck = function(name, input) {
  run = run_current()
  outer = if (is.null(run)) NULL else run$tool_call
  if (is.null(outer) || identical(outer$name, name)) return(invisible(NULL))
  flagged = outer$risk$flagged
  if (!is.data.frame(flagged) || !nrow(flagged)) return(invisible(NULL))
  hit = flagged$fn %in% c(name, paste0("gptr$", name))
  if (!any(hit)) return(invisible(NULL))
  approved = as.integer(outer$approved_level %||% 0L)
  if (max(as.integer(flagged$level[hit])) > approved) return(invisible(NULL))
  spec = registry_get("tool", name, session = run$session)
  risk = tryCatch(spec$risk(input, NULL),
                  error = function(e) list(level = 3L, categories = "unknown"))
  level = as.integer(risk$level %||% 3L)
  if (level <= approved) return(invisible(NULL))
  call = list(id = paste0(outer$id, "/", name, "-recheck"), name = name, input = input,
              raw = NULL, tool = spec, nested = TRUE, parent_id = outer$id,
              outer_level = approved, risk = NULL)
  dec = perm_check(call, run)
  if (identical(dec$decision, "allow")) return(invisible(NULL))
  gptr_abort(paste0("Permission denied: ", dec$reason %||% "not allowed", ". The arguments of ",
                    "gptr$", name, "() computed at run time are level ", level, "."),
             "permission", action = paste0("gptr$", name, "()"), tool = name, risk = level,
             how_to_allow = "write the arguments literally so that the call is reviewed",
             session = run$session)
}

#' A one-line summary of a member value (the text of a nested tool result, which P06 keeps in
#' the outer result's details$nested)
#' @noRd
bridge_summary = function(name, value) {
  if (inherits(value, "gptr_cmd")) {
    return(bridge_cmd_digest(value, name, bridge_label(value$cmd)))
  }
  if (inherits(value, "gptr_job")) return(paste0("bg ", value$name, " ", value$id, " started"))
  if (is.data.frame(value)) {
    return(paste0(name, ": ", nrow(value), " rows x ", ncol(value), " cols"))
  }
  paste0(name, ": <", class(value)[[1L]], ">")
}

#' The `execute` of a bridge member: the form P06's dispatch_nested() runs for model code
#' (contract 7.6); refuses direct tool calls, re-checks computed arguments, returns the R value
#' @noRd
bridge_execute = function(fun, name) {
  force(fun)
  force(name)
  function(input, ctx) {
    bridge_refuse_direct(name)
    bridge_recheck(name, input)
    value = do.call(fun, as.list(input))
    gptr_tool_result(bridge_summary(name, value), value = value)
  }
}

#' Bridges are never direct tools, whatever a preset lists (S-4, C-26; contract 9.1 available)
#' @noRd
bridge_never_direct = function(ctx) FALSE

#' A bridge member spec (contract 9.4): exposure "r", no namespace (reserved names, IC-37), a
#' `fun` with the 04 signature and an `execute` for nested calls
#' @noRd
bridge_member = function(name, description, properties, required, fun, risk, signature) {
  schema = list(type = "object", properties = properties)
  if (length(required)) schema$required = I(required)
  gptr_tool(name, description, parameters = schema, execute = bridge_execute(fun, name),
            fun = fun, exposure = "r", execution = "sequential", risk = risk,
            signature = signature, record = TRUE, available = bridge_never_direct)
}

#' JSON Schema property helpers
#' @noRd
bridge_prop = function(type, description) {
  list(type = type, description = description)
}

#' @noRd
bridge_strings = function(description) {
  list(type = c("string", "array"), items = list(type = "string"), description = description)
}

#' @noRd
bridge_any = function(description) {
  list(description = description)
}

#' The schema properties of the gptr$sh() options (also gptr$script()'s `...`)
#' @noRd
bridge_sh_properties = function() {
  list(
    input = bridge_any("stdin: character lines, a data frame (as CSV) or raw bytes."),
    wd = bridge_prop("string", "Working directory (default \".\")."),
    timeout = bridge_prop("number", "Seconds (default 120); then the process tree is killed."),
    env = bridge_any("Named values to set; unnamed values name variables to pass through."),
    merge = bridge_prop("boolean", "Merge stderr into stdout (default false)."),
    check = bridge_prop("boolean", "Error on a non-zero exit or a timeout (default false)."),
    max_tokens = bridge_prop("integer", "Print budget (default gptr.helper_output_tokens).")
  )
}

# ---- builtin:bridges members, risks and the <r_session> shell line -------------------------------

#' Risk of gptr$sh(): the command classifier on the actual command (G5 levels); passing a
#' variable through to the child (an unnamed `env` element) is a secret read, level 3
#' @noRd
bridge_risk_sh = function(input, ctx) {
  r = bridge_risk(bridge_chr(input$cmd), "command")
  env = bridge_chr(input$env)
  passed = is.character(env) && any(!nzchar(names(env) %||% rep("", length(env))))
  if (!passed) return(r)
  list(level = max(3L, as.integer(r$level %||% 3L)),
       categories = unique(c(r$categories, "secret")),
       paths = as.character(r$paths %||% character()))
}

#' Risk of gptr$script(): level 3 (contract 9.4; the script body is not trusted)
#' @noRd
bridge_risk_script = function(input, ctx) {
  list(level = 3L, categories = "process", paths = as.character(input$path %||% character()))
}

#' Risk of gptr$bg(): 3, or the command's level when that is higher
#' @noRd
bridge_risk_bg = function(input, ctx) {
  r = bridge_risk(bridge_chr(input$cmd), "command")
  list(level = max(3L, as.integer(r$level %||% 3L)),
       categories = unique(c("process", r$categories)),
       paths = as.character(r$paths %||% character()))
}

#' Risk of gptr$jobs(): 0 to list, 3 to kill
#' @noRd
bridge_risk_jobs = function(input, ctx) {
  if (isTRUE(input$kill)) return(list(level = 3L, categories = "process", paths = character()))
  list(level = 0L, categories = "read", paths = character())
}

#' The <r_session> shell line (architecture 7.3 as amended by IC-68, byte for byte)
#' @noRd
bridge_shell_fragment = paste0(
  "- There is no shell tool. Run programs from R: gptr$sh(c(\"git\", \"status\")) (argv, no ",
  "shell) or gptr$sh(\"cmd | filter\"); gptr$script(path); gptr$bg(cmd) for long jobs. Assign ",
  "results and print only what you need."
)

#' The member specs sh, script, bg and jobs (contract 9.4)
#' @noRd
bridge_sh_members = function() {
  list(
    bridge_member(
      "sh",
      paste("Run a program and capture UTF-8 stdout, stderr and the exit status as a gptr_cmd.",
            "A character vector is an argv run without a shell; one string runs directly when",
            "it is a simple command and through the shell otherwise. The process tree is",
            "killed after timeout seconds. The print shows the head and tail within the helper",
            "budget; gptr$out(id) returns the rest."),
      c(list(cmd = bridge_strings("An argv vector, or one command line.")),
        bridge_sh_properties()),
      "cmd", bridge_sh, bridge_risk_sh,
      paste0("gptr$sh(cmd, input = NULL, wd = \".\", timeout = 120, env = NULL, merge = FALSE, ",
             "check = FALSE, max_tokens = NULL)")
    ),
    bridge_member(
      "script",
      paste("Run a script file with the interpreter registered for its extension (.sh, .py, .R,",
            ".js, .pl, .rb, .jl) or its #! line, or with interpreter =; `...` takes the",
            "options of gptr$sh(). Returns a gptr_cmd."),
      c(list(path = bridge_prop("string", "The script file."),
             args = bridge_strings("Arguments after the script path."),
             interpreter = bridge_strings("A registered interpreter name, or a program.")),
        bridge_sh_properties()),
      "path", bridge_script, bridge_risk_script,
      "gptr$script(path, args = character(), interpreter = NULL, ...)"
    ),
    bridge_member(
      "bg",
      paste("Start a program in the background and return a gptr_job with read(stream, n),",
            "wait(timeout, until), write(text), kill() and status(); gptr$jobs() lists it."),
      list(cmd = bridge_strings("An argv vector, or one command line."),
           name = bridge_prop("string", "Job name (default: the program)."),
           stdin = bridge_prop("boolean", "Open stdin for write() (default false)."),
           merge = bridge_prop("boolean", "Merge stderr into stdout (default true).")),
      "cmd", bridge_bg, bridge_risk_bg,
      "gptr$bg(cmd, name = NULL, stdin = FALSE, merge = TRUE)"
    ),
    bridge_member(
      "jobs",
      "List the background jobs of gptr$bg(); kill = TRUE stops the running ones.",
      list(kill = bridge_prop("boolean", "Stop every running job (default false).")),
      character(), bridge_jobs, bridge_risk_jobs, "gptr$jobs(kill = FALSE)"
    )
  )
}

#' builtin:bridges (contract 7.22): the interpreter kind, the built-in interpreters, the members
#' sh, script, bg, jobs with their S-4 `tool_call` hook and the <r_session> fragment `shell`
#' (order 30, after P10's `helpers` 10 and `out` 20; IC-68)
#' @noRd
builtin_bridges = function(gptr) {
  gptr$register(gptr_spec("kind", "interpreter", validate = interpreter_validate,
                          resolve = "first", fields = bridge_interpreter_fields,
                          experimental = TRUE))
  for (spec in bridge_interpreters()) gptr$register(spec)
  for (spec in bridge_sh_members()) gptr$register(spec)
  gptr$on("tool_call", bridge_block_hook(c("sh", "script", "bg", "jobs")))
  gptr$register(gptr_prompt_section("shell", bridge_shell_fragment, tier = "T0", order = 30L,
                                    budget = 300L, parent = "r_session"))
  invisible(NULL)
}

on_load(ext_declare_builtin("bridges", builtin_bridges))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-sh")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 270 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-sh.R tests/testthat/test-bridge-sh.R
git commit -m "feat(bridge): builtin:bridges members, the S-4 refusal, run-time re-checks and the shell line"
```

### Task 6: Objects passed by name and `gptr$sql()`

`gptr$sql(query, name = NULL, con = NULL, n = 10L)` (04 §9.4) runs SQL on one of three targets: data frames given as `name` (one object, registered in an in-memory duckdb under the label of its expression, `name = mtcars` -> table `mtcars`, or a named list of data frames), an explicit DBI connection `con`, or the one DBI connection bound in the caller's environment (G5 `find_connection()`: only `class()` is read, lazy and active bindings are skipped; several connections or none is an argument error naming them). The value holds all rows; it prints its dimensions and `n` rows within the helper budget. Statements that return no rows report the rows affected.

The label of `name = df` is read from the member call on the stack (the user's `gptr$sql(..., name = df)` or the model's own expression inside `r`), else from the direct call; the objects are never put into a new list (rule R1): `duckdb_register()` receives the user's data frame directly. The registration itself copies nothing; the next in-place edit of the frame copies once, as rule R9 documents (Task 10 measures it). The caller's environment is the run's evaluation environment while a run executes (`run_eval_env()`, kernel SDK), else the frame that called the member; frames are only looked up, never kept (rule R2).

**Files:**
- Create: `R/bridge-lang.R`
- Test: `tests/testthat/test-bridge-lang.R` (create)
- Generate: `NAMESPACE` (`devtools::document()`)

**Interfaces:**
- Consumes: `run_current()`, `run_eval_env(run)` (P06 kernel SDK); `rlang::env_binding_are_lazy()`, `rlang::env_binding_are_active()`, `methods::extends()`, `methods::is()`; `DBI::dbConnect()`, `DBI::dbGetQuery()`, `DBI::dbExecute()`, `DBI::dbDisconnect()`, `duckdb::duckdb()`, `duckdb::duckdb_register()` (Suggests, behind `requireNamespace()`); `as_utf8()`, `check_strings()`, `check_number()`, `gptr_abort()`, `reactor_now()` (P01, P04); Tasks 1-2 (`bridge_chr()`, `bridge_view_lines()`, `bridge_budget()`, `bridge_write()`, `bridge_level()`, `bridge_emit()`); tests: `RSQLite::SQLite()`, `gptr_register()`, `gptr_hook()` (P02).
- Produces: `bridge_sql(query, name = NULL, con = NULL, n = 10L)` -> a data frame of class `c("gptr_sql", "data.frame")` with attributes `gptr_n` and `gptr_affected` (the `fun` of member `sql`); `bridge_frames(fun)`, `bridge_arg_label(arg, fun)`, `bridge_is_object_list(value)`, `bridge_object_names(value, arg, fun)` (reused by Task 7), `bridge_caller_env(fun)`, `bridge_find_connection(envir)` (reused by Task 8), `bridge_sql_lines(x)`, `bridge_sql_digest(x)`, `bridge_sql_is_query(query)`; S3 method `print.gptr_sql()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-bridge-lang.R`:

```r
# Tests for R/bridge-lang.R (P22): objects passed by name, gptr$sql(), gptr$py(), gptr$knit(),
# builtin:lang.

local_bridge_events = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$events = list()
  off = gptr_register(gptr_hook("bridge_call", function(event, ctx) {
    log$events[[length(log$events) + 1L]] = event
    NULL
  }))
  withr::defer(off(), envir = .env)
  log
}

test_that("objects passed by name take the label of their expression", {
  f = function(query, name = NULL) bridge_object_names(name, "name", f)
  mt = mtcars
  expect_identical(f("q", name = mt), "mt")
  expect_identical(f("q", name = list(a = 1, b = 2)), c("a", "b"))
  expect_error(f("q", name = head(mt)), class = "gptr_error_invalid_argument")
  expect_error(f("q", name = list(1, 2)), class = "gptr_error_invalid_argument")
  expect_error(f("q", name = list()), class = "gptr_error_invalid_argument")
  member = structure(function(query, name = NULL) f(query, name = name),
                     class = c("gptr_member", "function"))
  expect_identical(member("q", name = mt), "mt")
  expect_error(member("q", name = mt[1:2, ]), class = "gptr_error_invalid_argument")
})

test_that("gptr$sql() uses the one DBI connection in the calling frame", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  f = function() {
    shop = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(shop), add = TRUE)
    DBI::dbWriteTable(shop, "orders", data.frame(id = 1:30, region = rep(c("n", "s", "e"), 10)))
    x = bridge_sql("SELECT * FROM orders WHERE id > 5")
    agg = bridge_sql("SELECT region, COUNT(*) AS n FROM orders GROUP BY region ORDER BY region")
    upd = bridge_sql("UPDATE orders SET region = 'w' WHERE id < 3")
    other = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(other), add = TRUE)
    amb = tryCatch(bridge_sql("SELECT 1"),
                   gptr_error_invalid_argument = function(e) conditionMessage(e))
    list(x = x, agg = agg, upd = upd, amb = amb)
  }
  r = f()
  expect_s3_class(r$x, "gptr_sql")
  expect_s3_class(r$x, "data.frame")
  expect_identical(nrow(r$x), 25L)
  out = utils::capture.output(print(r$x))
  expect_identical(out[[1L]], "# 25 rows x 2 cols")
  expect_identical(out[[length(out)]], "# ... 15 more rows (all rows are in the value)")
  expect_identical(as.integer(r$agg$n), c(10L, 10L, 10L))
  expect_identical(utils::capture.output(print(r$upd)), "# 2 rows affected")
  expect_match(r$amb, "(other, shop)", fixed = TRUE)
  g = function() bridge_sql("SELECT 1")
  expect_error(g(), class = "gptr_error_invalid_argument")
  expect_error(bridge_sql("SELECT 1", con = list()), class = "gptr_error_invalid_argument")
})

test_that("name = registers data frames in an in-memory duckdb under their labels", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  log = local_bridge_events()
  big = data.frame(g = rep(letters[1:5], 200), v = seq_len(1000))
  s = bridge_sql("SELECT g, COUNT(*) AS n FROM big GROUP BY g ORDER BY g", name = big)
  expect_identical(s$g, letters[1:5])
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "sql")
  expect_identical(ev$digest, "#> sql: 5 rows x 2 cols")
  two = bridge_sql("SELECT COUNT(*) AS n FROM a JOIN b USING (k)",
                   name = list(a = data.frame(k = 1:3), b = data.frame(k = 2:4)))
  expect_equal(two$n, 2)
  expect_error(bridge_sql("SELECT 1", name = head(big)), class = "gptr_error_invalid_argument")
  expect_error(bridge_sql("SELECT 1", name = list(a = 1)), class = "gptr_error_invalid_argument")
  shop = DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(shop, shutdown = TRUE))
  expect_error(bridge_sql("SELECT 1", name = big, con = shop),
               class = "gptr_error_invalid_argument")
  expect_equal(bridge_sql("SELECT 41 + 1 AS x", con = shop)$x, 42)
})

test_that("a SQL result prints within the helper budget and keeps every row", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  wide = as.data.frame(matrix(seq_len(200 * 40), nrow = 200))
  x = bridge_sql("SELECT * FROM wide", name = wide, n = 200L)
  out = utils::capture.output(print(x))
  expect_lte(est_tokens(out, "r_output"), 1500)
  expect_identical(dim(x), c(200L, 40L))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: the tests error with `could not find function "bridge_object_names"` and `could not find function "bridge_sql"`; summary `[ FAIL 2 | WARN 0 | SKIP 2 | PASS 0 ]` without duckdb (the two duckdb tests skip with `duckdb cannot be loaded`), `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]` with it.

- [ ] **Step 3: Write the implementation**

Create `R/bridge-lang.R`:

```r
# Polyglot bridges, language side (P22): gptr$py(), gptr$sql(), gptr$knit() and builtin:lang
# (contract 7.22, 9.4; architecture 4.2). Adapted from the verified G5 prototype
# (dev/research/G5-polyglot-glue-helpers.md, g5_helpers.R: find_connection(), sql_is_query(),
# g5_sql(), PY_HELPER, py_ready(), g5_py(), g5_knit()) with its verification-log fixes:
# reticulate's uv provisioning is refused unless Python is configured (item 21), a data frame
# handed to duckdb or Python is copied once on its next in-place edit (item 22, rule R9), and
# knitr's shell engines, and engines with a registered interpreter, run through the gptr$sh()
# engine with a timeout and the helper environment (item 7, IC-67, IC-60). reticulate, DBI,
# duckdb and knitr are Suggests.

# ---- objects passed by name --------------------------------------------------------------------

#' Frame numbers of the innermost gptr$ member closure and of `fun` on the call stack (0: none);
#' frames are inspected with sys.function() and never kept [R2, R3]
#' @noRd
bridge_frames = function(fun) {
  member = 0L
  own = 0L
  k = sys.nframe() - 1L
  while (k >= 1L) {
    f = sys.function(k)
    if (member == 0L && inherits(f, "gptr_member")) member = k
    if (own == 0L && identical(f, fun)) own = k
    k = k - 1L
  }
  list(member = member, own = own)
}

#' The label of a symbol argument (name = mtcars -> "mtcars"): read from the member call when one
#' is on the stack (the user's or the model's own expression), else from the call of `fun`
#' @noRd
bridge_arg_label = function(arg, fun) {
  frames = bridge_frames(fun)
  k = if (frames$member > 0L) frames$member else frames$own
  if (k > 0L) {
    mc = tryCatch(match.call(sys.function(k), sys.call(k)), error = function(e) NULL)
    expr = if (is.null(mc)) NULL else mc[[arg]]
    if (is.symbol(expr)) return(as.character(expr))
  }
  gptr_abort(paste0("Pass `", arg, " = <an object by its name>` or `", arg,
                    " = list(<name> = <object>, ...)`."),
             "invalid_argument", arg = arg, expected = "a symbol or a named list")
}

#' Is a value passed as `name` a list of named objects (rather than one object)?
#' @noRd
bridge_is_object_list = function(value) {
  is.list(value) && !is.data.frame(value)
}

#' Names under which objects are handed to another runtime: the names of a named list, or the
#' label of one object's expression. The objects themselves are never put into a new list: a
#' list holding a user object keeps it referenced after the call (architecture 6.4 rule R1).
#' @noRd
bridge_object_names = function(value, arg, fun) {
  if (bridge_is_object_list(value)) {
    nms = names(value)
    ok = length(value) && !is.null(nms) && !anyNA(nms) && all(nzchar(nms)) &&
      !anyDuplicated(nms) && identical(make.names(nms), nms)
    if (!ok) {
      gptr_abort("A list given as `name` needs unique syntactic names.", "invalid_argument",
                 arg = arg, expected = "a named list with unique syntactic names")
    }
    return(nms)
  }
  bridge_arg_label(arg, fun)
}

#' The environment of the caller: the run's evaluation environment while a run executes, else
#' the frame that called the member (or `fun`); used only for a lookup, never kept [R2]
#' @noRd
bridge_caller_env = function(fun) {
  run = run_current()
  if (!is.null(run)) return(run_eval_env(run))
  frames = bridge_frames(fun)
  target = if (frames$member > 0L) frames$member else frames$own
  if (target == 0L) return(globalenv())
  parent = sys.parents()[[target]]
  if (parent == 0L) globalenv() else sys.frame(parent)
}

# ---- gptr$sql() --------------------------------------------------------------------------------

#' Does a statement return rows (G5 sql_is_query)?
#' @noRd
bridge_sql_is_query = function(query) {
  body = toupper(sub("^\\s*((--[^\n]*\n\\s*)|(/\\*.*?\\*/\\s*))*", "", query, perl = TRUE))
  grepl("^(SELECT|WITH|VALUES|SHOW|DESCRIBE|EXPLAIN|PRAGMA|TABLE|FROM|SUMMARIZE)\\b", body,
        perl = TRUE)
}

#' The class of a binding, read in a leaf that returns a primitive [R4]; lazy and active
#' bindings are skipped by the caller, so no promise is forced
#' @noRd
bridge_class_of = function(name, envir) {
  class(get(name, envir = envir, inherits = FALSE))[[1L]]
}

#' The one DBI connection bound in envir (G5 find_connection: lazy and active bindings skipped)
#' @noRd
bridge_find_connection = function(envir) {
  nms = ls(envir)
  if (length(nms)) {
    lazy = rlang::env_binding_are_lazy(envir, nms) | rlang::env_binding_are_active(envir, nms)
    nms = nms[!lazy]
  }
  hits = character()
  for (nm in nms) {
    cls = bridge_class_of(nm, envir)
    if (isTRUE(tryCatch(methods::extends(cls, "DBIConnection"), error = function(e) FALSE))) {
      hits = c(hits, nm)
    }
  }
  if (length(hits) != 1L) {
    what = if (length(hits)) {
      paste0("Several DBI connections are in scope (", paste(sort(hits), collapse = ", "),
             "); pass con =.")
    } else {
      "No DBI connection is in scope; pass con = or name = (data frames)."
    }
    gptr_abort(what, "invalid_argument", arg = "con", expected = "one DBI connection")
  }
  get(hits, envir = envir, inherits = FALSE)
}

#' A SQL result: all rows; prints the dimensions and `n` rows (contract 9.4)
#' @noRd
bridge_sql_result = function(df, n, affected = NULL) {
  class(df) = c("gptr_sql", class(df))
  attr(df, "gptr_n") = as.integer(n)
  attr(df, "gptr_affected") = affected
  df
}

#' The digest of a SQL result (G5 p09: "sql: 3 rows x 2 cols")
#' @noRd
bridge_sql_digest = function(x) {
  affected = attr(x, "gptr_affected", exact = TRUE)
  if (!is.null(affected)) return(paste0("sql: ", affected, " rows affected"))
  paste0("sql: ", format(nrow(x), big.mark = ","), " rows x ", ncol(x), " cols")
}

#' The display lines of a SQL result: dimensions, the first n rows, the rows not shown
#' @noRd
bridge_sql_lines = function(x) {
  affected = attr(x, "gptr_affected", exact = TRUE)
  if (!is.null(affected)) return(paste0("# ", format(affected, big.mark = ","), " rows affected"))
  n = attr(x, "gptr_n", exact = TRUE) %||% 10L
  y = x
  class(y) = setdiff(class(y), "gptr_sql")
  attr(y, "gptr_n") = NULL
  attr(y, "gptr_affected") = NULL
  lines = paste0("# ", format(nrow(y), big.mark = ","), " rows x ", ncol(y), " cols")
  if (n > 0L && nrow(y) > 0L) {
    lines = c(lines, utils::capture.output(print(utils::head(y, n), row.names = FALSE)))
  }
  if (nrow(y) > n) {
    lines = c(lines, paste0("# ... ", format(nrow(y) - n, big.mark = ","),
                            " more rows (all rows are in the value)"))
  }
  as_utf8(lines)
}

#' Register the data frames given as `name` in an in-memory duckdb connection (under their
#' labels, contract 9.4); the registration copies nothing, the next in-place edit of a frame
#' copies once (rule R9)
#' @noRd
bridge_sql_register = function(db, name, labels) {
  if (bridge_is_object_list(name)) {
    for (nm in labels) duckdb::duckdb_register(db, nm, name[[nm]])
  } else {
    duckdb::duckdb_register(db, labels, name)
  }
  invisible(db)
}

#' gptr$sql(): SQL on data frames (an in-memory duckdb), on `con`, or on the one DBI connection
#' in the caller's environment; returns all rows
#' @noRd
bridge_sql = function(query, name = NULL, con = NULL, n = 10L) {
  q_lines = bridge_chr(query)
  check_strings(q_lines, "query")
  q = as_utf8(paste(q_lines, collapse = "\n"))
  if (!nzchar(trimws(q))) {
    gptr_abort("`query` must hold a SQL statement.", "invalid_argument", arg = "query",
               expected = "a non-empty SQL statement")
  }
  rows = check_number(n %||% 10L, "n", min = 0, int = TRUE)
  if (!requireNamespace("DBI", quietly = TRUE)) {
    gptr_abort("gptr$sql() needs the 'DBI' package.", "missing_package", package = "DBI",
               feature = "gptr$sql()")
  }
  if (!is.null(name) && !is.null(con)) {
    gptr_abort("Pass either `name` (data frames) or `con` (a DBI connection), not both.",
               "invalid_argument", arg = "con", expected = "NULL when `name` is given")
  }
  if (!is.null(con) && !methods::is(con, "DBIConnection")) {
    gptr_abort("`con` must be a DBI connection.", "invalid_argument", arg = "con",
               expected = "a DBIConnection")
  }
  if (!is.null(name)) {
    labels = bridge_object_names(name, "name", bridge_sql)
    one = !bridge_is_object_list(name)
    frames = if (one) is.data.frame(name) else all(vapply(name, is.data.frame, TRUE))
    if (!frames) {
      gptr_abort("`name` must hold data frames.", "invalid_argument", arg = "name",
                 expected = "a data frame or a named list of data frames")
    }
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      gptr_abort("SQL over data frames needs the 'duckdb' package; or pass con =.",
                 "missing_package", package = "duckdb", feature = "gptr$sql(name =)")
    }
    db = DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(db, shutdown = TRUE), add = TRUE)
    bridge_sql_register(db, name, labels)
  } else if (!is.null(con)) {
    db = con
  } else {
    db = bridge_find_connection(bridge_caller_env(bridge_sql))
  }
  t0 = reactor_now()
  x = if (bridge_sql_is_query(q)) {
    bridge_sql_result(DBI::dbGetQuery(db, q), rows)
  } else {
    k = DBI::dbExecute(db, q)
    bridge_sql_result(data.frame(rows_affected = k), rows, affected = k)
  }
  bridge_emit(list(bridge = "sql", id = NULL, cmd = q, level = bridge_level(q, "sql"),
                   status = "ok", seconds = reactor_now() - t0, bytes_out = 0L, bytes_err = 0L,
                   spill = NULL, digest = bridge_sql_digest(x)))
  x
}

#' Print a SQL result: dimensions, then the first n rows, within the helper budget
#' @param x A `gptr_sql` data frame.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_sql = function(x, ...) {
  bridge_write(bridge_view_lines(bridge_sql_lines(x), bridge_budget(NULL)))
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: `devtools::document()` adds `S3method(print,gptr_sql)` to `NAMESPACE`; the tests print `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 17 ]` without duckdb and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 27 ]` with it.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-lang.R tests/testthat/test-bridge-lang.R NAMESPACE
git commit -m 'feat(bridge): gptr$sql() on registered data frames, con = or the connection in scope'
```

### Task 7: `gptr$py()`

`gptr$py(code, name = NULL, max_rows = 10L)` (04 §9.4) runs Python in reticulate's persistent `__main__`, which knitr's `{python}` chunks share (G5 key finding, verification item 8). A helper defined once in `__main__` (G5 `PY_HELPER`) evaluates the code REPL-style: the value of a final expression is shown with `repr()` (pandas display bounded by `max_rows`), stdout and stderr are captured, and an exception becomes one or two lines. R objects passed by name (`name = sales`, or a named list) become Python variables of those names through `reticulate::r_to_py()`; that hand-off may copy the object once on its next in-place edit (rule R9, G5 item 22).

Provisioning guard (G5 key finding and verification item 21): without an explicit configuration reticulate's discovery ends in a uv-managed download, so `gptr$py()` refuses with `gptr_error_not_available` (`member = "py"`, `provided_by = "reticulate"`) unless Python already runs in this session or one of `RETICULATE_PYTHON`, `RETICULATE_PYTHON_ENV`, `VIRTUAL_ENV` is set.

The `gptr_py` record has exactly the fields of 04 §5.10 (`name`, `output`, `repr`); the error text, the kind of the last value (`"Series 2"`), the `gptr$out()` id and the last value itself (a Python object) are the attributes `error`, `kind`, `id` and `py`, which the `$` method exposes as `$error`, `$kind` and `$id`; `$value` converts the last value to R (04 §5.10).

**Files:**
- Modify: `R/bridge-lang.R` (append)
- Test: `tests/testthat/test-bridge-lang.R` (append)
- Generate: `NAMESPACE` (`devtools::document()`)

**Interfaces:**
- Consumes: `reticulate::py_available()`, `reticulate::import_main()`, `reticulate::py_has_attr()`, `reticulate::py_run_string()`, `reticulate::py_set_attr()`, `reticulate::r_to_py()`, `reticulate::py_get_item()`, `reticulate::py_to_r()` (Suggests, behind `requireNamespace()`); `out_put()`, `as_utf8()`, `check_strings()`, `check_number()`, `gptr_abort()` (P01); Tasks 1-2 and 6 (`bridge_chr()`, `bridge_lines()`, `bridge_view_lines()`, `bridge_budget()`, `bridge_write()`, `bridge_level()`, `bridge_emit()`, `bridge_out_session()`, `bridge_object_names()`, `bridge_is_object_list()`); tests: `testthat::local_mocked_bindings(.package = "reticulate")`, `withr::local_envvar()`, `knitr::knit_engines`, `knitr::opts_chunk`.
- Produces: `bridge_py(code, name = NULL, max_rows = 10L)` -> `gptr_py` (the `fun` of member `py`); `bridge_py_main()`, `bridge_py_assign(main, name, labels)`, `bridge_py_lines(x)`, `bridge_py_digest(x)`, `bridge_py_source`; S3 methods `$.gptr_py`, `print.gptr_py()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-lang.R`:

```r
skip_if_no_python = function() {
  skip_on_cran()
  skip_if_not_installed("reticulate")
  vars = c("RETICULATE_PYTHON", "RETICULATE_PYTHON_ENV", "VIRTUAL_ENV")
  configured = any(nzchar(Sys.getenv(vars))) || reticulate::py_available(initialize = FALSE)
  skip_if_not(configured, "Python is not configured (set RETICULATE_PYTHON)")
}

test_that("gptr$py() refuses a Python that reticulate would have to provision", {
  skip_if_not_installed("reticulate")
  testthat::local_mocked_bindings(py_available = function(initialize = FALSE) FALSE,
                                  .package = "reticulate")
  withr::local_envvar(RETICULATE_PYTHON = NA, RETICULATE_PYTHON_ENV = NA, VIRTUAL_ENV = NA)
  err = expect_error(bridge_py("1"), class = "gptr_error_not_available")
  expect_identical(err$member, "py")
})

test_that("gptr$py() keeps objects in __main__, shows the last value and one-line errors", {
  skip_if_no_python()
  bridge_py("counter = 41")
  r = bridge_py("counter += 1\ncounter")
  expect_s3_class(r, "gptr_py")
  expect_identical(names(unclass(r)), c("name", "output", "repr"))
  expect_identical(r$value, 42L)
  expect_identical(r$repr, "42")
  expect_identical(r$kind, "int")
  expect_output(print(r), "^42$")
  expect_identical(out_get(r$id), "42")
  e = bridge_py("x = 1\ny = undefined_name + x")
  expect_match(e$error, "NameError", fixed = TRUE)
  s = bridge_py("def f(:\n  pass")
  expect_match(s$error, "^SyntaxError")
  expect_false(grepl("\n", s$error, fixed = TRUE))
  expect_identical(bridge_py("x")$value, 1L)
  w = bridge_py("import sys\nsys.stderr.write('to stderr\\n')\nprint('hello')")
  expect_identical(w$output, c("hello", "[stderr]", "to stderr"))
  expect_null(w$value)
})

test_that("gptr$py() receives R objects by name and knitr python chunks share __main__", {
  skip_if_no_python()
  skip_if_not(reticulate::py_module_available("pandas"), "pandas is not installed")
  log = local_bridge_events()
  sales = data.frame(region = rep(c("north", "south"), 50), revenue = seq_len(100))
  r = bridge_py("t = sales.groupby('region').revenue.sum()\nt", name = sales)
  expect_identical(r$name, "sales")
  expect_identical(r$kind, "Series 2")
  v = r$value
  expect_equal(as.numeric(v), c(2500, 2550))
  expect_identical(names(v), c("north", "south"))
  expect_identical(log$events[[length(log$events)]]$digest, "#> py: Series 2")
  expect_identical(bridge_py("a + b", name = list(a = 1L, b = 2L))$value, 3L)
  skip_if_not_installed("knitr")
  bridge_py("shared_value = 42")
  opts = knitr::opts_chunk$merge(list(engine = "python", code = "print(shared_value)",
                                      label = "k", echo = FALSE, results = "markup"))
  out = knitr::knit_engines$get("python")(opts)
  expect_match(paste(out, collapse = ""), "42", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected without duckdb and Python: the refusal test errors with `could not find function "bridge_py"` and the two Python tests skip with `Python is not configured (set RETICULATE_PYTHON)`; summary `[ FAIL 1 | WARN 0 | SKIP 4 | PASS 17 ]`. With duckdb and a configured Python: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 27 ]`.

- [ ] **Step 3: Write the implementation**

Append to `R/bridge-lang.R`:

```r
# ---- gptr$py() ---------------------------------------------------------------------------------

#' The Python helper defined once in __main__ (G5 PY_HELPER, with its two longest lines wrapped):
#' REPL-style last value, captured stdout and stderr, one-line errors, pandas display bounded by
#' max_rows
#' @noRd
bridge_py_source = c(
  "import ast, io, sys, traceback, contextlib",
  "def _gptr_run(src, max_rows=10):",
  "    g = __import__('__main__').__dict__",
  "    out, err = io.StringIO(), io.StringIO()",
  "    val, has, exc = None, False, None",
  "    try:",
  "        tree = ast.parse(src, filename='<gptr>', mode='exec')",
  "        last = None",
  "        if tree.body and isinstance(tree.body[-1], ast.Expr):",
  "            last = ast.Expression(tree.body.pop().value)",
  "        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):",
  "            exec(compile(tree, '<gptr>', 'exec'), g)",
  "            if last is not None:",
  "                val = eval(compile(last, '<gptr>', 'eval'), g)",
  "                has = val is not None",
  "    except Exception as e:",
  "        tb = traceback.extract_tb(e.__traceback__)",
  "        lines = src.splitlines()",
  "        where = [f'line {f.lineno}: {lines[f.lineno - 1].strip()}' for f in tb",
  "                 if f.filename == '<gptr>' and 0 < f.lineno <= len(lines)]",
  "        if isinstance(e, SyntaxError):",
  "            exc = f'SyntaxError: {e.msg} (line {e.lineno}: {(e.text or \"\").strip()})'",
  "        else:",
  "            exc = '\\n'.join(where[-2:] + traceback.format_exception_only(type(e), e)).strip()",
  "    rep = ''",
  "    if has:",
  "        try:",
  "            pd = sys.modules.get('pandas')",
  "            if pd is not None:",
  "                with pd.option_context('display.max_rows', max_rows, 'display.min_rows',",
  "                                       max_rows, 'display.max_columns', 12,",
  "                                       'display.width', 160,",
  "                                       'display.expand_frame_repr', False):",
  "                    rep = repr(val)",
  "            else:",
  "                rep = repr(val)",
  "        except Exception as e:",
  "            rep = '<repr failed: %s>' % e",
  "        g['_'] = val",
  "    kind = ''",
  "    if has:",
  "        shp = getattr(val, 'shape', None)",
  "        kind = type(val).__name__",
  "        if isinstance(shp, tuple) and shp:",
  "            kind = kind + ' ' + 'x'.join(map(str, shp))",
  "    return (out.getvalue(), err.getvalue(), rep, exc, val if has else None, kind)"
)

#' reticulate's __main__ with the helper; refuses a Python that reticulate would have to
#' provision (its discovery ends in a uv-managed download, G5 key finding and item 21): Python must
#' be running already or chosen through RETICULATE_PYTHON, RETICULATE_PYTHON_ENV or VIRTUAL_ENV
#' @noRd
bridge_py_main = function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    gptr_abort("gptr$py() needs the 'reticulate' package.", "missing_package",
               package = "reticulate", feature = "gptr$py()")
  }
  if (!reticulate::py_available(initialize = FALSE)) {
    vars = c("RETICULATE_PYTHON", "RETICULATE_PYTHON_ENV", "VIRTUAL_ENV")
    if (!any(nzchar(Sys.getenv(vars)))) {
      gptr_abort(c("Python is not configured for gptr$py().",
                   paste("Set RETICULATE_PYTHON (or RETICULATE_PYTHON_ENV), activate a virtual",
                         "environment, or initialise Python yourself (reticulate::py_config());",
                         "gptr never lets reticulate download a managed Python.")),
                 "not_available", member = "py", provided_by = "reticulate")
    }
  }
  main = reticulate::import_main(convert = FALSE)
  if (!reticulate::py_has_attr(main, "_gptr_run")) {
    reticulate::py_run_string(paste(bridge_py_source, collapse = "\n"), convert = FALSE)
  }
  main
}

#' Hand R objects to Python's __main__ under their names (one object by its label, or the
#' elements of a named list), without putting them into a new R list (rule R1); the next
#' in-place edit of an object handed over may copy it once (rule R9)
#' @noRd
bridge_py_assign = function(main, name, labels) {
  if (bridge_is_object_list(name)) {
    for (nm in labels) reticulate::py_set_attr(main, nm, reticulate::r_to_py(name[[nm]]))
  } else {
    reticulate::py_set_attr(main, labels, reticulate::r_to_py(name))
  }
  invisible(main)
}

#' All display lines of a gptr_py: output, then the repr of the last value, then the error
#' @noRd
bridge_py_lines = function(x) {
  err = attr(x, "error", exact = TRUE)
  lines = c(.subset2(x, "output"), .subset2(x, "repr"),
            if (!is.null(err)) c("[python error]", bridge_lines(err)))
  if (length(lines)) lines else "(no output)"
}

#' The digest of a gptr_py (G5 p09: "py: Series 2")
#' @noRd
bridge_py_digest = function(x) {
  err = attr(x, "error", exact = TRUE)
  if (!is.null(err)) return(paste("py error:", strsplit(err, "\n", fixed = TRUE)[[1L]][[1L]]))
  kind = attr(x, "kind", exact = TRUE)
  if (is.null(kind) || !nzchar(kind)) "py: ok (no value)" else paste("py:", kind)
}

#' gptr$py(): Python in reticulate's persistent __main__ (shared with knitr python chunks); R
#' objects passed by name become Python variables of those names
#'
#' The record has the fields of contract 5.10 (name, output, repr); the Python error, the kind of
#' the last value (`"Series 2"`), the gptr$out() id and the last value itself (a Python object,
#' converted by `$value`) are the attributes `error`, `kind`, `id` and `py`.
#' @noRd
bridge_py = function(code, name = NULL, max_rows = 10L) {
  src_lines = bridge_chr(code)
  check_strings(src_lines, "code")
  rows = check_number(max_rows %||% 10L, "max_rows", min = 1, int = TRUE)
  labels = if (is.null(name)) character() else bridge_object_names(name, "name", bridge_py)
  main = bridge_py_main()
  if (length(labels)) bridge_py_assign(main, name, labels)
  src = as_utf8(paste(src_lines, collapse = "\n"))
  t0 = reactor_now()
  res = main$`_gptr_run`(src, rows)
  out = as_utf8(reticulate::py_to_r(reticulate::py_get_item(res, 0L)))
  err = as_utf8(reticulate::py_to_r(reticulate::py_get_item(res, 1L)))
  shown = as_utf8(reticulate::py_to_r(reticulate::py_get_item(res, 2L)))
  exc = reticulate::py_to_r(reticulate::py_get_item(res, 3L))
  output = c(bridge_lines(out), if (nzchar(err)) c("[stderr]", bridge_lines(err)))
  x = structure(list(name = labels, output = output, repr = bridge_lines(shown)),
                class = "gptr_py", error = if (is.null(exc)) NULL else as_utf8(exc),
                kind = reticulate::py_to_r(reticulate::py_get_item(res, 5L)),
                py = reticulate::py_get_item(res, 4L))
  text = paste(bridge_py_lines(x), collapse = "\n")
  attr(x, "id") = out_put(text, stream = "stdout", meta = list(bridge = "py"),
                          session = bridge_out_session())
  bridge_emit(list(bridge = "py", id = attr(x, "id"), cmd = src,
                   level = bridge_level(src, "python"),
                   status = if (is.null(attr(x, "error"))) "ok" else "error",
                   seconds = reactor_now() - t0, bytes_out = nchar(text, type = "bytes"),
                   bytes_err = nchar(err, type = "bytes"), spill = NULL,
                   digest = bridge_py_digest(x)))
  x
}

#' Fields of a Python result: `$value` converts the last Python value to R through reticulate;
#' `$error`, `$kind` and `$id` read the attributes of the same names; other names are fields
#' @param x A `gptr_py`.
#' @param name Field name.
#' @return The field, the attribute or the converted value.
#' @export
#' @noRd
`$.gptr_py` = function(x, name) {
  if (identical(name, "value")) {
    obj = attr(x, "py", exact = TRUE)
    return(if (is.null(obj)) NULL else reticulate::py_to_r(obj))
  }
  if (name %in% c("error", "kind", "id")) return(attr(x, name, exact = TRUE))
  .subset2(x, name)
}

#' Print a Python result within the helper budget
#' @param x A `gptr_py`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_py = function(x, ...) {
  bridge_write(bridge_view_lines(bridge_py_lines(x), bridge_budget(NULL),
                                 id = attr(x, "id", exact = TRUE)))
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: `devtools::document()` adds `S3method("$",gptr_py)` and `S3method(print,gptr_py)` to `NAMESPACE`; the tests print `[ FAIL 0 | WARN 0 | SKIP 4 | PASS 19 ]` without duckdb and Python, and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 49 ]` with duckdb and `RETICULATE_PYTHON` set to a Python with pandas (for example `RETICULATE_PYTHON=/opt/homebrew/bin/python3 Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'`; nothing is installed by the test).

- [ ] **Step 5: Commit**

```bash
git add R/bridge-lang.R tests/testthat/test-bridge-lang.R NAMESPACE
git commit -m 'feat(bridge): gptr$py() in reticulate __main__ with the provisioning guard'
```

### Task 8: `gptr$knit()`

`gptr$knit(engine, code)` (04 §9.4) returns the output lines of a knitr language engine. The shell engines (`bash`, `sh`, `zsh`, `powershell`, `cmd`) never reach knitr: knitr's bash engine runs `system2()` with no timeout and assumes bash (G5 verification item 7), so they run through the `gptr$sh()` engine of Task 2 with the complete `helper` environment and a timeout (IC-67): `bash -c`/`sh -c`/`zsh -c` on Unix, Git Bash on Windows, PowerShell with `-EncodedCommand` (P04's `shell_ps_encode()`), and `cmd /d /s /c "chcp 65001 >nul & ..."` on Windows only. `python` and `sql` run through `gptr$py()` (its provisioning guard and the shared `__main__`) and `gptr$sql()` on the one DBI connection in the caller's scope, as G5 routes them. An engine that names a registered interpreter (an interpreter of that name, or one whose `programs` include it: `Rscript`, `R`, `perl`, `ruby`, `node`, `js`, `julia`, `python3`) runs like `gptr$script()`: the code goes to a temporary script with the interpreter's first extension and runs through the `gptr$sh()` engine with the `helper` environment and the timeout. knitr's own engines for these programs call `system2()` without a timeout and hand the child the session's complete environment, registered keys included, which IC-60 forbids for bridge children (a `perl` chunk could read a key the secret guard would stop in `r`). Every other engine (non-interpreter engines such as `cat`, `verbatim` or a user-registered engine, and programs gptr has no interpreter record for) runs through knitr with its `running:` message suppressed. The timeout is `bridge_knit_timeout()` (120 s, `gptr$sh()`'s default), a function so that the test can shorten it with `local_mocked_bindings()` without a new option.

**Files:**
- Modify: `R/bridge-lang.R` (append)
- Test: `tests/testthat/test-bridge-lang.R` (append)

**Interfaces:**
- Consumes: `shell_resolve(cmd)` (P04, Windows Git Bash) and `shell_ps_encode(cmd)` (P04 `proc-spawn.R`: base64 of the UTF-16LE command with the UTF-8 output prefix and the `$LASTEXITCODE` postfix); `knitr::knit_engines`, `knitr::opts_chunk` (Suggests); `registry_all(kind, session = NULL)` (P02); `out_put()`, `as_utf8()`, `check_string()`, `check_strings()`, `gptr_abort()`, `reactor_now()` (P01, P04); Tasks 1-7 (`bridge_exec()`, `bridge_program()`, `bridge_cmd_lines()`, `bridge_write_lines()`, `bridge_interpreter_argv()`, `bridge_session_id()`, `bridge_text()`, `bridge_py()`, `bridge_py_lines()`, `bridge_sql()`, `bridge_sql_lines()`, `bridge_find_connection()`, `bridge_caller_env()`, `bridge_level()`, `bridge_emit()`, `bridge_out_session()`); tests: `secret_register(value, name, source = "user", active = TRUE, origin = NULL)` and `vault_reset()` (P03), `RSQLite::SQLite()`, `knitr::knit_engines$set()`/`$delete()`.
- Produces: `bridge_knit(engine, code)` -> `gptr_bridge_text` (a character vector; the `fun` of member `knit`); `bridge_knit_shells`; `bridge_knit_timeout()`; `bridge_knit_target(engine, code)`; `bridge_knit_interpreter(engine)` -> an interpreter spec or `NULL`; `bridge_knit_script(spec, engine, src)` -> `gptr_cmd`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-lang.R`:

```r
test_that("shell engines run through gptr$sh() without registered keys and with a timeout", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")) || !nzchar(Sys.which("pgrep")))
  key = paste0("gptr-fake-", "key-0123456789abcdef")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(GPTR_P22_PLAIN = key)
  secret_register(key, "GPTR_P22_PLAIN", source = "user")
  log = local_bridge_events()
  out = bridge_knit("bash", "echo \"from bash: $((6 * 7))\"; env")
  expect_s3_class(out, "gptr_bridge_text")
  expect_true("from bash: 42" %in% out)
  expect_false(any(grepl(key, out, fixed = TRUE)))
  expect_true("TERM=dumb" %in% out)
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "knit")
  expect_match(ev$digest, "^#> knit bash: exit 0, ")
  testthat::local_mocked_bindings(bridge_knit_timeout = function() 1)
  t0 = proc.time()[["elapsed"]]
  slow = bridge_knit("bash", "sleep 999")
  expect_lt(proc.time()[["elapsed"]] - t0, 10)
  expect_true(any(grepl("timed out after", slow, fixed = TRUE)))
  Sys.sleep(0.5)
  left = processx::run("pgrep", c("-f", "sleep 999"), error_on_status = FALSE)$stdout
  expect_identical(left, "")
})

test_that("interpreter engines run as scripts without registered keys and with a timeout", {
  skip_on_cran()
  key = paste0("gptr-fake-", "key-fedcba9876543210")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(GPTR_P22_PLAIN = key)
  secret_register(key, "GPTR_P22_PLAIN", source = "user")
  log = local_bridge_events()
  code = "cat(sprintf('from R: %d [%s]\\n', 6L * 7L, Sys.getenv('GPTR_P22_PLAIN')))"
  out = bridge_knit("Rscript", code)
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(as.character(out), "from R: 42 []")
  expect_identical(out_get(attr(out, "out_id")), "from R: 42 []")
  ev = log$events[[length(log$events)]]
  expect_identical(ev$bridge, "knit")
  expect_identical(ev$digest, "#> knit Rscript: exit 0, 1 line")
  testthat::local_mocked_bindings(bridge_knit_timeout = function() 1)
  t0 = proc.time()[["elapsed"]]
  slow = bridge_knit("Rscript", "Sys.sleep(30)")
  expect_lt(proc.time()[["elapsed"]] - t0, 10)
  expect_true(any(grepl("timed out after", slow, fixed = TRUE)))
  skip_if(!nzchar(Sys.which("perl")))
  pl = bridge_knit("perl", "print \"from perl: \", 6 * 7, \"\\n\";")
  expect_identical(as.character(pl), "from perl: 42")
})

test_that("other engines run through knitr", {
  skip_if_not_installed("knitr")
  knitr::knit_engines$set(gptrp22test = function(options) {
    paste0("engine gptrp22test got: ", paste(options$code, collapse = " | "))
  })
  withr::defer(knitr::knit_engines$delete("gptrp22test"))
  out = bridge_knit("gptrp22test", c("a", "b"))
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(as.character(out), "engine gptrp22test got: a | b")
  expect_identical(out_get(attr(out, "out_id")), "engine gptrp22test got: a | b")
  expect_error(bridge_knit("nosuchengine", "x"), class = "gptr_error_invalid_argument")
})

test_that("the python and sql engines run through gptr$py() and gptr$sql()", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  f = function() {
    shop = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(shop), add = TRUE)
    DBI::dbWriteTable(shop, "orders", data.frame(id = 1:3))
    bridge_knit("sql", "SELECT COUNT(*) AS n FROM orders")
  }
  out = f()
  expect_s3_class(out, "gptr_bridge_text")
  expect_identical(out[[1L]], "# 1 rows x 1 cols")
  expect_true(any(grepl("^ *3$", out)))
  skip_if_no_python()
  py = bridge_knit("python", "6 * 7")
  expect_identical(as.character(py), "42")
  expect_identical(out_get(attr(py, "out_id")), "42")
})

test_that("the cmd engine is refused outside Windows", {
  skip_on_os("windows")
  expect_error(bridge_knit("cmd", "dir"), class = "gptr_error_invalid_argument")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: the five new tests error with `could not find function "bridge_knit"`; summary `[ FAIL 5 | WARN 0 | SKIP 4 | PASS 19 ]` without duckdb and Python, `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 49 ]` with both.

- [ ] **Step 3: Write the implementation**

Append to `R/bridge-lang.R`:

```r
# ---- gptr$knit() --------------------------------------------------------------------------------

#' knitr engines that run through the gptr$sh() engine (IC-67)
#' @noRd
bridge_knit_shells = c("bash", "sh", "zsh", "powershell", "cmd")

#' Seconds before a shell engine's process tree is killed: gptr$sh()'s default
#' @noRd
bridge_knit_timeout = function() {
  120
}

#' How to run code with a shell engine: list(command, args, via); knitr's own bash engine has no
#' timeout and assumes bash (G5 item 7)
#' @noRd
bridge_knit_target = function(engine, code) {
  windows = identical(.Platform$OS.type, "windows")
  if (engine %in% c("bash", "sh", "zsh")) {
    if (windows) {
      sh = shell_resolve(code)
      if (!grepl("bash", basename(sh$command), ignore.case = TRUE)) {
        gptr_abort(paste0("The ", engine, " engine needs Git Bash on Windows."), "spawn",
                   command = engine)
      }
      return(list(command = sh$command, args = sh$args, via = "shell"))
    }
    prog = bridge_program(engine)
    if (is.null(prog)) {
      gptr_abort(paste0("No ", engine, " program was found."), "spawn", command = engine)
    }
    return(list(command = prog, args = c("-c", code), via = "shell"))
  }
  if (identical(engine, "powershell")) {
    prog = bridge_program(c("pwsh", "powershell"))
    if (is.null(prog)) {
      gptr_abort("No PowerShell program was found.", "spawn", command = "powershell")
    }
    return(list(command = prog, args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy",
                                         "Bypass", "-EncodedCommand", shell_ps_encode(code)),
                via = "shell"))
  }
  if (!windows) {
    gptr_abort("The cmd engine runs only on Windows.", "invalid_argument", arg = "engine",
               expected = "an engine available on this platform")
  }
  comspec = Sys.getenv("COMSPEC")
  if (!nzchar(comspec)) comspec = "cmd.exe"
  args = c("/d", "/s", "/c", paste0("\"chcp 65001 >nul & ", code, "\""))
  attr(args, "verbatim") = TRUE
  list(command = comspec, args = args, via = "shell")
}

#' The registered interpreter that runs a knitr engine, or NULL: an interpreter named like the
#' engine, else one whose programs include it (Rscript, perl, ruby, node, julia, ...)
#' @noRd
bridge_knit_interpreter = function(engine) {
  eng = tolower(engine)
  for (spec in registry_all("interpreter", session = bridge_session_id())) {
    progs = tolower(sub("\\.exe$", "", basename(spec$programs), ignore.case = TRUE))
    if (identical(tolower(spec$name), eng) || eng %in% progs) return(spec)
  }
  NULL
}

#' Run engine code with an interpreter, like gptr$script(): a temporary script with the
#' interpreter's first extension, run through the gptr$sh() engine with the helper environment
#' and the knit timeout (IC-60); knitr's own engines would call system2() without a timeout and
#' with the session's complete environment
#' @noRd
bridge_knit_script = function(spec, engine, src) {
  f = tempfile("gptr-knit-", fileext = paste0(".", spec$ext[[1L]]))
  on.exit(unlink(f), add = TRUE)
  bridge_write_lines(src, f)
  argv = bridge_interpreter_argv(spec, f, character())
  bridge_exec(argv, timeout = bridge_knit_timeout(), bridge = "knit", label = engine,
              level = 3L)
}

#' gptr$knit(): run code with a knitr language engine and return its output lines
#'
#' Shell engines run through the gptr$sh() engine (helper environment, timeout; IC-67); `python`
#' and `sql` run through gptr$py() (its provisioning guard and shared __main__) and gptr$sql()
#' (the one DBI connection in the caller's scope), as G5 routes them; an engine that names a
#' registered interpreter runs as a script through the same engine (IC-60); every other engine
#' runs through knitr with its "running:" message suppressed.
#' @noRd
bridge_knit = function(engine, code) {
  check_string(engine, "engine")
  src_lines = bridge_chr(code)
  check_strings(src_lines, "code")
  src = as_utf8(paste(src_lines, collapse = "\n"))
  eng = tolower(engine)
  if (eng %in% bridge_knit_shells) {
    res = bridge_exec(c(eng, src), timeout = bridge_knit_timeout(), bridge = "knit",
                      label = eng, level = bridge_level(src, "command"),
                      target = bridge_knit_target(eng, src))
    return(bridge_text(bridge_cmd_lines(res), out_id = res$id))
  }
  if (identical(eng, "python")) {
    py = bridge_py(src)
    return(bridge_text(bridge_py_lines(py), out_id = py$id))
  }
  if (identical(eng, "sql")) {
    con = bridge_find_connection(bridge_caller_env(bridge_knit))
    return(bridge_text(bridge_sql_lines(bridge_sql(src, con = con))))
  }
  interp = bridge_knit_interpreter(engine)
  if (!is.null(interp)) {
    res = bridge_knit_script(interp, engine, src)
    return(bridge_text(bridge_cmd_lines(res), out_id = res$id))
  }
  if (!requireNamespace("knitr", quietly = TRUE)) {
    gptr_abort("gptr$knit() needs the 'knitr' package for this engine.", "missing_package",
               package = "knitr", feature = "gptr$knit()")
  }
  fun = knitr::knit_engines$get(engine)
  if (is.null(fun)) {
    gptr_abort("Unknown knitr engine.", "invalid_argument", arg = "engine",
               expected = "a name in names(knitr::knit_engines$get())")
  }
  opts = knitr::opts_chunk$merge(list(engine = engine, code = strsplit(src, "\n")[[1L]],
                                      label = "gptr-knit", echo = FALSE, results = "asis"))
  t0 = reactor_now()
  out = suppressMessages(fun(opts))
  text = as_utf8(sub("\n+$", "", paste(out, collapse = "\n")))
  lines = if (nzchar(text)) strsplit(text, "\n", fixed = TRUE)[[1L]] else character()
  id = out_put(text, stream = "stdout", meta = list(bridge = "knit", engine = engine),
               session = bridge_out_session())
  bridge_emit(list(bridge = "knit", id = id, cmd = src, level = 3L, status = "ok",
                   seconds = reactor_now() - t0, bytes_out = nchar(text, type = "bytes"),
                   bytes_err = 0L, spill = NULL,
                   digest = paste0("knit ", eng, ": ", length(lines),
                                   if (length(lines) == 1L) " line" else " lines")))
  bridge_text(lines, out_id = id)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 5 | PASS 44 ]` without duckdb and Python (the Python half of "the python and sql engines ..." skips), `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 76 ]` with both.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-lang.R tests/testthat/test-bridge-lang.R
git commit -m 'feat(bridge): gptr$knit() with shell engines on the sh engine and a timeout'
```

### Task 9: `builtin:lang`: member specs, risks and the `languages` fragment

`builtin:lang` registers the members `py`, `sql` and `knit` with the shared `bridge_member()` of Task 5 (exposure `r`, a `fun` with the 04 signature, the nested `execute` with the S-4 refusal and the run-time re-check, `available = FALSE`), their own S-4 `tool_call` hook (`bridge_block_hook()`) and the `<r_session>` fragment `languages` (T0, order 40, IC-68). Risks follow 04 §9.4: `py` the Python classifier, `sql` the SQL classifier (select 0, drop 3), `knit` the command classifier for the shell engines and 3 for every other engine, like `gptr$script()` (IC-67). The declaration `on_load(ext_declare_builtin("lang", builtin_lang))` ends the file.

**Files:**
- Modify: `R/bridge-lang.R` (append)
- Test: `tests/testthat/test-bridge-lang.R` (append)

**Interfaces:**
- Consumes: Task 5 (`bridge_member()`, `bridge_block_hook()`, `bridge_prop()`, `bridge_strings()`, `bridge_any()`), Task 2 (`bridge_risk()`, `bridge_chr()`), Task 8 (`bridge_knit_shells`); `gptr_prompt_section()`, `ext_declare_builtin()`, the factory API's `gptr$on()` (P02); `on_load()` (P01); tests: `gptr_check()`, `registry_get()` (P02), `gptr_risk()` (P11), `gptr_prompt()` (P07), the gateway `gptr` (P08/P10), `local_project()`, `local_fake_provider()`, `fake_tool()`, `fake_text()` (P01).
- Produces: the member specs `py`, `sql`, `knit` (04 §9.4); the prompt section `languages` (`parent = "r_session"`, T0, order 40); `builtin_lang(gptr)` declared as `builtin:lang`; `bridge_risk_py()`, `bridge_risk_sql()`, `bridge_risk_knit()`; `bridge_lang_members()`; `bridge_lang_fragment`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-bridge-lang.R`:

```r
lang_line = "- Other languages: gptr$py(code); gptr$sql(query, name = df); gptr$knit(engine, code)."

test_that("builtin:lang registers py, sql and knit as gptr$ members only", {
  for (nm in c("py", "sql", "knit")) {
    spec = registry_get("tool", nm)
    expect_s3_class(spec, "gptr_tool")
    expect_identical(spec$exposure, "r")
    expect_null(spec$namespace)
    expect_true(is.function(spec$execute))
    expect_false(spec$available(NULL))
    expect_true(all(gptr_check(spec)$ok))
    expect_true(inherits(gptr[[nm]], "gptr_member"))
  }
  expect_identical(names(formals(registry_get("tool", "py")$fun)), c("code", "name", "max_rows"))
  expect_identical(formals(registry_get("tool", "py")$fun)$max_rows, 10L)
  expect_identical(names(formals(registry_get("tool", "sql")$fun)), c("query", "name", "con", "n"))
  expect_identical(formals(registry_get("tool", "sql")$fun)$n, 10L)
  expect_identical(names(formals(registry_get("tool", "knit")$fun)), c("engine", "code"))
  frag = registry_get("prompt_section", "languages")
  expect_identical(frag$text, lang_line)
  expect_identical(frag$parent, "r_session")
  expect_identical(as.integer(frag$order), 40L)
})

test_that("SQL, Python and knit risks follow 04 (acceptance 3)", {
  sql = registry_get("tool", "sql")
  expect_identical(as.integer(sql$risk(list(query = "select * from t"), NULL)$level), 0L)
  expect_identical(as.integer(sql$risk(list(query = "drop table t"), NULL)$level), 3L)
  expect_identical(gptr_risk("gptr$sql(\"select * from t\")")$level, 0L)
  expect_identical(gptr_risk("gptr$sql(\"drop table t\")")$level, 3L)
  expect_gte(registry_get("tool", "py")$risk(list(code = "import subprocess"), NULL)$level, 3L)
  knit = registry_get("tool", "knit")
  expect_identical(as.integer(knit$risk(list(engine = "bash", code = "wc -l data.csv"),
                                        NULL)$level), 0L)
  expect_identical(knit$risk(list(engine = "perl", code = "print 1"), NULL)$level, 3L)
  expect_identical(knit$risk(list(engine = "sql", code = "select 1"), NULL)$level, 3L)
  expect_identical(knit$risk(list(engine = "python", code = "x = 1"), NULL)$level, 3L)
})

test_that("gptr$sql(name = df) labels the table by the expression, at the console and in r", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  big = data.frame(v = seq_len(1000))
  expect_equal(gptr$sql("SELECT COUNT(*) AS n FROM big", name = big)$n, 1000)
  skip_on_cran()
  local_project()
  e = new.env()
  e$orders = data.frame(id = 1:12)
  code = "n = gptr$sql(\"SELECT COUNT(*) AS n FROM orders\", name = orders)$n"
  fake = local_fake_provider(list(fake_tool("r", code = code), fake_text("done")))
  gptr("count the orders", model = fake, envir = e, mode = "auto")
  expect_equal(e$n, 12)
})

test_that("<r_session> carries the shell and languages lines in order", {
  t0 = gptr_prompt(preset = "standard")$system$t0
  at_shell = regexpr("- There is no shell tool.", t0, fixed = TRUE)
  at_lang = regexpr(lang_line, t0, fixed = TRUE)
  expect_gt(at_shell, 0)
  expect_gt(at_lang, at_shell)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: the 44 expectations of Tasks 6-8 still pass (76 with duckdb and Python) and the new tests fail (`FAIL` is 3 or more): `registry_get("tool", "py")` is `NULL`, so `expect_s3_class()` fails and `spec$available(NULL)` errors with `attempt to apply non-function`; `sql$risk(...)` errors the same way; `registry_get("prompt_section", "languages")` is `NULL`; the languages line is not in `<r_session>` (`regexpr()` gives -1). With duckdb the console call `gptr$sql(...)` signals `gptr_error_unknown_member` too.

- [ ] **Step 3: Write the implementation**

Append to `R/bridge-lang.R`:

```r
# ---- builtin:lang --------------------------------------------------------------------------------

#' The <r_session> languages line (architecture 7.3 as amended by IC-68, byte for byte)
#' @noRd
bridge_lang_fragment = paste0(
  "- Other languages: gptr$py(code); gptr$sql(query, name = df); gptr$knit(engine, code)."
)

#' Risk of gptr$py(): the Python token classifier
#' @noRd
bridge_risk_py = function(input, ctx) {
  bridge_risk(paste(bridge_chr(input$code), collapse = "\n"), "python")
}

#' Risk of gptr$sql(): the SQL keyword classifier (select 0, drop 3)
#' @noRd
bridge_risk_sql = function(input, ctx) {
  bridge_risk(paste(bridge_chr(input$query), collapse = "\n"), "sql")
}

#' Risk of gptr$knit(): the command classifier for the shell engines, 3 for every other engine,
#' like gptr$script() (contract 9.4, IC-67)
#' @noRd
bridge_risk_knit = function(input, ctx) {
  eng = tolower(as.character(input$engine %||% "")[1L])
  if (eng %in% bridge_knit_shells) {
    return(bridge_risk(paste(bridge_chr(input$code), collapse = "\n"), "command"))
  }
  list(level = 3L, categories = "process", paths = character())
}

#' The member specs py, sql and knit (contract 9.4)
#' @noRd
bridge_lang_members = function() {
  list(
    bridge_member(
      "py",
      paste("Run Python in reticulate's persistent __main__ (shared with knitr python chunks);",
            "the last expression is shown with pandas output bounded by max_rows, and $value",
            "converts it to R. name = obj (or a named list) makes R objects Python variables."),
      list(code = bridge_strings("Python code (one string or lines)."),
           name = bridge_any("An R object by name, or a named list of objects."),
           max_rows = bridge_prop("integer", "Rows of pandas output (default 10).")),
      "code", bridge_py, bridge_risk_py, "gptr$py(code, name = NULL, max_rows = 10L)"
    ),
    bridge_member(
      "sql",
      paste("Run SQL and return all rows as a data frame that prints its dimensions and the",
            "first n rows. name = df (or a named list of data frames) registers them in an",
            "in-memory duckdb under those names; otherwise con = or the one DBI connection in",
            "scope is used."),
      list(query = bridge_strings("The SQL statement."),
           name = bridge_any("A data frame by name, or a named list of data frames."),
           con = bridge_any("A DBI connection."),
           n = bridge_prop("integer", "Rows to print (default 10).")),
      "query", bridge_sql, bridge_risk_sql, "gptr$sql(query, name = NULL, con = NULL, n = 10L)"
    ),
    bridge_member(
      "knit",
      paste("Run code with a knitr language engine and return its output lines; bash, sh, zsh,",
            "powershell and cmd run through gptr$sh() with its child environment and timeout,",
            "engines with a registered interpreter (Rscript, perl, ruby, node, julia) run as",
            "scripts like gptr$script(), python through gptr$py() and sql through gptr$sql()."),
      list(engine = bridge_prop("string", "A knitr engine name, for example \"perl\"."),
           code = bridge_strings("The code (one string or lines).")),
      c("engine", "code"), bridge_knit, bridge_risk_knit, "gptr$knit(engine, code)"
    )
  )
}

#' builtin:lang (contract 7.22): the members py, sql, knit with their S-4 `tool_call` hook and the
#' <r_session> fragment `languages` (order 40, IC-68)
#' @noRd
builtin_lang = function(gptr) {
  for (spec in bridge_lang_members()) gptr$register(spec)
  gptr$on("tool_call", bridge_block_hook(c("py", "sql", "knit")))
  gptr$register(gptr_prompt_section("languages", bridge_lang_fragment, tier = "T0", order = 40L,
                                    budget = 300L, parent = "r_session"))
  invisible(NULL)
}

on_load(ext_declare_builtin("lang", builtin_lang))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge-lang")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 6 | PASS 84 ]` without duckdb and Python, `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 118 ]` with both.

- [ ] **Step 5: Commit**

```bash
git add R/bridge-lang.R tests/testthat/test-bridge-lang.R
git commit -m "feat(bridge): builtin:lang members py, sql, knit and the languages line"
```

### Task 10: Copy-safety rows (`tests/testthat/test-copy-bridge.R`)

The copy suite of 03 §3.4 and 05 P22 acceptance 4: each row runs in a fresh `Rscript --vanilla` through P01's `expect_no_copy()` (04 §12.2), which loads gptr, runs `setup`, starts `tracemem()` on the object, runs the gptr `action`, then the user's next in-place edit, and counts the copies that edit makes. `gptr$sh()` must cost none: at the console, with a character or raw `input` (the bytes reach the child through a temporary file, Task 2), and from model code inside `r` (the fake provider issues the `r` call; `mode = 'auto'` and `gptr.interactive = FALSE` so no question is asked). `gptr$sql(name = df)` costs exactly the one copy rule R9 documents, and the row must be able to see it: a frame built with `data.frame()` copies its column on the first `big$v[1] = 0` even without gptr (its column is already shared when `data.frame()` returns), which would hide the bridge's copy, so the rows build `big` from a list by setting its `class()` and `row.names` attribute, whose column edit copies nothing. The control row asserts 0 copies without gptr and the `gptr$sql()` row exactly 1: the copy that `duckdb_register()`'s reference causes (measured in a fresh `Rscript --vanilla` with R 4.4.3 and duckdb 1.5.0: 0 without gptr, 0 after passing the frame through a plain closure, 1 after a registration, also after `duckdb_unregister()` and `gc()`). The negative control of the `gptr$sh()` rows keeps a reference (`keep = list(big)`), so exactly one copy is counted, which shows that the zero counts are not vacuous.

**Files:**
- Test: `tests/testthat/test-copy-bridge.R` (create)

**Interfaces:**
- Consumes: `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` (P01 `helper-tracemem.R`; returns the copy count invisibly, skips on CRAN and without `capabilities("profmem")`); the exported `gptr`, `gptr_fake_provider()` inside the child; Tasks 2, 5, 6 and 9 (`gptr$sh()`, `gptr$sql()`).
- Produces: the P22 rows of the copy suite (03 §3.4: `test-copy-bridge.R`).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-copy-bridge.R`:

```r
# Copy-safety rows of P22 (architecture 6.4 rules R1, R3 and R9; contract 1.3 and 12.3). Each row
# runs in a fresh `Rscript --vanilla` through P01's expect_no_copy(), which skips on CRAN and
# without capabilities("profmem"), and counts the copies the user's next in-place edit makes.

rscript_code = paste0("file.path(R.home('bin'), if (.Platform$OS.type == 'windows') ",
                      "'Rscript.exe' else 'Rscript')")

test_that("gptr$sh() at the console leaves a big vector editable in place", {
  action = paste0("res = gptr$sh(c(", rscript_code, ", '--vanilla', '-e', 'invisible(1)'))")
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, label = "gptr$sh()")
  expect_identical(n, 0L)
})

test_that("gptr$sh(input = big) leaves the input vector editable in place", {
  action = paste0("res = gptr$sh(c(", rscript_code, ", '--vanilla', '-e', ",
                  "'invisible(readLines(file(\"stdin\")))'), input = big)")
  n = expect_no_copy(setup = "big = as.character(seq_len(2e5))", action = action,
                     edit = "big[1] = 'a'", label = "gptr$sh(input = big)")
  expect_identical(n, 0L)
})

test_that("gptr$sh(input = <raw>) leaves the raw vector editable in place", {
  action = paste0("res = gptr$sh(c(", rscript_code, ", '--vanilla', '-e', 'invisible(1)'), ",
                  "input = big)")
  n = expect_no_copy(setup = "big = as.raw(rep(65L, 1e6))", action = action,
                     edit = "big[1] = as.raw(66L)", label = "gptr$sh(input = <raw>)")
  expect_identical(n, 0L)
})

test_that("gptr$sh() called from model code leaves a big vector editable in place", {
  code = paste0("res = gptr$sh(c(", rscript_code, ", \"--vanilla\", \"-e\", \"invisible(1)\"))")
  action = paste0(
    "options(gptr.quiet = TRUE, gptr.interactive = FALSE); ",
    "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = ", deparse(code),
    ")), 'done')); s = gptr('run it', model = fake, envir = globalenv(), mode = 'auto')"
  )
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, label = "gptr$sh() in r")
  expect_identical(n, 0L)
})

test_that("a negative control: a reference kept by the action makes the next edit copy", {
  action = paste0("keep = list(big); res = gptr$sh(c(", rscript_code,
                  ", '--vanilla', '-e', 'invisible(1)'))")
  n = expect_no_copy(setup = "big = runif(5e6)", action = action, allow = 1L,
                     label = "negative control")
  expect_identical(n, 1L)
})

test_that("gptr$sql(name = df) costs exactly the one documented copy on the next edit (R9)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  # A frame made by data.frame() copies its column on the first `big$v[1] = 0` even without gptr,
  # which would hide the bridge's copy; this one, built by setting class and row.names on a list,
  # edits in place, so the control counts 0 and the gptr$sql() row exactly the copy that
  # duckdb's registration causes (measured with R 4.4.3 and duckdb 1.5.0: 0 and 1).
  setup = paste("big = list(v = runif(5e6)); class(big) = 'data.frame';",
                "attr(big, 'row.names') = c(NA, -5000000L)")
  control = expect_no_copy(setup = setup, action = "invisible(NULL)", edit = "big$v[1] = 0",
                           object = "big$v", label = "data frame column edit without gptr")
  expect_identical(control, 0L)
  n = expect_no_copy(setup = setup,
                     action = "x = gptr$sql('SELECT count(*) AS n FROM big', name = big)",
                     edit = "big$v[1] = 0", object = "big$v", allow = 1L,
                     label = "gptr$sql(name = big)")
  expect_identical(n, 1L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-bridge")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 10 ]` without duckdb, `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 14 ]` with it. The rows are regression guards over Tasks 2, 5, 6 and 9 and pass at once; the negative control proves they can fail. To see a row fail, temporarily change `allow = 1L` to `allow = 0L` in the negative control: the run reports `negative control: 1 copies of `big` (allowed 0)`; restore `allow = 1L` before Step 4. Without memory profiling (`capabilities("profmem")` is `FALSE`) every row skips.

- [ ] **Step 3: Write the implementation**

No package code changes: the rows measure the code of Tasks 2, 5, 6 and 9. If a `gptr$sh()` row counts a copy, look for a list, closure or `tryCatch()` frame that holds the user's object after the call (rules R1 and R3) in `bridge_sh()`, `bridge_exec()` and `bridge_input()`. One edit copies a vector at most once, so the `gptr$sql()` row cannot tell the registration's reference from a second one held by gptr; it documents the R9 copy (05 acceptance 4) against a control that counts 0. If the control counts a copy, R's data-frame semantics changed and the setup no longer builds an unshared column; if the `gptr$sql()` row counts 0, the frame no longer reaches `duckdb_register()` and R9's note in the documentation is stale.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-bridge")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 10 ]` without duckdb, `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 14 ]` with it.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-copy-bridge.R
git commit -m 'test(bridge): copy-safety rows for gptr$sh() and gptr$sql(name = df)'
```

### Task 11: P22's golden transcript and baseline row (`dev/bench/tokens/`)

IC-73: P22 adds its north-star fixture and baseline row to P07's golden-transcript runner (`dev/bench/tokens/run.R`, a development tool excluded from the build that needs rtiktoken). No north-star example is a polyglot task, so P22's fixture is an NS-1 console turn (02 §1: the interactive session) whose request is G5's task T2 ("a 402-line build log"), done the way the `shell` line of `<r_session>` tells the model: one composed `r` call runs the build through `gptr$sh()` and prints only the exit status, stderr and the last line (G5 variant C). It measures what P22 adds to the token budget: the `shell` and `languages` lines inside the standard prefix and a bridge result of 73 o200k tokens where printing the whole `gptr_cmd` would cost 1,018 and a bash tool about 8,100 (G5 token table, T2). The result text is exactly what the bridge returns for this build (the `gptr_cmd` fields printed by `b$status`, `b$stderr` and the `tail()` call, measured on the scratch build of this plan) followed by P09's state and status lines; `details$bridge` holds the digest P22 emits for it. The runner never runs the scripted code: `scripts/build.R` is written into the fixture's project only so that the session sees the file the prompt names.

**Files:**
- Create: `dev/bench/tokens/fixtures/ns01b-polyglot-build.json`
- Modify: `dev/bench/tokens/baseline.csv` (one row, written by P07's runner with `--update`)

**Interfaces:**
- Consumes (P07, IC-73): `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]` and its fixture format (`id`, `north_star`, `description`, `mode`, `human`, `preset`, `models`, `standins`, `environment`, `files`, `objects`, `facts`, `turns` with `prompt`, `source`, `context`, `steps` of `text` and `calls` (`id`, `name`, `input`, `result`, `details`)); its metrics (`requests`, `prefix`, `input_total`, `output_total`, `image_tokens`, `catalog`, `facts`, `est_prefix`, `est_input_total`) and gates (prefix +2%, input and output totals +5%, requests and image tokens +0, catalog +5%, facts no loss, `gptr_error_token_regression`); the development package rtiktoken.
- Produces: the fixture `ns01b-polyglot-build` and its row in `dev/bench/tokens/baseline.csv` (P24 gates every row).

- [ ] **Step 1: Write the failing test**

Check the development tool first: `Rscript --vanilla -e 'cat(requireNamespace("rtiktoken", quietly = TRUE), "\n")'` must print `TRUE`. If it prints `FALSE`, stop and ask the maintainer to install rtiktoken (CRAN) into their library; do not install it from a plan step (conventions §1).

Create `dev/bench/tokens/fixtures/ns01b-polyglot-build.json`:

```json
{
  "id": "ns01b-polyglot-build",
  "north_star": 1,
  "description": "> run scripts/build.R at the console: standard preset, manual mode, a human present, no bound document; one composed r call runs the 402-line build through gptr$sh() and prints only its status, stderr and last line (G5 task T2, variant C: no shell tool, S-4), then the answer.",
  "mode": "manual",
  "human": true,
  "preset": null,
  "models": [
    "benchmain/benchmain-1"
  ],
  "standins": [
    "artifacts",
    "system1",
    "skills",
    "r_env"
  ],
  "environment": "Date: 2026-09-29\nWorking directory: /Users/me/project (project root)\nFront end: interactive console (RStudio)\nR 4.4.3 on aarch64-apple-darwin20; RAM 24 GB (17 GB free)",
  "files": {
    "AGENTS.md": "# AGENTS.md\n- Style: = for assignment, |> for pipes, snake_case.\n- The pipeline is scripts/build.R; it writes out/.",
    "scripts/build.R": "writeLines(sprintf(\"[step %d/400] processing chunk_%d.parquet ... ok (%d rows/s)\", 1:400, 1:400, 3 * (1:400)))\nmessage(\"WARNING: 3 chunks had missing timestamps\")\nwriteLines(\"== done: 400 chunks, 1,203,300 rows, output in out/\")"
  },
  "objects": {},
  "facts": [],
  "turns": [
    {
      "prompt": "Run scripts/build.R and tell me whether it succeeded and what the warnings were",
      "source": "prompt",
      "context": [],
      "steps": [
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_01",
              "name": "r",
              "input": {
                "code": "b = gptr$sh(c(\"Rscript\", \"scripts/build.R\"))\nb$status\nb$stderr\ntail(strsplit(b$stdout, \"\\n\", fixed = TRUE)[[1]], 1)"
              },
              "result": "[1] 0\n[1] \"WARNING: 3 chunks had missing timestamps\\n\"\n[1] \"== done: 400 chunks, 1,203,300 rows, output in out/\"\n[r] + b <gptr_cmd>\n[status: ok; 4 of 4 top-level expressions completed; 1.9s]",
              "details": {
                "code": "b = gptr$sh(c(\"Rscript\", \"scripts/build.R\"))\nb$status\nb$stderr\ntail(strsplit(b$stdout, \"\\n\", fixed = TRUE)[[1]], 1)",
                "status": "ok",
                "bridge": [
                  "#> sh Rscript scripts/build.R: exit 0, 401 lines, 1 stderr"
                ]
              }
            }
          ]
        },
        {
          "text": "The build succeeded (exit status 0): 400 chunks and 1,203,300 rows were written to out/. The only warning: 3 chunks had missing timestamps. The full log is in `b$stdout`.",
          "calls": []
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: P07's static-prefix table and one results row per fixture (including `ns01b-polyglot-build`) are printed, then the run stops with the `gptr_error_token_regression` message:

```text
Error: Token-efficiency regression:
  ns01b-polyglot-build: no baseline row (run with --update ns01b-polyglot-build)
Execution halted
```

- [ ] **Step 3: Write the implementation**

Record the baseline row with P07's runner:

```bash
Rscript --vanilla dev/bench/tokens/run.R --update ns01b-polyglot-build
```

Expected: the static-prefix and results tables, then `baseline written: ns01b-polyglot-build`. Check the new row of `dev/bench/tokens/baseline.csv` against what the fixture scripts:

- `requests` is 2 (one request before the `r` call, one before the answer);
- `prefix` and `catalog` equal those of the `ns02-mixed-model` row of the same run (the same composition: standard preset, a human, no document, the same stand-ins); with every `<r_session>` fragment registered (P10's `helpers` and `out`, P22's `shell` and `languages`, P19's `subagents`) the prefix is the IC-68 total of 2,750 o200k tokens, and P22's two lines are part of it;
- `output_total` is 99 (the `r` call as the runner counts it, `r` plus the JSON of its input: 53 o200k tokens; the answer: 46);
- `image_tokens` and `facts` are 0;
- `input_total` is twice the prefix plus the message payloads: the first user message (its context blocks and the prompt) in both requests, then the `r` call (53) and its result (73).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: the last line `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`, where `<n>` is the number of files in `dev/bench/tokens/fixtures/`.

- [ ] **Step 5: Commit**

```bash
git add dev/bench/tokens/fixtures/ns01b-polyglot-build.json dev/bench/tokens/baseline.csv
git commit -m "chore(bench): add the polyglot build golden transcript and baseline row"
```

(`dev/bench/tokens/results.csv` is regenerated on every run and is not committed.)

## Plan acceptance

Every acceptance check of 05 P22, including its review amendments, the task and test that prove it, and the command with its expected result. Counts are those of the environment described above the tasks.

| # | Acceptance check (05 P22) | Proved by |
|---|---|---|
| 1 | `Rscript --vanilla -e 'devtools::test(filter = "bridge\|copy-bridge")'` is green (Python, duckdb and knitr engine cases skip when unavailable) | Tasks 1-10: all tests of `test-bridge-sh.R`, `test-bridge-lang.R`, `test-copy-bridge.R` |
| 2a | argv without a shell | Task 1 "argv vectors, simple lines and shell lines resolve differently"; Task 2 "the argv form passes arguments without a shell and decodes UTF-8" |
| 2b | a simple command line run directly and pipelines through the resolved shell | Task 2 "a simple command line runs directly and a pipeline through the shell"; Task 1 "simple command lines split into words and shell syntax does not" |
| 2c | C-locale UTF-8 output correct | Task 2 "output and arguments stay correct UTF-8 in a C locale" (and "the argv form ... decodes UTF-8") |
| 2d | timeout kills the process tree and suggests `gptr$bg` | Task 2 "a timeout kills the process tree and suggests gptr$bg()" (no `sleep` left over: `pgrep` finds none) |
| 2e | a background job's `$wait(until = "ready")` | Task 4 "a background job is read incrementally and waited for until a pattern"; "a job with stdin = TRUE talks over stdin and kill() stops it" |
| 2f | truncation notice `gptr$out(<id>)` returns the full output | Task 2 "long output is cut in the view and gptr$out() returns all of it" (the store `gptr$out()` reads); Task 5 "the members run through the gateway with the contract defaults" (`gptr$out(long$id)` has all 5,000 lines) |
| 2g | the print budget of 1,500 tokens holds with stderr floors | Task 2 "the default print budget of 1,500 tokens holds with the stderr floors" |
| 3a | `gptr$sh("rm -rf data")` is level 3, `gptr$sh(c("git", "status"))` level 0 | Task 5 "member risks follow the command classifier; script and bg are at least 3" and "r code calling gptr$sh() is classified by the command it runs (acceptance 3)" |
| 3b | `gptr$sql("select ...")` level 0 and `drop table` level 3 | Task 9 "SQL, Python and knit risks follow 04 (acceptance 3)" (member risk and `gptr_risk()` of the R call) |
| 3c | computed commands are re-checked at run time | Task 5 "computed commands are re-checked at run time with the actual command" (a level-4 command computed in the model code is denied, a level-0 one runs) |
| 4 | the copy row documents exactly one copy after `gptr$sql(name = df)` (duckdb registration) and none for `gptr$sh()` | Task 10, all rows: the `gptr$sh()` rows count 0 against a negative control that counts 1; the `gptr$sql()` row counts exactly 1 against a control without gptr that counts 0 |
| 5a | `gptr$knit("bash", "sleep 999")` times out and kills the process, and its environment lacks a registered fake key | Task 8 "shell engines run through gptr$sh() without registered keys and with a timeout" |
| 5b | `-builtin:bridges` removes the shell line from `<r_session>` | Task 5 "-builtin:bridges removes the shell line from <r_session> and the members" |
| 5c | P22's NS fixtures are added to `dev/bench/tokens/` (IC-73) | Task 11 |
| RA-1 | the shell and languages `r_session` fragments (IC-68) | Task 5 "the shell line of <r_session> is registered byte for byte"; Task 9 "builtin:lang registers py, sql and knit as gptr$ members only" and "<r_session> carries the shell and languages lines in order" |
| RA-2 | bridge children through `proc_spawn()` with `encoding = "UTF-8"`, the complete `helper` environment and non-blocking stdin (IC-60) | Task 2 (every child through `proc_run()`/`proc_spawn()` with `child_env("helper")`; the C-locale test); Task 8 (`TERM=dumb` and no registered key in the child's `env` for the shell engines; no registered key and a timeout for the interpreter engines, "interpreter engines run as scripts without registered keys and with a timeout"); Task 4 "a job with stdin = TRUE talks over stdin ..." (`write_all()`) |
| RA-3 | the pool cap of 2 under check (IC-60) | Task 4 "at most two jobs run at once under R CMD check (IC-60)" |

Commands and expected results:

```bash
Rscript --vanilla -e 'devtools::test(filter = "bridge|copy-bridge")'
```

Expected without duckdb and a configured Python: `[ FAIL 0 | WARN 0 | SKIP 7 | PASS 364 ]` (`test-bridge-sh.R` 270; `test-bridge-lang.R` 84 with 6 skips: two duckdb tests, two Python tests, the Python half of the knit engines test and the console/model `gptr$sql(name =)` test; `test-copy-bridge.R` 10 with the `gptr$sql()` row skipped). With duckdb installed and `RETICULATE_PYTHON` set to a Python with pandas: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 402 ]`.

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: the last line `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances` (acceptance 5c).

```bash
Rscript --vanilla -e 'devtools::test(filter = "lint-rules|arch-layers")'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); mine = lints[grepl("(^|/)(bridge-(sh|lang)|test-(bridge-(sh|lang)|copy-bridge))[.]R$", vapply(lints, function(l) l$filename, ""))]; print(mine); stopifnot(length(mine) == 0L)'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with P01's counts: `test-lint-rules.R` finds no left arrow, `:::`, `withr::`, `processx::run(`, `Sys.setenv(`, `readLines()` without `encoding = "UTF-8"` or non-ASCII byte in `R/bridge-sh.R` and `R/bridge-lang.R`, and `test-arch-layers.R` finds no call from the `bridge` area outside L0, its own area, the declared service `risk.classify` and the kernel SDK (`run_current()`, `run_eval_env()`, `run_emit()`, `session_live()`, `perm_check()`); the lint gate prints `No lints found.` for P22's files (`R/bridge-sh.R`, `R/bridge-lang.R`, `tests/testthat/test-bridge-sh.R`, `test-bridge-lang.R`, `test-copy-bridge.R`) and the script exits 0. The gate lints the whole package with P01's `.lintr` (namespace loaded first, as in P01 A3) but keeps only the lints whose file is one of these five: `lint_package()` also lints `tests/` and `inst/` files of other plans (P12's `fixtures/sse/` scripts, P18's `fixtures/mcp/` servers, P20's `inst/gptr/fixtures/fake_cli.R`), which P22 may not edit, so a lint there is the owning plan's acceptance, not P22's. A lint in any of the five files stops the script with `Error: length(mine) == 0L is not TRUE`.

## Self-review

**Spec coverage (05 P22 scope -> task).**

| Scope item (05 P22, 04 §7.22, §9.4) | Task |
|---|---|
| `bridge-sh.R`: `gptr$sh` (argv, direct, resolved shell; UTF-8; stdin; merge; check; timeout with tree kill) | 1, 2 |
| `gptr$script` with the `interpreter` kind registered through `kind` and the built-in interpreters (`.sh`, `.py`, `.R`, `.js`, `.pl`, `.rb`, `.jl`) | 3 |
| `gptr$bg`, `gptr$jobs` on the process engine (`gptr$out` is P10's, IC-36) | 4 |
| budgeted head+tail prints (1,500 tokens, 0.6 x the `r` budget inside `r`, stderr 25% with 200/100 floors) | 1, 2 (`gptr_cmd`), 4 (job reads), 6 (`gptr_sql`), 7 (`gptr_py`), 8 (knit output) |
| `bridge_call` events and `#>` digests | 2 (`bridge_emit()`), 3, 4, 6, 7, 8; collected into `details$bridge` (Task 5 test) |
| `builtin:bridges` | 3 (first version), 5 (final) |
| `bridge-lang.R`: `gptr$py` with reticulate's persistent `__main__` and the uv-provisioning guard | 7 |
| `gptr$sql` with duckdb registration or the DBI connection in scope | 6 |
| `gptr$knit` for other engines; shell engines through `gptr$sh()` with the `helper` environment and a timeout (IC-67); engines with a registered interpreter as scripts through the same engine (IC-60) | 8 |
| `builtin:lang` | 9 |
| the shell and languages `r_session` fragments (IC-68) | 5, 9 |
| bridge children through `proc_spawn()` with `encoding = "UTF-8"`, the complete `helper` environment and non-blocking stdin (IC-60) | 2, 4, 8 |
| the pool cap of 2 under check (IC-60) | 4 |
| `test-copy-bridge.R` | 10 |
| NS fixtures in `dev/bench/tokens/` (IC-73) | 11 |

Every acceptance check of 05 P22 maps to a task and test in "Plan acceptance" above.

**Placeholder scan.** The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task" and "write tests for the above": none occur. Every step that changes code shows the complete code: whole new files (Tasks 1, 6, 10, 11), whole appended sections (Tasks 2, 3, 7, 8, 9), one inserted section (Task 4) and one replaced section (Task 5, which replaces exactly the `builtin:bridges` section Task 3 appended). Task 10 changes no package code by design (regression rows over earlier tasks) and says what to inspect if a row fails. Task 11's baseline row is written by P07's runner; the plan states the values the row must hold (requests 2, `output_total` 99, `image_tokens` and `facts` 0, `prefix` and `catalog` equal to `ns02-mixed-model`'s) and how `input_total` is composed.

**Type and name consistency with 04.** Member signatures, defaults and returns are those of 04 §9.4 (the `fun` formals are asserted in Tasks 5 and 9); member risks follow §9.4; the result classes have exactly the §5.10 fields (`names(unclass())` is asserted for `gptr_cmd` and `gptr_py`; extra information travels as attributes); the `gptr_job` environment has `id`, `cmd`, `name`, `pid` and the five closures with the §5.10 formals; the kind `interpreter` has the §10.2 row 6 fields, resolve `first` and is experimental; the built-ins are `builtin:bridges` and `builtin:lang` (§10.3); the event is `bridge_call` with the §10.4 payload fields; option names are `gptr.helper_output_tokens` and `gptr.r_output_tokens` (§3.1); condition classes and fields are those of §2.2 listed in the Global Constraints. Every function the code calls is defined in this plan, in 04 for an earlier plan, or in an earlier plan's file of the allowed layers (L0 `utils`, `ext`, `proc`, `http`, `auth`; the kernel SDK): P01 `est_tokens_each()`, `truncation_notice()`; P04 `proc_input_file()`, `proc_read_text()`, `proc_pool_cap()`, `shell_ps_encode()`; P03 `vault_reset()` (tests only). Their definitions were read in the dependency plans (P01 `utils-tokens.R`, `utils-text.R`; P04 `proc-spawn.R`, `proc-supervise.R`; P03 `auth-secrets.R`) on 2026-10-01.

**Contract ambiguities and dependency-plan deviations (04 followed where it speaks).**

1. Run fields. 04 §7.6 lists the run fields other plans may read (`id`, `session`, `status`, `turn`, `mode`, `model`, `depth`, `parent_run`, `opts`, `signal`, `started`, `children`). P22 also reads two bindings P06 creates: `run$tool_call` (the call record of the executing tool, 04 §4.4 shape plus `approved_level`; needed for the S-4 refusal and the run-time re-check of acceptance 3, because a member's `execute(input, ctx)` receives neither the outer call nor its approved level) and `run$shell` (the session object; needed for the per-session `gptr$out()` store of IC-71, since `session_live()` takes a session, not an id). P10 reaches the session through its own r-call marker, which the `bridge` area may not call (03 §2.2).
2. Digest prefix. 04 §10.4 names the payload field `digest` without its format; 04 §4.4 shows `details$bridge` entries as `#> sh git status --porcelain: exit 0, 6 lines`, and P10 copies `event$digest` into `details$bridge` verbatim (its test uses a `#> ` digest), so P22's digests carry the `#> ` prefix. P15 accepts digests with or without it.
3. Record shapes. 04 §5.10 fixes the fields of `gptr_cmd` and `gptr_py`; G5's prototypes carried more. P22 keeps exactly the 04 fields and stores the print budget and resolution route of a `gptr_cmd` (`max_tokens`, `via`) and the error, kind, out id and Python object of a `gptr_py` (`error`, `kind`, `id`, `py`) as attributes; `$.gptr_py` exposes `$value`, `$error`, `$kind`, `$id`.
4. Knit risk. 04 §9.4 says `knit` is "3 (shell engines: the command classifier)" and IC-67 "classifies the others like `gptr$script()`". P11's static classifier (`risk_member_flags()`) classifies `gptr$knit("python"/"sql", ...)` with its Python and SQL classifiers. P22's member risk follows 04 (3 for every non-shell engine); the run-time re-check may therefore ask once more for a knit Python or SQL chunk that P11 listed lower.
5. `bg` and `script` risks. 04 §9.4 gives both level 3. P11 lists `gptr$bg(<literal command>)` at the command's level (at least 1) and reads `.sh` scripts line by line. P22's member risks follow 04 (`bg` at least 3, `script` 3), so in `manual` mode such a call approved at a lower level is asked once more by the re-check.
6. Print cap inside `r`. 04 §9.4 says "at most 0.6x the remaining `r` budget"; P22 uses 0.6 x `gptr.r_output_tokens`, the rule of P10's `member_budget()`, and detects "inside a run" with `run_current()` (kernel SDK) rather than P10's r-call marker.
7. Fragment names. 04 fixes the fragment texts (03 §7.3) but not their spec names or orders; P22 uses P07's stand-in names and orders (`shell` 30, `languages` 40), so P07's dev runner stops registering stand-ins once the real fragments exist.
8. `gptr$jobs()` columns are not fixed by 04 ("df of `bg` jobs"): `id`, `name`, `pid`, `status`, `seconds`, `cmd`. `gptr$sql()` returns a data frame of class `c("gptr_sql", "data.frame")`; a statement that returns no rows gives `data.frame(rows_affected = k)` and prints `# k rows affected`.
9. `gptr$sh()` arguments beyond 04's types: `input` accepts character lines, a data frame (CSV) or raw bytes, and `env` sets named values and passes through unnamed variable names (P03's `child_env(pass =)`), as in G5. G5's options (`gptr.sh_timeout`, `gptr.output_tokens`, `gptr.max_jobs`, `gptr.py_managed`) and its `shell`, `echo` and `python` arguments are not adopted: 04 lists none of them.
10. A direct `sh` tool call is blocked by the built-ins' `tool_call` hooks (a decision event P06 emits before its permission check, so a human is never asked to approve a shell tool and no checkpoint is taken); the model reads P06's `Tool execution was blocked: <reason>`. The `execute` refusal behind it signals `gptr_error_not_available` (`member`, `provided_by = "the r tool"`); 04 has no class for "this member is not a tool", and the model sees only the message. The run-time re-check denial is `gptr_error_permission` with the §2.2 fields; P06's `dispatch_nested()` turns it into an error result and a `gptr_error_tool` in the model's code.
11. `interpreter` specs without `args` get the default `function(path, args) c(path, args)` from the validator (04 lists `args` as a field without saying whether it is required).
12. The job process table `bridge_state` is a namespace environment, not a field of `the` (04 §7.0 lists no P22 field); 03 §2.2 rule 5 allows job process tables, and P04's job table holds the rows `gptr_jobs()` lists and its unload cleanup stops.
13. The `python` and `sql` knit engines run through `gptr$py()` and `gptr$sql()` (G5's routing; 04 names only the shell engines): knitr's own Python engine would let reticulate provision a managed Python without the guard. Engines that name a registered interpreter (`Rscript`, `R`, `perl`, `ruby`, `node`, `js`, `julia`, `python3`) run as a temporary script through the `gptr$sh()` engine (Task 8): IC-67 asks only that the other engines be classified like `gptr$script()`, but knitr's `system2()`-based engines would give the child the session's complete environment, registered keys included, and no timeout, which IC-60 rules out for bridge children (verified in the review: knitr's `Rscript` engine printed a registered fake key and ran a `Sys.sleep(30)` chunk to the end). Only engines without an interpreter record (knitr's `cat`, `verbatim`, user-registered engines, programs gptr has no interpreter for) still run through knitr; a user who needs such a program sandboxed registers an `interpreter` record for it. `gptr$knit("js", code)` therefore runs node rather than knitr's `<script>` wrapper, and `gptr$knit("R", code)` a separate Rscript.
14. No north-star example is a polyglot task; the IC-73 fixture is an NS-1 console turn running G5's task T2 (`ns01b-polyglot-build`), on the pattern of P10's `ns02b-data-first-pipe`.
15. Copy row for `gptr$sql(name = df)`: in R 4.4.3 the first column edit `big$v[1] = 0` of a frame made by `data.frame()` copies the column even without gptr, so a row built on such a frame counts 1 whatever the bridge does. The rows build `big` from a list by setting its `class()` and `row.names` attribute, whose edit copies nothing (the control asserts 0), so the `gptr$sql()` row's exactly 1 is the copy `duckdb_register()`'s reference causes (R9, 05 acceptance 4). One edit copies a vector at most once, so no row can tell that copy from a second reference held by gptr; the `gptr$sh()` rows (0 against a negative control of 1) cover gptr's own references.
16. P22 consumes nothing from P18, P19 or P20. P19's `builtin:subagents` registers the fifth `<r_session>` fragment (`subagents`, order 50) that the IC-68 total of 2,750 includes; Task 11 compares its prefix with `ns02-mixed-model` of the same run, so the check holds whichever fragments are loaded.

**Executed validation (scratch, 2026-10-01; author, before the review).** The counts and the `gptr$sql()` copy row below describe the plan as first written; the review paragraph that follows supersedes them. Every `r` block of this plan was extracted and parsed (`parse(file =)`: 20 blocks, 0 errors); `getParseData()` finds no left-arrow assignment and no `%>%` in any block; the R sources and tests are ASCII. The R code of Tasks 1-9 was assembled into a scratch package with a shim holding verbatim copies of the P01 and P04 functions it calls (`utils-text.R`, `utils-tokens.R`, `utils-encoding.R`, conditions and checkers; `proc_run()`, `proc_spawn()`, `proc_input_file()`, `proc_read_text()`, `shell_resolve()`, `shell_ps_encode()`, `kill_all()`, `job_add()`, `proc_pool_cap()`) and small stand-ins for P02 (registry, specs, hooks), P03 (`child_env("helper")`), P06 (`run_current()`) and P11 (`risk.classify`): the tests of Tasks 1-4 and 6-8 pass (`[ FAIL 0 | WARN 0 | SKIP 5 | PASS 206 ]` without duckdb and Python; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 238 ]` with duckdb 1.5 and `RETICULATE_PYTHON` set to Python 3.14 with pandas 3.0.1), and the red and green counts stated in Tasks 1, 2, 4, 6, 7 and 8 were reproduced phase by phase. The member specs, risks, fragment texts and the nested `execute` path were checked against the shim registry (formals equal to 04 §9.4; `available()` is `FALSE`; knit Python and SQL risks are 3). The copy rows were measured in fresh `Rscript --vanilla` processes with `tracemem()`: `gptr$sh()` at the console 0, with a character `input` 0, with a raw `input` 0, `gptr$script(input =)` 0, `gptr$sql(name = big)` 1 (equal to the control without gptr, 1), the negative control 1. `lintr::lint()` with the repository `.lintr` reports nothing for the two R files and three test files apart from `object_usage_linter` notes that only appear when a single file is linted outside the package; P01's `lint_scan()` (copied from the P01 plan) finds no hit in the two R files; and an inventory of every function the two R files call outside their own definitions lists only base R, the Imports and Suggests named in the Tech Stack, P01-P04 L0 helpers and the kernel SDK (`run_current()`, `run_eval_env()`, `run_emit()`, `session_live()`, `perm_check()`). The Task 11 fixture was generated and parsed with jsonlite; the bridge produced the scripted result text and digest (`#> sh Rscript scripts/build.R: exit 0, 401 lines, 1 stderr`) for the fixture's build script, and rtiktoken o200k counts give the stated 53 + 46 = 99 output tokens and 73 tokens of result (1,018 for the full `gptr_cmd` print). Not executed: the tests that need the real kernel (Task 5 and Task 9 registration through P02's loader, the gateway runs of P06/P08/P10, P07's `gptr_prompt()`, P11's classifier, the copy row from model code) and P07's runner of Task 11; they were checked by reading the consumed functions in the P02, P06, P07, P10 and P11 plans. The Windows branches (Git Bash, PowerShell, `cmd`, batch shims) are unexecuted, as in G5.

**Executed validation (review, 2026-10-01).** The reviewer re-extracted every `r` block of the revised plan (20 blocks, 0 parse errors; no `LEFT_ASSIGN` token, no `%>%`, no non-ASCII byte in any block), rebuilt the author's scratch shim package from those blocks (Tasks 1-4 with Task 3's first `builtin_bridges()`, Tasks 6-8) and ran its tests: `[ FAIL 0 | WARN 0 | SKIP 5 | PASS 220 ]` with the maintainer's library (no duckdb, no configured Python; `test-bridge-sh.R` 176, `test-bridge-lang.R` 44) and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 252 ]` with duckdb 1.5.0 and `RETICULATE_PYTHON=/opt/homebrew/bin/python3` (pandas 3.0.1; `test-bridge-lang.R` 76); the per-task counts stated in Tasks 1-4 and 6-9 and in Plan acceptance follow from these per-test counts (Task 5 adds 94 expectations, Task 9 adds 40, or 42 with duckdb). Red phases of the review's new tests were run against the original code: `bridge_chr(list())`, `wait(until =)` on a partial line and the spill of a 200-line output cut at `max_tokens = 120` fail (one failure or error each), the interpreter-engine test fails 5 expectations (knitr's `Rscript` engine printed the registered fake key and the `Sys.sleep(30)` chunk ran to the end). With the final `builtin_bridges()` and `builtin_lang()` in the shim, every member spec has an `execute`, exposure `r`, `available()` `FALSE` and the 04 §9.4 formals, and the copy rows measured through the shim's gateway in fresh `Rscript --vanilla` processes give: `gptr$sh()` at the console 0, with a character `input` 0, with a raw `input` 0, the negative control 1, the `gptr$sql()` control (frame built by setting `class()` on a list) 0, `gptr$sql(name = big)` 1, and a `data.frame()`-built control 1 (why the original row could not fail). rtiktoken 0.0.7 confirms the Task 11 fixture's 53 (the `r` call), 46 (the answer) and 73 (the result) o200k tokens.

## Plan review log

Adversarial review of 2026-10-01 against `dev/plan/00-conventions.md`, 04 (§5.10, §9.1, §9.4, §10.2-§10.5, §12, §15 IC-36, IC-37, IC-60, IC-67, IC-68, IC-70, IC-71, IC-73), 05 P22, the dependency plans P01-P04, P06, P07, P10, P11 and G5's verification log. Every `r` block was re-extracted and parsed; the code of Tasks 1-9 was rebuilt into the author's scratch shim and its tests and copy rows were run (Self-review, "Executed validation (review)").

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 10, `gptr$sql(name = df)` copy row; Self-review 15 | The row could not fail: a frame made by `data.frame()` copies its column on the first `big$v[1] = 0` even without gptr (measured: control 1), so the row counted 1 whatever the bridge held, and the claim "the test asserts that `gptr$sql()` adds none" was false. | applied | The rows build `big` by setting `class()` and `row.names` on a list (measured: 0 copies without gptr, 0 through a plain closure, 1 after `duckdb_register()`); the control asserts exactly 0 and the `gptr$sql()` row exactly 1. Task 10 text, Step 3 diagnosis, acceptance row 4 and Self-review 15 explain what the row can and cannot show. |
| 2 | major | Task 8 `bridge_knit()`; Global Constraints; Task 9 knit description | Non-shell interpreter engines (`Rscript`, `perl`, `ruby`, `node`, `julia`) ran through knitr's `system2()` with no timeout and the session's complete environment: a chunk could read a registered key that the secret guard stops in `r` (reproduced: knitr's `Rscript` engine printed the fake key, and a `Sys.sleep(30)` chunk ran to the end). This contradicts IC-60 ("bridge children through `proc_spawn()` ... the complete `helper` environment"). | applied | New `bridge_knit_interpreter()` and `bridge_knit_script()`: an engine that names a registered interpreter runs as a temporary script through `bridge_exec()` (helper environment, `bridge_knit_timeout()`); only engines without an interpreter record still go to knitr. New test "interpreter engines run as scripts without registered keys and with a timeout" (red on the old code: 5 failures); the knitr fallback is tested with a user-registered engine. Self-review 13 records the choice. |
| 3 | minor | Task 5 S-4 refusal; Task 9 `builtin_lang()` | A direct `sh` tool call reached P06's permission check and checkpoints before the `execute` refused it, so in `manual` mode a person was asked to approve a shell tool that does not exist (and a non-interactive manual run stopped as `blocked`). | applied | `bridge_block_hook(names)`: a `tool_call` hook (decision event, 04 §10.4) registered with `gptr$on()` by each built-in blocks top-level calls of its members before the permission check; the `execute` refusal stays as a second line. New unit test; the direct-call test now runs in `manual` mode and asserts the session ends `idle`. Self-review 10 updated. |
| 4 | minor | Task 2 `bridge_exec()` spill | Output was spilled only above `gptr.helper_output_tokens`, but a view cut at a smaller `max_tokens` (or the in-run budget) still printed `all: gptr$out("<id>")`; once the session store (`gptr.out_keep` = 20) dropped the entry that id returned nothing. | applied | Spill threshold is `min(helper budget, bridge_budget(max_tokens))`; the "long output" test asserts a spill file for a 200-line output cut at `max_tokens = 120` (red on the old code). |
| 5 | minor | Task 1 `bridge_chr()` | P01's schema validation turns `character()` given for an `array` property into `list()`, which `bridge_chr()` returned unchanged, so `gptr$script(path, args = character())` from model code failed `check_strings()`. | applied | An empty list becomes `character()`; test added (red on the old code). |
| 6 | minor | Task 4 `bridge_job_wait()` | `until` matched new bytes including a partial last line, while `read()` holds partial lines back, so `wait(until =)` could return without the matching line. | applied | `until` is matched against complete lines only; new test "wait(until =) returns once the matching line is complete" (red on the old code). |
| 7 | minor | Task 6 `bridge_sql()` | `con` was never validated (04 §9.4: members validate with the §1.1 checkers); a non-DBI `con` failed inside DBI with an unclassed error. | applied | `methods::is(con, "DBIConnection")` check with `gptr_error_invalid_argument`; test expectation added. |
| 8 | minor | Task 10 `rscript_code` | The child scripts named `file.path(R.home('bin'), 'Rscript')`, which does not exist on Windows (`Rscript.exe`), so the rows would fail there. | applied | The path adds `.exe` on Windows. |
| 9 | minor | Global Constraints | Conventions §10's commit attribution line was not stated among the plan's constraints. | applied | One line added. |
| 10 | minor | Self-review 16; Executed validation; every task's expected counts | Self-review 16 said P18-P20 did not exist; the author's validation counts and the per-task `PASS` numbers no longer matched the revised tests. | applied | Item 16 rewritten (P19 registers the `subagents` fragment the 2,750 total includes); the author's paragraph is marked pre-review and a review paragraph records the re-run; every Step 2/Step 4 count and the Plan acceptance totals (364 without duckdb and Python, 402 with both) were recomputed from the shim's per-test counts. |
| 11 | minor | Task 1 `bridge_budget()` | 04 §9.4 caps member prints at 0.6x the *remaining* `r` budget; P22 uses 0.6 x `gptr.r_output_tokens`. | rejected | The remaining budget lives in P10's r-call marker (`member_budget()`, `tool-namespace.R`), which the L4 `bridge` area may not call (03 §2.2, IC-33); already recorded as ambiguity 6, and P09 cuts the whole `r` result to `gptr.r_output_tokens` anyway. |
| 12 | minor | Task 2 `bridge_exec()` record | The `gptr_cmd` keeps the caller's `cmd` vector (rule R1). | rejected | Command vectors are a few strings, and `paste()`/`bridge_label()` on them already mark them shared, so a copy of the record's own vector would change nothing measurable; large user objects (`input`) never enter the record (copy rows: 0). |
| 13 | minor | Tasks 5 and 9, Step 2 | The red-phase counts read "`FAIL` is 8 (3) or more" instead of an exact summary. | rejected | They depend on the real kernel (P02 loader, P06 dispatch, P07, P10, P11), which no scratch shim reproduces; the steps name each expected failure message, which is what the red phase checks. |
| 14 | minor | Tasks 2 and 5 (`run$shell`, `run$tool_call$approved_level`) | Both are P06 run bindings outside 04 §7.6's list of readable run fields. | rejected | Already recorded as ambiguity 1: P06 binds both (its own `run_emit()` reads `run$shell`), the S-4 refusal and the acceptance-3 re-check need them, and the kernel SDK offers no alternative. |
| 15 | minor | Task 4 job tables | Finished `gptr$bg()` jobs stay in `bridge_state$jobs` and P04's job table for the session. | rejected | 04 fixes no retention for `bg` rows (P04 keeps every row too); `gptr$jobs()` and `gptr_jobs()` show their final status, which is what the model reads, and the raw output files live in `tempdir()` (IC-70). |

## Cross-plan consolidation log

Consolidation of 2026-10-01 against 04, 05 P22 (whose acceptance names no package-wide lint gate), `dev/plan/00-conventions.md` and the plans named below. Checked in scratch (`work/consolidate/P22-lint`): a package with P01's current `.lintr` (which already excludes `tests/testthat/fixtures/docs`, so P15's BOM/CRLF fixtures no longer lint), P22's five file names and copies of P18's `fixtures/mcp/server.R` head (`%||%` and `TOOLS = tool_defs()` without `# nolint`) and P20's `inst/gptr/fixtures/fake_cli.R` head gave 3 `object_name_linter` lints from the old command (exit 1, none in a P22 file) and `No lints found.`, exit 0, from the new one; a `<-` appended to each of the five P22 files was reported by the new command for all five, which then stopped with `Error: length(mine) == 0L is not TRUE`; with no lint anywhere it printed `No lints found.` and exited 0. Every `r` block of the plan was re-extracted and parsed after the change with `Rscript --vanilla` (20 blocks, 0 parse errors, no `LEFT_ASSIGN` or `%>%` token, no non-ASCII byte; no `r` block changed), and the R expression of the new lint command parses.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| X1 | ownership | major | Plan acceptance, second lint command (`lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)`) and its expectation | applied | Valid in part, measured: P01's `.lintr` now carries `exclusions: list("tests/testthat/fixtures/docs")`, so P15's `crlf-bom.R` fixtures no longer lint, but `lint_package()` still lints `tests/` and `inst/` files of other plans that P22 may not edit (P18 `fixtures/mcp/oauth.R` and `server.R`, P20 `inst/gptr/fixtures/fake_cli.R`: `%||%` and `TOOLS` give `object_name_linter` lints; P12 and P18 fixture scripts as reported), so the whole-package gate could fail for reasons outside P22. 05 P22's acceptance asks for no package-wide lint. The command now keeps only lints of P22's five files: `mine = lints[grepl("(^\|/)(bridge-(sh\|lang)\|test-(bridge-(sh\|lang)\|copy-bridge))[.]R$", vapply(lints, function(l) l$filename, ""))]; print(mine); stopifnot(length(mine) == 0L)` (an anchored pattern instead of the suggested bare `"bridge"`, so a later file of another plan whose name contains `bridge` is not pulled in). The expectation reads: the lint gate prints `No lints found.` for P22's files and the script exits 0, with the reason for the scope. No test, code or count changed. |
