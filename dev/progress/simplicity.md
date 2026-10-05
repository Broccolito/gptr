# Simplicity pass (D-135)

Work packages of `dev/progress/simplicity-plan.md`; one short section per package (conventions 11).

## Simplicity DEF-1 - Deferred events during gptr_check() (uncommitted, 2026-10-05)
- Reproduced: during gptr_check() ev_defer() queued into the discarded scratch registry, so a
  session finalized mid-check lost its session_shutdown and kept its live records. Fix:
  `R/ext-events.R` queues into `reg$check_origin %||% reg` (+1 line); `R/ext-check.R` unchanged.
- Red: FAIL 2 (`ext-check`: live session record kept, shutdown hook never ran). Green:
  `ext-check` PASS 258; `ext-` PASS 1661 (+1 test). Lint clean. Neighbours:
  `session-live|gptr-gateway` green.
- Reviews: r1 1 finding (0/0/1: heading format) fixed.
- Deviations: none (restores D-085). Open: none.
