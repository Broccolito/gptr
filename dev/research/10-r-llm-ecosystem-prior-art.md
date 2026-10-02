# Track 10 — R LLM ecosystem prior art and build-vs-reuse

Date: 2026-09-29 (CRAN snapshots taken 2026-09-29/30 UTC). Author: research agent, track 10.
Scope: survey of every relevant R package (CRAN, r-universe, GitHub, Posit products), a deep
dive into ellmer / btw / mcptools, and four decisions for gptr: (1) is there already an
in-session R coding agent, (2) ellmer vs own provider layer, (3) CRAN status of `gptr`,
(4) exported-name collisions. Requirements are referenced as REQ-nn
(`dev/spec/00-vision-brief.md`) and decisions as S-n / D-nn (`dev/spec/01-decision-register.md`).

Evidence labels: **VERIFIED** = I saw the evidence myself (file:line, URL fetched, or command
executed with output shown); **LIKELY** = strong indirect evidence; **UNCERTAIN** = not
confirmed.

Prior work: an interrupted earlier researcher left scratch files in
`scratchpad/work/track10/` (tarballs, a CRAN db snapshot, four small scripts, no report). I
re-verified all of it: every tarball's MD5 matches the CRAN `MD5sum` field (section 5.1), the
CRAN database was re-downloaded, all scripts were re-run with the fresh database, and the
r-universe collision list was regenerated. Nothing from the earlier attempt is used unverified.

All local paths below are relative to
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track10/`
(call it `$T10`) unless absolute. Extracted CRAN sources live in `$T10/srcv/<pkg>/`.
A track-private library `$T10/rlib` holds btw 1.5.0, ellmer 0.5.0, mcptools 1.0.3 and their
missing dependencies (the user library was not touched; the system library has ellmer 0.4.0).

---

## 1. Executive summary

1. **gptr is not the first in-session R coding agent.** At least four CRAN packages already
   give an LLM a live R session plus file/grep/edit tools and an agent loop:
   **corteza 0.7.1** (cornball.ai; `chat()` REPL, `tool_run_r`, `tool_read_file`,
   `tool_write_file`, `tool_replace_in_file`, `tool_grep_files`, `tool_bash`, sub-agents via
   `callr`, plan mode, permissions, MCP server `serve()`), **btw 1.5.0 + ellmer** (Posit;
   `btw_client()`/`btw_app()`, 30 tools incl. files edit/patch/replace/search, opt-in
   `btw_tool_run_r`, sub-agents, skills, `btw.md`), **agenticr 0.3.3** (console agent that
   routes natural language typed at the R prompt to an agent; evaluates in `.GlobalEnv`), and
   **aisdk 1.4.12** (YuLab-SMU; `console_chat()`, but code execution in a `callr`
   subprocess). Non-CRAN: **side** (Posit, experimental, "will not go to CRAN"), **ClaudeR**
   (GitHub; Python MCP bridge). Proprietary: **Posit Assistant** (RStudio/Positron/terminal,
   from $20/month) which superseded Positron Assistant and Databot. VERIFIED.
2. **What gptr adds that none of them has** (VERIFIED by reading their code): a single
   gateway function that is also a value inside `if`/`for`/pipes; System 1 typed decisions
   with probabilities (Jev) — nobody integrates Jev; the runnable script/Rmd/qmd/ipynb as
   harness *and* replayable history; evaluation in the caller's frame (`parent.frame()`)
   instead of a hard-coded global environment (btw, corteza, agenticr all hard-code
   `globalenv()`); Pi-v3-compatible (id/parentId tree) sessions and Pi extensions;
   subscription plans through the official CLIs (ToS-compliant, see item 12).
   *Verifier correction:* corteza does claim a Pi-style session file ("matches openclaw /
   pi-coding-agent", `srcv/corteza/R/session.R:2-11`), but it writes a `"version":2` header
   followed by flat Pi-shaped message objects with no entry `id`/`parentId` tree (Pi's current
   `CURRENT_SESSION_VERSION = 3`, `pi/packages/coding-agent/src/core/session-manager.ts:41`), and
   has no Pi extension support — so "first with Pi-*compatible* sessions" must not be claimed;
   "Pi v3 tree sessions + extensions" is the defensible differentiator.
3. **Recommendation for D-01: implement gptr's own thin provider layer; do not Import
   ellmer.** Offer ellmer strictly as an optional bridge (`Suggests: ellmer (>= 0.5.0)`) so
   that any ellmer `Chat` (Bedrock, Vertex, Azure, Databricks, Snowflake, Posit, Portkey, …)
   can be passed as `model =`. Reasons, verified below unless marked: ellmer's provider
   generics are not exported and changed signature between 0.4.0 and 0.5.0; ellmer's tool loop
   cannot be stepped from outside (prototype); no subscription/CLI/System-1 providers; its
   streaming uses `httr2::req_perform_connection` (source verified; the interrupt pitfalls are a
   track-02 finding, not re-verified here); API churn in every minor release; the maintainer
   wants routing implemented in gptr (D-01).
4. **The dependency-weight argument against ellmer is weaker than assumed**: ellmer's hard
   closure is 25 packages besides ellmer itself (16 compiled) vs 16 packages in total for
   `{httr2, jsonlite, cli, processx}` (the four themselves + 12 transitive; 12 compiled);
   namespace load time 0.15 s vs 0.12 s for httr2 alone (re-run under concurrent load: 0.22–0.25 s
   vs 0.19–0.22 s; the ratio holds, absolute times are machine-load dependent). The decisive arguments are control
   and stability, not size. btw is the heavy one (70 packages, 41 compiled, two of them need a
   Rust toolchain from source). VERIFIED (section 5.6/5.7).
5. **Prototype result (VERIFIED, offline mock server):** a "single-step" ellmer bridge in
   which gptr owns the loop is **not possible cleanly with exported API**: when a `Chat`
   whose last turn contains tool requests is called again, ellmer's private
   `complete_dangling_tool_requests()` (`srcv/ellmer/R/chat.R:1279-1300`) injects an error
   result "Chat ended before the tool could be invoked." *in addition to* the caller's result
   (observed on the wire in 0.4.0 and 0.5.0). The **"delegate" bridge works**: ellmer runs
   its loop, every tool call is routed through a gptr executor (permission check in
   `on_tool_request` + `tool_reject()`, execution in the caller's environment, events via
   `on_tool_result`, turn budget via a classed condition), and the resulting Turns are
   translated back to gptr messages. Tested on ellmer 0.4.0 and 0.5.0.
6. **Found an ellmer 0.4.0 wire bug** (VERIFIED on the wire): OpenAI-compatible providers
   replay tool-call arguments as `{"code":["..."]}` (scalars boxed into arrays) because
   `as_json(ProviderOpenAICompatible, ContentToolRequest)` used `jsonlite::toJSON()` without
   `auto_unbox`; 0.5.0 fixes it (`srcv/ellmer/R/provider-openai-compatible.R:549`,
   `utils.R:347-349`). Illustrates that gptr would inherit wire-format bugs it cannot fix.
7. **gptr on CRAN (VERIFIED):** version 0.7.0, Date/Publication 2025-04-05 11:20:14 UTC,
   Imports jsonlite + RCurl, exports `get_response()` and `dataframe_to_text()`, **no reverse
   dependencies of any kind**, all 13 CRAN check flavours OK (2026-09-30), not archived;
   archive holds 0.5.0 (2024-05-06) and 0.6.0 (2024-05-07); 302 downloads in the last month
   (RStudio mirror), 11,125 since 2024-05-01. A total API break needs no CRAN coordination
   (the policy's reverse-dependency clause does not apply); ship it as **gptr 1.0.0**.
8. **Name collisions (VERIFIED over 613 installed packages, 37 LLM tarballs and the
   r-universe exports index):** `gptr` and every `gptr_*` name are free. Unsafe to export:
   `plan` (future, SeuratObject), `prompt` and `history` (utils — base R!), `tool` (ellmer,
   aisdk, mcplite), `chat` (ellmer, corteza, llm.api, tidyllm, rollama, gptstudio), `agent`
   (llm.api, LLMRagent), `classify` (terra, admisc), `decide` (nimble), `ask` (gtools),
   `extract` (magrittr, tidyr), `pick` (dplyr), `session` (rvest), `config` (httr, plotly),
   `setup` (testthat), `score`/`rank` (BiocGenerics). Bare-identifier hazards for NSE:
   `claude`, `gemini`, `chatgpt`, `openai`, `ollama`, `groq`, `mistral`, `deepseek` are
   functions in **tidyllm**; `codex` and `claude_code` are functions in **vitals**; `plan`
   is `future::plan` — so `mode = plan`, `model = codex`, `model = openai` must be captured
   with `substitute()` and never evaluated first.
9. **How ecosystem packages describe R objects (VERIFIED by running them):**
   `ellmer::df_schema()` = one line per column (type, range, NAs, unique values), 0.22 s on a
   2e6×5 data frame; `btw::btw_this()` = markdown table for ≤10 cols × ≤30 rows, otherwise a
   `skimr` JSON summary (2.5 s on the same frame), `print()` capture for everything else,
   `btw()` / `btw_this(<env>)` = "## Context" markdown with one fenced block per object.
   mcptools does not describe objects at all — it serves whatever ellmer tools it is given
   (normally `btw_tools()`). A bounded-cost sampling describer prototype took 0.078 s.
   (Verifier re-run: btw 3.75 s, df_schema 0.28 s, prototype 0.077 s under concurrent machine
   load — treat btw as "2.5–3.7 s".)
10. **btw's full toolset costs ~46k characters (≈11.6k tokens by chars/4) of tool schema per
    request** (31 tools); `btw_tool_run_r` alone is 2.7k chars. Supports REQ-10's minimal
    surface. VERIFIED (section 5.5).
11. **mcptools is the reference design for "external agent reaches the live R session"**
    (Claude Code → `Rscript -e "mcptools::mcp_server()"` → per-user IPC socket →
    `mcp_session()` in the interactive session, serviced by `promises`/`later` when the
    console is idle). gptr-as-MCP-server (D-14) can reuse the pattern but should not Import
    mcptools (ellmer + nanonext + httpuv + processx + openssl…, 31 packages).
12. **Subscription OAuth prior art exists but must not be copied for Claude:** `llm.api`
    (CRAN) + `tinyoauth` implement Claude-plan OAuth (`Authorization: Bearer` +
    `anthropic-beta: oauth-2025-04-20`) and ChatGPT-plan Codex OAuth. Anthropic's current
    Claude Code legal page states developers may not "route requests through Free, Pro, or
    Max plan credentials on behalf of their users" and must not "collect, store, or
    intermediate Claude.ai credentials" — confirming D-15 (drive the unmodified `claude`
    binary). `ravel` shows the CLI pattern: `codex exec --skip-git-repo-check --ephemeral
    --sandbox read-only --output-last-message <file> -` via `system2()`. VERIFIED.
13. **Useful conventions to be compatible with (VERIFIED):** R packages ship skills in
    `inst/skills/<name>/SKILL.md` (btw, commons); btw reads project `.btw/skills` or
    `.agents/skills`, user `~/.btw/skills`, and agents from `.claude/agents/`
    (`srcv/btw/R/tool-skills.R:28`, `R/btw-config.R:53`); commons tells users to copy skills to `.agents/skills` (Posit
    Assistant, Codex) or `.claude/skills` (Claude Code); mcptools' client config is
    `~/.config/mcptools/config.json` in Claude-Desktop `mcpServers` shape; ellmer's price
    table comes from litellm and is cached under `tools::R_user_dir("ellmer","cache")`.
14. **Evidence that such a package can pass CRAN**: corteza (bash/file/R tools, sub-agents,
    writes to `R_user_dir`) and ellmer both pass all 13 CRAN flavours incl. Windows. querychat
    (Posit) was **archived 2026-09-27** "as issues were not corrected in time" — even
    well-resourced LLM packages get archived; keep tests offline and robust. VERIFIED.
15. **Offer interop in both directions cheaply** (prototyped): (a) `model = <ellmer Chat>`
    via the delegate bridge; (b) import any ellmer `ToolDef` (e.g. `btw::btw_tools("docs")`)
    as a gptr tool using only exported S7 properties — verified by running
    `btw_tool_docs_help_page` through a gptr-style registry; (c) optionally export gptr's
    tools as ellmer `ToolDef`s so btw_app/shinychat/mcptools users can use them.

---

## 2. Findings

### 2.1 Method and evidence base

- CRAN package database: `tools::CRAN_package_db()` re-downloaded (25,273 rows = 25,258
  unique packages after dropping duplicate rows; newest publication 2026-09-30) →
  `$T10/cran_db2.rds`. VERIFIED (executed; output in 5.1; verifier re-download identical counts).
- CRAN archive index `https://cran.r-project.org/src/contrib/Meta/archive.rds` → `$T10/archive.rds`.
- 37 CRAN source tarballs in `$T10/src/`, MD5-verified against CRAN and re-extracted to
  `$T10/srcv/`.
- A case-insensitive Perl regex over Title+Description of all CRAN packages
  (`large language model|\bLLM|\bGPT\b|ChatGPT|OpenAI|Anthropic|Claude|Gemini|Ollama|Model
  Context Protocol|\bMCP\b|AI agent|coding agent|agentic|AI assistant|chatbot|generative AI`;
  the word boundaries matter — without them the same search gives 261 hits) gave 184
  hits (some false positives such as MCP-penalty regression packages). Full list in
  `$T10/cran_search.out`. VERIFIED.
- Web: CRAN pages, CRAN checks, crandb, cranlogs API, r-universe search API, Posit docs/blogs,
  GitHub READMEs, Anthropic's Claude Code legal page.
- Experiments: R 4.4.3, `Rscript --vanilla`, macOS arm64. No paid API calls: all LLM traffic
  went to a local mock OpenAI-compatible server (`httpuv` in a `callr::r_bg` process).

### 2.2 Landscape table (CRAN metadata VERIFIED from `cran_db2.rds`; "deps" = recursive hard
dependencies Depends+Imports+LinkingTo excluding base packages and the package itself;
"comp" = how many of those need compilation)

| Package | Version (published) | Licence | deps/comp | What it is | Maturity | Lesson for gptr |
|---|---|---|---|---|---|---|
| **ellmer** | 0.5.0 (2026-09-04) | MIT | 25/16 | Posit's multi-provider chat: `Chat` R6, S7 Provider/Model/Turn/Content, tools, structured output, streaming, async, parallel & batch | 11 CRAN releases since 2025-01; 13.8k downloads/month; used by 24 packages via Imports | The de-facto R standard; bridge to it, don't build on it (2.8) |
| **btw** | 1.5.0 (2026-09-09) | MIT | 70/41 | Posit toolkit: describe objects/docs for LLMs (`btw()`, `btw_this()`), 30 ellmer tools, `btw_client()`, `btw_app()`, skills, sub-agents, `btw.md`, MCP server wrapper, Rapp CLI | 7 releases since 2025-11 | Closest Posit analogue of gptr's tool layer; copy the ideas (hash-anchored edits, cwd restriction, skill discovery), not the dependency |
| **mcptools** | 1.0.3 (2026-09-18) | MIT | 31/21 | R as MCP server (`mcp_server()`), live-session bridge (`mcp_session()`), MCP client returning ellmer tools (`mcp_tools()`) | 8 releases since 2025-07; formerly "acquaint" | Reference design for D-14; own client/server in gptr (report 06) |
| shinychat | 0.5.0 (2026-09-09) | MIT | 43/27 | Shiny chat UI for ellmer; history stores; slash commands | active | Possible artifact/chat UI in Suggests; not needed for console |
| querychat | archived 2026-09-27 | not checked | — | Natural-language → SQL filtering for Shiny/data frames | 0.2.0–0.4.0 then archived "issues were not corrected in time" | Even Posit LLM packages get archived; CRAN hygiene matters |
| vitals | 0.4.0 (2026-09-02) | MIT | 35/22 | LLM evaluation (Inspect port); exports `claude_code()`, `codex()` solvers (Docker + Python Inspect) | active | NSE hazard: `codex`, `claude_code` symbols |
| ragnar | 0.3.1 (2026-09-10) | MIT | 48/30 | RAG: read_as_markdown, chunking, DuckDB store, retrieval tool | active | Out of scope for core; possible skill/plugin |
| chores | 0.3.1 (2026-03-04) | MIT | 46/27 | RStudio addin "helpers" rewriting selections via ellmer | stable | Editor-selection UX; not agentic |
| gander | 0.2.0 (2026-03-08) | MIT | 48/29 | Addin: chat that sees selection + env; inlines results via streamy | stable | Uses treesitter for context; not agentic |
| streamy | 0.2.1 (2025-12-09) | MIT | 5/2 | Streams coro generator output into the editor (rstudioapi) | small | Pattern for REQ-25 live document writing in RStudio |
| chattr | 0.3.1 (2025-08-18) | MIT | 50/31 | mlverse RStudio chat app over ellmer | maintenance | — |
| gptstudio | 0.4.0 (2024-05-21) | MIT | 63/33 | RStudio addins/chat app, multi-provider | stale on CRAN since 2024 | Heavy UI stack ages badly |
| tidyllm | 0.6.0 (2026-09-08) | MIT | 32/22 | Pipe-based multi-provider API (`claude()`, `openai()`, …), batch, `chat_ellmer()` backend | active | Its ellmer backend refuses tidyllm tools — same loop-ownership wall (2.8.4); NSE hazard `claude`, `gemini` |
| rollama | 0.3.1 (2026-08-24) | GPL-3 | 27/17 | Ollama client; exports `chat`, `type_*` | active | `type_*` names now used by 3 packages |
| openai | 0.4.1 (2023-03-15) | MIT | 14/10 | Legacy OpenAI wrapper (httr) | abandoned | — |
| **aisdk** | 1.4.12 (2026-06-02) | MIT | 24/17 | "Vercel AI SDK for R": providers, Agent/Session R6, skills, hooks, MCP, sandbox, `console_chat()`; 215 exports, 42k lines | very active; 17k downloads/month | Breadth ≠ focus; its `r_eval` runs in a `callr` subprocess (not in-memory) |
| mall | 0.2.0 (2025-08-18) | MIT | 33/20 | Row-wise LLM ops on data frames (`llm_classify`, `llm_verify` → factor 1/0, caching) | stable | Vectorised typed outputs, but no probabilities (REQ-20 goes further) |
| kuzco | 0.1.0 (2026-01-26) | MIT | 91/45 | Computer vision with LLMs via ellmer/ollamar | early | — |
| **corteza** | 0.7.1 (2026-08-05) | Apache-2 | 13/5 | "AI Agent Runtime": live-session agent, CLI, console REPL `chat()`, MCP server `serve()`, handles for large results, provenance, sub-agents (callr), plan mode, permissions, skills, Matrix bot | 4 CRAN releases in 2026 | Closest functional competitor; lessons on handles, globalenv writes, Windows bash |
| **llm.api** | 0.1.9 (2026-08-04) | MIT | 4/3 | Minimal-deps provider layer (curl+jsonlite+tinyoauth) + `agent()` loop + MCP client; Anthropic, OpenAI, Moonshot, Ollama, OpenAI-compatible, **Claude and Codex subscription OAuth** | 6 releases in 2026 | Proves a thin provider layer is ~3.5k lines; its Claude OAuth route conflicts with Anthropic terms |
| tinyoauth | 0.1.1 (2026-06-24) | MIT | 3/3 | OAuth2 client incl. Claude-Code and Codex routes; caches in `R_user_dir` | new | Do not reuse for Claude (ToS) |
| saber / pensar | 0.7.2 / 0.7.0 | Apache-2 | 0/0, 4/4 | Context engineering (AGENTS.md/CLAUDE.md assembly, AST symbol index) / LLM wiki engine | new | Context-file conventions |
| **agenticr** | 0.3.3 (2026-07-28) | MIT | 12/10 | Console agent: NL or R at the same prompt, `options(error=)` interceptor, tools `execute_r_code`, `read_file`, `grep_search`, `list_files`, `file_edit`, `file_write`, tasks, skills, MCP | first CRAN release | Validates "agent at the R prompt" UX; evaluates in `.GlobalEnv` |
| ravel | 0.1.4 (2026-08-03) | MIT | 42/26 | RStudio copilot; stages actions for approval; providers via API or **CLIs** (Codex, Copilot, Gemini) | new | Concrete `codex exec` invocation (3.9) |
| myownrobs | 1.0.0 (2026-01-22) | MIT | 55/33 | RStudio-extension coding agent over ellmer | new | — |
| codriver | 1.0.0 (2026-08-08) | MIT | 39/23 | In-editor generate/complete/edit via ellmer | new | — |
| rtemis.llm | 0.8.7 (2026-09-24) | GPL-3 | 21/15 | S7 LLM/Agent objects, `logprobs()`/`token_probs()` | active | Log-prob probabilities = emulated System 1 option |
| commons | 0.1.0 (2026-09-11) | MIT | 89/52 | Posit "trustworthy data agents" with measures/semantic layer; ships an agent skill | experimental | Skill-distribution convention (`inst/skills`, `.agents/skills`) |
| mini007 | 0.4.0 (2026-05-27) | MIT | 78/43 | R6 multi-agent orchestration over ellmer | small | — |
| LLMR / LLMRagent | 0.8.11 / 0.8.1 | MIT | 38/23, 39/23 | Research-grade LLM calls, `llm_mutate`, logprobs; governed agents, workflows | active | `agent()` name taken; logprobs prior art |
| tidyprompt | 0.4.0 (2026-04-21) | GPL-3 | 24/16 | Prompt wraps (`answer_as_boolean`, …), `llm_provider_ellmer()` bridge | active | Its bridge needs version shims for ellmer classes (2.8.4) |
| llmflow | 3.0.2 (2026-01-31) | GPL-3 | 12/8 | ReAct loop generating & running R code via callr | small | — |
| harness | 0.2.0 (2026-08-24) | MIT | 2/2 | Launches external coding agents with curated skills; no loop | new | — |
| wf | 0.0.1 (2026-03-19) | MIT | 19/12 | Skill installer/lockfile | new | — |
| mcplite | 0.1.0 (2026-08-03) | MIT | 3/2 | Minimal stdio MCP server; re-implements `tool()`/`type_*()` ellmer-compatibly | new | ellmer's tool DSL is becoming a de-facto standard |
| LLMAgentR | 0.3.2 | MIT | 206/104 | Graph agents for forecasting/ML | — | Dependency explosion warning |
| llamaR | 0.2.6 | MIT | 4/2 | llama.cpp bindings | — | Local models without HTTP |
| gemini.R, ollamar, chatLLM, PacketLLM, chatAI4R | various | MIT/Artistic | 8–73 | single-provider or addin clients | — | — |
| **side** (GitHub) | — | MIT | — | Posit experimental RStudio-sidebar coding agent built on ellmer+btw+shinychat; "will not go to CRAN" | experimental | Posit's own prototype of an R-implemented agent |
| **ClaudeR** (GitHub) | — | MIT | — | RStudio addin + httpuv server (port 8787) + Python MCP bridge (`uvx clauder-mcp`), 41 tools | active | Python dependency; not CRAN |
| mcpr (GitHub/r-universe, devOpifex) | — | — | — | MCP server/client in R (John Coene) | r-universe only | — |
| claudeR | not on CRAN, never archived | — | — | (name used by several GitHub projects) | — | — |
| acquaint | — | — | — | pre-release name of mcptools (NEWS.md:162) | renamed | — |
| Positron Assistant / Databot / **Posit Assistant** | proprietary | — | — | IDE agents with live-session access; Posit Assistant (Apr 2026 RStudio, Jun 2026 Positron, also terminal) superseded both | commercial ($20/month base, BYO key possible) | The main commercial competitor; gptr is the open, in-console, scriptable alternative |

Sources for the non-CRAN rows are in section 8.

### 2.3 Critical question 1 — is there already an in-session R coding agent?

**Yes (VERIFIED).** Evidence per package:

**corteza 0.7.1** (`srcv/corteza`, 20,290 lines of R):
- `chat()` "Run a conversational agent inside your R session. Tools execute as direct
  function calls, no MCP server needed." (`R/chat.R:139-140`); refuses to run
  non-interactively (`R/chat.R:176-178`); `max_turns` default 50 via
  `getOption("corteza.max_turns")` (`R/chat.R:187-189`).
- Exported tools include `tool_run_r`, `tool_run_r_script`, `tool_read_file`,
  `tool_write_file`, `tool_replace_in_file`, `tool_grep_files`, `tool_list_files`,
  `tool_bash`, `tool_cmd`, `tool_git_*`, `tool_spawn_subagent`, `tool_exit_plan_mode`,
  `tool_web_search`, `tool_fetch_url`, `tool_r_help` (NAMESPACE).
- `tool_run_r()` snapshots `ls(globalenv())`, evaluates in `handle_eval_env(parent =
  globalenv())`, stashes large visible results as handles `.h_NNN` with a `str()` summary,
  and records provenance of new global bindings (`R/tool-impl.R:431-481`,
  `R/handles.R:1-140`). Comment at `R/handles.R` (handle_eval_env docs) records that an
  earlier version evaluating in a *child* environment "silently broke `<-` persistence".
- Sub-agents are `callr::r_session` children (`R/subagent.R:3`, `:542`); sessions are JSONL
  under `tools::R_user_dir("corteza","data")/agents/main/sessions/{id}.jsonl`
  (`R/session.R:6-7`), declared "openclaw / pi-coding-agent" compatible: line 1
  `{"type":"session","version":2,"id",...,"cwd"}`, then bare Pi-shaped messages (`role`,
  `content`, `stopReason`, `api`, `provider`, `model`, `usage`, `timestamp`) without Pi's
  `type`/`id`/`parentId` entry wrapper (`R/session.R:8-14, 393-458`; not tested against Pi); permissions/deny lists/plan mode (`R/permissions.R`,
  `R/plan-mode.R`, `R/policy.R`).
- On Windows it resolves `bash` explicitly, preferring Rtools, then Git for Windows, because
  `C:\Windows\System32\bash.exe` is the WSL stub (`R/tool-impl.R:569-575`).

**btw 1.5.0 + ellmer** (`srcv/btw`):
- `btw_client()` returns an ellmer `Chat` with btw's system prompt, tools, skills and project
  context (`R/btw_client.R:129-189`); chat in the console through `ellmer::live_console()` or
  in Shiny through `btw_app()`.
- Default registry = 30 tools (VERIFIED by running `btw_tools()`, section 5.5):
  `btw_tool_agent_subagent, btw_tool_cran_search, btw_tool_cran_versions,
  btw_tool_cran_package, btw_tool_docs_package_news, btw_tool_docs_package_help_topics,
  btw_tool_docs_help_page, btw_tool_docs_available_vignettes, btw_tool_docs_vignette,
  btw_tool_env_describe_data_frame, btw_tool_env_describe_environment, btw_tool_files_edit,
  btw_tool_files_list, btw_tool_files_patch, btw_tool_files_read, btw_tool_files_replace,
  btw_tool_files_search, btw_tool_files_write, btw_tool_github,
  btw_tool_ide_read_current_editor, btw_tool_pkg_coverage, btw_tool_pkg_document,
  btw_tool_pkg_check, btw_tool_pkg_test, btw_tool_pkg_load_all,
  btw_tool_sessioninfo_is_package_installed, btw_tool_sessioninfo_platform,
  btw_tool_sessioninfo_package, btw_tool_skill, btw_tool_web_read_url`.
- `btw_tool_run_r` is **opt-in**: registered only when `options(btw.run_r.enabled = TRUE)`,
  env `BTW_RUN_R_ENABLED=true|1`, or the "run" group is requested explicitly
  (`R/tool-run.R`, function `btw_run_r_tool_is_enabled`). It evaluates with
  `evaluate::evaluate(code, envir = global_env(), stop_on_error = 1, new_device = TRUE)`,
  restores wd/options/envvars after each call (`withr::local_dir/local_options/
  local_envvar`), captures text/messages/warnings/errors/plots (plots replayed to a PNG via
  `ragg::agg_png` or `grDevices::png`) (`R/tool-run.R`, `btw_tool_run_r_impl`). The tool
  description tells the model the code "runs in a global environment" and must not write
  files, run shell, use network or install packages unless explicitly asked.
- File tools refuse paths outside the working directory: `check_path_within_current_wd()`
  (`R/tool-files-read.R:338-341`), used by read/list/edit/patch.
- `btw_tool_files_edit()` uses line-hash anchors (`2:f1a|  return("world")`) and rejects
  stale edits; `btw_tool_files_patch()` applies multi-file patch envelopes atomically
  (NEWS 1.2.0, 1.3.0).
- No permission modes beyond opt-in run_r and an editor-read `consent` flag (grep of
  `consent|askYesNo|approve|permission` in `R/`).

**agenticr 0.3.3** (`srcv/agenticr`): tools `execute_r_code, get_dataframe_info,
search_variables, read_file, get_function_source, get_function_help, grep_search,
list_files, file_edit, file_write, install_package, task_list, task_write, task_update,
load_skill_body, memory_write, create_skill, append_skill_memory` (`R/tools.R:12-427`);
evaluates `eval(expr, envir = .GlobalEnv)` (`R/tools.R:564`); `agentic_enable()` (opt-in)
installs an `options(error=)` interceptor so natural language typed at the normal prompt
reaches the agent (`R/repl.R:1278-1330`; line 1346 is the restore in `agentic_disable()`;
README "Error interceptor — works in standard R console").

**aisdk 1.4.12**: `console_chat()` (`R/console.R:101-115`), but its `r_eval` tool "run[s] R
code in an isolated subprocess" via `callr::r_bg()` (`R/r_introspect_tools.R:13, 204-215,
351`); introspection tools read `.GlobalEnv` read-only (`R/r_context_tools.R`). So aisdk is
*not* in-memory compute in the REQ-21/22 sense. LIKELY (did not read all 42k lines).

**How gptr differs** (requirement-by-requirement; VERIFIED absence by reading exports/code of
corteza, btw, agenticr, aisdk, llm.api):

| Capability | corteza | btw+ellmer | agenticr | aisdk | gptr target |
|---|---|---|---|---|---|
| Single function usable as value in `if`/pipe (REQ-17/18/20) | no (`chat()` is a REPL, `turn()` internal-ish) | `chat$chat()` returns string | no | `generate_text()` | `gptr()` returns typed values / results |
| System 1 typed decisions with probabilities (REQ-13/20) | no | no | no | no | Jev + emulation |
| Script/Rmd/qmd/ipynb as harness and replayable history (REQ-24–26) | JSONL transcript only | chat history DB (RSQLite) | per-session history | session store | yes (D-08) |
| Evaluation env | `globalenv()` | `global_env()` (hard-coded) | `.GlobalEnv` | subprocess | `parent.frame()` / explicit `envir` (D-04) |
| Subscription plans | via llm.api OAuth (Codex, Claude) | Posit OAuth only | no | no | official CLIs (D-15) |
| Permission modes (REQ-37) | yes (dangerous tools, deny paths, plan mode) | opt-in run_r only | ? | hooks, sandbox modes | manual/edits/auto/plan |
| Pi session/extension compatibility | partial claim: "pi-coding-agent/openclaw" JSONL (v2 header, flat messages, no tree); no extensions | no | no | no | yes (v3 tree + extensions) |
| Shiny artifacts (REQ-39) | no | btw_app is a chat UI, not artifacts | no | no | yes |
| Hard deps | 13 | 70 (btw) | 12 | 24 | target ≤ ~5–16 |

### 2.4 ellmer deep dive (source: `srcv/ellmer`, 0.5.0; runtime checks on 0.4.0 and 0.5.0)

**Package facts** (VERIFIED `srcv/ellmer/DESCRIPTION`): Depends R (>= 4.1); Imports cli, coro
(>= 1.1.0), glue, httr2 (>= 1.2.3), jsonlite, later (>= 1.4.0), lifecycle, promises
(>= 1.5.0), R6, rlang (>= 1.3.0), S7 (>= 0.2.0), tibble, vctrs; Suggests connectcreds, curl,
gargle, jose, knitr, magick, openssl, otel, otelsdk, paws.common, png, rmarkdown, shiny,
shinychat (>= 0.3.0), testthat, vcr (>= 2.0.0), withr. 20,255 lines of R. 130 exports.
Authors: Hadley Wickham (cre), Joe Cheng, Aaron Jacobs, Garrick Aden-Buie, Barret Schloerke.

**Object model.**
- `Chat` is an **R6** class (`R/chat.R:24`). Private state: `provider`, `model`, `.turns`,
  `echo`, `.conversation_id`, `tools`, four `CallbackManager`s (`R/chat.R:735-746`). Public
  methods (VERIFIED in `R/chat.R`): `get_turns(include_system_prompt)`, `set_turns(value)`,
  `get_rounds()`, `last_round()`, `add_turn(user, assistant, log_tokens)`,
  `get_system_prompt()`, `get_model()`, `get_model_object()`, `set_model(model)`,
  `set_system_prompt(value)`, `get_tokens()`, `get_cost(include = c("all","last"))`,
  `token_count(..., include = c("new","complete"), type)`, `file_upload/list/get/download/
  delete`, `last_turn(role)`, `chat(..., echo)`, `chat_structured(..., type, echo, convert)`,
  `chat_structured_async()`, `chat_async(..., tool_mode = c("concurrent","sequential"))`,
  `stream(..., type, stream = c("text","content"), controller)`, `stream_async(...)`,
  `register_tool(tool)`, `register_tools(tools)`, `get_provider()`, `get_tools()`,
  `set_tools(tools)`, `on_tool_request(cb)`, `on_tool_result(cb)`,
  `on_request_start(cb)` and `on_request_end(cb)` (new in 0.5.0), active field
  `conversation_id`.
- `Provider` is an **S7** class with properties `name`, `base_url`, `extra_headers`,
  `credentials` (function or NULL) and deprecated `model/params/extra_args`
  (`R/provider.R:30-42`). 0.5.0 split model configuration into a new `Model` class (NEWS 0.5.0).
- Provider behaviour is a set of **S7 generics that are not exported**: `base_request`,
  `base_request_error`, `chat_request`, `chat_body`, `chat_body_tools`, `chat_path`,
  `chat_resp_stream`, `chat_params`, `stream_parse`, `stream_content`,
  `stream_content_with_turns`, `stream_merge_chunks`, `value_turn`,
  `value_turn_with_turns`, `value_tokens`, `value_finish_reason`, `as_json`,
  `count_tokens`, `models_list`, `has_batch_support`, `batch_submit`, `batch_poll`,
  `batch_status`, `batch_retrieve`, `batch_result_turn` (`R/provider.R:66-423`; NAMESPACE
  exports the `Provider` and `Model` classes but none of these generics). VERIFIED.
- Their signatures changed between minor versions (VERIFIED by `formals()` on both
  installs): 0.4.0 `chat_body(provider, stream, turns, tools, type)` → 0.5.0
  `chat_body(provider, model, stream, turns, tools, type)`; 0.4.0 `value_turn(provider, ...)`
  → 0.5.0 `value_turn(provider, model, result, has_type)`; `stream_content` did not exist in
  0.4.0. Note: S7's external-generic registrar resolves generics with
  `get(name, envir = asNamespace(pkg))` (`S7:::registrar`, printed in 5.8), so a package
  *could* register methods on these non-exported generics without `:::` — but it would be
  coding against unstable internals.
- **Turns**: `Turn` (props `contents`, computed `text`, `role`), `UserTurn`, `SystemTurn`,
  `AssistantTurn` (adds `json`, `tokens` = length-3 numeric input/output/cached_input,
  `cost`, `duration`, `finish_reason`), `AssistantPartialTurn` (adds `reason`, default
  "interrupted") (`R/turns.R:31-185`). `Round` groups a user turn with following
  assistant/tool-result turns (0.5.0).
- **Content** classes (`R/content.R`): `ContentText(text)`, `ContentCitation(source,
  grounded_span, cited_quote, extra)`, `ContentImageRemote(url, detail)`,
  `ContentImageInline(type, data)`, `ContentToolRequest(id, name, arguments, tool, extra)`,
  `ContentToolResult(value, error, extra, request)` (error = string or condition),
  `ContentJson(data, string)` (internal), `ContentUploaded(uri, mime_type, provider, extra)`,
  `ContentThinking(thinking, extra)`, `ContentPDF(type, data, filename, url)`,
  `ContentDocument(mime_type, data, filename, url)`, plus web search/fetch request/response
  types.
- **Serialization**: `contents_record(x)` → plain list `{version = 1, class, props}`
  recursively, dropping the live `tool` from tool requests; `contents_replay(x, tools)`
  rebuilds and re-matches tools (`R/content-replay.R`). This is ellmer's only persistence
  format — no session files, no tree.

**Tools.** `tool(fun, description, ..., arguments = list(), name = NULL, convert = TRUE,
annotations = list())` (`R/tools-def.R:121-192`): name defaults to the symbol of `fun`
(else `tool_001`…), must match `^[a-zA-Z0-9_-]+$`; `arguments` names must equal the formals
of `fun`; `type_ignore()` args are hidden from the model; returns `ToolDef`, an S7 class
*inheriting from* `class_function` with props `name, description, arguments (TypeObject),
convert, annotations` (`R/tools-def.R:217-228`) — so a `ToolDef` is callable directly.
`ToolDef` is exported only from 0.5.0 (0.4.0: `could not find function "ToolDef"`, observed).
`tool_annotations(title, read_only_hint, open_world_hint, idempotent_hint,
destructive_hint, ...)` mirrors MCP 2025-03-26 hints. Types: `type_boolean/integer/number/
string(description = NULL, required = TRUE)`, `type_enum(values, description, required)`,
`type_array(items, description, required)`, `type_object(.description, ...,
.required, .additional_properties)`, `type_from_schema(text, path)`, `type_ignore()`
(`R/types.R:158-236`). Tool return values must be character, atomic, `json`, `Content` or
list of `Content`; data frames/lists are deprecated in 0.5.0 and auto-JSON'd with a warning
(`R/chat-tools.R:165-195`).

**How tool calls are executed** (`R/chat-tools.R`, `R/chat.R:750-840`):
1. `chat_impl` loops `while (!is.null(user_turn))` — **no maximum number of rounds**.
2. After each assistant turn, if it contains `ContentToolRequest`s, `invoke_tools()` (a coro
   generator) processes requests **sequentially** in `$chat()`/`$stream()`; `$chat_async()`/
   `$stream_async()` default to `tool_mode = "concurrent"` (promises in parallel).
3. Per request: echo; `on_tool_request` callbacks (a `tool_reject()` there converts to an
   error result *before* the function runs); unknown tool → `"Unknown tool"` error result;
   argument conversion (`convert_from_type`, extra args → error result);
   `do.call(request@tool, args)` inside `tryCatch(error = …)` so **any R error becomes a
   `ContentToolResult(error = e)` sent back to the model**; promises returned in sync mode
   abort with class `tool_async_error`; `on_tool_result` callbacks.
4. Results become one `UserTurn` of `ContentToolResult`s and the loop continues.
5. With `echo = "none"`, tool errors are summarised afterwards as a warning of class
   `ellmer_tool_failure` ("Failed to evaluate N tool call(s).") (`R/chat-tools.R:353-381`).
6. `tool_reject(reason)` signals class `ellmer_tool_reject` with message
   "Tool call rejected. <reason>" (`R/tools-def.R:468-478`).
7. `tool_context()` (0.5.0) gives a running tool the `ContentToolRequest` and the turns;
   implemented as a stack in package state (`R/tool-context.R`).
8. Before each new user input, `complete_dangling_tool_requests()` answers any unanswered
   tool requests in the last assistant turn with an error result "Chat ended before the tool
   could be invoked." (`R/chat.R:1279-1300`) — the root cause of the single-step bridge
   failure (2.8.3).

**Structured output.** `chat_structured(..., type)` disables registered tools; uses native
JSON-schema output when the provider/model supports it (Claude: models matching
`^claude-[a-z]+-(4-[5-9]|[5-9]|[1-9]\d)(-|$)` get `output_config.format = json_schema`,
`R/provider-claude.R:1145-1151`), otherwise a forced tool `_structured_tool_call` with
`tool_choice` (`R/provider-claude.R` `chat_body` method). Streaming structured output only
with native support (0.5.0). `parallel_chat_structured()` returns a data frame, filling
failed rows with NA plus a warning (NEWS 0.4.0).

**Streaming and cancellation.** Sync streaming uses `httr2::req_perform_connection(req)` and
reads SSE events in a `repeat` checking `controller$cancelled`
(`R/httr2.R:49-74`); async streaming uses `blocking = FALSE` + `later::later_fd()` on the
curl fd set (`R/httr2.R:76-115`). `stream_controller()` is an R6 object with `$cancel(reason)`
and `$reset()` (`R/stream-controller.R`). Partial turns survive cancel/Ctrl-C/errors as
`AssistantPartialTurn` (NEWS 0.4.1). Track 02 (digest) found that httr2 connections fail if an
interrupt arrives before the first byte and that only a `curl::multi_run` polling loop
survived resumed interrupts in every phase — ellmer inherits the httr2 behaviour. (Track-02
result, not re-verified here.)

**Async, parallel, batch.**
- `chat_async`/`stream_async`/`chat_structured_async` return promises / coro async
  generators.
- `parallel_chat(chat, prompts, max_active = 10, rpm = 500, on_error = c("return",
  "continue","stop"))` (`R/parallel-chat.R:66-72`): builds one request per conversation,
  throttles with `req_throttle(capacity = rpm, fill_time_s = 60)` and runs
  `httr2::req_perform_parallel(max_active=)`; tools requested by the model are then executed
  **sequentially in R** and the next round is sent in parallel again
  (`R/parallel-chat.R:88-141, 309-360`). Returns cloned `Chat`s, error objects or NULL.
  Also `parallel_chat_text()`, `parallel_chat_structured(…, include_tokens, include_cost)`.
- `batch_chat(chat, prompts, path, wait = TRUE, ignore_hash = FALSE)` and `_text`,
  `_structured`, `_completed` use provider batch APIs; batch support: Anthropic, OpenAI,
  Google Gemini (not Vertex), Groq (`has_batch_support` methods). State is persisted in a
  JSON file at `path`, hashed on provider name/model/base_url.

**Console / browser.** `live_console(chat, quiet = FALSE)` is a 30-line `readline(">>> ")`
loop, `"""` for multi-line input, `Q` to quit, calls `chat$chat(user_input, echo = TRUE)`,
aborts if not interactive (`R/live.R`). `live_browser()` runs
`shiny::runGadget(shinychat::chat_app(chat))`. No slash commands, no interrupt/steer.

**Tokens and cost.** Each `AssistantTurn` carries `tokens` (input, output, cached_input) and
`cost`; session totals in package state `the$tokens` (provider, model, input, output,
cached_input, price) via `token_usage()` (`R/tokens.R`). Prices come from a snapshot
`sysdata.rda` (1,401 rows: AWS/Bedrock 419, Anthropic 31, Azure/OpenAI 272, Google/Gemini 97,
Google/Vertex 85, Groq 15, Mistral 72, OpenAI 289, OpenRouter 111, Posit 10 — VERIFIED by
loading `srcv/ellmer/R/sysdata.rda`), refreshed weekly upstream from **litellm** by a GitHub
workflow, downloadable at runtime with `models_update_prices()` from
`https://raw.githubusercontent.com/tidyverse/ellmer/refs/heads/main/data-raw/prices.json` into
`tools::R_user_dir("ellmer", "cache")`, gated by an integer `schema_version`
(`R/prices.R:1-30, 146`). Cost = tokens × USD per million, with a `variant` column (e.g.
`above_200k_tokens`).

**Providers and defaults (0.5.0).** `chat_anthropic` (= `chat_claude`), `chat_aws_bedrock`,
`chat_azure_openai`, `chat_cloudflare`, `chat_databricks`, `chat_deepseek`, `chat_github`
(defunct 0.5.0), `chat_google_gemini`, `chat_google_vertex`, `chat_groq`,
`chat_huggingface`, `chat_lmstudio`, `chat_mistral`, `chat_ollama`, `chat_openai`
(Responses API), `chat_openai_compatible` (Chat Completions; `base_url` required),
`chat_openrouter`, `chat_perplexity`, `chat_portkey`, `chat_posit` (OAuth device flow against
login.posit.cloud), `chat_snowflake`, `chat_vllm`; generic `chat("provider/model")` looks up
`chat_<provider>` in the ellmer namespace (`R/provider-any.R:13-51`). Default models in source:
`claude-sonnet-5` (Anthropic, Posit, Snowflake), `us.anthropic.claude-sonnet-5` (Bedrock),
`gpt-5.6-terra` (OpenAI, OpenRouter), `gemini-3.7-flash` (Gemini, Vertex),
`deepseek-v4-flash`, `openai/gpt-oss-20b` (Groq), `mistral-large-latest`, `sonar`
(Perplexity), `Qwen/Qwen3-235B-A22B-Instruct-2507` (HF) (grep of `set_default(model, …)`).
Key env vars: `ANTHROPIC_API_KEY` (+`ANTHROPIC_BASE_URL`), `OPENAI_API_KEY`
(+`OPENAI_BASE_URL`), `GOOGLE_API_KEY` then `GEMINI_API_KEY`, `GROQ_API_KEY`,
`DEEPSEEK_API_KEY`, `MISTRAL_API_KEY`, `OPENROUTER_API_KEY`, `PERPLEXITY_API_KEY`,
`HUGGINGFACE_API_KEY`, `AZURE_OPENAI_API_KEY`/`AZURE_OPENAI_ENDPOINT`, `OLLAMA_BASE_URL`,
`LMSTUDIO_BASE_URL`, Databricks/Snowflake/Cloudflare/Portkey variables. **No Claude-plan,
ChatGPT-plan, CLI or System-1 provider** (grep for codex/claude code/oauth in
`provider-claude.R`/`provider-openai.R`: none). VERIFIED.

**Credentials and errors.** Since 0.4.0 keys are never stored: `credentials` is a zero-arg
function returning a string (API key) or a named list of headers, or (internal) a function
of `req` (`R/utils-auth.R:1-88`); headers are added with `req_headers_redacted()`. Anthropic
requests add `anthropic-version: 2023-06-01`, `x-api-key`, optional `anthropic-beta`, retry
on 429/503/529 (`R/provider-claude.R` `base_request` method). All requests:
`req_timeout(getOption("ellmer_timeout_s", 300))`, `req_retry(max_tries =
getOption("ellmer_max_tries", 3), retry_on_failure = TRUE)` (`R/httr2.R:119-131`);
provider-specific `req_error(body = …)` extracts API error messages. Echo default via
`getOption("ellmer_echo")`. OpenTelemetry spans when `otel` is installed (0.4.1).

**API churn** (NEWS.md): 0.3.0 redesigned `tool()` arguments; 0.4.0 removed
`extract_data()`, `chat_azure()`, `chat_bedrock()`, `chat_gemini()`, … and replaced `api_key`
with `credentials`, moved `chat_openai()` to the Responses API and made
`chat_openai_compatible(base_url)` required; 0.4.2 deprecated
`type_object(.additional_properties)`; 0.5.0 made `chat_github()` defunct, deprecated
complex tool return values and `provider@model/params/extra_args`. Every minor release has
breaking or deprecating changes. VERIFIED.

**Dependency footprint and load time** (VERIFIED, 5.6/5.7): ellmer closure 25 non-base
packages (16 compiled); ellmer adds `Rcpp, S7, coro, fastmap, later, otel, pillar,
pkgconfig, promises, tibble, utf8` on top of `{httr2, jsonlite, cli, processx}`;
`loadNamespace("ellmer")` 0.15 s vs httr2 0.12 s, jsonlite 0.01 s, curl 0.007 s, processx
0.01 s, btw 0.46 s.

### 2.5 btw: how it describes R objects and environments (VERIFIED by running, 5.3)

- `btw(...)`: captures dots with names (`dots_list(!!!enquos(...), .named = TRUE)`); no args
  → describes `globalenv()`; otherwise builds a new environment of the evaluated items and
  calls `btw_this(env, items = names)`; the result is an S7 `BTW` object (subclass of
  `ellmer::ContentText`) whose print copies to the clipboard (`R/btw.R`).
- `btw_this()` is an **S3 generic** with methods for `default` (capture `print()` with
  `max.print = 100`, ANSI stripped), `matrix`, `character` (a mini language: `"@news pkg
  v1.2"`, `"@cran versions pkg"`, `"@url …"`, `"@pkg"`, `"@help"`, `"@git"`, `"@issue"`,
  `"@pr"`, `"@current_file"`, `"@current_selection"`, `"@clipboard"`, `"@platform_info"`,
  `"@attached_packages"`, `"@last_error"`, `"@last_value"`, `"./path"`, `"{pkg}"`,
  `"?topic"`, else a user prompt), `data.frame`/`tbl`, `environment`, `function`
  (deparsed source without bytecode/env lines), `Chat` (ignored), help/vignette/news objects
  (`R/btw_this.R`, NAMESPACE S3method lines).
- Data frames: `format = c("skim","glimpse","print","json")`, `max_rows = 5`,
  `max_cols = 100`; frames with ≤10 columns and ≤30 rows are inlined as a markdown table;
  otherwise the default `skim` returns a fenced JSON object `{n_cols, n_rows, groups, class,
  columns: {name: {variable, type, mean, sd, p0..p100 | n_unique, values…}}}`
  (`R/tool-env-df.R:136`; verifier confirmed 30×10 → table, 31×10 and 5×11 → JSON). Cost:
  **2.54 s** for a 2e6×5 frame (full scan via skimr; 3.75 s on verifier re-run under load).
- Environments: iterates `ls(env)` (or `items`), describes each with `btw_this()`, and emits
  `## Context` + one fenced block per object, prefixed by the name; for printed objects the
  output is shown as `#>` lines under the name (see 5.3 output) (`R/tool-env.R`).
- As tools: `btw_tool_env_describe_environment(items)` ("List and describe items in the R
  session's global environment", always `global_env()`) and
  `btw_tool_env_describe_data_frame(data_frame, package, format = skim|json, max_rows,
  max_cols)` — the model passes a *name*; `get0()` resolves it.

**ellmer** has one describer: `df_schema(df, max_cols = 50)` → "A data frame with R rows and
C columns:" + `* col: <type> with range [a, b], and k NAs` / `k unique values ("a", "b")`
(`R/schema.R:21-170`), 0.22 s on the 2e6×5 frame (full-column range/unique). Plus
`content_image_plot(width = 768, height = 768)` which replays `recordPlot()` into a PNG
(`R/content-image.R:128-153`).

**mcptools** does not describe objects (grep: no describer); tools come from
`mcp_server(tools =)`, recommended `btw::btw_mcp_server()` → `btw_tools()` minus skills
(`srcv/btw/R/mcp.R`). mcptools even special-cases `btw_tool_env_describe_environment`'s
empty `items` array (`srcv/mcptools/R/tools.R:297-302`).

**corteza** returns `str(x, max.level = 1, list.len = 10)` summaries plus a handle for
"large" results (data frames, matrices, lists > 10, atomics > 50, or > 10 kB)
(`srcv/corteza/R/handles.R:43-67`).

**Lesson for gptr's describer (REQ-21):** btw's skim and ellmer's df_schema both scan every
element; on a multi-GB object they cost seconds to minutes. gptr needs a bounded-cost
describer (header with class/dim/size, `str()`-like shallow structure, sampled column
summaries marked as approximate, `print()` only under a time/line budget). Prototype
`gptr_describe()` took 0.078 s on the same frame (5.3).

### 2.6 mcptools architecture (reference for D-14)

- Exports only `mcp_server()`, `mcp_session()`, `mcp_tools()` (NAMESPACE).
- `mcp_server(tools = NULL, ..., type = c("stdio","http"), host = "127.0.0.1", port =
  as.integer(Sys.getenv("MCPTOOLS_PORT","8080")), session_tools = TRUE)`; refuses interactive
  use; `tools` is a list of ellmer `tool()`s or a path to an `.R` file returning one
  (`R/server.R:180-204`, docs lines 1-178).
- Setup documented: Claude Desktop `{"mcpServers":{"r-mcptools":{"command":"Rscript",
  "args":["-e","mcptools::mcp_server()"]}}}`; Claude Code `claude mcp add -s "user"
  r-mcptools Rscript -e "mcptools::mcp_server()"`; on Windows "you may need to configure
  the full path to the Rscript executable" (`R/server.R` roxygen).
- `mcp_session()` listens on a `nanonext` "poly" socket at `<socket_url><i>` (first free
  i < 1024), registers a finalizer, and schedules
  `nanonext::recv_aio()` → `promises::as.promise()$then(handle_message_from_server)`
  (`R/session.R:3-38, 346-352`): **tool calls run when the R event loop is idle** (between
  top-level commands). Messages are MAC-sealed (HMAC-SHA256 via `openssl::sha256(key=)`) with
  a per-user secret file stored next to the sockets (`R/socket-auth.R`); sockets live in an
  owner-only (0700) directory. Order per NEWS 1.0.1 (Linux): `MCPTOOLS_SOCKET_DIR` >
  `XDG_RUNTIME_DIR/mcptools/` > `$TMPDIR/mcptools-<user>/` > `/tmp/mcptools-<user>/`. Source
  (`R/socket-dir.R:10-52, 150-160`) adds: on **macOS** the default is `$TMPDIR/mcptools`
  (no user suffix; fallback `tempdir()/mcptools`); on **Windows** there is no socket
  directory — named pipes `ipc://mcptools-<user>-socket`, secret under
  `%TEMP%/mcptools-<user>/`, documented as "not a security boundary".
- Session selection: the server prefers the session whose working directory matches its
  own, else the only session, else runs in its own process until `select_r_session` (NEWS
  1.0.1).
- Client: `mcp_tools(config = NULL)` reads `getOption(".mcptools_config",
  "~/.config/mcptools/config.json")` (Claude-Desktop `mcpServers` format) and returns ellmer
  tools (`R/client.R:140-179`); OAuth authorization-code flow for remote servers on 401
  (NEWS 1.0.1).

### 2.7 Other packages: specific lessons

- **llm.api** (`srcv/llm.api`, 3,554 lines): `chat(prompt, model, system, history,
  temperature, max_tokens, provider = c("auto","openai","anthropic","anthropic_claude",
  "moonshot","openai_codex","ollama","openai_compatible"), stream, cache, thinking_budget_tokens,
  web_search, ...)` (`R/chat.R:205-210`); `agent(prompt, tools, tool_handler, system, model,
  provider, max_turns = 20L, verbose, history, history_callback, cache,
  thinking_budget_tokens, web_search, ...)` (`R/agent.R:81-87`); MCP client in 282 lines. Claude
  subscription: headers `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`
  (`R/anthropic-claude.R:26-71`); tokens via `tinyoauth::oauth_token_anthropic()` whose client
  uses `https://claude.com/cai/oauth/authorize`, `https://platform.claude.com/v1/oauth/token`,
  redirect `https://platform.claude.com/oauth/code/callback`, scope `user:inference`
  (`srcv/tinyoauth/R/anthropic.R:24-27`). Codex: `Authorization: Bearer`,
  `chatgpt-account-id`, `OpenAI-Beta: responses=experimental`, `originator: llm.api`,
  `accept: text/event-stream` (`R/openai-codex.R:236-243`); device flow on
  `https://auth.openai.com` (`srcv/tinyoauth/R/openai_codex.R:24-27`). Token cache under
  `tools::R_user_dir("tinyoauth","cache")` (`srcv/tinyoauth/R/cache.R:3-12`). **Lesson:** a
  complete thin provider layer is feasible in a few thousand lines on curl+jsonlite; but the
  Claude-OAuth route contradicts Anthropic's published terms (2.9.2).
- **ravel** drives CLIs with `system2()`: `codex exec --skip-git-repo-check --ephemeral
  --sandbox read-only --output-last-message <tmpfile> -` with the prompt on stdin
  (`srcv/ravel/R/providers_openai.R:222-243`); login check `codex login status`
  (`R/auth.R:282`); Copilot `-p <prompt>` and a PowerShell variant on Windows
  (`R/providers_copilot.R:25-74`). Detailed CLI protocol is tracks 07/08's topic.
- **tidyprompt** `llm_provider_ellmer(chat, parameters, verbose)` needs runtime checks for
  which ellmer classes exist (`exists("UserTurn", envir = ellmer_ns)`, fallback to
  `Turn(role=)` for < 0.4.0) and maps tool rows to user turns
  (`srcv/tidyprompt/R/llm_providers.R`, `llm_provider_ellmer`). **tidyllm**'s ellmer backend
  aborts if tidyllm tools are supplied: "Tidyllm tools are not supported in the ellmer
  backend. Set ellmer tools directly in the ellmer chat object instead"
  (`srcv/tidyllm/R/api_ellmer.R:101`). Both corroborate 2.8.3.
- **mall**: `llm_vec_verify(x, what, yes_no = factor(c(1, 0)), ...)` → factor without
  probabilities (`srcv/mall/R/llm-verify.R:67-82`).
- **LLMR** `llm_logprobs()` / **rtemis.llm** `logprobs()`, `token_probs()` extract token
  log-probabilities; both document that Anthropic returns none (roxygen in
  `srcv/LLMR/R/logprobs.R:9-33`, `srcv/rtemis.llm/R/map.R:239-263`). Relevant to emulated
  System 1 (D-06): probabilities are only available from OpenAI-style/Ollama providers.
  LIKELY (documentation claim, not tested).
- **vitals** `claude_code(solver_chat, ..., version = "auto", sandbox = "docker")` and
  `codex(...)` run the real CLIs inside Docker through Python Inspect's `inspect_swe`
  (`srcv/vitals/R/solver-agent.R:1-140`).
- **mcplite** re-implements (does not re-export) an ellmer-compatible `tool()` / `type_*()`
  DSL; Imports are only jsonlite, nanonext, otel (ellmer is in Suggests) — ellmer's tool DSL
  is a de-facto convention (NAMESPACE, DESCRIPTION).
- **commons** ships its skill at `system.file("skills","commons")` and instructs copying to
  `.agents/skills` (Posit Assistant, Codex) or `.claude/skills` (Claude Code)
  (`srcv/commons/README.md`).
- **streamy** `stream()` inlines coro-generator output into the active document via
  rstudioapi — prior art for REQ-25 live document writing in RStudio (NAMESPACE, DESCRIPTION).

### 2.8 Critical question 2 — build on ellmer or own thin layer?

#### 2.8.1 Arguments for building on ellmer (all VERIFIED)
- 22 exported `chat_*` provider constructors (plus the `chat_claude` alias; 21 usable because
  `chat_github()` is defunct in 0.5.0) including enterprise auth (AWS SigV4 Bedrock, gargle/Vertex, Azure AD,
  Databricks, Snowflake key-pair, Posit OAuth) that gptr would otherwise never cover.
- Mature structured output, citations, file uploads, batch APIs, OTel, price table.
- Passes all 13 CRAN flavours; 13.8k downloads/month; Posit-maintained.
- Moderate footprint (25 deps, 0.15 s load).

#### 2.8.2 Arguments against (all VERIFIED unless marked)
1. **No extension surface for new provider kinds.** Provider generics are internal and
   changed signatures in 0.5.0; Jev (`POST /systemone`, non-chat), CLI providers
   (`claude -p`, `codex exec`) and subscription routing cannot be added as ellmer providers
   without depending on internals.
2. **Loop ownership.** gptr's loop (Pi semantics: steering/follow-up queues, finite
   `max_turns`, compaction, abort, events, permission modes, document writing) must own the
   step between model calls. ellmer's `Chat` owns its loop; the only exported hooks are
   callbacks. A single-step bridge is impossible without an artificial extra user message
   (prototype 5.2; verifier also checked the alternative "`set_turns()` including the
   tool-result turn, then `$chat()` with no input": it aborts with "`...` must contain at
   least one input." on 0.4.0 and 0.5.0).
3. **Session format.** ellmer has no session file/tree; gptr needs Pi-v3-compatible JSONL
   (track 02) and cross-provider hand-off; gptr must translate anyway.
4. **Streaming/interrupt semantics.** ellmer streams via `req_perform_connection` (sync)
   whose interrupt behaviour track 02 found unreliable before the first byte; gptr needs the
   `curl::multi_run` polling design for REQ-38. (track-02 finding)
5. **Churn.** Breaking/deprecating changes in 0.3.0, 0.4.0, 0.4.2, 0.5.0 (2.4).
6. **Wire bugs are inherited.** 0.4.0 boxes tool-call argument scalars into arrays on
   replay (5.2). gptr cannot fix a dependency's wire format.
7. **The maintainer wants routing and plan usage implemented in gptr itself** (D-01).
8. **Tool-result contract.** ellmer 0.5.0 deprecates complex tool return values
   (data frames/lists) — gptr's R tool wants to return R values to the harness while
   sending text to the model; its own contract is simpler to control.

#### 2.8.3 Prototype outcome (VERIFIED, 5.2)
- *Single-step bridge* (`proto_ellmer_bridge.R`): step 1 works (stub tools + an
  `on_tool_request` callback that aborts with class `gptr_ellmer_yield` → assistant turn
  with tool requests, tokens and cost is recorded, no tool runs). Step 2 fails: the wire
  shows roles `system,user,assistant,tool,tool` with an extra `"Tool calling failed with
  error Chat ended before the tool could be invoked."` for the same `tool_call_id` (ellmer
  0.4.0 and 0.5.0). Many providers reject duplicate results for one call id (UNCERTAIN which).
- *Delegate bridge* (`proto_ellmer_bridge2.R`): ellmer owns the loop; tool functions are
  generated wrappers that call gptr's executor; the permission check runs in
  `on_tool_request` and denies with `tool_reject()`; tool code is evaluated in the caller's
  environment (object `x_bridge` = 55 appeared there); denial reached the model as
  "Tool call rejected. Denied by gptr permission mode 'manual'."; a turn budget is enforced
  by aborting with class `gptr_budget` from the callback; ellmer's `ellmer_tool_failure`
  warning is muffled; turns are translated back to gptr messages. Works on 0.4.0 and 0.5.0.
- Importing ellmer `ToolDef`s into gptr (`proto_import_ellmer_tools.R`): JSON schema built
  from exported S7 properties (`TypeBasic@type`, `TypeEnum@values`, `TypeArray@items`,
  `TypeObject@properties`, `@description`, `@required`); a btw tool executed by gptr code
  returned the `stats::sd` help page.

#### 2.8.4 Recommendation (D-01)
**Own thin provider layer in gptr (Imports: jsonlite + curl or httr2 per track 15), plus an
optional ellmer bridge in Suggests.** Concretely:
- Native providers: Anthropic Messages, OpenAI Responses (+ Chat Completions for
  compatibles), Gemini, Ollama/OpenAI-compatible (OpenRouter, Groq, vLLM, LM Studio …),
  Jev System One, CLI providers (`claude`, `codex`). Everything REQ-11..15 needs.
- `model =` also accepts an **ellmer `Chat` object** → wrapped by `gptr_provider_ellmer()`
  in *delegate mode*; documented limitations: no mid-loop steering (only abort at the next
  tool request), no gptr compaction inside a run (0.5.0's `on_request_start` could be used
  later), streaming events only via `$stream(stream = "content")` (not prototyped).
- Minimum `ellmer (>= 0.5.0)` in Suggests (0.4.0 argument-boxing bug; `ToolDef` exported).
- Interop helpers (Suggests ellmer): `gptr_tools_from_ellmer(x)` to accept `ToolDef`s (btw,
  mcptools, ragnar tools) and `gptr_tools_as_ellmer()` to export gptr tools to ellmer users.
- Reuse *ideas and data formats*, not code: litellm-derived price table (ellmer's approach),
  ellmer-compatible tool-type vocabulary in docs, btw's hash-anchored edits and cwd
  restriction, mcptools' socket-based session discovery.

### 2.9 Critical question 3 — gptr on CRAN

#### 2.9.1 Facts (VERIFIED)
- `https://cran.r-project.org/package=gptr`: Version 0.7.0, Imports jsonlite, RCurl,
  Published 2025-04-05, Maintainer "Wanjun Gu <wanjun.gu at ucsf.edu>", MIT + file LICENSE,
  NeedsCompilation no; archive link present; no reverse dependencies listed.
- `tools::CRAN_package_db()`: Packaged "2025-04-04 18:12:53 UTC; wanjun", Date/Publication
  "2025-04-05 11:20:14 UTC", X-CRAN-Comment NA, Reverse depends/imports/suggests/linking
  to/enhances all NA.
- CRAN checks (generated 2026-09-30 03:01 CEST): OK on all 13 flavours incl.
  r-devel/r-release/r-oldrel Windows.
- Archive: `gptr_0.5.0.tar.gz` (2024-05-06 21:10, 4.8K), `gptr_0.6.0.tar.gz` (2024-05-07
  10:00, 4.8K). crandb timeline: 0.5.0 2024-05-06T18:10:03Z, 0.6.0 2024-05-07T07:00:03Z,
  0.7.0 2025-04-05T10:20:14Z; `archived: false`.
- Exports of 0.7.0: `get_response(user_input = "what is a p-value in statistics?",
  system_specification = "You are a helpful assistant.", model = "gpt-3.5-turbo",
  api_key = Sys.getenv("OPENAI_API_KEY"), print_response = TRUE)` and
  `dataframe_to_text(dataframe)` (tarball `srcv/gptr/R/get_response.R:27-31`,
  `R/dataframe_to_text.R:19`, NAMESPACE; also `importFrom(RCurl,getURL)`,
  `importFrom(jsonlite,fromJSON)`).
- Downloads (cranlogs, RStudio mirror): 302 in 2026-08-30..2026-09-28; 11,125 in
  2024-05-01..2026-09-28.

#### 2.9.2 Implications of a total API break
- CRAN policy: "Changes to CRAN packages causing significant disruption to other packages
  must be agreed with the CRAN maintainers well in advance of any publicity" and maintainers
  should notify reverse dependencies "at least 2 weeks" before — **not triggered** (no
  reverse dependencies). VERIFIED (policy text fetched).
- Package names are persistent; keeping the name `gptr` with a new API is allowed
  (policy: "it is not permitted to change a package's name").
- Recommend version **1.0.0**, a NEWS.md entry stating both old functions are removed with a
  migration line (`get_response(x)` → `gptr(x)`), new Title/Description. S-7 forbids shims.
- If the maintainer email in DESCRIPTION changes, the policy requires to "Explain any
  change in the maintainer's email address and if possible send confirmation from the
  previous address".
- Update cadence: "no more than every 1–2 months" once established — plan 1.0.0 then
  consolidate fixes.
- User impact: ~300 downloads/month of scripts calling `get_response()` will break; no way
  to measure GitHub usage (GitHub code search was rate-limited during this research —
  UNCERTAIN).

### 2.10 Critical question 4 — name collisions

Method (VERIFIED, 5.9): (a) exports of all 613 packages installed on this machine (includes
tidyverse, Bioconductor-heavy Seurat stack, future, data.table …), read from
`Meta/nsInfo.rds`; (b) export() lines of the 37 LLM tarballs; (c) r-universe exports search
(`https://r-universe.dev/api/search?q=exports:<name>`, which indexes CRAN, Bioconductor and
r-universe — but it missed some CRAN LLM packages such as corteza/llm.api for `chat`, so it
is **not exhaustive**).

| Candidate | Exported by (usedby count from r-universe where available) | Verdict |
|---|---|---|
| `gptr`, `gptr_init`, `gptr_config`, `gptr_env`, `gptr_providers`, `gptr_models`, `gptr_mcp`, `gptr_tool`, `gptr_session` | nobody | safe |
| `prompt`, `history` | **utils** (base R), Rcpp[14877], renv | never export |
| `plan` | **future**, SeuratObject, renv[148], drake | never export; also NSE hazard for `mode = plan` |
| `tool`, `tools` | ellmer[47], aisdk[61], mcplite, epiworldR; eppoFindeR | avoid |
| `chat` | ellmer, corteza, llm.api, tidyllm, rollama, gptstudio, ollamar, … | avoid |
| `agent` | llm.api, LLMRagent, villager, rmorie | avoid (north-star `agent()` → rename) |
| `classify` | terra[1017], admisc[85], 41 others | avoid |
| `decide`, `decision` | nimble[34]; changepoint[45], decideR | avoid |
| `ask` | gtools[1177], sensitivity | avoid |
| `extract` | magrittr[14435], tidyr[6898], terra, raster, … (89) | avoid |
| `pick` | dplyr[9607] | avoid |
| `rank`, `score` | BiocGenerics[2514], bit64, GenomicRanges, … | avoid |
| `session` | rvest[611] | avoid |
| `config`, `setup` | httr[4061], plotly, renv; testthat[456], harness | avoid |
| `model`, `provider` | aisdk, rmutil, fabletools…; GenomeInfoDb, Seqinfo | avoid |
| `mcp` | multcomp[400] | avoid |
| `skill`, `skills`, `judge`, `jev`, `yes_no`, `run_r`, `as_tool`, `plugin`, `steer`, `subagent`, `system1`, `system2`, `haiku`, `edits` | nobody (skills: treeclim) | free but generic; prefer `gptr_` prefix |
| `read_file`, `write_file`, `edit_file` | readr[2396], brio[548]; usethis | avoid |
| `type_string`, `type_boolean`, `type_enum` | ellmer, mcplite, rollama | avoid |
| `interpolate`, `params` | ellmer, e1071, generics; S4Vectors | avoid |
| **NSE identifiers** `claude`, `gemini`, `chatgpt`, `openai`, `ollama`, `groq`, `mistral`, `deepseek`, `ellmer` | functions in **tidyllm** (VERIFIED `srcv/tidyllm/NAMESPACE`) | must be read with `substitute()` before evaluation |
| **NSE identifiers** `codex`, `claude_code` | functions in **vitals** | same |
| **NSE identifiers** `opus`, `sonnet`, `gpt`, `auto`, `manual` | opusminer, netOP, meta.shrinkage, isoreader2/r2typ, lidR (all obscure) | same rule |

Recommendation: export `gptr()` plus only `gptr_*` names (D-28 confirmed). The sub-agent
constructor in north-star example 6 should be `gptr_agent()` (or a plain list). For NSE
(D-07): resolve a bare symbol against gptr's alias registry *first*; evaluate the symbol only
if it is not a known alias; if a known alias is also bound in the caller's frame to
something that is not a gptr spec (e.g. `tidyllm::claude` attached), still use the alias
and do not warn; if bound to a character/gptr spec, use the binding only when wrapped in
`I()` or `!!`.

---

## 3. Exact specifications

### 3.1 ellmer 0.5.0 signatures (verbatim from source)

```r
# R/chat.R:41-46
Chat$new(provider, model = NULL, system_prompt = NULL, echo = "none")
# R/provider.R:30-42
Provider <- new_class("Provider", properties = list(
  name = prop_string(), base_url = prop_string(), extra_headers = class_character,
  credentials = class_function | NULL,
  model = prop_deprecated("model", "name"), params = prop_deprecated("params", "params"),
  extra_args = prop_deprecated("extra_args", "extra_args")))
# R/provider.R:78-91 (internal generic)
chat_request <- new_generic("chat_request", "provider",
  function(provider, model, stream = TRUE, turns = list(), tools = list(), type = NULL) S7_dispatch())
# R/tools-def.R:121-132
tool <- function(fun, description, ..., arguments = list(), name = NULL, convert = TRUE,
  annotations = list(), .name = deprecated(), .description = deprecated(),
  .convert = deprecated(), .annotations = deprecated())
# R/tools-def.R:217-228
ToolDef <- new_class("ToolDef", parent = class_function, properties = list(
  name = prop_string(), description = prop_string(), arguments = TypeObject,
  convert = prop_bool(TRUE), annotations = class_list))
# R/tools-def.R:468-478
tool_reject <- function(reason = "The user has chosen to disallow the tool call.")
  # abort(paste("Tool call rejected.", reason), class = "ellmer_tool_reject")
# R/types.R
type_boolean(description = NULL, required = TRUE); type_integer(...); type_number(...)
type_string(description = NULL, required = TRUE)
type_enum(values, description = NULL, required = TRUE)
type_array(items, description = NULL, required = TRUE)
type_object(.description = NULL, ..., .required = TRUE, .additional_properties = deprecated())
  # (verifier: args(ellmer::type_object) on 0.5.0; the default is deprecated(), not FALSE)
type_from_schema(text, path); type_ignore()
# R/params.R:27-39
params(temperature = NULL, top_p = NULL, top_k = NULL, frequency_penalty = NULL,
  presence_penalty = NULL, seed = NULL, max_tokens = NULL, log_probs = NULL,
  stop_sequences = NULL, reasoning_effort = NULL, reasoning_tokens = NULL, ...)
# R/parallel-chat.R:66-72
parallel_chat(chat, prompts, max_active = 10, rpm = 500, on_error = c("return", "continue", "stop"))
parallel_chat_structured(chat, prompts, type, convert = TRUE, include_tokens = FALSE,
  include_cost = FALSE, max_active = 10, rpm = 500, on_error = c("return","continue","stop"))
# R/batch-chat.R:85
batch_chat(chat, prompts, path, wait = TRUE, ignore_hash = FALSE)
# R/provider-any.R:13-19
chat(name, ..., system_prompt = NULL, params = NULL, echo = c("none", "output", "all"))
# R/schema.R:21
df_schema(df, max_cols = 50)
# R/content-image.R:128
content_image_plot(width = 768, height = 768)
# R/live.R
live_console(chat, quiet = FALSE); live_browser(chat, quiet = FALSE)
```

Options/env honoured by ellmer: `ellmer_timeout_s` (default 300), `ellmer_max_tries`
(default 3), `ellmer_echo`; `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT="true"` for
message content in OTel spans (NEWS 0.4.1).

Condition classes: `ellmer_tool_reject` (rejection), `ellmer_tool_failure` (post-run warning),
`tool_async_error`, `ellmer_error_tool_context_unavailable`, `not_implemented`.

Dangling-request error text (exact): `"Chat ended before the tool could be invoked."`
(`R/chat.R:1296`). Tool error string sent to the model: `"Tool calling failed with error "`
+ message (`R/content.R`, `tool_string`).

Anthropic wire constants in ellmer: base `https://api.anthropic.com/v1` (or
`ANTHROPIC_BASE_URL`, trailing slashes stripped and `/v1` appended only if not already
present), path `messages`, header `anthropic-version: 2023-06-01`, key header `x-api-key`,
transient statuses 429/503/529, `max_tokens` default 4096 when unset, system prompt gets
`cache_control = {type: "ephemeral", ttl: <cache>}` unless `chat_anthropic(cache = "none")`
(default `cache = "5m"`; `cache_control()` returns NULL for "none")
(`R/provider-claude.R:150-311, 1134-1143`).

Price data URL: `https://raw.githubusercontent.com/tidyverse/ellmer/refs/heads/main/data-raw/prices.json`
(`R/prices.R:146`); cache dir `tools::R_user_dir("ellmer", "cache")`.

### 3.2 btw 1.5.0

- Signatures: `btw(..., clipboard = TRUE)`; `btw_this(x, ...)`;
  `btw_this.data.frame(x, ..., format = c("skim","glimpse","print","json"), max_rows = 5,
  max_cols = 100, package = NULL)`; `btw_this.environment(x, ..., items = NULL)`;
  `btw_client(..., client = NULL, tools = NULL, path_btw = NULL, path_llms_txt = NULL)`;
  `btw_tools(...)`; `btw_mcp_server(tools = NULL)`; `btw_mcp_session()`.
- Options/env: `btw.run_r.enabled`, `BTW_RUN_R_ENABLED` (`true`/`1`),
  `btw.run_r.plot_aspect_ratio` (default "3:2"), `btw.run_r.plot_size` (768),
  `btw.run_r.graphics_device`, `btw.skills.paths` / `BTW_SKILLS_PATHS`,
  `btw.files_search.extensions`, `btw.files_search.exclusions`.
- Config/instructions file: `btw.md` (project), `~/.btw/btw.md` (user); multiple clients in
  YAML frontmatter `client:` (list or named aliases) (NEWS 1.2.0, 1.4.0).
- Skills: package `inst/skills/`, user `~/.btw/skills`, project `.btw/skills` or
  `.agents/skills` (`R/tool-skills.R:28`); custom agents
  `.btw/agents/*.md`, `~/.btw/agents/*.md`, `.claude/agents/` (NEWS 1.2.0–1.4.0).
- Edit anchoring: `btw_tool_files_read()` annotates lines as `2:f1a|  return("world")` (NEWS 1.2.0).

### 3.3 mcptools 1.0.3

- `mcp_server(tools = NULL, ..., type = c("stdio","http"), host = "127.0.0.1", port =
  as.integer(Sys.getenv("MCPTOOLS_PORT", "8080")), session_tools = TRUE)`.
- Built-in session tools: `list_r_sessions`, `select_r_session`.
- Env: `MCPTOOLS_PORT`, `MCPTOOLS_SOCKET_DIR`; socket dir fallback (Linux)
  `XDG_RUNTIME_DIR/mcptools/`, `$TMPDIR/mcptools-<user>/`, `/tmp/mcptools-<user>/`; macOS
  `$TMPDIR/mcptools/`; Windows: named pipe `ipc://mcptools-<user>-socket` (no directory).
- Client config: option `.mcptools_config`, default `~/.config/mcptools/config.json`.

### 3.4 Subscription-route constants seen in CRAN code (documented for tracks 07/08; do
not implement the Claude one)

```text
llm.api anthropic_claude:  Authorization: Bearer <access_token>
                           anthropic-beta: oauth-2025-04-20
                           anthropic-version: 2023-06-01
tinyoauth Claude client:   auth_url     https://claude.com/cai/oauth/authorize
                           token_url    https://platform.claude.com/v1/oauth/token
                           redirect_uri https://platform.claude.com/oauth/code/callback
                           scope        user:inference
llm.api openai_codex:      Authorization: Bearer <token>; chatgpt-account-id: <id>
                           OpenAI-Beta: responses=experimental; originator: llm.api
                           accept: text/event-stream
tinyoauth Codex base:      https://auth.openai.com (device flow; redirect /deviceauth/callback)
ravel codex CLI:           codex exec --skip-git-repo-check --ephemeral --sandbox read-only
                                      --output-last-message <file> - [--model <m>]
                           (prompt file on stdin via system2(stdin=); ravel appends
                            --model AFTER the "-" positional, R/providers_openai.R:227-240)
```

Anthropic policy (verbatim, `https://code.claude.com/docs/en/legal-and-compliance`,
fetched 2026-09-29): "Anthropic does not permit third-party developers to offer Claude.ai
login into their own applications, or to route requests through Free, Pro, or Max plan
credentials on behalf of their users. Moreover, developers may not collect, store, or
intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must
complete through Anthropic's own flow." and "Nor does it prevent an end user from signing
in to the unmodified Claude Code binary with their own Claude subscription".

### 3.5 CRAN metadata of gptr 0.7.0 (DESCRIPTION from the CRAN tarball, abridged: the `Description:`, `Author:` and `Maintainer: Wanjun Gu <wanjun.gu@ucsf.edu>` fields are omitted and `Authors@R` is re-wrapped)

```text
Package: gptr
Type: Package
Title: A Convenient R Interface with the OpenAI 'ChatGPT' API
Version: 0.7.0
Authors@R: person("Wanjun", "Gu", , "wanjun.gu@ucsf.edu", role = c("aut", "cre"),
           comment = c(ORCID = "0000-0002-7342-7000"))
License: MIT + file LICENSE
Encoding: UTF-8
RoxygenNote: 7.3.1
Imports: jsonlite, RCurl
NeedsCompilation: no
Packaged: 2025-04-04 18:12:53 UTC; wanjun
Repository: CRAN
Date/Publication: 2025-04-05 11:20:14 UTC
```

### 3.6 CRAN policy sentences relevant here (verbatim, fetched)

- "Packages should not modify the global environment (user's workspace)."
- "Packages should not write in the user's home filespace (including clipboards), nor
  anywhere else on the file system apart from the R session's temporary directory …
  Limited exceptions may be allowed in interactive sessions if the package obtains
  confirmation from the user." / "packages may store user-specific data, configuration and
  cache files in their respective user directories obtained from `tools::R_user_dir()`".
- "`:::` should not be used to access undocumented/internal objects in base packages (nor
  should other means of access be employed)."
- "Packages which use Internet resources should fail gracefully with an informative message
  if the resource is not available or has changed (and not give a check warning nor error)."
- "If running a package uses multiple threads/cores it must never use more than two
  simultaneously".
- "Packages should not start external software (such as PDF viewers or browsers) during
  examples or tests unless that specific instance of the software is explicitly closed
  afterwards."
- "Changes to CRAN packages causing significant disruption to other packages must be agreed
  with the CRAN maintainers well in advance of any publicity."

---

## 4. Recommended design for gptr (this track's scope)

### 4.1 Package dependencies (D-20 input)

| Package | Role | Recommendation |
|---|---|---|
| jsonlite | JSON | Imports |
| curl (or httr2) | HTTP/SSE | Imports; choose per track 15. {curl, jsonlite, processx} closure = 5 packages (R6, curl, jsonlite, processx, ps); {httr2, jsonlite, cli, processx} = 16 |
| processx | CLI providers, MCP stdio, shell tool | Imports |
| cli | console rendering | Imports (small) |
| ellmer (>= 0.5.0) | optional bridge + tool interop | **Suggests** only |
| btw, mcptools, shinychat, ragnar | none required | not listed, or Suggests only for vignettes/tests of interop |
| evaluate, knitr, rmarkdown, shiny, bslib, yaml, callr, httpuv, later, promises | per other tracks | Suggests unless another track proves Imports |

Never Import btw (70 deps incl. two Rust-built packages, `frontmatter` → `tomledit`,
`yaml12`).

### 4.2 Provider contract and ellmer bridge

gptr's provider contract (from track 02): `stream_fn(model, context, options, on_event)`
returning the final assistant message, never throwing for provider failures. For an ellmer
`Chat` the bridge implements a *run* contract instead of a *step* contract:

```r
# exported, requires ellmer (Suggests); also used automatically when model= is an ellmer Chat
gptr_provider_ellmer <- function(chat, name = NULL)
# returns a gptr_provider with kind = "delegate" and
#   $run(messages, tools, system, envir, permit, max_tool_rounds, on_event)
#     -> list(status = "ok"|"budget"|"aborted"|"error", messages = <gptr messages>, usage)
```

Algorithm (prototype 5.2, `gptr_run_via_ellmer`):
1. `ch <- chat$clone(deep = TRUE)` (deep so callbacks do not leak to the user's Chat —
   verified: original chat stayed at 0 turns; verifier also checked directly on 0.4.0 and
   0.5.0 that a *shallow* clone shares the `CallbackManager`, so `ch$on_tool_request()` on a
   shallow clone adds the callback to the user's Chat, while a deep clone does not).
   Note: ellmer validates callback formals — `on_tool_request()` callbacks must have an
   argument named `request` and `on_tool_result()` callbacks one named `result`
   (`function(r)` aborts with "`callback` must have the argument `request`").
2. `ch$set_system_prompt(system)`; `ch$set_turns(to_ellmer_turns(history_before_last_user))`.
3. For each gptr tool spec create `tool(<wrapper>, name, description, arguments)` whose
   formals match the JSON-schema properties and whose body calls gptr's executor
   (`executor$run(name, args)`), so R code runs in `envir` under gptr's output capture.
4. `ch$on_tool_request()`: increment round counter; abort with class `gptr_budget` beyond
   `max_tool_rounds`; poll gptr's abort/steer signal and abort with `gptr_abort` if set;
   `permit(name, args)` → `tool_reject("<mode message>")` when denied; emit
   `tool_execution_start`.
5. `ch$on_tool_result()` → emit `tool_execution_end`.
6. `withCallingHandlers(ch$chat(last_user_text, echo = "none"), ellmer_tool_failure =
   muffle)` inside `tryCatch(gptr_budget =, gptr_abort =)`.
7. Translate `ch$get_turns()` to gptr messages (text, thinking, tool_call, tool results with
   `is_error`, usage = tokens + cost). Append to the gptr session like any provider output.

Limitations to document: no steering message injection mid-run; gptr compaction applies only
between runs (0.5.0 `on_request_start` could compact within a run later); ellmer's own
retries/timeouts apply; streaming deltas require `ch$stream(stream = "content")` (not
prototyped — UNCERTAIN).

### 4.3 Tool interop

```r
gptr_tools_from_ellmer(x)   # x: ToolDef or list of ToolDef (e.g. btw::btw_tools("docs"))
# -> list of gptr tools: name, description, parameters (JSON schema from S7 props),
#    read_only (annotations$read_only_hint), run(args) calling the ToolDef and flattening
#    ContentToolResult/Content to text (prototype 5.4)
gptr_tools_as_ellmer(tools = gptr_default_tools())   # gptr tools -> ellmer ToolDefs
```

Tool definitions inside gptr: keep a JSON-schema-first internal representation (not ellmer
Type objects), so MCP tools (JSON schema native), ellmer tools and gptr tools share one
format.

### 4.4 Object description (REQ-21) informed by btw/ellmer

`gptr_describe(x, name, budget = list(time = 0.5, lines = 40, sample = 1000))` (internal,
also available to the model from the `r` tool as an ordinary R function):
1. Header: name, class vector, `object.size()` only for atomic/data.frame/S4 or length
   < 1e5 (guard against slow traversal), dims/length.
2. Data frames: up to 30 columns, per column class + **sampled** summary (≤1,000 evenly
   spaced values; numeric range, factor levels count, first 3 distinct strings, date range)
   explicitly marked "~" as approximate.
3. S4: slot names (≤20); lists: first 10 element names/classes; functions: formals.
4. Objects with informative print methods (e.g. `lm`, Seurat): `print()` captured under a
   `setTimeLimit(elapsed = budget$time)` and truncated to `budget$lines`.
5. Environment summary = one header line per object, sorted by size descending, with a
   total count; never describes every object in full by default (btw's
   `describe_environment` does).
Offer `format = "btw"` delegating to `btw::btw_this()` when btw is installed (Suggests-free
dynamic check) for users who prefer skim output.

### 4.5 Naming and NSE

- Exports: `gptr()` + `gptr_*` only (e.g. `gptr_init`, `gptr_config`, `gptr_env`,
  `gptr_providers`, `gptr_models`, `gptr_mcp`, `gptr_agent`, `gptr_tool`,
  `gptr_provider_ellmer`, `gptr_tools_from_ellmer`, `gptr_tools_as_ellmer`).
- North-star `agent(model = opus, ...)` → `gptr_agent(model = opus, ...)`.
- NSE ambiguity rule (D-07): capture with `substitute()`; known alias wins over any binding
  of the same name unless `I()`/`!!` is used; this is required because `claude`, `gemini`,
  `openai`, `ollama`, `groq`, `mistral` (tidyllm), `codex`, `claude_code` (vitals) and
  `plan` (future) are functions in commonly attached packages.

### 4.6 Compatibility conventions to adopt

- Skills discovery order should include package `inst/skills/` (btw/commons convention),
  project `.gptr/skills`, `.agents/skills`, `.claude/skills`, `.btw/skills`, user
  `~/.gptr/skills` (or `R_user_dir`), subject to CRAN rules on reading (reading is fine).
- MCP config import: also read `~/.config/mcptools/config.json` (Claude-Desktop shape).
- Price table: vendor a litellm-derived snapshot in `inst/extdata` (MIT licence; attribute)
  and refresh into `tools::R_user_dir("gptr","cache")` on request (D-18), mirroring ellmer.

### 4.7 Positioning statement (for README / CRAN Description)

"gptr is an agent harness that runs inside the R session: one function, `gptr()`, is both
an interactive console chat and an R expression that returns typed values; it evaluates
code in the caller's environment, records the session as a runnable R/Rmd/qmd/ipynb
document, and unifies generative models with System 1 decision models." Cite ellmer/btw/
corteza as related work in the vignette; avoid claims of being first.

---

## 5. Verified R prototypes

All run with `Rscript --vanilla` on R 4.4.3 (macOS arm64). `$T10` as defined above.
Run each script with `$T10` as the working directory (5.2 sources `mock_openai_server.R`
by relative path; 5.5 uses `.libPaths("rlib")`). The literal `"<$T10>/rlib"` strings in 5.3
and 5.4 are placeholders and must be replaced by the absolute path before running (as
printed they fail). Verifier re-ran every block of 5.2–5.5 as extracted from this report
(with that substitution) on ellmer 0.4.0 (system library) and 0.5.0 (`TRACK10_LIB=$T10/rlib`):
all ran to completion and reproduced the shown output (timings differ, see 5.3/5.7); the
scripts additionally print `[1] TRUE` from `srv$kill()`.

### 5.1 Evidence collection scripts

`md5check.R` (tarball integrity):

```r
setwd("src")
db <- readRDS("../cran_db2.rds"); db <- db[!duplicated(db$Package),]
f <- list.files(".", pattern = "tar[.]gz$")
for (x in f) {
  p <- sub("_.*", "", x); v <- sub("^[^_]+_(.*)[.]tar[.]gz$", "\\1", x)
  r <- db[db$Package == p, ]
  m <- unname(tools::md5sum(x))
  cat(sprintf("%-14s %-9s cran=%-9s md5match=%s\n", p, v, r$Version, identical(m, r$MD5sum)))
}
```

Observed: all 37 lines `md5match=TRUE` (LLMR 0.8.11, LLMRagent 0.8.1, agenticr 0.3.3,
agentr 0.2.8.4, aisdk 1.4.12, btw 1.5.0, chattr 0.3.1, chores 0.3.1, codriver 1.0.0,
commons 0.1.0, corteza 0.7.1, ellmer 0.5.0, gander 0.2.0, gptr 0.7.0, gptstudio 0.4.0,
harness 0.2.0, llm.api 0.1.9, llmflow 3.0.2, mall 0.2.0, mcplite 0.1.0, mcptools 1.0.3,
mini007 0.4.0, myownrobs 1.0.0, openai 0.4.1, pensar 0.7.0, ragnar 0.3.1, ravel 0.1.4,
rollama 0.3.1, rtemis.llm 0.8.7, saber 0.7.2, shinychat 0.5.0, streamy 0.2.1, tidyllm 0.6.0,
tidyprompt 0.4.0, tinyoauth 0.1.1, vitals 0.4.0, wf 0.0.1).

CRAN db refresh: executed `db <- tools::CRAN_package_db(); saveRDS(db, "cran_db2.rds")` →
`25273 rows; max published 2026-09-30`; btw 1.5.0 2026-09-09, ellmer 0.5.0 2026-09-04,
gptr 0.7.0 2025-04-05, mcptools 1.0.3 2026-09-18.

`archive.R`:

```r
f <- "archive.rds"
if (!file.exists(f)) download.file("https://cran.r-project.org/src/contrib/Meta/archive.rds", f, quiet = TRUE, mode = "wb")
a <- readRDS(f)
cat("archive entries:", length(a), "\n")
for (p in c("gptr","querychat","mcpr","claudeR","acquaint","side","gpttools","chatgpt","openai","ellmer","btw","mcptools","llm.api","corteza","agenticr","aisdk","hellmer","gptstudio","TheOpenAIR","askgpt","tidychatmodels","elmer")) {
  x <- a[[p]]
  if (is.null(x)) { cat(sprintf("%-12s: no archived versions\n", p)); next }
  cat(sprintf("%-12s: %d archived: %s\n", p, nrow(x), paste(sprintf("%s(%s)", basename(rownames(x)), format(x$mtime, "%Y-%m-%d")), collapse=", ")))
}
```

Observed (excerpt):

```text
archive entries: 28034
gptr        : 2 archived: gptr_0.5.0.tar.gz(2024-05-06), gptr_0.6.0.tar.gz(2024-05-07)
querychat   : 3 archived: querychat_0.2.0.tar.gz(2026-01-12), querychat_0.3.0.tar.gz(2026-06-01), querychat_0.4.0.tar.gz(2026-09-13)
mcpr        : no archived versions
claudeR     : no archived versions
acquaint    : no archived versions
side        : no archived versions
ellmer      : 10 archived: ellmer_0.1.0 (2025-01-09) … ellmer_0.4.2 (2026-07-13)
btw         : 6 archived: btw_1.0.0 (2025-11-04) … btw_1.4.0 (2026-08-04)
mcptools    : 7 archived: mcptools_0.1.0 (2025-07-18) … mcptools_1.0.2 (2026-08-22)
llm.api     : 5 archived; corteza: 3 archived; aisdk: 3 archived
hellmer     : 3 archived: hellmer_0.1.0 … hellmer_0.1.2(2025-04-17)   (no longer on CRAN)
```

cranlogs (executed `jsonlite::fromJSON("https://cranlogs.r-pkg.org/downloads/total/last-month/…")`):

```text
      package downloads      start        end
1        gptr       302 2026-08-30 2026-09-28
2      ellmer     13786
3         btw      1662
4    mcptools      2346
5     corteza       275
6     llm.api       303
7    agenticr       354
8       aisdk     17066
9     tidyllm       707
10     chattr      1654
11  gptstudio       885
12       LLMR       431
13    rollama       681
14     ragnar      1196
15     vitals       743
16  shinychat      3399
17       mall       435
18     chores       457
19     gander       630
20 tidyprompt       402
21 rtemis.llm       241
22      ravel       304
23  myownrobs       277
gptr total 2024-05-01..2026-09-28: 11125
```

Private installs (executed `install_btw.R`, 2.57 min, into `$T10/rlib`): btw 1.5.0, ellmer
0.5.0, frontmatter 0.3.0, httr2 1.3.0, mcptools 1.0.3, nanonext 1.10.3, pkgsearch 3.1.5,
rlang 1.3.0, skimr 2.2.2, tomledit 0.1.1, yaml12 0.2.0.

### 5.2 ellmer bridge prototypes (mock server; no network beyond localhost)

`mock_openai_server.R` (run in a separate process with `callr::r_bg`):

```r
args <- commandArgs(trailingOnly = TRUE)
port <- as.integer(args[[1]])
log_file <- args[[2]]
handle <- function(req) {
  body <- rawToChar(req$rook.input$read())
  cat(body, "\n", file = log_file, append = TRUE, sep = "")
  j <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  msgs <- j$messages
  last <- msgs[[length(msgs)]]
  if (identical(last$role, "tool")) {
    msg <- list(role = "assistant", content = paste0("Tool said: ", last$content))
    finish <- "stop"
  } else {
    msg <- list(role = "assistant", content = NULL,
      tool_calls = list(list(id = "call_1", type = "function",
        `function` = list(name = "run_r", arguments = '{"code":"x_bridge <- sum(1:10); x_bridge"}'))))
    finish <- "tool_calls"
  }
  resp <- list(id = "chatcmpl-mock", object = "chat.completion", created = 0L, model = j$model,
    choices = list(list(index = 0L, message = msg, finish_reason = finish)),
    usage = list(prompt_tokens = 11L, completion_tokens = 7L, total_tokens = 18L))
  list(status = 200L, headers = list("Content-Type" = "application/json"),
       body = jsonlite::toJSON(resp, auto_unbox = TRUE, null = "null"))
}
srv <- httpuv::startServer("127.0.0.1", port, list(call = handle))
cat("listening\n")
while (TRUE) httpuv::service(100)
```

**(a) Single-step bridge — `proto_ellmer_bridge.R` (the approach that fails).**

```r
lib <- Sys.getenv("TRACK10_LIB")
if (nzchar(lib)) .libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(ellmer))
cat("ellmer version:", format(packageVersion("ellmer")), "\n")

schema_to_ellmer_type <- function(s, required = TRUE) {
  d <- s$description %||% NULL
  if (!is.null(s$enum)) return(type_enum(unlist(s$enum), description = d, required = required))
  switch(s$type %||% "string",
    string  = type_string(d, required = required),
    number  = type_number(d, required = required),
    integer = type_integer(d, required = required),
    boolean = type_boolean(d, required = required),
    array   = type_array(schema_to_ellmer_type(s$items %||% list(type = "string")), d, required = required),
    object  = {
      props <- s$properties %||% list()
      req <- unlist(s$required %||% list())
      args <- lapply(names(props), function(nm) schema_to_ellmer_type(props[[nm]], nm %in% req))
      names(args) <- names(props)
      do.call(type_object, c(list(.description = d, .required = required), args))
    },
    type_string(d, required = required))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

gptr_tool_to_ellmer_stub <- function(spec) {
  props <- spec$parameters$properties %||% list()
  req <- unlist(spec$parameters$required %||% list())
  args <- lapply(names(props), function(nm) schema_to_ellmer_type(props[[nm]], nm %in% req))
  names(args) <- names(props)
  # ToolDef() is only exported from ellmer 0.5.0; tool() works in 0.4.x and 0.5.x but
  # requires formals that match `arguments`, so build the stub's formals dynamically.
  stub <- rlang::new_function(
    rlang::pairlist2(!!!stats::setNames(rep(list(NULL), length(args)), names(args))),
    quote(stop("gptr stub: ellmer must never execute gptr tools")))
  tool(stub, name = spec$name, description = spec$description, arguments = args)
}

gptr_to_ellmer_turns <- function(messages) {
  turns <- list(); reqs <- list()
  for (m in messages) {
    if (m$role == "user") {
      turns[[length(turns) + 1]] <- UserTurn(list(ContentText(m$content[[1]]$text)))
    } else if (m$role == "assistant") {
      cs <- lapply(m$content, function(b) {
        if (b$type == "text") ContentText(b$text)
        else {
          r <- ContentToolRequest(id = b$id, name = b$name, arguments = b$arguments)
          reqs[[b$id]] <<- r
          r
        }
      })
      turns[[length(turns) + 1]] <- AssistantTurn(cs)
    } else if (m$role == "tool") {
      res <- ContentToolResult(value = if (!isTRUE(m$is_error)) m$content[[1]]$text,
                               error = if (isTRUE(m$is_error)) m$content[[1]]$text,
                               request = reqs[[m$tool_call_id]])
      n <- length(turns)
      if (n && S7::S7_inherits(turns[[n]], UserTurn) &&
          all(vapply(turns[[n]]@contents, S7::S7_inherits, logical(1), ContentToolResult))) {
        turns[[n]] <- UserTurn(c(turns[[n]]@contents, list(res)))
      } else turns[[n + 1]] <- UserTurn(list(res))
    }
  }
  turns
}

ellmer_turn_to_gptr <- function(turn) {
  content <- list()
  for (c in turn@contents) {
    if (S7::S7_inherits(c, ContentToolRequest)) {
      content[[length(content) + 1]] <- list(type = "tool_call", id = c@id, name = c@name, arguments = c@arguments)
    } else if (S7::S7_inherits(c, ContentThinking)) {
      content[[length(content) + 1]] <- list(type = "thinking", text = c@thinking)
    } else if (S7::S7_inherits(c, ContentText)) {
      content[[length(content) + 1]] <- list(type = "text", text = c@text)
    }
  }
  tk <- turn@tokens
  list(role = "assistant", content = content,
       usage = list(input = tk[[1]], output = tk[[2]], cached_input = tk[[3]], cost = turn@cost),
       stop_reason = if (any(vapply(content, function(b) b$type == "tool_call", logical(1)))) "tool_use" else "stop")
}

gptr_provider_ellmer <- function(chat) {
  stopifnot(inherits(chat, "Chat"))
  list(
    name = paste0("ellmer/", chat$get_provider()@name),
    model = chat$get_model(),
    step = function(messages, tools = list(), system = NULL) {
      ch <- chat$clone(deep = TRUE)
      ch$set_system_prompt(system)
      last <- messages[[length(messages)]]
      ch$set_turns(gptr_to_ellmer_turns(messages[-length(messages)]))
      ch$set_tools(lapply(tools, gptr_tool_to_ellmer_stub))
      ch$on_tool_request(function(request) {
        rlang::abort("stop ellmer tool loop", class = "gptr_ellmer_yield")
      })
      if (last$role == "user") {
        input <- list(last$content[[1]]$text)
      } else {  # trailing tool results are passed as ContentToolResult input
        tail_turns <- gptr_to_ellmer_turns(messages)
        input <- tail_turns[[length(tail_turns)]]@contents
      }
      tryCatch(do.call(ch$chat, c(input, list(echo = "none"))),
               gptr_ellmer_yield = function(cnd) NULL)
      ellmer_turn_to_gptr(ch$last_turn())
    }
  )
}

run_r_tool <- list(name = "run_r", description = "Evaluate R code in the live session",
  parameters = list(type = "object", properties = list(code = list(type = "string", description = "R code")),
                    required = list("code")))

gptr_agent_loop <- function(provider, prompt, envir, max_turns = 5) {
  msgs <- list(list(role = "user", content = list(list(type = "text", text = prompt))))
  for (i in seq_len(max_turns)) {
    a <- provider$step(msgs, tools = list(run_r_tool), system = "You are gptr.")
    msgs[[length(msgs) + 1]] <- a
    calls <- Filter(function(b) b$type == "tool_call", a$content)
    cat(sprintf("step %d: %d tool call(s); usage in=%s out=%s\n", i, length(calls), a$usage$input, a$usage$output))
    if (!length(calls)) break
    for (cl in calls) {
      out <- tryCatch(paste(capture.output(print(eval(parse(text = cl$arguments$code), envir = envir))), collapse = "\n"),
                      error = function(e) structure(conditionMessage(e), is_error = TRUE))
      msgs[[length(msgs) + 1]] <- list(role = "tool", tool_call_id = cl$id, tool_name = cl$name,
        is_error = isTRUE(attr(out, "is_error")), content = list(list(type = "text", text = as.character(out))))
    }
  }
  msgs
}

port <- 8765L
log_file <- tempfile(fileext = ".jsonl")
srv <- callr::r_bg(function(script, port, log) {
  commandArgs <- function(trailingOnly = TRUE) c(as.character(port), log)
  source(script, local = TRUE)
}, args = list(script = normalizePath("mock_openai_server.R"), port = port, log = log_file))
Sys.sleep(2)

chat <- chat_openai_compatible(base_url = sprintf("http://127.0.0.1:%d/v1", port), model = "mock-model",
                               credentials = function() "sk-test-not-a-real-key")
prov <- gptr_provider_ellmer(chat)
user_env <- new.env()
msgs <- gptr_agent_loop(prov, "Compute the sum of 1:10 in my session", envir = user_env)

cat("final assistant text:", msgs[[length(msgs)]]$content[[1]]$text, "\n")
cat("object created in caller env: x_bridge =", get("x_bridge", envir = user_env), "\n")
cat("original chat untouched, turns:", length(chat$get_turns()), "\n")
reqs <- readLines(log_file)
cat("requests received by mock server:", length(reqs), "\n")
second <- jsonlite::fromJSON(reqs[[2]], simplifyVector = FALSE)
cat("2nd request message roles:", paste(vapply(second$messages, `[[`, "", "role"), collapse = ","), "\n")
cat("2nd request tool message content:", second$messages[[length(second$messages)]]$content, "\n")
cat("tools sent:", jsonlite::toJSON(second$tools, auto_unbox = TRUE), "\n")
srv$kill()
cat("2nd request messages (full):\n"); print(jsonlite::toJSON(second$messages, auto_unbox = TRUE, pretty = TRUE))
```

First attempt (ellmer 0.4.0) with `ToolDef()` instead of `tool()` failed:
`Error in ToolDef(...) : could not find function "ToolDef"` (ToolDef not exported in 0.4.0).

Observed with ellmer 0.4.0 (after switching to `tool()`):

```text
ellmer version: 0.4.0
step 1: 1 tool call(s); usage in=11 out=7
step 2: 0 tool call(s); usage in=11 out=7
final assistant text: Tool said: [1] 55
object created in caller env: x_bridge = 55
original chat untouched, turns: 0
requests received by mock server: 2
2nd request message roles: system,user,assistant,tool,tool
2nd request tool message content: [1] 55
tools sent: [{"type":"function","function":{"name":"run_r","description":"Evaluate R code in the live session","strict":true,"parameters":{"type":"object","description":"","properties":{"code":{"type":"string","description":"R code"}},"required":["code"],"additionalProperties":false}}}]
2nd request messages (full):
 ... {"role":"assistant","tool_calls":[{"id":"call_1","function":{"name":"run_r",
      "arguments":"{\"code\":[\"x_bridge <- sum(1:10); x_bridge\"]}"},"type":"function"}]},
     {"role":"tool","content":"Tool calling failed with error Chat ended before the tool could be invoked.","tool_call_id":"call_1"},
     {"role":"tool","content":"[1] 55","tool_call_id":"call_1"}
```

Observed with ellmer 0.5.0 (`TRACK10_LIB=$T10/rlib`): identical except the arguments are
`"{\"code\":\"x_bridge <- sum(1:10); x_bridge\"}"` (no array). The duplicate tool message
is present in both versions. Conclusion: single-step bridging is not viable.

**(b) Delegate bridge — `proto_ellmer_bridge2.R` (works).**

```r
lib <- Sys.getenv("TRACK10_LIB")
if (nzchar(lib)) .libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(ellmer))
cat("ellmer version:", format(packageVersion("ellmer")), "\n")
`%||%` <- function(a, b) if (is.null(a)) b else a

schema_prop_to_type <- function(s, required = TRUE) {
  d <- s$description
  if (!is.null(s$enum)) return(type_enum(unlist(s$enum), d, required = required))
  switch(s$type %||% "string",
    string = type_string(d, required = required), number = type_number(d, required = required),
    integer = type_integer(d, required = required), boolean = type_boolean(d, required = required),
    array = type_array(schema_prop_to_type(s$items %||% list(type = "string")), d, required = required),
    type_string(d, required = required))
}

as_ellmer_tool <- function(spec, executor) {
  props <- spec$parameters$properties %||% list()
  req <- unlist(spec$parameters$required %||% list())
  args <- stats::setNames(lapply(names(props), function(n) schema_prop_to_type(props[[n]], n %in% req)), names(props))
  body <- rlang::expr({
    a <- as.list(environment())
    (!!executor$run)(!!spec$name, a[!vapply(a, is.null, logical(1))])
  })
  fn <- rlang::new_function(rlang::pairlist2(!!!stats::setNames(rep(list(NULL), length(args)), names(args))), body)
  tool(fn, name = spec$name, description = spec$description, arguments = args)
}

ellmer_turns_to_gptr <- function(turns) {
  out <- list()
  for (t in turns) {
    role <- t@role
    if (role == "system") next
    blocks <- list(); tool_results <- list()
    for (c in t@contents) {
      if (S7::S7_inherits(c, ContentToolResult)) {
        err <- c@error
        tool_results[[length(tool_results) + 1]] <- list(role = "tool", tool_call_id = c@request@id,
          tool_name = c@request@name, is_error = !is.null(err),
          content = list(list(type = "text", text = if (!is.null(err)) { if (inherits(err, "condition")) conditionMessage(err) else err } else paste(as.character(c@value), collapse = "\n"))))
      } else if (S7::S7_inherits(c, ContentToolRequest)) {
        blocks[[length(blocks) + 1]] <- list(type = "tool_call", id = c@id, name = c@name, arguments = c@arguments)
      } else if (S7::S7_inherits(c, ContentThinking)) {
        blocks[[length(blocks) + 1]] <- list(type = "thinking", text = c@thinking)
      } else if (S7::S7_inherits(c, ContentText)) {
        blocks[[length(blocks) + 1]] <- list(type = "text", text = c@text)
      }
    }
    if (length(tool_results)) out <- c(out, tool_results)
    if (length(blocks)) {
      m <- list(role = role, content = blocks)
      if (role == "assistant") m$usage <- list(input = t@tokens[[1]], output = t@tokens[[2]], cached_input = t@tokens[[3]], cost = t@cost)
      out[[length(out) + 1]] <- m
    }
  }
  out
}

gptr_run_via_ellmer <- function(chat, prompt, tools, envir, permit, max_tool_rounds = 5, on_event = function(e) NULL) {
  ch <- chat$clone(deep = TRUE)
  executor <- list(run = function(name, args) {
    if (name == "run_r") {
      val <- withVisible(eval(parse(text = args$code), envir = envir))
      paste(utils::capture.output(if (val$visible) print(val$value)), collapse = "\n")
    } else stop("unknown tool ", name)
  })
  ch$set_tools(lapply(tools, as_ellmer_tool, executor = executor))
  rounds <- 0
  ch$on_tool_request(function(request) {
    rounds <<- rounds + 1
    if (rounds > max_tool_rounds) rlang::abort("turn budget exhausted", class = "gptr_budget")
    on_event(list(type = "tool_request", name = request@name, args = request@arguments))
    if (!permit(request@name, request@arguments)) tool_reject("Denied by gptr permission mode 'manual'.")
  })
  ch$on_tool_result(function(result) on_event(list(type = "tool_result", error = !is.null(result@error))))
  status <- tryCatch(withCallingHandlers({ ch$chat(prompt, echo = "none"); "ok" }, ellmer_tool_failure = function(w) invokeRestart("muffleWarning")), gptr_budget = function(e) "budget")
  list(status = status, messages = ellmer_turns_to_gptr(ch$get_turns()), chat = ch)
}

run_r_tool <- list(name = "run_r", description = "Evaluate R code in the live session",
  parameters = list(type = "object", properties = list(code = list(type = "string", description = "R code")), required = list("code")))

port <- 8766L
log_file <- tempfile(fileext = ".jsonl")
srv <- callr::r_bg(function(script, port, log) {
  commandArgs <- function(trailingOnly = TRUE) c(as.character(port), log)
  source(script, local = TRUE)
}, args = list(script = normalizePath("mock_openai_server.R"), port = port, log = log_file))
Sys.sleep(2)
chat <- chat_openai_compatible(base_url = sprintf("http://127.0.0.1:%d/v1", port), model = "mock-model",
                               credentials = function() "sk-test-not-a-real-key")

cat("\n--- run 1: permission granted ---\n")
env1 <- new.env()
r1 <- gptr_run_via_ellmer(chat, "sum 1:10", list(run_r_tool), env1, permit = function(...) TRUE,
                          on_event = function(e) cat("event:", e$type, "\n"))
cat("status:", r1$status, "| x_bridge in caller env:", get0("x_bridge", envir = env1), "\n")
str(lapply(r1$messages, function(m) c(role = m$role, first = substr(m$content[[1]][[if (m$content[[1]]$type == "tool_call") "name" else "text"]], 1, 40))))

cat("\n--- run 2: permission denied ---\n")
env2 <- new.env()
r2 <- gptr_run_via_ellmer(chat, "sum 1:10", list(run_r_tool), env2, permit = function(...) FALSE)
cat("status:", r2$status, "| x_bridge exists:", exists("x_bridge", envir = env2, inherits = FALSE), "\n")
cat("final text:", r2$messages[[length(r2$messages)]]$content[[1]]$text, "\n")

cat("\n--- run 3: budget of 0 tool rounds ---\n")
r3 <- gptr_run_via_ellmer(chat, "sum 1:10", list(run_r_tool), new.env(), permit = function(...) TRUE, max_tool_rounds = 0)
cat("status:", r3$status, "\n")

reqs <- readLines(log_file)
second <- jsonlite::fromJSON(reqs[[2]], simplifyVector = FALSE)
cat("\nrequests seen by server:", length(reqs), "\n")
cat("run-1 2nd request roles:", paste(vapply(second$messages, `[[`, "", "role"), collapse = ","), "\n")
cat("run-1 2nd request replayed tool-call arguments JSON:", second$messages[[2]]$tool_calls[[1]]$`function`$arguments, "\n")
srv$kill()
```

Observed (ellmer 0.5.0; 0.4.0 identical except the last line):

```text
ellmer version: 0.5.0

--- run 1: permission granted ---
event: tool_request
event: tool_result
status: ok | x_bridge in caller env: 55
List of 4
 $ : Named chr [1:2] "user" "sum 1:10"
 $ : Named chr [1:2] "assistant" "run_r"
 $ : Named chr [1:2] "tool" "[1] 55"
 $ : Named chr [1:2] "assistant" "Tool said: [1] 55"

--- run 2: permission denied ---
status: ok | x_bridge exists: FALSE
final text: Tool said: Tool calling failed with error Tool call rejected. Denied by gptr permission mode 'manual'.

--- run 3: budget of 0 tool rounds ---
status: budget

requests seen by server: 5
run-1 2nd request roles: user,assistant,tool
run-1 2nd request replayed tool-call arguments JSON: {"code":"x_bridge <- sum(1:10); x_bridge"}
```

ellmer 0.4.0 last line: `run-1 2nd request replayed tool-call arguments JSON:
{"code":["x_bridge <- sum(1:10); x_bridge"]}` — the argument-boxing bug in ellmer's *own*
loop. Confirmed cause (executed `S7::method(ellmer:::as_json, list(ellmer:::ProviderOpenAICompatible,
ellmer::ContentToolRequest))` on 0.4.0 → body `json_args <- jsonlite::toJSON(x@arguments)`).
Before muffling, ellmer printed `Warning message: Failed to evaluate 1 tool call. x [run_r
(call_1)]: Tool call rejected. …` for run 2.

### 5.3 Object description comparison — `proto_describe.R`

```r
lib <- "<$T10>/rlib"
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages({ library(ellmer); library(btw) })
cat("ellmer", format(packageVersion("ellmer")), "| btw", format(packageVersion("btw")), "\n\n")
cat("==== ellmer::df_schema(mtcars[1:4]) ====\n"); print(df_schema(mtcars[1:4]))
cat("\n==== ellmer::df_schema(iris) ====\n"); print(df_schema(iris))
cat("\n==== btw::btw_this(mtcars) ====\n")
x <- btw_this(mtcars); cat(head(x, 8), sep = "\n"); cat("... (", length(x), "lines )\n")
set.seed(1)
big <- data.frame(id = seq_len(2e6), g = sample(letters, 2e6, TRUE), x = rnorm(2e6), y = runif(2e6),
                  d = as.Date("2020-01-01") + sample(0:1000, 2e6, TRUE))
cat("\n==== btw::btw_this(big) (2e6 x 5, skim) ====\n")
t_btw <- system.time(xb <- btw_this(big)); cat(xb, sep = "\n")
cat("btw_this(big) elapsed:", t_btw[["elapsed"]], "s\n")
cat("\n==== btw::btw() on an environment with several objects ====\n")
e <- new.env(); e$fit <- lm(mpg ~ wt, mtcars); e$f <- function(a, b = 2) a + b
e$note <- c("alpha", "beta"); e$lst <- list(a = 1:3, b = "x")
t_env <- system.time(out <- btw_this(e)); cat(out, sep = "\n")
cat("btw_this(env) elapsed:", t_env[["elapsed"]], "s\n")
cat("\n==== ellmer::df_schema(big) ====\n")
t_ell <- system.time(ds <- df_schema(big)); print(ds); cat("df_schema(big) elapsed:", t_ell[["elapsed"]], "s\n")

gptr_describe <- function(x, name = deparse(substitute(x)), sample_n = 1000L, max_cols = 30L) {
  cls <- paste(class(x), collapse = "/")
  sz <- if (is.atomic(x) || is.data.frame(x) || isS4(x) || length(x) < 1e5) format(utils::object.size(x), units = "auto") else "?"
  hdr <- sprintf("%s <%s> %s", name, cls, sz)
  one_col <- function(v) {
    n <- length(v)
    s <- if (n > sample_n) v[unique(round(seq(1, n, length.out = sample_n)))] else v
    info <- if (is.numeric(s)) sprintf("range~[%s, %s]", format(min(s, na.rm = TRUE), digits = 4), format(max(s, na.rm = TRUE), digits = 4))
            else if (is.factor(s)) sprintf("%d levels", nlevels(s))
            else if (is.character(s)) sprintf("e.g. %s", paste(encodeString(utils::head(unique(s), 3), quote = '"'), collapse = ", "))
            else if (inherits(s, "Date")) sprintf("range~[%s, %s]", min(s, na.rm = TRUE), max(s, na.rm = TRUE))
            else ""
    sprintf("%s%s", paste(class(v), collapse = "/"), if (nzchar(info)) paste0(", ", info) else "")
  }
  body <- if (is.data.frame(x)) {
    cols <- utils::head(names(x), max_cols)
    c(sprintf("  %d rows x %d cols%s", nrow(x), ncol(x), if (ncol(x) > max_cols) sprintf(" (first %d shown)", max_cols) else ""),
      sprintf("  $ %s: %s", cols, vapply(x[cols], one_col, "")))
  } else if (isS4(x)) {
    sprintf("  S4 slots: %s", paste(utils::head(methods::slotNames(x), 20), collapse = ", "))
  } else if (is.function(x)) {
    sprintf("  function(%s)", paste(names(formals(x)), collapse = ", "))
  } else if (is.list(x)) {
    c(sprintf("  list of %d", length(x)),
      sprintf("  $ %s: %s", utils::head(names(x) %||% seq_along(x), 10), vapply(utils::head(x, 10), function(el) paste(class(el), collapse = "/"), "")))
  } else if (is.atomic(x)) {
    sprintf("  length %d: %s", length(x), one_col(x))
  } else ""
  paste(c(hdr, body), collapse = "\n")
}
`%||%` <- function(a, b) if (is.null(a)) b else a
cat("\n==== gptr_describe prototype ====\n")
t_g <- system.time(g <- gptr_describe(big)); cat(g, "\n"); cat("gptr_describe(big) elapsed:", t_g[["elapsed"]], "s\n")
cat(gptr_describe(e$fit, "fit"), "\n"); cat(gptr_describe(e$f, "f"), "\n"); cat(gptr_describe(e$lst, "lst"), "\n")
```

Observed:

```text
ellmer 0.5.0 | btw 1.5.0

==== ellmer::df_schema(mtcars[1:4]) ====
[1] | A data frame with 32 rows and 4 columns:
    | * mpg: numeric with range [10.4, 33.9], and 0 NAs
    | * cyl: numeric with range [4, 8], and 0 NAs
    | * disp: numeric with range [71.1, 472], and 0 NAs
    | * hp: numeric with range [52, 335], and 0 NAs

==== ellmer::df_schema(iris) ====
[1] | A data frame with 150 rows and 5 columns:
    | * Sepal.Length: numeric with range [4.3, 7.9], and 0 NAs
    | * Sepal.Width: numeric with range [2, 4.4], and 0 NAs
    | * Petal.Length: numeric with range [1, 6.9], and 0 NAs
    | * Petal.Width: numeric with range [0.1, 2.5], and 0 NAs
    | * Species: nominal with 0 NAs, and 3 permitted values ("setosa", "versicolor", "virginica")

==== btw::btw_this(mtcars) ====
```json
{"n_cols":11,"n_rows":32,"groups":[],"class":"data.frame","columns":{"mpg":{"variable":"mpg","type":"numeric","mean":20.0906,"sd":6.0269,"p0":10.4,"p25":15.425,"p50":19.2,"p75":22.8,"p100":33.9}, … "carb":{…}}}
```
... ( 1 lines )

==== btw::btw_this(big) (2e6 x 5, skim) ====
```json
{"n_cols":5,"n_rows":2000000,"groups":[],"class":"data.frame","columns":{"d":{"variable":"d","type":"Date","min":"2020-01-01","max":"2022-09-27","median":"2021-05-15","n_unique":1001},"g":{"variable":"g","type":"character","min":1,"max":1,"empty":0,"n_unique":26,"values":["b","e","f","i","j","k","l","m","n","o"]},"id":{…"mean":1000000.5…},"x":{…},"y":{…}}}
```
btw_this(big) elapsed: 2.538 s

==== btw::btw() on an environment with several objects ====
## Context

f
```r
function (a, b = 2)
a + b
```

```r
fit
#>
#> Call:
#> lm(formula = mpg ~ wt, data = mtcars)
#>
#> Coefficients:
#> (Intercept)           wt
#>      37.285       -5.344
#>
```

```r
lst
#> $a
#> [1] 1 2 3
#>
#> $b
#> [1] "x"
#>
```

```r
note
#> [1] "alpha" "beta"
```
btw_this(env) elapsed: 0.005 s

==== ellmer::df_schema(big) ====
[1] | A data frame with 2000000 rows and 5 columns:
    | * id: integer with range [1, 2000000], and 0 NAs
    | * g: character with 0 NAs, and 26 unique values
    | * x: numeric with range [-5.042, 5.372], and 0 NAs
    | * y: numeric with range [2.333e-07, 1], and 0 NAs
    | * d: date with range [2020-01-01, 2022-09-27], and 0 NAs
df_schema(big) elapsed: 0.224 s

==== gptr_describe prototype ====
big <data.frame> 68.7 Mb
  2000000 rows x 5 cols
  $ id: integer, range~[1, 2000000]
  $ g: character, e.g. "y", "e", "j"
  $ x: numeric, range~[-2.975, 3.078]
  $ y: numeric, range~[0.001042, 0.9999]
  $ d: Date, range~[2020-01-02, 2022-09-27]
gptr_describe(big) elapsed: 0.078 s
fit <lm> 24.9 Kb
  list of 12
  $ coefficients: numeric
  … (10 more element lines)
f <function> 728 bytes
  function(a, b)
lst <list> 528 bytes
  list of 2
  $ a: integer
  $ b: character
```

Note the trade-off visible in the output: the sampled ranges are approximate (x range
−2.975..3.078 vs true −5.042..5.372) and the list-level view of `lm` is less informative
than its `print()` — hence the design in 4.4 (sample + print under budget).

### 5.4 Importing ellmer tools — `proto_import_ellmer_tools.R`

```r
.libPaths(c("<$T10>/rlib", .libPaths()))
suppressPackageStartupMessages({ library(ellmer); library(btw) })
`%||%` <- function(a, b) if (is.null(a)) b else a
ellmer_type_to_schema <- function(t) {
  d <- if (length(t@description) && nzchar(t@description)) t@description else NULL
  s <- if (S7::S7_inherits(t, TypeEnum)) list(type = "string", enum = as.list(t@values))
  else if (S7::S7_inherits(t, TypeArray)) list(type = "array", items = ellmer_type_to_schema(t@items))
  else if (S7::S7_inherits(t, TypeObject)) {
    props <- lapply(t@properties, ellmer_type_to_schema)
    req <- names(Filter(function(p) isTRUE(p@required), t@properties))
    c(list(type = "object", properties = if (length(props)) props else structure(list(), names = character())),
      if (length(req)) list(required = as.list(req)))
  }
  else if (S7::S7_inherits(t, TypeJsonSchema)) t@json
  else list(type = t@type)
  if (!is.null(d)) s$description <- d
  s
}
import_ellmer_tool <- function(td) {
  stopifnot(S7::S7_inherits(td, ToolDef))
  list(name = td@name, description = td@description,
    parameters = ellmer_type_to_schema(td@arguments),
    read_only = isTRUE(td@annotations$read_only_hint),
    run = function(args) {
      res <- do.call(td, args)
      if (S7::S7_inherits(res, ContentToolResult)) {
        if (!is.null(res@error)) stop(if (inherits(res@error, "condition")) conditionMessage(res@error) else res@error)
        res <- res@value
      }
      if (S7::S7_inherits(res, Content)) contents_text(res) else paste(as.character(res), collapse = "\n")
    })
}
tools <- lapply(btw_tools(c("docs", "env")), import_ellmer_tool)
cat("imported", length(tools), "btw tools:", paste(vapply(tools, `[[`, "", "name"), collapse = ", "), "\n\n")
h <- tools[[which(vapply(tools, `[[`, "", "name") == "btw_tool_docs_help_page")]]
cat("JSON schema of", h$name, ":\n", jsonlite::toJSON(h$parameters, auto_unbox = TRUE, pretty = FALSE), "\n")
cat("read_only annotation:", h$read_only, "\n\n")
out <- h$run(list(package_name = "stats", topic = "sd"))
cat("gptr executed btw tool -> first 6 lines:\n"); cat(head(strsplit(out, "\n")[[1]], 6), sep = "\n")
```

Observed:

```text
imported 7 btw tools: btw_tool_docs_package_news, btw_tool_docs_package_help_topics, btw_tool_docs_help_page, btw_tool_docs_available_vignettes, btw_tool_docs_vignette, btw_tool_env_describe_data_frame, btw_tool_env_describe_environment

JSON schema of btw_tool_docs_help_page :
 {"type":"object","properties":{"package_name":{"type":"string","description":"The exact name of the package, e.g. 'shiny'. Can be an empty string to search for a help topic across all packages."},"topic":{"type":"string","description":"The topic_id or alias of the help page, e.g. 'withProgress' or 'incProgress'."},"_intent":{"type":"string","description":"The intent of the tool call that describes why you called this tool. This should be a single, short phrase that explains this tool call to the user."}},"required":["package_name","topic","_intent"]}
read_only annotation: TRUE

gptr executed btw tool -> first 6 lines:
## `help(package = "stats", "sd")`

### Standard Deviation

#### Description
```

(btw adds a required `_intent` argument to its tools; its implementation defaults it, so
gptr may omit it when calling directly.)

### 5.5 Tool-schema size — `tool_schema_size.R` (uses one ellmer internal for measurement only)

```r
.libPaths(c("rlib", .libPaths()))
suppressPackageStartupMessages({ library(ellmer); library(btw) })
prov <- ellmer:::ProviderAnthropic(name = "Anthropic", base_url = "x", credentials = function() "x", beta_headers = character(), cache = "none")
size <- function(tools) {
  js <- lapply(tools, function(t) ellmer:::as_json(prov, t))
  txt <- jsonlite::toJSON(js, auto_unbox = TRUE)
  c(n_tools = length(tools), chars = nchar(txt), approx_tokens = round(nchar(txt) / 4))
}
options(btw.run_r.enabled = TRUE)
all <- btw_tools()
print(rbind(btw_default_30_plus_run_r = size(all),
            btw_files_env_run = size(btw_tools(c("files", "env", "run"))),
            btw_run_r_only = size(btw_tools("run"))))
```

Observed:

```text
                          n_tools chars approx_tokens
btw_default_30_plus_run_r      31 46235         11559
btw_files_env_run              10 17455          4364
btw_run_r_only                  1  2679           670
```

Also observed: `btw_tools()` default = 30 tools (list in 2.3); `btw_tools("run")` →
`btw_tool_run_r`; with `options(btw.run_r.enabled = TRUE)` run_r joins the default set.

### 5.6 Dependency closures — `deps2.R` / `deps_table.R`

```r
db <- readRDS("cran_db2.rds"); db <- db[!duplicated(db$Package), ]; rownames(db) <- db$Package
base_pk <- rownames(installed.packages(priority = "base"))
dbm <- as.matrix(db[, c("Package","Depends","Imports","LinkingTo","Suggests","Enhances")])
closure <- function(pk) {
  d <- unique(unlist(tools::package_dependencies(pk, db = dbm, which = c("Depends","Imports","LinkingTo"), recursive = TRUE)))
  setdiff(union(d, pk), base_pk)
}
# show(label, pk): prints length(closure) and number with NeedsCompilation == "yes"
```

Observed (counts *include* the named packages themselves):

```text
ellmer                                       n= 26  compiled=16
     R6, Rcpp, S7, askpass, cli, coro, curl, ellmer, fastmap, glue, httr2, jsonlite, later, lifecycle, magrittr, openssl, otel, pillar, pkgconfig, promises, rlang, sys, tibble, utf8, vctrs, withr
httr2                                        n= 13  compiled= 9
curl + jsonlite                              n=  2  compiled= 2
gptr D-20 {httr2,jsonlite,cli,processx}      n= 16  compiled=12
     R6, askpass, cli, curl, glue, httr2, jsonlite, lifecycle, magrittr, openssl, processx, ps, rlang, sys, vctrs, withr
gptr alt {curl,jsonlite,processx}            n=  5  compiled= 4
     R6, curl, jsonlite, processx, ps
gptr D-20 + R6 + callr                       n= 18  compiled=12
btw 71/41, mcptools 32/21, shinychat 44/27, vitals 36/22, ragnar 49/31, corteza 14/5,
llm.api 5/3, aisdk 25/17, agenticr 13/10, tidyllm 33/22, LLMR 39/23, chattr 51/31,
gptstudio 64/33, rtemis.llm 22/15
ellmer closure minus gptr-D20 closure:  Rcpp, S7, coro, ellmer, fastmap, later, otel, pillar, pkgconfig, promises, tibble, utf8
```

btw's Rust-dependent chain (VERIFIED from CRAN db): `frontmatter` (NeedsCompilation yes;
Imports cpp11, rlang, tomledit, yaml12) → `tomledit` (SystemRequirements "Cargo (Rust's
package manager), rustc") and `yaml12` ("Cargo (Rust's package manager), rustc >= 1.71.0,
xz. On Windows ARM64, source installs also require Microsoft C++ Build Tools with ARM64
components.").

### 5.7 Namespace load times (executed, 3 fresh processes each)

(Verifier re-run under concurrent load, httr2 1.3.0/ellmer 0.5.0/btw 1.5.0 from `$T10/rlib`:
jsonlite 0.013–0.017, curl 0.007–0.012, httr2 0.185–0.217, processx 0.017–0.063, ellmer
0.216–0.251, btw 0.719–0.786 s; same new-namespace counts. Relative ordering confirmed;
absolute values are load dependent.)

```text
jsonlite  0.009 / 0.014 / 0.015 s   (1 new namespace)
curl      0.007 / 0.007 / 0.006 s   (1)
httr2     0.143 / 0.114 / 0.125 s   (9)
processx  0.012 / 0.011 / 0.020 s   (2)
ellmer    0.150 / 0.154 / 0.157 s   (12)
btw       0.464 / 0.448 / 0.476 s   (16)
```

### 5.8 ellmer internals across versions (executed)

```text
0.4.0 chat_body            (provider, stream, turns, tools, type)
0.4.0 chat_request         (provider, stream, turns, tools, type)
0.4.0 value_turn           (provider, ...)
0.4.0 stream_parse         (provider, event)
Error ... object 'stream_content' not found          # absent in 0.4.0
0.5.0 chat_body            (provider, model, stream, turns, tools, type)
0.5.0 chat_request         (provider, model, stream, turns, tools, type)
0.5.0 value_turn           (provider, model, result, has_type)
0.5.0 stream_parse         (provider, event)
0.5.0 stream_content       (provider, event, completion)
0.5.0 stream_merge_chunks  (provider, result, chunk)
0.5.0 chat_params          (provider, params)
0.5.0 base_request         (provider)
```

`S7:::registrar` (printed) resolves external generics with
`ns <- asNamespace(generic$package); … get(generic$name, envir = ns, inherits = FALSE)` —
i.e. non-exported generics are reachable.

### 5.9 Collision scans — `collide_local2.R`, `collide_runiverse.R`

`collide_local2.R` scans `Meta/nsInfo.rds` exports (plus `getNamespaceExports()` for
packages with exportPattern) of all installed packages and parses `export()` lines of the
37 tarballs. Observed: "installed packages scanned: 613 ; tarballs scanned: 37" and:

```text
gptr           -
agent          LLMRagent, llm.api
tool           aisdk, ellmer, mcplite
classify       admisc
ask            gtools
chat           corteza, ellmer, gptstudio, llm.api, rollama, tidyllm
prompt         utils
model          aisdk
session        rvest
provider       GenomeInfoDb
pick           dplyr
rank           BiocGenerics, bit64
score          BiocGenerics, ade4, lava, rtracklayer
extract        R.utils, grr, magrittr, stringdist, tidyr
plan           SeuratObject, future
mcp            multcomp
read_file      brio, readr
write_file     brio, readr
edit_file      usethis
history        renv, utils
setup          harness, testthat
config         httr, plotly, renv
claude         tidyllm
codex          vitals
gemini         tidyllm
claude_code    vitals
serve          corteza
turn           corteza
new_session    corteza
create_agent   aisdk, llm.api, rtemis.llm
live_console   ellmer
interpolate    e1071, ellmer, generics
params         S4Vectors, ellmer
type_string    ellmer, mcplite, rollama
type_boolean   ellmer, mcplite, rollama
type_enum      ellmer, mcplite, rollama
tool_reject    ellmer
(all other candidates: -)
```

`collide_runiverse.R` queries `https://r-universe.dev/api/search?q=exports:<name>&limit=100`;
full output in `$T10/collide_runiverse2.txt` (summarised in 2.10). Every `gptr*` query
returned `total=0`.

### 5.10 Things I could not run

- Real provider calls (not allowed): the delegate bridge was only exercised against a mock
  OpenAI-compatible server with non-streaming JSON; streaming through the bridge and
  Anthropic/Gemini wire formats were not tested.
- Windows: nothing was executed on Windows; Windows statements are from CRAN check pages and
  package source.
- GitHub code search for `library(gptr)` failed with HTTP 403 rate limit.

---

## 6. CRAN and cross-platform considerations

1. **Global environment.** btw (`global_env()`), corteza (`globalenv()`), agenticr
   (`.GlobalEnv`) all write to the global environment at the user's request and pass CRAN.
   gptr's `parent.frame()` design (D-04) avoids naming `.GlobalEnv` at all; keep it that way
   so the "Packages should not modify the global environment" sentence is never at issue.
2. **Files.** Cache/config/credentials under `tools::R_user_dir("gptr", …)` (ellmer,
   tinyoauth, corteza all do). Project `.gptr/` only after explicit init or interactive
   confirmation ("Limited exceptions may be allowed in interactive sessions if the package
   obtains confirmation from the user"). Restrict file tools to the project root by default
   as btw does (`check_path_within_current_wd`), with an explicit override.
3. **No `:::`** into ellmer (or any package) in package code; the bridge uses only
   exported API. The S7 external-generic route to ellmer internals is technically possible
   but should not be used (unstable signatures, 5.8).
4. **Tests/examples offline.** Use a built-in fake provider and a local mock server
   (pattern in 5.2: `callr::r_bg` + `httpuv`); `skip_on_cran()` for anything else;
   ellmer-bridge tests `skip_if_not_installed("ellmer", "0.5.0")`. querychat's archival
   (2026-09-27) shows the cost of unaddressed check issues.
5. **Cores.** `parallel_chat`-style fan-out uses HTTP concurrency (not cores); if gptr uses
   `callr`/worker processes in tests, cap at 2.
6. **Windows specifics.**
   - Never assume bash; corteza had to search Rtools, then Git for Windows, because
     `C:\Windows\System32\bash.exe` is the WSL launcher (`srcv/corteza/R/tool-impl.R:569-575`).
     gptr's shell tool (off by default) should use `processx` with `cmd.exe`/PowerShell on
     Windows (ravel builds a PowerShell command line for Copilot on Windows,
     `srcv/ravel/R/providers_copilot.R:65`).
   - MCP clients on Windows may need the full path to `Rscript.exe` (mcptools docs; 2.6).
   - btw's user-level discovery on Windows also looks under R's `~` (usually `Documents`)
     as well as the user profile (btw NEWS 1.4.0) — gptr should do the same for
     `~/.gptr`-style paths or, better, use `R_user_dir`.
   - Avoid dependencies needing Rust (btw's `tomledit`/`yaml12`), and system libraries
     (RCurl in the old gptr needs libcurl dev headers on Linux; the new version drops RCurl).
   - mcptools' per-user sockets are filesystem sockets on Linux/macOS; on Windows mcptools
     uses nanonext named pipes (`ipc://mcptools-<user>-socket`), which its own code comments
     call "not a security boundary" (`srcv/mcptools/R/socket-dir.R:150-160`,
     `R/socket-auth.R`) — if gptr serves MCP to CLI providers, prefer stdio or loopback TCP
     with a token, testable on all OSes.
7. **Encoding.** btw strips ANSI (`cli::ansi_strip`) from captured output before sending to
   models; do the same (Windows consoles and knitr produce different escape handling).
8. **R version.** ellmer and httr2 require R >= 4.1 — consistent with D-23.

---

## 7. Risks, pitfalls, open questions

1. **Competitive risk.** Posit Assistant (commercial, IDE-integrated), btw+ellmer (Posit,
   open) and corteza (open, CRAN) overlap substantially. gptr must lead with its
   distinctive features (gateway-as-expression, System 1, document-as-history, caller-env
   evaluation) or risk being seen as another chat wrapper.
2. **Bridge fragility.** The delegate bridge depends on `on_tool_request` running *before*
   argument conversion and on `tool_reject()`/abort semantics (`srcv/ellmer/R/chat-tools.R:
   44-77, 282-295`); a future ellmer could change these. Pin `ellmer (>= 0.5.0)` and keep a
   CI job against ellmer's GitHub main.
3. **Duplicate tool results.** Unknown which providers reject two results for one
   `tool_call_id` (UNCERTAIN); irrelevant if gptr never uses single-step mode.
4. **Price data.** ellmer's table is derived from litellm; vendoring litellm data requires
   an MIT attribution and a refresh strategy; prices change weekly.
5. **Subscription routes.** llm.api demonstrates Claude-plan OAuth is technically easy and
   CRAN accepted it, but Anthropic's terms prohibit it for third-party developers; gptr must
   use the official `claude` binary. OpenAI's position on third-party use of ChatGPT-plan
   Codex OAuth was not researched here (track 08).
6. **Name `gptr`.** The package name suggests "GPT"; the new scope is provider-agnostic.
   Renaming is effectively impossible on CRAN; the Title/Description must carry the new
   meaning.
7. **Old-API users.** ~300 downloads/month will hit removed functions. S-7 forbids shims;
   consider at least a NEWS entry and a README section "Upgrading from 0.7.0".
8. **Maintainer e-mail.** If it changes from the address in DESCRIPTION, confirmation from
   the previous address is requested by CRAN.
9. **Open:** whether gptr should offer `format = "btw"` in its describer when btw is
   installed; whether to export `gptr_tools_as_ellmer()` in 1.0.0 or later; whether ellmer's
   `$stream(stream = "content")` yields enough events for gptr's console in delegate mode.
10. **Open:** r-universe exports search is incomplete (missed CRAN's corteza/llm.api for
    `chat`); a truly exhaustive CRAN-wide export scan would need all 25k NAMESPACE files.

---

## 8. Sources

Local source (CRAN tarballs, MD5-verified, extracted to `$T10/srcv/`):
- ellmer 0.5.0: `R/chat.R`, `R/provider.R`, `R/turns.R`, `R/content.R`, `R/types.R`,
  `R/tools-def.R`, `R/chat-tools.R`, `R/httr2.R`, `R/parallel-chat.R`, `R/batch-chat.R`,
  `R/live.R`, `R/tokens.R`, `R/prices.R`, `R/sysdata.rda`, `R/stream-controller.R`,
  `R/tool-context.R`, `R/content-replay.R`, `R/schema.R`, `R/content-image.R`,
  `R/provider-any.R`, `R/provider-claude.R`, `R/provider-openai-compatible.R`,
  `R/utils-auth.R`, `R/utils.R`, `NAMESPACE`, `NEWS.md`, `DESCRIPTION`.
- btw 1.5.0: `R/btw.R`, `R/btw_this.R`, `R/tool-env.R`, `R/tool-env-df.R`, `R/tool-run.R`,
  `R/tools.R`, `R/btw_client.R`, `R/mcp.R`, `R/tool-files-read.R`,
  `R/tool-agent-subagent.R`, `NEWS.md`, `NAMESPACE`.
- mcptools 1.0.3: `R/server.R`, `R/session.R`, `R/tools.R`, `R/client.R`, `NEWS.md`,
  `vignettes/server.Rmd`.
- corteza 0.7.1: `R/chat.R`, `R/tool-impl.R`, `R/handles.R`, `R/subagent.R`, `R/session.R`,
  `R/permissions.R`, `R/plan-mode.R`, `R/policy.R`, `NAMESPACE`, `NEWS.md`.
- llm.api 0.1.9: `R/anthropic-claude.R`, `R/openai-codex.R`, `R/agent.R`, `R/chat.R`,
  `NEWS.md`; tinyoauth 0.1.1: `R/anthropic.R`, `R/openai_codex.R`, `R/cache.R`.
- agenticr 0.3.3 `R/tools.R`, `R/repl.R`, `README.md`; aisdk 1.4.12 `R/console.R`,
  `R/r_introspect_tools.R`, `R/r_context_tools.R`, `NEWS.md`; ravel 0.1.4
  `R/providers_openai.R`, `R/providers_copilot.R`, `R/auth.R`; tidyprompt 0.4.0
  `R/llm_providers.R`; tidyllm 0.6.0 `R/api_ellmer.R`; vitals 0.4.0 `R/solver-agent.R`;
  mall 0.2.0 `R/llm-verify.R`; LLMR 0.8.11 `R/logprobs.R`; rtemis.llm 0.8.7 `R/map.R`;
  commons 0.1.0 `README.md`; gptr 0.7.0 `DESCRIPTION`, `NAMESPACE`, `R/*.R`.
- Spec: `/Users/wanjun/Desktop/gptr/dev/spec/00-vision-brief.md`,
  `01-decision-register.md`, `02-north-star-examples.md`; research digest
  `/Users/wanjun/Desktop/gptr/dev/research/00-digest.md` (track 02/05/06 summaries).

Web (fetched 2026-09-29/30):
- https://cran.r-project.org/package=gptr
- https://cran.r-project.org/web/checks/check_results_gptr.html
- https://cran.r-project.org/src/contrib/Archive/gptr/
- https://crandb.r-pkg.org/gptr/all
- https://cran.r-project.org/src/contrib/Meta/archive.rds
- https://cran.r-project.org/web/packages/packages.rds (via `tools::CRAN_package_db()`)
- https://cran.r-project.org/package=querychat (archival note)
- https://cran.r-project.org/web/checks/check_results_ellmer.html
- https://cran.r-project.org/web/checks/check_results_corteza.html
- https://cran.r-project.org/web/packages/policies.html
- https://cranlogs.r-pkg.org/downloads/total/last-month/gptr,ellmer,btw,… and
  https://cranlogs.r-pkg.org/downloads/total/2024-05-01:2026-09-28/gptr
- https://r-universe.dev/api/search?q=exports:<name> (collision scan) and ?q=<terms>
- https://ellmer.tidyverse.org/reference/index.html
- https://opensource.posit.co/blog/2026-06-11_history-of-posit-data-science-agents/
- https://posit.co/products/ai
- https://www.r-bloggers.com/2026/08/posit-assistant-is-it-worth-the-switch/
- https://positron.posit.co/databot.html (search result listing)
- https://github.com/simonpcouch/side
- https://github.com/IMNMV/ClaudeR
- https://github.com/devOpifex/mcpr and https://mcpr.opifex.org/ (search results)
- https://tidyverse.org/blog/2025/07/mcptools-0-1-0/ (search result, acquaint rename)
- https://code.claude.com/docs/en/legal-and-compliance
- https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/
  (search result summary; policy wording taken from the Anthropic page above)

---

## Verification log

Adversarial fact-check, 2026-09-29/30, independent of the original author. Scratch:
`scratchpad/work/verify-10/` (fresh `tools::CRAN_package_db()` and `archive.rds` downloads,
tarballs re-extracted to `verify-10/srcx/` after re-checking all 37 MD5s against the fresh
CRAN db, prototype blocks extracted verbatim from section 5 of this report and re-run).
R 4.4.3, `Rscript --vanilla`; ellmer 0.4.0 = system library, ellmer 0.5.0 / btw 1.5.0 /
mcptools 1.0.3 = `$T10/rlib`. No paid API calls; only a localhost mock server.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | CRAN versions/publication dates/licences in table 2.2 (ellmer 0.5.0 2026-09-04, btw 1.5.0, mcptools 1.0.3, corteza 0.7.1, llm.api 0.1.9, aisdk 1.4.12, agenticr 0.3.3, …) | confirmed | fresh `CRAN_package_db()` |
| 2 | gptr 0.7.0: Imports jsonlite+RCurl, Packaged/Date-Publication, no reverse deps, X-CRAN-Comment NA | confirmed | fresh CRAN db |
| 3 | gptr/ellmer/corteza OK on all 13 check flavours | confirmed | CRAN check pages (updated 2026-09-30 03:56 CEST) |
| 4 | gptr archive 0.5.0/0.6.0; release counts ellmer 11, btw 7, mcptools 8, corteza 4, llm.api 6; querychat 0.2.0–0.4.0 archived | confirmed | `Meta/archive.rds` |
| 5 | querychat "Archived on 2026-09-27 as issues were not corrected in time" | confirmed | cran.r-project.org/package=querychat |
| 6 | Downloads: gptr 302/month, 11,125 since 2024-05-01; ellmer 13,786; aisdk 17,066 | confirmed | cranlogs API |
| 7 | 37 tarballs MD5-match CRAN | confirmed | `tools::md5sum` vs fresh db |
| 8 | "25,273 packages"; regex gives 184 hits | corrected (25,273 rows = 25,258 unique packages; the 184 needs the word-bounded regex, 261 without) | fresh db + `cran_search.R` |
| 9 | ellmer DESCRIPTION Depends/Imports/Suggests, 130 exports, 20,255 lines, authors, 24 reverse Imports | confirmed | tarball + CRAN db |
| 10 | Provider generics unexported; `chat_body`/`chat_request`/`value_turn` formals changed 0.4.0→0.5.0; `stream_content` absent in 0.4.0; S7 registrar uses `get(..., asNamespace())` | confirmed; "exports only Provider" corrected (Model is exported too) | `formals()` on both installs; NAMESPACE |
| 11 | `ToolDef` exported only from 0.5.0 | confirmed | `getNamespaceExports()` on both |
| 12 | `complete_dangling_tool_requests()` at `R/chat.R:1279-1300`, text at :1296; `chat_impl` loop has no round limit | confirmed | ellmer 0.5.0 source |
| 13 | `tool()`, `ToolDef`, `tool_reject()` signatures/class; name regex; `on_tool_request` runs before argument conversion | confirmed | `R/tools-def.R`, `R/chat-tools.R:44-77, 270-295` |
| 14 | `type_object(..., .additional_properties = FALSE)` | corrected (default is `deprecated()`) | `args(ellmer::type_object)` 0.5.0 |
| 15 | `params`, `parallel_chat[_structured]`, `batch_chat`, `chat`, `df_schema`, `content_image_plot`, `live_console/browser`, `tool_annotations`, Chat public methods | confirmed | `args()` / `Chat$public_methods` on 0.5.0 |
| 16 | Anthropic constants; "system prompt always gets cache_control"; "`ANTHROPIC_BASE_URL` with /v1 appended" | corrected (cache_control omitted when `cache = "none"`, default "5m"; /v1 appended only if absent) | `R/provider-claude.R:150-311, 1134-1151` |
| 17 | Claude native structured-output regex; default models; 22 `chat_*` constructors | confirmed; clarified that `chat_github()` is defunct (21 usable) | source grep + exports |
| 18 | Price table 1,401 rows with per-provider counts, URL, `R_user_dir("ellmer","cache")`, litellm weekly refresh | confirmed (weekly workflow only via code comment `R/prices.R:5-6`) | `sysdata.rda`, `R/prices.R` |
| 19 | 0.4.0 boxes tool-call args; 0.5.0 fixes via `to_json(auto_unbox = TRUE)` | confirmed | `body(S7::method(...))` on 0.4.0; 0.5.0 source; wire log |
| 20 | Prototype 5.2(a) single-step bridge: duplicate tool result `"Chat ended before..."` on 0.4.0 and 0.5.0 | confirmed (re-run) | mock server wire log |
| 21 | "Single step impossible without extra user message" | confirmed with extra test (`$chat()` with no input aborts "`...` must contain at least one input.") | `alt_step.R` on both versions |
| 22 | Prototype 5.2(b) delegate bridge: ok/denied/budget statuses, `x_bridge = 55` in caller env | confirmed (re-run, both versions) | mock server |
| 23 | Deep clone keeps callbacks out of the user's Chat | confirmed (shallow clone leaks, deep does not); added callback-formals requirement | `clone_test.R` |
| 24 | Prototype 5.3 outputs; btw markdown table iff ≤10 cols and ≤30 rows | confirmed (timings vary: btw 3.75 s, df_schema 0.28 s, prototype 0.077 s) | re-run; `R/tool-env-df.R:136` |
| 25 | Prototype 5.4 (import btw ToolDefs, `_intent` optional) | confirmed | re-run |
| 26 | Prototype 5.5 schema size 31 tools = 46,235 chars | confirmed exactly | re-run |
| 27 | Report code blocks runnable as printed | corrected: `"<$T10>/rlib"` placeholders must be substituted; working dir must be `$T10` (note added) | extraction + run |
| 28 | btw default registry = 30 tools (list), `btw_tool_run_r` opt-in via option/env var/"run" group, `global_env()`, `check_path_within_current_wd` at `tool-files-read.R:338` | confirmed | `btw_tools()` run; source |
| 29 | btw skill locations | corrected (project `.agents/skills` also read) | `R/tool-skills.R:28`, `R/btw-config.R:53` |
| 30 | mcptools exports 3 functions; `mcp_server()` signature; config `~/.config/mcptools/config.json`; `claude mcp add` line; Windows Rscript path note | confirmed | mcptools 1.0.3 source |
| 31 | mcptools socket-dir order; "Windows named pipes/abstract transports (not verified)" | corrected: Linux order as stated; macOS `$TMPDIR/mcptools`; Windows named pipes, "not a security boundary" | `R/socket-dir.R`, `R/socket-auth.R` |
| 32 | Dependency closures (ellmer 25+self/16 compiled, D-20 set 16, curl set 5, btw 70, …) | confirmed; executive-summary "15" corrected to 16 | `package_dependencies()` on fresh db |
| 33 | btw Rust chain (frontmatter → tomledit, yaml12 SystemRequirements) | confirmed | fresh db |
| 34 | Load times ellmer 0.15 s vs httr2 0.12 s | confirmed as ratio; absolute values load dependent (re-run numbers added) | 3 fresh processes each |
| 35 | llm.api/tinyoauth Claude OAuth (Bearer + `anthropic-beta: oauth-2025-04-20`, auth/token/redirect URLs, scope) and Codex headers/device flow; token cache path | confirmed | `anthropic-claude.R:26-71`, `tinyoauth/R/anthropic.R:20-29`, `openai-codex.R:63, 236-243`, `openai_codex.R:24-30`, `cache.R` |
| 36 | llm.api `chat()`/`agent()` signatures, 3,554 lines | confirmed | source |
| 37 | ravel `codex exec` command line | corrected (`--model <m>` is appended after `-`) | `ravel/R/providers_openai.R:227-240` |
| 38 | corteza facts (roxygen quote, non-interactive refusal, max_turns 50, globalenv eval, handles, callr sub-agents, Windows bash) | confirmed; line numbers adjusted | corteza 0.7.1 source |
| 39 | corteza has no Pi session compatibility | corrected: corteza claims a pi-coding-agent/openclaw-style transcript (v2 header, flat messages, no tree); Pi is v3 | `corteza/R/session.R`; `pi/.../session-manager.ts:41` |
| 40 | agenticr tools list, `.GlobalEnv` eval; interceptor at `repl.R:1346` | tools/eval confirmed; interceptor location corrected (`agentic_enable()`, `repl.R:1278-1330`) | agenticr 0.3.3 source |
| 41 | aisdk `console_chat()`, `r_eval` via `callr::r_bg`, 215 exports, 42k lines, YuLab-SMU | confirmed | aisdk 1.4.12 source |
| 42 | tidyllm exports `claude/gemini/chatgpt/openai/ollama/groq/mistral/deepseek/ellmer`; vitals exports `codex`/`claude_code`; tidyllm ellmer-backend error text; tidyprompt `exists("UserTurn")` | confirmed | NAMESPACE / source |
| 43 | mcplite "re-exports" ellmer DSL | corrected to "re-implements" (ellmer only in Suggests) | mcplite DESCRIPTION/NAMESPACE |
| 44 | Local collision scan over 613 installed packages (plan, prompt, history, ask, extract, pick, session, config, setup, score, rank, mcp, classify) | confirmed | `Meta/nsInfo.rds` scan |
| 45 | r-universe: `decide` nimble[34], `classify` terra[1017]/admisc[85], `agent` villager/rmorie/LLMRagent, `gptr*` none; `opus/sonnet/gpt/auto/manual` owners | confirmed | r-universe search API |
| 46 | gptr `get_response()` signature | corrected (defaults for `user_input`, `system_specification`) | `gptr/R/get_response.R:27-31` |
| 47 | 3.5 "verbatim DESCRIPTION" | corrected to "abridged" | tarball DESCRIPTION |
| 48 | Anthropic legal-page quotes (third-party developers, credentials, unmodified binary) | confirmed verbatim | code.claude.com/docs/en/legal-and-compliance |
| 49 | CRAN policy quotes (global env, home filespace, interactive exception, `R_user_dir`, `:::`, fail gracefully, two cores, external software, significant disruption, "at least 2 weeks", persistent names, maintainer e-mail change, "1–2 months") | confirmed (13/13) | CRAN Repository Policy page |
| 50 | Posit Assistant: RStudio Apr 2026, Positron Jun 2026, terminal, superseded Positron Assistant and Databot, from $20/month, BYO key | confirmed | Posit blog 2026-06-11; posit.co/products/ai |
| 51 | side: "will not go to CRAN", built on btw/ellmer/shinychat | confirmed | github.com/simonpcouch/side |
| 52 | ClaudeR: port 8787, `uvx clauder-mcp`, 41 tools, MIT, GitHub only | confirmed | github.com/IMNMV/ClaudeR |
| 53 | btw_app chat history uses RSQLite | confirmed (RSQLite in Suggests; NEWS) | btw DESCRIPTION/NEWS |
| 54 | LLMR / rtemis.llm document that Anthropic returns no logprobs | confirmed as documentation only (LIKELY label kept) | roxygen lines cited |
| 55 | Executive-summary claim that the interrupt pitfalls are "verified below" | corrected (track-02 finding, not re-verified) | section 2.4 text |

Unverifiable here (left labelled or marked UNCERTAIN): track-02's httr2 interrupt findings;
which providers reject duplicate results for one `tool_call_id`; whether
`$stream(stream = "content")` gives enough events for delegate mode; GitHub usage of
`get_response()`; any Windows runtime behaviour; the upstream ellmer weekly price workflow
itself (only a code comment); OpenAI's policy on third-party ChatGPT-plan OAuth; whether
corteza's transcripts actually load in Pi.
