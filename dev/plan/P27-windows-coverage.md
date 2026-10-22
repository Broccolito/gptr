# P27 Windows coverage (2026-10-19)

**Goal:** Prove every Windows function of gptr on GitHub's hosted Windows CI, repeatably:
`windows-latest` R release, oldrel-4 (R 4.2) and R-devel, in CRAN and NOT_CRAN modes, with every
Windows lane green twice on one commit. Branch `claude/windows-coverage-p27`, draft PR
[#51](https://github.com/Broccolito/gptr/pull/51).

**Evidence:** Windows cannot run on the maintainer's Mac. Each fix reasons from the R, processx, ps
and Chromium sources and the hosted logs, reproduces the failure on macOS where it is portable, or
emulates the Win32 calls with stubs (`is_windows()` TRUE, `Sys.readlink()` empty, UCRT `stat()`
facts), and claims Windows behaviour only from hosted runs. Per-fix evidence:
`dev/progress/fixes.md` Tasks CI-25..CI-73.

**Depends on:** P01-P26. **Milestone:** post-M5 maintenance, before CRAN submission.

## Global Constraints

`dev/plan/00-conventions.md` applies in full. Plan-specific rules:

- Issue [#47](https://github.com/Broccolito/gptr/issues/47): no product bound, deadline or
  strictness check is loosened and no test is skipped to get green. A wrong test is corrected; a
  product defect is fixed in product code with a test that is red before the fix; a cause that is
  not proven is called inferred. Two test elapsed bounds were raised from 10 s to 30 s (Task 2).
- A Windows branch that cannot run locally is checked against R's Windows sources and, where
  portable, by a macOS emulation; its Windows status stays pending until a hosted run passes it.
- Ids: fixes CI-25..CI-73, deviations D-228..D-235; every rename, unskip and `dev/ci` registry
  change is named in its commit body.
- Lanes run in worktrees from this branch and are cherry-picked in order; a lane never pushes or
  dispatches a hosted run.

## Gap inventory (base `f4202bb`, 2026-10-18)

| Area | Gap at base | Tasks |
|---|---|---|
| CI lanes | Plan gates required exactly P01..P25, so P26 turned them red; the optional registry kept renamed titles; ordinary windows-by-file had no Python for the no-follow observer (run 39179988023, job 117830492561); optional owned children inherited Git Bash's SeBackup/SeRestore privileges (runs 38840747973, 38840750797); a cold PowerShell start exceeded the ACL script's 5 s guard on Windows R-devel Exact-tarball (jobs 114834115071, 114882859729) | 1 |
| Skipped on Windows | 77 `skip_on_os("windows")` sites. Never run there: the shell routes (Git Bash, PowerShell, cmd), knit engines and `.sh` scripts, a bare `R` MCP command, the orphan sweep after a parent's death, IC-59 crash resume, IC-51 sidecar recovery, junctions and file symlinks in the walker, edit and write tools and path classes, read-only files, drive paths, the credential store's location, the child environment allowlist, CLI stdin beyond the 64 KiB pipe buffer (D-019 item 5) | 2-9 |
| Hosted failures | R-CMD-check's session checks skipped with "startup timed out" (run 39179983061); the #37 `/undo` test failed in CRAN mode (job 117848217386); the IC-60 parent-death case went over the RSS cap in rscript-native (run 39185663719); an exited artifact child "did not settle" (job 117842876468); the preflight's perl probe timed out (job 117847473135); INFRA-01's six-stream wall fails in about 3% of Windows jobs | 1, 8, 10, 11 |
| Found while unskipping | file links renamed over their targets and 8.3 aliases deleted by patch moves; dangling Windows links replaced, opened or warned about (`stat()` succeeds on them and `Sys.readlink()` is empty); a `.gptr` junction onto a foreign directory took the scrub locks there; cmd output in the OEM code page; Store aliases reached by 8.3 name; macOS `kill_all()` leaked a shell's background children; gptr's own document writes recorded as a turn's change | 2-6, 10 |

## Tasks

### Task 1: The CI lanes reach the Windows tests (CI-25..CI-29, CI-42, CI-46, CI-53, CI-57, CI-58)

Decisions:
- `dev/ci/check-plans.py` accepts any contiguous P01..Pnn plan set with n >= 25, and `extract.py`
  extracts every plan.
- The optional registry names current tests only: a pure gate test requires every approved,
  original-OS-guard and skip-allowance title to name a top-level `test_that()` case, and the skip
  allowances are one table, `optional_os_skips`.
- Ordinary windows-by-file runs R-CMD-check's Python pin and provisioning; owned Windows children
  start from pwsh, never Git Bash.
- Test-harness startup guards, not product bounds: 60 s for the ACL script's PowerShell and for
  the preflight's quarto, rg and perl probes (`optional_startup_s`).
- The by-file, optional and callr-native runners write testthat's progress to `stdout()`: a
  reporter on `stderr()` writes into a test's `sink(type = "message")`.

Commits: `3e63a8a`, `b00d681`, `f1b62da`, `17c0fb9`, `1637f4b`, `37edb30`, `6537173`, `c8600c8`,
`dd4820c`, `8fde8fa`.

### Task 2: Shell routes, scripts and knit engines on Windows (CI-30, CI-31, CI-49, CI-50, CI-65, CI-66, D-229, D-235)

Decisions:
- `bridge_program()` matches WindowsApps aliases on `normalizePath()`, since `Sys.which()` returns
  8.3 names on Windows.
- The resolution, direct-line, pipeline, timeout, `peter$bg()` tree, `.sh`, `#!` and shell-engine
  tests run on Windows; Windows-only tests cover the PowerShell and cmd routes, Git Bash without
  bash on PATH and the cmd and powershell knit engines.
- The cmd route runs the line in a cmd started after `chcp 65001`, passed through `GPTR_SHELL_CMD`
  (D-229): chcp and an echo on one `/c` line kept the OEM code page (run 39193453652).
- The PowerShell route (D-235): Rtools' extensionless MSYS2 `usr/bin/cmd`, first on PATH under
  R CMD, shadowed `cmd.exe` in PowerShell's PATH search and was opened with ShellExecute without a
  wait, so `cmd /c exit 4` gave status 0 (diagnostic job 118000300246). On Windows a lookup hook
  resolves a bare name to the first program of that name with an extension, or to none ("not
  recognized"), as cmd does; the status is 0 when the last command succeeded, else the last native
  exit code, else 1. The test puts an extensionless `cmd` first on PATH and asserts the statuses
  under pwsh and Windows PowerShell 5.1.
- A background job's read takes the status before the bytes, so a read that reports the job ended
  holds all of its output; the job tests release their child through a file, not a sleep.
- The timeout test and the shell-engine test allow 30 s instead of 10 s on every OS, for Git Bash
  start-up on hosted Windows; their jobs run 57 s and 999 s, so the timeout kill is still proven.

Commits: `f370026`, `ec6cf5b`, `838f322`, `6ede769`, `7c36123`, `0fbca74`, `adfef78`, `1f5359e`,
`b4df19c`, `bd8e30b`, `c65f11e`, `3596af1`, `3942e0b`.

### Task 3: The orphan sweep, a bare `R` server and process trees (CI-32, CI-47, CI-56, CI-69, D-233)

Decisions:
- The parent-death sweep test runs on Windows through a `cleanup = FALSE` grandchild: processx's
  kill-on-close job ends the child with its parent, and `Rscript.exe` runs R in its own process
  (D-019 item 2 corrected). It reads only the `<marker>.json` records, never the stdin writer's
  `.stdin` files.
- A live MCP server started with the command `R` proves `mcp_stdio_command()`'s R mapping.
- `kill_all()` records the descendants of a live process by parent link before the interrupt and
  kills them after `$kill()` (D-233). `proc_children()` lists them from ps's own handle of the pid:
  on Linux processx and ps estimate the boot time differently, and `ps_children()` of processx's
  handle dropped a shell's background jobs forked in its first clock tick.

Commits: `efe55df`, `e1ebdb6`, `812940c`, `9170baf`, `85e5883` (superseded), `d480ee5`.

### Task 4: Paths, links and the file tools on Windows (CI-33..CI-36, CI-51, D-231)

Decisions:
- Run on Windows: drive-path rewrites, a junction loop through the walker, find and grep,
  case-only patch moves, read-only files, the relative Rscript file fallback, two operations
  through a file link, path classes through junctions and file links; `local_symlink()` is the one
  link helper.
- A patch move never renames a file link over its target (`path_is_link()`, `file.remove()`) and
  keeps the file when the old name is an 8.3 or trailing-dot alias (`path_listed()`).
- `resolve_link_target()` refuses a dangling Windows link before its existence shortcut: Windows
  `stat()` succeeds on such a link, so `file.exists()` is TRUE (745397d assumed FALSE).

Commits: `d43511f`, `607777a`, `439d00c`, `e761a8a`, `ea3abc9`, `6541910` (superseded),
`e23f44d`, `d415b90`, `745397d`, `d29750a`, `9be7d4b`, `c036bb2`, `73b60c2`.

### Task 5: The wire log and scrub through Windows links (CI-37, CI-38, CI-48, CI-52, CI-68, D-231)

Decisions:
- `path_dangling()` means no followed metadata plus a readlink target on POSIX, as on `main`, and a
  listed entry (`path_listed()`) on Windows, where readlink has none; `resolve_link_target()` asks
  it on every OS, and `local_dangling_link()` is the one fixture.
- `wire_log_path()` refuses a dangling link (`path_dangling()`) at or above the log path.
- `scrub_walk()` counts a file only with followed metadata, without Windows warnings.
- `scrub_lock()` refuses a dangling root or lock root (`path_dangling()`) and a link at either
  (`path_is_link()`) before it takes any lock.

Commits: `267f441`, `13de743`, `2c9b6a4`, `fda61bf`, `089bc9a`, `dba9c78`.

### Task 6: A dangling link reads as absent on Windows (CI-60, CI-61, CI-67, D-231)

Decisions:
- `path_info()` is `file.info(extra_cols = FALSE)` with Windows' warning muffled and a row with NA
  times made all NA, as POSIX gives it.
- Readers, the read, edit and grep tools, the walker and `ls`, the files checkpointer, `@file`
  mentions, the document file argument and cache, and spec and gateway image checks read through
  it; gptr's own stores keep base reads and the trust gate keeps `file.exists()`.
- The `path_info()` test's Windows `file.info()` mock adds its octmode column after `data.frame()`
  (R 4.2) and leaves atime out of the regular-file comparison.

Commits: `4ac06da`, `3383843`, `95199d2`.

### Task 7: Crash recovery on Windows (CI-39)

Decisions:
- The SIGKILL crash-resume tests (IC-59), the SIGTERM sidecar recovery (IC-51) and the dangling
  sidecar links (real junctions) run on Windows; processx's `kill()` and `signal(SIGTERM)` are
  `TerminateProcess()` plus a wait for the exit there.

Commits: `21f01b7`, `f2cf9a3`, `1b87c03`.

### Task 8: Artifacts and Chrome on Windows (CI-40, CI-45, CI-55, CI-59, CI-63, CI-64, D-230, D-233)

Decisions:
- The tokenless fallback and the socket path check run on Windows; a session-check skip names the
  Chrome binary and quotes the stderr log its own launch wrote. The `USERPROFILE` swap was
  reverted as unverified.
- The suite home is a Windows profile (`APPDATA` and `LOCALAPPDATA` under it), so system Google
  Chrome can tell its `--user-data-dir` from the default one and serves DevTools; a test asks
  Windows PowerShell for the browser child's Local AppData.
- A child that exits by itself must leave the process table with its marker family: the test
  helper `family_left()`, and at the launch `proc_family_wait()` for up to `artifact_stop_grace`
  before the unchanged `kill_all()`.
- The owned Chrome binds `--remote-debugging-port=0` and gptr records the port Chrome announces
  (D-230); the app child's fall-through past a port that does not bind is tested.
- The owned Chrome's close records the browser's descendants by parent link and waits for them
  before removing the profile: Chrome's helpers carry no readable marker (D-233).

Commits: `6644347`, `71baed1`, `610ecf8`, `0cbd095`, `630968f`, `2a5e415`, `f35bb9a`, `c751670`,
`96aab0e`, `f40cadb`, `6bae056`, `a7b1793`.

### Task 9: Privacy, the child environment and CLI stdin on Windows (CI-41, D-234)

Decisions:
- `auth.json` lives under `APPDATA/R/config/R/gptr`, so its privacy is the profile's ACL;
  `?gptr_login` says so (Task 12).
- An `mcp` child gets exactly the documented base variables, plus the `LOGONSERVER` and
  `USERDOMAIN` that processx copies into every Windows child (D-234).
- 200 KB CLI stdin payloads (the codex prompt, a claude first user line) go through the owned
  Windows stdin writer in 64 KiB chunks (D-019 item 5 status).

Commits: `0711327`, `6e225bb`, `275cd6d`.

### Task 10: Checkpoints under per-turn scans (CI-43, CI-54, D-228, D-232)

Decisions:
- In per-turn scan mode an explicit row of a walked path is relative, as the walk records it
  (D-228); the #37 test runs in walk mode and a new test in per-turn mode.
- gptr's own document writes run through the service `checkpoint.own_write`, so no turn's undo
  reverts them (D-232).

Commits: `e941222`, `05537a8`, `136beda`.

### Task 11: Test harness bounds on loaded runners (CI-44, CI-62, CI-70..CI-73)

Decisions:
- `bp_run()` charges the observer's supervisor only for its growth in the case; the 1 GiB cap is
  unchanged and CI-23's unit-RSS mock goes.
- The mock server reads requests only when no connection waits to be accepted; INFRA-01's 2.475 s
  bound is unchanged and the failure message prints each head's delay after its read.
- `bp_observe()` retries the five transient observer reasons every 100 ms until the 1 s snapshot
  deadline has passed since the first failure, not once; the observer, caps and deadlines are
  unchanged.
- The observer's construction raises `observer-initial-entry-limit` and `observer-initial-deadline`
  apart; `bp_run()` constructs through `bp_observe()`, which retries the initial deadline as it
  retries the snapshot deadline, and the entry limit stays fatal.
- The observer charges a non-reparse regular file whose lstat gives `st_ino` 0 as an ordinary file
  only when `NtQueryAttributesFile` on the same literal path returns exactly
  `STATUS_DELETE_PENDING`; every other `st_ino`-0 entry stays `observer-metadata-invalid`. A
  Windows-only case in `test-bp-disk-observer.R` makes a real delete-pending file and is that
  file's one platform guard in the Optional-integrations registry.
- Two tests that abort a hanging fake request pump until the run streams (at most 30 s), not for a
  fixed 0.2 s, so the provider has read the request before the abort.

Commits: `f663aa1`, `92a2944`, `404b90a`, `a41cfb8`, `6ad7a95`, `1b472c2`, `406befb`.

### Task 12: Documentation

Decisions:
- This plan, its index row and its row in 05's dependency table (with P26's); fixes
  CI-25..CI-73; D-228..D-235, the D-231 and D-233 amendments, the D-019 item 2 correction and the
  Windows stdin status of D-019 item 5, D-101, D-104 and D-106; the P27 sections of
  `dev/PROGRESS.md` and `dev/HANDOFF.md`.
- Plans and 05 cite the test titles P27 renamed (P04, P10, P18, P20, P22, P23); 04 section 3.2
  lists `GPTR_SHELL_CMD`; 04 section 7.4 and 03 section 6.7 give the cmd and PowerShell routes and
  the descendants `kill_all()` records; IC-61 names the DevTools port; `?gptr_login` gives the
  Windows privacy of `auth.json`.

## Renamed and unskipped tests

`skip_on_os("windows")` sites: 77 at `f4202bb`, 60 at `92a2944`, `404b90a` and `406befb`. Renamed:

| File | Old title | New title | Commit |
|---|---|---|---|
| `test-artifact-app.R` | the access token is 128 random bits from openssl or /dev/urandom | the access token is 128 random bits from openssl, else /dev/urandom or none (Windows) | `6644347` |
| `test-bridge-sh.R` | shell scripts and #! lines run on Unix | shell scripts run with bash or sh and #! lines with the program they name | `838f322` |
| `test-mcp-client.R` | a server configured with a bare Rscript command runs with this R's Rscript | a server configured with a bare Rscript or R command runs with this R | `efe55df` |
| `test-proc-spawn.R` | a parent killed with SIGTERM leaves children that the next load's sweep removes | a killed parent leaves a grandchild that the next load's sweep removes | `e1ebdb6` |
| `test-tool-walk.R` | a symlinked directory is listed but not followed | a directory link back to the root (a Windows junction) is listed but not followed | `607777a` |
| `test-doc-io.R` | a differently cased dangling modern entry masks legacy on a POSIX filesystem | a differently cased dangling modern entry masks legacy where names ignore case | `1b87c03` |
| `test-cli-codex.R` | a codex turn: exact argv, a 50 KB prompt on stdin intact, no token in env | a codex turn: exact argv, a 200 KB prompt on stdin intact, no token in env | `275cd6d` |
| `test-proc-backpressure-sampling.R` | backpressure observation retries a fixed transient observer reason once | backpressure observation retries fixed transient observer reasons for one deadline | `404b90a` |

## Out of scope

- The interactive Windows console (pause menu, Ctrl+C, readline in Rterm, Rgui and RStudio):
  manual checks (`00-index.md` section 7).
- The frozen, hash-pinned windows-token packets (`dev/ci/windows-token/`): their `stderr()`
  reporters and 5 s utility deadline stay.
- `callr-native-environment`: callr is retired; only its runner's reporter moved to `stdout()`
  (CI-58), its registry is unchanged and the workflow is not part of acceptance.
- Real `claude` and `codex` binaries on Windows (live tests only) and claude control responses
  larger than one writer chunk (D-104).
- The 60 sites that stay `skip_on_os("windows")` at `92a2944` (59 in the "On Windows" skips of
  R-CMD-check job 118001849245; `test-subagent-worker.R:649` runs in a separate native file): POSIX
  modes, umask, execute bits and owner identity (13) and legacy RDS sidecars, which Windows never
  reads (1); unreadable mode-000 files (4); FIFOs (6); POSIX symbolic links, relative or missing
  targets among them (R's Win32 `file.symlink()` stats the target) (13); names with a newline, `*`
  or `?` (3); same-size rewrites under a restored mtime (POSIX ctime; Windows compares content)
  (2); a C locale (2); POSIX `SingletonSocket` files (3); terminal completion and typing (10) and
  real SIGINTs (INFRA-03) (1); the cmd engine's refusal outside Windows (1); the POSIX IC-60
  worker case, whose Windows counterpart is its own test (1).

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| A1 | R-CMD-check `windows-latest (release)` (a Windows-check.yaml gate since D-239), NOT_CRAN, green twice on one commit | `9170baf` run 39217189384 job 117943690103: `FAIL 2 \| WARN 8`, `test-bridge-sh.R:146` and `:155` (PowerShell route, fixed by CI-66); the WARN are the dangling sidecar warnings fixed by CI-60. `92a2944` run 39235008757 job 118001849245: `FAIL 2 \| WARN 0`, the same two. `85e5883` run 39250578309 job 118053097431 and `74de8c6` run 39255504135 job 118076803835 (the same `R/` and `tests/`): `Status: OK`, `FAIL 0 \| WARN 0 \| SKIP 94 \| PASS 33631`, both artifact session checks ran (CI-63). `d9a7840` (`404b90a` merged with `main`) run 39274424747 jobs 118134892121 and 118200832727 (attempts 1 and 2): green | pending on the final head (green twice on `d9a7840`) |
| A2 | R-CMD-check `windows-latest (oldrel-4)` (a Windows-check.yaml gate since D-239), NOT_CRAN, green twice on one commit | `9170baf` job 117943690159: `FAIL 2 \| WARN 4`, the same two expectations. `92a2944` job 118001849423: `FAIL 3 \| WARN 0`, the same two and `test-utils-paths.R:324` (R 4.2.3 `octmode`, fixed by CI-67). `85e5883` job 118053097175: testthat `FAIL 0 \| WARN 0 \| SKIP 94 \| PASS 33631`, but native-07 failed on `observer-metadata-invalid` twice in a row (fixed by CI-70). `74de8c6` job 118076804097: `Status: 1 NOTE` (size), `FAIL 0`. `d9a7840` run 39274424747: attempt 1 job 118134892183 failed native-08 while constructing the observer (`observer-initial-entry-or-time-limit`, fixed by CI-72); attempt 2 job 118200832757 failed native-01 on `observer-metadata-invalid` after 8 retries (CI-73) | pending on the final head (green once, on `74de8c6`) |
| A3 | windows-by-file ordinary full suite (`optional = false`), green twice on one commit | `2c9b6a4` run 39202175985 job 117897290402: `test-bridge-lang.R`, `test-bridge-sh.R`, `test-console-notice.R`, `test-tool-write.R` failed (CI-49, CI-51, CI-53 came after); the filtered `9170baf` run 39217182105 job 117943670939: only `test-bridge-sh.R` failed (`:146`, `:155`, `:445`, `:449`; CI-66, CI-65). `85e5883` run 39250571244 and `74de8c6` runs 39255516069 and 39255537264: all 203 files pass; both `74de8c6` runs skipped the first session check (`test-artifact-app.R:511`) as a browser startup failure, whose reason the runner does not print. `d9a7840` runs 39274424599 and 39274441623: green | pending on the final head (green twice on `d9a7840`) |
| A4 | rscript-native on Windows, macOS and Ubuntu, green twice on one commit | `2c9b6a4` run 39202178250: macOS and Ubuntu green; Windows job 117897297705 failed on an unexpected session-check skip (Chrome for Testing bind `0x271D`, fixed by CI-59); `92a2944` run 39234997432, `85e5883` run 39250575003, `74de8c6` runs 39255497307 and 39255504649 and `d9a7840` runs 39274414158 and 39274432989: all three green | pending on the final head (green twice on `d9a7840`) |
| A5 | Exact-tarball (Windows release and R-devel in CRAN mode, macOS, Ubuntu), green twice on one commit | `2c9b6a4` run 39202180585, `85e5883` run 39250578324, `74de8c6` runs 39255512201 and 39255541223 and `d9a7840` runs 39274429016 and 39274447505: all five legs green | pending on the final head (green twice on `d9a7840`) |
| A6 | windows-by-file optional Windows packet, green twice on one commit | `92a2944` run 39235001873 job 118001831486: 12 optional files PASS; `85e5883` run 39250581987, `74de8c6` runs 39255501073 and 39255508574 and `d9a7840` runs 39274419504 and 39274437600 green | pending on the final head (green twice on `d9a7840`) |
| A7 | the other R-CMD-check jobs | `9170baf`: 11 green; `ubuntu-latest (oldrel-4)` job 117943690034 `FAIL 1`, `test-artifact-app.R:488` "The private headless browser directory did not finish cleanup: unlink returned 1" (fixed by CI-64). `92a2944` run 39235008757: `ubuntu-latest (oldrel-4)` job 118001849303 `FAIL 1`, `test-utils-paths.R:324` (R 4.2.3, CI-67); `ubuntu-latest (release, LC_ALL=C)` job 118001849130 `FAIL 1`, `test-bridge-sh.R:512` (`length(tree)` 1, expected >= 2); the other 10 green. `85e5883`: all 12 green. `74de8c6`: `ubuntu-latest (release, no Suggests)` job 118076803865 `FAIL 1`, `test-bridge-sh.R:569` (0 of 2 sleeps for 10 s, fixed by CI-69); the other 11 green. `d9a7840` run 39274424747: `ubuntu-latest (oldrel-4)` hit the 45-minute job timeout on both attempts (jobs 118134892383, 118200833216; fixed by CI-71); the other 11 green on both attempts, `ubuntu-latest (release, no Suggests)` among them (CI-69) | pending on the final head |
| A8 | macOS: full offline suite, lint, `python3 -I dev/ci/check-plans.py` | `3383843`: `[ FAIL 0 \| WARN 0 \| SKIP 62 \| PASS 34753 ]`, lint clean; `85e5883`: `[ FAIL 0 \| WARN 0 \| SKIP 63 \| PASS 34801 ]` and `R CMD check --as-cran` 0 errors, 0 warnings, 0 notes; `d9a7840`: `[ FAIL 0 \| WARN 0 \| SKIP 63 \| PASS 34827 ]` and `R CMD check --as-cran` 0 errors, 0 warnings, 0 notes; `406befb`: only the lanes' test files (CI-71..CI-73). Plan checks with this plan: `27 plans, 1446 blocks, 4391 definitions, 28351 calls, 957 findings (info 823, warn 134)`, 0 error; `770 R blocks; 0 with parse/style problems`; `no lints`. P27's 13 warnings name functions that exist in `R/` or `tests/testthat/` but in no plan block (`path_info()`, `path_dangling()`, `path_listed()`, `path_is_link()`, `scrub_walk()`, `scrub_lock()`, `proc_children()`, `proc_family_wait()`, `local_symlink()`, `local_dangling_link()`, `family_left()`, `bp_run()`, `bp_observe()`), as P26's do; its `plan_not_in_decomposition` warning, and P26's, are fixed by their rows in 05 | pass on `d9a7840`; pending on the final head |
| A9 | Plan-gates (Ubuntu) and Optional-integrations (Windows and Ubuntu), green on one commit, the Windows leg twice | neither has run on this branch (both are dispatched with a `source_sha`); the plan checks pass on macOS (A8), and the optional registry passed in the windows-by-file optional packet (A6) | pending |
