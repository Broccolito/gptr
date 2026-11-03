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

## Verifier follow-up

| Problem | Commit | Outcome |
|---|---|---|
| A nested `peter$sh`, `bg` or `script` in a plan-mode served `r` call was refused with the false "plan mode needs a scratch environment for r" (medium): `mcp_nested_gate()` built its literal `r` call without the call's `envir` | 4496ab29 | Fixed: the gate gets the served call and gives the literal its `envir`. test-mcp-server.R "a plan-mode served r call runs a nested read-only sh call; a writing one is refused" (`echo`, `ls`, `cat` run; `touch`, a computed `touch`, `script` are refused; no file is made); D-351 |
| "plan mode reads inside the project only" was false for a protected file inside the project and for the `r` tool's level-1 reads beyond it (low) | fcc1ae91 | Fixed: the wording claims no boundary, "plan mode does not run this read: describe what you need from it in your plan instead of reading it". test-perm-gate.R "plan mode says it does not run a read, never that the read is a change (D-352)" (the `read` tool beyond the project and on `.env`, an `r` network read; a write keeps the general wording); D-352 |

Not changed: an `r` call that reads a secret (`readLines('.env')`, category `secret`, level 3)
keeps the general wording. A secret is also a hand-over to a child process, so the category is not
a pure read, and the branch stays the one exact case (`categories` is `read`) rather than a list.

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
