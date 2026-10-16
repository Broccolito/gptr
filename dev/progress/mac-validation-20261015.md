# Mac validation checkpoint — 2026-10-15

The exact current package candidate K is `2bf18595f65030ed8d253ef5cbd4ccc173d95205`
in `/Users/wgu/.codex/worktrees/mac-final-integration/gptr`. Its three focused fixes
(history comment wrapping, concise tool descriptions and checkpoint-test startup)
now pass the combined normal build/install and full as-CRAN check. Release notes
are coordinated separately in `/Users/wgu/.codex/worktrees/release-validation-notes/gptr`
so active GUI checks keep their original source unchanged. Only excluded release
metadata changes there; the 667 public package inputs must remain byte-identical.
PR6 is draft/unmerged. Submission preparation is underway; no CRAN submission or
release has occurred. Frozen J and older evidence remain separately identified.

This is a timestamped checkpoint. The operational ledger at
`/Users/wgu/Desktop/gptr/dev/.validation/readiness-20261011/host-r-reinstall-20261015/PLAN.md`
records subsequent running/completed/queued/blocked transitions and exact private
outputs. A prepared packet or a passed check for a different artifact is not acceptance.

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
| K normal build/install | Accepted: archive **2,660,769 B**, installed **7,012,965 B**, Rdb **5,046,506 B**, documentation **1,729,695 B**, data **0 B**. All 667 public inputs, 121 R files, 14 guide pairs, 64 exports, 80 read-only files/20 inclusive directories and five MD5s match. Three phases/owned cleanup and five raw logs pass; 46.508 s, 497.359375 MiB, 34 valid samples/0 errors. Default byte compilation retained. |
| K full as-CRAN check | Accepted **Status OK, zero errors/warnings/notes**: 30,643 passing assertions, 446 accounted skips (421 On CRAN/25 specific), all 59 examples and 15 quiet raw logs. Whole 491.329 s, 2,187.625 MiB, 417 valid samples/0 errors; 98 sampled owned identities absent, four protected identities unchanged, no signals. Keep-source installation 10,099,974 B/Rdb 8,141,788 B; displayed 10.6 Mb is INFO. This does not imply native Windows or R-caller-all-eight acceptance. |
| K standard user installation | Ordinary `library(gptr)` passes from the standard library; all four phases/all-eight/W0/cleanup pass. Eight existing dependencies and all 402 non-gptr entries/root identity remain unchanged; no downloads. Whole 19.226 s/333.625 MiB/20 valid samples. User package 7,007,800 B/Rdb 5,046,404 B is explicitly distinct from the private normal profile. |
| K plan and site checks | Four plan stages pass: 770 R blocks/0 parse-style problems, 746 inputs/0 lints; existing 90 static WARN/822 INFO/0 ERROR retained. Whole 111.411 s/1,149.09375 MiB/94 samples. Hosted K plan independently passes. Site five phases/89 staging assertions/9 controls pass: 265 assets/123 HTML/3,706 links/822 fragments, 77.965 s/774.734375 MiB/72 samples. All 14 guides, CSS and logos match J; 20 generated differences are exhaustively explained. Local build is not deployed-site or new GUI acceptance. |
| Optional HTML dependency follow-up | Separate binary overlay supplies 10 missing packages, including Plotly/DT, without changing the sealed 139-package library. Installation all-eight/W0 passes. Original focused shiny-html tests now pass 69 assertions/0 failures/warnings/skips, resolving the missing-Plotly skip. Historical 520-pass/one-skip benchmark remains unchanged; this is not a new full browser benchmark. |
| K Qwen steering comparison | Separate context="names" comparison passes two user turns, exact transformed input/model frame/numeric result and same-session history. Four requests/10,236 known tokens stay within the original budget. LIVE 23.549 s, R peak 180.625 MiB; external Ollama RSS peak 15,397.96875 MiB/API model size 19,597,076,220 B, below the original 32 GiB cap; actual 32,768-token context and one permitted cold-start catalog timeout recorded. Fresh replay makes zero requests/usage/native rows. All-eight/W0/source/parent/cleanup pass. Raw `<-` remains a model-style qualification; the earlier context="none" input-fidelity failure is retained. |
| Current native client continuation | Jupyter J executed all seven cells/tool42, saved all MIME forms and passed all 13 GUI predicates, but its final gate remains NONPASS due an upstream legacy heartbeat-unit warning. The private all-route client correction passes all 25 offline controls; fresh K browser run is awaiting local sign-in. Code J/K prebody routing failures remain NONPASS with zero R input; a supported private accessibility configuration is source-reviewed and still unrun. No frontend pass is inferred from these preparations. |
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

## Running, queued and blocked at this checkpoint

- **Complete:** K normal build/install, genuine as-CRAN check, standard-user loading,
  four source-plan stages, hosted plan gate and current local pkgdown rebuild.
  The three focused successors are now covered by combined K checks; historical
  clock/network/raw warnings and failed fixtures remain retained.
- **Running:** fresh K Jupyter browser test after a private client compatibility
  correction. Human local sign-in is required; no credential value is read or
  copied. Original seven cells, all 13 GUI predicates, warning, state and cleanup
  gates remain unchanged. Its final result belongs in the operational ledger.
- **Queued:** source-reviewed Code terminal/editor runs with two supported private
  accessibility settings. Exact PID/birth/executable/private profile/nonce/window
  ownership and original 180/150-second bounds remain mandatory. Original routing
  failures are not R-test passes; no unowned window receives input.
- **CI:** preceding J retains its token-budget failure. K passes all unchanged local
  token budgets with 19 fewer tokens. Required hosted CI and Windows artifacts
  await final-head readback; no cancellation, baseline relaxation or bypass.
  Historical Windows oldrel4 timing failures remain beside the deterministic
  test-only correction and its passing local reproduction. Hosted CI does not
  replace final live Windows verification.
- **Qualifications:** Quarto functional output passes, while its framework closure
  serialization drift reproduces without gptr and remains recorded. The separate
  Qwen context-names steering/replay comparison passes; it does not erase the
  earlier failed model instructions or guarantee future model behavior.
- **Delivery:** review final-head checks, merge PR6 only after required gates,
  synchronize main safely and verify actual public Pages publication and links.
  Keep local GUI evidence distinct from deployed-site verification. Final live
  Windows verification remains last after Mac integration and native checks.

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

- **K normal:** `H/normal-final-K-prepared/CONSUMER-ACTUAL-ACCEPTANCE.json`, SHA256 `64c2527680dbda851d2af95e4697b56897d5a56c6a500f4650623e8d48818015`; certificate `41529ac3cf80f7d93aecb5cb4dc38aa37374a530ef1faa6aeeec515e4474756f`; Root receipt `0d827beed30dbfd489f176cc198b7e36aaf55154ad8b907fa97906bdf9718de8`.
- **K full check:** `H/cran-check/cK/peer/PR5-K-C1-FULL-AS-CRAN-ACTUAL-ACCEPTANCE.json`, SHA256 `223252d12968855c66fe69dc3bdef54ba423811eb8e0df95260391390a2f8e74`.
- **K user installation:** `H/default-install-final-K-prepared/ACTUAL-ACCEPTANCE.json`, SHA256 `c0731264c1cf73b4412f9957e34c736c0b6fbbaf3f2f42398a81ffd3e24306e0`.
- **K plan/site:** `B/plan-crosschecks-final-K-prepared/ACTUAL-ACCEPTANCE.json` (`1a6a910f3935ff6d331f8f07d90ea55ecd37045f174330c8b6bb70b81e81fc8a`); `B/current-2bf1859-delivery/pkgdown-prepared/PKGDOWN-2BF1859-ACTUAL-LOCAL-ACCEPTANCE.json` (`8e3fa4c235d934a26f328108c4eb8edc79813d7c231fbc13ee7aa89271ba4c21`).
- **K Qwen:** `H/model-smoke/qwen-context-names-K-prepared/QWEN-CONTEXT-NAMES-K-LIVE-REPLAY-ACTUAL-ACCEPTANCE.json`, SHA256 `447fbfe9850c53f0ed147280dfdb632af1da7c489b318cd1ad9297b5c2c4227f`.
- **Optional HTML tests:** `H/plotly-overlay-prepared/FOCUSED-SHINY-HTML-ACTUAL-ACCEPTANCE.json`, SHA256 `922c903b428c4437a0834c3bb95dfb75d6235d236570cb1f7b83b63a51538294`.
- **CRAN/hosted timing scope:** `B/current-2bf1859-delivery/CRAN-VS-HOSTED-TIMING-SCOPE.json`, SHA256 `28dc9f2d8d475b5626a1b0ddf32eb0f08f46f187b8bfd7e9690b24d0395e8948`.
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
