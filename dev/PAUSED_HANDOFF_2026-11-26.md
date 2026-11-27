# gptr paused handoff — 2026-11-26 (gptr 1.3.0 campaigns)

The maintainer set a token cap of 98% of the weekly plan ("Weekly · all models" in
`mcp__ccd_session_mgmt__get_usage`) and asked for a graceful pause with this handoff and a resume
prompt (`dev/RESUME_PROMPT_2026-11-26.md`). Read this file first, then refresh the live state
(Git, PRs, CI, running workflows) before acting. Nothing here authorizes merging into `main`, a
GitHub release or a CRAN submission: those wait for the maintainer's word.

## 1. What the maintainer asked for (2026-11-26)

Three campaigns, all landing in gptr 1.3.0 on the release branch `claude/v1.3.0`:

1. **Bridge (P34).** Move the GptrAgent Biorouter extension into gptr, so Biorouter downloads it
   from gptr's releases. Make the same bridge a Claude Code plugin and a Codex plugin, coordinate
   with the Biorouter session, document everything, and test it end to end.
2. **Compact tool calls (P35).** A default-on setting that shows tool calls abbreviated in the
   `peter()` console, with the full calls available from the history. It changes like every other
   setting. Verify it in real apps, in its own worktree, with CI green before merging.
3. **Models (P36).** Discover the models of Claude Code and Codex through their native interfaces,
   with no hard-coded regexes or rules, and start from the user's default. Accept a write-in model
   for any route or provider. Refresh every provider's catalog (Grok, Gemini and the rest), and
   test live in a terminal console and in RStudio.

Decisions taken with the maintainer:
- the version is 1.3.0;
- outside agents' served calls are recorded (D-373);
- no discovery-record nonce;
- the Claude Code plugin only, no Claude Desktop `.mcpb`;
- Broccolito/GptrAgent is archived with no final release. Its README pointer and archive were
  done on 2026-11-26, and v0.1.2 stays its latest release.

## 2. State at the pause

| Item | State |
|---|---|
| `claude/v1.3.0` | the head after `c7a9fa0b`, pushed: ALL THREE campaigns, namely P34 (bridge, plugins, recording, CI and release workflow, docs), the S6 permission fix `25fcd26c`, P35 (PR #126), P36 (PR #127, merged `c7a9fa0b` after a 50/50 green CI), the timing-test fix `87d9550b` and this handoff. The R checks were last fully green at `aea0d3fb` (before P36). The merged head's CI starts with the next push or run. |
| PR #125 (`claude/v1.3.0` -> `main`) | draft, Auto-fix on. CI was running at `87d9550b` at the pause. Merge only on the maintainer's word. |
| PR #126 (compact calls -> `claude/v1.3.0`) | MERGED after a 50/50 green CI. The remote branch was auto-deleted. |
| PR #127 (models -> `claude/v1.3.0`) | MERGED (`c7a9fa0b`) after a 50/50 green CI at `a01b4e1a`. |
| PR #127 CI | the first run at `5674b3c4` failed: (a) `test-subagent-backends.R:972`, a stale expectation that `claude_code/sonnet` resolves to `claude-sonnet-5-5`, which only the removed fuzzy matcher did. Fixed in `a01b4e1a` (a CLI's own alias passes as written; 330 pass locally). (b) Windows `test-artifact-app.R:527`: "The artifact test child did not settle in 0.3 s", a timing flake in a file P36 does not touch. If it recurs, fix its timing at the root (memory `gptr-release-branch`: never accept a known failure). CI reran at `a01b4e1a` at the pause. |
| P36 review fixes | `86a2c3d8` (workflow `wf_ddae1aea-e76`): write-ins pass as written (`model_near()` only suggests), the Codex provider-key allowlist, the Claude probe with `--tools ""` and `--disable-slash-commands`, the write-in notice before discovery, the D-390 wording, and the Ollama `:cloud` exception in D-393. Filtered suite 9,998 expectations, 0 failed, no lints. The independent Sonnet check passed with 13,521 tests (catalog, CLI, provider, console, config, model, perm and MCP filters), 0 failed, no lints. `model_resolve("openai/gpt-6")` is a write-in with one notice, and `sonnet` and `gemini` resolve to catalog models. |
| Broccolito/GptrAgent | archived; README points to gptr. |
| gptr main | `0280d953` (1.2.0, not on CRAN; CRAN has 1.1.0). |

## 3. What is done and verified

**Bridge (P34; plan `dev/plan/P34-agent-plugins.md`, log `dev/progress/P34.md`, D-372..D-374).**
- **Layout and release.** `gptragent/` holds GptrAgent's history (6 commits, via git
  filter-repo). It is at version 1.3.0 (tied to `DESCRIPTION` by a test), with repository
  Broccolito/gptr. The Biorouter bundle is `gptragent.brxt`, from 13 allow-listed files.
  `.github/workflows/gptragent.yaml` runs unit tests on 3 systems, live tests against this
  checkout and against CRAN gptr, and plugin validation. On a published, non-prerelease gptr
  release `vX.Y.Z` it attaches `gptragent.brxt`, `gptragent-X.Y.Z.brxt` and `SHA256SUMS`.
- **Plugins.** The root marketplaces are `.claude-plugin/marketplace.json` and
  `.agents/plugins/marketplace.json`, and the plugin manifests sit in `gptragent/`. Codex expands
  no variables, so it uses `cwd = "./src"` and `tool_timeout_sec = 300`.
- **Recording (D-373).** An idle served `r` call that ran appends `gptr.mcp_r` to the server's
  session, and goes into a bound `gptr_doc()` document as a direct R line, which `gptr_export()`
  keeps.
- **Live, 2026-11-26.**
  - Claude Code 2.1.323 with `--plugin-dir` passed: connected, sessions/inspect/r, an image, the
    level-4 refusal, recording, and the export replayed in a fresh R. The GitHub install
    `Broccolito/gptr@claude/v1.3.0` works, and `--sparse .claude-plugin gptragent` brings the
    clone from 63 MB to 1 MB.
  - Codex 0.157.1 passed: install from GitHub in a throwaway `CODEX_HOME`, app-server tool list,
    and a live run through the plugin's MCP entry via `-c`. `codex exec` needs
    `mcp_servers.gptr.default_tools_approval_mode="approve"` for `r`.
  - Biorouter 1.94.6, with the WP-14 harness on the CI-built bundle: 11/12 scenarios twice. S4
    fails as in 0.1.2 (the model refits instead of asking).
- **S6.** Found in that run and fixed in `25fcd26c` (with regression tests). With `HOME` naming a
  missing folder, `tools::R_user_dir()` warns, and `risk_path_class()` turned the warning into
  class "unknown". A delete outside the project, or of `.git`/`.env`, or a write to gptr settings,
  then became level 3 and ran in auto/yolo. This affects gptr 1.0.0-1.2.0, including CRAN 1.1.0.
  The harness never created `HOME`; its `start_r.sh` now does, and so does the Biorouter
  session's copy. **The maintainer decides whether to patch CRAN 1.1.x.**
- **L-72.** Added to `dev/progress/open-findings.md`, open: a symlink is classified by its
  target, which the S6 audit found.

**Compact calls (P35; plan `dev/plan/P35-compact-calls.md`, log `dev/progress/P35.md`, D-380..D-383).**
- **Setting.** `compact_calls` (TRUE by default) is a core setting:
  `gptr_config(compact_calls = FALSE, .scope = ...)`, or the option `gptr.compact_calls`.
- **Display.** A call is one row, `▎ r  <first line>  (+N more lines)`. An edit's result is
  `edited <path> · +a -r`, and printed output shows 5 rows, then a count. An approval prints the
  code it gates. `/calls [n]` prints this session's calls whole.
- **Checks.** Filtered suite 9,862 pass. A real pty passed at widths 80 and 40, and with
  NO_COLOR/LANG=C. CI was 50/50 green before the merge.
- **Open: the RStudio live check.** The maintainer DECLINED computer-use access to RStudio at
  about 11:45 PT, so do not request it again unasked. The branch is installed at
  `/private/tmp/claude-501/compact-rlib`.

**Models (P36; plan `dev/plan/P36-model-discovery.md` on `claude/models-discovery`, log
`dev/progress/P36.md`, D-390..D-395).**
- **Claude discovery.** A zero-cost stream-json probe sends `initialize` and `get_settings`, using
  the user's settings.
- **Codex discovery.** `codex app-server` with `model/list` and `config/read`, falling back to
  `codex debug models`. It is cached per CLI command and binary time, and
  `gptr_models(refresh = TRUE)` asks again.
- **Default.** The default is the CLI's own and is shown by name.
- **Write-ins.** Any id is accepted, with one notice. Codex runs carry the user's provider routing
  as `-c` overrides.
- **No name rules.** The hard-coded lists, regexes and name rules are replaced by catalog data.
  The snapshot is built from models.dev by `dev/release`: 704 models in 23.6 KB, dated
  2026-11-26, and includes gemini-4-*, grok-4.7, claude-fable-5-2, claude-haiku-5-5 and
  gpt-6.2-sol.
- **Adapters.** They now pick request shapes from data: Anthropic sampling, GPT-6.2 sampling,
  Gemini levels, xAI and DeepSeek effort, vLLM `reasoning`, Ollama `/api/show`, and OpenRouter
  reasoning.
- **Checks.** Full offline suite 45,098 pass / 0 fail. Lint clean when the package is loaded.
- **Live.** Claude discovery and a live Claude turn worked. Codex discovery worked, but a live
  turn failed because **the maintainer's own `~/.codex/config.toml` default `gpt-6.1-sol` is not
  allowed for their ChatGPT login**, and gptr now follows that config. Tell them.

## 4. What remains, in order

1. **Confirm CI on PR #125 at the merged head.** P36 has landed. If no run is going, start one
   (`gh workflow run` or an empty commit) and let Auto-fix report. Fix any failure at its root.
2. **Models live checks still open.** Run `/model` listing and a write-in in a terminal pty;
   RStudio only if the maintainer grants access. Live provider calls with `GPTR_LIVE_TESTS=true`
   were not run; keep the cost small and load keys only via `gptr_env()`.
3. **One comprehensive review, then one comprehensive fix**, of the whole 1.3.0 diff
   (`main..claude/v1.3.0`, see memory `gptr-review-cadence`).
4. **Release gates.**
   - Finish the NEWS 1.3.0 intro paragraph.
   - `R CMD check --as-cran` on the built tarball, then win-builder R-devel, keeping the check
     time well under 600 s (memory `gptr-cran-checktime`).
   - Update `cran-comments.md`, `dev/PROGRESS.md` and `dev/HANDOFF.md`.
5. **Rerun the Biorouter scenario S6** with the fixed build, once with `HOME` present and once
   deliberately missing. The no-model replay scripts are in
   `/private/tmp/claude-501/s6-reconstruct/bin/` (replay.py, flip.py).
6. **On the maintainer's word only:**
   - merge PR #125 into `main`;
   - publish the GitHub release `v1.3.0` (not a prerelease). This runs the `gptragent` release
     job and DEPLOYS to every Biorouter install at its next launch.
   - Then send the Biorouter session (or its successor) the tag, the asset URL
     `https://github.com/Broccolito/gptr/releases/download/v1.3.0/gptragent.brxt` and the
     `SHA256SUMS` line. It switches the BAAM card, catalog, registries and CLAUDE.md row by PR,
     following section 5 of
     `/Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-26-claude/HANDOFF.md`.
   - The CRAN submission is the maintainer's call.

## 5. Workflows and subagents (how this campaign was run)

Scripts are copied in `dev/progress/workflows-2026-11-26/` (the originals are in the session's
`workflows/scripts/`). Rerun one with `Workflow({scriptPath: "<copy>"})`. A resume
(`resumeFromRunId`) works only in this same session; a new session starts a new run.

| Workflow (run id) | Purpose | Agents (model, isolation) | Outcome |
|---|---|---|---|
| gptr-biorouter-bridge-map (`wf_ce25a7aa-a7d`) | read-only map of GptrAgent vs gptr 1.2.0 | 5 readers + critic (Sonnet) | done |
| gptr-agent-hosting-research (`wf_d6d53c26-493`) | Biorouter hosting rules, Claude/Codex plugin formats, docs/CI conventions | 6 (Sonnet; claude-code-guide/general-purpose) | done |
| gptr-v130-implement (`wf_2a880fe4-753`) | P34 recording, plugins, CI | 3 implementers (Opus, worktree) | done; commits cherry-picked onto `claude/v1.3.0` |
| gptr-bridge-live (`wf_112cb6f0-a5c`) | live Claude Code, Codex, Biorouter checks | 3 (Sonnet) | done; found S6 |
| gptr-s6-gate-rootcause (`wf_42d42032-ef3`) | S6 root cause (reconstruct, audit, cross-check) | 3 (Opus) | done; fix proposal applied in `25fcd26c` |
| gptr-compact-calls-research (`wf_c97b1048-44a`) | console rendering, settings UX, reference agents | 3 (Sonnet) | done |
| gptr-compact-calls-build (`wf_29c0ada0-86c`) | P35 implement, then suite, pty and review | 1 Opus (worktree) + 3 Sonnet | done |
| gptr-compact-calls-fix (`wf_4295dfb7-1f6`) | P35 review fixes | 1 Opus (worktree) + 1 Sonnet | done (`80e82417`) |
| gptr-compact-rstudio (`wf_28ccd010-dda`) | RStudio live check | 1 Sonnet | blocked: access declined |
| gptr-models-research (`wf_e12801fc-cbe`) | CLI native discovery, gptr machinery, 3 provider surveys | 6 (Sonnet) | done; notes in `/private/tmp/claude-501/models-research.txt` |
| gptr-models-build (`wf_d11e483b-e19`) | P36 implement (cli, catalog, providers), integrate, document, verify | 3 Opus (worktree) -> integrator -> docs -> 3 Sonnet | done (`cffee0a1`) |
| gptr-models-fix (`wf_ddae1aea-e76`) | P36 review fixes | 1 Opus (worktree) + 1 Sonnet | done (`86a2c3d8`; check passed, 13,521 tests) |

Patterns that worked (keep them):
- **Isolated worktrees.** Implementers run in isolated worktrees (`isolation: 'worktree'`) and
  start with `git reset --hard <campaign branch>`, because the worktree is cut from main. This
  session's hook refuses Write/Edit into another worktree, so campaign branches are only refs.
  Integrate implementer commits by cherry-pick or merge in your own worktree, or by
  `git branch -f <branch> <sha>` when no worktree has the branch checked out.
- **Model tiers.** Opus implements; Sonnet verifies (full suite, pty driving, review, live
  probes), as in memory `gptr-workflow-model-tiers`.
- **Briefs.** Each brief names the files the agent owns, the facts already settled and what done
  looks like. Agents must never write into another worktree, print secrets or touch the user's
  real `~/.claude`/`~/.codex`. They use throwaway `CLAUDE_CONFIG_DIR`/`CODEX_HOME` for install
  checks, and real logins only for zero-cost read-only probes or a few tiny prompts.
- **Heartbeats.** A background `sleep 600-840; echo heartbeat` Bash call wakes the coordinator.
  At each wake, check `get_usage`, each agent's transcript mtime and line count, and the PR
  checks (memory `gptr-periodic-health-checks`). Never message a running workflow agent; stop
  the workflow and relaunch instead.
- **Auto-fix.** Auto-fix on a PR (`mcp__ccd_pr__set_monitor`) wakes the session on CI failures
  and conflicts. Resolve a conflict by merging the fetched base (never a rebase or force-push).
  Cancel superseded CI runs after a new push (`gh run cancel`).

## 6. Environment

- Repository: `/Users/wgu/Desktop/gptr` (main checkout on `main`). This session's worktree is
  `.claude/worktrees/gptr-biorouter-bridge-coord-2d1eed`, on `claude/v1.3.0`.
- R tests: `R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"
  Rscript --vanilla -e 'devtools::test(filter = "<name>")'`. Lint: `Rscript --vanilla
  dev/ci/isolated-check.R lint <files>`. Docs: `dev/release/check-files.R all`,
  `dev/release/check-docs.R`, `dev/release/precompute.R <vignette>|--readme|--check`.
- Bridge: `cd gptragent && uv run python -m unittest discover -s tests`, then
  `uv run python scripts/build_brxt.py`. Live tests: `GPTRAGENT_LIVE=1` (and
  `GPTRAGENT_LIVE_ATTACH=1` for `attach.R`), with gptr 1.3.0 installed in
  `/private/tmp/claude-501/gptr130-lib`.
- CLIs: claude 2.1.323, codex 0.157.1, uv 0.13.9, python3 3.15.2.
- Biorouter harness: the copy is at `/Users/wgu/biorouter-runs/gptr-bridge-1.3.0`, with
  `scripts/`, `e2e/` and `run1/` (the failing S6 evidence is `run1/s6-first.jsonl`). The isolated
  profile is `/Users/wgu/bi-iso/gptr-1.3.0` and the binary
  `/Users/wgu/biorouter-runs/bin-1.94.6/biorouter`. Versa keys load inside `brun.sh` from
  `/Users/wgu/Desktop/biorouter/live-test.env`: never print them, and keep to the harness's
  scenarios (the owner has a cost concern).
- Peer: the session "Biorouter 1.94.6 release campaign"
  (`local_5eacc075-782d-4cbd-a1e1-9bc6b6c1ae79`), near its own cap. Its successor's handoff is
  the file named in section 4, item 6.
