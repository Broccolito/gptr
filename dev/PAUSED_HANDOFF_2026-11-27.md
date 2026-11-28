# gptr paused handoff — 2026-11-27 (1.3.1 prepared, the Biorouter id rename planned)

Read this first, then `dev/PROGRESS.md` (its current checkpoint), `CLAUDE.md` and
`dev/plan/00-conventions.md`, and refresh the live state (Git, PRs, releases, CI, `get_usage`)
before acting. Nothing here authorizes a release, a CRAN resubmission or a gptr-named bundle.

## 1. State

| Item | State |
|---|---|
| `main` | dac45704: gptr 1.3.1 (PR #130, the mode wording and the Baranzini Lab credit), CI green (R-CMD-check, Windows-check, gptragent, pkgdown). |
| PR #131 | `claude/mcp-bridge`: the bridge moves from `gptragent/` to `mcp-bridge/` and its texts say "gptr's MCP bridge"; "gptr Agent" names the Biorouter extension only (D-397). Three commits: the pure move (bundle bytes identical to dac45704's, `aef1a872…fa3f`), docs, host-neutral messages; plus this handoff. The maintainer said to fold it into 1.3.1 ("do this exactly as planned"); merge when green. |
| GitHub releases | `v1.3.0` is Latest (f35c2cab; `gptragent.brxt`, `gptragent-1.3.0.brxt`, `SHA256SUMS`, `gptr_1.3.0.tar.gz`). `v1.3.1` is not published: it waits for the maintainer's word, and publishing redeploys the bundle to every Biorouter install. |
| CRAN | 1.3.0 uploaded about 05:18 UTC on 2026-11-27, waiting for the maintainer's email confirmation. Its vignette and README carry the old folder name and the old "only read" sentence (docs only); the next CRAN release fixes them. |
| Biorouter | session "Biorouter campaign orchestration takeover" (`local_c020cda1-baf3-4f13-a92e-54a740c29fe4`) wound down at 94 % of the weekly window; its handoff: `/Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-26-claude/HANDOFF.md` (section 0c, item 5) and `NEXT-AGENT-PROMPT.md` (item 4). It keeps the BAAM listing on gptragent and repoints it after v1.3.1 is published. |

## 2. Remaining, in order

1. PR #131: when every check is green, merge it (the maintainer's go-ahead of 2026-11-27).
2. On the maintainer's word only, publish v1.3.1 from `main`'s head after #131:
   `gh release create v1.3.1 -R Broccolito/gptr --target <full sha> --title "gptr 1.3.1"
   --notes-file <NEWS 1.3.1 section without its heading> --latest` (bundle only, no tarball).
   The `mcp-bridge` workflow's release job attaches `gptragent.brxt`, `gptragent-1.3.1.brxt` and
   `SHA256SUMS`; check them with `shasum -c`, then send the Biorouter session the tag, the URL
   `https://github.com/Broccolito/gptr/releases/download/v1.3.1/gptragent.brxt` and the
   `SHA256SUMS` line (it reruns its install test and opens the BAAM repoint PR).
3. CRAN 1.3.0: when the maintainer confirms and CRAN's emails arrive, record them in
   `dev/PROGRESS.md`; resubmit only on the maintainer's word.
4. The Biorouter id rename `gptragent` -> `gptr` (the maintainer's request of 2026-11-27: tools
   `gptr__sessions`, `gptr__inspect`, `gptr__r`; display name stays "gptr Agent"). Agreed with the
   Biorouter session:
   - G1: until a Biorouter release R ships its side, gptr releases attach only `gptragent.brxt`
     and `gptragent-X.Y.Z.brxt` (manifest and entry point `gptragent`). Build no gptr-named bundle
     for release before that session confirms R has shipped.
   - Biorouter's side (B1-B4, its session): `gptr` joins the compiled private list (keeping
     `gptragent`), a rename map migrates config keys, install folders, provenance and stored
     `gptragent__*` tool names, the updater takes only the expected asset and manifest name, and
     the catalog gets a `gptr` row with `gptragent` superseded by it.
   - Why the order matters: old clients' updater (`extensionUpdater.ts:224`) installs the first
     `.brxt` of releases/latest without checking its name, and GitHub listed v1.3.0's assets in
     case-insensitive name order, not upload order, so `gptr.brxt` would sort before
     `gptragent.brxt`.
   - G2 (agreed): after R, gptr-named bundles (`gptr.brxt`, `gptr-X.Y.Z.brxt`, manifest and entry
     point `gptr`, tools `gptr__*`, display name "gptr Agent", their own `SHA256SUMS`) go ONLY on a
     separate release never marked latest (`make_latest` false, for example tag `bridge-vX.Y.Z`);
     the BAAM registry row names that tag, asset and sha256. releases/latest keeps only
     gptragent-named bundles, so the release job builds both.
   - G3: when the download dashboard shows old clients are rare, new releases stop attaching the
     gptragent bundles. A gptr-named bundle goes on a release marked latest only after a
     scratch-repo test shows a pre-R client handles it safely.
   - gptr's side, once cleared: manifest name, entry point, pyproject name and console script
     `gptr` (`build_brxt.py` requires the pyproject name to equal the manifest name); the Python
     package `src/gptragent` renamed (for example `gptr_mcp_bridge`) with `python -m` in both
     plugin.json files and `uv lock`; the skill's `extension:` and tool names; serverInfo,
     clientInfo and User-Agent names; `GPTRAGENT_RSCRIPT` renamed with the old name still read;
     the test variables; `build_brxt.py`, `version.py`, the tests, and the release job's assets
     and `--previous` identity check per the agreed design; a decision D-398. The Claude Code and
     Codex plugin stays `gptr`.
5. Open, not blocking: L-72 (symlink classified by its target); `dev/release/tests/
   test-interactive-examples.R`'s two failures (its `gptr_mcp_serve()` stub lacks `mode` and
   `advertise`); the maintainer's Codex default `gpt-6.1-sol`, which their ChatGPT login rejects.

## 3. Environment

R tests: `R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"
Rscript --vanilla -e 'devtools::test(filter = "<name>")'`. Bridge: from `mcp-bridge/`,
`uv run python -m unittest discover -s tests` and `uv run python scripts/build_brxt.py`.
Cross-plan checks: `dev/research/assets/consolidation-tools/README.md` (on 2026-11-27 the index
reports error 14122, info 895, warn 578, the same on `main`; 773 R blocks clean; no lints).

## 4. Resume prompt

```text
Resume gptr after the 1.3.1 preparation. Work in a git worktree off origin/main. Read
dev/PAUSED_HANDOFF_2026-11-27.md first (on main once PR #131 merges, else on branch
claude/mcp-bridge), then dev/PROGRESS.md's current checkpoint, CLAUDE.md and
dev/plan/00-conventions.md. Refresh: git log --oneline -3 origin/main, gh pr list -R
Broccolito/gptr, gh pr checks 131 -R Broccolito/gptr, gh release list -R Broccolito/gptr --limit 3,
mcp__ccd_session_mgmt__get_usage, and ListAgents for the Biorouter session (answer its messages
with SendMessage to their from address). Then follow the handoff's section 2: merge PR #131 when
green; ask the maintainer before publishing v1.3.1, before a CRAN resubmission, and before any
gptr-named bundle; do the gptragent -> gptr rename on gptr's side only after the Biorouter session
confirms its release and the asset design. Hold the token cap: at about 98% of the weekly window
pause gracefully: push, revise this handoff and this prompt, and tell the Biorouter session.
```
