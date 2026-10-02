# Track 13 — CRAN compliance checklist for an agent harness package (gptr 1.0.0)

Date: 2026-09-29. Research agent, track 13. Requirements referenced as `REQ-nn` are in
`dev/spec/00-vision-brief.md`; decisions as `D-nn` / `S-n` are in `dev/spec/01-decision-register.md`.

Scope: the rules an R package must obey to be accepted and kept on CRAN, applied to
gptr specifically. gptr is an agent that writes files, evaluates model-generated R code
in the live session, spawns processes, talks to paid web APIs and keeps a `.gptr/`
workspace. The deliverable is the numbered checklist in section 4. Every rule has a
source URL and a concrete gptr pattern with R code. A throwaway skeleton `gptr 1.0.0`
built with the proposed DESCRIPTION and these patterns passes
`R CMD check --as-cran` with `Status: OK` (section 5).

Prior work: an earlier researcher on this track stopped after downloading sources into
`scratchpad/work/13/web/` (CRAN policy, WRE, R Internals, R Packages chapters, the CRAN
Cookbook, R-package-devel archives 2019q1–2026q3) and `scratchpad/work/13/cranpkgs/`
(tarballs of aisdk, btw, chattr, chores, ellmer, gander, gptstudio, httptest2, mcptools,
shinychat, tidyprompt, vitals, webfakes, askgpt). No draft report existed. I treated all
of it as unverified and re-checked every claim I use: I re-fetched the policy revision
from CRAN, read the R sources in the installed R, and ran the experiments myself.

Evidence labels: **VERIFIED** means I saw it myself, in a file with line numbers, a URL
I fetched, or a command I ran. **LIKELY** means it is well supported but not proven.
**UNCERTAIN** means it is a judgement call or unconfirmed. Web text is paraphrased, not
quoted (copyright). Local paths are abbreviated as follows:
`$S = /private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad`,
`$W = $S/work/13`.

---

## 1. Executive summary

1. **Nothing in CRAN policy forbids an agent that evaluates model-generated code or writes files.** The policy targets things a package does *without being asked*: writing outside `tempdir()`, modifying the global environment, sending session data to third parties, using more than 2 cores, and leaving processes or files behind. Every action gptr takes on the user's behalf must be user-initiated, go through a documented permission mode, and never happen in examples, tests or vignettes. (LIKELY. Policy rev 6875 was VERIFIED; the judgement about acceptance is mine.)
2. **Precedents exist on CRAN today, all with OK check status** (VERIFIED from the check pages, 2026-09-30 CEST; re-checked by the verifier: 13/13 flavors OK for each package listed):
   - `btw` 1.5.0 has an opt-in tool, off by default, that runs LLM-written R code in the global environment and documents a "Security Considerations" section. Its file-write tool refuses paths outside the working directory, and its examples run in `withr::with_tempdir()`.
   - `aisdk` 1.4.12 evaluates model code with `eval(parse(text=))` in `globalenv()` and writes `.aisdk/sessions` in the start-up directory of its interactive console.
   - `ellmer` 0.5.0 provides tool-approval hooks (`on_tool_request()`, `tool_reject()`).
   - `mcptools` 1.0.3 lets external agents run tools inside a live R session.
   - `chattr`, `gander` and `chores` insert code into the editor, and the user runs it.
3. **gptr 1.0.0 is an update, not a new submission.** gptr 0.7.0 has been on CRAN since 2025-04-05 with the same maintainer, and it has **no reverse dependencies of any type** (VERIFIED with `tools::package_dependencies(reverse = TRUE, which = "all")`). CRAN policy does **not** require a deprecation cycle. It only requires that reverse-dependency maintainers be notified at least 2 weeks ahead, and there are none. Use `1.0.0`, a "Breaking changes" section in NEWS.md, and a cran-comments.md that states the rewrite and the absence of revdeps.
4. **Minimum R version: `Depends: R (>= 4.2)`**, not 4.1 as D-23 proposes.
   - The native pipe and `\(x)` need 4.1; raw strings and `tools::R_user_dir()` need 4.0; the pipe placeholder `_` needs 4.2.
   - Decisively, **R 4.2.0 made UTF-8 the native encoding on recent Windows** (R NEWS: at least Windows 10 version 1903 / Windows Server 2022; older Windows keeps a code page). An agent that shuttles Unicode LLM text between the console, files and APIs needs this.
   - 4.2.3 is "oldrel-4" today (VERIFIED from the api.r-hub.io rversions API), which matches the tidyverse's five-minor-version support window. `btw` already requires R >= 4.2.0.
5. **Imports budget.** `R CMD check --as-cran` gives a NOTE when more than **20 non-base** packages are in Imports, and another when more than 5 packages are in Depends other than `R` and the default-attached packages (`base`, `datasets`, `grDevices`, `graphics`, `methods`, `utils`, `stats`; so e.g. `tools` or `parallel` in Depends *would* count) (VERIFIED in the source of `tools:::.check_package_depends`, and the NOTE text was reproduced with 21 Imports).
   - Recommended Imports: `cli, curl, httr2, jsonlite, openssl, processx, rlang, yaml` (8), plus the base packages `grDevices, stats, tools, utils`.
   - The whole hard-dependency closure is 19 CRAN packages, almost all already pulled in by httr2.
   - `rlang` must be imported explicitly if gptr uses `cli::cli_abort()`/`cli_inform()`: those call `rlang::abort()`/`inform()`, and rlang is only a *Suggests* of cli (VERIFIED).
6. **The `.gptr/` workspace is compliant only when created explicitly.**
   - `gptr_init(path)` takes the path as an argument with no default. When `path` is missing, an interactive session is asked yes/no and a non-interactive session gets an error.
   - An existing `.gptr/` directory is the persisted record of that consent. Without one, sessions go to `tempdir()`.
   - Global config, cache and data go to `tools::R_user_dir("gptr", which)`, kept small and pruned.
   - All of these patterns pass `--as-cran` in the skeleton (VERIFIED).
7. **Tests must redirect `R_user_dir()`.** CRAN's "donttest" additional-issues run reported *"checking for new files in some other directories ... NOTE"* for a package whose tests/examples wrote to `~/.cache` (rsurvstat, July 2026), even though writing there is legal in normal use. (When CRAN started using `_R_CHECK_THINGS_IN_OTHER_DIRS_` in its extra runs is not established; do not assume "since 2026".)
   - Evidence: the rsurvstat thread of July 2026, and my own probe run with an isolated HOME, which produced exactly this NOTE (VERIFIED; re-run by the verifier).
   - Fix: set `R_USER_CONFIG_DIR`, `R_USER_DATA_DIR` and `R_USER_CACHE_DIR` to a temp directory in `tests/testthat/setup.R`.
8. **processx `supervise = TRUE` opens two R fifo connections that stay open.** In examples this makes `R CMD check --as-cran` fail with the fatal *"connections left open"* ERROR (VERIFIED: my first check run failed exactly this way). Examples must start workers unsupervised, or not start them at all. Tests are not subject to this check.
9. **Never pass untrusted text as a cli/glue format string.** API error bodies or model output that contain `{...}` are *evaluated* as R code by cli. In the skeleton this produced a crash ("Could not evaluate cli `{}` expression"), and it is also a code-injection vector. Always interpolate a variable instead: `"x" = "{detail}"` (VERIFIED by a failing and then fixed test). The skeleton's own interactive REPL still had this bug (`cli::cli_text(reply)`): the verifier showed that an injected `{...}` in a model reply runs. Section 5.2 now uses `cli::cli_verbatim(reply)`. No check catches this, so add a unit test that feeds a reply containing braces to every printer.
10. **Testing without network or keys** is a solved problem, and all of these ran under `--as-cran` (VERIFIED):
    - a scripted **fake provider**;
    - `httr2::local_mocked_responses()` for request building, error classes and key redaction;
    - recorded **fixtures** (JSON and SSE) tested with pure parsers;
    - `webfakes::local_app_process()` for real loopback streaming on a random port, auto-stopped;
    - testthat 3e snapshots, which are skipped on CRAN by default;
    - live tests gated by `skip_on_cran()`, `skip_if_offline()`, an explicit `GPTR_LIVE_TESTS=true` and a key-presence check.

    38 tests pass and 2 are skipped, in 2.3 s.
11. **Examples that need keys** use `@examplesIf interactive() && nzchar(Sys.getenv("KEY"))` (roxygen emits `\dontshow{if (...) withAutoprint(\{...\})}`), and never `\dontrun{}` unless the code truly cannot run. The **vignettes are precomputed** from `vignettes/*.Rmd.orig`, knitted locally and shipped as static Markdown (rOpenSci pattern). VERIFIED in the skeleton.
12. **Two cores maximum.**
    - gptr caps worker processes at `getOption("gptr.max_workers", 2)`, and at 2 whenever `_R_CHECK_PACKAGE_NAME_` is set; R CMD check sets this variable (VERIFIED in the R source).
    - Tests also set `OMP_THREAD_LIMIT=2`.
    - testthat's parallel mode defaults to 2 CPUs, but `getOption("Ncpus")` and then `TESTTHAT_CPUS` override that default (VERIFIED in the testthat 3.3.2 source), so leave `Config/testthat/parallel` off.
    - Two callr children are acceptable if the parent R process stays idle (Henrik Bengtsson on R-package-devel).
13. **External CLIs** (`claude`, `codex`, `quarto`, `jupyter`) must be declared in `SystemRequirements` as optional, discovered with `Sys.which()`, and gptr must pass all checks without them. Policy also says a FOSS-licensed package must not *require* software that restricts users or usage, so the proprietary CLIs can only ever be optional (VERIFIED from the policy text).
14. **R itself must be launched as `file.path(R.home("bin"), "Rscript")`, never as a bare `Rscript`.** `--as-cran` sets `_R_CHECK_R_ON_PATH_` to catch this (VERIFIED in R Internals).
15. **Proposed DESCRIPTION.** Title: *Language Model Agents Inside the Live 'R' Session* (49 characters, identical under `tools::toTitleCase`). The Description is a single paragraph of 161 words, with every software/API name in single quotes, the one URL in angle brackets, and no "This package". With these, `--as-cran` reports only the standard "Maintainer" note. An emulation of CRAN's aspell filter flags no words (VERIFIED).
    - My first title used the word "That", and CRAN's title-case check produced a NOTE for it. Pass any title through `tools::toTitleCase()` before submitting.
16. **Windows.**
    - CRAN's Windows checks take roughly 2x as long as Linux: gptr 0.7.0 totals 53 s on r-devel-windows against 23.9 s on debian-gcc.
    - In text mode, Windows translates LF to CRLF, so the edit tool must read and write in binary mode to preserve line endings.
    - `file.rename()` cannot cross volumes, so atomic writes need a temp file in the *same* directory.
    - Reserved file names (`con`, `nul`, `com1`, ...), case-insensitive collisions, the 100-byte tarball path limit and 8.3 short temp paths must all be handled.
    - Windows has no `fork`: workers must be processx/callr processes.
17. **CI.**
    - r-lib/actions `check-standard`: macOS, Windows and Ubuntu on release, Ubuntu on devel and oldrel-1.
    - Add **oldrel-4** to prove the R 4.2 floor, and `check-no-suggests`.
    - Before each submission: `devtools::check_win_devel()` (the same machine as CRAN's r-devel-windows), rhub v2 (`rhub_check(platforms = c("windows", "macos-arm64", "nosuggests", "donttest", ...))`), and the macOS builder if an M1 issue ever appears.
18. **Housekeeping for the real repository** (do not act now; recorded for the implementer):
    - Add `^\.gptr$`, `^cran-comments\.md$`, `^CRAN-SUBMISSION$`, `^\.github$` and `^vignettes/.*\.Rmd\.orig$` to `.Rbuildignore`. A `.gptr/` directory otherwise ends up in the tarball and triggers the hidden-directory NOTE (VERIFIED). `.Rprofile` is excluded by `R CMD build` automatically (VERIFIED).
    - Update the LICENSE year to 2026.
    - Keep the maintainer email that CRAN already has, `wanjun.gu@ucsf.edu`, or follow the email-change procedure.
    - Credit Mario Zechner (Pi, MIT) as `ctb`/`cph` if any Pi text or code is ported.

---

## 2. Findings

### 2.1 Sources read, and their currency

| Source | Version seen | How |
|---|---|---|
| CRAN Repository Policy | `$Revision: 6875 $` | Downloaded file `$W/web/policies.txt`, then re-fetched live on 2026-09-29: still rev 6875. It contains no mention of AI/LLM-generated code (VERIFIED) |
| CRAN submission checklist | current | `$W/web/checklist.txt` |
| Writing R Extensions | R-devel 4.7.0 (2026-09-28) and release 4.6.1 (2026-06-24) | `$W/web/rexts_devel.txt`, `$W/web/rexts.txt` |
| R Internals, "Tools" chapter (the `_R_CHECK_*` variables) | 4.6.1 | `$W/web/rints.txt` lines 2040–2470 |
| R Packages (2e), chapters on R CMD check, DESCRIPTION, dependencies, testing (3 chapters), vignettes, lifecycle, release | web | `$W/web/rpkgs_*.txt` |
| CRAN Cookbook (code, DESCRIPTION, documentation and general chapters) | web | `$W/web/cookbook_*.txt` |
| DavisVaughan/extrachecks | web | `$W/web/extrachecks.txt` |
| R-package-devel archive | 2019q1–2026q3 (through 2026-09-28) | `$W/web/rpd/*.txt`, searched with `$W/tools/rpd.py` and `thread.py` |
| CRAN package pages and check pages (gptr, aisdk, btw, ellmer, mcptools, chattr) | 2026-09-30 01:55 CEST | `$W/web/checks_*.txt`, `gptr_*.txt` |
| Precedent package sources | versions listed in 2.3 | `$W/cranpkgs/<pkg>/` |
| Current R versions | release 4.6.1 (2026-06-24); oldrel/4 4.2.3 | executed: `curl https://api.r-hub.io/rversions/resolve/oldrel/4` returned `{"version":"4.2.3",...}` |
| Local R used for experiments | R 4.4.3, aarch64-apple-darwin20, macOS 26.6.2 | the check logs |

Limitation: my experiments ran on R 4.4.3 (macOS), not on R-devel 4.7.0 or Windows. CRAN
requires R-devel for submission checks, so win-builder and rhub runs remain mandatory
(checklist C-51).

### 2.2 What the policy actually constrains (paraphrased from rev 6875)

The policy's "Source packages" section contains all the rules that matter for gptr (VERIFIED, `$W/web/policies.txt` lines 50–142):

- **File system.** A package must not write in the user's home filespace (the clipboard included), nor anywhere else on the file system except the session's temporary directory. There are two exceptions. First, limited exceptions may be allowed in *interactive* sessions when the package obtains the user's confirmation. Second, for R >= 4.0, packages may keep user-specific data, config and cache in `tools::R_user_dir()` directories, provided sizes are kept as small as possible and the contents are actively managed, with outdated material removed. (lines 116–120)
- **Global environment.** Packages should not modify the user's workspace. (line 122)
- **External software.** No external software (PDF viewers, browsers) may be started during examples or tests unless that instance is explicitly closed afterwards. (line 124)
- **Data about the session.** Information about the R session must not be sent to the maintainer or to third-party sites without the user's confirmation. (line 126)
- **Loaded code.** A package must not call `q()`, must not tamper with code already loaded into R (in the standard, recommended or other packages), must use only the public API (no `.Internal`, no `:::` into base), and must not disable the stack check or compiler diagnostics. (lines 112–134)
- **TLS.** Security provisions such as TLS certificate verification must not be circumvented. (line 136)
- **Websites.** Use of websites must be kept to a minimum, and rate-limit errors (429/403) must be avoided. (line 138)
- **Cores and check time.** At most two threads/cores at any time. Checking should use as little CPU as possible. Examples should run for no more than a few seconds each. (lines 99–103)
- **Internet resources.** These must fail gracefully with an informative message, and must not cause a check warning or error. (line 105)
- **Size.** The tarball should be at most 10 MB; data and documentation should be at most 5 MB each. No binary executables in the sources. (lines 59, 89–97)
- **Licensing.** A FOSS-licensed package must not require (in Depends, Imports or LinkingTo, directly or indirectly) a package or external software that restricts users or usage. (line 63)
- **Portability.** The package must run on at least two major platforms. (line 69)
- **Submission.** Run `R CMD check --as-cran` with the current R-devel. Explain any NOTE you cannot eliminate. Updates to previously published packages must increase the version number. Updates should come "no more than every 1–2 months" once the package is established. Wait for the check page to update fully (at least 48 h) before sending corrections. If an API change affects reverse dependencies, contact their maintainers and give at least 2 weeks. Explain any change of maintainer email address. (lines 166–216)

### 2.3 Question 1 — is an agent that writes files and runs LLM code acceptable?

**Answer: yes, LIKELY, under three conditions.** Every write and every evaluation must be initiated by the user (an explicit call or an explicit permission mode). Nothing may happen by default in non-interactive contexts. And examples, tests and vignettes must never touch anything outside `tempdir()`.

The policy does not regulate *what* R code a package evaluates; `source()`, `eval()`, `knitr` and `rmarkdown` all evaluate arbitrary code. The regulated behaviours are unrequested side effects (2.2). The CRAN Cookbook's standard reviewer text on writing files asks for two things: that functions do not write *by default* to the home filespace, including the working directory, and that examples, vignettes and tests write only to `tempdir()`. It explicitly accepts functions that have no default path.
(https://contributor.r-project.org/cran-cookbook/code_issues.html, "Writing Files and Directories to the Home Filespace", VERIFIED in `$W/web/cookbook_code.txt` lines 225–249.)

Precedents: all of these are on CRAN now, all with OK status on every flavor (VERIFIED from `$W/web/checks_*.txt` fetched 2026-09-30).

| Package (version, date) | What it does that gptr also does | How it stays compliant (evidence) |
|---|---|---|
| **btw** 1.5.0 (2026-09-09) | `btw_tool_run_r()` runs LLM-written R code. Its default is `.envir = global_env()` | Off by default. It must be enabled through the option `btw.run_r.enabled`, the env var `BTW_RUN_R_ENABLED`, or `btw_tools("run")`. It has a documented "Security Considerations" section (`$W/cranpkgs/btw/R/tool-run.R` lines 9–28, 123). Examples are in `\dontrun{}` |
| btw | LLM file-write tool | `check_path_within_current_wd(path)` refuses anything outside the working directory (`R/tool-files-write.R` line 27). Examples run inside `withr::with_tempdir()` (line 7) |
| btw | `use_btw_md()` writes `btw.md` into the project, and `.Rbuildignore` too | Only on an explicit call. Examples run in `withr::with_tempdir()` (`R/edit_btw_md.R` line 192). Moving user config under `~/.btw` asks with `utils::menu(c("Yes","No"))` and does nothing in non-interactive sessions (lines 356–366) |
| btw | Installs a skill into `~/.agents/skills` or `~/.claude/skills` | Asks with `utils::menu()` interactively; non-interactively it only copies to the clipboard (`R/cli.R` lines 45–79). Global state in `tools::R_user_dir("btw", ...)` (`R/utils.R` lines 160–167, 337) |
| **aisdk** 1.4.12 (2026-06-02), "Unified Interface for AI Model Providers": console agent, sub-agents, skills, MCP | Evaluates model code: `eval(parse(text = code_str), envir = globalenv())` | `R/computer.R` line 331; `R/console_agent.R` lines 620–621. The console is interactive-only; examples use `if (interactive())` (`R/console.R` line 60) |
| aisdk | Writes session JSONL to `file.path(getwd(), ".aisdk", "sessions")` | `R/session_event_store.R` lines 23–37. Only inside the user-started interactive console; there is no separate consent prompt. **gptr should be stricter than this** (see C-18) |
| **ellmer** 0.5.0 | Tool calling, i.e. the LLM invokes R functions | `Chat$on_tool_request()` plus `tool_reject()` let the user approve or reject each call; the documented example uses `utils::menu("Always","Once","No")` (`R/tools-def.R` lines 376–451). Price cache in `R_user_dir("ellmer","cache")` (`R/prices.R` lines 249–255) |
| **mcptools** 1.0.3 (2026-09-18) | External agents (Claude Code) run R tools inside a live R session | `mcp_session()` is explicit; its socket and auth notes say the design is not a security boundary on Windows (`R/socket-dir.R` line 155). OAuth cache in `R_user_dir` (`R/client.R` line 650) |
| chattr 0.3.1, gander 0.2.0, chores 0.3.1 | Put LLM-generated code into the user's document | They insert text through `rstudioapi` (for example `chattr/R/ide.R` line 49); the user decides whether to run it |
| golem, mirai | Ship agent skills in `inst/` | Michael Chirico on R-package-devel, 2026-07-06 (https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012437.html; thread root 012436 is Roy Mendelssohn's question). VERIFIED through the GitHub API: `cran/mirai` has `inst/skills/mirai`, `cran/golem` has `inst/agent-skills` |

Mailing-list search: I searched every R-package-devel message from 2019q1 to 2026q3 for
LLM, ChatGPT, OpenAI, "large language model", ellmer, AI-generated and copilot. No
thread reports a CRAN rejection *because* a package evaluates LLM code or is an agent.
The hits concern licence formatting (openaistream, 2024-01), bundling agent skills
(2026-07) and unrelated SSL/pretest problems (VERIFIED with `$W/tools/rpd.py`).

UNCERTAIN: a human reviewer could still ask for changes. CRAN reviews new submissions by hand, and updates can be reviewed ad hoc if they fail automated checks (R Packages ch. 22.7–22.8, `$W/web/rpkgs_release.txt` lines 355–365). gptr is an update, so a clean automated check is the strongest protection.

### 2.4 Question 2 — the `.gptr/` workspace and the global config directory

Rules (VERIFIED):
- **No default writes outside `tempdir()`.** Policy line 116. The Cookbook adds that writing functions should have no default path.
- **Interactive exception.** Confirmation from the user makes the "limited exception" apply. R core member Martin Maechler on R-package-devel (2019-10-17): prompt the user explicitly, write to the directory only on "yes", otherwise use `tempdir()` (https://stat.ethz.ch/pipermail/r-package-devel/2019q4/004535.html; thread root 004532).
- **`R_user_dir` is legal for config, data and cache** (R >= 4.0), but must be small and actively managed (policy line 120). Ivan Krylov first suggested `tools::R_user_dir(pkg, "config")` (https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009945.html) and Simon Urbanek (CRAN) quoted exactly this policy clause (https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009947.html; thread root 009944). Ivan Krylov added in a 2024 thread that code outside tests and examples should not touch the file system without the user's permission (https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010846.html; thread root 010844).
- **Checks must not create user files, not even in `R_user_dir`.** Robert Challen's rsurvstat package received an archival-threat email (deadline 2026-08-21; thread posted 2026-07-27) because `~/.cache/rsurvstat/*.xml` files appeared during the donttest run. The NOTE text was *"checking for new files in some other directories"* (https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012484.html). Ivan Krylov's reply: caching in the designated places during normal use is fine, but running R CMD check should not create or modify user files, the cache included (https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012486.html). The mechanism is `_R_CHECK_THINGS_IN_OTHER_DIRS_` (default false; not in the documented `--as-cran` set). It monitors `~` (top level), `/tmp` (excluding `RtmpXXXXXX`), `/dev/shm`, `~/.cache` and `~/.local/share` (both recursively), and their macOS and Windows equivalents, i.e. the directories under which the default `R_user_dir()` locations live. Note that on Linux the default *config* location `~/.config` is not in the list (R Internals, `$W/web/rints.txt` lines 2235–2245; re-checked against the live R 4.6.1 R-ints). I reproduced the NOTE (5.6).
- **Never write into the installed package directory.** It is read-only on CRAN. The geohabnet example failed with "Read-only file system" (https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009944.html).
- **Platform defaults of `tools::R_user_dir("gptr", which)`**, read from the R 4.4.3 source (VERIFIED). The environment variables `R_USER_{DATA,CONFIG,CACHE}_DIR` take precedence, then `XDG_*_HOME`, then:
  - Windows: `%APPDATA%/R/data`, `%APPDATA%/R/config`, `%LOCALAPPDATA%/R/cache`;
  - macOS: `~/Library/Application Support/org.R-project.R`, `~/Library/Preferences/org.R-project.R`, `~/Library/Caches/org.R-project.R`;
  - Linux: `~/.local/share`, `~/.config`, `~/.cache`;

  always followed by `/R/gptr`.

Compliant pattern for gptr (implemented and VERIFIED in the skeleton):

1. `gptr_init(path, overwrite = FALSE)` creates `.gptr/` (with `vignette.Rmd`, `sessions/`, `skills/`) only when called, and `path` has no default. When `path` is missing:
   - in an interactive session, gptr proposes `getwd()` and asks yes/no; "no" writes nothing;
   - in a non-interactive session (Rscript, knitr, tests) it is an error.
2. An existing `.gptr/` is the persisted consent. A non-interactive `gptr("...")` inside a script or Rmd may append session files there, because the user created it. If there is no `.gptr/`, session state lives in memory and in `tempdir()`, and gptr says once, interactively, how to persist it (`gptr_init()`).
3. Global state goes to `gptr_user_dir(which)`, a wrapper over `tools::R_user_dir("gptr", which)` with an `options(gptr.user_dir=)` override:
   - config: providers, defaults, permission mode;
   - data: stored credentials, only when the user calls an explicit `gptr_auth_*()` or `gptr_config_set()`;
   - cache: the model catalog refreshed on request, MCP tool metadata, the answer cache.

   Directories are created lazily, only when something must be stored. Size is capped and pruned by `gptr_cache_prune()`.
4. The script-as-history document (REQ-24/25) is a user file. Writing to it requires the user to designate it, for example `gptr(doc = "analysis.R")` or `gptr_record("analysis.R")`, or to confirm interactively. gptr never writes silently to an arbitrary open file.
5. Model tool writes (write/edit) follow the permission mode:
   - `manual` (default when interactive) asks every time;
   - `edits`/`auto` must be chosen explicitly;
   - the non-interactive default is read-only (`plan`) unless the caller passes `permission = "auto"`.

   Writes are confined to the workspace root unless the user widens it (the btw pattern).
6. When `gptr_init()` runs inside a package source directory (a `DESCRIPTION` exists), it offers to add `^\.gptr$` to `.Rbuildignore`, as btw does for `btw.md`. Otherwise the user's own package gets a hidden-directory NOTE (VERIFIED, 5.6).

### 2.5 Question 3 — DESCRIPTION

Rules (all VERIFIED):
- **Title** (WRE 1.1.1, `$W/web/rexts_devel.txt` line 378; Cookbook "Title Case"; extrachecks):
  - title case as produced by `tools::toTitleCase()`;
  - no markup, no continuation lines, no final period;
  - listings may truncate it at 65 characters;
  - do not repeat the package name;
  - single-quote other packages and software.

  Extrachecks reports "for R" being flagged as redundant, and a request to keep titles under 65 characters.
- **Description** (WRE line 380; checklist; extrachecks):
  - one paragraph of complete sentences;
  - do not start with the package name, "This package" or "Functions for";
  - single-quote package, software and API names, including `'R'` itself;
  - write function names with parentheses and without quotes, e.g. `gptr()`;
  - double quotes only for publication titles;
  - URLs in angle brackets, e.g. `<https://...>`;
  - explain all acronyms;
  - if in doubt, make it longer rather than shorter.
- **Authors@R is required for CRAN submissions.** ORCID or ROR identifiers are strongly encouraged (WRE line 388, identical in 4.6.1 and 4.7.0). Extrachecks adds that CRAN asks sole authors to add the `cph` role.
- **Spell check.** CRAN's incoming spell check runs `aspell` on Title and Description when `_R_CHECK_CRAN_INCOMING_USE_ASPELL_` is true (its default in the R source is `"FALSE"`; that CRAN's incoming machines turn it on is LIKELY, from the widely reported "Possibly misspelled words in DESCRIPTION" pretest NOTE, but the variable is not documented in R Internals). It uses dictionaries en_US, en_GB and "en_stats". It ignores text in single quotes, `fun()`-style function names, and URLs or DOIs inside angle brackets (VERIFIED: `deparse(tools:::.check_package_CRAN_incoming)`, R 4.4.3).
- **License.** `MIT + file LICENSE` is a template licence. The LICENSE file must contain only `YEAR:` and `COPYRIGHT HOLDER:` lines, and a full MIT text is rejected with an "invalid DCF" licence-stub NOTE. Ivan Krylov made this point in the openaistream thread (https://stat.ethz.ch/pipermail/r-package-devel/2024q1/010357.html; the "invalid DCF" NOTE is quoted in the thread root 010356). The Cookbook has a matching "LICENSE files" section. Keep the full text in `LICENSE.md`, listed in `.Rbuildignore`; the current repository already does this.
- **Minimum R version.** Specify `R (>= x.y)` without a patch level: `_R_CHECK_R_DEPENDS_=warn` under `--as-cran` (R Internals line 2173; WRE line 511).
- **SystemRequirements** lists external dependencies (WRE line 396). External commands must be used conditionally on a presence test such as `Sys.which()`, and the package must pass its checks without them (WRE line 2370).

The proposed DESCRIPTION is given verbatim in 3.1. It was validated with `R CMD check --as-cran` (5.4). Notes on the choices:
- Title: *Language Model Agents Inside the Live 'R' Session* (49 characters). The earlier candidate *"... That Work Inside ..."* produced the NOTE "The Title field should be in title case ... 'Language Model Agents that Work ...'" (VERIFIED in `$W/build/check-as-cran.log`). The `'R'` is needed for meaning, so it is not the redundant "for R".
- Description: I removed "(LLM)" because my emulation of the CRAN aspell filter flags it (`$W/tools/spell_desc.R`). I also removed "runnable". The final text flags nothing (VERIFIED). Acronyms kept: 'MCP' (expanded as Model Context Protocol) and "application programming interfaces" (spelled out, so no acronym).
- Maintainer email: keep `wanjun.gu@ucsf.edu`, the address CRAN has for gptr 0.7.0 (VERIFIED on the CRAN page). Changing it requires an explanation and, if possible, a confirmation sent from the old address (policy line 188). The ORCID `0000-0002-7342-7000` comes from the current DESCRIPTION.

### 2.6 Dependencies and the Imports budget

- **The NOTE.** `tools:::.check_package_depends` computes `setdiff(imports, standard_package_names$base)`. If `_R_CHECK_EXCESSIVE_IMPORTS_` is positive (`--as-cran` sets it to `"20"`) and more than 20 packages remain, it reports `many_imports`. It separately flags more than 5 Depends after removing only `R`, `base`, `datasets`, `grDevices`, `graphics`, `methods`, `utils` and `stats` (other base packages such as `tools` or `parallel` *do* count toward the Depends limit). Base packages such as `tools`, `utils`, `stats`, `parallel` and `grDevices` do not count (VERIFIED: deparsed R 4.4.3 source). Reproduced text: *"Imports includes 21 non-default packages. Importing from so many packages makes the package vulnerable to any of them becoming unavailable. Move as many as possible to Suggests and use conditionally."* (`$W/probe/probe-check.log`, VERIFIED).
- **Every Import must be used.** Otherwise: *"Namespaces in Imports field not imported from: ... All declared Imports should be used."* (VERIFIED in the probe).
- **Hard-dependency closure** (executed against the current CRAN database):
  - `httr2 + jsonlite + cli + processx` gives 16 packages: R6, askpass, cli, curl, glue, httr2, jsonlite, lifecycle, magrittr, openssl, processx, ps, rlang, sys, vctrs, withr;
  - adding `callr, curl, openssl, R6, rlang, yaml` gives 19, adding only callr, otel and yaml;
  - for comparison, `ellmer` alone gives 26.

  So importing curl, openssl, rlang and R6 costs nothing extra in installation, because httr2 already brings them.
- **Current CRAN versions** (executed on 2026-09-29): httr2 1.3.0 (R >= 4.1), cli 3.6.6, jsonlite 2.0.0, processx 3.9.0, callr 3.8.0, curl 8.0.0, rlang 1.3.0 (R >= 4.0), yaml 2.3.12, testthat 3.3.2 (R >= 4.1), withr 3.0.3, webfakes 1.5.0, vcr 2.1.0 (R >= 4.1), httptest2 1.2.2, knitr 1.52, rmarkdown 2.32, shiny 1.14.0, mirai 2.7.3, nanonext 1.10.3, ellmer 0.5.0, rhub 2.0.1, urlchecker 2.0.0.
- **httr2 minimum version** (from the NEWS on httr2.r-lib.org):
  - 1.2.0 removed `with_mock()`/`local_mock()`, added mocking support for `req_perform_connection()`, and soft-deprecated `req_perform_stream()`;
  - 1.2.3 made mocked responses carry `resp$request` and made SSE decoding much faster;
  - 1.3.0 moved the OAuth cache to `R_user_dir()`.

  Recommendation: `httr2 (>= 1.2.0)`.
- **cli needs rlang.** `cli::cli_abort()` has the body `rlang::abort(message, ...)`, and cli declares rlang only in *Suggests* (VERIFIED: `packageDescription("cli")$Suggests` contains rlang). So gptr must list `rlang` in Imports whenever it uses `cli_abort`, `cli_warn` or `cli_inform`.
- **Suggested packages must be used conditionally.** WRE 1.1.3.1 (lines 563–587): use `requireNamespace(pkg, quietly = TRUE)` together with `pkg::fun`. Never `require()` or `library()` in package code. Beware of top-level or `.onLoad` code that depends on a suggested package being available. CRAN's `noSuggests` extra check and the `check-no-suggests` GitHub workflow enforce this.

### 2.7 Minimum R version (D-23)

Syntax and API floors (R NEWS, VERIFIED via `utils::news()` in R 4.4.3):
- raw strings `r"(...)"` and `tools::R_user_dir()`: R 4.0.0;
- native pipe `|>` and lambda `\(x)`: R 4.1.0;
- named placeholder `_` in the pipe (`x |> f(y = _)`): R 4.2.0;
- `_` as the head of an extraction chain (`_$coef[[2]]`): R 4.3.0;
- base `%||%`: R 4.4.0 (gptr defines an internal fallback).

The decisive platform change is in R 4.2.0 (the WINDOWS section of NEWS): R uses UTF-8 as the native encoding on recent Windows (at least Windows 10 version 1903 or Windows Server 2022/1903), and switched to the UCRT C runtime at the same time.

Recommendation: **`Depends: R (>= 4.2)`**. Reasons:
1. UTF-8 is native on Windows, which removes a whole class of encoding bugs in console I/O, file paths and `system2()` arguments that an LLM harness would otherwise hit.
2. The pipe placeholder becomes available.
3. It equals oldrel-4 today (4.2.3), so the r-lib CI `check-full` matrix can prove it.
4. btw already uses `R (>= 4.2.0)`.

Parse-level syntax such as `|>` cannot be guarded at run time, so the floor must be declared honestly. Duncan Murdoch and Henrik Bengtsson discussed this on R-package-devel (thread root https://stat.ethz.ch/pipermail/r-package-devel/2024q1/010385.html; replies 010386–010390).

### 2.8 Question 4 — updating a CRAN package with a complete API break

- **Reverse dependencies: none.** Executed on 2026-09-29 against 25,106 CRAN packages: `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` returns `character(0)`, and so does `which = "most", recursive = "strong"`. The CRAN page lists no "Reverse depends/imports/suggests".
- **Policy.** API changes that affect reverse dependencies require contacting their maintainers at least 2 weeks ahead (line 216). There are none. The policy does **not** mandate a deprecation cycle, and `.Deprecated()`/`.Defunct()` are courtesy only (R-package-devel "Notifying users of major changes", thread root https://stat.ethz.ch/pipermail/r-package-devel/2022q1/007771.html; Duncan Murdoch's reply 007772). The maintainer decision S-7 ("no deprecation shims") is compatible with policy. UNCERTAIN, as a user-experience point: Duncan Murdoch suggests giving a helpful error when old syntax is used. An optional internal stub that makes `get_response()` point at `gptr()` would add documentation burden (every export needs Rd), so omit it and cover the migration in NEWS.md and README.
- **Version.** Use `1.0.0`: a major release signals breaking change and a stable API (R Packages 21.5, `$W/web/rpkgs_lifecycle.txt` lines 145–216). Always use three components and increase at every submission, including resubmissions (policy lines 204–206; R Packages 22.8).
- **Automation.** Update submissions are processed automatically if they pass (R Packages 22.7). Our incoming check produced only the "Maintainer" line and no "New submission" NOTE (VERIFIED in `$W/build/check-final.log`).
- **Cadence.** After release, space updates 1–2 months apart. aisdk shipped 1.4.10, 1.4.11 and 1.4.12 within 5 days (2026-05-29 to 06-02, VERIFIED in the CRAN archive listing). That was tolerated, but it is against the stated policy.
- **gptr history on CRAN** (archive listing): 0.5.0 (2024-05-06), 0.6.0 (2024-05-07), 0.7.0 (2025-04-05, current). All 13 flavors are OK. Check totals: 12 s on macos-arm64, 23.9 s on debian-gcc, 53 s on r-devel-windows.

### 2.9 Question 5 — testing with no network and no keys

Guidance (VERIFIED):
- R Packages 15.4:
  - put `skip_on_cran()` on anything flaky or slow;
  - `skip_on_cran()` runs a test only when `NOT_CRAN=true`, which devtools and GitHub Actions set;
  - keep the whole suite under about a minute;
  - there is essentially no tolerance for flaky tests on CRAN;
  - web API tests belong off CRAN;
  - snapshot tests are skipped on CRAN by default;
  - write only in the session temp directory and clean up;
  - kill any process you start;
  - turn clipboard features off in tests.

  (`$W/web/rpkgs_testing_advanced.txt` lines 310–366.)
- WRE (`$W/web/rexts_devel.txt` lines 2400–2427):
  - do not test timings;
  - do not test the exact text of R, libcurl or system messages;
  - do not test for the *absence* of warnings;
  - use `options(warn = 1)`;
  - use tolerances;
  - set seeds.

  WRE also notes, from R 4.6.0 on, conditioning on `interactive() && !getOption("quiet", FALSE)` for parts that need an observer (line 2308).
- Ivan Krylov's pattern for internet functions (https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010846.html): raise errors of a specific class, and wrap examples and tests that must touch the internet in `tryCatch(..., pkg_internet_error = function(e) message(...))`, so that other errors still surface.
- API-key examples (Ivan Krylov, https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009966.html; thread root 009965): `\dontrun{}` is acceptable if nothing can run without a key. A better option is `if (nzchar(Sys.getenv("TOKEN"))) withAutoprint({ ... })`, so that a maintainer with the key can run everything.

Techniques and their status in the skeleton (all VERIFIED under `--as-cran`, section 5):

| Layer | Technique | Where it runs |
|---|---|---|
| Agent loop, tools, permissions, history document | Scripted fake provider (`gptr_provider_fake()`) | Everywhere, including CRAN |
| Request building, headers, error classes, key redaction | `httr2::local_mocked_responses(function(req) ... )` returning `httr2::response(status_code, headers, body = charToRaw(json))` | Everywhere |
| Wire formats (Anthropic, OpenAI, Gemini, Jev JSON; SSE streams) | Recorded fixtures in `tests/testthat/fixtures/`, fed to pure parsers | Everywhere |
| Streaming transport end to end (`req_perform_connection()` + `resp_stream_sse()`) | `webfakes::local_app_process(app)` on a random loopback port, stopped automatically; guarded by `skip_if_not_installed("webfakes")` and `("callr")` | Everywhere webfakes is installed |
| Print, format and message UX | `expect_snapshot()`, skipped on CRAN by default (`cran = FALSE`) | CI |
| Live providers | `skip_on_cran()`, `skip_if_offline()`, `skip_if_not(Sys.getenv("GPTR_LIVE_TESTS") == "true")`, `skip_if_no_key("OPENAI_API_KEY")` | Maintainer machine and CI with secrets |
| Interactive consent and REPL | `testthat::local_mocked_bindings(gptr_confirm = function(...) TRUE)`; wrap `readline()`/`askYesNo()`/`menu()` in internal functions so they can be mocked | Everywhere |
| Recorded real traffic (optional) | `vcr` 2.1.0 cassettes, as ellmer uses (53 cassettes in `tests/testthat/_vcr`, `vcr (>= 2.0.0)` in Suggests, `$W/cranpkgs/ellmer/DESCRIPTION` line 30); filter secrets out of cassettes | Everywhere |

### 2.10 Processes, connections, ports, cores and timing

- **Connections left open is a fatal ERROR in examples.** `_R_CHECK_CONNECTIONS_LEFT_OPEN_` is true under `--as-cran` (R Internals line 2195). processx's supervisor opens two R `fifo` connections (`supervisor_stdin*`, `supervisor_stdout*`) that persist for the whole session. `p$kill()` does not close them; `processx::supervisor_kill()` does. Unsupervised processes with pipes create no R connections (VERIFIED: `showConnections()` before and after, 5.4). My first check run failed with *"Error: connections left open: .../supervisor_stdin... (fifo)"* (VERIFIED in `$W/build/check-as-cran.log`).
- **Starting R.** Use `file.path(R.home("bin"), "Rscript")`, with `Rscript.exe` on Windows. `_R_CHECK_R_ON_PATH_` puts failing fake R/Rscript scripts at the head of `PATH` (R Internals line 2181), and WRE line 2382 says the same.
- **Ports.** A fixed port can be taken on a CRAN machine. Ivan Krylov (2026-09-28, shinylight): no fixed port can be assumed; catch the `httpuv::startServer()` failure, give it a class, and `tryCatch` it in examples (https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012559.html; thread root 012557 is Tim Band's question). Use `httpuv::randomPort()` or webfakes.
- **Cores.**
  - Tests: CRAN reports *"Running R code in 'testthat.R' had CPU time 2.7 times elapsed time"* as more than two cores (thread root https://stat.ethz.ch/pipermail/r-package-devel/2023q3/009531.html). Ivan Krylov suggested `OMP_THREAD_LIMIT=2` in tests and vignettes to tame OpenMP dependencies (009532). The fix the maintainer finally shipped set `OMP_THREAD_LIMIT` (to 1) in `.onLoad` (009538); gptr must not do that (it modifies the user's environment).
  - Examples: the NOTE is *"Examples with CPU time > 2.5 times elapsed time"* (Cookbook).
  - `_R_CHECK_LIMIT_CORES_` errors when the `parallel` package spawns more than 2 children (R Internals line 2127).
  - Two callr children are fine if the parent stays idle (Henrik Bengtsson, https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010819.html; thread root 010818).
- **Timing.**
  - Local `--as-cran`: examples over 5 s are reported (`_R_CHECK_EXAMPLE_TIMING_THRESHOLD_` default 5).
  - CRAN incoming on r-devel-windows reported examples over **10 s**. Win-builder r-devel *is* the CRAN r-devel-windows machine: Ivan Krylov said so and Uwe Ligges replied "Yes" (https://stat.ethz.ch/pipermail/r-package-devel/2023q1/008965.html; thread root 008962).
  - Overall check time over 10 minutes gives a NOTE (Cookbook "Overall Checktime").
  - Current references: aisdk totals 339–453 s on the Windows flavors, btw 328–345 s, ellmer 346–430 s, mcptools 97–109 s (VERIFIED on check pages).
- **Detritus.**
  - `_R_CHECK_THINGS_IN_TEMP_DIR_` points `TMPDIR` at a private directory and reports anything left behind.
  - `_R_CHECK_THINGS_IN_CHECK_DIR_` does the same for the check directory.

  Both are on for CRAN (R Internals lines 2227–2233).

### 2.11 Question 6 — CI and pre-submission services

- **r-lib/actions `check-standard.yaml`** (VERIFIED, fetched from the `v2-branch`): matrix `macos-latest/release`, `windows-latest/release`, `ubuntu-latest/devel` (with `http-user-agent: release`), `ubuntu-latest/release`, `ubuntu-latest/oldrel-1`. It uses `actions/checkout@v6`, `setup-pandoc@v2`, `setup-r@v2`, `setup-r-dependencies@v2` (`extra-packages: any::rcmdcheck`, `needs: check`) and `check-r-package@v2` (`upload-snapshots: true`, `build_args: c("--no-manual","--compact-vignettes=gs+qpdf")`).
  - `check-full.yaml` adds oldrel-2, oldrel-3 and oldrel-4.
  - `check-no-suggests.yaml` installs only hard dependencies plus testthat, knitr and rmarkdown, and uses `cache: false`.
- **rhub v2** (VERIFIED from the rhub article and `platforms.json`): run `rhub::rhub_setup()` once, push, then `rhub::rhub_check(platforms = ...)`. It runs on your own GitHub Actions. Without GitHub, `rc_submit()` uses the shared R Consortium runners, which are public.

  Platform names:

  | Group | Platforms |
  |---|---|
  | GitHub runners | `linux`, `macos`, `macos-arm64`, `windows`, `m1-san` |
  | Containers matching CRAN flavors | `ubuntu-clang`, `ubuntu-gcc12`, `ubuntu-next`, `ubuntu-release` |
  | Containers matching CRAN "additional issues" | `atlas`, `c23`, `clang-asan`, `clang-ubsan`, `clang16`–`clang23`, `gcc13`–`gcc16`, `gcc-asan`, `lto`, `nold`, `noremap`, `valgrind`, `mkl`, `intel`, `donttest`, `nosuggests`, `rchk`, `vnu` |
- **win-builder** (VERIFIED, page dated 2026-04-29): R-oldrelease 4.5.3, R-release 4.6.0 (the page predates 4.6.1), R-devel 4.7.0. Results come by email to the DESCRIPTION maintainer in about 30 minutes. Use `devtools::check_win_devel()`.
- **macOS builder**: https://mac.r-project.org/macbuilder/submit.html, which mirrors the CRAN M1 setup. Policy line 214 requires it when macos-arm64 or M1mac issues appear.

### 2.12 Question 7 — vignettes that need API keys

- **Precompute.** Use `vignettes/x.Rmd.orig` and run `knitr::knit("x.Rmd.orig", output = "x.Rmd")` locally. Ship the `.Rmd`, which then contains only Markdown and verbatim output. Put `.Rmd.orig` and the helper script in `.Rbuildignore` (our choice, validated in the skeleton; the rOpenSci post does not itself mention `.Rbuildignore`). Put figures in `vignettes/` with named chunks. Re-knit before each release. (rOpenSci, https://ropensci.org/blog/2019/12/08/precompute-vignettes/, VERIFIED. jsonlite and eia use it.)
- **Alternatives.**
  - Per-chunk `eval = nzchar(Sys.getenv("OPENAI_API_KEY"))`. The vignette text must still read well when chunks do not run.
  - pkgdown-only articles in `vignettes/articles/` (ignored at build), which are not shipped to CRAN.
- In the skeleton the precomputed vignette builds, re-builds and checks cleanly (VERIFIED: "checking re-building of vignette outputs ... OK").
- The vignette must also avoid browsers, Shiny, network, more than 2 cores, and writes outside `tempdir()`. Policy applies to vignettes too (Cookbook).

### 2.13 Other reviewer-flagged items (CRAN Cookbook, extrachecks)

VERIFIED in `$W/web/cookbook_*.txt` and `extrachecks.txt`:
- Use `TRUE`/`FALSE`, never `T`/`F`.
- No `set.seed()` with a fixed number inside functions; offer a `seed = NULL` argument.
- `print()`/`cat()` in functions must be suppressible: use `message()`, or a `verbose`/`quiet` switch. Print methods and interactive functions are exempt.
- Reset `options()`, `par()`, `setwd()` and similar with `on.exit()` placed immediately after the change, using `add = TRUE` for further calls. In examples and vignettes, reset explicitly.
- `options(warn = -1)` is never acceptable; use `suppressWarnings()`.
- No `installed.packages()`; use `requireNamespace()`, `find.package()` or `system.file()`.
- Do not install packages in functions, examples, tests or vignettes. Dedicated installer functions are allowed for API or installer packages, must say so in their name and docs, and must not be called in examples or tests.
- No `rm(list = ls())` in examples.
- Every exported function needs `\value`, including "No return value, called for side effects", and should have examples.
- Examples must not contain commented-out code.
- Use `\dontrun{}` only when the code truly cannot run (a missing key or software), and prefer `\donttest{}` for slow code. `--as-cran` runs `\donttest` code (`_R_CHECK_DONTTEST_EXAMPLES_`).
- Wrap interactive-only functions such as Shiny apps in `if (interactive())`.
- Use `try()` for examples that demonstrate errors.
- Unexported functions must not have example Rd; use `@noRd`.
- Relative links in README must exist in the built tarball.
- URLs must use https and must not redirect (use `urlchecker::url_check()`/`url_update()`).
- `\url{}` only for always-live URLs; `localhost` in `\samp{}` (https://cran.r-project.org/web/packages/URL_checks.html).
- URL checks have a 60 s connection timeout.

---

## 3. Exact specifications

### 3.1 The proposed DESCRIPTION

**(a) Validated text.** This is exactly what `R CMD check --as-cran` passed (5.4); file `$W/pkg/gptr/DESCRIPTION`:

```
Package: gptr
Title: Language Model Agents Inside the Live 'R' Session
Version: 1.0.0
Authors@R:
    person("Wanjun", "Gu", , "wanjun.gu@ucsf.edu", role = c("aut", "cre", "cph"),
           comment = c(ORCID = "0000-0002-7342-7000"))
Description: Runs large language model agents inside the running 'R'
    session, so that models inspect and modify objects that are already in
    memory instead of re-running scripts from scratch. A single function,
    gptr(), opens an interactive chat in the console or, given a prompt,
    runs the agent loop and returns a value that can be piped into further
    prompts. Supports the 'Anthropic', 'OpenAI' and 'Google Gemini'
    application programming interfaces, 'OpenAI'-compatible endpoints, the
    'Claude Code' and 'Codex' command line tools, and System One
    typed-decision models such as 'Jev'
    <https://typesafe.ai/blog/introducing-system-one-models-and-jev>, whose
    calibrated yes/no, choice and score answers can be used directly in if()
    and for() statements. Tools for reading, writing, editing and searching
    files and for evaluating 'R' code are implemented in 'R'; skills,
    extensions, Model Context Protocol ('MCP') servers, sub-agents and
    'shiny' apps are supported. Sessions are recorded as 'R' scripts,
    'R Markdown', 'Quarto' or 'Jupyter' documents that can be re-run.
    Writing files and evaluating model-generated code require the user's
    permission by default.
License: MIT + file LICENSE
URL: https://github.com/Broccolito/gptr
BugReports: https://github.com/Broccolito/gptr/issues
Depends:
    R (>= 4.2)
Imports:
    cli (>= 3.6.0),
    httr2 (>= 1.2.0),
    jsonlite,
    processx (>= 3.8.0),
    rlang (>= 1.1.0),
    tools,
    utils
Suggests:
    callr,
    knitr,
    rmarkdown,
    testthat (>= 3.2.0),
    webfakes,
    withr
VignetteBuilder:
    knitr
Config/testthat/edition: 3
Encoding: UTF-8
Language: en-US
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.3.3
SystemRequirements: Optional command line tools: 'claude' (Claude Code)
    and 'codex' (Codex) for subscription providers, 'quarto' for 'Quarto'
    documents.
```

Checks behind it (VERIFIED):
- `tools::toTitleCase(Title) == Title`, 49 characters.
- CRAN-style aspell emulation (`$W/tools/spell_desc.R`): no flagged words.
- The URLs return HTTP 200 without redirects:
  - `https://typesafe.ai/blog/introducing-system-one-models-and-jev`;
  - `https://github.com/Broccolito/gptr`;
  - `.../issues`.

  Do **not** use `https://broccolito.github.io/gptr/` until it exists (404 today). Also avoid `https://docs.anthropic.com/en/api` (301) and `https://platform.openai.com/docs/api-reference` (301).

**(b) Production dependency fields.** These are the recommended fields for the real package once the code exists. Not check-validated, because the code does not exist yet; every package is on CRAN (VERIFIED with `available.packages()`).

```
Depends:
    R (>= 4.2)
Imports:
    cli (>= 3.6.0),
    curl (>= 6.0.0),
    grDevices,
    httr2 (>= 1.2.0),
    jsonlite (>= 1.8.0),
    openssl,
    processx (>= 3.8.0),
    rlang (>= 1.1.0),
    stats,
    tools,
    utils,
    yaml
Suggests:
    arrow, bslib, callr, collapse, data.table, duckdb, ellmer, evaluate,
    httpuv, keyring, knitr, later, magick, promises, qs2, quarto, ragg,
    rmarkdown, rstudioapi, shiny, stringi, testthat (>= 3.2.0), vroom,
    webfakes, withr
VignetteBuilder: knitr
Config/testthat/edition: 3
Config/Needs/website: pkgdown
```

That is 8 non-base Imports, well under the 20-package NOTE, and a closure of 19 packages. If Rcpp is justified under REQ-01, add `LinkingTo: Rcpp`, `Imports: Rcpp`, and let `NeedsCompilation: yes` be set automatically. If any Pi code or prompt text is ported, add
`person("Mario", "Zechner", role = c("ctb", "cph"), comment = "Author of 'pi', from which parts are derived")`
and an `inst/COPYRIGHTS` file (Pi is MIT, "Copyright (c) 2025 Mario Zechner": VERIFIED in `$S/pi/LICENSE`).

### 3.2 LICENSE (template MIT) — exact content

```
YEAR: 2026
COPYRIGHT HOLDER: Wanjun Gu
```

The repository's `LICENSE` currently says `YEAR: 2023` (VERIFIED). Update it. Keep the full text in `LICENSE.md`, which is already ignored at build.

### 3.3 `.Rbuildignore` — recommended content (validated in the skeleton)

```
^.*\.Rproj$
^\.Rproj\.user$
^LICENSE\.md$
^dev$
^renv$
^renv\.lock$
^\.Rprofile$
^cran-comments\.md$
^CRAN-SUBMISSION$
^\.github$
^_pkgdown\.yml$
^docs$
^pkgdown$
^revdep$
^\.gptr$
^vignettes/.*\.Rmd\.orig$
^vignettes/precompute\.R$
```

`R CMD build` drops `.Rprofile` even without this entry (VERIFIED: probe tarball listing). It is listed anyway for clarity. `.gptr` *does* enter the tarball when not ignored (VERIFIED).

### 3.4 NEWS.md (validated format)

```markdown
# gptr 1.0.0

This is a complete rewrite. gptr is now an agent harness that runs inside
the R session. Nothing from the 0.x API is kept.

## Breaking changes

* `get_response()` and `dataframe_to_text()` have been removed. Use
  `gptr("prompt")` instead of `get_response()`, and pass a data frame
  directly (`gptr("describe this", df)`) instead of `dataframe_to_text()`.
* The package no longer depends on 'RCurl'; HTTP is handled by 'httr2'.
* R (>= 4.2) is now required.

## New features

* `gptr()` is the single entry point: an interactive console chat when
  called without a prompt, a programmable function when given one.
* `gptr_init()` creates a `.gptr/` project workspace, only when called.
```

Headings must be `# gptr <version>`. `R CMD check` parses NEWS.md, and the URLs in it are checked.

### 3.5 cran-comments.md (template for 1.0.0)

```markdown
## Submission

This is a major update (0.7.0 -> 1.0.0) and a complete rewrite by the same
maintainer. The previous functions `get_response()` and
`dataframe_to_text()` are removed (documented in NEWS.md).

* The package never writes to the user's home filespace or working
  directory by default: files are written only by functions the user calls
  explicitly with a path (e.g. `gptr_init(path)`), after interactive
  confirmation, or under a permission mode the user selects. Examples,
  tests and vignettes write only to `tempdir()` and clean up.
* Model-generated R code is evaluated only in the environment the user
  passes (default: the caller's frame), after the user approves it; the
  package never assigns into the global environment itself.
* Examples that need an API key use `@examplesIf` on the presence of the
  key; all tests that need network or keys are skipped on CRAN; a scripted
  fake provider is used instead. The vignette is precomputed.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Reverse dependencies

There are currently no reverse dependencies for this package
(`tools::package_dependencies("gptr", reverse = TRUE, which = "all")`).
```

On resubmission, add at the top: `## Resubmission` followed by "This is a resubmission. In this version I have: ..." (R Packages 22.8). Increase the patch version as well.

### 3.6 Environment variables and constants that matter

| Variable / constant | Value in CRAN / `--as-cran` | Effect for gptr | Source |
|---|---|---|---|
| `_R_CHECK_EXCESSIVE_IMPORTS_` | 20 | NOTE if more than 20 non-base Imports | R-ints line 2255; R source |
| Depends limit | more than 5 packages other than R and base/datasets/grDevices/graphics/methods/utils/stats gives a NOTE | Use Depends only for R | R source (`.check_package_depends`) |
| `_R_CHECK_CONNECTIONS_LEFT_OPEN_` | TRUE | Fatal error if an example leaves a connection open (processx supervisor fifos!) | R-ints 2195; experiment |
| `_R_CHECK_THINGS_IN_TEMP_DIR_` / `_CHECK_DIR_` | true | NOTE on leftover files | R-ints 2227–2233 |
| `_R_CHECK_THINGS_IN_OTHER_DIRS_` | off by default and not in the `--as-cran` set; used in CRAN's donttest extra run (rsurvstat, 2026) | NOTE on new files in `~` (top level), `/tmp`, `/dev/shm`, `~/.cache`, `~/.local/share` and platform equivalents (the default data/cache `R_user_dir()` roots; Linux `~/.config` is not monitored recursively) | R-ints 2235; experiment |
| `_R_CHECK_CODE_ASSIGN_TO_GLOBALENV_` | TRUE | NOTE on `assign(..., envir = globalenv())` / `.GlobalEnv` / `pos = 1`. `eval(expr, envir)` with a variable environment is **not** flagged | R-ints 2089; R source; experiment |
| `_R_CHECK_R_ON_PATH_` | TRUE | Catches a bare `Rscript`/`R` taken from the PATH | R-ints 2181 |
| `_R_CHECK_LIMIT_CORES_` | TRUE | Error if the `parallel` package spawns more than 2 children | R-ints 2127 |
| `_R_CHECK_SCREEN_DEVICE_` | stop | Error if examples open a screen graphics device | R-ints 2109 |
| `_R_CHECK_BROWSER_NONINTERACTIVE_` | TRUE | Traps leftover `browser()` | R-ints 2299 |
| `_R_CHECK_DONTTEST_EXAMPLES_` | on with `--as-cran` | `\donttest{}` code is run | R-ints 2259 |
| `_R_CHECK_SUGGESTS_ONLY_` / `_R_CHECK_DEPENDS_ONLY_` | Suggests-only for CRAN runs; depends-only in the noSuggests extra check | Suggests must be guarded | R-ints 2347–2363 |
| `_R_CHECK_FORCE_SUGGESTS_` | FALSE for CRAN incoming | Missing Suggests give a NOTE, not an error | R-ints 2425; experiment |
| `_R_CHECK_TIMINGS_` | 10 (CRAN) | Timings reported; Windows reports elapsed time only | R-ints 2045 |
| `_R_CHECK_EXAMPLE_TIMING_THRESHOLD_` | 5 s (the incoming Windows note used 10 s) | Keep each example under 1 s | R-ints 2049; R-pkg-devel 2023q1 |
| CPU/elapsed ratio NOTE | 2.5 (examples); tests and vignettes ratio not checked on Windows | Two cores at most | Cookbook; R-ints 2053–2063 |
| `_R_CHECK_PACKAGE_NAME_` | set by R CMD check to the package name for the whole per-package check (examples, tests), but temporarily unset while R code from `inst/doc` vignettes is run | Detects "running under check" (not reliable inside vignette code) | R source (`Sys.setenv` in `check_pkg()` inside `.check_packages`) |
| `NOT_CRAN` | set to "true" by devtools and r-lib/actions; unset on CRAN | `skip_on_cran()` | R Packages 15.4.1 |
| `_R_CHECK_CRAN_INCOMING_USE_ASPELL_` | default FALSE in the R source; LIKELY TRUE on CRAN's incoming machines (not documented in R-ints) | Spell check of Title and Description, with the filters in 2.5 | R source; CRAN pretest NOTEs |
| `_R_CHECK_URLS_SHOW_301_STATUS_` | true | Redirecting URLs reported | R-ints 2303 |
| Title length | listings may truncate at 65 characters | 49 chars | WRE 1.1.1 |
| Tarball, docs, data | 10 MB; 5 MB; 5 MB | Keep fixtures and precomputed figures small | Policy 89–97 |
| Path length inside tarball | 100 bytes | Short fixture and skill paths | WRE line 317 |
| URL connection timeout | 60 s | — | URL_checks |
| Overall check time | more than 10 min gives a NOTE | Budget: under 3 min on Windows | Cookbook |
| Test suite | about 1 min or less | Skeleton: 2.3 s | R Packages 15.4.2 |
| Update cadence | "no more than every 1–2 months" | — | Policy 208 |
| Revdep notice | at least 2 weeks | None needed today | Policy 216 |
| Check page settle time | at least 48 h | — | Policy 210 |
| testthat parallel default | 2 CPUs unless the `Ncpus` option or `TESTTHAT_CPUS` is set (`getOption("Ncpus")` is consulted first) | Compliant only if the check machine does not set `Ncpus`; keep parallel off | testthat 3.3.2 source (`testthat:::default_num_cpus`) |

### 3.7 Reproduced CRAN check messages (useful for grep in CI logs)

All VERIFIED from my runs (`$W/build/check-as-cran.log`, `$W/probe/probe-check.log`, `$W/probe` hidden-directory run):

```
The Title field should be in title case. Current version is:
'Language Model Agents That Work Inside the Live 'R' Session'
In title case that is:
'Language Model Agents that Work Inside the Live 'R' Session'

Error: connections left open:
	.../RtmpTVnAl9/supervisor_stdin17b6250879b2d (fifo)
	.../RtmpTVnAl9/supervisor_stdout17b6276dcd0a8 (fifo)

* checking package dependencies ... NOTE
Imports includes 21 non-default packages.
Importing from so many packages makes the package vulnerable to any of
them becoming unavailable.  Move as many as possible to Suggests and
use conditionally.

* checking R code for possible problems ... NOTE
Found the following assignments to the global environment:
File 'probe13/R/probe.R':
  assign("probe_value", x, envir = globalenv())

* checking for new files in some other directories ... NOTE
Found the following files/directories:
  '~/Library' '~/Library/Caches/org.R-project.R/R'
  '~/Library/Caches/org.R-project.R/R/probe13'
  '~/Library/Caches/org.R-project.R/R/probe13/probe.txt'

* checking for hidden files and directories ... NOTE
Found the following hidden files and directories:
  .gptr

* checking package dependencies ... NOTE
Package suggested but not available for checking: 'webfakes'
```

### 3.8 GitHub Actions matrix for gptr (adapted from r-lib/actions v2 examples)

```yaml
# .github/workflows/R-CMD-check.yaml
on:
  push: {branches: [main]}
  pull_request:
name: R-CMD-check.yaml
permissions: read-all
jobs:
  R-CMD-check:
    runs-on: ${{ matrix.config.os }}
    name: ${{ matrix.config.os }} (${{ matrix.config.r }})
    strategy:
      fail-fast: false
      matrix:
        config:
          - {os: macos-latest,   r: 'release'}
          - {os: windows-latest, r: 'release'}
          - {os: windows-latest, r: 'oldrel-4'}   # proves R >= 4.2 on Windows (UTF-8/UCRT)
          - {os: ubuntu-latest,  r: 'devel', http-user-agent: 'release'}
          - {os: ubuntu-latest,  r: 'release'}
          - {os: ubuntu-latest,  r: 'oldrel-1'}
          - {os: ubuntu-latest,  r: 'oldrel-4'}
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      R_KEEP_PKG_SOURCE: yes
      _R_CHECK_THINGS_IN_OTHER_DIRS_: true   # catch R_user_dir writes during tests
      _R_CHECK_CRAN_INCOMING_: false
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.config.r }}
          http-user-agent: ${{ matrix.config.http-user-agent }}
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::rcmdcheck
          needs: check
      - uses: r-lib/actions/check-r-package@v2
        with:
          upload-snapshots: true
          build_args: 'c("--no-manual","--compact-vignettes=gs+qpdf")'
          args: 'c("--no-manual", "--as-cran")'
```

Add `check-no-suggests.yaml` unchanged from r-lib/actions. Add a separate, manually triggered "live" workflow that sets `GPTR_LIVE_TESTS: true` and the provider keys from `secrets`. It must never run on pull requests from forks.

---

## 4. Recommended design for gptr — THE CHECKLIST

Every item has a **Rule**, a **Source**, and a **gptr pattern** with R code. Internal
helper names match the skeleton, which passed `--as-cran`: `gptr_is_interactive()`,
`gptr_confirm()`, `gptr_inform()`, `gptr_max_workers()`, `gptr_redact()`,
`gptr_user_dir()`.

### A. Package metadata

**C-01 Title.** Rule: title case (`tools::toTitleCase`), at most 65 characters, no period, no markup, no package name, software names in single quotes, avoid redundant "for R". Source: WRE 1.1.1 (https://cran.r-project.org/doc/manuals/r-devel/R-exts.html#The-DESCRIPTION-file); Cookbook "Title Case"; extrachecks. Pattern:
```r
title <- "Language Model Agents Inside the Live 'R' Session"
stopifnot(identical(tools::toTitleCase(title), title), nchar(title) <= 65)
```

**C-02 Description.** Rule: one paragraph, several complete sentences, no "This package"/package name/"Functions for" at the start, single quotes for packages, software and APIs (including 'R'), `fun()` without quotes, double quotes only for titles, URLs as `<https://...>`, explain acronyms. Source: WRE 1.1.1; https://cran.r-project.org/web/packages/submission_checklist.html; extrachecks. Pattern: the text in 3.1. Test it with the aspell emulation:
```r
# $W/tools/spell_desc.R  (CRAN's ignore regexes + hunspell en_US/en_GB)
ignore <- c("(?<=[ \t[:punct:]])'[^']*'(?=[ \t[:punct:]])",
            "(?<=[ \t[:punct:]])([[:alnum:]]+::)?[[:alnum:]_.]*\\(\\)(?=[ \t[:punct:]])",
            "(?<=[<])(https?://|DOI:|doi:|arXiv:)[^>]+(?=[>])")
```

**C-03 Authors@R.** Rule: required for CRAN. The maintainer has `cre`; add `cph`; ORCID is encouraged. Credit derived code (Pi, MIT) with `ctb`/`cph` and keep its copyright notice (`inst/COPYRIGHTS`). Credit bundled JavaScript or CSS used in Shiny artifacts the same way (btw credits Google, Microsoft and countUp.js as `cph`). Source: WRE 1.1.1; policy lines 43–49 (ownership, `ctb` and `cph` roles); extrachecks "cph". Pattern: 3.1(a); 3.1(b) for Pi.

**C-04 Maintainer address.** Rule: a single person with a working, unfiltered address. Explain any change and confirm from the old address. Source: policy lines 51, 188. Pattern: keep `wanjun.gu@ucsf.edu`, which CRAN has on file.

**C-05 License.** Rule: `MIT + file LICENSE`, with LICENSE holding only `YEAR`/`COPYRIGHT HOLDER`. Source: WRE 1.1.2; Cookbook "LICENSE files"; https://stat.ethz.ch/pipermail/r-package-devel/2024q1/010357.html (Krylov; thread root 010356). Pattern: 3.2. Keep `LICENSE.md` in `.Rbuildignore`.

**C-06 Minimum R.** Rule: declare a real floor, with no patch level, and test it. Source: WRE 1.1.3 (line 511); R Packages 9.6.1; R NEWS 4.2.0 (UTF-8 on Windows). Pattern: `Depends: R (>= 4.2)`, and CI on `oldrel-4`. Guard base functions newer than 4.2:
```r
`%||%` <- function(x, y) if (is.null(x)) y else x   # base only from R 4.4.0
```

**C-07 Imports budget.** Rule: at most 20 non-base Imports (NOTE otherwise), at most 5 Depends, and every Import used. Source: R-ints `_R_CHECK_EXCESSIVE_IMPORTS_`; `tools:::.check_package_depends`. Pattern: the 8 Imports in 3.1(b). Every other package goes to Suggests (C-08). Reference each Import at least once with `pkg::fun`. Import `rlang` whenever cli condition helpers are used.

**C-08 Suggests used conditionally.** Rule: every use of a Suggests package in code, examples, tests and vignettes is guarded, and the package must pass a check without Suggests. Source: WRE 1.1.3.1; policy line 77; extrachecks "noSuggests"; R Packages 11.5. Pattern:
```r
gptr_need <- function(pkg, why) {
  rlang::check_installed(pkg, reason = why)   # interactive: offers to install; batch: classed error
}
gptr_fast_reader <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fread(path)
  } else {
    utils::read.csv(path)
  }
}
# tests:    skip_if_not_installed("webfakes")
# examples: #' @examplesIf rlang::is_installed("shiny") && interactive()
```

**C-09 External programs.** Rule: declare them in `SystemRequirements`, use them only after `Sys.which()` finds them, and pass checks without them. Never require software that restricts users or usage. Start R as `R.home("bin")/Rscript`. Never assume a POSIX shell. Source: WRE 1.6 (lines 2368–2387); policy line 63; R-ints `_R_CHECK_R_ON_PATH_`. Pattern:
```r
gptr_cli_path <- function(name = c("claude", "codex")) {
  name <- match.arg(name)
  p <- Sys.which(name)
  if (!nzchar(p)) return(NULL)   # caller falls back / explains; never errors at load
  unname(p)
}
gptr_rscript <- function() {
  exe <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  file.path(R.home("bin"), exe)
}
# tests: skip_if(is.null(gptr_cli_path("claude")), "claude CLI not installed")
```
Run programs with `processx::run(path, args_vector)`. It needs no shell, so no quoting problems on Windows. `system("bash -c ...")` is not allowed (REQ-03, S-4).

**C-10 URLs.** Rule: https, live, no redirects; `\url{}` only for always-live URLs; `localhost` examples (Ollama at `http://localhost:11434`, MCP loopback servers) in `\samp{}` or code format. Source: https://cran.r-project.org/web/packages/URL_checks.html; extrachecks. Pattern: run `urlchecker::url_check()` before release. In roxygen, write localhost addresses as code spans, never as links.

**C-11 Version.** Rule: it must increase with every submission, uses three components, and a major version signals the break. Source: policy line 204; R Packages 21. Pattern: `1.0.0`; `1.0.1` for any resubmission.

**C-12 NEWS.md.** Rule: headings `# gptr x.y.z`; document breaking changes. Source: R Packages ch. 18.2 and 22. Pattern: 3.4.

**C-13 cran-comments.md.** Rule: check results, reverse-dependency results, explanation of NOTEs, and a resubmission section when needed. Put it in `.Rbuildignore`. Source: R Packages 22.6. Pattern: 3.5.

**C-14 `.Rbuildignore`.** Rule: no development files, hidden directories or large sources in the tarball. Source: WRE 1.3.2; the hidden-files check. Pattern: 3.3, which includes `^\.gptr$` and `^vignettes/.*\.Rmd\.orig$`.

**C-15 ASCII and portable file names.** Rule: R code files must be ASCII; use `\uxxxx` escapes in strings. File names must be ASCII, at most 100 bytes of path, with no case-only differences and no Windows reserved names. Source: WRE 1.1 (line 317), 1.1.5 (line 613), 1.6.1. Pattern:
```r
gptr_symbols <- list(tick = "\u2714", bullet = "\u2022")   # never type the glyph itself
# cli::symbol$tick already falls back to ASCII on non-UTF-8 consoles
```
VERIFIED: `tools:::.check_package_ASCII_code()` flags a file containing literal UTF-8 and accepts its `\u` escape version (5.6). The verifier also confirmed that `R CMD check --as-cran` reports this as a **WARNING** ("checking code files for non-ASCII characters") even when DESCRIPTION declares `Encoding: UTF-8`.

**C-16 Size and binaries.** Rule: tarball at most 10 MB, docs and data at most 5 MB each, no executables in the sources. Source: policy lines 59, 89–97. Pattern: never bundle ripgrep or node binaries or CLI installers. Ship a compact model catalog snapshot (for example `inst/extdata/models.json`, compressed if large), and keep fixtures small.

### B. File system

**C-17 No default writes.** Rule: nothing outside `tempdir()` without an explicit path or interactive confirmation. Writing functions have no default path. Source: policy lines 116–118; Cookbook "Writing Files ..."; Maechler 2019 (https://stat.ethz.ch/pipermail/r-package-devel/2019q4/004535.html). Pattern:
```r
gptr_write_file <- function(path, text, permission = gptr_permission()) {
  if (missing(path)) cli::cli_abort("{.arg path} is required.")      # no default path
  if (!gptr_allow("write", path, permission)) {
    return(gptr_denied("write", path))
  }
  gptr_write_atomic(path, text)
}
```

**C-18 `.gptr/` only by explicit init or interactive yes.** Rule: see C-17. Source: see 2.4. Pattern (VERIFIED in the skeleton, full code in 5.2):
```r
gptr_init <- function(path, overwrite = FALSE) {
  if (missing(path)) {
    if (!gptr_is_interactive())
      cli::cli_abort(c("{.arg path} must be supplied in non-interactive sessions.",
                       "i" = "gptr only writes to directories that you name explicitly."))
    path <- getwd()
    if (!gptr_confirm(sprintf("Create a '.gptr' workspace in %s?", path)))
      return(invisible(NULL))
  }
  ...
}
gptr_session_dir <- function(project = getwd()) {
  ws <- gptr_workspace(project)                 # existing .gptr/ = persisted consent
  if (is.null(ws)) file.path(tempdir(), "gptr-sessions") else file.path(ws, "sessions")
}
```

**C-19 Global state in `R_user_dir`, small and managed.** Rule: R >= 4.0 (satisfied); keep it minimal; prune; never write into the installed package. Source: policy line 120; https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009947.html (Urbanek; thread root 009944). Pattern:
```r
gptr_user_dir <- function(which = c("config", "data", "cache")) {
  which <- match.arg(which)
  root <- getOption("gptr.user_dir")
  if (!is.null(root)) return(file.path(root, which))
  tools::R_user_dir("gptr", which = which)
}
gptr_cache_prune <- function(max_age_days = 30, max_mb = 50) { ... }   # call opportunistically, cheap
```
Credentials go in `gptr_user_dir("data")` only through an explicit `gptr_auth_login()`/`gptr_config_set(key=)`. Set file mode `0600` with `Sys.chmod()` on Unix (it is a no-op on Windows; document this). Prefer `keyring` (Suggests) when installed.

**C-20 Examples, tests and vignettes write only to `tempdir()` and clean up.** Rule: no detritus in the temp or check directory. Source: policy line 116; Cookbook "Leaving Files in the Temporary Directory"; R Packages 14.3.7 and 15.4.5. Pattern:
```r
#' @examples
#' proj <- file.path(tempdir(), "gptr-example"); dir.create(proj)
#' ws <- gptr_init(proj)
#' unlink(proj, recursive = TRUE)
test_that("...", {
  proj <- withr::local_tempdir()   # auto-deleted
  withr::local_dir(proj)           # restores getwd()
  ...
})
```

**C-21 Tests must not touch `R_user_dir` locations.** Rule: CRAN's extra checks report new files in `~`, `~/.cache`, `~/.local/share` and their equivalents. Source: R-ints `_R_CHECK_THINGS_IN_OTHER_DIRS_`; rsurvstat 2026 (https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012484.html, Krylov's reply 012486); btw's `local_user_home()` (`$W/cranpkgs/btw/tests/testthat/helpers.R` lines 190–201). Pattern (`tests/testthat/setup.R`, VERIFIED):
```r
user_root <- withr::local_tempdir("gptr-user-", .local_envir = teardown_env())
withr::local_envvar(
  R_USER_CONFIG_DIR = file.path(user_root, "config"),
  R_USER_DATA_DIR   = file.path(user_root, "data"),
  R_USER_CACHE_DIR  = file.path(user_root, "cache"),
  OMP_THREAD_LIMIT  = "2",
  .local_envir = teardown_env()
)
```
Examples that must show cache behaviour set `options(gptr.user_dir = file.path(tempdir(), "gptr-user"))` first and restore the option afterwards.

**C-22 Clipboard counts as home filespace.** Rule: no clipboard writes in tests or examples; interactive opt-in only. Source: policy line 116; R Packages 15.4.5. Pattern: `gptr_copy()` only when `gptr_is_interactive()`, and never called from tests.

**C-23 The script-as-history document is a user file.** Rule: see C-17. Source: policy line 116. Pattern: `gptr(..., doc = "analysis.R")`, `gptr_record(path)`, or interactive confirmation of the detected active document (`rstudioapi`, in Suggests). The permission mode `manual` asks before each edit. Write atomically (C-58) and keep a backup in `.gptr/` or `tempdir()`.

### C. Session state

**C-24 Never assign into the global environment from package code.** Rule: no `assign(..., envir = globalenv())`, no `<<-` that reaches the global environment, no `rm(list = ls())` in examples. Evaluate in the caller-supplied environment. Source: policy line 122; Cookbook "Writing to the .GlobalEnv"; R-ints `_R_CHECK_CODE_ASSIGN_TO_GLOBALENV_`. The static check flags only `assign()` whose `envir` or `pos` evaluates to the global environment. `eval(expr, envir = <variable>)` is not flagged (VERIFIED, 5.6). Pattern (VERIFIED, 5.2):
```r
gptr_eval <- function(code, envir = parent.frame(), permission = c("ask", "auto", "deny")) { ... }
# examples/tests always pass envir = new.env()
```
At top level, `parent.frame()` is the global environment because the *user* called `gptr()` there. This is a user-directed evaluation, like `source()`. Document it in `?gptr` and `?gptr_eval`.

**C-25 Restore anything changed.** Rule: `options()`, `par()`, `setwd()`, `Sys.setenv()`, `Sys.setlocale()` and graphics devices are restored with `on.exit(..., add = TRUE)` or withr, placed immediately after the change. Never `options(warn = -1)`. Source: Cookbook "Change of Options ..." and "Setting options(warn = -1)". Pattern:
```r
gptr_capture_plot <- function(expr, file) {
  grDevices::png(file); dev <- grDevices::dev.cur()
  on.exit(grDevices::dev.off(dev), add = TRUE)
  old <- options(warn = 1); on.exit(options(old), add = TRUE)
  force(expr)
}
```
For the r tool, do not restore changes that the *user's* code made on purpose (for example `setwd()` requested by the model under approval). Do report them in the tool result. btw restores wd, options and env vars after each run (`withr::local_dir(getwd())`, `local_options()`, `local_envvar()`, `$W/cranpkgs/btw/R/tool-run.R`). gptr should offer the same as an option: `gptr.r_tool.restore = TRUE` by default in non-interactive runs.

**C-26 No fixed seeds in functions.** Rule: see title. Source: Cookbook "Setting a Specific Seed". Pattern: `seed = NULL` arguments only, for example in sampling for System One emulation.

**C-27 Never call `q()`/`quit()`; the REPL exits by returning.** Rule: see title. Source: policy line 112. Pattern: the interactive loop ends with `/exit` and returns `invisible(session)`. The advisory risk classifier (D-11) marks model code that calls `q(`, `quit(`, `.Internal(`, `system(`/`system2(` or `install.packages(` as *high risk*, so it always requires explicit approval, even in `auto` mode.

**C-28 Do not tamper with loaded code.** Rule: no `assignInNamespace`, `unlockBinding` or `trace` on other packages; public API only; no `:::` into base. Source: policy lines 114, 132; R-ints `_R_CHECK_UNSAFE_CALLS_`. Pattern: hook into R through public mechanisms only: `addTaskCallback()`, knitr engines and hooks, `rstudioapi`, and your own print methods. Interrupts (REQ-38) use `tryCatch(interrupt = )` and `later`, not base patches.

**C-29 Side-effect-free load.** Rule: `.onLoad` does no writes, network, `options()`/`Sys.setenv()` changes or messages. `.onAttach` uses only `packageStartupMessage()`, and the check verifies that startup messages can be suppressed. Source: WRE 1.5; check step "whether startup messages can be suppressed" (passed in the skeleton). Pattern (VERIFIED):
```r
.onLoad <- function(libname, pkgname) {
  reg.finalizer(the, kill_all_workers, onexit = TRUE)   # cleanup only
  invisible(NULL)
}
```
Do not auto-load `.env` files on load. Load them on an explicit `gptr_env_load(path)` or at the first provider use, with a message.

**C-30 Suppressible output.** Rule: informational output through `message()`/cli, with a quiet switch. `print()`/`cat()` only in print methods and interactive functions. Source: Cookbook "Using print()/cat()". Pattern:
```r
gptr_inform <- function(msg, .envir = parent.frame()) {
  if (isTRUE(getOption("gptr.quiet", FALSE))) return(invisible(NULL))
  cli::cli_inform(msg, .envir = .envir)
}
```
Streaming tokens to the console is interactive output and is allowed. Programmatic `gptr("...")` returns a value and streams only when `stream = TRUE` or when running interactively.

**C-31 Environment variables and secrets.** Rule: no global side effects the user did not ask for; secrets never appear in output. Source: policy line 122 (by analogy); REQ-13 and D-22. Pattern: the `.env` loader returns a named list and stores keys in a package-private environment (`the$keys`). It calls `Sys.setenv()` only if the user passes `set_env = TRUE`. All errors pass through `gptr_redact()` (C-37).

### D. Code execution, security, privacy

**C-32 Model code runs only under the chosen permission mode.** Rule: this is not a formal policy item, but it is the basis for claiming "user-initiated" (2.3). Source: 2.3 precedents (btw opt-in; ellmer `on_tool_request`/`tool_reject`). Pattern (VERIFIED in the skeleton): the default is `permission = "ask"`, which calls `gptr_confirm()`. That returns FALSE when nobody can answer, so code does **not** run in batch or knitr unless the call says `permission = "auto"`. Document "not a security boundary" as btw and mcptools do.
```r
allowed <- switch(permission,
  auto = TRUE, deny = FALSE,
  ask  = gptr_confirm(paste0("Run this R code?\n", code, "\n")))
```

**C-33 No automatic installs.** Rule: no `install.packages()` or software installs in functions, examples, tests or vignettes. Installer helpers must be named as such. Source: Cookbook "Installing Software"; policy line 142 (secure downloads). Pattern: gptr never calls `install.packages()` itself. `rlang::check_installed()` may *offer* installs interactively. Model code containing installs is high risk (C-27). Do not download the `claude`/`codex` CLIs; print instructions instead.

**C-34 Sending session data to third parties.** Rule: information about the R session must not be sent without the user's confirmation. Source: policy line 126. Pattern: gptr sends data to a provider only when the user calls `gptr()` or the chat. The default context is minimal: the prompt, attached objects the user passed, and tool results the user approved in `manual` mode. The system prompt's automatic context (object listings from REQ-21, `sessionInfo()`) is documented in `?gptr_context` and can be switched off with `options(gptr.context = "none")`. On first use of each provider in an interactive session, show once what is sent, and record the acknowledgement in `gptr_user_dir("config")`. No telemetry, ever. (LIKELY sufficient; UNCERTAIN whether a reviewer would ask for more.)

**C-35 Never weaken TLS.** Rule: TLS verification may not be disabled. Source: policy line 136. Pattern: never set `ssl_verifypeer = 0`. For self-signed local endpoints, let users pass a CA bundle: `httr2::req_options(req, cainfo = path)`. Plain `http://localhost` is fine.

**C-36 Untrusted text is never a format string.** Rule: glue/cli evaluate `{...}`. Source: my experiment (5.3). Pattern:
```r
detail <- gptr_redact(body, key)
cli::cli_abort(c("HTTP {status} from provider.", "x" = "{detail}"), class = "gptr_http_error")
# NOT: cli::cli_abort(c("...", "x" = body))   # a body containing {..} is evaluated as R code
```
Apply the same rule to `cli_text()` output of model replies (`cli::cli_text("{reply}")` or `cli::cli_verbatim(reply)`) and to any `glue()` of model output.

**C-37 Secrets redacted everywhere.** Rule: see REQ-13 and D-22. Source: the httr2 "Wrapping APIs" vignette (https://httr2.r-lib.org/articles/wrapping-apis.html); policy on security. Pattern: `gptr_redact(x, secrets = gptr_known_secrets())` on every error, log line, transcript and history-document write. The test "HTTP errors are classed and never leak the key" passes (VERIFIED).

### E. Internet

**C-38 Fail gracefully, with classed errors.** Rule: internet failures produce an informative message and never a check WARNING or ERROR. Examples, tests and vignettes must not depend on the network. Source: policy line 105; Ivan Krylov 2024 (https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010846.html); R-pkg-devel 2021 (https://stat.ethz.ch/pipermail/r-package-devel/2021q3/007408.html). Pattern: provider functions `stop()` with class `c("gptr_http_error", "gptr_error")`; users expect errors. Nothing in examples, tests or vignettes calls the network unguarded. When an example must, use:
```r
#' @examplesIf interactive() && nzchar(Sys.getenv("OPENAI_API_KEY"))
#' tryCatch(gptr("Say hi", model = "openai/gpt-5-nano"),
#'          gptr_http_error = function(e) message("Provider unavailable: ", conditionMessage(e)))
```

**C-39 Minimal use of web resources.** Rule: keep web use to a minimum and never trigger 429 or 403. Source: policy line 138. Pattern: the model catalog is refreshed only by `gptr_models(refresh = TRUE)`. There are no calls at load time. Retries use exponential backoff and honour `Retry-After` (`httr2::req_retry()`).

### F. Processes, ports, cores, time

**C-40 Two cores maximum.** Rule: never more than 2 threads or cores. Source: policy line 101; Cookbook "Using more than 2 Cores"; R-ints `_R_CHECK_LIMIT_CORES_`. Pattern (VERIFIED):
```r
gptr_max_workers <- function() {
  n <- as.integer(getOption("gptr.max_workers", 2L)); if (is.na(n) || n < 1L) n <- 1L
  if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) n <- min(n, 2L)
  n
}
```
Tests set `OMP_THREAD_LIMIT = "2"`. If data.table is used in tests, call `data.table::setDTthreads(2)`, restored with `withr::defer`. HTTP concurrency through curl multi or httr2 `req_perform_parallel()` is I/O, not CPU, so it is fine. Cap it (`max_active`) anyway, at 2 in tests.

**C-41 Processes are started correctly and always cleaned up.** Rule: kill anything you start. Examples must leave no connections open. Source: policy line 124; R-ints `_R_CHECK_CONNECTIONS_LEFT_OPEN_`; experiment 5.4. Pattern (VERIFIED):
```r
p <- processx::process$new(gptr_rscript(), c("--vanilla", "-e", code),
       stdout = "|", stderr = "|", cleanup = TRUE, cleanup_tree = TRUE,
       supervise = isTRUE(getOption("gptr.supervise", TRUE)))
# tests:    withr::defer(if (p$is_alive()) p$kill())
# examples: \dontshow{old <- options(gptr.supervise = FALSE)} ... \dontshow{options(old)}
# session end: reg.finalizer(the, kill_all_workers, onexit = TRUE); .onUnload -> kill_all_workers()
```

**C-42 No browsers, viewers or Shiny in examples and tests unless closed.** Rule: see title. Source: policy line 124; Cookbook "Structuring of Examples". Pattern: artifacts (REQ-39) run `shiny::runApp(..., launch.browser = FALSE)` in a background process (D-17). Examples use `@examplesIf interactive()`. Tests use `shiny::testServer()` or skip. `utils::browseURL()` is called only when `gptr_is_interactive()`.

**C-43 Ports.** Rule: no fixed ports; handle unavailable ports; stop servers. Source: https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012559.html (Ivan Krylov; thread root 012557). Pattern:
```r
port <- httpuv::randomPort()
srv <- tryCatch(httpuv::startServer("127.0.0.1", port, app),
  error = function(e) cli::cli_abort("Could not open a local port.", parent = e,
                                     class = "gptr_port_unavailable"))
on.exit(httpuv::stopServer(srv), add = TRUE)   # or keep in a registry that is cleaned up
```
Tests use `webfakes::local_app_process()`, which picks a random port and stops the process automatically (VERIFIED).

**C-44 Close connections in examples.** Rule: a fatal error otherwise. Source: R-ints 2195. Pattern: `on.exit(close(con), add = TRUE)` for every `file()`, `url()`, `gzcon()`, `rawConnection()` and every `httr2` streaming response (`close(resp)` after `req_perform_connection()`, as in the webfakes test). Do not use `processx` supervision in examples (C-41).

**C-45 Timing budget.** Rule: examples take a few seconds each at most; tests about a minute; the whole check under 10 minutes. Windows is about 2x slower. Source: policy line 103; R Packages 15.4.2; Cookbook "Overall Checktime"; https://stat.ethz.ch/pipermail/r-package-devel/2023q1/008962.html (thread root; Ligges's confirmation 008965). Pattern: aim for each example under 0.5 s (skeleton maximum 0.136 s), the test suite under 30 s, and the full check on win-builder under 3 min. Use `skip_on_cran()` for anything slow (for example, starting 2 workers and running a sub-agent end to end).

**C-46 Interactive-only functions.** Rule: they must not block in batch mode and must be wrapped in examples. Source: Cookbook; WRE line 2308. Pattern: `gptr()` without a prompt errors in batch mode (VERIFIED test). Examples use `@examplesIf interactive()`. Wrap `readline()`, `askYesNo()` and `menu()` in internal functions such as `gptr_readline()` so tests can mock them with `local_mocked_bindings()`.

### G. Documentation

**C-47 Rd completeness.** Rule: `\value` for every exported function, examples for exported functions, no commented-out example code, `\dontrun{}` only when the code cannot run. Source: Cookbook "Missing \value-tags"; extrachecks. Pattern:
```r
#' @return A `gptr_result` object ... (or: No return value, called for side effects.)
#' @examplesIf interactive() && nzchar(Sys.getenv("ANTHROPIC_API_KEY"))
#' gptr("Summarise mtcars", model = "anthropic/claude-sonnet")
#' @examples
#' gptr("Summarise mtcars", provider = gptr_provider_fake("32 rows."))  # always runs
```
Every exported function should have at least one fake-provider example that always runs. The Cookbook says reviewers object when *all* examples are wrapped in `\donttest{}`/`\dontrun{}`.

**C-48 Rd hygiene.** Rule: anchored cross-references to other packages (`[processx::process]`); `\samp{}` for localhost; no non-ASCII in Rd without an encoding. Source: R-ints `_R_CHECK_XREFS_NOTE_MISSING_PACKAGE_ANCHORS_`; URL_checks. Pattern: roxygen markdown links with the package prefix, as the skeleton passed.

**C-49 Vignettes.** Rule: no network or keys at check time; `VignetteBuilder: knitr`; knitr and rmarkdown in Suggests. Source: rOpenSci precompute post; WRE 1.4. Pattern (VERIFIED): `vignettes/gptr.Rmd.orig` plus `vignettes/precompute.R`, both ignored at build, and a shipped `vignettes/gptr.Rmd`. Live output is recorded by the maintainer with real keys and re-knitted before each release.

### H. Tests

**C-50 Test architecture.** Rule: see 2.9. Source: R Packages 13–15; testthat. Pattern (VERIFIED, full files in 5.3):
- `setup.R`: redirect `R_user_dir`, blank the API keys unless `GPTR_LIVE_TESTS=true`, `gptr.interactive = FALSE`, `gptr.quiet = TRUE`, `warn = 1`, `OMP_THREAD_LIMIT=2`.
- Layers: fake provider, then `httr2::local_mocked_responses`, then fixtures with pure parsers, then webfakes loopback, then snapshots, then live tests.
- Do not assert timings, exact external messages, or the absence of warnings. Use `expect_error(class = )`.
- Keep `Config/testthat/parallel` off. Its "2-CPU default" is overridden by `getOption("Ncpus")` or `TESTTHAT_CPUS` whenever the check machine sets them (testthat 3.3.2 `default_num_cpus()`).

### I. Release process

**C-51 Pre-submission matrix.** Rule: `R CMD check --as-cran` on R-devel is mandatory; check on Windows (win-builder); cover at least two platforms. Source: policy lines 176–182; checklist. Pattern:
```r
devtools::document(); urlchecker::url_check(); spelling::spell_check_package()
devtools::check(args = "--as-cran", env_vars = c(`_R_CHECK_THINGS_IN_OTHER_DIRS_` = "true"))
# NB: env_vars *replaces* devtools' default c(NOT_CRAN = "true"), so skip_on_cran() tests are
# skipped here (a CRAN-like run); add NOT_CRAN = "true" to the vector to run them too.
devtools::check_win_devel()                     # same machine as CRAN r-devel-windows
rhub::rhub_check(platforms = c("windows", "macos-arm64", "linux", "nosuggests",
                               "donttest", "ubuntu-next", "ubuntu-release"))
# plus GitHub Actions matrix (3.8) green, incl. oldrel-4 and no-suggests
```

**C-52 Reverse dependencies and breaking changes.** Rule: notify revdep maintainers at least 2 weeks ahead; no deprecation cycle required. Source: policy lines 184, 216; R Packages 22.5. Pattern: re-run `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` on submission day and record the result in cran-comments.md.

**C-53 Submission etiquette.** Rule: one pending submission at a time; resubmissions use the "Optional comment" field and a bumped version; wait 48 h for the check page; updates every 1–2 months. Source: policy lines 194–210. Pattern: use `devtools::submit_cran()`, which writes `CRAN-SUBMISSION` (ignored at build), then confirm the email link.

**C-54 Names and trademarks.** Rule: trademarks must be respected; package names are permanent. Source: policy lines 41–47, 71. Pattern: the package name `gptr` cannot change. Avoid trademarks in the Title. In the docs, refer to 'OpenAI', 'Claude' and so on as names of third-party services, and imply no endorsement. (UNCERTAIN: OpenAI's brand guidelines restrict "GPT" in product names. This is a legal and brand risk, not a CRAN rule; the maintainer should be aware.)

**C-55 Compiled code (only if the REQ-01 Rcpp exception is used).** Rule: never terminate R (no `exit`/`abort`/`std::terminate`); register native routines; keep compiler diagnostics on; comply with sanitizer and rchk checks. Source: policy lines 112, 134; R-ints `_R_CHECK_NATIVE_ROUTINE_REGISTRATION_`. Pattern: `Rcpp::stop()` for errors, `// [[Rcpp::export]]` plus `Rcpp::compileAttributes()`, rhub `clang-asan`/`valgrind`/`rchk` before release, and a pure-R reference implementation used in tests (REQ-01).

### J. Cross-platform (details in section 6)

**C-56 Paths.** Rule: portable file names and path handling. Source: WRE 1.1 and 1.6. Pattern: use `normalizePath(path, winslash = "/", mustWork = FALSE)` before comparing paths. Resolve `~` with `path.expand()`; on Windows it is R's Documents directory, not `%USERPROFILE%`. When reading other harnesses' configs (Claude Code or Codex MCP settings, REQ-30), look in `Sys.getenv("USERPROFILE")` on Windows. btw documents the same distinction (`$W/cranpkgs/btw/R/utils.R` lines 155–167).

**C-57 Line endings.** Rule: text-mode connections on Windows translate LF to CRLF. Source: `?connections` (base R docs, VERIFIED). Pattern: the edit tool detects the file's EOL and writes through binary connections:
```r
gptr_read_text <- function(path) {
  raw <- readBin(path, "raw", file.size(path))
  txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
  eol <- if (grepl("\r\n", txt, fixed = TRUE)) "\r\n" else "\n"
  list(lines = strsplit(txt, "\r?\n")[[1]], eol = eol, final_newline = grepl("\n$", txt))
}
```

**C-58 Atomic writes.** Rule: `file.rename()` cannot cross file systems, so a temp file must be in the same directory. Source: `?file.rename` (VERIFIED). Pattern:
```r
gptr_write_atomic <- function(path, text, eol = "\n") {
  tmp <- tempfile(".gptr-", tmpdir = dirname(path))
  con <- file(tmp, "wb"); on.exit(close(con), add = TRUE)
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = eol), eol))), con)
  close(con); on.exit()
  if (!file.rename(tmp, path)) { unlink(tmp); cli::cli_abort("Could not write {.path {path}}.") }
  invisible(path)
}
```

### API and data structures implied by the checklist

| Element | Specification |
|---|---|
| Options | `gptr.quiet` (FALSE), `gptr.interactive` (NULL = `rlang::is_interactive()`), `gptr.user_dir` (NULL), `gptr.max_workers` (2), `gptr.supervise` (TRUE), `gptr.permission` ("ask" interactive, "plan" otherwise), `gptr.context` ("default"/"none"), `gptr.r_tool.restore` (TRUE in batch) |
| Environment variables | `GPTR_LIVE_TESTS` (tests only), provider keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `TYPESAFE_API_KEY`), `R_USER_*_DIR` (base R) |
| Condition classes | `gptr_error` (base); `gptr_http_error`, `gptr_no_key`, `gptr_permission_denied`, `gptr_port_unavailable`, `gptr_missing_cli`, `gptr_timeout` |
| Exported compliance-relevant functions | `gptr_init(path, overwrite)`, `gptr_workspace(path)`, `gptr_user_dir(which)`, `gptr_cache_prune(max_age_days, max_mb)`, `gptr_config_set(...)`, `gptr_eval(code, envir, permission)`, `gptr_provider_fake(responses)`, `gptr_worker_start()`/`gptr_worker_stop()` (or internal behind sub-agents) |
| Internal helpers | `gptr_is_interactive()`, `gptr_confirm()`, `gptr_readline()`, `gptr_inform()`, `gptr_redact()`, `gptr_max_workers()`, `gptr_rscript()`, `gptr_write_atomic()`, `kill_all_workers()` |

---

## 5. Verified R prototypes

Everything below was executed on R 4.4.3 (macOS arm64) with `Rscript --vanilla` /
`/usr/local/bin/R`. The skeleton lives in `$W/pkg/gptr/`, build outputs in `$W/build/`,
and probe experiments in `$W/probe/`. The private library `$S/rlib` supplied webfakes 1.4.0 and
spelling 2.3.2; nothing was installed into the user library.

### 5.1 Commands

```sh
cd $W/pkg/gptr && Rscript --vanilla -e 'roxygen2::roxygenise()'
Rscript --vanilla -e 'pkgload::load_all(quiet=TRUE); setwd("vignettes"); knitr::knit("gptr.Rmd.orig", output = "gptr.Rmd", quiet = TRUE)'
cd $W/build && R_LIBS=$S/rlib R CMD build ../pkg/gptr
R_LIBS=$S/rlib _R_CHECK_THINGS_IN_OTHER_DIRS_=true _R_CHECK_SYSTEM_CLOCK_=FALSE \
  _R_CHECK_RD_VALIDATE_RD2HTML_=false R CMD check --as-cran gptr_1.0.0.tar.gz
```

Two environment overrides reflect this machine, not the package:
- `_R_CHECK_SYSTEM_CLOCK_=FALSE`: without it, the first run gave "checking for future file timestamps ... NOTE unable to verify current time", because the external clock service was unreachable.
- `_R_CHECK_RD_VALIDATE_RD2HTML_=false`: `/usr/bin/tidy` here is Apple's 2006 build, which rejects the `<main>` element and produced about 100 spurious HTML-validation lines. CRAN has a modern HTML Tidy.

LaTeX was available, so the PDF manual was built and checked ("checking PDF version of manual ... OK").

### 5.2 Skeleton source (the compliance-relevant files, verbatim)

`R/utils.R`:
```r
gptr_inform <- function(msg, .envir = parent.frame()) {
  if (isTRUE(getOption("gptr.quiet", FALSE))) {
    return(invisible(NULL))
  }
  cli::cli_inform(msg, .envir = .envir)
}

gptr_is_interactive <- function() {
  opt <- getOption("gptr.interactive")
  if (!is.null(opt)) {
    return(isTRUE(opt))
  }
  rlang::is_interactive()
}

gptr_confirm <- function(question, default = FALSE) {
  if (!gptr_is_interactive()) {
    return(default)
  }
  isTRUE(utils::askYesNo(question, default = default))
}

gptr_max_workers <- function() {
  n <- getOption("gptr.max_workers", 2L)
  n <- as.integer(n)
  if (is.na(n) || n < 1L) {
    n <- 1L
  }
  if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
    n <- min(n, 2L)
  }
  n
}

gptr_redact <- function(x, secrets = character()) {
  secrets <- secrets[nzchar(secrets)]
  for (s in secrets) {
    x <- gsub(s, "<redacted>", x, fixed = TRUE)
  }
  x
}
```

`R/workspace.R` (roxygen blocks shortened; full file at `$W/pkg/gptr/R/workspace.R`):
```r
#' @examples
#' proj <- file.path(tempdir(), "gptr-example")
#' dir.create(proj)
#' ws <- gptr_init(proj)
#' list.files(ws, recursive = TRUE, all.files = TRUE)
#' unlink(proj, recursive = TRUE)
gptr_init <- function(path, overwrite = FALSE) {
  if (missing(path)) {
    if (!gptr_is_interactive()) {
      cli::cli_abort(c(
        "{.arg path} must be supplied in non-interactive sessions.",
        "i" = "gptr only writes to directories that you name explicitly."
      ))
    }
    path <- getwd()
    ok <- gptr_confirm(sprintf("Create a '.gptr' workspace in %s?", path))
    if (!ok) {
      gptr_inform("No workspace created.")
      return(invisible(NULL))
    }
  }
  if (!dir.exists(path)) {
    cli::cli_abort("Directory {.path {path}} does not exist.")
  }
  ws <- file.path(path, ".gptr")
  for (d in file.path(ws, c("", "sessions", "skills"))) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  }
  vig <- file.path(ws, "vignette.Rmd")
  if (!file.exists(vig) || overwrite) {
    writeLines(workspace_template(), vig, useBytes = TRUE)
  }
  gptr_inform("Workspace ready at {.path {ws}}.")
  invisible(ws)
}

gptr_workspace <- function(path = getwd()) {
  ws <- file.path(path, ".gptr")
  if (dir.exists(ws)) ws else NULL
}

gptr_user_dir <- function(which = c("config", "data", "cache")) {
  which <- match.arg(which)
  root <- getOption("gptr.user_dir")
  if (!is.null(root)) {
    return(file.path(root, which))
  }
  tools::R_user_dir("gptr", which = which)
}

gptr_cache_prune <- function(max_age_days = 30) {
  dir <- gptr_user_dir("cache")
  if (!dir.exists(dir)) {
    return(invisible(character()))
  }
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  age <- difftime(Sys.time(), file.mtime(files), units = "days")
  old <- files[age > max_age_days]
  unlink(old)
  invisible(old)
}
```

`R/eval.R`: the evaluation engine. It runs in the caller's environment only after permission, and captures output, messages, warnings and errors.
```r
gptr_eval <- function(code, envir = parent.frame(),
                      permission = c("ask", "auto", "deny")) {
  permission <- match.arg(permission)
  code <- paste(code, collapse = "\n")
  allowed <- switch(permission,
    auto = TRUE,
    deny = FALSE,
    ask = gptr_confirm(paste0("Run this R code?\n", code, "\n"))
  )
  res <- list(value = NULL, output = character(), messages = character(),
              warnings = character(), error = NULL, ran = FALSE)
  class(res) <- "gptr_eval_result"
  if (!allowed) {
    res$error <- "Permission denied: code was not run."
    return(res)
  }
  exprs <- tryCatch(parse(text = code, keep.source = FALSE),
                    error = function(e) e)
  if (inherits(exprs, "error")) {
    res$error <- conditionMessage(exprs)
    return(res)
  }
  res$ran <- TRUE
  out <- utils::capture.output(
    value <- withCallingHandlers(
      tryCatch({
        v <- NULL
        for (e in exprs) v <- eval(e, envir = envir)
        v
      }, error = function(e) {
        res$error <<- conditionMessage(e)
        NULL
      }),
      message = function(m) {
        res$messages <<- c(res$messages, conditionMessage(m))
        invokeRestart("muffleMessage")
      },
      warning = function(w) {
        res$warnings <<- c(res$warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  )
  res$value <- value
  res$output <- out
  res
}
```

`R/http.R`: the provider call. Classed errors, key redaction, and untrusted text passed as a variable.
```r
gptr_complete <- function(prompt, model, base_url = "https://api.openai.com/v1",
                          key = Sys.getenv("OPENAI_API_KEY")) {
  if (!nzchar(key)) {
    cli::cli_abort("No API key found. Set {.envvar OPENAI_API_KEY}.",
                   class = c("gptr_no_key", "gptr_error"))
  }
  req <- httr2::request(base_url)
  req <- httr2::req_url_path_append(req, "chat", "completions")
  req <- httr2::req_auth_bearer_token(req, key)
  req <- httr2::req_body_json(req, list(
    model = model, messages = list(list(role = "user", content = prompt))))
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) {
    detail <- gptr_redact(conditionMessage(e), key)
    cli::cli_abort(c("Could not reach {.url {base_url}}.", "x" = "{detail}"),
                   class = c("gptr_http_error", "gptr_error"), call = NULL)
  })
  if (httr2::resp_status(resp) >= 400) {
    body <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    detail <- gptr_redact(body, key)
    cli::cli_abort(c("HTTP {httr2::resp_status(resp)} from provider.", "x" = "{detail}"),
                   class = c("gptr_http_error", "gptr_error"), call = NULL)
  }
  out <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  out$choices[[1]]$message$content
}
```
It also contains `gptr_sse_parse(lines)`, a pure SSE parser, and `R/fake.R`:
`gptr_provider_fake(responses)`, a closure over an environment that replays the canned
replies, plus `gptr_ask()`.

`R/worker.R`: process hygiene.
```r
#' @examples
#' \dontshow{
#' old <- options(gptr.supervise = FALSE)
#' }
#' w <- gptr_worker_start("cat('ready\\n'); Sys.sleep(30)")
#' w$is_alive()
#' gptr_worker_stop(w)
#' w$is_alive()
#' \dontshow{
#' options(old)
#' }
gptr_worker_start <- function(expr_text) {
  if (length(the$workers) >= gptr_max_workers()) {
    cli::cli_abort("Too many workers running (limit {gptr_max_workers()}).")
  }
  exe <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  rscript <- file.path(R.home("bin"), exe)
  p <- processx::process$new(
    rscript, c("--vanilla", "-e", expr_text),
    stdout = "|", stderr = "|", cleanup = TRUE, cleanup_tree = TRUE,
    supervise = isTRUE(getOption("gptr.supervise", TRUE))
  )
  the$workers[[as.character(p$get_pid())]] <- p
  p
}
gptr_worker_stop <- function(worker) {
  pid <- as.character(worker$get_pid())
  if (worker$is_alive()) worker$kill()
  the$workers[[pid]] <- NULL
  invisible(TRUE)
}
the <- new.env(parent = emptyenv())
the$workers <- list()
kill_all_workers <- function(env = the) {
  for (w in env$workers) try(w$kill(), silent = TRUE)
  env$workers <- list()
  invisible(NULL)
}
.onLoad <- function(libname, pkgname) {
  reg.finalizer(the, kill_all_workers, onexit = TRUE)
  invisible(NULL)
}
.onUnload <- function(libpath) kill_all_workers()
```

`R/gptr.R`: interactive versus programmatic.
```r
#' @examples
#' gptr("Summarise mtcars in one line.",
#'      provider = gptr_provider_fake("32 cars, 11 variables."))
#' @examplesIf interactive()
#' gptr(provider = gptr_provider_fake("Hi!"))
gptr <- function(prompt, provider) {
  if (missing(prompt)) {
    if (!gptr_is_interactive()) {
      cli::cli_abort("The interactive chat needs an interactive R session.")
    }
    repeat {
      line <- readline("gptr> ")
      if (line %in% c("", "/exit", "/quit")) break
      reply <- gptr_ask(provider, line)
      cli::cli_verbatim(reply)   # NEVER cli::cli_text(reply): see the correction note below
    }
    return(invisible(NULL))
  }
  gptr_ask(provider, prompt)
}
```
**Correction (verifier).** The skeleton file on disk (`$W/pkg/gptr/R/gptr.R`) still contains
`cli::cli_text(gptr_ask(provider, line))`. That passes the model's reply to cli as a format string,
which is exactly the C-36 injection bug. A reply containing
`{(function() {cat('EVALUATED\n'); 'x'})()}` printed "EVALUATED": the code ran in the user's
session. `R CMD check` cannot catch it, because the REPL only runs interactively. The corrected
line above has been tested: `cli::cli_verbatim(reply)` and `cli::cli_text("{reply}")` both print
the braces literally. The skeleton also calls `readline()` directly, where C-46 asks for a mockable
`gptr_readline()` wrapper.
The generated Rd for `@examplesIf` (VERIFIED in `man/gptr.Rd`):
```
\dontshow{if (interactive()) withAutoprint(\{ # examplesIf}
gptr(provider = gptr_provider_fake("Hi!"))
\dontshow{\}) # examplesIf}
```

### 5.3 Tests (verbatim)

`tests/testthat/setup.R`:
```r
user_root <- withr::local_tempdir("gptr-user-", .local_envir = teardown_env())
withr::local_envvar(
  R_USER_CONFIG_DIR = file.path(user_root, "config"),
  R_USER_DATA_DIR = file.path(user_root, "data"),
  R_USER_CACHE_DIR = file.path(user_root, "cache"),
  OMP_THREAD_LIMIT = "2",
  .local_envir = teardown_env()
)
if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
  withr::local_envvar(
    OPENAI_API_KEY = "", ANTHROPIC_API_KEY = "", GEMINI_API_KEY = "",
    TYPESAFE_API_KEY = "",
    .local_envir = teardown_env()
  )
}
withr::local_options(
  gptr.interactive = FALSE, gptr.quiet = TRUE, warn = 1,
  .local_envir = teardown_env()
)
```

`tests/testthat/helper.R`:
```r
skip_if_no_key <- function(var) {
  skip_if(!nzchar(Sys.getenv(var)), paste(var, "not set"))
}
fixture_path <- function(...) test_path("fixtures", ...)
```

`test-workspace.R`:
```r
test_that("gptr_init() refuses to guess a path when nobody can consent", {
  expect_error(gptr_init(), "must be supplied")
})
test_that("gptr_init() writes only inside the directory it is given", {
  proj <- withr::local_tempdir()
  ws <- gptr_init(proj)
  expect_true(dir.exists(ws))
  expect_true(file.exists(file.path(ws, "vignette.Rmd")))
  expect_identical(normalizePath(gptr_workspace(proj)), normalizePath(ws))
})
test_that("interactive consent: 'no' writes nothing, 'yes' writes", {
  proj <- withr::local_tempdir()
  withr::local_dir(proj)
  withr::local_options(gptr.interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(...) FALSE)
  expect_null(gptr_init())
  expect_false(dir.exists(file.path(proj, ".gptr")))
  local_mocked_bindings(gptr_confirm = function(...) TRUE)
  gptr_init()
  expect_true(dir.exists(file.path(proj, ".gptr")))
})
test_that("global state goes to the (redirected) R_user_dir", {
  expect_true(startsWith(
    normalizePath(gptr_user_dir("cache"), mustWork = FALSE),
    normalizePath(Sys.getenv("R_USER_CACHE_DIR"), mustWork = FALSE)
  ))
  withr::local_options(gptr.user_dir = "/somewhere")
  expect_identical(gptr_user_dir("config"), file.path("/somewhere", "config"))
})
test_that("R CMD check exposes _R_CHECK_PACKAGE_NAME_ and workers are capped", {
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  withr::local_options(gptr.max_workers = 8L)
  expect_identical(gptr_max_workers(), 2L)
})
```

`test-eval.R`:
```r
test_that("code runs in the supplied environment, never in globalenv", {
  env <- new.env()
  before <- ls(globalenv(), all.names = TRUE)
  res <- gptr_eval("zz_gptr_test <- 41 + 1; zz_gptr_test", envir = env,
                   permission = "auto")
  expect_true(res$ran)
  expect_identical(res$value, 42)
  expect_identical(env$zz_gptr_test, 42)
  expect_identical(ls(globalenv(), all.names = TRUE), before)
})
test_that("default permission refuses to run code when nobody can consent", {
  res <- gptr_eval("stop('should not run')", envir = new.env())
  expect_false(res$ran)
  expect_match(res$error, "Permission denied")
})
test_that("messages, warnings, errors and output are captured", {
  res <- gptr_eval(c("print(1:3)", "message('m')", "warning('w')", "stop('e')"),
                   envir = new.env(), permission = "auto")
  expect_identical(res$output, "[1] 1 2 3")
  expect_identical(res$messages, "m\n")
  expect_identical(res$warnings, "w")
  expect_identical(res$error, "e")
})
test_that("print method output is stable", {
  res <- gptr_eval("1 + 1", envir = new.env(), permission = "auto")
  expect_snapshot(print(res))
})
```

`test-http-mock.R`:
```r
test_that("provider call works against a mocked httr2 response", {
  fixture <- readLines(fixture_path("openai-chat.json"), warn = FALSE)
  httr2::local_mocked_responses(function(req) {
    expect_identical(req$url, "https://api.example.test/v1/chat/completions")
    httr2::response(
      status_code = 200,
      headers = list(`Content-Type` = "application/json"),
      body = charToRaw(paste(fixture, collapse = "\n"))
    )
  }, env = environment())
  out <- gptr_complete("hi", model = "gpt-fixture",
                       base_url = "https://api.example.test/v1",
                       key = "sk-test-not-a-real-key")
  expect_identical(out, "Hello from the fixture.")
})
test_that("HTTP errors are classed and never leak the key", {
  key <- "sk-secret-123"
  httr2::local_mocked_responses(list(
    httr2::response(status_code = 401, body = charToRaw(
      paste0('{"error":"bad key ', key, '"}')))
  ))
  err <- expect_error(
    gptr_complete("hi", model = "m", base_url = "https://api.example.test/v1",
                  key = key),
    class = "gptr_http_error"
  )
  expect_false(grepl(key, conditionMessage(err), fixed = TRUE))
})
test_that("missing key gives an informative classed error, no network", {
  expect_error(gptr_complete("hi", model = "m", key = ""), class = "gptr_no_key")
})
test_that("SSE parser handles a recorded stream", {
  ev <- gptr_sse_parse(readLines(fixture_path("stream.sse"), warn = FALSE))
  expect_length(ev, 3)
  expect_identical(ev[[1]]$event, "delta")
  expect_identical(ev[[3]]$data, "[DONE]")
})
```

`test-webfakes.R` (real loopback streaming):
```r
test_that("streaming works end to end against a local fake server", {
  skip_if_not_installed("webfakes")
  skip_if_not_installed("callr") # webfakes runs the app in a callr session
  app <- webfakes::new_app()
  app$post("/v1/chat/completions", function(req, res) {
    res$set_type("text/event-stream")
    res$send(paste0(
      "event: delta\ndata: {\"t\":\"Hel\"}\n\n",
      "event: delta\ndata: {\"t\":\"lo\"}\n\n",
      "data: [DONE]\n\n"
    ))
  })
  web <- webfakes::local_app_process(app)
  req <- httr2::request(web$url("/v1/chat/completions"))
  req <- httr2::req_body_json(req, list(stream = TRUE))
  resp <- httr2::req_perform_connection(req)
  withr::defer(close(resp))
  events <- list()
  repeat {
    ev <- httr2::resp_stream_sse(resp)
    if (is.null(ev)) break
    events[[length(events) + 1L]] <- ev
  }
  expect_length(events, 3)
  expect_identical(events[[2]]$data, "{\"t\":\"lo\"}")
})
```

`test-worker.R`:
```r
test_that("background workers are started from R.home() and cleaned up", {
  w <- gptr_worker_start("cat('ready\\n'); Sys.sleep(60)")
  withr::defer(if (w$is_alive()) w$kill())
  expect_true(w$is_alive())
  out <- character()
  deadline <- Sys.time() + 20
  while (!length(out) && Sys.time() < deadline) {
    w$poll_io(1000)
    out <- c(out, w$read_output_lines())
  }
  expect_match(out, "ready")
  gptr_worker_stop(w)
  expect_false(w$is_alive())
})
test_that("callr background sessions are cleaned up too", {
  skip_if_not_installed("callr")
  rs <- callr::r_session$new()
  withr::defer(rs$close())
  expect_identical(rs$run(function() 1 + 1), 2)
})
```

`test-live.R`:
```r
test_that("live OpenAI round trip", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "live tests off")
  skip_if_no_key("OPENAI_API_KEY")
  out <- gptr_complete("Reply with the single word: pong", model = "gpt-5-nano")
  expect_type(out, "character")
})
```

`test-gptr.R` checks the fake provider sequence and that the interactive chat errors in batch mode.

Fixtures: `fixtures/openai-chat.json` is an OpenAI chat-completion object with content "Hello from the fixture.". `fixtures/stream.sse` contains two `event: delta` blocks and a `data: [DONE]` block, each ending in a blank line.

### 5.4 Observed results

**Unit tests (devtools)**, `NOT_CRAN=true Rscript --vanilla -e 'devtools::test(reporter = "summary")'`:
```
eval: ...........
gptr: ....
http-mock: ........
live: S
webfakes: ..
worker: ....
workspace: ..........
== Skipped ==
1. live OpenAI round trip ('test-live.R:7:3') - Reason: live tests off
```

**First `--as-cran` run.** 1 ERROR and 3 NOTEs (`$W/build/check-as-cran.log`):
- title case (fixed by changing the Title);
- future timestamps (environment; see 5.1);
- HTML Tidy (environment; see 5.1);
- **ERROR**: "connections left open: .../supervisor_stdin... (fifo) .../supervisor_stdout... (fifo)" from the `gptr_worker_start` example, which used `supervise = TRUE`.

**The bug found and fixed on the way.** The first test run crashed with *"Could not evaluate cli `{}` expression: `"error":"bad key ...`"*, because an HTTP error body was passed as a cli format string (C-36).

**Final `--as-cran` run** (`$W/build/check-final.log`, R 4.4.3). Every step OK (the log has 54 "... OK" lines plus the tests step), including:
```
* checking CRAN incoming feasibility ... [6s/21s] Note_to_CRAN_maintainers
Maintainer: 'Wanjun Gu <wanjun.gu@ucsf.edu>'
* checking package dependencies ... OK
* checking for hidden files and directories ... OK
* checking whether startup messages can be suppressed ... OK
* checking R code for possible problems ... OK
* checking examples ... OK
* checking tests ...
  Running 'testthat.R'
 OK
* checking re-building of vignette outputs ... OK
* checking PDF version of manual ... OK
* checking for non-standard things in the check directory ... OK
* checking for detritus in the temp directory ... OK
* checking for new files in some other directories ... OK
* DONE

Status: OK
```
- Test output inside the check: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 38 ]`, with `* On CRAN (2): 'test-eval.R:28:1', 'test-live.R:5:3'` (the snapshot and live tests are skipped on CRAN), in 2.256 s elapsed.
- The largest example took 0.136 s (`gptr_init`); the worker example took 0.043 s.
- The tarball `gptr_1.0.0.tar.gz` is 20,379 bytes.

**Without webfakes** (noSuggests-like; `_R_CHECK_FORCE_SUGGESTS_=false`, `$W/build/nosugg/check-nosugg.log`): `Status: 1 NOTE`, which is *"Package suggested but not available for checking: 'webfakes'"*. Tests: `SKIP 3 | PASS 36`, with `{webfakes} is not installed (1)`.

**processx supervisor experiment** (executed):
```r
p <- processx::process$new(file.path(R.home("bin"),"Rscript"), c("--vanilla","-e","Sys.sleep(30)"), supervise=TRUE)
showConnections()      # 2 rows: .../supervisor_stdin... fifo, .../supervisor_stdout... fifo
p$kill(); showConnections()      # still 2 rows
processx::supervisor_kill(); showConnections()   # empty
p2 <- processx::process$new(..., stdout="|", stderr="|", cleanup=TRUE); showConnections()  # empty
```

### 5.5 Other verified snippets

**Reverse dependencies** (executed):
```r
options(repos = c(CRAN = "https://cloud.r-project.org")); db <- available.packages()
db["gptr","Version"]                                                          # "0.7.0"
tools::package_dependencies("gptr", db = db, reverse = TRUE, which = "all")   # $gptr character(0)
tools::package_dependencies("gptr", db = db, reverse = TRUE, which = "most", recursive = "strong")  # character(0)
nrow(db)                                                                      # 25106
```

**Dependency closure** (executed; results in 2.6).

**Syntax floor** (executed on R 4.4.3):
`mtcars |> subset(cyl == 4, select = mpg) |> nrow()` gives 11, and `c(a = 1) |> list(v = _)` works (it needs R >= 4.2).

**`R_user_dir` redirection** (executed):
```r
tools::R_user_dir("gptr","config")   # /Users/wanjun/Library/Preferences/org.R-project.R/R/gptr
Sys.setenv(R_USER_CONFIG_DIR="/tmp/xx"); tools::R_user_dir("gptr","config")  # /tmp/xx/R/gptr
```

### 5.6 Probe-package experiments (`$W/probe/probe13`)

**Setup.**
- 21 Imports.
- Code containing `assign("probe_value", x, envir = globalenv())`, `eval(parse(text = code), envir = envir)`, and a function writing to `tools::R_user_dir("probe13","cache")` that is called from a test.
- A top-level `.Rprofile`, and later a `.gptr/` directory.

The check ran with `HOME=$W/probe/home`, so nothing reached the real home directory.

**Results** (VERIFIED, `$W/probe/probe-check.log`):
- `.Rprofile` was not in the tarball.
- NOTEs:
  - "Imports includes 21 non-default packages";
  - "Namespaces in Imports field not imported from";
  - "Found the following assignments to the global environment ... assign("probe_value", x, envir = globalenv())";
  - "checking for new files in some other directories ... Found the following files/directories: '~/Library' ... '~/Library/Caches/org.R-project.R/R/probe13/probe.txt'".
- `eval(parse(text=))` was **not** flagged.
- With `.gptr/` present, the tarball contained `probe13/.gptr/...` and the check gave "Found the following hidden files and directories: .gptr".

**ASCII check** (VERIFIED): `tools:::.check_package_ASCII_code()` returns `"R/a.R"` for a file containing `"café ✔"`. The same string written with `\u00e9 \u2714` escapes is accepted, and is a UTF-8 string when evaluated.

### 5.7 Not executed / not verifiable here

- `R CMD check` on R-devel 4.7.0, on Windows, and on Linux. This must be done with win-builder, rhub and GitHub Actions before submission.
- The real aspell. I emulated it with hunspell and CRAN's exact ignore regexes.
- The noSuggests check with a true Depends-only library. Every package here is in the system library, so I approximated it by removing webfakes.
- A live API call. None was allowed or needed.

---

## 6. CRAN and cross-platform considerations (Windows emphasis)

1. **Encoding.** With R >= 4.2, R on recent Windows (Windows 10 version 1903 or later, Windows Server 2022) uses UTF-8 as its native encoding, with the UCRT runtime (R NEWS 4.2.0). Declaring `R (>= 4.2)` means gptr does not have to handle Windows code pages on those systems. Older Windows builds still use a code page, so do not rely on `l10n_info()$UTF-8` being TRUE. Still write code files in ASCII with `\u` escapes, and use `enc2utf8()` or `Encoding(x) <- "UTF-8"` on bytes read with `readBin()`. For console symbols, let cli fall back to ASCII: a non-UTF-8 console prints `<U+00E9>`. This session printed exactly that, because `Rscript --vanilla` ran with charset ASCII.
2. **Processes.**
   - There is no `fork`, so `parallel::mclapply()` cannot parallelise; use processx or callr workers (D-12).
   - Start R with `file.path(R.home("bin"), "Rscript.exe")`; `R.home("bin")` is the architecture-specific `bin` directory. (LIKELY: from R's layout, not tested on Windows here.)
   - `p$kill()` maps to `TerminateProcess`. Use `cleanup_tree = TRUE` to catch grandchildren (Windows needs `ps`, which is already a processx dependency).
   - npm-installed CLIs (`claude`, `codex`) are `.cmd` shims on Windows. Resolve them with `Sys.which()` and test that processx can launch them; you may need `processx::run("cmd.exe", c("/c", shim, args))` with careful quoting. **UNCERTAIN**, and it belongs to tracks 07/08.
3. **File system.**
   - Text-mode connections translate LF to CRLF on Windows (`?connections`, VERIFIED), so the edit, write and history-document tools use binary I/O and preserve the file's own EOL (C-57).
   - `file.rename()` works only within a volume (`?file.rename`), so atomic writes put the temp file next to the target (C-58).
   - A file that another process holds open cannot be deleted or renamed on Windows. Close every connection before `unlink()` and retry briefly.
   - Reserved names (`con`, `prn`, `aux`, `nul`, `com1`–`com9`, `lpt1`–`lpt9`, with any extension) and the characters `"*:/<>?\|` are invalid (WRE line 317). Sanitise session, skill and artifact file names.
   - Windows and macOS file systems are case-insensitive: `Skill.md` and `skill.md` collide.
   - Short 8.3 temp paths (`C:/Users/RUNNER~1/...`) differ from long ones, so normalise before comparing (WRE line 2414).
4. **Home directory.** On Windows, R's `~` is usually `Documents`, while other tools use `%USERPROFILE%`. MCP and CLI config discovery (REQ-30) must look in `Sys.getenv("USERPROFILE")` (see btw's comment at `$W/cranpkgs/btw/R/utils.R` lines 155–159). `R_user_dir()` uses `%APPDATA%` and `%LOCALAPPDATA%`.
5. **Permissions.** `Sys.chmod(path, "600")` has no real effect on Windows, so credential files rely on the user-profile ACL. Document this, and prefer `keyring`.
6. **Console and interrupts.** Rgui, Rterm, RStudio, Positron and Windows Terminal differ:
   - `readline()` in Rgui opens no terminal line editor;
   - ANSI colour support varies, so rely on `cli::num_ansi_colors()`;
   - Esc and Ctrl+C semantics differ.

   Test the interrupt and steer paths (REQ-38) by hand on Windows; they cannot be automated on CRAN.
7. **Check machine and timing.**
   - CRAN r-devel-windows is the same machine as win-builder r-devel: Windows Server 2022, 2x AMD EPYC 7443 (VERIFIED on the win-builder page, and confirmed by Uwe Ligges in 2023).
   - Windows totals are roughly 2x Linux (gptr 0.7.0: 53 s against 23.9 s).
   - Windows reports elapsed time only, and the CPU/elapsed ratio checks for tests and vignettes do not run there (R-ints lines 2045, 2059–2063).
   - `_R_CHECK_BASHISMS_` is not run on Windows.
8. **Toolchain.** gptr is pure R, so no Rtools is needed. If the Rcpp exception is used, win-builder uses Rtools45 for R-release and R-devel (win-builder page), and CRAN builds the binaries itself; maintainers do not upload binaries (policy, "Binary packages").
9. **macOS.** `R_user_dir` uses `~/Library/...` (VERIFIED). CRAN macOS arm64 checks are the fastest (12 s for gptr 0.7.0). Use the macOS builder when an M1 issue appears.
10. **Linux.** `R_user_dir` follows XDG. There may be no display: guard browser opening with `gptr_is_interactive()`. Clipboard access needs `xclip`/`xsel`, which the policy counts as external software (R Packages 15.4.5), so keep clipboard features interactive-only.

---

## 7. Risks, pitfalls, open questions

**Risks**
1. **Human-review variance (UNCERTAIN).** Automated checks can be made clean. A reviewer who looks at the update could still object, for example to evaluation at top level reaching `globalenv()`, or to the history-document writer. Mitigations: the strict defaults (C-17, C-18, C-24, C-32) and the explicit cran-comments.md (3.5). If CRAN pushes back, fall back to btw's model: the `r` tool evaluates in `new.env(parent = envir)` by default, with an explicit `envir = globalenv()` opt-in. That conflicts with REQ-22, so it is a last resort.
2. **Model-generated code is arbitrary code.** A user in `auto` mode can have their files deleted. This is outside CRAN policy but is a reputational and security risk. Document "not a security boundary" (as btw and mcptools do); ship the advisory classifier (D-11); make `auto` opt-in per session.
3. **Data egress (policy line 126).** Automatic context in system prompts (object listings, file contents) may count as "sending information about the R session" if it is not made obvious. C-34 mitigates this; keep the default context minimal.
4. **Trademarks.** The name "gptr" contains "GPT" (UNCERTAIN; it is a brand issue, not a CRAN issue). CRAN names are permanent.
5. **Dependency churn.** httr2 is evolving: 1.2.0 removed `with_mock()`, and 1.3.0 changed cache-file hashing through rlang 1.3.0. Pin `httr2 (>= 1.2.0)` and run CI against the development version occasionally.
6. **Archival threats through CRAN "additional issues".** noSuggests (which runs with `_R_CHECK_DEPENDS_ONLY_=true`), donttest, the other-directories check and sanitizers run after publication. rsurvstat was given a correction deadline of 2026-08-21 for a single donttest NOTE (the thread was posted 2026-07-27; the date of CRAN's email is not stated). Keep CI mirroring these (rhub `nosuggests`, `donttest`).

**Pitfalls observed in this research (each VERIFIED)**
- A cli or glue format string built from untrusted text is evaluated as code (C-36).
- processx supervisor fifos cause the fatal "connections left open" error in examples (C-41).
- `tools::toTitleCase()` lowercases "That", which trips the title check.
- `cli_abort()` needs `rlang`, which cli only suggests.
- A `.gptr/` directory left in a package source goes into the tarball.
- Tests writing to `R_user_dir` are caught by the other-directories check.
- webfakes needs callr at run time; guard both.
- `expect_snapshot()` silently skips on CRAN, so snapshot-only coverage is invisible there.

**Open questions for the architecture**
1. The exact first-use disclosure UX for provider data egress (C-34): a once-per-provider acknowledgement stored in the config directory, or only documentation?
2. Should the non-interactive default permission be `plan` (read-only) or `deny` for the `r` tool? This skeleton used "ask", which becomes "deny" in batch. Replaying a recorded script-as-history (D-08) needs a sanctioned way to run recorded code in batch. Proposal: a recorded block in a document the user sources counts as the user's own code, so run it; only *new* model code requires permission.
3. Which exact Imports? The union of tracks 01, 03, 05 and 06 gives cli, curl, httr2, jsonlite, openssl, processx, rlang and yaml, plus optional callr, R6 and S7 (D-02 prefers S3). The final list must stay at or below about 12 non-base packages to leave headroom under 20.
4. On Windows, can `processx` launch the npm `.cmd` shims for `claude` and `codex` directly? This needs testing on a Windows runner (tracks 07/08).
5. Whether to offer a knitr chunk engine (D-27). If yes, it must follow the same no-write and no-network rules while `R CMD check` builds the vignettes, so the engine must honour a "replay only" mode.
6. Where the System One answer cache lives before `.gptr/` exists (digest open question for track 04). Answer from this track: `gptr_user_dir("cache")` is legal, size-capped and pruned, and is redirected in tests (C-19, C-21).

---

## 8. Sources

**CRAN and R core**
- CRAN Repository Policy, rev 6875: https://cran.r-project.org/web/packages/policies.html (fetched 2026-09-29; local copy `$W/web/policies.txt`)
- CRAN submission checklist: https://cran.r-project.org/web/packages/submission_checklist.html
- CRAN URL checks: https://cran.r-project.org/web/packages/URL_checks.html
- Writing R Extensions (R-devel 4.7.0, 2026-09-28): https://cran.r-project.org/doc/manuals/r-devel/R-exts.html (1.1.1 DESCRIPTION, 1.1.2 Licensing, 1.1.3 dependencies, 1.1.3.1 Suggested packages, 1.6 portable packages, 2.1.1 `\donttest`)
- R Internals, "Tools" (R 4.6.1): https://cran.r-project.org/doc/manuals/r-release/R-ints.html
- CRAN package page and checks for gptr: https://CRAN.R-project.org/package=gptr, https://cran.r-project.org/web/checks/check_results_gptr.html
- CRAN check pages: https://cran.r-project.org/web/checks/check_results_aisdk.html, `_btw.html`, `_ellmer.html`, `_mcptools.html`, `_chattr.html`
- CRAN archives: https://cran.r-project.org/src/contrib/Archive/gptr/, `/aisdk/`, `/btw/`
- win-builder: https://win-builder.r-project.org/ ; macOS builder: https://mac.r-project.org/macbuilder/submit.html
- R versions API: https://api.r-hub.io/rversions/resolve/oldrel/4, https://api.r-hub.io/rversions/resolve/release
- Local R sources read (R 4.4.3): `tools:::.check_package_depends`, `tools:::.check_packages`, `tools:::.check_package_code_assign_to_globalenv`, `tools:::.check_package_CRAN_incoming`, `tools:::get_exclude_patterns`, `tools::R_user_dir`, `utils::news()`, `?connections`, `?file.rename`, `testthat:::default_num_cpus`, `cli::cli_abort`

**Community guidance**
- CRAN Cookbook: https://contributor.r-project.org/cran-cookbook/ (code_issues.html, description_issues.html, docs_issues.html, general_issues.html)
- DavisVaughan/extrachecks: https://github.com/DavisVaughan/extrachecks
- R Packages (2e): https://r-pkgs.org/ (description.html, dependencies-in-practice.html, testing-basics.html, testing-design.html, testing-advanced.html, vignettes.html, lifecycle.html, release.html, R-CMD-check.html)
- tidyverse R version support: https://www.tidyverse.org/blog/2019/04/r-version-support/
- rOpenSci, precomputing vignettes: https://ropensci.org/blog/2019/12/08/precompute-vignettes/
- R-hub blog, persistent config: https://blog.r-hub.io/2020/03/12/user-preferences/
- rhub v2: https://r-hub.github.io/rhub/articles/rhubv2.html ; platform list https://raw.githubusercontent.com/r-hub/actions/v1/setup/platforms.json
- r-lib/actions examples: https://github.com/r-lib/actions/tree/v2-branch/examples (check-standard.yaml, check-full.yaml, check-no-suggests.yaml)
- httr2 mocking: https://httr2.r-lib.org/reference/with_mocked_responses.html ; NEWS https://httr2.r-lib.org/news/index.html ; wrapping APIs https://httr2.r-lib.org/articles/wrapping-apis.html
- webfakes: https://webfakes.r-lib.org/ ; vcr: https://docs.ropensci.org/vcr/ ; testthat skip: https://testthat.r-lib.org/reference/skip.html ; snapshots https://testthat.r-lib.org/articles/snapshotting.html
- ellmer `tool_reject()`: https://ellmer.tidyverse.org/reference/tool_reject.html ; btw `btw_tool_run_r()`: https://posit-dev.github.io/btw/reference/btw_tool_run_r.html

**R-package-devel threads** (archive https://stat.ethz.ch/pipermail/r-package-devel/). Where a person is quoted, the link goes to that person's message; the thread root is given in brackets. Links were corrected by the verifier, because the original list pointed to thread roots written by the question askers.
- User home dir and prompting (Maechler, 2019): https://stat.ethz.ch/pipermail/r-package-devel/2019q4/004535.html [root 004532]
- Writing to the user's config directory (2022): https://stat.ethz.ch/pipermail/r-package-devel/2022q4/008612.html [root]
- Config file / R_user_dir / read-only library (Krylov 009945, Urbanek 2023): https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009947.html [root 009944]
- API client failing on authentication (Krylov, 2023): https://stat.ethz.ch/pipermail/r-package-devel/2023q4/009966.html [root 009965]
- Detritus, R_user_dir, classed internet errors (Krylov, 2024): https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010846.html [root 010844]
- callr and the 2-core policy (Bengtsson, 2024): https://stat.ethz.ch/pipermail/r-package-devel/2024q2/010819.html [root 010818]
- New files in other directories, rsurvstat (2026-07; Krylov's reply): https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012486.html [root 012484]
- Fixed ports in examples, shinylight (2026-09; Krylov): https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012559.html [root 012557]
- Agentic skills in `inst/` (2026-07; Chirico): https://stat.ethz.ch/pipermail/r-package-devel/2026q3/012437.html [root 012436]
- Internet resources and errors (2021): https://stat.ethz.ch/pipermail/r-package-devel/2021q3/007408.html [root]
- API keys and tests (2020): https://stat.ethz.ch/pipermail/r-package-devel/2020q3/005964.html ; (2022): https://stat.ethz.ch/pipermail/r-package-devel/2022q2/008133.html (not re-checked by the verifier)
- More than 2 cores (2023; Krylov 009532, maintainer's fix 009538): https://stat.ethz.ch/pipermail/r-package-devel/2023q3/009531.html [root]
- Example timings, win-builder equals CRAN r-devel-windows (2023; Krylov 008964, Ligges "Yes"): https://stat.ethz.ch/pipermail/r-package-devel/2023q1/008965.html [root 008962]
- Native pipe and the minimum R version (2024; Murdoch/Bengtsson 010386–010390): https://stat.ethz.ch/pipermail/r-package-devel/2024q1/010385.html [root]
- MIT LICENSE stub, openaistream (2024; Krylov): https://stat.ethz.ch/pipermail/r-package-devel/2024q1/010357.html [root 010356]
- Major changes and deprecation (2022; Murdoch 007772): https://stat.ethz.ch/pipermail/r-package-devel/2022q1/007771.html [root] ; breaking changes with revdeps (2021): https://stat.ethz.ch/pipermail/r-package-devel/2021q1/006687.html (not re-checked by the verifier)

**Local evidence**
- Precedent package sources: `$W/cranpkgs/{aisdk,btw,ellmer,mcptools,chattr,gander,chores,gptstudio,vitals,webfakes,httptest2,shinychat,tidyprompt,askgpt}` (file and line references inline)
- Pi licence: `$S/pi/LICENSE` (MIT, Copyright (c) 2025 Mario Zechner)
- Skeleton package: `$W/pkg/gptr/`; tarball `$W/build/gptr_1.0.0.tar.gz`; logs `$W/build/check-as-cran.log` (first run), `check-as-cran-2.log`, `check-final.log`, `nosugg/check-nosugg.log`
- Probe experiments: `$W/probe/probe13/`, `$W/probe/probe-check.log`, `$W/probe/ascii/`
- Tools: `$W/tools/rpd.py`, `thread.py`, `url.sh` (archive search), `spell_desc.R` (aspell emulation), `rnews.R`

---

## Verification log

Adversarial fact-check, 2026-09-29. The verifier re-ran every experiment independently:
R 4.4.3 on macOS arm64, `Rscript --vanilla`, with the private library `$S/rlib` for webfakes
1.4.0, spelling and hunspell. Scratch files are in `$S/work/verify-13/`: the re-built skeleton
is in `pkg/` and `build/`, the fresh probe package is in `probe/`, the non-ASCII probes are in
`ascii/` and `ascii2/`, the supervised-example variant is in `supv/`, and the mailing-list
messages are in `rpd/`. Live sources were fetched on 2026-09-29.
Verdicts: **confirmed**, **corrected** (the report was edited in place), **unverifiable**.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | CRAN policy is rev 6875. The source-package rules are as paraphrased in 2.2 (tempdir only, interactive exception, `R_user_dir` small and managed, global env, external software, session info, TLS, 429/403, 2 cores, graceful internet failure, 5 MB/10 MB, no binaries, FOSS must not require restrictive software, two platforms, "1–2 months", 48 h, 2 weeks for revdeps, email change). No AI/LLM wording | confirmed | live https://cran.r-project.org/web/packages/policies.html |
| 2 | `--as-cran` sets `_R_CHECK_EXCESSIVE_IMPORTS_=20`, and more than 20 non-base Imports gives the NOTE (text reproduced) | confirmed | `deparse(tools:::.check_packages)`, `.check_package_depends`, live R-ints 4.6.1, fresh probe with 21 Imports |
| 3 | The Depends NOTE fires at "more than 5 non-base Depends" | **corrected** | The R source removes only R, base, datasets, grDevices, graphics, methods, utils and stats, so `tools` or `parallel` in Depends count. Exec. summary 5, 2.6 and 3.6 edited |
| 4 | `cli::cli_abort()` calls `rlang::abort()`, and rlang is only in cli's Suggests | confirmed | cli 3.6.6 `body(cli::cli_abort)`, `packageDescription("cli")`, CRAN db |
| 5 | Title is 49 characters and survives `toTitleCase()`; "That" becomes "that" | confirmed | executed |
| 6 | aspell filter: en_US + en_GB + en_stats, same three ignore regexes | confirmed | `deparse(tools:::.check_package_CRAN_incoming)` |
| 7 | `_R_CHECK_CRAN_INCOMING_USE_ASPELL_` is "TRUE on CRAN (R source)" | **corrected** | The R source default is `"FALSE"` and R-ints does not document it. Downgraded to LIKELY (2.5, 3.6) |
| 8 | Description has 161 words; the hunspell emulation flags nothing and flags "LLM" when "(LLM)" is added | confirmed | re-ran `$W/tools/spell_desc.R` |
| 9 | Version floors: raw strings and `R_user_dir` 4.0.0; `\|>` and `\(x)` 4.1.0; `_` placeholder 4.2.0; `_$` 4.3.0; `%\|\|%` 4.4.0; UTF-8/UCRT on Windows 4.2.0 | confirmed, with UTF-8 **corrected** | `utils::news()` in R 4.4.3. UTF-8 is native only on Windows 10 1903+ / Server 2022, so the qualifier was added in exec. summary 4, 2.7 and 6.1 |
| 10 | rversions: release 4.6.1, oldrel/1 4.5.3, oldrel/4 4.2.3, devel 4.7.0 | confirmed | live api.r-hub.io |
| 11 | Every hard dependency plus the test Suggests needs at most R 4.1, so `R (>= 4.2)` is installable | confirmed (new check) | CRAN `available.packages()` closure of 49 packages |
| 12 | gptr: no reverse dependencies (`which="all"` and `"most"`/strong); db has 25,106 packages; 0.7.0 published 2025-04-05; archive 0.5.0 2024-05-06, 0.6.0 2024-05-07; maintainer `wanjun.gu@ucsf.edu`; 13/13 flavors OK; 12 s / 23.91 s / 53 s | confirmed | CRAN db, package page, archive, check page |
| 13 | Current CRAN versions listed in 2.6 (httr2 1.3.0 … urlchecker 2.0.0, with their R floors) | confirmed | `available.packages()` |
| 14 | Dependency closure: 16 packages → 19 (adds callr, otel, yaml); ellmer alone 26 | confirmed | executed |
| 15 | httr2 NEWS: 1.2.0 removed `with_mock`/`local_mock`, made `req_perform_connection()` mockable and soft-deprecated `req_perform_stream()`; 1.2.3 added `resp$request` on mocks and faster SSE; 1.3.0 moved the OAuth cache to `R_user_dir` and re-hashed via rlang 1.3.0 | confirmed | live CRAN httr2 NEWS |
| 16 | Precedent versions, dates and statuses: btw 1.5.0, aisdk 1.4.12, ellmer 0.5.0, mcptools 1.0.3, chattr 0.3.1, gander 0.2.0, chores 0.3.1, all 13/13 OK; Windows totals aisdk 339–453, btw 328–345, ellmer 346–430 (347 on devel), mcptools 97–109 s; aisdk 1.4.10, 1.4.11 and 1.4.12 released within 5 days | confirmed | live CRAN pages, check pages and archive |
| 17 | Precedent source citations (btw run/write/md/cli/utils/helpers, aisdk `eval(parse(), globalenv())`, `.aisdk/sessions`, ellmer `on_tool_request`/`tool_reject`/menu example/prices cache/vcr with 53 cassettes, mcptools socket note and OAuth cache, chattr `insertText`) | confirmed | `$W/cranpkgs/*` tarball sources at the cited lines |
| 18 | golem and mirai ship skills in `inst/` | confirmed; URL **corrected** | GitHub API for `cran/mirai` and `cran/golem`. The statement is Chirico's message 012437, not 012436 |
| 19 | processx `supervise=TRUE` leaves 2 fifo connections open after `p$kill()`; `supervisor_kill()` clears them; an unsupervised process with pipes opens none | confirmed | executed (processx 3.8.6) |
| 20 | A supervised worker example makes `--as-cran` fail with "connections left open … supervisor_stdin/stdout (fifo)" | confirmed | re-ran the check on a variant (`supv/supv.log`) |
| 21 | Untrusted text passed as a cli format string is evaluated ("Could not evaluate cli `{}` expression") | confirmed | executed |
| 22 | The skeleton REPL in 5.2 follows C-36 | **corrected** | `cli::cli_text(gptr_ask(provider, line))` evaluated an injected `{...}` (it printed "EVALUATED"). Fixed in 5.2 to `cli::cli_verbatim(reply)`, with a note. The skeleton file on disk was not modified |
| 23 | `_R_CHECK_PACKAGE_NAME_` is set by R CMD check and visible to tests | confirmed, with a nuance **added** | `.check_packages` source: set in `check_pkg()`, temporarily unset while `inst/doc` vignette code runs (3.6 edited) |
| 24 | testthat parallel defaults to 2 CPUs | confirmed, with the caveat **added** | testthat 3.3.2 `default_num_cpus()`: `Ncpus` then `TESTTHAT_CPUS` override it (exec. summary 12, C-50, 3.6) |
| 25 | `R_user_dir` precedence (R_USER_*_DIR, then XDG_*, then the platform default) and the Windows, macOS and Linux paths | confirmed | `print(tools::R_user_dir)`, R 4.4.3 |
| 26 | `.Rprofile` is dropped by `R CMD build`; `.gptr/` is kept and gives the hidden-files NOTE | confirmed | `tools:::.hidden_file_exclusions`; fresh probe tarball and check |
| 27 | The globalenv check flags only `assign()` with `envir`/`pos` resolving to globalenv; `eval(parse(text=), envir)` is not flagged | confirmed | `tools:::.check_package_code_assign_to_globalenv` source; fresh probe |
| 28 | `_R_CHECK_THINGS_IN_OTHER_DIRS_` gives a NOTE listing `~/Library/Caches/org.R-project.R/R/<pkg>/...` for a test writing to `R_user_dir` | confirmed; monitored-directory list **corrected** | Fresh probe with isolated HOME. Per R-ints, `~` is watched at top level, plus `/tmp`, `/dev/shm`, and `~/.cache` and `~/.local/share` recursively (Linux `~/.config` is not), and the variable is not in the `--as-cran` set |
| 29 | ASCII check flags a literal UTF-8 string and accepts the `\u` escapes | confirmed; severity **added** | executed. It is a WARNING under `--as-cran` even with `Encoding: UTF-8` |
| 30 | R-ints values: R_ON_PATH, CONNECTIONS_LEFT_OPEN (examples only, fatal), LIMIT_CORES (>2 children), SCREEN_DEVICE=stop, BROWSER_NONINTERACTIVE, DONTTEST_EXAMPLES (on with `--as-cran`), URLS_SHOW_301, SUGGESTS_ONLY, FORCE_SUGGESTS=FALSE for incoming, TIMINGS=10, EXAMPLE_TIMING_THRESHOLD=5, test/vignette CPU ratios not on Windows, BASHISMS not on Windows, R_DEPENDS=warn, THINGS_IN_TEMP_DIR/CHECK_DIR. The cited line numbers match `$W/web/rints.txt` | confirmed | live R-ints (R 4.6.1) |
| 31 | The noSuggests check uses `_R_CHECK_DEPENDS_ONLY_=true` | confirmed | https://www.stats.ox.ac.uk/pub/bdr/noSuggests/README.txt |
| 32 | WRE (R-devel 2026-09-28): Authors@R required for CRAN, ORCID/ROR strongly encouraged; titles may be truncated at 65 characters; reserved file names; 100-byte paths; external commands conditional on `Sys.which()` and checks must pass without them; launch R/Rscript via `R_HOME`; testing guidance; `interactive() && !getOption("quiet", FALSE)` since R 4.6.0 | confirmed | live R-exts (r-devel) |
| 33 | `?connections`: CRLF translation happens in text mode only on Windows; `?file.rename`: no renames across file systems | confirmed | R 4.4.3 help |
| 34 | r-lib/actions check-standard, check-full and check-no-suggests contents (checkout@v6, matrix, build_args, `cache: false`, hard deps plus testthat/knitr/rmarkdown) | confirmed | live raw.githubusercontent.com v2-branch. Also confirmed: setup-r exports `NOT_CRAN=true`, and check-r-package defaults to `args = c("--no-manual","--as-cran")` |
| 35 | rhub v2 platform names; `rhub_setup`, `rhub_check` and `rc_submit` are exported (rhub 2.0.1) | confirmed | live platforms.json; cran/rhub NAMESPACE |
| 36 | win-builder page (2026-04-29): oldrel 4.5.3, release 4.6.0, devel to be 4.7.0; Windows Server 2022, 2x AMD EPYC 7443; Rtools45; results in about half an hour | confirmed | live win-builder page |
| 37 | URL statuses: typesafe.ai and the GitHub URLs 200; pkgdown site 404; the Anthropic and OpenAI docs 301 | confirmed | curl |
| 38 | URL_checks: `\samp{}` for localhost; 60 s connection timeout | confirmed | live CRAN URL_checks page |
| 39 | Cookbook items (no default writes, 2.5 CPU ratio, `warn=-1`, `installed.packages`, `.GlobalEnv`, seed, installing software, title case, single quotes, MIT LICENSE stub) and extrachecks items | confirmed | live Cookbook pages; github.com/DavisVaughan/extrachecks |
| 40 | R Packages 15.4 (`skip_on_cran`/`NOT_CRAN`, about 1 min, zero tolerance for flakiness, snapshots skipped on CRAN, temp-only writes, clipboard) | confirmed | live r-pkgs.org/testing-advanced.html |
| 41 | The rOpenSci precompute post recommends `.Rbuildignore` entries | **corrected** | The post does not mention `.Rbuildignore`; the attribution was fixed in 2.12 |
| 42 | Mailing-list attributions (Maechler, Urbanek, Krylov ×6, Bengtsson, Ligges, Chirico, Murdoch) | content confirmed; URLs **corrected** | Every cited URL pointed to the thread root written by the asker. They now point to the quoted messages: 004535, 009945/009947, 009966, 010846, 010819, 012486, 012559, 012437, 008965, 010357, 007772 |
| 43 | rsurvstat got "a 3-week deadline" | **corrected** | The thread gives a deadline of 2026-08-21 and was posted 2026-07-27; the email date is unknown (7 Risks 6) |
| 44 | "Since 2026" CRAN reports other-dirs NOTEs | **corrected** | Unsupported. Rephrased to the rsurvstat evidence (exec. summary 7) |
| 45 | No R-package-devel thread reports an LLM/agent-based rejection | confirmed within `$W/web/rpd` (local copy, not re-downloaded) | grep over the 2019q1–2026q3 archive text |
| 46 | Skeleton: roxygenise changes nothing; the knitted vignette is identical; `--as-cran` gives Status OK | confirmed | Re-run. The only NOTE was an unrelated `/tmp/gw2.R` that another process created mid-check. Tests `[FAIL 0 WARN 0 SKIP 2 PASS 38]` in 2.06 s; largest example 0.105 s (the report's 0.136 s was a different run); tarball 20,356 bytes (report: 20,379) |
| 47 | Without webfakes: 1 NOTE "suggested but not available", `SKIP 3 PASS 36` | confirmed | re-run |
| 48 | `devtools::test()` summary output in 5.4 | confirmed | re-run |
| 49 | Section-4 snippets C-01, C-06, C-09, C-40, C-57, C-58 run as described (CRLF preserved, no connection leaked) | confirmed | executed |
| 50 | C-51 `devtools::check(env_vars = ...)` | caveat **added** | devtools 2.5.0 source: `env_vars` replaces the default `NOT_CRAN="true"` |
| 51 | Functions and arguments used in patterns (httr2 `local_mocked_responses(mock, env)`, `req_perform_parallel(max_active)`, `req_retry(after)`; `rlang::check_installed(reason)`; `withr::local_tempdir(pattern, .local_envir)`; `local_mocked_bindings`; processx `cleanup_tree`; `cli_verbatim`; `num_ansi_colors`; `devtools::submit_cran` writes CRAN-SUBMISSION; webfakes has callr in Suggests; `rlang::is_interactive()` is FALSE under knitr/testthat) | confirmed | installed namespaces and sources |
| 52 | `@examplesIf` Rd output; R CMD check parses NEWS.md and checks its URLs | confirmed | `man/gptr.Rd`; `tools:::url_db_from_package_sources` |
| 53 | Pi is MIT, "Copyright (c) 2025 Mario Zechner"; the repo LICENSE says YEAR 2023; ORCID `0000-0002-7342-7000`; `LICENSE.md` is in `.Rbuildignore` | confirmed | `$S/pi/LICENSE`; repository files |
| 54 | Cross-references "(5.5)" for check results and "full files in 5.5" | **corrected** | changed to 5.4 and 5.3 |

Not verifiable here (still UNCERTAIN or LIKELY in the text): whether a human CRAN reviewer will
accept the design; whether CRAN's incoming machines enable `_R_CHECK_CRAN_INCOMING_USE_ASPELL_`;
the Windows-only behaviours (Rscript.exe under `R.home("bin")`, `TerminateProcess`, npm `.cmd`
shims, `Sys.chmod`); a check on R-devel 4.7.0 or Windows; the real aspell (only the hunspell
emulation was run); the threads 2020q3/005964, 2022q2/008133 and 2021q1/006687; the tidyverse
five-version support window; and OpenAI's "GPT" brand guidelines.
