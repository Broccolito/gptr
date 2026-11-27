export const meta = {
  name: 'gptr-models-research',
  description: 'Research native model discovery in Claude Code and Codex, gptr model machinery, and every provider current model list',
  phases: [
    { title: 'Research', detail: 'six read-only investigations', model: 'sonnet' },
  ],
}

const RULES = `READ-ONLY research for the gptr R package (repo worktree /Users/wgu/Desktop/gptr/.claude/worktrees/gptr-models-discovery, branch claude/models-discovery = main 0280d953, gptr 1.2.0). Do not edit, create or delete files in any repository; no commits, pushes or PRs. Never print or copy tokens, API keys or credentials (.secrets/, ~/.codex/auth.json, ~/.claude/.credentials.json, keychain); report field names only. Do not change the user's real Claude Code or Codex configuration: read-only commands only, and if a command might write state use a throwaway HOME/CLAUDE_CONFIG_DIR/CODEX_HOME under /private/tmp/claude-501/ (copying no credentials) or flags like --no-session-persistence. Never send a prompt that costs model tokens unless the task explicitly says so. Cite evidence as path:line, URL, or the exact command and its (redacted) output. Quote exact JSON shapes where they matter. The maintainer's rule for this campaign: no hard-coded model-name regexes or rule lists; use each tool's native API so discovery survives CLI updates.`

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

const PROVIDER_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    providers: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          provider: { type: 'string' },
          gptr_today: { type: 'string', description: 'what gptr seed/catalog and provider code have for it now' },
          current_models: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'string' }, released: { type: 'string' }, context: { type: 'string' }, max_output: { type: 'string' },
                input_modalities: { type: 'string' }, tools: { type: 'string' }, reasoning: { type: 'string' }, pricing: { type: 'string' },
                status: { type: 'string', description: 'current | preview | deprecated | retired, with date' }, source: { type: 'string' },
              },
              required: ['id', 'status', 'source'],
            },
          },
          api_changes: { type: 'string', description: 'request/response changes gptr provider code needs for the new models (new params, endpoints, thinking/reasoning config, removed fields)' },
          models_endpoint: { type: 'string', description: 'the provider\'s native list-models endpoint and its response shape, if any' },
        },
        required: ['provider', 'gptr_today', 'current_models', 'api_changes', 'models_endpoint'],
      },
    },
    open_questions: { type: 'array', items: { type: 'string' } },
    confident: { type: 'boolean' },
  },
  required: ['summary', 'providers', 'open_questions', 'confident'],
}

const PROVIDER_TASK = (names) => `Survey these model providers comprehensively as of today (2026-11-26): ${names}. For each: (1) what gptr has now — read R/catalog-models.R, the seed snapshot inst/extdata/models.json.gz (gzip JSON: schema_version, generated 2026-10-03, providers, models, aliases; read it with Rscript --vanilla -e 'str(jsonlite::fromJSON(gzcon(file("inst/extdata/models.json.gz","rb")), simplifyVector = FALSE))'), the provider's R/provider-*.R adapter and any model-specific code, and what gptr pulls live from models.dev (catalog_decision_url and the models.dev refresh path); (2) the provider's CURRENT official model list from its official docs/changelog/models page and, where public without a key, its list-models endpoint (do not call endpoints that need a key), plus models.dev's current entries for it (https://models.dev/api.json or the URL gptr uses) — every current model id with release date, context window, max output, input modalities, tool calling, reasoning/thinking support, pricing, and status (current, preview, deprecated or retired with dates), highlighting everything released or retired since 2026-10-03; (3) any API changes gptr's adapter would need for the new models (new reasoning/thinking parameters, endpoints, response fields, removed parameters such as temperature on reasoning models); (4) the native list-models endpoint and response shape. Use WebSearch (mode standard first, extended if thin) and WebFetch via ToolSearch. Be exhaustive and precise; mark anything you could not confirm from an official source.`

const TASKS = [
  {
    key: 'gptr-machinery', schema: SCHEMA, agentType: 'general-purpose',
    prompt: `Map gptr's whole model machinery so a redesign can be planned. Read R/catalog-models.R fully (seed snapshot, models.dev refresh, cache, decision catalog, aliases, how a model id is resolved, validated or refused, capability lookups), R/provider-registry.R, how gptr_models() and gptr_providers() present models, gptr_config(model = ) and the settings for the default model, the console's model choice (/model command and any picker: grep R/console-*.R), and the subscription-CLI routes R/cli-claude.R, R/cli-codex.R, R/cli-common.R: how a model is chosen and passed (claude --model, codex -m), what model ids they accept or map, whether any list of CLI models or regex of model names is hard-coded today (quote every hard-coded model id, alias table or regex in R/ and inst/extdata), how a route's default model is decided, and what happens with an unknown or custom model id (refused? warned? passed through?) for API providers and for CLI routes. Also find the docs that describe models (man pages for gptr_models, gptr_providers, gptr_config; vignettes/language-models.Rmd.orig; README.Rmd 'Connect a model'), the tests that pin model behaviour (tests/testthat/test-catalog-*.R, test-cli-*.R, test-provider-*.R), and dev/plan P20 and later plans' rules about models (grep dev/plan for 'model'). Report the exact functions, data shapes and lines.`,
  },
  {
    key: 'claude-native', schema: SCHEMA, agentType: 'claude-code-guide',
    prompt: `Find Claude Code's NATIVE ways to report (a) the models available to the user's account/setup and (b) the user's configured default model, for Claude Code 2.1.323 (/opt/homebrew/bin/claude). Candidates to check, with the official docs (Claude Code CLI reference, settings, model configuration, headless/stream-json protocol, the Agent SDK's supportedModels()/initialize control request and its ModelInfo shape) and with the local CLI: (1) the stream-json control protocol: run 'claude -p --input-format stream-json --output-format stream-json --verbose --no-session-persistence' and send ONLY a control_request {"type":"control_request","request_id":"1","request":{"subtype":"initialize"}} line, then close stdin — no user message, so no model call and no cost — and report the control_response shape (models list? fields value/displayName/description? account info, output styles, commands); confirm it costs nothing (no assistant message, usage zero) and whether it needs auth/network; (2) the system init event's 'model' field (which model a session would use, reflecting settings, ANTHROPIC_MODEL, --model aliases such as opus/sonnet/haiku/default/opusplan and [1m] variants); can it be obtained without sending a prompt? (3) the 'model' key in settings.json files and env vars (ANTHROPIC_MODEL, ANTHROPIC_DEFAULT_OPUS_MODEL, ANTHROPIC_DEFAULT_SONNET_MODEL, ANTHROPIC_DEFAULT_HAIKU_MODEL, CLAUDE_CODE_SUBAGENT_MODEL) and how third-party setups (Bedrock, Vertex, an LLM gateway/router via ANTHROPIC_BASE_URL, local models) change the list; (4) any 'claude config', '/model' or 'claude models' style subcommand. gptr runs Claude Code isolated with --strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources "" --disable-slash-commands --tools "" (R/cli-claude.R:66-98): say how each discovery method behaves under those flags and which flags discovery itself would need (e.g. whether the user's default model is visible only when user settings are loaded). Run the commands; use the user's real login read-only with --no-session-persistence (that is allowed for this check), never print credentials.`,
  },
  {
    key: 'codex-native', schema: SCHEMA, agentType: 'general-purpose',
    prompt: `Find Codex CLI's NATIVE ways to report (a) the models available to the user (ChatGPT plan, API key, or a custom model_provider such as a local Ollama/LM Studio or a router) and (b) the user's configured default model and reasoning effort, for codex-cli 0.157.1 (/opt/homebrew/bin/codex). Check: (1) 'codex app-server' (JSON-RPC over stdio): its initialize handshake and a model list request (e.g. 'model/list' with its params and response: ids, display names, isDefault, supported reasoning efforts, hidden/upgrade fields), config read requests (e.g. 'config/read' or 'getUserSavedConfig') for the default model and model_provider; generate the protocol schema if the CLI offers it ('codex app-server generate-json-schema' or 'generate-ts' into a /private/tmp/claude-501/ folder) and read the exact method names; (2) whether model/list works offline, without auth, with an API-key login, with a ChatGPT login, and with a custom model_provider (does it list the provider's models or only OpenAI's?); (3) 'codex exec --json' events: does thread.started/turn context report the model? (4) 'codex --help', 'codex debug', 'codex features', any 'models' subcommand; (5) config.toml keys model, model_provider, model_reasoning_effort, profiles, and -c overrides. gptr runs 'codex exec --json --ignore-user-config --skip-git-repo-check ...' with features disabled (R/cli-codex.R:60-100): say how each discovery method behaves with --ignore-user-config and which flags discovery itself needs. You may use the user's real CODEX_HOME read-only for app-server requests that only list or read (no thread/turn start, no prompt, no cost); never print auth.json contents. Report exact JSON-RPC request/response shapes.`,
  },
  { key: 'providers-a', schema: PROVIDER_SCHEMA, agentType: 'general-purpose', prompt: PROVIDER_TASK('Anthropic (direct API), OpenAI (Responses and Chat Completions), Azure OpenAI / Azure AI Foundry, Amazon Bedrock (all model families gptr can call there)') },
  { key: 'providers-b', schema: PROVIDER_SCHEMA, agentType: 'general-purpose', prompt: PROVIDER_TASK('Google Gemini (Gemini API and Vertex where gptr uses it), xAI Grok, Mistral, DeepSeek') },
  { key: 'providers-c', schema: PROVIDER_SCHEMA, agentType: 'general-purpose', prompt: PROVIDER_TASK('OpenRouter, Groq, Together AI, Cerebras, Fireworks AI, and the local servers Ollama, LM Studio, llama.cpp and vLLM (for local ones: how gptr discovers installed models today and whether their native list endpoints — e.g. Ollama /api/tags and /api/show, OpenAI-compatible /v1/models — give context length and tool support), plus whatever the "typesafe" provider in gptr\'s seed is') },
]

phase('Research')
const results = await parallel(TASKS.map(t => () =>
  agent(`${t.prompt}\n\n${RULES}`, { label: `models:${t.key}`, phase: 'Research', schema: t.schema, model: 'sonnet', agentType: t.agentType })
    .then(r => ({ key: t.key, result: r }))
))
const done = results.filter(Boolean).filter(r => r.result)
const missing = TASKS.map(t => t.key).filter(k => !done.find(d => d.key === k))
if (missing.length) log(`No result from: ${missing.join(', ')}`)
return { done, missing }
