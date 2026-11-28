# gptr paused handoff — 2026-11-27 (1.3.1 published; next: CRAN 1.3.0 and Biorouter's id rename)

Read this first, then `dev/PROGRESS.md` (its current checkpoint), `CLAUDE.md` and
`dev/plan/00-conventions.md`, and refresh the live state (Git, PRs, releases, CI, `get_usage`)
before acting. The maintainer's decision of 2026-11-27 ("the decision is to merge 132 and then
publish") is carried out. Nothing here authorizes anything else: no CRAN resubmission, no
`GPTR_NAMED_BUNDLE`, no gptr-named bundle on a release.

## 1. State

| Item | State |
|---|---|
| `main` | 58280d6d: PR #132 merged (06:19 UTC on 2026-11-28) after all 57 checks passed on 42bb8dfe (one macOS shard rerun after r-hub's R version lookup failed), tree equal to the tested head. CI green on 58280d6d (R-CMD-check, Windows-check, mcp-bridge, pkgdown). Before it: PR #130 (the mode wording, the Baranzini Lab credit) and PR #131 (the bridge moved from `gptragent/` to `mcp-bridge/`, named gptr's MCP bridge, "gptr Agent" kept for the Biorouter extension, D-397). |
| PR #132 | D-398, gptr's side of Biorouter's id rename `gptragent` -> `gptr`. The Python package is `gptr_mcp_bridge`; `build_brxt.py --name gptr` builds the gptr-named bundle; the release job puts it on its own prerelease `bridge-vX.Y.Z` (never latest) only when the repository variable `GPTR_NAMED_BUNDLE` is `true`; `GPTR_RSCRIPT` with `GPTRAGENT_RSCRIPT` still read. Each bundle reports its own extension name as serverInfo.name. |
| GitHub releases | `v1.3.1` is Latest (58280d6d, published 06:40 UTC on 2026-11-28, no tarball). Its `mcp-bridge` release run 46117686778 passed all 8 jobs and attached `gptragent.brxt` and the identical `gptragent-1.3.1.brxt` (34,869 bytes, sha256 `446e76bf8aa981334e6d7d0bbe4756be3e0455570b18c9fb72e97c4943b90c80`, `shasum -c` OK, manifest `gptragent` 1.3.1 "gptr Agent") and `SHA256SUMS`. No `bridge-v1.3.1` release and no gptr-named bundle on any release; `GPTR_NAMED_BUNDLE` unset. |
| CRAN | 1.3.0 uploaded about 05:18 UTC on 2026-11-27, waiting for the maintainer's email confirmation. Its vignette and README carry the old folder name and the old "only read" sentence (docs only). |
| Biorouter | session "Biorouter UCSF campaign orchestration" (`local_fd2052dd-b1fd-45a6-90f1-fd0c6913dc23`). Its owner approved the rename on 2026-11-27; it builds B1-B4 as one Biorouter PR. It got v1.3.1's tag, asset URL and `SHA256SUMS` line; it reruns its install test and published-bytes review and opens the BAAM repoint PR (gptragent; the merge waits for its owner). It tells gptr when Biorouter release R has shipped. The earlier session "Biorouter campaign orchestration takeover" wound down; its handoff: `/Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-26-claude/HANDOFF.md`. |

## 2. Remaining, in order

1. CRAN 1.3.0: when the maintainer confirms and CRAN's emails arrive, record them in
   `dev/PROGRESS.md`; resubmit only on the maintainer's word.
2. The Biorouter id rename `gptragent` -> `gptr` (the maintainer's request of 2026-11-27: tools
   `gptr__sessions`, `gptr__inspect`, `gptr__r`; display name stays "gptr Agent"), agreed with
   the Biorouter session:
   - Biorouter's side (B1-B4, one PR in the Biorouter session): `gptr` joins the compiled private
     list (keeping `gptragent`); a rename map with a tool-name resolver migrates config keys,
     install folders, provenance and stored `gptragent__*` tool names; the updater takes for a
     BAAM extension the release the registry row names (tag, asset, sha256) and refuses an
     unexpected manifest name; the catalog gets a `gptr` row with `gptragent` superseded by it.
     Biorouter release R ships these.
   - G1: until R ships, gptr's releases carry only gptragent-named bundles; keep
     `GPTR_NAMED_BUNDLE` unset. Old clients' updater (`extensionUpdater.ts:224`) installs the
     first `.brxt` of releases/latest without checking its name, and GitHub lists assets by name
     (case-insensitive), so a `gptr.brxt` there would sort first and classify as public on an old
     client.
   - G2: when the Biorouter session confirms R has shipped, and on the maintainer's word, set
     `gh variable set GPTR_NAMED_BUNDLE --body true -R Broccolito/gptr`; the next gptr release
     also creates the prerelease `bridge-vX.Y.Z` with `gptr.brxt`, `gptr-X.Y.Z.brxt` and its
     `SHA256SUMS`, which Biorouter's registry row names. Send the Biorouter session its tag and
     sha256.
   - G3: when the download dashboard shows old clients are rare, move the source to `gptr`
     (manifest, pyproject name and script, skill) and stop attaching gptragent bundles; a
     gptr-named bundle goes on a release marked latest only after a scratch-repo test shows a
     pre-R client handles it safely.
3. Open, not blocking: L-72 (symlink classified by its target); `dev/release/tests/
   test-interactive-examples.R`'s two failures (its `gptr_mcp_serve()` stub lacks `mode` and
   `advertise`); the maintainer's Codex default `gpt-6.1-sol`, which their ChatGPT login rejects.

## 3. Environment

R tests: `R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"
Rscript --vanilla -e 'devtools::test(filter = "<name>")'`. Bridge: from `mcp-bridge/`,
`uv run python -m unittest discover -s tests` and `uv run python scripts/build_brxt.py [--name
gptr --out dist-gptr]`. Cross-plan checks: `dev/research/assets/consolidation-tools/README.md`
(on 2026-11-27 the index reports error 14122, info 895, warn 578, the same as before D-397; 773 R
blocks clean; no lints).

## 4. Resume prompt

```text
Resume gptr after the 1.3.1 GitHub release. Work in a git worktree off origin/main. Read
dev/PAUSED_HANDOFF_2026-11-27.md first, then dev/PROGRESS.md's current checkpoint, CLAUDE.md and
dev/plan/00-conventions.md. Refresh: git log --oneline -3 origin/main, gh release list -R
Broccolito/gptr --limit 3, gh variable list -R Broccolito/gptr (GPTR_NAMED_BUNDLE must be unset),
mcp__ccd_session_mgmt__get_usage, and ListAgents for the Biorouter session "Biorouter UCSF
campaign orchestration" (answer its messages with SendMessage to their from address). Then
follow the handoff's section 2:
1. CRAN 1.3.0: when the maintainer confirms and CRAN's emails arrive, record them in
   dev/PROGRESS.md on a docs PR.
2. Biorouter's id rename: when the Biorouter session says Biorouter release R has shipped, ask
   the maintainer whether to set GPTR_NAMED_BUNDLE (G2); only on their word set it, and on the
   next gptr release send the Biorouter session the bridge-vX.Y.Z tag and its gptr.brxt sha256.
Ask the maintainer before a CRAN resubmission, setting GPTR_NAMED_BUNDLE, or any release that
carries a gptr-named bundle (that also needs the Biorouter session's confirmation that its
release R has shipped). Hold the token cap: at about 98% of the weekly window pause gracefully:
push, revise the handoff and this prompt, and tell the Biorouter session.
```
