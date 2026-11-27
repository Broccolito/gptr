export const meta = {
  name: 'gptr-compact-calls-fix',
  description: 'Fix the P35 review findings (lint, /calls in full and margin, argument check, doc wording), then check',
  phases: [
    { title: 'Fix', detail: 'one Opus fixer' },
    { title: 'Check', detail: 'lint and targeted tests', model: 'sonnet' },
  ],
}
const LIB = 'R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"'
const fix = await agent(`In your OWN isolated git worktree (current directory), FIRST run 'git reset --hard worktree-wf_29c0ada0-86c-1' (a local branch holding gptr plan P35 'compact tool calls': read dev/plan/P35-compact-calls.md, dev/progress/P35.md and 'git log --oneline -5'). Fix these review findings, smallest change each, tests first where behaviour changes, in one commit 'fix(console): /calls shows calls whole; review fixes (P35)' ending with 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>':
1. Lint: tests/testthat/test-console-render.R line ~858 is 103 characters (line_length_linter, limit 100): wrap it.
2. /calls must show each call WHOLE (the maintainer: "They can always go back to the history to look at the full tool calling"): print every code row with no 20-row cut (do not change the live call block or approvals), and an edit or write call shows what changed (its diff or content rows as the full display would) rather than only the path.
3. /calls rows are indented 2 columns deeper than live rows (the command's own margin is added to the call block's margin): make them line up with live rows.
4. /calls [n]: accept only a positive whole number; '2.5', '0', '-1' and '3 junk' print the usage line; add those cases to the test.
5. Docs wording: where ?peter (R/console-repl.R roxygen -> man/peter.Rd via devtools::document()), vignettes/interactive-console.Rmd.orig (regenerate with dev/release/precompute.R interactive-console), NEWS.md and pkgdown/assets/cheatsheet.html say errors are shown 'in full', say what is true (an error's rows stay, up to six wrapped rows); state that /calls lists this session's own tool calls (not a sub-agent's, and not steps a CLI route ran itself) and shows them whole.
Run under ${LIB}: Rscript --vanilla -e 'devtools::test(filter = "console-commands|console-render|console-ui|gptr-config")', the repository's lint runner on every changed R and test file (Rscript --vanilla dev/ci/isolated-check.R lint <files>), Rscript --vanilla dev/release/check-files.R all, dev/release/check-docs.R, precompute.R --check interactive-console. House rules: '=' and '|>', simplicity first (dev/plan/00-conventions.md section 11). Never write into another worktree; do not push. Final answer: worktree path, branch, commit, exact /calls rendering of a 30-line call and an edit, and the test and lint results.`, { label: 'compact:fix', phase: 'Fix', isolation: 'worktree', schema: {
  type: 'object',
  properties: { worktree: { type: 'string' }, branch: { type: 'string' }, commit: { type: 'string' }, rendering: { type: 'string' }, results: { type: 'array', items: { type: 'string' } }, open: { type: 'array', items: { type: 'string' } } },
  required: ['worktree', 'branch', 'commit', 'rendering', 'results', 'open'],
} })
phase('Check')
const check = await agent(`Independently check the commit ${fix.commit} in ${fix.worktree} (do not edit or commit). Run under ${LIB}: cd ${fix.worktree} && Rscript --vanilla dev/ci/isolated-check.R lint $(git -C ${fix.worktree} diff --name-only 0aeb2662..HEAD -- 'R/*.R' 'tests/testthat/*.R' | tr '\\n' ' '), and Rscript --vanilla -e 'devtools::test(filter = "console-|gptr-config|utils-options|cli-|doc-")'. Report pass/fail counts and every failure or lint exactly; verdict fail if any.`, { label: 'compact:check', phase: 'Check', model: 'sonnet', schema: {
  type: 'object',
  properties: { verdict: { type: 'string', enum: ['pass', 'fail', 'unsure'] }, details: { type: 'array', items: { type: 'string' } } },
  required: ['verdict', 'details'],
} })
return { fix, check }
