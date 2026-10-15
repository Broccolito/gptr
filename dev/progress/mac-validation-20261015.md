# Mac validation checkpoint — 2026-10-15

The three lanes are Shiny/browser, models/workflows/compaction, and frontends/UX.
Root owns integration, dependencies, shared documents, Git and rebuilds. Fast alone
controls GUI. Agents use separate files, private R sessions, libraries, working
directories and output paths. Independent lightweight work runs concurrently;
resource checks precede heavier overlap. Keep four private families within 12 GiB
declared caps, CPU 1 normally, at most two internally parallel jobs/12 workers,
and separately admit large-memory/GPU work. Preserve shared models and unowned
processes. Old serial-only scheduling is superseded; correctness, security,
resource, deadline, parent-state and cleanup gates remain unchanged.

## Source and environment

Primary `/Users/wgu/Desktop/gptr` remains dirty and preserved. The immutable f5
validation worktree is `/Users/wgu/.codex/worktrees/shiny-relaunch-cleanup/gptr` at
`f5f389c7bf8d20b36eb42f6f33bdcaee6baa5b16`. Root integrates tested follow-up changes
in `/Users/wgu/.codex/worktrees/mac-final-integration/gptr`. PR6 is open/draft;
main is protected. Current public Pages still serves an older deployment.

The original-Mac reinstall and separate cleanup passed. Backups are exclusively
on `/Volumes/WD_BLACK/gptr-r-backup-quiescent-20261015`. Do not rerun the installer.
R 4.6.1 ARM64/R.app 1.83 and 139 fresh private binary dependencies are verified.
A fresh ordinary R session also loads the accepted f5 installation from the
standard user library with exactly eight runtime dependency packages.

## Completed actual evidence

| Scope | Result and limits |
| --- | --- |
| Normal f5 archive/install | 2,656,461 B archive; 7,006,968 B installed; Rdb 5,044,669 B; documentation 1,725,641 B; data 0. Default byte compilation retained. Installed 5 MB aim remains unmet. |
| Full f5 as-CRAN | Status OK; zero errors/warnings/notes; 30,599 assertions and 446 accounted skips (421 On CRAN/25 specific), all 59 examples. 486.845 s/2,084.56 MiB sampled peak. Keep-source size 10,095,041 B is INFO. Historical Windows size NOTES remain visible. |
| Fresh source batches | 200 files/4,210 cases/33,418 assertions/44 accounted skips at 44a1c29. All eight caller predicates/full connections and owned cleanup pass; one direct test-owned process warning stays qualified. Later Shiny cleanup and compaction-clock fixes have focused RED/GREEN evidence. |
| Providers and decisions | Claude OAuth, Codex CLI, Azure, Jev typed decisions/composition, functional steering, two genuine overlapping workers and zero-request replay/resume passed their scoped checks. Qwen base numerics/state pass with output-style issues; its steering case remains NONPASS for replacing/removing supplied data. |
| Automatic/manual compaction | Manual, automatic, budget and abort LIVE/resume pairs are independently accepted, including repeated two-checkpoint hysteresis, independent compactor accounting and unchanged deadlines. A new genuine two-worker case passed one automatic checkpoint/continuation per worker with eight independent real charges and exact proxy accounting. |
| In-memory/scientific | Actual 4 GiB data, address/copy/RNG preservation across three turns; 23.829 s/5,603 MiB sampled peak. ML and synthetic RNA/PCA/clustering plus fresh zero-request raw replay pass. Synthetic data does not establish biological analysis validity. |
| Files/resources/storage | Four offline extension families pass; live file writes, download, web search and resource/skill/plugin/MCP workflows pass. Recovered tool errors remain visible. ST01 passes all 11 storage operations and cleanup; `/summary` is an unsupported old command, and JSON parsing is not a universal schema audit. |
| Native RStudio/R.app | RStudio physically resized 1200→800→1440 during output, reporting 81→52→99 columns. R.app native `!` completion, pasted fences and formatting passed. These scoped tests do not establish every progress/interrupt or resizing feature in every client. |
| Documents/notebooks | Fresh Rscript and R Markdown pass. Quarto functional output passes but its own serialized closure drifts, reproduced without gptr. Six headless Jupyter cells pass MIME/state/cleanup; this does not replace browser interaction. |
| Shiny generation/history | Genuine create→edit yielded v2 and headless numerical controls; original GUI lease case remains NONPASS because private opener checks prevented navigation. The same saved v2 completed actual browser interaction, narrow/wide layouts and 200% zoom within the original 300-second lease; full controller settlement remains to be audited. Recorded downstream Peter/raw exports, formatting and fresh raw replay pass; two original live history cases remain NONPASS (old AST fixture, then model skill-path waste exceeding the unchanged cap). |
| Focused follow-up fixes | Literal skill paths clarified in the read schema: RED one expected failure, GREEN 658 assertions/two clean lints. Windows observer caches immutable ABI/bindings only: RED four expected failures; GREEN 46 controls/zero failures/errors/warnings/skips. Every path/query/buffer/error/close stays fresh. No Windows runtime-resolution claim yet. |

## Remaining work, in order

1. **Running:** independent settlement review of the actual saved-v2 Shiny GUI
   and correction of a private pkgdown validator assumption. The f5 site build
   passed; its first validator incorrectly required a canonical tag absent from
   upstream pkgdown. Rescan the unchanged output; preserve the original failure.
2. **Blocked by client access:** VS Code terminal/editor needs macOS Accessibility
   access before exact-owned-window control. Authenticated Jupyter browser testing
   needs a fresh coordinated local sign-in; the previous page expired. Do not
   bypass authentication or treat headless output as GUI acceptance.
3. **Queued:** integrate concise R-MCP private-library guidance, current status and
   CRAN comments; regenerate the affected vignette; run all four plan tools.
   Rebuild the final integration artifact and run relevant combined source,
   documentation/lint/examples and full as-CRAN gates. Measure final sizes/timings.
4. **Queued:** review final-head required CI (including Windows observer controls),
   merge PR6 when gates permit, safely synchronize main, install the final accepted
   artifact into the standard user library and verify ordinary loading. Publish
   pkgdown and verify actual public deployment, responsive pages and links.
5. **Last:** final live Windows verification after all Mac integration and native
   work. Hosted Windows CI is a separate gate and does not replace live verification.

The full 13-guide feature matrix, slash commands/settings, plugins/skills/MCP,
history formats, workers, progress/completion and platform/provider combinations
remain in `dev/TESTING_PLAN.md`. Package examples remain minimal and offline;
live validation is explicitly enabled only in private tests. No release or CRAN
submission has occurred. Submission is being prepared.

## Local evidence

Detailed immutable receipts and original logs live under the ignored
`/Users/wgu/Desktop/gptr/dev/.validation/readiness-20261011/` tree, particularly
`host-r-reinstall-20261015/PLAN.md`, `remaining-installed-f5/`, `model-smoke/`,
`cran-check/cf5/`, `size/f5-final-size-audit/` and frontend-specific packets.
Do not infer completion from preparation, a provisional controller summary,
a source peer review, a historical artifact or a process that is still running.
