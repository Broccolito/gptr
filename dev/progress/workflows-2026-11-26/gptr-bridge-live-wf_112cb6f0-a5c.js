export const meta = {
  name: 'gptr-bridge-live',
  description: 'Live end-to-end checks of gptr Agent 1.3.0 in Claude Code, Codex and Biorouter against real served R sessions',
  phases: [
    { title: 'Live', detail: 'three live drivers', model: 'sonnet' },
  ],
}

const REPO = '/Users/wgu/Desktop/gptr/.claude/worktrees/gptr-biorouter-bridge-coord-2d1eed'
const COMMON = `You live-test gptr Agent 1.3.0 (the bridge in ${REPO}/gptragent, plan ${REPO}/dev/plan/P34-agent-plugins.md; read gptragent/README.md first). gptr 1.3.0 from this branch is installed in /private/tmp/claude-501/gptr130-lib (use R_LIBS="/private/tmp/claude-501/gptr130-lib:/Users/wgu/Library/R/arm64/4.6/library"); /usr/local/bin/R is R. Do NOT edit or commit anything in ${REPO} or any other git worktree; write only under your own scratch folder (given below). Never print tokens, API keys or credentials (serve-*.json token values, ~/.codex/auth.json, ~/.claude/.credentials.json, live-test.env values). Do not change the user's real Claude Code or Codex configuration (no plugin install, no mcp add into ~/.claude or ~/.codex); throwaway CLAUDE_CONFIG_DIR/CODEX_HOME are fine for install checks. Keep model usage small (a handful of short prompts).

How to run a served R session (pattern from the WP-14 harness at /Users/wgu/biorouter-runs/gptr-bridge-1.3.0/scripts: start_r.sh starts an interactive R fed by a FIFO, rsend.sh sends a line and waits for a marker; copy and adapt them into your scratch folder with YOUR OWN R_USER_DATA_DIR/R_USER_CONFIG_DIR/R_USER_CACHE_DIR and HOME under your scratch folder, so the bridge only sees your session, never the user's own R sessions). In it: library(gptr); load the fixture /Users/wgu/biorouter-runs/gptr-bridge-1.3.0/scripts/fixture.R (cohort, bmi, untouched); gptr_doc("<scratch>/agent.R") to bind a document; then invisible(gptr_mcp_serve(envir = globalenv(), advertise = TRUE, mode = "auto")). Export the same R_USER_CACHE_DIR to the agent process so the bridge finds the record. Stop R at the end (gptr_mcp_serve(stop = TRUE); q("no")) and kill the FIFO holder.

Checks after the agent runs, inside R via rsend: the objects the agent was asked to make exist with the right values; 'untouched' is unchanged (rlang::hash vs .e2e$fp_untouched); length of the gptr.mcp_r entries on gptr_last() (count custom entries with custom_type "gptr.mcp_r" in gptr_last()'s entries or JSONL file); the bound agent.R contains '# direct R (no model)' lines with the agent's code; gptr_export("<scratch>/agent.R", "<scratch>/analysis.R") succeeds and the exported script, sourced in a FRESH R with the fixture loaded first, recreates the agent's objects. Report exact outputs (tool calls the agent made, answers, R checks).`

const VERDICT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail', 'unsure'] },
    scenarios: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, result: { type: 'string', enum: ['pass', 'fail', 'skipped'] }, evidence: { type: 'string' } }, required: ['name', 'result', 'evidence'] } },
    defects: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, detail: { type: 'string' }, evidence: { type: 'string' } }, required: ['severity', 'detail', 'evidence'] } },
    summary: { type: 'string' },
  },
  required: ['verdict', 'scenarios', 'defects', 'summary'],
}

const TASKS = [
  {
    key: 'claude',
    prompt: `${COMMON}

Your scratch folder: /private/tmp/claude-501/live-claude. Host: Claude Code 2.1.323 (/opt/homebrew/bin/claude) with the user's real login, loading the plugin for one session only with --plugin-dir ${REPO}/gptragent (no install). Run each prompt as: claude -p "<prompt>" --plugin-dir ${REPO}/gptragent --model haiku --output-format stream-json --verbose --no-session-persistence --permission-mode dontAsk --allowedTools "mcp__plugin_gptr_gptr__sessions mcp__plugin_gptr_gptr__inspect mcp__plugin_gptr_gptr__r" < /dev/null, with R_USER_CACHE_DIR exported. Confirm from the init event that the server plugin:gptr:gptr is connected and the three tools and the skill gptr:gptr-live-r are listed. Scenarios: (1) "Which R sessions can you reach? Describe the data frame cohort in my R session." (expects sessions then inspect, 200 rows); (2) "In my R session create n_f, the number of rows of cohort whose sex is exactly \\"F\\". Do not change cohort." (expects r; verify n_f in R equals sum(cohort$sex == "F")); (3) "Plot a histogram of cohort$sbp in my R session." (expects an image content block in the tool result); (4) "Run rm(list = ls()) in my R session." (expects gptr to refuse; verify untouched and cohort still exist); (5) the recording checks from the common section. (6) GitHub install path in a throwaway CLAUDE_CONFIG_DIR (no auth needed): claude plugin marketplace add Broccolito/gptr@claude/v1.3.0 (if the @ref form is refused, try owner/repo#ref per claude plugin marketplace add --help), claude plugin install gptr@gptr, claude plugin details gptr@gptr, claude mcp list (expect plugin:gptr:gptr Connected); also try --sparse .claude-plugin gptragent and report whether it works and how much it downloads versus the full clone (du -sh of the marketplace folder).`,
  },
  {
    key: 'codex',
    prompt: `${COMMON}

Your scratch folder: /private/tmp/claude-501/live-codex. Host: Codex CLI 0.157.1 (/opt/homebrew/bin/codex). Part A, plugin install from GitHub in a throwaway CODEX_HOME (no auth needed): CODEX_HOME=<scratch>/home codex plugin marketplace add Broccolito/gptr --ref claude/v1.3.0, codex plugin add gptr@gptr, codex plugin list, codex mcp get gptr; then drive 'codex app-server' over stdio in that CODEX_HOME (initialize, initialized, mcpServerStatus/list) and confirm server gptr lists inspect, r, sessions; also skills/list shows gptr:gptr-live-r. Try --sparse gptragent --sparse .agents and report. Part B, live with the user's real login (no config written): run codex exec --ephemeral --skip-git-repo-check --json with -c overrides that reproduce the plugin's MCP entry exactly as gptragent/.codex-plugin/plugin.json declares it (command uv, args, cwd = absolute ${REPO}/gptragent/src, env_vars, startup_timeout_sec, tool_timeout_sec) under the server name gptr, plus -c 'approval_policy="never"' and whatever is needed for MCP tools to run without prompting (read codex exec --help; do not use --dangerously-bypass-approvals-and-sandbox unless nothing else lets MCP tools run, and say which you used); export R_USER_CACHE_DIR so env_vars forwards it. Scenarios (1) describe cohort, (2) create n_f, (4) rm(list = ls()) refused, (5) recording checks. Report the tool calls from the JSON events and the R checks.`,
  },
  {
    key: 'biorouter',
    prompt: `${COMMON}

Your scratch folder: /Users/wgu/biorouter-runs/gptr-bridge-1.3.0 (the run folder; the scripts there are a copy of the Biorouter campaign's WP-14 harness already pointed at RUN=/Users/wgu/biorouter-runs/gptr-bridge-1.3.0/e2e, ISO=/Users/wgu/bi-iso/gptr-1.3.0 and the released Biorouter 1.94.6 binary /Users/wgu/biorouter-runs/bin-1.94.6/biorouter; read run_all.sh, brun.sh, e2e.py, start_r.sh, drive.py, restart_check.py and verify.R first). The e2e R library $RUN/rlib already holds gptr 1.3.0 from this branch, $RUN/rlib11 holds CRAN gptr 1.1.0.
Steps: (1) Get the bundle users get: the PR's 'gptragent' workflow run on branch claude/v1.3.0 (gh run list -R Broccolito/gptr --workflow gptragent.yaml --branch claude/v1.3.0 --limit 1) uploads the artifact gptragent-bundle-ubuntu-latest; wait for it if the run is still going (check every 2 minutes, at most 25 minutes), then gh run download <id> -R Broccolito/gptr -n gptragent-bundle-ubuntu-latest -D $RUN/artifact; verify its SHA256SUMS and that its manifest says version 1.3.0 and repository https://github.com/Broccolito/gptr. (2) Create a fresh isolated profile at /Users/wgu/bi-iso/gptr-1.3.0: copy config/config.yaml and config/privacy-tiers.json from /Users/wgu/bi-iso/baam/wp14-e2e (inspect them first and copy only if they hold no secret values — report field names only), create home/, then install the artifact: env -i PATH=/opt/homebrew/bin:/usr/bin:/bin HOME=/Users/wgu/bi-iso/gptr-1.3.0/home BIOROUTER_PATH_ROOT=/Users/wgu/bi-iso/gptr-1.3.0 BIOROUTER_DISABLE_KEYRING=true UV_CACHE_DIR=/Users/wgu/.cache/uv UV_PYTHON_INSTALL_DIR=/Users/wgu/.local/share/uv/python /Users/wgu/biorouter-runs/bin-1.94.6/biorouter extension install $RUN/artifact/gptragent.brxt; confirm config/extensions/gptragent/manifest.json says 1.3.0. (3) Run the whole harness: bash $S/run_all.sh > $RUN/run_all.log 2>&1 (it starts R, loads the fixture, serves, drives the bridge without a model, runs the restart check, then scenarios S1-S12 on Versa gpt-5.5 — keep to exactly these scenarios: the owner has a cost concern; Versa keys load only inside brun.sh from /Users/wgu/Desktop/biorouter/live-test.env, never print them). Compare $RUN/e2e/summary.json (or the verdict files) with the 0.1.2 baseline at /Users/wgu/biorouter-runs/baam-refresh-2026-11/WP-14/e2e/summary.json (0.1.2: everything passed but s4; s11 not run). Report each scenario, any regression, the tool calls in a failing scenario's transcript, and clean up the R processes the harness started (their pid files are under $RUN).`,
  },
]

phase('Live')
const results = await parallel(TASKS.map(t => () =>
  agent(t.prompt, { label: `live:${t.key}`, phase: 'Live', schema: VERDICT, model: 'sonnet' }).then(r => ({ key: t.key, result: r }))
))
return results
