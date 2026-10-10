# Documentation, repository review and access audit (2026-10-10)

## Delivered documentation

Expanded the five existing guides and added eight, with grouped pkgdown navigation:

| Group | Guides |
|---|---|
| Get started | getting-started |
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
tooling now derives the 13-guide manifest and grouped pkgdown navigation from one list.

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
- Precomputed all 13 vignettes and README: zero problems.
- pkgdown manifest, Rd coverage/spelling, README and file checks: zero problems.
- Documentation/release checks: 71 passing assertions, zero failures, warnings or skips.
- All 58 reference example pages: zero problems; offline execution only.
- Complete pkgdown site: zero problems; 89 HTML pages.
- Final static site audit: 13/13 articles, 63/63 export aliases, all navigation groups,
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
