# P35 Compact tool calls in the console (2026-11-26)

**Goal:** a tool call takes one row in the console by default, so a long script does not flood the
screen, and the person can still read what runs: the call's name and first line, how many lines
follow, what changed. One setting turns it off, changed as every other setting is, and one console
command shows recent calls in full. An approval always shows the whole code it gates. The
maintainer: "I wanted to make sure that GPTR includes a setting so that the users can toggle it. By
default, it should be toggled on ... only the tool-calling details are shown ... abbreviated
succinctly and elegantly in a way that the users can still somewhat understand what's going on.
They can always go back to the history to look at the full tool calling, so that their screen is
not bombarded with a bunch of code ... Make sure that the settings are there, because all the
UI/UX experiences are consistent with the previous experiences that the users have with changing
items in the settings".

The survey of 2026-11-26 (main 0280d953) found:

| Finding | Where |
|---|---|
| every interactive front end draws calls through one renderer; a multi-line call is its name over at most 20 code rows and `# … +N more lines` (D-207) | `console_on_tool_start()`, `console_call_line()` in `R/console-render.R` |
| what `r` code prints is teed to the console uncapped | `eval_echo()` in `R/eval-core.R` |
| an edit's result is up to 12 diff rows unless its approval showed the change | `console_result_lines()` |
| an approval leaves out its call line when the console printed the call (`last_call`) | `ui_call_shown()` in `R/console-ui.R` |
| a setting is one `rec()` row, changed with `gptr_config(<name> = value, .scope = )`; no console command changes settings | `settings_core()` in `R/gptr-config.R` |
| the full code of every call is kept in `s$messages`, but nothing in the console shows a past call | `msg_calls()`, `path_messages()` |

**Authority:** this plan adds:

| D | Rule | Amends |
|---|---|---|
| D-380 | the core flag setting `compact_calls`, default `TRUE`, read with `setting_get("compact_calls", session)` where the console renders; its option layer is `gptr.compact_calls` | `04` §11.2 |
| D-381 | with `compact_calls`, a call that would expand to code rows is one row: its head, its first non-blank line cut to the width, a dim `(+N more lines)`; an edit's result is `edited <path> · +a -r`; the printed output of `r` code shows at most 5 rows a call, then a dim `(+N more lines)` after the call; with `FALSE` the console is as before | `04` IC-82 (tool calls, printed output) |
| D-382 | an approval of a call drawn compact prints the code rows itself, at most 20 as the call block did; `?` keeps its 40 | `04` IC-77, IC-82 |
| D-383 | `/calls [n]` (default 1) prints the last `n` tool calls of the session from `s$messages`, oldest first, whole | `03` §6.17 |

Next free decision: D-384.

**Depends on:** P34 (branch `claude/v1.3.0`). **Milestone:** 1.3.0 (`DESCRIPTION` already says
1.3.0).

## Global constraints

`dev/plan/00-conventions.md` applies in full: `=` and `|>`, simplicity first (section 11), pure R,
no compiled code, no new Imports or Suggests, offline tests with the fake provider, nothing left
changed. The only new user-facing names are the setting `compact_calls` and the command `/calls`.
No new option table entry, no new exported function.

## Design

### 1. The setting (D-380)

`settings_core()` gains, beside `type_ahead`,

```r
rec("compact_calls", TRUE, "flag",
    "Show tool calls in one abbreviated line in the console; /calls shows them in full.")
```

The generic `flag` validator, the `gptr.compact_calls` option layer, the session, project and user
scopes and the `gptr_config()` print follow from the record. `console_tool_line()` reads it with
`setting_get("compact_calls", session)` (its `compact` argument's default) and `eval_open()` reads
it once per evaluation.

### 2. Compact rows (D-381)

`console_call_line(call, width, kind, compact)`: a call that fits one row today is unchanged. With
`compact`, a call that would expand to code rows is its head, its first non-blank line (a comment
counts; R highlighted as on the one line) cut to leave room for a dim `(+N more lines)`, which
counts the other non-blank lines (`console_more_lines()`, as at verbosity 1). The row carries the
attribute `compact`. MCP and other JSON arguments, a command, a path and a question count stay one
row cut to the width, as now. At width 80:

```text
  ▎ r  library(stats)  (+29 more lines)
    + fit, s
  ▎ write  R/new.R
    wrote R/new.R (230 bytes)
  ▎ edit  R/fit.R
    edited R/fit.R · +1 -1
  ▎ github/search_issues  {"q":"bug","repo":"x/y"}
```

`console_result_lines(..., compact)`: an edit's result is always the one row
`edited <path> · +a -r`, the branch an asked edit takes today. Errors (red, at most 6 rows), object
changes, plot counts, `wrote`, `not run` and the run's status line are unchanged.

Printed output: `eval_open()` sets `st$echo_left = 5` when the setting is on (else `Inf`);
`eval_echo()` writes at most that many rows of a call (output, messages and warnings alike) and
counts the rest; `eval_finish()` writes one dim `    (+N more lines)` row when it counted any. The
tool result the model receives is unchanged.

### 3. Approvals (D-382)

`console_on_tool_start()` records `last_call = c(<session id>, <call id>, "compact")` for a row
drawn compact. `ui_call_shown(request)` returns `"full"`, `"compact"` or `""`. A compact call is not
shown for the ask: `ui_permission_lines()` prints its code rows under the compact row with
`console_code_rows(lines, lang, 20L, width)`, the block today's call line would have drawn, then the
question. The `?` view treats a compact call as shown, since the ask printed the same rows: it
leaves out code that fits 20 rows and shows a longer call's code, at most 40 rows, as today. A
call the console did not draw keeps its one-line call row, as now.

```text
  ▎ r  library(stats)  (+29 more lines)
    library(stats)
    ...                                   (20 rows)
    # … +10 more lines
  ? Allow r?
    y yes · a always (session) · p always (project) · n no · ? more
```

### 4. `/calls [n]` (D-383)

`cmd_calls()` takes `n` (default 1, a positive whole number), collects the `tool_call` blocks of
`s$messages` (`msg_calls()`), and prints the last `n` with `console_tool_line(call, NULL, s,
compact = FALSE, n = Inf)`, oldest first: the full call rows with every code row, then a path
tool's change rows as its approval shows them (`ui_request_change()`), uncut, at the live rows'
column. Before any call it says `No tool call yet.` `/help` lists it with its description.

### 5. Front ends

Verbosity 1 progress lines and verbosity 0 are unchanged. RStudio, Positron, VS Code and Jupyter
use the same hooks, so they get the same rows; a Codex step (`codex_shell`) is already one row.

### 6. Documentation

`?gptr_config` (Choosing controls), `?peter` (the console section), the configuration vignette
(settings table, next to `type_ahead`), the interactive-console vignette (call rows, `/calls` in
the command table), the cheat sheet (config row, `/calls`), NEWS 1.3.0 (`## Console`), contract
`04` §11.2 and IC-82, `03` §6.17, `inst/WORDLIST` if spelling asks, DEVIATIONS D-380 to D-383,
`dev/progress/P35.md`.

## Tasks

Each task: the failing test first (shown red), then the code, then green; lint on the changed
files; one commit with the message given; a progress section in the conventions' format. Tests
that assert expanded rows set `local_gptr_options(compact_calls = FALSE)`; no assertion is
weakened.

- **T1 Plan** (this file, `00-index.md`, `dev/DEVIATIONS.md`). Commit
  `docs(plan): P35 compact tool calls`.
- **T2 Compact rows, output cap, approvals** (design 1-3; `R/gptr-config.R`,
  `R/console-render.R`, `R/console-ui.R`, `R/eval-core.R`, `tests/testthat/test-gptr-config.R`,
  `test-console-render.R`, `test-console-ui.R`, and the tests that assert expanded rows). Failing
  tests: the setting's name, default, validation, layers and print; compact rows of a 30-line and
  a one-line `r` call, `write`, `edit`, an MCP call, a `codex_shell` step and an error; `FALSE`
  giving today's rows; the output cap through a console run; an approval of a compact call showing
  the code rows and its `?` view leaving them out. Commit `feat(console): compact tool calls by
  default (D-380..D-382)`.
- **T3 `/calls`** (design 4; `R/console-commands.R`, `tests/testthat/test-console-commands.R`).
  Failing tests: `/calls` and `/calls 2` on a session with three calls; `/calls` before a call;
  a bad `n`; `/help` lists it. Commit `feat(console): /calls shows recent calls in full (D-383)`.
- **T4 Documentation** (design 6). `devtools::document()`, the two vignettes' `.Rmd` from their
  `.Rmd.orig`, the cheat sheet and its PDF when `dev/release/cheatsheet-pdf.R` runs offline.
  Commit `docs: compact_calls and /calls`.

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| Tests | `devtools::test(filter = "console-\|gptr-config\|utils-options\|cli-codex\|doc-")` | FAIL 0, SKIP 3, PASS 8867 | met |
| Neighbours | `devtools::test(filter = "eval-core\|tool-\|perm-gate\|env-describe\|bridge-sh\|cli-claude\|...")` (16 patterns) | FAIL 0, SKIP 3, PASS 5667 | met |
| Lint | `lintr::lint()` on the changed R files, against the current source | clean | met |
| Files | `Rscript --vanilla dev/release/check-files.R all` | 0 problems | met |
| Vignettes | `Rscript --vanilla dev/release/precompute.R --check configuration interactive-console` | 0 problems | met |
| Live | a terminal, RStudio and Positron console with compact on and off | not run | open |
