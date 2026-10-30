# Open findings after the comprehensive review

This ledger lists the findings on `claude/v1-fixes` (PR #93). It was first written at `25f83241` on
2026-10-28, when the maintainer paused the iterative review rounds, as the input of one
comprehensive review and one comprehensive fix pass before the CRAN submission. Both have happened.
The review of `f690afc7` (15 lenses, each finding checked by a verifier, refuted ones dropped)
planned 168 items, F-1..F-168, with 67 decisions on the calls the maintainer had deferred; twelve
lanes fixed them, and the integration merged them on `4cf922a4`, whose CI is green
(`progress/fixes.md` FIX-37..FIX-48 and CI-106; `DEVIATIONS.md` D-291..D-300). Every row now ends
with its status. A row the pass fixed has left its section and is listed, with the item and the
record that closed it, under "Closed by the comprehensive fix pass"; a row kept by a decision names
its D entry; a row still open says why. The review's own new rows are under "Added by the
comprehensive review". The rest of this opening describes the ledger as first written: its sources
were round 6's seven lens verdicts, the four fix writers' reports and their verifiers' final
verdicts, the Windows verdict, PR #94's writer and verifier, the Open lists of `dev/HANDOFF.md` and
`dev/PROGRESS.md` (which agree), the Open bullets of FIX-20, FIX-27..FIX-36, CI-87, CI-88, CI-93,
CI-104 and CI-105 in `progress/fixes.md`, the status, Limits and Not covered lines of D-262..D-272,
the session handoffs of 2026-10-27 (its sections 3, 4 and 8) and 2026-10-28, and the release steps
not yet done. A row merges every source that names the same item and keeps each source id. Fixed
items are left out; the section on round 6 lists round 6's fixed findings by branch. CI-87's and
CI-88's notes are closed by CI-99 and CI-101 but for one residual (L-48). An independent
completeness check of the first version (`a3d18f40`) added L-62 to L-71 and PW-2, corrected this
paragraph and the rows V6G-1, V6G-N4, L-5 and L-26 (each re-measured or re-run here), and filled in
what other rows had left out; row ids are stable, V6S-7 is split into V6S-7a and V6S-7b, and L-53 is
folded into L-31.

Each row gives its ids, its severity, whether it is a regression of this branch against `main`
`13a917ff`, the item, the evidence and the smallest fix its source proposed. Severity is high,
medium, low or nit for a defect, gap for something not run or not covered, and step for a release
step not yet done. Regression is yes when `main` behaved better (no question, a lower level, a
shorter time), new for a defect in code or text this branch added that has no counterpart on `main`
(the commit that brought it is named), no when it is as on `main` or a documented limit, and n/a for
a record, a step or a gap. A file:line is at `25f83241`. A name in double quotes after a state file
is the workflow step inside it. `state/` is `A/state/`, where the round's state files are copied:

- `A`, the archive of this pause:
  `/Users/wgu/Desktop/gptr-session-archive-2026-10/handoff-2026-10-28`
- `B`, this review session's scratchpad (`state/`, `gate6v/`, `gate7/`, `fr6v3/`), these three
  parts joined:
  `/private/tmp/claude-501/`
  `-Users-wgu-Desktop-BioRouter--claude-worktrees-gptr-cran-readiness-ec0baa/`
  `9ae5edf9-a47e-4ebd-8c7f-6f8f029ae04c/scratchpad`
- `G`, the gptr session's scratchpad (`live/r6-*/`, the worktrees under `v1/` and `v1v/`), these
  three parts joined:
  `/private/tmp/claude-501/`
  `-Users-wgu-Desktop-gptr--claude-worktrees-gptr-completion-handoff-f802a1/`
  `b4598491-010f-4344-9895-e8aca8beb354/scratchpad`

`B` and `G` are under `/private/tmp` and may not survive a restart; `A` is kept. "Probes on an
install of `a3d18f40`" are this revision's: `gptr_risk()` on a scratch install of that commit with
an isolated HOME, the project and the outside directory both outside `tempdir()`; the scripts and
their output are in `A/probes/`.

## Permission gate

- **L-2** (low; yes). The drive-relative rule (`D:x` is outside on every OS) raises unrelated
  readings: `rm -rf ${X:-build}` with a one-letter name 3 to 4, `readLines("a:b.txt")` 0 to 1,
  `rm a:b` 3 to 4, and `cd <outside> && git commit -m 'rm -rf build'` 2 to 4 (the literal scan reads
  the message in the outside directory); no Open list names them. Evidence:
  `dev/progress/fixes.md:6322-6326` (FIX-27 review round 4, the fixes' verifier). Fix: none
  proposed. Status: kept: the rule fails safe (it raises readings, never lowers one), and no fix was
  proposed.
- **L-3**, also D-262's Not covered and section 4 of the 2026-10-27 handoff (low, documented; no). A
  computed command run through `get("system")(cmd)`, `baseenv()$system(cmd)`, a function handed to
  your own (`g(system)`), `eval(parse())`, a sourced file, package code, `peter$knit` R chunks,
  `peter$script`, `pipe()`, `processx::run(cmd)` or `data.table::fread(cmd = x)` still escapes `sh:`
  rules in auto and yolo; neither the rules nor the refusal read what a shell reads when it runs
  (standard input, the variables it expands, a script file); in manual and edits an allow rule such
  as `r(level<=3)` still lets a computed `system()` run past a deny `sh:` rule. Evidence:
  `dev/HANDOFF.md:320-327`; `dev/DEVIATIONS.md:7889-7904`; `dev/progress/fixes.md:6130-6137`. Fix:
  refusing `pipe()`, `processx::run()` and `fread(cmd =)` too is one word in the function vector,
  the maintainer's call; the rest is documented. Status: `pipe()`, `processx::run()` and
  `data.table::fread(cmd =)` with a computed command are refused in auto and yolo since F-20
  (FIX-37, D-293); the rest stays documented in `?gptr_security` (kept).
- **L-4**, also R6-D3 (a) and the gate6 first verifier's note (c) (low, documented; no). The
  classifier does not follow a working directory changed other than by `setwd()`,
  `withr::local_dir()`, `withr::with_dir()` or `xfun::in_dir()` (`usethis::local_project()`,
  `get("setwd")`, `callr::r()`'s `wd`), nor read another interpreter's code (`Rscript -e`,
  `perl -e`, `node -e`, `pwsh -CommandWithArgs` or `-cwa`), a path the shell computes (`rm "$f"`,
  `xargs rm`), an `sh -c` word whose spaces are escaped or written `$IFS`, `env -iC DIR` or
  `env --chd=DIR`, `eval()` of a quote reached otherwise (`eval(bquote(q()))` and
  `eval(expression(q()))` are level 3 and would end the session; a quoted call held in a name) or
  `processx::process$new()`'s command: each level 3 or lower, which auto and yolo run whatever it
  deletes. A computed `processx::run()` `wd` is read as the project. Evidence:
  `dev/HANDOFF.md:328-338`; `dev/progress/fixes.md:6500-6505` and `:6568-6572`;
  `state/fix6-results.json` "verify6 gate6" note (c). Fix: documented; reading an escaped `sh -c`
  word needs a tokenizer of its own. Status: `bquote(.(x))` and `eval(bquote(q()))` are read as code
  since F-2 (FIX-37); the rest stays documented (kept).
- **L-62**, also FIX-36's Open, D-272's Not covered and R6-D3 (b) (low, documented; no; the
  maintainer's call). Variable changes the classifier does not read, each level 3 or lower, which
  auto runs, so they move gptr's config folder or the home unasked: code in a file R runs
  (`source()`, `sys.source()`, `eval(parse(file = ))`; `writeLines()` of an `.R` file and then
  `source()` of it reads 3); `Sys.setenv()`, `Sys.unsetenv()`, `withr::local_envvar()` or
  `withr::with_envvar()` reached by a computed name, through a list or an environment, or handed to
  a function the classifier does not know calls it (`get("Sys.setenv")`, `baseenv()$Sys.setenv` and
  `identity(withr::local_envvar)` read 3, `assign("f", Sys.unsetenv)` 2); a Python write through
  another name for `os.environ` (`e = os.environ` reads 2), through `getattr(os, "environ")` or
  `ctypes` (3), or an `os.environ.update()` of a mapping the code computes, of names that are not
  plain string literals (`{'H' 'OME': d}`, 3) or of keyword names not all in upper case (`home = d`,
  3, which sets `HOME` on Windows); Python run through 'reticulate'. Evidence:
  `dev/HANDOFF.md:443-453`; `dev/PROGRESS.md:38`; `dev/progress/fixes.md:9589-9598` (round 2's list,
  which replaced round 1's at `:9528`); `dev/DEVIATIONS.md:8807-8809` and `:8868-8873`;
  `state/round6-verdicts.json` "r6 docs" R6-D3 (b); probes on an install of `a3d18f40`. Fix: none;
  documented as a class, the maintainer's call. Status: kept by decision (D-300, DEC-10).
- **L-63**, also D-262's Accepted false refusals and FIX-36's accepted false question (low; yes,
  costs of this branch's rules on code `main` ran unasked). In auto and yolo
  `cmd = "ls"; system(cmd)`, `system2("git", c("log", n))`, `system2("ls", character())` and a
  function defined but never called (`f = function(x) system(x)`) are refused (level 3 `dynamic`),
  each costing one round trip to `peter$sh()` or an `r(fn:)` rule (`do.call(system, list("ls"))` is
  no longer refused since R6-GATE-4's fix, `e97a7f5b`). In auto,
  `os.environ["MPLCONFIGDIR"] = os.path.join(os.environ["HOME"], ".mpl")` in Python and
  `lapply(nms, Sys.unsetenv)` read level 4 `control` and ask. Evidence:
  `dev/DEVIATIONS.md:7905-7911`; `dev/progress/fixes.md:9469-9478` and `:9875-9886`; probes on an
  install of `a3d18f40`. Fix: none; accepted when the rules were written. Status: kept by decision
  (D-300, DEC-10).

## Secrets and redaction

- **L-6**, also V6S-7b, the second half of "verify6 secret6 final" finding 7 (low; yes, new
  questions on code `main` ran). The round 6 guard's recorded costs: a `$NAME` of a registered name
  in a `peter$sh()` or `peter$bg()` command asks in auto although those children start without
  registered secrets; a command line or Python that only mentions `.env` (`echo .env >> .gitignore`,
  a comment) asks in auto; code that reads a secret, starts a process and names a network program in
  any string (a `message()` that says `curl`) asks in yolo; and, wider than FIX-32 and D-267 say, a
  computed-name `Sys.getenv()` of an ordinary variable counts as a read, so
  `v = 'PATH'; Sys.getenv(v)` with `system('echo hi')` and the string `'install curl first'` is
  level 4 and asks in auto too (3 on `3cd3b146`). Evidence: `dev/HANDOFF.md:359-366`;
  `dev/progress/fixes.md:7987`; `state/prop-secret6-results.json` "verify6 secret6 final" (coverage,
  New noise; finding 7). Fix: say in FIX-32 and D-267 that a computed-name `Sys.getenv()` counts as
  a read and asks in auto too; a mention is read word by word, which is the command classifier's
  side. Status: kept (accepted costs); FIX-32 and D-267 now say that a computed-name `Sys.getenv()`
  counts as a read and asks in auto (F-163, FIX-48).
- **L-7** (low; no, the cost of a new guard). A registered secret handed to a child through `env`
  asks each time in auto and twice in manual unless the same code reads it by name, and the idle
  gate does not take the level 3 of an ordinary variable passed through. Evidence:
  `dev/HANDOFF.md:357-359` (FIX-32 review round 5); D-267. Fix: none proposed. Status: kept (no fix
  proposed; the comprehensive review did not reopen it).
- **R6-SS-6** (residual; low; no; the maintainer's call). Output the console does not indent (a
  console that cannot redraw a line, or `gptr.verbose` below 2) reaches the screen through R's split
  sink and shows a secret model code prints, on the screen only; the margin and the teed warnings
  are redacted since `318cc940`. Only a tee that displays at flush points could filter it, which
  ends live output. Evidence: `dev/HANDOFF.md:361-363`; `state/fix6-results.json` "fix6 secret6"
  notes; `state/round6-verdicts.json` "r6 sec-secrets" R6-SS-6. Fix: none proposed. Status: kept by
  decision (D-300, DEC-15).
- **L-8** (low; no). An authenticated proxy variable (`HTTPS_PROXY` with a password) is not
  secret-looking, so discovery still registers its password as `HTTPS_PROXY_PASSWORD` (CI-99).
  Evidence: `dev/HANDOFF.md:388-389`. Fix: none proposed. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-64**, also R6-SS-1's documented part and FIX-32 review round 6 (low, documented; no). Limits
  of the secret guard that `?gptr_security` states: a registered secret read through a name the code
  computes when it runs (with `paste0()`, through `get()` or `do.call()`, as a function's argument,
  or in a variable it sets otherwise) is level 3 with no guard, so auto runs it and the value
  reaches R (`for (v in c('HOME', 'USER')) Sys.getenv(v)` reads 3); a copy the code changes other
  than by URL-encoding, JSON-escaping or base64, such as reversed or cut, is not redacted (R6-SS-1
  saw a reversed key 4 times in the fake provider's requests, with no question in auto); and a
  network program name the code builds from pieces is not read for the secret-to-network question.
  Evidence: `R/gptr-config.R:1784-1785`, `:1799-1801` and `:1806-1807`; `dev/HANDOFF.md:362-363`;
  `state/round6-verdicts.json` "r6 sec-secrets" R6-SS-1; D-267's status of 2026-10-28; probes on an
  install of `a3d18f40`. Fix: none; documented. Status: kept (documented).
- **L-68**, FIX-20's Open (low; no). A secret question asked under `.stdin = TRUE` on a tty is shown
  by the terminal's own echo, before and after FIX-20's echo fix. Evidence:
  `dev/progress/fixes.md:5053-5054`. Fix: none proposed. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).

## Console and paste

- **L-9**, also SC-2 (documented), SC-1's residual, D-263's Limits and section 4 of the 2026-10-27
  handoff (low; yes for the dropped Ctrl-C, by design). In a terminal that does not filter pastes,
  pasted text holding a paste end marker still sends at a newline of a read between when a read ends
  right after that marker and the rest is split again before the paste's own end marker, and a
  message sent there that starts with `!` or `/` runs as R or as a command at the next prompt with
  no Enter; a Ctrl-C typed in the same batch as a paste, within about 0.1 s of its read (0.2 s on
  the polling beat) or within 2 s of the last read of a paste left open is dropped once (`main`
  honoured it), while a pasted Ctrl-C that reaches the reader more than 2 s after a paste's last
  read is the key; a paste left open makes Enter only add lines until the run ends; DEL, Ctrl-U and
  Ctrl-W inside a paste edit the draft. Evidence: `dev/HANDOFF.md:426-436`; D-263;
  `state/round6-verdicts.json` "r6 sec-console" SC-1 and SC-2; `state/fix6-results.json` "verify6
  console6 round 2" item 1. Fix: documented; SC-2's code option, holding a `/` or `!` message from a
  read after an end marker until a quiet period, was not taken. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-10** (low; no). In a terminal that ignores bracketed paste a paste still splits when a read
  comes more than about 145 ms late (IC-76's 0.2 s bound; CI-94, FIX-28). Evidence:
  `dev/HANDOFF.md:437-438`. Fix: none proposed. Status: kept (no fix proposed; the comprehensive
  review did not reopen it).
- **L-11**, also FIX-34 PASTE-1 and section 4 of the 2026-10-27 handoff (low; no). On macOS a
  two-line paste without a final newline answers a question with its first line, as documented;
  outside a macOS terminal a block pasted at a question arrives one line at a time. Evidence:
  `dev/HANDOFF.md:419-420`; `dev/progress/fixes.md:8420-8427`; D-269. Fix: the triager's read of the
  waiting input in `tty_drain_mode()` was not taken, since it would also take a key typed just after
  Enter. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-12** (nit; new, FIX-34's merge). The console's not-run row cuts a guard refusal's long reason.
  Evidence: `dev/HANDOFF.md:420-421`; `dev/progress/fixes.md:8534-8535`. Fix: none proposed. Status:
  kept (no fix proposed; the comprehensive review did not reopen it).
- **L-13**, also FIX-34 review round 5 and the regressions lens's R6AT2 (low; no). Tab writes an `@`
  name holding a space or other punctuation without quotes, which the mention does not read whole
  (quoting it would end the word, so it needs `console_trigger()` to read a quoted word); in a UTF-8
  locale R's regular expressions read no mention in a line holding a file name that is not valid
  UTF-8; Rgui and Rterm in a code page hold only its characters; an `@` written straight after CJK
  text with no space attaches nothing, on this head and on `main`. Evidence:
  `dev/HANDOFF.md:422-425`; `dev/progress/fixes.md:8895-8900`; `state/round6-verdicts.json` "r6
  regressions" (b). Fix: none proposed beyond `console_trigger()`. Status: kept (no fix proposed;
  the comprehensive review did not reopen it).
- **L-14** (nit; yes, by design, D-244). Under `rc.settings(quotes = FALSE)` a `!` line's string
  completes nothing at the prompt, where readline used to offer every file name. Evidence:
  `dev/DEVIATIONS.md:6158-6163`; `dev/progress/fixes.md:8813-8814`. Fix: none proposed. Status: kept
  (no fix proposed; the comprehensive review did not reopen it).
- **L-15** (nit; no). Tab offers file names holding U+2028 or U+2029, and `ui_escape()` leaves them,
  as they are neither C0 nor C1; a transcript's header values keep them too, and keep bidi and
  zero-width characters, as they keep all non-ASCII text, and its output lines keep a tab
  (documented in FIX-29 and D-264). Evidence: `state/round6-verdicts.json` "r6 sec-console" summary;
  `dev/progress/fixes.md:7234-7237`. Fix: none proposed. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-16** (low; no). R draws no prompt again after a background callback's output, so the person
  types on a row without `> ` (FIX-21 L1). Evidence: `dev/HANDOFF.md:374-375`. Fix: none proposed.
  Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-17**, also PERM-9's second half and D-267 (b) (nit; no). An approved `system()` child's output
  starts on the frozen `r` row. Evidence: `dev/HANDOFF.md:355`; `dev/progress/fixes.md:7550-7555`.
  Fix: none taken; ending or clearing the row before evaluation drops IC-82's cue or erases the
  child's last line. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-65**, the rest of D-263's Limits and FIX-28's Open (low, one nit; no). Paste limits L-9 does
  not name: a tool's own `readline()`, `menu()` or `readLines(stdin())`, and a child process reading
  the terminal, get the paste markers; a read through GNU readline 8.1+ turns bracketed paste off as
  it ends (until the outermost `r` call returns, or until the call next sets its modes), so a paste
  made meanwhile is decided by timing; a kill or a crash leaves paste mode on (zsh, fish and bash
  5.1+ reset it at their prompts, as does `reset`); after a lone Esc a typed `[`, `[2`, `[20`,
  `[200` or `[201` waits for the next key and is lost where readline reads first; a paste bracketed
  just before a hand-over's `ESC [ ? 2004 l` reaches readline with its markers; the prompt's editor
  drops a pasted Tab that ends a read inside a split paste (nit); and the key loop is quadratic in a
  paste's size, so a 1 MB paste holds the console for minutes, as before. Evidence:
  `dev/DEVIATIONS.md:8062-8081`; `dev/progress/fixes.md:6953-6968`. Fix: none proposed. Status:
  kept. The review adds console-3: in a T console, `r` code that reads the terminal through
  `readline()` or `menu()` inside another function shows no text printed before the read and no echo
  of the answer, and Ctrl-C at that read stops the answer instead of pausing it; `?peter` says so
  (F-32, FIX-39, DEC-17).
- **L-70**, FIX-20's other Open notes (nit; no). `gptr_step()` on a background session relies on the
  timer to release it (at R's prompt the idle tick releases it at once), and the live row of a
  `system()` child's output stays smeared (D-253, no runtime change, as the verdict advised).
  Evidence: `dev/progress/fixes.md:5007-5008` and `:5022-5023`. Fix: none proposed. Status: kept (no
  fix proposed; the comprehensive review did not reopen it).

## Transcripts and documents

- **V6T-3**, the trans6 verifier's observation (nit; yes, in time, on an extension evaluator's path
  only). `doc_output_lines()` takes about 0.5 s for an output vector of 100k elements or 40 lines of
  1e5 characters (0.02 s before); the built-in evaluator's path is unchanged at 0.03 s. Evidence:
  `R/doc-blocks.R:1172`; `state/fix6-results.json` "verify6 trans6 round 2" observations. Fix: none
  proposed. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **R6-REG-2** (residual; nit; no). A block `main` recorded and an editor then trimmed, or whose
  code had CRLF line ends, reads user-edited, as on `main`; one whose code held a lone carriage
  return now does too (`main` read it fresh but could not source that document). A transcript whose
  only line ends are lone carriage returns is rewritten with LF line ends once, on gptr's next write
  to it (a round 6 test asserts it). Evidence: `dev/progress/fixes.md:8298-8302`; D-268;
  `state/fix6-results.json` "verify6 trans6 round 2" findings. Fix: none needed (documented).
  Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-18**, also D-264's Known limits (low, documented; no). A later console turn that uses an
  object made by a direct R line that is off still stops `source()`, as the undo kept the object;
  `all.names()` can match a column or formula term of the same name and switch a line off; a name
  reached through a string (`get("fit")`) is not seen; a non-ASCII name is matched only in a UTF-8
  locale (FIX-29); lines written by hand right after a direct R line switch off with it; a name
  holding a comma is left out of `created=`, so a line using it is not switched; and the `#<` lines
  are what was sent, so neither `gptr.doc_output_lines` nor the `doc` setting limits them. Evidence:
  `dev/HANDOFF.md:404-405`; `dev/DEVIATIONS.md:8186-8197`. Fix: none proposed. Status: kept (no fix
  proposed; the comprehensive review did not reopen it).
- **L-19**, also R6-D3 (c) and D-265's Known limits (low, documented; no). A console statement names
  the model and mode of a turn only as D-265 states: a switch during a run applies to the whole
  re-ask, a model given as a provider object is not named on a session's first statement,
  `.opts$thinking`, the budget, tools, skills and `.opts` are not recorded, and a turn recorded in
  auto or yolo is re-asked in that mode (FIX-30). D-265 also names: a model named on a re-assignment
  must resolve when re-asked (`gptr_error_unknown_model` otherwise); under an alias or an unset
  `model` setting the first statement after `/clear` names the model; a statement deleted or edited
  by hand is not accounted for; and a replay reconstructed from the document (no session log) does
  not apply the literals of fresh statements, so a stale statement after them continues the
  reconstructed session's model. Evidence: `dev/HANDOFF.md:406-409`; `dev/DEVIATIONS.md:8254-8269`.
  Fix: none proposed. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-20** (low; no). A line of `!` code that reads as another entry's first line but is not a
  comment still ends its section (FIX-31); a marker line inside a multi-line string of `!` code
  leaves the transcript's markers malformed, which the next block write names (FIX-33). Evidence:
  `dev/HANDOFF.md:410-412`; `dev/progress/fixes.md:8028-8033`. Fix: none proposed. Status: kept (no
  fix proposed; the comprehensive review did not reopen it).
- **L-21** (low; no). FIX-33's open items: a direct R line that read an object a turn changed stays
  on after the undo and replays with the restored value (DOC-3); a turn sent from outside the
  console is retried with the pending notes only (DOC-6); artifact references without `.gptr/` name
  `tempdir()/gptr` (MM-4); code recorded despite `record = false` has no `#>` output (ALL-3);
  claude-cli and codex blocks record `model=claude-cli/default` and `codex/default` (ALL-6); a
  refused turn records an empty block (PERM-8); a live re-ask sends neither a block's steering lines
  nor an `n <text>` answer, and the new block does not keep them (ALL-1, documented; L-23 is its
  script-replay twin). Evidence: `dev/HANDOFF.md:413-418`; `dev/progress/fixes.md:8101-8169`. Fix:
  none proposed. Status: kept; the review's live lens saw ALL-6 again.
- **L-22** (nit; no). An exported transcript keeps its replay note, which names the source
  transcript, and a refusal names no line (FIX-25, FIX-33). Evidence: `dev/HANDOFF.md:386-387`;
  `dev/progress/fixes.md:8120-8121`. Fix: none proposed. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-23** (low; no). A replayed script sends again a steer its run took after the script went on (a
  run sent to the background from the pause menu, a `gptr_wait(timeout =)` that returned early), and
  a `gptr_step(s, <n>)` that ended the run keeps the notes, so a later equal turn is still skipped
  (FIX-22). Evidence: `dev/HANDOFF.md:367-370`. Fix: none proposed. Status: kept (no fix proposed;
  the comprehensive review did not reopen it).
- **L-24** (low; no). From FIX-21: a console transcript repeats the call's prompt for the turn a
  parked session resumes and does not record the console note it answered (L3); a direct R line
  naming a session by a variable bound at R's prompt (`!!gptr::gptr_wait(b)`) stops the replay;
  `gptr_wait()` on a waiting session, called from inside a run's tool, resumes it as a nested run
  that inherits the outer run's safety record (the gate still asks). Evidence:
  `dev/HANDOFF.md:376-382`. Fix: none proposed. Status: kept (no fix proposed; the comprehensive
  review did not reopen it).
- **L-25** (nit; no). Replayed closures and `function` calls have no srcref where the agent's keep a
  `<gptr>` one, so a replayed ggplot is 1,412 bytes smaller serialized and 768 bytes by
  `env_snap_size()`; an expression that names `peter()` still makes its objects with the document's
  srcrefs (FIX-24). Evidence: `dev/HANDOFF.md:383-385`. Fix: none proposed. Status: kept (no fix
  proposed; the comprehensive review did not reopen it).

## Docs and records

- **PV-4 (b)** (nit; n/a; the maintainer's call). `CLAUDE.md` and `AGENTS.md` lines 3 and 30 still
  say "an AI agent harness that lives inside the R session" and "Peter Wason (System 1 / System 2
  reasoning)", not PR #92's words; line 30's rule, to keep the Wason and Naur rationale in the
  README and `?peter`, holds. Evidence: `CLAUDE.md:3` and `:30`; "propagate verify" finding 4 (b).
  Fix: align them if wanted; agents do not edit these files on an agent's request. Status: open, the
  maintainer's (F-168, DEC-57): agents do not edit these files on an agent's request. The prepared
  text, both files byte-identical: line 3, "gptr 1.0 is a ground-up rebuild: it runs language model
  agents in an existing R session, where generated code can inspect and modify objects already in
  memory (CRAN package, pure R)."; line 30 keeps its rule and takes the README's rationale, "Naur's
  work on readable language definitions (Backus-Naur form) and Wason's research with Evans on
  reasoning; sessions recorded as runnable documents".
- **PW-1**, also PV-5 (nit; n/a). Plan drafts of shipped files had drifted before #92 and are left
  (P25 Tasks 2, 5, 10, 11 and 13, P01 Task 1's Description; P19's goal line and specs 00 and 03 say
  "inside the live R session"); D-270 wins over them. On #94 spec 05's two edited lines are 102 and
  111 columns (110 and 110 on `main`; 05 is not fmt-clean on `main`). Evidence: "propagate writer
  (continue)" left_unchanged; "propagate verify" finding 5. Fix: none proposed. Status: kept (no fix
  needed).
- **PW-2** (nit; n/a). The propagation left "live R session" and its variants where the writer
  judged them to agree with PR #92's wording: the model prompts and tool text ("the user's live R
  session": `R/prompt-text.R:49` and `:100`, `R/tool-r.R:7`, `R/mcp-server.R:14`,
  `inst/gptr/skills/high-performance-r/SKILL.md`), which test-northstar.R and the token benchmark's
  `tests/testthat/fixtures/bench/prefix-baseline.json` pin (L-66); the `?gptr_mcp_serve` title,
  comments in `R/cli-codex.R` and `R/proc-supervise.R`, `inst/gptr/mcp_relay.R`, the mcp vignette,
  `inst/COPYRIGHTS:75` and `cran-comments.md:55`; the openings of the why-peter, execution-model,
  language-models, system-one and script-as-history vignettes; the cheat sheet's h1 and meta
  description; and `R/doc-formats.R:484` (`:470` on #94). Evidence:
  `state/prop-secret6-results.json` "propagate writer (continue)" left_unchanged. Fix: none needed
  unless the maintainer wants the phrase gone; a prompt change must pass the prefix gate. Status:
  kept (no fix needed).
- **V6S-7a**, the first half of "verify6 secret6 final" finding 7 (nit; n/a).
  `dev/progress/fixes.md:7906` is 101 columns, an unbreakable code span holding a test regex; fmt.py
  and lintfmt.py accept it. Evidence: `state/prop-secret6-results.json` "verify6 secret6 final"
  finding 7. Fix: none needed. Status: kept (no fix needed).

## CRAN and release

- **R6-CRAN-3**, also the release step cran-comments.md (medium; n/a). `cran-comments.md` is
  untouched by this branch and stale: the CRAN-mode tests take [17s/18s] at a load near 130 and
  [16s/17s] near 30 (it says [13s/14s]); "0 errors, 0 warnings, 0 notes in every environment above"
  was false at `3cd3b146` (R6-CRAN-1 and R6-CRAN-2, since fixed in the tests but not yet proven in
  CI); the win-builder (501 s, 693 s) and R-hub results are from 2026-10-26, before this branch;
  "all but 10 of the R files" measures 9 by covr (116 of 125 reached); the reverse-dependency date;
  R 4.2's installed size (10.4 Mb, R 8.6 Mb) is not given; #94 rewrites its opening. Evidence:
  `cran-comments.md:76-78`, `:93-99` and `:113`; `state/round6-verdicts.json` "r6 cran" R6-CRAN-3;
  `G/live/r6-cran/`. Fix: with CI green, set the test time from a quiet run and the re-measured
  count, run win-builder and R-hub on the final tarball (or name the tarball they ran on), and set
  the reverse-dependency date at submission with `cran_comments_set_revdeps()`. Status: partly fixed
  (F-142, FIX-48): `cran-comments.md` gives this head's CRAN-mode check and CI times, "all but 12",
  the installed sizes and the example's time; win-builder, R-hub and the reverse-dependency date
  wait for the final tarball (dev/HANDOFF.md Remaining; DEC-61).
- **L-67**, CI-104's Open (low; no). Points a CRAN reviewer may raise: the six pages of session S3
  methods (`print`, `format`, `str` and `summary` of `gptr_session`; `print` and `as.data.frame` of
  `gptr_session_summary`) have no examples; they are registered methods, not exports, but a reviewer
  may ask for some (B7). 'TypeSafe AI' is quoted as a host, not as software or an API ("hosted by
  TypeSafe AI" is the fallback if a reviewer queries it). The README's 4 GiB figure is one measured
  run (`dev/TESTING_PLAN.md`). Evidence: `dev/progress/fixes.md:6040-6045`. Fix: none proposed;
  answer if asked. Status: kept by decision (D-300, DEC-62).
- **L-27** (step; n/a). No `R CMD check` has run since round 6's CRAN lens on `3cd3b146`
  (`isolated-check.R check` FAIL 1, R6-CRAN-1). The merged code had the full suite through
  `devtools::test()`, which loads fs and other namespaces and so could not see R6-CRAN-1, and ten
  changed test files against the installed package. Evidence: `dev/HANDOFF.md:272-283`;
  `dev/progress/fixes.md:9166-9180`. Fix: on the final head, `dev/ci/isolated-check.R check` under
  the heavy lock, the CRAN-mode `R CMD check --as-cran` under `env -i` and the incoming feasibility
  check. Status: open, a release step (dev/HANDOFF.md Remaining, step 1). The CRAN-mode check passed
  on this pass's head (Status OK, no NOTE; FIX-48); the full set runs again on the final head.
- **L-28** (step; n/a). PR #93's last CI ran on the pushed head `3cd3b146`, with 11 failing checks
  (R6-CRAN-1 on macOS release, the four Ubuntu R versions, no Suggests and `LC_ALL=C`; R6-CRAN-1 and
  R6-CRAN-2 on both Windows shard 1 jobs). The local branch is 68 commits ahead at `25f83241`, and
  win6's test fixes are proven only by the Windows jobs (shard 1 passing without fs, R 4.2 reading
  as R 4.6). The `main` ruleset requires its 14 checks and a branch up to date with `main`.
  Evidence: `gh pr checks 93` (2026-10-28); `state/win6-verify.json` (Not proven here);
  `state/ruleset-24955100-after.json`; `gh pr view 93`. Fix: merge `main` (after #94), push, and
  read every job (`gh run rerun <id> --failed` when Ubuntu's apt mirror stalls a job, L-47); and
  rewrite PR #93's title and body, which still say FIX-27..FIX-34, "three review rounds" and
  "Checks: In progress: review round 4 ... This section is updated when they finish", and name
  D-262..D-270 only, so that they cover FIX-35, FIX-36, review rounds 4 to 6, D-271 and D-272 and
  the final checks. Status: open, a release step (Remaining, step 2). CI on `4cf922a4` is green
  (CI-106); PR #93's title and body still name FIX-27..FIX-34 only.
- **L-29** (step; n/a). R-hub (Windows R-devel and R-release, Ubuntu gcc 12) and win-builder
  (R-release, R-oldrelease and R-devel, by e-mail through Outlook) on the final tarball; the
  2026-10-26 runs used `e1b6ca59`'s tarball, and win-builder's R-devel run forwarded on 2026-10-27
  used `main`'s. Evidence: `dev/HANDOFF.md:303-313`; the 2026-10-27 15:10 entry of
  `SESSION-HANDOFF.md`. Fix: run them after L-27 and L-28. Status: open, a release step (Remaining,
  step 4), after the pkgdown deploy that the README's link to `articles/tailor-and-coach.html` needs
  (DEC-59).
- **L-30** (step; n/a). PR #94 (`4dd36dc9`) is open with its CI running (runs 40775715597 and
  40775715751, then 40775753561 and 40775753543, 2026-10-28); after it merges, `main` is merged into
  this branch (L-26), and #93 merges with a merge commit once its checks and the hosted checks
  (L-29) pass; then `main`'s CI is watched until it is green (section 3 step 8 of the 2026-10-27
  handoff). Evidence: `gh pr list`, `gh run list` (2026-10-28). Fix: as stated. Status: open, a
  release step (Remaining, steps 4 and 5). PR #94 merged on 2026-10-29 (`483c2192`), and `main` is
  merged into this branch; #93's merge and `main`'s CI remain.
- **L-31** (step; n/a). Cleanup to `main` only, after #93 merges: the spare branches
  `claude/pr92-main` (`d45f7d5b`) and `claude/v1-pr92` (`a59c242d`); every `claude/v1-fix-*` branch
  (browser, class6, cons6, console, console4, console5, console6, doc, docs4, docs5, env, env3,
  gate, gate5, gate6, perm, secret5, secret6, trans6, win, win42 and win6);
  `claude/fix27-system-gate` to `claude/fix31-transcript-hardening`; `claude/v1-fixes` and
  `claude/pr92-propagate` with their remote branches, and `origin/claude/fix27-system-gate`, the
  only other remote branch; their worktrees under `G/v1/` and `G/v1v/` (among them
  `fr6-secret6-base`, at `3cd3b146` with two untracked probes, which the first secret6 verifier left
  when the session limit cut it off and a second verified from scratch, formerly L-53; and the
  detached `pr92-main`), then `git worktree prune`; and fast-forward the base checkout to
  `origin/main` (L-32). PR #91 (`claude/fix27-system-gate`, FIX-27 alone) is still an open draft;
  #93 holds it, so close it if it does not show merged once #93 merges. Keep both stashes in the
  base checkout (`stash@{0}` "preserve-main-checkout-uncommitted-2026-10-20 (pre-sync, 718e81e)" and
  `stash@{1}` "codex-preserve-user-description-before-pr5-20261010"). The script
  `/Users/wgu/Desktop/gptr-session-archive-2026-10/handoff-2026-10-27/scripts/cleanup3.sh` does the
  deletions: set `KEEP_RE` and `KEEP_WT_RE` to match nothing, and run `dry` before `run`; delete a
  branch only after `git merge-base --is-ancestor <b> origin/main`, or, for a spare such as
  `claude/pr92-main`, after checking that its work is on `main`. Then confirm that `git branch -a`
  and `gh pr list` show only `main` and nothing open (section 3 step 9 of the 2026-10-27 handoff).
  `claude/p29-gptr-coach` (worktrees `gptr-p29` and `gptr-p29-check`) is other work: ask first.
  Evidence: `git for-each-ref refs/heads`, `git branch -r`, `git worktree list`, `git stash list`,
  `gh pr list` (2026-10-28); `state/prop-secret6-results.json` "verify6 secret6 final" ran. Fix: as
  stated. Status: open, a release step (Remaining, step 6).
- **L-32** (step; n/a). The maintainer's checkout `/Users/wgu/Desktop/gptr` has `main` at `13a917ff`
  (`origin/main` is `880e7ea4`); after the merges, update it, leaving its untracked
  `dev/spec/08-recursive-peter.md` alone, and install gptr from `main` in the maintainer's R, as
  `dev/HANDOFF.md:314-316` did for `c0dd52b7`. Fix: as stated. Status: open, a release step
  (Remaining, step 7).
- **L-33** (step; n/a). The CRAN submission and P25's live steps are the maintainer's. Evidence:
  `dev/HANDOFF.md:465`. Fix: as stated. Status: open, the maintainer's (Remaining, step 8).
- **L-71** (step; n/a). Report to the maintainer what changed, the checks and the decisions below,
  and update the memory files `gptr-session-handoff.md` and `gptr-readme-voice.md` (the README now
  follows PR #92's structure, which the maintainer approved). Evidence: section 3 step 11 of the
  2026-10-27 handoff. Fix: as stated. Status: open, a release step (Remaining, step 9).

## CI and test infrastructure

- **L-35** (gap; n/a). No round 6 lens, writer or verifier ran on Windows, Linux, R 4.2 or R-devel;
  Windows readings come from probes with `is_windows()` mocked and from reading the code. Only PR
  #93's Windows and Ubuntu jobs, win-builder and R-hub can prove them (L-28, L-29). Evidence: the
  not_done notes in `state/round6-verdicts.json`; "Not run" in every verdict of
  `state/fix6-results.json`. Fix: as L-28 and L-29. Status: gap. The review ran on macOS only;
  Windows readings come from CI logs and reading, and CI on `4cf922a4` passed every Windows, Ubuntu
  (R-devel to R 4.2) and macOS job.
- **L-37** (gap; n/a). Round 6 did not exercise: served R over HTTP (`gptr_mcp_serve()`; served R
  went through `mcp_dispatch_local()`), idle served R and the worker backend in the gate lens,
  worker sub-agents, the wire log, the RStudio dialog backend, `.Rhistory` (`console_history_add()`
  writes typed lines raw; not assessed), `gptr_scrub()`, an `.ipynb` written end to end,
  `gptr_export()` of a transcript built to carry forged lines, `peter$sh()`, `peter$bg()`,
  `peter$py()` or a nested `peter()` whose text holds a CR or LF end to end, team block lines and
  `ran_with` values, and the RStudio, Positron, Jupyter, R.app and Windows consoles. The docs lens
  did not re-drive the scripted-console transcript flows (`#<` lines, `model=` and `mode=`
  statements, `#~` switching, `/retry` notes) end to end; it checked their docs against the code
  diff and the Rd and spec text. Evidence: not_done of "r6 sec-gate", "r6 sec-secrets", "r6
  sec-transcripts", "r6 sec-console" and "r6 docs". Fix: cover them in the comprehensive review.
  Status: gap. The review covered team and fan-out blocks and an `.ipynb` end to end (transcripts
  lens); still not exercised: served R over HTTP (`gptr_mcp_serve()`), the RStudio dialog backend,
  `.Rhistory`, `gptr_scrub()` end to end, worker sub-agents in the gate lens, and the Positron,
  Jupyter, R.app and Windows consoles.
- **L-38** (gap; n/a). Live evidence is narrow: the gate and secret checks ran live on GPT-5.6
  (`versa/gpt-5.6-sol-2026-07-09`) and the fake only, since Claude Opus 4.8 refused the delete forms
  and the secret-redacted question even under a test framing or through a helper; p28's S10 and the
  S8 variants other than S8-clocale were not run; Ollama ran only S8; Python was not configured for
  the regressions lens, so the `os.environ` forms ran live only in gate6's verifier (reticulate,
  fake model); the docs lens drove no real terminal, so IC-76's bounds (0.1 s, 0.2 s and 145 ms)
  were not measured and spec 04 section 15 was sampled; and the gate lens did not use the tmux
  console driver (its live checks drove `peter()` in Rscript with a scripted UI that answers no).
  Evidence: not_done of "r6 regressions", "r6 sec-gate" and "r6 docs". Fix: none proposed. Status:
  gap. The review's live lens ran Ollama, Claude Opus in the console and the tmux driver, and
  live-cli and live-coach (10 tests, 58 expectations); not live: GPT-5.6, Bedrock Claude, the
  claude-cli and codex plans beyond the live lens, and the third-party chat-completions routes.
- **L-39** (gap; n/a). The incoming check's spelling of DESCRIPTION could not run locally (no
  aspell, hunspell or enchant); CRAN's own check runs it. Evidence: "r6 cran" not_done. Fix: none
  needed. Status: gap: aspell is not installed here; hunspell and the spelling package are clean.
- **L-40** (low; no). No CRAN-mode test reaches 10 R files (`artifact-registry`, `bridge-lang`,
  `console-jsonl`, `doc-export`, `doc-knitr`, `proc-rscript`, `provider-bedrock`, `s1-emulate`,
  `s1-ollama`, `tool-search`; CI-93); round 6's covr run counts 9. CI-93's other Open note, the
  Windows budget's calibration against win-builder once the new lane has run, stays open too (a
  hosted runner is not win-builder, and its timed step includes the build). Evidence:
  `dev/HANDOFF.md:401-403`; `dev/progress/fixes.md:4856-4860`; "r6 cran" R6-CRAN-3. Fix: none
  proposed. Status: kept by decision (DEC-60): no test in the CRAN list reaches 12 R files
  (`artifact-registry`, `console-jsonl`, `doc-export`, `doc-knitr`, `gptr-child`, `gptr-coach`,
  `gptr-tailor`, `proc-rscript`, `provider-bedrock`, `s1-emulate`, `s1-ollama`, `tool-search`; covr
  at `f690afc7`), while the providers and agent lenses ran those files' own tests in CRAN mode; no
  P29 test joins the list. CI-93's other note stays open.
- **L-66** (nit; no). The static-prefix gate of architecture 12.7 leaves `standard_core` 1 token to
  spare (2335 + 2%), so a change of one word to the static prompt (PW-2's text among it) fails the
  required "token benchmark" check. Evidence: `dev/HANDOFF.md:355-356`;
  `dev/DEVIATIONS.md:8471-8475`; `dev/progress/fixes.md:7522-7524`;
  `state/ruleset-24955100-after.json`. Fix: none proposed. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-41** (low; no). Why the Windows stdin writer exits early is not known: 2 of 1,356 writer cases
  in CI, none in 6,583 measured; a recurrence fails on `writer_failed` in about 5 s, with the
  writer's stderr in the witness (CI-98, CI-101). Evidence: `dev/HANDOFF.md:390-392`. Fix: none
  proposed. Status: kept. The review adds suite-11: one Windows native-absence failure at `a3d18f40`
  (job 123153922543).
- **L-42** (low; no). The Windows stdin writer's bootstrap stays about 630 bytes under Rscript's
  9998-byte `-e` limit with ordinary paths; it embeds `.libPaths()` and the temp path, so very long
  ones (a 153-character TMPDIR with a long check library: 10,179 bytes) make the writer refuse to
  start (`proc_writer_code_bytes()`, found by #88's CRAN gate). Evidence: `dev/HANDOFF.md:395-398`.
  Fix: none proposed. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-44** (low; no). What slowed or stopped pak's subprocess on the reporting Mac, and what removed
  its loaded copy of gptr before `load_all()`, is not in the report (CI-102). Evidence:
  `dev/HANDOFF.md:399-400`. Fix: none proposed. Status: kept (no fix proposed; the comprehensive
  review did not reopen it).
- **L-45** (low; no). A Windows security block near 500 ms can cross D-240's 500 ms line between
  runs (CI-95). Evidence: `dev/HANDOFF.md:439`. Fix: none proposed. Status: kept (no fix proposed;
  the comprehensive review did not reopen it).
- **L-49** (low; no). A `process_jsonl` line's events still follow the abort flag (its adapters
  check the signal themselves, 04 section 8.1), an `inprocess` generator keeps its two calls after
  it, and the partial of an abort inside a unit holds what was emitted only for a normaliser that
  records a delta before it emits it (FIX-26, CI-97). Evidence: `dev/HANDOFF.md:455-458`. Fix: none
  proposed. Status: kept (no fix proposed; the comprehensive review did not reopen it).

## Harness and process

- **L-50** (low; n/a). A Bash call pending well past its timeout with no process behind it is a lost
  tool result; it froze an agent twice in triage, and resuming a workflow with parallel branches
  reorders the calls and reruns finished agents. Evidence: section 8 of
  `handoff-2026-10-27/NEXT-AGENT-HANDOFF.md`; the 2026-10-27 03:30 and 05:20 entries of
  `SESSION-HANDOFF.md`. Fix: stop, then run the rest as a new small workflow with finished results
  passed as files. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-51** (low; n/a). Stopped workflows leave work running: 32 orphaned `yes` load loops (PPID 1)
  ran for 4 hours at a load of 220, and a writer waited for ever for the load to drop below 25;
  macOS services keep the load near 40 to 70, and round 6's lenses ran at loads of 120 to 226, so
  their times are not quiet-machine figures. Evidence: section 8 of `NEXT-AGENT-HANDOFF.md`; "r6
  regressions" and "r6 cran" ran. Fix: after stopping a workflow, look for what its agents left and
  stop it by PID. Status: kept (no fix proposed; the comprehensive review did not reopen it).
- **L-52** (low; n/a). Agents decline a lens worded as getting around the gate. Evidence: section 8
  of `NEXT-AGENT-HANDOFF.md`. Fix: word it as a maintainer-requested coverage check with harmless
  commands, and give the lens schema a `carried_out` flag. Status: kept (no fix proposed; the
  comprehensive review did not reopen it).
- **L-55** (nit; n/a). p28's S5 check of `/skill:` completion fails on this head and on `main` with
  the real HOME's many skills (a harness artifact), and claude-cli's first S8 run hit a transient
  "Not logged in". Evidence: "r6 regressions" (c). Fix: run p28 with an isolated HOME. Status: kept
  (no fix proposed; the comprehensive review did not reopen it).
- **L-57** (nit; n/a). Writers' reports carried claims nobody had established: commit `60427c7e`'s
  body says the Linux and macOS full suites load fs before test-risk-forms.R (a serial run of the
  157 earlier files never loaded it; fixes.md is corrected, the message stays), and win6's report
  counted 249 where the file holds 241. Evidence: `state/win6-verify.json` findings. Fix: verify
  every head, count and cause a writer reports. Status: kept (no fix proposed; the comprehensive
  review did not reopen it).

## Decisions for the maintainer

The review decided the rows that ended in the maintainer's call: L-1 (D-292), L-3 and L-5 (D-293),
L-62 (D-300), V6G-N1 (D-293) and R6-SS-6 (D-300); PV-4 (b) stays the maintainer's (DEC-57). These
rows have no defect row:

- **PERM-4**, also D-267 (a), section 4 of the 2026-10-27 handoff and the 2026-10-28 session handoff
  (n/a; no). On the codex route Codex's own shell runs outside gptr's gate, rules and secret guard
  in every mode (documented); `-c features.shell_tool=false` in the read-only modes was not taken,
  since IC-65 keeps Codex's shell and that key is not among the flags gptr's capability probe
  checks. Evidence: `dev/progress/fixes.md:7481-7495`; `dev/DEVIATIONS.md:8482-8484`;
  `dev/HANDOFF.md:355-356`. Decide whether to turn it off. Status: open, the maintainer's call; the
  review did not take it up (F-90 made `?gptr_security`'s Codex-shell sentence true for coached
  runs, whose Codex shell is off).
- **FIX-35 F2 and F3** (low; no). At a load average of 260 and more (above 245 in the session
  handoff) the owned browser close's process-table walks (`proc_children()`, `proc_tree()`) can take
  12 to 28 s and use up its 10 s deadline: 4 of 33 closes under 32 busy loops ended "close timed
  out", and 1 of 27 for its verifier. F3, which retries a pending lease's failed cleanup, makes each
  `artifact_browser()` call run that close before it raises (up to 10 s, 14.2 to 43.4 s with F2's
  walks). Evidence: `dev/HANDOFF.md:440-442`; `dev/progress/fixes.md:9322-9329` and `:9386-9391`;
  `dev/DEVIATIONS.md:8776-8779`. Decide whether F2 needs work and whether F3 stays. Status: decided
  (D-300, DEC-35): F2 is closed, since the close fails closed at its 10 s deadline (open and close
  took 0.55 s and 0.40 s at loads of 30 to 60), and F3 stays.
- **L-58** (low; no). A job that ends with no pump and no `kill()` before its first status look gets
  its end time at that look, an upper bound; processx 3.9.0's `get_end_time()` gives the exact end
  but needs the processx floor raised from 3.8.0 (FIX-23). Evidence: `dev/HANDOFF.md:371-373`.
  Decide whether to raise the floor. Status: kept by decision (D-300, DEC-36).
- **L-59** (n/a). Python's `chdir()` is read as `setwd()` with about 20 lines in `risk_python()`
  (`e4bea33b`, `ba2333bf`); the docs-only alternative reverts both and says that a relative
  `chdir()` literal is read in the project. Evidence: `state/fix6-results.json` "fix6 gate6" and
  "fix6 gate6 round 2" notes. Decide which. Status: kept: the reading stays, and F-17 (FIX-37)
  removed its false questions from strings and comments; the docs-only alternative was not taken.
- **L-60** (n/a). The new argument `gptr_source(model =)` (FIX-33, D-268) re-asks a record with
  another model. Evidence: section 4 of `NEXT-AGENT-HANDOFF.md`; `dev/DEVIATIONS.md:8600-8602`.
  Confirm the interface before 1.0.0. Status: kept by decision (D-300, DEC-22); `?gptr_source` says
  which calls `model =` reaches (F-46, FIX-40).

## Added by the comprehensive review

Rows the review of `f690afc7` and its fix pass add, each with its status.

- **agent-9** (low; n/a). The agent lens's finding on the edits mode's model-facing text: changing
  it needs the spec and the token benchmark's baseline, which leaves `standard_core` one token
  (L-66). Status: open, not before CRAN.
- **runtime-10** (low; no). Checkpoint snapshots cost seconds at about 20,000 bindings. Status: kept
  (no change).
- **suite-9** (low; n/a). 25 tests run only from a source tree; a green connections lane proves
  them. Status: kept.
- **suite-12** (low; no). The CRAN-mode check time grows: the Windows CRAN-mode lane used 381 to 505
  s of its 600 s budget (494 s on `4cf922a4`; Ubuntu R-devel 256 s of 480). Status: open, watched
  (DEC-60).
- **records-7** item 1 (low; no). The worker reads its child's result with `readRDS()`
  (R/subagent-worker.R:537), the CVE-2024-27322 pattern before R 4.4; the exported objects are R
  objects by design. Status: kept by decision (D-300, DEC-63); `?gptr_security` says so (F-88); a
  two-line R 4.4 guard only if model code in a worker is shown to overwrite the result path under
  auto.
- **F-58** (low; n/a). In auto a coaching run can still write outside its scratch folder, or move
  its working folder, through code with a computed path or name: the decided fence rule (DEC-24)
  refused writes to literal paths through `write.csv()` and its kin and was reverted (`d3bef645`).
  Status: open: a gate item must first apply the classifier half of the harness-child lane's
  cross-lane diff, then `git revert d3bef645` and the diff's test half (FIX-41, D-297).
- **F-6 residual** (low; n/a). `assign()` or `list2env()` rebinding a saved directory name inside a
  loop after `setwd(owd)` is read is seen in walk order only, so that `setwd(owd)` may read 3.
  Status: open (FIX-37, D-293).
- **copy-1** (medium; no, as at `f690afc7`). An inline function forwarded through a wrapper,
  `(function(...) peter(...))('x', big, extensions = function(gptr) NULL)`, copies `big` on the next
  edit, for `peter()` and a harness alike: `resolve_identifier()` evaluates the call in an
  `ident_mask()` whose parent is the wrapper's frame, and the kept extension closure keeps that
  frame and its forced dots. Status: open; copy-safety is a non-negotiable rule (FIX-42).
- **copy-2** (medium; no). `worker_ship_objects()` reads the objects with `mget()`, whose list keeps
  the caller's objects referenced after it is dropped (rule R6), so a worker's objects are copied on
  the next edit; F-51's write-once-and-clear fix for coaching would carry over. Status: open
  (FIX-42).
- **F-80 cost** (low; new, F-80). The checkpoint baseline classes every path: about 0.31 ms a path,
  1.57 s of a 2.16 s baseline for 5,000 files, 0.96 s of it in `path_class_key()`'s per-path
  `grepl()` calls, against 0.017 s for the same patterns over the whole vector. Status: open:
  vectorise `path_class_key()` (FIX-43).
- **F-64 limit** (low; n/a). Coaching spend charged inside a run is kept in memory and lost on
  resume: `usage_add_durable()` takes only rows its own session made. Status: kept, documented in 04
  IC-84 and 08 section 3.3 (FIX-42).
- **glob-1** (to triage). The gate lane's writer reported a finding on empty path components in
  `risk_glob_paths()` as out of the pass's scope, without its detail in the lane's results. Status:
  open: derive it again before acting (FIX-37).
- **wall-1** (low; no). Under a load of 300 to 400 (other lanes and a 32-process busy loop)
  test-proc-rscript-native.R failed 2 of 3 runs on its deadline bounds (lines 15 and 18,
  `elapsed <= 60` and completion), never on a sampling error; at loads of 130 to 165 it passed 3
  of 3. Status: open, as L-34 (CI-106).
- **ci-20** (low; n/a). The four serial CI lanes take 42 to 61 minutes (no-Suggests 46.0, C locale
  42.5, connections 61.2, macOS 54.7 on `4cf922a4`), and the maintainer asked that no CI job run
  longer than 20 minutes. Status: fixed by CI-107 (every job 20 minutes, a gate 5; the full suite
  in gated shards), which has not yet run on GitHub.
- **live-9** (step; n/a). This pass changed the fence, the Codex hook and the transport, so
  live-coach and live-cli run again (records-4), with one live request at the highest reasoning
  effort for the 90 s idle timeout (F-132, DEC-41) and the Windows job once on a host with Codex for
  the hook (F-59, DEC-27). Status: open, a release step (Remaining, step 3).
- **ack-1** (nit; no). Internal error texts in `R/proc-spawn.R` and `R/http-reactor.R` still say
  "acknowledgement", which tests match; not user documentation, and the spell check is clean.
  Status: kept (FIX-45).

## Closed by the comprehensive fix pass

Rows of this ledger that the comprehensive fix pass closed, with the item and the record
(`progress/fixes.md`, `DEVIATIONS.md`) that closed them; a row the review found fixed or not
reproduced is listed with its evidence.

| Row | Closed by | Record |
|---|---|---|
| V6G-1 | F-7 (the `<<-` and `assign()` sentence: F-88) | FIX-37 |
| R6-REG-3, R6-GATE-5 | F-6 | FIX-37, D-293 |
| V6G-N1 | F-16 | FIX-37, D-293 |
| V6G-N2, V6G-N3 | F-17 (the `getcwd()` idiom documented: F-88) | FIX-37, D-294 |
| V6G-N4 | F-15 | FIX-37, D-293 |
| L-1 | F-10 | FIX-37, D-292 |
| V6G-N5 | F-23 | FIX-37 |
| W6-1 | F-18 | FIX-37, D-293 |
| L-5 | F-19 | FIX-37, D-293 |
| V6S-1 | F-28 | FIX-38, D-295 |
| V6S-2 | F-21 | FIX-37 |
| V6S-3 | F-22 (documented) | FIX-37, D-294 |
| V6S-4 | F-88 (documented) | FIX-44 |
| V6S-5 | F-24 | FIX-37 |
| V6S-6 | F-25 | FIX-37 |
| V6T-1 | F-44 | FIX-40 |
| V6T-2 | F-166 | FIX-48 |
| L-69 | F-45 | FIX-40 |
| L-26 | F-141 (the cheat sheet PDF), F-164 (`880e7ea4`, the Why lines); the merge was done | FIX-47, FIX-48 |
| PV-4 (a) | F-145 | FIX-47 |
| PV-1 | F-148 | FIX-47 |
| V6C-4, V6C-5 | F-167 (V6C-5 needs no action) | FIX-48 |
| L-34 | F-74, F-92 | FIX-41, FIX-46, CI-106 |
| L-36 | not reproduced: test-perm-classify.R is in Windows shard 1, which passed on release and oldrel-4 at `5930c8f9` and `f690afc7` | the review's Closed list |
| L-43 | not reproduced: all nine Windows jobs got through setup at `5930c8f9` and `f690afc7` | the review's Closed list |
| L-46 | F-135 | CI-106 |
| L-47 | not reproduced: Linux setup steps took about 50 s in the hosted jobs | the review's Closed list |
| L-48 | F-92 | FIX-46, CI-106 |
| L-72 | F-30 | FIX-39, CI-106 |
| L-54 | F-139 | CI-106 |
| L-56 | not reproduced: a full run against the installed package found no test whose result depends on loaded namespaces | the review's Closed list |
| L-61 | F-149 | FIX-47 |

## Round 6 findings that are fixed

The lens findings of round 6, with the branch and commits that fixed them (all merged into
`25f83241`); a residual named in the first column is a row above. The branch gate6 is
`claude/v1-fix-gate6`, and so for win6, secret6, console6 and trans6. The verifiers' own first-round
findings (gate6's four, secret6's six, console6's F-1, trans6's first and its notes 2 and 3) were
fixed on the same branches before their final verdicts, as `progress/fixes.md` records.

| Finding | Branch | Commits |
|---|---|---|
| R6-GATE-1, and R6-REG-3's `setwd("..")` | gate6 | `9717f384` |
| R6-GATE-2 | gate6 | `db2b2242` |
| R6-GATE-3 | gate6 | `091d59b5`, `0771e8d3` |
| R6-GATE-4 | gate6 | `e97a7f5b`, `6a262830` |
| R6-GATE-5, R6-REG-3 (residuals: two rows) | gate6 | `b6f22118`, `ba95834f` |
| sec-gate's `eval(quote(q()))` note | gate6 | `b355c1ca`, `1f6d7cdd` |
| sec-gate's `os.chdir('..')` note | gate6 | `e4bea33b`, `ba2333bf` |
| R6-NOTE-1 | gate6 | `a0973d86` |
| R6-REG-1, R6-CRAN-1 (test; W6-1) | win6 | `60427c7e` |
| R6-REG-4, R6-CRAN-2 (test) | win6 | `6e43b975`, `307287e9` |
| R6-SS-1 (residual: V6S-1, L-64) | secret6 | `076fbc90`, `f9cf1ea0`, `40770c71`, `8d7a7fff` |
| R6-SS-2 | secret6 | `22fd71f9`, `1ddf572f` |
| R6-SS-3 | secret6 | `ec95f836`, `bd80c168`, `a539786a` |
| R6-SS-4 (residual: V6S-2), SC-5 | secret6 | `6438b19d`, `02a19d34` |
| R6-SS-5 | secret6 | `200c09e9` |
| R6-SS-6 (residual: its row) | secret6 | `318cc940` |
| R6-SS-7 | secret6 | `65412ba4`, `058b571e` |
| R6-SS-8 | secret6 | `1dfeb662` |
| SC-1 | console6 | `26c42473`, `1e0c58e2` |
| SC-2 (documented; L-9) | console6 | `a3d081e5` |
| SC-3 | console6 | `a641de77` |
| SC-4 | console6 | `032698d9` |
| T6-1 | console6 | `ed129da2` |
| R6-REG-2 (residual: its row) | trans6 | `c3506872` |
| T6-2 | trans6 | `7fd767b9`, `bf619da7` |
| T6-3 | trans6 | `3af6ae8c` |
| T6-4 | trans6 | `5977ea34`, `e3cc6858`, `010dabfa` |
| R6-D1, R6-D2, R6-D3, R6-D4 | `claude/v1-fixes` | `25f83241` |
| R6-D5, R6-D6 | `claude/v1-fixes` | `0c3e7f2f` |

R6-CRAN-3 is open (above), and R6-D3 (d) needed no Open item, since R6-SS-3's fix covers it.
