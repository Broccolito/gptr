# P30 Visible steering: receipts at send, answers under their question (2026-11-02)

**Goal:** What the person sends while peter works stays in the transcript, at once, and reads as
the person's message, never as an answer or as the agent's output. The maintainer reported on gptr
1.0.1: "when users steer, the steering text does not stay in the session: after Enter it just goes
away; it is hard to tell the user's steering text from the agent's output; when the terminal
flushes, the steering text does not stay." Reproduced the same day (terminal, RStudio, Jupyter):
the T console showed a sent steer only on the live row, which is gone while an in-process `r` call
runs, then printed it at the step boundary as `› <text>` at column 0 on the band, the same glyph,
column and band as an approval's answer `› y`; on the CLI routes it showed only after the CLI's
whole answer. RStudio's live row said `esc pause · typed lines run next`, a typed line vanished
until it ran as the next prompt, and a question's text left stale live rows in its transcript.

**Authority:** the design below (decided by the maintainer's agent, refined here) amends IC-76,
IC-82 and the D-242/D-243/D-245 text of 04 section 15.10 in place; decisions are D-301 onward.

**Depends on:** P28 (merged). **Milestone:** 1.0.1, before CRAN submission.

## Global constraints

`dev/plan/00-conventions.md` applies in full: `=` and `|>`, simplicity first (section 11), no new
Imports, pure R, offline tests with the fake provider, nothing left changed. The console principles
of P28 hold: Codex-style, minimal, CLI only, no boxes, frames or ornament, the logo's glyphs and
palette, nothing unstable, a clean degrade in RStudio, R.app, Positron, Windows Rterm and Rgui,
TERM=dumb, `NO_COLOR` and `cli.unicode = FALSE`. Wire messages to the model (the steer relay) and
the session's queue items do not change; documents keep recording what was delivered (IC-55).

## Design

1. **Receipts at send.** A message the person sends while a run goes (the composer's Enter and
   Tab, a D console's line, a line a question read past, the pause menu's `s` and `f`, a chat
   prompt to a session running in the background) is written at once as the person's row at
   column 0 on the input band: `steer> <text>` (to the agent at its next step boundary) or
   `next> <text>` (after this answer), the word mirroring the prompt `peter> `, the text escaped
   and wrapped under itself; a steer on a CLI route adds a dim `(after the CLI's answer)`. It goes
   between whole rows: the live row is cleared and drawn again, a streamed answer's held row
   continues after it (D-245), as a block of the person's lines.
2. **No duplicate at delivery.** Items from the sources that always show a receipt (`repl`,
   `pause_menu`) print nothing when the loop takes them; `pipe` and `api_user` items (a pipe into a
   running session, `gptr_steer()`) print their row then, `steer> <text>` (`next> ` for a
   follow-up). A follow-up held for the next prompt is echoed as that prompt, `peter> <text>`.
3. **Live row while queued:** the count only, `1 steer queued`, `1 follow-up queued`, `2 queued`,
   and with an empty draft `↑ edit` where Up takes something back. Up writes a dim
   `↳ steer taken back` (`follow-up`), as the draft holds the text again.
4. **Answers under their question.** Every read that answers a question (approval, choice, text,
   secret, the pause menu's key) reads at `  › ` (ASCII `  >> `), two columns in, under the
   question's `? `; column 0 on the band is only ever a message to the agent. The pause menu's `s`
   and `f` read their text at `steer> ` and `next> ` themselves: the line read is the receipt.
   A secret's read shows nothing typed. The draft-kept rule stays.
5. **Consoles without a composer.** Where only the pause menu steers (RStudio, Positron) the live
   row says `<key>, then s, to steer`, in RStudio with `typed lines run after this answer`; the
   banner says it once.
6. **Live row around questions.** A question's rows clear the live row first in every console, and
   every read of the console (`gptr_readline()`) clears it before reading, so no row is drawn
   between a question and its prompt, nor left behind where a written row cannot be erased.

## Tasks

Each task: the failing test first (shown red), then the code, then green; the console filter and
lint on the changed files; one commit with the message given.

- **T1 Receipts at send, none at delivery** (design 1, 2; `R/console-interrupt.R`,
  `R/console-repl.R`, `R/console-render.R`). `console_receipt()` replaces `console_queue_line()`;
  `policy_enqueue(shown = )` names the kind whose receipt is on screen; the held-row machinery
  (`rec$queued`, `the$echoed`) goes. Acceptance: Enter in a T console writes `steer> <text>` with
  the live row up; a steer sent while text streams is written before the paragraph's next row; a
  `repl` item's take prints nothing, an `api_user` item's take prints `steer> <text>`; Up writes
  `↳ steer taken back` under the receipt; plain and ASCII consoles show the same words without the
  band. Commit
  `feat(console): write a steer's receipt when it is sent`.
- **T2 The live row counts what is queued** (design 3; `R/console-input.R`). Acceptance:
  `1 steer queued   ↑ edit`, `2 queued`, no queued text on the row. Commit `feat(console): count queued messages on the live row`.
- **T3 Answers under their question** (design 4; `R/console-ui.R`, `R/console-interrupt.R`).
  Acceptance: approvals, choices, text and secrets read at `  › `; the pause menu's `s` reads at
  `steer> ` and its line is the only receipt. Commit
  `feat(console): read answers under their question`.
- **T4 Steering where no composer reads keys** (design 5; `R/console-input.R`,
  `R/console-repl.R`). Acceptance: RStudio's row ends `esc, then s, to steer · typed lines run
  after this answer`; its banner names the way. Commit
  `feat(console): say how to steer where typing cannot`.
- **T5 No live row around a question** (design 6; `R/utils-options.R`, `R/console-render.R`).
  Acceptance: a shown row is cleared before `gptr_confirm()`'s question and not drawn again before
  its answer; a console question clears it without a foreground record. Commit
  `fix(console): keep the live row off a question`.
- **T6 Contract, decisions and documents.** IC-76/IC-82 and the D-242 text in 04 section 15.10,
  D-301 onward, `?peter`, the interactive-console vignette (`.Rmd.orig` and its precomputed `.Rmd`),
  `NEWS.md`. Commit `docs(console): describe visible steering`.

## Review round (2026-11-02)

The reviewers' findings on the branch, each verified against the code; a failing test first, then
the fix, one commit each.

- **R1 TERM=dumb answer prompt** (`R/utils-options.R`): macOS libedit drew `y` over `  › ` where
  the quiet prompt's hidden `\r\033[K` came first. The hidden part follows the leading blanks and
  steps over them. Acceptance: a pty in TERM=dumb shows `  › y`. Commit
  `fix(console): keep a TERM=dumb answer after its indented prompt`.
- **R2 Take-back notice** (`R/console-input.R`, `R/console-interrupt.R`): `↳ steer taken back ·
  <text>`, a block of the person's lines (`console_person_write()`, shared with receipts), in the
  console's colours. Acceptance: Up as text streams leaves the paragraph's rows whole, the notice
  between blank rows. Commit `fix(console): write a take-back as the person's block, naming the
  text`.
- **R3 CLI note on the pause menu's steer** (`console_receipt(shown = )`). Commit
  `fix(console): say a pause-menu steer on a CLI route waits for its answer`.
- **R4 `!code` at `steer> `**: the note `(runs after this answer)` in place of a second receipt;
  an empty line's bare `steer>` row is accepted (D-303). Commit
  `fix(console): one receipt for !code read at the pause menu's steer>`.
- **R5 Chat steer into a background session** (`R/gptr-gateway.R`): source `repl` for a console
  turn, so its take writes nothing again. Commit
  `fix(console): queue a chat steer into a running session as the console's`.
- **R6 Unspaced wide text** (`console_person_rows()`): a word wider than a row breaks at its
  width. Commit `fix(console): break unspaced wide text in a receipt under the text`.
- **R7 Windows' Rterm** (`console_typed_fate()`): the banner, `/help` and the live row say how to
  steer there. Commit `fix(console): say how to steer in Windows' Rterm`.
- **R8 Documents**: 03 and 04 passages still describing queue lines and `› ` at column 0; the
  pause keys per console in `?peter` and the vignette; re-wrapped prose; D-301, D-303, D-304.
  Commit `docs(console): record the steering review fixes`.

## Plan acceptance

`isolated-check.R test '^console'` and `'^(doc-|agent-run|agent-loop)'` with no failure; lint
clean on the changed files; `document` leaves no diff; a tmux check (100x34, the fake provider of
the steering repro) shows the receipt at Enter, during the `r` call and none at delivery, and a
manual-mode approval reads at `  › `; captures under the session's
`live/captures/steer-impl/`.
