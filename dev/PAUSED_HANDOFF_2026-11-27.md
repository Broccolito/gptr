# gptr paused handoff — 2026-11-27 (gptr 1.3.0 release candidate)

Read this first, then `dev/PROGRESS.md` (its current checkpoint), `CLAUDE.md` and
`dev/plan/00-conventions.md`, and refresh the live state (Git, PR #125, CI, `get_usage`) before
acting. Nothing here authorizes merging into `main`, a GitHub release or a CRAN submission.

## 1. State

| Item | State |
|---|---|
| `claude/v1.3.0` | the release candidate: P34, P35, P36, the review ledger `dev/progress/review-1.3.0.md` (R130-01..R130-30) and its fixes, the CI flake fix, and (if section 2 says it landed) the default `auto` mode. CI was all green at 5dfaca5b. |
| PR #125 | MERGED into `main` (a78ca77e, 2026-11-27 04:13 UTC) on the maintainer's "merge when green", after every check passed on 11214460. |
| win-builder | R-devel uploads: the 5dfaca5b tarball (sha256 `6331534f…`) at 01:44 UTC and the final adc9a2b0 tarball (sha256 `ce7159ed…`, CRAN-mode check Status OK, 123 s locally) at 03:29 UTC; results go by email to the maintainer. Results: the first 515 s, the final (`O9eY6F7FZVG4`) Status OK, check 516 s, installation 90 s, no NOTE. |
| Biorouter | the orchestration session `local_784f49b2-8d15-45ee-b259-95798f22449b` waits for the tag, the release URL and the `SHA256SUMS` line of `gptragent.brxt` after a published v1.3.0. |

## 2. The default `auto` mode (maintainer's request of 2026-11-27)

"Change the default permission mode to auto ... users can grant yolo or drop back to manual. At the
default auto mode there is no badge; only another mode shows the badge." Workflow
`wf_99bf52df-f62` (Opus implementer, Sonnet check passed) built it as D-396, and its four commits
are on `claude/v1.3.0` (823ed7b2..adc9a2b0 locally). Confirm CI is green on the pushed head. Tell the maintainer: `cran-comments.md` now says model
code that changes objects or files runs without asking by default (a CRAN reviewer may question
it), and the Biorouter WP-14 harness's S5 serves without a mode to test manual asking, so it needs
`mode = "manual"`.

## 3. Remaining, in order

1. Land section 2, CI green on the pushed head.
2. Release gates: fill `cran-comments.md`'s "R CMD check results" placeholder (tarball sha256,
   macOS and win-builder results and times, installed size 8.3 Mb, every CI check green) and its
   reverse-dependency date; rebuild the tarball from the final head and rerun the CRAN-mode check;
   re-upload to win-builder if the package changed after 5dfaca5b.
3. Ask the maintainer: merge #125; publish release v1.3.0 (deploys gptr Agent to Biorouter); CRAN
   submission; a CRAN 1.1.x patch for S6; their Codex default `gpt-6.1-sol`.

## 4. Environment

R tests: `R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"
Rscript --vanilla -e 'devtools::test(filter = "<name>")'`. CRAN-mode check commands: see
`/private/tmp/claude-501/gptr130-resume/cran-cbb93cb3/` (build, then `env -i` check with `-o chk`,
creating `chk` first). Another session's vitest suite kept the load near 250 on 16 cores on
2026-11-27; judge timing failures by rerunning the file alone.

## 5. Resume prompt

```text
Resume gptr's 1.3.0 release. Work in a git worktree on branch claude/v1.3.0 (git fetch origin).
Read dev/PAUSED_HANDOFF_2026-11-27.md first, then dev/PROGRESS.md's current checkpoint, CLAUDE.md
and dev/plan/00-conventions.md. Refresh: git log --oneline -5 origin/claude/v1.3.0, gh pr checks
125 -R Broccolito/gptr, mcp__ccd_session_mgmt__get_usage. Bind PR #125 (mcp__ccd_pr__bind_pr) and
turn Auto-fix on (mcp__ccd_pr__set_monitor). Then follow the handoff's section 3. Stop and ask the
maintainer before merging into main, publishing the v1.3.0 release or submitting to CRAN. Hold the
token cap: from about 93% of the weekly window start no new workflow; from about 95% wind down,
push and write the next handoff.
```
