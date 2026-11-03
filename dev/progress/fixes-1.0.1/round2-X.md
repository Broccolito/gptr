# Round 2, lane X: hidden prompt commands and plan-mode /mcp serve (gptr 1.0.1)

Branch `claude/fix2-X`, cut from `3418f942` (`claude/v1.0.1`). Findings: retest `rt-mcp` (2
confirmed, 1 low UX). Decisions: D-350 to D-352.

## Fixed

| Finding | Commit | Test |
|---|---|---|
| `/SKIP`, `/Skip` and `/CANCEL` stored as the API key at the hidden prompt (medium); a padded `/skip` or a capitalised command kept as a text answer | 0d250957 | test-auth-setup.R "/skip and /cancel at the hidden prompt ..." (store unchanged), "ordinary text questions can be submitted, skipped and cancelled"; D-350 |
| Plan-mode `/mcp serve` refused every `r` call, `value + 1` included (medium) | ee3ee881 | test-mcp-server.R "a fork's served calls evaluate in its overlay; a plan-mode parent stays in plan" (reads run, nothing is kept, writes refused); D-351 |
| The refusal advice "run it yourself or add a rule with gptr_permissions(allow = ...)" on every denial, false for plan mode and level 4 | 1928fa36 | test-mcp-server.R "a served refusal offers what a person can do ..." (advice and console notice); D-352 |
| Plan mode called an outside-project read "this change" (low) | 1928fa36 | test-perm-gate.R "plan mode says a read outside the project is no change (D-352)" |

## Evidence

Red before green for each fix (the new assertions failed on `3418f942`, see the commit order).
Focused filters pass: `auth-setup`, `mcp-server`, `perm-gate`, `perm-plan`, `mcp-waits`; the
neighbouring groups `mcp`, `perm`, `auth`, `agent-dispatch|agent-run|agent-loop`,
`console|tool-r|tool-ask`, `northstar|gateway|security|plan` all pass with 0 failures. Lint is
clean on the changed files, `isolated-check.R document` leaves no stray diff beyond
`man/gptr_mcp_serve.Rd`, and the spelling check is clean.

## Deferred

- `?gptr_mcp_serve` has the plan-mode sentence; the MCP vignette (`mcp.Rmd.orig`) and the
  `/mcp serve` banner still say only "calls that need approval are refused". Rebuilding the
  vignette needs `precompute.R mcp`.
- The case-insensitive command match covers the two places that match `/skip` and `/cancel`.
  Slash commands of the REPL (`/HELP`) stay lowercase-only, and `/cancel now` stays an answer.
