# Lane E: discovery, plugins, API documentation (#100 to #102), gptr 1.0.1

Branch `claude/fix-E`, cut from `04dca16a` (`claude/v1.0.1`). Findings: lanes.json key "E" (35
findings: 3 medium reviews, 1 medium live finding, 31 low). Decisions: D-330 to D-334.

## Fixed

| Finding | Commit | Test |
|---|---|---|
| #100 api documents crowd members, skills and tools out of `peter$search()` (medium) | d7a34222 | test-tool-namespace.R "peter$search() lists api documents only after ..."; the 1.0.0 "shiny apps" assertion is restored; D-330 |
| #100 `peter$help("gptr::", source = TRUE)` raised a base error | dcbc7d85 | test-tool-discovery.R (source help) |
| #100 api ranking depended on the collation locale | 9a4ba212 | test-tool-discovery.R "... same order under any collation" (en_US.UTF-8, skipped where the locale has no collation of its own) |
| #100 duplicated Rd alias readers, a needless `man/` branch; stale headers | a44cf917 | existing help tests; installed package checked by hand (66 exports both ways) |
| #100 tests miss the unqualified alias and the package conflict | a44cf917 | test-tool-discovery.R |
| #100 stale spec totals, stale estimate block, no decision (live finding: gptr setup not found on the Codex route, medium) | f97bc7e6 | test-tool-discovery.R (tool declaration), test-bench-context.R (pinned totals, 5% estimate), `dev/bench/tokens/run.R --check`; D-334 |
| #100 tools article shows the old `peter$help()` signature | 4d588cd2 | `precompute.R tools-and-artifacts` |
| #101 a bare plugin name blocked by a same-named folder (medium, two findings) | 7f40e419 | test-ext-plugins.R "a bare plugin name is not blocked ..."; D-331 |
| #101 installed Claude plugin on a marketplace root vanished (two findings) | 7f40e419 | test-ext-plugins.R "an installed Claude plugin whose install root is a marketplace ..." |
| #101 the marketplace diagnostic recorded 3 to 4 times, without the path (three findings, one live) | 78b5ea54 | test-ext-plugins.R "a configured marketplace path is recorded once, with its path, at every start"; D-332 |
| #101 `gptr_plugins()` flagged configured extension entries as skipped | 78b5ea54 | same test (a `.R` entry adds no footer count) |
| #101 marketplace message "pass that path in plugins = ." | 7f40e419 | existing "Choose an individual plugin directory" test |
| #101 tests miss the marketplace + `.mcp.json` and + `skills/` exceptions | 7f40e419 | test-ext-plugins.R |
| #101 and #102 `tailor-and-coach` shows gptr 1.0.0 | a73fcf94 | `precompute.R tailor-and-coach` (the three harness ids change with it) |
| #102 "WebP" (and, from #101, "unactivated") fail the spelling gate | af2f61ed | dev/release/tests/test-gptr-release.R Task 15 spelling check |
| #102 approval wording on control exports wrong in yolo and for the own session (two findings) | 9cec8eda | text only; D-333 |
| #102 `gptr_mcp_add()` omits the session-start connection of direct servers | 9d01cd02 | text only |
| #102 `gptr_env` wording weakened | 63b6ed69 | text only |
| #102 gptr_backend docs disagree with `gptr_check()`; build() omits `sign` and header pieces | fc2ef32c | text only |
| #102 MCP vignette omits the workspace prerequisite | 87e0314d | `precompute.R mcp` |
| #102 shiny-bslib skill promises the same URL | 705f59cc | test-artifact-app.R (skill test) |
| #102 audit ledger carries #101's evidence | dd57645b | none (dev record) |
| `?peter` says where api rows rank | ebbdf365 | none (text) |
| Verifier: a bare name whose folder is a marketplace clone got the generic "No plugin" error | 72759abe | test-ext-plugins.R "a bare plugin name is not blocked ..." (the marketplace explanation is chosen last, after every other place; D-331) |
| Verifier: fc2ef32c added "URL's" to `?gptr_adapter`, a new spelling hit | 04e675d3 | `spelling::spell_check_package()` no longer lists it |

## Deferred

- #101 live: console visibility of a failing configured entry. The diagnostic is now recorded once
  with its path, and `gptr_plugins()` shows the footer. A console warning at session start would
  change the reporting of every unresolved configured entry (contract 10.8: diagnostics, never
  errors) and add warnings to the tests that configure invalid entries; a maintainer decision.
  A `/plugins` command was never specified (03 section 6.17); a feature request.
- #101 live: the marketplace message does not name the plugin directories of its `marketplace.json`.
  The wording is now neutral for `plugins =` and the setting; naming candidates needs a manifest
  reader in the error path.
- #102: the permission sentence is not added to the other control exports (`gptr_trust()`,
  `gptr_fork()`, `gptr_init()`, `gptr_doc()`, `gptr_env()`, `gptr_login()`, `gptr_logout()`,
  `gptr_mcp_add()`, `gptr_mcp_remove()`); `?gptr_security` states the rule for all of them.
- #100 tests: the active-binding guard of `ns_gptr_fun()` and `source = TRUE` with another package
  stay untested (the namespace is locked, so a binding cannot be planted).
- #101 tests: `expect_identical(tail(diag$source, 1L), "user")` pins an implementation detail; left.
- Not in this lane: NEWS.md (coordinator). It needs bullets for: `peter$help()` `source =` and the
  `"gptr"` index and api rows in `peter$search()` (#100); a marketplace root in `plugins`, a plugin
  with nothing usable failing activation, the `gptr_plugins()` footer (#101); the r tool
  description now naming gptr setup (D-334).
- Other spelling hits of `spelling::spell_check_package()` predate this lane (blame: 7d85e1d0,
  f4110b47, b3d0044b, 045154bf, 8556ec6d on `claude/v1.0.1`) and belong to other lanes: `unvisited`
  (#98, gptr_options.Rd, gptr_rewind.Rd, teams-and-background.Rmd, NEWS.md), `entrantly` and
  `handoff` (#104), `deduplicates` and `judgements` (#106), `schemas` (NEWS.md).

## Rejected

- #100 version bump partial, #101 and #102 version consolidation: stale on `claude/v1.0.1`.
  `dev/release/check-files.R all` reports 0 problems; README.md:35, README.Rmd:34 and the
  cheat sheet (HTML and PDF) say 1.0.1, and cran-comments.md calls the release a patch update.
  Only the precomputed tailor-and-coach output was still 1.0.0 (fixed).
- `.github/workflows/Exact-tarball.yaml` pins `gptr_1.0.0.tar.gz`: it is the published tarball's
  name, pinned with that tarball's sha256 for `original_profiles_only`.
- #100 public Rd example `peter$help("gptr:::member_help", source = TRUE)` names an internal
  function: an internal name is the point of the example, and the tests pin it as well.

## Checks run

`isolated-check.R test` with filters tool-namespace, tool-discovery, ext-plugins, bench-context,
prompt, artifact-app, and a broad pass over the files that touch tools, plugins, skills, prompts,
bench, config, permissions, MCP, sessions, extensions, specs and docs: `[ FAIL 4 | WARN 3 | SKIP 4
| PASS 15135 ]`. The four failures (test-mcp-server.R:284, :288, :289 and test-session-budget.R:423)
are the bounded checkpoint scan reporting "automatic scan incomplete" under a machine load of 14 to
23; each fails the same way on a detached worktree of `04dca16a`, so none comes from this lane
(they belong to the checkpoint lane or to a load-tolerant timeout); `isolated-check.R lint` on every changed R and
test file (no lints); `isolated-check.R document` (only the expected Rd pages change);
`dev/release/check-docs.R` and `check-files.R all` (0 problems); `dev/bench/tokens/run.R --check`
after the baselines moved; `spelling::spell_check_package()` (only words that predate this lane remain);
an installed copy (`R CMD INSTALL` into a temporary library) answered search, help and source help
with 66 exports read from NAMESPACE.
