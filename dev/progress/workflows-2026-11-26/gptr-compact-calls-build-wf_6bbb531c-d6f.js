export const meta = {
  name: 'gptr-compact-calls-build',
  description: 'Implement the default-on compact_calls console setting and /calls, then verify it with tests, a pty console and a review',
  phases: [
    { title: 'Implement', detail: 'one Opus implementer in the compact worktree' },
    { title: 'Verify', detail: 'tests, live pty rendering and review', model: 'sonnet' },
  ],
}

const LIB = 'R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"'

const BRIEF = `You implement gptr plan P35 "Compact tool calls in the console" in your own isolated git worktree (your current directory). FIRST run 'git reset --hard claude/console-compact-calls' there (a local branch of this repository, equal to claude/v1.3.0: gptr 1.3.0 in progress; DESCRIPTION already says 1.3.0 and NEWS.md has a '# gptr 1.3.0' heading; another campaign's P34 and decisions D-372..D-379 exist; you take P35 and decisions D-380 upward). Work ONLY in your worktree; never write into another worktree.

The maintainer's request (2026-11-26): "Currently, the way GPTR calls tools or calls any R code is that it will expand all the code, R code, scripts, or whatever it writes, which is fine. I wanted to make sure that GPTR includes a setting so that the users can toggle it. By default, it should be toggled on unless the users want to toggle it backwards. When this setting is on, only in abbreviated R code or any sort of script implementations, only the tool-calling details are shown. Everything is shown in a very abbreviated manner. It's abbreviated succinctly and elegantly in a way that the users can still somewhat understand what's going on. They can always go back to the history to look at the full tool calling, so that their screen is not bombarded with a bunch of code running and just getting flushed every time with a large chunk of code. Please provide that setting and leave that, by default, toggled on. Make sure that the settings are there, because all the UI/UX experiences are consistent with the previous experiences that the users have with changing items in the settings, etc."

Research findings (verified on main 0280d953; full notes in /private/tmp/claude-501/compact-research.txt — read it first):
- One renderer for every interactive front end: console_on_tool_start / console_on_tool_end in R/console-render.R; a call is drawn by console_tool_line() -> console_call_line() (~:886); code is cut at 20 rows with '# … +N more lines' (console_code_rows ~:870, D-207); verbosity 1 already prints 'gptr: r  <first line>  (+N more lines)' (console_more_lines, D-187). write shows only the path; edit prints a diff of up to 12 rows as its result, or 'edited path · +a -r' when its approval already showed the change (call$asked, console_result_lines ~:977-1028). The r tool's printed output is teed UNCAPPED by eval_echo() (R/eval-core.R ~:284-317). Approvals rely on the printed call block: ui_permission_lines() skips its own call line when console_state()$last_call equals the request (ui_call_shown, R/console-ui.R ~:241-303; last_call set at console-render.R ~:1316).
- Settings: one rec() row in settings_core() (R/gptr-config.R ~:33-105) gives validation, the gptr.<name> option layer, session/project/user scopes and gptr_config() printing; type_ahead is the console-UI precedent (read by setting_get('type_ahead', s)). There is NO console command that changes settings; settings are changed with gptr_config(<name> = value, .scope = ...). The full code of every call is kept in s$messages (tool_call arguments) and the session JSONL, but nothing in the console shows it again.

Design (decided; implement exactly, smallest code):
1. Setting (D-380): rec("compact_calls", TRUE, "flag", "Show tool calls in one abbreviated line in the console; /calls shows them in full.") in settings_core() beside type_ahead; read with setting_get("compact_calls", session) where the console renders, never through a separate option table entry.
2. Rendering when compact_calls is TRUE (D-381): every call that today expands to code rows renders as ONE row: the existing head ('▎ r' etc.) plus the first non-blank line of its code or command (comments count as lines; cut to the width) plus a dim '(+N more lines)' when there are more (reuse console_preview()/console_more_lines()); MCP and other JSON arguments stay one row cut to the width; write keeps 'wrote path (N bytes)'; edit's result is always the one-row 'edited path · +a -r' (the existing asked branch) instead of diff rows; errors keep their current rows in red; object-change rows ('+ fit, s'), plot counts and the end-of-run status line stay. The teed printed output of r code is capped at 5 rows per call, followed by one dim '(+N more lines)' row after the call finishes (the model still receives the full output as today). When FALSE, today's output is reproduced byte for byte.
3. Approvals never hide what they gate (D-382): when a call was drawn compact, the approval prints the full code itself (as ui_permission_lines does for a call it did not see: do not treat a compact call line as 'shown'), bounded exactly as today (the ask and the '?' detail view keep their row limits).
4. History (D-383): a console command /calls [n] (default 1) re-prints the last n tool calls of the session in full (the code or arguments from s$messages, rendered with today's full call rows, oldest first), registered beside the other commands with a one-line description, listed by /help, and named in the compact row's documentation. No other new command or option.
5. Non-interactive and other front ends: verbosity-1 progress lines and verbosity 0 are unchanged; Jupyter, RStudio, Positron and VS Code use the same hooks and get the same behaviour; Codex route codex_shell rows follow rule 2.

Process: write dev/plan/P35-compact-calls.md first (format of dev/plan/P33-undo-large-objects.md: Goal quoting the maintainer, Authority table D-380..D-383, tasks, acceptance table) and add its row to dev/plan/00-index.md; add D-380..D-383 entries to dev/DEVIATIONS.md (conventions section 11 format); then test first: tests in tests/testthat/test-gptr-config.R (name list, default, validation, layers/print like the undo/type_ahead tests), test-console-render.R and test-console-ui.R (compact rows for a multi-line r call, a one-line call, write, edit, MCP, codex_shell, an error, the output cap, FALSE reproducing old rows, an approval of a compact call still showing the full code), test-console-commands.R (or wherever commands are tested) for /calls; update existing tests that assume expanded rows by turning compact_calls off locally in those tests (session scope or withr::local_options(gptr.compact_calls = FALSE)) — do not weaken assertions. Then code. Docs in the same change: roxygen of gptr_config() ('Choosing controls' or the settings list) and of peter() where the console is described, then devtools::document() under the dev library; vignettes/configuration.Rmd.orig (settings table next to type_ahead) and vignettes/interactive-console.Rmd.orig (where call blocks are described; mention /calls), regenerated to .Rmd with 'Rscript --vanilla dev/release/precompute.R configuration interactive-console' under the dev library; the cheat sheet (pkgdown/assets/cheatsheet.html: the config row and the console paragraph) and its PDF only if dev/release/cheatsheet-pdf.R runs offline here; NEWS.md: a '## Console' section under '# gptr 1.3.0' (pure ASCII); inst/WORDLIST if spelling flags new words; dev/progress/P35.md (conventions format). Run and report: ${LIB} Rscript --vanilla -e 'devtools::test(filter = "console-|gptr-config|utils-options|cli-codex|doc-")'; lintr::lint on changed R files; Rscript --vanilla dev/release/check-files.R all; Rscript --vanilla dev/release/precompute.R --check configuration interactive-console. House rules: '=' and '|>', simplicity first, no new Imports/Suggests, no compiled code, offline tests, never leave options/env changed. Commit one commit per task with conventional messages (e.g. 'docs(plan): P35 compact tool calls', 'feat(console): compact tool calls by default (D-380..D-382)', 'feat(console): /calls shows recent calls in full (D-383)', 'docs: compact_calls and /calls') each ending with 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'. Do not push. Final answer: commits, exact renderings (ANSI stripped) of a 30-line r call, a write, an edit, an MCP call and an approval in compact mode and the same r call with compact_calls = FALSE, test counts, and anything not verified.`

const IMPL = {
  type: 'object',
  properties: {
    worktree: { type: 'string', description: 'absolute path of your worktree' },
    branch: { type: 'string' },
    commits: { type: 'array', items: { type: 'string' } },
    renderings: { type: 'string' },
    tests: { type: 'array', items: { type: 'string' } },
    not_verified: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['worktree', 'branch', 'commits', 'renderings', 'tests', 'not_verified', 'summary'],
}

const VERDICT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail', 'unsure'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, detail: { type: 'string' }, evidence: { type: 'string' } },
        required: ['severity', 'detail', 'evidence'],
      },
    },
    summary: { type: 'string' },
  },
  required: ['verdict', 'findings', 'summary'],
}

phase('Implement')
const impl = await agent(BRIEF, { label: 'compact:implement', phase: 'Implement', schema: IMPL, isolation: 'worktree' })
const WT = impl.worktree

phase('Verify')
const VCOMMON = `Verify the compact_calls work in the worktree ${WT} (the implementer's branch ${impl.branch}; read dev/plan/P35-compact-calls.md and 'git -C ${WT} log --oneline claude/v1.3.0..HEAD' and the diff). Do not edit or commit anything; work only under /private/tmp/claude-501/ for scratch. The implementer reported: ${JSON.stringify(impl).slice(0, 6000)}`
const checks = await parallel([
  () => agent(`${VCOMMON}\n\nRun the FULL offline test suite of the worktree and report failures exactly: cd ${WT} && ${LIB} Rscript --vanilla dev/ci/isolated-check.R test '' (if that runner needs a filter, run devtools::test() whole instead, with NOT_CRAN=true). Also run lintr::lint_package() or lint the changed files, Rscript --vanilla dev/release/check-files.R all, and Rscript --vanilla dev/release/check-docs.R. Report pass/fail counts and every failing test with its message. verdict fail if anything fails.`, { label: 'verify:suite', phase: 'Verify', schema: VERDICT, model: 'sonnet' }),
  () => agent(`${VCOMMON}\n\nLive-check the console in a REAL pseudo-terminal: install the worktree into a scratch library (R CMD INSTALL --no-docs -l /private/tmp/claude-501/compact-lib ${WT}), then drive an interactive R in a pty (python3 pty or the 'script' command, or the tests' local_pty_r helper approach in tests/testthat/helper-*.R) with the fake provider (see tests/testthat/helper-*.R for how tests script fake turns) so peter() makes: a 30-line r call that prints 40 lines, a one-line r call, a write, an edit, an error, and, in manual mode, an approval of a multi-line r call; then type /calls and /calls 3 and /help. Do it twice: default settings, and gptr_config(compact_calls = FALSE, .scope = "session"). Capture the screen text (strip ANSI) at widths 80 and 40 and with NO_COLOR=1 and an ASCII locale (LANG=C) once. Check: compact rows are one line each with '(+N more lines)', output capped at 5 rows plus a count, approvals show the full code, /calls prints full calls, FALSE restores the old full rows, nothing overflows the width, no stray escape codes. Report exact captured text for each case.`, { label: 'verify:pty', phase: 'Verify', schema: VERDICT, model: 'sonnet' }),
  () => agent(`${VCOMMON}\n\nReview the diff (git -C ${WT} diff claude/v1.3.0..HEAD) as a strict gptr maintainer: correctness (every tool kind and front end, approvals never hide gated code, FALSE reproduces old output byte for byte, the output cap counts lines right including partial lines and very long lines, /calls with no calls, n larger than the count, sub-agents and fan-outs, the Codex route), consistency with how other settings behave (gptr_config print, scopes, option layer, docs), simplicity (conventions section 11: no redundant code, helpers or tests; reuse existing helpers), house style ('=' and '|>'), docs accuracy vs code (vignettes, roxygen, cheat sheet, NEWS), and test quality. Report findings with file:line evidence; verdict fail if any blocker or major.`, { label: 'verify:review', phase: 'Verify', schema: VERDICT, model: 'sonnet' }),
])
return { impl, checks }
