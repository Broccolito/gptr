# Open findings before the comprehensive review

This ledger lists every finding still open on `claude/v1-fixes` (PR #93) at `25f83241`, the records
commit after review round 6's merge of its four fix branches (`909350e6`), on 2026-10-28. That day
the maintainer paused the iterative verify-and-fix rounds: what was running was finished and
recorded, and nothing found since is fixed now (a test that a merge breaks is still fixed, test
first). PR #94 (`claude/pr92-propagate`) carries contributor PR #92's wording through the repository
and merges into `main` first; `main` is then merged into this branch, and one comprehensive review
and one comprehensive fix follow before the CRAN submission. This file is that review's input. Its
sources: round 6's seven lens verdicts, the four fix writers' reports and their verifiers' final
verdicts, the Windows verdict, PR #94's writer and verifier, the Open lists of `dev/HANDOFF.md` and
`dev/PROGRESS.md` (which agree), the Open bullets of FIX-20, FIX-27..FIX-36, CI-87, CI-88, CI-93,
CI-104 and CI-105 in `progress/fixes.md`, the status, Limits and Not covered lines of D-262..D-272,
the session handoffs of 2026-10-27 (its sections 3, 4 and 8) and 2026-10-28, and the release steps
not yet done. A row merges every source that names the same item and keeps each source id. Fixed
items are left out; the last section lists round 6's fixed findings by branch. CI-87's and CI-88's
notes are closed by CI-99 and CI-101 but for one residual (L-48). An independent completeness check
of the first version (`a3d18f40`) added L-62 to L-71 and PW-2, corrected this paragraph and the rows
V6G-1, V6G-N4, L-5 and L-26 (each re-measured or re-run here), and filled in what other rows had
left out; row ids are stable, V6S-7 is split into V6S-7a and V6S-7b, and L-53 is folded into L-31.

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

- **V6G-1**, also the gate6 first verifier's note (b) (low to medium; new, of `b6f22118`, where
  `2bb1fcc1` read 4 and `main` reads every `setwd()` 2). `local()` treats a name it assigns into an
  enclosing environment as its own:
  `d = 'data'; local({ assign('d', <outside>, inherits = TRUE) }); setwd(d)` and its
  `envir = globalenv()`, `envir = parent.frame()` and `pos = 1` forms and
  `local({ list2env(list(d = <outside>), globalenv()) })` read 2, and `eval()` or `evalq()` with
  `envir = globalenv()` read 3 (with `unlink(p)` in place of `setwd(d)` every one of these forms
  reads 3), so auto and yolo move R out of the project unasked (end to end), where `?gptr_security`
  says yolo asks; the merged code still reads 2 (probed again on an install of `a3d18f40`).
  Evidence: `R/perm-classify.R:2916` (only `<<-` adds to `sup`) and `:3037`;
  `state/fix6-results.json` "verify6 gate6 round 2" Finding 1 and "verify6 gate6" note (b);
  `B/gate6v/` (`e2e-*.tsv`, `local-assign-fix.diff`); `dev/progress/fixes.md:9121`. Fix (verified in
  a copy): at `:2916` add to `sup` for `op %in% c("<<-", "assign") || isTRUE(ctx$outer)`, after
  `:3037` set `inner$outer` for `eval`, `evalq`, `with` and `within`, add the test row (4), and say
  in `?gptr_security` that a name assigned with `<<-` or `assign()` counts outside them.
- **R6-REG-3, R6-GATE-5** (residuals; medium; yes, `main` read them 2). These idioms still read 4,
  ask in auto and yolo and stop a non-interactive auto run (Rscript, knitr): `setwd(here::here())`,
  `setwd(here::here("data"))`, `withr::with_dir(here::here("data"), ...)`,
  `setwd(dirname(rstudioapi::getSourceEditorContext()$path))`, and the save-and-restore idiom with
  its directory saved in a branch, a loop or another call's argument (`if (p) owd = setwd("data")`,
  `tryCatch(..., finally = setwd(owd))`, `lapply(dirs, function(d) withr::with_dir(d, ...))`);
  documented as a directory the code computes. After `setwd(tempdir())` relative paths other than a
  `setwd()` target are still placed in the project root. Evidence: `dev/HANDOFF.md:339-343`;
  `state/round6-verdicts.json` "r6 regressions" R6-REG-3 (GPT-5.6 asked live,
  `G/live/r6-regressions/con/out5/`; knitr in `G/live/r6-regressions/knit/`) and "r6 sec-gate"
  R6-GATE-5; `state/fix6-results.json` "fix6 gate6"; `R/perm-classify.R:2774-2790`. Fix: fold
  `here::here(<literals>)` to the project root as `tempdir()` is folded; read a scope that restores
  the directory it saved as the top-level idiom; at least make a computed target the same scope
  restores level 3, and name the forms in NEWS and the yolo notice if they stay 4.
- **V6G-N1**, also the gate6 first verifier's note (a) (low; yes, 2 on `main`).
  `withr::with_dir("data", x); setwd("sub")` and `xfun::in_dir("data", x); setwd("data")` read 4 and
  ask in auto and yolo (end to end): `with_dir()` and `in_dir()` leave `NA` in the tracked
  directory, which round 6's join reads as computed. Evidence: `dev/HANDOFF.md:346-347`;
  `state/fix6-results.json` "verify6 gate6 round 2" N1; `R/perm-classify.R:2777-2786`. Fix: restore
  the tracked directory (`attr(known, "wd")`) after walking `with_dir()`'s and `in_dir()`'s
  arguments, about 3 lines in `walk()`; the maintainer's call.
- **V6G-N2, V6G-N3**, also the gate6 writer's round 2 note (low; yes, `main` read Python's `chdir()`
  at level 1). New questions from Python's `chdir()`: `peter$py("print('call os.chdir(d) first')")`
  reads 4 (a `chdir(` inside a string); the restore idiom
  `cwd = os.getcwd(); os.chdir('data'); os.chdir(cwd)` reads 4; a round trip inside a function, an
  `if` or a file with a triple-quoted string still asks, since only an `os.chdir()` statement on a
  line with no indentation moves R. All ask in auto and yolo (end to end). Evidence:
  `R/perm-classify.R:1839-1862` (the loop scans text that still holds its strings);
  `state/fix6-results.json` "verify6 gate6 round 2" N2 and N3, "fix6 gate6 round 2" notes. Fix: skip
  a line whose string-blanked text holds no `chdir(` (one line, N2); name the `getcwd()` idiom in
  `?gptr_security` (N3).
- **V6G-N4** (low to medium; yes, in time). Directory candidates are joined as text and never
  normalised, and each branched relative `setwd()` doubles them, so the classifier's time about
  doubles with each such line, and the gate runs it before every `r` call and holds the session
  meanwhile. Alternating `if (p) setwd('a')` and `if (q) setwd('..')` lines (level 4) take 0.28 s at
  10 lines, 0.76 s at 12, 2.08 s at 14 and 5.41 s at 16 (0.02 s before); independent lines
  `if (pK) setwd('dK')` take 0.63 s at 10, 2.62 s at 12, 10.2 s at 14 and 41.7 s at 16 and still
  read level 2 (the completeness check measured 167 s at 18, so 24 such lines would take hours).
  `risk_python()` on 400 KB of Python takes 0.47 s (0.19 s on `2bb1fcc1`), and 0.86 s on 564 KB.
  Evidence: `R/perm-classify.R:2783`; `state/fix6-results.json` "verify6 gate6 round 2" N4 and its
  timing line; this revision's timings on an install of `a3d18f40` at a load near 20. Fix: read a
  directory with more than about 64 candidates as computed.
- **L-1** (low; yes, `main` read every `setwd()` 2; the maintainer's call). In a project inside a
  protected folder (`.git`, `.claude` or `.aws`; Claude Code's worktrees sit in `.claude/worktrees`)
  every directory is protected, so `setwd('.')` and `setwd('sub')` are level 4 and ask in every mode
  there. Evidence: `dev/HANDOFF.md:348-350`; `dev/progress/fixes.md:6534-6536` (FIX-27 review
  round 5); the 2026-10-28 08:35 entry of `SESSION-HANDOFF.md`. Fix: none proposed.
- **L-2** (low; yes). The drive-relative rule (`D:x` is outside on every OS) raises unrelated
  readings: `rm -rf ${X:-build}` with a one-letter name 3 to 4, `readLines("a:b.txt")` 0 to 1,
  `rm a:b` 3 to 4, and `cd <outside> && git commit -m 'rm -rf build'` 2 to 4 (the literal scan reads
  the message in the outside directory); no Open list names them. Evidence:
  `dev/progress/fixes.md:6322-6326` (FIX-27 review round 4, the fixes' verifier). Fix: none
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
  the maintainer's call; the rest is documented.
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
  word needs a tokenizer of its own.
- **V6G-N5** (nit; no). `do.call()` with its default `quote = FALSE` evaluates a quoted list
  element, but the classifier and the evaluator's guard read `f(quote(x))`, so
  `do.call(identity, list(quote(unlink('<outside>/x'))))` is level 2 and
  `do.call(identity, list(quote(q())))` is not refused, as before round 6 (the class of code that
  builds a call). Evidence: `R/perm-classify.R:2565` (`direct_call`), `R/eval-guard.R:95`
  (`eval_guard_direct()`); `state/fix6-results.json` "verify6 gate6 round 2" N5. Fix: unwrap the
  `quote()` elements of a written-out list when `quote` is not `TRUE`, in both.
- **W6-1**, also the classifier half of R6-REG-1 and R6-CRAN-1 and FIX-27 round 6's Not changed
  (low; no). `risk_args()` matches a package call's arguments to its formals only while that
  namespace is loaded, so a reading depends on load state: with fs not loaded
  `fs::link_create(p = <outside>, n = 'lnk')` reads 2 where `?gptr_security` says 4 (4 with fs
  loaded), and so for each row of a package that is not loaded. Evidence: `R/perm-classify.R:2281`;
  `state/win6-verify.json` findings; `state/round6-verdicts.json` "r6 regressions" R6-REG-1 and "r6
  cran" R6-CRAN-1; `dev/progress/fixes.md:6640-6643`. Fix: give the classifier the formals of the
  table's package functions as written, as `ba95834f` does for withr's `local_tempdir()`.
- **L-5** (low; no; the maintainer's call). `file.rename()` and `fs::file_move()` remove their
  source, which is not read as a delete: a move of a file outside the project into it is level 2.
  The reading also depends on load state, as W6-1's does: `fs::file_move(<outside>/f, 'f')` reads 3
  while fs is not loaded and 2 once it is (written with `path =` and `new_path =` it reads 2 either
  way). Evidence: `dev/HANDOFF.md:344-345`; `state/fix6-results.json` "fix6 gate6" records; probes
  on an install of `a3d18f40`. Fix: none proposed.
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
  documented as a class, the maintainer's call.
- **L-63**, also D-262's Accepted false refusals and FIX-36's accepted false question (low; yes,
  costs of this branch's rules on code `main` ran unasked). In auto and yolo
  `cmd = "ls"; system(cmd)`, `system2("git", c("log", n))`, `system2("ls", character())` and a
  function defined but never called (`f = function(x) system(x)`) are refused (level 3 `dynamic`),
  each costing one round trip to `peter$sh()` or an `r(fn:)` rule (`do.call(system, list("ls"))` is
  no longer refused since R6-GATE-4's fix, `e97a7f5b`). In auto,
  `os.environ["MPLCONFIGDIR"] = os.path.join(os.environ["HOME"], ".mpl")` in Python and
  `lapply(nms, Sys.unsetenv)` read level 4 `control` and ask. Evidence:
  `dev/DEVIATIONS.md:7905-7911`; `dev/progress/fixes.md:9469-9478` and `:9875-9886`; probes on an
  install of `a3d18f40`. Fix: none; accepted when the rules were written.

## Secrets and redaction

- **V6S-1** (medium; no, the promise is this branch's). `?gptr_security` lists `$NAME`, `${NAME}`
  and a `.env` read in a command line as secret reads and says that sending a secret over the
  network asks in every mode, yolo included, but such a read is no source for that question: in
  yolo, answered no, `v = system('echo $FAKE_API_KEY', intern = TRUE)`,
  `v = peter$sh(c('cat', '.env'))$stdout` or
  `v = processx::run('sh', c('-c', 'echo $FAKE_API_KEY'))$stdout` followed by
  `curl::curl_fetch_memory()`, `download.file()` or a `curl` command ran with no question, also
  split over two `r` calls (no taint is recorded). The documented limits beside it are L-64.
  Evidence: `R/auth-secrets.R:690-698` (the sources are `secret_scan()`'s own),
  `R/perm-classify.R:421` (`risk_secret_rows()`), `R/gptr-config.R:1790-1808`;
  `state/prop-secret6-results.json` "verify6 secret6 final" finding 1; `B/fr6v3/`. Fix: in
  `secret_scan()`, when the code starts a process, add a source for each registered name a string
  names as `$NAME` or `${NAME}` (`secret_env_registered`) and for each word `scan_env_file()`
  matches (`secret_file`), which also taints the assigned names; or narrow the network sentence to
  reads by `Sys.getenv()`, an R file read or an environment dump.
- **V6S-2**, the residual of R6-SS-4 (low; no, `3cd3b146` showed the key in 3 rendered lines). The
  redacted request and condition keep the key in `attr(risk$flagged, "hidden")`, `risk_cmd_line()`'s
  working attribute, which `redact()` and `redact_tree()` do not reach: in yolo with
  `gptr_permissions(ask = 'r(sh:touch *)')` and the key in a `shQuote()`d path, the question and the
  `?` view hold no copy, but the request every UI is given, the `permission_request` hook payload,
  `str(err$risk)` and `run$blocked` hold one, against IC-53 item 8 and D-267's status. Evidence:
  `R/perm-classify.R:1604-1610` and `:2109-2114`; `state/prop-secret6-results.json` "verify6 secret6
  final" finding 2. Fix (tested): in `risk_new()`, after `g = risk_secret_guard(flags)`, set
  `attr(flags, "hidden")` and `attr(flags, "dirs")` to `NULL`.
- **V6S-3** (low; new, of `ec95f836`; `main` gated no served member, which FIX-32's round 1 added).
  With `gptr_permissions(deny = 'script')` or `ask = 'script'`, an idle served
  `x = peter$script('s.R')` that hands over no secret now runs in auto and yolo, where `3cd3b146`
  denied it: the member call is gated only when it meets the secret guard. The loop never honoured
  such a rule, and `?gptr_permissions` does not name member tools as rule targets. Evidence:
  `R/mcp-server.R:363`; `state/prop-secret6-results.json` "verify6 secret6 final" finding 3. Fix:
  keep the member call for `script` (`isTRUE(call$risk$secret_guard) || identical(name, "script")`),
  or say in IC-57 that tool-name rules do not apply to served members.
- **V6S-4**, also the gate6 first verifier's note (c) (low; no). `?gptr_security` lists a read of a
  `.env` file by a function that reads its text such as `readLines()` with no caveat, but
  `x = lapply('.env', readLines)` (level 1) and `file.copy('.env', 'k.txt'); x = readLines('k.txt')`
  (level 2) run in auto with no question and the key reaches R; since the merge
  `do.call(readLines, list('.env'))` and `rlang::exec(readLines, '.env')` ask (level 3, `secret`).
  Likewise `file.copy("~/.ssh/id_rsa", "data/k")` is level 2: a copy's source is not read as a
  secret file. Evidence: `R/gptr-config.R:1795-1796`; `state/prop-secret6-results.json` "verify6
  secret6 final" finding 4; `state/fix6-results.json` "verify6 gate6" note (c);
  `dev/progress/fixes.md:9132-9134`. Fix: one sentence: a read through `lapply()` or another
  function that calls the reader, or of a copy, is not read.
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
  side.
- **L-7** (low; no, the cost of a new guard). A registered secret handed to a child through `env`
  asks each time in auto and twice in manual unless the same code reads it by name, and the idle
  gate does not take the level 3 of an ordinary variable passed through. Evidence:
  `dev/HANDOFF.md:357-359` (FIX-32 review round 5); D-267. Fix: none proposed.
- **R6-SS-6** (residual; low; no; the maintainer's call). Output the console does not indent (a
  console that cannot redraw a line, or `gptr.verbose` below 2) reaches the screen through R's split
  sink and shows a secret model code prints, on the screen only; the margin and the teed warnings
  are redacted since `318cc940`. Only a tee that displays at flush points could filter it, which
  ends live output. Evidence: `dev/HANDOFF.md:361-363`; `state/fix6-results.json` "fix6 secret6"
  notes; `state/round6-verdicts.json` "r6 sec-secrets" R6-SS-6. Fix: none proposed.
- **L-8** (low; no). An authenticated proxy variable (`HTTPS_PROXY` with a password) is not
  secret-looking, so discovery still registers its password as `HTTPS_PROXY_PASSWORD` (CI-99).
  Evidence: `dev/HANDOFF.md:388-389`. Fix: none proposed.
- **V6S-5** (nit, a test gap; n/a). Mutant M25, which drops `bridge_risk_env()`'s keeping of the
  command's own guard (`R/bridge-sh.R:799`), keeps perm-gate, bridge-sh, agent-dispatch and
  mcp-server green, while under it
  `cmd = paste('cat', '.env'); x = peter$sh(cmd, env = 'HOME')$stdout` runs in auto unasked.
  Evidence: `state/prop-secret6-results.json` "verify6 secret6 final" finding 5. Fix: add that form
  to test-perm-gate.R's round 6 loop test.
- **V6S-6** (nit, a test gap; n/a). Mutant M28, which drops `risk_secret_rows()`'s registered-name
  arm (`R/perm-classify.R:428`), keeps auth-secrets and perm-gate green, while under it
  `system('echo $PLAIN_NAME')` for a registered name that does not look secret is level 1 unguarded.
  Evidence: "verify6 secret6 final" finding 6. Fix: one `risk_classify()` assertion with such a
  name.
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
  install of `a3d18f40`. Fix: none; documented.
- **L-68**, FIX-20's Open (low; no). A secret question asked under `.stdin = TRUE` on a tty is shown
  by the terminal's own echo, before and after FIX-20's echo fix. Evidence:
  `dev/progress/fixes.md:5053-5054`. Fix: none proposed.

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
  read after an end marker until a quiet period, was not taken.
- **L-10** (low; no). In a terminal that ignores bracketed paste a paste still splits when a read
  comes more than about 145 ms late (IC-76's 0.2 s bound; CI-94, FIX-28). Evidence:
  `dev/HANDOFF.md:437-438`. Fix: none proposed.
- **L-11**, also FIX-34 PASTE-1 and section 4 of the 2026-10-27 handoff (low; no). On macOS a
  two-line paste without a final newline answers a question with its first line, as documented;
  outside a macOS terminal a block pasted at a question arrives one line at a time. Evidence:
  `dev/HANDOFF.md:419-420`; `dev/progress/fixes.md:8420-8427`; D-269. Fix: the triager's read of the
  waiting input in `tty_drain_mode()` was not taken, since it would also take a key typed just after
  Enter.
- **L-12** (nit; new, FIX-34's merge). The console's not-run row cuts a guard refusal's long reason.
  Evidence: `dev/HANDOFF.md:420-421`; `dev/progress/fixes.md:8534-8535`. Fix: none proposed.
- **L-13**, also FIX-34 review round 5 and the regressions lens's R6AT2 (low; no). Tab writes an `@`
  name holding a space or other punctuation without quotes, which the mention does not read whole
  (quoting it would end the word, so it needs `console_trigger()` to read a quoted word); in a UTF-8
  locale R's regular expressions read no mention in a line holding a file name that is not valid
  UTF-8; Rgui and Rterm in a code page hold only its characters; an `@` written straight after CJK
  text with no space attaches nothing, on this head and on `main`. Evidence:
  `dev/HANDOFF.md:422-425`; `dev/progress/fixes.md:8895-8900`; `state/round6-verdicts.json` "r6
  regressions" (b). Fix: none proposed beyond `console_trigger()`.
- **L-14** (nit; yes, by design, D-244). Under `rc.settings(quotes = FALSE)` a `!` line's string
  completes nothing at the prompt, where readline used to offer every file name. Evidence:
  `dev/DEVIATIONS.md:6158-6163`; `dev/progress/fixes.md:8813-8814`. Fix: none proposed.
- **L-15** (nit; no). Tab offers file names holding U+2028 or U+2029, and `ui_escape()` leaves them,
  as they are neither C0 nor C1; a transcript's header values keep them too, and keep bidi and
  zero-width characters, as they keep all non-ASCII text, and its output lines keep a tab
  (documented in FIX-29 and D-264). Evidence: `state/round6-verdicts.json` "r6 sec-console" summary;
  `dev/progress/fixes.md:7234-7237`. Fix: none proposed.
- **L-16** (low; no). R draws no prompt again after a background callback's output, so the person
  types on a row without `> ` (FIX-21 L1). Evidence: `dev/HANDOFF.md:374-375`. Fix: none proposed.
- **L-17**, also PERM-9's second half and D-267 (b) (nit; no). An approved `system()` child's output
  starts on the frozen `r` row. Evidence: `dev/HANDOFF.md:355`; `dev/progress/fixes.md:7550-7555`.
  Fix: none taken; ending or clearing the row before evaluation drops IC-82's cue or erases the
  child's last line.
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
  `dev/DEVIATIONS.md:8062-8081`; `dev/progress/fixes.md:6953-6968`. Fix: none proposed.
- **L-70**, FIX-20's other Open notes (nit; no). `gptr_step()` on a background session relies on the
  timer to release it (at R's prompt the idle tick releases it at once), and the live row of a
  `system()` child's output stays smeared (D-253, no runtime change, as the verdict advised).
  Evidence: `dev/progress/fixes.md:5007-5008` and `:5022-5023`. Fix: none proposed.

## Transcripts and documents

- **V6T-1** (low; new, FIX-29's `uses undone`, which `main` lacks). `doc_re_direct` ends the reason
  at the first `) ` and `ui_escape()` leaves `)`, so a model-chosen name holding `) `, such as
  `a) created=zz`, leaks `created=zz)` into the header's key=value part: a forged `created=` can
  switch a few later lines off, and the rescan rewrites the header once more before it is stable,
  against FIX-29's record that only the reason's `uses undone ` prefix is read back. Evidence:
  `R/doc-replay.R:953`, `:1003` and `:1040`; `state/fix6-results.json` "verify6 trans6 round 2" note
  1; `dev/progress/fixes.md:7244-7247`. Fix: write the names with `)` escaped, or leave out names
  holding `)` as `doc_direct_header()` leaves out comma names; otherwise limit the record to names
  holding a control character.
- **V6T-2** (nit, records; n/a). Control characters inside the model's own code (a string or a
  comment) are kept, since the code must run as written, so a raw ESC or BEL there reaches the
  transcript; `5977ea34`'s message, FIX-29's Not changed lists and D-264's status do not say so.
  Evidence: `state/fix6-results.json` "verify6 trans6 round 2" note 2;
  `dev/progress/fixes.md:7215-7236` and `:9137`; `dev/DEVIATIONS.md:8198-8208`. Fix: append that
  sentence to FIX-29 and to D-264's status.
- **V6T-3**, the trans6 verifier's observation (nit; yes, in time, on an extension evaluator's path
  only). `doc_output_lines()` takes about 0.5 s for an output vector of 100k elements or 40 lines of
  1e5 characters (0.02 s before); the built-in evaluator's path is unchanged at 0.03 s. Evidence:
  `R/doc-blocks.R:1172`; `state/fix6-results.json` "verify6 trans6 round 2" observations. Fix: none
  proposed.
- **R6-REG-2** (residual; nit; no). A block `main` recorded and an editor then trimmed, or whose
  code had CRLF line ends, reads user-edited, as on `main`; one whose code held a lone carriage
  return now does too (`main` read it fresh but could not source that document). A transcript whose
  only line ends are lone carriage returns is rewritten with LF line ends once, on gptr's next write
  to it (a round 6 test asserts it). Evidence: `dev/progress/fixes.md:8298-8302`; D-268;
  `state/fix6-results.json` "verify6 trans6 round 2" findings. Fix: none needed (documented).
- **L-18**, also D-264's Known limits (low, documented; no). A later console turn that uses an
  object made by a direct R line that is off still stops `source()`, as the undo kept the object;
  `all.names()` can match a column or formula term of the same name and switch a line off; a name
  reached through a string (`get("fit")`) is not seen; a non-ASCII name is matched only in a UTF-8
  locale (FIX-29); lines written by hand right after a direct R line switch off with it; a name
  holding a comma is left out of `created=`, so a line using it is not switched; and the `#<` lines
  are what was sent, so neither `gptr.doc_output_lines` nor the `doc` setting limits them. Evidence:
  `dev/HANDOFF.md:404-405`; `dev/DEVIATIONS.md:8186-8197`. Fix: none proposed.
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
  Fix: none proposed.
- **L-20** (low; no). A line of `!` code that reads as another entry's first line but is not a
  comment still ends its section (FIX-31); a marker line inside a multi-line string of `!` code
  leaves the transcript's markers malformed, which the next block write names (FIX-33). Evidence:
  `dev/HANDOFF.md:410-412`; `dev/progress/fixes.md:8028-8033`. Fix: none proposed.
- **L-21** (low; no). FIX-33's open items: a direct R line that read an object a turn changed stays
  on after the undo and replays with the restored value (DOC-3); a turn sent from outside the
  console is retried with the pending notes only (DOC-6); artifact references without `.gptr/` name
  `tempdir()/gptr` (MM-4); code recorded despite `record = false` has no `#>` output (ALL-3);
  claude-cli and codex blocks record `model=claude-cli/default` and `codex/default` (ALL-6); a
  refused turn records an empty block (PERM-8); a live re-ask sends neither a block's steering lines
  nor an `n <text>` answer, and the new block does not keep them (ALL-1, documented; L-23 is its
  script-replay twin). Evidence: `dev/HANDOFF.md:413-418`; `dev/progress/fixes.md:8101-8169`. Fix:
  none proposed.
- **L-22** (nit; no). An exported transcript keeps its replay note, which names the source
  transcript, and a refusal names no line (FIX-25, FIX-33). Evidence: `dev/HANDOFF.md:386-387`;
  `dev/progress/fixes.md:8120-8121`. Fix: none proposed.
- **L-23** (low; no). A replayed script sends again a steer its run took after the script went on (a
  run sent to the background from the pause menu, a `gptr_wait(timeout =)` that returned early), and
  a `gptr_step(s, <n>)` that ended the run keeps the notes, so a later equal turn is still skipped
  (FIX-22). Evidence: `dev/HANDOFF.md:367-370`. Fix: none proposed.
- **L-24** (low; no). From FIX-21: a console transcript repeats the call's prompt for the turn a
  parked session resumes and does not record the console note it answered (L3); a direct R line
  naming a session by a variable bound at R's prompt (`!!gptr::gptr_wait(b)`) stops the replay;
  `gptr_wait()` on a waiting session, called from inside a run's tool, resumes it as a nested run
  that inherits the outer run's safety record (the gate still asks). Evidence:
  `dev/HANDOFF.md:376-382`. Fix: none proposed.
- **L-25** (nit; no). Replayed closures and `function` calls have no srcref where the agent's keep a
  `<gptr>` one, so a replayed ggplot is 1,412 bytes smaller serialized and 768 bytes by
  `env_snap_size()`; an expression that names `peter()` still makes its objects with the document's
  srcrefs (FIX-24). Evidence: `dev/HANDOFF.md:383-385`. Fix: none proposed.
- **L-69**, FIX-20's Open, found in passing (low; no; to triage). A console transcript with a
  `{name}` prompt cannot replay without a model: `doc_console_site()` sets `args_hash = NULL`, so
  its block reads stale under `GPTR_REPLAY=replay`. Evidence: `dev/progress/fixes.md:5173-5175`
  (R27's evidence, `doc-locate.R`). Fix: none proposed; triage first.

## Docs and records

- **L-26**, also PV-2, PV-3 and CI-105's Open line (medium; n/a, a merge step). This branch and
  `claude/pr92-propagate` (#94) each carry their own CI-105 and D-270 for PR #92, and they differ:
  this branch's D-270 says P01, P25 and 05 keep the old Title, #94 gives them the new one; both
  D-270s have a `- Why:` line, which no other entry has; #94's HANDOFF and PROGRESS headers name no
  D-270; #94's records give #92's merge no sha (it is `880e7ea4`); this branch made its own README
  and vignette corrections (CI-105 review round 4) beside #94's three. A trial merge of #94 into
  `25f83241` conflicts in `R/gptr-gateway.R`, `man/peter.Rd`, `README.Rmd`, `README.md`,
  `pkgdown/assets/gptr-cheatsheet.pdf`, `dev/DEVIATIONS.md`, `dev/HANDOFF.md`, `dev/PROGRESS.md` and
  `dev/progress/fixes.md` (so does one into `a3d18f40`); `origin/main` alone merges clean, and #94
  itself merges clean into `main`, whose head `880e7ea4` is #94's merge base, so the order #94, then
  `main` into this branch, then #93 holds, and the nine conflicts arise only when `main` (with #94)
  is merged into this branch. Evidence: `dev/progress/fixes.md:9182-9268`;
  `dev/DEVIATIONS.md:8715-8735`; `state/prop-secret6-results.json` "propagate verify" findings 2 and
  3 and "propagate writer (continue)" notes; `git merge-tree --write-tree` of `25f83241` and
  `4dd36dc9` (2026-10-28). Fix: one copy of each id goes; fold the Why line into Rule; keep both
  sides' README corrections, then render README.md and the cheat sheet PDF again.
- **PV-4 (a)** (low; n/a; the maintainer's call). PR #92's README links the system-one and
  script-as-history guides as "Typed decisions" and "Record, replay and export", but the vignettes
  keep "System 1 decisions" and "Script as history" (titles, `VignetteIndexEntry`, cross-links,
  getting-started's "Where to go next", the cheat sheet). Evidence: `README.Rmd:146` and `:171`;
  `vignettes/system-one.Rmd:5`, `vignettes/script-as-history.Rmd:5`;
  `state/prop-secret6-results.json` "propagate verify" finding 4 (a) and the writer's
  left_unchanged. Fix: rename both guides site-wide, or link them by their titles.
- **PV-4 (b)** (nit; n/a; the maintainer's call). `CLAUDE.md` and `AGENTS.md` lines 3 and 30 still
  say "an AI agent harness that lives inside the R session" and "Peter Wason (System 1 / System 2
  reasoning)", not PR #92's words; line 30's rule, to keep the Wason and Naur rationale in the
  README and `?peter`, holds. Evidence: `CLAUDE.md:3` and `:30`; "propagate verify" finding 4 (b).
  Fix: align them if wanted; agents do not edit these files on an agent's request.
- **PV-1** (nit; n/a). The token-efficiency vignette opens "The model sees a compact description
  while its R tool computes on the object", where getting-started (on #94) says the model receives
  size-limited descriptions, previews and tool output that may include data values; not wrong.
  Evidence: `vignettes/token-efficiency.Rmd.orig:18`, `vignettes/token-efficiency.Rmd:29`;
  "propagate verify" finding 1. Fix: the same edit, if the disclosure should be everywhere.
- **PW-1**, also PV-5 (nit; n/a). Plan drafts of shipped files had drifted before #92 and are left
  (P25 Tasks 2, 5, 10, 11 and 13, P01 Task 1's Description; P19's goal line and specs 00 and 03 say
  "inside the live R session"); D-270 wins over them. On #94 spec 05's two edited lines are 102 and
  111 columns (110 and 110 on `main`; 05 is not fmt-clean on `main`). Evidence: "propagate writer
  (continue)" left_unchanged; "propagate verify" finding 5. Fix: none proposed.
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
  unless the maintainer wants the phrase gone; a prompt change must pass the prefix gate.
- **V6S-7a**, the first half of "verify6 secret6 final" finding 7 (nit; n/a).
  `dev/progress/fixes.md:7906` is 101 columns, an unbreakable code span holding a test regex; fmt.py
  and lintfmt.py accept it. Evidence: `state/prop-secret6-results.json` "verify6 secret6 final"
  finding 7. Fix: none needed.
- **V6C-4, V6C-5** (nit; n/a). D-264's Tests line does not name test-console-repl.R's round 6 test
  (a lone carriage return ends a `!` note's line), as D-263's lists its own; spec 04 is far from
  fmt-clean on `main`, so fmt.py cannot be held for it. Evidence: `dev/DEVIATIONS.md:8212-8222`;
  `state/fix6-results.json` "verify6 console6 round 2" items 4 and 5. Fix: extend D-264's Tests
  line.

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
  the reverse-dependency date at submission with `cran_comments_set_revdeps()`.
- **L-67**, CI-104's Open (low; no). Points a CRAN reviewer may raise: the six pages of session S3
  methods (`print`, `format`, `str` and `summary` of `gptr_session`; `print` and `as.data.frame` of
  `gptr_session_summary`) have no examples; they are registered methods, not exports, but a reviewer
  may ask for some (B7). 'TypeSafe AI' is quoted as a host, not as software or an API ("hosted by
  TypeSafe AI" is the fallback if a reviewer queries it). The README's 4 GiB figure is one measured
  run (`dev/TESTING_PLAN.md`). Evidence: `dev/progress/fixes.md:6040-6045`. Fix: none proposed;
  answer if asked.
- **L-27** (step; n/a). No `R CMD check` has run since round 6's CRAN lens on `3cd3b146`
  (`isolated-check.R check` FAIL 1, R6-CRAN-1). The merged code had the full suite through
  `devtools::test()`, which loads fs and other namespaces and so could not see R6-CRAN-1, and ten
  changed test files against the installed package. Evidence: `dev/HANDOFF.md:272-283`;
  `dev/progress/fixes.md:9166-9180`. Fix: on the final head, `dev/ci/isolated-check.R check` under
  the heavy lock, the CRAN-mode `R CMD check --as-cran` under `env -i` and the incoming feasibility
  check.
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
  the final checks.
- **L-29** (step; n/a). R-hub (Windows R-devel and R-release, Ubuntu gcc 12) and win-builder
  (R-release, R-oldrelease and R-devel, by e-mail through Outlook) on the final tarball; the
  2026-10-26 runs used `e1b6ca59`'s tarball, and win-builder's R-devel run forwarded on 2026-10-27
  used `main`'s. Evidence: `dev/HANDOFF.md:303-313`; the 2026-10-27 15:10 entry of
  `SESSION-HANDOFF.md`. Fix: run them after L-27 and L-28.
- **L-30** (step; n/a). PR #94 (`4dd36dc9`) is open with its CI running (runs 40775715597 and
  40775715751, then 40775753561 and 40775753543, 2026-10-28); after it merges, `main` is merged into
  this branch (L-26), and #93 merges with a merge commit once its checks and the hosted checks
  (L-29) pass; then `main`'s CI is watched until it is green (section 3 step 8 of the 2026-10-27
  handoff). Evidence: `gh pr list`, `gh run list` (2026-10-28). Fix: as stated.
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
  stated.
- **L-32** (step; n/a). The maintainer's checkout `/Users/wgu/Desktop/gptr` has `main` at `13a917ff`
  (`origin/main` is `880e7ea4`); after the merges, update it, leaving its untracked
  `dev/spec/08-recursive-peter.md` alone, and install gptr from `main` in the maintainer's R, as
  `dev/HANDOFF.md:314-316` did for `c0dd52b7`. Fix: as stated.
- **L-33** (step; n/a). The CRAN submission and P25's live steps are the maintainer's. Evidence:
  `dev/HANDOFF.md:465`. Fix: as stated.
- **L-71** (step; n/a). Report to the maintainer what changed, the checks and the decisions below,
  and update the memory files `gptr-session-handoff.md` and `gptr-readme-voice.md` (the README now
  follows PR #92's structure, which the maintainer approved). Evidence: section 3 step 11 of the
  2026-10-27 handoff. Fix: as stated.

## CI and test infrastructure

- **L-34** (low; no). Absolute time limits fail on GitHub's shared `macos-latest (release)` runner:
  on #92's docs-only commit `71ae6e39` (run 40538439076) the first attempt failed
  test-http-sse.R:133 (INFRA-23, 20,000 deltas under 1 s of CPU: 1.34 s, job 123068236924) and the
  second test-subagent-team.R:109 (`gptr_parallel()` members run concurrently: 5.90 s of wall time
  where the test allows under five seconds, job 123095981276). Locally the merge `0768fb35`'s full
  suite at a load near 215 failed 9 tests in three timing files that pass alone;
  test-proc-windows-backpressure.R:529 (a 2 s stdin write timeout) failed 3 times at a load of 67,
  and fails alike when run alone on `fe873436`'s code; and a timing bound of test-cli-codex.R took
  16.7 s against 13 s at a load near 260. Evidence: `state/extra-ledger-items.md`;
  `dev/HANDOFF.md:218-223`; `dev/progress/fixes.md:6526-6529` and `:8193-8194`. Fix: `skip_on_ci()`
  or a scaled limit, or measure against a calibration loop.
- **L-35** (gap; n/a). No round 6 lens, writer or verifier ran on Windows, Linux, R 4.2 or R-devel;
  Windows readings come from probes with `is_windows()` mocked and from reading the code. Only PR
  #93's Windows and Ubuntu jobs, win-builder and R-hub can prove them (L-28, L-29). Evidence: the
  not_done notes in `state/round6-verdicts.json`; "Not run" in every verdict of
  `state/fix6-results.json`. Fix: as L-28 and L-29.
- **L-36** (low; n/a). test-perm-classify.R "a command run in a directory outside the project reads
  it (review round 4)" writes the raw `tempfile()` path into R code, whose backslashes on Windows
  (`\U`) stop the parse, so its `cd` line may read 0 there, not 1; the Open lists say it has not run
  on Windows, but the regressions lens saw perm-classify pass on Windows shard 4 at `3cd3b146` (run
  40716225723). Evidence: `dev/HANDOFF.md:351-354`; `state/round6-verdicts.json` "r6 regressions"
  (f). Fix: check whether that row ran or skipped there; give it a path with `/`.
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
- **L-38** (gap; n/a). Live evidence is narrow: the gate and secret checks ran live on GPT-5.6
  (`versa/gpt-5.6-sol-2026-07-09`) and the fake only, since Claude Opus 4.8 refused the delete forms
  and the secret-redacted question even under a test framing or through a helper; p28's S10 and the
  S8 variants other than S8-clocale were not run; Ollama ran only S8; Python was not configured for
  the regressions lens, so the `os.environ` forms ran live only in gate6's verifier (reticulate,
  fake model); the docs lens drove no real terminal, so IC-76's bounds (0.1 s, 0.2 s and 145 ms)
  were not measured and spec 04 section 15 was sampled; and the gate lens did not use the tmux
  console driver (its live checks drove `peter()` in Rscript with a scripted UI that answers no).
  Evidence: not_done of "r6 regressions", "r6 sec-gate" and "r6 docs". Fix: none proposed.
- **L-39** (gap; n/a). The incoming check's spelling of DESCRIPTION could not run locally (no
  aspell, hunspell or enchant); CRAN's own check runs it. Evidence: "r6 cran" not_done. Fix: none
  needed.
- **L-40** (low; no). No CRAN-mode test reaches 10 R files (`artifact-registry`, `bridge-lang`,
  `console-jsonl`, `doc-export`, `doc-knitr`, `proc-rscript`, `provider-bedrock`, `s1-emulate`,
  `s1-ollama`, `tool-search`; CI-93); round 6's covr run counts 9. CI-93's other Open note, the
  Windows budget's calibration against win-builder once the new lane has run, stays open too (a
  hosted runner is not win-builder, and its timed step includes the build). Evidence:
  `dev/HANDOFF.md:401-403`; `dev/progress/fixes.md:4856-4860`; "r6 cran" R6-CRAN-3. Fix: none
  proposed.
- **L-66** (nit; no). The static-prefix gate of architecture 12.7 leaves `standard_core` 1 token to
  spare (2335 + 2%), so a change of one word to the static prompt (PW-2's text among it) fails the
  required "token benchmark" check. Evidence: `dev/HANDOFF.md:355-356`;
  `dev/DEVIATIONS.md:8471-8475`; `dev/progress/fixes.md:7522-7524`;
  `state/ruleset-24955100-after.json`. Fix: none proposed.
- **L-41** (low; no). Why the Windows stdin writer exits early is not known: 2 of 1,356 writer cases
  in CI, none in 6,583 measured; a recurrence fails on `writer_failed` in about 5 s, with the
  writer's stderr in the witness (CI-98, CI-101). Evidence: `dev/HANDOFF.md:390-392`. Fix: none
  proposed.
- **L-42** (low; no). The Windows stdin writer's bootstrap stays about 630 bytes under Rscript's
  9998-byte `-e` limit with ordinary paths; it embeds `.libPaths()` and the temp path, so very long
  ones (a 153-character TMPDIR with a long check library: 10,179 bytes) make the writer refuse to
  start (`proc_writer_code_bytes()`, found by #88's CRAN gate). Evidence: `dev/HANDOFF.md:395-398`.
  Fix: none proposed.
- **L-43** (low; no). Windows setup sometimes times out downloading pak from r-lib.github.io (60 s).
  Evidence: `dev/HANDOFF.md:393-394`. Fix: set `R_DEFAULT_INTERNET_TIMEOUT` in `Windows-check.yaml`
  if it recurs.
- **L-44** (low; no). What slowed or stopped pak's subprocess on the reporting Mac, and what removed
  its loaded copy of gptr before `load_all()`, is not in the report (CI-102). Evidence:
  `dev/HANDOFF.md:399-400`. Fix: none proposed.
- **L-45** (low; no). A Windows security block near 500 ms can cross D-240's 500 ms line between
  runs (CI-95). Evidence: `dev/HANDOFF.md:439`. Fix: none proposed.
- **L-46** (low; no). The macOS row's time grows with its serial pty tests (CI-96). Evidence:
  `dev/HANDOFF.md:454`. Fix: none proposed.
- **L-47** (low; no). Ubuntu's apt mirror stalled hosted CI: on 2026-10-25 two Ubuntu jobs reached
  their 45-minute limit after setups of 30 and 19 minutes, and on 2026-10-26 (#88) it stalled the
  token benchmark's install until its 30-minute limit; the re-runs passed. Evidence:
  `dev/HANDOFF.md:459-462`. Fix: re-run.
- **L-48** (low; no). CI-88's last note: the cold controls' 2 s stdin bound fails under CPU
  saturation (22 of 1,800 with one busy loop per CPU), which hosted runs have not shown; CI-101
  closed its other notes. Evidence: `dev/progress/fixes.md:1792-1812` and `:5484-5485`. Fix: none
  proposed.
- **L-49** (low; no). A `process_jsonl` line's events still follow the abort flag (its adapters
  check the signal themselves, 04 section 8.1), an `inprocess` generator keeps its two calls after
  it, and the partial of an abort inside a unit holds what was emitted only for a normaliser that
  records a delta before it emits it (FIX-26, CI-97). Evidence: `dev/HANDOFF.md:455-458`. Fix: none
  proposed.
- **L-72** (low; no). A timing-sensitive pty test failed on GitHub's `ubuntu-latest (release)`
  runner: on #93's head `0c61c453` (run 40784878426, job 123174204936) only test-console-typing.R
  "a terminal: after r code reads through readline a paste is one draft" (FIX-28) failed, at :1600
  (`pty$wait("REQ 1 [one/two/three]")` was FALSE) and so at :1604; every other job of the run
  passed. Evidence: the job's log. Fix: as L-34; re-run the failed job.

## Harness and process

- **L-50** (low; n/a). A Bash call pending well past its timeout with no process behind it is a lost
  tool result; it froze an agent twice in triage, and resuming a workflow with parallel branches
  reorders the calls and reruns finished agents. Evidence: section 8 of
  `handoff-2026-10-27/NEXT-AGENT-HANDOFF.md`; the 2026-10-27 03:30 and 05:20 entries of
  `SESSION-HANDOFF.md`. Fix: stop, then run the rest as a new small workflow with finished results
  passed as files.
- **L-51** (low; n/a). Stopped workflows leave work running: 32 orphaned `yes` load loops (PPID 1)
  ran for 4 hours at a load of 220, and a writer waited for ever for the load to drop below 25;
  macOS services keep the load near 40 to 70, and round 6's lenses ran at loads of 120 to 226, so
  their times are not quiet-machine figures. Evidence: section 8 of `NEXT-AGENT-HANDOFF.md`; "r6
  regressions" and "r6 cran" ran. Fix: after stopping a workflow, look for what its agents left and
  stop it by PID.
- **L-52** (low; n/a). Agents decline a lens worded as getting around the gate. Evidence: section 8
  of `NEXT-AGENT-HANDOFF.md`. Fix: word it as a maintainer-requested coverage check with harmless
  commands, and give the lens schema a `carried_out` flag.
- **L-54** (nit; n/a). The four plan checks fail their index step when `R_LIBS_USER` does not hold
  the development library (the findings name testthat's functions as undefined), and
  `check-plans.py` leaves `dev/ci/__pycache__` unless Python runs with `-B`. Evidence:
  `dev/progress/fixes.md:9176-9178`; "propagate verify" ran. Fix: have the script check its library,
  or say so in its usage.
- **L-55** (nit; n/a). p28's S5 check of `/skill:` completion fails on this head and on `main` with
  the real HOME's many skills (a harness artifact), and claude-cli's first S8 run hit a transient
  "Not logged in". Evidence: "r6 regressions" (c). Fix: run p28 with an isolated HOME.
- **L-56** (low; n/a). The local gate runs tests through `devtools::test()`, which loads fs and
  other namespaces, so a test that depends on load state passes locally and fails in `R CMD check`
  (R6-CRAN-1 reached PR #93's CI that way). Evidence: `state/round6-verdicts.json` "r6 cran"
  R6-CRAN-1; `state/win6-verify.json`. Fix: before a round is called green, run its changed test
  files against the installed package, as round 6's merge did for ten, or run L-27's check.
- **L-57** (nit; n/a). Writers' reports carried claims nobody had established: commit `60427c7e`'s
  body says the Linux and macOS full suites load fs before test-risk-forms.R (a serial run of the
  157 earlier files never loaded it; fixes.md is corrected, the message stays), and win6's report
  counted 249 where the file holds 241. Evidence: `state/win6-verify.json` findings. Fix: verify
  every head, count and cause a writer reports.

## Decisions for the maintainer

Rows above that end in the maintainer's call: L-1, L-3, L-5, L-62, V6G-N1, R6-SS-6 and PV-4. These
have no defect row:

- **PERM-4**, also D-267 (a), section 4 of the 2026-10-27 handoff and the 2026-10-28 session handoff
  (n/a; no). On the codex route Codex's own shell runs outside gptr's gate, rules and secret guard
  in every mode (documented); `-c features.shell_tool=false` in the read-only modes was not taken,
  since IC-65 keeps Codex's shell and that key is not among the flags gptr's capability probe
  checks. Evidence: `dev/progress/fixes.md:7481-7495`; `dev/DEVIATIONS.md:8482-8484`;
  `dev/HANDOFF.md:355-356`. Decide whether to turn it off.
- **FIX-35 F2 and F3** (low; no). At a load average of 260 and more (above 245 in the session
  handoff) the owned browser close's process-table walks (`proc_children()`, `proc_tree()`) can take
  12 to 28 s and use up its 10 s deadline: 4 of 33 closes under 32 busy loops ended "close timed
  out", and 1 of 27 for its verifier. F3, which retries a pending lease's failed cleanup, makes each
  `artifact_browser()` call run that close before it raises (up to 10 s, 14.2 to 43.4 s with F2's
  walks). Evidence: `dev/HANDOFF.md:440-442`; `dev/progress/fixes.md:9322-9329` and `:9386-9391`;
  `dev/DEVIATIONS.md:8776-8779`. Decide whether F2 needs work and whether F3 stays.
- **L-58** (low; no). A job that ends with no pump and no `kill()` before its first status look gets
  its end time at that look, an upper bound; processx 3.9.0's `get_end_time()` gives the exact end
  but needs the processx floor raised from 3.8.0 (FIX-23). Evidence: `dev/HANDOFF.md:371-373`.
  Decide whether to raise the floor.
- **L-59** (n/a). Python's `chdir()` is read as `setwd()` with about 20 lines in `risk_python()`
  (`e4bea33b`, `ba2333bf`); the docs-only alternative reverts both and says that a relative
  `chdir()` literal is read in the project. Evidence: `state/fix6-results.json` "fix6 gate6" and
  "fix6 gate6 round 2" notes. Decide which.
- **L-60** (n/a). The new argument `gptr_source(model =)` (FIX-33, D-268) re-asks a record with
  another model. Evidence: section 4 of `NEXT-AGENT-HANDOFF.md`; `dev/DEVIATIONS.md:8600-8602`.
  Confirm the interface before 1.0.0.
- **L-61** (nit; n/a). NEWS lists features only, and `main` is unreleased, so the writers did not
  add "Transcripts recorded before this release read as fresh again" or "Control characters in
  recorded output and header values are escaped". Evidence: `state/fix6-results.json` "fix6 trans6"
  and "fix6 trans6 round 2" notes. Decide whether NEWS names fixes to unreleased behaviour.

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
