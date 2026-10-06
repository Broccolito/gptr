# P14 Console and Front Ends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `peter()` its interactive face (REQ-16, REQ-38): a REPL with slash commands, `!expr` passthrough and a Ctrl-C pause menu that steers, queues, continues, aborts or backgrounds a run, plus event-driven front ends (a streaming markdown renderer and a JSONL event sink, INFRA-27).

**Architecture:** Five layer-L5 files in area `console` (architecture section 3.2). `console-render.R` turns events into console output through process-wide notify hooks that render only foreground sessions (a chunk-invariant markdown stream renderer, tool lines, a status line, a spinner ticked from the reactor); `console-interrupt.R` is the `console.interrupt_policy` service every blocking gptr call runs under; `console-repl.R` is `builtin:console` (the `console` frontend and route, the REPL, the `user_ran` and `user_files` context blocks); `console-commands.R` holds the slash commands as `command` specs; `console-jsonl.R` is `builtin:jsonl` (the JSONL sink and the `jsonl` frontend). Every REPL prompt is an ordinary gateway call, `gptr::peter(<session>, <@objects>, prompt = "...", envir = <env>, .opts = list(max_turns = ...))`, so routing, documents (P15 transcripts), budgets and the interrupt policy are exactly those of a typed call.

**Tech Stack:** base R (>= 4.2.0); cli (`num_ansi_colors()`, `is_dynamic_tty()`, `is_utf8_output()`, `console_width()`, `code_highlight()`, `ansi_strtrim()`, `col_*()`); jsonlite through P01's `json_encode()`; testthat 3e, withr and processx in tests; P01's fake provider, mock server and helpers, P11's `local_scripted_ui()`.

**Spec:** dev/spec/03-architecture.md (sections 2.2, 2.3, 3.2, 6.2, 6.4, 6.5, 6.9.3, 6.17, 10.1, 12.2), dev/spec/04-interface-contract.md (sections 1.4, 1.5, 2.1-2.2, 3.1, 4.1-4.2, 4.5, 5.1, 6.1, 6.5, 7.0, 7.1, 7.2, 7.6, 7.8, 7.9, 7.11, 7.14, 9.1, 10.2 kinds 10, 11, 13, 23, 24, 31, 35, 10.3, 10.4, 10.6, 10.7, 11.2, 11.5, 12.1-12.3; section 15: IC-33, IC-34, IC-43, IC-44, IC-49, IC-53, IC-55, IC-57, IC-59, IC-69, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P14).

**Depends on:** P08, P11 (and through them P01-P07, P09, P10). The INFRA-03 test of Task 7 also uses P12's `anthropic-messages` adapter, which is in the package by milestone M3. **Milestone:** M3.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only for closure state), the native `|>` (never `%>%`), ASCII-only R sources (non-ASCII as `\u` escapes), `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions, no `:::` in `R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed option restored with `on.exit(..., add = TRUE)` placed right after the change, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line the executing harness specifies. Plan-specific requirements, copied from the specification:

- Owned files (05 P14): `R/console-repl.R`, `R/console-render.R`, `R/console-interrupt.R`, `R/console-commands.R`, `R/console-jsonl.R` and one test file each: `tests/testthat/test-console-repl.R`, `test-console-render.R`, `test-console-interrupt.R`, `test-console-commands.R`, `test-console-jsonl.R`; plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`. P14 has **no exports** (04 section 14.1); its one roxygen page section is merged into `?peter` (Task 7).
- Layer (03 section 2.2, 3.2): the five files are L5. They call L0 functions, L5 functions (including P11's `console-ui.R`: `ui_escape()`, `ui_permission_lines()`, `ui_permission_detail()`, `ui_parse_choice()`, `ui_questions_via()`, `ui_can_remember()`), the kernel SDK of IC-33 (`session_data()`, `session_live()`, `session_home()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`, `run_abort()`, `run_current()`, `interpolate_prompt()`, `describe_binding()`, `eval_r()` (the fallback of the `eval.r` service, which 04 section 7.0 names for P14's `!expr`), `format_eval_result()`, `rule_parse()`, `setting_get()`), the SDK verbs of `gptr-sdk.R` (`gptr_wait()`), the services of 04 section 7.0, and registry lookups. Exported functions of earlier plans that live in other layers (`peter()`, `gptr_last()`, `gptr_usage()`, `gptr_sessions()`, `gptr_resume()`, `gptr_fork()`, `gptr_permissions()`) are called as `gptr::<name>()`, the way a user calls them (03 section 2.2: "L5 (`console`) | SDK verbs, ..."); exports of later plans (`gptr_doc()` P15, `gptr_rewind()` P16, `gptr_skills()` P17, `gptr_mcp()` P18) are reached through P01's documented late binding `ns_fun("<name>")` with a "not available" answer while absent.
- Contract signatures (04 section 7.14), exactly: `builtin_console(gptr)`; `console_run(s, envir, stdin = FALSE)` ("the REPL of 18 section 4.3 on `s` (a new session when `NULL`); returns `s` invisibly on `/exit`"); `with_interrupt_policy(expr_fun, runs, mode = c("call", "repl"))` (service `console.interrupt_policy` = `function(expr_fun, runs, mode = c("call", "repl")) value`, provided by P14, owned by `builtin:console`); `render_markdown_stream(width = cli::console_width())` ("environment with `write(delta)`, `finish()`, `reset_line()`; chunk-invariant; untrusted text never used as a format string"); `builtin_jsonl(gptr)`; `jsonl_sink(session, con)` ("subscribes to the session's events and writes one redacted JSON object per line in the section 4.5 JSON form (event names verbatim)").
- Built-ins (04 section 10.3): `builtin:console` and `builtin:jsonl` ("frontends, route `console`, renderer hooks, commands"; replaceable), declared with `on_load(ext_declare_builtin(...))`.
- Route (04 section 6.1.1, IC-39): `console`, order `30`, match "no prompt (`gptr_can_prompt()` or `.stdin`)", result "the `console` frontend on the piped session or a new one; returns it invisibly on `/exit`". The frontend is chosen by `.opts$frontend`, then setting `frontend` (default `null` = `console`), validated against `registry_names("frontend")` (IC-69). P08 already registers the `frontend` setting spec; P14 registers none.
- Kinds used (04 section 10.2): `frontend` (`run` `function(session, ...)` -> session), `route` (`order`, `match(call)`, `run(call)`), `command` (`handler` `function(args, ctx)` returning `NULL`, a chr "printed verbatim" or `list(prompt = chr(1))` "sent as a prompt"; "an error is reported and the input counts as handled"), `hook`, `context_block` (`provide(ctx, budget)`, `placement`, `budget` int, `order` int), `renderer` (`render(entry, width, ctx)` -> chr), tool `render` = `function(call, result, width)` (IC-69).
- Hooks (04 section 7.14): "process-wide notify hooks on `message_update`, `message_end`, `tool_execution_start`, `tool_execution_end`, `agent_end` that render only for the foreground session when `verbosity() >= 2`, a hook on `artifact_start` printing `artifact  <id>  ->  <url>   (running in background)` (NS-8)"; P14 also hooks `agent_start`, `before_request` (spinner), `retry_start`, `permission_request` (returns `NULL`: it only ends a partial line before the UI asks) and `session_shutdown`.
- Events emitted: `input` (transform chain) with `source = "passthrough"` for `!expr`, `source = "repl"` for slash-command lines and `source = "steer"` for pause-menu text (04 section 10.4); `session_shutdown` with `reason = "exit"` when the REPL ends; the notify channels for transcript writers (P15 ambiguity 11; 03 section 6.17 "Commands are recorded as comments in transcripts"): `console:command` (`data = list(text)`, a slash command line that passed the `input` event unhandled and is dispatched as a command, after any transform) and `console:direct` (`data = list(code, output, status, noted)`, a direct R line after evaluation). P15's `doc_on_console_command()` (channel `console:command`) and `doc_on_console_direct()` (channel `console:direct`) write them to console transcripts.
- Pause menu (03 section 6.2, 04 section 7.14): `[s]teer`, `[f]ollow-up`, `[c]ontinue`, `[a]bort`, `[b]ackground` ("for foreground calls when P21 is loaded", through the `bg.register` service); "a second Ctrl-C aborts"; menu text on stderr; "`mode = "call"` re-signals the interrupt after an abort"; "abort-only where the restart is unverified (Rgui, IDE consoles)". Steers and follow-ups enter the queue with `session_enqueue(s, text, as, source = "pause_menu")` (IC-49, IC-55).
- Options (04 section 3.1): `gptr.verbose` (`int(1) | NULL`, default `NULL`; "0 silent, 1 progress on stderr, 2 streamed console, 3 debug; `NULL` = by context (0 knitr/testthat, 1 Rscript, 2 console)", read through P01's `verbosity()`); `gptr.max_turns_console` (`int(1)`, `200L`, "turns per console prompt"); `gptr.history` (`lgl(1)`, `TRUE`, "REPL inputs to the console history via `utils::timestamp()`").
- Conditions (04 section 2.2): warning `gptr_warning_readline_limit`; message `gptr_message_progress` ("P14, verbosity 1"); errors `gptr_error_invalid_argument` (fields `arg`, `expected`), `gptr_error_not_available` (`member`, `provided_by`).
- Readline limit (03 section 6.17, report 18 fact-check): "4,095 bytes on R < 4.5, 8,190 on R >= 4.5"; a longer line is warned about and not sent.
- `!expr` (03 section 6.17, IC-73): "evaluated in `envir`, added to the next prompt's context within 300 tokens"; `!!expr` is not added.
- Transcripts (04 section 11.5, IC-49): REPL prompts are recorded by P15 as `s_<6 hex> = peter("...")` / `s_<6 hex> |> peter("...")`; P14 supplies them as ordinary gateway calls and announces direct R (the `input` event with source `passthrough` first, which may handle or transform the code; then the `console:direct` channel with the output, which P15's `doc_on_console_direct()` records) and slash commands (the `input` event with source `repl` first; then the `console:command` channel, which P15's `doc_on_console_command()` records as a comment).
- Rendering (03 section 6.17): "colours only when `cli::num_ansi_colors() > 1`; `\r` only on dynamic TTYs; spinner ticked from the reactor; `flush.console()` after deltas". Untrusted text (model, tool, file and user text) is escaped with `console_escape()` (C0/C1 controls except TAB, bidi and zero-width characters as `<U+XXXX>`, IC-53 item 8) and written with `cat()` or `msg_verbatim()`; it is never the first argument of a `cli_*()` call (rule C1).
- IC-59: "the `.stdin` REPL connection (closed on `/exit` and by `on.exit()`)"; the JSONL sink "writes to a connection its caller owns" and opens none.
- Copy safety (03 section 6.4 R2): the REPL keeps the evaluation environment only in the binding `rs$envir`, reset to `NULL` when the REPL ends; the prompt mask's bindings are removed and its parent reset to `emptyenv()` after each prompt.
- Tests (04 section 12): `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`, `fake_requests(spec)`, `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_gptr_options(..., .env = parent.frame())`, `local_mock_server(scenario, ..., .env = parent.frame())`, `local_scripted_ui(answers = list(), .env = parent.frame())`, `tracemem_loader()` (child-script loader of `helper-tracemem.R`); `tests/testthat/setup.R` sets `options(gptr.interactive = FALSE, gptr.quiet = TRUE)` and `GPTR_REPLAY=replay` (the fake provider is `offline = TRUE`). Printed output is compared inside `testthat::local_reproducible_output(width = 80)` where it matters; SIGINT tests `skip_on_cran()`.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/console-render.R` | create (Task 1), extend (Task 2) | escaping, plain output and notices, the markdown stream renderer, the spinner; the console state, foreground test, tool, result, status and artifact lines, custom-entry renderers and the renderer hooks |
| `R/console-interrupt.R` | create (Task 3) | `with_interrupt_policy()`, the pause menu, deferred steering, abort and re-signal; the `console.interrupt_policy` service |
| `R/console-repl.R` | create (Task 4), extend (Tasks 5, 7) | REPL state and the input layer (readers, grammar, readline limit, history); `!expr`, notes, `@mentions`, the `user_ran` and `user_files` providers and `console_send()`; the loop, banner, stdin UI, `console_run()`, the frontend and route, `builtin:console`, the `?peter` console section |
| `R/console-commands.R` | create (Task 6) | the slash commands as `command` specs and their dispatcher |
| `R/console-jsonl.R` | create (Task 8) | the JSON form of events, `jsonl_sink()`, the `jsonl` frontend, `builtin:jsonl` |
| `tests/testthat/test-console-render.R` | create (Task 1), extend (Tasks 2, 7, 8) | renderer, escaping, hooks, end-to-end rendering (acceptance 3, 7); INFRA-27, rendering decoupled from transport (acceptance 4, the file 03 section 6.18 names; Task 8) |
| `tests/testthat/test-console-interrupt.R` | create (Task 3), extend (Task 7) | pause menu, abort, nesting; the INFRA-03 SIGINT test (acceptance 5) |
| `tests/testthat/test-console-repl.R` | create (Task 4), extend (Tasks 5, 7) | input grammar, passthrough and notes, scripted `.stdin` sessions (acceptance 2), IRkernel (acceptance 7) |
| `tests/testthat/test-console-commands.R` | create (Task 6) | every command |
| `tests/testthat/test-console-jsonl.R` | create (Task 8) | JSON form, event order, secrets (acceptance 6), the frontend |
| `NAMESPACE`, `man/peter.Rd` | regenerated (Task 7) | `Rscript --vanilla -e 'devtools::document()'` (the console section of `?peter`; no new exports) |

## Tasks (overview)

1. Escaping, the markdown stream renderer and the spinner (`console-render.R`)
2. Renderer hooks: console state, foreground, tool and status lines, custom entries (`console-render.R`)
3. The interrupt policy and the pause menu (`console-interrupt.R`)
4. REPL state and the input layer (`console-repl.R`)
5. `!expr` passthrough, notes, `@mentions` and `console_send()` (`console-repl.R`)
6. Slash commands (`console-commands.R`)
7. The REPL loop, the stdin UI, the frontend and route, `builtin:console`; INFRA-03 with real SIGINTs (`console-repl.R`)
8. The JSONL sink, the `jsonl` frontend and `builtin:jsonl` (`console-jsonl.R`)

---

### Task 1: Escaping, the markdown stream renderer and the spinner

**Files:**
- Create: `R/console-render.R`
- Test: `tests/testthat/test-console-render.R` (create)

**Interfaces:**
- Consumes: P01 `as_utf8(x)`, `msg_verbatim(x, stream = c("stdout", "stderr"))`, `front_end()`; P11 (`console-ui.R`, same layer and area) `ui_escape(x)` (C0/C1 controls except TAB, bidi and zero-width characters as `<U+XXXX>`; IC-53 item 8); cli `num_ansi_colors()`, `is_utf8_output()`, `is_dynamic_tty()`, `console_width()`, `code_highlight()`.
- Produces (04 section 7.14): `render_markdown_stream(width = cli::console_width())` -> environment with `write(delta)`, `finish()`, `reset_line()` (and `column()`); private helpers used by later tasks: `console_escape(x, newlines = TRUE)`, `console_lines(x)`, `console_out(x)`, `console_write(lines)`, `console_notice(...)`, `console_symbols()`, `console_interrupt_key()`, `console_print_text(text)`, `console_spinner(label = "thinking")` -> environment with `tick()`, `clear()`.

The renderer is report 18's verified `md_stream()` (Appendix A.6; 200 random chunkings identical in both modes) with its verification-log fix (item 24: display widths are right only for UTF-8-marked text, so every delta passes `as_utf8()` and the width test needs a UTF-8 locale) and two fixes made while writing this plan: line ends are normalised before escaping, holding a CR at the end of a chunk for the next one, so a CRLF split across chunks gives one line break; and every delta is escaped with `console_escape()` before rendering, so an ESC sequence in model text is shown, never executed (rule C1, IC-53 item 8). Escaping, line-end normalisation and rendering are each per character, so the output stays chunk-invariant. Untrusted text is written with `cat()` after escaping; it is never the first argument of a `cli_*()` call. The spinner is report 18's `wait_indicator()`: `\r` redraws only, a no-op when stdout is not a dynamic terminal. Symbols fall back to ASCII when the output is not UTF-8 (report 18 section 6); the non-ASCII ones are written as `\u` escapes.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-console-render.R`:

```r
# tests/testthat/test-console-render.R -- the console's printing layer (plan P14).
# Task 1: escaping, the markdown stream renderer, plain output, notices and the spinner; Task 2:
# the renderer hooks; Task 7: end-to-end rendering.

render_sample = paste0(
  "# Model summary\n\nThe **linear model** explains most of the variance in `mpg`; the ",
  "coefficient on `wt` is strongly negative, which means heavier cars travel fewer miles ",
  "per gallon on average.\r\n\r\n",
  "- first bullet that is long enough to need wrapping onto a second line at forty columns\n",
  "- second bullet with **bold text** inside\n",
  "1. numbered item\n\n",
  "> a quoted remark from the user\n\n",
  "```r\nfit = lm(mpg ~ wt, data = mtcars)\nsummary(fit)$r.squared\n```\n",
  "Done: R\u00b2 = 0.75 \u2014 averaging wide chars \u4e2d\u6587\u5b57\u7b26 too.")

render_chunks = function(chunks, width = 40L) {
  utils::capture.output({
    r = render_markdown_stream(width)
    for (ch in chunks) r$write(ch)
    r$finish()
  })
}

random_chunks = function(x, maxlen) {
  chars = strsplit(x, "")[[1L]]
  out = character()
  i = 1L
  while (i <= length(chars)) {
    k = sample.int(maxlen, 1L)
    out = c(out, paste(chars[i:min(length(chars), i + k - 1L)], collapse = ""))
    i = i + k
  }
  out
}

test_that("the output does not depend on chunking, plain and styled (acceptance 3)", {
  withr::local_seed(42)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    ref = render_chunks(render_sample)
    same = vapply(seq_len(200L), function(i) {
      identical(render_chunks(random_chunks(render_sample, sample.int(9L, 1L))), ref)
    }, NA)
    expect_true(all(same))
  }
})

test_that("prose lines respect the width and bullets hang (UTF-8 locale)", {
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "display widths need a UTF-8 locale (report 18)")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks(render_sample, width = 40L)
  prose = out[!grepl("^(```|fit|summary)", out)]
  expect_true(all(nchar(prose, type = "width") <= 40L))
  expect_true("- first bullet that is long enough to" %in% out)
  expect_true("  need wrapping onto a second line at" %in% out)
  expect_true("fit = lm(mpg ~ wt, data = mtcars)" %in% out)
})

test_that("a CRLF split across two chunks gives one line break", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(render_chunks(c("one\r", "\ntwo")), render_chunks("one\r\ntwo"))
  expect_identical(render_chunks("one\r\ntwo"), c("one", "two"))
  expect_identical(render_chunks(c("one\r", "two")), c("one", "two"))
})

test_that("untrusted braces are printed verbatim and never evaluated (rule C1)", {
  withr::local_envvar(GPTR_PWNED = NA)
  for (colours in c(1L, 256L)) {
    withr::local_options(cli.num_colors = colours)
    out = render_chunks(c("Try {Sys.setenv(GPTR", "_PWNED = \"1\")} now"), width = 80L)
    expect_true(any(grepl("{Sys.setenv(GPTR_PWNED = \"1\")}", out, fixed = TRUE)))
  }
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("control, bidi and zero-width characters are escaped (IC-53 item 8)", {
  expect_identical(console_escape("a\033[31mb"), "a<U+001B>[31mb")
  expect_identical(console_escape(paste0("x", intToUtf8(0x202e), "y")), "x<U+202E>y")
  expect_identical(console_escape(paste0("x", intToUtf8(0x200b), "y")), "x<U+200B>y")
  expect_identical(console_escape("tab\there\nnext"), "tab\there\nnext")
  expect_identical(console_escape("a\nb", newlines = FALSE), "a<U+000A>b")
  expect_identical(console_escape(c("ok", NA, "")), c("ok", NA, ""))
  expect_identical(console_escape("caf\u00e9"), "caf\u00e9")
  expect_identical(console_escape("end\n"), "end\n")
  withr::local_options(cli.num_colors = 1L)
  out = render_chunks("red \033[31mtext\033[0m", width = 80L)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_true(any(grepl("<U+001B>[31m", out, fixed = TRUE)))
})

test_that("console_lines() splits on any line end and console_out() prints escaped lines", {
  expect_identical(console_lines(c("a\r\nb\rc", "d\033")), c("a", "b", "c", "d<U+001B>"))
  expect_identical(console_lines(NA_character_), character())
  expect_identical(utils::capture.output(console_out("x {y}\ny\033")), c("x {y}", "y<U+001B>"))
})

test_that("notices go to stderr, never to stdout", {
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output(console_notice("[gptr] ", "hello"), type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "[gptr] hello")
})

test_that("reset_line() ends a partial line and finish() closes it", {
  withr::local_options(cli.num_colors = 1L)
  out = utils::capture.output({
    r = render_markdown_stream(80L)
    r$write("partial answer ")
    r$write("continues")
    r$reset_line()
    r$write(" next line")
    r$finish()
  })
  expect_identical(out, c("partial answer", "continues next line"))
})

test_that("console_print_text() prints a whole reply and skips empty text", {
  withr::local_options(cli.num_colors = 1L)
  expect_identical(utils::capture.output(console_print_text("Hello **there**")),
                   "Hello **there**")
  expect_identical(utils::capture.output(console_print_text(NA_character_)), character())
  expect_identical(utils::capture.output(console_print_text("")), character())
})

test_that("the spinner is silent when stdout is not a dynamic terminal", {
  withr::local_options(cli.dynamic = FALSE)
  sp = console_spinner()
  expect_identical(utils::capture.output({
    sp$tick()
    sp$clear()
  }), character())
})

test_that("the interrupt key follows the front end", {
  local_mocked_bindings(front_end = function() "rstudio")
  expect_identical(console_interrupt_key(), "Esc")
  local_mocked_bindings(front_end = function() "terminal")
  expect_identical(console_interrupt_key(), "Ctrl-C")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
```

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 0 ]`; the errors read `could not find function "render_markdown_stream"` (and `console_escape`, `console_lines`, `console_notice`, `console_print_text`, `console_spinner`, `console_interrupt_key`).

- [ ] **Step 3: Write the implementation**

Create `R/console-render.R`:

```r
# console-render.R -- P14 Console and front ends (layer L5, area console).
# The printing layer of the console (architecture 6.17; contract 7.14). Task 1: escaping of
# untrusted text, plain output and notices, the chunk-invariant markdown stream renderer and the
# waiting indicator. Task 2 appends the renderer hooks. Adapted from report 18 Appendix A.6
# (md_stream(), wait_indicator()) with its verification-log fix (text is UTF-8 marked before
# widths are measured, item 24) and two fixes of this plan: line ends are normalised before
# escaping (a CR at the end of a chunk is held for the next chunk, so a CRLF split across chunks
# gives one line break) and every delta is escaped (IC-53 item 8). Untrusted text is written with
# cat() after console_escape(), never as a cli or glue format string (rule C1).

#' Symbols of the console with ASCII fallbacks (report 18 section 6: symbols vanish when the
#' output is not UTF-8)
#' @noRd
console_symbols = function() {
  if (cli::is_utf8_output()) {
    list(bullet = "\u2022 ", tool = "\u25cf ", bar = "\u2502 ", top = "\u250c\u2500 ",
         bottom = "\u2514\u2500", result = "\u23bf ", sep = " \u00b7 ",
         frames = c("\u280b", "\u2819", "\u2839", "\u2838", "\u283c", "\u2834", "\u2826",
                    "\u2827", "\u2807", "\u280f"))
  } else {
    list(bullet = "- ", tool = "* ", bar = "| ", top = "+- ", bottom = "+-", result = "-> ",
         sep = " | ", frames = c("-", "\\", "|", "/"))
  }
}

#' The key that interrupts R in this front end (Esc in Rgui, R.app and the IDE consoles; report
#' 18 section 6)
#' @noRd
console_interrupt_key = function() {
  if (front_end() %in% c("rgui", "rstudio", "positron")) "Esc" else "Ctrl-C"
}

#' Escape untrusted text for display (IC-53 item 8)
#'
#' C0/C1 controls (except TAB), bidi and zero-width characters become `<U+XXXX>` through P11's
#' `ui_escape()`, one rule for every display of the console. With `newlines = TRUE` (streamed
#' text) line feeds are kept and each line is escaped on its own; the mapping is per character,
#' so escaping commutes with chunking. With `newlines = FALSE` (one-line displays) line feeds are
#' escaped too. NA stays NA.
#' @noRd
console_escape = function(x, newlines = TRUE) {
  x = as_utf8(as.character(x))
  if (!newlines) return(ui_escape(x))
  out = x
  k = 1L
  while (k <= length(x)) {
    s = x[[k]]
    if (!is.na(s) && grepl("[^\t\n -~]", s, perl = TRUE)) {
      pieces = strsplit(paste0(s, "\n"), "\n", fixed = TRUE)[[1L]]
      out[[k]] = paste(ui_escape(pieces), collapse = "\n")
    }
    k = k + 1L
  }
  out
}

#' Lines of untrusted text for one-line displays: split on CRLF, CR and LF, then escaped
#' @noRd
console_lines = function(x) {
  x = as_utf8(as.character(x))
  x = x[!is.na(x)]
  if (!length(x)) return(character())
  lines = unlist(strsplit(paste(x, collapse = "\n"), "\r\n|\r|\n", perl = TRUE), use.names = FALSE)
  console_escape(lines, newlines = FALSE)
}

#' Print untrusted text on stdout, one escaped line each (never a format string, rule C1)
#' @noRd
console_out = function(x) {
  console_write(console_lines(x))
}

#' Print lines that are already safe (built from escaped parts) on stdout
#' @noRd
console_write = function(lines) {
  if (length(lines)) cat(paste0(lines, "\n"), sep = "")
  utils::flush.console()
  invisible(NULL)
}

#' A console notice on stderr: the pause menu and REPL notices (the menu can run inside a tool's
#' stdout capture, G3 menu fixes). Callers escape untrusted parts with console_escape().
#' @noRd
console_notice = function(...) {
  msg_verbatim(paste0(...), "stderr")
  invisible(NULL)
}

#' Chunk-invariant markdown stream renderer (report 18 A.6 md_stream(); contract 7.14)
#'
#' Returns an environment with `write(delta)`, `finish()`, `reset_line()` and `column()`.
#' Output goes to stdout. Styling (bold, inline code, headings, bullets, quotes, fenced code)
#' is used when `cli::num_ansi_colors() > 1` at creation; the plain mode keeps the markdown
#' characters and only wraps at `width` display columns. Words are buffered until the next
#' blank or line end, so the output does not depend on how the text was chunked.
#' @noRd
render_markdown_stream = function(width = cli::console_width()) {
  style = cli::num_ansi_colors() > 1L
  sym = console_symbols()
  width = max(20L, as.integer(width))
  st = new.env(parent = emptyenv())
  st$buf = ""
  st$cr = ""
  st$col = 0L
  st$line_start = TRUE
  st$indent = 0L
  st$fence = FALSE
  st$fence_lang = ""
  st$bold = FALSE
  st$code = FALSE
  st$heading = FALSE
  st$space = FALSE
  sgr = function(code) if (style) paste0("\033[", code, "m") else ""
  emit = function(x) {
    if (nzchar(x)) cat(x, sep = "")
    invisible()
  }
  vis_width = function(x) sum(nchar(x, type = "width"))
  reset_styles = function() if (st$heading || st$bold || st$code) sgr("0") else ""
  newline = function() {
    emit(paste0(reset_styles(), "\n"))
    st$col = 0L
    st$line_start = TRUE
    st$indent = 0L
    st$heading = FALSE
    st$bold = FALSE
    st$code = FALSE
    st$space = FALSE
  }
  inline = function(tok) {
    if (!style) return(list(text = tok, width = vis_width(tok)))
    out = character()
    w = 0L
    i = 1L
    n = nchar(tok)
    while (i <= n) {
      if (!st$code && identical(substr(tok, i, i + 1L), "**")) {
        st$bold = !st$bold
        out = c(out, if (st$bold) sgr("1") else sgr("22"))
        i = i + 2L
        next
      }
      ch = substr(tok, i, i)
      if (identical(ch, "`")) {
        st$code = !st$code
        out = c(out, if (st$code) sgr("36") else sgr("39"))
        i = i + 1L
        next
      }
      out = c(out, ch)
      w = w + vis_width(ch)
      i = i + 1L
    }
    list(text = paste(out, collapse = ""), width = w)
  }
  line_prefix = function(tok) {
    if (grepl("^#{1,6}$", tok)) {
      st$heading = TRUE
      return(list(text = if (style) sgr("1;4") else paste0(tok, " "),
                  width = if (style) 0L else nchar(tok) + 1L))
    }
    if (tok %in% c("-", "*", "+")) {
      st$indent = 2L
      return(list(text = if (style) sym$bullet else "- ", width = 2L))
    }
    if (grepl("^[0-9]+[.)]$", tok)) {
      st$indent = nchar(tok) + 1L
      return(list(text = paste0(tok, " "), width = nchar(tok) + 1L))
    }
    if (identical(tok, ">")) {
      st$indent = 2L
      return(list(text = if (style) paste0(sgr("2"), sym$bar, sgr("22")) else "> ", width = 2L))
    }
    NULL
  }
  fence_line = function(line) {
    code = line
    if (st$fence_lang %in% c("r", "R", "{r}") && nzchar(trimws(line))) {
      code = tryCatch(cli::code_highlight(line), error = function(e) line)
    }
    emit(paste0(sgr("2"), sym$bar, sgr("22"), code, "\n"))
  }
  fence_marker = function(line) {
    if (!st$fence) {
      st$fence = TRUE
      st$fence_lang = trimws(substring(line, 4L))
      emit(paste0(if (style) paste0(sgr("2"), sym$top, st$fence_lang, sgr("22")) else line, "\n"))
    } else {
      st$fence = FALSE
      emit(paste0(if (style) paste0(sgr("2"), sym$bottom, sgr("22")) else line, "\n"))
    }
  }
  process = function(text, final = FALSE) {
    text = paste0(st$buf, text)
    st$buf = ""
    repeat {
      if (!nzchar(text)) break
      if (st$fence || (st$line_start && startsWith(text, "```"))) {
        nl = regexpr("\n", text, fixed = TRUE)
        if (nl < 0L) {
          if (final) {
            text = paste0(text, "\n")
            next
          }
          st$buf = text
          return(invisible())
        }
        line = substr(text, 1L, nl - 1L)
        text = substr(text, nl + 1L, nchar(text))
        if (startsWith(line, "```")) {
          fence_marker(line)
        } else if (style) {
          fence_line(line)
        } else {
          emit(paste0(line, "\n"))
        }
        st$col = 0L
        st$line_start = TRUE
        next
      }
      m = regexpr("^(\n|[ \t]+|[^ \t\n]+)", text)
      tok = regmatches(text, m)
      rest = substr(text, attr(m, "match.length") + 1L, nchar(text))
      if (!nzchar(rest) && !final && !identical(tok, "\n")) {
        st$buf = tok
        return(invisible())
      }
      text = rest
      if (identical(tok, "\n")) {
        newline()
        next
      }
      if (grepl("^[ \t]+$", tok)) {
        if (st$line_start || st$col == st$indent) next
        st$space = TRUE
        next
      }
      if (st$line_start) {
        st$line_start = FALSE
        pre = line_prefix(tok)
        if (!is.null(pre)) {
          emit(pre$text)
          st$col = st$col + pre$width
          if (nzchar(text) && grepl("^[ \t]", text)) text = sub("^[ \t]+", "", text)
          next
        }
      }
      w = inline(tok)
      sp = isTRUE(st$space)
      st$space = FALSE
      if (st$col > st$indent && st$col + sp + w$width > width) {
        emit(paste0(reset_styles(), "\n", strrep(" ", st$indent),
                    if (st$heading) sgr("1;4") else "", if (st$bold) sgr("1") else "",
                    if (st$code) sgr("36") else ""))
        st$col = st$indent
      } else if (sp) {
        emit(" ")
        st$col = st$col + 1L
      }
      emit(w$text)
      st$col = st$col + w$width
    }
    invisible()
  }
  # Line ends first (CRLF and lone CR become LF; a trailing CR waits for the next chunk), then
  # escaping, then rendering: each step is chunk-invariant
  ingest = function(delta, final = FALSE) {
    text = paste0(st$cr, paste(as_utf8(as.character(delta)), collapse = ""))
    st$cr = ""
    if (!final && endsWith(text, "\r")) {
      st$cr = "\r"
      text = substr(text, 1L, nchar(text) - 1L)
    }
    process(console_escape(gsub("\r\n?", "\n", text)), final)
  }
  r = new.env(parent = emptyenv())
  r$write = function(delta) {
    ingest(delta)
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$finish = function() {
    ingest("", final = TRUE)
    if (st$col > 0L) newline()
    flush(stdout())
    utils::flush.console()
    invisible()
  }
  r$reset_line = function() {
    if (st$col > 0L) {
      emit(paste0(reset_styles(), "\n"))
      st$col = 0L
      st$line_start = TRUE
      st$indent = 0L
      st$space = FALSE
      st$heading = FALSE
      st$bold = FALSE
      st$code = FALSE
    }
    invisible()
  }
  r$column = function() st$col
  r
}

#' Print a complete text through the markdown renderer (one shot)
#' @noRd
console_print_text = function(text) {
  text = as_utf8(as.character(text))
  text = text[!is.na(text)]
  if (!length(text) || !any(nzchar(text))) return(invisible())
  r = render_markdown_stream()
  r$write(paste(text, collapse = "\n"))
  r$finish()
  invisible()
}

#' The waiting indicator (report 18 A.6 wait_indicator()), ticked by its caller
#'
#' Uses only "\r" redraws (safe in RStudio and Windows consoles); `tick()` is a no-op when stdout
#' is not a dynamic terminal, so tests, pipes and knitr never see it.
#' @noRd
console_spinner = function(label = "thinking") {
  frames = console_symbols()$frames
  key = console_interrupt_key()
  sp = new.env(parent = emptyenv())
  sp$dynamic = cli::is_dynamic_tty()
  sp$i = 0L
  sp$t0 = Sys.time()
  sp$shown = FALSE
  sp$last = 0
  sp$tick = function() {
    if (!sp$dynamic) return(invisible())
    now = as.numeric(Sys.time())
    if (now - sp$last < 0.08) return(invisible())
    sp$last = now
    sp$i = sp$i %% length(frames) + 1L
    secs = as.numeric(difftime(Sys.time(), sp$t0, units = "secs"))
    cat(sprintf("\r%s %s (%.0fs, %s to steer or stop)", frames[[sp$i]], label, secs, key),
        sep = "")
    utils::flush.console()
    sp$shown = TRUE
    invisible()
  }
  sp$clear = function() {
    if (sp$shown) {
      cat("\r", strrep(" ", max(0L, cli::console_width() - 1L)), "\r", sep = "")
      utils::flush.console()
      sp$shown = FALSE
    }
    invisible()
  }
  sp
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
LC_ALL=C Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 34 ]` in a UTF-8 locale; in the C locale `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 30 ]` (the width test needs a UTF-8 locale, report 18 fact-check item 24; chunk invariance holds in both).

- [ ] **Step 5: Commit**

```bash
git add R/console-render.R tests/testthat/test-console-render.R
git commit -m "feat(console): add escaping, the markdown stream renderer and the spinner"
```

---

### Task 2: Renderer hooks: console state, foreground, tool and status lines, custom entries

**Files:**
- Modify: `R/console-render.R` (append)
- Test: `tests/testthat/test-console-render.R` (append)

**Interfaces:**
- Consumes: Task 1; P01 `the`, `ev_new(type, ...)`, `json_encode(x)`, `gptr_inform(message, class, ...)` (class `progress`, 04 section 2.2), `verbosity()`; P02 `gptr_hook(event, handler, matcher = NULL)`, `registry_get(kind, name, session = NULL)` (kinds `tool` with field `render` = `function(call, result, width)`, and `renderer` with `render(entry, width, ctx)` -> chr, IC-69); P04 `reactor_task(fn, run = NULL)` (a number returned by `fn` means "call me again after that many seconds"), `reactor_cancel(ids)`; P06 kernel SDK `session_data(s)` (`.d$id`, `depth`, `entries`), `session_live(s)` (live record: `ctx`, `background`), `run_current()` (the innermost run whose tool is executing on this call stack, or `NULL`; 04 section 7.6); the event payloads of 04 section 10.4 (`agent_start`; `before_request`: `provider`, `model`, `request_id`, `tokens_est`; `message_update`: `index`, `kind`, `delta`; `message_end`: `role`, `message`; `tool_execution_start`: `tool_call_id`, `tool_name`, `input`; `tool_execution_end`: `is_error`, `elapsed`; `agent_end`: `status`, `reason`, `usage`, `turns`; `artifact_start`: `id`, `url`, `version`; `retry_start`: `attempt`, `delay`, `class`; `permission_request`; `session_shutdown`). Tests: P01 `gptr_fake_provider()`, `msg_assistant()`, `msg_tool_result()`, `local_project()`, `local_gptr_options()`; P02 `gptr_spec()`, `gptr_register()`; P06 `session_append(s, entry)`; P08 `peter(..., .run = FALSE)`.
- Produces: `console_hooks()` -> the list of hook specs builtin_console() registers (Task 7); the console state `console_state()` (`the$console`, owned by P14) with `active`: run id -> record (session, markdown stream, spinner, pending tool calls) between `agent_start` and `agent_end`, read by the interrupt policy (Task 3) through `console_track(run_id, session)`, `console_record(event)`, `console_drop(run_id)`; `console_foreground(rec)`, `console_render_pause()`; the line builders `console_tool_line(call, result = NULL, session = NULL, width = cli::console_width())`, `console_artifact_line(id, url)`, `console_status_line(status, reason = NULL, usage = NULL, turns = NULL)`; the NS-8 queue helpers `console_artifact_emit(lines)` and `console_artifact_flush()` (field `artifacts` of the console state); the handlers `console_on_*()`.

The hooks follow 04 section 7.14: process-wide notify hooks that render only foreground sessions (depth 0, live, not handed to P21's background pump) when `verbosity() >= 2`; at verbosity 1 tool calls and run ends become progress messages on stderr (class `gptr_message_progress`); at verbosity 3 thinking deltas and request lines are shown too. A run is tracked from `agent_start` at any verbosity because the interrupt policy needs the session of each run it is given (04 gives no accessor from a `gptr_run` to its session object). Answers stream through Task 1's renderer; a reply that arrived without deltas is printed whole at `message_end`. A tool call gets one line at `tool_execution_start`, "  * r  <first line>  (+N more lines)" (NS-1), and its result lines come from the tool-result message at `message_end`: errors, the object changes of `r`, the diff of `edit`, the path of `write`. A tool spec's `render(call, result, width)` replaces both (IC-69: `call` = `list(id, name, input)`, `result` = `NULL` at the start and the tool-result message plus `elapsed` at the end); custom entries appended during the run are shown at `agent_end` through `renderer` records. `artifact_start` prints the NS-8 line `artifact  <id>  ->  <url>   (running in background)` (IC-71). The event usually fires inside the model's `r` code (`peter$app()`, P23), whose stdout and messages P09's evaluator captures into the tool result; printed there, the line (with its tokenised URL) would reach the model a second time next to the handle's own print (P23 ambiguity 14). So while a tool executes (`run_current()` non-`NULL`) the line is queued in the console state and printed by the `tool_execution_end` hook once no tool executes on the stack (a nested `peter$<tool>()` call ending inside the `r` code keeps it queued), or at `agent_end` after an interrupted tool; outside a tool it prints at once. `permission_request` only ends partial lines (the UI of P11 asks next); it returns `NULL` and cannot fail, because a failing `permission_request` handler denies. The spinner is a reactor task ticking every 0.1 s from `before_request` to the first delta (03 section 6.17: "spinner ticked from the reactor").

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-console-render.R`:

```r
# ---------------------------------------------------------------- Task 2: renderer hooks

# A real, idle session that never ran (its prompt waits in the queue): the hooks only read it
render_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

# Run events through the handlers that console_hooks() registers, capturing stdout
render_events = function(s, events) {
  hooks = console_hooks()
  types = vapply(hooks, function(h) h$event, "")
  ctx = session_live(s)$ctx
  utils::capture.output({
    for (ev in events) {
      for (h in hooks[types == ev$type]) h$handler(ev, ctx)
    }
  })
}

hook_event = function(type, s, ..., run = "u0000test") {
  ev_new(type, session = session_data(s)$id, run = run, ...)
}

assistant_msg = function(text) {
  msg_assistant(text, api = "fake", provider = "fake", model = "fake-1")
}

test_that("console_hooks() subscribes the events of contract 7.14", {
  events = vapply(console_hooks(), function(h) h$event, "")
  expect_true(all(c("message_update", "message_end", "tool_execution_start",
                    "tool_execution_end", "agent_end", "artifact_start") %in% events))
  expect_true(all(vapply(console_hooks(), function(h) inherits(h, "gptr_hook"), NA)))
})

test_that("a foreground run streams its answer and ends with a status line (verbosity 2)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "Hello **wo"),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "rld** {x}\n"),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("Hello")),
    hook_event("agent_end", s, status = "idle", reason = NULL, usage = NULL, doc = NULL,
               turns = 1L)))
  expect_identical(out, c("Hello **world** {x}", "  done | 1 turn | 0 tokens | $0.0000"))
  expect_null(console_record(list(run = "u0000test")))
})

test_that("nothing is printed at verbosity 0 or for a background session", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  s = render_session()
  events = list(
    hook_event("agent_start", s),
    hook_event("message_update", s, index = 1L, kind = "text", delta = "quiet"),
    hook_event("agent_end", s, status = "idle", usage = NULL, turns = 1L))
  local_gptr_options(verbose = 0L)
  expect_identical(render_events(s, events), character())
  local_gptr_options(verbose = 2L)
  live = session_live(s)
  live$background = list(id = "s-in-the-background")
  withr::defer({
    live$background = NULL
  })
  expect_identical(render_events(s, events), character())
})

test_that("an answer without deltas is printed whole at message_end", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("message_end", s, role = "assistant", message = assistant_msg("All at once."))))
  expect_identical(out, "All at once.")
})

test_that("tool lines escape the preview and summarise the result (acceptance 7)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  result = msg_tool_result("c1", "r", "ok", details = list(
    objects = list(added = c("x", "y"), modified = character(), removed = character()),
    plots = 0L))
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c1", tool_name = "r",
               input = list(code = "x = 1 # \033[31mred\ny = 2")),
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 2.5, details = list()),
    hook_event("message_end", s, role = "tool_result", message = result)))
  expect_identical(out, c("  * r  x = 1 # <U+001B>[31mred  (+1 more lines)",
                          "    -> + x, y (2.5 s)"))
  expect_false(any(grepl("\033", out, fixed = TRUE)))
})

test_that("an error result shows its first line", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  bad = msg_tool_result("c2", "r", "Error: object 'z' not found\nIn: z + 1", is_error = TRUE)
  out = render_events(s, list(
    hook_event("agent_start", s),
    hook_event("tool_execution_start", s, tool_call_id = "c2", tool_name = "r",
               input = list(code = "z + 1")),
    hook_event("message_end", s, role = "tool_result", message = bad)))
  expect_identical(out[[2L]], "    -> error: Error: object 'z' not found")
})

test_that("a tool's render() function replaces the default lines (IC-69)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  shout = gptr_spec("tool", "shout", description = "Shout a text.",
                    parameters = list(type = "object",
                                      properties = list(text = list(type = "string"))),
                    execute = function(input, ctx) "ok",
                    render = function(call, result, width) {
                      if (is.null(result)) paste("SHOUT", call$input$text) else "SHOUTED"
                    })
  off = gptr_register(shout)
  withr::defer(off())
  call = list(id = "c1", name = "shout", input = list(text = "hi\033"))
  expect_identical(console_tool_line(call), "SHOUT hi<U+001B>")
  expect_identical(console_tool_line(call, list(is_error = FALSE)), "SHOUTED")
})

test_that("artifact_start prints the NS-8 line (acceptance 7)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  ev = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
              version = 1L)
  local_gptr_options(verbose = 2L)
  expect_identical(utils::capture.output(invisible(console_on_artifact_start(ev, NULL))),
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
  local_gptr_options(verbose = 1L, quiet = FALSE)
  expect_message(console_on_artifact_start(ev, NULL), class = "gptr_message_progress")
})

test_that("an artifact_start fired while a tool executes prints after tool_execution_end", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  st = console_state()
  st$artifacts = NULL
  withr::defer({
    st$artifacts = NULL
    console_drop("u0000test")
  })
  s = render_session()
  ctx = session_live(s)$ctx
  in_tool = structure(new.env(parent = emptyenv()), class = "gptr_run")
  art = ev_new("artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827",
               version = 1L)
  line = "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)"
  invisible(utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "a = peter$app()")),
                          ctx)
  }))
  # inside the model's r code (run_current() non-NULL; P09 captures this output): queued; a
  # nested tool call (peter$<tool>() in that code) ends while the r tool still runs
  inside = local({
    local_mocked_bindings(run_current = function() in_tool)
    utils::capture.output({
      console_on_artifact_start(art, ctx)
      invisible(console_on_tool_end(hook_event("tool_execution_end", s, tool_call_id = "n1",
                                               tool_name = "read", is_error = FALSE,
                                               elapsed = 0.1, details = list()), ctx))
    })
  })
  expect_identical(inside, character())
  expect_identical(console_state()$artifacts, line)
  after = utils::capture.output(invisible(console_on_tool_end(
    hook_event("tool_execution_end", s, tool_call_id = "c1", tool_name = "r", is_error = FALSE,
               elapsed = 0.2, details = list()), ctx)))
  expect_identical(after, line)
  expect_null(console_state()$artifacts)
})

test_that("verbosity 1 reports tool calls and the end as progress messages", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 1L, quiet = FALSE)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  expect_message(
    console_on_tool_start(hook_event("tool_execution_start", s, tool_call_id = "c1",
                                     tool_name = "r", input = list(code = "dim(x)")), ctx),
    "gptr: r  dim(x)", fixed = TRUE)
  expect_message(
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 2L),
                         ctx),
    "gptr: done | 2 turns", fixed = TRUE)
})

test_that("the status line names an unusual end and sums the usage rows", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  usage = data.frame(input = c(1000, 200), output = c(50, 10), cache_read = c(0, 900),
                     cost = c(0.001, 0.0005))
  expect_identical(console_status_line("idle", NULL, usage, 3L),
                   "  done | 3 turns | 2.2k tokens | $0.0015")
  expect_identical(console_status_line("aborted", "aborted (user)", NULL, 1L),
                   "  aborted: aborted (user) | 1 turn | 0 tokens | $0.0000")
})

test_that("custom entries of a run are shown through renderer records (IC-69)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  off = gptr_register(gptr_spec("renderer", "demo.note",
                                render = function(entry, width, ctx) {
                                  paste("NOTE:", entry$data$text)
                                }))
  withr::defer(off())
  s = render_session()
  ctx = session_live(s)$ctx
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    session_append(s, list(type = "custom", custom_type = "demo.note",
                           data = list(text = "kept \033 safe")))
    console_on_agent_end(hook_event("agent_end", s, status = "idle", usage = NULL, turns = 0L),
                         ctx)
  })
  expect_identical(out[[1L]], "NOTE: kept <U+001B> safe")
})

test_that("the spinner runs as a reactor task from before_request to the first delta", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  console_on_agent_start(hook_event("agent_start", s), ctx)
  rec = console_record(list(run = "u0000test"))
  console_on_before_request(hook_event("before_request", s, provider = "fake",
                                       model = "fake/fake-1", request_id = "q1",
                                       tokens_est = 10), ctx)
  expect_false(is.null(rec$task))
  utils::capture.output(console_on_message_update(
    hook_event("message_update", s, index = 1L, kind = "text", delta = "x"), ctx))
  expect_null(rec$task)
  expect_null(rec$spinner)
  console_drop("u0000test")
})

test_that("permission_request ends partial lines and never decides", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  s = render_session()
  ctx = session_live(s)$ctx
  out = utils::capture.output({
    console_on_agent_start(hook_event("agent_start", s), ctx)
    console_on_message_update(hook_event("message_update", s, index = 1L, kind = "text",
                                         delta = "partial "), ctx)
    expect_null(console_on_permission(hook_event("permission_request", s), ctx))
    cat("allow? ")
  })
  expect_identical(out, c("partial", "allow? "))
  console_drop("u0000test")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
```

Expected: `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 34 ]`; the new tests error with `could not find function "console_hooks"` (and `console_tool_line`, `console_on_artifact_start`, `console_on_agent_start`, `console_status_line`, `console_record`).

- [ ] **Step 3: Write the implementation**

Append to `R/console-render.R`:

```r
# ---------------------------------------------------------------------------------------------
# Renderer hooks (Task 2). Rendering subscribes to events (INFRA-27): the transport and the loop
# never print. builtin:console registers these process-wide notify hooks; they render runs of
# foreground sessions (depth 0, not handed to the background pump) at verbosity() >= 2 and
# print progress lines on stderr at verbosity 1 (message class gptr_message_progress). The
# console state `the$console` maps a run id to its session and renderer state from agent_start
# to agent_end; it holds front-end state only, never run state (INFRA-15). The interrupt policy
# reads the same map to find the session of a run it was given.
# ---------------------------------------------------------------------------------------------

#' The console's process state (`the$console`, owned by P14): `active` maps a run id to its
#' record (session, markdown stream, spinner, pending tool calls); `artifacts` holds the NS-8
#' lines of `artifact_start` events that fired while a tool executed, until none executes
#' @noRd
console_state = function() {
  st = the$console
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$active = new.env(parent = emptyenv())
    the$console = st
  }
  st
}

#' Start tracking a run of a session (the agent_start hook; tests call it directly)
#' @noRd
console_track = function(run_id, session) {
  rec = new.env(parent = emptyenv())
  rec$session = session
  rec$run = run_id
  rec$md = NULL
  rec$think = NULL
  rec$spinner = NULL
  rec$task = NULL
  rec$tools = new.env(parent = emptyenv())
  rec$n0 = length(session_data(session)$entries)
  rec$streamed = FALSE
  assign(run_id, rec, envir = console_state()$active)
  invisible(rec)
}

#' The record of the run an event belongs to, or NULL
#' @noRd
console_record = function(event) {
  run = event$run
  if (!is.character(run) || length(run) != 1L || is.na(run)) return(NULL)
  get0(run, envir = console_state()$active, inherits = FALSE)
}

#' Forget a run (agent_end) after stopping its spinner
#' @noRd
console_drop = function(run_id) {
  st = console_state()
  rec = get0(run_id, envir = st$active, inherits = FALSE)
  if (!is.null(rec)) {
    console_spinner_stop(rec)
    rm(list = run_id, envir = st$active)
  }
  invisible(NULL)
}

#' Is the run's session a foreground session? Depth 0, live, not in the background pump (P21
#' stores a list in the live record's `background` field)
#' @noRd
console_foreground = function(rec) {
  s = rec$session
  if (!inherits(s, "gptr_session")) return(FALSE)
  live = session_live(s)
  if (is.null(live) || !is.null(live$background)) return(FALSE)
  isTRUE(as.integer(session_data(s)$depth %||% 0L) == 0L)
}

#' Render this record now? (verbosity 2 or 3 and a foreground session)
#' @noRd
console_render_on = function(rec) {
  verbosity() >= 2L && console_foreground(rec)
}

#' Start the spinner of a record, ticked by a reactor task every 0.1 s (03 section 6.17)
#' @noRd
console_spinner_start = function(rec) {
  if (!is.null(rec$task) || !isTRUE(cli::is_dynamic_tty())) return(invisible(NULL))
  rec$spinner = console_spinner("thinking")
  rec$task = reactor_task(function() {
    sp = rec$spinner
    if (is.null(sp)) return(FALSE)
    sp$tick()
    0.1
  })
  invisible(NULL)
}

#' Stop the spinner of a record and clear its line
#' @noRd
console_spinner_stop = function(rec) {
  sp = rec$spinner
  rec$spinner = NULL
  if (!is.null(sp)) sp$clear()
  task = rec$task
  rec$task = NULL
  if (!is.null(task)) tryCatch(reactor_cancel(task), error = function(e) NULL)
  invisible(NULL)
}

#' End the partial lines of a record (before a tool line, a prompt or the pause menu)
#' @noRd
console_pause_one = function(rec) {
  console_spinner_stop(rec)
  if (!is.null(rec$think)) rec$think$reset_line()
  if (!is.null(rec$md)) rec$md$reset_line()
  invisible(NULL)
}

#' End the partial lines of every tracked run (the pause menu, approval prompts)
#' @noRd
console_render_pause = function() {
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) console_pause_one(get(id, envir = active))
  invisible(NULL)
}

#' Concatenated text blocks of a message (context blocks excluded)
#' @noRd
console_msg_text = function(msg) {
  parts = character()
  for (b in msg$content %||% list()) {
    if (identical(b$type, "text") && is.character(b$text)) parts = c(parts, b$text)
  }
  paste(parts, collapse = "")
}

#' A short preview of a tool input: its code, its path, its questions, else compact JSON
#' @noRd
console_tool_preview = function(input) {
  if (is.character(input$code) && length(input$code)) return(paste(input$code, collapse = "\n"))
  if (is.character(input$path) && length(input$path)) return(input$path[[1L]])
  if (is.list(input$questions)) return(paste0(length(input$questions), " question(s)"))
  if (!length(input)) return("")
  tryCatch(json_encode(input), error = function(e) "")
}

#' Fit display lines into the console width (ANSI-aware)
#' @noRd
console_fit = function(lines, width = cli::console_width()) {
  if (!length(lines)) return(character())
  as.character(cli::ansi_strtrim(lines, max(20L, as.integer(width))))
}

#' The default start line of a tool call: "  * r  first line  (+N more lines)" (NS-1)
#' @noRd
console_call_line = function(call) {
  sym = console_symbols()
  lines = strsplit(console_tool_preview(call$input %||% list()), "\n", fixed = TRUE)[[1L]]
  first = if (length(lines)) lines[[1L]] else ""
  more = if (length(lines) > 1L) paste0("  (+", length(lines) - 1L, " more lines)") else ""
  paste0("  ", sym$tool, console_escape(call$name %||% "?", FALSE), "  ",
         console_escape(first, FALSE), more)
}

#' The default lines of a tool result: errors, object changes of `r`, the diff of `edit`, the
#' path of `write`; nothing for quiet successes
#' @noRd
console_result_lines = function(call, result) {
  sym = console_symbols()
  pad = paste0("    ", sym$result)
  el = result$elapsed
  secs = if (is.numeric(el) && length(el) == 1L && !is.na(el) && el >= 1) {
    sprintf(" (%.1f s)", el)
  } else {
    ""
  }
  if (isTRUE(result$is_error)) {
    text = strsplit(console_msg_text(result), "\n", fixed = TRUE)[[1L]]
    first = if (length(text)) text[[1L]] else "failed"
    return(cli::col_red(paste0(pad, "error: ", console_escape(first, FALSE), secs)))
  }
  d = result$details %||% list()
  name = call$name %||% ""
  if (identical(name, "r")) {
    obj = d$objects %||% list()
    parts = c(
      if (length(obj$added)) paste0("+ ", paste(obj$added, collapse = ", ")),
      if (length(obj$modified)) paste0("~ ", paste(obj$modified, collapse = ", ")),
      if (length(obj$removed)) paste0("- ", paste(obj$removed, collapse = ", ")),
      if (isTRUE(d$plots >= 1L)) paste0("[", d$plots, if (d$plots == 1L) " plot]" else " plots]")
    )
    if (!length(parts) && !nzchar(secs)) return(character())
    body = if (length(parts)) paste(parts, collapse = "  ") else "done"
    return(paste0(pad, console_escape(body, FALSE), secs))
  }
  if (identical(name, "edit") && length(d$diff)) {
    diff = as.character(d$diff)
    shown = utils::head(diff, 12L)
    lines = paste0("    ", console_escape(shown, FALSE))
    lines = ifelse(startsWith(shown, "+"), cli::col_green(lines),
                   ifelse(startsWith(shown, "-"), cli::col_red(lines), lines))
    if (length(diff) > 12L) lines = c(lines, paste0("    (+", length(diff) - 12L, " more lines)"))
    return(as.character(lines))
  }
  if (identical(name, "write") && is.character(d$path) && length(d$path) == 1L) {
    bytes = ""
    if (is.numeric(d$bytes)) bytes = paste0(" (", format(d$bytes, big.mark = ","), " bytes)")
    return(paste0(pad, "wrote ", console_escape(d$path, FALSE), bytes, secs))
  }
  if (nzchar(secs)) return(paste0(pad, "done", secs))
  character()
}

#' The console lines of a tool call (`result = NULL`) or of its result
#'
#' A tool spec's `render(call, result, width)` wins (IC-69); its output is escaped like any other
#' untrusted text. `call` is `list(id, name, input)`; `result` is the tool-result message (04
#' section 4.2: `content`, `is_error`, `details`) plus `elapsed`.
#' @noRd
console_tool_line = function(call, result = NULL, session = NULL, width = cli::console_width()) {
  sid = if (inherits(session, "gptr_session")) session_data(session)$id else NULL
  spec = tryCatch(registry_get("tool", call$name %||% "", session = sid), error = function(e) NULL)
  if (!is.null(spec) && is.function(spec$render)) {
    out = tryCatch(spec$render(call, result, width), error = function(e) NULL)
    if (is.character(out)) return(console_fit(console_escape(out, FALSE), width))
  }
  if (is.null(result)) return(console_fit(console_call_line(call), width))
  console_fit(console_result_lines(call, result), width)
}

#' The NS-8 artifact line (IC-71): `artifact  <id>  ->  <url>   (running in background)`
#' @noRd
console_artifact_line = function(id, url) {
  paste0("artifact  ", console_escape(id %||% "?", FALSE), "  ->  ",
         console_escape(url %||% "?", FALSE), "   (running in background)")
}

#' Tokens of usage rows (input, output and cache columns)
#' @noRd
console_tokens = function(usage) {
  if (!is.data.frame(usage) || !nrow(usage)) return(0)
  cols = intersect(c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h"),
                   names(usage))
  sum(vapply(cols, function(k) sum(as.numeric(usage[[k]]), na.rm = TRUE), 0))
}

#' 1234 -> "1.2k"
#' @noRd
console_format_tokens = function(n) {
  if (n >= 1e6) return(sprintf("%.1fM", n / 1e6))
  if (n >= 1e3) return(sprintf("%.1fk", n / 1e3))
  format(round(n))
}

#' The status line printed when a foreground run ends:
#' `  done . 2 turns . 1.2k tokens . $0.0042` (status and reason when the run did not end idle)
#' @noRd
console_status_line = function(status, reason = NULL, usage = NULL, turns = NULL) {
  sym = console_symbols()
  word = if (identical(status, "idle")) "done" else as.character(status %||% "?")
  if (!identical(status, "idle") && is.character(reason) && length(reason) == 1L &&
        nzchar(reason)) {
    word = paste0(word, ": ", console_escape(reason, FALSE))
  }
  cost = if (is.data.frame(usage) && "cost" %in% names(usage)) {
    sum(as.numeric(usage$cost), na.rm = TRUE)
  } else {
    0
  }
  n = suppressWarnings(as.integer(turns %||% NA_integer_))
  parts = c(word,
            if (length(n) == 1L && !is.na(n)) paste0(n, if (n == 1L) " turn" else " turns"),
            paste0(console_format_tokens(console_tokens(usage)), " tokens"),
            sprintf("$%.4f", cost))
  paste0("  ", paste(parts, collapse = sym$sep))
}

#' Show custom entries appended during a run through `renderer` records (IC-69)
#' @noRd
console_render_custom = function(s, n0) {
  d = session_data(s)
  entries = d$entries
  if (length(entries) <= n0) return(invisible(NULL))
  live = session_live(s)
  ctx = if (is.null(live)) NULL else live$ctx
  for (e in entries[seq.int(n0 + 1L, length(entries))]) {
    if (!identical(e$type, "custom") || !is.character(e$custom_type)) next
    spec = tryCatch(registry_get("renderer", e$custom_type, session = d$id),
                    error = function(err) NULL)
    if (is.null(spec) || !is.function(spec$render)) next
    out = tryCatch(spec$render(e, cli::console_width(), ctx), error = function(err) NULL)
    if (is.character(out) && length(out)) console_write(console_escape(out, FALSE))
  }
  invisible(NULL)
}

#' agent_start: track the run (any verbosity: the interrupt policy needs the session of a run)
#' @noRd
console_on_agent_start = function(event, ctx) {
  s = ctx$session
  run = event$run
  if (!inherits(s, "gptr_session") || !is.character(run) || length(run) != 1L) return(NULL)
  console_track(run, s)
  NULL
}

#' before_request: start the spinner; at verbosity 3 also a request line
#' @noRd
console_on_before_request = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  if (verbosity() >= 3L) {
    console_pause_one(rec)
    line = paste0("  request ", console_escape(event$request_id %||% "", FALSE), " -> ",
                  console_escape(event$model %||% "", FALSE), " (~",
                  format(round(as.numeric(event$tokens_est %||% 0))), " tokens)")
    console_write(cli::col_grey(line))
  }
  console_spinner_start(rec)
  NULL
}

#' message_update: stream text deltas through the markdown renderer; thinking at verbosity 3
#' @noRd
console_on_message_update = function(event, ctx) {
  rec = console_record(event)
  delta = event$delta
  if (is.null(rec) || !is.character(delta) || !length(delta) || !console_render_on(rec)) {
    return(NULL)
  }
  kind = event$kind %||% "text"
  if (identical(kind, "text")) {
    console_spinner_stop(rec)
    if (!is.null(rec$think)) {
      rec$think$finish()
      rec$think = NULL
    }
    if (is.null(rec$md)) rec$md = render_markdown_stream()
    rec$md$write(delta)
    rec$streamed = TRUE
  } else if (identical(kind, "thinking") && verbosity() >= 3L) {
    console_spinner_stop(rec)
    if (is.null(rec$think)) {
      console_write(cli::col_grey("  (thinking)"))
      rec$think = render_markdown_stream()
    }
    rec$think$write(delta)
  }
  NULL
}

#' message_end: close the streamed answer (or print it whole when nothing was streamed); for a
#' tool result, the result lines
#' @noRd
console_on_message_end = function(event, ctx) {
  rec = console_record(event)
  msg = event$message
  if (is.null(rec) || !is.list(msg) || !console_render_on(rec)) return(NULL)
  if (identical(msg$role, "assistant")) {
    console_spinner_stop(rec)
    if (!is.null(rec$think)) {
      rec$think$finish()
      rec$think = NULL
    }
    if (!is.null(rec$md)) {
      rec$md$finish()
      rec$md = NULL
    } else if (!isTRUE(rec$streamed)) {
      console_print_text(console_msg_text(msg))
    }
    rec$streamed = FALSE
  } else if (identical(msg$role, "tool_result")) {
    key = paste0("t", msg$tool_call_id %||% "")
    call = get0(key, envir = rec$tools, inherits = FALSE) %||%
      list(id = msg$tool_call_id %||% "", name = msg$tool_name %||% "?", input = list())
    if (exists(key, envir = rec$tools, inherits = FALSE)) rm(list = key, envir = rec$tools)
    result = c(msg[c("content", "is_error", "details")], list(elapsed = call$elapsed))
    console_write(console_tool_line(call, result, rec$session))
  }
  NULL
}

#' tool_execution_start: one line per call (verbosity 2) or a progress line (verbosity 1)
#' @noRd
console_on_tool_start = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_foreground(rec)) return(NULL)
  call = list(id = event$tool_call_id %||% "", name = event$tool_name %||% "?",
              input = event$input %||% list())
  v = verbosity()
  if (v == 1L) {
    first = strsplit(console_tool_preview(call$input), "\n", fixed = TRUE)[[1L]]
    gptr_inform(paste0("gptr: ", console_escape(call$name, FALSE), "  ",
                       console_escape(if (length(first)) first[[1L]] else "", FALSE)),
                "progress")
    return(NULL)
  }
  if (v < 2L) return(NULL)
  assign(paste0("t", call$id), call, envir = rec$tools)
  console_pause_one(rec)
  console_write(console_tool_line(call, NULL, rec$session))
  NULL
}

#' tool_execution_end: print the artifact lines queued while the tool ran (once no tool executes
#' on the stack), remember the elapsed time for the result line
#' @noRd
console_on_tool_end = function(event, ctx) {
  console_artifact_flush()
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  key = paste0("t", event$tool_call_id %||% "")
  call = get0(key, envir = rec$tools, inherits = FALSE)
  if (!is.null(call)) {
    call$elapsed = event$elapsed
    assign(key, call, envir = rec$tools)
  }
  if (verbosity() == 1L && isTRUE(event$is_error) && console_foreground(rec)) {
    gptr_inform(paste0("gptr: ", console_escape(event$tool_name %||% "?", FALSE), " failed"),
                "progress")
  }
  NULL
}

#' permission_request: end partial lines before the UI asks. Returns NULL (no decision); never
#' fails, because a failing permission_request handler denies (04 section 10.7)
#' @noRd
console_on_permission = function(event, ctx) {
  tryCatch(console_render_pause(), error = function(e) NULL)
  NULL
}

#' retry_start: say that a request is retried
#' @noRd
console_on_retry = function(event, ctx) {
  rec = console_record(event)
  if (is.null(rec) || !console_render_on(rec)) return(NULL)
  console_pause_one(rec)
  delay = suppressWarnings(as.numeric(event$delay %||% 0))
  console_write(cli::col_grey(paste0("  retrying in ", format(round(delay, 1)), " s (",
                                     console_escape(event$class %||% "error", FALSE), ")")))
  NULL
}

#' agent_end: close the streams, show custom entries and the status line, forget the run; artifact
#' lines still queued (a tool that was interrupted) are printed last
#' @noRd
console_on_agent_end = function(event, ctx) {
  on.exit(console_artifact_flush(), add = TRUE)
  rec = console_record(event)
  if (is.null(rec)) return(NULL)
  on.exit(console_drop(rec$run), add = TRUE)
  console_spinner_stop(rec)
  if (!console_foreground(rec)) return(NULL)
  line = console_status_line(event$status, event$reason, event$usage, event$turns)
  v = verbosity()
  if (v == 1L) {
    gptr_inform(paste0("gptr:", sub("^ +", " ", line)), "progress")
    return(NULL)
  }
  if (v < 2L) return(NULL)
  if (!is.null(rec$think)) rec$think$finish()
  if (!is.null(rec$md)) rec$md$finish()
  rec$think = NULL
  rec$md = NULL
  console_render_custom(rec$session, rec$n0)
  console_write(cli::col_grey(line))
  NULL
}

#' artifact_start: the NS-8 line at verbosity >= 1 (stdout at 2, progress on stderr at 1)
#'
#' The event usually fires inside the model's `r` code (`peter$app()`), whose stdout and messages
#' P09's evaluator captures into the tool result, which already shows the handle. While a tool
#' executes (`run_current()` non-NULL) the line is therefore queued in `console_state()` and
#' printed by the tool_execution_end hook (or at agent_end) once no tool executes on the stack.
#' @noRd
console_on_artifact_start = function(event, ctx) {
  if (verbosity() < 1L) return(NULL)
  line = console_artifact_line(event$id, event$url)
  if (!is.null(run_current())) {
    st = console_state()
    st$artifacts = c(st$artifacts, line)
    return(NULL)
  }
  console_artifact_emit(line)
}

#' Print NS-8 lines at the current verbosity (stdout at 2 or 3, progress on stderr at 1)
#' @noRd
console_artifact_emit = function(lines) {
  v = verbosity()
  for (line in lines) {
    if (v == 1L) {
      gptr_inform(line, "progress")
    } else if (v >= 2L) {
      console_write(line)
    }
  }
  NULL
}

#' Print the queued NS-8 lines once no tool executes on the stack (outside any evaluator capture)
#' @noRd
console_artifact_flush = function() {
  st = console_state()
  lines = st$artifacts
  if (!length(lines) || !is.null(run_current())) return(invisible(NULL))
  st$artifacts = NULL
  console_artifact_emit(lines)
  invisible(NULL)
}

#' session_shutdown: forget every run of the session
#' @noRd
console_on_shutdown = function(event, ctx) {
  sid = event$session
  active = console_state()$active
  for (id in ls(active, all.names = TRUE)) {
    rec = get(id, envir = active)
    s = rec$session
    if (inherits(s, "gptr_session") && identical(session_data(s)$id, sid)) console_drop(id)
  }
  NULL
}

#' The renderer hooks registered by builtin_console() (04 section 7.14)
#' @noRd
console_hooks = function() {
  list(
    gptr_hook("agent_start", console_on_agent_start),
    gptr_hook("before_request", console_on_before_request),
    gptr_hook("message_update", console_on_message_update),
    gptr_hook("message_end", console_on_message_end),
    gptr_hook("tool_execution_start", console_on_tool_start),
    gptr_hook("tool_execution_end", console_on_tool_end),
    gptr_hook("permission_request", console_on_permission),
    gptr_hook("retry_start", console_on_retry),
    gptr_hook("agent_end", console_on_agent_end),
    gptr_hook("artifact_start", console_on_artifact_start),
    gptr_hook("session_shutdown", console_on_shutdown)
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 62 ]` (UTF-8 locale; `LC_ALL=C` gives `SKIP 1 | PASS 58`).

- [ ] **Step 5: Commit**

```bash
git add R/console-render.R tests/testthat/test-console-render.R
git commit -m "feat(console): add the renderer hooks, tool and status lines"
```

---

### Task 3: The interrupt policy and the pause menu

**Files:**
- Create: `R/console-interrupt.R`
- Test: `tests/testthat/test-console-interrupt.R` (create)

**Interfaces:**
- Consumes: Tasks 1-2 (`console_escape()`, `console_notice()`, `console_render_pause()`, `console_state()`, `console_track()`, `console_drop()`); P01 `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_has(name)`, `ext_service_get(name)`, `gptr_can_prompt()`, `gptr_readline(prompt = "")`, `front_end()`, `check_function()`, `check_choice()`, `as_utf8()`, `ev_new()`; P02 `ev_dispatch(event, payload, session = NULL, ctx = NULL)` (`input` is a transform chain: `list(action = "continue" | "transform" | "handled", text)`); P04 `reactor_timer(at, fn, run = NULL)`, `reactor_now()`; P06 kernel SDK `session_data(s)` (`queue`, `dropped`, `id`), `session_live(s)` (`run`), `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())` (source `"pause_menu"`, IC-55), `run_abort(run, reason = "user")`, `run_current()`; the `gptr_run` fields `id`, `status`, `opts$background` (04 section 7.6); the service `bg.register` = `function(session) invisible(session)` (P21). Tests: P04 `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`; P02 `gptr_register()`, `gptr_hook()`.
- Produces (04 section 7.14, 7.0): `with_interrupt_policy(expr_fun, runs, mode = c("call", "repl"))`, registered as the service `console.interrupt_policy` (provided by P14, owned by `builtin:console`; consumed by P06 `session_run()`, P08's SDK pumps and P21's idle ticks); `console_repl_find()` (the innermost REPL state on the call stack: a frame binding `.gptr_repl`), `console_ask(prompt)`, `policy_find()`, `policy_active(run)`, `policy_enqueue(s, text, as)`, `console_menu_available()`.

The policy is report 18's verified pattern (section 2.2.2; seven SIGINT scenarios passed in Appendix A.8) with G3's menu fixes: `tryCatch(withCallingHandlers(expr_fun(), interrupt = <menu>), interrupt = <abort>)`; the menu writes to stderr because it can run inside a tool's stdout capture, and it resumes through R's `resume` restart (report 02 section 5.4: restarts `resume` and `abort` are offered; a resumed `Sys.sleep()` completes). Only the outermost policy on the stack shows a menu: a nested call (a sub-agent inside a tool, the gateway's pump inside a REPL turn) adds its runs to the outer one, so no exiting handler sits between the menu and the code; the REPL binds `.gptr_interrupt_barrier` around a prompt, making that prompt's policy the outermost one. The runs present when the interrupt arrived are remembered, because nested policies drop theirs while the stack unwinds to the exiting handler. Abort calls `run_abort()` for every active run (transfers cancelled, children aborted, the partial turn kept with `stop_reason = "aborted"`, queued items moved to `dropped`, which are then listed), and in mode `"call"` re-signals the interrupt (`signalCondition()` then the `abort` restart) so loops stop; mode `"repl"` returns `NULL`. The menu needs someone to answer (`gptr_can_prompt()`, IC-43) and a console where resuming is verified (terminal R, also in VS Code); RStudio, Positron, Rgui, Jupyter and knitr are abort-only (03 section 6.2). `[b]ackground` is offered for foreground calls (mode `"call"`) when the `bg.register` service exists. Steer and follow-up text passes the `input` event (source `"steer"`) and enters the queue with source `"pause_menu"` (IC-49, IC-55); when the interrupt hit a tool, P06 refuses steering from inside the session's own `r` frames, so the item is queued from a reactor timer as soon as no tool is executing, which is still before the next request (INFRA-12).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-console-interrupt.R`:

```r
# tests/testthat/test-console-interrupt.R -- the interrupt policy and the pause menu (plan P14).
# Task 3: menu, steering, abort and nesting with simulated interrupts. Task 7 appends the
# INFRA-03 test with real SIGINTs.

# A simulated Ctrl-C: an `interrupt` condition with a `resume` restart, as R's onintr() signals
# it during a computation (report 18 section 2.2.1). One that is neither resumed nor caught fails
# the test instead of jumping to the top level.
fake_interrupt = function() {
  cnd = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  resumed = withRestarts({
    signalCondition(cnd)
    FALSE
  }, resume = function() TRUE)
  if (!isTRUE(resumed)) stop("the interrupt was neither resumed nor caught")
  invisible(TRUE)
}

# Menu answers for gptr_readline(), in order (a function answer is called: it may signal a
# second interrupt); a terminal front end where someone can answer
local_menu_answers = function(answers, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$answers = as.list(answers)
  log$prompts = character()
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    log$prompts = c(log$prompts, prompt)
    a = if (length(log$answers)) log$answers[[1L]] else "a"
    log$answers = log$answers[-1L]
    if (is.function(a)) a() else a
  }, front_end = function() "terminal", .env = .env)
  local_gptr_options(interactive = TRUE, .env = .env)
  log
}

# run_abort() replaced by a recorder (the runs below are stand-ins with the 04 section 7.6
# fields the policy reads: id, status, opts)
local_abort_log = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$aborted = character()
  testthat::local_mocked_bindings(run_abort = function(run, reason = "user") {
    log$aborted = c(log$aborted, run$id)
    run$status = "aborted"
    invisible(run)
  }, .env = .env)
  log
}

stand_in_run = function(id = "u0000run1", status = "streaming", background = FALSE) {
  run = new.env(parent = emptyenv())
  run$id = id
  run$status = status
  run$opts = list(background = background)
  class(run) = "gptr_run"
  run
}

policy_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

local_tracked = function(run, s, .env = parent.frame()) {
  console_track(run$id, s)
  withr::defer(console_drop(run$id), envir = .env)
  invisible(run)
}

notices = function(expr) {
  utils::capture.output(expr, type = "message")
}

test_that("continue resumes the interrupted computation", {
  log = local_menu_answers("c")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "finished"
    }, list(), mode = "call")
  })
  expect_identical(res, "finished")
  expect_true(any(grepl("[gptr] paused: [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_true(any(grepl("[gptr] continuing", err, fixed = TRUE)))
})

test_that("steer and follow-up queue the text with source pause_menu (IC-55)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  log = local_menu_answers(c("s", "use only mpg", "f", "then plot it"))
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      fake_interrupt()
      "done"
    }, list(run), mode = "call")
  })
  expect_identical(res, "done")
  q = session_data(s)$queue
  expect_identical(q$steer[[1L]]$text, "use only mpg")
  expect_identical(q$steer[[1L]]$source, "pause_menu")
  texts = vapply(q$follow_up, function(i) i$text, "")
  expect_true("then plot it" %in% texts)
  expect_true(any(grepl("[s]teer, [f]ollow-up, [c]ontinue, [a]bort", err, fixed = TRUE)))
  expect_identical(log$prompts, c("? ", "steer> ", "? ", "follow-up> "))
})

test_that("pause-menu text passes the input event with source steer", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (identical(event$source, "steer")) list(action = "transform", text = toupper(event$text))
  }))
  withr::defer(off())
  local_menu_answers(c("s", "use mpg"))
  notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "call"))
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "USE MPG")
})

test_that("abort in mode repl aborts the runs and returns NULL", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = "not set"
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
  expect_true(any(grepl("[gptr] aborted; the session is kept.", err, fixed = TRUE)))
})

test_that("abort in mode call re-signals the interrupt so loops stop", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  local_menu_answers("a")
  res = NULL
  notices({
    res = tryCatch(with_interrupt_policy(function() {
      fake_interrupt()
      "not reached"
    }, list(run), mode = "call"), interrupt = function(e) "outer handler saw it")
  })
  expect_identical(res, "outer handler saw it")
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("a second Ctrl-C while the menu waits aborts", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  second = function() {
    signalCondition(structure(class = c("interrupt", "condition"),
                              list(message = "", call = NULL)))
    "c"
  }
  local_menu_answers(list(second))
  res = "not set"
  notices({
    res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
  })
  expect_null(res)
  expect_identical(aborted$aborted, "u0000run1")
})

test_that("the policy is abort-only where resuming is unverified (RStudio, Rgui, Jupyter)", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  aborted = local_abort_log()
  log = local_menu_answers("c")
  for (fe in c("rstudio", "rgui", "jupyter")) {
    local_mocked_bindings(front_end = function() fe)
    run$status = "streaming"
    res = "not set"
    notices({
      res = with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl")
    })
    expect_null(res)
  }
  expect_identical(log$prompts, character())
  expect_identical(aborted$aborted, rep("u0000run1", 3L))
})

test_that("nested policies show one menu and the inner runs join the outer one", {
  s = policy_session()
  outer_run = local_tracked(stand_in_run("u0000run1"), s)
  inner_run = local_tracked(stand_in_run("u0000run2"), s)
  aborted = local_abort_log()
  log = local_menu_answers("a")
  box = new.env(parent = emptyenv())
  res = "not set"
  notices({
    res = with_interrupt_policy(function() {
      with_interrupt_policy(function() {
        box$seen = vapply(policy_find()$runs, function(r) r$id, "")
        fake_interrupt()
      }, list(inner_run), mode = "call")
    }, list(outer_run), mode = "repl")
  })
  expect_null(res)
  expect_identical(box$seen, c("u0000run1", "u0000run2"))
  expect_identical(log$prompts, "? ")
  expect_setequal(aborted$aborted, c("u0000run1", "u0000run2"))
})

test_that("[b]ackground hands a foreground run to bg.register (P21) and resumes", {
  s = policy_session()
  run = local_tracked(stand_in_run(), s)
  old = the$services
  withr::defer({
    the$services = old
  })
  got = new.env(parent = emptyenv())
  ext_service_set("bg.register", function(session) {
    got$session = session
    invisible(session)
  }, provided_by = "test")
  local_menu_answers("b")
  res = NULL
  err = notices({
    res = with_interrupt_policy(function() {
      fake_interrupt()
      "kept running"
    }, list(run), mode = "call")
  })
  expect_identical(res, "kept running")
  expect_identical(got$session, s)
  expect_true(any(grepl("[b]ackground", err, fixed = TRUE)))
  local_menu_answers(c("b", "c"))
  err = notices(with_interrupt_policy(function() fake_interrupt(), list(run), mode = "repl"))
  expect_false(any(grepl("[b]ackground", err, fixed = TRUE)))
})

test_that("a steer typed while a tool runs is queued once no tool is on the stack", {
  s = policy_session()
  tool_run = stand_in_run("u0000tool")
  local({
    local_mocked_bindings(run_current = function() tool_run)
    notices(policy_enqueue(s, "after the tool", "steer"))
    expect_length(session_data(s)$queue$steer, 0L)
  })
  reactor_pump(until = function() length(session_data(s)$queue$steer) > 0L, slice_ms = 10L,
               timeout = 5)
  expect_identical(session_data(s)$queue$steer[[1L]]$text, "after the tool")
  expect_identical(session_data(s)$queue$steer[[1L]]$source, "pause_menu")
})

test_that("the policy is the console.interrupt_policy service of builtin:console", {
  expect_identical(the$services[["console.interrupt_policy"]]$provided_by, "P14")
  expect_identical(the$services[["console.interrupt_policy"]]$builtin, "console")
  expect_identical(names(formals(the$services[["console.interrupt_policy"]]$fun)),
                   c("expr_fun", "runs", "mode"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-interrupt$")'
```

Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `could not find function "with_interrupt_policy"` (and `policy_enqueue`), and the service test fails three times because no `console.interrupt_policy` service is registered.

- [ ] **Step 3: Write the implementation**

Create `R/console-interrupt.R`:

```r
# console-interrupt.R -- P14 Console and front ends (layer L5, area console).
# The interrupt policy of every blocking gptr call (INFRA-03, REQ-38; architecture 6.2; contract
# 7.14), provided to P06 (session_run()), P08 (the SDK pumps) and P21 (idle ticks) as the
# `console.interrupt_policy` service. Ctrl-C opens a pause menu through R's `resume` restart:
# [s]teer, [f]ollow-up, [c]ontinue, [a]bort, and [b]ackground for foreground calls when the
# `bg.register` service (P21) exists; a second Ctrl-C while the menu waits aborts. Abort cancels
# the runs (run_abort(): transfers, children, the partial turn with stop_reason "aborted") and,
# in mode "call", re-signals the interrupt so loops stop. Pattern and fixes from report 18
# sections 2.2.2 and 4.6 and G3 (5): menu text goes to stderr (the handler may run inside a
# tool's stdout capture); no exiting interrupt handler sits between the menu and the code (a
# nested policy only adds its runs to the outermost one); where the resume restart is not
# verified (Rgui, RStudio, Positron, Jupyter, knitr) the policy is abort-only.

#' Run `expr_fun()` under the console interrupt policy
#'
#' @param expr_fun Zero-argument function doing the blocking work (a reactor pump).
#' @param runs `gptr_run` objects (or sessions, meaning their current run) this call waits for.
#' @param mode `"call"` re-signals the interrupt after an abort; `"repl"` returns `NULL`.
#' @return The value of `expr_fun()`, or `NULL` after an abort in mode `"repl"`.
#' @noRd
with_interrupt_policy = function(expr_fun, runs, mode = c("call", "repl")) {
  check_function(expr_fun, "expr_fun")
  mode = check_choice(mode, c("call", "repl"), "mode")
  runs = policy_as_runs(runs)
  outer = policy_find()
  if (!is.null(outer)) {
    n0 = length(outer$runs)
    outer$runs = c(outer$runs, runs)
    on.exit(policy_drop_runs(outer, n0), add = TRUE)
    return(expr_fun())
  }
  pol = policy_new(runs, mode)
  .gptr_interrupt_policy = pol
  tryCatch(
    withCallingHandlers(expr_fun(), interrupt = function(cnd) policy_menu(cnd, pol)),
    interrupt = function(cnd) policy_abort(cnd, pol)
  )
}

on_load(ext_service_set("console.interrupt_policy", with_interrupt_policy,
                        provided_by = "P14", builtin = "console"))

#' A fresh policy state
#' @noRd
policy_new = function(runs, mode) {
  pol = new.env(parent = emptyenv())
  pol$runs = runs
  pol$mode = mode
  pol
}

#' Normalise `runs`: a run, a session (its current run) or a list of either; NULLs dropped
#' @noRd
policy_as_runs = function(runs) {
  if (is.null(runs)) return(list())
  if (inherits(runs, "gptr_run") || inherits(runs, "gptr_session")) runs = list(runs)
  out = list()
  for (r in as.list(runs)) {
    if (inherits(r, "gptr_session")) {
      live = session_live(r)
      r = if (is.null(live)) NULL else live$run
    }
    if (inherits(r, "gptr_run")) out[[length(out) + 1L]] = r
  }
  out
}

#' @noRd
policy_drop_runs = function(pol, n) {
  pol$runs = if (n > 0L) pol$runs[seq_len(n)] else list()
  invisible(NULL)
}

#' The outermost active policy on the call stack below the innermost console barrier, or NULL
#'
#' Walks frames with sys.frame(k) (never sys.frames(), G3 capture rule 6) and reads two marker
#' bindings with get0(inherits = FALSE). The REPL binds `.gptr_interrupt_barrier` around each
#' input, so the policy of a prompt's run is the outermost one there.
#' @noRd
policy_find = function() {
  k = sys.nframe() - 1L
  found = NULL
  while (k >= 1L) {
    env = sys.frame(k)
    pol = get0(".gptr_interrupt_policy", envir = env, inherits = FALSE)
    if (!is.null(pol)) found = pol
    if (isTRUE(get0(".gptr_interrupt_barrier", envir = env, inherits = FALSE))) break
    k = k - 1L
  }
  found
}

#' Is a run still active? (04 section 7.6 statuses before settlement)
#' @noRd
policy_active = function(run) {
  isTRUE(run$status %in% c("queued", "requesting", "streaming", "tools", "boundary"))
}

#' The active runs of a policy with their sessions (from the console state of Task 2)
#' @noRd
policy_targets = function(pol) {
  out = list()
  active = console_state()$active
  for (r in pol$runs) {
    if (!policy_active(r)) next
    rec = get0(r$id, envir = active, inherits = FALSE)
    out[[length(out) + 1L]] = list(run = r, session = if (is.null(rec)) NULL else rec$session)
  }
  out
}

#' Whether the pause menu can be offered here (else the policy is abort-only)
#'
#' Needs someone to answer (gptr_can_prompt(), IC-43) and a console where resuming an interrupt
#' is verified: terminal R (also inside VS Code); Rgui, RStudio, Positron, Jupyter and knitr are
#' abort-only (03 section 6.2, report 18 section 2.1.6).
#' @noRd
console_menu_available = function() {
  isTRUE(gptr_can_prompt()) && front_end() %in% c("terminal", "vscode", "unknown")
}

#' The innermost console REPL state on the call stack (a frame binding `.gptr_repl`), or NULL
#'
#' The REPL (console-repl.R) and the `jsonl` frontend bind their state under this name; the pause
#' menu, the slash commands and the context-block providers find it here without any package
#' state (G3 capture rule 6: frames are walked with sys.frame(k)).
#' @noRd
console_repl_find = function() {
  k = sys.nframe() - 1L
  while (k >= 1L) {
    rs = get0(".gptr_repl", envir = sys.frame(k), inherits = FALSE)
    if (is.environment(rs)) return(rs)
    k = k - 1L
  }
  NULL
}

#' Read one answer for the menu; Ctrl-C while waiting (no resume restart there) gives NA
#'
#' Inside a REPL driven by `.stdin = TRUE` the answer comes from the REPL's connection (one
#' persistent stdin, report 18 2.1.3), else from gptr_readline().
#' @noRd
console_ask = function(prompt) {
  rs = console_repl_find()
  tryCatch({
    x = if (!is.null(rs) && isTRUE(rs$stdin) && !is.null(rs$reader)) {
      rs$reader$read(prompt, stream = "stderr")
    } else {
      gptr_readline(prompt)
    }
    if (length(x) != 1L || is.na(x)) NA_character_ else as_utf8(x)
  }, interrupt = function(e) NA_character_)
}

#' The pause menu (calling handler for `interrupt`)
#'
#' Returns normally to let the policy's exiting handler abort; resumes the interrupted
#' computation with invokeRestart("resume") for steer, follow-up, continue and background.
#' @noRd
policy_menu = function(cnd, pol) {
  # the runs at the moment of the interrupt: nested policies drop theirs while the stack unwinds
  # to the exiting handler, which must still abort them
  pol$abort_runs = pol$runs
  if (is.null(findRestart("resume", cnd)) || !console_menu_available()) return(invisible(NULL))
  console_render_pause()
  targets = Filter(function(t) !is.null(t$session), policy_targets(pol))
  s = if (length(targets)) targets[[1L]]$session else NULL
  run = if (length(targets)) targets[[1L]]$run else NULL
  bg = !is.null(s) && identical(pol$mode, "call") && ext_service_has("bg.register") &&
    !isTRUE(run$opts$background)
  choices = if (is.null(s)) {
    "[c]ontinue, [a]bort"
  } else {
    paste0("[s]teer, [f]ollow-up, [c]ontinue, [a]bort", if (bg) ", [b]ackground" else "")
  }
  who = if (is.null(s)) "" else paste0(" ", session_data(s)$id)
  tries = 0L
  repeat {
    console_notice("[gptr] paused", who, ": ", choices)
    ans = console_ask("? ")
    key = if (is.na(ans)) "a" else tolower(substr(trimws(ans), 1L, 1L))
    if (key %in% c("", "c")) {
      console_notice("[gptr] continuing")
      invokeRestart("resume")
    }
    if (identical(key, "a")) return(invisible(NULL))
    if (!is.null(s) && key %in% c("s", "f")) {
      text = console_ask(if (identical(key, "s")) "steer> " else "follow-up> ")
      if (is.na(text)) return(invisible(NULL))
      policy_enqueue(s, text, if (identical(key, "s")) "steer" else "follow_up")
      invokeRestart("resume")
    }
    if (bg && identical(key, "b")) {
      ext_service_get("bg.register")(s)
      console_notice("[gptr] running in the background; gptr_wait() brings it back")
      invokeRestart("resume")
    }
    tries = tries + 1L
    if (tries >= 3L) {
      console_notice("[gptr] continuing")
      invokeRestart("resume")
    }
    console_notice("[gptr] please answer with one of the letters shown")
  }
}

#' Queue pause-menu text on the session (IC-49, IC-55: source "pause_menu")
#'
#' The text passes the `input` event (source "steer", a transform chain) first. When the menu
#' interrupted a tool (an `r` evaluation is on the stack), P06 refuses steering from inside the
#' session's own tool frames (IC-55), so the item is queued from a reactor timer as soon as no
#' tool is executing: it still arrives before the next request, after the tool result (INFRA-12).
#' @noRd
policy_enqueue = function(s, text, as) {
  text = as_utf8(text)
  if (!nzchar(trimws(text))) {
    console_notice("[gptr] nothing queued; continuing")
    return(invisible(FALSE))
  }
  ev = ev_dispatch("input", ev_new("input", text = text, source = "steer"), session = s)
  if (is.list(ev) && identical(ev$action, "handled")) return(invisible(FALSE))
  if (is.list(ev) && identical(ev$action, "transform") && is.character(ev$text) &&
        length(ev$text) == 1L) {
    text = ev$text
  }
  if (is.null(run_current())) {
    session_enqueue(s, text, as = as, source = "pause_menu")
  } else {
    policy_defer_enqueue(s, text, as)
  }
  console_notice(if (identical(as, "steer")) {
    "[gptr] steering message queued; it is delivered after the current tool results"
  } else {
    "[gptr] follow-up queued; it is sent when the agent would stop"
  })
  invisible(TRUE)
}

#' Queue an item from a reactor timer once no tool is executing on the stack
#' @noRd
policy_defer_enqueue = function(s, text, as) {
  force(s)
  force(text)
  force(as)
  fire = function() {
    if (!is.null(run_current())) {
      reactor_timer(at = reactor_now() + 0.05, fn = fire)
      return(invisible(NULL))
    }
    tryCatch(session_enqueue(s, text, as = as, source = "pause_menu"), error = function(e) {
      console_notice("[gptr] the queued message could not be delivered: ",
                     console_escape(conditionMessage(e), FALSE))
    })
    invisible(NULL)
  }
  reactor_timer(at = reactor_now(), fn = fire)
  invisible(NULL)
}

#' Abort (exiting handler for `interrupt`): abort the runs, report dropped queue items, and in
#' mode "call" re-signal the interrupt
#' @noRd
policy_abort = function(cnd, pol) {
  if (!is.null(pol$abort_runs)) pol$runs = pol$abort_runs
  targets = policy_targets(pol)
  sessions = Filter(Negate(is.null), lapply(targets, function(t) t$session))
  n_dropped = vapply(sessions, function(s) length(session_data(s)$dropped), 0L)
  suspendInterrupts({
    for (t in rev(targets)) {
      if (policy_active(t$run)) run_abort(t$run, reason = "user")
    }
  })
  console_render_pause()
  console_notice("[gptr] aborted; the session is kept.")
  i = 1L
  while (i <= length(sessions)) {
    dropped = session_data(sessions[[i]])$dropped
    if (length(dropped) > n_dropped[[i]]) {
      new = dropped[seq.int(n_dropped[[i]] + 1L, length(dropped))]
      texts = vapply(new, function(item) as.character(item$text %||% ""), "")
      console_notice("[gptr] dropped queued messages: ",
                     paste(console_escape(paste0("'", texts, "'"), FALSE), collapse = ", "))
    }
    i = i + 1L
  }
  if (identical(pol$mode, "call")) policy_resignal(cnd)
  invisible(NULL)
}

#' Re-signal an interrupt (03 section 6.2: programmatic calls stop loops): enclosing handlers see
#' it; without one the evaluation returns to the top level
#' @noRd
policy_resignal = function(cnd) {
  signalCondition(cnd)
  invokeRestart("abort")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-interrupt$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 36 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/console-interrupt.R tests/testthat/test-console-interrupt.R
git commit -m "feat(console): add the interrupt policy and the pause menu"
```

---

### Task 4: REPL state and the input layer

**Files:**
- Create: `R/console-repl.R`
- Test: `tests/testthat/test-console-repl.R` (create)

**Interfaces:**
- Consumes: Task 1 (`console_escape()`); P01 `check_class()`, `check_env()`, `check_flag()`, `as_utf8()`, `gptr_readline(prompt = "")` (the one readline wrapper, IC-43), `gptr_warn(message, class)`, `%||%`; P06 kernel SDK `session_home(s)`, `setting_get(key, session = NULL, default = NULL)`; the `gptr_session` bindings `$mode`, `$model` (04 section 5.1); P08's `gptr_call` record (04 section 7.8): `ids` (`model`, `mode`, `skills`, `tools`, `plugins`, `extensions`), `args` (`budget`, `opts`, `stdin`, and `envir_given`, the flag P08's capture sets when `envir =` was passed), `context` (items with `kind` and `name`). Tests: P01 `local_gptr_options()`; testthat `local_mocked_bindings()`.
- Produces: `repl_state(session, envir, stdin = FALSE, call = NULL)` -> environment (`session`, `envir`, `envir_given`, `stdin`, `reader`, `render`, `model`, `mode`, `skills`, `tools`, `plugins`, `extensions`, `budget`, `opts`, `attach`, `pending_call` (TRUE until the console call's identifiers and objects reached a prompt, also on a piped session), `notes`, `files`, `next_skills`, `sending`, `mask`, `exit`, `interrupts`, `waiting`); `repl_eval_env(rs)`; `repl_prompt(rs)`, `repl_mode(rs)`, `repl_model(rs)`, `console_model_label(x)`; `console_stdin_open()` (the one place that opens `file("stdin")`; tests mock it); `readline_limit()`; `console_reader(stdin = FALSE, echo = stdin)` -> environment with `read(prompt = "", stream = "stdout")`, `close()`, `flag`; `r_incomplete(code)`; `repl_read_logical(rd, prompt)`; `console_history_add(x)`.

The input layer is report 18's (sections 2.1.2-2.1.3, 4.3, Appendix A.7) with its verified facts: readline() delivers 4,095 bytes on R < 4.5 and 8,190 on R >= 4.5 and silently splits or truncates longer lines, so a line that reaches the limit is warned about (`gptr_warning_readline_limit`) and dropped rather than sent half; under `.stdin = TRUE` one persistent `file("stdin")` connection serves the whole REPL, because a fresh connection per read loses buffered lines, and it is closed on `/exit` and on exit (IC-59). The stdin reader echoes the prompt and the escaped line, so a piped session reads like a terminal session. The grammar (03 section 6.17): a `"""` block is one multi-line prompt, a fenced block is R code (returned as `!code`), `!code` and `!!code` continue with `+ ` while the code is incomplete (detected locale-independently: the parse error of incomplete input points at column 0 of the line after the last, or is an `INCOMPLETE_STRING`), a trailing backslash continues a line, and the end of piped input ends every block. The REPL state takes the console call's resolved identifiers, budget and `.opts` (minus `frontend`) for its first prompt and the call's plain-symbol context objects as attachments (`pending_call`), also when a session was piped in, so `s |> peter(mode = auto)` changes the mode at the first prompt as `s |> peter("...", mode = auto)` would; prompts and `!code` evaluate in the call's explicit `envir`, else the session's kept home, else the call's environment (IC-40).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-console-repl.R`:

```r
# tests/testthat/test-console-repl.R -- the console REPL (plan P14).
# Task 4: REPL state and the input layer; Task 5: `!expr`, notes, mentions and console_send();
# Task 7: scripted console sessions.

# The REPL's persistent stdin connection replaced by a text connection over `lines`
local_console_stdin = function(lines, .env = parent.frame()) {
  testthat::local_mocked_bindings(console_stdin_open = function() textConnection(lines),
                                  .env = .env)
}

# A reader over `lines` (piped input, no echo unless asked)
stdin_reader = function(lines, echo = FALSE, .env = parent.frame()) {
  local_console_stdin(lines, .env = .env)
  rd = console_reader(stdin = TRUE, echo = echo)
  withr::defer(rd$close(), envir = .env)
  rd
}

test_that("the stdin reader reads one line per call and NA at the end", {
  rd = stdin_reader(c("first", "second"))
  expect_identical(rd$read("peter> "), "first")
  expect_identical(rd$read("peter> "), "second")
  expect_identical(rd$read("peter> "), NA_character_)
})

test_that("the stdin reader echoes the prompt and the escaped line when asked", {
  rd = stdin_reader("hello \033", echo = TRUE)
  got = NULL
  out = utils::capture.output({
    got = rd$read("peter> ")
  })
  expect_identical(out, "peter> hello <U+001B>")
  expect_identical(got, "hello \033")
})

test_that("close() closes the stdin connection once (IC-59)", {
  n0 = nrow(showConnections())
  local_console_stdin("x")
  rd = console_reader(stdin = TRUE)
  expect_identical(nrow(showConnections()), n0 + 1L)
  rd$close()
  rd$close()
  expect_identical(nrow(showConnections()), n0)
  expect_identical(rd$read(""), NA_character_)
})

test_that("a triple-quote block is one prompt", {
  rd = stdin_reader(c('"""', "line one", "line two", '"""', "next"))
  expect_identical(repl_read_logical(rd, "peter> "), "line one\nline two")
  expect_identical(repl_read_logical(rd, "peter> "), "next")
  rd = stdin_reader(c('"""one line"""'))
  expect_identical(repl_read_logical(rd, "peter> "), "one line")
})

test_that("a fenced block is R code and ! code continues while incomplete", {
  rd = stdin_reader(c("```r", "x = 1", "y = 2", "```", "!for (i in 1:2) {", "  print(i)", "}",
                      "!!z = 3"))
  expect_identical(repl_read_logical(rd, "peter> "), "!x = 1\ny = 2")
  expect_identical(repl_read_logical(rd, "peter> "), "!for (i in 1:2) {\n  print(i)\n}")
  expect_identical(repl_read_logical(rd, "peter> "), "!!z = 3")
})

test_that("a trailing backslash continues a line; end of input ends every block", {
  rd = stdin_reader(c("first part \\", "second part"))
  expect_identical(repl_read_logical(rd, "peter> "), "first part \nsecond part")
  rd = stdin_reader(c('"""', "unterminated"))
  expect_identical(repl_read_logical(rd, "peter> "), "unterminated")
  expect_identical(repl_read_logical(rd, "peter> "), NA_character_)
  rd = stdin_reader("!f = function() {")
  expect_identical(repl_read_logical(rd, "peter> "), "!f = function() {")
})

test_that("r_incomplete() recognises incomplete code in any locale", {
  expect_true(r_incomplete("for (i in 1:2) {"))
  expect_true(r_incomplete("x = 'abc"))
  expect_false(r_incomplete("x = 1"))
  expect_false(r_incomplete("x = )"))
})

test_that("a line at the readline limit is warned about and dropped", {
  long = strrep("a", readline_limit())
  local_mocked_bindings(gptr_readline = function(prompt = "") long)
  rd = console_reader(stdin = FALSE)
  out = NULL
  expect_warning({
    out = repl_read_logical(rd, "peter> ")
  }, class = "gptr_warning_readline_limit")
  expect_identical(out, "")
  expect_identical(readline_limit(), if (getRversion() >= "4.5.0") 8190L else 4095L)
})

test_that("repl_state() takes the console call's identifiers, options and objects", {
  e = new.env()
  call = list(ids = list(model = "fake/fake-1", mode = "auto", skills = "stats", tools = NULL,
                         plugins = NULL, extensions = NULL),
              args = list(budget = list(cost = 1),
                          opts = list(frontend = "console", max_turns = 5L),
                          envir_given = TRUE),
              context = list(list(label = "mtcars", kind = "symbol", name = "mtcars"),
                             list(label = "..2", kind = "value", name = NULL)))
  rs = repl_state(NULL, e, stdin = FALSE, call = call)
  expect_identical(rs$model, "fake/fake-1")
  expect_identical(rs$mode, "auto")
  expect_identical(rs$opts, list(max_turns = 5L))
  expect_identical(rs$attach, "mtcars")
  expect_identical(rs$budget, list(cost = 1))
  expect_identical(repl_eval_env(rs), e)
  expect_identical(repl_prompt(rs), "peter[auto]> ")
  expect_identical(repl_model(rs), "fake/fake-1")
  rs$mode = NULL
  local_gptr_options(mode = "manual")
  expect_identical(repl_prompt(rs), "peter> ")
  expect_error(repl_state(NULL, "not an env"), class = "gptr_error_invalid_argument")
})

test_that("console_history_add() never fails", {
  expect_null(console_history_add("a prompt"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-repl$")'
```

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 0 ]`; the errors read `could not find function "console_reader"` (and `repl_read_logical`, `r_incomplete`, `repl_state`, `console_history_add`); the helper `local_console_stdin()` fails to mock the absent `console_stdin_open`.

- [ ] **Step 3: Write the implementation**

Create `R/console-repl.R`:

```r
# console-repl.R -- P14 Console and front ends (layer L5, area console).
# The `console` built-in (contract 7.14, 10.3): the REPL behind `peter()` with no prompt (report
# 18 section 4.3), its input grammar (architecture 6.17), the `user_ran` and `user_files` context
# blocks, the `console` frontend and route (order 30) and builtin_console(). Task 4: REPL state
# and the input layer; Task 5: `!expr`, notes, `@mentions` and console_send(); Task 7: the loop,
# the banner, the stdin UI, the frontend, the route and the built-in. Options read here
# (contract 3.1): gptr.max_turns_console (200L, turns per console prompt), gptr.history (TRUE,
# REPL inputs to the console history through utils::timestamp()), gptr.verbose (through
# verbosity()).

# ---------------------------------------------------------------------------------------------
# REPL state
# ---------------------------------------------------------------------------------------------

#' REPL state: an environment (`envir` is reset to NULL when the REPL ends, rule R2)
#'
#' `call` is the gateway's `gptr_call` record of the console call (P08, contract 7.8): its
#' resolved identifiers, budget and `.opts` apply to the first prompt, and its plain-symbol
#' context objects are attached to it.
#' @noRd
repl_state = function(session, envir, stdin = FALSE, call = NULL) {
  check_class(session, "gptr_session", "s", null = TRUE)
  check_env(envir, "envir")
  check_flag(stdin, "stdin")
  rs = new.env(parent = emptyenv())
  rs$session = session
  rs$envir = envir
  rs$envir_given = !is.null(call) && isTRUE(call$args$envir_given)
  rs$stdin = stdin
  rs$reader = NULL
  rs$render = TRUE
  ids = if (is.null(call)) list() else call$ids %||% list()
  rs$model = ids$model
  rs$mode = ids$mode
  rs$skills = ids$skills
  rs$tools = ids$tools
  rs$plugins = ids$plugins
  rs$extensions = ids$extensions
  rs$budget = if (is.null(call)) NULL else call$args$budget
  opts = if (is.null(call)) list() else call$args$opts %||% list()
  opts$frontend = NULL
  rs$opts = opts
  rs$attach = repl_call_symbols(call)
  rs$pending_call = !is.null(call)
  rs$notes = character()
  rs$files = character()
  rs$next_skills = NULL
  rs$sending = NULL
  rs$mask = NULL
  rs$exit = FALSE
  rs$interrupts = 0L
  rs$waiting = 0L
  rs
}

#' Names of the plain-symbol context objects of the console call (attached to the first prompt)
#' @noRd
repl_call_symbols = function(call) {
  if (is.null(call) || !length(call$context)) return(character())
  out = character()
  for (item in call$context) {
    if (identical(item$kind, "symbol") && is.character(item$name)) out = c(out, item$name)
  }
  unique(out)
}

#' Where `!expr` runs and prompts evaluate (IC-40): an explicit `envir` of the console call, else
#' the session's kept home, else the console call's environment
#' @noRd
repl_eval_env = function(rs) {
  if (isTRUE(rs$envir_given) || is.null(rs$session)) return(rs$envir)
  session_home(rs$session) %||% rs$envir
}

#' A display label for a model reference or spec
#' @noRd
console_model_label = function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "gptr_spec")) return(as.character(x$id %||% x$name)[1L])
  as.character(x)[1L]
}

#' @noRd
repl_mode = function(rs) {
  if (!is.null(rs$session)) return(rs$session$mode)
  console_model_label(rs$mode) %||% setting_get("mode", default = "manual")
}

#' @noRd
repl_model = function(rs) {
  if (!is.null(rs$session)) return(rs$session$model)
  console_model_label(rs$model) %||% setting_get("model") %||% "the default model"
}

#' The prompt: "peter> " in manual mode, "peter[auto]> " otherwise
#' @noRd
repl_prompt = function(rs) {
  mode = repl_mode(rs)
  if (identical(mode, "manual")) "peter> " else paste0("peter[", mode, "]> ")
}

# ---------------------------------------------------------------------------------------------
# Input layer (report 18 sections 2.1.2-2.1.3, 4.3 and Appendix A.7)
# ---------------------------------------------------------------------------------------------

#' The persistent stdin connection of `peter(.stdin = TRUE)` (tests mock this function)
#'
#' One connection for the whole REPL: a fresh file("stdin") per read loses buffered lines
#' (report 18 2.1.3). The reader closes it on `/exit` and on exit (IC-59).
#' @noRd
console_stdin_open = function() {
  file("stdin", open = "r")
}

#' The longest console line readline() delivers whole: 4,095 bytes on R < 4.5, 8,190 on
#' R >= 4.5 (report 18 fact-check 2)
#' @noRd
readline_limit = function() {
  if (getRversion() >= "4.5.0") 8190L else 4095L
}

#' A line reader: gptr_readline() (terminal, IDE, IRkernel) or the persistent stdin connection
#'
#' Returns an environment with `read(prompt = "", stream = "stdout")` -> chr(1), or NA at the
#' end of piped input; `close()`; `flag` (TRUE when a raw line reached the readline limit). The
#' stdin reader writes the prompt and echoes the line on `stream` (so a piped session reads like
#' a terminal session) unless `echo = FALSE`.
#' @noRd
console_reader = function(stdin = FALSE, echo = stdin) {
  rd = new.env(parent = emptyenv())
  rd$flag = FALSE
  rd$con = NULL
  rd$echo = isTRUE(echo)
  if (isTRUE(stdin)) {
    rd$con = console_stdin_open()
    rd$read = function(prompt = "", stream = "stdout") {
      if (is.null(rd$con)) return(NA_character_)
      out = if (identical(stream, "stderr")) stderr() else stdout()
      if (rd$echo && nzchar(prompt)) cat(prompt, file = out, sep = "")
      x = readLines(rd$con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(x)) {
        if (rd$echo) cat("\n", file = out)
        return(NA_character_)
      }
      x = as_utf8(x)
      if (rd$echo) cat(console_escape(x, FALSE), "\n", file = out, sep = "")
      x
    }
  } else {
    rd$read = function(prompt = "", stream = "stdout") {
      x = gptr_readline(prompt)
      if (length(x) != 1L || is.na(x)) return(NA_character_)
      x = as_utf8(x)
      if (nchar(x, type = "bytes") >= readline_limit()) {
        rd$flag = TRUE
        gptr_warn(paste0("That line was ", nchar(x, type = "bytes"), " bytes long, at the ",
                         "console limit of ", readline_limit(), " bytes: its end was dropped ",
                         "(on R < 4.5 the next line was merged into it), so it was not sent. ",
                         "Use @file or a \"\"\" block for long input."),
                  "readline_limit")
      }
      x
    }
  }
  rd$close = function() {
    if (!is.null(rd$con)) {
      con = rd$con
      rd$con = NULL
      close(con)
    }
    invisible(NULL)
  }
  rd
}

#' Is R code incomplete (continue reading with "+ ")? Locale-independent: the parse error of an
#' incomplete input points at column 0 of the line after the last, or is an INCOMPLETE_STRING
#' (the messages themselves are translated)
#' @noRd
r_incomplete = function(code) {
  msg = tryCatch({
    parse(text = code, keep.source = FALSE)
    NULL
  }, error = function(e) conditionMessage(e))
  if (is.null(msg)) return(FALSE)
  grepl("INCOMPLETE_STRING", msg, fixed = TRUE) || grepl("^<text>:[0-9]+:0:", msg)
}

#' Read one logical input (report 18 A.7 read_logical_input(), EOF-safe)
#'
#' The grammar of architecture 6.17: a `"""` block is one multi-line prompt; a fenced ```` ``` ````
#' block is R code (returned as `!code`); `!code` and `!!code` continue with "+ " while the code
#' is incomplete; a trailing backslash continues a line. Returns the input, NA at the end of
#' piped input, or "" when a raw line hit the readline limit (the input is dropped).
#' @noRd
repl_read_logical = function(rd, prompt) {
  rd$flag = FALSE
  line = rd$read(prompt)
  if (is.na(line)) return(NA_character_)
  out = line
  if (grepl('^\\s*"""', line)) {
    body = sub('^\\s*"""', "", line)
    while (!grepl('"""\\s*$', body)) {
      x = rd$read("... ")
      if (is.na(x)) break
      body = paste0(body, "\n", x)
    }
    out = trimws(sub('"""\\s*$', "", body))
  } else if (grepl("^\\s*```", line)) {
    body = character()
    repeat {
      x = rd$read("... ")
      if (is.na(x) || grepl("^\\s*```\\s*$", x)) break
      body = c(body, x)
    }
    out = paste0("!", paste(body, collapse = "\n"))
  } else if (startsWith(line, "!")) {
    bang = if (startsWith(line, "!!")) "!!" else "!"
    code = substring(line, nchar(bang) + 1L)
    while (r_incomplete(code)) {
      x = rd$read("+ ")
      if (is.na(x)) break
      code = paste0(code, "\n", x)
    }
    out = paste0(bang, code)
  } else {
    while (grepl("\\\\$", out)) {
      out = sub("\\\\$", "", out)
      x = rd$read("... ")
      if (is.na(x)) break
      out = paste0(out, "\n", x)
    }
  }
  if (isTRUE(rd$flag)) return("")
  out
}

#' Add a REPL input to the console history (report 18: utils::timestamp(); gptr.history)
#' @noRd
console_history_add = function(x) {
  tryCatch(utils::timestamp(stamp = x, prefix = "", suffix = "", quiet = TRUE),
           error = function(e) NULL)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-repl$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 36 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/console-repl.R tests/testthat/test-console-repl.R
git commit -m "feat(console): add the REPL state and the input layer"
```

---

### Task 5: `!expr` passthrough, notes, `@mentions` and `console_send()`

**Files:**
- Modify: `R/console-repl.R` (append)
- Test: `tests/testthat/test-console-repl.R` (append)

**Interfaces:**
- Consumes: Tasks 1-4 (`console_escape()`, `console_notice()`, `console_write()`, `console_repl_find()`, `policy_active()`, `repl_state()`, `repl_eval_env()`); P01 `est_tokens(x, class)` (classes `r_output`, `code`), `clean_terminal()`, `project_root()`, `path_rel()`, `as_utf8()`, `gptr_opt()`, `verbosity()`, `ev_new()`; P02 `ev_dispatch()`, `gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"), budget = 300L, order = 650L)`, `registry_names()`; P03 `redact(x, profile = "context")`; P06 kernel SDK `session_live(s)` (`run`), `run_abort(run, reason = "user")`, `session_home(s)`; P08 kernel SDK `interpolate_prompt(template, envir)` (`$prompt`), the export `peter()` (called as `gptr::peter()`: a context dot that is a plain symbol is read by name from `envir`, never forced, IC-41; `envir =`; `.opts = list(max_turns =)`; the condition field `$session` of a failed call) and `gptr_last()`; the `gptr_call` binding `sys_call` (04 section 7.8), reached from a context block's `ctx$input$call`; P09's service `eval.r` = `function(code, envir, ...)` (04 section 7.0: "`eval_r()` through the `evaluator` kind (IC-69)", consumers "P14 `!expr`"), fetched with P01 `ext_service_has()`/`ext_service_get()`, else the kernel SDK `eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE, max_images = gptr_opt("r_max_images"))` (a `gptr_eval_result`: `status`, `events`, `outputs`; P14 passes `plots = "auto", tee = TRUE, guard = FALSE`), `format_eval_result(res, budget_tokens)` (`$text`); P09's `attached` context block (it describes the objects a call attaches). Tests: P01 `gptr_fake_provider()`, `fake_requests()` (each request's `messages` and `last_user`), `local_project()`, `local_gptr_options()`, `the$services` and `ext_service_set()` (a replaced `eval.r` service, restored on exit); P02 `gptr_hook()`, `gptr_register()`; P08 `peter()` (`.run = FALSE`).
- Produces: `repl_mentions(text, env)` -> `list(files, objects)`, `repl_file_block(path, shown, max_lines = 40L)`, `console_object_visible(name, env)`, `attr_escape(x)`; `repl_note(code, res)`, `console_notes_text(notes, budget = 300L)`, `console_files_text(files, budget = 2000L)`; the context blocks `console_blocks()` (`user_ran`: budget 300, order 550; `user_files`: budget 2000, order 560; placement `both`, authority `data`) with `console_notes_provide(ctx, budget)`, `console_files_provide(ctx, budget)`, `repl_sending(ctx)`; `repl_passthrough(rs, text)` (the `input` event with `source = "passthrough"`, the `console:direct` channel); `console_abort_stray(s)`; `console_call(rs, text)`, `console_call_release(rs)`, `console_send(rs, text)` -> `list(status = "ok" | "error" | "interrupt", value, error)`.

`!code` is the user's own R (report 18 section 4.3): it runs through the `eval.r` service (the evaluator selected by the `evaluator` setting, so a plugin evaluator also serves `!code`; P09's `eval_r()` when the service is absent) in the REPL's environment, shown as it runs, without the permission gate or the code guard, and P14 never classifies it. `!code` leaves a note (the code and its output as `#>` lines, redacted with the `context` profile) that the `user_ran` block adds to the next prompt within 300 tokens, the newest notes first and one over-long note cut from its end (IC-73); `!!code` leaves none. The `input` event may handle or transform the code first (source `"passthrough"`), and the `console:direct` channel tells P15 what ran. `@path` mentions add the first 40 lines of a file (a one-line note for a binary file) to the `user_files` block; `@name` mentions of objects bound in the evaluation environment (up to the global environment, never namespaces) are passed to the gateway as plain symbols, so P09's `attached` block describes them by name and nothing is copied. A prompt is an ordinary gateway call, `gptr::peter(.gptr_session, <@objects>, prompt = "<text>", envir = .gptr_env, .opts = list(max_turns = <gptr.max_turns_console>))`, evaluated in a mask whose parent is the evaluation environment; the first prompt also passes the console call's model, mode, tools, plugins, extensions and budget, and `/skill:<name>` adds `skills =` for one prompt. The two blocks answer only that call: the gateway record's `sys_call` is the call `console_send()` built. `console_call()` binds the evaluation environment but creates no closure (rule R3); after each prompt the mask's bindings are removed and its parent reset to `emptyenv()` (R2). A failed call keeps its session (the condition's `$session`, else a new `gptr_last()`), and an interrupt that hit before the policy did aborts the session's stray run.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-console-repl.R`:

```r
# ---------------------------------------------------------------- Task 5: !expr, notes, mentions

# The console's context blocks for this test unless builtin:console registered them already
local_console_blocks = function(.env = parent.frame()) {
  have = registry_names("context_block")
  for (spec in console_blocks()) {
    if (spec$name %in% have) next
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  invisible(NULL)
}

# Context blocks and text of the last user message a fake provider received, named by kind
last_user_blocks = function(req) {
  users = Filter(function(m) identical(m$role, "user"), req$messages)
  content = users[[length(users)]]$content
  kinds = vapply(content, function(b) if (identical(b$type, "context")) b$kind else b$type, "")
  stats::setNames(vapply(content, function(b) as.character(b$text %||% ""), ""), kinds)
}

test_that("notes keep the newest within the token budget and cut one long note", {
  notes = c("> a\n#> [1] 1", "> b\n#> [1] 2")
  text = console_notes_text(notes, 300L)
  expect_match(text, "^The user ran this R code in the session")
  expect_match(text, "> a\n#> [1] 1\n> b\n#> [1] 2", fixed = TRUE)
  many = vapply(1:200, function(i) paste0("> x", i, "\n#> [1] ", i), "")
  text = console_notes_text(many, 300L)
  expect_lte(est_tokens(text, "r_output"), 300)
  expect_match(text, "> x200", fixed = TRUE)
  expect_false(grepl("> x1\n", text, fixed = TRUE))
  expect_match(text, "earlier omitted", fixed = TRUE)
  long = paste(c("> big", paste0("#> ", strrep("y", 60), seq_len(200))), collapse = "\n")
  text = console_notes_text(long, 300L)
  expect_lte(est_tokens(text, "r_output"), 300)
  expect_match(text, "#> [... output cut]", fixed = TRUE)
  expect_null(console_notes_text(character()))
})

test_that("@mentions: files become <file> blocks, bound names become objects", {
  root = local_project(files = list("data/notes.txt" = c("line one", "line two")))
  e = new.env()
  e$tbl = data.frame(a = 1:3)
  men = repl_mentions("compare @tbl with @data/notes.txt and mail me@example.org", e)
  expect_identical(men$objects, "tbl")
  expect_length(men$files, 1L)
  expect_match(men$files, "<file path=\"data/notes.txt\">\nline one\nline two\n</file>",
               fixed = TRUE)
  expect_identical(repl_mentions("use @c and @nothing", e)$objects, character())
})

test_that("a binary @file is announced, not inlined", {
  root = local_project()
  writeBin(as.raw(c(0x50, 0x00, 0x01)), file.path(root, "blob.bin"))
  men = repl_mentions("look at @blob.bin", new.env())
  expect_match(men$files, "binary=\"true\" bytes=\"3\"", fixed = TRUE)
})

test_that("!code runs in the REPL environment and leaves a note; !!code does not", {
  local_project()
  e = new.env()
  e$x = matrix(1:6, 2)
  rs = repl_state(NULL, e)
  out = utils::capture.output(repl_passthrough(rs, "!dim(x)"))
  expect_true("[1] 2 3" %in% out)
  expect_length(rs$notes, 1L)
  expect_match(rs$notes, "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  utils::capture.output(repl_passthrough(rs, "!!y = sum(x)"))
  expect_identical(e$y, 21L)
  expect_length(rs$notes, 1L)
})

test_that("!code errors are shown on stderr and noted", {
  local_project()
  rs = repl_state(NULL, new.env())
  err = utils::capture.output(invisible(utils::capture.output(
    repl_passthrough(rs, "!stop('boom')"))), type = "message")
  expect_true(any(grepl("Error: boom", err, fixed = TRUE)))
  expect_match(rs$notes, "boom", fixed = TRUE)
})

test_that("the input event (source passthrough) can handle or transform !code", {
  local_project()
  e = new.env()
  rs = repl_state(NULL, e)
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (!identical(event$source, "passthrough")) return(NULL)
    if (identical(event$text, "secret()")) return(list(action = "handled", text = ""))
    list(action = "transform", text = sub("^old", "new_value", event$text))
  }))
  withr::defer(off())
  utils::capture.output(repl_passthrough(rs, "!secret()"))
  expect_length(rs$notes, 0L)
  utils::capture.output(repl_passthrough(rs, "!old = 5"))
  expect_identical(e$new_value, 5)
})

test_that("!code is announced on the console:direct channel", {
  local_project()
  got = new.env(parent = emptyenv())
  off = gptr_register(gptr_hook("console:direct", function(event, ctx) {
    got$data = event$data
    NULL
  }))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  utils::capture.output(repl_passthrough(rs, "!1 + 1"))
  expect_identical(got$data$code, "1 + 1")
  expect_identical(got$data$status, "ok")
  expect_true(got$data$noted)
  expect_true(any(grepl("[1] 2", got$data$output, fixed = TRUE)))
})

test_that("console_send() makes an ordinary gateway call and continues the session", {
  local_project()
  local_console_blocks()
  fake = gptr_fake_provider(list("first answer", "second answer"))
  e = new.env()
  e$x = matrix(1:6, 2)
  rs = repl_state(NULL, e)
  rs$model = fake
  utils::capture.output(repl_passthrough(rs, "!dim(x)"))
  res = console_send(rs, "how big is it?")
  expect_identical(res$status, "ok")
  s = rs$session
  expect_s3_class(s, "gptr_session")
  expect_identical(s$text, "first answer")
  blocks = last_user_blocks(fake_requests(fake)[[1L]])
  expect_identical(unname(blocks[["text"]]), "how big is it?")
  expect_match(blocks[["user_ran"]], "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  expect_length(rs$notes, 0L)
  console_send(rs, "and now?")
  expect_identical(rs$session, s)
  expect_identical(s$turns, 2L)
  expect_false("user_ran" %in% names(last_user_blocks(fake_requests(fake)[[2L]])))
  expect_identical(ls(e), "x")
  expect_null(rs$sending)
})

test_that("console_send() attaches @objects by name and @files as a block", {
  local_project(files = list("a.R" = "fit = lm(mpg ~ wt, data = mtcars)"))
  local_console_blocks()
  fake = gptr_fake_provider(list("ok"))
  e = new.env(parent = globalenv())
  e$my_cars = mtcars
  rs = repl_state(NULL, e)
  rs$model = fake
  console_send(rs, "explain @a.R using @my_cars")
  blocks = last_user_blocks(fake_requests(fake)[[1L]])
  expect_match(blocks[["user_files"]], "<file path=\"a.R\">", fixed = TRUE)
  expect_true("attached" %in% names(blocks))
  expect_match(blocks[["attached"]], "my_cars", fixed = TRUE)
  expect_identical(unname(blocks[["text"]]), "explain @a.R using @my_cars")
})

test_that("console_send() keeps the session of a failed call and reports the error", {
  local_project()
  fake = gptr_fake_provider(list(list(error = "bad key", status = 401L, after = 0L)))
  rs = repl_state(NULL, new.env())
  rs$model = fake
  res = console_send(rs, "hello")
  expect_identical(res$status, "error")
  expect_s3_class(res$error, "gptr_error")
  expect_s3_class(rs$session, "gptr_session")
  expect_identical(rs$session$status, "error")
})

test_that("!code runs through the eval.r service (the evaluator kind, IC-69)", {
  local_project()
  old = the$services
  withr::defer({
    the$services = old
  })
  seen = new.env(parent = emptyenv())
  ext_service_set("eval.r", function(code, envir, ...) {
    seen$code = code
    seen$args = names(list(...))
    eval_r(code, envir, ...)
  }, provided_by = "test")
  rs = repl_state(NULL, new.env())
  utils::capture.output(repl_passthrough(rs, "!1 + 1"))
  expect_identical(seen$code, "1 + 1")
  expect_setequal(seen$args, c("plots", "tee", "guard"))
})

test_that("the console call's arguments reach the first prompt, also on a piped session", {
  local_project()
  s = peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  call = list(ids = list(mode = "auto"), args = list(), context = list())
  rs = repl_state(s, new.env(), call = call)
  cl = console_call(rs, "go")
  console_call_release(rs)
  expect_identical(cl$mode, "auto")
  expect_identical(cl[[2L]], quote(.gptr_session))
  cl2 = console_call(rs, "again")
  console_call_release(rs)
  expect_null(cl2$mode)
})

test_that("console_send() passes max_turns from gptr.max_turns_console", {
  local_project()
  fake = gptr_fake_provider(list("ok"))
  rs = repl_state(NULL, new.env())
  rs$model = fake
  local_gptr_options(max_turns_console = 7L)
  got = new.env(parent = emptyenv())
  off = gptr_register(gptr_context_block("probe_opts", function(ctx, budget) {
    got$max_turns = ctx$input$opts$max_turns
    NULL
  }, placement = "both"))
  withr::defer(off())
  console_send(rs, "hello")
  expect_identical(got$max_turns, 7L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-repl$")'
```

Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 36 ]`; the new tests error with `could not find function "console_notes_text"` (and `repl_mentions`, `repl_passthrough`, `console_blocks`, `console_send`, `console_call`).

- [ ] **Step 3: Write the implementation**

Append to `R/console-repl.R`:

```r
# ---------------------------------------------------------------------------------------------
# `!expr`, notes, @mentions and the prompt call (Task 5). `!code` and `!!code` are the user's own
# R: evaluated with eval_r() in the REPL's environment (no permission gate, no guard), shown as
# it runs; `!code` also leaves a note that the `user_ran` block adds to the next prompt within
# 300 tokens (IC-73). `@file` mentions add the file's head to the `user_files` block; `@object`
# mentions attach the object by name (P09's `attached` block describes it). Both blocks answer
# only the gateway call that console_send() built: the call record's `sys_call` is that call.
# ---------------------------------------------------------------------------------------------

#' Escape an attribute value of a context tag
#' @noRd
attr_escape = function(x) {
  gsub("\"", "&quot;", gsub("&", "&amp;", x, fixed = TRUE), fixed = TRUE)
}

#' The <file> block of an @file mention: the first 40 lines of a text file (redacted with the
#' `context` profile), or a one-line note for a binary file (report 18 section 4.3)
#' @noRd
repl_file_block = function(path, shown, max_lines = 40L) {
  head_raw = readBin(path, "raw", n = 8192L)
  if (any(head_raw == as.raw(0L))) {
    return(paste0("<file path=\"", attr_escape(shown), "\" binary=\"true\" bytes=\"",
                  format(file.size(path), scientific = FALSE), "\"/>"))
  }
  x = readLines(path, n = max_lines + 1L, warn = FALSE, encoding = "UTF-8")
  x = redact(clean_terminal(as_utf8(x)), profile = "context")
  more = length(x) > max_lines
  paste0("<file path=\"", attr_escape(shown), "\"", if (more) " truncated=\"true\"" else "",
         ">\n", paste(utils::head(x, max_lines), collapse = "\n"), "\n</file>")
}

#' Is `name` bound in `env` or one of its parents up to the global environment? (exists() forces
#' nothing; namespaces and base are not searched, so `@c` is not the function c)
#' @noRd
console_object_visible = function(name, env) {
  e = env
  while (!identical(e, emptyenv()) && !isNamespace(e) && !identical(e, baseenv())) {
    if (exists(name, envir = e, inherits = FALSE)) return(TRUE)
    if (identical(e, globalenv())) break
    e = parent.env(e)
  }
  FALSE
}

#' Resolve @mentions: files (relative to the working directory or the project root, or
#' absolute/home paths) become <file> blocks; syntactic names bound in `env` become context
#' objects passed by name (never read here). Other mentions (e-mail addresses) stay text.
#' @noRd
repl_mentions = function(text, env) {
  pattern = "@(\"[^\"]+\"|[A-Za-z0-9_./~-]*[A-Za-z0-9_/~-])"
  toks = regmatches(text, gregexpr(pattern, text))[[1L]]
  files = character()
  objects = character()
  for (t in unique(toks)) {
    nm = gsub("^@\"?|\"$", "", t)
    cand = unique(c(path.expand(nm), file.path(project_root(), nm)))
    hit = cand[file.exists(cand) & !dir.exists(cand)]
    if (length(hit)) {
      files = c(files, repl_file_block(hit[[1L]], path_rel(hit[[1L]])))
    } else if (identical(make.names(nm), nm) && console_object_visible(nm, env)) {
      objects = c(objects, nm)
    }
  }
  list(files = files, objects = unique(objects))
}

#' The note an `!expr` leaves for the next prompt: the code and its output as #> lines
#' (redacted with the `context` profile)
#' @noRd
repl_note = function(code, res) {
  fmt = tryCatch(format_eval_result(res, 300L)$text, error = function(e) "")
  out = strsplit(fmt %||% "", "\n", fixed = TRUE)[[1L]]
  note = paste(c(paste0("> ", strsplit(code, "\n", fixed = TRUE)[[1L]]),
                 if (length(out)) paste0("#> ", out)), collapse = "\n")
  redact(note, profile = "context")
}

#' Text of the `user_ran` block: the newest notes that fit `budget` tokens (the
#' `workspace_changes` rules, IC-73); one over-long note is cut from its end
#' @noRd
console_notes_text = function(notes, budget = 300L) {
  notes = as.character(notes)
  if (!length(notes)) return(NULL)
  header = "The user ran this R code in the session (output as #> lines):"
  # the reserve covers the "(n earlier omitted)" suffix added after the selection
  fits = function(x) {
    est_tokens(paste(c(header, " (999 earlier omitted)", x), collapse = "\n"), "r_output") <=
      budget
  }
  keep = character()
  i = length(notes)
  while (i >= 1L && fits(c(notes[[i]], keep))) {
    keep = c(notes[[i]], keep)
    i = i - 1L
  }
  if (!length(keep)) {
    lines = strsplit(notes[[length(notes)]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 1L && !fits(c(lines, "#> [... output cut]"))) {
      lines = lines[-length(lines)]
    }
    keep = paste(c(lines, "#> [... output cut]"), collapse = "\n")
  }
  dropped = length(notes) - length(keep)
  if (dropped > 0L) header = paste0(header, " (", dropped, " earlier omitted)")
  paste(c(header, keep), collapse = "\n")
}

#' Text of the `user_files` block: the <file> blocks that fit `budget` tokens, in order
#' @noRd
console_files_text = function(files, budget = 2000L) {
  files = as.character(files)
  if (!length(files)) return(NULL)
  keep = character()
  for (f in files) {
    if (est_tokens(paste(c(keep, f), collapse = "\n"), "code") > budget) break
    keep = c(keep, f)
  }
  if (!length(keep)) {
    lines = strsplit(files[[1L]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 2L && est_tokens(paste(lines, collapse = "\n"), "code") > budget) {
      lines = lines[-(length(lines) - 1L)]
    }
    keep = paste(lines, collapse = "\n")
  }
  paste(keep, collapse = "\n")
}

#' The REPL whose prompt call is being assembled, when `ctx` renders that call's context
#' @noRd
repl_sending = function(ctx) {
  inp = tryCatch(ctx$input, error = function(e) NULL)
  call = if (is.list(inp)) inp$call else NULL
  if (!is.environment(call)) return(NULL)
  rs = console_repl_find()
  if (is.null(rs) || is.null(rs$sending)) return(NULL)
  if (!identical(get0("sys_call", envir = call, inherits = FALSE), rs$sending)) return(NULL)
  rs
}

#' provide() of the `user_ran` context block: the pending `!expr` notes (taken once)
#' @noRd
console_notes_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$notes)) return(NULL)
  text = console_notes_text(rs$notes, budget)
  rs$notes = character()
  text
}

#' provide() of the `user_files` context block: the files mentioned in the prompt (taken once)
#' @noRd
console_files_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$files)) return(NULL)
  text = console_files_text(rs$files, budget)
  rs$files = character()
  text
}

#' The context blocks registered by builtin:console (placement both: first and later turns)
#' @noRd
console_blocks = function() {
  list(
    gptr_context_block("user_ran", console_notes_provide, placement = "both",
                       authority = "data", budget = 300L, order = 550L),
    gptr_context_block("user_files", console_files_provide, placement = "both",
                       authority = "data", budget = 2000L, order = 560L)
  )
}

#' `!code` / `!!code`: the user's own R code in the REPL's environment
#'
#' The `input` event (source "passthrough") may handle or transform the code first. Errors are
#' shown on stderr; `!code` leaves a note for the next prompt. The `console:direct` channel
#' tells transcript writers (P15) what ran.
#' @noRd
repl_passthrough = function(rs, text) {
  noted = !startsWith(text, "!!")
  code = substring(text, if (noted) 2L else 3L)
  ev = ev_dispatch("input", ev_new("input", text = code, source = "passthrough"),
                   session = rs$session)
  if (is.list(ev) && identical(ev$action, "handled")) return(invisible(NULL))
  if (is.list(ev) && identical(ev$action, "transform") && is.character(ev$text) &&
        length(ev$text) == 1L) {
    code = ev$text
  }
  if (!nzchar(trimws(code))) return(invisible(NULL))
  # the evaluator of the `evaluator` setting (04 section 7.0 service `eval.r`, IC-69); the
  # built-in eval_r() when builtin:workspace is filtered out
  evaluate = if (ext_service_has("eval.r")) ext_service_get("eval.r") else eval_r
  res = evaluate(code, repl_eval_env(rs), plots = "auto", tee = TRUE, guard = FALSE)
  for (e in res$events) {
    if (identical(e$type, "error")) {
      console_notice("Error: ", console_escape(as.character(e$message %||% ""), FALSE))
    }
  }
  if (res$status %in% c("interrupt", "timeout")) console_notice("[gptr] ", res$status)
  if (noted) rs$notes = utils::tail(c(rs$notes, repl_note(code, res)), 20L)
  data = list(code = code, output = as.character(unlist(res$outputs %||% list())),
              status = res$status, noted = noted)
  ev_dispatch("console:direct", list(data = data), session = rs$session)
  invisible(res$status)
}

#' Abort a run left without a pump by an interrupt that hit before the policy did
#' @noRd
console_abort_stray = function(s) {
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (inherits(run, "gptr_run") && policy_active(run)) run_abort(run, reason = "user")
  invisible(NULL)
}

#' Build the gateway call of one prompt (no closure or handler is created in this frame, which
#' binds the evaluation environment; rule R3)
#'
#' Returns `gptr::peter(.gptr_session, <@objects>, prompt = "<text>", envir = .gptr_env, .opts =
#' ...)` (on the first prompt of a new or piped-in session also the console call's model, mode,
#' tools, plugins, extensions, skills and context objects). `.gptr_session` and `.gptr_env` are
#' bound in the mask `rs$mask`, whose parent is the evaluation environment, so @objects reach
#' the gateway as plain symbols (read by name, never forced, IC-41). The literal prompt gets
#' `{identifier}` interpolation like a typed one; the console echoes the interpolated text at
#' verbosity 2 (03 section 4.1.4).
#' @noRd
console_call = function(rs, text) {
  env = repl_eval_env(rs)
  men = repl_mentions(text, env)
  first = is.null(rs$session)
  # the console call's identifiers and objects go with the first prompt of a new session and
  # with the first prompt on a piped-in session (`s |> peter(mode = auto)`)
  extras = first || isTRUE(rs$pending_call)
  rs$pending_call = FALSE
  objs = unique(c(if (extras) rs$attach else character(), men$objects))
  opts = rs$opts
  if (is.null(opts$max_turns)) opts$max_turns = as.integer(gptr_opt("max_turns_console"))
  skills = unique(c(if (extras) rs$skills else character(), rs$next_skills))
  rs$next_skills = NULL
  rs$files = men$files
  mask = new.env(parent = env)
  assign(".gptr_env", env, envir = mask)
  rs$mask = mask
  head = list(quote(gptr::peter))
  if (!first) {
    assign(".gptr_session", rs$session, envir = mask)
    head = c(head, list(quote(.gptr_session)))
  }
  args = list(prompt = text, envir = quote(.gptr_env), .opts = opts)
  if (!is.null(rs$budget)) args$budget = rs$budget
  if (extras) {
    extra = list(model = rs$model, mode = rs$mode, tools = rs$tools, plugins = rs$plugins,
                 extensions = rs$extensions)
    args = c(args, extra[!vapply(extra, is.null, NA)])
    rs$opts$images = NULL
  }
  if (length(skills)) args$skills = skills
  if (isTRUE(rs$render) && verbosity() >= 2L && !isFALSE(opts$interpolate) &&
        !isFALSE(gptr_opt("interpolate"))) {
    shown = interpolate_prompt(text, env)$prompt
    if (!identical(shown, text)) console_write(cli::col_grey(paste0("> ", console_escape(shown))))
  }
  as.call(c(head, lapply(objs, as.name), args))
}

#' Release the mask of a prompt call: bindings removed, parent reset to emptyenv() (R2)
#' @noRd
console_call_release = function(rs) {
  mask = rs$mask
  rs$mask = NULL
  rs$sending = NULL
  rs$files = character()
  if (is.environment(mask)) {
    rm(list = ls(mask, all.names = TRUE), envir = mask)
    parent.env(mask) = emptyenv()
  }
  invisible(NULL)
}

#' One prompt as an ordinary gateway call (console_call())
#'
#' The frame binds `.gptr_interrupt_barrier`, so the policy of this call's run is the outermost
#' one and its re-signalled interrupt ends here. A failed call keeps its session (the condition's
#' `$session`, else a new gptr_last()); a stray run left by an early interrupt is aborted.
#' @return list(status = "ok" | "error" | "interrupt", value, error); `rs$session` is updated.
#' @noRd
console_send = function(rs, text) {
  .gptr_interrupt_barrier = TRUE
  on.exit(console_call_release(rs), add = TRUE)
  cl = console_call(rs, text)
  rs$sending = cl
  before = gptr::gptr_last()
  res = tryCatch(list(status = "ok", value = eval(cl, envir = rs$mask)),
                 error = function(e) list(status = "error", error = e),
                 interrupt = function(e) list(status = "interrupt"))
  s = NULL
  if (inherits(res$value, "gptr_session")) {
    s = res$value
  } else if (inherits(res$error$session, "gptr_session")) {
    s = res$error$session
  } else {
    last = gptr::gptr_last()
    if (inherits(last, "gptr_session") && !identical(last, before)) s = last
  }
  if (!is.null(s)) rs$session = s
  if (identical(res$status, "interrupt") && !is.null(rs$session)) console_abort_stray(rs$session)
  res
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-repl$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/console-repl.R tests/testthat/test-console-repl.R
git commit -m "feat(console): add !expr passthrough, notes, mentions and console_send()"
```

---

### Task 6: Slash commands

**Files:**
- Create: `R/console-commands.R`
- Test: `tests/testthat/test-console-commands.R` (create)

**Interfaces:**
- Consumes: Tasks 1-5 (`console_escape()`, `console_notice()`, `console_out()`, `console_interrupt_key()`, `console_repl_find()`, `with_interrupt_policy()`, `repl_model()`, `repl_mode()`, `repl_eval_env()`); P01 `ns_fun(name)`, `ext_service_has()`, `ext_service_get()`, `ev_new()`, `%||%`; P02 `gptr_command(name, handler, description = NULL, complete = NULL)` (kind `command`: `handler(args, ctx)` returns `NULL`, a chr printed verbatim, or `list(prompt = chr(1))` sent as a prompt; an error is reported and the input counts as handled), `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)`, `ev_dispatch()`, `ctx_new(session, run = NULL)`; P06 kernel SDK `session_data(s)` (`id`, `status`, `turns`, `model`, `mode`, `queue$steer`, `queue$follow_up`, `file`, `frozen$tool_names`), `session_live(s)` (`ctx`), `session_set_model(s, ref, reason = "user")`, `session_set_mode(s, mode, source = "user")`, `setting_get()`; P09 `describe_binding(name, envir, budget = 150L)`; P11 `rule_parse(rule)` (kernel SDK); the services `compact.run` = `function(s, reason, focus = NULL)` (P07), `doc.site` = `function(session)` -> `list(path, format, ...)` or `NULL` (P15), `skill.body` (P17, presence only); exports of earlier plans called as `gptr::<name>()`: `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)` (P06; the detail ledger has `request_id`, `component`, `tokens`, `cached`), `gptr_sessions(project = TRUE)`, `gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)`, `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))` (P06), `gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL, scope = c("session", "project", "user"))` (P11); exports of later plans through `ns_fun()`: `gptr_doc(path = NULL, format = NULL, sync = FALSE)` (P15), `gptr_rewind(s, turn = -1L, ...)` (P16; the rewound session's `editor_text` holds the removed prompt), `gptr_skills(scope = ...)` (P17), `gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)` (P18). Tests: P01 `the$services`, `ext_service_set()`; P08 `peter()` (with `.run = FALSE`); P11 `local_permission_rules()`.
- Produces: `console_commands()` -> the 22 `command` specs (`help`, `exit`, `quit`, `q`, `model`, `mode`, `plan`, `tools`, `env`, `compact`, `cost`, `context`, `status`, `clear`, `resume`, `fork`, `doc`, `skills`, `skill`, `mcp`, `permissions`, `retry`); `console_register_commands(gptr)`; `command_parse(text)` -> `list(name, args, full, rest)` or `NULL` (`full` is the whole first token, so a command registered as `<plugin>:<cmd>` (04 section 11.12, P17's Claude plugin commands) wins over the `/skill:<name>` split); `console_command(text, session = NULL, send = NULL)` -> invisibly `"unknown"`, `"error"`, `"prompt"` or `"done"` (the `input` event with `source = "repl"` first: a hook may handle or transform it; then a line that is still a command goes out on the notify channel `console:command` with `data = list(text)`, which P15's `doc_on_console_command()` records); `console_ctx(s)`; the handlers `cmd_*()`.

The commands are those of 03 section 6.17 that the console owns. `/undo`, `/redo`, `/rewind` and `/checkpoints` are registered by P16, prompt templates as `/<name>` by P17 (IC-31); the console only dispatches them, so every command, built-in or not, goes through the `command` registry. Handlers find the REPL state on the call stack (`console_repl_find()`) and otherwise act on `ctx$session`, so they also run from other front ends. Before the first prompt, `/model` and `/mode` set the first prompt's arguments; on a session they call `session_set_model()` and `session_set_mode()`, whose entries take effect at the next request or turn. `/compact` runs under the interrupt policy (mode `"repl"`). `/skill:<name> [request]` preloads the skill for the next prompt (the call's `skills =`) and sends the request. `/permissions allow|ask|deny|remove <rule>` changes the rules of this R session through `gptr_permissions(scope = "session")` after `rule_parse()`; changing project or user rules stays with the R function. `/retry` rewinds one turn with `gptr_rewind()` and sends the removed prompt again. Commands of later plans answer "not available" while their plan is absent. A handler's text is printed escaped, so model or file text in it cannot inject terminal sequences. Each command line first passes the `input` event with `source = "repl"` (04 section 10.4; a transform chain): a hook may handle it (nothing else happens) or transform it (the new text is dispatched as a command, or sent as a prompt when it is no longer a command). A line that is still a command is then announced on the notify channel `console:command` (`data = list(text)`, the text after any transform), which P15's `doc_on_console_command()` records as a comment in the console transcript (03 section 6.17, 04 section 11.5); a handled line and a line sent as a prompt are not announced (P15 records the prompt as a gateway call). A command name is looked up first as the whole first token, so Claude plugin commands registered as `<plugin>:<cmd>` by P17 (04 section 11.12) are found, then as the part before `:` with the rest as arguments (`/skill:<name> request`).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-console-commands.R`:

```r
# tests/testthat/test-console-commands.R -- the slash commands (plan P14, Task 6).

# The console's command specs for this test unless builtin:console registered them already
local_console_commands = function(.env = parent.frame()) {
  for (spec in console_commands()) {
    if (!is.null(registry_get("command", spec$name))) next
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  invisible(NULL)
}

# Run `fun()` from a frame that binds the REPL state, as the REPL loop does
in_repl = function(rs, fun) {
  .gptr_repl = rs
  fun()
}

# Run a command line inside `rs`; returns list(out = stdout lines, err = stderr lines, res)
run_command = function(rs, text, send = NULL) {
  res = NULL
  err = NULL
  out = utils::capture.output({
    err = utils::capture.output({
      res = in_repl(rs, function() console_command(text, rs$session, send))
    }, type = "message")
  })
  list(out = out, err = err, res = res)
}

idle_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  peter("hello", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
}

test_that("command_parse() splits names, sub-names and arguments", {
  expect_identical(command_parse("/mode auto"),
                   list(name = "mode", args = "auto", full = "mode", rest = "auto"))
  expect_identical(command_parse("/help"), list(name = "help", args = "", full = "help", rest = ""))
  expect_identical(command_parse("/skill:stats run it"),
                   list(name = "skill", args = "stats run it", full = "skill:stats",
                        rest = "run it"))
  expect_null(command_parse("not a command"))
})

test_that("a command named <plugin>:<cmd> wins over the /skill:<name> split (04 11.12)", {
  off = gptr_register(gptr_command("tidy:review", function(args, ctx) paste("reviewing", args)))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/tidy:review analysis.R")$out, "reviewing analysis.R")
})

test_that("every command of architecture 6.17 that P14 owns is a command spec", {
  nms = vapply(console_commands(), function(x) x$name, "")
  expect_true(all(c("help", "exit", "model", "mode", "plan", "tools", "env", "compact", "cost",
                    "context", "status", "clear", "resume", "fork", "doc", "skills", "skill",
                    "mcp", "retry", "permissions") %in% nms))
  expect_true(all(vapply(console_commands(), function(x) inherits(x, "gptr_command"), NA)))
})

test_that("unknown commands and failing handlers are reported; the input counts as handled", {
  local_console_commands()
  off = gptr_register(gptr_command("boom", function(args, ctx) stop("kaput")))
  withr::defer(off())
  rs = repl_state(NULL, new.env())
  r = run_command(rs, "/nope")
  expect_identical(r$res, "unknown")
  expect_true(any(grepl("Unknown command /nope", r$err, fixed = TRUE)))
  r = run_command(rs, "/boom")
  expect_identical(r$res, "error")
  expect_true(any(grepl("Error in /boom: kaput", r$err, fixed = TRUE)))
})

test_that("a command's text is printed escaped and a list(prompt =) is sent", {
  off = gptr_register(gptr_command("echo", function(args, ctx) paste("got", args, "\033")))
  withr::defer(off())
  off2 = gptr_register(gptr_command("ask", function(args, ctx) list(prompt = "the prompt")))
  withr::defer(off2())
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/echo {x}")$out, "got {x} <U+001B>")
  sent = new.env(parent = emptyenv())
  r = run_command(rs, "/ask", send = function(text) {
    sent$text = text
  })
  expect_identical(r$res, "prompt")
  expect_identical(sent$text, "the prompt")
})

test_that("commands pass the input event (source repl): recorded, handled or transformed", {
  local_console_commands()
  got = new.env(parent = emptyenv())
  got$texts = character()
  got$recorded = character()
  off = gptr_register(gptr_hook("input", function(event, ctx) {
    if (!identical(event$source, "repl")) return(NULL)
    got$texts = c(got$texts, event$text)
    if (identical(event$text, "/swallow")) return(list(action = "handled", text = ""))
    if (identical(event$text, "/m")) return(list(action = "transform", text = "/mode plan"))
    if (identical(event$text, "/p")) return(list(action = "transform", text = "summarise x"))
    NULL
  }))
  withr::defer(off())
  # the channel P15's doc_on_console_command() subscribes to (data = list(text))
  off2 = gptr_register(gptr_hook("console:command", function(event, ctx) {
    got$recorded = c(got$recorded, event$data$text)
    NULL
  }))
  withr::defer(off2())
  rs = repl_state(NULL, new.env())
  run_command(rs, "/mode auto")
  expect_identical(got$texts, "/mode auto")
  expect_identical(run_command(rs, "/swallow")$res, "done")
  r = run_command(rs, "/m")
  expect_identical(r$out, "Mode: plan (used from the first prompt)")
  expect_identical(rs$mode, "plan")
  run_command(rs, "/model opus")
  expect_identical(rs$model, "opus")
  sent = new.env(parent = emptyenv())
  r = run_command(rs, "/p", send = function(text) {
    sent$text = text
  })
  expect_identical(r$res, "prompt")
  expect_identical(sent$text, "summarise x")
  # handled lines and lines sent as prompts are not recorded; a transformed command is recorded
  # as it ran
  expect_identical(got$recorded, c("/mode auto", "/mode plan", "/model opus"))
})

test_that("/help lists the commands and the input syntax", {
  local_console_commands()
  out = run_command(repl_state(NULL, new.env()), "/help")$out
  expect_true(any(grepl("^  /mode", out)))
  expect_true(any(grepl("!!code", out, fixed = TRUE)))
  expect_identical(run_command(repl_state(NULL, new.env()), "/help mode")$out,
                   "/mode  Show or switch the permission mode: /mode [plan|manual|edits|auto]")
})

test_that("/exit, /quit and /q end the REPL", {
  local_console_commands()
  for (cmd in c("/exit", "/quit", "/q")) {
    rs = repl_state(NULL, new.env())
    run_command(rs, cmd)
    expect_true(rs$exit)
  }
})

test_that("/model and /mode before the first prompt set the first prompt's arguments", {
  local_console_commands()
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/model haiku")$out,
                   "Model: haiku (used from the first prompt)")
  expect_identical(rs$model, "haiku")
  run_command(rs, "/plan")
  expect_identical(rs$mode, "plan")
  expect_identical(run_command(rs, "/mode")$out, "Mode: plan")
  expect_match(run_command(rs, "/mode turbo")$out, "Unknown mode 'turbo'", fixed = TRUE)
})

test_that("/mode on a session appends the mode change for the next turn", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  expect_identical(run_command(rs, "/mode auto")$out, "Mode: auto (from the next turn)")
  expect_identical(s$mode, "auto")
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% "", "")
  expect_true("gptr.mode_change" %in% types)
})

test_that("/status, /tools and /env describe the console", {
  local_console_commands()
  e = new.env()
  e$counts = matrix(1:4, 2)
  rs = repl_state(NULL, e)
  expect_match(run_command(rs, "/status")$out[[1L]], "session   (none yet", fixed = TRUE)
  expect_match(run_command(rs, "/tools")$out[[1L]], "Direct tools:", fixed = TRUE)
  env_out = run_command(rs, "/env count")$out
  expect_match(env_out, "^  counts: ")
  s = idle_session()
  rs$session = s
  status = run_command(rs, "/status")$out
  expect_identical(status[[1L]], paste0("session   ", s$id, "  (idle, 0 turns)"))
  expect_true(any(grepl("^queue     0 steer, 1 follow-up$", status)))
})

test_that("/clear starts a new conversation and keeps model and mode", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  rs$notes = "> x"
  run_command(rs, "/clear")
  expect_null(rs$session)
  expect_identical(rs$model, s$model)
  expect_identical(rs$notes, character())
})

test_that("/cost, /context, /fork and /resume work on a session that ran", {
  local_console_commands()
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
  rs = repl_state(s, new.env())
  cost = run_command(rs, "/cost")$out
  expect_match(cost[[length(cost)]], "^Total: \\$")
  ctx_out = run_command(rs, "/context")$out
  expect_match(ctx_out[[1L]], "^Last request q[0-9a-f]+:$")
  run_command(rs, "/fork")
  expect_false(identical(rs$session$id, s$id))
  listing = run_command(rs, "/resume")$out
  expect_true(any(grepl(s$id, listing, fixed = TRUE)))
})

test_that("commands of later plans answer when their plan is absent", {
  local_console_commands()
  s = idle_session()
  rs = repl_state(s, new.env())
  local_mocked_bindings(ns_fun = function(name) NULL)
  expect_identical(run_command(rs, "/skills")$out, "Skills are not available.")
  expect_identical(run_command(rs, "/mcp")$out, "MCP is not available.")
  expect_identical(run_command(rs, "/doc analysis.R")$out,
                   "Binding a document needs gptr_doc(), which is not available.")
  expect_identical(run_command(rs, "/retry")$out, "There is no answer to retry.")
})

test_that("/skill:<name> preloads the skill for the next prompt", {
  local_console_commands()
  old = the$services
  withr::defer({
    the$services = old
  })
  ext_service_set("skill.body", function(name) list(text = "Use lm().", dir = tempdir()),
                  provided_by = "test")
  rs = repl_state(NULL, new.env())
  sent = new.env(parent = emptyenv())
  run_command(rs, "/skill:stats fit a model", send = function(text) {
    sent$text = text
  })
  expect_identical(rs$next_skills, "stats")
  expect_identical(sent$text, "fit a model")
})

test_that("/permissions shows and changes the rules of this R session", {
  local_console_commands()
  local_permission_rules()
  rs = repl_state(NULL, new.env())
  expect_identical(run_command(rs, "/permissions allow r(fn:saveRDS)")$out,
                   "Added allow rule r(fn:saveRDS) for this R session.")
  expect_true(any(grepl("r(fn:saveRDS)", run_command(rs, "/permissions")$out, fixed = TRUE)))
  expect_match(run_command(rs, "/permissions maybe x")$out, "^Use /permissions")
  r = run_command(rs, "/permissions allow r(fn:")
  expect_identical(r$res, "error")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-commands$")'
```

Expected: `[ FAIL 16 | WARN 0 | SKIP 0 | PASS 0 ]`; the errors read `could not find function "command_parse"` (and `console_commands`, `console_command`).

- [ ] **Step 3: Write the implementation**

Create `R/console-commands.R`:

```r
# console-commands.R -- P14 Console and front ends (layer L5, area console).
# The slash commands of architecture 6.17 as `command` specs (contract 10.2 kind 10: handler(args,
# ctx) returns NULL, a character vector printed verbatim, or list(prompt = chr(1)) sent as a
# prompt; an error is reported and the input counts as handled). The console only dispatches
# commands: /undo, /redo, /rewind and /checkpoints are registered by P16 and prompt templates by
# P17 (IC-31). Handlers find the REPL state on the call stack (console_repl_find()) and otherwise
# act on ctx$session, so they also work from other front ends. Exports of later plans
# (gptr_doc() P15, gptr_rewind() P16, gptr_skills() P17, gptr_mcp() P18) are reached through
# P01's late binding ns_fun(); exports of earlier plans in other layers are called as gptr::.

#' The command specs registered by builtin_console()
#' @noRd
console_commands = function() {
  cmd = function(name, handler, description) {
    gptr_command(name, handler, description = description)
  }
  list(
    cmd("help", cmd_help, "Show the commands and the input syntax: /help [command]"),
    cmd("exit", cmd_exit, "Leave the console; the session is returned invisibly"),
    cmd("quit", cmd_exit, "Leave the console (same as /exit)"),
    cmd("q", cmd_exit, "Leave the console (same as /exit)"),
    cmd("model", cmd_model, "Show or switch the model: /model [provider/model or alias]"),
    cmd("mode", cmd_mode, "Show or switch the permission mode: /mode [plan|manual|edits|auto]"),
    cmd("plan", cmd_plan, "Switch to plan mode (read-only exploration, then a plan)"),
    cmd("tools", cmd_tools, "List the direct tools and the peter$ members"),
    cmd("env", cmd_env, "List objects of the console environment: /env [pattern]"),
    cmd("compact", cmd_compact, "Compact the conversation now: /compact [focus]"),
    cmd("cost", cmd_cost, "Tokens and cost of this session"),
    cmd("context", cmd_context, "Token ledger of the last request"),
    cmd("status", cmd_status, "Session, model, mode, document and queued messages"),
    cmd("clear", cmd_clear, "Start a new conversation; objects are kept"),
    cmd("resume", cmd_resume, "List stored sessions, or continue one: /resume [id]"),
    cmd("fork", cmd_fork, "Fork the session and continue on the fork"),
    cmd("doc", cmd_doc, "Show or bind the history document: /doc [path]"),
    cmd("skills", cmd_skills, "List the skills"),
    cmd("skill", cmd_skill, "Use a skill for the next prompt: /skill:<name> [request]"),
    cmd("mcp", cmd_mcp, "List the MCP servers"),
    cmd("permissions", cmd_permissions,
        "Show or change the rules of this R session: /permissions [allow|ask|deny|remove <rule>]"),
    cmd("retry", cmd_retry, "Undo the last turn and send its prompt again")
  )
}

#' Register the command specs (called by builtin_console())
#' @noRd
console_register_commands = function(gptr) {
  for (spec in console_commands()) gptr$register(spec)
  invisible(NULL)
}

#' Split a command line into list(name, args, full, rest); NULL when `text` is not a command
#'
#' "/name args" gives name = full = "name" and args = rest = "args". "/a:b args" gives
#' name "a", args "b args" (the `/skill:<name> request` form), full "a:b" and rest "args": a
#' command registered under the whole token (a Claude plugin command `<plugin>:<cmd>`, contract
#' 11.12) is tried first with `rest` as its arguments.
#' @noRd
command_parse = function(text) {
  pattern = "^/([^[:space:]:]+)(:([^[:space:]]*))?[[:space:]]*(.*)$"
  m = regmatches(text, regexec(pattern, text))[[1L]]
  if (!length(m)) return(NULL)
  rest = trimws(m[[5L]])
  args = rest
  if (nzchar(m[[4L]])) args = trimws(paste(m[[4L]], rest))
  full = if (nzchar(m[[4L]])) paste0(m[[2L]], ":", m[[4L]]) else m[[2L]]
  list(name = m[[2L]], args = args, full = full, rest = rest)
}

#' The ctx a command handler gets: the session's own ctx, else a process-level one
#' @noRd
console_ctx = function(s) {
  if (!is.null(s)) {
    live = session_live(s)
    if (!is.null(live) && !is.null(live$ctx)) return(live$ctx)
  }
  ctx_new(s)
}

#' Run one slash command through its `command` spec
#'
#' The line first passes the `input` event with source "repl" (contract 10.4, a transform
#' chain): a hook may handle it (nothing else happens) or transform it (the new text is
#' dispatched as a command, or sent as a prompt when it is not one). A line that is still a
#' command is announced on the notify channel `console:command` (`data = list(text)`), which
#' transcript writers (P15's `doc_on_console_command()`) record as a comment. The whole first
#' token is looked up before the part before ":". A character result is printed (escaped),
#' `list(prompt =)` is sent as a prompt through `send(text)`, and an error is reported on stderr
#' (the input counts as handled).
#' @return Invisibly: "unknown", "error", "prompt" or "done".
#' @noRd
console_command = function(text, session = NULL, send = NULL) {
  if (is.null(command_parse(text))) return(invisible("unknown"))
  ev = ev_dispatch("input", ev_new("input", text = text, source = "repl"), session = session)
  if (is.list(ev) && identical(ev$action, "handled")) return(invisible("done"))
  if (is.list(ev) && identical(ev$action, "transform") && is.character(ev$text) &&
        length(ev$text) == 1L && !is.na(ev$text)) {
    text = trimws(ev$text)
  }
  cmd = command_parse(text)
  if (is.null(cmd)) {
    if (!nzchar(text) || !is.function(send)) return(invisible("unknown"))
    send(text)
    return(invisible("prompt"))
  }
  # the transcript channel (03 section 6.17: commands are recorded as comments; P15)
  ev_dispatch("console:command", list(data = list(text = text)), session = session)
  sid = if (is.null(session)) NULL else session_data(session)$id
  spec = NULL
  args = cmd$args
  if (!identical(cmd$full, cmd$name)) {
    spec = registry_get("command", cmd$full, session = sid)
    if (!is.null(spec)) args = cmd$rest
  }
  if (is.null(spec)) spec = registry_get("command", cmd$name, session = sid)
  if (is.null(spec)) {
    console_notice("Unknown command /", console_escape(cmd$full, FALSE),
                   ". Type /help for the list.")
    return(invisible("unknown"))
  }
  out = tryCatch(spec$handler(args, console_ctx(session)), error = function(e) {
    console_notice("Error in /", console_escape(spec$name %||% cmd$name, FALSE), ": ",
                   console_escape(conditionMessage(e), FALSE))
    structure(list(), class = "gptr_command_error")
  })
  if (inherits(out, "gptr_command_error")) return(invisible("error"))
  if (is.character(out) && length(out)) {
    console_out(out)
  } else if (is.list(out) && is.character(out$prompt) && length(out$prompt) == 1L &&
               nzchar(out$prompt)) {
    if (is.function(send)) send(out$prompt)
    return(invisible("prompt"))
  }
  invisible("done")
}

#' The session a command acts on: the REPL's, else the ctx's
#' @noRd
cmd_session = function(ctx) {
  rs = console_repl_find()
  if (!is.null(rs)) return(rs$session)
  if (is.null(ctx)) NULL else tryCatch(ctx$session, error = function(e) NULL)
}

#' A function of this namespace defined by a later plan, or NULL (P01's late binding)
#' @noRd
cmd_late = function(name) {
  ns_fun(name)
}

#' The printed form of a value as lines
#' @noRd
cmd_print = function(x) {
  utils::capture.output(print(x))
}

#' @noRd
cmd_help = function(args, ctx) {
  s = cmd_session(ctx)
  sid = if (is.null(s)) NULL else session_data(s)$id
  if (nzchar(args)) {
    nm = sub("^/", "", args)
    spec = registry_get("command", nm, session = sid)
    if (is.null(spec)) return(paste0("No command /", nm, "."))
    return(paste0("/", nm, "  ", spec$description %||% ""))
  }
  nms = sort(registry_names("command", session = sid), method = "radix")
  lines = vapply(nms, function(nm) {
    spec = registry_get("command", nm, session = sid)
    sprintf("  /%-12s %s", nm, spec$description %||% "")
  }, "")
  c("Commands:", unname(lines),
    "Input:",
    "  text             a prompt; @file adds a file, @object attaches an object",
    "  !code            run R code here; the code and its output go with the next prompt",
    "  !!code           run R code here; not sent to the model",
    "  ```r ... ```     a block of R code (like !)",
    "  \"\"\" ... \"\"\"      a multi-line prompt; a trailing \\ also continues a line",
    paste0("Keys: ", console_interrupt_key(), " pauses a running answer (steer, follow-up, ",
           "continue, abort); twice at the prompt leaves."))
}

#' /exit, /quit, /q: leave the REPL
#' @noRd
cmd_exit = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/exit works inside the gptr console.")
  rs$exit = TRUE
  NULL
}

#' @noRd
cmd_model = function(args, ctx) {
  rs = console_repl_find()
  s = cmd_session(ctx)
  if (!nzchar(args)) {
    model = if (!is.null(s)) {
      s$model
    } else if (!is.null(rs)) {
      repl_model(rs)
    } else {
      setting_get("model")
    }
    return(paste0("Model: ", model %||% "the default model"))
  }
  if (!is.null(s)) {
    session_set_model(s, args, reason = "user")
    # the user's choice also outlives /clear (a new session starts with it)
    if (!is.null(rs)) rs$model = args
    return(paste0("Model: ", s$model, " (from the next request)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  rs$model = args
  paste0("Model: ", args, " (used from the first prompt)")
}

#' @noRd
cmd_mode = function(args, ctx) {
  rs = console_repl_find()
  s = cmd_session(ctx)
  if (!nzchar(args)) {
    mode = if (!is.null(s)) {
      s$mode
    } else if (!is.null(rs)) {
      repl_mode(rs)
    } else {
      setting_get("mode")
    }
    return(paste0("Mode: ", mode %||% "manual"))
  }
  if (!args %in% c("plan", "manual", "edits", "auto")) {
    return(paste0("Unknown mode '", args, "': use plan, manual, edits or auto."))
  }
  if (!is.null(s)) {
    session_set_mode(s, args, source = "user")
    if (!is.null(rs)) rs$mode = args
    return(paste0("Mode: ", args, " (from the next turn)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  rs$mode = args
  paste0("Mode: ", args, " (used from the first prompt)")
}

#' @noRd
cmd_plan = function(args, ctx) {
  cmd_mode("plan", ctx)
}

#' @noRd
cmd_tools = function(args, ctx) {
  s = cmd_session(ctx)
  sid = if (is.null(s)) NULL else session_data(s)$id
  direct = if (is.null(s)) character() else session_data(s)$frozen$tool_names %||% character()
  members = character()
  for (nm in sort(registry_names("tool", session = sid), method = "radix")) {
    spec = registry_get("tool", nm, session = sid)
    if (is.null(spec) || !is.function(spec$fun) || identical(spec$exposure, "hidden")) next
    members = c(members, paste0("peter$", gsub("/", "$", nm, fixed = TRUE)))
  }
  shown = if (length(direct)) paste(direct, collapse = ", ") else "(fixed at the first prompt)"
  c(paste0("Direct tools: ", shown),
    paste0("peter$ members: ", if (length(members)) paste(members, collapse = ", ") else "(none)"))
}

#' @noRd
cmd_env = function(args, ctx) {
  rs = console_repl_find()
  env = if (!is.null(rs)) repl_eval_env(rs) else tryCatch(ctx$envir, error = function(e) NULL)
  if (!is.environment(env)) return("No environment is attached to this console.")
  nms = sort(ls(env), method = "radix")
  if (nzchar(args)) nms = nms[grepl(args, nms, fixed = TRUE)]
  if (!length(nms)) return("(no objects)")
  shown = utils::head(nms, 30L)
  lines = vapply(shown, function(nm) {
    paste0("  ", describe_binding(nm, env, budget = 40L)[[1L]])
  }, "")
  c(unname(lines), if (length(nms) > 30L) paste0("  (+ ", length(nms) - 30L, " more)"))
}

#' @noRd
cmd_compact = function(args, ctx) {
  s = cmd_session(ctx)
  if (is.null(s)) return("There is no conversation to compact yet.")
  focus = if (nzchar(args)) args else NULL
  compact = ext_service_get("compact.run")
  # mode "repl": an abort returns NULL instead of re-signalling the interrupt
  done = with_interrupt_policy(function() {
    compact(s, "manual", focus)
    TRUE
  }, list(), mode = "repl")
  if (isTRUE(done)) "Conversation compacted." else "Compaction was interrupted."
}

#' @noRd
cmd_cost = function(args, ctx) {
  s = cmd_session(ctx)
  if (is.null(s)) return("No session yet.")
  c(cmd_print(s$usage), sprintf("Total: $%.4f", s$cost))
}

#' @noRd
cmd_context = function(args, ctx) {
  s = cmd_session(ctx)
  if (is.null(s)) return("No session yet.")
  led = gptr::gptr_usage(s, detail = TRUE)
  if (!is.data.frame(led) || !nrow(led)) return("No request yet.")
  last = led[led$request_id == led$request_id[[nrow(led)]], , drop = FALSE]
  lines = sprintf("  %-14s %9s%s", last$component, format(round(last$tokens), big.mark = ","),
                  ifelse(last$cached, "  (cached)", ""))
  c(paste0("Last request ", last$request_id[[1L]], ":"), lines,
    sprintf("  %-14s %9s", "total", format(round(sum(last$tokens)), big.mark = ",")))
}

#' @noRd
cmd_status = function(args, ctx) {
  rs = console_repl_find()
  s = cmd_session(ctx)
  if (is.null(s)) {
    return(c("session   (none yet: the first prompt starts one)",
             paste0("model     ", if (!is.null(rs)) repl_model(rs) else "the default model"),
             paste0("mode      ", if (!is.null(rs)) repl_mode(rs) else "manual")))
  }
  d = session_data(s)
  doc = if (ext_service_has("doc.site")) {
    tryCatch(ext_service_get("doc.site")(s), error = function(e) NULL)
  }
  c(paste0("session   ", d$id, "  (", d$status, ", ", d$turns, " turns)"),
    paste0("model     ", d$model),
    paste0("mode      ", d$mode),
    paste0("document  ", if (is.null(doc)) "(none)" else doc$path),
    paste0("queue     ", length(d$queue$steer), " steer, ", length(d$queue$follow_up),
           " follow-up"),
    paste0("file      ", d$file %||% "(not written yet)"))
}

#' @noRd
cmd_clear = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/clear works inside the gptr console.")
  s = rs$session
  if (!is.null(s)) {
    # keep the console call's (or /model's) model: a spec registered for the old session only
    # would not resolve from its model string in a new session
    rs$model = rs$model %||% s$model
    rs$mode = s$mode
  }
  rs$session = NULL
  rs$notes = character()
  rs$attach = character()
  "New conversation; the objects in the environment are kept."
}

#' @noRd
cmd_resume = function(args, ctx) {
  if (!nzchar(args)) return(cmd_print(gptr::gptr_sessions()))
  rs = console_repl_find()
  if (is.null(rs)) return("Use gptr_resume() outside the console.")
  s = gptr::gptr_resume(args, envir = rs$envir)
  rs$session = s
  # the resumed session's kept home now decides where prompts and !code evaluate (IC-40)
  rs$envir_given = FALSE
  paste0("Resumed ", session_data(s)$id, " (", session_data(s)$turns, " turns).")
}

#' @noRd
cmd_fork = function(args, ctx) {
  rs = console_repl_find()
  s = cmd_session(ctx)
  if (is.null(s)) return("There is no session to fork yet.")
  f = gptr::gptr_fork(s)
  if (!is.null(rs)) {
    rs$session = f
    # the fork's overlay (its kept home) must win over an explicit console `envir`, or the
    # fork's prompts would write into the original environment
    rs$envir_given = FALSE
  }
  paste0("Forked ", session_data(s)$id, " into ", session_data(f)$id,
         "; the fork's new objects stay in its overlay.")
}

#' @noRd
cmd_doc = function(args, ctx) {
  s = cmd_session(ctx)
  if (!nzchar(args)) {
    if (is.null(s) || !ext_service_has("doc.site")) return("No document is bound.")
    site = ext_service_get("doc.site")(s)
    if (is.null(site)) return("No document is bound.")
    return(paste0("Document: ", site$path, " (", site$format, ")"))
  }
  f = cmd_late("gptr_doc")
  if (is.null(f)) return("Binding a document needs gptr_doc(), which is not available.")
  f(args)
  paste0("Recording into ", args, ".")
}

#' @noRd
cmd_skills = function(args, ctx) {
  f = cmd_late("gptr_skills")
  if (is.null(f)) return("Skills are not available.")
  cmd_print(f())
}

#' /skill:<name> [request]: preload the skill for the next prompt (the `skills =` argument of
#' that call) and send the request
#' @noRd
cmd_skill = function(args, ctx) {
  name = sub("[[:space:]].*$", "", args)
  request = trimws(substring(args, nchar(name) + 1L))
  if (!nzchar(name)) return("Name a skill: /skill:<name> [request].")
  if (!ext_service_has("skill.body")) return("Skills are not available.")
  rs = console_repl_find()
  if (is.null(rs)) return("/skill works inside the gptr console.")
  rs$next_skills = unique(c(rs$next_skills, name))
  list(prompt = if (nzchar(request)) request else paste0("Use the ", name, " skill."))
}

#' @noRd
cmd_mcp = function(args, ctx) {
  f = cmd_late("gptr_mcp")
  if (is.null(f)) return("MCP is not available.")
  cmd_print(f())
}

#' /permissions [allow|ask|deny|remove <rule>]: show the rules, or change a rule for this R
#' session (gptr_permissions(), P11; rules checked with rule_parse())
#' @noRd
cmd_permissions = function(args, ctx) {
  if (!nzchar(args)) return(cmd_print(gptr::gptr_permissions()))
  verb = sub("[[:space:]].*$", "", args)
  rule = trimws(substring(args, nchar(verb) + 1L))
  if (!verb %in% c("allow", "ask", "deny", "remove") || !nzchar(rule)) {
    return(paste("Use /permissions allow|ask|deny|remove <rule>,",
                 "e.g. /permissions allow r(fn:saveRDS)."))
  }
  if (!identical(verb, "remove")) rule_parse(rule)
  arg = stats::setNames(list(rule), verb)
  do.call(gptr::gptr_permissions, c(arg, list(scope = "session")))
  if (identical(verb, "remove")) {
    paste0("Removed ", rule, ".")
  } else {
    paste0("Added ", verb, " rule ", rule, " for this R session.")
  }
}

#' /retry: undo the last turn (gptr_rewind(), P16) and send its prompt again
#' @noRd
cmd_retry = function(args, ctx) {
  s = cmd_session(ctx)
  if (is.null(s) || !isTRUE(session_data(s)$turns >= 1L)) return("There is no answer to retry.")
  f = cmd_late("gptr_rewind")
  if (is.null(f)) return("/retry needs gptr_rewind(), which is not available.")
  f(s, turn = -1L)
  prompt = s$editor_text
  if (!is.character(prompt) || length(prompt) != 1L || !nzchar(prompt)) {
    return("The last prompt could not be recovered.")
  }
  list(prompt = prompt)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-commands$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 58 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/console-commands.R tests/testthat/test-console-commands.R
git commit -m "feat(console): add the slash commands"
```

---

### Task 7: The REPL loop, the stdin UI, the frontend and route, `builtin:console`; INFRA-03 with real SIGINTs

**Files:**
- Modify: `R/console-repl.R` (append)
- Test: `tests/testthat/test-console-repl.R` (append), `tests/testthat/test-console-render.R` (append), `tests/testthat/test-console-interrupt.R` (append)
- Regenerate: `NAMESPACE`, `man/peter.Rd` (`Rscript --vanilla -e 'devtools::document()'`)

**Interfaces:**
- Consumes: Tasks 1-6 (`console_write()`, `console_notice()`, `console_escape()`, `console_print_text()`, `console_out()`, `console_interrupt_key()`, `console_hooks()`, `console_blocks()`, `console_register_commands()`, `console_command()`, `repl_state()`, `console_reader()`, `repl_read_logical()`, `repl_passthrough()`, `console_send()`, `console_abort_stray()`, `console_history_add()`, `repl_prompt()`, `repl_model()`, `repl_mode()`, `repl_eval_env()`); P01 `on_load()`, `workspace_dir()`, `gptr_is_interactive()`, `gptr_can_prompt()` (IC-43), `gptr_opt()`, `gptr_abort()`, `verbosity()`; P02 `gptr_spec(kind, name, ...)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` and the factory's `gptr$register(spec)`, `registry_get()`, `ev_dispatch()`, `ev_new()`; P04 `job_list(kind = NULL)` (P21's rows of kind `session` with status `waiting`, IC-57); P06 `session_data()`, `session_home()`, `run_current()` (the route does not match inside a run), `setting_get("frontend")`; P08's route loop (routes in `order`; a route's `run(call)` value is returned with its visibility; with no prompt and no matching route, `gptr_error_not_available` "peter() without a prompt opens the console, which is not loaded.") and the `gptr_call` bindings `prompt`, `session`, `envir`, `args$stdin`, `args$opts$frontend`; P09 `describe_binding(name, envir, budget = 150L)`; P11 `ui_escape()`, `ui_permission_lines(request)`, `ui_permission_detail(request)`, `ui_parse_choice(ans, labels, multiple = FALSE)`, `ui_questions_via(select, input, qs)`, `ui_can_remember(request)`, the `ui` kind (04 section 10.2 kind 22: `has_ui`, `select`, `input`, `questions`, `notify`, `permission`) and the option `gptr.ui`. Tests: P01 `local_mock_server(scenario, ..., .env = parent.frame())` (scenarios `ttft` and `stream`, fields `provider` and `log()` with `disconnected`), `tracemem_loader()`, `gptr_fake_provider()`, `fake_requests()`; P02 `registry_all(kind)`; P11 `local_scripted_ui()`; processx.
- Produces (04 section 7.14): `builtin_console(gptr)` (hooks, context blocks, the `console` frontend, the `console` route with `order = 30`, the commands), declared with `on_load(ext_declare_builtin("console", builtin_console))`; `console_run(s, envir, stdin = FALSE)`; the frontend's `console_frontend_run(session, ..., call = NULL, envir = NULL, stdin = NULL)`; `console_route_match(call)`, `console_route_run(call)`; `console_stdin_ui(rd)` (a `ui` spec named `console_stdin`); `repl_main(rs)`, `repl_banner(rs)`, `repl_workspace_lines(env, n = 6L)`, `repl_waiting_notice(rs)`, `repl_read(rs)`, `repl_dispatch(rs, line)`, `repl_turn(rs, text)`, `repl_error(e)`, `repl_close(rs)`, `repl_history_on(rs)`; the `?peter` section "The interactive console".

The loop is report 18's `gptr_repl()` (Appendix A.7) on gptr's gateway: each logical input is a slash command, `!code`/`!!code`, or a prompt sent with `console_send()`; Ctrl-C at the prompt prints a hint and twice in a row leaves; an error is printed on stderr after `Error: `, escaped (its line feeds kept, every other control character shown as `<U+XXXX>`), and the REPL goes on; `/exit`, two Ctrl-C at the prompt and the end of piped input return the session invisibly. The banner is NS-1's first line, `gptr <version> | model ... | mode ... | .gptr/ found`, then up to six objects of the evaluation environment described without forcing promises, then the keys. A notice tells when background sessions wait for approval; P21 asks at the next blocking call (IC-57). Under `.stdin = TRUE` the console is a person at a pipe: when unset, `gptr.interactive` is `TRUE` and `gptr.ui` is a stdin UI that answers questions and approvals from the same connection with P11's escaped displays (IC-53), both restored on exit; inputs go to the console history (`gptr.history`) only in interactive consoles. A session the console created gets `session_shutdown` (reason `"exit"`) when the REPL ends; a piped-in session stays the caller's. The `console` route matches a call without a prompt when `gptr_can_prompt()` holds or `.stdin = TRUE`, never while a run's tool executes (model code cannot open a REPL); it runs the frontend named by `.opts$frontend`, then the `frontend` setting, then `console` (IC-69). In IRkernel `gptr_can_prompt()` is `TRUE` and `gptr_readline()` reads the notebook's input box, so the console works there (acceptance 7).

The end-to-end rendering tests (acceptance 3 and 7) and the INFRA-03 test (acceptance 5) are added here because they need the registered built-in. INFRA-03 is report 18's verified e2 driver (Appendix A.8): a processx-driven `R --interactive` child with `TERM=xterm` loads gptr, runs three scenarios against P01's mock server and receives real SIGINTs: during the time to first token, `[c]ontinue` completes the request; while a tool runs, `[s]teer` delivers the text after the tool result; mid-stream, `[a]bort` closes the socket and keeps exactly the received partial. The child uses P12's `anthropic-messages` adapter through the mock provider, so the test runs on CI only (`CI=true`, not on CRAN or Windows), as 05 acceptance 5 states.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-console-repl.R`:

```r
# ---------------------------------------------------------------- Task 7: console sessions

# A console test: a temporary project, no history, no document recording questions
local_console_test = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(history = FALSE, record = "off", .env = .env)
}

test_that("builtin:console registers its frontend, route, commands, blocks and service", {
  routes = registry_all("route")
  console = Filter(function(r) identical(r$name, "console"), routes)
  expect_length(console, 1L)
  expect_identical(console[[1L]]$order, 30)
  expect_false(is.null(registry_get("frontend", "console")))
  expect_false(is.null(registry_get("command", "mode")))
  expect_true(all(c("user_ran", "user_files") %in% registry_names("context_block")))
  expect_true(ext_service_has("console.interrupt_policy"))
})

test_that("the console route never matches inside a run (model code cannot open a REPL)", {
  call = list(prompt = NULL, args = list(stdin = TRUE))
  expect_true(console_route_match(call))
  local_mocked_bindings(run_current = function() structure(new.env(), class = "gptr_run"))
  expect_false(console_route_match(call))
})

test_that("the stdin UI answers selections and approvals from the reader", {
  rd = stdin_reader(c("2", "maybe", "y", "n use base R"))
  ui = console_stdin_ui(rd)
  pick = NULL
  a1 = NULL
  a2 = NULL
  out = utils::capture.output({
    pick = ui$select("Which?", c("Table", "Plot"))
    a1 = ui$permission(list(tool = "r", input = list(code = "y = 2"), risk = list(level = 1L)))
    a2 = ui$permission(list(tool = "r", input = list(code = "unlink('x')"),
                            risk = list(level = 3L)))
  })
  expect_identical(pick, 2L)
  expect_identical(a1$decision, "allow")
  expect_identical(a2, list(decision = "deny", remember = NULL, feedback = "use base R"))
  expect_true(any(grepl("Answer [y]es", out, fixed = TRUE)))
  expect_s3_class(ui, "gptr_ui")
})

test_that("a scripted .stdin console session (acceptance 2)", {
  local_console_test()
  local_scripted_ui()
  fake = gptr_fake_provider(list("first answer", "second answer"))
  e = new.env(parent = globalenv())
  e$x = matrix(1:6, 2)
  local_console_stdin(c("hello there", "!dim(x)", "!!x", "/mode auto", '"""', "line one",
                        "line two", '"""', "/exit"))
  n0 = nrow(showConnections())
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter(.stdin = TRUE, model = fake, envir = e))
  })
  expect_false(res$visible)
  s = res$value
  expect_s3_class(s, "gptr_session")
  expect_identical(s$turns, 2L)
  expect_identical(s$mode, "auto")
  expect_identical(nrow(showConnections()), n0)
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  expect_identical(reqs[[1L]]$last_user, "hello there")
  expect_identical(reqs[[2L]]$last_user, "line one\nline two")
  blocks = last_user_blocks(reqs[[2L]])
  expect_match(blocks[["user_ran"]], "> dim(x)\n#> [1] 2 3", fixed = TRUE)
  expect_false(grepl("> x\n", blocks[["user_ran"]], fixed = TRUE))
  expect_true("mode" %in% names(blocks))
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% "", "")
  expect_true("gptr.mode_change" %in% types)
  expect_true("peter> hello there" %in% out)
  expect_true("first answer" %in% out)
  expect_true("second answer" %in% out)
  expect_true("[1] 2 3" %in% out)
})

test_that("the end of piped input leaves the REPL like /exit", {
  local_console_test()
  local_scripted_ui()
  local_console_stdin("only line")
  res = NULL
  utils::capture.output({
    res = peter(.stdin = TRUE, model = gptr_fake_provider(list("ok")), envir = new.env())
  })
  expect_s3_class(res, "gptr_session")
  expect_identical(res$text, "ok")
})

test_that("in IRkernel peter() without a prompt starts the console on gptr_readline() (acc. 7)", {
  local_console_test()
  withr::local_options(gptr.interactive = NULL, jupyter.in_kernel = TRUE)
  box = new.env(parent = emptyenv())
  box$answers = c("/status", "/exit")
  local_mocked_bindings(
    gptr_is_interactive = function() FALSE, is_testthat = function() FALSE,
    check_running = function() FALSE, is_knitting = function() FALSE,
    gptr_readline = function(prompt = "") {
      a = box$answers[[1L]]
      box$answers = box$answers[-1L]
      a
    })
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter(envir = new.env()))
  })
  expect_false(res$visible)
  expect_null(res$value)
  expect_match(out[[1L]], "^gptr .* \\| model .* \\| mode .* \\| ")
  expect_true(any(grepl("session   (none yet", out, fixed = TRUE)))
  expect_length(box$answers, 0L)
})

test_that("Ctrl-C at the prompt prints a hint; twice in a row leaves", {
  local_console_test()
  ctrl_c = function(prompt = "") {
    signalCondition(structure(class = c("interrupt", "condition"),
                              list(message = "", call = NULL)))
    ""
  }
  local_mocked_bindings(gptr_readline = ctrl_c)
  res = "not set"
  err = utils::capture.output(invisible(utils::capture.output({
    res = console_run(NULL, new.env())
  })), type = "message")
  expect_null(res)
  expect_length(grep("again to leave gptr", err, fixed = TRUE), 1L)
})

test_that("background sessions that wait for approval are announced once (IC-57)", {
  rows = data.frame(id = c("s1", "s2"), kind = "session", name = c("a", "b"),
                    pid = NA_integer_, status = c("waiting", "running"),
                    stringsAsFactors = FALSE)
  local_mocked_bindings(job_list = function(kind = NULL) rows)
  rs = repl_state(NULL, new.env())
  err = utils::capture.output({
    repl_waiting_notice(rs)
    repl_waiting_notice(rs)
  }, type = "message")
  expect_identical(err, paste("[gptr] 1 background session waits for approval;",
                              "the next prompt or gptr_wait() asks."))
  expect_identical(rs$waiting, 1L)
})

test_that("an error is printed on stderr and the REPL goes on", {
  local_console_test()
  local_scripted_ui()
  fake = gptr_fake_provider(list(list(error = "bad key", status = 401L, after = 0L),
                                 "recovered"))
  local_console_stdin(c("first", "second", "/exit"))
  res = NULL
  err = utils::capture.output(invisible(utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, envir = new.env())
  })), type = "message")
  expect_true(any(startsWith(err, "Error: ")))
  expect_identical(res$text, "recovered")
})

test_that("approvals of a .stdin session are answered from the same stdin", {
  local_console_test()
  withr::local_options(gptr.interactive = NULL, gptr.ui = NULL)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "y = 2")), "made y"))
  e = new.env(parent = globalenv())
  local_console_stdin(c("make y", "y", "/exit"))
  res = NULL
  out = utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, envir = e, mode = manual)
  })
  expect_identical(e$y, 2)
  expect_identical(res$text, "made y")
  expect_true(any(grepl("allow? [y]es", out, fixed = TRUE)))
  expect_null(getOption("gptr.ui"))
  expect_null(getOption("gptr.interactive"))
})

test_that("the frontend comes from .opts$frontend or the setting frontend (IC-69)", {
  local_console_test()
  off = gptr_register(gptr_spec("frontend", "probe", run = function(session, ...) "probe ran"))
  withr::defer(off())
  res = withVisible(peter(.stdin = TRUE, .opts = list(frontend = "probe")))
  expect_identical(res$value, "probe ran")
  expect_false(res$visible)
  local_gptr_options(frontend = "probe")
  expect_identical(peter(.stdin = TRUE), "probe ran")
})

test_that("the console echoes an interpolated prompt at verbosity 2", {
  local_console_test()
  local_scripted_ui()
  local_gptr_options(verbose = 2L)
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  e = new.env(parent = globalenv())
  e$cl = 4L
  local_console_stdin(c("describe cluster {cl}", "/exit"))
  out = utils::capture.output(peter(.stdin = TRUE, model = gptr_fake_provider(list("ok")),
                                   envir = e))
  expect_true("> describe cluster 4" %in% out)
})
```

Append to `tests/testthat/test-console-render.R`:

```r
# ---------------------------------------------------------------- Task 7: end-to-end rendering

test_that("a streamed reply is printed verbatim and never evaluated (acceptance 3, rule C1)", {
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  withr::local_envvar(GPTR_PWNED = NA)
  fake = gptr_fake_provider(list("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care."))
  res = NULL
  out = utils::capture.output({
    res = withVisible(peter("hi", model = fake, envir = new.env()))
  })
  expect_true("Use {Sys.setenv(GPTR_PWNED = \"1\")} with care." %in% out)
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_false(res$visible)
  expect_match(out[[length(out)]], "^  done \\| 1 turn \\| ")
})

test_that("nothing is rendered at verbosity 0 (knitr, testthat)", {
  local_project()
  local_gptr_options(verbose = 0L, record = "off")
  out = utils::capture.output(invisible(peter("hi", model = gptr_fake_provider(list("quiet")),
                                             envir = new.env())))
  expect_false(any(grepl("quiet", out, fixed = TRUE)))
})

test_that("tool calls of a run show escaped previews and results (acceptance 7)", {
  local_project()
  local_gptr_options(verbose = 2L, record = "off")
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1 # \033[31mred")),
                                 "done"))
  e = new.env(parent = globalenv())
  out = utils::capture.output(peter("go", model = fake, envir = e, mode = auto))
  expect_true("  * r  z = 1 # <U+001B>[31mred" %in% out)
  expect_true("    -> + z" %in% out)
  expect_false(any(grepl("\033", out, fixed = TRUE)))
  expect_identical(e$z, 1)
})

test_that("artifact_start events print the NS-8 line through builtin:console (acceptance 7)", {
  local_gptr_options(verbose = 2L)
  out = utils::capture.output(invisible(ev_dispatch("artifact_start", ev_new(
    "artifact_start", id = "marker-explorer", url = "http://127.0.0.1:4827", version = 1L))))
  expect_identical(out,
                   "artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)")
})
```

Append to `tests/testthat/test-console-interrupt.R`:

```r
# ---------------------------------------------------------------- Task 7: INFRA-03 (real SIGINTs)

# Drives an interactive R child through processx like a user at a terminal (report 18 A.8
# e2_driver.R): reads its merged stdout/stderr, waits for markers, sends lines
infra03_driver = function(p) {
  st = new.env(parent = emptyenv())
  st$out = ""
  st$seen = 0L
  pump = function(ms = 200L) {
    p$poll_io(ms)
    x = p$read_output()
    if (nzchar(x)) st$out = paste0(st$out, x)
    invisible(NULL)
  }
  st$wait_for = function(pattern, timeout = 30) {
    deadline = Sys.time() + timeout
    repeat {
      pump()
      rest = substring(st$out, st$seen + 1L)
      pos = regexpr(pattern, rest, fixed = TRUE)
      if (pos > 0L) {
        st$seen = st$seen + pos + nchar(pattern) - 1L
        return(TRUE)
      }
      if (!p$is_alive() || Sys.time() > deadline) return(FALSE)
    }
  }
  st$send = function(x) {
    Sys.sleep(0.2)
    p$write_input(paste0(x, "\n"))
  }
  st$has = function(pattern) grepl(pattern, st$out, fixed = TRUE)
  st$value = function(key) {
    m = regmatches(st$out, regexpr(paste0(key, "\\[[^]]*\\]"), st$out))
    if (!length(m)) return(NA_character_)
    sub("\\]$", "", sub(paste0("^", key, "\\["), "", m))
  }
  st
}

# The child script: loads gptr (tracemem_loader(), P01), defines one function per scenario
infra03_child = function(providers) {
  c(
    tracemem_loader(),
    paste0("options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off', ",
           "cli.num_colors = 1L)"),
    sprintf("prov = readRDS('%s')", providers),
    "e = new.env(parent = globalenv())",
    "msg_texts = function(msgs) vapply(msgs, function(m) {",
    "  paste(vapply(Filter(function(b) identical(b$type, 'text'), m$content),",
    "               function(b) b$text, ''), collapse = '')",
    "}, '')",
    "step_ttft = function() {",
    "  s = peter('first', model = prov$ttft, envir = e, mode = auto)",
    "  cat('STATUS-TTFT', s$status, '\\n')",
    "}",
    "step_tool = function() {",
    "  fake = gptr_fake_provider(list(",
    "    list(tool = 'r', input = list(code = 'Sys.sleep(3); 1')), 'after the tool'))",
    "  peter('tool', model = fake, envir = e, mode = auto)",
    "  req = fake$log$requests[[2L]]$messages",
    "  roles = vapply(req, function(m) m$role, '')",
    "  steer = which(grepl('use base R only', msg_texts(req), fixed = TRUE))",
    "  tool = which(roles == 'tool_result')",
    "  ok = length(steer) == 1L && length(tool) >= 1L && steer[[1L]] > tool[[1L]]",
    "  cat('STEER-AFTER-TOOL', ok, '\\n')",
    "}",
    "step_abort = function() {",
    "  res = tryCatch(peter('stream', model = prov$stream, envir = e, mode = auto),",
    "                 interrupt = function(i) 'INTERRUPTED')",
    "  s = gptr_last()",
    "  m = s$messages[[length(s$messages)]]",
    "  cat('STOP', m$stop_reason, '\\n')",
    "  cat('PARTIAL[', msg_texts(list(m)), ']\\n', sep = '')",
    "  cat('ABORT-DONE', identical(res, 'INTERRUPTED'), '\\n')",
    "}",
    "cat('CHILD READY\\n')"
  )
}

test_that("INFRA-03: real SIGINTs continue, steer and abort runs (acceptance 5)", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not(identical(Sys.getenv("CI"), "true"), "INFRA-03 drives an interactive R on CI")
  ttft = local_mock_server("ttft", delay = 3, n = 4L, interval = 0.05)
  stream = local_mock_server("stream", n = 40L, interval = 0.25)
  dir = withr::local_tempdir("gptr-infra03-")
  providers = file.path(dir, "providers.rds")
  saveRDS(list(ttft = ttft$provider, stream = stream$provider), providers)
  child = file.path(dir, "child.R")
  writeLines(infra03_child(normalizePath(providers, winslash = "/")), child)
  # a complete environment (processx rejects NA, IC-60) without the IDE variables that would
  # make front_end() report RStudio, Positron, VS Code or Jupyter (abort-only, no menu)
  env = unclass(Sys.getenv())
  env = env[!names(env) %in% c("RSTUDIO", "POSITRON", "TERM_PROGRAM", "JPY_SESSION_NAME",
                               "QUARTO_DOCUMENT_PATH", "QUARTO_DOCUMENT_FILE")]
  env[["TERM"]] = "xterm"
  env[["LANG"]] = "en_US.UTF-8"
  env[["R_LIBS"]] = paste(.libPaths(), collapse = .Platform$path.sep)
  # `R --interactive`, not rscript_path(): only R reads its console from a pipe interactively
  # (report 18 A.8); an absolute path, so R CMD check's dummy `R` on PATH is never used (IC-60)
  p = processx::process$new(file.path(R.home("bin"), "R"),
                            c("--vanilla", "--interactive", "--quiet", "--no-echo"),
                            stdin = "|", stdout = "|", stderr = "2>&1", env = env,
                            cleanup = TRUE)
  withr::defer(if (p$is_alive()) p$kill())
  drv = infra03_driver(p)
  p$write_input(sprintf("source('%s')\n", normalizePath(child, winslash = "/")))
  expect_true(drv$wait_for("CHILD READY", timeout = 120))

  # 1. SIGINT while waiting for the first byte, then [c]ontinue: the request completes
  drv$send("step_ttft()")
  Sys.sleep(1)
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("c")
  expect_true(drv$wait_for("STATUS-TTFT idle"))
  expect_true(drv$has("tok04"))

  # 2. SIGINT while a tool runs, then [s]teer: the steer arrives after the tool result
  drv$send("step_tool()")
  expect_true(drv$wait_for("Sys.sleep(3)"))
  Sys.sleep(0.5)
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("s")
  expect_true(drv$wait_for("steer>"))
  drv$send("use base R only")
  expect_true(drv$wait_for("STEER-AFTER-TOOL TRUE"))

  # 3. SIGINT mid-stream, then [a]bort: the socket closes and the partial is what arrived
  drv$send("step_abort()")
  expect_true(drv$wait_for("tok03"))
  p$interrupt()
  expect_true(drv$wait_for("paused"))
  drv$send("a")
  expect_true(drv$wait_for("ABORT-DONE TRUE"))
  expect_true(drv$has("STOP aborted"))
  partial = drv$value("PARTIAL")
  full = paste(sprintf("tok%02d ", 1:40), collapse = "")
  expect_true(nzchar(partial))
  expect_true(startsWith(full, partial))
  expect_lt(nchar(partial), nchar(full))
  deadline = Sys.time() + 15
  closed = FALSE
  while (!closed && Sys.time() < deadline) {
    closed = any(stream$log()$disconnected %in% TRUE)
    if (!closed) Sys.sleep(0.25)
  }
  expect_true(closed)
  p$write_input("q('no')\n")
})
```

- [ ] **Step 2: Run them to verify they fail**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-(repl|render|interrupt)$")'
```

Expected: a non-zero FAIL count with `SKIP 1` (INFRA-03 off CI) and a PASS count of at least 186 (the expectations of Tasks 1-5 still pass). The new console-repl tests error with `could not find function "console_stdin_ui"` (and `repl_waiting_notice`, `console_run`, `console_route_match`) or with `peter() without a prompt opens the console, which is not loaded.` (class `gptr_error_not_available`), and the registration test fails; the new console-render tests fail because no renderer hook is registered yet (nothing is printed).

- [ ] **Step 3: Write the implementation and regenerate the documentation**

Append to `R/console-repl.R`:

```r
# ---------------------------------------------------------------------------------------------
# The REPL (Task 7): loop, banner, stdin UI, frontend, route and builtin:console. The loop is
# report 18 A.7 gptr_repl() on gptr's gateway: each logical input is a slash command
# (console-commands.R), `!code`/`!!code` (repl_passthrough()) or a prompt (console_send()).
# Ctrl-C at the prompt prints a hint; twice in a row leaves. Errors are printed escaped on
# stderr and the REPL goes on.
# ---------------------------------------------------------------------------------------------

#' The `ui` backend of a REPL driven by `.stdin = TRUE`: questions and approvals are answered from
#' the same persistent stdin connection (report 18 2.1.3; its e1 session answers prompts from the
#' pipe). It mirrors P11's console UI (`ui_console_select()`, `ui_console_permission()`) with the
#' REPL's reader instead of gptr_readline(), and shows the same escaped lines (IC-53 item 8).
#' @noRd
console_stdin_ui = function(rd) {
  read = function(prompt) {
    x = rd$read(prompt)
    if (length(x) != 1L || is.na(x)) NA_character_ else x
  }
  say = function(lines) console_write(lines)
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    labels = as.character(unlist(choices))
    say(c("", ui_escape(title), if (length(details)) paste0("  | ", ui_escape(details)),
          sprintf("  %d: %s", seq_along(labels), ui_escape(labels))))
    for (attempt in seq_len(5L)) {
      ans = read("Choose (a number): ")
      if (is.na(ans)) return(NA_integer_)
      if (!nzchar(trimws(ans))) {
        if (length(default)) return(as.integer(default))
        next
      }
      idx = ui_parse_choice(ans, labels, multiple)
      if (length(idx) && !anyNA(idx)) return(idx)
      if (allow_other) return(structure(NA_integer_, other = trimws(ans)))
      say("  Please enter one of the numbers shown.")
    }
    NA_integer_
  }
  input = function(prompt, default = "", secret = FALSE) {
    # the default comes from the model's `ask` questions: escaped like the prompt (IC-53 item 8)
    shown = if (nzchar(default)) paste0(prompt, " [", default, "]: ") else paste0(prompt, ": ")
    ans = read(ui_escape(shown))
    if (is.na(ans)) return(NA_character_)
    if (!nzchar(ans)) default else ans
  }
  permission = function(request) {
    can_remember = ui_can_remember(request)
    opts = if (can_remember) "[y]es / [a]lways / [n]o / [?]" else "[y]es / [n]o / [?]"
    say(ui_permission_lines(request))
    for (attempt in seq_len(5L)) {
      ans = read(paste0("  allow? ", opts, ": "))
      if (is.na(ans)) return(list(decision = "abort", remember = NULL, feedback = NULL))
      a = trimws(ans)
      low = tolower(a)
      if (low %in% c("y", "yes")) return(list(decision = "allow", remember = NULL, feedback = NULL))
      if (low %in% c("a", "always") && can_remember) {
        return(list(decision = "allow", remember = "session", feedback = NULL))
      }
      if (low %in% c("p", "project") && can_remember) {
        return(list(decision = "allow", remember = "project", feedback = NULL))
      }
      if (low %in% c("n", "no")) return(list(decision = "deny", remember = NULL, feedback = NULL))
      if (grepl("^(n|no)\\s+", low)) {
        return(list(decision = "deny", remember = NULL, feedback = sub("^[Nn][Oo]?\\s+", "", a)))
      }
      if (identical(low, "?")) {
        say(ui_permission_detail(request))
        next
      }
      say(paste0("  Answer ", opts, "."))
    }
    list(decision = "deny", remember = NULL, feedback = NULL)
  }
  gptr_spec("ui", "console_stdin",
            has_ui = function() TRUE,
            select = select,
            input = input,
            questions = function(qs) ui_questions_via(select, input, qs),
            notify = function(text, level = "info") {
              console_notice("[", level, "] ", ui_escape(text))
            },
            permission = permission)
}

#' Up to `n` objects of the evaluation environment, described without forcing promises
#' (describe_binding(), P09) for the banner
#' @noRd
repl_workspace_lines = function(env, n = 6L) {
  nms = sort(ls(env), method = "radix")
  if (!length(nms)) return(character())
  shown = utils::head(nms, n)
  lines = vapply(shown, function(nm) {
    tryCatch(describe_binding(nm, env, budget = 40L)[[1L]], error = function(e) nm)
  }, "")
  more = length(nms) - length(shown)
  c(console_escape(unname(lines), FALSE),
    if (more > 0L) paste0("(+ ", more, " more objects: /env)"))
}

#' The banner (architecture 6.17, NS-1): `gptr <version> | model ... | mode ... | .gptr/ found`,
#' the workspace summary and the keys
#' @noRd
repl_banner = function(rs) {
  ws = if (is.null(workspace_dir())) "no .gptr/" else ".gptr/ found"
  version = tryCatch(as.character(utils::packageVersion("gptr")), error = function(e) "?")
  console_write(paste0("gptr ", version, " | model ", console_escape(repl_model(rs), FALSE),
                       " | mode ", console_escape(repl_mode(rs), FALSE), " | ", ws))
  lines = repl_workspace_lines(repl_eval_env(rs))
  if (length(lines)) console_write(paste0("  ", lines))
  console_write(paste0("/help lists commands; ", console_interrupt_key(),
                       " pauses an answer, twice at the prompt leaves"))
  invisible(NULL)
}

#' A notice when background sessions wait for approval (IC-57): the question itself is asked at
#' the next blocking call (P21 resumes waiting sessions inside every reactor pump)
#' @noRd
repl_waiting_notice = function(rs) {
  jobs = tryCatch(job_list("session"), error = function(e) NULL)
  n = if (is.data.frame(jobs) && nrow(jobs)) sum(jobs$status == "waiting") else 0L
  if (n > 0L && n != rs$waiting) {
    what = if (n == 1L) " background session waits" else " background sessions wait"
    console_notice("[gptr] ", n, what, " for approval; the next prompt or gptr_wait() asks.")
  }
  rs$waiting = n
  invisible(n)
}

#' Do REPL inputs go to the console history? (gptr.history; interactive consoles only)
#' @noRd
repl_history_on = function(rs) {
  isTRUE(gptr_opt("history")) && !isTRUE(rs$stdin) && isTRUE(gptr_is_interactive())
}

#' Print an error on stderr (escaped, line feeds kept) and keep the REPL alive
#' @noRd
repl_error = function(e) {
  console_notice("Error: ", console_escape(conditionMessage(e)))
  invisible(NULL)
}

#' Read one logical input; Ctrl-C at the prompt returns an interrupt marker
#' @noRd
repl_read = function(rs) {
  tryCatch(repl_read_logical(rs$reader, repl_prompt(rs)),
           interrupt = function(e) structure(list(), class = "gptr_repl_interrupt"))
}

#' One prompt: console_send(), then the answer when the renderer did not stream it
#' @noRd
repl_turn = function(rs, text) {
  res = console_send(rs, text)
  if (identical(res$status, "error")) {
    repl_error(res$error)
  } else if (identical(res$status, "ok")) {
    value = res$value
    if (inherits(value, "gptr_session")) {
      if (verbosity() < 2L) console_print_text(value$text)
    } else if (!is.null(value)) {
      console_out(utils::capture.output(print(value)))
    }
  }
  invisible(res$status)
}

#' Dispatch one logical input: /command, !code, or a prompt
#' @noRd
repl_dispatch = function(rs, line) {
  text = trimws(line)
  if (!nzchar(text)) return(invisible(NULL))
  if (repl_history_on(rs)) console_history_add(line)
  tryCatch({
    if (startsWith(text, "/")) {
      console_command(text, rs$session, send = function(prompt) repl_turn(rs, prompt))
    } else if (startsWith(text, "!")) {
      repl_passthrough(rs, text)
    } else {
      repl_turn(rs, text)
    }
  }, interrupt = function(e) {
    if (!is.null(rs$session)) console_abort_stray(rs$session)
    console_notice("[gptr] interrupted")
  }, error = function(e) repl_error(e))
  invisible(NULL)
}

#' Close the reader (the `.stdin` connection, IC-59) and drop the environment reference (R2)
#' @noRd
repl_close = function(rs) {
  if (!is.null(rs$reader)) rs$reader$close()
  rs$envir = NULL
  invisible(NULL)
}

#' The REPL loop on a state from repl_state(); returns the session invisibly
#'
#' Under `.stdin = TRUE` the console is a person at a pipe: when the options are unset, it sets
#' `gptr.interactive = TRUE` (streamed answers, approvals asked) and `gptr.ui` to the stdin UI,
#' and restores both on exit. A session the console created gets `session_shutdown` (reason
#' "exit") when the REPL ends; a piped-in session stays the caller's.
#' @noRd
repl_main = function(rs) {
  .gptr_repl = rs
  created = is.null(rs$session)
  on.exit(repl_close(rs), add = TRUE)
  rs$reader = console_reader(rs$stdin, echo = rs$stdin)
  if (isTRUE(rs$stdin)) {
    set = list()
    if (is.null(getOption("gptr.interactive"))) set$gptr.interactive = TRUE
    if (is.null(getOption("gptr.ui"))) set$gptr.ui = console_stdin_ui(rs$reader)
    if (length(set)) {
      old = options(set)
      on.exit(options(old), add = TRUE)
    }
  }
  repl_banner(rs)
  repeat {
    if (isTRUE(rs$exit)) break
    repl_waiting_notice(rs)
    line = repl_read(rs)
    if (inherits(line, "gptr_repl_interrupt")) {
      rs$interrupts = rs$interrupts + 1L
      if (rs$interrupts >= 2L) break
      console_notice("[gptr] press ", console_interrupt_key(),
                     " again to leave gptr, or type /exit")
      next
    }
    if (is.na(line)) break
    rs$interrupts = 0L
    repl_dispatch(rs, line)
  }
  s = rs$session
  if (created && inherits(s, "gptr_session")) {
    tryCatch(ev_dispatch("session_shutdown",
                         ev_new("session_shutdown", session = session_data(s)$id,
                                reason = "exit"), session = s),
             error = function(e) NULL)
  }
  invisible(s)
}

#' The REPL on `s` (a new session is created at the first prompt when `s` is NULL)
#'
#' @param s A `gptr_session` or `NULL`.
#' @param envir Environment where `!code` runs and objects persist (an existing session's kept
#'   home wins, IC-40).
#' @param stdin Read input from one persistent `file("stdin")` connection.
#' @return The session, invisibly, when the user leaves (`/exit`, two Ctrl-C at the prompt, the
#'   end of piped input); `NULL` when no prompt was sent.
#' @noRd
console_run = function(s, envir, stdin = FALSE) {
  repl_main(repl_state(s, envir, stdin, call = NULL))
}

#' run() of the `console` frontend: the REPL on the call's session and environment
#' @noRd
console_frontend_run = function(session, ..., call = NULL, envir = NULL, stdin = NULL) {
  if (is.null(envir) && !is.null(call)) envir = call$envir
  if (!is.environment(envir) && inherits(session, "gptr_session")) envir = session_home(session)
  if (!is.environment(envir)) {
    gptr_abort("The console needs an environment to work in; pass envir =.",
               "invalid_argument", arg = "envir", expected = "an environment")
  }
  if (is.null(stdin)) stdin = !is.null(call) && isTRUE(call$args$stdin)
  repl_main(repl_state(session, envir, stdin, call))
}

#' match() of the `console` route (order 30): no prompt, and someone can answer (IC-43) or
#' `.stdin = TRUE`; never while a run's tool executes (`run_current()`): model code must not
#' open a REPL that reads the user's input or re-points `gptr.ui` (IC-53)
#' @noRd
console_route_match = function(call) {
  is.null(call$prompt) && is.null(run_current()) &&
    (isTRUE(call$args$stdin) || isTRUE(gptr_can_prompt()))
}

#' run() of the `console` route: the frontend named by `.opts$frontend`, else the setting
#' `frontend`, else "console" (IC-69); the session comes back invisibly
#' @noRd
console_route_run = function(call) {
  name = call$args$opts$frontend %||% setting_get("frontend") %||% "console"
  sid = if (is.null(call$session)) NULL else session_data(call$session)$id
  fe = registry_get("frontend", name, session = sid)
  if (is.null(fe)) {
    gptr_abort(paste0("No frontend named '", name, "' is registered."), "invalid_argument",
               arg = "frontend", expected = "a registered frontend name")
  }
  invisible(fe$run(call$session, call = call))
}

#' The `console` built-in (contract 7.14, 10.3): renderer hooks, context blocks, the `console`
#' frontend and route, the slash commands. The `console.interrupt_policy` service is declared in
#' console-interrupt.R and owned by this built-in.
#' @noRd
builtin_console = function(gptr) {
  for (spec in console_hooks()) gptr$register(spec)
  for (spec in console_blocks()) gptr$register(spec)
  gptr$register(gptr_spec("frontend", "console", run = console_frontend_run))
  gptr$register(gptr_spec("route", "console", order = 30, match = console_route_match,
                          run = console_route_run,
                          description = paste("peter() with no prompt: the console on the",
                                              "piped session or a new one")))
  console_register_commands(gptr)
  invisible(NULL)
}

on_load(ext_declare_builtin("console", builtin_console))

#' @section The interactive console:
#' `peter()` without a prompt starts a console when someone can answer (an interactive R
#' session or IRkernel); `peter(.stdin = TRUE)` reads the console's input from standard input,
#' one line at a time. `s |> peter()` opens the console on `s`. Each line is one of:
#'
#' * a prompt, sent as `s |> peter("...")` (with `{name}` interpolation); `@file` adds the head of
#'   a file and `@object` attaches an object by name;
#' * `!code` runs R code in the session's environment and adds the code and its output to the
#'   next prompt (at most 300 tokens); `!!code` runs it without telling the model;
#' * a fenced ```` ```r ```` block (like `!`), a `"""` block (a multi-line prompt), or a line
#'   ending in a backslash (continued);
#' * a slash command: `/help` lists them (`/model`, `/mode`, `/plan`, `/tools`, `/env`,
#'   `/compact`, `/cost`, `/context`, `/status`, `/clear`, `/resume`, `/fork`, `/doc`, `/skills`,
#'   `/skill:<name>`, `/mcp`, `/permissions`, `/retry`, `/exit`, and the commands of plugins).
#'
#' Ctrl-C (Esc in RStudio and Rgui) while an answer runs opens a pause menu in terminal R:
#' `[s]teer` (delivered after the current tool results), `[f]ollow-up`, `[c]ontinue`, `[a]bort`
#' and, with the later package, `[b]ackground`; a second Ctrl-C aborts. Elsewhere Ctrl-C aborts.
#' `/exit` (or Ctrl-C twice at the prompt) returns the session invisibly, so `s = peter()` keeps
#' the conversation.
#'
#' Options: `gptr.verbose` (0 silent, 1 progress on stderr, 2 streamed console, 3 debug; by
#' default 0 in knitr and testthat, 1 under Rscript, 2 at the console), `gptr.max_turns_console`
#' (turns per console prompt, default 200), `gptr.history` (add console inputs to R's history,
#' default `TRUE`).
#' @name peter
#' @rdname peter
NULL
```

Then regenerate `NAMESPACE` and `man/peter.Rd` (the console section joins `?peter`; P14 adds no export):

```bash
Rscript --vanilla -e 'devtools::document()'
grep -c "The interactive console" man/peter.Rd
git diff --stat NAMESPACE
```

Expected: `1` from the `grep`; no change to `NAMESPACE`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-(repl|render|interrupt)$")'
CI=true Rscript --vanilla -e 'devtools::test(filter = "^console-interrupt$")'
LC_ALL=C Rscript --vanilla -e 'devtools::test(filter = "^console-(repl|render|interrupt)$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 247 ]` (console-render 72, console-interrupt 36, console-repl 139; INFRA-03 skipped off CI); with `CI=true` on Linux or macOS `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]`; in the C locale `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 243 ]` (the width test of Task 1 also skips).

- [ ] **Step 5: Commit**

```bash
git add R/console-repl.R tests/testthat/test-console-repl.R tests/testthat/test-console-render.R tests/testthat/test-console-interrupt.R NAMESPACE man/peter.Rd
git commit -m "feat(console): add the REPL loop, the console frontend and route, builtin:console"
```

---

### Task 8: The JSONL sink, the `jsonl` frontend and `builtin:jsonl`

**Files:**
- Create: `R/console-jsonl.R`
- Test: `tests/testthat/test-console-jsonl.R` (create)
- Test: `tests/testthat/test-console-render.R` (append the INFRA-27 test, acceptance 4: 03 section 6.18 row 27 names `test-console-render.R` as its acceptance file, and P24's INFRA suite runs `console-render`)

**Interfaces:**
- Consumes: Tasks 4-7 (`repl_state()`, `console_reader()`, `console_send()`, `repl_close()`, the `.gptr_repl` frame binding); P01 `json_encode(x)`, `json_decode(text)`, `json_obj()`, `msg_to_json(msg)`, `block_to_json(block)` (the JSON shapes of 04 sections 4.1-4.2 and the one mapping table of 4.8), `as_utf8()`, `check_class()`, `gptr_abort()`, `on_load()`; P02 `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)`, `hook_remove(id)`, `ev_catalogue()` (column `event`), `ev_new()`, `gptr_spec()`, `ext_declare_builtin()`; P03 `redact_tree(x, profile = "persist", structural = FALSE)`, `redact(x, profile = "persist")`; P06 `session_data()`; P08 SDK verb `gptr_wait(x, timeout = Inf)` (`gptr-sdk.R`). Tests: P01 `msg_assistant()`, `gptr_fake_provider()`, `fake_requests()`, `local_project()`, `local_gptr_options()`; P03 `vault_reset()`, `secret_register(value, name, source = "user", active = TRUE, origin = NULL)`; P08 `peter()` (`.run = FALSE`), `gptr_step(s, turns = 1L)`.
- Produces (04 section 7.14): `jsonl_sink(session, con)` -> a detach function, invisibly (session hooks of rank 0, dropped by P02 at the session's `session_shutdown`; with `session = NULL`, process-level hooks of rank 3 for every session); `builtin_jsonl(gptr)` (the `jsonl` frontend), declared with `on_load(ext_declare_builtin("jsonl", builtin_jsonl))`; `jsonl_frontend_run(session, ..., call = NULL, envir = NULL, stdin = NULL, con = stdout())`; `jsonl_events()`, `jsonl_write(con, event)`, `jsonl_line(event)`, `jsonl_event(event)`, `jsonl_ts(ts)`, `jsonl_value(x)`, `jsonl_msg(m)`, `jsonl_block(b)`, `jsonl_is_msg(x)`, `jsonl_is_block(x)`, `jsonl_prompt_text(line)`, `jsonl_error_event(e, session = NULL)`.

The sink writes every catalogued event (04 section 10.4, names verbatim; channels are not catalogued and not written) as one JSON object per line in the 04 section 4.5 JSON form: the payload's field names, `ts` as ISO 8601 UTC with milliseconds, messages and content blocks in their JSON shapes; functions, environments and other live objects are dropped. Each line passes the `persist` redaction profile (tree, then text) on top of the `stream` profile that `ev_dispatch()` applied (04 section 1.4), so no registered secret reaches it (acceptance 6), and a writing error never fails the run (fail-closed events would otherwise deny). The sink writes to a connection its caller owns and opens none (IC-59), flushing each line so a reading parent sees it at once (P19's worker children write it, IC-28). Rendering never touches the sink, so the transcript of a run is the same at every verbosity (INFRA-27, acceptance 4; the test is appended to `test-console-render.R`, the file 03 section 6.18 names for INFRA-27 "rendering decoupled from transport", with its own file-local helpers). The `jsonl` frontend streams the events of a piped session until it settles (`s |> peter(.opts = list(frontend = "jsonl"))` at a console: a no-prompt call needs someone to answer or `.stdin`, 04 section 6.1.1 step 4; P19's workers call the frontend's `run()` from the registry); with `.stdin = TRUE` it reads one prompt per line (plain text or `{"type":"prompt","text":...}`; `/exit` ends), sends each through `console_send()` like a console prompt, writes the events of every session and prints nothing else (`gptr.verbose` is 0 for the duration).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-console-jsonl.R`:

```r
# tests/testthat/test-console-jsonl.R -- the JSONL sink and the `jsonl` frontend (plan P14,
# Task 8). The INFRA-27 test (acceptance 4) is in test-console-render.R (03 section 6.18).

# One fake-provider run (an `r` call, then an answer) streamed to a JSONL file at `verbose`
jsonl_run = function(verbose, script = NULL) {
  local_gptr_options(verbose = verbose, quiet = TRUE, record = "off")
  script = script %||% list(list(tool = "r", input = list(code = "z = 1")), "The answer is 42.")
  fake = gptr_fake_provider(script)
  s = peter("compute", model = fake, .run = FALSE, envir = new.env(parent = globalenv()),
           mode = auto)
  file = tempfile(fileext = ".jsonl")
  on.exit(unlink(file), add = TRUE)
  con = file(file, open = "wb")
  off = jsonl_sink(s, con)
  utils::capture.output(gptr_step(s, turns = Inf))
  off()
  close(con)
  readLines(file, encoding = "UTF-8", warn = FALSE)
}

test_that("jsonl_event() gives the contract 4.5 JSON form", {
  msg = msg_assistant("hi", api = "fake", provider = "fake", model = "fake-1",
                      stop_reason = "tool_use")
  ev = ev_new("message_end", session = "s0123456789", run = "u01234567", role = "assistant",
              message = msg)
  ev$ts = 1790000000.5
  x = jsonl_event(ev)
  expect_identical(x$ts, "2026-09-21T14:13:20.500Z")
  expect_identical(x$type, "message_end")
  expect_identical(x$message$stopReason, "toolUse")
  expect_identical(x$message$content[[1L]]$text, "hi")
  expect_false("turn" %in% names(x))
  line = jsonl_line(ev)
  expect_false(grepl("\n", line, fixed = TRUE))
  expect_identical(json_decode(line)$message$role, "assistant")
})

test_that("jsonl_value() keeps data and drops live objects", {
  x = jsonl_value(list(a = 1, f = function() 1, e = new.env(), q = quote(x + 1),
                       d = as.Date("2026-09-30"), k = factor("lvl")))
  expect_identical(x, list(a = 1, d = "2026-09-30", k = "lvl"))
  df = jsonl_value(data.frame(t = as.POSIXct(0, origin = "1970-01-01", tz = "UTC"), n = 2))
  expect_identical(df$t, "1970-01-01T00:00:00.000Z")
  expect_identical(jsonl_value(list(f = function() 1)), json_obj())
  expect_identical(json_encode(jsonl_value(df)), "[{\"t\":\"1970-01-01T00:00:00.000Z\",\"n\":2}]")
})

test_that("jsonl_sink() needs an open connection and subscribes to every catalogued event", {
  local_project()
  s = peter("hi", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
  expect_error(jsonl_sink(s, "stdout"), class = "gptr_error_invalid_argument")
  expect_setequal(jsonl_events(), ev_catalogue()$event)
})

test_that("a run gives a JSON line per event, in order (contract 4.5)", {
  local_project()
  lines = jsonl_run(0L)
  types = vapply(lines, function(l) json_decode(l)$type, "", USE.NAMES = FALSE)
  # P06's run_start() takes the queued prompt (queue_update) and freezes the prompt of a new
  # session (session_start) before agent_start
  expect_true(all(c("queue_update", "session_start", "agent_start") %in% types))
  expect_lt(match("session_start", types), match("agent_start", types))
  expect_lt(match("agent_start", types), match("message_update", types))
  expect_identical(types[[length(types)]], "agent_end")
  expect_true(all(c("message_update", "message_end", "tool_execution_start",
                    "tool_execution_end", "turn_end") %in% types))
  ends = Filter(function(x) identical(x$type, "message_end"), lapply(lines, json_decode))
  roles = vapply(ends, function(x) x$message$role, "")
  expect_true("toolResult" %in% roles)
})

test_that("no registered secret reaches the sink (acceptance 6)", {
  local_project()
  vault_reset()
  withr::defer(vault_reset())
  key = paste0("sk-ant-api03-", strrep("Q7x", 12), "AA")
  secret_register(key, "ANTHROPIC_API_KEY", source = "test")
  lines = jsonl_run(0L, script = list(paste("The key is", key, "and it must not leak.")))
  expect_gt(length(lines), 3L)
  expect_false(any(grepl(key, lines, fixed = TRUE)))
  expect_false(any(grepl(substr(key, 1L, 24L), lines, fixed = TRUE)))
})

test_that("the jsonl frontend streams a piped session until it settles", {
  local_project()
  local_gptr_options(record = "off")
  s = peter("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
  file = withr::local_tempfile(fileext = ".jsonl")
  con = file(file, open = "wb")
  res = jsonl_frontend_run(s, con = con)
  close(con)
  expect_identical(res, s)
  expect_identical(s$status, "idle")
  types = vapply(readLines(file, encoding = "UTF-8"), function(l) json_decode(l)$type, "",
                 USE.NAMES = FALSE)
  expect_identical(types[[length(types)]], "agent_end")
  expect_error(jsonl_frontend_run(NULL, con = stdout()), class = "gptr_error_invalid_argument")
})

test_that("peter(.stdin = TRUE, .opts = list(frontend = 'jsonl')) reads prompts, writes events", {
  local_project()
  local_gptr_options(record = "off")
  lines = c("hello", "{\"type\":\"prompt\",\"text\":\"again\"}", "/exit")
  local_mocked_bindings(console_stdin_open = function() textConnection(lines))
  fake = gptr_fake_provider(list("one", "two"))
  res = NULL
  out = utils::capture.output({
    res = peter(.stdin = TRUE, model = fake, .opts = list(frontend = "jsonl"),
               envir = new.env())
  })
  expect_identical(res$turns, 2L)
  expect_identical(fake_requests(fake)[[2L]]$last_user, "again")
  decoded = lapply(out, json_decode)
  expect_true(all(vapply(decoded, function(x) is.character(x$type), NA)))
  expect_identical(sum(vapply(decoded, function(x) identical(x$type, "agent_end"), NA)), 2L)
  expect_false(any(grepl("^gptr ", out)))
})

test_that("builtin:jsonl registers the jsonl frontend", {
  expect_false(is.null(registry_get("frontend", "jsonl")))
})
```

Append to `tests/testthat/test-console-render.R` (the INFRA-27 acceptance file of 03 section 6.18; the helpers are file-local, since 05 gives P14 no helper file):

```r
# ---------------------------------------------------------------- Task 8: INFRA-27

# Rendering is decoupled from transport (INFRA-27, 03 section 2.2 rule 2): the JSONL transcript
# of one run does not depend on what the renderer prints.

# Fields that depend on time or on generated ids (contract 12.3 golden-event rule: ts, session,
# run, request_id; plus the other clocks and the prefix guard's view of the request)
infra27_volatile = c("ts", "timestamp", "session", "run", "request_id", "requestId", "elapsed",
                     "started", "seconds", "view", "response_id", "responseId")

infra27_norm_value = function(x) {
  if (is.list(x)) {
    nms = names(x)
    if (!is.null(nms)) x = x[!(nms %in% infra27_volatile)]
    return(lapply(x, infra27_norm_value))
  }
  if (is.character(x)) {
    x = gsub("\\bs[0-9a-f]{10}\\b", "<session>", x, perl = TRUE)
    x = gsub("\\bu[0-9a-f]{8}\\b", "<run>", x, perl = TRUE)
    x = gsub("\\bq[0-9a-f]{12}\\b", "<request>", x, perl = TRUE)
  }
  x
}

infra27_normalise = function(lines) {
  vapply(lines, function(l) json_encode(infra27_norm_value(json_decode(l))), "",
         USE.NAMES = FALSE)
}

# One fake-provider run (an `r` call, then an answer) streamed to a JSONL file at `verbose`,
# with whatever the renderer prints captured and discarded
infra27_run = function(verbose) {
  local_gptr_options(verbose = verbose, quiet = TRUE, record = "off")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 1")),
                                 "The answer is 42."))
  s = peter("compute", model = fake, .run = FALSE, envir = new.env(parent = globalenv()),
           mode = auto)
  file = tempfile(fileext = ".jsonl")
  on.exit(unlink(file), add = TRUE)
  con = file(file, open = "wb")
  off = jsonl_sink(s, con)
  utils::capture.output(gptr_step(s, turns = Inf))
  off()
  close(con)
  readLines(file, encoding = "UTF-8", warn = FALSE)
}

test_that("the transcript is the same at verbosity 0, 1 and 2 (INFRA-27, acceptance 4)", {
  local_project()
  v0 = infra27_normalise(infra27_run(0L))
  v1 = infra27_normalise(infra27_run(1L))
  v2 = infra27_normalise(infra27_run(2L))
  expect_gt(length(v0), 10L)
  expect_identical(v1, v0)
  expect_identical(v2, v0)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-(jsonl|render)$")'
```

Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 72 ]` (UTF-8 locale): console-jsonl gives `FAIL 8 | PASS 0`, the errors reading `could not find function "jsonl_event"` (and `jsonl_value`, `jsonl_sink`, `jsonl_frontend_run`), the `.stdin` test erroring with P08's `gptr_error_invalid_argument` for `.opts$frontend` (validated against `registry_names("frontend")`, which has no `jsonl` yet) and the registration test's expectation failing; console-render gives `FAIL 1 | PASS 72`, the INFRA-27 test erroring with `could not find function "jsonl_sink"`.

- [ ] **Step 3: Write the implementation**

Create `R/console-jsonl.R`:

```r
# console-jsonl.R -- P14 Console and front ends (layer L5, area console).
# The `jsonl` front end (architecture 6.17, P-B graft; contract 7.14): one redacted JSON object
# per line for every catalogued event of a session, in the JSON form of contract 4.5 (the same
# field names, `ts` as ISO 8601 UTC, messages and blocks in their 4.1-4.2 JSON shapes, event names
# verbatim). Worker children (P19, contract 11.11) and agentic layers in other languages read it.
# The sink writes to a connection its caller owns and opens none (IC-59). Every line passes the
# `persist` redaction profile (tree, then text) on top of the `stream` profile that ev_dispatch()
# applied (contract 1.4). Rendering never reaches the sink, so the transcript does not depend on
# the verbosity (INFRA-27).

#' Stream events as JSON lines to `con`
#'
#' @param session A `gptr_session` (its events only, through session-scoped hooks that P02 drops
#'   at its `session_shutdown`), or `NULL` for the events of every session (process-level hooks).
#' @param con An open connection owned by the caller (`stdout()`, or a file opened with
#'   `open = "wb"`).
#' @return A zero-argument function that detaches the sink, invisibly.
#' @noRd
jsonl_sink = function(session, con) {
  check_class(session, "gptr_session", "session", null = TRUE)
  if (!inherits(con, "connection") || !isOpen(con)) {
    gptr_abort("`con` must be an open connection.", "invalid_argument", arg = "con",
               expected = "an open connection")
  }
  sid = if (is.null(session)) NULL else session_data(session)$id
  handler = function(event, ctx) {
    tryCatch(jsonl_write(con, event), error = function(e) NULL)
    NULL
  }
  ids = character()
  for (ev in jsonl_events()) {
    ids = c(ids, if (is.null(sid)) {
      hook_add(ev, handler, rank = 3L, source = "user")
    } else {
      hook_add(ev, handler, rank = 0L, source = "session", session = sid)
    })
  }
  invisible(function() {
    for (id in ids) hook_remove(id)
    invisible(NULL)
  })
}

#' The catalogued events the sink subscribes to (contract 10.4; channels are not included)
#' @noRd
jsonl_events = function() {
  unique(as.character(ev_catalogue()$event))
}

#' Write one event as one line of UTF-8 bytes, flushed so a reading parent sees it at once
#' @noRd
jsonl_write = function(con, event) {
  writeLines(jsonl_line(event), con, useBytes = TRUE)
  flush(con)
  invisible(NULL)
}

#' One event as redacted JSON text (chr(1))
#' @noRd
jsonl_line = function(event) {
  x = redact_tree(jsonl_event(event), profile = "persist")
  as_utf8(redact(json_encode(x), profile = "persist"))
}

#' The contract 4.5 JSON form of an event
#' @noRd
jsonl_event = function(event) {
  out = jsonl_value(event)
  if (is.numeric(event$ts) && length(event$ts) == 1L) out$ts = jsonl_ts(event$ts)
  if (jsonl_is_msg(event$message)) out$message = jsonl_msg(event$message)
  if (is.list(event$results) && length(event$results)) {
    out$results = lapply(event$results, function(m) {
      if (jsonl_is_msg(m)) jsonl_msg(m) else jsonl_value(m)
    })
  }
  if (jsonl_is_block(event$block)) out$block = jsonl_block(event$block)
  if (is.list(event$content) && length(event$content) &&
        all(vapply(event$content, jsonl_is_block, NA))) {
    out$content = lapply(event$content, jsonl_block)
  }
  out
}

#' Epoch seconds as ISO 8601 UTC with milliseconds, locale-independent (contract 1.2)
#' @noRd
jsonl_ts = function(ts) {
  ms = round(ts * 1000)
  paste0(format(.POSIXct(ms %/% 1000, tz = "UTC"), "%Y-%m-%dT%H:%M:%S", tz = "UTC"), ".",
         sprintf("%03d", as.integer(ms %% 1000)), "Z")
}

#' @noRd
jsonl_is_msg = function(x) {
  is.list(x) && is.character(x$role) && length(x$role) == 1L &&
    x$role %in% c("user", "assistant", "tool_result", "operator")
}

#' @noRd
jsonl_is_block = function(x) {
  is.list(x) && is.character(x$type) && length(x$type) == 1L &&
    x$type %in% c("text", "thinking", "image", "tool_call", "opaque", "context")
}

#' A message in its JSON shape through P01's one mapping table (contract 4.8)
#' @noRd
jsonl_msg = function(m) {
  tryCatch(msg_to_json(m), error = function(e) jsonl_value(m))
}

#' A content block in its JSON shape (contract 4.1)
#' @noRd
jsonl_block = function(b) {
  tryCatch(block_to_json(b), error = function(e) jsonl_value(b))
}

#' A JSON-able copy of a payload value: functions, environments, language objects, external
#' pointers and S4 objects are dropped; times become ISO strings; factors become strings; data
#' frames stay (json_encode() writes them as arrays of row objects)
#' @noRd
jsonl_value = function(x) {
  if (is.null(x)) return(NULL)
  if (is.function(x) || is.environment(x) || is.language(x) || typeof(x) == "externalptr" ||
        isS4(x)) {
    return(NULL)
  }
  if (inherits(x, "POSIXt")) return(jsonl_ts(as.numeric(x)))
  if (inherits(x, "Date")) return(format(x))
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) {
    cols = lapply(x, function(col) {
      if (inherits(col, "POSIXt")) return(jsonl_ts(as.numeric(col)))
      if (is.factor(col)) return(as.character(col))
      if (is.list(col) || !is.atomic(col)) return(NULL)
      as.vector(unclass(col))
    })
    cols = cols[!vapply(cols, is.null, NA)]
    return(as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE))
  }
  if (is.list(x)) {
    nms = names(x)
    out = lapply(unclass(x), jsonl_value)
    keep = !vapply(out, is.null, NA)
    out = out[keep]
    if (!is.null(nms) && !length(out)) return(json_obj())
    return(out)
  }
  if (is.atomic(x)) return(as.vector(unclass(x)))
  NULL
}

#' Read one prompt from a JSONL client line: `{"type":"prompt","text":...}` or plain text
#' @noRd
jsonl_prompt_text = function(line) {
  line = trimws(as_utf8(line))
  if (startsWith(line, "{")) {
    x = tryCatch(json_decode(line), error = function(e) NULL)
    if (is.list(x) && is.character(x$text) && length(x$text) == 1L) return(x$text)
  }
  line
}

#' The JSON line of a failed prompt (the `error` event shape of contract 4.5)
#' @noRd
jsonl_error_event = function(e, session = NULL) {
  ev_new("error", session = if (is.null(session)) NULL else session_data(session)$id,
         reason = "error", error = list(class = class(e)[[1L]], message = conditionMessage(e)))
}

#' run() of the `jsonl` frontend
#'
#' Without `stdin`: the events of `session` (with queued input or running) as JSON lines until it
#' settles. With `stdin` (`peter(.stdin = TRUE, .opts = list(frontend = "jsonl"))`): each line of
#' standard input is a prompt (plain text or `{"type":"prompt","text":...}`; `/exit` ends) sent
#' through the gateway like a console prompt; the events of every session go to `con` and nothing
#' else is printed (gptr.verbose is 0 for the duration).
#' @noRd
jsonl_frontend_run = function(session, ..., call = NULL, envir = NULL, stdin = NULL,
                              con = stdout()) {
  if (is.null(stdin)) stdin = !is.null(call) && isTRUE(call$args$stdin)
  if (!isTRUE(stdin)) {
    if (!inherits(session, "gptr_session")) {
      gptr_abort(c("The jsonl frontend streams the events of a session; pipe one in:",
                   paste0("s = peter(\"...\", .run = FALSE); ",
                          "s |> peter(.opts = list(frontend = \"jsonl\")) at a console."),
                   paste0("From a script, read prompts from standard input: ",
                          "peter(.stdin = TRUE, .opts = list(frontend = \"jsonl\")).")),
                 "invalid_argument", arg = "session", expected = "a gptr_session")
    }
    off = jsonl_sink(session, con)
    on.exit(off(), add = TRUE)
    gptr_wait(session)
    return(invisible(session))
  }
  old = options(gptr.verbose = 0L)
  on.exit(options(old), add = TRUE)
  if (is.null(envir) && !is.null(call)) envir = call$envir
  if (!is.environment(envir)) envir = globalenv()
  rs = repl_state(session, envir, stdin = TRUE, call = call)
  rs$render = FALSE
  .gptr_repl = rs
  rs$reader = console_reader(stdin = TRUE, echo = FALSE)
  on.exit(repl_close(rs), add = TRUE)
  off = jsonl_sink(NULL, con)
  on.exit(off(), add = TRUE)
  repeat {
    line = rs$reader$read("")
    if (is.na(line)) break
    text = jsonl_prompt_text(line)
    if (!nzchar(text)) next
    if (text %in% c("/exit", "/quit")) break
    res = console_send(rs, text)
    if (identical(res$status, "error")) {
      tryCatch(jsonl_write(con, jsonl_error_event(res$error, rs$session)),
               error = function(e) NULL)
    }
  }
  invisible(rs$session)
}

#' The `jsonl` built-in (contract 7.14, 10.3): the `jsonl` frontend
#' @noRd
builtin_jsonl = function(gptr) {
  gptr$register(gptr_spec("frontend", "jsonl", run = jsonl_frontend_run))
  invisible(NULL)
}

on_load(ext_declare_builtin("jsonl", builtin_jsonl))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "^console-jsonl$")'
Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 32 ]` for console-jsonl and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 75 ]` for console-render (UTF-8 locale; `LC_ALL=C` gives `SKIP 1 | PASS 71`).

- [ ] **Step 5: Commit**

```bash
git add R/console-jsonl.R tests/testthat/test-console-jsonl.R tests/testthat/test-console-render.R
git commit -m "feat(console): add the JSONL sink and the jsonl frontend"
```

---

## Plan acceptance

Every check of 05 P14, including its review amendments, with the task and test that prove it and the command with its expected result. All commands run from the repository root `/Users/wanjun/Desktop/gptr` after Task 8. The per-file commands are:

- `Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 75 ]` (UTF-8 locale; `LC_ALL=C` -> `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 71 ]`)
- `Rscript --vanilla -e 'devtools::test(filter = "^console-interrupt$")'` -> `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 36 ]` (INFRA-03 skipped off CI; `CI=true` on Linux or macOS -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]`)
- `Rscript --vanilla -e 'devtools::test(filter = "^console-repl$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 139 ]`
- `Rscript --vanilla -e 'devtools::test(filter = "^console-commands$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 58 ]`
- `Rscript --vanilla -e 'devtools::test(filter = "^console-jsonl$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 32 ]`

| # | Acceptance check (05, P14) | Proved by |
|---|---|---|
| 1 | `devtools::test(filter = "console")` is green (SIGINT tests skip on CRAN) | Tasks 1-8 Step 4. Command: `Rscript --vanilla -e 'devtools::test(filter = "console")'`. Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 401 ]` (P14's 340 expectations and the 61 of P11's `test-console-ui.R`, which the filter also selects; the skip is INFRA-03 off CI). `LC_ALL=C`: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 397 ]`. `CI=true` (Linux, macOS): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 417 ]`. The SIGINT test calls `skip_on_cran()` first, so `NOT_CRAN=false` reports it as `On CRAN`. |
| 2 | `peter(.stdin = TRUE)` with a scripted UI: a prompt, `!dim(x)` (added to the next prompt's context), `!!x` (not added), `/mode auto` (mode entry at the next turn), `"""` input, `/exit` returning the session invisibly | Task 7, `test-console-repl.R` "a scripted .stdin console session (acceptance 2)": two requests; request 2's last user text is `line one\nline two`, its `user_ran` block holds `> dim(x)` and `#> [1] 2 3` and not `> x`, it carries the `mode` block, the session has a `gptr.mode_change` entry and mode `auto`; the value is invisible and a `gptr_session` with 2 turns; the stdin connection is closed (IC-59). Supporting: Task 4 grammar tests, Task 5 "!code runs in the REPL environment and leaves a note; !!code does not", Task 6 "/mode on a session appends the mode change for the next turn". Command: the `console-repl` line. |
| 3 | The renderer gives identical output over 200 random chunkings (UTF-8 locale); a reply containing `{Sys.setenv(GPTR_PWNED = "1")}` is printed verbatim and nothing is evaluated | Task 1, "the output does not depend on chunking, plain and styled (acceptance 3)" (200 random chunkings, colours off and on) and "untrusted braces are printed verbatim and never evaluated (rule C1)"; Task 7, "a streamed reply is printed verbatim and never evaluated (acceptance 3, rule C1)" (a full `peter()` run at verbosity 2 through `builtin:console`; `GPTR_PWNED` stays unset). Command: the `console-render` line in a UTF-8 locale (chunk invariance also holds in the C locale). |
| 4 | INFRA-27: the same fake-provider run gives byte-identical JSONL transcripts at verbosity 0, 1 and 2 | Task 8, `test-console-render.R` (the INFRA-27 acceptance file of 03 section 6.18, run by P24's INFRA suite) "the transcript is the same at verbosity 0, 1 and 2 (INFRA-27, acceptance 4)": the three transcripts (more than 10 lines each, an `r` tool call and an answer) are identical after the volatile fields of 04 section 12.3 (`ts`, `session`, `run`, `request_id`) and the other clock and id fields are removed (ambiguity 15). Command: `Rscript --vanilla -e 'devtools::test(filter = "^console-render$")'` (the `console-render` line). |
| 5 | INFRA-03 (processx-driven `R --interactive`, CI only): SIGINT during TTFT then "continue" completes the request; mid-tool "steer" delivers after the tool result; "abort" closes the mock socket and the partial equals what was received | Task 7, `test-console-interrupt.R` "INFRA-03: real SIGINTs continue, steer and abort runs (acceptance 5)": status `idle` and the last token after `c`; the steer message follows the tool result in request 2; after `a` the last message has `stop_reason` `aborted`, its text is a proper prefix of the streamed tokens and the mock server logs the disconnect. Simulated-interrupt counterparts run everywhere: Task 3 "continue resumes the interrupted computation", "steer and follow-up queue the text with source pause_menu (IC-55)", "abort in mode call re-signals the interrupt so loops stop". Command: `CI=true Rscript --vanilla -e 'devtools::test(filter = "^console-interrupt$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]` (Linux, macOS). |
| 6 | The JSONL sink contains no registered secret (fake key) | Task 8, "no registered secret reaches the sink (acceptance 6)": a fake Anthropic-shaped key registered with `secret_register()` and echoed by the fake provider appears in no line, nor does its 24-character prefix. Command: the `console-jsonl` line. |
| 7a | `artifact_start` prints `artifact  <id>  ->  <url>   (running in background)` | Task 2, "artifact_start prints the NS-8 line (acceptance 7)" and "an artifact_start fired while a tool executes prints after tool_execution_end" (the line never lands in the model's `r` output, P23 ambiguity 14); Task 7, "artifact_start events print the NS-8 line through builtin:console (acceptance 7)" (the registered hook, through `ev_dispatch()`). Command: the `console-render` line. |
| 7b | An ESC sequence in a tool preview is escaped | Task 2, "tool lines escape the preview and summarise the result (acceptance 7)"; Task 7, "tool calls of a run show escaped previews and results (acceptance 7)" (a full run: the preview line shows `<U+001B>[31mred` and no output line contains ESC); Task 1, "control, bidi and zero-width characters are escaped (IC-53 item 8)". Command: the `console-render` line. |
| 7c | With `jupyter.in_kernel = TRUE` mocked, `peter()` with no prompt starts the console on a mocked `gptr_readline()` | Task 7, "in IRkernel peter() without a prompt starts the console on gptr_readline() (acc. 7)": the banner is printed, `/status` answers, `/exit` returns invisibly, every mocked line was read. Command: the `console-repl` line. |
| IC-69 | The renderer uses tool `render` functions and `renderer` records; `frontend` selectable by setting | Task 2, "a tool's render() function replaces the default lines (IC-69)" and "custom entries of a run are shown through renderer records (IC-69)"; Task 7, "the frontend comes from .opts$frontend or the setting frontend (IC-69)". |
| IC-71 | NS-8 line on `artifact_start` | rows 7a. |
| IC-53 | Approval displays are sanitised and list every flagged call | The console's approvals are P11's displays (`ui_permission_lines()`, proved by P11's `test-console-ui.R`, selected by the same `console` filter); the `.stdin` UI reuses them: Task 7, "the stdin UI answers selections and approvals from the reader" and "approvals of a .stdin session are answered from the same stdin". Everything P14 prints itself is escaped: Tasks 1, 2, 6 ("a command's text is printed escaped ..."). |
| IC-43 | The `console` route and the REPL use `gptr_can_prompt()` | Task 7, the IRkernel test (`gptr_is_interactive()` mocked `FALSE`, the route matches through `gptr_can_prompt()`); Task 3, "the policy is abort-only where resuming is unverified (RStudio, Rgui, Jupyter)". |
| IC-49, IC-55 | Pause-menu steer and follow-up enter the queue with `source = "pause_menu"` (P15 writes the `## Steer:`/`## Follow-up:` lines); direct R and slash commands reach the transcript | Task 3, "steer and follow-up queue the text with source pause_menu (IC-55)", "pause-menu text passes the input event with source steer", "a steer typed while a tool runs is queued once no tool is on the stack"; Task 5, "the input event (source passthrough) can handle or transform !code" and "!code is announced on the console:direct channel"; Task 6, "commands pass the input event (source repl): recorded, handled or transformed" (the `console:command` channel carries the command as it ran; handled lines and lines sent as prompts are not announced). These are the channels P15's `doc_on_console_command()` and `doc_on_console_direct()` record; P15's transcript lines are P15's acceptance. |
| IC-57 | Asks of background runs are shown at the next blocking call | Task 7, "background sessions that wait for approval are announced once (IC-57)"; the question itself is asked by P21 inside the next blocking pump (P21 acceptance). |
| IC-73 | `!expr` notes within 300 tokens | Task 5, "notes keep the newest within the token budget and cut one long note" (200 notes and one 200-line note stay within 300 tokens) and "console_send() makes an ordinary gateway call and continues the session" (the note reaches exactly the next prompt). |
| IC-59 | The `.stdin` connection closes on `/exit` and on exit | Task 4, "close() closes the stdin connection once (IC-59)"; Task 7, acceptance 2 (the connection count is back to its value before the call). |
| scope | Readline and persistent stdin, grammar, long-line warning, history | Task 4 (all tests), Task 7 (`gptr.history` off for piped input). |
| scope | Pause menu: second Ctrl-C aborts, menu on stderr, abort-only fallback, `[b]ackground` | Task 3, "a second Ctrl-C while the menu waits aborts", "the policy is abort-only where resuming is unverified (RStudio, Rgui, Jupyter)", "[b]ackground hands a foreground run to bg.register (P21) and resumes"; every menu test captures the menu on stderr and asserts stdout stays empty. |
| scope | Spinner ticked from the reactor; verbosity levels | Task 2, "the spinner runs as a reactor task from before_request to the first delta", "nothing is printed at verbosity 0 or for a background session", "verbosity 1 reports tool calls and the end as progress messages"; Task 7, "nothing is rendered at verbosity 0 (knitr, testthat)". |
| scope | Slash commands as `command` specs, templates as `/<name>` | Task 6 (every command; templates are `command` specs P17 registers, dispatched like the test's `/ask` and `/echo` commands; "a command named <plugin>:<cmd> wins over the /skill:<name> split (04 11.12)" for P17's Claude plugin commands). |
| scope | Banner, `!expr` passthrough, `@mentions`, prompts as gateway calls | Tasks 5 and 7. |
| rules | Lint rules and the layer table hold for P14's files | Command: `Rscript --vanilla -e 'devtools::test(filter = "^(lint-rules|arch-layers)$")'`. Expected: `FAIL 0`. |

Further commands:

1. `Rscript --vanilla -e 'devtools::test()'`
   Expected: a summary line with `FAIL 0 | WARN 0` (the whole suite).
2. `grep -c "The interactive console" man/peter.Rd`
   Expected: `1`.
3. The M3 exit check runs once P14-P17 are complete (05 milestone M3): `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`. Expected: 0 errors and 0 warnings.

## Manual check (interactive terminal R; not automated)

03 section 13 asks for a manual checklist of the pause menu. In a terminal `R --vanilla` session started in the repository:

```r
devtools::load_all()
x = matrix(1:6, 2)
fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "Sys.sleep(5); y = sum(x)")),
  "Done: y is 21.", "The second answer."))
s = peter(model = fake, mode = auto)
# In the console: type "compute y". While the tool sleeps press Ctrl-C: "[gptr] paused ..." and
# "[s]teer, [f]ollow-up, [c]ontinue, [a]bort" appear; answer s, then type "use base R only" at
# steer>. The answer streams once the tool returns. Then try !dim(x) and !!x, @x, /status,
# /mode plan, a """ block, Ctrl-C at the empty prompt (a hint), and /exit.
class(s)
y
```

Expected: `s` is the console's `gptr_session` and `y` is 21; in RStudio, Positron and Rgui the same Ctrl-C (Esc) aborts the run without a menu and the session is kept.

---

## Self-review

### Spec coverage (05 P14 scope and review amendments -> tasks)

- `console-repl.R`: `readline()` through `gptr_readline()` or one persistent `file("stdin")` under `.stdin = TRUE`, the input grammar of 03 section 6.17, the long-line warning, the optional `timestamp()` history -> Task 4; `!expr` passthrough, notes, `@mentions`, prompts as gateway calls -> Task 5; banner, the REPL loop, the "no prompt" route, the `console` frontend, `builtin:console` and the `?peter` section -> Task 7.
- `console-render.R`: the chunk-invariant markdown stream renderer and rule C1 -> Task 1; tool lines, the status line, the spinner ticked from the reactor, verbosity levels, tool `render` functions and `renderer` records, the NS-8 artifact line -> Task 2; the end-to-end checks -> Task 7.
- `console-interrupt.R`: the pause menu through the `resume` restart with steer, follow-up, continue, abort and background, the second Ctrl-C, the menu on stderr, the abort-only fallback -> Task 3; INFRA-03 with real SIGINTs -> Task 7.
- `console-commands.R`: the slash commands of 03 section 6.17 as `command` specs; templates as `/<name>` are P17's `command` specs, dispatched by the same code -> Task 6.
- `console-jsonl.R`: the `jsonl` frontend writing redacted, Pi-named events on a connection -> Task 8; the INFRA-27 acceptance test, in `test-console-render.R` as 03 section 6.18 names it -> Task 8.
- Review amendments: IC-69 and IC-71 -> Task 2 (and Task 7 for the frontend setting); IC-53 -> Tasks 1, 2, 6, 7 (P14 escapes everything it prints; approvals are P11's displays, reused by the stdin UI); IC-43 -> Tasks 3, 7; IC-49 and IC-55 -> Task 3 (P15 writes the transcript lines); IC-57 -> Task 7; IC-73 -> Task 5; IC-59 -> Tasks 4, 7.
- Every acceptance check of 05 P14 is mapped in "Plan acceptance" above.

### Placeholder scan

The plan was searched for "TBD", "TODO", "implement later", "fill in", "similar to Task", "handle edge cases" and "add appropriate": none occurs. Every step that changes code shows the complete code; the test steps show complete test files or complete appended blocks.

### Type and name consistency with 04

- 04 section 7.14 signatures, exactly: `builtin_console(gptr)`, `console_run(s, envir, stdin = FALSE)`, `with_interrupt_policy(expr_fun, runs, mode = c("call", "repl"))`, `render_markdown_stream(width = cli::console_width())`, `builtin_jsonl(gptr)`, `jsonl_sink(session, con)`. The service `console.interrupt_policy` is set with `ext_service_set("console.interrupt_policy", with_interrupt_policy, provided_by = "P14", builtin = "console")` (04 section 7.0, IC-34).
- Registry records: route `console` with `order = 30`, `match(call)`, `run(call)`; frontends `console` and `jsonl` with `run(session, ...)`; `command` specs through `gptr_command(name, handler, description = NULL, complete = NULL)`; hooks through `gptr_hook(event, handler, matcher = NULL)` on the events of 04 section 10.4; context blocks through `gptr_context_block()` with the 04 section 6.8 arguments; a `ui` spec with the six members of kind 22.
- Events and channels: `input` with `source` `"passthrough"`, `"repl"` (slash-command lines) and `"steer"` (transform chain, `list(action, text)`); `session_shutdown` with `reason = "exit"`; the notify channels `console:command` (`data = list(text)`) and `console:direct` (`data = list(code, output, status, noted)`), to which P15's `doc_on_console_command()` and `doc_on_console_direct()` subscribe (a channel name contains `:`). Queue source `"pause_menu"` (IC-55). Services consumed: `console.interrupt_policy` (own), `eval.r` (P09, `!code`), `bg.register` (P21), `compact.run` (P07), `doc.site` (P15), `skill.body` (P17).
- Conditions: `gptr_warning_readline_limit`, `gptr_message_progress`, `gptr_error_invalid_argument` (`arg`, `expected`); `gptr_error_not_available` is P08's when no console is loaded. Options read: `gptr.verbose` (through `verbosity()`), `gptr.max_turns_console`, `gptr.history`, `gptr.interpolate`; the `frontend` setting through `setting_get()`.
- P14 defines no function another plan defines (the 146 function names of the five files were checked against every other plan) and no test helper that shadows one; private helpers carry the prefixes `console_`, `render_`, `policy_`, `repl_`, `command_`, `cmd_`, `jsonl_`, plus `attr_escape()`, `readline_limit()` and `r_incomplete()`.

### Contract ambiguities and deviations (recorded, with the reading chosen)

1. **Which exports L5 may call.** 03 section 2.2 lets L5 call "SDK verbs"; P01's `arch_edge_ok()` lets L5 call L0, L5, the kernel SDK of IC-33 and `gptr-sdk.R` only. Exports that live in L3, L4 or L6 files (`peter()`, `gptr_last()`, `gptr_usage()`, `gptr_sessions()`, `gptr_resume()`, `gptr_fork()`, `gptr_permissions()`) are called as `gptr::<name>()`, as a user calls them; `codetools::findGlobals()` reports such a call as `::`, so the layer test sees no edge (verified). Exports of later plans (`gptr_doc()`, `gptr_rewind()`, `gptr_skills()`, `gptr_mcp()`) are reached through P01's `ns_fun()` with a "not available" answer.
2. **The banner's workspace lines.** 04 section 7.9 names P14 as a consumer of `workspace_lines(snapshot, budget = 600L)`, which lives in an L4 service file that L5 may not call and needs a snapshot. The banner describes up to six objects with the kernel SDK's `describe_binding()` (never forcing promises) and points to `/env`.
3. **`input` source `repl`.** 04 section 10.4 lists `prompt`, `pipe`, `repl`, `passthrough` and `steer`. A console prompt is an ordinary gateway call, so P08 already emits its `input` event (source `prompt` or `pipe`); a second event for the same prompt would run transform hooks twice and make P11's plan hand-off count one console prompt as two calls. P14 emits `repl` for slash-command lines only, `passthrough` for `!code` and `steer` for pause-menu text. Transcripts are not written from the `input` event (it fires before a direct line runs, and a later hook may still handle or transform a command): P15's `doc_on_console_command()` records slash commands from the `console:command` channel and `doc_on_console_direct()` records direct R from the `console:direct` channel (ambiguity 4).
4. **Transcript events.** IC-49 and 04 section 11.5 have P15 record console prompts (they are gateway calls), direct R lines "with `#>` output" and slash commands as comments, but name no event for the last two. P15's plan (its ambiguity 11) subscribes `doc_on_console_command()` to the notify channel `console:command` and `doc_on_console_direct()` to `console:direct`, so P14 dispatches exactly those: `console:command` (`data = list(text)`) for a slash command line that passed the `input` event (source `repl`) unhandled and is still a command after any transform, and `console:direct` (`data = list(code, output, status, noted)`) after a direct R line ran. The `input` events with sources `repl` and `passthrough` are still emitted first (04 section 10.4), so hooks can handle or transform the line; they are not the transcript's source.
5. **`session_shutdown` at `/exit`.** P14 emits it only for a session the console created; a session piped in with `s |> peter()` stays the caller's, and P02 would drop its session-scoped hooks at `session_shutdown`.
6. **Steering while a tool runs.** P06's `session_enqueue()` refuses an enqueue from the session's own `r` tool frames, which are on the stack when the interrupt arrives during a tool. The pause menu then queues the text from a reactor timer as soon as `run_current()` is `NULL`, which is still before the next request (INFRA-12); the INFRA-03 test checks the order.
7. **From a run to its session.** The policy receives runs (P14 also accepts sessions), and 04 gives no accessor from a `gptr_run` to its session. P14 records run id -> session at `agent_start` (`the$console$active`, a new field of P01's `the`, created lazily by `console_state()`); a run without a record can be continued or aborted but not steered.
8. **Answers in a `.stdin` console.** 04 does not say who answers approvals in a piped console. When the options are unset, P14 sets `gptr.interactive = TRUE` and `gptr.ui` to a stdin UI spec (named `console_stdin`, not registered) for the duration of the REPL and restores both; P11's scripted UI and an explicit `gptr.ui` win.
9. **Tool `render` arguments.** IC-69 fixes `render = function(call, result, width)` without defining `call` and `result`. P14 passes `call = list(id, name, input)`, and `result = NULL` at `tool_execution_start` and the tool-result message plus `elapsed` at its `message_end`. P02's `gptr_tool()` has no `render` argument, so the test builds the record with `gptr_spec("tool", ..., render =)`.
10. **`jsonl_sink(NULL, con)`.** The `.stdin` form of the `jsonl` frontend creates its session at the first prompt, so `jsonl_sink()` also accepts `session = NULL` (process-level hooks for every session). `jsonl_sink()` returns a detach function (04 names no return value).
11. **`/permissions`.** 03 section 6.17 lists the command without arguments; P14 shows the rules and changes rules of this R session (`allow|ask|deny|remove <rule>`); project and user rules stay with `gptr_permissions()`.
12. **Context blocks of the console.** 04 names no blocks for `!expr` notes and `@file` mentions. P14 registers `user_ran` (budget 300 as IC-73 requires, order 550) and `user_files` (budget 2000, order 560), placement `both`, authority `data`. They answer only the call `console_send()` built: the gateway record's `sys_call` is that call object (verified with a `sys.call()` identity test).
13. **Where the menu appears.** 03 section 6.2 names Rgui and IDE consoles as abort-only. P14 shows the menu when `gptr_can_prompt()` holds and `front_end()` is `terminal`, `vscode` (terminal R) or `unknown`; RStudio, Positron, Rgui (also R.app), Jupyter, knitr and Quarto abort.
14. **INFRA-03's dependencies.** 05 makes the test CI-only; its child also uses P12's `anthropic-messages` adapter through P01's mock provider (in the package by M3) and real SIGINTs from processx, so the test skips unless `CI=true`, on CRAN and on Windows.
15. **"Byte-identical" transcripts (INFRA-27).** Timestamps, generated ids and clocks differ between two runs. The test removes the volatile fields of 04 section 12.3 (`ts`, `session`, `run`, `request_id`) and the other clock and id fields (`timestamp`, `elapsed`, `started`, `seconds`, `view`, `response_id` and their camel-case JSON names) and masks id patterns; everything else must be byte-identical.
16. **`console_run()` without a prompt.** 04 says it returns `s` invisibly on `/exit`; with `s = NULL` and no prompt sent there is no session, and it returns `NULL` invisibly.
17. **`[b]ackground`.** Offered in mode `"call"` when the `bg.register` service exists and the run is not already background. After it the menu resumes; whether the blocked foreground call then returns at once is P06's and P08's behaviour (P21's ambiguity A17).
18. **P11's private helpers.** The stdin UI uses `console-ui.R` helpers that are not contract entries (`ui_permission_lines()`, `ui_permission_detail()`, `ui_parse_choice()`, `ui_questions_via()`, `ui_can_remember()`, `ui_escape()`); same area and layer, so allowed, but a rename in P11 must follow here.
19. **`cli_verbatim()` (05 scope).** 05 names `cli_verbatim()` for untrusted text; P14 escapes untrusted text and writes it with `cat()` or P01's `msg_verbatim()`, which interpolate nothing either and keep the console output on stdout and notices on stderr (rule C1 forbids untrusted text as a format string; 04 section 7.14 says the same).
20. **Whether `envir =` was given.** IC-40 lets an explicit `envir` win over a session's kept home, but the `gptr_call` record of 04 section 7.8 has no binding for it; P14 reads `call$args$envir_given`, which P08's capture sets.
21. **Slash commands and the pending plan.** P11's `plan_on_input()` counts only `input` events of source `prompt` or `pipe` as a `peter()` call (IC-56; P11's cross-plan consolidation, its log row 2), so a slash command sent as `repl` between a plan and the next prompt (for example `/mode auto`) does not discard the pending plan; a console prompt still counts once, through P08's gateway event. 04 section 10.4 lists `repl` among the sources P14 emits (transcripts are written from the `console:command` channel, ambiguity 4).
22. **INFRA-03 starts `R`, not `rscript_path()`.** Conventions section 7 asks for `rscript_path()`; an interactive console needs `R --interactive` (report 18 Appendix A.8), started by its absolute path `file.path(R.home("bin"), "R")`, so R CMD check's dummy `R` on `PATH` is never used (the reason for the IC-60 rule); the child's environment is complete (no `NA`, IC-60) and drops `RSTUDIO`, `POSITRON`, `TERM_PROGRAM`, `JPY_SESSION_NAME` and the Quarto variables so `front_end()` is `terminal`.
23. **Printed output is compared with `expect_identical()`.** Conventions section 7 names `expect_snapshot()` inside `local_reproducible_output(width = 80)`; P14 keeps the reproducible output and compares the captured lines exactly, so no `_snaps/` files (which no plan owns and which fail on CI when absent) are needed.
24. **Other questions in a `.stdin` console.** The stdin UI answers what goes through the `ui` kind (approvals, `ask`). Questions that P08 and P15 ask through `gptr_confirm()` (project trust, the egress acknowledgement, transcript consent) read `readline()`, which under Rscript returns `""` at once, so they take their defaults; a piped session acknowledges egress and trust beforehand (`gptr_init()`, settings).
25. **The `console` route inside a run.** 04 section 6.1.1 gives the route's match as "no prompt (`gptr_can_prompt()` or `.stdin`)". P14 also requires `run_current()` to be `NULL`: a `peter()` without a prompt evaluated by model code (a continuation, which the `nested` route does not take) would otherwise open a REPL inside the tool that reads the user's input or the rest of a piped stdin and sets `gptr.ui`/`gptr.interactive` (IC-53 item 3 counts `options()` with `gptr.*` names as `control`).
26. **The console call's arguments on a piped session.** 04 section 6.1 says a continuation "may only keep or change" the mode explicitly; `s |> peter(mode = auto)` opening the console therefore passes the console call's model, mode, tools, plugins, extensions, skills and context objects with the first prompt (`rs$pending_call`), exactly as `s |> peter("...", mode = auto)` would.

### Validation executed while writing this plan

- A scratch package was assembled from the five R files of this plan (exactly the code blocks, except that calls written `gptr::<name>()` were plain calls there) and stand-ins for the functions of P01-P11 they call (registry, events, services, reactor, session data and queue, `eval_r()`, the P11 UI helpers). Every test that does not need the real gateway was run from this plan's test blocks: 217 expectations passed in `en_US.UTF-8` with no failure, and 213 passed with 1 skip (the width test) in the C locale. The tests that need `peter()` (P06-P10) were parse-checked and their counts taken statically; the Step 2 and Step 4 summaries add those counts to the measured ones.
- `lintr` with the repository's settings (`=` and `<<-` only, 100 characters): no lints in the five R files; no line over 100 characters in any code block; every code block is ASCII.
- A layering check: all 152 external call edges of the 146 P14 functions (`codetools::findGlobals()`) were mapped to the files the other plans define them in and checked with P01's `arch_edge_ok()` rules and kernel SDK list: no violation and no unmapped callee.
- roxygen2 7.3.3 merged the `@section The interactive console:` block (`@name peter`, `@rdname peter`, `NULL`) into the `peter` page of a scratch package.
- A probe showed that `identical(sys.call(), cl)` holds inside a function reached by `eval(cl, envir)`, the identity the context blocks rely on.
- Every fenced `r` block of this plan was extracted and parsed with `parse(file =)`; the plan contains no left-arrow assignment and no magrittr pipe in code.


---

## Plan review log

Adversarial review of 2026-10-01 against `00-conventions.md`, 03 (sections 2.2, 3.4, 6.2, 6.17, 10.1), 04 (sections 6.1, 7.0, 7.6, 7.8, 7.14, 10.2-10.7, 11.12, 12; IC-33, IC-40, IC-43, IC-53, IC-55, IC-56, IC-57, IC-59, IC-60, IC-69, IC-73), 05 P14, report 18's verification log and the plans already written (P01, P02, P04, P06, P08, P09, P10, P11, P15, P16, P17, P19, P21). Every fix below was applied in place; the counts of Tasks 5-8, the acceptance table and the self-review were updated with them.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 8 test "a run gives a JSON line per event, in order" | It asserted that the first JSONL line is `agent_start`. P06's `run_start()` (P06 plan, `run_initial_input()` -> `run_take()` -> `queue_update`, then `run_freeze()` -> `session_start`, then `agent_start`) emits `queue_update` and `session_start` first for a `.run = FALSE` session, so the test could not pass. | applied | The test now checks that `queue_update`, `session_start` and `agent_start` occur, `session_start` before `agent_start`, `agent_start` before the first `message_update`, and `agent_end` last (4 expectations instead of 2; `console-jsonl` 33 -> 35). |
| 2 | major | Task 6 `console_command()`; Global Constraints "Events emitted"; ambiguities 3-4 | Slash commands were announced on a private channel `console:command`, but P15's written plan records console commands from the `input` event with `source = "repl"` (`doc_on_input()`), the source 04 section 10.4 lists with P14 as an emitter; 03 section 6.17 requires "Commands are recorded as comments in transcripts", which would silently not happen. | applied | Each command line now passes `ev_dispatch("input", ev_new("input", text, source = "repl"))` first, honouring the transform chain (`handled` stops, `transform` re-dispatches or sends the text as a prompt); `console:command` is gone, `console:direct` stays (P15 ambiguity 11 asks for a post-evaluation hook). New test "commands pass the input event (source repl): recorded, handled or transformed". Ambiguities 3, 4 rewritten; new ambiguity 21 records that P11's `plan_on_input()` then counts a slash command as a call (the fail-safe direction of IC-56). Superseded in part by the cross-plan consolidation log, items 1-2: P15 later replaced `doc_on_input()` with `doc_on_console_command()`, so `console:command` is dispatched again after the `input` event. |
| 3 | major | Task 6 `command_parse()`/`console_command()` | `/<plugin>:<cmd>` commands (04 section 11.12; P17 registers Claude plugin commands under that name) could never be dispatched: the parser always split at `:` and looked up only the part before it. | applied | `command_parse()` returns `list(name, args, full, rest)`; the whole token is looked up first (with `rest` as arguments), then the `/skill:<name>` split. Test "a command named <plugin>:<cmd> wins over the /skill:<name> split (04 11.12)"; the `command_parse()` test checks the new fields; unknown-command notices name the whole token. |
| 4 | major | Task 5 `repl_passthrough()` | `!code` called `eval_r()` directly, but 04 section 7.0 names "P14 `!expr`" as a consumer of the `eval.r` service ("`eval_r()` through the `evaluator` kind", IC-69), so an evaluator selected by the `evaluator` setting (S-11) was bypassed. | applied | `!code` evaluates through `ext_service_get("eval.r")` when the service exists (owned by `builtin:workspace`), else `eval_r()`; Interfaces and prose updated; new test "!code runs through the eval.r service (the evaluator kind, IC-69)". |
| 5 | minor | Tasks 4-5 `repl_state()`/`console_call()` | The console call's model, mode, tools, plugins, extensions, skills and context objects were used only when no session existed, so `s \|> peter(mode = auto)` (console on a piped session) silently ignored them. | applied | New state field `pending_call`; the first prompt of a new or piped-in session carries them (as `s \|> peter("...", mode = auto)` would). Test "the console call's arguments reach the first prompt, also on a piped session"; ambiguity 26. |
| 6 | minor | Task 6 `cmd_clear()`, `cmd_model()`, `cmd_mode()` | `/clear` replaced the model with the old session's model string; a model given as a spec (the fake provider, any `model = <spec>`) is registered for that session only, so the next prompt could not resolve it. | applied | `/clear` keeps `rs$model %||% s$model`; `/model` and `/mode` on a session also record the choice in the REPL state. |
| 7 | minor | Task 6 `cmd_fork()`, `cmd_resume()` | With an explicit console `envir`, `repl_eval_env()` kept returning that environment after `/fork`, so the fork's prompts and `!code` wrote into the original environment instead of the fork's overlay (IC-40). | applied | Both commands reset `rs$envir_given` so the new session's kept home decides. |
| 8 | minor | Task 6 `cmd_compact()` | It printed "Conversation compacted." even after an abort from the pause menu (mode `"repl"` returns `NULL`). | applied | The handler reports "Compaction was interrupted." when the policy returned `NULL`. |
| 9 | minor | Task 7 `console_route_match()` | The route matched a no-prompt call made by model code inside a run (a continuation, which the `nested` route does not take): a REPL inside a tool would read the user's input or the rest of piped stdin and set `gptr.ui`/`gptr.interactive` (IC-53 item 3). | applied | The match also requires `is.null(run_current())`; test "the console route never matches inside a run (model code cannot open a REPL)"; ambiguity 25. |
| 10 | minor | Task 7 INFRA-03 test | The child inherited `RSTUDIO`, `POSITRON` or `TERM_PROGRAM` from the parent, which makes `front_end()` report an IDE (abort-only: no menu) when the suite runs from an IDE; the use of `R` instead of `rscript_path()` was not justified. | applied | The child gets a complete environment (no `NA`, IC-60) without the IDE and Quarto variables; a comment and ambiguity 22 justify `file.path(R.home("bin"), "R") --interactive`. |
| 11 | minor | Task 7 `console_stdin_ui()` `input()` | The default value (from the model's `ask` questions) was written into the prompt unescaped (IC-53 item 8). | applied | The whole shown prompt is escaped, as P11's `ui_console_input()` does. |
| 12 | minor | Task 7 prose, `repl_error()` title, test name | "printed in one line" did not match the code, which keeps line feeds of multi-line messages. | applied | Wording changed to "printed escaped on stderr" (the code was already safe: other controls are shown as `<U+XXXX>`). |
| 13 | minor | Task 8 `jsonl_frontend_run()` error and prose; Task 8 Step 2 | The error suggested `s \|> peter(.opts = list(frontend = "jsonl"))`, which fails non-interactively (P08 raises `gptr_error_noninteractive` for a no-prompt call without a human or `.stdin`); Step 2 named the wrong red-phase error for the `.stdin` test (P08 validates `.opts$frontend` before routing). | applied | The message also names `peter(.stdin = TRUE, .opts = list(frontend = "jsonl"))` for scripts; prose explains the 6.1.1 step 4 rule; Step 2 names P08's `gptr_error_invalid_argument`. |
| 14 | minor | Self-review | Deviations from conventions section 7 (`expect_snapshot()`) and the `.stdin` behaviour of questions asked through `gptr_confirm()` were not recorded. | applied | Ambiguities 23 and 24. |
| 15 | major (claimed) | Task 7 `repl_main()` `session_shutdown` at `/exit` | Emitting `session_shutdown` drops the session's rank-0 records (P02) although `/exit` returns the session for further use. | rejected | 03 section 10.1 (NS-1 walkthrough, step 9) specifies "`/exit` fires `session_shutdown`, releases the store's lock ... and returns the session invisibly", and 04 section 10.4 lists P14 with reason `exit`; the plan already limits it to sessions the console created (ambiguity 5). |
| 16 | major (claimed) | File Structure | No `test-copy-console.R` although P14 touches user frames. | rejected | 03 section 3.4 lists the copy suites and their owners (P08, P09, P10, P13, P16, P19, P22, P23) and 05 P14's "Owns" names none; adding one would create an unowned file. The console's frame handling is covered by `test-copy-gateway.R` (prompts are gateway calls) and Task 5's mask-release checks. |
| 17 | minor (claimed) | Tasks 1-2, 6 | Untrusted text is written with `cat()` after escaping, not `cli::cli_verbatim()` as conventions section 5 and 04 section 1.5 say. | rejected | Already ambiguity 19: `cli_verbatim()` goes to stderr in non-interactive sessions (cli's output connection) and cannot stream partial lines; escaped `cat()` never interprets the text, which is what rule C1 and 04 section 7.14 require. |
| 18 | minor (claimed) | Task 2 | `the$console` is not a field of 04 section 7.0's `the` table. | rejected | Kept as ambiguity 7: a `gptr_run` carries only its session id (04 section 7.6) and `live_all()` is not in the IC-33 kernel SDK, so the console maps run ids to sessions at `agent_start` in its own lazily created field. |
| 19 | minor (claimed) | Task 8 | INFRA-27 could differ across the three runs through the token estimator's calibration. | rejected | P06 keeps the estimator state per session (`.d$estimator`), and each run is a new session; the remaining clocks and ids are removed by the test (ambiguity 15). |
| 20 | minor (claimed) | Task 8 `jsonl_value()` | Length-1 vectors serialise as scalars (the jsonlite shape trap). | rejected | 04 section 4.5 fixes no per-field array shape for event payloads; messages and blocks, whose shapes 04 fixes, go through P01's `msg_to_json()`/`block_to_json()`. |

Validation of this review (scratch directory `scratchpad/work/plans/review-P14/`):

- Every fenced `r` block (19) was re-extracted and parsed with `parse(file =)`; `getParseData()` finds no `LEFT_ASSIGN` token and no `%>%`; every block is ASCII and no line exceeds 100 characters.
- Three scratch packages built from the plan's code blocks with stand-ins for P01-P11 ran the self-contained tests: Task 1's renderer tests (34 expectations in `en_US.UTF-8`, 30 + 1 skip in the C locale), Task 3's interrupt-policy tests (36), Task 4's input-layer tests and the pure helpers of Tasks 5, 6 and 8 (`console_notes_text()`, `command_parse()`, `jsonl_value()`).
- A fourth scratch package ran the revised Task 6 code with a stand-in registry and the P02 transform-chain semantics: `command_parse()`, `<plugin>:<cmd>` lookup, unknown and failing commands, escaped output and `list(prompt =)`, the `input` event (`repl`: recorded, handled, transformed), `/help`, `/exit`/`/quit`/`/q`, `/model`/`/mode`/`/plan` before the first prompt: 29 expectations, no failure. A script checked the revised `console_call()` (the first prompt on a piped session carries `mode = "auto"`, the second does not) and that `repl_passthrough()` evaluates through a replaced `eval.r` service with `plots`, `tee` and `guard`.
- The 173 top-level function names of the plan's code blocks were compared with every other plan in `dev/plan/`: no collision; every external callee resolves to a definition in P01-P11 (or to a base, utils, stats, cli, testthat, withr or processx function).

---

## Cross-plan consolidation log

Cross-plan consistency pass of 2026-10-01 (lenses: interfaces, shared names, obligations, trace), checked against 04 (sections 7.6, 7.14, 10.4, 11.5; IC-49, IC-71), 03 (sections 2.2, 6.17, 6.18 row 27), 05 P14 and the current texts of P15 (Task 13 hooks, ambiguity 11, review row 3), P23 (Task 10, ambiguity 14, review rows 2 and 13), P09 and P24 (`infra-time.R`).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | minor | Global Constraints "Events emitted" and "Transcripts"; Task 6 prose; acceptance row IC-49/IC-55; ambiguity 4 | applied (corrected) | The stale `doc_on_input()` mentions are gone. The issue's replacement names (`doc_on_console_input()`, slash commands "through `input` with source `repl`") do not match P15 either: P15 defines `doc_on_console_command()` on the channel `console:command` and `doc_on_console_direct()` on `console:direct` (P15 L6948-6949). The plan now names those two handlers and channels everywhere (applied together with item 2). |
| 2 | shared-names | major | Task 6 `console_command()` and its test; Global Constraints; Task 6 Interfaces and prose; acceptance row IC-49/IC-55; ambiguities 3, 4, 21; self-review "Events and channels" | applied | No plan recorded slash commands: P15 listens only on `console:command`, which P14 had dropped. `console_command()` now dispatches `ev_dispatch("console:command", list(data = list(text = text)), session = session)` once the line has passed the `input` event (source `repl`, still emitted as 04 section 10.4 lists) and is still a command, so a handled line returns before it, a transformed command is recorded as it ran, and a line transformed into a prompt is not recorded twice (P15 records the prompt as a gateway call). The test "commands pass the input event (source repl): recorded, handled or transformed" registers a `console:command` hook and checks `c("/mode auto", "/mode plan", "/model opus")` (with `/swallow` handled and `/p` sent as the prompt `summarise x` left out); 4 more expectations, console-commands 54 -> 58. Review-log row 2 is annotated as superseded in part. |
| 3 | obligations | minor | Task 2 `console_on_artifact_start()` | applied | 04 section 7.14 only requires the hook to print the NS-8 line, so when it is printed is open. While a tool executes (`run_current()` non-NULL, 04 section 7.6) the line is now queued in `console_state()$artifacts`. `console_on_tool_end()` prints it through the new `console_artifact_flush()`/`console_artifact_emit()` once no tool executes on the stack: a nested `peter$<tool>()` end inside the `r` code keeps it queued. `console_on_agent_end()` flushes on exit after an interrupted tool. Outside a tool the line prints at once, as before. The line therefore never reaches P09's evaluator capture or the model's `r` output. P23's NS-8 test still passes: it re-dispatches the payload after the run, and the `r` result shows the line through the handle's own print. New Task 2 test "an artifact_start fired while a tool executes prints after tool_execution_end" (4 expectations; Task 2 red `FAIL 14`, green 62 / C locale 58; Task 7 green 247 / 243, at least 186 in red). The two new function names collide with no other plan. |
| 4 | trace | minor | Task 8 INFRA-27 test; acceptance row 4; File Structure | applied | 03 section 6.18 row 27 names `test-console-render.R`, and P24's `infra-time.R` runs `console-render`. Task 8 now appends the INFRA-27 test to `test-console-render.R` with its own file-local helpers (`infra27_volatile`, `infra27_norm_value()`, `infra27_normalise()`, `infra27_run()`), because 05 gives P14 no helper file. It removes the test and the now unused normalisation helpers from `test-console-jsonl.R`, where `jsonl_run()` stays for two tests. Task 8 Step 2 runs `^console-(jsonl\|render)$` (`FAIL 9 \| PASS 72`), Step 4 runs both files (32 and 75), and Step 5 adds `test-console-render.R`. Acceptance row 4 points at the `console-render` command. Per-file lines: console-render 68 -> 75 (C locale 64 -> 71), console-jsonl 35 -> 32. |

Totals after this pass: P14 has 340 expectations (console-render 75, console-interrupt 36, console-repl 139, console-commands 58, console-jsonl 32). Acceptance row 1 is `PASS 401` (C locale 397, `CI=true` 417).

Validation (scratch `scratchpad/work/consolidate/`):
- All 20 fenced `r` blocks were re-extracted and parsed with `parse(file =)`. `getParseData()` finds no `<-` token (only `<<-`) and no `%>%`. Every block is ASCII, with no line over 100 characters.
- The expectation counts come from the parse data: Task 2 tests 24 -> 28, Task 6 tests 52 -> 56 (+2 for the `/exit` loop), console-jsonl 35 -> 32, and the INFRA-27 block 3.
- A stand-in script ran the revised artifact handlers. A line raised inside a tool is queued, a nested tool end keeps it, the outer tool end prints it once and empties the queue, and outside a tool it prints at once (as a progress message at verbosity 1).
