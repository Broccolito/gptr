# Live harness validation (2026-10-10)

## Stream block boundaries
- Reproduced incomplete displayed tails, lexical ordering after block 9, and lost cancellation tails with offline normalized provider events.
- Fix: flush completed blocks once, sort remaining indices numerically, and flush safe partial text before cancellation closes its message.
- Red: FAIL 17 / PASS 30. Green: PASS 47; affected agent/console tests PASS 1253, FAIL 0, WARN 0, one CI-only interactive skip. Both files lint clean.
- Independent source review found no blocking defect. No dependency or public API changes.
- Live provider/frontend validation remains in progress; offline evidence does not establish live correctness.

## Reviewed pull request
- PR #5 merged after adaptation and independent review; merge commit `8b93b1e3417ca9a115c608e713f0232903784ddf`. Main synced by fast-forward.
- Adaptation evidence: [pr5-adaptation-20261010.md](pr5-adaptation-20261010.md). Hosted checks are tracked separately; no blanket all-green claim.

## Azure Responses authentication
- Offline red: FAIL 3 / PASS 3: Azure compatibility ignored, and provider record could supply a second auth header. Fix reuses Completions' bound-handle header selection and merge protection.
- Green: Responses/Completions PASS 472, FAIL 0, WARN 0; changed files lint clean. Independent source review clear.
- Authorized live Versa Luna: R-tool `lm(mpg ~ wt + hp)` coefficients and continued `AIC(fit)` match independent R oracles; session idle. Four requests, 8.27 seconds; 9 process samples, peak summed RSS 172 MiB, sampling errors 0. RSS is not GPU/unified memory.
- Actual interactive R terminal also returned correct mean and SD; Ctrl-C pause/continue and streamed multiline text worked. Continuing a pending request lost its indicator until the next request: UI repair in progress.
- This verifies the selected UCSF Versa deployment, not every Azure model or platform.

## Hosted MCP test isolation
- Prior main Windows-release check failed two HTTP request/probe assertions. Deliberately priming a prior URL's legacy-era cache reproduced exactly those failures locally (PASS 164, FAIL 2).
- Test-only fresh user-directory isolation preserves same-fixture reconnect checks. Green PASS 166, FAIL 0, WARN 0; one Windows-only skip locally. Changed test lint clean; production MCP unchanged.

## Waiting feedback
- Live terminal reproduction: resuming a pending request after Ctrl-C lost its indicator; verbosity 1 in Rscript also waited silently before its first tool response.
- Dynamic consoles now draw immediately and restore the spinner after continue, steer or follow-up. It remains active while text is buffered and clears before visible output. Other foreground consoles receive concise stderr feedback; verbosity zero stays quiet.
- Nested tool captures suppress redraws, completion/error removes reactor tasks, and abort-only IDEs advertise their actual stop key. Background notices remove missing bidi/invisible control characters.
- Offline red: FAIL 26 / PASS 28; IDE hint red: FAIL 2 / PASS 54. Green new regressions PASS 56; affected suite PASS 1477; final renderer/interrupt/stream checks PASS 238, FAIL 0, WARN 0, one CI-only interrupt skip. Five changed files lint clean; independent root source review clear.
- Evidence: ignored `dev/.validation/live-20261010/console-wait/`. Revised installed-package live verification is still pending.

## Per-call recording control
- Actual R terminal prompted for a transcript despite `.opts = list(record = FALSE)`. Offline regressions also reproduced writes to a bound document and native System 1 summary blocks.
- Three recording-route guards now honor FALSE. Existing explicit binding consent is preserved; TRUE does not newly grant consent when persistent recording is off. Replay behavior is unchanged.
- Red PASS 594 / FAIL 7. Affected document/capture tests PASS 954, FAIL 0, WARN 0, SKIP 0 (18.0s test time, 19.78s measured wall). Two changed files lint clean; root source review clear. Sandbox denied scheduling-priority and BSD peak-RSS probes for this lane, so no RAM measurement is claimed.
- Evidence: ignored `dev/.validation/live-20261010/record-false-{red,green,lint}.log`. Updated installed-package live verification is pending.

## Console content boundaries
- Synthetic offline before/current comparisons both reconstructed a contiguous registered value from separate text blocks on the console. Canonical `msg_text()` already separated the blocks; this display issue predates the stream-order patch. No real credential was read.
- Console fallback now joins only text blocks with canonical line breaks. Streaming respects distinct content indices and flushes buffered tails before thinking headers, tool lines or pause notices; same-block chunking remains intact. Structural/signed blocks and event deltas are unchanged.
- New plain/styled display and order regressions: red FAIL 11 / PASS 143; green PASS 154, FAIL 0, WARN 0, SKIP 0 (18.6s). Three changed files lint clean. Root reviewed the minimal source diff.
- Evidence: `/private/tmp/gptr-console-boundary-{red,green,lint}-20261010.log` and ignored `cross-block-secret-review.md`. Arbitrarily concatenating separate event or stored fields is not the canonical display contract. Installed-package live checks remain pending.

## Hosted timeout fixture and pause follow-up
- Windows showed a Perl success call inheriting the previous case's one-second timeout mock. The mock is now scoped only around the intentional slow Rscript check; the original Perl success oracle and production timeout remain intact.
- Root pause/wait/bridge follow-up: PASS 210, FAIL 0, WARN 0 (10.7s); four skips cover three unconfigured optional Python bridges and the CI-only interactive interrupt case. Changed bridge test lint clean.
- The separate hosted HTTP wall-bound failure had 6–15ms end-delivery latency and 0.509s response-head spread. No runtime slowdown is established; its serialization threshold remains unchanged while timing evidence is reviewed.

## Installed package and RStudio checkpoint
- Exported committed `4e66376` and installed it into ignored `dev/.library` without changing the user's working DESCRIPTION. Default byte compilation remains enabled. Installation succeeded in 16.14s; 17 process-family samples peaked at 293 MiB RSS with zero sampling errors.
- RStudio 2026.09.0+174 / R 4.5.0 executed the disposable function fixture through its native Source action. Both the `lm(mpg ~ wt + hp, mtcars)` coefficients and the continued session's AIC matched independent R assertions. Two R-tool executions/four provider requests took 6.10s across the two agent calls.
- The initial fixture omitted `.opts` on its continuation and legitimately asked for recording consent after inference. Consent was declined. The corrected disposable fixture uses `record = FALSE` on both calls; an isolated RStudio-console repeat completed with both numerical assertions and no consent prompt (10.35s total; agent calls 3.70s and 6.39s).
- The revised animated thinking indicator was observed directly during the repeat, with elapsed seconds and the correct IDE `Esc to stop` hint. Tool/text lines remained separate and the prompt returned after completion. Private configuration/listeners were cleaned up and R was restarted. Screenshots and metadata are in ignored `runs/rstudio-versa/`; the original Source and repeat timings are separate files.
- This verifies RStudio function/pipeline use with the selected Versa deployment. Native Knit, Quarto, Jupyter, other providers, and live pause/steering/fan-out remain outstanding.
- Resource checkpoint: 127 GiB used, 104 GiB wired, 9% memory free, 57.7 GiB swap used, 119 GiB disk free. One unrelated Ollama runner accounts for about 90 GiB RSS. Keep local jobs serial and defer loading Qwen; do not terminate or reconfigure unrelated sessions.

## Claude CLI quota diagnosis
- Actual `claude-cli/claude-haiku-4-5` function test stopped on HTTP-equivalent status 429. Its three stored assistant errors all contain the same session-limit notice with a future reset; no R tool ran. The original final diagnostic misleadingly said "it reported success" because the CLI used a success subtype alongside an error flag/status.
- Failed-result diagnostics now name the classified failure and retain the provider's result detail when `errors` is absent; explicit errors keep precedence and successful results remain successful. The existing definitive-quota pattern now recognizes the observed "hit your session limit" wording, avoiding the two unproductive agent retries (2s then 4s). Ordinary transient rate limits still retry; informational plan-status events do not terminate turns.
- Diagnostic regressions: red FAIL 15/PASS 27, green PASS 42. Combined narrow quota/result regressions: red FAIL 2/PASS 46, green PASS 48; no failures, warnings or skips on green. All four changed files lint clean. No credential or authentication changes.
- Original live failure: 10.52s, peak process-family RSS 384 MiB, zero sampling errors. Updated installed-package verification and a post-reset inference retry remain pending. This is a confirmed account limit, not model-not-found or authentication evidence.

## Codex HTTP return context
- Actual `codex/default` completed a function turn in 8.65s but its numerical return oracle failed; saved text claimed success without an MCP execution checkpoint. The saved run does not establish whether its fit objects were created. Peak process-family RSS 398 MiB; sampling errors 0.
- Independent real fake-CLI HTTP bridge reproduction confirmed a separate callable-result bug: the fit and coefficient objects were correct, but `gptr_return()` left `session$value` NULL. Served R evaluation lacked the running-tool stack marker used by direct tool execution.
- The served evaluator now marks the token-authorized run on its call stack, preserving function return attribution and nested-call ownership. Red CLI regression FAIL 1/PASS 258; affected CLI/MCP/SDK/architecture checks green PASS 495 with zero failures/warnings/skips (50.5s). Two changed R files lint clean; root reviewed the minimal source diff.
- Post-install live Codex execution remains required; the offline bridge repair does not prove the original live tool path ran.

## Initial document probes and corrected fixtures
- Azure Quarto 1.10.18 rendered the regression through its actual child process: live numerical checks passed and one fresh history block was recorded (7.71s; peak process-family RSS 521 MiB). Strict replay then failed because the fixture put `dat` only in a custom environment while its emitted ordinary R chunk used `dat` in the document's caller environment. The original artifact is retained. Master recordable fixtures now use ordinary caller variables; function-only fixtures retain their separate environment and recording opt-out. The workflow guide states this scope requirement; no replay runtime change was made.
- Jev R Markdown performed the native live decision path, preserving names and correctly returning one TRUE/one FALSE with probabilities 0.98/0.01. The assertion incorrectly compared that named result to an unnamed vector. Master typed fixtures now verify names separately and compare unnamed values. Original run retained; corrected full document/replay rerun remains pending.

## Installed live checkpoint (`d1887f2`)
- Exact committed export installed into `dev/.library` with default byte compilation: 16.87s; peak process-family RSS 322 MiB, 18 samples, zero sampling errors. User DESCRIPTION remains byte-identical to its preserved copy.
- After the reported reset, Claude CLI passed both independent coefficient and AIC assertions in the same session (13.40s; peak family RSS 407 MiB). This verifies the installed return fix with the selected Claude model and account at this time. CLI timing hooks do not expose every MCP tool execution; object existence and numeric return oracles establish the result.
- Codex CLI passed the same function/pipeline assertions (22.22s; peak family RSS 350 MiB). The first-call probe records an idle session, a three-element numeric value, and actual `fit`/`beta` objects. This completes live verification of the served-R return attribution repair.
- Corrected native Jev R Markdown passed logical, choice and score/probability assertions and recorded three fresh blocks (4.03s; peak family RSS 199 MiB). Strict replay passed in 1.63s with the same document MD5 and no request events. The installed external Pandoc 3.12.1 emits its `--mathjax` deprecation warning; package warning classes are empty. This is an external renderer compatibility warning, not a clean-process claim.
- Corrected Quarto child render passed the independent fit/value assertions and recorded one fresh block (7.49s; peak family RSS 499 MiB). A fresh strict replay passed (5.31s; peak family RSS 483 MiB), unchanged document MD5 and zero provider requests.
- Native RStudio Knit rendered the disposable caller-environment regression and displayed its correct coefficients. A fresh strict-replay Knit passed without request events. Child cleanup proofs report restored working directory, options, environment, library paths and binding, with all tracked runs settled (live 5.22s; replay 0.37s). IDE parent environment was separately restored, gptr remained unloaded there, and its workspace is empty. Native process-family profiling includes RStudio and its viewer: 90 samples, peak 1052 MiB, zero sampling errors; it is not agent-only memory.
- Actual JupyterLab 4.6.4 / IRkernel 1.3.2 / R 4.5.0 ran the notebook through Run All Cells with the private vanilla R kernel. Live numeric and fit assertions passed; two requests/one R tool finished in 5.31s including cleanup. All restoration booleans are true. The saved notebook was closed and its owned kernel shut down before external sync; one fresh history block verified. Its 90-sample server/kernel profile peaked at 844 MiB with zero sampling errors.
- Jupyter visual review found normal progress and the successful session result displayed as pink stderr strips, with raw Markdown in the latter. Narrow progress-routing and rich-representation repairs are being developed; strict notebook replay and their installed live verification remain required. Screenshots and run evidence stay in ignored `dev/.validation/live-20261010/runs/`.
- Machine memory free percentage recovered to 73%, but load remains high, swap remains active and disk free is about 120 GiB. Two unrelated GPU models are loaded. Keep local jobs serial and do not unload or reconfigure them to fit Qwen.
