# gptr paused handoff — 2026-11-27 (1.3.1 on main, the Biorouter id rename in a draft PR)

Read this first, then `dev/PROGRESS.md` (its current checkpoint), `CLAUDE.md` and
`dev/plan/00-conventions.md`, and refresh the live state (Git, PRs, releases, CI, `get_usage`)
before acting. Nothing here authorizes a release, a CRAN resubmission or a merge of the draft PR.

## 1. State

| Item | State |
|---|---|
| `main` | 8189db27: gptr 1.3.1. PR #130 (the mode wording, the Baranzini Lab credit) and PR #131 (the bridge moved from `gptragent/` to `mcp-bridge/`, named gptr's MCP bridge, "gptr Agent" kept for the Biorouter extension, D-397; merged on the maintainer's go-ahead after 57 checks passed, tree equal to the tested head). CI green on 8189db27 (R-CMD-check, Windows-check, mcp-bridge, pkgdown). |
| Draft PR | `claude/gptr-extension-id` (D-398): gptr's side of Biorouter's id rename `gptragent` -> `gptr`. The Python package is `gptr_mcp_bridge`; `build_brxt.py --name gptr` builds the gptr-named bundle; the release job puts it on its own prerelease `bridge-vX.Y.Z` (never latest) only when the repository variable `GPTR_NAMED_BUNDLE` is `true`; `GPTR_RSCRIPT` with `GPTRAGENT_RSCRIPT` still read. Both bundles install with `uv sync` and answer `initialize` through their entry points. Merging is the maintainer's call. |
| GitHub releases | `v1.3.0` is Latest (f35c2cab). `v1.3.1` is not published: it waits for the maintainer's word, and publishing redeploys the bundle to every Biorouter install. |
| CRAN | 1.3.0 uploaded about 05:18 UTC on 2026-11-27, waiting for the maintainer's email confirmation. Its vignette and README carry the old folder name and the old "only read" sentence (docs only). |
| Biorouter | session "Biorouter campaign orchestration takeover" (`local_c020cda1-baf3-4f13-a92e-54a740c29fe4`) wound down at 94 % of the weekly window (its owner's rule: nothing new from 90 %); the next Biorouter session builds its side. Its handoff: `/Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-26-claude/HANDOFF.md` (section 0c, item 5) and `NEXT-AGENT-PROMPT.md` (item 4). It repoints the BAAM listing (gptragent) after v1.3.1 is published. |

## 2. Remaining, in order

1. On the maintainer's word only, publish v1.3.1 from `main`:
   `gh release create v1.3.1 -R Broccolito/gptr --target <full sha of main> --title "gptr 1.3.1"
   --notes-file <NEWS 1.3.1 section without its heading> --latest` (bundle only, no tarball).
   If the draft PR merges first, 1.3.1 carries it too (then update its NEWS heading text if
   needed). The `mcp-bridge` workflow's release job attaches `gptragent.brxt`,
   `gptragent-1.3.1.brxt` and `SHA256SUMS`; check them with `shasum -c`, then send the Biorouter
   session the tag, `https://github.com/Broccolito/gptr/releases/download/v1.3.1/gptragent.brxt`
   and the `SHA256SUMS` line.
2. CRAN 1.3.0: when the maintainer confirms and CRAN's emails arrive, record them in
   `dev/PROGRESS.md`; resubmit only on the maintainer's word.
3. The Biorouter id rename `gptragent` -> `gptr` (the maintainer's request of 2026-11-27: tools
   `gptr__sessions`, `gptr__inspect`, `gptr__r`; display name stays "gptr Agent"), agreed with
   the Biorouter session:
   - Biorouter's side (B1-B4, its next session): `gptr` joins the compiled private list (keeping
     `gptragent`); a rename map migrates config keys, install folders, provenance and stored
     `gptragent__*` tool names; the updater takes for a BAAM extension the release the registry
     row names (tag, asset, sha256) and refuses an unexpected manifest name; the catalog gets a
     `gptr` row with `gptragent` superseded by it. Biorouter release R ships these.
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
4. Open, not blocking: L-72 (symlink classified by its target); `dev/release/tests/
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
Resume gptr after the 1.3.1 preparation. Work in a git worktree off origin/main. Read
dev/PAUSED_HANDOFF_2026-11-27.md first (the newest copy is on branch claude/gptr-extension-id
until its draft PR merges), then dev/PROGRESS.md's current checkpoint, CLAUDE.md and
dev/plan/00-conventions.md. Refresh: git log --oneline -3 origin/main, gh pr list -R
Broccolito/gptr, gh release list -R Broccolito/gptr --limit 3, mcp__ccd_session_mgmt__get_usage,
and ListAgents for the Biorouter session (answer its messages with SendMessage to their from
address). Then follow the handoff's section 2. Ask the maintainer before publishing v1.3.1,
merging the draft PR (claude/gptr-extension-id), setting GPTR_NAMED_BUNDLE, a CRAN resubmission,
or any release that carries a gptr-named bundle; G2 also needs the Biorouter session's
confirmation that its release R has shipped. Hold the token cap: at about 98% of the weekly window
pause gracefully: push, revise this handoff and this prompt, and tell the Biorouter session.
```
