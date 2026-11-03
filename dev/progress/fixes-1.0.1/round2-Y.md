# gptr 1.0.1 fixes, round 2, lane Y: CLI checkpoints and listings (2026-11-03)

Branch `claude/fix2-Y` from `3418f942`. Findings of the live retest (tags rt-ckpt and rt-disc),
each confirmed by a verifier. Decisions D-353..D-355.

## Y-1 - A CLI turn's files are scanned only when it could write files (D-353)
- Defect: claude-cli and codex scanned every turn (`force = TRUE` at turn_end, `force =
  ckpt_cli_session(s)` at agent_end). In a project over 2,000 entries each scan stopped early and
  returned an empty "partial" fragment, so a text-only or R-only turn's `/undo` asked "Undo
  anyway?", reported "some items were not restored: file coverage" and put a `<rewind>` block in
  the next request.
- Fix: one flag, `dirty`, set by a file-capable call's before() and by an informational
  `tool_execution_start` (a Codex step outside R), cleared by a sync or a per-turn scan; a CLI turn
  is scanned only when it is set.
- Red: ckpt-scan-integration FAIL 3 (CLI route, 2,100 files); cli-codex FAIL 1 (fake Codex text
  case) on the old code. Green: `ckpt` PASS 1087; `cli-codex|cli-claude|mcp-server|cli-common`
  PASS 1875. The IC-65 native-edit tests fail without `local_native_step()` (FAIL 4), so they
  exercise the new hook.

## Y-2 - /undo's question lists what it restores (D-354)
- Defect: the "Undo anyway?" question listed only the items it could not restore, so a CLI turn
  with an approved edit and a new file in a large project showed the coverage row alone; a file
  to delete previewed as "would be restored".
- Fix: the question lists every plan item, unrestorable first; a removal previews as "would be
  removed".
- Red: ckpt-rewind FAIL 1. Green: `ckpt|console-command` PASS 1266.
