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
