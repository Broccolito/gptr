export const meta = {
  name: 'gptr-simplicity-review',
  description: 'Read-only retrospective simplicity review of the gptr codebase plus the peter() rename inventory; synthesize an execution plan',
  phases: [
    { title: 'Review', detail: 'one reviewer per area finds unnecessary complexity (read-only)' },
    { title: 'Inventory', detail: 'locate every gptr()/gptr$ occurrence the rename must change' },
    { title: 'Synthesize', detail: 'dedupe, rank and package the simplifications and the rename into safe work packages' },
  ],
}

const ROOT = '/Users/wgu/Desktop/gptr'
const SCRATCH = '/private/tmp/claude-501/-Users-wgu-Desktop-gptr/0e1ce390-ccb6-46f4-bcb0-3e36676bd924/scratchpad/simplicity'

const COMMON = `Repository ${ROOT} (R package gptr 1.0, pure R). STRICTLY READ-ONLY: do not edit, create, stage or commit any repository file; do not run the test suite (other agents are working in this tree; uncommitted files may be mid-edit - review the COMMITTED version with 'git show HEAD:<path>' when 'git status' shows a file modified). You may write scratch files only under ${SCRATCH}/<your-area>/.
The maintainer's new top priority (CLAUDE.md; dev/plan/00-conventions.md section 11; D-135): SIMPLICITY / Occam's razor - the smallest design that meets the interface contract (dev/spec/04-interface-contract.md, section 15 and IC-74 = dev/spec/07-local-ollama.md) and each plan's acceptance; no redundant code, wrappers, helpers, options, layers, comments, phrases or scripts; one general conservative rule over many special cases; no duplicated logic.
Context: the code was built task by task from dev/plan/Pxx-*.md, then hardened through adversarial review rounds that often added special-case handling (recorded in dev/DEVIATIONS.md and dev/progress/Pxx.md). Some hardening is essential (real contract defects, security/privacy, IC-74 unknown-not-zero semantics, copy safety, cross-platform); much may be disproportionate. Contract behaviour and every plan acceptance test must be preserved; simplifications that would change a contract-visible behaviour must say so explicitly.`

const FINDINGS = {
  type: 'object',
  properties: {
    area: { type: 'string' },
    lines_now: { type: 'integer', description: 'current committed lines in the area R files' },
    plan_literal_estimate: { type: 'string', description: 'rough size of the plan literal code for these files, and where the growth came from' },
    summary: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          kind: { type: 'string', enum: ['duplication', 'dead-code', 'over-engineering', 'special-case-sprawl', 'redundant-validation', 'verbose-text', 'redundant-test', 'needless-abstraction', 'other'] },
          problem: { type: 'string' },
          proposal: { type: 'string', description: 'concrete simplification, naming the functions to merge/delete/replace' },
          est_lines_removed: { type: 'integer' },
          risk: { type: 'string', enum: ['low', 'medium', 'high'] },
          behaviour_change: { type: 'string', description: "'none' or the exact contract-visible change and why it is acceptable" },
          tests: { type: 'string', description: 'which tests guard it; which redundant tests can go' },
        },
        required: ['id', 'files', 'kind', 'problem', 'proposal', 'est_lines_removed', 'risk', 'behaviour_change', 'tests'],
      },
    },
  },
  required: ['area', 'lines_now', 'summary', 'findings'],
}

const AREAS = [
  { key: 'p01-core', files: 'R/aaa-state.R R/zzz.R R/utils-*.R R/json-*.R R/provider-fake*.R R/provider-events*.R R/provider-message*.R (and their tests)', plan: 'dev/plan/P01-foundation.md' },
  { key: 'p02-ext', files: 'R/ext-*.R except R/ext-plugins.R (and tests)', plan: 'dev/plan/P02-extension-api-registry.md' },
  { key: 'p03-auth', files: 'R/auth-*.R except R/auth-oauth.R (and tests)', plan: 'dev/plan/P03-secrets-redaction.md' },
  { key: 'p04-transport', files: 'R/proc-*.R R/http-*.R (and tests)', plan: 'dev/plan/P04-reactor-process-engine.md' },
  { key: 'p05-p12-models', files: 'R/provider-*.R (except fake/events/message) R/catalog-*.R, dev/catalog/ (and tests)', plan: 'dev/plan/P05-model-layer-core.md and dev/plan/P12-native-provider-adapters.md' },
  { key: 'p06-kernel', files: 'R/session-*.R R/agent-*.R (and tests, tests/testthat/fixtures/oracles/report02/)', plan: 'dev/plan/P06-session-kernel-agent-loop.md' },
  { key: 'p07-prompt', files: 'R/prompt-*.R, dev/bench/tokens/ (and tests)', plan: 'dev/plan/P07-prompt-context-caching-compaction.md' },
  { key: 'p08-gateway', files: 'R/gptr-*.R (and tests, inst/templates)', plan: 'dev/plan/P08-gateway-sdk.md' },
  { key: 'p09-p10-eval-tools', files: 'R/eval-*.R R/env-*.R R/tool-*.R (and tests)', plan: 'dev/plan/P09-evaluator-workspace.md and dev/plan/P10-tools-namespace.md' },
  { key: 'p11-perm', files: 'R/perm-*.R (10,131 lines!), inst/extdata/risk-*.csv (and tests). Special focus: the command/SQL/Python classifier grew through 15 review rounds; evaluate replacing special-case modelling with the explicit level-0 ALLOWLIST of D-061 standard (A)-(C): a small table of known read-only programs with their allowed options, everything else level 3, level 4 only for statically identifiable critical/control targets - estimate how much code that removes while keeping the plan tests and the D-061 standard', plan: 'dev/plan/P11-permissions-ui-plan-mode.md and dev/spec/03-architecture.md section 6.8' },
  { key: 'p13-s1', files: 'R/s1-*.R (and tests, fixtures/jev, fixtures/ollama, fixtures/classifier)', plan: 'dev/plan/P13-system-one.md and dev/spec/07-local-ollama.md' },
  { key: 'p15-docs', files: 'R/doc-*.R (and tests)', plan: 'dev/plan/P15-documents-replay.md' },
  { key: 'p17-p18-p20', files: 'R/skill-*.R R/ext-plugins.R R/agent-defs*.R R/prompt-templates*.R (whatever P17 owns), R/mcp-*.R R/auth-oauth.R, R/cli-*.R, inst/gptr/ (and tests)', plan: 'dev/plan/P17-skills-templates-agents-plugins.md, P18-mcp-oauth.md, P20-subscription-cli-providers.md' },
  { key: 'tests-docs', files: 'tests/testthat/helper-*.R and shared test fixtures (duplicated helpers across test files), dev/ci/*, dev/DEVIATIONS.md (9,800+ lines, 135 entries) and dev/progress/*.md (verbosity: propose a concise format and what can be condensed without losing decisions/evidence pointers), README.Rmd/README.md, .github/workflows', plan: 'dev/plan/00-conventions.md' },
]

phase('Review')
const reviews = parallel(AREAS.map(a => () => agent(`${COMMON}

You are the SIMPLICITY REVIEWER for area "${a.key}": ${a.files}. Plan(s): ${a.plan}.
1. Measure the area (lines per file of the committed versions). Skim the plan's File Structure and literal code for these files to estimate how large the plan-literal implementation was, and where the growth came from (D-entries, review rounds).
2. Read the code. Find concrete simplification opportunities: duplicated logic within or across files (name the existing helper to reuse), dead or unreachable code, needless helpers/wrappers/layers/options, special-case sprawl replaceable by one conservative rule, redundant validation (the same check in several layers), verbose comments/messages, redundant or near-duplicate tests, over-general abstractions with a single caller.
3. For each finding give a concrete proposal (which functions to merge/delete/replace), an estimate of lines removed, the risk, and whether any contract-visible behaviour changes (cite contract sections). Never propose removing a guard that implements the contract, privacy/secret handling, IC-74 unknown semantics, copy safety, or a fix for a real defect recorded in DEVIATIONS unless a simpler mechanism provides the same guarantee.
4. Rank findings by value (lines saved x safety). Be specific and verifiable; skip vague style opinions. Write any long notes to ${SCRATCH}/${a.key}/notes.md.`, { label: `review ${a.key}`, phase: 'Review', schema: FINDINGS })))

const inventory = agent(`${COMMON}

You are the RENAME INVENTORY agent. Maintainer decision (D-135): the package stays 'gptr', but the main entry point users call is renamed from gptr() to peter(), and its member namespace from gptr$... to peter$... (the namespace is the same gateway object: S3 class gptr_gateway with $, [[, print, .DollarNames methods). Other exports keep the gptr_ prefix (gptr_last, gptr_usage, gptr_fork, gptr_doc, gptr_prob, ...). Things that must NOT change: the package name gptr and gptr:: qualifiers (gptr::gptr becomes gptr::peter), the gptr_ prefixed exports, option names gptr.*, the .gptr/ directory, the GPTR_* environment variables, condition classes gptr_error_*, S3 class names (gptr_gateway etc., unless you find a reason), file names R/gptr-*.R.
Produce a complete inventory (write the detailed list to ${SCRATCH}/rename/inventory.md): every occurrence class of the callable gptr( and of gptr$ in (a) R/ code (definition, NAMESPACE export, S3 methods, the P09 gptr:: shim rewrite in R/eval-guard.R, doc.site/scanner patterns in R/doc-*.R that recognise gptr() calls in documents (they must recognise peter() - and decide whether old gptr() blocks in user documents still need recognition: NO back-compat is needed, 1.0 is unreleased), prompt texts in R/prompt-text.R (verbatim model-facing texts mentioning gptr$), tool texts, error messages), (b) tests and fixtures (golden transcripts, SSE fixtures, recorded blocks), (c) man/ and roxygen, inst/ (templates, skills, examples), README.Rmd/README.md, (d) dev/bench/tokens baselines and golden transcripts (model-facing text changes alter token counts: the baselines must be re-recorded; note rtiktoken counts), (e) dev/spec/*.md and dev/plan/*.md (count occurrences per file; specs/plans are the design record and should be updated so future tasks read peter()), dev/research (historical: recommend leaving untouched). Count occurrences per file group, note tricky cases (regexes, string-built calls, '\\\\bgptr\\\\(' patterns, deparse/str2lang text, documentation examples, the IC-38/IC-52 context texts), and propose an ordered, mechanical execution plan with verification commands (which test filters prove it; that token baselines must be regenerated with the bench runner).`, { label: 'rename inventory', phase: 'Inventory', schema: { type: 'object', properties: { counts: { type: 'string' }, tricky: { type: 'array', items: { type: 'string' } }, plan: { type: 'string' } }, required: ['counts', 'tricky', 'plan'] } })

const [rs, inv] = await Promise.all([reviews, inventory])
const ok = rs.filter(Boolean)
log(`reviews: ${ok.length}/${AREAS.length}; findings: ${ok.reduce((n, r) => n + r.findings.length, 0)}`)

phase('Synthesize')
const synthesis = await agent(`${COMMON}

You are the SYNTHESIS agent. Inputs: per-area simplicity reviews (JSON below) and the rename inventory. Produce an execution plan the coordinator can run as task-sized work packages through the usual TDD + independent review + commit workflow.
Requirements: (1) dedupe cross-area findings (shared helpers); (2) drop findings that would weaken contract behaviour, privacy, IC-74 semantics or real-defect fixes without an equivalent simpler guarantee; (3) group the rest into work packages, each confined to one plan's files where possible, ordered by value (lines removed x safety) and with explicit tests that must stay green; mark which packages touch files of plans still in progress (P10 Tasks 11-12, P11 Tasks 3-8, P17 Tasks 8-12 are being implemented now; P14, P16, P18-P25 not started) so the coordinator can schedule them after those lanes; (4) put the peter() rename as ONE coordinated work package (or a short ordered sequence) using the inventory; (5) propose a concise format for dev/progress/*.md and dev/DEVIATIONS.md going forward (and whether to condense the existing ones); (6) estimate total lines removable.
Write the full plan to ${SCRATCH}/plan.md and return a structured summary.

Reviews: ${JSON.stringify(ok)}

Rename inventory: ${JSON.stringify(inv)}`, { label: 'synthesize', phase: 'Synthesize', schema: { type: 'object', properties: { total_lines_removable: { type: 'integer' }, packages: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, title: { type: 'string' }, plan_owner: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, est_lines_removed: { type: 'integer' }, risk: { type: 'string' }, blocked_by_active_lane: { type: 'string' }, notes: { type: 'string' } }, required: ['id', 'title', 'plan_owner', 'files', 'est_lines_removed', 'risk', 'blocked_by_active_lane', 'notes'] } }, rename_package: { type: 'string' }, docs_format: { type: 'string' } }, required: ['total_lines_removable', 'packages', 'rename_package', 'docs_format'] } })
return { synthesis, inventory: inv, reviewCount: ok.length }