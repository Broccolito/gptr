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
