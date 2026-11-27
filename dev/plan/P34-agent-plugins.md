# P34 gptr Agent: one bridge in gptr for Biorouter, Claude Code and Codex (2026-11-26)

**Goal:** the bridge that lets an agent outside R work in a live R session moves from
`Broccolito/GptrAgent` into this repository. Biorouter downloads it from gptr's own releases,
and the same folder is a Claude Code plugin and a Codex plugin. An outside agent's work in a
served session is recorded like Peter's, so the user gets a runnable script of it. The
maintainer: "make and deposit that extension for GPTR to be hosted within GPTR ... Biorouter will
reference GPTR's extension and download it from the GPTR repository directly ... I also want you
to create the GPTR extension or plugin for Claude and Codex ... It works the same way ... make
sure that all of those extensions and plugins are comprehensively detailed in the documentation
as well as the README files ... easily set up and easily installed".

Decisions taken with the maintainer on 2026-11-26: version 1.3.0; record outside agents' calls;
no discovery-record nonce; Claude Code only (no Claude Desktop bundle); Broccolito/GptrAgent is
archived with no final release (its 0.1.x installs reinstall from the Biorouter marketplace).

Biorouter's constraints (its campaign session, 2026-11-26; `BaranziniLab/biorouter` main): the
desktop updater reads an installed bundle's `manifest.repository`, asks GitHub for that repo's
`releases/latest`, strips one `v` from the tag, compares it with `manifest.version` and installs
the first `.brxt` asset, with no prompt. The catalog check requires `release.tag == "v" + version`
and a card URL `https://github.com/<repo>/releases/download/<tag>/<asset>`. So the extension's
version is gptr's version, and every gptr release that carries `gptragent.brxt` deploys it.

**Authority:** this plan adds:

| D | Rule | Amends |
|---|---|---|
| D-372 | the bridge lives in the top-level `gptragent/` folder (Python, outside the R package: `.Rbuildignore`), keeps its id `gptragent` and asset name `gptragent.brxt`; its version is `DESCRIPTION`'s Version and its repository `https://github.com/Broccolito/gptr`; a published, non-prerelease gptr release `vX.Y.Z` gets `gptragent.brxt`, `gptragent-X.Y.Z.brxt` and `SHA256SUMS` from a workflow that refuses a tag other than `v` + both versions | conventions section 3 (layout) |
| D-373 | an `r` call served with no live run that ran (not refused, not plan mode) is recorded on the server's session as a `gptr.mcp_r` entry, and into the bound document when the user bound one with `gptr_doc()` | `04` IC-58/IC-65 recording rule (`mcp_r_recording()`) |
| D-374 | `gptragent/` is also a Claude Code plugin and a Codex plugin named `gptr`, listed by root marketplaces (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`); every host starts the same server with `uv` | none |

Next free decision: D-375.

**Depends on:** gptr 1.2.0 (main 0280d953), GptrAgent 0.1.2 (6b3295e). **Milestone:** 1.3.0.
**Branch:** `claude/v1.3.0`, fast-forwardable from main; merged and released only on the
maintainer's word.

## Global constraints

`dev/plan/00-conventions.md` applies in full to R code. The bridge stays standard-library Python
(>= 3.11, `dependencies = []`), so the R package gains no Imports, Suggests or compiled code, and
nothing in `gptragent/` reaches the CRAN tarball. The discovery record's format 1 is a contract
with the bridge: new fields are additive, a breaking change is format 2. Tests are offline;
live tests run only with `GPTRAGENT_LIVE=1` (bridge) or `GPTR_LIVE_TESTS=true` (R), and never
touch the user's real Claude Code, Codex or Biorouter configuration.

## Tasks

### Task 1 - Bring GptrAgent into gptragent/ with its history
Rewrite GptrAgent's history into `gptragent/` (git filter-repo) and merge it unrelated. Point
`manifest.json`, README, NOTICE and the attach.R header at `Broccolito/gptr`; set the version
to 1.3.0 everywhere the bundle states it; make `build_brxt.py` and a test refuse a version other
than `../DESCRIPTION`'s. `.Rbuildignore` gains the new top-level paths. Accept: the unit suite
and `build_brxt.py` pass in place; `R CMD build` leaves them out.

### Task 2 - Record an outside agent's R calls (D-373)
Relax `mcp_r_recording()` for idle served calls: the call's code, status, outputs and value go to
the server's session, and to the bound document as a block `gptr_export()` turns into R.
Accept: `test-mcp-recording.R` (the old "idle served R adds no history" block becomes the new
rule; plan mode, refused and failed-before-running calls still record nothing), `?gptr_mcp_serve`.

### Task 3 - Claude Code and Codex plugins (D-374)
Plugin manifests in `gptragent/`, root marketplaces, one MCP launch that works on macOS, Linux and
Windows, tool timeouts above the bridge's 280 s cap, the bundled `gptr-live-r` skill. Accept:
`claude plugin validate`; install, list and tool load in throwaway `CLAUDE_CONFIG_DIR` and
`CODEX_HOME`.

### Task 4 - Agent-neutral bridge texts
Setup, overview, mode notes and the skill name no host where the text holds for all three, and
tell the agent that gptr 1.3.0 records its calls. Accept: bridge unit tests.

### Task 5 - CI and release
`.github/workflows/gptragent.yaml`: unit tests on three systems, live tests against this checkout
on Linux and macOS, plugin validation, and the release job of D-372. Every job at most 20
minutes; none is a required check. Accept: a green run on the PR.

### Task 6 - Documentation
README section on working from Biorouter, Claude Code and Codex; the MCP article's serve section
per client; `gptragent/README.md`; NEWS 1.3.0, DESCRIPTION 1.3.0, WORDLIST; this plan's log.
Accept: `dev/release/precompute.R --check`, `check-files.R all`, `check-docs.R`.

### Task 7 - Verification
Bridge unit and live suites; R suites for mcp and docs; `R CMD check --as-cran`; a Biorouter
install of the workflow-built bundle in an isolated profile with the WP-14 e2e scenarios; live
Claude Code and Codex sessions that list, inspect and change a served session, and the recorded
script that results. Accept: the plan acceptance table.

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| 1 | `uv run python -m unittest discover -s tests` in `gptragent/` | | |
| 2 | `GPTRAGENT_LIVE=1` live suite against this checkout | | |
| 3 | `devtools::test(filter = "mcp")` | | |
| 4 | `R CMD check --as-cran` | | |
| 5 | Biorouter 1.94.6 e2e on the workflow-built bundle | | |
| 6 | Claude Code plugin: validate, install, live session | | |
| 7 | Codex plugin: install, live session | | |
| 8 | CI on the PR | | |
