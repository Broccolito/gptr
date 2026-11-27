# gptr paused handoff — 2026-11-27 (gptr 1.3.0 released, CRAN submission pending)

Read this first, then `dev/PROGRESS.md` (its current checkpoint), `CLAUDE.md` and
`dev/plan/00-conventions.md`, and refresh the live state (Git, releases, CI, `get_usage`) before
acting. Nothing here authorizes another release, a CRAN resubmission or a merge into `main`.

## 1. State

| Item | State |
|---|---|
| `main` | f35c2cab (PR #128 merged on the maintainer's "merge when green", after all 50 checks passed on 554dfd50, whose tree it is). CI was green on a78ca77e (35 R-CMD-check jobs, Windows-check, gptragent, pkgdown). |
| GitHub release | `v1.3.0` at f35c2cab, published 2026-11-27 05:01 UTC as Latest on the maintainer's word. Assets: `gptragent.brxt` and `gptragent-1.3.0.brxt` (sha256 `2cbe62f3…fcc3`), `SHA256SUMS` and `gptr_1.3.0.tar.gz` (the CRAN archive). The `gptragent` release run 45943290897, its first, passed all 8 jobs; `shasum -c SHA256SUMS` passes and `releases/latest/download/gptragent.brxt` answers 200. |
| Biorouter | the running "Biorouter campaign orchestration takeover" session (`local_c020cda1-baf3-4f13-a92e-54a740c29fe4`; the earlier `local_784f49b2-…` is no longer listed) received the tag, the asset URL, the `SHA256SUMS` line and the note that the WP-14 harness's S5 needs `mode = "manual"`. |
| CRAN | the archive `gptr_1.3.0.tar.gz` (sha256 `ce7159ed…`, package files of f35c2cab) and `main`'s `cran-comments.md` were uploaded with `devtools:::upload_cran()` at about 05:18 UTC on the maintainer's word; CRAN emails the maintainer a confirmation link, and the submission counts only once they click it. |
| Decisions | the maintainer chose no separate CRAN 1.1.x patch for S6 (1.3.0 carries the fix, and `cran-comments.md` names it as the reason for the early update). |

## 2. Remaining, in order

1. The maintainer confirms the CRAN submission from the email. Then CRAN's pretest emails arrive
   (Debian and Windows R-devel). On "on its way to CRAN" or the publication email, record the date
   in `dev/PROGRESS.md`. If the pretest archives the submission, read the reason, fix it on a
   branch, rebuild, rerun the CRAN-mode check and win-builder, and resubmit only on the
   maintainer's word.
2. Confirm with the Biorouter session that its installs picked up gptr Agent 1.3.0.
3. Open, not blocking: L-72 (symlink classified by its target); `dev/release/tests/
   test-interactive-examples.R`'s two failures (its `gptr_mcp_serve()` stub lacks `mode` and
   `advertise`); the maintainer's own Codex default `gpt-6.1-sol`, which their ChatGPT login
   rejects (their `~/.codex/config.toml`, not gptr).

## 3. Environment

R tests: `R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"
Rscript --vanilla -e 'devtools::test(filter = "<name>")'`. CRAN-mode check commands: see
`/private/tmp/claude-501/gptr130-resume/cran-cbb93cb3/` (build, then `env -i` check with `-o chk`,
creating `chk` first); the submitted archive is
`/private/tmp/claude-501/gptr130-resume/cran-adc9a2b0/gptr_1.3.0.tar.gz` and on the v1.3.0 release.

## 4. Resume prompt

```text
Resume gptr after the 1.3.0 release. v1.3.0 is published on GitHub (f35c2cab) and the CRAN
submission was uploaded on 2026-11-27. Work in a git worktree off origin/main. Read
dev/PAUSED_HANDOFF_2026-11-27.md first, then dev/PROGRESS.md's current checkpoint, CLAUDE.md and
dev/plan/00-conventions.md. Refresh: git log --oneline -3 origin/main, gh release view v1.3.0 -R
Broccolito/gptr, gh run list -R Broccolito/gptr --limit 10, mcp__ccd_session_mgmt__get_usage; ask
the maintainer whether they confirmed the CRAN submission and what CRAN's emails said. Then follow
the handoff's section 2. Stop and ask the maintainer before a CRAN resubmission, another release or
a merge into main.
```
