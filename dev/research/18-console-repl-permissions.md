# 18 — Interactive console REPL, permission modes, ask-user

Track 18 of the gptr research programme. Requirements covered: REQ-16 (interactive `gptr()`), REQ-36
(ask-user), REQ-37 (permission modes), REQ-38 (interrupt / abort / steer), plus the console-facing parts
of REQ-03 (front ends) and REQ-25 (non-interactive scripts). Decisions touched: D-11 (permission modes),
D-26 (console UX), D-03 (`ask` tool), D-05 (result printing).

- Date: 2026-09-29. R 4.4.3 on macOS (arm64), cli 3.6.6, rlang 1.1.7, ellmer 0.4.0, processx 3.8.6, curl 7.0.0.
- Pi reference clone: commit `1b347794e2a630e4359f2584f4eea388145d0ddf` (2026-09-29).
- Scratch directory with every prototype, driver and captured output:
  `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/18/`
  (called `$W` below). Appendix A of this file reproduces the core prototype sources and their outputs.
- A previous researcher left six small unverified scripts in `$W` (`a1_stdin.R`, `a1b_stdin.R`,
  `a1c_stdin.R`, `a2_pty_driver.R`, `a2_tty.R`, `a3_parse_quirks.R`) and no draft report. All six were
  re-run; their findings are included below as VERIFIED with the observed output.
- Related reports read and not repeated here: `02-pi-agent-loop-sessions.md` (sections 4.7, 4.8, 5.6–5.8:
  interrupt `resume` restart, steering queues, file-inbox and httpuv side channels, transport constraints)
  and `05-pi-extensibility.md` (sections 4.6 and 5.6: first-pass permission gate and a first-pass code
  classifier). This track supersedes the classifier of report 05 (101 test cases instead of 15, see 2.5).

Evidence labels: **VERIFIED** = I saw the evidence myself (source lines, a web page, or an executed
command with observed output). **LIKELY** = strong indirect evidence. **UNCERTAIN** = not verified.

---

## 1. Executive summary

1. **`readline()` is the only portable line reader for the interactive REPL, and it has sharp edges.**
   It strips leading and trailing blanks, truncates the prompt at 256 characters, returns `""` for
   Ctrl-D, and does not add what the user typed to the console history. **Long lines are R-version
   dependent**: on R 4.4.3 (Unix, GNU readline) a console line of 4,095 bytes or more is cut to at most its
   first 4,096 bytes, the rest is silently dropped, and because no newline was delivered `readline()` keeps
   reading and **glues the next input line onto it** (observed: a 6,000-character line followed by
   `second` came back as one 4,102-character string ending in `...abcdefsecond`; the next `readline()`
   returned `third`). R >= 4.5.0 keeps the remainder of long readline lines (source only, not run here),
   leaving `do_readln`'s own 8,190-byte cap. VERIFIED on R 4.4.3 (R source `src/main/scan.c` `do_readln`,
   `src/unix/sys-std.c` `readline_handler`, `$W/a10_long_driver.R`, re-run with a tail probe;
   `$W/a8_ctrld_driver.R`, `$W/a5_history_driver.R`).
2. **Up-arrow history for gptr prompts is possible with `utils::timestamp(stamp = x, prefix = "",
   suffix = "", quiet = TRUE)`**, which inserts an entry into the console history that the next
   `readline()` recalls. VERIFIED in terminal R on macOS; RStudio/Positron behaviour UNCERTAIN.
3. **Non-interactive reading must use one persistent `file("stdin")` connection.** Under `Rscript`,
   `readline()` returns `""` immediately (after printing the prompt plus a newline), `stdin()` is the
   *script file itself*, and a fresh `file("stdin")` per call loses everything after the first line
   because the first connection buffered it. VERIFIED (`$W/a1*_stdin.R`).
4. **Pasted multi-line text arrives as separate `readline()` calls, and text typed while the agent is busy
   is delivered to the next `readline()`.** So multi-line prompts need an explicit convention (`"""` blocks,
   trailing `\`, fenced ```` ```r ```` blocks, `/edit`), and type-ahead naturally becomes the next prompt.
   VERIFIED in a pty (`$W/e3_pty_driver.R`).
5. **Front-end capabilities differ and `cli` already encodes them.** RStudio console: colours yes (from
   `RSTUDIO_CONSOLE_COLOR`), `\r` updates yes, ANSI cursor movement no. Positron sets
   `cli.default_num_colors = 256`, `cli.dynamic = TRUE`, `cli.hyperlink = TRUE` at startup. RGui: no colours,
   Esc interrupts, output buffered (needs `flush.console()`). Windows terminals: colours from the Windows 10
   build number, but `cli::is_ansi_tty()` is FALSE on Windows (Unix-only test), so only `\r` redraws are safe.
   IRkernel: `interactive()` is FALSE but `readline()` is replaced by a Jupyter `input_request`, so questions
   still work while `menu()` errors. VERIFIED from cli, Positron, ark and IRkernel sources (runtime on those
   front ends UNCERTAIN).
6. **Ctrl-C steering rests on a platform-independent R mechanism** (runtime verified on macOS only). R's C function `onintrEx()` adds an
   internal `resume` restart before signalling the `interrupt` condition (platform-independent
   `src/main/errors.c`; Windows reaches it through `R_ProcessEvents()` → `onintr()`), while interrupts that
   arrive during a console read use `onintrNoResume()`. VERIFIED from source, and end to end with real
   SIGINTs in interactive R (`$W/e2_driver.R`): steer, follow-up, abort, continue, double Ctrl-C = abort,
   Ctrl-C during time-to-first-token, Ctrl-C at the prompt twice = leave the REPL, session and objects kept.
7. **Abort really cancels the HTTP request.** With a `curl::multi_run(timeout = 0.05, poll = TRUE)` loop and
   `on.exit(curl::multi_cancel(h))`, choosing (a)bort in the pause menu closed the socket; a local server
   logged "client disconnected" and the next request in the same session completed. VERIFIED
   (`$W/g1_driver.R`).
8. **Ctrl-C at a permission prompt aborts the whole run cleanly** (the prompt's own `tryCatch(interrupt=)`
   is innermost, so the pause menu is not shown). VERIFIED with a real SIGINT (`$W/e4_driver.R`).
9. **Permission models compared.** Claude Code: modes `default` (alias `manual`), `acceptEdits`, `plan`,
   `auto` (classifier), `dontAsk`, `bypassPermissions`; rules `Tool(specifier)` evaluated deny → ask → allow;
   protected-path writes are never pre-approved by allow rules (prompted, or routed to the classifier in
   `auto`; only `bypassPermissions` allows them) and "critical path" removals are never approved by allow
   rules or hooks. Codex: independent
   `approval_policy` (`on-request` default, alias `on-failure`; `never`; `granular{...}`; `untrusted` now
   internal) × `sandbox_mode` (`read-only`, `workspace-write`, `danger-full-access`), decisions include
   approve once / for session / with a persisted policy amendment / deny with reason / abort. Pi: no
   built-in gate, only example extensions (regex permission gate, protected paths, plan mode) that fail
   closed without UI. VERIFIED (docs and source, section 8).
10. **Recommended gptr modes: `plan`, `manual`, `edits`, `auto`** (D-11 names), driven by a 0–4 risk level
    per tool call (read-only, local, mutating, dangerous, critical) and Claude-style allow/ask/deny rules.
    `plan` evaluates low-risk R in a throwaway child environment; `edits` auto-approves file writes inside the
    project; `auto` asks only for critical actions (and blocks them without UI); `manual` asks for anything
    above read-only. An 11-row decision matrix and 18 behavioural checks pass (`$W/c2_test.R`).
11. **A static R risk classifier is feasible, fast and useful, but it is advisory only.** The prototype
    walks the parse tree (no evaluation), resolves backtick names, `"unlink"(x)`, `pkg::fn`, `pkg:::fn`,
    `get("x")(...)`, `match.fun`, `do.call`, `rlang::exec`, aliases (`f <- unlink`), higher-order use
    (`lapply(x, file.remove)`), pipes, lambdas, `eval(parse(text = "<literal>"))` (classifies the literal),
    `source("file.R")` (classifies the file), user functions, R6/environment methods and user S3 methods
    found in the session; it classifies path arguments (workspace, temp, outside, protected, critical) and
    detects overwrites of existing objects with their class and size. 101/101 test cases pass (VERIFIED,
    `$W/b1_test.R`, re-run); 1,500 statements classify in 0.3–1.1 s on a heavily loaded machine (load
    average 40–75 during the re-runs; idle-machine timing not measured, LIKELY well under 0.5 s).
12. **What it cannot see (documented blind spots, VERIFIED):** package functions not in its table
    (`targets::tar_destroy()`, `usethis::create_package()`), package load hooks (`library(evilpkg)`), S4
    dispatch to user methods, and anything computed at run time beyond simple literals. It must be presented
    as "when to ask", never as a sandbox.
13. **Never use `utils::askYesNo()` for permissions**: non-interactively it returns its `default`
    (TRUE unless changed) without reading anything, i.e. it fails open. `menu()` and `select.list()` error
    non-interactively. VERIFIED (`$W/a7_prompts.R`).
14. **The `ask` tool** (model-visible, sequential, read-only) takes 1–4 questions of type `single`, `multi`
    or `text` with 2–9 options, `allow_other` and `default`; it merges Claude Code's AskUserQuestion,
    Codex's `request_user_input` and Pi's `questionnaire`. Non-interactively it returns the defaults and
    tells the model to state its assumptions. VERIFIED prototype (`$W/c3_test.R`).
15. **One UI abstraction for all prompts** (`select`, `input`, `questions`, `notify`, `has_ui`) with
    backends: console (shares the REPL's reader so piped answers work), none (fail closed), scripted (tests),
    plus planned RStudio-dialog, Shiny-gadget and RPC backends; front ends replace it with
    `options(gptr.ui = ...)`. VERIFIED for console, none and scripted.
16. **Streaming renderer**: a word-wrapping, incremental markdown styler whose output is byte-identical
    regardless of how the stream is chunked (200 random chunkings, styled and plain), wide-character aware,
    with fenced code blocks and optional per-line `cli::code_highlight()` (which silently returns partial
    lines unchanged). VERIFIED (`$W/d1_test.R`) **in a UTF-8 locale only**: under `Rscript --vanilla` in a
    C locale the chunk-invariance still holds but the width check fails (max width 59 > 40, 2 plain / 6
    styled overlong lines) because the test's non-ASCII literals are read as native bytes. Run the test with
    `LANG=en_US.UTF-8`; gptr must mark streamed text as UTF-8 (`enc2utf8()`) before measuring widths.
17. **Spinners need ticks.** `cli::cli_progress_step(spinner = TRUE)` froze during a 2 s blocking wait and
    animated only when `cli_progress_update()` was called; gptr's HTTP polling loop is the natural ticker.
    VERIFIED (`$W/a9_flush_driver.R`).
18. **Non-interactive defaults**: verbosity 0 in knitr/testthat (nothing added to rendered documents),
    1 under Rscript (one progress line per step on stderr via a classed `message()`), 2 at the console
    (streamed answer, returned invisibly so it is not printed twice). A `knit_print` method puts the answer
    into documents as markdown. VERIFIED (`$W/f1_*.R`).
19. **Snapshots for `/undo` are cheap in R**: `mget()` of objects about to be overwritten costs no copy
    (copy-on-modify); restoring is a rebind. The cost is that the old value stays alive. VERIFIED
    (`$W/h1_snapshot.R`: +4 MB for a 381 MB vector).

---

## 2. Findings

### 2.1 Console mechanics across front ends

#### 2.1.1 Detecting the situation

| Signal | Meaning | Evidence |
|---|---|---|
| `interactive()` | TRUE in terminal R, RGui, R.app, RStudio, Positron; FALSE in Rscript, `R -f`, IRkernel (`R --slave -e IRkernel::main()`), R CMD check | VERIFIED for terminal R (`$W/a2_pty_driver.R`: `interactive()=TRUE`), Rscript (FALSE); IRkernel from `inst/kernelspec/kernel.json` argv `["R", "--slave", "-e", "IRkernel::main()", ...]`; others LIKELY |
| `rlang::is_interactive()` | option `rlang_interactive` if set, else FALSE while `knitr.in.progress` is TRUE, else FALSE when `TESTTHAT == "true"`, else `interactive()` | VERIFIED (printed function body, rlang 1.1.7) |
| `getOption("knitr.in.progress")` | TRUE while knitting, even when knitting from an interactive session | VERIFIED (`$W/f1_doc.Rmd` output: `knitting: logi TRUE`) |
| `getOption("jupyter.in_kernel")` | TRUE inside IRkernel | VERIFIED source `IRkernel/R/kernel.r` line 390 `options(jupyter.in_kernel = TRUE)` |
| `Sys.getenv("RSTUDIO") == "1"` | RStudio (console, terminal, jobs; cli distinguishes them) | VERIFIED cli source (`cli:::rstudio$detect`) |
| `Sys.getenv("POSITRON") == "1"`, `.Platform$GUI == "Positron"` | Positron | VERIFIED `posit-dev/ark` `crates/ark/src/modules/positron/positron.R` lines 8-12 |
| `.Platform$GUI` `"Rgui"` / `"AQUA"` | Windows RGui / macOS R.app | VERIFIED (cli uses both, see below; R `utils/R/zzz.R` uses `"Rgui"`) |
| `Sys.getenv("TERM_PROGRAM") == "vscode"` | VS Code integrated terminal | LIKELY (cli uses `TERM_PROGRAM` for iTerm only) |
| `isatty(stdin())`, `isatty(stdout())` | real terminal | VERIFIED: TRUE/TRUE in a pty for both Rscript and R; FALSE/FALSE with pipes |

gptr should not import rlang for this. A base-R `gptr_context()` (prototype in `$W/f1_result.R`) returns
`human` (someone can see the console now), `can_prompt` (someone can answer; TRUE also in IRkernel),
`knitting`, `testing`, `frontend`. It honours `getOption("gptr.interactive")` and `rlang_interactive` as
overrides. Observed under Rscript: `human FALSE, can_prompt FALSE, knitting FALSE, testing FALSE,
frontend "rscript"`; in knitr: `knitting TRUE`. VERIFIED.

#### 2.1.2 `readline()` behaviour (VERIFIED unless noted)

Source: `src/main/scan.c` `do_readln` (fetched from the r-source mirror; lines 1032-1080 at the time of
fetching) and `?readline`:

- Interactive: skips leading blanks, reads characters until `\n`, discards characters past the internal
  buffer, strips trailing blanks. `?readline`: "Both leading and trailing spaces and tabs are stripped from
  the result." Consequence: indentation of pasted R code is lost (harmless for R) and a prompt consisting of
  spaces is `""`.
- Non-interactive: `Rprintf("%s\n", ConsolePrompt); ans = mkString("")`. Observed under Rscript:
  prints `prompt> ` followed by a newline and returns `""` without touching piped stdin.
- Prompt truncated to `CONSOLE_PROMPT_SIZE - 1` (256 per `?readline`).
- Long lines: `$W/a10_long_driver.R` wrote a 6,000-character line followed by `second`, `third`,
  `fourth`. Both with a pipe console (`R --interactive`) and in a pty, `readline()` returned 4,102
  characters, then `third`, then `fourth`, and the `[p1]` prompt was printed twice. A re-run that also
  printed the last 12 characters showed `tail=abcdefsecond`: the result is **the first 4,096 characters
  of the long line with the next line (`second`) appended without a separator**; the remaining 1,904
  characters were lost, and `second` was not lost but merged. Mechanism (VERIFIED from source, R 4.4.3 tag):
  `ConsoleGetchar()` in `scan.c` reads through `R_ReadConsole(prompt, buf, CONSOLE_BUFFER_SIZE, 0)`
  (`#define CONSOLE_BUFFER_SIZE 4096`, `src/include/Defn.h` line 2031 on trunk, line 1888 in R 4.4.3);
  R 4.4.3's `readline_handler()` (`src/unix/sys-std.c`) copies at most 4,096 bytes with no trailing `\n`
  and frees the rest, so `do_readln` calls `R_ReadConsole` again (second prompt) and reads the next line
  into the same result. R trunk commit "Unlimited line length on Unix with readline (PR#18690)"
  (2024-08-13; present in the R-4-5-0 tag as `readline_rest`) keeps the remainder for the next read, so on
  R >= 4.5.0 with GNU readline a long line should arrive whole up to `do_readln`'s own buffer
  (`MAXELTSIZE` 8192: bytes past 8,190 are skipped). R >= 4.5 runtime, Windows Rterm/RGui, RStudio and
  Positron: UNCERTAIN (not run). gptr's minimum is R 4.1 (D-23), so the R 4.4 behaviour must be handled.
- Ctrl-D on an empty prompt returns `""` and does not quit R; Ctrl-D after text is ignored until Enter
  (`$W/a8_ctrld_driver.R`: `readline returned: ""  nchar = 0`, `STILL ALIVE`). gptr cannot use EOF to
  leave the REPL in interactive mode. (The prototype's `/help` text in `$W/e1_repl.R` still lists Ctrl-D
  as a way out; that is true only for piped input and must not be copied into gptr's help.)
- History: text entered at a `readline()` prompt is not added to the console history; Up-arrow at the next
  `readline()` recalled the previous top-level command `source('a5_history_child.R')`. After
  `utils::timestamp(stamp = "added via timestamp()", prefix = "", suffix = "", quiet = TRUE)` Up-arrow
  recalled `added via timestamp()` (`$W/a5_history_driver.R`: `GOT2: source('a5_history_child.R')`,
  `GOT3: added via timestamp()`).
- In IRkernel `base::readline` is replaced at every execute request by a function that sends a Jupyter
  `input_request` and waits for `input_reply` (`IRkernel/R/execution.r` lines 130-137 and 271-272:
  `replace_in_package('base', 'readline', .self$readline)`). VERIFIED source; runtime UNCERTAIN.

#### 2.1.3 Reading stdin under Rscript (VERIFIED, `$W/a1_stdin.R`, `a1b_stdin.R`, `a1c_stdin.R`)

Command: `printf 'line one\nline two\nline three\nline four\n' | Rscript --vanilla a1_stdin.R` and variants.

```text
readline() -> ""                                   # after printing "prompt> " and a newline
fresh file('stdin') call 1 -> "line one"
fresh file('stdin') call 2 -> character(0)         # buffered data lost with the first connection
fresh file('stdin') call 3 -> character(0)
persistent call 1 -> "line one" (length 1)        # con <- file("stdin", open = "r") once
persistent call 2 -> "line two" (length 1)
persistent call 3 -> "line three" (length 1)
persistent call 4 -> character(0) (length 0)       # EOF
stdin() call 1 -> "x <- scan(file = \"stdin\", ...)"   # stdin() is the SCRIPT being run
```

So the REPL reader for non-interactive use is: open `file("stdin", open = "r")` once, `readLines(con, n = 1)`,
treat `character(0)` as EOF. The REPL prototype runs complete sessions this way, including permission
prompts and ask-user questions answered from the same pipe (`$W/e1_run.R < $W/e1_input.txt`).

#### 2.1.4 Paste and type-ahead (VERIFIED in a pty on macOS, `$W/e3_pty_driver.R`)

- Writing `"pasted line one\rpasted line two\r"` in one go produced two separate turns
  (`TRANSCRIPT user pasted line one`, `TRANSCRIPT user pasted line two`). R's readline in this build does
  not enable bracketed paste (no `ESC[?2004h` in the output; `ESC[?1034h` meta-mode only). Terminal
  emulators with bracketed paste and a newer readline could differ: UNCERTAIN.
- Typing `typed while busy` while the agent was streaming: the tty echoed it inline
  (`...Ctrl-C to steer or stop)typed while busy`), and after the run finished the next `readline()` returned
  it and it ran as the next turn. Type-ahead is therefore a free "follow-up queue" in terminal R.
  RStudio queues console input while R is busy too (LIKELY, not tested).

#### 2.1.5 Colour, dynamic updates, cursor control: what cli decides (VERIFIED from cli 3.6.6 source)

- `cli::num_ansi_colors()` order: option `cli.num_colors`; env `R_CLI_NUM_COLORS`; `crayon.enabled`/
  `crayon.colors`; env `NO_COLOR` → 1; `knitr.in.progress` → 1; sink active → 1; stderr redirected → 1;
  option `cli.default_num_colors`; `.Platform$GUI == "AQUA"` → 1; RStudio console/build pane/job →
  `RSTUDIO_CONSOLE_COLOR`; `.Platform$GUI == "Rgui"` → 1; not a tty → 1; else `detect_tty_colors()`
  (`COLORTERM=truecolor|24bit` → 16,777,216; Windows 10 build ≥ 10586 → 256, ≥ 14931 → truecolor, after
  running `system2("cmd", c("/c", "echo 1 >NUL"))`, presumably to put the console into VT mode (purpose
  LIKELY, call VERIFIED); `tput colors` on Unix).
- `cli::is_dynamic_tty()` (can use `\r`): option `cli.dynamic`, env `R_CLI_DYNAMIC`, else
  `isatty(stream) || RStudio dynamic || R.app interactive || RKWard`.
- `cli::is_ansi_tty()` (can use cursor movement): option `cli.ansi`; RStudio `ansi_tty` capability (FALSE
  for every RStudio pane type); else `isatty(stream) && .Platform$OS.type == "unix" && !is_rapp() &&
  !is_emacs() && TERM != "dumb"`. **Always FALSE on Windows** unless forced by option.
- RStudio capability table (`get("caps", environment(cli:::rstudio$detect))`): `rstudio_console`:
  `dynamic_tty = TRUE, ansi_tty = FALSE, num_colors = RSTUDIO_CONSOLE_COLOR, hyperlink =
  RSTUDIO_CLI_HYPERLINKS != ""`; `rstudio_terminal`: dynamic TRUE, 1 colour; `rstudio_job`: dynamic FALSE;
  `rstudio_render_pane`: dynamic TRUE, 1 colour.
- Positron: `extensions/positron-r/resources/scripts/startup.R` sets `options(cli.default_num_colors =
  256L)`, `options(cli.dynamic = TRUE)`, `options(cli.hyperlink = TRUE)` and the `hyperlink_run/help/
  vignette` variants. VERIFIED (raw file). ark does not set cli options itself (`options.R`, VERIFIED).
- Measured (`$W/a2_pty_driver.R`, pty, macOS):

| Situation | num_ansi_colors | is_ansi_tty | is_dynamic_tty | console_width |
|---|---|---|---|---|
| Rscript in pty, `TERM=xterm-256color COLORTERM=truecolor` | 16777216 | TRUE | TRUE | 80 |
| Rscript in pty, `TERM=dumb` | 1 | FALSE | TRUE | 80 |
| Rscript in pty, `NO_COLOR=1` | 1 | TRUE | TRUE | 80 |
| interactive R in pty, `TERM=xterm-256color` | 256 | TRUE | TRUE | 80 (`COLUMNS=80` set by R) |
| Rscript with pipes | 1 | FALSE | FALSE | 80 |

- macOS terminal R prints everything sent to stderr in **bold** (the R-admin manual: "warnings, messages
  and other output to stderr are highlighted in bold"; observed `ESC[1mto-stderr ESC[0m` for `message()`
  in `$W/a4_stderr_bold.R`). gptr's styled output should go to stdout; stderr is for progress and
  diagnostics.

#### 2.1.6 Front-end matrix

| Front end | `interactive()` | `readline()` | `menu()` | Interrupt | Colours | `\r` redraw | Cursor ANSI | Status |
|---|---|---|---|---|---|---|---|---|
| Terminal R, macOS/Linux | TRUE | GNU readline editing; no history entry | works | Ctrl-C (SIGINT), resumable during computation | tty detection (256 / truecolor) | yes | yes | VERIFIED (macOS pty); Linux LIKELY |
| Rterm, Windows (conhost / Windows Terminal) | TRUE | simple line editing (rw-FAQ 5.1) | works | Ctrl-C or Ctrl-Break (rw-FAQ 5.1) | Win10 build detection | yes | no (cli Unix-only) | source/docs VERIFIED, runtime UNCERTAIN |
| RGui, Windows | TRUE | GUI console | works (`graphics = TRUE` gives a dialog) | **Esc** (Ctrl-C is copy, rw-FAQ 5.1) | 1 | no (not a tty) | no | docs VERIFIED, runtime UNCERTAIN |
| R.app, macOS | TRUE | GUI console | works | Esc / Cmd-. (LIKELY) | 1 | yes (`is_rapp_stdx`) | no | cli source VERIFIED |
| RStudio console | TRUE | console input | works | Esc or Stop button (LIKELY) | `RSTUDIO_CONSOLE_COLOR` | yes | **no** | cli source VERIFIED, runtime UNCERTAIN |
| Positron console | TRUE (LIKELY) | via ark ReadConsole (LIKELY) | LIKELY works | Stop / Ctrl-C (LIKELY) | 256 (startup option) | yes (option) | UNCERTAIN | startup.R VERIFIED |
| VS Code (vscode-R terminal) | TRUE | terminal R semantics | works | Ctrl-C | terminal | yes | yes | LIKELY |
| Jupyter / IRkernel | **FALSE** | replaced by `input_request` | **errors** | kernel interrupt (SIGINT, LIKELY) | not a tty → 1 unless options set | no | no | source VERIFIED |
| Rscript | FALSE | returns `""` | errors | Ctrl-C terminates (LIKELY, not tested) | tty-dependent | tty-dependent | tty-dependent | VERIFIED except the interrupt column |
| knitr / Quarto rendering | depends; `rlang::is_interactive()` FALSE | must not be called | must not be called | n/a | 1 | n/a | n/a | VERIFIED (option) |

#### 2.1.7 Streaming, wrapping, markdown, flushing

- `cat()` to a pipe or pty is not held back on macOS: chunks arrived 0.2 s, 0.6 s, 1.0 s, 1.4 s apart with
  and without `flush(stdout())` (`$W/a9_flush_driver.R`). `?flush.console`: "This does nothing except on
  console-based versions of R. On the macOS and Windows GUIs, it ensures that the display of output in the
  console is current, even if output buffering is on." So the renderer calls `flush(stdout())` and
  `flush.console()` after each delta (cheap). VERIFIED.
- ellmer's streaming wrapper (`ellmer:::sink_wordwrap_gen`, printed from the installed 0.4.0) buffers the
  last whitespace-delimited token until the next chunk, wraps at `cli::console_width()`, uses `nchar()`
  (characters, not display width), and does not style markdown. VERIFIED.
- gptr prototype `md_stream()` (`$W/d1_stream.R`): tokenises into newline / blank run / word, buffers only
  the trailing possibly-incomplete token, measures `nchar(type = "width")` (CJK counts 2), defers blanks so
  no line ends in a space, and in styled mode toggles `**bold**`, `` `code` `` (cyan), headings (bold
  underline, `#` removed), bullets (`•` with hanging indent), numbered items, `>` quotes (dim gutter) and
  fenced code (dim `┌─ r` / `│` / `└─`, no wrapping, optional per-line highlighting). Plain mode keeps the
  markdown characters and only wraps. Result: identical output for 200 random chunkings (1–9 characters)
  in both modes; no prose line exceeded the width. VERIFIED with `LANG=en_US.UTF-8`; in a C locale the
  width check fails (see summary item 16), so the test must set a UTF-8 locale and gptr must hand the
  renderer UTF-8-marked strings.
- `cli::code_highlight()` is a no-op without colours and returns an unparseable line such as
  `"for (i in 1:3) {"` unchanged instead of erroring (observed with `cli.num_colors = 256`), so per-line
  highlighting of streamed fenced R code is safe. VERIFIED.
- `cli::cli_text()` / `cli::cli_bullets()` are not suitable for token streaming (they format whole
  paragraphs and wrap on their own); use them for complete messages (banner, errors, `/help`). LIKELY
  (cli documentation; not separately tested).

#### 2.1.8 Spinners and status lines

- `cli::cli_progress_step("Waiting for the model", spinner = TRUE); Sys.sleep(2)` showed one frame, then
  the final `v Waiting for the model [2s]`: the spinner is frozen while R is blocked. Calling
  `cli::cli_progress_update()` every 0.1 s animated it (frames about every 0.2 s). VERIFIED
  (`$W/a9_flush_driver.R`). gptr must tick from the loop that polls the HTTP connection, which it needs
  anyway for interrupt responsiveness (report 02: `curl::multi_run(timeout = 0.05, poll = TRUE)`).
- gptr prototype `wait_indicator()` uses only `\r` (safe in RStudio and Windows consoles), is disabled when
  `cli::is_dynamic_tty()` is FALSE, clears itself with `\r` + spaces + `\r` before the first token, and shows
  `(Ns, Ctrl-C to steer or stop)`. Observed in a pty: `<CR>⠋ thinking (0s, Ctrl-C to steer or stop)<CR>⠙ ...
  <CR><spaces><CR>You said: ...`. VERIFIED.

#### 2.1.9 Prior art in R

- `ellmer::live_console(chat, quiet = FALSE)` (ellmer 0.4.0, printed source): aborts unless
  `is_interactive()`; banner via `cli::cat_boxx()`; loop `readline(prompt = ">>> ")`; `Q` quits; blank lines
  ignored; `"""` opens a multi-line block read with `readline(prompt = "... ")` until a line ends with
  `"""`; each turn `chat$chat(user_input, echo = TRUE)`. No interrupt handling, no commands, no R
  passthrough. `live_browser()` wraps `shiny::runGadget(shinychat::chat_app(chat))` in
  `tryCatch(interrupt = function(cnd) NULL)`. VERIFIED.
- ellmer's tool approval hook: `Chat$on_tool_request(callback)` and `tool_reject(reason)` which raises a
  condition of class `ellmer_tool_reject`; tool metadata via `tool_annotations(title, read_only_hint,
  open_world_hint, idempotent_hint, destructive_hint, ...)`. VERIFIED (printed functions). gptr can map
  these annotations when bridging ellmer tools.
- Echo policy in ellmer: `check_echo()` uses option `ellmer_echo`, else `"output"` when the calling
  environment is user-facing (`rlang::env_is_user_facing`), else `"none"`; `chat()` returns text
  invisibly when it echoed. VERIFIED. gptr adopts the same visibility rule (2.7).
- Other packages (chattr: Shiny app plus console; askgpt; gptstudio: add-ins) were not read. LIKELY per
  their CRAN/website descriptions (section 8); whether any of them offers steering or permission prompts
  was not checked (UNCERTAIN).

### 2.2 Interrupts, abort and steering

#### 2.2.1 R mechanics (VERIFIED from `src/main/errors.c`, `src/unix/sys-std.c`, `src/gnuwin32/system.c`)

```c
static void onintrEx(Rboolean resumeOK)
{
    if (R_interrupts_suspended) { R_interrupts_pending = 1; return; }
    else R_interrupts_pending = 0;
    if (resumeOK) {
        ... begincontext(&restartcontext, CTXT_RESTART, ...);
        if (SETJMP(restartcontext.cjmpbuf)) { ... return; }   /* invokeRestart("resume") lands here */
        addInternalRestart(&restartcontext, "resume");
        signalInterrupt();
        endcontext(&restartcontext);
    }
    else signalInterrupt();
    ...
    jump_to_top_ex(TRUE, tryUserError, TRUE, TRUE, FALSE);
}
void onintr(void)  { onintrEx(TRUE); }
void onintrNoResume(void) { onintrEx(FALSE); }
```

- `R_CheckUserInterrupt()` → `R_ProcessEvents()` → `if (R_interrupts_pending) onintr();` (resumable).
- Windows: `R_ProcessEvents()` checks `UserBreak` and calls `onintr()` (resumable); `R_ReadConsole()`
  calls `onintrNoResume()` when an interrupt arrives while reading console input.
- Unix: `handleInterrupt()` during readline input calls `onintrNoResume()`.
- Therefore: an interrupt during computation (streaming loop, tool code, `Sys.sleep`) can be resumed by a
  calling handler; an interrupt during `readline()` cannot, and is simply caught as a condition.
- `suspendInterrupts()` defers interrupts (`R_interrupts_suspended`), used for atomic session-file appends
  (report 02, 5.8).

#### 2.2.2 The pattern (VERIFIED end to end, `$W/e1_repl.R` `run_with_interrupt_menu()`, `$W/e2_driver.R`)

```r
tryCatch(
  withCallingHandlers({ run_agent(); "done" },
    interrupt = function(cnd) {                       # calling handler: stack still intact
      ans <- tryCatch(reader$read("[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? "),
                      interrupt = function(e) "a")     # Ctrl-C again while the menu waits = abort
      if (ans %in% c("s", "f")) { queue(read_one_line()); invokeRestart("resume") }
      if (ans %in% c("c", "")) invokeRestart("resume")
      # "a": return normally -> the condition continues to the exiting handler below
    }),
  interrupt = function(cnd) { drop_queues(); "aborted" })   # unwinds: on.exit() closes HTTP, tool code
```

Observed in interactive R with real SIGINTs (`p$interrupt()` from processx), all seven scenarios passed:
steer delivered after the current message (`TRANSCRIPT user steer please answer in French`), follow-up
delivered after the run, abort returned to the prompt, a second Ctrl-C while the menu waited aborted,
Ctrl-C during the "thinking" wait (before the first token) continued, `!z <- 99; z * 2` worked afterwards
(`[1] 198`), one Ctrl-C at the prompt printed the hint and a second left the REPL
(`REPL EXITED; back at the R top level`, `R still alive, z = 99`).

#### 2.2.3 Abort cancels the network request (VERIFIED, `$W/g1_driver.R`)

A base-R socket server streamed `data: token i` every 0.15 s and logged write failures. The client streamed
with `curl::multi_add()` + `curl::multi_run(timeout = 0.05, poll = TRUE, pool = pool)` and
`on.exit(curl::multi_cancel(h))`. Ctrl-C at about 2.2 s, then `a`:

```text
STREAM 1 START
 token 1 ... token 12
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? [transport] request cancelled/cleaned up
[gptr] aborted; the session is kept.
STREAM 1 RESULT: aborted
STREAM 2 START
 token 1 ... token 60 [transport] request cancelled/cleaned up
STREAM 2 RESULT: done
==== server log
18:58:42.82 request 1 accepted
18:58:45.59 request 1 client disconnected before token 19
18:58:45.59 request 2 accepted
18:58:55.27 request 2 completed all tokens
```

While the menu waits the stream is not polled; the server keeps writing into socket buffers. A long pause
can therefore end in a provider-side timeout; "continue" must treat a dead stream as a retryable error
(LIKELY; not tested against real providers).

#### 2.2.4 Steering semantics to copy

- Pi: `Enter` while streaming = **steer** (delivered "until the current response and its tool calls
  finish, then guides the next response"); `Alt+Enter` = **follow-up** (waits until Pi finishes the current
  task); `Alt+Up` returns queued messages to the editor; `Escape` stops; "Aborting returns queued messages
  to the editor." (`packages/coding-agent/docs/usage.md` lines 29-40; keybindings `app.interrupt` =
  escape, `app.clear` = ctrl+c "Clear editor (first) / exit (second)", `app.exit` = ctrl+d,
  `app.message.followUp` = alt+enter (`ctrl+q` on Windows and WSL), `app.message.dequeue` = alt+up
  (`alt+q` on Windows and WSL), `docs/keybindings.md` lines 123-125,
  165-166). VERIFIED.
- Claude Code: messages typed while working are queued; "if you queue a message while Claude is running
  tool calls, Claude Code passes it to Claude as soon as those tool calls finish, within the same turn";
  `Esc` interrupts and sends queued messages right away; double `Esc` opens the rewind menu; `Ctrl+C`
  interrupts or clears input, a second press exits (interactive-mode docs). VERIFIED.
- gptr in the console cannot read input while R is busy, so: (1) the pause menu offers steer and follow-up;
  (2) terminal type-ahead becomes the next prompt; (3) `/queue <text>` queues follow-ups before starting a
  run; (4) side channels from report 02 (file inbox `.gptr/sessions/<id>.inbox.jsonl`, optional httpuv
  endpoint pumped by `later::run_now(0)`) let another process or a Shiny gadget steer or abort.

#### 2.2.5 REPL vs programmatic calls

- In the REPL, abort returns to the `gptr>` prompt; queued steering/follow-ups are printed as "Dropped
  queued messages" (Pi returns them to the editor; `readline()` cannot pre-fill, so gptr prints them and keeps
  them in `session$dropped` for `/queue restore`).
- In `gptr("prompt")` at the console, the same menu appears (REQ-38), but (a)bort must stop the whole R
  expression, otherwise `for (i in 1:100) gptr(...)` would continue with the next iteration. So the
  programmatic path persists the session, stores the partial result for `gptr_last()`, and re-signals the
  interrupt (report 02, 4.8 item 6).
- Non-interactive (`Rscript`, knitr): no menu; an interrupt aborts and propagates as usual.

### 2.3 The input language of the REPL

- Pi dispatch order (report 05 digest; `interactive-mode.ts` lines 3150-3300 VERIFIED for the built-in
  part): built-in `/commands` → `!`/`!!` shell → extension commands / input handlers → `/skill:name` →
  prompt templates → model. `!cmd` output enters the context as a user message rendered by
  `bashExecutionToText()`: ``Ran `cmd` `` + fenced output (+ "(command cancelled)" or "Command exited with
  code N" or a truncation note); `!!` sets `excludeFromContext` (`src/core/messages.ts` lines 27-39,
  82-98, 152-161). If the agent is streaming, the record is deferred until `agent_end` to keep
  tool_use/tool_result ordering (`agent-session.ts` lines 3781-3802). VERIFIED.
- Claude Code `!` shell mode: "Adds the command and its output to the conversation context"; multi-line
  input via `\` + Enter, Option+Enter, Shift+Enter, Ctrl+J, or paste (interactive-mode docs). VERIFIED.
- gptr prototype grammar (VERIFIED in `$W/e1_run.out`; the fenced block and trailing-`\` forms are not in
  that transcript and were verified separately by piping them into `e1_run.R`): natural language; `/command args`; `!R code`
  (continued with a `+ ` prompt while `parse()` reports an incomplete expression, exactly like the R console);
  `!!R code` (not added to context); a line starting with ```` ``` ```` opens a fenced R block closed by
  ```` ``` ````; `"""` opens a multi-line prompt closed by `"""`; a trailing `\` continues; `@file` and
  `@object` mentions expand into `<file path="...">` / `<object name="..." class="..." size="...">` blocks.
  Incompleteness test: `parse()` error message matching `unexpected end of input|INCOMPLETE_STRING`.

### 2.4 Permission models of other harnesses

#### 2.4.1 Claude Code (VERIFIED, code.claude.com docs fetched 2026-09-29)

Modes (permissions page, "Permission modes" table):

| Mode | Description (quoted) |
|---|---|
| `default` | "Prompts for permission on first use of each tool. Labeled Manual in the CLI ... Claude Code accepts `manual` as an alias." |
| `acceptEdits` | "Automatically accepts file edits and common filesystem commands such as `mkdir`, `touch`, `mv`, and `cp` for paths in the working directory or `additionalDirectories`" |
| `plan` | "Claude reads files and runs read-only shell commands to explore but doesn't edit your source files" |
| `auto` | "Auto-approves tool calls with background safety checks that verify actions align with your request" |
| `dontAsk` | "Auto-denies every call that would otherwise prompt" (pre-approved tools still run; AskUserQuestion is denied) |
| `bypassPermissions` | "Skips permission prompts, except for the actions no mode auto-approves" |

- Rules: `Tool` or `Tool(specifier)`; "Rules are evaluated in order: deny, then ask, then allow. The first
  match in that order determines the outcome, and rule specificity doesn't change the order." A bare
  deny rule (`Bash`) removes the tool from the model's context. Bash rules split compound commands on
  `&&`, `||`, `;`, `|`, `|&`, `&`, newlines; strip wrappers `timeout`, `time`, `nice`, `nohup`, `stdbuf`,
  `command`, `builtin`, `noglob`; Read/Edit rules use gitignore patterns with anchors `//abs`, `~/home`,
  `/settings-relative`, `./cwd-relative`. The docs state plainly that a Bash rule "isn't a security boundary
  around the program" (`/bin/rm` or `bash -c` evade `Bash(rm *)`).
- "Yes, and don't ask again": Bash and WebFetch approvals persist to `.claude/settings.local.json` at the
  repository root; file-modification approvals last "Until session end". A prompt offers "don't ask again"
  "only when the prompt can show you everything they would allow". Comments can be attached to Yes/No; a
  No with a comment becomes the denial reason and Claude continues; a bare No stops the turn.
- Protected paths are never pre-approved by allow rules or `acceptEdits`: per the permission-modes page,
  writes to them are prompted in `default`/`acceptEdits`, **routed to the classifier in `auto`** (so the
  classifier, not a human, may approve them unless the session uses `--restricted`), denied in `dontAsk`,
  and allowed in `bypassPermissions` (and in plan mode when bypass is available). Directories `.git`,
  `.config/git`, `.vscode`, `.idea`, `.husky`, `.cargo`, `.devcontainer`, `.yarn`, `.mvn`, `.claude` (except
  `.claude/worktrees`); files such as `.gitconfig`, `.bashrc`, `.zshrc`, `.profile`, `.envrc`, `.npmrc`,
  `.mcp.json`, `.claude.json` (full list in section 3.3).
- Critical paths: `rm`/`rmdir` targeting a critical path are never approved by an allow rule or a
  `PreToolUse` hook. The list is broader than root/home/cwd: the filesystem root, **every top-level
  directory** (`/usr`, `/etc`, ...), home, Windows drive roots and their top-level directories, **the working
  directory and its parents**, and globs under additional working directories. gptr's own critical-path
  class (3.8) should consider the top-level-directory and parent-of-project cases too.
- Starting mode: the permission-modes page says that from Claude Code v2.1.283 **auto mode is the built-in
  starting mode** for interactive terminal and VS Code sessions (earlier versions: only on Pro, Max and Team
  plans); `default` (Manual) is the config value's default name, not necessarily the mode a session starts in.
- Auto mode: "a second model, the classifier, reviews actions"; the classifier sees user messages, tool
  calls and CLAUDE.md but "Tool results are stripped from those requests"; 3 consecutive or 20 total blocks
  pause auto mode and fall back to prompting; boundaries stated in conversation ("don't push") are honoured;
  broad allow rules for arbitrary code execution (`Bash(*)`, interpreters) are dropped on entering auto.
- Plan approval options: "Yes, and use auto mode", "Yes, manually approve edits", "No, keep planning".
- Mode cycle `Shift+Tab`: `default` → `acceptEdits` → `plan` → (optional `bypassPermissions`, `auto`).

#### 2.4.2 Codex (VERIFIED: learn.chatgpt.com docs, `openai/codex` main `2cc65cdd`, 2026-09-30)

- `codex-rs/protocol/src/protocol.rs`: `enum AskForApproval { #[serde(rename = "untrusted")]
  UnlessTrusted, #[serde(alias = "on-failure")] #[default] OnRequest, Granular(GranularApprovalConfig),
  Never }` with doc comments "Internal policy for projects marked untrusted", "The model decides when to ask
  the user for approval", "Never ask the user to approve commands. Failures are immediately returned to the
  model, and never escalated to the user for approval."
- `GranularApprovalConfig { sandbox_approval, rules, skill_approval, request_permissions,
  mcp_elicitations }`: "When a field is `true`, commands in that category are allowed. When it is `false`,
  those requests are automatically rejected instead of shown to the user."
- `SandboxPolicy`: `danger-full-access`, `read-only {network_access}`, `external-sandbox {network_access}`,
  `workspace-write {writable_roots, network_access, exclude_tmpdir_env_var, exclude_slash_tmp}`.
- `ReviewDecision`: `Approved`, `ApprovedExecpolicyAmendment {proposed_execpolicy_amendment}`,
  `ApprovedForSession`, `ApprovedMcpPolicyAmendment`, `NetworkPolicyAmendment`, `Denied {rejection}`
  ("should not execute it, but it should continue the session and try something else"), `TimedOut`,
  `Abort` ("should not do anything until the user's next command"). Default is `Denied`.
- Docs: default pairing `sandbox_mode = "workspace-write"` + `approval_policy = "on-request"`; `untrusted`
  is "no longer supported" as a selectable policy; network access in workspace-write defaults to off;
  inside writable roots `.git`, `.agents`, `.codex` stay read-only; `approvals_reviewer = "auto_review"`
  routes approvals to an automated reviewer; `--dangerously-bypass-approvals-and-sandbox` (alias `--yolo`);
  `/permissions` switches interactively; Windows uses a native sandbox in PowerShell and the Linux sandbox
  under WSL2.
- Codex's ask-user protocol `request_user_input` (`codex-rs/protocol/src/request_user_input.rs`):
  questions `{id, header, question, isOther, isSecret, options?: [{label, description}]}`, `isBlocking`;
  response `{answers: {<id>: {answers: [string]}}}`.
- Lesson for gptr: Codex's safety comes from an OS sandbox around a child process. gptr's R evaluation is
  in-process by design (REQ-22), so gptr can only copy the *approval* half of Codex, not the sandbox half.

#### 2.4.3 Pi (VERIFIED, local clone)

- `docs/security.md` lines 3-7: Pi "does not ask for approval before every tool call"; "Watching the
  transcript, using project trust, and reviewing changes do not create a security boundary"; isolation is
  containers/VMs.
- `examples/extensions/permission-gate.ts` (34 lines): regexes `/\brm\s+(-rf?|--recursive)/i`,
  `/\bsudo\b/i`, `/\b(chmod|chown)\b.*777/i` on `event.input.command` of the `bash` tool; without UI returns
  `{ block: true, reason: "Dangerous command blocked (no UI for confirmation)" }`; otherwise
  `ctx.ui.select(..., ["Yes", "No"])`.
- `protected-paths.ts` (30 lines): substring match of `.env`, `.git/`, `node_modules/` on `write`/`edit`
  paths → block.
- `plan-mode/` (README, `utils.ts` lines 7-101): disables edit/write, bash allowlist (`cat`, `grep`, `ls`,
  `git status|log|diff|show|branch`, ...) and denylist (`rm`, `mv`, redirections `>`/`>>`, package installs,
  git writes, `sudo`, editors); extracts a numbered `Plan:`; `[DONE:n]` markers; `/plan`, `/todos`,
  Ctrl+Alt+P.
- `question.ts`: tool `question {question, options: [{label, description?}]}`, `executionMode:
  "sequential"`, adds "Type something." as a free-text option; returns error text when `ctx.mode !== "tui"`;
  results "User selected: N. label" / "User wrote: text" / "User cancelled the selection".
- `questionnaire.ts` lines 51-72, 396-414: `questions: [{id, label?, prompt, options: [{value, label,
  description?}], allowOther? (default true)}]`; result lines `"<label>: user selected: N. <label>"` or
  `"<label>: user wrote: <text>"`; cancelled → "User cancelled the questionnaire".
- Extension UI contract (`src/core/extensions/types.ts` lines 114-119, 148-160, 323-331): `select(title,
  options, {signal, timeout})`, `confirm(title, message, opts)`, `input(title, placeholder, opts)`,
  `notify(message, type)`, `custom()`, `editor()`, plus `ctx.mode` (`"tui" | "rpc" | "json" | "print"`) and
  `ctx.hasUI` ("true in TUI and RPC modes"). `timed-confirm.ts` shows dialogs with `timeout` and `signal`.

### 2.5 Static risk classification of R code

Why a classifier and not a sandbox: R evaluation happens in the user's process with the user's rights
(REQ-22, S-4). There is no in-process capability system; `local()`, child environments or `callr` do not
stop `unlink()` or `system2()`. OS sandboxes are platform specific and would require a separate process,
which defeats in-memory compute. So gptr labels code before running it and uses the label to decide whether
to ask. Statement for the documentation (proposed wording):

> gptr reads R code without running it and labels the effects it can see. It cannot see code that is built
> at run time, functions from packages it does not know, S4 methods, compiled code, or anything a package
> does when it loads. The label decides when gptr asks you; it is not a security boundary. Code that gptr
> runs has your permissions. For untrusted tasks use a worker sub-agent in a container or VM, and keep your
> work under version control.

#### 2.5.1 Parser facts (VERIFIED, `$W/a3_parse_quirks.R`)

- `` `unlink`("x") ``, `"unlink"("x")` and `'unlink'('x')` all parse to a call whose head is the **symbol**
  `unlink` (the parser converts a string in function position); `"\u0075nlink"('x')` too.
- `base::unlink`, `base:::unlink`, `base::` `` `unlink` `` and `"base"::"unlink"` are calls to `::`/`:::`
  whose arguments may be symbols **or strings**.
- `` `base::unlink`("x") `` is a single symbol named `base::unlink` (fails at run time; classify
  conservatively).
- `x -> y` becomes `<-`(y, x); `x ->> y` becomes `<<-`; `x |> f()` is rewritten to `f(x)` at parse time;
  `x %>% f()` stays a `%>%` call; `\(x) ...` is `function`.
- `codetools::findGlobals(fun, merge = FALSE)` reported `unlink` and `file.remove` as *variables* and
  `system` only as `::`: not sufficient on its own.
- `getParseData()` token for `"quit"()` is `STR_CONST` even though the AST head is a symbol; the AST is the
  right level.

#### 2.5.2 Prototype results (VERIFIED, `$W/b1_classifier.R`, `$W/b1_test.R`, output `$W/b1_test.out`)

101 of 101 expectation cases pass. Levels: 0 read-only, 1 local, 2 mutating, 3 dangerous, 4 critical.
Excerpt (full table in Appendix A.2):

| Code | Level | Why |
|---|---|---|
| `summary(mtcars); head(df[df$a > 1, ])` | 0 | nothing flagged |
| `fit <- lm(mpg ~ wt, data = mtcars)` | 1 | creates `fit` |
| `df <- head(df, 2)` (df exists) | 2 | overwrites existing object `df` <data.frame, 744 bytes> |
| `cfg$token <- 'abc'` (cfg is an environment) | 2 | modifies a reference object in place |
| `"unlink"('x')`, `` `unlink`('x') ``, `"base"::"unlink"('x')`, `(unlink)('x')` | 3 | file_delete |
| `do.call('unlink', ...)`, `get('system')('ls')`, `match.fun('file.remove')(...)`, `utils::getFromNamespace('unlink','base')('x')`, `rlang::exec('unlink','x')` | 3 | resolved indirect call |
| `x <- 'unlink'; do.call(x, list('a'))` | 3 | function chosen by a variable |
| `f <- unlink; f('x')`, `f <- get('unlink')` | 3 | alias |
| `lapply(files, file.remove)`, `Map(unlink, files)`, `purrr::walk(files, fs::file_delete)`, `files %>% unlink`, `(function(f) f('x'))(unlink)` | 3 | function passed as a value |
| `eval(parse(text = "unlink('x')"))` | 3 | eval + the literal is classified |
| `source('helper.R')` (file contains `unlink(...)`) | 3 | the file is classified recursively |
| `cleanup('data')` (user function in the session calling `unlink`) | 3 | user function body classified |
| `obj$cleanup()` (R6-like environment method), `print(structure(1, class = 'evil'))` (user S3 method `print.evil`) | 3 | method bodies found in the session |
| `system2('rm', ...)`, `processx::run('ls')`, `processx::process$new(...)` | 3 | process |
| `install.packages(...)`, `remove.packages(...)` | 3 | package |
| `download.file(url, 'x.csv')` | 2 | network |
| `setwd('/')`, `Sys.setenv(PATH = '')`, `options(warn = 2)` | 2 | session state (`options('digits')` is 0) |
| `write.csv(mtcars, 'out.csv')` / `'/etc/out.csv'` / `writeLines('x', '~/.Rprofile')` | 2 / 3 / 3 | path: workspace / outside / protected |
| `saveRDS(big, file.path(tempdir(), 'big.rds'))`, `unlink(tempfile())` | 1 | temp path |
| `unlink(tempdir(), recursive = TRUE)`, `unlink('~', ...)`, `unlink('.', ...)`, `file.remove('.git/config')` | 4 | critical / protected delete |
| `rm(list = ls())`, `q('no')`, `tools::pskill(Sys.getpid())`, `sapply(1:3, q)` | 4 | critical |
| `ggplot(df, aes(x = q, y = system))`, `dplyr::filter(df, run > 1)` | 0 | column names are not calls |
| `Sys.getenv('OPENAI_API_KEY')` / `Sys.getenv('HOME')` / `Sys.getenv()` | 2 / 0 / 2 | secret-looking name or dump-all |
| `browser()`, `readline('continue? ')` | 3 | would block the agent on input |
| `httr2::request(u) \|> httr2::req_body_json(list(k = key)) \|> httr2::req_perform()` | 3 | network send |
| `quote(unlink('x'))`, `body(f) <- quote(unlink('x'))` | 2 | quoted code capped at 2 |
| `this is not R code {` | invalid | parse error returned to the model, nothing evaluated |

Documented blind spots (the true risk is dangerous; classifier result shown):

```text
got 1 local     | library(evilpkg)                 | package .onLoad/.onAttach hooks are invisible
got 0 read-only | targets::tar_destroy()           | package functions not in the table
got 0 read-only | usethis::create_package('.')     | package functions not in the table
got 0 read-only | show(s4obj)                      | S4 dispatch to a user method is not followed
```

Other facts: classifying code that deletes a real file left it in place (`file still exists after
classifying code that deletes it: TRUE`); 500 lines × 3 statements took 0.33–0.54 s in the original runs
and 0.66–1.14 s in four verification re-runs (machine heavily loaded, load average 40–75; profile showed
time in the walker and `sub`/`grepl`); typical tool calls are a few lines (milliseconds, LIKELY).

### 2.6 Prompting the user from R

| Function | Interactive | Non-interactive | Notes | Evidence |
|---|---|---|---|---|
| `readline(prompt)` | reads a line (see 2.1.2) | prints prompt + newline, returns `""` | IRkernel replaces it with `input_request` | VERIFIED |
| `utils::menu(choices, graphics, title)` | numbered menu read by `.Call(C_menu)` from the console | **error** "menu() cannot be used non-interactively" | `graphics = TRUE` uses `select.list()` dialogs on Windows / R.app / Tk | VERIFIED |
| `utils::select.list()` | GUI or text list | **error** "select.list() cannot be used non-interactively" | | VERIFIED |
| `utils::askYesNo(msg, default = TRUE, prompts)` | `readline()` + `pmatch` | **returns `default`** (TRUE) without reading | on Windows RGui the option `askYesNo` is `askYesNoWinDialog` (`utils/R/zzz.R`); RStudio fixed native dialogs from `askYesNo()` opening behind its window on Windows (NEWS 2026.08.0) | VERIFIED |
| `rstudioapi::showQuestion(title, message, ok, cancel, timeout = 60)`, `showPrompt(title, message, default, timeout = 60)` | RStudio modal dialogs | n/a | default **60 s timeout** | VERIFIED (rstudioapi reference) |
| `askpass::askpass(prompt)` / option `askpass` | password prompt; RStudio and Positron install their own handler | | Positron: `set_override("askpass", ...)` in ark `options.R` | VERIFIED (ark source) |
| Claude Agent SDK `canUseTool` | callback receives `(toolName, input, {signal, suggestions})`, returns `{behavior: "allow", updatedInput, updatedPermissions?}` or `{behavior: "deny", message}` | | "The callback never fires for auto-approved tools" | VERIFIED (docs) |

Claude Code AskUserQuestion (Agent SDK "Handle approvals and user input"): input
`{"questions": [{"question", "header" (max 12 characters), "options": [2-4 × {"label", "description",
"preview"?}], "multiSelect"}]}`, 1–4 questions per call; answers returned as `{"questions": [...],
"answers": {"<question text>": "<label>" | ["<label>", ...] | "<free text>"}, "response"?: "<free reply>"}`;
"Display an additional 'Other' choice"; "Use the user's custom text as the answer value (not the word
'Other')"; not available in subagents; `dontAsk` mode denies it; `askUserQuestionTimeout` (60s/5m/10m) can
auto-continue telling Claude the user may be away. VERIFIED.

### 2.7 Non-interactive behaviour (VERIFIED, `$W/f1_*.R`, `$W/f1.out`)

- `Rscript f1_script.R 2>&1` shows progress lines `gptr: run started (...)`, `gptr: tool r: ...
  [allowed: mode auto]`, `gptr: done in 2.1 s, 1.2k tokens` (stderr) and the answer plus a grey footer
  `# complete · fake/model · 2 turns · 1.1k in / 0.1k out tokens · session s-1` (stdout). With `2>/dev/null`
  only the answer and footer remain. `suppressMessages()` silences progress; a front end can intercept
  the classed condition `gptr_progress` with `withCallingHandlers()` and `invokeRestart("muffleMessage")`.
- In knitr: `knitting: logi TRUE`, verbosity 0, no progress lines in the document, and the answer is
  inserted as markdown by a lazily registered `knit_print.gptr_result` (`registerS3method("knit_print",
  "gptr_result", ..., envir = asNamespace("knitr"))`).
- Encoding: the knitted `R²` came out as `R<c2><b2>` under a C locale; gptr must write documents as UTF-8
  explicitly (session store rules from report 02 apply).

---

## 3. Exact specifications

### 3.1 R base behaviour

```text
readline(prompt = "")        interactive: line without leading/trailing blanks; Ctrl-D -> ""
                             non-interactive: Rprintf("%s\n", prompt) (prompt, no space, newline); returns ""
                             prompt keeps at most 255 chars (CONSOLE_PROMPT_SIZE 256)
                             line length: R <= 4.4 + GNU readline: first 4096 bytes kept, rest dropped, NEXT
                             line appended to the result; R >= 4.5 + readline: up to 8190 bytes (source only)
utils::timestamp(stamp, prefix = "", suffix = "", quiet = TRUE)   adds `stamp` to the console history
file("stdin", open = "r") + readLines(con, n = 1L)                 Rscript line reader; character(0) = EOF
utils::menu() / select.list()  error non-interactively
utils::askYesNo(default = TRUE) returns default non-interactively (fails open)
interrupt condition: class c("interrupt", "condition"); restart "resume" present when signalled from
                     computation (onintr), absent during console reads (onintrNoResume)
suspendInterrupts(expr)       defer interrupts during expr
flush.console()               needed on RGui and R.app; harmless elsewhere
```

### 3.2 cli capability functions used by gptr

```text
cli::num_ansi_colors(stream = "auto")   options cli.num_colors, crayon.enabled/colors, cli.default_num_colors;
                                        env R_CLI_NUM_COLORS, NO_COLOR, COLORTERM, RSTUDIO_CONSOLE_COLOR
cli::is_dynamic_tty(stream = "auto")    option cli.dynamic, env R_CLI_DYNAMIC
cli::is_ansi_tty(stream = "auto")       option cli.ansi; Unix only otherwise
cli::is_utf8_output()                   choose "•", "│", "⠋" vs ASCII fallbacks
cli::console_width()                    option cli.width; RStudio console -> getOption("width"); terminal width
cli::ansi_has_hyperlink_support()       option cli.hyperlink, env R_CLI_HYPERLINKS, RStudio, WT_SESSION, iTerm >= 3.1, VTE >= 0.50.1
cli::code_highlight(code)               returns code unchanged if it does not parse or without colours
cli::ansi_strip(x), cli::col_grey(x), cli::style_bold(x), cli::symbol$...
```

### 3.3 Claude Code protected paths (verbatim lists)

Directories: `.git`, `.config/git`, `.vscode`, `.idea`, `.husky`, `.cargo`, `.devcontainer`, `.yarn`,
`.mvn`, `.claude` (except `.claude/worktrees`). Files: `.gitconfig`, `.gitmodules`, `.bashrc`,
`.bash_profile`, `.bash_login`, `.bash_aliases`, `.bash_logout`, `.zshrc`, `.zprofile`, `.zshenv`,
`.zlogin`, `.zlogout`, `.profile`, `.envrc`, `.npmrc`, `.yarnrc`, `.yarnrc.yml`, `.pnp.cjs`,
`.pnp.loader.mjs`, `.pnpmfile.cjs`, `bunfig.toml`, `.bunfig.toml`, `.bazelrc`, `.bazelversion`,
`.bazeliskrc`, `.pre-commit-config.yaml`, `lefthook.yml`, `lefthook.yaml`, `.lefthook.yml`,
`.lefthook.yaml`, `gradle-wrapper.properties`, `maven-wrapper.properties`, `.devcontainer.json`,
`.ripgreprc`, `pyrightconfig.json`, `.mcp.json`, `.claude.json`.

### 3.4 Claude Code AskUserQuestion (verbatim example from the Agent SDK docs)

```json
{
  "questions": [
    {
      "question": "How should I format the output?",
      "header": "Format",
      "options": [
        { "label": "Summary", "description": "Brief overview" },
        { "label": "Detailed", "description": "Full explanation" }
      ],
      "multiSelect": false
    },
    {
      "question": "Which sections should I include?",
      "header": "Sections",
      "options": [
        { "label": "Introduction", "description": "Opening context" },
        { "label": "Conclusion", "description": "Final summary" }
      ],
      "multiSelect": true
    }
  ]
}
```

Answer (TypeScript form): `{ behavior: "allow", updatedInput: { questions: input.questions, answers: {
"How should I format the output?": "Summary", "Which sections should I include?": "Introduction,
Conclusion" } } }`. Limits: 1–4 questions, 2–4 options, `header` max 12 characters.

### 3.5 Codex request_user_input (verbatim Rust)

```rust
pub struct RequestUserInputQuestionOption { pub label: String, pub description: String }
pub struct RequestUserInputQuestion {
    pub id: String, pub header: String, pub question: String,
    #[serde(rename = "isOther", default)] pub is_other: bool,
    #[serde(rename = "isSecret", default)] pub is_secret: bool,
    #[serde(skip_serializing_if = "Option::is_none")] pub options: Option<Vec<RequestUserInputQuestionOption>>,
}
pub struct RequestUserInputArgs { pub questions: Vec<RequestUserInputQuestion>,
    #[serde(rename = "isBlocking")] pub is_blocking: bool, ... }
pub struct RequestUserInputAnswer { pub answers: Vec<String> }
pub struct RequestUserInputResponse { pub answers: HashMap<String, RequestUserInputAnswer> }
```

### 3.6 gptr `ask` tool (proposed, implemented in `$W/c3_ask_tool.R`)

```json
{
  "name": "ask",
  "description": "Ask the user one to four questions and wait for the answers. Use it when a decision materially changes the result (which object, which method, which output format) and you cannot infer the answer from the session or files. Prefer options the user can pick; the user can always type their own answer instead. Do not use it for permission to run code: the harness asks for permission itself.",
  "input_schema": {
    "type": "object", "additionalProperties": false, "required": ["questions"],
    "properties": {
      "questions": {
        "type": "array", "minItems": 1, "maxItems": 4,
        "items": {
          "type": "object", "additionalProperties": false, "required": ["id", "question"],
          "properties": {
            "id":       {"type": "string", "description": "Short stable key for the answer, e.g. 'format'"},
            "header":   {"type": "string", "maxLength": 16, "description": "Very short label, e.g. 'Format'"},
            "question": {"type": "string", "description": "The full question shown to the user"},
            "type":     {"type": "string", "enum": ["single", "multi", "text"],
                         "description": "single = pick one option, multi = pick any number, text = free text"},
            "options":  {"type": "array", "maxItems": 9, "items": {"type": "object", "additionalProperties": false,
                         "required": ["label"], "properties": {"label": {"type": "string"}, "description": {"type": "string"}}}},
            "allow_other": {"type": "boolean", "description": "Let the user type an answer that is not an option (default true)"},
            "default":  {"type": "string", "description": "Label (or text) used if the user just presses Enter"}
          }
        }
      }
    }
  },
  "annotations": {"readOnlyHint": true, "requiresUserInteraction": true},
  "sequential": true
}
```

Validation: unique non-empty `id`s; `single`/`multi` need ≥ 2 options; ≤ 9 options (single-digit console
selection); `type` defaults to `single` when options are given, else `text`.

Result text for the model:

```text
The user answered:
- Format: Plot
- Sections: Residuals, Leverage
- Object: (typed) use a forest plot
```

Cancelled: `The user dismissed the questions without answering. Do not guess silently: either stop and
summarise what you need, or proceed with clearly stated assumptions.` Non-interactive (option
`gptr.ask_noninteractive = "defaults"`, the default): `The user is not available (<reason>). Proceeding with
the defaults: format = Table; name = fit. Continue with your best judgement, state every assumption you
make, and do not ask again.` `details` carries `answers` (named list keyed by `id`; multi = character
vector; typed text has attribute `other = TRUE`) and `cancelled`.

### 3.7 gptr permission rules (proposed grammar, implemented in `$W/c2_permissions.R`)

```text
rule      := tool | tool "(" spec ")"
tool      := "read" | "write" | "edit" | "grep" | "find" | "ls" | "r" | "ask" | "agent" | "shell"
           | "mcp__" server "__" name | "mcp__" server "__*" | "*"
spec      := "*"
           | glob                              ; path tools: gitignore-style, relative to project root,
                                               ; "**" any depth, "*" within a segment, "~/..." home, "//..." absolute
           | "level<=" digit                   ; r: classifier level at most n (0..3)
           | "fn:" name ("," name)*            ; r: flagged functions
           | "category:" cat ("," cat)*        ; r: flagged categories (file_write, file_delete, network, ...)
evaluation: deny rules (any match) > ask rules (any match) > allow rules (session, project, user) > mode
allow r(fn:..)/r(category:..) matches only if EVERY flagged call (level >= 1) is covered;
deny/ask match if ANY flagged call is covered; level-4 (critical) calls are never pre-approved by rules.
plan mode ignores allow rules (a rule can never loosen plan).
```

Settings files (JSON): `<project>/.gptr/settings.json` (shared, may only tighten the mode),
`<project>/.gptr/settings.local.json` (personal "always allow in this project" rules, add to
`.gitignore`), `tools::R_user_dir("gptr", "config")/settings.json` (user). Shape:

```json
{ "permissions": { "mode": "manual",
    "allow": ["write(results/**)", "r(fn:write.csv,saveRDS)", "r(level<=1)"],
    "ask":   ["r(category:network)"],
    "deny":  ["r(fn:install.packages)", "write(data/raw/**)", "edit(.gptr/settings.json)"] } }
```

### 3.8 Risk levels and categories (implemented in `$W/b1_classifier.R`)

| Level | Label | Examples |
|---|---|---|
| 0 | read-only | inspection, printing, plotting to screen, reading files and URLs into memory |
| 1 | local | creates new objects, writes/deletes under `tempfile()`, `library()`, `set.seed()`, `par()`, possibly non-terminating loops (advisory) |
| 2 | mutating | overwrites or modifies existing objects, by-reference mutation (`:=`, `set*()`, environments/R6), `<<-`, `assign(envir = )`, `rm(x)`, writes/moves inside the workspace, `setwd`, `options(x = )`, `Sys.setenv`, network reads/downloads, secret-looking `Sys.getenv`, quoted risky code |
| 3 | dangerous | deletes files, writes outside the workspace or to protected files, processes (`system*`, `processx`, `callr`), package install/remove, dynamic code (`eval`, `source`, computed calls, `.Call`, `Rcpp`, `reticulate`), network sends (POST/bodies), blocking input (`readline`, `browser`) |
| 4 | critical | `q()`/`quit()`/`pskill(Sys.getpid())`, `rm(list = ls())`, deleting the filesystem root, home, project root, `tempdir()` itself, or protected paths |

Path classes: `url`, `wildcard`, `critical` (root, home, project root, `tempdir()` itself, drive root),
`protected` (`.git/`, `.gptr/settings*`, `.Rprofile`, `.Renviron`, `.env*`, `~/.ssh`, `~/.codex`,
`~/.claude`, `~/.aws`, `~/.gnupg`, `.netrc`, `renv.lock`), `workspace`, `temp`, `outside`, `console`,
`unknown` (not a literal). Paths are resolved against the project root with a symlink-safe
normalisation (resolve the deepest existing ancestor; macOS `/var` → `/private/var` broke naive
`normalizePath(mustWork = FALSE)` comparisons in the first test run — VERIFIED and fixed).

### 3.9 Proposed options

| Option | Default | Meaning |
|---|---|---|
| `gptr.mode` | `"manual"` | permission mode for new sessions (`plan`, `manual`, `edits`, `auto`) |
| `gptr.noninteractive_ask` | `"deny"` | what an "ask" becomes when nobody can answer (`"deny"` or `"allow"`) |
| `gptr.critical_guard` | `TRUE` | level-4 actions ask even in `auto` (and are blocked without UI) |
| `gptr.ask_noninteractive` | `"defaults"` | `ask` tool without UI: report defaults, or `"none"` |
| `gptr.ui` | `NULL` | a `gptr_ui` object or a function returning one; replaces console prompts |
| `gptr.verbose` | context dependent | 0 silent, 1 progress on stderr, 2 streamed console output, 3 debug |
| `gptr.interactive` | `NULL` | force the "human present" decision (like `rlang_interactive`) |
| `gptr.history` | `TRUE` | add REPL inputs to the console history via `utils::timestamp()` |
| `gptr.protect_size` | `100e6` | overwriting an object larger than this many bytes counts as dangerous (level 3) |
| `gptr.undo_max_bytes` | `1e9` | keep pre-overwrite snapshots for `/undo` only below this total size |

---

## 4. Recommended design for gptr

### 4.1 Files and functions

| File (R/) | Functions | Exported? |
|---|---|---|
| `console-context.R` | `gptr_context()`, `gptr_verbosity()`, `console_caps()` (wraps cli: colours, dynamic, ansi, utf8, width, hyperlinks, frontend) | no (context is internal; document options) |
| `console-reader.R` | `gptr_reader(con = NULL, echo = !interactive())` → `$read(prompt)`, `$eof()`, `$close()`; `read_logical_input()`; `r_incomplete()` | no |
| `console-render.R` | `md_stream(width, style, out, highlight_r)` → `$write(delta)`, `$finish()`, `$column()`, `$reset_line()`; `wait_indicator()`; `render_tool_call()`, `render_tool_result()` | no |
| `repl.R` | `gptr_repl(session, reader, envir)`; `repl_commands` registry; `expand_mentions()`; `eval_passthrough()` | reached through `gptr()` with no prompt |
| `interrupt.R` | `with_interrupt_policy(expr_fun, agent, reader, mode = c("repl", "call"))`; `resignal_interrupt()` | no |
| `ui.R` | `gptr_ui_console()`, `gptr_ui_none()`, `gptr_ui_scripted()`, `gptr_ui_rstudio()`, `gptr_ui_gadget()`, `gptr_ui_rpc()`; `gptr_current_ui()`; `ui_questions_via()` | export the constructor `gptr_ui()` so front ends can build one |
| `permissions.R` | `tool_risk()`, `permission_check()`, `permission_prompt()`, `gate_tool_call()`, `parse_rule()`, `rule_matches()`, `persist_rule()` | export `gptr_permissions()` (view/add/remove rules) |
| `classify.R` | `gptr_classify(code, envir, root)` (the classifier), risk table data | export `gptr_classify()` (useful and testable by users) |
| `tool-ask.R` | `ask` tool definition, `validate_ask_input()`, `run_ask_tool()` | registered tool |
| `result.R` | `new_gptr_result()`, `print/format/as.character.gptr_result`, `knit_print.gptr_result` (registered in `.onLoad`) | S3 methods |

Use dot-prefixed formals for any exported function that forwards user arguments through `...` (report 05
found a real bug from `id =` partial matching).

### 4.2 `gptr()` with no prompt

```r
gptr <- function(...) {
  # (dispatch per decision register S-1 / D-05; only the no-prompt branch is shown)
  if (no_prompt) {
    ctx <- gptr_context()
    if (!ctx$human && !isTRUE(.stdin)) {
      stop(structure(class = c("gptr_error_noninteractive", "error", "condition"), list(
        message = paste("gptr() without a prompt starts the interactive console and needs a human.",
                        "In scripts pass a prompt: gptr(\"...\"). To drive the console from piped",
                        "input use gptr(.stdin = TRUE)."), call = NULL)))
    }
    reader <- if (isTRUE(.stdin)) gptr_reader(file("stdin", open = "r"), echo = TRUE) else gptr_reader()
    return(invisible(gptr_repl(session, reader, envir = .envir %||% parent.frame())))
  }
  ...
}
```

Never read stdin implicitly when non-interactive: `R CMD check`, CI or a knitr render would block or eat
input. The `.stdin = TRUE` escape hatch is what the tests use (`printf ... | Rscript -e 'gptr::gptr(.stdin = TRUE)'`).

### 4.3 REPL algorithm

```text
gptr_repl(session, reader, envir):
  print banner (model, mode, session id, "/help", "Ctrl-C interrupts; twice at the prompt leaves")
  interrupts <- 0
  repeat:
    prompt <- "gptr> " (or "gptr[plan]> ", "gptr[auto]> "; plus "(n queued)" when follow-ups are queued)
    input <- tryCatch(read_logical_input(reader, prompt), interrupt = <marker>)
    if marker: interrupts += 1; if interrupts >= 2 -> leave; else print hint; next
    if EOF (NA, only for piped input): leave
    interrupts <- 0
    if getOption("gptr.history", TRUE) && interactive(): utils::timestamp(input, prefix = "", suffix = "", quiet = TRUE)
    for each raw readline() line (check inside the reader, before logical-line joining):
      if nchar(line, "bytes") >= 4095 (R < 4.5) or >= 8190 (R >= 4.5): warn "that line was longer than the
      console accepts: its end was dropped and on R < 4.5 the NEXT line you entered was merged into it;
      use @file, /edit or a triple-quote block" and do not send it (ask the user to re-enter)
    dispatch (first match):
      ""               -> next
      "/cmd args"      -> command registry (built-in, then extensions, then /skill:name, then prompt templates)
      "!!code"         -> eval_passthrough(code); do not add to context
      "!code"          -> eval_passthrough(code); add "I ran R code in the session: ```r ...``` Output: ```...```"
                          (deferred until the run ends if a run is active; mirrors Pi's _pendingBashMessages)
      otherwise        -> text <- expand_mentions(input); with_interrupt_policy(session$prompt(text), mode = "repl")
    each iteration wrapped in tryCatch(error = print a one-line error, keep the REPL alive)
  on exit: reader$close(); persist the session; return the session invisibly
```

`read_logical_input()` rules (prototype VERIFIED): `"""` block; ```` ``` ```` fenced R block → `!`;
`!` code continues with `+ ` while `r_incomplete()`; trailing `\` continues with `... `. Optional
(off by default): `gptr.repl_detect_r = TRUE` offers to run an input that parses as R and starts with an
existing object or function name.

`@mentions`: token regex `@("[^"]+"|[A-Za-z0-9_./~-]*[A-Za-z0-9_/~-])`. Resolution order: an existing file
under the project root (or absolute/home path) → `<file path="..." [truncated="true"]>` with the first
`max_lines` lines of a text file (for data files: size, dimensions from the header, first rows; never the
whole file); else an object in `envir` → `<object name class size>` + `str(max.level = 1, list.len = 20)` (use
the session inspector of track 21 when available); else leave the text alone (so e-mail addresses survive).

### 4.4 Slash commands (proposed full list)

Tier 1 (v1):

| Command | Action |
|---|---|
| `/help [cmd]`, `/?` | commands, input syntax, keys |
| `/exit`, `/quit`, `/q` | leave the REPL; return the session invisibly |
| `/model [provider/model]` | show or switch model (REQ-14); `/models` lists the catalog |
| `/thinking [off\|low\|medium\|high]` | reasoning level |
| `/mode [plan\|manual\|edits\|auto]` | show or switch permission mode; `/plan` = `/mode plan` |
| `/permissions [allow\|ask\|deny <rule>] [remove <rule>]` | show and edit rules (session / project / user scope) |
| `/tools [enable\|disable <tool>]` | list tools and their state |
| `/env [pattern]` | objects in the session environment with class and size |
| `/clear` | new conversation, objects kept |
| `/compact [instructions]` | compact context |
| `/cost` (alias `/usage`) | tokens and cost for the session |
| `/context` | context window breakdown |
| `/status` | model, mode, session id, document path, queued messages |
| `/resume [id]`, `/sessions` | switch to a saved session / list sessions |
| `/undo` | revert the last turn: conversation, file edits (from edit backups) and object snapshots (4.8) |
| `/retry` | regenerate the last answer |
| `/save [path.R\|.Rmd\|.qmd\|.ipynb]` | write or relocate the runnable history document (REQ-24) |
| `/queue [text\|clear\|restore]` | queue follow-ups before a run; restore dropped ones |
| `/edit` | compose a long prompt in an editor (`utils::file.edit()` on a temp file; blocking behaviour differs by front end, UNCERTAIN) |
| `/btw <question>` | side question answered without adding to the conversation (Claude Code) |

Tier 2: `/skills`, `/skill:<name>`, `/mcp [status|connect|disconnect]`, `/agents`, `/extensions`,
`/reload`, `/init` (create `.gptr/` and `vignette.Rmd`), `/vignette` (open project instructions),
`/system` (show/edit system prompt), `/export [file]` (transcript), `/copy` (last answer; clipboard needs
Suggests `clipr`), `/fork`, `/tree`, `/name`, `/artifacts`, `/login`, `/logout`, `/keys`, `/debug`.

### 4.5 Rendering and verbosity

- Styled output only when `console_caps()$colors > 1`; `\r` redraws only when `dynamic`; never cursor
  movement unless `ansi` (so RStudio and Windows get the `\r` spinner, terminals may get more later).
- Streamed text: `md_stream()`; tool activity as one line each: `  ● r  fit <- lm(...)  [allowed: mode
  edits]` then `  ⎿ 12 lines of output` (truncated preview, like ellmer's `maybe_echo_tool()`); errors red.
- After the pause menu, call `renderer$reset_line()`: the prototype continued the interrupted line at the
  wrong column (cosmetic, seen in `$W/e2_driver.out`).
- Verbosity (VERIFIED prototype): 0 in knitr/testthat, 1 under Rscript (progress through
  `message(structure(class = c("gptr_progress", "message", "condition"), ...))`), 2 at the console, 3 debug.
- Visibility: if the answer was streamed to the console, return `invisible(result)`; otherwise visible.
- `print.gptr_result`: the text (styled when possible) plus a dim footer (`status · model · turns · tokens ·
  cost · session`); `format()`/`as.character()` give the text; `knit_print` emits markdown via
  `knitr::asis_output()`, registered in `.onLoad` only when knitr is installed.

### 4.6 Interrupt policy

- `with_interrupt_policy(expr_fun, agent, reader, mode)`; `mode = "repl"` → abort returns `"aborted"`;
  `mode = "call"` → abort persists the session, stores the partial result for `gptr_last()`, and re-signals
  the interrupt; `!human` → no menu.
- The menu handler only touches queues and the abort flag; it must never start a nested run.
- Transport: providers stream with `curl` multi handles polled at 50 ms (report 02) and register
  `on.exit(curl::multi_cancel(handle))`; tool code runs inside the same policy so Ctrl-C during a long R
  computation offers the same menu (steer = "deliver after this tool finishes").
- Critical sections (session appends, file edits via temp-file + rename) use `suspendInterrupts()`.

### 4.7 Permission modes and the gate

Decision table (implemented and VERIFIED in `$W/c2_test.R`; "scratch" = evaluate in `new.env(parent =
envir)` and discard at the end of plan mode):

| Tool call | Level | plan | manual | edits | auto |
|---|---|---|---|---|---|
| read inside project | 0 | allow | allow | allow | allow |
| read outside project | 1 | deny | ask | ask | allow |
| read protected/secret file (`~/.ssh/id_rsa`, `.env`) | 2 | deny | ask | ask | allow |
| write/edit inside project | 2 | deny | ask | **allow** | allow |
| write/edit protected file (`.Rprofile`) or outside | 3 | deny | ask | ask | allow |
| R: read-only | 0 | allow | allow | allow | allow |
| R: creates new objects | 1 | **allow (scratch)** | ask | ask | allow |
| R: modifies existing objects / writes workspace files | 2 | deny | ask | ask | allow |
| R: deletes files, runs processes, installs | 3 | deny | ask | ask | allow |
| R: `rm(list = ls())`, `q()` | 4 | deny | ask | ask | **ask** (blocked without UI) |

Additional rules:
- Deny rules apply in every mode; ask rules force a prompt in every mode; allow rules never loosen `plan`
  and never pre-approve level 4.
- Overwriting an object bigger than `gptr.protect_size` is level 3 (the Seurat case: re-loading costs
  minutes). Proposed; not implemented in the prototype, which reports the size but keeps level 2.
- `edits` corresponds to Claude's `acceptEdits`; `auto` corresponds to `bypassPermissions` plus a small
  "critical guard" (Claude's critical paths); there is no classifier *model* in v1. A System 1 (Jev)
  reviewer could be added later as an `approvals_reviewer` equivalent (open question).
- A project's `.gptr/settings.json` may set the mode only if it is stricter than the user's (`plan >
  manual > edits > auto`), because repository content is untrusted (report 05).
- Sub-agents inherit the parent's mode and rules and can only tighten them; worker processes have no
  console: their prompts are forwarded to the parent over the RPC channel (report 06) or fail closed.
- Plan mode: exploratory R runs in a scratch child of `envir` (reads fall through, new bindings vanish);
  `<<-`, `assign(envir =)`, `:=` and environment mutation are level 2 and therefore denied; the model is told
  "Plan mode is read-only: describe this change in your plan instead of performing it." When the model
  finishes a plan, offer "Execute (edits)", "Execute (auto)", "Execute (manual)", "Keep planning"
  (Claude Code pattern).

Prompt (VERIFIED rendering, `$W/c2_test.out` and `$W/e1_run.out`):

```text
gptr wants to use r (risk 2: mutating). Allow?
  │ risk 2 (mutating)
  │   [2] file_write    calls write.csv [path: workspace]
  │   [2] file_write    calls saveRDS [path: workspace]
  │
  │ > write.csv(df, 'results/summary.csv')
  │ > saveRDS(df, 'results/df.rds')
  1: Yes
  2: Yes, and don't ask again this session for r(fn:write.csv,saveRDS)
  3: Yes, and always allow r(fn:write.csv,saveRDS) in this project
  4: No, and tell gptr what to do instead
  5: No
Choose (a number):
```

Semantics: option 2 adds a session rule; option 3 also writes `.gptr/settings.local.json`; option 4 asks
"What should gptr do instead?" and sends that text as the tool result (Claude's "No with comment", Codex's
`Denied { rejection }`); option 5 sends "The user denied this action."; Ctrl-C/Esc returns `abort` and ends
the run (Codex `Abort`). The "remember" options are offered only when the suggested rule covers exactly
what was shown (Claude Code rule) and never for level 4. Non-interactive: an "ask" becomes a block whose
text tells the model the action was NOT performed and how the user can allow it (VERIFIED).

Which tool calls count as mutating: `write`, `edit`, `r` at level ≥ 1, `shell` (always ≥ 3), `agent`
(inherits), MCP tools without `readOnlyHint = TRUE` (server annotations are hints: a tool without
annotations is level 3, `destructiveHint = FALSE` level 2). `read`, `grep`, `find`, `ls` inside the project
and `ask` are read-only.

### 4.8 `/undo` for in-memory objects

Before running level-2 R code, snapshot the objects the classifier says will be overwritten:
`snap <- mget(overwrites, envir = envir)` (no copy thanks to copy-on-modify; VERIFIED +4 MB for a 381 MB
vector), store with the turn, and restore with `list2env(snap, envir)` on `/undo`. Drop snapshots when
their total size exceeds `gptr.undo_max_bytes` or after N turns, because they keep old values alive.
Files are restored from the edit tool's backups; external effects (deleted files, processes, network) cannot
be undone and `/undo` must say so.

### 4.9 UI abstraction

```r
gptr_ui(select, input, questions = NULL, notify = NULL, has_ui = TRUE, kind = "custom")
# select(title, choices, default = NULL, details = NULL, allow_other = FALSE, multiple = FALSE)
#   -> integer index/indices; NA = cancelled; NA with attr(, "other") = free text
# input(prompt, default = "", secret = FALSE) -> character(1) or NA
# questions(qs) -> list(answers = named list, cancelled = lgl)   (default built from select/input)
# notify(text, level = "info")
```

Backends: console (readline or the REPL's piped reader; `tryCatch(interrupt =)` → `NA`), none (fails
closed, carries `reason`), scripted (tests; logs prompts), RStudio (`rstudioapi::showQuestion()` /
`showPrompt()`; remember their 60 s default timeout: pass `timeout = Inf`?, UNCERTAIN whether allowed),
Shiny gadget (a blocking `shiny::runGadget()` per question in the viewer; LIKELY works because the console
is blocked anyway), RPC (child processes send `{"type":"ui_request","id":..,"method":"select",...}` on stdout
and read the reply on stdin; report 05/06). Resolution: explicit argument → `getOption("gptr.ui")` (object
or function) → console when a human is present or in IRkernel → none. A Shiny front end that runs the agent
in-process must not block its own event loop: run the agent in a background R process and implement the UI
over RPC, or pump `httpuv::service()`/`later::run_now()` while waiting (UNCERTAIN).

### 4.10 Package choices

- Imports (already in D-20, whose preliminary list is `httr2`, `jsonlite`, `cli`, `processx`): `cli`
  (capabilities, symbols, colours, `code_highlight`), `jsonlite` (settings, schemas), `processx` (already an
  Import, not a Suggest). No new Imports for the console itself. **Caveat**: the abort pattern in 2.2.3/4.6
  calls `curl::multi_add()`/`multi_run()`/`multi_cancel()` directly; `curl` is not in D-20 (it is only
  present as an `httr2` dependency), so calling it with `curl::` requires declaring `curl` in Imports, or the
  cancel must go through `httr2`'s API instead. The transport choice is open (D-13, track 15).
- Suggests: `rstudioapi` (dialogs, `isAvailable()`), `shiny` (gadget UI), `knitr` (`knit_print`), `askpass`
  (secret input), `clipr` (`/copy`), `httpuv` + `later` (side-channel steering), `withr` (tests),
  `testthat`.
- Do not depend on `rlang` for `is_interactive()`; do not use `askYesNo()`, `menu()` or `select.list()` in
  gptr's own prompts (non-interactive traps, IRkernel incompatibility).

---

## 5. Verified R prototypes

All run with `Rscript --vanilla` (or `R --vanilla --interactive` / a pty via processx) on R 4.4.3, macOS.
Complete sources and outputs: Appendix A. Summary:

| Prototype | Command | Observed |
|---|---|---|
| stdin readers (previous researcher's scripts, re-run) | `printf ... \| Rscript --vanilla a1_stdin.R` etc. | 2.1.3 |
| terminal capabilities | `Rscript --vanilla a2_pty_driver.R` | 2.1.5 table |
| parse quirks | `Rscript --vanilla a3_parse_quirks.R` | 2.5.1 |
| stderr bold (macOS) | `Rscript --vanilla a4_stderr_bold.R \| cat -v` | `^[[1mto-stderr^M ^[[0mto-stdout` |
| history via `timestamp()` | `Rscript --vanilla a5_history_driver.R` | `GOT2: source(...)`, `GOT3: added via timestamp()` |
| base prompt functions non-interactive | `echo y \| Rscript --vanilla a7_prompts.R` | menu error, askYesNo → TRUE/FALSE default, readline "" |
| Ctrl-D in readline | `Rscript --vanilla a8_ctrld_driver.R` | returns "", R alive |
| flushing and cli spinner ticks | `Rscript --vanilla a9_flush_driver.R` | 2.1.7, 2.1.8 |
| 6,000-char line | `Rscript --vanilla a10_long_driver.R` | `nchar=4102` = first 4,096 chars + the next line `second` appended (tail probe re-run); rest of the long line lost (R 4.4.3) |
| risk classifier | `Rscript --vanilla b1_test.R` | 101/101, 3 followed indirections, 4 documented blind spots, file not deleted, 0.33–1.14 s / 1,500 statements (loaded machine) |
| permission gate | `Rscript --vanilla c2_test.R` | decision matrix + 18/18 checks |
| ask tool | `Rscript --vanilla c3_test.R` | 5/5 checks + console rendering |
| streaming renderer | `LANG=en_US.UTF-8 Rscript --vanilla d1_test.R` | chunk-invariant (200 × 2 modes), width respected; in a C locale the width check fails (59 > 40) |
| REPL under Rscript with piped stdin | `Rscript --vanilla e1_run.R < e1_input.txt` | full session incl. prompts answered from the pipe |
| REPL with real SIGINTs | `Rscript --vanilla e2_driver.R` | 7 scenarios pass |
| paste / type-ahead / spinner in pty | `Rscript --vanilla e3_pty_driver.R` | 2.1.4, 2.1.8 |
| Ctrl-C at a permission prompt | `Rscript --vanilla e4_driver.R` | `-> abort`, session alive |
| non-interactive output, knitr | `Rscript --vanilla f1_script.R`; `knitr::knit("f1_doc.Rmd")` | 2.7 |
| HTTP cancel on abort | `Rscript --vanilla g1_driver.R` | 2.2.3 |
| undo snapshot cost | `Rscript --vanilla h1_snapshot.R` | +4 MB for a 381 MB vector; `object.size` 0.0004 s (numeric), 0.114 s (200k-element list) |

Not run: anything on Windows, Linux, RStudio, Positron, VS Code, Jupyter; real LLM providers (no paid calls
were needed; the agent in the REPL is a scripted fake with Pi's queue semantics).

---

## 6. CRAN and cross-platform considerations

- **Never block on input in non-interactive contexts.** `gptr()` without a prompt errors unless a human is
  present or `.stdin = TRUE`; all examples that start the console go in `if (interactive())`; tests use
  `gptr_ui_scripted()` and `gptr_reader(textConnection(...))`.
- **Tests**: drive the REPL with `textConnection()` readers (as in `c2_test.R`, `c3_test.R`); interrupt
  tests that need `processx` and signals must be `skip_on_cran()` and `skip_on_os("windows")` (processx documents that `interrupt()` is "a CTRL+BREAK keypress" on
  Windows, which Rterm treats as an interrupt per rw-FAQ 5.1; whether it reaches R as a resumable
  interrupt was not tested: UNCERTAIN).
- **Files**: "always allow in this project" writes only `.gptr/settings.local.json` after the user chose it;
  history via `utils::timestamp()` changes the user's console history and must be optional
  (`gptr.history`). Nothing is written to the home directory except under `tools::R_user_dir("gptr")`.
- **Output**: use `cat()` for the conversation and `message()` for progress (CRAN prefers
  `message()`/`warning()` over `cat()` for diagnostics; the REPL transcript is the function's purpose, so
  `cat()` there is appropriate). Respect `NO_COLOR` via cli. Do not print ANSI in knitr.
- **Encoding**: use `enc2utf8()` for documents and settings; symbols via `cli::symbol` with ASCII fallback
  when `!cli::is_utf8_output()` (observed: the `·` and braille frames disappear when the reading process
  runs in a C locale).
- **Windows specifics**:
  - Interrupt keys: RGui **Esc** (Ctrl-C copies), Rterm Ctrl-C or Ctrl-Break (rw-FAQ 5.1). The banner
    and help must say "Esc" in RGui and RStudio.
  - The resumable path exists on Windows (`R_ProcessEvents()` → `onintr()`), so the pause menu should work;
    runtime UNCERTAIN.
  - `cli::is_ansi_tty()` is FALSE on Windows: use only `\r` redraws; cli enables VT processing by running
    `cmd /c echo 1 >NUL` when it probes colours (side effect to be aware of).
  - RGui: no colours, output buffered → `flush.console()` after each delta; `askYesNo` uses a native
    dialog (option set in `utils/R/zzz.R`), another reason not to use it.
  - Paths: normalise with `winslash = "/"`; drive roots (`C:/`) are critical paths; case-insensitive
    comparisons for protected patterns on Windows (TODO in the prototype); UNC paths (`\\server\share`)
    should count as `outside` (Claude Code prompts for them because they can leak credentials).
  - `Sys.chmod()` does nothing on Windows; settings files rely on profile ACLs (report 06).
- **Front ends**: RStudio console has no cursor movement; Positron sets cli options; IRkernel has
  `interactive() == FALSE` but a working `readline()` (use `can_prompt`); Jupyter output is not a tty
  (plain rendering unless cli options are set).

---

## 7. Risks, pitfalls, open questions

1. **The classifier is a heuristic.** Blind spots are real (package functions not in the table, load hooks,
   S4, run-time code). It must be framed as "when to ask". Consider shipping the risk table as data that
   packages can extend (`inst/gptr/risk.csv`), and a "risky packages" list (`targets`, `usethis`,
   `devtools`, `renv`, `pak`) whose every function is at least level 2.
2. **Prompt fatigue in `manual`.** Every new object asks. The "don't ask again this session for
   r(level<=1)" option mitigates; measure in usability tests whether `manual` should allow level 1.
3. **4 KB input truncation (R <= 4.4)** silently drops the end of a long line and merges the following
   line into it; long prompts must come through `@file`, `/edit` or `"""` blocks, and the reader should
   refuse (and warn about) any raw line of 4,095+ bytes on R < 4.5 (8,190+ on R >= 4.5). Windows consoles
   and RStudio/Positron limits: UNCERTAIN.
4. **Pasting multi-line prompts** runs each line as a turn in terminal R; users need to learn `"""`. A
   Unix-only mitigation (poll fd 0 with `processx::conn_create_fd(0)` + `processx::poll()` after each line
   to detect pending paste) is UNCERTAIN (GNU readline may already have consumed the bytes).
5. **Paused streams** (menu waiting) may be dropped by providers; "continue" must retry transparently.
6. **Type-ahead echo** garbles the terminal while streaming; acceptable, cannot be fixed portably.
7. **RStudio/Positron/Jupyter/Windows behaviour is inferred from source**, not observed: Esc during
   `readline()`, resumable interrupts, `timestamp()` history, `readline()` inside a calling handler.
   Manual test matrix needed before documenting support.
8. **`rstudioapi::showQuestion()` 60 s timeout** would silently cancel a permission prompt; decide whether
   a timeout means deny (safe) and tell the user.
9. **Shiny front end**: in-process agent + in-process Shiny UI deadlocks unless the agent runs elsewhere or
   the UI pumps the event loop; decide the architecture (report 06 RPC is the likely answer).
10. **Security of settings**: `.gptr/settings.json` in a cloned repository can add allow rules; allow rules
    from project settings should require project trust (report 05) or be ignored until trusted.
11. **Snapshots for `/undo` keep memory alive**; with 5 GB objects this can exhaust RAM. Default the limit
    low and say when a turn cannot be undone.
12. **Open**: should `plan` allow level-1 `library()` (changes the search path)? Should `edits` also
    auto-approve R code that only writes files inside the workspace (level 2 file_write without object
    overwrite)? Should a System 1 (Jev) reviewer (`approvals_reviewer`-like) be offered for `auto`? Should
    `/mode auto` require a confirmation step (Claude Code shows none; Codex warns for `--yolo`)?
13. **Open**: exact `ask` limits (Claude uses 2–4 options and a 12-character header; gptr proposes up to 9
    options and 16 characters for console numbering). Keep aligned with provider tool-schema limits.

---

## 8. Sources

Local (VERIFIED, read directly):
- Pi clone `1b347794`: `packages/coding-agent/docs/usage.md` (29-40, 68-76), `docs/keybindings.md`
  (123-125, 165-166), `docs/slash-commands.md` (7-52), `docs/security.md` (3-7, 75-82),
  `src/modes/interactive/interactive-mode.ts` (3150-3300), `src/core/messages.ts` (27-39, 82-98, 152-161),
  `src/core/agent-session.ts` (3781-3802), `src/core/extensions/types.ts` (114-119, 148-160, 323-331),
  `examples/extensions/permission-gate.ts`, `protected-paths.ts`, `confirm-destructive.ts`,
  `plan-mode/README.md`, `plan-mode/utils.ts` (7-101), `question.ts`, `questionnaire.ts` (51-72, 396-414),
  `qna.ts` (30-37), `timed-confirm.ts` (12-42).
- Installed R packages (printed with `Rscript --vanilla -e 'print(...)'`): `ellmer::live_console`,
  `live_browser`, `ellmer:::check_echo`, `emitter`, `maybe_echo_tool`, `sink_wordwrap_gen`,
  `Chat$chat/on_tool_request`, `tool_reject`, `tool_annotations`; `cli::num_ansi_colors`, `is_dynamic_tty`,
  `is_ansi_tty`, `console_width`, `ansi_has_hyperlink_support`, `cli:::detect_tty_colors`, RStudio caps;
  `rlang::is_interactive`; `utils::askYesNo`, `utils::menu`; `?readline`, `?flush.console`.
- Previous reports: `dev/research/02-pi-agent-loop-sessions.md` (4.7, 4.8, 5.6-5.8),
  `dev/research/05-pi-extensibility.md` (4.6, 5.6, 5.7), `dev/research/00-digest.md`,
  `dev/spec/00-vision-brief.md`, `dev/spec/01-decision-register.md`.

R sources (fetched from the GitHub mirror `wch/r-source`, trunk, 2026-09-29):
- `src/main/errors.c` (`R_CheckUserInterrupt`, `onintrEx`, `onintr`, `onintrNoResume`)
- `src/main/scan.c` (`do_readln`), `src/include/Defn.h` (`CONSOLE_BUFFER_SIZE 4096`)
- `src/unix/sys-std.c` (`handleInterrupt` → `onintrNoResume`), `src/gnuwin32/system.c` (`UserBreak`,
  `R_ReadConsole`)
- `src/library/utils/R/zzz.R`, `src/library/utils/R/windows/winDialog.R` (`askYesNoWinDialog`)

Other source repositories (GitHub API/raw, 2026-09-29/30):
- IRkernel `master` `124f2347`: `R/execution.r` (readline shadowing, 130-146, 271-272), `R/kernel.r` (390),
  `R/options.r`, `inst/kernelspec/kernel.json`.
- posit-dev/ark `main` `c5df06d0`: `crates/ark/src/modules/positron/positron.R`, `options.R`, `cli.R`.
- posit-dev/positron: `extensions/positron-r/resources/scripts/startup.R`
  (https://raw.githubusercontent.com/posit-dev/positron/main/extensions/positron-r/resources/scripts/startup.R).
- openai/codex `main` `2cc65cdd`: `codex-rs/protocol/src/protocol.rs` (AskForApproval,
  GranularApprovalConfig, SandboxPolicy, ReviewDecision), `codex-rs/protocol/src/request_user_input.rs`.
- rstudio/rstudio NEWS-2026.08.0 (askYesNo dialog fix, found via code search).

Web documentation:
- Claude Code permissions: https://code.claude.com/docs/en/permissions
- Claude Code permission modes: https://code.claude.com/docs/en/permission-modes
- Claude Code tools reference (AskUserQuestion behaviour): https://code.claude.com/docs/en/tools-reference
- Claude Agent SDK user input / AskUserQuestion schema: https://code.claude.com/docs/en/agent-sdk/user-input
- Claude Code commands: https://code.claude.com/docs/en/commands
- Claude Code interactive mode: https://code.claude.com/docs/en/interactive-mode
- Codex sandboxing: https://learn.chatgpt.com/docs/sandboxing (redirect from developers.openai.com/codex/concepts/sandboxing)
- Codex approvals and security: https://learn.chatgpt.com/docs/agent-approvals-security
- R for Windows FAQ 5.1: https://cran.r-project.org/bin/windows/base/rw-FAQ.html
- R Installation and Administration, macOS (stderr in bold): https://rstudio.github.io/r-manuals/r-admin/Installing-R-under-macOS.html
- rstudioapi dialogs: https://rstudio.github.io/rstudioapi/reference/showQuestion.html,
  https://rstudio.github.io/rstudioapi/reference/showPrompt.html
- IRkernel stdin issue (historical): https://github.com/IRkernel/IRkernel/issues/199
- R chat packages (not read in depth): https://cran.r-project.org/package=chattr,
  https://github.com/JBGruber/askgpt, https://www.infoworld.com/article/2338386/8-chatgpt-tools-for-r-programming.html

---

## Appendix A. Prototype sources and captured outputs

Generated verbatim from the files in `$W` after the final runs. Each listing is the exact file that
produced the output shown after it.

### A.1 Risk classifier

**Source** (`b1_classifier.R`)

````r
# gptr prototype: static, advisory risk classifier for R code (track 18).
# NEVER evaluates the code it classifies. It is a heuristic for permission prompts,
# not a security boundary: see the README section "What the classifier cannot see".
#
# Public entry point: classify_r_code(code, envir = NULL, root = getwd(), depth = 2L)
#   code  : character (one or more lines) or an expression / call
#   envir : optional environment the code WOULD run in; enables overwrite detection and
#           classification of user-defined functions found there (read-only lookups only)
#   root  : project root (workspace) used for path analysis
# Returns an object of class "gptr_risk":
#   list(level = 0..4, label, flags = data.frame(level, category, fn, detail),
#        assigns, overwrites, calls, parse_error)

`%||%` <- function(a, b) if (is.null(a)) b else a

RISK_LABELS <- c("read-only", "local", "mutating", "dangerous", "critical")

# ---------------------------------------------------------------------------
# Function table: name -> category, level, and which argument carries a path.
# pkg = NA means "any package / base".
# ---------------------------------------------------------------------------
.rt <- function(fns, category, level, path_arg = NA_character_, pkg = NA_character_)
  data.frame(fn = fns, pkg = pkg, category = category, level = level, path_arg = path_arg,
             stringsAsFactors = FALSE)

RISK_TABLE <- rbind(
  .rt(c("q", "quit"), "quit", 4L),
  .rt("pskill", "quit", 4L, pkg = "tools"),
  .rt(c("unlink", "file.remove"), "file_delete", 3L, "x"),
  .rt(c("file_delete", "dir_delete", "link_delete"), "file_delete", 3L, "path", pkg = "fs"),
  .rt("file.rename", "file_move", 2L, "from"),
  .rt(c("file_move"), "file_move", 2L, "path", pkg = "fs"),
  .rt(c("writeLines"), "file_write", 2L, "con"),
  .rt(c("write", "write.csv", "write.csv2", "write.table"), "file_write", 2L, "file"),
  .rt(c("saveRDS", "save", "save.image", "dput", "dump", "capture.output"), "file_write", 2L, "file"),
  .rt(c("cat"), "file_write", 2L, "file"),       # only when file= is supplied (see special case)
  .rt(c("file.create", "dir.create", "file.append", "file.symlink", "file.link", "Sys.chmod",
        "Sys.setFileTime", "Sys.umask", "writeBin", "writeChar", "sink", "zip", "unzip", "untar", "tar"),
      "file_write", 2L, "file"),
  .rt("file.copy", "file_write", 2L, "to"),
  .rt(c("fwrite"), "file_write", 2L, "file", pkg = "data.table"),
  .rt(c("write_csv", "write_tsv", "write_delim", "write_rds", "write_lines", "write_file"),
      "file_write", 2L, "file", pkg = "readr"),
  .rt(c("write_parquet", "write_feather", "write_dataset", "write_csv_arrow", "write_ipc_file"),
      "file_write", 2L, "sink", pkg = "arrow"),
  .rt("vroom_write", "file_write", 2L, "file", pkg = "vroom"),
  .rt(c("write_json"), "file_write", 2L, "path", pkg = "jsonlite"),
  .rt(c("write_yaml"), "file_write", 2L, "file", pkg = "yaml"),
  .rt("ggsave", "file_write", 2L, "filename", pkg = "ggplot2"),
  .rt(c("pdf", "png", "jpeg", "bmp", "tiff", "svg", "cairo_pdf", "cairo_ps", "postscript"),
      "file_write", 2L, "filename"),
  .rt(c("file_create", "file_copy", "dir_create", "file_touch", "file_chmod", "link_create"),
      "file_write", 2L, "path", pkg = "fs"),
  .rt(c("render"), "file_write", 3L, NA, pkg = "rmarkdown"),       # executes code + writes
  .rt(c("knit", "purl"), "file_write", 3L, NA, pkg = "knitr"),
  .rt(c("system", "system2", "shell", "shell.exec", "pipe"), "process", 3L),
  .rt(c("run", "process", "r_process", "run_process"), "process", 3L, pkg = "processx"),
  .rt(c("r", "r_bg", "rscript", "r_session", "r_vanilla", "rcmd", "rcmd_bg"), "process", 3L, pkg = "callr"),
  .rt(c("mcparallel", "mclapply", "makeCluster", "makePSOCKcluster", "makeForkCluster"), "process", 2L),
  .rt(c("browseURL"), "process", 2L),
  .rt(c("install.packages", "remove.packages", "update.packages"), "package", 3L),
  .rt(c("install_github", "install_cran", "install_local", "install_url", "install_git", "install_version"),
      "package", 3L, pkg = "remotes"),
  .rt(c("install", "install_github", "install_dev", "install_local"), "package", 3L, pkg = "devtools"),
  .rt(c("pkg_install", "pak", "pkg_remove", "local_install"), "package", 3L, pkg = "pak"),
  .rt(c("install"), "package", 3L, pkg = "BiocManager"),
  .rt(c("install", "restore", "update", "remove"), "package", 3L, pkg = "renv"),
  .rt(c("download.file"), "network", 2L, "destfile"),
  .rt(c("url", "socketConnection", "socketAccept", "make.socket"), "network", 2L),
  .rt(c("curl", "curl_download", "curl_fetch_memory", "curl_fetch_disk", "curl_fetch_stream",
        "multi_run"), "network", 2L, pkg = "curl"),
  .rt(c("GET", "HEAD"), "network", 2L, pkg = "httr"),
  .rt(c("POST", "PUT", "PATCH", "DELETE", "VERB"), "network_send", 3L, pkg = "httr"),
  .rt(c("req_perform", "req_perform_stream", "req_perform_connection", "req_perform_parallel",
        "req_perform_sequential"), "network", 2L, pkg = "httr2"),
  .rt(c("req_body_json", "req_body_raw", "req_body_form", "req_body_multipart", "req_body_file"),
      "network_send", 3L, pkg = "httr2"),
  .rt(c("setwd", "Sys.setenv", "Sys.unsetenv", "Sys.setlocale", "options", ".libPaths",
        "attach", "detach", "unloadNamespace", "trace", "untrace", "setHook", "addTaskCallback",
        "reg.finalizer", "Sys.setLanguage"), "session", 2L),
  .rt(c("library", "require", "requireNamespace", "loadNamespace", "set.seed", "par",
        "dev.off", "graphics.off", "dev.new", "suppressPackageStartupMessages"), "session_light", 1L),
  .rt(c("rm", "remove"), "object_delete", 2L),
  .rt(c("assign", "<<-", "delayedAssign", "makeActiveBinding", "environment<-", "body<-",
        "formals<-", "lockBinding", "lockEnvironment"), "env_mutation", 2L),
  .rt(c("assignInNamespace", "assignInMyNamespace", "unlockBinding", "fixInNamespace"),
      "env_mutation", 3L),
  .rt(c(":=", "set", "setnames", "setattr", "setkey", "setkeyv", "setorder", "setorderv", "setDT",
        "setDF", "setcolorder", "setindex", "setindexv", "alloc.col"), "by_reference", 2L),
  .rt(c("eval", "evalq", "eval.parent", "source", "sys.source", "Recall", ".Internal", ".Primitive",
        ".Call", ".External", ".External2", ".C", ".Fortran", "dyn.load", "library.dynam",
        "do.call", "match.fun", "get", "get0", "mget", "getExportedValue", "getFromNamespace",
        "exec", "invoke", "eval_tidy", "eval_bare", "inject"), "dynamic", 3L),
  .rt(c("sourceCpp", "cppFunction", "evalCpp"), "dynamic", 3L, pkg = "Rcpp"),
  .rt(c("py_run_string", "py_run_file", "source_python", "py_eval"), "dynamic", 3L, pkg = "reticulate"),
  .rt(c("Sys.getenv", "readRenviron", "key_get", "key_get_raw", "askpass", "getPass"), "secrets", 2L),
  .rt(c("readline", "menu", "browser", "debug", "debugonce", "readLines_stdin", "scan_stdin",
        "file.edit", "edit", "fix", "select.list", "askYesNo"), "blocking", 3L)
)

# Functions whose argument(s) are FUNCTIONS: which argument (name or position) holds it.
HOF_ARGS <- list(
  do.call = c("what", "1"), exec = c(".fn", "1"), invoke = c(".f", "1"), match.fun = c("FUN", "1"),
  lapply = c("FUN", "2"), sapply = c("FUN", "2"), vapply = c("FUN", "2"), mapply = c("FUN", "1"),
  Map = c("f", "1"), Reduce = c("f", "1"), Filter = c("f", "1"), Find = c("f", "1"),
  Position = c("f", "1"), apply = c("FUN", "3"), tapply = c("FUN", "3"), outer = c("FUN", "3"),
  rapply = c("f", "2"), Vectorize = c("FUN", "1"), Negate = c("f", "1"), Recall = c("", ""),
  map = c(".f", "2"), map2 = c(".f", "3"), pmap = c(".f", "2"), walk = c(".f", "2"),
  walk2 = c(".f", "3"), pwalk = c(".f", "2"), imap = c(".f", "2"), iwalk = c(".f", "2"),
  map_chr = c(".f", "2"), map_lgl = c(".f", "2"), map_dbl = c(".f", "2"), map_int = c(".f", "2"),
  future_lapply = c("FUN", "2"), future_map = c(".f", "2"), mclapply = c("FUN", "2"),
  parLapply = c("fun", "3"), parSapply = c("FUN", "3"), clusterCall = c("fun", "2"),
  on.exit = c("", ""), tryCatch = c("", ""), later = c("func", "1")
)
# Functions whose first argument is a function NAME given as a string (get("system")).
NAME_ARG_FUNS <- c("get", "get0", "match.fun", "getExportedValue", "getFromNamespace", "do.call",
                   "exec", "invoke", "mget")
# Direct symbol arguments of these calls are data (NSE), not function values.
NSE_FUNS <- c("aes", "aes_", "vars", "filter", "mutate", "transmute", "select", "arrange", "group_by",
              "summarise", "summarize", "count", "distinct", "rename", "relocate", "pull", "with",
              "within", "subset", "transform", "$", "@", "[", "[[", "~", "quote", "bquote",
              "substitute", "expression", "alist", "list", "c", "data.frame", "tibble", "data.table",
              "facet_wrap", "facet_grid", "slice", "across", "if_else", "case_when", "ifelse",
              "print", "str", "summary", "head", "tail", "nrow", "ncol", "length", "names",
              "class", "typeof", "is.null", "identical", "exists")
# Symbols that are also very common column / variable names: only flag them as call heads,
# in a known function slot, or on the right-hand side of an alias assignment (f <- q).
COLLISION_PRONE <- c("q", "run", "shell", "rm", "write", "save", "url", "options", "source",
                     "library", "require", "get", "eval", "set", "exec", "invoke", "render",
                     "install", "restore", "update", "remove", "edit", "fix", "par", "pipe", "process",
                     "curl", "r", "debug", "cat", "menu", "pdf", "png", "svg")
QUOTING_FUNS <- c("quote", "bquote", "expression", "substitute", "~", "alist")
PROTECTED_PATTERNS <- c("(^|/)\\.git(/|$)", "(^|/)\\.gptr/settings[^/]*$", "(^|/)\\.Rprofile$",
                        "(^|/)\\.Renviron$", "(^|/)\\.env([.][^/]*)?$", "(^|/)\\.ssh(/|$)",
                        "(^|/)\\.codex(/|$)", "(^|/)\\.claude(/|$)", "(^|/)\\.aws(/|$)",
                        "(^|/)\\.gnupg(/|$)", "(^|/)\\.netrc$", "(^|/)renv\\.lock$")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RISK_INDEX <- new.env(hash = TRUE, parent = emptyenv())
for (.i in seq_len(nrow(RISK_TABLE))) {
  .e <- as.list(RISK_TABLE[.i, ])
  assign(.e$fn, c(get0(.e$fn, envir = RISK_INDEX, inherits = FALSE), list(.e)), envir = RISK_INDEX)
}
rm(.i, .e)

# Returns NULL or one table entry (a list). Qualified names (pkg::fn) prefer an exact package
# match; entries without a package match any package (conservative).
lookup_fn <- function(name, pkg = NA_character_) {
  bare <- sub("^.*:::?", "", name)                       # `base::unlink` as ONE backticked symbol
  if (grepl(":::?", name) && is.na(pkg)) pkg <- sub(":::?.*$", "", name)
  if (!nzchar(bare)) return(NULL)
  hits <- get0(bare, envir = RISK_INDEX, inherits = FALSE)
  if (is.null(hits)) return(NULL)
  pk <- vapply(hits, function(h) h$pkg, "")
  if (!is.na(pkg)) {
    if (any(!is.na(pk) & pk == pkg)) return(hits[[which(!is.na(pk) & pk == pkg)[1L]]])
    if (any(is.na(pk))) return(hits[[which(is.na(pk))[1L]]])
    return(NULL)                                            # e.g. dplyr::filter: not in the table
  }
  if (any(is.na(pk))) hits[[which(is.na(pk))[1L]]] else hits[[1L]]
}

str_or_sym <- function(x) {
  if (is.character(x) && length(x) == 1L) return(x)
  if (is.symbol(x)) return(as.character(x))
  NULL
}

# Resolve a call head to list(name, pkg, how). how: direct | ns | lambda | indirect | method$m | computed
resolve_head <- function(h) {
  if (is.symbol(h)) return(list(name = as.character(h), pkg = NA_character_, how = "direct"))
  if (is.character(h) && length(h) == 1L) return(list(name = h, pkg = NA_character_, how = "direct"))
  if (is.call(h)) {
    hh <- h[[1L]]
    hn <- if (is.symbol(hh)) as.character(hh) else ""
    if (hn %in% c("::", ":::") && length(h) == 3L) {
      pkg <- str_or_sym(h[[2L]]); fn <- str_or_sym(h[[3L]])
      if (!is.null(pkg) && !is.null(fn)) return(list(name = fn, pkg = pkg, how = "ns"))
    }
    if (hn == "(" && length(h) == 2L) return(resolve_head(h[[2L]]))
    if (hn == "function") return(list(name = "<lambda>", pkg = NA_character_, how = "lambda"))
    fr <- fun_ref(h)                                   # get("system")(...), match.fun("x")(...)
    if (!is.null(fr)) return(fr)
    if (hn == "$" && length(h) == 3L) {                # processx::process$new(...), obj$method()
      obj <- resolve_head(h[[2L]]); meth <- str_or_sym(h[[3L]]) %||% "?"
      return(list(name = obj$name, pkg = obj$pkg, how = paste0("method$", meth)))
    }
  }
  list(name = "<computed>", pkg = NA_character_, how = "computed")
}

# A static reference to a function VALUE: unlink, base::unlink, get("unlink"), get0("unlink"),
# match.fun("unlink"), getExportedValue("base", "unlink"), getFromNamespace("unlink", "base").
# Returns NULL when the reference is not static.
fun_ref <- function(x) {
  if (is.symbol(x) || (is.character(x) && length(x) == 1L)) return(resolve_head(x))
  if (!is.call(x)) return(NULL)
  h0 <- x[[1L]]
  if (is.symbol(h0) && as.character(h0) %in% c("::", ":::")) return(resolve_head(x))
  h <- if (is.symbol(h0)) as.character(h0)
       else if (is.call(h0) && is.symbol(h0[[1L]]) && as.character(h0[[1L]]) %in% c("::", ":::") &&
                length(h0) == 3L) str_or_sym(h0[[3L]]) %||% ""
       else ""
  a <- as.list(x)[-1L]
  if (h %in% c("get", "get0", "match.fun") && length(a) && is.character(a[[1L]]))
    return(list(name = a[[1L]], pkg = NA_character_, how = "indirect"))
  if (h == "getExportedValue" && length(a) >= 2L && is.character(a[[2L]]))
    return(list(name = a[[2L]], pkg = str_or_sym(a[[1L]]) %||% NA_character_, how = "indirect"))
  if (h == "getFromNamespace" && length(a) >= 1L && is.character(a[[1L]]))
    return(list(name = a[[1L]], pkg = if (length(a) >= 2L) str_or_sym(a[[2L]]) %||% NA_character_
                                      else NA_character_, how = "indirect"))
  NULL
}

# normalizePath() only resolves symlinks for paths that exist (macOS: /var -> /private/var), so
# resolve the deepest existing ancestor and re-append the rest.
norm_path <- function(p) {
  p <- path.expand(p); rest <- character()
  while (!file.exists(p) && dirname(p) != p) { rest <- c(basename(p), rest); p <- dirname(p) }
  out <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (length(rest)) out <- paste(c(sub("/$", "", out), rest), collapse = "/")
  out
}

classify_path <- function(p, root) {
  if (grepl("^(https?|ftps?|s3|gs)://", p, ignore.case = TRUE)) return("url")
  if (grepl("[*?]", p)) return("wildcard")
  home <- norm_path("~")
  pp <- path.expand(p)
  abs <- if (grepl("^([A-Za-z]:)?[/\\\\]", pp)) pp else file.path(root, pp)
  abs <- sub("/[.]$", "", norm_path(abs))
  rootn <- norm_path(root)
  tmp <- norm_path(tempdir())
  if (abs %in% c("/", home, rootn) || grepl("^[A-Za-z]:/?$", abs)) return("critical")
  if (any(vapply(PROTECTED_PATTERNS, grepl, logical(1), x = abs))) return("protected")
  if (abs == tmp) return("critical")                  # R's own session temp dir
  if (startsWith(abs, paste0(rootn, "/"))) return("workspace")
  if (startsWith(abs, paste0(tmp, "/"))) return("temp")
  "outside"
}

# Extract the path-like argument of a call: literal string -> classify; tempfile()/tempdir()-based
# -> "temp"; anything else -> "unknown".
path_arg_class <- function(call, entry, root) {
  args <- as.list(call)[-1L]
  if (!length(args)) return(NA_character_)
  nms <- names(args) %||% rep("", length(args))
  pa <- entry$path_arg
  val <- NULL
  if (!is.na(pa) && pa %in% nms) val <- args[[match(pa, nms)]]
  else {
    unnamed <- args[nms == ""]
    pos <- if (!is.na(pa) && pa %in% c("con", "file", "filename") && entry$fn %in%
               c("writeLines", "write", "write.csv", "write.csv2", "write.table", "saveRDS",
                 "save", "dput", "dump", "fwrite", "write_csv", "write_tsv", "write_rds",
                 "vroom_write", "write_json", "write_yaml", "writeBin", "writeChar"))
      2L else if (!is.na(pa) && pa %in% c("to", "destfile")) 2L else 1L
    if (entry$fn == "save") return(if ("file" %in% nms) path_arg_class_val(args[["file"]], root) else "unknown")
    if (length(unnamed) >= pos) val <- unnamed[[pos]]
  }
  if (is.null(val)) {
    # argument omitted: some defaults write to the console, some to a default file in getwd()
    if (entry$fn %in% c("writeLines", "cat", "dput", "capture.output", "sink")) return("console")
    if (entry$fn %in% c("png", "pdf", "jpeg", "bmp", "tiff", "svg", "dump", "save.image")) return("workspace")
    return(NA_character_)
  }
  path_arg_class_val(val, root)
}
path_arg_class_val <- function(val, root) {
  if (is.character(val) && length(val) == 1L) return(classify_path(val, root))
  if (is.call(val)) {
    fn <- resolve_head(val[[1L]])$name
    if (fn %in% c("tempfile", "tempdir")) return(if (fn == "tempdir") "critical" else "temp")
    if (fn %in% c("file.path", "paste0", "paste") && length(val) >= 2L && is.call(val[[2L]]) &&
        resolve_head(val[[2L]][[1L]])$name %in% c("tempdir", "tempfile")) return("temp")
    if (fn %in% c("stdout", "stderr")) return("console")
  }
  "unknown"
}

path_level <- function(category, base_level, pclass) {
  if (is.na(pclass)) return(base_level)
  if (category == "file_delete") {
    return(switch(pclass, critical = 4L, protected = 4L, outside = 3L, wildcard = 3L, unknown = 3L,
                  workspace = 3L, temp = 1L, url = 3L, 3L))
  }
  if (category %in% c("file_write", "file_move")) {
    return(switch(pclass, critical = 4L, protected = 3L, outside = 3L, wildcard = 3L,
                  unknown = base_level, workspace = 2L, temp = 1L, console = 0L, url = 3L, base_level))
  }
  base_level
}

is_literal_text_parse <- function(call) {
  # parse(text = "..."), str2lang("..."), str2expression("...") with a literal string
  fn <- resolve_head(call[[1L]])$name
  if (!fn %in% c("parse", "str2lang", "str2expression")) return(NULL)
  args <- as.list(call)[-1L]; nms <- names(args) %||% rep("", length(args))
  txt <- if (fn == "parse") (if ("text" %in% nms) args[["text"]] else NULL) else if (length(args)) args[[1L]] else NULL
  if (is.character(txt)) paste(txt, collapse = "\n") else if (is.null(txt)) NULL else NA_character_
}

# ---------------------------------------------------------------------------
# The walker
# ---------------------------------------------------------------------------
classify_r_code <- function(code, envir = NULL, root = getwd(), depth = 2L, .seen = character()) {
  flags <- list(); assigns <- character(); overwrites <- character(); calls <- character()
  env_names <- NULL; seen_user <- character()
  add_flag <- function(level, category, fn, detail) {
    flags[[length(flags) + 1L]] <<- data.frame(level = as.integer(level), category = category,
                                                fn = fn, detail = detail, stringsAsFactors = FALSE)
  }
  exprs <- if (is.character(code)) {
    tryCatch(parse(text = code, keep.source = FALSE), error = function(e) e)
  } else if (is.expression(code)) code else as.expression(list(code))
  if (inherits(exprs, "error")) {
    return(structure(list(level = 0L, label = "invalid", flags = NULL, assigns = character(),
                          overwrites = character(), calls = character(),
                          parse_error = conditionMessage(exprs)), class = "gptr_risk"))
  }

  flag_fn <- function(name, pkg, how, call, ctx) {
    entry <- lookup_fn(name, pkg)
    if (is.null(entry)) return(invisible())
    if (entry$fn == "cat" && !"file" %in% names(as.list(call))) return(invisible())
    if (entry$fn == "options" && !is.null(call)) {         # options("digits") is a query
      a <- as.list(call)[-1L]; n <- names(a) %||% rep("", length(a))
      if (all(n == "")) return(invisible())
    }
    if (entry$fn == "Sys.getenv" && !is.null(call)) {       # only secret-looking names or dump-all
      a <- as.list(call)[-1L]
      if (length(a) && is.character(a[[1L]]) &&
          !any(grepl("KEY|TOKEN|SECRET|PASS|AUTH|CRED|PAT", toupper(a[[1L]])))) return(invisible())
    }
    if (entry$fn == "rm" && !is.null(call)) {
      a <- as.list(call)[-1L]; n <- names(a) %||% rep("", length(a))
      if ("list" %in% n && is.call(a[["list"]]) && identical(resolve_head(a[["list"]][[1L]])$name, "ls")) {
        add_flag(4L, "object_delete", "rm", "rm(list = ls()) deletes every object in the environment")
        return(invisible())
      }
    }
    lvl <- entry$level; detail <- paste0("calls ", if (!is.na(pkg)) paste0(pkg, "::") else "", name)
    if (how == "indirect") detail <- paste0(detail, " (resolved from a string/indirect reference)")
    if (how == "hof") detail <- paste0(detail, " (passed as a function value)")
    if (how == "alias") detail <- paste0(detail, " (aliased to another name)")
    if (startsWith(how, "method$")) detail <- paste0(detail, " (", sub("method", "", how), " method)")
    if (!is.null(call) && !is.na(entry$path_arg) && how %in% c("direct", "ns", "indirect")) {
      pc <- path_arg_class(call, entry, root)
      lvl <- path_level(entry$category, lvl, pc)
      if (!is.na(pc)) detail <- paste0(detail, " [path: ", pc, "]")
    }
    if (entry$category == "dynamic" && name %in% c("get", "get0", "mget", "getExportedValue",
                                                     "getFromNamespace")) {
      # a lookup by name is harmless unless the result is called; a literal target is resolved
      # by resolve_head()/fun_ref(), a computed one is only advisory here
      a <- if (!is.null(call)) as.list(call)[-1L] else list()
      tgt <- if (length(a)) a[[1L]] else NULL
      if (is.null(call) || is.character(tgt)) return(invisible())
      add_flag(1L, "dynamic", name, paste0("looks up an object by a computed name (", name, ")"))
      return(invisible())
    }
    if (entry$category == "dynamic" && name %in% c("match.fun", "do.call", "exec", "invoke")) {
      a <- if (!is.null(call)) as.list(call)[-1L] else list()
      nm <- names(a) %||% rep("", length(a))
      slot <- match(c("what", ".fn", ".f", "FUN"), nm); slot <- slot[!is.na(slot)]
      tgt <- if (length(slot)) a[[slot[1L]]] else if (length(a)) a[[which(nm == "")[1L]]] else NULL
      if (is.null(call) || is.character(tgt)) return(invisible())   # literal: resolved elsewhere
      if (is.call(tgt) && !is.null(fun_ref(tgt))) return(invisible())
      if (is.call(tgt) && identical(tgt[[1L]], as.name("function"))) return(invisible())
      if (is.symbol(tgt)) {
        s <- as.character(tgt)
        # a symbol that names a function is resolved; a symbol holding a *string*
        # (x <- "unlink"; do.call(x, ...)) or an unknown variable is not
        if (!is.null(lookup_fn(s)) ||
            exists(s, envir = envir %||% globalenv(), mode = "function", inherits = TRUE))
          return(invisible())
        detail <- paste0(detail, " with the function chosen by variable `", s, "`")
      } else {
        detail <- paste0(detail, " with a computed target: the called function cannot be determined")
      }
      add_flag(3L, "dynamic", name, detail)
      return(invisible())
    }
    if (entry$category == "dynamic" && name %in% c("source", "sys.source") && !is.null(call)) {
      a <- as.list(call)[-1L]
      if (length(a) && is.character(a[[1L]])) {
        pc <- classify_path(a[[1L]], root)
        if (pc == "url") { lvl <- 3L; detail <- paste0(detail, " [downloads and runs remote code]") }
        else if (depth > 0L && file.exists(file.path(root, a[[1L]])) &&
                 file.size(file.path(root, a[[1L]])) < 1e6 && !a[[1L]] %in% .seen) {
          sub <- classify_r_code(readLines(file.path(root, a[[1L]]), warn = FALSE), envir, root,
                                 depth - 1L, c(.seen, a[[1L]]))
          lvl <- max(1L, sub$level)
          detail <- paste0(detail, " [file classified: ", RISK_LABELS[sub$level + 1L], "]")
          if (!is.null(sub$flags)) for (i in seq_len(nrow(sub$flags)))
            add_flag(sub$flags$level[i], sub$flags$category[i], sub$flags$fn[i],
                     paste0("in ", a[[1L]], ": ", sub$flags$detail[i]))
        }
      }
    }
    if (ctx$in_def) detail <- paste0(detail, " (inside a function definition)")
    if (ctx$in_quote) { detail <- paste0(detail, " (inside quoted code)"); lvl <- min(lvl, 2L) }
    if (lvl <= 0L) return(invisible())                   # e.g. writeLines() to the console
    add_flag(lvl, entry$category, name, detail)
  }

  # classify the body of a user-defined closure found in envir (read-only lookup)
  flag_user_fun <- function(name, ctx) {
    if (is.null(envir) || depth <= 0L || !nzchar(name) || name %in% .seen || name %in% seen_user) return(invisible())
    seen_user <<- c(seen_user, name)
    f <- get0(name, envir = envir, mode = "function", inherits = TRUE)
    if (is.null(f) || is.primitive(f)) return(invisible())
    fe <- environment(f)
    if (isNamespace(topenv(fe))) return(invisible())          # package function: trust the table
    sub <- classify_r_code(as.expression(list(body(f))), envir, root, depth - 1L, c(.seen, name))
    if (!is.null(sub$flags)) for (i in seq_len(nrow(sub$flags)))
      add_flag(sub$flags$level[i], sub$flags$category[i], sub$flags$fn[i],
               paste0("via user function ", name, "(): ", sub$flags$detail[i]))
  }

  # obj$method(): if obj is an environment in envir (R6, reference class, closure env) that holds
  # a user-written function `method`, classify that function's body
  flag_env_method <- function(objname, meth, ctx) {
    if (is.null(envir) || depth <= 0L || !nzchar(objname)) return(invisible())
    obj <- get0(objname, envir = envir, inherits = TRUE)
    if (!is.environment(obj)) return(invisible())
    f <- get0(meth, envir = obj, mode = "function", inherits = FALSE)
    if (is.null(f) || is.primitive(f) || isNamespace(topenv(environment(f)))) return(invisible())
    key <- paste0(objname, "$", meth)
    if (key %in% .seen) return(invisible())
    sub <- classify_r_code(as.expression(list(body(f))), envir, root, depth - 1L, c(.seen, key))
    if (!is.null(sub$flags)) for (i in seq_len(nrow(sub$flags)))
      add_flag(sub$flags$level[i], sub$flags$category[i], sub$flags$fn[i],
               paste0("via method ", key, "(): ", sub$flags$detail[i]))
  }
  # generic(x): user-defined S3 methods generic.* living in envir might be dispatched to
  flag_user_s3_methods <- function(gen, ctx) {
    if (is.null(envir) || depth <= 0L || !grepl("^[A-Za-z.][A-Za-z0-9._]*$", gen)) return(invisible())
    if (is.null(env_names)) env_names <<- ls(envir, all.names = TRUE)
    cand <- env_names[startsWith(env_names, paste0(gen, "."))]
    for (m in setdiff(cand, .seen)) {
      f <- get0(m, envir = envir, mode = "function", inherits = FALSE)
      if (is.null(f)) next
      sub <- classify_r_code(as.expression(list(body(f))), envir, root, depth - 1L, c(.seen, m))
      if (!is.null(sub$flags)) for (i in seq_len(nrow(sub$flags)))
        add_flag(sub$flags$level[i], sub$flags$category[i], sub$flags$fn[i],
                 paste0("via S3 method ", m, "() that ", gen, "() may dispatch to: ", sub$flags$detail[i]))
    }
  }

  note_assign <- function(target, op, ctx) {
    if (ctx$in_def || ctx$in_quote) return(invisible())
    root_sym <- target
    complex <- FALSE
    while (is.call(root_sym) && length(root_sym) >= 2L) {
      h <- resolve_head(root_sym[[1L]])$name
      if (h %in% c("environment", "globalenv", "parent.frame", "parent.env", "asNamespace",
                   "as.environment", "baseenv", "topenv", "sys.frame", "get", "get0", "emptyenv")) {
        add_flag(2L, "env_mutation", op, paste0("assigns into an environment obtained from ", h, "()"))
        return(invisible())
      }
      root_sym <- root_sym[[2L]]; complex <- TRUE
    }
    nm <- str_or_sym(root_sym)
    if (is.null(nm)) return(invisible())
    assigns[[length(assigns) + 1L]] <<- nm
    if (op == "<<-") { add_flag(2L, "env_mutation", "<<-", paste0("super-assignment to ", nm)); return(invisible()) }
    if (nm %in% c(".GlobalEnv", "globalenv")) { add_flag(2L, "env_mutation", op, "assigns into the global environment"); return(invisible()) }
    if (!is.null(envir)) {
      if (exists(nm, envir = envir, inherits = FALSE)) {
        obj <- get(nm, envir = envir, inherits = FALSE)
        overwrites <<- c(overwrites, nm)
        sz <- tryCatch(format(utils::object.size(obj), units = "auto"), error = function(e) "?")
        add_flag(2L, "overwrite", op, sprintf("%s existing object `%s` <%s, %s>",
                 if (complex) "modifies" else "overwrites", nm, class(obj)[1L], sz))
      } else if (complex && exists(nm, envir = envir, inherits = TRUE)) {
        obj <- get(nm, envir = envir, inherits = TRUE)
        if (is.environment(obj) || inherits(obj, c("R6", "data.table")))
          add_flag(2L, "by_reference", op, sprintf("modifies reference object `%s` <%s> in place",
                   nm, class(obj)[1L]))
      }
    }
  }

  walk <- function(e, ctx) {
    if (is.expression(e) || is.pairlist(e)) { for (a in as.list(e)) if (!missing(a)) walk(a, ctx); return(invisible()) }
    if (!is.call(e)) return(invisible())
    head <- e[[1L]]
    r <- resolve_head(head)
    calls[[length(calls) + 1L]] <<- if (!is.na(r$pkg)) paste0(r$pkg, "::", r$name) else r$name
    fname <- r$name
    args <- as.list(e)[-1L]
    nms <- names(args) %||% rep("", length(args))

    if (r$how == "computed") {
      add_flag(3L, "dynamic", "<computed>", paste0("calls a computed function: ",
               paste(deparse(head, width.cutoff = 60L)[1L], collapse = "")))
      walk(head, ctx)
    } else if (r$how == "lambda") {
      walk(head, ctx)                                  # the lambda body
    } else {
      if (r$how == "indirect") walk(head, ctx)
      flag_fn(fname, r$pkg, r$how, e, ctx)
      if (r$how == "direct" && nzchar(fname) && is.null(get0(fname, envir = RISK_INDEX, inherits = FALSE))) {
        flag_user_fun(fname, ctx)
        flag_user_s3_methods(fname, ctx)
      }
      if (startsWith(r$how, "method$")) flag_env_method(r$name, sub("^method[$]", "", r$how), ctx)
    }

    # assignments
    if (fname %in% c("<-", "=", "<<-") && length(args) == 2L) {
      note_assign(args[[1L]], fname, ctx)
      rhs <- args[[2L]]
      # alias: f <- unlink ; f <- base::unlink
      rr <- fun_ref(rhs)
      if (!is.null(rr) && !is.null(lookup_fn(rr$name, rr$pkg))) flag_fn(rr$name, rr$pkg, "alias", NULL, ctx)
      walk(rhs, ctx)
      if (is.call(args[[1L]])) walk(args[[1L]], ctx)
      return(invisible())
    }
    if (fname == "assign" && length(args) >= 1L && is.character(args[[1L]])) {
      note_assign(as.name(args[[1L]]), "assign", ctx)
    }
    # parse(text = "literal") -> classify the literal too
    lit <- is_literal_text_parse(e)
    if (!is.null(lit)) {
      if (is.na(lit)) add_flag(1L, "dynamic", fname, "parses computed text (only dangerous if evaluated)")
      else {
        sub <- classify_r_code(lit, envir, root, depth, .seen)
        if (!is.null(sub$flags)) for (i in seq_len(nrow(sub$flags)))
          add_flag(sub$flags$level[i], sub$flags$category[i], sub$flags$fn[i],
                   paste0("in parsed text: ", sub$flags$detail[i]))
      }
    }
    # higher-order functions: function-valued arguments
    hof <- HOF_ARGS[[fname]]
    fun_slots <- integer()
    if (!is.null(hof) && nzchar(hof[1L])) {
      i <- match(hof[1L], nms)
      if (is.na(i)) { un <- which(nms == ""); p <- as.integer(hof[2L]); if (length(un) >= p) i <- un[p] }
      if (!is.na(i)) fun_slots <- i
    }
    for (i in fun_slots) {
      a <- args[[i]]
      rr <- fun_ref(a)
      if (!is.null(rr)) {
        if (!is.null(lookup_fn(rr$name, rr$pkg))) flag_fn(rr$name, rr$pkg, "hof", NULL, ctx)
        else flag_user_fun(rr$name, ctx)
      } else if (is.call(a) && !identical(a[[1L]], as.name("function"))) {
        add_flag(if (fname %in% c("do.call", "exec", "invoke")) 3L else 1L, "dynamic", fname,
                 "function argument is computed")
      }
    }
    # direct symbol arguments that name risky functions (e.g. (function(f) f())(unlink), x %>% unlink)
    if (!fname %in% NSE_FUNS && !fname %in% c("<-", "=", "<<-", "::", ":::", "function")) {
      for (i in setdiff(seq_along(args), fun_slots)) {
        a <- args[[i]]
        if (is.symbol(a) && !identical(a, quote(expr = ))) {
          s <- as.character(a)
          if (!s %in% COLLISION_PRONE && !is.null(lookup_fn(s))) flag_fn(s, NA_character_, "hof", NULL, ctx)
        }
      }
    }
    # recurse with context
    new_ctx <- ctx
    if (fname == "function") new_ctx$in_def <- TRUE
    if (fname %in% c("local")) new_ctx$in_def <- TRUE
    if (fname %in% QUOTING_FUNS) new_ctx$in_quote <- TRUE
    if (fname %in% c("repeat") || (fname == "while" && length(args) >= 1L && isTRUE(args[[1L]])))
      add_flag(1L, "advisory", fname, "loop without a static exit condition: may not terminate")
    for (i in seq_along(args)) {
      a <- args[[i]]
      if (missing(a)) next
      if (fname == "function" && i == 1L) next         # formals pairlist
      walk(a, new_ctx)
    }
    invisible()
  }
  walk(exprs, list(in_def = FALSE, in_quote = FALSE))

  fl <- if (length(flags)) unique(do.call(rbind, flags)) else NULL
  new_objs <- setdiff(unique(assigns), overwrites)
  level <- if (is.null(fl)) 0L else max(fl$level)
  if (level < 1L && length(new_objs)) level <- 1L
  structure(list(level = level, label = RISK_LABELS[level + 1L], flags = fl,
                 assigns = unique(assigns), overwrites = unique(overwrites),
                 calls = unique(calls), parse_error = NULL), class = "gptr_risk")
}

format.gptr_risk <- function(x, ...) {
  if (identical(x$label, "invalid")) return(paste0("invalid R code: ", x$parse_error))
  out <- sprintf("risk %d (%s)", x$level, x$label)
  if (!is.null(x$flags)) {
    f <- x$flags[order(-x$flags$level), , drop = FALSE]
    out <- c(out, sprintf("  [%d] %-13s %s", f$level, f$category, f$detail))
  }
  if (length(setdiff(x$assigns, x$overwrites))) out <- c(out, paste0("  creates: ", paste(setdiff(x$assigns, x$overwrites), collapse = ", ")))
  out
}
print.gptr_risk <- function(x, ...) { cat(format(x), sep = "\n"); invisible(x) }

````

### A.2 Classifier test table

**Source** (`b1_test.R`)

````r
source("b1_classifier.R")

# A fake session environment the code WOULD run in (never evaluated by the classifier).
sess <- new.env(parent = globalenv())
sess$df <- data.frame(a = 1:3)
sess$big <- rnorm(1e6)
sess$cfg <- new.env()                       # a reference object
sess$cleanup <- function(path) unlink(path, recursive = TRUE)   # user wrapper around unlink
sess$safe_summary <- function(x) summary(x)
if (requireNamespace("data.table", quietly = TRUE)) sess$dt <- data.table::data.table(x = 1:3)
root <- file.path(tempdir(), "proj"); dir.create(root, showWarnings = FALSE)
writeLines("unlink('data', recursive = TRUE)", file.path(root, "helper.R"))

cases <- list(
  # code, expected level
  list("summary(mtcars); str(iris); head(df[df$a > 1, , drop = FALSE])", 0),
  list("fit <- lm(mpg ~ wt, data = mtcars); coef(fit)", 1),
  list("df <- head(df, 2)", 2),
  list("big[1] <- 0", 2),
  list("x$a[[2]]$b <- 1", 1),
  list("cfg$token <- 'abc'", 2),
  list("unlink('x')", 3),
  list("`unlink`('x')", 3),
  list("\"unlink\"('x')", 3),
  list("base::unlink('x')", 3),
  list("base:::unlink('x')", 3),
  list("\"base\"::\"unlink\"('x')", 3),
  list("`base::unlink`('x')", 3),
  list("(unlink)('x')", 3),
  list("do.call('unlink', list('x'))", 3),
  list("do.call(what = unlink, args = list('x'))", 3),
  list("get('system')('ls')", 3),
  list("get(paste0('sys', 'tem'))('ls')", 3),
  list("match.fun('file.remove')('a.csv')", 3),
  list("utils::getFromNamespace('unlink', 'base')('x')", 3),
  list("rlang::exec('unlink', 'x')", 3),
  list("f <- unlink; f('x')", 3),
  list("g <- base::file.remove", 3),
  list("lapply(files, file.remove)", 3),
  list("Map(unlink, files)", 3),
  list("purrr::walk(files, fs::file_delete)", 3),
  list("invisible(lapply(c('a', 'b'), function(f) file.remove(f)))", 3),
  list("x |> unlink()", 3),
  list("files %>% unlink", 3),
  list("(function(f) f('x'))(unlink)", 3),
  list("h <- \\(p) unlink(p)", 3),
  list("funs[['unlink']]('x')", 3),
  list("eval(parse(text = \"unlink('x')\"))", 3),
  list("eval(str2lang(cmd))", 3),
  list("system2('rm', c('-rf', '/'))", 3),
  list("processx::run('ls')", 3),
  list("p <- processx::process$new('sleep', '10')", 3),
  list("install.packages('data.table')", 3),
  list("remove.packages('ggplot2')", 3),
  list("download.file('https://example.com/x.csv', 'x.csv')", 2),
  list("read.csv('https://example.com/x.csv')", 0),
  list("source('https://example.com/evil.R')", 3),
  list("source('helper.R')", 3),
  list("setwd('/')", 2),
  list("Sys.setenv(PATH = '')", 2),
  list("options(warn = 2)", 2),
  list("options('digits')", 0),
  list("rm(list = ls())", 4),
  list("rm(df)", 2),
  list("q('no')", 4),
  list("quit(save = 'no')", 4),
  list("tools::pskill(Sys.getpid())", 4),
  list("sapply(1:3, q)", 4),
  list("x <<- 1", 2),
  list("assign('x', 1, envir = globalenv())", 2),
  list("dt[, y := x * 2]", 2),
  list("data.table::setnames(dt, 'x', 'z')", 2),
  list("write.csv(mtcars, 'out.csv')", 2),
  list("write.csv(mtcars, '/etc/out.csv')", 3),
  list("writeLines('x', '~/.Rprofile')", 3),
  list("writeLines(c('a', 'b'))", 0),
  list("saveRDS(big, file.path(tempdir(), 'big.rds'))", 1),
  list("unlink(tempfile())", 1),
  list("unlink(tempdir(), recursive = TRUE)", 4),
  list("unlink('*.csv')", 3),
  list("unlink('~', recursive = TRUE)", 4),
  list("unlink('.', recursive = TRUE)", 4),
  list("file.remove('.git/config')", 4),
  list("cat('x', file = 'notes.txt', append = TRUE)", 2),
  list("cat('hello\\n')", 0),
  list("con <- file('out.txt', 'w'); writeLines('hi', con); close(con)", 2),
  list("png('plot.png'); plot(1); dev.off()", 2),
  list("ggplot(df, aes(x = q, y = system)) + geom_point()", 0),
  list("dplyr::filter(df, run > 1)", 0),
  list("Sys.getenv('OPENAI_API_KEY')", 2),
  list("Sys.getenv('HOME')", 0),
  list("Sys.getenv()", 2),
  list("library(data.table)", 1),
  list("cleanup('data')", 3),
  list("safe_summary(df)", 0),
  list("lapply(list(df), safe_summary)", 0),
  list("browser()", 3),
  list("ans <- readline('continue? ')", 3),
  list("repeat { i <- i + 1 }", 1),
  list("reticulate::py_run_string('import os')", 3),
  list("file.rename('a.csv', 'b.csv')", 2),
  list(".Internal(inspect(x))", 3),
  list("environment(f)$secret <- 1", 2),
  list("httr2::request('https://api.x.com') |> httr2::req_body_json(list(k = key)) |> httr2::req_perform()", 3),
  list("quote(unlink('x'))", 2),
  list("x <- 'unlink'; do.call(x, list('a'))", 3),
  list("f <- get('unlink'); f('x')", 3),
  list("nm <- 'mtcars'; get(nm)", 1),
  list("\"\\u0075nlink\"('x')", 3),
  list("get('unlink', envir = baseenv())('x')", 3),
  list("withr::with_dir('/', unlink('x'))", 3),
  list("body(f) <- quote(unlink('x'))", 2),
  list("do.call(paste0('unl', 'ink'), list('a'))", 3),
  list("eval(as.call(list(as.name('unlink'), 'x')))", 3),
  list("Sys.setenv(R_LIBS_USER = '/tmp/evil')", 2),
  list("this is not R code {", 0)
)
# Documented blind spots: the true risk is 3 but a static classifier cannot see it.
sess$obj <- local({ e <- new.env(); e$cleanup <- function() unlink("data", recursive = TRUE); class(e) <- "R6like"; e })
sess$print.evil <- function(x, ...) unlink("data", recursive = TRUE)
limits <- list(
  list("library(evilpkg)", "package .onLoad/.onAttach hooks are invisible"),
  list("targets::tar_destroy()", "package functions not in the table (this one deletes _targets/)"),
  list("usethis::create_package('.')", "package functions not in the table (writes many files)"),
  list("show(s4obj)", "S4 dispatch to a user method registered with setMethod() is not followed")
)
followed <- list(
  list("obj$cleanup()", 3L), list("print(structure(1, class = 'evil'))", 3L),
  list("f <- function() get(paste0('unl', 'ink')); f()('x')", 3L)
)

res <- data.frame(code = character(), expected = integer(), got = integer(), label = character(),
                  reasons = character(), ok = logical(), stringsAsFactors = FALSE)
for (k in cases) {
  r <- classify_r_code(k[[1]], envir = sess, root = root)
  reasons <- if (is.null(r$flags)) "" else paste(unique(sprintf("%s:%s", r$flags$category, r$flags$fn)), collapse = " ")
  if (identical(r$label, "invalid")) reasons <- "parse error"
  res[nrow(res) + 1L, ] <- list(k[[1]], as.integer(k[[2]]), r$level, r$label, reasons, r$level == k[[2]])
}
old <- options(width = 250)
for (i in seq_len(nrow(res)))
  cat(sprintf("%s | %d | %d %-9s | %-62s | %s\n", if (res$ok[i]) "ok  " else "FAIL", res$expected[i],
              res$got[i], res$label[i], substr(res$code[i], 1, 62), substr(res$reasons[i], 1, 110)))
cat(sprintf("\n%d / %d cases as expected\n", sum(res$ok), nrow(res)))
cat("\n--- indirect cases the classifier follows (R6 method, user S3 method, computed call) ---\n")
for (k in followed) {
  r <- classify_r_code(k[[1]], envir = sess, root = root)
  cat(sprintf("%s got %d %-9s | %s\n", if (r$level == k[[2]]) "ok  " else "FAIL", r$level, r$label, k[[1]]))
}
cat("\n--- documented blind spots (true risk: dangerous) ---\n")
for (k in limits) {
  r <- classify_r_code(k[[1]], envir = sess, root = root)
  cat(sprintf("got %d %-9s | %-52s | %s\n", r$level, r$label, k[[1]], k[[2]]))
}

cat("\n--- detail for three cases ---\n")
print(classify_r_code("cleanup('data'); df <- head(df, 2); f <- unlink", envir = sess, root = root))
print(classify_r_code("eval(parse(text = \"unlink('x')\"))", envir = sess, root = root))
print(classify_r_code("source('helper.R')", envir = sess, root = root))

# never evaluates: a real file survives classification of code that deletes it
victim <- file.path(root, "victim.txt"); writeLines("x", victim)
invisible(classify_r_code(sprintf("unlink('%s'); file.remove('%s')", victim, victim), root = root))
cat("\nfile still exists after classifying code that deletes it:", file.exists(victim), "\n")

big_script <- paste(rep("x <- mean(rnorm(10)); y <- lapply(1:3, function(i) i^2); df2 <- merge(df, df)", 500), collapse = "\n")
cat("classify 500-line script (1500 statements):", system.time(classify_r_code(big_script, envir = sess, root = root))[["elapsed"]], "s\n")
options(old)

````

**Output of Rscript --vanilla b1_test.R** (`b1_test.out`)

````text
ok   | 0 | 0 read-only | summary(mtcars); str(iris); head(df[df$a > 1, , drop = FALSE]) | 
ok   | 1 | 1 local     | fit <- lm(mpg ~ wt, data = mtcars); coef(fit)                  | 
ok   | 2 | 2 mutating  | df <- head(df, 2)                                              | overwrite:<-
ok   | 2 | 2 mutating  | big[1] <- 0                                                    | overwrite:<-
ok   | 1 | 1 local     | x$a[[2]]$b <- 1                                                | 
ok   | 2 | 2 mutating  | cfg$token <- 'abc'                                             | overwrite:<-
ok   | 3 | 3 dangerous | unlink('x')                                                    | file_delete:unlink
ok   | 3 | 3 dangerous | `unlink`('x')                                                  | file_delete:unlink
ok   | 3 | 3 dangerous | "unlink"('x')                                                  | file_delete:unlink
ok   | 3 | 3 dangerous | base::unlink('x')                                              | file_delete:unlink
ok   | 3 | 3 dangerous | base:::unlink('x')                                             | file_delete:unlink
ok   | 3 | 3 dangerous | "base"::"unlink"('x')                                          | file_delete:unlink
ok   | 3 | 3 dangerous | `base::unlink`('x')                                            | file_delete:base::unlink
ok   | 3 | 3 dangerous | (unlink)('x')                                                  | file_delete:unlink
ok   | 3 | 3 dangerous | do.call('unlink', list('x'))                                   | file_delete:unlink
ok   | 3 | 3 dangerous | do.call(what = unlink, args = list('x'))                       | file_delete:unlink
ok   | 3 | 3 dangerous | get('system')('ls')                                            | process:system
ok   | 3 | 3 dangerous | get(paste0('sys', 'tem'))('ls')                                | dynamic:<computed> dynamic:get
ok   | 3 | 3 dangerous | match.fun('file.remove')('a.csv')                              | file_delete:file.remove
ok   | 3 | 3 dangerous | utils::getFromNamespace('unlink', 'base')('x')                 | file_delete:unlink
ok   | 3 | 3 dangerous | rlang::exec('unlink', 'x')                                     | file_delete:unlink
ok   | 3 | 3 dangerous | f <- unlink; f('x')                                            | file_delete:unlink
ok   | 3 | 3 dangerous | g <- base::file.remove                                         | file_delete:file.remove
ok   | 3 | 3 dangerous | lapply(files, file.remove)                                     | file_delete:file.remove
ok   | 3 | 3 dangerous | Map(unlink, files)                                             | file_delete:unlink
ok   | 3 | 3 dangerous | purrr::walk(files, fs::file_delete)                            | file_delete:file_delete
ok   | 3 | 3 dangerous | invisible(lapply(c('a', 'b'), function(f) file.remove(f)))     | file_delete:file.remove
ok   | 3 | 3 dangerous | x |> unlink()                                                  | file_delete:unlink
ok   | 3 | 3 dangerous | files %>% unlink                                               | file_delete:unlink
ok   | 3 | 3 dangerous | (function(f) f('x'))(unlink)                                   | file_delete:unlink
ok   | 3 | 3 dangerous | h <- \(p) unlink(p)                                            | file_delete:unlink
ok   | 3 | 3 dangerous | funs[['unlink']]('x')                                          | dynamic:<computed>
ok   | 3 | 3 dangerous | eval(parse(text = "unlink('x')"))                              | dynamic:eval file_delete:unlink
ok   | 3 | 3 dangerous | eval(str2lang(cmd))                                            | dynamic:eval dynamic:str2lang
ok   | 3 | 3 dangerous | system2('rm', c('-rf', '/'))                                   | process:system2
ok   | 3 | 3 dangerous | processx::run('ls')                                            | process:run
ok   | 3 | 3 dangerous | p <- processx::process$new('sleep', '10')                      | process:process
ok   | 3 | 3 dangerous | install.packages('data.table')                                 | package:install.packages
ok   | 3 | 3 dangerous | remove.packages('ggplot2')                                     | package:remove.packages
ok   | 2 | 2 mutating  | download.file('https://example.com/x.csv', 'x.csv')            | network:download.file
ok   | 0 | 0 read-only | read.csv('https://example.com/x.csv')                          | 
ok   | 3 | 3 dangerous | source('https://example.com/evil.R')                           | dynamic:source
ok   | 3 | 3 dangerous | source('helper.R')                                             | file_delete:unlink dynamic:source
ok   | 2 | 2 mutating  | setwd('/')                                                     | session:setwd
ok   | 2 | 2 mutating  | Sys.setenv(PATH = '')                                          | session:Sys.setenv
ok   | 2 | 2 mutating  | options(warn = 2)                                              | session:options
ok   | 0 | 0 read-only | options('digits')                                              | 
ok   | 4 | 4 critical  | rm(list = ls())                                                | object_delete:rm
ok   | 2 | 2 mutating  | rm(df)                                                         | object_delete:rm
ok   | 4 | 4 critical  | q('no')                                                        | quit:q
ok   | 4 | 4 critical  | quit(save = 'no')                                              | quit:quit
ok   | 4 | 4 critical  | tools::pskill(Sys.getpid())                                    | quit:pskill
ok   | 4 | 4 critical  | sapply(1:3, q)                                                 | quit:q
ok   | 2 | 2 mutating  | x <<- 1                                                        | env_mutation:<<-
ok   | 2 | 2 mutating  | assign('x', 1, envir = globalenv())                            | env_mutation:assign
ok   | 2 | 2 mutating  | dt[, y := x * 2]                                               | by_reference::=
ok   | 2 | 2 mutating  | data.table::setnames(dt, 'x', 'z')                             | by_reference:setnames
ok   | 2 | 2 mutating  | write.csv(mtcars, 'out.csv')                                   | file_write:write.csv
ok   | 3 | 3 dangerous | write.csv(mtcars, '/etc/out.csv')                              | file_write:write.csv
ok   | 3 | 3 dangerous | writeLines('x', '~/.Rprofile')                                 | file_write:writeLines
ok   | 0 | 0 read-only | writeLines(c('a', 'b'))                                        | 
ok   | 1 | 1 local     | saveRDS(big, file.path(tempdir(), 'big.rds'))                  | file_write:saveRDS
ok   | 1 | 1 local     | unlink(tempfile())                                             | file_delete:unlink
ok   | 4 | 4 critical  | unlink(tempdir(), recursive = TRUE)                            | file_delete:unlink
ok   | 3 | 3 dangerous | unlink('*.csv')                                                | file_delete:unlink
ok   | 4 | 4 critical  | unlink('~', recursive = TRUE)                                  | file_delete:unlink
ok   | 4 | 4 critical  | unlink('.', recursive = TRUE)                                  | file_delete:unlink
ok   | 4 | 4 critical  | file.remove('.git/config')                                     | file_delete:file.remove
ok   | 2 | 2 mutating  | cat('x', file = 'notes.txt', append = TRUE)                    | file_write:cat
ok   | 0 | 0 read-only | cat('hello\n')                                                 | 
ok   | 2 | 2 mutating  | con <- file('out.txt', 'w'); writeLines('hi', con); close(con) | file_write:writeLines
ok   | 2 | 2 mutating  | png('plot.png'); plot(1); dev.off()                            | file_write:png session_light:dev.off
ok   | 0 | 0 read-only | ggplot(df, aes(x = q, y = system)) + geom_point()              | 
ok   | 0 | 0 read-only | dplyr::filter(df, run > 1)                                     | 
ok   | 2 | 2 mutating  | Sys.getenv('OPENAI_API_KEY')                                   | secrets:Sys.getenv
ok   | 0 | 0 read-only | Sys.getenv('HOME')                                             | 
ok   | 2 | 2 mutating  | Sys.getenv()                                                   | secrets:Sys.getenv
ok   | 1 | 1 local     | library(data.table)                                            | session_light:library
ok   | 3 | 3 dangerous | cleanup('data')                                                | file_delete:unlink
ok   | 0 | 0 read-only | safe_summary(df)                                               | 
ok   | 0 | 0 read-only | lapply(list(df), safe_summary)                                 | 
ok   | 3 | 3 dangerous | browser()                                                      | blocking:browser
ok   | 3 | 3 dangerous | ans <- readline('continue? ')                                  | blocking:readline
ok   | 1 | 1 local     | repeat { i <- i + 1 }                                          | advisory:repeat
ok   | 3 | 3 dangerous | reticulate::py_run_string('import os')                         | dynamic:py_run_string
ok   | 2 | 2 mutating  | file.rename('a.csv', 'b.csv')                                  | file_move:file.rename
ok   | 3 | 3 dangerous | .Internal(inspect(x))                                          | dynamic:.Internal
ok   | 2 | 2 mutating  | environment(f)$secret <- 1                                     | env_mutation:<-
ok   | 3 | 3 dangerous | httr2::request('https://api.x.com') |> httr2::req_body_json(li | network:req_perform network_send:req_body_json
ok   | 2 | 2 mutating  | quote(unlink('x'))                                             | file_delete:unlink
ok   | 3 | 3 dangerous | x <- 'unlink'; do.call(x, list('a'))                           | file_delete:unlink dynamic:do.call
ok   | 3 | 3 dangerous | f <- get('unlink'); f('x')                                     | file_delete:unlink
ok   | 1 | 1 local     | nm <- 'mtcars'; get(nm)                                        | dynamic:get
ok   | 3 | 3 dangerous | "\u0075nlink"('x')                                             | file_delete:unlink
ok   | 3 | 3 dangerous | get('unlink', envir = baseenv())('x')                          | file_delete:unlink
ok   | 3 | 3 dangerous | withr::with_dir('/', unlink('x'))                              | file_delete:unlink
ok   | 2 | 2 mutating  | body(f) <- quote(unlink('x'))                                  | file_delete:unlink
ok   | 3 | 3 dangerous | do.call(paste0('unl', 'ink'), list('a'))                       | dynamic:do.call
ok   | 3 | 3 dangerous | eval(as.call(list(as.name('unlink'), 'x')))                    | dynamic:eval
ok   | 2 | 2 mutating  | Sys.setenv(R_LIBS_USER = '/tmp/evil')                          | session:Sys.setenv
ok   | 0 | 0 invalid   | this is not R code {                                           | parse error

101 / 101 cases as expected

--- indirect cases the classifier follows (R6 method, user S3 method, computed call) ---
ok   got 3 dangerous | obj$cleanup()
ok   got 3 dangerous | print(structure(1, class = 'evil'))
ok   got 3 dangerous | f <- function() get(paste0('unl', 'ink')); f()('x')

--- documented blind spots (true risk: dangerous) ---
got 1 local     | library(evilpkg)                                     | package .onLoad/.onAttach hooks are invisible
got 0 read-only | targets::tar_destroy()                               | package functions not in the table (this one deletes _targets/)
got 0 read-only | usethis::create_package('.')                         | package functions not in the table (writes many files)
got 0 read-only | show(s4obj)                                          | S4 dispatch to a user method registered with setMethod() is not followed

--- detail for three cases ---
risk 3 (dangerous)
  [3] file_delete   via user function cleanup(): calls unlink [path: unknown]
  [3] file_delete   calls unlink (aliased to another name)
  [2] overwrite     overwrites existing object `df` <data.frame, 744 bytes>
  creates: f
risk 3 (dangerous)
  [3] dynamic       calls eval
  [3] file_delete   in parsed text: calls unlink [path: workspace]
risk 3 (dangerous)
  [3] file_delete   in helper.R: calls unlink [path: workspace]
  [3] dynamic       calls source [file classified: dangerous]

file still exists after classifying code that deletes it: TRUE 
classify 500-line script (1500 statements): 0.394 s

````

### A.3 UI backends and line reader

**Source** (`c1_ui.R`)

````r
# gptr prototype (track 18): line reader + pluggable user-interaction backends.
#
# A "ui" is a plain list of functions (S3 class "gptr_ui"). Front ends (console, Shiny gadget,
# RStudio dialogs, RPC to a parent process, tests) supply their own list; the agent only calls:
#   ui$has_ui                                   logical: can we ask a human right now?
#   ui$select(title, choices, default, details) -> integer index, or NA (cancelled)
#   ui$input(prompt, default, secret)           -> character(1), or NA (cancelled)
#   ui$questions(qs)                            -> list(answers = named list, cancelled = lgl)
#   ui$notify(text, level)                      -> invisible
# Resolution order: explicit `ui =` argument > getOption("gptr.ui") > console (interactive) >
# non-interactive backend (fails closed).

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# Line reader. interactive(): readline() (history, line editing, Jupyter input_request via
# IRkernel's shadowed readline). Otherwise a single persistent connection: a fresh
# file("stdin") per call loses buffered lines (verified in a1_stdin.R).
# ---------------------------------------------------------------------------
gptr_reader <- function(con = NULL, echo = !interactive()) {
  if (is.null(con) && interactive()) {
    return(structure(list(
      read = function(prompt = "") readline(prompt),    # "" at EOF never happens interactively
      eof = function() FALSE, close = function() invisible()), class = "gptr_reader"))
  }
  own <- is.null(con)
  if (own) con <- file("stdin", open = "r")
  if (!isOpen(con)) open(con, "r")
  at_eof <- FALSE
  structure(list(
    read = function(prompt = "") {
      if (at_eof) return(NA_character_)
      if (nzchar(prompt)) { cat(prompt); flush(stdout()) }
      x <- readLines(con, n = 1L, warn = FALSE)
      if (!length(x)) { at_eof <<- TRUE; if (echo) cat("\n"); return(NA_character_) }
      if (echo) cat(x, "\n", sep = "")                  # transcript looks like a terminal session
      x
    },
    eof = function() at_eof,
    close = function() if (own) close(con)), class = "gptr_reader")
}

# ---------------------------------------------------------------------------
# Console backend
# ---------------------------------------------------------------------------
parse_choice <- function(ans, n, labels, multiple = FALSE) {
  ans <- trimws(ans)
  if (!nzchar(ans)) return(integer())
  parts <- if (multiple) strsplit(ans, "[,[:space:]]+")[[1L]] else ans
  idx <- suppressWarnings(as.integer(parts))
  if (all(!is.na(idx)) && all(idx >= 1L & idx <= n)) return(unique(idx))
  # label prefix match (case-insensitive), e.g. "y" for "Yes"
  hit <- pmatch(tolower(parts), tolower(labels), duplicates.ok = TRUE)
  if (all(!is.na(hit))) return(unique(hit))
  NA_integer_                                           # not a choice: maybe free text
}

gptr_ui_console <- function(reader = gptr_reader(), out = stdout()) {
  say <- function(...) { cat(..., file = out, sep = ""); flush(out) }
  sym <- if (isTRUE(l10n_info()$`UTF-8`)) list(q = "?", bar = "│") else list(q = "?", bar = "|")
  read <- function(prompt) {
    # Ctrl-C / Esc while waiting => cancel (NA). The caller decides what cancel means.
    tryCatch(reader$read(prompt), interrupt = function(e) { say("\n"); NA_character_ })
  }
  select <- function(title, choices, default = NULL, details = NULL, allow_other = FALSE,
                     multiple = FALSE) {
    say("\n", title, "\n")
    if (length(details)) say(paste0("  ", sym$bar, " ", details, collapse = "\n"), "\n")
    labels <- vapply(choices, function(ch) if (is.list(ch)) ch$label else ch, "")
    descs <- vapply(choices, function(ch) if (is.list(ch)) ch$description %||% "" else "", "")
    for (i in seq_along(labels)) {
      say(sprintf("  %d: %s%s\n", i, labels[i], if (nzchar(descs[i])) paste0("  - ", descs[i]) else ""))
    }
    hint <- c(if (multiple) "numbers separated by commas" else "a number",
              if (allow_other) "or type your own answer",
              if (!is.null(default)) sprintf("Enter = %s", paste(labels[default], collapse = ", ")))
    repeat {
      ans <- read(sprintf("%s (%s): ", if (multiple) "Choose" else "Choose", paste(hint, collapse = "; ")))
      if (is.na(ans)) return(NA_integer_)
      if (!nzchar(trimws(ans))) { if (!is.null(default)) return(default); next }
      idx <- parse_choice(ans, length(labels), labels, multiple)
      if (length(idx) && !anyNA(idx)) return(idx)
      if (allow_other) return(structure(NA_integer_, other = trimws(ans)))
      say("  Please enter one of the numbers shown.\n")
    }
  }
  input <- function(prompt, default = "", secret = FALSE) {
    if (secret && requireNamespace("askpass", quietly = TRUE)) return(askpass::askpass(prompt))
    ans <- read(paste0(prompt, if (nzchar(default)) sprintf(" [%s]", default), ": "))
    if (is.na(ans)) return(NA_character_)
    if (!nzchar(ans)) default else ans
  }
  questions <- function(qs) ui_questions_via(select, input, qs, say)
  structure(list(has_ui = TRUE, kind = "console", select = select, input = input,
                 questions = questions,
                 notify = function(text, level = "info") say(sprintf("[%s] %s\n", level, text))),
            class = "gptr_ui")
}

# Generic ask-user implementation on top of select()/input(): usable by every backend.
ui_questions_via <- function(select, input, qs, say = function(...) invisible()) {
  answers <- list()
  for (q in qs) {
    id <- q$id %||% q$header %||% q$question
    type <- q$type %||% (if (length(q$options)) (if (isTRUE(q$multiSelect %||% q$multiple)) "multi" else "single") else "text")
    title <- paste0(if (!is.null(q$header)) paste0("[", q$header, "] ") else "", q$question)
    if (type == "text") {
      a <- input(title, default = q$default %||% "")
      if (is.na(a)) return(list(answers = answers, cancelled = TRUE))
      answers[[id]] <- a
      next
    }
    labels <- vapply(q$options, function(o) o$label, "")
    def <- if (!is.null(q$default)) match(q$default, labels) else NULL
    if (!is.null(def) && anyNA(def)) def <- NULL
    idx <- select(title, q$options, default = def, allow_other = !isFALSE(q$allow_other),
                  multiple = type == "multi")
    if (length(idx) == 1L && is.na(idx) && is.null(attr(idx, "other")))
      return(list(answers = answers, cancelled = TRUE))
    answers[[id]] <- if (!is.null(attr(idx, "other"))) structure(attr(idx, "other"), other = TRUE) else labels[idx]
  }
  list(answers = answers, cancelled = FALSE)
}

# ---------------------------------------------------------------------------
# Non-interactive backend: nobody can answer. Fails closed (NA = cancelled/denied).
# ---------------------------------------------------------------------------
gptr_ui_none <- function(reason = "no interactive user (non-interactive R session)") {
  structure(list(has_ui = FALSE, kind = "none", reason = reason,
                 select = function(...) NA_integer_, input = function(...) NA_character_,
                 questions = function(qs) list(answers = list(), cancelled = TRUE, reason = reason),
                 notify = function(text, level = "info") message("gptr: ", text)),
            class = "gptr_ui")
}

# ---------------------------------------------------------------------------
# Scripted backend for tests: answers are consumed in order; each is an index, a label, a
# free-text string, or NA (cancel). Records every prompt it was shown.
# ---------------------------------------------------------------------------
gptr_ui_scripted <- function(answers) {
  log <- list(); i <- 0L
  nxt <- function() { i <<- i + 1L; if (i > length(answers)) NA else answers[[i]] }
  select <- function(title, choices, default = NULL, details = NULL, allow_other = FALSE, multiple = FALSE) {
    labels <- vapply(choices, function(ch) if (is.list(ch)) ch$label else ch, "")
    a <- nxt(); log[[length(log) + 1L]] <<- list(title = title, choices = labels, answer = a)
    if (length(a) == 1L && is.na(a)) return(NA_integer_)
    if (is.numeric(a)) return(as.integer(a))
    idx <- match(a, labels)
    if (!anyNA(idx)) return(idx)
    if (allow_other) return(structure(NA_integer_, other = a))
    NA_integer_
  }
  input <- function(prompt, default = "", secret = FALSE) {
    a <- nxt(); log[[length(log) + 1L]] <<- list(title = prompt, answer = a)
    if (is.na(a)) NA_character_ else as.character(a)
  }
  structure(list(has_ui = TRUE, kind = "scripted", select = select, input = input,
                 questions = function(qs) ui_questions_via(select, input, qs),
                 notify = function(text, level = "info") invisible(),
                 log = function() log), class = "gptr_ui")
}

# ---------------------------------------------------------------------------
# Resolution: the hook other front ends (Shiny, RStudio, RPC) use is options(gptr.ui = <ui>)
# or options(gptr.ui = function() <ui>) evaluated lazily.
# ---------------------------------------------------------------------------
gptr_current_ui <- function(ui = NULL, reader = NULL) {
  if (!is.null(ui)) return(ui)
  opt <- getOption("gptr.ui")
  if (is.function(opt)) opt <- opt()
  if (!is.null(opt)) return(opt)
  if (!is.null(reader)) return(gptr_ui_console(reader))
  if (interactive() && !isTRUE(getOption("knitr.in.progress"))) return(gptr_ui_console())
  if (isTRUE(getOption("jupyter.in_kernel"))) return(gptr_ui_console())   # IRkernel shadows readline
  gptr_ui_none()
}

````

### A.4 Permission modes, rules and prompt

**Source** (`c2_permissions.R`)

````r
# gptr prototype (track 18): permission modes, rules, and the approval prompt.
# Depends on b1_classifier.R (classify_r_code) and c1_ui.R (ui backends).

MODES <- c("plan", "manual", "edits", "auto")          # strictness: plan > manual > edits > auto

# ---------------------------------------------------------------------------
# Risk of a tool call (0..4) plus a human-readable summary and suggested session rule.
# ---------------------------------------------------------------------------
tool_risk <- function(tool, input, ctx) {
  root <- ctx$root
  if (tool %in% c("read", "grep", "find", "ls")) {
    p <- input$path %||% "."
    pc <- classify_path(p, root)
    lvl <- switch(pc, workspace = 0L, temp = 0L, critical = 0L, protected = 2L, 1L)
    if (pc == "critical" && norm_path(file.path(root, p)) == norm_path(root)) lvl <- 0L
    return(list(level = lvl, category = paste0("read_", pc), summary = sprintf("%s %s [%s]", tool, p, pc),
                rule = sprintf("%s(%s)", tool, suggest_glob(p, root))))
  }
  if (tool %in% c("write", "edit")) {
    p <- input$path
    pc <- classify_path(p, root)
    lvl <- switch(pc, workspace = 2L, temp = 1L, protected = 3L, outside = 3L, critical = 4L, 3L)
    return(list(level = lvl, category = paste0("file_", pc), summary = sprintf("%s %s [%s]", tool, p, pc),
                rule = sprintf("%s(%s)", tool, suggest_glob(p, root))))
  }
  if (tool == "r") {
    risk <- classify_r_code(input$code, envir = ctx$envir, root = root)
    cats <- if (is.null(risk$flags)) character() else unique(risk$flags$fn[risk$flags$level == risk$level])
    rule <- if (risk$level <= 1L) "r(level<=1)" else if (length(cats) && risk$level < 4L)
      sprintf("r(fn:%s)", paste(cats, collapse = ",")) else NA_character_
    return(list(level = if (identical(risk$label, "invalid")) 0L else risk$level, category = "r",
                summary = format(risk), risk = risk, rule = rule))
  }
  if (tool == "ask") return(list(level = 0L, category = "ask", summary = "ask the user", rule = "ask"))
  if (startsWith(tool, "mcp__")) {
    ann <- input$.annotations %||% list()
    lvl <- if (isTRUE(ann$readOnlyHint)) 0L else if (isFALSE(ann$destructiveHint)) 2L else 3L
    return(list(level = lvl, category = "mcp", summary = tool, rule = tool))
  }
  list(level = 3L, category = "unknown_tool", summary = tool, rule = tool)
}

suggest_glob <- function(p, root) {
  rel <- sub(paste0("^", norm_path(root), "/?"), "", norm_path(file.path(root, p)))
  d <- dirname(rel)
  if (d == ".") rel else paste0(d, "/**")
}

# ---------------------------------------------------------------------------
# Rules: "tool", "tool(spec)". Specs: glob for path tools, level<=n / fn:a,b / category:x for r.
# ---------------------------------------------------------------------------
parse_rule <- function(rule) {
  m <- regmatches(rule, regexec("^([A-Za-z0-9_*]+)(?:\\((.*)\\))?$", rule, perl = TRUE))[[1L]]
  if (!length(m)) stop("invalid rule: ", rule)
  list(tool = m[2L], spec = if (length(m) >= 3L && nzchar(m[3L])) m[3L] else NA_character_)
}
glob_to_regex <- function(g) {
  g <- gsub("([.+^$(){}|\\[\\]\\\\])", "\\\\\\1", g)
  g <- gsub("**/", "\001", g, fixed = TRUE); g <- gsub("**", "\002", g, fixed = TRUE)
  g <- gsub("*", "[^/]*", g, fixed = TRUE); g <- gsub("?", "[^/]", g, fixed = TRUE)
  g <- gsub("\001", "(.*/)?", g, fixed = TRUE); g <- gsub("\002", ".*", g, fixed = TRUE)
  paste0("^", g, "$")
}
rule_matches <- function(rule, tool, input, risk, ctx, kind) {
  r <- parse_rule(rule)
  if (!(r$tool == tool || r$tool == "*" || (endsWith(r$tool, "*") && startsWith(tool, sub("[*]$", "", r$tool)))))
    return(FALSE)
  if (is.na(r$spec) || r$spec == "*") return(TRUE)
  if (tool %in% c("read", "write", "edit", "grep", "find", "ls")) {
    rel <- sub(paste0("^", norm_path(ctx$root), "/?"), "", norm_path(file.path(ctx$root, input$path %||% ".")))
    return(grepl(glob_to_regex(r$spec), rel))
  }
  if (tool == "r") {
    rk <- risk$risk
    if (startsWith(r$spec, "level<=")) return(rk$level <= as.integer(sub("level<=", "", r$spec)))
    flagged <- if (is.null(rk$flags)) data.frame(fn = character(), category = character(), level = integer())
               else rk$flags[rk$flags$level >= 1L, , drop = FALSE]
    if (startsWith(r$spec, "fn:") || startsWith(r$spec, "category:")) {
      field <- if (startsWith(r$spec, "fn:")) "fn" else "category"
      set <- strsplit(sub("^[a-z]+:", "", r$spec), ",", fixed = TRUE)[[1L]]
      hits <- flagged[[field]] %in% set
      # allow: EVERY flagged call must be covered (and no un-flagged overwrite etc.);
      # deny/ask: ANY flagged call matching is enough
      if (kind == "allow") return(nrow(flagged) > 0L && all(hits) && rk$level < 4L)
      return(any(hits))
    }
  }
  FALSE
}

# ---------------------------------------------------------------------------
# The decision. Order: deny rules > ask rules > session/project allow rules > mode policy.
# ---------------------------------------------------------------------------
mode_policy <- function(mode, tool, rk) {
  lvl <- rk$level
  if (mode == "auto") return(if (lvl >= 4L && isTRUE(getOption("gptr.critical_guard", TRUE))) "ask" else "allow")
  if (lvl == 0L) return("allow")
  if (mode == "plan") {
    if (tool == "r" && lvl <= 1L) return("allow_scratch")  # evaluate in a throwaway child env
    return("deny")
  }
  if (mode == "edits" && tool %in% c("write", "edit") && rk$category %in% c("file_workspace", "file_temp"))
    return("allow")
  "ask"
}

permission_check <- function(tool, input, ctx) {
  rk <- tool_risk(tool, input, ctx)
  rules <- ctx$rules
  for (rule in rules$deny) if (rule_matches(rule, tool, input, rk, ctx, "deny"))
    return(list(decision = "deny", reason = sprintf("denied by rule %s", rule), risk = rk))
  forced_ask <- FALSE
  for (rule in rules$ask) if (rule_matches(rule, tool, input, rk, ctx, "ask")) forced_ask <- TRUE
  if (!forced_ask && ctx$mode != "plan" && rk$level < 4L) {
    for (rule in c(rules$allow, ctx$session_allow))
      if (rule_matches(rule, tool, input, rk, ctx, "allow"))
        return(list(decision = "allow", reason = sprintf("allowed by rule %s", rule), risk = rk))
  }
  d <- if (forced_ask) "ask" else mode_policy(ctx$mode, tool, rk)
  list(decision = d, reason = sprintf("mode %s, risk %d", ctx$mode, rk$level), risk = rk)
}

# Ask the human. Returns list(decision = "allow"|"deny"|"abort", message, remember).
permission_prompt <- function(tool, input, check, ctx) {
  ui <- ctx$ui
  rk <- check$risk
  if (!isTRUE(ui$has_ui)) {
    if (identical(getOption("gptr.noninteractive_ask", "deny"), "allow"))
      return(list(decision = "allow", message = "allowed: non-interactive, gptr.noninteractive_ask = 'allow'"))
    return(list(decision = "deny", message = paste0(
      "Permission required but nobody can answer (", ui$reason %||% "no UI", "). ",
      "The action was NOT performed. The user can allow it with gptr(..., mode = \"auto\"), ",
      "an allow rule such as ", rk$rule %||% tool, ", or options(gptr.noninteractive_ask = \"allow\").")))
  }
  code <- if (tool == "r") strsplit(input$code, "\n", fixed = TRUE)[[1L]] else NULL
  details <- c(rk$summary, if (length(code)) c("", paste0("> ", head(code, 20L)),
                                               if (length(code) > 20L) sprintf("> ... (%d more lines)", length(code) - 20L)))
  choices <- list("Yes")
  can_remember <- !is.na(rk$rule %||% NA_character_) && rk$level < 4L
  if (can_remember) {
    choices <- c(choices, list(sprintf("Yes, and don't ask again this session for %s", rk$rule)))
    if (!is.null(ctx$project_settings))
      choices <- c(choices, list(sprintf("Yes, and always allow %s in this project", rk$rule)))
  }
  choices <- c(choices, list("No, and tell gptr what to do instead", "No"))
  title <- sprintf("gptr wants to use %s (risk %d: %s). Allow?", tool, rk$level,
                   RISK_LABELS[rk$level + 1L])
  idx <- ui$select(title, choices, default = NULL, details = details)
  if (length(idx) == 1L && is.na(idx)) return(list(decision = "abort", message = "user cancelled (interrupt)"))
  lab <- choices[[idx]]
  if (lab == "Yes") return(list(decision = "allow"))
  if (startsWith(lab, "Yes, and don't ask again")) return(list(decision = "allow", remember = "session", rule = rk$rule))
  if (startsWith(lab, "Yes, and always allow")) return(list(decision = "allow", remember = "project", rule = rk$rule))
  if (startsWith(lab, "No, and tell")) {
    why <- ui$input("What should gptr do instead?")
    return(list(decision = "deny", message = paste0("The user denied this action and said: ", why %||% "")))
  }
  list(decision = "deny", message = "The user denied this action.")
}

# Persist an allow rule (project scope) into <root>/.gptr/settings.local.json
persist_rule <- function(rule, file) {
  s <- if (file.exists(file)) jsonlite::read_json(file, simplifyVector = FALSE) else list()
  s$permissions$allow <- unique(c(unlist(s$permissions$allow), rule))
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(file, ".tmp")
  jsonlite::write_json(s, tmp, auto_unbox = TRUE, pretty = TRUE)
  file.rename(tmp, file)
}

# One-stop gate used by the agent loop before executing a tool call.
gate_tool_call <- function(tool, input, ctx) {
  chk <- permission_check(tool, input, ctx)
  if (chk$decision %in% c("allow", "allow_scratch"))
    return(list(action = chk$decision, reason = chk$reason, risk = chk$risk))
  if (chk$decision == "deny") return(list(action = "block", reason = paste0(
    "Blocked (", chk$reason, "). ", if (ctx$mode == "plan")
      "Plan mode is read-only: describe this change in your plan instead of performing it." else ""),
    risk = chk$risk))
  ans <- permission_prompt(tool, input, chk, ctx)
  if (identical(ans$remember, "session")) ctx$session_allow <- c(ctx$session_allow, ans$rule)
  if (identical(ans$remember, "project")) {
    ctx$session_allow <- c(ctx$session_allow, ans$rule)
    persist_rule(ans$rule, ctx$project_settings)
  }
  switch(ans$decision,
         allow = list(action = "allow", reason = "approved by user", risk = chk$risk),
         deny = list(action = "block", reason = ans$message, risk = chk$risk),
         abort = list(action = "abort", reason = ans$message, risk = chk$risk))
}

new_permission_ctx <- function(mode = "manual", root = getwd(), envir = globalenv(), ui = NULL,
                               rules = list(allow = character(), ask = character(), deny = character()),
                               project_settings = file.path(root, ".gptr", "settings.local.json")) {
  ctx <- new.env(parent = emptyenv())
  ctx$mode <- match.arg(mode, MODES); ctx$root <- root; ctx$envir <- envir
  ctx$ui <- ui %||% gptr_current_ui(); ctx$rules <- rules; ctx$session_allow <- character()
  ctx$project_settings <- project_settings
  ctx
}

````

**Test** (`c2_test.R`)

````r
source("b1_classifier.R"); source("c1_ui.R"); source("c2_permissions.R")
root <- file.path(tempdir(), "proj2"); dir.create(root, showWarnings = FALSE)
sess <- new.env(); sess$df <- data.frame(a = 1:3)

calls <- list(
  list("read",  list(path = "R/analysis.R")),
  list("read",  list(path = "~/.ssh/id_rsa")),
  list("write", list(path = "results/table.csv")),
  list("edit",  list(path = ".Rprofile")),
  list("write", list(path = "/etc/hosts")),
  list("r",     list(code = "summary(df)")),
  list("r",     list(code = "fit <- lm(a ~ 1, df)")),
  list("r",     list(code = "df$b <- df$a * 2")),
  list("r",     list(code = "write.csv(df, 'out.csv')")),
  list("r",     list(code = "unlink('old', recursive = TRUE)")),
  list("r",     list(code = "rm(list = ls())"))
)
cat("Decision matrix (no rules; 'ask' means the user would be prompted):\n")
cat(sprintf("%-42s %-6s %-14s %-8s %-8s %-6s\n", "call", "risk", "plan", "manual", "edits", "auto"))
for (k in calls) {
  row <- vapply(MODES, function(m) {
    ctx <- new_permission_ctx(m, root, sess, ui = gptr_ui_none())
    permission_check(k[[1]], k[[2]], ctx)$decision
  }, "")
  rk <- tool_risk(k[[1]], k[[2]], new_permission_ctx("manual", root, sess, ui = gptr_ui_none()))
  lab <- paste0(k[[1]], ": ", k[[2]][[1]])
  cat(sprintf("%-42s %-6d %-14s %-8s %-8s %-6s\n", substr(lab, 1, 42), rk$level, row[1], row[2], row[3], row[4]))
}

check <- function(label, cond) cat(sprintf("%-78s %s\n", label, if (isTRUE(cond)) "ok" else "FAIL"))
cat("\nBehavioural checks:\n")

# 1. manual + user says "Yes, don't ask again this session" -> second identical call not prompted
ui <- gptr_ui_scripted(list(2L))
ctx <- new_permission_ctx("manual", root, sess, ui = ui)
g1 <- gate_tool_call("r", list(code = "write.csv(df, 'a.csv')"), ctx)
g2 <- gate_tool_call("r", list(code = "write.csv(mtcars, 'b.csv')"), ctx)
check("session rule remembered after 'Yes, and don't ask again this session'",
      g1$action == "allow" && g2$action == "allow" && length(ui$log()) == 1L &&
      identical(ctx$session_allow, "r(fn:write.csv)"))
g3 <- gate_tool_call("r", list(code = "write.csv(df, 'c.csv'); unlink('x')"), ctx)
check("session rule does NOT cover code that also calls unlink (prompted again)", length(ui$log()) == 2L)

# 2. project rule persisted to .gptr/settings.local.json
ui <- gptr_ui_scripted(list(3L))
ctx <- new_permission_ctx("manual", root, sess, ui = ui)
g <- gate_tool_call("write", list(path = "results/t.csv"), ctx)
js <- jsonlite::read_json(file.path(root, ".gptr", "settings.local.json"))
check("'always allow in this project' persists write(results/**)", g$action == "allow" &&
      identical(unlist(js$permissions$allow), "write(results/**)"))

# 3. deny with feedback -> model receives the user's text
ui <- gptr_ui_scripted(list(4L, "use saveRDS into results/ instead"))
ctx <- new_permission_ctx("manual", root, sess, ui = ui)
g <- gate_tool_call("r", list(code = "unlink('old')"), ctx)
check("'No, and tell gptr what to do instead' blocks and forwards the text",
      g$action == "block" && grepl("saveRDS into results", g$reason))

# 4. Ctrl-C at the prompt -> abort the run
ui <- gptr_ui_scripted(list(NA))
ctx <- new_permission_ctx("manual", root, sess, ui = ui)
check("cancel (NA / interrupt) at the prompt aborts the run",
      gate_tool_call("r", list(code = "unlink('old')"), ctx)$action == "abort")

# 5. non-interactive: fails closed with an actionable reason
ctx <- new_permission_ctx("manual", root, sess, ui = gptr_ui_none())
g <- gate_tool_call("r", list(code = "df$a <- 0"), ctx)
check("non-interactive manual mode blocks and explains how to allow", g$action == "block" &&
      grepl("NOT performed", g$reason))
withr_opt <- options(gptr.noninteractive_ask = "allow")
check("options(gptr.noninteractive_ask = 'allow') opts in",
      gate_tool_call("r", list(code = "df$a <- 0"), ctx)$action == "allow")
options(withr_opt)

# 6. auto mode: deny rules still apply; critical guard asks (and blocks without UI)
ctx <- new_permission_ctx("auto", root, sess, ui = gptr_ui_none(),
                          rules = list(allow = character(), ask = character(), deny = c("r(fn:install.packages)", "write(data/raw/**)")))
check("auto: deny rule r(fn:install.packages) blocks", gate_tool_call("r", list(code = "install.packages('x')"), ctx)$action == "block")
check("auto: deny rule write(data/raw/**) blocks", gate_tool_call("write", list(path = "data/raw/a.csv"), ctx)$action == "block")
check("auto: unlink in workspace runs without prompt", gate_tool_call("r", list(code = "unlink('old')"), ctx)$action == "allow")
check("auto: critical q() is guarded (blocked when nobody can answer)", gate_tool_call("r", list(code = "q('no')"), ctx)$action == "block")

# 7. ask rules force a prompt even in auto
ui <- gptr_ui_scripted(list(1L))
ctx <- new_permission_ctx("auto", root, sess, ui = ui, rules = list(allow = character(), ask = "r(category:network)", deny = character()))
g <- gate_tool_call("r", list(code = "download.file('https://x.org/a', 'a')"), ctx)
check("auto: ask rule r(category:network) forces a prompt", length(ui$log()) == 1L && g$action == "allow")

# 8. plan mode: level<=1 R runs in scratch env; writes denied with an explanation
ctx <- new_permission_ctx("plan", root, sess, ui = gptr_ui_none())
check("plan: 'fit <- lm(...)' allowed in a scratch child environment",
      gate_tool_call("r", list(code = "fit <- lm(a ~ 1, df)"), ctx)$action == "allow_scratch")
g <- gate_tool_call("edit", list(path = "R/a.R"), ctx)
check("plan: edit blocked with 'describe this change in your plan'", g$action == "block" && grepl("plan", g$reason))
check("plan: allow rules cannot loosen plan mode", {
  ctx$rules$allow <- "r(level<=2)"; gate_tool_call("r", list(code = "df$a <- 0"), ctx)$action == "block" })

# 9. edits mode: workspace edits auto, protected files prompt
ui <- gptr_ui_scripted(list(5L))
ctx <- new_permission_ctx("edits", root, sess, ui = ui)
check("edits: write results/x.csv auto-approved", gate_tool_call("write", list(path = "results/x.csv"), ctx)$action == "allow")
check("edits: edit .Rprofile (protected) prompts; 'No' blocks",
      gate_tool_call("edit", list(path = ".Rprofile"), ctx)$action == "block" && length(ui$log()) == 1L)
check("edits: R code that overwrites df still prompts", permission_check("r", list(code = "df <- df[1, ]"), ctx)$decision == "ask")

# 10. what the prompt looks like on the console (piped answer "2")
cat("\n--- console rendering of a permission prompt (answer read from a pipe) ---\n")
con <- textConnection(c("2"))
ctx <- new_permission_ctx("manual", root, sess, ui = gptr_ui_console(gptr_reader(con, echo = TRUE)))
invisible(gate_tool_call("r", list(code = "write.csv(df, 'results/summary.csv')\nsaveRDS(df, 'results/df.rds')"), ctx))
cat("session rules now:", ctx$session_allow, "\n")

````

**Output of Rscript --vanilla c2_test.R** (`c2_test.out`)

````text
Decision matrix (no rules; 'ask' means the user would be prompted):
call                                       risk   plan           manual   edits    auto  
read: R/analysis.R                         0      allow          allow    allow    allow 
read: ~/.ssh/id_rsa                        2      deny           ask      ask      allow 
write: results/table.csv                   2      deny           ask      allow    allow 
edit: .Rprofile                            3      deny           ask      ask      allow 
write: /etc/hosts                          3      deny           ask      ask      allow 
r: summary(df)                             0      allow          allow    allow    allow 
r: fit <- lm(a ~ 1, df)                    1      allow_scratch  ask      ask      allow 
r: df$b <- df$a * 2                        2      deny           ask      ask      allow 
r: write.csv(df, 'out.csv')                2      deny           ask      ask      allow 
r: unlink('old', recursive = TRUE)         3      deny           ask      ask      allow 
r: rm(list = ls())                         4      deny           ask      ask      ask   

Behavioural checks:
session rule remembered after 'Yes, and don't ask again this session'          ok
session rule does NOT cover code that also calls unlink (prompted again)       ok
'always allow in this project' persists write(results/**)                      ok
'No, and tell gptr what to do instead' blocks and forwards the text            ok
cancel (NA / interrupt) at the prompt aborts the run                           ok
non-interactive manual mode blocks and explains how to allow                   ok
options(gptr.noninteractive_ask = 'allow') opts in                             ok
auto: deny rule r(fn:install.packages) blocks                                  ok
auto: deny rule write(data/raw/**) blocks                                      ok
auto: unlink in workspace runs without prompt                                  ok
auto: critical q() is guarded (blocked when nobody can answer)                 ok
auto: ask rule r(category:network) forces a prompt                             ok
plan: 'fit <- lm(...)' allowed in a scratch child environment                  ok
plan: edit blocked with 'describe this change in your plan'                    ok
plan: allow rules cannot loosen plan mode                                      ok
edits: write results/x.csv auto-approved                                       ok
edits: edit .Rprofile (protected) prompts; 'No' blocks                         ok
edits: R code that overwrites df still prompts                                 ok

--- console rendering of a permission prompt (answer read from a pipe) ---

gptr wants to use r (risk 2: mutating). Allow?
  │ risk 2 (mutating)
  │   [2] file_write    calls write.csv [path: workspace]
  │   [2] file_write    calls saveRDS [path: workspace]
  │ 
  │ > write.csv(df, 'results/summary.csv')
  │ > saveRDS(df, 'results/df.rds')
  1: Yes
  2: Yes, and don't ask again this session for r(fn:write.csv,saveRDS)
  3: Yes, and always allow r(fn:write.csv,saveRDS) in this project
  4: No, and tell gptr what to do instead
  5: No
Choose (a number): 2
session rules now: r(fn:write.csv,saveRDS) 

````

### A.5 ask tool

**Source** (`c3_ask_tool.R`)

````r
# gptr prototype (track 18): the model-visible `ask` tool (REQ-36).
# Schema merges Claude Code AskUserQuestion (questions[] with header/options/multiSelect),
# Codex request_user_input (id, isOther, isSecret) and Pi questionnaire (id, allowOther).

ASK_TOOL <- list(
  name = "ask",
  description = paste(
    "Ask the user one to four questions and wait for the answers. Use it when a decision",
    "materially changes the result (which object, which method, which output format) and you",
    "cannot infer the answer from the session or files. Prefer options the user can pick;",
    "the user can always type their own answer instead. Do not use it for permission to run",
    "code: the harness asks for permission itself."),
  input_schema = list(
    type = "object", additionalProperties = FALSE, required = list("questions"),
    properties = list(questions = list(
      type = "array", minItems = 1L, maxItems = 4L,
      items = list(type = "object", additionalProperties = FALSE, required = list("id", "question"),
        properties = list(
          id = list(type = "string", description = "Short stable key for the answer, e.g. 'format'"),
          header = list(type = "string", maxLength = 16L, description = "Very short label, e.g. 'Format'"),
          question = list(type = "string", description = "The full question shown to the user"),
          type = list(type = "string", enum = list("single", "multi", "text"),
                      description = "single = pick one option, multi = pick any number, text = free text"),
          options = list(type = "array", maxItems = 9L, items = list(
            type = "object", additionalProperties = FALSE, required = list("label"),
            properties = list(label = list(type = "string"), description = list(type = "string")))),
          allow_other = list(type = "boolean", description = "Let the user type an answer that is not an option (default true)"),
          default = list(type = "string", description = "Label (or text) used if the user just presses Enter")
        ))))),
  annotations = list(readOnlyHint = TRUE, requiresUserInteraction = TRUE),
  sequential = TRUE                     # never run concurrently with other tool calls
)

validate_ask_input <- function(input) {
  qs <- input$questions
  if (!is.list(qs) || !length(qs)) return("`questions` must be a non-empty array")
  if (length(qs) > 4L) return("at most 4 questions per call")
  ids <- vapply(qs, function(q) q$id %||% "", "")
  if (any(!nzchar(ids)) || anyDuplicated(ids)) return("every question needs a unique non-empty `id`")
  for (q in qs) {
    type <- q$type %||% (if (length(q$options)) "single" else "text")
    if (type %in% c("single", "multi") && length(q$options) < 2L) return(sprintf("question '%s' needs at least 2 options", q$id))
    if (length(q$options) > 9L) return(sprintf("question '%s' has more than 9 options", q$id))
  }
  NULL
}

# Execute: returns a tool result list(content = text for the model, details = structured answers,
# is_error = lgl). Never throws.
run_ask_tool <- function(input, ui) {
  err <- validate_ask_input(input)
  if (!is.null(err)) return(list(content = paste("Invalid ask call:", err), is_error = TRUE, details = NULL))
  if (!isTRUE(ui$has_ui)) {
    mode <- getOption("gptr.ask_noninteractive", "defaults")
    defs <- lapply(input$questions, function(q) q$default)
    names(defs) <- vapply(input$questions, function(q) q$id, "")
    have <- !vapply(defs, is.null, TRUE)
    txt <- paste0("The user is not available (", ui$reason %||% "non-interactive session", "). ",
                  if (mode == "defaults" && any(have)) paste0("Proceeding with the defaults: ",
                    paste(sprintf("%s = %s", names(defs)[have], unlist(defs[have])), collapse = "; "), ". ") else "",
                  "Continue with your best judgement, state every assumption you make, and do not ask again.")
    return(list(content = txt, is_error = FALSE,
                details = list(answers = if (mode == "defaults") defs[have] else list(), cancelled = TRUE)))
  }
  res <- ui$questions(input$questions)
  if (isTRUE(res$cancelled)) {
    return(list(content = paste("The user dismissed the questions without answering.",
                                "Do not guess silently: either stop and summarise what you need, or proceed",
                                "with clearly stated assumptions."), is_error = FALSE, details = res))
  }
  lines <- vapply(input$questions, function(q) {
    a <- res$answers[[q$id]]
    shown <- if (isTRUE(attr(a, "other"))) sprintf("(typed) %s", a) else paste(a, collapse = ", ")
    sprintf("- %s: %s", q$header %||% q$id, shown)
  }, "")
  list(content = paste(c("The user answered:", lines), collapse = "\n"), is_error = FALSE, details = res)
}

````

**Test** (`c3_test.R`)

````r
source("c1_ui.R"); source("c3_ask_tool.R")
# The input exactly as a model would send it (JSON -> list, simplifyVector = FALSE)
json <- '{"questions": [
  {"id": "format", "header": "Format", "question": "How should I report the model fit?",
   "type": "single", "options": [{"label": "Table", "description": "broom::tidy() table"},
                                 {"label": "Plot", "description": "coefficient plot"}], "default": "Table"},
  {"id": "sections", "header": "Sections", "question": "Which diagnostics should I include?",
   "type": "multi", "options": [{"label": "Residuals"}, {"label": "QQ plot"}, {"label": "Leverage"}]},
  {"id": "name", "header": "Object", "question": "Name for the fitted model object?", "type": "text", "default": "fit"}
]}'
input <- jsonlite::fromJSON(json, simplifyVector = FALSE)
check <- function(label, cond) cat(sprintf("%-70s %s\n", label, if (isTRUE(cond)) "ok" else "FAIL"))

r <- run_ask_tool(input, gptr_ui_scripted(list(2L, c(1L, 3L), "fit_lm")))
cat(r$content, "\n")
check("single / multi / text answers mapped to labels",
      identical(r$details$answers$format, "Plot") && identical(r$details$answers$sections, c("Residuals", "Leverage")) &&
      identical(r$details$answers$name, "fit_lm"))
r <- run_ask_tool(input, gptr_ui_scripted(list("use a forest plot", 1L, "m")))
check("free text instead of an option is marked (typed)", grepl("(typed) use a forest plot", r$content, fixed = TRUE))
r <- run_ask_tool(input, gptr_ui_scripted(list(NA)))
check("cancel (Ctrl-C) -> dismissed, model told not to guess silently", isTRUE(r$details$cancelled) && grepl("dismissed", r$content))
r <- run_ask_tool(input, gptr_ui_none())
cat(r$content, "\n")
check("non-interactive -> defaults reported, no error", !r$is_error && grepl("format = Table", r$content))
bad <- list(questions = list(list(id = "a", question = "?", type = "single", options = list(list(label = "only")))))
check("validation: a single-option choice question is rejected", run_ask_tool(bad, gptr_ui_none())$is_error)

cat("\n--- console rendering (answers piped: '', '1 3', '') ---\n")
con <- textConnection(c("", "1 3", ""))
r <- run_ask_tool(input, gptr_ui_console(gptr_reader(con, echo = TRUE)))
cat("\n", r$content, "\n", sep = "")

````

**Output of Rscript --vanilla c3_test.R** (`c3_test.out`)

````text
The user answered:
- Format: Plot
- Sections: Residuals, Leverage
- Object: fit_lm 
single / multi / text answers mapped to labels                         ok
free text instead of an option is marked (typed)                       ok
cancel (Ctrl-C) -> dismissed, model told not to guess silently         ok
The user is not available (no interactive user (non-interactive R session)). Proceeding with the defaults: format = Table; name = fit. Continue with your best judgement, state every assumption you make, and do not ask again. 
non-interactive -> defaults reported, no error                         ok
validation: a single-option choice question is rejected                ok

--- console rendering (answers piped: '', '1 3', '') ---

[Format] How should I report the model fit?
  1: Table  - broom::tidy() table
  2: Plot  - coefficient plot
Choose (a number; or type your own answer; Enter = Table): 

[Sections] Which diagnostics should I include?
  1: Residuals
  2: QQ plot
  3: Leverage
Choose (numbers separated by commas; or type your own answer): 1 3
[Object] Name for the fitted model object? [fit]: 

The user answered:
- Format: Table
- Sections: Residuals, Leverage
- Object: fit

````

### A.6 Streaming renderer and wait indicator

**Source** (`d1_stream.R`)

````r
# gptr prototype (track 18): streaming console renderer for model text.
# - word wraps at the console width while tokens arrive (a trailing partial word is buffered)
# - styles a markdown subset incrementally when ANSI colours are available:
#   **bold**, `inline code`, # headings, - / * / 1. bullets (hanging indent), > quotes,
#   ``` fenced code blocks (gutter, no wrapping, optional R highlighting per complete line)
# - plain mode (no ANSI: knitr, RGui, pipes, NO_COLOR) keeps the markdown text as is and only wraps
# Output is independent of how the text was chunked (tested in d1_test.R).

`%||%` <- function(a, b) if (is.null(a)) b else a

md_stream <- function(width = cli::console_width(), style = cli::num_ansi_colors() > 1L,
                      out = stdout(), highlight_r = style) {
  st <- new.env(parent = emptyenv())
  st$buf <- ""; st$col <- 0L; st$line_start <- TRUE; st$indent <- 0L
  st$fence <- FALSE; st$fence_lang <- ""; st$bold <- FALSE; st$code <- FALSE; st$heading <- FALSE
  st$line_buf <- ""                                       # only used inside fences
  sgr <- function(code) if (style) paste0("\033[", code, "m") else ""
  emit <- function(x) { cat(x, file = out, sep = ""); invisible() }
  vis_width <- function(x) sum(nchar(x, type = "width"))

  newline <- function() {
    emit(paste0(if (st$heading || st$bold || st$code) sgr("0") else "", "\n"))
    st$col <- 0L; st$line_start <- TRUE; st$indent <- 0L
    st$heading <- FALSE; st$bold <- FALSE; st$code <- FALSE   # markdown inline styles end at EOL
    st$space <- FALSE
  }
  # style + strip inline markers of one complete word; returns list(text, width)
  inline <- function(tok) {
    if (!style) return(list(text = tok, width = vis_width(tok)))
    out <- character(); w <- 0L; i <- 1L; n <- nchar(tok)
    while (i <= n) {
      if (!st$code && substr(tok, i, i + 1L) == "**") {
        st$bold <- !st$bold; out <- c(out, if (st$bold) sgr("1") else sgr("22")); i <- i + 2L; next
      }
      ch <- substr(tok, i, i)
      if (ch == "`") { st$code <- !st$code; out <- c(out, if (st$code) sgr("36") else sgr("39")); i <- i + 1L; next }
      out <- c(out, ch); w <- w + vis_width(ch); i <- i + 1L
    }
    list(text = paste(out, collapse = ""), width = w)
  }
  line_prefix <- function(tok) {                          # first word of a line
    if (grepl("^#{1,6}$", tok)) { st$heading <- TRUE; return(list(text = if (style) sgr("1;4") else paste0(tok, " "), width = if (style) 0L else nchar(tok) + 1L, eat_space = TRUE)) }
    if (tok %in% c("-", "*", "+")) { st$indent <- 2L; return(list(text = if (style) "• " else "- ", width = 2L, eat_space = TRUE)) }
    if (grepl("^[0-9]+[.)]$", tok)) { st$indent <- nchar(tok) + 1L; return(list(text = paste0(tok, " "), width = nchar(tok) + 1L, eat_space = TRUE)) }
    if (tok == ">") { st$indent <- 2L; return(list(text = if (style) paste0(sgr("2"), "│ ", sgr("22")) else "> ", width = 2L, eat_space = TRUE)) }
    NULL
  }
  fence_line <- function(line) {
    code <- line
    if (highlight_r && st$fence_lang %in% c("r", "R", "{r}") && nzchar(trimws(line))) {
      code <- tryCatch(cli::code_highlight(line), error = function(e) line)
    }
    emit(paste0(sgr("2"), "│ ", sgr("22"), code, "\n"))
  }
  process <- function(text, final = FALSE) {
    text <- gsub("\r\n?", "\n", paste0(st$buf, text)); st$buf <- ""
    repeat {
      if (!nzchar(text)) break
      if (st$fence || (st$line_start && startsWith(text, "```"))) {
        nl <- regexpr("\n", text, fixed = TRUE)
        if (nl < 0) { if (final) { text <- paste0(text, "\n"); next }; st$buf <- text; return(invisible()) }
        line <- substr(text, 1L, nl - 1L); text <- substr(text, nl + 1L, nchar(text))
        if (startsWith(line, "```")) {
          if (!st$fence) { st$fence <- TRUE; st$fence_lang <- trimws(substring(line, 4L))
                           emit(paste0(if (style) paste0(sgr("2"), "┌─ ", st$fence_lang, sgr("22")) else line, "\n")) }
          else { st$fence <- FALSE; emit(paste0(if (style) paste0(sgr("2"), "└─", sgr("22")) else line, "\n")) }
        } else if (style) fence_line(line) else emit(paste0(line, "\n"))
        st$col <- 0L; st$line_start <- TRUE
        next
      }
      m <- regexpr("^(\n|[ \t]+|[^ \t\n]+)", text)
      tok <- regmatches(text, m); rest <- substr(text, attr(m, "match.length") + 1L, nchar(text))
      if (!nzchar(rest) && !final && tok != "\n") { st$buf <- tok; return(invisible()) }  # maybe partial
      text <- rest
      if (tok == "\n") { newline(); next }
      if (grepl("^[ \t]+$", tok)) {
        if (st$line_start || st$col == st$indent) next    # no leading blanks after wrap / markers
        st$space <- TRUE; next                            # emitted only if the next word fits
      }
      if (st$line_start) {
        st$line_start <- FALSE
        pre <- line_prefix(tok)
        if (!is.null(pre)) { emit(pre$text); st$col <- st$col + pre$width
          if (nzchar(text) && grepl("^[ \t]", text)) text <- sub("^[ \t]+", "", text)
          next }
      }
      w <- inline(tok)
      sp <- isTRUE(st$space); st$space <- FALSE
      if (st$col > st$indent && st$col + sp + w$width > width) {
        emit(paste0(if (st$bold || st$code || st$heading) sgr("0") else "", "\n", strrep(" ", st$indent),
                    if (st$heading) sgr("1;4") else "", if (st$bold) sgr("1") else "", if (st$code) sgr("36") else ""))
        st$col <- st$indent
      } else if (sp) { emit(" "); st$col <- st$col + 1L }
      emit(w$text); st$col <- st$col + w$width
    }
    invisible()
  }
  list(
    write = function(delta) { process(delta); flush(out); if (identical(out, stdout())) flush.console(); invisible() },
    finish = function() { process("", final = TRUE); if (st$col > 0L) newline(); emit(sgr("0")); flush(out); invisible() },
    column = function() st$col
  )
}

# A minimal "waiting" indicator that needs no ticks from a progress bar: the caller spins it from
# the polling loop that waits for the first token (the same loop that keeps Ctrl-C responsive).
# Uses \r only (works in RStudio and Windows consoles); disabled when not a dynamic tty.
wait_indicator <- function(label = "thinking", out = stdout(), dynamic = cli::is_dynamic_tty(out)) {
  frames <- if (cli::is_utf8_output()) c("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏") else c("-", "\\", "|", "/")
  i <- 0L; t0 <- Sys.time(); shown <- FALSE; last <- 0
  list(
    tick = function() {
      if (!dynamic) return(invisible())
      now <- as.numeric(Sys.time())
      if (now - last < 0.08) return(invisible())
      last <<- now; i <<- i %% length(frames) + 1L
      msg <- sprintf("\r%s %s (%.0fs, Ctrl-C to steer or stop)", frames[i], label, as.numeric(difftime(Sys.time(), t0, units = "secs")))
      cat(msg, file = out); flush(out); shown <<- TRUE; invisible()
    },
    clear = function() {
      if (shown) { cat("\r", strrep(" ", cli::console_width() - 1L), "\r", sep = "", file = out); flush(out) }
      shown <<- FALSE; invisible()
    })
}

````

**Test** (`d1_test.R`)

````r
source("d1_stream.R")
sample <- paste0(
  "# Model summary\n\nThe **linear model** explains most of the variance in `mpg`; the coefficient on ",
  "`wt` is strongly negative, which means heavier cars travel fewer miles per gallon on average.\n\n",
  "- first bullet that is long enough to need wrapping onto a second line at forty columns\n",
  "- second bullet with **bold text** inside\n",
  "1. numbered item\n\n",
  "> a quoted remark from the user\n\n",
  "```r\nfit <- lm(mpg ~ wt, data = mtcars)\nsummary(fit)$r.squared\n```\n",
  "Done: R² = 0.75 — averaging wide chars 中文字符 too.")

render <- function(chunks, style, width = 40L) {
  tc <- textConnection("res", "w", local = TRUE)
  s <- md_stream(width = width, style = style, out = tc, highlight_r = FALSE)
  for (ch in chunks) s$write(ch)
  s$finish(); close(tc)
  paste(res, collapse = "\n")
}
random_chunks <- function(x, maxlen) {
  chars <- strsplit(x, "")[[1L]]; out <- character(); i <- 1L
  while (i <= length(chars)) { k <- sample.int(maxlen, 1L); out <- c(out, paste(chars[i:min(length(chars), i + k - 1L)], collapse = "")); i <- i + k }
  out
}
set.seed(42)
for (style in c(FALSE, TRUE)) {
  ref <- render(sample, style)
  same <- vapply(1:200, function(i) identical(render(random_chunks(sample, sample(1:9, 1)), style), ref), TRUE)
  cat(sprintf("style=%-5s: 200 random chunkings (1..9 chars) identical to one-shot rendering: %s\n", style, all(same)))
  lines <- strsplit(cli::ansi_strip(ref), "\n")[[1L]]
  w <- nchar(lines, type = "width")
  over <- lines[w > 40L & !grepl("^(│|fit|summary|```)", lines)]
  cat(sprintf("style=%-5s: max display width of wrapped prose lines = %d (limit 40); overlong: %d\n", style,
              max(w[!grepl("^(│|```)", lines)]), length(over)))
}
cat("\n--- plain rendering, width 40 ---\n"); cat(render(sample, FALSE), "\n")
cat("\n--- styled rendering, width 40 (ANSI escapes made visible) ---\n")
cat(gsub("\033", "^[", render(sample, TRUE), fixed = TRUE), "\n")
cat("\n--- cli::code_highlight on single lines ---\n")
print(tryCatch(cli::code_highlight("fit <- lm(mpg ~ wt, data = mtcars)"), error = function(e) conditionMessage(e)))
print(tryCatch(cli::code_highlight("for (i in 1:3) {"), error = function(e) paste("ERROR:", conditionMessage(e))))
cat("num_ansi_colors here:", cli::num_ansi_colors(), " (code_highlight is a no-op without colours)\n")
options(cli.num_colors = 256L)
cat("with cli.num_colors = 256:\n")
print(gsub("\033", "^[", cli::code_highlight("fit <- lm(mpg ~ wt, data = mtcars)"), fixed = TRUE))
print(tryCatch(cli::code_highlight("for (i in 1:3) {"), error = function(e) paste("ERROR:", conditionMessage(e))))

````

**Output of Rscript --vanilla d1_test.R (UTF-8 locale)** (`d1_test.out`)

````text
style=FALSE: 200 random chunkings (1..9 chars) identical to one-shot rendering: TRUE
style=FALSE: max display width of wrapped prose lines = 38 (limit 40); overlong: 0
style=TRUE : 200 random chunkings (1..9 chars) identical to one-shot rendering: TRUE
style=TRUE : max display width of wrapped prose lines = 38 (limit 40); overlong: 0

--- plain rendering, width 40 ---
# Model summary

The **linear model** explains most of
the variance in `mpg`; the coefficient
on `wt` is strongly negative, which
means heavier cars travel fewer miles
per gallon on average.

- first bullet that is long enough to
  need wrapping onto a second line at
  forty columns
- second bullet with **bold text**
  inside
1. numbered item

> a quoted remark from the user

```r
fit <- lm(mpg ~ wt, data = mtcars)
summary(fit)$r.squared
```
Done: R² = 0.75 — averaging wide chars
中文字符 too. 

--- styled rendering, width 40 (ANSI escapes made visible) ---
^[[1;4mModel summary^[[0m

The ^[[1mlinear model^[[22m explains most of the
variance in ^[[36mmpg^[[39m; the coefficient on ^[[36mwt^[[39m
is strongly negative, which means
heavier cars travel fewer miles per
gallon on average.

• first bullet that is long enough to
  need wrapping onto a second line at
  forty columns
• second bullet with ^[[1mbold text^[[22m inside
1. numbered item

^[[2m│ ^[[22ma quoted remark from the user

^[[2m┌─ r^[[22m
^[[2m│ ^[[22mfit <- lm(mpg ~ wt, data = mtcars)
^[[2m│ ^[[22msummary(fit)$r.squared
^[[2m└─^[[22m
Done: R² = 0.75 — averaging wide chars
中文字符 too.
^[[0m 

--- cli::code_highlight on single lines ---
[1] "fit <- lm(mpg ~ wt, data = mtcars)"
[1] "for (i in 1:3) {"
num_ansi_colors here: 1  (code_highlight is a no-op without colours)
with cli.num_colors = 256:
[1] "fit ^[[38;5;178m<-^[[39m ^[[1mlm^[[22m^[[38;5;178m(^[[39mmpg ^[[38;5;178m~^[[39m wt, data = mtcars^[[38;5;178m)^[[39m"
[1] "for (i in 1:3) {"

````

### A.7 REPL skeleton, run under Rscript with piped stdin

**Source** (`e1_repl.R`)

````r
# gptr prototype (track 18): the interactive console REPL behind gptr() with no prompt.
# Sources: b1_classifier.R, c1_ui.R, c2_permissions.R, c3_ask_tool.R, d1_stream.R
#
# Input language (one logical input per prompt):
#   text                      natural-language turn (with @file / @object mentions expanded)
#   /command args             slash command (see COMMANDS)
#   !<R code>                 evaluate R in the session; code + output are added to the context
#   !!<R code>                evaluate R in the session; NOT added to the context
#   ```r ... ```              fenced block: same as ! (multi-line R)
#   """ ... """               multi-line natural-language prompt
#   line ending in \          continue on the next line
# Interrupts:
#   Ctrl-C (terminal) / Esc (RStudio, RGui) while the agent works -> pause menu:
#       s = steer (message delivered after the current tool calls), f = follow-up (after the run),
#       a = abort (back to the prompt, session kept), c = continue;  Ctrl-C again = abort
#   Ctrl-C at an empty prompt -> hint; twice in a row -> leave the REPL (session returned invisibly)

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# A scripted fake agent with Pi's queue semantics (enough to exercise the REPL)
# ---------------------------------------------------------------------------
new_fake_agent <- function(envir, perm, ui, out = stdout(), delay = 0.04) {
  a <- new.env(parent = emptyenv())
  a$messages <- list(); a$steering <- character(); a$follow_up <- character(); a$usage <- 0L
  add <- function(role, text, ...) a$messages[[length(a$messages) + 1L]] <- list(role = role, text = text, ...)
  a$steer <- function(x) a$steering <- c(a$steering, x)
  a$queue_follow_up <- function(x) a$follow_up <- c(a$follow_up, x)
  a$add_context <- function(text) add("user", text, kind = "r_passthrough")

  stream_text <- function(text) {
    sp <- wait_indicator("thinking", out = out)
    for (i in 1:8) { sp$tick(); Sys.sleep(delay) }        # time to first token
    sp$clear()
    s <- md_stream(out = out)
    on.exit(s$finish())
    words <- regmatches(text, gregexpr("[^ ]+ *", text))[[1L]]
    for (w in words) { s$write(w); Sys.sleep(delay) }     # Sys.sleep is interruptible
    invisible(text)
  }
  # the "model": decides a reply / tool call from the last user message
  decide <- function(last) {
    if (grepl("^compute", last)) return(list(tool = "r", input = list(code = "avg <- mean(1:10)")))
    if (grepl("^delete", last)) return(list(tool = "r", input = list(code = "unlink('old_results', recursive = TRUE)")))
    if (grepl("^ask", last)) return(list(tool = "ask", input = list(questions = list(list(
      id = "fmt", header = "Format", question = "Table or plot?", type = "single",
      options = list(list(label = "Table"), list(label = "Plot")))))))
    list(text = paste0("You said: ", last, ". This reply streams word by word so that it can be ",
                       "interrupted, steered or aborted from the console."))
  }
  run_tool <- function(call) {
    g <- gate_tool_call(call$tool, call$input, perm)
    cat(sprintf("  [tool %s] %s -> %s\n", call$tool, gsub("\n", "; ", call$input$code %||% "questions"), g$action), file = out)
    if (g$action == "abort") stop(structure(class = c("gptr_abort", "error", "condition"),
                                            list(message = "aborted at a permission prompt", call = NULL)))
    if (g$action == "block") return(g$reason)
    if (call$tool == "ask") return(run_ask_tool(call$input, ui)$content)
    target <- if (g$action == "allow_scratch") new.env(parent = envir) else envir
    val <- eval(parse(text = call$input$code), target)
    paste("ok:", format(val))
  }
  a$prompt <- function(text) {
    add("user", text)
    pending <- character()
    repeat {
      last <- a$messages[[length(a$messages)]]$text
      d <- decide(last)
      if (!is.null(d$tool)) {
        res <- run_tool(d)
        add("tool", res)
        stream_text(paste("Tool result:", res))
        add("assistant", paste("Tool result:", res))
      } else {
        stream_text(d$text)
        add("assistant", d$text)
      }
      a$usage <- a$usage + 1L
      # Pi order: steering first (after the assistant message and its tool calls), then follow-ups
      if (length(a$steering)) { m <- a$steering[1L]; a$steering <- a$steering[-1L]; add("user", m, kind = "steer"); next }
      if (length(a$follow_up)) { m <- a$follow_up[1L]; a$follow_up <- a$follow_up[-1L]; add("user", m, kind = "follow_up"); next }
      break
    }
    invisible(a$messages[[length(a$messages)]]$text)
  }
  a
}

# ---------------------------------------------------------------------------
# Interrupt policy around one agent run (REPL mode). Returns "done" | "aborted".
# ---------------------------------------------------------------------------
run_with_interrupt_menu <- function(expr_fun, agent, reader, out = stdout()) {
  say <- function(...) cat(..., file = out, sep = "")
  menu_handler <- function(cnd) {
    say("\n")
    ans <- tryCatch(reader$read("[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? "),
                    interrupt = function(e) "a")          # Ctrl-C again while the menu waits = abort
    ans <- tolower(substr(trimws(ans %||% "a"), 1L, 1L))
    if (ans %in% c("s", "f")) {
      msg <- tryCatch(reader$read(if (ans == "s") "steer> " else "follow-up> "), interrupt = function(e) NA)
      if (!is.na(msg) && nzchar(msg)) {
        if (ans == "s") agent$steer(msg) else agent$queue_follow_up(msg)
        say(sprintf("[gptr] %s queued; continuing\n", if (ans == "s") "steering message" else "follow-up"))
      }
      invokeRestart("resume")
    }
    if (ans == "c" || ans == "") { say("[gptr] continuing\n"); invokeRestart("resume") }
    # "a": fall through; the enclosing tryCatch(interrupt =) unwinds to the prompt
  }
  tryCatch(
    withCallingHandlers({ expr_fun(); "done" }, interrupt = menu_handler),
    interrupt = function(cnd) {
      dropped <- c(agent$steering, agent$follow_up)
      agent$steering <- character(); agent$follow_up <- character()
      say("\n[gptr] aborted; the session is kept.",
          if (length(dropped)) paste0(" Dropped queued messages: ", paste(shQuote(dropped), collapse = ", ")) else "", "\n")
      "aborted"
    },
    gptr_abort = function(cnd) { say("[gptr] ", conditionMessage(cnd), "; back to the prompt\n"); "aborted" })
}

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------
r_incomplete <- function(code) {
  res <- tryCatch({ parse(text = code, keep.source = FALSE); "ok" }, error = function(e) conditionMessage(e))
  if (identical(res, "ok")) return(FALSE)
  grepl("unexpected end of input|INCOMPLETE_STRING|unexpected INCOMPLETE", res)
}

read_logical_input <- function(reader, prompt) {
  line <- reader$read(prompt)
  if (is.na(line)) return(NA_character_)
  cont <- function(p = "... ") { x <- reader$read(p); if (is.na(x)) "" else x }
  if (grepl('^\\s*"""', line)) {                        # """ multi-line prompt """
    body <- sub('^\\s*"""', "", line)
    while (!grepl('"""\\s*$', body)) body <- paste0(body, "\n", cont())
    return(trimws(sub('"""\\s*$', "", body)))
  }
  if (grepl("^\\s*```", line)) {                         # ```r fenced R block ```
    body <- character()
    repeat { x <- reader$read("... "); if (is.na(x) || grepl("^\\s*```\\s*$", x)) break; body <- c(body, x) }
    return(paste0("!", paste(body, collapse = "\n")))
  }
  if (startsWith(line, "!")) {                           # ! R code: continue while incomplete
    code <- sub("^!!?", "", line)
    while (r_incomplete(code)) code <- paste0(code, "\n", cont("+ "))
    return(paste0(if (startsWith(line, "!!")) "!!" else "!", code))
  }
  while (grepl("\\\\$", line)) line <- paste0(sub("\\\\$", "", line), "\n", cont())
  line
}

# evaluate R typed by the user: output goes to the console AND is captured for the context
eval_passthrough <- function(code, envir, out = stdout()) {
  captured <- character(); tc <- textConnection("captured", "w", local = TRUE)
  sink(tc, split = TRUE)
  msgs <- character()
  status <- tryCatch(withCallingHandlers({
    for (e in parse(text = code, keep.source = FALSE)) {
      v <- withVisible(eval(e, envir))
      if (v$visible) print(v$value)
    }
    "ok"
  }, message = function(m) msgs <<- c(msgs, conditionMessage(m)),
     warning = function(w) msgs <<- c(msgs, paste("Warning:", conditionMessage(w)))),
  error = function(e) { cat("Error: ", conditionMessage(e), "\n", sep = ""); "error" })
  sink(); close(tc)
  list(status = status, output = c(captured, trimws(msgs)))
}

expand_mentions <- function(text, envir, root = getwd(), max_lines = 40L) {
  toks <- regmatches(text, gregexpr('@("[^"]+"|[A-Za-z0-9_./~-]*[A-Za-z0-9_/~-])', text))[[1L]]
  blocks <- character()
  for (t in unique(toks)) {
    nm <- gsub('^@"?|"$', "", t)
    f <- file.path(root, nm)
    if (file.exists(f) && !dir.exists(f)) {
      x <- readLines(f, n = max_lines + 1L, warn = FALSE)
      blocks <- c(blocks, sprintf("<file path=\"%s\"%s>\n%s\n</file>", nm,
                                  if (length(x) > max_lines) " truncated=\"true\"" else "",
                                  paste(head(x, max_lines), collapse = "\n")))
    } else if (exists(nm, envir = envir, inherits = TRUE) && !is.function(get(nm, envir = envir))) {
      obj <- get(nm, envir = envir)
      desc <- utils::capture.output(utils::str(obj, max.level = 1L, list.len = 20L, give.attr = FALSE))
      blocks <- c(blocks, sprintf("<object name=\"%s\" class=\"%s\" size=\"%s\">\n%s\n</object>", nm,
                                  paste(class(obj), collapse = "/"), format(utils::object.size(obj), units = "auto"),
                                  paste(head(desc, max_lines), collapse = "\n")))
    }
  }
  if (length(blocks)) paste0(text, "\n\n", paste(blocks, collapse = "\n")) else text
}

# ---------------------------------------------------------------------------
# Slash commands. Each takes (args, st) and returns NULL or "exit".
# ---------------------------------------------------------------------------
COMMANDS <- list(
  help = list(desc = "show commands and input syntax", fn = function(args, st) {
    cat("Commands:\n")
    for (n in names(COMMANDS)) cat(sprintf("  /%-8s %s\n", n, COMMANDS[[n]]$desc))
    cat("Input: text | !R code | !!R code (not sent to the model) | ```r block | \"\"\" multi-line \"\"\" | @file @object\n")
  }),
  mode = list(desc = "show or set the permission mode: plan, manual, edits, auto", fn = function(args, st) {
    if (nzchar(args)) { st$perm$mode <- match.arg(args, MODES) }
    cat("permission mode:", st$perm$mode, "\n")
  }),
  queue = list(desc = "queue a follow-up for the next run (/queue alone lists, /queue clear empties)", fn = function(args, st) {
    if (args == "clear") st$agent$follow_up <- character() else if (nzchar(args)) st$agent$queue_follow_up(args)
    cat("queued follow-ups:", if (length(st$agent$follow_up)) paste(shQuote(st$agent$follow_up), collapse = ", ") else "(none)", "\n")
  }),
  env = list(desc = "list objects in the session environment", fn = function(args, st) {
    nms <- ls(st$envir)
    if (!length(nms)) return(cat("(empty)\n"))
    for (n in nms) { o <- get(n, st$envir); cat(sprintf("  %-12s %-12s %s\n", n, class(o)[1L], format(utils::object.size(o), units = "auto"))) }
  }),
  cost = list(desc = "show usage for this session", fn = function(args, st) cat("turns:", st$agent$usage, "\n")),
  clear = list(desc = "start a new conversation (objects are kept)", fn = function(args, st) { st$agent$messages <- list(); cat("context cleared\n") }),
  exit = list(desc = "leave the REPL (also /quit, /q, Ctrl-D, Ctrl-C twice)", fn = function(args, st) "exit")
)
COMMAND_ALIASES <- c(quit = "exit", q = "exit", "?" = "help")

# ---------------------------------------------------------------------------
# The REPL
# ---------------------------------------------------------------------------
gptr_repl <- function(envir = globalenv(), reader = gptr_reader(), mode = "manual", root = getwd(),
                      out = stdout()) {
  ui <- gptr_ui_console(reader)
  st <- new.env(parent = emptyenv())
  st$envir <- envir
  st$perm <- new_permission_ctx(mode, root = root, envir = envir, ui = ui)
  st$agent <- new_fake_agent(envir, st$perm, ui, out = out)
  cat("gptr (prototype) · mode ", mode, " · /help · Ctrl-C interrupts, twice at the prompt exits\n", sep = "", file = out)
  interrupts <- 0L
  repeat {
    prompt <- if (st$perm$mode == "manual") "gptr> " else sprintf("gptr[%s]> ", st$perm$mode)
    input <- tryCatch(read_logical_input(reader, prompt), interrupt = function(e) structure("", class = "gptr_int"))
    if (inherits(input, "gptr_int")) {
      interrupts <- interrupts + 1L
      if (interrupts >= 2L) { cat("\n[gptr] bye\n", file = out); break }
      cat("\n[gptr] press Ctrl-C again to leave gptr, or type /exit\n", file = out); next
    }
    if (is.na(input)) { cat("[gptr] end of input; bye\n", file = out); break }
    interrupts <- 0L
    input <- trimws(input)
    if (!nzchar(input)) next
    if (startsWith(input, "/")) {
      cmd <- sub("^/(\\S+).*$", "\\1", input); args <- trimws(sub("^/\\S+", "", input))
      cmd <- if (cmd %in% names(COMMAND_ALIASES)) COMMAND_ALIASES[[cmd]] else cmd
      if (is.null(COMMANDS[[cmd]])) { cat("Unknown command /", cmd, ". Try /help\n", sep = "", file = out); next }
      if (identical(COMMANDS[[cmd]]$fn(args, st), "exit")) { cat("[gptr] bye\n", file = out); break }
      next
    }
    if (startsWith(input, "!")) {
      excluded <- startsWith(input, "!!")
      code <- sub("^!!?", "", input)
      res <- eval_passthrough(code, envir, out)
      if (!excluded) st$agent$add_context(sprintf("I ran R code in the session:\n```r\n%s\n```\nOutput:\n```\n%s\n```",
                                                  code, paste(res$output, collapse = "\n")))
      next
    }
    text <- expand_mentions(input, envir, root)
    if (!identical(text, input)) cat("[gptr] attached:", gsub('^<(file path|object name)="|"$', "", regmatches(text, gregexpr('<(file path|object name)="[^"]+"', text))[[1L]]), "\n", file = out)
    run_with_interrupt_menu(function() st$agent$prompt(text), st$agent, reader, out)
  }
  reader$close()
  invisible(st)
}

````

**Runner** (`e1_run.R`)

````r
for (f in c("b1_classifier.R", "c1_ui.R", "c2_permissions.R", "c3_ask_tool.R", "d1_stream.R", "e1_repl.R")) source(f)
root <- file.path(tempdir(), "proj3"); dir.create(root, showWarnings = FALSE)
writeLines(c("a,b", "1,2"), file.path(root, "data.csv"))
sess <- new.env(parent = globalenv())
cat("interactive():", interactive(), "\n")
st <- gptr_repl(envir = sess, mode = "manual", root = root)
cat("\n== after the REPL ==\nobjects in session:", ls(sess), "\n")
cat("messages in context:", length(st$agent$messages), "\n")
for (m in st$agent$messages) cat(sprintf("  %-9s %-14s %s\n", m$role, m$kind %||% "", substr(gsub("\n", " | ", m$text), 1, 90)))

````

**Piped input** (`e1_input.txt`)

````text
hello there
/help
/mode edits
!x <- c(3, 5, 10); mean(x)
!!y <- 42
!for (i in 1:2) {
  print(i)
}
what is @x in @data.csv about?
"""
line one
line two
"""
compute the average
1
delete old results
5
ask me something
2
/env
/queue then plot it
/queue clear
/nonexistent
/exit

````

**Output of Rscript --vanilla e1_run.R < e1_input.txt** (`e1_run.out`)

````text
interactive(): FALSE 
gptr (prototype) · mode manual · /help · Ctrl-C interrupts, twice at the prompt exits
gptr> hello there
You said: hello there. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
gptr> /help
Commands:
  /help     show commands and input syntax
  /mode     show or set the permission mode: plan, manual, edits, auto
  /queue    queue a follow-up for the next run (/queue alone lists, /queue clear empties)
  /env      list objects in the session environment
  /cost     show usage for this session
  /clear    start a new conversation (objects are kept)
  /exit     leave the REPL (also /quit, /q, Ctrl-D, Ctrl-C twice)
Input: text | !R code | !!R code (not sent to the model) | ```r block | """ multi-line """ | @file @object
gptr> /mode edits
permission mode: edits 
gptr[edits]> !x <- c(3, 5, 10); mean(x)
[1] 6
gptr[edits]> !!y <- 42
gptr[edits]> !for (i in 1:2) {
+   print(i)
+ }
[1] 1
[1] 2
gptr[edits]> what is @x in @data.csv about?
[gptr] attached: x data.csv 
You said: what is @x in @data.csv about?

<object name="x" class="numeric" size="80 bytes">
num [1:3] 3 5 10
</object>
<file path="data.csv">
a,b
1,2
</file>. This reply streams word by word so that it can be interrupted, steered
or aborted from the console.
gptr[edits]> """
... line one
... line two
... """
You said: line one
line two. This reply streams word by word so that it can be interrupted, steered
or aborted from the console.
gptr[edits]> compute the average

gptr wants to use r (risk 1: local). Allow?
  │ risk 1 (local)
  │   creates: avg
  │ 
  │ > avg <- mean(1:10)
  1: Yes
  2: Yes, and don't ask again this session for r(level<=1)
  3: Yes, and always allow r(level<=1) in this project
  4: No, and tell gptr what to do instead
  5: No
Choose (a number): 1
  [tool r] avg <- mean(1:10) -> allow
Tool result: ok: 5.5
gptr[edits]> delete old results

gptr wants to use r (risk 3: dangerous). Allow?
  │ risk 3 (dangerous)
  │   [3] file_delete   calls unlink [path: workspace]
  │ 
  │ > unlink('old_results', recursive = TRUE)
  1: Yes
  2: Yes, and don't ask again this session for r(fn:unlink)
  3: Yes, and always allow r(fn:unlink) in this project
  4: No, and tell gptr what to do instead
  5: No
Choose (a number): 5
  [tool r] unlink('old_results', recursive = TRUE) -> block
Tool result: The user denied this action.
gptr[edits]> ask me something
  [tool ask] questions -> allow

[Format] Table or plot?
  1: Table
  2: Plot
Choose (a number; or type your own answer): 2
Tool result: The user answered:
- Format: Plot
gptr[edits]> /env
  avg          numeric      56 bytes
  i            integer      56 bytes
  x            numeric      80 bytes
  y            numeric      56 bytes
gptr[edits]> /queue then plot it
queued follow-ups: 'then plot it' 
gptr[edits]> /queue clear
queued follow-ups: (none) 
gptr[edits]> /nonexistent
Unknown command /nonexistent. Try /help
gptr[edits]> /exit
[gptr] bye

== after the REPL ==
objects in session: avg i x y 
messages in context: 17 
  user                     hello there
  assistant                You said: hello there. This reply streams word by word so that it can be interrupted, stee
  user      r_passthrough  I ran R code in the session: | ```r | x <- c(3, 5, 10); mean(x) | ``` | Output: | ``` | [1
  user      r_passthrough  I ran R code in the session: | ```r | for (i in 1:2) { |   print(i) | } | ``` | Output: | 
  user                     what is @x in @data.csv about? |  | <object name="x" class="numeric" size="80 bytes"> |  n
  assistant                You said: what is @x in @data.csv about? |  | <object name="x" class="numeric" size="80 by
  user                     line one | line two
  assistant                You said: line one | line two. This reply streams word by word so that it can be interrupt
  user                     compute the average
  tool                     ok: 5.5
  assistant                Tool result: ok: 5.5
  user                     delete old results
  tool                     The user denied this action.
  assistant                Tool result: The user denied this action.
  user                     ask me something
  tool                     The user answered: | - Format: Plot
  assistant                Tool result: The user answered: | - Format: Plot

````

### A.8 REPL in interactive R with real SIGINTs

**Child** (`e2_child.R`)

````r
for (f in c("b1_classifier.R", "c1_ui.R", "c2_permissions.R", "c3_ask_tool.R", "d1_stream.R", "e1_repl.R")) source(f)
sess <- new.env(parent = globalenv())
cat("CHILD interactive() =", interactive(), "\n")
st <- gptr_repl(envir = sess, mode = "auto", root = tempdir())
cat("REPL EXITED; back at the R top level\n")
for (m in st$agent$messages) cat(sprintf("TRANSCRIPT %-9s %-9s %s\n", m$role, m$kind %||% "", substr(gsub("\n", " | ", m$text), 1, 70)))

````

**Driver** (`e2_driver.R`)

````r
library(processx)
p <- process$new("/usr/local/bin/R", c("--vanilla", "--interactive", "-q", "--no-echo"),
                 stdin = "|", stdout = "|", stderr = "2>&1", env = c("current", LANG = "en_US.UTF-8"))
out <- character(); seen <- 0L
pump <- function(ms = 200) { p$poll_io(ms); x <- p$read_output(); if (nzchar(x)) out <<- c(out, x) }
text <- function() paste(out, collapse = "")
wait_for <- function(pat, timeout = 20) {
  t0 <- Sys.time()
  repeat {
    pump()
    txt <- substring(text(), seen + 1L)
    if (grepl(pat, txt, fixed = TRUE)) { seen <<- seen + regexpr(pat, txt, fixed = TRUE)[[1]] + nchar(pat) - 1L; return(TRUE) }
    if (!p$is_alive() || difftime(Sys.time(), t0, units = "secs") > timeout) { cat("TIMEOUT waiting for:", pat, "\n"); return(FALSE) }
  }
}
send <- function(x) { Sys.sleep(0.15); p$write_input(paste0(x, "\n")) }
step <- function(label) cat(sprintf("---- %s\n", label))

p$write_input("source('e2_child.R')\n")
wait_for("gptr[auto]> ")
step("1. Ctrl-C mid-stream, (s)teer")
send("first question"); wait_for("You said"); Sys.sleep(0.3); p$interrupt()
wait_for("paused"); send("s"); wait_for("steer> "); send("please answer in French")
wait_for("continuing"); wait_for("gptr[auto]> ")
step("2. Ctrl-C mid-stream, (f)ollow-up")
send("second question"); wait_for("You said"); Sys.sleep(0.3); p$interrupt()
wait_for("paused"); send("f"); wait_for("follow-up> "); send("then summarise"); wait_for("gptr[auto]> ")
step("3. Ctrl-C mid-stream, (a)bort")
send("third question"); wait_for("You said"); Sys.sleep(0.3); p$interrupt()
wait_for("paused"); send("a"); wait_for("aborted"); wait_for("gptr[auto]> ")
step("4. Ctrl-C mid-stream, then Ctrl-C again while the menu waits")
send("fourth question"); wait_for("You said"); Sys.sleep(0.3); p$interrupt()
wait_for("paused"); Sys.sleep(0.3); p$interrupt(); wait_for("aborted"); wait_for("gptr[auto]> ")
step("5. Ctrl-C during the 'thinking' wait (before the first token), (c)ontinue")
send("fifth question"); Sys.sleep(0.15); p$interrupt()
wait_for("paused"); send("c"); wait_for("You said"); wait_for("gptr[auto]> ")
step("6. session still alive: R passthrough works after aborts")
send("!z <- 99; z * 2"); wait_for("[1] 198"); wait_for("gptr[auto]> ")
step("7. Ctrl-C at the prompt once (hint), then twice (exit)")
Sys.sleep(0.3); p$interrupt(); wait_for("press Ctrl-C again"); Sys.sleep(0.3); p$interrupt(); wait_for("REPL EXITED")
wait_for("TRANSCRIPT"); Sys.sleep(0.5); pump(500)
p$write_input("cat('R still alive, z =', get('z', envir = sess), '\\n'); q('no')\n")
p$wait(5000); pump(100); if (p$is_alive()) p$kill()
cat(gsub("\r", "", text()))

````

**Output of Rscript --vanilla e2_driver.R** (`e2_driver.out`)

````text
---- 1. Ctrl-C mid-stream, (s)teer
---- 2. Ctrl-C mid-stream, (f)ollow-up
---- 3. Ctrl-C mid-stream, (a)bort
---- 4. Ctrl-C mid-stream, then Ctrl-C again while the menu waits
---- 5. Ctrl-C during the 'thinking' wait (before the first token), (c)ontinue
---- 6. session still alive: R passthrough works after aborts
---- 7. Ctrl-C at the prompt once (hint), then twice (exit)
CHILD interactive() = TRUE 
gptr (prototype) · mode auto · /help · Ctrl-C interrupts, twice at the prompt exits
gptr[auto]> You said: first question. This reply streams word
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? steer> [gptr] steering message queued; continuing
 by word so that it can be
interrupted, steered or aborted from the console.
You said: please answer in French. This reply streams word by word so that it
can be interrupted, steered or aborted from the console.
gptr[auto]> You said: second question. This reply streams word
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? follow-up> [gptr] follow-up queued; continuing
 by word so that it can be
interrupted, steered or aborted from the console.
You said: then summarise. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
gptr[auto]> You said: third question. This reply streams word
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? 

[gptr] aborted; the session is kept.
gptr[auto]> You said: fourth question. This reply streams word
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? 

[gptr] aborted; the session is kept.
gptr[auto]> 
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? [gptr] continuing
You said: fifth question. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
gptr[auto]> [1] 198
gptr[auto]> 
[gptr] press Ctrl-C again to leave gptr, or type /exit
gptr[auto]> 
[gptr] bye
REPL EXITED; back at the R top level
TRANSCRIPT user                first question
TRANSCRIPT assistant           You said: first question. This reply streams word by word so that it c
TRANSCRIPT user      steer     please answer in French
TRANSCRIPT assistant           You said: please answer in French. This reply streams word by word so 
TRANSCRIPT user                second question
TRANSCRIPT assistant           You said: second question. This reply streams word by word so that it 
TRANSCRIPT user      follow_up then summarise
TRANSCRIPT assistant           You said: then summarise. This reply streams word by word so that it c
TRANSCRIPT user                third question
TRANSCRIPT user                fourth question
TRANSCRIPT user                fifth question
TRANSCRIPT assistant           You said: fifth question. This reply streams word by word so that it c
TRANSCRIPT user      r_passthrough I ran R code in the session: | ```r | z <- 99; z * 2 | ``` | Output: |
R still alive, z = 99 

````

### A.9 Paste, type-ahead and spinner in a pty

**Driver** (`e3_pty_driver.R`)

````r
library(processx)
p <- process$new("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), pty = TRUE,
                 env = c("current", TERM = "xterm-256color", LANG = "en_US.UTF-8", LC_ALL = "en_US.UTF-8", COLUMNS = "72"),
                 pty_options = list(echo = TRUE))
out <- character(); seen <- 0L
pump <- function(ms = 100) { p$poll_io(ms); x <- p$read_output(); if (nzchar(x)) out <<- c(out, x) }
txt <- function() paste(out, collapse = "")
wait_for <- function(pat, timeout = 20) {
  t0 <- Sys.time()
  repeat { pump(); t <- substring(txt(), seen + 1L)
    if (grepl(pat, t, fixed = TRUE)) { seen <<- seen + regexpr(pat, t, fixed = TRUE)[[1]] + nchar(pat) - 1L; return(invisible(TRUE)) }
    if (!p$is_alive() || difftime(Sys.time(), t0, units = "secs") > timeout) { cat("TIMEOUT:", pat, "\n"); return(invisible(FALSE)) } }
}
Sys.sleep(1); p$write_input("source('e2_child.R')\r")
wait_for("gptr[auto]> ")
# A. multi-line paste into one readline(): three lines arrive at once
p$write_input("pasted line one\rpasted line two\r")
wait_for("You said: pasted line two"); wait_for("gptr[auto]> ")
# B. type-ahead: the user types while the agent is still streaming
p$write_input("a question\r"); wait_for("thinking"); Sys.sleep(0.2)
p$write_input("typed while busy\r")
wait_for("You said: typed while busy"); wait_for("gptr[auto]> ")
p$write_input("/exit\r"); wait_for("REPL EXITED"); Sys.sleep(0.5); pump(300)
p$write_input("q('no')\r"); p$wait(3000); pump(100); if (p$is_alive()) p$kill()
raw <- txt()
cat("---- raw bytes with control characters made visible (\\r shown as <CR>, ESC as ^[) ----\n")
vis <- gsub("\033", "^[", gsub("\r", "<CR>", raw, fixed = TRUE), fixed = TRUE)
cat(gsub("<CR>\n", "\n", vis, fixed = TRUE), "\n")

````

**Output (control characters made visible)** (`e3_pty_driver.out`)

````text
---- raw bytes with control characters made visible (\r shown as <CR>, ESC as ^[) ----
^[[?1034hsource('e2_child.R')
CHILD interactive() = TRUE 
gptr (prototype) · mode auto · /help · Ctrl-C interrupts, twice at the prompt exits
gptr[auto]> pasted line one
<CR>⠋ thinking (0s, Ctrl-C to steer or stop)<CR>⠙ thinking (0s, Ctrl-C to steer or stop)<CR>⠹ thinking (0s, Ctrl-C to steer or stop)<CR>⠸ thinking (0s, Ctrl-C to steer or stop)<CR>                                                                               <CR>You said: pasted line one. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
^[[0mgptr[auto]> pasted line two
<CR>⠋ thinking (0s, Ctrl-C to steer or stop)<CR>⠙ thinking (0s, Ctrl-C to steer or stop)<CR>⠹ thinking (0s, Ctrl-C to steer or stop)<CR>⠸ thinking (0s, Ctrl-C to steer or stop)<CR>                                                                               <CR>You said: pasted line two. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
^[[0mgptr[auto]> a question
<CR>⠋ thinking (0s, Ctrl-C to steer or stop)<CR>⠙ thinking (0s, Ctrl-C to steer or stop)<CR>⠹ thinking (0s, Ctrl-C to steer or stop)typed while busy
<CR>⠸ thinking (0s, Ctrl-C to steer or stop)<CR>                                                                               <CR>You said: a question. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
^[[0mgptr[auto]> typed while busy
<CR>⠋ thinking (0s, Ctrl-C to steer or stop)<CR>⠙ thinking (0s, Ctrl-C to steer or stop)<CR>⠹ thinking (0s, Ctrl-C to steer or stop)<CR>⠸ thinking (0s, Ctrl-C to steer or stop)<CR>                                                                               <CR>You said: typed while busy. This reply streams word by word so that it can be
interrupted, steered or aborted from the console.
^[[0mgptr[auto]> /exit
[gptr] bye
REPL EXITED; back at the R top level
TRANSCRIPT user                pasted line one
TRANSCRIPT assistant           You said: pasted line one. This reply streams word by word so that it 
TRANSCRIPT user                pasted line two
TRANSCRIPT assistant           You said: pasted line two. This reply streams word by word so that it 
TRANSCRIPT user                a question
TRANSCRIPT assistant           You said: a question. This reply streams word by word so that it can b
TRANSCRIPT user                typed while busy
TRANSCRIPT assistant           You said: typed while busy. This reply streams word by word so that it
^[[?25hq('no')
 

````

### A.10 Ctrl-C at a permission prompt

`e4_child.R` is `e2_child.R` with `mode = "manual"` (`sed s/mode = "auto"/mode = "manual"/`).

**Driver** (`e4_driver.R`)

````r
library(processx)
p <- process$new("/usr/local/bin/R", c("--vanilla", "--interactive", "-q", "--no-echo"), stdin = "|", stdout = "|", stderr = "2>&1")
out <- ""
wait_for <- function(pat, timeout = 30) {
  t0 <- Sys.time()
  while (!grepl(pat, out, fixed = TRUE) && difftime(Sys.time(), t0, units = "secs") < timeout) {
    p$poll_io(100); out <<- paste0(out, p$read_output())
  }
  invisible(grepl(pat, out, fixed = TRUE))
}
p$write_input("source('e4_child.R')\n"); wait_for("gptr> ")
p$write_input("delete old results\n"); wait_for("Choose (a number)")   # permission prompt is waiting
Sys.sleep(0.3); p$interrupt()                                           # Ctrl-C at the permission prompt
wait_for("back to the prompt"); p$write_input("!cat('session alive\\n')\n"); wait_for("session alive\n")
p$write_input("/exit\n"); wait_for("REPL EXITED"); Sys.sleep(0.5); p$poll_io(200); out <- paste0(out, p$read_output())
p$write_input("q('no')\n"); p$wait(3000); if (p$is_alive()) p$kill()
cat(gsub("\r", "", out))

````

**Output** (`e4_driver.out`)

````text
[1] TRUE
  output    error  process 
 "ready" "nopipe" "nopipe" 
CHILD interactive() = TRUE 
gptr (prototype) · mode manual · /help · Ctrl-C interrupts, twice at the prompt exits
gptr> 
gptr wants to use r (risk 3: dangerous). Allow?
  │ risk 3 (dangerous)
  │   [3] file_delete   calls unlink [path: workspace]
  │ 
  │ > unlink('old_results', recursive = TRUE)
  1: Yes
  2: Yes, and don't ask again this session for r(fn:unlink)
  3: Yes, and always allow r(fn:unlink) in this project
  4: No, and tell gptr what to do instead
  5: No
Choose (a number): 
  [tool r] unlink('old_results', recursive = TRUE) -> abort
[gptr] aborted at a permission prompt; back to the prompt
gptr> session alive
gptr> [gptr] bye
REPL EXITED; back at the R top level
TRANSCRIPT user                delete old results
TRANSCRIPT user      r_passthrough I ran R code in the session: | ```r | cat('session alive\n') | ``` | O

````

### A.11 Non-interactive output, verbosity, knitr

**Source** (`f1_result.R`)

````r
# gptr prototype (track 18): context detection, verbosity, progress channel, result printing.

`%||%` <- function(a, b) if (is.null(a)) b else a

# Where are we running? Pure base R (no rlang), cheap, no side effects.
gptr_context <- function() {
  knitting <- isTRUE(getOption("knitr.in.progress"))
  testing <- identical(Sys.getenv("TESTTHAT"), "true")
  jupyter <- isTRUE(getOption("jupyter.in_kernel"))
  opt <- getOption("gptr.interactive", getOption("rlang_interactive"))
  human <- if (is.logical(opt) && length(opt) == 1L && !is.na(opt)) opt else
    interactive() && !knitting && !testing
  frontend <- if (nzchar(Sys.getenv("POSITRON")) || identical(.Platform$GUI, "Positron")) "positron"
    else if (identical(Sys.getenv("RSTUDIO"), "1")) "rstudio"
    else if (jupyter) "jupyter"
    else if (identical(.Platform$GUI, "Rgui")) "rgui"
    else if (identical(.Platform$GUI, "AQUA")) "r.app"
    else if (identical(Sys.getenv("TERM_PROGRAM"), "vscode")) "vscode-terminal"
    else if (!interactive()) "rscript"
    else "terminal"
  list(human = human, can_prompt = human || jupyter, knitting = knitting, testing = testing,
       frontend = frontend)
}

# verbosity: 0 silent, 1 progress (stderr, one line per step), 2 stream text + tool activity (console), 3 debug
gptr_verbosity <- function(ctx = gptr_context()) {
  v <- getOption("gptr.verbose")
  if (!is.null(v)) return(as.integer(v))
  if (ctx$knitting || ctx$testing) return(0L)          # never pollute rendered documents / test output
  if (ctx$human) return(2L)
  1L                                                   # Rscript, batch jobs: progress lines on stderr
}

# Progress goes through message() so it is (a) on stderr, (b) suppressible with suppressMessages(),
# (c) catchable as a condition of class gptr_progress by front ends.
gptr_progress <- function(text, verbosity = gptr_verbosity()) {
  if (verbosity < 1L) return(invisible())
  cnd <- structure(class = c("gptr_progress", "message", "condition"),
                   list(message = paste0("gptr: ", text, "\n"), call = NULL))
  message(cnd)
}

new_gptr_result <- function(text, value = NULL, usage = list(), model = "fake/model", session = "s-1",
                            streamed = FALSE, status = "complete") {
  structure(list(text = text, value = value, usage = usage, model = model, session = session,
                 status = status), class = "gptr_result", streamed = streamed)
}
format.gptr_result <- function(x, ...) x$text
as.character.gptr_result <- function(x, ...) x$text
print.gptr_result <- function(x, ..., footer = TRUE) {
  cat(x$text, "\n", sep = "")
  if (footer) {
    u <- x$usage
    line <- sprintf("# %s · %s · %d turns · %s in / %s out tokens · session %s",
                    x$status, x$model, u$turns %||% 1L, u$input %||% "?", u$output %||% "?", x$session)
    cat(if (cli::num_ansi_colors() > 1L) cli::col_grey(line) else line, "\n", sep = "")
  }
  invisible(x)
}
# knitr: emit the answer as markdown into the document (registered lazily, knitr is Suggests)
knit_print.gptr_result <- function(x, ...) knitr::asis_output(paste0(x$text, "\n"))
.onLoad_register <- function() {
  if (requireNamespace("knitr", quietly = TRUE))
    registerS3method("knit_print", "gptr_result", knit_print.gptr_result, envir = asNamespace("knitr"))
}

# A stand-in for gptr("prompt"): progress + (optional) streaming + visibility rule.
fake_gptr <- function(prompt) {
  ctx <- gptr_context(); v <- gptr_verbosity(ctx)
  gptr_progress(sprintf("run started (%s)", substr(prompt, 1, 40)), v)
  gptr_progress("tool r: fit <- lm(mpg ~ wt, mtcars)  [allowed: mode auto]", v)
  text <- "The slope is **-5.34** mpg per 1000 lb; R² = 0.75."
  streamed <- FALSE
  if (v >= 2L) { cat(text, "\n", sep = ""); streamed <- TRUE }   # (really: md_stream while tokens arrive)
  gptr_progress("done in 2.1 s, 1.2k tokens", v)
  res <- new_gptr_result(text, usage = list(turns = 2L, input = "1.1k", output = "0.1k"), streamed = streamed)
  # already shown on the console -> return invisibly so autoprint does not repeat it
  if (streamed) invisible(res) else res
}

````

**Script** (`f1_script.R`)

````r
source("f1_result.R")
str(gptr_context()); cat("verbosity:", gptr_verbosity(), "\n")
r <- fake_gptr("fit a model of mpg on wt")
print(r)
suppressMessages(r2 <- fake_gptr("quiet please"))
withCallingHandlers(fake_gptr("front end"), gptr_progress = function(m) { cat("[front end saw progress]", conditionMessage(m)); invokeRestart("muffleMessage") })

````

**Document** (`f1_doc.Rmd`)

````markdown
---
title: test
---

```{r}
source("f1_result.R"); .onLoad_register()
str(gptr_context()[c("human", "knitting", "frontend")]); gptr_verbosity()
fake_gptr("summarise mtcars")
```

````

**Outputs (Rscript 2>&1, Rscript 2>/dev/null, knitr::knit)** (`f1.out`)

````text
List of 5
 $ human     : logi FALSE
 $ can_prompt: logi FALSE
 $ knitting  : logi FALSE
 $ testing   : logi FALSE
 $ frontend  : chr "rscript"
verbosity: 1 
gptr: run started (fit a model of mpg on wt)
gptr: tool r: fit <- lm(mpg ~ wt, mtcars)  [allowed: mode auto]
gptr: done in 2.1 s, 1.2k tokens
The slope is **-5.34** mpg per 1000 lb; R² = 0.75.
# complete · fake/model · 2 turns · 1.1k in / 0.1k out tokens · session s-1
[front end saw progress] gptr: run started (front end)
[front end saw progress] gptr: tool r: fit <- lm(mpg ~ wt, mtcars)  [allowed: mode auto]
[front end saw progress] gptr: done in 2.1 s, 1.2k tokens
The slope is **-5.34** mpg per 1000 lb; R² = 0.75.
# complete · fake/model · 2 turns · 1.1k in / 0.1k out tokens · session s-1
=== stdout only
List of 5
 $ human     : logi FALSE
 $ can_prompt: logi FALSE
 $ knitting  : logi FALSE
 $ testing   : logi FALSE
 $ frontend  : chr "rscript"
verbosity: 1 
The slope is **-5.34** mpg per 1000 lb; R² = 0.75.
# complete · fake/model · 2 turns · 1.1k in / 0.1k out tokens · session s-1
[front end saw progress] gptr: run started (front end)
[front end saw progress] gptr: tool r: fit <- lm(mpg ~ wt, mtcars)  [allowed: mode auto]
[front end saw progress] gptr: done in 2.1 s, 1.2k tokens
The slope is **-5.34** mpg per 1000 lb; R² = 0.75.
# complete · fake/model · 2 turns · 1.1k in / 0.1k out tokens · session s-1
=== knitr
---
title: test
---


``` r
source("f1_result.R"); .onLoad_register()
str(gptr_context()[c("human", "knitting", "frontend")]); gptr_verbosity()
```

```
## List of 3
##  $ human   : logi FALSE
##  $ knitting: logi TRUE
##  $ frontend: chr "rscript"
```

```
## [1] 0
```

``` r
fake_gptr("summarise mtcars")
```

The slope is **-5.34** mpg per 1000 lb; R² = 0.75.

````

### A.12 Abort cancels the HTTP stream

**Server** (`g1_server.R`)

````r
# Minimal slow HTTP streaming server (base R sockets). Logs when the client goes away.
args <- commandArgs(TRUE); port <- as.integer(args[1]); log <- args[2]
lg <- function(...) cat(format(Sys.time(), "%H:%M:%OS2"), ..., "\n", file = log, append = TRUE)
srv <- serverSocket(port)
for (conn_no in 1:2) {
  con <- socketAccept(srv, blocking = TRUE, open = "r+b")
  repeat { l <- readLines(con, n = 1); if (!length(l) || !nzchar(l)) break }
  lg("request", conn_no, "accepted")
  writeLines(c("HTTP/1.1 200 OK", "Content-Type: text/event-stream", "Connection: close", ""), con, sep = "\r\n")
  for (i in 1:60) {
    ok <- tryCatch({ writeBin(charToRaw(sprintf("data: token %d\n\n", i)), con); flush(con); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) { lg("request", conn_no, "client disconnected before token", i); break }
    Sys.sleep(0.15)
  }
  if (ok) lg("request", conn_no, "completed all tokens")
  close(con)
}

````

**Client (child, interactive R)** (`g1_client_child.R`)

````r
source("c1_ui.R"); source("e1_repl.R")
stream_sse <- function(url, on_text) {
  h <- curl::new_handle(url = url)
  pool <- curl::new_pool()
  done <- FALSE
  curl::multi_add(h, pool = pool,
                  data = function(x, final) on_text(rawToChar(x)),
                  done = function(res) done <<- TRUE, fail = function(msg) { done <<- TRUE })
  on.exit({ curl::multi_cancel(h); cat("[transport] request cancelled/cleaned up\n") }, add = TRUE)
  while (!done) curl::multi_run(timeout = 0.05, poll = TRUE, pool = pool)
  invisible()
}
agent <- new.env(); agent$steering <- character(); agent$follow_up <- character()
agent$steer <- function(x) agent$steering <- c(agent$steering, x); agent$queue_follow_up <- agent$steer
reader <- gptr_reader()
url <- commandArgs(TRUE)[1]
for (k in 1:2) {
  cat("STREAM", k, "START\n")
  r <- run_with_interrupt_menu(function() stream_sse(url, function(t) { cat(gsub("data: |\n\n", " ", t)); flush(stdout()) }), agent, reader)
  cat("\nSTREAM", k, "RESULT:", r, "\n")
}
cat("CHILD DONE\n")

````

**Driver** (`g1_driver.R`)

````r
library(processx)
port <- 18821L; log <- file.path(getwd(), "g1_server.log"); unlink(log)
srv <- process$new("/usr/local/bin/Rscript", c("--vanilla", "g1_server.R", port, log), stdout = "|", stderr = "2>&1")
Sys.sleep(1.5)
p <- process$new("/usr/local/bin/R", c("--vanilla", "--interactive", "-q", "--no-echo", "--args", sprintf("http://127.0.0.1:%d/", port)),
                 stdin = "|", stdout = "|", stderr = "2>&1")
out <- ""; pump <- function(s) { t0 <- Sys.time(); while (difftime(Sys.time(), t0, units = "secs") < s) { p$poll_io(100); out <<- paste0(out, p$read_output()) } }
p$write_input("source('g1_client_child.R')\n")
pump(2.2)                       # stream 1 runs ~2 s ...
p$interrupt(); pump(0.8)        # ... user presses Ctrl-C
p$write_input("a\n"); pump(1)   # ... and chooses (a)bort
pump(10)                        # stream 2 runs to completion (60 tokens * 0.15 s = 9 s)
p$write_input("q('no')\n"); p$wait(3000); if (p$is_alive()) p$kill()
srv$wait(3000); if (srv$is_alive()) srv$kill()
cat("==== client console\n"); cat(out, "\n")
cat("==== server log\n"); cat(readLines(log), sep = "\n")

````

**Output** (`g1_driver.out`)

````text
==== client console
STREAM 1 START
 token 1  token 2  token 3  token 4  token 5  token 6  token 7  token 8 
[gptr] paused: (s)teer, (f)ollow-up, (a)bort, (c)ontinue? [transport] request cancelled/cleaned up

[gptr] aborted; the session is kept.

STREAM 1 RESULT: aborted 
STREAM 2 START
 token 1  token 2  token 3  token 4  token 5  token 6  token 7  token 8  token 9  token 10  token 11  token 12  token 13  token 14  token 15  token 16  token 17  token 18  token 19  token 20  token 21  token 22  token 23  token 24  token 25  token 26  token 27  token 28  token 29  token 30  token 31  token 32  token 33  token 34  token 35  token 36  token 37  token 38  token 39  token 40  token 41  token 42  token 43  token 44  token 45  token 46  token 47  token 48  token 49  token 50  token 51  token 52  token 53  token 54  token 55  token 56  token 57  token 58  token 59  token 60 [transport] request cancelled/cleaned up

STREAM 2 RESULT: done 
CHILD DONE
 
==== server log
19:04:59.60 request 1 accepted 
19:05:01.94 request 1 client disconnected before token 14 
19:05:01.95 request 2 accepted 
19:05:11.24 request 2 completed all tokens 

````

### A.13 Undo snapshot cost

**Source** (`h1_snapshot.R`)

````r
mb <- function() sum(gc()[, 2])                     # "used (Mb)" column
env <- new.env(); env$big <- rnorm(5e7)             # ~381 MB
m0 <- mb()
snap <- mget("big", envir = env)                     # snapshot before the agent overwrites `big`
m1 <- mb()
env$big <- env$big[1:10]                             # agent code: big <- big[1:10]
m2 <- mb()
cat(sprintf("after snapshot: +%.0f MB (no copy); after overwrite: old value kept alive by snapshot, total %.0f MB\n", m1 - m0, m2))
assign("big", snap$big, envir = env); rm(snap)       # /undo
cat("restored length:", length(env$big), "\n")
t0 <- Sys.time(); s <- utils::object.size(env$big); cat("object.size of 381 MB numeric:", format(s, units = "MB"), "in", round(as.numeric(Sys.time() - t0), 4), "s\n")
l <- replicate(2e5, list(a = 1, b = "x"), simplify = FALSE)
t0 <- Sys.time(); s <- utils::object.size(l); cat("object.size of a 200k-element nested list:", format(s, units = "MB"), "in", round(as.numeric(Sys.time() - t0), 3), "s\n")

````

**Output** (`h1_snapshot.out`)

````text
after snapshot: +4 MB (no copy); after overwrite: old value kept alive by snapshot, total 406 MB
restored length: 50000000 
object.size of 381 MB numeric: 381.5 Mb in 4e-04 s
object.size of a 200k-element nested list: 100.7 Mb in 0.114 s

````

### A.14 Console mechanics experiments

**stdin readers (previous researcher)** (`a1_stdin.R`)

````r
# A1: how to read piped stdin under Rscript
cat("interactive():", interactive(), "\n")
cat("rlang::is_interactive():", rlang::is_interactive(), "\n")
cat("isatty(stdin()):", isatty(stdin()), " isatty(stdout()):", isatty(stdout()), " isatty(stderr()):", isatty(stderr()), "\n")
r1 <- readline("prompt> ")
cat("\nreadline() ->", deparse(r1), "\n")
# fresh file("stdin") each call
for (i in 1:3) {
  con <- file("stdin")
  x <- readLines(con, n = 1L)
  close(con)
  cat(sprintf("fresh file('stdin') call %d -> %s\n", i, deparse(x)))
}

````

**persistent connection** (`a1b_stdin.R`)

````r
# persistent connection
con <- file("stdin", open = "r")
for (i in 1:5) {
  x <- readLines(con, n = 1L)
  cat(sprintf("persistent call %d -> %s (length %d)\n", i, deparse(x), length(x)))
}
close(con)

````

**stdin() and scan** (`a1c_stdin.R`)

````r
# stdin() connection under Rscript file.R
for (i in 1:3) {
  x <- readLines(stdin(), n = 1L)
  cat(sprintf("stdin() call %d -> %s (length %d)\n", i, deparse(x), length(x)))
}
x <- scan(file = "stdin", what = "", n = 1, quiet = TRUE, sep = "\n")
cat("scan('stdin') ->", deparse(x), "\n")

````

**Outputs** (`a1.out`)

````text
$ printf "line one
line two
line three
line four
" | Rscript --vanilla a1_stdin.R
interactive(): FALSE 
rlang::is_interactive(): FALSE 
isatty(stdin()): FALSE  isatty(stdout()): FALSE  isatty(stderr()): FALSE 
prompt> 

readline() -> "" 
fresh file('stdin') call 1 -> "line one"
fresh file('stdin') call 2 -> character(0)
fresh file('stdin') call 3 -> character(0)
$ printf "line one
line two
line three
" | Rscript --vanilla a1b_stdin.R
persistent call 1 -> "line one" (length 1)
persistent call 2 -> "line two" (length 1)
persistent call 3 -> "line three" (length 1)
persistent call 4 -> character(0) (length 0)
persistent call 5 -> character(0) (length 0)
$ printf "line one
line two
line three
line four
" | Rscript --vanilla a1c_stdin.R
stdin() call 1 -> "x <- scan(file = \"stdin\", what = \"\", n = 1, quiet = TRUE, sep = \"\\n\")" (length 1)
stdin() call 2 -> "cat(\"scan('stdin') ->\", deparse(x), \"\\n\")" (length 1)
stdin() call 3 -> character(0) (length 0)

````

**Terminal capability probe (child)** (`a2_tty.R`)

````r
suppressPackageStartupMessages(library(cli))
f <- function(...) cat(sprintf(...), "\n", sep = "", file = stderr())
f("interactive()=%s rlang::is_interactive()=%s", interactive(), rlang::is_interactive())
f("isatty stdin=%s stdout=%s stderr=%s", isatty(stdin()), isatty(stdout()), isatty(stderr()))
f("cli::num_ansi_colors()=%s  (stderr: %s)", cli::num_ansi_colors(), cli::num_ansi_colors(stderr()))
f("cli::is_ansi_tty()=%s  (stderr: %s)", cli::is_ansi_tty(), cli::is_ansi_tty(stderr()))
f("cli::is_dynamic_tty()=%s  (stderr: %s)", cli::is_dynamic_tty(), cli::is_dynamic_tty(stderr()))
f("cli::is_utf8_output()=%s", cli::is_utf8_output())
f("cli::console_width()=%s getOption('width')=%s COLUMNS=%s", cli::console_width(), getOption("width"), Sys.getenv("COLUMNS", "<unset>"))
f("cli::ansi_has_hyperlink_support()=%s", cli::ansi_has_hyperlink_support())
f("TERM=%s NO_COLOR=%s COLORTERM=%s RSTUDIO=%s POSITRON=%s TERM_PROGRAM=%s", Sys.getenv("TERM"), Sys.getenv("NO_COLOR","<unset>"), Sys.getenv("COLORTERM","<unset>"), Sys.getenv("RSTUDIO","<unset>"), Sys.getenv("POSITRON","<unset>"), Sys.getenv("TERM_PROGRAM","<unset>"))
f("crayon-style opts: cli.num_colors=%s crayon.enabled=%s cli.dynamic=%s cli.ansi=%s", deparse(getOption("cli.num_colors")), deparse(getOption("crayon.enabled")), deparse(getOption("cli.dynamic")), deparse(getOption("cli.ansi")))

````

**pty driver** (`a2_pty_driver.R`)

````r
library(processx)
run_pty <- function(cmd, args, env = character(), input = NULL, wait = 6) {
  p <- process$new(cmd, args, pty = TRUE, env = c("current", env), pty_options = list(echo = FALSE))
  out <- character()
  if (!is.null(input)) { Sys.sleep(1); for (l in input) { p$write_input(l); Sys.sleep(0.4) } }
  t0 <- Sys.time()
  while (p$is_alive() && difftime(Sys.time(), t0, units = "secs") < wait) { p$poll_io(300); out <- c(out, p$read_output()) }
  out <- c(out, tryCatch(p$read_output(), error = function(e) ""))
  if (p$is_alive()) p$kill()
  paste(out, collapse = "")
}
cat("=== Rscript in a pty, TERM=xterm-256color, LANG=en_US.UTF-8\n")
cat(run_pty("/usr/local/bin/Rscript", c("--vanilla", "a2_tty.R"), env = c(TERM = "xterm-256color", LANG = "en_US.UTF-8", COLORTERM = "truecolor")))
cat("=== Rscript in a pty, TERM=dumb\n")
cat(run_pty("/usr/local/bin/Rscript", c("--vanilla", "a2_tty.R"), env = c(TERM = "dumb", LANG = "en_US.UTF-8")))
cat("=== Rscript in a pty, NO_COLOR=1\n")
cat(run_pty("/usr/local/bin/Rscript", c("--vanilla", "a2_tty.R"), env = c(TERM = "xterm-256color", NO_COLOR = "1", LANG = "en_US.UTF-8")))
cat("=== interactive R in a pty\n")
cat(run_pty("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), env = c(TERM = "xterm-256color", LANG = "en_US.UTF-8"), input = c("source('a2_tty.R')\n", "q('no')\n")))
cat("=== simulated RStudio env (RSTUDIO=1) piped: cli heuristics\n")

````

**Output (cat -v)** (`a2.out`)

````text
=== Rscript in a pty, TERM=xterm-256color, LANG=en_US.UTF-8
^[[?25h^[[?25hinteractive()=FALSE rlang::is_interactive()=FALSE^M
^[[?25hisatty stdin=TRUE stdout=TRUE stderr=TRUE^M
^[[?25hcli::num_ansi_colors()=16777216  (stderr: 16777216)^M
^[[?25hcli::is_ansi_tty()=TRUE  (stderr: TRUE)^M
^[[?25hcli::is_dynamic_tty()=TRUE  (stderr: TRUE)^M
^[[?25hcli::is_utf8_output()=TRUE^M
^[[?25hcli::console_width()=80 getOption('width')=80 COLUMNS=<unset>^M
^[[?25hcli::ansi_has_hyperlink_support()=FALSE^M
^[[?25hTERM=xterm-256color NO_COLOR=<unset> COLORTERM=truecolor RSTUDIO=<unset> POSITRON=<unset> TERM_PROGRAM=<unset>^M
^[[?25hcrayon-style opts: cli.num_colors=NULL crayon.enabled=NULL cli.dynamic=NULL cli.ansi=NULL^M
^[[?25h^[[?25h=== Rscript in a pty, TERM=dumb
interactive()=FALSE rlang::is_interactive()=FALSE^M
isatty stdin=TRUE stdout=TRUE stderr=TRUE^M
cli::num_ansi_colors()=1  (stderr: 1)^M
cli::is_ansi_tty()=FALSE  (stderr: FALSE)^M
cli::is_dynamic_tty()=TRUE  (stderr: TRUE)^M
cli::is_utf8_output()=TRUE^M
cli::console_width()=80 getOption('width')=80 COLUMNS=<unset>^M
cli::ansi_has_hyperlink_support()=FALSE^M
TERM=dumb NO_COLOR=<unset> COLORTERM=<unset> RSTUDIO=<unset> POSITRON=<unset> TERM_PROGRAM=<unset>^M
crayon-style opts: cli.num_colors=NULL crayon.enabled=NULL cli.dynamic=NULL cli.ansi=NULL^M
=== Rscript in a pty, NO_COLOR=1
^[[?25h^[[?25hinteractive()=FALSE rlang::is_interactive()=FALSE^M
^[[?25hisatty stdin=TRUE stdout=TRUE stderr=TRUE^M
^[[?25hcli::num_ansi_colors()=1  (stderr: 1)^M
^[[?25hcli::is_ansi_tty()=TRUE  (stderr: TRUE)^M
^[[?25hcli::is_dynamic_tty()=TRUE  (stderr: TRUE)^M
^[[?25hcli::is_utf8_output()=TRUE^M
^[[?25hcli::console_width()=80 getOption('width')=80 COLUMNS=<unset>^M
^[[?25hcli::ansi_has_hyperlink_support()=FALSE^M
^[[?25hTERM=xterm-256color NO_COLOR=1 COLORTERM=<unset> RSTUDIO=<unset> POSITRON=<unset> TERM_PROGRAM=<unset>^M
^[[?25hcrayon-style opts: cli.num_colors=NULL crayon.enabled=NULL cli.dynamic=NULL cli.ansi=NULL^M
^[[?25h^[[?25h=== interactive R in a pty
^[[?1034h^[[1minteractive()=TRUE rlang::is_interactive()=TRUE^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1misatty stdin=TRUE stdout=TRUE stderr=TRUE^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::num_ansi_colors()=256  (stderr: 256)^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::is_ansi_tty()=TRUE  (stderr: TRUE)^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::is_dynamic_tty()=TRUE  (stderr: TRUE)^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::is_utf8_output()=TRUE^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::console_width()=80 getOption('width')=80 COLUMNS=80^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcli::ansi_has_hyperlink_support()=FALSE^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mTERM=xterm-256color NO_COLOR=<unset> COLORTERM=<unset> RSTUDIO=<unset> POSITRON=<unset> TERM_PROGRAM=<unset>^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[1mcrayon-style opts: cli.num_colors=NULL crayon.enabled=NULL cli.dynamic=NULL cli.ansi=NULL^[[0m^[[1m^[[0m^[[1m^M
^[[0m^[[?25h^[[?25h=== simulated RStudio env (RSTUDIO=1) piped: cli heuristics

````

**Parser quirks** (`a3_parse_quirks.R`)

````r
# How does the R parser represent tricky call forms?
show <- function(code) {
  e <- parse(text = code, keep.source = FALSE)[[1]]
  h <- e[[1]]
  cat(sprintf("%-38s head type=%-9s head=%s\n", code, typeof(h), paste(deparse(h), collapse = "")))
}
show('unlink("x")')
show('`unlink`("x")')
show('"unlink"("x")')
show("'unlink'('x')")
show('base::unlink("x")')
show('base:::unlink("x")')
show('base::`unlink`("x")')
show('"base"::"unlink"("x")')
show('get("system")("ls")')
show('(unlink)("x")')
show('(function(f) f("x"))(unlink)')
show('x -> y')
show('x ->> y')
show('y <<- x')
show('y = x')
show('f(x) <- 1')
show('x$a[[2]]$b <- 1')
show('x |> unlink()')
show('x %>% unlink()')
show('\\(x) unlink(x)')
show('if (TRUE) unlink("x")')
show('`<-`(y, 1)')
show('`if`(TRUE, unlink("x"))')
cat("\nall.names on pipe: "); print(all.names(parse(text = 'f <- unlink; lapply(files, file.remove); x |> base::system()')))
cat("all.vars: "); print(all.vars(parse(text = 'f <- unlink; lapply(files, file.remove); x |> base::system()')))
pd <- getParseData(parse(text = '`unlink`("a"); base::system("ls"); "quit"()', keep.source = TRUE))
print(pd[pd$terminal, c("line1", "col1", "token", "text")])
cat("\ncodetools::findGlobals:\n")
print(codetools::findGlobals(function() { f <- unlink; lapply(files, file.remove); base::system("ls"); get("q")() }, merge = FALSE))

````

**Output** (`a3.out`)

````text
unlink("x")                            head type=symbol    head=unlink
`unlink`("x")                          head type=symbol    head=unlink
"unlink"("x")                          head type=symbol    head=unlink
'unlink'('x')                          head type=symbol    head=unlink
base::unlink("x")                      head type=language  head=base::unlink
base:::unlink("x")                     head type=language  head=base:::unlink
base::`unlink`("x")                    head type=language  head=base::unlink
"base"::"unlink"("x")                  head type=language  head="base"::"unlink"
get("system")("ls")                    head type=language  head=get("system")
(unlink)("x")                          head type=language  head=(unlink)
(function(f) f("x"))(unlink)           head type=language  head=(function(f) f("x"))
x -> y                                 head type=symbol    head=<-
x ->> y                                head type=symbol    head=<<-
y <<- x                                head type=symbol    head=<<-
y = x                                  head type=symbol    head==
f(x) <- 1                              head type=symbol    head=<-
x$a[[2]]$b <- 1                        head type=symbol    head=<-
x |> unlink()                          head type=symbol    head=unlink
x %>% unlink()                         head type=symbol    head=%>%
\(x) unlink(x)                         head type=symbol    head=function
if (TRUE) unlink("x")                  head type=symbol    head=if
`<-`(y, 1)                             head type=symbol    head=<-
`if`(TRUE, unlink("x"))                head type=symbol    head=if

all.names on pipe:  [1] "<-"          "f"           "unlink"      "lapply"      "files"      
 [6] "file.remove" "::"          "base"        "system"      "x"          
all.vars: [1] "f"           "unlink"      "files"       "file.remove" "x"          
   line1 col1                token     text
1      1    1 SYMBOL_FUNCTION_CALL `unlink`
2      1    9                  '('        (
4      1   10            STR_CONST      "a"
5      1   13                  ')'        )
11     1   14                  ';'        ;
14     1   16       SYMBOL_PACKAGE     base
15     1   20               NS_GET       ::
16     1   22 SYMBOL_FUNCTION_CALL   system
18     1   28                  '('        (
19     1   29            STR_CONST     "ls"
20     1   33                  ')'        )
26     1   34                  ';'        ;
29     1   36            STR_CONST   "quit"
30     1   42                  '('        (
32     1   43                  ')'        )

codetools::findGlobals:
$functions
[1] "::"     "{"      "<-"     "get"    "lapply"

$variables
[1] "file.remove" "files"       "unlink"     


````

**stderr bold on macOS** (`a4_stderr_bold.R`)

````r
library(processx)
p <- process$new("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), pty = TRUE,
  env = c("current", TERM = "xterm-256color", LANG = "en_US.UTF-8"), pty_options = list(echo = FALSE))
Sys.sleep(1)
p$write_input("message('to-stderr'); cat('to-stdout\\n'); Sys.getenv('R_HOME'); q('no')\n")
out <- character(); t0 <- Sys.time()
while (p$is_alive() && difftime(Sys.time(), t0, units = "secs") < 5) { p$poll_io(300); out <- c(out, p$read_output()) }
cat(paste(out, collapse = ""))

````

**Output (cat -v)** (`a4.out`)

````text
^[[?1034h^[[1mto-stderr^M
^[[0mto-stdout^M
[1] "/Library/Frameworks/R.framework/Resources"^M

````

**History child** (`a5_history_child.R`)

````r
a <- readline("first> ")
cat("GOT1:", a, "\n")
b <- readline("second (press Up) > ")
cat("GOT2:", b, "\n")
utils::timestamp(stamp = "added via timestamp()", prefix = "", suffix = "", quiet = TRUE)
d <- readline("third (press Up) > ")
cat("GOT3:", d, "\n")

````

**History driver** (`a5_history_driver.R`)

````r
library(processx)
p <- process$new("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), pty = TRUE,
                 env = c("current", TERM = "xterm-256color", LANG = "en_US.UTF-8", LC_ALL = "en_US.UTF-8"), pty_options = list(echo = TRUE))
out <- ""; pump <- function(s = 1) { t0 <- Sys.time(); while (difftime(Sys.time(), t0, units = "secs") < s) { p$poll_io(100); out <<- paste0(out, p$read_output()) } }
pump(1); p$write_input("source('a5_history_child.R')\r"); pump(1)
p$write_input("hello from readline\r"); pump(0.7)
p$write_input("\033[A\r"); pump(0.7)          # Up arrow then Enter at the second prompt
p$write_input("\033[A\r"); pump(0.7)          # Up arrow then Enter at the third prompt
p$write_input("q('no')\r"); pump(1); if (p$is_alive()) p$kill()
cat(gsub("\033", "^[", gsub("\r", "", out), fixed = TRUE))

````

**Output** (`a5.out`)

````text
GOT1: hello from readline 
GOT2: source('a5_history_child.R') 
GOT3: added via timestamp() 

````

**Base prompt functions non-interactively** (`a7_prompts.R`)

````r
cat("interactive():", interactive(), "\n")
r <- tryCatch(utils::menu(c("a", "b")), error = function(e) paste("ERROR:", conditionMessage(e))); cat("menu() ->", r, "\n")
r <- utils::askYesNo("Delete everything?"); cat("askYesNo() default=TRUE ->", r, "\n")
r <- utils::askYesNo("Delete everything?", default = FALSE); cat("askYesNo(default = FALSE) ->", r, "\n")
r <- readline("readline> "); cat("readline() ->", deparse(r), "\n")
r <- tryCatch(utils::select.list(c("a", "b")), error = function(e) paste("ERROR:", conditionMessage(e))); cat("select.list() ->", deparse(r), "\n")

````

**Output of echo y | Rscript --vanilla a7_prompts.R** (`a7.out`)

````text
interactive(): FALSE 
menu() -> ERROR: menu() cannot be used non-interactively 
Delete everything? (Yes/no/cancel) 
askYesNo() default=TRUE -> TRUE 
Delete everything? (yes/No/cancel) 
askYesNo(default = FALSE) -> FALSE 
readline> 
readline() -> "" 
select.list() -> "ERROR: select.list() cannot be used non-interactively" 

````

**Ctrl-D child** (`a8_ctrld_child.R`)

````r
x <- readline("prompt> ")
cat("readline returned:", deparse(x), " nchar =", nchar(x), "\n")
cat("STILL ALIVE\n")

````

**Ctrl-D driver** (`a8_ctrld_driver.R`)

````r
library(processx)
run <- function(keys, label) {
  p <- process$new("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), pty = TRUE,
                   env = c("current", TERM = "xterm-256color", LANG = "en_US.UTF-8", LC_ALL = "en_US.UTF-8"), pty_options = list(echo = TRUE))
  out <- ""; pump <- function(s = 1) { t0 <- Sys.time(); while (difftime(Sys.time(), t0, units = "secs") < s) { p$poll_io(100); out <<- paste0(out, p$read_output()) } }
  pump(1); p$write_input("source('a8_ctrld_child.R')\r"); pump(1)
  p$write_input(keys); pump(1.5)
  alive <- p$is_alive()
  if (alive) { p$write_input("cat('R top level OK\\n')\r"); pump(1); p$write_input("q('no')\r"); pump(1); if (p$is_alive()) p$kill() }
  cat("=====", label, "| R process alive after keys:", alive, "\n")
  cat(gsub("\033\\[[0-9;?]*[A-Za-z]", "", gsub("\r", "", out)), "\n")
}
run("\004", "Ctrl-D on an empty readline() prompt")
run("abc\004\r", "Ctrl-D after typing text, then Enter")

````

**Output** (`a8.out`)

````text
===== Ctrl-D on an empty readline() prompt | R process alive after keys: TRUE 
source('a8_ctrld_child.R')
prompt> readline returned: ""  nchar = 0 
STILL ALIVE
cat('R top level OK\n')
R top level OK
q('no')
 
===== Ctrl-D after typing text, then Enter | R process alive after keys: TRUE 
source('a8_ctrld_child.R')
prompt> abc
readline returned: "abc"  nchar = 3 
STILL ALIVE
cat('R top level OK\n')
R top level OK
q('no')
 

````

**Flushing and cli spinner ticks** (`a9_flush_driver.R`)

````r
library(processx)
arrivals <- function(code, pty = FALSE) {
  p <- process$new("/usr/local/bin/Rscript", c("--vanilla", "-e", code), stdout = if (pty) NULL else "|", stderr = if (pty) NULL else "|", pty = pty)
  t0 <- Sys.time(); ev <- character()
  while (p$is_alive() || (!pty && p$is_incomplete_output())) {
    p$poll_io(50); x <- p$read_output()
    if (nzchar(x)) ev <- c(ev, sprintf("%.1fs:%s", as.numeric(difftime(Sys.time(), t0, units = "secs")), gsub("\r|\n", "|", x)))
    if (difftime(Sys.time(), t0, units = "secs") > 8) break
  }
  paste(ev, collapse = "  ")
}
cat("pipe, cat() without flush :", arrivals("for (i in 1:4) { cat(i, ''); Sys.sleep(0.4) }"), "\n")
cat("pipe, cat() + flush(stdout()):", arrivals("for (i in 1:4) { cat(i, ''); flush(stdout()); Sys.sleep(0.4) }"), "\n")
cat("pty,  cat() without flush :", arrivals("for (i in 1:4) { cat(i, ''); Sys.sleep(0.4) }", pty = TRUE), "\n")
cat("pty,  cli_progress_step with no ticks during a 2 s blocking wait:\n")
cat("   ", gsub("\033", "^[", arrivals("cli::cli_progress_step('Waiting for the model', spinner = TRUE); Sys.sleep(2); cli::cli_progress_done()", pty = TRUE)), "\n")
cat("pty,  cli_progress_step ticked with cli_progress_update() every 0.1 s:\n")
cat("   ", gsub("\033", "^[", arrivals("cli::cli_progress_step('Waiting for the model', spinner = TRUE); for (i in 1:20) { Sys.sleep(0.1); cli::cli_progress_update() }; cli::cli_progress_done()", pty = TRUE)), "\n")

````

**Output** (`a9.out`)

````text
pipe, cat() without flush : 0.2s:1   0.6s:2   1.0s:3   1.4s:4  
pipe, cat() + flush(stdout()): 0.2s:1   0.6s:2   1.0s:3   1.4s:4  
pty,  cat() without flush : 0.2s:1   0.6s:2   1.0s:3   1.5s:4  
pty,  cli_progress_step with no ticks during a 2 s blocking wait:
    0.5s:|⠙ Waiting for the model^[[K|  0.5s:^[[?25h  2.5s:^[[?25h  2.5s:|✔ Waiting for the model [2.1s]^[[K|||^[[?25h^[[?25h  2.5s:^[[?25h 
pty,  cli_progress_step ticked with cli_progress_update() every 0.1 s:
    0.3s:|⠙ Waiting for the model^[[K|^[[?25h  0.5s:|⠹ Waiting for the model^[[K|  0.6s:|⠸ Waiting for the model^[[K|  0.8s:|⠼ Waiting for the model^[[K|  1.0s:|⠴ Waiting for the model^[[K|  1.3s:|⠦ Waiting for the model^[[K|  1.5s:|⠧ Waiting for the model^[[K|  1.7s:|⠇ Waiting for the model^[[K|  1.9s:|⠏ Waiting for the model^[[K|  2.1s:|⠋ Waiting for the model^[[K|  2.3s:|⠙ Waiting for the model^[[K|  2.4s:^[[?25h  2.4s:|✔ Waiting for the model [2.2s]^[[K|||^[[?25h^[[?25h^[[?25h 

````

**Long line child** (`a10_long_child.R`)

````r
for (i in 1:4) { x <- readline(sprintf("[p%d]", i)); cat(sprintf("<got %d: nchar=%d head=%s>\n", i, nchar(x), substr(x, 1, 6))) }
cat("CHILD END\n")

````

**Long line driver** (`a10_long_driver.R`)

````r
library(processx)
for (mode in c("pipe", "pty")) {
  if (mode == "pty") p <- process$new("/usr/local/bin/R", c("--vanilla", "-q", "--no-echo"), pty = TRUE, env = c("current", TERM = "xterm"), pty_options = list(echo = FALSE))
  else p <- process$new("/usr/local/bin/R", c("--vanilla", "--interactive", "-q", "--no-echo"), stdin = "|", stdout = "|", stderr = "2>&1")
  out <- ""; pump <- function(s = 1) { t0 <- Sys.time(); while (difftime(Sys.time(), t0, units = "secs") < s) { p$poll_io(100); out <<- paste0(out, p$read_output()) } }
  nl <- if (mode == "pty") "\r" else "\n"
  pump(1); p$write_input(paste0("source('a10_long_child.R')", nl)); pump(1)
  long <- paste(rep("abcdefghij", 600), collapse = "")
  for (k in seq(1, nchar(long), by = 500)) { p$write_input(substr(long, k, k + 499)); pump(0.05) }
  p$write_input(nl); pump(1); p$write_input(paste0("second", nl)); pump(1); p$write_input(paste0("third", nl)); pump(1); p$write_input(paste0("fourth", nl)); pump(1)
  p$kill()
  cat(mode, ":", gsub("\r", "", gsub("(abcdefghij)+", "<long>", out)), "\n")
}

````

**Output** (`a10.out`)

````text
pipe : [p1][p1]<got 1: nchar=4102 head=abcdef>
[p2]<got 2: nchar=5 head=third>
[p3]<got 3: nchar=6 head=fourth>
[p4] 
pty : ^[[?1034h[p1][p1]<got 1: nchar=4102 head=abcdef>
[p2]<got 2: nchar=5 head=third>
[p3]<got 3: nchar=6 head=fourth>
[p4] 

````

Verification re-run with a tail probe (`$W/../verify-18/w/a10_tail_driver.R`, same driver, child also prints
the last 12 characters): `<got 1: nchar=4102 head=abcdef tail=abcdefsecond>` in both pipe and pty modes, i.e.
the next line is appended to the truncated first line, not lost (see 2.1.2).

---

## Verification log

Adversarial fact-check of this report, 2026-09-29/30. Every prototype in section 5 was re-run from a copy of
`$W` (`scratchpad/work/verify-18/w/`, outputs in `verify-18/out/`) with `Rscript --vanilla` on R 4.4.3,
macOS arm64; web and source claims were re-fetched independently. Verdicts: **confirmed**, **corrected**
(report edited in place), **unverifiable** (left or marked UNCERTAIN).

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | `readline()` strips leading/trailing blanks; prompt limit 256; non-interactive prints prompt + newline and returns `""` | confirmed (3.1 wording fixed: `Rprintf("%s\n")`, not `cat(prompt, "\n")`) | `?readline` (Rd2txt), `scan.c` `do_readln` (trunk and R-4-4-3 tag, identical), `a1`/`a7` re-run |
| 2 | 6,000-char line returns 4,102 chars and "the following line vanished" | **corrected**: first 4,096 chars + next line appended; rest dropped; R >= 4.5 keeps the remainder (source only) | `a10` re-run + tail probe; `sys-std.c` R-4-4-3 vs R-4-5-0 tags; wch/r-source commit "Unlimited line length on Unix with readline (PR#18690)", 2024-08-13 |
| 3 | `CONSOLE_BUFFER_SIZE 4096`, `Defn.h` line 2031 | confirmed for trunk (line 1888 in R 4.4.3; noted) | raw `Defn.h` trunk and R-4-4-3 tag |
| 4 | Ctrl-D returns `""`, R stays alive; typed text + Ctrl-D ignored until Enter | confirmed | `a8` re-run |
| 5 | `utils::timestamp(..., quiet = TRUE)` adds a history entry that Up recalls; `readline()` input is not added | confirmed | `a5` re-run; `timestamp` body (`.External2(C_addhistory)`); `ConsoleGetchar` calls `R_ReadConsole(..., 0)` |
| 6 | Under Rscript: one persistent `file("stdin")`; fresh connections lose buffered lines; `stdin()` is the script | confirmed | `a1`, `a1b`, `a1c` re-run |
| 7 | `askYesNo()` returns `default` non-interactively; `menu()`/`select.list()` error | confirmed | `a7` re-run; printed `utils::askYesNo`, `utils::menu` |
| 8 | `rlang::is_interactive()` logic (`rlang_interactive`, knitr, `TESTTHAT`) | confirmed | printed body, rlang 1.1.7 |
| 9 | cli colour/dynamic/ansi/width/hyperlink detection order; `is_ansi_tty()` Unix-only; RStudio caps table | confirmed | printed `num_ansi_colors`, `detect_tty_colors`, `is_ansi_tty`, `is_dynamic_tty`, `console_width`, `ansi_has_hyperlink_support`, RStudio `caps`, cli 3.6.6 |
| 10 | Terminal capability table (pty, TERM=dumb, NO_COLOR, interactive R, pipes) | confirmed | `a2` re-run; extra piped run of `a2_tty.R` for the pipes row |
| 11 | Positron `startup.R` sets `cli.default_num_colors = 256L`, `cli.dynamic`, `cli.hyperlink*`; ark sets `.Platform$GUI = "Positron"` when `POSITRON == 1`; ark `askpass` override | confirmed | raw posit-dev/positron `startup.R`; posit-dev/ark `positron.R` lines 8-12, `options.R` |
| 12 | IRkernel: `options(jupyter.in_kernel = TRUE)` (kernel.r 390); `base::readline` replaced by an `input_request` function (execution.r 131-137, 271-272); argv `R --slave -e IRkernel::main()`; no override of `interactive()` | confirmed (runtime still UNCERTAIN) | raw IRkernel master `R/*.r`, `kernel.json` |
| 13 | `onintrEx()` adds a `resume` restart; `onintr` vs `onintrNoResume`; Windows `R_ProcessEvents()`→`onintr()`, `R_ReadConsole()`→`onintrNoResume()`; Unix `handleInterrupt()`→`onintrNoResume()` | confirmed | raw trunk `errors.c`, `gnuwin32/system.c` (lines 152-154, 255-261), `unix/sys-std.c` |
| 14 | Pause menu with real SIGINTs: 7 scenarios | confirmed | `e2_driver.R` re-run (all checks TRUE, same transcript) |
| 15 | Abort cancels the HTTP stream; next request completes | confirmed | `g1_driver.R` re-run (server log: disconnected before token 19) |
| 16 | Ctrl-C at a permission prompt aborts the run, session alive | confirmed | `e4_driver.R` re-run |
| 17 | Paste arrives as separate lines; no bracketed paste (`ESC[?2004h` absent); type-ahead becomes the next prompt | confirmed (macOS pty only) | `e3_pty_driver.R` re-run |
| 18 | `cat()` not buffered; `cli_progress_step` spinner frozen without ticks | confirmed | `a9` re-run |
| 19 | Classifier 101/101, indirections, 4 blind spots, file not deleted | confirmed | `b1_test.R` re-run (four times) |
| 20 | Classifier speed "about 0.4 s" / "0.33–0.54 s" per 1,500 statements | **corrected** to 0.33–1.14 s on a loaded machine; idle timing unmeasured | four re-runs at load average 40–75 |
| 21 | Parser facts (string heads become symbols, `` `base::unlink` `` single symbol, native pipe rewritten at parse time, `findGlobals`) | confirmed (only `findGlobals` sort order differs with locale) | `a3` re-run; extra parse checks |
| 22 | Permission gate: decision matrix + 18/18 checks; prompt rendering | confirmed (the "read outside project" row is in the code, level 1, but not in the printed matrix) | `c2_test.R` re-run; `c2_permissions.R` `tool_risk()` |
| 23 | `ask` tool 5/5 checks | confirmed | `c3_test.R` re-run |
| 24 | Streaming renderer chunk-invariant and width-respecting | **corrected**: width check passes only in a UTF-8 locale (C locale: 59 > 40, 2/6 overlong); chunk invariance holds in both | `d1_test.R` re-run under C and `en_US.UTF-8` |
| 25 | `cli::code_highlight()` returns partial lines unchanged | confirmed | `d1_test.R` output |
| 26 | Piped REPL session incl. prompts answered from the pipe; `"""`, fenced block, trailing `\` | confirmed (fenced and `\` tested with extra input) | `e1_run.R < e1_input.txt` re-run, identical to `e1_run.out`; extra piped input |
| 27 | Non-interactive output: progress on stderr, verbosity 1 under Rscript, 0 in knitr and under `TESTTHAT=true`; `knit_print` markdown; `R²` mangled in C locale | confirmed | `f1_script.R` re-run (with and without `2>/dev/null`), `knitr::knit()` in C and UTF-8 locales, `TESTTHAT=true` run |
| 28 | `/undo` snapshot via `mget()` costs no copy (+4 MB for 381 MB) | confirmed | `h1_snapshot.R` re-run |
| 29 | stderr printed in bold by macOS terminal R | confirmed | `a4` re-run; R-admin macOS page quote |
| 30 | ellmer 0.4.0: `live_console()` loop, `"""`, `Q`; `live_browser()`; `check_echo()`; `tool_reject()` class; `tool_annotations()` args; `on_tool_request`; `chat()` returns invisibly when echoing; word wrap at `cli::console_width()` | confirmed | printed functions (`cat_word_wrap(width = cli::console_width())`) |
| 31 | Claude Code modes table, `manual` alias, deny→ask→allow, bare deny removes tool, compound separators, stripped wrappers, "isn't a security boundary", `/bin/rm`/`bash -c` examples, anchors, `.claude/settings.local.json` persistence, comment semantics | confirmed | code.claude.com/docs/en/permissions |
| 32 | Protected paths "never auto-approved (except bypassPermissions)" | **corrected**: in `auto` they are routed to the classifier; allowed in `bypassPermissions` and plan-with-bypass; list itself verbatim-confirmed | code.claude.com/docs/en/permission-modes "Protected paths" |
| 33 | Critical paths = root, home, working directory | **corrected/extended**: also top-level dirs, parents of the working directory, drive roots, globs under additional dirs | permission-modes "Which paths are critical" |
| 34 | Auto mode: classifier, tool results stripped, 3-in-a-row / 20-total fallback, stated boundaries, broad allow rules dropped; plan approval labels; Shift+Tab cycle | confirmed; added: auto is the built-in starting mode from v2.1.283 | permission-modes page |
| 35 | AskUserQuestion: 1–4 questions, 2–4 options, `header` max 12, `preview` (TS, opt-in), `response`, multi-select as array or `", "`-joined, "Other" text as value, not in subagents; `askUserQuestionTimeout` 60s/5m/10m | confirmed | code.claude.com/docs/en/agent-sdk/user-input; /docs/en/tools-reference |
| 36 | `canUseTool(toolName, input, {signal, suggestions})` → allow/deny shapes; "never fires for auto-approved tools" | confirmed | agent-sdk/user-input |
| 37 | Claude Code interactive mode: queued messages delivered after tool calls within the same turn; Esc/double Esc/Ctrl+C; `!` adds output to context; multiline methods | confirmed | code.claude.com/docs/en/interactive-mode |
| 38 | Codex `AskForApproval`, `GranularApprovalConfig`, `SandboxPolicy`, `ReviewDecision` (default `Denied`), `request_user_input` structs | confirmed | raw openai/codex main `8c3612fb` (2026-09-30) `protocol.rs`, `request_user_input.rs` |
| 39 | Codex docs: default workspace-write + on-request; `untrusted` no longer supported; `approvals_reviewer = "auto_review"`; `--yolo`; `.git`/`.agents`/`.codex` read-only; network off; `/permissions` | confirmed | learn.chatgpt.com/docs/agent-approvals-security (308 redirect from developers.openai.com) |
| 40 | Pi: steering docs (usage.md 29-40), keybindings (123-125, 165-166), security.md 3-7, `permission-gate.ts` (34 lines, regexes, no-UI block), `protected-paths.ts` (30 lines), `question.ts`, `questionnaire.ts`, `ExtensionUIContext`, `ctx.mode`/`hasUI` (types.ts 323-331), `bashExecutionToText`, `_pendingBashMessages` (agent-session.ts 3781-3802), plan-mode allow/deny lists, `/plan`, `/todos`, Ctrl+Alt+P | confirmed; Windows key variants added | Pi clone `1b347794` |
| 41 | `rstudioapi::showQuestion/showPrompt` default `timeout = 60` | confirmed | rstudioapi reference pages |
| 42 | RStudio 2026.08.0 fixed native dialogs from `askYesNo()` opening behind the window on Windows | confirmed (#18270) | rstudio/rstudio `version/news/os/NEWS-2026.08.0-yellow-yarrow.md` |
| 43 | `askYesNo` option set to `askYesNoWinDialog` in RGui | confirmed | trunk `src/library/utils/R/zzz.R` line 63 |
| 44 | processx `interrupt()` is a CTRL+BREAK keypress on Windows | confirmed | processx `process.Rd` |
| 45 | rw-FAQ 5.1: Esc in RGui (Ctrl-C copies), Ctrl-C/Ctrl-Break in Rterm; simpler line editing | confirmed | cran.r-project.org rw-FAQ |
| 46 | `?flush.console` quote | confirmed | utils `flush.console.Rd` |
| 47 | 4.10 "Imports already in D-20 ... `processx`/`curl` already planned" (as Suggests) | **corrected**: `processx` is a D-20 Import; direct `curl::` calls need `curl` in Imports (not in D-20; D-13 open) | `dev/spec/01-decision-register.md` D-13, D-20 |
| 48 | REQ-03/16/22/24/25/36/37/38 and D-03/D-05/D-11/D-26 references | confirmed | `dev/spec/00-vision-brief.md`, `01-decision-register.md` |
| 49 | Appendix listings are the exact prototype files | confirmed for every listing (`a10.out` differs only by ESC shown as `^[`) | line-by-line comparison script |

Unverifiable here (kept or marked UNCERTAIN): runtime behaviour on Windows, Linux, RStudio, Positron, VS
Code and Jupyter (including Esc during `readline()`, resumable interrupts, `timestamp()` history); the
R >= 4.5 long-line behaviour (source only, only R 4.4.3 installed); classifier speed on an idle machine;
whether a processx CTRL+BREAK reaches Rterm as a resumable interrupt; whether `rstudioapi` accepts
`timeout = Inf`; bracketed paste with newer readline builds; features of chattr, askgpt and gptstudio.
