# Mac validation checkpoint — 2026-10-15

Root owns tracked integration. Current release-candidate
source J is `bc13abaa51738310c5e9d40efd9fe11276e8d313` in
`/Users/wgu/.codex/worktrees/mac-release-candidate/gptr`. J adds one packaged Shiny
skill clarification to frozen I `7c3d92c0290a47c2f519bfbab3ec532f2ef5d6f5`:
use `=` for assignment, `|>` for data transforms and `+` for ggplot2 layers.
All 121 R files, 14 vignettes and 64 exports are unchanged from I. J normal
build/install, full as-CRAN check, genuine Shiny history and ordinary user installation
are accepted, including the new app browser interaction. Root integrated three tested
successors: readable history comments, tool-description token savings and deterministic
checkpoint-test startup timing. Their combined successor build/check remains pending.
PR6 is draft/unmerged; no release
or CRAN submission has occurred.

Root owns dependencies, shared documents, Git and dispatch; Fast alone owns GUI.
Use separate private sessions/output paths, at most four families/12 GiB declared
caps, normally CPU 1, with at most two internally parallel jobs/12 workers.
Admit heavy/GPU overlap only after current CPU, memory/swap, disk and thermal
checks. Original resource, security, warning, caller-state and cleanup gates remain.
Preserve unowned processes and shared models. No prepared or historical receipt
becomes current merely through a metadata rebind.

## Completed and qualified actuals

| Scope | Current result and limits |
| --- | --- |
| J normal build/install | Accepted: archive **2,659,416 B**, installed **7,010,625 B**, Rdb **5,044,726 B**, doc/help/html **1,729,155 B**, data **0 B**. All 667 current public inputs, 121 R files, 14 exact guide pairs, 64 exports, 80 read-only files/20 inclusive directories and five MD5s match. Five raw logs are quiet; default byte compilation/final loading and three natural-zero phases/owned cleanup pass. Whole **43.471 s**, sampled peak **527.90625 MiB**, 35 valid samples/0 errors. Outer build/install 22.104/15.105 s; inner R build/install 20.470/14.274 s. Controller output peak 41,312,784 B and CSV peak 52,741,580 B remain distinct, both below 512 MiB. No caller-R all-eight or full-check claim is inferred. |
| J full as-CRAN check | Accepted **Status OK, zero errors/warnings/notes**: 30,600 passing assertions, 446 accounted skips (421 On CRAN/25 specific), all 59 examples, all 15 raw logs quiet. Whole 474.206 s, sampled peak 2,120.171875 MiB, 411 valid samples/0 errors. All 105 sampled owned identities are absent; all four protected identities unchanged, no signals. Keep-source installation 10,097,097 B/Rdb 8,139,173 B; displayed 10.5 Mb is INFO. This J result does not erase I's actual incoming-network warning or establish Windows/native-browser acceptance. |
| History comment wrapping | Integrated focused fix: long generated raw-prompt metadata wraps at 80 characters and reconstructs the exact escaped literal. Actual RED six expected failures; GREEN 211 passing assertions, zero failures/warnings/skips, parsing/two-file lint clear; 7.189 s/252.375 MiB. Separate actual re-export of immutable genuine J history passes: 24/8 metadata lines, maximum 79 characters, lossless prompts; Peter bytes and raw executable AST unchanged. Fresh raw replay and six numeric/image cases pass with zero provider requests/warnings and all-eight/connections/cleanup restored. Whole 8.317 s/501.234375 MiB, 8 valid samples/0 errors. This source-level result is not final-installed-package acceptance. |
| Checkpoint timing fixture | Actual deterministic RED reproduces six failures/483 passes with 0.55-second synchronous startup. Minimal test-only correction admits startup before the existing timed in-flight waits. GREEN 506 passes/0 failures/warnings/skips, syntax/lint clear; 11.948 s/250.6875 MiB/13 samples, owned cleanup. Original 0.04/0.2/0.3/0.8/1-second bounds and correctness/identity/accounting/fallback assertions remain; four checks strengthen admission and once-only injection. No product runtime changed. Historical Windows latency cause is not proved and current hosted/live Windows acceptance remains separate. |
| Tool token budget | Three concise schema descriptions save 19 actual o200k tokens while retaining literal skill-path/line guidance; behavior, schema structure, baselines and tolerances remain unchanged. Actual namespace 403 passes, two-file lint clear, all 14 golden/4 static prefix gates, seven-task polyglot and original INFRA gate pass (29 files/1,096 tests, 14.4 s counted INFRA <60 s). First development-test run retains a temporary-directory ancestry failure: its TMPDIR was inside another checkout. Fresh unchanged test-only execution with an owned external TMPDIR passes 520 assertions/0 failures/warnings/1 missing-plotly skip in 17.070 s/783.546875 MiB. The optional dependency follow-up uses a separate overlay; sealed libraries stay unchanged. |
| I full-check retry c2 | Formal `Status: OK`, child/controller 0; **30,600 passing assertions, 0 failures/test warnings, 446 accounted skips** (421 On CRAN/25 specific), all 59 examples completed. Whole **556.119 s**, sampled peak **2,121 MiB**, 482 samples/0 errors; reported input/parent/cleanup guards pass. **Qualified raw output:** incoming feasibility emitted a real 60-second CRAN `packages.rds` timeout warning inline before continuing OK. The inherited anchored matcher missed this line; do not call the complete raw output warning-free. Independent sealing verifies all 106 sampled owned identities absent and all four protected identities unchanged; no process was signalled. This checks I, not J. |
| I first full-check c1 | Retained **NONPASS before installation/tests**: incoming-feasibility `archive.rds` receive-from-peer/read-connection failure and `Execution halted`; only two of 15 required logs existed. No test result was obtained. c2 changed only the fresh output path; no source, runner, nomination, cap or oracle changed. |
| I four plan tools | Index/extract/parse/lint pass: 770 R blocks/0 parse-style problems, 746 lint inputs/0 lints; original 912 findings retain 90 static WARN/822 INFO/0 ERROR. Current 43 source/ordered 39 witnesses/external 257, parent and cleanup match. 108.870 s/1,145.125 MiB, 97 valid samples/0 errors. This I source-only result is not a new J run or R-caller state claim. |
| I documentation site | Static build/map accepted; actual local GUI accepted representative 320/768/1440/1920 viewport layouts, light/dark, navigation, MCP/reference content and independently observed **native Chrome 200%→100% zoom/DPR 2→1**. Recorded documents have no page overflow; long code scrolls locally. Owned tab closed, prior window/theme/viewport restored. Viewport overrides are not physical-window resize evidence; not every page/example/external link/native console was tested. **Unpublished:** local preview is not public deployment acceptance. |
| I genuine Shiny history | Original live NONPASS retained. Separate zero-provider continuation passed public Peter/raw exports, parsing/comments, two fresh history blocks and fresh raw replay; durable v2 bytes match. The original numerical oracle then rejected replay-derived **v1** because `geom_point()` received a ggplot object through `|>` rather than `+`; v2/raw-v2 numeric checks were not reached and no GUI opened. Actual original v1 hook capture was not durable; derived v1 is replay evidence. Final all-eight/W0/connections and outer cleanup pass only for the stated continuation scope. |
| J Shiny history/replay | Two genuine turns, durable version-one/version-two captures and public Peter/raw exports pass. All three original numeric children validate 150/30 rows and images; fresh raw replay makes zero model requests. Six genuine requests used 27,438 known tokens; monetary costs are unknown. LIVE 25.094 s/372.69 MiB and replay 3.770 s/310.06 MiB; all-eight, post-bootstrap connections, W0 and owned cleanup pass. New app browser interaction remains separate. |
| J saved-app browser | Accepted original numeric/authentication/interaction predicates and actual GUI: 150/50/30 rows, keyboard 34→30, restored 150; responsive 320/768/1440 layouts, native 200%→100% zoom and keyboard table scrolling. GUI receipt at 215.706 s is within both 240-second target and 300-second lease. Whole 233.442 s/1,079.140625 MiB/206 valid samples, zero provider requests/usage; all-eight/W0/source/input/parent/owned cleanup pass. Owned tab closed and prior window restored. Native-title tool transcript briefly included the local authenticated URL; no bearer was copied into evidence/messages, and server settlement invalidates that temporary access. The receipt retains this operator qualification. No successor-artifact/native-Windows equivalence is inferred. |
| J standard user installation | All four phases pass; fresh ordinary `library(gptr)` loads from the standard library. Eight existing dependencies and the full non-gptr tree/root identity remain unchanged; no downloads. Whole 19.290 s/333.5 MiB, 20 samples/0 errors, all-eight/W0/cleanup. User package 7,005,790 B/Rdb 5,044,626 B differs from private normal build due to its installation profile; all 14 guide pairs match the archive. |
| J local site rebuild | All five phases/89 assertions/9 controls pass; 265 files, 123 HTML pages, 3,706 links and 822 fragments. Whole 76.522 s/793.125 MiB, 71 samples/0 errors. All guide pages, CSS and logos match the separately GUI-tested I site; generated metadata/IDs/order account for the remaining delta. This is not public deployment or a new GUI acceptance. |
| Saved Shiny and earlier native scopes | Model-free **f5** saved-v2 GUI remains accepted separately: 247.333 s within the original 300-second lease; whole 265.082 s/1,084.59375 MiB, full raw-native quietness/final state/cleanup. RStudio AX-v3 and R.app v3 scoped positives remain; neither proves every frontend capability. The f5 PTY proves actual default ANSI/120→80→120, completion, pending Ctrl-C/recovery, errors/tool output and all-eight/connections/W0; six sparse samples are not continuous RSS. These receipts are not relabeled J-native passes. |
| Original source and model/workflow evidence | Fresh R 4.6.1 **44a** five-batch result remains 200 files/4,210 cases/33,418 assertions/44 accounted skips; all-eight/full connections/captured-wrapper W0/cleanup pass. The direct test-owned process warning remains qualified. Later changes have focused evidence, not a new J five-batch run. The f5 model/workflow index retains in-memory 4 GiB, scientific/raw replay, integrations/extensions, storage, compaction/resume and overlapping-worker scopes; recovered tool errors/one prediction warning/unknown costs and synthetic-data limits remain explicit. |
| Size | Default byte compilation, useful debugging/security metadata and local docs remain. The installed **5 MB goal is unmet**. Prior finite audits found no further demonstrated safe reduction or exact installed duplicate. Historical keep-source check size, Windows size NOTES and the slower rejected no-bytecompile trial remain separate. Request CRAN consideration; do not conceal size or infer a J keep-source measurement from normal install. |

## Running, queued and blocked

- **Final successor check queued:** J passed the original full as-CRAN route with
  incoming checks enabled. Integrate and test the three focused fixes, then rebuild
  and rerun combined checks from the settled successor. I transport/timeout outcomes
  remain visible; twelve matcher controls retain inline warning detection.
- **J browser complete:** model-free interaction with the newly generated app passed
  the original 300-second authenticated lease and numeric/accessibility predicates.
  Genuine history/replay and source-level wrapped re-export remain separate scopes.
- **CI running/successor queued:** J required CI retains its actual token-budget
  failure. The integrated successor passes the unchanged local budgets with 19 fewer
  tokens. Current Windows jobs await readback. Historical f5 oldrel4 failed six
  ordinary checkpoint-timing assertions; its native child-process/security witnesses
  passed. The deterministic local reproduction and test-only correction now pass.
  Hosted checks do not
  establish live Windows acceptance; remaining Mac work is still open.
- **Human/client prerequisites:** VS Code terminal/editor needs exact-owned-window
  Accessibility interaction. ChatGPT and Codex Computer Use are visibly enabled;
  actual private-window access still needs testing. The fresh Jupyter server/login
  is running; the user was prompted for local sign-in, with no token content read.
  Expired/authentication-failed pages and headless IRkernel execution do not count
  as authenticated notebook GUI acceptance. Do not bypass either prerequisite.
- **Other frontend qualifications:** functional Quarto output remains positive while
  its own serialized closure changes, also reproduced without gptr. Qwen steering
  retains its original input-fidelity NONPASS; numerical/replay and other provider
  positives do not remove it. Final client/history acceptance is limited to exact
  receipts, not a universal slash/settings/interrupt or provider claim.
- **Delivery after gates:** finalize review and permitted PR6 merge, synchronize main
  safely, verify the accepted standard-user installation and publish pkgdown from
  the accepted source. Verify the actual public site and links. Final live Windows
  verification remains last after Mac integration; hosted CI is a separate gate.

The full 13-guide requirement matrix remains in `dev/TESTING_PLAN.md`; the package
contains 14 guides. Primary `/Users/wgu/Desktop/gptr` stays dirty/preserved; frozen J and
f5 remain separate from the coordinator checkout. Native ARM64 R 4.6.1/R.app 1.83 and the 139-package private profile
are verified. Original-Mac reinstall/cleanup passed; backups remain exclusively on
`/Volumes/WD_BLACK/gptr-r-backup-quiescent-20261015`. Do not rerun the installer.
Submission preparation is underway, not submitted or accepted.

## Exact evidence pointers

B = `/Users/wgu/Desktop/gptr/dev/.validation/readiness-20261011`;
H = `B/host-r-reinstall-20261015`. Hashes below identify immutable scope, not a
new audit or acceptance of every linked platform/model.

- **J normal:** `H/normal-final-J-prepared/CONSUMER-ACTUAL-ACCEPTANCE.json`, 22,305 B, SHA256 `c5ec9038e26e6195ad298b0447575fc0e7e205711716e44d9fa83bbf98f2e226`. Its output is `runs/bc13abaa51738310c5e9d40efd9fe11276e8d313-root-normal-1`; certificate `4e565d51f4354ec8894b170e6c3b054de301a4e7cb4f356e25ca0b8aacc159e0`; Root acceptance `d2ab4def07a7ea0ffe8ce148becf766d19b75ba40fccaa1efa9ff5f09ba0fdeb`.
- **J full check:** `H/cran-check/cJ/peer/PR5-J-C1-FULL-AS-CRAN-ACTUAL-ACCEPTANCE.json`, 17,237 B, SHA256 `3c1573d9f22a27a58da171aa3cb41f2392e2dda17be0bc6b75806d25035a6d5d`.
- **History successor:** `H/history-comment-wrap-source-only/ACTUAL-SCOPED-ACCEPTANCE.json`, SHA256 `1ed6306e9beed4902b1d3ebf5bc104dd704d26de6def8c7c81088d97eed6eee5`; `H/history-comment-wrap-J-offline-prepared/OFFLINE-J-REEXPORT-ACTUAL-SCOPED-ACCEPTANCE.json`, 18,461 B, SHA256 `2df667e61c173fced2d9f0bab2955b8a21c3db62fd2da555b77e62e36ee40bc1`.
- **Checkpoint successor:** `H/windows-delayed-checkpoint-source-audit/GREEN-ACTUAL-READBACK.json`, 6,621 B, SHA256 `08ca512d4a97990a210c3eac5cb52815b41dfea7af631c03999003714a5f3674`; the same directory preserves the actual RED, source comparison and historical-failure limits.
- **Token successor:** `H/token-benchmark-bc13-diagnostic/ACTUAL-ACCEPTANCE.json`, 17,666 B, SHA256 `45b375a03caec2849f55e02827ff6c0093afeead98c24c290497f7b11cb84fdf`.
- **I c1/c2:** `H/cran-check/cI/runs/c1/check-readback.json` (`6e49dfa39745ff5ee39a9340b45ec214d2446d3813f550a8a40329d7098a3255`); `runs/c2/check.log` (`a10a6fe8bedeb2121c903e0deb96f37ff24c0ca74c798e7c23eaa8c1eaea91a4`) preserves the inline timeout; `runs/c2/controller-summary.json` (`e0d50a7d4f4da8b8520c14bf739fc24a858bd4443f9b9a907872eb4a2e224091`). Final qualified peer: `H/cran-check/cI/peer/PR5-I-C2-FULL-AS-CRAN-QUALIFIED-ACTUAL.json`, SHA256 `1c32ca05daad355494701c95ab6df70b023551f0bed1cfd13a9c91e062bb0a5a`.
- **I plans:** `B/plan-crosschecks-7c3-final-I-prepared/ACTUAL-ACCEPTANCE.json`, SHA256 `b0867d9082894afa80ea0fca7df161d13d5dcc2d241852eb4ac29894ed26a8df`.
- **I local site GUI:** `B/current-7c3d92c-delivery/pkgdown-prepared/preview-prepared/SITE-VISUAL-ACTUAL.json`, 8,334 B, SHA256 `2d9de21f74eed732c765cd353c2fcf7fac194ff515faa73db6762ab864354aa8`.
- **I Shiny downstream NONPASS:** `H/shiny-history-final-I-head-downstream-prepared/FINAL-I-RECORDED-DOWNSTREAM-ACTUAL-NONPASS.json`, 16,228 B, SHA256 `8926150acd79937c15d6dfb978daa56be5be09edecaf0adb087b17a1d6d7fae8`; original live receipt is linked there. J successor acceptance: `H/shiny-history-final-J-operative-prepared/FINAL-J-SHINY-HISTORY-LIVE-REPLAY-ACTUAL-ACCEPTANCE.json`, SHA256 `0ab683b82577ea4a24208e8f086307f655f6d2012a385bcbfb42a4bc9d83ffc8`.
- **J saved-app browser:** `H/shiny-history-final-J-operative-prepared/J-SAVED-GUI300-ACTUAL-ACCEPTANCE.json`, 45,732 B, SHA256 `8adf68a45a4657241d9b8632fdc4a5fa2f86a966a61bdb152db3527b7d5696f1`.
- **Historical f5:** `H/shiny-next-final-rebind-prepared/F5-SAVED-GUI300-ACTUAL-ACCEPTANCE.json` (`76174e3f…`); `B/native-pty-f5f389c-r461-completion-bound-prepared-v2/ACTUAL-SCOPED-ACCEPTANCE.json` (`b3d5a91d…`); `H/remaining-installed-f5/FINAL-F5-MODEL-WORKFLOW-ACTUAL-INDEX.json` (`63b7c5d7…`).

Latest actual statuses are recorded above; queued/running rows are not acceptance.
Preserve original failures beside separately tested successors; do not infer a pass
from source preparation, a process exit alone or a receipt for another artifact.
