export const meta = {
  name: 'gptr-compact-calls-research',
  description: 'Research for a default-on setting that shows tool calls in the peter() console in a compact, abbreviated form',
  phases: [
    { title: 'Research', detail: 'three read-only investigations', model: 'sonnet' },
  ],
}

const RULES = `READ-ONLY research for the gptr R package (worktree /Users/wgu/Desktop/gptr/.claude/worktrees/gptr-console-compact, branch claude/console-compact-calls = main 0280d953, gptr 1.2.0). Do not edit, create or delete repository files; no commits, pushes or PRs. Never print or copy credentials. Do not change the user's real Claude Code or Codex configuration. Cite evidence as path:line or URL and quote exact rendered console text where it matters. R must run as 'Rscript --vanilla' with R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"; you may run pkgload::load_all() of this worktree and the fake provider (see tests/testthat/helper-*.R) in a scratch session to render real console output, writing only under /private/tmp/claude-501/.`

const SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    facts: {
      type: 'array',
      items: {
        type: 'object',
        properties: { topic: { type: 'string' }, detail: { type: 'string' }, evidence: { type: 'string' } },
        required: ['topic', 'detail', 'evidence'],
      },
    },
    recommendations: { type: 'array', items: { type: 'string' } },
    open_questions: { type: 'array', items: { type: 'string' } },
    confident: { type: 'boolean' },
  },
  required: ['summary', 'facts', 'recommendations', 'open_questions', 'confident'],
}

const GOAL = `The maintainer wants a setting, ON by default, under which the peter() console shows tool calls (R code the agent runs, shell/Python/SQL via peter$ members, file writes and edits, scripts, MCP tools, sub-agent calls) in an abbreviated, succinct and elegant form that still tells the user what is going on, instead of expanding every line of code; the full calls stay available in the history. Turned off, today's full display returns. The setting must behave exactly like gptr's other settings (how they are defined, shown, changed in the console and from R, documented).`

const TASKS = [
  {
    key: 'rendering',
    prompt: `${GOAL}\n\nMap exactly how the console renders a tool call today. Read R/console-render.R in full and the other R/console-*.R files that draw tool calls (console_record(), the tool-call/approval/result rows, code highlighting, output truncation such as r_output_tokens and line caps, the live row, P28's Codex-style layout and P30's steering lines), and find every tool kind's rendering path: the r tool (code and its printed output, plots), peter$sh/py/sql/script/bg/knit/app, write/edit/read (diffs?), grep/find/ls, MCP tools, sub-agents and fan-outs, approvals that show the code they gate (an approval must keep showing the full code it asks about — note where), errors and tracebacks. Also the non-console front ends that print calls: RStudio console, Positron, Jupyter, knitr/Quarto documents, Rscript/non-interactive runs, background sessions, and gptr's own Claude Code/Codex routes (do they render calls the same way?). Render real examples: with pkgload::load_all() and the fake provider, drive a peter() run that makes a long r call, a sh call, a write and an edit, and capture the exact console text (strip ANSI) for each; list where long code is already cut, if anywhere. Then find how the user can see the full history of a run today (session object members such as gptr_last()$..., print methods, transcripts, documents, any console command like /history, /transcript or a key binding) and whether that history holds the full code of each call. List the tests that pin console rendering (tests/testthat/test-console-*.R, snapshots under _snaps/) that a compact mode would touch.`,
  },
  {
    key: 'settings',
    prompt: `${GOAL}\n\nMap how gptr settings work end to end, so a new display setting can follow them exactly. Read the settings core (grep R/ for settings_core, rec(, setting_get, gptr_config): how a setting is declared (type, default, description, layers: options gptr.<name> and dotted fields, project vs user config, environment), validated, shown by gptr_config() (print format), changed from R (gptr_config(<name> = ), options()), changed in the console (find every console command that shows or changes settings, e.g. /config, /settings, /mode, /model, /permissions and any picker UI, and how they persist changes), and documented: ?gptr_config, ?gptr_options (the options collection), vignettes/configuration.Rmd.orig, the cheat sheet (find its source under dev/ or pkgdown/), NEWS conventions. Use P33's D-370 'undo' setting and P28's/P30's console settings (e.g. type_ahead) as worked examples: list every file a recent display-related setting touched (git log -p for those commits) so the new setting can touch the same set. Find existing display settings or options (verbosity, colours, NO_COLOR, output lines, r_output_tokens, doc_output_lines) and say whether the compact display should be a new core setting or a field of an existing one, under the simplicity rule (one general mechanism, no redundant options). Report exact names and the tests that pin settings (test-gptr-config.R, test-utils-options.R, docs checks in dev/release).`,
  },
  {
    key: 'reference-design',
    prompt: `${GOAL}\n\nResearch how the reference agents abbreviate tool calls, to inform an elegant design that fits gptr's Codex-style console (minimal, no boxes or frames, logo glyphs: '>' chevron, thin red strip for System 1, blue block for System 2; palette ink #1c1e22, cream #f3f1ec, red #b85450, blue #6c8ebf). Codex CLI 0.157.1 (/opt/homebrew/bin/codex) and Claude Code 2.1.323 (/opt/homebrew/bin/claude) are installed: use their docs and source (github.com/openai/codex codex-rs/tui: exec cell rendering, 'Ran', 'Explored', command summarisation, output line limits, transcript overlay Ctrl+T; Claude Code docs on tool display, 'ctrl+o'/'ctrl+r' expand, verbose mode, the /config 'verbose' setting) to describe exactly what each shows for a long shell command, a multi-line script, a file edit (diff summary like '+12 -3'), a file read and a search, and how the user expands or reviews the full call later. Do not run prompts that cost tokens. Then propose 2-3 concrete compact formats for gptr's r tool (multi-line R code), peter$sh, write/edit and MCP calls — e.g. first meaningful line plus '… +N lines', a one-line semantic summary derived without model calls (the call's top-level function names and assigned names, which gptr's risk classifier and checkpoint 'created=' headers already compute), result as one status line — with exact sample renderings, and say which needs no new heuristics (the maintainer dislikes hard-coded rule lists; reuse what gptr already parses: risk classification, changed objects, created names).`,
  },
]

phase('Research')
const results = await parallel(TASKS.map(t => () =>
  agent(`${t.prompt}\n\n${RULES}`, { label: `compact:${t.key}`, phase: 'Research', schema: SCHEMA, model: 'sonnet', agentType: 'general-purpose' })
    .then(r => ({ key: t.key, result: r }))
))
return { done: results.filter(Boolean) }
