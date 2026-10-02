# Track 20 — Feature survey of Claude Code, Codex and other harnesses (model-facing tools, orchestration, instructions, hooks, context, notebooks, R tooling)

Research date: 2026-09-29 (Codex source snapshot is 2026-09-30 01:34 UTC). Author: research sub-agent, track 20.
Requirements (`REQ-nn`) and decisions (`S-n`, `D-nn`) refer to
`/Users/wanjun/Desktop/gptr/dev/spec/00-vision-brief.md` and `01-decision-register.md`.

Evidence levels: **VERIFIED** = I read the cited primary source or ran the cited command myself;
**LIKELY** = inferred from verified evidence; **UNCERTAIN** = not verifiable here.

Prior work: a previous researcher on this track left raw downloads only (no draft report) in
`.../scratchpad/work/track-20/docs/{cc,codex}`. I re-downloaded 17 of the Claude Code pages and 3 Codex
pages and compared them byte-for-byte: 16/17 and 3/3 identical (`hooks.md` had changed; I used the fresh copy).
All fresh downloads are in `.../scratchpad/work/track-20/verify/`. Abbreviations for local evidence:

| Abbrev. | What | Location |
|---|---|---|
| `CC/<page>` | Claude Code docs `https://code.claude.com/docs/en/<page>.md` (fetched 2026-09-29) | `.../work/track-20/verify/<page>.md` (or `docs/cc/`) |
| `SDK` | Claude Agent SDK TypeScript reference `CC/agent-sdk/typescript` | `.../verify/agent-sdk_typescript.md` |
| `CX/<path>` | openai/codex, commit `8ea2c0e0d4bc` (2026-09-30), sparse clone | `.../work/track-20/codex-src/<path>` |
| `CXD/<page>` | Codex docs `https://learn.chatgpt.com/docs/<page>.md` | `.../verify/codex/` and `.../docs/codex/` |
| `BTW/<path>` | posit-dev/btw commit `a471e6de` (1.5.0.9000), shallow clone | `.../work/track-20/btw-src/<path>` |
| `PROTO/<file>` | my R prototypes and their outputs | `.../work/track-20/proto/` |

(`...` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad`.)

Local CLIs: `claude --version` → `2.1.261 (Claude Code)`; `codex --version` → `codex-cli 0.157.0` (executed). The
docs describe up to Claude Code v2.1.285 (top of `CHANGELOG.md`, fetched) — some features below are newer than the local CLI.

---

## 1. Executive summary

1. **Claude Code's tools reference lists 46 built-in tools**, but the everyday core is `Read`, `Write`, `Edit`, `Bash`, `Agent`,
   `AskUserQuestion`, `WebFetch`, `WebSearch`, `NotebookEdit`, `EnterPlanMode`/`ExitPlanMode`, `Skill`
   (`CC/tools-reference` table, lines 19-66). **`Glob` and `Grep` are now absent by default on macOS/Linux/WSL**
   (the model uses embedded `bfs`/`ugrep` through `Bash`); they are default only on Windows (lines 261-269).
   **`MultiEdit` no longer exists** in the current tool list or changelog. VERIFIED.
2. **Both leading harnesses have turned their todo tools off by default.** Claude Code v2.1.268+ provides
   `TodoWrite`/`Task*` only on older models ("On newer models, Claude keeps track of multi-step work without a written
   checklist, and the tools' definitions and reminders take up context", `CC/tools-reference` 526-528); Codex's `update_plan` is enabled
   only when `[tools.update_plan] enabled = true` (`CX/codex-rs/core/src/config/mod.rs:2717-2723`). VERIFIED. →
   gptr v1 should **not** ship a todo tool.
3. **Codex's model-visible tools today** (HEAD 2026-09-30): `exec_command` + `write_stdin` (unified PTY exec; the old
   shell tool types `default`/`local`/`shell_command` are now serde aliases of `UnifiedExec`,
   `CX/codex-rs/protocol/src/openai_models.rs:312-318`), `apply_patch` (**freeform/grammar tool only** — the JSON variant is gone),
   `view_image`, `request_user_input` (Plan mode only), hosted `web_search`, multi-agent tools
   (`spawn_agent`, `send_input`, `resume_agent`, `wait_agent`, `close_agent`; v2: `send_message`, `followup_task`,
   `interrupt_agent`, `list_agents`), MCP resource tools, and optional `update_plan`, `get_context_remaining`,
   `new_context_window`, `request_permissions`, `sleep` (`CX/.../tools/spec_plan.rs:1015-1420`). VERIFIED.
4. **`apply_patch` format is fully specified** by a 19-line Lark grammar (`CX/codex-rs/core/assets/tools/apply_patch.lark`)
   plus lenient-parsing rules and a 4-level fuzzy line matcher (exact → rstrip → trim → Unicode-punctuation
   normalised) (`CX/codex-rs/apply-patch/src/seek_sequence.rs`). I wrote a **pure-R port (277 lines, base R) that passes
   25/25 of Codex's official portable conformance fixtures** byte-for-byte, including CRLF and mixed line endings,
   and handles a 50,000-line file in 0.41 s (`PROTO/apply_patch.R`, §5.1). VERIFIED.
5. **Recommendation on apply_patch:** yes — gptr should accept it, but as a **model-family-specific tool, not as an
   alternative input shape of `edit`**. opencode already does exactly this: GPT models (`gpt-*`, not `oss`, not `gpt-4`)
   get `apply_patch` *instead of* `edit`/`write` (`anomalyco/opencode@2fa3363c packages/opencode/src/tool/registry.ts:297-300`).
   OpenAI's Responses API also has a native `{"type":"apply_patch"}` tool (GPT-5.1/5.2/5.4/5.5) emitting per-file V4A
   diffs; my R engine applies those too via a 10-line adapter. `edit` should additionally *detect* a pasted
   `*** Begin Patch` envelope and route it to the same engine. VERIFIED facts / design recommendation.
6. **Anthropic's analogue** is the API-defined text editor tool `text_editor_20250728` / name `str_replace_based_edit_tool`
   with commands `view`, `str_replace`, `create`, `insert` (`platform.claude.com/.../text-editor-tool`). Claude Code's own
   `Edit` (`file_path`, `old_string`, `new_string`, `replace_all`) is the same exact-match idea. Pi's `edit` (track 01)
   is schema-compatible in spirit. VERIFIED.
7. **Sub-agents**: Claude Code uses Markdown files `.claude/agents/*.md` with YAML frontmatter (required `name`,
   `description`; optional `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`,
   `hooks`, `memory`, `background`, `omitClaudeMd`, `effort`, `isolation`, `color`, `initialPrompt`, `experimental`)
   (`CC/sub-agents` 296-319). Codex uses **TOML** files `.codex/agents/*.toml` (required `name`, `description`,
   `developer_instructions`; any `config.toml` key such as `model`, `model_reasoning_effort`, `sandbox_mode`,
   `mcp_servers`) with built-ins `default`, `worker`, `explorer` (`CXD/agent-configuration/subagents` 332-399). btw
   (R) already reads `.claude/agents/` (`BTW/R/btw-config.R:52-66`). My R reader normalises both (§5.5). VERIFIED.
8. **Parallel/background sub-agents are presented to the model as asynchronous handles plus later notifications**:
   Claude Code returns `{status:"async_launched", agentId, outputFile, ...}` and delivers the result "as a completion
   notification in a later turn" (`SDK` 3566-3638; `CC/sub-agents` 886-908). Codex injects
   `<subagent_notification>{"agent_path":…,"status":…}</subagent_notification>` user fragments and
   `Message Type: FINAL_ANSWER\nTask name: …\nSender: …\nPayload:\n…` messages
   (`CX/.../context/subagent_notification.rs`, `inter_agent_completion_message.rs`). Limits: Claude — depth 3, 20
   concurrent; Codex — depth 1, 6 threads (v1) / 4 concurrent (v2), `wait_agent` default 30 s. VERIFIED.
9. **Codex's spawn_agent description forbids unsolicited delegation**: "Do not spawn sub-agents unless the user or
   applicable AGENTS.md/skill instructions explicitly ask for sub-agents…" (`CX/.../multi_agents_spec.rs:706`) and
   gives a detailed delegation playbook (critical path vs sidecar tasks, disjoint write sets, call `wait_agent`
   sparingly). Worth copying into gptr's `agent` tool description. VERIFIED.
10. **Project instruction files converge on `AGENTS.md`** (agents.md standard, now stewarded by the Agentic AI
    Foundation under the Linux Foundation; used by Codex, Gemini CLI via `context.fileName`, Aider via `read:`, Posit
    Assistant as its "memory", btw as fallback). Claude Code ≥ v2.1.277 reads `AGENTS.md` when there is no
    `CLAUDE.md`/`CLAUDE.local.md` on the path (`CC/memory` 345-373). Import syntax `@path` (Claude, Gemini, Posit
    Assistant; max depth 4 hops in Claude; skipped inside code spans/fences). Codex concatenates root→cwd, one file per
    directory (`AGENTS.override.md` > `AGENTS.md` > fallbacks), 32 KiB cap, injected as a **user-role** fragment
    `# AGENTS.md instructions for <dir>\n\n<INSTRUCTIONS>\n…\n</INSTRUCTIONS>` (`CX/.../context/user_instructions.rs:23-34`).
    Claude also delivers CLAUDE.md as a user message, not in the system prompt (`CC/memory` 561). VERIFIED.
11. **gptr interop design (prototyped, §5.3)**: load `.gptr/vignette.Rmd` (YAML header and HTML comments stripped),
    then per directory from project root to cwd `AGENTS.md` (else `CLAUDE.md`, configurable), expand `@imports`
    (file-relative, then project-root-relative for `.gptr/vignette.Rmd`), dedupe by normalised path, cap at 64 KiB,
    wrap each in `<instructions source="…">`. VERIFIED by running.
12. **Hooks**: Claude Code has 33 events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`,
    `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Stop`, `SubagentStart/Stop`, `PreCompact/PostCompact`,
    `SessionEnd`, …), five handler types (`command`, `http`, `mcp_tool`, `prompt`, `agent`), JSON on stdin, exit 2 =
    block, `hookSpecificOutput.permissionDecision ∈ {allow, deny, ask, defer}`, `updatedInput`, `additionalContext`
    (`CC/hooks` 35-69, 404-450, 782-1051). Codex deliberately copies the names and JSON shapes for a subset (plus
    `Interrupt`), with hash-based hook trust; legacy `notify = [argv]` fires on `agent-turn-complete`
    (`CXD/hooks`, `CXD/config-file/config-advanced` 680-730). VERIFIED. → gptr R-level hooks should reuse these event
    names and decision fields as R lists.
13. **Context management**: Claude auto-compacts at the model limit (≈967K on native-1M models), re-injects root
    CLAUDE.md, auto memory, plan file, ≤5 recently edited files and invoked skills (≤5K tokens each)
    (`CC/context-window` 1592-1633). Codex auto-compacts at 90% of the window by default with a published 10-line
    handoff prompt and "Another language model started to solve this problem…" prefix
    (`CX/codex-rs/prompts/templates/compact/*.md`; `CX/codex-rs/protocol/src/openai_models.rs:456-458`). Posit
    Assistant: 30,000-token buffer + an explicit `/microcompact` that stubs old tool results. VERIFIED.
14. **Plan mode** is a *mode*, not really a tool, everywhere: Claude has `EnterPlanMode` (no input) and `ExitPlanMode`
    (plan written to a file first; input effectively empty); Codex's Plan mode is a developer-message template that
    forbids mutation and requires a final `<proposed_plan>` block; Posit Assistant and Gemini write plan files.
    `request_user_input` in Codex is available **only** in Plan mode by default (an under-development feature flag,
    off by default, also enables it in Default mode). VERIFIED.
15. **Notebook support**: Claude `NotebookEdit {notebook_path, cell_id?, new_source, cell_type?, edit_mode?}` and `Read`
    renders `.ipynb` cells+outputs; Codex has no notebook tool; Positron Assistant had `editNotebook`,
    `executeNotebook`, `getNotebookInfo`, `createNotebook`. A Claude-compatible `notebook_edit` in pure R (jsonlite)
    round-trips nbformat JSON losslessly (`{}` vs `[]` preserved) (§5.4). VERIFIED.
16. **R-specific agents**: btw 1.5.0 (CRAN) ships 38 ellmer tools in 13 groups — docs (`help_page`, `vignette`,
    `package_help_topics`, `package_news`), env (`describe_data_frame`, `describe_environment`), `run_r` (**opt-in**, via
    `evaluate`, captures plots), files (incl. **an R implementation of the apply_patch envelope** and hashline edits),
    CRAN, git, pkg dev, sessioninfo, skills, subagent (§2.13, extracted by parsing BTW sources). Positron Assistant
    (succeeded by Posit Assistant as of June 2026) had `executeCode`, `inspectVariables`, `getPlot`, `getTableSummary`, `getProjectTree`,
    `getChangedFiles` + 4 notebook tools. **Posit Assistant** (Posit's new harness in RStudio/Positron/terminal) reads
    `AGENTS.md` as memory, auto-injects "names and types of variables (not their values)", has Normal/Auto/YOLO/Restricted
    approval modes plus Ask (read-only, *no R execution*) and Plan modes. VERIFIED.
17. **R-native introspection is cheap**: help page as text without `:::` via `utils::help()` → `tools::Rd_db()` →
    `tools::Rd2txt()` in 0.4–1.0 s cold (Rd_db of ggplot2 0.19–0.37 s); `help.search()` over 613 installed packages
    1.1–1.3 s cold / 0.3–0.5 s warm; bounded description of a 2e6-row data.frame 0.04–0.06 s (§5.2; ranges = author run
    and verifier re-run, same machine). VERIFIED (timings are machine-dependent).
18. **Recommended gptr v1 model-visible tools** (§4.1): `read`, `write`, `edit`, `grep`, `find`, `ls`, `run_r`,
    **`r_inspect`** (read-only, approval-free object/help/package/session introspection that still works in plan mode),
    `ask`, `agent`; auto-substituted `apply_patch` for GPT-5 family; opt-in `shell`, `notebook_edit`,
    `web_fetch`/`web_search` (prefer provider server-side tools). Defer todo, plan-mode tools, Monitor/cron/goal,
    worktrees, agent teams, LSP, auto memory.

---

## 2. Findings

### 2.1 Harnesses and versions surveyed

| Harness | Version / snapshot | Primary evidence |
|---|---|---|
| Claude Code | docs 2026-09-29 (≈v2.1.285); local CLI 2.1.261 | `CC/*` (27 pages), `claude --help` (executed) |
| Claude Agent SDK (TS) | tool input/output types | `SDK` 2792-3900 |
| Codex CLI | source `8ea2c0e0` (2026-09-30); local 0.157.0 | `CX/codex-rs/{core,apply-patch,protocol,prompts,collaboration-mode-templates,config}`, `codex --help`, `codex features list` (executed) |
| OpenAI API | Apply Patch & Shell tool guides | `developers.openai.com/api/docs/guides/tools-apply-patch.md`, `tools-shell.md` |
| OpenAI Agents SDK | `apply_diff.py` (V4A reference) | `raw.githubusercontent.com/openai/openai-agents-python/main/src/agents/apply_diff.py` |
| opencode | `anomalyco/opencode@2fa3363c` (dev) | docs `opencode.ai/docs/tools/`, `registry.ts` |
| Gemini CLI | `google-gemini/gemini-cli@38700b4b` | `docs/tools/*.md`, `docs/cli/gemini-md.md` |
| Aider | main | `aider.chat/docs/more/edit-formats.html`, `aider/coders/*.py`, `resources/model-settings.yml` |
| Goose | `aaif-goose/goose` (moved from block/goose) | `goose-docs.ai/docs/mcp/developer-mcp/` |
| btw (R) | 1.5.0 on CRAN; source 1.5.0.9000 | `BTW/R/*.R`, pkgdown reference |
| Positron Assistant | `posit-dev/positron` tag `latest-daily-2026.06` | `extensions/positron-assistant/package.json` |
| Posit Assistant | docs 2026-09 | `assistant.posit.co/docs/...` |
| Pi (baseline) | `1b347794` | track 01 report; `pi/packages/coding-agent/src/core/tools/edit.ts:21-51` |

CRAN versions (executed `available.packages()` 2026-09-29): btw 1.5.0, mcptools 1.0.3, ellmer **0.5.0** (0.4.0
installed locally), gander 0.2.0, chores 0.3.1, shinychat 0.5.0, commons 0.1.0, evaluate 1.0.5, ragnar 0.3.1, vitals 0.4.0.

### 2.2 Claude Code — built-in tools

Full list with permission requirement (VERIFIED, `CC/tools-reference` lines 19-66):
`Agent` (no), `Artifact` (yes), `AskUserQuestion` (no), `Bash` (yes), `CronCreate/CronDelete/CronList` (no), `Edit`
(yes), `EndConversation` (no), `EnterPlanMode` (no), `EnterWorktree` (yes), `ExitPlanMode` (yes), `ExitWorktree` (no),
`Glob` (no; absent by default on macOS/Linux/WSL), `Grep` (no; same), `ListAgents` (no), `ListMcpResourcesTool` (no),
`LSP` (no), `Monitor` (yes), `NotebookEdit` (yes), `PowerShell` (yes), `PushNotification` (no), `Read` (no),
`ReadMcpResourceTool` (no), `RemoteTrigger` (no), `ReportFindings` (no), `ScheduleWakeup` (no), `SendFeedback` (no),
`SendMessage` (no), `SendUserFile` (no), `ShareOnboardingGuide` (yes), `Skill` (yes), `SubagentHandback` (no),
`TaskCreate/TaskGet/TaskList/TaskUpdate` (no), `TaskOutput` (deprecated; removed v2.1.277 per `SDK` 2926-2930),
`TaskStop` (no), `TodoWrite` (no), `ToolSearch` (no), `WaitForMcpServers` (no), `WebFetch` (yes), `WebSearch` (yes),
`Workflow` (yes), `Write` (yes).

Behaviour details that matter for gptr (all VERIFIED from `CC/tools-reference`):

* **Read** (448-464): returns content with line numbers; whole-file reads over the token limit return the first page with
  a `PARTIAL view` notice explaining `offset`/`limit`; explicit ranges over the limit error; empty file → notice;
  images returned as visual content (resized; >500 KB re-encoded JPEG); PDFs >10 pages need `pages` (≤20 per call, uses
  `pdftoppm`); `.ipynb` returns all cells with outputs (refuses >100 MB); directories are not readable (use `ls`).
* **Edit** (215-229): exact string replacement, no regex/fuzzy; three checks: read-before-edit (relaxed for newer models
  when the read would not need a prompt), exact match, uniqueness (else longer context or `replace_all`). A file changed on
  disk since the read can still be edited if `old_string` matches the current content exactly and uniquely.
* **Write** (595-609): full overwrite; existing files must have been read first (older models always; newer models
  under the same relaxed rule); notebooks and partially-read files always need a read.
* **Glob** (261-283): `**` globbing; results sorted by modification time, **capped at 100** with a truncation flag;
  ignores `.gitignore` by default (unlike Grep).
* **Grep** (285-303): ripgrep regex syntax; `output_mode` `files_with_matches` (default) | `content` | `count`;
  `glob`/`type` filters; `multiline`; respects `.gitignore`; rejected patterns return rg's diagnostic.
* **Bash** (139-187): each command in a separate process; `cd` persists within project dirs; env vars do not persist;
  default timeout 2 min, max 10 min; valid output inline up to ~30,000 chars, beyond that saved to a file with a 2,000-char
  preview; failures get a 10,000-char head+tail excerpt; exit code 1 is benign for `grep`, `rg`, `find`, `diff`,
  `test`, `git diff`, `git grep`; `run_in_background: true`; commands that hit their timeout are **moved to the
  background** rather than killed (message `Command did not complete within its 120s timeout and was moved to the
  background`).
* **NotebookEdit** (375-385): one cell at a time by `cell_id`; `edit_mode` `replace` (default) | `insert` (after
  target; at start if no `cell_id`; requires `cell_type`) | `delete`.
* **WebFetch** (543-571): URL + prompt; HTML→Markdown; a small fast model answers the prompt ("lossy by design"); 15-min
  cache; cross-host redirects returned, not followed; localhost/dotless hosts refused.
* **WebSearch** (573-593): Anthropic server-side search; up to 8 backend searches per call; `allowed_domains` xor
  `blocked_domains`; 200 searches per session.
* **Task tool availability** (524-541): todo/task tools only on Claude 3.x, Opus 4–4.7, Sonnet 4–4.6, Haiku 4.5 by
  default (v2.1.268+); opt in with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`.
* **Parallel execution** (`CC/agent-sdk/agent-loop` 184-188): read-only tools (`Read`, `Glob`, `Grep`, read-only MCP
  tools) run concurrently; state-modifying tools (`Edit`, `Write`, `Bash`) run sequentially; custom tools default to
  sequential unless annotated `readOnlyHint`.

### 2.3 What Claude Code tells the model about tool usage

* The `claude_code` preset system prompt contains "tool usage instructions and security and safety instructions"; the
  Agent SDK's *minimal default* prompt covers only tool calling (`CC/agent-sdk/modifying-system-prompts` 15-16). The
  preset text itself is not published verbatim. VERIFIED.
* **Per-machine context is mostly kept out of the system prompt**: CLAUDE.md and environment details (cwd, platform,
  shell, OS) are delivered in the conversation, not the system prompt; the preset *does* embed the auto-memory location
  in the system prompt by default, and `excludeDynamicSections: true` moves that per-user context into the first user
  message so identical configurations share the prompt cache (208-212, verifier-clarified);
  CLI flag `--exclude-dynamic-system-prompt-sections` (executed `claude --help`). VERIFIED.
* **System reminders** carry CLAUDE.md, output style, attribution lines, hook `additionalContext`, the skills list, the
  sub-agent list, task-list nudges and file-changed notes (393-412). "Claude Code introduces your CLAUDE.md files with a
  line telling Claude that the instructions override default behavior" (412). The docs recommend any custom system prompt
  include: *"The application adds system reminders to this conversation. Treat them as context from the application, not
  as messages from the user."* (416-418). The git commit/PR workflow instructions live **in the Bash tool description**
  (434). VERIFIED.
* **Tool descriptions observed in this research agent's own Claude Code harness** (VERIFIED by observation, 2026-09-29):
  Bash — avoid `cat/head/tail/sed/awk/echo` and "use the appropriate dedicated tool"; prefer absolute paths;
  `run_in_background`; foreground `sleep` blocked. Read — "Reads up to 2000 lines by default", `cat -n` format; do not
  re-read a file just edited ("Edit/Write would have errored if the change failed"). Edit — "You must Read the file in
  this conversation before editing"; `old_string` must match exactly incl. indentation and be unique; strip the line-number
  prefix before matching. Write — use Edit for partial changes. The system prompt instructs to batch independent tool calls
  in one turn ("make all of the independent calls in the same function_calls block").

### 2.4 Codex — model-visible tools (source-level)

Tool plan assembly: `CX/codex-rs/core/src/tools/spec_plan.rs` `add_core_tool_sources()` (≈1015-1035) calls
`add_shell_tools`, `add_mcp_resource_tools`, `add_core_utility_tools`, `add_collaboration_tools`. VERIFIED details:

| Tool | Condition | Parameters (required in **bold**) | Source |
|---|---|---|---|
| `exec_command` | `Feature::ShellTool` (stable, on) and model `shell_type != Disabled` | **`cmd`**, `workdir`, `tty`, `yield_time_ms` (default 10000, 250–30000), `max_output_tokens` (default 10000), `shell`, `login`, `environment_id`, `sandbox_permissions` (`use_default` \| `with_additional_permissions` \| `require_escalated`), `justification`, `prefix_rule`, `additional_permissions` | `shell_spec.rs:24-115` |
| `write_stdin` | `Feature::UnifiedExec` (stable, on) | **`session_id`**, `chars`, `yield_time_ms`, `max_output_tokens` | `shell_spec.rs:117-159` |
| `apply_patch` | model catalog `apply_patch_tool_type` is set; only value is `Freeform` | freeform text constrained by Lark grammar | `apply_patch_spec.rs:9-28`; `protocol/src/openai_models.rs:320-324` |
| `update_plan` | only when `[tools.update_plan] enabled = true` | `explanation`, **`plan`**: [{**`step`**, **`status`** ∈ pending/in_progress/completed}] | `plan_spec.rs:7-58`; `config/mod.rs:2717-2723` |
| `view_image` | `Feature::ViewImage` (stable, on) | **`path`**, `detail` ∈ high/original, `environment_id` | `view_image_spec.rs:16-51` |
| `request_user_input` | `experimental_request_user_input` default on, but available modes = Plan only by default (the under-development, off-by-default feature `default_mode_request_user_input` adds Default mode; `tools/src/tool_config.rs:17-26`) | **`questions`**: 1–3 × {**`id`**, **`header`** (≤12 chars), **`question`**, **`options`**: 2–3 × {**`label`** (1–5 words), **`description`**}}; recommended option first with "(Recommended)"; client adds "Other" | `request_user_input_spec.rs:16-128` |
| `web_search` | hosted Responses API tool; modes cached/indexed/live/disabled | (server tool) | `tools/hosted_spec.rs:14-40` |
| `spawn_agent` (v1, namespace `multi_agent_v1`) | multi-agent enabled | `message` or `items`, `agent_type`, `fork_context`, `model`, `reasoning_effort` | `multi_agents_spec.rs:65-99, 591-628` |
| `send_input` / `resume_agent` / `wait_agent` / `close_agent` | same | `target`, `message`/`items`, `interrupt` / `id` / **`targets`**, `timeout_ms` / `target` | `multi_agents_spec.rs:147-340, 849-876` |
| v2: `spawn_agent`, `send_message`, `followup_task`, `wait_agent`, `interrupt_agent`, `list_agents` | `multi_agent_v2` (stable, off) | `task_name`, `fork_turns` ("none"/"all"/N) … | `multi_agents_spec.rs:100-146, 185-316, 630-672` |
| `list_mcp_resources`, `list_mcp_resource_templates`, `read_mcp_resource` | any MCP server configured | | `spec_plan.rs` `add_mcp_resource_tools` |
| `get_context_remaining`, `new_context_window` | `Feature::TokenBudget` (under development) | none | `get_context_remaining_spec.rs`, `new_context_window_spec.rs` |
| `request_permissions` | `Feature::RequestPermissionsTool` (under development) | `reason`, **`permissions`** {network, file_system{read,write}} | `shell_spec.rs:161-196` |

`codex features list` (executed) confirms: `shell_tool`, `unified_exec`, `view_image`, `multi_agent`, `hooks`,
`goals`, `skill_search`, `sleep_tool` stable/on; `multi_agent_v2`, `memories` stable/off; `apply_patch_freeform`
**removed** (freeform is now the only form); `js_repl`, `search_tool`, `undo` removed. VERIFIED.

Windows: when the executor is Windows, `exec_command`'s description appends "Windows safety rules" (do not compose
destructive commands across shells; prefer `Remove-Item -LiteralPath`; verify resolved paths before recursive delete;
`Start-Process -WindowStyle Hidden`) (`shell_spec.rs:339-345`). VERIFIED.

### 2.5 Codex — system prompt content about tools

`CX/codex-rs/protocol/src/prompts/base_instructions/default.md` (275 lines) sections: identity; Personality;
**AGENTS.md spec** (17-27: scope = directory tree; deeper files win; direct instructions beat AGENTS.md; root→cwd files
are already included); Preamble messages; **Planning/update_plan** rules; Task execution (123-147: keep going until
resolved; use `apply_patch` (never `applypatch`); root-cause fixes; do not re-read files after `apply_patch`; no
commits unless asked; no inline comments/one-letter names unless asked); Validating work (test specific→broad; behaviour
depends on approval mode); Final answer formatting; **Tool Guidelines** (258-275: prefer `rg`/`rg --files`; "Do not use
python scripts to attempt to output larger chunks of a file"; update_plan: 1-sentence steps, exactly one
`in_progress`). Model-specific prompts (`core/gpt-5.2-codex_prompt.md`, 80 lines) add: default to ASCII; use apply_patch
for single-file edits but not for generated changes; never revert others' changes in a dirty worktree; skip the plan
tool for the easiest 25% of tasks. `gpt_5_2_prompt.md:252`: "Parallelize tool calls whenever possible … Use
`multi_tool_use.parallel`". When `update_plan` is disabled, Codex strips the planning sections from its own prompt text
(`prompts/src/update_plan_instructions.rs`). VERIFIED.

### 2.6 The `apply_patch` (V4A) format — precise specification and ecosystem

**Grammar** (VERIFIED, `CX/codex-rs/core/assets/tools/apply_patch.lark`, verbatim in §3.4). Semantics from the Rust
implementation (VERIFIED, `CX/codex-rs/apply-patch/src/{parser.rs,streaming_parser.rs,seek_sequence.rs,file_update.rs,text_file.rs,lib.rs}`):

1. Envelope `*** Begin Patch` … `*** End Patch`; first/last lines compared after trimming whitespace; lenient mode strips a
   heredoc wrapper `<<EOF`/`<<'EOF'`/`<<"EOF"` … `EOF` (added for GPT-4.1, `parser.rs:145-195`). Optional
   `*** Environment ID: <id>` right after Begin (multi-environment sessions only).
2. Hunks: `*** Add File: <path>` followed by `+`-prefixed lines (content = lines joined with `\n`, trailing newline
   added); `*** Delete File: <path>`; `*** Update File: <path>` optionally followed by `*** Move to: <new path>` and one or
   more chunks. Paths are relative to the working directory (absolute allowed).
3. Chunk lines: `@@` or `@@ <context line>` starts a chunk (the text after `@@ ` is a single line searched for **after** the
   previous chunk, e.g. a function signature); ` ` context, `-` delete, `+` insert; an empty line counts as an empty
   context line; `*** End of File` marks a chunk that must match at EOF. The first chunk may omit `@@`.
4. Errors (exact strings): "The first line of the patch must be '*** Begin Patch'", "The last line of the patch must be
   '*** End Patch'", "'<line>' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File:
   {path}', '*** Update File: {path}'", "Update file hunk for path '<p>' is empty", "Update hunk does not contain any lines",
   "Failed to find context '<ctx>' in <path>", "No files were modified." Parse errors are reported as
   `Invalid patch hunk on line N: …`.
5. Matching (`seek_sequence.rs`): for each chunk the old lines (context+deleted) are searched from the cursor with four
   passes: exact, trailing-whitespace-insensitive, fully trimmed, and trimmed with Unicode dashes/quotes/odd spaces mapped
   to ASCII. EOF chunks are anchored: every pass starts at `len(lines) − len(pattern)` (in preserve mode
   `max(that, cursor)`), so only the end-of-file position is tried — there is no fallback to earlier positions
   (`seek_sequence.rs:30-38`, verifier-corrected wording). If the pattern ends with an empty line and fails, retry without it.
   Pure-insertion chunks (no old lines) append at the end of the file.
6. Line endings: in "preserve" mode (used by the conformance fixtures; runtime flag `apply_patch_preserve_line_endings`
   is under development) unchanged and context lines keep their original terminators, inserted lines use the file's first
   terminator, and every line ends with a terminator (`text_file.rs`).
7. Application is **sequential and not atomic** (fixture `015_failure_after_partial_success_leaves_changes` expects the
   Add to persist when a later Update fails); Add File and Move overwrite existing files (fixtures 010, 011); deleting a
   directory fails (012). Output: `Success. Updated the following files:\nA <p>\nM <p>\nD <p>\n` (every line written with
`writeln!`, so the text ends in a newline; the R port in §5.1 omits the final newline) (`lib.rs:862-877`).

**Model-facing description** of the freeform tool: "The `apply_patch` tool can be used to edit files. This is a FREEFORM
tool, so do not wrap the patch in JSON." (`apply_patch_spec.rs:20`). The base prompt still shows the legacy exec-style
invocation `{"command":["apply_patch","*** Begin Patch\n…"]}` (`default.md:132`). VERIFIED.

**OpenAI Responses API native tool** (VERIFIED, `developers.openai.com/api/docs/guides/tools-apply-patch.md`):
`tools=[{"type":"apply_patch"}]` (supported models listed: GPT-5.5, 5.4, 5.2, 5.1). Output items
`{"type":"apply_patch_call","call_id":…,"status":…,"operation":{"type":"create_file"|"update_file"|"delete_file","path":…,"diff":…}}`
where `diff` is a per-file V4A diff (create: all `+` lines; `delete_file` carries no `diff`). The harness replies with
`{"type":"apply_patch_call_output","call_id":…,"status":"completed"|"failed","output":…}`. Reference implementations:
Agents SDK `apply_diff.py` / `applyDiff.ts` (matching with fuzz levels exact/rstrip/strip; multiple stacked `@@` anchors
allowed). The companion `{"type":"shell","environment":{"type":"local"}}` tool emits
`shell_call {action:{commands:[…], timeout_ms, max_output_length}}` and expects `shell_call_output` with
`[{stdout, stderr, outcome:{type:"exit",exit_code}|{type:"timeout"}}]` (`tools-shell.md` ≈1517-1560, local-mode section).

**Who else uses the format** (VERIFIED): opencode registers `apply_patch` (arg `patchText`) and gives it to GPT models
instead of `edit`/`write` (`registry.ts:297-300`); Aider has a `PatchCoder` (`edit_format = "patch"`,
`aider/coders/patch_coder.py:210-217`) but **no model in `model-settings.yml` defaults to it** (`edit_format`: 289
`diff`, 35 `diff-fenced`, 4 `udiff`, 4 `whole`, 1 `architect`; plus 138 `editor_edit_format: editor-diff` — executed
count, re-verified); btw implements the envelope in R
(`BTW/R/tool-files-patch.R`) but, unlike Codex, rejects pure-insert hunks and is atomic. Pi does **not** support it (no
match for `apply_patch`/`Begin Patch` in `pi/packages/*/src`).

**Answer to "should gptr's edit tool accept it as an alternative input format?"**: Yes, but in three layers (§4.3):
(a) one shared R patch engine; (b) for OpenAI GPT-5.x on the Responses API register the Codex-identical freeform
`apply_patch` tool (name, description, grammar verbatim) and **omit** `edit`/`write`, as opencode and Codex do (the model
family is trained on this surface; note opencode's gate is a plain model-ID substring test — contains `gpt-`, not `oss`,
not `gpt-4` — applied on every provider, and its tool is a JSON function with a `patchText` string, not a freeform tool); for OpenAI-compatible Chat Completions endpoints use a JSON function
`apply_patch(patch: string)`; optionally support the native `{"type":"apply_patch"}` tool through the adapter;
(c) `edit` stays Pi/Claude-shaped for every other model but accepts a patch envelope if a model sends one anyway.

### 2.7 Other harnesses (brief)

* **Gemini CLI** (VERIFIED, `docs/tools/*.md`): `list_directory {dir_path, ignore, file_filtering_options}`,
  `read_file {file_path, offset, limit}`, `write_file {file_path, content}`, `glob {pattern, path, case_sensitive,
  respect_git_ignore}`, `grep_search {pattern, path, include}`, `replace {file_path, instruction, old_string, new_string,
  allow_multiple}` (note the extra semantic `instruction`), `run_shell_command {command, description, dir_path,
  is_background}` (`powershell.exe -NoProfile -Command` on Windows, `bash -c` elsewhere), `write_todos {todos:[{description,
  status ∈ pending/in_progress/completed/cancelled/blocked}]}`, `ask_user {questions: 1–4 × {question, header (≤16 chars),
  type ∈ choice/text/yesno, options 2–4, multiSelect, placeholder}}`, `enter_plan_mode {reason}`, `exit_plan_mode
  {plan_path}`; memory = the agent edits `GEMINI.md` files with `write_file`/`replace`. `GEMINI.md` hierarchy: global
  `~/.gemini/GEMINI.md`, workspace dirs and parents, and just-in-time files discovered when a tool touches a directory;
  `@file.md` imports; `context.fileName` can be `["AGENTS.md", …]`.
* **opencode** (VERIFIED, docs): `bash`, `edit`, `write`, `read`, `grep`, `glob` (sorted by mtime), `lsp`
  (experimental), `apply_patch`, `skill`, `todowrite` (disabled for sub-agents by default), `webfetch`, `websearch`
  (Exa/Parallel, provider-gated), `question`; permissions `allow|ask|deny` per tool with wildcards; one `edit` permission
  covers `edit`, `write`, `apply_patch`.
* **Aider** (VERIFIED): no tool calling for edits — edit *formats* in the reply text: `whole`, `diff` (SEARCH/REPLACE
  blocks), `diff-fenced` (Gemini), `udiff` (GPT-4 Turbo), `editor-diff`/`editor-whole` (architect mode: planner model +
  editor model), `patch` (V4A).
* **Goose** (VERIFIED, docs): Developer extension tools `shell`, `write`, `edit` (exact replace), `tree` (with line
  counts), `read_image`; modes Autonomous (default!) / Manual / Smart approval / Chat only.

### 2.8 Sub-agents, background work and orchestration

**Claude Code** (VERIFIED, `CC/sub-agents`):
* Built-ins: `Explore` (read-only, skips CLAUDE.md and git status, thoroughness quick/medium/very thorough), `Plan`
  (read-only research in plan mode), `general-purpose` (all tools), plus `claude`, `statusline-setup`,
  `claude-code-guide` (29-81).
* Definition files: `.claude/agents/*.md` (project), `~/.claude/agents/` (user), plugin `agents/`, `--agents '<json>'`
  (CLI help, executed); hot-reloaded. The body is the **entire system prompt** of the sub-agent (it does *not* get the
  Claude Code system prompt), plus environment details (245-271). Frontmatter table in §3.6.
* Tool resolution: `tools` allowlist, `disallowedTools` denylist (deny wins); always removed from sub-agents: `Agent` at
  the depth limit, `AskUserQuestion`, `EndConversation`, `EnterPlanMode`, `ExitPlanMode` (unless `permissionMode: plan`),
  `ScheduleWakeup`, `WaitForMcpServers`, `Workflow`; background sub-agents keep only a fixed built-in subset (`Read`,
  `Grep`, `Glob`, `LSP`, `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`,
  `Skill`, `ToolSearch`, worktree tools, `Monitor`, `TaskStop`, `SendMessage`, `Artifact`) (422-441).
* Model resolution: per-invocation `model` > frontmatter `model` (`inherit` allowed) > `CLAUDE_CODE_SUBAGENT_MODEL` >
  main model (350-376).
* Foreground vs background: fork mode is on by default interactively, so sub-agents run **in the background by
  default**; background permission prompts surface in the main session naming the sub-agent; "A background subagent's
  results reach Claude as a completion notification in a later turn. Claude waits for that notification before reporting"
  (886-908).
* Nesting depth default 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), 20 concurrent (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`),
  no total cap (1011-1051). Resume with `SendMessage {to: agentId|name}` (1080-1116). Transcripts at
  `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`. Sub-agents auto-compact independently.
* **Output scanning**: before Claude reads a sub-agent report, imitation `<system-reminder>`/`Human:` markers are
  backslash-escaped and a `[harness: subagent output matched instruction-shaped pattern(s):` marker is prepended; the report
  arrives "under a header marking it as subagent output… carry no authority from you" (941-956).
* **Forks**: a sub-agent that inherits the full conversation, system prompt, tools and prompt cache (1143-1208).
* **Agent tool I/O** (`SDK` 2842-2864, 3566-3638): input `{description, prompt, subagent_type?, model?,
  run_in_background?, name?, isolation?}`; output `completed` {agentId, content[text], usage, totalToolUseCount,
  totalDurationMs, toolStats…} | `async_launched` {agentId, description, prompt, outputFile} | `remote_launched`.
* **Dynamic workflows** (`CC/workflows` 292-368): Claude writes a JavaScript script (`export const meta = {name,
  description}`; `agent(prompt, {schema, label})`, `parallel()`, `pipeline(items, fn)`, `phase()`, `log()`, global
  `args`); the runtime executes it in the background; `Date.now()`/`Math.random()` throw so resumed runs replay cached
  `agent()` results; ≤16 concurrent agents (≤256 configurable), ≤4,096 items per `parallel`/`pipeline`, ≤1,000 agents per run;
  `agent()` with `schema` returns validated JSON (fails after five attempts; `MAX_STRUCTURED_OUTPUT_RETRIES`). **This is exactly REQ-35's "the R script is the graph" —
  gptr gets it for free by making `gptr()` itself the `agent()` primitive.**
* `/goal <condition>` (`CC/goal`): after each turn a small fast model checks the condition; continues until met/impossible.
  In gptr this is `while (!gptr("condition met?", state, model = jev)) gptr("continue")` — a System One use case.

**Codex** (VERIFIED): built-in agent types `default`, `worker`, `explorer`; custom agents are TOML config layers
(`CXD/agent-configuration/subagents` 332-399); `[agents]` settings `enabled`, `max_concurrent_threads_per_session`
(legacy `max_threads`), `default_subagent_model`, `default_subagent_reasoning_effort`, `interrupt_message`. Code constants:
`DEFAULT_AGENT_MAX_THREADS = 6`, `DEFAULT_MULTI_AGENT_V2_MAX_CONCURRENT_THREADS_PER_SESSION = 4`, `DEFAULT_AGENT_MAX_DEPTH = 1`,
wait timeout default 30,000 ms, min 10,000, max 3,600,000 (`config/mod.rs:256-266`, `multi_agents_common.rs:22-24`).
Sub-agents inherit the parent's sandbox/approval overrides; approvals from inactive threads surface with the source
thread label. The spawn description (v1) is a delegation playbook (§3.5).

**btw (R)**: `btw_tool_agent_subagent(prompt, tools, session_id)` — the caller must pick the sub-agent's tools from a
listed catalogue; returns plain text and a `session_id` to resume (`BTW/R/tool-agent-subagent.R:682-727`).
**Posit Assistant**: `launchSubagent` with tier requests `low|medium|high|default` mapped through `modelTiers`
(config reference). VERIFIED.

### 2.9 Project instruction files

| Harness | File(s) | Hierarchy / merge | Imports | Limits | Delivery |
|---|---|---|---|---|---|
| Claude Code | managed `CLAUDE.md`; `~/.claude/CLAUDE.md`; `./CLAUDE.md` or `./.claude/CLAUDE.md`; `CLAUDE.local.md`; `.claude/rules/*.md` (optional `paths:` globs) | all files from filesystem root down to cwd concatenated (closest last); subdirectory files lazily when Claude reads there; `CLAUDE.local.md` after `CLAUDE.md` per dir | `@path` (relative to the importing file, `~` ok, `\ ` for spaces, not inside code spans/fences, ≤4 hops; external imports need approval) | file >4 MiB skipped; <200 lines advised; `MEMORY.md` 200 lines/25 KB | user message wrapped as system reminder; block HTML comments stripped |
| Claude Code AGENTS.md | `AGENTS.md`, `.claude/AGENTS.md` | read **only if no** `CLAUDE.md`/`.claude/CLAUDE.md`/`CLAUDE.local.md` on the path (setting `claude-md-or-agents-md`, default; alternatives `claude-md-and-agents-md`, `claude-md`, `managed-only`); not read: `AGENTS.local.md`, `AGENTS.override.md`, `.agents/` | same | | v2.1.277+ |
| Codex | `~/.codex/AGENTS.override.md` or `AGENTS.md`; per dir root→cwd: `AGENTS.override.md` > `AGENTS.md` > `project_doc_fallback_filenames` | project root by `project_root_markers` (default `.git`); at most one file per directory; concatenated root→cwd | none | `project_doc_max_bytes` 32 KiB (silently truncated) | user fragment `# AGENTS.md instructions for <dir>\n\n<INSTRUCTIONS>\n…\n</INSTRUCTIONS>`; untrusted projects skip project docs |
| Gemini CLI | `~/.gemini/GEMINI.md`, workspace + parents, JIT per directory | concatenated | `@file.md` | | |
| btw | nearest `btw.md` > `AGENTS.md` > `CLAUDE.md` (project root markers `DESCRIPTION`, `.git`, `.vscode`, `.here`, `*.Rproj`); user `~/btw.md`, `~/.btw/`, `~/.config/btw/`, `tools::R_user_dir("btw")` | single nearest file | | | also `llms.txt` |
| Posit Assistant | `~/.posit/assistant/AGENTS.md` + project-root `AGENTS.md` ("memory") | project wins on conflict | `@file.md`, may not escape the memory file's directory | | project memory only in trusted workspaces; `/savememory` writes it |
| agents.md standard | `AGENTS.md`, nested per package | "closest AGENTS.md to the edited file wins; explicit user chat prompts override everything" | none specified | plain Markdown, no required fields | |

Sources (VERIFIED): `CC/memory` 53-148, 345-456; `CXD/agent-configuration/agents-md` 7-16;
`CX/codex-rs/core/src/agents_md.rs:1-52`, `config/mod.rs:255`, `context/user_instructions.rs:23-34`;
`google-gemini/gemini-cli docs/cli/gemini-md.md`; `BTW/R/btw-config.R:1-66`; `assistant.posit.co/docs/features/memory/`;
`https://agents.md/` (fetched, text-stripped).

### 2.10 Hooks

**Claude Code** (VERIFIED, `CC/hooks`): events and cadences at lines 19-69; locations: user/project/local settings,
managed policy, plugin `hooks/hooks.json`, skill and sub-agent frontmatter (249-261); matcher = exact names separated by
`|`/`,` or a JS regex (285-300); handler types `command` (stdin JSON), `http` (POST body), `mcp_tool`, `prompt` (single-turn
model judgement, `$ARGUMENTS` placeholder, default timeout 30 s), `agent` (sub-agent with Read/Grep/Glob, 60 s) (404-450,
590-597); common input fields `session_id`, `prompt_id`, `transcript_path`, `cwd`, `scratchpad_dir`,
`permission_mode`, `effort`, `hook_event_name`, plus `agent_id`/`agent_type` inside sub-agents (730-751). Exit code 0 =
success (stdout becomes context only for `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `PostModelSwitch`),
**exit 2 = block** (stderr is the reason), other codes = non-blocking error (782-847). JSON output: universal `continue`,
`stopReason`, `systemMessage`, `terminalSequence`; `decision:"block"` + `reason`; `hookSpecificOutput` with
`permissionDecision` (`allow|deny|ask|defer`), `permissionDecisionReason`, `updatedInput`, `additionalContext`,
`updatedToolOutput` (PostToolUse); `additionalContext`/`systemMessage`/plain stdout capped at 10,000 chars each — larger
values are saved to a file and replaced by its path plus a 2,000-char preview (913-1051, 1790-1800). All matching hooks run in
parallel.

**Codex** (VERIFIED, `CXD/hooks`): events `SessionStart` (matcher startup|resume|clear|compact), `SessionEnd`,
`SubagentStart`, `SubagentStop`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact` (matcher
manual|auto), `UserPromptSubmit`, `Stop`, `Interrupt`; sources `~/.codex/hooks.json`, `config.toml [hooks]`,
`<repo>/.codex/…`, plugins; **non-managed hooks must be reviewed and trusted by hash** (`/hooks`); shell and
`exec_command` calls match as `Bash`, `apply_patch` matches `apply_patch|Edit|Write`, `spawn_agent` matches `Agent`;
`updatedInput` for Bash/apply_patch must contain `command`; `permissionDecision:"ask"` not yet supported; hook output
visible to the model capped at ~2,500 tokens. Legacy `notify = ["python3","notify.py"]` receives one JSON argv with
`type:"agent-turn-complete"`, `thread-id`, `turn-id`, `cwd`, `input-messages`, `last-assistant-message`
(`CXD/config-file/config-advanced` 680-720).

### 2.11 Context management, memory, todos, plan mode, steering

* **Claude compaction** (VERIFIED, `CC/context-window` 1592-1633, `CC/how-claude-code-works` 136-142,
  `CC/model-config` "Default auto-compact thresholds"): "clears older tool outputs first, then summarizes"; auto at the
  model's limit (≈967K for native-1M models, 200K boundary for 200K windows); `/compact [focus]`, "Compact Instructions"
  section in CLAUDE.md, `/autocompact <tokens>`; after compaction re-injects root CLAUDE.md + unscoped rules, auto memory,
  fresh git status, the plan file, up to 5 most-recently modified files (files >5,000 tokens become path references),
  invoked skill bodies (≤5,000 tokens each, ≤25,000 total); background tasks keep running and are re-listed; thrash
  detection stops auto-compaction after a few attempts.
* **Codex compaction** (VERIFIED): prompt `prompts/templates/compact/prompt.md` (verbatim §3.9); the summary is inserted
  as a user message prefixed by `summary_prefix.md`; `model_auto_compact_token_limit` default = 90% of the window;
  `compact_prompt` / `experimental_compact_prompt_file` overrides; `tool_output_token_limit` caps stored tool output.
* **Posit Assistant** (VERIFIED): auto-compaction when fewer than `features.autoCompactTokenBuffer` (30,000) tokens remain;
  compacted messages hidden, not deleted; `/microcompact` replaces most tool results in the active path with placeholders
  (tool calls stay), manual only.
* **Memory**: Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md` (index, first 200 lines/25 KB loaded)
  + topic files with `type ∈ user|feedback|project|reference` (`CC/memory` 468-541); Codex local memories
  (`~/.codex/memories/`, generated in the background from idle chats, secrets redacted; `memories` feature off by default);
  Gemini: the agent edits GEMINI.md; Posit Assistant: `/savememory [user]` edits AGENTS.md.
* **Todos**: see executive summary item 2. Gemini keeps `write_todos`; opencode `todowrite`.
* **Plan mode**: Claude `EnterPlanMode {}` / `ExitPlanMode` (plan written to `plansDirectory`, default `~/.claude/plans`;
  approval options: auto mode / accept edits / manual / keep planning) (`CC/permission-modes` 240-272, `CC/hooks`
  1778-1788). Codex Plan mode template (`collaboration-mode-templates/templates/plan.md`, 128 lines): explore
  non-mutating first, then intent chat, then implementation chat; ask via `request_user_input` with 2–4 options and a
  recommended default; final plan in exactly one `<proposed_plan>` block; "decision complete"; `update_plan` errors in Plan
  mode. Posit Assistant: `/plan` writes `.posit/assistant/plans/YYYY-MM-DD-HHMM-<subject>.md` (only if that project
  directory exists, else `~/.posit/assistant/plans/`); its Plan mode is advisory — the assistant "can still edit files,
  run code" but is instructed not to; `/ask` is a hard read-only
  mode with **no R/Python execution**, only the user can enter/exit it.
* **Checkpointing** (`CC/checkpointing`): file snapshots before every user turn (100 most recent), `/rewind` restores
  code and/or conversation or summarises from/up to a point; changes made through Bash are not tracked.
* **Steering** (`CC/interactive-mode` 356-392): messages typed while the agent works are queued and delivered **after
  the current tool calls finish, within the same turn**; `Esc` interrupts; `!cmd` shell mode adds output to the session;
  `/btw` side questions answer from context with no tools and never enter history (595-630).

### 2.12 Notebook support

* Claude: `Read` of `.ipynb` returns all cells with outputs; `NotebookEdit` schema in §3.1; permission rules use
  `Edit(...)` paths. VERIFIED.
* Codex: no notebook tool (would have to patch JSON). VERIFIED by absence in `spec_plan.rs` tool registration.
* Positron Assistant (VERIFIED, package.json at `latest-daily-2026.06`): `editNotebook {operation ∈ add|update|delete|
  reorder|clearOutputs, cellType, index (-1 = append), content, cellIndex, cellIndices, run (default true for code),
  fromIndex, toIndex, newOrder}`, `executeNotebook {operation, cellIndices, runAll}`, `getNotebookInfo {operation,
  cellIndices}`, `createNotebook {language}`; cells addressed by 0-based index, not id.
* gptr: `.ipynb` is also a *history format* (REQ-24). A Claude-compatible `notebook_edit` is easy in R (§5.4); nbformat
  4.5 cell `id`s are available for addressing.

### 2.13 Existing R-specific agent tooling

**btw 1.5.0** — tool table extracted by statically parsing every `ellmer::tool(...)` call in `BTW/R/tool-*.R`
(`PROTO/btw_tool_table.R`, executed; §5.6). The clone is the dev version 1.5.0.9000; the verifier re-ran the same
extraction on the CRAN `btw_1.5.0.tar.gz` source: also 38 tools, identical names/arguments except `pkg_test` (no
`reporter` in 1.5.0); `tool-run.R`, `tool-files-patch.R`, `btw-config.R` are byte-identical between the two.

| group | tools (arguments) |
|---|---|
| agent | `btw_tool_agent_subagent(prompt, tools, session_id)` |
| cran | `cran_search(query, format, n_results)`, `cran_versions(package_name, after, before)`, `cran_package(package_name)` |
| docs | `docs_package_news(package_name, search_term, version)`, `docs_package_help_topics(package_name)`, `docs_help_page(package_name, topic)`, `docs_available_vignettes(package_name)`, `docs_vignette(package_name, vignette)` |
| env | `env_describe_data_frame(data_frame, package, format, max_rows, max_cols)`, `env_describe_environment(items)` |
| files | `files_edit(path, edits)` (hashline refs `N:hash`), `files_list(path, type, regexp)`, `files_patch(patch)` (apply_patch envelope), `files_read(path, line_start, line_end)` (lines prefixed `N:hash|`), `files_replace(path, old_string, new_string, replace_all)`, `files_search(term, limit, case_sensitive, use_regex, show_lines)`, `files_write(path, content)` |
| git | `git_status`, `git_diff`, `git_log`, `git_commit`, `git_branch_list/create/checkout` |
| github | `github(code, fields)` (R code calling `gh()`) |
| ide | `ide_read_current_editor(selection, consent)` |
| pkg | `pkg_check(pkg)`, `pkg_coverage(pkg, filename)`, `pkg_document(pkg)`, `pkg_test(pkg, filter)` (CRAN 1.5.0; the dev source 1.5.0.9000 adds `reporter`), `pkg_load_all(pkg)` |
| run | `run_r(code)` — **opt-in**: requires `evaluate` installed and either `options(btw.run_r.enabled=TRUE)`, `BTW_RUN_R_ENABLED=true`/`1`, or the caller naming tools explicitly (`btw_tools("run")`, which sets `.btw_tools.match_mode = "explicit"`); `btw_tools()` with no arguments leaves it out (`tool-run.R:318-338`, `tools.R:59-64`) |
| sessioninfo | `sessioninfo_is_package_installed(package_name)`, `sessioninfo_platform()`, `sessioninfo_package(packages, dependencies)` |
| skills | `skill(name)` |
| web | `web_read_url(url)` |

`btw_tool_run_r` (VERIFIED, `tool-run.R:121-317`): evaluates with `evaluate::evaluate(code, envir = global_env(),
stop_on_error = 1, new_device = TRUE, output_handler = …)`; restores wd/options/envvars with `withr::local_*` after each
call; captures source, text, messages, warnings, errors and plots (replayed into a PNG via `ragg` if installed, 768 px
long side, 3:2); merges adjacent outputs; strips ANSI. Its description encodes useful R rules: incremental ≤50-line
calls, one figure per call, never "talk to the user" through code, at most 2 attempts to fix an error, no file writes /
shell / network / installs unless requested, return values implicitly, prefer `head()`/`str()`/`summary()`.

**Positron Assistant** (blog status line: "Succeeded by Posit Assistant (as of June 2026)"; no formal deprecation notice
was checked) — 13 tools at tag `latest-daily-2026.06`
(VERIFIED): `documentEdit(deltas)`, `documentCreate(filePath, workspaceFolder, content, errorIfExists)`,
`selectionEdit(code)`, `executeCode(sessionIdentifier, code, language, summary)` ("You prefer to show code over running
it unless given an imperative"), `inspectVariables(sessionIdentifier, variableNames)` (children of variables; empty =
root), `getPlot()`, `getTableSummary(sessionIdentifier, variableNames)`, `getProjectTree(include, exclude,
skipDefaultExcludes, maxItems, directoriesOnly)`, `getChangedFiles()`, and the four notebook tools.

**Databot / Posit Assistant lessons** (VERIFIED, Joe Cheng, "A brief and biased history of Posit data science agents",
opensource.posit.co, 2026-06-11): Databot = frontier model + unfettered live R/Python session; three decisions made it
work for EDA: see results including tables and plots; **cap tool calls before stopping to summarise and check in**;
**always offer 3–5 next-step suggestions**. Its weakness was narrow scope; Posit Assistant generalises it ("a simple agent
harness with a small number of powerful and general tools … full access to live R/Python sessions"). Posit Assistant
docs: session context auto-included = "language, version, and names and types of variables in your environment (not their
values)"; runtime settings `runtime.r.path = "Rscript"`, `runtime.r.timeout = 30000`; `.env` and `.Renviron` blocked from
reading by default; per-tool permissions `allow|ask|deny` with command patterns; sandbox via Seatbelt/bubblewrap, and on
Windows only an allowlist of read-only commands.

**mcptools 1.0.3** (VERIFIED, reference page): `mcp_server(tools = NULL, ..., type = c("stdio", "http"),
host = "127.0.0.1", port = as.integer(Sys.getenv("MCPTOOLS_PORT", "8080")), session_tools = TRUE)` serves
`ellmer::tool()` lists (or a path to an `.R` file yielding one) over MCP; `mcp_session()` makes an interactive R session reachable
(via nanonext sockets) with built-in `list_r_sessions`/`select_r_session` tools — the existing way Claude Code reaches a live
R session (relevant to D-14/D-15).

### 2.14 R-native introspection (what is cheap in R)

Measured on this machine (R 4.4.3, 613 installed packages; `PROTO/r_native_tools.R`, `help_search_timing`; VERIFIED):

| Operation | API (exported only) | Cost |
|---|---|---|
| help page → text | `utils::help(topic, package, help_type="text")` gives `<lib>/<pkg>/help/<Rd>`; `tools::Rd_db(pkg)[[<Rd>.Rd]]`; `tools::Rd2txt(rd, out="")` | 0.41–0.51 s (`median`), 0.48–0.60 s (`lm`, 10.6 KB text); `Rd_db("base")` 0.86–0.95 s; `Rd_db` of data.table/Matrix/ggplot2 0.09–0.37 s (re-run varied) |
| full-text help search | `utils::help.search(pattern, package=)` | 1.06–1.33 s first call over all packages, 0.28–0.50 s cached; 0.03 s restricted to 2 packages |
| exports with signatures | `getNamespaceExports()` + `formals()` | instant |
| name search / signature | `apropos("^read\\.")`, `args(f)` | instant |
| vignettes | `tools::getVignetteInfo(pkg)` → `Dir/doc/File` source (Rmd/asis) | instant |
| session | `utils::sessionInfo()`, `loadedNamespaces()`, `R.version.string`, `Sys.getlocale()` | instant |
| data.frame description | sampled NA rates + types + examples | 0.044 s for 2e6×3 |
| `object.size()` | | 0.027 s for 38 MB data.frame |

---

## 3. Exact specifications

### 3.1 Claude Code tool input schemas (verbatim from `SDK` 2842-3187)

```typescript
type AgentInput = {
  description: string;
  prompt: string;
  subagent_type?: string;
  model?: "sonnet" | "opus" | "haiku" | "fable";
  run_in_background?: boolean;
  name?: string;
  team_name?: string; // Deprecated; ignored
  mode?: "acceptEdits" | "auto" | "bypassPermissions" | "default" | "dontAsk" | "plan"; // Deprecated; ignored
  isolation?: "worktree" | "remote";
};
type AskUserQuestionInput = {
  questions: Array<{
    question: string;
    header: string;
    options: Array<{ label: string; description: string; preview?: string }>;
    multiSelect: boolean;
  }>;
  answers?: Record<string, string>;
  annotations?: Record<string, { preview?: string; notes?: string }>;
  metadata?: { source?: string };
};
type BashInput = {
  command: string;
  timeout?: number; // milliseconds, max 600000
  description?: string;
  run_in_background?: boolean;
  dangerouslyDisableSandbox?: boolean;
};
type FileEditInput = { file_path: string; old_string: string; new_string: string; replace_all?: boolean; };
type FileReadInput = { file_path: string; offset?: number; limit?: number; pages?: string; };
type FileWriteInput = { file_path: string; content: string; };
type GlobInput = { pattern: string; path?: string; };
type GrepInput = {
  pattern: string; path?: string; glob?: string; type?: string;
  output_mode?: "content" | "files_with_matches" | "count";
  "-i"?: boolean; "-o"?: boolean; "-n"?: boolean; "-B"?: number; "-A"?: number; "-C"?: number;
  context?: number; head_limit?: number; offset?: number; multiline?: boolean;
};
type NotebookEditInput = {
  notebook_path: string; cell_id?: string; new_source: string;
  cell_type?: "code" | "markdown"; edit_mode?: "replace" | "insert" | "delete";
};
type WebFetchInput = { url: string; prompt: string; };
type WebSearchInput = { query: string; allowed_domains?: string[]; blocked_domains?: string[]; };
type TodoWriteInput = { todos: Array<{ content: string; status: "pending" | "in_progress" | "completed"; activeForm: string; }>; };
type TaskCreateInput = { subject: string; description: string; activeForm?: string; metadata?: Record<string, unknown>; };
type TaskUpdateInput = { taskId: string; status?: "pending" | "in_progress" | "completed" | "deleted"; subject?: string;
  description?: string; activeForm?: string; addBlocks?: string[]; addBlockedBy?: string[]; owner?: string; metadata?: Record<string, unknown>; };
type ExitPlanModeInput = { allowedPrompts?: Array<{ tool: "Bash"; prompt: string; }>; /* deprecated */ [k: string]: unknown; };
type EnterPlanModeInput = {};
type MonitorInput = { description: string; timeout_ms: number; command?: string; ws?: { url: string; protocols?: string[]; }; };
type TaskStopInput = { task_id?: string; shell_id?: string; };
type WorkflowInput = { script?: string; name?: string; scriptPath?: string; args?: unknown; resumeFromRunId?: string; title?: string; description?: string; };
```
AskUserQuestion constraints (`CC/agent-sdk/user-input` 546-555): 1–4 questions; `header` ≤12 chars; 2–4 options each
with `label`+`description`; free-text "Other" row always available; a typed reply arrives as "The user responded: …"
(`SDK` 3671).

Agent output (`SDK` 3570-3635), abridged: `{status:"completed", agentId, agentType?, content:[{type:"text",text}],
resolvedModel?, modelsUsed?, totalToolUseCount, totalDurationMs, totalTokens, usage{…}, toolStats?{readCount, searchCount,
bashCount, editFileCount, linesAdded, linesRemoved, otherToolCount}, prompt, worktreePath?, worktreeBranch?}` |
`{status:"async_launched", agentId, description, resolvedModel?, prompt, outputFile, canReadOutputFile?}` |
`{status:"remote_launched", taskId, sessionUrl, description, prompt, outputFile}`.

Edit output (`SDK` 3742-3766): `{filePath, oldString, newString, originalFile, structuredPatch:[{oldStart, oldLines,
newStart, newLines, lines[]}], userModified, replaceAll, gitDiff?}`.

### 3.2 Claude Code limits and constants (VERIFIED)

| Item | Value | Source |
|---|---|---|
| Bash default / max timeout | 120,000 / 600,000 ms (`BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS`) | tools-reference 156-159 |
| Bash inline output | ~30,000 chars valid / ~10,000 failure; file + 2,000-char preview beyond; hard read-back ceiling 150,000 | 161-174 |
| Glob results | 100 files, mtime-sorted | 277 |
| WebSearch | ≤8 backend searches/call; 200/session | 577, 591 |
| WebFetch | 15-min cache; 5-min deadline | 554-555 |
| Monitor deadline | 5 min default, 30 min max | 335 |
| Sub-agent depth / concurrency | 3 / 20 | sub-agents 1013, 1044 |
| Sub-agent descriptions budget | warning over 15,000 tokens combined | sub-agents 819 |
| Workflow | 16 concurrent agents (1–256), 4,096 items per call, 1,000 agents per run, schema validation fails after 5 attempts | workflows 365-368, 321 |
| CLAUDE.md | load ≤4 MiB; imports ≤4 hops | memory 102, 533 |
| MEMORY.md | first 200 lines or 25 KB | memory 529 |
| Hook output | 10,000 chars per string; default timeouts 600 s (command/http/mcp_tool), 30 s (prompt), 60 s (agent) | hooks common-fields table (≈424-431), 923 |
| Compaction re-injection | ≤5 files (≤5,000 tokens each), skills ≤5,000 each / 25,000 total | context-window 1600-1614 |

### 3.3 Codex tool schemas (verbatim fragments)

`exec_command` (`CX/.../shell_spec.rs:35-114`): `required: ["cmd"]`, `additionalProperties: false`; description
"Runs a command in a PTY, returning output or a session ID for ongoing interaction."; output schema
`{chunk_id?, wall_time_seconds, exit_code?, session_id?, original_token_count?, output}` (198-230).
`write_stdin`: "Writes characters to an existing unified exec session and returns recent output."; `chars` default empty =
poll; non-empty writes default 250 ms, cap 30,000 ms; empty polls 5,000–300,000 ms.

`update_plan` (`plan_spec.rs:42-56`): description
```
Updates the task plan.
Provide an optional explanation and a list of plan items, each with a step and status.
At most one step can be in_progress at a time.
```
`view_image`: "View a local image file from the filesystem when visual inspection is needed. Use this for images already
available on disk."; returns `{image_url: <data URL>, detail?}`.

`request_user_input`: description "Request user input for one to three short questions and wait for the response. This
tool is only available in {modes}."; options description: "Provide 2-3 mutually exclusive choices. Put the recommended
option first and suffix its label with \"(Recommended)\". Do not include an \"Other\" option in this list; the client
will add a free-form \"Other\" option automatically."; questions "Prefer 1 and do not exceed 3".

`spawn_agent` v1 properties (`multi_agents_spec.rs:591-628`): `message` ("Initial plain-text task for the new agent. Use
either message or items."), `items` (typed input items: text/image_url/audio_url/path/name), `agent_type`,
`fork_context` ("True forks the current thread history into the new agent"), `model`, `reasoning_effort`.
`wait_agent` v1: `targets` (required; "Pass multiple ids to wait for whichever finishes first"), `timeout_ms` ("Prefer
longer waits (minutes) to avoid busy polling"). `close_agent`: "Completed agents remain open and count toward the
concurrency limit until closed."

### 3.4 apply_patch Lark grammar (verbatim, `CX/codex-rs/core/assets/tools/apply_patch.lark`)

```
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF
```
Tool spec sent to the Responses API (`apply_patch_spec.rs:18-27`):
```json
{"type": "custom", "name": "apply_patch",
 "description": "The `apply_patch` tool can be used to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON.",
 "format": {"type": "grammar", "syntax": "lark", "definition": "<the grammar above>"}}
```
(field names per `FreeformTool`/`FreeformToolFormat`; LIKELY serialised as the OpenAI "custom tool" shape documented at
`platform.openai.com/docs/guides/function-calling#custom-tools`, which the source comment links). In multi-environment
mode the start rule becomes `begin_patch environment_id? hunk+ end_patch` with `environment_id: "*** Environment ID: " filename LF`.

Example:
```
*** Begin Patch
*** Add File: R/utils.R
+`%||%` <- function(a, b) if (is.null(a)) b else a
*** Update File: R/model.R
@@ fit_model <- function(df) {
-  lm(y ~ x, data = df)
+  lm(y ~ x + z, data = df)
*** Delete File: R/old.R
*** End Patch
```

### 3.5 Codex spawn_agent delegation guidance (verbatim excerpt, `multi_agents_spec.rs:704-738`)

```
Do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask for sub-agents, delegation, or parallel agent work.
Requests for depth, thoroughness, research, investigation, or detailed codebase analysis do not count as permission to spawn.
...
### When to delegate vs. do the subtask yourself
- First, quickly analyze the overall user task and form a succinct high-level plan. Identify which tasks are immediate blockers on the critical path, and which tasks are sidecar tasks ...
- Do not delegate urgent blocking work when your immediate next step depends on that result. ...
### Designing delegated subtasks
- Subtasks must be concrete, well-defined, and self-contained. ...
- For code-edit subtasks, decompose work so each delegated task has a disjoint write set.
### After you delegate
- Call wait_agent very sparingly. ...
- While the subagent is running in the background, do meaningful non-overlapping work immediately.
### Parallel delegation patterns
- Run multiple independent information-seeking subtasks in parallel when you have distinct questions ...
```

### 3.6 Sub-agent definition formats

Claude Code frontmatter (VERIFIED, `CC/sub-agents` 300-319): `name` (required; no `:`), `description` (required),
`tools` (comma string or YAML list), `disallowedTools`, `model` (`sonnet|opus|haiku|fable|<full id>|inherit`),
`permissionMode` (`default|acceptEdits|auto|dontAsk|bypassPermissions|plan|manual`), `maxTurns`, `skills` (preloaded full
content), `mcpServers` (names or inline configs), `hooks`, `memory` (`user|project|local`), `background`, `omitClaudeMd`,
`effort` (`low|medium|high|xhigh|max`), `isolation` (`worktree`), `color`, `initialPrompt`, `experimental.cacheTtl`
(`5m|1h`). Unknown fields ignored silently; files with no `name` are treated as documentation.

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
---

You are a code reviewer. When invoked, analyze the code and provide
specific, actionable feedback on quality, security, and best practices.
```

Codex custom agent (VERIFIED, `CXD/agent-configuration/subagents` 387-439):
```toml
name = "pr_explorer"
description = "Read-only codebase explorer for gathering evidence before changes are proposed."
model = "gpt-6-luna"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
Stay in exploration mode.
Trace the real execution path, cite files and symbols, and avoid proposing fixes unless the parent agent asks for them.
"""
```

### 3.7 Hook I/O (Claude Code, verbatim example `CC/hooks` 760-778, 1070-1078)

Input on stdin:
```json
{"session_id":"abc123","prompt_id":"550e8400-e29b-41d4-a716-446655440000",
 "transcript_path":"/home/user/.claude/projects/.../transcript.jsonl","cwd":"/home/user/my-project",
 "scratchpad_dir":"/tmp/claude-1000/-home-user-my-project/abc123/scratchpad",
 "permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash",
 "tool_input":{"command":"npm test","description":"Run test suite","timeout":120000,"run_in_background":false},
 "tool_use_id":"toolu_01ABC123..."}
```
Deny:
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Database writes are not allowed"}}
```
Context injection: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"This file is generated. …"}}`;
stop: `{"continue": false, "stopReason": "Build failed, fix errors before continuing"}`; block a Stop: `{"decision":"block","reason":"…"}`.
Codex accepts the same `hookSpecificOutput` deny shape and the older `{"decision":"block","reason":…}`.

### 3.8 Project-instruction constants

Codex: `DEFAULT_AGENTS_MD_FILENAME = "AGENTS.md"`, `LOCAL_AGENTS_MD_FILENAME = "AGENTS.override.md"`, separator between
user and project docs `"\n\n--- project-doc ---\n\n"`, `AGENTS_MD_MAX_BYTES = 32 KiB` (`agents_md.rs:42-50`,
`config/mod.rs:255`). Fragment markers: `("# AGENTS.md instructions", "</INSTRUCTIONS>")`, body
`" for {dir}\n\n<INSTRUCTIONS>\n{text}\n"` (`user_instructions.rs:23-34`).

### 3.9 Compaction prompts (Codex, verbatim)

`prompts/templates/compact/prompt.md`:
```
You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.

Include:
- Current progress and key decisions made
- Important context, constraints, or user preferences
- What remains to be done (clear next steps)
- Any critical data, examples, or references needed to continue

Be concise, structured, and focused on helping the next LLM seamlessly continue the work.
```
`summary_prefix.md`: "Another language model started to solve this problem and produced a summary of its thinking
process. You also have access to the state of the tools that were used by that language model. Use this to build on the
work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use
the information in this summary to assist with your own analysis:"

### 3.10 OpenAI native apply_patch / shell wire items (verbatim shapes from the guides)

```json
{"type":"apply_patch_call","call_id":"call_Rjsqzz96C5xzPb0jUWJFRTNW","status":"completed",
 "operation":{"type":"update_file","path":"lib/fib.py","diff":"@@\n-def fib(n):\n+def fibonacci(n):\n ..."}}
{"type":"apply_patch_call_output","call_id":"call_cNWm41dB3RyQcLNOVTIPBWZU","status":"failed",
 "output":"Could not apply patch to lib/foo.py — file not found on disk"}
{"type":"shell_call","call_id":"call_9d14ac6f2b73485e91c0f4da6e1b27c8",
 "action":{"commands":["ls -l"],"timeout_ms":120000,"max_output_length":4096},"status":"in_progress"}
{"type":"shell_call_output","call_id":"call_3ef1b8c79a4d6520f9e3ab7d41c68f25","max_output_length":4096,
 "output":[{"stdout":"...","stderr":"...","outcome":{"type":"exit","exit_code":0}},
           {"stdout":"...","stderr":"...","outcome":{"type":"timeout"}}]}
```
(The guide's own example `diff` string is visibly garbled in the rendered page; do not copy it as a test vector.)

---

## 4. Recommended design for gptr

### 4.1 Final model-visible tool list for v1

Principle (REQ-10, D-03): Pi-minimal core; add a tool only when (a) models are trained on it, (b) it removes an
approval prompt or a risk class, or (c) it works in a mode where `run_r` is disabled.

| Tool | Default | Purpose (one line) | Parameters |
|---|---|---|---|
| `read` | on | Read a text file window; images → image block (replaces `view_image`); `.ipynb` → cells with ids | `path`, `offset?`, `limit?` (track 01 schema) |
| `write` | on | Create/overwrite a file | `path`, `content` |
| `edit` | on | Exact-match multi-replace with diff output; also accepts an `*** Begin Patch` envelope (auto-routed) | `path`, `edits:[{oldText,newText}]` (track 01 / Pi schema) |
| `apply_patch` | replaces `edit`+`write` for OpenAI GPT-5.x family | Codex-identical freeform patch (Responses API) or `apply_patch(patch)` JSON function (Chat Completions) | freeform text / `patch` |
| `grep`, `find`, `ls` | on | Pure-R search/list/sort (track 01) | per track 01 |
| `run_r` | on (approval per mode) | Evaluate R in the live session env; capture output/warnings/errors/plots | `code`, `timeout_s?`, `description?` (7-word summary shown to the user, cf. Positron `summary`, Claude `description`) |
| `r_inspect` | on, read-only, **never needs approval, available in plan mode** | Describe objects and look up R documentation without executing arbitrary code | `action ∈ {objects, describe, help, search, package, vignette, session}`, `name?` (object, topic, package or pattern), `package?`, `max_chars?` |
| `ask` | on in interactive sessions | Ask the user 1–4 multiple-choice questions (Claude/Codex/Gemini-compatible shape) | `questions:[{question, header(≤12), options:[{label, description}] (2–4), multi_select}]` |
| `agent` | on when agents are defined or `agents=` is used | Spawn a sub-agent (inline/worker/cli) with its own context/model/tools; background → handle + later notification | `description`, `prompt`, `agent_type?`, `model?`, `background?`, `returns?` (JSON schema) |
| `shell` | **off** | Run a shell command through `processx`/`system2` (never assume bash) | `command`, `timeout_s?`, `workdir?` |
| `notebook_edit` | auto-on when the harness document is `.ipynb` | Claude-identical cell edit | `notebook_path`, `cell_id?`, `new_source`, `cell_type?`, `edit_mode?` |
| `web_search` / `web_fetch` | off; prefer provider server-side tools (Anthropic `web_search`/`web_fetch`, OpenAI hosted `web_search`) | Look things up online | provider-defined |

**Why `r_inspect` is model-visible rather than left to `run_r`** (the one addition beyond Pi/track 01):
1. In `manual` mode every `run_r` call needs approval (north-star §11); looking up a help page or `str(pbmc)` through
   `run_r` would spam prompts. Claude Code auto-runs read-only tools without prompting (`CC/permission-modes` 17-24).
2. In `plan` mode (and a Posit-style read-only mode) R execution is disabled, but the agent still needs object structure and
   documentation — Posit Assistant's Ask mode keeps "Inspect your R/Python sessions" while blocking code execution
   (but Posit defines that as "reading console history and viewing plots", not object introspection, so this is only a
   partial precedent; the automatic variable-names-and-types context is what supplies structure there).
3. Precedent: Positron (`inspectVariables`, `getTableSummary`, `getPlot` separate from `executeCode`), btw (env + docs
   tools; `run_r` opt-in), Posit Assistant (automatic session context).
4. It is cheap (§2.14) and bounded: implementation uses only `get0()` on the session env, `class/dim/length/names`,
   `utils::str(max.level=1)`, sampled NA rates, `tools::Rd_db/Rd2txt`, `getNamespaceExports/formals`,
   `tools::getVignetteInfo`, `utils::help.search`, `sessionInfo`. It must never force promises (`get0` on an active
   binding/promise evaluates it — use `exists()` + `bindingIsActive()` checks) and must not touch the RNG (use stride,
   not `sample()`: see §7).

**Left to `run_r`** (documented in the system prompt as available R functions, not tools): CRAN search
(`tools::CRAN_package_db()` — network), `news()`, package installation (always ask), `devtools::test()`/`check()`,
plotting, arbitrary `summary()`s, `methods()`, `getAnywhere()`, `RSiteSearch` (network). Every gptr tool is also an R
function (`gptr::tool_grep()` etc., track 01 §4.1), so the minimal preset stays fully capable.

**Automatic context (no tool call)**: a compact `<session_context>` block each turn listing object names, classes,
dimensions and sizes in the evaluation env (values never included), R version, attached packages, cwd, mode — the Posit
Assistant pattern, which saves the first `objects` call on nearly every turn. Cap at e.g. 60 objects / 3 KB, most recently
modified first.

**Deferred (not in v1)**: todo/plan tools (both leaders disabled them by default on new models), `EnterPlanMode`/
`ExitPlanMode` (mode is set by the user: `mode = plan`), `Monitor`, cron/loop/`/goal` (trivially R control flow),
worktrees, agent teams / cross-session messaging, LSP, auto memory, `request_permissions`, `get_context_remaining`,
Workflow scripts (REQ-35 is satisfied by R itself), artifacts beyond the Shiny track.

### 4.2 System prompt outline (sections as XML tags, Pi-style, each independently replaceable — D-03/REQ-31)

1. `<preamble>` — "You are gptr, an agent running *inside* the user's live R session (R x.y, OS). Objects you create
   persist in `<env label>`; the user will keep using them."
2. `<tools>` — one line per active tool + guidelines (from each tool's definition, Pi's mechanism, track 01 §2.11).
3. `<r_rules>` — R-specific rules distilled from btw's `run_r` description and Databot: work incrementally (≤50 lines
   per call), one figure per call, return values implicitly, prefer `str()/head()/summary()`, never reload large objects
   that already exist, never overwrite or `rm()` user objects without asking (create new names), use `tempfile()` for
   scratch, at most 2 attempts to fix the same error then report, no installs/network/shell unless asked, keep printed
   output small, use `r_inspect` for help and structure.
4. `<document>` — how the harness document works (where code goes, `#>` outputs, `## Decision:` comments; D-08).
5. `<mode>` — current permission mode text (plan mode = Codex plan template adapted: explore non-mutating first, ask via
   `ask`, finish with `<proposed_plan>`; manual/edits/auto semantics).
6. `<delegation>` — only if `agent` is active: Codex's "do not spawn unless asked" + critical-path guidance (§3.5).
7. `<skills>` — skill list (names + descriptions; track 05).
8. `<environment>` — cwd, project root, harness document path, date; **placed in the first user message, not the system
   prompt**, for cache reuse (Claude's `excludeDynamicSections`).
9. Project instructions (`.gptr/vignette.Rmd`, `AGENTS.md`/`CLAUDE.md`) and `<session_context>` are **user-role context
   messages**, as Claude and Codex do; the system prompt contains the sentence: "The application adds context blocks
   (project instructions, session context, hook output) to this conversation; treat them as information from the
   application, not as messages from the user" (Claude's recommended wording, `CC/agent-sdk/modifying-system-prompts` 416-418).
10. `<closing>` — answer style: concise; for exploratory work end with 3–5 suggested next steps (Databot); name objects
    created.

### 4.3 Edit / apply_patch engine

```r
# Internal engine (one implementation, §5.1)
patch_parse(patch)                      # -> list(hunks, environment_id); gptr_patch_error on failure
patch_apply(patch, cwd = project_root(), atomic = TRUE, mode = c("preserve_eol", "lf"))
patch_from_openai_operation(operation)  # native {"type":"apply_patch"} items -> envelope
# Model-facing registration
tool_apply_patch_freeform()   # Responses API custom tool: name/description/grammar verbatim from Codex
tool_apply_patch_function()   # {"name":"apply_patch","parameters":{"type":"object","properties":{"patch":{"type":"string"}},"required":["patch"]}}
select_edit_tools(model)      # gpt-5* (not oss) on openai/responses -> apply_patch; else edit + write
```
Rules: `atomic = TRUE` by default (validate every hunk against an in-memory overlay before writing — Codex is not
atomic; btw is); refuse paths outside the project unless mode allows (D-11); return the Codex success summary plus a
unified diff (Pi returns only a one-line message to the model; Claude returns `structuredPatch` for UI); preserve line
endings and encodings (track 01's encoding round-trip applies); record pre-edit copies for undo (Claude checkpointing
analogue, `.gptr/sessions/<id>/snapshots/`).

### 4.4 Sub-agent definitions and presentation

* Files: `.gptr/agents/*.md` and `tools::R_user_dir("gptr","config")/agents/*.md`, **Claude-compatible frontmatter**
  (`name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`→`mode`, `maxTurns`, `skills`,
  `mcpServers`, `effort`, `background`) plus gptr extras: `execution: inline|worker|cli` (D-12), `returns:` (JSON schema
  → structured R value), `envir: inherit|isolated`. Also *read-only discovery* of `.claude/agents/*.md` and
  `.codex/agents/*.toml` (btw precedent), with tool-name mapping `Read→read`, `Glob→find`, `Grep→grep`, `LS→ls`,
  `Edit|MultiEdit→edit`, `Write→write`, `NotebookEdit→notebook_edit`, `Bash|PowerShell→shell` (not `run_r`!),
  `WebFetch→web_fetch`, `WebSearch→web_search`, `Agent|Task→agent`, `AskUserQuestion→ask` (sub-agents never get `ask`,
  as in Claude Code), Codex `sandbox_mode read-only→plan`, `workspace-write→edits`, `danger-full-access→auto`.
* Programmatic API is primary (REQ-32..35): `gptr(prompt, agents = list(stats = agent(...)))`, `parallel = 4`; the
  model-facing `agent` tool is a thin wrapper.
* Presentation to the model: foreground → the sub-agent's final text (+ `<usage tokens=… tools=… seconds=…/>`), wrapped
  as `<agent_result id="…" name="…">…</agent_result>` with a header stating it is sub-agent output without user
  authority, after escaping imitation tags (Claude's output scanning). Background → immediate
  `<agent_started id="…" name="…"/>`; completion arrives as a user-role
  `<agent_notification id="…" status="completed|failed">…</agent_notification>` at the next turn boundary (Claude and Codex
  both do this). Defaults: depth 2, 4 concurrent `worker` agents (Codex v2 default), no unsolicited spawning.

### 4.5 Project instructions (`.gptr/vignette.Rmd` interop)

Algorithm (prototype §5.3): root = nearest ancestor with `.gptr`, `.git`, `DESCRIPTION`, `.here`, `*.Rproj` (btw's
markers + `.gptr`); load order user file → `.gptr/vignette.Rmd` → for each dir root→cwd: first of `AGENTS.md`,
`CLAUDE.md`, `.claude/CLAUDE.md` (option `gptr.instruction_files = "first" | "all" | "none"`), then `CLAUDE.local.md`;
strip YAML front matter and block HTML comments; expand `@path` imports outside code (≤4 hops, cycle-safe, project-root
fallback for vignette, outside-project imports need approval); dedupe by normalised path (handles `CLAUDE.md` symlinked or
importing `AGENTS.md`); 64 KiB budget with a warning listing skipped files; each file wrapped in
`<instructions source="rel/path">`. Re-inject after compaction (Claude behaviour). `gptr_init()` should write a
`vignette.Rmd` whose first lines say it may `@AGENTS.md`, and should *offer* (not force) creating `AGENTS.md`.
R chunks inside `vignette.Rmd` are **not executed** when loading instructions (text only); rendering to HTML is for humans.

### 4.6 R-level hooks (D-25 input)

Register with `gptr_hook(event, fn, matcher = NULL)`; `fn(event)` receives a list mirroring Claude's JSON
(`session_id`, `cwd`, `mode`, `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`, `agent_id`, …) and returns
`NULL` (no-op) or a list with any of `decision = "block"`, `reason`, `permission = "allow"|"deny"|"ask"`,
`updated_input`, `additional_context`, `updated_output`, `continue = FALSE`, `stop_reason`, `message`. v1 events:
`session_start` (source startup|resume|compact), `user_prompt`, `pre_tool`, `permission_request`, `post_tool`,
`post_tool_failure`, `stop`, `subagent_start`, `subagent_stop`, `pre_compact`, `post_compact`, `session_end`. Defer
file/cwd/config/worktree/elicitation/notification events and external command/http hooks (security: Codex requires hash
trust for non-managed hooks). Errors in a hook are reported, never silently swallowed, and a crashing `pre_tool` hook
must not allow a call that the permission system would deny.

### 4.7 Context management (D-19 input)

Auto-compact when `remaining < max(30000, 10% of window)` (Posit buffer vs Codex 90% rule); two-stage like Claude:
(1) micro-compaction replacing old tool results with `[output of <tool> elided; rerun if needed]` stubs (keeping calls),
(2) full summary with Codex's handoff prompt + prefix. After compaction re-inject: system prompt, instructions,
session context, active plan file, last ≤5 edited files (paths only when large), invoked skills (≤5K tokens each).
Tool outputs >30,000 chars go to a temp file with head/tail preview (track 01). `/compact [focus]`, `/btw`-style side
questions (no tools, not recorded) are cheap wins for the console UX (D-26). Steering: queue console input and deliver it
after the current tool call finishes (Claude's rule).

### 4.8 Package choices

| Need | Package | Imports / Suggests |
|---|---|---|
| JSON (tool schemas, ipynb, hooks) | jsonlite | Imports (already in D-20) |
| YAML frontmatter (agents, skills, rules) | yaml | **Imports recommended** (small, CRAN-stable, already required by rmarkdown/knitr); fallback mini-parser otherwise |
| apply_patch, instructions discovery, r_inspect | base R + utils + tools | — |
| Output capture with plots | evaluate | Suggests (btw uses it; track on eval decides) |
| PNG device | ragg | Suggests |
| TOML (Codex agent files) | none — ship the 40-line subset reader (§5.5) | — |

---

## 5. Verified R prototypes

All run with `Rscript --vanilla` (R 4.4.3, macOS arm64, C locale because `LANG`/`LC_ALL` are unset in the agent's shell
environment — not because of `--vanilla`: `Rscript` without `--vanilla` is also `C` here, and `LANG=en_US.UTF-8 Rscript
--vanilla` gives `en_US.UTF-8`; re-verified 2026-09-29) on 2026-09-29. Files and outputs are in `.../scratchpad/work/track-20/proto/`.

### 5.1 apply_patch engine (`apply_patch.R`, 277 lines) — passes Codex conformance fixtures

```r
# Pure-R port of the Codex `apply_patch` format ("*** Begin Patch" envelope,
# a.k.a. the V4A patch format that OpenAI GPT-4.1/5.x models are trained on).
# Reference: openai/codex codex-rs/apply-patch (parser.rs, streaming_parser.rs,
# seek_sequence.rs, file_update.rs, text_file.rs) at commit 8ea2c0e0 (2026-09-30).
# Base R only. Semantics follow Codex's "PreserveLineEndings" mode, which is the
# mode the official portable fixtures are run in.

ap_error <- function(msg, line = NULL) {
  stop(structure(class = c("gptr_patch_error", "error", "condition"),
                 list(message = if (is.null(line)) msg else sprintf("Invalid patch hunk on line %d: %s", line, msg),
                      call = NULL)))
}

# ---- parsing -----------------------------------------------------------------
ap_parse <- function(patch) {
  patch <- ap_as_utf8(patch)
  lines <- strsplit(trimws(patch), "\n", fixed = TRUE)[[1]]
  lines <- sub("\r$", "", lines)
  # lenient heredoc form produced by some models: <<'EOF' ... EOF
  if (length(lines) >= 4L && lines[1] %in% c("<<EOF", "<<'EOF'", "<<\"EOF\"") &&
      grepl("EOF$", lines[length(lines)])) {
    lines <- lines[2:(length(lines) - 1L)]
  }
  if (!length(lines) || trimws(lines[1]) != "*** Begin Patch")
    ap_error("Invalid patch: The first line of the patch must be '*** Begin Patch'")
  hunks <- list(); mode <- "started"; hunk_line <- NA_integer_; env_id <- NULL
  cur <- function() hunks[[length(hunks)]]
  set_cur <- function(h) hunks[[length(hunks)]] <<- h
  new_chunk <- function(ctx = NULL) list(change_context = ctx, old = character(), new = character(),
                                         ctx_idx = list(), eof = FALSE)
  ensure_update_not_empty <- function(line, lno) {
    if (length(hunks) && cur()$type == "update") {
      h <- cur()
      if (!length(h$chunks) && mode == "update")
        ap_error(sprintf("Update file hunk for path '%s' is empty", h$path), hunk_line)
      if (length(h$chunks)) {
        last <- h$chunks[[length(h$chunks)]]
        if (!length(last$old) && !length(last$new)) {
          if (line == "*** End Patch") ap_error("Update hunk does not contain any lines", lno)
          ap_error(sprintf("Unexpected line found in update hunk: '%s'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)", line), lno)
        }
      }
    }
  }
  headers <- function(t, lno) {
    if (mode == "started" && startsWith(t, "*** Environment ID: ")) {
      env_id <<- trimws(substring(t, 21L)); return(TRUE)
    }
    if (t == "*** End Patch") { ensure_update_not_empty(t, lno); mode <<- "ended"; return(TRUE) }
    for (m in list(c("*** Add File: ", "add"), c("*** Delete File: ", "delete"), c("*** Update File: ", "update"))) {
      if (startsWith(t, m[1])) {
        ensure_update_not_empty(t, lno)
        path <- substring(t, nchar(m[1]) + 1L)
        hunks[[length(hunks) + 1L]] <<- switch(m[2],
          add = list(type = "add", path = path, contents = ""),
          delete = list(type = "delete", path = path),
          update = list(type = "update", path = path, move_to = NULL, chunks = list()))
        mode <<- m[2]; if (m[2] == "update") hunk_line <<- lno
        return(TRUE)
      }
    }
    FALSE
  }
  bad_header <- function(t, lno) ap_error(sprintf("'%s' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'", t), lno)
  nlines <- length(lines)
  for (lno in seq_along(lines)[-1L]) {
    line <- lines[lno]; t <- trimws(line)
    # Codex finish(): the final (unterminated) line is compared with a full trim
    if (lno == nlines && t == "*** End Patch" && mode != "ended") {
      ensure_update_not_empty(t, lno); mode <- "ended"; next
    }
    if (mode == "ended") { if (nzchar(t)) ap_error("Invalid patch: The last line of the patch must be '*** End Patch'"); next }
    if (mode %in% c("started", "delete")) { if (!headers(t, lno)) bad_header(t, lno); next }
    if (mode == "add") {
      if (headers(t, lno)) next
      if (startsWith(line, "+")) { h <- cur(); h$contents <- paste0(h$contents, substring(line, 2L), "\n"); set_cur(h); next }
      bad_header(t, lno)
    }
    # mode == "update"
    ul <- sub("[[:space:]]+$", "", line)
    if (headers(ul, lno)) next
    h <- cur(); ch <- h$chunks; nch <- length(ch)
    if (nch && ch[[nch]]$eof) {
      if (!nzchar(ul)) next
      if (ul != "@@" && !startsWith(ul, "@@ "))
        ap_error(sprintf("Expected update hunk to start with a @@ context marker, got: '%s'", line), lno)
    }
    if (!nch && is.null(h$move_to) && startsWith(ul, "*** Move to: ")) {
      h$move_to <- substring(ul, 14L); set_cur(h); next
    }
    if ((ul == "@@" || startsWith(ul, "@@ ")) && nch && !length(ch[[nch]]$old) && !length(ch[[nch]]$new))
      ap_error(sprintf("Unexpected line found in update hunk: '%s'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)", line), lno)
    if (ul == "@@") { h$chunks[[nch + 1L]] <- new_chunk(); set_cur(h); next }
    if (startsWith(ul, "@@ ")) { h$chunks[[nch + 1L]] <- new_chunk(substring(ul, 4L)); set_cur(h); next }
    if (ul == "*** End of File") {
      if (nch && !length(ch[[nch]]$old) && !length(ch[[nch]]$new)) ap_error("Update hunk does not contain any lines", lno)
      h$chunks[[nch]]$eof <- TRUE; set_cur(h); next
    }
    pfx <- if (!nzchar(line)) " " else substr(line, 1L, 1L)
    if (pfx %in% c(" ", "+", "-")) {
      if (!nch) { h$chunks[[1L]] <- new_chunk(); nch <- 1L }
      c1 <- h$chunks[[nch]]; txt <- if (nzchar(line)) substring(line, 2L) else ""
      if (pfx == " ") {
        c1$ctx_idx[[length(c1$ctx_idx) + 1L]] <- c(length(c1$old), length(c1$new)) # 0-based indices
        c1$old <- c(c1$old, txt); c1$new <- c(c1$new, txt)
      } else if (pfx == "+") c1$new <- c(c1$new, txt) else c1$old <- c(c1$old, txt)
      h$chunks[[nch]] <- c1; set_cur(h); next
    }
    if (nch && (length(ch[[nch]]$old) || length(ch[[nch]]$new)))
      ap_error(sprintf("Expected update hunk to start with a @@ context marker, got: '%s'", line), lno)
    ap_error(sprintf("Unexpected line found in update hunk: '%s'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)", line), lno)
  }
  if (mode != "ended") ap_error("Invalid patch: The last line of the patch must be '*** End Patch'")
  list(hunks = hunks, environment_id = env_id)
}

# ---- fuzzy line matching (exact, rstrip, trim, unicode-normalised) -----------
ap_normalise <- function(s) {
  s <- trimws(s)
  s <- gsub("[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]", "-", s)
  s <- gsub("[\u2018\u2019\u201A\u201B]", "'", s)
  s <- gsub("[\u201C\u201D\u201E\u201F]", "\"", s)
  gsub("[\u00A0\u2002-\u200A\u202F\u205F\u3000]", " ", s)
}
ap_seek <- function(lines, pattern, start, eof) {   # start is 1-based; returns 1-based or NA
  np <- length(pattern); nl <- length(lines)
  if (!np) return(start)
  if (np > nl) return(NA_integer_)
  from <- if (eof) max(nl - np + 1L, start) else start
  last <- nl - np + 1L
  if (from > last) return(NA_integer_)
  for (f in list(identity, function(x) sub("[[:space:]]+$", "", x), trimws, ap_normalise)) {
    fp <- f(pattern); fl <- f(lines)
    for (i in from:last) if (identical(fl[i:(i + np - 1L)], fp)) return(i)
  }
  NA_integer_
}

# ---- source file with per-line endings ---------------------------------------
ap_source <- function(contents) {
  if (!nzchar(contents)) return(list(text = character(), end = character(), pref = "\n"))
  m <- gregexpr("\r\n|\r|\n", contents)[[1]]
  if (m[1] == -1L) return(list(text = contents, end = NA_character_, pref = "\n"))
  ends <- regmatches(contents, list(m))[[1]]
  starts <- c(1L, m + attr(m, "match.length"))
  texts <- substring(contents, starts[-length(starts)], m - 1L)
  tail_txt <- substring(contents, starts[length(starts)])
  if (nzchar(tail_txt)) { texts <- c(texts, tail_txt); ends <- c(ends, NA_character_) }
  list(text = texts, end = ends, pref = ends[1])
}
ap_render <- function(src) {
  e <- src$end; e[is.na(e)] <- src$pref   # every line gets an ending (Codex historical behaviour)
  paste0(src$text, e, collapse = "")
}

ap_compute_replacements <- function(orig, path, chunks) {
  reps <- list(); li <- 1L
  for (ch in chunks) {
    if (!is.null(ch$change_context)) {
      idx <- ap_seek(orig, ch$change_context, li, FALSE)
      if (is.na(idx)) ap_error(sprintf("Failed to find context '%s' in %s", ch$change_context, path))
      li <- idx + 1L
    }
    if (!length(ch$old)) {                      # pure insertion: append at end of file
      reps[[length(reps) + 1L]] <- list(start = length(orig) + 1L, len = 0L, new = ch$new, ch = ch)
      next
    }
    pat <- ch$old; nw <- ch$new
    found <- ap_seek(orig, pat, li, ch$eof)
    if (is.na(found) && length(pat) && pat[length(pat)] == "") {
      pat <- pat[-length(pat)]; if (length(nw) && nw[length(nw)] == "") nw <- nw[-length(nw)]
      found <- ap_seek(orig, pat, li, ch$eof)
    }
    if (is.na(found))
      ap_error(sprintf("Failed to find expected lines in %s:\n%s", path, paste(ch$old, collapse = "\n")))
    # keep context lines untouched (their exact text and endings survive)
    os <- 0L; ns <- 0L
    for (ci in ch$ctx_idx) {
      oc <- ci[1]; nc <- ci[2]
      if (oc >= length(pat) || nc >= length(nw)) break
      if (os != oc || ns != nc)
        reps[[length(reps) + 1L]] <- list(start = found + os, len = oc - os, new = nw[seq_len(nc - ns) + ns])
      os <- oc + 1L; ns <- nc + 1L
    }
    if (os != length(pat) || ns != length(nw))
      reps[[length(reps) + 1L]] <- list(start = found + os, len = length(pat) - os,
                                        new = if (length(nw) > ns) nw[(ns + 1L):length(nw)] else character())
    li <- found + length(pat)
  }
  reps[order(vapply(reps, `[[`, 1L, "start"))]
}
ap_apply_replacements <- function(src, reps) {
  out_t <- character(); out_e <- character(); si <- 1L; n <- length(src$text)
  for (r in reps) {
    if (r$start > si) { k <- si:(r$start - 1L); out_t <- c(out_t, src$text[k]); out_e <- c(out_e, src$end[k]) }
    si <- r$start + r$len
    out_t <- c(out_t, r$new); out_e <- c(out_e, rep(src$pref, length(r$new)))
  }
  if (si <= n) { k <- si:n; out_t <- c(out_t, src$text[k]); out_e <- c(out_e, src$end[k]) }
  list(text = out_t, end = out_e, pref = src$pref)
}
ap_update_contents <- function(contents, path, chunks) {
  src <- ap_source(contents)
  ap_render(ap_apply_replacements(src, ap_compute_replacements(src$text, path, chunks)))
}

# ---- applying to disk ----------------------------------------------------------
read_bin_text <- function(p) { n <- file.size(p); if (!n) "" else ap_as_utf8(rawToChar(readBin(p, "raw", n))) }
# Mark text as UTF-8 when it is valid UTF-8 (Rscript --vanilla may run in the C
# locale, where unmarked multibyte strings break regex/trimws/substring).
ap_as_utf8 <- function(s) { if (Encoding(s) == "unknown" && validUTF8(s)) Encoding(s) <- "UTF-8"; s }
write_bin_text <- function(p, s) {
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  con <- file(p, "wb"); on.exit(close(con)); writeBin(charToRaw(enc2utf8(s)), con)
}

# atomic = FALSE mirrors Codex (sequential, partial success is kept);
# atomic = TRUE (recommended gptr default) validates every hunk in memory first.
ap_apply <- function(patch, cwd = getwd(), atomic = TRUE) {
  parsed <- ap_parse(patch)
  if (!length(parsed$hunks)) ap_error("No files were modified.")
  full <- function(p) if (grepl("^(/|[A-Za-z]:[/\\\\])", p)) p else file.path(cwd, p)
  plan <- list(); overlay <- new.env()      # overlay holds pending content for atomic mode
  get_text <- function(p) {
    if (exists(p, envir = overlay, inherits = FALSE)) {
      v <- get(p, envir = overlay); if (is.null(v)) ap_error(sprintf("Failed to read file to update %s", p)); return(v)
    }
    if (!file.exists(p) || dir.exists(p)) ap_error(sprintf("Failed to read file to update %s", p))
    read_bin_text(p)
  }
  summary <- list(A = character(), M = character(), D = character())
  do_write <- function(op) {
    if (op$kind == "write") write_bin_text(op$path, op$text)
    else if (op$kind == "delete") { if (!file.remove(op$path)) ap_error(sprintf("Failed to delete file %s", op$path)) }
  }
  for (h in parsed$hunks) {
    p <- full(h$path)
    ops <- switch(h$type,
      add = { summary$A <- c(summary$A, h$path); list(list(kind = "write", path = p, text = h$contents)) },
      delete = {
        if (!file.exists(p) || dir.exists(p)) {
          if (!(exists(p, envir = overlay, inherits = FALSE) && !is.null(get(p, envir = overlay))))
            ap_error(sprintf("Failed to delete file %s", p))
        }
        summary$D <- c(summary$D, h$path); list(list(kind = "delete", path = p))
      },
      update = {
        newtxt <- ap_update_contents(get_text(p), h$path, h$chunks)
        if (is.null(h$move_to)) { summary$M <- c(summary$M, h$path); list(list(kind = "write", path = p, text = newtxt)) }
        else { summary$M <- c(summary$M, h$move_to)
               list(list(kind = "write", path = full(h$move_to), text = newtxt), list(kind = "delete", path = p)) }
      })
    for (op in ops) {
      assign(op$path, if (op$kind == "write") op$text else NULL, envir = overlay)
      if (atomic) plan[[length(plan) + 1L]] <- op else do_write(op)
    }
  }
  if (atomic) for (op in plan) do_write(op)
  out <- "Success. Updated the following files:"
  for (k in c("A", "M", "D")) if (length(summary[[k]])) out <- c(out, paste(k, summary[[k]]))
  paste(out, collapse = "\n")
}

# OpenAI Responses API native tool: {"type":"apply_patch"} emits apply_patch_call
# items whose `operation` is {type: create_file|update_file|delete_file, path, diff}
# with a per-file V4A diff (no envelope). Wrap it so the same engine applies it.
ap_from_openai_operation <- function(operation) {
  d <- sub("^(\r?\n)+", "", operation$diff %||% "")
  d <- sub("(\r?\n)+$", "", d)
  hdr <- switch(operation$type,
                create_file = paste0("*** Add File: ", operation$path),
                update_file = paste0("*** Update File: ", operation$path),
                delete_file = paste0("*** Delete File: ", operation$path))
  body <- if (operation$type == "delete_file") character() else d
  paste(c("*** Begin Patch", hdr, body, "*** End Patch"), collapse = "\n")
}
`%||%` <- function(a, b) if (is.null(a)) b else a
```

Conformance harness (`test_apply_patch.R`) — copies each fixture's `input/` to a temp dir, applies `patch.txt`, compares
the full directory snapshot byte-for-byte with `expected/` (as `CX/codex-rs/apply-patch/tests/suite/scenarios.rs` does):

```r
source(".../proto/apply_patch.R")
scen <- ".../codex-src/codex-rs/apply-patch/tests/fixtures/scenarios"
snapshot <- function(root) {
  if (!dir.exists(root)) return(list())
  f <- list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE, no.. = TRUE)
  f <- f[f != ".gitattributes"]
  out <- lapply(f, function(x) { p <- file.path(root, x); if (dir.exists(p)) "<dir>" else readBin(p, "raw", max(1L, file.size(p)))[seq_len(file.size(p))] })
  names(out) <- f
  out[order(names(out))]
}
run_one <- function(d, atomic) {
  tmp <- tempfile("ap_"); dir.create(tmp)
  inp <- file.path(d, "input")
  if (dir.exists(inp)) file.copy(list.files(inp, full.names = TRUE, all.files = TRUE, no.. = TRUE), tmp, recursive = TRUE)
  patch <- rawToChar(readBin(file.path(d, "patch.txt"), "raw", file.size(file.path(d, "patch.txt"))))
  msg <- tryCatch(ap_apply(patch, cwd = tmp, atomic = atomic), error = function(e) paste("ERROR:", conditionMessage(e)))
  ok <- identical(snapshot(tmp), snapshot(file.path(d, "expected")))
  unlink(tmp, recursive = TRUE)
  list(ok = ok, msg = msg)
}
dirs <- sort(list.dirs(scen, recursive = FALSE))
res <- lapply(dirs, function(d) {
  r1 <- run_one(d, atomic = FALSE); r2 <- run_one(d, atomic = TRUE)
  data.frame(scenario = basename(d), codex_mode = r1$ok, atomic_mode = r2$ok,
             result = substr(gsub("\n", " | ", r1$msg), 1, 70))
})
res <- do.call(rbind, res)
options(width = 200)
print(res, row.names = FALSE, right = FALSE)
cat(sprintf("\nCodex-compatible (atomic=FALSE): %d/%d pass; atomic=TRUE: %d/%d match\n",
            sum(res$codex_mode), nrow(res), sum(res$atomic_mode), nrow(res)))
# OpenAI native apply_patch_call adapter, @@ anchors, unicode fuzz, parse error:
tmp <- tempfile("ap_"); dir.create(tmp)
writeLines(c("def fib(n):", "    if n <= 1:", "        return n", "    return fib(n-1) + fib(n-2)"), file.path(tmp, "fib.py"))
op <- list(type = "update_file", path = "fib.py",
           diff = "@@\n-def fib(n):\n+def fibonacci(n):\n     if n <= 1:\n         return n\n-    return fib(n-1) + fib(n-2)\n+    return fibonacci(n-1) + fibonacci(n-2)\n")
cat("\n", ap_apply(ap_from_openai_operation(op), cwd = tmp), "\n", sep = "")
cat(readLines(file.path(tmp, "fib.py")), sep = "\n")
op2 <- list(type = "create_file", path = "notes/todo.md", diff = "+# TODO\n+- one\n")
cat(ap_apply(ap_from_openai_operation(op2), cwd = tmp), "\n")
cat(readLines(file.path(tmp, "notes/todo.md")), sep = "\n")
writeLines(c("f <- function(x) {", "  # a \u2014 dash", "  x + 1", "}", "g <- function(x) {", "  x + 1", "}"), file.path(tmp, "a.R"), useBytes = TRUE)
p3 <- "*** Begin Patch\n*** Update File: a.R\n@@ g <- function(x) {\n-  x + 1\n+  x + 2\n*** End Patch"
cat(ap_apply(p3, cwd = tmp), "\n"); cat(readLines(file.path(tmp, "a.R"), encoding = "UTF-8"), sep = "\n")
p4 <- "*** Begin Patch\n*** Update File: a.R\n@@\n-  # a - dash\n+  # an ASCII dash\n*** End Patch"
cat(ap_apply(p4, cwd = tmp), "\n"); cat(readLines(file.path(tmp, "a.R"), encoding = "UTF-8")[2], "\n")
cat(tryCatch(ap_apply("*** Begin Patch\n*** Frobnicate File: x\n*** End Patch", cwd = tmp), error = conditionMessage), "\n")
unlink(tmp, recursive = TRUE)
```
(`...` stands for the scratchpad path; the executed file uses the absolute path. In the executed file the em dash is written
as a literal UTF-8 character; `\u2014` shown here is equivalent.)

Observed output (executed: `Rscript --vanilla test_apply_patch.R`):
```
 scenario                                         codex_mode atomic_mode result
 001_add_file                                     TRUE        TRUE       Success. Updated the following files: | A bar.md
 002_multiple_operations                          TRUE        TRUE       Success. Updated the following files: | A nested/new.txt | M modify.tx
 003_multiple_chunks                              TRUE        TRUE       Success. Updated the following files: | M multi.txt
 004_move_to_new_directory                        TRUE        TRUE       Success. Updated the following files: | M renamed/dir/name.txt
 005_rejects_empty_patch                          TRUE        TRUE       ERROR: No files were modified.
 006_rejects_missing_context                      TRUE        TRUE       ERROR: Failed to find expected lines in modify.txt: | missing
 007_rejects_missing_file_delete                  TRUE        TRUE       ERROR: Failed to delete file /var/folders/...
 008_rejects_empty_update_hunk                    TRUE        TRUE       ERROR: Invalid patch hunk on line 2: Update file hunk for path 'foo.tx
 009_requires_existing_file_for_update            TRUE        TRUE       ERROR: Failed to read file to update /var/folders/...
 010_move_overwrites_existing_destination         TRUE        TRUE       Success. Updated the following files: | M renamed/dir/name.txt
 011_add_overwrites_existing_file                 TRUE        TRUE       Success. Updated the following files: | A duplicate.txt
 012_delete_directory_fails                       TRUE        TRUE       ERROR: Failed to delete file /var/folders/...
 013_rejects_invalid_hunk_header                  TRUE        TRUE       ERROR: Invalid patch hunk on line 2: '*** Frobnicate File: foo' is not
 014_update_file_appends_trailing_newline         TRUE        TRUE       Success. Updated the following files: | M no_newline.txt
 015_failure_after_partial_success_leaves_changes TRUE       FALSE       ERROR: Failed to read file to update /var/folders/...
 016_pure_addition_update_chunk                   TRUE        TRUE       Success. Updated the following files: | M input.txt
 017_whitespace_padded_hunk_header                TRUE        TRUE       Success. Updated the following files: | M foo.txt
 018_whitespace_padded_patch_markers              TRUE        TRUE       Success. Updated the following files: | M file.txt
 019_unicode_simple                               TRUE        TRUE       Success. Updated the following files: | M foo.txt
 020_delete_file_success                          TRUE        TRUE       Success. Updated the following files: | D obsolete.txt
 020_whitespace_padded_patch_marker_lines         TRUE        TRUE       Success. Updated the following files: | M file.txt
 021_update_file_deletion_only                    TRUE        TRUE       Success. Updated the following files: | M lines.txt
 022_update_file_end_of_file_marker               TRUE        TRUE       Success. Updated the following files: | M tail.txt
 023_preserves_crlf_line_endings                  TRUE        TRUE       Success. Updated the following files: | M lines.txt
 024_preserves_mixed_line_endings                 TRUE        TRUE       Success. Updated the following files: | M lines.txt

Codex-compatible (atomic=FALSE): 25/25 pass; atomic=TRUE: 24/25 match

Success. Updated the following files:
M fib.py
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
Success. Updated the following files:
A notes/todo.md
# TODO
- one
Success. Updated the following files:
M a.R
f <- function(x) {
  # a <U+2014> dash
  x + 1
}
g <- function(x) {
  x + 2
}
Success. Updated the following files:
M a.R
  # an ASCII dash
Invalid patch hunk on line 2: '*** Frobnicate File: x' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'
```
The only atomic-mode mismatch (015) is the intended difference (nothing is written when any hunk fails). Verifier re-ran
this exact code (extracted from this report) against the same fixtures: identical table, 25/25 and 24/25. Note that
Codex's own runner (`tests/suite/scenarios.rs`) compares only the final directory snapshot, not messages or exit
status, so "passes" means byte-identical resulting files; the error strings were checked separately against
`streaming_parser.rs`/`file_update.rs`/`lib.rs` and match. `<U+2014>` is how
`cat()` prints an em dash in the C locale; the file bytes are correct. **Two bugs found while developing and fixed**: (1)
under the C locale, unmarked UTF-8 file content broke fixture 019 until strings were marked `Encoding(x) <- "UTF-8"`;
(2) Codex compares the final unterminated line with a full trim (fixture `020_whitespace_padded_patch_marker_lines`).

Benchmark (executed `bench_apply_patch.R`): 50,000-line file, change at EOF: **0.41 s**; unmatched context (all four fuzz
passes over the file): **0.66 s**. No Rcpp justification (REQ-01).

### 5.2 R-native introspection helpers (`r_native_tools.R`)

```r
`%||%` <- function(a, b) if (is.null(a)) b else a

## 1. Help page as plain text, no ':::'
help_text <- function(topic, package = NULL, max_chars = 20000L) {
  hf <- if (is.null(package)) {
    utils::help(topic = (topic), help_type = "text")
  } else {
    utils::help(topic = (topic), package = (package), help_type = "text")
  }
  paths <- as.character(hf)
  if (!length(paths)) {
    return(sprintf("No help found for topic '%s'%s.", topic,
                   if (is.null(package)) "" else paste0(" in package '", package, "'")))
  }
  path <- paths[[1L]]                      # <lib>/<pkg>/help/<Rdname>; several hits possible
  pkg <- basename(dirname(dirname(path)))
  rdname <- basename(path)
  db <- tools::Rd_db(pkg)
  rd <- db[[paste0(rdname, ".Rd")]]
  if (is.null(rd)) return(sprintf("Rd object '%s' not found in '%s'.", rdname, pkg))
  txt <- utils::capture.output(
    tools::Rd2txt(rd, out = "", options = list(underline_titles = FALSE, width = 80L))
  )
  txt <- paste(txt, collapse = "\n")
  hdr <- sprintf("[help: %s::%s]%s", pkg, topic,
                 if (length(paths) > 1L) sprintf(" (%d matches; first shown: %s)",
                                                  length(paths), paste(basename(dirname(dirname(paths))), collapse = ", ")) else "")
  if (nchar(txt) > max_chars) txt <- paste0(substr(txt, 1L, max_chars), "\n...[truncated]")
  paste(hdr, txt, sep = "\n")
}

## 2. Package discovery
pkg_exports <- function(package, pattern = NULL, n = 200L) {
  if (!requireNamespace(package, quietly = TRUE)) return(sprintf("Package '%s' is not installed.", package))
  ex <- sort(getNamespaceExports(package))
  if (!is.null(pattern)) ex <- grep(pattern, ex, value = TRUE)
  ns <- asNamespace(package)
  sig <- vapply(utils::head(ex, n), function(nm) {
    obj <- get0(nm, envir = ns, inherits = FALSE)
    if (is.function(obj)) sprintf("%s(%s)", nm, paste(names(formals(obj) %||% list()), collapse = ", "))
    else sprintf("%s <%s>", nm, class(obj)[1L])
  }, character(1))
  c(sprintf("%s %s: %d exports%s", package, as.character(utils::packageVersion(package)),
            length(ex), if (length(ex) > n) sprintf(" (first %d shown)", n) else ""), sig)
}
vignettes_of <- function(package) {
  vi <- tools::getVignetteInfo(package)
  if (!nrow(vi)) return(sprintf("No installed vignettes for '%s'.", package))
  sprintf("%s  [%s]  source: %s", vi[, "Topic"], vi[, "Title"], file.path(vi[, "Dir"], "doc", vi[, "File"]))
}

## 3. Session description
session_brief <- function() {
  si <- utils::sessionInfo()
  att <- vapply(si$otherPkgs %||% list(), function(d) paste0(d$Package, " ", d$Version), "")
  c(sprintf("%s | %s | %s", R.version.string, si$running %||% Sys.info()[["sysname"]], Sys.getlocale("LC_CTYPE")),
    sprintf("cwd: %s", getwd()),
    sprintf("attached: %s", paste(c(si$basePkgs, att), collapse = ", ")),
    sprintf("loaded namespaces: %d", length(loadedNamespaces())))
}

## 4. Cheap object description (bounded cost)
describe_object <- function(x, name = deparse(substitute(x)), max_cols = 30L, sample_rows = 1e5L) {
  cls <- paste(class(x), collapse = "/")
  head <- sprintf("%s <%s>", name, cls)
  if (is.data.frame(x)) {
    nr <- nrow(x); nc <- ncol(x)
    idx <- if (nr > sample_rows) sort(sample.int(nr, sample_rows)) else seq_len(nr)
    cols <- utils::head(names(x), max_cols)
    info <- vapply(cols, function(cn) {
      v <- x[[cn]]; vs <- v[idx]; na <- mean(is.na(vs)); ty <- paste(class(v), collapse = "/")
      ex <- paste(utils::head(format(unique(utils::head(vs[!is.na(vs)], 50L))), 3L), collapse = ", ")
      sprintf("  $ %s <%s> NA%s%.1f%% e.g. %s", cn, ty, if (nr > sample_rows) "~" else "=", 100 * na, ex)
    }, character(1))
    return(c(sprintf("%s %s x %s%s", head, format(nr, big.mark = ","), nc,
                     if (nr > sample_rows) sprintf(" (NA rates from %s sampled rows)", format(sample_rows, big.mark = ",")) else ""),
             info, if (nc > max_cols) sprintf("  ... %d more columns", nc - max_cols)))
  }
  if (isS4(x)) return(sprintf("%s (S4) slots: %s", head, paste(methods::slotNames(x), collapse = ", ")))
  if (is.list(x)) return(c(sprintf("%s list of %d", head, length(x)),
                           utils::capture.output(utils::str(x, max.level = 1L, list.len = 20L, give.attr = FALSE))))
  c(sprintf("%s length %s", head, format(length(x), big.mark = ",")),
    utils::capture.output(utils::str(x, give.attr = FALSE, vec.len = 3L)))
}
## (exercise code: help_text("median"), help_text("lm","stats"), Rd_db("base") timing,
##  pkg_exports("jsonlite", "^(to|from)JSON$"), apropos/args, vignettes_of("jsonlite"),
##  session_brief(), describe_object(<2e6-row data.frame>), object.size, help.search)
```
Observed output (excerpt, executed):
```
=== help_text('median') (first 700 chars) ===
[help: stats::median]
Median Value

Description:

     Compute the sample median.

Usage:

     median(x, na.rm = FALSE, ...)
...
[elapsed 0.51s, nchar 1553]
=== help_text('lm', 'stats') timing (Rd_db(stats)) ===
[elapsed 0.60s, nchar 10627]
Rd_db('base') elapsed 0.86s
No help found for topic 'no_such_topic_xyz'.
=== pkg_exports('jsonlite', '^(to|from)JSON$') ===
jsonlite 2.0.0: 2 exports
fromJSON(txt, simplifyVector, simplifyDataFrame, simplifyMatrix, flatten, ...)
toJSON(x, dataframe, matrix, Date, POSIXt, factor, complex, raw, null, na, auto_unbox, digits, pretty, force, ...)
=== vignettes_of('jsonlite') ===
json-mapping  [A mapping between JSON data and R objects]  source: /Library/.../jsonlite/doc/json-mapping.pdf.asis
json-paging  [Combining pages of JSON data with jsonlite]  source: /Library/.../jsonlite/doc/json-paging.Rmd
=== session_brief() ===
R version 4.4.3 (2025-02-28) | macOS 26.6.2 | C
=== describe_object on a 2e6-row data.frame ===
big <data.frame> 2,000,000 x 3 (NA rates from 100,000 sampled rows)
  $ id <integer> NA~0.0% e.g.  24,  35,  45
  $ g <character> NA~0.0% e.g. y, c, b
  $ x <numeric> NA~10.0% e.g. -1.20560325, -0.55251852,  0.54359013
[elapsed 0.044s]
object.size 38.1 Mb [elapsed 0.027s]
=== help.search timing ===
hits 14 [elapsed 0.03s]
```
and (executed separately): `613 installed pkgs`, `help.search all pkgs: 124 hits, 1.06s`, `second call: 0.28s`,
`Rd_db(data.table): 77 Rd, 0.18s`, `Rd_db(Matrix): 123 Rd, 0.17s`, `Rd_db(ggplot2): 226 Rd, 0.19s`.
Verifier re-run (same machine; `help.search("linear model")` over all packages): 613 pkgs, 139 hits, 1.33 s, second
call 0.50 s; `Rd_db` data.table 0.09 s, Matrix 0.29 s, ggplot2 0.37 s (same Rd counts); `help_text("median")` 0.41 s,
`lm` 0.48 s, `Rd_db("base")` 0.95 s, `describe_object` 0.055 s. The author's hit count (124) came from an unrecorded
pattern; treat all timings as order-of-magnitude only.
**Caveat found**: `sample.int()` in `describe_object` perturbs the user's RNG stream (see §7); the production version must
use stride sampling.

### 5.3 Project-instruction discovery (`instructions.R`)

```r
`%||%` <- function(a, b) if (is.null(a)) b else a
read_utf8 <- function(p) {
  x <- readLines(p, warn = FALSE, encoding = "UTF-8")
  if (length(x) && startsWith(x[1], "\ufeff")) x[1] <- substring(x[1], 2L)   # strip BOM
  x
}
find_project_root <- function(start = getwd(),
                              markers = c(".gptr", ".git", "DESCRIPTION", ".here", "*.Rproj")) {
  d <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    hit <- vapply(markers, function(m) {
      if (grepl("*", m, fixed = TRUE)) length(Sys.glob(file.path(d, m))) > 0L
      else file.exists(file.path(d, m))
    }, logical(1))
    if (any(hit)) return(d)
    parent <- dirname(d)
    if (identical(parent, d)) return(normalizePath(start, winslash = "/"))  # no marker: cwd only
    d <- parent
  }
}
strip_front_matter <- function(x) {
  if (length(x) >= 2L && trimws(x[1]) == "---") {
    end <- which(trimws(x[-1]) %in% c("---", "..."))[1]
    if (!is.na(end)) x <- x[-seq_len(end + 1L)]
  }
  x
}
in_fence_mask <- function(x) {
  fence <- grepl("^\\s*(```|~~~)", x)
  inside <- (cumsum(fence) %% 2L) == 1L
  inside | fence
}
strip_html_comments <- function(x) {
  keep <- in_fence_mask(x)
  txt <- paste(ifelse(keep, x, x), collapse = "\n")   # (unused leftover)
  out <- x; i <- 1L; n <- length(x)
  while (i <= n) {
    if (!keep[i] && grepl("^\\s*<!--", x[i])) {
      j <- i; while (j <= n && !grepl("-->", x[j], fixed = TRUE)) j <- j + 1L
      out[i:min(j, n)] <- NA_character_; i <- j + 1L
    } else i <- i + 1L
  }
  out[!is.na(out)]
}
# Expand `@path` imports: outside fences and code spans; relative to the importing file,
# then (gptr rule) relative to the project root; ~ allowed; "\ " escapes spaces; max 4 hops.
expand_imports <- function(lines, file, root, depth = 0L, seen = new.env(), max_depth = 4L,
                           allow_outside = FALSE) {
  mask <- in_fence_mask(lines)
  out <- character()
  for (i in seq_along(lines)) {
    ln <- lines[i]
    out <- c(out, ln)
    if (mask[i] || depth >= max_depth) next
    stripped <- gsub("`[^`]*`", "", ln)
    m <- gregexpr("(^|\\s)@((\\\\ |[^[:space:]])+)", stripped, perl = TRUE)[[1]]
    if (m[1] == -1L) next
    tokens <- regmatches(stripped, list(m))[[1]]
    for (tk in tokens) {
      p <- sub("^\\s*@", "", tk)
      p <- gsub("\\\\ ", " ", p)
      p <- sub("[.,;:)]+$", "", p)
      if (!nzchar(p) || grepl("^[A-Za-z0-9_.+-]+@", p)) next
      target <- if (startsWith(p, "~")) path.expand(p) else if (grepl("^(/|[A-Za-z]:)", p)) p else file.path(dirname(file), p)
      if (!file.exists(target) && !grepl("^(/|~|[A-Za-z]:)", p)) target <- file.path(root, p)
      if (!file.exists(target) || dir.exists(target)) next
      target <- normalizePath(target, winslash = "/")
      if (!allow_outside && !startsWith(target, paste0(root, "/"))) {   # "/" guard: sibling "proj2" is outside "proj"
        out <- c(out, sprintf("<!-- gptr: import %s skipped (outside project; needs approval) -->", p)); next
      }
      if (exists(target, envir = seen, inherits = FALSE)) next
      assign(target, TRUE, envir = seen)
      sub_lines <- strip_html_comments(strip_front_matter(read_utf8(target)))
      out <- c(out, sprintf("<imported path=\"%s\">", p),
               expand_imports(sub_lines, target, root, depth + 1L, seen, max_depth, allow_outside),
               "</imported>")
    }
  }
  out
}
gptr_instructions <- function(cwd = getwd(), user_dir = NULL, mode = c("first", "all", "none"),
                              names = c("AGENTS.md", "CLAUDE.md"), max_bytes = 65536L) {
  mode <- match.arg(mode)
  root <- find_project_root(cwd)
  cwd <- normalizePath(cwd, winslash = "/")
  seen <- new.env(); files <- character()
  add <- function(p) {
    if (!file.exists(p) || dir.exists(p)) return(invisible())
    np <- normalizePath(p, winslash = "/")
    if (exists(np, envir = seen, inherits = FALSE)) return(invisible())
    assign(np, TRUE, envir = seen); files <<- c(files, np)
  }
  if (!is.null(user_dir)) { add(file.path(user_dir, "vignette.Rmd")); add(file.path(user_dir, "AGENTS.md")) }
  add(file.path(root, ".gptr", "vignette.Rmd"))
  rel <- if (startsWith(paste0(cwd, "/"), paste0(root, "/"))) substring(cwd, nchar(root) + 2L) else ""
  parts <- if (nzchar(rel)) strsplit(rel, "/", fixed = TRUE)[[1]] else character()
  dirs <- c(root, if (length(parts)) vapply(seq_along(parts), function(k) file.path(root, paste(parts[1:k], collapse = "/")), ""))
  if (mode != "none") for (d in dirs) {
    cand <- c(file.path(d, names), file.path(d, ".claude", "CLAUDE.md"))
    present <- cand[file.exists(cand)]
    if (mode == "first") present <- utils::head(present, 1L)
    for (p in present) add(p)
    add(file.path(d, "CLAUDE.local.md"))
  }
  blocks <- character(); total <- 0L; truncated <- character()
  for (f in files) {
    x <- strip_html_comments(strip_front_matter(read_utf8(f)))
    x <- expand_imports(x, f, root, seen = seen)
    txt <- paste(x, collapse = "\n")
    b <- nchar(txt, type = "bytes")
    if (total + b > max_bytes) { truncated <- c(truncated, f); next }
    total <- total + b
    blocks <- c(blocks, sprintf("<instructions source=\"%s\">\n%s\n</instructions>",
                                if (startsWith(f, paste0(root, "/"))) substring(f, nchar(root) + 2L) else f, txt))
  }
  structure(paste(blocks, collapse = "\n\n"), files = files, root = root, bytes = total,
            skipped_over_budget = truncated)
}
## test: synthetic project with .gptr/vignette.Rmd (YAML header, HTML comment, @docs/style.md import,
## @-paths inside a code fence and a code span), docs/style.md (self-import cycle, @../AGENTS.md),
## root AGENTS.md and CLAUDE.md, analysis/CLAUDE.md, analysis/sub/AGENTS.md; cwd = analysis/sub
```
Observed output (executed; temp path shortened):
````
files:
  .../proj/.gptr/vignette.Rmd
  .../proj/AGENTS.md
  .../proj/analysis/CLAUDE.md
  .../proj/analysis/sub/AGENTS.md
bytes: 496

<instructions source=".gptr/vignette.Rmd">

# How we work
Use data.table for anything over 1e6 rows. See @docs/style.md.
<imported path="docs/style.md">
## Style
snake_case everywhere; import again: @style.md (cycle)
@../AGENTS.md
</imported>
```r
# @docs/not-imported.md stays literal inside code
```
Mentioning `@docs/also-literal.md` in a code span does not import.
</instructions>

<instructions source="AGENTS.md">
# AGENTS.md
Run tests with testthat::test_local().
</instructions>

<instructions source="analysis/CLAUDE.md">
# analysis/CLAUDE.md
Plots use theme_minimal().
</instructions>

<instructions source="analysis/sub/AGENTS.md">
# sub AGENTS.md
This folder holds Seurat objects; never saveRDS over them.
</instructions>

--- mode = 'all' files ---
  .../proj/.gptr/vignette.Rmd
  .../proj/AGENTS.md
  .../proj/CLAUDE.md
  .../proj/analysis/CLAUDE.md
  .../proj/analysis/sub/AGENTS.md
````
YAML header and the HTML comment were stripped; the import expanded; the cycle and the already-loaded `AGENTS.md` were not
duplicated; fenced/code-span `@` paths stayed literal; root `CLAUDE.md` was skipped in `first` mode because `AGENTS.md`
exists in that directory. First run revealed that Claude's "relative to the importing file" rule makes `@docs/x.md` inside
`.gptr/vignette.Rmd` resolve to `.gptr/docs/x.md`; the root-relative fallback fixes that.
**Verifier fix (2026-09-29):** the original prototype tested containment with `startsWith(target, root)`, so an import
of `@../proj2/x.md` from project `.../proj` was treated as *inside* the project and expanded without approval
(re-executed: the sibling file's text was injected). The code above now compares against `paste0(root, "/")`; re-run
gives identical output for the synthetic test and the sibling import is skipped with the "needs approval" marker.
Production code should also compare case-insensitively on Windows/macOS file systems. The prototype records
`skipped_over_budget` but does not yet emit the warning described in §4.5.

### 5.4 Claude-compatible `notebook_edit` on `.ipynb` (`notebook_edit.R`)

```r
library(jsonlite)
nb_read <- function(path) fromJSON(path, simplifyVector = FALSE)
nb_write <- function(nb, path) {
  txt <- toJSON(nb, auto_unbox = TRUE, pretty = 1, null = "null", na = "null", digits = NA)
  writeLines(txt, path, useBytes = TRUE)
}
nb_new_id <- function() paste(sample(c(letters, 0:9), 8, TRUE), collapse = "")   # NB: touches RNG (see §7)
nb_split_source <- function(s) {           # nbformat stores source as list of lines with "\n"
  if (!nzchar(s)) return(list())
  as.list(strsplit(s, "(?<=\n)", perl = TRUE)[[1]])
}
notebook_edit <- function(notebook_path, new_source = "", cell_id = NULL,
                          cell_type = NULL, edit_mode = c("replace", "insert", "delete")) {
  edit_mode <- match.arg(edit_mode)
  nb <- nb_read(notebook_path)
  ids <- vapply(nb$cells, function(c) c$id %||% "", "")
  pos <- if (is.null(cell_id)) 0L else match(cell_id, ids)
  if (!is.null(cell_id) && is.na(pos)) stop(sprintf("Cell with ID '%s' not found in notebook.", cell_id))
  mk_cell <- function(type, src) {
    cell <- list(cell_type = type, id = nb_new_id(), metadata = structure(list(), names = character()),
                 source = nb_split_source(src))
    if (type == "code") { cell$execution_count <- NULL; cell["execution_count"] <- list(NULL); cell$outputs <- list() }
    cell
  }
  if (edit_mode == "insert") {
    if (is.null(cell_type)) stop("cell_type is required when using edit_mode=insert.")
    nb$cells <- append(nb$cells, list(mk_cell(cell_type, new_source)), after = pos)
  } else if (edit_mode == "delete") {
    if (is.null(cell_id)) stop("cell_id is required for delete.")
    nb$cells[[pos]] <- NULL
  } else {
    if (is.null(cell_id)) stop("cell_id is required for replace.")
    nb$cells[[pos]]$source <- nb_split_source(new_source)
    if (!is.null(cell_type)) nb$cells[[pos]]$cell_type <- cell_type
    if (identical(nb$cells[[pos]]$cell_type, "code")) {   # stale outputs are cleared, like Jupyter
      nb$cells[[pos]]["execution_count"] <- list(NULL); nb$cells[[pos]]$outputs <- list()
    }
  }
  nb_write(nb, notebook_path)
  sprintf("Updated cell %s (%s)", cell_id %||% "<start>", edit_mode)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
## test: a 2-cell nbformat 4.5 notebook with {} metadata, "tags": [], outputs; round-trip; replace b2; insert after a1
```
Observed output (executed):
```
round-trip identical after parse: TRUE
empty metadata stays {}: TRUE
empty tags stays []: TRUE
Updated cell b2 (replace)
Updated cell a1 (insert)
 $ type "markdown" id "a1" src "# Title\n" "text"
 $ type "markdown" id "3shqidfe" src "## Notes"
 $ type "code" id "b2" src "summary(mtcars)\n" "plot(mtcars$mpg)" n_out 0 ec NULL
valid JSON: TRUE
```
and `toJSON` writes `"execution_count":null,"outputs":[]` (executed check).

### 5.5 Cross-harness agent definitions (`agent_defs.R`)

```r
parse_frontmatter <- function(path) {
  x <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!length(x) || trimws(x[1]) != "---") return(list(meta = list(), body = paste(x, collapse = "\n")))
  end <- which(trimws(x[-1]) == "---")[1] + 1L
  if (is.na(end)) stop("unterminated frontmatter in ", path)
  meta <- yaml::yaml.load(paste(x[2:(end - 1L)], collapse = "\n"))
  list(meta = meta %||% list(), body = paste(x[-seq_len(end)], collapse = "\n"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a
split_tools <- function(v) {
  if (is.null(v)) return(NULL)
  v <- unlist(v); v <- unlist(strsplit(v, ","))
  trimws(v[nzchar(trimws(v))])
}
toml_subset <- function(path) {   # top-level key = value, """multi-line""", bools, numbers, string arrays, [tables]
  x <- readLines(path, warn = FALSE, encoding = "UTF-8"); out <- list(); i <- 1L; table <- NULL
  while (i <= length(x)) {
    ln <- sub("^\\s+", "", x[i])
    if (!nzchar(ln) || startsWith(ln, "#")) { i <- i + 1L; next }
    if (grepl("^\\[\\[?[^]]+\\]\\]?\\s*$", ln)) { table <- gsub("[][[:space:]]", "", ln); i <- i + 1L; next }
    m <- regmatches(ln, regexec("^([A-Za-z0-9_.-]+)\\s*=\\s*(.*)$", ln))[[1]]
    if (!length(m)) { i <- i + 1L; next }
    key <- if (is.null(table)) m[2] else paste(table, m[2], sep = ".")
    val <- m[3]
    if (startsWith(val, "\"\"\"")) {
      rest <- substring(val, 4L); buf <- character()
      if (grepl("\"\"\"\\s*$", rest)) buf <- sub("\"\"\"\\s*$", "", rest) else {
        if (nzchar(rest)) buf <- rest
        repeat { i <- i + 1L; if (grepl("\"\"\"\\s*$", x[i])) { buf <- c(buf, sub("\"\"\"\\s*$", "", x[i])); break }; buf <- c(buf, x[i]) }
      }
      val <- paste(buf, collapse = "\n"); val <- sub("\n$", "", val)
    } else if (grepl("^\".*\"\\s*(#.*)?$", val)) {
      val <- sub("^\"(.*)\"\\s*(#.*)?$", "\\1", val)
    } else if (val %in% c("true", "false")) val <- val == "true"
    else if (grepl("^-?[0-9.]+$", val)) val <- as.numeric(val)
    else if (startsWith(val, "[")) val <- trimws(gsub("\"", "", strsplit(gsub("^\\[|\\]$", "", val), ",")[[1]]))
    out[[key]] <- val; i <- i + 1L
  }
  out
}
gptr_agent_spec <- function(name, description, prompt, model = NULL, tools = NULL,
                            disallowed_tools = NULL, effort = NULL, mode = NULL, source = NULL,
                            max_turns = NULL, skills = NULL) {
  structure(list(name = name, description = description, prompt = prompt, model = model,
                 tools = tools, disallowed_tools = disallowed_tools, effort = effort,
                 mode = mode, max_turns = max_turns, skills = skills, source = source),
            class = "gptr_agent_spec")
}
from_claude_agent <- function(path) {
  fm <- parse_frontmatter(path); m <- fm$meta
  if (is.null(m$name) || is.null(m$description)) return(NULL)   # Claude Code skips these too
  gptr_agent_spec(m$name, m$description, fm$body, model = m$model, tools = split_tools(m$tools),
                  disallowed_tools = split_tools(m$disallowedTools), effort = m$effort,
                  mode = m$permissionMode, max_turns = m$maxTurns, skills = split_tools(m$skills), source = path)
}
from_codex_agent <- function(path) {
  t <- toml_subset(path)
  if (is.null(t$name) || is.null(t$description) || is.null(t$developer_instructions)) return(NULL)
  mode <- switch(t$sandbox_mode %||% "", "read-only" = "plan", "workspace-write" = "edits",
                 "danger-full-access" = "auto", NULL)
  gptr_agent_spec(t$name, t$description, t$developer_instructions, model = t$model,
                  effort = t$model_reasoning_effort, mode = mode, source = path)
}
## test: code-reviewer.md (Claude example), notes.md (no name -> skipped), pr-explorer.toml (Codex example + [mcp_servers] table)
```
Observed output (executed):
```
 $ name     : chr "code-reviewer"      $ model: chr "sonnet"   $ tools: chr [1:3] "Read" "Glob" "Grep"   $ max_turns: int 20
 $ name     : chr "pr_explorer"        $ model: chr "gpt-6-luna" $ effort: chr "high"   $ mode: chr "plan"
 $ prompt   : chr "Stay in exploration mode.\nTrace the real execution path, cite "| __truncated__
 $ mcp_servers.openaiDeveloperDocs.url: chr "https://developers.openai.com/mcp"
```
(`notes.md` without `name` was skipped, matching Claude Code's rule. The block above is a condensed, hand-merged
rendering of the `str()` output; the verifier re-ran the code and got the same values, printed one field per line.
The test file adds `maxTurns: 20` to the §3.6 example.)

### 5.6 btw tool extraction (`btw_tool_table.R`)

Static parse of `BTW/R/tool-*.R`, walking every call to `ellmer::tool`/`tool` and printing `name`, the first line of
`description`, and `names(arguments)`. Executed; 38 rows printed; summarised in §2.13. (Code: `parse()` each file,
recursive walker over calls, `data.frame` of results.)

### 5.7 Could not run

* No live model calls were made (not permitted for this track), so the claim that GPT-5.x models edit more reliably with
  `apply_patch` than with Pi-style `edit` is taken from vendor/opencode practice, **not measured** (UNCERTAIN).
* Windows behaviour of the prototypes (CRLF, drive-letter paths, `R_USER` home) was reasoned, not executed; the
  CRLF/mixed-ending fixtures passed on macOS.

---

## 6. CRAN and cross-platform considerations (Windows specifics)

1. **Encoding**: in this environment the locale is `C` (because `LANG` is unset in the shell, not because of
   `--vanilla`); unmarked UTF-8 read via `readBin`/
   `rawToChar` broke regex/`trimws` on multibyte text until marked with `Encoding(x) <- "UTF-8"` (fixture 019, VERIFIED).
   Always read files as bytes → validate → mark UTF-8 (or convert from the detected encoding, track 01), write with
   `writeBin(charToRaw(enc2utf8(x)))` (only after marking: `enc2utf8()` of an *unmarked* non-ASCII string in the C locale
   returns `<e2><80><94>`-style escape text) or `writeLines(useBytes = TRUE)`. Re-verified in the C locale (R 4.4.3):
   `writeLines()` **without** `useBytes` of a UTF-8-*marked* string wrote the escape text `<U+2014>` into the file, while
   `useBytes = TRUE` wrote the correct bytes `e2 80 94`. (The original draft said `<e2><80><94>`; that form comes from
   `enc2utf8()` on unmarked input, corrected.) Strip a BOM.
2. **Non-ASCII in package source**: R CMD check warns on non-ASCII characters in R code; use `\u` escapes (as in
   `ap_normalise`). The Write tool in this session turned `"\ufeff"` into a literal BOM in `instructions.R` — a reminder to
   lint for non-ASCII before building.
3. **Line endings**: preserve per-line terminators (Codex preserve mode passes CRLF and mixed fixtures); never normalise a
   Windows user's CRLF files to LF silently.
4. **Paths**: `normalizePath(winslash = "/")`; absolute-path detection must include `C:/` and `C:\`; R's `~` on Windows
   is `Documents` (`R_USER`), not the profile dir — btw searches both `fs::path_home_r()` and `fs::path_home()`
   (`BTW/R/btw-config.R:37-39`). Symlinks need admin/Developer Mode on Windows and Git checks them out as text unless
   `core.symlinks` — prefer `@AGENTS.md` imports over `CLAUDE.md → AGENTS.md` symlinks (Claude docs say the same,
   `CC/memory` 451-455).
5. **No POSIX shell**: `shell` is off by default; when on, use `processx`/`system2` and name the detected shell in the tool
   description; add Codex's Windows safety rules (§2.4) to the description on Windows.
6. **File-system policy**: tools write only inside the project or `tempdir()`; `.gptr/` only after consent (D-10); tests
   and examples use `tempdir()` (all prototypes do). Plan files → `.gptr/plans/`.
7. **RNG hygiene**: harness code must not change the user's `.Random.seed` (executed: `sample()` in a helper changed the
   next `runif()` value). Generate ids from `digest`/time/counters, or wrap in `withr::with_preserve_seed()`-style
   save/restore; use stride sampling in `r_inspect`.
8. **No `:::`**: help lookup uses only exported `utils::help`, `tools::Rd_db`, `tools::Rd2txt`; set
   `options(useFancyQuotes = FALSE)` locally for ASCII output.
9. **Timing**: `tools::Rd_db()` 0.1–1.0 s — cache per package in the session; `help.search()` first call ~1–1.3 s.
10. **yaml/TOML**: yaml is compiled but ubiquitous on CRAN binaries (Windows/macOS/Linux); no CRAN TOML parser is needed if
    only Codex agent files are read (subset reader).

---

## 7. Risks, pitfalls, open questions

**Risks / pitfalls**
* **Tool-surface drift**: Claude Code changed defaults twice in months (Glob/Grep removed on Unix; todo tools removed on new
  models; MultiEdit gone; TaskOutput removed). gptr should not hard-code "Claude-like" tool sets; keep the surface small and
  model-family-aware.
* **apply_patch is a training-distribution bet**: Codex offers *only* the freeform grammar tool; the freeform/grammar
  `custom` tool type exists only on the OpenAI Responses API. On Chat Completions/OpenAI-compatible endpoints the JSON
  `apply_patch(patch)` variant is an approximation (opencode uses a JSON `patchText` argument). Needs an eval.
* **Non-atomic semantics**: Codex leaves partial changes on failure; gptr's atomic default differs (documented, fixture 015).
* **Instruction injection**: project `AGENTS.md`/`CLAUDE.md` in a cloned repo can steer the agent. Codex skips project docs
  in untrusted projects; Posit Assistant requires workspace trust; Claude requires approval for external imports.
  gptr runs inside the user's own session, but `gptr()` in a freshly cloned repo should ask once before loading project
  instructions and never auto-approve anything based on them.
* **Sub-agent output as an injection vector**: adopt Claude's scanning (escape `<system-reminder>`-like tags, mark as
  sub-agent output without user authority).
* **`r_inspect` must be side-effect free**: `get0()` forces promises/active bindings (e.g. delayed data, `pins`); `str()`
  on some S4/R6 objects runs user methods; `object.size()` on huge nested lists can be slow — enforce time and size budgets
  and never call `print()` methods of unknown classes without a budget.
* **Help text size**: some Rd pages exceed 20 KB (e.g. `lm` 10.6 KB, ggplot2 pages larger); truncate with a pointer to
  sections.
* **Background sub-agents vs one R process**: inline agents share the session and cannot run truly in parallel (D-12);
  present them as foreground unless `worker`.

**Open questions**
1. Should gptr default `apply_patch` for GPT-5.x (opencode/Codex practice) or keep one `edit` for all models? Needs a
   small benchmark once providers exist (track on evals).
2. Name of the evaluation tool: `run_r` (track 01, btw) vs `r` (D-03 working name). Recommendation here: `run_r`
   (descriptive verb, matches btw's trained-on surface).
3. Should `r_inspect` be one tool with an `action` enum (recommended, one schema ≈200 tokens) or split into
   `inspect_objects` + `r_help` (Positron/btw style, clearer descriptions)?
4. Should gptr honour hooks defined for other harnesses (`.claude/settings.json`, `.codex/hooks.json`)? Probably not in
   v1 (trust model, shell dependence).
5. Should `.claude/agents/*.md` and `.codex/agents/*.toml` be *used* automatically or only listed by `gptr_agents()` for
   opt-in import?
6. Precedence when both `.gptr/vignette.Rmd` and `AGENTS.md` conflict: this report orders vignette first then AGENTS.md
   (closer files later = win, Codex rule). The maintainer may prefer vignette last (highest priority).
7. Is a `<proposed_plan>`-block convention (Codex) or a plan-file + approval tool (Claude) better for `mode = plan` in a
   console? Codex's is simpler (no tool) and fits `gptr("go ahead", mode = auto)`.

---

## 8. Sources

Claude Code (all fetched 2026-09-29; local copies in `.../work/track-20/verify/`):
* https://code.claude.com/docs/en/tools-reference.md
* https://code.claude.com/docs/en/agent-sdk/typescript.md (Tool Input/Output Types)
* https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts.md, /agent-sdk/agent-loop.md, /agent-sdk/user-input.md, /agent-sdk/todo-tracking.md, /agent-sdk/subagents.md
* https://code.claude.com/docs/en/sub-agents.md, /hooks.md, /memory.md, /context-window.md, /model-config.md, /permission-modes.md, /workflows.md, /goal.md, /checkpointing.md, /interactive-mode.md, /skills.md, /how-claude-code-works.md, /settings-reference.md, /claude-directory.md
* https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
* https://platform.claude.com/docs/en/agents-and-tools/tool-use/text-editor-tool.md
* `claude --help`, `claude --version` (executed)

Codex / OpenAI:
* https://github.com/openai/codex (commit 8ea2c0e0d4bc1261258eb532b5a9d616147b6571, 2026-09-30): `codex-rs/core/assets/tools/apply_patch.lark`, `codex-rs/core/src/tools/{spec_plan.rs,handlers/*_spec.rs,hosted_spec.rs}`, `codex-rs/apply-patch/src/*`, `codex-rs/apply-patch/tests/fixtures/scenarios/*`, `codex-rs/core/src/{agents_md.rs,config/mod.rs,context/*.rs}`, `codex-rs/protocol/src/{openai_models.rs,config_types.rs,prompts/base_instructions/default.md}`, `codex-rs/core/gpt-5.2-codex_prompt.md`, `codex-rs/prompts/templates/compact/*`, `codex-rs/collaboration-mode-templates/templates/{plan,default}.md`
* https://learn.chatgpt.com/docs/agent-configuration/subagents.md, /agent-configuration/agents-md.md, /hooks.md, /config-file/config-reference.md, /config-file/config-advanced.md, /customization/memories.md
* `codex --help`, `codex exec --help`, `codex features list`, `codex --version` (executed)
* https://developers.openai.com/api/docs/guides/tools-apply-patch.md ; https://developers.openai.com/api/docs/guides/tools-shell.md
* https://raw.githubusercontent.com/openai/openai-agents-python/main/src/agents/apply_diff.py

Other harnesses:
* https://agents.md/
* https://github.com/google-gemini/gemini-cli (38700b4b): `docs/tools/{file-system,shell,memory,planning,todos,ask-user}.md`, `docs/cli/gemini-md.md`
* https://opencode.ai/docs/tools/ ; https://github.com/anomalyco/opencode (2fa3363c) `packages/opencode/src/tool/registry.ts`
* https://aider.chat/docs/more/edit-formats.html ; https://github.com/Aider-AI/aider `aider/coders/__init__.py`, `aider/coders/patch_coder.py`, `aider/resources/model-settings.yml`
* https://goose-docs.ai/docs/mcp/developer-mcp/
* Pi: local clone `.../scratchpad/pi` (1b347794), `packages/coding-agent/src/core/tools/edit.ts`; track 01 report `/Users/wanjun/Desktop/gptr/dev/research/01-pi-builtin-tools.md`

R ecosystem:
* https://github.com/posit-dev/btw (a471e6de) `R/tool-*.R`, `R/btw-config.R`, `R/btw_client.R`; https://posit-dev.github.io/btw/reference/btw_tools.html
* https://github.com/posit-dev/positron tag `latest-daily-2026.06`, `extensions/positron-assistant/package.json`; https://positron.posit.co/assistant-chat-agents.html, /assistant-tips.html, /databot.html
* https://assistant.posit.co/docs/features/{permissions,context-management,memory,plan-mode,ask-mode}/ ; https://assistant.posit.co/docs/reference/config-file/
* https://opensource.posit.co/blog/2026-06-11_history-of-posit-data-science-agents
* https://posit-dev.github.io/mcptools/reference/server.html
* CRAN `available.packages()` (executed 2026-09-29)

---

## Verification log

Independent fact-check, 2026-09-29 (adversarial verifier, track 20). Method: fresh `curl` downloads of every cited doc
page (Claude Code, Codex/learn.chatgpt.com, OpenAI API guides, Anthropic text-editor tool, agents.md, Posit Assistant,
Posit blog, mcptools, Gemini CLI @38700b4b, opencode @2fa3363c, Aider main, Positron `latest-daily-2026.06`), compared
byte-for-byte with the author's copies where they existed (all identical); direct reading of the Codex clone at
`8ea2c0e0` and the Pi clone at `1b34779`; `codex features list`, `codex --version`, `claude --version`, `claude --help`
(executed locally, no model calls); CRAN `available.packages()` and the CRAN `btw_1.5.0.tar.gz` source (downloaded, not
installed); and every §5 prototype re-run with `Rscript --vanilla` from the code **as printed in this report**. Scratch
files: `.../scratchpad/work/verify-20/`.

| # | Claim (section) | Verdict | Source / evidence |
|---|---|---|---|
| 1 | Claude Code tools table lists 46 tools; `Glob`/`Grep` absent by default on macOS/Linux/WSL (§1.1, §2.2) | confirmed | `code.claude.com/docs/en/tools-reference.md` (46 table rows; Glob/Grep sections) |
| 2 | Todo/Task tools default only on Claude 3.x, Opus 4–4.7, Sonnet 4–4.6, Haiku 4.5; v2.1.268+; `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (§1.2, §2.2) | confirmed | tools-reference "Task tool availability" |
| 3 | Codex `update_plan` only when `[tools.update_plan] enabled = true` (`config/mod.rs:2717-2723`) | confirmed | `resolve_update_plan_enabled` uses `is_some_and(enabled)`; gate at `spec_plan.rs:1153` |
| 4 | Codex shell types `default`/`local`/`shell_command` are serde aliases of `UnifiedExec`; `ApplyPatchToolType` has only `Freeform` (`openai_models.rs:312-324`) | confirmed | `openai_models.rs:314-323` |
| 5 | `apply_patch.lark` grammar printed verbatim (§3.4); freeform tool description string (`apply_patch_spec.rs`) | confirmed | `diff` of report block vs `core/assets/tools/apply_patch.lark`: identical |
| 6 | `apply_patch` error strings and `Invalid patch hunk on line N:` / success summary format (§2.6) | confirmed (summary newline detail added) | `streaming_parser.rs`, `file_update.rs:110,211`, `lib.rs:375-385,483,862-877` |
| 7 | Fuzzy matcher: 4 passes (exact, rstrip, trim, Unicode-normalised) (§2.6) | confirmed | `seek_sequence.rs` |
| 8 | "EOF chunks try the end of file first" (§2.6 item 5) | corrected | `seek_sequence.rs:30-38`: EOF chunks are searched only at the end position, no fallback |
| 9 | R `apply_patch` port passes 25/25 Codex fixtures, 24/25 atomic; 50k-line file 0.41 s / 0.66 s (§1.4, §5.1) | confirmed | re-ran report code: identical table; bench 0.40–0.43 s / 0.67–0.68 s. Extra edge tests (heredoc, CRLF patch, add+update same file, pure insert, EOF anchor, delete+re-add) behaved as Codex |
| 10 | Codex constants: max threads 6, v2 concurrency 4, max depth 1, wait 30 s default / 10 s min / 3,600 s max (§1.8, §2.8) | confirmed | `config/mod.rs:256-266`, `multi_agents_common.rs:22-24` |
| 11 | Codex AGENTS.md: override > AGENTS.md > fallbacks, one file per dir, 32 KiB, separator `--- project-doc ---`, user-role fragment markers, untrusted projects skipped (§1.10, §3.8) | confirmed | `agents_md.rs:42-50,64,272-295`; `user_instructions.rs`; `config_toml.rs:75` |
| 12 | Codex compact prompt and summary prefix verbatim; auto-compact default 90 % (§3.9) | confirmed | `prompts/templates/compact/*.md` (diff identical); `openai_models.rs:457` |
| 13 | `request_user_input` Plan-mode only (§1.3, §1.14, §2.4) | corrected (nuance) | `tools/src/tool_config.rs:17-26`: Plan only by default; `default_mode_request_user_input` (under development, off) adds Default |
| 14 | `codex features list` stages (shell_tool, unified_exec, … apply_patch_freeform removed) (§2.4) | confirmed | executed `codex features list` (codex-cli 0.157.0) |
| 15 | Codex hooks: matcher aliases, `updatedInput.command`, `ask` unsupported, 2,500-token cap, hash trust; `notify` payload (§2.10) | confirmed | `learn.chatgpt.com/docs/hooks.md`, `config-file/config-advanced.md:680-720` |
| 16 | Claude hooks: 33 events, handler types, exit 2 = block, `permissionDecision` incl. `defer`, default timeouts 600/30/60 s (§2.10, §3.2) | confirmed | `hooks.md` (33 event rows, 428, 782-800, 1796-1801) |
| 17 | Hook `additionalContext` "capped at 10,000 chars" (§2.10) | corrected (clarified) | `hooks.md:923-930`: over-limit text goes to a file + 2,000-char preview |
| 18 | §3.7 hook stdin example "verbatim" | corrected | `hooks.md:760-778` also contains `scratchpad_dir`; added |
| 19 | Sub-agent frontmatter fields, depth 3 / 20 concurrent, filtered tools, background tool subset, model order (§2.8, §3.6) | confirmed | `sub-agents.md:300-319, 420-440, 1011-1044, 356-367` |
| 20 | Workflow limits 16 (1–256) / 4,096 / 1,000; "5 schema retries" (§2.8, §3.2) | corrected | `workflows.md:321,365-368`: "fails … after five attempts" (`MAX_STRUCTURED_OUTPUT_RETRIES`) |
| 21 | CLAUDE.md: AGENTS.md read only without CLAUDE.md (v2.1.277+), `@` imports ≤4 hops, 4 MiB, MEMORY.md 200 lines/25 KB, delivered as user message (§1.10, §2.9) | confirmed | `memory.md:102, 345-388, 529-533, 561` |
| 22 | Per-machine context not in system prompt (§2.3) | corrected (clarified) | `agent-sdk/modifying-system-prompts.md:206-212`: auto-memory location *is* in the preset system prompt by default |
| 23 | Claude Agent SDK input types (§3.1) and AskUserQuestion limits (1–4 q, header ≤12, 2–4 options) | confirmed | `agent-sdk/typescript.md:2842-3200`; `agent-sdk/user-input.md:546-555, 820` |
| 24 | OpenAI native `apply_patch` tool shapes and supported models GPT-5.5/5.4/5.2/5.1; local `shell` tool shapes (§2.6, §3.10) | confirmed (added: `delete_file` has no `diff`) | `developers.openai.com/api/docs/guides/tools-apply-patch.md`, `tools-shell.md:1511-1560, 1825-1848` |
| 25 | Anthropic `text_editor_20250728` / `str_replace_based_edit_tool`, commands view/str_replace/create/insert (§1.6) | confirmed | `platform.claude.com/.../text-editor-tool.md` |
| 26 | opencode gives `apply_patch` instead of `edit`/`write` to `gpt-` models (not `oss`, not `gpt-4`), arg `patchText` (§1.5, §2.6) | confirmed (added: provider-independent substring gate) | `registry.ts:297-300`, `apply_patch.ts:18-19` @2fa3363c (= current `dev`) |
| 27 | Pi has no `apply_patch`; Pi `edit` = `path`, `edits:[{oldText,newText}]`, returns a one-line message (§2.6, §4.3) | confirmed | Pi clone `1b34779`: no match in `packages/*/src`; `edit.ts:21-42, 202-209` |
| 28 | Aider model-settings counts (§2.6) | corrected (field attribution) | `model-settings.yml` (fresh): 138 is `editor_edit_format: editor-diff`, not `edit_format` |
| 29 | Gemini CLI tool parameters (`replace.instruction`, `ask_user` header ≤16, 1–4 questions, `write_todos` statuses, shell per OS) (§2.7) | confirmed | `gemini-cli@38700b4b docs/tools/*.md` |
| 30 | CRAN versions btw 1.5.0, mcptools 1.0.3, ellmer 0.5.0, gander 0.2.0, chores 0.3.1, shinychat 0.5.0, commons 0.1.0, evaluate 1.0.5, ragnar 0.3.1, vitals 0.4.0; ellmer 0.4.0 local; 613 installed (§2.1) | confirmed | `available.packages()` executed 2026-09-29 |
| 31 | btw 1.5.0 ships 38 tools; table signatures (§1.16, §2.13) | corrected (one signature) | CRAN tarball re-parse: 38 tools; `pkg_test(pkg, filter)` in 1.5.0 (`reporter` is dev-only) |
| 32 | btw `run_r` registered only via option/env var (§2.13) | corrected (incomplete) | `tool-run.R:318-338`, `tools.R:59-64`: also when tools are named explicitly; requires `evaluate` |
| 33 | btw `evaluate::evaluate(..., stop_on_error = 1, new_device = TRUE)`, 768 px plots, ragg; patch tool atomic, rejects pure inserts (§2.13, §2.6) | confirmed | `tool-run.R:123,145,232-237,311`; `tool-files-patch.R:9,52,250` |
| 34 | mcptools `mcp_server()` signature (§2.13) | corrected (exact signature) | pkgdown `reference/server.html` Usage block |
| 35 | Positron Assistant "deprecated June 2026" (§1.16, §2.13) | corrected (wording) | Posit blog 2026-06-11: "Succeeded by Posit Assistant (as of June 2026)" |
| 36 | Positron Assistant 13 tools and their parameters (§2.12, §2.13) | confirmed | `positron@latest-daily-2026.06 extensions/positron-assistant/package.json` (`contributes.languageModelTools`) |
| 37 | Posit Assistant: 30,000-token buffer, `/microcompact`, "names and types … (not their values)", `runtime.r.timeout` 30000, `.Renviron` blocked, Seatbelt/bubblewrap, memory files (§2.11, §2.13) | confirmed | `assistant.posit.co/docs/features/{context-management,permissions,memory}`, `reference/config-file` |
| 38 | Posit Ask mode keeps "Inspect your R/Python sessions" as precedent for `r_inspect` (§4.1) | corrected (qualified) | `features/ask-mode`: inspection = console history + plots only |
| 39 | Posit Plan-mode file location (§2.11) | corrected (qualified) | `features/plan-mode`: project dir only if it exists, else `~/.posit/assistant/plans/`; plan mode is advisory |
| 40 | agents.md stewarded by Agentic AI Foundation / Linux Foundation; "closest AGENTS.md wins; explicit user chat prompts override everything" (§1.10, §2.9) | confirmed | `https://agents.md/` (fresh) |
| 41 | C locale "because `LANG` is unset under `--vanilla`" (§5, §6.1) | corrected | executed: `Rscript` without `--vanilla` is also `C`; `LANG=en_US.UTF-8 Rscript --vanilla` → `en_US.UTF-8` |
| 42 | `writeLines()` without `useBytes` in C locale writes `<e2><80><94>` (§6.1) | corrected | executed: marked UTF-8 → `<U+2014>`; `<e2><80><94>` comes from `enc2utf8()` on unmarked input |
| 43 | `get0()` forces promises and active bindings; `exists()`/`bindingIsActive()` do not (§4.1, §7) | confirmed | executed `Rscript --vanilla` |
| 44 | `sample()` in a helper changes the next `runif()` (§6.7) | confirmed | executed |
| 45 | `utils::help(..., help_type="text")` returns `<lib>/<pkg>/help/<Rd>`; `Rd_db`/`Rd2txt` pipeline (§2.14, §5.2) | confirmed | executed; `help_text()` output matches §5.2 excerpt |
| 46 | Introspection timings (§1.17, §2.14, §5.2) | corrected (ranges) | re-run: `Rd_db` 0.09–0.37 s, `help.search` 1.33 s / 0.50 s, 139 hits for "linear model"; ranges now shown |
| 47 | §5.3 instruction discovery prototype runs and gives the printed output | confirmed, **bug fixed** | re-run identical; containment test `startsWith(target, root)` let `@../proj2/x.md` escape the project — fixed with `paste0(root, "/")`, re-run output unchanged, sibling import now skipped |
| 48 | §5.4 `notebook_edit` round-trip (`{}` vs `[]`, `execution_count: null`, insert/replace/delete) | confirmed | re-run of report code + extra delete/insert-at-start checks |
| 49 | §5.5 agent-definition reader output | confirmed (output block is condensed) | re-run; values identical |
| 50 | yaml is Imported by rmarkdown and knitr; yaml/jsonlite need compilation (§4.8, §6.10) | confirmed | `available.packages()` `Imports`/`NeedsCompilation` |
| 51 | Goose Developer tools incl. `tree`, `read_image`; modes Autonomous (default) / Manual / Smart / Chat only (§2.7) | confirmed | `goose-docs.ai/docs/mcp/developer-mcp/` (fresh) |
| 52 | Positron `executeCode` description quote "You prefer to show code over running it unless given an imperative" (§2.13) | confirmed | package.json @`latest-daily-2026.06` |

**Unverifiable / not re-checked here**: the claim that GPT-5.x models edit more reliably with `apply_patch` than with
Pi-style `edit` (already marked UNCERTAIN in §5.7); Windows behaviour of the prototypes; whether Claude Code's
`MultiEdit` was *removed* (it is absent from current docs and the changelog never mentions it, so "removed" is LIKELY,
not documented); Databot/Posit design history beyond the quoted blog lines; line-number citations were spot-checked,
not all re-verified.

**Overall**: no claim that an implementation plan would copy (endpoint shape, field name, constant, file path, function
signature) was found to be materially wrong except the items marked *corrected* above, all of which were fixed in place.
The one functional defect (sibling-directory import escaping the project check in §5.3) is fixed in the printed code.
