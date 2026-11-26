export const meta = {
  name: 'gptr-biorouter-bridge-map',
  description: 'Read-only map of the GptrAgent bridge: architecture, gptr contract cross-check, peer-claim verification, gptr-side gaps, Biorouter integration',
  phases: [
    { title: 'Read', detail: 'five independent read-only investigations', model: 'sonnet' },
    { title: 'Critique', detail: 'completeness and contradiction critic', model: 'sonnet' },
  ],
}

const RULES = `STRICTLY READ-ONLY. Do not edit, create or delete any file outside your own scratch use, do not commit, push, tag, open/merge/comment on PRs or issues, do not run gh commands that mutate anything, do not start gptr_mcp_serve or any server, do not touch running R sessions. Never print or copy tokens: if you look at a live discovery record (serve-*.json) or any .secrets / auth.json file, report field names only, never values. Rscript --vanilla -e for harmless queries (e.g. tools::R_user_dir) is fine. Cite evidence as absolute_path:line. Be concrete and terse.`

const PATHS = `Key locations:
- GptrAgent (Biorouter extension, Python stdio MCP server, git repo, remote Broccolito/GptrAgent): /Users/wgu/biorouter-runs/baam-refresh-2026-11/GptrAgent (src/gptragent/, r/attach.R, manifest.json, skills/gptr-live-r/SKILL.md, tests/, scripts/build_brxt.py, .github/workflows/)
- WP-14 (bridge work package evidence): /Users/wgu/biorouter-runs/baam-refresh-2026-11/WP-14 (handoff.json, releases/gptragent.json, catalog-rows/gptragent.json, e2e/summary.json, e2e/s*.jsonl, e2e/round1/, scripts/run_all.sh)
- WP-13 (gptr 1.2.0 work package handoff): /Users/wgu/biorouter-runs/baam-refresh-2026-11/WP-13/handoff.json
- gptr package, main branch incl. 1.2.0 (PR #124 merged): /Users/wgu/Desktop/gptr/.claude/worktrees/gptr-biorouter-bridge-coord-2d1eed (R/mcp-server.R, R/auth-secrets.R, R/gptr-config.R, R/zzz.R, tests/testthat/test-mcp-advertise.R, tests/testthat/test-mcp-server.R, vignettes/mcp.Rmd, NEWS.md, dev/spec/, dev/plan/)
- Biorouter app repo, main: /Users/wgu/Desktop/biorouter (landing/scripts/build-registry.mjs, landing/baam.html, crates/biorouter/src/privacy/, secret guard code); GitHub BaranziniLab/biorouter (open PR #552)
- Campaign plans: /Users/wgu/biorouter-runs/baam-inventory-2026-11-21/PLAN.md and /Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-20-claude/STATUS.md`

const PEER = `The Biorouter campaign session (another Claude session) reported:
1. Broccolito/GptrAgent is public; main at f15cd43 after Windows fixes 156a4cc and f15cd43; v0.1.0 tagged on f15cd43 and released (release.yml run 44874753403; gptragent.brxt sha256 3c74671e8dfcf851f1a93f0c7016733f36eae25175376ad21f6f669c600e8d4b); CI run 44874620096 passed unit tests on 3 OSes and live R on ubuntu and macos; WP-14/handoff.json is stale.
2. Design: discovery reads R_user_dir("gptr","cache")/mcp-serve/serve-<pid>.json (0600 in 0700 folder, atomic, removed at stop/unload/exit, swept at next load if pid dead). On gptr >= 1.2, r/attach.R calls gptr_mcp_serve(advertise = ...); on 1.0/1.1 it writes a compatible 0600 record itself and removes it on detach or R exit (the stand-in path). Bridge is a stdlib stdio MCP server using http.client, no proxy, no redirects. Tools: sessions (read-only; lists live records, attaches, returns overview; with none returns a one-line setup instruction), inspect (read-only; gptr's served inspect on 1.2; on 1.1 runs gptr_risk() first), r (destructive; timeout capped at 280 s under Biorouter's 300 s). Bundled skill gptr-live-r: inspect first, never reload data, verify in R.
3. Gaps: e2e s4 fails (gpt-5.5, on an error inside an assignment x <- f(...) it refits a different existing object instead of creating x or asking; wish: a gptr error read that includes the full top-level call expression incl. assignment target). processx 3.10.0 sets PROCESSX_RM_PATH on load so the user's R env changes on gptr's first processx use; gptr commit 24d3c2c9 fixed the test, not the behaviour. Windows record protection relies on profile ACL, no chmod.
4. WP-01 not in a PR yet: workflow wf_c13af600-371 (BAAM wave 2) Site phase will change EXPECTED_PRIVATE_EXTENSIONS (gptragent, null affiliation), regenerate registry_private.rs, add baam.html card, open a BaranziniLab/biorouter PR flagged Needs human review that auto-merges with a merge commit.
5. WP-21 not done: Biorouter secret guard has no **/R/gptr/mcp-serve/serve-*.json rule; open PR #552 only adds a generic rule for helper apps in the extensions folder. e2e: s1,s2,s3,s5,s6,s7,s10,s12 pass; s4 fails; s11 (privacy) waits for WP-01.
6. Coordinate before changing the discovery record path/fields (attach.R and discovery.py parse them; the planned guard glob depends on the path), before changing mode values, and before CRAN submission of 1.2.0 (owner's call). GptrAgent works with CRAN gptr 1.1 via attach.R, no pin needed. Treat the gptr-1.2.0-biorouter branch as frozen; do not touch GptrAgent main/tags.`

const FINDINGS = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'one dense paragraph' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          topic: { type: 'string' },
          detail: { type: 'string' },
          evidence: { type: 'string', description: 'absolute_path:line or command output' },
          severity: { type: 'string', enum: ['info', 'gap', 'risk', 'bug'] },
        },
        required: ['topic', 'detail', 'evidence', 'severity'],
      },
    },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'findings', 'open_questions'],
}

const CLAIMS = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    claims: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          verdict: { type: 'string', enum: ['confirmed', 'refuted', 'partly', 'unverifiable'] },
          evidence: { type: 'string' },
        },
        required: ['claim', 'verdict', 'evidence'],
      },
    },
    open_questions: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'claims', 'open_questions'],
}

const TASKS = [
  {
    key: 'architecture',
    schema: FINDINGS,
    prompt: `Map the GptrAgent bridge's architecture from its source. Read every file under src/gptragent/, r/attach.R, manifest.json, skills/gptr-live-r/SKILL.md, README.md, scripts/build_brxt.py, .github/workflows/*.yml and the tests (fake_gptr.py, test_discovery.py, test_bridge.py, test_stdio.py, test_live.py, test_bundle.py). Report: module layout and responsibilities; the exact MCP tools it exposes (names, input schemas, annotations such as readOnlyHint/destructiveHint, descriptions); how discovery works (which folder per OS, how it computes R_user_dir rules in Python, which record fields it reads and validates, liveness/pid checks, stale record handling, choosing between several sessions, labels); how it attaches and speaks to gptr (HTTP transport, bearer token, MCP session init, timeouts incl. the 280 s cap, error/refusal relay); the stand-in path in attach.R for gptr 1.0/1.1 (what record it writes, how it starts the server, how inspect is emulated with gptr_risk(), cleanup); Windows-specific logic (commits 156a4cc, f15cd43: git -C <repo> show); how the .brxt bundle is built and what goes in it; what the skill tells the model. Note anything that looks fragile or inconsistent.`,
  },
  {
    key: 'contract',
    schema: FINDINGS,
    prompt: `Cross-check the contract between gptr 1.2.0 (producer) and GptrAgent (consumer). On the gptr side read R/mcp-server.R fully (advertise, record writing, sweep at load, removal at stop/unload/exit, mode handling, inspect tool, served instructions, refusal responses), the guarded secret read for discovery records in R/auth-secrets.R, R/zzz.R, and tests/testthat/test-mcp-advertise.R; also WP-13/handoff.json for the documented record contract. On the GptrAgent side read src/gptragent/ (especially the discovery and bridge modules) and r/attach.R. Produce a field-by-field and behaviour-by-behaviour comparison and list every mismatch or assumption that is not guaranteed by gptr: record path rules on macOS/Linux/Windows (R_USER_CACHE_DIR, XDG_CACHE_HOME, platform defaults) vs. the Python reimplementation; field names/types/format version handling; whether GptrAgent tolerates unknown or missing fields and a future format 2; pid liveness and pid reuse; whether gptr 1.2's load-time sweep could delete or misread a stand-in record written by attach.R (and vice versa); whether attach.R's stand-in record is byte-compatible with gptr's; tool names and arguments (r, inspect, read, edit, write) and how GptrAgent calls them; the refusal shape of inspect and how the bridge relays it; mode values; how the token is read (does the bridge read the record directly, and does gptr's guarded secret read apply only to gptr's own agents?). Severity 'bug' only when you can show concrete inputs that break.`,
  },
  {
    key: 'peer-claims',
    schema: CLAIMS,
    prompt: `Independently verify each factual claim the Biorouter campaign session made, below. Use read-only commands: git -C /Users/wgu/biorouter-runs/baam-refresh-2026-11/GptrAgent log/show/tag; gh repo view Broccolito/GptrAgent; gh release view v0.1.0 -R Broccolito/GptrAgent --json assets,tagName,targetCommitish; gh run view <id> -R Broccolito/GptrAgent (read-only); compute shasum -a 256 of the local dist/gptragent.brxt and compare to the claim and to the release asset digest if gh shows one (do not download unless it is cheap and into a fresh empty folder in /tmp/claude-501 scratch; never execute it); read WP-14/e2e/summary.json; grep /Users/wgu/Desktop/biorouter for any mcp-serve / serve-*.json / R/gptr secret-guard rule and locate the secret guard's pattern list; gh pr view 552 -R BaranziniLab/biorouter --json title,state,files and gh pr diff 552 -R BaranziniLab/biorouter to see what it adds; read landing/scripts/build-registry.mjs EXPECTED_PRIVATE_EXTENSIONS on biorouter main and check whether gptragent appears in registry.json / registry_private.rs / baam.html; check whether gptr commit 24d3c2c9 changes only a test. Give one verdict per numbered sub-claim.\n\n${PEER}`,
  },
  {
    key: 'gptr-gaps',
    schema: FINDINGS,
    prompt: `Assess the gptr-side wishes and gaps the campaign session raised, without implementing anything. (a) s4 / error context: read WP-14/e2e/summary.json and the s4 transcripts (e2e/s4.jsonl and round1 if present) to see exactly what the model saw; then find in the gptr package how an error in the served r tool is reported (R/mcp-server.R and the r tool's evaluation path, conditions, traceback, geterrmessage handling, any 'last error' reader) and whether the top-level call expression incl. an assignment target (x <- f(...), x = f(...)) is available at that point. State what a minimal gptr change would be and which file/function it touches, or whether the fix belongs in the skill instead. (b) processx PROCESSX_RM_PATH: find every place gptr loads or uses processx (grep R/ for processx), check whether loading processx sets an env var that persists in the user's session, read gptr commit 24d3c2c9 (git show) to see what it changed, and check gptr's own rule in dev/plan/00-conventions.md and dev/spec/03-architecture.md section 6.4 (never leave env vars changed). Say whether this is a real violation in normal use and where it would be fixed. (c) Windows record protection: read how gptr writes the record on Windows and what guarantees exist. (d) Any other contract gap you notice while reading R/mcp-server.R from the perspective of an external client like GptrAgent. Check dev/PROGRESS.md, dev/HANDOFF.md, dev/DEVIATIONS.md and dev/progress/open-findings.md for anything already ledgered about these.`,
  },
  {
    key: 'biorouter-integration',
    schema: FINDINGS,
    prompt: `Explain how GptrAgent plugs into Biorouter (repo /Users/wgu/Desktop/biorouter, main; read-only). Find and summarise: how .brxt extensions are installed and launched (stdio MCP subprocess, env, working folder, per-tool timeout of 300 s), the extension registry and the 'private extensions' closed set (landing/scripts/build-registry.mjs EXPECTED_PRIVATE_EXTENSIONS, its tests, registry.json, registry.fallback.json, crates/biorouter/src/privacy/registry_private.rs) and what 'private with null affiliation' would mean for gptragent (what privacy behaviour it triggers, why it is security code); the marketplace card format in landing/baam.html and baam-details.js; the secret guard (where credential-file patterns live, how a rule like **/R/gptr/mcp-serve/serve-*.json would be added, and whether the bridge itself, which must read the token, would be blocked by such a rule or exempted); how Biorouter treats tool annotations (readOnlyHint/destructiveHint) for approval. Also read the campaign plan(s) for WP-01, WP-13, WP-14, WP-21, WP-22 and the decisions they cite (e.g. 'plan ground rule 5, decision 1', 'decision 2'): /Users/wgu/biorouter-runs/baam-inventory-2026-11-21/PLAN.md and /Users/wgu/biorouter-runs/orchestration-2026-11-12/handoff-2026-11-20-claude/STATUS.md, and the WP-14 catalog row draft. Report the full dependency chain to ship the bridge end to end.`,
  },
]

phase('Read')
const results = await parallel(TASKS.map(t => () =>
  agent(`${t.prompt}\n\n${PATHS}\n\n${RULES}`, { label: `read:${t.key}`, phase: 'Read', schema: t.schema, model: 'sonnet' })
    .then(r => ({ key: t.key, result: r }))
))
const done = results.filter(Boolean).filter(r => r.result)
const missing = TASKS.map(t => t.key).filter(k => !done.find(d => d.key === k))
if (missing.length) log(`No result from: ${missing.join(', ')}`)

phase('Critique')
const critic = await agent(
  `You are a completeness and contradiction critic. Below are five independent read-only investigations of the GptrAgent bridge between the gptr R package and the Biorouter app, plus the campaign session's own claims. (1) List contradictions between investigations or between them and the peer claims, and resolve each by reading the cited source yourself. (2) List important questions none of them answered and answer the ones you can by reading the code. (3) Re-check every finding marked 'bug' or 'risk' by reading the cited lines; drop any that do not hold and say why. Return the corrected, consolidated findings.\n\n${PEER}\n\nINVESTIGATIONS:\n${JSON.stringify(done, null, 1)}\n\n${PATHS}\n\n${RULES}`,
  { label: 'critic', phase: 'Critique', schema: FINDINGS, model: 'sonnet' }
)
return { investigations: done, critic, missing }
