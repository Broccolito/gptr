# gptr 1.0.1 fixes, round 2, lane Y: CLI checkpoints and listings (2026-11-03)

Branch `claude/fix2-Y` from `3418f942`. Findings of the live retest (tags rt-ckpt and rt-disc),
each confirmed by a verifier. Decisions D-353..D-355.

## Y-1 - A CLI turn's files are scanned only when it could write files (`fb2624ed`, D-353)
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

## Y-2 - /undo's question lists what it restores (`89632fd7`, D-354)
- Defect: the "Undo anyway?" question listed only the items it could not restore, so a CLI turn
  with an approved edit and a new file in a large project showed the coverage row alone; a file
  to delete previewed as "would be restored".
- Fix: the question lists every plan item, unrestorable first; a removal previews as "would be
  removed".
- Red: ckpt-rewind FAIL 1. Green: `ckpt|console-command` PASS 1266.

## Y-3 - The coverage notice names the folder and says why in plain words (`0dada112`, D-354)
- Defect: the notice printed the absolute project root, which a 120-column console wrapped
  mid-word (`.../live/ho` + `mes/rt-ckpt/big:`), and gave internal reasons ("entry limit").
- Fix: both checkpoint notices name the project folder (its base name); the scan's reasons are
  plain words ("the folder has more than 2,000 entries", "it ran out of time
  (gptr.checkpoint_scan_timeout)", ...).
- Red: `ckpt-scan$|ckpt-files` FAIL 9. Green: `ckpt` PASS 1091.

## Y-4 - Listings keep short columns whole and state first (`753a94ba`, D-355)
- Defect: `listing_print_lines()` never shortened only a named list of state and date columns,
  which missed provider, availability and checked_at; at 120 columns "advertised (stale)" became
  "advertised (..." and "versa-bedrock" "versa-be...", and at 80 columns availability and
  checked_at were only named in "# Other columns".
- Fix: a column whose values fit in 24 columns is never shortened (identifiers never are), and
  provider, availability and checked_at are placed first after the existing provenance columns.
- Red: listing-print FAIL on the flaky (120), codex (80) and versa-bedrock shapes. Green:
  `listing|models|provider|skill|mcp-config|plugin|session-store|session-history|doc-blocks|
  doc-replay|subagent-defs|perm-rules|session-budget|proc-supervise|artifact|utils-text|
  console-commands` PASS 10615.

## Y-5 - The models footer is short (`df46f767`, D-355)
- Defect: the `gptr_models()` footer was about 160 characters (229 with a failed listing): two
  lines at 120 columns and three at 80, one split inside `gptr_models(refresh = TRUE)`.
- Fix: "catalog <date> (<source>), <n> models; refresh = TRUE updates it; advertised does not
  verify access" plus any failure; footers still wrap at word boundaries.
- Red: provider-model-discovery FAIL 3. Green: `provider-model-discovery|models|catalog|listing`
  PASS 704.

## Checks
- Neighbours: `ckpt|cli-|mcp-server|subagent|agent-run|agent-loop|agent-dispatch|console-|session-|
  doc-|eval-|tool-|gptr-child|bench|arch` PASS 17217, FAIL 0, SKIP 8.
- Lint: the 14 changed R files, no lints. `isolated-check.R document`: no diff (only `@noRd`
  comments changed).
- Not run: a live claude-cli or codex retest in a project over 2,000 entries.

## Follow-up after the verifier (D-353..D-355)
- Y-6 (`f91fd3bf`, D-355, supersedes Y-4's rule): never shortening every column whose values fit
  in 24 columns kept `gptr_providers()`'s `api` whole and cut `default_model` and `credential`
  at 80 columns ("google/gemini-3..."), and a source over 24 characters lost its 24-column
  floor. The never-shortened columns are again one named list (identifiers, provenance, state,
  dates), now with provider, availability and checked_at. Red: listing-print FAIL 4. Green:
  the listing regex PASS 10623.
- Y-7 (`4da5af46`, D-353): below auto Codex runs read-only (contract 8.5), yet a shell read in a
  large project still gave the turn a coverage item; a step outside R now marks the turn only in
  auto or yolo. Red: cli-codex FAIL 1 (manual-mode codex_shell). Green: cli-codex PASS 717;
  `ckpt|cli-claude|mcp-server|cli-common` PASS 2251.
- Y-8 (`f1613eec`, D-354): the "Undo anyway?" question lists at most 10 items, then "(+ n
  more)", and items left as is (RNG state, locale) come after the unrestorable ones, before what
  it restores. Red: ckpt-rewind FAIL 4. Green: ckpt-rewind PASS 268.
- Y-9 (`0eb5c523`, D-354): both scan notices quote the folder name ("the project folder "my
  project": ..."). Red: ckpt-files FAIL 2. Green: `ckpt` PASS 1099.
- Not changed: a served write in a large project still reports the coverage row ("some items
  were not restored: file coverage ...", as on the API route), which is the honest D-312/D-314
  statement; a read-only step in auto or yolo (a shell read, a web search) is still scanned
  after, since gptr cannot tell a read from a write; the models footer keeps the short caveat,
  with the full one in `?gptr_models` and the vignette; the dev/DEVIATIONS.md append conflict
  with lane X is a two-block merge.
