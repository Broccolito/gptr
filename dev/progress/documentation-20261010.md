# Documentation, repository review and access audit (2026-10-10)

## Delivered documentation

Expanded the five existing guides and added nine, with grouped pkgdown navigation:

| Group | Guides |
|---|---|
| Get started | getting-started, why-peter |
| Use Peter | language-models, system-one, interactive-console, configuration |
| Build workflows | script-as-history, teams-and-background, tools-and-artifacts |
| Extend Peter | skills-and-plugins, mcp, extending-gptr |
| Understand execution | execution-model, token-efficiency |

The guides cover functions, scripts, pipes and R control flow; typed Jev/Clef decisions;
provider/API/CLI/local-model setup; all 26 registered slash-command names and dynamic skill
commands; inline `!`/`!!` R; all 32 core settings and 90 supported runtime options; tools,
artifacts, templates, skills, plugins and MCP; teams, fan-outs and background execution;
recording, replay, workflow summaries and executable script drafts; budgets, caching and
compaction. The existing function reference covers all 63 exports, including shared Rd aliases.
Updated roxygen comments and generated reference pages where the usage needed clarification.

Examples use the offline fake provider where practical. Recipes requiring a real provider,
MCP server, interactive console or external program are explicitly not evaluated. The guides
distinguish genuine recorded execution from generated summaries/scripts, model probabilities
from empirical calibration, cooperative background execution from independent workers, and
configured settings from options that currently affect execution.

The README now directs users to the 1.0 development installation, runnable offline examples
and all guides. Native vignette links work both on the local site and in installed R help.
The generated site stays under ignored `docs/`; it was built and inspected locally, not deployed.

## Review and scope

Three independent subagents investigated architecture, repository evolution and PR #5, then
owned disjoint documentation lanes and reviewed the rendered guides. Fan-out was held at three
because the machine had high load and active swap. Local validation ran one job at a time with
single-thread limits; no new dependency was installed.

All 119 package R files parse to the same expressions as the starting main revision
`34b53cf2abbd6db65fe93f5347d139b370f767c5`, with source attributes removed. NAMESPACE is unchanged.
Package implementation, dependency declarations and tests are unchanged. Development release
tooling now derives the 14-guide manifest and grouped pkgdown navigation from one list.

The maintainer's initial DESCRIPTION change and untracked AGENTS.md were preserved and excluded
from these commits. The validation snapshot used the committed DESCRIPTION and roxygen2 7.3.3,
not the maintainer's independently changed tool metadata. Credentials, inventories and private
machine evidence were never included in the package, generated site or Git changes.

## Verification

Clean source snapshot: `dev/.validation/documentation-20261010/src`, made from committed main
plus this task's documentation files. It excludes `.secrets`, AGENTS.md and CLAUDE.md. Checks use
the configured `dev/.library`, `Rscript --vanilla`, isolated child directories, scrubbed
credentials and `GPTR_LIVE_TESTS=false`.

- roxygen generation: success, no unresolved documentation links; unchanged NAMESPACE.
- Precomputed the initial 13 vignettes and README, then the updated getting-started and new Why
  Peter guide: zero problems (all 14 guides).
- pkgdown manifest, Rd coverage/spelling, README and file checks: zero problems.
- Documentation/release checks: 71 passing assertions, zero failures, warnings or skips.
- All 58 reference example pages: zero problems; offline execution only.
- Complete pkgdown site: zero problems; 90 HTML pages.
- Final static site audit: 14/14 articles, 63/63 export aliases, all navigation groups,
  zero broken local links/fragments, no AGENTS/CLAUDE outputs.
- Browser inspection: homepage, article index and interactive guide render correctly;
  compact logo and local vignette navigation verified.
- `git diff --check`: clean, including normalized whitespace in generated output lines.

Logs: `dev/.validation/documentation-20261010/` (`document.log`, `precompute.log`, `audit.log`,
`examples.log`, `site.log`, `readme_home.log`, `html-audit.txt`). Pandoc emits a nonfatal
`--mathml` deprecation notice when building HTML. Testthat emits its existing package-build
version notice outside the test result. The full package suite and CRAN checks were not repeated
for this documentation-only change; the earlier main gate remains historical evidence.

## Repository and PR review

Fetched all remote branches, tags and PR heads. At the start, main and origin/main were identical
at the revision above. PR #3 is closed without merge (its legacy fix landed independently);
PR #4 merged the 1.0 foundation; PR #5 is open and was reviewed at
`a7662ec3acdc6809a15e99c06edf0e1637d4110c`.

The detailed PR review is [pr-review-20261010.md](pr-review-20261010.md). Its focused offline
suite passed 1,810 assertions; independent synthetic process/reset checks passed 35; changed
files had zero lint findings. The addition is useful, with authentication/design/toolchain
clarifications and manual onboarding validation still recommended. No merge, workflow approval,
GitHub comment or PR amendment was performed. The first-time-contributor workflow was awaiting
approval; it had not run any hosted jobs.

Main's most recent successful hosted run was 13/13 jobs on `240db69`. That evidence predates this
documentation work. New hosted results must be reported for their actual revision.

## Local model-access inventory

The current machine inventory and sanitized evidence are kept only in ignored
`dev/LOCAL_SETUP.md` and `dev/.validation/access-inventory-20261010/`. Read-only catalogs and
CLI authentication status were checked under the maintainer's explicit authorization, including
the confirmed UCSF Versa Azure destination. No inference requests, model downloads, persistent
provider configuration changes or credential copies were made. Catalog availability and signed-in
status do not establish model invocation permission, quota, billing, latency or tool support.

Next: review the PR findings with the maintainer before merge; separately authorize and plan
bounded live harness tests using the local inventory. Release, tags and CRAN submission remain
the maintainer's outstanding gates in HANDOFF.md.

## Maintainer logo follow-up

Moved all nine supplied files from `~/Downloads/gptr-logo` into `man/figures/`, with unchanged
bytes verified before and after the move. The original light/dark SVG and PNG variants, small
and double-resolution PNGs, and asset README are now versioned together; the Downloads folder
is gone. Removed the old green logo from `man/img/` and updated both README source and output.

The README uses a light fallback and a dark-mode picture source. Shared pkgdown branding uses
the canonical PNG assets for the navbar and page headers, with the native light/dark/auto switch
and paired syntax highlighting. New visitors start in light mode; existing reader preferences
are retained. Locally supplied SVG tab icons follow the selected theme. A pkgdown 2.2.1 head
template override changes only its favicon block, so no external favicon generator or image
conversion is needed. Logo source artwork is unmodified; package executable code is unchanged.

## Namesake and responsive design follow-up

Added the concise Why Peter guide with primary sources for Peter Naur's ALGOL 60/syntax
notation contribution and Peter Cathcart Wason's work with Jonathan Evans on dual processes
in reasoning. It distinguishes gptr's software roles from human cognition and does not
attribute the System 1/System 2 labels to Wason. README, getting-started and article navigation
link to it.

The light site uses a white background, dark text and derived blue links (6.25:1 light,
6.01:1 dark contrast against their page backgrounds), with paired a11y syntax themes.
Mobile headers stack a 72px portrait logo above the title; wider headers contain its float.
Tables and code scroll independently. Overflowing regions have labels and keyboard focus;
the compact menu has bounded vertical scrolling for short windows.

Browser layout checks passed for homepage, article index, configuration, Why Peter and peter()
reference at 320, 375, 768, 1024, 1440 and 1920 CSS pixels in both themes: 60 cases, zero
page-wide horizontal overflow, contained logos and no unfocusable overflow regions. A temporary
copy of configuration tested doubled root/body text at 320, 768 and 1440 pixels: zero page-wide
overflow. This is a text-scaling/reflow check, not a claim that browser zoom controls were tested.
The temporary page was removed. Native mobile menu/theme choices and theme persistence were
also inspected. The viewport override was reset and the local preview returned to light mode.

Final static audit: 90/90 pages include shared branding/theme controls; 14/14 articles,
63/63 export aliases and all local links, fragments and assets resolve. All nine supplied
logo files and copied site assets retain their original hashes. The final isolated documentation
suite passes 71 assertions with zero failures, warnings or skips; the full site rebuild succeeds.
Evidence adds responsive-matrix.json, text-scale-matrix.json and logo-light-preview.jpg under
ignored dev/.validation/documentation-20261010/.

Hosted run 38071919571 for documentation commit 42a89f6 was still in progress at the last check;
its completed benchmark, copy-safety, macOS-release and Ubuntu-oldrel-4 jobs had passed. These are
revision-specific observations, not a completed hosted gate for this follow-up.

## White background follow-up

At the maintainer's request, changed the light-mode bslib background to pure white (#ffffff).
The logo retains its original cream fill inside the artwork; no artwork bytes were changed.
The generated pkgdown configuration and shared Bootstrap CSS were refreshed. The layout and
explicit dark-mode colors remain the same. Verification uses rendered browser colors and the
existing generated-manifest check; no package implementation or dependency changes.

## In-memory compute across user entry points

The README source/rendered page, quickstart, language-model, execution, configuration and token
guides now explain reuse of already loaded R objects and intermediates across turns. The
interactive guide adds the same-session compute link. Function and egress help share the
same explanation, and the canonical asset README identifies the in-session harness.

The examples distinguish local R computation from bounded model descriptions and tool output.
Large-object illustrations do not allocate 4 GiB during documentation builds. Copy-on-modify,
worker boundaries, file-backed objects, optional checkpoint/cache serialization, model latency
and replay's need for original inputs are explicit. Replaced obsolete absolute statements that
objects are never copied or that context="none" disables every data transmission path.

Private-overlay roxygen and all 14 guide/README precomputes passed with zero documentation/file
problems (guide knitting 10.96s; total refresh 47.54s). The process-family profiler recorded
48 samples, peak RSS 574.8 MiB and zero sampling errors. Original source/DESCRIPTION SHA256
fingerprints stayed unchanged, and generated NAMESPACE stayed identical. Only reviewed
README, guide and help outputs were copied back; the working roxygen preference was preserved.

The interactive guide also documents proven native Unix !/!! R completion, preservation of
caller completers, client-owned GUI input and width refresh of newly streamed prose. Active
native-window resizing remains a separate live check. The site server and earlier browser
layout certificate predate these edits; a fresh site build and browser review are still pending.

## Living plan and cross-plan gate

Saved `dev/TESTING_PLAN.md` covers all14 guides/tables, 63 exports, provider/frontend combinations,
native/system-wide decisions, interactive UX, extensions, optional tools, memory/performance and
CRAN gates. A row is updated only from its revision-specific evidence; inherited tests, prepared
fixtures and inventory are distinguished from live behavior.

The required rerun after the latest plan edit completed successfully: 25 implementation plans,
1,446 indexed blocks, 4,389 definitions, 28,337 calls; 910 findings (821 info, 89 warnings,0errors).
Extraction/parse checked770 R blocks with0parse/style problems; single-worker lintr3.4 found no
lints. Three LONG notes are nested P17 skill examples. Read-only warning triage found recorded
ownership/signature/prototype/historical-contract exceptions and current implementation coverage
limitations; no new runtime blocker or numbered-plan change was required. The checker README's
74-warning count is historical. Output remains ignored under `dev/.validation/plan-20261010/final/`.

## Final in-memory prose and local website refresh

README now names in-memory compute explicitly. Seven remaining guides add specific boundaries:
System 1 derives compact decision inputs locally; recorded history requires the input objects;
inline teams read parent bindings while workers transfer selected inputs; Python conversion can
allocate; skills provide instructions; MCP arguments/results cross a serialized connection;
and ordinary R extension helpers run in the current process. Artifact wording now describes
versioned RDS snapshots and child-process loading, rather than promising an unconditional copy.
Independent review found no blocking source/output or memory/egress inaccuracies.

All 14 guides and README rendered in separate fresh offline R processes, using the installed
8d13b58 runtime without another package installation. Guide knitting took 11.029s; total
documentation/file validation 12.720s with zero problems. Profiling recorded 13 samples,
250.8 MiB peak family RSS and zero sampling errors. Source, user DESCRIPTION and NAMESPACE
fingerprints were preserved. Only affected generated outputs were copied; unchanged guide
snapshots were retained to avoid unrelated session-ID changes.

The static pkgdown site rebuilt in 85.557s (86 profile samples, peak family RSS 704.2 MiB,
zero sampling errors). It skipped package installation and reference-example execution; the
previous 58-page example gate remains separate. Its 90 HTML pages cover all 14 guides and
63 exports, with zero broken local links and eight hash-identical canonical image assets.
Agent instruction pages are excluded. The ignored docs/ artifact was refreshed with a retained
backup; an owned loopback preview serves the same output at http://127.0.0.1:8766/.

The build log retains pkgdown's missing-public-URL/custom-favicon sitrep advisories, two false
interactive @examplesIf conditions, and Pandoc 3.12 deprecated math-flag notices. These are
separate from the zero documentation/file/lint findings; do not describe this as a warning-free
full release gate. The installed RStudio bundle has Pandoc 3.10 for subsequent rendering checks.

Actual browser checks covered 18 viewport/theme cases: five light pages (home, introduction,
configuration, options reference and tools) plus the dark homepage at 320/768/1440px. All
reported no horizontal page overflow. Light background is rgb(255,255,255); dark is
rgb(28,30,34), with the corresponding canonical header/navbar logos. Desktop light/dark and
mobile screenshots were inspected. The light theme and normal viewport were restored. This
does not establish actual browser zoom or new doubled-text coverage; prior checks are historical.

The full cross-plan sequence after the first ledger update passed: 25 plans, 1,446 indexed
blocks, 4,389 definitions, 28,337 calls; 910 findings (821 info, 89 existing warnings, zero
errors), 770 parsed R blocks with zero parse/style problems and zero lintr findings. Logs
are retained in ignored plan-20261010/after-e094f22-memory/. A further required full sequence
follows the final plan status update; its result is appended below.

The final required sequence after that plan status update also passed: all four stages exited
zero; 25 plans, 1,446 indexed blocks, 4,389 definitions and 28,337 calls; 821 informational
findings, 89 existing consolidation warnings and zero errors. All 770 extracted R blocks had
zero parse/style problems, and single-worker lintr 3.4 reported no lints. Logs are retained
under ignored `dev/.validation/plan-20261010/after-e094f22-memory-final/`. These historical
cross-plan warnings are distinct from documentation/file/lint problems.

The rebuilt Why Peter article was also opened in the browser, checking both full names and
the distinction between software System 1/2 roles and historical terminology. Its ACM
announcement, revised ALGOL 60 report and Wason/Evans primary paper were reopened for content
review; this is not the full automated external URL scan. The homepage preview is restored
to light mode with its normal viewport. DESCRIPTION and NEWS already describe objects in
memory and were reviewed alongside the updated README and guides.

The required full consolidation sequence after the bounded-integration plan update passed
at the 2aeb9f0 checkpoint: index, extraction, parse and serial lint all exited zero. It
indexed 25 plans, 1,446 blocks, 4,389 definitions and 28,337 calls, with 821 informational
findings, 89 existing consolidation warnings and zero errors. All 770 extracted R blocks
had zero parse/style problems; three LONG notes are nested P17 examples. Single-worker
lintr 3.4.0 found no lints. Outputs remain ignored under
`dev/.validation/plan-20261010/after-7d7a39a-offline-fixtures/`.
