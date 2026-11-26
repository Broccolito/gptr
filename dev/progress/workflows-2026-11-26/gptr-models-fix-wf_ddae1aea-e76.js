export const meta = {
  name: 'gptr-models-fix',
  description: 'Fix the P36 review findings (write-in hijack, provider-table allowlist, discovery flags, notices, cloud-rule exception), then check',
  phases: [
    { title: 'Fix', detail: 'one Opus fixer' },
    { title: 'Check', detail: 'suites and lint', model: 'sonnet' },
  ],
}
const LIB = 'R_LIBS_USER="/Users/wgu/Desktop/gptr/dev/.library:/Users/wgu/Library/R/arm64/4.6/library"'
const fix = await agent(`In your OWN isolated git worktree (current directory), FIRST run 'git reset --hard worktree-wf_d11e483b-e19-5' (local branch: gptr plan P36, model discovery, at cffee0a1; read dev/plan/P36-model-discovery.md, dev/progress/P36.md and the D-390..D-395 entries in dev/DEVIATIONS.md). Fix these review findings with the smallest correct change each, tests first, one commit 'fix(models): write-ins pass as written; review fixes (P36)' ending with 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>':
1. MAJOR: model_match_fuzzy() (R/catalog-models.R ~559-568) silently resolves an id that is a substring of a catalog id to another model (model_resolve('openai/gpt-6') gives openai/gpt-6.1-sol), defeating write-ins (D-392) and matching names (D-393). Make resolution: an exact id, then a data-backed alias, then (with a provider) the write-in path with its one notice; a bare name that is neither is refused with an error that SUGGESTS close catalog ids (the suggestion may use the existing matcher, but nothing resolves silently). Update the tests that relied on fuzzy resolution, and the docs (?gptr_models, language-models article) if they mention it.
2. R/cli-codex.R ~123-139: the user's model_providers table goes onto codex command lines with only experimental_bearer_token and http_headers removed. Use an allowlist of Codex's documented non-secret provider keys (read Codex's config reference: e.g. name, base_url, env_key, env_key_instructions, wire_api, env_http_headers, requires_openai_auth, request_max_retries, stream_max_retries, stream_idle_timeout_ms, supports_websockets) and drop everything else (query_params, auth commands, tokens) with the existing one-time notice; test it.
3. R/cli-claude.R ~34-40: the discovery probe loads the user's settings (needed for the default model) but also their hooks/plugins/skills; add --tools "" and --disable-slash-commands if they do not change initialize/get_settings's model data (verify against the recorded fixtures' shape and, read-only and zero-cost, against the real claude 2.1.323 once), and say in ?gptr_models that the probe starts Claude Code with the user's settings, so its SessionStart hooks run.
4. R/cli-common.R ~566-576: a write-in on a CLI route gives its one notice even when discovery has not run or failed (say it was not checked against the CLI's list).
5. D-390's text says one probe 'per CLI version and login'; the cache key is the CLI command and binary time. Make the D-390 entry, P36 plan row and docs say what is true (once per R session and CLI version; gptr_models(refresh = TRUE) asks again).
6. R/catalog-models.R ~1311-1313: the Ollama ':cloud'/'-cloud' id-suffix check is a name rule; it is a fail-closed privacy guard that predates P36. Keep it, and record it as the one exception in D-393's entry (and the plan's D-393 row), with the reason.
Run under ${LIB}: Rscript --vanilla -e 'devtools::test(filter = "catalog-|cli-|provider-|console-|gptr-config|model")', the lint runner on changed files (Rscript --vanilla dev/ci/isolated-check.R lint <files>), dev/release/check-files.R all, dev/release/check-docs.R, and precompute.R --check language-models if the article changed. House rules: '=' and '|>', simplicity first. Never write into another worktree; do not push. Final answer: worktree, branch, commit, what changed per finding, the test and lint results.`, { label: 'models:fix', phase: 'Fix', isolation: 'worktree', schema: {
  type: 'object',
  properties: { worktree: { type: 'string' }, branch: { type: 'string' }, commit: { type: 'string' }, changes: { type: 'array', items: { type: 'string' } }, results: { type: 'array', items: { type: 'string' } }, open: { type: 'array', items: { type: 'string' } } },
  required: ['worktree', 'branch', 'commit', 'changes', 'results', 'open'],
} })
phase('Check')
const check = await agent(`Independently check commit ${fix.commit} in ${fix.worktree} (do not edit or commit). Under ${LIB}: cd ${fix.worktree} && Rscript --vanilla -e 'devtools::test(filter = "catalog-|cli-|provider-|console-|gptr-config|model|perm-|mcp-")'; lint the files changed since claude/models-discovery with Rscript --vanilla dev/ci/isolated-check.R lint <files>; offline probes with pkgload::load_all(): model_resolve("openai/gpt-6") must be a write-in passed as written with one notice; model_resolve("sonnet") and ("gemini") resolve to real catalog models; a bare unknown name errors with suggestions. Report counts and every failure exactly; verdict fail if any.`, { label: 'models:check', phase: 'Check', model: 'sonnet', schema: {
  type: 'object',
  properties: { verdict: { type: 'string', enum: ['pass', 'fail', 'unsure'] }, details: { type: 'array', items: { type: 'string' } } },
  required: ['verdict', 'details'],
} })
return { fix, check }
