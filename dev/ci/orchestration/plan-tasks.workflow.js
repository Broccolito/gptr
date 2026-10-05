export const meta = {
  name: 'gptr-plan-tasks',
  description: 'Execute gptr plan tasks sequentially: TDD implement, independent verify/review, fix, commit, periodic push',
  whenToUse: 'Run one gptr implementation plan (or a slice of its tasks) end to end with review gates',
  phases: [
    { title: 'Implement', detail: 'TDD implementer per task (red, implement, green, lint, progress log)' },
    { title: 'Review', detail: 'independent reviewer re-runs tests and audits the diff against plan and contract' },
    { title: 'Fix', detail: 'address blocker/major/minor findings, re-verify' },
    { title: 'Commit', detail: 'stage exactly the task files, commit with the plan message, push periodically' },
  ],
}

const A = args
const RUN = "R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R"
const SCRATCH = A.scratch || "/Users/wgu/Desktop/gptr/dev/.validation/scratch"

const COMMON = `
Repository: /Users/wgu/Desktop/gptr (git branch main; work directly on main; never create branches or worktrees).
Validation runner (always use it; it isolates HOME/config/cache/credentials before package load):
  ${RUN} test '<filter>'      # one testthat filter (regex), e.g. '^catalog-models$'
  ${RUN} lint <file> [<file> ...]
  ${RUN} document
Save raw logs under dev/.validation/${A.plan}/ (ignored by git), e.g. '> dev/.validation/${A.plan}/task<id>-green.log 2>&1'.
The startup line "package 'testthat' was built under R version 4.5.2" is a harmless notice, not a test warning.
Authority when texts disagree: dev/spec/04-interface-contract.md (section 15 IC-32..IC-73 wins over earlier sections; IC-74 = dev/spec/07-local-ollama.md overrides older plan literals and exact PASS counts) > dev/spec/03-architecture.md > dev/spec/05-plan-decomposition.md > plan literal code > plan expected counts. dev/plan/00-conventions.md wins over a plan unless the plan names the exception.
Plan file: ${A.planFile}. Plan-wide context to read: ${A.contextRanges}. Progress log for this plan: ${A.log}.
House rules (CLAUDE.md, enforced by lint): assign with '=', never '<-'; pipe '|>' never '%>%'; ASCII-only sources; pkg::fun(); no ':::' in R/; no withr in R/; cli_*() calls take a literal first argument; never write .GlobalEnv; restore options/env/wd/seed; tests offline (fake provider, mock servers, local_mocked_bindings); never read, print, or copy anything in .secrets/; no new Imports/Suggests; no compiled code; no R LLM packages, no httr2.
SIMPLICITY FIRST (maintainer's priority; CLAUDE.md, dev/plan/00-conventions.md section 11): build the smallest design that meets the contract and the task's acceptance; no redundant code, helpers, wrappers, options, comments or text; reuse existing helpers; prefer one general conservative rule (fail closed) over many special cases; keep evidence notes in progress logs and DEVIATIONS short and factual. NAMING: the main entry point is peter() and its namespace peter$... (D-135); older spec/plan text that says gptr()/gptr$ means peter()/peter$ once the rename has landed (check whether R/ defines peter yet: until the coordinated rename commit lands, keep using the current names).
Processes: a sandbox "Operation not permitted" from ps/process signalling is environmental, not a code failure. Never signal unrelated processes. Use at most 2 cores for heavy jobs.
${A.extraContext || ''}`

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    files: { type: 'array', items: { type: 'string' }, description: 'every repo-relative path this task created or modified, including progress logs, DEVIATIONS.md, NAMESPACE/man files' },
    test_filters: { type: 'array', items: { type: 'string' } },
    red: { type: 'string', description: 'actual red result line and what the failures were' },
    green: { type: 'string', description: 'actual final green result line(s)' },
    lint: { type: 'string' },
    commit_message: { type: 'string', description: 'the conventional commit subject the plan gives for this task' },
    adaptations: { type: 'array', items: { type: 'string' } },
    blocker: { type: 'string', description: 'if blocked: exactly what is needed (maintainer decision, missing tool, etc.)' },
  },
  required: ['status', 'files', 'test_filters', 'red', 'green', 'lint', 'commit_message', 'adaptations'],
}

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['clear', 'changes_required'] },
    tests_rerun: { type: 'string', description: 'the result lines you observed when re-running the focused filters and lint yourself' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          location: { type: 'string' },
          problem: { type: 'string' },
          scenario: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'location', 'problem', 'fix'],
      },
    },
  },
  required: ['verdict', 'tests_rerun', 'findings'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    files: { type: 'array', items: { type: 'string' } },
    addressed: { type: 'array', items: { type: 'string' } },
    declined: { type: 'array', items: { type: 'string' }, description: 'findings not changed, each with the reason (e.g. reviewer misread the contract)' },
    green: { type: 'string' },
    lint: { type: 'string' },
    blocker: { type: 'string' },
  },
  required: ['status', 'files', 'addressed', 'declined', 'green', 'lint'],
}

const COMMIT_SCHEMA = {
  type: 'object',
  properties: {
    sha: { type: 'string' },
    committed_files: { type: 'array', items: { type: 'string' } },
    pushed: { type: 'boolean' },
    note: { type: 'string' },
  },
  required: ['sha', 'committed_files', 'pushed'],
}

function implPrompt(t) {
  return `You are the IMPLEMENTER for gptr plan ${A.plan} Task ${t.id}: "${t.title}". Implement this ONE task only, test-first, and record actual evidence.
${COMMON}
Read before editing:
- dev/HANDOFF.md, dev/PROGRESS.md, dev/DEVIATIONS.md (current state; earlier decisions)
- dev/plan/00-conventions.md
- ${A.planFile}: ${A.contextRanges}
- ${t.planFile || A.planFile} lines ${t.range}: THIS task (authoritative steps, literal test and source code, commit message)
- The contract/architecture sections the task cites, plus dev/spec/07-local-ollama.md where the task touches providers, models, usage, decisions or locality.
- ${t.log || A.log} (earlier tasks' decisions in this plan) and the plan's Self-review "Contract ambiguities" rows for this task.
Task-specific notes from the coordinator: ${t.notes || 'none'}

${A.early ? `EARLY LANE PRECHECK (mandatory, before editing anything): this plan runs ahead of its declared dependencies. Read the task and list every function, service, hook, option or file from OTHER plans that its tests or source call. Grep R/ to confirm each exists (exact name). If any is missing and the task's tests cannot be satisfied without it (the plan's own skip guards for not-yet-available services count as satisfiable), return status 'blocked' immediately WITHOUT editing any file, naming the missing items. Never stub another plan's function.
` : ''}Process:
1. Run 'git status --short' and 'git log --oneline -5'. Do not modify, revert or stage unrelated uncommitted changes.
2. Write the task's tests as the plan gives them. Adapt only where the contract/IC-74 or the ACTUAL already-implemented interfaces (read the real R/ sources) require it; record every adaptation with its reason.
3. RED: run the focused filter(s); confirm the failures are the expected missing-implementation ones rather than fixture mistakes (fix fixture mistakes first, then re-run red). Prefix with testthat::set_max_fails(Inf) behaviour - the runner already does this.
4. Implement the source as the plan gives it, reconciled with the contract. Use the real interfaces of earlier plans (grep R/). No placeholders or stubs for future tasks, no lint suppressions, no weakening of tests to make them pass.
5. GREEN: re-run until [ FAIL 0 | WARN 0 ]. Record the actual counts; explain any difference from the plan's expected count (historical; IC-74 may change them).
6. Lint every R/test file you touched (zero lints). If roxygen/exports changed, run the document action and include NAMESPACE/man changes.
7. Run the test filters of neighbouring areas your change could affect, to catch regressions; fix regressions you caused.
8. Record evidence in ${t.log || A.log} as ONE section in the short format of dev/plan/00-conventions.md section 11 (at most ~8 lines: '## Task ${t.id} - ${t.title} (YYYY-MM-DD)', then '- Red: ... Green: ... Lint clean. Neighbours: ... green.', '- Reviews: ...', '- Deviations: D-nnn or none. Open: ... or none.'). No narrative, no per-round counts, no dev/.validation paths. Add a D-nnn entry (section 11 format, at most ~12 lines; take the next free number at the moment of writing: grep -o '^## D-[0-9]*' dev/DEVIATIONS.md | sort -t- -k2 -n | tail -1) only for a meaningful contract-visible or behavioural deviation.
9. Do NOT commit, push, stash, reset or clean. Leave all changes in the working tree.
If you cannot proceed without a maintainer decision, a missing tool/package, network access, paid/live calls or credentials, stop and return status 'blocked' with the exact need (do not fake it).
Return the structured result; 'files' must list every path you created or modified (repo-relative).`
}

function reviewPrompt(t, impl, round) {
  return `You are an INDEPENDENT REVIEWER (round ${round}) for gptr plan ${A.plan} Task ${t.id}: "${t.title}". You did not write this code. Do not edit repository files. Do not commit.
${COMMON}
Read: ${t.planFile || A.planFile} lines ${t.range} (the task), the contract sections it cites (and dev/spec/07-local-ollama.md if relevant), dev/plan/00-conventions.md, and the implementer's evidence in ${t.log || A.log}.
Implementer report: ${JSON.stringify(impl)}
Coordinator notes for this task: ${t.notes || 'none'}
${t.reviewScope ? `REVIEW SCOPE (coordinator decision, binding): ${t.reviewScope}
` : ''}
Do all of the following:
1. Inspect the change: 'git status --short', 'git diff' and every untracked file the task created (files: ${JSON.stringify(impl.files)}).
2. Independently RE-RUN the focused test filter(s) ${JSON.stringify(impl.test_filters)} and lint of the touched R/test files with the runner; report the exact result lines you observe. A failing run, a test warning, or lint output is a blocker.
3. Audit correctness against the plan task AND the contract (contract wins): exact signatures and return shapes, condition classes and fields, edge cases, IC-74 unknown-vs-zero semantics where relevant, cancellation/cleanup, connection/process leaks, state isolation (no global state beyond what the contract allows), security (no secret in messages/logs, untrusted text never a format string), house style. Check that the tests are not vacuous and actually prove the plan's acceptance claims for this task; check that no required test from the plan was dropped or weakened without a recorded, justified reason.
4. Verify each finding concretely (read the code path; optionally write a throwaway reproduction in ${SCRATCH}, never in the repo). Do not report speculative or stylistic padding; nits only if cheap and clearly right.
Severity: blocker = wrong behaviour/failing gate/contract violation; major = real defect in a realistic case, missing required test, or unnecessary complexity that adds meaningful code or surface (simplicity is a primary criterion: flag duplicated logic, needless helpers/options/layers, verbose or redundant text); minor = small but real improvement; nit = trivial. Do NOT demand bespoke handling of exotic inputs that a simple conservative rule already covers: proportionate hardening only.
Verdict 'clear' only if there are no blocker/major findings.`
}

function fixPrompt(t, impl, review, round) {
  return `You are the FIXER (round ${round}) for gptr plan ${A.plan} Task ${t.id}: "${t.title}". An independent reviewer audited the uncommitted implementation. Address its findings.
${COMMON}
Read: ${t.planFile || A.planFile} lines ${t.range}, the cited contract sections, ${t.log || A.log}.
Implementer report: ${JSON.stringify(impl)}
Reviewer report: ${JSON.stringify(review)}

For each blocker/major/minor finding: verify it against the plan and contract (the contract wins; the reviewer can be wrong). If real, fix it test-first where practical (add a regression test, see it fail, fix, see it pass). If not real, decline it with a precise reason. Nits: fix if trivial.
Then re-run the focused filters and lint of touched files; ensure [ FAIL 0 | WARN 0 ] and zero lints; re-run document if roxygen changed. Update the Task ${t.id} section of ${t.log || A.log} in the short section 11 format (one '- Reviews:' line summarising findings and outcome; refresh the Green line); no narrative. Do NOT commit, push, stash, reset or clean.
Return the structured result; 'files' lists every path modified by you or the implementer for this task.`
}

function commitPrompt(t, files, msg, push) {
  return `You are the COMMITTER for gptr plan ${A.plan} Task ${t.id}: "${t.title}" in /Users/wgu/Desktop/gptr (branch main).
Files reported for this task: ${JSON.stringify(files)}
Commit subject from the plan: ${JSON.stringify(msg)}
Steps:
1. 'git status --short'. Stage EXACTLY this task's files with explicit 'git add -- <paths>' (include files listed above that exist and are modified/untracked; also include NAMESPACE/man/*.Rd changes and dev/progress or dev/DEVIATIONS.md edits if they belong to this task). Never 'git add -A' or '.', never stage anything under .secrets/, dev/.validation/, dev/.library/ or *.env. If an unrelated modified file exists that clearly is not this task's, leave it unstaged and mention it in 'note'.
2. Commit with: git commit -F - <<'EOF'
<subject>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
   (use the plan's subject; if empty, write a conventional subject like 'feat(<area>): <task title>').
3. ${push ? "Push: 'git push origin main'. If rejected because the remote moved, run 'git pull --rebase origin main' then push again. Never force-push." : "Do not push."}
Return sha (short), committed_files, pushed, note.`
}

const results = []
let sincepush = 0
for (let i = 0; i < A.tasks.length; i++) {
  const t = A.tasks[i]
  const tag = `${A.plan} T${t.id}`
  log(`${tag}: ${t.title}`)
  const impl = await agent(implPrompt(t), { label: `impl ${tag}`, phase: 'Implement', schema: IMPL_SCHEMA })
  if (!impl) { results.push({ task: t.id, status: 'agent-died', stage: 'implement' }); break }
  if (impl.status === 'blocked') {
    results.push({ task: t.id, status: 'blocked', stage: 'implement', blocker: impl.blocker, files: impl.files })
    log(`${tag} blocked: ${(impl.blocker || '').slice(0, 200)}`)
    if (A.continueOnBlocked) continue
    break
  }

  let files = impl.files.slice()
  let review = null
  let clear = false
  const history = []
  for (let round = 1; round <= 5; round++) {
    review = await agent(reviewPrompt(t, Object.assign({}, impl, { files }), round), { label: `review ${tag} r${round}`, phase: 'Review', schema: REVIEW_SCHEMA })
    if (!review) break
    const serious = review.findings.filter(f => f.severity === 'blocker' || f.severity === 'major')
    const minors = review.findings.filter(f => f.severity === 'minor')
    history.push({ round, verdict: review.verdict, serious: serious.length, minor: minors.length, tests: review.tests_rerun })
    if (serious.length === 0 && minors.length === 0) { clear = true; break }
    if (serious.length === 0 && round >= 2) { clear = true; break }
    if (round === 5) break
    const fix = await agent(fixPrompt(t, Object.assign({}, impl, { files }), review, round), { label: `fix ${tag} r${round}`, phase: 'Fix', schema: FIX_SCHEMA })
    if (!fix) break
    files = Array.from(new Set(files.concat(fix.files)))
    history[history.length - 1].fixed = fix.addressed.length
    history[history.length - 1].declined = fix.declined
    if (fix.status === 'blocked') { results.push({ task: t.id, status: 'blocked', stage: 'fix', blocker: fix.blocker, files }); clear = false; review = null; break }
    if (serious.length === 0) { clear = true; break }
  }
  if (!clear) {
    results.push({ task: t.id, status: 'review-not-clear', files, history, lastFindings: review ? review.findings.filter(f => f.severity !== 'nit') : null })
    break
  }
  sincepush++
  const push = sincepush >= (A.pushEvery || 3) || i === A.tasks.length - 1
  const msg = impl.commit_message || ''
  const c = await agent(commitPrompt(t, files, msg, push), { label: `commit ${tag}`, phase: 'Commit', schema: COMMIT_SCHEMA, effort: 'low' })
  if (!c || !c.sha) { results.push({ task: t.id, status: 'commit-failed', files, history }); break }
  if (c.pushed) sincepush = 0
  results.push({ task: t.id, status: 'committed', sha: c.sha, pushed: c.pushed, red: impl.red, green: impl.green, adaptations: impl.adaptations, history, note: c.note || '' })
  log(`${tag} committed ${c.sha}${c.pushed ? ' (pushed)' : ''}`)
}
return results
