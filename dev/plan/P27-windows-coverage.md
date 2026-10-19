# P27 Windows coverage (2026-10-19)

**Goal:** Prove every Windows function of gptr on GitHub's hosted Windows CI, repeatably:
`windows-latest` R release, oldrel-4 (R 4.2) and R-devel, in CRAN and NOT_CRAN modes, with every
Windows lane green twice on one commit. Branch `claude/windows-coverage-p27`, draft PR
[#51](https://github.com/Broccolito/gptr/pull/51).

**Evidence:** Windows cannot run on the maintainer's Mac. Each fix reasons from the R, processx, ps
and Chromium sources and the hosted logs, reproduces the failure on macOS where it is portable, or
emulates the Win32 calls with stubs (`is_windows()` TRUE, `Sys.readlink()` empty, UCRT `stat()`
facts), and claims Windows behaviour only from hosted runs. Per-fix evidence:
`dev/progress/fixes.md` Tasks CI-25..CI-62.

**Depends on:** P01-P26. **Milestone:** post-M5 maintenance, before CRAN submission.

## Global Constraints

`dev/plan/00-conventions.md` applies in full. Plan-specific rules:

- Issue [#47](https://github.com/Broccolito/gptr/issues/47): no product bound, deadline or
  strictness check is loosened and no test is skipped to get green. A wrong test is corrected; a
  product defect is fixed in product code with a test that is red before the fix; a cause that is
  not proven is called inferred.
- A Windows branch that cannot run locally is checked against R's Windows sources and, where
  portable, by a macOS emulation; its Windows status stays pending until a hosted run passes it.
- Ids: fixes CI-25..CI-62, deviations D-228..D-234; every rename, unskip and `dev/ci` registry
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

### Task 2: Shell routes, scripts and knit engines on Windows (CI-30, CI-31, CI-49, CI-50, D-229)

Decisions:
- `bridge_program()` matches WindowsApps aliases on `normalizePath()`, since `Sys.which()` returns
  8.3 names on Windows.
- The resolution, direct-line, pipeline, timeout, `peter$bg()` tree, `.sh`, `#!` and shell-engine
  tests run on Windows; Windows-only tests cover the PowerShell and cmd routes, Git Bash without
  bash on PATH and the cmd and powershell knit engines.
- The cmd route runs the line in a cmd started after `chcp 65001`, passed through `GPTR_SHELL_CMD`
  (D-229): chcp and an echo on one `/c` line kept the OEM code page (run 39193453652).
- PowerShell route: `cmd /c exit 4` gives status 0 on hosted Windows. The product is unchanged
  and the test prints `$LASTEXITCODE` and `$?` after each native exit (open).

Commits: `f370026`, `ec6cf5b`, `838f322`, `6ede769`, `7c36123`, `0fbca74`.

### Task 3: The orphan sweep, a bare `R` server and process trees (CI-32, CI-47, CI-56, D-233)

Decisions:
- The parent-death sweep test runs on Windows through a `cleanup = FALSE` grandchild: processx's
  kill-on-close job ends the child with its parent, and `Rscript.exe` runs R in its own process
  (D-019 item 2 corrected). It reads only the `<marker>.json` records, never the stdin writer's
  `.stdin` files.
- A live MCP server started with the command `R` proves `mcp_stdio_command()`'s R mapping.
- `kill_all()` records the descendants of a live process by parent link before the interrupt and
  kills them after `$kill()` (D-233).

Commits: `efe55df`, `e1ebdb6`, `812940c`, `9170baf`.

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

### Task 5: The wire log and scrub through Windows links (CI-37, CI-38, CI-48, CI-52, D-231)

Decisions:
- `wire_log_path()` refuses a listed entry without followed metadata at or above the log path.
- `scrub_walk()` counts a file only with followed metadata, without Windows warnings.
- `scrub_lock()` refuses a dangling root or lock root (`path_dangling()`) and a link at either
  (`path_is_link()`) before it takes any lock.

Commits: `267f441`, `13de743`, `2c9b6a4`, `fda61bf`.

### Task 6: A dangling link reads as absent on Windows (CI-60, CI-61, D-231)

Decisions:
- `path_info()` is `file.info(extra_cols = FALSE)` with Windows' warning muffled and a row with NA
  times made all NA, as POSIX gives it.
- Readers, the read, edit and grep tools, the walker and `ls`, the files checkpointer, `@file`
  mentions, the document file argument and cache, and spec and gateway image checks read through
  it; gptr's own stores keep base reads and the trust gate keeps `file.exists()`.

Commits: `4ac06da`, `3383843`.

### Task 7: Crash recovery on Windows (CI-39)

Decisions:
- The SIGKILL crash-resume tests (IC-59), the SIGTERM sidecar recovery (IC-51) and the dangling
  sidecar links (real junctions) run on Windows; processx's `kill()` and `signal(SIGTERM)` are
  `TerminateProcess()` plus a wait for the exit there.

Commits: `21f01b7`, `f2cf9a3`, `1b87c03`.

### Task 8: Artifacts and Chrome on Windows (CI-40, CI-45, CI-55, CI-59, D-230)

Decisions:
- The tokenless fallback and the socket path check run on Windows; a session-check skip names the
  Chrome binary and quotes the stderr log its own launch wrote. The `USERPROFILE` swap was
  reverted as unverified.
- A child that exits by itself must leave the process table with its marker family: the test
  helper `family_left()`, and at the launch `proc_family_wait()` for up to `artifact_stop_grace`
  before the unchanged `kill_all()`.
- The owned Chrome binds `--remote-debugging-port=0` and gptr records the port Chrome announces
  (D-230); the app child's fall-through past a port that does not bind is tested.

Commits: `6644347`, `71baed1`, `610ecf8`, `0cbd095`, `630968f`, `2a5e415`, `f35bb9a`, `c751670`,
`96aab0e`, `f40cadb`.

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

### Task 11: Test harness bounds on loaded runners (CI-44, CI-62)

Decisions:
- `bp_run()` charges the observer's supervisor only for its growth in the case; the 1 GiB cap is
  unchanged and CI-23's unit-RSS mock goes.
- The mock server reads requests only when no connection waits to be accepted; INFRA-01's 2.475 s
  bound is unchanged and the failure message prints each head's delay after its read.

Commits: `f663aa1`, `92a2944`.

### Task 12: Documentation

Decisions:
- This plan, its index row and its row in 05's dependency table (with P26's); fixes
  CI-25..CI-62; D-228..D-234, the D-019 item 2 correction and the Windows stdin status of D-019
  item 5, D-101, D-104 and D-106; the P27 sections of `dev/PROGRESS.md` and `dev/HANDOFF.md`.
- Plans and 05 cite the test titles P27 renamed (P04, P10, P18, P20, P22, P23); 04 section 3.2
  lists `GPTR_SHELL_CMD`; 04 section 7.4 and 03 section 6.7 give the cmd route and the
  descendants `kill_all()` records; IC-61 names the DevTools port; `?gptr_login` gives the
  Windows privacy of `auth.json`.

## Renamed and unskipped tests

`skip_on_os("windows")` sites: 77 at `f4202bb`, 60 at `92a2944`. Renamed:

| File | Old title | New title | Commit |
|---|---|---|---|
| `test-artifact-app.R` | the access token is 128 random bits from openssl or /dev/urandom | the access token is 128 random bits from openssl, else /dev/urandom or none (Windows) | `6644347` |
| `test-bridge-sh.R` | shell scripts and #! lines run on Unix | shell scripts run with bash or sh and #! lines with the program they name | `838f322` |
| `test-mcp-client.R` | a server configured with a bare Rscript command runs with this R's Rscript | a server configured with a bare Rscript or R command runs with this R | `efe55df` |
| `test-proc-spawn.R` | a parent killed with SIGTERM leaves children that the next load's sweep removes | a killed parent leaves a grandchild that the next load's sweep removes | `e1ebdb6` |
| `test-tool-walk.R` | a symlinked directory is listed but not followed | a directory link back to the root (a Windows junction) is listed but not followed | `607777a` |
| `test-doc-io.R` | a differently cased dangling modern entry masks legacy on a POSIX filesystem | a differently cased dangling modern entry masks legacy where names ignore case | `1b87c03` |
| `test-cli-codex.R` | a codex turn: exact argv, a 50 KB prompt on stdin intact, no token in env | a codex turn: exact argv, a 200 KB prompt on stdin intact, no token in env | `275cd6d` |

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
| A1 | R-CMD-check `windows-latest (release)`, NOT_CRAN, green twice on one commit | `9170baf` run 39217189384 job 117943690103: `FAIL 2 \| WARN 8`, `test-bridge-sh.R:146` and `:155` (PowerShell route; `lec= ok=True` after both cmd exits); the WARN are the dangling sidecar warnings fixed by CI-60. `92a2944` run 39235008757 job 118001849245: `FAIL 2 \| WARN 0`, the same two | pending |
| A2 | R-CMD-check `windows-latest (oldrel-4)`, NOT_CRAN, green twice on one commit | `9170baf` job 117943690159: `FAIL 2 \| WARN 4`, the same two expectations. `92a2944` job 118001849423: `FAIL 3 \| WARN 0`, the same two and `test-utils-paths.R:324` (R 4.2.3 `octmode`, as on ubuntu oldrel-4) | pending |
| A3 | windows-by-file ordinary full suite (`optional = false`), green twice on one commit | `2c9b6a4` run 39202175985 job 117897290402: `test-bridge-lang.R`, `test-bridge-sh.R`, `test-console-notice.R`, `test-tool-write.R` failed (CI-49, CI-51, CI-53 came after); the filtered `9170baf` run 39217182105 job 117943670939: only `test-bridge-sh.R` failed (`:146`, `:155`, `:445`, `:449`) | pending |
| A4 | rscript-native on Windows, macOS and Ubuntu, green twice on one commit | `2c9b6a4` run 39202178250: macOS and Ubuntu green; Windows job 117897297705 failed on an unexpected session-check skip (Chrome for Testing bind `0x271D`, fixed by CI-59); `92a2944` run 39234997432: all three green | pending (green once, on `92a2944`) |
| A5 | Exact-tarball (Windows release and R-devel in CRAN mode, macOS, Ubuntu), green twice on one commit | `2c9b6a4` run 39202180585: all five legs green; not run on `92a2944` | pending (green once, on `2c9b6a4`) |
| A6 | windows-by-file optional Windows packet, green twice on one commit | `92a2944` run 39235001873 job 118001831486: 12 optional files PASS | pending (green once, on `92a2944`) |
| A7 | the other R-CMD-check jobs | `9170baf`: 11 green; `ubuntu-latest (oldrel-4)` job 117943690034 `FAIL 1`, `test-artifact-app.R:488` "The private headless browser directory did not finish cleanup: unlink returned 1". `92a2944` run 39235008757: `ubuntu-latest (oldrel-4)` job 118001849303 `FAIL 1`, `test-utils-paths.R:324` (R 4.2.3: "cannot coerce class '"octmode"' to a data.frame" in the emulated row); `ubuntu-latest (release, LC_ALL=C)` job 118001849130 `FAIL 1`, `test-bridge-sh.R:512` (`length(tree)` 1, expected >= 2); the other 10 green | pending |
| A8 | macOS: full offline suite, lint, `python3 -I dev/ci/check-plans.py` | `3383843`: `[ FAIL 0 \| WARN 0 \| SKIP 62 \| PASS 34753 ]`, lint clean; `92a2944`: `http-reactor` and the 16 other mock-server files `FAIL 0`. Plan checks with this plan: `27 plans, 1446 blocks, 4391 definitions, 28351 calls, 954 findings (info 823, warn 131)`, 0 error; `770 R blocks; 0 with parse/style problems`; `no lints`. P27's 10 warnings name functions that exist in `R/` or `tests/testthat/` but in no plan block (`path_info()`, `path_dangling()`, `path_listed()`, `path_is_link()`, `scrub_walk()`, `scrub_lock()`, `local_symlink()`, `family_left()`, `proc_family_wait()`, `bp_run()`), as P26's do; its `plan_not_in_decomposition` warning, and P26's, are fixed by their rows in 05 | pass |
| A9 | Plan-gates (Ubuntu) and Optional-integrations (Windows and Ubuntu), green on one commit, the Windows leg twice | neither has run on this branch (both are dispatched with a `source_sha`); the plan checks pass on macOS (A8), and the optional registry passed in the windows-by-file optional packet (A6) | pending |
