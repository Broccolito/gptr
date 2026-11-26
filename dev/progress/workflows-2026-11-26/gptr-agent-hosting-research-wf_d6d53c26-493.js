export const meta = {
  name: 'gptr-agent-hosting-research',
  description: 'Research for hosting the gptr Agent bridge in gptr and packaging it for Biorouter, Claude and Codex',
  phases: [
    { title: 'Research', detail: 'six independent read-only investigations', model: 'sonnet' },
  ],
}

const RULES = `STRICTLY READ-ONLY: do not edit, create or delete files in any repository, do not commit, push, tag, release, or open/merge/comment on PRs or issues; no mutating gh calls; do not install plugins or extensions into the user's real Claude Code, Codex or Biorouter configuration (if you need to try a CLI command, use --help or a throwaway HOME/CODEX_HOME/CLAUDE_CONFIG_DIR under /private/tmp/claude-501/ and never copy credentials there). Never print tokens or secrets (.secrets/, auth.json, serve-*.json values). Cite evidence as absolute_path:line or URL. Be concrete; quote exact JSON/TOML shapes where formats matter.`

const PATHS = `Locations:
- gptr R package repo (worktree, main 0280d953 = gptr 1.2.0; CRAN has 1.1.0): /Users/wgu/Desktop/gptr/.claude/worktrees/gptr-biorouter-bridge-coord-2d1eed (R/mcp-server.R, inst/gptr/, vignettes/*.Rmd and *.Rmd.orig, README.Rmd, NEWS.md, _pkgdown.yml, .Rbuildignore, .github/workflows/, dev/plan/00-index.md, dev/plan/00-conventions.md, dev/release/check-files.R, dev/spec/)
- GptrAgent extension repo (Python stdio MCP bridge, latest v0.1.2 at 6b3295e, remote Broccolito/GptrAgent): /Users/wgu/biorouter-runs/baam-refresh-2026-11/GptrAgent
- Biorouter app repo: /Users/wgu/Desktop/biorouter (local main is stale; read origin/main via 'git -C /Users/wgu/Desktop/biorouter show origin/main:<path>' or 'git grep ... origin/main'); GitHub BaranziniLab/biorouter
- BAAM refresh plan: /Users/wgu/biorouter-runs/baam-inventory-2026-11-21/PLAN.md; WP-14 evidence /Users/wgu/biorouter-runs/baam-refresh-2026-11/WP-14
- Local CLIs: claude 2.1.323 (/opt/homebrew/bin/claude), codex-cli 0.157.1 (/opt/homebrew/bin/codex), uv 0.13.9, python3 3.15.2`

const SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'one dense paragraph with the answer' },
    facts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          topic: { type: 'string' },
          detail: { type: 'string', description: 'exact formats, commands, paths, field names' },
          evidence: { type: 'string' },
        },
        required: ['topic', 'detail', 'evidence'],
      },
    },
    recommendations: { type: 'array', items: { type: 'string' } },
    open_questions: { type: 'array', items: { type: 'string' } },
    confident: { type: 'boolean' },
  },
  required: ['summary', 'facts', 'recommendations', 'open_questions', 'confident'],
}

const TASKS = [
  {
    key: 'gptragent-source',
    agentType: 'general-purpose',
    prompt: `Goal: plan importing the GptrAgent extension (with git history) into the gptr repo. Read the whole GptrAgent repo at its current HEAD (6b3295e, v0.1.2): every file under src/gptragent/, r/attach.R, manifest.json, pyproject.toml, uv.lock, skills/gptr-live-r/SKILL.md, README.md, NOTICE, LICENSE, scripts/build_brxt.py, scripts/version.py, tests/, .github/workflows/ci.yml and release.yml, .gitignore, .gitattributes, .python-version. Report: (1) what changed in 0.1.1 and 0.1.2 (git -C <repo> show --stat 6c999b7 6b3295e and read the diffs); (2) every place the repo name, URL, version, tag scheme or folder layout is hard-coded (Broccolito/GptrAgent, v0.1.x, paths relative to repo root, manifest.repository, README links, release.yml tag check, build_brxt.py inputs, test_bundle.py expectations) and what must change if the code lives in a subfolder of Broccolito/gptr (e.g. a top-level folder) and is released from gptr's own releases; (3) exactly how the .brxt is built (inputs, determinism, file list) and how the version is derived; (4) the CI matrix and how live R tests install gptr (CRAN vs source) so the gptr repo's CI could instead test against the gptr checkout itself; (5) the minimum Python version, dependencies (stdlib only?), and whether the server can run with plain python3 >= 3.11 without uv; (6) how the bridge is started (entry point, uv run, python -m gptragent) so the same code could also be launched by a Claude Code plugin (.mcp.json) and a Codex plugin; (7) which tools are bridged (sessions, inspect, r; not read/edit/write) and why, citing code/comments.`,
  },
  {
    key: 'biorouter-hosting',
    agentType: 'general-purpose',
    prompt: `Goal: find every Biorouter constraint on where an extension's .brxt is hosted, so the gptr Agent can be downloaded from Broccolito/gptr's own GitHub releases instead of Broccolito/GptrAgent. Read on Biorouter origin/main (git -C /Users/wgu/Desktop/biorouter fetch is NOT allowed; origin/main is already current at d789a623d): how the desktop app and CLI install an extension from the BAAM registry (landing/registry.json fields 'github', 'download', 'filename', 'extension_name'; ui/desktop/src/components/baam/; crates/biorouter/src/extension_install/ brxt.rs, transaction.rs, any download/verify code); whether there is an update check (how it decides a newer version: manifest version vs registry, GitHub releases API, 'latest' URLs) and whether sha256/size are pinned anywhere (catalog/extensions.json release fields, registry); landing/scripts/build-registry.mjs and its tests and any catalog checker (landing/catalog/*.json, scripts that verify releases against GitHub, tag == v+manifest.version rules, repository fields, CI workflows under .github/workflows that fetch release assets); every place GptrAgent or Broccolito/GptrAgent appears (git grep -n -i 'gptragent\\|GptrAgent' origin/main) and what each would need to become; the BAAM plan's rules (PLAN.md ground rules, esp. rule 9 on tags and anything about extension repos). Answer concretely: would download URL https://github.com/Broccolito/gptr/releases/download/v1.2.1/gptragent.brxt (extension version = gptr version 1.2.1) pass every check? Would https://github.com/Broccolito/gptr/releases/latest/download/gptragent.brxt? Would a prefixed tag like gptragent-v0.2.0? What does the card's GitHub link need to be (a repo root or can it be a tree/<branch>/<folder> URL)?`,
  },
  {
    key: 'claude-plugin-format',
    agentType: 'claude-code-guide',
    prompt: `Goal: the exact, current way to ship a Claude Code plugin (and, separately, a Claude Desktop extension) from a GitHub repo whose main content is an R package, so Claude can use a stdio MCP server (a stdlib Python bridge) plus a skill. Use the official Claude Code docs (plugins, plugin marketplaces, plugins reference, MCP in plugins, skills in plugins) and the local CLI (claude --help, claude plugin --help, claude plugin marketplace --help, claude plugin validate --help) for claude 2.1.323. Report exactly: marketplace file location and schema (.claude-plugin/marketplace.json: name, owner, plugins[] with source forms — relative path, github, git-subdir, url — and whether a plugin can live in a subfolder of the marketplace repo); plugin manifest (.claude-plugin/plugin.json fields, version); how a plugin declares an MCP server (.mcp.json or mcpServers in plugin.json, \${CLAUDE_PLUGIN_ROOT}, env, how a python or uv command is written portably on macOS/Linux/Windows); skills layout inside a plugin; install commands for users (claude plugin marketplace add Broccolito/gptr; claude plugin install <plugin>@<marketplace>; the /plugin UI); how to test locally without installing (claude --plugin-dir <dir>, claude plugin validate <dir>), and how to run a headless check (claude -p with --plugin-dir and --allowedTools/--permission-mode to confirm the MCP tools load: e.g. 'claude -p --output-format json' listing mcp servers or tools). Also: does a marketplace repo's other content (an R package at the root) interfere? For Claude Desktop: the current extension format (.mcpb, formerly .dxt): manifest.json schema version, server types (node/python/binary/uv?), how a Python stdio server with no dependencies is packaged, 'mcpb pack', and whether a uv-type server exists. Give exact JSON examples.`,
  },
  {
    key: 'codex-plugin-format',
    agentType: 'general-purpose',
    prompt: `Goal: the exact, current way to ship a Codex plugin from a GitHub repo (Codex CLI 0.157.1 installed at /opt/homebrew/bin/codex), so Codex can use a stdio MCP server (a stdlib Python bridge) plus a skill. First read the local CLI: codex --help, codex plugin --help (and its subcommands: marketplace add/list, install, etc. if present), codex mcp --help, codex mcp add --help; look for documentation in the installed package (find /opt/homebrew -path '*codex*' -name '*.md' 2>/dev/null | head; strings are fine). Then the official docs on developers.openai.com/codex (plugins, build plugins, marketplaces, skills, MCP, config reference) and github.com/openai/codex docs (use WebSearch/WebFetch via ToolSearch if available). Report exactly: plugin manifest location and schema (e.g. .codex-plugin/plugin.json fields), how a plugin bundles an MCP server (.mcp.json? mcpServers key? paths relative to the plugin root, env), skills inside a plugin (skills/<name>/SKILL.md), the marketplace file (location such as .agents/plugins/marketplace.json, schema, source forms, whether a plugin can live in a subfolder), how a user installs from a GitHub repo (exact commands), how to test without touching the user's config (CODEX_HOME=<tmp> plus copying only a plugin? codex exec with -c overrides; codex mcp list), and the fallback when plugins are unavailable (codex mcp add gptr -- uv run ... or a config.toml [mcp_servers.gptr] block with command/args/env and startup_timeout_sec/tool_timeout_sec). Note per-tool timeout defaults (tool_timeout_sec default 60 s?) since the bridge's r calls can take up to 280 s. Give exact examples. If the installed CLI's behaviour and the docs disagree, the CLI wins; say so.`,
  },
  {
    key: 'gptr-docs-ci',
    agentType: 'general-purpose',
    prompt: `Goal: learn the gptr repo's documentation, release and CI conventions so a bridge folder plus Claude/Codex/Biorouter packaging can be added without breaking CRAN checks or house style. Read: README.Rmd (all sections, especially where MCP, Codex, Claude Code, Claude Desktop, Cursor and Biorouter appear), vignettes/mcp.Rmd.orig and mcp.Rmd (how each client is set up today; the 'advertise' section), vignettes/skills-and-plugins.Rmd.orig, extending-gptr.Rmd.orig, how .Rmd.orig precomputes to .Rmd (dev/ scripts), _pkgdown.yml (it says it is generated by dev/release/check-files.R pkgdown --write: read that script and what else it checks, e.g. a list of allowed top-level files or a WORDLIST), NEWS.md format, inst/WORDLIST, DESCRIPTION, .Rbuildignore (would a new top-level folder like 'bridge/' or 'extensions/' or '.claude-plugin/' need entries? check R CMD build behaviour: hidden dirs, non-standard top-level files NOTE), .github/workflows/*.yml (names, required checks, triggers, timeouts; how a new Python job for the bridge and a release job attaching gptragent.brxt to gptr's GitHub release would fit the 20-minute rule; any existing release workflow), dev/plan/00-index.md and 00-conventions.md (how a new plan Pxx is added; numbering of the latest plan; what a plan must contain; the cross-plan checks in dev/research/assets/consolidation-tools/README.md), dev/PROGRESS.md and dev/HANDOFF.md heads, and the lintr/style rules. Report exact file names, section headings and the structure the new docs should follow.`,
  },
  {
    key: 'gptr-serve-surface',
    agentType: 'general-purpose',
    prompt: `Goal: decide what 'all of gptr's functionality through an external agent' can mean with the smallest design. Read gptr's MCP server (R/mcp-server.R in full: the served tools r, inspect, read, edit, write; their schemas, annotations, instructions; how a served session's mode and permission gate apply; plan mode scratch overlay; images/plots in results; what the dedicated served session records — does a served session become a gptr session that is recorded as a runnable document, can the user resume it with gptr_last() |> peter()?), R/mcp-*.R and anything the served r tool exposes (peter$ members such as describe, undo, checkpoints, artifacts, gptr_doc export of the served session). Compare with what GptrAgent bridges today (sessions, inspect, r only: /Users/wgu/biorouter-runs/baam-refresh-2026-11/GptrAgent/src/gptragent/server.py). Answer: (1) which gptr capabilities an external agent can already reach through r/inspect (e.g. calling peter$..., gptr_undo, gptr_doc, gptr_artifacts from R code — and whether gptr's risk classifier/permission gate allow or block them in each mode); (2) whether bridging gptr's read/edit/write tools adds anything an agent like Claude Code or Codex lacks (they have their own file tools) versus Biorouter (which has a Developer extension); (3) what a served session leaves behind for reproducibility (is every call recorded? where? can the user export it as a runnable script?) — this matters for gptr's pillar 3; (4) any gptr-side gap that would block a Claude Code or Codex plugin from working the same way as Biorouter (e.g. timeouts, images, instructions text naming Biorouter, the inspect tool on 1.1). Cite lines.`,
  },
]

phase('Research')
const results = await parallel(TASKS.map(t => () =>
  agent(`${t.prompt}\n\n${PATHS}\n\n${RULES}`, { label: `research:${t.key}`, phase: 'Research', schema: SCHEMA, model: 'sonnet', agentType: t.agentType })
    .then(r => ({ key: t.key, result: r }))
))
const done = results.filter(Boolean).filter(r => r.result)
const missing = TASKS.map(t => t.key).filter(k => !done.find(d => d.key === k))
const unsure = done.filter(d => d.result.confident === false).map(d => d.key)
if (missing.length) log(`No result from: ${missing.join(', ')}`)
if (unsure.length) log(`Not confident: ${unsure.join(', ')}`)
return { done, missing, unsure }
