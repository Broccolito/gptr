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
