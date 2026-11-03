# 1.0.1 fixes, lane A: bounded file checkpoints (#98)

Branch `claude/fix-A`, cut from `04dca16a`. Decisions D-310 to D-314. Every high and medium finding
of the lane is fixed, and so are the verifier's follow-up problems (the last three rows). Tests were written first, seen failing, then made to pass.

## Fixed

| Commit | Fix | Findings | Tests |
| --- | --- | --- | --- |
| `a6e2c71b` | The bounded scan runs in the R session (D-310), not in a supervised `Rscript` worker. It keeps #98's limits, order and absence proofs. The 2 s budget is checked between entries and before each capture. An interrupt that the person continues from ends the scan and keeps what it completed. `gptr.checkpoint_scan_budget` compares the scan's own time. The worker, its record files, the cleanup and reaping code, the `ckpt_scan` bootstrap entry and test-ckpt-scan-lifecycle.R are deleted. The entry limit is one constant, `ckpt_entry_max`. `?gptr_rewind` now lists the timeout. The vignette `.Rmd.orig` gets the paragraph that #98 added only to the `.Rmd`. | review correctness: two R start-ups per call (medium), killed workers leave Rtmp directories (low). Review design: two child launches per call (medium), per-entry checks and record files (low), repeated literals (low), redundant bootstrap and cleanup (low), stale option docs (low), vignette `.orig` drift (low). Live tests: empty project times out (medium), 2 s deadline includes start-up (high), misleading time-limit notice (two low reports). | test-ckpt-scan.R: "the time budget stops a scan between entries and keeps what it completed", "a zero budget scans nothing and invalid budgets are refused", "an interrupt the person continues from stops the scan and keeps its records", "scans never capture protected paths, startup files, links or FIFOs". test-ckpt-files.R: "a scan slower than gptr.checkpoint_scan_budget switches to per-turn scans once". |
| `c3e8b9e6` | A sync's observations replace the tracker's (D-311). A path that a partial sync missed has no pre-image and no proven absence from before the sync. | review correctness: a user's edit missed by a partial sync is reverted by the next rewind (medium), including the deletion and re-creation variants. | test-ckpt-partial.R: "a partial sync gives no pre-image to an edit or deletion made outside gptr", "a file recreated outside gptr after a proven absence is not undone as created". |
| `0d4850dc` | Links and non-regular entries are flagged only when they replace a captured file. | review correctness: unchanged links and FIFOs are reported as modified on every scan (medium). | test-ckpt-files.R: "unchanged links and FIFOs are not reported by later scans". The existing FIFO-replacement test still passes. |
| `3e79d83e` | Coverage is partial only where a scan stopped early (D-312). The files checkpointer skips R code that can write no file (`ckpt_file_free()`). A per-turn scan runs only after a turn that synced. | review design: every rewind is partial in an ordinary project, including R-only turns (medium). The "Undo anyway?" part of the live report on the once-per-session notice. | test-ckpt-scan-integration.R: "R-only and text-only turns rewind fully in capped and partially scanned projects", "a complete scan with capped captures leaves undo coverage complete", "a real unreadable file is listed without a backup until it can be read". test-ckpt-partial.R: "a complete scan that cannot back up a file keeps coverage and lists its edits". test-ckpt-rewind.R: "R code that can write no file skips only the files checkpointer". |
| `f97cdefa` | On every route, a predicted target that no scan observed gets its state from just before the call (D-313). The section 15 IC-65 and IC-79 text and D-201 now state the bounded rule. | live test: `/undo` on CLI routes leaves Peter's own approved edit and new file in place (high). Review design: section 15 still states the old rules (low). | test-ckpt-partial.R: three CLI-served write cases (unobserved edit, creation, outside the project). test-ckpt-scan-integration.R: the real partial-checkpoint case now edits an unscanned file and creates a new one, and undo names and reverts both. |
| `bc887eae` | The coverage notice is user-facing (D-314). It and the per-turn scan notice are console lines written once per root, never as message conditions, so no tool result records them. Neither is shown while knitting or in a Jupyter kernel. The budget notice is not repeated after a scan that stopped early. | live tests: the notice leaks into Quarto, notebooks and the console (medium); it prints between roster lines and leaks into the parent's tool output (low); it gives the model's advice to the user (low). | test-ckpt-files.R: "the coverage notice is a console line for the person, once per root", "the coverage notice stays out of tool results, documents and notebooks". |
| `540408a1` | `?gptr_rewind`, the vignette and the specs say that unpredicted writes by R code, shell commands and CLIs to unvisited files have no backup. Before, they named only native CLI edits. | review design: docs say only native CLI edits lack a backup (low). | none (documentation only). |
| `e47c6d82` | The internal roxygen describes the tracker fields and fragment shapes. The unused `walk_time` field is dropped. | review design: internal roxygen describes old shapes (low). | the ckpt suites. |
| `94e3c5e8` | tailor-and-coach's precomputed output shows gptr 1.0.1. | review design: version consolidation is incomplete (low). The README and cheat sheet parts were already fixed by `8556ec6d`. | none. |
| `5706b137` | A served edit of a file that a complete scan inventoried without a backup (past the 256-capture limit) is undone on CLI routes too (D-313, amended). Every route now uses `ckpt_as_scanned()`: the target needs its content hash or, without one, its size and mtime, as API routes and 1.0.0 did. #98's content-hash-only rule for `sync = FALSE` is withdrawn. A native edit that changed the file is still recorded by the turn scan without a pre-image. The contract (7.16, IC-79), the architecture (6.16) and D-201 are amended in place. | verification: Peter's own approved edit of a scanned but capture-capped file is still not undone on CLI routes, for projects of 257 to 2,000 entries (medium). | test-ckpt-partial.R: "a CLI-served write to a scanned file without a backup is undone while it is as seen" (with and without a native edit). test-ckpt-files.R: "CLI calls back up an unhashed target only while its size and mtime match the scan". test-ckpt-scan-integration.R: "a CLI-served write to a real scanned file past the capture limit is undone" (300 files, real scan). All three failed before the change (FAIL 7, then FAIL 3 in the real case). |
| `300c7764` | The two adjacent checks for a scan that stopped early in `ckpt_files_observe()` are one block. | verification: two adjacent ifs on the same condition (low). | the ckpt suites. |
| `1989f1ef` | `cran-comments.md` says the checkpoint tests scan in the R session and that the CRAN list has 38 files (test-ckpt-scan-lifecycle.R was removed). | verification: release text still describes the worker and gives 39 files (low). | none. The "all but 12 of the R files" figure was measured on the 35-file list, which the 38 files contain; no R file was removed. |

## Measurements (this machine, load average 20-26)

- In-process baseline of 2,500 small files: the entry limit binds at 2,000 entries in 0.50-0.79 s, and the scan captures 256 files. A one-file project takes 4-6 ms. The #98 worker spent 0.6-0.9 s on start-up alone and could not reach 2,000 entries within 2 s.
- A fake-provider `peter()` with three `r` calls in a small project took 3.6 s end to end, and a full rewind ran with no warning. The review measured 7.56 s on #98 and 3.08 s on main.
- Before the changes, `^ckpt-(files|partial|rewind)$` gave FAIL 97 in this environment, because the workers loaded an older installed gptr or timed out under load. After them, all `^ckpt-` suites pass: FAIL 0, PASS 984.

## Validation

- `isolated-check.R test '^ckpt-'`: FAIL 0 | WARN 0 | SKIP 0 | PASS 984.
- After the follow-up (`1989f1ef`): `^ckpt-` FAIL 0 | WARN 0 | SKIP 0 | PASS 1000;
  `^(cli-claude|cli-codex|mcp-server)` FAIL 0 | SKIP 2 | PASS 1535;
  `^(agent-|session-|subagent-|copy-|injection)` FAIL 0 | SKIP 1 | PASS 4550;
  `^(proc-rscript|arch-|utils-options|windows-|doc-blocks|doc-replay|gptr-capture|eval-core|tool-r|perm-gate|console|rewind|gptr-rewind)`
  FAIL 0 | SKIP 12 | PASS 7213; CRAN mode (`NOT_CRAN=false`) over
  `^ckpt-(scan|partial|rewind|scan-integration|files)$` FAIL 0 | SKIP 45 | PASS 459. The changed R
  and test files lint clean.
- `isolated-check.R test '^(ckpt-|cli-claude|cli-codex|mcp-server)'`: FAIL 0, SKIP 2, PASS 2509.
- `isolated-check.R test '^(agent-dispatch|cli-codex|cli-claude|copy-ckpt|doc-blocks|doc-replay|injection-e2e|mcp-server|session-object|session-usage-durable)$'` (after the coverage change): FAIL 0, SKIP 2, PASS 4367.
- `isolated-check.R test '^(ckpt-|cli-|mcp-|agent-|session-|subagent-|copy-|injection|proc-rscript|arch-|utils-options|windows-|doc-blocks|doc-replay|gptr-capture|eval-core|tool-r$|perm-gate)'` at `94e3c5e8`: FAIL 0 | WARN 0 | SKIP 15 | PASS 11415.
- `isolated-check.R test '^(arch-|ckpt-)'`: FAIL 0, PASS 1028. `proc-rscript`, `windows-link` and `utils-options`, run with the first commit: FAIL 0.
- Every changed R and test file lints clean. `isolated-check.R document` regenerated `man/gptr_options.Rd` and `man/gptr_rewind.Rd` with no stray diff.
- `dev/release/precompute.R --check teams-and-background`: 0 problems. Its paragraph is identical in `.Rmd.orig` and `.Rmd`.

## Deferred

- Finding 23, general part: once-keyed notices in rendered documents. The claude-cli "experimental" paragraph and the `billing_env` notice still reach rendered Quarto output. The suggested rule in `gptr_inform()` would change every notice outside this lane, and it is not clearly right for the billing notice. The checkpoint notices are fixed (D-314).
- Finding 17, child label: the reviewer suggested a sub-agent label on the notice. The notice now names the folder (`File undo covers part of <root>`) and stays out of the parent's tool result. A child label would need the run threaded into the tracker.
- Live report on the once-per-session notice, part 1 (show it once per session): not adopted. The design decision keeps once per root and process.
- Same report, part 3 (make "file coverage" a caveat instead of a failed item): after D-312, the item appears only for file-capable calls and turns whose scan stopped early. There it is a true limit, so it stays a "not restored" item, following #98's conservative intent.
- CI: the `install-source-workers` step that #98 added to `R-CMD-check.yaml` is no longer needed by checkpoints. Other worker tests may still rely on it, so it is left as is.

## For the coordinator (NEWS, not edited here)

The 1.0.1 NEWS bullet (NEWS.md lines 32-35) still describes the worker and must be replaced before
release. `cran-comments.md` is already updated. A suggested replacement:

> Automatic file checkpoints no longer inventory and copy a whole working directory before the
> first response. A scan runs for at most two seconds, inspects at most 2,000 entries and backs up
> at most 256 files within the existing byte limits; a scan that stops early is reported once per
> folder. The files Peter's tools name are still backed up before they change, on every route;
> other changes to unvisited files (computed paths in R code, shell commands, a CLI's own edits)
> cannot be undone automatically. Turns that only run R code on objects or only answer in text
> rewind fully. Folder discovery remains available on demand through `ls`, `find` and `read`.
